SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'scopeAllowed',intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1'),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'apiFunctionCount',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api'),
 'guardFingerprints',(SELECT jsonb_agg(jsonb_build_object('signature',s,'md5',md5(pg_get_functiondef(s::regprocedure))) ORDER BY s) FROM unnest(ARRAY['intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)','intelligence_control.edge_schedule_tick(text)','api.wave5_runtime_worker(uuid,text,jsonb)','api.wave5_edge_control(uuid,text,jsonb)','intelligence_control.runtime_worker_required(uuid)','intelligence_control.worker_required()','api.wave5_health_collect(uuid,uuid)']) s),
 'serviceRoleRpcGrants',has_function_privilege('service_role','api.wave5_runtime_worker(uuid,text,jsonb)','EXECUTE') AND has_function_privilege('service_role','api.wave5_edge_control(uuid,text,jsonb)','EXECUTE'),
 'authority',(SELECT jsonb_build_object('runtimeId',runtime_id,'enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,'jobIds',job_ids) FROM intelligence_control.edge_authorities WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'ownJobs',(SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'active',active,'schedule',schedule,'command',command) ORDER BY jobid) FROM cron.job WHERE jobid IN(4,5,6)),
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN(4,5,6)),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'readinessTicks',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'state',t.state,
  'tickSha256',encode(extensions.digest(to_jsonb(t)::text,'sha256'),'hex'),
  'outcomeSha256',encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex'),'success',o.success,'summary',o.summary) ORDER BY t.id),'[]'::jsonb)
  FROM intelligence_control.edge_ticks t LEFT JOIN intelligence_control.edge_tick_outcomes o ON o.runtime_id=t.runtime_id AND o.id=t.id WHERE t.runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'tickOutcomes',(SELECT count(*) FROM intelligence_control.edge_tick_outcomes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'deliveryOutcomes',(SELECT count(*) FROM intelligence_control.delivery_outcomes WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'receiverReceipts',(SELECT count(*) FROM intelligence_control.edge_receiver_receipts WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'modelInvocations',(SELECT count(*) FROM intelligence_control.model_invocations WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'modelOutcomes',(SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'usageEvents',(SELECT count(*) FROM intelligence_control.usage_events WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'recordedCronRuns',(SELECT count(*) FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>='2026-10-13T09:57:07.481942Z'::timestamptz),
 'completedOriginalExports',(SELECT count(*) FROM core.export_jobs WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c' AND actor_id='8b740ab8-24f7-4455-a78b-aea0d99d20f6' AND status='completed'
 AND id IN ('5594aa22-a243-337d-e574-9095f97b46c2'::uuid,'7ea25345-a8c0-45b0-f22b-8d1d0fba5318'::uuid))=2
 AND (SELECT count(*) FROM core.command_receipts WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c' AND actor_id='8b740ab8-24f7-4455-a78b-aea0d99d20f6' AND command_name='finance.report.export' AND aggregate_type='report_export'
 AND ((command_id='d4a0ad64-f138-b857-30d6-6fe0afe64e4f' AND aggregate_id='5594aa22-a243-337d-e574-9095f97b46c2') OR (command_id='217bcee3-d103-9513-a3e7-cc56d26e45be' AND aggregate_id='7ea25345-a8c0-45b0-f22b-8d1d0fba5318')))=2
 ) AS snapshot;