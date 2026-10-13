-- Installed metadata assertions only: no pgtap install, fixture, Auth DML or JWT claims.
BEGIN READ ONLY;
DO $installed_metadata$
DECLARE failed integer;
BEGIN
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>114 THEN RAISE EXCEPTION 'FINAL_LEDGER_COUNT_MISMATCH'; END IF;
 SELECT count(*) INTO failed FROM (VALUES ('analytics.cash_date_decisions'),('analytics.cash_date_proposals'),('analytics.cash_scenario_revisions'),('analytics.pipeline_forecasts'),('analytics.statement_classifications'),('core.operational_reports'),('core.wave3_notification_subscriptions'),('finance.allocation_reversals'),('finance.budget_events'),('finance.budget_variance_reports'),('finance.budget_versions'),('finance.cash_flow_mapping_events'),('finance.close_control_reviews'),('finance.control_account_basis'),('finance.control_reports'),('finance.dimension_events'),('finance.dimensions'),('finance.financial_reports'),('finance.fx_revaluation_reversals'),('finance.fx_revaluation_runs'),('finance.manual_journals'),('finance.period_events'),('finance.period_reopen_requests'),('finance.tax_definition_versions'),('finance.tax_reports'),('intelligence_control.edge_authorities'),('intelligence_control.edge_key_refs'),('intelligence_control.edge_receiver_receipts'),('intelligence_control.edge_tick_outcomes'),('intelligence_control.edge_ticks'),('intelligence_control.health_probes'),('intelligence_control.operator_access_events'),('intelligence_control.operator_tenant_grants'),('intelligence_control.operators'),('intelligence_control.proposal_decisions'),('intelligence_control.proposal_executions'),('intelligence_control.proposals'),('intelligence_control.quota_periods'),('intelligence_control.runtime_operator_authorities'),('intelligence_control.runtime_worker_scopes'),('intelligence_control.subscription_activations'),('intelligence_control.subscription_revisions'),('intelligence_control.synthetic_tenants'),('intelligence_control.usage_corrections'),('intelligence_control.usage_events'),('intelligence_control.usage_reservations'),('inventory.product_unit_conversions'),('inventory.product_unit_history'),('inventory.reservation_history'),('inventory.reservation_history_coverage'),('inventory.stock_counts'),('inventory.stock_dispositions'),('inventory.valuation_reports'),('inventory.value_adjustments'),('people.department_revisions'),('people.departments'),('people.organization_assignments'),('people.organization_consumptions'),('people.organization_withdrawals'),('people.raw_clock_batch_rows'),('people.raw_clock_batches'),('procurement.purchase_orders'),('procurement.receipt_allowances'),('procurement.requisition_history'),('procurement.requisition_lines'),('procurement.requisitions'),('procurement.rfqs'),('procurement.supplier_quote_lines'),('projects.payroll_billing_effects'),('projects.payroll_time_impacts'),('projects.service_cost_revisions'),('service.asset_equipment_links')) e(name)
 LEFT JOIN pg_class c ON c.oid=to_regclass(e.name) WHERE NOT coalesce(c.relrowsecurity AND c.relforcerowsecurity,false);
 IF failed<>0 THEN RAISE EXCEPTION 'INSTALLED_FORCED_RLS_MISMATCH:%',failed; END IF;
 WITH expected(signature,role_name,allowed) AS (VALUES
('api.wave5_runtime_worker(uuid,text,jsonb)','authenticated',false),
('api.wave5_runtime_worker(uuid,text,jsonb)','service_role',true),
('api.wave5_edge_control(uuid,text,jsonb)','authenticated',false),
('api.wave5_edge_control(uuid,text,jsonb)','service_role',true),
('intelligence_control.edge_schedule_tick(text)','service_role',false),
('analytics.cash_source_rows(uuid,uuid,uuid,text,date,timestamptz)','authenticated',false),
('api.get_pipeline_forecast(uuid,uuid,uuid,uuid)','authenticated',true),
('api.get_wave5_subscription(uuid)','authenticated',true),
('api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)','authenticated',true),
('api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)','authenticated',true),
('api.accept_invitation(text)','authenticated',true),
('api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)','service_role',true),
('api.apply_synthetic_subscription(uuid,uuid)','service_role',true),
('api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)','authenticated',true),
('api.wave5_runtime_delivery_worker(uuid,text,jsonb)','service_role',true),
('api.schedule_synthetic_subscription(uuid,uuid,uuid,timestamptz,bigint,text,integer,timestamptz,timestamptz)','authenticated',true),
('api.create_invitation(uuid,text,uuid,uuid,uuid,integer)','authenticated',true),
('api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb)','authenticated',true)
 ) SELECT count(*) INTO failed FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
 WHERE p.oid IS NULL OR has_function_privilege(e.role_name,p.oid,'EXECUTE') IS DISTINCT FROM e.allowed;
 IF failed<>0 THEN RAISE EXCEPTION 'INSTALLED_FUNCTION_GRANT_MISMATCH:%',failed; END IF;
 SELECT count(*) INTO failed FROM (VALUES ('api.wave5_runtime_worker(uuid,text,jsonb)'),('api.wave5_edge_control(uuid,text,jsonb)'),('intelligence_control.edge_schedule_tick(text)'),('analytics.cash_source_rows(uuid,uuid,uuid,text,date,timestamptz)'),('api.get_pipeline_forecast(uuid,uuid,uuid,uuid)'),('api.get_wave5_subscription(uuid)'),('api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)'),('api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)'),('api.accept_invitation(text)'),('api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)'),('api.apply_synthetic_subscription(uuid,uuid)'),('api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)'),('api.wave5_runtime_delivery_worker(uuid,text,jsonb)'),('api.schedule_synthetic_subscription(uuid,uuid,uuid,timestamptz,bigint,text,integer,timestamptz,timestamptz)'),('api.create_invitation(uuid,text,uuid,uuid,uuid,integer)'),('api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb)')) e(signature)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
 WHERE p.oid IS NULL OR has_function_privilege('anon',p.oid,'EXECUTE') OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE');
 IF failed<>0 THEN RAISE EXCEPTION 'INSTALLED_ANON_PUBLIC_GRANT_MISMATCH:%',failed; END IF;
 IF has_table_privilege('authenticated','analytics.cash_date_proposals','SELECT') OR has_table_privilege('authenticated','analytics.cash_date_decisions','SELECT') THEN RAISE EXCEPTION 'PRIVATE_CASH_DIRECT_READ_GRANTED'; END IF;
END
$installed_metadata$;
SELECT jsonb_build_object('observedAt',statement_timestamp(),'strictMetadataPredicatesPassed',true,
 'ledgerCount',114,'forcedRlsPredicates',72,'functionGrantPredicates',18,
 'behaviorFixturesExecuted',false,'realAuthVerified',false,'realMfaVerified',false,'actualDeliveryVerified',false) AS strict_metadata;
ROLLBACK;
