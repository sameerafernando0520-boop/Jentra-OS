-- CANDIDATE ONLY. Not installed anywhere. Install after
-- 20261106106000_managed_login_membership_bridge.sql.
--
-- Organization creation and module control for the J Panel.
--
-- 1. Self-created organizations are blocked by default. Organizations come
--    from the J Panel or an approved checkout order; the trial allowlist in
--    20261106100000_subscription_checkout.sql still exempts named accounts.
-- 2. Operators switch modules on and off per package and move an organization
--    to another package. Module access checks already read a package's
--    entitlements, so they need no change.
-- 3. Field Sales becomes a module with its own switch.

-- 1. Creation rule ---------------------------------------------------------

alter table billing.subscription_checkout_settings alter column enforce_checkout set default true;
update billing.subscription_checkout_settings set enforce_checkout = true;

create table billing.platform_control_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type in ('checkout_enforcement')),
  actor_id uuid not null references auth.users(id),
  before_context jsonb not null,
  after_context jsonb not null,
  reason text not null check (length(reason) between 5 and 500),
  occurred_at timestamptz not null default clock_timestamp()
);
create index platform_control_events_actor_idx on billing.platform_control_events (actor_id);
alter table billing.platform_control_events enable row level security;
alter table billing.platform_control_events force row level security;
revoke all on billing.platform_control_events from public, anon, authenticated;

create function api.platform_set_checkout_enforcement(p_enforce boolean, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_before boolean;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform intelligence_control.operator_required('organization');
  if p_enforce is null or v_reason is null or length(v_reason) not between 5 and 500
    or v_reason ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'INVALID_CHECKOUT_ENFORCEMENT';
  end if;
  select enforce_checkout into v_before from billing.subscription_checkout_settings for update;
  if v_before is distinct from p_enforce then
    update billing.subscription_checkout_settings
    set enforce_checkout = p_enforce, updated_at = statement_timestamp(), updated_by = auth.uid();
    insert into billing.platform_control_events (event_type, actor_id, before_context, after_context, reason)
    values ('checkout_enforcement', auth.uid(), jsonb_build_object('enforce_checkout', v_before),
      jsonb_build_object('enforce_checkout', p_enforce), v_reason);
  end if;
end;
$$;

-- The operator trial path created a subscription without a trial end, so
-- module checks, which need an unexpired trial, could never pass.
create or replace function api.platform_create_organization(
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
  v_trial_days integer;
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
  select greatest(1, least(10000, coalesce(e.numeric_limit, 5)))::integer, p.trial_days
  into v_seats, v_trial_days
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
  insert into billing.tenant_subscriptions (tenant_id, plan_code, status, seats, trial_ends_at)
  values (v_tenant_id, p_plan_code, 'trialing', v_seats,
    statement_timestamp() + make_interval(days => v_trial_days));
  insert into billing.organization_orders (tenant_id, signup_email)
  values (v_tenant_id, lower(trim(p_signup_email)));
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id, after_context)
  values (v_tenant_id, v_actor, gen_random_uuid(), 'organization.registered', 'tenant',
    v_tenant_id, jsonb_build_object('plan_code', p_plan_code));
  return v_tenant_id;
end;
$$;

-- 2. Module control --------------------------------------------------------

-- Field Sales starts switched off on every package, like the other modules.
insert into billing.plan_entitlements (plan_code, entitlement_code, enabled)
select code, 'module.field_sales', false from billing.plans
on conflict do nothing;

-- The entitlements an operator may switch. Limits such as users and
-- legal_entities are not modules and are not switchable here.
create function billing.platform_module_codes()
returns text[] language sql immutable set search_path = '' as $$
  select array['module.people', 'module.assets', 'module.projects', 'module.service',
    'module.finance', 'module.field_sales', 'analytics', 'module.ai'];
$$;

create function billing.platform_plan_modules(p_plan_code text)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_object_agg(m.code, coalesce(e.enabled, false))
  from unnest(billing.platform_module_codes()) as m(code)
  left join billing.plan_entitlements e on e.plan_code = p_plan_code and e.entitlement_code = m.code;
$$;

-- True when the organization's subscription is current and its package has
-- the module switched on. Same currency rule as the existing module checks.
create function billing.organization_module_enabled(p_tenant_id uuid, p_entitlement_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from billing.tenant_subscriptions s
    join billing.plan_entitlements e on e.plan_code = s.plan_code
    where s.tenant_id = p_tenant_id and e.entitlement_code = p_entitlement_code and e.enabled
      and ((s.status = 'active' and (s.current_period_ends_at is null or s.current_period_ends_at > now()))
        or (s.status = 'trialing' and s.trial_ends_at > now()))
  );
$$;

create function api.platform_package_modules()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return coalesce((select jsonb_agg(jsonb_build_object(
    'code', p.code, 'revision', p.control_revision, 'modules', billing.platform_plan_modules(p.code)
  ) order by p.name, p.code) from billing.plans p), '[]'::jsonb);
end;
$$;

create function api.platform_save_package_modules(p_code text, p_modules jsonb, p_expected_revision bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_before billing.plans;
  v_after billing.plans;
  v_before_modules jsonb;
begin
  perform intelligence_control.operator_required('organization');
  if jsonb_typeof(p_modules) is distinct from 'object' or p_modules = '{}'::jsonb or exists (
    select 1 from jsonb_each(p_modules) as m
    where m.key <> all (billing.platform_module_codes()) or jsonb_typeof(m.value) <> 'boolean'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_PACKAGE_MODULES';
  end if;
  select * into v_before from billing.plans where code = p_code for update;
  if not found or v_before.control_revision is distinct from p_expected_revision then
    raise exception using errcode = '40001', message = 'PACKAGE_CHANGED';
  end if;
  v_before_modules := billing.platform_plan_modules(p_code);
  insert into billing.plan_entitlements (plan_code, entitlement_code, enabled)
  select p_code, m.key, m.value = 'true'::jsonb from jsonb_each(p_modules) as m
  on conflict (plan_code, entitlement_code) do update set enabled = excluded.enabled;
  update billing.plans set control_revision = control_revision + 1
  where code = p_code returning * into v_after;
  insert into billing.package_events (plan_code, actor_id, before_context, after_context)
  values (p_code, auth.uid(), to_jsonb(v_before) || jsonb_build_object('modules', v_before_modules),
    to_jsonb(v_after) || jsonb_build_object('modules', billing.platform_plan_modules(p_code)));
end;
$$;

-- Lock order matches api.platform_apply_organization_offer: organization,
-- subscription, package.
create function api.platform_set_organization_package(p_tenant_id uuid, p_plan_code text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_before text;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform intelligence_control.operator_required('organization');
  if v_reason is null or length(v_reason) not between 5 and 500 or v_reason ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'INVALID_PACKAGE_CHANGE';
  end if;
  perform 1 from core.tenants where id = p_tenant_id and status in ('trial', 'active') for update;
  if not found then
    raise exception using errcode = '42501', message = 'ORGANIZATION_UNAVAILABLE';
  end if;
  select plan_code into v_before from billing.tenant_subscriptions where tenant_id = p_tenant_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'ORGANIZATION_UNAVAILABLE';
  end if;
  perform 1 from billing.plans
  where code = p_plan_code and status = 'active' and price_minor is not null for share;
  if not found then
    raise exception using errcode = '22023', message = 'PACKAGE_UNAVAILABLE';
  end if;
  if v_before is distinct from p_plan_code then
    update billing.tenant_subscriptions
    set plan_code = p_plan_code, version = version + 1, updated_at = statement_timestamp()
    where tenant_id = p_tenant_id;
    insert into audit.events (tenant_id, actor_id, request_id, event_type,
      aggregate_type, aggregate_id, before_context, after_context, metadata)
    values (p_tenant_id, auth.uid(), gen_random_uuid(), 'organization.package_changed', 'tenant', p_tenant_id,
      jsonb_build_object('plan_code', v_before), jsonb_build_object('plan_code', p_plan_code),
      jsonb_build_object('reason', v_reason));
  end if;
end;
$$;

-- 3. Field Sales module switch ---------------------------------------------

-- Company and rep access to Field Sales needs the module on the organization's
-- package. Customer confirmation and delivery links are left alone so orders
-- already in progress can finish. Without Field Sales installed this is a
-- no-op; installing Field Sales after this candidate is not supported.
do $scope$
begin
  if to_regprocedure('field_sales.require_rep(uuid,uuid,uuid,text)') is not null then
    execute $ddl$
      create or replace function field_sales.require_rep(t uuid, e uuid, b uuid, permission text) returns void
      language plpgsql security definer set search_path = '' as $body$
      begin
        perform field_sales.require_session();
        perform core.wave3_require_scope(t, permission, e, b);
        if b is null or not field_sales.restricted(t) then
          raise exception using errcode = '42501', message = 'FIELD_ACCOUNT_REQUIRED';
        end if;
        if not billing.organization_module_enabled(t, 'module.field_sales') then
          raise exception using errcode = '42501', message = 'FIELD_SALES_ENTITLEMENT_REQUIRED';
        end if;
      end;
      $body$;
    $ddl$;
    execute $ddl$
      create or replace function field_sales.require_company(t uuid, e uuid, b uuid, permission text) returns void
      language plpgsql security definer set search_path = '' as $body$
      begin
        perform field_sales.require_session();
        perform core.wave3_require_scope(t, permission, e, b);
        if b is null or coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2' or field_sales.restricted(t) then
          raise exception using errcode = '42501', message = 'MFA_REQUIRED';
        end if;
        if not billing.organization_module_enabled(t, 'module.field_sales') then
          raise exception using errcode = '42501', message = 'FIELD_SALES_ENTITLEMENT_REQUIRED';
        end if;
      end;
      $body$;
    $ddl$;
  end if;
end;
$scope$;

revoke all on function billing.platform_module_codes(), billing.platform_plan_modules(text),
  billing.organization_module_enabled(uuid, text)
  from public, anon, authenticated;

revoke all on function api.platform_set_checkout_enforcement(boolean, text), api.platform_package_modules(),
  api.platform_save_package_modules(text, jsonb, bigint), api.platform_set_organization_package(uuid, text, text)
  from public, anon, authenticated;
grant execute on function api.platform_set_checkout_enforcement(boolean, text), api.platform_package_modules(),
  api.platform_save_package_modules(text, jsonb, bigint), api.platform_set_organization_package(uuid, text, text)
  to authenticated;
