-- SOURCE-ONLY proposal. This exact read is used for renewal preflight and readback.
-- No Vault values, headers, bodies, keys or Auth credentials are selected.
SELECT jsonb_build_object(
 'observedAt',statement_timestamp(),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'apiFunctionCount',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api'),
 'authority',(SELECT jsonb_build_object('runtimeId',runtime_id,'enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,
  'jobIds',job_ids,'nonWindowHash',encode(extensions.digest((to_jsonb(a)-'expires_at')::text,'sha256'),'hex'))
  FROM intelligence_control.edge_authorities a WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'scopeCount',(SELECT count(*) FROM intelligence_control.runtime_worker_scopes WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'scope',(SELECT jsonb_build_object('tenantId',tenant_id,'legalEntityId',legal_entity_id,'branchId',branch_id,'enabled',enabled,
  'issuedAt',issued_at,'expiresAt',expires_at) FROM intelligence_control.runtime_worker_scopes
  WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7' AND tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c' AND legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd' AND branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'),
 'scopeNonWindowHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(s)-'expires_at' ORDER BY tenant_id,legal_entity_id,branch_id)::text,'[]'),'sha256'),'hex')
 FROM intelligence_control.runtime_worker_scopes s WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'scopeAllowed',intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1'),
 'guardFunctionBindings',(SELECT jsonb_agg(jsonb_build_object('identity',p.oid::regprocedure::text,'oid',p.oid::text,
 'bodySha256',encode(extensions.digest(p.prosrc,'sha256'),'hex'),
 'definitionSha256',encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'),
 'securityDefiner',p.prosecdef,'configuration',p.proconfig,'grants',p.proacl) ORDER BY p.oid::regprocedure::text)
 FROM pg_proc p WHERE p.oid=ANY(ARRAY['api.wave5_edge_control(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_delivery_worker(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_worker(uuid,text,jsonb)'::regprocedure,'intelligence_control.edge_schedule_tick(text)'::regprocedure,'intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)'::regprocedure,'intelligence_control.runtime_tenant_allowed(uuid,uuid)'::regprocedure,'intelligence_control.runtime_worker_required(uuid)'::regprocedure])),
 'containsUnexpected24HourFunctionCeiling',(SELECT coalesce(bool_or(p.prosrc ~* 'issued_at[[:space:]]*\+[[:space:]]*interval[[:space:]]+''24 hours'''),false)
  FROM pg_proc p WHERE p.oid=ANY(ARRAY['api.wave5_edge_control(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_delivery_worker(uuid,text,jsonb)'::regprocedure,'api.wave5_runtime_worker(uuid,text,jsonb)'::regprocedure,'intelligence_control.edge_schedule_tick(text)'::regprocedure,'intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)'::regprocedure,'intelligence_control.runtime_tenant_allowed(uuid,uuid)'::regprocedure,'intelligence_control.runtime_worker_required(uuid)'::regprocedure])),
 'ownJobs',(SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) ORDER BY jobid)
  FROM cron.job WHERE jobid IN(4,5,6)),
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN(4,5,6)),
 'keyReferences',(SELECT jsonb_agg(jsonb_build_object('ref',ref,'secretId',secret_id) ORDER BY ref) FROM intelligence_control.edge_key_refs WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),
 'modelInvocations',(SELECT count(*) FROM intelligence_control.model_invocations WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'recordedCronRuns',(SELECT count(*) FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>='2026-10-13T09:57:07.481942+00:00'::timestamptz),
 'tableContracts',(SELECT jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'rls',c.relrowsecurity,'forceRls',c.relforcerowsecurity,
  'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',a.atttypid::regtype::text,'required',a.attnotnull) ORDER BY a.attnum)
   FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
  'constraints',(SELECT jsonb_agg(pg_get_constraintdef(k.oid) ORDER BY k.conname) FROM pg_constraint k WHERE k.conrelid=c.oid),
  'userTriggers',(SELECT count(*) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)) ORDER BY c.oid::regclass::text)
  FROM pg_class c WHERE c.oid IN('intelligence_control.edge_authorities'::regclass,'intelligence_control.runtime_worker_scopes'::regclass))
) AS renewal_snapshot;
