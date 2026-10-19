-- Corporate Audit & Assurance A2 candidate tests (blueprint 68).
-- Included only by build_assurance_candidate.ps1 -Slice A2, after the A1 tests and the A2
-- candidate DDL, inside the same begin ... rollback block. Reuses A1 fixtures.
create function pg_temp.e2(a text,eng text) returns jsonb language sql as $$
  select jsonb_build_object('action',a,'engagement_id',pg_temp.aid(eng)) $$;
create function pg_temp.vv(eng text) returns bigint language sql security definer set search_path='' as $$
  select version from assurance.engagements where id=pg_temp.aid(eng) $$;
create function pg_temp.tc(p jsonb,v bigint,k text) returns jsonb language sql as $$
  select api.assurance_test_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
    pg_temp.aid('key2.'||k),p,v) $$;
create function pg_temp.c2(p jsonb,v bigint,k text) returns jsonb language sql as $$
  select api.assurance_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
    pg_temp.aid('key2.'||k),p,v) $$;
create function pg_temp.design(k text,pop integer,start integer) returns jsonb language sql as $$
  select pg_temp.e2('design_test','eng2')||jsonb_build_object('procedure_id',pg_temp.aid(k),'control_id',pg_temp.aid('ctl2'),
    'code',upper(replace(k,'.','-')),'objective','Each sampled payment has a matched receipt','population_size',pop,'sample_start',start) $$;
create function pg_temp.run(k text,proc text,items integer,found integer,concl text) returns jsonb language sql as $$
  select pg_temp.e2('execute_test','eng2')||jsonb_build_object('run_id',pg_temp.aid(k),'procedure_id',pg_temp.aid(proc),
    'items_tested',items,'exceptions_found',found,'conclusion',concl,'workpaper_sha256',pg_temp.hex(k)) $$;

reset role;
-- A1's revocation test removed this grant; restore it for A2.
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.aid('tenant'),pg_temp.aid('reviewer.r'),'assurance.engagement.close');
select ok((select count(*)=14 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class c
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='assurance' and c.relkind='r'),'A2: all 14 assurance tables force RLS');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='assurance' and c.relkind='r' and (has_table_privilege('authenticated',c.oid,'SELECT')
  or has_table_privilege('service_role',c.oid,'SELECT'))),'A2: no direct table grants');
select ok(has_function_privilege('authenticated','api.assurance_test_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_test_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE')
  and not has_function_privilege('authenticated','assurance.prepare_command(uuid,uuid,uuid,uuid,jsonb,bigint,text,text[],boolean)','EXECUTE'),
  'A2: test command authenticated-only; shared helpers are not client-callable');
select is(assurance.systematic_sample(100,25,7),
  array(select ((7-1+(i*100/25))%100)+1 from generate_series(0,24) i),'systematic sample matches the domain formula');
select is(assurance.sample_size(12,'high'),12,'sample capped at population');

-- Engagement 2: team revocation and request cancellation.
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('create_engagement','eng2')||jsonb_build_object('name','FY26 Payments','period_start','2026-04-01',
  'period_end','2027-03-31','scope_summary','Supplier payment controls','lead_auditor_id',pg_temp.aid('lead')),0,'create');
select pg_temp.c2(pg_temp.e2('add_team_member','eng2')||jsonb_build_object('user_id',pg_temp.aid('auditor'),'role','auditor'),pg_temp.vv('eng2'),'auditor');
select pg_temp.c2(pg_temp.e2('add_team_member','eng2')||jsonb_build_object('user_id',pg_temp.aid('reviewer'),'role','reviewer'),pg_temp.vv('eng2'),'reviewer');
select pg_temp.c2(pg_temp.e2('add_team_member','eng2')||jsonb_build_object('user_id',pg_temp.aid('entityviewer'),'role','auditor'),pg_temp.vv('eng2'),'ev');
select throws_ok($$select pg_temp.c2(pg_temp.e2('revoke_team_member','eng2')||jsonb_build_object('user_id',pg_temp.aid('lead'),'reason','Rotation'),pg_temp.vv('eng2'),'rev.lead')$$,
  '55000','ASSURANCE_LEAD_REQUIRED','lead auditor cannot be revoked');
select pg_temp.c2(pg_temp.e2('revoke_team_member','eng2')||jsonb_build_object('user_id',pg_temp.aid('entityviewer'),'reason','Reassigned'),pg_temp.vv('eng2'),'rev.ev');
reset role;
select ok((select revoked_at is not null and revoked_by=pg_temp.aid('manager') from assurance.engagement_team
  where engagement_id=pg_temp.aid('eng2') and user_id=pg_temp.aid('entityviewer')),'revoked membership is retained, not deleted');
select is(assurance.team_role(pg_temp.aid('eng2'),pg_temp.aid('entityviewer')),null,'revoked member has no active team role');
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('map_control','eng2')||jsonb_build_object('control_id',pg_temp.aid('ctl2'),'control_code','PAY-APPROVAL',
  'title','Payment approval before release','owner_id',pg_temp.aid('owner'),'risk','high'),pg_temp.vv('eng2'),'ctl2');
reset role;select pg_temp.actor('lead');set local role authenticated;
select pg_temp.c2(pg_temp.e2('request_evidence','eng2')||jsonb_build_object('request_id',pg_temp.aid('req2a'),'control_id',pg_temp.aid('ctl2'),
  'owner_id',pg_temp.aid('owner'),'due_date',(current_date+5)::text,'description','Payment run approvals Q1'),pg_temp.vv('eng2'),'req2a');
select pg_temp.c2(pg_temp.e2('request_evidence','eng2')||jsonb_build_object('request_id',pg_temp.aid('req2b'),'control_id',pg_temp.aid('ctl2'),
  'owner_id',pg_temp.aid('owner'),'due_date',(current_date+5)::text,'description','Duplicate request'),pg_temp.vv('eng2'),'req2b');
select pg_temp.c2(pg_temp.e2('cancel_request','eng2')||jsonb_build_object('request_id',pg_temp.aid('req2b'),'reason','Duplicate of req2a'),pg_temp.vv('eng2'),'cancel');
reset role;
select is((select status from assurance.evidence_requests where id=pg_temp.aid('req2b')),'cancelled','cancelled request retained with status');

-- Test design: server computes the sample from control risk.
select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.design('tp.owner',1000,7),pg_temp.vv('eng2'),'tp.owner')$$,
  '42501',null,'control owner cannot design tests');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.design('tp.bad',1000,1001),pg_temp.vv('eng2'),'tp.badstart')$$,
  '22023','ASSURANCE_FIELD_INVALID','sample start must lie inside the population');
select throws_ok($$select pg_temp.tc(pg_temp.design('tp.bad',1000,7)||'{"sample_size":5}',pg_temp.vv('eng2'),'tp.size')$$,
  '22023','ASSURANCE_UNEXPECTED_FIELD','client cannot choose the sample size');
select pg_temp.tc(pg_temp.design('tp1',1000,7),pg_temp.vv('eng2'),'tp1');
reset role;
select is((select sample_size from assurance.test_procedures where id=pg_temp.aid('tp1')),40,'high-risk control samples 40');
select is((select sample_positions[1:3] from assurance.test_procedures where id=pg_temp.aid('tp1')),array[7,32,57],'recorded start reproduces positions');
select throws_ok($$update assurance.test_procedures set sample_size=10 where id=pg_temp.aid('tp1')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','designed sample cannot be rewritten');
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.run('run0','tp1',40,0,'effective'),pg_temp.vv('eng2'),'run0')$$,
  '55000','ASSURANCE_TRANSITION_INVALID','tests execute only in fieldwork');

-- Fieldwork, evidence and freeze.
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('transition','eng2')||'{"to_status":"fieldwork","reason":"Plan approved"}',pg_temp.vv('eng2'),'fieldwork');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.run('run0','tp1',40,0,'effective'),pg_temp.vv('eng2'),'run0.frz')$$,
  '55000','ASSURANCE_EVIDENCE_FREEZE_REQUIRED','tests execute only on frozen evidence');
reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.c2(pg_temp.e2('submit_evidence','eng2')||jsonb_build_object('request_id',pg_temp.aid('req2a'),'evidence_id',pg_temp.aid('ev2a'),
  'source_module','finance','source_reference','payment_run_approvals.v1','source_as_of',now()::text,'collection_method','system',
  'query_version','fin.pay.1','sha256',pg_temp.hex('ev2a'),'byte_size',8192,
  'storage_ref','assurance/'||pg_temp.aid('tenant')||'/'||pg_temp.aid('eng2')||'/'||pg_temp.aid('ev2a'),'classification','confidential'),pg_temp.vv('eng2'),'ev2a');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.c2(pg_temp.e2('review_evidence','eng2')||jsonb_build_object('request_id',pg_temp.aid('req2a'),'decision','accept','reason','Complete'),pg_temp.vv('eng2'),'acc2a');
reset role;select pg_temp.actor('lead');set local role authenticated;
select pg_temp.c2(pg_temp.e2('freeze_evidence','eng2')||'{"reason":"Fieldwork cutoff"}',pg_temp.vv('eng2'),'freeze');
reset role;
select ok((select evidence_frozen_at is not null from assurance.engagements where id=pg_temp.aid('eng2')),'cancelled request does not block freeze');

-- Execution and independent review.
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.run('run0','tp1',39,0,'effective'),pg_temp.vv('eng2'),'run0.short')$$,
  '22023','ASSURANCE_SAMPLE_INCOMPLETE','every sampled item must be tested');
select throws_ok($$select pg_temp.tc(pg_temp.run('run0','tp1',40,2,'effective'),pg_temp.vv('eng2'),'run0.concl')$$,
  '22023','ASSURANCE_CONCLUSION_INCONSISTENT','exceptions cannot support an effective conclusion');
select pg_temp.tc(pg_temp.run('run1','tp1',40,2,'ineffective'),pg_temp.vv('eng2'),'run1');
select throws_ok($$select pg_temp.tc(pg_temp.e2('review_test','eng2')||jsonb_build_object('procedure_id',pg_temp.aid('tp1'),
  'decision','accept','reason','Self review'),pg_temp.vv('eng2'),'rv.self')$$,'42501',null,'performer cannot review own test');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.tc(pg_temp.e2('review_test','eng2')||jsonb_build_object('procedure_id',pg_temp.aid('tp1'),
  'decision','return','reason','Attach exception list'),pg_temp.vv('eng2'),'rv.return');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.tc(pg_temp.run('run2','tp1',40,2,'ineffective'),pg_temp.vv('eng2'),'run2');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.tc(pg_temp.e2('review_test','eng2')||jsonb_build_object('procedure_id',pg_temp.aid('tp1'),
  'decision','accept','reason','Workpaper complete'),pg_temp.vv('eng2'),'rv.accept');
reset role;
select is((select count(*)::integer from assurance.test_runs where procedure_id=pg_temp.aid('tp1')),2,'returned and accepted runs both retained');
select is((select status||':'||reviewed_by::text from assurance.test_procedures where id=pg_temp.aid('tp1')),
  'reviewed:'||pg_temp.aid('reviewer')::text,'procedure reviewed by independent reviewer');
select throws_ok($$update assurance.test_runs set exceptions_found=0 where id=pg_temp.aid('run1')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','test run results immutable');
select is((select sample_digest from assurance.test_runs where id=pg_temp.aid('run2')),
  encode(extensions.digest((select array_to_string(sample_positions,',') from assurance.test_procedures where id=pg_temp.aid('tp1')),'sha256'),'hex'),
  'run binds the exact sample positions');

-- Exceptions from testing; dismissal and independent risk decisions.
select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.c2(pg_temp.e2('record_exception','eng2')||jsonb_build_object('exception_id',pg_temp.aid('x2a'),'control_id',pg_temp.aid('ctl2'),
  'description','Two payments released before approval','severity','high'),pg_temp.vv('eng2'),'x2a');
select pg_temp.c2(pg_temp.e2('record_exception','eng2')||jsonb_build_object('exception_id',pg_temp.aid('x2b'),'control_id',pg_temp.aid('ctl2'),
  'description','Approval timestamp one minute late','severity','low'),pg_temp.vv('eng2'),'x2b');
select pg_temp.c2(pg_temp.e2('record_exception','eng2')||jsonb_build_object('exception_id',pg_temp.aid('x2c'),'control_id',pg_temp.aid('ctl2'),
  'description','Approver also prepared payment','severity','medium'),pg_temp.vv('eng2'),'x2c');
select throws_ok($$select pg_temp.c2(pg_temp.e2('dismiss_exception','eng2')||jsonb_build_object('exception_id',pg_temp.aid('x2b'),
  'reason','Clock skew'),pg_temp.vv('eng2'),'dis.self')$$,'42501','ASSURANCE_INDEPENDENT_REVIEW_REQUIRED','recorder cannot dismiss own exception');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.c2(pg_temp.e2('dismiss_exception','eng2')||jsonb_build_object('exception_id',pg_temp.aid('x2b'),'reason','Clock skew'),pg_temp.vv('eng2'),'dis');
select pg_temp.c2(pg_temp.e2('issue_finding','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2a'),'exception_id',pg_temp.aid('x2a'),
  'title','Payments released before approval','severity','high','owner_id',pg_temp.aid('owner')),pg_temp.vv('eng2'),'f2a');
select pg_temp.c2(pg_temp.e2('issue_finding','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2c'),'exception_id',pg_temp.aid('x2c'),
  'title','Preparer approved own payment','severity','medium','owner_id',pg_temp.aid('owner')),pg_temp.vv('eng2'),'f2c');
reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.c2(pg_temp.e2('respond','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2a'),'response','Request to accept until ERP upgrade',
  'due_date',(current_date+60)::text,'accept_risk',true),pg_temp.vv('eng2'),'r2a');
select pg_temp.c2(pg_temp.e2('respond','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2c'),'response','Accept until hiring completes',
  'due_date',(current_date+60)::text,'accept_risk',true),pg_temp.vv('eng2'),'r2c');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.c2(pg_temp.e2('decide_risk','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2a'),
  'decision','approve','reason','Issuer approving'),pg_temp.vv('eng2'),'dr.issuer')$$,'42501','ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED','issuer cannot decide risk');
reset role;select pg_temp.actor('lead',false);set local role authenticated;
select throws_ok($$select pg_temp.c2(pg_temp.e2('decide_risk','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2a'),
  'decision','reject','reason','Too severe'),pg_temp.vv('eng2'),'dr.nomfa')$$,'42501','ASSURANCE_RECENT_MFA_REQUIRED','risk decision requires MFA');
reset role;select pg_temp.actor('lead');set local role authenticated;
select pg_temp.c2(pg_temp.e2('decide_risk','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2a'),'decision','reject','reason','Too severe to accept'),pg_temp.vv('eng2'),'dr.reject');
select pg_temp.c2(pg_temp.e2('decide_risk','eng2')||jsonb_build_object('finding_id',pg_temp.aid('f2c'),'decision','approve','reason','Compensating review exists'),pg_temp.vv('eng2'),'dr.approve');
reset role;
select is((select array_agg(status order by id) from assurance.findings where id in (pg_temp.aid('f2a'),pg_temp.aid('f2c'))),
  (select array_agg(s order by i) from (values (pg_temp.aid('f2a'),'remediating'),(pg_temp.aid('f2c'),'risk_accepted')) v(i,s)),
  'rejected risk returns to remediation; approved risk is accepted');

-- Report issue; archive blocked until the open finding is carried forward.
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('transition','eng2')||'{"to_status":"reporting","reason":"Fieldwork complete"}',pg_temp.vv('eng2'),'reporting');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.c2(pg_temp.e2('issue_report','eng2')||jsonb_build_object('report_id',pg_temp.aid('eng2.rep1'),'summary','One open high finding; one accepted risk'),pg_temp.vv('eng2'),'rep');
reset role;select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.c2(pg_temp.e2('transition','eng2')||'{"to_status":"archived","reason":"Cycle end"}',pg_temp.vv('eng2'),'arch.early')$$,
  '55000','ASSURANCE_OPEN_FINDINGS_NOT_CARRIED','open findings block archiving');
select pg_temp.c2(pg_temp.e2('create_engagement','eng3')||jsonb_build_object('name','FY27 Payments','period_start','2027-04-01',
  'period_end','2028-03-31','scope_summary','Supplier payment controls','lead_auditor_id',pg_temp.aid('lead')),0,'eng3');
select pg_temp.c2(pg_temp.e2('add_team_member','eng3')||jsonb_build_object('user_id',pg_temp.aid('reviewer'),'role','reviewer'),pg_temp.vv('eng3'),'eng3.rev');
select pg_temp.c2(pg_temp.e2('map_control','eng3')||jsonb_build_object('control_id',pg_temp.aid('ctl3'),'control_code','PAY-APPROVAL',
  'title','Payment approval before release','owner_id',pg_temp.aid('owner'),'risk','high'),pg_temp.vv('eng3'),'ctl3');
create function pg_temp.carry(src text,f text,x text) returns jsonb language sql as $$
  select pg_temp.e2('carry_forward','eng3')||jsonb_build_object('finding_id',pg_temp.aid(f),'source_finding_id',pg_temp.aid(src),
    'exception_id',pg_temp.aid(x),'control_id',pg_temp.aid('ctl3')) $$;
reset role;select pg_temp.actor('reviewer',false);set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.carry('f2a','f3a','x3a'),pg_temp.vv('eng3'),'cf.nomfa')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','carry-forward requires MFA');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.tc(pg_temp.carry('f2c','f3c','x3c'),pg_temp.vv('eng3'),'cf.accepted')$$,
  '55000','ASSURANCE_FINDING_NOT_OPEN','accepted risk is not carried as open');
select pg_temp.tc(pg_temp.carry('f2a','f3a','x3a'),pg_temp.vv('eng3'),'cf');
select throws_ok($$select pg_temp.tc(pg_temp.carry('f2a','f3b','x3b'),pg_temp.vv('eng3'),'cf.twice')$$,
  '23505','ASSURANCE_ALREADY_CARRIED','a finding is carried only once');
select throws_ok($$select pg_temp.tc(pg_temp.carry('f3a','f3d','x3d'),pg_temp.vv('eng3'),'cf.self')$$,
  '55000','ASSURANCE_SOURCE_NOT_ISSUED','source engagement must have an issued report');
reset role;
select ok((select carried_from_finding_id=pg_temp.aid('f2a') and status='issued' and severity='high' and owner_id=pg_temp.aid('owner')
  from assurance.findings where id=pg_temp.aid('f3a')),'carried finding links to its source with severity and owner');
select is((select status from assurance.findings where id=pg_temp.aid('f2a')),'remediating','source finding history is unchanged');
select is((select source||':'||status from assurance.exceptions where id=pg_temp.aid('x3a')),'carry_forward:promoted','carried exception is marked as carried');
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('transition','eng2')||'{"to_status":"archived","reason":"Cycle end"}',pg_temp.vv('eng2'),'arch');
select throws_ok($$select pg_temp.c2(pg_temp.e2('map_control','eng2')||jsonb_build_object('control_id',pg_temp.aid('ctl2x'),'control_code','LATE',
  'title','Late control','owner_id',pg_temp.aid('owner'),'risk','low'),pg_temp.vv('eng2'),'arch.write')$$,
  '55000','ASSURANCE_ENGAGEMENT_CLOSED','archived engagement is read-only');

-- External reviewers cannot use the test command either.
reset role;
update assurance.engagement_team set expires_at=now()+interval '1 day' where engagement_id=pg_temp.aid('eng') and user_id=pg_temp.aid('external');
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.aid('tenant'),pg_temp.aid('external.r'),'assurance.test.perform');
select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select api.assurance_test_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
  pg_temp.aid('key2.ext'),pg_temp.e2('design_test','eng')||jsonb_build_object('procedure_id',pg_temp.aid('tp.ext'),'control_id',pg_temp.aid('ctl'),
  'code','EXT','objective','External test','population_size',10,'sample_start',1),pg_temp.ver())$$,
  '42501','ASSURANCE_EXTERNAL_READ_ONLY','external reviewer cannot run tests');
insert into assurance_samples values('tests',api.assurance_tests(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('eng')));
reset role;
select is((select body from assurance_samples where label='tests'),'[]'::jsonb,'external can read test work for their engagement');

-- A late failure leaves no procedure, receipt, event or version change.
create function pg_temp.late_failure() returns trigger language plpgsql as $$begin
  if new.aggregate_id=pg_temp.aid('tp.late') then raise exception using errcode='P0001',message='SYNTHETIC_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_late_failure before insert on assurance.events for each row execute function pg_temp.late_failure();
create temporary table assurance_versions as select pg_temp.vv('eng3') v;
select pg_temp.actor('lead');set local role authenticated;
select throws_ok($$select api.assurance_test_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
  pg_temp.aid('key2.late'),pg_temp.e2('design_test','eng3')||jsonb_build_object('procedure_id',pg_temp.aid('tp.late'),'control_id',pg_temp.aid('ctl3'),
  'code','LATE','objective','Late failure probe','population_size',10,'sample_start',1),pg_temp.vv('eng3'))$$,
  'P0001','SYNTHETIC_LATE_FAILURE','late event failure aborts the whole command');
reset role;
drop trigger synthetic_late_failure on assurance.events;
select ok(not exists(select 1 from assurance.test_procedures where id=pg_temp.aid('tp.late'))
  and not exists(select 1 from assurance.command_receipts where idempotency_key=pg_temp.aid('key2.late'))
  and pg_temp.vv('eng3')=(select v from assurance_versions),'late failure leaves no residue');

select is((select count(*)::integer from assurance.events where engagement_id=pg_temp.aid('eng2')),
  (select version::integer from assurance.engagements where id=pg_temp.aid('eng2')),'A2: one event per engagement version');
