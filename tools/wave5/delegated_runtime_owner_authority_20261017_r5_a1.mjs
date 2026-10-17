// Pure authority validation. No files, credentials, network, approvals or receipts
// are created here. Callers must hash-check both public evidence documents.
import {isDeepStrictEqual as same} from 'node:util';

export const SOURCE='tools/wave5/delegated_runtime_owner_authority_20261017_r5_a1.mjs';
export const OWNER_DECISION_PATH='docs/verification/wave5/runtime-continuation-delegated-owner-decision-20261017-r5-a1.json';
const BASE='docs/verification/wave5/root-runtime-review-20261017/';
export const AUTHORITY_BINDINGS=Object.freeze({
 evidence:Object.freeze({path:BASE+'owner-authority-evidence-a1.json',sha256:'57a323baaff79abf49208a236a1867848fed678e46e645974e6a437a504f7d68'}),
 audit:Object.freeze({path:BASE+'owner-authority-audit-a1.json',sha256:'e5210fd9dad727154b7a918e58592e934dd970a144e3787d589782db87b20896'})
});
export const PROJECT='xpdoufauvrbdmxgngetv',RUNTIME='778237e3-3d4e-4871-8cc9-e08b07b989c7';
export const BUNDLE='db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
export const SCOPE=Object.freeze({tenantId:'babe6c86-a764-4d3a-80a3-952a7c096c2c',legalEntityId:'caa2bb06-219a-47e9-8132-66d1271b0ffd',branchId:'3813692c-f0de-4c69-8e34-d56cf54695b1'});
export const BUDGET=Object.freeze({recordedPrior:137,ownerRefreshCalls:1,renewalControlCalls:3,prior:141,ordinary:24,ordinaryLimit:165,resolution:1,total:166});
export const PHASES=Object.freeze(['renewal','exports','health','scheduler']);
export const WINDOW_RULE=Object.freeze({anchor:'actual-renewal-server-preflight',maximumWindowMs:7200000,
 expiresAt:'min(serverWindowAnchor+maximumWindowMs,actualA10Metadata.expiresAt)',preserveOriginalIssuedAt:true,preserveOriginalSevenDayGuards:true});
export const PRECONDITIONS=Object.freeze({actualTwoRowRenewalWithThreeRawReceipts:true,twoOriginalExportsCompleted:true,
 oneAuthenticatedDeployedV7HealthPassed:true,schedulesPausedUntilFinalReview:true,independentFinalReviewOfActualWindowAndReceipts:true});
const must=(ok,code)=>{if(!ok){const e=Error(code);e.publicCode=code;throw e;}};
const digest=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const binding=x=>x&&typeof x.path==='string'&&digest(x.sha256)&&same(Object.keys(x).sort(),['path','sha256']);
const utc=x=>{must(typeof x==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|\+00:00)$/.test(x),'DELEGATED_EXPLICIT_UTC_REQUIRED');
 const t=Date.parse(x);must(Number.isFinite(t)&&new Date(t).toISOString().slice(0,19)===x.slice(0,19),'DELEGATED_VALID_UTC_REQUIRED');return t;};

export function validateDelegatedOwnerDecision(record,{policy,policyBinding,policyReviewBinding,evidence,audit,now=Date.now(),phase,sourceBinding}={}){
 must(PHASES.includes(phase)&&Number.isFinite(now),'EXACT_DELEGATED_PHASE_REQUIRED');
 must(binding(policyBinding)&&binding(policyReviewBinding)&&binding(sourceBinding),'DELEGATED_POLICY_AND_SOURCE_BINDINGS_REQUIRED');
 must(evidence?.kind==='independently-retrieved-explicit-user-owner-delegation-evidence'&&evidence.version===1
  &&evidence.source?.threadId==='01a13650-c557-70d3-bb66-3c40b2a71efb'&&evidence.source.role==='user'
  &&Array.isArray(evidence.sourceItems)&&evidence.sourceItems.length===5
  &&evidence.sourceItems.every(x=>x.role==='user'&&x.sourceItemType==='userMessage'&&x.sourceTextTruncated===false
   &&x.exactUserMessageTimestampAvailable===false&&x.userMessageTimestamp===null)
  &&evidence.sourceItems.some(x=>x.userItemId==='01a13667-4300-7d90-bc3b-2c4b40391c33'&&x.text.includes('act as the owner and do it your self'))
  &&evidence.sourceItems.some(x=>x.userItemId==='01a13685-c880-7051-8e13-aaaa35479a99'&&x.text.includes("don't ask me again"))
  &&evidence.ownerRuntimeApprovalCreated===false&&evidence.agentOperationDecisionRecorded===false,'GENUINE_USER_DELEGATION_EVIDENCE_REQUIRED');
 must(audit?.kind==='independent-owner-delegation-authority-audit'&&audit.version===1&&audit.allowedTechnicalApproval===true
  &&audit.personalSignoff===false&&audit.explicitUserOwnerDelegationVerified===true
  &&same(({path,sha256})=>({path,sha256}),({path,sha256})=>({path,sha256}))===false,'INDEPENDENT_DELEGATION_AUDIT_REQUIRED');
 // Evidence bindings may include a recorded byte count in the immutable audit.
 must(audit.authorityEvidenceBinding?.path===AUTHORITY_BINDINGS.evidence.path&&audit.authorityEvidenceBinding.sha256===AUTHORITY_BINDINGS.evidence.sha256
  &&audit.executionBoundary?.authorityAssessmentOnly===true&&audit.executionBoundary.ownerApprovalRecordCreated===false
  &&audit.honestRecordInterface?.humanReplyTimestampAvailable===false,'EXACT_DELEGATION_AUDIT_LINEAGE_REQUIRED');
 const limits=audit.authorityLimits;
 must(limits?.projectId===PROJECT&&limits.runtimeId===RUNTIME&&limits.runtimeBundleSha256===BUNDLE&&same(limits.scope,SCOPE)
  &&limits.accounting?.recordedActualPrior===137&&limits.accounting.cumulativeMaximum===174&&limits.accounting.newMaximumCountedAttempts===37
  &&limits.renewal?.maximumWindowMs===7200000&&limits.renewal.maximumRows===2&&limits.renewal.issuedAtMustRemainUnchanged===true
  &&limits.health?.maximumActualInvocations===1&&limits.health.maximumManagementAttempts===5
  &&same(limits.scheduler?.exactJobIds,[4,5,6])&&limits.scheduler.unconditionalResumeAllowed===false
  &&limits.inheritedWorkerBounds?.newModelInvocationsIncludedInThisContinuation===0,'ORIGINAL_BOUNDED_DELEGATION_LIMITS_REQUIRED');
 must(same(policy?.delegatedAuthorityBindings?.evidence,AUTHORITY_BINDINGS.evidence)&&same(policy.delegatedAuthorityBindings.audit,AUTHORITY_BINDINGS.audit)
  &&binding(policy.delegatedAuthorityBindings.module)&&policy.delegatedAuthorityBindings.module.path===SOURCE
  &&same(Object.keys(policy.delegatedPhaseSourceBindings??{}).sort(),[...PHASES].sort())
  &&Object.values(policy.delegatedPhaseSourceBindings).every(binding)&&same(policy.delegatedPhaseSourceBindings[phase],sourceBinding),
  'REVIEWED_DELEGATED_PHASE_SOURCE_REQUIRED');
 must(record?.kind==='delegated-owner-runtime-continuation-approval'&&record.version===1&&record.approved===true
  &&record.approvalSource==='explicit-user-owner-delegation'&&record.decisionMaker==='Codex delegated technical owner'
  &&record.technicalApprovalOnly===true&&record.personalHumanSignatureClaimed===false&&record.personalWholeSystemSignoff===false
  &&!Object.hasOwn(record,'exactReply')&&!Object.hasOwn(record,'questionItemId')&&!Object.hasOwn(record,'humanReplyAt')&&!Object.hasOwn(record,'window'),
  'HONEST_DELEGATED_TECHNICAL_DECISION_REQUIRED');
 must(record.projectId===PROJECT&&record.runtimeId===RUNTIME&&record.runtimeBundleSha256===BUNDLE&&same(record.scope,SCOPE)
  &&same(record.authorityEvidenceBinding,AUTHORITY_BINDINGS.evidence)&&same(record.authorityAuditBinding,AUTHORITY_BINDINGS.audit)
  &&same(record.authorityLimits,limits)&&same(record.permittedPhases,PHASES)&&same(record.budget,BUDGET)
  &&record.operationBundleSha256===policy.renewalOperationBundleSha256&&digest(record.operationBundleSha256)
  &&same(record.sourcePolicyBinding,policyBinding)&&same(record.independentReviewBinding,policyReviewBinding),
  'EXACT_DELEGATED_OPERATION_AND_SCOPE_REQUIRED');
 must(record.maximumWindowMs===7200000&&record.onlyTwoExpiryFieldsMayChange===true&&record.schedulesMustRemainPaused===true
  &&record.overallCumulativeMaximum===174&&record.maximumHealthInvocations===1&&record.maximumHealthManagementAttempts===5
  &&record.healthInvocationAuthorized===true&&record.healthKeepsSchedulesPaused===true&&record.maximumScheduleRequests===4320
  &&same(record.conditionalScheduler,{jobIds:[4,5,6],windowRule:WINDOW_RULE,preconditions:PRECONDITIONS})
  &&record.productionAuthorized===false&&record.realBillingAuthorized===false&&record.newModelInvocationsAuthorized===0,
  'FINITE_DELEGATED_RUNTIME_CAPS_REQUIRED');
 must(utc(record.decidedAt)>=utc(audit.reviewedAt)&&utc(record.decidedAt)<=now,'ACTUAL_AGENT_DECISION_TIME_REQUIRED');
 return record;
}
