begin read only;
set local transaction_read_only=on;
set local statement_timeout='10s';
set local search_path='';
with snapshot as (select jsonb_build_object(
 'projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),
 'delivery',(select to_jsonb(d) from intelligence_control.delivery_heads d where id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),
 'allHeads',coalesce((select jsonb_agg(to_jsonb(d) order by d.id) from intelligence_control.delivery_heads d where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'attempts',coalesce((select jsonb_agg(to_jsonb(a) order by attempt) from intelligence_control.delivery_attempts a where delivery_id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),'[]'::jsonb),
 'outcomes',coalesce((select jsonb_agg(to_jsonb(o) order by attempt) from intelligence_control.delivery_outcomes o where delivery_id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),'[]'::jsonb),
 'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by recorded_at) from intelligence_control.delivery_reviews r where delivery_id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),'[]'::jsonb),
 'subscriptions',coalesce((select jsonb_agg(to_jsonb(s) order by id) from intelligence_control.integration_subscriptions s where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'receiverReceipts',coalesce((select jsonb_agg(jsonb_build_object('eventId',event_id,'subscriptionId',subscription_id,'sha256',sha256,'receivedAt',received_at,'keyVersion',key_version,'signedTimestamp',signed_timestamp) order by received_at) from intelligence_control.edge_receiver_receipts where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'reservation',(select to_jsonb(r) from intelligence_control.usage_reservations r where invocation_id='257b49a7-0be2-4319-b6bd-a574ae9bb59f'::uuid),
 'usage',(select to_jsonb(u) from intelligence_control.usage_events u where invocation_id='257b49a7-0be2-4319-b6bd-a574ae9bb59f'::uuid),
 'quotaPeriods',coalesce((select jsonb_agg(to_jsonb(q) order by metric_code,period_start) from intelligence_control.quota_periods q where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'subscription',(select jsonb_build_object('plan',plan_code,'seats',seats,'version',version::text,'status',status,'trialStart',trial_started_at,'trialEnd',trial_ends_at,'windowActive',trial_started_at<=statement_timestamp() and trial_ends_at>statement_timestamp()) from billing.tenant_subscriptions where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'runtimeScopes',coalesce((select jsonb_agg(jsonb_build_object('tenantId',tenant_id,'entityId',legal_entity_id,'branchId',branch_id,'enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,'windowActive',issued_at<=statement_timestamp() and expires_at>statement_timestamp())) from intelligence_control.runtime_worker_scopes where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid),'[]'::jsonb),
 'edgeAuthority',(select jsonb_build_object('enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,'jobIds',job_ids,'windowActive',issued_at<=statement_timestamp() and expires_at>statement_timestamp()) from intelligence_control.edge_authorities where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid),
 'edgeKeyRefs',coalesce((select jsonb_agg(jsonb_build_object('ref',ref,'vaultRecordExists',exists(select 1 from vault.secrets v where v.id=k.secret_id))) from intelligence_control.edge_key_refs k where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid),'[]'::jsonb),
 'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'active',active,'schedule',schedule) order by jobid) from cron.job where jobid in(4,5,6)),'[]'::jsonb),
 'tickCount',(select count(*) from intelligence_control.edge_ticks where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid),
 'unmaterializedDeliveries',coalesce((select jsonb_agg(jsonb_build_object('subscriptionId',s.id,'eventId',e.id,'forecastId',f.id,'eventCreatedAt',e.created_at) order by e.created_at,e.id,s.id) from intelligence_control.integration_subscriptions s join analytics.pipeline_forecasts f on f.tenant_id=s.tenant_id and f.legal_entity_id=s.legal_entity_id and f.branch_id is not distinct from s.branch_id join core.outbox_events e on e.tenant_id=f.tenant_id and e.aggregate_id=f.id and e.aggregate_type='pipeline_forecast' and e.topic='analytics.freeze_pipeline' where s.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and s.enabled and e.created_at>=s.created_at and not exists(select 1 from intelligence_control.delivery_heads h where h.tenant_id=s.tenant_id and h.subscription_id=s.id and h.event_id=e.id and h.generation=0)),'[]'::jsonb),
 'functions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'args',pg_catalog.pg_get_function_identity_arguments(p.oid),'body',p.prosrc,'securityDefiner',p.prosecdef,'config',p.proconfig,'acl',p.proacl::text) order by n.nspname,p.proname) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where (n.nspname,p.proname) in (('api','wave5_runtime_delivery_worker'),('api','wave5_edge_control'),('api','wave5_reserve_usage'),('api','wave5_settle_usage'),('intelligence_control','runtime_worker_required'),('intelligence_control','delivery_authorize'),('intelligence_control','runtime_scope_allowed'),('intelligence_control','quota_limit')))
 ) as evidence)
select evidence#>>'{delivery,state}' as delivery_state,
 evidence#>>'{delivery,attempt}' as attempt,
 jsonb_array_length(evidence->'receiverReceipts') as receiver_receipts,
 evidence#>>'{subscription,windowActive}' as trial_active,
 evidence#>>'{edgeAuthority,windowActive}' as edge_active,
 evidence as verified_evidence from snapshot;
rollback;
