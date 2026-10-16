// Independent controlled public-policy checks only. No actual approval/renewal/profile is written.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {hashBytes} from '../../../../tools/wave5/runtime_contract.mjs';
import {PROJECT,BUNDLE,ORGANIZATION} from '../../../../tools/wave5/approved_management_installer.mjs';
import {FINANCE_SCOPE} from '../../../../tools/wave5/finance_cash_fixture_20261013_r5.mjs';
import {EXPORTS_PROFILE,EXPORTS_A5_SOURCE_BINDINGS,EXPORTS_DEPENDENCY,EXPORTS_REVIEWED_BUDGET,EXPORTS_ORIGINAL_WINDOW,EXPORTS_OWNER_REPLY,EXPORTS_RUNTIME_ID,EXPORTS_PROFILE_PATHS,EXPORTS_PRESERVED_BINDINGS,EXPORTS_SOURCE_PATHS,EXPORTS_COMMANDS,EXPORTS_SQL_SHA256,EXPORTS_PLAN,validateExportsProfile,validateExportsWindow,validateExportsTime,preflightExportsOperation} from '../../../../tools/wave5/finance_exports_20261014_r5_a6.mjs';
import {buildExportsPreparation} from '../../../../tools/wave5/prepare_finance_exports_20261014_r5_a6.mjs';
const stamp='2026-10-14T14:00:00.000Z',now=()=>Date.parse(stamp),digest=hashBytes('controlled-evidence'),clone=structuredClone;
const readJson=file=>fs.readFile(file,'utf8').then(JSON.parse);
const testWindow={notBefore:'2026-10-14T13:30:00.000Z',edgeExpiresAt:'2026-10-14T15:30:00.000Z',scopeExpiresAt:'2026-10-14T15:30:00.000Z',privateExpiresAt:'2026-10-14T15:00:00.000Z',expiresAt:'2026-10-14T15:00:00.000Z'};
async function publicPreparationInputs(){
 const snapshot='build/wave5-approved-execution-20261013-r5-a2/',preserved={};
 for(const [name,binding] of Object.entries(EXPORTS_PRESERVED_BINDINGS))preserved[name]=await readJson(snapshot+binding.path);
 const oldPlan=preserved.a3Plan,sourceBindings=[];
 for(const binding of [...oldPlan.sourceBindings,...Object.values(EXPORTS_PRESERVED_BINDINGS),...EXPORTS_A5_SOURCE_BINDINGS])
  if(!sourceBindings.some(row=>row.path===binding.path))sourceBindings.push(binding);
 const exportSourceBindings=[];
 for(const file of EXPORTS_SOURCE_PATHS){const binding={path:file,sha256:hashBytes(await fs.readFile(file))};sourceBindings.push(binding);exportSourceBindings.push(binding);}
 const controlBindings=Object.fromEntries(Object.entries(EXPORTS_PROFILE_PATHS).map(([name,file])=>[name,{path:file,sha256:digest}]));
 controlBindings.dependency=EXPORTS_DEPENDENCY;
 const sourcePolicy={kind:'source-only-export-a6-renewal-policy',projectId:PROJECT,runtimeBundleSha256:BUNDLE,runtimeId:EXPORTS_RUNTIME_ID,
  sourceImplementationOnly:true,liveExecutionAuthorized:false,originalConcreteCumulativeCap:150,budget:EXPORTS_REVIEWED_BUDGET,
  windowMode:'server-clock-at-application',maximumWindowMs:7200000,originalWindow:EXPORTS_ORIGINAL_WINDOW,dependencyBinding:EXPORTS_DEPENDENCY,
  permittedOriginalExportCommands:EXPORTS_COMMANDS,originalFixtureUtcDay:'2026-10-13',a5SourceBindings:EXPORTS_A5_SOURCE_BINDINGS,
  preservedOriginalSourceCount:68,consolidatedSqlSha256:EXPORTS_SQL_SHA256,maximumRunMs:900000,maximumRequestMs:45000,
  ordinaryReserveMs:90000,resolutionReserveMs:45000,transportRetries:0,unlistedCallsAllowed:0,schedulesMustRemainPaused:true,
  onlyTwoExpiryFieldsMayChange:true,renewalOperationBundleSha256:digest,exportSourceBindings:clone(exportSourceBindings)};
 const independentReview={kind:'independent-export-a6-policy-review',passed:true,sourceOnly:true,liveExecutionAuthorized:false,
  policyBinding:controlBindings.sourcePolicy,exportSourceBindings,budget:EXPORTS_REVIEWED_BUDGET,renewalOperationBundleSha256:digest,
  exactConsolidatedSqlSha256:EXPORTS_SQL_SHA256};
 const ownerDecision={kind:'direct-human-runtime-renewal-and-export-a6-decision',approved:true,approvalSource:'direct-user-reply',
  exactReply:EXPORTS_OWNER_REPLY,questionItemId:'CONTROLLED_TEST_ONLY_NEVER_AN_ACTUAL_HUMAN_REPLY',projectId:PROJECT,runtimeBundleSha256:BUNDLE,
  runtimeId:EXPORTS_RUNTIME_ID,sourcePolicyBinding:controlBindings.sourcePolicy,independentReviewBinding:controlBindings.independentReview,
  operationBundleSha256:digest,budget:EXPORTS_REVIEWED_BUDGET,maximumWindowMs:7200000,onlyTwoExpiryFieldsMayChange:true,schedulesMustRemainPaused:true,
  productionAuthorized:false,realBillingAuthorized:false,decidedAt:'2026-10-14T13:00:00.000Z'};
 const controlCallAccounting={attempts:3,failedAttempts:0,automaticRetries:0,receipts:['preflight','two-row-expiry-write','readback'].map((phase,i)=>
  ({ordinal:136+i,phase,successful:true,responseSha256:digest}))};
 const renewalReadback={kind:'actual-two-row-runtime-expiry-renewal-readback',actual:true,committed:true,projectId:PROJECT,runtimeId:EXPORTS_RUNTIME_ID,
  ownerDecisionBinding:controlBindings.ownerDecision,sourcePolicyBinding:controlBindings.sourcePolicy,operationBundleSha256:digest,
  appliedAt:testWindow.notBefore,observedAt:'2026-10-14T13:30:01.000Z',affectedRows:2,onlyTwoExpiryFieldsChanged:true,issuedAtUnchanged:true,
  nonWindowValuesUnchanged:true,jobsPaused:true,countersUnchanged:true,secretValuesRead:false,controlCallAccounting,
  scope:{count:1,runtimeId:EXPORTS_RUNTIME_ID,tenantId:FINANCE_SCOPE.tenantId,legalEntityId:FINANCE_SCOPE.entityId,branchId:FINANCE_SCOPE.branchId,
   issuedAt:EXPORTS_ORIGINAL_WINDOW.scopeIssuedAt,oldExpiresAt:EXPORTS_ORIGINAL_WINDOW.scopeExpiresAt,
   expiresAt:testWindow.scopeExpiresAt,nonWindowHash:EXPORTS_ORIGINAL_WINDOW.scopeNonWindowHash},
  edge:{count:1,runtimeId:EXPORTS_RUNTIME_ID,issuedAt:EXPORTS_ORIGINAL_WINDOW.edgeIssuedAt,oldExpiresAt:EXPORTS_ORIGINAL_WINDOW.edgeExpiresAt,
   expiresAt:testWindow.edgeExpiresAt,nonWindowHash:EXPORTS_ORIGINAL_WINDOW.edgeNonWindowHash}};
 const metadata={kind:'wave5-private-owner-input-metadata',projectId:PROJECT,runtimeBundleSha256:BUNDLE,metadataFilename:'metadata-renewed-a10.json',
  containsPlaintextCredential:false,reuseAuthorizationQuestionId:'["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]',
  createdAt:'2026-10-14T13:05:00.000Z',expiresAt:testWindow.privateExpiresAt,helperSha256:digest,refreshEvidence:controlBindings.refresh};
 const refresh={kind:'actual-private-owner-scope-refresh',projectId:PROJECT,organizationId:ORGANIZATION,actualStatus:'ACTIVE_HEALTHY',readOnlyOwnerApiCalls:1,
  actualVerifiedAt:metadata.createdAt,helperSha256:digest,databaseWrites:0,authWrites:0,settingsChanges:0};
 const dependency=await readJson(EXPORTS_DEPENDENCY.path);
 const accounting={kind:'conservative-renewed-export-a6-read-accounting',projectId:PROJECT,recordedPriorBinding:EXPORTS_DEPENDENCY,recordedPrior:134,
  chargedA10OwnerIdentityReads:1,chargedRenewalControlCalls:3,otherFinanceCallsSinceDependency:0,cumulativeChargedPriorCalls:138,
  actualA10Refresh:controlBindings.refresh,actualRenewalReadback:controlBindings.renewalReadback,renewalCallAccounting:controlCallAccounting};
 const profile={kind:'source-reviewed-renewed-export-a6-profile',projectId:PROJECT,runtimeBundleSha256:BUNDLE,priorConservativeBound:138,ordinaryAttempts:24,
  ordinaryLimit:162,cumulativeLimit:163,resolutionAttempts:1,originalFixtureUtcDay:'2026-10-13',personalHumanExactSourceSignatureClaimed:false,
  controlBindings,window:testWindow,privateAdapterPredecessor:{path:'scripts/wave5/run_private_management_installer_20261013_r5.ps1',sha256:digest}};
 return {profileBinding:{path:EXPORTS_PROFILE,sha256:digest},profile,documents:{sourcePolicy,independentReview,ownerDecision,renewalReadback,metadata,refresh,accounting,dependency},
  oldPlan,preserved,sourceBindings,preparedAt:stamp};
}
function finalReviewFor(plan){return {kind:'independent-renewed-export-a6-final-operation-review',technicalDecision:'approve',executionPermitted:true,
 projectId:PROJECT,runtimeBundleSha256:BUNDLE,generatedPlan:{path:EXPORTS_PLAN,sha256:digest},sourceBindings:plan.sourceBindings,
 executionProfileBinding:plan.profileBinding,controlBindings:plan.controlBindings,window:plan.window,
 privateAdapter:{beforeSha256:plan.privateAdapterPredecessor.sha256,afterSha256:digest},priorConservativeBound:138,ordinaryLimit:162,cumulativeLimit:163,
 ordinaryAttempts:24,resolutionAttempts:1,permittedOriginalExportCommands:EXPORTS_COMMANDS,originalFixtureUtcDay:'2026-10-13',
 directHumanDecisionVerified:true,actualTwoRowReadbackVerified:true,personalHumanExactSourceSignatureClaimed:false};}

test('peer: actual owner refresh must precede renewal application for the ordinal135-before136 accounting contract',async()=>{
 const x=clone(await publicPreparationInputs());
 x.documents.metadata.createdAt=x.documents.refresh.actualVerifiedAt='2026-10-14T13:45:00.000Z';
 assert.throws(()=>validateExportsProfile(x.profile,x.documents,now()),undefined,'a refresh after appliedAt cannot be ordinal135 before the renewal136-138 sequence');
});
test('peer: an owner refresh after renewal readback cannot validate the same predecessor138 evidence',async()=>{
 const x=clone(await publicPreparationInputs());
 x.documents.metadata.createdAt=x.documents.refresh.actualVerifiedAt='2026-10-14T13:30:02.000Z';
 assert.throws(()=>buildExportsPreparation(x),undefined,'renewal readback was complete13:30:01 before the owner refresh');
});
test('peer: a failed individual renewal receipt cannot be hidden by zero failedAttempts',async()=>{
 const x=clone(await publicPreparationInputs());x.documents.renewalReadback.controlCallAccounting.receipts[1].successful=false;
 assert.throws(()=>validateExportsProfile(x.profile,x.documents,now()));
});
test('peer: a duplicated successful receipt ordinal cannot stand in for all three renewal phases',async()=>{
 const x=clone(await publicPreparationInputs());x.documents.renewalReadback.controlCallAccounting.receipts[2]=clone(x.documents.renewalReadback.controlCallAccounting.receipts[1]);
 assert.throws(()=>validateExportsProfile(x.profile,x.documents,now()));
});
test('peer: the common runtime expiry cannot override an earlier private-owner deadline',async()=>{
 const x=clone(await publicPreparationInputs());x.profile.window.expiresAt=x.profile.window.edgeExpiresAt;
 assert.throws(()=>validateExportsProfile(x.profile,x.documents,now()));
});
test('peer: explicit UTC windows reject a DST/local offset and leap-day normalization',()=>{
 for(const start of ['2026-11-01T01:30:00-04:00','2026-02-29T13:30:00.000Z'])
  assert.throws(()=>validateExportsWindow({...testWindow,notBefore:start}));
});
test('peer: common 120-minute window is accepted across the Oct15/16 boundary without altering fixture dates',async()=>{
 const x=clone(await publicPreparationInputs());
 x.documents.ownerDecision.decidedAt='2026-10-15T23:00:00.000Z';
 x.documents.metadata.createdAt=x.documents.refresh.actualVerifiedAt='2026-10-15T23:05:00.000Z';x.documents.metadata.expiresAt='2026-10-16T01:05:00.000Z';
 x.documents.renewalReadback.appliedAt='2026-10-15T23:30:00.000Z';x.documents.renewalReadback.observedAt='2026-10-15T23:30:01.000Z';
 x.documents.renewalReadback.edge.expiresAt=x.documents.renewalReadback.scope.expiresAt='2026-10-16T01:30:00.000Z';
 x.profile.window={notBefore:x.documents.renewalReadback.appliedAt,edgeExpiresAt:x.documents.renewalReadback.edge.expiresAt,scopeExpiresAt:x.documents.renewalReadback.scope.expiresAt,privateExpiresAt:x.documents.metadata.expiresAt,expiresAt:x.documents.metadata.expiresAt};
 x.preparedAt='2026-10-16T00:00:00.000Z';const plan=buildExportsPreparation(x);assert.equal(plan.originalFixtureUtcDay,'2026-10-13');
 assert.equal(validateExportsTime(x.preparedAt,{now:Date.parse(x.preparedAt),window:plan.window}),Date.parse(x.preparedAt));
});
test('peer: final public-review read failure returns before adapter access',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs());let reads=0;
 await assert.rejects(preflightExportsOperation({finalReviewSha256:digest,now,verifyPreparation:async()=>({plan,planSha256:digest}),
  readPublic:async()=>{reads++;throw Error('controlled final review unavailable');}}),/review unavailable/);assert.equal(reads,1);
});
test('peer: a public preparation failure performs no final-review or adapter read',async()=>{
 let reads=0;await assert.rejects(preflightExportsOperation({finalReviewSha256:digest,now,verifyPreparation:async()=>{throw Error('controlled source drift');},
  readPublic:async()=>{reads++;assert.fail('no read after failed source audit');}}),/source drift/);assert.equal(reads,0);
});
test('peer: control binding substitution in a final review blocks adapter access',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs()),review=clone(finalReviewFor(plan));let reads=0;
 review.controlBindings.ownerDecision.sha256=hashBytes('controlled substituted human decision');
 await assert.rejects(preflightExportsOperation({finalReviewSha256:digest,now,verifyPreparation:async()=>({plan,planSha256:digest}),
  readPublic:async()=>{reads++;return Buffer.from(JSON.stringify(review));}}));assert.equal(reads,1);
});
