-- Runs after the actual project candidate suite, inside the same outer rollback.
reset role;select pg_temp.wactor('creator');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.finance',true) on conflict(plan_code,entitlement_code) do update set enabled=true;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p where p.module in('sales','workflow','finance') on conflict do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p where p.code like 'projects.%' on conflict do nothing;
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by)
values(pg_temp.wid('pf.customer'),pg_temp.wid('tenant'),'PF-CUSTOMER','Synthetic customer','Synthetic customer','customer',1000000,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.wid('pf.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),'PF-'||upper(x),'Synthetic '||x,
 case when x in('receivable_control','bank','tax') then 'asset' when x='liability' then 'liability' when x='revenue' then 'revenue' else 'expense' end,
 case when x in('liability','revenue') then 'credit' else 'debit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
from unnest(array['expense','liability','tax','receivable_control','bank','revenue','rounding']) x;
insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),x,pg_temp.wid('pf.'||x),pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['receivable_control','rounding']) x;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.wid('pf.period'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Synthetic project period',pg_temp.wdate()-400,pg_temp.wdate()+400,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
values(pg_temp.wid('pf.bank'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'PF-BANK','Synthetic recorded bank','bank',pg_temp.wid('pf.bank'),'LKR',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.wid('pf.unit'),pg_temp.wid('tenant'),'PF-UNIT','Whole billing unit','ea','quantity',6,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,revenue_account_id,created_by,updated_by)
values(pg_temp.wid('pf.product'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'PF-SERVICE','Synthetic project service','service',pg_temp.wid('pf.unit'),'none',pg_temp.wid('pf.revenue'),pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),x,'PF-'||x||'-',pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['sales_invoice','sales_return','journal_entry']) x;
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.wid('pf.workflow'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'sales_invoice','Synthetic independent project invoice','active',
'{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["approved","posted"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","cancelled"]],"requires_approval":true,"separate_poster":true}',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.wid('pf.step'),pg_temp.wid('tenant'),pg_temp.wid('pf.workflow'),pg_temp.wid('reviewer.role'),1,pg_temp.wid('creator'),pg_temp.wid('creator'));
select pg_temp.pc(pg_temp.project_create('finance')||jsonb_build_object('customer_id',pg_temp.wid('pf.customer')),0,'pf.create');
select pg_temp.pc(jsonb_set(jsonb_set(pg_temp.project_plan('finance','finance-plan'),'{resources}','[]'::jsonb),'{tasks,0,planned_seconds}','0'::jsonb),1,'pf.plan');select pg_temp.wactor('reviewer');select pg_temp.pc(pg_temp.plan_action('approve_plan','finance','finance-plan'),2,'pf.approve');
create function pg_temp.pfc(p jsonb,v bigint,k text) returns jsonb language sql as $$
select api.projects_finance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.command.'||k),pg_temp.wid('pf.command.'||k),now(),p,v) $$;
create function pg_temp.pfe(k text default 'expense') returns jsonb language sql as $$
 select jsonb_build_object('action','expense_create','id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'employee_id',pg_temp.wid('employee'),'external_reference','PF-'||k,'service_date',pg_temp.wdate(),'purpose','Synthetic approved travel','evidence_reference','SYNTHETIC-PF-01','original_currency','LKR','original_precision',2,'net','0.03','tax','0','gross','0.03','tax_definition_id',null,'tax_version',null,'no_tax_reason','Synthetic no tax','exchange_rate_id',null,'exchange_rate_version',null,'expense_account_id',pg_temp.wid('pf.expense'),'tax_account_id',null,'liability_account_id',pg_temp.wid('pf.liability'),'billable',true,'bill_amount','0.05','allocations',jsonb_build_array(jsonb_build_object('task_id',pg_temp.wid('task'),'weight',1),jsonb_build_object('task_id',pg_temp.wid('task2'),'weight',1)),'reason','Synthetic expense preparation') $$;
create function pg_temp.pfa(a text,k text default 'expense') returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'posting_date',pg_temp.wdate(),'digest',(select digest from projects.expense_revisions where expense_id=pg_temp.wid('pf.'||k) order by version desc limit 1),'reason','Synthetic expense decision')-case when a in('expense_approve','expense_reject') then array['posting_date'] when a in('expense_post','expense_reverse') then array['digest'] else array['posting_date','digest'] end $$;
create temporary table project_finance_client_samples(label text primary key,body jsonb);grant insert,select on project_finance_client_samples to authenticated;
select ok(not has_table_privilege('authenticated','projects.expense_revisions','SELECT'),'finance private revisions have no direct reads');
select ok(not has_function_privilege('authenticated','projects.finance_access(uuid,uuid,uuid,text,boolean)','EXECUTE'),'finance helpers cannot bypass API');
select pg_temp.wactor('creator');set local role authenticated;
select is(pg_temp.pfc(pg_temp.pfe(),0,'create')->'entity'->>'status','draft','expense create preserves draft');
select is(pg_temp.pfc(pg_temp.pfe(),0,'create')->'entity'->>'version','1','exact expense replay');
select throws_ok($$select pg_temp.pfc(pg_temp.pfe()||'{"gross":"0.04"}',0,'create')$$,'22023','IDEMPOTENCY_MISMATCH','changed money cannot replay');
select throws_ok($$select pg_temp.pfc(pg_temp.pfe('bad')||'{"net":0.03}',0,'number')$$,'22023','PROJECT_AMOUNT_INVALID','numbers cannot replace decimal strings');
select throws_ok($$select pg_temp.pfc(pg_temp.pfe('bad')||'{"evidence_reference":"https://private.invalid"}',0,'url')$$,'22023','PROJECT_ATTACHMENT_PROVIDER_REQUIRED','unsafe attachment URL rejected');
select pg_temp.pfc(pg_temp.pfa('expense_submit'),1,'submit');
select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_approve'),2,'self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','expense approver independent');
select pg_temp.wactor('reviewer');select pg_temp.pfc(pg_temp.pfa('expense_approve'),2,'approve');
insert into project_finance_client_samples values('expenses',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses'));
reset role;
select is((select sum(amount) from projects.expense_allocations where expense_id=pg_temp.wid('pf.expense')),0.03::numeric,'ordered allocation preserves original gross');
select is((select amount from projects.expense_allocations where expense_id=pg_temp.wid('pf.expense') and ordinal=1),0.02::numeric,'half-even first allocation retained');
select is((select count(*)::integer from projects.expense_ownership where expense_id=pg_temp.wid('pf.expense')),1,'one liability ownership claim');
select throws_ok($$select projects.finance_closure_guard(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('finance'))$$,'55000','PROJECT_FINANCE_CLOSURE_IMPACT_REQUIRED','approved expense blocks closure');
set local role authenticated;select pg_temp.wactor('creator');select pg_temp.pfc(pg_temp.pfa('expense_post'),3,'post');
insert into project_finance_client_samples values('obligations',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'obligations'));
select pg_temp.pfc(jsonb_build_object('action','settle','id',pg_temp.wid('pf.settlement'),'project_id',pg_temp.wid('finance'),'obligation_id',pg_temp.wid('pf.expense'),'posting_date',pg_temp.wdate(),'amount','0.01','bank_id',pg_temp.wid('pf.bank'),'bank_version',1,'evidence_reference','SYNTHETIC-BANK-RECORD','reason','Synthetic recorded settlement'),0,'settle');
select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_reverse'),4,'reverse-blocked')$$,'55000','PROJECT_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL','active partial settlement blocks expense reversal');
insert into project_finance_client_samples values('settlements',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'settlements'));
select pg_temp.pfc(jsonb_build_object('action','settlement_reverse','id',pg_temp.wid('pf.settlement'),'project_id',pg_temp.wid('finance'),'posting_date',pg_temp.wdate(),'reason','Synthetic original settlement reversal'),1,'settlement-reverse');
reset role;
select is((select sum(amount) from projects.reimbursement_effects where obligation_id=pg_temp.wid('pf.expense')),0.03::numeric,'settlement reversal restores exact obligation');
select is((select sum(base_debit-base_credit) from finance.journal_lines where journal_entry_id in(select journal_id from projects.reimbursement_effects)),0::numeric,'expense and settlement journals conserved');
create function pg_temp.pfb(k text default 'batch') returns jsonb language sql security definer set search_path='' as $$
select jsonb_build_object('action','billing_prepare','id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'invoice_id',pg_temp.wid('pf.invoice.'||k),'document_date',(now() at time zone 'UTC')::date,'due_date',(now() at time zone 'UTC')::date,'exchange_rate_id',null,'units',jsonb_build_array(jsonb_build_object('unit_id',u.id,'source_version',u.source_version,'source_digest',u.source_digest,'product_id',pg_temp.wid('pf.product'),'product_version',1,'tax_definition_id',null,'tax_version',null,'description','Synthetic whole approved expense')),'reason','Synthetic billing preparation') from projects.billable_units u where u.source_kind='expense' and u.source_id=pg_temp.wid('pf.expense') $$;
create function pg_temp.pfba(a text,v bigint,k text default 'batch') returns jsonb language sql as $$select jsonb_build_object('action',a,'id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'invoice_version',v,'reason','Synthetic installed sales workflow') $$;
set local role authenticated;select pg_temp.pfc(pg_temp.pfb(),0,'billing-prepare');
select throws_ok($$select pg_temp.pfc(pg_temp.pfb('duplicate'),0,'billing-duplicate')$$,'55000','PROJECT_BILLING_SOURCE_UNAVAILABLE','source cannot reserve twice');
reset role;
select throws_ok($$update sales.sales_invoice_lines set quantity=2 where document_id=pg_temp.wid('pf.invoice.batch')$$,'55000','PROJECT_LINKED_INVOICE_IMMUTABLE','ordinary invoice line editing blocked');
select throws_ok($$update sales.sales_invoices set grand_total=1 where id=pg_temp.wid('pf.invoice.batch')$$,'55000','PROJECT_LINKED_INVOICE_IMMUTABLE','ordinary invoice money editing blocked');
select is((select quantity from sales.sales_invoice_lines where document_id=pg_temp.wid('pf.invoice.batch')),1::numeric,'whole unit avoids rounded fractional hours');
set local role authenticated;select pg_temp.pfc(pg_temp.pfba('billing_submit',1),1,'billing-submit');select pg_temp.wactor('reviewer');
select pg_temp.pfc(pg_temp.pfba('billing_decide',2)||'{"decision":"approved"}',2,'billing-decide');
select throws_ok($$select api.post_sales_invoice(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('id',pg_temp.wid('pf.invoice.batch')),3)$$,'42501','PROJECT_BILLING_INTENT_REQUIRED','direct sales posting cannot consume linked invoice');
reset role;
create function pg_temp.pf_billing_late_failure() returns trigger language plpgsql as $$begin if new.aggregate_id=pg_temp.wid('pf.batch') and new.action='billing_post' then raise exception using errcode='P0001',message='SYNTHETIC_BILLING_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_billing_late_failure before insert on projects.finance_events for each row execute function pg_temp.pf_billing_late_failure();
set local role authenticated;
select throws_ok($$select pg_temp.pfc(pg_temp.pfba('billing_post',3),3,'billing-late')$$,'P0001','SYNTHETIC_BILLING_LATE_FAILURE','late billing failure rolls back installed journal and source consumption');
reset role;
select ok((select status='approved' and posted_at is null from sales.sales_invoices where id=pg_temp.wid('pf.invoice.batch')) and(select status='reserved' from projects.billable_units where source_kind='expense' and source_id=pg_temp.wid('pf.expense')) and not exists(select 1 from core.command_receipts where command_id=pg_temp.wid('pf.command.billing-late')) and not exists(select 1 from projects.billing_intents),'late billing failure retains exact original reservation without receipt or posting intent');
drop trigger synthetic_billing_late_failure on projects.finance_events;
set local role authenticated;
select pg_temp.pfc(pg_temp.pfba('billing_post',3),3,'billing-post');
insert into project_finance_client_samples values('billing',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'billing'));
insert into project_finance_client_samples values('units',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'units'));
insert into project_finance_client_samples values('margin',api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate()));
insert into project_finance_client_samples values('history',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'history'));
reset role;
select is((select status from projects.billable_units where source_kind='expense' and source_id=pg_temp.wid('pf.expense')),'billed','invoice posting consumes original source');
select is((select count(*)::integer from projects.billing_intents),0,'protected transaction intent leaves no residue');
select ok(not exists(select 1 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name like 'projects.finance.%' and response::text ~ 'base_gross|expense_account|bill_amount|gross|net|tax|evidence_reference'),'generic finance receipts exclude private values');
select pg_temp.wactor('reader');set local role authenticated;
select throws_ok($$select api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses')$$,'42501',null,'ordinary project viewer has no private costs');
select pg_temp.wactor('creator','aal1');select throws_ok($$select pg_temp.pfc(pg_temp.pfe(),0,'create')$$,'42501',null,'finance MFA checked before replay');reset role;
select ok((select count(*)=14 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class where relnamespace='projects'::regnamespace and relname=any(array['expenses','expense_revisions','expense_allocations','expense_decisions','expense_ownership','reimbursements','reimbursement_effects','expense_settlements','billing_batches','billing_links','billing_intents','finance_events','payroll_billing_effects','service_cost_revisions'])),'all finance-owned tables force RLS');
select ok(not has_function_privilege('authenticated','projects.payroll_billing_impact(uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'payroll billing impact is protected provider-only');
select pg_temp.wactor('creator');
create function pg_temp.pf_late_failure() returns trigger language plpgsql as $$begin if new.aggregate_id=pg_temp.wid('pf.late') then raise exception using errcode='P0001',message='SYNTHETIC_FINANCE_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_late_failure before insert on projects.finance_events for each row execute function pg_temp.pf_late_failure();
set local role authenticated;
select throws_ok($$select pg_temp.pfc(pg_temp.pfe('late'),0,'late')$$,'P0001','SYNTHETIC_FINANCE_LATE_FAILURE','late event failure rolls back expense atomically');reset role;
select ok(not exists(select 1 from projects.expenses where id=pg_temp.wid('pf.late')) and not exists(select 1 from core.command_receipts where command_id=pg_temp.wid('pf.command.late')),'late failure leaves neither expense nor receipt');
insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount,payable_seconds) values(pg_temp.wid('pf.payroll.unit'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('finance'),pg_temp.wid('branch'),'time',pg_temp.wid('pf.payroll.revision'),1,repeat('a',64),12.00,1800);
select is(projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction')),'validate')->>'original_amount','12.000000','billing impact freezes original exact amount');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction')),'apply');
select is((select status from projects.billable_units where id=pg_temp.wid('pf.payroll.unit')),'cancelled','apply cancels original available source once');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction'),'operational_mode','reverse'),'validate');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction')),'reverse');
select is((select status from projects.billable_units where id=pg_temp.wid('pf.payroll.unit')),'cancelled','reverse retains original cancelled unit for fresh revision lineage');
select is((select count(*)::integer from projects.payroll_billing_effects where correction_id=pg_temp.wid('pf.payroll.correction')),2,'apply and reverse effects immutable separate records');
-- A second real installed sales workflow exercises immutable original credits.
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
select pg_temp.wid('pf.return.workflow'),tenant_id,legal_entity_id,'sales_return','Synthetic independent source credit',status,lifecycle,created_by,updated_by from workflow.workflow_definitions where id=pg_temp.wid('pf.workflow');
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.wid('pf.return.step'),pg_temp.wid('tenant'),pg_temp.wid('pf.return.workflow'),pg_temp.wid('reviewer.role'),1,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount,payable_seconds) values(pg_temp.wid('pf.credit.unit'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('finance'),pg_temp.wid('branch'),'time',pg_temp.wid('pf.credit.revision'),1,repeat('b',64),12.00,1800);
create function pg_temp.pf_credit_billing() returns jsonb language sql security definer set search_path='' as $$select pg_temp.pfb('credit')||jsonb_build_object('units',jsonb_build_array(jsonb_build_object('unit_id',pg_temp.wid('pf.credit.unit'),'source_version',1,'source_digest',repeat('b',64),'product_id',pg_temp.wid('pf.product'),'product_version',1,'tax_definition_id',null,'tax_version',null,'description','Synthetic original billed time'))) $$;
set local role authenticated;select pg_temp.wactor('creator');select pg_temp.pfc(pg_temp.pf_credit_billing(),0,'credit.prepare');
reset role;
select throws_ok($$update sales.sales_invoices set status='cancelled' where id=pg_temp.wid('pf.invoice.credit')$$,'42501','PROJECT_BILLING_INTENT_REQUIRED','protected linked draft status cannot bypass wrapper intent');
set local role authenticated;
select throws_ok($$select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('document_type','sales_invoice','document_id',pg_temp.wid('pf.invoice.credit'),'action','cancel','reason','Synthetic generic bypass'),1)$$,'55000','WORKFLOW_TRANSITION_INVALID','installed state rejects generic draft cancellation before source mutation');
select pg_temp.pfc(pg_temp.pfba('billing_submit',1,'credit'),1,'credit.submit');select pg_temp.wactor('reviewer');select pg_temp.pfc(pg_temp.pfba('billing_decide',2,'credit')||'{"decision":"approved"}',2,'credit.decide');select pg_temp.pfc(pg_temp.pfba('billing_post',3,'credit'),3,'credit.post');reset role;
select throws_ok($$select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.credit.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.credit.correction')),'validate')$$,'55000','PROJECT_POSTED_ORIGINAL_CREDIT_REQUIRED','billed source requires actual original posted credit');
create function pg_temp.pf_credit() returns jsonb language sql security definer set search_path='' as $$select jsonb_build_object('id',pg_temp.wid('pf.credit.document'),'customer_id',pg_temp.wid('pf.customer'),'document_date',(now() at time zone 'UTC')::date,'currency_code','LKR','reason','Synthetic original source credit','lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.wid('pf.credit.line'),'sales_invoice_line_id',l.id,'product_id',l.product_id,'base_quantity','1.000000','quantity','1.000000','unit_id',l.unit_id,'conversion_numerator','1','conversion_denominator','1','disposition','no_restock'))) from sales.sales_invoice_lines l where document_id=pg_temp.wid('pf.invoice.credit') $$;
set local role authenticated;select pg_temp.wactor('creator');
select api.upsert_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),pg_temp.pf_credit(),null);
select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('pf.credit.document'),'action','submit','reason','Synthetic credit submission'),1);
select pg_temp.wactor('reviewer');select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('pf.credit.document'),'action',null,'decision','approved','note','Synthetic independent original credit'),2);
select api.post_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('id',pg_temp.wid('pf.credit.document')),3);reset role;
set local role authenticated;
select is(api.projects_payroll_credit_choices(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.credit.revision'))#>>'{rows,0,id}',pg_temp.wid('pf.credit.line')::text,'named correction selector returns exact posted original credit');reset role;
select ok(not has_function_privilege('authenticated','projects.service_payroll_billing_impact(uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'service billing impact remains protected provider-only');
select is(projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.credit.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.credit.correction'),'billing_credit_line_ids',jsonb_build_array(pg_temp.wid('pf.credit.line'))),'validate')->>'original_amount','12.000000','posted original credit freezes exact whole source impact');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.credit.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.credit.correction'),'billing_credit_line_ids',jsonb_build_array(pg_temp.wid('pf.credit.line'))),'apply');
select is((select status from projects.billable_units where id=pg_temp.wid('pf.credit.unit')),'billed','posted original credits never release billed source');
select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate())->>'posted_credits')::numeric,12::numeric,'as-of margin includes exact original credit revenue');
-- Private cost rows exercise exact source-version, recorded/effective cutoffs.
-- Real service imports and linked callbacks are exercised by the service suite.
insert into project_finance_client_samples values('cost_asof',to_jsonb(clock_timestamp()-interval '10 seconds'));
insert into projects.service_cost_revisions(id,tenant_id,legal_entity_id,branch_id,project_id,provider_source_id,source_revision_id,source_version,source_digest,currency_code,precision,service_date,payable_seconds,hourly_cost,amount,status,recorded_by,recorded_at)
select pg_temp.wid('pf.service.cost.'||v),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.service.labor'),pg_temp.wid('pf.service.revision.'||v),v,repeat('c',64),'LKR',2,pg_temp.wdate(),
 case when v=3 then 0 when v=2 then 1800 else 3600 end,18,case when v=3 then 0 when v=2 then 9 else 18 end,
 case when v=3 then 'cancelled' else 'approved' end,pg_temp.wid('creator'),
 ((select body#>>'{}' from project_finance_client_samples where label='cost_asof')::timestamptz)+(v-1)*interval '1 second'
from generate_series(1,4) v;
create function pg_temp.pf_cost_margin(v integer,d date default pg_temp.wdate()) returns jsonb language sql as $$
 select api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),
 ((select body#>>'{}' from project_finance_client_samples where label='cost_asof')::timestamptz)+(v-1)*interval '1 second',d) $$;
select is(pg_temp.pf_cost_margin(1)->>'service_cost','18.000000','AC-428 as-of margin includes original protected service cost');
select is(pg_temp.pf_cost_margin(2)->>'service_cost','9.000000','AC-428 correction replaces cost at its recorded cutoff');
select is(pg_temp.pf_cost_margin(3)->>'service_cost','0.000000','AC-428 immutable zero removal stops original service cost');
select is(pg_temp.pf_cost_margin(4)->>'service_cost','18.000000','AC-428 fresh reversal restores cost exactly once');
select is(pg_temp.pf_cost_margin(4,pg_temp.wdate()-1)->>'service_cost','0','AC-428 service date independently bounds margin');
select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate())->>'margin')::numeric,-17.98::numeric,'AC-428 service cost subtraction reconciles original revenue and expense');
select throws_ok($$update projects.service_cost_revisions set amount=0 where id=pg_temp.wid('pf.service.cost.1')$$,'55000','PROJECT_HISTORY_IMMUTABLE','AC-428 historical internal service cost cannot be edited');
select ok(not has_function_privilege('authenticated','projects.service_payroll_cost_impact(uuid,uuid,uuid,uuid,uuid)','EXECUTE') and not has_table_privilege('authenticated','projects.service_cost_revisions','SELECT'),'AC-428 private cost provider and table have no client access');
set local role authenticated;select pg_temp.wactor('creator');
insert into project_finance_client_samples values('serviceCosts',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'serviceCosts'));
select pg_temp.wactor('reader');
select throws_ok($$select api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'serviceCosts')$$,'42501',null,'AC-428 ordinary project view cannot reveal internal service costs');
reset role;update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback' and entitlement_code='module.finance';
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.pfc(pg_temp.pfe(),0,'create')$$,'42501','PROJECT_FINANCE_ENTITLEMENT_REQUIRED','financial entitlement is checked before confirmed replay');
select throws_ok($$select pg_temp.pf_cost_margin(1)$$,'42501','PROJECT_FINANCE_ENTITLEMENT_REQUIRED','financial entitlement gates private margin reads');
reset role;update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback' and entitlement_code='module.finance';
delete from project_finance_client_samples where label='cost_asof';
