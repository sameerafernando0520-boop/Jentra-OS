import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {SOURCE,PRESERVED,READ_SQL,GUARDS,JOBS,EXPIRES,ISSUED,PROJECT,BUNDLE,REVIEW,ONCE,buildResumeSql,
 validatePreservedSources} from '../../../../tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const folder='docs/verification/wave5/task3-schedule-resume-20261014/';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
async function read(file,expected){const bytes=await fs.readFile(path.join(root,file));if(expected)assert.equal(sha(bytes),expected);
 return {path:file,sha256:sha(bytes),bytes:bytes.length};}
async function json(file,expected){await read(file,expected);return JSON.parse(await fs.readFile(path.join(root,file),'utf8'));}
async function write(file,value){const bytes=Buffer.from(typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
 await fs.writeFile(path.join(root,file),bytes,{flag:'wx'});return {path:file,sha256:sha(bytes),bytes:bytes.length};}
const evidence=await json(folder+'controlled-verification-a2.json','f2caa55c7de49144ac4060c1fa46deaf049f90dff2f971698bd5d4821de80bb3');
assert.equal(evidence.passed,true);assert.deepEqual(evidence.counts,{tests:20,pass:20,fail:0,cancelled:0,skipped:0,todo:0});
assert.equal(evidence.sourcesUnchangedDuringRun,true);for(const binding of evidence.sourceBindingsBefore)await read(binding.path,binding.sha256);
await read(evidence.log.path,evidence.log.sha256);assert.equal(evidence.syntax.exitCode,0);assert.equal(evidence.offlineValidation.exitCode,0);
assert.equal(evidence.expiredExecute.exitCode,1);assert.ok(evidence.expiredExecute.stderr.includes('ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED'));
const failed=await json(folder+'controlled-verification-a1.json','80c3917649a365acfd5e90c67c3650110ef10b647340674321ac183c1d97a887');
await read(failed.log.path,failed.log.sha256);assert.equal(failed.counts.fail,1);
const before=await fs.readFile(path.join(root,folder+'helper-before-durability-fix.mjs'),'utf8');
const after=await fs.readFile(path.join(root,SOURCE),'utf8');
assert.equal(sha(before),failed.sourceBindingsBefore.find(row=>row.path===SOURCE).sha256);
let inverse=after;
const once=(from,to)=>{assert.equal(inverse.split(from).length-1,1);inverse=inverse.replace(from,to);};
once('  if(!readOnly)mutationAttempted=true;\n','');
once("  phase='exact-resume';let uncertain=null;\n  try{await capture('02-write',writeSql,false);}catch(error){\n   if(!mutationAttempted)throw error;\n   uncertain=error.publicCode??'SCHEDULE_WRITE_OUTCOME_UNCERTAIN';\n  }",
 "  phase='exact-resume';mutationAttempted=true;let uncertain=null;\n  try{await capture('02-write',writeSql,false);}catch(error){uncertain=error.publicCode??'SCHEDULE_WRITE_OUTCOME_UNCERTAIN';}");
assert.equal(inverse,before);
const preservedValidation=await validatePreservedSources();assert.equal(preservedValidation.passed,true);
const mapping=await json(PRESERVED[8].path,PRESERVED[8].sha256);
const paths=[...new Set([SOURCE,...PRESERVED.map(row=>row.path),...mapping.evidence.map(row=>row.path),...mapping.sources.map(row=>row.path),
 folder+'resume_worker_schedules.test.mjs',folder+'verify_controlled_sources.mjs',folder+'finalize_source_proof.mjs',
 folder+'helper-before-durability-fix.mjs',folder+'test-before-durability-fix.mjs',folder+'controlled-verification-a1.json',failed.log.path,
 folder+'controlled-verification-a2.json',evidence.log.path])].sort();
const sourceBindings=await Promise.all(paths.map(file=>read(file)));
const readSql=await write(folder+'resume-read.sql',READ_SQL);
const fixtureFingerprints=[...GUARDS].sort().map((signature,i)=>({signature,md5:String(i+1).repeat(32)}));
let writeTemplate=buildResumeSql(fixtureFingerprints);
for(const [i,row] of fixtureFingerprints.entries())writeTemplate=writeTemplate.replace(row.md5,`__REVIEWED_CURRENT_MD5_${i+1}__`);
const sqlTemplate=await write(folder+'resume-write-review-template.sql','-- SOURCE REVIEW TEMPLATE ONLY. Replace the four markers solely through buildResumeSql after an independently pinned actual guard fingerprint read. This file is never dispatched.\n'+writeTemplate);
assert.ok(!await fs.stat(path.join(root,REVIEW)).catch(()=>null),'No actual schedule operation gate may be authored by this source proof');
const preparedAt=new Date().toISOString();assert.ok(Date.parse(preparedAt)>=Date.parse(EXPIRES));
const proof={kind:'source-only-exact-three-job-schedule-resume-successor-proof',preparedAt,author:'/root/requirement_acceptance',
 projectId:PROJECT,runtimeBundleSha256:BUNDLE,source:sourceBindings.find(row=>row.path===SOURCE),
 predecessor:PRESERVED[0],originalSql:PRESERVED[1],originalReadSql:PRESERVED[2],consumedOriginalA4Intent:PRESERVED[4],
 originalIntentOverwritten:false,oldSourceFilesEdited:0,oldEvidenceOverwritten:0,
 preservedOriginalAuthorityIssuedAt:ISSUED,preservedOriginalAuthorityExpiresAt:EXPIRES,originalAuthorityExpiredAtProof:true,
 sourceOnly:true,executionPermittedByThisProof:false,finalOperationReviewRequired:true,finalOperationReviewPresent:false,
 exactV7HumanDeploymentApproval:PRESERVED[6],exactV7UnsignedProbe:PRESERVED[7],exactV7SourceReadbackReview:PRESERVED[8],
 returnedActualV7SourceRowsBound:25,actualUnsigned403IsServiceKeyRoleProof:false,
 sqlInventory:{read:readSql,readOnlyRequests:2,writeRequests:1,maximumManagementAttempts:3,writeTemplate:sqlTemplate,
  actualWriteSqlFormula:'buildResumeSql(exact independently reviewed four guard fingerprints). The final operation record must pin the generated full SQL SHA256 and the exact source hash.',
  allowedGuardSignatures:GUARDS,unknownSignaturesOrNonhexMd5ValuesRejected:true,guardFingerprintPopulation:4,
  writableActions:['cron.alter_job(4,active:=true)','cron.alter_job(5,active:=true)','cron.alter_job(6,active:=true)'],
  schemaOrDataMutationElsewhereAllowed:false,guardChecks:['exact authority row locked; original issuance/expiry; enabled and unexpired',
   'exact original runtime/tenant/entity/branch scope', '115 migrations and363 API functions','exact four unchanged server guard function MD5s and existing service_role RPC execute grants',
   'exact two original completed export jobs and finance.report.export receipts','exact three existing paused minute jobs, commands and names','unchanged outside cron hash',
   'zero worker ticks and zero quota periods before resume','at least24 retained cron runs plus remaining possible minute slots <=4320'],
  mutationsOfKeysOrAuthorityOrScopeOrGrantsOrLeasesOrCounters:0,automaticRetries:0,readOnlyOutcomeResolution:'The third, normal after-read doubles as the one bounded readback after an actually dispatched uncertain write. No fourth request or replay is allowed.',
  SqlExecutedByAuthor:false,databaseSyntaxOrCurrentFingerprintValidationPerformed:false},
 jobIds:[4,5,6],exactJobs:JOBS,maximumScheduleRequestsOriginal:4320,scheduledRequestsAlreadyObserved:24,countersReset:false,
 budgetInterpretation:'The original installed scheduler has no separate cumulative HTTP counter. Three once-per-minute jobs within the retained24-hour authority define the lifetime4320 bound. The saved24 observed responses remain separate from zero worker ticks. The new guarded read also requires retained cron-run count >=24 and enforces that count plus all remaining possible minute slots <=4320. Missing retained run history fails closed; it is never reset or fabricated.',
 cli:{validate:'node tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs --validate',
  execute:'node tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs --execute <exact separately reviewed final operation JSON SHA256>',
  fixedFinalOperationReview:REVIEW,fixedExclusiveNewOnceIntent:ONCE,validateReadsPrivateInput:false,validateNetworkCalls:0,
  executeCurrentStatus:'rejects ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED before public operation-file validation, stdin, private parsing or request',
  executeBeforePrivateInputRequirements:['unexpired original deadline','exact current separate operation review and query/source hashes','actual successful original exports proof',
   'fresh hash-bound same-project/bundle/SID owner metadata','all old/new source and evidence bindings','exact independently reviewed private adapter and its current-SID check'],
  oldV7DeploymentApprovalAlonePermitsResume:false,freshOwnerMetadataExtendsOriginalRuntimeExpiry:false},
 tests:{record:sourceBindings.find(row=>row.path===folder+'controlled-verification-a2.json'),log:evidence.log,counts:evidence.counts,
  testIdentities:evidence.testIdentities,syntaxPassed:true,offlineValidationPassed:true,actualExpiredExecuteRejectedBeforePrivateUse:true,
  sourceBindingsUnchangedDuringRun:true},
 initialFailure:{record:sourceBindings.find(row=>row.path===folder+'controlled-verification-a1.json'),log:failed.log,
  sourceBefore:sourceBindings.find(row=>row.path===folder+'helper-before-durability-fix.mjs'),
  cause:'A failed pre-dispatch durable write-attempt acknowledgment was originally treated as an uncertain dispatched write. The final source distinguishes dispatch; pre-dispatch failure stops immediately and cannot reach a success readback.',
  exactTwoLocationFixReverseVerified:true,oldFailurePreserved:true},
 sourceBindings,sourceBindingsUnchangedDuringFinalization:true,
 actualPrivateInputsRead:0,actualProjectApiRequests:0,liveWrites:0,SDKJobs:0,schedulesResumed:false,actualDelivery:false,
 actualTrustedModelUsage:false,authenticatedNative:false,targetScaleLoad:false,additionalRequirementAcceptance:0,productionReleaseReady:false,
 personalHumanExactSourceSignatureClaimed:false,
 limitations:[
  'The original09:57 authority expired before this source proof finished. A later metadata refresh or completing exports cannot reactivate this authority. Any new runtime authority would require a separate concrete scope and decision; this helper deliberately does not implement it.',
  'Neither a final operation gate nor actual export success is supplied here. The source helper is concrete and controlled-tested, but currently cannot be executed live. It preserves original expiry and fails before private use.',
  'The saved unsigned403 proves the handler rejects unauthenticated ingress; it does not prove the real service key role/validity, backend success, HMAC receiver acceptance or delivery. Existing server function bodies, service_role grants, caller/scope/HMAC and readiness checks stay authoritative.',
  'All controlled sessions, token text, function MD5s, clocks, transport replies and persistence acknowledgments were fake. No SQL, socket, live provider, private token, actual model or SDK job was used.',
  'The write-review template intentionally contains four non-executable markers. Only a separate independently reviewed current fingerprint record can produce the exact full SQL pinned in an operation gate.',
  'Cron run retention and the arithmetic bound are conservative source checks. Their current database truth was not inspected by this author; an absent or changed baseline must stop the live owner rather than be waived.',
  'Exports must complete first. No registered statement reopen, native file save, target-scale load, owner acceptance or release readiness follows from this scheduler source work.'
 ]};
for(const binding of sourceBindings)await read(binding.path,binding.sha256);
const record=await write(folder+'source-proof.json',proof);
const markdown=await write(folder+'source-proof.md',[
 '# Source-only schedule resume successor','',
 'The new helper passes all20 controlled tests, its syntax check and offline source validation. It enables only the original jobs4,5 and6 after exact before-state checks, successful reconciliation of the two original exports and a separate operation review. No schedules were resumed.','',
 '**The original authority expired on October14,2026 at09:57:07.481942 UTC.** The helper now rejects execute before stdin, private parsing or any request. A fresh owner metadata file cannot extend that authority. The source remains reviewable, but it cannot currently execute live.','',
 'The original A4 helper, SQL, consumed intent, saved24 observed requests, original4,320 maximum and issuance/expiry are bound unchanged. Original ticks/quota rows remain a separate zero baseline. Current scope, four server guard fingerprints, existing service_role execute grants, exact115/363 installation, paused job names/commands, completed export IDs/receipts and the outside-job digest are rechecked. No lease, secret, permission, authority, counter or source data is reset.','',
 'The request inventory is exactly three fixed management calls: one read-only preflight, one guarded transaction calling cron.alter_job for jobs4/5/6, and one read-only after-state. An uncertain actually dispatched write is never replayed; the normal third read can establish enabled state. A failed durable acknowledgment before dispatch stops immediately. TLS chain/hostname verification, fixed project endpoint, response limits,45-second request deadline and original expiry are retained.','',
 'The first controlled run with19 passes and one durability failure is preserved with exact source bytes. The fix moves the mutation marker to actual transport invocation and rejects pre-dispatch failure before any readback. The final20 cases cover exact scope/SQL/caps/expiry, export proof, metadata and operation guards, persistence failures, unknown outcomes, preservation, TLS and expired CLI execution.','',
 'The write-review template contains four explicit non-executable MD5 markers. A separate exact final operation review must pin the actual current guard fingerprints, generated SQL digest, helper digest, successful export result, fresh owner metadata, all evidence/source bindings and the reviewed private adapter before any private use. The V7 deployment approval explicitly excludes schedule resume and is insufficient by itself.','',
 'This is source-only preparation. No private input, project API request, live SQL, schedule change, SDK job, delivery, model use, native acceptance, load acceptance, requirement decision or production release occurred.','',
 `Source proof: ${record.path} (SHA-256 ${record.sha256}).`,
 `Controlled result: ${folder}controlled-verification-a2.json (SHA-256 f2caa55c7de49144ac4060c1fa46deaf049f90dff2f971698bd5d4821de80bb3).`,''].join('\n'));
console.log(JSON.stringify({source:proof.source,record,markdown,tests:proof.tests.record,counts:evidence.counts,readSql,writeTemplate:sqlTemplate,
 boundInputs:sourceBindings.length,sourceOnly:true,originalAuthorityExpired:true,executionPermitted:false}));
