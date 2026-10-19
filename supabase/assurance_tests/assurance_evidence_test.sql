-- Corporate Audit & Assurance A4 candidate tests (blueprint 68).
-- Included only by build_assurance_candidate.ps1 -Slice A4, after the A1/A2 tests and the
-- A4 candidate DDL, inside the same begin ... rollback block. Reuses A1/A2 fixtures.
create function pg_temp.ec(p jsonb,v bigint,k text) returns jsonb language sql as $$
  select api.assurance_evidence_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
    pg_temp.aid('key4.'||k),p,v) $$;
create function pg_temp.collect(req text,ev text,kind text,src text) returns jsonb language sql as $$
  select pg_temp.e2('collect_system_evidence','eng4')||jsonb_build_object('request_id',pg_temp.aid(req),'evidence_id',pg_temp.aid(ev),
    'source_kind',kind,'source_id',case when src is null then null else pg_temp.aid(src) end) $$;
create function pg_temp.grant_perm(r text,p text) returns void language sql as $$
  insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.aid('tenant'),pg_temp.aid(r||'.r'),p) $$;

reset role;
-- Synthetic authoritative module reports (immutable source rows; rolled back).
insert into finance.control_reports(id,tenant_id,legal_entity_id,branch_id,as_of,generated_at,summary,evidence,created_by)
values
 (pg_temp.aid('cr.in'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'2026-09-30',now(),
  jsonb_build_object('id',pg_temp.aid('cr.in'),'difference','0.00'),'{"lines":[]}'::jsonb,pg_temp.aid('manager')),
 (pg_temp.aid('cr.old'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'2025-01-31',now(),
  jsonb_build_object('id',pg_temp.aid('cr.old'),'difference','0.00'),'{"lines":[]}'::jsonb,pg_temp.aid('manager')),
 (pg_temp.aid('cr.b2'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch2'),'2026-09-30',now(),
  jsonb_build_object('id',pg_temp.aid('cr.b2'),'difference','5.00'),'{"lines":[]}'::jsonb,pg_temp.aid('manager'));

select ok((select count(*)=16 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class c
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='assurance' and c.relkind='r'),'A4: all 16 assurance tables force RLS');
select ok(not has_table_privilege('authenticated','assurance.system_snapshots','SELECT')
  and not has_table_privilege('service_role','assurance.exports','SELECT')
  and not has_function_privilege('authenticated','assurance.source_document(text,uuid,uuid,uuid,uuid)','EXECUTE'),
  'A4: snapshots/exports are API-only and adapters are not client-callable');

select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('create_engagement','eng4')||jsonb_build_object('name','FY26 Close controls','period_start','2026-04-01',
  'period_end','2027-03-31','scope_summary','Period close and access controls','lead_auditor_id',pg_temp.aid('lead')),0,'eng4');
select pg_temp.c2(pg_temp.e2('add_team_member','eng4')||jsonb_build_object('user_id',pg_temp.aid('auditor'),'role','auditor'),pg_temp.vv('eng4'),'eng4.aud');
select pg_temp.c2(pg_temp.e2('add_team_member','eng4')||jsonb_build_object('user_id',pg_temp.aid('reviewer'),'role','reviewer'),pg_temp.vv('eng4'),'eng4.rev');
select pg_temp.c2(pg_temp.e2('add_team_member','eng4')||jsonb_build_object('user_id',pg_temp.aid('external'),'role','external',
  'expires_at',(now()+interval '10 days')::text),pg_temp.vv('eng4'),'eng4.ext');
select pg_temp.c2(pg_temp.e2('map_control','eng4')||jsonb_build_object('control_id',pg_temp.aid('ctl4'),'control_code','FIN-CTRL-REC',
  'title','Control account reconciliation','owner_id',pg_temp.aid('owner'),'risk','high'),pg_temp.vv('eng4'),'ctl4');
reset role;select pg_temp.actor('lead');set local role authenticated;
select pg_temp.c2(pg_temp.e2('request_evidence','eng4')||jsonb_build_object('request_id',pg_temp.aid('req4a'),'control_id',pg_temp.aid('ctl4'),
  'owner_id',pg_temp.aid('owner'),'due_date',(current_date+5)::text,'description','Control reconciliation at period end'),pg_temp.vv('eng4'),'req4a');
select pg_temp.c2(pg_temp.e2('request_evidence','eng4')||jsonb_build_object('request_id',pg_temp.aid('req4b'),'control_id',pg_temp.aid('ctl4'),
  'owner_id',pg_temp.aid('owner'),'due_date',(current_date+5)::text,'description','Privileged access review'),pg_temp.vv('eng4'),'req4b');
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('transition','eng4')||'{"to_status":"fieldwork","reason":"Plan approved"}',pg_temp.vv('eng4'),'eng4.fw');

-- Adapters reuse the owning module's authority; they never widen access.
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.collect('req4a','ev4a','finance.general_ledger','cr.in'),pg_temp.vv('eng4'),'kind')$$,
  '22023','ASSURANCE_SOURCE_KIND_INVALID','unknown source kinds are rejected');
select throws_ok($$select pg_temp.ec(pg_temp.collect('req4a','ev4a','finance.control_reconciliation','cr.in'),pg_temp.vv('eng4'),'noperm')$$,
  '42501',null,'auditor without finance authority cannot pull finance evidence');
reset role;
select pg_temp.grant_perm('auditor','finance.view');select pg_temp.grant_perm('auditor','finance.controls.reconcile');
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.collect('req4a','ev4a','finance.control_reconciliation','cr.b2'),pg_temp.vv('eng4'),'b2')$$,
  'P0002','ASSURANCE_SOURCE_NOT_FOUND','a report from another branch is not reachable through this scope');
select throws_ok($$select pg_temp.ec(pg_temp.collect('req4a','ev4a','finance.control_reconciliation','cr.old'),pg_temp.vv('eng4'),'old')$$,
  '22023','ASSURANCE_SOURCE_OUTSIDE_PERIOD','source cutoff must fall inside the audit period');
select pg_temp.ec(pg_temp.collect('req4a','ev4a','finance.control_reconciliation','cr.in'),pg_temp.vv('eng4'),'ev4a');
reset role;
select is((select sha256 from assurance.evidence_items where id=pg_temp.aid('ev4a')),
  (select encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') from finance.control_reports r where r.id=pg_temp.aid('cr.in')),
  'digest binds the canonical authoritative source row');
select is((select source_module||'|'||collection_method||'|'||query_version||'|'||source_reference from assurance.evidence_items where id=pg_temp.aid('ev4a')),
  'finance|system|fin.control_reports.v1|finance.control_reconciliation/'||pg_temp.aid('cr.in')::text,'provenance records module, method, query version and source');
select is((select (source_as_of at time zone 'UTC')::date from assurance.evidence_items where id=pg_temp.aid('ev4a')),'2026-09-30'::date,
  'evidence cutoff is the source as-of date');

select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.collect('req4b','ev4b','it_control.access_review',null),pg_temp.vv('eng4'),'acc.noperm')$$,
  '42501',null,'access review requires audit.read');
reset role;select pg_temp.grant_perm('auditor','audit.read');
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.collect('req4b','ev4b','it_control.access_review','cr.in'),pg_temp.vv('eng4'),'acc.src')$$,
  '22023','ASSURANCE_UNEXPECTED_FIELD','access review takes no source id');
select pg_temp.ec(pg_temp.collect('req4b','ev4b','it_control.access_review',null),pg_temp.vv('eng4'),'ev4b');
reset role;
select ok((select classification='restricted' and storage_ref='assurance.system_snapshots/'||pg_temp.aid('ev4b')::text
  from assurance.evidence_items where id=pg_temp.aid('ev4b')),'access review is restricted and stored as a protected snapshot');
select ok((select content::text not like '%@%' and jsonb_array_length(content->'roles')>0
  and sha256=encode(extensions.digest(convert_to(content::text,'UTF8'),'sha256'),'hex')
  from assurance.system_snapshots where id=pg_temp.aid('ev4b')),'snapshot has roles, no identities/emails, and a matching digest');
select throws_ok($$update assurance.system_snapshots set content='{}'::jsonb where id=pg_temp.aid('ev4b')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','system snapshot immutable');

-- Re-verification uses current module authority.
select pg_temp.actor('auditor');set local role authenticated;
insert into assurance_samples values('verify4a',api.assurance_verify_evidence(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('ev4a')));
insert into assurance_samples values('verify4b',api.assurance_verify_evidence(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('ev4b')));
reset role;
select ok((select bool_and((body->>'matches')::boolean) from assurance_samples where label in ('verify4a','verify4b')),
  'module and snapshot evidence both re-verify against their source');
delete from core.role_permissions where tenant_id=pg_temp.aid('tenant') and role_id=pg_temp.aid('auditor.r') and permission_code='finance.view';
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select api.assurance_verify_evidence(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('ev4a'))$$,
  '42501',null,'losing module authority stops re-reading the source');
reset role;select pg_temp.grant_perm('auditor','finance.view');

-- Independent review, freeze, then no further collection.
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.c2(pg_temp.e2('review_evidence','eng4')||jsonb_build_object('request_id',pg_temp.aid('req4a'),'decision','accept','reason','Own'),pg_temp.vv('eng4'),'self.rev')$$,
  '42501','ASSURANCE_SELF_REVIEW_FORBIDDEN','collector cannot accept system evidence they collected');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.c2(pg_temp.e2('review_evidence','eng4')||jsonb_build_object('request_id',pg_temp.aid('req4a'),'decision','accept','reason','Ties to ledger'),pg_temp.vv('eng4'),'acc4a');
select pg_temp.c2(pg_temp.e2('review_evidence','eng4')||jsonb_build_object('request_id',pg_temp.aid('req4b'),'decision','accept','reason','Roles reviewed'),pg_temp.vv('eng4'),'acc4b');
reset role;select pg_temp.actor('lead');set local role authenticated;
select pg_temp.c2(pg_temp.e2('freeze_evidence','eng4')||'{"reason":"Fieldwork cutoff"}',pg_temp.vv('eng4'),'freeze4');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.collect('req4a','ev4z','finance.control_reconciliation','cr.in'),pg_temp.vv('eng4'),'late')$$,
  '55000','ASSURANCE_EVIDENCE_FROZEN','no collection after freeze');

-- Governed audit-pack export.
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('transition','eng4')||'{"to_status":"reporting","reason":"Fieldwork complete"}',pg_temp.vv('eng4'),'eng4.rep');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.e2('export_pack','eng4')||jsonb_build_object('export_id',pg_temp.aid('x4.early'),'report_id',pg_temp.aid('eng4.r1')),pg_temp.vv('eng4'),'early')$$,
  '42501',null,'export requires assurance.report.export');
reset role;select pg_temp.grant_perm('reviewer','assurance.report.export');
select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.e2('export_pack','eng4')||jsonb_build_object('export_id',pg_temp.aid('x4.early'),'report_id',pg_temp.aid('eng4.r1')),pg_temp.vv('eng4'),'early2')$$,
  '55000','ASSURANCE_REPORT_NOT_ISSUED','nothing to export before a report is issued');
select pg_temp.c2(pg_temp.e2('issue_report','eng4')||jsonb_build_object('report_id',pg_temp.aid('eng4.r1'),'summary','No exceptions noted'),pg_temp.vv('eng4'),'eng4.r1');
reset role;select pg_temp.actor('reviewer',false);set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.e2('export_pack','eng4')||jsonb_build_object('export_id',pg_temp.aid('x4.1'),'report_id',pg_temp.aid('eng4.r1')),pg_temp.vv('eng4'),'x.nomfa')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','export requires recent MFA');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
insert into assurance_samples values('export1',pg_temp.ec(pg_temp.e2('export_pack','eng4')||jsonb_build_object('export_id',pg_temp.aid('x4.1'),'report_id',pg_temp.aid('eng4.r1')),pg_temp.vv('eng4'),'x1'));
insert into assurance_samples values('manifest1',api.assurance_export_manifest(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('x4.1')));
reset role;
select ok((select encode(extensions.digest(convert_to((body->'manifest')::text,'UTF8'),'sha256'),'hex')=body->>'manifest_sha256'
  and octet_length((body->'manifest')::text)=(body->>'manifest_bytes')::bigint
  and jsonb_array_length(body->'manifest'->'evidence')=2 from assurance_samples where label='manifest1'),
  'reopened manifest re-hashes to the recorded digest and size with both evidence items');
select ok((select body->'manifest'->'report'->>'digest'=(select digest from assurance.report_versions where id=pg_temp.aid('eng4.r1'))
  and body->'manifest'->'engagement'->>'evidence_cutoff_digest'=(select evidence_cutoff_digest from assurance.engagements where id=pg_temp.aid('eng4'))
  from assurance_samples where label='manifest1'),'manifest binds the issued report digest and the evidence cutoff digest');
select ok((select (body->'manifest')::text not like '%storage_ref%' from assurance_samples where label='manifest1'),'manifest carries metadata and digests, not storage paths');
select ok((select encode(extensions.digest(convert_to(body->>'manifest_text','UTF8'),'sha256'),'hex')=body->>'manifest_sha256'
  and (body->>'manifest_text')::jsonb=body->'manifest' from assurance_samples where label='manifest1'),'manifest_text is the exact hashed text a client verifies');
select throws_ok($$delete from assurance.exports where id=pg_temp.aid('x4.1')$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','export record immutable');

select pg_temp.actor('external');set local role authenticated;
insert into assurance_samples values('manifest.ext',api.assurance_export_manifest(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('x4.1')));
select throws_ok($$select api.assurance_evidence_command(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('key4.ext'),
  pg_temp.e2('export_pack','eng4')||jsonb_build_object('export_id',pg_temp.aid('x4.ext'),'report_id',pg_temp.aid('eng4.r1')),pg_temp.vv('eng4'))$$,
  '42501',null,'external reviewer cannot create exports');
reset role;
select is((select body->>'manifest_sha256' from assurance_samples where label='manifest.ext'),
  (select body->>'manifest_sha256' from assurance_samples where label='manifest1'),'active external reviewer receives the same pack');
select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select api.assurance_export_manifest(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('x4.1'))$$,
  '42501',null,'outsider cannot read the pack');

-- A reopened and reissued report supersedes the earlier version for export.
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.c2(pg_temp.e2('reopen_report','eng4')||'{"reason":"Add management comment"}',pg_temp.vv('eng4'),'eng4.reopen');
select pg_temp.c2(pg_temp.e2('issue_report','eng4')||jsonb_build_object('report_id',pg_temp.aid('eng4.r2'),'summary','No exceptions noted; comment added'),pg_temp.vv('eng4'),'eng4.r2');
select throws_ok($$select pg_temp.ec(pg_temp.e2('export_pack','eng4')||jsonb_build_object('export_id',pg_temp.aid('x4.old'),'report_id',pg_temp.aid('eng4.r1')),pg_temp.vv('eng4'),'x.old')$$,
  '55000','ASSURANCE_REPORT_SUPERSEDED','superseded report version cannot be exported');
reset role;
select is((select count(*)::integer from assurance.events where engagement_id=pg_temp.aid('eng4')),
  (select version::integer from assurance.engagements where id=pg_temp.aid('eng4')),'A4: one event per engagement version');
