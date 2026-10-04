reset role;
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.projects',true) on conflict do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p
where p.module='projects' or p.code='people.payroll.post' on conflict do nothing;
select pg_temp.wactor('creator');
create temporary table project_impact_samples(name text primary key,body jsonb);
grant select,insert on project_impact_samples to authenticated;
create function pg_temp.project_impact_command(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.projects_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
set local role authenticated;
select pg_temp.project_impact_command(jsonb_build_object('action','create','id',pg_temp.wid('linked.project'),'code','LINKED',
 'name','Synthetic linked correction project','manager_id',pg_temp.wid('manager'),'currency_code','LKR',
 'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+1,'reason','Synthetic impact fixture'),0,'linked.project.create');
select pg_temp.project_impact_command(jsonb_build_object('action','plan','id',pg_temp.wid('linked.project'),'plan_id',pg_temp.wid('linked.plan'),
 'terms','Synthetic exact linked labor','budget','1000.00','reason','Synthetic governed impact plan',
 'tasks',jsonb_build_array(jsonb_build_object('id',pg_temp.wid('linked.task'),'name','Linked task','owner_id',pg_temp.wid('manager'),'start_date',pg_temp.wdate(),
 'end_date_exclusive',pg_temp.wdate()+1,'planned_seconds',3600,'dependencies','[]'::jsonb)),
 'resources',jsonb_build_array(jsonb_build_object('id',pg_temp.wid('linked.slot'),'task_id',pg_temp.wid('linked.task'),'employee_id',pg_temp.wid('manager'),
 'calendar_version_id',pg_temp.wid('calendar-version'),'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'bill_rate','54.00','cost_rate','18.00'))),1,'linked.project.plan');
reset role;
insert into project_impact_samples values('plan_approval',jsonb_build_object('action','approve_plan','id',pg_temp.wid('linked.project'),'plan_id',pg_temp.wid('linked.plan'),
 'digest',(select basis_digest from projects.plans where id=pg_temp.wid('linked.plan')),'reason','Independent exact impact plan'));
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.project_impact_command((select body from project_impact_samples where name='plan_approval'),2,'linked.plan.approve');
reset role;
-- The fixture original payroll has already sealed this one attendance claim.
insert into project_impact_samples values('time_creation',jsonb_build_object('action','time_create','id',pg_temp.wid('linked.time'),
 'project_id',pg_temp.wid('linked.project'),'employee_id',pg_temp.wid('manager'),'resource_slot_id',pg_temp.wid('linked.slot'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours 30 minutes','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,
 'attendance_claim_id',(select active_claim_id from people.attendance_entries where id=pg_temp.wid('corr.attendance')),
 'reason','Synthetic already payable labor allocation'));
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.project_impact_command((select body from project_impact_samples where name='time_creation'),0,'linked.time.create');
select pg_temp.project_impact_command(jsonb_build_object('action','time_submit','id',pg_temp.wid('linked.time'),
 'project_id',pg_temp.wid('linked.project'),'employee_id',pg_temp.wid('manager'),'reason','Synthetic submit'),1,'linked.time.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.project_impact_command(jsonb_build_object('action','time_approve','id',pg_temp.wid('linked.time'),
 'project_id',pg_temp.wid('linked.project'),'employee_id',pg_temp.wid('manager'),'reason','Synthetic independent approval'),2,'linked.time.approve');
reset role;
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='attendance' and active),1,'allocation never adds payroll eligibility');
select is((select amount from projects.time_costs where project_id=pg_temp.wid('linked.project')),9::numeric,'independent exact original project cost');
select ok(not has_function_privilege('authenticated','projects.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'client cannot bypass linked impact guard');
select ok(not has_table_privilege('authenticated','projects.payroll_time_impacts','SELECT'),'linked impact base reads denied');
create function pg_temp.linked_correction(key text,minute integer,remove_allocation boolean default false) returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid(key),'original_calculation_id',c.id,'posting_date',pg_temp.wdate()+1,
 'reason','Synthetic linked geometry correction','replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,
 'before_revision_id',state->>'revision_id','expected_version',(state->>'version')::bigint,'paid_seconds',(minute-540)*60,
 'impact',jsonb_build_object('mode','geometry','expected_source_version',a.version,
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+make_interval(mins=>minute),'YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,
 'allocation_changes',case when remove_allocation then jsonb_build_array(jsonb_build_object('entry_id',pg_temp.wid('linked.time'),'mode','remove')) else '[]'::jsonb end))))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 cross join lateral(select people_payroll.correction_source_state(s.id) state) v
 join people.attendance_entries a on a.active_claim_id=(state->>'claim_id')::uuid
 where c.run_id=pg_temp.wid('corr.original') and s.claim_id=(c.inputs->'sources'->0->>'claim_id')::uuid $$;
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.linked_correction('linked.invalid',555),0,'linked.invalid.prepare')$q$,
 '55000','PROJECT_ALLOCATION_GEOMETRY_IMPACT_REQUIRED','revised attendance cannot silently truncate project time');
insert into project_impact_samples values('prepared',pg_temp.cc(pg_temp.linked_correction('linked.correction',585),0,'linked.correction.prepare'));
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','linked.correction'),1,'linked.correction.approve');
reset role;
create function pg_temp.project_allocation_probe(proof_change text,p_mode text default 'release') returns jsonb
language plpgsql as $$declare source people_payroll.correction_sources%rowtype;effect jsonb;proposal jsonb;begin
 select * into source from people_payroll.correction_sources where correction_id=pg_temp.wid('linked.correction');
 effect:=source.impact->'after'->'allocation_impacts'->0;
 proposal:=source.impact||jsonb_build_object('correction_id',source.correction_id,'attendance_after',source.impact->'after',
  'allocation_impact',effect->'impact','new_claim_id',pg_temp.wid('not-a-scoped-attendance-claim'));
 if proof_change='before' then proposal:=jsonb_set(proposal,'{allocation_impact,before,cost_rate}','"123.000000"');
 elsif proof_change='after' then proposal:=jsonb_set(proposal,'{allocation_impact,after,cost_amount}','"123.000000"');end if;
 return projects.payroll_allocation_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),
  (effect->>'allocation_id')::uuid,source.after_revision_id,proposal,p_mode);
end $$;
select throws_ok($q$select pg_temp.project_allocation_probe('before')$q$,'40001','PAYROLL_CORRECTION_SOURCE_CHANGED',
 'linked release rejects changed complete original cost proof');
select throws_ok($q$select pg_temp.project_allocation_probe('after')$q$,'40001','PAYROLL_CORRECTION_SOURCE_CHANGED',
 'linked release rejects changed complete calculated cost proof');
select throws_ok($q$select pg_temp.project_allocation_probe('none','apply')$q$,'55000','PROJECT_ATTENDANCE_SOURCE_INVALID',
 'linked mutation requires the actual scoped replacement attendance claim');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into project_impact_samples values('posted',pg_temp.cc(pg_temp.correction_action('post','linked.correction'),2,'linked.correction.post'));
reset role;
select is((select payable_seconds from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='attendance' and active),2700::bigint,'actual revised attendance owns exact reduced seconds');
select is((select count(*)::integer from projects.time_revisions where entry_id=pg_temp.wid('linked.time')),2,'linked project time appends a revision');
select is((select sum(extract(epoch from end_utc-start_utc))::bigint from people.work_allocations where employee_id=pg_temp.wid('manager') and active),1800::bigint,'retained allocation conserves its own exact seconds');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('linked.project') and status='available'),1,'correction creates exactly one current billable unit');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('linked.project') and status='cancelled'),1,'original unbilled unit remains retained cancelled history');
select is((select count(*)::integer from projects.payroll_time_impacts),1,'one immutable module impact per entry');
select throws_ok($q$select projects.payroll_revision_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('manager'),pg_temp.wid('linked.time'),(select active_claim_id from people.attendance_entries where id=pg_temp.wid('corr.attendance')),
 gen_random_uuid(),jsonb_build_object('correction_id',pg_temp.wid('unrelated-correction'),'operational_mode','reverse'),
 'validate',false)$q$,'40001','PAYROLL_CORRECTION_SOURCE_CHANGED',
 'old or unrelated reversal cannot supersede the current linked project revision');
select pg_temp.wactor('reviewer');set local role authenticated;
insert into project_impact_samples values('reversed',pg_temp.cc(pg_temp.correction_action('reverse','linked.correction'),3,'linked.correction.reverse'));
reset role;
select is((select payable_seconds from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='attendance' and active),3600::bigint,'reversal appends original attendance geometry');
select is((select count(*)::integer from projects.time_revisions where entry_id=pg_temp.wid('linked.time')),3,'reversal keeps both previous project revisions');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('linked.project') and status='available'),1,'reversal retains one current source without reviving original unit');
select is((select count(*)::integer from projects.payroll_time_impacts),2,'module impact reversal is separately attributable');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.linked_correction('linked.remove',555,true),0,'linked.remove.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','linked.remove'),1,'linked.remove.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','linked.remove'),2,'linked.remove.post');
reset role;
select is((select payable_seconds from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='attendance' and active),900::bigint,'explicit removal allows truthful short attendance');
select is((select count(*)::integer from people.work_allocations where employee_id=pg_temp.wid('manager') and active),0,'governed removal leaves no invalid project allocation');
select is((select status from projects.time_entries where id=pg_temp.wid('linked.time')),'cancelled','removed project source is visibly cancelled');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('linked.project') and status='available'),0,'removed geometry leaves no invented billable units');
insert into project_impact_samples values('removed_sources_request',jsonb_build_object('calculation_id',
 (select id from people_payroll.employee_calculations where run_id=pg_temp.wid('corr.original'))));
select pg_temp.wactor('reviewer');set local role authenticated;
insert into project_impact_samples values('removed_sources',api.people_payroll_correction_sources(
 pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select (body->>'calculation_id')::uuid from project_impact_samples where name='removed_sources_request'),null));
reset role;
select is(jsonb_array_length((select body->'items'->0->'operational'->'allocations' from project_impact_samples where name='removed_sources')),1,
 'removed allocation remains one deduplicated authorized current source');
select ok((select body->'items'->0->'operational'->'allocations'->0->>'active'='false'
 and (body->'items'->0->'operational'->'allocations'->0->'operational'->>'source_id')::uuid=
 (select current_revision_id from projects.time_entries where id=pg_temp.wid('linked.time'))
 and (body->'items'->0->'operational'->'allocations'->0->'operational'->>'source_version')::bigint=
 (select version from projects.time_entries where id=pg_temp.wid('linked.time'))
 from project_impact_samples where name='removed_sources'),
 'reversal source picker binds removed allocation to current cancelled revision and version');
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','linked.remove'),3,'linked.remove.reverse');
reset role;
select is((select payable_seconds from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='attendance' and active),3600::bigint,'reversal restores attendance after project removal');
select is((select sum(extract(epoch from end_utc-start_utc))::bigint from people.work_allocations where employee_id=pg_temp.wid('manager') and active),1800::bigint,'frozen removed allocation is restored despite no active allocation');
select is((select status from projects.time_entries where id=pg_temp.wid('linked.time')),'approved','restored project source receives a new approval revision');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('linked.project') and status='available'),1,'restoration issues exactly one fresh immutable source');
select throws_ok($q$update projects.payroll_time_impacts set body='{}'$q$,'55000','PROJECT_HISTORY_IMMUTABLE','module impact history cannot be overwritten');

-- A separate day proves direct project work is the sole payroll-eligible claim.
-- The original posted calculation remains frozen while governed corrections
-- append operational geometry, allocation/cost and billing history atomically.
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.project_impact_command(jsonb_build_object('action','create','id',pg_temp.wid('direct.project'),'code','DIRECT',
 'name','Synthetic direct payroll project','manager_id',pg_temp.wid('manager'),'currency_code','LKR',
 'start_date',pg_temp.wdate()+21,'end_date_exclusive',pg_temp.wdate()+22,'reason','Synthetic direct source fixture'),0,'direct.project.create');
select pg_temp.project_impact_command(jsonb_build_object('action','plan','id',pg_temp.wid('direct.project'),'plan_id',pg_temp.wid('direct.plan'),
 'terms','Synthetic direct payroll geometry','budget','1000.00','reason','Synthetic governed direct source',
 'tasks',jsonb_build_array(jsonb_build_object('id',pg_temp.wid('direct.task'),'name','Direct task','owner_id',pg_temp.wid('manager'),'start_date',pg_temp.wdate()+21,
 'end_date_exclusive',pg_temp.wdate()+22,'planned_seconds',3600,'dependencies','[]'::jsonb)),
 'resources',jsonb_build_array(jsonb_build_object('id',pg_temp.wid('direct.slot'),'task_id',pg_temp.wid('direct.task'),'employee_id',pg_temp.wid('manager'),
 'calendar_version_id',pg_temp.wid('calendar-version'),'start_local',to_char((pg_temp.wdate()+21)::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char((pg_temp.wdate()+21)::timestamp+interval '11 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'bill_rate','54.00','cost_rate','18.00'))),1,'direct.project.plan');
reset role;
insert into project_impact_samples values('direct_plan_approval',jsonb_build_object('action','approve_plan','id',pg_temp.wid('direct.project'),
 'plan_id',pg_temp.wid('direct.plan'),'digest',(select basis_digest from projects.plans where id=pg_temp.wid('direct.plan')),'reason','Independent direct plan'));
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.project_impact_command((select body from project_impact_samples where name='direct_plan_approval'),2,'direct.plan.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.project_impact_command(jsonb_build_object('action','time_create','id',pg_temp.wid('direct.time'),
 'project_id',pg_temp.wid('direct.project'),'employee_id',pg_temp.wid('manager'),'resource_slot_id',pg_temp.wid('direct.slot'),
 'start_local',to_char((pg_temp.wdate()+21)::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char((pg_temp.wdate()+21)::timestamp+interval '11 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,'reason','Synthetic direct payroll source'),0,'direct.time.create');
select pg_temp.project_impact_command(jsonb_build_object('action','time_submit','id',pg_temp.wid('direct.time'),
 'project_id',pg_temp.wid('direct.project'),'employee_id',pg_temp.wid('manager'),'reason','Synthetic direct submit'),1,'direct.time.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.project_impact_command(jsonb_build_object('action','time_approve','id',pg_temp.wid('direct.time'),
 'project_id',pg_temp.wid('direct.project'),'employee_id',pg_temp.wid('manager'),'reason','Independent direct time'),2,'direct.time.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_create('direct.run')||jsonb_build_object('start_date',pg_temp.wdate()+21,
 'end_date_exclusive',pg_temp.wdate()+22,'posting_date',pg_temp.wdate()+21,'employee_ids',jsonb_build_array(pg_temp.wid('manager'))),0,'direct.run.create');
select pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('direct.run'),'reason','Freeze actual direct source'),1,'direct.run.prepare');
select pg_temp.pcmd(pg_temp.run_action('submit','direct.run'),2,'direct.run.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('approve','direct.run'),3,'direct.run.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('post','direct.run'),4,'direct.run.post');
reset role;
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager')
 and source_kind='project' and active),1,'direct project work owns one payroll claim');
select is((select inputs->>'paid_seconds' from people_payroll.employee_calculations where run_id=pg_temp.wid('direct.run')),
 '3600','posted payroll consumed exact direct seconds');
create function pg_temp.direct_project_correction() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid('direct.correction'),'original_calculation_id',c.id,
 'posting_date',pg_temp.wdate()+22,'reason','Synthetic governed direct source correction',
 'replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,'before_revision_id',state->>'revision_id',
 'expected_version',(state->>'version')::bigint,'paid_seconds',1800,'impact',jsonb_build_object('mode','geometry',
 'expected_source_version',x.version,'start_local',to_char((pg_temp.wdate()+21)::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char((pg_temp.wdate()+21)::timestamp+interval '10 hours 30 minutes','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb))))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 cross join lateral(select people_payroll.correction_source_state(s.id) state) v
 join projects.time_entries x on x.id=pg_temp.wid('direct.time')
 where c.run_id=pg_temp.wid('direct.run') and s.claim_id=(c.inputs->'sources'->0->>'claim_id')::uuid $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.direct_project_correction(),0,'direct.correction.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','direct.correction'),1,'direct.correction.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','direct.correction'),2,'direct.correction.post');
reset role;
select is((select payable_seconds from people.work_claims where employee_id=pg_temp.wid('manager')
 and source_kind='project' and active),1800::bigint,'governed direct correction replaces eligible geometry');
select is((select count(*)::integer from projects.time_revisions where entry_id=pg_temp.wid('direct.time')),2,
 'direct correction retains original sealed revision');
select is((select c.amount from projects.time_costs c join projects.time_entries x on x.current_revision_id=c.revision_id
 where x.id=pg_temp.wid('direct.time')),9::numeric,'direct corrected internal cost follows exact seconds');
select is((select amount from projects.billable_units where project_id=pg_temp.wid('direct.project') and status='available'),
 27::numeric,'direct corrected whole unit retains exact customer amount');
select is((select inputs->>'paid_seconds' from people_payroll.employee_calculations where run_id=pg_temp.wid('direct.run')),
 '3600','original posted payroll remains immutable');
select ok(exists(select 1 from projects.time_allocations a join people.work_input_seals s on s.claim_id=a.claim_id
 join projects.time_entries x on x.current_revision_id=a.revision_id where x.id=pg_temp.wid('direct.time') and s.run_id=pg_temp.wid('direct.run')),
 'replacement direct claim is sealed against ordinary cancellation');
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.project_impact_command(jsonb_build_object('action','time_cancel','id',pg_temp.wid('direct.time'),
 'project_id',pg_temp.wid('direct.project'),'employee_id',pg_temp.wid('manager'),'reason','Cannot erase consumed work'),4,'direct.time.cancel')$q$,
 '55000',null,'ordinary time cancellation cannot erase corrected sealed claim');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','direct.correction')||jsonb_build_object('posting_date',pg_temp.wdate()+23),3,'direct.correction.reverse');
reset role;
select is((select payable_seconds from people.work_claims where employee_id=pg_temp.wid('manager')
 and source_kind='project' and active),3600::bigint,'direct reversal appends original geometry');
select is((select count(*)::integer from projects.time_revisions where entry_id=pg_temp.wid('direct.time')),3,
 'direct reversal keeps corrected and original revision history');
select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('direct.project') and status='available'),1,
 'direct reversal creates one new unit without reviving old units');
