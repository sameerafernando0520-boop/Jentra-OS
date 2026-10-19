begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(46);

-- FR-319..FR-325 / AC-303..AC-304: exact, versioned, tenant-scoped
-- quotation-to-order contracts with credit and reservation boundaries.
select is(
  (
    select count(*)
    from information_schema.tables
    where (table_schema, table_name) in (
      ('sales', 'quotations'),
      ('sales', 'quotation_lines'),
      ('sales', 'quotation_revisions'),
      ('sales', 'sales_orders'),
      ('sales', 'sales_order_lines'),
      ('sales', 'customer_credit_exposures'),
      ('sales', 'credit_decisions'),
      ('inventory', 'stock_balances'),
      ('inventory', 'stock_reservations')
    )
  ),
  9::bigint,
  'lead-to-cash foundation has all private relations'
);
select ok(
  (
    select count(*) = 9 and bool_and(c.relrowsecurity and c.relforcerowsecurity)
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and (n.nspname, c.relname) in (
        ('sales', 'quotations'),
        ('sales', 'quotation_lines'),
        ('sales', 'quotation_revisions'),
        ('sales', 'sales_orders'),
        ('sales', 'sales_order_lines'),
        ('sales', 'customer_credit_exposures'),
        ('sales', 'credit_decisions'),
        ('inventory', 'stock_balances'),
        ('inventory', 'stock_reservations')
      )
  ),
  'all lead-to-cash relations enable and force RLS'
);
select ok(
  (
    select count(*) = 9 and bool_and(
      coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']
    )
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'api'
      and c.relkind = 'v'
      and c.relname in (
        'sales_quotations', 'sales_quotation_lines',
        'sales_quotation_revisions', 'sales_orders', 'sales_order_lines',
        'customer_credit_exposures', 'sales_credit_decisions',
        'stock_availability',
        'stock_reservations'
      )
  ),
  'lead-to-cash reads use security-invoker API views'
);
select ok(
  (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(20,6)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'sales.quotations'::regclass
      and a.attname = 'grand_total' and not a.attisdropped
  )
  and (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(20,10)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'sales.quotations'::regclass
      and a.attname = 'exchange_rate' and not a.attisdropped
  )
  and (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(20,6)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'inventory.stock_reservations'::regclass
      and a.attname = 'base_quantity' and not a.attisdropped
  ),
  'money, rates, and quantities use explicit PostgreSQL numeric precision'
);
select ok(
  (
    select count(*) = 5 and bool_and(data_type = 'text')
    from information_schema.columns
    where table_schema = 'api'
      and (
        (table_name = 'sales_quotations'
          and column_name in ('exchange_rate', 'grand_total', 'base_total'))
        or (table_name = 'sales_order_lines'
          and column_name in ('ordered_quantity', 'unit_price'))
      )
  ),
  'public read models expose exact values as strings'
);
select has_function(
  'api', 'upsert_sales_quotation',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named quotation command exists'
);
select has_function(
  'api', 'transition_operational_document',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named operational transition command exists'
);
select has_function(
  'api', 'decide_operational_approval',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named approval decision command exists'
);
select has_function(
  'api', 'convert_quotation_to_order',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named quotation conversion command exists'
);
select has_function(
  'api', 'upsert_sales_order',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named sales-order command exists'
);
select has_function(
  'api', 'reserve_sales_order_stock',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named stock reservation command exists'
);
select ok(
  (
    select count(*) = 6 and bool_and(
      p.prosecdef
      and exists (
        select 1
        from unnest(coalesce(p.proconfig, '{}'::text[])) as config
        where config = 'search_path=""'
      )
    )
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and p.proname in (
        'upsert_sales_quotation', 'transition_operational_document',
        'decide_operational_approval', 'convert_quotation_to_order',
        'upsert_sales_order', 'reserve_sales_order_stock'
      )
  ),
  'all mutation commands are security definer with empty search paths'
);
select ok(
  not exists (
    select 1
    from information_schema.role_routine_grants as g
    where g.grantee in ('PUBLIC', 'anon')
      and g.specific_schema = 'api'
      and g.routine_name in (
        'upsert_sales_quotation', 'transition_operational_document',
        'decide_operational_approval', 'convert_quotation_to_order',
        'upsert_sales_order', 'reserve_sales_order_stock'
      )
  ),
  'PUBLIC and anon cannot execute lead-to-cash commands'
);
select ok(
  (
    select count(distinct g.routine_name) = 6
    from information_schema.role_routine_grants as g
    where g.grantee = 'authenticated'
      and g.specific_schema = 'api'
      and g.routine_name in (
        'upsert_sales_quotation', 'transition_operational_document',
        'decide_operational_approval', 'convert_quotation_to_order',
        'upsert_sales_order', 'reserve_sales_order_stock'
      )
  ),
  'authenticated clients execute only the named command surface'
);
select ok(
  has_table_privilege('authenticated', 'sales.quotations', 'SELECT')
  and not has_table_privilege('authenticated', 'sales.quotations', 'INSERT')
  and not has_table_privilege('authenticated', 'sales.sales_orders', 'UPDATE')
  and not has_table_privilege('authenticated', 'inventory.stock_reservations', 'DELETE')
  and not has_table_privilege('anon', 'api.sales_quotations', 'SELECT'),
  'base writes and anonymous reads are not granted'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'sales.quotation_revisions'::regclass
      and tgname = 'quotation_revisions_immutable' and not tgisinternal
  )
  and exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'sales.credit_decisions'::regclass
      and tgname = 'credit_decisions_immutable' and not tgisinternal
  ),
  'quotation revisions and credit decisions are immutable history'
);
select ok(
  to_regclass('inventory.stock_balances_tenant_branch_fk_idx') is not null
  and to_regclass('inventory.stock_balances_product_fk_idx') is not null
  and to_regclass('inventory.stock_balances_warehouse_fk_idx') is not null
  and to_regclass('inventory.stock_reservations_entity_fk_idx') is not null
  and to_regclass('inventory.stock_reservations_product_fk_idx') is not null
  and to_regclass('inventory.stock_reservations_order_fk_idx') is not null
  and to_regclass('inventory.stock_reservations_order_line_fk_idx') is not null
  and to_regclass('sales.credit_decisions_currency_fk_idx') is not null
  and to_regclass('sales.credit_decisions_entity_fk_idx') is not null
  and to_regclass('sales.credit_decisions_entity_order_fk_idx') is not null
  and to_regclass('sales.credit_exposures_currency_fk_idx') is not null
  and to_regclass('sales.credit_exposures_branch_fk_idx') is not null
  and to_regclass('sales.credit_exposures_customer_fk_idx') is not null
  and to_regclass('sales.quotation_lines_currency_fk_idx') is not null
  and to_regclass('sales.quotation_lines_entity_document_fk_idx') is not null
  and to_regclass('sales.quotation_revisions_entity_fk_idx') is not null
  and to_regclass('sales.quotation_revisions_entity_document_fk_idx') is not null
  and to_regclass('sales.quotations_base_currency_fk_idx') is not null
  and to_regclass('sales.quotations_currency_fk_idx') is not null
  and to_regclass('sales.quotations_branch_fk_idx') is not null
  and to_regclass('sales.sales_order_lines_currency_fk_idx') is not null
  and to_regclass('sales.sales_order_lines_branch_fk_idx') is not null
  and to_regclass('sales.sales_order_lines_entity_document_fk_idx') is not null
  and to_regclass('sales.sales_orders_base_currency_fk_idx') is not null
  and to_regclass('sales.sales_orders_currency_fk_idx') is not null
  and to_regclass('sales.sales_orders_customer_fk_idx') is not null
  and to_regclass('sales.sales_orders_source_quote_fk_idx') is not null,
  'every lead-to-cash foreign key has a covering index'
);

-- Three users and two tenants prove capability, SoD, and tenant isolation.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '15000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'seller@jentra.test', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '15000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'approver@jentra.test', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '15000000-0000-0000-0000-000000000099',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'other@jentra.test', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

insert into core.tenants (id, name, slug, default_currency_code, created_by) values
  (
    '25000000-0000-0000-0000-000000000001', 'Commerce Tenant',
    'commerce-tenant', 'LKR', '15000000-0000-0000-0000-000000000001'
  ),
  (
    '25000000-0000-0000-0000-000000000099', 'Other Commerce Tenant',
    'other-commerce-tenant', 'USD', '15000000-0000-0000-0000-000000000099'
  );

insert into core.legal_entities (
  id, tenant_id, name, code, currency_code, rounding_scale, created_by
) values
  (
    '35000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001',
    'Commerce Entity', 'COMMERCE', 'LKR', 2,
    '15000000-0000-0000-0000-000000000001'
  ),
  (
    '35000000-0000-0000-0000-000000000099',
    '25000000-0000-0000-0000-000000000099',
    'Other Entity', 'OTHERCOM', 'USD', 2,
    '15000000-0000-0000-0000-000000000099'
  );

insert into core.branches (
  id, tenant_id, legal_entity_id, name, code, created_by
) values
  (
    '45000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    'Commerce Head Office', 'COMHO',
    '15000000-0000-0000-0000-000000000001'
  ),
  (
    '45000000-0000-0000-0000-000000000099',
    '25000000-0000-0000-0000-000000000099',
    '35000000-0000-0000-0000-000000000099',
    'Other Head Office', 'OTHHO',
    '15000000-0000-0000-0000-000000000099'
  );

insert into core.warehouses (
  id, tenant_id, legal_entity_id, branch_id, name, code, created_by
) values (
  '55000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'Primary Warehouse', 'PRIMARY',
  '15000000-0000-0000-0000-000000000001'
);

insert into core.memberships (id, tenant_id, user_id, status, joined_at) values
  (
    '65000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001', 'active', now()
  ),
  (
    '65000000-0000-0000-0000-000000000002',
    '25000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000002', 'active', now()
  ),
  (
    '65000000-0000-0000-0000-000000000099',
    '25000000-0000-0000-0000-000000000099',
    '15000000-0000-0000-0000-000000000099', 'active', now()
  );

insert into core.roles (
  id, tenant_id, code, name, requires_mfa, is_system
) values
  (
    '75000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001',
    'sales_operator', 'Sales operator', true, true
  ),
  (
    '75000000-0000-0000-0000-000000000002',
    '25000000-0000-0000-0000-000000000001',
    'sales_approver', 'Sales approver', true, true
  );

insert into core.role_permissions (tenant_id, role_id, permission_code)
select '25000000-0000-0000-0000-000000000001',
  '75000000-0000-0000-0000-000000000001', p.code
from core.permissions as p
where p.code in (
  'sales.quotations.view', 'sales.quotations.manage',
  'sales.orders.view', 'sales.orders.manage',
  'inventory.stock.view', 'inventory.reservations.manage',
  'workflow.approvals.view', 'workflow.approvals.decide',
  'workflow.process.view'
);
insert into core.role_permissions (tenant_id, role_id, permission_code)
values (
  '25000000-0000-0000-0000-000000000001',
  '75000000-0000-0000-0000-000000000002',
  'workflow.approvals.decide'
);

insert into core.role_assignments (
  tenant_id, membership_id, role_id, legal_entity_id, branch_id, created_by
) values
  (
    '25000000-0000-0000-0000-000000000001',
    '65000000-0000-0000-0000-000000000001',
    '75000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  ),
  (
    '25000000-0000-0000-0000-000000000001',
    '65000000-0000-0000-0000-000000000002',
    '75000000-0000-0000-0000-000000000002',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  );

insert into crm.parties (
  id, tenant_id, code, legal_name, display_name, kind,
  credit_limit, credit_currency_code, payment_terms_days,
  created_by, updated_by
) values
  (
    '95000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001', 'CUS-ACME',
    'Acme Trading PLC', 'Acme Trading', 'customer',
    500.000000, 'LKR', 30,
    '15000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  ),
  (
    '95000000-0000-0000-0000-000000000099',
    '25000000-0000-0000-0000-000000000099', 'CUS-OTHER',
    'Other Customer LLC', 'Other Customer', 'customer',
    1000.000000, 'USD', 30,
    '15000000-0000-0000-0000-000000000099',
    '15000000-0000-0000-0000-000000000099'
  );

insert into inventory.units (
  id, tenant_id, code, name, symbol, category, precision, created_by, updated_by
) values (
  'a5000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000001',
  'EA', 'Each', 'ea', 'quantity', 0,
  '15000000-0000-0000-0000-000000000001',
  '15000000-0000-0000-0000-000000000001'
);

insert into finance.tax_definitions (
  id, tenant_id, legal_entity_id, code, name, rate, kind, inclusive,
  valid_from, status, created_by, updated_by
) values
  (
    'c5000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    'OUTPUT15', 'Output 15 percent', 15.000000, 'output', false,
    '2026-01-01', 'active',
    '15000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000002',
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    'OUTPUT15I', 'Output 15 percent inclusive', 15.000000, 'output', true,
    '2026-01-01', 'active',
    '15000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  );

insert into inventory.products (
  id, tenant_id, legal_entity_id, sku, name, kind, base_unit_id,
  can_sell, can_purchase, tax_definition_id, created_by, updated_by
) values
  (
    'b5000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    'STOCK-001', 'Stocked unit', 'stocked',
    'a5000000-0000-0000-0000-000000000001', true, true,
    'c5000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    'SERVICE-001', 'Inclusive service', 'service',
    'a5000000-0000-0000-0000-000000000001', true, false,
    'c5000000-0000-0000-0000-000000000002',
    '15000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  );

insert into core.document_sequences (
  id, tenant_id, legal_entity_id, branch_id, document_type,
  prefix, padding, next_value, status, created_by, updated_by
) values
  (
    'e5000000-0000-0000-0000-000000000001',
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'sales_quotation', 'QUO-', 6, 1, 'active',
    '15000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  ),
  (
    'e5000000-0000-0000-0000-000000000002',
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'sales_order', 'SO-', 6, 1, 'active',
    '15000000-0000-0000-0000-000000000001',
    '15000000-0000-0000-0000-000000000001'
  );

insert into workflow.workflow_definitions (
  id, tenant_id, legal_entity_id, document_type, name, revision,
  lifecycle, status, created_by, updated_by
) values (
  '85000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  'sales_quotation', 'Quotation approval', 3,
  '{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["draft","cancelled"],["submitted","approved"],["submitted","rejected"],["submitted","cancelled"],["rejected","draft"],["rejected","cancelled"],["approved","posted"],["approved","cancelled"],["posted","closed"],["posted","reversed"]],"quotation_transitions":[["submitted","draft"],["approved","draft"],["approved","accepted"],["submitted","accepted"],["submitted","expired"],["approved","expired"],["expired","draft"],["expired","cancelled"],["accepted","cancelled"]]}',
  'active',
  '15000000-0000-0000-0000-000000000001',
  '15000000-0000-0000-0000-000000000001'
);
insert into workflow.approval_matrix_steps (
  id, tenant_id, workflow_definition_id, role_id, step_order,
  minimum_amount, maximum_amount, currency_code,
  created_by, updated_by
) values (
  '86000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000001',
  '75000000-0000-0000-0000-000000000002', 1,
  0.000000, 1000.000000, 'LKR',
  '15000000-0000-0000-0000-000000000001',
  '15000000-0000-0000-0000-000000000001'
);

select is(
  (
    select array_agg(line->>'header_discount_amount' order by ordinal)
    from jsonb_array_elements(
      sales.wave3_price_lines(
        '25000000-0000-0000-0000-000000000001',
        '35000000-0000-0000-0000-000000000001',
        '2026-09-05',
        'LKR',
        '[
          {"line_id":"f5100000-0000-0000-0000-000000000011","product_id":"b5000000-0000-0000-0000-000000000001","description":"Allocation A","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"0.260000"},
          {"line_id":"f5100000-0000-0000-0000-000000000012","product_id":"b5000000-0000-0000-0000-000000000001","description":"Allocation B","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"0.260000"},
          {"line_id":"f5100000-0000-0000-0000-000000000013","product_id":"b5000000-0000-0000-0000-000000000001","description":"Allocation C","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"0.260000"},
          {"line_id":"f5100000-0000-0000-0000-000000000014","product_id":"b5000000-0000-0000-0000-000000000001","description":"Allocation D","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"0.220000"}
        ]'::jsonb,
        '"0.020000"'::jsonb,
        null
      )->'lines'
    ) with ordinality as priced(line, ordinal)
  ),
  array['0.010000', '0.000000', '0.010000', '0.000000'],
  'cumulative rounding keeps every proportional header allocation non-negative'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","email":"seller@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;

create temporary table quotation_create_result as
select api.upsert_sales_quotation(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001',
  '2026-09-05T09:00:00Z',
  '{
    "id":"f5000000-0000-0000-0000-000000000001",
    "customer_id":"95000000-0000-0000-0000-000000000001",
    "quotation_date":"2026-09-05","valid_until":"2099-10-05",
    "currency_code":"LKR","exchange_rate":"1.0000000000",
    "rate_date":"2026-09-05","payment_terms_days":30,
    "delivery_terms":"Delivered to Colombo",
    "salesperson_id":"15000000-0000-0000-0000-000000000001",
    "header_discount_percent":"10.000000",
    "notes":"Customer-facing note",
    "source_context":{"source":"wave3_lead_to_cash_test"},
    "lines":[
      {
        "line_id":"f5100000-0000-0000-0000-000000000001",
        "product_id":"b5000000-0000-0000-0000-000000000001",
        "description":"Stocked unit","unit_id":"a5000000-0000-0000-0000-000000000001",
        "quantity":"2.000000","base_quantity":"2.000000",
        "conversion_numerator":"1","conversion_denominator":"1",
        "unit_price":"100.000000","discount_percent":"10.000000",
        "tax_definition_id":"c5000000-0000-0000-0000-000000000001"
      },
      {
        "line_id":"f5100000-0000-0000-0000-000000000002",
        "product_id":"b5000000-0000-0000-0000-000000000002",
        "description":"Inclusive service","unit_id":"a5000000-0000-0000-0000-000000000001",
        "quantity":"1.000000","base_quantity":"1.000000",
        "conversion_numerator":"1","conversion_denominator":"1",
        "unit_price":"115.000000",
        "tax_definition_id":"c5000000-0000-0000-0000-000000000002"
      }
    ]
  }'::jsonb,
  null
) as response;

select ok(
  (select response#>>'{entity,subtotal}' from quotation_create_result) = '315.000000'
  and (select response#>>'{entity,line_discount_total}' from quotation_create_result) = '20.000000'
  and (select response#>>'{entity,header_discount_total}' from quotation_create_result) = '29.500000'
  and (select response#>>'{entity,tax_total}' from quotation_create_result) = '37.800000'
  and (select response#>>'{entity,grand_total}' from quotation_create_result) = '289.800000'
  and (select response#>>'{entity,base_total}' from quotation_create_result) = '289.800000',
  'quotation calculates exclusive and inclusive tax exactly'
);
select ok(
  (select response#>>'{entity,lines,0,tax_amount}' from quotation_create_result) = '24.300000'
  and (select response#>>'{entity,lines,0,line_total}' from quotation_create_result) = '186.300000'
  and (select response#>>'{entity,lines,1,net_amount}' from quotation_create_result) = '90.000000'
  and (select response#>>'{entity,lines,1,tax_amount}' from quotation_create_result) = '13.500000'
  and (select response#>>'{entity,lines,1,line_total}' from quotation_create_result) = '103.500000'
  and (select response#>>'{entity,lines,1,tax_inclusive}' from quotation_create_result) = 'true'
  and (select response#>>'{entity,lines,1,tax_definition_version}' from quotation_create_result) = '1',
  'line response preserves tax snapshots and exact allocation'
);
select ok(
  (
    select request_id = (response->>'request_id')::uuid
      and command_id = (response->>'command_id')::uuid
      and correlation_id = (response->>'correlation_id')::uuid
      and source_context->>'source' = 'wave3_lead_to_cash_test'
      and client_timestamp = '2026-09-05T09:00:00Z'::timestamptz
    from api.sales_quotations cross join quotation_create_result
    where id = 'f5000000-0000-0000-0000-000000000001'
  ),
  'quotation retains complete command attribution'
);
select is(
  api.upsert_sales_quotation(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    '2026-09-05T09:00:00Z',
    '{
      "id":"f5000000-0000-0000-0000-000000000001",
      "customer_id":"95000000-0000-0000-0000-000000000001",
      "quotation_date":"2026-09-05","valid_until":"2099-10-05",
      "currency_code":"LKR","exchange_rate":"1.0000000000",
      "rate_date":"2026-09-05","payment_terms_days":30,
      "delivery_terms":"Delivered to Colombo",
      "salesperson_id":"15000000-0000-0000-0000-000000000001",
      "header_discount_percent":"10.000000",
      "notes":"Customer-facing note",
      "source_context":{"source":"wave3_lead_to_cash_test"},
      "lines":[
        {"line_id":"f5100000-0000-0000-0000-000000000001","product_id":"b5000000-0000-0000-0000-000000000001","description":"Stocked unit","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"2.000000","base_quantity":"2.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"100.000000","discount_percent":"10.000000","tax_definition_id":"c5000000-0000-0000-0000-000000000001"},
        {"line_id":"f5100000-0000-0000-0000-000000000002","product_id":"b5000000-0000-0000-0000-000000000002","description":"Inclusive service","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"115.000000","tax_definition_id":"c5000000-0000-0000-0000-000000000002"}
      ]
    }'::jsonb,
    null
  ),
  (select response from quotation_create_result),
  'identical quotation retry returns the original response'
);
select throws_ok(
  $$select api.upsert_sales_quotation(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    '2026-09-05T09:00:00Z', '{"id":"f5000000-0000-0000-0000-000000000001"}', null
  )$$,
  '22023', 'IDEMPOTENCY_MISMATCH',
  'idempotency-key reuse with a different quotation payload is rejected'
);
select throws_ok(
  $$select api.upsert_sales_quotation(
    '25000000-0000-0000-0000-000000000099',
    '35000000-0000-0000-0000-000000000099',
    '45000000-0000-0000-0000-000000000099',
    'f1000000-0000-0000-0000-000000000099',
    'f2000000-0000-0000-0000-000000000099',
    '2026-09-05T09:01:00Z', '{}'::jsonb, null
  )$$,
  '42501', 'Permission denied or multi-factor authentication required.',
  'quotation command cannot cross tenant scope'
);
select throws_ok(
  $$select api.upsert_sales_quotation(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000003',
    'f2000000-0000-0000-0000-000000000003',
    '2026-09-05T09:02:00Z',
    (select response->'entity' || '{"notes":"stale"}'::jsonb from quotation_create_result),
    999
  )$$,
  '40001', 'VERSION_CONFLICT',
  'stale quotation update returns the stable conflict code'
);

create temporary table quotation_submit_result as
select api.transition_operational_document(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000004',
  'f2000000-0000-0000-0000-000000000004',
  '2026-09-05T09:10:00Z',
  '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000001","action":"submit","reason":"Ready for approval","source_context":{"source":"wave3_lead_to_cash_test"}}',
  1
) as response;
select ok(
  (select response#>>'{entity,status}' from quotation_submit_result) = 'pending_approval'
  and (select response#>>'{entity,document_number}' from quotation_submit_result) = 'QUO-000001'
  and (select response#>>'{entity,workflow_revision}' from quotation_submit_result) = '3'
  and (select response#>>'{entity,version}' from quotation_submit_result) = '2',
  'submission assigns a number and binds the approval workflow revision'
);
select ok(
  (
    select revision_number = 1 and status = 'submitted'
      and document_number = 'QUO-000001'
      and snapshot->>'grand_total' = '289.800000'
      and jsonb_array_length(snapshot->'lines') = 2
    from api.sales_quotation_revisions
    where quotation_id = 'f5000000-0000-0000-0000-000000000001'
  ),
  'submission stores one immutable customer-facing revision snapshot'
);
select ok(
  (
    select workflow_definition_id = '85000000-0000-0000-0000-000000000001'
      and workflow_revision = 3 and current_step = 1
      and amount = 289.800000 and currency_code = 'LKR'
    from api.approval_requests
    where document_id = 'f5000000-0000-0000-0000-000000000001'
      and status = 'submitted'
  ),
  'approval request preserves amount, currency, matrix step, and revision'
);
select throws_ok(
  $$select api.decide_operational_approval(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000005',
    'f2000000-0000-0000-0000-000000000005',
    '2026-09-05T09:11:00Z',
    '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000001","decision":"approved","note":"Self approval"}',
    2
  )$$,
  '42501', 'SEGREGATION_OF_DUTIES_VIOLATION',
  'quotation submitter cannot approve their own request'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated","email":"approver@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;
create temporary table quotation_approval_result as
select api.decide_operational_approval(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000006',
  'f2000000-0000-0000-0000-000000000006',
  '2026-09-05T09:12:00Z',
  '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000001","decision":"approved","note":"Commercial terms approved","source_context":{"source":"wave3_lead_to_cash_test"}}',
  2
) as response;
select ok(
  (select response#>>'{entity,status}' from quotation_approval_result) = 'approved'
  and (select response#>>'{entity,version}' from quotation_approval_result) = '3'
  and (
    select count(*) = 1 and bool_and(
      workflow_revision = 3 and decision = 'approved'
      and actor_id = '15000000-0000-0000-0000-000000000002'
    )
    from api.approval_decisions
    where approval_request_id = (
      select id from api.approval_requests
      where document_id = 'f5000000-0000-0000-0000-000000000001'
    )
  ),
  'authorized approval advances the quotation and records immutable history'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","email":"seller@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select api.transition_operational_document(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000090',
    'f2000000-0000-0000-0000-000000000090',
    '2099-10-06T09:19:00Z',
    '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000001","action":"accept","reason":"Late acceptance"}',
    3
  )$$,
  '55000', 'QUOTATION_EXPIRED',
  'acceptance enforces the submitted revision expiry boundary'
);
create temporary table quotation_accept_result as
select api.transition_operational_document(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000007',
  'f2000000-0000-0000-0000-000000000007',
  '2026-09-05T09:20:00Z',
  '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000001","action":"accept","reason":"Customer accepted by email"}',
  3
) as response;
select ok(
  (select response#>>'{entity,status}' from quotation_accept_result) = 'accepted'
  and (select response#>>'{entity,version}' from quotation_accept_result) = '4'
  and (select response#>>'{entity,accepted_at}' from quotation_accept_result) is not null,
  'approved and unexpired quotation can be accepted once'
);
select throws_ok(
  $$select api.upsert_sales_quotation(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000008',
    'f2000000-0000-0000-0000-000000000008',
    '2026-09-05T09:21:00Z',
    (select response->'entity' || '{"create_revision":true,"revision_reason":"Late change"}'::jsonb from quotation_accept_result),
    4
  )$$,
  '55000', 'ACCEPTED_QUOTATION_IMMUTABLE',
  'accepted customer-facing quotation cannot be revised'
);

create temporary table order_conversion_result as
select api.convert_quotation_to_order(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000009',
  'f2000000-0000-0000-0000-000000000009',
  '2026-09-05T09:30:00Z',
  '{"quotation_id":"f5000000-0000-0000-0000-000000000001","quotation_revision":1,"promised_date":"2026-09-20","warehouse_id":"55000000-0000-0000-0000-000000000001","ship_to":{"city":"Colombo"},"source_context":{"source":"wave3_lead_to_cash_test"}}',
  4
) as response;
select ok(
  (select response#>>'{entity,source_quotation_id}' from order_conversion_result)
    = 'f5000000-0000-0000-0000-000000000001'
  and (select response#>>'{entity,source_quotation_revision}' from order_conversion_result) = '1'
  and (select response#>>'{entity,grand_total}' from order_conversion_result) = '289.800000'
  and (select response#>>'{entity,status}' from order_conversion_result) = 'draft'
  and (select jsonb_array_length(response#>'{entity,lines}') from order_conversion_result) = 2
  and (
    select status = 'converted' and version = 5
    from api.sales_quotations
    where id = 'f5000000-0000-0000-0000-000000000001'
  ),
  'conversion copies the accepted revision and preserves traceability'
);
create temporary table order_conversion_retry_result as
select api.convert_quotation_to_order(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000010',
  'f2000000-0000-0000-0000-000000000010',
  '2026-09-05T09:31:00Z',
  '{"quotation_id":"f5000000-0000-0000-0000-000000000001","quotation_revision":1,"promised_date":"2026-09-20","warehouse_id":"55000000-0000-0000-0000-000000000001","ship_to":{"city":"Colombo"},"source_context":{"source":"wave3_lead_to_cash_test"}}',
  4
) as response;
select ok(
  (select response#>>'{entity,id}' from order_conversion_retry_result)
    = (select response#>>'{entity,id}' from order_conversion_result)
  and (
    select count(*) = 1
    from api.sales_orders
    where source_quotation_id = 'f5000000-0000-0000-0000-000000000001'
      and source_quotation_revision = 1
  ),
  'semantic conversion retry returns the original order without duplicates'
);

reset role;
insert into sales.customer_credit_exposures (
  id, tenant_id, legal_entity_id, branch_id, customer_id, currency_code,
  due_exposure, overdue_exposure, as_of_at, source_context,
  created_by, updated_by
) values (
  'f6000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000001', 'LKR',
  100.000000, 20.000000, '2026-09-05T09:35:00Z',
  '{"source":"finance_projection_fixture"}',
  '15000000-0000-0000-0000-000000000001',
  '15000000-0000-0000-0000-000000000001'
);
set local role authenticated;
create temporary table order_confirm_result as
select api.transition_operational_document(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000011',
  'f2000000-0000-0000-0000-000000000011',
  '2026-09-05T09:40:00Z',
  (select jsonb_build_object(
    'document_type', 'sales_order',
    'document_id', response#>>'{entity,id}',
    'action', 'confirm', 'reason', 'Customer order confirmed'
  ) from order_conversion_result),
  1
) as response;
select ok(
  (select response#>>'{entity,status}' from order_confirm_result) = 'confirmed'
  and (select response#>>'{entity,document_number}' from order_confirm_result) = 'SO-000001'
  and (
    select credit_limit = '500.000000' and due_exposure = '100.000000'
      and overdue_exposure = '20.000000'
      and existing_order_exposure = '0.000000'
      and current_order_exposure = '289.800000'
      and total_exposure = '389.800000' and decision = 'approved'
    from api.sales_credit_decisions
    where sales_order_id = (
      select (response#>>'{entity,id}')::uuid from order_confirm_result
    )
  ),
  'order confirmation snapshots currency-separated credit exposure exactly'
);

create temporary table direct_order_result as
select api.upsert_sales_order(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000012',
  'f2000000-0000-0000-0000-000000000012',
  '2026-09-05T09:41:00Z',
  '{"id":"f7000000-0000-0000-0000-000000000001","customer_id":"95000000-0000-0000-0000-000000000001","order_date":"2026-09-05","promised_date":"2026-09-25","currency_code":"LKR","exchange_rate":"1.0000000000","rate_date":"2026-09-05","warehouse_id":"55000000-0000-0000-0000-000000000001","payment_terms_days":30,"ship_to":{"city":"Colombo"},"lines":[{"line_id":"f7100000-0000-0000-0000-000000000001","product_id":"b5000000-0000-0000-0000-000000000001","description":"Additional stock","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"200.000000"}]}',
  null
) as response;
reset role;
update sales.customer_credit_exposures
set due_exposure = 400.000000, overdue_exposure = 100.000000,
  updated_by = '15000000-0000-0000-0000-000000000001'
where id = 'f6000000-0000-0000-0000-000000000001';
set local role authenticated;
create temporary table credit_hold_result as
select api.transition_operational_document(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000013',
  'f2000000-0000-0000-0000-000000000013',
  '2026-09-05T09:42:00Z',
  '{"document_type":"sales_order","document_id":"f7000000-0000-0000-0000-000000000001","action":"confirm","reason":"Credit check"}',
  1
) as response;
select ok(
  (select response#>>'{entity,status}' from credit_hold_result) = 'credit_hold'
  and (select response#>>'{warnings,0}' from credit_hold_result) = 'CREDIT_LIMIT_EXCEEDED'
  and (
    select total_exposure = '889.800000' and decision = 'blocked'
      and override_applied is false
    from api.sales_credit_decisions
    where sales_order_id = 'f7000000-0000-0000-0000-000000000001'
  ),
  'over-limit order enters an auditable credit hold'
);
select throws_ok(
  $$select api.transition_operational_document(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000014',
    'f2000000-0000-0000-0000-000000000014',
    '2026-09-05T09:43:00Z',
    '{"document_type":"sales_order","document_id":"f7000000-0000-0000-0000-000000000001","action":"confirm","override_credit":true,"override_reason":"Director exception"}',
    2
  )$$,
  '42501', 'Permission denied or multi-factor authentication required.',
  'credit override requires its distinct privileged capability'
);
reset role;
insert into core.role_permissions (tenant_id, role_id, permission_code) values (
  '25000000-0000-0000-0000-000000000001',
  '75000000-0000-0000-0000-000000000001', 'sales.credit.override'
);
set local role authenticated;
create temporary table credit_override_result as
select api.transition_operational_document(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000015',
  'f2000000-0000-0000-0000-000000000015',
  '2026-09-05T09:44:00Z',
  '{"document_type":"sales_order","document_id":"f7000000-0000-0000-0000-000000000001","action":"confirm","override_credit":true,"override_reason":"Director exception"}',
  2
) as response;
select ok(
  (select response#>>'{entity,status}' from credit_override_result) = 'confirmed'
  and (
    select count(*) = 1 and bool_and(
      decision = 'overridden' and override_applied
      and override_reason = 'Director exception'
      and override_by = '15000000-0000-0000-0000-000000000001'
    )
    from api.sales_credit_decisions
    where sales_order_id = 'f7000000-0000-0000-0000-000000000001'
      and decision = 'overridden'
  ),
  'privileged credit override is explicit and attributable'
);

reset role;
insert into inventory.stock_balances (
  id, tenant_id, legal_entity_id, branch_id, warehouse_id, product_id,
  on_hand_quantity, allocated_quantity, source_context,
  created_by, updated_by
) values (
  'f8000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  '55000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000001',
  1.500000, 0.000000, '{"source":"stock_projection_fixture"}',
  '15000000-0000-0000-0000-000000000001',
  '15000000-0000-0000-0000-000000000001'
);
set local role authenticated;
create temporary table reservation_result as
select api.reserve_sales_order_stock(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000016',
  'f2000000-0000-0000-0000-000000000016',
  '2026-09-05T09:50:00Z',
  (select jsonb_build_object(
    'sales_order_id', response#>>'{entity,id}',
    'expires_at', '2026-09-12T12:00:00Z',
    'lines', jsonb_build_array(jsonb_build_object(
      'sales_order_line_id', response#>>'{entity,lines,0,id}',
      'requested_base_quantity', '2.000000'
    )),
    'source_context', '{"source":"wave3_lead_to_cash_test"}'::jsonb
  ) from order_confirm_result),
  2
) as response;
select ok(
  (select response#>>'{entity,status}' from reservation_result) = 'partially_reserved'
  and (select response#>>'{warnings,0}' from reservation_result) = 'PARTIAL_STOCK_RESERVATION'
  and (
    select on_hand_quantity = '1.500000' and allocated_quantity = '1.500000'
      and available_quantity = '0.000000'
    from api.stock_availability
    where id = 'f8000000-0000-0000-0000-000000000001'
  )
  and (
    select count(*) = 1 and bool_and(base_quantity = '1.500000' and status = 'active')
    from api.stock_reservations
    where sales_order_id = (
      select (response#>>'{entity,id}')::uuid from reservation_result
    )
  ),
  'reservation is bounded by available stock without changing on-hand quantity'
);
select is(
  api.reserve_sales_order_stock(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000016',
    'f2000000-0000-0000-0000-000000000016',
    '2026-09-05T09:50:00Z',
    (select jsonb_build_object(
      'sales_order_id', response#>>'{entity,id}',
      'expires_at', '2026-09-12T12:00:00Z',
      'lines', jsonb_build_array(jsonb_build_object(
        'sales_order_line_id', response#>>'{entity,lines,0,id}',
        'requested_base_quantity', '2.000000'
      )),
      'source_context', '{"source":"wave3_lead_to_cash_test"}'::jsonb
    ) from order_confirm_result),
    2
  ),
  (select response from reservation_result),
  'identical reservation retry cannot double-allocate stock'
);
reset role;
update inventory.stock_balances
set on_hand_quantity = 2.000000,
  updated_by = '15000000-0000-0000-0000-000000000001'
where id = 'f8000000-0000-0000-0000-000000000001';
set local role authenticated;
create temporary table reservation_complete_result as
select api.reserve_sales_order_stock(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000017',
  'f2000000-0000-0000-0000-000000000017',
  '2026-09-05T09:51:00Z',
  (select jsonb_build_object(
    'sales_order_id', response#>>'{entity,id}',
    'expires_at', '2026-09-12T12:00:00Z',
    'lines', jsonb_build_array(jsonb_build_object(
      'sales_order_line_id', response#>>'{entity,lines,0,id}',
      'requested_base_quantity', '0.500000'
    ))
  ) from order_confirm_result),
  3
) as response;
select ok(
  (select response#>>'{entity,status}' from reservation_complete_result) = 'reserved'
  and (
    select allocated_quantity = '2.000000' and available_quantity = '0.000000'
      and on_hand_quantity = '2.000000'
    from api.stock_availability
    where id = 'f8000000-0000-0000-0000-000000000001'
  )
  and (
    select base_quantity = '2.000000'
    from api.stock_reservations
    where sales_order_id = (
      select (response#>>'{entity,id}')::uuid from reservation_complete_result
    ) and status = 'active'
  ),
  'incremental reservation stops at remaining demand and reaches reserved state'
);

create temporary table order_cancel_result as
select api.transition_operational_document(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000018',
  'f2000000-0000-0000-0000-000000000018',
  '2026-09-05T09:55:00Z',
  (select jsonb_build_object(
    'document_type', 'sales_order',
    'document_id', response#>>'{entity,id}',
    'action', 'cancel', 'reason', 'Customer cancelled'
  ) from order_confirm_result),
  4
) as response;
select ok(
  (select response#>>'{entity,status}' from order_cancel_result) = 'cancelled'
  and (
    select allocated_quantity = '0.000000' and on_hand_quantity = '2.000000'
    from api.stock_availability
    where id = 'f8000000-0000-0000-0000-000000000001'
  )
  and (
    select count(*) = 1 and bool_and(status = 'released' and released_at is not null)
    from api.stock_reservations
    where sales_order_id = (
      select (response#>>'{entity,id}')::uuid from order_cancel_result
    )
  )
  and (
    select allocated_quantity = '0.000000'
    from api.sales_order_lines
    where sales_order_id = (
      select (response#>>'{entity,id}')::uuid from order_cancel_result
    ) and product_id = 'b5000000-0000-0000-0000-000000000001'
  ),
  'order cancellation releases reservations without reversing stock on hand'
);

-- A second quotation proves a rejected customer-facing revision can be
-- revised without altering the submitted snapshot or reusing its line rows.
create temporary table revision_quote_create_result as
select api.upsert_sales_quotation(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000020',
  'f2000000-0000-0000-0000-000000000020',
  '2026-09-05T10:00:00Z',
  '{"id":"f5000000-0000-0000-0000-000000000002","customer_id":"95000000-0000-0000-0000-000000000001","quotation_date":"2026-09-05","valid_until":"2099-10-05","currency_code":"LKR","exchange_rate":"1.0000000000","rate_date":"2026-09-05","salesperson_id":"15000000-0000-0000-0000-000000000001","lines":[{"line_id":"f5100000-0000-0000-0000-000000000020","product_id":"b5000000-0000-0000-0000-000000000001","description":"Revision proof","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"10.000000"}]}',
  null
) as response;
create temporary table revision_quote_submit_result as
select api.transition_operational_document(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000021',
  'f2000000-0000-0000-0000-000000000021',
  '2026-09-05T10:01:00Z',
  '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000002","action":"submit","reason":"Revision one"}',
  1
) as response;
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated","email":"approver@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;
create temporary table revision_quote_reject_result as
select api.decide_operational_approval(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000022',
  'f2000000-0000-0000-0000-000000000022',
  '2026-09-05T10:02:00Z',
  '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000002","decision":"rejected","note":"Extend validity"}',
  2
) as response;
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","email":"seller@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;
create temporary table revision_quote_result as
select api.upsert_sales_quotation(
  '25000000-0000-0000-0000-000000000001',
  '35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000023',
  'f2000000-0000-0000-0000-000000000023',
  '2026-09-05T10:03:00Z',
  '{"id":"f5000000-0000-0000-0000-000000000002","customer_id":"95000000-0000-0000-0000-000000000001","quotation_date":"2026-09-05","valid_until":"2099-11-05","currency_code":"LKR","exchange_rate":"1.0000000000","rate_date":"2026-09-05","salesperson_id":"15000000-0000-0000-0000-000000000001","create_revision":true,"revision_reason":"Validity extended","lines":[{"line_id":"f5100000-0000-0000-0000-000000000023","product_id":"b5000000-0000-0000-0000-000000000001","description":"Revision proof extended","unit_id":"a5000000-0000-0000-0000-000000000001","quantity":"1.000000","base_quantity":"1.000000","conversion_numerator":"1","conversion_denominator":"1","unit_price":"10.000000"}]}',
  3
) as response;
select ok(
  (select response#>>'{entity,current_revision}' from revision_quote_result) = '2'
  and (select response#>>'{entity,status}' from revision_quote_result) = 'draft'
  and (select response#>>'{entity,version}' from revision_quote_result) = '4'
  and (select response#>>'{entity,document_number}' from revision_quote_result) = 'QUO-000002'
  and (
    select count(*) = 1 and bool_and(snapshot->>'valid_until' = '2099-10-05')
    from api.sales_quotation_revisions
    where quotation_id = 'f5000000-0000-0000-0000-000000000002'
  )
  and (
    select count(*) = 2
      and count(*) filter (where revision_number = 1) = 1
      and count(*) filter (where revision_number = 2) = 1
    from api.sales_quotation_lines
    where quotation_id = 'f5000000-0000-0000-0000-000000000002'
  ),
  'rejected quotation creates a new draft revision and preserves revision one'
);

select ok(
  (select count(*) from api.sales_quotations
    where tenant_id = '25000000-0000-0000-0000-000000000099') = 0
  and (select count(*) from api.sales_orders
    where tenant_id = '25000000-0000-0000-0000-000000000099') = 0,
  'security-invoker views hide other-tenant documents'
);
reset role;
update core.memberships set status = 'revoked'
where id = '65000000-0000-0000-0000-000000000001';
set local role authenticated;
select ok(
  (select count(*) from api.sales_quotations
    where tenant_id = '25000000-0000-0000-0000-000000000001') = 0
  and (select count(*) from api.sales_orders
    where tenant_id = '25000000-0000-0000-0000-000000000001') = 0
  and (select count(*) from api.stock_reservations
    where tenant_id = '25000000-0000-0000-0000-000000000001') = 0,
  'revoked membership immediately removes lead-to-cash visibility'
);

reset role;
select * from finish();
rollback;
