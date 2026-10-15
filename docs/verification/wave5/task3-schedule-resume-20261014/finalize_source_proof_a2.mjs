import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {SOURCE,PRESERVED,READ_SQL,GUARDS,JOBS,EXPIRES,ISSUED,PROJECT,BUNDLE,REVIEW,PROVIDER_REVIEW,ONCE,
 validatePreservedSources} from '../../../../tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const folder='docs/verification/wave5/task3-schedule-resume-20261014/';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const bindings=new Map();
async function read(file,expected){const bytes=await fs.readFile(path.join(root,file));const binding={path:file,sha256:hash(bytes),bytes:bytes.length};
 if(expected)assert.equal(binding.sha256,expected,'input changed: '+file);
 if(bindings.has(file))assert.deepEqual(binding,bindings.get(file));else bindings.set(file,binding);return bytes;}
async function json(file,expected){return JSON.parse(await read(file,expected));}
async function write(file,value){assert.ok(file.startsWith(folder));const bytes=Buffer.from(typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
 await fs.writeFile(path.join(root,file),bytes,{flag:'wx'});return {path:file,sha256:hash(bytes),bytes:bytes.length};}

const tests=await json(folder+'controlled-verification-a3.json','39653ee94544e7dcc66779773656082d8b903c5488357b16bdd49261eb321a5a');
assert.equal(tests.passed,true);assert.deepEqual(tests.counts,{tests:24,pass:24,fail:0,cancelled:0,skipped:0,todo:0});
assert.equal(tests.testIdentities.length,24);assert.ok(tests.testIdentities.every(row=>row.status==='ok'));
assert.equal(tests.syntax.exitCode,0);assert.equal(tests.offlineValidation.exitCode,0);
assert.equal(tests.expiredExecute.exitCode,1);assert.ok(tests.expiredExecute.stderr.includes('ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED'));
assert.equal(tests.sourcesUnchangedDuringRun,true);for(const binding of tests.sourceBindingsBefore)await read(binding.path,binding.sha256);
await read(tests.log.path,tests.log.sha256);
const prior=await json(folder+'source-proof.json','2ac9bf82c954dbf51bdad95ed161000b473cafb156e0fd6a40cf59311177cd6b');
await read(folder+'source-proof.md','6cfeeb754106110933128f47868e15be07e18491a9def92592b5cf29fbc1e3ae');
assert.equal(prior.source.sha256,'5ddfd0b63b38a729508bfcb14544e430b23caf85dcd8a5acd01f6e9d085576d9');
await read(folder+'helper-before-provider-gate.mjs',prior.source.sha256);
await read(folder+'test-before-provider-gate.mjs','47505f7fe592e12cf3e3f0aabb00673d65b685b8bc85b7af669259f0afcfcad6');
for(const file of ['controlled-verification-a1.json','controlled-verification-a2.json','helper-before-durability-fix.mjs',
 'test-before-durability-fix.mjs','finalize_source_proof.mjs','verify_controlled_sources.mjs','finalize_source_proof_a2.mjs'])await read(folder+file);
const failed=await json(folder+'controlled-verification-a1.json','80c3917649a365acfd5e90c67c3650110ef10b647340674321ac183c1d97a887');
await read(failed.log.path,failed.log.sha256);assert.equal(failed.counts.fail,1);
const firstPass=await json(folder+'controlled-verification-a2.json','f2caa55c7de49144ac4060c1fa46deaf049f90dff2f971698bd5d4821de80bb3');
await read(firstPass.log.path,firstPass.log.sha256);assert.equal(firstPass.counts.pass,20);
assert.equal((await validatePreservedSources()).passed,true);
const actualMapping=await json(PRESERVED[8].path,PRESERVED[8].sha256);
for(const binding of [...PRESERVED,...actualMapping.evidence,...actualMapping.sources])await read(binding.path,binding.sha256);
await read(folder+'resume-read.sql',hash(READ_SQL));
await read(folder+'resume-write-review-template.sql','60705b10f0c006918902d67e988724e01ad51b17458eea823aa6d43d40eba2c5');
const preparedAt=new Date().toISOString();assert.ok(Date.parse(preparedAt)>=Date.parse(EXPIRES));
assert.equal(Boolean(await fs.stat(path.join(root,PROVIDER_REVIEW)).catch(()=>null)),false,'No actual provider authority record may be fabricated here');
assert.equal(Boolean(await fs.stat(path.join(root,REVIEW)).catch(()=>null)),false,'No actual operation review may be fabricated here');
const currentSource=(await read(SOURCE)).toString();
assert.ok(currentSource.indexOf('const providerAuthority=JSON.parse(await exactFile(PROVIDER_REVIEW')
 <currentSource.indexOf('for await(const chunk of stdin)'), 'public provider proof must be validated before private input');
assert.ok(currentSource.includes('...providerAuthority.evidenceBindings'));
const sourceBindings=[...bindings.values()];
for(const binding of sourceBindings)assert.equal(hash(await fs.readFile(path.join(root,binding.path))),binding.sha256);

const proof={kind:'source-only-exact-three-job-schedule-resume-successor-proof-with-actual-provider-gate',preparedAt,
 author:'/root/requirement_acceptance',projectId:PROJECT,runtimeBundleSha256:BUNDLE,source:bindings.get(SOURCE),sourceOnly:true,
 supersedesIntermediateProof:bindings.get(folder+'source-proof.json'),intermediateBeforeProviderGateSource:bindings.get(folder+'helper-before-provider-gate.mjs'),
 intermediateBeforeProviderGateTests:bindings.get(folder+'test-before-provider-gate.mjs'),allIntermediateAndFailedRecordsPreserved:true,
 predecessor:PRESERVED[0],originalSql:PRESERVED[1],originalReadSql:PRESERVED[2],consumedOriginalA4Intent:PRESERVED[4],
 originalSourceOrIntentOrAcceptanceRewritten:false,preservedOriginalAuthorityIssuedAt:ISSUED,preservedOriginalAuthorityExpiresAt:EXPIRES,
 originalAuthorityExpiredAtProof:true,executionPermittedByThisProof:false,exactFinalOperationReviewRequired:true,
 exactV7HumanDeploymentApproval:PRESERVED[6],exactV7UnsignedProbe:PRESERVED[7],exactV7SourceReadbackReview:PRESERVED[8],returnedV7SourceRowsBound:25,
 providerAuthorityGate:{mandatory:true,fixedPublicPath:PROVIDER_REVIEW,actualRecordPresent:false,actualProbeAuthorizedByThisSource:false,
  acceptedKind:'independent-actual-v7-backend-provider-authority-review',
  beforeAnyStdinUnsealOrRequest:['Separate final operation review must pin the exact provider review hash at the fixed public path.',
   'Actual V7 backend read-only authorization, service role and key validity must have been independently reviewed for the exact project, runtime, tenant, candidate and existing injected server key.',
   'The record must be current within five minutes, within the original authority and bound to the exact four guard fingerprints.',
   'At least one actual successful read-only wave5_runtime_worker entitlement check must bind its genuine server UUID, response SHA256 and exact public evidence record.',
   'All provider evidence hashes must also appear in the final source/evidence inventory and match actual bytes before private input. Missing, inferred, denied, malformed, mismatched or stale evidence fails closed.'],
  unsigned403OrKeyShapeOrExecuteGrantsSufficient:false,secretContentsMayBePublished:false,newSecretsOrProbeOrLiveAuthorityCreated:false,
  actualRoleOrValidityProvedByTheseControlledTests:false},
 sqlInventory:{...prior.sqlInventory,read:bindings.get(folder+'resume-read.sql'),writeTemplate:bindings.get(folder+'resume-write-review-template.sql')},
 jobIds:[4,5,6],exactJobs:JOBS,maximumScheduleRequestsOriginal:4320,scheduledRequestsAlreadyObserved:24,countersReset:false,
 budgetInterpretation:prior.budgetInterpretation,
 cli:{validate:'node tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs --validate',
  execute:'node tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs --execute <exact separately reviewed final operation JSON SHA256>',
  fixedFinalOperationReview:REVIEW,fixedExclusiveNewOnceIntent:ONCE,validateReadsPrivateInput:false,validateNetworkCalls:0,
  executeCurrentStatus:'rejects ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED before even public gate-file validation, stdin, private parsing or requests',
  finalReviewOrProviderEvidenceOrCompletedExportsSuppliedByAuthor:false,
  currentSidSameProjectAndBundleMetadataRequired:true,privateAdapterExactHashRequired:true,
  freshOwnerMetadataCanExtendOriginalRuntimeExpiry:false},
 tests:{record:bindings.get(folder+'controlled-verification-a3.json'),log:tests.log,counts:tests.counts,testIdentities:tests.testIdentities,
  syntaxPassed:true,offlineValidationPassed:true,expiredExecuteRejectedBeforePrivateUse:true,sourceBindingsUnchangedDuringRun:true,
  previous20PassingRunPreserved:bindings.get(folder+'controlled-verification-a2.json')},
 firstDurabilityFailure:prior.initialFailure,
 addedProviderGateReason:'Independent source reviewer identified that saved unsigned ingress denial and SQL execute grants do not establish actual service-key backend authority. The mandatory independently reviewed actual-provider record and all its evidence are now pinned and validated before private input. No actual provider result or new probe was created.',
 sourceBindings,sourceBindingsUnchangedDuringFinalization:true,
 actualPrivateInputsRead:0,actualProjectApiRequests:0,liveWrites:0,SDKJobs:0,schedulesResumed:false,actualDelivery:false,
 actualTrustedModelUsage:false,authenticatedNative:false,targetScaleLoad:false,additionalRequirementAcceptance:0,productionReleaseReady:false,
 personalHumanExactSourceSignatureClaimed:false,
 limitations:[
  'The original authority expired on October 14, 2026 at 09:57:07.481942 UTC. This successor cannot now run live. Later owner metadata, export completion or provider evidence cannot extend that deadline.',
  'The actual provider authority record, actual completed export result and separate final operation review are absent. Their shapes are exercised only with clearly controlled fake test data, and no public success record or human signature is fabricated.',
  'The fixed provider record is a prerequisite, not authorization to obtain it. This source work does not permit an actual probe, new credential read, backend call, schedule activation or any runtime renewal.',
  'The unsigned 403 probe proves an authentication denial at ingress. It does not establish a real provider role or validity. Key format and SQL grants are also insufficient; the actual independently reviewed backend authorization evidence remains mandatory.',
  'All 24 controlled tests use fake clocks, request factories, sessions, keys, fingerprints, records and persistence receipts. They validate behavior and gates, without SQL execution or actual private/network/provider work.',
  'The unchanged SQL inventory contains a non-executable write review template with four explicit MD5 markers. The operation owner must independently verify actual installed fingerprints and pin generated SQL; no current database syntax or body match was checked by this author.',
  'The original helper, consumed A4 intent, saved 24 observed requests, original 4,320 cap and all failure/intermediate evidence remain intact. Source readiness adds no delivery, model, native, load, acceptance or release success.'
 ]};
const record=await write(folder+'source-proof-a2.json',proof);
const markdown=await write(folder+'source-proof-a2.md',[
 '# Source-only schedule resume successor','',
 'The finalized helper passes **24 controlled tests**, its syntax check and offline source validation. It retains the original jobs 4, 5 and 6, the recorded 24 requests, the 4,320 maximum and the exact original issuance and expiry. The previous 20-case passing source, intermediate proof and initial durability failure remain preserved.','',
 '**The original authority expired on October 14, 2026 at 09:57:07.481942 UTC.** Execute now rejects before public operation files, stdin, private parsing or requests. A fresh metadata file cannot extend this authority. No schedule was resumed.','',
 'Actual backend provider authority is now a mandatory gate. The separate final operation review must pin the fixed public provider review and all its actual evidence hashes. That independent record must establish current authorized read-only backend access and service-key role/validity for the exact V7 source, project, runtime and tenant. Missing proof, key-shape inference, unsigned 403, database grants alone, denied results, stale clocks or unbound evidence cannot pass. No actual provider record exists here, and no probe is authorized by this source work.','',
 'Exports must complete first, with the same two original registrations and independent source/CSV reproduction. A separate exact operation review, fresh owner metadata, current-SID private-adapter check and complete source/evidence inventory are required before private input. The V7 deployment approval explicitly excluded schedule resume.','',
 'The fixed inventory remains three management calls: read-only preflight, one guarded transaction changing only cron.alter_job for jobs 4/5/6, and read-only after-state. Guards retain exact scope, 115 migrations and 363 API functions, unchanged server function fingerprints/grants, completed original export jobs/receipts, paused job names/commands, outside-job digest and zero worker/quota baseline. No authority, key, lease, permission or counter is reset. An uncertain dispatched write gets one readback and is never replayed; failed acknowledgment before dispatch stops immediately.','',
 'The source work performed no project API request, private credential read, live SQL, deployment, schedule change or SDK job. It adds no provider success, delivery, model use, native acceptance, load acceptance, requirement decision or production release claim.','',
 `Exact successor proof: ${record.path} (SHA-256 ${record.sha256}).`,
 `Exact helper SHA-256: ${proof.source.sha256}.`,
 `Controlled result: ${proof.tests.record.path} (SHA-256 ${proof.tests.record.sha256}).`,''].join('\n'));
console.log(JSON.stringify({source:proof.source,record,markdown,tests:proof.tests.record,counts:tests.counts,
 boundInputs:sourceBindings.length,actualProviderAuthorityRecordPresent:false,originalAuthorityExpired:true,
 sourceOnly:true,executionPermitted:false}));
