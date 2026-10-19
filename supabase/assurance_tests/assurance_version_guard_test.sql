-- Corporate Audit & Assurance version-guard candidate tests (PR #1 review).
-- Included only by build_assurance_candidate.ps1 -Slice A6, after the A5 tests
-- and the guard candidate DDL. Reuses eng7, ctl7, u.pay and the planning grants.
select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.c2(pg_temp.e2('map_control','eng7')||jsonb_build_object('control_id',pg_temp.aid('ctl7.g'),
  'control_code','TRS-NULL','title','Null version probe','owner_id',pg_temp.aid('owner'),'risk','low'),null,'g.map')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','engagement commands reject a null expected version');
select throws_ok($$select pg_temp.c2(pg_temp.e2('create_engagement','engG')||jsonb_build_object('name','Null version create',
  'period_start','2026-04-01','period_end','2027-03-31','scope_summary','Probe','lead_auditor_id',pg_temp.aid('lead')),null,'g.create')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','creation requires expected version 0, not null');
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','assess_risk','item_id',pg_temp.aid('u.pay'),
  'assessment_id',pg_temp.aid('a.null'),'likelihood',3,'impact',3,'rationale','Null version probe'),null,'g.assess')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','planning commands reject a null expected version');
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','register_item','item_id',pg_temp.aid('u.null'),'code','NULLV',
  'name','Null version','category','process','owner_id',pg_temp.aid('owner')),null,'g.reg')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','universe registration requires version 0, not null');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.e2('design_test','eng7')||jsonb_build_object('procedure_id',pg_temp.aid('tp.null'),
  'control_id',pg_temp.aid('ctl7'),'code','NULLV','objective','Null version probe','population_size',10,'sample_start',1),null,'g.test')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','test commands reject a null expected version');
select throws_ok($$select pg_temp.ec(pg_temp.e2('run_monitoring','eng7')||jsonb_build_object('evidence_id',pg_temp.aid('ev.null'),
  'control_id',pg_temp.aid('ctl7')),null,'g.ev')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','evidence commands reject a null expected version');
select pg_temp.c2(pg_temp.e2('record_exception','eng7')||jsonb_build_object('exception_id',pg_temp.aid('x7.g'),'control_id',pg_temp.aid('ctl7'),
  'description','Current version still accepted','severity','low'),pg_temp.vv('eng7'),'g.ok');
reset role;
select is((select count(*)::integer from assurance.events where engagement_id=pg_temp.aid('eng7')),
  (select version::integer from assurance.engagements where id=pg_temp.aid('eng7')),'guard: a current version still commits; one event per version');
select ok(not has_function_privilege('authenticated','assurance.prepare_command(uuid,uuid,uuid,uuid,jsonb,bigint,text,text[],boolean)','EXECUTE')
  and has_function_privilege('authenticated','api.assurance_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_plan_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE'),
  'guard: replaced functions keep their grants');
