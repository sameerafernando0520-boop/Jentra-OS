-- Corporate Audit & Assurance A9 settings and plan revision candidate tests.
-- Included only by build_assurance_candidate.ps1 -Slice A9, after the A9
-- candidate DDL. Self-contained on the A1 actors, tenant and roles.
create function pg_temp.s9_grant(r text, p text) returns void language sql as $$
  insert into core.role_permissions(tenant_id,role_id,permission_code)
  values(pg_temp.aid('tenant'),pg_temp.aid(r||'.r'),p) on conflict do nothing $$;
create function pg_temp.s9_pc(p jsonb, v bigint, k text) returns jsonb language sql as $$
  select api.assurance_plan_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
    pg_temp.aid('key9.'||k),p,v) $$;
create function pg_temp.s9_v(k text) returns bigint language sql security definer set search_path='' as $$
  select coalesce((select version from assurance.plans where id=pg_temp.aid(k)),
    (select version from assurance.universe_items where id=pg_temp.aid(k)),0) $$;
create function pg_temp.s9_set(p jsonb, v bigint, k text) returns jsonb language sql as $$
  select api.assurance_settings_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
    pg_temp.aid('key9.'||k),p,v) $$;
create function pg_temp.s9_get() returns jsonb language sql as $$
  select api.assurance_settings(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch')) $$;
create function pg_temp.s9_mon(p_overrides jsonb default '{}') returns jsonb language sql immutable as $$
  select '{"ACCESS_PRIVILEGED_NO_MFA":{"enabled":true,"min_count":1},"P2P_MATCH_OVERRIDE":{"enabled":true,"min_count":1},
    "P2P_OVERRIDE_BY_CREATOR":{"enabled":true,"min_count":1},"HR_ATTENDANCE_SELF_APPROVAL":{"enabled":true,"min_count":1}}'::jsonb
    || p_overrides $$;
create function pg_temp.s9_body(p_level text, due integer, esc integer, resp integer, crit integer, high integer,
  med integer, mon jsonb default null) returns jsonb language sql immutable as $$
  select jsonb_build_object('level',p_level,'due_soon_days',due,'escalate_after_days',esc,'finding_response_days',resp,
    'rating_bands',jsonb_build_object('critical',crit,'high',high,'medium',med),
    'monitoring',coalesce(mon,pg_temp.s9_mon())) $$;
create function pg_temp.s9_levels() returns text[] language sql stable security definer set search_path='' as $$
  select array(select assurance.reminder_level(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),current_date+d,current_date)
    from unnest(array[7,6,5,4,3,0,-1,-7,-8,-10,-11]) d) $$;
select pg_temp.s9_grant('manager','assurance.plan.manage');
select pg_temp.s9_grant('reviewer','assurance.plan.manage');
select pg_temp.s9_grant('manager','assurance.engagement.manage');

-- Defaults reproduce today's behaviour.
select is(assurance.effective_settings(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity')),
  jsonb_build_object('source','default','due_soon_days',3,'escalate_after_days',7,'finding_response_days',14,
    'rating_bands',jsonb_build_object('critical',20,'high',10,'medium',5),'monitoring',pg_temp.s9_mon()),
  'A9: with no settings the defaults apply');
select is(pg_temp.s9_levels(),
  array['on_track','on_track','on_track','on_track','due_soon','due_soon','overdue','overdue','escalated','escalated','escalated'],
  'A9: default reminder bands match the installed levels');
select ok((select prosrc from pg_proc where oid='assurance.work_items(uuid,uuid,uuid)'::regprocedure)
  not like '%response_sla_days()%'
  and (select prosrc from pg_proc where oid='api.assurance_overview(uuid,uuid,uuid)'::regprocedure) not like '%response_sla_days()%',
  'A9: the read models no longer use the fixed-value helpers');

-- An assessment recorded before any settings keeps its rating.
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.s9_pc(jsonb_build_object('action','register_item','item_id',pg_temp.aid('u9a'),'code','S9A',
  'name','Settings area A','category','process','owner_id',pg_temp.aid('owner')),0,'u9a');
select pg_temp.s9_pc(jsonb_build_object('action','register_item','item_id',pg_temp.aid('u9b'),'code','S9B',
  'name','Settings area B','category','process','owner_id',pg_temp.aid('owner')),0,'u9b');
select pg_temp.s9_pc(jsonb_build_object('action','assess_risk','item_id',pg_temp.aid('u9a'),'assessment_id',pg_temp.aid('a9a'),
  'likelihood',2,'impact',5,'rationale','Before settings'),pg_temp.s9_v('u9a'),'a9a');
reset role;

-- Settings: read, authority, MFA, validation.
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('s9.read0',pg_temp.s9_get());
reset role;
select is((select body->'effective'->>'source' from assurance_samples where label='s9.read0'),'default','A9: settings read shows defaults');
select is((select body->'tenant' from assurance_samples where label='s9.read0'),'null'::jsonb,'A9: no tenant row yet');
select is((select jsonb_array_length(body->'rules') from assurance_samples where label='s9.read0'),4,'A9: four monitoring rules are listed');
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,20,12,6),0,'s9.auditor')$$,
  '42501',null,'A9: settings need planning rights');
reset role;select pg_temp.actor('manager',true,2000);set local role authenticated;
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,20,12,6),0,'s9.stale_mfa')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','A9: settings need recent MFA');
reset role;select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',0,10,21,20,12,6),0,'s9.bad1')$$,
  '22023','ASSURANCE_SETTINGS_INVALID','A9: due-soon days are 1 to 30');
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',5,91,21,20,12,6),0,'s9.bad2')$$,
  '22023','ASSURANCE_SETTINGS_INVALID','A9: escalation days are 1 to 90');
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,10,12,6),0,'s9.bad3')$$,
  '22023','ASSURANCE_SETTINGS_INVALID','A9: rating bands must descend');
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,20,12,6,
  pg_temp.s9_mon('{"UNKNOWN_RULE":{"enabled":true,"min_count":1}}')),0,'s9.bad4')$$,
  '22023','ASSURANCE_SETTINGS_INVALID','A9: monitoring rules are an allow-list');
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,20,12,6)||'{"extra":1}',0,'s9.bad5')$$,
  '22023','ASSURANCE_UNEXPECTED_FIELD','A9: unexpected settings fields are refused');
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,20,12,6),null,'s9.bad6')$$,
  '22023','ASSURANCE_VERSION_REQUIRED','A9: settings writes are versioned');
insert into assurance_samples values('s9.t1',pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,20,12,6,
  pg_temp.s9_mon('{"P2P_MATCH_OVERRIDE":{"enabled":false,"min_count":1},"P2P_OVERRIDE_BY_CREATOR":{"enabled":true,"min_count":3}}')),0,'s9.t1'));
insert into assurance_samples values('s9.t1r',pg_temp.s9_set(pg_temp.s9_body('tenant',5,10,21,20,12,6,
  pg_temp.s9_mon('{"P2P_MATCH_OVERRIDE":{"enabled":false,"min_count":1},"P2P_OVERRIDE_BY_CREATOR":{"enabled":true,"min_count":3}}')),0,'s9.t1'));
select throws_ok($$select pg_temp.s9_set(pg_temp.s9_body('tenant',4,10,21,20,12,6),0,'s9.t2')$$,
  '40001',null,'A9: a stale settings version is refused');
reset role;
select is((select body->>'level' from assurance_samples where label='s9.t1')||':'||(select body->>'version' from assurance_samples where label='s9.t1'),
  'tenant:1','A9: the first tenant write creates version 1');
select is((select body from assurance_samples where label='s9.t1r'),(select body from assurance_samples where label='s9.t1'),
  'A9: the same key replays the settings receipt');
select is(assurance.effective_settings(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'))->>'source','tenant',
  'A9: the tenant row applies');
select is(pg_temp.s9_levels(),
  array['on_track','on_track','due_soon','due_soon','due_soon','due_soon','overdue','overdue','overdue','overdue','escalated'],
  'A9: reminder levels follow the tenant bands');

-- Risk rating uses the bands; the earlier assessment keeps its rating.
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.s9_pc(jsonb_build_object('action','assess_risk','item_id',pg_temp.aid('u9b'),'assessment_id',pg_temp.aid('a9b'),
  'likelihood',2,'impact',5,'rationale','After settings'),pg_temp.s9_v('u9b'),'a9b');
reset role;
select is((select array_agg(rating order by id=pg_temp.aid('a9b')) from assurance.risk_assessments
  where id in (pg_temp.aid('a9a'),pg_temp.aid('a9b'))),array['high','medium'],
  'A9: new assessments use the bands and older ones keep their rating');
select is((select rating_bands from assurance.risk_assessments where id=pg_temp.aid('a9b')),
  '{"critical":20,"high":12,"medium":6}'::jsonb,'A9: an assessment records the bands it was rated with');
select throws_ok($$insert into assurance.risk_assessments(id,universe_item_id,likelihood,impact,rating,rationale,assessed_by,rating_bands)
  values(pg_temp.aid('a9bad'),pg_temp.aid('u9b'),2,5,'high','Inconsistent',pg_temp.aid('manager'),'{"critical":20,"high":12,"medium":6}')$$,
  '23514',null,'A9: a rating inconsistent with its recorded bands is refused');

-- An entity row replaces the tenant row as a whole.
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('s9.e1',pg_temp.s9_set(pg_temp.s9_body('entity',2,7,30,20,10,5),0,'s9.e1'));
insert into assurance_samples values('s9.read1',pg_temp.s9_get());
insert into assurance_samples values('s9.ov',api.assurance_overview(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch')));
reset role;
select is((select body->'effective'->>'source' from assurance_samples where label='s9.read1'),'entity','A9: the entity row overrides the tenant row');
select is((select (body->'tenant'->>'version')::integer*10+(body->'entity'->>'version')::integer from assurance_samples where label='s9.read1'),
  11,'A9: the read shows both row versions');
select is((select (body->>'response_sla_days')::integer from assurance_samples where label='s9.ov'),30,
  'A9: the overview reports the effective response deadline');
select is((select body->'reminder_bands' from assurance_samples where label='s9.ov'),
  '{"due_soon_days":2,"escalate_after_days":7}'::jsonb,'A9: the overview reports the effective reminder bands');
select is((select count(*)::integer from assurance.settings_events where tenant_id=pg_temp.aid('tenant')),2,
  'A9: every settings change is one event');
select throws_ok($$update assurance.settings_events set level='tenant'$$,null,null,'A9: settings events cannot be changed');

-- Monitoring thresholds.
select is((select count(*)::integer from assurance.monitoring_rules('procurement.three_way_match',
  '{"bills_with_match_override":2,"overrides_by_bill_creator":2}'::jsonb,pg_temp.s9_mon())),2,
  'A9: default thresholds keep both procurement rules');
select is((select count(*)::integer from assurance.monitoring_rules('procurement.three_way_match',
  '{"bills_with_match_override":2,"overrides_by_bill_creator":2}'::jsonb,
  pg_temp.s9_mon('{"P2P_MATCH_OVERRIDE":{"enabled":false,"min_count":1},"P2P_OVERRIDE_BY_CREATOR":{"enabled":true,"min_count":3}}'))),0,
  'A9: a disabled rule and a count below its minimum raise nothing');
select is((select array_agg(rule_code) from assurance.monitoring_rules('procurement.three_way_match',
  '{"bills_with_match_override":2,"overrides_by_bill_creator":3}'::jsonb,
  pg_temp.s9_mon('{"P2P_MATCH_OVERRIDE":{"enabled":false,"min_count":1},"P2P_OVERRIDE_BY_CREATOR":{"enabled":true,"min_count":3}}'))),
  array['P2P_OVERRIDE_BY_CREATOR'],'A9: a count at the minimum raises the rule');
select is((select count(*)::integer from assurance.monitoring_rules('it_control.access_review',
  '{"roles":[{"code":"a","requires_mfa":false,"privileged_permissions":["x"],"active_assignments":1},
   {"code":"b","requires_mfa":false,"privileged_permissions":["y"],"active_assignments":2}]}'::jsonb,
  pg_temp.s9_mon('{"ACCESS_PRIVILEGED_NO_MFA":{"enabled":true,"min_count":3}}'))),0,
  'A9: access review needs at least the minimum number of roles');
select ok((select prosrc from pg_proc where oid='api.assurance_evidence_command(uuid,uuid,uuid,uuid,jsonb,bigint)'::regprocedure)
  like '%assurance.monitoring_rules(v_snap.kind, v_snap.content, assurance.effective_settings(%',
  'A9: monitoring runs read the effective thresholds');

-- Plan revision.
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.s9_pc(jsonb_build_object('action','create_plan','plan_id',pg_temp.aid('p9'),'name','FY27 plan',
  'period_start','2027-01-01','period_end','2027-12-31'),0,'p9');
select pg_temp.s9_pc(jsonb_build_object('action','add_plan_item','plan_id',pg_temp.aid('p9'),'plan_item_id',pg_temp.aid('p9i'),
  'item_id',pg_temp.aid('u9a'),'frequency','semiannual','template_id',null,'lead_auditor_id',pg_temp.aid('lead'),
  'scope_summary','Settings coverage'),pg_temp.s9_v('p9'),'p9i');
select pg_temp.s9_pc(jsonb_build_object('action','submit_plan','plan_id',pg_temp.aid('p9')),pg_temp.s9_v('p9'),'p9s');
select pg_temp.s9_pc(jsonb_build_object('action','create_plan','plan_id',pg_temp.aid('p9d'),'name','Draft plan',
  'period_start','2027-01-01','period_end','2027-12-31'),0,'p9d');
select throws_ok($$select pg_temp.s9_pc(jsonb_build_object('action','supersede_plan','plan_id',pg_temp.aid('p9x'),
  'supersedes_plan_id',pg_temp.aid('p9d'),'name','Revision of a draft'),0,'p9x')$$,
  '55000','ASSURANCE_PLAN_NOT_APPROVED','A9: only approved plans can be revised');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.s9_pc(jsonb_build_object('action','decide_plan','plan_id',pg_temp.aid('p9'),'decision','approve',
  'reason','Coverage accepted'),pg_temp.s9_v('p9'),'p9a');
reset role;select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('p9r',pg_temp.s9_pc(jsonb_build_object('action','supersede_plan','plan_id',pg_temp.aid('p9r'),
  'supersedes_plan_id',pg_temp.aid('p9'),'name','FY27 plan (revised)'),0,'p9r'));
select throws_ok($$select pg_temp.s9_pc(jsonb_build_object('action','supersede_plan','plan_id',pg_temp.aid('p9r2'),
  'supersedes_plan_id',pg_temp.aid('p9'),'name','Second revision'),0,'p9r2')$$,
  '23505','ASSURANCE_PLAN_REVISION_OPEN','A9: one open revision per approved plan');
reset role;
select is((select body->>'to_status' from assurance_samples where label='p9r'),'draft','A9: a revision starts as a draft');
select ok((select p.supersedes_plan_id=pg_temp.aid('p9') and p.period_start='2027-01-01' and p.period_end='2027-12-31'
  and (select count(*) from assurance.plan_items i where i.plan_id=p.id and i.status='active')=1
  from assurance.plans p where p.id=pg_temp.aid('p9r')),'A9: a revision copies the period and active areas');
select is((select status from assurance.plans where id=pg_temp.aid('p9')),'approved','A9: the original stays approved until the revision is');
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.s9_pc(jsonb_build_object('action','submit_plan','plan_id',pg_temp.aid('p9r')),pg_temp.s9_v('p9r'),'p9rs');
reset role;
insert into assurance_samples values('p9.v',to_jsonb(pg_temp.s9_v('p9')));
select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.s9_pc(jsonb_build_object('action','decide_plan','plan_id',pg_temp.aid('p9r'),'decision','approve',
  'reason','Revision accepted'),pg_temp.s9_v('p9r'),'p9ra');
reset role;
select is((select status from assurance.plans where id=pg_temp.aid('p9')),'superseded','A9: approving the revision supersedes the original');
select is(pg_temp.s9_v('p9'),(select body::text::bigint+1 from assurance_samples where label='p9.v'),
  'A9: superseding advances the original version');
select ok(exists(select 1 from assurance.plan_events where aggregate_id=pg_temp.aid('p9') and to_status='superseded'
  and details->>'superseded_by'=pg_temp.aid('p9r')::text),'A9: the original records which plan superseded it');
select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.s9_pc(jsonb_build_object('action','instantiate_engagement','plan_id',pg_temp.aid('p9'),
  'plan_item_id',pg_temp.aid('p9i'),'occurrence',1,'engagement_id',pg_temp.aid('e9')),pg_temp.s9_v('p9'),'e9')$$,
  '55000','ASSURANCE_PLAN_NOT_APPROVED','A9: a superseded plan creates no engagements');
reset role;
select throws_ok($$update assurance.plans set name='Changed' where id=pg_temp.aid('p9r')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','A9: approved plans stay immutable');
select throws_ok($$update assurance.plans set status='draft' where id=pg_temp.aid('p9')$$,
  null,null,'A9: a superseded plan cannot change again');
