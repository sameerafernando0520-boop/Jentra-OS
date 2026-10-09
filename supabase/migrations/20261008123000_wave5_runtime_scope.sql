-- UNAPPLIED. Runtime adapter only; no account, scope, key or operator is seeded.
-- Derived delivery body SHA256 1a636229a0749cf9d6334ae49efe8ff38627b6a2d1bb642789a28e86efd1c663.
-- Keeps the earlier candidate and all Wave 3/4 sources byte-for-byte unchanged.
create table intelligence_control.runtime_worker_scopes(
 runtime_id uuid not null,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 enabled boolean not null default false,issued_at timestamptz not null default statement_timestamp(),expires_at timestamptz not null,
 primary key(runtime_id,tenant_id,legal_entity_id,branch_id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(isfinite(expires_at) and expires_at>issued_at and expires_at<=issued_at+interval '7 days'));
alter table intelligence_control.runtime_worker_scopes enable row level security;
alter table intelligence_control.runtime_worker_scopes force row level security;
revoke all on intelligence_control.runtime_worker_scopes from public,anon,authenticated;

create function intelligence_control.runtime_scope_allowed(r uuid,t uuid,e uuid,b uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from intelligence_control.runtime_worker_scopes s join core.branches br
  on br.tenant_id=s.tenant_id and br.legal_entity_id=s.legal_entity_id and br.id=s.branch_id
  where s.runtime_id=r and s.tenant_id=t and s.legal_entity_id=e and s.branch_id=b
   and s.enabled and s.issued_at<=statement_timestamp() and s.expires_at>statement_timestamp() and br.status='active')$$;
create function intelligence_control.runtime_tenant_allowed(r uuid,t uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from intelligence_control.runtime_worker_scopes s
  where s.runtime_id=r and s.tenant_id=t and intelligence_control.runtime_scope_allowed(r,t,s.legal_entity_id,s.branch_id))$$;
create function intelligence_control.runtime_worker_required(r uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 perform intelligence_control.worker_required();
 if not exists(select 1 from intelligence_control.runtime_worker_scopes s
  where s.runtime_id=r and intelligence_control.runtime_scope_allowed(r,s.tenant_id,s.legal_entity_id,s.branch_id)) then
  raise exception using errcode='42501',message='RUNTIME_SCOPE_DENIED';end if;end$$;
revoke all on function intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid),
 intelligence_control.runtime_tenant_allowed(uuid,uuid),intelligence_control.runtime_worker_required(uuid) from public,anon,authenticated;

-- The separately designated operator can exercise the installed real MFA grant
-- API only within the exact owner-approved tenant/reason/deadline. Other operator
-- records and existing installed functions retain their contracts.
create table intelligence_control.runtime_operator_authorities(
 operator_id uuid primary key references intelligence_control.operators(actor_id),
 tenant_id uuid not null references core.tenants(id),reason text not null,
 issued_at timestamptz not null default statement_timestamp(),expires_at timestamptz not null,
 check(length(trim(reason)) between 10 and 500),
 check(isfinite(expires_at) and expires_at>issued_at and expires_at<=issued_at+interval '45 minutes'));
alter table intelligence_control.runtime_operator_authorities enable row level security;
alter table intelligence_control.runtime_operator_authorities force row level security;
revoke all on intelligence_control.runtime_operator_authorities from public,anon,authenticated;
create trigger immutable before update or delete on intelligence_control.runtime_operator_authorities
 for each row execute function analytics.immutable_evidence();
create function intelligence_control.runtime_operator_guard() returns trigger
language plpgsql security definer set search_path='' as $$declare a intelligence_control.runtime_operator_authorities%rowtype;begin
 select * into a from intelligence_control.runtime_operator_authorities where operator_id in(new.operator_id,new.issued_by)
  order by case when operator_id=new.issued_by then 0 else 1 end limit 1;
 if found and (new.operator_id<>a.operator_id or new.tenant_id<>a.tenant_id or new.issued_by<>a.operator_id or auth.uid() is distinct from a.operator_id
  or new.reason<>a.reason or new.issued_at<a.issued_at or new.issued_at>=a.expires_at or new.expires_at>a.expires_at) then
  raise exception using errcode='42501',message='RUNTIME_OPERATOR_SCOPE_DENIED';end if;
 return new;end$$;
revoke all on function intelligence_control.runtime_operator_guard() from public,anon,authenticated;
create trigger runtime_operator_scope before insert on intelligence_control.operator_tenant_grants
 for each row execute function intelligence_control.runtime_operator_guard();
create function api.wave5_runtime_delivery_worker(p_runtime_id uuid,p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d intelligence_control.delivery_heads%rowtype;s intelligence_control.integration_subscriptions%rowtype;
 o intelligence_control.delivery_outcomes%rowtype;subscription billing.tenant_subscriptions%rowtype;v_state text;status integer;begin
 perform intelligence_control.runtime_worker_required(p_runtime_id);
 if p_action not in('readiness','claim','settle_acknowledged') and not exists(
  select 1 from intelligence_control.delivery_heads h join intelligence_control.integration_subscriptions s0
   on s0.tenant_id=h.tenant_id and s0.id=h.subscription_id
  where h.id=(p_payload->>'deliveryId')::uuid
   and intelligence_control.runtime_scope_allowed(p_runtime_id,s0.tenant_id,s0.legal_entity_id,s0.branch_id)) then
  raise exception using errcode='42501',message='RUNTIME_SCOPE_DENIED';end if;
 if p_action='readiness' then return jsonb_build_object('contractRevision',1,'ready',true,'providers',jsonb_build_object('committed_webhook.v1',1,'synthetic_subscription.v1',1));end if;
 if p_action='claim' then
  -- A lease lost after send cannot be auto-retried. ACK rows can be reconciled
  -- separately; expired attempts with no outcome retain uncertain reservations.
  update intelligence_control.delivery_heads set state='unknown' where state='leased' and lease_until<=statement_timestamp()
   and exists(select 1 from intelligence_control.integration_subscriptions s0
    where s0.id=subscription_id and s0.tenant_id=delivery_heads.tenant_id
     and intelligence_control.runtime_scope_allowed(p_runtime_id,s0.tenant_id,s0.legal_entity_id,s0.branch_id));
  insert into intelligence_control.delivery_heads(tenant_id,subscription_id,event_id)
   select s0.tenant_id,s0.id,e.id from intelligence_control.integration_subscriptions s0
   join analytics.pipeline_forecasts f on f.tenant_id=s0.tenant_id and f.legal_entity_id=s0.legal_entity_id and f.branch_id is not distinct from s0.branch_id
   join core.outbox_events e on e.tenant_id=f.tenant_id and e.aggregate_id=f.id and e.aggregate_type='pipeline_forecast' and e.topic='analytics.freeze_pipeline'
   where s0.enabled and intelligence_control.runtime_scope_allowed(p_runtime_id,s0.tenant_id,s0.legal_entity_id,s0.branch_id)
    and e.created_at>=s0.created_at and not exists(select 1 from intelligence_control.delivery_heads h
    where h.tenant_id=s0.tenant_id and h.subscription_id=s0.id and h.event_id=e.id and h.generation=0)
   order by e.created_at,e.id limit 1000 on conflict do nothing;
  select h.* into d from intelligence_control.delivery_heads h where
   exists(select 1 from intelligence_control.integration_subscriptions s0 where s0.tenant_id=h.tenant_id and s0.id=h.subscription_id
    and intelligence_control.runtime_scope_allowed(p_runtime_id,s0.tenant_id,s0.legal_entity_id,s0.branch_id))
   and state in('pending','retry') and available_at<=statement_timestamp()
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
  for d in select * from intelligence_control.delivery_heads h where h.state='acknowledged' and exists(
   select 1 from intelligence_control.integration_subscriptions s0 where s0.tenant_id=h.tenant_id and s0.id=h.subscription_id
    and intelligence_control.runtime_scope_allowed(p_runtime_id,s0.tenant_id,s0.legal_entity_id,s0.branch_id))
   and not exists(select 1 from intelligence_control.usage_events u where u.tenant_id=h.tenant_id and u.invocation_id=h.invocation_id)
   order by h.id for update skip locked limit 100 loop
   perform api.wave5_settle_usage(d.tenant_id,d.invocation_id,d.usage_event_id,'1');
  end loop;return '{}'::jsonb;
 end if;
 raise exception using errcode='22023',message='VALIDATION_ERROR';
end $$;
revoke all on function api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb) to authenticated;

revoke all on function api.wave5_runtime_delivery_worker(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_runtime_delivery_worker(uuid,text,jsonb) to service_role;

create function api.wave5_runtime_worker(p_runtime_id uuid,p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare tenant uuid;entity uuid;branch uuid;s jsonb;rows jsonb;n integer;cursor uuid;begin
 perform intelligence_control.runtime_worker_required(p_runtime_id);
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_action like 'delivery.%' then
  return api.wave5_runtime_delivery_worker(p_runtime_id,substring(p_action from 10),p_payload);end if;
 if p_action='model.readiness' then return api.wave5_model_worker('readiness',p_payload);end if;
 if p_action like 'external.%' then
  select tenant_id,legal_entity_id,branch_id into tenant,entity,branch from intelligence_control.integration_credentials
   where token_hash=p_payload->>'tokenHash';
 elsif p_action='model.begin' then
  select f.tenant_id,f.legal_entity_id,f.branch_id into tenant,entity,branch from analytics.pipeline_forecasts f
   where f.tenant_id=(p_payload->>'tenantId')::uuid and f.id=(p_payload->>'sourceId')::uuid;
 elsif p_action='model.outcome' then
  select f.tenant_id,f.legal_entity_id,f.branch_id into tenant,entity,branch from intelligence_control.model_invocations i
   join analytics.pipeline_forecasts f on f.tenant_id=i.tenant_id and f.id=i.source_id
   where i.invocation_id=(p_payload->>'invocationId')::uuid;
 elsif p_action='entitlement' then
  s:=p_payload->'scope';tenant:=(s->>'tenantId')::uuid;entity:=(s->>'legalEntityId')::uuid;branch:=(s->>'branchId')::uuid;
 elsif p_action in('usage.reserve','usage.settle','subscription.apply','health.collect') then
  tenant:=(p_payload->>'tenantId')::uuid;
  if not intelligence_control.runtime_tenant_allowed(p_runtime_id,tenant) then
   raise exception using errcode='42501',message='RUNTIME_SCOPE_DENIED';end if;
  if p_action='usage.reserve' then return api.wave5_reserve_usage(tenant,(p_payload->>'invocationId')::uuid,p_payload->>'metric',
   (p_payload->>'periodStart')::timestamptz,(p_payload->>'periodEnd')::timestamptz,p_payload->>'quantity');end if;
  if p_action='usage.settle' then return api.wave5_settle_usage(tenant,(p_payload->>'invocationId')::uuid,(p_payload->>'eventId')::uuid,p_payload->>'quantity');end if;
  if p_action='subscription.apply' then return api.apply_synthetic_subscription(tenant,(p_payload->>'revisionId')::uuid);end if;
  return api.wave5_health_collect((p_payload->>'collectionId')::uuid,tenant);
 elsif p_action='subscription.due' then
  select coalesce(jsonb_agg(jsonb_build_object('tenantId',tenant_id,'revisionId',id) order by id),'[]'),count(*) into rows,n
   from(select r.id,r.tenant_id from intelligence_control.subscription_revisions r
    join intelligence_control.synthetic_tenants t on t.tenant_id=r.tenant_id and t.allowed
    where intelligence_control.runtime_tenant_allowed(p_runtime_id,r.tenant_id)
     and r.trial_starts_at<=statement_timestamp() and r.trial_ends_at>statement_timestamp()
     and (p_payload->>'after' is null or r.id>(p_payload->>'after')::uuid)
     and not exists(select 1 from intelligence_control.subscription_activations a where a.tenant_id=r.tenant_id and a.revision_id=r.id)
     order by r.id limit 51) q;
  if n>50 then cursor:=(rows->49->>'revisionId')::uuid;rows:=rows-50;end if;
  return jsonb_build_object('contractRevision',1,'items',rows,'nextCursor',cursor);
 else raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if not intelligence_control.runtime_scope_allowed(p_runtime_id,tenant,entity,branch) then
  raise exception using errcode='42501',message='RUNTIME_SCOPE_DENIED';end if;
 if p_action in('external.credential','external.reserve','external.dispatch') then
  return api.wave5_external_worker(substring(p_action from 10),p_payload);end if;
 if p_action='model.begin' then
  perform pg_advisory_xact_lock(hashtextextended(tenant::text||':wave5-runtime-model-budget',531));
  if not exists(select 1 from intelligence_control.model_invocations where invocation_id=(p_payload->>'invocationId')::uuid)
   and (select count(*) from intelligence_control.model_invocations where tenant_id=tenant)>=4 then
   raise exception using errcode='54000',message='MODEL_CALL_LIMIT';end if;
  if coalesce(p_payload->>'maxTokens','')!~ '^[1-9][0-9]{0,3}$' or (p_payload->>'maxTokens')::numeric>2000 then
   raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 end if;
 if p_action in('model.begin','model.outcome') then return api.wave5_model_worker(substring(p_action from 7),p_payload);end if;
 if p_action='entitlement' then return to_jsonb(api.wave5_worker_entitlement(s));end if;
 raise exception using errcode='22023',message='VALIDATION_ERROR';
end$$;
revoke all on function api.wave5_runtime_worker(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_runtime_worker(uuid,text,jsonb) to service_role;
