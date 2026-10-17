// Local controlled-test fixture construction only. Never an operation record.
import fs from 'node:fs/promises';
const previous='docs/verification/wave5/seven-area-completion-20261016/area4-integrations/entrypoints.test.mjs';
let tests=(await fs.readFile(previous,'utf8')).replaceAll('../../../../../tools/','../../../../tools/');
tests=tests.replace("from '../../../../tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';","from '../../../../tools/wave5/resume_worker_schedules_20261017_r5_a2.mjs';");
tests+=String.raw`

import * as priorScheduler from '../../../../tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';
import * as conditionalScheduler from '../../../../tools/wave5/resume_worker_schedules_20261017_r5_a2.mjs';
const {SOURCE:SCHEDULER_SOURCE,SCHEDULE_DECISION,HEALTH_DECISION,SCHEDULE_REPLY,WINDOW_RULE,PRECONDITIONS,
 conditionalSchedulerScope,validateConditionalSchedulerDecision}=conditionalScheduler;
function conditionalFixture(){
 const sourceBinding=binding(SCHEDULER_SOURCE),controls={humanScheduleDecision:binding(SCHEDULE_DECISION),humanHealthDecision:binding(HEALTH_DECISION),
 humanRenewalDecision:binding('docs/verification/wave5/runtime-renewal-export-owner-decision-20261016-r5-a7.json'),
 sourcePolicy:binding('docs/verification/wave5/task3-export-renewal-20261016/source-policy-a1.json'),
 independentPolicyReview:binding('docs/verification/wave5/task3-export-renewal-20261016/independent-policy-review-a1.json')};
 const plan={sourceBinding,renewalOperationBundleSha256:'c'.repeat(64),controlBindings:controls,window:structuredClone(window)};
 const realReplyFixture={approved:true,approvalSource:'direct-user-reply',exactReply:SCHEDULE_REPLY,questionItemId:'CONTROLLED-ONLY-QUESTION-ID',
 decidedAt:'2026-10-15T23:59:00Z',projectId:PROJECT,runtimeId:RUNTIME,runtimeBundleSha256:BUNDLE,
 operationBundleSha256:plan.renewalOperationBundleSha256,productionAuthorized:false,realBillingAuthorized:false,
 sourcePolicyBinding:controls.sourcePolicy,independentReviewBinding:controls.independentPolicyReview};
 const human={...realReplyFixture,kind:'direct-human-conditional-renewed-three-job-schedule-resume-decision',conditionalPreapproval:true,
 scheduleResumeAuthorizedByThisDecision:true,sourceBinding,jobIds:[4,5,6],budget:structuredClone(BUDGET),maximumWindowMs:7200000,
 windowRule:structuredClone(WINDOW_RULE),preconditions:structuredClone(PRECONDITIONS),maximumManagementAttempts:3,maximumWorkerRequests:4320,
 independentFinalOperationReviewRequired:true,personalHumanExactWindowSignatureClaimed:false,renewalOwnerDecisionBinding:controls.humanRenewalDecision,
 healthOperationDecisionBinding:controls.humanHealthDecision};
 const scope=conditionalSchedulerScope(plan),documents={
 sourcePolicy:{sourceImplementationOnly:true,liveExecutionAuthorized:false,executionPermitted:false,conditionalSchedulerAuthority:structuredClone(scope)},
 independentPolicyReview:{sourceOnly:true,passed:true,liveExecutionAuthorized:false,executionPermitted:false,policyBinding:controls.sourcePolicy,
 conditionalSchedulerAuthority:structuredClone(scope)},
 humanRenewalDecision:{...realReplyFixture,kind:'direct-human-runtime-renewal-and-export-a7-decision',maximumWindowMs:7200000},
 humanHealthDecision:{...realReplyFixture,kind:'direct-human-renewed-health-scheduler-decision',healthInvocationAuthorized:true,maximumHealthInvocations:1,
 maximumHealthManagementAttempts:5,overallCumulativeMaximum:174,maximumScheduleRequests:4320,healthKeepsSchedulesPaused:true},
 renewalReadback:{serverWindowAnchor:'2026-10-16T00:00:00Z',preflightObservedAt:'2026-10-16T00:00:00Z',serverExpiryAnchor:'2026-10-16T00:00:00Z',
 appliedAt:plan.window.notBefore,applicationTimestampProvenance:'server-post-commit-observation',actualCumulativeChargedCalls:141},
 metadata:{createdAt:'2026-10-15T23:59:30Z',expiresAt:plan.window.privateExpiresAt}};
 return {human,plan,documents,now:instant};
}
const checkConditional=f=>validateConditionalSchedulerDecision(f.human,{plan:f.plan,documents:f.documents,now:f.now});
test('conditional direct preapproval accepts the genuine earlier timestamp without inventing a human exact window',()=>{
 const f=conditionalFixture();assert.equal(checkConditional(f),f.human);assert.equal(Object.hasOwn(f.human,'window'),false);
 assert.ok(Date.parse(f.human.decidedAt)<Date.parse(f.plan.window.notBefore));
});
test('conditional source preserves exact frozen SQL, request caps and nonhuman validation functions',()=>{
 assert.equal(conditionalScheduler.READ_SQL,priorScheduler.READ_SQL);assert.deepEqual(conditionalScheduler.BUDGET,priorScheduler.BUDGET);
 for(const name of ['buildResumeSql','validateTime','validateWindow','validateRenewal','validateRenewalTimeline','validateCallInventory','validateLockInventory',
 'validateHealthResult','validateHealthEvidence','validateProviderAuthority','validateSnapshot','createScheduleTransport','runScheduleResume','exactFile',
 'validateDeployedArchive','validatePreservedSources'])assert.equal(String(conditionalScheduler[name]),String(priorScheduler[name]),name);
 assert.deepEqual(conditionalScheduler.PRESERVED.slice(0,-1),priorScheduler.PRESERVED);
 assert.deepEqual(conditionalScheduler.PRESERVED.at(-1),{path:priorScheduler.SOURCE,sha256:'2b823d111990d2f93f1dcefe62d2bc48c2498a40b333311e4894738928a8604f'});
});
test('conditional source uses distinct additive plan, review, decision and once paths',()=>{
 for(const name of ['SOURCE','PLAN','REVIEW','ONCE'])assert.notEqual(conditionalScheduler[name],priorScheduler[name]);
 assert.match(conditionalScheduler.PLAN,/task3-schedule-resume-20261017/);
 assert.match(conditionalScheduler.SCHEDULE_DECISION,/conditional-schedule-owner-decision/);
 assert.equal(conditionalScheduler.PRIVATE_ADAPTER,priorScheduler.PRIVATE_ADAPTER);
});
test('conditional contract rejects a blanket approval, later exact-window record or fabricated human window',()=>{
 for(const change of [f=>f.human={approved:true},f=>f.human.kind='direct-human-exact-renewed-three-job-schedule-resume-decision',
 f=>f.human.window=f.plan.window,f=>f.human.personalHumanExactWindowSignatureClaimed=true,f=>f.human.conditionalPreapproval=false,
 f=>f.human.independentFinalOperationReviewRequired=false]){const f=conditionalFixture();change(f);assert.throws(()=>checkConditional(f));}
});
test('conditional contract rejects unrelated reply, question or timestamp instead of copying claimed authority',()=>{
 for(const change of [f=>f.human.exactReply='go ahead',f=>f.documents.humanRenewalDecision.questionItemId='UNRELATED-QUESTION-ID',
 f=>f.documents.humanHealthDecision.questionItemId='UNRELATED-QUESTION-ID',f=>f.documents.humanRenewalDecision.decidedAt='2026-10-15T23:58:59Z',
 f=>f.documents.humanHealthDecision.exactReply='Approve something else',f=>f.documents.humanHealthDecision.approvalSource='agent-decision',
 f=>f.documents.humanRenewalDecision.approved=false]){const f=conditionalFixture();change(f);assert.throws(()=>checkConditional(f));}
});
test('conditional contract binds the exact new source, bundle and all three owner/health/scope record hashes',()=>{
 for(const change of [f=>f.human.sourceBinding={...f.plan.sourceBinding,sha256:'f'.repeat(64)},f=>f.human.operationBundleSha256='f'.repeat(64),
 f=>f.human.renewalOwnerDecisionBinding={...f.human.renewalOwnerDecisionBinding,sha256:'f'.repeat(64)},
 f=>f.human.healthOperationDecisionBinding={...f.human.healthOperationDecisionBinding,sha256:'f'.repeat(64)},
 f=>f.human.sourcePolicyBinding={...f.human.sourcePolicyBinding,sha256:'f'.repeat(64)},
 f=>f.human.independentReviewBinding={...f.human.independentReviewBinding,sha256:'f'.repeat(64)},
 f=>f.documents.humanHealthDecision.operationBundleSha256='f'.repeat(64),f=>f.plan.sourceBinding.path=priorScheduler.SOURCE]){
 const f=conditionalFixture();change(f);assert.throws(()=>checkConditional(f));}
});
test('both source policy and independent scope review must approve the exact conditional source contract without execution permission',()=>{
 for(const change of [f=>delete f.documents.sourcePolicy.conditionalSchedulerAuthority,
 f=>f.documents.independentPolicyReview.conditionalSchedulerAuthority.maximumWindowMs=7200001,
 f=>f.documents.sourcePolicy.liveExecutionAuthorized=true,f=>f.documents.independentPolicyReview.executionPermitted=true,
 f=>f.documents.independentPolicyReview.passed=false,f=>f.documents.independentPolicyReview.policyBinding={...f.plan.controlBindings.sourcePolicy,sha256:'f'.repeat(64)}]){
 const f=conditionalFixture();change(f);assert.throws(()=>checkConditional(f));}
});
test('conditional preapproval cannot move after renewal or be laundered through a fake late health timestamp',()=>{
 for(const stamp of ['2026-10-16T00:00:01Z','2026-10-16T00:00:03Z','2026-10-16T01:00:00Z']){
 const f=conditionalFixture();for(const v of [f.human,f.documents.humanRenewalDecision,f.documents.humanHealthDecision])v.decidedAt=stamp;
 assert.throws(()=>checkConditional(f),/PREAPPROVAL_BEFORE_RENEWAL/);}
});
test('conditional actual window uses exact server preflight rather than later application time',()=>{
 const f=conditionalFixture();for(const key of ['edgeExpiresAt','scopeExpiresAt','expiresAt'])f.plan.window[key]='2026-10-16T02:00:02Z';
 f.plan.window.privateExpiresAt='2026-10-16T03:00:00Z';f.documents.metadata.expiresAt=f.plan.window.privateExpiresAt;
 assert.throws(()=>checkConditional(f),/ACTUAL_CONDITIONAL_WINDOW_RULE/);
});
test('conditional window is exactly truncated by the actual A10 expiry',()=>{
 const f=conditionalFixture();for(const key of ['edgeExpiresAt','scopeExpiresAt','privateExpiresAt','expiresAt'])f.plan.window[key]='2026-10-16T01:00:00Z';
 f.documents.metadata.expiresAt=f.plan.window.privateExpiresAt;assert.equal(checkConditional(f),f.human);
});
test('conditional maximum window retains microseconds and allows UTC midnight crossing',()=>{
 const f=conditionalFixture();for(const v of [f.human,f.documents.humanRenewalDecision,f.documents.humanHealthDecision])v.decidedAt='2026-10-15T23:40:00Z';
 f.documents.metadata.createdAt='2026-10-15T23:45:00Z';
 for(const k of ['serverWindowAnchor','preflightObservedAt','serverExpiryAnchor'])f.documents.renewalReadback[k]='2026-10-15T23:50:00.123456Z';
 f.documents.renewalReadback.appliedAt=f.plan.window.notBefore='2026-10-15T23:50:02Z';
 for(const k of ['edgeExpiresAt','scopeExpiresAt','privateExpiresAt','expiresAt'])f.plan.window[k]='2026-10-16T01:50:00.123456Z';
 f.documents.metadata.expiresAt=f.plan.window.privateExpiresAt;assert.equal(checkConditional(f),f.human);
 f.plan.window.edgeExpiresAt=f.plan.window.scopeExpiresAt=f.plan.window.expiresAt='2026-10-16T01:50:00.123457Z';
 assert.throws(()=>checkConditional(f));
});
test('conditional bound cannot omit original seven-day guards or broaden job IDs, management or model/delivery scope',()=>{
 for(const change of [f=>f.human.jobIds=[4,5,6,7],f=>f.human.maximumManagementAttempts=4,f=>f.human.maximumWorkerRequests=4321,
 f=>f.human.maximumWindowMs=7200001,f=>f.human.windowRule.preserveOriginalSevenDayGuards=false,
 f=>f.human.windowRule.expiresAt='application-time-plus-two-hours',f=>f.human.budget.overallMaximum=175,
 f=>f.human.productionAuthorized=true,f=>f.human.realBillingAuthorized=true,f=>f.documents.humanHealthDecision.maximumHealthInvocations=2]){
 const f=conditionalFixture();change(f);assert.throws(()=>checkConditional(f));}
});
test('conditional approval requires every stated actual precondition, not an undifferentiated approved flag',()=>{
 for(const key of Object.keys(PRECONDITIONS)){const f=conditionalFixture();f.human.preconditions[key]=false;assert.throws(()=>checkConditional(f));}
});
test('conditional actual-window gate rejects missing provenance, changed charge, false aliases and post-preflight owner refresh',()=>{
 for(const change of [f=>f.documents.renewalReadback.applicationTimestampProvenance='client-time',f=>f.documents.renewalReadback.actualCumulativeChargedCalls=138,
 f=>f.documents.renewalReadback.preflightObservedAt=f.plan.window.notBefore,f=>f.documents.renewalReadback.serverExpiryAnchor=f.plan.window.notBefore,
 f=>f.documents.metadata.createdAt='2026-10-16T00:00:01Z',f=>f.documents.humanHealthDecision.healthKeepsSchedulesPaused=false]){
 const f=conditionalFixture();change(f);assert.throws(()=>checkConditional(f));}
});
test('conditional contract rejects expired or over-seven-day authority before any later operation claim',()=>{
 const f=conditionalFixture();f.now=Date.parse(f.plan.window.expiresAt);assert.throws(()=>checkConditional(f),/EXPIRED/);
 const g=conditionalFixture();g.plan.window={notBefore:'2026-10-20T08:00:00Z',edgeExpiresAt:'2026-10-20T09:00:00Z',scopeExpiresAt:'2026-10-20T09:00:00Z',
 privateExpiresAt:'2026-10-20T09:00:00Z',expiresAt:'2026-10-20T09:00:00Z'};assert.throws(()=>checkConditional(g));
});
`;
await fs.writeFile('docs/verification/wave5/task3-schedule-resume-20261017/resume_worker_schedules_20261017_r5_a2.test.mjs',tests,{flag:'wx'});
console.log(JSON.stringify({sourceOnly:true,controlledFixtures:true,actualOperationRecordsCreated:0}));
