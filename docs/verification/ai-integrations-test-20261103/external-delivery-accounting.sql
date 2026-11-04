begin read only;
set local transaction_read_only=on;
set local statement_timeout='10s';
set local search_path='';
with snapshot as (select jsonb_build_object(
 'projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),
 'syntheticAllowed',exists(select 1 from intelligence_control.synthetic_tenants where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and allowed),
 'activeMemberCount',(select count(*) from core.memberships where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and status='active'),
 'nonFixtureBillingMemberships',(select count(*) from core.memberships m join core.tenants t on t.id=m.tenant_id where m.user_id='c6aa32c0-d91f-4555-8687-e77fdf878e0c'::uuid and t.slug!~'^jentra-w5-(runtime|load-[0-9]{3})-20261008$'),
 'readerPermissions',(select jsonb_agg(permission_code order by permission_code) from core.role_permissions where role_id='28d81f05-27c5-4673-85d5-eeb51a515f27'::uuid),
 'modelInvocationCount',(select count(*) from intelligence_control.model_invocations where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'aiOutcome',(select jsonb_build_object('state',state,'tokens',tokens::text) from intelligence_control.model_outcomes where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'webhookPlanQuota',(select jsonb_build_object('enabled',p.enabled,'limit',p.numeric_limit::text) from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code where s.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and p.entitlement_code='quota.webhook.deliveries'),
 'delivery',(select to_jsonb(d) from intelligence_control.delivery_heads d where id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),
 'allHeads',coalesce((select jsonb_agg(to_jsonb(d) order by d.id) from intelligence_control.delivery_heads d where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'attempts',coalesce((select jsonb_agg(to_jsonb(a) order by attempt) from intelligence_control.delivery_attempts a where delivery_id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),'[]'::jsonb),
 'outcomes',coalesce((select jsonb_agg(to_jsonb(o) order by attempt) from intelligence_control.delivery_outcomes o where delivery_id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),'[]'::jsonb),
 'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by recorded_at) from intelligence_control.delivery_reviews r where delivery_id='091e0c08-5038-4169-8e28-ffde9e0d51c8'::uuid),'[]'::jsonb),
 'subscriptions',coalesce((select jsonb_agg(to_jsonb(s) order by id) from intelligence_control.integration_subscriptions s where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'receiverReceipts',coalesce((select jsonb_agg(jsonb_build_object('eventId',event_id,'subscriptionId',subscription_id,'sha256',sha256,'computedSha256',encode(extensions.digest(payload,'sha256'),'hex'),'payloadBase64',encode(payload,'base64'),'payloadBytes',octet_length(payload),'runtimeId',runtime_id,'tenantId',tenant_id,'entityId',legal_entity_id,'branchId',branch_id,'receivedAt',received_at,'keyVersion',key_version,'signedTimestamp',signed_timestamp) order by received_at) from intelligence_control.edge_receiver_receipts where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
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
 'functions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'args',pg_catalog.pg_get_function_identity_arguments(p.oid),'bodyMd5',md5(p.prosrc),'securityDefiner',p.prosecdef,'config',p.proconfig,'acl',p.proacl::text) order by n.nspname,p.proname) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where (n.nspname,p.proname) in (('api','wave5_runtime_worker'),('intelligence_control','worker_required'),('api','wave5_runtime_delivery_worker'),('api','wave5_edge_control'),('api','wave5_reserve_usage'),('api','wave5_settle_usage'),('intelligence_control','runtime_worker_required'),('intelligence_control','delivery_authorize'),('intelligence_control','runtime_scope_allowed'),('intelligence_control','quota_limit')))
 ) as evidence)
select evidence#>>'{delivery,state}' as delivery_state,
 evidence#>>'{outcomes,0,http_status}' as http_status,
 jsonb_array_length(evidence->'receiverReceipts') as receiver_receipts,
 evidence#>>'{usage,quantity}' as webhook_units,
 (select q->>'reserved_units' from jsonb_array_elements(evidence->'quotaPeriods') q where q->>'metric_code'='webhook.deliveries') as webhook_reserved,
 evidence as verified_evidence from snapshot;
rollback;
