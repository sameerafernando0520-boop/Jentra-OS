-- Corporate Audit & Assurance A11 process metrics candidate tests.
-- Included only by build_assurance_candidate.ps1 -Slice A11, after the A11
-- candidate DDL. Self-contained on the A1 actors, tenant and roles; fixture
-- rows and events are inserted directly with known timestamps.
create function pg_temp.m11(p_from date default '2026-01-01', p_to date default '2026-03-31') returns jsonb
language sql as $$
  select api.assurance_metrics(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),p_from,p_to) $$;
create function pg_temp.m11ev(p_eng text, p_ver integer, p_action text, p_type text, p_agg text, p_from text, p_to text,
  p_at timestamptz) returns void language sql as $$
  insert into assurance.events(tenant_id,engagement_id,engagement_version,action,aggregate_type,aggregate_id,
    from_status,to_status,actor_id,occurred_at)
  values(pg_temp.aid('tenant'),pg_temp.aid(p_eng),p_ver,p_action,p_type,pg_temp.aid(p_agg),p_from,p_to,pg_temp.aid('lead'),p_at) $$;

insert into assurance.engagements(id,tenant_id,legal_entity_id,branch_id,name,period_start,period_end,scope_summary,
  lead_auditor_id,status,created_by)
values(pg_temp.aid('m11'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'Metrics review',
  '2026-01-01','2026-03-31','Metrics coverage',pg_temp.aid('lead'),'issued',pg_temp.aid('manager')),
      (pg_temp.aid('m11b'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'Second review',
  '2026-02-01','2026-02-28','Still in fieldwork',pg_temp.aid('lead'),'fieldwork',pg_temp.aid('manager')),
      (pg_temp.aid('m11x'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'Last year review',
  '2025-01-01','2025-03-31','Outside the range',pg_temp.aid('lead'),'fieldwork',pg_temp.aid('manager'));
insert into assurance.engagement_controls(id,engagement_id,control_code,title,owner_id,risk,mapped_by)
values(pg_temp.aid('c11a'),pg_temp.aid('m11'),'MET-A','Metrics control A',pg_temp.aid('owner'),'high',pg_temp.aid('lead')),
      (pg_temp.aid('c11b'),pg_temp.aid('m11'),'MET-B','Metrics control B',pg_temp.aid('owner'),'low',pg_temp.aid('lead')),
      (pg_temp.aid('c11x'),pg_temp.aid('m11x'),'MET-X','Old control',pg_temp.aid('owner'),'high',pg_temp.aid('lead'));
-- Stages: m11 planning 4 d, fieldwork 10 d, reporting 2.5 d; m11b planning 2 d, still in fieldwork.
select pg_temp.m11ev('m11',1,'create_engagement','engagement','m11',null,'planning','2026-01-01T00:00:00Z');
select pg_temp.m11ev('m11',2,'transition','engagement','m11','planning','fieldwork','2026-01-05T00:00:00Z');
select pg_temp.m11ev('m11',3,'transition','engagement','m11','fieldwork','reporting','2026-01-15T00:00:00Z');
select pg_temp.m11ev('m11',4,'issue_report','report','m11rep','reporting','issued','2026-01-17T12:00:00Z');
select pg_temp.m11ev('m11b',1,'create_engagement','engagement','m11b',null,'planning','2026-02-01T00:00:00Z');
select pg_temp.m11ev('m11b',2,'transition','engagement','m11b','planning','fieldwork','2026-02-03T00:00:00Z');
-- Requests: A waits 2 d, reviewed 1 d, right first time; B waits 4 d, rejected, resubmitted, reviewed 2 d after the
-- latest submission; C and D still open (40 and 3 days old).
insert into assurance.evidence_requests(id,engagement_id,control_id,owner_id,description,due_date,status,rework_count,
  requested_by,requested_at)
values(pg_temp.aid('r11a'),pg_temp.aid('m11'),pg_temp.aid('c11a'),pg_temp.aid('owner'),'Request A','2026-01-20','accepted',0,
  pg_temp.aid('lead'),'2026-01-06T00:00:00Z'),
      (pg_temp.aid('r11b'),pg_temp.aid('m11'),pg_temp.aid('c11a'),pg_temp.aid('owner'),'Request B','2026-01-20','accepted',1,
  pg_temp.aid('lead'),'2026-01-06T00:00:00Z'),
      (pg_temp.aid('r11c'),pg_temp.aid('m11'),pg_temp.aid('c11b'),pg_temp.aid('owner'),'Request C','2026-01-20','open',0,
  pg_temp.aid('lead'),now()-interval '40 days'),
      (pg_temp.aid('r11d'),pg_temp.aid('m11'),pg_temp.aid('c11b'),pg_temp.aid('owner'),'Request D','2026-01-20','open',0,
  pg_temp.aid('lead'),now()-interval '3 days');
select pg_temp.m11ev('m11',5,'request_evidence','evidence_request','r11a',null,'open','2026-01-06T00:00:00Z');
select pg_temp.m11ev('m11',6,'submit_evidence','evidence_request','r11a','open','submitted','2026-01-08T00:00:00Z');
select pg_temp.m11ev('m11',7,'review_evidence','evidence_request','r11a','submitted','accepted','2026-01-09T00:00:00Z');
select pg_temp.m11ev('m11',8,'request_evidence','evidence_request','r11b',null,'open','2026-01-06T00:00:00Z');
select pg_temp.m11ev('m11',9,'submit_evidence','evidence_request','r11b','open','submitted','2026-01-10T00:00:00Z');
select pg_temp.m11ev('m11',10,'review_evidence','evidence_request','r11b','submitted','open','2026-01-11T00:00:00Z');
select pg_temp.m11ev('m11',11,'submit_evidence','evidence_request','r11b','open','submitted','2026-01-12T00:00:00Z');
select pg_temp.m11ev('m11',12,'review_evidence','evidence_request','r11b','submitted','accepted','2026-01-14T00:00:00Z');
-- Testing: one of two procedures reviewed, covering one of two controls.
insert into assurance.test_procedures(id,engagement_id,control_id,code,objective,control_risk,population_size,sample_size,
  sample_start,sample_positions,status,designed_by,reviewed_by,reviewed_at)
values(pg_temp.aid('p11a'),pg_temp.aid('m11'),pg_temp.aid('c11a'),'T-A','Approvals are evidenced','high',10,1,1,array[1],
  'reviewed',pg_temp.aid('auditor'),pg_temp.aid('reviewer'),now()),
      (pg_temp.aid('p11b'),pg_temp.aid('m11'),pg_temp.aid('c11b'),'T-B','Changes are approved','low',10,1,1,array[1],
  'designed',pg_temp.aid('auditor'),null,null);
-- Findings: high remediating and overdue (10 d old), low closed after a failed then passed retest and a reopen,
-- critical issued (6 d old); a critical finding outside the range is ignored.
insert into assurance.exceptions(id,engagement_id,control_id,description,severity,status,recorded_by)
select pg_temp.aid(x),pg_temp.aid(e),pg_temp.aid(c),'Metrics exception',s,'promoted',pg_temp.aid('auditor')
  from (values('x11a','m11','c11a','high'),('x11b','m11','c11a','low'),('x11c','m11','c11b','critical'),
              ('x11x','m11x','c11x','critical')) v(x,e,c,s);
insert into assurance.findings(id,engagement_id,exception_id,title,severity,owner_id,status,response_due,issued_by,issued_at)
values(pg_temp.aid('f11a'),pg_temp.aid('m11'),pg_temp.aid('x11a'),'High finding','high',pg_temp.aid('owner'),'remediating',
  current_date-1,pg_temp.aid('reviewer'),now()-interval '10 days'),
      (pg_temp.aid('f11b'),pg_temp.aid('m11'),pg_temp.aid('x11b'),'Low finding','low',pg_temp.aid('owner'),'closed',
  null,pg_temp.aid('reviewer'),now()-interval '20 days'),
      (pg_temp.aid('f11c'),pg_temp.aid('m11'),pg_temp.aid('x11c'),'Critical finding','critical',pg_temp.aid('auditor'),'issued',
  null,pg_temp.aid('reviewer'),now()-interval '6 days'),
      (pg_temp.aid('f11x'),pg_temp.aid('m11x'),pg_temp.aid('x11x'),'Old critical finding','critical',pg_temp.aid('owner'),'issued',
  null,pg_temp.aid('reviewer'),now()-interval '300 days');
insert into assurance.retests(id,finding_id,result,evidence_sha256,note,performed_by)
values(pg_temp.aid('t11a'),pg_temp.aid('f11b'),'fail',repeat('a',64),'Still failing',pg_temp.aid('reviewer')),
      (pg_temp.aid('t11b'),pg_temp.aid('f11b'),'pass',repeat('b',64),'Now passing',pg_temp.aid('reviewer'));
select pg_temp.m11ev('m11',13,'reopen_finding','finding','f11b','closed','remediating','2026-01-20T00:00:00Z');

select ok(has_function_privilege('authenticated','api.assurance_metrics(uuid,uuid,uuid,date,date)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_metrics(uuid,uuid,uuid,date,date)','EXECUTE')
  and not has_function_privilege('authenticated','assurance.metric_spread(numeric[])','EXECUTE'),
  'A11: metrics are authenticated-only and the helpers are not client-callable');

select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('m11',pg_temp.m11());
insert into assurance_samples values('m11.empty',pg_temp.m11('2024-01-01','2024-02-01'));
select throws_ok($$select pg_temp.m11('2026-03-31','2026-01-01')$$,'22023','ASSURANCE_RANGE_INVALID','A11: the range must be ordered');
select throws_ok($$select pg_temp.m11('2025-01-01','2026-03-31')$$,'22023','ASSURANCE_RANGE_INVALID','A11: the range is at most a year');
reset role;select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select pg_temp.m11()$$,'42501',null,'A11: metrics need evidence access');
reset role;select pg_temp.actor('outsider');set local role authenticated;
select throws_ok($$select pg_temp.m11()$$,'42501',null,'A11: non-members cannot read metrics');
reset role;

select is((select (body->>'engagements')::integer from assurance_samples where label='m11'),2,
  'A11: engagements overlapping the range are measured, others are not');
select is((select body->'metrics'->'stage_planning_days' from assurance_samples where label='m11'),
  '{"p50":2.00,"p90":4.00,"samples":2}'::jsonb,'A11: planning time is nearest-rank over both engagements');
select is((select body->'metrics'->'stage_fieldwork_days' from assurance_samples where label='m11'),
  '{"p50":10.00,"p90":10.00,"samples":1}'::jsonb,'A11: an engagement still in fieldwork is not measured yet');
select is((select body->'metrics'->'stage_reporting_days' from assurance_samples where label='m11'),
  '{"p50":2.50,"p90":2.50,"samples":1}'::jsonb,'A11: reporting ends when the report is issued');
select is((select body->'metrics'->'report_issuance_days' from assurance_samples where label='m11'),
  '{"p50":2.50,"p90":2.50,"samples":1}'::jsonb,'A11: report issuance runs from the end of fieldwork');
select is((select body->'metrics'->'evidence_waiting_days' from assurance_samples where label='m11'),
  '{"p50":2.00,"p90":4.00,"samples":2}'::jsonb,'A11: waiting runs from request to first submission');
select is((select body->'metrics'->'evidence_review_days' from assurance_samples where label='m11'),
  '{"p50":1.00,"p90":2.00,"samples":2}'::jsonb,'A11: review runs from the latest submission to acceptance');
select is((select body->'metrics'->'evidence_first_time_right' from assurance_samples where label='m11'),
  '{"value":0.5000,"samples":2}'::jsonb,'A11: reworked evidence is not first-time-right');
select is((select body->'metrics'->'request_ageing' from assurance_samples where label='m11'),
  '{"d0_7":1,"d8_30":0,"d31_plus":1,"samples":2}'::jsonb,'A11: open requests are aged into buckets');
select is((select body->'metrics'->'test_completion' from assurance_samples where label='m11'),
  '{"value":0.5000,"samples":2}'::jsonb,'A11: test completion counts reviewed procedures');
select is((select body->'metrics'->'control_coverage' from assurance_samples where label='m11'),
  '{"value":0.5000,"samples":2}'::jsonb,'A11: coverage counts controls with a reviewed test');
select is((select body->'metrics'->'retest_pass_rate' from assurance_samples where label='m11'),
  '{"value":0.5000,"samples":2}'::jsonb,'A11: failed retests are kept in the pass rate');
select is((select body->'metrics'->'recurrence' from assurance_samples where label='m11'),
  '{"value":0.3333,"samples":3}'::jsonb,'A11: recurrence counts reopenings over findings');
select is((select body->'metrics'->'finding_ageing_days' from assurance_samples where label='m11'),
  '{"low":{"value":null,"samples":0},"medium":{"value":null,"samples":0},"high":{"value":10.00,"samples":1},"critical":{"value":6.00,"samples":1}}'::jsonb,
  'A11: open findings are aged by severity; none is not measured');
select is((select (body->'metrics'->'overdue_remediation'->>'value')::integer from assurance_samples where label='m11'),1,
  'A11: remediation past its due date is overdue');
select is((select (body->'metrics'->'open_high_risk_findings'->>'value')::integer from assurance_samples where label='m11'),2,
  'A11: open high and critical findings are counted, outside the range excluded');
select ok((select jsonb_array_length(body->'metrics'->'workload')=2
    and (body->'metrics'->'workload'->0->>'open_requests')::integer=2
    and (body->'metrics'->'workload'->0->>'open_findings')::integer=1
    and (body->'metrics'->'workload'->1->>'open_findings')::integer=1
    and not exists(select 1 from jsonb_array_elements(body->'metrics'->'workload') w where w->>'label' like '%@%')
  from assurance_samples where label='m11'),'A11: workload ranks people by open work, never by e-mail');
select is((select body->'metrics'->'stage_planning_days' from assurance_samples where label='m11.empty'),
  '{"p50":null,"p90":null,"samples":0}'::jsonb,'A11: with no engagements durations are not measured');
select is((select body->'metrics'->'evidence_first_time_right' from assurance_samples where label='m11.empty'),
  '{"value":null,"samples":0}'::jsonb,'A11: with no samples a rate is not measured, never zero');
