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
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>current_timestamp)
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

create function api.analytics_pipeline_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);return auth.uid();end$$;

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
