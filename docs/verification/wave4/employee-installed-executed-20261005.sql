begin;
set local lock_timeout='3s';
set local statement_timeout='60s';

create temporary table employee_assertions(message text);
grant insert on employee_assertions to authenticated;
-- AC-401–403. Included only inside build_employee_candidate.ps1 rollback block.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.fid(p text) returns uuid language sql immutable as
  $$select md5('wave4-employee-20260925:'||p)::uuid$$;
create function pg_temp.actor(p text,p_aal text default 'aal2') returns void
language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(p),
    'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.fid(p)::text,true);
end $$;
create function pg_temp.call(p_payload jsonb,p_version bigint,p_key text,
  p_branch text default 'branch') returns jsonb language sql as $$
  select api.people_employee_command(pg_temp.fid('tenant'),pg_temp.fid('entity'),
    pg_temp.fid(p_branch),pg_temp.fid(p_key),pg_temp.fid(p_key),
    '2026-09-25T00:00:00Z'::timestamptz,p_payload,p_version)
$$;
create function pg_temp.header(p_code text default 'EMP-01') returns jsonb
language sql as $$select jsonb_build_object('action','create',
  'id',pg_temp.fid('employee'),'code',p_code,'display_name','Synthetic Employee',
  'work_email','synthetic@jentra.test','start_date','2026-09-20',
  'job_title','Technician','employment_type','permanent')$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,
  email_confirmed_at,created_at,updated_at)
select pg_temp.fid(x),'00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated',x||'@employee.jentra.test','',now(),now(),now()
from unnest(array['creator','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by)
values(pg_temp.fid('tenant'),'Employee Test','wave4-employee-synthetic',pg_temp.fid('creator'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,
  rounding_scale,created_by)
values(pg_temp.fid('entity'),pg_temp.fid('tenant'),'Employee Entity','EMPTEST',
  'LKR','Asia/Colombo',2,pg_temp.fid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('branch'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
  'Employee Branch','EMPB',pg_temp.fid('creator')),
  (pg_temp.fid('branch2'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
  'Second Branch','EMP2',pg_temp.fid('creator'));
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.fid('tenant'),'starter','trialing',5,now()+interval '30 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.fid(x||'.membership'),pg_temp.fid('tenant'),pg_temp.fid(x),
  'active' from unnest(array['creator','reader']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.fid(x||'.role'),pg_temp.fid('tenant'),x,x,true
from unnest(array['creator','reader']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),p
from unnest(array['people.view','people.employees.view',
  'people.employees.manage','people.employment.manage',
  'people.employees.history.view']) p;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('reader.role'),p
from unnest(array['people.view','people.employees.view',
  'people.employees.history.view']) p;
insert into core.role_assignments(tenant_id,membership_id,role_id,
  legal_entity_id,branch_id,created_by)
select pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),
  pg_temp.fid('creator.role'),pg_temp.fid('entity'),pg_temp.fid(x),
  pg_temp.fid('creator') from unnest(array['branch','branch2']) x;
insert into core.role_assignments(tenant_id,membership_id,role_id,
  legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('reader.membership'),
  pg_temp.fid('reader.role'),pg_temp.fid('entity'),pg_temp.fid('branch'),
  pg_temp.fid('creator'));

select pg_temp.actor('creator');
insert into employee_assertions select is((select count(*) from billing.plan_entitlements
  where entitlement_code='module.people' and not enabled
    and plan_code in ('starter','growth','scale')),
  3::bigint,'AC-401 original commercial plans keep People disabled');
insert into employee_assertions select throws_ok($$select api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')$$,
  '42501','PEOPLE_ENTITLEMENT_REQUIRED',
  'AC-401 plan entitlement is disabled by default');
update billing.plan_entitlements set enabled=true
  where plan_code='starter' and entitlement_code='module.people';
create temporary table employee_response(name text primary key,response jsonb);
insert into employee_response values('create',pg_temp.call(pg_temp.header(),0,'create'));
insert into employee_assertions select is((select response#>>'{entity,code}' from employee_response where name='create'),
  'EMP-01','AC-402 employee created with scoped code');
insert into employee_assertions select is((select version from people.employees where id=pg_temp.fid('employee')),
  1::bigint,'AC-402 creation starts at version one');
insert into employee_assertions select is((select count(*) from people.employment_spells),1::bigint,
  'AC-402 one employment spell created atomically');
insert into employee_assertions select is((select count(*) from people.employment_assignments),1::bigint,
  'AC-402 one initial assignment created atomically');
insert into employee_assertions select is(pg_temp.call(pg_temp.header(),0,'create'),
  (select response from employee_response where name='create'),
  'AC-401 identical replay returns the original receipt');
update billing.plan_entitlements set enabled=false
  where plan_code='starter' and entitlement_code='module.people';
insert into employee_assertions select throws_ok($$select pg_temp.call(pg_temp.header(),0,'create')$$,
  '42501','PEOPLE_ENTITLEMENT_REQUIRED',
  'AC-401 confirmed replay is denied after entitlement revocation');
update billing.plan_entitlements set enabled=true
  where plan_code='starter' and entitlement_code='module.people';
update billing.tenant_subscriptions set trial_ends_at=now()-interval '1 day'
  where tenant_id=pg_temp.fid('tenant');
insert into employee_assertions select throws_ok($$select api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')$$,
  '42501','PEOPLE_ENTITLEMENT_REQUIRED',
  'AC-401 expired trial cannot read People');
update billing.tenant_subscriptions set trial_ends_at=now()+interval '30 days',
  status='suspended' where tenant_id=pg_temp.fid('tenant');
insert into employee_assertions select throws_ok($$select api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')$$,
  '42501','PEOPLE_ENTITLEMENT_REQUIRED',
  'AC-401 suspended subscription cannot read People');
update billing.tenant_subscriptions set status='trialing'
  where tenant_id=pg_temp.fid('tenant');
update billing.tenant_subscriptions set status='active',
  current_period_ends_at=now()+interval '30 days'
  where tenant_id=pg_temp.fid('tenant');
insert into employee_assertions select is(jsonb_array_length(api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')->'items'),1,
  'AC-401 enabled People is available during an active paid period');
update billing.tenant_subscriptions set current_period_ends_at=now()-interval '1 day'
  where tenant_id=pg_temp.fid('tenant');
insert into employee_assertions select throws_ok($$select api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')$$,
  '42501','PEOPLE_ENTITLEMENT_REQUIRED',
  'AC-401 expired paid period cannot read People');
update billing.tenant_subscriptions set status='trialing',
  current_period_ends_at=null where tenant_id=pg_temp.fid('tenant');
insert into employee_assertions select throws_ok($$select pg_temp.call(pg_temp.header('EMP-02'),0,'create')$$,
  '22023','IDEMPOTENCY_MISMATCH','AC-401 changed-body key reuse denied');
insert into employee_assertions select throws_ok($$select pg_temp.call(pg_temp.header('EMP-01'),0,'duplicate')$$,
  '23505',null,'AC-402 duplicate code denied');
insert into employee_assertions select throws_ok($$select pg_temp.call(pg_temp.header()||'{"salary":"50000"}',0,'private')$$,
  '22023','EMPLOYEE_COMMAND_FIELDS_INVALID','AC-401 private field rejected');
insert into employee_assertions select throws_ok($$select pg_temp.call(pg_temp.header()||'{"start_date":"2026-02-30"}',0,'bad-date')$$,
  '22008',null,'AC-402 nonexistent date rejected');
insert into employee_assertions select throws_ok($$select pg_temp.call('{"action":"identity","id":"invalid","display_name":"X","reason":"Correction"}',1,'bad-id')$$,
  '22023','EMPLOYEE_COMMAND_INVALID','AC-401 invalid identity rejected');
insert into employee_assertions select throws_ok($$select pg_temp.call(jsonb_build_object('action','identity',
  'id',pg_temp.fid('employee'),'display_name','Corrected','reason','Correct spelling'),
  8,'stale')$$,'40001','VERSION_CONFLICT','AC-402 stale version rejected');
insert into employee_assertions select is((select count(*) from people.employees),1::bigint,
  'AC-402 failed commands have no extra identity');
insert into employee_assertions select is((select count(*) from core.command_receipts where
  command_name='people.employee.create'),1::bigint,
  'AC-401 one receipt for one confirmed create');
insert into employee_assertions select is(jsonb_array_length((api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')) -> 'items'),
  1,'AC-401 directory returns bounded scoped identity');
insert into employee_assertions select is((api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'))->>'as_of'),
  (now() at time zone 'Asia/Colombo')::date::text,
  'AC-401 default register date follows entity calendar');
insert into employee_assertions select throws_ok($$select api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25',null)$$,
  '22023','EMPLOYEE_FILTER_INVALID',
  'AC-401 null status cannot select an unintended population');
insert into employee_assertions select ok((api.people_employee_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),
  pg_temp.fid('branch'),pg_temp.fid('employee'),'2026-09-25') ? 'salary') is false,
  'AC-401 operational detail has no payroll data');
insert into employee_assertions select throws_ok($$select api.people_employee_detail(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch2'),pg_temp.fid('employee'),
  '2026-09-25')$$,'42501','EMPLOYMENT_SCOPE_INVALID',
  'AC-401 destination cannot see employee before transfer');
select pg_temp.actor('reader');
insert into employee_assertions select throws_ok($$select pg_temp.call(pg_temp.header('EMP-02'),0,'reader-create')$$,
  '42501',null,'AC-401 directory reader cannot create employee');
select pg_temp.actor('reader','aal1');
insert into employee_assertions select throws_ok($$select api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')$$,
  '42501',null,'AC-401 MFA-protected role cannot read at aal1');
select pg_temp.actor('outsider');
insert into employee_assertions select throws_ok($$select api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-25')$$,
  '42501',null,'AC-401 outsider cannot read employee directory');
select pg_temp.actor('creator');
set local role authenticated;
insert into employee_assertions select throws_ok($$select * from people.employees$$,'42501',null,
  'AC-401 base tables unavailable to authenticated desktop role');
reset role;

insert into employee_response values('identity',pg_temp.call(jsonb_build_object(
  'action','identity','id',pg_temp.fid('employee'),'display_name',
  'Synthetic Corrected','reason','Correcting directory label'),1,'identity'));
insert into employee_assertions select is((select response#>>'{entity,version}' from employee_response
  where name='identity'),'2','AC-402 identity update increments version');
insert into employee_response values('transfer',pg_temp.call(jsonb_build_object(
  'action','assignment','id',pg_temp.fid('employee'),
  'effective_date','2099-01-01','destination_branch_id',pg_temp.fid('branch2'),
  'job_title','Lead Technician','employment_type','permanent',
  'reason','Scheduled branch change'),2,'transfer'));
insert into employee_assertions select is((select response#>>'{entity,version}' from employee_response
  where name='transfer'),'3','AC-403 scheduled transfer increments version');
insert into employee_assertions select is((select count(*) from people.employment_assignments
  where employee_id=pg_temp.fid('employee')),2::bigint,
  'AC-403 future transfer creates adjacent assignment');
insert into employee_assertions select is(jsonb_array_length((api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch2'),'2099-01-01'))->'items'),
  1,'AC-403 destination branch sees employee from effective date');
insert into employee_assertions select is(jsonb_array_length((api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2099-01-01'))->'items'),
  0,'AC-403 source branch no longer sees employee after transfer');
insert into employee_assertions select is(jsonb_array_length((api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2099-01-01','ended'))->'items'),
  0,'AC-403 transfer does not falsely mark employment ended');
insert into employee_assertions select throws_ok($$select api.people_employee_detail(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('employee'),
  '2099-01-01')$$,'42501','EMPLOYMENT_SCOPE_INVALID',
  'AC-401 dated source detail is denied after transfer');
insert into employee_assertions select ok(exists(select 1 from jsonb_array_elements(
  api.people_employee_history(pg_temp.fid('tenant'),pg_temp.fid('entity'),
    pg_temp.fid('branch'),pg_temp.fid('employee'))->'items') ev
  where ev->>'action'='assignment'),
  'AC-403 source branch retains redacted transfer event');
insert into employee_assertions select ok(not exists(select 1 from jsonb_array_elements(
  api.people_employee_history(pg_temp.fid('tenant'),pg_temp.fid('entity'),
    pg_temp.fid('branch'),pg_temp.fid('employee'))->'items') ev
  where ev ? 'destination_branch_id'),
  'AC-403 scoped history omits destination identity');
delete from core.role_assignments where tenant_id=pg_temp.fid('tenant')
  and membership_id=pg_temp.fid('creator.membership')
  and branch_id=pg_temp.fid('branch2');
insert into employee_assertions select throws_ok($$select pg_temp.call(jsonb_build_object(
  'action','assignment','id',pg_temp.fid('employee'),
  'effective_date','2099-01-01','destination_branch_id',pg_temp.fid('branch2'),
  'job_title','Lead Technician','employment_type','permanent',
  'reason','Scheduled branch change'),2,'transfer','branch')$$,
  '42501',null,'AC-401 transfer replay denied after destination revocation');
insert into core.role_assignments(tenant_id,membership_id,role_id,
  legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),
  pg_temp.fid('creator.role'),pg_temp.fid('entity'),pg_temp.fid('branch2'),
  pg_temp.fid('creator'));
insert into employee_assertions select throws_ok($$select pg_temp.call(jsonb_build_object('action','assignment',
  'id',pg_temp.fid('employee'),'effective_date','2099-02-01',
  'destination_branch_id',pg_temp.fid('branch2'),'job_title','Manager',
  'employment_type','permanent','reason','Second scheduled change'),3,
  'second-transfer')$$,'55000','EMPLOYMENT_FUTURE_EVENT_EXISTS',
  'AC-403 scheduled successor cannot be silently replaced');
insert into employee_response values('correct',pg_temp.call(jsonb_build_object(
  'action','correct','id',pg_temp.fid('employee'),
  'event_id',(select id from people.employment_events
    where action='assignment' and employee_id=pg_temp.fid('employee')),
  'correction_action','cancel','reason','Transfer cancelled'),3,'correct'));
insert into employee_assertions select is((select count(*) from people.employment_assignments
  where employee_id=pg_temp.fid('employee')),1::bigint,
  'AC-403 correction restores one open assignment');
insert into employee_assertions select is((select count(*) from people.employment_events
  where employee_id=pg_temp.fid('employee') and action in ('assignment','correct')),
  2::bigint,'AC-403 correction retains original immutable event');
insert into employee_assertions select throws_ok($$delete from people.employment_events where
  employee_id=pg_temp.fid('employee')$$,'55000','EMPLOYMENT_EVENT_IMMUTABLE',
  'AC-403 event history cannot be deleted');
insert into employee_response values('end',pg_temp.call(jsonb_build_object(
  'action','end','id',pg_temp.fid('employee'),
  'spell_id',(select id from people.employment_spells
    where employee_id=pg_temp.fid('employee')),
  'end_date_exclusive','2099-01-01','reason','End of engagement'),4,'end'));
insert into employee_assertions select is((select end_date_exclusive::text from people.employment_spells
  where employee_id=pg_temp.fid('employee')),'2099-01-01',
  'AC-403 employment ends at exclusive date');
insert into employee_assertions select is(jsonb_array_length((api.people_employee_directory(pg_temp.fid('tenant'),
  pg_temp.fid('entity'),pg_temp.fid('branch'),'2099-01-01','ended'))->'items'),
  1,'AC-403 ended filter finds last employing branch');
insert into employee_assertions select is((api.people_employee_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),
  pg_temp.fid('branch'),pg_temp.fid('employee'),'2099-01-01','ended'))->>'code',
  'EMP-01','AC-403 ended detail uses same dated predicate');
insert into employee_response values('rehire',pg_temp.call(jsonb_build_object(
  'action','rehire','id',pg_temp.fid('employee'),'start_date','2099-02-01',
  'job_title','Specialist','employment_type','contractor',
  'reason','New assignment agreed'),5,'rehire'));
insert into employee_assertions select is((select count(*) from people.employment_spells
  where employee_id=pg_temp.fid('employee')),2::bigint,
  'AC-403 rehire creates a new spell without deleting old employment');
insert into employee_assertions select is((select count(*) from people.employment_events
  where employee_id=pg_temp.fid('employee')),6::bigint,
  'AC-403 all successful transitions have attributable events');
insert into employee_assertions select is((select count(*) from core.command_receipts where
  aggregate_type='people.employee'),6::bigint,
  'AC-401 every successful employee command has one receipt');

do $$
declare v_failed text;
begin
  select string_agg(message, E'\n') into v_failed
  from employee_assertions where message like 'not ok%';
  if v_failed is not null then
    raise exception using errcode='P0001', message=v_failed;
  end if;
end $$;
select * from finish(true);
select count(*) as assertions from employee_assertions;
rollback;