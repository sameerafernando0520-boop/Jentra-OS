-- The storefront is opt-in. Publishing a plan does not publish the storefront
-- or change any existing organization's entitlements.
alter table billing.plans
  add column checkout_published boolean not null default false,
  add column checkout_description text,
  add column checkout_features text[] not null default '{}',
  add column checkout_demo_url text,
  add column checkout_demo_transcript text,
  add column checkout_term_days integer check (checkout_term_days between 1 and 3660),
  add constraint checkout_published_details check (
    not checkout_published or (
      price_minor is not null and price_currency_code = 'LKR'
      and checkout_description is not null and cardinality(checkout_features) > 0
      and checkout_demo_url is not null and checkout_demo_transcript is not null
      and checkout_term_days is not null
    )
  );

create table billing.subscription_checkout_settings (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  enforce_checkout boolean not null default false,
  bank jsonb,
  updated_at timestamptz not null default statement_timestamp(),
  updated_by uuid references auth.users(id)
);
insert into billing.subscription_checkout_settings default values;

create table billing.subscription_trial_allowlist (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table billing.subscription_verified_buyers (
  buyer_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  verified_at timestamptz not null default statement_timestamp()
);

create table billing.subscription_checkout_orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id),
  request_id uuid not null,
  signup_email text not null,
  organization_name text not null,
  username text unique check (username ~ '^[a-z0-9][a-z0-9._-]{2,47}$'),
  tenant_id uuid references core.tenants(id),
  kind text not null check (kind in ('initial', 'renewal')),
  status text not null default 'awaiting_payment'
    check (status in ('awaiting_payment', 'under_review', 'payment_rejected', 'paid', 'cancelled')),
  plan_code text not null references billing.plans(code),
  plan_name text not null,
  plan_revision bigint not null,
  price_minor bigint not null check (price_minor between 0 and 999999999999),
  currency_code text not null default 'LKR' check (currency_code = 'LKR'),
  term_days integer not null check (term_days between 1 and 3660),
  seats integer not null check (seats between 1 and 10000),
  bank jsonb,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null,
  transfer_reference text,
  verified_reference text,
  verified_amount_minor bigint,
  verified_paid_at timestamptz,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  decision_reason text,
  exception_reason text,
  paid_at timestamptz,
  term_ends_at timestamptz,
  unique (buyer_id, request_id),
  unique (id, tenant_id),
  check ((kind = 'initial') = (username is not null)),
  check (kind = 'initial' or tenant_id is not null),
  check (status <> 'paid' or (tenant_id is not null and paid_at is not null and term_ends_at is not null))
);
create unique index subscription_checkout_one_open_buyer
  on billing.subscription_checkout_orders (buyer_id)
  where kind = 'initial' and status in ('awaiting_payment', 'under_review', 'payment_rejected');
create unique index subscription_checkout_one_open_renewal
  on billing.subscription_checkout_orders (tenant_id)
  where kind = 'renewal' and status in ('awaiting_payment', 'under_review', 'payment_rejected');
create index subscription_checkout_tenant_idx on billing.subscription_checkout_orders (tenant_id);
create index subscription_checkout_paid_initial
  on billing.subscription_checkout_orders (tenant_id) where kind = 'initial' and status = 'paid';
create index subscription_checkout_recent_idx on billing.subscription_checkout_orders (created_at desc, id);

-- A fresh client may rediscover the same open order under a new request key.
-- Record the recovered key so its later replay still names the same order.
create table billing.subscription_checkout_replays (
  buyer_id uuid not null references auth.users(id),
  request_id uuid not null,
  order_id uuid not null references billing.subscription_checkout_orders(id),
  tenant_id uuid references core.tenants(id),
  plan_revision bigint not null,
  primary key (buyer_id, request_id)
);
create index subscription_checkout_replays_order_idx on billing.subscription_checkout_replays (order_id);
create index subscription_checkout_replays_tenant_idx on billing.subscription_checkout_replays (tenant_id);

create table billing.subscription_handover_jobs (
  order_id uuid primary key,
  tenant_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'failed', 'sent', 'completed')),
  attempts integer not null default 0 check (attempts >= 0),
  lease_token uuid,
  lease_until timestamptz,
  last_error text,
  user_id uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default statement_timestamp(),
  foreign key (order_id, tenant_id) references billing.subscription_checkout_orders(id, tenant_id)
);
create index subscription_handover_tenant_idx on billing.subscription_handover_jobs (tenant_id);

-- Retain only a fingerprint for the duplicate check, including after a tenant
-- purge. Initial checkout records its payment in the existing activation ledger.
create table billing.subscription_payment_references (
  fingerprint bytea primary key
);

create table billing.subscription_checkout_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references core.tenants(id),
  order_id uuid references billing.subscription_checkout_orders(id),
  actor_id uuid not null references auth.users(id),
  event_type text not null,
  details jsonb not null default '{}',
  occurred_at timestamptz not null default statement_timestamp()
);
create index subscription_checkout_events_order_idx on billing.subscription_checkout_events (order_id);
create index subscription_checkout_events_tenant_idx on billing.subscription_checkout_events (tenant_id);

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'subscription_checkout_settings', 'subscription_trial_allowlist',
    'subscription_verified_buyers', 'subscription_checkout_orders', 'subscription_checkout_replays', 'subscription_handover_jobs',
    'subscription_payment_references', 'subscription_checkout_events'
  ] loop
    execute format('alter table billing.%I enable row level security', v_table);
    execute format('revoke all on billing.%I from public, anon, authenticated', v_table);
  end loop;
end;
$$;

insert into billing.subscription_payment_references (fingerprint)
  select distinct extensions.digest(lower(trim(payment_reference)), 'sha256')
  from billing.organization_activations where payment_reference is not null;

create function billing.reserve_subscription_payment_reference(p_reference text)
returns void language sql volatile set search_path = '' as $$
  insert into billing.subscription_payment_references (fingerprint)
  values (extensions.digest(lower(trim(p_reference)), 'sha256'));
$$;

create function billing.organization_reserve_payment_reference()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.payment_reference is not null then
    if tg_op = 'INSERT' or lower(trim(new.payment_reference)) is distinct from lower(trim(old.payment_reference)) then
      perform billing.reserve_subscription_payment_reference(new.payment_reference);
    end if;
  end if;
  return new;
end;
$$;
create trigger organization_reserve_payment_reference
before insert or update of payment_reference on billing.organization_activations
for each row execute function billing.organization_reserve_payment_reference();

create function billing.reserve_subscription_username(p_name text, p_order_id uuid)
returns text language plpgsql set search_path = '' as $$
declare
  v_base text := trim(both '-' from regexp_replace(
    lower(regexp_replace(normalize(trim(p_name), NFKD), U&'[\0300-\036F]', '', 'g')),
    '[^a-z0-9]+', '-', 'g'));
  v_username text;
  v_attempt integer;
begin
  v_base := trim(both '-' from left(v_base, 35));
  if v_base = '' then
    v_base := 'organization-' || left(md5(normalize(lower(trim(p_name)), NFKC)), 12);
  end if;
  for v_attempt in 0..8 loop
    if v_attempt = 0 and length(v_base) >= 3 then
      v_username := v_base;
    else
      v_username := v_base || '-' || left(md5(p_order_id::text || ':' || v_attempt::text), 10);
    end if;
    perform pg_advisory_xact_lock(hashtextextended(v_username, 45109));
    if not exists (select 1 from billing.subscription_checkout_orders where username = v_username)
       and not exists (select 1 from auth.users where email = v_username || '@admin.jentra.invalid')
       and not exists (select 1 from core.organization_administrator_logins where username = v_username) then
      return v_username;
    end if;
  end loop;
  raise exception using errcode = '23505', message = 'SUBSCRIPTION_USERNAME_UNAVAILABLE';
end;
$$;

create or replace function core.organization_protect_login_alias()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_username text;
  v_metadata jsonb;
  v_order billing.subscription_checkout_orders;
begin
  if right(lower(coalesce(new.email, '')), 21) = '@admin.jentra.invalid' then
    v_username := split_part(lower(new.email), '@', 1);
    perform pg_advisory_xact_lock(hashtextextended(v_username, 45109));
    select raw_app_meta_data into v_metadata from auth.users where id = new.id;
    if found and v_metadata->>'managed_org_admin' is distinct from 'true' then
      raise exception using errcode = '42501', message = 'Managed login address is reserved.';
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

create function billing.checkout_current_buyer_email(p_buyer_id uuid)
returns text language sql stable set search_path = '' as $$
  select lower(trim(email)) from auth.users where id = p_buyer_id
    and email is not null and length(trim(email)) <= 254
    and lower(trim(email)) !~ '@admin\.jentra\.invalid$'
    and trim(email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$';
$$;

create function api.subscription_record_buyer_verification(p_buyer_id uuid, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_email text := billing.checkout_current_buyer_email(p_buyer_id);
begin
  if v_email is null or lower(trim(p_email)) is distinct from v_email then
    raise exception using errcode = '42501', message = 'SUBSCRIPTION_EMAIL_REQUIRED';
  end if;
  insert into billing.subscription_verified_buyers (buyer_id, email) values (p_buyer_id, v_email)
  on conflict (buyer_id) do update set email = excluded.email, verified_at = statement_timestamp();
end;
$$;

create function billing.checkout_verified_email(p_buyer_id uuid)
returns text language sql stable set search_path = '' as $$
  select email from billing.subscription_verified_buyers where buyer_id = p_buyer_id
    and email = billing.checkout_current_buyer_email(p_buyer_id);
$$;

create function billing.checkout_required()
returns boolean language sql stable set search_path = '' as $$
  select s.enforce_checkout
    and not exists (select 1 from billing.subscription_trial_allowlist where user_id = auth.uid())
  from billing.subscription_checkout_settings s;
$$;

alter function core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)
  rename to bootstrap_tenant_pre_checkout_impl;
revoke all on function core.bootstrap_tenant_pre_checkout_impl(text,text,text,text,text,text,text,text,uuid)
  from public, anon, authenticated;

create function core.bootstrap_tenant_impl(
  p_name text, p_slug text, p_legal_entity_name text, p_legal_entity_code text,
  p_branch_name text, p_branch_code text, p_timezone text default 'Asia/Colombo',
  p_currency_code text default 'LKR', p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if billing.checkout_required() then
    raise exception using errcode = '42501', message = 'SUBSCRIPTION_CHECKOUT_REQUIRED';
  end if;
  return core.bootstrap_tenant_pre_checkout_impl(
    p_name, p_slug, p_legal_entity_name, p_legal_entity_code, p_branch_name,
    p_branch_code, p_timezone, p_currency_code, p_idempotency_key);
end;
$$;
revoke all on function core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)
  from public, anon, authenticated;
grant execute on function core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid) to authenticated;

create or replace function api.bootstrap_tenant(
  p_name text, p_slug text, p_legal_entity_name text, p_legal_entity_code text,
  p_branch_name text, p_branch_code text, p_timezone text default 'Asia/Colombo',
  p_currency_code text default 'LKR', p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile set search_path = '' as $$
  select core.bootstrap_tenant_impl(
    p_name, p_slug, p_legal_entity_name, p_legal_entity_code, p_branch_name,
    p_branch_code, p_timezone, p_currency_code, p_idempotency_key);
$$;

create function billing.checkout_expired(p_tenant_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from billing.tenant_subscriptions s
    where s.tenant_id = p_tenant_id and s.current_period_ends_at <= statement_timestamp()
      and exists (select 1 from billing.subscription_checkout_orders o
        where o.tenant_id = s.tenant_id and o.kind = 'initial' and o.status = 'paid')
  );
$$;

-- Keep physical availability for account recovery and lifecycle operations.
-- Business permissions and row-level access require a current paid term.
create function core.organization_business_available(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.organization_available(p_tenant_id) and not billing.checkout_expired(p_tenant_id);
$$;
revoke all on function core.organization_business_available(uuid) from public, anon, authenticated;
grant execute on function core.organization_business_available(uuid) to authenticated;

create or replace function core.is_tenant_member(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.organization_business_available(p_tenant_id)
    and core.organization_account_ready((select auth.uid()))
    and exists (select 1 from core.memberships m
      where m.tenant_id = p_tenant_id and m.user_id = (select auth.uid()) and m.status = 'active');
$$;

create or replace function core.organization_can_manage_staff(p_tenant_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.organization_business_available(p_tenant_id) and exists (
    select 1 from core.memberships m
    join core.role_assignments a on (a.tenant_id, a.membership_id) = (m.tenant_id, m.id)
    join core.roles r on (r.tenant_id, r.id) = (a.tenant_id, a.role_id)
    where m.tenant_id = p_tenant_id and m.user_id = p_user_id and m.status = 'active'
      and a.legal_entity_id is null and a.branch_id is null
      and r.is_system and r.code in ('tenant_owner', 'tenant_admin')
  );
$$;

create or replace function organization_lifecycle.install_write_guards()
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in select * from organization_lifecycle.relations() where scope_column = 'tenant_id'
  loop
    if not exists (select 1 from pg_trigger where tgrelid = r.relid
                   and tgname = 'organization_write_lock') then
      execute format('create trigger organization_write_lock before insert or update or delete on %s '
                     'for each row execute function organization_lifecycle.check_write()', r.qualified_name);
    end if;
    if exists (select 1 from pg_class where oid = r.relid and relrowsecurity) then
      execute format('drop policy if exists organization_online_access on %s', r.qualified_name);
      execute format('create policy organization_online_access on %s as restrictive '
                     'to authenticated using (%I is null or core.organization_business_available(%I))',
                     r.qualified_name, r.scope_column, r.scope_column);
    end if;
  end loop;
end;
$$;
select organization_lifecycle.install_write_guards();

create function billing.checkout_can_renew(p_tenant_id uuid, p_actor_id uuid)
returns boolean language sql stable set search_path = '' as $$
  select core.organization_available(p_tenant_id) and (
    exists (select 1 from billing.subscription_checkout_orders o
      where o.tenant_id = p_tenant_id and o.kind = 'initial' and o.status = 'paid'
        and o.buyer_id = p_actor_id and o.signup_email = billing.checkout_verified_email(p_actor_id))
    or (core.organization_account_ready(p_actor_id) and exists (
      select 1 from core.memberships m
      join core.role_assignments a on (a.tenant_id, a.membership_id) = (m.tenant_id, m.id)
      join core.roles r on (r.tenant_id, r.id) = (a.tenant_id, a.role_id)
      where m.tenant_id = p_tenant_id and m.user_id = p_actor_id and m.status = 'active'
        and a.legal_entity_id is null and a.branch_id is null and r.is_system and r.code = 'tenant_owner'))
  );
$$;

create function api.subscription_checkout_access()
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
      and exists (select 1 from billing.subscription_checkout_orders o
        where o.tenant_id = s.tenant_id and o.kind = 'initial' and o.status = 'paid')
      and billing.checkout_can_renew(t.id, v_actor)), '[]')
  );
end;
$$;

create function api.subscription_checkout_catalog()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', p.code, 'name', p.name, 'description', p.checkout_description,
    'features', p.checkout_features, 'demo_url', p.checkout_demo_url,
    'demo_transcript', p.checkout_demo_transcript, 'term_days', p.checkout_term_days,
    'price_minor', p.price_minor, 'currency_code', p.price_currency_code, 'revision', p.control_revision
  ) order by p.price_minor, p.name, p.code), '[]')
  from billing.plans p
  where p.status = 'active' and p.checkout_published
    and exists (select 1 from billing.subscription_checkout_settings s where s.enabled);
$$;

create function billing.checkout_order_projection(p_order billing.subscription_checkout_orders, p_operator boolean default false)
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
    'created_at', p_order.created_at, 'expires_at', p_order.expires_at,
    'paid_at', p_order.paid_at, 'term_ends_at', p_order.term_ends_at, 'handover_status', j.status
  ) || case when p_operator then jsonb_build_object(
    'signup_email', p_order.signup_email, 'verified_reference', p_order.verified_reference,
    'verified_amount_minor', p_order.verified_amount_minor, 'verified_paid_at', p_order.verified_paid_at,
    'reviewed_at', p_order.reviewed_at, 'decision_reason', p_order.decision_reason,
    'exception_reason', p_order.exception_reason, 'handover_error', j.last_error,
    'handover_attempts', j.attempts
  ) else '{}' end
  from (select 1) base left join billing.subscription_handover_jobs j on j.order_id = p_order.id;
$$;

create function api.subscription_checkout_orders()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(billing.checkout_order_projection(o) order by o.created_at desc, o.id), '[]')
  from (select * from billing.subscription_checkout_orders
    where buyer_id = auth.uid() order by created_at desc, id limit 50) o;
$$;

create function billing.checkout_settle(
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

create function api.subscription_create_order(
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
      and exists (select 1 from billing.subscription_checkout_orders first_order
        where first_order.tenant_id = t.id and first_order.kind = 'initial' and first_order.status = 'paid');
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

create function api.subscription_submit_payment(p_order_id uuid, p_transfer_reference text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_order billing.subscription_checkout_orders;
  v_reference text := nullif(trim(p_transfer_reference), '');
begin
  select * into v_order from billing.subscription_checkout_orders
  where id = p_order_id and buyer_id = auth.uid() and core.organization_account_ready(auth.uid()) for update;
  if not found then
    raise exception using errcode = '42501', message = 'SUBSCRIPTION_ORDER_UNAVAILABLE';
  end if;
  if v_reference is null or length(v_reference) not between 3 and 160 or v_reference ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'INVALID_SUBSCRIPTION_REFERENCE';
  end if;
  if lower(v_order.transfer_reference) = lower(v_reference) and v_order.status in ('under_review', 'paid') then
    return billing.checkout_order_projection(v_order);
  end if;
  -- A customer may report an already-made transfer after the deadline.
  -- Its actual bank posting time still has to be inside the quote window.
  if v_order.status not in ('awaiting_payment', 'payment_rejected') or v_order.price_minor = 0 then
    raise exception using errcode = '40001', message = 'SUBSCRIPTION_ORDER_NOT_PAYABLE';
  end if;
  update billing.subscription_checkout_orders set status = 'under_review', transfer_reference = v_reference,
    reviewed_by = null, reviewed_at = null, verified_reference = null, verified_amount_minor = null,
    verified_paid_at = null, decision_reason = null, exception_reason = null
  where id = p_order_id returning * into v_order;
  insert into billing.subscription_checkout_events (tenant_id, order_id, actor_id, event_type, details)
  values (v_order.tenant_id, v_order.id, auth.uid(), 'payment_submitted', jsonb_build_object('reference', v_reference));
  return billing.checkout_order_projection(v_order);
end;
$$;

create function api.platform_subscription_checkout_settings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return (select jsonb_build_object('enabled', enabled, 'enforce_checkout', enforce_checkout, 'bank', bank)
    from billing.subscription_checkout_settings);
end;
$$;

create function api.platform_save_subscription_bank(
  p_bank_name text, p_account_name text, p_account_number text, p_branch text, p_instructions text
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_bank_name text := nullif(trim(p_bank_name), '');
  v_account_name text := nullif(trim(p_account_name), '');
  v_account_number text := nullif(trim(p_account_number), '');
  v_branch text := nullif(trim(p_branch), '');
  v_instructions text := nullif(trim(p_instructions), '');
begin
  perform intelligence_control.operator_required('organization');
  if v_bank_name is null or length(v_bank_name) > 120 or v_bank_name ~ '[[:cntrl:]]'
    or v_account_name is null or length(v_account_name) > 120 or v_account_name ~ '[[:cntrl:]]'
    or v_account_number is null or v_account_number !~ '^[A-Za-z0-9 -]{3,40}$'
    or length(v_branch) > 120 or v_branch ~ '[[:cntrl:]]' or length(v_instructions) > 1000 then
    raise exception using errcode = '22023', message = 'INVALID_SUBSCRIPTION_BANK';
  end if;
  update billing.subscription_checkout_settings
  set bank = jsonb_build_object(
    'bank_name', v_bank_name, 'account_name', v_account_name, 'account_number', v_account_number,
    'branch', v_branch, 'instructions', v_instructions
  ), updated_at = statement_timestamp(), updated_by = auth.uid();
  insert into billing.subscription_checkout_events (actor_id, event_type)
  values (auth.uid(), 'bank_settings_changed');
end;
$$;

create or replace function api.platform_list_packages()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return coalesce((select jsonb_agg(
    jsonb_build_object(
      'code', p.code, 'name', p.name, 'status', p.status,
      'price_minor', p.price_minor, 'currency_code', p.price_currency_code,
      'trial_days', p.trial_days, 'revision', p.control_revision,
      'published', p.checkout_published, 'description', p.checkout_description,
      'features', p.checkout_features, 'demo_url', p.checkout_demo_url,
      'demo_transcript', p.checkout_demo_transcript, 'term_days', p.checkout_term_days
    ) order by p.name, p.code)
  from billing.plans p), '[]'::jsonb);
end;
$$;

create function api.platform_save_subscription_publication(
  p_plan_code text, p_expected_revision bigint, p_description text, p_features text[],
  p_demo_url text, p_demo_transcript text, p_term_days integer, p_published boolean
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_before billing.plans;
  v_after billing.plans;
  v_description text := nullif(trim(p_description), '');
  v_demo_url text := nullif(trim(p_demo_url), '');
  v_transcript text := nullif(trim(p_demo_transcript), '');
  v_features text[] := array(select trim(feature) from unnest(p_features) feature);
begin
  perform intelligence_control.operator_required('organization');
  select * into v_before from billing.plans where code = p_plan_code for update;
  if not found or v_before.control_revision is distinct from p_expected_revision then
    raise exception using errcode = '40001', message = 'PACKAGE_CHANGED';
  end if;
  if p_published is null or length(v_description) > 3000 or cardinality(v_features) > 20
    or exists (select 1 from unnest(v_features) feature
      where feature is null or length(feature) not between 1 and 240 or feature ~ '[[:cntrl:]]')
    or length(v_demo_url) > 1000 or v_demo_url !~ '^https://[A-Za-z0-9][A-Za-z0-9.-]*([/?#][^[:space:][:cntrl:]]*)?$'
    or length(v_transcript) > 12000 or p_term_days not between 1 and 3660
    or (p_published and (v_before.status <> 'active' or v_before.price_minor is null
      or v_before.price_currency_code is distinct from 'LKR' or v_description is null
      or v_demo_url is null or v_transcript is null or p_term_days is null or cardinality(v_features) = 0)) then
    raise exception using errcode = '22023', message = 'INVALID_SUBSCRIPTION_PUBLICATION';
  end if;
  update billing.plans set checkout_published = p_published, checkout_description = v_description,
    checkout_features = v_features, checkout_demo_url = v_demo_url, checkout_demo_transcript = v_transcript,
    checkout_term_days = p_term_days, control_revision = control_revision + 1
  where code = p_plan_code returning * into v_after;
  insert into billing.package_events (plan_code, actor_id, before_context, after_context)
  values (p_plan_code, auth.uid(), to_jsonb(v_before), to_jsonb(v_after));
end;
$$;

create function api.platform_subscription_checkout_queue(p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  if p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'INVALID_SUBSCRIPTION_QUEUE';
  end if;
  return coalesce((select jsonb_agg(billing.checkout_order_projection(o, true) order by o.created_at desc, o.id)
    from (select * from billing.subscription_checkout_orders
      order by created_at desc, id offset p_offset limit 50) o), '[]');
end;
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
      'term_ends_at', s.current_period_ends_at, 'term_expired', billing.checkout_expired(t.id)
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
  left join billing.organization_orders o on o.tenant_id = t.id
  left join billing.organization_activations a on a.tenant_id = t.id
  left join lateral billing.current_organization_offer(t.id, s.plan_code) offer on p.code is not null), '[]'::jsonb);
end;
$$;

create function api.platform_review_subscription_payment(
  p_order_id uuid, p_approved boolean, p_verified_reference text, p_verified_amount_minor bigint,
  p_verified_paid_at timestamptz, p_reason text, p_exception_reason text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_order billing.subscription_checkout_orders;
  v_reference text := nullif(trim(p_verified_reference), '');
  v_reason text := nullif(trim(p_reason), '');
  v_exception text := nullif(trim(p_exception_reason), '');
begin
  perform intelligence_control.operator_required('organization');
  select * into v_order from billing.subscription_checkout_orders where id = p_order_id for update;
  if not found or p_approved is null then
    raise exception using errcode = '22023', message = 'INVALID_SUBSCRIPTION_REVIEW';
  end if;
  if v_order.status = 'paid' and p_approved
    and lower(v_order.verified_reference) is not distinct from lower(v_reference)
    and v_order.verified_amount_minor is not distinct from p_verified_amount_minor
    and v_order.verified_paid_at is not distinct from p_verified_paid_at
    and v_order.decision_reason is not distinct from v_reason
    and v_order.exception_reason is not distinct from v_exception then
    return billing.checkout_order_projection(v_order, true);
  end if;
  if v_order.status not in ('awaiting_payment', 'under_review', 'payment_rejected') or v_order.price_minor = 0 then
    raise exception using errcode = '40001', message = 'SUBSCRIPTION_ORDER_NOT_REVIEWABLE';
  end if;
  if length(v_reference) not between 3 and 160 or v_reference ~ '[[:cntrl:]]'
    or p_verified_amount_minor not between 0 and 999999999999
    or (p_verified_paid_at is not null and (not isfinite(p_verified_paid_at) or p_verified_paid_at > statement_timestamp()))
    or length(v_reason) > 500 or length(v_exception) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_SUBSCRIPTION_REVIEW';
  end if;
  if p_approved then
    if v_reference is null or p_verified_amount_minor is distinct from v_order.price_minor
      or p_verified_paid_at is null then
      raise exception using errcode = '22023', message = 'SUBSCRIPTION_VERIFIED_PAYMENT_REQUIRED';
    end if;
    if lower(v_reference) is distinct from lower(v_order.transfer_reference)
      or p_verified_paid_at < v_order.created_at or p_verified_paid_at > v_order.expires_at then
      raise exception using errcode = '22023', message = 'SUBSCRIPTION_PAYMENT_NOT_MATCHED';
    end if;
    v_order := billing.checkout_settle(v_order, auth.uid(), v_reference,
      p_verified_amount_minor, p_verified_paid_at, v_reason, v_exception);
  else
    if coalesce(length(v_reason), 0) < 5 then
      raise exception using errcode = '22023', message = 'SUBSCRIPTION_REJECTION_REASON_REQUIRED';
    end if;
    update billing.subscription_checkout_orders
    set status = 'payment_rejected', verified_reference = v_reference, verified_amount_minor = p_verified_amount_minor,
        verified_paid_at = p_verified_paid_at, reviewed_by = auth.uid(), reviewed_at = statement_timestamp(),
        decision_reason = v_reason, exception_reason = v_exception
    where id = p_order_id returning * into v_order;
    insert into billing.subscription_checkout_events (tenant_id, order_id, actor_id, event_type, details)
    values (v_order.tenant_id, v_order.id, auth.uid(), 'payment_rejected', jsonb_build_object(
      'reason', v_reason, 'exception', v_exception, 'verified_reference', v_reference,
      'verified_amount_minor', p_verified_amount_minor, 'verified_paid_at', p_verified_paid_at));
  end if;
  return billing.checkout_order_projection(v_order, true);
end;
$$;

create function api.platform_rename_subscription_organization(p_tenant_id uuid, p_name text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_before text;
  v_name text := nullif(trim(p_name), '');
  v_reason text := nullif(trim(p_reason), '');
begin
  perform intelligence_control.operator_required('organization');
  if v_name is null or length(v_name) not between 2 and 160 or v_name ~ '[[:cntrl:]]'
    or v_reason is null or length(v_reason) not between 5 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_ORGANIZATION_RENAME';
  end if;
  select name into v_before from core.tenants
  where id = p_tenant_id and status in ('trial', 'active') for update;
  if not found then
    raise exception using errcode = '42501', message = 'ORGANIZATION_UNAVAILABLE';
  end if;
  if v_name is distinct from v_before then
    update core.tenants set name = v_name, version = version + 1, updated_at = statement_timestamp()
    where id = p_tenant_id;
    insert into audit.events (tenant_id, actor_id, request_id, event_type,
      aggregate_type, aggregate_id, before_context, after_context, metadata)
    values (p_tenant_id, auth.uid(), gen_random_uuid(), 'organization.renamed', 'tenant', p_tenant_id,
      jsonb_build_object('name', v_before), jsonb_build_object('name', v_name),
      jsonb_build_object('reason', v_reason));
  end if;
end;
$$;

revoke all on function billing.reserve_subscription_payment_reference(text),
  billing.organization_reserve_payment_reference(), billing.reserve_subscription_username(text, uuid),
  billing.checkout_current_buyer_email(uuid), billing.checkout_verified_email(uuid), billing.checkout_required(),
  billing.checkout_expired(uuid), billing.checkout_can_renew(uuid, uuid),
  billing.checkout_order_projection(billing.subscription_checkout_orders, boolean),
  billing.checkout_settle(billing.subscription_checkout_orders, uuid, text, bigint, timestamptz, text, text)
from public, anon, authenticated;

revoke all on function api.subscription_record_buyer_verification(uuid, text) from public, anon, authenticated;
grant execute on function api.subscription_record_buyer_verification(uuid, text) to service_role;

revoke all on function api.subscription_checkout_access(), api.subscription_checkout_catalog(),
  api.subscription_checkout_orders(), api.subscription_create_order(text, bigint, text, uuid, uuid),
  api.subscription_submit_payment(uuid, text), api.platform_subscription_checkout_settings(),
  api.platform_save_subscription_bank(text, text, text, text, text),
  api.platform_save_subscription_publication(text, bigint, text, text[], text, text, integer, boolean),
  api.platform_subscription_checkout_queue(integer),
  api.platform_review_subscription_payment(uuid, boolean, text, bigint, timestamptz, text, text),
  api.platform_rename_subscription_organization(uuid, text, text)
from public, anon, authenticated;
grant execute on function api.subscription_checkout_access(), api.subscription_checkout_catalog(),
  api.subscription_checkout_orders(), api.subscription_create_order(text, bigint, text, uuid, uuid),
  api.subscription_submit_payment(uuid, text), api.platform_subscription_checkout_settings(),
  api.platform_save_subscription_bank(text, text, text, text, text),
  api.platform_save_subscription_publication(text, bigint, text, text[], text, text, integer, boolean),
  api.platform_subscription_checkout_queue(integer),
  api.platform_review_subscription_payment(uuid, boolean, text, bigint, timestamptz, text, text),
  api.platform_rename_subscription_organization(uuid, text, text)
to authenticated;
