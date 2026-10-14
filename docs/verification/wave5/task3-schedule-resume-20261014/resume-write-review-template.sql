-- SOURCE REVIEW TEMPLATE ONLY. Replace the four markers solely through buildResumeSql after an independently pinned actual guard fingerprint read. This file is never dispatched.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $resume_exact_jobs$
DECLARE a intelligence_control.edge_authorities%rowtype; j bigint; recorded bigint;
BEGIN
 SELECT * INTO a FROM intelligence_control.edge_authorities WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7' FOR UPDATE;
 IF NOT FOUND OR NOT a.enabled OR a.issued_at<>'2026-10-13T09:57:07.481942Z'::timestamptz OR a.expires_at<>'2026-10-14T09:57:07.481942Z'::timestamptz
  OR a.expires_at<=statement_timestamp() OR a.expires_at>a.issued_at+interval '24 hours'
  OR cardinality(a.job_ids)<>3 OR NOT a.job_ids @> ARRAY[4,5,6]::bigint[] THEN RAISE EXCEPTION 'EXACT_UNEXPIRED_AUTHORITY_REQUIRED'; END IF;
 IF NOT intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1') THEN RAISE EXCEPTION 'EXACT_APPROVED_SCOPE_REQUIRED'; END IF;
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>115 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api')<>363
  THEN RAISE EXCEPTION 'EXACT_115_363_BASELINE_REQUIRED'; END IF;
 IF (SELECT jsonb_agg(jsonb_build_object('signature',s,'md5',md5(pg_get_functiondef(s::regprocedure))) ORDER BY s) FROM unnest(ARRAY['intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)','intelligence_control.edge_schedule_tick(text)','api.wave5_runtime_worker(uuid,text,jsonb)','api.wave5_edge_control(uuid,text,jsonb)']) s) IS DISTINCT FROM '[{"signature":"api.wave5_edge_control(uuid,text,jsonb)","md5":"__REVIEWED_CURRENT_MD5_1__"},{"signature":"api.wave5_runtime_worker(uuid,text,jsonb)","md5":"__REVIEWED_CURRENT_MD5_2__"},{"signature":"intelligence_control.edge_schedule_tick(text)","md5":"__REVIEWED_CURRENT_MD5_3__"},{"signature":"intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)","md5":"__REVIEWED_CURRENT_MD5_4__"}]'::jsonb OR NOT has_function_privilege('service_role','api.wave5_runtime_worker(uuid,text,jsonb)','EXECUTE')
  OR NOT has_function_privilege('service_role','api.wave5_edge_control(uuid,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'UNCHANGED_SERVER_AUTHORITY_GUARDS_REQUIRED'; END IF;
 IF NOT ((SELECT count(*) FROM core.export_jobs WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c' AND actor_id='8b740ab8-24f7-4455-a78b-aea0d99d20f6' AND status='completed'
 AND id IN ('5594aa22-a243-337d-e574-9095f97b46c2'::uuid,'7ea25345-a8c0-45b0-f22b-8d1d0fba5318'::uuid))=2
 AND (SELECT count(*) FROM core.command_receipts WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c' AND actor_id='8b740ab8-24f7-4455-a78b-aea0d99d20f6' AND command_name='finance.report.export' AND aggregate_type='report_export'
 AND ((command_id='d4a0ad64-f138-b857-30d6-6fe0afe64e4f' AND aggregate_id='5594aa22-a243-337d-e574-9095f97b46c2') OR (command_id='217bcee3-d103-9513-a3e7-cc56d26e45be' AND aggregate_id='7ea25345-a8c0-45b0-f22b-8d1d0fba5318')))=2) THEN RAISE EXCEPTION 'EXACT_TWO_COMPLETED_EXPORTS_FIRST_REQUIRED'; END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobid IN (4,5,6) AND NOT active AND schedule='* * * * *'
  AND ((jobid=4 AND jobname='jentra-w5-20261009-delivery' AND command='select intelligence_control.edge_schedule_tick(''delivery'');')
   OR (jobid=5 AND jobname='jentra-w5-20261009-subscription' AND command='select intelligence_control.edge_schedule_tick(''subscription'');')
   OR (jobid=6 AND jobname='jentra-w5-20261009-health' AND command='select intelligence_control.edge_schedule_tick(''health'');')))<>3
  OR (SELECT count(*) FROM cron.job WHERE jobname IN ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'))<>3 THEN RAISE EXCEPTION 'EXACT_THREE_PAUSED_OWN_JOBS_REQUIRED'; END IF;
 IF (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(c) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job c WHERE jobid NOT IN (4,5,6))<>'4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945' THEN RAISE EXCEPTION 'OUTSIDE_JOB_PRESERVATION_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')
  OR EXISTS(SELECT 1 FROM intelligence_control.quota_periods WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c') THEN RAISE EXCEPTION 'ZERO_WORKER_START_BASELINE_REQUIRED'; END IF;
 SELECT count(*) INTO recorded FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>=a.issued_at;
 IF recorded<24 OR recorded+3*ceil(extract(epoch FROM(a.expires_at-statement_timestamp()))/60)>4320
  THEN RAISE EXCEPTION 'PRESERVED_REQUEST_BUDGET_REQUIRED'; END IF;
 FOREACH j IN ARRAY ARRAY[4,5,6]::bigint[] LOOP PERFORM cron.alter_job(j,active:=true); END LOOP;
END $resume_exact_jobs$;
COMMIT;