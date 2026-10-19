-- Corporate Audit & Assurance A8 access candidate tests.
-- Included only by build_assurance_candidate.ps1 -Slice A8, after the A8
-- candidate DDL. Uses the A1 actors, tenants, memberships and roles.
create function pg_temp.acc(p_after uuid default null, p_branch text default 'tenant.branch') returns jsonb
language sql as $$
  select api.assurance_access(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid(p_branch),p_after) $$;
create function pg_temp.setrole(p jsonb, v bigint, k text) returns jsonb language sql as $$
  select api.assurance_set_role(pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
    pg_temp.aid('key.'||k),p,v) $$;
create function pg_temp.grant8(p_member text, p_role text, p_scope text, p_granted boolean default true)
returns jsonb language sql immutable as $$
  select jsonb_build_object('membership_id',pg_temp.aid(p_member||'.m'),'role_code',p_role,
    'granted',p_granted,'scope',p_scope) $$;

-- A tenant owner role that predates the access candidate (tenant-wide role manager).
insert into core.roles(id,tenant_id,code,name,requires_mfa,is_system)
values(pg_temp.aid('tenant.owner.r'),pg_temp.aid('tenant'),'tenant_owner','Tenant owner',true,true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.aid('tenant'),pg_temp.aid('tenant.owner.r'),'core.roles.manage');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.aid('tenant'),pg_temp.aid('manager.m'),pg_temp.aid('tenant.owner.r'),null,null,pg_temp.aid('manager'));
select assurance.seed_roles(pg_temp.aid('tenant'));
-- A branch-scoped role manager is not a tenant role manager.
insert into core.roles(id,tenant_id,code,name,requires_mfa)
values(pg_temp.aid('branchadmin.r'),pg_temp.aid('tenant'),'assurance-branchadmin','branchadmin',false);
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.aid('tenant'),pg_temp.aid('branchadmin.r'),'core.roles.manage');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.aid('tenant'),pg_temp.aid('lead.m'),pg_temp.aid('branchadmin.r'),pg_temp.aid('tenant.entity'),
  pg_temp.aid('tenant.branch'),pg_temp.aid('manager'));
-- The process owner is linked to an employee record; everyone else is unlinked.
insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by)
values(pg_temp.aid('owner.emp'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),'A8OWN','Nadeesha Perera',
  pg_temp.aid('manager'),pg_temp.aid('manager'));
insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,
  status,initiated_by,accepted_at)
values(pg_temp.aid('owner.link'),pg_temp.aid('tenant'),pg_temp.aid('tenant.entity'),pg_temp.aid('tenant.branch'),
  pg_temp.aid('owner.emp'),pg_temp.aid('owner.m'),pg_temp.aid('owner'),'accepted',pg_temp.aid('manager'),now());

-- Structure: owner backfill, seeded roles, MFA on privileged roles, new-tenant trigger.
select ok((select count(*) from core.role_permissions where role_id=pg_temp.aid('tenant.owner.r')
  and permission_code like 'assurance.%')=(select count(*) from core.permissions where code like 'assurance.%')
  and (select count(*) from core.permissions where code like 'assurance.%')>=15,
  'existing tenant owners hold every assurance permission');
select is((select array_agg(code order by code) from core.roles where tenant_id=pg_temp.aid('tenant') and code like 'assurance\_%'),
  array['assurance_auditor','assurance_external','assurance_lead','assurance_process_owner','assurance_reviewer'],
  'five assurance roles are seeded');
select is((select count(*)::integer from core.roles where tenant_id=pg_temp.aid('other') and code like 'assurance\_%'),5,
  'roles are seeded in every existing tenant');
select is((select jsonb_object_agg(code,requires_mfa) from core.roles where tenant_id=pg_temp.aid('tenant') and code like 'assurance\_%'),
  '{"assurance_lead":true,"assurance_auditor":true,"assurance_reviewer":true,"assurance_process_owner":false,"assurance_external":false}'::jsonb,
  'lead, auditor and reviewer require MFA');
select is((select jsonb_object_agg(r.code,(select array_agg(rp.permission_code order by rp.permission_code)
    from core.role_permissions rp where rp.role_id=r.id))
  from core.roles r where r.tenant_id=pg_temp.aid('tenant') and r.code like 'assurance\_%'),
  jsonb_build_object(
   'assurance_lead',array['assurance.engagement.close','assurance.engagement.manage','assurance.evidence.request',
     'assurance.evidence.view','assurance.finding.issue','assurance.plan.manage','assurance.report.export',
     'assurance.retention.manage','assurance.test.perform','assurance.test.review'],
   'assurance_auditor',array['assurance.evidence.request','assurance.evidence.view','assurance.finding.issue','assurance.test.perform'],
   'assurance_reviewer',array['assurance.engagement.close','assurance.evidence.view','assurance.retest.perform','assurance.test.review'],
   'assurance_process_owner',array['assurance.evidence.submit','assurance.evidence.view','assurance.remediation.manage','assurance.response.manage'],
   'assurance_external',array['assurance.external_review']),
  'seeded role permissions match the role table');
select ok(not exists(select 1 from core.roles r join core.role_permissions rp on rp.role_id=r.id
  join core.permissions p on p.code=rp.permission_code
  where r.is_system and r.code in (select code from assurance.role_catalogue()) and p.privileged and not r.requires_mfa),
  'no seeded role grants a privileged permission without MFA');
insert into core.tenants(id,name,slug,status,created_by)
values(pg_temp.aid('newtenant'),'Assurance new','assurance-a8-new','active',pg_temp.aid('manager'));
select is((select count(*)::integer from core.roles where tenant_id=pg_temp.aid('newtenant') and code like 'assurance\_%'),5,
  'a new tenant receives the five assurance roles');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='assurance.access_events'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid='assurance.access_versions'::regclass),
  'access tables force RLS');
select ok(not has_function_privilege('anon','api.assurance_access(uuid,uuid,uuid,uuid)','EXECUTE')
  and has_function_privilege('authenticated','api.assurance_set_role(uuid,uuid,uuid,uuid,jsonb,bigint)','EXECUTE')
  and not has_function_privilege('authenticated','assurance.seed_roles(uuid)','EXECUTE'),
  'access APIs are authenticated-only and seeding is not client-callable');

-- Read authority and member labels.
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('acc.manager',pg_temp.acc());
reset role;select pg_temp.actor('lead');set local role authenticated;
insert into assurance_samples values('acc.lead',pg_temp.acc());
reset role;
select ok((select (body->>'can_manage')::boolean from assurance_samples where label='acc.manager'),
  'a tenant-wide role manager can manage access');
select ok(not (select (body->>'can_manage')::boolean from assurance_samples where label='acc.lead'),
  'a planner reads access without managing it');
select is((select jsonb_array_length(body->'roles') from assurance_samples where label='acc.manager'),5,
  'the five role definitions are returned');
select ok(not exists(select 1 from assurance_samples s, jsonb_array_elements(s.body->'members') m
  where s.label='acc.manager' and m->>'label' like '%@%'),'member labels never contain a login e-mail');
select is((select m->>'label' from assurance_samples s, jsonb_array_elements(s.body->'members') m
  where s.label='acc.manager' and m->>'membership_id'=pg_temp.aid('owner.m')::text),'Nadeesha Perera',
  'a linked member shows the employee name');
select is((select m->>'label' from assurance_samples s, jsonb_array_elements(s.body->'members') m
  where s.label='acc.manager' and m->>'membership_id'=pg_temp.aid('auditor.m')::text),
  'Unlinked member ····'||right(pg_temp.aid('auditor.m')::text,4),'an unlinked member shows a short id');
select pg_temp.actor('outsider');set local role authenticated;
select throws_ok($$select pg_temp.acc()$$,'42501',null,'non-members cannot read access');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select pg_temp.acc()$$,'42501',null,'another tenant cannot read access');
reset role;select pg_temp.actor('owner');set local role authenticated;
select throws_ok($$select pg_temp.acc()$$,'42501',null,'evidence submitters cannot read access');
reset role;

-- Grant, replay, duplicate grant, revoke.
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('set.1',pg_temp.setrole(pg_temp.grant8('owner','assurance_auditor','entity'),0,'a8.1'));
insert into assurance_samples values('set.1r',pg_temp.setrole(pg_temp.grant8('owner','assurance_auditor','entity'),0,'a8.1'));
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_auditor','branch'),0,'a8.1')$$,
  '22023','IDEMPOTENCY_MISMATCH','a reused key with a changed body is refused');
insert into assurance_samples values('set.2',pg_temp.setrole(pg_temp.grant8('owner','assurance_auditor','entity'),1,'a8.2'));
reset role;
select is((select body from assurance_samples where label='set.1'),
  jsonb_build_object('membership_id',pg_temp.aid('owner.m'),'version',1,'role_code','assurance_auditor',
    'granted',true,'scope','entity'),'a grant returns the membership version and assignment');
select is((select body from assurance_samples where label='set.1r'),(select body from assurance_samples where label='set.1'),
  'the same key replays the same receipt');
select is((select count(*)::integer from core.role_assignments ra join core.roles r on r.id=ra.role_id
  where ra.membership_id=pg_temp.aid('owner.m') and r.code='assurance_auditor'
    and ra.legal_entity_id=pg_temp.aid('tenant.entity') and ra.branch_id is null),1,
  'granting twice at the same scope keeps one assignment');
select is((select (body->>'version')::integer from assurance_samples where label='set.2'),2,'a repeated grant still advances the version');
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('acc.after',pg_temp.acc());
reset role;
select is((select a from assurance_samples s, jsonb_array_elements(s.body->'members') m, jsonb_array_elements(m->'assignments') a
  where s.label='acc.after' and m->>'membership_id'=pg_temp.aid('owner.m')::text),
  jsonb_build_object('role_code','assurance_auditor','scope','entity','legal_entity_id',pg_temp.aid('tenant.entity'),'branch_id',null),
  'the read model shows the assignment and its scope');
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('set.3',pg_temp.setrole(pg_temp.grant8('owner','assurance_auditor','entity',false),2,'a8.3'));
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_auditor','entity',false),3,'a8.4')$$,
  'P0002','ASSURANCE_ASSIGNMENT_NOT_FOUND','revoking an absent assignment is refused');
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_lead','tenant'),1,'a8.5')$$,
  '40001',null,'a stale version is refused');
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_lead','tenant'),null,'a8.6')$$,
  '22023','ASSURANCE_VERSION_REQUIRED','a missing version is refused');
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','tenant_owner','tenant'),3,'a8.7')$$,
  '22023','ASSURANCE_ROLE_UNKNOWN','only assurance roles can be given');
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_lead','tenant')||'{"extra":1}',3,'a8.8')$$,
  '22023','ASSURANCE_UNEXPECTED_FIELD','unexpected fields are refused');
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('outsider','assurance_lead','tenant'),0,'a8.9')$$,
  'P0002','ASSURANCE_MEMBER_NOT_FOUND','only active members of this tenant can be given roles');
reset role;
select is((select (body->>'version')::integer from assurance_samples where label='set.3'),3,'a revoke advances the version');
select ok(not exists(select 1 from core.role_assignments ra join core.roles r on r.id=ra.role_id
  where ra.membership_id=pg_temp.aid('owner.m') and r.code='assurance_auditor'),'a revoke removes the assignment');
select is((select array_agg(action||':'||version order by version) from assurance.access_events
  where membership_id=pg_temp.aid('owner.m')),array['grant:1','grant:2','revoke:3'],'every change is one ordered event');
select throws_ok($$update assurance.access_events set action='grant'$$,null,null,'access events cannot be changed');
select throws_ok($$delete from assurance.access_events$$,null,null,'access events cannot be deleted');

-- Authority and MFA.
select pg_temp.actor('manager',true,2000);set local role authenticated;
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_lead','tenant'),3,'a8.10')$$,
  '42501','ASSURANCE_RECENT_MFA_REQUIRED','role changes need recent MFA');
reset role;select pg_temp.actor('lead');set local role authenticated;
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_lead','tenant'),3,'a8.11')$$,
  '42501',null,'a branch-scoped role manager cannot change access');
reset role;select pg_temp.actor('foreign');set local role authenticated;
select throws_ok($$select pg_temp.setrole(pg_temp.grant8('owner','assurance_lead','tenant'),3,'a8.12')$$,
  '42501',null,'another tenant cannot change access');
reset role;

-- Paging: 51 more members make two pages.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.aid('bulk'||g),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'bulk'||g||'@assurance.jentra.test','',now(),now(),now() from generate_series(1,51) g;
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.aid('bulk'||g||'.m'),pg_temp.aid('tenant'),pg_temp.aid('bulk'||g),'active' from generate_series(1,51) g;
select pg_temp.actor('manager');set local role authenticated;
insert into assurance_samples values('page.1',pg_temp.acc());
insert into assurance_samples values('page.2',pg_temp.acc((select (body->>'next_cursor')::uuid from assurance_samples where label='page.1')));
reset role;
select is((select jsonb_array_length(body->'members') from assurance_samples where label='page.1'),50,'access pages members by 50');
select is((select jsonb_array_length(body->'members') from assurance_samples where label='page.1')
  +(select jsonb_array_length(body->'members') from assurance_samples where label='page.2'),
  (select count(*)::integer from core.memberships where tenant_id=pg_temp.aid('tenant') and status='active'),
  'the next page holds the remaining members');
select is((select body->'next_cursor' from assurance_samples where label='page.2'),'null'::jsonb,'the last page has no cursor');
