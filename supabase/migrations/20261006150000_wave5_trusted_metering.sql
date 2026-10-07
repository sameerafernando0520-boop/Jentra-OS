-- Unapplied candidate. Existing billing tables remain the entitlement authority.
-- No plan is enabled and no worker/service credential is provisioned here.
create schema if not exists intelligence_control;
revoke all on schema intelligence_control from public,anon,authenticated;
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
 select code,c,false from billing.plans cross join unnest(array['quota.ai.tokens','quota.webhook.deliveries']) c
 on conflict(plan_code,entitlement_code) do nothing;
create table intelligence_control.quota_periods(
 tenant_id uuid not null references core.tenants(id),metric_code text not null check(metric_code in('ai.tokens','webhook.deliveries')),
 period_start timestamptz not null,period_end timestamptz not null,
 settled_units numeric(20,0) not null default 0 check(settled_units>=0),reserved_units numeric(20,0) not null default 0 check(reserved_units>=0),
 primary key(tenant_id,metric_code,period_start),check(isfinite(period_start) and isfinite(period_end) and period_end>period_start
  and period_end-period_start<=interval '366 days')
);
create table intelligence_control.usage_reservations(
 tenant_id uuid not null,invocation_id uuid not null,metric_code text not null,period_start timestamptz not null,
 reserved_units numeric(20,0) not null check(reserved_units>0),created_at timestamptz not null default statement_timestamp(),
 primary key(tenant_id,invocation_id),foreign key(tenant_id,metric_code,period_start)
  references intelligence_control.quota_periods(tenant_id,metric_code,period_start)
);
create table intelligence_control.usage_events(
 tenant_id uuid not null,invocation_id uuid not null,event_id uuid not null,
 quantity numeric(20,0) not null check(quantity>=0),recorded_at timestamptz not null default statement_timestamp(),
 primary key(tenant_id,event_id),unique(tenant_id,invocation_id),
 foreign key(tenant_id,invocation_id) references intelligence_control.usage_reservations(tenant_id,invocation_id)
);
create table intelligence_control.usage_corrections(
 tenant_id uuid not null,event_id uuid not null,original_event_id uuid not null,
 quantity numeric(20,0) not null check(quantity>0),reason_code text not null check(reason_code in('provider_reconciled','duplicate_source','cancelled_before_send')),
 recorded_at timestamptz not null default statement_timestamp(),primary key(tenant_id,event_id),
 foreign key(tenant_id,original_event_id) references intelligence_control.usage_events(tenant_id,event_id)
);
do $$declare rel text;begin
 foreach rel in array array['quota_periods','usage_reservations','usage_events','usage_corrections'] loop
  execute format('alter table intelligence_control.%I enable row level security',rel);
  execute format('alter table intelligence_control.%I force row level security',rel);
  execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
  if rel<>'quota_periods' then execute format('create trigger immutable_usage before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);end if;
 end loop;
end $$;
create index usage_reservations_period_idx on intelligence_control.usage_reservations(tenant_id,metric_code,period_start,invocation_id);
create index usage_corrections_original_idx on intelligence_control.usage_corrections(tenant_id,original_event_id);

create function intelligence_control.worker_required() returns void language plpgsql stable set search_path='' as $$begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception using errcode='42501',message='TRUSTED_WORKER_REQUIRED';end if;
end $$;
revoke all on function intelligence_control.worker_required() from public,anon,authenticated;
create function intelligence_control.quota_limit(t uuid,metric text) returns numeric language plpgsql stable security definer set search_path='' as $$
declare result numeric;begin
 select p.numeric_limit into result from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
 where s.tenant_id=t and p.entitlement_code='quota.'||metric and p.enabled
 and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp()) or (s.status='active'
  and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())));
 if result is null or result<0 or result<>trunc(result) or result>=100000000000000000000 then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';end if;
 return result;
end $$;
revoke all on function intelligence_control.quota_limit(uuid,text) from public,anon,authenticated;

create function api.wave5_reserve_usage(p_tenant_id uuid,p_invocation_id uuid,p_metric_code text,
 p_period_start timestamptz,p_period_end timestamptz,p_quantity text) returns jsonb
language plpgsql security definer set search_path='' as $$declare q numeric;cap numeric;bucket intelligence_control.quota_periods%rowtype;r intelligence_control.usage_reservations%rowtype;begin
 perform intelligence_control.worker_required();
 if p_tenant_id is null or p_invocation_id is null or p_metric_code is null or p_metric_code not in('ai.tokens','webhook.deliveries') or p_quantity is null
  or p_quantity !~ '^[1-9][0-9]{0,19}$' or p_period_start is null or p_period_end is null
  or not isfinite(p_period_start) or not isfinite(p_period_end) or p_period_start>=p_period_end
  or p_period_end-p_period_start>interval '366 days' or statement_timestamp()<p_period_start or statement_timestamp()>=p_period_end then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 -- Share the billing lock with synthetic plan activation and seat admission.
 perform 1 from billing.tenant_subscriptions where tenant_id=p_tenant_id for update;
 q:=p_quantity::numeric;cap:=intelligence_control.quota_limit(p_tenant_id,p_metric_code);
 if not exists(select 1 from billing.tenant_subscriptions s where s.tenant_id=p_tenant_id and
  ((s.status='trialing' and p_period_start=coalesce(s.trial_started_at,s.created_at) and p_period_end=s.trial_ends_at)
   or (s.status='active' and p_period_end=s.current_period_ends_at))) then
  raise exception using errcode='22023',message='PERIOD_CONFLICT';end if;
 -- Serialize the tenant/metric before choosing the period: overlapping caller-
 -- supplied windows cannot split one allowance into multiple hard-cap buckets.
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_metric_code,5));
 if exists(select 1 from intelligence_control.quota_periods where tenant_id=p_tenant_id and metric_code=p_metric_code
  and period_start<>p_period_start and period_start<p_period_end and period_end>p_period_start) then
  raise exception using errcode='22023',message='PERIOD_CONFLICT';end if;
 insert into intelligence_control.quota_periods(tenant_id,metric_code,period_start,period_end)
  values(p_tenant_id,p_metric_code,p_period_start,p_period_end) on conflict do nothing;
 select * into bucket from intelligence_control.quota_periods where tenant_id=p_tenant_id and metric_code=p_metric_code
  and period_start=p_period_start for update;
 if bucket.period_end<>p_period_end then raise exception using errcode='22023',message='PERIOD_CONFLICT';end if;
 select * into r from intelligence_control.usage_reservations where tenant_id=p_tenant_id and invocation_id=p_invocation_id;
 if found then
  if r.metric_code<>p_metric_code or r.period_start<>p_period_start or r.reserved_units<>q then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  return jsonb_build_object('invocationId',r.invocation_id,'reservedUnits',r.reserved_units::text);
 end if;
 if bucket.settled_units+bucket.reserved_units+q>cap then raise exception using errcode='54000',message='QUOTA_EXCEEDED';end if;
 insert into intelligence_control.usage_reservations values(p_tenant_id,p_invocation_id,p_metric_code,p_period_start,q,statement_timestamp());
 update intelligence_control.quota_periods set reserved_units=reserved_units+q where tenant_id=p_tenant_id and metric_code=p_metric_code and period_start=p_period_start;
 return jsonb_build_object('invocationId',p_invocation_id,'reservedUnits',q::text);
end $$;

create function api.wave5_settle_usage(p_tenant_id uuid,p_invocation_id uuid,p_event_id uuid,p_quantity text) returns jsonb
language plpgsql security definer set search_path='' as $$declare q numeric;r intelligence_control.usage_reservations%rowtype;u intelligence_control.usage_events%rowtype;begin
 perform intelligence_control.worker_required();
 if p_quantity is null or p_quantity !~ '^(0|[1-9][0-9]{0,19})$' or p_event_id is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 q:=p_quantity::numeric;
 select * into r from intelligence_control.usage_reservations where tenant_id=p_tenant_id and invocation_id=p_invocation_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||r.metric_code,5));
 perform 1 from intelligence_control.quota_periods where tenant_id=r.tenant_id and metric_code=r.metric_code and period_start=r.period_start for update;
 select * into u from intelligence_control.usage_events where tenant_id=p_tenant_id and invocation_id=p_invocation_id;
 if found then
  if u.event_id<>p_event_id or u.quantity<>q then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  return jsonb_build_object('eventId',u.event_id,'quantity',u.quantity::text);
 end if;
 if q>r.reserved_units then raise exception using errcode='54000',message='RESERVATION_EXCEEDED';end if;
 insert into intelligence_control.usage_events values(p_tenant_id,p_invocation_id,p_event_id,q,statement_timestamp());
 update intelligence_control.quota_periods set reserved_units=reserved_units-r.reserved_units,settled_units=settled_units+q
  where tenant_id=r.tenant_id and metric_code=r.metric_code and period_start=r.period_start;
 return jsonb_build_object('eventId',p_event_id,'quantity',q::text);
end $$;

create function api.wave5_correct_usage(p_tenant_id uuid,p_event_id uuid,p_original_event_id uuid,p_quantity text,p_reason_code text) returns void
language plpgsql security definer set search_path='' as $$declare q numeric;total numeric;r intelligence_control.usage_reservations%rowtype;u intelligence_control.usage_events%rowtype;c intelligence_control.usage_corrections%rowtype;begin
 perform intelligence_control.worker_required();
 if p_quantity is null or p_quantity !~ '^[1-9][0-9]{0,19}$' or p_event_id is null or p_reason_code is null or p_reason_code not in('provider_reconciled','duplicate_source','cancelled_before_send') then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 q:=p_quantity::numeric;
 select * into u from intelligence_control.usage_events where tenant_id=p_tenant_id and event_id=p_original_event_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 select * into r from intelligence_control.usage_reservations where tenant_id=p_tenant_id and invocation_id=u.invocation_id;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||r.metric_code,5));
 perform 1 from intelligence_control.quota_periods where tenant_id=r.tenant_id and metric_code=r.metric_code and period_start=r.period_start for update;
 select * into c from intelligence_control.usage_corrections where tenant_id=p_tenant_id and event_id=p_event_id;
 if found then
  if c.original_event_id<>p_original_event_id or c.quantity<>q or c.reason_code<>p_reason_code then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;return;
 end if;
 select coalesce(sum(quantity),0) into total from intelligence_control.usage_corrections where tenant_id=p_tenant_id and original_event_id=p_original_event_id;
 if total+q>u.quantity then raise exception using errcode='22023',message='CORRECTION_EXCEEDED';end if;
 insert into intelligence_control.usage_corrections values(p_tenant_id,p_event_id,p_original_event_id,q,p_reason_code,statement_timestamp());
 update intelligence_control.quota_periods set settled_units=settled_units-q where tenant_id=r.tenant_id and metric_code=r.metric_code and period_start=r.period_start;
end $$;

create function api.get_wave5_usage_allowance(p_tenant_id uuid,p_metric_code text,p_period_start timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare b intelligence_control.quota_periods%rowtype;cap numeric;begin
 perform core.require_permission(p_tenant_id,'billing.read',null,null);
 cap:=intelligence_control.quota_limit(p_tenant_id,p_metric_code);
 select * into b from intelligence_control.quota_periods where tenant_id=p_tenant_id and metric_code=p_metric_code and period_start=p_period_start;
 if not found then return jsonb_build_object('state','unavailable','reason','PERIOD_NOT_RESERVED','limit',cap::numeric(20,0)::text);end if;
 return jsonb_build_object('state','available','tenantId',p_tenant_id,'metricCode',p_metric_code,'periodStart',analytics.process_utc(b.period_start),'periodEnd',analytics.process_utc(b.period_end),
  'limit',cap::numeric(20,0)::text,'settled',b.settled_units::text,'reserved',b.reserved_units::text,'remaining',greatest(cap-b.settled_units-b.reserved_units,0)::numeric(20,0)::text,
  'generatedAt',analytics.process_utc(statement_timestamp()));
end $$;
revoke all on function api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text),api.wave5_settle_usage(uuid,uuid,uuid,text),
 api.wave5_correct_usage(uuid,uuid,uuid,text,text),api.get_wave5_usage_allowance(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text),api.wave5_settle_usage(uuid,uuid,uuid,text),
 api.wave5_correct_usage(uuid,uuid,uuid,text,text) to service_role;
grant execute on function api.get_wave5_usage_allowance(uuid,text,timestamptz) to authenticated;
