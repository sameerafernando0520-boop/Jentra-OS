create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.projects',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer','branch-manager']) x
cross join core.permissions p where p.module='projects';
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reader.role'),'projects.view');
insert into people.departments(id,tenant_id,legal_entity_id,code) values(pg_temp.wid('department'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4OPS');
insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,start_date,end_date_exclusive,reason,recorded_by)
values(pg_temp.wid('department-r1'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('department'),'Synthetic Operations',pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic project fixture',pg_temp.wid('creator'));
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,
 role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('org-'||e.code),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),e.id,s.id,pg_temp.wid('department'),
 pg_temp.wid('calendar-version'),'Synthetic worker',pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic project fixture',pg_temp.wid('creator')
from people.employees e join people.employment_spells s on s.employee_id=e.id where e.tenant_id=pg_temp.wid('tenant') and e.code in('EMPLOYEE','THIRD');
create function pg_temp.pc(p jsonb,v bigint,k text,b text default 'branch') returns jsonb language sql as $$
 select api.projects_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid(k),pg_temp.wid(k),now(),p,v) $$;
create function pg_temp.project_create(p text default 'project') returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid(p),'code',upper(p),'name','Synthetic Project','manager_id',pg_temp.wid('manager'),
  'currency_code','LKR','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'reason','Synthetic project creation') $$;
create function pg_temp.project_plan(p text default 'project',pl text default 'plan') returns jsonb language sql as $$
 select jsonb_build_object('action','plan','id',pg_temp.wid(p),'plan_id',pg_temp.wid(pl),'terms','Synthetic whole-unit commercial terms','budget','1000.00','reason','Synthetic project plan',
 'tasks',jsonb_build_array(jsonb_build_object('id',pg_temp.wid('task'),'name','Delivery','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',7200,'dependencies','[]'::jsonb),
 jsonb_build_object('id',pg_temp.wid('task2'),'name','Review','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',0,'dependencies',jsonb_build_array(pg_temp.wid('task')))),
 'resources',jsonb_build_array(jsonb_build_object('id',pg_temp.wid(pl||'-slot'),'task_id',pg_temp.wid('task'),'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+interval '12 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'bill_rate','54.00','cost_rate','18.00'))) $$;
create function pg_temp.project_time(p text,s interval default interval '10 hours',z interval default interval '11 hours',cl boolean default true) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action','time_create','id',pg_temp.wid(p),'project_id',pg_temp.wid('project'),'employee_id',pg_temp.wid('employee'),
 'resource_slot_id',pg_temp.wid('plan-slot'),'start_local',to_char(pg_temp.wdate()::timestamp+s,'YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+z,'YYYY-MM-DD"T"HH24:MI:SS'),'start_offset_seconds',19800,'end_offset_seconds',19800,
 'breaks','[]'::jsonb,'attendance_claim_id',case when cl then(select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')) end,'reason','Synthetic project time') $$;
create function pg_temp.time_action(a text,p text) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid(p),'project_id',pg_temp.wid('project'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic project time transition') $$;
create function pg_temp.plan_action(a text,p text default 'project',pl text default 'plan') returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid(p),'plan_id',pg_temp.wid(pl),'digest',(select basis_digest from projects.plans where id=pg_temp.wid(pl)),'reason','Synthetic independent plan decision') $$;
create temporary table project_responses(label text primary key,body jsonb);grant insert,select on project_responses to authenticated;
create temporary table project_client_samples(label text primary key,body jsonb);grant insert,select on project_client_samples to authenticated;
select ok((select count(*)=16 and bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='projects' and c.relkind='r'
 and c.relname=any(array['register','plans','tasks','dependencies','resource_slots','resource_costs','cost_basis','plan_decisions','task_progress','time_entries','time_revisions','time_allocations','time_events','billable_units','time_costs','unit_decisions'])),'AC-401 all core project tables force RLS');
select ok(not has_table_privilege('authenticated','projects.cost_basis','SELECT'),'AC-404 no direct private cost read');
select ok(not has_table_privilege('authenticated','projects.resource_slots','UPDATE'),'AC-410 no direct planning bypass');
select ok(not has_function_privilege('anon','api.projects_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),'AC-401 anonymous commands denied');
select is(projects.ratio(18000000,3600,2)::numeric,0::numeric,'AC-411 exact even time tie');
select is(projects.ratio(54000000,3600,2)::numeric,0.02::numeric,'AC-411 exact odd time tie');
select is(projects.ratio(-15000,1,2)::numeric,-0.02::numeric,'AC-411 signed half-even');
select pg_temp.wactor('creator');set local role authenticated;
insert into project_responses values('create',pg_temp.pc(pg_temp.project_create(),0,'project-create'));
select is(pg_temp.pc(pg_temp.project_create(),0,'project-create'),(select body from project_responses where label='create'),'AC-401 exact project replay');
select throws_ok($$select pg_temp.pc(pg_temp.project_create()||jsonb_build_object('name','Changed'),0,'project-create')$$,'22023','IDEMPOTENCY_MISMATCH','AC-401 changed body cannot replay');
select throws_ok($$select pg_temp.pc(pg_temp.project_create('foreign'),0,'project-foreign','branch2')$$,'55000','PROJECT_MANAGER_COVERAGE_REQUIRED','AC-401 manager branch coverage enforced');
select throws_ok($$select pg_temp.pc(jsonb_set(pg_temp.project_plan(),'{resources,0,start_local}',
 to_jsonb(pg_temp.wdate()::text||'T10:00:00.500')),1,'fractional-plan')$$,
 '22023','WORK_LOCAL_BOUNDARY_INVALID','AC-411 fractional resource boundaries cannot be rounded to whole UTC seconds');
insert into project_responses values('plan',pg_temp.pc(pg_temp.project_plan(),1,'project-plan'));
select throws_ok($$select pg_temp.pc(pg_temp.plan_action('approve_plan'),2,'plan-self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','AC-410 independent planning decision');
select pg_temp.wactor('reviewer');
insert into project_responses values('approve',pg_temp.pc(pg_temp.plan_action('approve_plan'),2,'plan-approve'));
select is((select body#>>'{entity,current_plan_id}' from project_responses where label='approve'),pg_temp.wid('plan')::text,'AC-410 approved plan becomes current');
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('project'),'task_id',pg_temp.wid('task2'),'progress',10000,'reason','Synthetic early completion'),3,'early-complete')$$,'55000','PROJECT_PREREQUISITES_INCOMPLETE','AC-410 cannot finish before prerequisite');
reset role;
-- Existing attendance is the only payable claim; project approval allocates it.
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('att-create'),pg_temp.wid('att-create'),now(),
 jsonb_build_object('action','create','id',pg_temp.wid('attendance'),'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(pg_temp.wdate()::timestamp+interval '12 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,'reason','Synthetic attendance source'),0);
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('att-submit'),pg_temp.wid('att-submit'),now(),
 jsonb_build_object('action','submit','id',pg_temp.wid('attendance'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic attendance source'),1);
select pg_temp.wactor('creator');
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('att-approve'),pg_temp.wid('att-approve'),now(),
 jsonb_build_object('action','approve','id',pg_temp.wid('attendance'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic independent attendance'),2);
set local role authenticated;
select throws_ok($$select pg_temp.pc(pg_temp.project_time('fractional-time')||jsonb_build_object(
 'start_local',pg_temp.wdate()::text||'T10:00:00.500'),0,'fractional-time-create')$$,
 '22023','WORK_LOCAL_BOUNDARY_INVALID','AC-411 fractional time boundaries cannot silently change payable duration');
insert into project_responses values('time',pg_temp.pc(pg_temp.project_time('time'),0,'time-create'));
insert into project_responses values('submit',pg_temp.pc(pg_temp.time_action('time_submit','time'),1,'time-submit'));
select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','time'),2,'time-self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','AC-411 time reviewer independent');
select pg_temp.wactor('reviewer');
insert into project_responses values('time-approved',pg_temp.pc(pg_temp.time_action('time_approve','time'),2,'time-approve'));
reset role;
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('employee') and active),1,'AC-411 allocating attendance never makes another payable claim');
select is((select sum(extract(epoch from a.end_utc-a.start_utc))::bigint from people.work_allocations a where a.employee_id=pg_temp.wid('employee') and active),3600::bigint,'AC-411 exact allocated seconds');
select is((select amount from projects.time_costs),18::numeric,'AC-411 explicit synthetic costing separate from payroll');
select is((select amount from projects.billable_units),54::numeric,'AC-412 immutable whole unit retains exact commercial price');
select ok(not exists(select 1 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name like 'projects.%' and response::text~'bill_amount|cost_rate|hourly_rate|budget'),'AC-404 generic receipts exclude financial costing');
select pg_temp.wactor('reader');set local role authenticated;
insert into project_client_samples values('directory',api.projects_directory(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch')));
insert into project_client_samples values('plans',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'plans'));
insert into project_client_samples values('tasks',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'tasks'));
insert into project_client_samples values('resources',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'resources'));
insert into project_client_samples values('time',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'time'));
insert into project_client_samples values('units',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'units'));
select throws_ok($$select api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'cost')$$,'42501',null,'AC-404 operational viewer cannot read cost');
select throws_ok($$select api.projects_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project-plan'),'plan')$$,'42501',null,'AC-401 original capability required before receipt');
select pg_temp.wactor('creator');
insert into project_responses values('duplicate',pg_temp.pc(pg_temp.project_time('duplicate'),0,'duplicate-create'));
select pg_temp.pc(pg_temp.time_action('time_submit','duplicate'),1,'duplicate-submit');
select pg_temp.wactor('reviewer');
select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','duplicate'),2,'duplicate-approve')$$,'23514','WORK_INTERVAL_CONFLICT','AC-411 same attendance segment cannot be allocated twice');
select pg_temp.wactor('creator');
select pg_temp.pc(pg_temp.project_time('direct',interval '11 hours',interval '12 hours',false),0,'direct-create');
select pg_temp.pc(pg_temp.time_action('time_submit','direct'),1,'direct-submit');
select pg_temp.wactor('reviewer');
select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','direct'),2,'direct-approve')$$,'23514','WORK_INTERVAL_CONFLICT','AC-411 direct project claim cannot duplicate attendance pay');
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','close','id',pg_temp.wid('project'),'reason','Synthetic closure'),3,'close-open')$$,'55000','PROJECT_CLOSURE_IMPACT_REQUIRED','AC-412 closure cannot hide open sources');
select pg_temp.wactor('creator');
select pg_temp.pc(pg_temp.project_create('competing'),0,'competing-create');
select pg_temp.pc(pg_temp.project_plan('competing','competing-plan'),1,'competing-plan-create');
select pg_temp.wactor('reviewer');
select throws_ok($$select pg_temp.pc(pg_temp.plan_action('approve_plan','competing','competing-plan'),2,'competing-approve')$$,'23514','PROJECT_RESOURCE_CAPACITY_CONFLICT','AC-410 approved projects cannot reserve the same employee capacity');
reset role;
select ok((select bool_and(not active) from projects.resource_slots where plan_id=pg_temp.wid('competing-plan')),'AC-410 failed competing approval is atomic');
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($$select pg_temp.pc(pg_temp.project_plan('competing','cycle-plan')||jsonb_build_object('tasks',
 jsonb_build_array(jsonb_build_object('id',pg_temp.wid('task'),'name','Delivery','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',7200,'dependencies',jsonb_build_array(pg_temp.wid('task2'))),
 jsonb_build_object('id',pg_temp.wid('task2'),'name','Review','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',0,'dependencies',jsonb_build_array(pg_temp.wid('task'))))),2,'cycle-plan')$$,'23514','PROJECT_TASK_CYCLE','AC-410 cycles rejected before effects');
select pg_temp.wactor('reviewer');
insert into project_client_samples values('cost',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'cost'));
insert into project_client_samples values('resource_cost',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'resource_cost'));
insert into project_client_samples values('time_cost',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'time_cost'));
select pg_temp.pc(pg_temp.time_action('time_cancel','time'),3,'time-cancel');
reset role;
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('employee') and active),1,'AC-411 cancellation releases allocation but preserves attendance claim');
select is((select count(*)::integer from people.work_allocations where employee_id=pg_temp.wid('employee') and active),0,'AC-411 cancellation reverses exact original allocations');
select is((select status from projects.billable_units where source_id=(select current_revision_id from projects.time_entries where id=pg_temp.wid('time'))),'cancelled','AC-412 cancellation retains immutable original unit');
-- A second employee establishes a real direct project claim, then a late
-- outbox failure proves claim/allocation/unit/cost/consumption atomicity.
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pc(pg_temp.project_create('dedicated'),0,'dedicated-create');
select pg_temp.pc(jsonb_set(pg_temp.project_plan('dedicated','dedicated-plan'),'{resources,0,employee_id}',to_jsonb(pg_temp.wid('third'))),1,'dedicated-plan');
select pg_temp.wactor('reviewer');
select pg_temp.pc(pg_temp.plan_action('approve_plan','dedicated','dedicated-plan'),2,'dedicated-approve');
select pg_temp.wactor('creator');
select pg_temp.pc(pg_temp.project_time('dedicated-time',interval '10 hours',interval '11 hours',false)||
 jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third'),'resource_slot_id',pg_temp.wid('dedicated-plan-slot')),0,'dedicated-time-create');
select pg_temp.pc(pg_temp.time_action('time_submit','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),1,'dedicated-time-submit');
reset role;
create function pg_temp.project_outbox_failure() returns trigger language plpgsql as $$begin
 if new.command_id=pg_temp.wid('dedicated-time-approve') then raise exception using errcode='P0001',message='SYNTHETIC_PROJECT_OUTBOX_FAILURE';end if;return new;end $$;
create trigger w4_project_rollback_failure before insert on core.outbox_events for each row execute function pg_temp.project_outbox_failure();
select pg_temp.wactor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),2,'dedicated-time-approve')$$,
 'P0001','SYNTHETIC_PROJECT_OUTBOX_FAILURE','AC-411 late outbox failure rolls back the whole time approval');
reset role;
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('third')),0,'AC-411 failed approval leaves no direct claim');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('dedicated')),0,'AC-412 failed approval leaves no billing unit');
select is((select count(*)::integer from projects.time_costs where project_id=pg_temp.wid('dedicated')),0,'AC-411 failed approval leaves no private cost');
select is((select status from projects.time_entries where id=pg_temp.wid('dedicated-time')),'submitted','AC-411 failed approval retains the exact submitted revision');
drop trigger w4_project_rollback_failure on core.outbox_events;
set local role authenticated;
select pg_temp.pc(pg_temp.time_action('time_approve','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),2,'dedicated-time-approve');
select is(jsonb_array_length(api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('dedicated'),'time',pg_temp.wid('dedicated-time'))->'rows'),1,'AC-411 exact target time read is available beyond directory pages');
select is(jsonb_array_length(api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('dedicated'),'plans',pg_temp.wid('dedicated-plan'))->'rows'),1,'AC-410 exact original plan read is bounded');
reset role;
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('third') and active),1,'AC-411 successful direct time owns one payable claim');
select is((select projects.payroll_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('third'),id)->>'paid_seconds' from people.work_claims where employee_id=pg_temp.wid('third') and active),'3600','AC-411 payroll provider verifies exact approved direct claim');
select throws_ok($$select projects.payroll_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),(select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')))$$,
 '55000','PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED','AC-411 attendance allocations cannot duplicate project payroll eligibility');
select ok(not has_function_privilege('authenticated','projects.payroll_source(uuid,uuid,uuid,uuid,uuid)','EXECUTE'),'AC-404 payroll source provider is owner-only');
insert into people.work_input_seals(tenant_id,legal_entity_id,employee_id,run_id,claim_id,source_version,seconds,digest)
 select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('third'),pg_temp.wid('synthetic-payroll-run'),id,3,3600,repeat('a',64)
 from people.work_claims where employee_id=pg_temp.wid('third') and active;
set local role authenticated;
select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_cancel','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),3,'sealed-project-cancel')$$,
 '55000','PAYROLL_INPUT_SEALED','AC-411 consumed direct time requires a linked payroll correction');
select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('dedicated'),'task_id',pg_temp.wid('task'),'progress',10000,'reason','Synthetic completed original task'),3,'dedicated-progress');
select pg_temp.wactor('creator');
select pg_temp.pc(jsonb_set(pg_temp.project_plan('dedicated','revised-plan'),'{resources,0,employee_id}',to_jsonb(pg_temp.wid('third'))),4,'dedicated-revise');
select pg_temp.wactor('reviewer');
select pg_temp.pc(pg_temp.plan_action('approve_plan','dedicated','revised-plan'),5,'dedicated-revise-approve');
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('dedicated'),'task_id',pg_temp.wid('task2'),'progress',10000,'reason','Synthetic revised task'),6,'dedicated-revised-complete')$$,
 '55000','PROJECT_PREREQUISITES_INCOMPLETE','AC-410 revised plan cannot inherit completion from old dependency graph');
select pg_temp.wactor('creator');
insert into project_client_samples values('resolution',api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600));
insert into project_client_samples values('second_resolution',api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600,1));
select is(api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600,1)#>>'{resolution,local_datetime}',to_char(pg_temp.wdate()::timestamp+interval '10 hours 1 second','YYYY-MM-DD"T"HH24:MI:SS'),'AC-411 resolver retains original whole-second boundary');
select is(jsonb_array_length(api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600)#>'{resolution,candidates}'),1,'AC-410 named project reservation resolves original published zone');
select pg_temp.pc(pg_temp.project_plan('project','stale-plan'),3,'stale-plan-create');
select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('project'),'task_id',pg_temp.wid('task'),'progress',10000,'reason','Synthetic independent current-plan progress'),4,'stale-plan-progress');
select pg_temp.wactor('reviewer');
select throws_ok($$select pg_temp.pc(pg_temp.plan_action('approve_plan','project','stale-plan'),5,'stale-plan-approve')$$,'55000','PROJECT_PLAN_STALE','AC-410 concurrent progress cannot approve a stale plan basis');
select pg_temp.pc(pg_temp.plan_action('reject_plan','project','stale-plan'),5,'stale-plan-reject');
reset role;
select is((select status from projects.plans where id=pg_temp.wid('stale-plan')),'rejected','AC-410 independent original-digest rejection resolves a stale pending basis');
select pg_temp.wactor('creator','aal1');set local role authenticated;
select throws_ok($$select pg_temp.pc(pg_temp.project_create(),0,'project-create')$$,'42501',null,'AC-401 MFA checked before replay');
select pg_temp.wactor('outsider');
select throws_ok($$select api.projects_directory(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$$,'42501',null,'AC-401 outsider cannot read projects');
reset role;
