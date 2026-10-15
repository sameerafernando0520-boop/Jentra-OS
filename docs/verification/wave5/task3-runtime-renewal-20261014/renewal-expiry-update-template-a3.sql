-- SOURCE-ONLY guarded template; the NULL approval/time inputs make it fail closed.
-- A new exact successor helper must bind actual human approval, preflight,
-- owner metadata, rendered SQL and final independent operation review.
-- No SQL in this packet has been executed or database-tested.
BEGIN;
SET LOCAL standard_conforming_strings=on;
SET LOCAL search_path=pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $renew_exact_two_expiries$
DECLARE
 v_human_approval_sha256 text := NULL;
 v_review_packet_sha256 text := NULL;
 v_human_approved_at timestamptz := NULL;
 v_server_anchor timestamptz := NULL;
 v_owner_metadata_expires_at timestamptz := NULL;
 v_maximum_minutes integer := 120;
 v_new_expiry timestamptz;
 a intelligence_control.edge_authorities%rowtype;
 s intelligence_control.runtime_worker_scopes%rowtype;
 n integer;
BEGIN
 IF v_human_approval_sha256 IS NULL OR v_human_approval_sha256 !~ '^[a-f0-9]{64}$'
  OR v_review_packet_sha256 IS NULL OR v_review_packet_sha256 !~ '^[a-f0-9]{64}$'
  OR v_human_approved_at IS NULL OR v_server_anchor IS NULL OR v_owner_metadata_expires_at IS NULL
  OR v_maximum_minutes IS NULL OR v_maximum_minutes NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'ACTUAL_EXACT_HUMAN_APPROVAL_AND_WINDOW_REQUIRED'; END IF;
 IF NOT isfinite(v_human_approved_at) OR NOT isfinite(v_server_anchor) OR NOT isfinite(v_owner_metadata_expires_at)
  OR v_server_anchor<v_human_approved_at OR v_server_anchor>clock_timestamp()+interval '10 seconds'
  OR clock_timestamp()-v_server_anchor>interval '45 seconds' THEN RAISE EXCEPTION 'FRESH_POST_APPROVAL_SERVER_ANCHOR_REQUIRED'; END IF;
 v_new_expiry:=least(v_server_anchor+make_interval(mins=>v_maximum_minutes),v_owner_metadata_expires_at);
 IF v_new_expiry<=clock_timestamp()+interval '90 seconds' THEN RAISE EXCEPTION 'BOUNDED_RENEWAL_WINDOW_REQUIRED'; END IF;
 SELECT * INTO STRICT a FROM intelligence_control.edge_authorities WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7' FOR UPDATE;
 SELECT * INTO STRICT s FROM intelligence_control.runtime_worker_scopes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'
  AND tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c' AND legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd' AND branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1' FOR UPDATE;
 PERFORM jobid FROM cron.job WHERE jobid IN(4,5,6) ORDER BY jobid FOR SHARE;
 IF current_user<>'postgres' OR NOT a.enabled OR NOT s.enabled
  OR a.issued_at<>'2026-10-13T09:57:07.481942+00:00'::timestamptz OR a.expires_at<>'2026-10-14T09:57:07.481942+00:00'::timestamptz
  OR s.issued_at<>'2026-10-13T08:13:04.144135+00:00'::timestamptz OR s.expires_at<>'2026-10-14T08:13:04.144135+00:00'::timestamptz
  OR (SELECT count(*) FROM intelligence_control.runtime_worker_scopes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')<>1
  OR a.job_ids IS DISTINCT FROM ARRAY[4,5,6]::bigint[] THEN RAISE EXCEPTION 'EXACT_TWO_OLD_ROWS_REQUIRED'; END IF;
 IF v_new_expiry>a.issued_at+interval '7 days' OR v_new_expiry>s.issued_at+interval '7 days'
  THEN RAISE EXCEPTION 'ORIGINAL_SCHEMA_WINDOW_LIMIT_REQUIRED'; END IF;
 IF encode(extensions.digest((to_jsonb(a)-'expires_at')::text,'sha256'),'hex')<>'77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139'
  OR (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(scope_row)-'expires_at' ORDER BY tenant_id,legal_entity_id,branch_id)::text,'[]'),'sha256'),'hex')
 FROM intelligence_control.runtime_worker_scopes scope_row WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')<>'3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387' THEN RAISE EXCEPTION 'UNCHANGED_NON_WINDOW_ROW_HASHES_REQUIRED'; END IF;
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>115
  OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='api')<>363
  OR (SELECT jsonb_agg(jsonb_build_object('identity',p.oid::regprocedure::text,'oid',p.oid::text,
 'bodySha256',encode(extensions.digest(p.prosrc,'sha256'),'hex'),
 'definitionSha256',encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'),
 'securityDefiner',p.prosecdef,'configuration',p.proconfig,'grants',p.proacl) ORDER BY p.oid::regprocedure::text)
 FROM pg_proc p WHERE p.oid=ANY(ARRAY['api.wave5_edge_control(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_delivery_worker(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_worker(uuid,text,jsonb)'::regprocedure,'intelligence_control.edge_schedule_tick(text)'::regprocedure,'intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)'::regprocedure,'intelligence_control.runtime_tenant_allowed(uuid,uuid)'::regprocedure,'intelligence_control.runtime_worker_required(uuid)'::regprocedure])) IS DISTINCT FROM '[{"oid":"2913664","grants":["postgres=X/postgres","service_role=X/postgres"],"identity":"api.wave5_edge_control(uuid,text,jsonb)","bodySha256":"91850c1686eb52b997564568b536747f563163e80d358d04874d1c1283e4d015","configuration":["search_path=\"\""],"securityDefiner":true,"definitionSha256":"7659bb6645b41ac50957f978604879d72d52202c347f8318caa5c4a04b516dfc"},{"oid":"2913561","grants":["postgres=X/postgres","service_role=X/postgres"],"identity":"api.wave5_runtime_delivery_worker(uuid,text,jsonb)","bodySha256":"7fe0c609f81e5ee942517ac5b7370c3a1ef1232a700e2a95c63d9aa425a482e3","configuration":["search_path=\"\""],"securityDefiner":true,"definitionSha256":"576f78698fb51b6d49ca0c0d6b6f2e43f1a91a189c77439de957fea35fc2c501"},{"oid":"2913565","grants":["postgres=X/postgres","service_role=X/postgres"],"identity":"api.wave5_runtime_worker(uuid,text,jsonb)","bodySha256":"3ae1ff01c51e655b442c307ac64752dabd8e45e4c0f5168ed7ef5a3e8c7f1550","configuration":["search_path=\"\""],"securityDefiner":true,"definitionSha256":"174ef338fa9cd5ccba2189ac2b3b858a6c65f274917ea0768a3dc57d33a684d0"},{"oid":"2913766","grants":["postgres=X/postgres"],"identity":"intelligence_control.edge_schedule_tick(text)","bodySha256":"8fecbd2673c72f0a28b16d5a2a272e017f15647899e65306968acaac0fd519ff","configuration":["search_path=\"\""],"securityDefiner":true,"definitionSha256":"c330d3cc533e3b2e0ca08997089463ca24371a5d267c70f74da1b4793ee5eea4"},{"oid":"2913535","grants":["postgres=X/postgres"],"identity":"intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)","bodySha256":"52d09fa523f6766e5cea3ab3e591ee581840be5779a745d90b0efc3905cefb7a","configuration":["search_path=\"\""],"securityDefiner":true,"definitionSha256":"04dd1c054f35e24ebc62c205b8672392f656745d5e2b52c4f4ab4bd19c67adb9"},{"oid":"2913536","grants":["postgres=X/postgres"],"identity":"intelligence_control.runtime_tenant_allowed(uuid,uuid)","bodySha256":"6e60d0231efc0fc2afcfb75b845338385dd3a21e088564dd7ddf36c6350090af","configuration":["search_path=\"\""],"securityDefiner":true,"definitionSha256":"50e7a58ed44e041ee6bdf18254e17ff3ca4259c5de03f2ce10ee880968250280"},{"oid":"2913537","grants":["postgres=X/postgres"],"identity":"intelligence_control.runtime_worker_required(uuid)","bodySha256":"dab2dfd59274c75b93c951668febfd6e080b00db41ca88f491d6e38f45136f6b","configuration":["search_path=\"\""],"securityDefiner":true,"definitionSha256":"a2e98ffe2a5d5e8ca2d3dc37af67a6065e9b6f50c8bb6627a6bcb6fcfa885b12"}]'::jsonb
  THEN RAISE EXCEPTION 'UNCHANGED_115_363_AND_SEVEN_FUNCTION_ACL_BINDINGS_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=ANY(ARRAY['api.wave5_edge_control(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_delivery_worker(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_worker(uuid,text,jsonb)'::regprocedure,'intelligence_control.edge_schedule_tick(text)'::regprocedure,'intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)'::regprocedure,'intelligence_control.runtime_tenant_allowed(uuid,uuid)'::regprocedure,'intelligence_control.runtime_worker_required(uuid)'::regprocedure])
  AND p.prosrc ~* 'issued_at[[:space:]]*\+[[:space:]]*interval[[:space:]]+''24 hours''')
  THEN RAISE EXCEPTION 'SEPARATELY_REVIEWED_SOURCE_SUCCESSOR_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN('intelligence_control.edge_authorities'::regclass,
  'intelligence_control.runtime_worker_scopes'::regclass) AND NOT tgisinternal)
  THEN RAISE EXCEPTION 'UNREVIEWED_UPDATE_TRIGGER_FORBIDDEN'; END IF;
 IF (SELECT count(*) FROM pg_class WHERE oid IN('intelligence_control.edge_authorities'::regclass,
  'intelligence_control.runtime_worker_scopes'::regclass) AND relrowsecurity AND relforcerowsecurity)<>2
  THEN RAISE EXCEPTION 'ORIGINAL_FORCED_RLS_REQUIRED'; END IF;
 IF (SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) ORDER BY jobid)
  FROM cron.job WHERE jobid IN(4,5,6)) IS DISTINCT FROM '[{"name":"jentra-w5-20261009-delivery","jobId":4,"active":false,"command":"select intelligence_control.edge_schedule_tick(''delivery'');","schedule":"* * * * *"},{"name":"jentra-w5-20261009-subscription","jobId":5,"active":false,"command":"select intelligence_control.edge_schedule_tick(''subscription'');","schedule":"* * * * *"},{"name":"jentra-w5-20261009-health","jobId":6,"active":false,"command":"select intelligence_control.edge_schedule_tick(''health'');","schedule":"* * * * *"}]'::jsonb
  OR (SELECT count(*) FROM cron.job WHERE jobname IN('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'))<>3
  OR (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN(4,5,6))<>'4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945' THEN RAISE EXCEPTION 'EXACT_THREE_PAUSED_JOBS_AND_OUTSIDE_PRESERVATION_REQUIRED'; END IF;
 IF (SELECT jsonb_agg(jsonb_build_object('ref',ref,'secretId',secret_id) ORDER BY ref) FROM intelligence_control.edge_key_refs WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')
  IS DISTINCT FROM '[{"ref":"w5/runtime/20261008/delivery/v1","secretId":"2265a75b-8e27-4094-840e-9a68b1801872"},{"ref":"w5/runtime/20261008/delivery/v2","secretId":"394d3fe9-af6a-4f0d-9079-a436591f59aa"}]'::jsonb THEN RAISE EXCEPTION 'UNCHANGED_TWO_KEY_REFERENCES_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')
  OR EXISTS(SELECT 1 FROM intelligence_control.model_invocations WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c')
  THEN RAISE EXCEPTION 'PRESERVED_ZERO_WORKER_MODEL_START_REQUIRED'; END IF;
 IF (SELECT jsonb_agg(jsonb_build_object('name',attname,'type',atttypid::regtype::text,'required',attnotnull) ORDER BY attnum)
 FROM pg_attribute WHERE attrelid='intelligence_control.edge_authorities'::regclass AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM '[{"name":"runtime_id","type":"uuid","required":true},{"name":"enabled","type":"boolean","required":true},{"name":"issued_at","type":"timestamp with time zone","required":true},{"name":"expires_at","type":"timestamp with time zone","required":true},{"name":"schedule_secret_id","type":"uuid","required":true},{"name":"schedule_secret_hash","type":"text","required":true},{"name":"publishable_key","type":"text","required":true},{"name":"job_ids","type":"bigint[]","required":true}]'::jsonb
  OR (SELECT jsonb_agg(jsonb_build_object('name',attname,'type',atttypid::regtype::text,'required',attnotnull) ORDER BY attnum)
 FROM pg_attribute WHERE attrelid='intelligence_control.runtime_worker_scopes'::regclass AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM '[{"name":"runtime_id","type":"uuid","required":true},{"name":"tenant_id","type":"uuid","required":true},{"name":"legal_entity_id","type":"uuid","required":true},{"name":"branch_id","type":"uuid","required":true},{"name":"enabled","type":"boolean","required":true},{"name":"issued_at","type":"timestamp with time zone","required":true},{"name":"expires_at","type":"timestamp with time zone","required":true}]'::jsonb
  THEN RAISE EXCEPTION 'EXACT_TWO_TABLE_COLUMN_CONTRACTS_REQUIRED'; END IF;
 IF (SELECT count(*) FROM billing.tenant_subscriptions WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'
  AND status='trialing' AND trial_ends_at='2026-10-20T08:13:04.144135+00:00'::timestamptz
  AND trial_ends_at>=v_new_expiry)<>1 THEN RAISE EXCEPTION 'UNCHANGED_BILLING_WINDOW_MUST_COVER_RENEWAL'; END IF;
 IF clock_timestamp()-v_server_anchor>interval '45 seconds' OR clock_timestamp()>=v_new_expiry-interval '90 seconds'
  THEN RAISE EXCEPTION 'ANCHOR_OR_RENEWAL_WINDOW_EXPIRED'; END IF;
 IF jsonb_build_object('journals',(SELECT count(*) FROM finance.journal_entries WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'lines',(SELECT count(*) FROM finance.journal_lines WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'publications',(SELECT count(*) FROM finance.financial_reports WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'classifications',(SELECT count(*) FROM analytics.statement_classifications WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'dateProposals',(SELECT count(*) FROM analytics.cash_date_proposals WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'dateDecisions',(SELECT count(*) FROM analytics.cash_date_decisions WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'scenarios',(SELECT count(*) FROM analytics.cash_scenario_revisions WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'exports',(SELECT count(*) FROM core.export_jobs WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'processEvents',(SELECT count(*) FROM workflow.process_events WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c')) IS DISTINCT FROM '{"journals":9,"lines":18,"publications":3,"classifications":1,"dateProposals":3,"dateDecisions":3,"scenarios":0,"exports":0,"processEvents":7}'::jsonb
  OR jsonb_build_object('ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'outcomes',(SELECT count(*) FROM intelligence_control.edge_tick_outcomes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'deliveryOutcomes',(SELECT count(*) FROM intelligence_control.delivery_outcomes WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'receiverReceipts',(SELECT count(*) FROM intelligence_control.edge_receiver_receipts WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'modelInvocations',(SELECT count(*) FROM intelligence_control.model_invocations WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'usageEvents',(SELECT count(*) FROM intelligence_control.usage_events WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'modelOutcomes',
 (SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c')) IS DISTINCT FROM '{"ticks":0,"outcomes":0,"quotaPeriods":0,"deliveryOutcomes":0,"receiverReceipts":0,"modelInvocations":0,"usageEvents":0,"modelOutcomes":0}'::jsonb
  OR (SELECT count(*) FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>='2026-10-13T09:57:07.481942Z'::timestamptz)<>24
  THEN RAISE EXCEPTION 'PRESERVED_FINANCE_AND_WORKER_COUNTERS_REQUIRED'; END IF;
 UPDATE intelligence_control.edge_authorities SET expires_at=v_new_expiry
  WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7' AND expires_at='2026-10-14T09:57:07.481942+00:00'::timestamptz;
 GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'EXACT_ONE_EDGE_EXPIRY_UPDATE_REQUIRED'; END IF;
 UPDATE intelligence_control.runtime_worker_scopes SET expires_at=v_new_expiry
  WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7' AND tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c' AND legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd' AND branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'
   AND expires_at='2026-10-14T08:13:04.144135+00:00'::timestamptz;
 GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'EXACT_ONE_SCOPE_EXPIRY_UPDATE_REQUIRED'; END IF;
 SELECT * INTO STRICT a FROM intelligence_control.edge_authorities WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7';
 IF a.expires_at<>v_new_expiry OR encode(extensions.digest((to_jsonb(a)-'expires_at')::text,'sha256'),'hex')<>'77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139'
  OR (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(scope_row)-'expires_at' ORDER BY tenant_id,legal_entity_id,branch_id)::text,'[]'),'sha256'),'hex')
 FROM intelligence_control.runtime_worker_scopes scope_row WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')<>'3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387'
  OR (SELECT expires_at FROM intelligence_control.runtime_worker_scopes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7' AND tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'
   AND legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd' AND branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1')<>v_new_expiry
  OR NOT intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1')
  OR EXISTS(SELECT 1 FROM cron.job WHERE jobid IN(4,5,6) AND active)
  OR (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN(4,5,6))<>'4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945' THEN RAISE EXCEPTION 'EXACT_TWO_EXPIRIES_ONLY_POSTCHECK_REQUIRED'; END IF;
 IF jsonb_build_object('journals',(SELECT count(*) FROM finance.journal_entries WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'lines',(SELECT count(*) FROM finance.journal_lines WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'publications',(SELECT count(*) FROM finance.financial_reports WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'classifications',(SELECT count(*) FROM analytics.statement_classifications WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'dateProposals',(SELECT count(*) FROM analytics.cash_date_proposals WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'dateDecisions',(SELECT count(*) FROM analytics.cash_date_decisions WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'scenarios',(SELECT count(*) FROM analytics.cash_scenario_revisions WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'exports',(SELECT count(*) FROM core.export_jobs WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'processEvents',(SELECT count(*) FROM workflow.process_events WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c')) IS DISTINCT FROM '{"journals":9,"lines":18,"publications":3,"classifications":1,"dateProposals":3,"dateDecisions":3,"scenarios":0,"exports":0,"processEvents":7}'::jsonb
  OR jsonb_build_object('ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'outcomes',(SELECT count(*) FROM intelligence_control.edge_tick_outcomes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'deliveryOutcomes',(SELECT count(*) FROM intelligence_control.delivery_outcomes WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'receiverReceipts',(SELECT count(*) FROM intelligence_control.edge_receiver_receipts WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'modelInvocations',(SELECT count(*) FROM intelligence_control.model_invocations WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'usageEvents',(SELECT count(*) FROM intelligence_control.usage_events WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),'modelOutcomes',
 (SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c')) IS DISTINCT FROM '{"ticks":0,"outcomes":0,"quotaPeriods":0,"deliveryOutcomes":0,"receiverReceipts":0,"modelInvocations":0,"usageEvents":0,"modelOutcomes":0}'::jsonb
  OR (SELECT count(*) FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>='2026-10-13T09:57:07.481942Z'::timestamptz)<>24
  THEN RAISE EXCEPTION 'PRESERVED_FINANCE_AND_WORKER_COUNTERS_REQUIRED'; END IF;
END $renew_exact_two_expiries$;
COMMIT;

-- This is an actual server post-commit observation, not a client timestamp.
-- The earlier fresh preflight remains the conservative expiry anchor.
SELECT jsonb_build_object('runtimeId','778237e3-3d4e-4871-8cc9-e08b07b989c7','appliedAt',clock_timestamp(),
 'expiresAt',(SELECT expires_at FROM intelligence_control.edge_authorities WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'affectedRows',2,'applicationTimestampProvenance','server-post-commit-observation') AS renewal_application;
