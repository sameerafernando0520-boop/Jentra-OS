alter table core.organization_identity_challenges
  drop constraint organization_identity_challenges_purpose_check,
  add check (purpose in ('reset', 'verify', 'purchase', 'operator_reset', 'operator_verify'));
alter table core.organization_identity_limits
  drop constraint organization_identity_limits_purpose_check,
  add check (purpose in ('reset', 'verify', 'purchase', 'operator_reset', 'operator_verify'));

create table intelligence_control.operator_recovery_addresses (
  actor_id uuid primary key references intelligence_control.operators(actor_id) on delete cascade,
  email text not null check (length(email) <= 254),
  verified_at timestamptz not null default statement_timestamp()
);
create table intelligence_control.operator_password_grants (
  actor_id uuid primary key references intelligence_control.operators(actor_id) on delete cascade,
  token uuid not null,
  previous_hash_fingerprint bytea,
  expires_at timestamptz not null
);
alter table intelligence_control.operator_recovery_addresses enable row level security;
alter table intelligence_control.operator_password_grants enable row level security;
revoke all on intelligence_control.operator_recovery_addresses, intelligence_control.operator_password_grants
  from public, anon, authenticated, service_role;

create or replace function intelligence_control.operator_required(cap text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2'
      or (cap = 'organization' and not core.organization_account_ready(auth.uid()))
      or not exists (
    select 1 from intelligence_control.operators
    where actor_id = auth.uid() and active
      and case cap
        when 'health' then health_read
        when 'grant' then grant_manage
        when 'organization' then organization_manage
        else false
      end
  ) then
    raise exception using errcode = '42501', message = 'OPERATOR_ACCESS_REQUIRED';
  end if;
end;
$$;

create or replace function api.platform_organization_access()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
    and api.platform_organization_assignment()
    and core.organization_account_ready(auth.uid());
$$;

create function intelligence_control.operator_login_identity(p_actor_id uuid)
returns auth.users language sql stable security definer set search_path = '' as $$
  select u.* from auth.users u
  join intelligence_control.operators o on o.actor_id = u.id and o.active and o.organization_manage
  where u.id = p_actor_id and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= statement_timestamp())
    and not u.is_sso_user
    and u.email is not null and right(lower(u.email), 21) <> '@admin.jentra.invalid'
    and u.raw_app_meta_data->>'managed_org_admin' is distinct from 'true';
$$;

create function api.platform_operator_identity_profile()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_user auth.users;
  v_recovery intelligence_control.operator_recovery_addresses;
  v_pending text;
  v_changed timestamptz;
begin
  perform intelligence_control.operator_required('organization');
  v_user := intelligence_control.operator_login_identity(auth.uid());
  if v_user.id is null then raise exception using errcode = '42501', message = 'OPERATOR_ACCESS_REQUIRED'; end if;
  select * into v_recovery from intelligence_control.operator_recovery_addresses where actor_id = v_user.id;
  select email into v_pending from core.organization_identity_challenges
    where user_id = v_user.id and purpose = 'operator_verify' and not consumed
      and expires_at > statement_timestamp() and email <> lower(v_user.email);
  select password_changed_at into v_changed from core.organization_account_recovery where user_id = v_user.id;
  return jsonb_build_object(
    'email', lower(v_user.email), 'has_password', coalesce(v_user.encrypted_password, '') <> '',
    'recovery_email', case when v_recovery.email <> lower(v_user.email) then v_recovery.email end,
    'pending_recovery_email', v_pending,
    'recovery_verified', coalesce(v_recovery.email <> lower(v_user.email), false),
    'password_changed_at', v_changed
  );
end;
$$;

create function intelligence_control.operator_current_identity(p_actor_id uuid, p_password_changed_at timestamptz)
returns auth.users language plpgsql security definer set search_path = '' as $$
declare v_user auth.users; v_changed timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_actor_id::text, 34555));
  v_user := intelligence_control.operator_login_identity(p_actor_id);
  select password_changed_at into v_changed from core.organization_account_recovery where user_id = p_actor_id;
  if v_user.id is null or v_changed is distinct from p_password_changed_at then
    raise exception using errcode = '42501', message = 'OPERATOR_ACCESS_REQUIRED';
  end if;
  return v_user;
end;
$$;

create function api.platform_operator_issue_recovery_verification(
  p_actor_id uuid, p_password_changed_at timestamptz, p_email text, p_hash text
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_user auth.users;
begin
  v_user := intelligence_control.operator_current_identity(p_actor_id, p_password_changed_at);
  if coalesce(v_user.encrypted_password, '') = '' then
    raise exception using errcode = '42501', message = 'OPERATOR_ACCESS_REQUIRED';
  end if;
  if p_email is null or length(p_email) > 254 or p_email <> lower(p_email)
      or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      or right(p_email, 21) = '@admin.jentra.invalid' or p_email = lower(v_user.email) then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_RECOVERY_EMAIL';
  end if;
  return core.organization_issue_identity_challenge(v_user.id, 'operator_verify', p_email, p_hash);
end;
$$;

create function api.platform_operator_verify_recovery_email(p_actor_id uuid, p_password_changed_at timestamptz, p_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_user auth.users; v_email text;
begin
  v_user := intelligence_control.operator_current_identity(p_actor_id, p_password_changed_at);
  v_email := core.organization_consume_identity_challenge(v_user.id, 'operator_verify', p_hash);
  if v_email is null or v_email = lower(v_user.email) then return false; end if;
  insert into intelligence_control.operator_recovery_addresses (actor_id, email)
    values (v_user.id, v_email) on conflict (actor_id) do update
      set email = excluded.email, verified_at = excluded.verified_at;
  update core.organization_identity_challenges set consumed = true
    where user_id = v_user.id and purpose = 'operator_reset';
  delete from intelligence_control.operator_password_grants where actor_id = v_user.id;
  return true;
end;
$$;

create function intelligence_control.operator_grant_password(p_user auth.users)
returns uuid language sql security definer set search_path = '' as $$
  insert into intelligence_control.operator_password_grants (actor_id, token, previous_hash_fingerprint, expires_at)
  values (p_user.id, gen_random_uuid(), extensions.digest(p_user.encrypted_password, 'sha256'),
    statement_timestamp() + interval '2 minutes')
  on conflict (actor_id) do update set token = excluded.token,
    previous_hash_fingerprint = excluded.previous_hash_fingerprint, expires_at = excluded.expires_at
  returning token;
$$;

create function api.platform_operator_prepare_password(p_actor_id uuid, p_set_password boolean, p_password_changed_at timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user auth.users;
begin
  v_user := intelligence_control.operator_current_identity(p_actor_id, p_password_changed_at);
  if p_set_password is distinct from (coalesce(v_user.encrypted_password, '') = '') then
    raise exception using errcode = '42501', message = 'OPERATOR_PASSWORD_STATE_CHANGED';
  end if;
  return intelligence_control.operator_grant_password(v_user);
end;
$$;

create function intelligence_control.operator_reset_target(p_login_email text)
returns table (user_id uuid, email text) language sql stable security definer set search_path = '' as $$
  select u.id, r.email from auth.users u
  join intelligence_control.operators o on o.actor_id = u.id and o.active and o.organization_manage
  join intelligence_control.operator_recovery_addresses r on r.actor_id = u.id
  where lower(u.email) = p_login_email and r.email <> p_login_email
    and u.deleted_at is null and not u.is_sso_user and coalesce(u.encrypted_password, '') <> ''
    and (u.banned_until is null or u.banned_until <= statement_timestamp())
    and right(lower(u.email), 21) <> '@admin.jentra.invalid'
    and u.raw_app_meta_data->>'managed_org_admin' is distinct from 'true';
$$;

create function api.platform_operator_issue_reset(p_login_email text, p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_user uuid; v_email text;
begin
  select user_id into v_user from intelligence_control.operator_reset_target(p_login_email);
  if v_user is null then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 34555));
  select email into v_email from intelligence_control.operator_reset_target(p_login_email) where user_id = v_user;
  if v_email is not null and core.organization_issue_identity_challenge(v_user, 'operator_reset', v_email, p_hash) then
    return v_email;
  end if;
  return null;
end;
$$;

create function api.platform_operator_consume_reset(p_login_email text, p_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user auth.users; v_id uuid; v_email text;
begin
  select user_id into v_id from intelligence_control.operator_reset_target(p_login_email);
  if v_id is null then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 34555));
  select email into v_email from intelligence_control.operator_reset_target(p_login_email) where user_id = v_id;
  if v_email is null or core.organization_consume_identity_challenge(v_id, 'operator_reset', p_hash)
      is distinct from v_email then return null; end if;
  v_user := intelligence_control.operator_login_identity(v_id);
  if v_user.id is null then return null; end if;
  return jsonb_build_object('user_id', v_id, 'token', intelligence_control.operator_grant_password(v_user));
end;
$$;

-- GoTrue may write the hash before app metadata in the same transaction.
-- Fence Edge-issued password updates to the credential that was authorized.
create function intelligence_control.check_operator_password_grant()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_token text;
begin
  if new.encrypted_password is not distinct from old.encrypted_password then return new; end if;
  select raw_app_meta_data->>'jentra_operator_password_token' into v_token from auth.users where id = new.id;
  if v_token is not distinct from old.raw_app_meta_data->>'jentra_operator_password_token' then return new; end if;
  delete from intelligence_control.operator_password_grants
  where actor_id = new.id and token::text = v_token and expires_at > clock_timestamp()
    and previous_hash_fingerprint is not distinct from extensions.digest(old.encrypted_password, 'sha256')
    and exists (select 1 from intelligence_control.operators
      where actor_id = new.id and active and organization_manage);
  if not found then raise exception using errcode = '42501', message = 'OPERATOR_PASSWORD_STATE_CHANGED'; end if;
  return new;
end;
$$;
create constraint trigger platform_operator_password_grant
after update of encrypted_password on auth.users
deferrable initially deferred for each row execute function intelligence_control.check_operator_password_grant();

-- A platform assignment uses its own recovery authority, even if the account
-- has a tenant role or an older workspace recovery address.
create or replace function core.organization_recovery_target(p_login_email text)
returns table (user_id uuid, email text) language sql stable security definer set search_path = '' as $$
  select u.id, r.email from auth.users u
  join core.organization_account_recovery r on r.user_id = u.id and r.verified_at is not null
  left join core.organization_administrator_logins l on l.user_id = u.id
  where u.email = p_login_email and u.deleted_at is null and coalesce(u.encrypted_password, '') <> ''
    and (u.banned_until is null or u.banned_until <= statement_timestamp())
    and not exists (select 1 from intelligence_control.operators o where o.actor_id = u.id and o.organization_manage)
    and (u.raw_app_meta_data->>'managed_org_admin' is distinct from 'true'
      or (core.organization_available(l.tenant_id) and exists (
        select 1 from core.memberships m
        where (m.tenant_id, m.user_id) = (l.tenant_id, l.user_id) and m.status = 'active'
      )));
$$;

revoke all on function intelligence_control.operator_login_identity(uuid),
  intelligence_control.operator_current_identity(uuid,timestamptz),
  intelligence_control.operator_reset_target(text), intelligence_control.operator_grant_password(auth.users),
  intelligence_control.check_operator_password_grant(),
  api.platform_operator_identity_profile(),
  api.platform_operator_issue_recovery_verification(uuid,timestamptz,text,text),
  api.platform_operator_verify_recovery_email(uuid,timestamptz,text),
  api.platform_operator_prepare_password(uuid,boolean,timestamptz),
  api.platform_operator_issue_reset(text,text), api.platform_operator_consume_reset(text,text)
  from public, anon, authenticated, service_role;

grant execute on function api.platform_operator_identity_profile() to authenticated;
grant execute on function api.platform_operator_issue_recovery_verification(uuid,timestamptz,text,text),
  api.platform_operator_verify_recovery_email(uuid,timestamptz,text),
  api.platform_operator_prepare_password(uuid,boolean,timestamptz),
  api.platform_operator_issue_reset(text,text), api.platform_operator_consume_reset(text,text)
  to service_role;
