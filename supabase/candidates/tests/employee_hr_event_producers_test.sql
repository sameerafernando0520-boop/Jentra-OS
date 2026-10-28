-- ISOLATED LOCAL/CI ONLY. No hosted connection, installation, sender or finance posting.
-- All candidate definitions, synthetic rows, grants and event effects roll back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
\ir ../20261023090000_employee_push.sql
\ir ../20261025090000_employee_self_service.sql
\ir ../20261025100000_employee_cases_documents_notifications.sql
-- pg_get_functiondef deparses type/default names according to search_path.
-- Compare under one fixed path even when the TAP harness changes its own path.
create function pg_temp.hr_function_definition(p_function oid) returns text
language sql stable set search_path='' as $$select pg_catalog.pg_get_functiondef(p_function)$$;
create temporary table hr_event_preservation as select
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from core.permissions p) permissions,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from core.role_assignments p) assignments,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from core.role_permissions p) role_permissions,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from billing.plan_entitlements p) entitlements,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from supabase_migrations.schema_migrations p) ledger,
 (select count(*) from workflow.notifications) notices,
 (select count(*) from employee_push.deliveries) deliveries;
create temporary table hr_existing_functions as select p.oid,pg_temp.hr_function_definition(p.oid) definition,p.proacl
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('api','employee_self','employee_push','people','people_private','people_payroll') and p.prokind='f';
\ir ../20261027100000_employee_hr_event_producers.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from core.permissions p),
 (select permissions from hr_event_preservation),'producer preserves every permission row');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from core.role_assignments p),
 (select assignments from hr_event_preservation),'producer preserves every role assignment row');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from core.role_permissions p),
 (select role_permissions from hr_event_preservation),'producer preserves every role grant row');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from billing.plan_entitlements p),
 (select entitlements from hr_event_preservation),'producer preserves every plan entitlement row');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]'::jsonb)::text) from supabase_migrations.schema_migrations p),
 (select ledger from hr_event_preservation),'candidate preserves every migration ledger row');
select is((select count(*) from workflow.notifications),(select notices from hr_event_preservation),'candidate performs no inbox backfill');
select is((select count(*) from employee_push.deliveries),(select deliveries from hr_event_preservation),'candidate performs no outbox backfill');
select ok(not exists(select 1 from hr_existing_functions f left join pg_proc p on p.oid=f.oid
 where p.oid is null or pg_temp.hr_function_definition(p.oid) is distinct from f.definition or p.proacl is distinct from f.proacl),
 'all existing API, HR, notification and push function definitions/grants are preserved');
-- A scoped return/argument type reproduces the path-sensitive deparse without
-- editing a real API. Actual definition changes must still fail preservation.
create function pg_temp.hr_preservation_probe(c employee_self.cases) returns integer
language sql as $$select 1$$;
create temporary table hr_definition_probe as select
 pg_temp.hr_function_definition('pg_temp.hr_preservation_probe(employee_self.cases)'::regprocedure) definition;
set local search_path=employee_self,extensions,public,pg_catalog;
select is(pg_temp.hr_function_definition('pg_temp.hr_preservation_probe(employee_self.cases)'::regprocedure),
 (select definition from hr_definition_probe),'function preservation is independent of caller search path');
create or replace function pg_temp.hr_preservation_probe(c employee_self.cases) returns integer
language sql as $$select 2$$;
select isnt(pg_temp.hr_function_definition('pg_temp.hr_preservation_probe(employee_self.cases)'::regprocedure),
 (select definition from hr_definition_probe),'function preservation still detects a changed body');
set local search_path=extensions,public,pg_catalog;
select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""']
 and not has_function_privilege('anon',p.oid,'EXECUTE')
 and not has_function_privilege('authenticated',p.oid,'EXECUTE')
 and not has_function_privilege('service_role',p.oid,'EXECUTE'))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='employee_self'
 and p.proname in ('notify_attendance_event','notify_payroll_correction','notify_request_resolution')),
 'producer functions are trigger-only, security-definer and empty-search-path');
create function pg_temp.sid(label text) returns uuid language sql immutable as
 $$select md5('employee-hr-events-isolated-rollback-v1:'||label)::uuid$$;
create function pg_temp.actor(label text,level text default 'aal2') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.sid(label)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.sid(label),'role','authenticated',
  'aal',level,'session_id',pg_temp.sid(label||'.session'))::text,true);
end $$;
create function pg_temp.att(command text,action text,target text,expected bigint,days_ago integer default 3,end_hour integer default 10,
 employee text default 'a') returns jsonb language sql as $$
 select api.people_attendance_command(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
 pg_temp.sid(command),pg_temp.sid(command),statement_timestamp(),
 jsonb_build_object('action',action,'id',pg_temp.sid(target),'employee_id',pg_temp.sid(employee||'.employee'),
 'reason','PRIVATE_ATTENDANCE_REASON')||case when action in ('create','correct') then jsonb_build_object(
 'calendar_version_id',pg_temp.sid('calendar.version'),
 'start_local',to_char((current_date-days_ago)::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char((current_date-days_ago)::timestamp+make_interval(hours=>end_hour),'YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',0,'end_offset_seconds',0,'breaks','[]'::jsonb) else '{}'::jsonb end,expected)
$$;
create function pg_temp.register(device text,target text) returns jsonb language sql as $$
 select api.employee_push_register(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
 pg_temp.sid(device),target,'android',pg_temp.sid(device||'.register'))
$$;
create function pg_temp.capture(command text,request text) returns jsonb language sql as $$
 select api.employee_self_attendance_request(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
 pg_temp.sid(command),pg_temp.sid(request),jsonb_build_object('action','capture',
 'observed_at',to_char((current_date-1)::timestamp+interval '9 hours 30 minutes','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
 'reason','PRIVATE_INTAKE_REASON'))
$$;
create function pg_temp.resolve(command text,kind text,target text,decision text,canonical uuid default null,
 canonical_version bigint default null,balance_version bigint default null) returns jsonb language sql as $$
 select api.employee_staff_request_resolve(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),
 pg_temp.sid(command),kind,pg_temp.sid(target),decision,canonical,1,canonical_version,balance_version,'PRIVATE_STAFF_REASON')
$$;
create temporary table hr_results(name text primary key,value jsonb);
grant select,insert on hr_results to authenticated;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.sid(label),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 label||'@employee-self.rollback.invalid','',now(),now(),now() from unnest(array['a','b','outsider']) label;
insert into auth.sessions(id,user_id,created_at,updated_at)
select pg_temp.sid(label||'.session'),pg_temp.sid(label),now(),now() from unnest(array['a','b','outsider']) label;
insert into core.tenants(id,name,slug,created_by)
values(pg_temp.sid('tenant'),'Synthetic self rollback','employee-hr-events-isolated-rollback',pg_temp.sid('a'));
insert into core.legal_entities(id,tenant_id,name,code,timezone,created_by)
values(pg_temp.sid('entity'),pg_temp.sid('tenant'),'Synthetic entity','SELFQA','UTC',pg_temp.sid('a'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.sid(label),pg_temp.sid('tenant'),pg_temp.sid('entity'),'Synthetic '||label,
 case when label='branch' then 'SELF1' else 'SELF2' end,pg_temp.sid('a') from unnest(array['branch','other-branch']) label;
insert into billing.plans(code,name) values('employee_hr_events_isolated','Synthetic self plan');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('employee_hr_events_isolated','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.sid('tenant'),'employee_hr_events_isolated','trialing',5,now()+interval '2 days');
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


-- Two independent staff identities record and review time; self users gain no staff caps.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.sid(label),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 label||'@employee-hr-events.rollback.invalid','',now(),now(),now() from unnest(array['recorder','reviewer']) label;
insert into auth.sessions(id,user_id,created_at,updated_at)
select pg_temp.sid(label||'.session'),pg_temp.sid(label),now(),now() from unnest(array['recorder','reviewer']) label;
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.sid(label||'.membership'),pg_temp.sid('tenant'),pg_temp.sid(label),'active' from unnest(array['recorder','reviewer']) label;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
values(pg_temp.sid('staff-role'),pg_temp.sid('tenant'),'events.staff','Synthetic workforce reviewers',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.sid('tenant'),pg_temp.sid('staff-role'),cap from unnest(array['people.view','people.attendance.view',
 'people.attendance.manage','people.attendance.approve','people.leave.view','people.leave.manage','people.leave.approve']) cap;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.sid('tenant'),pg_temp.sid(label||'.membership'),pg_temp.sid('staff-role'),pg_temp.sid('entity'),
 pg_temp.sid('branch'),pg_temp.sid('recorder') from unnest(array['recorder','reviewer']) label;
select pg_temp.actor('a');set local role authenticated;
select is(pg_temp.register('device-a','SYNTHETIC_HR_FID_A_123456789012345')->>'status','active','recipient A has an authorized own push binding');
reset role;select pg_temp.actor('b');set local role authenticated;
select is(pg_temp.register('device-b','SYNTHETIC_HR_FID_B_123456789012345')->>'status','active','recipient B has a separate authorized binding');
reset role;

-- Exercise actual source-owning attendance commands, independent approval, and replay.
select pg_temp.actor('recorder');set local role authenticated;
select lives_ok($$select pg_temp.att('create-approved','create','entry-approved',0)$$,'authoritative attendance create succeeds');
select lives_ok($$select pg_temp.att('submit-approved','submit','entry-approved',1)$$,'authoritative attendance submit succeeds');
select throws_ok($$select pg_temp.att('self-approve','approve','entry-approved',2)$$,'55000','ATTENDANCE_INDEPENDENT_APPROVAL_REQUIRED','recorder cannot approve own time or manufacture an outcome');
reset role;
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant')),0::bigint,'draft, submit and rejected approval create no employee notice');
select pg_temp.actor('reviewer');set local role authenticated;
insert into hr_results values('approved',pg_temp.att('approve-approved','approve','entry-approved',2));
select is(pg_temp.att('approve-approved','approve','entry-approved',2),(select value from hr_results where name='approved'),'attendance command replay returns original receipt');
reset role;
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and aggregate_id=pg_temp.sid('entry-approved')),1::bigint,'approval and command retry produce one inbox row');
select is((select count(*) from employee_push.deliveries d join workflow.notifications n on n.id=d.notification_id
 where n.tenant_id=pg_temp.sid('tenant') and n.aggregate_id=pg_temp.sid('entry-approved') and d.installation_id=pg_temp.sid('device-a')),1::bigint,'approval queues the exact recipient device once');
select is((select count(*) from employee_push.deliveries where installation_id=pg_temp.sid('device-b')),0::bigint,'foreign employee device receives no approval');
select is((select count(*) from people.attendance_events where command_id=pg_temp.sid('approve-approved')),1::bigint,'retry creates no new authoritative event');
select pg_temp.actor('reviewer');set local role authenticated;
select lives_ok($$select pg_temp.att('cancel-approved','cancel','entry-approved',3)$$,'canonical cancellation succeeds');
reset role;
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and aggregate_id=pg_temp.sid('entry-approved')),2::bigint,'canonical cancellation adds one outcome notice');
select pg_temp.actor('recorder');set local role authenticated;
select lives_ok($$select pg_temp.att('create-rejected','create','entry-rejected',0,2)$$,'second attendance draft succeeds');
select lives_ok($$select pg_temp.att('submit-rejected','submit','entry-rejected',1)$$,'second attendance submission succeeds');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select lives_ok($$select pg_temp.att('reject-entry','reject','entry-rejected',2)$$,'independent rejection succeeds');
reset role;
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and aggregate_id=pg_temp.sid('entry-rejected')),1::bigint,'rejection creates one outcome notice');
select pg_temp.actor('recorder');set local role authenticated;
select lives_ok($$select pg_temp.att('create-corrected','create','entry-corrected',0,1)$$,'correction source draft succeeds');
select lives_ok($$select pg_temp.att('submit-corrected','submit','entry-corrected',1)$$,'correction source submission succeeds');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select lives_ok($$select pg_temp.att('approve-corrected','approve','entry-corrected',2)$$,'correction source approval succeeds');
reset role;select pg_temp.actor('recorder');set local role authenticated;
select lives_ok($$select pg_temp.att('correct-approved','correct','entry-corrected',3,1,11)$$,'source owner reopens approved attendance for correction');
select lives_ok($$select pg_temp.att('correct-draft','correct','entry-corrected',4,1,12)$$,'ordinary follow-up draft edit succeeds');
reset role;
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and aggregate_id=pg_temp.sid('entry-corrected')),2::bigint,'approved-to-draft correction notifies while draft edits stay silent');
select pg_temp.actor('recorder');set local role authenticated;
select lives_ok($$select pg_temp.att('resubmit-corrected','submit','entry-corrected',5)$$,'corrected draft is resubmitted through source owner');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select lives_ok($$select pg_temp.att('reapprove-corrected','approve','entry-corrected',6)$$,'corrected time is independently reapproved');
reset role;

-- Focused sealed-correction EVENT FIXTURE only: append a revision and its final
-- approved-to-approved canonical event. This does not establish payroll posting,
-- seal/claim replacement or linked finance acceptance.
insert into people.attendance_revisions(id,tenant_id,legal_entity_id,branch_id,employee_id,entry_id,version,calendar_version_id,
 start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,breaks,gross_seconds,break_seconds,payable_seconds,
 reason,supersedes_revision_id,recorded_by)
select pg_temp.sid('linked-revision'),r.tenant_id,r.legal_entity_id,r.branch_id,r.employee_id,r.entry_id,8,r.calendar_version_id,
 r.start_local,r.start_offset_seconds,r.end_local,r.end_offset_seconds,r.start_utc,r.end_utc,r.breaks,r.gross_seconds,r.break_seconds,
 r.payable_seconds,'PRIVATE_SEALED_REASON',r.id,pg_temp.sid('reviewer')
from people.attendance_entries a join people.attendance_revisions r on r.id=a.current_revision_id where a.id=pg_temp.sid('entry-corrected');
update people.attendance_entries set version=8,current_revision_id=pg_temp.sid('linked-revision') where id=pg_temp.sid('entry-corrected');
insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,entry_id,revision_id,action,before_status,after_status,reason,actor_id,command_id)
values(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),pg_temp.sid('entry-corrected'),
 pg_temp.sid('linked-revision'),'correct','approved','approved','PRIVATE_SEALED_REASON',pg_temp.sid('reviewer'),pg_temp.sid('sealed-event'));
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and aggregate_id=pg_temp.sid('entry-corrected')),4::bigint,'approved-to-approved linked source correction is not missed');
-- Distinct event insert at the same source version must still deduplicate.
insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,entry_id,revision_id,action,before_status,after_status,reason,actor_id,command_id)
values(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),pg_temp.sid('entry-corrected'),
 pg_temp.sid('linked-revision'),'correct','approved','approved','PRIVATE_SEALED_REASON',pg_temp.sid('reviewer'),pg_temp.sid('sealed-event-repeat'));
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and aggregate_id=pg_temp.sid('entry-corrected')),4::bigint,'source receipt suppresses repeated same-version event');
-- The source FK does not bind event.branch_id to revision.branch_id: producer must.
-- Reserve an unseen version so deduplication cannot mask a missing scope guard.
update people.attendance_entries set version=9 where id=pg_temp.sid('entry-corrected');
insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,entry_id,revision_id,action,before_status,after_status,reason,actor_id,command_id)
values(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('other-branch'),pg_temp.sid('a.employee'),pg_temp.sid('entry-corrected'),
 pg_temp.sid('linked-revision'),'approve','submitted','approved','PRIVATE_WRONG_SCOPE',pg_temp.sid('reviewer'),pg_temp.sid('wrong-scope-event'));
select is((select count(*) from employee_self.notification_events where tenant_id=pg_temp.sid('tenant') and source_id=pg_temp.sid('entry-corrected')),4::bigint,'wrong-branch event cannot even consume a source receipt');
insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,entry_id,revision_id,action,before_status,after_status,reason,actor_id,command_id)
select pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),pg_temp.sid('entry-corrected'),
 supersedes_revision_id,'correct','approved','approved','PRIVATE_STALE_REVISION',pg_temp.sid('reviewer'),pg_temp.sid('stale-revision-event')
from people.attendance_revisions where id=pg_temp.sid('linked-revision');
select is((select count(*) from employee_self.notification_events where tenant_id=pg_temp.sid('tenant') and source_id=pg_temp.sid('entry-corrected')),4::bigint,'stale-revision event cannot consume an unseen canonical source version');

-- Real employee intake plus staff decline RPC: outcome does not change time.
select pg_temp.actor('a');set local role authenticated;
select lives_ok($$select pg_temp.capture('capture-declined','intake-declined')$$,'employee creates pending attendance evidence');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
insert into hr_results values('declined',pg_temp.resolve('decline-intake','attendance','intake-declined','declined'));
select is(pg_temp.resolve('decline-intake','attendance','intake-declined','declined'),(select value from hr_results where name='declined'),'intake decision retry returns exact receipt');
reset role;
select is((select count(*) from workflow.notifications n join employee_self.request_resolutions r on r.id=n.aggregate_id
 where n.tenant_id=pg_temp.sid('tenant') and r.attendance_request_id=pg_temp.sid('intake-declined')),1::bigint,'declined attendance intake and retry produce one decision notice');
select is((select value->>'payable_time_changed' from hr_results where name='declined'),'false','intake decline does not claim payable-time changes');
select is((select count(*) from people.attendance_entries where tenant_id=pg_temp.sid('tenant')),3::bigint,'intake decision creates no canonical attendance');

-- Synthetic immutable decision rows focus the other source branches. Existing
-- staff RPC validation is covered separately by employee_self_service tests.
insert into employee_self.attendance_requests(id,tenant_id,legal_entity_id,branch_id,employee_id,action,observed_at,reason,created_by,command_id)
values(pg_temp.sid('intake-resolved'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 'capture',now(),'PRIVATE_INTAKE_REASON',pg_temp.sid('a'),pg_temp.sid('capture-resolved'));
insert into employee_self.request_resolutions(id,kind,tenant_id,legal_entity_id,branch_id,employee_id,attendance_request_id,
 decision,canonical_id,canonical_version,reason,created_by,command_id)
values(pg_temp.sid('resolution-resolved'),'attendance',pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 pg_temp.sid('intake-resolved'),'resolved',pg_temp.sid('entry-corrected'),9,'PRIVATE_STAFF_REASON',pg_temp.sid('reviewer'),pg_temp.sid('resolve-intake'));
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('resolution-resolved')),1::bigint,'resolved intake has its own immutable decision identity');

insert into people.leave_requests(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,policy_version_id,calendar_version_id,
 start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,charge_seconds,status,reason,created_by,submitted_by,decided_by)
select pg_temp.sid('leave-'||label),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 pg_temp.sid('policy'),pg_temp.sid('policy.version'),pg_temp.sid('calendar.version'),(current_date+1)::timestamp+interval '9 hours',0,
 (current_date+1)::timestamp+interval '10 hours',0,((current_date+1)::timestamp+interval '9 hours') at time zone 'UTC',
 ((current_date+1)::timestamp+interval '10 hours') at time zone 'UTC',3600,'approved','PRIVATE_LEAVE_REASON',pg_temp.sid('recorder'),pg_temp.sid('recorder'),pg_temp.sid('reviewer')
from unnest(array['declined','resolved']) label;
insert into employee_self.leave_intents(id,tenant_id,legal_entity_id,branch_id,employee_id,request_id,request_version,action,status,reason,created_by,command_id)
select pg_temp.sid('leave-intent-'||label),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 pg_temp.sid('leave-'||label),1,'cancel_request','cancellation_requested','PRIVATE_CANCEL_REASON',pg_temp.sid('a'),pg_temp.sid('request-cancel-'||label)
from unnest(array['declined','resolved']) label;
select pg_temp.actor('reviewer');set local role authenticated;
select lives_ok($$select pg_temp.resolve('decline-cancel','leave_cancel','leave-intent-declined','declined')$$,'staff decline of cancellation uses authorized intake owner');
reset role;
select is((select count(*) from workflow.notifications n join employee_self.request_resolutions r on r.id=n.aggregate_id
 where r.leave_intent_id=pg_temp.sid('leave-intent-declined')),1::bigint,'declined leave cancellation gets its previously missing notice');
select is((select status from people.leave_requests where id=pg_temp.sid('leave-declined')),'approved','declining cancellation preserves canonical approved leave');
-- A canonical cancellation already supplies the existing leave notice.
update people.leave_requests set status='cancelled',version=2 where id=pg_temp.sid('leave-resolved');
insert into employee_self.request_resolutions(id,kind,tenant_id,legal_entity_id,branch_id,employee_id,leave_intent_id,
 decision,canonical_id,canonical_version,reason,created_by,command_id)
values(pg_temp.sid('resolution-leave-resolved'),'leave_cancel',pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('a.employee'),
 pg_temp.sid('leave-intent-resolved'),'resolved',pg_temp.sid('leave-resolved'),2,'PRIVATE_CANCEL_REASON',pg_temp.sid('reviewer'),pg_temp.sid('resolve-cancel'));
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('leave-resolved')),2::bigint,'existing leave producer covers approval and cancellation');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('resolution-leave-resolved')),0::bigint,'resolved cancellation adds no duplicate decision wake');
-- Minimal payroll source FIXTURES only, with no payroll/finance posting commands.
-- Transitions exercise the producer after immutable issued slips exist; they do
-- not establish journal accounting, statutory readiness or payroll acceptance.
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.sid('pay.net'),pg_temp.sid('tenant'),pg_temp.sid('entity'),'HRNET','Synthetic payroll control','liability','credit',pg_temp.sid('recorder'),pg_temp.sid('recorder'));
insert into people_payroll.settings_versions(id,tenant_id,legal_entity_id,version,net_account_id,reason,published_by)
values(pg_temp.sid('pay.settings'),pg_temp.sid('tenant'),pg_temp.sid('entity'),1,pg_temp.sid('pay.net'),'Synthetic source fixture',pg_temp.sid('recorder'));
insert into people_payroll.runs(id,tenant_id,legal_entity_id,branch_id,name,start_date,end_date_exclusive,posting_date,currency_code,status,created_by)
values(pg_temp.sid('pay.run'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),'Synthetic source fixture',current_date-10,current_date,current_date,'LKR','posted',pg_temp.sid('recorder'));
insert into people_payroll.run_revisions(id,tenant_id,legal_entity_id,run_id,version,settings_version_id,digest,employee_count,prepared_by)
values(pg_temp.sid('pay.revision'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('pay.run'),1,pg_temp.sid('pay.settings'),repeat('b',64),1,pg_temp.sid('recorder'));
insert into people_payroll.run_employees(tenant_id,legal_entity_id,branch_id,run_id,employee_id)
values(pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.run'),pg_temp.sid('a.employee'));
insert into people_payroll.employee_calculations(id,tenant_id,legal_entity_id,run_id,revision_id,employee_id,inputs,input_digest,calculation,gross,deductions,employer_cost,net)
values(pg_temp.sid('pay.calculation'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('pay.run'),pg_temp.sid('pay.revision'),pg_temp.sid('a.employee'),
 '{"private_input":"PRIVATE_PAY_INPUT"}',repeat('c',64),'{"net":"100.000000"}',100,0,0,100);
insert into people_payroll.payslips(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,revision_digest)
values(pg_temp.sid('pay.payslip'),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.run'),pg_temp.sid('a.employee'),pg_temp.sid('pay.calculation'),repeat('b',64));
insert into people_payroll.corrections(id,tenant_id,legal_entity_id,branch_id,original_calculation_id,employee_id,original_run_id,chain_version,
 posting_date,currency_code,status,digest,before_calculation,after_calculation,difference,prepared_by,reason)
select pg_temp.sid('correction-'||label),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('pay.calculation'),
 pg_temp.sid('a.employee'),pg_temp.sid('pay.run'),0,current_date,'LKR','prepared',repeat('d',64),
 '{"net":"100.000000"}','{"net":"110.000000"}','{"net":"10.000000"}',pg_temp.sid('recorder'),'PRIVATE_CORRECTION_REASON'
from unnest(array['one','two','no-slip','wrong-employee']) label;
insert into people_payroll.correction_payslips(id,tenant_id,legal_entity_id,branch_id,correction_id,employee_id,payload,digest)
select pg_temp.sid('correction-slip-'||label),pg_temp.sid('tenant'),pg_temp.sid('entity'),pg_temp.sid('branch'),pg_temp.sid('correction-'||label),
 pg_temp.sid(case when label='wrong-employee' then 'b.employee' else 'a.employee' end),
 '{"net":"110.000000","private_reason":"PRIVATE_CORRECTION_REASON"}',repeat('d',64)
from unnest(array['one','two','wrong-employee']) label;
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and notification_type='people.employee.pay'),0::bigint,'prepared corrections and unpublished slips do not notify');
update people_payroll.corrections set status='approved',version=2,approved_by=pg_temp.sid('reviewer'),approved_digest=digest where id=pg_temp.sid('correction-one');
select is((select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant') and notification_type='people.employee.pay'),0::bigint,'internal correction approval does not notify');
update people_payroll.corrections set status='posted',version=3 where id=pg_temp.sid('correction-one');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-one')),1::bigint,'issued correction posting creates one pay notice');
select is((select source_context->>'source_version' from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-one')),'3','pay source identity uses correction version');
update people_payroll.corrections set status='posted',version=3 where id=pg_temp.sid('correction-one');
update people_payroll.corrections set version=4 where id=pg_temp.sid('correction-one');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-one')),1::bigint,'no-op and version-only updates do not manufacture pay events');
update people_payroll.corrections set status='reversed',version=5 where id=pg_temp.sid('correction-one');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-one')),2::bigint,'reversal emits a distinct correction version');
update people_payroll.corrections set status='posted',version=3 where id in(pg_temp.sid('correction-two'),pg_temp.sid('correction-no-slip'),pg_temp.sid('correction-wrong-employee'));
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-two')),1::bigint,'a second correction at the same version has a separate slip identity');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('pay.payslip')),0::bigint,'correction notices never reuse the original payslip identity');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-wrong-employee')),0::bigint,'mismatched correction-slip employee is rejected by exact source join');
select is((select count(*) from employee_self.notification_events where tenant_id=pg_temp.sid('tenant') and destination='pay'),3::bigint,'correction without an issued slip or with wrong employee consumes no extra notification receipt');
select is((select count(*) from finance.journal_entries where tenant_id=pg_temp.sid('tenant')),0::bigint,'focused fixtures perform no financial posting');

-- Pay publication obeys the existing employee-specific capability gate.
delete from core.role_permissions where tenant_id=pg_temp.sid('tenant') and role_id=pg_temp.sid('self-role') and permission_code='people.payroll.payslip.self';
update people_payroll.corrections set status='reversed',version=4 where id=pg_temp.sid('correction-two');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-two')),1::bigint,'revoked own-payslip capability suppresses new pay notice');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.sid('tenant'),pg_temp.sid('self-role'),'people.payroll.payslip.self');
update people_payroll.corrections set version=4 where id=pg_temp.sid('correction-two');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('correction-slip-two')),1::bigint,'restoring capability does not backfill the suppressed transition');

-- A real attendance command still succeeds for staff while its recipient has
-- lost membership. The event is consumed without notifying a stale identity.
update core.memberships set status='suspended' where id=pg_temp.sid('b.membership');
select pg_temp.actor('recorder');set local role authenticated;
select lives_ok($$select pg_temp.att('create-revoked','create','entry-revoked',0,4,10,'b')$$,'staff creates scoped time independently of recipient membership');
select lives_ok($$select pg_temp.att('submit-revoked','submit','entry-revoked',1,4,10,'b')$$,'staff submits time for revoked recipient');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select lives_ok($$select pg_temp.att('approve-revoked','approve','entry-revoked',2,4,10,'b')$$,'staff approves canonical time for revoked recipient');
reset role;
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('entry-revoked')),0::bigint,'inactive membership suppresses employee inbox notice');
select is((select count(*) from employee_push.deliveries where installation_id=pg_temp.sid('device-b')),0::bigint,'inactive or foreign recipient has no queued push');
update core.memberships set status='active' where id=pg_temp.sid('b.membership');
insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,entry_id,revision_id,action,before_status,after_status,reason,actor_id,command_id)
select tenant_id,legal_entity_id,branch_id,employee_id,id,current_revision_id,'approve','submitted','approved',
 'PRIVATE_REPLAY_REASON',pg_temp.sid('reviewer'),pg_temp.sid('revoked-event-repeat') from people.attendance_entries where id=pg_temp.sid('entry-revoked');
select is((select count(*) from workflow.notifications where aggregate_id=pg_temp.sid('entry-revoked')),0::bigint,'repeated event cannot backfill a version consumed while revoked');

select ok(not exists(select 1 from workflow.notifications n where n.tenant_id=pg_temp.sid('tenant')
 and (n.recipient_id<>pg_temp.sid('a') or n.legal_entity_id<>pg_temp.sid('entity') or n.branch_id<>pg_temp.sid('branch'))),
 'all actual notices bind the exact current employee recipient and entity/branch');
select ok(not exists(select 1 from workflow.notifications n where n.tenant_id=pg_temp.sid('tenant') and
 (n.title<>'Jentra Employee' or n.body<>'You have an update. Open the app to view it.'
 or n.notification_type not like 'people.employee.%' or n.source_context::text like '%PRIVATE_%')),
 'inbox payload is generic and excludes private attendance, intake, leave and payroll content');
select ok(not exists(select 1 from employee_push.deliveries d join workflow.notifications n on n.id=d.notification_id
 join employee_push.devices v on v.installation_id=d.installation_id where n.tenant_id=pg_temp.sid('tenant')
 and (v.user_id<>n.recipient_id or v.tenant_id<>n.tenant_id or v.legal_entity_id<>n.legal_entity_id or v.branch_id<>n.branch_id)),
 'every delivery is bound to matching authoritative notice scope and recipient');
select is((select count(*) from employee_push.deliveries d join workflow.notifications n on n.id=d.notification_id where n.tenant_id=pg_temp.sid('tenant')),
 (select count(*) from workflow.notifications where tenant_id=pg_temp.sid('tenant')),'one existing own device queues exactly once per notice');
select pg_temp.actor('a');set local role authenticated;
select is(pg_temp.register('late-device-a','SYNTHETIC_HR_FID_LATE_A_123456789012345')->>'status','active','late device registers after source history exists');
reset role;
select is((select count(*) from employee_push.deliveries where installation_id=pg_temp.sid('late-device-a')),0::bigint,'registration never pushes old inbox history');
select ok(not exists(select 1 from core.role_permissions where tenant_id=pg_temp.sid('tenant') and role_id=pg_temp.sid('self-role')
 and permission_code in('people.attendance.manage','people.attendance.approve','people.leave.approve','people.payroll.payslip.view')),
 'employee role retains only bounded self-service authority');
set constraints all immediate;
select * from finish();
rollback;
