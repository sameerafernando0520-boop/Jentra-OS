// Additive renewed-window successor. Import and construction perform no I/O.
// The Oct 14 helper, consumed intent, expiry and controlled evidence stay immutable.
import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual as same} from 'node:util';
import {PROJECT,BUNDLE,RUNTIME,TENANT,ISSUED,EXPIRES as ORIGINAL_EXPIRY,JOBS,GUARDS,EXPORT_COMMANDS,
 PRESERVED as ORIGINAL_BINDINGS,validateFingerprints,validateReadinessTick,validateExportsProof,
 validatePreservedSources as validateOriginalSources} from './resume_worker_schedules_20261014_r5_v7.mjs';
export {PROJECT,BUNDLE,RUNTIME,TENANT,ISSUED,ORIGINAL_EXPIRY,JOBS,GUARDS,EXPORT_COMMANDS,
 validateFingerprints,validateReadinessTick,validateExportsProof};
export const SOURCE='tools/wave5/resume_worker_schedules_20261017_r5_a2.mjs';
export const PLAN='docs/verification/wave5/task3-schedule-resume-20261017/renewed-execution-plan-20261017-r5-a2.json';
export const REVIEW='docs/verification/wave5/task3-schedule-resume-20261017/final-operation-review-20261017-r5-a2.json';
export const PROVIDER_REVIEW='docs/verification/wave5/task3-schedule-resume-20261014/actual-provider-authority-review-20261015-r5-a1.json';
export const ONCE='docs/verification/wave5/task3-schedule-resume-20261017/resume-once-20261017-r5-a2.json';
export const PRIVATE_ADAPTER='scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1';
export const HEALTH_SOURCE='tools/wave5/probe_worker_v7_health_20261014_r5.mjs';
export const CANDIDATE='2a540cabaf0b8ac10f1a553e07b5cea0e886cb9ec380ff8560f500eba4b1f35c';
export const SCOPE_ISSUED='2026-10-13T08:13:04.144135+00:00',SCOPE_OLD_EXPIRY='2026-10-14T08:13:04.144135+00:00';
export const AUTHORITY_HASH='77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139';
export const SCOPE_HASH='3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387';
export const OUTSIDE_HASH='4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945';
export const SCHEDULE_REPLY='Approve the exact two-row runtime renewal and export a7 continuation';
export const SCHEDULE_DECISION='docs/verification/wave5/task3-schedule-resume-20261017/conditional-schedule-owner-decision-20261017-r5-a2.json';
export const HEALTH_DECISION='docs/verification/wave5/runtime-renewed-health-scheduler-owner-decision-20261015-r5-a1.json';
export const WINDOW_RULE=Object.freeze({anchor:'actual-renewal-server-preflight',maximumWindowMs:7200000,
 expiresAt:'min(serverWindowAnchor+maximumWindowMs,actualA10Metadata.expiresAt)',preserveOriginalIssuedAt:true,preserveOriginalSevenDayGuards:true});
export const PRECONDITIONS=Object.freeze({actualTwoRowRenewalWithThreeRawReceipts:true,twoOriginalExportsCompleted:true,
 oneAuthenticatedDeployedV7HealthPassed:true,schedulesPausedUntilFinalReview:true,independentFinalReviewOfActualWindowAndReceipts:true});
export const BUDGET=Object.freeze({recordedPrior:137,ownerRefresh:1,renewal:3,priorAtExports:141,
 exportsOrdinary:24,exportsResolutionReserve:1,throughExportsMaximum:166,healthMaximum:5,
 throughHealthMaximum:171,schedulerMaximum:3,overallMaximum:174,historicalWorkerRequests:24,
 readinessWorkerRequests:1,reviewedWorkerRequests:25,wholeWorkerMaximum:4320});
export const RENEWAL_PROPOSAL=Object.freeze({path:'docs/verification/wave5/task3-runtime-renewal-20261014/renewal-proposal-a2.json',
 sha256:'8bb011428684768dc98b520e895b2bad0d1f9ddf7e17cd198083cc56bca9ef2c'});
export const CALL_INVENTORY=Object.freeze({path:'docs/verification/wave5/seven-area-completion-20261016/continuation-call-inventory-a1.json',
 sha256:'305503c62e6cc662971fddfe43672f86b6b89a7f328d440711312d06cb6407c0'});
export const DEPLOYED_ARCHIVE='build/wave5-deployed-v7-archive-20261017/';
export const ARCHIVE_MANIFEST=Object.freeze({path:'docs/verification/wave5/seven-area-completion-20261016/area4-integrations/deployed-archive-manifest.json',
 sha256:'8e0cf9712d58fcc01204fd2669afdaf88f74f57581883916a9b3344e2f9fbdca'});
export const FIXED_CONTROLS=Object.freeze({
 metadata:'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json',
 refresh:'docs/verification/wave5/private-owner-scope-refresh-20261014-r5-a10.json',
 accounting:'docs/verification/wave5/finance-cumulative-read-accounting-20261016-r5-a7.json',
 humanRenewalDecision:'docs/verification/wave5/runtime-renewal-export-owner-decision-20261016-r5-a7.json',
 renewalReadback:'docs/verification/wave5/runtime-renewal-two-row-readback-20261016-r5-a7.json',
 sourcePolicy:'docs/verification/wave5/task3-export-renewal-20261016/source-policy-a1.json',
 independentPolicyReview:'docs/verification/wave5/task3-export-renewal-20261016/independent-policy-review-a1.json',
 exportsPlan:'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json',
 providerAuthorityReview:PROVIDER_REVIEW,humanHealthDecision:HEALTH_DECISION,humanScheduleDecision:SCHEDULE_DECISION});
const root=fileURLToPath(new URL('../../',import.meta.url));
const sha=value=>createHash('sha256').update(value).digest('hex');
const must=(ok,code)=>{if(!ok){const e=Error(code);e.publicCode=code;throw e;}};
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(value);
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&same(Object.keys(value).sort(),[...keys].sort());
const receipt=value=>value&&typeof value.path==='string'&&digest(value.sha256);
export function schedulePlanBinding(review){
 must(review?.generatedPlan?.path===PLAN&&receipt(review.generatedPlan)
  &&(review.planBinding===undefined||same(review.planBinding,review.generatedPlan)),'EXACT_GENERATED_SCHEDULE_PLAN_REQUIRED');
 return review.generatedPlan;
}
const publicPath=value=>typeof value==='string'&&/^[A-Za-z0-9_./-]+$/.test(value)&&!value.includes('..')
 &&(value.startsWith('docs/verification/wave5/')||value.startsWith('tools/wave5/')||value.startsWith(DEPLOYED_ARCHIVE)
 ||value.startsWith('workers/wave5/')||value.startsWith('supabase/')||value.startsWith('scripts/wave5/'));
export const PRESERVED=Object.freeze([...ORIGINAL_BINDINGS,
 {path:'tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs',sha256:'8bf3fcbb9ec17a2697afa7c4e360e664503e0128922fb8361b64450af73e8372'},
 {path:'docs/verification/wave5/task3-schedule-resume-20261014/source-proof-health-a3.json',sha256:'c99d71eee8fcc8f4735f8bcb40626ee48fb9ef40ae8ee48e8b00f42fd00049bf'},
 RENEWAL_PROPOSAL,CALL_INVENTORY,ARCHIVE_MANIFEST,
 {path:'tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs',sha256:'2b823d111990d2f93f1dcefe62d2bc48c2498a40b333311e4894738928a8604f'}].map(row=>Object.freeze({...row})));

export function validateLockInventory(plan,required){
 const sources=plan?.sourceBindings,publicFiles=plan?.publicBindings;
 must(Array.isArray(sources)&&Array.isArray(publicFiles)&&[...sources,...publicFiles].every(row=>receipt(row)&&publicPath(row.path)),
  'EXPLICIT_SOURCE_AND_PUBLIC_LOCK_INVENTORIES_REQUIRED');
 const all=[...sources,...publicFiles];
 must(new Set(all.map(row=>row.path)).size===all.length&&required.every(row=>all.some(item=>same(item,row)))
  &&all.every(row=>required.some(item=>same(item,row))),'EXHAUSTIVE_EXACT_PUBLIC_LOCK_INVENTORY_REQUIRED');
 return all;
}
const uniqueBindings=rows=>{const byPath=new Map();for(const row of rows){must(receipt(row),'BOUND_PUBLIC_INVENTORY_ROW_REQUIRED');
 if(byPath.has(row.path))must(same(byPath.get(row.path),row),'NO_CONFLICTING_PUBLIC_BINDINGS_REQUIRED');else byPath.set(row.path,row);}return [...byPath.values()];};
export function validateCallInventory(value){
 must(value?.kind==='unapproved-bounded-seven-area-continuation-call-inventory'&&value.projectId===PROJECT&&value.runtimeId===RUNTIME
  &&value.sourceOnly===true&&value.executionPermitted===false&&value.approvalRecorded===false&&value.actualBaseline?.chargedCalls===137
  &&same(value.arithmetic,{actualPrior:137,ownerRefresh:1,renewal:3,priorAtExports:141,exportsOrdinary:24,exportsResolutionReserve:1,
   throughExportsMaximum:166,healthMaximum:5,throughHealthMaximum:171,schedulerMaximum:3,overallMaximum:174,maximumFutureAttempts:37})
  &&value.unchangedWorkerBounds?.knownHistoricalRequests===24&&value.unchangedWorkerBounds.maximumWorkerRequests===4320,
  'EXACT_137_BASELINE_UNAPPROVED_174_INVENTORY_REQUIRED');return value;
}

// Parse explicit UTC and retain microseconds for identity checks and SQL. A
// millisecond local clock fails slightly early at a sub-ms deadline, never late.
export function utc(value){
 must(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(value),'EXPLICIT_VALID_UTC_TIMESTAMP_REQUIRED');
 const n=Date.parse(value);must(Number.isFinite(n)&&new Date(n).toISOString().slice(0,19)===value.slice(0,19),'EXPLICIT_VALID_UTC_TIMESTAMP_REQUIRED');return n;
}
const micros=value=>{utc(value);const m=value.match(/^(.*T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|\+00:00)$/);
 return BigInt(Date.parse(m[1]+'Z'))*1000n+BigInt((m[2]??'').padEnd(6,'0'));};
const sameTime=(a,b)=>micros(a)===micros(b);
export function validateWindow(window){
 must(exact(window,['notBefore','edgeExpiresAt','scopeExpiresAt','privateExpiresAt','expiresAt']),'EXACT_RENEWED_WINDOW_REQUIRED');
 const start=micros(window.notBefore),edge=micros(window.edgeExpiresAt),scope=micros(window.scopeExpiresAt),owner=micros(window.privateExpiresAt),end=micros(window.expiresAt);
 must(edge===scope&&edge>start&&edge-start<=7200000000n&&owner>start&&end===(edge<owner?edge:owner)&&end>start
  &&edge<=micros(ISSUED)+604800000000n&&scope<=micros(SCOPE_ISSUED)+604800000000n,'BOUNDED_BOTH_RENEWED_EXPIRIES_REQUIRED');return window;
}
export function validateTime(now,window){
 validateWindow(window);must(Number.isFinite(now)&&now>=utc(window.notBefore)&&now<utc(window.expiresAt),'RENEWED_SCHEDULE_WINDOW_EXPIRED');return utc(window.expiresAt);
}

const scopeSql=`intelligence_control.runtime_scope_allowed('${RUNTIME}','${TENANT}','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1')`;
const fingerprintsSql=`(SELECT jsonb_agg(jsonb_build_object('signature',s,'md5',md5(pg_get_functiondef(s::regprocedure))) ORDER BY s) FROM unnest(ARRAY[${GUARDS.map(s=>"'"+s+"'").join(',')}]) s)`;
const exportSql=`(SELECT count(*) FROM core.export_jobs WHERE tenant_id='${TENANT}' AND actor_id='${EXPORT_COMMANDS[0].actorId}' AND status='completed'
 AND id IN ('${EXPORT_COMMANDS[0].exportId}'::uuid,'${EXPORT_COMMANDS[1].exportId}'::uuid))=2
 AND (SELECT count(*) FROM core.command_receipts WHERE tenant_id='${TENANT}' AND actor_id='${EXPORT_COMMANDS[0].actorId}' AND command_name='finance.report.export' AND aggregate_type='report_export'
 AND ((command_id='${EXPORT_COMMANDS[0].commandId}' AND aggregate_id='${EXPORT_COMMANDS[0].exportId}') OR (command_id='${EXPORT_COMMANDS[1].commandId}' AND aggregate_id='${EXPORT_COMMANDS[1].exportId}')))=2`;
const jobsSql=`(SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'active',active,'schedule',schedule,'command',command) ORDER BY jobid) FROM cron.job WHERE jobid IN(4,5,6))`;
export const READ_SQL=`SELECT jsonb_build_object('observedAt',statement_timestamp(),'timeZone',current_setting('TimeZone'),
 'scopeAllowed',${scopeSql},'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'apiFunctionCount',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api'),
 'guardFingerprints',${fingerprintsSql},
 'serviceRoleRpcGrants',has_function_privilege('service_role','api.wave5_runtime_worker(uuid,text,jsonb)','EXECUTE') AND has_function_privilege('service_role','api.wave5_edge_control(uuid,text,jsonb)','EXECUTE'),
 'authority',(SELECT jsonb_build_object('runtimeId',runtime_id,'enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,'jobIds',job_ids,
  'nonWindowHash',encode(extensions.digest((to_jsonb(a)-'expires_at')::text,'sha256'),'hex')) FROM intelligence_control.edge_authorities a WHERE runtime_id='${RUNTIME}'),
 'scopes',(SELECT jsonb_build_object('count',count(*),'enabled',count(*) FILTER(WHERE enabled),'issuedMin',min(issued_at),'issuedMax',max(issued_at),
  'expiresMin',min(expires_at),'expiresMax',max(expires_at),'nonWindowHash',encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(s)-'expires_at' ORDER BY tenant_id,legal_entity_id,branch_id)::text,'[]'),'sha256'),'hex')) FROM intelligence_control.runtime_worker_scopes s WHERE runtime_id='${RUNTIME}'),
 'ownJobs',${jobsSql},
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN(4,5,6)),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='${RUNTIME}'),
 'readinessTicks',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'state',t.state,
  'tickSha256',encode(extensions.digest(to_jsonb(t)::text,'sha256'),'hex'),'outcomeSha256',encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex'),
  'success',o.success,'summary',o.summary) ORDER BY t.id),'[]'::jsonb) FROM intelligence_control.edge_ticks t LEFT JOIN intelligence_control.edge_tick_outcomes o ON o.runtime_id=t.runtime_id AND o.id=t.id WHERE t.runtime_id='${RUNTIME}'),
 'tickOutcomes',(SELECT count(*) FROM intelligence_control.edge_tick_outcomes WHERE runtime_id='${RUNTIME}'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='${TENANT}'),
 'deliveryOutcomes',(SELECT count(*) FROM intelligence_control.delivery_outcomes WHERE tenant_id='${TENANT}'),
 'receiverReceipts',(SELECT count(*) FROM intelligence_control.edge_receiver_receipts WHERE runtime_id='${RUNTIME}'),
 'modelInvocations',(SELECT count(*) FROM intelligence_control.model_invocations WHERE tenant_id='${TENANT}'),
 'modelOutcomes',(SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id='${TENANT}'),
 'usageEvents',(SELECT count(*) FROM intelligence_control.usage_events WHERE tenant_id='${TENANT}'),
 'recordedCronRuns',(SELECT count(*) FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>='${ISSUED}'::timestamptz),
 'completedOriginalExports',${exportSql}) AS snapshot;`;

export function buildResumeSql(fingerprints,tick,window){
 validateFingerprints(fingerprints);validateReadinessTick(tick);validateWindow(window);
 // UTC timestamp validation, fixed identities and hex-only digests are the only
 // interpolated inputs; no caller SQL, identifiers or free text are accepted.
 return `BEGIN;
SET LOCAL standard_conforming_strings=on;
SET LOCAL search_path=pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $resume_renewed_exact_jobs$
DECLARE a intelligence_control.edge_authorities%rowtype; s intelligence_control.runtime_worker_scopes%rowtype;
 b core.branches%rowtype; j bigint; recorded bigint;
BEGIN
 SELECT * INTO STRICT a FROM intelligence_control.edge_authorities WHERE runtime_id='${RUNTIME}' FOR UPDATE;
 SELECT * INTO STRICT s FROM intelligence_control.runtime_worker_scopes WHERE runtime_id='${RUNTIME}'
  AND tenant_id='${TENANT}' AND legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd' AND branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1' FOR UPDATE;
 SELECT * INTO STRICT b FROM core.branches WHERE tenant_id=s.tenant_id AND id=s.branch_id FOR SHARE;
 PERFORM jobid FROM cron.job WHERE jobid IN(4,5,6) ORDER BY jobid FOR UPDATE;
 IF current_user<>'postgres' OR current_setting('TimeZone')<>'UTC'
  OR clock_timestamp()<'${window.notBefore}'::timestamptz OR clock_timestamp()>='${window.expiresAt}'::timestamptz
  OR NOT a.enabled OR a.issued_at<>'${ISSUED}'::timestamptz OR a.expires_at<>'${window.edgeExpiresAt}'::timestamptz
  OR a.job_ids IS DISTINCT FROM ARRAY[4,5,6]::bigint[]
  OR encode(extensions.digest((to_jsonb(a)-'expires_at')::text,'sha256'),'hex')<>'${AUTHORITY_HASH}'
  OR NOT s.enabled OR s.issued_at<>'${SCOPE_ISSUED}'::timestamptz OR s.expires_at<>'${window.scopeExpiresAt}'::timestamptz
  OR s.expires_at<>a.expires_at OR a.expires_at>a.issued_at+interval '7 days' OR s.expires_at>s.issued_at+interval '7 days'
  OR encode(extensions.digest(jsonb_build_array(to_jsonb(s)-'expires_at')::text,'sha256'),'hex')<>'${SCOPE_HASH}'
  OR (SELECT count(*) FROM intelligence_control.runtime_worker_scopes WHERE runtime_id='${RUNTIME}')<>1
  OR b.status<>'active' OR b.legal_entity_id<>s.legal_entity_id
  THEN RAISE EXCEPTION 'EXACT_LOCKED_RENEWED_AUTHORITY_AND_SCOPE_REQUIRED'; END IF;
 IF NOT ${scopeSql} THEN RAISE EXCEPTION 'EXACT_APPROVED_SCOPE_REQUIRED'; END IF;
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>115 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api')<>363
  THEN RAISE EXCEPTION 'EXACT_115_363_BASELINE_REQUIRED'; END IF;
 IF ${fingerprintsSql} IS DISTINCT FROM '${JSON.stringify(fingerprints)}'::jsonb
  OR NOT has_function_privilege('service_role','api.wave5_runtime_worker(uuid,text,jsonb)','EXECUTE')
  OR NOT has_function_privilege('service_role','api.wave5_edge_control(uuid,text,jsonb)','EXECUTE')
  THEN RAISE EXCEPTION 'UNCHANGED_SERVER_AUTHORITY_GUARDS_REQUIRED'; END IF;
 IF NOT (${exportSql}) THEN RAISE EXCEPTION 'EXACT_TWO_COMPLETED_EXPORTS_FIRST_REQUIRED'; END IF;
 IF ${jobsSql} IS DISTINCT FROM '${JSON.stringify(JOBS.map(job=>({...job,active:false})))}'::jsonb
  OR (SELECT count(*) FROM cron.job WHERE jobname IN ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'))<>3
  THEN RAISE EXCEPTION 'EXACT_THREE_PAUSED_OWN_JOBS_REQUIRED'; END IF;
 IF (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(c) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job c WHERE jobid NOT IN(4,5,6))<>'${OUTSIDE_HASH}'
  THEN RAISE EXCEPTION 'OUTSIDE_JOB_PRESERVATION_REQUIRED'; END IF;
 IF (SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='${RUNTIME}')<>1
  OR (SELECT count(*) FROM intelligence_control.edge_tick_outcomes WHERE runtime_id='${RUNTIME}')<>1
  OR NOT EXISTS(SELECT 1 FROM intelligence_control.edge_ticks t JOIN intelligence_control.edge_tick_outcomes o ON o.runtime_id=t.runtime_id AND o.id=t.id
   WHERE t.runtime_id='${RUNTIME}' AND t.id='${tick.id}' AND t.kind='health' AND t.state='completed' AND o.success
   AND o.summary='{"count":1,"states":["collected"]}'::jsonb
   AND encode(extensions.digest(to_jsonb(t)::text,'sha256'),'hex')='${tick.tickSha256}'
   AND encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex')='${tick.outcomeSha256}')
  THEN RAISE EXCEPTION 'EXACT_ONE_BOUND_HEALTH_READINESS_TICK_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM intelligence_control.quota_periods WHERE tenant_id='${TENANT}')
  OR EXISTS(SELECT 1 FROM intelligence_control.delivery_outcomes WHERE tenant_id='${TENANT}')
  OR EXISTS(SELECT 1 FROM intelligence_control.edge_receiver_receipts WHERE runtime_id='${RUNTIME}')
  OR EXISTS(SELECT 1 FROM intelligence_control.model_invocations WHERE tenant_id='${TENANT}')
  OR EXISTS(SELECT 1 FROM intelligence_control.usage_events WHERE tenant_id='${TENANT}')
  THEN RAISE EXCEPTION 'NO_UNREVIEWED_QUOTA_DELIVERY_MODEL_EFFECTS_REQUIRED'; END IF;
 SELECT count(*) INTO recorded FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>=a.issued_at;
 IF recorded<>24 OR recorded+1+3*ceil(extract(epoch FROM(a.expires_at-clock_timestamp()))/60)>4320
  THEN RAISE EXCEPTION 'PRESERVED_REQUEST_BUDGET_REQUIRED'; END IF;
 IF clock_timestamp()>='${window.expiresAt}'::timestamptz THEN RAISE EXCEPTION 'RENEWED_OPERATION_DEADLINE_EXPIRED'; END IF;
 FOREACH j IN ARRAY ARRAY[4,5,6]::bigint[] LOOP PERFORM cron.alter_job(j,active:=true); END LOOP;
END $resume_renewed_exact_jobs$;
COMMIT;`;
}

const zero={quotaPeriods:0,deliveryOutcomes:0,receiverReceipts:0,modelInvocations:0,modelOutcomes:0,usageEvents:0};
function assertRenewedRows(value,window){
 must(value?.timeZone==='UTC'&&value.authority?.enabled===true&&value.authority.nonWindowHash===AUTHORITY_HASH
  &&same(value.authority.jobIds,[4,5,6])&&sameTime(value.authority.issuedAt,ISSUED)&&sameTime(value.authority.expiresAt,window.edgeExpiresAt)
  &&value.scopes?.count===1&&value.scopes.enabled===1&&value.scopes.nonWindowHash===SCOPE_HASH
  &&sameTime(value.scopes.issuedMin,SCOPE_ISSUED)&&sameTime(value.scopes.issuedMax,SCOPE_ISSUED)
  &&sameTime(value.scopes.expiresMin,window.scopeExpiresAt)&&sameTime(value.scopes.expiresMax,window.scopeExpiresAt),
  'UNCHANGED_BOTH_RENEWED_ROW_IDENTITIES_REQUIRED');
}
export function validateHealthResult(result,{tick,fingerprints,window,now=Date.now()}={}){
 validateTime(now,window);validateReadinessTick(tick);validateFingerprints(fingerprints);
 must(result?.kind==='actual-v7-deployed-health-readiness-result'&&result.passed===true&&result.controlledFixture===false
  &&result.projectId===PROJECT&&result.runtimeBundleSha256===BUNDLE&&result.runtimeId===RUNTIME&&result.deployedVersion===7&&result.candidateBundleSha256===CANDIDATE
  &&result.authenticatedDatabaseOwnedInvocation===true&&result.clientScheduleSecretRetrieved===false&&result.hmacSignatureClaimed===false
  &&result.requestCount===1&&result.automaticRetries===0&&Number.isSafeInteger(result.managementAttempts)&&result.managementAttempts>=3&&result.managementAttempts<=5
  &&Number.isSafeInteger(result.netRequestId)&&result.netRequestId>0&&result.status===200&&uuid(result.serverRequestId)
  &&same(result.response,{state:'completed',count:1,states:['collected']})&&digest(result.responseSha256)&&same(result.readinessTick,tick)
  &&same(result.healthOutcome,{success:true,summary:{count:1,states:['collected']}})
  &&same(result.effectsBefore,{ticks:0,outcomes:0,...zero})&&same(result.effectsAfter,{ticks:1,outcomes:1,...zero})
  &&same(result.guardFingerprints,fingerprints)&&result.historicalScheduleRequests===24&&result.readinessInvocations===1
  &&result.cumulativeScheduleRequests===25&&result.maximumScheduleRequests===4320&&result.jobsRemainPaused===true
  &&result.actualDelivery===false&&result.actualModelUsage===false&&utc(result.observedAt)>=utc(window.notBefore)
  &&utc(result.observedAt)<=now&&now-utc(result.observedAt)<300000,'ACTUAL_DEPLOYED_AUTHENTICATED_HEALTH_RESULT_REQUIRED');return result;
}
export function validateHealthEvidence(result,{before,dispatch,after},window){
 assertRenewedRows(before,window);assertRenewedRows(after,window);
 must(same(before.effects,result.effectsBefore)&&same(after.effects,result.effectsAfter)&&same(before.guardFingerprints,result.guardFingerprints)
  &&same(after.guardFingerprints,result.guardFingerprints)&&before.scopeAllowed===true&&after.scopeAllowed===true&&before.completedExports===true&&after.completedExports===true
  &&before.migrationCount===115&&after.migrationCount===115&&before.apiFunctionCount===363&&after.apiFunctionCount===363
  &&same(before.ownJobs,JOBS.map(job=>({...job,active:false})))&&same(after.ownJobs,before.ownJobs)
  &&before.outsideJobHash===OUTSIDE_HASH&&after.outsideJobHash===OUTSIDE_HASH&&dispatch.requestId===result.netRequestId
  &&sameTime(dispatch.dispatchedAt,result.dispatchedAt)&&sameTime(after.observedAt,result.observedAt)&&after.ticks?.length===1,
  'ACTUAL_HEALTH_STATE_DISPATCH_LINEAGE_REQUIRED');
 const h=after.http,t=after.ticks[0],{startedAt,recordedAt,tickRow,outcomeRow,...identity}=t;
 must(same(identity,{...result.readinessTick,success:true,summary:{count:1,states:['collected']}})&&h?.id===result.netRequestId&&h.status===200&&h.timedOut===false
  &&typeof h.content==='string'&&h.responseBytes===Buffer.byteLength(h.content)&&h.responseBytes<=1024&&sha(h.content)===h.responseSha256
  &&h.responseSha256===result.responseSha256&&h.serverRequestId===result.serverRequestId
  &&micros(before.observedAt)>=micros(window.notBefore)&&micros(before.observedAt)<=micros(dispatch.dispatchedAt)
  &&micros(dispatch.dispatchedAt)<=micros(startedAt)&&micros(startedAt)<=micros(recordedAt)&&micros(recordedAt)<=micros(after.observedAt)
  &&micros(after.observedAt)<micros(window.expiresAt),'ACTUAL_HEALTH_HTTP_AND_TICK_LINEAGE_REQUIRED');
 must(tickRow?.runtime_id===RUNTIME&&tickRow.id===t.id&&tickRow.kind==='health'&&tickRow.state==='completed'&&sameTime(tickRow.started_at,startedAt)
  &&micros(tickRow.lease_until)>micros(recordedAt)&&outcomeRow?.runtime_id===RUNTIME&&outcomeRow.id===t.id&&outcomeRow.success===true
  &&same(outcomeRow.summary,t.summary)&&sameTime(outcomeRow.recorded_at,recordedAt),'ACTUAL_HEALTH_RAW_TICK_AND_OUTCOME_REQUIRED');
 let body;try{body=JSON.parse(h.content);}catch{must(false,'ACTUAL_HEALTH_HTTP_JSON_REQUIRED');}
 must(same(body,result.response),'ACTUAL_HEALTH_HTTP_BODY_REQUIRED');return true;
}
export function validateProviderAuthority(proof,{binding,fingerprints,healthResult,healthEvidence,window,now=Date.now()}={}){
 validateTime(now,window);
 must(binding?.path===PROVIDER_REVIEW&&digest(binding.sha256)&&proof?.kind==='independent-actual-v7-deployed-health-readiness-review'
  &&proof.technicalDecision==='approve'&&proof.passed===true&&proof.independentlyReviewed===true&&proof.projectId===PROJECT&&proof.runtimeBundleSha256===BUNDLE
  &&proof.runtimeId===RUNTIME&&proof.deployedVersion===7&&proof.candidateBundleSha256===CANDIDATE
  &&proof.credentialSource==='existing-injected-worker-service-key'&&proof.backendRole==='service_role'
  &&proof.actualDeployedWorkerBackendAuthorizationVerified===true&&proof.actualServiceKeyRoleAndValidityVerified===true
  &&proof.unsignedProbeUsedAsRoleProof===false&&proof.keyFormatUsedAsRoleProof===false&&proof.secretsPublished===false
  &&utc(proof.observedAt)<=now&&now-utc(proof.observedAt)<300000&&utc(proof.observedAt)>=utc(window.notBefore)
  &&same(proof.guardFingerprints,fingerprints)&&proof.priorScheduledRequestsObserved===24&&proof.readinessRequestsCharged===1&&proof.cumulativeReviewedWorkerRequests===25,
  'ACTUAL_BACKEND_PROVIDER_AUTHORITY_PROOF_REQUIRED');
 const keys=['actualHealthResultBinding','actualBeforeStateBinding','actualDispatchBinding','actualAfterStateBinding','healthControllerSourceBinding'];
 must(Array.isArray(proof.evidenceBindings)&&proof.evidenceBindings.every(row=>receipt(row)&&publicPath(row.path))
  &&new Set(proof.evidenceBindings.map(row=>row.path)).size===proof.evidenceBindings.length
  &&keys.every(key=>proof.evidenceBindings.some(row=>same(row,proof[key])))&&proof.healthControllerSourceBinding?.path===HEALTH_SOURCE,
  'ACTUAL_HASH_BOUND_HEALTH_RESULT_REQUIRED');
 validateHealthResult(healthResult,{tick:proof.readinessTick,fingerprints,window,now});
 must(same(healthResult.actualReadbackBinding,proof.actualAfterStateBinding)&&Array.isArray(healthResult.evidenceBindings)
  &&keys.slice(1,4).every(key=>healthResult.evidenceBindings.some(row=>same(row,proof[key]))),'ACTUAL_HEALTH_RESULT_EVIDENCE_LINEAGE_REQUIRED');
 validateHealthEvidence(healthResult,healthEvidence,window);
 must(micros(healthResult.observedAt)<=micros(proof.observedAt),'ACTUAL_HEALTH_OBSERVATION_LINEAGE_REQUIRED');return proof;
}

function snapshotOf(response){
 must(Array.isArray(response)&&response.length===1&&response[0].renewal_snapshot,'ACTUAL_RENEWAL_RAW_RESPONSE_REQUIRED');return response[0].renewal_snapshot;
}
export function validateRenewalTimeline({readback:r,human,metadata,before,after,writeResponse,window,now=Date.now()}){
 must(Number.isSafeInteger(human?.maximumWindowMs)&&human.maximumWindowMs>0&&human.maximumWindowMs<=7200000,
  'BOUNDED_HUMAN_RENEWAL_WINDOW_REQUIRED');
 const anchor=micros(r.serverWindowAnchor),applied=micros(r.appliedAt),observed=micros(r.observedAt);
 must(anchor>=micros(human.decidedAt)&&anchor===micros(before.observedAt)&&applied>=anchor&&applied-anchor<=45000000n
  &&observed>=applied&&observed-applied<=45000000n&&observed===micros(after.observedAt)&&utc(r.observedAt)<=now
  &&applied===micros(window.notBefore),'ACTUAL_SERVER_RENEWAL_TIMELINE_REQUIRED');
 const end=anchor+BigInt(human.maximumWindowMs)*1000n,ownerEnd=micros(metadata.expiresAt);
 must(micros(r.edge.expiresAt)===(end<ownerEnd?end:ownerEnd),'EXACT_PREFLIGHT_ANCHORED_EXPIRY_REQUIRED');
 must(Array.isArray(writeResponse)&&writeResponse.length===1,'ACTUAL_RENEWAL_WRITE_RESPONSE_REQUIRED');
 const application=writeResponse[0].renewal_application;
 must(application?.runtimeId===RUNTIME&&application.affectedRows===2&&application.applicationTimestampProvenance==='server-post-commit-observation'
  &&sameTime(application.appliedAt,r.appliedAt)&&sameTime(application.expiresAt,r.edge.expiresAt),
  'ACTUAL_POST_COMMIT_SERVER_APPLICATION_REQUIRED');
 return true;
}
export function validateRenewal(plan,documents,now=Date.now()){
 const {humanRenewalDecision:human,renewalReadback:r,metadata,refresh,accounting,sourcePolicy,independentPolicyReview,renewalPreflightResponse,renewalWriteResponse,renewalReadbackResponse}=documents;
 const controls=plan.controlBindings,window=plan.window;validateTime(now,window);
 must(human?.kind==='direct-human-runtime-renewal-and-export-a7-decision'&&human.approved===true&&human.approvalSource==='direct-user-reply'
  &&human.exactReply==='Approve the exact two-row runtime renewal and export a7 continuation'&&typeof human.questionItemId==='string'&&human.questionItemId.length>=16
  &&human.projectId===PROJECT&&human.runtimeBundleSha256===BUNDLE&&human.runtimeId===RUNTIME
  &&same(human.sourcePolicyBinding,controls.sourcePolicy)&&same(human.independentReviewBinding,controls.independentPolicyReview)
  &&human.operationBundleSha256===plan.renewalOperationBundleSha256&&human.maximumWindowMs>0&&human.maximumWindowMs<=7200000
  &&human.onlyTwoExpiryFieldsMayChange===true&&human.schedulesMustRemainPaused===true&&human.productionAuthorized===false&&human.realBillingAuthorized===false,
  'DIRECT_HUMAN_TWO_ROW_RENEWAL_DECISION_REQUIRED');
 must(sourcePolicy?.kind==='source-only-export-a7-renewal-policy'&&sourcePolicy.sourceImplementationOnly===true&&sourcePolicy.liveExecutionAuthorized===false
  &&sourcePolicy.renewalOperationBundleSha256===plan.renewalOperationBundleSha256&&sourcePolicy.onlyTwoExpiryFieldsMayChange===true
  &&independentPolicyReview?.kind==='independent-export-a7-policy-review'&&independentPolicyReview.passed===true&&independentPolicyReview.sourceOnly===true
  &&independentPolicyReview.liveExecutionAuthorized===false&&same(independentPolicyReview.policyBinding,controls.sourcePolicy)
  &&independentPolicyReview.renewalOperationBundleSha256===plan.renewalOperationBundleSha256,'ACTUAL_REVIEWED_RENEWAL_SOURCE_POLICY_REQUIRED');
 must(r?.kind==='actual-two-row-runtime-expiry-renewal-readback'&&r.actual===true&&r.committed===true&&r.projectId===PROJECT&&r.runtimeId===RUNTIME
  &&same(r.ownerDecisionBinding,controls.humanRenewalDecision)&&same(r.sourcePolicyBinding,controls.sourcePolicy)&&r.operationBundleSha256===plan.renewalOperationBundleSha256
  &&r.affectedRows===2&&r.onlyTwoExpiryFieldsChanged===true&&r.issuedAtUnchanged===true&&r.nonWindowValuesUnchanged===true
  &&r.jobsPaused===true&&r.countersUnchanged===true&&r.secretValuesRead===false&&r.scope?.count===1&&r.edge?.count===1
  &&r.scope.runtimeId===RUNTIME&&r.edge.runtimeId===RUNTIME&&r.scope.tenantId===TENANT&&r.scope.legalEntityId==='caa2bb06-219a-47e9-8132-66d1271b0ffd'
  &&r.scope.branchId==='3813692c-f0de-4c69-8e34-d56cf54695b1'&&sameTime(r.scope.issuedAt,SCOPE_ISSUED)&&sameTime(r.edge.issuedAt,ISSUED)
  &&sameTime(r.scope.oldExpiresAt,SCOPE_OLD_EXPIRY)&&sameTime(r.edge.oldExpiresAt,ORIGINAL_EXPIRY)
  &&r.scope.nonWindowHash===SCOPE_HASH&&r.edge.nonWindowHash===AUTHORITY_HASH&&sameTime(r.edge.expiresAt,window.edgeExpiresAt)&&sameTime(r.scope.expiresAt,window.scopeExpiresAt)
  &&sameTime(r.appliedAt,window.notBefore)&&micros(r.appliedAt)>=micros(human.decidedAt)&&micros(r.observedAt)>=micros(r.appliedAt)
  &&micros(r.observedAt)-micros(r.appliedAt)<=45000000n&&utc(r.observedAt)<=now,'ACTUAL_BOTH_RENEWED_ROWS_AND_PRESERVATION_REQUIRED');
 must(metadata?.kind==='wave5-private-owner-input-metadata'&&metadata.projectId===PROJECT&&metadata.runtimeBundleSha256===BUNDLE
  &&metadata.metadataFilename==='metadata-renewed-a10.json'&&metadata.containsPlaintextCredential===false&&typeof metadata.ownerSid==='string'
  &&micros(metadata.createdAt)>=micros(human.decidedAt)&&utc(metadata.createdAt)<=now&&sameTime(metadata.expiresAt,window.privateExpiresAt)
  &&micros(metadata.expiresAt)>micros(metadata.createdAt)&&micros(metadata.expiresAt)-micros(metadata.createdAt)<=7200000000n
  &&same(metadata.refreshEvidence,controls.refresh),'ACTUAL_FRESH_A10_OWNER_METADATA_REQUIRED');
 must(refresh?.kind==='actual-private-owner-scope-refresh'&&refresh.projectId===PROJECT&&refresh.actualStatus==='ACTIVE_HEALTHY'
  &&refresh.readOnlyOwnerApiCalls===1&&sameTime(refresh.actualVerifiedAt,metadata.createdAt)&&digest(refresh.helperSha256)
  &&refresh.helperSha256===metadata.helperSha256&&refresh.databaseWrites===0&&refresh.authWrites===0&&refresh.settingsChanges===0,
  'ACTUAL_ONE_CHARGED_OWNER_REFRESH_REQUIRED');
 must(accounting?.kind==='conservative-renewed-export-a7-read-accounting'&&accounting.projectId===PROJECT&&accounting.recordedPrior===137
  &&accounting.chargedA10OwnerIdentityReads===1&&accounting.chargedRenewalControlCalls===3&&accounting.otherFinanceCallsSinceDependency===0
  &&accounting.cumulativeChargedPriorCalls===141&&same(accounting.actualA10Refresh,controls.refresh)&&same(accounting.actualRenewalReadback,controls.renewalReadback)
  &&same(accounting.renewalCallAccounting,r.controlCallAccounting),'ACTUAL_CHARGED_137_PLUS_1_PLUS_3_REQUIRED');
 const calls=r.controlCallAccounting;
 must(calls?.attempts===3&&calls.failedAttempts===0&&calls.automaticRetries===0&&calls.receipts?.length===3&&calls.receipts.every((row,i)=>
  row.ordinal===139+i&&row.phase===['preflight','two-row-expiry-write','readback'][i]&&row.successful===true&&digest(row.responseSha256))
  &&calls.receipts[0].responseSha256===controls.renewalPreflightResponse.sha256&&calls.receipts[1].responseSha256===controls.renewalWriteResponse.sha256
  &&calls.receipts[2].responseSha256===controls.renewalReadbackResponse.sha256,
  'THREE_ACTUAL_RENEWAL_RECEIPTS_AND_RAW_BINDINGS_REQUIRED');
 const before=snapshotOf(renewalPreflightResponse),after=snapshotOf(renewalReadbackResponse);
 validateRenewalTimeline({readback:r,human,metadata,before,after,writeResponse:renewalWriteResponse,window,now});
 must(sameTime(before.observedAt,r.serverWindowAnchor)&&micros(before.observedAt)>=micros(human.decidedAt)
  &&micros(before.observedAt)<=micros(r.appliedAt)&&micros(r.appliedAt)-micros(before.observedAt)<=45000000n
  &&sameTime(after.observedAt,r.observedAt)&&before.migrationCount===115&&after.migrationCount===115
  &&before.apiFunctionCount===363&&after.apiFunctionCount===363&&before.authority?.runtimeId===RUNTIME&&after.authority?.runtimeId===RUNTIME
  &&before.authority.enabled===true&&after.authority.enabled===true&&same(before.authority.jobIds,[4,5,6])&&same(after.authority.jobIds,[4,5,6])
  &&sameTime(before.authority.issuedAt,ISSUED)&&sameTime(after.authority.issuedAt,ISSUED)&&sameTime(before.authority.expiresAt,ORIGINAL_EXPIRY)
  &&sameTime(after.authority.expiresAt,window.edgeExpiresAt)&&before.authority.nonWindowHash===AUTHORITY_HASH&&after.authority.nonWindowHash===AUTHORITY_HASH
  &&before.scopeCount===1&&after.scopeCount===1&&before.scopeNonWindowHash===SCOPE_HASH&&after.scopeNonWindowHash===SCOPE_HASH
  &&before.scope.enabled===true&&after.scope.enabled===true&&sameTime(before.scope.issuedAt,SCOPE_ISSUED)&&sameTime(after.scope.issuedAt,SCOPE_ISSUED)
  &&sameTime(before.scope.expiresAt,SCOPE_OLD_EXPIRY)&&sameTime(after.scope.expiresAt,window.scopeExpiresAt)
  &&[before,after].every(v=>v.scope.tenantId===TENANT&&v.scope.legalEntityId==='caa2bb06-219a-47e9-8132-66d1271b0ffd'&&v.scope.branchId==='3813692c-f0de-4c69-8e34-d56cf54695b1'
   &&same(v.ownJobs,JOBS.map(job=>({...job,active:false})))&&v.outsideJobHash===OUTSIDE_HASH&&v.ticks===0&&v.modelInvocations===0&&v.recordedCronRuns===24
   &&v.containsUnexpected24HourFunctionCeiling===false&&same(v.guardFunctionBindings,documents.renewalProposal.exactGuardFunctionBindings))
  &&same(before.keyReferences,after.keyReferences)&&same(before.tableContracts,after.tableContracts)&&after.scopeAllowed===true,
  'ACTUAL_RAW_RENEWAL_ROWS_GUARDS_COUNTERS_REQUIRED');return {before,after};
}

export function validatePlan(plan,documents,now=Date.now()){
 must(plan?.kind==='source-bound-renewed-three-job-schedule-resume-plan'&&plan.projectId===PROJECT&&plan.runtimeBundleSha256===BUNDLE&&plan.runtimeId===RUNTIME
  &&plan.sourceBinding?.path===SOURCE&&digest(plan.sourceBinding.sha256)&&same(plan.jobIds,[4,5,6])&&same(plan.budget,BUDGET)
  &&digest(plan.renewalOperationBundleSha256)&&plan.originalAuthorityIssuedAt===ISSUED&&plan.originalAuthorityExpiresAt===ORIGINAL_EXPIRY
  &&plan.originalScopeIssuedAt===SCOPE_ISSUED&&plan.originalScopeExpiresAt===SCOPE_OLD_EXPIRY&&plan.countersReset===false&&plan.oldA4IntentReused===false
  &&plan.newJobs===0&&plan.personalHumanExactSourceSignatureClaimed===false&&plan.crossUtcDayPermittedOnlyInNewWindow===true,
  'EXACT_NEW_RENEWED_SCHEDULE_PLAN_REQUIRED');
 validateTime(now,plan.window);validateFingerprints(plan.guardFingerprints);validateReadinessTick(plan.readinessTick);
 must(same(plan.controlBindings?.renewalProposal,RENEWAL_PROPOSAL)&&same(plan.controlBindings.callInventory,CALL_INVENTORY)
  &&Object.entries(FIXED_CONTROLS).every(([key,file])=>plan.controlBindings[key]?.path===file&&digest(plan.controlBindings[key].sha256))
  &&['renewalPreflightResponse','renewalWriteResponse','renewalReadbackResponse','completedExports','humanScheduleDecision'].every(key=>receipt(plan.controlBindings[key])&&publicPath(plan.controlBindings[key].path)),
  'EXACT_RENEWED_PUBLIC_CONTROL_BINDINGS_REQUIRED');
 validateCallInventory(documents.callInventory);
 validateRenewal(plan,documents,now);validateExportsProof(documents.completedExports);
 must(documents.exportsPlan?.kind==='source-bound-renewed-export-a7-preparation'&&documents.completedExports.planSha256===plan.controlBindings.exportsPlan.sha256
  &&sameTime(documents.exportsPlan.window?.notBefore,plan.window.notBefore)&&sameTime(documents.exportsPlan.window.expiresAt,plan.window.expiresAt)
  &&documents.exportsPlan.priorConservativeBound===141&&documents.exportsPlan.ordinaryLimit===165&&documents.exportsPlan.cumulativeLimit===166,
  'ACTUAL_COMPLETED_RENEWED_EXPORT_PLAN_REQUIRED');
 validateProviderAuthority(documents.providerAuthorityReview,{binding:plan.controlBindings.providerAuthorityReview,fingerprints:plan.guardFingerprints,
  healthResult:documents.healthResult,healthEvidence:documents.healthEvidence,window:plan.window,now});
 must(same(plan.readinessTick,documents.providerAuthorityReview.readinessTick)&&plan.readSqlSha256===sha(READ_SQL)
  &&plan.writeSqlSha256===sha(buildResumeSql(plan.guardFingerprints,plan.readinessTick,plan.window)),'EXACT_RENEWED_SQL_INVENTORY_REQUIRED');return plan;
}
export function validateFinalReview(review,{plan,planSha256,sourceSha256,documents,now=Date.now()}={}){
 validatePlan(plan,documents,now);
 must(review?.kind==='independent-exact-renewed-three-job-schedule-resume-operation-review'&&review.technicalDecision==='approve'
  &&review.executionPermitted===true&&review.independentlyReviewed===true&&review.controlledFixture===false&&review.projectId===PROJECT&&review.runtimeBundleSha256===BUNDLE
  &&review.runtimeId===RUNTIME&&same(schedulePlanBinding(review),{path:PLAN,sha256:planSha256})&&same(review.sourceBinding,{path:SOURCE,sha256:sourceSha256})
  &&same(review.sourceBinding,plan.sourceBinding)&&same(review.window,plan.window)&&same(review.budget,BUDGET)&&review.maximumManagementAttempts===3
  &&review.separateScheduleResumeDecision===true&&review.personalHumanExactSourceSignatureClaimed===false&&review.currentOwnerSidVerifiedByPrivateAdapter===true
  &&review.ownerSid===documents.metadata.ownerSid&&review.exportsCompletedFirst===true&&review.actualDeployedHealthVerified===true
  &&review.oldA4IntentReused===false&&review.countersReset===false&&review.automaticRetries===0&&review.newUsers===0&&review.newPermissions===0
  &&review.newSecrets===0&&review.newDestinations===0&&review.newJobs===0&&review.runtimeExpiryChangedByThisHelper===false
  &&review.privateAdapter?.path===PRIVATE_ADAPTER&&digest(review.privateAdapter.afterSha256),
  'ACTUAL_INDEPENDENT_RENEWED_SCHEDULE_OPERATION_REVIEW_REQUIRED');
 validateConditionalSchedulerDecision(documents.humanScheduleDecision,{plan,documents,now});return review;
}

// One genuine reply may conditionally authorize the later resume. It does not
// purport to approve timestamps or receipts that did not yet exist. The normal
// final review above still validates the complete ACTUAL plan and evidence.
export function conditionalSchedulerScope(plan){
 return {sourceBinding:plan.sourceBinding,operationBundleSha256:plan.renewalOperationBundleSha256,jobIds:[4,5,6],budget:BUDGET,
  maximumWindowMs:7200000,windowRule:WINDOW_RULE,preconditions:PRECONDITIONS};
}
export function validateConditionalSchedulerDecision(human,{plan,documents,now=Date.now()}={}){
 validateTime(now,plan?.window);
 const controls=plan.controlBindings,owner=documents.humanRenewalDecision,health=documents.humanHealthDecision;
 const scope=conditionalSchedulerScope(plan),policy=documents.sourcePolicy,policyReview=documents.independentPolicyReview;
 must(receipt(plan.sourceBinding)&&plan.sourceBinding.path===SOURCE&&digest(plan.renewalOperationBundleSha256)
  &&controls.humanScheduleDecision?.path===SCHEDULE_DECISION&&receipt(controls.humanScheduleDecision)
  &&controls.humanHealthDecision?.path===HEALTH_DECISION&&receipt(controls.humanHealthDecision),
  'EXACT_CONDITIONAL_SCHEDULER_SOURCE_AND_DECISION_BINDINGS_REQUIRED');
 must(policy?.sourceImplementationOnly===true&&policy.liveExecutionAuthorized===false&&policy.executionPermitted===false
  &&policyReview?.sourceOnly===true&&policyReview.passed===true&&policyReview.liveExecutionAuthorized===false&&policyReview.executionPermitted===false
  &&same(policyReview.policyBinding,controls.sourcePolicy)&&same(policy.conditionalSchedulerAuthority,scope)
  &&same(policyReview.conditionalSchedulerAuthority,scope),'EXACT_REVIEWED_CONDITIONAL_SCHEDULER_SCOPE_REQUIRED');
 must(human?.kind==='direct-human-conditional-renewed-three-job-schedule-resume-decision'&&human.approved===true
  &&human.approvalSource==='direct-user-reply'&&human.exactReply===SCHEDULE_REPLY&&typeof human.questionItemId==='string'&&human.questionItemId.length>=16
  &&human.projectId===PROJECT&&human.runtimeBundleSha256===BUNDLE&&human.runtimeId===RUNTIME&&human.conditionalPreapproval===true
  &&human.scheduleResumeAuthorizedByThisDecision===true&&same(human.sourceBinding,plan.sourceBinding)
  &&human.operationBundleSha256===plan.renewalOperationBundleSha256&&same(human.budget,BUDGET)&&same(human.jobIds,[4,5,6])
  &&human.maximumWindowMs===7200000&&same(human.windowRule,WINDOW_RULE)&&same(human.preconditions,PRECONDITIONS)
  &&human.maximumManagementAttempts===3&&human.maximumWorkerRequests===4320&&human.independentFinalOperationReviewRequired===true
  &&human.personalHumanExactWindowSignatureClaimed===false&&!Object.hasOwn(human,'window')
  &&human.productionAuthorized===false&&human.realBillingAuthorized===false
  &&same(human.renewalOwnerDecisionBinding,controls.humanRenewalDecision)&&same(human.healthOperationDecisionBinding,controls.humanHealthDecision)
  &&same(human.sourcePolicyBinding,controls.sourcePolicy)&&same(human.independentReviewBinding,controls.independentPolicyReview),
  'EXPLICIT_CONDITIONAL_DIRECT_HUMAN_SCHEDULER_DECISION_REQUIRED');
 const sameReply=record=>record?.approved===true&&record.approvalSource==='direct-user-reply'&&record.exactReply===human.exactReply
  &&record.questionItemId===human.questionItemId&&record.decidedAt===human.decidedAt&&record.projectId===PROJECT&&record.runtimeId===RUNTIME
  &&record.runtimeBundleSha256===BUNDLE&&record.operationBundleSha256===human.operationBundleSha256
  &&record.productionAuthorized===false&&record.realBillingAuthorized===false;
 must(owner?.kind==='direct-human-runtime-renewal-and-export-a7-decision'&&sameReply(owner)&&owner.maximumWindowMs===7200000
  &&same(owner.sourcePolicyBinding,controls.sourcePolicy)&&same(owner.independentReviewBinding,controls.independentPolicyReview)
  &&health?.kind==='direct-human-renewed-health-scheduler-decision'&&sameReply(health)
  &&health.healthInvocationAuthorized===true&&health.maximumHealthInvocations===1&&health.maximumHealthManagementAttempts===5
  &&health.overallCumulativeMaximum===174&&health.maximumScheduleRequests===4320&&health.healthKeepsSchedulesPaused===true
  &&same(health.sourcePolicyBinding,controls.sourcePolicy)&&same(health.independentReviewBinding,controls.independentPolicyReview),
  'SAME_GENUINE_OWNER_HEALTH_AND_REVIEWED_SCOPE_REQUIRED');
 const r=documents.renewalReadback,metadata=documents.metadata,anchor=micros(r.serverWindowAnchor),applied=micros(r.appliedAt);
 must(micros(human.decidedAt)<=anchor&&anchor<=applied&&applied===micros(plan.window.notBefore)&&utc(human.decidedAt)<=now
  &&sameTime(r.preflightObservedAt,r.serverWindowAnchor)&&sameTime(r.serverExpiryAnchor,r.serverWindowAnchor)
  &&r.applicationTimestampProvenance==='server-post-commit-observation'&&r.actualCumulativeChargedCalls===141
  &&micros(metadata.createdAt)>=micros(human.decidedAt)&&micros(metadata.createdAt)<=anchor,
  'ACTUAL_CONDITIONAL_PREAPPROVAL_BEFORE_RENEWAL_TIMELINE_REQUIRED');
 const ceiling=anchor+7200000000n,ownerExpiry=micros(metadata.expiresAt),expiry=ceiling<ownerExpiry?ceiling:ownerExpiry;
 must(micros(plan.window.edgeExpiresAt)===expiry&&micros(plan.window.scopeExpiresAt)===expiry&&micros(plan.window.expiresAt)===expiry
  &&micros(plan.window.privateExpiresAt)===ownerExpiry,'ACTUAL_CONDITIONAL_WINDOW_RULE_REQUIRED');
 return human;
}

export function validateSnapshot(value,{plan,active=false,now=Date.now(),before}={}){
 validateTime(now,plan.window);assertRenewedRows(value,plan.window);
 must(utc(value.observedAt)>=utc(plan.window.notBefore)&&utc(value.observedAt)<=now+1000&&now-utc(value.observedAt)<60000&&utc(value.observedAt)<utc(plan.window.expiresAt)
  &&value.scopeAllowed===true&&value.migrationCount===115&&value.apiFunctionCount===363&&value.serviceRoleRpcGrants===true&&value.completedOriginalExports===true
  &&value.authority.runtimeId===RUNTIME&&value.outsideJobHash===OUTSIDE_HASH&&same(value.guardFingerprints,plan.guardFingerprints)
  &&same(value.ownJobs,JOBS.map(job=>({...job,active})))&&value.recordedCronRuns===24
  &&value.recordedCronRuns+1+3*Math.ceil((utc(plan.window.edgeExpiresAt)-utc(value.observedAt))/60000)<=4320,
  'EXACT_FRESH_RENEWED_SCHEDULE_STATE_REQUIRED');
 must(value.ticks===1&&value.tickOutcomes===1&&same(value.readinessTicks,[{...plan.readinessTick,success:true,summary:{count:1,states:['collected']}}])
  &&Object.keys(zero).every(key=>value[key]===0),'EXACT_BOUND_HEALTH_ONLY_EFFECTS_REQUIRED');
 if(before)must(same(before.authority,value.authority)&&same(before.scopes,value.scopes)&&same(before.guardFingerprints,value.guardFingerprints)
  &&before.outsideJobHash===value.outsideJobHash&&before.recordedCronRuns===value.recordedCronRuns,'UNCHANGED_RENEWED_AUTHORITY_AND_COUNTERS_REQUIRED');return value;
}

export function createScheduleTransport(token,{writeSql,window,requestFactory=https.request,now=Date.now}={}){
 must(typeof token==='string'&&token.length>=9&&token.length<=2048&&!/\s/.test(token),'PRIVATE_OWNER_TOKEN_REQUIRED');validateWindow(window);
 must(typeof writeSql==='string'&&writeSql.startsWith('BEGIN;\nSET LOCAL standard_conforming_strings=on;'),'EXACT_RENEWED_WRITE_REQUIRED');
 let attempts=0;
 return async(sql,readOnly)=>{
  validateTime(now(),window);must(attempts<3,'THREE_SCHEDULE_MANAGEMENT_ATTEMPTS_ONLY');
  must((attempts===1&&readOnly===false&&sql===writeSql)||((attempts===0||attempts===2)&&readOnly===true&&sql===READ_SQL),
   'EXACT_ORDERED_SCHEDULE_QUERY_REQUIRED');attempts++;
  const body=JSON.stringify({query:sql,read_only:readOnly});
  return new Promise((resolve,reject)=>{let req,timer,settled=false,sent=false,size=0;const chunks=[];
   const fail=code=>{if(settled)return;settled=true;clearTimeout(timer);req?.destroy();const e=Error(code);e.publicCode=code;e.sent=sent;reject(e);};
   try{req=requestFactory(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,{method:'POST',rejectUnauthorized:true,
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}},res=>{
     res.on('error',()=>fail('SCHEDULE_RESPONSE_UNCERTAIN'));res.on('data',chunk=>{if(settled)return;size+=chunk.length;
      if(size>1048576)fail('SCHEDULE_RESPONSE_LIMIT');else chunks.push(chunk);});
     res.on('end',()=>{if(settled)return;settled=true;clearTimeout(timer);resolve({status:res.statusCode,raw:Buffer.concat(chunks)});});});
    req.on('error',()=>fail('SCHEDULE_TRANSPORT_UNCERTAIN'));
    timer=setTimeout(()=>fail('SCHEDULE_TIMEOUT_UNCERTAIN'),Math.min(45000,utc(window.expiresAt)-now()));
    req.once('socket',socket=>{const send=()=>{if(settled)return;try{validateTime(now(),window);}catch{return fail('RENEWED_SCHEDULE_WINDOW_EXPIRED');}
     if(socket.encrypted!==true||socket.authorized!==true)return fail('VERIFIED_SCHEDULE_TLS_REQUIRED');sent=true;req.end(body);};
     if(socket.authorized===true)send();else socket.once('secureConnect',send);});
   }catch{fail('SCHEDULE_REQUEST_FAILED');}
  });
 };
}
export async function runScheduleResume({plan,transport,persist,once,validatePublicGate,now=Date.now()}={}){
 validateTime(now(),plan?.window);must(typeof validatePublicGate==='function','PUBLIC_GATE_RECHECK_REQUIRED');
 const writeSql=buildResumeSql(plan.guardFingerprints,plan.readinessTick,plan.window);let attempts=0,mutationAttempted=false,phase='public-preflight',before;
 await validatePublicGate();validateTime(now(),plan.window);
 phase='once-intent';must(receipt(await once({kind:'exclusive-renewed-v7-three-job-resume-once',projectId:PROJECT,runtimeBundleSha256:BUNDLE,
  runtimeId:RUNTIME,actualStartedAt:new Date(now()).toISOString(),jobIds:[4,5,6],window:plan.window,budget:BUDGET,
  originalAuthorityExpiresAt:ORIGINAL_EXPIRY,originalScopeExpiresAt:SCOPE_OLD_EXPIRY,readSqlSha256:sha(READ_SQL),writeSqlSha256:sha(writeSql),
  readinessTick:plan.readinessTick,oldA4IntentReused:false,countersReset:false,automaticRetry:false})),'DURABLE_EXCLUSIVE_NEW_RESUME_INTENT_REQUIRED');
 async function capture(file,sql,readOnly){
  validateTime(now(),plan.window);must(attempts<3,'THREE_SCHEDULE_MANAGEMENT_ATTEMPTS_ONLY');
  must(receipt(await persist(file+'-attempt.json',{attempt:attempts+1,maximumCumulativeManagementOrdinal:171+attempts+1,
   readOnly,sqlSha256:sha(sql),actualAttemptAt:new Date(now()).toISOString()})),'DURABLE_SCHEDULE_ATTEMPT_REQUIRED');
  validateTime(now(),plan.window);attempts++;if(!readOnly)mutationAttempted=true;
  const response=await transport(sql,readOnly);
  must(receipt(await persist(file+'-response.json',{httpStatus:response.status,responseSha256:sha(response.raw),rawErrorPrinted:false})),
   'DURABLE_SCHEDULE_RESPONSE_REQUIRED');
  must([200,201].includes(response.status),'SCHEDULE_HTTP_FAILURE');return response;
 }
 async function read(file){const response=await capture(file,READ_SQL,true);let rows;try{rows=JSON.parse(response.raw);}catch{must(false,'SCHEDULE_READ_INVALID');}
  must(Array.isArray(rows)&&rows.length===1&&rows[0].snapshot,'ONE_SCHEDULE_STATE_ROW_REQUIRED');
  must(receipt(await persist(file+'-state.json',rows[0].snapshot)),'DURABLE_SCHEDULE_STATE_REQUIRED');return rows[0].snapshot;}
 try{
  phase='fresh-preflight';before=validateSnapshot(await read('00-before'),{plan,now:now()});
  phase='write-intent';await validatePublicGate();validateTime(now(),plan.window);
  must(receipt(await persist('01-write-intent.json',{writeSqlSha256:sha(writeSql),jobIds:[4,5,6],window:plan.window,budget:BUDGET,
   actualIntentAt:new Date(now()).toISOString(),changesOnlyThreeExistingJobActiveFlags:true})),'DURABLE_WRITE_INTENT_REQUIRED');
  phase='exact-resume';let uncertain=null;
  try{await capture('02-write',writeSql,false);}catch(error){if(!mutationAttempted)throw error;uncertain=error.publicCode??'SCHEDULE_WRITE_OUTCOME_UNCERTAIN';}
  phase='actual-readback';const after=validateSnapshot(await read('03-after'),{plan,active:true,now:now(),before});
  const result={kind:'actual-exact-renewed-v7-three-job-schedule-resume-result',passed:true,projectId:PROJECT,runtimeBundleSha256:BUNDLE,runtimeId:RUNTIME,
   jobIds:[4,5,6],ownJobs:after.ownJobs,authority:after.authority,scopes:after.scopes,window:plan.window,budget:BUDGET,
   managementAttempts:attempts,maximumCumulativeManagementBound:171+attempts,writeResponseUncertain:uncertain,enabledStateConfirmedByReadback:true,
   originalAuthorityExpiresAt:ORIGINAL_EXPIRY,originalScopeExpiresAt:SCOPE_OLD_EXPIRY,existingJobsAndAuthorityPreserved:true,countersReset:false,automaticRetry:false,
   scheduledRequestsAlreadyObserved:24,readinessRequestsCharged:1,cumulativeReviewedWorkerRequests:25,maximumScheduleRequestsOriginal:4320,
   readinessTick:plan.readinessTick,actualDelivery:false,actualTrustedModelUsage:false,nativeAccepted:false,targetScaleLoad:false,productionReleaseReady:false};
  must(receipt(await persist('99-result.json',result)),'DURABLE_RESUME_RESULT_REQUIRED');return result;
 }catch(error){await persist('99-stop.json',{passed:false,phase,failureCode:error.publicCode??'SCHEDULE_RESUME_STOP',actualStoppedAt:new Date(now()).toISOString(),
  mutationMayBeCommitted:mutationAttempted,managementAttempts:attempts,automaticRetry:false,secretsPrinted:false});throw error;}
}

export async function exactFile(relative,expected,{workspace=root}={}){
 must(publicPath(relative)&&digest(expected),'PUBLIC_SCHEDULE_BINDING_REQUIRED');
 const target=path.resolve(workspace,relative),real=await fs.realpath(target),stat=await fs.lstat(target);
 must(real===target&&stat.isFile()&&!stat.isSymbolicLink()&&stat.size<=8388608,'EXACT_PUBLIC_REGULAR_FILE_REQUIRED');
 const bytes=await fs.readFile(target);must(bytes.length<=8388608&&sha(bytes)===expected,'SCHEDULE_SOURCE_OR_EVIDENCE_CHANGED');return bytes;
}
export async function validatePreservedSources({workspace=root}={}){
 for(const binding of PRESERVED)await exactFile(binding.path,binding.sha256,{workspace});
 const archived=await validateDeployedArchive({workspace});
 const original=await validateOriginalSources({workspace:path.join(workspace,DEPLOYED_ARCHIVE)});return {...original,preservedBindings:PRESERVED.length,
  deployedArchiveBindings:archived.bindings.length,currentProductCandidate:archived.currentProductCandidate,
  candidateDiffersFromDeployed:true,originalExpiryStillImmutable:ORIGINAL_EXPIRY,newRenewalRequired:true,actualResumeAllowed:false};
}
export async function validateDeployedArchive({workspace=root}={}){
 const manifest=JSON.parse(await exactFile(ARCHIVE_MANIFEST.path,ARCHIVE_MANIFEST.sha256,{workspace}));
 must(manifest?.kind==='exact-deployed-v7-source-archive'&&manifest.archiveRoot===DEPLOYED_ARCHIVE&&manifest.codeExecutedFromArchive===false
  &&manifest.originalFilesOverwritten===false&&manifest.sourceOnlyArchiveDoesNotAuthorizeExecution===true&&manifest.entries?.length===39,
  'EXACT_SOURCE_ONLY_DEPLOYED_ARCHIVE_REQUIRED');
 const bindings=manifest.entries.map(row=>{must(row.path===DEPLOYED_ARCHIVE+row.originalPath&&publicPath(row.path),'EXACT_ARCHIVED_RELATIVE_SOURCE_REQUIRED');
  return {path:row.path,sha256:row.sha256};});
 for(const item of bindings)await exactFile(item.path,item.sha256,{workspace});
 const currentProductCandidate={path:manifest.currentProductCandidate.path,sha256:manifest.currentProductCandidate.sha256};
 must(currentProductCandidate.path==='workers/wave5/model_runtime.mjs'&&manifest.currentProductCandidate.deployedSha256==='fce748e511a81bdae957ff76275641142a738d8391132953d4d3c7eec03cfb99'
  &&currentProductCandidate.sha256==='7776efd148c1257c4cd78eba3345b13fe19406012cd4b58f7b0a6769ef77a72e'&&manifest.currentProductCandidate.installedByThisArchive===false,
  'EXACT_CHANGED_PRODUCT_CANDIDATE_SEPARATE_FROM_DEPLOYED_REQUIRED');
 await exactFile(currentProductCandidate.path,currentProductCandidate.sha256,{workspace});return {bindings,currentProductCandidate};
}
export async function loadPublicGate(reviewSha256,{workspace=root,now=Date.now()}={}){
 must(digest(reviewSha256),'PINNED_EXACT_SCHEDULE_OPERATION_REVIEW_SHA_REQUIRED');
 // Everything below is public source/evidence reading. No credential, stdin,
 // filesystem mutation, intent, socket or private folder access occurs here.
 const review=JSON.parse(await exactFile(REVIEW,reviewSha256,{workspace}));
 const planBinding=schedulePlanBinding(review);
 const planBytes=await exactFile(PLAN,planBinding.sha256,{workspace}),plan=JSON.parse(planBytes);
 validateTime(now,plan.window);await validatePreservedSources({workspace});
 const documents={};must(plan.controlBindings&&typeof plan.controlBindings==='object','PUBLIC_CONTROL_INVENTORY_REQUIRED');
 for(const [name,binding] of Object.entries(plan.controlBindings))documents[name]=JSON.parse(await exactFile(binding?.path,binding?.sha256,{workspace}));
 const provider=documents.providerAuthorityReview;must(provider&&Array.isArray(provider.evidenceBindings),'ACTUAL_PROVIDER_REVIEW_REQUIRED');
 for(const [name,key] of [['healthResult','actualHealthResultBinding'],['healthBefore','actualBeforeStateBinding'],['healthDispatch','actualDispatchBinding'],['healthAfter','actualAfterStateBinding']])
  documents[name]=JSON.parse(await exactFile(provider[key]?.path,provider[key]?.sha256,{workspace}));
 documents.healthEvidence={before:documents.healthBefore,dispatch:documents.healthDispatch,after:documents.healthAfter};
 const sourceSha256=sha(await fs.readFile(path.join(workspace,SOURCE)));
 validateFinalReview(review,{plan,planSha256:sha(planBytes),sourceSha256,documents,now});
 const archived=await validateDeployedArchive({workspace});
 const inputs=uniqueBindings([...PRESERVED,...archived.bindings,archived.currentProductCandidate,{path:SOURCE,sha256:sourceSha256},
  ...Object.values(plan.controlBindings),...provider.evidenceBindings,{path:PRIVATE_ADAPTER,sha256:review.privateAdapter.afterSha256}]);
 const locks=validateLockInventory(plan,inputs);
 if(plan.sourceAndEvidenceBindings!==undefined)must(same(uniqueBindings(plan.sourceAndEvidenceBindings).sort((a,b)=>a.path.localeCompare(b.path)),
  [...locks].sort((a,b)=>a.path.localeCompare(b.path))),'EXACT_PLAN_SOURCE_EVIDENCE_ALIAS_REQUIRED');
 const required=uniqueBindings([...inputs,planBinding]);
 must(Array.isArray(review.sourceAndEvidenceBindings)&&review.sourceAndEvidenceBindings.every(binding=>receipt(binding)&&publicPath(binding.path))
  &&new Set(review.sourceAndEvidenceBindings.map(binding=>binding.path)).size===review.sourceAndEvidenceBindings.length
  &&required.length===review.sourceAndEvidenceBindings.length&&required.every(binding=>review.sourceAndEvidenceBindings.some(row=>same(row,binding))),
  'ALL_EXACT_SOURCE_AND_ACTUAL_EVIDENCE_BINDINGS_REQUIRED');
 for(const binding of review.sourceAndEvidenceBindings)await exactFile(binding.path,binding.sha256,{workspace});
 validateTime(now,plan.window);return {plan,review,documents,reviewSha256,planSha256:sha(planBytes)};
}
async function save(directory,file,value){
 const relative=path.posix.join(directory,file),target=path.resolve(root,relative);must(publicPath(relative)&&target.startsWith(path.resolve(root)+path.sep),'PUBLIC_RESUME_OUTPUT_REQUIRED');
 const bytes=Buffer.from(JSON.stringify(value,null,2)+'\n'),handle=await fs.open(target,'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}return {path:relative,sha256:sha(bytes)};
}
export async function main(argv=process.argv.slice(2),{stdin=process.stdin,stdout=process.stdout,now=Date.now,
 publicGate=loadPublicGate,sourceGate=validatePreservedSources,run=runScheduleResume,requestFactory=https.request,stdinTimeoutMs=15000}={}){
 must((argv.length===1&&argv[0]==='--validate')||(argv.length===2&&['--preflight','--execute'].includes(argv[0])),'EXACT_SCHEDULE_RESUME_MODE_REQUIRED');
 if(argv[0]==='--validate'){const value=await sourceGate();stdout.write(JSON.stringify({...value,sourceOnly:true,privateInputsRead:false,networkCalls:0,intentsCreated:0})+'\n');return value;}
 must(digest(argv[1]),'PINNED_EXACT_SCHEDULE_OPERATION_REVIEW_SHA_REQUIRED');
 let verified=await publicGate(argv[1],{now:now()});
 if(argv[0]==='--preflight'){const value={passed:true,networkCalls:0,privateInputsRead:false,planSha256:verified.planSha256,finalReviewSha256:argv[1]};
  must(digest(value.planSha256),'EXACT_PREFLIGHT_PLAN_DIGEST_REQUIRED');stdout.write(JSON.stringify(value)+'\n');return value;}
 must(Number.isSafeInteger(stdinTimeoutMs)&&stdinTimeoutMs>0&&stdinTimeoutMs<=15000,'BOUNDED_PRIVATE_INPUT_TIMEOUT_REQUIRED');
 let incoming='',cfg,timer;
 try{
  await Promise.race([(async()=>{for await(const chunk of stdin){validateTime(now(),verified.plan.window);incoming+=chunk;must(Buffer.byteLength(incoming)<=8192,'PRIVATE_INPUT_LIMIT');}})(),
   new Promise((_,reject)=>{timer=setTimeout(()=>{stdin.destroy?.();const e=Error('PRIVATE_INPUT_TIMEOUT');e.publicCode='PRIVATE_INPUT_TIMEOUT';reject(e);},stdinTimeoutMs);})]);
  clearTimeout(timer);
  validateTime(now(),verified.plan.window);try{cfg=JSON.parse(incoming);}catch{must(false,'EXACT_MANAGEMENT_ONLY_INPUT_REQUIRED');}incoming='';
  must(exact(cfg,['projectId','bundleSha256','ownerToken'])&&cfg.projectId===PROJECT&&cfg.bundleSha256===BUNDLE,'EXACT_MANAGEMENT_ONLY_INPUT_REQUIRED');
  verified=await publicGate(argv[1],{now:now()});validateTime(now(),verified.plan.window);
  const directory='docs/verification/wave5/task3-schedule-resume-20261017/actual-conditional-a2-'+now()+'/';
  const transport=createScheduleTransport(cfg.ownerToken,{writeSql:buildResumeSql(verified.plan.guardFingerprints,verified.plan.readinessTick,verified.plan.window),
   window:verified.plan.window,now,requestFactory});
  // Directory and exclusive intent are created only after both complete public
  // gates. A public hash change before the write is checked again by the core.
  await fs.mkdir(path.join(root,directory));
  const result=await run({plan:verified.plan,transport,now,validatePublicGate:()=>publicGate(argv[1],{now:now()}),
   once:value=>save('',ONCE,{...value,finalReviewSha256:argv[1],completedExportsBinding:verified.plan.controlBindings.completedExports,directory}),
   persist:(file,value)=>save(directory,file,value)});
  stdout.write(JSON.stringify({passed:true,evidencePath:directory+'99-result.json',managementAttempts:result.managementAttempts,actualDelivery:false})+'\n');return result;
 }finally{clearTimeout(timer);if(cfg)cfg.ownerToken=null;incoming='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'SCHEDULE_RESUME_STOP',secretsPrinted:false})+'\n');process.exitCode=1;});
