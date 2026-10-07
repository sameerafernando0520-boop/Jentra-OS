begin;
-- Unapplied Wave 5 read candidate. Does not modify producers or enable plans.
create schema if not exists analytics;
revoke all on schema analytics from public,anon,authenticated;
create index wave5_process_cohort_idx on workflow.process_events(tenant_id,legal_entity_id,entered_at,id)
include(branch_id,document_id,created_at) where document_type='crm_opportunity';

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
   ('active_minutes','numeric'::regtype),('wait_minutes','numeric'::regtype)))<>11
  or (select count(*) from pg_attribute where attrelid='workflow.process_events'::regclass and not attisdropped
    and attname in ('active_minutes','wait_minutes') and atttypmod=1310730)<>2 then
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
   and (ev.branch_id is null or exists(select 1 from core.branches b where b.tenant_id=ev.tenant_id
     and b.legal_entity_id=ev.legal_entity_id and b.id=ev.branch_id and b.status='active'))
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

create function api.analytics_process_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)
returns void language sql stable security definer set search_path='' as $$select analytics.process_access(p_tenant_id,p_legal_entity_id,p_branch_id)$$;
revoke all on function api.analytics_process_authorize(uuid,uuid,uuid) from public,anon;
grant execute on function api.analytics_process_authorize(uuid,uuid,uuid) to authenticated;

-- Unapplied synthetic-development candidate. Current observations are frozen;
-- this does not reconstruct historical CRM revisions or enable entitlements.
create function analytics.pipeline_access(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception using errcode='42501',message='AUTH_REQUIRED';end if;
 perform core.wave3_require_scope(t,'analytics.view',e,b);
 if e is null or not (core.has_permission(t,'crm.opportunities.view',e,b)
  or core.has_permission(t,'crm.opportunities.manage',e,b)) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and s.trial_ends_at>current_timestamp)
    or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>current_timestamp)))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';end if;
end $$;
revoke all on function analytics.pipeline_access(uuid,uuid,uuid) from public,anon,authenticated;

create table analytics.pipeline_forecasts(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,
 legal_entity_id uuid not null,branch_id uuid,created_by uuid not null references auth.users(id),
 horizon_start date not null,horizon_end date not null,observed_at timestamptz not null,
 definition_version integer not null default 1 check(definition_version=1),
 source_contract text not null default 'crm.opportunities.current.v1' check(source_contract='crm.opportunities.current.v1'),
 canonical_text text not null check(octet_length(canonical_text)<=8388608),
 source_hash text not null check(source_hash ~ '^[0-9a-f]{64}$'),
 evidence jsonb not null check(jsonb_typeof(evidence)='object'),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(horizon_end>horizon_start and horizon_end-horizon_start<=366),
 check(source_hash=encode(extensions.digest(convert_to(canonical_text,'UTF8'),'sha256'),'hex'))
);
alter table analytics.pipeline_forecasts enable row level security;
alter table analytics.pipeline_forecasts force row level security;
revoke all on analytics.pipeline_forecasts from public,anon,authenticated;
create index pipeline_forecasts_scope_idx on analytics.pipeline_forecasts(tenant_id,legal_entity_id,branch_id,observed_at,id);
create index pipeline_forecasts_actor_idx on analytics.pipeline_forecasts(created_by);
create function analytics.immutable_evidence() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='IMMUTABLE_EVIDENCE';end $$;
revoke all on function analytics.immutable_evidence() from public,anon,authenticated;
create trigger pipeline_forecast_immutable before update or delete on analytics.pipeline_forecasts
 for each row execute function analytics.immutable_evidence();

create function api.analytics_pipeline_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns void
language sql stable security definer set search_path='' as $$select analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id)$$;

create function api.freeze_pipeline_forecast(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_horizon_start date,p_horizon_end date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare request_hash text;replayed jsonb;rows jsonb;groups jsonb;n integer;g integer;
 observed timestamptz:=statement_timestamp();canonical text;evidence jsonb;identity uuid:=gen_random_uuid();result jsonb;
begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null or not isfinite(p_client_timestamp)
  or p_horizon_start is null or p_horizon_end is null or not isfinite(p_horizon_start) or not isfinite(p_horizon_end)
  or p_horizon_start>=p_horizon_end then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_horizon_end-p_horizon_start>366 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 request_hash:=core.wave3_request_hash('analytics.freeze_pipeline',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,
  jsonb_build_object('start',p_horizon_start,'end',p_horizon_end,'client',p_client_timestamp),null);
 replayed:=core.wave3_replay(p_tenant_id,'analytics.freeze_pipeline',p_command_id,p_idempotency_key,request_hash);
 if replayed is not null then return replayed;end if;
 if (select count(*) from pg_attribute where attrelid='crm.opportunities'::regclass and not attisdropped
  and (attname,atttypid) in (('version','bigint'::regtype),('expected_close_date','date'::regtype),
   ('currency_code','text'::regtype),('probability','numeric'::regtype),('expected_value','numeric'::regtype)))<>5
  or (select atttypmod from pg_attribute where attrelid='crm.opportunities'::regclass and attname='expected_value')<>1310730
  or (select atttypmod from pg_attribute where attrelid='crm.opportunities'::regclass and attname='probability')<>327686 then
   raise exception using errcode='55000',message='CONTRACT_MISMATCH';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'version',o.version::text,
  'tenantId',o.tenant_id,'legalEntityId',o.legal_entity_id,'branchId',o.branch_id,
  'amount',o.expected_value::text,'probability',o.probability::text,'currency',o.currency_code,
  'expectedCloseDate',o.expected_close_date) order by o.id),'[]'),count(*) into rows,n
 from (select o.* from crm.opportunities o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or o.branch_id=p_branch_id) and o.status='open'
  and o.stage not in('rejected','cancelled','closed') and o.expected_close_date>=p_horizon_start and o.expected_close_date<p_horizon_end
  and (o.branch_id is null or exists(select 1 from core.branches b where b.tenant_id=o.tenant_id and b.legal_entity_id=o.legal_entity_id
    and b.id=o.branch_id and b.status='active'))
  and (core.has_permission(o.tenant_id,'crm.opportunities.view',o.legal_entity_id,o.branch_id)
   or core.has_permission(o.tenant_id,'crm.opportunities.manage',o.legal_entity_id,o.branch_id)) order by o.id limit 10001) o;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('currency',currency,'population',population,
   'amount',amount::text,'weightedAmount',weighted::text) order by currency),'[]'),count(*) into groups,g from (
   select x->>'currency' as currency,count(*) population,sum((x->>'amount')::numeric) amount,
    sum(round((x->>'amount')::numeric*(x->>'probability')::numeric/100,6)) weighted from jsonb_array_elements(rows) x group by x->>'currency') a;
 if g>100 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 evidence:=jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id,
  'definitionCode','pipeline.current_weighted','definitionVersion',1,'sourceContract','crm.opportunities.current.v1',
  'horizonStart',p_horizon_start,'horizonEnd',p_horizon_end,'asOf',analytics.process_utc(observed),
  'recordedThrough',analytics.process_utc(observed),'generatedAt',analytics.process_utc(observed),
  'complete',true,'sourceCount',n,'observations',rows,'currencies',groups,
  'unavailable',jsonb_build_object('conversion','HISTORICAL_REVISIONS_UNAVAILABLE','aging','STAGE_HISTORY_UNAVAILABLE',
    'velocity','HISTORICAL_REVISIONS_UNAVAILABLE','accuracy','REALIZED_MAPPING_UNAVAILABLE'));
 canonical:=evidence::text;
 if octet_length(canonical)>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 insert into analytics.pipeline_forecasts(id,tenant_id,legal_entity_id,branch_id,created_by,horizon_start,horizon_end,
  observed_at,canonical_text,source_hash,evidence) values(identity,p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),
   p_horizon_start,p_horizon_end,observed,canonical,encode(extensions.digest(convert_to(canonical,'UTF8'),'sha256'),'hex'),evidence);
 result:=jsonb_build_object('id',identity,'version','1','definitionVersion',1,'sourceHash',encode(extensions.digest(convert_to(canonical,'UTF8'),'sha256'),'hex'));
 return core.wave3_finish_command(p_tenant_id,'analytics.freeze_pipeline',p_command_id,'pipeline_forecast',identity,p_idempotency_key,
  request_hash,null,result,p_legal_entity_id,p_branch_id);
end $$;

create function api.get_pipeline_forecast(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_forecast_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare f analytics.pipeline_forecasts%rowtype;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 select * into f from analytics.pipeline_forecasts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id is not distinct from p_branch_id and id=p_forecast_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 -- Recheck every frozen source branch. Entity-wide selection must not permit a
 -- later loss of a source scope to reveal the previously captured values.
 if exists(select 1 from jsonb_array_elements(f.evidence->'observations') x where
  not (core.has_permission(p_tenant_id,'crm.opportunities.view',p_legal_entity_id,(x->>'branchId')::uuid)
   or core.has_permission(p_tenant_id,'crm.opportunities.manage',p_legal_entity_id,(x->>'branchId')::uuid))
  or ((x->>'branchId') is not null and not exists(select 1 from core.branches b where b.tenant_id=p_tenant_id
    and b.legal_entity_id=p_legal_entity_id and b.id=(x->>'branchId')::uuid and b.status='active'))) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 return jsonb_build_object('id',f.id,'canonicalText',f.canonical_text,'sourceHash',f.source_hash,'evidence',f.evidence);
end $$;
revoke all on function api.analytics_pipeline_authorize(uuid,uuid,uuid),
 api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date),api.get_pipeline_forecast(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.analytics_pipeline_authorize(uuid,uuid,uuid),
 api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date),api.get_pipeline_forecast(uuid,uuid,uuid,uuid) to authenticated;

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
 and ((s.status='trialing' and s.trial_ends_at>statement_timestamp()) or (s.status='active'
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
 q:=p_quantity::numeric;cap:=intelligence_control.quota_limit(p_tenant_id,p_metric_code);
 if not exists(select 1 from billing.tenant_subscriptions s where s.tenant_id=p_tenant_id and
  ((s.status='trialing' and p_period_start=s.created_at and p_period_end=s.trial_ends_at)
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
 return jsonb_build_object('state','available','tenantId',p_tenant_id,'metricCode',p_metric_code,'periodStart',b.period_start,'periodEnd',b.period_end,
  'limit',cap::numeric(20,0)::text,'settled',b.settled_units::text,'reserved',b.reserved_units::text,'remaining',greatest(cap-b.settled_units-b.reserved_units,0)::numeric(20,0)::text,
  'generatedAt',statement_timestamp());
end $$;
revoke all on function api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text),api.wave5_settle_usage(uuid,uuid,uuid,text),
 api.wave5_correct_usage(uuid,uuid,uuid,text,text),api.get_wave5_usage_allowance(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text),api.wave5_settle_usage(uuid,uuid,uuid,text),
 api.wave5_correct_usage(uuid,uuid,uuid,text,text) to service_role;
grant execute on function api.get_wave5_usage_allowance(uuid,text,timestamptz) to authenticated;

-- Separate operator authority; no operators or access grants are seeded.
create table intelligence_control.operators(
 actor_id uuid primary key references auth.users(id),active boolean not null default false,
 health_read boolean not null default false,grant_manage boolean not null default false
);
revoke all on intelligence_control.operators from public,anon,authenticated;
alter table intelligence_control.operators enable row level security;
alter table intelligence_control.operators force row level security;
create table intelligence_control.operator_tenant_grants(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),
 operator_id uuid not null references intelligence_control.operators(actor_id),issued_by uuid not null references auth.users(id),
 reason text not null check(length(trim(reason)) between 10 and 500),issued_at timestamptz not null default statement_timestamp(),
 expires_at timestamptz not null,unique(tenant_id,id),
 check(isfinite(expires_at) and expires_at>issued_at and expires_at-issued_at<=interval '1 hour')
);
create table intelligence_control.operator_access_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,grant_id uuid not null,actor_id uuid not null references auth.users(id),
 recorded_at timestamptz not null default statement_timestamp(),foreign key(tenant_id,grant_id)
 references intelligence_control.operator_tenant_grants(tenant_id,id)
);
create table intelligence_control.health_probes(
 id uuid primary key default gen_random_uuid(),tenant_id uuid references core.tenants(id),
 code text not null check(code in('worker_lag_seconds','retry_count','dead_letter_count','quota_remaining')),
 exact_value numeric(20,0) not null check(exact_value>=0),observed_at timestamptz not null,
 contract_revision integer not null check(contract_revision=1),check(isfinite(observed_at))
);
do $$declare rel text;begin foreach rel in array array['operator_tenant_grants','operator_access_events','health_probes'] loop
 execute format('alter table intelligence_control.%I enable row level security',rel);
 execute format('alter table intelligence_control.%I force row level security',rel);
 execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
 execute format('create trigger immutable_operator_evidence before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);
end loop;end$$;
create index operator_grants_scope_idx on intelligence_control.operator_tenant_grants(tenant_id,operator_id,expires_at,id);
create index operator_grants_issuer_idx on intelligence_control.operator_tenant_grants(issued_by);
create index operator_access_actor_idx on intelligence_control.operator_access_events(actor_id,recorded_at);
create index operator_access_grant_idx on intelligence_control.operator_access_events(tenant_id,grant_id);
create index health_probes_scope_idx on intelligence_control.health_probes(tenant_id,code,observed_at desc,id);

create function intelligence_control.operator_required(cap text) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' or not exists(select 1 from intelligence_control.operators
  where actor_id=auth.uid() and active and case cap when 'health' then health_read when 'grant' then grant_manage else false end) then
  raise exception using errcode='42501',message='OPERATOR_ACCESS_REQUIRED';end if;
end $$;
revoke all on function intelligence_control.operator_required(text) from public,anon,authenticated;

create function api.issue_operator_tenant_grant(p_tenant_id uuid,p_operator_id uuid,p_reason text,p_expires_at timestamptz,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare h text;replayed jsonb;identity uuid:=gen_random_uuid();entity jsonb;begin
 perform intelligence_control.operator_required('grant');
 if p_reason is null or length(trim(p_reason)) not between 10 and 500 or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at<=statement_timestamp() or p_expires_at-statement_timestamp()>interval '1 hour' then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if not exists(select 1 from core.tenants where id=p_tenant_id) or not exists(select 1 from intelligence_control.operators
  where actor_id=p_operator_id and active and health_read) then raise exception using errcode='42501',message='OPERATOR_ACCESS_REQUIRED';end if;
 h:=core.wave2_request_hash('operator.issue_grant',p_tenant_id,null,jsonb_build_object('operator',p_operator_id,'reason',p_reason,'expires',p_expires_at),null);
 replayed:=core.wave2_replay(p_tenant_id,'operator.issue_grant',p_idempotency_key,h);
 if replayed is not null then return replayed;end if;
 insert into intelligence_control.operator_tenant_grants(id,tenant_id,operator_id,issued_by,reason,expires_at)
  values(identity,p_tenant_id,p_operator_id,auth.uid(),trim(p_reason),p_expires_at);
 entity:=jsonb_build_object('id',identity,'version','1','operatorId',p_operator_id,'expiresAt',p_expires_at);
 -- Operator authority is independent of tenant membership. The existing Wave 2
 -- receipt/audit/outbox helper supports this reviewed separate authority.
 return core.wave2_finish_command(p_tenant_id,'operator.issue_grant','operator_tenant_grant',identity,p_idempotency_key,h,null,entity);
end $$;

create function intelligence_control.health_projection(t uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('contractRevision',1,'generatedAt',statement_timestamp(),'probes',jsonb_agg(
  jsonb_build_object('code',codes.code,'state',case when p.observed_at is null or p.observed_at>statement_timestamp()
   or p.observed_at<statement_timestamp()-interval '5 minutes' then 'unknown' else 'observed' end,
   'exactValue',case when p.observed_at<=statement_timestamp() and p.observed_at>=statement_timestamp()-interval '5 minutes'
    then p.exact_value::text else null end,'observedAt',p.observed_at) order by codes.code))
 from unnest(array['worker_lag_seconds','retry_count','dead_letter_count','quota_remaining']) codes(code)
 left join lateral(select exact_value,observed_at from intelligence_control.health_probes
  where tenant_id is not distinct from t and code=codes.code order by observed_at desc,id limit 1) p on true
$$;
revoke all on function intelligence_control.health_projection(uuid) from public,anon,authenticated;
create function api.get_operator_health() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform intelligence_control.operator_required('health');return intelligence_control.health_projection(null);end$$;
create function api.get_operator_tenant_health(p_tenant_id uuid,p_grant_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform intelligence_control.operator_required('health');
 if not exists(select 1 from intelligence_control.operator_tenant_grants where id=p_grant_id and tenant_id=p_tenant_id
  and operator_id=auth.uid() and issued_at<=statement_timestamp() and expires_at>statement_timestamp()) then
  raise exception using errcode='42501',message='OPERATOR_ACCESS_REQUIRED';end if;
 insert into intelligence_control.operator_access_events(tenant_id,grant_id,actor_id) values(p_tenant_id,p_grant_id,auth.uid());
 return intelligence_control.health_projection(p_tenant_id);
end $$;
create function api.record_wave5_health_probe(p_id uuid,p_tenant_id uuid,p_code text,p_value text,p_observed_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$declare prior intelligence_control.health_probes%rowtype;begin
 perform intelligence_control.worker_required();
 if p_id is null or p_code is null or p_code not in('worker_lag_seconds','retry_count','dead_letter_count','quota_remaining')
  or p_value is null or p_value !~ '^(0|[1-9][0-9]{0,19})$' or p_observed_at is null or not isfinite(p_observed_at)
  or p_observed_at>statement_timestamp() then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,7));
 select * into prior from intelligence_control.health_probes where id=p_id;
 if found then
  if prior.tenant_id is distinct from p_tenant_id or prior.code<>p_code or prior.exact_value<>p_value::numeric or prior.observed_at<>p_observed_at then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;return;
 end if;
 insert into intelligence_control.health_probes values(p_id,p_tenant_id,p_code,p_value::numeric,p_observed_at,1);
end $$;
revoke all on function api.issue_operator_tenant_grant(uuid,uuid,text,timestamptz,uuid),api.get_operator_health(),
 api.get_operator_tenant_health(uuid,uuid),api.record_wave5_health_probe(uuid,uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function api.issue_operator_tenant_grant(uuid,uuid,text,timestamptz,uuid),api.get_operator_health(),api.get_operator_tenant_health(uuid,uuid) to authenticated;
grant execute on function api.record_wave5_health_probe(uuid,uuid,text,text,timestamptz) to service_role;

-- Synthetic namespace; included after the candidate inside one strict rollback.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table w5_tap(message text);
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
insert into w5_tap select is((select result#>>'{source,sourceCount}' from w5_results),'3','Complete authorized cohort captured');
insert into w5_tap select is((select result#>>'{source,complete}' from w5_results),'true','Complete manifest advertised only after bounded query');
insert into w5_tap select ok((select result#>>'{source,sourceManifestHash}' ~ '^[0-9a-f]{64}$' from w5_results),'Canonical SHA256 captured');
insert into w5_tap select ok((select result::text not like '%PRIVATE TEST REASON%' and result::text not like '%actorId%' and result::text not like '%ownerId%' from w5_results),'Private reason and identities omitted');
insert into w5_tap select is((select count(*) from jsonb_array_elements((select result->'observations' from w5_results)) x where x->>'completedAt'='2026-09-01T00:00:00.000001Z'),1::bigint,'Exact microsecond transport');
insert into w5_tap select is((pg_temp.read()->'source'->>'sourceManifestHash'),(select result#>>'{source,sourceManifestHash}' from w5_results),'Repeated basis digest stable');
insert into w5_tap select is((api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))->>'documentId'),pg_temp.fid('o')::text,'Drill-through rechecks actual source');
insert into w5_tap select throws_ok($$select pg_temp.read('b2')$$,'42501','Permission denied or multi-factor authentication required.','Foreign branch denied');
insert into w5_tap select throws_ok($$select pg_temp.read('b','2026-09-01')$$,'22023','VALIDATION_ERROR','Empty range rejected');
insert into w5_tap select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2024-01-01','2026-01-01','2026-01-01','2026-01-01')$$,'54000','LIMIT_EXCEEDED','366-day bound enforced');
insert into w5_tap select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-01','2026-10-01','2026-10-01','2099-01-01')$$,'22023','VALIDATION_ERROR','Future recorded cutoff rejected');
delete from core.role_permissions where role_id=pg_temp.fid('reader.role') and permission_code='crm.opportunities.view';
select pg_temp.actor('reader');
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','PERMISSION_DENIED','Own/owned event is insufficient without source permission');
insert into w5_tap select throws_ok($$select api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))$$,'42501','PERMISSION_DENIED','Revoked source blocks drill-through');
select pg_temp.actor('outsider');
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','Permission denied or multi-factor authentication required.','Foreign member denied before aggregate');
select set_config('request.jwt.claims','{}',true);
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','AUTH_REQUIRED','Anonymous denied');
select pg_temp.actor('owner');
update billing.plan_entitlements set enabled=false where plan_code='starter' and entitlement_code='analytics';
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','ENTITLEMENT_REQUIRED','Missing entitlement denies aggregate');
update billing.plan_entitlements set enabled=true where plan_code='starter' and entitlement_code='analytics';
insert into w5_tap select ok(not has_function_privilege('anon','api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)','execute'),'Anonymous cannot execute provider');
insert into w5_tap select ok(not has_function_privilege('authenticated','analytics.process_access(uuid,uuid,uuid)','execute'),'Private helper denied');
insert into w5_tap select throws_ok($test$do $body$begin
 insert into workflow.process_events(id,tenant_id,legal_entity_id,branch_id,document_type,document_id,to_status,actor_id,
  entered_at,completed_at,request_id,command_id,correlation_id,created_at)
 select pg_temp.fid('bound.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'crm_opportunity',pg_temp.fid('o'),'qualified',pg_temp.fid('owner'),
  '2026-09-01','2026-09-02',pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),'2026-09-02'
 from generate_series(1,9998) i;
 perform pg_temp.read();
end $body$$test$,'54000','LIMIT_EXCEEDED','10001 rows fail atomically without truncated totals');
insert into w5_tap select is((pg_temp.read()#>>'{source,sourceCount}'),'3','Excess-fixture failure leaves original cohort intact');

-- Compose after the existing process fixture, before its finish(true).
update crm.opportunities set expected_value=10.000001,probability=50,version=9007199254740993
 where id=pg_temp.fid('o');
insert into crm.opportunities(id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,currency_code,created_by,updated_by,
 expected_value,probability,expected_close_date,request_id,command_id,correlation_id,client_timestamp,version)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'W5-'||upper(x),'Synthetic prospect',
 pg_temp.fid('owner'),case x when 'usd' then 'USD' else 'LKR' end,pg_temp.fid('owner'),pg_temp.fid('owner'),
 10.000001,50,'2026-10-01',pg_temp.fid(x),pg_temp.fid(x),pg_temp.fid(x),'2026-09-01',9007199254740993
from unnest(array['usd','lkr']) x;
create function pg_temp.freeze(cmd text default 'forecast',end_date date default '2026-11-01') returns jsonb language sql as $$
select api.freeze_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid(cmd),pg_temp.fid(cmd),
 '2026-10-06','2026-10-01',end_date)$$;
create temporary table w5_forecast as select pg_temp.freeze() receipt;
create temporary table w5_frozen as select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (receipt#>>'{entity,id}')::uuid) result from w5_forecast;
insert into w5_tap select is((select result#>>'{evidence,sourceCount}' from w5_frozen),'3','Complete open opportunity cohort frozen');
insert into w5_tap select is((select jsonb_array_length(result#>'{evidence,currencies}') from w5_frozen),2,'Currencies remain separate');
insert into w5_tap select is((select c->>'weightedAmount' from w5_frozen,jsonb_array_elements(result#>'{evidence,currencies}') c
 where c->>'currency'='LKR'),'10.000002','Exact per-opportunity half-away rounding precedes sum');
insert into w5_tap select is((select c->>'weightedAmount' from w5_frozen,jsonb_array_elements(result#>'{evidence,currencies}') c
 where c->>'currency'='USD'),'5.000001','USD forecast is never added to LKR');
insert into w5_tap select ok((select result::text like '%9007199254740993%' from w5_frozen),'Huge source revisions remain decimal strings');
insert into w5_tap select ok((select result::text not like '%prospect%' and result::text not like '%ownerId%' and result::text not like '%won_loss_reason%' from w5_frozen),'Names and private free text omitted');
insert into w5_tap select is((select result#>>'{evidence,unavailable,accuracy}' from w5_frozen),'REALIZED_MAPPING_UNAVAILABLE','Accuracy lacks realized cohort mapping');
insert into w5_tap select is((select result->>'sourceHash' from w5_frozen),
 (select encode(extensions.digest(convert_to(result->>'canonicalText','UTF8'),'sha256'),'hex') from w5_frozen),'Captured bytes bind complete evidence');
insert into w5_tap select is(pg_temp.freeze(),(select receipt from w5_forecast),'Identical retry reuses original receipt');
do $$begin for i in 1..100 loop perform pg_temp.freeze();end loop;end $$;
insert into w5_tap select is((select count(*) from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')),1::bigint,'100 duplicate requests produce one frozen aggregate');
insert into w5_tap select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_name='analytics.freeze_pipeline'),1::bigint,'100 duplicate requests produce one command receipt');
insert into w5_tap select throws_ok($$select pg_temp.freeze('forecast','2026-12-01')$$,'22023','IDEMPOTENCY_MISMATCH','Changed retry payload denied');
update crm.opportunities set expected_value=999,probability=1,version=version+1 where id=pg_temp.fid('o');
insert into w5_tap select is((api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)->>'sourceHash'),(select result->>'sourceHash' from w5_frozen),'Later source edits cannot change frozen evidence');
insert into w5_tap select throws_ok($$update analytics.pipeline_forecasts set evidence='{}' where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Frozen aggregate cannot be overwritten');
insert into w5_tap select throws_ok($$delete from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Frozen aggregate cannot be deleted');
insert into w5_tap select throws_ok($$select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)$$,'42501','Permission denied or multi-factor authentication required.','Foreign branch cannot reopen');
insert into w5_tap select throws_ok($$select pg_temp.freeze('too-long','2028-01-01')$$,'54000','LIMIT_EXCEEDED','Forecast range bound rejects before effect');
select pg_temp.actor('outsider');
insert into w5_tap select throws_ok($$select pg_temp.freeze('outsider')$$,'42501','Permission denied or multi-factor authentication required.','Nonmember denied before capture');
select pg_temp.actor('owner');
delete from core.role_permissions where role_id=pg_temp.fid('owner.role') and permission_code='crm.opportunities.view';
insert into w5_tap select throws_ok($$select api.get_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select receipt#>>'{entity,id}' from w5_forecast)::uuid)$$,'42501','PERMISSION_DENIED','Revocation blocks frozen reopen');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'crm.opportunities.view');
insert into w5_tap select ok(not has_table_privilege('authenticated','analytics.pipeline_forecasts','select'),'No direct client table read bypass');
insert into w5_tap select ok(not has_function_privilege('anon','api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)','execute'),'Anonymous cannot freeze');

-- Compose with process/pipeline setup; all state rolls back.
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'billing.read');
insert into core.role_assignments(tenant_id,membership_id,role_id,created_by)
 values(pg_temp.fid('t'),pg_temp.fid('owner.member'),pg_temp.fid('owner.role'),pg_temp.fid('owner'));
update billing.plan_entitlements set enabled=true,numeric_limit=100 where plan_code='starter' and entitlement_code='quota.ai.tokens';
create function pg_temp.worker() returns void language sql as $$select set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',pg_temp.fid('owner'))::text,true)::void$$;
create function pg_temp.reserve(i text,q text default '60') returns jsonb language sql as $$
 select api.wave5_reserve_usage(pg_temp.fid('t'),pg_temp.fid(i),'ai.tokens',s.created_at,s.trial_ends_at,q)
 from billing.tenant_subscriptions s where s.tenant_id=pg_temp.fid('t')$$;
select pg_temp.actor('owner');
insert into w5_tap select throws_ok($$select pg_temp.reserve('client')$$,'42501','TRUSTED_WORKER_REQUIRED','Client usage claims cannot reserve allowance');
select pg_temp.worker();
insert into w5_tap select is(pg_temp.reserve('invocation')->>'reservedUnits','60','Trusted worker reserves exact allowance');
do $$begin for i in 1..100 loop perform pg_temp.reserve('invocation');end loop;end$$;
insert into w5_tap select is((select reserved_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'60','100 retries consume one reservation');
insert into w5_tap select throws_ok($$select pg_temp.reserve('invocation','61')$$,'22023','IDEMPOTENCY_MISMATCH','Changed retry amount rejected');
insert into w5_tap select throws_ok($$select pg_temp.reserve('other','41')$$,'54000','QUOTA_EXCEEDED','Hard allowance rejects excess before effect');
insert into w5_tap select is((select count(*) from intelligence_control.usage_reservations where tenant_id=pg_temp.fid('t')),1::bigint,'Denied reservation has no effect');
insert into w5_tap select throws_ok($$select api.wave5_reserve_usage(pg_temp.fid('t'),pg_temp.fid('period'),'ai.tokens',now()-interval '1 hour',now()+interval '1 hour','1')$$,
 '22023','PERIOD_CONFLICT','Caller cannot split an authoritative trial period');
insert into w5_tap select throws_ok($$select api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'61')$$,
 '54000','RESERVATION_EXCEEDED','Settlement cannot exceed reservation');
insert into w5_tap select is(api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'55')->>'quantity','55','Trusted exact usage settlement');
do $$begin for i in 1..100 loop perform api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('event'),'55');end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.usage_events where tenant_id=pg_temp.fid('t')),1::bigint,'100 settlements produce one append-only usage event');
insert into w5_tap select is((select settled_units::text||':'||reserved_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'55:0','Settlement releases only its reservation and records actual usage');
insert into w5_tap select throws_ok($$select api.wave5_settle_usage(pg_temp.fid('t'),pg_temp.fid('invocation'),pg_temp.fid('changed-event'),'55')$$,
 '22023','IDEMPOTENCY_MISMATCH','Different event cannot resettle invocation');
select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('correction'),pg_temp.fid('event'),'5','provider_reconciled');
select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('correction'),pg_temp.fid('event'),'5','provider_reconciled');
insert into w5_tap select is((select settled_units::text from intelligence_control.quota_periods where tenant_id=pg_temp.fid('t')),'50','Linked correction counted once');
insert into w5_tap select throws_ok($$select api.wave5_correct_usage(pg_temp.fid('t'),pg_temp.fid('excess-correction'),pg_temp.fid('event'),'51','provider_reconciled')$$,
 '22023','CORRECTION_EXCEEDED','Corrections cannot erase more than original usage');
insert into w5_tap select throws_ok($$update intelligence_control.usage_events set quantity=0 where tenant_id=pg_temp.fid('t')$$,'55000','IMMUTABLE_EVIDENCE','Usage history immutable');
insert into w5_tap select throws_ok($$delete from intelligence_control.usage_corrections where tenant_id=pg_temp.fid('t')$$,'55000','IMMUTABLE_EVIDENCE','Correction history immutable');
insert into w5_tap select is(pg_temp.reserve('unknown','50')->>'reservedUnits','50','Unknown provider outcome retains full reservation');
insert into w5_tap select throws_ok($$select pg_temp.reserve('excess-after-unknown','1')$$,'54000','QUOTA_EXCEEDED','Unknown outcome cannot release or duplicate allowance');
select pg_temp.actor('owner');
insert into w5_tap select is((api.get_wave5_usage_allowance(pg_temp.fid('t'),'ai.tokens',now())->>'remaining'),'0','Scoped billing read reports actual remaining zero');
select pg_temp.actor('outsider');
insert into w5_tap select throws_ok($$select api.get_wave5_usage_allowance(pg_temp.fid('t'),'ai.tokens',now())$$,'42501','Permission denied or multi-factor authentication required.','Foreign member cannot read aggregate usage');
select pg_temp.actor('owner');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)','execute'),'Client cannot execute trusted reserve RPC');
insert into w5_tap select ok(not has_table_privilege('authenticated','intelligence_control.usage_events','select'),'Private trusted usage ledger has no client bypass');
insert into w5_tap select ok((select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='intelligence_control' and c.relkind='r'),'Every tenant-bearing metering table forces RLS');

select pg_temp.actor('owner');
insert into w5_tap select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Tenant role does not grant operator authority');
select set_config('request.jwt.claims','{}',true);
insert into w5_tap select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Anonymous cannot read health');
insert into intelligence_control.operators values(pg_temp.fid('reader'),true,true,false),(pg_temp.fid('outsider'),true,true,true);
select pg_temp.actor('reader');
insert into w5_tap select is((select count(*) from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'state'='unknown'),4::bigint,'Missing probes are unknown');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('reader'),'role','authenticated','aal','aal1')::text,true);
insert into w5_tap select throws_ok($$select api.get_operator_health()$$,'42501','OPERATOR_ACCESS_REQUIRED','Operator capability still requires live MFA');
select pg_temp.worker();
select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','0',now());
select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','0',now());
select api.record_wave5_health_probe(pg_temp.fid('stale-probe'),null,'worker_lag_seconds','100',now()-interval '6 minutes');
insert into w5_tap select throws_ok($$select api.record_wave5_health_probe(pg_temp.fid('probe'),null,'retry_count','1',now())$$,
 '22023','IDEMPOTENCY_MISMATCH','Changed probe retry rejected');
select pg_temp.actor('reader');
insert into w5_tap select is((select p->>'exactValue' from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'code'='retry_count'),'0','Observed zero is a real zero');
insert into w5_tap select is((select p->>'state' from jsonb_array_elements(api.get_operator_health()->'probes') p where p->>'code'='worker_lag_seconds'),'unknown','Stale probe does not imply health');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),pg_temp.fid('no-grant'))$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Operator cannot inspect selected tenant without exact grant');
select pg_temp.actor('outsider');
create temporary table w5_grant as select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('reader'),
 'Synthetic incident investigation',now()+interval '30 minutes',pg_temp.fid('grant-command')) receipt;
do $$begin for i in 1..100 loop perform api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('reader'),
 'Synthetic incident investigation',now()+interval '30 minutes',pg_temp.fid('grant-command'));end loop;end$$;
insert into w5_tap select is((select count(*) from intelligence_control.operator_tenant_grants where tenant_id=pg_temp.fid('t')),1::bigint,'Duplicate grant command creates one immutable grant');
insert into w5_tap select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_name='operator.issue_grant'),1::bigint,'Grant reuses existing audited command receipts');
select pg_temp.actor('reader');
insert into w5_tap select ok(api.get_operator_tenant_health(pg_temp.fid('t'),(select receipt#>>'{entity,id}' from w5_grant)::uuid) is not null,'Exact current MFA grant authorizes bounded tenant health');
insert into w5_tap select is((select count(*) from intelligence_control.operator_access_events where tenant_id=pg_temp.fid('t')),1::bigint,'Every selected tenant access is recorded');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('foreign-tenant'),(select receipt#>>'{entity,id}' from w5_grant)::uuid)$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Grant cannot cross tenants');
insert into intelligence_control.operator_tenant_grants(id,tenant_id,operator_id,issued_by,reason,issued_at,expires_at)
 values(pg_temp.fid('expired-grant'),pg_temp.fid('t'),pg_temp.fid('reader'),pg_temp.fid('outsider'),'Synthetic expired access',now()-interval '1 hour',now()-interval '1 second');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),pg_temp.fid('expired-grant'))$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Expired grant denied');
update intelligence_control.operators set active=false where actor_id=pg_temp.fid('reader');
insert into w5_tap select throws_ok($$select api.get_operator_tenant_health(pg_temp.fid('t'),(select receipt#>>'{entity,id}' from w5_grant)::uuid)$$,
 '42501','OPERATOR_ACCESS_REQUIRED','Operator revocation blocks still-current grant');
insert into w5_tap select throws_ok($$delete from intelligence_control.operator_access_events where tenant_id=pg_temp.fid('t')$$,
 '55000','IMMUTABLE_EVIDENCE','Operator access audit immutable');
insert into w5_tap select ok(not has_table_privilege('authenticated','intelligence_control.operators','select'),'Client cannot inspect or bootstrap operator authority');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.record_wave5_health_probe(uuid,uuid,text,text,timestamptz)','execute'),'Client cannot manufacture trusted health');
select pg_temp.actor('owner');

select * from finish(true);
select jsonb_agg(message) tap,(select result from w5_frozen) pipeline_snapshot,
 (select result from w5_results) process_snapshot from w5_tap;
rollback;
