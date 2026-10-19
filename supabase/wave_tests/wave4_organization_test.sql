create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.org(p jsonb,v bigint,k text) returns jsonb language sql as $$
  select api.people_organization_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
    pg_temp.wid(k),pg_temp.wid(k),'2026-09-26T00:00:00Z',p,v)
$$;
create function pg_temp.dept(p text,parent text default null) returns jsonb language sql as $$
  select jsonb_build_object('action','department_create','id',pg_temp.wid(p),'revision_id',pg_temp.wid(p||'.r1'),
    'code',upper(p),'name','Synthetic '||p,'parent_id',case when parent is null then null else pg_temp.wid(parent) end,
    'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,'reason','Synthetic organization fixture')
$$;
create function pg_temp.assign(p text,r text,m text default null) returns jsonb language sql security definer set search_path='' as $$
  select jsonb_build_object('action','assign','id',pg_temp.wid(r),'employee_id',pg_temp.wid(p),
    'spell_id',(select id from people.employment_spells where employee_id=pg_temp.wid(p)),
    'department_id',pg_temp.wid('operations'),'manager_id',case when m is null then null else pg_temp.wid(m) end,
    'calendar_version_id',pg_temp.wid('calendar-version'),'role_title','Synthetic technician',
    'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+40,'reason','Synthetic dated assignment')
$$;
create temporary table org_response(name text primary key,response jsonb);
grant select,insert on org_response to authenticated;
select ok(not has_table_privilege('authenticated','people.organization_assignments','SELECT'),'AC-401 base organization reads denied');
select ok(not has_function_privilege('authenticated','people.consume_organization(uuid,uuid,uuid,uuid,text,uuid,date,date)','EXECUTE'),
  'AC-401 organization consumption only available to trusted module commands');
select ok(not exists(select 1 from core.role_permissions where tenant_id<>pg_temp.wid('tenant')
  and permission_code like 'people.organization.%'),'AC-401 no existing role receives organization grants');
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid in
  ('people.departments'::regclass,'people.department_revisions'::regclass,'people.organization_assignments'::regclass,
   'people.organization_consumptions'::regclass)),'AC-401 all organization tables force RLS');
set local role authenticated;
insert into org_response values('dept',pg_temp.org(pg_temp.dept('operations'),0,'dept'));
select is((select response#>>'{entity,version}' from org_response where name='dept'),'1','AC-403 department starts at version one');
select is(pg_temp.org(pg_temp.dept('operations'),0,'dept'),(select response from org_response where name='dept'),
  'AC-401 department exact retry retains receipt');
select throws_ok($$select pg_temp.org(pg_temp.dept('operations')||'{"name":"Changed"}',0,'dept')$$,
  '22023','IDEMPOTENCY_MISMATCH','AC-401 changed-body replay denied');
select throws_ok($$select pg_temp.org(pg_temp.dept('private')||'{"salary":"50"}',0,'private')$$,
  '22023','ORGANIZATION_COMMAND_FIELDS_INVALID','AC-401 private fields rejected');
select throws_ok($$select pg_temp.org(pg_temp.dept('self','self'),0,'self')$$,
  '23514','DEPARTMENT_CYCLE_OR_DEPTH','AC-403 self parent rejected');
select throws_ok($$select pg_temp.org(pg_temp.dept('missing','unknown'),0,'missing')$$,
  '23503',null,'AC-403 nonexistent parent rejected');
select throws_ok($$select pg_temp.org(pg_temp.dept('too-long')||jsonb_build_object('start_date',pg_temp.wdate()-11,
  'parent_id',pg_temp.wid('operations')),0,'parent-coverage')$$,
  '23514','DEPARTMENT_PARENT_COVERAGE_REQUIRED','AC-403 parent must cover every affected boundary');
insert into org_response values('child',pg_temp.org(pg_temp.dept('delivery','operations'),0,'child'));
select throws_ok($$select pg_temp.org(pg_temp.dept('operations')-'code'||jsonb_build_object('action','department_revise',
  'revision_id',pg_temp.wid('operations.cycle'),'replace_revision_id',pg_temp.wid('operations.r1'),
  'parent_id',pg_temp.wid('delivery')),1,'cycle')$$,
  '23514','DEPARTMENT_CYCLE_OR_DEPTH','AC-403 hierarchy cycle rejected over the full interval');
insert into org_response values('assign',pg_temp.org(pg_temp.assign('employee','employee.org','manager'),1,'assign'));
select is((select response#>>'{entity,employee_version}' from org_response where name='assign'),'2',
  'AC-403 organization and employment share employee version');
select is(jsonb_array_length(api.people_organization_employee(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('employee'),pg_temp.wdate())->'items'),1,'AC-403 scoped dated assignment readable');
select throws_ok($$select pg_temp.org(pg_temp.assign('employee','employee.overlap'),2,'overlap')$$,
  '23P01',null,'AC-403 employee organization intervals cannot overlap');
select throws_ok($$select pg_temp.org(pg_temp.assign('manager','manager.self','manager'),1,'manager-self')$$,
  '23514','ORGANIZATION_IMPACT_REQUIRED','AC-403 manager cannot be employee');
select throws_ok($$select pg_temp.org(pg_temp.assign('manager','manager.cycle','employee'),1,'manager-cycle')$$,
  '23514','MANAGER_CYCLE_OR_DEPTH','AC-403 manager cycle rejected at all shared boundaries');
select throws_ok($$select pg_temp.org(pg_temp.assign('manager','manager.bad-spell')||jsonb_build_object('spell_id',
  (select (pg_temp.assign('employee','unused'))->>'spell_id')),1,'bad-spell')$$,
  '23503',null,'AC-403 spell composite FK binds employee');
select throws_ok($$select pg_temp.org(pg_temp.assign('manager','manager.bad-calendar')||jsonb_build_object(
  'end_date_exclusive',pg_temp.wdate()+401),1,'bad-calendar')$$,
  '23514','ORGANIZATION_IMPACT_REQUIRED','AC-405 assignment cannot outlive calendar coverage');
select throws_ok($$select pg_temp.org(pg_temp.assign('manager','manager.org'),0,'stale')$$,
  '40001','VERSION_CONFLICT','AC-401 stale shared employee version rejected');
insert into org_response values('manager',pg_temp.org(pg_temp.assign('manager','manager.org'),1,'manager'));
select is((api.people_organization_department(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('operations'),pg_temp.wdate())#>>'{department,name}'),'Synthetic operations',
  'AC-403 department detail resolves a scoped identity without directory scanning');
select is((api.people_organization_employee(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('employee'),pg_temp.wdate())#>>'{items,0,manager_display_name}'),'Synthetic manager',
  'AC-403 assignment uses the named operational manager projection');
insert into org_response values('future',pg_temp.org(pg_temp.assign('third','third.future')||jsonb_build_object(
  'start_date',pg_temp.wdate()+2,'end_date_exclusive',pg_temp.wdate()+30),1,'future'));
insert into org_response values('withdraw',pg_temp.org(jsonb_build_object('action','withdraw_assignment','id',pg_temp.wid('third.withdraw'),
  'employee_id',pg_temp.wid('third'),'replace_revision_id',pg_temp.wid('third.future'),
  'start_date',pg_temp.wdate()+2,'end_date_exclusive',pg_temp.wdate()+30,'reason','Synthetic future cancellation'),2,'withdraw'));
select is((select response#>>'{entity,employee_version}' from org_response where name='withdraw'),'3',
  'AC-403 explicit withdrawal advances employee version');
select is((api.people_organization_employee(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('third'),pg_temp.wdate())#>>'{items,0,withdrawal,reason}'),'Synthetic future cancellation',
  'AC-403 withdrawal actor and reason remain attached to original history');
select throws_ok($$select pg_temp.org(jsonb_build_object('action','withdraw_assignment','id',pg_temp.wid('manager.withdraw'),
  'employee_id',pg_temp.wid('manager'),'replace_revision_id',pg_temp.wid('manager.org'),
  'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+40,'reason','Invalid historical withdrawal'),2,'historical-withdraw')$$,
  '55000','ORGANIZATION_FUTURE_WITHDRAWAL_REQUIRED','AC-403 historical assignment withdrawal requires impact handling');
reset role;
select throws_ok($$update people.organization_withdrawals set reason='Tampered'$$,'55000','ORGANIZATION_CONSUMPTION_IMMUTABLE',
  'AC-403 withdrawal evidence cannot be rewritten');
select pg_temp.wactor('creator','aal1');
set local role authenticated;
select throws_ok($$select pg_temp.org(pg_temp.dept('mfa'),0,'mfa')$$,'42501',null,'AC-401 organization management requires current MFA');
reset role;
select pg_temp.wactor('reader');
set local role authenticated;
select is(jsonb_array_length(api.people_organization_departments(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wdate())->'items'),2,'AC-401 reader receives operational departments only');
select throws_ok($$select pg_temp.org(pg_temp.dept('reader'),0,'reader')$$,'42501',null,'AC-401 reader cannot write');
select throws_ok($$select api.people_organization_departments(pg_temp.wid('other-tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wdate())$$,'42501',null,'AC-401 cross-tenant read denied');
select throws_ok($$select api.people_organization_employee(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch2'),pg_temp.wid('employee'),pg_temp.wdate())$$,'42501',null,'AC-401 unauthorized branch read denied');
reset role;
select pg_temp.wactor('branch-manager');
set local role authenticated;
select throws_ok($$select pg_temp.org(pg_temp.dept('branch-only'),0,'branch-only')$$,'42501',null,
  'AC-401 branch-only manager cannot change entity hierarchy');
reset role;
select pg_temp.wactor('creator');
-- Seal original organization input as a trusted future attendance command would.
select people.consume_organization(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('employee'),'attendance',pg_temp.wid('attendance'),pg_temp.wdate(),pg_temp.wdate()+1);
select is((select count(*) from people.organization_consumptions),1::bigint,'AC-403 one original consumption retained');
select people.consume_organization(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('employee'),'attendance',pg_temp.wid('attendance'),pg_temp.wdate(),pg_temp.wdate()+1);
select is((select count(*) from people.organization_consumptions),1::bigint,'AC-403 duplicate consumption is exact replay');
select throws_ok($$select people.consume_organization(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('employee'),'attendance',pg_temp.wid('attendance'),pg_temp.wdate(),pg_temp.wdate()+2)$$,
  '22023','ORGANIZATION_CONSUMPTION_MISMATCH','AC-403 changed consumption dates denied');
set local role authenticated;
select throws_ok($$select pg_temp.org(pg_temp.assign('employee','replacement','manager')||jsonb_build_object(
  'action','replace','replace_revision_id',pg_temp.wid('employee.org')),2,'replacement')$$,
  '55000','ORGANIZATION_CONSUMED_IMPACT_REQUIRED','AC-403 consumed organization cannot silently be replaced');
select throws_ok($$select pg_temp.org(pg_temp.dept('operations')-'code'||jsonb_build_object('action','department_revise',
  'revision_id',pg_temp.wid('operations.consumed'),'replace_revision_id',pg_temp.wid('operations.r1')),
  1,'dept-consumed')$$,'55000','ORGANIZATION_CONSUMED_IMPACT_REQUIRED','AC-403 consumed department change needs explicit impact');
reset role;
select throws_ok($$update people.organization_assignments set role_title='Tampered' where id=pg_temp.wid('employee.org')$$,
  '55000','ORGANIZATION_HISTORY_IMMUTABLE','AC-403 organization history cannot be edited');
select throws_ok($$delete from people.organization_consumptions$$,'55000','ORGANIZATION_CONSUMPTION_IMMUTABLE',
  'AC-403 consumed inputs cannot be erased');
-- Deferred compatibility must make an installed employee command fully roll back.
create function pg_temp.end_employee() returns void language plpgsql as $$begin
  perform api.people_employee_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
    pg_temp.wid('end'),pg_temp.wid('end'),now(),jsonb_build_object('action','end','id',pg_temp.wid('employee'),
      'spell_id',(select id from people.employment_spells where employee_id=pg_temp.wid('employee')),
      'end_date_exclusive',pg_temp.wdate()+20,'reason','Synthetic end'),2);
  set constraints all immediate;
end $$;
select throws_ok($$select pg_temp.end_employee()$$,'23514','ORGANIZATION_IMPACT_REQUIRED',
  'AC-403 ending employment requires compatible organization history');
select is((select version from people.employees where id=pg_temp.wid('employee')),2::bigint,
  'AC-403 failed compatibility leaves employee version unchanged');
select is((select count(*) from core.command_receipts where command_id=pg_temp.wid('end')),0::bigint,
  'AC-401 failed compatibility leaves no receipt');
set constraints all deferred;
set local role authenticated;
insert into org_response values('end-org',pg_temp.org(jsonb_build_object('action','end_assignment','id',pg_temp.wid('employee.prefix'),
  'employee_id',pg_temp.wid('employee'),'replace_revision_id',pg_temp.wid('employee.org'),
  'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+20,'reason','Explicit future end'),2,'end-org'));
select is((select response#>>'{entity,end_date_exclusive}' from org_response where name='end-org'),
  (pg_temp.wdate()+20)::text,'AC-403 explicit future ending preserves consumed prefix');
insert into org_response values('dept-future',pg_temp.org(pg_temp.dept('operations')-'code'||jsonb_build_object(
  'action','department_revise','revision_id',pg_temp.wid('operations.r2'),'replace_revision_id',pg_temp.wid('operations.r1'),
  'start_date',pg_temp.wdate()+40,'end_date_exclusive',pg_temp.wdate()+50,'name','Future Operations'),1,'dept-future'));
reset role;
select is((select count(*) from people.department_revisions where department_id=pg_temp.wid('operations') and superseded_at is null),
  3::bigint,'AC-403 partial department revision preserves both unaffected intervals');
select is((select count(*) from people.organization_assignments where employee_id=pg_temp.wid('employee')),2::bigint,
  'AC-403 original and explicit successor retained');
select is((select revision_id from people.organization_consumptions),pg_temp.wid('employee.org'),
  'AC-403 consumption retains original immutable revision');
select api.people_employee_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('compatible-end'),pg_temp.wid('compatible-end'),now(),jsonb_build_object('action','end',
  'id',pg_temp.wid('employee'),'spell_id',(select id from people.employment_spells where employee_id=pg_temp.wid('employee')),
  'end_date_exclusive',pg_temp.wdate()+20,'reason','Compatible future end'),3);
select is((select version from people.employees where id=pg_temp.wid('employee')),4::bigint,
  'AC-403 installed employment end succeeds after explicit organization ending');
create function pg_temp.fail_org_outbox() returns trigger language plpgsql as $$begin
  if new.command_id=pg_temp.wid('late-failure') then
    raise exception using errcode='P0001',message='SYNTHETIC_ORG_LATE_FAILURE';
  end if;
  return new;
end $$;
create trigger synthetic_org_late_failure before insert on core.outbox_events
  for each row execute function pg_temp.fail_org_outbox();
set local role authenticated;
select throws_ok($$select pg_temp.org(pg_temp.dept('late'),0,'late-failure')$$,
  'P0001','SYNTHETIC_ORG_LATE_FAILURE','AC-401 injected outbox failure aborts whole command');
reset role;
drop trigger synthetic_org_late_failure on core.outbox_events;
select is((select count(*) from people.departments where id=pg_temp.wid('late')),0::bigint,
  'AC-401 late failure leaves no department');
select is((select count(*) from audit.events where command_id=pg_temp.wid('late-failure')),0::bigint,
  'AC-401 late failure leaves no audit');
select is((select count(*) from core.command_receipts where command_id=pg_temp.wid('late-failure')),0::bigint,
  'AC-401 late failure leaves no receipt');
set constraints all immediate;
set constraints all deferred;
update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback';
set local role authenticated;
select throws_ok($$select pg_temp.org(pg_temp.dept('operations'),0,'dept')$$,'42501','PEOPLE_ENTITLEMENT_REQUIRED',
  'AC-401 replay rechecks current entitlement');
reset role;
update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback';
update core.memberships set status='suspended' where id=pg_temp.wid('creator.membership');
set local role authenticated;
select throws_ok($$select pg_temp.org(pg_temp.dept('operations'),0,'dept')$$,'42501',null,'AC-401 replay rechecks current membership');
reset role;
