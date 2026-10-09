-- UNINSTALLED candidate. Creates contracts only: no authorities, keys, jobs,
-- receiver registrations or synthetic activation are seeded by installation.
create table intelligence_control.edge_authorities(
 runtime_id uuid primary key,enabled boolean not null default false,
 issued_at timestamptz not null default statement_timestamp(),expires_at timestamptz not null,
 schedule_secret_id uuid not null,schedule_secret_hash text not null check(schedule_secret_hash ~ '^[a-f0-9]{64}$'),
 publishable_key text not null check(length(publishable_key) between 32 and 4096),
 job_ids bigint[] not null default '{}',
 check(isfinite(expires_at) and expires_at>issued_at and expires_at<=issued_at+interval '7 days'));
create table intelligence_control.edge_key_refs(
 runtime_id uuid not null references intelligence_control.edge_authorities(runtime_id),ref text not null,secret_id uuid not null,
 primary key(runtime_id,ref),check(ref in('w5/runtime/20261008/delivery/v1','w5/runtime/20261008/delivery/v2')));
create table intelligence_control.edge_ticks(
 runtime_id uuid not null references intelligence_control.edge_authorities(runtime_id),id uuid not null,
 kind text not null check(kind in('delivery','subscription','health')),state text not null check(state in('running','completed','failed','unknown')),
 started_at timestamptz not null default statement_timestamp(),lease_until timestamptz not null,
 primary key(runtime_id,id));
create index edge_running_tick_idx on intelligence_control.edge_ticks(runtime_id,kind,lease_until) where state='running';
create table intelligence_control.edge_tick_outcomes(
 runtime_id uuid not null,id uuid not null,success boolean not null,summary jsonb not null,
 recorded_at timestamptz not null default statement_timestamp(),primary key(runtime_id,id),
 foreign key(runtime_id,id) references intelligence_control.edge_ticks(runtime_id,id),
 check(jsonb_typeof(summary)='object' and octet_length(summary::text)<=2048));
create table intelligence_control.edge_receiver_receipts(
 runtime_id uuid not null references intelligence_control.edge_authorities(runtime_id),event_id uuid not null references core.outbox_events(id),
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,subscription_id uuid not null,
 key_version integer not null check(key_version in(1,2)),payload bytea not null check(octet_length(payload)<=8192),
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),signed_timestamp bigint not null,
 received_at timestamptz not null default statement_timestamp(),primary key(runtime_id,subscription_id,event_id),
 foreign key(tenant_id,subscription_id) references intelligence_control.integration_subscriptions(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id));
do $$declare rel text;begin
 foreach rel in array array['edge_authorities','edge_key_refs','edge_ticks','edge_tick_outcomes','edge_receiver_receipts'] loop
  execute format('alter table intelligence_control.%I enable row level security',rel);
  execute format('alter table intelligence_control.%I force row level security',rel);
  execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
 end loop;
 foreach rel in array array['edge_key_refs','edge_tick_outcomes','edge_receiver_receipts'] loop
  execute format('create trigger immutable before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);
 end loop;
end$$;

create function api.wave5_edge_control(p_runtime_id uuid,p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a intelligence_control.edge_authorities%rowtype;t intelligence_control.edge_ticks%rowtype;
 s intelligence_control.integration_subscriptions%rowtype;f analytics.pipeline_forecasts%rowtype;
 existing intelligence_control.edge_receiver_receipts%rowtype;v jsonb;b bytea;secret_value text;secret_id uuid;
 saved_claims text;source_tenant uuid;tick_id uuid;begin
 perform intelligence_control.runtime_worker_required(p_runtime_id);
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 select * into a from intelligence_control.edge_authorities where runtime_id=p_runtime_id and enabled
  and issued_at<=statement_timestamp() and expires_at>statement_timestamp() for update;
 if not found then raise exception using errcode='42501',message='RUNTIME_SCOPE_DENIED';end if;
 if p_action='begin_tick' then
  if (p_payload-array['tickId','kind','secretHash'])<>'{}' or not(p_payload ?& array['tickId','kind','secretHash'])
   or p_payload->>'kind' not in('delivery','subscription','health') or p_payload->>'secretHash' is distinct from a.schedule_secret_hash then
   raise exception using errcode='42501',message='WORKER_ACCESS_DENIED';end if;
  tick_id:=(p_payload->>'tickId')::uuid;
  if tick_id is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
  if exists(select 1 from intelligence_control.edge_ticks where runtime_id=p_runtime_id and id=tick_id) then
   return jsonb_build_object('permitted',false);end if;
  update intelligence_control.edge_ticks set state='unknown' where runtime_id=p_runtime_id and kind=p_payload->>'kind' and state='running' and lease_until<=statement_timestamp();
  if exists(select 1 from intelligence_control.edge_ticks where runtime_id=p_runtime_id and kind=p_payload->>'kind' and state='running') then
   return jsonb_build_object('permitted',false);end if;
  select tenant_id into source_tenant from intelligence_control.runtime_worker_scopes
   where runtime_id=p_runtime_id and intelligence_control.runtime_scope_allowed(p_runtime_id,tenant_id,legal_entity_id,branch_id) limit 1;
  insert into intelligence_control.edge_ticks(runtime_id,id,kind,state,lease_until)
   values(p_runtime_id,tick_id,p_payload->>'kind','running',statement_timestamp()+interval '90 seconds');
  return jsonb_build_object('permitted',true,'tenantId',source_tenant);
 elsif p_action='finish_tick' then
  if (p_payload-array['tickId','success','summary'])<>'{}' or not(p_payload ?& array['tickId','success','summary'])
   or jsonb_typeof(p_payload->'success')<>'boolean' or jsonb_typeof(p_payload->'summary')<>'object'
   or octet_length((p_payload->'summary')::text)>2048 then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
  select * into t from intelligence_control.edge_ticks where runtime_id=p_runtime_id and id=(p_payload->>'tickId')::uuid for update;
  if t.id is null or t.state<>'running' or t.lease_until<=statement_timestamp() then raise exception using errcode='42501',message='LEASE_UNAVAILABLE';end if;
  insert into intelligence_control.edge_tick_outcomes values(p_runtime_id,t.id,(p_payload->>'success')::boolean,p_payload->'summary',statement_timestamp());
  update intelligence_control.edge_ticks set state=case when (p_payload->>'success')::boolean then 'completed' else 'failed' end where runtime_id=p_runtime_id and id=t.id;
  return jsonb_build_object('recorded',true);
 elsif p_action='key' then
  if (p_payload-'ref')<>'{}' or not(p_payload ? 'ref') then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
  select k.secret_id into secret_id from intelligence_control.edge_key_refs k where k.runtime_id=p_runtime_id and k.ref=p_payload->>'ref';
  if secret_id is null then raise exception using errcode='42501',message='DELIVERY_KEY_UNAVAILABLE';end if;
  -- Only this runtime's two explicitly provisioned Vault IDs can be read. No
  -- caller-provided Vault ID/name and no existing project secret are discoverable.
  select decrypted_secret into secret_value from vault.decrypted_secrets where id=secret_id;
  if secret_value is null or secret_value !~ '^[a-f0-9]{64}$' then raise exception using errcode='55000',message='DELIVERY_KEY_UNAVAILABLE';end if;
  return jsonb_build_object('value',secret_value);
 elsif p_action in('receive','receive_probe') then
  if (p_payload-array['event','keyVersion','payloadBase64','sha256','timestamp','mode'])<>'{}'
   or not(p_payload ?& array['event','keyVersion','payloadBase64','sha256','timestamp','mode'])
   or p_payload->>'mode' not in('accept','redirect','timeout','reject')
   or (p_action='receive') is distinct from (p_payload->>'mode' in('accept','timeout')) then
   raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
  v:=p_payload->'event';b:=decode(p_payload->>'payloadBase64','base64');
  if octet_length(b)>8192 or convert_from(b,'UTF8')::jsonb is distinct from v
   or encode(extensions.digest(b,'sha256'),'hex') is distinct from p_payload->>'sha256'
   or (p_payload->>'timestamp')::bigint<extract(epoch from statement_timestamp())-300
   or (p_payload->>'timestamp')::bigint>extract(epoch from statement_timestamp())+30 then
   raise exception using errcode='22023',message='EVENT_CONTRACT_MISMATCH';end if;
  select s0.* into s from intelligence_control.integration_subscriptions s0
   where s0.id=case p_payload->>'mode'
    when 'accept' then '58699e8a-28fd-4356-8cad-87ce46e17ddd'::uuid
    when 'redirect' then '2bdbd842-5b94-464b-85fc-22d722498831'::uuid
    when 'timeout' then '0961e194-dc0b-4632-8c2d-65686fc9f111'::uuid
    when 'reject' then '360e7a9d-08a5-4349-854f-c2343ce2ff5d'::uuid end
    and s0.enabled and s0.key_version=(p_payload->>'keyVersion')::integer
    and s0.key_ref='w5/runtime/20261008/delivery/v'||(p_payload->>'keyVersion')
    and s0.url='https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-receiver/'||(p_payload->>'mode')
    and intelligence_control.runtime_scope_allowed(p_runtime_id,s0.tenant_id,s0.legal_entity_id,s0.branch_id);
  if not found then raise exception using errcode='42501',message='INTEGRATION_ACCESS_DENIED';end if;
  select f0.* into f from core.outbox_events o join analytics.pipeline_forecasts f0 on f0.tenant_id=o.tenant_id and f0.id=o.aggregate_id
   where o.id=(v->>'eventId')::uuid and o.tenant_id=s.tenant_id and o.topic='analytics.freeze_pipeline' and o.aggregate_type='pipeline_forecast'
    and f0.legal_entity_id=s.legal_entity_id and f0.branch_id=s.branch_id;
  if f.id is null or v is distinct from jsonb_build_object('eventId',(v->>'eventId')::uuid,'type','analytics.forecast.frozen.v1',
   'tenantId',s.tenant_id,'legalEntityId',s.legal_entity_id,'branchId',s.branch_id,'forecastId',f.id,'definitionVersion',1,'sourceHash',f.source_hash) then
   raise exception using errcode='42501',message='EVENT_CONTRACT_MISMATCH';end if;
  perform intelligence_control.quota_limit(s.tenant_id,'webhook.deliveries');
  saved_claims:=current_setting('request.jwt.claims',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',s.created_by,'role','authenticated','aal','aal1')::text,true);
  perform core.wave3_require_scope(s.tenant_id,'integrations.manage',s.legal_entity_id,s.branch_id);
  perform api.get_pipeline_forecast(s.tenant_id,s.legal_entity_id,s.branch_id,f.id);
  perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
  if p_action='receive_probe' then return jsonb_build_object('permitted',true);end if;
  select * into existing from intelligence_control.edge_receiver_receipts where runtime_id=p_runtime_id and subscription_id=s.id and event_id=(v->>'eventId')::uuid;
  if found then
   if existing.payload<>b or existing.sha256<>p_payload->>'sha256' then raise exception using errcode='23505',message='RECEIVER_DIGEST_CONFLICT';end if;
   return jsonb_build_object('acknowledged',true,'duplicate',true,'sha256',existing.sha256);end if;
  if not exists(select 1 from intelligence_control.delivery_heads d join intelligence_control.delivery_attempts da
   on da.tenant_id=d.tenant_id and da.delivery_id=d.id and da.attempt=d.attempt and da.lease_id=d.lease_id
   where d.tenant_id=s.tenant_id and d.subscription_id=s.id and d.event_id=(v->>'eventId')::uuid
    and d.state='leased' and d.lease_until>statement_timestamp() and da.key_version=s.key_version and da.subscription_version=s.version) then
   raise exception using errcode='42501',message='LEASE_UNAVAILABLE';end if;
  insert into intelligence_control.edge_receiver_receipts values(p_runtime_id,(v->>'eventId')::uuid,s.tenant_id,s.legal_entity_id,s.branch_id,s.id,
   (p_payload->>'keyVersion')::integer,b,p_payload->>'sha256',(p_payload->>'timestamp')::bigint,statement_timestamp());
  return jsonb_build_object('acknowledged',true,'duplicate',false,'sha256',p_payload->>'sha256');
 end if;
 raise exception using errcode='22023',message='WORKER_ACTION_INVALID';
end$$;
revoke all on function api.wave5_edge_control(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_edge_control(uuid,text,jsonb) to service_role;
