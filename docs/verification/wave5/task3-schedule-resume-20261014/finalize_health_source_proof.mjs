import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {SOURCE,PRESERVED,READ_SQL,GUARDS,JOBS,EXPIRES,ISSUED,PROJECT,BUNDLE,REVIEW,PROVIDER_REVIEW,ONCE,
 buildResumeSql,validatePreservedSources} from '../../../../tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const folder='docs/verification/wave5/task3-schedule-resume-20261014/';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const bindings=new Map();
async function read(file,expected){const bytes=await fs.readFile(path.join(root,file));const binding={path:file,sha256:hash(bytes),bytes:bytes.length};
 if(expected)assert.equal(binding.sha256,expected,'input drift: '+file);
 if(bindings.has(file))assert.deepEqual(binding,bindings.get(file));else bindings.set(file,binding);return bytes;}
const json=async(file,expected)=>JSON.parse(await read(file,expected));
async function write(file,value){assert.ok(file.startsWith(folder));const bytes=Buffer.from(typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
 await fs.writeFile(path.join(root,file),bytes,{flag:'wx'});return {path:file,sha256:hash(bytes),bytes:bytes.length};}
const before=await json(folder+'health-a3-source-before.json');
assert.equal(before.length,3);for(const binding of before)await read(binding.path,binding.sha256);
const exit=await json(folder+'health-a3-exit.json');assert.equal(exit.exitCode,0);
const log=(await read(folder+'controlled-verification-health-a3.tap')).toString();
const counts={};for(const field of ['tests','pass','fail','cancelled','skipped','todo'])counts[field]=Number(new RegExp(`^# ${field} (\\d+)\\r?$`,'m').exec(log)?.[1]??NaN);
assert.deepEqual(counts,{tests:30,pass:30,fail:0,cancelled:0,skipped:0,todo:0});
const identities=[...log.matchAll(/^(ok|not ok) (\d+) - (.*?)\r?$/gm)].map(match=>({status:match[1],index:Number(match[2]),name:match[3]}));
assert.equal(identities.length,30);assert.ok(identities.every(row=>row.status==='ok'));
const testSource=(await read(folder+'resume_worker_schedules_health.test.mjs')).toString();
assert.deepEqual([...testSource.matchAll(/\btest\('([^']+)'/g)].map(match=>match[1]).sort(),identities.map(row=>row.name).sort());
const offline=await json(folder+'health-a3-offline-checks.json');
assert.equal(offline.syntax.exitCode,0);assert.equal(offline.offlineValidation.exitCode,0);
const validation=JSON.parse(offline.offlineValidation.output);assert.equal(validation.privateInputsRead,false);assert.equal(validation.networkCalls,0);
assert.equal(validation.originalExpiry,EXPIRES);assert.equal(validation.actualResumeAllowed,false);assert.equal(validation.originalAuthorityCurrentlyUnexpired,false);
assert.equal(offline.expiredExecute.exitCode,1);assert.equal(offline.expiredExecute.stdinSupplied,false);
assert.equal(JSON.parse(offline.expiredExecute.output).failureCode,'ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED');
assert.equal((await validatePreservedSources()).passed,true);
for(const binding of PRESERVED)await read(binding.path,binding.sha256);
const mapping=await json(PRESERVED[8].path,PRESERVED[8].sha256);
for(const binding of [...mapping.evidence,...mapping.sources])await read(binding.path,binding.sha256);

const previous=await json(folder+'source-proof-a2.json','762762cf7e70a9f108f34320f2886b6afd7c5e5ee0cbc79fc62618899df5ba21');
await read(folder+'source-proof-a2.md','bd1c495cde78b668f0672fbd234ea4b0a076d6d64ae1fecfa1e1e46186050e66');
await read(folder+'helper-before-health-gate.mjs',previous.source.sha256);
await read(folder+'test-before-health-gate.mjs',previous.sourceBindings.find(row=>row.path===folder+'resume_worker_schedules.test.mjs').sha256);
await read(folder+'source-proof.json','2ac9bf82c954dbf51bdad95ed161000b473cafb156e0fd6a40cf59311177cd6b');
await read(folder+'source-proof.md','6cfeeb754106110933128f47868e15be07e18491a9def92592b5cf29fbc1e3ae');
for(const file of ['helper-before-durability-fix.mjs','test-before-durability-fix.mjs','helper-before-provider-gate.mjs','test-before-provider-gate.mjs',
 'resume_worker_schedules.test.mjs','verify_controlled_sources.mjs','verify_health_sources.mjs','finalize_source_proof.mjs','finalize_source_proof_a2.mjs',
 'finalize_health_source_proof.mjs','controlled-verification-a1.json','controlled-verification-a1.tap',
 'controlled-verification-a2.json','controlled-verification-a2.tap','controlled-verification-a3.json','controlled-verification-a3.tap',
 'controlled-verification-health-a1.json','controlled-verification-health-a1.tap','health-a2-source-before.json','health-a2-exit.json',
 'controlled-verification-health-a2.tap','health-a2-offline-checks.json'])await read(folder+file);
const blocked=await json(folder+'controlled-verification-health-a1.json','815275c65351efc87cb2c5814c03c1118fc4c57b140e81d82f0ac2ff2d95c693');
assert.equal(blocked.exitCode,null);assert.ok(blocked.error.includes('EPERM'));assert.equal(blocked.counts.tests,null);
const oldFailure=await json(folder+'controlled-verification-a1.json');assert.equal(oldFailure.counts.fail,1);
const oldPassing=await json(folder+'controlled-verification-a3.json');assert.equal(oldPassing.counts.pass,24);
const readSql=await write(folder+'resume-read-health.sql',READ_SQL);
const fixtureFingerprints=[...GUARDS].sort().map((signature,i)=>({signature,md5:String(i+1).repeat(32)}));
const fakeTick={id:'00000000-0000-4000-8000-000000000025',kind:'health',state:'completed',tickSha256:'8'.repeat(64),outcomeSha256:'9'.repeat(64)};
let template=buildResumeSql(fixtureFingerprints,fakeTick);
for(const [i,row] of fixtureFingerprints.entries())template=template.replace(row.md5,`__REVIEWED_CURRENT_MD5_${i+1}__`);
template=template.replace(fakeTick.id,'__ACTUAL_COMPLETED_HEALTH_TICK_ID__').replace(fakeTick.tickSha256,'__ACTUAL_HEALTH_TICK_ROW_SHA256__')
 .replace(fakeTick.outcomeSha256,'__ACTUAL_HEALTH_OUTCOME_ROW_SHA256__');
const writeTemplate=await write(folder+'resume-write-health-review-template.sql',
 '-- SOURCE REVIEW TEMPLATE ONLY. Seven function fingerprints and the one actual completed health tick/outcome identity must come from independently reviewed actual evidence. This file is never dispatched.\n'+template);
const contract=await write(folder+'health-readiness-gate-schema.json',{
 kind:'source-only-scheduler-health-readiness-gate-contract',actualEvidenceSupplied:false,actualProbeAuthorized:false,
 fixedProviderReviewPath:PROVIDER_REVIEW,providerReviewKind:'independent-actual-v7-deployed-health-readiness-review',
 requiredProviderReviewFields:['technicalDecision=approve','passed=true','independentlyReviewed=true','projectId','runtimeBundleSha256','runtimeId',
  'deployedVersion=7','candidateBundleSha256','observedAt','guardFingerprints','readinessTick','actualHealthResultBinding',
  'actualBeforeStateBinding','actualDispatchBinding','actualAfterStateBinding','healthControllerSourceBinding','evidenceBindings',
  'actualDeployedWorkerBackendAuthorizationVerified=true','actualServiceKeyRoleAndValidityVerified=true',
  'unsignedProbeUsedAsRoleProof=false','keyFormatUsedAsRoleProof=false','secretsPublished=false',
  'priorScheduledRequestsObserved=24','readinessRequestsCharged=1','cumulativeReviewedWorkerRequests=25'],
 actualHealthResultKind:'actual-v7-deployed-health-readiness-result',rootHealthController:before.find(row=>row.path==='tools/wave5/probe_worker_v7_health_20261014_r5.mjs'),
 transport:'One existing database-owned edge_schedule_tick health invocation; schedule-key token/hash authentication, not HMAC. No client schedule-secret retrieval.',
 tick:{id:'actual UUID',kind:'health',state:'completed',tickSha256:'actual SQL-produced full-row digest',outcomeSha256:'actual SQL-produced full-outcome digest'},
 effectsBefore:{ticks:0,outcomes:0,quotaPeriods:0,deliveryOutcomes:0,receiverReceipts:0,modelInvocations:0,modelOutcomes:0,usageEvents:0},
 effectsAfter:{ticks:1,outcomes:1,quotaPeriods:0,deliveryOutcomes:0,receiverReceipts:0,modelInvocations:0,modelOutcomes:0,usageEvents:0},
 successfulHttp:{netRequestId:'actual positive integer',status:200,serverRequestId:'actual server UUID',
  response:{state:'completed',count:1,states:['collected']},responseSha256:'digest of exact successful public response bytes'},
 requiredRawLineage:'Full actual before-state, enqueue dispatch and successful after-state records are hash-bound. Match request ID, actual observed/dispatched/tick-start/completion times, HTTP content/hash/bytes/server UUID, sole completed health tick, full raw tick/outcome rows, positive lease and exact success summary.',
 beforePrivateUse:'Pin all provider, controller and raw evidence hashes in the separate final operation review and source/evidence bindings, then verify bytes before stdin or unseal.',
 originalAuthorityExpiresAt:EXPIRES,sourceCanRenewAuthority:false,currentExecutionAllowed:false});
const testRecord=await write(folder+'controlled-verification-health-a3.json',{
 kind:'source-bound-controlled-scheduler-one-health-readiness-verification',passed:true,verifiedAt:new Date().toISOString(),
 command:['C:\\Program Files\\nodejs\\node.exe','--test','--test-isolation=none','--test-reporter=tap','--test-timeout=5000',folder+'resume_worker_schedules_health.test.mjs'],
 invocation:'Direct PowerShell child Node; avoids the preserved Node spawnSync EPERM. The actual TAP and exit-code artifact are linked.',
 actualExit:bindings.get(folder+'health-a3-exit.json'),exitCode:exit.exitCode,counts,testIdentities:identities,
 log:bindings.get(folder+'controlled-verification-health-a3.tap'),sourceBindingsBefore:before,sourcesUnchangedDuringRun:true,
 offlineChecks:bindings.get(folder+'health-a3-offline-checks.json'),syntaxExitCode:0,offlineValidationExitCode:0,expiredExecuteExitCode:1,
 expiredExecuteReadPrivateInput:false,networkCalls:0,liveSqlExecuted:0,privateInputsRead:0,SDKJobs:0});
const preparedAt=new Date().toISOString();assert.ok(Date.parse(preparedAt)>Date.parse(EXPIRES));
const providerPresent=Boolean(await fs.stat(path.join(root,PROVIDER_REVIEW)).catch(()=>null));
const finalReviewPresent=Boolean(await fs.stat(path.join(root,REVIEW)).catch(()=>null));
const sourceBindings=[...bindings.values()];for(const binding of sourceBindings)assert.equal(hash(await fs.readFile(path.join(root,binding.path))),binding.sha256);
const proof={kind:'source-only-exact-three-job-resume-with-one-actual-deployed-health-readiness-gate',preparedAt,author:'/root/requirement_acceptance',
 projectId:PROJECT,runtimeBundleSha256:BUNDLE,source:bindings.get(SOURCE),sourceOnly:true,implementationCompleteForIndependentReview:true,
 supersedesIntermediateProof:bindings.get(folder+'source-proof-a2.json'),allPriorProofsTestsFailuresAndBeforeBytesPreserved:true,
 originalHelper:PRESERVED[0],originalSql:PRESERVED[1],originalReadSql:PRESERVED[2],consumedOriginalA4Intent:PRESERVED[4],
 originalSourceOrIntentOrAcceptanceRewritten:false,originalIssuedAt:ISSUED,originalExpiry:EXPIRES,originalAuthorityExpired:true,
 expiryExtended:false,privateWindowCannotExtendAuthority:true,executionPermitted:false,
 exactV7HumanDeploymentApproval:PRESERVED[6],exactV7UnsignedProbe:PRESERVED[7],exactV7SourceReadbackReview:PRESERVED[8],returnedActualV7SourceRowsBound:25,
 actualUnsigned403IsInjectedBackendKeyProof:false,localServiceRoleRequestIsInjectedBackendKeyProof:false,
 healthReadinessGate:{schema:contract,mandatory:true,providerReviewPresent:providerPresent,actualProviderEvidenceCreatedByAuthor:false,
  rootHealthControllerAtInterfaceAlignment:before.find(row=>row.path==='tools/wave5/probe_worker_v7_health_20261014_r5.mjs'),
  actualHealthResultKind:'actual-v7-deployed-health-readiness-result',providerReviewKind:'independent-actual-v7-deployed-health-readiness-review',
  oneActualHealthInvocationRequired:true,allOtherTickIdentitiesKindsStatesOrCountsRejected:true,oneSuccessfulOutcomeRequired:true,
  rawBeforeDispatchAfterEvidenceMandatory:true,fullRawTickAndOutcomeRowsMandatory:true,netRequestHttpBodyHashServerUuidTimesAndLeaseChecked:true,
  noQuotaDeliveryReceiverModelOrUsageEffectsRequired:true,requiredFunctionFingerprints:GUARDS,
  databaseOwnedScheduleKeyHashAuthentication:true,hmacSignatureClaimed:false,clientScheduleSecretRetrievalAllowed:false,
  exactProviderAndRawEvidenceHashesRequiredBeforeStdin:true,actualProbeAuthorizedOrExecutedByAuthor:false},
 sqlInventory:{read:readSql,writeTemplate,guardFingerprintPopulation:7,actualTickIdAndTwoFullRowDigestsRequired:true,
  actualWriteSqlFormula:'buildResumeSql(exact reviewed seven guard fingerprints, exact one completed health readiness tick). Final operation review pins the complete generated SQL hash.',
  managementRequests:['read-only exact preflight','one guarded transaction enabling only jobs 4/5/6','read-only exact after-state'],
  maximumManagementAttempts:3,maximumMutationDispatches:1,automaticRetries:0,
  guardedActions:['cron.alter_job(4,active:=true)','cron.alter_job(5,active:=true)','cron.alter_job(6,active:=true)'],
  installedBaseline:{migrations:115,apiFunctions:363},originalScopeAuthorityExpiryAndJobGuardsPreserved:true,
  noOtherMutationOrCounterOrLeaseOrGrantOrSecretChange:true,databaseSqlExecutedByAuthor:false,databaseSyntaxValidationClaimed:false},
 jobIds:[4,5,6],exactJobs:JOBS,requestAccounting:{earlierObserved404Requests:24,requiredGenuineHealthRequests:1,
  priorReviewedWorkerRequests:25,maximumOriginalWorkerRequests:4320,countersReset:false,
  remainingCheck:'retained cron-run count + one direct health invocation + all remaining possible three-per-minute slots <= 4320'},
 cli:{validateDoesNotUsePrivateInputOrNetwork:true,validateExitCode:0,expiredExecuteExitCode:1,
  expiredExecuteFailureCode:'ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED',fixedFinalOperationReview:REVIEW,fixedExclusiveNewOnceIntent:ONCE,
  separateFinalOperationReviewPresent:finalReviewPresent,separateFinalReviewAndCompletedExportsAndFreshOwnerScopeStillRequired:true,
  originalA4OnceIntentNeverReused:true},
 verification:{record:testRecord,counts,syntaxPassed:true,offlineValidationPassed:true,expiredExecuteRejectedBeforeStdin:true,
  allCurrentBoundSourceBytesUnchanged:true,windowsSpawnRestrictionPreserved:bindings.get(folder+'controlled-verification-health-a1.json')},
 sourceBindings,sourceBindingsUnchangedDuringFinalization:true,
 actualProjectApiRequests:0,privateInputsRead:0,liveSqlExecuted:0,SDKJobs:0,schedulesResumed:false,actualDelivery:false,
 actualModelUsage:false,authenticatedNative:false,targetScaleLoad:false,additionalRequirementAcceptance:0,productionReleaseReady:false,
 personalHumanExactSourceSignatureClaimed:false,
 limitations:[
  'Original edge authority expired on October 14, 2026 at 09:57:07.481942 UTC; runtime scope had an earlier independent expiry. This immutable helper rejects before private use and cannot implement any later authority renewal. A future helper/window requires its own concrete source and operation review.',
  'The actual health invocation is a prerequisite, not an action authorized by this source work. No actual provider result, health probe, owner metadata refresh, export registration, schedule activation or private adapter operation was performed by this author.',
  'A local service-role success or unsigned403 does not prove the injected edge key. Only independently reviewed genuine database-owned deployed health success, tied to one completed health tick/outcome and actual HTTP lineage, is eligible.',
  'A health invocation creates that one tick/outcome and the existing health-collection observations. This is counted after the earlier24 failures, without resetting them. No quota, delivery, receiver, model or usage rows are allowed by this gate.',
  'All controlled test keys, clocks, IDs, records, fingerprints, transports and persistence receipts are fake and confined to test source. They do not establish actual provider authority or supply a personal human signature.',
  'SQL-produced JSONB row digests are compared with exact bound server observations; raw JSON is not normalized into a substitute hash. Templates contain explicit non-executable markers and were not sent to a database.',
  'The strict readback also rejects unexpected extra ticks or effects after activation; a minute-boundary scheduled run may therefore produce an unconfirmed stop rather than success. It must never cause a replay or counter reset.',
  'All previous failed and intermediate evidence remains preserved. This source work adds no native acceptance, target-scale load, delivery/model success, requirement acceptance or release readiness.'
 ]};
const record=await write(folder+'source-proof-health-a3.json',proof);
const markdown=await write(folder+'source-proof-health-a3.md',[
 '# Scheduler source with one health-readiness gate','',
 'The finalized scheduler successor passes **30 controlled cases**, its syntax check and offline source validation. The fixed operation enables only jobs 4, 5 and 6, after completed original exports and a separate exact operation review. No schedules were resumed.','',
 '**The original authority expired on October 14, 2026 at 09:57:07.481942 UTC.** Execute now returns ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED before private input or any request. Runtime scope had a separate earlier expiry. This helper preserves the original window and cannot implement a renewal.','',
 'The injected-key prerequisite now uses one genuine deployed health invocation through the existing database-owned schedule-key/hash gate. It is not a local service-role test or an HMAC signature. The gate requires the actual successful HTTP body/hash, pg_net request ID, server UUID, full raw before/dispatch/after evidence, one exact completed health tick/outcome and matching timestamps, lease and server row digests. Any other tick count, identity, kind, state or quota/delivery/receiver/model/usage effect is rejected.','',
 'The earlier 24 failed HTTP requests remain recorded. The readiness invocation adds one, making 25 reviewed worker requests toward the original 4,320 cap. No counter, authority, lease, key or grant is reset. The write SQL also rechecks the original authority, exact scope, 115/363 installation, seven server function fingerprints, service-role grants, completed original export jobs/receipts, paused job names/commands and outside-job digest.','',
 'A final operation record must bind the actual independent provider review, actual health result, raw observations, controller source, completed export proof, current owner metadata, exact helper/query hashes and private adapter before stdin or unseal. The successful health readback must remain durably captured. No actual evidence file or operation approval is supplied by this source proof.','',
 'The final inventory is read-only preflight, one guarded three-job activation and read-only after-state. An actually dispatched uncertain write is never replayed; its one normal after-read can establish state. Failed persistence before dispatch stops immediately. Strict extra-effect rejection may stop a minute-boundary readback without asserting success.','',
 'The Windows Node-child-spawn EPERM record is preserved separately; no tests ran in that attempt. The direct terminal run passed all 30 cases with unchanged bound source bytes. Earlier 19/20, 20/20 and 24/24 records, before-change source copies and intermediate proofs remain intact.','',
 'This was source-only work: zero project API requests, private credential reads, live SQL, probes, schedule changes or SDK jobs. No actual provider authority, delivery, model use, native acceptance, load acceptance, requirement decision or production release is claimed.','',
 `Proof: ${record.path} (SHA-256 ${record.sha256}).`,
 `Helper SHA-256: ${proof.source.sha256}.`,
 `Controlled result: ${testRecord.path} (SHA-256 ${testRecord.sha256}).`,''].join('\n'));
console.log(JSON.stringify({source:proof.source,proof:record,markdown,tests:testRecord,counts,readSql,writeTemplate,
 contract,bindings:sourceBindings.length,sourceOnly:true,originalAuthorityExpired:true,executionPermitted:false}));
