-- Corporate Audit & Assurance A10 reminder scan candidate tests.
-- Included only by build_assurance_candidate.ps1 -Slice A10, after the A10
-- candidate DDL. Self-contained on the A1 actors, tenant and roles; earlier
-- fragments may leave other due work in the same scope, so assertions look
-- only at this fragment's engagements.
create function pg_temp.s10_scan(k text, p_after uuid default null, p_branch text default 'tenant.branch') returns jsonb
language sql as $$
  select api.assurance_scan_reminders(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid(p_branch),
    pg_temp.aid('key10.'||k),jsonb_build_object('after_id',p_after)) $$;
create function pg_temp.s10_notices(p_engagement text) returns setof workflow.notifications
language sql security definer set search_path='' as $$
  select * from workflow.notifications where notification_type='assurance.reminder'
    and aggregate_id=pg_temp.aid(p_engagement) $$;

-- Fixtures: two engagements in fieldwork with requests at every level.
insert into assurance.engagements(id,tenant_id,legal_entity_id,branch_id,name,period_start,period_end,scope_summary,
  lead_auditor_id,status,created_by)
values(pg_temp.aid('e10'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'Reminder review',
  '2026-01-01','2026-12-31','Reminder coverage',pg_temp.aid('lead'),'fieldwork',pg_temp.aid('manager')),
      (pg_temp.aid('e10b'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'Self-led review',
  '2026-01-01','2026-12-31','Lead owns the work',pg_temp.aid('auditor'),'fieldwork',pg_temp.aid('manager'));
insert into assurance.engagement_controls(id,engagement_id,control_code,title,owner_id,risk,mapped_by)
values(pg_temp.aid('c10'),pg_temp.aid('e10'),'REM-1','Reminder control',pg_temp.aid('owner'),'high',pg_temp.aid('lead')),
      (pg_temp.aid('c10b'),pg_temp.aid('e10b'),'REM-2','Self-led control',pg_temp.aid('auditor'),'high',pg_temp.aid('auditor'));
insert into assurance.evidence_requests(id,engagement_id,control_id,owner_id,description,due_date,requested_by)
values(pg_temp.aid('r10a'),pg_temp.aid('e10'),pg_temp.aid('c10'),pg_temp.aid('owner'),'Confidential bank letter',current_date+1,pg_temp.aid('lead')),
      (pg_temp.aid('r10b'),pg_temp.aid('e10'),pg_temp.aid('c10'),pg_temp.aid('owner'),'Overdue evidence',current_date-2,pg_temp.aid('lead')),
      (pg_temp.aid('r10c'),pg_temp.aid('e10'),pg_temp.aid('c10'),pg_temp.aid('owner'),'Escalated evidence',current_date-10,pg_temp.aid('lead')),
      (pg_temp.aid('r10d'),pg_temp.aid('e10'),pg_temp.aid('c10'),pg_temp.aid('owner'),'Later evidence',current_date+20,pg_temp.aid('lead')),
      (pg_temp.aid('r10e'),pg_temp.aid('e10b'),pg_temp.aid('c10b'),pg_temp.aid('auditor'),'Lead-owned evidence',current_date-10,pg_temp.aid('auditor'));

select ok(has_function_privilege('authenticated','api.assurance_scan_reminders(uuid,uuid,uuid,uuid,jsonb)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_scan_reminders(uuid,uuid,uuid,uuid,jsonb)','EXECUTE'),
  'A10: the reminder scan is authenticated-only');

-- Authority.
select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.s10_scan('owner')$$,'42501',null,'A10: only engagement managers send reminders');
reset role;select pg_temp.actor('outsider');set local role authenticated;
select throws_ok($$select pg_temp.s10_scan('outsider')$$,'42501',null,'A10: non-members cannot send reminders');
reset role;

-- First scan, replay, second scan.
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('s10.1',pg_temp.s10_scan('one'));
insert into assurance_samples values('s10.1r',pg_temp.s10_scan('one'));
select throws_ok($$select api.assurance_scan_reminders(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
  pg_temp.aid('key10.one'),jsonb_build_object('after_id',pg_temp.aid('r10a')))$$,
  '22023','IDEMPOTENCY_MISMATCH','A10: a reused key with a changed body is refused');
select throws_ok($$select api.assurance_scan_reminders(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
  pg_temp.aid('key10.bad'),'{"after_id":null,"extra":1}')$$,'22023','ASSURANCE_UNEXPECTED_FIELD','A10: unexpected fields are refused');
insert into assurance_samples values('s10.2',pg_temp.s10_scan('two'));
reset role;
select is((select body from assurance_samples where label='s10.1r'),(select body from assurance_samples where label='s10.1'),
  'A10: the same key replays the scan receipt');
select is((select array_agg(r.email||':'||(n.source_context->>'level') order by r.email, n.source_context->>'level')
  from pg_temp.s10_notices('e10') n join auth.users r on r.id=n.recipient_id),
  array['lead@assurance.jentra.test:escalated','owner@assurance.jentra.test:due_soon',
    'owner@assurance.jentra.test:escalated','owner@assurance.jentra.test:overdue'],
  'A10: owners get due-soon, overdue and escalated notices; the lead also gets escalations');
select is((select count(*)::integer from pg_temp.s10_notices('e10b')),1,
  'A10: an owner who also leads the engagement gets one notice');
select is((select count(*)::integer from pg_temp.s10_notices('e10')
  where source_context->>'due_key' like pg_temp.aid('r10d')::text||':%'),0,'A10: work on track sends nothing');
select is((select (body->>'emitted')::integer from assurance_samples where label='s10.2'),0,
  'A10: a second scan sends no duplicates');
select is((select count(*)::integer from pg_temp.s10_notices('e10')),4,'A10: still four notices after scanning twice');
select ok((select bool_and(n.title in ('Evidence request due soon','Evidence request overdue','Evidence request escalated')
    and n.body not like '%Confidential%' and n.body like 'Reminder review:%'
    and n.aggregate_type='assurance_engagement' and n.legal_entity_id=pg_temp.aid('tenant.entity')
    and n.branch_id=pg_temp.aid('tenant.branch') and n.source_context->>'engagement_id'=pg_temp.aid('e10')::text
    and n.source_context->>'kind'='evidence_request')
  from pg_temp.s10_notices('e10') n),'A10: notices name the engagement and item kind, never the request text');

-- Paging: 101 due requests in the second branch make two pages.
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.aid('tenant'),pg_temp.aid('manager.m'),pg_temp.aid('manager.r'),pg_temp.aid('tenant.entity'),null,pg_temp.aid('manager'));
insert into assurance.engagements(id,tenant_id,legal_entity_id,branch_id,name,period_start,period_end,scope_summary,
  lead_auditor_id,status,created_by)
values(pg_temp.aid('e10p'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch2'),'Paging review',
  '2026-01-01','2026-12-31','Paging coverage',pg_temp.aid('lead'),'fieldwork',pg_temp.aid('manager'));
insert into assurance.engagement_controls(id,engagement_id,control_code,title,owner_id,risk,mapped_by)
values(pg_temp.aid('c10p'),pg_temp.aid('e10p'),'REM-P','Paging control',pg_temp.aid('owner'),'low',pg_temp.aid('lead'));
insert into assurance.evidence_requests(id,engagement_id,control_id,owner_id,description,due_date,requested_by)
select pg_temp.aid('r10p'||g),pg_temp.aid('e10p'),pg_temp.aid('c10p'),pg_temp.aid('owner'),'Paging evidence',current_date,pg_temp.aid('lead')
  from generate_series(1,101) g;
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('s10.p1',pg_temp.s10_scan('p1',null,'tenant.branch2'));
insert into assurance_samples values('s10.p2',pg_temp.s10_scan('p2',
  (select (body->>'next_after')::uuid from assurance_samples where label='s10.p1'),'tenant.branch2'));
reset role;
select ok((select (body->>'examined')::integer=100 and (body->>'has_more')::boolean and body->>'next_after' is not null
  from assurance_samples where label='s10.p1'),'A10: a scan examines at most 100 items and returns a cursor');
select ok((select not (body->>'has_more')::boolean and body->'next_after'='null'::jsonb from assurance_samples where label='s10.p2'),
  'A10: the last page has no cursor');
select is((select count(*)::integer from pg_temp.s10_notices('e10p')),101,'A10: paging reaches every due item once');
