BEGIN;
DO $start_exact_jobs$
DECLARE a intelligence_control.edge_authorities%rowtype; j bigint;
BEGIN
 SELECT * INTO a FROM intelligence_control.edge_authorities WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7' FOR UPDATE;
 IF NOT FOUND OR NOT a.enabled OR a.expires_at<=statement_timestamp() OR a.expires_at>a.issued_at+interval '24 hours'
  OR cardinality(a.job_ids)<>3 OR NOT a.job_ids @> ARRAY[4,5,6]::bigint[] THEN RAISE EXCEPTION 'EXACT_UNEXPIRED_AUTHORITY_REQUIRED'; END IF;
 IF NOT intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1') THEN RAISE EXCEPTION 'EXACT_APPROVED_SCOPE_REQUIRED'; END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobid IN (4,5,6) AND active AND schedule='* * * * *'
  AND ((jobid=4 AND jobname='jentra-w5-20261009-delivery' AND command='select intelligence_control.edge_schedule_tick(''delivery'');')
   OR (jobid=5 AND jobname='jentra-w5-20261009-subscription' AND command='select intelligence_control.edge_schedule_tick(''subscription'');')
   OR (jobid=6 AND jobname='jentra-w5-20261009-health' AND command='select intelligence_control.edge_schedule_tick(''health'');')))<>3
  OR (SELECT count(*) FROM cron.job WHERE jobname IN ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'))<>3 THEN RAISE EXCEPTION 'EXACT_THREE_ACTIVE_OWN_JOBS_REQUIRED'; END IF;
 IF (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(c) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job c WHERE jobid NOT IN (4,5,6))<>'4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945' THEN RAISE EXCEPTION 'OUTSIDE_JOB_PRESERVATION_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')
  OR EXISTS(SELECT 1 FROM intelligence_control.quota_periods WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c') THEN RAISE EXCEPTION 'ZERO_WORKER_START_BASELINE_REQUIRED'; END IF;
 FOREACH j IN ARRAY ARRAY[4,5,6]::bigint[] LOOP PERFORM cron.alter_job(j,active:=false); END LOOP;
END $start_exact_jobs$;
COMMIT;
SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'scopeAllowed',intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1'),
 'authority',(SELECT jsonb_build_object('runtimeId',runtime_id,'enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,'jobIds',job_ids) FROM intelligence_control.edge_authorities WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'ownJobs',(SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'active',active,'schedule',schedule,'command',command) ORDER BY jobid) FROM cron.job WHERE jobid IN (4,5,6)),
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN (4,5,6)),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c')
 ) AS snapshot;
