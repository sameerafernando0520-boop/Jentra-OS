import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const output='docs/verification/wave5/task3-export-independent-20261014/';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const bindings=new Map(),checks=[],reviewedAt=new Date().toISOString();
function read(relative,expected){
 assert.ok(!path.isAbsolute(relative)&&!relative.split('/').includes('..'),'relative public workspace evidence only');
 const bytes=fs.readFileSync(path.join(root,relative));const binding={path:relative,bytes:bytes.length,sha256:sha(bytes)};
 if(expected){assert.equal(binding.sha256,expected.sha256??expected,'input hash drift: '+relative);
  if(expected.bytes!==undefined)assert.equal(binding.bytes,expected.bytes);}
 if(bindings.has(relative))assert.deepEqual(binding,bindings.get(relative));else bindings.set(relative,binding);return bytes;
}
const json=(relative,expected)=>JSON.parse(read(relative,expected));
function write(relative,value){
 assert.ok(relative.startsWith(output),'only additive review files are owned');
 const bytes=Buffer.from(typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
 fs.writeFileSync(path.join(root,relative),bytes,{flag:'wx'});return {path:relative,bytes:bytes.length,sha256:sha(bytes)};
}
function check(name,operation){try{operation();checks.push({name,passed:true});}catch(error){checks.push({name,passed:false,failure:error.message});}}
const previousPath=output+'export-budget-day-independent-review-a2.json';
const decisionPath='docs/verification/wave5/task3-completion-20261013/export-continuation-technical-decision-20261014-a2.json';
const previous=json(previousPath,'7564bc4564fcbf1e68af2484373d3bd4571a2694c57f94d2633fbb88518a308b');
const priorValidation=json(output+'verifier-result-a2.json','2365f146f7a1c1f000f93ce50e7e79cbfc5c953e36d67e55dffb25a796d8a2fb');
const decision=json(decisionPath,'493f4e266bf1c427f4830a224f712f8869df22734855d6359e28a5547bd555d1');
const oldDecision=json(decision.successorOf.path,decision.successorOf);
const budget=json('docs/verification/wave5/task3-export-continuation-20261014/budget-feasibility.json',
 '1124bf1696224f1d62863a7f043990811fde953bae7703a40171fe75598855ec');
const preservation=json('docs/verification/wave5/task3-export-continuation-20261014/source-preservation-manifest.json',
 '32c05b20eb25905e0b82acd6861e164e82780cdab374133b333eb2d3b0f152a2');
const readiness=json(previous.readiness.newMetadata.path,previous.readiness.newMetadata);
const accounting=json(previous.readiness.readAccounting.path,previous.readiness.readAccounting);
read(previous.readiness.newRefreshProof.path,previous.readiness.newRefreshProof);

check('prior passing independent budget review and original records are preserved and reused explicitly',()=>{
 assert.equal(previous.passed,true);assert.equal(priorValidation.passed,true);assert.equal(priorValidation.checksPassed,13);
 assert.equal(priorValidation.checksTotal,13);assert.equal(priorValidation.report.sha256,bindings.get(previousPath).sha256);
 read(priorValidation.markdown.path,priorValidation.markdown);read(priorValidation.verifier.path,priorValidation.verifier);
 assert.equal(previous.originalApprovalAndPlansUntouched,true);assert.equal(previous.historicalManifestOverwritten,false);
 assert.equal(previous.personalHumanSignatureClaimed,false);
});
check('all directly cited source-only decision records match exact recorded hashes',()=>{
 for(const binding of decision.evidence)read(binding.path,binding);
 assert.equal(decision.successorOf.sha256,previous.readiness.sourceOnlyDecision.sha256);
 assert.equal(decision.successorOf.maximumCumulativeAttemptLimit,156);
 assert.equal(decision.sourceImplementationAuthorized,true);assert.equal(decision.liveExecutionAuthorizedByThisDecision,false);
 assert.equal(decision.personalHumanExactSourceSignatureClaimed,false);
});
check('all 32 unchanged original audit inputs remain current and the declared A9 adapter successor remains exact',()=>{
 assert.equal(preservation.sourceBindingsBefore.length,33);assert.deepEqual(preservation.sourceBindingsBefore,preservation.sourceBindingsAfter);
 const adapter=previous.declaredReadinessAdapterSuccessor;assert.ok(adapter);
 for(const binding of preservation.sourceBindingsBefore.filter(row=>row.path!==adapter.path))read(binding.path,binding);
 read(adapter.currentA9Binding.path,adapter.currentA9Binding);read(adapter.sourceRecord.path,adapter.sourceRecord);read(adapter.helper.path,adapter.helper);
 assert.equal(adapter.exactInverseReproducesOriginalAuditHash,true);
 assert.equal(adapter.originalAuditBinding.sha256,preservation.sourceBindingsBefore.find(row=>row.path===adapter.path).sha256);
});
check('actually charged 131 remains separate from one conditional future readiness charge',()=>{
 assert.equal(previous.accounting.currentConservativePriorAfterRecordedA9,131);
 assert.equal(previous.accounting.actualA3Attempts,50);assert.equal(previous.accounting.stoppedA3Total,128);
 assert.equal(previous.accounting.pipelineInvestigation,1);assert.equal(previous.accounting.attributedA8OwnerRefresh,1);
 assert.equal(previous.accounting.actualNewReadinessRefreshAttemptsRecorded,1);
 assert.equal(40+35+3+50+1+1+1,131);
 assert.equal(decision.preservedPriorBeforeNewRefresh,131);assert.equal(decision.requiredAdditionalReadOnlyOwnerRefreshAttempts,1);
 assert.equal(decision.priorConservativeBoundAfterRequiredRefresh,132);
 assert.equal(decision.originalAttemptCountersReset,false);assert.equal(decision.attemptedAndFailedRequestsChargedBeforeDispatch,true);
});
check('new arithmetic transparently retains 24 ordinary calls and one read-only uncertainty resolution within maximum 157',()=>{
 assert.equal(decision.ordinaryContinuationAttempts,24);assert.equal(decision.ordinaryCumulativeLimit,156);
 assert.equal(decision.reservedReadOnlyResolutionAttempts,1);assert.equal(decision.maximumCumulativeAttemptLimit,157);
 assert.equal(132+24,156);assert.equal(132+24+1,157);assert.equal(decision.explicitAdditionalCeiling,7);
 assert.equal(decision.originalConcreteCumulativeCap,150);assert.equal(157-150,7);
 assert.equal(decision.transportRetries,0);assert.equal(decision.unlistedCallsAllowed,0);
 assert.equal(decision.reservedResolution.maximumAttempts,1);assert.equal(decision.reservedResolution.automaticRetry,false);
});
check('future fixed A10 metadata is conditional and no proof, refresh or future observation is fabricated',()=>{
 const expected={metadataPath:'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json',
  refreshPath:'docs/verification/wave5/private-owner-scope-refresh-20261014-r5-a10.json',
  accountingPath:'docs/verification/wave5/finance-cumulative-read-accounting-20261014-r5-a6.json'};
 for(const [key,value] of Object.entries(expected))assert.equal(decision.futureFreshScope[key],value);
 assert.equal(decision.futureFreshScope.proofExistsOrRequestAlreadyPerformedClaimed,false);
 assert.equal(decision.futureFreshScope.exactHashesMustBeBoundInFinalGeneratedPlan,true);
 assert.equal(decision.futureFreshScope.refreshOnlyAfterSourceAndIndependentReviewReady,true);
 assert.equal(decision.futureFreshScope.numberOfReadinessRequestsAuthorizedForThisSuccessor,1);
 assert.equal(decision.futureFreshScope.anyFailureOrAdditionalRefreshRequiresNewTransparentAccountingAndReview,true);
 for(const value of Object.values(expected))assert.equal(fs.existsSync(path.join(root,value)),false,'future public proof already exists: successor must bind actual bytes');
});
check('A9 is now expired and cannot be substituted while original authority expiry remains unchanged',()=>{
 assert.equal(readiness.createdAt,'2026-10-14T03:53:48.705Z');assert.equal(readiness.expiresAt,'2026-10-14T05:53:48.705Z');
 assert.ok(Date.parse(reviewedAt)>Date.parse(readiness.expiresAt));
 assert.equal(decision.expiredPredecessorMetadata.expiresAt,readiness.expiresAt);
 assert.equal(decision.expiredPredecessorMetadata.eligibleForExecution,false);
 assert.equal(decision.expiredPredecessorMetadata.sha256,previous.readiness.newMetadata.sha256);
 assert.equal(decision.originalRuntimeExpiryUnchanged,'2026-10-14T09:57:07.481942Z');assert.equal(decision.runtimeExpiryExtensionAuthorized,false);
 assert.ok(Date.parse(reviewedAt)<Date.parse(decision.originalRuntimeExpiryUnchanged),'original authority expired: no source review may extend it');
});
check('business scope, exact source, receipt reconciliation, sessions and all ordered calls are unchanged from prior decision',()=>{
 for(const key of ['projectId','runtimeBundleSha256','exactSource','requiredBefore','requiredAfter','ordinaryCallInventory','reservedResolution',
  'permittedExportRpcNames','onlyPermittedBusinessCommands','genuineSessionChecksRetained','freshScopeRequirements',
  'maximumRunMs','maximumSingleRequestMs','ordinaryDispatchResolutionReserveMs','originalFixtureUtcDay','requiredActualExportUtcDay',
  'privateOrLiveOperationsOwnedBy','registeredStatementReopenClaimed','statementFreshPageAndPreviewCsvReproductionRequired'])
  assert.deepEqual(decision[key],oldDecision[key],key);
 assert.equal(decision.ordinaryCallInventory.length,24);
 assert.deepEqual(decision.ordinaryCallInventory.map(row=>row.ordinal),Array.from({length:24},(_,i)=>i+1));
 assert.ok(decision.ordinaryCallInventory.every(row=>row.attempts===1&&row.automaticRetries===0));
 assert.equal(decision.ordinaryCallInventory.filter(row=>row.route==='api.record_report_export').length,2);
 assert.equal(decision.previouslyCompletedDateCommandsReexecuted,false);assert.equal(decision.oldUncertainCommandReplayed,false);
 assert.equal(decision.dateScenarioModelDeliveryOrSchemaWritesAuthorized,false);
});
check('UTC14 export day, UTC13 fixture day, exact two original registrations and decimals remain unchanged',()=>{
 assert.equal(reviewedAt.slice(0,10),'2026-10-14');assert.equal(decision.originalFixtureUtcDay,'2026-10-13');
 assert.equal(decision.requiredActualExportUtcDay,'2026-10-14');
 assert.deepEqual(decision.exactSource.exportIds,previous.exactExportScope.originalIds);
 assert.deepEqual(decision.onlyPermittedBusinessCommands,decision.exactSource.exportIds);
 assert.deepEqual(decision.exactSource.pipelineRows,previous.exactExportScope.decimalRowsUnchanged);
 assert.equal(decision.exactSource.pipelineId,previous.exactExportScope.immutablePipelineId);
 assert.equal(decision.exactSource.pipelineSourceBasisHash,previous.exactExportScope.pipelineSourceBasisHash);
 assert.equal(decision.exactSource.statementId,previous.exactExportScope.originalStatementId);
 assert.equal(decision.exactSource.fixtureDatesOrAmountsModified,false);assert.equal(decision.sourceOrAmountsOrCurrenciesOrExistingIdsChanged,false);
 assert.equal(decision.registeredStatementReopenClaimed,false);
});
check('original human runtime scope remains maximum eight exports with untouched concrete150 and no new personal signature',()=>{
 const runtime=json(budget.originalAuthorization.runtimePacket.path,budget.originalAuthorization.runtimePacket);
 const owner=json(budget.originalAuthorization.ownerDecision.path,budget.originalAuthorization.ownerDecision);
 const concrete=json(budget.originalAuthorization.concreteOriginalFinancePlan.path,budget.originalAuthorization.concreteOriginalFinancePlan);
 assert.equal(runtime.bootstrap.sourceFixtureLimits.runtimeOnly.governedExports,8);assert.equal(owner.decision,'approve');
 assert.equal(concrete.maximumTotalWorkflowRequestAttempts,150);assert.equal(decision.originalHumanApprovalAndConcrete150PlanPreserved,true);
 let numeric150=0;const walk=value=>{if(value===150)numeric150++;if(value&&typeof value==='object')Object.values(value).forEach(walk);};
 walk(runtime);assert.equal(numeric150,0);assert.equal(previous.originalAuthorization.explicitNumeric150InHumanRuntimePacket,false);
});
check('the previously reviewed identical consolidated query remains exact and no database validation is invented',()=>{
 const before=budget.consolidatedEvidenceQueries.before,after=budget.consolidatedEvidenceQueries.after;
 assert.equal(before.query,after.query);assert.equal(sha(before.query),'f0783ac9e8b2041f2566c0fa64e8616d65c9fd2246f0a1809a36f4ce23f3b291');
 assert.equal(before.sha256,after.sha256);assert.equal(before.sha256,previous.queryReview.exactConsolidatedSqlSha256);
 assert.equal(previous.queryReview.beforeAndAfterIdentical,true);assert.equal(previous.queryReview.readOnlySingleStatement,true);
 assert.deepEqual(previous.queryReview.knownBlockingQuerySourceDefects,[]);assert.equal(previous.queryReview.databaseExecutionOrSyntaxValidationPerformed,false);
 assert.ok(previous.queryReview.activityBoundary.includes('momentary'));assert.equal(budget.consolidatedEvidenceQueries.networkExecutions,0);
});
check('remaining expiry, final metadata binding, resolution, private adapter and exclusive intent gates remain explicit',()=>{
 assert.equal(decision.maximumRunMs,900000);assert.equal(decision.maximumSingleRequestMs,45000);
 assert.equal(decision.ordinaryDispatchResolutionReserveMs,45000);assert.equal(decision.serverDayAndExpiryCheckedBeforeWrites,true);
 assert.equal(decision.freshScopeRequirements.finalMetadataAndRefreshHashesBoundInGeneratedPlan,true);
 assert.equal(decision.freshScopeRequirements.expiredOrMismatchedMetadataRejectedBeforePrivateUnsealOrRequest,true);
 assert.ok(decision.executionPrerequisites.includes('one new charged readiness refresh with public proof'));
 assert.ok(decision.executionPrerequisites.includes('primary review of the generated plan and exact private adapter delta'));
 assert.ok(decision.executionPrerequisites.includes('exclusive new export-only once intent'));
 assert.equal(decision.targetScaleLoad,false);assert.equal(decision.productionReleaseReady,false);
});
read(output+'verify_budget_day_review_a3.mjs');
check('all source and evidence bindings remain unchanged throughout this source-only successor review',()=>{
 for(const binding of bindings.values())assert.equal(sha(fs.readFileSync(path.join(root,binding.path))),binding.sha256,binding.path);
});

const passed=checks.every(row=>row.passed);
const report={kind:'independent-source-only-export-budget-and-utc-day-review-conditional-A10-successor',reviewedAt,
 reviewer:'/root/requirement_acceptance',projectId:decision.projectId,passed,checks,
 sourceOnlyVerdict:passed?'supports exact source-only ceiling157 and UTC14 export-day successor, conditional on one actual fresh A10 readiness proof and all separate final execution gates':'review failed; preserve this result and resolve the recorded input or scope issue before any private use',
 originalApprovalAndPlansUntouched:true,acceptanceMatrixEdited:false,personalHumanSignatureClaimed:false,newHumanApprovalInvented:false,
 technicalAmendmentGrantedByThisReview:false,liveExecutionAuthorizedByThisReview:false,
 sourceOnlyDecision:bindings.get(decisionPath),previousIndependentReview:bindings.get(previousPath),previousVerification:bindings.get(output+'verifier-result-a2.json'),
 accounting:{conservativeFirstAttempt:40,observedResume:35,stoppedA2Reads:3,priorA3:78,actualA3Attempts:50,stoppedA3Total:128,
  pipelineInvestigation:1,attributedA8OwnerRefresh:1,actualRecordedA9Refresh:1,currentActuallyChargedPrior:131,
  requiredFutureReadinessRefreshAttempts:1,priorConservativeBound:132,priorBoundIsConditionalOnRecordedFutureRefresh:true,
  ordinaryFutureCalls:24,ordinaryMaximum:156,readonlyResolutionReserve:1,requiredTotalMaximum:157,deltaFromOriginalConcrete150:7,
  oldConcreteCapPreserved:150,disappearingOrResetCallsAllowed:false,automaticRetriesAllowed:0,
  anyAdditionalRefreshRequiresNewExplicitAccountingAndReview:true},
 readiness:{sourceOnlyDecision:bindings.get(decisionPath),oldA8MayBeReused:false,oldA9MayBeReused:false,
  expiredA9Metadata:bindings.get(previous.readiness.newMetadata.path),expiredA9RefreshProof:bindings.get(previous.readiness.newRefreshProof.path),
  currentReadAccounting:bindings.get(previous.readiness.readAccounting.path),expiredA9At:readiness.expiresAt,
  recordedOriginalRuntimeAuthorityExpiresAt:decision.originalRuntimeExpiryUnchanged,authorityExtensionAllowed:false,
  futureScope:decision.futureFreshScope,futureMetadataOrRefreshProofExistsOrClaimed:false,actualFutureRefreshPerformedByThisReview:false,
  currentActualReadinessUsable:false,allFutureProofHashesPending:true,
  beforeAnyPrivateExportUnsealOrRequest:[
   'Exactly one independently reviewed fresh readiness GET must actually complete and be charged, with additive A10 public metadata, refresh proof and cumulative accounting. A failed or uncertain attempt stays charged; this review supplies no retry authority.',
   'Actual future metadata/refresh/accounting bytes must be pinned into the generated source-bound plan and separately reviewed final operation gate before private unseal or any export request. No future timestamp or expected hash is fabricated here.',
   'Validate the actual project, bundle, current SID, creation time and the earliest metadata/original-runtime/run expiry. Reject old A8/A9, expired or mismatched metadata before private use.',
   'Check local UTC14 before private unseal and actual server UTC14 in the charged consolidated preflight before session/export work. Preserve UTC13 fixture facts.',
   'Retain the 15-minute run, 45-second request deadline and one 45-second conditional read-only receipt-resolution window. Stop on failure, expiry, evidence failure or day drift without unlisted calls or replay.',
   'The generated plan, exact adapter/source changes, controlled tests and exclusive new export-only intent still require root/operation-owner review. This source record does not authorize live execution.'
  ]},
 exactExportScope:previous.exactExportScope,queryReview:{...previous.queryReview,queryBytesRechecked:true,previousFullQueryReviewExplicitlyReused:true,
  databaseExecutionOrSyntaxValidationPerformed:false},
 sourcePreservation:{originalManifest:bindings.get('docs/verification/wave5/task3-export-continuation-20261014/source-preservation-manifest.json'),
  originalInputPopulation:33,originalInputsCurrentUnchanged:32,declaredA9AdapterCurrent:previous.declaredReadinessAdapterSuccessor,
  original68ConsumedSourceAnd37PriorEvidenceVerificationReusedFromExactPassingA2Record:true,
  oldConsumedSourceCopiesReexecutedOrRewritten:false,historicalManifestOverwritten:false},
 sourceBindings:[...bindings.values()],sourceBindingsUnchangedDuringReview:true,
 actualProjectApiRequests:0,privateCredentialFilesRead:false,liveOrPrivateWrites:0,SDKJobs:0,
 liveExportAcceptanceAdded:0,targetScaleLoadClaimed:false,productionReleaseReady:false,
 limitations:[
  '132 is the conditional pre-export base after one actual future charge; current recorded prior is131. The review does not claim a future readiness GET or future public proof already happened.',
  'The a1 failed audit, passing a2 budget review, old150 plans and charged A8/A9 records remain intact. This new source-only report does not reset them.',
  'The consolidated SQL remains source-reviewed and was not executed here. pg_stat_activity is momentary, not continuing quiescence; preserve both immediate before-registration queries and live-owner coordination.',
  'This independent review decides source feasibility only. Actual private provider configuration, generated plan, final adapter, exclusive intent and live operation remain separately owned. No new human signature, authentication evidence, export success, native acceptance, load acceptance or release follows.'
 ]};
const reportRef=write(output+'export-budget-day-independent-review-a3.json',report);
const mdRef=write(output+'export-budget-day-independent-review-a3.md',[
 '# Independent export budget and UTC day successor','',
 'The source-only successor supports a maximum of **157 cumulative attempts**, conditional on exactly one actual fresh A10 readiness check and the existing final execution gates. The recorded prior is **131**. A9 expired on October 14, 2026 at 05:53:48.705 UTC; it cannot be reused. No A10 request, future metadata or future timestamp is claimed by this review.','',
 '| Accounting | Attempts |','|---|---:|','| Already charged conservative prior, including A8 and A9 | 131 |',
 '| Exactly one conditional future readiness refresh | 1 |','| Conditional pre-export base | 132 |',
 '| Ordinary continuation calls | 24 |','| Ordinary cumulative maximum | 156 |','| Conditional read-only receipt resolution | 1 |',
 '| Required maximum | **157** |','',
 'The delta is seven above the untouched concrete 150 plan. Every failed or attempted request remains charged. The original human runtime scope still permits at most eight governed exports; this successor retains only the two original registration commands, IDs, actors and data. No date, scenario, model, delivery or schema command is added.','',
 'Actual export day remains October 14 UTC; the original fixture day stays October 13. All source hashes, amounts and separate currency rows remain exact. The statement keeps its distinct-session page/preview and CSV reproduction; registered statement reopen and native save/download are not claimed.','',
 'The earlier passing review is reused explicitly. The 32 unchanged audit inputs and recorded A9 adapter successor still match actual bytes. The identical consolidated query digest remains f0783ac9e8b2041f2566c0fa64e8616d65c9fd2246f0a1809a36f4ce23f3b291. Its original full source review is preserved; no database syntax or execution claim is added.','',
 'The actual A10 metadata, refresh proof and cumulative accounting must exist and have their exact hashes bound into the generated plan and final operation review before private unseal or request. Preserve the earliest metadata expiry, the 15-minute run and 45-second request/resolution windows. Original authority still expires at **09:57:07.481942 UTC**, without extension. Any failed or additional refresh requires transparent successor accounting and review.','',
 'This is a conditional technical source review. It grants no live execution authority, personal human signature, requirement acceptance, native/load result or production release claim. No project API request, private credential operation or SDK job was performed.','',
 `Exact review: ${reportRef.path} (SHA-256 ${reportRef.sha256}).`,''].join('\n'));
const result=write(output+'verifier-result-a3.json',{kind:'independent-export-budget-day-conditional-successor-verification',verifiedAt:new Date().toISOString(),
 passed,checksPassed:checks.filter(row=>row.passed).length,checksTotal:checks.length,checks,report:reportRef,markdown:mdRef,
 verifier:bindings.get(output+'verify_budget_day_review_a3.mjs'),sourceBindingsUnchanged:true,networkCalls:0,privateCredentialsRead:false,SDKJobs:0});
console.log(JSON.stringify({passed,checksPassed:checks.filter(row=>row.passed).length,checksTotal:checks.length,
 failures:checks.filter(row=>!row.passed),report:reportRef,markdown:mdRef,verifierResult:result,checkedBindings:bindings.size,
 currentChargedPrior:131,conditionalPrior:132,maximum157Conditional:true}));
if(!passed)process.exitCode=1;
