-- Wave 3 CRM pipeline foundation.
--
-- Adds tenant-scoped leads, activities, and opportunities with exact numeric
-- storage, complete command attribution, forced RLS, and security-invoker read
-- models. Mutations are intentionally withheld from desktop roles.

-- ---------------------------------------------------------------------------
-- Shared party attribution used when a lead conversion creates party records.
-- ---------------------------------------------------------------------------

alter table crm.parties
  add column request_id uuid,
  add column command_id uuid,
  add column correlation_id uuid,
  add column source_context jsonb not null default '{}'::jsonb,
  add column client_timestamp timestamptz;

alter table crm.contacts
  add column request_id uuid,
  add column command_id uuid,
  add column correlation_id uuid,
  add column source_context jsonb not null default '{}'::jsonb,
  add column client_timestamp timestamptz;

alter table crm.parties
  add constraint parties_wave3_source_context_check
    check (jsonb_typeof(source_context) = 'object') not valid;
alter table crm.contacts
  add constraint contacts_wave3_source_context_check
    check (jsonb_typeof(source_context) = 'object') not valid;
alter table crm.parties validate constraint parties_wave3_source_context_check;
alter table crm.contacts validate constraint contacts_wave3_source_context_check;

create index parties_wave3_command_idx
  on crm.parties (tenant_id, command_id, id) where command_id is not null;
create index parties_wave3_correlation_idx
  on crm.parties (tenant_id, correlation_id, id) where correlation_id is not null;
create index contacts_wave3_command_idx
  on crm.contacts (tenant_id, command_id, id) where command_id is not null;
create index contacts_wave3_correlation_idx
  on crm.contacts (tenant_id, correlation_id, id) where correlation_id is not null;

-- ---------------------------------------------------------------------------
-- CRM aggregates.
-- Canonical workflow states map to CRM language as follows:
-- draft=new, submitted=qualification, approved=qualified, posted=converted.
-- ---------------------------------------------------------------------------

create table crm.leads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,31}$'),
  lead_type text not null check (lead_type in ('person', 'organization')),
  name text not null check (length(trim(name)) between 2 and 180),
  contact_name text check (
    contact_name is null or length(trim(contact_name)) between 2 and 140
  ),
  email text check (email is null or position('@' in email) > 1),
  phone text,
  party_id uuid,
  contact_id uuid,
  source text not null check (length(trim(source)) between 1 and 100),
  owner_id uuid not null references auth.users(id),
  stage text not null default 'draft'
    check (stage in ('draft', 'submitted', 'approved', 'rejected', 'cancelled', 'posted')),
  stage_entered_at timestamptz not null default now(),
  expected_value numeric(20, 6) not null default 0 check (expected_value >= 0),
  currency_code text not null references core.currencies(code),
  expected_close_date date not null,
  qualification_data jsonb not null default '{}'::jsonb
    check (jsonb_typeof(qualification_data) = 'object'),
  loss_reason text check (
    loss_reason is null or length(trim(loss_reason)) between 1 and 1000
  ),
  status text not null default 'active'
    check (status in ('active', 'converted', 'inactive')),
  converted_opportunity_id uuid,
  converted_at timestamptz,
  converted_by uuid references auth.users(id),
  version bigint not null default 1 check (version > 0),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  client_timestamp timestamptz not null,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, legal_entity_id, id),
  unique (tenant_id, legal_entity_id, code),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, party_id)
    references crm.parties(tenant_id, id),
  foreign key (tenant_id, contact_id)
    references crm.contacts(tenant_id, id),
  check (branch_id is null or legal_entity_id is not null),
  check (contact_id is null or party_id is not null),
  check (
    stage <> 'approved'
    or qualification_data <> '{}'::jsonb
  ),
  check (
    stage not in ('rejected', 'cancelled')
    or loss_reason is not null
  ),
  check (
    (
      status = 'converted'
      and stage = 'posted'
      and party_id is not null
      and contact_id is not null
      and converted_opportunity_id is not null
      and converted_at is not null
      and converted_by is not null
    )
    or (
      status <> 'converted'
      and stage <> 'posted'
      and converted_opportunity_id is null
      and converted_at is null
      and converted_by is null
    )
  )
);

create table crm.activities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  aggregate_type text not null
    check (aggregate_type in ('lead', 'opportunity', 'party', 'contact')),
  aggregate_id uuid not null,
  activity_type text not null
    check (activity_type ~ '^[a-z][a-z0-9_.-]{1,39}$'),
  subject text not null check (length(trim(subject)) between 2 and 180),
  owner_id uuid not null references auth.users(id),
  activity_at timestamptz not null,
  due_at timestamptz,
  completed_at timestamptz,
  outcome text check (outcome is null or length(trim(outcome)) between 1 and 2000),
  notes text check (notes is null or length(notes) <= 10000),
  status text not null default 'planned'
    check (status in ('planned', 'completed', 'cancelled')),
  version bigint not null default 1 check (version > 0),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  client_timestamp timestamptz not null,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  check (branch_id is null or legal_entity_id is not null),
  check (due_at is null or due_at >= activity_at),
  check (
    (status = 'completed' and completed_at is not null and outcome is not null)
    or (status <> 'completed' and completed_at is null)
  ),
  check (completed_at is null or completed_at >= activity_at)
);

create table crm.opportunities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,31}$'),
  source_lead_id uuid,
  party_id uuid,
  contact_id uuid,
  prospect_name text check (
    prospect_name is null or length(trim(prospect_name)) between 2 and 180
  ),
  owner_id uuid not null references auth.users(id),
  stage text not null default 'draft'
    check (stage in ('draft', 'submitted', 'approved', 'rejected', 'posted', 'closed', 'cancelled')),
  probability numeric(5, 2) not null default 0
    check (probability between 0 and 100),
  expected_value numeric(20, 6) not null default 0 check (expected_value >= 0),
  weighted_value numeric(20, 6) generated always as (
    round(expected_value * probability / 100::numeric, 6)
  ) stored,
  currency_code text not null references core.currencies(code),
  expected_close_date date not null,
  next_action text check (
    next_action is null or length(trim(next_action)) between 1 and 1000
  ),
  products_of_interest jsonb not null default '[]'::jsonb
    check (jsonb_typeof(products_of_interest) = 'array'),
  forecast_bucket text not null default 'pipeline'
    check (forecast_bucket in ('pipeline', 'best_case', 'commit', 'closed')),
  won_loss_reason text check (
    won_loss_reason is null or length(trim(won_loss_reason)) between 1 and 1000
  ),
  status text not null default 'open'
    check (status in ('open', 'won', 'lost', 'inactive')),
  version bigint not null default 1 check (version > 0),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  client_timestamp timestamptz not null,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, legal_entity_id, id),
  unique (tenant_id, legal_entity_id, code),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, source_lead_id)
    references crm.leads(tenant_id, id),
  foreign key (tenant_id, party_id)
    references crm.parties(tenant_id, id),
  foreign key (tenant_id, contact_id)
    references crm.contacts(tenant_id, id),
  check (branch_id is null or legal_entity_id is not null),
  check (party_id is not null or prospect_name is not null),
  check (contact_id is null or party_id is not null),
  check (
    status <> 'won'
    or (
      stage = 'closed' and probability = 100
      and forecast_bucket = 'closed' and won_loss_reason is not null
    )
  ),
  check (
    status <> 'lost'
    or (
      stage in ('closed', 'rejected', 'cancelled') and probability = 0
      and forecast_bucket = 'closed' and won_loss_reason is not null
    )
  )
);

alter table crm.leads
  add constraint leads_converted_opportunity_fkey
  foreign key (tenant_id, converted_opportunity_id)
  references crm.opportunities(tenant_id, id);

create unique index opportunities_source_lead_uidx
  on crm.opportunities (tenant_id, source_lead_id)
  where source_lead_id is not null;

-- ---------------------------------------------------------------------------
-- Cover tenant filters, dashboard paths, and every new foreign key.
-- ---------------------------------------------------------------------------

create index leads_scope_stage_idx
  on crm.leads (
    tenant_id, legal_entity_id, branch_id, stage, status,
    expected_close_date, id
  );
create index leads_branch_fk_idx on crm.leads (tenant_id, branch_id);
create index leads_owner_fk_idx on crm.leads (owner_id);
create index leads_party_fk_idx on crm.leads (tenant_id, party_id);
create index leads_contact_fk_idx on crm.leads (tenant_id, contact_id);
create index leads_converted_opportunity_fk_idx
  on crm.leads (tenant_id, converted_opportunity_id);
create index leads_currency_fk_idx on crm.leads (currency_code);
create index leads_converted_by_fk_idx on crm.leads (converted_by);
create index leads_created_by_fk_idx on crm.leads (created_by);
create index leads_updated_by_fk_idx on crm.leads (updated_by);
create index leads_correlation_idx
  on crm.leads (tenant_id, correlation_id, id);

create index activities_aggregate_idx
  on crm.activities (
    tenant_id, aggregate_type, aggregate_id, activity_at desc, id
  );
create index activities_scope_status_idx
  on crm.activities (
    tenant_id, legal_entity_id, branch_id, status, due_at, id
  );
create index activities_branch_fk_idx on crm.activities (tenant_id, branch_id);
create index activities_owner_fk_idx on crm.activities (owner_id);
create index activities_created_by_fk_idx on crm.activities (created_by);
create index activities_updated_by_fk_idx on crm.activities (updated_by);
create index activities_correlation_idx
  on crm.activities (tenant_id, correlation_id, id);

create index opportunities_scope_forecast_idx
  on crm.opportunities (
    tenant_id, legal_entity_id, branch_id, forecast_bucket, status,
    expected_close_date, id
  );
create index opportunities_branch_fk_idx
  on crm.opportunities (tenant_id, branch_id);
create index opportunities_owner_fk_idx on crm.opportunities (owner_id);
create index opportunities_party_fk_idx
  on crm.opportunities (tenant_id, party_id);
create index opportunities_contact_fk_idx
  on crm.opportunities (tenant_id, contact_id);
create index opportunities_source_lead_fk_idx
  on crm.opportunities (tenant_id, source_lead_id);
create index opportunities_currency_fk_idx on crm.opportunities (currency_code);
create index opportunities_created_by_fk_idx on crm.opportunities (created_by);
create index opportunities_updated_by_fk_idx on crm.opportunities (updated_by);
create index opportunities_correlation_idx
  on crm.opportunities (tenant_id, correlation_id, id);

create trigger leads_touch before update on crm.leads
  for each row execute function core.touch_mutable_record();
create trigger activities_touch before update on crm.activities
  for each row execute function core.touch_mutable_record();
create trigger opportunities_touch before update on crm.opportunities
  for each row execute function core.touch_mutable_record();

-- ---------------------------------------------------------------------------
-- Forced RLS and select-only desktop access.
-- ---------------------------------------------------------------------------

alter table crm.leads enable row level security;
alter table crm.leads force row level security;
alter table crm.activities enable row level security;
alter table crm.activities force row level security;
alter table crm.opportunities enable row level security;
alter table crm.opportunities force row level security;

create policy leads_permitted_read on crm.leads
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    core.has_permission(
      tenant_id, 'crm.leads.view', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'crm.leads.manage', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'crm.leads.convert', legal_entity_id, branch_id
    )
  )
);

create policy activities_permitted_read on crm.activities
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    core.has_permission(
      tenant_id, 'crm.activities.manage', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'crm.leads.view', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'crm.opportunities.view', legal_entity_id, branch_id
    )
  )
);

create policy opportunities_permitted_read on crm.opportunities
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    core.has_permission(
      tenant_id, 'crm.opportunities.view', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'crm.opportunities.manage', legal_entity_id, branch_id
    )
  )
);

-- ---------------------------------------------------------------------------
-- Versioned API read models. Exact numbers cross the boundary as strings.
-- Existing party/contact columns retain their order; attribution is appended.
-- ---------------------------------------------------------------------------

create or replace view api.parties
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id, code,
  display_name as name, legal_name, display_name, kind, tax_identifier,
  email, phone, address_line_1, address_line_2, city, country_code,
  credit_limit::text as credit_limit, credit_currency_code,
  payment_terms_days, status, version, created_at, updated_at,
  request_id, command_id, correlation_id, source_context, client_timestamp
from crm.parties;

create or replace view api.contacts
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id, party_id,
  left(name, 24) as code, name, role, email, phone, is_primary,
  status, version, created_at, updated_at,
  request_id, command_id, correlation_id, source_context, client_timestamp
from crm.contacts;

create view api.crm_leads
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, code, lead_type, name,
  contact_name, email, phone, party_id, contact_id, source, owner_id,
  stage, stage_entered_at, expected_value::text as expected_value,
  currency_code, expected_close_date, qualification_data, loss_reason,
  status, converted_opportunity_id, converted_at, converted_by, version,
  request_id, command_id, correlation_id, source_context, client_timestamp,
  created_by, updated_by, created_at, updated_at
from crm.leads;

create view api.crm_activities
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, aggregate_type, aggregate_id,
  activity_type, subject, owner_id, activity_at, due_at, completed_at,
  outcome, notes, status, version, request_id, command_id, correlation_id,
  source_context, client_timestamp, created_by, updated_by,
  created_at, updated_at
from crm.activities;

create view api.crm_opportunities
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, code, source_lead_id,
  party_id, contact_id, prospect_name, owner_id, stage,
  probability::text as probability,
  expected_value::text as expected_value,
  weighted_value::text as weighted_value,
  currency_code, expected_close_date, next_action, products_of_interest,
  forecast_bucket, won_loss_reason, status, version,
  request_id, command_id, correlation_id, source_context, client_timestamp,
  created_by, updated_by, created_at, updated_at
from crm.opportunities;

create view api.crm_pipeline_entries
with (security_invoker = true)
as
select
  'lead'::text as entry_type, l.id, l.tenant_id, l.legal_entity_id,
  l.branch_id, l.code, l.name, l.owner_id, l.stage, l.status,
  null::text as probability, l.expected_value::text as expected_value,
  null::text as weighted_value, l.currency_code, l.expected_close_date,
  l.stage_entered_at, l.created_at,
  (
    select max(a.activity_at)
    from crm.activities as a
    where a.tenant_id = l.tenant_id
      and a.aggregate_type = 'lead' and a.aggregate_id = l.id
  ) as last_activity_at
from crm.leads as l
union all
select
  'opportunity'::text, o.id, o.tenant_id, o.legal_entity_id,
  o.branch_id, o.code, coalesce(p.display_name, o.prospect_name),
  o.owner_id, o.stage, o.status, o.probability::text,
  o.expected_value::text, o.weighted_value::text, o.currency_code,
  o.expected_close_date, o.updated_at, o.created_at,
  (
    select max(a.activity_at)
    from crm.activities as a
    where a.tenant_id = o.tenant_id
      and a.aggregate_type = 'opportunity' and a.aggregate_id = o.id
  )
from crm.opportunities as o
left join crm.parties as p
  on p.tenant_id = o.tenant_id and p.id = o.party_id;

revoke all on crm.leads, crm.activities, crm.opportunities
  from public, anon, authenticated;
grant select on crm.leads, crm.activities, crm.opportunities
  to authenticated;

revoke all on api.crm_leads, api.crm_activities, api.crm_opportunities,
  api.crm_pipeline_entries from public, anon, authenticated;
grant select on api.crm_leads, api.crm_activities, api.crm_opportunities,
  api.crm_pipeline_entries to authenticated;

comment on table crm.leads is
  'Tenant-scoped Wave 3 leads governed by an active canonical CRM workflow.';
comment on table crm.activities is
  'Attributable CRM interactions against one tenant-scoped aggregate.';
comment on table crm.opportunities is
  'Exact-value CRM opportunities with generated weighted forecast values.';

notify pgrst, 'reload schema';
