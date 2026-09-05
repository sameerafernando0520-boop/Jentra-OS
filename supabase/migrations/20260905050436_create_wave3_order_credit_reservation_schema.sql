-- Wave 3 lead-to-cash foundation, part 3: traced sales orders, private credit
-- projections and decisions, and non-posting stock reservation state.

insert into core.permissions (code, module, description, privileged) values
  (
    'sales.credit.override', 'sales',
    'Override a governed customer credit hold with an attributable reason.', true
  )
on conflict (code) do update set
  module = excluded.module,
  description = excluded.description,
  privileged = excluded.privileged;

insert into core.role_permissions (tenant_id, role_id, permission_code)
select r.tenant_id, r.id, 'sales.credit.override'
from core.roles as r
where r.code = 'tenant_owner'
on conflict (role_id, permission_code) do nothing;

create table sales.sales_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  document_number text,
  source_quotation_id uuid,
  source_quotation_revision integer,
  source_snapshot jsonb check (
    source_snapshot is null or jsonb_typeof(source_snapshot) = 'object'
  ),
  customer_id uuid not null,
  contact_id uuid,
  order_date date not null,
  promised_date date not null,
  ship_to jsonb not null default '{}'::jsonb
    check (jsonb_typeof(ship_to) = 'object'),
  warehouse_id uuid not null,
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
  status text not null default 'draft' check (
    status in (
      'draft', 'credit_hold', 'confirmed', 'partially_reserved',
      'reserved', 'fulfilled', 'cancelled'
    )
  ),
  version bigint not null default 1 check (version > 0),
  confirmed_at timestamptz,
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
  foreign key (tenant_id, legal_entity_id, source_quotation_id)
    references sales.quotations(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, customer_id)
    references crm.parties(tenant_id, id),
  foreign key (tenant_id, contact_id)
    references crm.contacts(tenant_id, id),
  foreign key (tenant_id, warehouse_id)
    references core.warehouses(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, exchange_rate_id)
    references finance.exchange_rates(tenant_id, legal_entity_id, id),
  check ((source_quotation_id is null) = (source_quotation_revision is null)),
  check (source_quotation_revision is null or source_quotation_revision > 0),
  check ((source_quotation_id is null) = (source_snapshot is null)),
  check (promised_date >= order_date),
  check (header_discount_amount = 0 or header_discount_percent is null),
  check (line_discount_total + header_discount_total = discount_total),
  check (header_discount_total <= subtotal - line_discount_total),
  check (
    (currency_code = base_currency_code and exchange_rate = 1)
    or currency_code <> base_currency_code
  )
);

create unique index sales_orders_source_quotation_uidx
  on sales.sales_orders (tenant_id, source_quotation_id, source_quotation_revision)
  where source_quotation_id is not null;

create table sales.sales_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  sales_order_id uuid not null,
  line_number integer not null check (line_number > 0),
  source_quotation_id uuid,
  source_quotation_line_id uuid,
  source_quotation_revision integer,
  product_id uuid not null,
  product_kind text not null check (product_kind in ('stocked', 'non_stocked', 'service')),
  description text not null check (length(trim(description)) between 1 and 1000),
  unit_id uuid not null,
  conversion_numerator bigint not null check (conversion_numerator > 0),
  conversion_denominator bigint not null check (conversion_denominator > 0),
  ordered_quantity numeric(20, 6) not null check (ordered_quantity > 0),
  base_ordered_quantity numeric(20, 6) not null check (base_ordered_quantity > 0),
  cancelled_quantity numeric(20, 6) not null default 0 check (cancelled_quantity >= 0),
  allocated_quantity numeric(20, 6) not null default 0 check (allocated_quantity >= 0),
  delivered_quantity numeric(20, 6) not null default 0 check (delivered_quantity >= 0),
  invoiced_quantity numeric(20, 6) not null default 0 check (invoiced_quantity >= 0),
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
  version bigint not null default 1 check (version > 0),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, sales_order_id, line_number),
  unique (tenant_id, sales_order_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, sales_order_id)
    references sales.sales_orders(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, source_quotation_id, source_quotation_revision, source_quotation_line_id)
    references sales.quotation_lines(tenant_id, quotation_id, revision_number, id),
  foreign key (tenant_id, legal_entity_id, product_id)
    references inventory.products(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, unit_id)
    references inventory.units(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, tax_definition_id)
    references finance.tax_definitions(tenant_id, legal_entity_id, id),
  check (
    (source_quotation_id is null and source_quotation_line_id is null
      and source_quotation_revision is null)
    or (source_quotation_id is not null and source_quotation_line_id is not null
      and source_quotation_revision is not null)
  ),
  check (base_ordered_quantity * conversion_denominator
    = ordered_quantity * conversion_numerator),
  check (cancelled_quantity <= base_ordered_quantity),
  check (allocated_quantity <= base_ordered_quantity - cancelled_quantity),
  check (delivered_quantity <= base_ordered_quantity - cancelled_quantity),
  check (invoiced_quantity <= base_ordered_quantity - cancelled_quantity),
  check (line_discount_amount <= gross_amount),
  check (header_discount_amount <= gross_amount - line_discount_amount)
);

create table sales.customer_credit_exposures (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  customer_id uuid not null,
  currency_code text not null references core.currencies(code),
  due_exposure numeric(20, 6) not null default 0 check (due_exposure >= 0),
  overdue_exposure numeric(20, 6) not null default 0 check (overdue_exposure >= 0),
  as_of_at timestamptz not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, legal_entity_id, branch_id, customer_id, currency_code),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, customer_id)
    references crm.parties(tenant_id, id),
  check (overdue_exposure <= due_exposure)
);

create table sales.credit_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  sales_order_id uuid not null,
  customer_id uuid not null,
  currency_code text not null references core.currencies(code),
  credit_limit numeric(20, 6) not null check (credit_limit >= 0),
  due_exposure numeric(20, 6) not null check (due_exposure >= 0),
  overdue_exposure numeric(20, 6) not null check (overdue_exposure >= 0),
  existing_order_exposure numeric(20, 6) not null
    check (existing_order_exposure >= 0),
  current_order_exposure numeric(20, 6) not null
    check (current_order_exposure >= 0),
  total_exposure numeric(20, 6) not null check (total_exposure >= 0),
  decision text not null check (decision in ('approved', 'blocked', 'overridden')),
  override_applied boolean not null default false,
  override_reason text check (
    override_reason is null or length(trim(override_reason)) between 1 and 1000
  ),
  override_by uuid references auth.users(id),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  decided_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, sales_order_id)
    references sales.sales_orders(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, customer_id)
    references crm.parties(tenant_id, id),
  check (overdue_exposure <= due_exposure),
  check (total_exposure = due_exposure + existing_order_exposure + current_order_exposure),
  check (
    (decision = 'overridden' and override_applied
      and override_reason is not null and override_by is not null)
    or (decision <> 'overridden' and not override_applied
      and override_reason is null and override_by is null)
  )
);

create table inventory.stock_balances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  warehouse_id uuid not null,
  product_id uuid not null,
  on_hand_quantity numeric(20, 6) not null default 0 check (on_hand_quantity >= 0),
  allocated_quantity numeric(20, 6) not null default 0 check (allocated_quantity >= 0),
  available_quantity numeric(20, 6) generated always as (
    on_hand_quantity - allocated_quantity
  ) stored,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, legal_entity_id, branch_id, warehouse_id, product_id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, warehouse_id)
    references core.warehouses(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, product_id)
    references inventory.products(tenant_id, legal_entity_id, id),
  check (allocated_quantity <= on_hand_quantity)
);

create table inventory.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  warehouse_id uuid not null,
  product_id uuid not null,
  sales_order_id uuid not null,
  sales_order_line_id uuid not null,
  base_quantity numeric(20, 6) not null check (base_quantity > 0),
  status text not null default 'active'
    check (status in ('active', 'released', 'fulfilled', 'expired')),
  expires_at timestamptz not null,
  released_at timestamptz,
  release_reason text check (
    release_reason is null or length(trim(release_reason)) between 1 and 1000
  ),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context) = 'object'),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, warehouse_id)
    references core.warehouses(tenant_id, id),
  foreign key (tenant_id, legal_entity_id, product_id)
    references inventory.products(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id, sales_order_id)
    references sales.sales_orders(tenant_id, legal_entity_id, id),
  foreign key (tenant_id, sales_order_id, sales_order_line_id)
    references sales.sales_order_lines(tenant_id, sales_order_id, id),
  check ((status = 'active' and released_at is null)
    or (status <> 'active' and released_at is not null))
);

create unique index stock_reservations_active_line_uidx
  on inventory.stock_reservations (
    tenant_id, warehouse_id, sales_order_line_id
  ) where status = 'active';

create index sales_orders_scope_status_idx on sales.sales_orders (
  tenant_id, legal_entity_id, branch_id, status, order_date desc, id
);
create index sales_orders_customer_exposure_idx on sales.sales_orders (
  tenant_id, legal_entity_id, branch_id, customer_id, currency_code, status, id
);
create index sales_orders_branch_fk_idx on sales.sales_orders (tenant_id, branch_id);
create index sales_orders_contact_fk_idx on sales.sales_orders (tenant_id, contact_id);
create index sales_orders_warehouse_fk_idx on sales.sales_orders (tenant_id, warehouse_id);
create index sales_orders_exchange_rate_fk_idx
  on sales.sales_orders (tenant_id, legal_entity_id, exchange_rate_id);
create index sales_orders_salesperson_fk_idx on sales.sales_orders (salesperson_id);
create index sales_orders_created_by_fk_idx on sales.sales_orders (created_by);
create index sales_orders_updated_by_fk_idx on sales.sales_orders (updated_by);
create index sales_order_lines_document_idx on sales.sales_order_lines (
  tenant_id, sales_order_id, line_number, id
);
create index sales_order_lines_source_quote_fk_idx on sales.sales_order_lines (
  tenant_id, source_quotation_id, source_quotation_revision,
  source_quotation_line_id
);
create index sales_order_lines_product_fk_idx
  on sales.sales_order_lines (tenant_id, legal_entity_id, product_id);
create index sales_order_lines_unit_fk_idx
  on sales.sales_order_lines (tenant_id, unit_id);
create index sales_order_lines_tax_fk_idx
  on sales.sales_order_lines (tenant_id, legal_entity_id, tax_definition_id);
create index sales_order_lines_created_by_fk_idx on sales.sales_order_lines (created_by);
create index sales_order_lines_updated_by_fk_idx on sales.sales_order_lines (updated_by);
create index credit_exposures_customer_idx on sales.customer_credit_exposures (
  tenant_id, legal_entity_id, branch_id, customer_id, currency_code, as_of_at desc
);
create index credit_exposures_created_by_fk_idx
  on sales.customer_credit_exposures (created_by);
create index credit_exposures_updated_by_fk_idx
  on sales.customer_credit_exposures (updated_by);
create index credit_decisions_order_idx on sales.credit_decisions (
  tenant_id, sales_order_id, decided_at desc, id
);
create index credit_decisions_customer_idx on sales.credit_decisions (
  tenant_id, customer_id, currency_code, decided_at desc, id
);
create index credit_decisions_branch_fk_idx
  on sales.credit_decisions (tenant_id, branch_id);
create index credit_decisions_override_by_fk_idx on sales.credit_decisions (override_by);
create index credit_decisions_created_by_fk_idx on sales.credit_decisions (created_by);
create index stock_balances_scope_idx on inventory.stock_balances (
  tenant_id, legal_entity_id, branch_id, warehouse_id, product_id
);
create index stock_balances_created_by_fk_idx on inventory.stock_balances (created_by);
create index stock_balances_updated_by_fk_idx on inventory.stock_balances (updated_by);
create index stock_reservations_order_idx on inventory.stock_reservations (
  tenant_id, sales_order_id, status, expires_at, id
);
create index stock_reservations_product_idx on inventory.stock_reservations (
  tenant_id, warehouse_id, product_id, status, expires_at, id
);
create index stock_reservations_branch_fk_idx
  on inventory.stock_reservations (tenant_id, branch_id);
create index stock_reservations_created_by_fk_idx
  on inventory.stock_reservations (created_by);
create index stock_reservations_updated_by_fk_idx
  on inventory.stock_reservations (updated_by);

create trigger sales_orders_touch before update on sales.sales_orders
for each row execute function core.touch_mutable_record();
create trigger sales_order_lines_touch before update on sales.sales_order_lines
for each row execute function core.touch_mutable_record();
create trigger customer_credit_exposures_touch
before update on sales.customer_credit_exposures
for each row execute function core.touch_mutable_record();
create trigger stock_balances_touch before update on inventory.stock_balances
for each row execute function core.touch_mutable_record();
create trigger stock_reservations_touch before update on inventory.stock_reservations
for each row execute function core.touch_mutable_record();
create trigger credit_decisions_immutable
before update or delete on sales.credit_decisions
for each row execute function sales.reject_immutable_history();

alter table sales.sales_orders enable row level security;
alter table sales.sales_orders force row level security;
alter table sales.sales_order_lines enable row level security;
alter table sales.sales_order_lines force row level security;
alter table sales.customer_credit_exposures enable row level security;
alter table sales.customer_credit_exposures force row level security;
alter table sales.credit_decisions enable row level security;
alter table sales.credit_decisions force row level security;
alter table inventory.stock_balances enable row level security;
alter table inventory.stock_balances force row level security;
alter table inventory.stock_reservations enable row level security;
alter table inventory.stock_reservations force row level security;

create policy sales_orders_permitted_read on sales.sales_orders
for select to authenticated using (
  core.is_tenant_member(tenant_id) and (
    core.has_permission(tenant_id, 'sales.orders.view', legal_entity_id, branch_id)
    or core.has_permission(tenant_id, 'sales.orders.manage', legal_entity_id, branch_id)
  )
);
create policy sales_order_lines_permitted_read on sales.sales_order_lines
for select to authenticated using (
  core.is_tenant_member(tenant_id) and (
    core.has_permission(tenant_id, 'sales.orders.view', legal_entity_id, branch_id)
    or core.has_permission(tenant_id, 'sales.orders.manage', legal_entity_id, branch_id)
  )
);
create policy credit_exposures_permitted_read on sales.customer_credit_exposures
for select to authenticated using (
  core.is_tenant_member(tenant_id)
  and core.has_permission(tenant_id, 'sales.orders.manage', legal_entity_id, branch_id)
);
create policy credit_decisions_permitted_read on sales.credit_decisions
for select to authenticated using (
  core.is_tenant_member(tenant_id) and (
    core.has_permission(tenant_id, 'sales.orders.view', legal_entity_id, branch_id)
    or core.has_permission(tenant_id, 'sales.orders.manage', legal_entity_id, branch_id)
  )
);
create policy stock_balances_permitted_read on inventory.stock_balances
for select to authenticated using (
  core.is_tenant_member(tenant_id) and (
    core.has_permission(tenant_id, 'inventory.stock.view', legal_entity_id, branch_id)
    or core.has_permission(tenant_id, 'inventory.reservations.manage', legal_entity_id, branch_id)
  )
);
create policy stock_reservations_permitted_read on inventory.stock_reservations
for select to authenticated using (
  core.is_tenant_member(tenant_id) and (
    core.has_permission(tenant_id, 'inventory.stock.view', legal_entity_id, branch_id)
    or core.has_permission(tenant_id, 'inventory.reservations.manage', legal_entity_id, branch_id)
  )
);

create view api.sales_orders with (security_invoker = true) as
select
  id, tenant_id, legal_entity_id, branch_id, document_number,
  source_quotation_id, source_quotation_revision, customer_id, contact_id,
  order_date, promised_date, ship_to, warehouse_id, currency_code,
  base_currency_code, exchange_rate_id, exchange_rate::text as exchange_rate,
  rate_date, payment_terms_days, delivery_terms, salesperson_id,
  header_discount_amount::text as header_discount_amount,
  header_discount_percent::text as header_discount_percent,
  subtotal::text as subtotal,
  line_discount_total::text as line_discount_total,
  header_discount_total::text as header_discount_total,
  discount_total::text as discount_total, tax_total::text as tax_total,
  grand_total::text as grand_total, base_total::text as base_total,
  notes, status, version, confirmed_at, cancelled_at,
  request_id, command_id, correlation_id, source_context, client_timestamp,
  created_by, updated_by, created_at, updated_at
from sales.sales_orders;

create view api.sales_order_lines with (security_invoker = true) as
select
  id, tenant_id, legal_entity_id, branch_id, sales_order_id, line_number,
  source_quotation_id, source_quotation_line_id, source_quotation_revision,
  product_id, product_kind,
  description, unit_id,
  conversion_numerator::text as conversion_numerator,
  conversion_denominator::text as conversion_denominator,
  ordered_quantity::text as ordered_quantity,
  base_ordered_quantity::text as base_ordered_quantity,
  cancelled_quantity::text as cancelled_quantity,
  allocated_quantity::text as allocated_quantity,
  delivered_quantity::text as delivered_quantity,
  invoiced_quantity::text as invoiced_quantity,
  unit_price::text as unit_price, gross_amount::text as gross_amount,
  line_discount_amount::text as line_discount_amount,
  discount_percent::text as discount_percent,
  header_discount_amount::text as header_discount_amount,
  net_amount::text as net_amount, tax_definition_id, tax_code, tax_name,
  tax_kind, tax_rate::text as tax_rate, tax_inclusive,
  tax_definition_version, taxable_amount::text as taxable_amount,
  tax_amount::text as tax_amount, line_total::text as line_total,
  currency_code, version, request_id, command_id, correlation_id,
  source_context, created_by, updated_by, created_at, updated_at
from sales.sales_order_lines;

create view api.customer_credit_exposures with (security_invoker = true) as
select
  id, tenant_id, legal_entity_id, branch_id, customer_id, currency_code,
  due_exposure::text as due_exposure,
  overdue_exposure::text as overdue_exposure,
  as_of_at, source_context, version, created_at, updated_at
from sales.customer_credit_exposures;

create view api.sales_credit_decisions with (security_invoker = true) as
select
  id, tenant_id, legal_entity_id, branch_id, sales_order_id, customer_id,
  currency_code, credit_limit::text as credit_limit,
  due_exposure::text as due_exposure,
  overdue_exposure::text as overdue_exposure,
  existing_order_exposure::text as existing_order_exposure,
  current_order_exposure::text as current_order_exposure,
  total_exposure::text as total_exposure, decision, override_applied,
  override_reason, override_by, request_id, command_id, correlation_id,
  source_context, decided_at, created_by, created_at
from sales.credit_decisions;

create view api.stock_availability with (security_invoker = true) as
select
  id, tenant_id, legal_entity_id, branch_id, warehouse_id, product_id,
  on_hand_quantity::text as on_hand_quantity,
  allocated_quantity::text as allocated_quantity,
  available_quantity::text as available_quantity,
  source_context, version, created_at, updated_at
from inventory.stock_balances;

create view api.stock_reservations with (security_invoker = true) as
select
  id, tenant_id, legal_entity_id, branch_id, warehouse_id, product_id,
  sales_order_id, sales_order_line_id, base_quantity::text as base_quantity,
  status, expires_at, released_at, release_reason, request_id, command_id,
  correlation_id, source_context, version, created_by, created_at, updated_at
from inventory.stock_reservations;

revoke all on sales.sales_orders, sales.sales_order_lines,
  sales.customer_credit_exposures, sales.credit_decisions,
  inventory.stock_balances, inventory.stock_reservations
  from public, anon, authenticated;
grant select on sales.sales_orders, sales.sales_order_lines,
  sales.customer_credit_exposures, sales.credit_decisions,
  inventory.stock_balances, inventory.stock_reservations to authenticated;
revoke all on api.sales_orders, api.sales_order_lines,
  api.customer_credit_exposures, api.sales_credit_decisions,
  api.stock_availability,
  api.stock_reservations from public, anon, authenticated;
grant select on api.sales_orders, api.sales_order_lines,
  api.customer_credit_exposures, api.sales_credit_decisions,
  api.stock_availability,
  api.stock_reservations to authenticated;

comment on table sales.customer_credit_exposures is
  'Private currency-specific receivables projection consumed by order credit control.';
comment on table inventory.stock_balances is
  'Non-posting stock projection; reservations change allocated, never on-hand quantity.';

notify pgrst, 'reload schema';
