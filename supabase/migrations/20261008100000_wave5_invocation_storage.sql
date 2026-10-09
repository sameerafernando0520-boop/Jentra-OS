-- UNAPPLIED. No credential, model provider, secret or entitlement is enabled.
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
 select code,'quota.integration.commands',false from billing.plans on conflict do nothing;
create table intelligence_control.integration_credentials(
 id uuid primary key,token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'),
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,actor_id uuid not null references auth.users(id),
 starts_at timestamptz not null,expires_at timestamptz not null,revoked_at timestamptz,
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(isfinite(starts_at) and isfinite(expires_at) and expires_at>starts_at and expires_at-starts_at<=interval '366 days'));
create table intelligence_control.external_periods(
 tenant_id uuid not null references core.tenants(id),period_start timestamptz not null,period_end timestamptz not null,
 reserved numeric(20,0) not null default 0 check(reserved>=0),primary key(tenant_id,period_start),check(period_end>period_start));
create table intelligence_control.external_requests(
 tenant_id uuid not null,credential_id uuid not null,command_id uuid not null,idempotency_key uuid not null,
 request_hash text not null,request jsonb not null,period_start timestamptz not null,response jsonb,
 created_at timestamptz not null default statement_timestamp(),primary key(tenant_id,credential_id,command_id),
 unique(tenant_id,credential_id,idempotency_key),foreign key(tenant_id,credential_id) references intelligence_control.integration_credentials(tenant_id,id),
 foreign key(tenant_id,period_start) references intelligence_control.external_periods(tenant_id,period_start));
create table intelligence_control.external_throttles(
 credential_id uuid not null references intelligence_control.integration_credentials(id),window_start timestamptz not null,
 count integer not null check(count between 0 and 60),primary key(credential_id,window_start));
create table intelligence_control.model_invocations(
 invocation_id uuid primary key,tenant_id uuid not null references core.tenants(id),source_id uuid not null,
 source_hash text not null check(source_hash ~ '^[0-9a-f]{64}$'),manifest_hash text not null check(manifest_hash ~ '^[0-9a-f]{64}$'),
 request jsonb not null,created_at timestamptz not null default statement_timestamp(),
 foreign key(tenant_id,source_id) references analytics.pipeline_forecasts(tenant_id,id));
create table intelligence_control.model_outcomes(
 invocation_id uuid primary key references intelligence_control.model_invocations(invocation_id),state text not null check(state in('settled','unknown')),
 tokens numeric(20,0),suggestion jsonb,recorded_at timestamptz not null default statement_timestamp(),
 check((state='unknown' and tokens is null and suggestion is null) or (state='settled' and tokens is not null and tokens>=0 and suggestion is not null and jsonb_typeof(suggestion)='object')));
do $$declare rel text;begin foreach rel in array array['integration_credentials','external_periods','external_requests','external_throttles','model_invocations','model_outcomes'] loop
 execute format('alter table intelligence_control.%I enable row level security',rel);
 execute format('alter table intelligence_control.%I force row level security',rel);
 execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
 if rel in('model_invocations','model_outcomes') then
 execute format('create trigger immutable before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);end if;
end loop;end $$;
create index credential_scope_idx on intelligence_control.integration_credentials(tenant_id,legal_entity_id,branch_id,id);
create index model_source_idx on intelligence_control.model_invocations(tenant_id,source_id,invocation_id);

create function api.wave5_credential_manage(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_action text,p_id uuid,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command uuid;v_hash text;v_receipt jsonb;
begin
 if p_id is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 -- Each credential has one immutable registration and one revocation identity.
 -- Repeating the original request reopens its audited receipt after live access.
 v_command:=md5('wave5.credential:'||p_id::text||':'||p_action||':'||auth.uid()::text)::uuid;
 v_hash:=core.wave3_request_hash('integration.credential.'||p_action,v_command,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,null);
 v_receipt:=core.wave3_replay(p_tenant_id,'integration.credential.'||p_action,v_command,v_command,v_hash);
 if v_receipt is not null then return v_receipt;end if;
 if p_action='register' and (p_payload-array['tokenHash','startsAt','expiresAt'])='{}' and p_payload ?& array['tokenHash','startsAt','expiresAt'] then
  insert into intelligence_control.integration_credentials values(p_id,p_payload->>'tokenHash',p_tenant_id,p_legal_entity_id,p_branch_id,
   auth.uid(),(p_payload->>'startsAt')::timestamptz,(p_payload->>'expiresAt')::timestamptz,null);
 elsif p_action='revoke' and p_payload='{}' then
  update intelligence_control.integration_credentials set revoked_at=coalesce(revoked_at,statement_timestamp()) where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id is not distinct from p_branch_id and id=p_id;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 else raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 -- Immutable system audit plus outbox; never a token or hash in public receipt.
 return core.wave3_finish_command(p_tenant_id,'integration.credential.'||p_action,v_command,'integration_credential',p_id,v_command,
  v_hash,null,jsonb_build_object('id',p_id,'version','1','state',p_action),p_legal_entity_id,p_branch_id);
end $$;

create function api.wave5_external_worker(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c intelligence_control.integration_credentials%rowtype;r intelligence_control.external_requests%rowtype;
 req jsonb:=p_payload->'request';s jsonb;h text;v_period_start timestamptz;v_period_end timestamptz;cap numeric;used numeric;
 window_at timestamptz:=date_trunc('minute',statement_timestamp());throttle integer;saved_claims text;result jsonb;begin
 perform intelligence_control.worker_required();
 select * into c from intelligence_control.integration_credentials where token_hash=p_payload->>'tokenHash';
 if not found or c.revoked_at is not null or c.starts_at>statement_timestamp() or c.expires_at<=statement_timestamp() then
  raise exception using errcode='42501',message='INTEGRATION_ACCESS_DENIED';end if;
 if p_action='credential' then return jsonb_build_object('id',c.id,'tokenHash',c.token_hash,
  'scope',jsonb_build_object('tenantId',c.tenant_id,'legalEntityId',c.legal_entity_id,'branchId',c.branch_id),
  'startsAt',floor(extract(epoch from c.starts_at))::bigint,'expiresAt',floor(extract(epoch from c.expires_at))::bigint,'revokedAt',null,
  'commands',jsonb_build_array('analytics.freeze_pipeline.v1'));end if;
 if req is null or req->>'commandCode' is distinct from 'analytics.freeze_pipeline.v1' or req->>'schemaVersion' is distinct from '1'
  or (req-array['schemaVersion','scope','commandCode','commandId','idempotencyKey','clientTimestamp','horizonStart','horizonEnd'])<>'{}'
  or not(req ?& array['schemaVersion','scope','commandCode','commandId','idempotencyKey','clientTimestamp','horizonStart','horizonEnd'])
  or req->'scope' is distinct from jsonb_build_object('tenantId',c.tenant_id,'legalEntityId',c.legal_entity_id,'branchId',c.branch_id) then
  raise exception using errcode='42501',message='INTEGRATION_ACCESS_DENIED';end if;
 -- Credential-bound delegation uses AAL1 only. It cannot forge human MFA or
 -- cross into a privileged command. The named domain command rechecks authority.
 saved_claims:=current_setting('request.jwt.claims',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.actor_id,'role','authenticated','aal','aal1')::text,true);
 perform analytics.pipeline_access(c.tenant_id,c.legal_entity_id,c.branch_id);
 perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
 perform 1 from billing.tenant_subscriptions where tenant_id=c.tenant_id for update;
 select case when status='trialing' then coalesce(trial_started_at,created_at) else date_trunc('month',statement_timestamp()) end,
  case when status='trialing' then trial_ends_at else current_period_ends_at end into v_period_start,v_period_end
  from billing.tenant_subscriptions where tenant_id=c.tenant_id;
 if v_period_end is null then raise exception using errcode='55000',message='BILLING_PERIOD_UNAVAILABLE';end if;
 perform pg_advisory_xact_lock(hashtextextended(c.tenant_id::text||':integration.commands',58));
 cap:=intelligence_control.quota_limit(c.tenant_id,'integration.commands');
 h:=encode(extensions.digest(req::text,'sha256'),'hex');
 select * into r from intelligence_control.external_requests where tenant_id=c.tenant_id and credential_id=c.id
  and (command_id=(req->>'commandId')::uuid or idempotency_key=(req->>'idempotencyKey')::uuid) for update;
 if found then
  if r.request_hash<>h then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
 else
  if p_action<>'reserve' then raise exception using errcode='42501',message='RESERVATION_REQUIRED';end if;
  if exists(select 1 from intelligence_control.external_periods x where x.tenant_id=c.tenant_id and x.period_start<>v_period_start
   and x.period_start<v_period_end and x.period_end>v_period_start) then raise exception using errcode='22023',message='PERIOD_CONFLICT';end if;
  insert into intelligence_control.external_periods values(c.tenant_id,v_period_start,v_period_end,0) on conflict do nothing;
  select x.reserved into used from intelligence_control.external_periods x where x.tenant_id=c.tenant_id and x.period_start=v_period_start for update;
  if used+1>cap then raise exception using errcode='54000',message='QUOTA_EXCEEDED';end if;
  insert into intelligence_control.external_throttles values(c.id,window_at,0) on conflict do nothing;
  select count into throttle from intelligence_control.external_throttles where credential_id=c.id and window_start=window_at for update;
  if throttle>=60 then raise exception using errcode='54000',message='THROTTLED';end if;
  update intelligence_control.external_throttles set count=count+1 where credential_id=c.id and window_start=window_at;
  update intelligence_control.external_periods x set reserved=reserved+1 where x.tenant_id=c.tenant_id and x.period_start=v_period_start;
  insert into intelligence_control.external_requests values(c.tenant_id,c.id,(req->>'commandId')::uuid,(req->>'idempotencyKey')::uuid,h,req,v_period_start,null,statement_timestamp()) returning * into r;
 end if;
 if p_action='reserve' then return jsonb_build_object('quotaReserved',true,'throttleReserved',true);end if;
 if p_action<>'dispatch' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if r.response is not null then return r.response;end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.actor_id,'role','authenticated','aal','aal1')::text,true);
 result:=api.freeze_pipeline_forecast(c.tenant_id,c.legal_entity_id,c.branch_id,(req->>'commandId')::uuid,(req->>'idempotencyKey')::uuid,
  (req->>'clientTimestamp')::timestamptz,(req->>'horizonStart')::date,(req->>'horizonEnd')::date);
 perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
 update intelligence_control.external_requests set response=result where tenant_id=c.tenant_id and credential_id=c.id and command_id=r.command_id;
 return result;
end $$;

create function api.wave5_model_worker(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i intelligence_control.model_invocations%rowtype;o intelligence_control.model_outcomes%rowtype;begin
 perform intelligence_control.worker_required();
 if p_action='readiness' then return jsonb_build_object('contractRevision',1,'ready',true);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_payload->>'invocationId',59));
 if p_action='begin' then
  select * into i from intelligence_control.model_invocations where invocation_id=(p_payload->>'invocationId')::uuid;
  if found then
   if i.request<>p_payload then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
   select * into o from intelligence_control.model_outcomes where invocation_id=i.invocation_id;
   return case when o.invocation_id is null then jsonb_build_object('state','pending')
    else jsonb_build_object('state',o.state,'tokens',o.tokens::text,'suggestion',o.suggestion) end;
  end if;
  if p_payload->>'policyRevision' is distinct from '1' or coalesce(p_payload->>'maxTokens','')!~ '^[1-9][0-9]{0,6}$'
   or not exists(select 1 from analytics.pipeline_forecasts where tenant_id=(p_payload->>'tenantId')::uuid
    and id=(p_payload->>'sourceId')::uuid and source_hash=p_payload->>'sourceHash') then raise exception using errcode='22023',message='MODEL_BASIS_MISMATCH';end if;
  insert into intelligence_control.model_invocations values((p_payload->>'invocationId')::uuid,(p_payload->>'tenantId')::uuid,
   (p_payload->>'sourceId')::uuid,p_payload->>'sourceHash',p_payload->>'manifestHash',p_payload,statement_timestamp());
  return jsonb_build_object('state','new');
 elsif p_action='outcome' then
  select * into i from intelligence_control.model_invocations where invocation_id=(p_payload->>'invocationId')::uuid;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
  if p_payload->>'state' is null or p_payload->>'state' not in('settled','unknown') or
   (p_payload->>'state'='unknown' and ((p_payload-array['invocationId','state'])<>'{}')) then
   raise exception using errcode='22023',message='MODEL_OUTCOME_MISMATCH';end if;
  if p_payload->>'state'='settled' and (
   (p_payload-array['invocationId','state','tokens','suggestion'])<>'{}' or not(p_payload ?& array['invocationId','state','tokens','suggestion'])
   or jsonb_typeof(p_payload->'tokens') is distinct from 'string' or coalesce(p_payload->>'tokens','')!~ '^(0|[1-9][0-9]{0,6})$'
   or (p_payload->>'tokens')::numeric>(i.request->>'maxTokens')::numeric
   or jsonb_typeof(p_payload->'suggestion') is distinct from 'object'
   or ((p_payload->'suggestion')-array['commandCode','sourceId','sourceHash','horizonStart','horizonEnd'])<>'{}'
   or not((p_payload->'suggestion') ?& array['commandCode','sourceId','sourceHash','horizonStart','horizonEnd'])
   or p_payload#>>'{suggestion,commandCode}' is distinct from 'analytics.freeze_pipeline.v1'
   or p_payload#>>'{suggestion,sourceId}' is distinct from i.source_id::text or p_payload#>>'{suggestion,sourceHash}' is distinct from i.source_hash
   or not exists(select 1 from analytics.pipeline_forecasts f where f.id=i.source_id and f.tenant_id=i.tenant_id
    and f.horizon_start::text=(p_payload#>>'{suggestion,horizonStart}') and f.horizon_end::text=(p_payload#>>'{suggestion,horizonEnd}'))) then
   raise exception using errcode='22023',message='MODEL_OUTCOME_MISMATCH';end if;
  select * into o from intelligence_control.model_outcomes where invocation_id=i.invocation_id;
  if found then
   if o.state<>p_payload->>'state' or o.tokens is distinct from (p_payload->>'tokens')::numeric
    or o.suggestion is distinct from p_payload->'suggestion' then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;return '{}'::jsonb;
  end if;
  insert into intelligence_control.model_outcomes values(i.invocation_id,p_payload->>'state',(p_payload->>'tokens')::numeric,p_payload->'suggestion',statement_timestamp());
  return '{}'::jsonb;
 end if;
 raise exception using errcode='22023',message='VALIDATION_ERROR';
end $$;
revoke all on function api.wave5_credential_manage(uuid,uuid,uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_credential_manage(uuid,uuid,uuid,text,uuid,jsonb) to authenticated;
revoke all on function api.wave5_external_worker(text,jsonb),api.wave5_model_worker(text,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_external_worker(text,jsonb),api.wave5_model_worker(text,jsonb) to service_role;

create function api.wave5_worker_entitlement(p_scope jsonb) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare tenant uuid:=(p_scope->>'tenantId')::uuid;begin
 perform intelligence_control.worker_required();
 perform intelligence_control.quota_limit(tenant,'integration.commands');
 return exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=tenant and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp()))));
end $$;
revoke all on function api.wave5_worker_entitlement(jsonb) from public,anon,authenticated;
grant execute on function api.wave5_worker_entitlement(jsonb) to service_role;

-- Only explicitly allowlisted synthetic tenants enter scheduled application.
-- The existing installed apply RPC owns billing locks, MFA-grant revalidation,
-- seat admission and stable command identity. No tenant is enabled here.
create function api.wave5_subscription_due(p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;n integer;cursor uuid;begin
 perform intelligence_control.worker_required();
 select coalesce(jsonb_agg(jsonb_build_object('tenantId',tenant_id,'revisionId',id) order by id),'[]'),count(*) into rows,n
 from (select r.id,r.tenant_id from intelligence_control.subscription_revisions r
  join intelligence_control.synthetic_tenants t on t.tenant_id=r.tenant_id and t.allowed
  where r.trial_starts_at<=statement_timestamp() and r.trial_ends_at>statement_timestamp()
   and (p_after is null or r.id>p_after) and not exists(select 1 from intelligence_control.subscription_activations a
    where a.tenant_id=r.tenant_id and a.revision_id=r.id) order by r.id limit 51) q;
 if n>50 then cursor:=(rows->49->>'revisionId')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('contractRevision',1,'items',rows,'nextCursor',cursor);
end $$;
revoke all on function api.wave5_subscription_due(uuid) from public,anon,authenticated;
grant execute on function api.wave5_subscription_due(uuid) to service_role;
