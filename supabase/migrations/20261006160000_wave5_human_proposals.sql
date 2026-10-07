-- Provider-neutral human proposals. No model invocation or autonomous command.
insert into core.permissions(code,module,description,privileged) values
 ('ai.proposals.view','ai','Read scoped governed proposals',false),('ai.proposals.manage','ai','Create immutable scoped proposals',false),
 ('ai.proposals.approve','ai','Make distinct MFA approval decisions',true),('ai.proposals.execute','ai','Execute approved named proposals',true)
 on conflict(code) do nothing;
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) select code,'module.ai',false from billing.plans on conflict do nothing;
create table intelligence_control.proposals(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,
 proposer_id uuid not null references auth.users(id),source_forecast_id uuid not null,source_hash text not null check(source_hash ~ '^[0-9a-f]{64}$'),
 execution_id uuid not null unique,created_at timestamptz not null,expires_at timestamptz not null,
 horizon_start date not null,horizon_end date not null,targets jsonb not null check(jsonb_typeof(targets)='object'),
 canonical_text text not null check(octet_length(canonical_text)<=8388608),parameters_hash text not null check(parameters_hash ~ '^[0-9a-f]{64}$'),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,source_forecast_id) references analytics.pipeline_forecasts(tenant_id,id),
 check(isfinite(expires_at) and expires_at>created_at and expires_at-created_at<=interval '24 hours'),
 check(horizon_end>horizon_start and horizon_end-horizon_start<=366),
 check(parameters_hash=encode(extensions.digest(convert_to(canonical_text,'UTF8'),'sha256'),'hex'))
);
create table intelligence_control.proposal_decisions(
 tenant_id uuid not null,proposal_id uuid not null,parameters_hash text not null,approver_id uuid not null references auth.users(id),
 decision text not null check(decision in('approved','rejected')),assurance text not null check(assurance='aal2'),
 recorded_at timestamptz not null default statement_timestamp(),primary key(tenant_id,proposal_id),
 foreign key(tenant_id,proposal_id) references intelligence_control.proposals(tenant_id,id)
);
create table intelligence_control.proposal_executions(
 tenant_id uuid not null,proposal_id uuid not null,executor_id uuid not null references auth.users(id),
 response jsonb not null,recorded_at timestamptz not null default statement_timestamp(),primary key(tenant_id,proposal_id),
 foreign key(tenant_id,proposal_id) references intelligence_control.proposals(tenant_id,id)
);
do $$declare rel text;begin foreach rel in array array['proposals','proposal_decisions','proposal_executions'] loop
 execute format('alter table intelligence_control.%I enable row level security',rel);
 execute format('alter table intelligence_control.%I force row level security',rel);
 execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
 execute format('create trigger immutable_proposal_evidence before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);
end loop;end$$;
create index proposal_scope_idx on intelligence_control.proposals(tenant_id,legal_entity_id,branch_id,created_at desc,id);
create index proposal_source_idx on intelligence_control.proposals(tenant_id,source_forecast_id);
create index proposal_actor_idx on intelligence_control.proposals(proposer_id);
create index proposal_approver_idx on intelligence_control.proposal_decisions(approver_id);
create index proposal_executor_idx on intelligence_control.proposal_executions(executor_id);

create function intelligence_control.proposal_access(t uuid,e uuid,b uuid,cap text) returns void
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.pipeline_access(t,e,b);perform core.wave3_require_scope(t,cap,e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='module.ai' and p.enabled and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';end if;
end $$;
revoke all on function intelligence_control.proposal_access(uuid,uuid,uuid,text) from public,anon,authenticated;

create function api.wave5_proposal_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform intelligence_control.proposal_access(p_tenant_id,p_legal_entity_id,p_branch_id,'ai.proposals.view');return auth.uid();end$$;
revoke all on function api.wave5_proposal_authorize(uuid,uuid,uuid) from public,anon;
grant execute on function api.wave5_proposal_authorize(uuid,uuid,uuid) to authenticated;

create function api.get_ai_forecast_evidence(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_forecast_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare f jsonb;begin
 perform intelligence_control.proposal_access(p_tenant_id,p_legal_entity_id,p_branch_id,'ai.proposals.view');
 f:=api.get_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,p_forecast_id);
 return jsonb_build_object('contractRevision',1,'modelProvider','unavailable','sourceId',p_forecast_id,'sourceHash',f->'sourceHash',
  'scope',jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
  'currencies',f#>'{evidence,currencies}','horizonStart',f#>'{evidence,horizonStart}','horizonEnd',f#>'{evidence,horizonEnd}');
end $$;

create function api.wave5_proposal_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cap text;name text;h text;replayed jsonb;identity uuid;f jsonb;targets jsonb;canonical jsonb;entity jsonb;execution uuid:=gen_random_uuid();
expiry timestamptz;canonical_bytes text;p intelligence_control.proposals%rowtype;d intelligence_control.proposal_decisions%rowtype;child jsonb;now_at timestamptz:=statement_timestamp();begin
 cap:=case p_action when 'create' then 'ai.proposals.manage' when 'decide' then 'ai.proposals.approve' when 'execute' then 'ai.proposals.execute' end;
 if cap is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform intelligence_control.proposal_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap);
 if p_action in('decide','execute') and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null or not isfinite(p_client_timestamp)
  or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_action='create' and (not(p_payload ?& array['sourceId','expiresAt']) or (p_payload-array['sourceId','expiresAt'])<>'{}'
  or jsonb_typeof(p_payload->'sourceId')<>'string' or jsonb_typeof(p_payload->'expiresAt')<>'string') then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_action='decide' and (not(p_payload ?& array['proposalId','parametersHash','decision']) or (p_payload-array['proposalId','parametersHash','decision'])<>'{}'
  or p_payload->>'decision' not in('approved','rejected') or jsonb_typeof(p_payload->'decision')<>'string' or jsonb_typeof(p_payload->'proposalId')<>'string'
  or jsonb_typeof(p_payload->'parametersHash')<>'string') then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_action='execute' and (not(p_payload ? 'proposalId') or (p_payload-'proposalId')<>'{}'
  or jsonb_typeof(p_payload->'proposalId')<>'string') then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 name:='ai.proposal.'||p_action;
 h:=core.wave3_request_hash(name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload||jsonb_build_object('client',p_client_timestamp),null);
 replayed:=core.wave3_replay(p_tenant_id,name,p_command_id,p_idempotency_key,h);
 if replayed is not null then return replayed;end if;
 if p_action='create' then
  expiry:=(p_payload->>'expiresAt')::timestamptz;
  if not isfinite(expiry) or expiry<=now_at or expiry-now_at>interval '24 hours' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
  f:=api.get_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'sourceId')::uuid);
  select coalesce(jsonb_object_agg(x->>'id',x->'version'),'{}') into targets from jsonb_array_elements(f#>'{evidence,observations}') x;
  identity:=gen_random_uuid();canonical_bytes:=json_build_object('policyVersion',1,'id',identity,'revision',1,'proposerId',auth.uid(),
   'commandId',execution,'commandCode','analytics.freeze_pipeline.v1',
   'scope',json_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
   'horizonStart',f#>'{evidence,horizonStart}','horizonEnd',f#>'{evidence,horizonEnd}',
   'sourceId',f->'id','sourceHash',f->'sourceHash','targets',targets,'createdAt',analytics.process_utc(now_at),
   'expiresAt',analytics.process_utc(expiry),'estimatedUnits','0')::text;
  -- Fixed codes, UUIDs, exact revisions and UTC/date strings only; no arbitrary
  -- text can contain a structural separator in this canonical projection.
  canonical_bytes:=replace(replace(replace(canonical_bytes,' : ',':'),': ',':'),', ',',');
  canonical:=canonical_bytes::jsonb;
  insert into intelligence_control.proposals(id,tenant_id,legal_entity_id,branch_id,proposer_id,source_forecast_id,source_hash,execution_id,
   created_at,expires_at,horizon_start,horizon_end,targets,canonical_text,parameters_hash)
  values(identity,p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),(f->>'id')::uuid,f->>'sourceHash',execution,now_at,expiry,
   (f#>>'{evidence,horizonStart}')::date,(f#>>'{evidence,horizonEnd}')::date,targets,canonical_bytes,
   encode(extensions.digest(convert_to(canonical_bytes,'UTF8'),'sha256'),'hex'));
  entity:=jsonb_build_object('id',identity,'version','1','state','proposed','parametersHash',encode(extensions.digest(convert_to(canonical_bytes,'UTF8'),'sha256'),'hex'));
 else
  identity:=(p_payload->>'proposalId')::uuid;
  perform pg_advisory_xact_lock(hashtextextended(identity::text,6));
  select * into p from intelligence_control.proposals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id is not distinct from p_branch_id and id=identity;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
  if p.expires_at<=now_at then raise exception using errcode='22023',message='APPROVAL_EXPIRED';end if;
  perform api.get_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,p.source_forecast_id);
  if p_action='decide' then
   if p.proposer_id=auth.uid() then raise exception using errcode='42501',message='DISTINCT_APPROVER_REQUIRED';end if;
   if p.parameters_hash<>p_payload->>'parametersHash' then raise exception using errcode='22023',message='APPROVAL_HASH_MISMATCH';end if;
   if exists(select 1 from intelligence_control.proposal_decisions where tenant_id=p_tenant_id and proposal_id=p.id) then
    raise exception using errcode='40001',message='CONFLICT';end if;
   insert into intelligence_control.proposal_decisions values(p_tenant_id,p.id,p.parameters_hash,auth.uid(),p_payload->>'decision','aal2',now_at);
   entity:=jsonb_build_object('id',identity,'version','1','state',p_payload->>'decision','parametersHash',p.parameters_hash);
  else
   select * into d from intelligence_control.proposal_decisions where tenant_id=p_tenant_id and proposal_id=p.id and decision='approved';
   if not found or d.parameters_hash<>p.parameters_hash or d.approver_id=p.proposer_id then
    raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
   -- Stored approval assurance plus current verified MFA factor and live scoped
   -- approver membership/capability: revoked human authority cannot be reused.
   if not exists(select 1 from auth.mfa_factors where user_id=d.approver_id and status='verified') or not exists(
    select 1 from core.memberships m join core.role_assignments ra on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
    join core.roles r on r.tenant_id=ra.tenant_id and r.id=ra.role_id join core.role_permissions rp on rp.tenant_id=r.tenant_id and rp.role_id=r.id
    where m.tenant_id=p_tenant_id and m.user_id=d.approver_id and m.status='active' and rp.permission_code='ai.proposals.approve'
     and (ra.legal_entity_id is null or ra.legal_entity_id=p_legal_entity_id) and (ra.branch_id is null or ra.branch_id=p_branch_id)) then
    raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
   select response into child from intelligence_control.proposal_executions where tenant_id=p_tenant_id and proposal_id=p.id;
   if child is null then
    if exists(select 1 from jsonb_each_text(p.targets) target where not exists(select 1 from crm.opportunities o
     where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and (p_branch_id is null or o.branch_id=p_branch_id)
      and o.id=target.key::uuid and o.version::text=target.value)) then raise exception using errcode='40001',message='TARGET_SOURCE_CHANGED';end if;
    child:=api.freeze_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,p.execution_id,p.execution_id,p.created_at,p.horizon_start,p.horizon_end);
    f:=api.get_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,(child#>>'{entity,id}')::uuid);
    select coalesce(jsonb_object_agg(x->>'id',x->'version'),'{}') into targets from jsonb_array_elements(f#>'{evidence,observations}') x;
    if targets<>p.targets then raise exception using errcode='40001',message='TARGET_SOURCE_CHANGED';end if;
    insert into intelligence_control.proposal_executions values(p_tenant_id,p.id,auth.uid(),child,now_at);
   end if;
   entity:=jsonb_build_object('id',identity,'version','1','state','executed','parametersHash',p.parameters_hash,'businessReceipt',child);
  end if;
 end if;
 return core.wave3_finish_command(p_tenant_id,name,p_command_id,'ai_proposal',identity,p_idempotency_key,h,null,entity,p_legal_entity_id,p_branch_id);
end $$;

create function api.get_wave5_proposal(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_proposal_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare p intelligence_control.proposals%rowtype;state text;begin
 perform intelligence_control.proposal_access(p_tenant_id,p_legal_entity_id,p_branch_id,'ai.proposals.view');
 select * into p from intelligence_control.proposals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id is not distinct from p_branch_id and id=p_proposal_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform api.get_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,p.source_forecast_id);
 state:=case when exists(select 1 from intelligence_control.proposal_executions where tenant_id=p_tenant_id and proposal_id=p.id) then 'executed'
  when p.expires_at<=statement_timestamp() then 'expired' else coalesce((select decision from intelligence_control.proposal_decisions where tenant_id=p_tenant_id and proposal_id=p.id),'proposed') end;
 return jsonb_build_object('id',p.id,'revision','1','state',state,'parametersHash',p.parameters_hash,'canonicalText',p.canonical_text,
  'explanationCode','freeze_current_pipeline_for_review','resourceBudget',jsonb_build_object('modelUnits','0','commands','1','sourceRows',(select count(*) from jsonb_each(p.targets))::text),
  'origin','human','modelProvider','unavailable');
end $$;
revoke all on function api.get_ai_forecast_evidence(uuid,uuid,uuid,uuid),api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb),
 api.get_wave5_proposal(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.get_ai_forecast_evidence(uuid,uuid,uuid,uuid),api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb),
 api.get_wave5_proposal(uuid,uuid,uuid,uuid) to authenticated;
