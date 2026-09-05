-- Wave 3 lead-to-cash foundation, part 1: versioned quotations.
-- FR-319..FR-321 / AC-303 / NFR-302..NFR-304.

create table sales.quotations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  document_number text,
  current_revision integer not null default 1 check (current_revision > 0),
  customer_id uuid not null,
  contact_id uuid,
  opportunity_id uuid,
  quotation_date date not null,
  valid_until date not null,
  currency_code text not null references core.currencies(code),
  base_currency_code text not null references core.currencies(code),
  exchange_rate_id uuid,
  exchange_rate numeric(20, 10) not null check (exchange_rate > 0),
  rate_date date not null,
  payment_terms_days integer not null default 0
    check (payment_terms_days between 0 and 3650),
  delivery_terms text check (
    delivery_terms is null or length(trim(delivery_terms)) between 1 and 1000
  ),
  salesperson_id uuid not null references auth.users(id),
  header_discount_amount numeric(20, 6) not null default 0
    check (header_discount_amount >= 0),
  header_discount_percent numeric(12, 6)
    check (header_discount_percent between 0 and 100),
  subtotal numeric(20, 6) not null default 0 check (subtotal >= 0),
  line_discount_total numeric(20, 6) not null default 0
    check (line_discount_total >= 0),
  header_discount_total numeric(20, 6) not null default 0
    check (header_discount_total >= 0),
  discount_total numeric(20, 6) not null default 0
    check (discount_total >= 0),
  tax_total numeric(20, 6) not null default 0 check (tax_total >= 0),
  grand_total numeric(20, 6) not null default 0 check (grand_total >= 0),
  base_total numeric(20, 6) not null default 0 check (base_total >= 0),
  notes text check (notes is null or length(trim(notes)) between 1 and 4000),
  revision_reason text check (
    revision_reason is null or length(trim(revision_reason)) between 1 and 1000
  ),
  status text not null default 'draft' check (
    status in (
      'draft', 'submitted', 'pending_approval', 'approved', 'rejected',
      'accepted', 'expired', 'cancelled', 'converted'
    )
  ),
  workflow_definition_id uuid,
  workflow_revision integer,
  version bigint not null default 1 check (version > 0),
  submitted_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  accepted_at timestamptz,
  expired_at timestamptz,
  cancelled_at timestamptz,
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
  unique (tenant_id, legal_entity_id, branch_id, document_number),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, customer_id)
    references crm.parties(tenant_id, id),
  foreign key (tenant_id, contact_id)
    references crm.contacts(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, opportunity_id)
    references crm.opportunities(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, exchange_rate_id)
    references finance.exchange_rates(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, workflow_definition_id, workflow_revision)
    references workflow.workflow_definitions(tenant_id, id, revision),
  check (valid_until >= quotation_date),
  check ((workflow_definition_id is null) = (workflow_revision is null)),
  check (workflow_revision is null or workflow_revision > 0),
  check (
    header_discount_amount = 0 or header_discount_percent is null
  ),
  check (line_discount_total + header_discount_total = discount_total),
  check (header_discount_total <= subtotal - line_discount_total),
  check (
    (currency_code = base_currency_code and exchange_rate = 1)
    or currency_code <> base_currency_code
  )
);

create table sales.quotation_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  quotation_id uuid not null,
  revision_number integer not null check (revision_number > 0),
  line_number integer not null check (line_number > 0),
  product_id uuid,
  description text not null check (length(trim(description)) between 1 and 1000),
  unit_id uuid not null,
  quantity numeric(20, 6) not null check (quantity > 0),
  base_quantity numeric(20, 6) not null check (base_quantity > 0),
  conversion_numerator bigint not null check (conversion_numerator > 0),
  conversion_denominator bigint not null check (conversion_denominator > 0),
  unit_price numeric(20, 6) not null check (unit_price >= 0),
  gross_amount numeric(20, 6) not null check (gross_amount >= 0),
  line_discount_amount numeric(20, 6) not null default 0
    check (line_discount_amount >= 0),
  discount_percent numeric(12, 6) check (discount_percent between 0 and 100),
  header_discount_amount numeric(20, 6) not null default 0
    check (header_discount_amount >= 0),
  net_amount numeric(20, 6) not null check (net_amount >= 0),
  tax_definition_id uuid,
  tax_code text,
  tax_name text,
  tax_kind text,
  tax_rate numeric(12, 6) not null default 0 check (tax_rate between 0 and 100),
  tax_inclusive boolean not null default false,
  tax_definition_version bigint,
  taxable_amount numeric(20, 6) not null check (taxable_amount >= 0),
  tax_amount numeric(20, 6) not null default 0 check (tax_amount >= 0),
  line_total numeric(20, 6) not null check (line_total >= 0),
  currency_code text not null references core.currencies(code),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, quotation_id, revision_number, line_number),
  unique (tenant_id, quotation_id, revision_number, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, quotation_id)
    references sales.quotations(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, product_id)
    references inventory.products(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, unit_id)
    references inventory.units(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, tax_definition_id)
    references finance.tax_definitions(tenant_id, legal_entity_id, id),
  check (base_quantity * conversion_denominator = quantity * conversion_numerator),
  check (line_discount_amount <= gross_amount),
  check (header_discount_amount <= gross_amount - line_discount_amount),
  check (
    (tax_definition_id is null and tax_code is null and tax_name is null
      and tax_kind is null and tax_rate = 0 and tax_definition_version is null)
    or
    (tax_definition_id is not null and tax_code is not null and tax_name is not null
      and tax_kind is not null and tax_definition_version is not null)
  )
);

create table sales.quotation_revisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  quotation_id uuid not null,
  revision_number integer not null check (revision_number > 0),
  document_number text not null,
  status text not null check (status in ('submitted', 'rejected', 'accepted', 'expired')),
  reason text check (reason is null or length(trim(reason)) between 1 and 1000),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, quotation_id, revision_number),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, quotation_id)
    references sales.quotations(tenant_id, legal_entity_id, id)
);

create index quotations_scope_status_idx on sales.quotations (
  tenant_id, legal_entity_id, branch_id, status, quotation_date desc, id
);
create index quotations_customer_idx on sales.quotations (
  tenant_id, customer_id, status, valid_until, id
);
create index quotations_contact_fk_idx on sales.quotations (tenant_id, contact_id);
create index quotations_opportunity_fk_idx
  on sales.quotations (tenant_id, legal_entity_id, opportunity_id);
create index quotations_exchange_rate_fk_idx
  on sales.quotations (tenant_id, legal_entity_id, exchange_rate_id);
create index quotations_salesperson_fk_idx on sales.quotations (salesperson_id);
create index quotations_workflow_fk_idx
  on sales.quotations (tenant_id, workflow_definition_id, workflow_revision);
create index quotations_created_by_fk_idx on sales.quotations (created_by);
create index quotations_updated_by_fk_idx on sales.quotations (updated_by);
create index quotation_lines_document_idx on sales.quotation_lines (
  tenant_id, quotation_id, revision_number, line_number, id
);
create index quotation_lines_branch_fk_idx
  on sales.quotation_lines (tenant_id, branch_id);
create index quotation_lines_product_fk_idx
  on sales.quotation_lines (tenant_id, legal_entity_id, product_id);
create index quotation_lines_unit_fk_idx on sales.quotation_lines (tenant_id, unit_id);
create index quotation_lines_tax_fk_idx
  on sales.quotation_lines (tenant_id, legal_entity_id, tax_definition_id);
create index quotation_lines_created_by_fk_idx on sales.quotation_lines (created_by);
create index quotation_revisions_document_idx on sales.quotation_revisions (
  tenant_id, quotation_id, revision_number desc, id
);
create index quotation_revisions_branch_fk_idx
  on sales.quotation_revisions (tenant_id, branch_id);
create index quotation_revisions_created_by_fk_idx
  on sales.quotation_revisions (created_by);

create trigger quotations_touch before update on sales.quotations
for each row execute function core.touch_mutable_record();

create function sales.reject_immutable_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'COMMERCIAL_HISTORY_IMMUTABLE';
end;
$$;

create trigger quotation_revisions_immutable
before update or delete on sales.quotation_revisions
for each row execute function sales.reject_immutable_history();

create function sales.guard_quotation_line_history()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_quotation_id uuid := coalesce(new.quotation_id, old.quotation_id);
  v_revision integer := coalesce(new.revision_number, old.revision_number);
begin
  if not exists (
    select 1
    from sales.quotations as q
    where q.id = v_quotation_id
      and q.current_revision = v_revision
      and q.status = 'draft'
  ) then
    raise exception using errcode = '55000', message = 'QUOTATION_REVISION_IMMUTABLE';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger quotation_lines_history_guard
before insert or update or delete on sales.quotation_lines
for each row execute function sales.guard_quotation_line_history();

alter table sales.quotations enable row level security;
alter table sales.quotations force row level security;
alter table sales.quotation_lines enable row level security;
alter table sales.quotation_lines force row level security;
alter table sales.quotation_revisions enable row level security;
alter table sales.quotation_revisions force row level security;

create policy quotations_permitted_read on sales.quotations
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    core.has_permission(
      tenant_id, 'sales.quotations.view', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'sales.quotations.manage', legal_entity_id, branch_id
    )
  )
);
create policy quotation_lines_permitted_read on sales.quotation_lines
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    core.has_permission(
      tenant_id, 'sales.quotations.view', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'sales.quotations.manage', legal_entity_id, branch_id
    )
  )
);
create policy quotation_revisions_permitted_read on sales.quotation_revisions
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    core.has_permission(
      tenant_id, 'sales.quotations.view', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'sales.quotations.manage', legal_entity_id, branch_id
    )
  )
);

create view api.sales_quotations
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, document_number,
  current_revision, customer_id, contact_id, opportunity_id,
  quotation_date, valid_until, currency_code, base_currency_code,
  exchange_rate_id, exchange_rate::text as exchange_rate, rate_date,
  payment_terms_days, delivery_terms, salesperson_id,
  header_discount_amount::text as header_discount_amount,
  header_discount_percent::text as header_discount_percent,
  subtotal::text as subtotal,
  line_discount_total::text as line_discount_total,
  header_discount_total::text as header_discount_total,
  discount_total::text as discount_total, tax_total::text as tax_total,
  grand_total::text as grand_total, base_total::text as base_total,
  notes, revision_reason, status, workflow_definition_id, workflow_revision,
  version, submitted_at, approved_at, rejected_at, accepted_at, expired_at,
  cancelled_at, request_id, command_id, correlation_id, source_context,
  client_timestamp, created_by, updated_by, created_at, updated_at
from sales.quotations;

create view api.sales_quotation_lines
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, quotation_id,
  revision_number, line_number, product_id, description, unit_id,
  quantity::text as quantity, base_quantity::text as base_quantity,
  conversion_numerator::text as conversion_numerator,
  conversion_denominator::text as conversion_denominator,
  unit_price::text as unit_price, gross_amount::text as gross_amount,
  line_discount_amount::text as line_discount_amount,
  discount_percent::text as discount_percent,
  header_discount_amount::text as header_discount_amount,
  net_amount::text as net_amount, tax_definition_id, tax_code, tax_name,
  tax_kind, tax_rate::text as tax_rate, tax_inclusive,
  tax_definition_version, taxable_amount::text as taxable_amount,
  tax_amount::text as tax_amount, line_total::text as line_total,
  currency_code, request_id, command_id, correlation_id, source_context,
  created_by, created_at
from sales.quotation_lines;

create view api.sales_quotation_revisions
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, quotation_id,
  revision_number, document_number, status, reason, snapshot,
  request_id, command_id, correlation_id, source_context,
  created_by, created_at
from sales.quotation_revisions;

revoke all on function sales.reject_immutable_history()
  from public, anon, authenticated;
revoke all on function sales.guard_quotation_line_history()
  from public, anon, authenticated;
revoke all on sales.quotations, sales.quotation_lines,
  sales.quotation_revisions from public, anon, authenticated;
grant select on sales.quotations, sales.quotation_lines,
  sales.quotation_revisions to authenticated;
revoke all on api.sales_quotations, api.sales_quotation_lines,
  api.sales_quotation_revisions from public, anon, authenticated;
grant select on api.sales_quotations, api.sales_quotation_lines,
  api.sales_quotation_revisions to authenticated;

comment on table sales.quotation_revisions is
  'Immutable customer-facing quotation snapshots, one per submitted revision.';
comment on column sales.quotation_lines.tax_rate is
  'Tax rate snapshot retained with the line revision; never re-derived for history.';

notify pgrst, 'reload schema';
