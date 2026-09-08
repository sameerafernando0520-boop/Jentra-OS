begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- FR-322–FR-325 / AC-304. Synthetic fixtures roll back in this transaction.
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


create function pg_temp.order_command(
  verb text, payload jsonb, expected bigint default null,
  request_key uuid default gen_random_uuid()
) returns jsonb language plpgsql as $$
begin
  case verb
    when 'save' then return api.upsert_sales_order(
      '25000000-0000-0000-0000-000000000001',
      '35000000-0000-0000-0000-000000000001',
      '45000000-0000-0000-0000-000000000001',
      request_key, request_key, '2026-09-07T00:00:00Z', payload, expected);
    when 'quote' then return api.upsert_sales_quotation(
      '25000000-0000-0000-0000-000000000001',
      '35000000-0000-0000-0000-000000000001',
      '45000000-0000-0000-0000-000000000001',
      request_key, request_key, '2026-09-07T00:00:00Z', payload, expected);
    when 'convert' then return api.convert_quotation_to_order(
      '25000000-0000-0000-0000-000000000001',
      '35000000-0000-0000-0000-000000000001',
      '45000000-0000-0000-0000-000000000001',
      request_key, request_key, '2026-09-07T00:00:00Z', payload, expected);
    when 'transition' then return api.transition_operational_document(
      '25000000-0000-0000-0000-000000000001',
      '35000000-0000-0000-0000-000000000001',
      '45000000-0000-0000-0000-000000000001',
      request_key, request_key, '2026-09-07T00:00:00Z', payload, expected);
    when 'decide' then return api.decide_operational_approval(
      '25000000-0000-0000-0000-000000000001',
      '35000000-0000-0000-0000-000000000001',
      '45000000-0000-0000-0000-000000000001',
      request_key, request_key, '2026-09-07T00:00:00Z', payload, expected);
    when 'reserve' then return api.reserve_sales_order_stock(
      '25000000-0000-0000-0000-000000000001',
      '35000000-0000-0000-0000-000000000001',
      '45000000-0000-0000-0000-000000000001',
      request_key, request_key, '2026-09-07T00:00:00Z', payload, expected);
    when 'fulfillment' then return api.update_sales_order_fulfillment(
      '25000000-0000-0000-0000-000000000001',
      '35000000-0000-0000-0000-000000000001',
      '45000000-0000-0000-0000-000000000001',
      request_key, request_key, '2026-09-07T00:00:00Z', payload, expected);
    else raise exception 'Unknown test command';
  end case;
end;
$$;

create temporary table order_input as select '{
  "id":"fa040000-0000-0000-0000-000000000001",
  "customer_id":"95000000-0000-0000-0000-000000000001",
  "order_date":"2026-09-05","promised_date":"2099-09-20",
  "warehouse_id":"55000000-0000-0000-0000-000000000001",
  "ship_to":{"city":"Colombo"},"currency_code":"LKR",
  "exchange_rate":"1.0000000000","rate_date":"2026-09-05",
  "payment_terms_days":30,"notes":"Order workspace fixture",
  "lines":[{"line_id":"fa041000-0000-0000-0000-000000000001",
    "product_id":"b5000000-0000-0000-0000-000000000001",
    "description":"Stocked fixture","unit_id":"a5000000-0000-0000-0000-000000000001",
    "quantity":"10.000000","base_quantity":"10.000000",
    "conversion_numerator":"1","conversion_denominator":"1",
    "unit_price":"10.000000"}]
}'::jsonb as payload;
grant select on order_input to authenticated;
select set_config('request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
create temporary table saved_order as
select pg_temp.order_command('save',(select payload from order_input)) as response;

reset role;
update crm.parties set status='inactive' where id='95000000-0000-0000-0000-000000000001';
set local role authenticated;
select throws_ok($q$select pg_temp.order_command('transition',
  '{"document_type":"sales_order","document_id":"fa040000-0000-0000-0000-000000000001","action":"confirm"}',1)$q$,
  '55000','CUSTOMER_INACTIVE','inactive customers cannot gain a confirmed order');
reset role;
update crm.parties set status='active' where id='95000000-0000-0000-0000-000000000001';
set local role authenticated;

select has_view('api','sales_order_details','one coherent caller-RLS order detail view exists');
select ok((select jsonb_array_length(lines)=1 and grand_total='100.000000'
  from api.sales_order_details where id='fa040000-0000-0000-0000-000000000001'),
  'detail includes exact header and current line values');
select ok((select reloptions @> array['security_invoker=true']
  from pg_class where oid='api.sales_order_details'::regclass),
  'detail view keeps caller RLS');

create temporary table credit_preview as select api.get_sales_order_credit_preview(
  '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001','fa040000-0000-0000-0000-000000000001') as snapshot;
select ok((select snapshot->>'total_exposure'='100.000000'
  and snapshot->>'credit_limit'='500.000000'
  and snapshot->>'projection_available'='false'
  and snapshot->>'customer_status'='active' from credit_preview),
  'credit preview uses exact scoped currency values and declares missing projection');

reset role;
insert into sales.customer_credit_exposures(
  tenant_id,legal_entity_id,branch_id,customer_id,currency_code,
  due_exposure,overdue_exposure,as_of_at,created_by,updated_by
) values (
  '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',
  'LKR',450,20,'2026-09-07T00:00:00Z',
  '15000000-0000-0000-0000-000000000001','15000000-0000-0000-0000-000000000001');
set local role authenticated;
select ok((select snapshot->>'due_exposure'='450.000000'
  and snapshot->>'overdue_exposure'='20.000000'
  and snapshot->>'total_exposure'='550.000000'
  and snapshot->>'projection_available'='true'
  and snapshot->>'reason'='CREDIT_LIMIT_EXCEEDED'
  from (select api.get_sales_order_credit_preview(
    '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001','fa040000-0000-0000-0000-000000000001') as snapshot) s),
  'overdue exposure is disclosed as part of due, without being double counted');
reset role;
delete from sales.customer_credit_exposures where customer_id='95000000-0000-0000-0000-000000000001';
update crm.parties set credit_currency_code='USD' where id='95000000-0000-0000-0000-000000000001';
set local role authenticated;
select throws_ok($q$select pg_temp.order_command('transition',
  '{"document_type":"sales_order","document_id":"fa040000-0000-0000-0000-000000000001","action":"confirm"}',1)$q$,
  '55000','CREDIT_CURRENCY_MISMATCH','confirmation never combines different credit currencies');
select is(api.get_sales_order_credit_preview(
    '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001','fa040000-0000-0000-0000-000000000001')->>'reason',
  'CREDIT_CURRENCY_MISMATCH','preview reports credit currency mismatch before commitment');
reset role;
update crm.parties set credit_currency_code='LKR' where id='95000000-0000-0000-0000-000000000001';
set local role authenticated;

create temporary table confirmed_order as select pg_temp.order_command('transition',
  '{"document_type":"sales_order","document_id":"fa040000-0000-0000-0000-000000000001","action":"confirm"}',1) as response;
select ok((select total_exposure=(select snapshot->>'total_exposure' from credit_preview)
  and decision='approved' from api.sales_credit_decisions
  where sales_order_id='fa040000-0000-0000-0000-000000000001'),
  'confirmation decision agrees with the server credit preview');

reset role;
insert into inventory.stock_balances(
  tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,
  created_by,updated_by
) values (
  '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001','55000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000001',20,
  '15000000-0000-0000-0000-000000000001','15000000-0000-0000-0000-000000000001');
update core.warehouses set status='inactive' where id='55000000-0000-0000-0000-000000000001';
set local role authenticated;
select throws_ok($q$select pg_temp.order_command('reserve',
  '{"sales_order_id":"fa040000-0000-0000-0000-000000000001","expires_at":"2099-09-20T00:00:00Z",
    "lines":[{"sales_order_line_id":"fa041000-0000-0000-0000-000000000001","requested_base_quantity":"10.000000"}]}',2)$q$,
  '55000','WAREHOUSE_INACTIVE','reservations recheck warehouse eligibility');
reset role;
update core.warehouses set status='active' where id='55000000-0000-0000-0000-000000000001';
update inventory.products set status='inactive' where id='b5000000-0000-0000-0000-000000000001';
set local role authenticated;
select throws_ok($q$select pg_temp.order_command('reserve',
  '{"sales_order_id":"fa040000-0000-0000-0000-000000000001","expires_at":"2099-09-20T00:00:00Z",
    "lines":[{"sales_order_line_id":"fa041000-0000-0000-0000-000000000001","requested_base_quantity":"10.000000"}]}',2)$q$,
  '55000','PRODUCT_NOT_RESERVABLE','reservations recheck current stocked product eligibility');
reset role;
update inventory.products set status='active' where id='b5000000-0000-0000-0000-000000000001';
-- A delivery projection is seeded only to test the remaining-demand boundary.
update sales.sales_order_lines set delivered_quantity=4 where id='fa041000-0000-0000-0000-000000000001';
set local role authenticated;
create temporary table reserved_order as select pg_temp.order_command('reserve',
  '{"sales_order_id":"fa040000-0000-0000-0000-000000000001","expires_at":"2099-09-20T00:00:00Z",
    "lines":[{"sales_order_line_id":"fa041000-0000-0000-0000-000000000001","requested_base_quantity":"10.000000"}]}',2) as response;
select ok((select allocated_quantity='6.000000' and delivered_quantity='4.000000'
  from api.sales_order_lines where id='fa041000-0000-0000-0000-000000000001'),
  'already delivered base demand cannot be reserved a second time');
select is((select on_hand_quantity from api.stock_availability
  where product_id='b5000000-0000-0000-0000-000000000001'),'20.000000',
  'reservation preserves on-hand quantity');
select throws_ok($q$select pg_temp.order_command('transition',
  '{"document_type":"sales_order","document_id":"fa040000-0000-0000-0000-000000000001","action":"cancel","reason":"Request"}',3)$q$,
  '55000','FULFILLED_ORDER_NOT_CANCELLABLE','delivered orders cannot be cancelled');
reset role;
-- Restore the synthetic delivery projection to exercise whole-order cancellation.
update sales.sales_order_lines set delivered_quantity=0 where id='fa041000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.order_command('transition',
  '{"document_type":"sales_order","document_id":"fa040000-0000-0000-0000-000000000001","action":"cancel","reason":"Customer request"}',3);
select ok((select cancelled_quantity='10.000000' and allocated_quantity='0.000000'
  from api.sales_order_lines where id='fa041000-0000-0000-0000-000000000001'),
  'cancellation records the cancelled demand and clears allocation');
select ok((select status='released' and released_at is not null
  from api.stock_reservations where sales_order_id='fa040000-0000-0000-0000-000000000001'),
  'cancellation retains released reservation history');
select ok((select on_hand_quantity='20.000000' and allocated_quantity='0.000000'
  from api.stock_availability where product_id='b5000000-0000-0000-0000-000000000001'),
  'cancellation releases availability without a stock movement');

create temporary table quote_saved as select pg_temp.order_command('quote',
  (select payload - 'id' - 'order_date' - 'promised_date' - 'warehouse_id' - 'ship_to'
    || '{"id":"fa045000-0000-0000-0000-000000000001","quotation_date":"2026-09-05",
      "valid_until":"2099-09-20","salesperson_id":"15000000-0000-0000-0000-000000000001"}'::jsonb
    || jsonb_build_object('lines',jsonb_build_array((payload->'lines'->0)-'line_id'))
    from order_input)) as response;
select pg_temp.order_command('transition',
  '{"document_type":"sales_quotation","document_id":"fa045000-0000-0000-0000-000000000001","action":"submit"}',1);
select set_config('request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}',true);
select pg_temp.order_command('decide',
  '{"document_type":"sales_quotation","document_id":"fa045000-0000-0000-0000-000000000001","decision":"approved"}',2);
select set_config('request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',true);
select pg_temp.order_command('transition',
  '{"document_type":"sales_quotation","document_id":"fa045000-0000-0000-0000-000000000001","action":"accept"}',3);
create temporary table conversion as select pg_temp.order_command('convert',
  '{"quotation_id":"fa045000-0000-0000-0000-000000000001","quotation_revision":1,
    "promised_date":"2099-09-20","warehouse_id":"55000000-0000-0000-0000-000000000001",
    "ship_to":{"city":"Colombo"}}',4) as response;
select is((select count(*) from api.sales_orders
  where source_quotation_id='fa045000-0000-0000-0000-000000000001'),1::bigint,
  'accepted quotation creates exactly one traced order');
create temporary table fulfillment_input as select jsonb_build_object(
  'id',response#>>'{entity,id}','promised_date','2099-10-01',
  'warehouse_id','55000000-0000-0000-0000-000000000001','ship_to',jsonb_build_object('city','Galle')) as payload
  from conversion;
create temporary table fulfillment as select pg_temp.order_command('fulfillment',
  (select payload from fulfillment_input),1,'fa049000-0000-0000-0000-000000000001') as response;
select ok((select response#>>'{entity,ship_to,city}'='Galle'
  and response#>>'{entity,promised_date}'='2099-10-01'
  and response#>>'{entity,grand_total}'='100.000000' from fulfillment),
  'converted fulfillment edits preserve exact source pricing');
select is((select response#>'{entity,lines}' from fulfillment),
  (select response#>'{entity,lines}' from conversion),
  'converted fulfillment does not replace source line identities or snapshots');
select is(pg_temp.order_command('fulfillment',(select payload from fulfillment_input),
  1,'fa049000-0000-0000-0000-000000000001'),
  (select response from fulfillment),'fulfillment retries return the original response');
select throws_ok($q$select pg_temp.order_command('fulfillment',
  (select payload from fulfillment_input),1)$q$,
  '40001','VERSION_CONFLICT','stale fulfillment edits fail explicitly');
select throws_ok($q$select pg_temp.order_command('fulfillment',
  (select payload || '{"grand_total":"1.000000"}'::jsonb from fulfillment_input),2)$q$,
  '22023','FULFILLMENT_FIELDS_ONLY','fulfillment command rejects commercial field smuggling');

reset role;
create function pg_temp.ac304_reject_outbox() returns trigger language plpgsql as $q$
begin
  raise exception 'AC304_INJECTED_OUTBOX_FAILURE';
end;
$q$;
create trigger ac304_reject_outbox before insert on core.outbox_events
for each row execute function pg_temp.ac304_reject_outbox();
set local role authenticated;
select throws_ok($q$select pg_temp.order_command('fulfillment',
  (select payload || '{"ship_to":{"city":"Should roll back"}}'::jsonb from fulfillment_input),2)$q$,
  'P0001','AC304_INJECTED_OUTBOX_FAILURE','late fulfillment outbox failure is reported');
select ok((select ship_to->>'city'='Galle' and version=2
  from api.sales_order_details where source_quotation_id='fa045000-0000-0000-0000-000000000001'),
  'late failure rolls back fulfillment fields and version');
reset role;
drop trigger ac304_reject_outbox on core.outbox_events;
insert into core.role_permissions(tenant_id,role_id,permission_code) values
 ('25000000-0000-0000-0000-000000000001','75000000-0000-0000-0000-000000000002','sales.orders.view');
select set_config('request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select is((select count(*) from api.sales_order_details),2::bigint,
  'view-only order users can read coherent details');
select throws_ok($q$select api.get_sales_order_credit_preview(
  '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000001','fa040000-0000-0000-0000-000000000001')$q$,
  '42501',null,'credit preview requires order management capability');
select set_config('request.jwt.claims',
  '{"sub":"15000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}',true);
select is((select count(*) from api.sales_order_details),0::bigint,
  'other-tenant users see no order details');
reset role;
select * from finish(true);
select 'wave3_order_workspace' as suite, _get('curr_test') as passed;
rollback;
