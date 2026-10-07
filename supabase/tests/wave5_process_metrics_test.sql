-- Synthetic namespace; included after the candidate inside one strict rollback.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.fid(s text) returns uuid language sql immutable as $$select md5('wave5-process-20261006:'||s)::uuid$$;
create function pg_temp.actor(s text) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(s),'role','authenticated','aal','aal2')::text,true);end$$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.fid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@w5.jentra.test','',now(),now(),now()
from unnest(array['owner','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('t'),'Synthetic Wave 5','wave5-process-synthetic',pg_temp.fid('owner'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
values(pg_temp.fid('e'),pg_temp.fid('t'),'Synthetic Analytics','W5SYN','LKR','UTC',2,pg_temp.fid('owner'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),'Synthetic Branch '||x,'W5'||upper(x),pg_temp.fid('owner') from unnest(array['b','b2']) x;
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.fid('t'),'starter','trialing',5,now()+interval '1 day');
-- The existing plan is changed only within this rollback transaction.
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('starter','analytics',true)
on conflict(plan_code,entitlement_code) do update set enabled=true;
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.fid(x||'.member'),pg_temp.fid('t'),pg_temp.fid(x),'active' from unnest(array['owner','reader']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.fid(x||'.role'),pg_temp.fid('t'),x,x,false from unnest(array['owner','reader']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('t'),pg_temp.fid(x||'.role'),p from unnest(array['owner','reader']) x
cross join unnest(array['analytics.view','workflow.process.view','crm.opportunities.view']) p;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('t'),pg_temp.fid(x||'.member'),pg_temp.fid(x||'.role'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('owner')
from unnest(array['owner','reader']) x;
insert into crm.opportunities(id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,currency_code,created_by,updated_by,
 expected_close_date,request_id,command_id,correlation_id,client_timestamp)
values(pg_temp.fid('o'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'W5-O','Synthetic prospect',pg_temp.fid('owner'),'LKR',pg_temp.fid('owner'),pg_temp.fid('owner'),
 '2026-10-01',pg_temp.fid('o'),pg_temp.fid('o'),pg_temp.fid('o'),'2026-09-01');
insert into workflow.process_events(id,tenant_id,legal_entity_id,branch_id,document_type,document_id,to_status,actor_id,owner_id,
 entered_at,completed_at,request_id,command_id,correlation_id,created_at,reason)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'crm_opportunity',pg_temp.fid('o'),'qualified',
 pg_temp.fid('reader'),pg_temp.fid('reader'),'2026-09-01T00:00:00Z',
 case x when 'zero' then '2026-09-01T00:00:00Z'::timestamptz when 'closed' then '2026-09-01T00:00:00.000001Z'::timestamptz else null end,
 pg_temp.fid(x),pg_temp.fid(x),pg_temp.fid(x),'2026-09-02T00:00:00Z','PRIVATE TEST REASON'
from unnest(array['zero','closed','open']) x;
create function pg_temp.read(b text default 'b', ending timestamptz default '2026-10-01T00:00:00Z') returns jsonb language sql as $$
select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid(b),'2026-09-01T00:00:00Z',ending,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z')$$;
select pg_temp.actor('owner');
create temporary table w5_results(name text primary key,result jsonb);
select is(api.analytics_process_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),pg_temp.fid('owner'),'Recovery authorization returns actual authenticated actor');
insert into w5_results values('snapshot',pg_temp.read());
select is((select result#>>'{source,sourceCount}' from w5_results),'3','Complete authorized cohort captured');
select is((select result#>>'{source,complete}' from w5_results),'true','Complete manifest advertised only after bounded query');
select ok((select result#>>'{source,sourceManifestHash}' ~ '^[0-9a-f]{64}$' from w5_results),'Canonical SHA256 captured');
select ok((select result::text not like '%PRIVATE TEST REASON%' and result::text not like '%actorId%' and result::text not like '%ownerId%' from w5_results),'Private reason and identities omitted');
select is((select count(*) from jsonb_array_elements((select result->'observations' from w5_results)) x where x->>'completedAt'='2026-09-01T00:00:00.000001Z'),1::bigint,'Exact microsecond transport');
select is((pg_temp.read()->'source'->>'sourceManifestHash'),(select result#>>'{source,sourceManifestHash}' from w5_results),'Repeated basis digest stable');
select is((api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))->>'documentId'),pg_temp.fid('o')::text,'Drill-through rechecks actual source');
select throws_ok($$select pg_temp.read('b2')$$,'42501','Permission denied or multi-factor authentication required.','Foreign branch denied');
select throws_ok($$select pg_temp.read('b','2026-09-01')$$,'22023','VALIDATION_ERROR','Empty range rejected');
select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2024-01-01','2026-01-01','2026-01-01','2026-01-01')$$,'54000','LIMIT_EXCEEDED','366-day bound enforced');
select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-01','2026-10-01','2026-10-01','2099-01-01')$$,'22023','VALIDATION_ERROR','Future recorded cutoff rejected');
delete from core.role_permissions where role_id=pg_temp.fid('reader.role') and permission_code='crm.opportunities.view';
select pg_temp.actor('reader');
select throws_ok($$select pg_temp.read()$$,'42501','PERMISSION_DENIED','Own/owned event is insufficient without source permission');
select throws_ok($$select api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))$$,'42501','PERMISSION_DENIED','Revoked source blocks drill-through');
select pg_temp.actor('outsider');
select throws_ok($$select pg_temp.read()$$,'42501','Permission denied or multi-factor authentication required.','Foreign member denied before aggregate');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select pg_temp.read()$$,'42501','AUTH_REQUIRED','Anonymous denied');
select pg_temp.actor('owner');
update billing.plan_entitlements set enabled=false where plan_code='starter' and entitlement_code='analytics';
select throws_ok($$select pg_temp.read()$$,'42501','ENTITLEMENT_REQUIRED','Missing entitlement denies aggregate');
update billing.plan_entitlements set enabled=true where plan_code='starter' and entitlement_code='analytics';
select ok(not has_function_privilege('anon','api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)','execute'),'Anonymous cannot execute provider');
select ok(not has_function_privilege('authenticated','analytics.process_access(uuid,uuid,uuid)','execute'),'Private helper denied');
select throws_ok($test$do $body$begin
 insert into workflow.process_events(id,tenant_id,legal_entity_id,branch_id,document_type,document_id,to_status,actor_id,
  entered_at,completed_at,request_id,command_id,correlation_id,created_at)
 select pg_temp.fid('bound.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'crm_opportunity',pg_temp.fid('o'),'qualified',pg_temp.fid('owner'),
  '2026-09-01','2026-09-02',pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),'2026-09-02'
 from generate_series(1,9998) i;
 perform pg_temp.read();
end $body$$test$,'54000','LIMIT_EXCEEDED','10001 rows fail atomically without truncated totals');
select is((pg_temp.read()#>>'{source,sourceCount}'),'3','Excess-fixture failure leaves original cohort intact');
select * from finish(true);
-- Actual wire is returned for cross-language canonical digest verification.
select result as snapshot from w5_results;
