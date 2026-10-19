reset role;select pg_temp.wactor('creator');
create temporary table milestone_client_samples(label text primary key,body jsonb);grant select,insert on milestone_client_samples to authenticated;
create function pg_temp.mc(p jsonb,v bigint,k text) returns jsonb language sql as $$
 select api.project_milestone_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('ml.'||k),pg_temp.wid('ml.'||k),now(),p,v) $$;
create function pg_temp.ml(k text default 'one') returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid('ml.'||k),'project_id',pg_temp.wid('milestones'),'plan_id',pg_temp.wid('ml.plan'),
 'task_id',pg_temp.wid('task'),'owner_id',pg_temp.wid('employee'),'name','Customer acceptance milestone','due_date',pg_temp.wdate(),
 'amount','125.25','commercial_terms','Whole accepted deliverable; no partial time quantities','payment_terms','Payment due 30 days from invoice date',
 'payment_due_days',30,'evidence_reference','ACCEPTANCE-ML-01','reason','Governed milestone terms') $$;
create function pg_temp.ma(a text,k text default 'one') returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('ml.'||k),'project_id',pg_temp.wid('milestones'),
 'digest',(select digest from projects.milestone_revisions where id=(select current_revision_id from projects.milestones where id=pg_temp.wid('ml.'||k))),'reason','Governed independent milestone decision') $$;
select ok((select count(*)=3 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='projects' and relname in('milestones','milestone_revisions','milestone_events')),'milestone tables force RLS');
select ok(not has_function_privilege('authenticated','projects.milestone_billing_terms(uuid,uuid,uuid,uuid)','EXECUTE'),'frozen billing provider is owner-only');
select ok(not has_table_privilege('authenticated','projects.milestone_revisions','SELECT'),'immutable commercial history is API-only');
set local role authenticated;
select pg_temp.pc(pg_temp.project_create('milestones')||jsonb_build_object('customer_id',pg_temp.wid('pf.customer')),0,'ml.project');
select pg_temp.pc(jsonb_set(jsonb_set(pg_temp.project_plan('milestones','ml.plan'),'{resources}','[]'::jsonb),'{tasks,0,planned_seconds}','0'::jsonb),1,'ml.plan');
select throws_ok($$select pg_temp.mc(pg_temp.ml(),0,'unapproved')$$,'55000','MILESTONE_APPROVED_PLAN_REQUIRED','milestone requires exact approved plan');
select pg_temp.wactor('reviewer');select pg_temp.pc(pg_temp.plan_action('approve_plan','milestones','ml.plan'),2,'ml.approve.plan');
select pg_temp.wactor('creator');
select throws_ok($$select pg_temp.mc(pg_temp.ml()||'{"amount":"125.255"}',0,'precision')$$,'22023','PROJECT_AMOUNT_PRECISION','milestone amount obeys project precision');
select throws_ok($$select pg_temp.mc(pg_temp.ml()||'{"payment_due_days":366}',0,'days')$$,'22023','MILESTONE_PAYMENT_DAYS_INVALID','payment duration bounded');
select throws_ok($$select pg_temp.mc(pg_temp.ml()||jsonb_build_object('due_date',pg_temp.wdate()+2),0,'due')$$,'22023','MILESTONE_DUE_TASK_INVALID','milestone due belongs to task and project half-open dates');
select throws_ok($$select pg_temp.mc(pg_temp.ml()||jsonb_build_object('owner_id',pg_temp.wid('foreign-owner')),0,'owner')$$,'55000','MILESTONE_OWNER_COVERAGE_REQUIRED','dated accountable owner must belong to scope');
insert into milestone_client_samples values('create_receipt',pg_temp.mc(pg_temp.ml(),0,'create'));
select is(pg_temp.mc(pg_temp.ml(),0,'create'),(select body from milestone_client_samples where label='create_receipt'),'exact milestone replay');
select throws_ok($$select pg_temp.mc(pg_temp.ml()||'{"name":"Changed"}',0,'create')$$,'22023','IDEMPOTENCY_MISMATCH','changed milestone cannot reuse sealed key');
select pg_temp.mc(pg_temp.ma('submit'),1,'submit');
select throws_ok($$select pg_temp.mc(pg_temp.ma('approve'),2,'self')$$,'42501','MILESTONE_INDEPENDENT_APPROVAL_REQUIRED','maker cannot approve milestone');
select pg_temp.wactor('reviewer');
select throws_ok($$select pg_temp.mc(pg_temp.ma('approve'),2,'incomplete')$$,'55000','MILESTONE_TASK_INCOMPLETE','approval requires task progress10000');
select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('milestones'),'task_id',pg_temp.wid('task'),'progress',10000,'reason','Exact deliverable completed'),3,'ml.progress');
insert into milestone_client_samples values('approve_receipt',pg_temp.mc(pg_temp.ma('approve'),2,'approve'));
insert into milestone_client_samples values('directory',api.project_milestones(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('milestones')));
insert into milestone_client_samples values('events',api.project_milestone_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('milestones'),pg_temp.wid('ml.one')));
insert into milestone_client_samples values('revisions',api.project_milestone_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('milestones'),pg_temp.wid('ml.one'),null,'revisions'));
reset role;
-- Access is checked before both immutable history and actor-bound replay.
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select api.project_milestones(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'),pg_temp.wid('milestones'))$$,
 'P0002','PROJECT_NOT_FOUND','denied project branch cannot broaden milestone reads');
reset role;
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('creator.role') and permission_code='projects.manage';
set local role authenticated;
select throws_ok($$select pg_temp.mc(pg_temp.ml(),0,'create')$$,'42501','Permission denied or multi-factor authentication required.','revoked action cannot reveal original milestone replay');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'projects.manage');
create function pg_temp.milestone_late_failure() returns trigger language plpgsql as $$begin
 if new.milestone_id=pg_temp.wid('ml.late') then raise exception using errcode='P0001',message='SYNTHETIC_MILESTONE_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_milestone_late_failure before insert on projects.milestone_events for each row execute function pg_temp.milestone_late_failure();
set local role authenticated;
select throws_ok($$select pg_temp.mc(pg_temp.ml('late'),0,'late')$$,
 'P0001','SYNTHETIC_MILESTONE_LATE_FAILURE','late audit failure rolls back draft revision and business effects');
reset role;
select ok(not exists(select 1 from projects.milestones where id=pg_temp.wid('ml.late')) and not exists(select 1 from core.command_receipts where command_id=pg_temp.wid('ml.late')),
 'late failure has no milestone or receipt residue');
drop trigger synthetic_milestone_late_failure on projects.milestone_events;
select is((select count(*)::integer from projects.billable_units where source_kind='milestone' and source_id=(select current_revision_id from projects.milestones where id=pg_temp.wid('ml.one'))),1,'one whole immutable approved source');
select is((select amount from projects.billable_units where source_kind='milestone' and source_id=(select current_revision_id from projects.milestones where id=pg_temp.wid('ml.one'))),125.25::numeric,'exact approved commercial amount retained');
select throws_ok($$select projects.milestone_closure_guard(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('milestones'))$$,'55000','MILESTONE_CLOSURE_IMPACT_REQUIRED','unresolved available source blocks project closure');
create function pg_temp.mb(d integer default 30,k text default 'one') returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action','billing_prepare','id',pg_temp.wid('ml.batch.'||k),'project_id',pg_temp.wid('milestones'),'invoice_id',pg_temp.wid('ml.invoice.'||k),
 'document_date',(now() at time zone 'UTC')::date,'due_date',(now() at time zone 'UTC')::date+d,'exchange_rate_id',null,'units',
 jsonb_build_array(jsonb_build_object('unit_id',u.id,'source_version',u.source_version,'source_digest',u.source_digest,'product_id',pg_temp.wid('pf.product'),
 'product_version',1,'tax_definition_id',null,'tax_version',null,'description','Whole approved customer milestone')),'reason','Approved immutable milestone invoice')
 from projects.billable_units u where u.source_kind='milestone' and u.source_id=(select current_revision_id from projects.milestones where id=pg_temp.wid('ml.'||k)) $$;
create function pg_temp.mbc(p jsonb,v bigint,k text) returns jsonb language sql as $$
 select api.projects_finance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('ml.finance.'||k),pg_temp.wid('ml.finance.'||k),now(),p,v) $$;
create function pg_temp.mba(a text,v bigint) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('ml.batch.one'),'project_id',pg_temp.wid('milestones'),'invoice_version',v,'reason','Independent installed invoice workflow') $$;
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.mbc(pg_temp.mb(0),0,'bad.days')$$,'22023','PROJECT_MILESTONE_DUE_DATE_REQUIRED','invoice retains approved frozen payment duration');
select pg_temp.mbc(pg_temp.mb(),0,'prepare');
select throws_ok($$select pg_temp.mc(pg_temp.ma('cancel'),3,'reserved.cancel')$$,'55000','MILESTONE_BILLING_IMPACT_REQUIRED','reserved milestone cannot be cancelled');
select pg_temp.mbc(pg_temp.mba('billing_submit',1),1,'submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.mbc(pg_temp.mba('billing_decide',2)||'{"decision":"approved"}',2,'decide');
select pg_temp.mbc(pg_temp.mba('billing_post',3),3,'post');
reset role;
select is((select quantity from sales.sales_invoice_lines where document_id=pg_temp.wid('ml.invoice.one')),1::numeric,'real posted invoice uses quantity one');
select is((select grand_total from sales.sales_invoices where id=pg_temp.wid('ml.invoice.one')),125.25::numeric,'real invoice posts exact milestone total');
select is((select status from projects.billable_units where source_kind='milestone' and source_id=(select current_revision_id from projects.milestones where id=pg_temp.wid('ml.one'))),'billed','real posting consumes milestone exactly once');
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.mc(pg_temp.ma('cancel'),3,'billed.cancel')$$,'55000','MILESTONE_BILLING_IMPACT_REQUIRED','consumed milestone retains original invoice evidence');
select throws_ok($$select pg_temp.mc(pg_temp.ml()||'{"action":"correct"}',3,'billed.correct')$$,'55000','MILESTONE_BILLING_IMPACT_REQUIRED','consumed correction requires governed finance impact');
select pg_temp.wactor('reader');
select throws_ok($$select api.project_milestone_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('milestones'),pg_temp.wid('ml.create'),'create')$$,
 '42501','Permission denied or multi-factor authentication required.','own receipt rechecks current action authority');
select pg_temp.wactor('reviewer');
select is(api.project_milestone_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('milestones'),pg_temp.wid('ml.create'),'create'),null::jsonb,'receipt is actor-owned');
select pg_temp.wactor('creator','aal1');
select throws_ok($$select pg_temp.mc(pg_temp.ml('two'),0,'mfa')$$,'42501','Permission denied or multi-factor authentication required.','fresh command requires MFA');
select pg_temp.wactor('creator');
select throws_ok($$select pg_temp.mc(pg_temp.ml('long')||jsonb_build_object('payment_terms',repeat('x',1001)),0,'long.reject')$$,'22023','PROJECT_TEXT_INVALID','commercial payment terms beyond1000 are rejected');
select pg_temp.mc(pg_temp.ml('long')||jsonb_build_object('payment_terms',repeat('x',1000)),0,'long.create');
select pg_temp.mc(pg_temp.ma('submit','long'),1,'long.submit');
select pg_temp.wactor('reviewer');select pg_temp.mc(pg_temp.ma('approve','long'),2,'long.approve');
select pg_temp.wactor('creator');
select is((select x->>'payment_terms' from jsonb_array_elements(api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('milestones'),'units')->'rows') x where length(x->>'payment_terms')=1000),repeat('x',1000),'approved maximum payment terms survive named billing unit read');
select lives_ok($$select pg_temp.mbc(pg_temp.mb(30,'long'),0,'long.prepare')$$,'maximum frozen payment terms prepare whole invoice with exactdue+30');
select pg_temp.mc(pg_temp.ml('two'),0,'two.create');select pg_temp.mc(pg_temp.ma('submit','two'),1,'two.submit');
select pg_temp.wactor('reviewer');select pg_temp.mc(pg_temp.ma('approve','two'),2,'two.approve');
reset role;
insert into milestone_client_samples values('historical_terms',projects.milestone_billing_terms(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select current_revision_id from projects.milestones where id=pg_temp.wid('ml.two'))));
create temporary table milestone_old_source as select current_revision_id id from projects.milestones where id=pg_temp.wid('ml.two');grant select on milestone_old_source to authenticated;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.mc(pg_temp.ml('two')||'{"action":"correct","amount":"150.00","payment_due_days":15,"payment_terms":"Payment due15 days"}',3,'two.correct');
reset role;
select is((select status from projects.billable_units where source_kind='milestone' and source_id=(select id from milestone_old_source)),'cancelled','correction cancels only available old source');
select is(projects.milestone_billing_terms(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),(select id from milestone_old_source)),
 (select body from milestone_client_samples where label='historical_terms'),'historical originally approved terms remain readable');
select is((select count(*)::integer from projects.milestone_revisions where milestone_id=pg_temp.wid('ml.two')),2,'correction appends immutable commercial terms');
select throws_ok($$update projects.milestone_revisions set amount=1 where milestone_id=pg_temp.wid('ml.two')$$,'55000','PROJECT_HISTORY_IMMUTABLE','historical terms cannot be overwritten');
set local role authenticated;
insert into milestone_client_samples values('corrected_revisions',api.project_milestone_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('milestones'),pg_temp.wid('ml.two'),null,'revisions'));
select pg_temp.mc(pg_temp.ml('three'),0,'three.create');select pg_temp.mc(pg_temp.ma('submit','three'),1,'three.submit');
select pg_temp.pc(jsonb_set(jsonb_set(pg_temp.project_plan('milestones','ml.new.plan'),'{resources}','[]'::jsonb),'{tasks,0,planned_seconds}','0'::jsonb),4,'new.plan');
select pg_temp.wactor('reviewer');select pg_temp.pc(pg_temp.plan_action('approve_plan','milestones','ml.new.plan'),5,'new.plan.approve');
select throws_ok($$select pg_temp.mc(pg_temp.ma('approve','three'),2,'stale.plan')$$,'55000','MILESTONE_APPROVED_PLAN_REQUIRED','new plan cannot make old milestone eligibility current');
reset role;
