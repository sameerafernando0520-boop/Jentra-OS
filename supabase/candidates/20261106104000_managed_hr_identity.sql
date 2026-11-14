insert into core.permissions (code, module, description, privileged)
values ('people.employee_credentials.manage', 'people', 'Issue and revoke scoped Employee app access.', true)
on conflict (code) do nothing;

insert into core.role_permissions(tenant_id,role_id,permission_code)
select tenant_id,id,'people.employee_credentials.manage' from core.roles
where code = 'tenant_owner' and is_system
on conflict do nothing;

create table people_private.managed_staff_identities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  kind text not null check (kind in ('hr_manager','employee')),
  username text not null unique check (username ~ '^[a-z0-9][a-z0-9._-]{2,47}$'),
  display_name text not null check (length(display_name) between 1 and 160),
  legal_entity_ids uuid[] not null default '{}',
  legal_entity_id uuid,
  branch_id uuid,
  employee_id uuid,
  employee_number text,
  created_by uuid not null references auth.users(id),
  request_id uuid not null,
  delivery text not null check (delivery in ('email','reveal')),
  email text,
  mailbox_verified_at timestamptz,
  mailbox_code_hash text,
  mailbox_code_expires_at timestamptz,
  mailbox_attempts integer not null default 0,
  mailbox_sent_at timestamptz,
  status text not null check (status in ('verification_required','prepared','processing','issued','ready','active','failed','revoked')),
  generation uuid,
  lease_token uuid,
  lease_until timestamptz,
  expires_at timestamptz,
  user_id uuid unique references auth.users(id) on delete set null,
  membership_id uuid,
  link_id uuid,
  migration_id uuid,
  supersedes_membership_id uuid,
  supersedes_link_id uuid,
  legacy_membership_revoked boolean not null default false,
  legacy_grants jsonb not null default '[]',
  password_ready_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  unique (created_by, request_id),
  foreign key (tenant_id, legal_entity_id, employee_id) references people.employees(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, branch_id) references core.branches(tenant_id, legal_entity_id, id),
  check ((delivery = 'email') = (email is not null)),
  check ((kind = 'employee' and legal_entity_id is not null and branch_id is not null
      and employee_id is not null and employee_number is not null and cardinality(legal_entity_ids) = 0)
    or (kind = 'hr_manager' and legal_entity_id is null and branch_id is null and employee_id is null
      and employee_number is null and cardinality(legal_entity_ids) > 0)),
  check (migration_id is not null or (supersedes_membership_id is null and supersedes_link_id is null))
);
create unique index managed_staff_employee_current
  on people_private.managed_staff_identities(tenant_id, employee_id)
  where kind = 'employee' and status <> 'revoked';
create index managed_staff_tenant_idx on people_private.managed_staff_identities(tenant_id);
create index managed_staff_migration_idx on people_private.managed_staff_identities(migration_id) where migration_id is not null;
create unique index managed_staff_replacement_idx on people_private.managed_staff_identities
  (migration_id,kind,supersedes_membership_id,supersedes_link_id) nulls not distinct
  where migration_id is not null and status <> 'revoked';
alter table people_private.managed_staff_identities enable row level security;
revoke all on people_private.managed_staff_identities from public, anon, authenticated, service_role;

create table people_private.managed_staff_password_grants (
  user_id uuid primary key references auth.users(id) on delete cascade,
  token uuid not null,
  generation uuid not null,
  expires_at timestamptz not null
);
alter table people_private.managed_staff_password_grants enable row level security;
revoke all on people_private.managed_staff_password_grants from public, anon, authenticated, service_role;

create function people_private.managed_staff_hr_plan(p_tenant_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select core.organization_business_available(p_tenant_id) and exists (
    select 1 from billing.tenant_subscriptions s join billing.plan_entitlements e on e.plan_code = s.plan_code
    where s.tenant_id = p_tenant_id and e.entitlement_code = 'module.people' and e.enabled
      and ((s.status = 'active' and (s.current_period_ends_at is null or s.current_period_ends_at > now()))
        or (s.status = 'trialing' and s.trial_ends_at > now()))
  );
$$;

create function people_private.managed_employee_is_current(p_tenant_id uuid, p_entity_id uuid, p_branch_id uuid, p_employee_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from people.employment_assignments a
    join people.employment_spells s on (s.tenant_id, s.legal_entity_id, s.id, s.employee_id) =
      (a.tenant_id, a.legal_entity_id, a.spell_id, a.employee_id)
    join core.legal_entities e on (e.tenant_id, e.id) = (a.tenant_id, a.legal_entity_id) and e.status = 'active'
    join core.branches b on (b.tenant_id, b.legal_entity_id, b.id) = (a.tenant_id, a.legal_entity_id, a.branch_id)
      and b.status = 'active'
    cross join lateral (select (statement_timestamp() at time zone b.timezone)::date as work_date) d
    where (a.tenant_id, a.legal_entity_id, a.branch_id, a.employee_id) =
      (p_tenant_id, p_entity_id, p_branch_id, p_employee_id)
      and daterange(a.start_date, a.end_date_exclusive, '[)') @> d.work_date
      and daterange(s.start_date, s.end_date_exclusive, '[)') @> d.work_date
  );
$$;

create function people_private.managed_staff_eligible(s people_private.managed_staff_identities)
returns boolean language sql stable set search_path = '' as $$
  select people_private.managed_staff_hr_plan(s.tenant_id)
    and (s.kind = 'hr_manager' or people_private.managed_employee_is_current(
      s.tenant_id, s.legal_entity_id, s.branch_id, s.employee_id
    ));
$$;

create function people_private.managed_staff_can_manage(
  p_tenant_id uuid, p_kind text, p_legal_entity_id uuid, p_branch_id uuid, p_migration_id uuid
)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
    and people_private.managed_staff_hr_plan(p_tenant_id)
    and case when p_migration_id is not null then api.platform_organization_access()
      when p_kind = 'hr_manager' then core.is_tenant_member(p_tenant_id)
        and exists (
          select 1 from core.memberships m
          join core.role_assignments a on (a.tenant_id,a.membership_id) = (m.tenant_id,m.id)
          join core.roles r on (r.tenant_id,r.id) = (a.tenant_id,a.role_id)
          where m.tenant_id = p_tenant_id and m.user_id = auth.uid() and m.status = 'active'
            and r.code = 'tenant_owner' and r.is_system
            and a.legal_entity_id is null and a.branch_id is null
        )
      when p_kind = 'employee' then core.has_permission(p_tenant_id, 'people.employee_credentials.manage',
        p_legal_entity_id, p_branch_id)
      else false end;
$$;

create function people_private.managed_staff_projection(s people_private.managed_staff_identities)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'identity_id', s.id, 'tenant_id', s.tenant_id, 'kind', s.kind, 'username', s.username,
    'name', s.display_name, 'legal_entity_ids', to_jsonb(s.legal_entity_ids),
    'legal_entity_id', s.legal_entity_id, 'branch_id', s.branch_id, 'employee_id', s.employee_id,
    'employee_number', s.employee_number, 'delivery', s.delivery, 'recovery_verified', s.mailbox_verified_at is not null,
    'status', case when s.status = 'issued' and s.expires_at <= statement_timestamp() then 'expired' else s.status end,
    'expires_at', s.expires_at, 'migration_id', s.migration_id, 'password_ready_at', s.password_ready_at
  );
$$;

create function people_private.managed_staff_username(
  p_kind text, p_name text, p_username text, p_employee_number text, p_serial text, p_employee_id uuid
)
returns text language plpgsql set search_path = '' as $$
declare
  v_suffix text;
  v_base text;
  v_candidate text;
  v_limit integer;
  v_try integer;
begin
  if p_serial is null then raise exception using errcode = '22023', message = 'SYSTEM_SERIAL_REQUIRED'; end if;
  v_suffix := case when p_kind = 'employee' then '-' || lower(p_employee_number) else '' end
    || '-' || lower(p_serial);
  v_limit := 48 - length(v_suffix);
  if v_limit < 4 then raise exception using errcode = '22023', message = 'INVALID_STAFF_LOGIN_SCOPE'; end if;
  if p_username is not null then
    if p_username !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
      or length(p_username) + (case when p_kind = 'hr_manager' then 3 else 0 end) > v_limit then
      raise exception using errcode = '22023', message = 'INVALID_STAFF_USERNAME_NAME';
    end if;
    v_base := p_username;
  else
    v_base := trim(both '-' from regexp_replace(
      lower(regexp_replace(normalize(trim(p_name), NFKD), U&'[\0300-\036F]', '', 'g')),
      '[^a-z0-9]+', '-', 'g'));
    if v_base = '' then
      v_base := (case when p_kind = 'employee' then 'employee-' else 'staff-' end)
        || left(md5(normalize(trim(p_name), NFKC)), 6);
    end if;
  end if;
  if p_kind = 'hr_manager' then v_base := 'hr-' || v_base; end if;
  v_base := trim(trailing '-' from left(v_base,v_limit));
  for v_try in 0..12 loop
    if v_try = 0 then v_candidate := v_base || v_suffix;
    else
      v_candidate := trim(both '-' from left(v_base, v_limit - 3))
        || left(md5(p_employee_id::text || ':' || v_try::text), 3) || v_suffix;
    end if;
    perform pg_advisory_xact_lock(hashtextextended(v_candidate, 45109));
    if not exists (select 1 from auth.users where email = v_candidate || '@admin.jentra.invalid')
      and not exists (select 1 from core.organization_administrator_logins where username = v_candidate)
      and not exists (select 1 from billing.subscription_checkout_orders where username = v_candidate)
      and not exists (select 1 from billing.system_owner_handover_targets where username = v_candidate)
      and not exists (select 1 from people_private.managed_staff_identities where username = v_candidate)
    then return v_candidate; end if;
  end loop;
  raise exception using errcode = '23505', message = 'STAFF_USERNAME_UNAVAILABLE';
end;
$$;

create function api.prepare_managed_staff_identity(
  p_tenant_id uuid, p_kind text, p_request_id uuid, p_delivery text,
  p_username text default null, p_name text default null, p_email text default null,
  p_legal_entity_ids uuid[] default '{}', p_legal_entity_id uuid default null, p_branch_id uuid default null,
  p_employee_id uuid default null, p_migration_id uuid default null,
  p_supersedes_membership_id uuid default null, p_supersedes_link_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_staff people_private.managed_staff_identities;
  v_employee people.employees;
  v_serial text;
  v_name text := btrim(p_name);
  v_email text := lower(btrim(p_email));
  v_username text;
  v_entities uuid[] := coalesce(p_legal_entity_ids, '{}');
begin
  if not people_private.managed_staff_can_manage(p_tenant_id, p_kind, p_legal_entity_id, p_branch_id, p_migration_id) then
    raise exception using errcode = '42501', message = 'STAFF_PROVISION_FORBIDDEN';
  end if;
  if p_migration_id is not null and not api.platform_system_cutover_stage_target(
    p_migration_id, p_supersedes_membership_id, p_supersedes_link_id, p_kind
  ) then raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_TARGET_INVALID'; end if;
  if p_request_id is null or p_delivery is null or p_delivery not in ('email','reveal')
    or (p_migration_id is null and (p_supersedes_membership_id is not null or p_supersedes_link_id is not null))
    or (p_delivery = 'email' and (v_email is null or length(v_email) > 254
      or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      or right(v_email, 21) = '@admin.jentra.invalid'))
    or (p_delivery = 'reveal' and v_email is not null)
  then raise exception using errcode = '22023', message = 'STAFF_PROVISION_INVALID'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_actor::text || ':' || p_request_id::text, 45131));
  select * into v_staff from people_private.managed_staff_identities where created_by = v_actor and request_id = p_request_id;
  if found then
    if v_staff.tenant_id is distinct from p_tenant_id or v_staff.kind is distinct from p_kind
      or v_staff.employee_id is distinct from p_employee_id or v_staff.legal_entity_id is distinct from p_legal_entity_id
      or v_staff.branch_id is distinct from p_branch_id or v_staff.legal_entity_ids is distinct from v_entities
      or v_staff.migration_id is distinct from p_migration_id or v_staff.delivery is distinct from p_delivery
      or v_staff.email is distinct from v_email or v_staff.supersedes_membership_id is distinct from p_supersedes_membership_id
      or v_staff.supersedes_link_id is distinct from p_supersedes_link_id
    then raise exception using errcode = '22023', message = 'STAFF_REQUEST_MISMATCH'; end if;
    return people_private.managed_staff_projection(v_staff);
  end if;

  if p_kind = 'employee' then
    if cardinality(v_entities) <> 0 or not people_private.managed_employee_is_current(
      p_tenant_id, p_legal_entity_id, p_branch_id, p_employee_id
    ) then raise exception using errcode = '42501', message = 'STAFF_EMPLOYMENT_SCOPE_DENIED'; end if;
    select * into strict v_employee from people.employees
      where (tenant_id, legal_entity_id, id) = (p_tenant_id, p_legal_entity_id, p_employee_id);
    v_name := v_employee.display_name;
    if exists (select 1 from people_private.account_links l where l.tenant_id = p_tenant_id
        and l.employee_id = p_employee_id and l.status in ('pending','accepted')
        and l.id is distinct from p_supersedes_link_id) then
      raise exception using errcode = '23505', message = 'EMPLOYEE_ALREADY_LINKED';
    end if;
  elsif p_kind = 'hr_manager' then
    if p_employee_id is not null or p_legal_entity_id is not null or p_branch_id is not null
      or v_name is null or length(v_name) not between 1 and 160 or v_name ~ '[[:cntrl:]]'
      or cardinality(v_entities) not between 1 and 40 or array_ndims(v_entities) <> 1
      or (select count(*) from core.legal_entities e where e.tenant_id = p_tenant_id
        and e.status = 'active' and e.id = any(v_entities)) <> cardinality(v_entities) then
      raise exception using errcode = '22023', message = 'INVALID_HR_ENTITY_SCOPE';
    end if;
  else raise exception using errcode = '22023', message = 'STAFF_PROVISION_INVALID'; end if;

  if p_migration_id is not null and not exists (select 1 from core.memberships m
      where m.tenant_id = p_tenant_id and m.id = p_supersedes_membership_id and m.status = 'active') then
    raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_TARGET_INVALID';
  end if;
  if p_supersedes_link_id is not null and not exists (select 1 from people_private.account_links l
    where (l.id, l.tenant_id, l.legal_entity_id, l.branch_id, l.employee_id, l.membership_id) =
      (p_supersedes_link_id, p_tenant_id, p_legal_entity_id, p_branch_id, p_employee_id, p_supersedes_membership_id)
      and l.status = 'accepted') then
    raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_TARGET_INVALID';
  end if;

  select system_serial into v_serial from core.tenants where id = p_tenant_id;
  v_username := people_private.managed_staff_username(
    p_kind, v_name, p_username, v_employee.code, v_serial, coalesce(p_employee_id,p_request_id)
  );
  insert into people_private.managed_staff_identities (
    tenant_id, kind, username, display_name, legal_entity_ids, legal_entity_id, branch_id, employee_id,
    employee_number, created_by, request_id, delivery, email, status, migration_id,
    supersedes_membership_id, supersedes_link_id
  ) values (
    p_tenant_id, p_kind, v_username, v_name, v_entities, p_legal_entity_id, p_branch_id, p_employee_id,
    v_employee.code, v_actor, p_request_id, p_delivery, v_email,
    case when p_delivery = 'email' then 'verification_required' else 'prepared' end, p_migration_id,
    p_supersedes_membership_id, p_supersedes_link_id
  ) returning * into v_staff;
  return people_private.managed_staff_projection(v_staff);
end;
$$;


alter table people_private.managed_staff_identities add column reissue_request_id uuid;

create function api.managed_staff_credentials(
  p_tenant_id uuid, p_legal_entity_id uuid default null, p_employee_id uuid default null,
  p_migration_id uuid default null
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(people_private.managed_staff_projection(s) order by s.display_name, s.id), '[]')
  from (
    select s.* from people_private.managed_staff_identities s
    where s.tenant_id = p_tenant_id and s.migration_id is not distinct from p_migration_id
      and (p_legal_entity_id is null or s.legal_entity_id = p_legal_entity_id)
      and (p_employee_id is null or s.employee_id = p_employee_id)
      and people_private.managed_staff_can_manage(s.tenant_id, s.kind, s.legal_entity_id, s.branch_id, s.migration_id)
    order by s.created_at desc, s.id limit 100
  ) s;
$$;

create function api.request_managed_staff_reissue(p_identity_id uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities;
begin
  select * into s from people_private.managed_staff_identities where id = p_identity_id for update;
  if not found or not people_private.managed_staff_can_manage(s.tenant_id, s.kind, s.legal_entity_id, s.branch_id, s.migration_id) then
    raise exception using errcode = '42501', message = 'STAFF_PROVISION_FORBIDDEN';
  end if;
  if p_request_id is null then raise exception using errcode = '22023', message = 'STAFF_PROVISION_INVALID'; end if;
  if s.reissue_request_id = p_request_id then return people_private.managed_staff_projection(s); end if;
  if s.status = 'revoked' or (s.status = 'processing' and s.lease_until > clock_timestamp())
      or (s.reissue_request_id is not null and s.updated_at > clock_timestamp() - interval '1 minute')
      or not people_private.managed_staff_eligible(s) then
    raise exception using errcode = '22023', message = 'STAFF_REISSUE_UNAVAILABLE';
  end if;

  update people_private.managed_staff_identities
    set status = case when delivery = 'email' and mailbox_verified_at is null then 'verification_required' else 'prepared' end,
        reissue_request_id = p_request_id, generation = null, lease_token = null, lease_until = null,
        expires_at = null, password_ready_at = null, updated_at = clock_timestamp()
    where id = p_identity_id returning * into s;
  if s.user_id is not null then
    update core.organization_administrator_logins
      set must_change_password = true, handover_sent_at = null, password_changed_at = clock_timestamp()
      where user_id = s.user_id;
    update core.organization_account_recovery set password_changed_at = clock_timestamp() where user_id = s.user_id;
    delete from people_private.managed_staff_password_grants where user_id = s.user_id;
  end if;
  insert into audit.events (tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id)
    values (s.tenant_id,auth.uid(),p_request_id,'organization.staff_reissue_requested','managed_staff_identity',s.id);
  return people_private.managed_staff_projection(s);
end;
$$;

create function api.revoke_managed_staff_identity(p_identity_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities;
begin
  select * into s from people_private.managed_staff_identities where id = p_identity_id for update;
  if not found or not people_private.managed_staff_can_manage(s.tenant_id, s.kind, s.legal_entity_id, s.branch_id, s.migration_id) then
    raise exception using errcode = '42501', message = 'STAFF_PROVISION_FORBIDDEN';
  end if;
  if s.status = 'revoked' then return; end if;
  update people_private.managed_staff_identities
    set status = 'revoked', lease_token = null, lease_until = null, mailbox_code_hash = null, updated_at = clock_timestamp()
    where id = s.id;
  update core.memberships set status = 'revoked', version = version + 1, updated_at = statement_timestamp()
    where tenant_id = s.tenant_id and id = s.membership_id and status <> 'revoked';
  update people_private.account_links set status = 'revoked', version = version + 1
    where tenant_id = s.tenant_id and id = s.link_id and status = 'accepted';
  delete from people_private.managed_staff_password_grants where user_id = s.user_id;
  insert into audit.events (tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id)
    values (s.tenant_id,auth.uid(),gen_random_uuid(),'organization.staff_access_revoked','managed_staff_identity',s.id);
end;
$$;

alter table core.organization_identity_limits
  drop constraint organization_identity_limits_purpose_check,
  add check (purpose in ('reset','verify','purchase','operator_reset','operator_verify','staff_mailbox'));

create function api.managed_staff_issue_mailbox_code(p_identity_id uuid, p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  s people_private.managed_staff_identities;
  v_now timestamptz := clock_timestamp();
  v_hour timestamptz := date_trunc('hour', v_now);
begin
  select * into s from people_private.managed_staff_identities where id = p_identity_id for update;
  if not found or s.status <> 'verification_required' or s.email is null
      or s.mailbox_sent_at > v_now - interval '1 minute' or not people_private.managed_staff_eligible(s)
      or p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then return null; end if;
  insert into core.organization_identity_limits as l (purpose, window_start, sent_count)
  values ('staff_mailbox', v_hour, 1)
  on conflict (purpose) do update set window_start = excluded.window_start,
    sent_count = case when l.window_start = v_hour then l.sent_count + 1 else 1 end
    where l.window_start <> v_hour or l.sent_count < 120;
  if not found then return null; end if;
  update people_private.managed_staff_identities
    set mailbox_code_hash = p_hash, mailbox_code_expires_at = v_now + interval '10 minutes',
        mailbox_attempts = 0, mailbox_sent_at = v_now, updated_at = v_now where id = s.id;
  return s.email;
end;
$$;

create function api.managed_staff_consume_mailbox_code(p_identity_id uuid, p_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities;
begin
  select * into s from people_private.managed_staff_identities where id = p_identity_id for update;
  if not found or s.status <> 'verification_required' or s.mailbox_code_hash is null
      or s.mailbox_attempts >= 5 or s.mailbox_code_expires_at <= clock_timestamp()
      or not people_private.managed_staff_eligible(s) then return false; end if;
  if s.mailbox_code_hash is distinct from p_hash then
    update people_private.managed_staff_identities set mailbox_attempts = mailbox_attempts + 1 where id = s.id;
    return false;
  end if;
  update people_private.managed_staff_identities
    set status = 'prepared', mailbox_verified_at = clock_timestamp(), mailbox_code_hash = null,
        mailbox_code_expires_at = null, updated_at = clock_timestamp() where id = s.id;
  return true;
end;
$$;

-- The namespace is reserved before GoTrue creates the Auth row. The common
-- checkout trigger takes the same advisory lock and protects the login alias.
create function people_private.check_managed_staff_alias()
returns trigger language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities; v_metadata jsonb;
begin
  if right(lower(coalesce(new.email, '')),21) <> '@admin.jentra.invalid' then return new; end if;
  select * into s from people_private.managed_staff_identities
    where username = split_part(lower(new.email),'@',1);
  select raw_app_meta_data into v_metadata from auth.users where id = new.id;
  if s.id is null and v_metadata->>'managed_staff_identity_id' is null then return new; end if;
  if s.id is null or s.status <> 'processing'
      or v_metadata->>'managed_staff_identity_id' is distinct from s.id::text
      or v_metadata->>'provisioned_tenant_id' is distinct from s.tenant_id::text
      or v_metadata->>'managed_staff_generation' is distinct from s.generation::text
      or v_metadata->>'managed_staff_prepare_token' is distinct from s.lease_token::text
      or s.lease_until <= clock_timestamp()
  then raise exception using errcode = '23505', message = 'STAFF_USERNAME_UNAVAILABLE'; end if;
  return new;
end;
$$;
create constraint trigger zz_managed_staff_alias after insert or update of email on auth.users
  deferrable initially deferred for each row execute function people_private.check_managed_staff_alias();

create function api.managed_staff_claim(p_identity_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities; v_user uuid; v_now timestamptz := clock_timestamp();
begin
  select * into s from people_private.managed_staff_identities where id = p_identity_id for update;
  if not found or not people_private.managed_staff_eligible(s)
      or (s.delivery = 'email' and s.mailbox_verified_at is null)
      or (s.status <> 'prepared' and not (s.status = 'processing' and s.lease_until <= v_now)) then return null; end if;
  update people_private.managed_staff_identities
    set status = 'processing', generation = gen_random_uuid(), lease_token = gen_random_uuid(),
      lease_until = v_now + interval '3 minutes', expires_at = v_now + interval '24 hours', updated_at = v_now
    where id = s.id returning * into s;
  select id into v_user from auth.users
    where email = s.username || '@admin.jentra.invalid' and deleted_at is null
      and raw_app_meta_data->>'managed_staff_identity_id' = s.id::text
      and raw_app_meta_data->>'provisioned_tenant_id' = s.tenant_id::text;
  return people_private.managed_staff_projection(s) || jsonb_build_object(
    'email', s.email, 'generation', s.generation, 'lease_token', s.lease_token, 'user_id', v_user
  );
end;
$$;

create function api.managed_staff_bind(p_identity_id uuid, p_lease_token uuid, p_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities; v_now timestamptz := clock_timestamp();
begin
  select * into s from people_private.managed_staff_identities where id = p_identity_id and status = 'processing'
    and lease_token = p_lease_token and lease_until > v_now for update;
  if not found or not people_private.managed_staff_eligible(s) or (s.user_id is not null and s.user_id <> p_user_id)
      or not exists (select 1 from auth.users u
        where u.id = p_user_id and u.email = s.username || '@admin.jentra.invalid' and u.deleted_at is null
          and u.raw_app_meta_data->>'managed_staff_identity_id' = s.id::text
          and u.raw_app_meta_data->>'provisioned_tenant_id' = s.tenant_id::text
          and u.raw_app_meta_data->>'managed_staff_generation' = s.generation::text
          and u.raw_app_meta_data->>'managed_staff_prepare_token' = s.lease_token::text) then return false; end if;
  insert into core.organization_administrator_logins (
    tenant_id, user_id, username, password_changed_at
  ) values (s.tenant_id, p_user_id, s.username, v_now)
  on conflict (user_id) do update set must_change_password = true, password_changed_at = excluded.password_changed_at,
    handover_sent_at = null
  where core.organization_administrator_logins.tenant_id = excluded.tenant_id
    and core.organization_administrator_logins.username = excluded.username;
  if not found then return false; end if;
  insert into core.organization_account_recovery (user_id,email,verified_at,password_changed_at)
    values (p_user_id, s.email, s.mailbox_verified_at, v_now)
  on conflict (user_id) do update set password_changed_at = excluded.password_changed_at;
  update people_private.managed_staff_identities set user_id = p_user_id, updated_at = v_now where id = s.id;
  return true;
end;
$$;

create function api.managed_staff_finish(p_identity_id uuid, p_lease_token uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities; v_now timestamptz := clock_timestamp();
begin
  update people_private.managed_staff_identities s1
    set status = 'issued', lease_token = null, lease_until = null, updated_at = v_now
    where id = p_identity_id and status = 'processing' and lease_token = p_lease_token and lease_until > v_now
      and user_id is not null and people_private.managed_staff_eligible(s1)
    returning * into s;
  if not found then return false; end if;
  update core.organization_administrator_logins set handover_sent_at = v_now where user_id = s.user_id;
  insert into audit.events (tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id)
    values (s.tenant_id,s.created_by,s.generation,'organization.staff_credential_issued','managed_staff_identity',s.id);
  return true;
end;
$$;

create function api.managed_staff_fail(p_identity_id uuid, p_lease_token uuid)
returns void language sql security definer set search_path = '' as $$
  update people_private.managed_staff_identities
    set status = 'failed', lease_token = null, lease_until = null, updated_at = clock_timestamp()
    where id = p_identity_id and status = 'processing' and lease_token = p_lease_token
    and lease_until > clock_timestamp();
$$;


create function people_private.activate_managed_staff_identity(p_identity_id uuid, p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s people_private.managed_staff_identities;
  v_role_id uuid;
  v_role_code text;
  v_permissions text[];
  v_seats integer;
  v_memberships integer;
  v_legacy_grants jsonb := '[]';
  v_legacy_revoked boolean := false;
  v_now timestamptz := clock_timestamp();
begin
  select * into strict s from people_private.managed_staff_identities where id = p_identity_id for update;
  if s.status = 'active' then return to_jsonb(s) - array['email','mailbox_code_hash','lease_token']; end if;
  if s.status <> 'ready' or s.user_id is null or s.password_ready_at is null
      or not people_private.managed_staff_eligible(s) then
    raise exception using errcode = '42501', message = 'STAFF_ACTIVATION_NOT_READY';
  end if;
  if s.membership_id is not null then
    if not exists (select 1 from core.memberships m where m.tenant_id = s.tenant_id and m.id = s.membership_id
        and m.user_id = s.user_id and m.status = 'active')
      or (s.kind = 'employee' and not exists (select 1 from people_private.account_links l
        where l.tenant_id = s.tenant_id and l.id = s.link_id and l.status = 'accepted')) then
      raise exception using errcode = '42501', message = 'STAFF_ACTIVATION_NOT_READY';
    end if;
    update people_private.managed_staff_identities set status = 'active', updated_at = v_now where id = s.id;
    return jsonb_build_object('membership_id',s.membership_id,'link_id',s.link_id);
  end if;
  if exists (select 1 from core.organization_administrator_logins l where l.user_id = s.user_id and l.must_change_password)
    or exists (select 1 from core.memberships m where m.user_id = s.user_id) then
    raise exception using errcode = '42501', message = 'STAFF_ACTIVATION_NOT_READY';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(s.tenant_id::text, 45132));
  if s.supersedes_membership_id is not null then
    if not exists (select 1 from core.memberships m where m.tenant_id = s.tenant_id
      and m.id = s.supersedes_membership_id and m.status = 'active') then
      raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_TARGET_INVALID';
    end if;
    if s.supersedes_link_id is not null then
      update people_private.account_links l set status = 'revoked', version = version + 1
      where (l.id,l.tenant_id,l.legal_entity_id,l.branch_id,l.employee_id,l.membership_id) =
        (s.supersedes_link_id,s.tenant_id,s.legal_entity_id,s.branch_id,s.employee_id,s.supersedes_membership_id)
        and l.status = 'accepted';
      if not found then raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_TARGET_INVALID'; end if;
      insert into people_private.link_events (tenant_id,legal_entity_id,employee_id,link_id,event_type,recorded_by,actor_kind)
        values (s.tenant_id,s.legal_entity_id,s.employee_id,s.supersedes_link_id,'link_revoke',p_actor_id,'user');
    end if;
    if s.kind = 'hr_manager' then
      with removed as (
        delete from core.role_assignments a using core.roles r
        where (r.tenant_id,r.id) = (a.tenant_id,a.role_id)
          and a.tenant_id = s.tenant_id and a.membership_id = s.supersedes_membership_id
          and r.is_system and r.code in ('department.hr','people.hr_manager')
        returning a.*
      )
      select coalesce(jsonb_agg(to_jsonb(removed) order by removed.id),'[]') into v_legacy_grants from removed;
      if v_legacy_grants = '[]' then
        raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_TARGET_INVALID';
      end if;
    end if;
    update core.memberships m set status = 'revoked', version = version + 1, updated_at = v_now
      where m.tenant_id = s.tenant_id and m.id = s.supersedes_membership_id and m.status = 'active'
        and not exists (
          select 1 from people_private.account_links l where (l.tenant_id,l.membership_id) = (m.tenant_id,m.id)
            and l.status in ('accepted','pending')
        )
        and not exists (
          select 1 from core.role_assignments a where (a.tenant_id,a.membership_id) = (m.tenant_id,m.id)
            and (s.kind = 'hr_manager' or exists (
              select 1 from core.role_permissions rp where rp.role_id = a.role_id
                and rp.permission_code not in ('people.view','people.self.view')
            ))
        );
    v_legacy_revoked := found;
  end if;

  select max(seats) into v_seats from billing.tenant_subscriptions
    where tenant_id = s.tenant_id and status in ('active','trialing');
  select count(*) into v_memberships from core.memberships where tenant_id = s.tenant_id and status in ('active','invited');
  if v_seats is null or v_memberships >= v_seats then
    raise exception using errcode = '22023', message = 'STAFF_SEATS_UNAVAILABLE';
  end if;

  if s.kind = 'hr_manager' then
    if (select count(*) from core.legal_entities e where e.tenant_id = s.tenant_id
      and e.status = 'active' and e.id = any(s.legal_entity_ids)) <> cardinality(s.legal_entity_ids) then
      raise exception using errcode = '22023', message = 'INVALID_HR_ENTITY_SCOPE';
    end if;
    v_role_code := 'people.hr_manager';
    v_permissions := array['people.view','people.employees.view','people.employees.manage','people.employment.manage',
      'people.employees.history.view','people.employee_credentials.manage'];
  else
    v_role_code := 'people.employee_app';
    v_permissions := array['people.self.view'];
  end if;

  insert into core.roles (tenant_id,code,name,is_system,requires_mfa) values (
    s.tenant_id,v_role_code,case when s.kind = 'hr_manager' then 'HR Manager' else 'Employee App' end,
    true,s.kind = 'hr_manager'
  ) on conflict (tenant_id,code) do nothing;
  select id into v_role_id from core.roles where tenant_id = s.tenant_id and code = v_role_code and is_system
    and requires_mfa = (s.kind = 'hr_manager');
  if v_role_id is null or exists (select 1 from core.role_permissions rp where rp.role_id = v_role_id
      and rp.permission_code <> all(v_permissions)) then
    raise exception using errcode = '42501', message = 'STAFF_ROLE_INVALID';
  end if;
  insert into core.role_permissions (tenant_id,role_id,permission_code)
    select s.tenant_id,v_role_id,code from core.permissions where code = any(v_permissions) on conflict do nothing;
  insert into core.memberships (tenant_id,user_id,invited_by,joined_at) values (s.tenant_id,s.user_id,p_actor_id,v_now)
    returning id into s.membership_id;

  if s.kind = 'hr_manager' then
    insert into core.role_assignments (tenant_id,membership_id,role_id,legal_entity_id,created_by)
      select s.tenant_id,s.membership_id,v_role_id,id,p_actor_id from unnest(s.legal_entity_ids) e(id);
  else
    insert into core.role_assignments (tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
      values (s.tenant_id,s.membership_id,v_role_id,s.legal_entity_id,s.branch_id,p_actor_id);
    s.link_id := gen_random_uuid();
    insert into people_private.account_links (id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,
      user_id,status,initiated_by,accepted_at) values (
      s.link_id,s.tenant_id,s.legal_entity_id,s.branch_id,s.employee_id,s.membership_id,s.user_id,'accepted',p_actor_id,v_now
    );
    insert into people_private.link_events (tenant_id,legal_entity_id,employee_id,link_id,event_type,recorded_by,actor_kind)
      values (s.tenant_id,s.legal_entity_id,s.employee_id,s.link_id,'link_accept',s.user_id,'user');
  end if;
  update people_private.managed_staff_identities set status = 'active', membership_id = s.membership_id,
    link_id = s.link_id, legacy_grants = v_legacy_grants, legacy_membership_revoked = v_legacy_revoked,
    updated_at = v_now where id = s.id;
  insert into audit.events (tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id)
    values (s.tenant_id,p_actor_id,gen_random_uuid(),'organization.staff_access_activated','managed_staff_identity',s.id);
  return jsonb_build_object('membership_id',s.membership_id,'link_id',s.link_id,
    'retired_membership_id',s.supersedes_membership_id,'retired_link_id',s.supersedes_link_id);
end;
$$;

create function people_private.rollback_managed_staff_identity(p_identity_id uuid,p_actor_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities;
begin
  select * into strict s from people_private.managed_staff_identities where id = p_identity_id for update;
  if s.migration_id is null or s.supersedes_membership_id is null or s.membership_id is null
      or s.status <> 'active' then
    raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_STAFF_CHANGED';
  end if;
  update core.memberships set status = 'revoked', version = version + 1
    where (tenant_id,id,user_id) = (s.tenant_id,s.membership_id,s.user_id) and status = 'active';
  if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_STAFF_CHANGED'; end if;
  if s.legacy_membership_revoked then
    update core.memberships set status = 'active', version = version + 1
      where (tenant_id,id) = (s.tenant_id,s.supersedes_membership_id) and status = 'revoked';
    if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_STAFF_CHANGED'; end if;
  end if;
  if s.kind = 'employee' then
    if not people_private.managed_employee_is_current(s.tenant_id,s.legal_entity_id,s.branch_id,s.employee_id) then
      raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_EMPLOYMENT_CHANGED';
    end if;
    update people_private.account_links set status = 'revoked', version = version + 1
      where (tenant_id,id) = (s.tenant_id,s.link_id) and status = 'accepted';
    if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_STAFF_CHANGED'; end if;
    update people_private.account_links set status = 'accepted', version = version + 1
      where (tenant_id,id) = (s.tenant_id,s.supersedes_link_id) and status = 'revoked';
    if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_STAFF_CHANGED'; end if;
    insert into people_private.link_events
      (tenant_id,legal_entity_id,employee_id,link_id,event_type,recorded_by,actor_kind)
      values (s.tenant_id,s.legal_entity_id,s.employee_id,s.link_id,'link_revoke',p_actor_id,'user'),
        (s.tenant_id,s.legal_entity_id,s.employee_id,s.supersedes_link_id,'link_accept',p_actor_id,'user');
  else
    insert into core.role_assignments
      select * from jsonb_populate_recordset(null::core.role_assignments,s.legacy_grants);
  end if;
  update people_private.managed_staff_identities set status = 'revoked', updated_at = clock_timestamp()
    where id = s.id;
end;
$$;

create function people_private.protect_managed_staff_roles()
returns trigger language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities; v_role core.roles;
begin
  select i.* into s from people_private.managed_staff_identities i
    join core.memberships m on (m.tenant_id,m.user_id) = (i.tenant_id,i.user_id)
    where (m.tenant_id,m.id) = (new.tenant_id,new.membership_id);
  if not found then return new; end if;
  select * into strict v_role from core.roles where (tenant_id,id) = (new.tenant_id,new.role_id);
  if not v_role.is_system or (case when s.kind = 'employee' then
    v_role.code <> 'people.employee_app'
      or (new.legal_entity_id,new.branch_id) is distinct from (s.legal_entity_id,s.branch_id)
  else v_role.code <> 'people.hr_manager' or new.legal_entity_id is null
    or not (new.legal_entity_id = any(s.legal_entity_ids)) or new.branch_id is not null end) then
    raise exception using errcode = '42501', message = 'STAFF_ROLE_SCOPE_DENIED';
  end if;
  return new;
end;
$$;

create trigger protect_managed_staff_roles before insert or update on core.role_assignments
  for each row execute function people_private.protect_managed_staff_roles();

create function people_private.managed_staff_access_ready(s people_private.managed_staff_identities)
returns boolean language sql stable set search_path = '' as $$
  select s.status = 'active' and people_private.managed_staff_eligible(s)
    and exists (select 1 from core.memberships m where m.tenant_id = s.tenant_id and m.id = s.membership_id
      and m.user_id = s.user_id and m.status = 'active')
    and (s.kind = 'hr_manager' or exists (
      select 1 from people_private.account_links l
      where (l.id,l.tenant_id,l.legal_entity_id,l.branch_id,l.employee_id,l.membership_id,l.user_id) =
        (s.link_id,s.tenant_id,s.legal_entity_id,s.branch_id,s.employee_id,s.membership_id,s.user_id)
        and l.status = 'accepted'
    ));
$$;

create or replace function core.organization_account_ready(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when auth.jwt()->'app_metadata'->>'managed_org_admin' = 'true'
    or exists (select 1 from core.organization_administrator_logins where user_id = p_user_id)
  then exists (
    select 1 from core.organization_administrator_logins l
    left join people_private.managed_staff_identities s on s.user_id = l.user_id
    where l.user_id = p_user_id and not l.must_change_password
      and core.organization_identity_session_is_current(p_user_id, l.password_changed_at)
      and (s.id is null or people_private.managed_staff_access_ready(s))
  ) else not exists (
    select 1 from core.organization_account_recovery r
    where r.user_id = p_user_id and r.password_changed_at is not null
      and not core.organization_identity_session_is_current(p_user_id, r.password_changed_at)
  ) end;
$$;

-- Field Sales governance, when installed before this candidate, lets a
-- restricted companion account use its own Employee self-service capabilities
-- without the broad people.view gate. This candidate replaces
-- people.require_access afterwards, so it must carry that exception forward.
-- Keep the permission list identical to 20261031090000_field_sales_governance.sql.
-- Without Field Sales the helper never applies.
do $scope$
begin
  if to_regprocedure('field_sales.restricted(uuid)') is not null then
    execute $ddl$
      create function people_private.field_self_capability(p_tenant_id uuid, p_permission text)
      returns boolean language sql stable security definer set search_path = '' as $body$
        select field_sales.restricted(p_tenant_id) and p_permission in (
          'people.self.view', 'people.attendance.self.request', 'people.leave.self.manage',
          'people.payroll.payslip.self', 'people.hr.cases.self.manage', 'people.hr.documents.self.view'
        );
      $body$;
    $ddl$;
  else
    execute $ddl$
      create function people_private.field_self_capability(p_tenant_id uuid, p_permission text)
      returns boolean language sql stable security definer set search_path = '' as $body$
        select false;
      $body$;
    $ddl$;
  end if;
end;
$scope$;
revoke all on function people_private.field_self_capability(uuid,text) from public, anon, authenticated;

create or replace function people.require_access(
  p_tenant_id uuid, p_entity_id uuid, p_branch_id uuid, p_permission text
)
returns void language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities;
begin
  if p_branch_id is null or p_entity_id is null or p_tenant_id is null then
    raise exception using errcode = '42501', message = 'Permission denied.';
  end if;
  select * into s from people_private.managed_staff_identities where user_id = auth.uid() and kind = 'employee';
  if found then
    if p_permission is distinct from 'people.self.view'
        or (s.tenant_id,s.legal_entity_id,s.branch_id) is distinct from (p_tenant_id,p_entity_id,p_branch_id)
        or not people_private.managed_staff_access_ready(s)
        or not core.has_permission(p_tenant_id,p_permission,p_entity_id,p_branch_id) then
      raise exception using errcode = '42501', message = 'EMPLOYEE_SELF_SCOPE_DENIED';
    end if;
    return;
  end if;
  if not people_private.field_self_capability(p_tenant_id, p_permission) then
    perform core.wave3_require_scope(p_tenant_id, 'people.view', p_entity_id, p_branch_id);
  end if;
  perform core.wave3_require_scope(p_tenant_id, p_permission, p_entity_id, p_branch_id);
  if not people_private.managed_staff_hr_plan(p_tenant_id) then
    raise exception using errcode = '42501', message = 'PEOPLE_ENTITLEMENT_REQUIRED';
  end if;
end;
$$;

create function api.managed_employee_workspaces()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'tenant_id',t.id,'tenant_name',t.name,'legal_entity_id',e.id,'entity_name',e.name,
    'branch_id',b.id,'branch_name',b.name,'timezone',b.timezone
  )), '[]')
  from people_private.managed_staff_identities s
  join core.tenants t on t.id = s.tenant_id
  join core.legal_entities e on (e.tenant_id,e.id) = (s.tenant_id,s.legal_entity_id)
  join core.branches b on (b.tenant_id,b.legal_entity_id,b.id) = (s.tenant_id,s.legal_entity_id,s.branch_id)
  where s.user_id = auth.uid() and s.kind = 'employee' and core.organization_account_ready(s.user_id);
$$;

alter table people_private.managed_staff_password_grants add column allow_expired boolean not null default false;

create function people_private.managed_staff_password_grant(s people_private.managed_staff_identities, p_recovery boolean)
returns uuid language sql set search_path = '' as $$
  insert into people_private.managed_staff_password_grants (user_id,token,generation,expires_at,allow_expired)
    values (s.user_id,gen_random_uuid(),s.generation,clock_timestamp() + interval '2 minutes',p_recovery)
  on conflict (user_id) do update set token = excluded.token, generation = excluded.generation,
    expires_at = excluded.expires_at, allow_expired = excluded.allow_expired
  returning token;
$$;

create function api.managed_staff_authorize_password_change(p_user_id uuid,p_password_changed_at timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,34555));
  select * into s from people_private.managed_staff_identities where user_id = p_user_id for update;
  if not found or s.status not in ('issued','ready','active') or not people_private.managed_staff_eligible(s)
      or (s.status = 'issued' and s.expires_at <= clock_timestamp())
      or not exists (select 1 from core.organization_administrator_logins l where l.user_id = p_user_id
        and l.password_changed_at = p_password_changed_at) then
    raise exception using errcode = '42501', message = 'STAFF_PASSWORD_STATE_CHANGED';
  end if;
  return people_private.managed_staff_password_grant(s,false);
end;
$$;

create function api.managed_staff_consume_password_reset(p_login_email text,p_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_reset jsonb; s people_private.managed_staff_identities;
begin
  v_reset := api.subscription_consume_password_reset(p_login_email,p_hash);
  if v_reset is null then return null; end if;
  select * into s from people_private.managed_staff_identities
    where user_id = (v_reset->>'user_id')::uuid for update;
  if not found then return v_reset; end if;
  if s.status not in ('issued','ready','active') or not people_private.managed_staff_eligible(s) then return null; end if;
  return v_reset || jsonb_build_object('staff_token',people_private.managed_staff_password_grant(s,true));
end;
$$;

create function people_private.managed_staff_guard_password()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  s people_private.managed_staff_identities;
  v_meta jsonb;
  v_token text;
  v_prepare text;
  v_now timestamptz := clock_timestamp();
begin
  if new.encrypted_password is not distinct from old.encrypted_password then return new; end if;
  select raw_app_meta_data into v_meta from auth.users where id = new.id;
  if v_meta->>'managed_staff_identity_id' is null then return new; end if;
  select * into strict s from people_private.managed_staff_identities
    where id::text = v_meta->>'managed_staff_identity_id' for update;
  v_prepare := v_meta->>'managed_staff_prepare_token';
  v_token := v_meta->>'managed_staff_password_token';

  if v_prepare is distinct from old.raw_app_meta_data->>'managed_staff_prepare_token' then
    if s.status <> 'processing' or (s.user_id is not null and s.user_id <> new.id)
        or v_prepare is distinct from s.lease_token::text or s.lease_until <= v_now
        or v_meta->>'managed_staff_generation' is distinct from s.generation::text then
      raise exception using errcode = '42501', message = 'STAFF_HANDOVER_STATE_CHANGED';
    end if;
    return new;
  end if;

  if v_token is distinct from old.raw_app_meta_data->>'managed_staff_password_token' then
    if s.user_id is distinct from new.id or s.status not in ('issued','ready','active')
        or not people_private.managed_staff_eligible(s) then
      raise exception using errcode = '42501', message = 'STAFF_PASSWORD_STATE_CHANGED';
    end if;
    delete from people_private.managed_staff_password_grants g
      where g.user_id = new.id and g.token::text = v_token and g.generation = s.generation and g.expires_at > v_now
        and (g.allow_expired or s.status <> 'issued' or s.expires_at > v_now);
    if not found then raise exception using errcode = '42501', message = 'STAFF_PASSWORD_STATE_CHANGED'; end if;
    if s.status = 'issued' then
      update people_private.managed_staff_identities set status = 'ready', password_ready_at = v_now,
        updated_at = v_now where id = s.id;
      if s.migration_id is null or s.membership_id is not null then
        perform people_private.activate_managed_staff_identity(s.id,s.created_by);
      end if;
    end if;
    return new;
  end if;
  if s.status <> 'active' or not people_private.managed_staff_access_ready(s) then
    raise exception using errcode = '42501', message = 'STAFF_PASSWORD_STATE_CHANGED';
  end if;
  return new;
end;
$$;
create constraint trigger managed_staff_guard_password after update of encrypted_password on auth.users
  deferrable initially deferred for each row execute function people_private.managed_staff_guard_password();

create function people_private.managed_staff_guard_session()
returns trigger language plpgsql security definer set search_path = '' as $$
declare s people_private.managed_staff_identities;
begin
  select si.* into s from auth.users u left join people_private.managed_staff_identities si
    on si.id::text = u.raw_app_meta_data->>'managed_staff_identity_id' and si.user_id = u.id
  where u.id = new.user_id and u.raw_app_meta_data->>'managed_staff_identity_id' is not null;
  if found and (s.id is null or s.status not in ('issued','ready','active')
      or (s.status = 'issued' and s.expires_at <= clock_timestamp())
      or not people_private.managed_staff_eligible(s)
      or (s.status = 'active' and not people_private.managed_staff_access_ready(s))) then
    raise exception using errcode = '42501', message = 'STAFF_LOGIN_UNAVAILABLE';
  end if;
  return new;
end;
$$;
create trigger managed_staff_guard_session before insert on auth.sessions
  for each row execute function people_private.managed_staff_guard_session();

create or replace function core.organization_recovery_target(p_login_email text)
returns table (user_id uuid, email text) language sql stable security definer set search_path = '' as $$
  select u.id, r.email from auth.users u
  join core.organization_account_recovery r on r.user_id = u.id and r.verified_at is not null
  left join core.organization_administrator_logins l on l.user_id = u.id
  left join people_private.managed_staff_identities s on s.user_id = u.id
  where u.email = p_login_email and u.deleted_at is null and coalesce(u.encrypted_password, '') <> ''
    and (u.banned_until is null or u.banned_until <= statement_timestamp())
    and not exists (select 1 from intelligence_control.operators o where o.actor_id = u.id and o.organization_manage)
    and case when s.id is not null then s.status in ('issued','ready','active') and people_private.managed_staff_eligible(s)
      else u.raw_app_meta_data->>'managed_org_admin' is distinct from 'true'
        or (core.organization_available(l.tenant_id) and exists (
          select 1 from core.memberships m
          where (m.tenant_id,m.user_id) = (l.tenant_id,l.user_id) and m.status = 'active'
        )) end;
$$;

alter function api.organization_identity_profile() rename to organization_identity_profile_base;
revoke all on function api.organization_identity_profile_base() from public, anon, authenticated, service_role;
create function api.organization_identity_profile()
returns jsonb language sql stable security definer set search_path = '' as $$
  select api.organization_identity_profile_base() || jsonb_build_object(
    'account_kind',s.kind,'staff_status',s.status
  )
  from (select 1) base left join people_private.managed_staff_identities s on s.user_id = auth.uid();
$$;

select organization_lifecycle.install_write_guards();

revoke all on function people_private.managed_staff_hr_plan(uuid),
  people_private.managed_employee_is_current(uuid,uuid,uuid,uuid),
  people_private.managed_staff_eligible(people_private.managed_staff_identities),
  people_private.managed_staff_can_manage(uuid,text,uuid,uuid,uuid),
  people_private.managed_staff_projection(people_private.managed_staff_identities),
  people_private.managed_staff_username(text,text,text,text,text,uuid),
  people_private.check_managed_staff_alias(), people_private.activate_managed_staff_identity(uuid,uuid),
  people_private.rollback_managed_staff_identity(uuid,uuid), people_private.protect_managed_staff_roles(),
  people_private.managed_staff_access_ready(people_private.managed_staff_identities),
  people_private.managed_staff_password_grant(people_private.managed_staff_identities,boolean),
  people_private.managed_staff_guard_password(),people_private.managed_staff_guard_session(),
  api.prepare_managed_staff_identity(uuid,text,uuid,text,text,text,text,uuid[],uuid,uuid,uuid,uuid,uuid,uuid),
  api.managed_staff_credentials(uuid,uuid,uuid,uuid),api.request_managed_staff_reissue(uuid,uuid),
  api.revoke_managed_staff_identity(uuid),api.managed_employee_workspaces(),api.organization_identity_profile(),
  api.managed_staff_issue_mailbox_code(uuid,text),api.managed_staff_consume_mailbox_code(uuid,text),
  api.managed_staff_claim(uuid),api.managed_staff_bind(uuid,uuid,uuid),api.managed_staff_finish(uuid,uuid),
  api.managed_staff_fail(uuid,uuid),api.managed_staff_authorize_password_change(uuid,timestamptz),
  api.managed_staff_consume_password_reset(text,text)
  from public, anon, authenticated, service_role;

grant execute on function
  api.prepare_managed_staff_identity(uuid,text,uuid,text,text,text,text,uuid[],uuid,uuid,uuid,uuid,uuid,uuid),
  api.managed_staff_credentials(uuid,uuid,uuid,uuid),api.request_managed_staff_reissue(uuid,uuid),
  api.revoke_managed_staff_identity(uuid),api.managed_employee_workspaces(),api.organization_identity_profile()
  to authenticated;
grant execute on function api.managed_staff_issue_mailbox_code(uuid,text),api.managed_staff_consume_mailbox_code(uuid,text),
  api.managed_staff_claim(uuid),api.managed_staff_bind(uuid,uuid,uuid),api.managed_staff_finish(uuid,uuid),
  api.managed_staff_fail(uuid,uuid),api.managed_staff_authorize_password_change(uuid,timestamptz),
  api.managed_staff_consume_password_reset(text,text) to service_role;
