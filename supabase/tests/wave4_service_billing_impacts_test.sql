-- Real installed sales posting and independently posted original credit govern billed service revisions.
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.projects',true) on conflict do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p where p.module in('projects','sales','workflow','finance') on conflict do nothing;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.wid('sb.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),'SB-'||upper(x),'Synthetic service '||x,
 case when x='revenue' then 'revenue' when x='receivable_control' then 'asset' else 'expense' end,
 case when x='revenue' then 'credit' else 'debit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['revenue','receivable_control','rounding']) x;
insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),x,pg_temp.wid('sb.'||x),pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['receivable_control','rounding']) x on conflict(tenant_id,legal_entity_id,purpose) do nothing;
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.wid('sb.unit'),pg_temp.wid('tenant'),'SB-UNIT','Synthetic whole service unit','ea','quantity',6,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,revenue_account_id,created_by,updated_by)
values(pg_temp.wid('sb.product'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'SB-SERVICE','Synthetic original service revenue','service',pg_temp.wid('sb.unit'),'none',pg_temp.wid('sb.revenue'),pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),x,'SB-'||x||'-',pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['sales_invoice','sales_return','journal_entry']) x on conflict(tenant_id,legal_entity_id,branch_id,document_type) do nothing;
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
select pg_temp.wid('sb.workflow.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),x,'Synthetic independent service invoice/credit','active',
 '{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["approved","posted"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","cancelled"]],"requires_approval":true,"separate_poster":true}'::jsonb,
 pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['sales_invoice','sales_return']) x;
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
select pg_temp.wid('sb.step.'||x),pg_temp.wid('tenant'),pg_temp.wid('sb.workflow.'||x),pg_temp.wid('reviewer.role'),1,pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['sales_invoice','sales_return']) x;
create function pg_temp.sbf(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.projects_finance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
select pg_temp.wactor('creator');set local role authenticated;
select api.projects_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('sb.project.create'),pg_temp.wid('sb.project.create'),now(),
 jsonb_build_object('action','create','id',pg_temp.wid('sb.project'),'code','SB-PROJECT','name','Synthetic billed service project','manager_id',pg_temp.wid('manager'),
 'customer_id',pg_temp.wid('customer'),'currency_code','LKR','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'reason','Synthetic commercial provenance'),0);
select pg_temp.sic(jsonb_build_object('action','complete','id',pg_temp.wid('sd.order'),'observed_utc',pg_temp.sidu(600),'resolution','Synthetic direct repair',
 'customer_confirmed',true,'reason','Synthetic completion'),3,'sb.complete');
reset role;
insert into service_impact_samples values('billing_source',service.billing_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('sd.labor')));
set local role authenticated;
select pg_temp.sbf(jsonb_build_object('action','service_source','id',pg_temp.wid('sb.source'),'project_id',pg_temp.wid('sb.project'),
 'service_source_id',pg_temp.wid('sd.labor'),'source_version',(select (body->>'source_version')::bigint from service_impact_samples where name='billing_source'),
 'source_digest',(select body->>'digest' from service_impact_samples where name='billing_source'),'reason','Synthetic actual service source'),0,'sb.source.import');
reset role;
create function pg_temp.sb_prepare() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action','billing_prepare','id',pg_temp.wid('sb.batch'),'project_id',pg_temp.wid('sb.project'),'invoice_id',pg_temp.wid('sb.invoice'),
 'document_date',(now() at time zone 'UTC')::date,'due_date',(now() at time zone 'UTC')::date,'exchange_rate_id',null,'units',
 jsonb_build_array(jsonb_build_object('unit_id',u.id,'source_version',u.source_version,'source_digest',u.source_digest,'product_id',pg_temp.wid('sb.product'),
 'product_version',1,'tax_definition_id',null,'tax_version',null,'description','Synthetic original approved service')),'reason','Synthetic source reservation')
 from projects.billable_units u where u.id=pg_temp.wid('sb.source') $$;
create function pg_temp.sb_action(action text,invoice_version bigint) returns jsonb language sql as $$
 select jsonb_build_object('action',action,'id',pg_temp.wid('sb.batch'),'project_id',pg_temp.wid('sb.project'),'invoice_version',invoice_version,'reason','Synthetic installed sales workflow') $$;
set local role authenticated;select pg_temp.sbf(pg_temp.sb_prepare(),0,'sb.prepare');reset role;
select throws_ok($q$select service.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('sd.labor'),
 (select current_revision_id from service.labor where id=pg_temp.wid('sd.labor')),jsonb_build_object('correction_id',pg_temp.wid('sb.correction')),'validate')$q$,'55000','PROJECT_BILLING_IMPACT_REQUIRED','reserved service source blocks correction');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.sbf(pg_temp.sb_action('billing_submit',1),1,'sb.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.sbf(pg_temp.sb_action('billing_decide',2)||'{"decision":"approved"}',2,'sb.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.sbf(pg_temp.sb_action('billing_post',3),3,'sb.post');
reset role;
select ok((select billing_consumption_id=pg_temp.wid('sb.batch') from service.labor where id=pg_temp.wid('sd.labor')),'actual invoice posting consumes current service source');
select throws_ok($q$select service.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('sd.labor'),
 (select current_revision_id from service.labor where id=pg_temp.wid('sd.labor')),jsonb_build_object('correction_id',pg_temp.wid('sb.correction')),'validate')$q$,'55000','PROJECT_POSTED_ORIGINAL_CREDIT_REQUIRED','consumed service requires actual original posted credit');
create function pg_temp.sb_credit() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('id',pg_temp.wid('sb.credit'),'customer_id',pg_temp.wid('customer'),'document_date',(now() at time zone 'UTC')::date,'currency_code','LKR',
 'reason','Synthetic original service credit','lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.wid('sb.credit.line'),'sales_invoice_line_id',l.id,
 'product_id',l.product_id,'base_quantity','1.000000','quantity','1.000000','unit_id',l.unit_id,'conversion_numerator','1','conversion_denominator','1','disposition','no_restock')))
 from sales.sales_invoice_lines l where document_id=pg_temp.wid('sb.invoice') $$;
select pg_temp.wactor('creator');set local role authenticated;
select api.upsert_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),pg_temp.sb_credit(),null);
select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),
 jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('sb.credit'),'action','submit','reason','Synthetic credit submit'),1);
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),
 jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('sb.credit'),'action',null,'decision','approved','note','Independent original credit'),2);
reset role;select pg_temp.wactor('creator');set local role authenticated;
select api.post_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('id',pg_temp.wid('sb.credit')),3);
reset role;
create function pg_temp.sb_correction() returns jsonb language sql security definer set search_path='' as $$
 select pg_temp.sd_correction()||jsonb_build_object('id',pg_temp.wid('sb.correction'),'replacements',jsonb_build_array(
 (pg_temp.sd_correction()->'replacements'->0)||jsonb_build_object('impact',
 (pg_temp.sd_correction()->'replacements'->0->'impact')||jsonb_build_object('billing_credit_line_ids',jsonb_build_array(pg_temp.wid('sb.credit.line')))))) $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.sb_correction(),0,'sb.correction.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','sb.correction'),1,'sb.correction.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','sb.correction'),2,'sb.correction.post');
reset role;
select is((select status from projects.billable_units where id=pg_temp.wid('sb.source')),'billed','credited historical service unit remains consumed');
select is(service.snapshot('labor',pg_temp.wid('sd.labor'))->>'seconds','2700','credited consumed service now has truthful linked replacement');
select ok((select billing_consumption_id is null from service.labor where id=pg_temp.wid('sd.labor')),'replacement service source awaits its own separate invoice');
select is((select count(*)::integer from sales.sales_returns where id=pg_temp.wid('sb.credit') and status='posted'),1,'original sales credit retained as posted evidence');
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','sb.correction'),3,'sb.correction.reverse');
reset role;
select is(service.snapshot('labor',pg_temp.wid('sd.labor'))->>'seconds','3600','billed source operational reverse restores basis as new revision');
select is((select status from projects.billable_units where id=pg_temp.wid('sb.source')),'billed','operational reverse cannot revive original consumed unit');
