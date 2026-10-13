import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';

// Offline peer review of the preserved first remaining-finance snapshot.
// No main(), private input, HTTP client, SDK, SQL or subprocess is invoked.
const root=fileURLToPath(new URL('../../../',import.meta.url));
const snapshot=path.join(root,'build/wave5-approved-execution-20261013-r5-a2');
const base='docs/verification/wave5/';
const out=base+'finance-remaining-independent-source-review-20261013-r5-a1';
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const inputs=new Map(),checks=[];
const read=async(relative,{snapshotFile=false,expected}={})=>{
  const absolute=path.join(snapshotFile?snapshot:root,relative),bytes=await fs.readFile(absolute);
  if(expected)assert.equal(sha(bytes),expected,'Unexpected review input: '+relative);
  inputs.set(absolute,{path:path.relative(root,absolute).replaceAll('\\','/'),sha256:sha(bytes)});
  return bytes;
};
const check=(name,fn)=>{fn();checks.push({name,passed:true});};
const manifestRelative=base+'approved-isolated-execution-snapshot-20261013-r5-a2.json';
const manifest=JSON.parse(await read(manifestRelative,{expected:'9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01'}));
const planRelative=base+'finance-remaining-preparation-20261013-r5-a1.json';
const planBytes=await read(planRelative,{snapshotFile:true,expected:'7b8bc312ebcb7e3389e3dbd358d988e3d417ca1149c221e0eb81800215540d2e'});
const plan=JSON.parse(planBytes);
check('isolated snapshot preserves concurrent workspace changes without claiming current original closure',()=>{
  assert.equal(manifest.executionRootRelative,'build/wave5-approved-execution-20261013-r5-a2');
  assert.equal(manifest.approvedBindingCount,5539);assert.equal(manifest.uniqueApprovedFileCount,5468);
  assert.equal(manifest.originalFullApprovalGuardPassed,true);
  assert.equal(manifest.currentWorkspaceIsExactApprovedBundle,false);
  assert.equal(manifest.concurrentChangesPreserved,true);assert.equal(manifest.additionalSourceApprovalImplied,false);
});
check('preserved preparation has exactly58 unique public source/evidence bindings',()=>{
  assert.equal(plan.sourceBindings.length,58);assert.equal(new Set(plan.sourceBindings.map(row=>row.path)).size,58);
  assert.equal(plan.priorEvidenceBindings.length,35);
  assert.equal(plan.projectId,'xpdoufauvrbdmxgngetv');
  assert.equal(plan.bundleSha256,'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b');
});
for(const binding of plan.sourceBindings){
  assert.equal(path.isAbsolute(binding.path),false);assert.equal(binding.path.includes('..'),false);
  await read(binding.path,{snapshotFile:true,expected:binding.sha256});
  checks.push({name:'snapshot byte binding: '+binding.path,passed:true});
}
const mainBinding=plan.sourceBindings.find(row=>row.path==='tools/wave5/finance_remaining_20261013_r5.mjs');
const source=(await read(mainBinding.path,{snapshotFile:true,expected:mainBinding.sha256})).toString();
const helper=await import(pathToFileURL(path.join(snapshot,mainBinding.path)).href);
const legacy=await import(pathToFileURL(path.join(snapshot,'tools/wave5/finance_cash_workflows_20261013_r5.mjs')).href);
const fixture=await import(pathToFileURL(path.join(snapshot,'tools/wave5/finance_cash_fixture_20261013_r5.mjs')).href);
const transport=await import(pathToFileURL(path.join(snapshot,'tools/wave5/finance_https_transport_20261013_r5_a2.mjs')).href);
const preservedStop=JSON.parse(await read(base+'finance-remaining-preparation-stop-20261013-r5-a1.json'));
const logBytes=await read(base+'finance-remaining-root-local-tests-20261013-r5-a1.log',{expected:'bac844fb163d2703e6070c8a721479b253fd7de8334445aa83ed7dce38c42074'});
check('original24 passing unit tests precede preserved preparation failure; no live execution occurred',()=>{
  assert.match(logBytes.toString(),/# tests 24/);assert.match(logBytes.toString(),/# pass 24/);
  assert.match(logBytes.toString(),/# fail 0/);assert.match(logBytes.toString(),/# skipped 0/);
  assert.equal(preservedStop.privateExecution,false);assert.equal(preservedStop.liveWrites,false);
  assert.equal(preservedStop.planWritten,false);assert.equal(preservedStop.preparationFailure,'APPROVED_FILE_CHANGED');
});
const clause="FROM workflow.process_events x WHERE tenant_id='"+fixture.FINANCE_SCOPE.tenantId+"'";
const commandList=rows=>rows.map(row=>"'"+row.commandId+"'::uuid").join(',');
check('baseline recipe removes only the five exact append command IDs from the original frozen recipe',()=>{
  assert.equal(helper.REMAINING_BASELINE_SQL.replace(clause+' AND command_id NOT IN ('+commandList(helper.EXPECTED_PROCESS_APPENDS)+')',clause),legacy.FINANCE_FACTS_SQL);
});
check('prior-complete recipe removes only the two new export commands and retains all earlier rows',()=>{
  assert.equal(helper.REMAINING_PRIOR_COMPLETE_SQL.replace(clause+' AND command_id NOT IN ('+commandList(helper.EXPECTED_PROCESS_APPENDS.slice(3))+')',clause),legacy.FINANCE_FACTS_SQL);
});
check('two remaining date kinds and seven read/write RPCs exclude successful and stale workflow commands',()=>{
  assert.deepEqual([...helper.REMAINING_KINDS],['payroll_correction','project_reimbursement']);
  assert.equal(helper.REMAINING_RPCS.length,7);
  for(const rpc of ['generate_financial_statement','wave5_classification_publish','wave5_cash_save','post_manual_journal'])assert.equal(helper.REMAINING_RPCS.includes(rpc),false);
  assert.match(source,/p_command_id!==STALE_COMMAND/);assert.match(source,/exactKeys\(body,/);
});
check('known SQLSTATE/message mapping requires the actual corresponding HTTP status',()=>{
  assert.equal(transport.financeDenial({ok:false,status:500,value:{code:'40001',message:'CASH_DATE_VERSION_CONFLICT'}}),'CASH_DATE_VERSION_CONFLICT');
  for(const status of [400,403,409,502])assert.equal(transport.financeDenial({ok:false,status,value:{code:'40001',message:'CASH_DATE_VERSION_CONFLICT'}}),null);
  assert.equal(transport.financeDenial({ok:false,status:500,value:{code:'XX000',message:'CASH_DATE_VERSION_CONFLICT'}}),null);
  assert.equal(transport.financeDenial({ok:false,status:403,value:{code:'42501',message:'Permission denied or multi-factor authentication required.'}}),'PERMISSION_DENIED');
});
check('request budget retains75 prior reserved/observed attempts plus exactly one resolution slot',()=>{
  const budget=helper.createRemainingBudget({now:()=>0,startedAt:0});
  for(let index=0;index<74;index++)budget.claim();
  assert.equal(budget.snapshot().totalRequestBound,149);assert.throws(()=>budget.claim(),/REMAINING_REQUEST_BOUND_EXCEEDED/);
  budget.claim({resolution:true});assert.equal(budget.snapshot().totalRequestBound,150);
  assert.throws(()=>budget.claim({resolution:true}),/SINGLE_ORIGINAL_READONLY_RESOLUTION_REQUIRED/);
});
check('deadline reserves45 seconds rather than beginning a request in the last deadline interval',()=>{
  let now=855000;const budget=helper.createRemainingBudget({now:()=>now,startedAt:0});budget.claim();
  now=855001;assert.throws(()=>budget.claim(),/REMAINING_EXECUTION_DEADLINE_REQUIRED/);
  assert.equal(budget.snapshot().actualRemainingAttempts,1);
});
const id=legacy.financeWorkflowId;
const body={p_command_id:id('command.date.prepare.payroll_correction'),p_idempotency_key:id('command.date.prepare.payroll_correction'),p_issued_at:'2026-10-13T16:00:00Z',
  p_action:'prepare',p_payload:{id:id('date.payroll_correction'),sourceKind:'payroll_correction',sourceId:id('payroll.recovery'),sourceHash:'a'.repeat(64),dueDate:'2026-10-16',reasonCode:'correction_recovery',expectedVersion:'0'}};
const actor={proof:{actorId:'8b740ab8-24f7-4455-a78b-aea0d99d20f6',aal:'aal2',onlineAuthVerified:true,serverSessionRowVerified:true}};
const appendPrivate=async()=> 'runtime-offline-peer-00000000-0000-4000-8000-000000000000.sealed.json';
const appendPublic=async()=>({path:'offline-peer-receipt.json',sha256:'b'.repeat(64)});
const prepared={value:{command_id:body.p_command_id,entity:{id:body.p_payload.id,status:'prepared',proposalHash:'c'.repeat(64),version:'0'}},responseSha256:'d'.repeat(64)};
const altered={ok:true,value:{command_id:body.p_command_id,entity:{id:body.p_payload.id,status:'approved',proposalHash:'c'.repeat(64),version:'99'}},responseSha256:'e'.repeat(64),evidence:{offlineDouble:true}};
let defectProbeDispatched=0;
// Assert the exact reviewed predicate before reproducing it using controlled values.
assert.ok(source.includes('value.command_id===prepareCommand&&value.entity?.proposalHash===prepared.value.entity.proposalHash'));
const flawedPredicate=value=>assert.ok(value.command_id===body.p_command_id&&value.entity?.proposalHash===prepared.value.entity.proposalHash);
const defectWriter=helper.createRemainingCommandWriter({appendPrivate,appendPublic,planSha256:sha(planBytes),send:async()=>{defectProbeDispatched++;return altered;}});
await defectWriter.write(actor,'wave5_cash_date_command',body,flawedPredicate);
check('source-bound defect probe demonstrates that changed cached fields can pass the preserved replay predicate',()=>{
  assert.equal(defectProbeDispatched,1);assert.notDeepEqual(altered.value,prepared.value);assert.notEqual(altered.responseSha256,prepared.responseSha256);
});
const abort=new AbortController();let cancelledDispatches=0;
const cancelWriter=helper.createRemainingCommandWriter({appendPrivate,appendPublic:async()=>{abort.abort();return appendPublic();},signal:abort.signal,
  planSha256:sha(planBytes),send:async()=>{cancelledDispatches++;return altered;}});
await assert.rejects(cancelWriter.write(actor,'wave5_cash_date_command',body,()=>{}),/REMAINING_COMMAND_JOURNAL_STOPPED/);
check('cancellation during acknowledged public intent prevents transport',()=>assert.equal(cancelledDispatches,0));
check('the preserved source does not claim actual denial/load/native/delivery/acceptance completion',()=>{
  for(const marker of ['actualStaleVersionConflictHttpResponseObserved:false','originalUncertainRequestCauseEstablished:false','authenticatedNative:false',
    'targetScaleLoad:false','actualDelivery:false','ownerAcceptance:false','fullFinanceAndCashGatesComplete:false'])assert.ok(source.includes(marker));
});
for(const [absolute,binding]of inputs)assert.equal(sha(await fs.readFile(absolute)),binding.sha256,'Input changed during review: '+binding.path);
const programRelative=path.relative(root,fileURLToPath(import.meta.url)).replaceAll('\\','/');
const report={kind:'independent-offline-source-review-of-remaining-finance-first-candidate',reviewer:'/root/provider_review_20261013',reviewedAt:new Date().toISOString(),
  projectId:'xpdoufauvrbdmxgngetv',bundleSha256:plan.bundleSha256,verdict:'REPLAY_EQUALITY_DEFECT_REQUIRES_SOURCE_BOUND_SUCCESSOR',passedForLiveExecution:false,
  reviewedSnapshot:{manifest:{path:manifestRelative,sha256:inputs.get(path.join(root,manifestRelative)).sha256},executionRootRelative:manifest.executionRootRelative,
    preparation:{path:path.relative(root,path.join(snapshot,planRelative)).replaceAll('\\','/'),sha256:sha(planBytes)},freshlyVerifiedPlanBindings:58,
    original5539BindingsAreHistoricalManifestEvidence:true,currentSharedCheckoutIsExactApprovedBundle:false,additionalSourceApprovalImplied:false},
  localExecution:{checksPassed:checks.length,checksFailed:0,sourceBoundDefectProbes:1,defectProbeObserved:true,inputHashesStable:true,
    networkRequests:0,sqlQueries:0,sqlMutations:0,sdkCalls:0,privateFilesRead:0,childTestProcesses:0,operationalSourceEdits:0,
    note:'Pure controlled doubles are not authenticated runtime evidence.'},
  priorRootUnitEvidence:{path:base+'finance-remaining-root-local-tests-20261013-r5-a1.log',sha256:sha(logBytes),tests:24,passed:24,failed:0,skipped:0,
    subsequentPreparationStop:base+'finance-remaining-preparation-stop-20261013-r5-a1.json',stop:'APPROVED_FILE_CHANGED',stopPreserved:true},
  findings:[{id:'F-REMAINING-01',severity:'required-correction',path:mainBinding.path,sha256:mainBinding.sha256,
    problem:'The preserved original prepare replay validates only command ID and proposal hash. It can accept changed cached entity fields and different response bytes.',
    actualOfflineProbe:{dispatches:1,acceptedAlteredCachedResponse:true,alteredEntityStatus:'approved',alteredEntityVersion:'99',completeValueEqual:false,responseByteHashesEqual:false},
    requiredCorrection:'Require complete canonical replay.value equality and actual replay.responseSha256 equality with the original prepared response before readback/success. Preserve this candidate; bind a new successor plan and snapshot.',
    runtimeEffectObserved:false}],
  reviewedGuards:{sourceBaselineRecipeExact:true,originalProcessRowsAnd3PriorPlus2ExportAppendsChecked:true,staleCommandNotReplayed:true,
    freshZeroReceiptProposalAndMatchingCashInvocationRequiredBeforeEachWrite:true,actualPgActivityPredicateEvaluated:false,
    distinctExistingMfaActorsRequired:true,tlsAuthorizationCheckedBeforeBodyDispatch:true,privateAndPublicAcknowledgedIntentsBeforeDispatch:true,
    signalRecheckedBeforeTransport:true,onceOnlyExecutionIntent:true,unknownCommandResultRetainsOriginalReceiptResolution:true,
    allowedRemainingWrites:8,cumulativeAttemptCap:150,priorConservativeBound:75,oneResolutionSlotReserved:true,noAutomaticRetry:true},
  evidenceLimits:[
    'Original digests cover journal entries/lines, open items, payroll/correction/reimbursement effects, CRM and process rows; publications, classifications and date contents are counted, not included in that digest.',
    'Only profit/loss is freshly read and compared by this continuation. Other two publications, prior classification and payroll approval are linked through preserved earlier evidence, not freshly revalidated in full.',
    'All-invocation quiescence means the reviewed exact pg_stat_activity predicate and observed instant; it is not a complete trace or transaction-lock proof.',
    'Private file-content sync is source-reviewed; directory-entry or power-loss durability is not independently proved.',
    'The response mapper has a source-grounded HTTP/code/message contract. It does not prove the prior timeout cause or a live stale-version denial.',
    'No full private provider/Pg driver/external observer/native save dialog/xlsx/target-scale load/delivery/owner acceptance verdict is granted.'
  ],checks,sourceBindings:[...inputs.values()],reviewProgram:{path:programRelative,sha256:sha(await fs.readFile(fileURLToPath(import.meta.url)))},
  actualRemainingRuntimeExecutedByReviewer:false,authenticatedNative:false,actualDelivery:false,targetScaleLoad:false,ownerAcceptance:false,acceptedRequirements:3,totalRequirements:109,
  production:false,realBilling:false};
const reportBytes=Buffer.from(JSON.stringify(report,null,2)+'\n');
await fs.writeFile(path.join(root,out+'.json'),reportBytes,{flag:'wx'});
const markdown='# Remaining finance independent source review — preserved first candidate\n\nThe first candidate requires a source-bound successor: its replay validator accepts changed cached fields when command and proposal hashes match. One controlled offline probe demonstrated this. No live write or private input was used.\n\n'+
  'The exact isolated manifest and all 58 preparation bindings passed fresh byte checks. The original 24/24 unit run and subsequent `APPROVED_FILE_CHANGED` stop remain preserved.\n\n'+
  'The continuation preserves the original eight source families and process append identities. Full prior report/classification/date contents are not included in the digest; only profit/loss is freshly reproduced. Earlier evidence remains linked separately.\n\n'+
  'Required correction: compare the complete canonical replay response and its actual response-byte SHA-256 to the original prepare response before readback and success. Rebind a new candidate and snapshot.\n\n'+
  'Authenticated native, xlsx, full provider/contention/load, actual delivery and owner acceptance remain separate. Owner acceptance is 3/109.\n';
await fs.writeFile(path.join(root,out+'.md'),markdown,{flag:'wx'});
process.stdout.write(JSON.stringify({report:out+'.json',sha256:sha(reportBytes),checksPassed:checks.length,defectObserved:true,passedForLiveExecution:false,inputHashesStable:true,networkRequests:0,privateFilesRead:0})+'\n');
