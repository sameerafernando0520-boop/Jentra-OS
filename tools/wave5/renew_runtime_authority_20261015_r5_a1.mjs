// Source-only successor. Importing or public preflight never reads private input,
// writes an intent, or makes a network request. No approval is embedded here.
import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {isDeepStrictEqual as same} from 'node:util';

export const PROJECT='xpdoufauvrbdmxgngetv',RUNTIME='778237e3-3d4e-4871-8cc9-e08b07b989c7';
export const ORGANIZATION='kuzlgtbvfmxqcodmicoy';
export const BUNDLE='db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
const BASE='docs/verification/wave5/',OWN=BASE+'root-runtime-renewal-20261015/';
export const SOURCE='tools/wave5/renew_runtime_authority_20261015_r5_a1.mjs';
export const TEST=OWN+'renew_runtime_authority_20261015_r5_a1.test.mjs';
export const PLAN=OWN+'execution-plan-a1.json',REVIEW=OWN+'final-operation-review-a1.json',ONCE=OWN+'actual-renewal-once-a1.json';
export const READBACK=BASE+'runtime-renewal-two-row-readback-20261016-r5-a7.json';
export const PRIVATE_ADAPTER='scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1';
export const OWNER_REPLY='Approve the exact two-row runtime renewal and export a7 continuation';
export const OWNER_REFRESH_HELPER=Object.freeze({path:'tools/wave5/refresh_private_owner_scope_20261014_r5_a10.mjs',
 sha256:'a3fe771a022dac5ba3a81a33591e7017fb6f446a2e813affd09fc6e40738d07a'});
export const SQL_BINDINGS=Object.freeze({
 read:{path:BASE+'task3-runtime-renewal-20261014/renewal-preflight-read-a3.sql',sha256:'546b3490cccecb4ae46740d4960dd64a919e35ba813261fefc17725d5afbae93'},
 write:{path:BASE+'task3-runtime-renewal-20261014/renewal-expiry-update-template-a3.sql',sha256:'ba2d17a9d47b64974d6086a16aaa25f3c04efbed60344ba18ba09fc8d543eeff'}
});
export const CONTROL_PATHS=Object.freeze({
 sourcePolicy:BASE+'task3-export-renewal-20261016/source-policy-a1.json',
 policyReview:BASE+'task3-export-renewal-20261016/independent-policy-review-a1.json',
 ownerDecision:BASE+'runtime-renewal-export-owner-decision-20261016-r5-a7.json',
 metadata:BASE+'private-owner-input-ready-20261014-r5-a10.json',refresh:BASE+'private-owner-scope-refresh-20261014-r5-a10.json',
 proposal:BASE+'task3-runtime-renewal-20261014/renewal-proposal-a2.json',
 sourceRepair:BASE+'task3-runtime-renewal-20261014/source-repair-a3.json',
 dependency:BASE+'runtime-expiry-dependency-readonly-20261014-r5-a1.json',
 currentCharge:BASE+'task3-export-renewal-20261016/recorded-call-accounting-137-a1.json',
 staticReview:OWN+'independent-source-review-a1.json'
});
export const STATIC_HASHES=Object.freeze({proposal:'8bb011428684768dc98b520e895b2bad0d1f9ddf7e17cd198083cc56bca9ef2c',
 sourceRepair:'f5d4242bc5cc464ff9391ae394c2c674195a1ace46d2be21bb77c09b8dddc722',
 currentCharge:'f74dc940a839267f8d1d19982f08b122a43455b911d93dab9be85604050d1963',
 dependency:'0dc87893b6635d3ef4fb64c724e6aab2a42dd89d9d07ffc42251105f7c3141dc'});
export const SCOPE=Object.freeze({tenantId:'babe6c86-a764-4d3a-80a3-952a7c096c2c',legalEntityId:'caa2bb06-219a-47e9-8132-66d1271b0ffd',branchId:'3813692c-f0de-4c69-8e34-d56cf54695b1'});
export const OLD=Object.freeze({scopeIssuedAt:'2026-10-13T08:13:04.144135+00:00',scopeExpiresAt:'2026-10-14T08:13:04.144135+00:00',
 edgeIssuedAt:'2026-10-13T09:57:07.481942+00:00',edgeExpiresAt:'2026-10-14T09:57:07.481942+00:00',
 scopeNonWindowHash:'3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387',
 edgeNonWindowHash:'77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139'});
export const BUDGET=Object.freeze({recordedPrior:137,ownerRefreshCalls:1,renewalControlCalls:3,prior:141,ordinary:24,ordinaryLimit:165,resolution:1,total:166});
export const CURRENT_EVIDENCE=Object.freeze([
 ['root-readonly-attempt-a1.json','5b9b136a1e0b414b40a8cd314e9a7b1b6a7ea201c594cd12e510562fb3b105a4'],
 ['root-readonly-result-a1.json','010900eea3f210b95d1d9e3f5e15b8c59663d90ad8f638fdc8e3cc919703b7de'],
 ['root-advisors-attempt-a1.json','47822988c8200b8adf01a3d9ced4a24f2f79440152418c6ddfe38d1cf0d55bd2'],
 ['root-security-advisors-result-a1.json','865b97745c013beb18414231699e10e58b585f98f8bff57de16448fba4b7c18b'],
 ['root-performance-advisors-result-a1.json','cb45cd5bcc061edb44ebeb8b150d255b5c25e0d5b838f504754b9eef38e51722'],
 ['current-state-verification-a1.json','1d10f95d8c0f23534d101475f1a5d72dcff6711296a6dc59a064fb03a28590fb']
].map(([name,sha256])=>Object.freeze({path:BASE+'seven-area-completion-20261016/'+name,sha256})));
const root=fileURLToPath(new URL('../../',import.meta.url));
const hash=x=>createHash('sha256').update(x).digest('hex');
const digest=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const must=(value,code)=>{if(!value){const error=Error(code);error.publicCode=code;throw error;}};
const keys=(object,wanted)=>object&&typeof object==='object'&&!Array.isArray(object)&&same(Object.keys(object).sort(),wanted.slice().sort());
const binding=x=>keys(x,['path','sha256'])&&typeof x.path==='string'&&digest(x.sha256);
const publicPath=x=>typeof x==='string'&&/^(docs\/verification\/wave5\/|tools\/wave5\/|scripts\/wave5\/)/.test(x)
 &&/^[A-Za-z0-9_./-]+$/.test(x)&&!x.split('/').includes('..')&&!x.includes('//');
const jsonBytes=x=>Buffer.from(JSON.stringify(x,null,2)+'\n');
const immutable=x=>{const value=structuredClone(x);const freeze=v=>{if(v&&typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;};return freeze(value);};
export function utc(value){
 must(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(value),'RENEWAL_EXPLICIT_UTC_REQUIRED');
 const time=Date.parse(value);must(Number.isFinite(time)&&new Date(time).toISOString().slice(0,19)===value.slice(0,19),'RENEWAL_VALID_UTC_REQUIRED');return time;
}
export function validateWindow(window,now=Date.now(),reserve=0){
 must(keys(window,['notBefore','expiresAt'])&&Number.isFinite(now),'EXACT_RENEWAL_WINDOW_REQUIRED');
 const start=utc(window.notBefore),end=utc(window.expiresAt);
 must(end>start&&end-start<=7200000&&now>=start&&now+reserve<end,'FRESH_BOUNDED_RENEWAL_WINDOW_REQUIRED');return end;
}
export async function readPublicFile(item,{workspace=root}={}){
 must(binding(item)&&publicPath(item.path),'PINNED_RENEWAL_PUBLIC_FILE_REQUIRED');
 const target=path.resolve(workspace,item.path),stat=await fs.lstat(target);
 must(stat.isFile()&&!stat.isSymbolicLink()&&stat.size>0&&stat.size<=2097152&&path.resolve(await fs.realpath(target))===target,'BOUNDED_RENEWAL_PUBLIC_FILE_REQUIRED');
 const bytes=await fs.readFile(target);must(bytes.length<=2097152&&hash(bytes)===item.sha256,'RENEWAL_PUBLIC_HASH_MISMATCH');return bytes;
}
export function validateContract({plan,review,controls,planSha256,currentEvidence},now=Date.now()){
 const {sourcePolicy:policy,policyReview,ownerDecision:owner,metadata,refresh,proposal,sourceRepair,dependency,staticReview}=controls??{};
 must(plan?.kind==='source-bound-two-row-runtime-renewal-plan'&&plan.projectId===PROJECT&&plan.runtimeId===RUNTIME&&plan.runtimeBundleSha256===BUNDLE
  &&plan.maximumManagementAttempts===3&&plan.recordedPrior===137&&plan.actualPriorAfterOwnerRefresh===138&&plan.cumulativeAfterRenewal===141
  &&plan.maximumRequestMs===45000&&plan.maximumRunMs===900000&&plan.ordinaryReserveMs===90000&&plan.maximumWindowMinutes===120
  &&plan.automaticRetries===0&&plan.exclusiveOncePath===ONCE&&plan.finalReviewPath===REVIEW&&plan.readbackPath===READBACK
  &&plan.liveExecutionAuthorizedByPreparation===false&&same(plan.sqlBindings,SQL_BINDINGS)&&keys(plan.controlBindings,Object.keys(CONTROL_PATHS))
  &&Array.isArray(plan.sourceBindings)&&plan.sourceBindings.length===2&&plan.sourceBindings.every((x,i)=>binding(x)&&x.path===[SOURCE,TEST][i]),
  'EXACT_THREE_CALL_RENEWAL_PLAN_REQUIRED');
 validateWindow(plan.window,now,90000);
 for(const [name,file] of Object.entries(CONTROL_PATHS))must(binding(plan.controlBindings[name])&&plan.controlBindings[name].path===file
  &&(!STATIC_HASHES[name]||plan.controlBindings[name].sha256===STATIC_HASHES[name]),'EXACT_RENEWAL_CONTROL_BINDINGS_REQUIRED');
 const publicBindings=[...Object.values(plan.controlBindings),...Object.values(SQL_BINDINGS),...CURRENT_EVIDENCE,OWNER_REFRESH_HELPER].sort((a,b)=>a.path.localeCompare(b.path));
 must(same(plan.publicBindings,publicBindings),'EXACT_RENEWAL_PUBLIC_BINDING_CLOSURE_REQUIRED');
 must(review?.kind==='independent-runtime-renewal-final-operation-review'&&review.technicalDecision==='approve'&&review.executionPermitted===true
  &&review.projectId===PROJECT&&review.runtimeId===RUNTIME&&review.runtimeBundleSha256===BUNDLE
  &&same(review.generatedPlan,{path:PLAN,sha256:planSha256})&&same(review.controlBindings,plan.controlBindings)
  &&same(review.sourceBindings,plan.sourceBindings)&&same(review.publicBindings,plan.publicBindings)&&same(review.sqlBindings,SQL_BINDINGS)&&same(review.window,plan.window)
  &&review.privateAdapter?.path===PRIVATE_ADAPTER&&digest(review.privateAdapter.afterSha256)
  &&review.directHumanDecisionVerified===true&&review.maximumManagementAttempts===3&&review.cumulativeAfterRenewal===141,
  'EXACT_FINAL_RENEWAL_OPERATION_REVIEW_REQUIRED');
 must(policy?.kind==='source-only-export-a7-renewal-policy'&&policy.projectId===PROJECT&&policy.runtimeId===RUNTIME&&policy.runtimeBundleSha256===BUNDLE
  &&policy.sourceImplementationOnly===true&&policy.liveExecutionAuthorized===false&&same(policy.budget,BUDGET)
  &&policy.maximumWindowMs===7200000&&policy.windowMode==='server-clock-at-application'&&policy.onlyTwoExpiryFieldsMayChange===true
  &&policy.schedulesMustRemainPaused===true&&same(policy.originalWindow,OLD)&&digest(policy.renewalOperationBundleSha256)
  &&same(policy.renewalControllerSourceBindings,plan.sourceBindings)&&same(policy.renewalSqlBindings,SQL_BINDINGS)
  &&same(policy.currentChargeBinding,plan.controlBindings.currentCharge)
  &&same(policy.renewalProposalBinding,plan.controlBindings.proposal)&&same(policy.renewalSourceRepairBinding,plan.controlBindings.sourceRepair),
  'EXACT_REVIEWED_RENEWAL_SOURCE_POLICY_REQUIRED');
 must(policyReview?.kind==='independent-export-a7-policy-review'&&policyReview.passed===true&&policyReview.sourceOnly===true&&policyReview.liveExecutionAuthorized===false
  &&same(policyReview.policyBinding,plan.controlBindings.sourcePolicy)&&same(policyReview.budget,BUDGET)
  &&same(policyReview.currentChargeBinding,plan.controlBindings.currentCharge)
  &&policyReview.renewalOperationBundleSha256===policy.renewalOperationBundleSha256
  &&same(policyReview.renewalControllerSourceBindings,plan.sourceBindings)&&same(policyReview.renewalSqlBindings,SQL_BINDINGS),
  'INDEPENDENT_RENEWAL_POLICY_REVIEW_REQUIRED');
 must(owner?.kind==='direct-human-runtime-renewal-and-export-a7-decision'&&owner.approved===true&&owner.approvalSource==='direct-user-reply'
  &&owner.exactReply===OWNER_REPLY&&typeof owner.questionItemId==='string'&&owner.questionItemId.length>=16&&owner.questionItemId.length<=300
  &&owner.projectId===PROJECT&&owner.runtimeId===RUNTIME&&owner.runtimeBundleSha256===BUNDLE&&same(owner.budget,BUDGET)
  &&owner.maximumWindowMs===7200000&&owner.onlyTwoExpiryFieldsMayChange===true&&owner.schedulesMustRemainPaused===true
  &&owner.productionAuthorized===false&&owner.realBillingAuthorized===false&&owner.operationBundleSha256===policy.renewalOperationBundleSha256
  &&same(owner.sourcePolicyBinding,plan.controlBindings.sourcePolicy)&&same(owner.independentReviewBinding,plan.controlBindings.policyReview)
  &&utc(owner.decidedAt)<=now,'DIRECT_EXACT_HUMAN_RENEWAL_DECISION_REQUIRED');
 must(metadata?.kind==='wave5-private-owner-input-metadata'&&metadata.projectId===PROJECT&&metadata.runtimeBundleSha256===BUNDLE
  &&metadata.metadataFilename==='metadata-renewed-a10.json'&&metadata.containsPlaintextCredential===false
  &&metadata.reuseAuthorizationQuestionId==='["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]'
  &&same(metadata.refreshEvidence,plan.controlBindings.refresh)&&utc(metadata.createdAt)>=utc(owner.decidedAt)&&utc(metadata.createdAt)<=now
  &&same(plan.window,{notBefore:metadata.createdAt,expiresAt:metadata.expiresAt}), 'ACTUAL_FRESH_A10_RENEWAL_METADATA_REQUIRED');
 must(refresh?.kind==='actual-private-owner-scope-refresh'&&refresh.projectId===PROJECT&&refresh.organizationId===ORGANIZATION&&refresh.actualStatus==='ACTIVE_HEALTHY'
  &&refresh.readOnlyOwnerApiCalls===1&&refresh.actualVerifiedAt===metadata.createdAt&&refresh.helperSha256===OWNER_REFRESH_HELPER.sha256&&refresh.helperSha256===metadata.helperSha256
  &&refresh.databaseWrites===0&&refresh.authWrites===0&&refresh.settingsChanges===0,'ACTUAL_ONE_GET_OWNER_REFRESH_REQUIRED');
 must(dependency?.kind==='actual-readonly-runtime-expiry-dependency-investigation'&&dependency.projectId===PROJECT&&dependency.mutation===false
  &&dependency.conservativeContinuationAccounting?.cumulativeChargedCalls===134&&dependency.conservativeContinuationAccounting.actualA10RefreshPerformed===false
  &&plan.otherCallsSinceDependency===3&&plan.otherCallsSinceCurrentCharge===0,'PRESERVED_RECORDED134_DEPENDENCY_REQUIRED');
 validateCurrentCharge(controls.currentCharge,currentEvidence,plan.controlBindings.currentCharge,metadata.createdAt);
 must(proposal?.kind==='source-only-two-existing-expiry-runtime-renewal-proposal'&&proposal.projectId===PROJECT&&proposal.runtimeId===RUNTIME
  &&proposal.executionPermitted===false&&proposal.requestedChange?.maximumWindowMinutes===120&&proposal.budget?.priorAtExports===138
  &&proposal.budget.financeThroughExportsMaximum===163&&proposal.budget.overallMaximum===171&&proposal.exactGuardFunctionBindings?.length===7
  &&sourceRepair?.kind==='additive-renewal-a3-source-repair'&&sourceRepair.sourceOnly===true&&sourceRepair.executionPermitted===false
  &&sourceRepair.sources?.every((row,i)=>row.path===[SQL_BINDINGS.read.path,SQL_BINDINGS.write.path][i]&&row.sha256===[SQL_BINDINGS.read.sha256,SQL_BINDINGS.write.sha256][i])
  &&sourceRepair.sources.length===2,'PINNED_A3_RENEWAL_PROPOSAL_AND_REPAIR_REQUIRED');
 must(staticReview?.kind==='independent-runtime-renewal-controller-source-review'&&staticReview.passed===true&&staticReview.sourceOnly===true
  &&staticReview.executionPermitted===false&&same(staticReview.sourceBindings,plan.sourceBindings)&&same(staticReview.sqlBindings,SQL_BINDINGS)
  &&same(staticReview.proposalBinding,plan.controlBindings.proposal)&&same(staticReview.sourceRepairBinding,plan.controlBindings.sourceRepair),
  'INDEPENDENT_RENEWAL_CONTROLLER_REVIEW_REQUIRED');
 return plan;
}
export function validateCurrentCharge(ledger,evidence,bound,metadataCreatedAt){
 must(Array.isArray(evidence)&&evidence.length===CURRENT_EVIDENCE.length,'SIX_PINNED_CURRENT_CHARGE_EVIDENCE_REQUIRED');
 const [attempt,read,advisors,security,performance,verification]=evidence;
 must(attempt.kind==='root-current-state-readonly-attempt'&&attempt.oldRecordedCharge===134&&attempt.conservativelyChargedAttempt===1
  &&attempt.proposedNewActualCharge===135&&read.kind==='root-current-state-readonly-result'&&read.actualConnectorAttempts===1
  &&read.conservativeRecordedCharge===135&&read.originalPermissionsRenewed===false&&read.rawResult?.isError!==true
  &&advisors.kind==='readonly-production-advisors-attempts'&&same(advisors.types,['security','performance'])&&advisors.previousChargedCalls===135
  &&advisors.maximumAttempts===2&&advisors.conservativeCumulativeCharge===137
  &&[attempt,read,advisors].every(x=>x.projectId===PROJECT&&x.mutation===false&&x.privateInputsRead===false),
  'ACTUAL_THREE_ADDITIONAL_READ_ATTEMPTS_REQUIRED');
 for(const [entry,kind] of [[security,'security'],[performance,'performance']])must(entry.kind===`actual-readonly-${kind}-advisors`
  &&entry.projectId===PROJECT&&entry.mutation===false&&entry.credentialInputsRead===false&&entry.result?.status==='fulfilled'
  &&entry.result.value?.isError!==true,'ACTUAL_SUCCESSFUL_READONLY_ADVISOR_RESULT_REQUIRED');
 must(verification.kind==='independent-current-live-state-projection-verification'&&verification.passed===true&&verification.projectId===PROJECT
  &&verification.originalPriorCharge===134&&verification.actualDatabaseReadCalls===1&&verification.actualAdvisorReadCalls===2
  &&verification.cumulativeConservativeCharge===137&&verification.mutations===0&&verification.privateInputsRead===false
  &&same(verification.sourceBindings.map(({path,sha256})=>({path,sha256})),CURRENT_EVIDENCE.slice(0,5))
  &&utc(verification.actualDatabaseObservedAt)<=utc(metadataCreatedAt),'PINNED_ACTUAL137_PROJECTION_REQUIRED');
 // A source-derived accounting ledger binds recorded calls; it is not a new live read or permission.
 must(binding(bound)&&bound.path===CONTROL_PATHS.currentCharge&&bound.sha256===STATIC_HASHES.currentCharge
  &&ledger?.kind==='source-derived-conservative-export-a7-charge-baseline'&&ledger.projectId===PROJECT
  &&ledger.historicalChargedPrior===134&&ledger.newReadOnlyAttempts===3&&ledger.actualChargedPrior===137
  &&same(ledger.historicalDependencyBinding,{path:CONTROL_PATHS.dependency,sha256:STATIC_HASHES.dependency})
  &&same(ledger.evidenceBindings.map(({path,sha256})=>({path,sha256})),CURRENT_EVIDENCE)
  &&ledger.sourceCallsSinceBaseline===0&&ledger.executionPermitted===false&&ledger.futureCallsObserved===false,
  'EXACT_CURRENT137_ACCOUNTING_LEDGER_REQUIRED');
 return ledger;
}
export async function preflightRenewalOperation({finalReviewSha256,readPublic=readPublicFile,now=Date.now}={}){
 must(digest(finalReviewSha256),'PINNED_RENEWAL_FINAL_REVIEW_SHA_REQUIRED');
 const get=async item=>JSON.parse(await readPublic(item));
 const review=await get({path:REVIEW,sha256:finalReviewSha256});
 must(binding(review.generatedPlan)&&review.generatedPlan.path===PLAN,'FIXED_RENEWAL_PLAN_PATH_REQUIRED');
 const plan=await get(review.generatedPlan),controls={};
 must(keys(plan.controlBindings,Object.keys(CONTROL_PATHS)),'EXACT_RENEWAL_PUBLIC_CONTROL_SET_REQUIRED');
 for(const [name,file] of Object.entries(CONTROL_PATHS)){
  must(binding(plan.controlBindings[name])&&plan.controlBindings[name].path===file
   &&(!STATIC_HASHES[name]||plan.controlBindings[name].sha256===STATIC_HASHES[name]),'PINNED_RENEWAL_CONTROL_PATH_REQUIRED');
  controls[name]=await get(plan.controlBindings[name]);
 }
 const currentEvidence=[];for(const item of CURRENT_EVIDENCE)currentEvidence.push(await get(item));
 const checked={plan,review,controls,currentEvidence,planSha256:review.generatedPlan.sha256,finalReviewSha256};validateContract(checked,now());
 for(const item of plan.sourceBindings)await readPublic(item);
 await readPublic(OWNER_REFRESH_HELPER);
 await readPublic({path:PRIVATE_ADAPTER,sha256:review.privateAdapter.afterSha256});
 const readSql=(await readPublic(SQL_BINDINGS.read)).toString('utf8'),writeTemplate=(await readPublic(SQL_BINDINGS.write)).toString('utf8');
 must(hash(readSql)===SQL_BINDINGS.read.sha256&&hash(writeTemplate)===SQL_BINDINGS.write.sha256,'EXACT_A3_SQL_BYTES_REQUIRED');
 validateContract(checked,now());
 return {...immutable(checked),readSql,writeTemplate,publicResult:{passed:true,networkCalls:0,privateInputsRead:false,planSha256:checked.planSha256,finalReviewSha256}};
}
export function validateSnapshot(value,checked,{now=Date.now(),renewedExpiry,appliedAt}={}){
 const {proposal,sourceRepair}=checked.controls;
 must(value?.timeZone==='UTC'&&value.migrationCount===115&&value.apiFunctionCount===363&&value.containsUnexpected24HourFunctionCeiling===false
  &&value.scopeCount===1&&value.scopeAllowed===(renewedExpiry!==undefined)&&value.authority?.runtimeId===RUNTIME&&value.authority.enabled===true
  &&value.authority.issuedAt===OLD.edgeIssuedAt&&value.authority.nonWindowHash===OLD.edgeNonWindowHash&&same(value.authority.jobIds,[4,5,6])
  &&value.scope?.enabled===true&&value.scope.issuedAt===OLD.scopeIssuedAt&&value.scopeNonWindowHash===OLD.scopeNonWindowHash
  &&Object.entries(SCOPE).every(([k,v])=>value.scope[k]===v),'EXACT_TWO_RENEWAL_ROWS_REQUIRED');
 const observed=utc(value.observedAt);must(now-observed>=0&&now-observed<=45000&&observed>=utc(checked.plan.window.notBefore), 'FRESH_RENEWAL_SERVER_OBSERVATION_REQUIRED');
 must(utc(value.authority.expiresAt)===utc(renewedExpiry??OLD.edgeExpiresAt)&&utc(value.scope.expiresAt)===utc(renewedExpiry??OLD.scopeExpiresAt),
  'EXACT_COMMON_RENEWAL_EXPIRY_REQUIRED');
 if(appliedAt!==undefined)must(observed>=utc(appliedAt)&&observed-utc(appliedAt)<=45000&&observed<=now,'ACTUAL_POST_APPLICATION_READBACK_REQUIRED');
 must(same(value.financeCounters,sourceRepair.financeBaseline)&&same(value.effectCounters,sourceRepair.effectBaseline)
  &&same(value.ownJobs,proposal.recordedState.pausedJobs)&&value.outsideJobHash==='4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945'
  &&same(value.guardFunctionBindings,proposal.exactGuardFunctionBindings)&&same(value.keyReferences,checked.controls.dependency.snapshot.keyReferences)
  &&value.ticks===0&&value.modelInvocations===0&&value.recordedCronRuns===24,'PRESERVED_RENEWAL_FUNCTIONS_COUNTERS_JOBS_AND_KEYS_REQUIRED');
 must(Array.isArray(value.billingWindow)&&value.billingWindow.length===1&&value.billingWindow[0].status==='trialing'
  &&value.billingWindow[0].trialEndsAt==='2026-10-20T08:13:04.144135+00:00'&&value.billingWindow[0].currentPeriodEndsAt===null
  &&utc(value.billingWindow[0].trialEndsAt)>utc(renewedExpiry??checked.plan.window.expiresAt),'UNCHANGED_BILLING_WINDOW_REQUIRED');
 must(Array.isArray(value.tableContracts)&&value.tableContracts.length===2,'EXACT_RENEWAL_TABLE_CONTRACTS_REQUIRED');
 for(const [name,key] of [['intelligence_control.edge_authorities','edgeAuthority'],['intelligence_control.runtime_worker_scopes','workerScope']]){
  const rows=value.tableContracts.filter(row=>row.name===name);must(rows.length===1&&rows[0].rls===true&&rows[0].forceRls===true&&rows[0].userTriggers===0
   &&same(rows[0].columns,proposal.schemaContracts[key])&&Array.isArray(rows[0].constraints)&&rows[0].constraints.length>=2
   &&rows[0].constraints.every(x=>typeof x==='string'&&x.length<4096),'PRESERVED_RENEWAL_SCHEMA_COLUMNS_RLS_AND_TRIGGERS_REQUIRED');
 }
 return value;
}
export function renderRenewalSql(checked,snapshot,now=Date.now()){
 validateContract(checked,now);validateSnapshot(snapshot,checked,{now});
 must(hash(checked.writeTemplate)===SQL_BINDINGS.write.sha256,'EXACT_NULL_A3_WRITE_TEMPLATE_REQUIRED');
 const anchor=utc(snapshot.observedAt),end=Math.min(anchor+7200000,utc(checked.controls.metadata.expiresAt));
 must(anchor>=utc(checked.controls.ownerDecision.decidedAt)&&anchor<=now+10000&&now-anchor<=45000&&end>now+90000
  &&end<=utc(OLD.scopeIssuedAt)+604800000&&end<=utc(OLD.edgeIssuedAt)+604800000,'FRESH_SCHEMA_BOUNDED_RENEWAL_ANCHOR_REQUIRED');
 const fields={v_human_approval_sha256:['text',checked.plan.controlBindings.ownerDecision.sha256],v_review_packet_sha256:['text',checked.controls.sourcePolicy.renewalOperationBundleSha256],
  v_human_approved_at:['timestamptz',checked.controls.ownerDecision.decidedAt],v_server_anchor:['timestamptz',snapshot.observedAt],
  v_owner_metadata_expires_at:['timestamptz',checked.controls.metadata.expiresAt]};
 let query=checked.writeTemplate;
 for(const [name,[type,value]] of Object.entries(fields)){
  must(type==='text'?digest(value):Number.isFinite(utc(value)),'RENEWAL_SQL_LITERAL_VALIDATION_REQUIRED');
  const token=` ${name} ${type} := NULL;`;must(query.split(token).length===2,'EXACT_FIVE_NULL_INPUT_SLOTS_REQUIRED');
  query=query.replace(token,` ${name} ${type} := '${value}'${type==='timestamptz'?'::timestamptz':''};`);
 }
 return {query,querySha256:hash(query),anchor:snapshot.observedAt,expiresAt:new Date(end).toISOString(),substitutions:Object.keys(fields)};
}
function validateApplication(value,rendered,checked,now){
 must(keys(value,['runtimeId','appliedAt','expiresAt','affectedRows','applicationTimestampProvenance'])&&value.runtimeId===RUNTIME&&value.affectedRows===2
  &&value.applicationTimestampProvenance==='server-post-commit-observation'&&utc(value.expiresAt)===utc(rendered.expiresAt)
  &&utc(value.appliedAt)>=utc(rendered.anchor)&&utc(value.appliedAt)>=utc(checked.controls.ownerDecision.decidedAt)
  &&utc(value.appliedAt)<=now&&now-utc(value.appliedAt)<=45000&&utc(value.appliedAt)-utc(rendered.anchor)<=45000,'ACTUAL_POST_COMMIT_APPLICATION_RESPONSE_REQUIRED');return value;
}
export async function runRenewal({checked,transport,persist,once,publishReadback,close=async()=>{},now=Date.now,signal,portTimeoutMs=45000}={}){
 validateContract(checked,now());must([transport,persist,once,publishReadback,close].every(x=>typeof x==='function')&&Number.isInteger(portTimeoutMs)
  &&portTimeoutMs>0&&portTimeoutMs<=45000,'BOUNDED_RENEWAL_PORTS_REQUIRED');
 const immutableChecked=immutable(checked);checked=immutableChecked;
 const startedAt=now(),deadline=Math.min(startedAt+900000,utc(checked.plan.window.expiresAt));
 let attempts=0,failedAttempts=0,writeDispatched=false,readbackAttempted=false,before,rendered,application,stage='once',closed=false;
 const receipts=[],rawBindings=[];
 const stopTransport=async()=>{if(!closed){closed=true;await close();}};
 const timed=(fn,{local=false,resolution=false}={})=>new Promise((resolve,reject)=>{
  let settled=false,timer;const aborter=new AbortController();
  const done=(f,v)=>{if(settled)return;settled=true;clearTimeout(timer);signal?.removeEventListener('abort',abort);f(v);};
  const fail=code=>{aborter.abort();const e=Error(code);e.publicCode=code;done(reject,e);};
  const abort=()=>fail('RENEWAL_EXECUTION_ABORTED');
  const remaining=local?5000:Math.min(portTimeoutMs,deadline-now());
  if(remaining<=0){fail('RENEWAL_PORT_DEADLINE');return;}
  if(!local&&!resolution&&signal?.aborted){abort();return;}
  if(!local&&!resolution)signal?.addEventListener('abort',abort,{once:true});
  timer=setTimeout(()=>fail('RENEWAL_PORT_DEADLINE'),remaining);
  Promise.resolve().then(()=>settled?undefined:fn(aborter.signal)).then(value=>done(resolve,value),error=>done(reject,error));
 });
 const save=async(file,value)=>{const receipt=await timed(()=>persist(file,value),{local:true}),bytes=Buffer.isBuffer(value)?value:jsonBytes(value);
  must(binding(receipt)&&receipt.sha256===hash(bytes),'ACKNOWLEDGED_EXACT_RENEWAL_EVIDENCE_REQUIRED');return receipt;};
 const call=async(phase,query,readOnly,{resolution=false}={})=>{
  validateWindow(checked.plan.window,now(),resolution?45000:90000);
  must(now()>=startedAt&&now()+(resolution?45000:90000)<deadline,'RENEWAL_INFLIGHT_RESOLUTION_MARGIN_REQUIRED');
  must(attempts<3&&phase===['preflight','two-row-expiry-write','readback'][attempts]
   &&readOnly===(phase!=='two-row-expiry-write')&&(readOnly?query===checked.readSql:query===rendered?.query),'EXACT_THREE_ORDERED_RENEWAL_CALLS_REQUIRED');
  const ordinal=139+attempts++;if(phase==='readback')readbackAttempted=true;
  await save(`${ordinal}-${phase}-attempt.json`,{phase,ordinal,chargedBeforeDispatch:true,querySha256:hash(query),readOnly,automaticRetries:0});
  let response;
  try{
   if(!readOnly)writeDispatched=true;
   response=await timed(requestSignal=>transport({phase,query,readOnly,signal:requestSignal,deadline:Math.min(now()+45000,deadline)}),{resolution});
   must(Buffer.isBuffer(response?.raw)&&response.raw.length<=2097152&&Number.isInteger(response.status),'BOUNDED_ACTUAL_RAW_RENEWAL_RESPONSE_REQUIRED');
   const rawReceipt=await save(`${ordinal}-${phase}-response.bin`,response.raw);
   await save(`${ordinal}-${phase}-response.json`,{phase,ordinal,status:response.status,raw:rawReceipt,rawBytes:response.raw.length,validationPending:true});
   must(response.status===200,'SUCCESSFUL_RENEWAL_HTTP_REQUIRED');
   const rows=JSON.parse(response.raw.toString('utf8'));must(Array.isArray(rows)&&rows.length===1,'ONE_ACTUAL_RENEWAL_RESPONSE_ROW_REQUIRED');
   receipts.push({ordinal,phase,successful:true,responseSha256:rawReceipt.sha256});rawBindings.push(rawReceipt);return rows[0];
  }catch(error){failedAttempts++;await save(`${ordinal}-${phase}-failure.json`,{phase,ordinal,failedAttemptCharged:true,
    publicCode:error.publicCode??'RENEWAL_RESPONSE_UNCERTAIN',responseReceived:!!response,privateErrorPrinted:false});throw error;}
 };
 try{
  const onceValue={kind:'exclusive-two-row-renewal-intent',projectId:PROJECT,runtimeId:RUNTIME,runtimeBundleSha256:BUNDLE,
   planSha256:checked.planSha256,finalReviewSha256:checked.finalReviewSha256,startedAt:new Date(startedAt).toISOString(),window:checked.plan.window,
   recordedPrior:137,actualPriorAfterOwnerRefresh:138,maximumManagementAttempts:3,cumulativeAfterRenewal:141,replayAllowed:false};
  const onceReceipt=await timed(()=>once(onceValue),{local:true});must(binding(onceReceipt)&&onceReceipt.path===ONCE&&onceReceipt.sha256===hash(jsonBytes(onceValue)),
   'ACKNOWLEDGED_EXCLUSIVE_RENEWAL_INTENT_REQUIRED');
  stage='preflight';before=validateSnapshot((await call('preflight',checked.readSql,true)).renewal_snapshot,checked,{now:now()});
  rendered=renderRenewalSql(checked,before,now());await save('rendered-expiry-update.sql',Buffer.from(rendered.query));
  stage='write';application=validateApplication((await call('two-row-expiry-write',rendered.query,false)).renewal_application,rendered,checked,now());
  stage='readback';const after=validateSnapshot((await call('readback',checked.readSql,true)).renewal_snapshot,checked,
   {now:now(),renewedExpiry:rendered.expiresAt,appliedAt:application.appliedAt});
  must(same(after.tableContracts,before.tableContracts),'RENEWAL_TABLE_CONTRACT_CHANGED');
  must(attempts===3&&failedAttempts===0&&receipts.length===3,'THREE_SUCCESSFUL_ACTUAL_RENEWAL_RECEIPTS_REQUIRED');
  const result={kind:'actual-two-row-runtime-expiry-renewal-readback',actual:true,committed:true,projectId:PROJECT,runtimeId:RUNTIME,
   ownerDecisionBinding:checked.plan.controlBindings.ownerDecision,sourcePolicyBinding:checked.plan.controlBindings.sourcePolicy,
   operationBundleSha256:checked.controls.sourcePolicy.renewalOperationBundleSha256,appliedAt:application.appliedAt,observedAt:after.observedAt,
   applicationTimestampProvenance:application.applicationTimestampProvenance,preflightObservedAt:rendered.anchor,serverExpiryAnchor:rendered.anchor,serverWindowAnchor:rendered.anchor,
   affectedRows:2,onlyTwoExpiryFieldsChanged:true,issuedAtUnchanged:true,nonWindowValuesUnchanged:true,jobsPaused:true,countersUnchanged:true,secretValuesRead:false,
   scope:{count:1,runtimeId:RUNTIME,...SCOPE,issuedAt:after.scope.issuedAt,oldExpiresAt:before.scope.expiresAt,expiresAt:after.scope.expiresAt,nonWindowHash:after.scopeNonWindowHash},
   edge:{count:1,runtimeId:RUNTIME,issuedAt:after.authority.issuedAt,oldExpiresAt:before.authority.expiresAt,expiresAt:after.authority.expiresAt,nonWindowHash:after.authority.nonWindowHash},
   controlCallAccounting:{attempts:3,failedAttempts:0,automaticRetries:0,receipts},actualCumulativeChargedCalls:141,
   renewalPreflightResponseBinding:rawBindings[0],renewalWriteResponseBinding:rawBindings[1],renewalReadbackResponseBinding:rawBindings[2],
   originalSqlBindings:SQL_BINDINGS,renderedSqlSha256:rendered.querySha256,planSha256:checked.planSha256,
   financeCounters:after.financeCounters,effectCounters:after.effectCounters,actualExports:0,actualDelivery:false,requirementsAccepted:0,productionReady:false};
  await save('99-result.json',result);
  const receipt=await timed(()=>publishReadback(result),{local:true});must(binding(receipt)&&receipt.path===READBACK&&receipt.sha256===hash(jsonBytes(result)),
   'ACKNOWLEDGED_ACTUAL_RENEWAL_READBACK_REQUIRED');return result;
 }catch(error){
  let resolution=null;
  if(writeDispatched&&!readbackAttempted){
   try{const row=await call('readback',checked.readSql,true,{resolution:true});
    const observed=validateSnapshot(row.renewal_snapshot,checked,{now:now(),renewedExpiry:rendered.expiresAt});
    resolution={attempted:true,renewedRowsObserved:true,observedAt:observed.observedAt,applicationTimestampRecovered:false,replayPerformed:false};
   }catch{resolution={attempted:readbackAttempted,readbackUnavailable:true,replayPerformed:false};}
  }
  await stopTransport();
  const stop={kind:'actual-runtime-renewal-stop',projectId:PROJECT,runtimeId:RUNTIME,stage,failureCode:error.publicCode??'RENEWAL_STOPPED',
   actualOrConservativelyChargedAttempts:attempts,cumulativeChargedCalls:138+attempts,failedAttempts,receipts,resolution,
   writeDispatched,writeReplayed:false,a7ContinuationAllowed:false,applicationTimestampFabricated:false,privateErrorPrinted:false};
  try{await save('99-stop.json',stop);}catch{error.publicCode='RENEWAL_STOP_EVIDENCE_UNAVAILABLE';}error.renewalStop=stop;throw error;
 }finally{await stopTransport();}
}
export function assertRenderedQuery(query,writeTemplate){
 must(typeof query==='string','EXACT_FIVE_SLOT_RENEWAL_WRITE_REQUIRED');
 const textRows=[...query.matchAll(/ (v_human_approval_sha256|v_review_packet_sha256) text := '([a-f0-9]{64})';/g)];
 const dateRows=[...query.matchAll(/ (v_human_approved_at|v_server_anchor|v_owner_metadata_expires_at) timestamptz := '([0-9T:.+Z-]+)'::timestamptz;/g)];
 must(textRows.length===2&&dateRows.length===3&&new Set([...textRows,...dateRows].map(row=>row[1])).size===5,
  'EXACT_FIVE_SUBSTITUTED_RENEWAL_INPUTS_REQUIRED');
 dateRows.forEach(row=>utc(row[2]));
 const normalized=query.replace(/ (v_human_approval_sha256|v_review_packet_sha256) text := '[a-f0-9]{64}';/g,' $1 text := NULL;')
  .replace(/ (v_human_approved_at|v_server_anchor|v_owner_metadata_expires_at) timestamptz := '[0-9T:.+Z-]+'::timestamptz;/g,' $1 timestamptz := NULL;');
 must(normalized===writeTemplate,'EXACT_FIVE_SLOT_RENEWAL_WRITE_REQUIRED');return true;
}
export function createRenewalTransport(ownerToken,{readSql,writeTemplate,window,requestFactory=https.request,now=Date.now}={}){
 must(typeof ownerToken==='string'&&ownerToken.length>=9&&ownerToken.length<=2048&&!/\s/.test(ownerToken)
  &&hash(readSql)===SQL_BINDINGS.read.sha256&&hash(writeTemplate)===SQL_BINDINGS.write.sha256,'EXACT_PRIVATE_RENEWAL_TRANSPORT_REQUIRED');
 const approvedWindow=immutable(window);validateWindow(approvedWindow,now(),90000);
 let count=0,writeCount=0,closed=false;const active=new Set();
 const close=()=>{closed=true;for(const request of active)request.destroy();active.clear();};
 return {close,send:async({phase,query,readOnly,signal,deadline})=>{
  validateWindow(approvedWindow,now(),phase==='readback'?45000:90000);
  must(!closed&&count<3&&phase===['preflight','two-row-expiry-write','readback'][count]&&readOnly===(phase!=='two-row-expiry-write')
   &&Number.isFinite(deadline)&&deadline>now()&&deadline<=now()+45000&&deadline<utc(approvedWindow.expiresAt)
   &&!signal?.aborted,'EXACT_BOUNDED_RENEWAL_TRANSPORT_ORDER_REQUIRED');
  if(readOnly)must(query===readSql,'EXACT_RENEWAL_READ_SQL_REQUIRED');
  else{
   must(writeCount===0,'EXACT_SINGLE_RENEWAL_WRITE_REQUIRED');assertRenderedQuery(query,writeTemplate);writeCount++;
  }
  count++;const body=JSON.stringify({query,read_only:readOnly});
  return new Promise((resolve,reject)=>{let req,timer,settled=false,size=0,sent=false;const chunks=[];
   const cleanup=()=>{clearTimeout(timer);signal?.removeEventListener('abort',abort);if(req)active.delete(req);};
   const fail=code=>{if(settled)return;settled=true;cleanup();req?.destroy();const e=Error(code);e.publicCode=code;e.sent=sent;reject(e);};
   const abort=()=>fail('RENEWAL_TRANSPORT_ABORTED');signal?.addEventListener('abort',abort,{once:true});
   try{
    req=requestFactory(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,{method:'POST',rejectUnauthorized:true,
     headers:{Authorization:`Bearer ${ownerToken}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}},res=>{
     res.on('error',()=>fail('RENEWAL_RESPONSE_UNCERTAIN'));res.on('aborted',()=>fail('RENEWAL_RESPONSE_ABORTED'));
     res.on('data',chunk=>{if(settled)return;size+=chunk.length;if(size>2097152)fail('RENEWAL_RESPONSE_LIMIT');else chunks.push(Buffer.from(chunk));});
     res.on('end',()=>{if(settled)return;settled=true;cleanup();resolve({status:res.statusCode,raw:Buffer.concat(chunks)});});});
    active.add(req);req.on('error',()=>fail('RENEWAL_TRANSPORT_UNCERTAIN'));
    timer=setTimeout(()=>fail('RENEWAL_TRANSPORT_TIMEOUT'),Math.max(1,deadline-now()));
    req.once('socket',socket=>{const send=()=>{if(settled)return;
     if(closed||signal?.aborted||now()>=deadline||now()>=utc(approvedWindow.expiresAt))return fail('RENEWAL_TRANSPORT_EXPIRED');
     if(socket.encrypted!==true||socket.authorized!==true)return fail('VERIFIED_RENEWAL_TLS_REQUIRED');sent=true;req.end(body);};
     if(socket.authorized===true)send();else socket.once('secureConnect',send);});
   }catch{fail('RENEWAL_TRANSPORT_FAILED');}
  });
 }};
}
async function save(relative,value){
 must(publicPath(relative),'FIXED_PUBLIC_RENEWAL_OUTPUT_REQUIRED');const target=path.resolve(root,relative),bytes=Buffer.isBuffer(value)?value:jsonBytes(value);
 const parent=path.dirname(target);must(path.resolve(await fs.realpath(parent))===parent,'RENEWAL_OUTPUT_REDIRECTION_FORBIDDEN');
 const handle=await fs.open(target,'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:relative,sha256:hash(bytes)};
}
export async function main(argv=process.argv.slice(2),{stdin=process.stdin,stdout=process.stdout,now=Date.now,
 preflight=preflightRenewalOperation,run=runRenewal,transportFactory=createRenewalTransport}={}){
 must(argv.length===2&&['--preflight','--execute'].includes(argv[0])&&digest(argv[1]),'EXACT_RENEWAL_LAUNCH_MODE_REQUIRED');
 let checked=await preflight({finalReviewSha256:argv[1],now});
 if(argv[0]==='--preflight'){stdout.write(JSON.stringify(checked.publicResult)+'\n');return checked.publicResult;}
 let input='',config,timer,transport;
 try{
  await Promise.race([(async()=>{for await(const chunk of stdin){input+=chunk;must(input.length<=8192,'BOUNDED_PRIVATE_RENEWAL_INPUT_REQUIRED');}})(),
   new Promise((_,reject)=>{timer=setTimeout(()=>{stdin.destroy?.();reject(Error('PRIVATE_RENEWAL_INPUT_TIMEOUT'));},15000);})]);clearTimeout(timer);
  config=JSON.parse(input);input='';must(keys(config,['projectId','bundleSha256','ownerToken'])&&config.projectId===PROJECT&&config.bundleSha256===BUNDLE,
   'EXACT_MANAGEMENT_ONLY_RENEWAL_INPUT_REQUIRED');
  const refreshed=await preflight({finalReviewSha256:argv[1],now});must(refreshed.planSha256===checked.planSha256,'RENEWAL_PUBLIC_INPUT_CHANGED');checked=refreshed;
  transport=transportFactory(config.ownerToken,{readSql:checked.readSql,writeTemplate:checked.writeTemplate,window:checked.plan.window,now});
  const directory=OWN+'actual-'+randomUUID()+'/';await fs.mkdir(path.join(root,directory));
  const result=await run({checked,transport:transport.send,close:transport.close,now,
   once:value=>save(ONCE,value),persist:(file,value)=>save(directory+file,value),publishReadback:value=>save(READBACK,value)});
  stdout.write(JSON.stringify({passed:true,evidencePath:READBACK,managementAttempts:3,cumulativeChargedCalls:141,actualExports:0})+'\n');return result;
 }finally{clearTimeout(timer);transport?.close();input='';if(config)config.ownerToken='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'RENEWAL_STOPPED',privateErrorPrinted:false,replayPerformed:false})+'\n');process.exitCode=1;
});
