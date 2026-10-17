-- Corporate Audit & Assurance A1 candidate tests (blueprint 68).
-- Included only by build_assurance_candidate.ps1 inside a begin ... rollback block.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.aid(p text) returns uuid language sql immutable as
  $$select md5('assurance-a1-20261018:'||p)::uuid$$;
create function pg_temp.actor(p text,p_mfa boolean default true,p_age integer default 60) returns void
language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.aid(p),
    'role','authenticated','aal',case when p_mfa then 'aal2' else 'aal1' end,
    'amr',case when p_mfa then jsonb_build_array(jsonb_build_object('method','totp',
      'timestamp',extract(epoch from now())::bigint-p_age)) else '[]'::jsonb end)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.aid(p)::text,true);
end $$;
create function pg_temp.cmd(p jsonb,v bigint,k text,t text default 'tenant') returns jsonb language sql as $$
  select api.assurance_command(pg_temp.aid(t),pg_temp.aid(t||'.entity'),pg_temp.aid(t||'.branch'),
    pg_temp.aid('key.'||k),p,v) $$;
create function pg_temp.e(a text) returns jsonb language sql as $$
  select jsonb_build_object('action',a,'engagement_id',pg_temp.aid('eng')) $$;
create function pg_temp.ver() returns bigint language sql security definer set search_path='' as $$
  select version from assurance.engagements where id=pg_temp.aid('eng') $$;
create function pg_temp.hex(p text) returns text language sql immutable as
  $$select encode(extensions.digest(p,'sha256'),'hex')$$;

-- Synthetic fixtures (rolled back).
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.aid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@assurance.jentra.test','',now(),now(),now()
from unnest(array['manager','lead','auditor','reviewer','owner','external','outsider','foreign']) x;
insert into core.tenants(id,name,slug,status,created_by)
select pg_temp.aid(t),'Assurance '||t,'assurance-a1-'||t,'active',pg_temp.aid('manager')
from unnest(array['tenant','other']) t;
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
select pg_temp.aid(t||'.entity'),pg_temp.aid(t),'Entity '||t,upper(left(t,4))||'AS','LKR','Asia/Colombo',2,pg_temp.aid('manager')
from unnest(array['tenant','other']) t;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.aid(t||'.branch'),pg_temp.aid(t),pg_temp.aid(t||'.entity'),'Branch '||t,upper(left(t,4))||'B',pg_temp.aid('manager')
from unnest(array['tenant','other']) t;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.aid('tenant.branch2'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),'Second','TENB2',pg_temp.aid('manager'));
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.aid(x||'.m'),pg_temp.aid('tenant'),pg_temp.aid(x),'active'
from unnest(array['manager','lead','auditor','reviewer','owner','external']) x;
insert into core.memberships(id,tenant_id,user_id,status)
values(pg_temp.aid('foreign.m'),pg_temp.aid('other'),pg_temp.aid('foreign'),'active');
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.aid(x||'.r'),pg_temp.aid('tenant'),'assurance-'||x,x,false
from unnest(array['manager','lead','auditor','reviewer','owner','external']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
values(pg_temp.aid('foreign.r'),pg_temp.aid('other'),'assurance-foreign','foreign',false);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.aid('tenant'),pg_temp.aid(r||'.r'),p from (values
 ('manager','assurance.engagement.manage'),('manager','assurance.evidence.view'),('manager','assurance.retention.manage'),
 ('lead','assurance.engagement.manage'),('lead','assurance.evidence.request'),('lead','assurance.evidence.view'),
 ('lead','assurance.test.perform'),('lead','assurance.test.review'),('lead','assurance.finding.issue'),
 ('lead','assurance.retest.perform'),('lead','assurance.engagement.close'),
 ('auditor','assurance.evidence.request'),('auditor','assurance.evidence.view'),('auditor','assurance.test.perform'),
 ('auditor','assurance.test.review'),('auditor','assurance.finding.issue'),('auditor','assurance.retest.perform'),
 ('auditor','assurance.evidence.submit'),
 ('reviewer','assurance.evidence.view'),('reviewer','assurance.test.review'),('reviewer','assurance.finding.issue'),
 ('reviewer','assurance.retest.perform'),('reviewer','assurance.engagement.close'),('reviewer','assurance.retention.manage'),
 ('owner','assurance.evidence.submit'),('owner','assurance.response.manage'),('owner','assurance.remediation.manage'),
 ('owner','assurance.retest.perform'),('owner','assurance.evidence.view'),
 ('external','assurance.external_review'),('external','assurance.engagement.manage')) v(r,p);
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.aid('other'),pg_temp.aid('foreign.r'),'assurance.engagement.manage'),
      (pg_temp.aid('other'),pg_temp.aid('foreign.r'),'assurance.evidence.view');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.aid('tenant'),pg_temp.aid(x||'.m'),pg_temp.aid(x||'.r'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('manager')
from unnest(array['manager','lead','auditor','reviewer','owner','external']) x;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.aid('other'),pg_temp.aid('foreign.m'),pg_temp.aid('foreign.r'),null,null,pg_temp.aid('manager'));

-- Structural controls.
select ok((select count(*)=12 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class c
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='assurance' and c.relkind='r'),'all 12 assurance tables force RLS');
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='assurance' and c.relkind='r' and (has_table_privilege('authenticated',c.oid,'SELECT')
  or has_table_privilege('authenticated',c.oid,'INSERT') or has_table_privilege('anon',c.oid,'SELECT')
  or has_table_privilege('service_role',c.oid,'SELECT'))),'no direct client or service table grants');
select ok(not has_schema_privilege('authenticated','assurance','USAGE'),'assurance schema is not exposed');
select ok(has_function_privilege('authenticated','api.assurance_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE')
  and not has_function_privilege('anon','api.assurance_command(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE'),'command API is authenticated-only');
select is((select count(*)::integer from core.permissions where code like 'assurance.%'),15,'fifteen narrow assurance capabilities');
select ok(not exists(select 1 from core.role_permissions where permission_code like 'assurance.%'
  and tenant_id not in (pg_temp.aid('tenant'),pg_temp.aid('other'))),'migration grants no business role any assurance capability');

-- Engagement creation, idempotency and version control.
create temporary table assurance_samples(label text primary key,body jsonb);
grant select,insert on assurance_samples to authenticated;
select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('create_engagement')||jsonb_build_object('name','FY26 Procure-to-pay',
  'period_start','2026-04-01','period_end','2026-03-31','scope_summary','P2P controls','lead_auditor_id',pg_temp.aid('lead')),0,'bad.period')$$,
  '22023','ASSURANCE_PERIOD_INVALID','period end before start rejected');
select throws_ok($$select pg_temp.cmd(pg_temp.e('create_engagement')||jsonb_build_object('name','FY26 Procure-to-pay',
  'period_start','2026-04-01','period_end','2027-03-31','scope_summary','P2P controls','lead_auditor_id',pg_temp.aid('lead'),'status','issued'),0,'extra')$$,
  '22023','ASSURANCE_UNEXPECTED_FIELD','arbitrary status/field injection rejected');
select throws_ok($$select pg_temp.cmd(pg_temp.e('create_engagement')||jsonb_build_object('name','FY26 Procure-to-pay',
  'period_start','2026-04-01','period_end','2027-03-31','scope_summary','P2P controls','lead_auditor_id',pg_temp.aid('outsider')),0,'outsider.lead')$$,
  '22023','ASSURANCE_MEMBER_REQUIRED','lead auditor must be an active tenant member');
select throws_ok($$select pg_temp.cmd(pg_temp.e('create_engagement')||jsonb_build_object('name','FY26','period_start','2026-04-01')
  ,0,'missing')$$,'22023','ASSURANCE_FIELD_INVALID','missing required field rejected, not skipped');
insert into assurance_samples values('create',pg_temp.cmd(pg_temp.e('create_engagement')||jsonb_build_object('name','FY26 Procure-to-pay',
  'period_start','2026-04-01','period_end','2027-03-31','scope_summary','P2P controls','lead_auditor_id',pg_temp.aid('lead')),0,'create'));
select is(pg_temp.cmd(pg_temp.e('create_engagement')||jsonb_build_object('name','FY26 Procure-to-pay',
  'period_start','2026-04-01','period_end','2027-03-31','scope_summary','P2P controls','lead_auditor_id',pg_temp.aid('lead')),0,'create'),
  (select body from assurance_samples where label='create'),'exact replay returns sealed receipt');
select throws_ok($$select pg_temp.cmd(pg_temp.e('create_engagement')||jsonb_build_object('name','Changed name',
  'period_start','2026-04-01','period_end','2027-03-31','scope_summary','P2P controls','lead_auditor_id',pg_temp.aid('lead')),0,'create')$$,
  '22023','IDEMPOTENCY_MISMATCH','changed request cannot reuse a key');
select throws_ok($$select pg_temp.cmd(pg_temp.e('map_control')||jsonb_build_object('control_id',pg_temp.aid('ctl'),
  'control_code','P2P-3WM','title','Three-way match','owner_id',pg_temp.aid('owner'),'risk','high'),7,'stale')$$,
  '40001','ASSURANCE_VERSION_CONFLICT','stale expected version rejected');

-- Tenant / entity / branch isolation.
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select api.assurance_engagement(pg_temp.aid('other'),pg_temp.aid('other.entity'),pg_temp.aid('other.branch'),pg_temp.aid('eng'))$$,
  'P0002','ASSURANCE_ENGAGEMENT_NOT_FOUND','other tenant cannot discover engagement');
select throws_ok($$select api.assurance_engagement(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('eng'))$$,
  '42501',null,'foreign actor denied in tenant');
reset role;select pg_temp.actor('manager');set local role authenticated;
select throws_ok($$select api.assurance_engagement(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch2'),pg_temp.aid('eng'))$$,
  'P0002','ASSURANCE_ENGAGEMENT_NOT_FOUND','other branch cannot broaden reads');
select throws_ok($$select api.assurance_engagement(pg_temp.aid('tenant'),pg_temp.aid('other.entity'),null,pg_temp.aid('eng'))$$,
  'P0002','ASSURANCE_SCOPE_NOT_FOUND','foreign entity scope rejected');

-- Team, independence and control mapping.
select pg_temp.cmd(pg_temp.e('add_team_member')||jsonb_build_object('user_id',pg_temp.aid('auditor'),'role','auditor'),pg_temp.ver(),'team.auditor');
select pg_temp.cmd(pg_temp.e('add_team_member')||jsonb_build_object('user_id',pg_temp.aid('reviewer'),'role','reviewer'),pg_temp.ver(),'team.reviewer');
select throws_ok($$select pg_temp.cmd(pg_temp.e('add_team_member')||jsonb_build_object('user_id',pg_temp.aid('external'),'role','external'),pg_temp.ver(),'ext.noexp')$$,
  '22023','ASSURANCE_EXTERNAL_EXPIRY_REQUIRED','external access must be time-bound');
select throws_ok($$select pg_temp.cmd(pg_temp.e('add_team_member')||jsonb_build_object('user_id',pg_temp.aid('external'),'role','external',
  'expires_at',(now()+interval '120 days')::text),pg_temp.ver(),'ext.long')$$,'22023','ASSURANCE_EXTERNAL_EXPIRY_REQUIRED','external access bounded to 90 days');
select pg_temp.cmd(pg_temp.e('add_team_member')||jsonb_build_object('user_id',pg_temp.aid('external'),'role','external',
  'expires_at',(now()+interval '30 days')::text),pg_temp.ver(),'team.external');
select throws_ok($$select pg_temp.cmd(pg_temp.e('map_control')||jsonb_build_object('control_id',pg_temp.aid('ctl.bad'),
  'control_code','P2P-BAD','title','Auditor owned','owner_id',pg_temp.aid('auditor'),'risk','high'),pg_temp.ver(),'ctl.bad')$$,
  '42501','ASSURANCE_INDEPENDENCE_REQUIRED','audit team member cannot own an in-scope control');
select pg_temp.cmd(pg_temp.e('map_control')||jsonb_build_object('control_id',pg_temp.aid('ctl'),
  'control_code','P2P-3WM','title','Three-way match','owner_id',pg_temp.aid('owner'),'risk','high'),pg_temp.ver(),'ctl');
select throws_ok($$select pg_temp.cmd(pg_temp.e('add_team_member')||jsonb_build_object('user_id',pg_temp.aid('owner'),'role','auditor'),pg_temp.ver(),'team.owner')$$,
  '42501','ASSURANCE_INDEPENDENCE_REQUIRED','control owner cannot join the audit team');
select throws_ok($$select pg_temp.cmd(pg_temp.e('transition')||'{"to_status":"issued","reason":"skip ahead"}',pg_temp.ver(),'skip')$$,
  '55000','ASSURANCE_TRANSITION_INVALID','explicit transitions only; no jump to issued');

-- Evidence/PBC lifecycle.
reset role;select pg_temp.actor('lead');set local role authenticated;
select pg_temp.cmd(pg_temp.e('request_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'control_id',pg_temp.aid('ctl'),
  'owner_id',pg_temp.aid('owner'),'due_date',(current_date+7)::text,'description','Three-way match exception report Q1'),pg_temp.ver(),'req');
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.cmd(pg_temp.e('transition')||'{"to_status":"fieldwork","reason":"Planning approved"}',pg_temp.ver(),'to.fieldwork');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('submit_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'evidence_id',pg_temp.aid('ev1'),
  'source_module','procurement','source_reference','three_way_match.v1','source_as_of',now()::text,'collection_method','system',
  'query_version','p2p.3wm.1','sha256',pg_temp.hex('ev1'),'byte_size',2048,
  'storage_ref','assurance/'||pg_temp.aid('tenant')||'/'||pg_temp.aid('eng')||'/'||pg_temp.aid('ev1'),'classification','confidential'),pg_temp.ver(),'ev.notowner')$$,
  '42501','ASSURANCE_REQUEST_OWNER_REQUIRED','only the assigned owner submits');
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('submit_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'evidence_id',pg_temp.aid('ev1'),
  'source_module','procurement','source_reference','three_way_match.v1','source_as_of',now()::text,'collection_method','system',
  'query_version','p2p.3wm.1','sha256','NOT-A-DIGEST','byte_size',2048,
  'storage_ref','assurance/'||pg_temp.aid('tenant')||'/'||pg_temp.aid('eng')||'/'||pg_temp.aid('ev1'),'classification','confidential'),pg_temp.ver(),'ev.baddigest')$$,
  '22023','ASSURANCE_DIGEST_INVALID','digest must be lowercase SHA-256');
select throws_ok($$select pg_temp.cmd(pg_temp.e('submit_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'evidence_id',pg_temp.aid('ev1'),
  'source_module','procurement','source_reference','three_way_match.v1','source_as_of',now()::text,'collection_method','system',
  'query_version','p2p.3wm.1','sha256',pg_temp.hex('ev1'),'byte_size',2048,'storage_ref','public/anything','classification','confidential'),pg_temp.ver(),'ev.path')$$,
  '22023','ASSURANCE_STORAGE_REF_INVALID','storage reference is generated from scope, not client-chosen');
select pg_temp.cmd(pg_temp.e('submit_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'evidence_id',pg_temp.aid('ev1'),
  'source_module','procurement','source_reference','three_way_match.v1','source_as_of',now()::text,'collection_method','system',
  'query_version','p2p.3wm.1','sha256',pg_temp.hex('ev1'),'byte_size',2048,
  'storage_ref','assurance/'||pg_temp.aid('tenant')||'/'||pg_temp.aid('eng')||'/'||pg_temp.aid('ev1'),'classification','confidential'),pg_temp.ver(),'ev1');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.cmd(pg_temp.e('review_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'decision','reject','reason','Missing April data'),pg_temp.ver(),'rev.reject');
reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.cmd(pg_temp.e('submit_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'evidence_id',pg_temp.aid('ev2'),
  'source_module','procurement','source_reference','three_way_match.v1','source_as_of',now()::text,'collection_method','system',
  'query_version','p2p.3wm.1','sha256',pg_temp.hex('ev2'),'byte_size',4096,
  'storage_ref','assurance/'||pg_temp.aid('tenant')||'/'||pg_temp.aid('eng')||'/'||pg_temp.aid('ev2'),'classification','confidential'),pg_temp.ver(),'ev2');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.cmd(pg_temp.e('review_evidence')||jsonb_build_object('request_id',pg_temp.aid('req'),'decision','accept','reason','Complete'),pg_temp.ver(),'rev.accept');
reset role;
select is((select rework_count from assurance.evidence_requests where id=pg_temp.aid('req')),1,'rework is measured, not lost');
select is((select count(*)::integer from assurance.evidence_items where request_id=pg_temp.aid('req')),2,'both submissions retained with provenance');
select throws_ok($$update assurance.evidence_items set sha256=repeat('0',64) where id=pg_temp.aid('ev1')$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','evidence provenance immutable');
select throws_ok($$delete from assurance.evidence_items where id=pg_temp.aid('ev1')$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','evidence cannot be deleted');

-- Freeze requires recent MFA and the lead auditor.
select pg_temp.actor('lead',false);set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('freeze_evidence')||'{"reason":"Fieldwork cutoff"}',pg_temp.ver(),'freeze.nomfa')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','freeze requires MFA');
reset role;select pg_temp.actor('lead',true,3600);set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('freeze_evidence')||'{"reason":"Fieldwork cutoff"}',pg_temp.ver(),'freeze.stale')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','stale MFA (older than 15 minutes) rejected');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('freeze_evidence')||'{"reason":"Fieldwork cutoff"}',pg_temp.ver(),'freeze.notlead')$$,
  '42501',null,'non-lead cannot freeze');
reset role;select pg_temp.actor('lead');set local role authenticated;
insert into assurance_samples values('freeze',pg_temp.cmd(pg_temp.e('freeze_evidence')||'{"reason":"Fieldwork cutoff"}',pg_temp.ver(),'freeze'));
reset role;
select is((select evidence_cutoff_digest from assurance.engagements where id=pg_temp.aid('eng')),
  encode(extensions.digest(pg_temp.aid('ev2')::text||':'||pg_temp.hex('ev2')||':4096','sha256'),'hex'),'cutoff digest binds accepted evidence identity, digest and size');
select throws_ok($$update assurance.engagements set evidence_cutoff_digest=repeat('1',64) where id=pg_temp.aid('eng')$$,
  '55000','ASSURANCE_HISTORY_IMMUTABLE','frozen cutoff cannot be rewritten');

-- Exceptions are not findings; findings require an independent issuer.
select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.cmd(pg_temp.e('record_exception')||jsonb_build_object('exception_id',pg_temp.aid('exc'),'control_id',pg_temp.aid('ctl'),
  'description','12 invoices paid without matched receipt','severity','high'),pg_temp.ver(),'exc');
reset role;
select is((select count(*)::integer from assurance.findings where engagement_id=pg_temp.aid('eng')),0,'exception does not auto-create a finding');
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('issue_finding')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'exception_id',pg_temp.aid('exc'),
  'title','Unmatched supplier payments','severity','high','owner_id',pg_temp.aid('owner')),pg_temp.ver(),'fin.self')$$,
  '42501','ASSURANCE_INDEPENDENT_REVIEW_REQUIRED','recorder cannot issue own exception as a finding');
reset role;select pg_temp.actor('reviewer',false);set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('issue_finding')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'exception_id',pg_temp.aid('exc'),
  'title','Unmatched supplier payments','severity','high','owner_id',pg_temp.aid('owner')),pg_temp.ver(),'fin.nomfa')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','finding issuance requires MFA');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.cmd(pg_temp.e('issue_finding')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'exception_id',pg_temp.aid('exc'),
  'title','Unmatched supplier payments','severity','high','owner_id',pg_temp.aid('owner')),pg_temp.ver(),'fin');

-- Management response, remediation and independent retest.
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('respond')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'response','We agree',
  'due_date',(current_date+30)::text,'accept_risk',false),pg_temp.ver(),'resp.notowner')$$,'42501',null,'only the finding owner responds');
reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.cmd(pg_temp.e('respond')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'response','Block payment without GRN match',
  'due_date',(current_date+30)::text,'accept_risk',false),pg_temp.ver(),'resp');
select pg_temp.cmd(pg_temp.e('submit_remediation')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'evidence_sha256',pg_temp.hex('fix'),
  'note','Hard block configured'),pg_temp.ver(),'remed');
select throws_ok($$select pg_temp.cmd(pg_temp.e('retest')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'retest_id',pg_temp.aid('rt0'),
  'result','pass','evidence_sha256',pg_temp.hex('rt0'),'note','Self check'),pg_temp.ver(),'rt.self')$$,'42501',null,'control owner cannot retest');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.cmd(pg_temp.e('retest')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'retest_id',pg_temp.aid('rt1'),
  'result','fail','evidence_sha256',pg_temp.hex('rt1'),'note','Block bypassable by admin'),pg_temp.ver(),'rt1');
reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.cmd(pg_temp.e('submit_remediation')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'evidence_sha256',pg_temp.hex('fix2'),
  'note','Admin bypass removed'),pg_temp.ver(),'remed2');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.cmd(pg_temp.e('retest')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'retest_id',pg_temp.aid('rt2'),
  'result','pass','evidence_sha256',pg_temp.hex('rt2'),'note','Sample of 25 all blocked'),pg_temp.ver(),'rt2');
reset role;
select is((select status from assurance.findings where id=pg_temp.aid('fin')),'closed','passing independent retest closes');
select is((select count(*)::integer from assurance.retests where finding_id=pg_temp.aid('fin')),2,'failed and passed retests both retained');
select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.cmd(pg_temp.e('reopen_finding')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'reason','Recurrence detected'),pg_temp.ver(),'reopen');
reset role;select pg_temp.actor('owner');set local role authenticated;
select pg_temp.cmd(pg_temp.e('submit_remediation')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'evidence_sha256',pg_temp.hex('fix3'),
  'note','Monitoring added'),pg_temp.ver(),'remed3');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.cmd(pg_temp.e('retest')||jsonb_build_object('finding_id',pg_temp.aid('fin'),'retest_id',pg_temp.aid('rt3'),
  'result','pass','evidence_sha256',pg_temp.hex('rt3'),'note','Recurrence resolved'),pg_temp.ver(),'rt3');

-- External auditor: read-only, time-bound, metadata only.
reset role;select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('map_control')||jsonb_build_object('control_id',pg_temp.aid('ctl.x'),
  'control_code','EXT-1','title','External control','owner_id',pg_temp.aid('owner'),'risk','low'),pg_temp.ver(),'ext.write')$$,
  '42501','ASSURANCE_EXTERNAL_READ_ONLY','external reviewer cannot write even with a broad role');
insert into assurance_samples values('external_read',api.assurance_engagement(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('eng')));
reset role;
select ok((select body->'requests'->0->'evidence'->>'storage_ref' is null and body->'requests'->0->'evidence'->>'sha256'=pg_temp.hex('ev2')
  from assurance_samples where label='external_read'),'external sees digest but not storage reference');
update assurance.engagement_team set expires_at=now()-interval '1 second' where engagement_id=pg_temp.aid('eng') and user_id=pg_temp.aid('external');
select pg_temp.actor('external');set local role authenticated;
select throws_ok($$select api.assurance_engagement(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('eng'))$$,
  '42501','ASSURANCE_EXTERNAL_ACCESS_EXPIRED','expired external access denied immediately');

-- Report issuance, reopening and immutability.
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.cmd(pg_temp.e('transition')||'{"to_status":"reporting","reason":"Fieldwork complete"}',pg_temp.ver(),'to.reporting');
reset role;select pg_temp.actor('lead');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('issue_report')||jsonb_build_object('report_id',pg_temp.aid('rep1'),'summary','One high finding, closed'),pg_temp.ver(),'rep.lead')$$,
  '42501','ASSURANCE_INDEPENDENT_ISSUER_REQUIRED','lead auditor cannot issue own report');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
insert into assurance_samples values('report1',pg_temp.cmd(pg_temp.e('issue_report')||jsonb_build_object('report_id',pg_temp.aid('rep1'),'summary','One high finding, closed'),pg_temp.ver(),'rep1'));
select pg_temp.cmd(pg_temp.e('reopen_report')||'{"reason":"Management letter correction"}',pg_temp.ver(),'rep.reopen');
select pg_temp.cmd(pg_temp.e('issue_report')||jsonb_build_object('report_id',pg_temp.aid('rep2'),'summary','One high finding, closed; corrected'),pg_temp.ver(),'rep2');
reset role;
select is((select array_agg(report_version order by report_version) from assurance.report_versions where engagement_id=pg_temp.aid('eng')),array[1,2],'reissue creates a new version; original preserved');
select throws_ok($$update assurance.report_versions set summary='rewritten' where id=pg_temp.aid('rep1')$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','issued report immutable');
select throws_ok($$delete from assurance.events where engagement_id=pg_temp.aid('eng')$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','event history immutable');
select throws_ok($$delete from assurance.findings where id=pg_temp.aid('fin')$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','findings never deleted');

-- Legal holds with segregated release.
select pg_temp.actor('manager');set local role authenticated;
select pg_temp.cmd(pg_temp.e('place_hold')||jsonb_build_object('hold_id',pg_temp.aid('hold'),'reason','Regulator inquiry'),pg_temp.ver(),'hold');
select throws_ok($$select pg_temp.cmd(pg_temp.e('release_hold')||jsonb_build_object('hold_id',pg_temp.aid('hold'),'reason','Inquiry closed'),pg_temp.ver(),'hold.self')$$,
  '42501','ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED','placer cannot release own hold');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.cmd(pg_temp.e('release_hold')||jsonb_build_object('hold_id',pg_temp.aid('hold'),'reason','Inquiry closed'),pg_temp.ver(),'hold.release');

-- Revocation removes access immediately (and hides replay) without deleting history.
reset role;
delete from core.role_permissions where tenant_id=pg_temp.aid('tenant') and role_id=pg_temp.aid('reviewer.r') and permission_code='assurance.engagement.close';
select pg_temp.actor('reviewer');set local role authenticated;
select throws_ok($$select pg_temp.cmd(pg_temp.e('issue_report')||jsonb_build_object('report_id',pg_temp.aid('rep1'),'summary','One high finding, closed'),2147483647,'rep1')$$,
  '42501','Permission denied or multi-factor authentication required.','revoked capability cannot replay a sealed receipt');
reset role;
select ok((select count(*)>0 from assurance.events where actor_id=pg_temp.aid('reviewer')),'revocation preserves attributed history');

-- Every committed command produced exactly one ordered event.
select is((select count(*)::integer from assurance.events where engagement_id=pg_temp.aid('eng')),
  (select version::integer from assurance.engagements where id=pg_temp.aid('eng')),'one event per engagement version');
select ok((select bool_and(actor_id is not null) from assurance.events where engagement_id=pg_temp.aid('eng')),'all events attributable');
