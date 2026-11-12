-- Platform control is independent of company memberships and tenant roles.
alter table intelligence_control.operators
  add column organization_manage boolean not null default false;

create or replace function intelligence_control.operator_required(cap text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2' or not exists (
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

create function api.platform_organization_assignment()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from intelligence_control.operators
    where actor_id = auth.uid() and active and organization_manage
  );
$$;

create function api.platform_organization_access()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
    and api.platform_organization_assignment();
$$;

alter table billing.plans
  add column price_minor bigint check (price_minor between 0 and 999999999999),
  add column price_currency_code text check (price_currency_code ~ '^[A-Z]{3}$'),
  add column control_revision bigint not null default 1,
  add constraint plan_price_pair check (
    (price_minor is null) = (price_currency_code is null)
  );

create table billing.package_events (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null references billing.plans(code),
  actor_id uuid not null references auth.users(id),
  before_context jsonb,
  after_context jsonb not null,
  occurred_at timestamptz not null default statement_timestamp()
);

create table billing.organization_orders (
  tenant_id uuid primary key references core.tenants(id),
  signup_email text not null check (length(signup_email) <= 254
    and signup_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  created_at timestamptz not null default statement_timestamp()
);

create table billing.organization_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  plan_code text not null references billing.plans(code),
  price_minor bigint check (price_minor between 0 and 999999999999),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  expires_at timestamptz,
  reason text not null check (length(reason) between 5 and 250),
  batch_id uuid not null,
  offered_by uuid not null references auth.users(id),
  offered_at timestamptz not null default clock_timestamp()
);

create index organization_offers_lookup_idx
  on billing.organization_offers (tenant_id, plan_code, offered_at desc, id desc);

create table billing.organization_activations (
  tenant_id uuid primary key references core.tenants(id),
  plan_code text not null references billing.plans(code),
  amount_minor bigint not null check (amount_minor between 0 and 999999999999),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  signup_email text not null check (length(signup_email) <= 254
    and signup_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  payment_reference text check (length(payment_reference) between 3 and 160),
  offer_id uuid references billing.organization_offers(id),
  activated_by uuid not null references auth.users(id),
  activated_at timestamptz not null default statement_timestamp(),
  check ((amount_minor = 0) = (payment_reference is null))
);

create unique index organization_payment_reference_idx
  on billing.organization_activations (lower(payment_reference))
  where payment_reference is not null;

do $$
declare relation text;
begin
  foreach relation in array array[
    'package_events', 'organization_orders', 'organization_offers', 'organization_activations'
  ] loop
    execute format('alter table billing.%I enable row level security', relation);
    execute format('alter table billing.%I force row level security', relation);
    execute format('revoke all on billing.%I from public, anon, authenticated', relation);
  end loop;
end;
$$;

-- Only the latest decision per organization and plan can be used. An expired
-- or withdrawn replacement never revives an earlier offer.
create function billing.current_organization_offer(p_tenant_id uuid, p_plan_code text)
returns billing.organization_offers language sql stable set search_path = '' as $$
  select candidate.*
  from (
    select o.* from billing.organization_offers o
    where o.tenant_id = p_tenant_id and o.plan_code = p_plan_code
    order by o.offered_at desc, o.id desc limit 1
  ) candidate
  join billing.plans p on p.code = candidate.plan_code
  where candidate.price_minor is not null
    and candidate.price_minor <= p.price_minor
    and candidate.currency_code = p.price_currency_code
    and (candidate.expires_at is null or candidate.expires_at > statement_timestamp());
$$;
revoke all on function billing.current_organization_offer(uuid, text)
  from public, anon, authenticated;

create function api.platform_list_packages()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return coalesce((select jsonb_agg(
    jsonb_build_object(
      'code', p.code, 'name', p.name, 'status', p.status,
      'price_minor', p.price_minor, 'currency_code', p.price_currency_code,
      'trial_days', p.trial_days, 'revision', p.control_revision
    ) order by p.name, p.code
  ) from billing.plans p), '[]'::jsonb);
end;
$$;

create function api.platform_save_package(
  p_code text, p_name text, p_price_minor bigint, p_currency_code text,
  p_trial_days integer, p_status text, p_expected_revision bigint,
  p_copy_from_code text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_before billing.plans;
  v_after billing.plans;
begin
  perform intelligence_control.operator_required('organization');
  if p_code is null or p_code !~ '^[a-z0-9][a-z0-9-]{1,62}$'
    or p_name is null or length(trim(p_name)) not between 2 and 120
    or p_price_minor is null or p_price_minor not between 0 and 999999999999
    or p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$'
    or p_trial_days is null or p_trial_days not between 0 and 365
    or p_status is null or p_status not in ('active', 'retired') then
    raise exception using errcode = '22023', message = 'INVALID_PACKAGE';
  end if;

  select * into v_before from billing.plans where code = p_code for update;
  if found then
    if p_expected_revision is distinct from v_before.control_revision then
      raise exception using errcode = '40001', message = 'PACKAGE_CHANGED';
    end if;
    update billing.plans set name = trim(p_name), price_minor = p_price_minor,
      price_currency_code = p_currency_code, trial_days = p_trial_days,
      status = p_status, control_revision = control_revision + 1
    where code = p_code returning * into v_after;
  else
    if p_expected_revision is not null or not exists (
      select 1 from billing.plans where code = p_copy_from_code
    ) then
      raise exception using errcode = '22023', message = 'PACKAGE_TEMPLATE_REQUIRED';
    end if;
    insert into billing.plans (code, name, price_minor, price_currency_code, trial_days, status)
    values (p_code, trim(p_name), p_price_minor, p_currency_code, p_trial_days, p_status)
    returning * into v_after;
    insert into billing.plan_entitlements (plan_code, entitlement_code, enabled, numeric_limit)
    select p_code, entitlement_code, enabled, numeric_limit from billing.plan_entitlements
    where plan_code = p_copy_from_code;
  end if;

  insert into billing.package_events (plan_code, actor_id, before_context, after_context)
  values (p_code, auth.uid(), to_jsonb(v_before), to_jsonb(v_after));
end;
$$;

create function api.platform_list_organizations(
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
      'price_minor', coalesce(offer.price_minor, p.price_minor),
      'price_currency_code', p.price_currency_code
    ) order by t.name, t.id
  )
  from (
    select * from core.tenants
    where (p_tenant_id is null or id = p_tenant_id)
      and (position(lower(trim(coalesce(p_query, ''))) in lower(name)) > 0
        or position(lower(trim(coalesce(p_query, ''))) in slug) > 0)
    order by name, id offset p_offset limit 51
  ) t
  left join billing.tenant_subscriptions s on s.tenant_id = t.id
  left join billing.plans p on p.code = s.plan_code and p.status = 'active'
  left join billing.organization_orders o on o.tenant_id = t.id
  left join billing.organization_activations a on a.tenant_id = t.id
  left join lateral billing.current_organization_offer(t.id, s.plan_code) offer
    on p.code is not null), '[]'::jsonb);
end;
$$;

create function api.platform_create_organization(
  p_name text, p_slug text, p_signup_email text, p_plan_code text,
  p_timezone text, p_currency_code text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_tenant_id uuid;
  v_entity_id uuid;
  v_role_id uuid;
  v_seats integer;
begin
  perform intelligence_control.operator_required('organization');
  if p_name is null or length(trim(p_name)) not between 2 and 160
    or p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{2,62}$'
    or p_signup_email is null or length(trim(p_signup_email)) > 254
    or trim(p_signup_email) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$'
    or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone)
  then
    raise exception using errcode = '22023', message = 'INVALID_ORGANIZATION';
  end if;
  select greatest(1, least(10000, coalesce(e.numeric_limit, 5)))::integer into v_seats
  from billing.plans p left join billing.plan_entitlements e
    on e.plan_code = p.code and e.entitlement_code = 'users' and e.enabled
  where p.code = p_plan_code and p.status = 'active' and p.price_minor is not null
  for share of p;
  if not found then
    raise exception using errcode = '22023', message = 'PACKAGE_PRICE_REQUIRED';
  end if;

  insert into core.tenants (name, slug, status, timezone, default_currency_code, created_by)
  values (trim(p_name), p_slug, 'trial', p_timezone, p_currency_code, v_actor)
  returning id into v_tenant_id;
  insert into core.legal_entities (tenant_id, name, code, currency_code, timezone, created_by)
  values (v_tenant_id, trim(p_name), 'MAIN', p_currency_code, p_timezone, v_actor)
  returning id into v_entity_id;
  insert into core.branches (tenant_id, legal_entity_id, name, code, timezone, created_by)
  values (v_tenant_id, v_entity_id, 'Head office', 'HQ', p_timezone, v_actor);
  insert into core.roles (tenant_id, code, name, description, requires_mfa, is_system)
  values (v_tenant_id, 'tenant_owner', 'Tenant owner', 'Administrator for this organization.', true, true)
  returning id into v_role_id;
  insert into core.role_permissions (tenant_id, role_id, permission_code)
  select v_tenant_id, v_role_id, code from core.permissions;
  insert into billing.tenant_subscriptions (tenant_id, plan_code, status, seats)
  values (v_tenant_id, p_plan_code, 'trialing', v_seats);
  insert into billing.organization_orders (tenant_id, signup_email)
  values (v_tenant_id, lower(trim(p_signup_email)));
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id, after_context)
  values (v_tenant_id, v_actor, gen_random_uuid(), 'organization.registered', 'tenant',
    v_tenant_id, jsonb_build_object('plan_code', p_plan_code));
  return v_tenant_id;
end;
$$;

create function api.platform_confirm_organization_activation(
  p_tenant_id uuid, p_signup_email text, p_payment_reference text,
  p_expected_amount_minor bigint, p_expected_currency_code text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_activation billing.organization_activations;
  v_plan billing.plans;
  v_offer billing.organization_offers;
  v_signup_email text := lower(trim(p_signup_email));
  v_order_email text;
  v_reference text := nullif(trim(p_payment_reference), '');
  v_amount bigint;
begin
  perform intelligence_control.operator_required('organization');
  perform 1 from core.tenants
  where id = p_tenant_id and status in ('trial', 'active') for update;
  if not found then
    raise exception using errcode = '22023', message = 'ORGANIZATION_UNAVAILABLE';
  end if;

  select * into v_activation from billing.organization_activations where tenant_id = p_tenant_id;
  if found then
    if v_activation.signup_email = v_signup_email
      and v_activation.amount_minor = p_expected_amount_minor
      and v_activation.currency_code = p_expected_currency_code
      and v_activation.payment_reference is not distinct from v_reference then
      return jsonb_build_object('activated_at', v_activation.activated_at);
    end if;
    raise exception using errcode = '23505', message = 'ORGANIZATION_ALREADY_ACTIVATED';
  end if;

  select signup_email into v_order_email from billing.organization_orders
  where tenant_id = p_tenant_id;
  if v_signup_email is null or length(v_signup_email) > 254
    or v_signup_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or (v_order_email is not null and v_order_email <> v_signup_email) then
    raise exception using errcode = '22023', message = 'SIGNUP_EMAIL_REQUIRED';
  end if;
  select p.* into v_plan
  from billing.tenant_subscriptions s join billing.plans p on p.code = s.plan_code
  where s.tenant_id = p_tenant_id and s.status in ('trialing', 'active', 'past_due')
    and p.status = 'active' and p.price_minor is not null
  for update of s for share of p;
  if not found then
    raise exception using errcode = '22023', message = 'PACKAGE_PRICE_REQUIRED';
  end if;
  select * into v_offer from billing.current_organization_offer(p_tenant_id, v_plan.code);
  v_amount := coalesce(v_offer.price_minor, v_plan.price_minor);
  if v_amount is distinct from p_expected_amount_minor
    or v_plan.price_currency_code is distinct from p_expected_currency_code then
    raise exception using errcode = '40001', message = 'ORGANIZATION_QUOTE_CHANGED';
  end if;
  if (v_amount > 0 and (v_reference is null or length(v_reference) not between 3 and 160))
    or (v_amount = 0 and v_reference is not null) then
    raise exception using errcode = '22023', message = 'INVALID_PAYMENT_CONFIRMATION';
  end if;
  insert into billing.organization_activations (
    tenant_id, plan_code, amount_minor, currency_code, signup_email, payment_reference, offer_id, activated_by
  )
  values (p_tenant_id, v_plan.code, v_amount, v_plan.price_currency_code, v_signup_email,
    v_reference, v_offer.id, auth.uid()) returning * into v_activation;
  update core.tenants set status = 'active', version = version + 1, updated_at = statement_timestamp()
  where id = p_tenant_id;
  update billing.tenant_subscriptions set status = 'active', version = version + 1,
    updated_at = statement_timestamp()
  where tenant_id = p_tenant_id;
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id, after_context)
  values (p_tenant_id, auth.uid(), gen_random_uuid(), 'organization.activated', 'tenant', p_tenant_id,
    jsonb_build_object('plan_code', v_plan.code, 'amount_minor', v_amount, 'currency_code', v_plan.price_currency_code));
  return jsonb_build_object('activated_at', v_activation.activated_at);
end;
$$;

create function api.platform_apply_organization_offer(
  p_targets jsonb, p_price_minor bigint, p_currency_code text,
  p_expires_at timestamptz, p_reason text
)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_batch_id uuid := gen_random_uuid();
  v_tenant_ids uuid[];
  v_count integer;
begin
  perform intelligence_control.operator_required('organization');
  if jsonb_typeof(p_targets) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'INVALID_OFFER';
  end if;
  if jsonb_array_length(p_targets) not between 1 and 50
    or p_reason is null or length(trim(p_reason)) not between 5 and 250
    or p_price_minor < 0
    or (p_expires_at is not null and (
      not isfinite(p_expires_at) or p_expires_at <= statement_timestamp()
    )) then
    raise exception using errcode = '22023', message = 'INVALID_OFFER';
  end if;

  -- Serialize against lock/purge and activation and lock in consistent order.
  select array_agg(target.tenant_id) into v_tenant_ids
  from jsonb_to_recordset(p_targets) as target(tenant_id uuid);
  perform 1 from core.tenants t
  where t.id = any(v_tenant_ids) and t.status in ('trial', 'active')
  order by t.id for update;
  get diagnostics v_count = row_count;
  perform 1 from billing.tenant_subscriptions s
  where s.tenant_id = any(v_tenant_ids)
  order by s.tenant_id for share;
  if v_count <> cardinality(v_tenant_ids) or exists (
    select 1 from jsonb_to_recordset(p_targets) as target(tenant_id uuid, plan_code text)
    left join billing.tenant_subscriptions s on s.tenant_id = target.tenant_id
    where s.plan_code is null or s.plan_code is distinct from target.plan_code
  ) then
    raise exception using errcode = '22023', message = 'OFFER_ORGANIZATIONS_CHANGED';
  end if;
  perform 1 from billing.plans p where p.code in (
    select target.plan_code from jsonb_to_recordset(p_targets) as target(plan_code text)
  ) order by p.code for share;
  if exists (
    select 1 from jsonb_to_recordset(p_targets) as target(plan_code text, revision bigint)
    left join billing.plans p on p.code = target.plan_code
    where p.code is null or p.status <> 'active' or p.price_minor is null
      or p.control_revision is distinct from target.revision
      or p_price_minor > p.price_minor
      or (p_price_minor > 0 and p.price_currency_code is distinct from p_currency_code)
  ) then
    raise exception using errcode = '22023', message = 'INVALID_OFFER_PACKAGE_OR_PRICE';
  end if;

  with applied as (
    insert into billing.organization_offers (
      tenant_id, plan_code, price_minor, currency_code, expires_at, reason, batch_id, offered_by
    )
    select target.tenant_id, target.plan_code, p_price_minor, p.price_currency_code,
      p_expires_at, trim(p_reason), v_batch_id, auth.uid()
    from jsonb_to_recordset(p_targets) as target(tenant_id uuid, plan_code text)
    join billing.plans p on p.code = target.plan_code
    returning tenant_id, plan_code, price_minor, currency_code, expires_at, reason
  )
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id, after_context)
  select tenant_id, auth.uid(), v_batch_id, 'organization.offer_changed', 'tenant', tenant_id,
    jsonb_build_object('plan_code', plan_code, 'price_minor', price_minor,
      'currency_code', currency_code, 'expires_at', expires_at, 'reason', reason)
  from applied;
  return v_count;
end;
$$;

revoke all on function api.platform_organization_assignment(), api.platform_organization_access(),
  api.platform_list_packages(), api.platform_save_package(text,text,bigint,text,integer,text,bigint,text),
  api.platform_list_organizations(text,integer,uuid), api.platform_create_organization(text,text,text,text,text,text),
  api.platform_confirm_organization_activation(uuid,text,text,bigint,text),
  api.platform_apply_organization_offer(jsonb,bigint,text,timestamptz,text)
  from public, anon, authenticated;
grant execute on function api.platform_organization_assignment(), api.platform_organization_access(),
  api.platform_list_packages(), api.platform_save_package(text,text,bigint,text,integer,text,bigint,text),
  api.platform_list_organizations(text,integer,uuid), api.platform_create_organization(text,text,text,text,text,text),
  api.platform_confirm_organization_activation(uuid,text,text,bigint,text),
  api.platform_apply_organization_offer(jsonb,bigint,text,timestamptz,text)
  to authenticated;
