import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const read=async(file,base=root)=>{assert.ok(!path.win32.isAbsolute(file)&&!file.split('/').includes('..'));
 const bytes=await fs.readFile(path.join(base,file));return{path:file,root:base,bytes:bytes.length,sha256:sha(bytes),text:bytes.toString('utf8')};};
const ref=({text,...binding})=>binding;
const packet=await read('docs/verification/wave5/task3-peer-review-20261013/finance-successor-source-preparation-20261014-peer-a3.json');
assert.equal(packet.sha256,'638505ecd104f5a1ff5e674fe079a6d498452b1e7f308cff76f32ea0f39c6715');
const proof=JSON.parse(packet.text),snapshot='C:/Users/sheha/Desktop/Jentra OS/build/wave5-approved-execution-20261013-r5-a2';
assert.equal(proof.evidenceRoots.executionRoot,snapshot);
assert.equal(proof.evidenceRoots.publicCashEvidenceRoot,'C:/Users/sheha/Desktop/Jentra OS');
assert.equal(proof.sources.length,3);
const sources=[];
for(const binding of proof.sources){const actual=await read(binding.path);assert.equal(actual.sha256,binding.sha256);assert.equal(actual.bytes,binding.bytes);sources.push(actual);}
const helper=await import(pathToFileURL(path.join(root,'tools/wave5/finance_remaining_20261014_r5_a3.mjs')).href);
const preparation=await import(pathToFileURL(path.join(root,'tools/wave5/prepare_finance_remaining_20261014_r5_a3.mjs')).href);
assert.equal(helper.PRIOR_REQUEST_BOUND,78);
assert.equal(helper.CASH_PATCH.migrationVersion,'20261013184757');
assert.equal(helper.REMAINING_FUNCTION_MD5.wave5_cash_date_command,'1073f011cc41fd591ae30e37fee6f411');
assert.deepEqual(helper.REMAINING_KINDS,['payroll_correction','project_reimbursement']);
assert.equal(helper.REMAINING_RPCS.length,7);
const predecessor=await Promise.all(proof.preservedPredecessorPlanPopulation.map(binding=>read(binding.path,snapshot)));
assert.equal(predecessor.length,62);
for(let i=0;i<predecessor.length;i++){const binding=proof.preservedPredecessorPlanPopulation[i];
 assert.equal(predecessor[i].sha256,binding.sha256);assert.equal(predecessor[i].bytes,binding.bytes);}
const previous=await helper.loadConsumedRemainingAttempt();
assert.equal(previous.validation.observedReadOnlyAttempts,3);
assert.equal(previous.validation.completedCommands,0);
assert.equal(previous.validation.pendingCommand,null);assert.equal(previous.validation.resolution,null);
const cash=await helper.loadCashPatchEvidence();
assert.equal(cash.validation.cashDateDefinitionMd5,'1073f011cc41fd591ae30e37fee6f411');
const newBindings=sources.map(row=>({path:row.path,sha256:row.sha256}));
const joined=new Map([...previous.plan.sourceBindings,...Object.values(helper.PREVIOUS_ATTEMPT),...newBindings].map(row=>[row.path,{path:row.path,sha256:row.sha256}]));
const controlledPlan=preparation.buildRemainingPreparation({previous,sourceBindings:[...joined.values()],cashValidation:cash.validation,
 preparedAt:'2026-10-13T21:40:00.000Z'});
helper.validateRemainingPreparationPlan(controlledPlan);
helper.validatePreservedRemainingBindings(controlledPlan,previous.plan);
assert.equal(controlledPlan.maximumRemainingOrdinaryAttempts,71);
assert.equal(controlledPlan.maximumTotalWorkflowRequestAttempts,150);
assert.equal(controlledPlan.maximumExecutionMs,900000);
assert.equal(controlledPlan.maximumManagementOrActualTransportTimeoutMs,45000);
assert.equal(controlledPlan.preflightResponsesPersistedBeforeValidation,true);
assert.equal(controlledPlan.cashBasisScenariosAndCashExportsExcluded,true);
assert.equal(controlledPlan.originalStaleCommandId,'92e523de-6d82-d54a-0bfe-e81a78593a96');
assert.throws(()=>helper.validateRemainingActualDay('2026-10-14T00:00:00.000Z'));
const actualPlanFile=await read(helper.REMAINING_PLAN,snapshot);
assert.equal(actualPlanFile.sha256,'6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198');
const actualPlan=JSON.parse(actualPlanFile.text);
helper.validateRemainingPreparationPlan(actualPlan);
helper.validatePreservedRemainingBindings(actualPlan,previous.plan);
assert.equal(actualPlan.sourceBindings.length,68);assert.equal(actualPlan.publicCashBindings.length,10);
const checked=[];
for(const binding of actualPlan.sourceBindings){const actual=await read(binding.path,snapshot);
 assert.equal(actual.sha256,binding.sha256);checked.push(ref(actual));}
const authorRunFile=await read(proof.verification.json.path);
assert.equal(authorRunFile.sha256,proof.verification.json.sha256);
const authorRun=JSON.parse(authorRunFile.text);
const sourceText=sources.find(row=>row.path.endsWith('finance_remaining_20261014_r5_a3.mjs')).text;
assert.match(sourceText,/await persist\('00-source-and-uncertainty-before\.json',[\s\S]*?validateRemainingState\(before/);
assert.match(sourceText,/await persist\('01-installed-function-contracts\.json',[\s\S]*?validateRemainingFunctions\(functionRows\)/);
assert.match(sourceText,/if\(pending\)[\s\S]*receiptResolutionSql\(pending\.commandId\),\{resolution:true\}/);
assert.match(sourceText,/fs\.open\(path\.join\(root,file\),'wx'\)/);
const report={kind:'independent-source-and-generated-plan-finance-a3-review',reviewedAt:new Date().toISOString(),
 projectId:'xpdoufauvrbdmxgngetv',technicalVerdict:'approve exact generated preparation and existing bounded source successor; private adapter review still required',
 reviewerChat:'01a13650-c557-70d3-bb66-3c40b2a71efb',implementationAuthor:'/root/completion_peer',
 personalHumanExactSourceSignatureClaimed:false,sourceProof:ref(packet),sources:sources.map(ref),
 predecessorBindingsVerified:62,generatedPlan:ref(actualPlanFile),sourceBindingsVerified:checked,
 consumedAttemptValidation:previous.validation,cashPatchEvidenceValidation:cash.validation,
 actualCurrentDateIsStillMandatory:true,maximumTotalAttempts:150,priorBound:78,ordinaryAttemptsAvailable:71,
 readOnlyResolutionReserve:1,maximumExecutionMs:900000,individualTimeoutMs:45000,
 oldConsumedIntentAndUncertainCommandPreserved:true,arbitraryReplayForbidden:true,
 approvedNewActions:'Only remaining two source payment-date preparation/independent approval pairs, exact new prepared-command replays and two governed CSV registrations.',
 savedAuthorVerification:ref(authorRunFile),authorRunRecordKind:authorRun.kind,
 generatedActualPlanWrittenByReviewer:false,privateInputsRead:false,liveNetworkRequests:0,liveSqlMutations:0,
 sourceApprovedForCopiedSnapshot:true,generatedPlanApproved:true,privateAdapterReviewPending:true,
 cashBasisScenariosExcluded:true,authenticatedNativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,
 decision:'The live owner may bind the exact plan68/cash10 and three current copies to its separately reviewed A3 adapter. Execution remains conditional on fresh source/quiescence/function checks, original date/authority expiry, cumulative caps and the adapter review.'};
const bytes=Buffer.from(JSON.stringify(report,null,2)+'\n'),destination=path.join(folder,'finance-a3-independent-source-and-plan-review.json');
await fs.writeFile(destination,bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({approved:true,sourceBindings:68,cashBindings:10,report:{path:path.relative(root,destination).replaceAll('\\','/'),bytes:bytes.length,sha256:sha(bytes)}})+'\n');
