-- Corporate Audit & Assurance A4b candidate tests (blueprint 68).
-- Included only by build_assurance_candidate.ps1 -Slice A4b, after the A1/A2/A4 tests and the
-- A4b candidate DDL, inside the same begin ... rollback block. Reuses earlier fixtures.
-- Synthetic module rows below never commit. people.attendance_entries rows point at a
-- revision id that does not exist; that FK is DEFERRABLE INITIALLY DEFERRED and is never
-- checked because the transaction rolls back. The adapter reads only entry status/actors.
create function pg_temp.collect5(req text,ev text,kind text,src text) returns jsonb language sql as $$
  select pg_temp.e2('collect_system_evidence','eng5')||jsonb_build_object('request_id',pg_temp.aid(req),'evidence_id',pg_temp.aid(ev),
    'source_kind',kind,'source_id',case when src is null then null else pg_temp.aid(src) end) $$;
create function pg_temp.monitor(ev text) returns jsonb language sql as $$
  select pg_temp.e2('run_monitoring','eng5')||jsonb_build_object('evidence_id',pg_temp.aid(ev),'control_id',pg_temp.aid('ctl5')) $$;

reset role;
-- Entity-wide module authority for the auditor (branch null), as finance close
-- review and inventory valuation require. procurement.bills.view is granted later.
insert into core.roles(id,tenant_id,code,name,requires_mfa)
values(pg_temp.aid('auditor.ent'),pg_temp.aid('tenant'),'assurance-auditor-entity','auditor entity',false);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.aid('tenant'),pg_temp.aid('auditor.ent'),p from unnest(array['finance.view','finance.controls.reconcile',
  'inventory.stock.view','inventory.cost.view','procurement.view','people.view','people.attendance.view']) p;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.aid('tenant'),pg_temp.aid('auditor.m'),pg_temp.aid('auditor.ent'),pg_temp.aid('tenant.entity'),null,pg_temp.aid('manager'));

-- Authoritative module report rows (immutable sources).
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,state,status,created_by,updated_by)
values(pg_temp.aid('fp1'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),'FY27 H1 A4b','2026-04-01','2026-09-30','open','active',pg_temp.aid('manager'),pg_temp.aid('manager'));
insert into finance.financial_reports(id,tenant_id,legal_entity_id,requested_branch_id,kind,period_id,as_of,generated_at,summary,evidence,created_by)
values(pg_temp.aid('fs1'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),'trial_balance',pg_temp.aid('fp1'),
  '2026-09-30',now(),'{"balanced":true}','{"lines":[]}',pg_temp.aid('manager'));
insert into finance.tax_reports(id,tenant_id,legal_entity_id,requested_branch_id,period_id,as_of,generated_at,summary,evidence,created_by)
values(pg_temp.aid('tx1'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('fp1'),
  '2026-09-30',now(),'{"output_tax":"0.00"}','{"lines":[]}',pg_temp.aid('manager'));
insert into finance.close_control_reviews(id,tenant_id,legal_entity_id,branch_id,period_id,as_of,generated_at,summary,evidence,created_by)
values(pg_temp.aid('cl1'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('fp1'),
  '2026-09-30',now(),'{"ready":true}','{"components":[]}',pg_temp.aid('manager'));
insert into inventory.valuation_reports(id,tenant_id,legal_entity_id,branch_id,as_of,generated_at,summary,evidence,created_by)
values(pg_temp.aid('vr1'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
  '2026-09-30',now(),'{"difference":"0.00"}','{"items":[]}',pg_temp.aid('manager'));

-- Procurement: two posted bills in period (one overridden by its own creator),
-- one draft in period and one posted bill outside the period (both excluded).
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
values(pg_temp.aid('supplier'),pg_temp.aid('tenant'),'SUPA4B','Synthetic Supplier A4b','Synthetic Supplier','supplier',pg_temp.aid('manager'),pg_temp.aid('manager'));
insert into procurement.supplier_bills(id,tenant_id,legal_entity_id,branch_id,supplier_id,supplier_reference,document_date,due_date,
  currency_code,base_currency_code,exchange_rate,subtotal,tax_total,total,base_total,status,match_result,created_by,updated_by)
select pg_temp.aid(b),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('supplier'),'INV-'||b,d,d+30,
  'LKR','LKR',1,amt,0,amt,amt,st,'{}'::jsonb,pg_temp.aid('owner'),pg_temp.aid('owner')
from (values ('bill1','2026-06-01'::date,100::numeric,'posted'),('bill2','2026-07-01',250,'posted'),
             ('bill3','2026-07-15',75,'draft'),('bill4','2025-12-01',999,'posted')) v(b,d,amt,st);
insert into procurement.supplier_bill_match_approvals(tenant_id,legal_entity_id,branch_id,bill_id,bill_version,match_hash,control_version,reason,approved_by)
values(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('bill2'),1,'h-bill2',1,'Price variance accepted',pg_temp.aid('owner')),
      (pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('bill4'),1,'h-bill4',1,'Old period override',pg_temp.aid('manager'));

-- Workforce: one independently approved entry, one self-approved, one awaiting decision.
insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by)
values(pg_temp.aid('emp1'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),'EMPA4B','Synthetic Employee A4b',pg_temp.aid('manager'),pg_temp.aid('manager'));
insert into people.attendance_entries(id,tenant_id,legal_entity_id,branch_id,employee_id,current_revision_id,status,submitted_by,decided_by,created_by)
values(pg_temp.aid('att1'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('emp1'),pg_temp.aid('att1.rev'),'approved',pg_temp.aid('owner'),pg_temp.aid('manager'),pg_temp.aid('owner')),
      (pg_temp.aid('att2'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('emp1'),pg_temp.aid('att2.rev'),'approved',pg_temp.aid('owner'),pg_temp.aid('owner'),pg_temp.aid('owner')),
      (pg_temp.aid('att3'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('emp1'),pg_temp.aid('att3.rev'),'submitted',pg_temp.aid('owner'),null,pg_temp.aid('owner'));

select ok((select count(*)=17 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class c
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='assurance' and c.relkind='r'),'A4b: all 17 assurance tables force RLS');
select ok(not has_function_privilege('authenticated','assurance.snapshot_document(text,uuid,uuid,uuid,date,date)','EXECUTE')
  and not has_table_privilege('authenticated','assurance.monitoring_hits','SELECT'),'A4b: snapshot builder and hits are not client-reachable');

select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('create_engagement','eng5')||jsonb_build_object('name','FY27 Integrated controls','period_start','2026-04-01',
  'period_end','2027-03-31','scope_summary','Finance, inventory, procurement, workforce and access controls','lead_auditor_id',pg_temp.aid('lead')),0,'eng5');
select pg_temp.c2(pg_temp.e2('add_team_member','eng5')||jsonb_build_object('user_id',pg_temp.aid('auditor'),'role','auditor'),pg_temp.vv('eng5'),'eng5.aud');
select pg_temp.c2(pg_temp.e2('add_team_member','eng5')||jsonb_build_object('user_id',pg_temp.aid('reviewer'),'role','reviewer'),pg_temp.vv('eng5'),'eng5.rev');
select pg_temp.c2(pg_temp.e2('map_control','eng5')||jsonb_build_object('control_id',pg_temp.aid('ctl5'),'control_code','INT-CTRL',
  'title','Integrated control environment','owner_id',pg_temp.aid('owner'),'risk','high'),pg_temp.vv('eng5'),'ctl5');
reset role;select pg_temp.actor('lead');set local role authenticated;
create function pg_temp.req5(k text) returns jsonb language sql as $$
  select pg_temp.c2(pg_temp.e2('request_evidence','eng5')||jsonb_build_object('request_id',pg_temp.aid('r5.'||k),'control_id',pg_temp.aid('ctl5'),
    'owner_id',pg_temp.aid('owner'),'due_date',(current_date+5)::text,'description','System evidence '||k),pg_temp.vv('eng5'),'r5.'||k) $$;
select pg_temp.req5('fs');
select pg_temp.req5('tx');
select pg_temp.req5('cl');
select pg_temp.req5('vr');
select pg_temp.req5('p2p');
select pg_temp.req5('hr');
select pg_temp.req5('acc');
reset role;select pg_temp.actor('manager');set local role authenticated;
select pg_temp.c2(pg_temp.e2('transition','eng5')||'{"to_status":"fieldwork","reason":"Plan approved"}',pg_temp.vv('eng5'),'eng5.fw');

-- The four previously unexercised report kinds, under entity-wide module authority.
reset role;select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.ec(pg_temp.collect5('r5.fs','ev5.fs','finance.financial_statement','fs1'),pg_temp.vv('eng5'),'ev5.fs');
select pg_temp.ec(pg_temp.collect5('r5.tx','ev5.tx','finance.tax_summary','tx1'),pg_temp.vv('eng5'),'ev5.tx');
select pg_temp.ec(pg_temp.collect5('r5.cl','ev5.cl','finance.close_review','cl1'),pg_temp.vv('eng5'),'ev5.cl');
select pg_temp.ec(pg_temp.collect5('r5.vr','ev5.vr','inventory.valuation','vr1'),pg_temp.vv('eng5'),'ev5.vr');
reset role;
select is((select count(*)::integer from assurance.evidence_items i where i.id in (pg_temp.aid('ev5.fs'),pg_temp.aid('ev5.tx'),pg_temp.aid('ev5.cl'),pg_temp.aid('ev5.vr'))
  and i.sha256 = case i.id
    when pg_temp.aid('ev5.fs') then (select encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') from finance.financial_reports r where r.id=pg_temp.aid('fs1'))
    when pg_temp.aid('ev5.tx') then (select encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') from finance.tax_reports r where r.id=pg_temp.aid('tx1'))
    when pg_temp.aid('ev5.cl') then (select encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') from finance.close_control_reviews r where r.id=pg_temp.aid('cl1'))
    else (select encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex') from inventory.valuation_reports r where r.id=pg_temp.aid('vr1')) end),
  4,'financial statement, tax summary, close review and valuation digests bind their source rows');
select is((select string_agg(source_module||':'||query_version,',' order by query_version) from assurance.evidence_items
  where id in (pg_temp.aid('ev5.fs'),pg_temp.aid('ev5.tx'),pg_temp.aid('ev5.cl'),pg_temp.aid('ev5.vr'))),
  'finance:fin.close_control_reviews.v1,finance:fin.financial_reports.v1,finance:fin.tax_reports.v1,inventory:inv.valuation_reports.v1',
  'each kind records its owning module and query version');
delete from core.role_assignments where tenant_id=pg_temp.aid('tenant') and role_id=pg_temp.aid('auditor.ent');
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select api.assurance_verify_evidence(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid('ev5.cl'))$$,
  '42501',null,'close review re-verification needs current entity-wide finance authority');
reset role;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.aid('tenant'),pg_temp.aid('auditor.m'),pg_temp.aid('auditor.ent'),pg_temp.aid('tenant.entity'),null,pg_temp.aid('manager'));
select pg_temp.actor('auditor');set local role authenticated;
insert into assurance_samples values('verify5',(select jsonb_agg(api.assurance_verify_evidence(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),pg_temp.aid(k)))
  from unnest(array['ev5.fs','ev5.tx','ev5.cl','ev5.vr']) k));
reset role;
select ok((select bool_and((x->>'matches')::boolean) and count(*)=4 from assurance_samples s, jsonb_array_elements(s.body) x where s.label='verify5'),
  'all four report kinds re-verify against their sources');

-- Procurement and workforce adapters keep their modules' own authority.
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.collect5('r5.p2p','ev5.p2p','procurement.three_way_match',null),pg_temp.vv('eng5'),'p2p.noperm')$$,
  '42501',null,'procurement evidence needs procurement.bills.view');
select throws_ok($$select pg_temp.ec(pg_temp.collect5('r5.hr','ev5.hr','workforce.attendance_approvals',null),pg_temp.vv('eng5'),'hr.noplan')$$,
  '42501','PEOPLE_ENTITLEMENT_REQUIRED','workforce evidence honours the People module entitlement');
select throws_ok($$select pg_temp.ec(pg_temp.collect5('r5.p2p','ev5.p2p','procurement.three_way_match','bill1'),pg_temp.vv('eng5'),'p2p.src')$$,
  '22023','ASSURANCE_UNEXPECTED_FIELD','period snapshots take no source id');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.aid('tenant'),pg_temp.aid('auditor.ent'),'procurement.bills.view');
with u as (update billing.tenant_subscriptions set plan_code='w4_employee_synthetic',status='trialing',trial_ends_at=now()+interval '30 days'
  where tenant_id=pg_temp.aid('tenant') returning 1)
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
select pg_temp.aid('tenant'),'w4_employee_synthetic','trialing',5,now()+interval '30 days' where not exists(select 1 from u);
select pg_temp.actor('auditor');set local role authenticated;
select pg_temp.ec(pg_temp.collect5('r5.p2p','ev5.p2p','procurement.three_way_match',null),pg_temp.vv('eng5'),'ev5.p2p');
select pg_temp.ec(pg_temp.collect5('r5.hr','ev5.hr','workforce.attendance_approvals',null),pg_temp.vv('eng5'),'ev5.hr');
select pg_temp.ec(pg_temp.collect5('r5.acc','ev5.acc','it_control.access_review',null),pg_temp.vv('eng5'),'ev5.acc');
reset role;
select ok((select (content->>'posted_bills')::integer=2 and (content->>'posted_base_total')::numeric=350
  and (content->>'bills_with_match_override')::integer=1 and (content->>'overrides_by_bill_creator')::integer=1
  and content->'overrides'->0->>'bill_id'=pg_temp.aid('bill2')::text
  from assurance.system_snapshots where id=pg_temp.aid('ev5.p2p')),'three-way-match snapshot counts posted in-period bills and creator overrides only');
select ok((select content::text not like '%'||pg_temp.aid('supplier')::text||'%' and content::text not like '%SUPA4B%' and content::text not like '%Synthetic Supplier%'
  from assurance.system_snapshots where id=pg_temp.aid('ev5.p2p')),'procurement snapshot carries no supplier identity');
select ok((select (content->>'entries')::integer=3 and (content->>'self_decided')::integer=1 and (content->>'awaiting_decision')::integer=1
  and (content->'by_status'->>'approved')::integer=2
  from assurance.system_snapshots where id=pg_temp.aid('ev5.hr')),'attendance snapshot counts statuses and self-decisions');
select ok((select content::text not like '%'||pg_temp.aid('emp1')::text||'%' and content::text not like '%EMPA4B%'
  and content::text not like '%'||pg_temp.aid('owner')::text||'%' and classification='restricted'
  from assurance.system_snapshots s join assurance.evidence_items i on i.id=s.id where s.id=pg_temp.aid('ev5.hr')),
  'workforce snapshot is restricted and carries no employee or actor identity');

-- Continuous monitoring creates reviewable candidates only.
select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.monitor('ev5.p2p'),pg_temp.vv('eng5'),'mon.owner')$$,'42501',null,'control owner cannot run monitoring');
reset role;select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.ec(pg_temp.monitor('ev5.fs'),pg_temp.vv('eng5'),'mon.report')$$,
  '55000','ASSURANCE_MONITORING_SOURCE_INVALID','monitoring rules run on system snapshots only');
insert into assurance_samples values('mon.p2p',pg_temp.ec(pg_temp.monitor('ev5.p2p'),pg_temp.vv('eng5'),'mon.p2p'));
select pg_temp.ec(pg_temp.monitor('ev5.hr'),pg_temp.vv('eng5'),'mon.hr');
select pg_temp.ec(pg_temp.monitor('ev5.acc'),pg_temp.vv('eng5'),'mon.acc');
select pg_temp.ec(pg_temp.monitor('ev5.p2p'),pg_temp.vv('eng5'),'mon.p2p.again');
reset role;
select is((select string_agg(rule_code,',' order by rule_code) from assurance.monitoring_hits where engagement_id=pg_temp.aid('eng5')),
  'ACCESS_PRIVILEGED_NO_MFA,HR_ATTENDANCE_SELF_APPROVAL,P2P_MATCH_OVERRIDE,P2P_OVERRIDE_BY_CREATOR',
  'each triggered rule recorded once; re-running adds nothing');
select ok((select count(*)=4 and bool_and(status='candidate' and source='continuous_monitoring' and recorded_by=pg_temp.aid('auditor'))
  from assurance.exceptions where engagement_id=pg_temp.aid('eng5')),'monitoring creates candidate exceptions only');
select is((select count(*)::integer from assurance.findings where engagement_id=pg_temp.aid('eng5')),0,'monitoring never issues findings');
select ok((select description not like '%'||pg_temp.aid('owner')::text||'%' and severity='high'
  from assurance.exceptions x join assurance.monitoring_hits h on h.exception_id=x.id where h.rule_code='HR_ATTENDANCE_SELF_APPROVAL'),
  'candidate descriptions carry counts, not identities');
create temporary table assurance_ids as select rule_code,exception_id id from assurance.monitoring_hits where engagement_id=pg_temp.aid('eng5');
grant select on assurance_ids to authenticated;
select pg_temp.actor('auditor');set local role authenticated;
select throws_ok($$select pg_temp.c2(pg_temp.e2('issue_finding','eng5')||jsonb_build_object('finding_id',pg_temp.aid('f5'),
  'exception_id',(select id from assurance_ids where rule_code='P2P_OVERRIDE_BY_CREATOR'),
  'title','Bill creator approved own override','severity','high','owner_id',pg_temp.aid('owner')),pg_temp.vv('eng5'),'f5.self')$$,
  '42501','ASSURANCE_INDEPENDENT_REVIEW_REQUIRED','monitoring runner cannot promote its own candidate');
reset role;select pg_temp.actor('reviewer');set local role authenticated;
select pg_temp.c2(pg_temp.e2('dismiss_exception','eng5')||jsonb_build_object('exception_id',(select id from assurance_ids where rule_code='P2P_MATCH_OVERRIDE'),
  'reason','Overrides reviewed; within tolerance'),pg_temp.vv('eng5'),'dis5');
reset role;
select is((select status from assurance.exceptions where id=(select id from assurance_ids where rule_code='P2P_MATCH_OVERRIDE')),'dismissed','an independent reviewer can dismiss a candidate');
select throws_ok($$delete from assurance.monitoring_hits where engagement_id=pg_temp.aid('eng5')$$,'55000','ASSURANCE_HISTORY_IMMUTABLE','monitoring hits immutable');
select ok((select (body->>'action')='run_monitoring' from assurance_samples where label='mon.p2p'),'monitoring run is a governed, receipted command');
select is((select count(*)::integer from assurance.events where engagement_id=pg_temp.aid('eng5')),
  (select version::integer from assurance.engagements where id=pg_temp.aid('eng5')),'A4b: one event per engagement version');
