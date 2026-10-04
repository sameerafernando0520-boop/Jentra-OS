-- Setup is inserted before root's project fixtures. Reuse the existing payroll
-- fiscal period and journal sequence; never create overlapping period evidence.
reset role;select pg_temp.wactor('creator');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.finance',true) on conflict(plan_code,entitlement_code) do update set enabled=true;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x
cross join core.permissions p where p.module in('sales','workflow','finance') on conflict do nothing;
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by)
values(pg_temp.wid('pb.customer'),pg_temp.wid('tenant'),'PB-CUSTOMER','Synthetic billed project customer',
 'Synthetic billed project customer','customer',1000000,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.wid('pb.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),'PB-'||upper(x),'Synthetic billed '||x,
 case when x='receivable_control' then 'asset' when x='revenue' then 'revenue' else 'expense' end,
 case when x='revenue' then 'credit' else 'debit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
from unnest(array['receivable_control','revenue','rounding']) x;
insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),x,pg_temp.wid('pb.'||x),pg_temp.wid('creator'),pg_temp.wid('creator')
from unnest(array['receivable_control','rounding']) x;
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.wid('pb.uom'),pg_temp.wid('tenant'),'PB-UNIT','Whole billed project source','ea','quantity',6,
 pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,revenue_account_id,created_by,updated_by)
values(pg_temp.wid('pb.product'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'PB-SERVICE','Synthetic billed project service',
 'service',pg_temp.wid('pb.uom'),'none',pg_temp.wid('pb.revenue'),pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),x,'PB-'||x||'-',pg_temp.wid('creator'),pg_temp.wid('creator')
from unnest(array['sales_invoice','sales_return']) x;
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
select pg_temp.wid('pb.workflow.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),x,'Synthetic independent billed '||x,'active',
 '{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["approved","posted"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","cancelled"]],"requires_approval":true,"separate_poster":true}',
 pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['sales_invoice','sales_return']) x;
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
select pg_temp.wid('pb.step.'||x),pg_temp.wid('tenant'),pg_temp.wid('pb.workflow.'||x),pg_temp.wid('reviewer.role'),1,
 pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['sales_invoice','sales_return']) x;

-- BILLING_TEST_BODY
reset role;
create temporary table project_billed_samples(name text primary key,body jsonb);
grant select,insert on project_billed_samples to authenticated;
create function pg_temp.pbc(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.projects_finance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('pb.command.'||key),pg_temp.wid('pb.command.'||key),now(),p,v) $$;
create function pg_temp.pb_prepare(key text) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action','billing_prepare','id',pg_temp.wid('pb.batch.'||key),'project_id',pg_temp.wid('direct.project'),
 'invoice_id',pg_temp.wid('pb.invoice.'||key),'document_date',(now() at time zone 'UTC')::date,
 'due_date',(now() at time zone 'UTC')::date,'exchange_rate_id',null,'reason','Synthetic exact original project billing',
 'units',jsonb_build_array(jsonb_build_object('unit_id',u.id,'source_version',u.source_version,'source_digest',u.source_digest,
 'product_id',pg_temp.wid('pb.product'),'product_version',1,'tax_definition_id',null,'tax_version',null,'description','Synthetic whole direct project time')))
 from projects.billable_units u join projects.time_entries x on x.current_revision_id=u.source_id
 where x.id=pg_temp.wid('direct.time') and u.status='available' $$;
create function pg_temp.pb_action(a text,key text,v bigint) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('pb.batch.'||key),'project_id',pg_temp.wid('direct.project'),
 'invoice_version',v,'reason','Synthetic governed installed sales action') $$;
create function pg_temp.pb_credit(key text) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('id',pg_temp.wid('pb.credit.'||key),'customer_id',pg_temp.wid('pb.customer'),
 'document_date',(now() at time zone 'UTC')::date,'currency_code','LKR','reason','Synthetic original direct project credit',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.wid('pb.credit.line.'||key),'sales_invoice_line_id',l.id,
 'product_id',l.product_id,'base_quantity','1.000000','quantity','1.000000','unit_id',l.unit_id,
 'conversion_numerator','1','conversion_denominator','1','disposition','no_restock')))
 from sales.sales_invoice_lines l where document_id=pg_temp.wid('pb.invoice.'||key) $$;
create function pg_temp.pb_invoice(key text) returns void language plpgsql as $$begin
 perform pg_temp.wactor('creator');perform pg_temp.pbc(pg_temp.pb_prepare(key),0,key||'.prepare');
 perform pg_temp.pbc(pg_temp.pb_action('billing_submit',key,1),1,key||'.submit');
 perform pg_temp.wactor('reviewer');perform pg_temp.pbc(pg_temp.pb_action('billing_decide',key,2)||'{"decision":"approved"}',2,key||'.decide');
 perform pg_temp.pbc(pg_temp.pb_action('billing_post',key,3),3,key||'.post');
end $$;
create function pg_temp.pb_post_credit(key text) returns void language plpgsql as $$begin
 perform pg_temp.wactor('creator');
 perform api.upsert_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),pg_temp.pb_credit(key),null);
 perform api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),
 jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('pb.credit.'||key),'action','submit','reason','Synthetic original credit submit'),1);
 perform pg_temp.wactor('reviewer');
 perform api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),
 jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('pb.credit.'||key),'action',null,'decision','approved','note','Synthetic independent original credit'),2);
 perform api.post_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('id',pg_temp.wid('pb.credit.'||key)),3);
end $$;
create function pg_temp.pb_correction(key text,credit text default null) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_set(jsonb_set(pg_temp.direct_project_correction(),'{id}',to_jsonb(pg_temp.wid(key))),'{replacements,0,impact,billing_credit_line_ids}',
 case when credit is null then '[]'::jsonb else jsonb_build_array(pg_temp.wid('pb.credit.line.'||credit)) end)
 ||jsonb_build_object('posting_date',pg_temp.wdate()+24) $$;
create function pg_temp.pb_reverse(key text,credit text default null) returns jsonb language sql security definer set search_path='' as $$
 select pg_temp.correction_action('reverse',key)||jsonb_build_object('posting_date',pg_temp.wdate()+25,
 'current_billing_impacts',jsonb_build_array(jsonb_build_object('seal_id',s.seal_id,
 'source_revision_id',state.body->>'operational_source_id','expected_source_version',(state.body->>'operational_source_version')::bigint,
 'billing_credit_line_ids',case when credit is null then '[]'::jsonb else jsonb_build_array(pg_temp.wid('pb.credit.line.'||credit)) end,
 'allocation_credits','[]'::jsonb)))
 from people_payroll.correction_sources s cross join lateral(select people_payroll.correction_source_state(s.seal_id) body) state
 where s.correction_id=pg_temp.wid(key) $$;

insert into project_billed_samples values('v3',jsonb_build_object('revision_id',(select current_revision_id from projects.time_entries where id=pg_temp.wid('direct.time'))));
set local role authenticated;select pg_temp.pb_invoice('original');reset role;
select is((select grand_total from sales.sales_invoices where id=pg_temp.wid('pb.invoice.original')),54::numeric,'AC-412 actual posted direct source invoice has exact original revenue');
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.pb_correction('pb.correction'),0,'pb.missing.credit')$q$,'55000','PROJECT_POSTED_ORIGINAL_CREDIT_REQUIRED','AC-412 billed geometry cannot supersede without posted original credit');
select pg_temp.pb_post_credit('original');reset role;
select is((select grand_total from sales.sales_returns where id=pg_temp.wid('pb.credit.original')),54::numeric,'AC-412 actual independent original credit preserves exact full line basis');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.pb_correction('pb.correction','original'),0,'pb.correction.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','pb.correction'),1,'pb.correction.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','pb.correction'),2,'pb.correction.post');reset role;
select is((select amount from projects.billable_units where project_id=pg_temp.wid('direct.project') and status='available'),27::numeric,'AC-412 billed correction appends exact independent replacement unit');
select is((select status from projects.billable_units where source_id=((select body->>'revision_id' from project_billed_samples where name='v3'))::uuid),'billed','AC-412 credited original source remains consumed');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='projects.billing.manage';
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','pb.correction'),2,'pb.correction.post')$q$,'42501',null,'AC-415 billed correction confirmed replay rechecks current billing permission');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'projects.billing.manage');
update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback' and entitlement_code='module.finance';
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','pb.correction'),2,'pb.correction.post')$q$,'42501','PROJECT_FINANCE_ENTITLEMENT_REQUIRED','AC-415 billed correction confirmed replay rechecks current finance entitlement');
reset role;update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback' and entitlement_code='module.finance';
select pg_temp.wactor('reviewer');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.pb_reverse('pb.correction','original'),3,'pb.reverse.wrong.original')$q$,'22023','PROJECT_PAYROLL_CREDIT_LINEAGE_INVALID','AC-412 reverse cannot reuse original credit against current unbilled replacement');
select pg_temp.cc(pg_temp.correction_action('reverse','pb.correction')||jsonb_build_object('posting_date',pg_temp.wdate()+25),3,'pb.correction.reverse');reset role;
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('direct.project') and status='available'),1,'AC-412 default empty current credits reverse an unbilled replacement into exactly one fresh unit');
select is((select amount from projects.billable_units where project_id=pg_temp.wid('direct.project') and status='available'),54::numeric,'AC-412 reversal restores commercial basis without reviving original source');

-- A newly billed replacement requires independently posted current credits.
set local role authenticated;select pg_temp.pb_invoice('second.original');select pg_temp.pb_post_credit('second.original');reset role;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.pb_correction('pb.second','second.original'),0,'pb.second.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','pb.second'),1,'pb.second.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','pb.second'),2,'pb.second.post');
select pg_temp.pb_invoice('replacement');reset role;
select is((select grand_total from sales.sales_invoices where id=pg_temp.wid('pb.invoice.replacement')),27::numeric,'AC-412 corrected source is billed once at its own exact amount');
select pg_temp.wactor('reviewer');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.pb_reverse('pb.second'),3,'pb.second.reverse.missing')$q$,'55000','PROJECT_POSTED_ORIGINAL_CREDIT_REQUIRED','AC-412 newly billed replacement blocks reverse without current posted credit');
select throws_ok($q$select pg_temp.cc(pg_temp.pb_reverse('pb.second','second.original'),3,'pb.second.reverse.old')$q$,'55000','PROJECT_POSTED_ORIGINAL_CREDIT_REQUIRED','AC-412 old original credit cannot cover newly billed replacement');
select throws_ok($q$select pg_temp.cc(jsonb_set(pg_temp.pb_reverse('pb.second'),'{current_billing_impacts,0,expected_source_version}','1'),3,'pb.second.reverse.stale')$q$,'40001','PAYROLL_CORRECTION_SOURCE_CHANGED','AC-415 reverse binds exact current source version before credit proof');
select pg_temp.pb_post_credit('replacement');
select pg_temp.cc(pg_temp.pb_reverse('pb.second','replacement'),3,'pb.second.reverse');reset role;
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('direct.project') and status='available'),1,'AC-412 fresh current credit permits exactly one new restoration unit');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('direct.project') and status='billed'),3,'AC-412 all three historical invoice sources stay consumed after credit and reversal');
select is((select payable_seconds from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='project' and active),3600::bigint,'AC-411 current direct payroll ownership retains exact restored geometry');
select is((select inputs->>'paid_seconds' from people_payroll.employee_calculations where run_id=pg_temp.wid('direct.run')),'3600','AC-411 original posted calculation remains frozen after billed correction roundtrips');
select is((select count(*)::integer from finance.fiscal_periods where tenant_id=pg_temp.wid('tenant') and legal_entity_id=pg_temp.wid('entity')),1,'AC-412 installed sales shares original synthetic payroll fiscal period');
select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('direct.project'),clock_timestamp(),pg_temp.wdate()+30)->>'posted_revenue')::numeric,135::numeric,'AC-412 posted original and replacement revenue retains immutable invoice lineage');
select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('direct.project'),clock_timestamp(),pg_temp.wdate()+30)->>'posted_credits')::numeric,135::numeric,'AC-412 actual original and replacement credits fully reconcile revenue');
