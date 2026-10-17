// Additive source generation only. No operation record or authority is created.
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
const sha=x=>createHash('sha256').update(x).digest('hex');
const oldPath='tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';
const old=await fs.readFile(oldPath);
if(sha(old)!=='2b823d111990d2f93f1dcefe62d2bc48c2498a40b333311e4894738928a8604f')throw Error('FROZEN_A1_SOURCE_CHANGED');
let code=old.toString('utf8');
function replace(a,b){if(code.split(a).length!==2)throw Error('EXACT_SINGLE_REPLACEMENT_REQUIRED');code=code.replace(a,b);}
replace("export const SOURCE='tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';","export const SOURCE='tools/wave5/resume_worker_schedules_20261017_r5_a2.mjs';");
replace("export const PLAN='docs/verification/wave5/task3-schedule-resume-20261014/renewed-execution-plan-20261015-r5-a1.json';","export const PLAN='docs/verification/wave5/task3-schedule-resume-20261017/renewed-execution-plan-20261017-r5-a2.json';");
replace("export const REVIEW='docs/verification/wave5/task3-schedule-resume-20261014/final-operation-review-20261015-r5-a1.json';","export const REVIEW='docs/verification/wave5/task3-schedule-resume-20261017/final-operation-review-20261017-r5-a2.json';");
replace("export const ONCE='docs/verification/wave5/task3-schedule-resume-20261014/resume-once-20261015-r5-a1.json';","export const ONCE='docs/verification/wave5/task3-schedule-resume-20261017/resume-once-20261017-r5-a2.json';");
replace("export const SCHEDULE_REPLY='Approve the exact renewed V7 three-job schedule resume';",`export const SCHEDULE_REPLY='Approve the exact two-row runtime renewal and export a7 continuation';
export const SCHEDULE_DECISION='docs/verification/wave5/task3-schedule-resume-20261017/conditional-schedule-owner-decision-20261017-r5-a2.json';
export const HEALTH_DECISION='docs/verification/wave5/runtime-renewed-health-scheduler-owner-decision-20261015-r5-a1.json';
export const WINDOW_RULE=Object.freeze({anchor:'actual-renewal-server-preflight',maximumWindowMs:7200000,
 expiresAt:'min(serverWindowAnchor+maximumWindowMs,actualA10Metadata.expiresAt)',preserveOriginalIssuedAt:true,preserveOriginalSevenDayGuards:true});
export const PRECONDITIONS=Object.freeze({actualTwoRowRenewalWithThreeRawReceipts:true,twoOriginalExportsCompleted:true,
 oneAuthenticatedDeployedV7HealthPassed:true,schedulesPausedUntilFinalReview:true,independentFinalReviewOfActualWindowAndReceipts:true});`);
replace(' providerAuthorityReview:PROVIDER_REVIEW});',' providerAuthorityReview:PROVIDER_REVIEW,humanHealthDecision:HEALTH_DECISION,humanScheduleDecision:SCHEDULE_DECISION});');
replace(' RENEWAL_PROPOSAL,CALL_INVENTORY,ARCHIVE_MANIFEST].map(row=>Object.freeze({...row})));',` RENEWAL_PROPOSAL,CALL_INVENTORY,ARCHIVE_MANIFEST,
 {path:'tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs',sha256:'2b823d111990d2f93f1dcefe62d2bc48c2498a40b333311e4894738928a8604f'}].map(row=>Object.freeze({...row})));`);
const start=code.indexOf(' const human=documents.humanScheduleDecision;\n',code.indexOf('export function validateFinalReview('));
const end=code.indexOf('\nexport function validateSnapshot(',start);
if(start<0||end<0)throw Error('EXACT_DECISION_BLOCK_REQUIRED');
code=code.slice(0,start)+` validateConditionalSchedulerDecision(documents.humanScheduleDecision,{plan,documents,now});return review;
}

// One genuine reply may conditionally authorize the later resume. It does not
// purport to approve timestamps or receipts that did not yet exist. The normal
// final review above still validates the complete ACTUAL plan and evidence.
export function conditionalSchedulerScope(plan){
 return {sourceBinding:plan.sourceBinding,operationBundleSha256:plan.renewalOperationBundleSha256,jobIds:[4,5,6],budget:BUDGET,
  maximumWindowMs:7200000,windowRule:WINDOW_RULE,preconditions:PRECONDITIONS};
}
export function validateConditionalSchedulerDecision(human,{plan,documents,now=Date.now()}={}){
 validateTime(now,plan?.window);
 const controls=plan.controlBindings,owner=documents.humanRenewalDecision,health=documents.humanHealthDecision;
 const scope=conditionalSchedulerScope(plan),policy=documents.sourcePolicy,policyReview=documents.independentPolicyReview;
 must(receipt(plan.sourceBinding)&&plan.sourceBinding.path===SOURCE&&digest(plan.renewalOperationBundleSha256)
  &&controls.humanScheduleDecision?.path===SCHEDULE_DECISION&&receipt(controls.humanScheduleDecision)
  &&controls.humanHealthDecision?.path===HEALTH_DECISION&&receipt(controls.humanHealthDecision),
  'EXACT_CONDITIONAL_SCHEDULER_SOURCE_AND_DECISION_BINDINGS_REQUIRED');
 must(policy?.sourceImplementationOnly===true&&policy.liveExecutionAuthorized===false&&policy.executionPermitted===false
  &&policyReview?.sourceOnly===true&&policyReview.passed===true&&policyReview.liveExecutionAuthorized===false&&policyReview.executionPermitted===false
  &&same(policyReview.policyBinding,controls.sourcePolicy)&&same(policy.conditionalSchedulerAuthority,scope)
  &&same(policyReview.conditionalSchedulerAuthority,scope),'EXACT_REVIEWED_CONDITIONAL_SCHEDULER_SCOPE_REQUIRED');
 must(human?.kind==='direct-human-conditional-renewed-three-job-schedule-resume-decision'&&human.approved===true
  &&human.approvalSource==='direct-user-reply'&&human.exactReply===SCHEDULE_REPLY&&typeof human.questionItemId==='string'&&human.questionItemId.length>=16
  &&human.projectId===PROJECT&&human.runtimeBundleSha256===BUNDLE&&human.runtimeId===RUNTIME&&human.conditionalPreapproval===true
  &&human.scheduleResumeAuthorizedByThisDecision===true&&same(human.sourceBinding,plan.sourceBinding)
  &&human.operationBundleSha256===plan.renewalOperationBundleSha256&&same(human.budget,BUDGET)&&same(human.jobIds,[4,5,6])
  &&human.maximumWindowMs===7200000&&same(human.windowRule,WINDOW_RULE)&&same(human.preconditions,PRECONDITIONS)
  &&human.maximumManagementAttempts===3&&human.maximumWorkerRequests===4320&&human.independentFinalOperationReviewRequired===true
  &&human.personalHumanExactWindowSignatureClaimed===false&&!Object.hasOwn(human,'window')
  &&human.productionAuthorized===false&&human.realBillingAuthorized===false
  &&same(human.renewalOwnerDecisionBinding,controls.humanRenewalDecision)&&same(human.healthOperationDecisionBinding,controls.humanHealthDecision)
  &&same(human.sourcePolicyBinding,controls.sourcePolicy)&&same(human.independentReviewBinding,controls.independentPolicyReview),
  'EXPLICIT_CONDITIONAL_DIRECT_HUMAN_SCHEDULER_DECISION_REQUIRED');
 const sameReply=record=>record?.approved===true&&record.approvalSource==='direct-user-reply'&&record.exactReply===human.exactReply
  &&record.questionItemId===human.questionItemId&&record.decidedAt===human.decidedAt&&record.projectId===PROJECT&&record.runtimeId===RUNTIME
  &&record.runtimeBundleSha256===BUNDLE&&record.operationBundleSha256===human.operationBundleSha256
  &&record.productionAuthorized===false&&record.realBillingAuthorized===false;
 must(owner?.kind==='direct-human-runtime-renewal-and-export-a7-decision'&&sameReply(owner)&&owner.maximumWindowMs===7200000
  &&same(owner.sourcePolicyBinding,controls.sourcePolicy)&&same(owner.independentReviewBinding,controls.independentPolicyReview)
  &&health?.kind==='direct-human-renewed-health-scheduler-decision'&&sameReply(health)
  &&health.healthInvocationAuthorized===true&&health.maximumHealthInvocations===1&&health.maximumHealthManagementAttempts===5
  &&health.overallCumulativeMaximum===174&&health.maximumScheduleRequests===4320&&health.healthKeepsSchedulesPaused===true
  &&same(health.sourcePolicyBinding,controls.sourcePolicy)&&same(health.independentReviewBinding,controls.independentPolicyReview),
  'SAME_GENUINE_OWNER_HEALTH_AND_REVIEWED_SCOPE_REQUIRED');
 const r=documents.renewalReadback,metadata=documents.metadata,anchor=micros(r.serverWindowAnchor),applied=micros(r.appliedAt);
 must(micros(human.decidedAt)<=anchor&&anchor<=applied&&applied===micros(plan.window.notBefore)&&utc(human.decidedAt)<=now
  &&sameTime(r.preflightObservedAt,r.serverWindowAnchor)&&sameTime(r.serverExpiryAnchor,r.serverWindowAnchor)
  &&r.applicationTimestampProvenance==='server-post-commit-observation'&&r.actualCumulativeChargedCalls===141
  &&micros(metadata.createdAt)>=micros(human.decidedAt)&&micros(metadata.createdAt)<=anchor,
  'ACTUAL_CONDITIONAL_PREAPPROVAL_BEFORE_RENEWAL_TIMELINE_REQUIRED');
 const ceiling=anchor+7200000000n,ownerExpiry=micros(metadata.expiresAt),expiry=ceiling<ownerExpiry?ceiling:ownerExpiry;
 must(micros(plan.window.edgeExpiresAt)===expiry&&micros(plan.window.scopeExpiresAt)===expiry&&micros(plan.window.expiresAt)===expiry
  &&micros(plan.window.privateExpiresAt)===ownerExpiry,'ACTUAL_CONDITIONAL_WINDOW_RULE_REQUIRED');
 return human;
}
`+code.slice(end);
replace("const directory='docs/verification/wave5/task3-schedule-resume-20261014/actual-renewed-a1-'+now()+'/';","const directory='docs/verification/wave5/task3-schedule-resume-20261017/actual-conditional-a2-'+now()+'/';");
await fs.writeFile('tools/wave5/resume_worker_schedules_20261017_r5_a2.mjs',code,{flag:'wx'});
console.log(JSON.stringify({sourceOnly:true,oldPath,oldSha256:sha(old),newPath:'tools/wave5/resume_worker_schedules_20261017_r5_a2.mjs',newSha256:sha(code),oldSourceUnchanged:sha(await fs.readFile(oldPath))===sha(old)}));
