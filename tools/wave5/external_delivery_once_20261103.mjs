import {createHash} from 'node:crypto';
import {forecastEvent} from '../../workers/wave5/integration_policy.mjs';

export const deliveryTarget=Object.freeze({
 projectId:'xpdoufauvrbdmxgngetv',runtimeId:'778237e3-3d4e-4871-8cc9-e08b07b989c7',
 tenantId:'babe6c86-a764-4d3a-80a3-952a7c096c2c',entityId:'caa2bb06-219a-47e9-8132-66d1271b0ffd',branchId:'3813692c-f0de-4c69-8e34-d56cf54695b1',
 deliveryId:'091e0c08-5038-4169-8e28-ffde9e0d51c8',invocationId:'257b49a7-0be2-4319-b6bd-a574ae9bb59f',usageEventId:'ebc3757e-6a2c-4458-b7a2-1db39d473bef',
 eventId:'a10d0346-b9c6-474a-a3fc-d643602b8b5e',forecastId:'5719b23f-757b-4da8-8cf7-47d82103415c',
 sourceHash:'89de69a7ec67c48c110b4416042239f174a7f7a95bff4c5b0f2e023d2dc194a7',subscriptionId:'58699e8a-28fd-4356-8cad-87ce46e17ddd',
 receiverUrl:'https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-receiver/accept',
});
const must=(v,c)=>{if(!v)throw Error(c);};
export const bytesSha256=b=>createHash('sha256').update(b).digest('hex');

export function validateExactLeasedDelivery(snapshot,now=Date.now()){
 const t=deliveryTarget,j=snapshot?.job;
 must(snapshot?.projectId===t.projectId&&Date.parse(snapshot.observedAt)<=now+5000&&Date.parse(snapshot.observedAt)>=now-25000&&Date.parse(snapshot.leaseUntil)>now+25000,'FRESH_LEASE_REQUIRED');
 must(snapshot.exactHeadOnly===true&&snapshot.attemptCount===2&&snapshot.receipts===0&&snapshot.reservationAbsent===true&&snapshot.scheduledJobsPaused===true,'EXACT_UNSENT_LEASE_REQUIRED');
 must(j?.deliveryId===t.deliveryId&&j.invocationId===t.invocationId&&j.usageEventId===t.usageEventId&&j.attempt===2&&/^[a-f0-9-]{36}$/.test(j.leaseId),'ORIGINAL_DELIVERY_IDENTITIES_REQUIRED');
 must(j.event?.eventId===t.eventId&&j.event.forecastId===t.forecastId&&j.event.sourceHash===t.sourceHash&&j.event.tenantId===t.tenantId&&j.event.legalEntityId===t.entityId&&j.event.branchId===t.branchId,'ORIGINAL_COMMITTED_EVENT_REQUIRED');
 const s=j.subscription;
 must(s?.id===t.subscriptionId&&s.enabled===true&&s.keyVersion===1&&s.url===t.receiverUrl&&JSON.stringify(s.allowedHosts)===JSON.stringify([new URL(t.receiverUrl).hostname])&&s.scope?.tenantId===t.tenantId&&s.scope.legalEntityId===t.entityId&&s.scope.branchId===t.branchId,'EXACT_RECEIVER_REQUIRED');
 must(Date.parse(j.periodStart)<=now&&Date.parse(j.periodEnd)>now+120000&&Date.parse(j.periodEnd)-Date.parse(j.periodStart)===1800000,'APPROVED_BILLING_PERIOD_REQUIRED');
 forecastEvent(j.event,s.scope);
 return j;
}

// Consume the single attempt before invoking the transport. Neither a rejected
// response nor a thrown network error permits this closure to send again.
export function createExactSinglePost({job,post,persistIntent,now=()=>Date.now()}){
 const expected=forecastEvent(job.event,job.subscription.scope),hash=bytesSha256(expected);
 let consumed=false;
 return async(destination,payload,headers,signal)=>{
  must(!consumed,'ONE_SIGNED_REQUEST_LIMIT');consumed=true;
  must(destination?.url===deliveryTarget.receiverUrl&&destination.hostname===new URL(deliveryTarget.receiverUrl).hostname&&Buffer.isBuffer(payload)&&payload.equals(expected),'EXACT_PAYLOAD_AND_DESTINATION_REQUIRED');
  must(headers?.['x-jentra-event-id']===deliveryTarget.eventId&&/^v1=[a-f0-9]{64}$/.test(headers['x-jentra-signature']??'')&&/^\d{10}$/.test(headers['x-jentra-timestamp']??'')&&Math.abs(now()/1000-Number(headers['x-jentra-timestamp']))<60,'FRESH_SIGNED_IDENTITY_REQUIRED');
  signal?.throwIfAborted();
  await persistIntent({recordedAt:new Date(now()).toISOString(),deliveryId:job.deliveryId,invocationId:job.invocationId,eventId:job.event.eventId,attempt:job.attempt,leaseId:job.leaseId,url:destination.url,payloadSha256:hash,payloadBytes:payload.length,signedTimestamp:Number(headers['x-jentra-timestamp']),maximumRequests:1,automaticRetry:false,signaturePrinted:false});
  return post(destination,payload,headers,signal);
 };
}
