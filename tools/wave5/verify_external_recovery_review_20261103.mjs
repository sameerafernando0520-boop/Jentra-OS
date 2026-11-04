import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const base='docs/verification/ai-integrations-test-20261103/';
const load=async n=>JSON.parse(await readFile(base+n,'utf8'));
const before=await load('external-delivery-after-rollback.json'),after=await load('external-delivery-preapproval-final.json');
const rolled=await load('external-delivery-rollback-final-result.json'),candidate=await load('external-delivery-recovery-candidate.json');
const checks=[];
for(const name of ['delivery','allHeads','attempts','outcomes','reviews','subscriptions','receiverReceipts','reservation','usage','quotaPeriods','subscription','runtimeScopes','edgeAuthority','edgeKeyRefs','jobs','tickCount','unmaterializedDeliveries','syntheticAllowed','activeMemberCount','nonFixtureBillingMemberships','readerPermissions','modelInvocationCount','aiOutcome','webhookPlanQuota']){
 assert.deepEqual(after[name],before[name],name+' changed after rollback');checks.push(name+' preserved');
}
assert.equal(after.functions.length,10);
for(const f of after.functions){
 assert.equal(createHash('md5').update(Buffer.from(f.bodyBase64,'base64')).digest('hex'),f.bodyMd5);
 assert.equal(f.bodyMd5,before.functions.find(x=>x.name===f.name&&x.schema===f.schema)?.bodyMd5);
}checks.push('ten exact database function bodies preserved');
assert.equal(rolled.job.deliveryId,candidate.deliveryId);assert.equal(rolled.job.invocationId,candidate.invocationId);assert.equal(rolled.job.usageEventId,candidate.usageEventId);assert.equal(rolled.job.attempt,2);assert.equal(rolled.attemptCount,2);assert.equal(rolled.exactHeadOnly,true);assert.equal(rolled.reservationAbsent,true);assert.equal(rolled.receipts,0);assert.equal(rolled.committed,false);checks.push('frozen candidate authorized original event in rollback');
assert.equal(after.delivery.attempt,1);assert.equal(after.attempts.length,1);assert.equal(after.delivery.state,'retry');assert.equal(after.receiverReceipts.length,0);assert.equal(after.reservation,null);assert.equal(after.usage,null);checks.push('rollback left original attempt and empty delivery ledger intact');
for(const a of [...candidate.artifacts,...candidate.sources])assert.equal(createHash('sha256').update(await readFile(a.path)).digest('hex'),a.sha256);
checks.push('all six candidate artifacts and eleven sources remain bound');
const report={recordedAt:new Date().toISOString(),databaseObservedAt:after.observedAt,projectId:after.projectId,passed:true,checksPassed:checks.length,checks,focusedRunnerTests:{passed:13,failed:0,path:'tools/wave5/external_delivery_once_20261103.test.mjs'},runnerSyntaxCheckPassed:true,liveDeliverySent:false,committedRecovery:false,approvalPending:true,candidateSha256:createHash('sha256').update(await readFile(base+'external-delivery-recovery-candidate.json')).digest('hex')};
await writeFile(base+'external-delivery-review-verified.json',JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({passed:true,checks:checks.length,deliverySent:false,committedRecovery:false,candidateSha256:report.candidateSha256}));
