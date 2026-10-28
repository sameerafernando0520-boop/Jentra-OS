-- ISOLATED LOCAL/CI DATABASE ONLY. All candidate definitions/fixtures roll back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
\ir ../20261025090000_employee_self_service.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.sid(label text) returns uuid language sql immutable as
 $$select md5('employee-self-isolated-rollback-v1:'||label)::uuid$$;
create function pg_temp.self_actor(label text,level text default 'aal2') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.sid(label)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.sid(label),'role','authenticated',
  'aal',level,'session_id',pg_temp.sid(label||'.session'))::text,true);
end $$;
create function pg_temp.capture_body() returns jsonb language sql stable as $$
 select jsonb_build_object('action','capture','observed_at',to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'reason','Synthetic own attendance evidence')
$$;
create function pg_temp.leave_body(start_hour integer default 9,end_hour integer default 10) returns jsonb language sql stable as $$
 select jsonb_build_object('policy_version_id',pg_temp.sid('policy.version'),'calendar_version_id',pg_temp.sid('calendar.version'),
  'start_local',to_char((current_date+1)::timestamp+make_interval(hours=>start_hour),'YYYY-MM-DD"T"HH24:MI:SS'),
  'end_local',to_char((current_date+1)::timestamp+make_interval(hours=>end_hour),'YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',0,'end_offset_seconds',0,'reason','Synthetic own leave')
$$;
create function pg_temp.self_submit(command text,request text,body jsonb default pg_temp.leave_body(),v bigint default 0)
 returns jsonb language sql as $$
 select api.employee_self_leave_submit(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
  pg_temp.sid(command),pg_temp.sid(request),body,v)
$$;
create function pg_temp.self_capture(command text,request text,body jsonb default pg_temp.capture_body()) returns jsonb language sql as $$
 select api.employee_self_attendance_request(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
  pg_temp.sid(command),pg_temp.sid(request),body)
$$;
create function pg_temp.staff_resolve(command text,kind text,target uuid,decision text,canonical uuid default null,
 canonical_version bigint default null,balance_version bigint default null,expected_version bigint default 1,
 reason text default 'Synthetic employee-visible staff decision') returns jsonb language sql as $$
 select api.employee_staff_request_resolve(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
  pg_temp.sid(command),kind,target,decision,canonical,expected_version,canonical_version,balance_version,reason)
$$;
create temporary table self_results(name text primary key,value jsonb);
grant select,insert on self_results to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.sid(label),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 label||'@employee-self.rollback.invalid','',now(),now(),now() from unnest(array['a','b','outsider']) label;
insert into auth.sessions(id,user_id,created_at,updated_at)
select pg_temp.sid(label||'.session'),pg_temp.sid(label),now(),now() from unnest(array['a','b','outsider']) label;
insert into core.tenants(id,name,slug,created_by)
values(pg_temp.sid('tenant'),'Synthetic self rollback','employee-self-isolated-rollback',pg_temp.sid('a'));
insert into core.legal_entities(id,tenant_id,name,code,timezone,created_by)
values(pg_temp.sid('entity'),pg_temp.sid('tenant'),'Synthetic entity','SELFQA','UTC',pg_temp.sid('a'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.sid(label),pg_temp.sid('tenant'),pg_temp.sid('entity'),'Synthetic '||label,
 case when label='branch' then 'SELF1' else 'SELF2' end,pg_temp.sid('a') from unnest(array['branch','other-branch']) label;
insert into billing.plans(code,name) values('employee_self_isolated','Synthetic self plan');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('employee_self_isolated','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.sid('tenant'),'employee_self_isolated','trialing',5,now()+interval '2 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.sid(label||'.membership'),pg_temp.sid('tenant'),pg_temp.sid(label),'active' from unnest(array['a','b']) label;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
values(pg_temp.sid('self-role'),pg_temp.sid('tenant'),'employee.self','Synthetic bounded employee self',false);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.sid('tenant'),pg_temp.sid('self-role'),cap from unnest(array['people.view','people.self.view',
 'people.attendance.self.request','people.leave.self.manage','people.payroll.payslip.self']) cap;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.sid('tenant'),pg_temp.sid(label||'.membership'),pg_temp.sid('self-role'),pg_temp.sid('entity'),
 pg_temp.sid('branch'),pg_temp.sid('a') from unnest(array['a','b']) label;
insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by)
select pg_temp.sid(label||'.employee'),pg_temp.sid('tenant'),pg_temp.sid('entity'),upper(label),'Synthetic '||label,pg_temp.sid('a'),pg_temp.sid('a')
from unnest(array['a','b']) label;
insert into people.employment_spells(id,tenant_id,legal_entity_id,employee_id,start_date,created_by)
select pg_temp.sid(label||'.spell'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid(label||'.employee'),current_date-40,pg_temp.sid('a')
from unnest(array['a','b']) label;
insert into people.employment_assignments(id,tenant_id,legal_entity_id,employee_id,spell_id,branch_id,start_date,job_title,employment_type,created_by)
select pg_temp.sid(label||'.assignment'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid(label||'.employee'),pg_temp.sid(label||'.spell'),
 pg_temp.sid('branch'),current_date-40,'Synthetic employee','permanent',pg_temp.sid('a') from unnest(array['a','b']) label;
insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at)
select pg_temp.sid(label||'.link'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid(label||'.employee'),
 pg_temp.sid(label||'.membership'),pg_temp.sid(label),'accepted',pg_temp.sid('a'),now() from unnest(array['a','b']) label;
insert into people.work_calendars(id,tenant_id,legal_entity_id,code,name,created_by,updated_by)
values(pg_temp.sid('calendar'),pg_temp.sid('tenant'),pg_temp.sid('entity'),'SELFCAL','Synthetic calendar',pg_temp.sid('a'),pg_temp.sid('a'));
insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,start_date,end_date_exclusive,timezone,weekly_intervals,date_overrides,published_by)
select pg_temp.sid('calendar.version'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('calendar'),current_date-40,current_date+400,'UTC',
 jsonb_agg(jsonb_build_object('day_of_week',day,'start_minute',540,'end_minute',1020,'end_day_offset',0) order by day),'[]',pg_temp.sid('a')
from generate_series(1,7) day;
insert into people.departments(id,tenant_id,legal_entity_id,code) values(pg_temp.sid('department'),pg_temp.sid('tenant'),pg_temp.sid('entity'),'SELF');
insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,start_date,end_date_exclusive,reason,recorded_by)
values(pg_temp.sid('department.version'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('department'),'Synthetic department',
 current_date-40,current_date+400,'Synthetic self fixture',pg_temp.sid('a'));
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.sid(label||'.organization'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid(label||'.employee'),
 pg_temp.sid(label||'.spell'),pg_temp.sid('department'),pg_temp.sid('calendar.version'),'Synthetic role',current_date-40,current_date+400,
 'Synthetic self fixture',pg_temp.sid('a') from unnest(array['a','b']) label;
insert into people.leave_policies(id,tenant_id,legal_entity_id,code,name,created_by)
values(pg_temp.sid('policy'),pg_temp.sid('tenant'),pg_temp.sid('entity'),'SELFLEAVE','Synthetic leave',pg_temp.sid('a'));
insert into people.leave_policy_versions(id,tenant_id,legal_entity_id,policy_id,version,start_date,end_date_exclusive,unit,day_seconds,
 accrual_frequency,accrual_seconds,carry_cap_seconds,expiry_days,eligible_types,allow_unpaid,reason,published_by)
values(pg_temp.sid('policy.version'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('policy'),1,current_date-40,current_date+400,
 'hours',28800,'once',7200,0,365,array['permanent'],false,'Synthetic self fixture',pg_temp.sid('a'));
insert into people.leave_grants(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,policy_version_id,source_kind,source_key,effective_date,expiry_date,seconds,reason,recorded_by)
select pg_temp.sid(label||'.grant'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid(label||'.employee'),
 pg_temp.sid('policy'),pg_temp.sid('policy.version'),'adjustment',label||'.synthetic',current_date-1,current_date+365,7200,'Synthetic self fixture',pg_temp.sid('a')
from unnest(array['a','b']) label;

-- Real scoped attendance rows exercise bounded paging, foreign cursor and version binding.
insert into people.attendance_entries(id,tenant_id,legal_entity_id,branch_id,employee_id,current_revision_id,status,created_by)
select pg_temp.sid('attendance.'||i),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 pg_temp.sid('attendance.revision.'||i),'submitted',pg_temp.sid('a') from generate_series(1,51) i;
insert into people.attendance_entries(id,tenant_id,legal_entity_id,branch_id,employee_id,current_revision_id,status,created_by)
values(pg_temp.sid('attendance.b'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('b.employee'),
 pg_temp.sid('attendance.revision.b'),'submitted',pg_temp.sid('b'));
insert into people.attendance_revisions(id,tenant_id,legal_entity_id,branch_id,employee_id,entry_id,version,calendar_version_id,
 start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,gross_seconds,break_seconds,payable_seconds,reason,recorded_by)
select a.current_revision_id,a.tenant_id,a.legal_entity_id,a.branch_id,a.employee_id,a.id,1,pg_temp.sid('calendar.version'),
 (current_date-1)::timestamp+interval '9 hours',0,(current_date-1)::timestamp+interval '10 hours',0,
 ((current_date-1)::timestamp+interval '9 hours') at time zone 'UTC',((current_date-1)::timestamp+interval '10 hours') at time zone 'UTC',
 3600,0,3600,'Synthetic attendance',pg_temp.sid('a') from people.attendance_entries a where a.tenant_id=pg_temp.sid('tenant');

insert into people_private.policies(id,tenant_id,legal_entity_id,purpose,created_by)
values(pg_temp.sid('hr.policy'),pg_temp.sid('tenant'),pg_temp.sid('entity'),'Synthetic self publication fixture',pg_temp.sid('a'));
insert into people_private.reviews(id,tenant_id,legal_entity_id,branch_id,employee_id,reviewer_id,policy_id,revision_id,status,start_date,end_date_exclusive,created_by)
select pg_temp.sid('review.'||status),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),pg_temp.sid('b.employee'),
 pg_temp.sid('hr.policy'),pg_temp.sid('review.revision.'||status),status,current_date-1,current_date+1,pg_temp.sid('b')
from unnest(array['draft','submitted','reviewed']) status;

insert into people_private.review_revisions(id,tenant_id,legal_entity_id,employee_id,review_id,body,reason,digest,recorded_by)
select pg_temp.sid('review.revision.'||status),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('a.employee'),pg_temp.sid('review.'||status),
 jsonb_build_object('comments','Synthetic '||status),'Synthetic internal reason',repeat('a',64),pg_temp.sid('b')
from unnest(array['draft','submitted','reviewed']) status;
set constraints all immediate;
-- Validate the seed graph, then restore the installed command contract: an
-- attendance create writes its entry and revision under a deferred cyclic FK.
set constraints all deferred;

-- Minimal immutable issued payroll fixtures exercise positive own detail and
-- exact revision linkage without invoking any financial posting command.
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.sid('pay.net'),pg_temp.sid('tenant'),pg_temp.sid('entity'),'SELFNET','Synthetic payroll control','liability','credit',pg_temp.sid('a'),pg_temp.sid('a'));
insert into people_payroll.settings_versions(id,tenant_id,legal_entity_id,version,net_account_id,reason,published_by)
values(pg_temp.sid('pay.settings'),pg_temp.sid('tenant'),pg_temp.sid('entity'),1,pg_temp.sid('pay.net'),'Synthetic self fixture',pg_temp.sid('a'));
insert into people_payroll.runs(id,tenant_id,legal_entity_id,branch_id,name,start_date,end_date_exclusive,posting_date,currency_code,status,created_by)
values(pg_temp.sid('pay.run'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'Synthetic self fixture',current_date-10,current_date,current_date,'LKR','posted',pg_temp.sid('a'));
insert into people_payroll.run_revisions(id,tenant_id,legal_entity_id,run_id,version,settings_version_id,digest,employee_count,prepared_by)
values(pg_temp.sid('pay.revision'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('pay.run'),1,pg_temp.sid('pay.settings'),repeat('b',64),2,pg_temp.sid('a'));
insert into people_payroll.run_employees(tenant_id,legal_entity_id,branch_id,run_id,employee_id)
select pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.run'),pg_temp.sid(label||'.employee') from unnest(array['a','b']) label;
insert into people_payroll.employee_calculations(id,tenant_id,legal_entity_id,run_id,revision_id,employee_id,inputs,input_digest,calculation,gross,deductions,employer_cost,net)
select pg_temp.sid('pay.calculation.'||label),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('pay.run'),pg_temp.sid('pay.revision'),pg_temp.sid(label||'.employee'),
 jsonb_build_object('employee_code',upper(label),'employee_name','Synthetic '||label,'private_input','MUST_NOT_APPEAR'),repeat('c',64),
 '{"lines":[{"code":"BASE","classification":"earning","amount":"100.000000","internal_source":"MUST_NOT_APPEAR"}]}',100,0,0,100 from unnest(array['a','b']) label;
insert into people_payroll.payslips(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,revision_digest)
select pg_temp.sid('pay.payslip.'||label),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.run'),pg_temp.sid(label||'.employee'),
 pg_temp.sid('pay.calculation.'||label),repeat('b',64) from unnest(array['a','b']) label;
insert into people_payroll.corrections(id,tenant_id,legal_entity_id,branch_id,original_calculation_id,employee_id,original_run_id,chain_version,
 posting_date,currency_code,status,digest,before_calculation,after_calculation,difference,prepared_by,reason)
select pg_temp.sid('pay.correction.'||status),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.calculation.a'),
 pg_temp.sid('a.employee'),pg_temp.sid('pay.run'),case when status='posted' then 1 else 0 end,current_date,'LKR',status,repeat('d',64),
 '{"net":"100.000000"}','{"net":"110.000000"}','{"net":"10.000000"}',pg_temp.sid('b'),'INTERNAL_CORRECTION_REASON'
from unnest(array['prepared','posted']) status;
insert into people_payroll.correction_payslips(id,tenant_id,legal_entity_id,branch_id,correction_id,employee_id,payload,digest)
select pg_temp.sid('pay.correction.payslip.'||status),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.correction.'||status),
 pg_temp.sid('a.employee'),jsonb_build_object('employee_id',pg_temp.sid('a.employee'),'currency_code','LKR','before',jsonb_build_object('net','100.000000'),
 'after',jsonb_build_object('net','110.000000','private_source','MUST_NOT_APPEAR',
  'lines',jsonb_build_array(jsonb_build_object('code','BASE','classification','earning','amount','110.000000','internal_source','MUST_NOT_APPEAR'))),
 'difference',jsonb_build_object('net','10.000000','private_source','MUST_NOT_APPEAR',
  'lines',jsonb_build_array(jsonb_build_object('code','BASE','classification','earning','difference','10.000000',
   'before',jsonb_build_object('code','BASE','classification','earning','amount','100.000000','internal_source','MUST_NOT_APPEAR'),
   'after',jsonb_build_object('code','BASE','classification','earning','amount','110.000000','internal_source','MUST_NOT_APPEAR')))),
 'internal_reason','MUST_NOT_APPEAR'),repeat('d',64)
from unnest(array['prepared','posted']) status;

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='employee_self' and relkind='r'),'every employee self table enforces RLS');
select ok(not has_schema_privilege('authenticated','employee_self','USAGE'),'private self schema is not browsable');
select ok(not has_table_privilege('service_role','employee_self.receipts','SELECT'),'service has no direct receipt content access');
select ok(not has_function_privilege('anon','api.employee_self_leave_submit(uuid,uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE'),'anonymous cannot submit');
select ok(not exists(select 1 from core.role_permissions where role_id=pg_temp.sid('self-role') and permission_code in
 ('people.attendance.view','people.attendance.manage','people.attendance.approve','people.leave.view','people.leave.manage','people.leave.approve','people.payroll.payslip.view')),
 'ordinary employee needs no staff-wide permission');
select pg_temp.self_actor('a','aal1');
select throws_ok($$select employee_self.require_subject(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'people.hr.erase')$$,
 '42501','EMPLOYEE_CAPABILITY_INVALID','private helper rejects a staff-wide capability');
set local role authenticated;
insert into self_results values('attendance-first',api.employee_self_attendance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch')));
select is(jsonb_array_length((select value->'items' from self_results where name='attendance-first')),50,'own attendance page has at most 50 rows');
select ok((select bool_and(value->>'employee_id'=pg_temp.sid('a.employee')::text) from jsonb_array_elements(
 (select value->'items' from self_results where name='attendance-first'))),'every attendance subject is the accepted employee');
select is(jsonb_array_length(api.employee_self_attendance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
 (select (value->>'next_cursor')::uuid from self_results where name='attendance-first'))->'items'),1,'second page returns the remaining own row');
select throws_ok($$select api.employee_self_attendance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('attendance.b'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','another employee cursor is refused');
select throws_ok($$select api.employee_self_attendance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('other-branch'))$$,
 '42501',null,'another branch is refused before rows are read');
select throws_ok($$select pg_temp.self_capture('capture.a','capture.a')$$,'42501','EMPLOYEE_MFA_REQUIRED','capture requires MFA even a non-MFA role');
select throws_ok($$select pg_temp.self_submit('leave.a','leave.a')$$,'42501','EMPLOYEE_MFA_REQUIRED','leave submit requires MFA');
select throws_ok($$select api.employee_self_payslips(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))$$,
 '42501','EMPLOYEE_MFA_REQUIRED','payslip self requires MFA');
select is(jsonb_array_length(api.employee_self_reviews(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items'),1,
 'employee reviews contain published reviewed content only');
select throws_ok($$select api.employee_self_reviews(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('review.draft'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','unpublished review cannot serve as a cursor');
reset role;

-- Broad review permission must not switch this dedicated endpoint into a staff projection.
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.sid('tenant'),pg_temp.sid('self-role'),'people.reviews.view');
select pg_temp.self_actor('a');
set local role authenticated;
insert into self_results values('payslip',api.employee_self_payslip(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.a')));
select is(jsonb_array_length(api.employee_self_payslips(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items'),1,'own issued payslip summary excludes second employee');
select ok(not ((api.employee_self_payslips(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))#>'{items,0}') ? 'lines'),'summary omits component detail');
select is((select value#>>'{payslip,payslip_revision_id}' from self_results where name='payslip'),pg_temp.sid('pay.revision')::text,'own detail provides exact immutable revision UUID for a payroll question');
select is((select value#>>'{payslip,lines,0,code}' from self_results where name='payslip'),'BASE','own issued component detail is present');
select ok((select value::text not like '%MUST_NOT_APPEAR%' from self_results where name='payslip'),'private calculation inputs do not escape the own projection');
select throws_ok($$select api.employee_self_payslip(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.b'))$$,
 '42501','EMPLOYEE_SUBJECT_DENIED','foreign issued payslip detail is denied');
select throws_ok($$select api.employee_self_payslips(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.b'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','foreign payslip cannot control summary paging');
insert into self_results values('corrections',api.employee_self_payslip_corrections(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.a')));
select is(jsonb_array_length((select value->'items' from self_results where name='corrections')),1,'only issued posted correction is disclosed');
select ok((select value::text not like '%MUST_NOT_APPEAR%' and value::text not like '%INTERNAL_CORRECTION_REASON%' from self_results where name='corrections'),'correction projection omits internal fields and reason');
select is((select value#>>'{items,0,payload,after,lines,0,amount}' from self_results where name='corrections'),'110.000000','correction keeps the own component amount while filtering nested internal fields');
select is((select value#>>'{items,0,payload,difference,lines,0,difference}' from self_results where name='corrections'),'10.000000','correction keeps its own component delta');
select throws_ok($$select api.employee_self_payslip_corrections(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.a'),pg_temp.sid('pay.correction.payslip.prepared'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','unpublished correction cannot act as a paging cursor');
select is(jsonb_array_length(api.employee_self_reviews(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items'),1,
 'dual-role employee still sees only reviewed own content');
select is((api.employee_self_leave_policies(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),current_date)#>>'{items,0,calendar_version_id}'),
 pg_temp.sid('calendar.version')::text,'leave policy exposes the linked effective calendar');
select is(api.employee_self_leave_balance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('policy'),current_date)->>'available_seconds',
 '7200','own balance uses exact seconds from the existing ledger');
select throws_ok($$select api.employee_self_leave_policies(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'infinity')$$,
 '22023','LEAVE_DATE_INVALID','infinite policy dates are rejected');
reset role;
update core.branches set timezone='Pacific/Kiritimati' where id=pg_temp.sid('branch');
set local role authenticated;
insert into self_results values('local-policies',api.employee_self_leave_policies(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch')));
select is((select value->>'as_of' from self_results where name='local-policies'),(statement_timestamp() at time zone 'Pacific/Kiritimati')::date::text,
 'initial leave policy date is derived in the workplace timezone');
select is((select value#>>'{items,0,as_of}' from self_results where name='local-policies'),(select value->>'as_of' from self_results where name='local-policies'),
 'each policy carries the authoritative balance date');
select is(api.employee_self_leave_balance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('policy'))->>'as_of',
 (statement_timestamp() at time zone 'Pacific/Kiritimati')::date::text,'omitted balance date also uses the workplace timezone');
reset role;
update core.branches set timezone='Etc/GMT+12' where id=pg_temp.sid('branch');
set local role authenticated;
select isnt(api.employee_self_leave_policies(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->>'as_of',
 (select value->>'as_of' from self_results where name='local-policies'),'server dates differ across the international date line instead of using a device date');
reset role;
update core.branches set timezone='UTC' where id=pg_temp.sid('branch');
update people_payroll.runs set status='prepared' where id=pg_temp.sid('pay.run');
set local role authenticated;
select is(jsonb_array_length(api.employee_self_payslips(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items'),0,
 'an unposted payroll run is not an employee publication');
select throws_ok($$select api.employee_self_payslip(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.a'))$$,
 '42501','EMPLOYEE_SUBJECT_DENIED','unposted run detail is denied even if an administrator created a payslip row');
select throws_ok($$select api.employee_self_payslips(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.a'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','an unpublished payslip is not a valid cursor');
select throws_ok($$select api.employee_self_payslip_corrections(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.payslip.a'))$$,
 '42501','EMPLOYEE_SUBJECT_DENIED','correction history requires the original own publication');
reset role;
update people_payroll.runs set status='posted' where id=pg_temp.sid('pay.run');
set local role authenticated;
insert into self_results values('capture',pg_temp.self_capture('capture.a','capture.a'));
select is((select value->>'status' from self_results where name='capture'),'pending_evidence','capture receipt explicitly remains pending evidence');
select is(pg_temp.self_capture('capture.a','capture.a'),(select value from self_results where name='capture'),'identical capture command is replayed');
select is(api.employee_self_receipt(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('capture.a'),
 pg_temp.sid('capture.a'),'employee_self_attendance_request')->'receipt',(select value from self_results where name='capture'),
 'opaque receipt recovery does not require retaining the sensitive request body');
select throws_ok($$select api.employee_self_receipt(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('capture.a'),
 pg_temp.sid('different.capture'),'employee_self_attendance_request')$$,'42501','EMPLOYEE_RECEIPT_DENIED','receipt recovery binds the exact original target');
select throws_ok($$select api.employee_self_receipt(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('capture.a'),
 pg_temp.sid('capture.a'),'employee_self_leave_submit')$$,'42501','EMPLOYEE_RECEIPT_DENIED','receipt recovery binds the exact original RPC');
insert into self_results values('abandoned',api.employee_self_receipt(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
 pg_temp.sid('never.dispatched'),pg_temp.sid('never.dispatched'),'employee_self_attendance_request'));
select ok((select value->'receipt'='null'::jsonb and value->'abandoned'='true'::jsonb
 and value->>'command_id'=pg_temp.sid('never.dispatched')::text and value->>'request_id'=pg_temp.sid('never.dispatched')::text
 and value->>'rpc'='employee_self_attendance_request' from self_results where name='abandoned'),'absent opaque command is durably fenced with exact binding');
select throws_ok($$select pg_temp.self_capture('never.dispatched','never.dispatched')$$,
 '55000','EMPLOYEE_COMMAND_ABANDONED','a delayed original request cannot commit after receipt recovery fenced its absence');
select throws_ok($$select pg_temp.self_capture('capture.a','capture.a',pg_temp.capture_body()||'{"reason":"Changed"}')$$,
 '22023','EMPLOYEE_COMMAND_REUSED','changed capture retry cannot reuse the receipt');
select throws_ok($$select pg_temp.self_capture('capture.subject','capture.subject',pg_temp.capture_body()||jsonb_build_object('employee_id',pg_temp.sid('b.employee')))$$,
 '22023','HR_FIELDS_INVALID','employee selector is never accepted as request data');
select throws_ok($$select pg_temp.self_capture('capture.foreign','capture.foreign',pg_temp.capture_body()||jsonb_build_object(
 'action','correction','entry_id',pg_temp.sid('attendance.b'),'expected_version',1))$$,
 '42501','EMPLOYEE_SUBJECT_DENIED','correction cannot target another employee attendance');
select throws_ok($$select pg_temp.self_capture('capture.stale','capture.stale',pg_temp.capture_body()||jsonb_build_object(
 'action','correction','entry_id',pg_temp.sid('attendance.1'),'expected_version',2))$$,
 '40001','VERSION_CONFLICT','correction binds the observed attendance version');
select is(pg_temp.self_capture('correction.a','correction.a',pg_temp.capture_body()||jsonb_build_object(
 'action','correction','entry_id',pg_temp.sid('attendance.1'),'expected_version',1))->>'status','pending_evidence','valid correction is attributable pending evidence');
insert into self_results values('leave',pg_temp.self_submit('leave.a','leave.a'));
select is((select value->>'status' from self_results where name='leave'),'submitted','own leave enters existing independent decision lifecycle');
select is(pg_temp.self_submit('leave.a','leave.a'),(select value from self_results where name='leave'),'identical leave retry returns the original acknowledgement');
select throws_ok($$select pg_temp.self_submit('leave.a','leave.a',pg_temp.leave_body()||'{"reason":"Changed"}')$$,
 '22023','EMPLOYEE_COMMAND_REUSED','changed leave body is refused on replay');
select throws_ok($$select pg_temp.self_submit('leave.subject','leave.subject',pg_temp.leave_body()||jsonb_build_object('employee_id',pg_temp.sid('b.employee')))$$,
 '22023','HR_FIELDS_INVALID','leave submission has no authoritative employee input');
select throws_ok($$select pg_temp.self_submit('leave.overlap','leave.overlap')$$,
 '23514','WORK_INTERVAL_CONFLICT','another pending leave cannot overlap');
select throws_ok($$select pg_temp.self_submit('leave.balance','leave.balance',pg_temp.leave_body(10,12))$$,
 '23514','LEAVE_BALANCE_INSUFFICIENT','pending competing request consumes the available reservation budget');
select throws_ok($$select pg_temp.self_submit('leave.version','leave.version',pg_temp.leave_body(10,11),1)$$,
 '40001','VERSION_CONFLICT','submission refuses a stale balance version');
select is(api.employee_self_leave_balance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('policy'),current_date)->>'reserved_seconds',
 '3600','pending request has a separate reservation projection');
select is(api.employee_self_leave_balance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('policy'),current_date)->>'available_seconds',
 '7200','submission does not debit the leave ledger');
select is(jsonb_array_length(api.employee_self_leave_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items'),1,'own leave history reads the submitted record');
select throws_ok($$select api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('withdraw.stale'),
 pg_temp.sid('leave.a'),'withdraw',2,'Synthetic withdrawal')$$,'40001','VERSION_CONFLICT','withdraw requires current request version');
insert into self_results values('withdraw',api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
 pg_temp.sid('withdraw.a'),pg_temp.sid('leave.a'),'withdraw',1,'Synthetic withdrawal'));
select is((select value->>'status' from self_results where name='withdraw'),'withdrawn','employee can withdraw only their submitted unapproved request');
select is(api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('withdraw.a'),
 pg_temp.sid('leave.a'),'withdraw',1,'Synthetic withdrawal'),(select value from self_results where name='withdraw'),'withdraw receipt replays after version transition');
select throws_ok($$select api.employee_self_payslip(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('foreign.payslip'))$$,
 '42501','EMPLOYEE_SUBJECT_DENIED','unknown or foreign issued payslip detail is denied');
reset role;
select is((select count(*) from people.leave_events where request_id=pg_temp.sid('leave.a') and action='cancel'
 and before_status='submitted' and after_status='cancelled' and actor_id=pg_temp.sid('a') and command_id=pg_temp.sid('withdraw.a')),1::bigint,
 'withdrawal appends exactly one attributable canonical leave cancellation event');
select is((select count(*) from people.leave_effects where employee_id=pg_temp.sid('a.employee')),0::bigint,'self commands never post leave debits or reversals');
select is((select count(*) from people.work_claims where employee_id=pg_temp.sid('a.employee')),0::bigint,'self commands never create payable work claims');
select is((select version from people.attendance_entries where id=pg_temp.sid('attendance.1')),1::bigint,'attendance correction request preserves the source revision');
select is((select count(*) from people.raw_clock_events where employee_id=pg_temp.sid('a.employee')),0::bigint,'capture request cannot impersonate a trusted clock import');
select throws_ok($$update employee_self.attendance_requests set reason='rewrite' where id=pg_temp.sid('capture.a')$$,
 '55000','EMPLOYEE_HISTORY_IMMUTABLE','attendance evidence history is immutable');

-- A trusted synthetic approved leave already has a claim and ledger debit.
-- Employee cancellation is an intent only; independent staff remains the owner.
insert into people.leave_requests(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,policy_version_id,calendar_version_id,
 start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,charge_seconds,status,reason,submitted_by,decided_by,created_by)
values(pg_temp.sid('leave.approved'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),pg_temp.sid('policy'),
 pg_temp.sid('policy.version'),pg_temp.sid('calendar.version'),(current_date+1)::timestamp+interval '12 hours',0,(current_date+1)::timestamp+interval '13 hours',0,
 ((current_date+1)::timestamp+interval '12 hours') at time zone 'UTC',((current_date+1)::timestamp+interval '13 hours') at time zone 'UTC',
 3600,'approved','Synthetic approved fixture',pg_temp.sid('a'),pg_temp.sid('b'),pg_temp.sid('a'));
update people.leave_requests set active_claim_id=people.make_work_claim(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 'leave',pg_temp.sid('leave.approved'),((current_date+1)::timestamp+interval '12 hours') at time zone 'UTC',((current_date+1)::timestamp+interval '13 hours') at time zone 'UTC',
 '[]',pg_temp.sid('calendar.version'),pg_temp.sid('b')) where id=pg_temp.sid('leave.approved');
select people.allocate_leave(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('a.employee'),pg_temp.sid('policy'),pg_temp.sid('leave.approved'),
 null,current_date+1,current_date,3600,pg_temp.sid('b'));
set local role authenticated;
insert into self_results values('cancel',api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('cancel.approved'),
 pg_temp.sid('leave.approved'),'cancel_request',1,'Synthetic cancellation request'));
select is((select value->>'status' from self_results where name='cancel'),'cancellation_requested','approved leave cancellation remains a request');
select is(api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('cancel.approved'),pg_temp.sid('leave.approved'),
 'cancel_request',1,'Synthetic cancellation request'),(select value from self_results where name='cancel'),'cancellation intent replays without duplicate effects');
select throws_ok($$select api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('cancel.duplicate'),pg_temp.sid('leave.approved'),
 'cancel_request',1,'Duplicate cancellation')$$,'55000','LEAVE_CANCELLATION_ALREADY_REQUESTED','same approved revision has only one pending cancellation intent');
select throws_ok($$select api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('withdraw.approved'),pg_temp.sid('leave.approved'),
 'withdraw',1,'Cannot withdraw approved')$$,'55000','LEAVE_WITHDRAWAL_INVALID','employee cannot use withdrawal to cancel approved leave');
reset role;
select is((select status from people.leave_requests where id=pg_temp.sid('leave.approved')),'approved','requesting cancellation preserves approval');
select is(people.leave_available(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('a.employee'),pg_temp.sid('policy'),current_date),3600::bigint,'requesting cancellation preserves the posted debit');
select ok((select c.active from people.leave_requests r join people.work_claims c on c.id=r.active_claim_id where r.id=pg_temp.sid('leave.approved')),'requesting cancellation preserves the approved claim');

-- A different accepted subject cannot read or withdraw the first subject request.
select pg_temp.self_actor('b');set local role authenticated;
select is(jsonb_array_length(api.employee_self_leave_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items'),0,'second employee history has no first-employee row');
select throws_ok($$select api.employee_self_leave_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('leave.a'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','leave cursor cannot select another subject');
select throws_ok($$select api.employee_self_leave_intent(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('foreign.withdraw'),
 pg_temp.sid('leave.a'),'withdraw',2,'Synthetic foreign attempt')$$,'42501','EMPLOYEE_SUBJECT_DENIED','another employee cannot withdraw a request');
reset role;

-- Authority is checked before replay, including revocation and retained expired sessions.
-- Staff queues consume these requests without granting staff permissions to the
-- employee role. Canonical transitions are exercised through their real owners.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values(pg_temp.sid('reviewer'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'reviewer@employee-self.rollback.invalid','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values(pg_temp.sid('reviewer.session'),pg_temp.sid('reviewer'),now(),now());
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.sid('reviewer.membership'),pg_temp.sid('tenant'),pg_temp.sid('reviewer'),'active');
insert into core.roles(id,tenant_id,code,name,requires_mfa)
values(pg_temp.sid('staff-role'),pg_temp.sid('tenant'),'employee.request.review','Synthetic workforce reviewer',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.sid('tenant'),pg_temp.sid('staff-role'),cap from unnest(array['people.view','people.attendance.view','people.attendance.manage',
 'people.attendance.approve','people.leave.view','people.leave.approve']) cap;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.sid('tenant'),pg_temp.sid(label||'.membership'),pg_temp.sid('staff-role'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a')
from unnest(array['b','reviewer']) label;
insert into self_results values('cancel-intent',jsonb_build_object('id',(select id from employee_self.leave_intents where request_id=pg_temp.sid('leave.approved') and action='cancel_request'),
 'balance_version',(select version from people.leave_accounts where employee_id=pg_temp.sid('a.employee') and policy_id=pg_temp.sid('policy'))));
select pg_temp.self_actor('a');set local role authenticated;
select throws_ok($$select api.employee_staff_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'attendance')$$,
 '42501',null,'ordinary employees cannot browse the staff intake queue');
reset role;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.sid('tenant'),pg_temp.sid('a.membership'),pg_temp.sid('staff-role'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('b'));
set local role authenticated;
select throws_ok($$select pg_temp.staff_resolve('self.decline','attendance',pg_temp.sid('capture.a'),'declined')$$,
 '42501','EMPLOYEE_INDEPENDENT_REVIEW_REQUIRED','even a dual-role employee cannot decide their own evidence');
reset role;
delete from core.role_assignments where membership_id=pg_temp.sid('a.membership') and role_id=pg_temp.sid('staff-role');
select pg_temp.self_actor('b','aal1');set local role authenticated;
select throws_ok($$select api.employee_staff_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'attendance')$$,
 '42501',null,'staff intake always requires current MFA');
reset role;
select pg_temp.self_actor('b');set local role authenticated;
select is(jsonb_array_length(api.employee_staff_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'attendance')->'items'),2,
 'staff queue exposes the two actual pending evidence requests');
select is(jsonb_array_length(api.employee_staff_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'leave_cancel')->'items'),1,
 'staff queue exposes the approved leave cancellation intent');
select throws_ok($$select api.employee_staff_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('other-branch'),'attendance')$$,
 '42501',null,'staff scope is rechecked before another branch queue');
select throws_ok($$select pg_temp.staff_resolve('resolve.foreign','attendance',pg_temp.sid('capture.a'),'resolved',pg_temp.sid('attendance.b'),1)$$,
 '42501','EMPLOYEE_CANONICAL_RECORD_REQUIRED','attendance intake cannot bind another employee record');
select throws_ok($$select pg_temp.staff_resolve('resolve.unapproved','attendance',pg_temp.sid('capture.a'),'resolved',pg_temp.sid('attendance.1'),1)$$,
 '55000','EMPLOYEE_CANONICAL_RECORD_REQUIRED','unapproved existing time is not fulfilled evidence');
insert into self_results values('staff-decline',pg_temp.staff_resolve('resolve.decline','attendance',pg_temp.sid('correction.a'),'declined'));
select is((select value->>'status' from self_results where name='staff-decline'),'declined','staff can append an attributable evidence decline');
select is(pg_temp.staff_resolve('resolve.decline','attendance',pg_temp.sid('correction.a'),'declined'),
 (select value from self_results where name='staff-decline'),'staff decision retry returns the original acknowledgement');
select throws_ok($$select pg_temp.staff_resolve('resolve.decline','attendance',pg_temp.sid('correction.a'),'declined',null,null,null,1,'Changed decision note')$$,
 '22023','EMPLOYEE_COMMAND_REUSED','staff receipt cannot be replayed with a changed note');
select throws_ok($$select pg_temp.staff_resolve('resolve.decline.again','attendance',pg_temp.sid('correction.a'),'declined')$$,
 '40001','VERSION_CONFLICT','another command cannot process the same intake revision twice');

select api.people_attendance_command(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('canonical.create'),pg_temp.sid('canonical.create'),now(),
 jsonb_build_object('action','create','id',pg_temp.sid('attendance.fulfilled'),'employee_id',pg_temp.sid('a.employee'),'calendar_version_id',pg_temp.sid('calendar.version'),
 'start_local',to_char((now() at time zone 'UTC')-interval '1 minute','YYYY-MM-DD"T"HH24:MI:SS'),'start_offset_seconds',0,
 'end_local',to_char((now() at time zone 'UTC')+interval '1 minute','YYYY-MM-DD"T"HH24:MI:SS'),'end_offset_seconds',0,'breaks','[]'::jsonb,
 'reason','Synthetic canonical attendance from employee evidence'),0);
select api.people_attendance_command(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('canonical.submit'),pg_temp.sid('canonical.submit'),now(),
 jsonb_build_object('action','submit','id',pg_temp.sid('attendance.fulfilled'),'employee_id',pg_temp.sid('a.employee'),'reason','Synthetic independent review submission'),1);
reset role;
select pg_temp.self_actor('reviewer');set local role authenticated;
select api.people_attendance_command(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('canonical.approve'),pg_temp.sid('canonical.approve'),now(),
 jsonb_build_object('action','approve','id',pg_temp.sid('attendance.fulfilled'),'employee_id',pg_temp.sid('a.employee'),'reason','Synthetic independent review'),2);
reset role;
select pg_temp.self_actor('b');set local role authenticated;
select throws_ok($$select pg_temp.staff_resolve('resolve.stale','attendance',pg_temp.sid('capture.a'),'resolved',pg_temp.sid('attendance.fulfilled'),2)$$,
 '40001','VERSION_CONFLICT','fulfillment binds the current canonical attendance version');
insert into self_results values('staff-fulfilled',pg_temp.staff_resolve('resolve.fulfilled','attendance',pg_temp.sid('capture.a'),'resolved',pg_temp.sid('attendance.fulfilled'),3));
select ok((select value->>'status'='resolved' and value->>'canonical_id'=pg_temp.sid('attendance.fulfilled')::text
 and value->'canonical_version'='3'::jsonb and value->'payable_time_changed'='false'::jsonb from self_results where name='staff-fulfilled'),
 'staff links independently approved attendance without inventing another payable effect');
insert into self_results values('staff-cancelled',pg_temp.staff_resolve('resolve.cancel','leave_cancel',
 (select (value->>'id')::uuid from self_results where name='cancel-intent'),'resolved',pg_temp.sid('leave.approved'),1,
 (select (value->>'balance_version')::bigint from self_results where name='cancel-intent')));
select ok((select value->>'status'='resolved' and value->'canonical_changed'='true'::jsonb and value->'canonical_version'='2'::jsonb
 from self_results where name='staff-cancelled'),'cancellation intent resolves through the actual canonical leave owner');
select is(pg_temp.staff_resolve('resolve.cancel','leave_cancel',(select (value->>'id')::uuid from self_results where name='cancel-intent'),
 'resolved',pg_temp.sid('leave.approved'),1,(select (value->>'balance_version')::bigint from self_results where name='cancel-intent')),
 (select value from self_results where name='staff-cancelled'),'cancel retry does not repeat a ledger reversal');
select is(jsonb_array_length(api.employee_staff_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'attendance')->'items'),0,
 'processed evidence leaves the pending staff queue');
select is(jsonb_array_length(api.employee_staff_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'leave_cancel')->'items'),0,
 'processed cancellation leaves the pending staff queue');
reset role;
select is((select status from people.leave_requests where id=pg_temp.sid('leave.approved')),'cancelled','staff resolution performs the canonical leave state transition');
select is(people.leave_available(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('a.employee'),pg_temp.sid('policy'),current_date),7200::bigint,
 'canonical cancellation reverses the exact posted leave debit');
select is((select count(*) from people.leave_effects where request_id=pg_temp.sid('leave.approved') and reversal_of is not null),1::bigint,
 'staff resolution makes exactly one canonical reversal');
select ok(not (select active from people.work_claims where source_kind='leave' and source_id=pg_temp.sid('leave.approved')),
 'canonical cancellation releases approved leave ownership');
select is((select count(*) from people.work_claims where source_kind='attendance' and source_id=
 (select current_revision_id from people.attendance_entries where id=pg_temp.sid('attendance.fulfilled'))),1::bigint,
 'linking evidence preserves the single canonical attendance claim');
delete from core.role_permissions where role_id=pg_temp.sid('staff-role') and permission_code='people.attendance.approve';
set local role authenticated;
select throws_ok($$select pg_temp.staff_resolve('resolve.decline','attendance',pg_temp.sid('correction.a'),'declined')$$,
 '42501',null,'revoked staff decision permission is checked before receipt recovery');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.sid('tenant'),pg_temp.sid('staff-role'),'people.attendance.approve');
select pg_temp.self_actor('a');set local role authenticated;
select is((select item->>'status' from jsonb_array_elements(api.employee_self_attendance_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items') item
 where item->>'id'=pg_temp.sid('capture.a')::text),'resolved','employee can see independently resolved attendance evidence');
select is((select item#>>'{resolution,reason}' from jsonb_array_elements(api.employee_self_attendance_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items') item
 where item->>'id'=pg_temp.sid('correction.a')::text),'Synthetic employee-visible staff decision','employee can see the staff response to declined evidence');
select is((select item#>>'{cancellation_request,status}' from jsonb_array_elements(api.employee_self_leave_requests(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))->'items') item
 where item->>'id'=pg_temp.sid('leave.approved')::text),'resolved','employee leave history connects its cancellation request to the processed outcome');
reset role;

-- Authority is checked before replay, including revocation and retained expired sessions.
update people_private.account_links set status='revoked',version=version+1 where id=pg_temp.sid('a.link');
select pg_temp.self_actor('a');set local role authenticated;
select throws_ok($$select pg_temp.self_capture('capture.a','capture.a')$$,'42501','EMPLOYEE_ACTIVE_LINK_REQUIRED','revoked link cannot recover even an existing capture receipt');
select throws_ok($$select api.employee_self_receipt(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('capture.a'),
 pg_temp.sid('capture.a'),'employee_self_attendance_request')$$,'42501','EMPLOYEE_ACTIVE_LINK_REQUIRED','receipt-only recovery still checks current link authority');
select throws_ok($$select pg_temp.self_submit('leave.a','leave.a')$$,'42501','EMPLOYEE_ACTIVE_LINK_REQUIRED','revoked link cannot recover an existing leave receipt');
reset role;
update people_private.account_links set status='accepted',version=version+1 where id=pg_temp.sid('a.link');
update auth.sessions set not_after=statement_timestamp()-interval '1 minute' where id=pg_temp.sid('a.session');
set local role authenticated;
select throws_ok($$select pg_temp.self_capture('capture.a','capture.a')$$,'42501','EMPLOYEE_SESSION_REQUIRED','retained expired session cannot replay a command');
reset role;
update auth.sessions set not_after=null where id=pg_temp.sid('a.session');
update people.employment_assignments set end_date_exclusive=current_date where id=pg_temp.sid('a.assignment');
set local role authenticated;
select throws_ok($$select pg_temp.self_capture('capture.a','capture.a')$$,'42501','EMPLOYEE_ACTIVE_LINK_REQUIRED','ended current employment prevents replay despite accepted link');
reset role;
update people.employment_assignments set end_date_exclusive=null where id=pg_temp.sid('a.assignment');
update billing.tenant_subscriptions set trial_ends_at=now()-interval '1 minute' where tenant_id=pg_temp.sid('tenant');
set local role authenticated;
select throws_ok($$select pg_temp.self_submit('leave.a','leave.a')$$,'42501','PEOPLE_ENTITLEMENT_REQUIRED','expired subscription cannot replay a command');
reset role;
update billing.tenant_subscriptions set trial_ends_at=now()+interval '1 day' where tenant_id=pg_temp.sid('tenant');
delete from core.role_permissions where role_id=pg_temp.sid('self-role') and permission_code='people.attendance.self.request';
set local role authenticated;
select throws_ok($$select pg_temp.self_capture('capture.a','capture.a')$$,'42501',null,'removed exact self capability prevents receipt recovery');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.sid('tenant'),pg_temp.sid('self-role'),'people.attendance.self.request');
insert into employee_self.receipts(user_id,command_id,tenant_id,legal_entity_id,branch_id,employee_id,rpc,request_hash,response,created_at,expires_at)
values(pg_temp.sid('a'),pg_temp.sid('expired.capture'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 'employee_self_attendance_request',
 employee_self.request_hash(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),'attendance_request',
 jsonb_build_array(pg_temp.sid('expired.capture'),pg_temp.capture_body())),
 employee_self.envelope(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'))||
 jsonb_build_object('command_id',pg_temp.sid('expired.capture'),'request_id',pg_temp.sid('expired.capture'),'version',1,'status','pending_evidence','payable_time_changed',false),
 now()-interval '2 days',now()-interval '1 day');
set local role authenticated;
select throws_ok($$select pg_temp.self_capture('expired.capture','expired.capture')$$,'55000','EMPLOYEE_COMMAND_EXPIRED','expired receipt fails explicitly instead of recreating an old command');
select is(api.employee_self_receipt(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('expired.capture'),
 pg_temp.sid('expired.capture'),'employee_self_attendance_request')#>>'{receipt,status}','pending_evidence',
 'an expired redispatch lease does not destroy current-authority receipt-only recovery');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.sid('a'),'role','authenticated','aal','aal2')::text,true);
set local role authenticated;
select throws_ok($$select api.employee_self_attendance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))$$,
 '42501','EMPLOYEE_SESSION_REQUIRED','a subject JWT without a live session binding is refused');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.sid('a'),'role','authenticated','aal','aal2','session_id',pg_temp.sid('b.session'))::text,true);
set local role authenticated;
select throws_ok($$select api.employee_self_attendance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))$$,
 '42501','EMPLOYEE_SESSION_REQUIRED','another user session cannot be presented with the employee subject');
reset role;
select pg_temp.self_actor('outsider');set local role authenticated;
select throws_ok($$select api.employee_self_attendance(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'))$$,
 '42501',null,'unlinked nonmember cannot enter a self projection');
reset role;
select * from finish();
rollback;
