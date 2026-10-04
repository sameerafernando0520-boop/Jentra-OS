reset role;
select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='people_payroll' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity),24,'nine correction tables forced RLS');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='people_payroll'
 and c.relkind='r' and has_table_privilege('authenticated',c.oid,'SELECT')),'all correction base-table reads denied');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='people_payroll'
 and has_function_privilege('authenticated',p.oid,'EXECUTE')),'all trusted correction helpers denied');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p
where p.code in('people.payroll.correction.prepare','people.payroll.correction.approve','people.payroll.post') on conflict do nothing;
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,
 role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('org.correction.manager'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),s.id,
 pg_temp.wid('department'),pg_temp.wid('calendar-version'),'Synthetic correction subject',pg_temp.wdate()-10,pg_temp.wdate()+400,
 'Synthetic correction fixture',pg_temp.wid('creator') from people.employment_spells s where s.employee_id=pg_temp.wid('manager');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pc(pg_temp.publish('CORRHOURS','earning','100','wages',null,'hourly'),0,'corr.rule');
select pg_temp.pc(jsonb_build_object('action','assign','id',pg_temp.wid('corr.assign'),'employee_id',pg_temp.wid('manager'),
 'component_id',pg_temp.wid('component.CORRHOURS'),'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,'reason','Synthetic hourly'),0,'corr.assign');
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.time.create'),pg_temp.wid('corr.time.create'),now(),
 jsonb_build_object('action','create','id',pg_temp.wid('corr.attendance'),'employee_id',pg_temp.wid('manager'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(pg_temp.wdate()::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,'reason','Synthetic time'),0);
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.time.submit'),pg_temp.wid('corr.time.submit'),now(),
 jsonb_build_object('action','submit','id',pg_temp.wid('corr.attendance'),'employee_id',pg_temp.wid('manager'),'reason','Synthetic time'),1);
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.time.approve'),pg_temp.wid('corr.time.approve'),now(),
 jsonb_build_object('action','approve','id',pg_temp.wid('corr.attendance'),'employee_id',pg_temp.wid('manager'),'reason','Synthetic time'),2);
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_create('corr.original')||jsonb_build_object('employee_ids',jsonb_build_array(pg_temp.wid('manager'))),0,'corr.original.create');
select pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('corr.original'),'reason','Synthetic freeze'),1,'corr.original.prepare');
select pg_temp.pcmd(pg_temp.run_action('submit','corr.original'),2,'corr.original.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('approve','corr.original'),3,'corr.original.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('post','corr.original'),4,'corr.original.post');
reset role;
create temporary table correction_client_samples(name text primary key,response jsonb);
grant select,insert on correction_client_samples to authenticated;
create function pg_temp.correction_prepare(p_seconds bigint,key text default 'corr.one') returns jsonb language sql security definer as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid(key),'original_calculation_id',c.id,'posting_date',pg_temp.wdate()+1,
  'reason','Synthetic eligibility correction','replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,
  'before_revision_id',people_payroll.correction_source_state(s.id)->>'revision_id','expected_version',
  (people_payroll.correction_source_state(s.id)->>'version')::bigint,'paid_seconds',p_seconds)))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 where c.run_id=pg_temp.wid('corr.original') $$;
create function pg_temp.correction_action(act text,key text default 'corr.one') returns jsonb language sql security definer as $$
 select jsonb_build_object('action',act,'id',id,'digest',digest,'reason','Synthetic decision')||
 case when act='reverse' then jsonb_build_object('posting_date',pg_temp.wdate()+2) else '{}'::jsonb end from people_payroll.corrections where id=pg_temp.wid(key) $$;
create function pg_temp.cc(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_payroll_correction_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
create function pg_temp.cdetail(section text,key text default 'corr.one') returns jsonb language sql as $$
 select api.people_payroll_correction_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),section) $$;
create function pg_temp.csettle(p_amount text,direction text default 'recover') returns jsonb language sql security definer as $$
 select jsonb_build_object('action','record','id',pg_temp.wid('corr.settlement'),'correction_id',pg_temp.wid('corr.one'),
  'posting_date',pg_temp.wdate()+1,'bank_id',pg_temp.wid('pay.bank.record'),'bank_version',1,'direction',direction,
  'evidence_reference','SYNTHETIC-CORR-001','reason','Synthetic recorded recovery','allocations',
  jsonb_build_array(jsonb_build_object('balance_id',id,'amount',p_amount))) from people_payroll.correction_balances where correction_id=pg_temp.wid('corr.one') and kind='net' $$;
create function pg_temp.cs(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_payroll_correction_settlement(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
select pg_temp.wactor('creator','aal1');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.lowaal')$q$,'42501',null,'corrections need MFA');
reset role;select pg_temp.wactor('reader');set local role authenticated;
select throws_ok($q$select api.people_payroll_corrections(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,'42501',null,'directory capability never reveals corrections');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(3601),0,'corr.excess')$q$,'22023','PAYROLL_CORRECTION_ELIGIBILITY_INVALID','eligibility cannot invent new worked seconds');
insert into correction_client_samples values('prepared',pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.prepare'));
select is(pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.prepare'),(select response from correction_client_samples where name='prepared'),'prepare exact replay');
select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(1800)||'{"reason":"changed"}',0,'corr.prepare')$q$,'22023','IDEMPOTENCY_MISMATCH','changed correction body cannot reuse key');
select is(pg_temp.cdetail('calculation')->'items'->0->'difference'->>'net','-50.000000','full rounded calculation produces signed recovery');
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('approve'),1,'corr.self')$q$,'42501','PAYROLL_INDEPENDENT_APPROVAL_REQUIRED','preparer cannot independently approve');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
insert into correction_client_samples values('approved',pg_temp.cc(pg_temp.correction_action('approve'),1,'corr.approve'));
reset role;
create function pg_temp.correction_fail_late() returns trigger language plpgsql as $$begin
 if new.command_id=pg_temp.wid('corr.fail.post') then raise exception using errcode='P0001',message='SYNTHETIC_CORRECTION_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_correction_fail_late before insert on core.outbox_events for each row execute function pg_temp.correction_fail_late();
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post'),2,'corr.fail.post')$q$,'P0001','SYNTHETIC_CORRECTION_LATE_FAILURE','late outbox failure rolls back correction');
reset role;
select is((select count(*)::integer from people_payroll.correction_balances),0,'failed correction has no signed balances');
select is((select count(*)::integer from people_payroll.correction_payslips),0,'failed correction has no payslip');
select is((select count(*)::integer from people_payroll.correction_source_effects),0,'failed correction leaves source chain unchanged');
select pg_temp.wactor('creator');set local role authenticated;
insert into correction_client_samples values('posted',pg_temp.cc(pg_temp.correction_action('post'),2,'corr.post'));
select is(pg_temp.cc(pg_temp.correction_action('post'),2,'corr.post'),(select response from correction_client_samples where name='posted'),'post exact replay');
select is(api.people_payroll_correction_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.post'),'post'),
 (select response from correction_client_samples where name='posted'),'own receipt retains confirmed correction');
select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('reverse','corr.original'),5,'corr.original.reverse')$q$,'55000','PAYROLL_ACTIVE_CORRECTION_BLOCKS_REVERSAL','original regular run cannot reverse active correction');
insert into correction_client_samples values('calculation',pg_temp.cdetail('calculation'));
insert into correction_client_samples values('sources',pg_temp.cdetail('sources'));
insert into correction_client_samples values('balances',pg_temp.cdetail('balances'));
insert into correction_client_samples values('payslip',pg_temp.cdetail('payslip'));
insert into correction_client_samples values('originals',api.people_payroll_correction_originals(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch')));
insert into correction_client_samples values('sealed_sources',api.people_payroll_correction_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select response->'entity'->>'original_calculation_id' from correction_client_samples where name='prepared')::uuid));
select throws_ok($q$select pg_temp.cs(pg_temp.csettle('50.01'),0,'corr.overpay')$q$,'55000','PAYROLL_SETTLEMENT_EXCEEDS_DUE','signed recovery cannot be over-allocated');
select throws_ok($q$select pg_temp.cs(pg_temp.csettle('10','pay'),0,'corr.wrongdirection')$q$,'55000','PAYROLL_SETTLEMENT_EXCEEDS_DUE','recovery cannot be paid out');
insert into correction_client_samples values('settlement',pg_temp.cs(pg_temp.csettle('20'),0,'corr.settle'));
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('reverse'),3,'corr.settled.reverse')$q$,'55000','PAYROLL_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL','active recorded recovery blocks correction reversal');
select pg_temp.cs(jsonb_build_object('action','reverse','id',pg_temp.wid('corr.settlement'),'correction_id',pg_temp.wid('corr.one'),
 'posting_date',pg_temp.wdate()+2,'reason','Synthetic original recovery reversal'),1,'corr.settle.reverse');
select throws_ok($q$select pg_temp.cs(jsonb_build_object('action','reverse','id',pg_temp.wid('corr.settlement'),'correction_id',pg_temp.wid('corr.one'),
 'posting_date',pg_temp.wdate()+2,'reason','Synthetic repeat'),2,'corr.settle.reverse.again')$q$,'55000','PAYROLL_SETTLEMENT_ALREADY_REVERSED','settlement original reversed once');
insert into correction_client_samples values('restoration_prepared',pg_temp.cc(pg_temp.correction_prepare(3600,'corr.two'),0,'corr.two.prepare'));
select is(pg_temp.cdetail('calculation','corr.two')->'items'->0->'difference'->>'net','50.000000','restoration recomputes original full pay then subtracts last rounded pay');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','corr.two'),1,'corr.two.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','corr.two'),2,'corr.two.post');
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('reverse'),3,'corr.earlier.reverse')$q$,'55000','PAYROLL_LATER_CORRECTION_BLOCKS_REVERSAL','later correction protects original difference');
select pg_temp.cc(pg_temp.correction_action('reverse','corr.two'),3,'corr.two.reverse');
select pg_temp.cc(pg_temp.correction_action('reverse'),3,'corr.one.reverse');
insert into correction_client_samples values('history',pg_temp.cdetail('history'));
reset role;
select is((select sum(amount) from people_payroll.correction_balance_effects),0::numeric,'all original signed correction balances reverse exactly');
select is((select sum(base_debit-base_credit) from finance.journal_lines where tenant_id=pg_temp.wid('tenant')),0::numeric,'off-cycle and recovery journals conserve');
select is((select count(*)::integer from people_payroll.correction_payslips),2,'difference payslips remain immutable after reversals');
select throws_ok($q$update people_payroll.correction_payslips set digest='changed'$q$,'55000','PAYROLL_CORRECTION_HISTORY_IMMUTABLE','difference payslip immutable');
select is((select seconds from people_payroll.correction_source_effects order by version desc limit 1),3600::bigint,'reversal stack restores original eligibility with new source versions');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.payroll.post';
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post'),2,'corr.post')$q$,'42501',null,'revocation rechecked before correction replay');
select throws_ok($q$select api.people_payroll_correction_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.post'),'post')$q$,'42501',null,'revocation rechecked before own correction receipt');
reset role;

-- Legitimate approved worked geometry changes are a distinct linked vertical.
insert into core.role_permissions(tenant_id,role_id,permission_code) values
 (pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'people.payroll.post') on conflict do nothing;
create function pg_temp.geometry_prepare() returns jsonb language sql security definer as $$
 select pg_temp.correction_prepare(7200,'corr.geometry')||jsonb_build_object('replacements',jsonb_build_array(
 (pg_temp.correction_prepare(7200,'corr.geometry')->'replacements'->0)||jsonb_build_object('impact',jsonb_build_object(
  'mode','geometry','expected_source_version',a.version,'start_local',to_char(r.start_local,'YYYY-MM-DD"T"HH24:MI:SS'),
  'end_local',to_char(r.end_local+interval '1 hour','YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',r.start_offset_seconds,'end_offset_seconds',r.end_offset_seconds,'breaks',r.breaks))))
 from people.attendance_entries a join people.attendance_revisions r on r.id=a.current_revision_id where a.id=pg_temp.wid('corr.attendance') $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.geometry_prepare(),0,'corr.geometry.prepare');
select is(pg_temp.cdetail('calculation','corr.geometry')->'items'->0->'difference'->>'net','100.000000','geometry difference can increase legitimate approved worked seconds');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','corr.geometry'),1,'corr.geometry.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','corr.geometry'),2,'corr.fail.post')$q$,'P0001','SYNTHETIC_CORRECTION_LATE_FAILURE','late geometry posting failure rolls back source and payroll together');
reset role;
select is((select payable_seconds from people.attendance_revisions where id=(select current_revision_id from people.attendance_entries where id=pg_temp.wid('corr.attendance'))),3600::bigint,'failed geometry post retains original worked duration');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','corr.geometry'),2,'corr.geometry.post');
reset role;
create function pg_temp.geometry_reverse_credits() returns jsonb language sql security definer as $$
 select pg_temp.correction_action('reverse','corr.geometry')||jsonb_build_object('current_billing_impacts',jsonb_build_array(
  jsonb_build_object('seal_id',s.seal_id,'source_revision_id',state.body->>'operational_source_id',
   'expected_source_version',(state.body->>'operational_source_version')::bigint,
   'billing_credit_line_ids','[]'::jsonb,'allocation_credits','[]'::jsonb)))
 from people_payroll.correction_sources s cross join lateral(select people_payroll.correction_source_state(s.seal_id) body) state
 where s.correction_id=pg_temp.wid('corr.geometry') $$;
select is((select payable_seconds from people.attendance_revisions where id=(select current_revision_id from people.attendance_entries where id=pg_temp.wid('corr.attendance'))),7200::bigint,'geometry post appends authoritative approved attendance revision');
select is((select count(*)::integer from people.attendance_revisions where entry_id=pg_temp.wid('corr.attendance')),2,'original attendance revision remains immutable');
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and active),1,'geometry replacement has one current payable owner');
select throws_ok($q$select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('corr.attendance')))$q$,'55000','PAYROLL_INPUT_SEALED','replacement source retains ordinary payroll seal guard');
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.geometry_reverse_credits()||jsonb_build_object('current_billing_impacts',jsonb_build_array(
 (pg_temp.geometry_reverse_credits()->'current_billing_impacts'->0)||jsonb_build_object('expected_source_version',1))),3,'corr.geometry.stale.current')$q$,
 '40001','PAYROLL_CORRECTION_SOURCE_CHANGED','current reverse source version is authoritative before credit proof');
select throws_ok($q$select pg_temp.cc(pg_temp.geometry_reverse_credits()||jsonb_build_object('current_billing_impacts',jsonb_build_array(
 (pg_temp.geometry_reverse_credits()->'current_billing_impacts'->0)||jsonb_build_object('billing_credit_line_ids',jsonb_build_array(pg_temp.wid('foreign.credit'))))),3,'corr.geometry.foreign.current')$q$,
 '22023','PAYROLL_CURRENT_BILLING_IMPACT_INVALID','attendance cannot claim direct customer credit proof');
select pg_temp.cc(pg_temp.geometry_reverse_credits(),3,'corr.geometry.reverse');
reset role;
select is((select payable_seconds from people.attendance_revisions where id=(select current_revision_id from people.attendance_entries where id=pg_temp.wid('corr.attendance'))),3600::bigint,'geometry reversal appends original-basis geometry as a fresh approved revision');
select is((select count(*)::integer from people.attendance_revisions where entry_id=pg_temp.wid('corr.attendance')),3,'geometry reversal never rewrites prior revisions');
select is((select count(*)::integer from people.attendance_events where entry_id=pg_temp.wid('corr.attendance') and action='correct'),2,'native attendance history retains linked apply and original-basis reversal');
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and active),1,'geometry reversal retains exactly one current payable owner');
select ok(not has_function_privilege('authenticated','people_payroll.replace_claim(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,timestamptz,timestamptz,jsonb,uuid)','EXECUTE'),'trusted claim replacement unavailable to clients');
select ok(not has_function_privilege('authenticated','people_payroll.source_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'trusted source impact unavailable to clients');

-- Approved paid leave: corrections reverse original grant effects atomically.
create function pg_temp.clp(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_leave_policy_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
create function pg_temp.clr(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_leave_request_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
create function pg_temp.clreq(key text,day_offset integer) returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid(key),'employee_id',pg_temp.wid('manager'),
  'policy_version_id',pg_temp.wid('corr.leave.policy.v1'),'calendar_version_id',pg_temp.wid('calendar-version'),
  'start_local',to_char((pg_temp.wdate()+day_offset)::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),
  'end_local',to_char((pg_temp.wdate()+day_offset)::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',19800,'end_offset_seconds',19800,'reason','Synthetic original paid leave') $$;
create function pg_temp.clstate(act text,key text,balance bigint default null) returns jsonb language sql as $$
 select jsonb_build_object('action',act,'id',pg_temp.wid(key),'employee_id',pg_temp.wid('manager'),'reason','Synthetic leave decision')||
 case when balance is null then '{}'::jsonb else jsonb_build_object('balance_version',balance) end $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.clp(jsonb_build_object('action','create','id',pg_temp.wid('corr.leave.policy'),'version_id',pg_temp.wid('corr.leave.policy.v1'),
 'code','CORRLEAVE','name','Synthetic correction leave','start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,
 'unit','hours','day_seconds',28800,'accrual_frequency','once','accrual_seconds',3600,'carry_cap_seconds',3600,'expiry_days',365,
 'eligible_types',jsonb_build_array('permanent'),'allow_unpaid',false,'reason','Synthetic leave policy'),0,'corr.leave.policy.create');
select api.people_leave_grant_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.leave.grant'),pg_temp.wid('corr.leave.grant'),now(),
 jsonb_build_object('action','adjust','id',pg_temp.wid('corr.leave.grant'),'employee_id',pg_temp.wid('manager'),
 'policy_version_id',pg_temp.wid('corr.leave.policy.v1'),'effective_date',pg_temp.wdate(),'source_key','CORR-LEAVE-GRANT','seconds',3600,'reason','Synthetic original grant'),0);
select pg_temp.clr(pg_temp.clreq('corr.leave.request',7),0,'corr.leave.create');
select pg_temp.clr(pg_temp.clstate('submit','corr.leave.request'),1,'corr.leave.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.clr(pg_temp.clstate('approve','corr.leave.request',1),2,'corr.leave.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_create('corr.leave.run')||jsonb_build_object('start_date',pg_temp.wdate()+7,'end_date_exclusive',pg_temp.wdate()+8,
 'posting_date',pg_temp.wdate()+8,'employee_ids',jsonb_build_array(pg_temp.wid('manager'))),0,'corr.leave.run.create');
select pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('corr.leave.run'),'reason','Synthetic leave freeze'),1,'corr.leave.run.prepare');
select pg_temp.pcmd(pg_temp.run_action('submit','corr.leave.run'),2,'corr.leave.run.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('approve','corr.leave.run'),3,'corr.leave.run.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('post','corr.leave.run'),4,'corr.leave.run.post');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select throws_ok($q$select pg_temp.clr(pg_temp.clstate('cancel','corr.leave.request',2),3,'corr.leave.ordinary.cancel')$q$,'55000','PAYROLL_INPUT_SEALED','ordinary cancellation of payroll sealed leave remains guarded');
reset role;
create function pg_temp.leave_correction_prepare() returns jsonb language sql security definer as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid('corr.leave.cancel'),'original_calculation_id',c.id,'posting_date',pg_temp.wdate()+8,
 'reason','Synthetic linked original paid leave cancellation','replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,
 'before_revision_id',people_payroll.correction_source_state(s.id)->>'revision_id','expected_version',(people_payroll.correction_source_state(s.id)->>'version')::bigint,
 'paid_seconds',0,'impact',jsonb_build_object('mode','cancel_leave','expected_source_version',l.version))))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 join people.leave_requests l on l.active_claim_id=s.claim_id where c.run_id=pg_temp.wid('corr.leave.run') $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.leave_correction_prepare(),0,'corr.leave.cancel.prepare');
select is(pg_temp.cdetail('calculation','corr.leave.cancel')->'items'->0->'difference'->>'net','-100.000000','paid leave correction recomputes original rounded payroll basis');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','corr.leave.cancel'),1,'corr.leave.cancel.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','corr.leave.cancel'),2,'corr.fail.post')$q$,'P0001','SYNTHETIC_CORRECTION_LATE_FAILURE','late paid leave post failure rolls back source balance and journal');
reset role;
select is((select status from people.leave_requests where id=pg_temp.wid('corr.leave.request')),'approved','failed paid leave impact retains approved request');
select is((select sum(seconds) from people.leave_effects where request_id=pg_temp.wid('corr.leave.request')),-3600::numeric,'failed paid leave impact retains original debit');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','corr.leave.cancel'),2,'corr.leave.cancel.post');
select is(api.people_leave_balance(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),pg_temp.wid('corr.leave.policy'),pg_temp.wdate()+7)->>'available_seconds','3600','linked cancellation restores original grant balance');
select is(jsonb_array_length(api.people_payroll_correction_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select response->'entity'->>'original_calculation_id' from correction_client_samples where name='prepared')::uuid)->'items'),1,'source picker retains original identity after unrelated linked correction');
select pg_temp.clr(pg_temp.clreq('corr.leave.consumer',14),0,'corr.leave.consumer.create');
select pg_temp.clr(pg_temp.clstate('submit','corr.leave.consumer'),1,'corr.leave.consumer.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.clr(pg_temp.clstate('approve','corr.leave.consumer',3),2,'corr.leave.consumer.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('reverse','corr.leave.cancel')||jsonb_build_object('posting_date',pg_temp.wdate()+15),3,'corr.leave.cancel.blocked.reverse')$q$,'55000','LEAVE_ORIGINAL_BALANCE_IMPACT_REQUIRED','reversal refuses a restored original grant already consumed by later leave');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.clr(pg_temp.clstate('cancel','corr.leave.consumer',4),3,'corr.leave.consumer.cancel');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','corr.leave.cancel')||jsonb_build_object('posting_date',pg_temp.wdate()+15),3,'corr.leave.cancel.reverse');
select is(api.people_leave_balance(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),pg_temp.wid('corr.leave.policy'),pg_temp.wdate()+7)->>'available_seconds','0','reversal reconsumes exact original grant with a new negative effect');
reset role;
select is((select status from people.leave_requests where id=pg_temp.wid('corr.leave.request')),'approved','leave reversal restores original approved operational request');
select is((select count(*)::integer from people.leave_effects where request_id=pg_temp.wid('corr.leave.request')),3,'original debit cancellation and reversal remain immutable');
select is((select count(*)::integer from people.leave_events where request_id=pg_temp.wid('corr.leave.request')),5,'native leave history retains linked cancellation and original-basis reversal');
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='leave' and active),1,'leave reversal restores exactly one active payable owner');
select is((select net from people_payroll.employee_calculations where run_id=pg_temp.wid('corr.leave.run')),100::numeric,'original posted leave calculation remains unchanged');
select throws_ok($q$select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),
 (select active_claim_id from people.leave_requests where id=pg_temp.wid('corr.leave.request')))$q$,'55000','PAYROLL_INPUT_SEALED','restored paid leave remains sealed against ordinary cancellation');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.attendance.approve';
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','corr.geometry'),2,'corr.geometry.post')$q$,'42501',null,'source authority is rechecked before confirmed post replay');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'people.attendance.approve') on conflict do nothing;
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code in('people.payroll.correction.prepare','people.attendance.manage');
select pg_temp.wactor('creator');set local role authenticated;
select ok(jsonb_array_length(api.people_payroll_correction_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select response->'entity'->>'original_calculation_id' from correction_client_samples where name='prepared')::uuid)->'items')>0,
 'independent source reader can inspect current facts without preparation authority');
select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.prepare')$q$,'42501',null,
 'preparation authority remains required before confirmed prepare replay');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('creator.role'),p from unnest(array['people.payroll.correction.prepare','people.attendance.manage']) p on conflict do nothing;
-- Real scoped common ownership rows exercise the bound before module effects.
create temporary table correction_bound_claim as
 select people.make_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),
 'attendance',pg_temp.wid('corr.bound.source'),(pg_temp.wdate()+28)::timestamp+interval '9 hours' at time zone 'Asia/Colombo',
 (pg_temp.wdate()+28)::timestamp+interval '10 hours' at time zone 'Asia/Colombo','[]',pg_temp.wid('calendar-version'),pg_temp.wid('creator')) id;
insert into people.work_allocations(id,tenant_id,legal_entity_id,branch_id,employee_id,claim_id,source_kind,source_id,start_utc,end_utc,created_by)
select pg_temp.wid('corr.bound.allocation.'||i),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),c.id,
 'project',pg_temp.wid('corr.bound.project.source.'||i),w.start_utc+make_interval(secs=>i*2),w.start_utc+make_interval(secs=>i*2+1),pg_temp.wid('creator')
from generate_series(1,51) i cross join correction_bound_claim c join people.work_claims w on w.id=c.id;
select throws_ok($q$select people_payroll.linked_allocation_bound(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('manager'),(select id from correction_bound_claim),'[]')$q$,'55000','WORK_ALLOCATION_IMPACT_BOUND_REQUIRED',
 '51 scoped distinct allocated sources fail before linked module effects');
delete from people.work_allocations where id=pg_temp.wid('corr.bound.allocation.51');
create function pg_temp.cbound_ok() returns boolean language plpgsql as $$begin
 perform people_payroll.linked_allocation_bound(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('manager'),(select id from correction_bound_claim),'[]');return true;end $$;
select ok(pg_temp.cbound_ok(),'50 scoped distinct allocated sources remain within bound');
select throws_ok($q$select people_payroll.linked_allocation_bound(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),null,
 (select jsonb_agg(jsonb_build_object('source_kind','project','impact',jsonb_build_object('entry_id',pg_temp.wid('corr.bound.project.entry.'||i))))
  from generate_series(1,51) i))$q$,'55000','WORK_ALLOCATION_IMPACT_BOUND_REQUIRED',
 '51 frozen removed origins fail the reversal bound without truncation');
delete from people.work_allocations where claim_id=(select id from correction_bound_claim);
select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),(select id from correction_bound_claim));
