-- Jentra OS Wave 2 shared business foundation — schema, constraints, RLS,
-- reference data, permissions, and private attachment storage.
-- Additive only: Wave 1 contracts and intentional legacy deletions stay intact.

create extension if not exists btree_gist with schema extensions;

alter table core.command_receipts
  add column if not exists request_hash text;

-- ---------------------------------------------------------------------------
-- Global reference data
-- ---------------------------------------------------------------------------

create table core.currencies (
  code text primary key check (code ~ '^[A-Z]{3}$'),
  name text not null check (length(trim(name)) between 2 and 80),
  numeric_code text not null unique check (numeric_code ~ '^[0-9]{3}$'),
  minor_units smallint not null check (minor_units between 0 and 6),
  symbol text,
  active boolean not null default true,
  display_order integer not null default 1000 check (display_order >= 0),
  created_at timestamptz not null default now()
);

insert into core.currencies (
  code, name, numeric_code, minor_units, symbol, display_order
) values
  ('LKR', 'Sri Lankan Rupee', '144', 2, 'Rs', 10),
  ('USD', 'US Dollar', '840', 2, '$', 20),
  ('EUR', 'Euro', '978', 2, '€', 30),
  ('GBP', 'Pound Sterling', '826', 2, '£', 40),
  ('INR', 'Indian Rupee', '356', 2, '₹', 50),
  ('AUD', 'Australian Dollar', '036', 2, 'A$', 60),
  ('SGD', 'Singapore Dollar', '702', 2, 'S$', 70),
  ('AED', 'UAE Dirham', '784', 2, 'د.إ', 80),
  ('CNY', 'Chinese Yuan', '156', 2, '¥', 90),
  ('JPY', 'Japanese Yen', '392', 0, '¥', 100)
on conflict (code) do update set
  name = excluded.name,
  numeric_code = excluded.numeric_code,
  minor_units = excluded.minor_units,
  symbol = excluded.symbol,
  display_order = excluded.display_order;

-- ---------------------------------------------------------------------------
-- Finance setup
-- ---------------------------------------------------------------------------

create table finance.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  source_currency_code text not null references core.currencies(code),
  target_currency_code text not null references core.currencies(code),
  rate numeric(20, 10) not null check (rate > 0),
  effective_date date not null,
  rate_type text not null default 'spot'
    check (rate_type in ('spot', 'average', 'closing', 'custom')),
  source text not null default 'manual'
    check (length(trim(source)) between 2 and 80),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, id),
  unique (
    tenant_id, legal_entity_id, source_currency_code,
    target_currency_code, effective_date, rate_type
  ),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  check (source_currency_code <> target_currency_code)
);

create table finance.tax_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,31}$'),
  name text not null check (length(trim(name)) between 2 and 120),
  rate numeric(12, 6) not null check (rate between 0 and 100),
  kind text not null
    check (kind in ('input', 'output', 'withholding', 'zero', 'exempt')),
  inclusive boolean not null default false,
  recoverable boolean not null default false,
  valid_from date not null,
  valid_to date,
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, id),
  unique (tenant_id, legal_entity_id, code),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  check (valid_to is null or valid_to >= valid_from)
);

create table finance.accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_.-]{0,31}$'),
  name text not null check (length(trim(name)) between 2 and 140),
  account_type text not null
    check (account_type in ('asset', 'liability', 'equity', 'revenue', 'expense')),
  normal_balance text not null check (normal_balance in ('debit', 'credit')),
  parent_id uuid,
  is_posting boolean not null default true,
  currency_code text references core.currencies(code),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, id),
  unique (tenant_id, legal_entity_id, code),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, parent_id)
    references finance.accounts(tenant_id, legal_entity_id, id),
  check (parent_id is null or parent_id <> id)
);

create table finance.fiscal_periods (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  name text not null check (length(trim(name)) between 2 and 100),
  start_date date not null,
  end_date date not null,
  state text not null default 'open'
    check (state in ('open', 'soft_locked', 'hard_locked')),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, id),
  unique (tenant_id, legal_entity_id, name),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  check (end_date >= start_date),
  exclude using gist (
    tenant_id with =,
    legal_entity_id with =,
    daterange(start_date, end_date, '[]') with &&
  ) where (status = 'active')
);

-- ---------------------------------------------------------------------------
-- Party and catalogue setup
-- ---------------------------------------------------------------------------

create table crm.parties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,31}$'),
  legal_name text not null check (length(trim(legal_name)) between 2 and 180),
  display_name text not null check (length(trim(display_name)) between 2 and 160),
  kind text not null check (kind in ('customer', 'supplier', 'both')),
  tax_identifier text,
  email text check (email is null or position('@' in email) > 1),
  phone text,
  address_line_1 text,
  address_line_2 text,
  city text,
  country_code text not null default 'LK'
    check (country_code ~ '^[A-Z]{2}$'),
  credit_limit numeric(20, 6) not null default 0 check (credit_limit >= 0),
  credit_currency_code text not null default 'LKR'
    references core.currencies(code),
  payment_terms_days integer not null default 0
    check (payment_terms_days between 0 and 3650),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table crm.contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  party_id uuid not null,
  name text not null check (length(trim(name)) between 2 and 140),
  role text,
  email text check (email is null or position('@' in email) > 1),
  phone text,
  is_primary boolean not null default false,
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, party_id) references crm.parties(tenant_id, id)
);

create unique index contacts_one_active_primary_idx
  on crm.contacts (tenant_id, party_id)
  where is_primary and status = 'active';

create table inventory.units (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_.-]{0,23}$'),
  name text not null check (length(trim(name)) between 2 and 80),
  symbol text not null check (length(trim(symbol)) between 1 and 16),
  category text not null
    check (category in ('quantity', 'weight', 'length', 'area', 'volume', 'time', 'service')),
  precision smallint not null default 0 check (precision between 0 and 6),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table inventory.products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  sku text not null check (sku ~ '^[A-Z0-9][A-Z0-9_.-]{1,47}$'),
  name text not null check (length(trim(name)) between 2 and 180),
  description text,
  kind text not null check (kind in ('stocked', 'non_stocked', 'service')),
  base_unit_id uuid not null,
  tracking_mode text not null default 'none'
    check (tracking_mode in ('none', 'lot', 'serial')),
  can_sell boolean not null default true,
  can_purchase boolean not null default true,
  tax_definition_id uuid,
  revenue_account_id uuid,
  expense_account_id uuid,
  inventory_account_id uuid,
  cogs_account_id uuid,
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, id),
  unique (tenant_id, sku),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, base_unit_id)
    references inventory.units(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, tax_definition_id)
    references finance.tax_definitions(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, revenue_account_id)
    references finance.accounts(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, expense_account_id)
    references finance.accounts(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, inventory_account_id)
    references finance.accounts(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, cogs_account_id)
    references finance.accounts(tenant_id, legal_entity_id, id)
);

-- ---------------------------------------------------------------------------
-- Numbering, governance, files, jobs, and reports
-- ---------------------------------------------------------------------------

create table core.document_sequences (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid,
  branch_id uuid,
  document_type text not null check (document_type ~ '^[a-z][a-z0-9_.-]{2,79}$'),
  prefix text not null default '' check (length(prefix) <= 24),
  suffix text not null default '' check (length(suffix) <= 24),
  padding smallint not null default 6 check (padding between 1 and 12),
  reset_policy text not null default 'never'
    check (reset_policy in ('never', 'yearly', 'monthly')),
  next_value bigint not null default 1 check (next_value > 0),
  last_reset_key text,
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique nulls not distinct (tenant_id, legal_entity_id, branch_id, document_type),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  check (branch_id is null or legal_entity_id is not null)
);

create table workflow.workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid,
  document_type text not null check (document_type ~ '^[a-z][a-z0-9_.-]{2,79}$'),
  name text not null check (length(trim(name)) between 2 and 140),
  revision integer not null default 1 check (revision > 0),
  lifecycle jsonb not null check (jsonb_typeof(lifecycle) = 'object'),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique nulls not distinct (tenant_id, legal_entity_id, document_type, revision),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id)
);

create unique index workflow_definitions_one_active_idx
  on workflow.workflow_definitions (
    tenant_id, coalesce(legal_entity_id, '00000000-0000-0000-0000-000000000000'),
    document_type
  ) where status = 'active';

create table workflow.approval_matrix_steps (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  workflow_definition_id uuid not null,
  role_id uuid not null,
  step_order integer not null check (step_order between 1 and 100),
  minimum_amount numeric(20, 6),
  maximum_amount numeric(20, 6),
  currency_code text references core.currencies(code),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, workflow_definition_id, step_order),
  foreign key (tenant_id, workflow_definition_id)
    references workflow.workflow_definitions(tenant_id, id),
  foreign key (tenant_id, role_id) references core.roles(tenant_id, id),
  check (
    minimum_amount is null or maximum_amount is null
    or minimum_amount <= maximum_amount
  ),
  check (
    (minimum_amount is null and maximum_amount is null and currency_code is null)
    or currency_code is not null
  )
);

create table core.attachments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  aggregate_type text not null check (aggregate_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  aggregate_id uuid not null,
  file_name text not null check (length(trim(file_name)) between 1 and 255),
  mime_type text not null,
  byte_size bigint not null check (byte_size between 1 and 26214400),
  bucket_id text not null default 'jentra-attachments'
    check (bucket_id = 'jentra-attachments'),
  object_path text not null,
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[a-f0-9]{64}$'),
  upload_status text not null default 'staged'
    check (upload_status in ('staged', 'ready', 'rejected')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (bucket_id, object_path),
  check (mime_type in (
    'application/pdf', 'image/png', 'image/jpeg', 'text/csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ))
);

create table workflow.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  recipient_id uuid not null references auth.users(id),
  notification_type text not null check (notification_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  title text not null check (length(trim(title)) between 2 and 160),
  body text not null check (length(trim(body)) between 1 and 4000),
  aggregate_type text,
  aggregate_id uuid,
  read_at timestamptz,
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table core.import_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid,
  actor_id uuid not null references auth.users(id),
  resource text not null,
  file_format text not null check (file_format in ('csv', 'xlsx')),
  file_name text not null check (length(trim(file_name)) between 1 and 255),
  file_size bigint not null check (file_size between 1 and 5242880),
  status text not null check (status in ('completed', 'failed')),
  total_rows integer not null check (total_rows between 0 and 500),
  accepted_rows integer not null check (accepted_rows between 0 and 500),
  rejected_rows integer not null check (rejected_rows between 0 and 500),
  errors jsonb not null default '[]'::jsonb check (jsonb_typeof(errors) = 'array'),
  request_id uuid not null,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  check (accepted_rows + rejected_rows = total_rows)
);

create table core.export_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  actor_id uuid not null references auth.users(id),
  resource text not null,
  file_format text not null check (file_format in ('csv', 'xlsx')),
  filters jsonb not null default '{}'::jsonb check (jsonb_typeof(filters) = 'object'),
  columns_json jsonb not null check (jsonb_typeof(columns_json) = 'array'),
  status text not null default 'completed' check (status = 'completed'),
  row_count integer not null check (row_count between 0 and 10000),
  file_name text not null check (length(trim(file_name)) between 1 and 255),
  file_size bigint not null check (file_size >= 0),
  request_id uuid not null,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table core.report_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,47}$'),
  title text not null check (length(trim(title)) between 2 and 160),
  source_view text not null,
  columns_json jsonb not null check (jsonb_typeof(columns_json) = 'array'),
  filters jsonb not null default '{}'::jsonb check (jsonb_typeof(filters) = 'object'),
  sort_json jsonb not null default '[]'::jsonb check (jsonb_typeof(sort_json) = 'array'),
  row_limit integer not null default 100 check (row_limit between 1 and 1000),
  is_shared boolean not null default false,
  owner_id uuid not null references auth.users(id),
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

-- ---------------------------------------------------------------------------
-- Tenant-leading indexes and optimistic-version triggers
-- ---------------------------------------------------------------------------

create index exchange_rates_tenant_entity_date_idx
  on finance.exchange_rates (tenant_id, legal_entity_id, effective_date desc, id);
create index tax_definitions_tenant_entity_status_idx
  on finance.tax_definitions (tenant_id, legal_entity_id, status, code, id);
create index accounts_tenant_entity_status_idx
  on finance.accounts (tenant_id, legal_entity_id, status, code, id);
create index accounts_tenant_entity_parent_idx
  on finance.accounts (tenant_id, legal_entity_id, parent_id, id);
create index fiscal_periods_tenant_entity_start_idx
  on finance.fiscal_periods (tenant_id, legal_entity_id, start_date desc, id);
create index parties_tenant_status_name_idx
  on crm.parties (tenant_id, status, display_name, id);
create index contacts_tenant_party_status_idx
  on crm.contacts (tenant_id, party_id, status, id);
create index units_tenant_status_code_idx
  on inventory.units (tenant_id, status, code, id);
create index products_tenant_entity_status_idx
  on inventory.products (tenant_id, legal_entity_id, status, sku, id);
create index document_sequences_tenant_scope_idx
  on core.document_sequences (tenant_id, legal_entity_id, branch_id, document_type, id);
create index workflow_definitions_tenant_scope_idx
  on workflow.workflow_definitions (tenant_id, legal_entity_id, document_type, status, id);
create index approval_steps_tenant_workflow_order_idx
  on workflow.approval_matrix_steps (tenant_id, workflow_definition_id, step_order, id);
create index attachments_tenant_aggregate_idx
  on core.attachments (tenant_id, aggregate_type, aggregate_id, upload_status, id);
create index notifications_recipient_unread_idx
  on workflow.notifications (recipient_id, read_at, created_at desc, id);
create index notifications_tenant_recipient_idx
  on workflow.notifications (tenant_id, recipient_id, created_at desc, id);
create index import_jobs_tenant_created_idx
  on core.import_jobs (tenant_id, created_at desc, id);
create index export_jobs_tenant_created_idx
  on core.export_jobs (tenant_id, created_at desc, id);
create index report_definitions_tenant_status_idx
  on core.report_definitions (tenant_id, status, code, id);

create trigger exchange_rates_touch before update on finance.exchange_rates
  for each row execute function core.touch_mutable_record();
create trigger tax_definitions_touch before update on finance.tax_definitions
  for each row execute function core.touch_mutable_record();
create trigger accounts_touch before update on finance.accounts
  for each row execute function core.touch_mutable_record();
create trigger fiscal_periods_touch before update on finance.fiscal_periods
  for each row execute function core.touch_mutable_record();
create trigger parties_touch before update on crm.parties
  for each row execute function core.touch_mutable_record();
create trigger contacts_touch before update on crm.contacts
  for each row execute function core.touch_mutable_record();
create trigger units_touch before update on inventory.units
  for each row execute function core.touch_mutable_record();
create trigger products_touch before update on inventory.products
  for each row execute function core.touch_mutable_record();
create trigger document_sequences_touch before update on core.document_sequences
  for each row execute function core.touch_mutable_record();
create trigger workflow_definitions_touch before update on workflow.workflow_definitions
  for each row execute function core.touch_mutable_record();
create trigger approval_matrix_steps_touch before update on workflow.approval_matrix_steps
  for each row execute function core.touch_mutable_record();
create trigger attachments_touch before update on core.attachments
  for each row execute function core.touch_mutable_record();
create trigger notifications_touch before update on workflow.notifications
  for each row execute function core.touch_mutable_record();
create trigger import_jobs_touch before update on core.import_jobs
  for each row execute function core.touch_mutable_record();
create trigger export_jobs_touch before update on core.export_jobs
  for each row execute function core.touch_mutable_record();
create trigger report_definitions_touch before update on core.report_definitions
  for each row execute function core.touch_mutable_record();

-- ---------------------------------------------------------------------------
-- Defense-in-depth RLS. Client roles receive select-only base-table grants in
-- the API migration; all mutations flow through named commands.
-- ---------------------------------------------------------------------------

alter table core.currencies enable row level security;
alter table finance.exchange_rates enable row level security;
alter table finance.tax_definitions enable row level security;
alter table finance.accounts enable row level security;
alter table finance.fiscal_periods enable row level security;
alter table crm.parties enable row level security;
alter table crm.contacts enable row level security;
alter table inventory.units enable row level security;
alter table inventory.products enable row level security;
alter table core.document_sequences enable row level security;
alter table workflow.workflow_definitions enable row level security;
alter table workflow.approval_matrix_steps enable row level security;
alter table core.attachments enable row level security;
alter table workflow.notifications enable row level security;
alter table core.import_jobs enable row level security;
alter table core.export_jobs enable row level security;
alter table core.report_definitions enable row level security;

create policy currencies_authenticated_read on core.currencies
  for select to authenticated using (true);
create policy exchange_rates_permitted_read on finance.exchange_rates
  for select to authenticated using (
    core.has_permission(tenant_id, 'finance.setup.view', legal_entity_id)
    or core.has_permission(tenant_id, 'finance.setup.manage', legal_entity_id)
  );
create policy tax_definitions_permitted_read on finance.tax_definitions
  for select to authenticated using (
    core.has_permission(tenant_id, 'finance.setup.view', legal_entity_id)
    or core.has_permission(tenant_id, 'finance.setup.manage', legal_entity_id)
  );
create policy accounts_permitted_read on finance.accounts
  for select to authenticated using (
    core.has_permission(tenant_id, 'finance.setup.view', legal_entity_id)
    or core.has_permission(tenant_id, 'finance.setup.manage', legal_entity_id)
  );
create policy fiscal_periods_permitted_read on finance.fiscal_periods
  for select to authenticated using (
    core.has_permission(tenant_id, 'finance.setup.view', legal_entity_id)
    or core.has_permission(tenant_id, 'finance.setup.manage', legal_entity_id)
  );
create policy parties_permitted_read on crm.parties
  for select to authenticated using (
    core.has_permission(tenant_id, 'crm.parties.view')
    or core.has_permission(tenant_id, 'crm.parties.manage')
  );
create policy contacts_permitted_read on crm.contacts
  for select to authenticated using (
    core.has_permission(tenant_id, 'crm.parties.view')
    or core.has_permission(tenant_id, 'crm.parties.manage')
  );
create policy units_permitted_read on inventory.units
  for select to authenticated using (
    core.has_permission(tenant_id, 'inventory.catalog.view')
    or core.has_permission(tenant_id, 'inventory.catalog.manage')
  );
create policy products_permitted_read on inventory.products
  for select to authenticated using (
    core.has_permission(tenant_id, 'inventory.catalog.view', legal_entity_id)
    or core.has_permission(tenant_id, 'inventory.catalog.manage', legal_entity_id)
  );
create policy document_sequences_permitted_read on core.document_sequences
  for select to authenticated using (
    core.has_permission(tenant_id, 'core.setup.view', legal_entity_id, branch_id)
    or core.has_permission(tenant_id, 'core.setup.manage', legal_entity_id, branch_id)
  );
create policy workflow_definitions_permitted_read on workflow.workflow_definitions
  for select to authenticated using (
    core.has_permission(tenant_id, 'workflow.configure', legal_entity_id)
  );
create policy approval_steps_permitted_read on workflow.approval_matrix_steps
  for select to authenticated using (
    core.has_permission(tenant_id, 'workflow.configure')
  );
create policy attachments_permitted_read on core.attachments
  for select to authenticated using (
    core.has_permission(tenant_id, 'core.files.view')
    or core.has_permission(tenant_id, 'core.files.manage')
  );
create policy notifications_recipient_read on workflow.notifications
  for select to authenticated using (
    recipient_id = (select auth.uid()) and core.is_tenant_member(tenant_id)
  );
create policy import_jobs_actor_read on core.import_jobs
  for select to authenticated using (
    actor_id = (select auth.uid()) and core.is_tenant_member(tenant_id)
  );
create policy export_jobs_actor_read on core.export_jobs
  for select to authenticated using (
    actor_id = (select auth.uid()) and core.is_tenant_member(tenant_id)
  );
create policy report_definitions_permitted_read on core.report_definitions
  for select to authenticated using (
    (is_shared or owner_id = (select auth.uid()))
    and (
      core.has_permission(tenant_id, 'analytics.reports.view')
      or core.has_permission(tenant_id, 'analytics.reports.manage')
    )
  );

-- ---------------------------------------------------------------------------
-- Permission vocabulary and owner-role backfill
-- ---------------------------------------------------------------------------

insert into core.permissions (code, module, description, privileged) values
  ('core.setup.view', 'core', 'View shared business setup and numbering.', false),
  ('core.setup.manage', 'core', 'Manage shared business setup and numbering.', true),
  ('finance.setup.view', 'finance', 'View finance setup reference data.', true),
  ('finance.setup.manage', 'finance', 'Manage finance setup reference data.', true),
  ('crm.parties.view', 'crm', 'View parties and contacts.', false),
  ('crm.parties.manage', 'crm', 'Manage parties and contacts.', true),
  ('inventory.catalog.view', 'inventory', 'View units and products.', false),
  ('inventory.catalog.manage', 'inventory', 'Manage units and products.', true),
  ('workflow.configure', 'workflow', 'Configure workflows and approval matrices.', true),
  ('core.files.view', 'core', 'Read permitted private attachments.', false),
  ('core.files.manage', 'core', 'Register and complete private attachments.', true),
  ('analytics.reports.view', 'analytics', 'View saved report definitions.', false),
  ('analytics.reports.manage', 'analytics', 'Manage saved report definitions.', true)
on conflict (code) do update set
  module = excluded.module,
  description = excluded.description,
  privileged = excluded.privileged;

insert into core.role_permissions (tenant_id, role_id, permission_code)
select r.tenant_id, r.id, p.code
from core.roles as r
cross join core.permissions as p
where r.code = 'tenant_owner'
  and p.code in (
    'core.setup.view', 'core.setup.manage',
    'finance.setup.view', 'finance.setup.manage',
    'crm.parties.view', 'crm.parties.manage',
    'inventory.catalog.view', 'inventory.catalog.manage',
    'workflow.configure', 'core.files.view', 'core.files.manage',
    'analytics.reports.view', 'analytics.reports.manage'
  )
on conflict (role_id, permission_code) do nothing;

-- ---------------------------------------------------------------------------
-- Private development bucket and path-scoped Storage policies
-- ---------------------------------------------------------------------------

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'jentra-attachments',
  'jentra-attachments',
  false,
  26214400,
  array[
    'application/pdf',
    'image/png',
    'image/jpeg',
    'text/csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create function core.storage_object_tenant(p_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return split_part(p_name, '/', 1)::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

create policy jentra_attachments_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'jentra-attachments'
    and core.storage_object_tenant(name) is not null
    and (
      core.has_permission(core.storage_object_tenant(name), 'core.files.view')
      or core.has_permission(core.storage_object_tenant(name), 'core.files.manage')
    )
  );
create policy jentra_attachments_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'jentra-attachments'
    and core.storage_object_tenant(name) is not null
    and core.has_permission(core.storage_object_tenant(name), 'core.files.manage')
  );
create policy jentra_attachments_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'jentra-attachments'
    and core.storage_object_tenant(name) is not null
    and core.has_permission(core.storage_object_tenant(name), 'core.files.manage')
  )
  with check (
    bucket_id = 'jentra-attachments'
    and core.storage_object_tenant(name) is not null
    and core.has_permission(core.storage_object_tenant(name), 'core.files.manage')
  );

revoke all on core.currencies, finance.exchange_rates, finance.tax_definitions,
  finance.accounts, finance.fiscal_periods, crm.parties, crm.contacts,
  inventory.units, inventory.products, core.document_sequences,
  workflow.workflow_definitions, workflow.approval_matrix_steps,
  core.attachments, workflow.notifications, core.import_jobs,
  core.export_jobs, core.report_definitions
  from public, anon, authenticated;

revoke execute on function core.storage_object_tenant(text)
  from public, anon, authenticated;
