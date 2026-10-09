-- UNAPPLIED synthetic-development candidate. No hosts, keys, credentials,
-- subscriptions, worker deployment or entitlement activation are provisioned.
insert into core.permissions(code,module,description,privileged) values
 ('integrations.manage','integrations','Manage scoped reviewed integrations',true)
 on conflict(code) do nothing;
create table intelligence_control.integration_hosts(hostname text primary key,
 check(hostname ~ '^[a-z0-9][a-z0-9.-]{1,250}[a-z0-9]$'));
create table intelligence_control.integration_subscriptions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,
 created_by uuid not null references auth.users(id),url text not null,hostname text not null references intelligence_control.integration_hosts,
 version bigint not null default 1,key_version integer not null default 1,key_ref text not null,
 enabled boolean not null default true,created_at timestamptz not null default statement_timestamp(),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(version>0 and key_version>0 and key_ref ~ '^[a-zA-Z0-9_/-]{1,180}$'),
 check(url ~ '^https://[^/@:#?]+(:443)?(/[^#]*)?$' and length(url)<=2048));
create table intelligence_control.integration_changes(
 id uuid primary key,tenant_id uuid not null,subscription_id uuid not null,version bigint not null,
 actor_id uuid not null references auth.users(id),action text not null,evidence jsonb not null,
 recorded_at timestamptz not null default statement_timestamp(),unique(tenant_id,subscription_id,version),
 foreign key(tenant_id,subscription_id) references intelligence_control.integration_subscriptions(tenant_id,id));
create table intelligence_control.delivery_heads(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,subscription_id uuid not null,event_id uuid not null references core.outbox_events(id),
 invocation_id uuid not null default gen_random_uuid(),usage_event_id uuid not null default gen_random_uuid(),
 attempt integer not null default 0 check(attempt between 0 and 8),state text not null default 'pending'
 check(state in('pending','leased','retry','unknown','acknowledged','dead_letter')),
 available_at timestamptz not null default statement_timestamp(),lease_id uuid,lease_until timestamptz,
 period_start timestamptz,period_end timestamptz,generation integer not null default 0 check(generation>=0),replay_of uuid,
 unique(tenant_id,subscription_id,event_id,generation),unique(tenant_id,id),
 foreign key(tenant_id,replay_of) references intelligence_control.delivery_heads(tenant_id,id),
 foreign key(tenant_id,subscription_id) references intelligence_control.integration_subscriptions(tenant_id,id));
create table intelligence_control.delivery_attempts(
 tenant_id uuid not null,delivery_id uuid not null,attempt integer not null,lease_id uuid not null unique,
 key_version integer not null,subscription_version bigint not null,claimed_at timestamptz not null default statement_timestamp(),
 primary key(tenant_id,delivery_id,attempt),foreign key(tenant_id,delivery_id) references intelligence_control.delivery_heads(tenant_id,id));
create table intelligence_control.delivery_outcomes(
 tenant_id uuid not null,delivery_id uuid not null,attempt integer not null,state text not null,
 http_status integer,recorded_at timestamptz not null default statement_timestamp(),
 primary key(tenant_id,delivery_id,attempt),foreign key(tenant_id,delivery_id,attempt)
 references intelligence_control.delivery_attempts(tenant_id,delivery_id,attempt),
 check(state in('acknowledged','retry','unknown','dead_letter')),
 check(http_status is null or http_status between 100 and 599));
create table intelligence_control.delivery_reviews(
 id uuid primary key,tenant_id uuid not null,delivery_id uuid not null,actor_id uuid not null references auth.users(id),
 action text not null check(action in('replay','acknowledged','not_sent')),reason text not null check(length(trim(reason)) between 8 and 500),
 recorded_at timestamptz not null default statement_timestamp(),
 foreign key(tenant_id,delivery_id) references intelligence_control.delivery_heads(tenant_id,id));
do $$declare rel text;begin
 foreach rel in array array['integration_hosts','integration_subscriptions','integration_changes','delivery_heads','delivery_attempts','delivery_outcomes','delivery_reviews'] loop
  execute format('alter table intelligence_control.%I enable row level security',rel);
  execute format('alter table intelligence_control.%I force row level security',rel);
  execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
  if rel not in('integration_subscriptions','delivery_heads') then
   execute format('create trigger immutable before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);
  end if;
 end loop;
end $$;
create index delivery_ready_idx on intelligence_control.delivery_heads(state,available_at,id);
create index delivery_subscription_idx on intelligence_control.delivery_heads(tenant_id,subscription_id,id);
create index integration_scope_idx on intelligence_control.integration_subscriptions(tenant_id,legal_entity_id,branch_id,id);

create function api.wave5_integration_manage(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_action text,p_id uuid,p_expected_version bigint,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s intelligence_control.integration_subscriptions%rowtype;prior intelligence_control.integration_changes%rowtype;host text;h text;receipt jsonb;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 if p_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,58));
 if p_expected_version is null or p_expected_version<0 or p_action is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 h:=encode(extensions.digest(jsonb_build_object('scope',jsonb_build_array(p_tenant_id,p_legal_entity_id,p_branch_id),'action',p_action,'payload',p_payload)::text,'sha256'),'hex');
 select * into prior from intelligence_control.integration_changes where tenant_id=p_tenant_id and subscription_id=p_id and version=p_expected_version+1;
 if found then
  if prior.actor_id<>auth.uid() or prior.action<>p_action or prior.evidence->>'requestHash' is distinct from h then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  return prior.evidence->'receipt';end if;
 if p_action='register' then
  if p_expected_version<>0 or p_expected_version is null or (p_payload-array['url','keyRef'])<>'{}'
   or not(p_payload ?& array['url','keyRef']) or jsonb_typeof(p_payload->'url')<>'string' or jsonb_typeof(p_payload->'keyRef')<>'string' then
   raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
  host:=substring(p_payload->>'url' from '^https://([^/:?#]+)');
  if host is null or not exists(select 1 from intelligence_control.integration_hosts where hostname=host) then
   raise exception using errcode='42501',message='UNREVIEWED_DESTINATION';end if;
  insert into intelligence_control.integration_subscriptions(id,tenant_id,legal_entity_id,branch_id,created_by,url,hostname,key_ref)
   values(p_id,p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),p_payload->>'url',host,p_payload->>'keyRef') returning * into s;
 else
  select * into s from intelligence_control.integration_subscriptions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id is not distinct from p_branch_id and id=p_id for update;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
  if s.version is distinct from p_expected_version then raise exception using errcode='40001',message='CONFLICT';end if;
  if p_action='rotate' and (p_payload-'keyRef')='{}' and jsonb_typeof(p_payload->'keyRef')='string' then
   update intelligence_control.integration_subscriptions set key_ref=p_payload->>'keyRef',key_version=key_version+1,version=version+1 where id=p_id returning * into s;
  elsif p_action='revoke' and p_payload='{}' then
   update intelligence_control.integration_subscriptions set enabled=false,version=version+1 where id=p_id returning * into s;
  else raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 end if;
 receipt:=jsonb_build_object('id',s.id,'version',s.version::text,'keyVersion',s.key_version,'enabled',s.enabled);
 insert into intelligence_control.integration_changes values(gen_random_uuid(),p_tenant_id,p_id,s.version,auth.uid(),p_action,
  jsonb_build_object('requestHash',h,'receipt',receipt),statement_timestamp());
 return receipt;
end $$;

create function intelligence_control.delivery_authorize(p_delivery_id uuid,p_lease_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d intelligence_control.delivery_heads%rowtype;s intelligence_control.integration_subscriptions%rowtype;
 f analytics.pipeline_forecasts%rowtype;a intelligence_control.delivery_attempts%rowtype;saved_claims text;begin
 select * into d from intelligence_control.delivery_heads where id=p_delivery_id and lease_id=p_lease_id and state='leased' and lease_until>statement_timestamp();
 if not found then raise exception using errcode='42501',message='LEASE_UNAVAILABLE';end if;
 select * into s from intelligence_control.integration_subscriptions where tenant_id=d.tenant_id and id=d.subscription_id and enabled;
 select * into a from intelligence_control.delivery_attempts where tenant_id=d.tenant_id and delivery_id=d.id and attempt=d.attempt;
 if s.id is null or a.lease_id is null or s.version<>a.subscription_version or s.key_version<>a.key_version then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform intelligence_control.quota_limit(d.tenant_id,'webhook.deliveries');
 select f0.* into f from core.outbox_events o join analytics.pipeline_forecasts f0 on f0.tenant_id=o.tenant_id and f0.id=o.aggregate_id
 where o.id=d.event_id and o.tenant_id=s.tenant_id and o.topic='analytics.freeze_pipeline' and o.aggregate_type='pipeline_forecast'
  and f0.legal_entity_id=s.legal_entity_id and f0.branch_id is not distinct from s.branch_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 -- Explicit subscription delegation uses AAL1. It never fabricates human MFA;
 -- the installed scope, role, entitlement and every captured-branch check run.
 saved_claims:=current_setting('request.jwt.claims',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',s.created_by,'role','authenticated','aal','aal1')::text,true);
 perform core.wave3_require_scope(s.tenant_id,'integrations.manage',s.legal_entity_id,s.branch_id);
 perform api.get_pipeline_forecast(s.tenant_id,s.legal_entity_id,s.branch_id,f.id);
 perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
 return jsonb_build_object('event',jsonb_build_object('eventId',d.event_id,'type','analytics.forecast.frozen.v1',
  'tenantId',s.tenant_id,'legalEntityId',s.legal_entity_id,'branchId',s.branch_id,'forecastId',f.id,'definitionVersion',1,'sourceHash',f.source_hash),
  'subscription',jsonb_build_object('id',s.id,'scope',jsonb_build_object('tenantId',s.tenant_id,'legalEntityId',s.legal_entity_id,'branchId',s.branch_id),
  'enabled',true,'url',s.url,'allowedHosts',jsonb_build_array(s.hostname),'keyVersion',s.key_version),
  'deliveryId',d.id,'leaseId',d.lease_id,'invocationId',d.invocation_id,'usageEventId',d.usage_event_id,
  'periodStart',analytics.process_utc(d.period_start),'periodEnd',analytics.process_utc(d.period_end),'attempt',d.attempt);
end $$;
revoke all on function intelligence_control.delivery_authorize(uuid,uuid) from public,anon,authenticated;

create function api.wave5_delivery_worker(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d intelligence_control.delivery_heads%rowtype;s intelligence_control.integration_subscriptions%rowtype;
 o intelligence_control.delivery_outcomes%rowtype;subscription billing.tenant_subscriptions%rowtype;v_state text;status integer;begin
 perform intelligence_control.worker_required();
 if p_action='readiness' then return jsonb_build_object('contractRevision',1,'ready',true,'providers',jsonb_build_object('committed_webhook.v1',1,'synthetic_subscription.v1',1));end if;
 if p_action='claim' then
  -- A lease lost after send cannot be auto-retried. ACK rows can be reconciled
  -- separately; expired attempts with no outcome retain uncertain reservations.
  update intelligence_control.delivery_heads set state='unknown' where state='leased' and lease_until<=statement_timestamp();
  insert into intelligence_control.delivery_heads(tenant_id,subscription_id,event_id)
   select s0.tenant_id,s0.id,e.id from intelligence_control.integration_subscriptions s0
   join analytics.pipeline_forecasts f on f.tenant_id=s0.tenant_id and f.legal_entity_id=s0.legal_entity_id and f.branch_id is not distinct from s0.branch_id
   join core.outbox_events e on e.tenant_id=f.tenant_id and e.aggregate_id=f.id and e.aggregate_type='pipeline_forecast' and e.topic='analytics.freeze_pipeline'
   where s0.enabled and e.created_at>=s0.created_at and not exists(select 1 from intelligence_control.delivery_heads h
    where h.tenant_id=s0.tenant_id and h.subscription_id=s0.id and h.event_id=e.id and h.generation=0)
   order by e.created_at,e.id limit 1000 on conflict do nothing;
  select * into d from intelligence_control.delivery_heads where state in('pending','retry') and available_at<=statement_timestamp()
   and attempt<8 order by available_at,id for update skip locked limit 1;
  if not found then return null;end if;
  select * into s from intelligence_control.integration_subscriptions where tenant_id=d.tenant_id and id=d.subscription_id and enabled;
  if not found then update intelligence_control.delivery_heads set state='dead_letter' where id=d.id;return null;end if;
  select * into subscription from billing.tenant_subscriptions where tenant_id=d.tenant_id;
  if d.period_start is null then
   d.period_start:=case when subscription.status='trialing' then coalesce(subscription.trial_started_at,subscription.created_at)
    else coalesce((select period_start from intelligence_control.quota_periods where tenant_id=d.tenant_id and metric_code='webhook.deliveries'
     and period_end=subscription.current_period_ends_at limit 1),date_trunc('month',statement_timestamp())) end;
   d.period_end:=case when subscription.status='trialing' then subscription.trial_ends_at else subscription.current_period_ends_at end;
  end if;
  if d.period_end is null then raise exception using errcode='55000',message='BILLING_PERIOD_UNAVAILABLE';end if;
  update intelligence_control.delivery_heads set attempt=attempt+1,state='leased',lease_id=gen_random_uuid(),lease_until=statement_timestamp()+interval '60 seconds',
   period_start=d.period_start,period_end=d.period_end where id=d.id returning * into d;
  insert into intelligence_control.delivery_attempts values(d.tenant_id,d.id,d.attempt,d.lease_id,s.key_version,s.version,statement_timestamp());
  begin
   return intelligence_control.delivery_authorize(d.id,d.lease_id);
  exception when insufficient_privilege then
   -- No send occurred. Keep this denied item from starving another tenant's
   -- queue; replay still requires a reasoned MFA review after access is fixed.
   update intelligence_control.delivery_heads set state='dead_letter' where id=d.id;
   return null;
  end;
 end if;
 if p_action='authorize' then return intelligence_control.delivery_authorize((p_payload->>'deliveryId')::uuid,(p_payload->>'leaseId')::uuid);end if;
 if p_action='key_ref' then
  perform intelligence_control.delivery_authorize((p_payload->>'deliveryId')::uuid,(p_payload->>'leaseId')::uuid);
  return to_jsonb((select s0.key_ref from intelligence_control.delivery_heads d0 join intelligence_control.integration_subscriptions s0 on s0.tenant_id=d0.tenant_id and s0.id=d0.subscription_id where d0.id=(p_payload->>'deliveryId')::uuid));
 end if;
 if p_action='outcome' then
  select * into d from intelligence_control.delivery_heads where id=(p_payload->>'deliveryId')::uuid and lease_id=(p_payload->>'leaseId')::uuid for update;
  if not found then raise exception using errcode='42501',message='LEASE_UNAVAILABLE';end if;
  v_state:=p_payload->>'state';status:=(p_payload->>'httpStatus')::integer;
  if v_state not in('acknowledged','retry','unknown','dead_letter') or v_state is null
   or (v_state='acknowledged' and (status is null or status not between 200 and 299))
   or (v_state='unknown' and status is not null) or (v_state in('retry','dead_letter') and (status is null or status between 200 and 299))
   or (v_state='retry' and d.attempt>=8) or (v_state='dead_letter' and d.attempt<>8) then
   raise exception using errcode='22023',message='OUTCOME_MISMATCH';end if;
  select * into o from intelligence_control.delivery_outcomes where tenant_id=d.tenant_id and delivery_id=d.id and attempt=d.attempt;
  if found then
   if o.state<>v_state or o.http_status is distinct from status then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;return '{}'::jsonb;
  end if;
  insert into intelligence_control.delivery_outcomes values(d.tenant_id,d.id,d.attempt,v_state,status,statement_timestamp());
  update intelligence_control.delivery_heads set state=v_state,available_at=statement_timestamp()+make_interval(secs=>least(3600,15*power(2,d.attempt-1)::integer)) where id=d.id;
  return '{}'::jsonb;
 end if;
 if p_action='settle_acknowledged' then
  for d in select * from intelligence_control.delivery_heads h where h.state='acknowledged'
   and not exists(select 1 from intelligence_control.usage_events u where u.tenant_id=h.tenant_id and u.invocation_id=h.invocation_id)
   order by h.id for update skip locked limit 100 loop
   perform api.wave5_settle_usage(d.tenant_id,d.invocation_id,d.usage_event_id,'1');
  end loop;return '{}'::jsonb;
 end if;
 raise exception using errcode='22023',message='VALIDATION_ERROR';
end $$;
revoke all on function api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb) to authenticated;
revoke all on function api.wave5_delivery_worker(text,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_delivery_worker(text,jsonb) to service_role;

create function api.wave5_delivery_review(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_delivery_id uuid,p_review_id uuid,p_action text,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d intelligence_control.delivery_heads%rowtype;r intelligence_control.delivery_reviews%rowtype;next_id uuid;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 select h.* into d from intelligence_control.delivery_heads h join intelligence_control.integration_subscriptions s on s.tenant_id=h.tenant_id and s.id=h.subscription_id
 where h.tenant_id=p_tenant_id and h.id=p_delivery_id and s.legal_entity_id=p_legal_entity_id and s.branch_id is not distinct from p_branch_id for update of h;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 select * into r from intelligence_control.delivery_reviews where id=p_review_id;
 if found then
  if r.tenant_id<>p_tenant_id or r.delivery_id<>p_delivery_id or r.actor_id<>auth.uid() or r.action<>p_action or r.reason<>p_reason then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  select id into next_id from intelligence_control.delivery_heads where replay_of=d.id;
  if next_id is not null then return jsonb_build_object('id',next_id,'state','pending','replayOf',d.id);end if;
  return jsonb_build_object('id',d.id,'state',case when p_action='acknowledged' then 'acknowledged' else 'retry' end);
 end if;
 if p_action not in('replay','acknowledged','not_sent') or p_action is null or p_reason is null
  or length(trim(p_reason)) not between 8 and 500 or p_review_id is null
  or (d.state='unknown' and p_action='replay') or (p_action='replay' and d.state<>'dead_letter')
  or (p_action in('acknowledged','not_sent') and d.state<>'unknown') then
  raise exception using errcode='22023',message='OUTCOME_REVIEW_REQUIRED';end if;
 insert into intelligence_control.delivery_reviews values(p_review_id,p_tenant_id,p_delivery_id,auth.uid(),p_action,p_reason,statement_timestamp());
 -- Each reviewed replay creates a new generation. It preserves the committed
 -- event, original invocation/quota and all earlier immutable attempt identities.
 if p_action='replay' or (p_action='not_sent' and d.attempt>=8) then
  if exists(select 1 from intelligence_control.delivery_heads where replay_of=d.id) then
   raise exception using errcode='40001',message='REPLAY_ALREADY_REVIEWED';end if;
  insert into intelligence_control.delivery_heads(tenant_id,subscription_id,event_id,invocation_id,usage_event_id,period_start,period_end,generation,replay_of)
   values(d.tenant_id,d.subscription_id,d.event_id,d.invocation_id,d.usage_event_id,d.period_start,d.period_end,d.generation+1,d.id) returning id into next_id;
  return jsonb_build_object('id',next_id,'state','pending','replayOf',d.id);
 end if;
 update intelligence_control.delivery_heads set state=case when p_action='acknowledged' then 'acknowledged' else 'retry' end,
  available_at=statement_timestamp() where id=d.id returning * into d;
 return jsonb_build_object('id',d.id,'state',d.state);
end $$;
revoke all on function api.wave5_delivery_review(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function api.wave5_delivery_review(uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;

create function api.wave5_integration_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_subscription_after uuid default null,p_delivery_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;deliveries jsonb;subscription_next text;delivery_next text;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 with selected as (select s.*,row_number() over(order by id) ordinal from intelligence_control.integration_subscriptions s
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id is not distinct from p_branch_id
  and (p_subscription_after is null or id>p_subscription_after) order by id limit 51)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'url',url,'version',version::text,'keyVersion',key_version,'enabled',enabled) order by id)
  filter(where ordinal<=50),'[]'),case when count(*)>50 then max(id::text) filter(where ordinal=50) end
 into rows,subscription_next from selected;
 with selected as (select d.*,row_number() over(order by d.id) ordinal from intelligence_control.delivery_heads d
  join intelligence_control.integration_subscriptions s on s.tenant_id=d.tenant_id and s.id=d.subscription_id
  where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.branch_id is not distinct from p_branch_id
  and (p_delivery_after is null or d.id>p_delivery_after) order by d.id limit 51)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'subscriptionId',subscription_id,'state',state,'attempt',attempt,'generation',generation) order by id)
  filter(where ordinal<=50),'[]'),case when count(*)>50 then max(id::text) filter(where ordinal=50) end
 into deliveries,delivery_next from selected;
 return jsonb_build_object('contractRevision',1,'subscriptions',rows,'deliveries',deliveries,
  'subscriptionNext',subscription_next,'deliveryNext',delivery_next);
end $$;
revoke all on function api.wave5_integration_list(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_integration_list(uuid,uuid,uuid,uuid,uuid) to authenticated;

create function api.wave5_integration_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 return auth.uid();end $$;
revoke all on function api.wave5_integration_authorize(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_integration_authorize(uuid,uuid,uuid) to authenticated;

-- Observations come from durable queue and metering rows, never desktop claims.
-- An absent current quota period remains unknown; it is not published as zero.
create function api.wave5_health_collect(p_collection_id uuid,p_tenant_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare lag_seconds numeric;retries bigint;dead bigint;quota numeric;used numeric;observations jsonb;prior jsonb;r jsonb;begin
 perform intelligence_control.worker_required();
 if p_collection_id is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_collection_id::text,530));
 select jsonb_agg(jsonb_build_object('code',code,'exactValue',exact_value::text,'observedAt',analytics.process_utc(observed_at)) order by code)
  into prior from intelligence_control.health_probes where tenant_id is not distinct from p_tenant_id and id in(
   select md5(p_collection_id::text||':'||code)::uuid from unnest(array['worker_lag_seconds','retry_count','dead_letter_count','quota_remaining'])code);
 if prior is not null then return jsonb_build_object('contractRevision',1,'probes',prior);end if;
 select coalesce(greatest(0,floor(extract(epoch from statement_timestamp()-min(available_at) filter(where state in('pending','retry') and available_at<=statement_timestamp())))),0),
  count(*) filter(where state='retry'),count(*) filter(where state='dead_letter') into lag_seconds,retries,dead
  from intelligence_control.delivery_heads where p_tenant_id is null or tenant_id=p_tenant_id;
 observations:=jsonb_build_array(jsonb_build_object('code','worker_lag_seconds','exactValue',lag_seconds::text),
  jsonb_build_object('code','retry_count','exactValue',retries::text),jsonb_build_object('code','dead_letter_count','exactValue',dead::text));
 if p_tenant_id is not null then
  begin
   quota:=intelligence_control.quota_limit(p_tenant_id,'webhook.deliveries');
   select settled_units+reserved_units into used from intelligence_control.quota_periods where tenant_id=p_tenant_id and metric_code='webhook.deliveries'
    and period_start<=statement_timestamp() and period_end>statement_timestamp();
   if used is not null then observations:=observations||jsonb_build_array(jsonb_build_object('code','quota_remaining','exactValue',greatest(0,quota-used)::text));end if;
  exception when insufficient_privilege then null;end;
 end if;
 select jsonb_agg(value||jsonb_build_object('observedAt',analytics.process_utc(statement_timestamp())) order by value->>'code')
  into observations from jsonb_array_elements(observations);
 for r in select * from jsonb_array_elements(observations) loop
  perform api.record_wave5_health_probe(md5(p_collection_id::text||':'||(r->>'code'))::uuid,p_tenant_id,r->>'code',r->>'exactValue',statement_timestamp());
 end loop;
 return jsonb_build_object('contractRevision',1,'probes',observations);
end $$;
revoke all on function api.wave5_health_collect(uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_health_collect(uuid,uuid) to service_role;
