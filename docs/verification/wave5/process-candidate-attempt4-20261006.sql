begin;
-- Unapplied Wave 5 read candidate. Does not modify producers or enable plans.
create schema if not exists analytics;
revoke all on schema analytics from public,anon,authenticated;

create function analytics.process_access(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception using errcode='42501',message='AUTH_REQUIRED';end if;
 if t is null or e is null then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform core.wave3_require_scope(t,'analytics.view',e,b);
 perform core.wave3_require_scope(t,'workflow.process.view',e,b);
 if not (core.has_permission(t,'crm.opportunities.view',e,b) or core.has_permission(t,'crm.opportunities.manage',e,b)) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';
 end if;
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and s.trial_ends_at>current_timestamp)
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>current_timestamp)))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';
 end if;
end $$;
revoke all on function analytics.process_access(uuid,uuid,uuid) from public,anon,authenticated;

create function analytics.process_utc(v timestamptz) returns text
language sql immutable set search_path='' as $$select to_char(v at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$$;
revoke all on function analytics.process_utc(timestamptz) from public,anon,authenticated;

create function api.analytics_process_snapshot(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_window_start timestamptz,p_window_end timestamptz,p_as_of timestamptz,p_recorded_through timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows json;ids json;canonical json;digest text;count_rows integer;result jsonb;
begin
 perform analytics.process_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_window_start is null or p_window_end is null or p_as_of is null or p_recorded_through is null
  or not isfinite(p_window_start) or not isfinite(p_window_end) or not isfinite(p_as_of) or not isfinite(p_recorded_through)
  or p_window_start>=p_window_end or p_window_end>p_as_of or p_as_of>p_recorded_through
  or p_recorded_through>statement_timestamp() then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_window_end-p_window_start>interval '366 days' then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 -- Compare the exact projected installed column contract, not a readiness label.
 if (select count(*) from pg_attribute a where a.attrelid='workflow.process_events'::regclass and not a.attisdropped
  and (a.attname,a.atttypid) in (('id','uuid'::regtype),('tenant_id','uuid'::regtype),('legal_entity_id','uuid'::regtype),
   ('branch_id','uuid'::regtype),('document_type','text'::regtype),('document_id','uuid'::regtype),
   ('entered_at','timestamptz'::regtype),('completed_at','timestamptz'::regtype),('created_at','timestamptz'::regtype),
   ('active_minutes','numeric'::regtype),('wait_minutes','numeric'::regtype)))<>11 then
  raise exception using errcode='55000',message='CONTRACT_MISMATCH';end if;
 select coalesce(json_agg(json_build_object('id',x.id,'tenantId',x.tenant_id,'legalEntityId',x.legal_entity_id,
   'branchId',x.branch_id,'documentType',x.document_type,'documentId',x.document_id,
   'enteredAt',analytics.process_utc(x.entered_at),'completedAt',analytics.process_utc(x.completed_at),
   'recordedAt',analytics.process_utc(x.created_at),'activeMinutes',x.active_minutes::text,'waitMinutes',x.wait_minutes::text)
   order by x.id),'[]'::json),coalesce(json_agg(x.id order by x.id),'[]'::json),count(*)
 into rows,ids,count_rows from (
  select ev.* from workflow.process_events ev join crm.opportunities o
   on o.tenant_id=ev.tenant_id and o.id=ev.document_id and o.legal_entity_id=ev.legal_entity_id
    and o.branch_id is not distinct from ev.branch_id
  where ev.tenant_id=p_tenant_id and ev.legal_entity_id=p_legal_entity_id
   and (p_branch_id is null or ev.branch_id=p_branch_id) and ev.document_type='crm_opportunity'
   and ev.entered_at>=p_window_start and ev.entered_at<p_window_end and ev.created_at<=p_recorded_through
   and (core.has_permission(p_tenant_id,'crm.opportunities.view',p_legal_entity_id,ev.branch_id)
     or core.has_permission(p_tenant_id,'crm.opportunities.manage',p_legal_entity_id,ev.branch_id))
  order by ev.id limit 10001
 ) x;
 if count_rows>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 canonical:=json_build_object('definitionCode','process.event_duration','definitionVersion',1,
  'sourceContractVersion','workflow.process_events.v1','tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,
  'branchId',p_branch_id,'documentType','crm_opportunity','windowStart',analytics.process_utc(p_window_start),
  'windowEnd',analytics.process_utc(p_window_end),'asOf',analytics.process_utc(p_as_of),
  'recordedThrough',analytics.process_utc(p_recorded_through),'observations',rows);
 -- All string values above are fixed codes, UUIDs, numeric strings or UTC instants.
 -- They cannot contain structural separators; no arbitrary text enters this JSON.
 digest:=encode(extensions.digest(convert_to(replace(replace(replace(canonical::text,' : ',':'),': ',':'),', ',','),'UTF8'),'sha256'),'hex');
 result:=jsonb_build_object('source',jsonb_build_object('snapshotId',gen_random_uuid(),'sourceManifestHash',digest,
  'sourceEventIds',ids,'sourceContractVersion','workflow.process_events.v1','tenantId',p_tenant_id,
  'legalEntityId',p_legal_entity_id,'branchId',p_branch_id,'documentType','crm_opportunity',
  'windowStart',analytics.process_utc(p_window_start),'windowEnd',analytics.process_utc(p_window_end),
  'asOf',analytics.process_utc(p_as_of),'recordedThrough',analytics.process_utc(p_recorded_through),
  'sourceCount',count_rows,'complete',true),'observations',rows);
 if octet_length(convert_to(result::text,'UTF8'))>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return result;
end $$;
revoke all on function api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz) from public,anon;
grant execute on function api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz) to authenticated;

create function api.analytics_process_event(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ev workflow.process_events%rowtype;
begin
 perform analytics.process_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 select x.* into ev from workflow.process_events x join crm.opportunities o on o.tenant_id=x.tenant_id and o.id=x.document_id
  and o.legal_entity_id=x.legal_entity_id and o.branch_id is not distinct from x.branch_id
 where x.id=p_event_id and x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or x.branch_id=p_branch_id) and x.document_type='crm_opportunity';
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform analytics.process_access(p_tenant_id,p_legal_entity_id,ev.branch_id);
 return jsonb_build_object('eventId',ev.id,'documentType',ev.document_type,'documentId',ev.document_id,
  'tenantId',ev.tenant_id,'legalEntityId',ev.legal_entity_id,'branchId',ev.branch_id);
end $$;
revoke all on function api.analytics_process_event(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function api.analytics_process_event(uuid,uuid,uuid,uuid) to authenticated;

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
insert into w5_results values('snapshot',pg_temp.read());
select is((select result#>>'{source,sourceCount}' from w5_results),'3','Complete authorized cohort captured');
select is((select result#>>'{source,complete}' from w5_results),'true','Complete manifest advertised only after bounded query');
select ok((select result#>>'{source,sourceManifestHash}' ~ '^[0-9a-f]{64}$' from w5_results),'Canonical SHA256 captured');
select ok((select result::text not like '%PRIVATE TEST REASON%' and result::text not like '%actorId%' and result::text not like '%ownerId%' from w5_results),'Private reason and identities omitted');
select is((select count(*) from jsonb_array_elements((select result->'observations' from w5_results)) x where x->>'completedAt'='2026-09-01T00:00:00.000001Z'),1::bigint,'Exact microsecond transport');
select is((pg_temp.read()->'source'->>'sourceManifestHash'),(select result#>>'{source,sourceManifestHash}' from w5_results),'Repeated basis digest stable');
select is((api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))->>'documentId'),pg_temp.fid('o')::text,'Drill-through rechecks actual source');
select throws_ok($$select pg_temp.read('b2')$$,'42501','Permission denied.','Foreign branch denied');
select throws_ok($$select pg_temp.read('b','2026-09-01')$$,'22023','VALIDATION_ERROR','Empty range rejected');
select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2024-01-01','2026-01-01','2026-01-01','2026-01-01')$$,'54000','LIMIT_EXCEEDED','366-day bound enforced');
select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-01','2026-10-01','2026-10-01','2099-01-01')$$,'22023','VALIDATION_ERROR','Future recorded cutoff rejected');
delete from core.role_permissions where role_id=pg_temp.fid('reader.role') and permission_code='crm.opportunities.view';
select pg_temp.actor('reader');
select throws_ok($$select pg_temp.read()$$,'42501','PERMISSION_DENIED','Own/owned event is insufficient without source permission');
select throws_ok($$select api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))$$,'42501','PERMISSION_DENIED','Revoked source blocks drill-through');
select pg_temp.actor('outsider');
select throws_ok($$select pg_temp.read()$$,'42501','Permission denied.','Foreign member denied before aggregate');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select pg_temp.read()$$,'42501','AUTH_REQUIRED','Anonymous denied');
select pg_temp.actor('owner');
update billing.plan_entitlements set enabled=false where plan_code='starter' and entitlement_code='analytics';
select throws_ok($$select pg_temp.read()$$,'42501','ENTITLEMENT_REQUIRED','Missing entitlement denies aggregate');
update billing.plan_entitlements set enabled=true where plan_code='starter' and entitlement_code='analytics';
select ok(not has_function_privilege('anon','api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)','execute'),'Anonymous cannot execute provider');
select ok(not has_function_privilege('authenticated','analytics.process_access(uuid,uuid,uuid)','execute'),'Private helper denied');
select * from finish(true);
-- Actual wire is returned for cross-language canonical digest verification.
select result as snapshot from w5_results;

rollback;

