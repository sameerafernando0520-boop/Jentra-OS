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
 'runtimeFunctionDefinition',pg_catalog.pg_get_functiondef('api.wave5_runtime_worker(uuid,text,jsonb)'::regprocedure),
 'modelFunctionDefinition',pg_catalog.pg_get_functiondef('api.wave5_model_worker(text,jsonb)'::regprocedure)
) as model_attempt_accounting;
rollback;
