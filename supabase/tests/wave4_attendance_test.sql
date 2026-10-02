create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();

insert into people.departments(id,tenant_id,legal_entity_id,code)
values(pg_temp.wid('department'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4OPS');
insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,
 start_date,end_date_exclusive,reason,recorded_by)
values(pg_temp.wid('department-r1'),pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('department'),'Synthetic Operations',pg_temp.wdate()-10,
 pg_temp.wdate()+400,'Synthetic attendance fixture',pg_temp.wid('creator'));
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,
 employee_id,spell_id,department_id,calendar_version_id,role_title,
 start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('organization-employee'),pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),s.id,pg_temp.wid('department'),
 pg_temp.wid('calendar-version'),'Synthetic worker',pg_temp.wdate()-10,
 pg_temp.wdate()+400,'Synthetic attendance fixture',pg_temp.wid('creator')
from people.employment_spells s where s.employee_id=pg_temp.wid('employee');

create function pg_temp.ac(p jsonb,v bigint,k text,p_branch text default 'branch')
returns jsonb language sql as $$
 select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid(p_branch),pg_temp.wid(k),pg_temp.wid(k),now(),p,v)
$$;
create function pg_temp.aentry(p_id text,p_start interval default interval '9 hours',
 p_end interval default interval '12 hours',p_break boolean default true)
returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid(p_id),
 'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+p_start,'YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,
 'end_local',to_char(pg_temp.wdate()::timestamp+p_end,'YYYY-MM-DD"T"HH24:MI:SS'),
 'end_offset_seconds',19800,
 'breaks',case when p_break then jsonb_build_array(jsonb_build_object(
  'start_utc',to_char(pg_temp.wdate()::timestamp+interval '4 hours 30 minutes',
    'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'end_utc',to_char(pg_temp.wdate()::timestamp+interval '4 hours 45 minutes',
    'YYYY-MM-DD"T"HH24:MI:SS"Z"'))) else '[]'::jsonb end,
 'reason','Synthetic time fixture')
$$;
create function pg_temp.astate(p_action text,p_id text) returns jsonb language sql as $$
 select jsonb_build_object('action',p_action,'id',pg_temp.wid(p_id),
  'employee_id',pg_temp.wid('employee'),'reason','Synthetic attendance transition')
$$;
create temporary table attendance_responses(name text primary key,response jsonb);
grant select,insert on attendance_responses to authenticated,service_role;

select ok((select bool_and(c.relrowsecurity and c.relforcerowsecurity)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='people'
 and c.relname in ('raw_clock_events','attendance_entries','attendance_revisions',
 'attendance_events','work_claims','work_claim_segments','work_allocations',
 'work_input_seals')),
 'AC-401 all attendance base tables force RLS');
select ok(not has_table_privilege('authenticated','people.work_allocations','SELECT'),
 'AC-411 common allocations are trusted API-only');
select ok(not has_table_privilege('authenticated','people.work_claims','SELECT'),
 'AC-401 no direct work claim read');
select ok(not has_table_privilege('authenticated','people.raw_clock_events','INSERT'),
 'AC-401 no direct raw import');
select ok(not has_function_privilege('anon',
 'api.people_attendance_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),
 'AC-401 anonymous command denied');
select ok(not has_function_privilege('authenticated',
 'people.make_work_claim(uuid,uuid,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb,uuid,uuid)',
 'EXECUTE'),'AC-411 direct claim creation denied');
select throws_ok($$select people.resolve_local_instant('America/New_York',
 '2026-03-08 02:30:00'::timestamp,-18000)$$,'22023','CALENDAR_LOCAL_TIME_NONEXISTENT',
 'AC-405 New York clock gap cannot become attendance');
select throws_ok($$select people.resolve_local_instant('America/New_York',
 '2026-11-01 01:30:00'::timestamp)$$,'22023','CALENDAR_OFFSET_SELECTION_REQUIRED',
 'AC-405 fold requires selected offset');
select is((people.resolve_local_instant('America/New_York',
 '2026-11-01 01:30:00'::timestamp,-18000) at time zone 'UTC')::text,
 '2026-11-01 06:30:00','AC-405 selected fold freezes UTC instant');

select pg_temp.wactor('creator');
set local role authenticated;
insert into attendance_responses values('raw-start',pg_temp.ac(jsonb_build_object(
 'action','raw_import','id',pg_temp.wid('raw-start'),'employee_id',pg_temp.wid('employee'),
 'source_system','synthetic-clock','source_key','SYN-START',
 'observed_utc',to_char(pg_temp.wdate()::timestamp+interval '3 hours 30 minutes',
  'YYYY-MM-DD"T"HH24:MI:SS"Z"'),'checksum',repeat('a',64)),0,'raw-start-command'));
select is(pg_temp.ac(jsonb_build_object('action','raw_import','id',pg_temp.wid('raw-start'),
 'employee_id',pg_temp.wid('employee'),'source_system','synthetic-clock',
 'source_key','SYN-START','observed_utc',to_char(pg_temp.wdate()::timestamp+
 interval '3 hours 30 minutes','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'checksum',repeat('a',64)),
 0,'raw-start-command'),(select response from attendance_responses where name='raw-start'),
 'AC-405 exact raw import replay');
select throws_ok($$select pg_temp.ac(jsonb_build_object('action','raw_import',
 'id',pg_temp.wid('raw-duplicate'),'employee_id',pg_temp.wid('employee'),
 'source_system','synthetic-clock','source_key','SYN-START',
 'observed_utc',to_char(pg_temp.wdate()::timestamp+interval '3 hours 30 minutes',
  'YYYY-MM-DD"T"HH24:MI:SS"Z"'),'checksum',repeat('b',64)),0,'raw-duplicate-command')$$,
 '23505',null,'AC-405 duplicate raw key with changed checksum denied');
insert into attendance_responses values('create',pg_temp.ac(pg_temp.aentry('attendance'),0,'att-create'));
select is((select response#>>'{entity,revision,payable_seconds}' from attendance_responses
 where name='create'),'9900','AC-405 three UTC hours minus fifteen-minute break');
select is(pg_temp.ac(pg_temp.aentry('attendance'),0,'att-create'),
 (select response from attendance_responses where name='create'),'AC-401 exact create replay');
select throws_ok($$select pg_temp.ac(pg_temp.aentry('attendance')||
 jsonb_build_object('reason','Changed body'),0,'att-create')$$,
 '22023','IDEMPOTENCY_MISMATCH','AC-401 changed request cannot replay');
select throws_ok($$select pg_temp.ac(pg_temp.aentry('gap')||
 jsonb_build_object('start_local','2026-03-08T02:30:00'),0,'gap')$$,
 '22023',null,'AC-405 mismatched or nonexistent boundary denied');
insert into attendance_responses values('submit',pg_temp.ac(pg_temp.astate('submit','attendance'),1,'att-submit'));
select is((select response#>>'{entity,status}' from attendance_responses where name='submit'),
 'submitted','AC-405 submitted revision frozen');
select throws_ok($$select pg_temp.ac(pg_temp.astate('approve','attendance'),2,'self-approve')$$,
 '55000','ATTENDANCE_INDEPENDENT_APPROVAL_REQUIRED','AC-405 self approval denied');
select throws_ok($$select pg_temp.ac(pg_temp.aentry('cross-scope'),0,'cross-scope','branch2')$$,
 '42501','ATTENDANCE_SCOPE_DENIED','AC-401 other branch denied');

select pg_temp.wactor('reader');
select throws_ok($$select pg_temp.ac(pg_temp.astate('approve','attendance'),2,'reader-approve')$$,
 '42501',null,'AC-401 reader cannot approve');
select pg_temp.wactor('reviewer');
insert into attendance_responses values('approve',pg_temp.ac(pg_temp.astate('approve','attendance'),2,'att-approve'));
select is((select response#>>'{entity,status}' from attendance_responses where name='approve'),
 'approved','AC-405 independent approval');
reset role;
select is((select payable_seconds::text from people.work_claims where
 source_kind='attendance' and source_id=(select current_revision_id from people.attendance_entries
 where id=pg_temp.wid('attendance'))),'9900','AC-411 approved claim owns payable seconds');
select is((select count(*)::text from people.work_claim_segments where claim_id=
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance'))),
 '2','AC-411 break excludes two separate payable segments');
select is((select count(*)::text from people.organization_consumptions where source_type='attendance'),
 '1','AC-403 exact organization revision consumed');
create temporary table test_allocations(id uuid);
insert into test_allocations select people.allocate_work(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')),
 'project',pg_temp.wid('project-time'),
 (pg_temp.wdate()::timestamp+interval '3 hours 30 minutes') at time zone 'UTC',
 (pg_temp.wdate()::timestamp+interval '4 hours 30 minutes') at time zone 'UTC',
 pg_temp.wid('reviewer'));
select is((select count(*)::text from people.work_allocations where active),
 '1','AC-411 project allocation references approved payable segment once');
select throws_ok($$select people.allocate_work(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')),
 'service',pg_temp.wid('service-time'),
 (pg_temp.wdate()::timestamp+interval '4 hours') at time zone 'UTC',
 (pg_temp.wdate()::timestamp+interval '4 hours 15 minutes') at time zone 'UTC',
 pg_temp.wid('reviewer'))$$,'23P01',null,
 'AC-411 project and service cannot allocate same payable seconds');
select throws_ok($$select people.allocate_work(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')),
 'service',pg_temp.wid('break-spanning'),
 (pg_temp.wdate()::timestamp+interval '4 hours 29 minutes') at time zone 'UTC',
 (pg_temp.wdate()::timestamp+interval '4 hours 46 minutes') at time zone 'UTC',
 pg_temp.wid('reviewer'))$$,'55000','WORK_ALLOCATION_SOURCE_INVALID',
 'AC-411 one allocation cannot cross an unpaid break');
select throws_ok($$select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')))$$,
 '55000','WORK_ALLOCATION_IMPACT_REQUIRED',
 'AC-411 allocation blocks silent attendance correction');
select people.revoke_work_allocation(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('employee'),(select id from test_allocations));
set local role authenticated;
select is((api.people_attendance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('attendance'))#>>'{entry,revision,payable_seconds}'),
 '9900','AC-405 scoped detail shows frozen payable duration');

select pg_temp.wactor('creator');
insert into attendance_responses values('overlap-create',pg_temp.ac(
 pg_temp.aentry('overlap',interval '11 hours',interval '13 hours',false),0,'overlap-create'));
insert into attendance_responses values('overlap-submit',pg_temp.ac(
 pg_temp.astate('submit','overlap'),1,'overlap-submit'));
select pg_temp.wactor('reviewer');
select throws_ok($$select pg_temp.ac(pg_temp.astate('approve','overlap'),2,'overlap-approve')$$,
 '23514','WORK_INTERVAL_CONFLICT','AC-411 overlapping payable segment denied');
reset role;
select is((select status from people.attendance_entries where id=pg_temp.wid('overlap')),
 'submitted','AC-411 failed approval leaves no partial state');
set local role authenticated;

select pg_temp.wactor('creator');
select throws_ok($$select pg_temp.ac(pg_temp.aentry('bad-break')||jsonb_build_object('breaks',
 jsonb_build_array(jsonb_build_object('start_utc','2026-01-01T00:00:00Z',
 'end_utc','2026-01-01T00:15:00Z'))),0,'bad-break')$$,
 '22023','WORK_BREAK_INVALID','AC-405 out-of-range break denied');
select throws_ok($$select pg_temp.ac(pg_temp.aentry('unknown')||jsonb_build_object('salary','100'),
 0,'unknown')$$,'22023','ATTENDANCE_FIELDS_INVALID','AC-401 unknown field denied');

select pg_temp.wactor('creator','aal1');
select throws_ok($$select pg_temp.ac(pg_temp.astate('submit','attendance'),3,'att-submit')$$,
 '42501',null,'AC-401 MFA checked before replay');
reset role;
select pg_temp.wactor('creator');
insert into people.work_input_seals(tenant_id,legal_entity_id,employee_id,run_id,
 claim_id,source_version,seconds,digest)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('employee'),
 pg_temp.wid('synthetic-payroll-run'),active_claim_id,1,9900,repeat('a',64)
from people.attendance_entries where id=pg_temp.wid('attendance');
set local role authenticated;
select throws_ok($$select pg_temp.ac(pg_temp.aentry('attendance')||
 jsonb_build_object('action','correct'),3,'sealed-correct')$$,
 '55000','PAYROLL_INPUT_SEALED','AC-407 sealed input cannot silently change');
reset role;
select ok(not exists(select 1 from core.role_permissions where tenant_id<>pg_temp.wid('tenant')
 and permission_code like 'people.attendance.%'),'AC-401 no existing role grants');
select is((select count(*)::text from people.work_claims where source_kind='attendance'),
 '1','AC-411 rejected overlaps and corrections create no claim');
