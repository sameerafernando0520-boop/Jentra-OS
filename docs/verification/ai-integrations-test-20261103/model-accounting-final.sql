begin read only;
set local transaction_read_only=on;
set local statement_timeout='10s';
set local search_path='';
select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),
 'invocationId','bf887435-88db-4a1f-9df9-2e9ec326f9b4',
 'invocation',(select jsonb_build_object('tenantId',tenant_id,'sourceId',source_id,'sourceHash',source_hash,'manifestHash',manifest_hash,
 'createdAt',created_at,'maxTokens',request->>'maxTokens','periodStart',request->>'periodStart','periodEnd',request->>'periodEnd')
 from intelligence_control.model_invocations where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'outcome',(select jsonb_build_object('state',state,'tokens',tokens::text,'recordedAt',recorded_at)
 from intelligence_control.model_outcomes where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'reservation',(select jsonb_build_object('metric',metric_code,'reservedUnits',reserved_units::text,'periodStart',period_start)
 from intelligence_control.usage_reservations where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'usage',(select jsonb_build_object('eventId',event_id,'quantity',quantity::text)
 from intelligence_control.usage_events where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'modelInvocationCount',(select count(*) from intelligence_control.model_invocations where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'quotaPeriods',coalesce((select jsonb_agg(jsonb_build_object('metric',metric_code,'periodStart',period_start,'periodEnd',period_end,
 'reserved',reserved_units::text,'settled',settled_units::text)) from intelligence_control.quota_periods
 where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'originalDeliveries',coalesce((select jsonb_agg(jsonb_build_object('id',id,'state',state,'attempt',attempt,'invocationId',invocation_id))
 from intelligence_control.delivery_heads where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'receiverReceipts',(select count(*) from intelligence_control.edge_receiver_receipts where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'subscription',(select jsonb_build_object('plan',plan_code,'seats',seats,'version',version::text,'trialStart',trial_started_at,'trialEnd',trial_ends_at,'windowActive',trial_started_at<=statement_timestamp() and trial_ends_at>statement_timestamp()) from billing.tenant_subscriptions where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'runtimeScope',(select jsonb_build_object('issuedAt',issued_at,'expiresAt',expires_at,'enabled',enabled,'windowActive',issued_at<=statement_timestamp() and expires_at>statement_timestamp()) from intelligence_control.runtime_worker_scopes where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid and tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid),
 'readerPermissions',(select jsonb_agg(permission_code order by permission_code) from core.role_permissions where role_id='28d81f05-27c5-4673-85d5-eeb51a515f27'::uuid)
 ) as final_model_attempt_accounting;
rollback;
