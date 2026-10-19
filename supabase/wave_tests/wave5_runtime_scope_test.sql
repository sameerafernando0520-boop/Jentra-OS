-- Follows both actual-source fixtures in one caller-owned strict ROLLBACK.
-- Clear the Wave 4 fixture's legacy sub setting before the process fixture
-- switches JSON claims. Real PostgREST supplies consistent request claims.
select set_config('request.jwt.claim.sub','',true);
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='intelligence_control.runtime_worker_scopes'::regclass),'Worker allowlist forces RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='intelligence_control.runtime_operator_authorities'::regclass),'Operator authority forces RLS');
select ok(not has_function_privilege('authenticated','api.wave5_runtime_worker(uuid,text,jsonb)','execute'),'Clients cannot call trusted runtime worker');
select ok(has_function_privilege('service_role','api.wave5_runtime_worker(uuid,text,jsonb)','execute'),'Trusted service can call scoped runtime worker');
insert into intelligence_control.runtime_worker_scopes(runtime_id,tenant_id,legal_entity_id,branch_id,enabled,expires_at)
 values(pg_temp.fid('runtime'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),true,statement_timestamp()+interval '1 day');
select ok(intelligence_control.runtime_scope_allowed(pg_temp.fid('runtime'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),'Exact reviewed scope allowed');
select ok(not intelligence_control.runtime_scope_allowed(pg_temp.fid('runtime'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2')),'Sibling branch denied');
select ok(not intelligence_control.runtime_tenant_allowed(pg_temp.fid('runtime'),pg_temp.wid('tenant')),'Foreign tenant denied');
select pg_temp.actor('owner');
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'delivery.claim','{}')$$,'42501','TRUSTED_WORKER_REQUIRED','Real service authority required before claim');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('unregistered-runtime'),'delivery.claim','{}')$$,'42501','RUNTIME_SCOPE_DENIED','Unregistered runtime denied');
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'usage.reserve',jsonb_build_object('tenantId',pg_temp.wid('tenant')))$$,'42501','RUNTIME_SCOPE_DENIED','Foreign quota mutation denied before reservation');
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'health.collect',jsonb_build_object('collectionId',pg_temp.fid('health'),'tenantId',null))$$,'42501','RUNTIME_SCOPE_DENIED','Global health collection denied');
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'model.outcome',jsonb_build_object('invocationId',pg_temp.fid('unknown-invocation'),'state','unknown'))$$,'42501','RUNTIME_SCOPE_DENIED','Missing/foreign invocation cannot receive an outcome');
insert into analytics.pipeline_forecasts(id,tenant_id,legal_entity_id,branch_id,created_by,horizon_start,horizon_end,observed_at,canonical_text,source_hash,evidence)
 values(pg_temp.fid('runtime.model.source'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('owner'),current_date,current_date+1,statement_timestamp(),
 '{}',encode(extensions.digest('{}','sha256'),'hex'),'{}');
create function pg_temp.runtime_model(i integer,max_tokens text default '2000') returns jsonb language sql as $$
 select jsonb_build_object('invocationId',pg_temp.fid('runtime.model.'||i),'tenantId',pg_temp.fid('t'),'sourceId',pg_temp.fid('runtime.model.source'),
 'sourceHash',encode(extensions.digest('{}','sha256'),'hex'),'manifestHash',repeat('b',64),'policyRevision',1,'maxTokens',max_tokens)$$;
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'model.begin',pg_temp.runtime_model(0,'2500'))$$,'22023','VALIDATION_ERROR','Runtime limits each model reservation to 2000 tokens');
create temporary table runtime_model_states as select api.wave5_runtime_worker(pg_temp.fid('runtime'),'model.begin',pg_temp.runtime_model(i)) result from generate_series(1,4) i;
select ok((select bool_and(result->>'state'='new') from runtime_model_states),'Four distinct invocations enter immutable storage');
select is(api.wave5_runtime_worker(pg_temp.fid('runtime'),'model.begin',pg_temp.runtime_model(1))->>'state','pending','Restart/retry retains original pending invocation');
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'model.begin',pg_temp.runtime_model(5))$$,'54000','MODEL_CALL_LIMIT','Persistent budget rejects fifth distinct invocation');
select is((select count(*) from intelligence_control.model_invocations where tenant_id=pg_temp.fid('t')),4::bigint,'Rejected invocation has no storage effect');
-- A foreign credential and an expired foreign lease remain untouched by claim.
insert into intelligence_control.integration_subscriptions(id,tenant_id,legal_entity_id,branch_id,created_by,url,hostname,key_ref)
 select pg_temp.fid('runtime.foreign.subscription'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2'),pg_temp.fid('owner'),
 'https://example.test/webhook',hostname,'runtime/foreign' from intelligence_control.integration_hosts limit 1;
insert into intelligence_control.delivery_heads(id,tenant_id,subscription_id,event_id,state,lease_id,lease_until)
 select pg_temp.fid('runtime.foreign.delivery'),pg_temp.fid('t'),pg_temp.fid('runtime.foreign.subscription'),o.id,'leased',pg_temp.fid('runtime.foreign.lease'),statement_timestamp()-interval '1 minute'
 from core.outbox_events o where o.tenant_id=pg_temp.fid('t') limit 1;
select lives_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'delivery.claim','{}')$$,'Scoped claim executes with actual tables');
select is((select state from intelligence_control.delivery_heads where id=pg_temp.fid('runtime.foreign.delivery')),'leased','Unreviewed expired lease is untouched');
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'delivery.outcome',jsonb_build_object('deliveryId',pg_temp.fid('runtime.foreign.delivery'),'leaseId',pg_temp.fid('runtime.foreign.lease'),'state','unknown'))$$,'42501','RUNTIME_SCOPE_DENIED','Foreign lease outcome denied before mutation');
select is(api.wave5_runtime_worker(pg_temp.fid('runtime'),'subscription.due','{}')->'items','[]'::jsonb,'Scheduler excludes other synthetic tenants');
update intelligence_control.runtime_worker_scopes set enabled=false where runtime_id=pg_temp.fid('runtime');
select throws_ok($$select api.wave5_runtime_worker(pg_temp.fid('runtime'),'delivery.readiness','{}')$$,'42501','RUNTIME_SCOPE_DENIED','Revoked runtime fails before readiness');
insert into intelligence_control.operators(actor_id,active,health_read,grant_manage) values(pg_temp.fid('outsider'),true,true,true) on conflict(actor_id) do update set active=true,health_read=true,grant_manage=true;
insert into intelligence_control.runtime_operator_authorities(operator_id,tenant_id,reason,expires_at)
 values(pg_temp.fid('outsider'),pg_temp.fid('t'),'Owner reviewed runtime health acceptance only',statement_timestamp()+interval '30 minutes');
select pg_temp.actor('outsider');
select lives_ok($$select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('outsider'),'Owner reviewed runtime health acceptance only',statement_timestamp()+interval '20 minutes',pg_temp.fid('runtime.grant'))$$,'Scoped operator uses installed grant API');
select throws_ok($$select api.issue_operator_tenant_grant(pg_temp.wid('tenant'),pg_temp.fid('outsider'),'Owner reviewed runtime health acceptance only',statement_timestamp()+interval '20 minutes',pg_temp.fid('runtime.foreign.grant'))$$,'42501','RUNTIME_OPERATOR_SCOPE_DENIED','Operator cannot grant foreign tenant');
select throws_ok($$select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('outsider'),'Other unreviewed reason for health',statement_timestamp()+interval '20 minutes',pg_temp.fid('runtime.reason.grant'))$$,'42501','RUNTIME_OPERATOR_SCOPE_DENIED','Operator cannot change reviewed reason');
select throws_ok($$select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('outsider'),'Owner reviewed runtime health acceptance only',statement_timestamp()+interval '40 minutes',pg_temp.fid('runtime.long.grant'))$$,'42501','RUNTIME_OPERATOR_SCOPE_DENIED','Operator cannot extend fixed authority deadline');
select throws_ok($$select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('owner'),'Owner reviewed runtime health acceptance only',statement_timestamp()+interval '20 minutes',pg_temp.fid('runtime.other.operator.grant'))$$,'42501','RUNTIME_OPERATOR_SCOPE_DENIED','Operator cannot issue to another operator');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('outsider'),'role','authenticated','aal','aal1')::text,true);
select throws_ok($$select api.issue_operator_tenant_grant(pg_temp.fid('t'),pg_temp.fid('outsider'),'Owner reviewed runtime health acceptance only',statement_timestamp()+interval '20 minutes',pg_temp.fid('runtime.aal1.grant'))$$,'42501','OPERATOR_ACCESS_REQUIRED','Installed operator MFA check preserved');
