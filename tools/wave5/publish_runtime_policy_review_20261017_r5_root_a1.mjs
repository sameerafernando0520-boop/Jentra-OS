// Local technical policy publication only. No execution authority is created.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import * as E from './finance_exports_20261016_r5_a7.mjs';
import * as R from './renew_runtime_authority_20261015_r5_a1.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),own='docs/verification/wave5/root-runtime-review-20261017/';
const hash=x=>createHash('sha256').update(x).digest('hex'),slim=({path,sha256})=>({path,sha256});
async function exact(row){const target=path.resolve(root,row.path);assert.equal(await fs.realpath(target),target);const bytes=await fs.readFile(target);assert.equal(hash(bytes),row.sha256,row.path);if(row.bytes!==undefined)assert.equal(bytes.length,row.bytes);return bytes;}
async function absent(file){try{await fs.lstat(path.join(root,file));throw Error('EXCLUSIVE_SOURCE_OUTPUT_OR_ABSENT_ACTUAL_REQUIRED:'+file);}catch(error){if(error.code!=='ENOENT')throw error;}}
const bundleBinding={path:own+'operation-bundle.draft-a1.json',sha256:'7b196512d368a4ac39f7113c0d5b04c21178cf0779179caf1f1f9fd8418d04de'};
const draftBinding={path:own+'source-policy.draft-a1.json',sha256:'fddf8cab9460aa590889468fc0bcd693a857697a6da8ffe6e24e3b14b6665813'};
const bundle=JSON.parse(await exact(bundleBinding)),draftBytes=await exact(draftBinding),policy=JSON.parse(draftBytes);
assert.equal(bundle.sourceOnly,true);assert.equal(bundle.approvalRecorded,false);assert.equal(bundle.executionPermitted,false);
assert.equal(bundle.actualPriorCharge,137);assert.equal(bundle.actualStateObservedAt,'2026-10-16T12:13:25.833347+00:00');
assert.equal(bundle.sourceAndEvidenceBindings.length,189);assert.equal(new Set(bundle.sourceAndEvidenceBindings.map(x=>x.path)).size,189);
for(const row of bundle.sourceAndEvidenceBindings)await exact(row);
assert.equal(bundle.preservedOriginalSnapshotBindings.length,68);assert.equal(bundle.deployedV7ArchiveBindings.length,39);
assert.equal(bundle.productDeploymentAuthorized,false);assert.equal(bundle.maximumWindowMs,7200000);
assert.deepEqual(bundle.proposedBudget,{actualPrior:137,ownerRefresh:1,renewal:3,priorAtExports:141,exportsOrdinary:24,exportsResolutionReserve:1,throughExportsMaximum:166,healthMaximum:5,throughHealthMaximum:171,schedulerMaximum:3,overallMaximum:174,maximumFutureAttempts:37});
assert.equal(bundle.decisions.scheduler.mayNotBePreauthorizedNow,true);assert.equal(bundle.decisions.scheduler.decisionAtOrAfterActualRenewalApplication,true);
assert.equal(bundle.decisions.health.mustBeDecidedBeforeActualRenewalApplication,true);
const preserved=JSON.parse(await fs.readFile(path.join(root,'docs/verification/wave5/task3-export-renewal-20261016/export-a7-source-proof-a1.json'),'utf8'));
assert.equal(policy.kind,'source-only-export-a7-renewal-policy');assert.equal(policy.intendedPublishedPath,E.EXPORTS_PROFILE_PATHS.sourcePolicy);
assert.equal(policy.projectId,R.PROJECT);assert.equal(policy.runtimeId,R.RUNTIME);assert.equal(policy.runtimeBundleSha256,R.BUNDLE);
assert.equal(policy.sourceImplementationOnly,true);assert.equal(policy.liveExecutionAuthorized,false);assert.equal(policy.executionPermitted,false);
assert.equal(policy.ownerApprovalRecorded,false);assert.equal(policy.originalConcreteCumulativeCap,150);assert.deepEqual(policy.budget,E.EXPORTS_REVIEWED_BUDGET);
assert.equal(policy.windowMode,'server-clock-at-application');assert.equal(policy.maximumWindowMs,E.EXPORTS_MAX_WINDOW_MS);assert.deepEqual(policy.originalWindow,E.EXPORTS_ORIGINAL_WINDOW);
assert.deepEqual(policy.dependencyBinding,E.EXPORTS_DEPENDENCY);assert.deepEqual(policy.currentChargeBinding,E.EXPORTS_CURRENT_CHARGE);
assert.deepEqual(policy.permittedOriginalExportCommands,E.EXPORTS_COMMANDS);assert.equal(policy.originalFixtureUtcDay,'2026-10-13');
assert.deepEqual(policy.a5SourceBindings,E.EXPORTS_A5_SOURCE_BINDINGS);assert.deepEqual(policy.a6SourceBindings,E.EXPORTS_A6_SOURCE_BINDINGS);
assert.equal(policy.preservedOriginalSourceCount,68);assert.equal(policy.consolidatedSqlSha256,E.EXPORTS_SQL_SHA256);
for(const [key,value] of Object.entries({maximumRunMs:900000,maximumRequestMs:45000,ordinaryReserveMs:90000,resolutionReserveMs:45000,transportRetries:0,unlistedCallsAllowed:0}))assert.equal(policy[key],value,key);
assert.equal(policy.schedulesMustRemainPaused,true);assert.equal(policy.onlyTwoExpiryFieldsMayChange,true);
assert.equal(policy.renewalOperationBundleSha256,bundleBinding.sha256);assert.deepEqual(policy.operationBundleBinding,bundleBinding);
assert.deepEqual(policy.exportSourceBindings,preserved.sources.map(slim));assert.deepEqual(policy.renewalSqlBindings,R.SQL_BINDINGS);
assert.deepEqual(policy.renewalProposalBinding,{path:R.CONTROL_PATHS.proposal,sha256:R.STATIC_HASHES.proposal});
assert.deepEqual(policy.renewalSourceRepairBinding,{path:R.CONTROL_PATHS.sourceRepair,sha256:R.STATIC_HASHES.sourceRepair});
const staticReviewBinding=bundle.sourceReviews.find(x=>x.name==='Renewal controller');assert.ok(staticReviewBinding);
const staticReview=JSON.parse(await exact(staticReviewBinding));assert.equal(staticReview.passed,true);assert.equal(staticReview.executionPermitted,false);
assert.deepEqual(policy.renewalControllerSourceBindings,staticReview.sourceBindings);
for(const row of bundle.sourceReviews){const review=JSON.parse(await exact(row));assert.equal(review.passed,true);}
for(const row of bundle.localPreparationOnlyAfterExactApproval.newSnapshotFiles){assert.equal(row.creationMode,'wx');await absent(row.target);}
await absent(bundle.localPreparationOnlyAfterExactApproval.managementAdapter.target);
for(const file of [E.EXPORTS_PROFILE,E.EXPORTS_FINAL_REVIEW,E.EXPORTS_PLAN,E.EXPORTS_ONCE,E.EXPORTS_PROFILE_PATHS.ownerDecision,E.EXPORTS_PROFILE_PATHS.renewalReadback,E.EXPORTS_PROFILE_PATHS.metadata,E.EXPORTS_PROFILE_PATHS.refresh,E.EXPORTS_PROFILE_PATHS.accounting,R.PLAN,R.REVIEW,R.ONCE])await absent(file);
const target=E.EXPORTS_PROFILE_PATHS.sourcePolicy,reviewTarget=E.EXPORTS_PROFILE_PATHS.independentReview;
await absent(target);await absent(reviewTarget);
const review={kind:'independent-export-a7-policy-review',reviewedAt:new Date().toISOString(),passed:true,sourceOnly:true,liveExecutionAuthorized:false,
 policyBinding:{path:target,sha256:draftBinding.sha256},exportSourceBindings:policy.exportSourceBindings,budget:policy.budget,currentChargeBinding:policy.currentChargeBinding,
 renewalOperationBundleSha256:bundleBinding.sha256,exactConsolidatedSqlSha256:E.EXPORTS_SQL_SHA256,
 renewalControllerSourceBindings:policy.renewalControllerSourceBindings,renewalSqlBindings:policy.renewalSqlBindings,
 operationManifestBinding:bundleBinding,reviewedInputBindings:189,preservedOriginalSnapshotBindings:68,preservedDeployedArchiveBindings:39,
 sourceReviews:bundle.sourceReviews,reviewNotes:[
 'Exact new policy values match the frozen export and controller interfaces and all 189 source/evidence files match their hashes.',
 'The publication preserves the source-only proposal flags. No approval, authority or successful runtime observation is inferred.',
 'Renewal/export and single paused-schedule health decisions are separate. Scheduler requires its later actual-window decision; a reply now cannot satisfy it.',
 'After exact approval only the six absent snapshot files and two reviewed adapter installations are proposed; original68 sources, consumed intents, accounts and sessions remain preserved.'
 ],networkCalls:0,privateInputsRead:false,ownerDecisionCreated:false,actualOwnerRefreshPerformed:false,actualRenewalPerformed:false,actualExports:0,
 executionPermitted:false,acceptanceChanged:false,production:false,realBilling:false};
await fs.writeFile(path.join(root,target),draftBytes,{flag:'wx'});
await fs.writeFile(path.join(root,reviewTarget),JSON.stringify(review,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({passed:true,publishedPolicy:{path:target,sha256:hash(draftBytes)},independentPolicyReview:{path:reviewTarget,sha256:hash(JSON.stringify(review,null,2)+'\n')},operationBundleSha256:bundleBinding.sha256,bindingsVerified:189,networkCalls:0,privateInputsRead:false,executionPermitted:false})+'\n');
