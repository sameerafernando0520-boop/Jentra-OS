-- A5 rollback suite: engagement register and reminder/escalation work queue.
-- Runs after the A1, A2, A4, A4b and A3 suites in the same transaction
-- (build_assurance_candidate.ps1 -Slice A5) and reuses their fixtures. Overdue
-- dates are produced by back-dating synthetic rows inside the transaction.
create function pg_temp.ov() returns jsonb language sql as $$
  select api.assurance_overview(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch')) $$;
create function pg_temp.reg7(p_after uuid default null) returns jsonb language sql as $$
  select api.assurance_engagements(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),p_after) $$;
create function pg_temp.q7(body jsonb, part text) returns text language sql as $$
  select string_agg((i->>'kind')||':'||(i->>'level'), ',' order by n)
  from jsonb_array_elements(body->part) with ordinality t(i,n) where i->>'engagement_id'=pg_temp.aid('eng7')::text $$;

reset role;
select ok((select count(*)=24 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='assurance' and c.relkind='r'),'A5 adds no tables');
select ok(has_function_privilege('authenticated','api.assurance_overview(uuid,uuid,uuid)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_overview(uuid,uuid,uuid)','EXECUTE')
  and has_function_privilege('authenticated','api.assurance_engagements(uuid,uuid,uuid,uuid)','EXECUTE')
  and not has_function_privilege('authenticated','assurance.work_items(uuid,uuid,uuid)','EXECUTE'),
  'A5: read models authenticated-only; work-item helper not client-callable');
select is(array(select assurance.reminder_level(current_date + d, current_date) from unnest(array[5,3,0,-1,-7,-8]) d)
  || assurance.reminder_level(null, current_date),
  array['on_track','due_soon','due_soon','overdue','overdue','escalated','on_track'],'reminder bands by days to or past due');

select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('create_engagement','eng7')||jsonb_build_object('name','FY27 Treasury','period_start','2026-04-01',
  'period_end','2027-03-31','scope_summary','Treasury and cash controls','lead_auditor_id',pg_temp.aid('lead')),0,'eng7');
select pg_temp.c2(pg_temp.e2('add_team_member','eng7')||jsonb_build_object('user_id',pg_temp.aid('auditor'),'role','auditor'),pg_temp.vv('eng7'),'eng7.aud');
select pg_temp.c2(pg_temp.e2('add_team_member','eng7')||jsonb_build_object('user_id',pg_temp.aid('reviewer'),'role','reviewer'),pg_temp.vv('eng7'),'eng7.rev');
select pg_temp.c2(pg_temp.e2('map_control','eng7')||jsonb_build_object('control_id',pg_temp.aid('ctl7'),'control_code','TRS-SIGN',
  'title','Dual signatories on payments','owner_id',pg_temp.aid('owner'),'risk','high'),pg_temp.vv('eng7'),'ctl7');
reset role;select pg_temp.actor('lead');set local role authenticated;
create function pg_temp.req7(k text) returns jsonb language sql as $$
  select pg_temp.c2(pg_temp.e2('request_evidence','eng7')||jsonb_build_object('request_id',pg_temp.aid('r7'||k),'control_id',pg_temp.aid('ctl7'),
    'owner_id',pg_temp.aid('owner'),'due_date',(current_date+2)::text,'description','Bank mandate evidence '||k),pg_temp.vv('eng7'),'r7'||k) $$;
select pg_temp.req7('a');
select pg_temp.req7('b');
select pg_temp.req7('c');
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('transition','eng7')||'{"to_status":"fieldwork","reason":"Plan approved"}',pg_temp.vv('eng7'),'eng7.fw');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.c2(pg_temp.e2('record_exception','eng7')||jsonb_build_object('exception_id',pg_temp.aid('x7'),'control_id',pg_temp.aid('ctl7'),
  'description','Single signatory release','severity','high'),pg_temp.vv('eng7'),'x7');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.c2(pg_temp.e2('issue_finding','eng7')||jsonb_build_object('finding_id',pg_temp.aid('f7'),'exception_id',pg_temp.aid('x7'),
  'title','Payments released by one signatory','severity','high','owner_id',pg_temp.aid('owner')),pg_temp.vv('eng7'),'f7');
reset role;
update assurance.evidence_requests set due_date=current_date-3 where id=pg_temp.aid('r7b');
update assurance.evidence_requests set due_date=current_date-10 where id=pg_temp.aid('r7c');
update assurance.findings set issued_at=now()-interval '20 days' where id=pg_temp.aid('f7');

select pg_temp.actor('owner');set local role authenticated;
insert into assurance_samples values('ov.owner',pg_temp.ov());
reset role;select pg_temp.actor('lead');set local role authenticated;
insert into assurance_samples values('ov.lead',pg_temp.ov());
reset role;select pg_temp.actor('reviewer');set local role authenticated;
insert into assurance_samples values('ov.reviewer',pg_temp.ov());
reset role;select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('reg.manager',pg_temp.reg7());
insert into assurance_samples values('reg.after',pg_temp.reg7((select max(id)::uuid from (select i->>'id' id
  from assurance_samples s, jsonb_array_elements(s.body->'items') i where s.label='reg.manager') x)));
reset role;

select is((select pg_temp.q7(body,'mine') from assurance_samples where label='ov.owner'),
  'evidence_request:escalated,finding:overdue,evidence_request:overdue,evidence_request:due_soon',
  'owner sees own open requests and findings ordered by due date with reminder levels');
select is((select (i->>'due_date')::date from assurance_samples s, jsonb_array_elements(s.body->'mine') i
  where s.label='ov.owner' and i->>'item_id'=pg_temp.aid('f7')::text),
  ((now()-interval '20 days') at time zone 'UTC')::date + 14,'an unanswered finding is due the response SLA after issue');
select ok((select body->'counts'='{"due_soon":1,"overdue":2,"escalated":1}'::jsonb and (body->>'response_sla_days')::integer=14
  from assurance_samples where label='ov.owner'),'owner counts cover due-soon, overdue and escalated work');
select ok((select not exists(select 1 from jsonb_array_elements(body->'mine') i where i->>'engagement_id'=pg_temp.aid('eng2')::text)
  from assurance_samples where label='ov.owner'),'archived engagements leave the work queue');
select is((select pg_temp.q7(body,'team') from assurance_samples where label='ov.lead'),
  'evidence_request:escalated,finding:overdue,evidence_request:overdue','the lead sees overdue and escalated team items only');
select ok((select pg_temp.q7(body,'mine') is null from assurance_samples where label='ov.lead'),'the lead owns none of the items');
select ok((select pg_temp.q7(body,'team') is null from assurance_samples where label='ov.reviewer'),'reviewers are not escalation targets');
select ok((select bool_and(i->>'level' in ('overdue','escalated')) from assurance_samples s, jsonb_array_elements(s.body->'team') i
  where s.label='ov.lead'),'team queue contains no on-track items');
select ok((select (i->>'open_requests')::integer=3 and (i->>'overdue_requests')::integer=2 and (i->>'open_findings')::integer=1
  and (i->>'overdue_findings')::integer=1 and (i->>'candidate_exceptions')::integer=0 and not (i->>'evidence_frozen')::boolean
  and i->>'status'='fieldwork'
  from assurance_samples s, jsonb_array_elements(s.body->'items') i where s.label='reg.manager' and i->>'id'=pg_temp.aid('eng7')::text),
  'the register summarises open and overdue work per engagement');
select ok((select jsonb_array_length(body->'items')=8 and body->'next_cursor'='null'::jsonb from assurance_samples where label='reg.manager'),
  'the register lists every engagement in scope');
select is((select jsonb_array_length(body->'items') from assurance_samples where label='reg.after'),0,'the register pages after a cursor');

select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select pg_temp.ov()$$,'42501',null,'external reviewers have no work queue');
select throws_ok($$select pg_temp.reg7()$$,'42501',null,'external reviewers cannot list engagements');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select pg_temp.reg7()$$,'42501',null,'another tenant cannot list engagements');
reset role;select pg_temp.actor('entityviewer');set local role authenticated;
select is((select jsonb_array_length(api.assurance_engagements(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),
  pg_temp.aid('tenant.branch2'),null)->'items')),0,'a branch register shows only that branch');

reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.c2(pg_temp.e2('respond','eng7')||jsonb_build_object('finding_id',pg_temp.aid('f7'),'response','Second signatory enforced in bank portal',
  'due_date',(current_date+30)::text,'accept_risk',false),pg_temp.vv('eng7'),'f7.resp');
insert into assurance_samples values('ov.owner.after',pg_temp.ov());
reset role;
select ok((select i->>'status'='remediating' and i->>'level'='on_track' and (i->>'due_date')::date=current_date+30
  from assurance_samples s, jsonb_array_elements(s.body->'mine') i where s.label='ov.owner.after' and i->>'item_id'=pg_temp.aid('f7')::text),
  'a response moves the finding to its remediation due date');
select is((select count(*)::integer from assurance.events where engagement_id=pg_temp.aid('eng7')),
  (select version::integer from assurance.engagements where id=pg_temp.aid('eng7')),'A5: reads add no events; one event per version');
