create table core.organization_administrator_logins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid not null references core.tenants(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9][a-z0-9._-]{2,47}$'),
  password_changed_at timestamptz not null default statement_timestamp(),
  must_change_password boolean not null default true,
  handover_requested_at timestamptz not null default statement_timestamp(),
  handover_sent_at timestamptz
);
create index organization_administrator_logins_tenant_idx
  on core.organization_administrator_logins (tenant_id);

create table core.organization_account_recovery (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  verified_at timestamptz,
  password_changed_at timestamptz,
  check (verified_at is null or email is not null)
);

create table core.organization_identity_challenges (
  user_id uuid not null references auth.users(id) on delete cascade,
  purpose text not null check (purpose in ('reset', 'verify')),
  email text not null,
  code_hash text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  issued_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts between 0 and 5),
  consumed boolean not null default false,
  primary key (user_id, purpose)
);

-- A fixed-size project-wide email limit complements the per-account cooldown.
create table core.organization_identity_limits (
  purpose text primary key check (purpose in ('reset', 'verify')),
  window_start timestamptz not null,
  sent_count integer not null check (sent_count between 1 and 120)
);

alter table core.organization_administrator_logins enable row level security;
alter table core.organization_account_recovery enable row level security;
alter table core.organization_identity_challenges enable row level security;
alter table core.organization_identity_limits enable row level security;
revoke all on core.organization_administrator_logins, core.organization_account_recovery,
  core.organization_identity_challenges, core.organization_identity_limits from public, anon, authenticated;

-- Public signup must not claim the internal username namespace, and a managed
-- administrator keeps their assigned sign-in alias when changing recovery email.
-- AdminCreate writes app metadata after inserting the row in the same transaction.
create function core.organization_protect_login_alias()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if right(lower(coalesce(new.email, '')), 21) = '@admin.jentra.invalid'
      and exists (select 1 from auth.users where id = new.id
        and raw_app_meta_data->>'managed_org_admin' is distinct from 'true') then
    raise exception using errcode = '42501', message = 'Managed login address is reserved.';
  end if;
  if tg_op = 'UPDATE' and old.raw_app_meta_data->>'managed_org_admin' = 'true'
      and new.email is distinct from old.email then
    raise exception using errcode = '42501', message = 'Managed login address cannot be changed.';
  end if;
  return new;
end;
$$;
create constraint trigger organization_protect_login_alias after insert or update of email on auth.users
deferrable initially deferred for each row execute function core.organization_protect_login_alias();

-- GoTrue owns the password hash. It updates the password and app metadata in
-- one transaction, with the metadata write following the password update.
create function core.organization_track_password_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    perform pg_advisory_xact_lock(hashtextextended(new.id::text, 34555));
    insert into core.organization_account_recovery (user_id, password_changed_at)
    values (new.id, statement_timestamp())
    on conflict (user_id) do update set password_changed_at = excluded.password_changed_at;
    update core.organization_administrator_logins
    set password_changed_at = statement_timestamp(), must_change_password = false
    where user_id = new.id;
    update core.organization_identity_challenges set consumed = true where user_id = new.id;
  end if;
  if new.raw_app_meta_data->>'jentra_handover_generation' is not null
      and new.raw_app_meta_data->>'jentra_handover_generation'
        is distinct from old.raw_app_meta_data->>'jentra_handover_generation' then
    update core.organization_administrator_logins
    set must_change_password = true, handover_sent_at = null
    where user_id = new.id;
  end if;
  return new;
end;
$$;
create trigger organization_track_password_change
after update of encrypted_password, raw_app_meta_data on auth.users
for each row execute function core.organization_track_password_change();

create function core.organization_identity_session_is_current(p_user_id uuid, p_changed_at timestamptz)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.sessions as s
    where s.id = (auth.jwt()->>'session_id')::uuid and s.user_id = p_user_id
      and (s.not_after is null or s.not_after > statement_timestamp())
      and (p_changed_at is null or s.created_at >= p_changed_at)
  );
$$;

create function core.organization_account_ready(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when auth.jwt()->'app_metadata'->>'managed_org_admin' = 'true'
    or exists (select 1 from core.organization_administrator_logins where user_id = p_user_id)
  then exists (
    select 1 from core.organization_administrator_logins as l
    where l.user_id = p_user_id and not l.must_change_password
      and core.organization_identity_session_is_current(p_user_id, l.password_changed_at)
  ) else not exists (
    select 1 from core.organization_account_recovery as r
    where r.user_id = p_user_id and r.password_changed_at is not null
      and not core.organization_identity_session_is_current(p_user_id, r.password_changed_at)
  ) end;
$$;

create or replace function core.is_tenant_member(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.organization_available(p_tenant_id)
    and core.organization_account_ready((select auth.uid()))
    and exists (
      select 1 from core.memberships as m
      where m.tenant_id = p_tenant_id and m.user_id = (select auth.uid()) and m.status = 'active'
    );
$$;

-- Password sign-in is sufficient for regular work and organization administration.
-- Keep the role requirement for privileged transaction permissions and scoped
-- custom roles. Explicit MFA guards in approval functions remain authoritative.
create function core.organization_role_permits(p_role_code text, p_requires_mfa boolean, p_permission text, p_privileged boolean)
returns boolean language sql stable set search_path = '' as $$
  select not p_requires_mfa
    or coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
    or (p_role_code = 'tenant_owner' and (not p_privileged or p_permission in (
      'core.tenant.manage', 'core.members.invite', 'core.roles.manage',
      'finance.view', 'people.view', 'control.view', 'audit.read'
    )));
$$;

create or replace function core.has_permission(
  p_tenant_id uuid, p_permission_code text,
  p_legal_entity_id uuid default null, p_branch_id uuid default null
)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.is_tenant_member(p_tenant_id) and exists (
    select 1 from core.memberships as m
    join core.role_assignments as a on (a.tenant_id, a.membership_id) = (m.tenant_id, m.id)
    join core.roles as r on (r.tenant_id, r.id) = (a.tenant_id, a.role_id)
    join core.role_permissions as rp on (rp.tenant_id, rp.role_id) = (r.tenant_id, r.id)
    join core.permissions as p on p.code = rp.permission_code
    where m.tenant_id = p_tenant_id and m.user_id = (select auth.uid()) and m.status = 'active'
      and p.code = p_permission_code
      and (a.legal_entity_id is null or a.legal_entity_id = p_legal_entity_id)
      and (a.branch_id is null or a.branch_id = p_branch_id)
      and core.organization_role_permits(r.code, r.requires_mfa, p.code, p.privileged)
  );
$$;

create or replace function core.list_capabilities(p_tenant_id uuid)
returns table (permission_code text) language sql stable security definer set search_path = '' as $$
  select distinct p.code from core.memberships as m
  join core.role_assignments as a on (a.tenant_id, a.membership_id) = (m.tenant_id, m.id)
  join core.roles as r on (r.tenant_id, r.id) = (a.tenant_id, a.role_id)
  join core.role_permissions as rp on (rp.tenant_id, rp.role_id) = (r.tenant_id, r.id)
  join core.permissions as p on p.code = rp.permission_code
  where m.tenant_id = p_tenant_id and m.user_id = (select auth.uid()) and m.status = 'active'
    and core.is_tenant_member(p_tenant_id)
    and core.organization_role_permits(r.code, r.requires_mfa, p.code, p.privileged)
  order by p.code;
$$;

-- A managed sign-in belongs to its assigned tenant. This guard also catches
-- alternate RPCs that could otherwise create or activate another membership.
create function core.organization_check_managed_membership()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from auth.users where id = new.user_id and raw_app_meta_data->>'managed_org_admin' = 'true')
    and not exists (select 1 from core.organization_administrator_logins
      where user_id = new.user_id and tenant_id = new.tenant_id) then
    raise exception using errcode = '42501', message = 'Managed account is assigned to one organization.';
  end if;
  return new;
end;
$$;
create trigger organization_check_managed_membership before insert or update of tenant_id, user_id on core.memberships
for each row execute function core.organization_check_managed_membership();

create function core.organization_is_administrator(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from core.memberships as m
    join core.role_assignments as a on (a.tenant_id, a.membership_id) = (m.tenant_id, m.id)
    join core.roles as r on (r.tenant_id, r.id) = (a.tenant_id, a.role_id)
    where m.user_id = p_user_id and m.status = 'active' and core.organization_available(m.tenant_id)
      and a.legal_entity_id is null and a.branch_id is null
      and r.is_system and r.code in ('tenant_owner', 'tenant_admin')
  );
$$;

create function api.organization_identity_profile()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_login core.organization_administrator_logins;
  v_recovery core.organization_account_recovery;
  v_pending text;
begin
  select * into v_login from core.organization_administrator_logins where user_id = v_user;
  select * into v_recovery from core.organization_account_recovery where user_id = v_user;
  if not core.organization_identity_session_is_current(v_user, v_recovery.password_changed_at) then
    raise exception using errcode = '42501', message = 'Current session required.';
  end if;
  select email into v_pending from core.organization_identity_challenges
    where user_id = v_user and purpose = 'verify' and not consumed and expires_at > statement_timestamp();
  return jsonb_build_object(
    'is_administrator', core.organization_is_administrator(v_user),
    'username', v_login.username,
    'recovery_email', case when v_recovery.verified_at is not null then v_recovery.email end,
    'pending_recovery_email', v_pending,
    'recovery_verified', v_recovery.verified_at is not null,
    'organization_locked', exists (select 1 from core.tenants
      where id = v_login.tenant_id and status = 'suspended'),
    'must_change_password', coalesce(v_login.must_change_password, false),
    'password_changed_at', coalesce(v_login.password_changed_at, v_recovery.password_changed_at)
  );
end;
$$;
revoke all on function api.organization_identity_profile() from public, anon, authenticated;
grant execute on function api.organization_identity_profile() to authenticated;

create function core.organization_issue_identity_challenge(p_user_id uuid, p_purpose text, p_email text, p_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := statement_timestamp();
  v_hour timestamptz := date_trunc('hour', v_now);
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 34555));
  if exists (select 1 from core.organization_identity_challenges
    where user_id = p_user_id and purpose = p_purpose and issued_at > v_now - interval '1 minute') then
    return false;
  end if;
  insert into core.organization_identity_limits as l (purpose, window_start, sent_count)
  values (p_purpose, v_hour, 1)
  on conflict (purpose) do update set window_start = excluded.window_start,
    sent_count = case when l.window_start = v_hour then l.sent_count + 1 else 1 end
    where l.window_start <> v_hour or l.sent_count < 120;
  if not found then return false; end if;
  insert into core.organization_identity_challenges (user_id, purpose, email, code_hash, issued_at, expires_at)
  values (p_user_id, p_purpose, p_email, p_hash, v_now, v_now + interval '10 minutes')
  on conflict (user_id, purpose) do update set email = excluded.email, code_hash = excluded.code_hash,
    issued_at = excluded.issued_at, expires_at = excluded.expires_at, attempts = 0, consumed = false;
  return true;
end;
$$;

create function core.organization_recovery_target(p_login_email text)
returns table (user_id uuid, email text) language sql stable security definer set search_path = '' as $$
  select u.id, r.email from auth.users as u
  join core.organization_account_recovery as r on r.user_id = u.id and r.verified_at is not null
  left join core.organization_administrator_logins as l on l.user_id = u.id
  where u.email = p_login_email and u.deleted_at is null and coalesce(u.encrypted_password, '') <> ''
    and (u.banned_until is null or u.banned_until <= statement_timestamp())
    and (u.raw_app_meta_data->>'managed_org_admin' is distinct from 'true'
      or (core.organization_available(l.tenant_id) and core.organization_is_administrator(u.id)));
$$;

create function api.organization_issue_reset(p_login_email text, p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_user uuid; v_email text;
begin
  select user_id, email into v_user, v_email from core.organization_recovery_target(p_login_email);
  if v_user is null then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 34555));
  select email into v_email from core.organization_recovery_target(p_login_email) where user_id = v_user;
  if v_email is null then return null; end if;
  if core.organization_issue_identity_challenge(v_user, 'reset', v_email, p_hash) then return v_email; end if;
  return null;
end;
$$;

create function api.organization_issue_recovery_verification(p_user_id uuid, p_email text, p_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_email is null or length(p_email) not between 5 and 254 or position('@' in p_email) < 2
      or right(p_email, 21) = '@admin.jentra.invalid' then
    raise exception using errcode = '22023', message = 'Invalid recovery address.';
  end if;
  return core.organization_issue_identity_challenge(p_user_id, 'verify', p_email, p_hash);
end;
$$;

create function core.organization_consume_identity_challenge(p_user_id uuid, p_purpose text, p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_challenge core.organization_identity_challenges;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 34555));
  select * into v_challenge from core.organization_identity_challenges
  where user_id = p_user_id and purpose = p_purpose and not consumed and attempts < 5
    and expires_at > statement_timestamp() for update;
  if not found then return null; end if;
  if p_hash is distinct from v_challenge.code_hash then
    update core.organization_identity_challenges set attempts = attempts + 1
    where user_id = p_user_id and purpose = p_purpose;
    return null;
  end if;
  update core.organization_identity_challenges set consumed = true
  where user_id = p_user_id and purpose = p_purpose;
  return v_challenge.email;
end;
$$;

create function api.organization_consume_reset(p_login_email text, p_hash text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid; v_email text;
begin
  select user_id, email into v_user, v_email from core.organization_recovery_target(p_login_email);
  if v_user is null then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 34555));
  select email into v_email from core.organization_recovery_target(p_login_email) where user_id = v_user;
  if v_email is null then return null; end if;
  if core.organization_consume_identity_challenge(v_user, 'reset', p_hash) = v_email then return v_user; end if;
  return null;
end;
$$;

create function api.organization_verify_recovery_email(p_user_id uuid, p_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_email text;
begin
  v_email := core.organization_consume_identity_challenge(p_user_id, 'verify', p_hash);
  if v_email is null then return false; end if;
  insert into core.organization_account_recovery (user_id, email, verified_at)
    values (p_user_id, v_email, statement_timestamp())
  on conflict (user_id) do update set email = excluded.email, verified_at = excluded.verified_at;
  update core.organization_identity_challenges set consumed = true where user_id = p_user_id and purpose = 'reset';
  return true;
end;
$$;

create function core.organization_provisioning_recipient(p_actor_id uuid, p_tenant_id uuid, p_signup_email text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_email text;
begin
  if not exists (select 1 from intelligence_control.operators
    where actor_id = p_actor_id and active and organization_manage) then
    raise exception using errcode = '42501', message = 'Platform organization operator required.';
  end if;
  select signup_email into v_email from billing.organization_activations where tenant_id = p_tenant_id;
  if v_email is null or not core.organization_available(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Confirmed activation required.';
  end if;
  if exists (select 1 from core.organization_administrator_logins where tenant_id = p_tenant_id) then
    v_email := coalesce(p_signup_email, v_email);
  elsif p_signup_email is distinct from v_email then
    raise exception using errcode = '22023', message = 'First administrator must use the activation email.';
  end if;
  if length(v_email) not between 5 and 254 or position('@' in v_email) < 2
      or right(v_email, 21) = '@admin.jentra.invalid' then
    raise exception using errcode = '22023', message = 'Invalid handover address.';
  end if;
  return v_email;
end;
$$;

create function api.organization_check_admin_provision(p_actor_id uuid, p_tenant_id uuid, p_signup_email text)
returns text language sql stable security definer set search_path = '' as $$
  select core.organization_provisioning_recipient(p_actor_id, p_tenant_id, p_signup_email);
$$;

-- An interrupted Edge invocation may leave only the Auth identity. An operator
-- can reclaim that same tenant's abandoned alias without touching existing users.
create function api.organization_abandoned_admin_identity(p_actor_id uuid, p_tenant_id uuid,
  p_signup_email text, p_username text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid;
begin
  perform core.organization_provisioning_recipient(p_actor_id, p_tenant_id, p_signup_email);
  select u.id into v_user from auth.users as u
  where u.email = p_username || '@admin.jentra.invalid'
    and u.raw_app_meta_data->>'managed_org_admin' = 'true'
    and u.raw_app_meta_data->>'provisioned_tenant_id' = p_tenant_id::text
    and u.created_at <= statement_timestamp() - interval '1 minute'
    and not exists (select 1 from core.organization_administrator_logins where user_id = u.id)
    and not exists (select 1 from core.memberships where user_id = u.id);
  return v_user;
end;
$$;

create function api.organization_register_admin(p_actor_id uuid, p_tenant_id uuid, p_user_id uuid,
  p_username text, p_signup_email text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare v_email text; v_role uuid; v_member uuid; v_changed timestamptz;
begin
  perform 1 from core.tenants where id = p_tenant_id for update;
  v_email := core.organization_provisioning_recipient(p_actor_id, p_tenant_id, p_signup_email);
  if not exists (select 1 from auth.users where id = p_user_id
    and email = p_username || '@admin.jentra.invalid' and raw_app_meta_data->>'managed_org_admin' = 'true'
    and raw_app_meta_data->>'provisioned_tenant_id' = p_tenant_id::text) then
    raise exception using errcode = '42501', message = 'Provisioned identity required.';
  end if;
  select id into v_role from core.roles where tenant_id = p_tenant_id and code = 'tenant_owner' and is_system;
  if v_role is null then raise exception using errcode = '22023', message = 'Administrator role unavailable.'; end if;
  insert into core.organization_administrator_logins (user_id, tenant_id, username)
    values (p_user_id, p_tenant_id, p_username) returning password_changed_at into v_changed;
  insert into core.organization_account_recovery (user_id, email, password_changed_at)
    values (p_user_id, v_email, v_changed);
  insert into core.memberships (tenant_id, user_id, invited_by, joined_at)
    values (p_tenant_id, p_user_id, p_actor_id, statement_timestamp()) returning id into v_member;
  insert into core.role_assignments (tenant_id, membership_id, role_id, created_by)
    values (p_tenant_id, v_member, v_role, p_actor_id);
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (p_tenant_id, p_actor_id, gen_random_uuid(), 'organization.administrator_created', 'membership', v_member);
  return v_changed;
end;
$$;

create function api.organization_admin_reissue_target(p_actor_id uuid, p_tenant_id uuid, p_username text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if not exists (select 1 from intelligence_control.operators
    where actor_id = p_actor_id and active and organization_manage) then
    raise exception using errcode = '42501', message = 'Platform organization operator required.';
  end if;
  update core.organization_administrator_logins as l set handover_requested_at = statement_timestamp()
  from core.organization_account_recovery as r
  where l.tenant_id = p_tenant_id and l.username = p_username and core.organization_available(l.tenant_id)
    and l.user_id = r.user_id and core.organization_is_administrator(l.user_id)
    and (r.verified_at is not null or l.handover_sent_at is null)
    and l.handover_requested_at <= statement_timestamp() - interval '1 minute'
  returning jsonb_build_object('user_id', l.user_id, 'email', r.email) into v_result;
  return v_result;
end;
$$;

create function api.organization_finish_admin_handover(p_actor_id uuid, p_user_id uuid, p_email text,
  p_initial_changed_at timestamptz, p_generation text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 34555));
  if not exists (select 1 from core.organization_account_recovery
    where user_id = p_user_id and email = p_email) then return false; end if;
  update core.organization_administrator_logins as l set handover_sent_at = statement_timestamp()
    from auth.users as u
    where l.user_id = p_user_id and u.id = l.user_id and l.must_change_password
      and ((p_generation is null and l.password_changed_at = p_initial_changed_at)
        or (p_generation is not null and u.raw_app_meta_data->>'jentra_handover_generation' = p_generation))
    returning l.tenant_id into v_tenant;
  if not found then return false; end if;
  update core.organization_account_recovery set verified_at = coalesce(verified_at, statement_timestamp())
    where user_id = p_user_id and email = p_email;
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (v_tenant, p_actor_id, gen_random_uuid(), 'organization.administrator_handover', 'administrator', p_user_id);
  return true;
end;
$$;

revoke all on function core.organization_protect_login_alias(), core.organization_track_password_change(),
  core.organization_identity_session_is_current(uuid,timestamptz), core.organization_account_ready(uuid),
  core.organization_role_permits(text,boolean,text,boolean), core.organization_check_managed_membership(),
  core.organization_is_administrator(uuid), core.organization_issue_identity_challenge(uuid,text,text,text),
  core.organization_recovery_target(text), core.organization_consume_identity_challenge(uuid,text,text),
  core.organization_provisioning_recipient(uuid,uuid,text) from public, anon, authenticated;

revoke all on function api.organization_issue_reset(text,text),
  api.organization_issue_recovery_verification(uuid,text,text), api.organization_consume_reset(text,text),
  api.organization_verify_recovery_email(uuid,text), api.organization_check_admin_provision(uuid,uuid,text),
  api.organization_abandoned_admin_identity(uuid,uuid,text,text),
  api.organization_register_admin(uuid,uuid,uuid,text,text), api.organization_admin_reissue_target(uuid,uuid,text),
  api.organization_finish_admin_handover(uuid,uuid,text,timestamptz,text) from public, anon, authenticated;
grant execute on function api.organization_issue_reset(text,text),
  api.organization_issue_recovery_verification(uuid,text,text), api.organization_consume_reset(text,text),
  api.organization_verify_recovery_email(uuid,text), api.organization_check_admin_provision(uuid,uuid,text),
  api.organization_abandoned_admin_identity(uuid,uuid,text,text),
  api.organization_register_admin(uuid,uuid,uuid,text,text), api.organization_admin_reissue_target(uuid,uuid,text),
  api.organization_finish_admin_handover(uuid,uuid,text,timestamptz,text) to service_role;
