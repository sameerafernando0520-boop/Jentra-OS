// Source-only successor. Import/construction performs no file, environment or network I/O.
import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual as equal} from 'node:util';

export const PROJECT='xpdoufauvrbdmxgngetv',BUNDLE='db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
export const RUNTIME='778237e3-3d4e-4871-8cc9-e08b07b989c7',TENANT='babe6c86-a764-4d3a-80a3-952a7c096c2c';
export const ISSUED='2026-10-13T09:57:07.481942Z',EXPIRES='2026-10-14T09:57:07.481942Z';
export const SOURCE='tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs';
export const REVIEW='docs/verification/wave5/task3-schedule-resume-20261014/final-operation-review.json';
export const PROVIDER_REVIEW='docs/verification/wave5/task3-schedule-resume-20261014/actual-provider-authority-review.json';
export const ONCE='docs/verification/wave5/task3-schedule-resume-20261014/resume-once.json';
const root=fileURLToPath(new URL('../../',import.meta.url));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
export const JOBS=Object.freeze(['delivery','subscription','health'].map((kind,i)=>Object.freeze({jobId:4+i,
 name:'jentra-w5-20261009-'+kind,schedule:'* * * * *',command:`select intelligence_control.edge_schedule_tick('${kind}');`})));
export const GUARDS=Object.freeze(['intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)',
 'intelligence_control.edge_schedule_tick(text)','api.wave5_runtime_worker(uuid,text,jsonb)','api.wave5_edge_control(uuid,text,jsonb)',
 'intelligence_control.runtime_worker_required(uuid)','intelligence_control.worker_required()','api.wave5_health_collect(uuid,uuid)']);
export const EXPORT_COMMANDS=Object.freeze([
 Object.freeze({name:'record_report_export',commandId:'d4a0ad64-f138-b857-30d6-6fe0afe64e4f',exportId:'5594aa22-a243-337d-e574-9095f97b46c2',actorId:'8b740ab8-24f7-4455-a78b-aea0d99d20f6'}),
 Object.freeze({name:'record_report_export',commandId:'217bcee3-d103-9513-a3e7-cc56d26e45be',exportId:'7ea25345-a8c0-45b0-f22b-8d1d0fba5318',actorId:'8b740ab8-24f7-4455-a78b-aea0d99d20f6'}),
]);
export const PRESERVED=Object.freeze([
 ['tools/wave5/start_scheduled_delivery_20261013_r5_a4.mjs','930e6c3ca3bc26c0a91448df834746c234e6e211280d900747f2f4ddf17ff096'],
 ['docs/verification/wave5/scheduled-delivery-start-20261013-r5.sql','94019d7ea0386ed21e04602f8678aed75ddcaaf1dfec8ae4810c714431641322'],
 ['docs/verification/wave5/scheduled-delivery-start-read-20261013-r5-a2.sql','0555cc9a7719d5d3c9ac381357f4a8147c5febecd83aaaeccfaf48deef24a371'],
 ['docs/verification/wave5/scheduled-delivery-start-intent-20261013-r5.json','f885fcf190bd017889915e9805d01194779f18b2d13662d4e15e4c1cb6ec8296'],
 ['docs/verification/wave5/scheduled-delivery-start-once-20261013-r5-a4.json','f0bf227cddae5132fc4a95f05715489fdb866107b0e0d2fdbad1424e8b7b504d'],
 ['docs/verification/wave5/runtime-global-readonly-snapshot-20261013-r5-a4.json','4b798483071ff24515534786bbf10805aff0933074e59cf7ea392a54afb6faca'],
 ['docs/verification/wave5/worker-v7-provider-owner-decision-20261014-r5.json','0f513290971c544eaabd15a56aca78ff5a6a5ddc09e2a8dcca52f87178ef0066'],
 ['docs/verification/wave5/task3-completion-20261013/worker-v7-independent-actual-probe-result-20261014.json','25297e420e7ac1fa62b2fef2e6b4e678a3ff13d7dd8fd59b6fadab2d46f8e236'],
 ['docs/verification/wave5/task3-completion-20261013/worker-v7-independent-deployment-and-probe-review-20261014.json','d15f3a3941175dcd258b252069c881badb0f8670d1f3b07b3669d3257bc0220f'],
 ['tools/wave5/private_runtime_seal.mjs','1395a91ee666d40c5504c8977b5d4f64aa4d54b383dfe147fe78eb07a5d7a206'],
 ['tools/wave5/runtime_contract.mjs','7bc04153aa169c2f85f4371c74319c2eded1f6666a97609ba29f5a2ad94d1da2'],
 ['tools/wave5/approved_management_installer.mjs','f6266b37e9c5eb254a794aedd512984d35865e2ff4ddfd19f6a67cf5f9750bd5'],
 ['docs/verification/wave5/runtime-owner-decision-20261012-r5.json','90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab'],
 ['docs/verification/wave5/complete-app-runtime-review-20261010-r5.json','b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3'],
].map(([path,sha256])=>Object.freeze({path,sha256})));
const outside='4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945';
const scope=`intelligence_control.runtime_scope_allowed('${RUNTIME}','${TENANT}','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1')`;
const fingerprints=`(SELECT jsonb_agg(jsonb_build_object('signature',s,'md5',md5(pg_get_functiondef(s::regprocedure))) ORDER BY s) FROM unnest(ARRAY[${GUARDS.map(s=>"'"+s+"'").join(',')}]) s)`;
const exportCheck=`(SELECT count(*) FROM core.export_jobs WHERE tenant_id='${TENANT}' AND actor_id='${EXPORT_COMMANDS[0].actorId}' AND status='completed'
 AND id IN ('${EXPORT_COMMANDS[0].exportId}'::uuid,'${EXPORT_COMMANDS[1].exportId}'::uuid))=2
 AND (SELECT count(*) FROM core.command_receipts WHERE tenant_id='${TENANT}' AND actor_id='${EXPORT_COMMANDS[0].actorId}' AND command_name='finance.report.export' AND aggregate_type='report_export'
 AND ((command_id='${EXPORT_COMMANDS[0].commandId}' AND aggregate_id='${EXPORT_COMMANDS[0].exportId}') OR (command_id='${EXPORT_COMMANDS[1].commandId}' AND aggregate_id='${EXPORT_COMMANDS[1].exportId}')))=2`;
export const READ_SQL=`SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'scopeAllowed',${scope},
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'apiFunctionCount',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api'),
 'guardFingerprints',${fingerprints},
 'serviceRoleRpcGrants',has_function_privilege('service_role','api.wave5_runtime_worker(uuid,text,jsonb)','EXECUTE') AND has_function_privilege('service_role','api.wave5_edge_control(uuid,text,jsonb)','EXECUTE'),
 'authority',(SELECT jsonb_build_object('runtimeId',runtime_id,'enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,'jobIds',job_ids) FROM intelligence_control.edge_authorities WHERE runtime_id='${RUNTIME}'),
 'ownJobs',(SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'active',active,'schedule',schedule,'command',command) ORDER BY jobid) FROM cron.job WHERE jobid IN(4,5,6)),
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN(4,5,6)),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='${RUNTIME}'),
 'readinessTicks',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'state',t.state,
  'tickSha256',encode(extensions.digest(to_jsonb(t)::text,'sha256'),'hex'),
  'outcomeSha256',encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex'),'success',o.success,'summary',o.summary) ORDER BY t.id),'[]'::jsonb)
  FROM intelligence_control.edge_ticks t LEFT JOIN intelligence_control.edge_tick_outcomes o ON o.runtime_id=t.runtime_id AND o.id=t.id WHERE t.runtime_id='${RUNTIME}'),
 'tickOutcomes',(SELECT count(*) FROM intelligence_control.edge_tick_outcomes WHERE runtime_id='${RUNTIME}'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='${TENANT}'),
 'deliveryOutcomes',(SELECT count(*) FROM intelligence_control.delivery_outcomes WHERE tenant_id='${TENANT}'),
 'receiverReceipts',(SELECT count(*) FROM intelligence_control.edge_receiver_receipts WHERE runtime_id='${RUNTIME}'),
 'modelInvocations',(SELECT count(*) FROM intelligence_control.model_invocations WHERE tenant_id='${TENANT}'),
 'modelOutcomes',(SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id='${TENANT}'),
 'usageEvents',(SELECT count(*) FROM intelligence_control.usage_events WHERE tenant_id='${TENANT}'),
 'recordedCronRuns',(SELECT count(*) FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>='${ISSUED}'::timestamptz),
 'completedOriginalExports',${exportCheck}
 ) AS snapshot;`;

export function validateFingerprints(value){
 must(Array.isArray(value)&&value.length===7&&value.every((row,i)=>row.signature===[...GUARDS].sort()[i]
  &&typeof row.md5==='string'&&/^[a-f0-9]{32}$/.test(row.md5)&&Object.keys(row).length===2),'EXACT_SEVEN_GUARD_FINGERPRINTS_REQUIRED');return value;
}
export function validateReadinessTick(tick){
 must(tick&&Object.keys(tick).length===5&&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(tick.id??'')
  &&tick.kind==='health'&&tick.state==='completed'&&digest(tick.tickSha256)&&digest(tick.outcomeSha256),
  'EXACT_ONE_COMPLETED_HEALTH_READINESS_TICK_REQUIRED');return tick;
}
export function buildResumeSql(guardFingerprints,readinessTick){
 validateFingerprints(guardFingerprints);
 validateReadinessTick(readinessTick);
 const guardJson=JSON.stringify(guardFingerprints); // validated fixed signatures and hexadecimal values only
 return `BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $resume_exact_jobs$
DECLARE a intelligence_control.edge_authorities%rowtype; j bigint; recorded bigint;
BEGIN
 SELECT * INTO a FROM intelligence_control.edge_authorities WHERE runtime_id='${RUNTIME}' FOR UPDATE;
 IF NOT FOUND OR NOT a.enabled OR a.issued_at<>'${ISSUED}'::timestamptz OR a.expires_at<>'${EXPIRES}'::timestamptz
  OR a.expires_at<=statement_timestamp() OR a.expires_at>a.issued_at+interval '24 hours'
  OR cardinality(a.job_ids)<>3 OR NOT a.job_ids @> ARRAY[4,5,6]::bigint[] THEN RAISE EXCEPTION 'EXACT_UNEXPIRED_AUTHORITY_REQUIRED'; END IF;
 IF NOT ${scope} THEN RAISE EXCEPTION 'EXACT_APPROVED_SCOPE_REQUIRED'; END IF;
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>115 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api')<>363
  THEN RAISE EXCEPTION 'EXACT_115_363_BASELINE_REQUIRED'; END IF;
 IF ${fingerprints} IS DISTINCT FROM '${guardJson}'::jsonb OR NOT has_function_privilege('service_role','api.wave5_runtime_worker(uuid,text,jsonb)','EXECUTE')
  OR NOT has_function_privilege('service_role','api.wave5_edge_control(uuid,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'UNCHANGED_SERVER_AUTHORITY_GUARDS_REQUIRED'; END IF;
 IF NOT (${exportCheck}) THEN RAISE EXCEPTION 'EXACT_TWO_COMPLETED_EXPORTS_FIRST_REQUIRED'; END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobid IN (4,5,6) AND NOT active AND schedule='* * * * *'
  AND ((jobid=4 AND jobname='jentra-w5-20261009-delivery' AND command='select intelligence_control.edge_schedule_tick(''delivery'');')
   OR (jobid=5 AND jobname='jentra-w5-20261009-subscription' AND command='select intelligence_control.edge_schedule_tick(''subscription'');')
   OR (jobid=6 AND jobname='jentra-w5-20261009-health' AND command='select intelligence_control.edge_schedule_tick(''health'');')))<>3
  OR (SELECT count(*) FROM cron.job WHERE jobname IN ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'))<>3 THEN RAISE EXCEPTION 'EXACT_THREE_PAUSED_OWN_JOBS_REQUIRED'; END IF;
 IF (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(c) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job c WHERE jobid NOT IN (4,5,6))<>'${outside}' THEN RAISE EXCEPTION 'OUTSIDE_JOB_PRESERVATION_REQUIRED'; END IF;
 IF (SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='${RUNTIME}')<>1
  OR (SELECT count(*) FROM intelligence_control.edge_tick_outcomes WHERE runtime_id='${RUNTIME}')<>1
  OR NOT EXISTS(SELECT 1 FROM intelligence_control.edge_ticks t JOIN intelligence_control.edge_tick_outcomes o ON o.runtime_id=t.runtime_id AND o.id=t.id
   WHERE t.runtime_id='${RUNTIME}' AND t.id='${readinessTick.id}' AND t.kind='health' AND t.state='completed' AND o.success
   AND o.summary='{"count":1,"states":["collected"]}'::jsonb
   AND encode(extensions.digest(to_jsonb(t)::text,'sha256'),'hex')='${readinessTick.tickSha256}'
   AND encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex')='${readinessTick.outcomeSha256}')
  THEN RAISE EXCEPTION 'EXACT_ONE_BOUND_HEALTH_READINESS_TICK_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM intelligence_control.quota_periods WHERE tenant_id='${TENANT}')
  OR EXISTS(SELECT 1 FROM intelligence_control.delivery_outcomes WHERE tenant_id='${TENANT}')
  OR EXISTS(SELECT 1 FROM intelligence_control.edge_receiver_receipts WHERE runtime_id='${RUNTIME}')
  OR EXISTS(SELECT 1 FROM intelligence_control.model_invocations WHERE tenant_id='${TENANT}')
  OR EXISTS(SELECT 1 FROM intelligence_control.usage_events WHERE tenant_id='${TENANT}') THEN RAISE EXCEPTION 'NO_UNREVIEWED_QUOTA_DELIVERY_MODEL_EFFECTS_REQUIRED'; END IF;
 SELECT count(*) INTO recorded FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>=a.issued_at;
 IF recorded<24 OR recorded+1+3*ceil(extract(epoch FROM(a.expires_at-statement_timestamp()))/60)>4320
  THEN RAISE EXCEPTION 'PRESERVED_REQUEST_BUDGET_REQUIRED'; END IF;
 FOREACH j IN ARRAY ARRAY[4,5,6]::bigint[] LOOP PERFORM cron.alter_job(j,active:=true); END LOOP;
END $resume_exact_jobs$;
COMMIT;`;
}
export function validateTime(now,{expiresAt=EXPIRES}={}){
 must(Number.isFinite(now)&&Number.isFinite(Date.parse(expiresAt))&&Date.parse(expiresAt)<=Date.parse(EXPIRES)
  &&now>=Date.parse(ISSUED)&&now<Date.parse(expiresAt),'ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED');return Date.parse(expiresAt);
}
export function validateExportsProof(value){
 must(value?.kind==='genuine-export-only-successor-result'&&value.passed===true&&value.projectId===PROJECT&&value.runtimeBundleSha256===BUNDLE
  &&equal(value.completed,EXPORT_COMMANDS)&&value.actualOrdinaryAttempts===24&&value.actualReadOnlyResolutionAttempts===0
  &&Array.isArray(value.artifacts)&&value.artifacts.length===2&&value.rawWholeHashChanged===true
  &&value.successfulDateCommandsReexecuted===false&&value.oldUncertainCommandReplayed===false,'ACTUAL_EXPORTS_FIRST_PROOF_REQUIRED');
 for(const [i,artifact] of value.artifacts.entries())must(artifact.exportId===EXPORT_COMMANDS[i].exportId&&digest(artifact.sourceHash)&&digest(artifact.fileSha256)
  &&typeof artifact.independentSessionId==='string'&&/^[a-f0-9-]{36}$/.test(artifact.independentSessionId)
  &&artifact.registeredPipelineReopen===(i===0)&&artifact.statementFreshSourceReproduction===(i===1)
  &&artifact.registeredStatementReopen===false,'ACTUAL_EXPORT_REPRODUCTION_PROOF_REQUIRED');
 return value;
}
export function validateHealthReadinessResult(result,{readinessTick,guardFingerprints,now=Date.now()}={}){
 validateReadinessTick(readinessTick);
 const observed=Date.parse(result?.observedAt);
 const zero={quotaPeriods:0,deliveryOutcomes:0,receiverReceipts:0,modelInvocations:0,modelOutcomes:0,usageEvents:0};
 must(result?.kind==='actual-v7-deployed-health-readiness-result'&&result.passed===true&&result.controlledFixture===false
  &&result.projectId===PROJECT&&result.runtimeBundleSha256===BUNDLE&&result.runtimeId===RUNTIME&&result.deployedVersion===7
  &&result.candidateBundleSha256==='2a540cabaf0b8ac10f1a553e07b5cea0e886cb9ec380ff8560f500eba4b1f35c'
  &&result.authenticatedDatabaseOwnedInvocation===true&&result.clientScheduleSecretRetrieved===false&&result.hmacSignatureClaimed===false
  &&result.requestCount===1&&result.automaticRetries===0&&Number.isSafeInteger(result.managementAttempts)&&result.managementAttempts>=3&&result.managementAttempts<=5
  &&Number.isSafeInteger(result.netRequestId)&&result.netRequestId>0&&result.status===200
  &&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(result.serverRequestId??'')
  &&equal(result.response,{state:'completed',count:1,states:['collected']})&&digest(result.responseSha256)
  &&equal(result.readinessTick,readinessTick)&&equal(result.healthOutcome,{success:true,summary:{count:1,states:['collected']}})
  &&equal(result.effectsBefore,{ticks:0,outcomes:0,...zero})&&equal(result.effectsAfter,{ticks:1,outcomes:1,...zero})
  &&equal(result.guardFingerprints,guardFingerprints)&&result.historicalScheduleRequests===24
  &&result.readinessInvocations===1&&result.cumulativeScheduleRequests===25&&result.maximumScheduleRequests===4320
  &&result.jobsRemainPaused===true&&result.actualDelivery===false&&result.actualModelUsage===false
  &&Number.isFinite(observed)&&observed<=now&&now-observed<300000&&observed<Date.parse(EXPIRES),
  'ACTUAL_DEPLOYED_AUTHENTICATED_HEALTH_RESULT_REQUIRED');
 return result;
}
export function validateHealthEvidence(result,{before,dispatch,after}={}){
 must(before&&dispatch&&after&&equal(before.effects,result.effectsBefore)&&equal(after.effects,result.effectsAfter)
  &&equal(before.guardFingerprints,result.guardFingerprints)&&equal(after.guardFingerprints,result.guardFingerprints)
  &&before.scopeAllowed===true&&after.scopeAllowed===true&&before.completedExports===true&&after.completedExports===true
  &&before.migrationCount===115&&after.migrationCount===115&&before.apiFunctionCount===363&&after.apiFunctionCount===363
  &&equal(before.ownJobs,JOBS.map(job=>({...job,active:false})))&&equal(after.ownJobs,before.ownJobs)
  &&before.outsideJobHash===outside&&after.outsideJobHash===outside
  &&dispatch.requestId===result.netRequestId&&dispatch.dispatchedAt===result.dispatchedAt&&after.observedAt===result.observedAt
  &&Array.isArray(after.ticks)&&after.ticks.length===1,'ACTUAL_HEALTH_STATE_DISPATCH_LINEAGE_REQUIRED');
 const h=after.http,t=after.ticks[0],start=Date.parse(t?.startedAt),end=Date.parse(t?.recordedAt),sent=Date.parse(dispatch.dispatchedAt);
 const {startedAt,recordedAt,tickRow,outcomeRow,...tick}=t;
 must(equal(tick,{...result.readinessTick,success:true,summary:{count:1,states:['collected']}})
  &&h?.id===result.netRequestId&&h.status===200&&h.timedOut===false&&typeof h.content==='string'
  &&h.responseBytes===Buffer.byteLength(h.content)&&h.responseBytes<=1024&&sha(h.content)===h.responseSha256
  &&h.responseSha256===result.responseSha256&&h.serverRequestId===result.serverRequestId
  &&Number.isFinite(sent)&&Number.isFinite(start)&&Number.isFinite(end)&&Date.parse(before.observedAt)<=sent
  &&sent<=start&&start<=end&&end<=Date.parse(after.observedAt)&&end<Date.parse(EXPIRES),
  'ACTUAL_HEALTH_HTTP_AND_TICK_LINEAGE_REQUIRED');
 must(tickRow?.runtime_id===RUNTIME&&tickRow.id===t.id&&tickRow.kind==='health'&&tickRow.state==='completed'
  &&Date.parse(tickRow.started_at)===start&&Date.parse(tickRow.lease_until)>end
  &&outcomeRow?.runtime_id===RUNTIME&&outcomeRow.id===t.id&&outcomeRow.success===true
  &&equal(outcomeRow.summary,t.summary)&&Date.parse(outcomeRow.recorded_at)===end,
  'ACTUAL_HEALTH_RAW_TICK_AND_OUTCOME_REQUIRED');
 let body;try{body=JSON.parse(h.content);}catch{throw Error('ACTUAL_HEALTH_HTTP_JSON_REQUIRED');}
 must(equal(body,result.response),'ACTUAL_HEALTH_HTTP_BODY_REQUIRED');return true;
}
export function validateProviderAuthority(proof,{binding,guardFingerprints,healthResult,healthEvidence,now=Date.now()}={}){
 validateTime(now);
 const observed=Date.parse(proof?.observedAt);
 must(binding?.path===PROVIDER_REVIEW&&digest(binding.sha256)
  &&proof?.kind==='independent-actual-v7-deployed-health-readiness-review'&&proof.technicalDecision==='approve'&&proof.passed===true
  &&proof.independentlyReviewed===true&&proof.projectId===PROJECT&&proof.runtimeBundleSha256===BUNDLE&&proof.runtimeId===RUNTIME
  &&proof.deployedVersion===7&&proof.candidateBundleSha256==='2a540cabaf0b8ac10f1a553e07b5cea0e886cb9ec380ff8560f500eba4b1f35c'
  &&proof.credentialSource==='existing-injected-worker-service-key'&&proof.backendRole==='service_role'
  &&proof.actualDeployedWorkerBackendAuthorizationVerified===true&&proof.actualServiceKeyRoleAndValidityVerified===true
  &&proof.unsignedProbeUsedAsRoleProof===false&&proof.keyFormatUsedAsRoleProof===false&&proof.secretsPublished===false
  &&Number.isFinite(observed)&&observed<=now&&now-observed<300000&&observed<Date.parse(EXPIRES)
  &&equal(proof.guardFingerprints,guardFingerprints)&&proof.priorScheduledRequestsObserved===24
  &&proof.readinessRequestsCharged===1&&proof.cumulativeReviewedWorkerRequests===25,
  'ACTUAL_BACKEND_PROVIDER_AUTHORITY_PROOF_REQUIRED');
 validateFingerprints(proof.guardFingerprints);
 must(Array.isArray(proof.evidenceBindings)&&proof.evidenceBindings.length>0
  &&proof.evidenceBindings.every(row=>typeof row.path==='string'&&(row.path.startsWith('docs/verification/wave5/')
   ||row.path==='tools/wave5/probe_worker_v7_health_20261014_r5.mjs')
   &&/^[A-Za-z0-9_./-]+$/.test(row.path)&&!row.path.includes('..')&&digest(row.sha256))
  &&new Set(proof.evidenceBindings.map(row=>row.path)).size===proof.evidenceBindings.length
  &&['actualHealthResultBinding','actualBeforeStateBinding','actualDispatchBinding','actualAfterStateBinding','healthControllerSourceBinding'].every(key=>
   proof.evidenceBindings.some(row=>equal(row,proof[key])))
  &&proof.healthControllerSourceBinding.path==='tools/wave5/probe_worker_v7_health_20261014_r5.mjs',
  'ACTUAL_HASH_BOUND_HEALTH_RESULT_REQUIRED');
 validateHealthReadinessResult(healthResult,{readinessTick:proof.readinessTick,guardFingerprints,now});
 must(equal(healthResult.actualReadbackBinding,proof.actualAfterStateBinding)&&Array.isArray(healthResult.evidenceBindings)
  &&['actualBeforeStateBinding','actualDispatchBinding','actualAfterStateBinding'].every(key=>
   healthResult.evidenceBindings.some(row=>equal(row,proof[key]))),
  'ACTUAL_HEALTH_RESULT_EVIDENCE_LINEAGE_REQUIRED');
 validateHealthEvidence(healthResult,healthEvidence);
 must(Date.parse(healthResult.observedAt)<=observed,'ACTUAL_HEALTH_OBSERVATION_LINEAGE_REQUIRED');
 return proof;
}
export function validateFinalReview(review,{sourceSha256,metadata,exportsProof,providerAuthority,healthResult,healthEvidence,now=Date.now()}={}){
 validateTime(now,{expiresAt:review?.authorizationExpiresAt});
 must(review?.kind==='independent-exact-three-job-schedule-resume-operation-review'&&review.technicalDecision==='approve'&&review.executionPermitted===true
  &&review.projectId===PROJECT&&review.runtimeBundleSha256===BUNDLE&&review.sourceBinding?.path===SOURCE&&review.sourceBinding.sha256===sourceSha256
  &&equal(review.jobIds,[4,5,6])&&review.originalAuthorityExpiresAt===EXPIRES&&review.originalAuthorityIssuedAt===ISSUED
  &&review.maximumScheduleRequestsOriginal===4320&&review.scheduledRequestsAlreadyObserved===24&&review.maximumManagementAttempts===3
  &&review.readinessRequestsCharged===1&&review.cumulativeReviewedWorkerRequests===25
  &&review.automaticRetries===0&&review.newUsers===0&&review.newPermissions===0&&review.newSecrets===0&&review.newDestinations===0
  &&review.extendedExpiry===false&&review.personalHumanExactSourceSignatureClaimed===false
  &&review.v7ProbeProof?.sha256===PRESERVED[7].sha256&&review.v7OwnerDecision?.sha256===PRESERVED[6].sha256
  &&review.v7ProbeProof.path===PRESERVED[7].path&&review.v7OwnerDecision.path===PRESERVED[6].path
  &&review.separateScheduleResumeDecision===true&&review.currentOwnerSidVerifiedByPrivateAdapter===true
  &&review.exportsMustCompleteFirst===true&&review.oldA4IntentReused===false&&review.countersReset===false,'EXACT_SCHEDULE_OPERATION_REVIEW_REQUIRED');
 validateFingerprints(review.guardFingerprints);
 validateProviderAuthority(providerAuthority,{binding:review.providerAuthorityBinding,guardFingerprints:review.guardFingerprints,healthResult,healthEvidence,now});
 must(equal(review.readinessTick,providerAuthority.readinessTick)&&equal(review.actualHealthResultBinding,providerAuthority.actualHealthResultBinding)
  &&review.readSqlSha256===sha(READ_SQL)&&review.writeSqlSha256===sha(buildResumeSql(review.guardFingerprints,review.readinessTick)),
  'EXACT_SCHEDULE_SQL_INVENTORY_REQUIRED');
 must(metadata?.kind==='wave5-private-owner-input-metadata'&&metadata.projectId===PROJECT&&metadata.runtimeBundleSha256===BUNDLE
  &&metadata.containsPlaintextCredential===false&&metadata.ownerSid===review.ownerSid&&typeof metadata.privateFolder==='string'
  &&review.authorizationExpiresAt===new Date(Math.min(Date.parse(metadata.expiresAt),Date.parse(EXPIRES))).toISOString()
  &&Number.isFinite(Date.parse(metadata.createdAt))&&now>=Date.parse(metadata.createdAt),'FRESH_SCHEDULE_OWNER_METADATA_REQUIRED');
 validateTime(now,{expiresAt:review.authorizationExpiresAt});
 validateExportsProof(exportsProof);return review;
}
export function validateSnapshot(snapshot,{active=false,guardFingerprints,readinessTick,now=Date.now(),before}={}){
 const observed=Date.parse(snapshot?.observedAt);validateTime(now);
 must(Number.isFinite(observed)&&Math.abs(now-observed)<60000&&observed<Date.parse(EXPIRES)&&snapshot.scopeAllowed===true
  &&snapshot.migrationCount===115&&snapshot.apiFunctionCount===363&&snapshot.serviceRoleRpcGrants===true&&snapshot.completedOriginalExports===true
  &&snapshot.authority?.runtimeId===RUNTIME&&snapshot.authority.enabled===true&&Date.parse(snapshot.authority.issuedAt)===Date.parse(ISSUED)
  &&Date.parse(snapshot.authority.expiresAt)===Date.parse(EXPIRES)&&equal(snapshot.authority.jobIds,[4,5,6])
  &&snapshot.outsideJobHash===outside&&equal(snapshot.guardFingerprints,guardFingerprints)
  &&snapshot.ownJobs?.length===3&&snapshot.ownJobs.every((job,i)=>equal(job,{...JOBS[i],active})),
  'EXACT_FRESH_SCHEDULE_STATE_REQUIRED');
 must(Number.isSafeInteger(snapshot.recordedCronRuns)&&snapshot.recordedCronRuns>=24
  &&snapshot.recordedCronRuns+1+3*Math.ceil((Date.parse(EXPIRES)-observed)/60000)<=4320,'PRESERVED_SCHEDULE_REQUEST_BUDGET_REQUIRED');
 validateReadinessTick(readinessTick);
 must(snapshot.ticks===1&&snapshot.tickOutcomes===1&&equal(snapshot.readinessTicks,[{...readinessTick,success:true,summary:{count:1,states:['collected']}}]),
  'EXACT_ONE_BOUND_HEALTH_READINESS_TICK_REQUIRED');
 must(['quotaPeriods','deliveryOutcomes','receiverReceipts','modelInvocations','modelOutcomes','usageEvents'].every(name=>snapshot[name]===0),
  'NO_UNREVIEWED_QUOTA_DELIVERY_MODEL_EFFECTS_REQUIRED');
 if(before)must(equal(before.authority,snapshot.authority)&&equal(before.guardFingerprints,snapshot.guardFingerprints)
  &&before.outsideJobHash===snapshot.outsideJobHash&&snapshot.recordedCronRuns>=before.recordedCronRuns,'PRESERVED_SCHEDULE_AUTHORITY_REQUIRED');
 return snapshot;
}

export function createScheduleTransport(token,{writeSql,requestFactory=https.request,now=Date.now,expiresAt=EXPIRES}={}){
 must(typeof token==='string'&&token.length>=9&&token.length<=2048&&!/\s/.test(token),'PRIVATE_OWNER_INPUT_REQUIRED');
 must(typeof writeSql==='string'&&writeSql.startsWith('BEGIN;\nSET LOCAL lock_timeout='),'EXACT_RESUME_WRITE_REQUIRED');
 let attempts=0;
 return async(sql,readOnly)=>{
  validateTime(now(),{expiresAt});must(attempts<3,'THREE_SCHEDULE_MANAGEMENT_ATTEMPTS_ONLY');
  must((readOnly===true&&sql===READ_SQL)||(readOnly===false&&sql===writeSql),'FIXED_SCHEDULE_QUERY_ONLY');attempts++;
  const body=JSON.stringify({query:sql,read_only:readOnly});
  return new Promise((resolve,reject)=>{let req,timer,settled=false,sent=false,size=0;const chunks=[];
   const fail=code=>{if(settled)return;settled=true;clearTimeout(timer);req?.destroy();const error=Error(code);error.publicCode=code;error.sent=sent;reject(error);};
   try{req=requestFactory(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,{method:'POST',rejectUnauthorized:true,
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}},res=>{
     res.on('error',()=>fail('SCHEDULE_RESPONSE_UNCERTAIN'));res.on('data',chunk=>{if(settled)return;size+=chunk.length;
      if(size>1048576)fail('SCHEDULE_RESPONSE_LIMIT');else chunks.push(chunk);});
     res.on('end',()=>{if(settled)return;settled=true;clearTimeout(timer);resolve({status:res.statusCode,raw:Buffer.concat(chunks)});});});
    req.on('error',()=>fail('SCHEDULE_TRANSPORT_UNCERTAIN'));
    timer=setTimeout(()=>fail('SCHEDULE_TIMEOUT_UNCERTAIN'),Math.min(45000,Date.parse(expiresAt)-now()));
    req.once('socket',socket=>{const send=()=>{if(settled)return;try{validateTime(now(),{expiresAt});}catch{return fail('ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED');}
     if(socket.encrypted!==true||socket.authorized!==true)return fail('VERIFIED_SCHEDULE_TLS_REQUIRED');sent=true;req.end(body);};
     if(socket.authorized===true)send();else socket.once('secureConnect',send);});
   }catch{fail('SCHEDULE_REQUEST_FAILED');}
  });
 };
}
const receiptOk=receipt=>receipt&&digest(receipt.sha256)&&typeof receipt.path==='string';
export async function runScheduleResume({transport,persist,appendPrivate,once,guardFingerprints,readinessTick,now=Date.now,expiresAt=EXPIRES}={}){
 const writeSql=buildResumeSql(guardFingerprints,readinessTick);let phase='once-intent',mutationAttempted=false,attempts=0,before;
 validateTime(now(),{expiresAt});must(receiptOk(await once({kind:'exclusive-v7-three-job-resume-once',projectId:PROJECT,runtimeBundleSha256:BUNDLE,
  actualStartedAt:new Date(now()).toISOString(),jobIds:[4,5,6],readSqlSha256:sha(READ_SQL),writeSqlSha256:sha(writeSql),
  maximumManagementAttempts:3,scheduledRequestsAlreadyObserved:24,maximumScheduleRequestsOriginal:4320,originalExpiry:EXPIRES,
  readinessRequestsCharged:1,cumulativeReviewedWorkerRequests:25,readinessTick,
  oldA4IntentReused:false,countersReset:false,automaticRetry:false})),'DURABLE_EXCLUSIVE_RESUME_INTENT_REQUIRED');
 async function capture(file,sql,readOnly){
  validateTime(now(),{expiresAt});must(attempts<3,'THREE_SCHEDULE_MANAGEMENT_ATTEMPTS_ONLY');
  must(receiptOk(await persist(file+'-attempt.json',{attempt:attempts+1,readOnly,sqlSha256:sha(sql),actualAttemptAt:new Date(now()).toISOString()})),
   'DURABLE_SCHEDULE_ATTEMPT_REQUIRED');attempts++;
  if(!readOnly)mutationAttempted=true;
  const response=await transport(sql,readOnly);
  let privateErrorRecord=null;if(![200,201].includes(response.status))privateErrorRecord=await appendPrivate('schedule-resume-error',{
   httpStatus:response.status,responseBase64:response.raw.toString('base64'),actualCapturedAt:new Date(now()).toISOString()});
  must(receiptOk(await persist(file+'-response.json',{httpStatus:response.status,responseSha256:sha(response.raw),privateErrorRecord,rawErrorPrinted:false})),
   'DURABLE_SCHEDULE_RESPONSE_REQUIRED');
  must([200,201].includes(response.status),'SCHEDULE_HTTP_FAILURE');return response;
 }
 async function read(file){const response=await capture(file,READ_SQL,true);let value;try{value=JSON.parse(response.raw);}catch{throw Error('SCHEDULE_READ_INVALID');}
  must(Array.isArray(value)&&value.length===1&&value[0].snapshot,'ONE_SCHEDULE_STATE_ROW_REQUIRED');
  must(receiptOk(await persist(file+'-state.json',value[0].snapshot)),'DURABLE_SCHEDULE_STATE_REQUIRED');return value[0].snapshot;}
 try{
  phase='fresh-preflight';before=validateSnapshot(await read('00-before'),{guardFingerprints,readinessTick,now:now()});
  phase='write-intent';must(receiptOk(await persist('01-write-intent.json',{writeSqlSha256:sha(writeSql),jobIds:[4,5,6],
   changesOnlyThreeReviewedJobs:true,originalExpiry:EXPIRES,actualIntentAt:new Date(now()).toISOString()})),'DURABLE_WRITE_INTENT_REQUIRED');
  phase='exact-resume';let uncertain=null;
  try{await capture('02-write',writeSql,false);}catch(error){
   if(!mutationAttempted)throw error;
   uncertain=error.publicCode??'SCHEDULE_WRITE_OUTCOME_UNCERTAIN';
  }
  phase='actual-readback';const after=validateSnapshot(await read('03-after'),{active:true,guardFingerprints,readinessTick,now:now(),before});
  const result={kind:'actual-exact-v7-three-job-schedule-resume-result',passed:true,projectId:PROJECT,runtimeBundleSha256:BUNDLE,
   jobIds:[4,5,6],ownJobs:after.ownJobs,authority:after.authority,managementAttempts:attempts,writeResponseUncertain:uncertain,
   enabledStateConfirmedByReadback:true,originalExpiry:EXPIRES,existingJobsAndAuthorityPreserved:true,countersReset:false,
   automaticRetry:false,scheduledRequestsAlreadyObserved:24,maximumScheduleRequestsOriginal:4320,
   readinessRequestsCharged:1,cumulativeReviewedWorkerRequests:25,readinessTick,
   actualDelivery:false,actualTrustedModelUsage:false,nativeAccepted:false,targetScaleLoad:false,productionReleaseReady:false};
  must(receiptOk(await persist('99-result.json',result)),'DURABLE_RESUME_RESULT_REQUIRED');return result;
 }catch(error){await persist('99-stop.json',{passed:false,phase,failureCode:error.publicCode??'SCHEDULE_RESUME_STOP',actualStoppedAt:new Date(now()).toISOString(),
  mutationMayBeCommitted:mutationAttempted,managementAttempts:attempts,automaticRetry:false,secretPrinted:false});throw error;}
}

async function exactFile(relative,expected,{workspace=root}={}){
 must(typeof relative==='string'&&/^[A-Za-z0-9_./-]+$/.test(relative)&&!relative.includes('..')&&!path.isAbsolute(relative),'PUBLIC_SCHEDULE_BINDING_REQUIRED');
 const file=path.resolve(workspace,relative),bytes=await fs.readFile(file);must(sha(bytes)===expected,'SCHEDULE_SOURCE_OR_EVIDENCE_CHANGED');return bytes;
}
export async function validatePreservedSources({workspace=root}={}){
 for(const binding of PRESERVED)await exactFile(binding.path,binding.sha256,{workspace});
 const owner=JSON.parse(await exactFile(PRESERVED[6].path,PRESERVED[6].sha256,{workspace}));
 const probe=JSON.parse(await exactFile(PRESERVED[7].path,PRESERVED[7].sha256,{workspace}));
 const readback=JSON.parse(await exactFile(PRESERVED[8].path,PRESERVED[8].sha256,{workspace}));
 const originalApproval=JSON.parse(await exactFile(PRESERVED[12].path,PRESERVED[12].sha256,{workspace}));
 must(originalApproval.decision==='approve'&&originalApproval.runtimeBundleSha256===BUNDLE,'ORIGINAL_RUNTIME_APPROVAL_REQUIRED');
 must(owner.scheduleResumeAuthorizedByThisDecision===false&&owner.originalAuthorityExpiresAt===EXPIRES
  &&owner.scheduledRequestsAlreadyObserved===24&&owner.maximumScheduleRequestsOriginal===4320,'OLD_WORKER_APPROVAL_SCOPE_MUST_REMAIN_EXACT');
 must(probe.actualUnsignedProbePassed===true&&probe.status===403&&probe.code==='WORKER_ACCESS_DENIED'&&probe.returnedSourceRowsVerified===25
  &&probe.backendServiceKeyRoleOrValidityVerified===false&&probe.scheduleResumeAuthorized===false,'EXACT_V7_UNSIGNED_PROBE_FACTS_REQUIRED');
 must(readback.sources.length===25&&readback.peopleFunctionMetadataUnchanged===true,'EXACT_V7_DEPLOYMENT_READBACK_REQUIRED');
 for(const binding of readback.evidence)await exactFile(binding.path,binding.sha256,{workspace});
 for(const binding of readback.sources)await exactFile(binding.path,binding.sha256,{workspace});
 return {passed:true,preservedBindings:PRESERVED.length,returnedSourceRows:25,readSqlSha256:sha(READ_SQL),
  executePrerequisitesPending:true,privateInputsRead:false,networkCalls:0,originalExpiry:EXPIRES};
}
async function save(directory,file,value){
 const target=path.resolve(root,directory,file);must(target.startsWith(path.resolve(root)+path.sep),'PUBLIC_RESUME_EVIDENCE_OUTSIDE_ROOT');
 const bytes=Buffer.from(JSON.stringify(value,null,2)+'\n'),handle=await fs.open(target,'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:path.posix.join(directory,file),sha256:sha(bytes)};
}
export async function main(argv=process.argv.slice(2),{stdin=process.stdin,stdout=process.stdout,now=Date.now}={}){
 must(argv.length===(argv[0]==='--execute'?2:1)&&['--validate','--execute'].includes(argv[0]),'EXACT_SCHEDULE_RESUME_MODE_REQUIRED');
 if(argv[0]==='--execute')validateTime(now()); // before file review, stdin or any private input
 const validation=await validatePreservedSources();
 if(argv[0]==='--validate'){stdout.write(JSON.stringify({...validation,originalAuthorityCurrentlyUnexpired:now()<Date.parse(EXPIRES),
  actualResumeAllowed:false,originalA4IntentReused:false})+'\n');return validation;}
 must(digest(argv[1]),'PINNED_EXACT_SCHEDULE_OPERATION_REVIEW_SHA_REQUIRED');
 const review=JSON.parse(await exactFile(REVIEW,argv[1]));
 const metadata=JSON.parse(await exactFile(review.ownerMetadataBinding?.path,review.ownerMetadataBinding?.sha256));
 const exportsProof=JSON.parse(await exactFile(review.completedExportsBinding?.path,review.completedExportsBinding?.sha256));
 must(review.providerAuthorityBinding?.path===PROVIDER_REVIEW&&digest(review.providerAuthorityBinding.sha256),
  'EXACT_ACTUAL_PROVIDER_AUTHORITY_BINDING_REQUIRED');
 const providerAuthority=JSON.parse(await exactFile(PROVIDER_REVIEW,review.providerAuthorityBinding.sha256));
 must(equal(review.actualHealthResultBinding,providerAuthority.actualHealthResultBinding),'EXACT_HEALTH_RESULT_BINDING_REQUIRED');
 const healthResult=JSON.parse(await exactFile(review.actualHealthResultBinding?.path,review.actualHealthResultBinding?.sha256));
 const healthEvidence={};
 for(const [name,key] of [['before','actualBeforeStateBinding'],['dispatch','actualDispatchBinding'],['after','actualAfterStateBinding']]){
  must(providerAuthority.evidenceBindings?.some(binding=>equal(binding,providerAuthority[key])),'EXACT_HEALTH_LINEAGE_BINDINGS_REQUIRED');
  healthEvidence[name]=JSON.parse(await exactFile(providerAuthority[key]?.path,providerAuthority[key]?.sha256));
 }
 const sourceSha256=sha(await fs.readFile(path.join(root,SOURCE)));
 validateFinalReview(review,{sourceSha256,metadata,exportsProof,providerAuthority,healthResult,healthEvidence,now:now()});
 must(Array.isArray(review.sourceAndEvidenceBindings)&&review.sourceAndEvidenceBindings.length>0,'EXACT_SCHEDULE_REVIEW_BINDINGS_REQUIRED');
 must([...PRESERVED,{path:SOURCE,sha256:sourceSha256},review.ownerMetadataBinding,review.completedExportsBinding,
  review.providerAuthorityBinding,...providerAuthority.evidenceBindings].every(required=>
  review.sourceAndEvidenceBindings.some(binding=>binding.path===required.path&&binding.sha256===required.sha256)),
  'ALL_REQUIRED_SCHEDULE_SOURCE_BINDINGS_REQUIRED');
 for(const binding of review.sourceAndEvidenceBindings)await exactFile(binding.path,binding.sha256);
 must(review.privateAdapter?.path==='scripts/wave5/run_private_management_installer_20261013_r5.ps1'&&digest(review.privateAdapter.sha256),
  'EXACT_PRIVATE_ADAPTER_REVIEW_REQUIRED');await exactFile(review.privateAdapter.path,review.privateAdapter.sha256);
 validateTime(now(),{expiresAt:review.authorizationExpiresAt});
 let incoming='',cfg,key;
 try{
  for await(const chunk of stdin){validateTime(now(),{expiresAt:review.authorizationExpiresAt});incoming+=chunk;must(incoming.length<=16000,'PRIVATE_INPUT_LIMIT');}
  validateTime(now(),{expiresAt:review.authorizationExpiresAt});cfg=JSON.parse(incoming);incoming='';
  must(cfg?.projectId===PROJECT&&cfg.bundleSha256===BUNDLE&&cfg.privateDirectory===metadata.privateFolder,'EXACT_PRIVATE_RESUME_INPUT_REQUIRED');
  const {runtimeSealKey,appendRuntimeSecret}=await import('./private_runtime_seal.mjs');key=runtimeSealKey(cfg.encryptionKey);
  const directory='docs/verification/wave5/task3-schedule-resume-20261014/actual-'+now()+'/';await fs.mkdir(path.join(root,directory));
  const transport=createScheduleTransport(cfg.ownerToken,{writeSql:buildResumeSql(review.guardFingerprints,review.readinessTick),now,expiresAt:review.authorizationExpiresAt});
  const result=await runScheduleResume({transport,guardFingerprints:review.guardFingerprints,readinessTick:review.readinessTick,now,expiresAt:review.authorizationExpiresAt,
   once:value=>save('',ONCE,{...value,finalReviewSha256:argv[1],completedExportsBinding:review.completedExportsBinding,directory}),
   persist:(file,value)=>save(directory,file,value),appendPrivate:(kind,value)=>appendRuntimeSecret(cfg.privateDirectory,key,kind,value)});
  stdout.write(JSON.stringify({passed:true,evidencePath:directory+'99-result.json',managementAttempts:result.managementAttempts,actualDelivery:false})+'\n');return result;
 }finally{key?.fill(0);if(cfg){cfg.ownerToken=null;cfg.encryptionKey=null;}incoming='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'SCHEDULE_RESUME_STOP',secretsPrinted:false})+'\n');process.exitCode=1;});
