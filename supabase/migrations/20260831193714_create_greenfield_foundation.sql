-- Jentra OS Wave 1 foundation — FR-1..FR-16, NFR-2, NFR-4, AC-2..AC-8.
-- Base relations stay outside the Data API. The api schema is the only client
-- database surface and grants are deliberately opt-in.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists core;
create schema if not exists crm;
create schema if not exists sales;
create schema if not exists procurement;
create schema if not exists inventory;
create schema if not exists finance;
create schema if not exists people;
create schema if not exists projects;
create schema if not exists service;
create schema if not exists workflow;
create schema if not exists billing;
create schema if not exists ai;
create schema if not exists audit;
create schema if not exists api;

revoke all on schema public from anon, authenticated;
revoke all on schema core, crm, sales, procurement, inventory, finance,
  people, projects, service, workflow, billing, ai, audit, api
  from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Foundation hierarchy and authorization
-- ---------------------------------------------------------------------------

create table core.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,62}$'),
  status text not null default 'active'
    check (status in ('trial', 'active', 'suspended', 'closed')),
  timezone text not null default 'Asia/Colombo',
  default_currency_code text not null default 'LKR'
    check (default_currency_code ~ '^[A-Z]{3}$'),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, status)
);

create table core.legal_entities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  name text not null check (length(trim(name)) between 2 and 180),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,19}$'),
  registration_number text,
  tax_identifier text,
  currency_code text not null default 'LKR' check (currency_code ~ '^[A-Z]{3}$'),
  timezone text not null default 'Asia/Colombo',
  accounting_basis text not null default 'accrual' check (accounting_basis = 'accrual'),
  inventory_valuation text not null default 'weighted_average'
    check (inventory_valuation = 'weighted_average'),
  rounding_scale smallint not null default 2 check (rounding_scale between 0 and 6),
  posting_started_at timestamptz,
  status text not null default 'active' check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table core.branches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  name text not null check (length(trim(name)) between 2 and 160),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,19}$'),
  timezone text not null default 'Asia/Colombo',
  status text not null default 'active' check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, legal_entity_id, code),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id)
);

create table core.warehouses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  name text not null check (length(trim(name)) between 2 and 160),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,19}$'),
  status text not null default 'active' check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, branch_id, code),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id)
);

create table core.memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'active'
    check (status in ('invited', 'active', 'suspended', 'revoked')),
  invited_by uuid references auth.users(id),
  joined_at timestamptz,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, user_id)
);

create table core.roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  code text not null check (code ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  name text not null check (length(trim(name)) between 2 and 100),
  description text,
  requires_mfa boolean not null default false,
  is_system boolean not null default false,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table core.permissions (
  code text primary key check (code ~ '^[a-z][a-z0-9_.-]{2,99}$'),
  module text not null,
  description text not null,
  privileged boolean not null default false
);

create table core.role_permissions (
  tenant_id uuid not null references core.tenants(id),
  role_id uuid not null,
  permission_code text not null references core.permissions(code),
  created_at timestamptz not null default now(),
  primary key (role_id, permission_code),
  foreign key (tenant_id, role_id) references core.roles(tenant_id, id)
);

create table core.role_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  membership_id uuid not null,
  role_id uuid not null,
  legal_entity_id uuid,
  branch_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (membership_id, role_id, legal_entity_id, branch_id),
  foreign key (tenant_id, membership_id)
    references core.memberships(tenant_id, id),
  foreign key (tenant_id, role_id) references core.roles(tenant_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id),
  check (branch_id is null or legal_entity_id is not null)
);

create table core.invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  email text not null check (position('@' in email) > 1),
  role_id uuid not null,
  legal_entity_id uuid,
  branch_id uuid,
  token_hash bytea not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null,
  invited_by uuid not null references auth.users(id),
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (tenant_id, role_id) references core.roles(tenant_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id),
  check (branch_id is null or legal_entity_id is not null)
);

create unique index invitations_pending_email_idx
  on core.invitations (tenant_id, lower(email))
  where status = 'pending';

create table core.command_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  actor_id uuid not null references auth.users(id),
  idempotency_key uuid not null,
  command_name text not null,
  request_id uuid not null default gen_random_uuid(),
  response jsonb,
  error jsonb,
  created_at timestamptz not null default now(),
  unique (actor_id, idempotency_key)
);

create table core.outbox_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  topic text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  payload jsonb not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Plans, approvals, and attributable audit
-- ---------------------------------------------------------------------------

create table billing.plans (
  code text primary key,
  name text not null,
  status text not null default 'active' check (status in ('active', 'retired')),
  trial_days integer not null default 30 check (trial_days between 0 and 365),
  created_at timestamptz not null default now()
);

create table billing.plan_entitlements (
  plan_code text not null references billing.plans(code),
  entitlement_code text not null,
  enabled boolean not null default true,
  numeric_limit numeric(20, 6),
  primary key (plan_code, entitlement_code)
);

create table billing.tenant_subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  plan_code text not null references billing.plans(code),
  status text not null default 'trialing'
    check (status in ('trialing', 'active', 'past_due', 'suspended', 'cancelled')),
  seats integer not null default 5 check (seats > 0),
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id)
);

create table workflow.approval_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid,
  branch_id uuid,
  document_type text not null,
  document_id uuid not null,
  status text not null default 'submitted'
    check (status in ('submitted', 'approved', 'rejected', 'cancelled')),
  submitted_by uuid not null references auth.users(id),
  assigned_to uuid references auth.users(id),
  decision_by uuid references auth.users(id),
  decision_note text,
  submitted_at timestamptz not null default now(),
  decided_at timestamptz,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id)
);

create table audit.events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  event_type text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  legal_entity_id uuid,
  branch_id uuid,
  before_context jsonb,
  after_context jsonb,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id)
);

-- ---------------------------------------------------------------------------
-- Indexes for membership, scope, cursor, and outbox paths
-- ---------------------------------------------------------------------------

create index memberships_user_status_idx
  on core.memberships (user_id, status, tenant_id);
create index memberships_tenant_status_idx
  on core.memberships (tenant_id, status, user_id);
create index legal_entities_tenant_status_idx
  on core.legal_entities (tenant_id, status, id);
create index branches_tenant_entity_status_idx
  on core.branches (tenant_id, legal_entity_id, status, id);
create index warehouses_tenant_branch_status_idx
  on core.warehouses (tenant_id, branch_id, status, id);
create index role_assignments_membership_scope_idx
  on core.role_assignments (membership_id, legal_entity_id, branch_id);
create index role_permissions_tenant_permission_idx
  on core.role_permissions (tenant_id, permission_code, role_id);
create index command_receipts_tenant_created_idx
  on core.command_receipts (tenant_id, created_at desc);
create index outbox_pending_idx
  on core.outbox_events (status, available_at, id)
  where status in ('pending', 'processing');
create index approval_requests_tenant_status_idx
  on workflow.approval_requests (tenant_id, status, submitted_at desc);
create index audit_events_tenant_occurred_idx
  on audit.events (tenant_id, occurred_at desc, id);
create index audit_events_aggregate_idx
  on audit.events (tenant_id, aggregate_type, aggregate_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Private authorization helpers. They are not in the exposed api schema.
-- ---------------------------------------------------------------------------

create function core.is_tenant_member(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from core.memberships as m
      where m.tenant_id = p_tenant_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
    );
$$;

create function core.has_permission(
  p_tenant_id uuid,
  p_permission_code text,
  p_legal_entity_id uuid default null,
  p_branch_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from core.memberships as m
      join core.role_assignments as ra
        on ra.tenant_id = m.tenant_id and ra.membership_id = m.id
      join core.roles as r
        on r.tenant_id = ra.tenant_id and r.id = ra.role_id
      join core.role_permissions as rp
        on rp.tenant_id = r.tenant_id and rp.role_id = r.id
      where m.tenant_id = p_tenant_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
        and rp.permission_code = p_permission_code
        and (ra.legal_entity_id is null or ra.legal_entity_id = p_legal_entity_id)
        and (ra.branch_id is null or ra.branch_id = p_branch_id)
        and (
          not r.requires_mfa
          or coalesce((select auth.jwt()->>'aal'), 'aal1') = 'aal2'
        )
    );
$$;

create function core.require_permission(
  p_tenant_id uuid,
  p_permission_code text,
  p_legal_entity_id uuid default null,
  p_branch_id uuid default null
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if not core.has_permission(
    p_tenant_id,
    p_permission_code,
    p_legal_entity_id,
    p_branch_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Permission denied or multi-factor authentication required.';
  end if;
end;
$$;

create function core.list_capabilities(p_tenant_id uuid)
returns table (permission_code text)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct rp.permission_code
  from core.memberships as m
  join core.role_assignments as ra
    on ra.tenant_id = m.tenant_id and ra.membership_id = m.id
  join core.roles as r
    on r.tenant_id = ra.tenant_id and r.id = ra.role_id
  join core.role_permissions as rp
    on rp.tenant_id = r.tenant_id and rp.role_id = r.id
  where m.tenant_id = p_tenant_id
    and m.user_id = (select auth.uid())
    and m.status = 'active'
    and (
      not r.requires_mfa
      or coalesce((select auth.jwt()->>'aal'), 'aal1') = 'aal2'
    )
  order by rp.permission_code;
$$;

create function core.touch_mutable_record()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  new.version := old.version + 1;
  return new;
end;
$$;

create function audit.reject_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'Audit events are append-only.';
end;
$$;

create trigger tenants_touch before update on core.tenants
  for each row execute function core.touch_mutable_record();
create trigger legal_entities_touch before update on core.legal_entities
  for each row execute function core.touch_mutable_record();
create trigger branches_touch before update on core.branches
  for each row execute function core.touch_mutable_record();
create trigger warehouses_touch before update on core.warehouses
  for each row execute function core.touch_mutable_record();
create trigger memberships_touch before update on core.memberships
  for each row execute function core.touch_mutable_record();
create trigger roles_touch before update on core.roles
  for each row execute function core.touch_mutable_record();
create trigger subscriptions_touch before update on billing.tenant_subscriptions
  for each row execute function core.touch_mutable_record();
create trigger approval_requests_touch before update on workflow.approval_requests
  for each row execute function core.touch_mutable_record();
create trigger audit_events_immutable
  before update or delete on audit.events
  for each row execute function audit.reject_event_mutation();

-- ---------------------------------------------------------------------------
-- RLS defense in depth on every tenant-bearing table
-- ---------------------------------------------------------------------------

alter table core.tenants enable row level security;
alter table core.legal_entities enable row level security;
alter table core.branches enable row level security;
alter table core.warehouses enable row level security;
alter table core.memberships enable row level security;
alter table core.roles enable row level security;
alter table core.role_permissions enable row level security;
alter table core.role_assignments enable row level security;
alter table core.invitations enable row level security;
alter table core.command_receipts enable row level security;
alter table core.outbox_events enable row level security;
alter table billing.tenant_subscriptions enable row level security;
alter table workflow.approval_requests enable row level security;
alter table audit.events enable row level security;

create policy tenants_member_read on core.tenants
  for select to authenticated
  using (core.is_tenant_member(id));
create policy legal_entities_member_read on core.legal_entities
  for select to authenticated
  using (core.is_tenant_member(tenant_id));
create policy branches_member_read on core.branches
  for select to authenticated
  using (core.is_tenant_member(tenant_id));
create policy warehouses_member_read on core.warehouses
  for select to authenticated
  using (core.is_tenant_member(tenant_id));
create policy memberships_self_read on core.memberships
  for select to authenticated
  using (user_id = (select auth.uid()));
create policy roles_member_read on core.roles
  for select to authenticated
  using (core.is_tenant_member(tenant_id));
create policy role_permissions_member_read on core.role_permissions
  for select to authenticated
  using (core.is_tenant_member(tenant_id));
create policy role_assignments_self_read on core.role_assignments
  for select to authenticated
  using (
    exists (
      select 1
      from core.memberships as m
      where m.id = membership_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
    )
  );
create policy invitations_invitee_or_manager_read on core.invitations
  for select to authenticated
  using (
    lower(email) = lower(coalesce((select auth.jwt()->>'email'), ''))
    or core.has_permission(tenant_id, 'core.members.invite')
  );
create policy command_receipts_actor_read on core.command_receipts
  for select to authenticated
  using (actor_id = (select auth.uid()));
create policy subscriptions_member_read on billing.tenant_subscriptions
  for select to authenticated
  using (core.is_tenant_member(tenant_id));
create policy approvals_member_read on workflow.approval_requests
  for select to authenticated
  using (core.is_tenant_member(tenant_id));
create policy audit_permitted_read on audit.events
  for select to authenticated
  using (core.has_permission(tenant_id, 'audit.read', legal_entity_id, branch_id));

-- No policies are intentionally created for core.outbox_events. Data API roles
-- cannot read or mutate the integration queue.

-- ---------------------------------------------------------------------------
-- Seed configurable plans and the permission vocabulary
-- ---------------------------------------------------------------------------

insert into core.permissions (code, module, description, privileged) values
  ('core.tenant.manage', 'core', 'Manage tenant and company configuration.', true),
  ('core.members.invite', 'core', 'Invite and scope tenant members.', true),
  ('core.roles.manage', 'core', 'Manage roles and permission assignments.', true),
  ('workflow.approve', 'workflow', 'Review and decide assigned approvals.', true),
  ('billing.read', 'billing', 'View plan, entitlement, and usage information.', false),
  ('audit.read', 'audit', 'Read attributable audit history.', true),
  ('crm.view', 'crm', 'Open CRM and revenue workspaces.', false),
  ('sales.view', 'sales', 'Open sales workspaces.', false),
  ('procurement.view', 'procurement', 'Open procurement workspaces.', false),
  ('inventory.view', 'inventory', 'Open inventory workspaces.', false),
  ('finance.view', 'finance', 'Open finance workspaces.', true),
  ('people.view', 'people', 'Open people workspaces.', true),
  ('projects.view', 'projects', 'Open project workspaces.', false),
  ('service.view', 'service', 'Open service workspaces.', false),
  ('analytics.view', 'analytics', 'Open analytics workspaces.', false),
  ('control.view', 'control', 'Open Jentra control-plane workspaces.', true)
on conflict (code) do nothing;

insert into billing.plans (code, name, trial_days) values
  ('starter', 'Starter', 30),
  ('growth', 'Growth', 30),
  ('scale', 'Scale', 30)
on conflict (code) do nothing;

insert into billing.plan_entitlements
  (plan_code, entitlement_code, enabled, numeric_limit) values
  ('starter', 'users', true, 5),
  ('starter', 'legal_entities', true, 1),
  ('starter', 'ai_monthly_tokens', false, 0),
  ('growth', 'users', true, 50),
  ('growth', 'legal_entities', true, 5),
  ('growth', 'ai_monthly_tokens', true, 1000000),
  ('scale', 'users', true, 500),
  ('scale', 'legal_entities', true, 50),
  ('scale', 'ai_monthly_tokens', true, 10000000)
on conflict (plan_code, entitlement_code) do nothing;

-- ---------------------------------------------------------------------------
-- Transactional command implementations in the private core schema
-- ---------------------------------------------------------------------------

create function core.bootstrap_tenant_impl(
  p_name text,
  p_slug text,
  p_legal_entity_name text,
  p_legal_entity_code text,
  p_branch_name text,
  p_branch_code text,
  p_timezone text default 'Asia/Colombo',
  p_currency_code text default 'LKR',
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_tenant_id uuid := gen_random_uuid();
  v_entity_id uuid := gen_random_uuid();
  v_branch_id uuid := gen_random_uuid();
  v_membership_id uuid := gen_random_uuid();
  v_owner_role_id uuid := gen_random_uuid();
  v_request_id uuid := gen_random_uuid();
  v_response jsonb;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select cr.response into v_response
  from core.command_receipts as cr
  where cr.actor_id = v_actor and cr.idempotency_key = p_idempotency_key;
  if v_response is not null then
    return v_response;
  end if;

  if length(trim(p_name)) not between 2 and 160 then
    raise exception using errcode = '22023', message = 'Business name is invalid.';
  end if;
  if lower(trim(p_slug)) !~ '^[a-z0-9][a-z0-9-]{2,62}$' then
    raise exception using errcode = '22023', message = 'Business slug is invalid.';
  end if;
  if upper(trim(p_currency_code)) !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Currency code is invalid.';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_timezone_names as tz where tz.name = p_timezone
  ) then
    raise exception using errcode = '22023', message = 'Time zone is invalid.';
  end if;

  insert into core.tenants (
    id, name, slug, status, timezone, default_currency_code, created_by
  ) values (
    v_tenant_id,
    trim(p_name),
    lower(trim(p_slug)),
    'trial',
    p_timezone,
    upper(trim(p_currency_code)),
    v_actor
  );

  insert into core.legal_entities (
    id, tenant_id, name, code, currency_code, timezone, created_by
  ) values (
    v_entity_id,
    v_tenant_id,
    trim(p_legal_entity_name),
    upper(trim(p_legal_entity_code)),
    upper(trim(p_currency_code)),
    p_timezone,
    v_actor
  );

  insert into core.branches (
    id, tenant_id, legal_entity_id, name, code, timezone, created_by
  ) values (
    v_branch_id,
    v_tenant_id,
    v_entity_id,
    trim(p_branch_name),
    upper(trim(p_branch_code)),
    p_timezone,
    v_actor
  );

  insert into core.memberships (
    id, tenant_id, user_id, status, invited_by, joined_at
  ) values (
    v_membership_id, v_tenant_id, v_actor, 'active', v_actor, now()
  );

  insert into core.roles (
    id, tenant_id, code, name, description, requires_mfa, is_system
  ) values (
    v_owner_role_id,
    v_tenant_id,
    'tenant_owner',
    'Tenant owner',
    'Full tenant authority; the session must be AAL2.',
    true,
    true
  );

  insert into core.role_permissions (tenant_id, role_id, permission_code)
  select v_tenant_id, v_owner_role_id, p.code from core.permissions as p;

  insert into core.role_assignments (
    tenant_id, membership_id, role_id, created_by
  ) values (v_tenant_id, v_membership_id, v_owner_role_id, v_actor);

  insert into billing.tenant_subscriptions (
    tenant_id, plan_code, status, seats, trial_ends_at
  ) values (
    v_tenant_id, 'starter', 'trialing', 5, now() + interval '30 days'
  );

  v_response := jsonb_build_object(
    'request_id', v_request_id,
    'tenant_id', v_tenant_id,
    'legal_entity_id', v_entity_id,
    'branch_id', v_branch_id,
    'membership_id', v_membership_id,
    'mfa_required', true
  );

  insert into audit.events (
    tenant_id, actor_id, request_id, event_type, aggregate_type,
    aggregate_id, legal_entity_id, branch_id, after_context
  ) values (
    v_tenant_id,
    v_actor,
    v_request_id,
    'tenant.created',
    'tenant',
    v_tenant_id,
    v_entity_id,
    v_branch_id,
    v_response
  );

  insert into core.outbox_events (
    tenant_id, topic, aggregate_type, aggregate_id, payload
  ) values (
    v_tenant_id, 'tenant.created', 'tenant', v_tenant_id, v_response
  );

  insert into core.command_receipts (
    tenant_id, actor_id, idempotency_key, command_name, request_id, response
  ) values (
    v_tenant_id,
    v_actor,
    p_idempotency_key,
    'bootstrap_tenant',
    v_request_id,
    v_response
  );

  return v_response;
end;
$$;

create function core.create_invitation_impl(
  p_tenant_id uuid,
  p_email text,
  p_role_id uuid,
  p_legal_entity_id uuid default null,
  p_branch_id uuid default null,
  p_expires_in_hours integer default 72
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_invitation_id uuid := gen_random_uuid();
  v_request_id uuid := gen_random_uuid();
  v_raw_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  perform core.require_permission(p_tenant_id, 'core.members.invite');
  if p_expires_in_hours not between 1 and 168 then
    raise exception using errcode = '22023', message = 'Invitation expiry is invalid.';
  end if;
  if not exists (
    select 1 from core.roles as r
    where r.tenant_id = p_tenant_id and r.id = p_role_id
  ) then
    raise exception using errcode = '22023', message = 'Role is invalid.';
  end if;

  insert into core.invitations (
    id, tenant_id, email, role_id, legal_entity_id, branch_id,
    token_hash, expires_at, invited_by
  ) values (
    v_invitation_id,
    p_tenant_id,
    lower(trim(p_email)),
    p_role_id,
    p_legal_entity_id,
    p_branch_id,
    extensions.digest(v_raw_token, 'sha256'),
    now() + make_interval(hours => p_expires_in_hours),
    v_actor
  );

  insert into audit.events (
    tenant_id, actor_id, request_id, event_type, aggregate_type,
    aggregate_id, legal_entity_id, branch_id, after_context
  ) values (
    p_tenant_id,
    v_actor,
    v_request_id,
    'membership.invited',
    'invitation',
    v_invitation_id,
    p_legal_entity_id,
    p_branch_id,
    jsonb_build_object('email', lower(trim(p_email)), 'role_id', p_role_id)
  );

  insert into core.outbox_events (
    tenant_id, topic, aggregate_type, aggregate_id, payload
  ) values (
    p_tenant_id,
    'membership.invited',
    'invitation',
    v_invitation_id,
    jsonb_build_object('email', lower(trim(p_email)), 'invitation_id', v_invitation_id)
  );

  return jsonb_build_object(
    'request_id', v_request_id,
    'invitation_id', v_invitation_id,
    'token', v_raw_token,
    'expires_in_hours', p_expires_in_hours
  );
end;
$$;

create function core.accept_invitation_impl(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_email text := lower(coalesce((select auth.jwt()->>'email'), ''));
  v_invitation core.invitations%rowtype;
  v_membership_id uuid;
  v_request_id uuid := gen_random_uuid();
begin
  if v_actor is null or v_email = '' then
    raise exception using errcode = '42501', message = 'Verified authentication required.';
  end if;

  select i.* into v_invitation
  from core.invitations as i
  where i.token_hash = extensions.digest(p_token, 'sha256')
    and i.status = 'pending'
  for update;

  if not found or v_invitation.expires_at <= now() then
    raise exception using errcode = '22023', message = 'Invitation is invalid or expired.';
  end if;
  if lower(v_invitation.email) <> v_email then
    raise exception using errcode = '42501', message = 'Invitation email does not match.';
  end if;

  insert into core.memberships (
    tenant_id, user_id, status, invited_by, joined_at
  ) values (
    v_invitation.tenant_id, v_actor, 'active', v_invitation.invited_by, now()
  )
  on conflict (tenant_id, user_id) do update
    set status = 'active', joined_at = now()
  returning id into v_membership_id;

  insert into core.role_assignments (
    tenant_id, membership_id, role_id, legal_entity_id, branch_id, created_by
  ) values (
    v_invitation.tenant_id,
    v_membership_id,
    v_invitation.role_id,
    v_invitation.legal_entity_id,
    v_invitation.branch_id,
    v_invitation.invited_by
  )
  on conflict (membership_id, role_id, legal_entity_id, branch_id) do nothing;

  update core.invitations
  set status = 'accepted', accepted_by = v_actor, accepted_at = now()
  where id = v_invitation.id;

  insert into audit.events (
    tenant_id, actor_id, request_id, event_type, aggregate_type,
    aggregate_id, legal_entity_id, branch_id, after_context
  ) values (
    v_invitation.tenant_id,
    v_actor,
    v_request_id,
    'membership.joined',
    'membership',
    v_membership_id,
    v_invitation.legal_entity_id,
    v_invitation.branch_id,
    jsonb_build_object('invitation_id', v_invitation.id)
  );

  return jsonb_build_object(
    'request_id', v_request_id,
    'tenant_id', v_invitation.tenant_id,
    'membership_id', v_membership_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Versioned Data API: security-invoker reads and security-invoker wrappers.
-- Privilege escalation happens only inside validated private implementations.
-- ---------------------------------------------------------------------------

create view api.my_tenants
with (security_invoker = true)
as
select
  t.id as tenant_id,
  t.name as tenant_name,
  t.slug as tenant_slug,
  t.status as tenant_status,
  t.timezone,
  t.default_currency_code,
  m.status as membership_status,
  m.joined_at
from core.tenants as t
join core.memberships as m on m.tenant_id = t.id
where m.user_id = (select auth.uid()) and m.status = 'active';

create view api.legal_entities
with (security_invoker = true)
as
select
  id, tenant_id, name, code, registration_number, tax_identifier,
  currency_code, timezone, accounting_basis, inventory_valuation,
  rounding_scale, posting_started_at, status, version, created_at, updated_at
from core.legal_entities;

create view api.branches
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, name, code, timezone,
  status, version, created_at, updated_at
from core.branches;

create view api.warehouses
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, name, code,
  status, version, created_at, updated_at
from core.warehouses;

create view api.my_subscriptions
with (security_invoker = true)
as
select
  s.id, s.tenant_id, s.plan_code, p.name as plan_name, s.status,
  s.seats, s.trial_ends_at, s.current_period_ends_at, s.version
from billing.tenant_subscriptions as s
join billing.plans as p on p.code = s.plan_code;

create function api.list_my_tenants()
returns table (
  tenant_id uuid,
  tenant_name text,
  tenant_slug text,
  tenant_status text,
  timezone text,
  default_currency_code text,
  membership_status text,
  joined_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  select * from api.my_tenants order by tenant_name, tenant_id;
$$;

create function api.get_my_capabilities(p_tenant_id uuid)
returns table (permission_code text)
language sql
stable
set search_path = ''
as $$
  select c.permission_code from core.list_capabilities(p_tenant_id) as c;
$$;

create function api.bootstrap_tenant(
  p_name text,
  p_slug text,
  p_legal_entity_name text,
  p_legal_entity_code text,
  p_branch_name text,
  p_branch_code text,
  p_timezone text default 'Asia/Colombo',
  p_currency_code text default 'LKR',
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb
language sql
volatile
set search_path = ''
as $$
  select core.bootstrap_tenant_impl(
    p_name,
    p_slug,
    p_legal_entity_name,
    p_legal_entity_code,
    p_branch_name,
    p_branch_code,
    p_timezone,
    p_currency_code,
    p_idempotency_key
  );
$$;

create function api.create_invitation(
  p_tenant_id uuid,
  p_email text,
  p_role_id uuid,
  p_legal_entity_id uuid default null,
  p_branch_id uuid default null,
  p_expires_in_hours integer default 72
)
returns jsonb
language sql
volatile
set search_path = ''
as $$
  select core.create_invitation_impl(
    p_tenant_id,
    p_email,
    p_role_id,
    p_legal_entity_id,
    p_branch_id,
    p_expires_in_hours
  );
$$;

create function api.accept_invitation(p_token text)
returns jsonb
language sql
volatile
set search_path = ''
as $$
  select core.accept_invitation_impl(p_token);
$$;

-- ---------------------------------------------------------------------------
-- Explicit grants. No table mutation privilege is granted to client roles.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema core, audit, api from public, anon, authenticated;
revoke all on all tables in schema core, workflow, billing, audit, api
  from public, anon, authenticated;

grant usage on schema api to authenticated;
grant usage on schema core, workflow, billing, audit to authenticated;

grant select on core.tenants, core.legal_entities, core.branches,
  core.warehouses, core.memberships, core.roles, core.role_permissions,
  core.role_assignments, core.invitations, core.command_receipts
  to authenticated;
grant select on billing.plans, billing.plan_entitlements,
  billing.tenant_subscriptions to authenticated;
grant select on workflow.approval_requests to authenticated;
grant select on audit.events to authenticated;

grant select on api.my_tenants, api.legal_entities, api.branches,
  api.warehouses, api.my_subscriptions to authenticated;

grant execute on function core.is_tenant_member(uuid) to authenticated;
grant execute on function core.has_permission(uuid, text, uuid, uuid) to authenticated;
grant execute on function core.require_permission(uuid, text, uuid, uuid) to authenticated;
grant execute on function core.list_capabilities(uuid) to authenticated;
grant execute on function core.bootstrap_tenant_impl(
  text, text, text, text, text, text, text, text, uuid
) to authenticated;
grant execute on function core.create_invitation_impl(
  uuid, text, uuid, uuid, uuid, integer
) to authenticated;
grant execute on function core.accept_invitation_impl(text) to authenticated;

grant execute on function api.list_my_tenants() to authenticated;
grant execute on function api.get_my_capabilities(uuid) to authenticated;
grant execute on function api.bootstrap_tenant(
  text, text, text, text, text, text, text, text, uuid
) to authenticated;
grant execute on function api.create_invitation(
  uuid, text, uuid, uuid, uuid, integer
) to authenticated;
grant execute on function api.accept_invitation(text) to authenticated;

alter default privileges for role postgres in schema api
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema api
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema core
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema core
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema workflow
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema billing
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema audit
  revoke all on tables from public, anon, authenticated;

comment on schema api is
  'Jentra OS versioned Data API. Only security-invoker views and command wrappers.';
comment on table audit.events is
  'Append-only attributable audit events; updates and deletes are rejected.';
comment on table core.outbox_events is
  'Private idempotent integration queue processed only by trusted server workers.';

-- Keep local and hosted PostgREST aligned to the dedicated API boundary.
alter role authenticator set pgrst.db_schemas = 'api, graphql_public';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';
