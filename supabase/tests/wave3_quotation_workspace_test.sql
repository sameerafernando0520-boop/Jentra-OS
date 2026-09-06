begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(43);

-- AC-303 / FR-321: reuse the synthetic commerce fixtures, never production data.
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
    "quotation_date":"2026-09-05","valid_until":"2026-10-05",
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

create function pg_temp.quote_transition(
  p_action text, p_reason text default '', p_version bigint default 1,
  p_key uuid default gen_random_uuid(),
  p_id uuid default 'f5000000-0000-0000-0000-000000000001'
) returns jsonb language sql set search_path='' as $$
  select api.transition_operational_document(
    '25000000-0000-0000-0000-000000000001',
    '35000000-0000-0000-0000-000000000001',
    '45000000-0000-0000-0000-000000000001', p_key, p_key,
    '2026-09-06T00:00:00Z',
    jsonb_build_object('document_type','sales_quotation',
      'document_id',p_id,
      'action',p_action,'reason',p_reason), p_version);
$$;


-- A test-local exception sandbox rolls back even unexpected successful commands.
-- TAP assertions live outside it, so their failure counters are never rolled back.
create function pg_temp.command_error(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  raise exception using errcode='Z0001',message='UNEXPECTED_SUCCESS';
exception when others then return sqlstate||':'||sqlerrm;
end;
$$;

reset role;
update workflow.workflow_definitions set status='inactive'
where id='85000000-0000-0000-0000-000000000001';
set local role authenticated;
select is(pg_temp.command_error($$select pg_temp.quote_transition('submit')$$),
 '55000:WORKFLOW_CONFIGURATION_ERROR','missing active workflow fails closed');
reset role;
update workflow.workflow_definitions set status='active'
where id='85000000-0000-0000-0000-000000000001';
update workflow.approval_matrix_steps set maximum_amount=1
where id='86000000-0000-0000-0000-000000000001';
set local role authenticated;
select is(pg_temp.command_error($$select pg_temp.quote_transition('submit')$$),
 '55000:WORKFLOW_CONFIGURATION_ERROR','an unmatched amount cannot bypass approval');
reset role;
update workflow.approval_matrix_steps set maximum_amount=1000
where id='86000000-0000-0000-0000-000000000001';
set local role authenticated;
select lives_ok($$select pg_temp.quote_transition('submit')$$,'configured quotation submits');
select throws_ok($$select pg_temp.quote_transition('recall','',2)$$,
 '22023','Recall reason is required.','recall requires an attributable reason');
create temporary table recalled as select pg_temp.quote_transition('recall',
 'Correct the delivery terms',2,'f1000000-0000-0000-0000-000000000090') as response;
select ok((select response#>>'{entity,status}'='draft' and response#>>'{entity,current_revision}'='2'
 from recalled),'recall returns an editable new revision');
select is((select count(*) from api.sales_quotation_lines
 where quotation_id='f5000000-0000-0000-0000-000000000001'),4::bigint,
 'recall retains published lines and copies new draft lines');
select is((select snapshot#>>'{lines,0,tax_amount}' from api.sales_quotation_revisions
 where quotation_id='f5000000-0000-0000-0000-000000000001' and revision_number=1),
 '24.300000','published tax snapshots survive recall');
select is(pg_temp.quote_transition('recall','Correct the delivery terms',2,
 'f1000000-0000-0000-0000-000000000090'),(select response from recalled),
 'recall replay returns the original receipt');
select throws_ok($$select pg_temp.quote_transition('recall','stale',2)$$,
 '40001','VERSION_CONFLICT','stale recall cannot change the document');
select lives_ok($$select pg_temp.quote_transition('submit','Second revision',3)$$,
 'the new revision can be resubmitted');
select ok((select count(*)=2 and count(distinct document_number)=1
 from api.sales_quotation_revisions where quotation_id='f5000000-0000-0000-0000-000000000001'),
 'resubmission preserves both snapshots and the original permanent number');

-- A matrix edit after submission must not silently reroute the pinned decision.
reset role;
update workflow.approval_matrix_steps set role_id='75000000-0000-0000-0000-000000000001'
where id='86000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims',
 '{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select lives_ok($$select api.decide_operational_approval(
 '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
 '45000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000091',
 'f2000000-0000-0000-0000-000000000091','2026-09-06T00:00:00Z',
 '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000001",
 "decision":"approved","note":"Pinned matrix approval"}',4)$$,
 'approval consumes the submitted matrix snapshot, not a later configuration');
reset role;
select set_config('request.jwt.claims',
 '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select ok((select jsonb_typeof(lines->0->'unit_price')='string'
 and lines->0->>'unit_price'='100.000000' and status='approved'
 from api.sales_quotation_details where id='f5000000-0000-0000-0000-000000000001'),
 'one scoped view returns coherent header and exact current line details');
select ok((select revision_number=2 and decision='approved' and amount='289.800000'
 from api.sales_quotation_decisions where quotation_id='f5000000-0000-0000-0000-000000000001'),
 'decision history identifies the exact submitted revision and decimal amount');
select throws_ok($$select pg_temp.quote_transition('expire','Too early',5)$$,
 '55000','QUOTATION_NOT_EXPIRABLE','a valid quotation cannot expire early');
reset role;
select throws_ok($$update sales.quotation_lines set description='rewrite'
 where id='f5100000-0000-0000-0000-000000000001'$$,
 '55000','QUOTATION_REVISION_IMMUTABLE','trusted callers cannot rewrite a published line');

-- Readers do not need approval-management rights to inspect quotation decisions.
insert into core.roles(id,tenant_id,code,name) values (
 '75000000-0000-0000-0000-000000000003','25000000-0000-0000-0000-000000000001',
 'quote_viewer','Quotation viewer');
insert into core.role_permissions(tenant_id,role_id,permission_code) values (
 '25000000-0000-0000-0000-000000000001','75000000-0000-0000-0000-000000000003',
 'sales.quotations.view');
-- A fresh reader has never submitted or decided this quotation.
insert into auth.users(id,aud,role,email) values
 ('15000000-0000-0000-0000-000000000003','authenticated','authenticated','viewer@jentra.test');
insert into core.memberships(id,tenant_id,user_id,status,joined_at) values
 ('65000000-0000-0000-0000-000000000003','25000000-0000-0000-0000-000000000001',
 '15000000-0000-0000-0000-000000000003','active',now());
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by) values
 ('25000000-0000-0000-0000-000000000001','65000000-0000-0000-0000-000000000003',
 '75000000-0000-0000-0000-000000000003','35000000-0000-0000-0000-000000000001',
 '45000000-0000-0000-0000-000000000001','15000000-0000-0000-0000-000000000001');
select set_config('request.jwt.claims',
 '{"sub":"15000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select is((select count(*) from api.sales_quotation_decisions),1::bigint,
 'quotation-only viewer can read decision history');
select throws_ok($$select pg_temp.quote_transition('cancel','Viewer cannot write',5)$$,
'42501',null,'quotation-only viewer cannot mutate the quotation');
reset role;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
 ('45000000-0000-0000-0000-000000000002','25000000-0000-0000-0000-000000000001',
 '35000000-0000-0000-0000-000000000001','Other branch','OTHERBR','15000000-0000-0000-0000-000000000001');
update core.role_assignments set branch_id='45000000-0000-0000-0000-000000000002'
where membership_id='65000000-0000-0000-0000-000000000003';
set local role authenticated;
select ok((select count(*)=0 from api.sales_quotation_details)
 and (select count(*)=0 from api.sales_quotation_decisions),
 'a same-tenant reader in another branch sees no quotation details or decisions');
reset role;
insert into core.legal_entities(id,tenant_id,name,code,currency_code,created_by) values
 ('35000000-0000-0000-0000-000000000002','25000000-0000-0000-0000-000000000001',
 'Other legal entity','OTHERLE','LKR','15000000-0000-0000-0000-000000000001');
update core.role_assignments set legal_entity_id='35000000-0000-0000-0000-000000000002',branch_id=null
where membership_id='65000000-0000-0000-0000-000000000003';
set local role authenticated;
select ok((select count(*)=0 from api.sales_quotation_details)
 and (select count(*)=0 from api.sales_quotation_decisions),
 'a same-tenant reader in another legal entity sees no quotation details or decisions');
reset role;
select set_config('request.jwt.claims',
 '{"sub":"15000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select ok((select count(*)=0 from api.sales_quotation_details)
 and (select count(*)=0 from api.sales_quotation_decisions),
 'foreign tenant sees neither details nor decisions');

reset role;
select set_config('request.jwt.claims',
 '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',true);
-- Inject a late transactional failure; no recalled header/line/receipt may survive.
create function pg_temp.reject_quote_outbox() returns trigger language plpgsql as $$
begin raise exception 'AC303_INJECTED_OUTBOX_FAILURE'; end;
$$;
create trigger ac303_reject_outbox before insert on core.outbox_events
for each row execute function pg_temp.reject_quote_outbox();
set local role authenticated;
select throws_ok($$select pg_temp.quote_transition('recall','Fault injection',5,
 'f1000000-0000-0000-0000-000000000092')$$,
 'P0001','AC303_INJECTED_OUTBOX_FAILURE','late recall failure is reported');
select ok((select status='approved' and current_revision=2 and version=5
 from api.sales_quotations where id='f5000000-0000-0000-0000-000000000001')
 and (select count(*)=4 from api.sales_quotation_lines
 where quotation_id='f5000000-0000-0000-0000-000000000001'),
 'late failure rolls back the recalled header and copied lines');

reset role;
drop trigger ac303_reject_outbox on core.outbox_events;
set local role authenticated;
select ok((select snapshot#>>'{workflow_snapshot,steps,0,role_id}'=
 '75000000-0000-0000-0000-000000000002'
 from api.sales_quotation_revisions where quotation_id='f5000000-0000-0000-0000-000000000001'
 and revision_number=2),'published revision retains its original approval policy');

create function pg_temp.quote_revision(p_version bigint,p_revision boolean default true,
 p_key uuid default gen_random_uuid()) returns jsonb
language sql set search_path='' as $$
 select api.upsert_sales_quotation(
 '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
 '45000000-0000-0000-0000-000000000001',p_key,p_key,'2026-09-06T00:00:00Z',
 to_jsonb(q)||jsonb_build_object('create_revision',p_revision,'revision_reason','Revise terms',
 'header_discount_amount',null,'lines',(select jsonb_agg(jsonb_strip_nulls(l||jsonb_build_object(
 'line_id',l->>'id','discount_amount',case when l->>'discount_percent' is null
 then l->'line_discount_amount' else null end))) from jsonb_array_elements(q.lines) l)),p_version)
 from api.sales_quotation_details q where id='f5000000-0000-0000-0000-000000000001';
$$;
select lives_ok($$select pg_temp.quote_revision(5)$$,
 'revision of approved content allocates new line IDs without rewriting published lines');
reset role;
select ok((select current_revision=3 and workflow_snapshot is null
 from sales.quotations where id='f5000000-0000-0000-0000-000000000001'),
 'new draft clears the prior submission policy until it is resubmitted');

update finance.tax_definitions set rate=20 where id='c5000000-0000-0000-0000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.quote_transition('submit','Changed tax',6)$$,
 '55000','QUOTATION_RECALCULATION_REQUIRED','changed governed tax requires an explicit recalculation');
select lives_ok($$select pg_temp.quote_revision(6,false)$$,'saving the draft recalculates governed tax');
select is((select tax_total from api.sales_quotations where id='f5000000-0000-0000-0000-000000000001'),
 '45.900000','recalculation keeps inclusive and exclusive tax exact');
reset role;
update workflow.approval_matrix_steps set role_id='75000000-0000-0000-0000-000000000002'
where id='86000000-0000-0000-0000-000000000001';
set local role authenticated;
select lives_ok($$select pg_temp.quote_transition('submit','Repriced revision',7)$$,
 'recalculated revision can submit under the current policy');
reset role;
select set_config('request.jwt.claims',
 '{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select lives_ok($$select api.decide_operational_approval(
 '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
 '45000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000094',
 'f2000000-0000-0000-0000-000000000094','2026-09-06T00:00:00Z',
 '{"document_type":"sales_quotation","document_id":"f5000000-0000-0000-0000-000000000001",
 "decision":"approved","note":"Repriced approval"}',8)$$,'repriced revision receives its own approval decision');
reset role;
-- Fixture-only clock passage: expiry checks must ignore the older client date.
update sales.quotations set valid_until=(clock_timestamp() at time zone 'UTC')::date-1
where id='f5000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims',
 '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select throws_ok($$select pg_temp.quote_transition('accept','Backdated acceptance',10)$$,
 '55000','QUOTATION_EXPIRED','an expired unrevised quote cannot be accepted using an older client date');
select lives_ok($$select pg_temp.quote_transition('expire','Validity elapsed',10)$$,
 'configured expiry uses server time');
select is((select count(*) from api.sales_quotation_decisions),2::bigint,
 'both approval decisions remain readable after revisions and expiry');
reset role;
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
 where oid in ('sales.quotations'::regclass,'sales.quotation_lines'::regclass,
 'sales.quotation_revisions'::regclass,'workflow.approval_requests'::regclass,
 'workflow.approval_decisions'::regclass)), 'all quotation and decision tables retain forced RLS');
select ok(not has_table_privilege('anon','api.sales_quotation_details','SELECT')
 and not has_table_privilege('authenticated','sales.quotations','INSERT')
 and not has_function_privilege('authenticated','sales.validate_quotation_submission(sales.quotations)','EXECUTE')
 and not has_function_privilege('anon','api.upsert_sales_quotation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),
 'anonymous, direct-write and private-helper privileges remain revoked');
select ok((select bool_and(reloptions @> array['security_invoker=true']) from pg_class
 where oid in ('api.sales_quotation_details'::regclass,'api.sales_quotation_decisions'::regclass)),
 'both new read views execute with caller RLS');
insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,
 target_currency_code,rate,effective_date,created_by,updated_by) values
 ('d6000000-0000-0000-0000-000000000001','25000000-0000-0000-0000-000000000001',
 '35000000-0000-0000-0000-000000000001','USD','LKR',300.1234567890,'2026-09-05',
 '15000000-0000-0000-0000-000000000001','15000000-0000-0000-0000-000000000001');
set local role authenticated;
create temporary table fx_quote as select api.upsert_sales_quotation(
 '25000000-0000-0000-0000-000000000001','35000000-0000-0000-0000-000000000001',
 '45000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000095',
 'f2000000-0000-0000-0000-000000000095','2026-09-06T00:00:00Z',
 to_jsonb(q)||jsonb_build_object('id','f5000000-0000-0000-0000-000000000098',
 'valid_until','2099-12-31','currency_code','USD','exchange_rate','300.1234567890',
 'exchange_rate_id','d6000000-0000-0000-0000-000000000001','create_revision',false,
 'header_discount_amount',null,'lines',(select jsonb_agg(jsonb_strip_nulls(l||jsonb_build_object(
 'line_id',gen_random_uuid(),'discount_amount',case when l->>'discount_percent' is null
 then l->'line_discount_amount' else null end))) from jsonb_array_elements(q.lines) l)),null) as response
 from api.sales_quotation_details q where id='f5000000-0000-0000-0000-000000000001';
select ok((select response#>>'{entity,currency_code}'='USD'
 and response#>>'{entity,grand_total}'='297.900000'
 and response#>>'{entity,base_currency_code}'='LKR'
 and response#>>'{entity,base_total}'='89406.780000' from fx_quote),
 'USD quotation and LKR base total preserve the exact governed ten-place rate');
reset role;
update finance.exchange_rates set rate=301 where id='d6000000-0000-0000-0000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.quote_transition('submit','FX changed',1,
 p_id=>'f5000000-0000-0000-0000-000000000098')$$,'22023','QUOTATION_RATE_CHANGED',
 'submission refuses a changed exchange-rate snapshot');
reset role;
update finance.exchange_rates set rate=300.1234567890 where id='d6000000-0000-0000-0000-000000000001';
update crm.parties set status='inactive' where id='95000000-0000-0000-0000-000000000001';
set local role authenticated;
select throws_ok($$select pg_temp.quote_transition('submit','Inactive customer',1,
 p_id=>'f5000000-0000-0000-0000-000000000098')$$,'22023','QUOTATION_REFERENCE_INACTIVE',
 'submission rechecks active customer references');
reset role;
update crm.parties set status='active' where id='95000000-0000-0000-0000-000000000001';
update workflow.workflow_definitions set lifecycle=lifecycle||'{"requires_approval":false}'::jsonb
where id='85000000-0000-0000-0000-000000000001';
set local role authenticated;
select lives_ok($$select pg_temp.quote_transition('submit','Explicit non-approval workflow',1,
 p_id=>'f5000000-0000-0000-0000-000000000098')$$,
 'bypassing approval requires an explicit configured non-approval workflow');
select lives_ok($$select pg_temp.quote_transition('accept','Customer accepted',2,
 p_id=>'f5000000-0000-0000-0000-000000000098')$$,
 'a valid quotation can be accepted through its configured transition');
reset role;
select is((select count(*) from pg_policies where schemaname='workflow'
 and tablename in ('approval_requests','approval_decisions') and cmd='SELECT'),2::bigint,
 'quotation reads do not introduce overlapping permissive policies');
select * from finish(true);
rollback;
