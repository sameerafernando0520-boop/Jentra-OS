-- A3 rollback suite: audit universe, risk assessment, maker-checker plans,
-- templates and recurring engagements. Runs after the A1, A2, A4 and A4b suites
-- in the same transaction (build_assurance_candidate.ps1 -Slice A3) and reuses
-- their synthetic tenant, actors and helpers. Everything rolls back.
create function pg_temp.pc(p jsonb,v bigint,k text) returns jsonb language sql as $$
  select api.assurance_plan_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
    pg_temp.aid('key6.'||k),p,v) $$;
create function pg_temp.pv(k text) returns bigint language sql security definer set search_path='' as $$
  select coalesce((select version from assurance.plans where id=pg_temp.aid(k)),
    (select version from assurance.universe_items where id=pg_temp.aid(k)),0) $$;
create function pg_temp.reg(k text,code text,name text,owner text) returns jsonb language sql as $$
  select pg_temp.pc(jsonb_build_object('action','register_item','item_id',pg_temp.aid(k),'code',code,'name',name,
    'category','process','owner_id',pg_temp.aid(owner)),0,k) $$;
create function pg_temp.assess(k text,a text,l integer,i integer) returns jsonb language sql as $$
  select pg_temp.pc(jsonb_build_object('action','assess_risk','item_id',pg_temp.aid(k),'assessment_id',pg_temp.aid(a),
    'likelihood',l,'impact',i,'rationale','Annual risk workshop'),pg_temp.pv(k),a) $$;
create function pg_temp.tpl(k text,controls jsonb,requests jsonb) returns jsonb language sql as $$
  select pg_temp.pc(jsonb_build_object('action','create_template','template_id',pg_temp.aid(k),'code','P2P-STD',
    'name','Procure to pay standard','controls',controls,'requests',requests),0,k) $$;
create function pg_temp.pl(a text) returns jsonb language sql as $$
  select jsonb_build_object('action',a,'plan_id',pg_temp.aid('plan6')) $$;
create function pg_temp.additem(pi text,item text,freq text,tpl text,lead text) returns jsonb language sql as $$
  select pg_temp.pc(pg_temp.pl('add_plan_item')||jsonb_build_object('plan_item_id',pg_temp.aid(pi),'item_id',pg_temp.aid(item),
    'frequency',freq,'template_id',case when tpl is null then null else pg_temp.aid(tpl) end,'lead_auditor_id',pg_temp.aid(lead),
    'scope_summary','Design and operating effectiveness'),pg_temp.pv('plan6'),pi) $$;
create function pg_temp.inst(pi text,occ integer,eng text,k text) returns jsonb language sql as $$
  select pg_temp.pc(pg_temp.pl('instantiate_engagement')||jsonb_build_object('plan_item_id',pg_temp.aid(pi),'occurrence',occ,
    'engagement_id',pg_temp.aid(eng)),pg_temp.pv('plan6'),k) $$;

reset role;
select pg_temp.grant_perm('manager','assurance.plan.manage');
select pg_temp.grant_perm('reviewer','assurance.plan.manage');
select ok((select count(*)=24 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class c
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='assurance' and c.relkind='r'),'A3: all 24 assurance tables force RLS');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='assurance' and c.relkind='r' and (has_table_privilege('authenticated',c.oid,'SELECT')
  or has_table_privilege('service_role',c.oid,'SELECT')))
  and has_function_privilege('authenticated','api.assurance_plan_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_plan_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE')
  and not has_function_privilege('authenticated','assurance.plan_digest(uuid)','EXECUTE'),
  'A3: planning is API-only and authenticated-only; helpers are not client-callable');
select is(array(select assurance.risk_rating(s) from unnest(array[4,5,9,10,16,20,25]) s),
  array['low','medium','medium','high','high','critical','critical'],'risk rating bands over likelihood x impact');
select is((select array[o_start,o_end] from assurance.occurrence_period('2026-04-01','2027-03-31',4,2)),
  array['2026-07-01'::date,'2026-09-29'::date],'occurrences split the plan period deterministically');

-- Universe
select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','register_item','item_id',pg_temp.aid('u.bad'),'code','BAD',
  'name','Bad item','category','department','owner_id',pg_temp.aid('owner')),0,'u.bad')$$,
  '22023','ASSURANCE_FIELD_INVALID','universe category is an allow-list');
select throws_ok($$select pg_temp.reg('u.out','OUT','Outsider owned','outsider')$$,
  '22023','ASSURANCE_MEMBER_REQUIRED','area owner must be an active member');
insert into assurance_samples values('u.p2p',pg_temp.reg('u.p2p','P2P','Procure to pay','owner'));
select is(pg_temp.reg('u.p2p','P2P','Procure to pay','owner'),(select body from assurance_samples where label='u.p2p'),
  'universe registration replays its receipt');
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','register_item','item_id',pg_temp.aid('u.p2p'),'code','P2P2',
  'name','Again','category','process','owner_id',pg_temp.aid('owner')),0,'u.dup')$$,
  '23505','ASSURANCE_ITEM_EXISTS','universe item ids are unique');
select pg_temp.reg('u.pay','PAY','Payroll','owner');
select pg_temp.reg('u.it','ITGC','IT general controls','reviewer');
select pg_temp.reg('u.new','NEWPROC','New process','owner');

-- Risk assessment
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.assess('u.p2p','a.own',4,4)$$,'42501',null,'area owner without planning capability cannot assess');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.assess('u.it','a.it.self',5,4)$$,
  '42501','ASSURANCE_INDEPENDENCE_REQUIRED','an area owner cannot assess its own risk');
reset role;select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.assess('u.p2p','a.bad',6,4)$$,'22023','ASSURANCE_FIELD_INVALID','likelihood and impact are 1 to 5');
select pg_temp.assess('u.p2p','a.p2p1',4,4);
select pg_temp.assess('u.p2p','a.p2p2',5,4);
select pg_temp.assess('u.pay','a.pay',2,2);
select pg_temp.assess('u.it','a.it',5,5);
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','assess_risk','item_id',pg_temp.aid('u.pay'),
  'assessment_id',pg_temp.aid('a.stale'),'likelihood',3,'impact',3,'rationale','Stale'),1,'a.stale')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','stale universe version rejected');
reset role;
select is((select a.rating||':'||a.score from assurance.universe_items u join assurance.risk_assessments a
  on a.id=u.current_assessment_id where u.id=pg_temp.aid('u.p2p')),'critical:20','current assessment is the latest; score = likelihood x impact');
select is((select count(*)::integer from assurance.risk_assessments where universe_item_id=pg_temp.aid('u.p2p')),2,
  'earlier assessments are retained');
select throws_ok($$update assurance.risk_assessments set likelihood=1 where id=pg_temp.aid('a.p2p1')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','risk assessments immutable');

-- Templates
select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.tpl('tpl.bad1','[{"control_code":"P2P-3WM","title":"Three-way match","risk":"high"}]',
  '[{"control_code":"P2P-XX","description":"Unknown control","due_offset_days":14}]')$$,
  '22023','ASSURANCE_TEMPLATE_INVALID','template requests must reference template controls');
select throws_ok($$select pg_temp.tpl('tpl.bad2','[{"control_code":"P2P-3WM","title":"Three-way match","risk":"high","owner_id":"x"}]','[]')$$,
  '22023','ASSURANCE_TEMPLATE_INVALID','template entries are exact allow-lists');
select pg_temp.tpl('tpl1','[{"control_code":"P2P-3WM","title":"Three-way match","risk":"high"},{"control_code":"P2P-VEND","title":"Vendor master changes","risk":"medium"}]',
  '[{"control_code":"P2P-3WM","description":"Match exception report","due_offset_days":14},{"control_code":"P2P-VEND","description":"Vendor master change log","due_offset_days":21}]');
select pg_temp.tpl('tpl2','[{"control_code":"P2P-3WM","title":"Three-way match","risk":"critical"}]','[]');
reset role;
select is((select array_agg(version order by version) from assurance.templates where id in (pg_temp.aid('tpl1'),pg_temp.aid('tpl2'))),
  array[1,2],'a template code is versioned, not overwritten');
select throws_ok($$update assurance.templates set name='Renamed' where id=pg_temp.aid('tpl1')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','templates immutable');

-- Plan: maker
select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.pc(pg_temp.pl('create_plan')||'{"name":"FY27 plan","period_start":"2027-03-31","period_end":"2026-04-01"}',0,'plan.bad')$$,
  '22023','ASSURANCE_PERIOD_INVALID','plan period must be ordered');
select pg_temp.pc(pg_temp.pl('create_plan')||'{"name":"FY27 internal audit plan","period_start":"2026-04-01","period_end":"2027-03-31"}',0,'plan6');
select throws_ok($$select pg_temp.additem('pi.new','u.new','once',null,'lead')$$,
  '55000','ASSURANCE_RISK_ASSESSMENT_REQUIRED','only risk-assessed areas can be planned');
select throws_ok($$select pg_temp.additem('pi.own','u.p2p','quarterly','tpl1','owner')$$,
  '42501','ASSURANCE_INDEPENDENCE_REQUIRED','an area owner cannot lead its audit');
select throws_ok($$select pg_temp.additem('pi.freq','u.p2p','weekly','tpl1','lead')$$,
  '22023','ASSURANCE_FIELD_INVALID','frequency is an allow-list');
select pg_temp.additem('pi.p2p','u.p2p','quarterly','tpl1','lead');
select throws_ok($$select pg_temp.additem('pi.p2p.b','u.p2p','once',null,'lead')$$,
  '23505','ASSURANCE_PLAN_ITEM_EXISTS','an area is planned once per plan');
select pg_temp.additem('pi.pay','u.pay','once',null,'lead');
select pg_temp.pc(pg_temp.pl('remove_plan_item')||jsonb_build_object('plan_item_id',pg_temp.aid('pi.pay'),
  'reason','Covered by the external auditor'),pg_temp.pv('plan6'),'pi.pay.rm');
select throws_ok($$select pg_temp.inst('pi.p2p',1,'eng6.early','inst.early')$$,
  '55000','ASSURANCE_PLAN_NOT_APPROVED','engagements come only from approved plans');
select throws_ok($$select pg_temp.pc(jsonb_build_object('action','retire_item','item_id',pg_temp.aid('u.p2p'),'reason','Process merged'),
  pg_temp.pv('u.p2p'),'u.p2p.ret')$$,'55000','ASSURANCE_ITEM_IN_OPEN_PLAN','an area in an open plan cannot be retired');
select pg_temp.pc(pg_temp.pl('submit_plan'),pg_temp.pv('plan6'),'submit1');
select throws_ok($$select pg_temp.additem('pi.it','u.it','once',null,'lead')$$,
  '55000','ASSURANCE_TRANSITION_INVALID','a submitted plan is locked');
select throws_ok($$select pg_temp.pc(pg_temp.pl('decide_plan')||'{"decision":"approve","reason":"Self approval"}',pg_temp.pv('plan6'),'dec.self')$$,
  '42501','ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED','the maker cannot approve their own plan');

-- Plan: checker
reset role;select pg_temp.actor('reviewer',false);set local role authenticated;
select throws_ok($$select pg_temp.pc(pg_temp.pl('decide_plan')||'{"decision":"approve","reason":"Approved"}',pg_temp.pv('plan6'),'dec.nomfa')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','plan approval requires recent MFA');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.pc(pg_temp.pl('decide_plan')||'{"decision":"return","reason":"Add IT general controls rationale"}',pg_temp.pv('plan6'),'dec.return');
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.pc(pg_temp.pl('submit_plan'),pg_temp.pv('plan6'),'submit2');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
insert into assurance_samples values('plan.read.pre',api.assurance_plan(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),
  pg_temp.aid('tenant.branch'),pg_temp.aid('plan6')));
select pg_temp.pc(pg_temp.pl('decide_plan')||'{"decision":"approve","reason":"Coverage accepted for FY27"}',pg_temp.pv('plan6'),'dec.approve');
reset role;
select ok((select jsonb_array_length(body->'uncovered_high_risk')=1 and body->'uncovered_high_risk'->0->>'code'='ITGC'
  from assurance_samples where label='plan.read.pre'),'uncovered high-risk areas are shown to the approver');
select ok((select status='approved' and approved_by=pg_temp.aid('reviewer') and approved_digest=assurance.plan_digest(id)
  from assurance.plans where id=pg_temp.aid('plan6')),'approval records the approver and a digest over the approved items');
select throws_ok($$update assurance.plans set approved_digest=repeat('0',64) where id=pg_temp.aid('plan6')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','an approved plan digest is fixed');
select throws_ok($$update assurance.plan_items set frequency='once' where id=pg_temp.aid('pi.p2p')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','plan items cannot be rewritten');
select is((select status from assurance.plan_items where id=pg_temp.aid('pi.pay')),'removed','removed plan items are retained');

-- Recurring engagements from the approved plan
select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.inst('pi.p2p',2,'eng6.q2','inst.rev')$$,'42501',null,'instantiation needs engagement authority');
reset role;select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.inst('pi.p2p',5,'eng6.q5','inst.q5')$$,
  '22023','ASSURANCE_FIELD_INVALID','occurrence is bounded by the planned frequency');
insert into assurance_samples values('inst.q2',pg_temp.inst('pi.p2p',2,'eng6.q2','inst.q2'));
select is(pg_temp.pc(pg_temp.pl('instantiate_engagement')||jsonb_build_object('plan_item_id',pg_temp.aid('pi.p2p'),'occurrence',2,
  'engagement_id',pg_temp.aid('eng6.q2')),pg_temp.pv('plan6')-1,'inst.q2'),(select body from assurance_samples where label='inst.q2'),
  'instantiation replays its receipt');
select throws_ok($$select pg_temp.inst('pi.p2p',2,'eng6.q2b','inst.q2b')$$,
  '23505','ASSURANCE_OCCURRENCE_EXISTS','each occurrence is instantiated once');
select pg_temp.inst('pi.p2p',3,'eng6.q3','inst.q3');
reset role;
select ok((select period_start='2026-07-01' and period_end='2026-09-29' and status='planning' and version=1
  and lead_auditor_id=pg_temp.aid('lead') and name='Procure to pay 2/4'
  from assurance.engagements where id=pg_temp.aid('eng6.q2')),'engagement takes the occurrence period, planned lead and planning state');
select is((select string_agg(c.control_code||':'||c.risk||':'||(c.owner_id=pg_temp.aid('owner'))::text,',' order by c.control_code)
  from assurance.engagement_controls c where engagement_id=pg_temp.aid('eng6.q2')),
  'P2P-3WM:high:true,P2P-VEND:medium:true','template controls are mapped to the area owner');
select ok((select count(*)=2 and bool_and(status='open' and owner_id=pg_temp.aid('owner') and requested_by=pg_temp.aid('manager'))
  and min(due_date)=current_date+14 and max(due_date)=current_date+21
  from assurance.evidence_requests where engagement_id=pg_temp.aid('eng6.q2')),'template PBC requests go to the area owner with their due offsets');
select ok((select count(*)=1 and bool_and(engagement_version=1 and action='create_engagement'
  and details->>'plan_item_id'=pg_temp.aid('pi.p2p')::text and actor_id=pg_temp.aid('manager'))
  from assurance.events where engagement_id=pg_temp.aid('eng6.q2')),'an instantiated engagement starts with one attributable creation event');
select ok((select role='lead' from assurance.engagement_team where engagement_id=pg_temp.aid('eng6.q2')
  and user_id=pg_temp.aid('lead')),'the planned lead joins the team');
select throws_ok($$delete from assurance.plan_occurrences where engagement_id=pg_temp.aid('eng6.q2')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','occurrence links immutable');

-- The instantiated engagement continues under A1 rules
select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.c2(pg_temp.e2('add_team_member','eng6.q2')||jsonb_build_object('user_id',pg_temp.aid('owner'),'role','auditor'),
  pg_temp.vv('eng6.q2'),'eng6.owner')$$,'42501','ASSURANCE_INDEPENDENCE_REQUIRED','instantiated engagements keep A1 independence rules');
select pg_temp.c2(pg_temp.e2('add_team_member','eng6.q2')||jsonb_build_object('user_id',pg_temp.aid('auditor'),'role','auditor'),
  pg_temp.vv('eng6.q2'),'eng6.aud');
reset role;
select is((select version::integer from assurance.engagements where id=pg_temp.aid('eng6.q2')),2,'A1 commands continue the engagement version');

-- Retirement and closed plans
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.pc(jsonb_build_object('action','retire_item','item_id',pg_temp.aid('u.p2p'),'reason','Process outsourced'),
  pg_temp.pv('u.p2p'),'u.p2p.ret2');
select throws_ok($$select pg_temp.inst('pi.p2p',4,'eng6.q4','inst.q4')$$,'55000','ASSURANCE_ITEM_RETIRED','retired areas are not instantiated');
select throws_ok($$select pg_temp.pc(pg_temp.pl('cancel_plan')||'{"reason":"Too late"}',pg_temp.pv('plan6'),'cancel')$$,
  '55000','ASSURANCE_TRANSITION_INVALID','approved plans are not cancelled');

-- Reads and isolation
reset role;select pg_temp.actor('owner');set local role authenticated;
insert into assurance_samples values('universe.owner',api.assurance_universe(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch')));
reset role;
select ok((select jsonb_array_length(body->'items')=4 and jsonb_array_length(body->'templates')=2
  and (select x->'assessment'->>'rating' from jsonb_array_elements(body->'items') x where x->>'code'='ITGC')='critical'
  and (select x->>'status' from jsonb_array_elements(body->'items') x where x->>'code'='P2P')='retired'
  from assurance_samples where label='universe.owner'),'evidence viewers read the universe with current ratings and templates');
select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select api.assurance_universe(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'))$$,
  '42501',null,'external reviewers cannot read the universe');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select api.assurance_plan(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('plan6'))$$,
  '42501',null,'another tenant cannot read the plan');
reset role;select pg_temp.actor('entityviewer');set local role authenticated;
select throws_ok($$select api.assurance_plan(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch2'),pg_temp.aid('plan6'))$$,
  'P0002','ASSURANCE_PLAN_NOT_FOUND','an entity-wide viewer cannot reach a branch plan through another branch');
reset role;
select is((select count(*)::integer from assurance.plan_events where aggregate_type='plan' and aggregate_id=pg_temp.aid('plan6')),
  (select version::integer from assurance.plans where id=pg_temp.aid('plan6')),'one plan event per plan version');
select is((select count(*)::integer from assurance.plan_events where aggregate_type='universe_item' and aggregate_id=pg_temp.aid('u.p2p')),
  (select version::integer from assurance.universe_items where id=pg_temp.aid('u.p2p')),'one universe event per item version');
select throws_ok($$delete from assurance.plan_events$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','planning history immutable');
