import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {forecastEvent} from '../../workers/wave5/integration_policy.mjs';
import {deliveryTarget as t} from './external_delivery_once_20261103.mjs';
const base='docs/verification/ai-integrations-test-20261103/';
const load=async n=>JSON.parse(await readFile(base+n,'utf8'));
const save=(n,v)=>writeFile(base+n,JSON.stringify(v,null,2)+'\n',{flag:'wx'});
const hash=b=>createHash('sha256').update(b).digest('hex');
if(process.argv[2]==='prepare'){
 let sql=await readFile(base+'external-delivery-acceptance-state.sql','utf8');
 const sourceFields="'body',p.prosrc,'bodyBase64',encode(convert_to(p.prosrc,'UTF8'),'base64'),";
 assert.ok(sql.includes(sourceFields));sql=sql.replace(sourceFields,'');
 const receipt="'sha256',sha256,'receivedAt',received_at";
 assert.ok(sql.includes(receipt));sql=sql.replace(receipt,"'sha256',sha256,'computedSha256',encode(extensions.digest(payload,'sha256'),'hex'),'payloadBase64',encode(payload,'base64'),'payloadBytes',octet_length(payload),'runtimeId',runtime_id,'tenantId',tenant_id,'entityId',legal_entity_id,'branchId',branch_id,'receivedAt',received_at");
 const start=sql.indexOf("select evidence#>>'{delivery,state}' as delivery_state,");assert.ok(start>0);
 sql=sql.slice(0,start)+`select evidence#>>'{delivery,state}' as delivery_state,
 evidence#>>'{outcomes,0,http_status}' as http_status,
 jsonb_array_length(evidence->'receiverReceipts') as receiver_receipts,
 evidence#>>'{usage,quantity}' as webhook_units,
 (select q->>'reserved_units' from jsonb_array_elements(evidence->'quotaPeriods') q where q->>'metric_code'='webhook.deliveries') as webhook_reserved,
 evidence as verified_evidence from snapshot;
rollback;
`;
 await writeFile(base+'external-delivery-accounting.sql',sql,{flag:'wx'});
 console.log(JSON.stringify({readOnly:true,networkCalls:0,deliverySent:false}));
}else if(process.argv[2]==='verify'){
 const before=await load('external-delivery-before-trial.json'),after=await load('external-delivery-accounting.json');
 const sent=await load('external-delivery-send-result.json'),intent=await load('external-delivery-signed-request-intent.json');
 const leased=await load('external-delivery-leased-job.json'),trial=await load('external-delivery-trial-activated.json'),authority=await load('external-delivery-authority-renewed.json');
 const checks=[];const check=(label,fn)=>{fn();checks.push(label);};
 check('actual single-request HTTP 200 acknowledgement',()=>{assert.equal(sent.postCalls,1);assert.equal(sent.automaticRetries,0);assert.equal(sent.outcome.httpStatus,200);assert.equal(sent.outcome.state,'acknowledged');});
 check('original delivery and ledger identities preserved',()=>{for(const [a,b] of [['id','deliveryId'],['invocation_id','invocationId'],['usage_event_id','usageEventId'],['event_id','eventId']])assert.equal(after.delivery[a],t[b]);assert.equal(after.delivery.generation,0);assert.equal(after.delivery.replay_of,null);});
 check('only original head exists and remains acknowledged at attempt 2',()=>{assert.equal(after.allHeads.length,1);assert.equal(after.delivery.state,'acknowledged');assert.equal(after.delivery.attempt,2);assert.equal(after.delivery.lease_id,leased.job.leaseId);});
 check('first immutable attempt and MFA not-sent review preserved',()=>{assert.equal(after.attempts.length,2);assert.deepEqual(after.attempts[0],before.attempts[0]);assert.deepEqual(after.reviews,before.reviews);});
 check('one persisted attempt 2 outcome with actual HTTP 200',()=>{assert.equal(after.outcomes.length,1);assert.equal(after.outcomes[0].attempt,2);assert.equal(after.outcomes[0].state,'acknowledged');assert.equal(after.outcomes[0].http_status,200);assert.equal(after.attempts[1].lease_id,leased.job.leaseId);});
 check('one persisted receiver receipt for the original event and subscription',()=>{assert.equal(after.receiverReceipts.length,1);const r=after.receiverReceipts[0];assert.equal(r.eventId,t.eventId);assert.equal(r.subscriptionId,t.subscriptionId);assert.equal(r.runtimeId,t.runtimeId);assert.equal(r.tenantId,t.tenantId);assert.equal(r.entityId,t.entityId);assert.equal(r.branchId,t.branchId);assert.equal(r.keyVersion,1);});
 const receipt=after.receiverReceipts[0],payload=forecastEvent(leased.job.event,leased.job.subscription.scope);
 check('receiver stored exactly the signed canonical bytes',()=>{assert.ok(Buffer.from(receipt.payloadBase64,'base64').equals(payload));assert.equal(receipt.payloadBytes,payload.length);assert.equal(payload.length,intent.payloadBytes);assert.equal(payload.length,397);});
 check('sender, receiver and independent payload digests match',()=>{assert.equal(hash(payload),intent.payloadSha256);assert.equal(receipt.sha256,intent.payloadSha256);assert.equal(receipt.computedSha256,intent.payloadSha256);assert.equal(receipt.signedTimestamp,intent.signedTimestamp);});
 check('receipt was persisted during the actual leased request',()=>{assert.ok(Date.parse(receipt.receivedAt)>=Date.parse(intent.recordedAt)-1000);assert.ok(Date.parse(receipt.receivedAt)<=Date.parse(sent.observedAt)+1000);assert.ok(Date.parse(receipt.receivedAt)<Date.parse(leased.leaseUntil));});
 check('one original webhook reservation and usage event',()=>{assert.equal(after.reservation.invocation_id,t.invocationId);assert.equal(after.reservation.metric_code,'webhook.deliveries');assert.equal(String(after.reservation.reserved_units),'1');assert.equal(after.usage.invocation_id,t.invocationId);assert.equal(after.usage.event_id,t.usageEventId);assert.equal(String(after.usage.quantity),'1');});
 const quota=after.quotaPeriods.find(q=>q.metric_code==='webhook.deliveries');
 check('exactly one webhook quota period settled 1 with zero outstanding reservation',()=>{assert.equal(after.quotaPeriods.filter(q=>q.metric_code==='webhook.deliveries').length,1);assert.equal(String(quota.settled_units),'1');assert.equal(String(quota.reserved_units),'0');assert.equal(Date.parse(quota.period_start),Date.parse(trial.after.trialStart));assert.equal(Date.parse(quota.period_end),Date.parse(trial.after.trialEnd));assert.equal(Date.parse(after.delivery.period_start),Date.parse(trial.after.trialStart));assert.equal(Date.parse(after.delivery.period_end),Date.parse(trial.after.trialEnd));});
 check('AI invocation count, settled result and quota unchanged',()=>{assert.equal(after.modelInvocationCount,1);assert.deepEqual(after.aiOutcome,{state:'settled',tokens:'247'});assert.deepEqual(after.quotaPeriods.filter(q=>q.metric_code==='ai.tokens'),before.quotaPeriods.filter(q=>q.metric_code==='ai.tokens'));});
 check('all three schedules paused with no scheduler tick',()=>{assert.deepEqual(after.jobs,before.jobs);assert.equal(after.jobs.length,3);assert.ok(after.jobs.every(j=>!j.active));assert.equal(after.tickCount,0);});
 check('four other historical deliveries remain unmaterialized',()=>assert.deepEqual(after.unmaterializedDeliveries,before.unmaterializedDeliveries));
 check('registrations, existing key references and read permissions unchanged',()=>{assert.deepEqual(after.subscriptions,before.subscriptions);assert.deepEqual(after.edgeKeyRefs,before.edgeKeyRefs);assert.deepEqual(after.readerPermissions,before.readerPermissions);assert.equal(after.activeMemberCount,5);assert.equal(after.nonFixtureBillingMemberships,0);assert.deepEqual(after.webhookPlanQuota,before.webhookPlanQuota);});
 check('same five-seat synthetic plan and approved 30-minute trial',()=>{assert.equal(after.syntheticAllowed,true);assert.equal(after.subscription.version,'6');assert.equal(after.subscription.plan,before.subscription.plan);assert.equal(after.subscription.seats,5);assert.equal(Date.parse(after.subscription.trialEnd)-Date.parse(after.subscription.trialStart),1800000);assert.equal(Date.parse(after.subscription.trialStart),Date.parse(trial.after.trialStart));});
 check('approved RT1 runtime and edge authority last exactly 30 minutes',()=>{assert.equal(after.runtimeScopes.length,1);const s=after.runtimeScopes[0];assert.equal(s.branchId,t.branchId);assert.equal(s.tenantId,t.tenantId);assert.equal(s.entityId,t.entityId);assert.equal(Date.parse(s.expiresAt)-Date.parse(s.issuedAt),1800000);assert.equal(Date.parse(after.edgeAuthority.expiresAt)-Date.parse(after.edgeAuthority.issuedAt),1800000);assert.equal(Date.parse(s.expiresAt),Date.parse(authority.runtimeExpiresAt));assert.equal(Date.parse(after.edgeAuthority.expiresAt),Date.parse(authority.edgeExpiresAt));});
 check('all ten reviewed database function bodies and permissions unchanged',()=>{assert.equal(after.functions.length,before.functions.length);for(const f of after.functions){const b=before.functions.find(x=>x.name===f.name&&x.schema===f.schema);for(const k of ['bodyMd5','args','acl','securityDefiner','config'])assert.deepEqual(f[k],b[k]);}});
 const report={observedAt:new Date().toISOString(),databaseObservedAt:after.observedAt,projectId:t.projectId,passed:true,checksPassed:checks.length,checks,deliveryId:t.deliveryId,eventId:t.eventId,invocationId:t.invocationId,usageEventId:t.usageEventId,attempt:2,actualHttpStatus:200,controlledSignedRequests:1,automaticRetries:0,receiverReceipts:1,payloadSha256:receipt.sha256,payloadBytes:payload.length,webhookUsageUnits:'1',webhookQuotaReserved:'0',webhookQuotaSettled:'1',persistedReceiptAndAccountingVerified:true,aiInvocationCount:1,aiSettledTokens:'247',scheduledJobsPaused:true,controlledLocalWorker:true,hostedScheduledDispatchVerified:false,trialEndsAt:after.subscription.trialEnd,runtimeExpiresAt:after.runtimeScopes[0].expiresAt,edgeExpiresAt:after.edgeAuthority.expiresAt,paidPlanOrPaymentMethodAdded:false,ownerAcceptance:false,nativeAcceptance:false};
 await save('external-delivery-usage-reconciled.json',report);console.log(JSON.stringify(report));
}else throw Error('EXPLICIT_PREPARE_OR_VERIFY_MODE_REQUIRED');
