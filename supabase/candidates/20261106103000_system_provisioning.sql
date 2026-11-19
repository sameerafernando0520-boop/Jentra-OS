create sequence core.system_serial_sequence as bigint;
revoke all on sequence core.system_serial_sequence from public, anon, authenticated;

alter table core.tenants
  add column system_serial text unique check (system_serial ~ '^J[0-9]{9,19}$'),
  add column primary_owner_user_id uuid references auth.users(id);

alter table billing.subscription_checkout_orders
  add column system_serial text unique check (system_serial ~ '^J[0-9]{9,19}$');

create table billing.system_owner_handover_targets (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  serial text unique check (serial ~ '^J[0-9]{9,19}$'),
  username text not null unique check (username ~ '^[a-z0-9][a-z0-9._-]{2,47}$'),
  recipient_email text not null,
  actor_id uuid not null references auth.users(id),
  source text not null check (source in ('checkout','operator','cutover')),
  verified_at timestamptz,
  request_id uuid,
  request_payload jsonb,
  created_at timestamptz not null default statement_timestamp(),
  unique (id, tenant_id),
  unique (actor_id, request_id)
);

-- Mail challenges are outside tenant archives and have no tenant FK. A
-- challenge is useless without a still-present and available target.
create table billing.system_owner_verifications (
  target_id uuid primary key,
  code_hash text not null check (code_hash ~ '^[a-f0-9]{64}$'),
  issued_at timestamptz not null,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts between 0 and 5)
);
create table billing.system_owner_verification_rate (
  singleton boolean primary key default true check (singleton),
  window_start timestamptz not null,
  sent_count integer not null check (sent_count between 1 and 120)
);

create table core.system_registration_requests (
  tenant_id uuid not null references core.tenants(id),
  request_id uuid not null,
  actor_id uuid not null references auth.users(id),
  payload jsonb not null,
  primary key (tenant_id, request_id)
);

alter table billing.system_owner_handover_targets enable row level security;
alter table billing.system_owner_verifications enable row level security;
alter table billing.system_owner_verification_rate enable row level security;
alter table core.system_registration_requests enable row level security;
revoke all on billing.system_owner_handover_targets, billing.system_owner_verifications,
  billing.system_owner_verification_rate, core.system_registration_requests
from public, anon, authenticated, service_role;

-- Old orders keep the username displayed to their purchaser. Adapt existing
-- jobs to the general owner queue without touching Auth or tenant identity.
insert into billing.system_owner_handover_targets
  (id, tenant_id, username, recipient_email, actor_id, source, verified_at)
select o.id, o.tenant_id, o.username, o.signup_email, o.buyer_id, 'checkout', o.paid_at
from billing.subscription_handover_jobs j
join billing.subscription_checkout_orders o on o.id = j.order_id;

alter table billing.subscription_handover_jobs
  drop constraint subscription_handover_jobs_order_id_tenant_id_fkey,
  add foreign key (order_id, tenant_id) references billing.system_owner_handover_targets(id, tenant_id);
alter table core.organization_administrator_logins
  drop constraint organization_administrator_logins_checkout_order_id_fkey,
  add foreign key (checkout_order_id) references billing.system_owner_handover_targets(id);

create function core.allocate_system_serial()
returns text language sql volatile set search_path = '' as $$
  select 'J' || lpad(serial, greatest(9, length(serial)), '0')
  from (select nextval('core.system_serial_sequence')::text as serial) as allocated;
$$;

alter table core.tenants alter column system_serial set default core.allocate_system_serial();
update core.tenants set system_serial = core.allocate_system_serial() where system_serial is null;
alter table core.tenants alter column system_serial set not null;
create unique index system_primary_owner_idx on core.tenants(primary_owner_user_id)
  where primary_owner_user_id is not null;
create unique index system_handover_source_idx on billing.system_owner_handover_targets(tenant_id, source);

create function core.keep_system_serial()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.system_serial is not null and old.system_serial is distinct from new.system_serial then
    raise exception using errcode = '22023', message = 'SYSTEM_SERIAL_IMMUTABLE';
  end if;
  return new;
end;
$$;
create trigger system_serial_immutable before update of system_serial on core.tenants
for each row execute function core.keep_system_serial();

create function core.check_primary_system_owner_grant()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from core.tenants t
    join core.roles r on r.tenant_id = t.id and r.id = new.role_id
    join core.memberships m on m.tenant_id = t.id and m.id = new.membership_id
    where t.id = new.tenant_id and t.primary_owner_user_id is not null
      and r.is_system and r.code = 'tenant_owner'
      and (m.user_id <> t.primary_owner_user_id or new.legal_entity_id is not null or new.branch_id is not null)
  ) then raise exception using errcode = '42501', message = 'SYSTEM_PRIMARY_OWNER_REQUIRED'; end if;
  return new;
end;
$$;
create trigger system_primary_owner_grant before insert or update on core.role_assignments
for each row execute function core.check_primary_system_owner_grant();

create function billing.reserve_system_username(p_name text, p_serial text, p_seed uuid)
returns text language plpgsql set search_path = '' as $$
declare
  v_base text := trim(both '-' from regexp_replace(
    lower(regexp_replace(normalize(trim(p_name), NFKD), U&'[\0300-\036F]', '', 'g')),
    '[^a-z0-9]+', '-', 'g'));
  v_suffix text := '-' || lower(p_serial);
  v_extra text;
  v_username text;
  v_attempt integer;
  v_staff_reserved boolean;
begin
  if v_base = '' then
    v_base := 'organization-' || left(md5(normalize(trim(p_name), NFKC)), 8);
  end if;
  for v_attempt in 0..8 loop
    v_extra := case when v_attempt = 0 then '' else '-' || left(md5(p_seed::text || ':' || v_attempt), 8) end;
    v_username := rtrim(left(v_base, 48 - length(v_extra) - length(v_suffix)), '-') || v_extra || v_suffix;
    perform pg_advisory_xact_lock(hashtextextended(v_username, 45109));
    v_staff_reserved := false;
    if to_regclass('people_private.managed_staff_identities') is not null then
      execute 'select exists (select 1 from people_private.managed_staff_identities where username = $1)'
        into v_staff_reserved using v_username;
    end if;
    if not v_staff_reserved and not exists (select 1 from billing.subscription_checkout_orders where username = v_username)
      and not exists (select 1 from billing.system_owner_handover_targets where username = v_username)
      and not exists (select 1 from auth.users where lower(email) = v_username || '@admin.jentra.invalid')
      and not exists (select 1 from core.organization_administrator_logins where username = v_username) then
      return v_username;
    end if;
  end loop;
  raise exception using errcode = '23505', message = 'SYSTEM_USERNAME_UNAVAILABLE';
end;
$$;

create or replace function billing.reserve_subscription_username(p_name text, p_order_id uuid)
returns text language sql volatile set search_path = '' as $$
  select billing.reserve_system_username(p_name, core.allocate_system_serial(), p_order_id);
$$;

create function billing.set_checkout_system_serial()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.kind = 'initial' then
    new.system_serial := upper(substring(new.username from '-(j[0-9]{9,19})$'));
    if new.system_serial is null then
      raise exception using errcode = '22023', message = 'SYSTEM_SERIAL_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;
create trigger checkout_system_serial before insert on billing.subscription_checkout_orders
for each row execute function billing.set_checkout_system_serial();

create function billing.attach_checkout_handover_target()
returns trigger language plpgsql set search_path = '' as $$
begin
  insert into billing.system_owner_handover_targets
    (id, tenant_id, serial, username, recipient_email, actor_id, source, verified_at)
  select o.id, o.tenant_id, o.system_serial, o.username, o.signup_email, o.buyer_id, 'checkout', o.paid_at
  from billing.subscription_checkout_orders o
  where o.id = new.order_id and o.tenant_id = new.tenant_id and o.kind = 'initial' and o.status = 'paid'
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger checkout_handover_target before insert on billing.subscription_handover_jobs
for each row execute function billing.attach_checkout_handover_target();

create function core.create_system_instance(
  p_name text, p_serial text, p_currency text, p_timezone text, p_actor uuid
)
returns uuid language plpgsql set search_path = '' as $$
declare
  v_id uuid := gen_random_uuid();
  v_role uuid;
begin
  insert into core.tenants (id, name, slug, status, timezone, default_currency_code, created_by, system_serial)
  values (v_id, p_name, 'jentra-' || lower(p_serial) || '-' || left(v_id::text, 8),
    'active', p_timezone, p_currency, p_actor, p_serial);
  insert into core.roles (tenant_id, code, name, description, requires_mfa, is_system)
  values (v_id, 'tenant_owner', 'Tenant owner', 'Administrator for this system.', true, true)
  returning id into v_role;
  insert into core.role_permissions (tenant_id, role_id, permission_code)
  select v_id, v_role, code from core.permissions;
  return v_id;
end;
$$;

create function billing.valid_system_owner_email(p_email text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(length(p_email) <= 254
    and p_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    and p_email !~ '@admin\.jentra\.invalid$', false);
$$;

create function billing.system_owner_status(p_target billing.system_owner_handover_targets)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'tenant_id', p_target.tenant_id, 'serial', p_target.serial, 'username', p_target.username,
    'verification_id', p_target.id, 'owner_email', p_target.recipient_email,
    'owner_status', case
      when p_target.verified_at is null then 'awaiting_verification'
      when j.status = 'sent' and j.credential_expires_at <= statement_timestamp() then 'expired'
      else j.status end,
    'term_ends_at', s.current_period_ends_at,
    'can_request_verification', p_target.verified_at is null and core.organization_available(p_target.tenant_id)
      and (v.target_id is null or v.issued_at <= statement_timestamp() - interval '1 minute'),
    'can_reissue', coalesce(j.status in ('failed', 'sent')
      and j.updated_at <= statement_timestamp() - interval '1 minute'
      and core.organization_available(p_target.tenant_id), false)
  )
  from (select 1) base
  left join billing.subscription_handover_jobs j on j.order_id = p_target.id
  left join billing.tenant_subscriptions s on s.tenant_id = p_target.tenant_id
  left join billing.system_owner_verifications v on v.target_id = p_target.id;
$$;

create function api.platform_create_system(
  p_name text, p_owner_email text, p_plan_code text, p_expected_revision bigint,
  p_request_id uuid, p_mode text, p_payment_reference text default null,
  p_paid_amount_minor bigint default null, p_paid_at timestamptz default null, p_reason text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_name text := trim(p_name);
  v_email text := lower(trim(p_owner_email));
  v_reference text := nullif(trim(p_payment_reference), '');
  v_reason text := nullif(trim(p_reason), '');
  v_target billing.system_owner_handover_targets;
  v_payload jsonb;
  v_plan billing.plans;
  v_serial text;
  v_tenant uuid;
  v_target_id uuid := gen_random_uuid();
  v_seats integer;
  v_end timestamptz;
begin
  perform intelligence_control.operator_required('organization');
  if v_name is null or length(v_name) not between 2 and 160 or v_name ~ '[[:cntrl:]]'
    or not billing.valid_system_owner_email(v_email) or p_request_id is null
    or p_expected_revision is null or p_mode is null or p_mode not in ('paid','complimentary')
    or length(v_reason) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_SYSTEM_CREATION';
  end if;
  v_payload := jsonb_build_object('name', v_name, 'email', v_email, 'plan', p_plan_code,
    'revision', p_expected_revision, 'mode', p_mode, 'reference', lower(v_reference),
    'amount', p_paid_amount_minor, 'paid_at', p_paid_at, 'reason', v_reason);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text || p_request_id::text, 45112));
  select * into v_target from billing.system_owner_handover_targets
    where actor_id = v_actor and request_id = p_request_id;
  if found then
    if v_target.request_payload is distinct from v_payload then
      raise exception using errcode = '40001', message = 'SYSTEM_REQUEST_CHANGED';
    end if;
    return billing.system_owner_status(v_target);
  end if;
  select * into v_plan from billing.plans where code = p_plan_code and status = 'active'
    and price_currency_code = 'LKR' and price_minor is not null for share;
  if not found or v_plan.control_revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'SUBSCRIPTION_PLAN_CHANGED';
  end if;
  if p_mode = 'paid' then
    if v_plan.price_minor = 0 or p_paid_amount_minor is distinct from v_plan.price_minor
      or v_reference is null or length(v_reference) not between 3 and 160 or v_reference ~ '[[:cntrl:]]'
      or p_paid_at is null or not isfinite(p_paid_at) or p_paid_at > statement_timestamp() then
      raise exception using errcode = '22023', message = 'SUBSCRIPTION_VERIFIED_PAYMENT_REQUIRED';
    end if;
  elsif v_reason is null or length(v_reason) < 5
      or v_reference is not null or p_paid_amount_minor is not null or p_paid_at is not null then
    raise exception using errcode = '22023', message = 'SYSTEM_COMPLIMENTARY_REASON_REQUIRED';
  end if;

  v_serial := core.allocate_system_serial();
  v_tenant := core.create_system_instance(v_name, v_serial, 'LKR', 'Asia/Colombo', v_actor);
  v_end := statement_timestamp() + coalesce(v_plan.checkout_term_days, 30) * interval '24 hours';
  select greatest(1, least(10000, coalesce((
    select e.numeric_limit from billing.plan_entitlements e
    where e.plan_code = v_plan.code and e.entitlement_code = 'users' and e.enabled
  ), 5)))::integer into v_seats;
  insert into billing.tenant_subscriptions (tenant_id, plan_code, status, seats, current_period_ends_at)
  values (v_tenant, v_plan.code, 'active', v_seats, v_end);
  insert into billing.organization_orders (tenant_id, signup_email) values (v_tenant, v_email);
  insert into billing.organization_activations
    (tenant_id, plan_code, amount_minor, currency_code, signup_email, payment_reference, activated_by)
  values (v_tenant, v_plan.code, coalesce(p_paid_amount_minor, 0), 'LKR', v_email, v_reference, v_actor);
  insert into billing.system_owner_handover_targets
    (id, tenant_id, serial, username, recipient_email, actor_id, source, request_id, request_payload)
  values (v_target_id, v_tenant, v_serial, billing.reserve_system_username(v_name, v_serial, v_target_id),
    v_email, v_actor, 'operator', p_request_id, v_payload)
  returning * into v_target;
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id, after_context)
  values (v_tenant, v_actor, p_request_id, 'system.created', 'tenant', v_tenant,
    jsonb_build_object('system_serial', v_serial, 'plan', v_plan.code, 'mode', p_mode,
      'amount_minor', coalesce(p_paid_amount_minor, 0), 'paid_at', p_paid_at, 'reason', v_reason,
      'term_ends_at', v_end));
  return billing.system_owner_status(v_target);
end;
$$;

create function api.platform_system_details(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return (select billing.system_owner_status(t)
    from billing.system_owner_handover_targets t where t.tenant_id = p_tenant_id
    order by (t.source = 'cutover') desc limit 1);
end;
$$;

create function billing.stage_system_owner_cutover(p_tenant_id uuid, p_actor_id uuid, p_recipient_email text)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_tenant core.tenants;
  v_target billing.system_owner_handover_targets;
  v_email text := lower(trim(p_recipient_email));
  v_target_id uuid := gen_random_uuid();
begin
  if not billing.valid_system_owner_email(v_email) or not exists (
    select 1 from intelligence_control.operators where actor_id = p_actor_id and active and organization_manage
  ) then raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_UNAVAILABLE'; end if;
  select * into v_tenant from core.tenants where id = p_tenant_id and status in ('trial','active') for update;
  if not found or v_tenant.system_serial is null or v_tenant.primary_owner_user_id is not null then
    raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_UNAVAILABLE';
  end if;
  select * into v_target from billing.system_owner_handover_targets
    where tenant_id = p_tenant_id and source = 'cutover';
  if found then
    if v_target.recipient_email <> v_email then
      raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_CHANGED';
    end if;
    return billing.system_owner_status(v_target);
  end if;
  insert into billing.system_owner_handover_targets
    (id, tenant_id, serial, username, recipient_email, actor_id, source)
  values (v_target_id, p_tenant_id, v_tenant.system_serial,
    billing.reserve_system_username(v_tenant.name, v_tenant.system_serial, v_target_id),
    v_email, p_actor_id, 'cutover')
  returning * into v_target;
  return billing.system_owner_status(v_target);
end;
$$;

create function api.system_issue_owner_verification(p_verification_id uuid, p_actor_id uuid, p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_target billing.system_owner_handover_targets;
  v_now timestamptz := clock_timestamp();
begin
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' or not exists (
    select 1 from intelligence_control.operators where actor_id = p_actor_id and active and organization_manage
  ) then return null; end if;
  select * into v_target from billing.system_owner_handover_targets
  where id = p_verification_id and source in ('operator','cutover') and verified_at is null
    and core.organization_available(tenant_id) for update;
  if not found or exists (select 1 from billing.system_owner_verifications
      where target_id = p_verification_id and issued_at > v_now - interval '1 minute') then return null; end if;
  insert into billing.system_owner_verification_rate (singleton, window_start, sent_count)
  values (true, v_now, 1)
  on conflict (singleton) do update set
    window_start = case when billing.system_owner_verification_rate.window_start <= v_now - interval '1 hour'
      then v_now else billing.system_owner_verification_rate.window_start end,
    sent_count = case when billing.system_owner_verification_rate.window_start <= v_now - interval '1 hour'
      then 1 else billing.system_owner_verification_rate.sent_count + 1 end
  where billing.system_owner_verification_rate.window_start <= v_now - interval '1 hour'
    or billing.system_owner_verification_rate.sent_count < 120;
  if not found then return null; end if;
  delete from billing.system_owner_verifications where expires_at <= v_now;
  insert into billing.system_owner_verifications (target_id, code_hash, issued_at, expires_at)
  values (p_verification_id, p_hash, v_now, v_now + interval '10 minutes')
  on conflict (target_id) do update
  set code_hash = excluded.code_hash, issued_at = excluded.issued_at, expires_at = excluded.expires_at, attempts = 0;
  return v_target.recipient_email;
end;
$$;

create function api.system_consume_owner_verification(p_verification_id uuid, p_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_target billing.system_owner_handover_targets;
  v_attempt billing.system_owner_verifications;
  v_now timestamptz := clock_timestamp();
begin
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' then return null; end if;
  select * into v_target from billing.system_owner_handover_targets
  where id = p_verification_id and source in ('operator','cutover') and verified_at is null
    and core.organization_available(tenant_id) for update;
  if not found then return null; end if;
  select * into v_attempt from billing.system_owner_verifications
  where target_id = p_verification_id and expires_at > v_now and attempts < 5 for update;
  if not found then return null; end if;
  if v_attempt.code_hash <> p_hash then
    update billing.system_owner_verifications set attempts = attempts + 1 where target_id = p_verification_id;
    return null;
  end if;
  delete from billing.system_owner_verifications where target_id = p_verification_id;
  update billing.system_owner_handover_targets set verified_at = v_now where id = p_verification_id;
  insert into billing.subscription_handover_jobs (order_id, tenant_id) values (v_target.id, v_target.tenant_id);
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
  values (v_target.tenant_id, v_target.actor_id, v_target.id, 'system.owner_email_verified', 'tenant', v_target.tenant_id);
  return jsonb_build_object('ok', true, 'username', v_target.username);
end;
$$;

create function billing.system_registration_projection(p_tenant_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'tenant_id', t.id, 'serial', t.system_serial, 'name', t.name,
    'registration_required', not exists (select 1 from core.legal_entities e where e.tenant_id = t.id),
    'entities', coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'name', e.name, 'code', e.code,
      'branches', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'code', b.code)
        order by b.code) from core.branches b
        where b.tenant_id = t.id and b.legal_entity_id = e.id), '[]')
    ) order by e.code) from core.legal_entities e where e.tenant_id = t.id), '[]')
  )
  from core.tenants t where t.id = p_tenant_id;
$$;

create function api.system_registration_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select billing.system_registration_projection(t.id)
  from core.tenants t where t.primary_owner_user_id = auth.uid() and t.system_serial is not null
    and core.has_permission(t.id, 'core.tenant.manage', null, null)
  order by t.id limit 1;
$$;

create function api.system_register_entities(p_tenant_id uuid, p_entities jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_tenant core.tenants;
  v_prior jsonb;
  v_entity jsonb;
  v_branch jsonb;
  v_entity_id uuid;
  v_name text;
  v_code text;
begin
  select * into v_tenant from core.tenants
  where id = p_tenant_id and system_serial is not null and primary_owner_user_id = v_actor for update;
  if not found or not core.has_permission(p_tenant_id, 'core.tenant.manage', null, null) then
    raise exception using errcode = '42501', message = 'SYSTEM_REGISTRATION_FORBIDDEN';
  end if;
  if p_request_id is null or p_entities is null or jsonb_typeof(p_entities) <> 'array' then
    raise exception using errcode = '22023', message = 'INVALID_SYSTEM_REGISTRATION';
  end if;
  if jsonb_array_length(p_entities) not between 1 and 20 then
    raise exception using errcode = '22023', message = 'INVALID_SYSTEM_REGISTRATION';
  end if;
  select payload into v_prior from core.system_registration_requests
    where tenant_id = p_tenant_id and request_id = p_request_id;
  if found then
    if v_prior is distinct from p_entities then
      raise exception using errcode = '40001', message = 'SYSTEM_REQUEST_CHANGED';
    end if;
    return billing.system_registration_projection(p_tenant_id);
  end if;
  for v_entity in select value from jsonb_array_elements(p_entities) loop
    if jsonb_typeof(v_entity) <> 'object' or jsonb_typeof(v_entity->'branches') is distinct from 'array' then
      raise exception using errcode = '22023', message = 'INVALID_SYSTEM_REGISTRATION';
    end if;
    if jsonb_array_length(v_entity->'branches') not between 1 and 20 then
      raise exception using errcode = '22023', message = 'INVALID_SYSTEM_REGISTRATION';
    end if;
    if v_entity ? 'id' then
      select id into v_entity_id from core.legal_entities
      where tenant_id = p_tenant_id and status = 'active' and id::text = v_entity->>'id';
      if not found then raise exception using errcode = '22023', message = 'SYSTEM_ENTITY_UNAVAILABLE'; end if;
    else
      v_name := nullif(trim(v_entity->>'name'), '');
      v_code := nullif(upper(trim(v_entity->>'code')), '');
      if v_name is null or length(v_name) not between 2 and 180 or v_name ~ '[[:cntrl:]]'
        or v_code is null or v_code !~ '^[A-Z0-9][A-Z0-9_-]{1,19}$' then
        raise exception using errcode = '22023', message = 'INVALID_SYSTEM_ENTITY';
      end if;
      insert into core.legal_entities (tenant_id, name, code, currency_code, timezone, created_by)
      values (p_tenant_id, v_name, v_code, v_tenant.default_currency_code, v_tenant.timezone, v_actor)
      returning id into v_entity_id;
    end if;
    for v_branch in select value from jsonb_array_elements(v_entity->'branches') loop
      v_name := nullif(trim(v_branch->>'name'), '');
      v_code := nullif(upper(trim(v_branch->>'code')), '');
      if jsonb_typeof(v_branch) <> 'object'
        or v_name is null or length(v_name) not between 2 and 160 or v_name ~ '[[:cntrl:]]'
        or v_code is null or v_code !~ '^[A-Z0-9][A-Z0-9_-]{1,19}$' then
        raise exception using errcode = '22023', message = 'INVALID_SYSTEM_BRANCH';
      end if;
      insert into core.branches (tenant_id, legal_entity_id, name, code, timezone, created_by)
      values (p_tenant_id, v_entity_id, v_name, v_code, v_tenant.timezone, v_actor);
    end loop;
  end loop;
  insert into core.system_registration_requests (tenant_id, request_id, actor_id, payload)
  values (p_tenant_id, p_request_id, v_actor, p_entities);
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id, after_context)
  values (p_tenant_id, v_actor, p_request_id, 'system.entities_registered', 'tenant', p_tenant_id,
    jsonb_build_object('entity_batch_size', jsonb_array_length(p_entities)));
  return billing.system_registration_projection(p_tenant_id);
end;
$$;



create function billing.system_subscription(p_tenant_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from billing.subscription_checkout_orders o
    where o.tenant_id = p_tenant_id and o.kind = 'initial' and o.status = 'paid')
  or exists (select 1 from billing.system_owner_handover_targets t
    where t.tenant_id = p_tenant_id and t.source = 'operator');
$$;

create function billing.system_owner_target_ready(p_target billing.system_owner_handover_targets)
returns boolean language sql stable set search_path = '' as $$
  select p_target.verified_at is not null and core.organization_available(p_target.tenant_id)
    and (p_target.source = 'cutover' or exists (
      select 1 from billing.organization_activations a
      where a.tenant_id = p_target.tenant_id and a.signup_email = p_target.recipient_email
    ));
$$;

create or replace function billing.checkout_settle(
  p_order billing.subscription_checkout_orders, p_actor uuid, p_reference text,
  p_amount bigint, p_bank_paid_at timestamptz, p_reason text, p_exception text
)
returns billing.subscription_checkout_orders language plpgsql set search_path = '' as $$
declare
  v_order billing.subscription_checkout_orders := p_order;
  v_tenant uuid := p_order.tenant_id;
  v_entity uuid;
  v_role uuid;
  v_now timestamptz := statement_timestamp();
  v_period_end timestamptz;
begin
  if v_order.kind = 'initial' then
    v_period_end := v_now + v_order.term_days * interval '24 hours';
    if v_order.system_serial is not null then
      v_tenant := core.create_system_instance(v_order.organization_name, v_order.system_serial,
        v_order.currency_code, 'Asia/Colombo', p_actor);
    else
      -- Existing quotes keep their original identity and initial workspace.
      insert into core.tenants (name, slug, status, timezone, default_currency_code, created_by)
      values (v_order.organization_name, left(v_order.username, 45) || '-' || left(v_order.id::text, 8),
        'active', 'Asia/Colombo', v_order.currency_code, p_actor)
      returning id into v_tenant;
      insert into core.legal_entities (tenant_id, name, code, currency_code, timezone, created_by)
      values (v_tenant, v_order.organization_name, 'MAIN', v_order.currency_code, 'Asia/Colombo', p_actor)
      returning id into v_entity;
      insert into core.branches (tenant_id, legal_entity_id, name, code, timezone, created_by)
      values (v_tenant, v_entity, 'Head office', 'HQ', 'Asia/Colombo', p_actor);
      insert into core.roles (tenant_id, code, name, description, requires_mfa, is_system)
      values (v_tenant, 'tenant_owner', 'Tenant owner', 'Administrator for this organization.', true, true)
      returning id into v_role;
      insert into core.role_permissions (tenant_id, role_id, permission_code)
      select v_tenant, v_role, code from core.permissions;
    end if;
    insert into billing.tenant_subscriptions
      (tenant_id, plan_code, status, seats, current_period_ends_at)
    values (v_tenant, v_order.plan_code, 'active', v_order.seats, v_period_end);
    insert into billing.organization_orders (tenant_id, signup_email)
    values (v_tenant, v_order.signup_email);
    insert into billing.organization_activations
      (tenant_id, plan_code, amount_minor, currency_code, signup_email, payment_reference, activated_by)
    values (v_tenant, v_order.plan_code, v_order.price_minor, v_order.currency_code,
      v_order.signup_email, p_reference, p_actor);
  else
    -- The tenant lock serializes extension and protects the lifecycle lock.
    perform 1 from core.tenants where id = v_tenant and status in ('trial', 'active') for update;
    if not found then
      raise exception using errcode = '42501', message = 'ORGANIZATION_UNAVAILABLE';
    end if;
    if p_reference is not null then
      perform billing.reserve_subscription_payment_reference(p_reference);
    end if;
    update billing.tenant_subscriptions
    set status = 'active',
        current_period_ends_at = greatest(v_now, current_period_ends_at)
          + v_order.term_days * interval '24 hours',
        version = version + 1, updated_at = v_now
    where tenant_id = v_tenant and plan_code = v_order.plan_code
      and status in ('active', 'past_due')
    returning current_period_ends_at into v_period_end;
    if not found then
      raise exception using errcode = '40001', message = 'SUBSCRIPTION_RENEWAL_CHANGED';
    end if;
  end if;

  update billing.subscription_checkout_orders
  set status = 'paid', tenant_id = v_tenant, paid_at = v_now, term_ends_at = v_period_end,
      verified_reference = p_reference, verified_amount_minor = p_amount,
      verified_paid_at = p_bank_paid_at, reviewed_by = p_actor, reviewed_at = v_now,
      decision_reason = p_reason, exception_reason = p_exception
  where id = v_order.id returning * into v_order;
  update billing.subscription_checkout_events set tenant_id = v_tenant
    where order_id = v_order.id and tenant_id is null;
  update billing.subscription_checkout_replays set tenant_id = v_tenant
    where order_id = v_order.id and tenant_id is null;
  if v_order.kind = 'initial' then
    insert into billing.subscription_handover_jobs (order_id, tenant_id)
    values (v_order.id, v_tenant);
  end if;
  insert into billing.subscription_checkout_events (tenant_id, order_id, actor_id, event_type, details)
  values (v_tenant, v_order.id, p_actor, 'payment_confirmed',
    jsonb_build_object('price_minor', v_order.price_minor, 'bank_reference', p_reference,
      'verified_amount_minor', p_amount, 'bank_paid_at', p_bank_paid_at,
      'reason', p_reason, 'exception', p_exception, 'term_ends_at', v_period_end));
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id, after_context)
  values (v_tenant, p_actor, gen_random_uuid(),
    case v_order.kind when 'initial' then 'organization.activated' else 'organization.subscription_renewed' end,
    'tenant', v_tenant, jsonb_build_object(
      'plan_code', v_order.plan_code, 'amount_minor', v_order.price_minor,
      'currency_code', v_order.currency_code, 'order_id', v_order.id, 'term_ends_at', v_period_end));
  return v_order;
end;
$$;

create or replace function billing.checkout_expired(p_tenant_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from billing.tenant_subscriptions s
    where s.tenant_id = p_tenant_id and s.current_period_ends_at <= statement_timestamp()
      and billing.system_subscription(s.tenant_id)
  );
$$;

create or replace function api.subscription_checkout_access()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_email text := billing.checkout_current_buyer_email(v_actor);
  v_enabled boolean;
  v_has_workspaces boolean;
  v_has_memberships boolean;
  v_paused jsonb;
begin
  select enabled into v_enabled from billing.subscription_checkout_settings;
  select exists (select 1 from core.memberships m where m.user_id = v_actor
    and m.status = 'active' and core.organization_business_available(m.tenant_id)),
    exists (select 1 from core.memberships m where m.user_id = v_actor
      and m.status in ('active', 'invited'))
  into v_has_workspaces, v_has_memberships;
  select coalesce(jsonb_agg(m.tenant_id order by m.tenant_id), '[]') into v_paused
  from core.memberships m where m.user_id = v_actor and m.status = 'active'
    and core.organization_available(m.tenant_id) and billing.checkout_expired(m.tenant_id);
  return jsonb_build_object(
    'enabled', v_enabled,
    'requires_checkout', v_email is not null and billing.checkout_required()
      and not v_has_memberships
      and not api.platform_organization_assignment(),
    'email', v_email,
    'email_verified', billing.checkout_verified_email(v_actor) is not null,
    'workspace_paused', not v_has_workspaces and v_paused <> '[]',
    'paused_tenant_ids', v_paused,
    'renewable', coalesce((select jsonb_agg(jsonb_build_object(
      'tenant_id', s.tenant_id, 'organization_name', t.name,
      'plan_code', s.plan_code, 'term_ends_at', s.current_period_ends_at
    ) order by t.name, t.id)
    from billing.tenant_subscriptions s join core.tenants t on t.id = s.tenant_id
    join billing.plans p on p.code = s.plan_code
    where v_enabled and p.status = 'active' and p.checkout_published
      and billing.system_subscription(s.tenant_id)
      and billing.checkout_can_renew(t.id, v_actor)), '[]')
  );
end;
$$;

create or replace function api.subscription_create_order(
  p_plan_code text, p_expected_revision bigint, p_organization_name text, p_request_id uuid,
  p_renewal_tenant_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_name text := nullif(trim(p_organization_name), '');
  v_kind text := case when p_renewal_tenant_id is null then 'initial' else 'renewal' end;
  v_email text;
  v_username text;
  v_order_id uuid := gen_random_uuid();
  v_order billing.subscription_checkout_orders;
  v_replay billing.subscription_checkout_replays;
  v_replay_revision bigint;
  v_plan billing.plans;
  v_settings billing.subscription_checkout_settings;
  v_seats integer;
begin
  select * into v_settings from billing.subscription_checkout_settings;
  if not v_settings.enabled or v_actor is null or not core.organization_account_ready(v_actor) then
    raise exception using errcode = '42501', message = 'SUBSCRIPTION_CHECKOUT_UNAVAILABLE';
  end if;
  if p_request_id is null or p_plan_code is null or p_expected_revision is null then
    raise exception using errcode = '22023', message = 'INVALID_SUBSCRIPTION_ORDER';
  end if;
  -- Serializes creation across requests and sessions, including retries from
  -- multiple owners of a renewal. Also serialize idempotency across kinds.
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text, 45110));
  if v_kind = 'renewal' then
    perform pg_advisory_xact_lock(hashtextextended(p_renewal_tenant_id::text, 45111));
  end if;
  select * into v_order from billing.subscription_checkout_orders
    where buyer_id = v_actor and request_id = p_request_id for update;
  if found then
    v_replay_revision := v_order.plan_revision;
  else
    select * into v_replay from billing.subscription_checkout_replays
      where buyer_id = v_actor and request_id = p_request_id;
    if found then
      select * into v_order from billing.subscription_checkout_orders where id = v_replay.order_id for update;
      v_replay_revision := v_replay.plan_revision;
    end if;
  end if;
  if v_order.id is not null then
    if v_order.kind <> v_kind or v_order.plan_code <> p_plan_code
      or v_replay_revision <> p_expected_revision
      or (v_kind = 'initial' and v_order.organization_name is distinct from v_name)
      or (v_kind = 'renewal' and v_order.tenant_id is distinct from p_renewal_tenant_id) then
      raise exception using errcode = '40001', message = 'SUBSCRIPTION_REQUEST_CHANGED';
    end if;
    return billing.checkout_order_projection(v_order);
  end if;

  if v_kind = 'initial' then
    v_email := billing.checkout_verified_email(v_actor);
    if v_email is null then
      raise exception using errcode = '42501', message = 'SUBSCRIPTION_EMAIL_REQUIRED';
    end if;
    if v_name is null or length(v_name) not between 2 and 160 or v_name ~ '[[:cntrl:]]' then
      raise exception using errcode = '22023', message = 'INVALID_ORGANIZATION';
    end if;
  else
    if not billing.checkout_can_renew(p_renewal_tenant_id, v_actor) then
      raise exception using errcode = '42501', message = 'SUBSCRIPTION_RENEWAL_FORBIDDEN';
    end if;
    select t.name, a.signup_email, s.seats into v_name, v_email, v_seats
    from core.tenants t
    join billing.tenant_subscriptions s on s.tenant_id = t.id
    join billing.organization_activations a on a.tenant_id = t.id
    where t.id = p_renewal_tenant_id and s.plan_code = p_plan_code and s.status in ('active', 'past_due')
      and billing.system_subscription(t.id);
    if not found then
      raise exception using errcode = '40001', message = 'SUBSCRIPTION_RENEWAL_CHANGED';
    end if;
  end if;

  select * into v_order from billing.subscription_checkout_orders
  where status in ('awaiting_payment', 'under_review', 'payment_rejected')
    and ((kind = 'initial' and v_kind = 'initial' and buyer_id = v_actor)
      or (kind = 'renewal' and v_kind = 'renewal' and tenant_id = p_renewal_tenant_id))
  for update;
  if found then
    if v_order.status = 'under_review' or v_order.expires_at > statement_timestamp() then
      if v_order.buyer_id = v_actor and v_order.plan_code = p_plan_code
        and (v_kind = 'renewal' or v_order.organization_name = v_name) then
        insert into billing.subscription_checkout_replays
          (buyer_id, request_id, order_id, tenant_id, plan_revision)
        values (v_actor, p_request_id, v_order.id, v_order.tenant_id, p_expected_revision);
        return billing.checkout_order_projection(v_order);
      end if;
      raise exception using errcode = '40001', message = 'SUBSCRIPTION_ORDER_OPEN';
    end if;
    update billing.subscription_checkout_orders set status = 'cancelled' where id = v_order.id;
    insert into billing.subscription_checkout_events (tenant_id, order_id, actor_id, event_type)
    values (v_order.tenant_id, v_order.id, v_actor, 'expired_order_replaced');
  end if;

  select * into v_plan from billing.plans
  where code = p_plan_code and status = 'active' and checkout_published for share;
  if not found or v_plan.control_revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'SUBSCRIPTION_PLAN_CHANGED';
  end if;
  if v_plan.price_minor > 0 and v_settings.bank is null then
    raise exception using errcode = '55000', message = 'SUBSCRIPTION_BANK_UNAVAILABLE';
  end if;
  if v_kind = 'initial' then
    v_username := billing.reserve_subscription_username(v_name, v_order_id);
    select greatest(1, least(10000, coalesce(
      (select e.numeric_limit from billing.plan_entitlements e
        where e.plan_code = v_plan.code and e.entitlement_code = 'users' and e.enabled), 5)))::integer
    into v_seats;
  end if;
  insert into billing.subscription_checkout_orders (
    id, buyer_id, request_id, signup_email, organization_name, username, tenant_id,
    kind, plan_code, plan_name, plan_revision, price_minor, currency_code, term_days, seats, bank, expires_at
  ) values (
    v_order_id, v_actor, p_request_id, v_email, v_name, v_username, p_renewal_tenant_id,
    v_kind, v_plan.code, v_plan.name, v_plan.control_revision, v_plan.price_minor,
    v_plan.price_currency_code, v_plan.checkout_term_days, v_seats,
    case when v_plan.price_minor > 0 then v_settings.bank end,
    statement_timestamp() + interval '7 days'
  ) returning * into v_order;
  insert into billing.subscription_checkout_events (tenant_id, order_id, actor_id, event_type)
  values (v_order.tenant_id, v_order.id, v_actor, 'order_created');
  if v_order.price_minor = 0 then
    v_order := billing.checkout_settle(v_order, v_actor, null, 0, null, 'zero_cost', null);
  end if;
  return billing.checkout_order_projection(v_order);
end;
$$;

create or replace function billing.checkout_order_projection(p_order billing.subscription_checkout_orders, p_operator boolean default false)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_order.id, 'kind', p_order.kind,
    'status', case when p_order.expires_at <= statement_timestamp()
      and p_order.status in ('awaiting_payment', 'payment_rejected') then 'expired' else p_order.status end,
    'plan_code', p_order.plan_code, 'plan_name', p_order.plan_name,
    'plan_revision', p_order.plan_revision, 'price_minor', p_order.price_minor,
    'currency_code', p_order.currency_code, 'term_days', p_order.term_days,
    'organization_name', p_order.organization_name, 'username', p_order.username, 'tenant_id', p_order.tenant_id,
    'transfer_reference', p_order.transfer_reference, 'bank', p_order.bank,
    'system_serial', coalesce(p_order.system_serial,
      (select t.system_serial from core.tenants t where t.id = p_order.tenant_id)),
    'created_at', p_order.created_at, 'expires_at', p_order.expires_at,
    'paid_at', p_order.paid_at, 'term_ends_at', p_order.term_ends_at,
    'handover_status', case when j.status = 'sent' and j.credential_expires_at <= statement_timestamp()
      then 'expired' else j.status end,
    'handover_expires_at', case when j.status = 'sent' then j.credential_expires_at end,
    'handover_can_reissue', coalesce(j.status in ('failed','sent')
      and j.updated_at <= statement_timestamp() - interval '1 minute'
      and core.organization_available(j.tenant_id), false)
  ) || case when p_operator then jsonb_build_object(
    'signup_email', p_order.signup_email, 'verified_reference', p_order.verified_reference,
    'verified_amount_minor', p_order.verified_amount_minor, 'verified_paid_at', p_order.verified_paid_at,
    'reviewed_at', p_order.reviewed_at, 'decision_reason', p_order.decision_reason,
    'exception_reason', p_order.exception_reason, 'handover_error', j.last_error,
    'handover_attempts', j.attempts
  ) else '{}' end
  from (select 1) base left join billing.subscription_handover_jobs j on j.order_id = p_order.id;
$$;

create or replace function api.platform_list_organizations(
  p_query text default '', p_offset integer default 0, p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  if p_offset is null or p_offset < 0 or length(coalesce(p_query, '')) > 160 then
    raise exception using errcode = '22023', message = 'INVALID_ORGANIZATION_QUERY';
  end if;
  return coalesce((select jsonb_agg(
    jsonb_build_object(
      'id', t.id, 'name', t.name, 'slug', t.slug, 'status', t.status,
      'plan_code', s.plan_code, 'subscription_status', s.status,
      'signup_email', coalesce(o.signup_email, a.signup_email), 'activated_at', a.activated_at,
      'paid_minor', a.amount_minor, 'paid_currency_code', a.currency_code,
      'offer_minor', offer.price_minor, 'offer_currency_code', offer.currency_code,
      'offer_expires_at', offer.expires_at,
      'price_minor', coalesce(offer.price_minor, p.price_minor), 'price_currency_code', p.price_currency_code,
      'checkout_managed', exists (select 1 from billing.subscription_checkout_orders initial_order
        where initial_order.tenant_id = t.id and initial_order.kind = 'initial' and initial_order.status = 'paid'),
      'term_ends_at', s.current_period_ends_at, 'term_expired', billing.checkout_expired(t.id),
      'system_serial', t.system_serial, 'system_username', owner_target.username,
      'system_owner_status', case when owner_target.id is not null then billing.system_owner_status(owner_target)->>'owner_status' end
    ) order by t.name, t.id)
  from (
    select * from core.tenants
    where (p_tenant_id is null or id = p_tenant_id)
      and (position(lower(trim(coalesce(p_query, ''))) in lower(name)) > 0
        or position(lower(trim(coalesce(p_query, ''))) in slug) > 0)
    order by name, id offset p_offset limit 51
  ) t
  left join billing.tenant_subscriptions s on s.tenant_id = t.id
  left join billing.plans p on p.code = s.plan_code and p.status = 'active'
  left join lateral (
    select h.* from billing.system_owner_handover_targets h where h.tenant_id = t.id
    order by (h.source = 'cutover') desc limit 1
  ) owner_target on true
  left join billing.organization_orders o on o.tenant_id = t.id
  left join billing.organization_activations a on a.tenant_id = t.id
  left join lateral billing.current_organization_offer(t.id, s.plan_code) offer on p.code is not null), '[]'::jsonb);
end;
$$;

create or replace function core.organization_protect_login_alias()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_username text;
  v_metadata jsonb;
  v_order billing.subscription_checkout_orders;
  v_target billing.system_owner_handover_targets;
begin
  if right(lower(coalesce(new.email, '')), 21) = '@admin.jentra.invalid' then
    v_username := split_part(lower(new.email), '@', 1);
    perform pg_advisory_xact_lock(hashtextextended(v_username, 45109));
    select raw_app_meta_data into v_metadata from auth.users where id = new.id;
    if found and v_metadata->>'managed_org_admin' is distinct from 'true' then
      raise exception using errcode = '42501', message = 'Managed login address is reserved.';
    end if;
    select * into v_target from billing.system_owner_handover_targets where username = v_username;
    if found and (v_target.verified_at is null
        or v_metadata->>'checkout_order_id' is distinct from v_target.id::text
        or v_metadata->>'provisioned_tenant_id' is distinct from v_target.tenant_id::text) then
      raise exception using errcode = '23505', message = 'SYSTEM_USERNAME_UNAVAILABLE';
    end if;
    select * into v_order from billing.subscription_checkout_orders where username = v_username;
    if found and (v_order.status <> 'paid'
        or v_metadata->>'checkout_order_id' is distinct from v_order.id::text
        or v_metadata->>'provisioned_tenant_id' is distinct from v_order.tenant_id::text) then
      raise exception using errcode = '23505', message = 'SUBSCRIPTION_USERNAME_UNAVAILABLE';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.raw_app_meta_data->>'managed_org_admin' = 'true'
      and new.email is distinct from old.email then
    raise exception using errcode = '42501', message = 'Managed login address cannot be changed.';
  end if;
  return new;
end;
$$;

create or replace function core.bootstrap_tenant_impl(
  p_name text, p_slug text, p_legal_entity_name text, p_legal_entity_code text,
  p_branch_name text, p_branch_code text, p_timezone text default 'Asia/Colombo',
  p_currency_code text default 'LKR', p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from auth.users where id = auth.uid()
      and raw_app_meta_data->>'managed_org_admin' = 'true') then
    raise exception using errcode = '42501', message = 'SYSTEM_BOOTSTRAP_FORBIDDEN';
  end if;
  if billing.checkout_required() then
    raise exception using errcode = '42501', message = 'SUBSCRIPTION_CHECKOUT_REQUIRED';
  end if;
  return core.bootstrap_tenant_pre_checkout_impl(
    p_name, p_slug, p_legal_entity_name, p_legal_entity_code, p_branch_name,
    p_branch_code, p_timezone, p_currency_code, p_idempotency_key);
end;
$$;

create or replace function api.subscription_claim_handover()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_target billing.system_owner_handover_targets;
  v_job billing.subscription_handover_jobs;
begin
  update billing.subscription_handover_jobs
  set status = 'failed', lease_token = null, lease_until = null, updated_at = v_now,
      last_error = case when credential_expires_at <= v_now then 'credential_expired' else 'retry_limit_reached' end
  where status in ('pending','processing') and (lease_until is null or lease_until <= v_now)
    and (credential_expires_at <= v_now or attempts >= 5)
    and core.organization_available(tenant_id);

  delete from billing.subscription_handover_payloads p where p.expires_at <= v_now
    or not exists (select 1 from billing.subscription_handover_jobs j
      where j.generation = p.generation and j.status in ('pending','processing'));
  delete from billing.subscription_password_reset_grants where expires_at <= v_now;

  select j.* into v_job
  from billing.subscription_handover_jobs j
  join billing.system_owner_handover_targets t on t.id = j.order_id
  where billing.system_owner_target_ready(t)
    and j.attempts < 5 and (j.credential_expires_at is null or j.credential_expires_at > v_now)
    and ((j.status = 'pending' and j.next_attempt_at <= v_now)
      or (j.status = 'processing' and j.lease_until <= v_now))
  order by j.next_attempt_at, j.order_id limit 1 for update of j skip locked;
  if not found then return null; end if;

  update billing.subscription_handover_jobs
  set status = 'processing', lease_token = gen_random_uuid(), lease_until = v_now + interval '3 minutes',
      attempts = attempts + 1, updated_at = v_now
  where order_id = v_job.order_id returning * into v_job;
  select * into v_target from billing.system_owner_handover_targets where id = v_job.order_id;
  return jsonb_build_object(
    'order_id', v_target.id, 'tenant_id', v_target.tenant_id, 'username', v_target.username,
    'organization_name', (select name from core.tenants where id = v_target.tenant_id),
    'system_serial', v_target.serial, 'source', v_target.source, 'email', v_target.recipient_email,
    'lease_token', v_job.lease_token, 'generation', v_job.generation,
    'ciphertext', (select p.ciphertext from billing.subscription_handover_payloads p where p.generation = v_job.generation),
    'credential_expires_at', v_job.credential_expires_at
  );
end;
$$;

create or replace function api.subscription_handover_identity(p_order_id uuid, p_lease_token uuid, p_generation uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id', u.id,
    'password_prepared', coalesce(u.raw_app_meta_data->>'jentra_handover_generation' = j.generation::text, false)
  )
  from billing.subscription_handover_jobs j
  join billing.system_owner_handover_targets t on t.id = j.order_id
  left join auth.users u on u.email = t.username || '@admin.jentra.invalid'
    and u.deleted_at is null and u.raw_app_meta_data->>'managed_org_admin' = 'true'
    and u.raw_app_meta_data->>'checkout_order_id' = t.id::text
    and u.raw_app_meta_data->>'provisioned_tenant_id' = t.tenant_id::text
  where j.order_id = p_order_id and j.status = 'processing' and j.lease_token = p_lease_token
    and j.generation = p_generation and j.lease_until > statement_timestamp()
    and j.credential_expires_at > statement_timestamp()
    and billing.system_owner_target_ready(t);
$$;

create or replace function api.subscription_register_handover(
  p_order_id uuid, p_lease_token uuid, p_generation uuid, p_user_id uuid
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_job billing.subscription_handover_jobs;
  v_target billing.system_owner_handover_targets;
  v_role uuid;
  v_membership uuid;
begin
  select * into v_job from billing.subscription_handover_jobs
  where order_id = p_order_id and status = 'processing' and lease_token = p_lease_token
    and generation = p_generation and lease_until > v_now and credential_expires_at > v_now
  for update;
  if not found then return false; end if;

  select * into v_target from billing.system_owner_handover_targets t
  where t.id = p_order_id and billing.system_owner_target_ready(t);
  if not found or not exists (
    select 1 from auth.users u
    where u.id = p_user_id and u.email = v_target.username || '@admin.jentra.invalid' and u.deleted_at is null
      and u.raw_app_meta_data->>'managed_org_admin' = 'true'
      and u.raw_app_meta_data->>'checkout_order_id' = v_target.id::text
      and u.raw_app_meta_data->>'provisioned_tenant_id' = v_target.tenant_id::text
      and u.raw_app_meta_data->>'jentra_handover_generation' = v_job.generation::text
  ) then return false; end if;

  if v_job.user_id is not null then
    return v_job.user_id = p_user_id and exists (
      select 1 from core.organization_administrator_logins l
      where l.user_id = p_user_id and l.checkout_order_id = p_order_id and l.must_change_password
        and l.temporary_password_expires_at = v_job.credential_expires_at
    );
  end if;


  insert into core.organization_administrator_logins (
    user_id, tenant_id, username, checkout_order_id, temporary_password_expires_at, password_changed_at
  ) values (
    p_user_id, v_target.tenant_id, v_target.username, p_order_id, v_job.credential_expires_at, v_now
  );
  insert into core.organization_account_recovery (user_id, email, verified_at, password_changed_at)
    values (p_user_id, v_target.recipient_email, v_now, v_now);
  if v_target.source <> 'cutover' then
    select id into strict v_role from core.roles
    where tenant_id = v_target.tenant_id and code = 'tenant_owner' and is_system;
    insert into core.memberships (tenant_id, user_id, invited_by, joined_at)
      values (v_target.tenant_id, p_user_id, v_target.actor_id, v_now) returning id into v_membership;
    insert into core.role_assignments (tenant_id, membership_id, role_id, created_by)
      values (v_target.tenant_id, v_membership, v_role, v_target.actor_id);
    if v_target.serial is not null then
      update core.tenants set primary_owner_user_id = p_user_id
      where id = v_target.tenant_id and system_serial = v_target.serial
        and (primary_owner_user_id is null or primary_owner_user_id = p_user_id);
      if not found then
        raise exception using errcode = '40001', message = 'SYSTEM_OWNER_CHANGED';
      end if;
    end if;
  end if;
  update billing.subscription_handover_jobs set user_id = p_user_id, updated_at = v_now
    where order_id = p_order_id;
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (v_target.tenant_id, v_target.actor_id, p_order_id, 'organization.administrator_created',
      case when v_membership is null then 'administrator' else 'membership' end, coalesce(v_membership, p_user_id));
  return true;
end;
$$;

create or replace function api.subscription_finish_handover(
  p_order_id uuid, p_lease_token uuid, p_generation uuid, p_message_id text
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_job billing.subscription_handover_jobs;
  v_target billing.system_owner_handover_targets;
begin
  update billing.subscription_handover_jobs
  set status = 'sent', lease_token = null, lease_until = null,
      last_error = null, sent_message_id = p_message_id, updated_at = v_now
  where order_id = p_order_id and status = 'processing' and lease_token = p_lease_token
    and generation = p_generation and lease_until > v_now and user_id is not null
    and credential_expires_at > v_now and length(p_message_id) between 1 and 200
  returning * into v_job;
  if not found then return false; end if;
  delete from billing.subscription_handover_payloads where generation = p_generation;

  update core.organization_administrator_logins set handover_sent_at = v_now
    where user_id = v_job.user_id and checkout_order_id = p_order_id and must_change_password;
  select * into v_target from billing.system_owner_handover_targets where id = p_order_id;
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (v_target.tenant_id, v_target.actor_id, v_job.generation, 'organization.administrator_handover',
      'administrator', v_job.user_id);
  return true;
end;
$$;

create or replace function core.organization_provisioning_recipient(p_actor_id uuid, p_tenant_id uuid, p_signup_email text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_email text;
begin
  if not exists (select 1 from intelligence_control.operators
    where actor_id = p_actor_id and active and organization_manage) then
    raise exception using errcode = '42501', message = 'Platform organization operator required.';
  end if;
  if exists (select 1 from billing.system_owner_handover_targets t where t.tenant_id = p_tenant_id and t.serial is not null) then
    raise exception using errcode = '42501', message = 'Use the system owner handover.';
  end if;
  select signup_email into v_email from billing.organization_activations where tenant_id = p_tenant_id;
  if v_email is null or not core.organization_available(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Confirmed activation required.';
  end if;
  if exists (select 1 from billing.subscription_handover_jobs j
    where j.tenant_id = p_tenant_id and not exists (
      select 1 from core.organization_administrator_logins l where l.checkout_order_id = j.order_id
    )) then
    raise exception using errcode = '42501', message = 'Automatic handover must register the first administrator.';
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

create function api.platform_reissue_system_owner(p_tenant_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_target billing.system_owner_handover_targets;
  v_job billing.subscription_handover_jobs;
begin
  perform intelligence_control.operator_required('organization');
  select * into v_target from billing.system_owner_handover_targets
    where tenant_id = p_tenant_id order by (source = 'cutover') desc limit 1;
  if not found then raise exception using errcode = '42501', message = 'HANDOVER_UNAVAILABLE'; end if;
  if v_target.source = 'checkout' then
    perform api.subscription_reissue_handover(v_target.id);
    return;
  end if;
  select * into v_job from billing.subscription_handover_jobs where order_id = v_target.id for update;
  if not found or not core.organization_available(v_target.tenant_id) or v_job.status not in ('failed','sent')
      or v_job.updated_at > v_now - interval '1 minute' then
    raise exception using errcode = '22023', message = 'HANDOVER_UNAVAILABLE';
  end if;
  if v_job.user_id is not null then
    update core.organization_administrator_logins
    set handover_sent_at = null, handover_requested_at = v_now,
        temporary_password_expires_at = v_now, password_changed_at = v_now
    where user_id = v_job.user_id and checkout_order_id = v_target.id and must_change_password;
    if not found then raise exception using errcode = '22023', message = 'HANDOVER_UNAVAILABLE'; end if;
    update core.organization_account_recovery set password_changed_at = v_now where user_id = v_job.user_id;
  end if;

  update billing.subscription_handover_jobs set status = 'pending', generation = gen_random_uuid(),
    attempts = 0, lease_token = null, lease_until = null,
    credential_expires_at = null, next_attempt_at = v_now, reissue_requested_at = v_now,
    updated_at = v_now, sent_message_id = null, last_error = null where order_id = v_target.id;
  delete from billing.subscription_handover_payloads where generation = v_job.generation;

  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (v_target.tenant_id, auth.uid(), gen_random_uuid(), 'organization.administrator_handover_requested',
      'system_owner_handover', v_target.id);
end;
$$;

revoke all on function core.allocate_system_serial(), core.keep_system_serial(),
  core.check_primary_system_owner_grant(),
  core.create_system_instance(text,text,text,text,uuid),
  billing.reserve_system_username(text,text,uuid), billing.set_checkout_system_serial(),
  billing.attach_checkout_handover_target(), billing.valid_system_owner_email(text),
  billing.system_owner_status(billing.system_owner_handover_targets),
  billing.stage_system_owner_cutover(uuid,uuid,text), billing.system_registration_projection(uuid),
  billing.system_subscription(uuid), billing.system_owner_target_ready(billing.system_owner_handover_targets)
from public, anon, authenticated, service_role;

revoke all on function api.platform_create_system(text,text,text,bigint,uuid,text,text,bigint,timestamptz,text),
  api.platform_system_details(uuid), api.system_registration_status(),
  api.system_register_entities(uuid,jsonb,uuid), api.platform_reissue_system_owner(uuid)
from public, anon, authenticated;
grant execute on function api.platform_create_system(text,text,text,bigint,uuid,text,text,bigint,timestamptz,text),
  api.platform_system_details(uuid), api.system_registration_status(),
  api.system_register_entities(uuid,jsonb,uuid), api.platform_reissue_system_owner(uuid)
to authenticated;

revoke all on function api.system_issue_owner_verification(uuid,uuid,text),
  api.system_consume_owner_verification(uuid,text) from public, anon, authenticated;
grant execute on function api.system_issue_owner_verification(uuid,uuid,text),
  api.system_consume_owner_verification(uuid,text) to service_role;

select organization_lifecycle.install_write_guards();
