-- Corporate Audit & Assurance evidence-storage candidate tests (PR #1 review,
-- thread 4309904782). Included only by build_assurance_candidate.ps1 -Slice A7,
-- after the A6 tests and the storage candidate DDL. Reuses the A1 actors and
-- pg_temp.e2/vv. Storage rows are synthetic metadata; no bytes are uploaded and
-- everything rolls back.
create function pg_temp.sref(ev text) returns text language sql as $$
  select 'assurance/'||pg_temp.aid('tenant')||'/'||pg_temp.aid('engS')||'/'||pg_temp.aid(ev) $$;
create function pg_temp.submit(req text,ev text,body text,k text) returns jsonb language sql as $$
  select pg_temp.cmd(pg_temp.e2('submit_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid(req),
    'evidence_id',pg_temp.aid(ev),'source_module','manual','source_reference','Signed bank confirmation',
    'source_as_of',now()::text,'collection_method','manual','query_version',null,'sha256',pg_temp.hex(body),
    'byte_size',octet_length(body),'storage_ref',pg_temp.sref(ev),'classification','confidential'),pg_temp.vv('engS'),k) $$;
create function pg_temp.put(ev text,size bigint,p_name text default null) returns void language sql as $$
  insert into storage.objects(bucket_id,name,owner_id,metadata)
  values('jentra-assurance-evidence',coalesce(p_name,pg_temp.sref(ev)),(select auth.uid())::text,
    jsonb_build_object('size',size,'mimetype','application/pdf')) $$;
create function pg_temp.ticket(ev text) returns jsonb language sql as $$
  select api.assurance_evidence_verification_ticket(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),
    pg_temp.aid('tenant.branch'),pg_temp.aid('engS'),pg_temp.aid(ev)) $$;
create function pg_temp.vstatus(ev text) returns jsonb language sql as $$
  select api.assurance_evidence_verification(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),
    pg_temp.aid('tenant.branch'),pg_temp.aid('engS'),pg_temp.aid(ev)) $$;
create function pg_temp.service() returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  perform set_config('request.jwt.claim.sub','',true);
end $$;
create temporary table storage_tickets(label text primary key,body jsonb);
do $$ begin if to_regclass('pg_temp.assurance_assertions') is not null then
  execute 'grant insert on assurance_assertions to service_role'; end if; end $$;
grant select,insert on storage_tickets to authenticated,service_role;

-- Structure.
select ok((select not public and file_size_limit=104857600 from storage.buckets where id='jentra-assurance-evidence'),
  'storage: private evidence bucket bounded to the 100 MiB evidence limit');
select ok((select bool_and(relrowsecurity and relforcerowsecurity) and count(*)=2 from pg_class c join pg_namespace n
  on n.oid=c.relnamespace where n.nspname='assurance' and c.relname in ('evidence_verifications','evidence_verification_tickets')),
  'storage: verification tables force RLS');
select ok(not exists(select 1 from unnest(array['assurance.evidence_verifications','assurance.evidence_verification_tickets']) t
  where has_table_privilege('authenticated',t,'SELECT') or has_table_privilege('service_role',t,'SELECT')
     or has_table_privilege('service_role',t,'INSERT')),'storage: no direct client or service grants on verification tables');
select ok(has_function_privilege('service_role','api.assurance_evidence_service_verify(uuid,uuid,text,bigint)','EXECUTE')
  and not has_function_privilege('authenticated','api.assurance_evidence_service_verify(uuid,uuid,text,bigint)','EXECUTE')
  and not has_function_privilege('authenticated','api.assurance_evidence_service_target(uuid,uuid)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_evidence_verification_ticket(uuid,uuid,uuid,uuid,uuid)','EXECUTE')
  and has_function_privilege('authenticated','api.assurance_evidence_verification_ticket(uuid,uuid,uuid,uuid,uuid)','EXECUTE'),
  'storage: only the service records verifications; tickets are authenticated-only');
select is((select count(*)::integer from pg_policies where schemaname='storage' and tablename='objects'
  and policyname like 'assurance_evidence_%'),6,'storage: upload, own-read and four restrictive guards on storage.objects');

-- An engagement in fieldwork with one owner request.
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.cmd(pg_temp.e2('create_engagement','engS')||jsonb_build_object('name','FY26 Treasury evidence',
  'period_start','2026-04-01','period_end','2027-03-31','scope_summary','Bank confirmations','lead_auditor_id',pg_temp.aid('lead')),0,'s.create');
select pg_temp.cmd(pg_temp.e2('add_team_member','engS')||jsonb_build_object('user_id',pg_temp.aid('auditor'),'role','auditor'),pg_temp.vv('engS'),'s.auditor');
select pg_temp.cmd(pg_temp.e2('add_team_member','engS')||jsonb_build_object('user_id',pg_temp.aid('reviewer'),'role','reviewer'),pg_temp.vv('engS'),'s.reviewer');
select pg_temp.cmd(pg_temp.e2('add_team_member','engS')||jsonb_build_object('user_id',pg_temp.aid('external'),'role','external',
  'expires_at',(now()+interval '30 days')::text),pg_temp.vv('engS'),'s.external');
select pg_temp.cmd(pg_temp.e2('map_control','engS')||jsonb_build_object('control_id',pg_temp.aid('ctlS'),
  'control_code','TRS-BANK','title','Bank confirmation','owner_id',pg_temp.aid('owner'),'risk','high'),pg_temp.vv('engS'),'s.ctl');
reset role;select pg_temp.actor('lead');set local role authenticated;
select pg_temp.cmd(pg_temp.e2('request_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqS'),'control_id',pg_temp.aid('ctlS'),
  'owner_id',pg_temp.aid('owner'),'due_date',(current_date+7)::text,'description','Signed bank confirmation letter'),pg_temp.vv('engS'),'s.req');
select pg_temp.cmd(pg_temp.e2('request_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqT'),'control_id',pg_temp.aid('ctlS'),
  'owner_id',pg_temp.aid('owner'),'due_date',(current_date+7)::text,'description','Bank reconciliation sign-off'),pg_temp.vv('engS'),'s.req2');
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.cmd(pg_temp.e2('transition','engS')||'{"to_status":"fieldwork","reason":"Planning approved"}',pg_temp.vv('engS'),'s.fieldwork');

-- Upload is authorized only for the owner's own submitted item, on its path.
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.put('evS1',20)$$,'42501',null,'storage: no upload before the evidence item exists');
select pg_temp.submit('reqS','evS1','tampered bank letter','s.ev1');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.put('evS1',20)$$,'42501',null,'storage: a non-owner cannot upload to the generated path');
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.put('evS1',20,'assurance/'||pg_temp.aid('tenant')||'/'||pg_temp.aid('engS')||'/'||pg_temp.aid('evX'))$$,
  '42501',null,'storage: the owner cannot upload to a path with no submitted item');
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata) values('jentra-assurance-evidence',
  pg_temp.sref('evS1'),pg_temp.aid('auditor')::text,'{"size":20}')$$,'42501',null,'storage: the upload must be owned by the caller');
select throws_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata) values('jentra-attachments',
  pg_temp.sref('evS1'),(select auth.uid())::text,'{"size":20}')$$,'42501',null,'storage: the generated path is unusable in another bucket');

-- Acceptance is refused while no bytes are stored or verified.
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e2('review_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqS'),
  'decision','accept','reason','Looks complete'),pg_temp.vv('engS'),'s.acc.nobytes')$$,
  '55000','ASSURANCE_EVIDENCE_UNVERIFIED','storage: evidence with no stored bytes cannot be accepted');
reset role;select pg_temp.actor('owner');set local role authenticated;
insert into storage_tickets values('nobytes',pg_temp.ticket('evS1'));
reset role;select pg_temp.service();set local role service_role;
select throws_ok($$select api.assurance_evidence_service_target((select (body->>'ticket_id')::uuid from storage_tickets where label='nobytes'),
  pg_temp.aid('owner'))$$,'55000','ASSURANCE_EVIDENCE_OBJECT_MISSING','storage: verification reports a missing object');

reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.put('evS1',20);
select is((select count(*)::integer from storage.objects where name=pg_temp.sref('evS1')),1,'storage: the owner uploads once and can read their row back');
select throws_ok($$select pg_temp.put('evS1',20)$$,'23505',null,'storage: an uploaded object cannot be replaced by a second insert');
update storage.objects set metadata='{"size":1}' where name=pg_temp.sref('evS1');
select is((select metadata->>'size' from storage.objects where name=pg_temp.sref('evS1')),'20','storage: clients cannot overwrite an uploaded object');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select is((select count(*)::integer from storage.objects where name=pg_temp.sref('evS1')),0,'storage: reviewers never read evidence bytes directly');
select throws_ok($$select pg_temp.cmd(pg_temp.e2('review_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqS'),
  'decision','accept','reason','Looks complete'),pg_temp.vv('engS'),'s.acc.unverified')$$,
  '55000','ASSURANCE_EVIDENCE_UNVERIFIED','storage: stored but unverified evidence cannot be accepted');

-- Tickets: who may ask.
reset role;select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select pg_temp.ticket('evS1')$$,'42501',null,'storage: external reviewers cannot trigger verification');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select pg_temp.ticket('evS1')$$,'42501',null,'storage: a foreign tenant actor cannot ask for a ticket');
reset role;select pg_temp.actor('owner');set local role authenticated;
insert into storage_tickets values('owner',pg_temp.ticket('evS1'));
select ok((select body->>'ticket_id' is not null and body->'verification'='null'::jsonb from storage_tickets where label='owner'),
  'storage: the request owner obtains a one-use verification ticket');
select throws_ok($$select api.assurance_evidence_service_verify((select (body->>'ticket_id')::uuid from storage_tickets where label='owner'),
  pg_temp.aid('owner'),repeat('a',64),20)$$,'42501',null,'storage: a human session cannot record a verification');

-- The service hashes the stored bytes; a mismatch is recorded and final.
reset role;select pg_temp.service();set local role service_role;
select throws_ok($$select api.assurance_evidence_service_target((select (body->>'ticket_id')::uuid from storage_tickets where label='owner'),
  pg_temp.aid('reviewer'))$$,'42501','ASSURANCE_TICKET_INVALID','storage: a ticket is bound to the human who asked');
select is((select api.assurance_evidence_service_target((select (body->>'ticket_id')::uuid from storage_tickets where label='owner'),
  pg_temp.aid('owner'))->>'object_path'),pg_temp.sref('evS1'),'storage: the service target is the generated path');
select is(api.assurance_evidence_service_verify((select (body->>'ticket_id')::uuid from storage_tickets where label='owner'),
  pg_temp.aid('owner'),pg_temp.hex('different stored bytes'),20)->>'outcome','mismatch',
  'storage: bytes that do not hash to the claimed digest are recorded as a mismatch');
select throws_ok($$select api.assurance_evidence_service_verify((select (body->>'ticket_id')::uuid from storage_tickets where label='owner'),
  pg_temp.aid('owner'),pg_temp.hex('tampered bank letter'),20)$$,'42501','ASSURANCE_TICKET_INVALID','storage: a ticket is used once');
reset role;
select throws_ok($$update assurance.evidence_verifications set outcome='verified' where evidence_id=pg_temp.aid('evS1')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','storage: a verification outcome is immutable');
select pg_temp.actor('owner');set local role authenticated;
select is(pg_temp.ticket('evS1')#>>'{verification,outcome}','mismatch','storage: a later ticket request returns the recorded outcome');
select ok((select (v->>'stored')::boolean and not (v->>'bytes_verified')::boolean and (v->>'upload_required')::boolean
  from pg_temp.vstatus('evS1') v),'storage: the owner reads stored-but-mismatched status');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e2('review_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqS'),
  'decision','accept','reason','Looks complete'),pg_temp.vv('engS'),'s.acc.mismatch')$$,
  '55000','ASSURANCE_EVIDENCE_UNVERIFIED','storage: mismatched evidence cannot be accepted');
select pg_temp.cmd(pg_temp.e2('review_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqS'),
  'decision','reject','reason','Stored file does not match its digest'),pg_temp.vv('engS'),'s.rej');

-- Resubmission under a new id and path, verified by an audit team member.
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.put('evS1',20,pg_temp.sref('evS1')||'x')$$,'42501',null,'storage: malformed paths are refused');
select pg_temp.submit('reqS','evS2','signed bank letter v2','s.ev2');
select pg_temp.put('evS2',21);
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.put('evS1',20)$$,'42501',null,'storage: a superseded item can no longer be uploaded');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
insert into storage_tickets values('reviewer',pg_temp.ticket('evS2'));
reset role;select pg_temp.service();set local role service_role;
select is(api.assurance_evidence_service_verify((select (body->>'ticket_id')::uuid from storage_tickets where label='reviewer'),
  pg_temp.aid('reviewer'),pg_temp.hex('signed bank letter v2'),21)->>'outcome','verified',
  'storage: matching bytes are verified');
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.put('evS2',21,pg_temp.sref('evS2'))$$,'42501',null,'storage: no upload after verification');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select ok((select (v->>'bytes_verified')::boolean and v#>>'{verification,outcome}'='verified' from pg_temp.vstatus('evS2') v),
  'storage: reviewers read the verified status, not the bytes');
select pg_temp.cmd(pg_temp.e2('review_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqS'),
  'decision','accept','reason','Verified bank confirmation'),pg_temp.vv('engS'),'s.acc');
reset role;
select is((select status from assurance.evidence_requests where id=pg_temp.aid('reqS')),'accepted','storage: verified evidence is accepted');

-- A verified object that is later rewritten (outside the client API) no longer counts.
select pg_temp.actor('owner');set local role authenticated;
select pg_temp.submit('reqT','evT1','reconciliation sign-off','s.evT');
select pg_temp.put('evT1',23);
insert into storage_tickets values('owner.t',pg_temp.ticket('evT1'));
reset role;select pg_temp.service();set local role service_role;
select is(api.assurance_evidence_service_verify((select (body->>'ticket_id')::uuid from storage_tickets where label='owner.t'),
  pg_temp.aid('owner'),pg_temp.hex('reconciliation sign-off'),23)->>'outcome','verified','storage: second item verified');
reset role;
update storage.objects set metadata=metadata||'{"eTag":"rewritten"}', version='rewritten'
 where name=pg_temp.sref('evT1');
select ok(not assurance.evidence_bytes_verified(pg_temp.aid('evT1')),'storage: a rewritten object invalidates its verification');
select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e2('review_evidence','engS')||jsonb_build_object('request_id',pg_temp.aid('reqT'),
  'decision','accept','reason','Looks complete'),pg_temp.vv('engS'),'s.acc.rewritten')$$,
  '55000','ASSURANCE_EVIDENCE_UNVERIFIED','storage: a rewritten object cannot be accepted');
reset role;

-- Freeze also refuses unverified accepted upload evidence (covers pre-install acceptances).
alter table assurance.evidence_requests disable trigger evidence_requests_verified_acceptance;
update assurance.evidence_requests set status='accepted' where id=pg_temp.aid('reqT');
alter table assurance.evidence_requests enable trigger evidence_requests_verified_acceptance;
select pg_temp.actor('lead');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e2('freeze_evidence','engS')||'{"reason":"Fieldwork cutoff"}',pg_temp.vv('engS'),'s.freeze')$$,
  '55000','ASSURANCE_EVIDENCE_UNVERIFIED','storage: freeze refuses accepted evidence whose bytes are not verified');
reset role;
