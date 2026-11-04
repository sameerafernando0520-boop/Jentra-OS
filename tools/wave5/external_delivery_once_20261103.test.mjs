import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createExactSinglePost,validateExactLeasedDelivery,deliveryTarget as t} from './external_delivery_once_20261103.mjs';
import {forecastEvent} from '../../workers/wave5/integration_policy.mjs';
const original=JSON.parse(await readFile(new URL('../../docs/verification/ai-integrations-test-20261103/external-delivery-rollback-result.json',import.meta.url),'utf8'));
const now=Date.parse(original.observedAt),clone=()=>structuredClone(original);
test('accepts only the original committed event and approved one minute lease',()=>assert.equal(validateExactLeasedDelivery(clone(),now).deliveryId,t.deliveryId));
for(const [name,change,code] of [
 ['replacement invocation',s=>s.job.invocationId='bf887435-88db-4a1f-9df9-2e9ec326f9b4','ORIGINAL_DELIVERY_IDENTITIES_REQUIRED'],
 ['changed source',s=>s.job.event.sourceHash='a'.repeat(64),'ORIGINAL_COMMITTED_EVENT_REQUIRED'],
 ['different receiver',s=>s.job.subscription.url=t.receiverUrl+'/redirect','EXACT_RECEIVER_REQUIRED'],
 ['expired lease',s=>s.leaseUntil=new Date(now-1).toISOString(),'FRESH_LEASE_REQUIRED'],
 ['previous reservation',s=>s.reservationAbsent=false,'EXACT_UNSENT_LEASE_REQUIRED'],
 ['enabled scheduler',s=>s.scheduledJobsPaused=false,'EXACT_UNSENT_LEASE_REQUIRED'],
 ['different billing duration',s=>s.job.periodEnd=new Date(Date.parse(s.job.periodStart)+3600000).toISOString(),'APPROVED_BILLING_PERIOD_REQUIRED'],
])test('blocks '+name,()=>{const s=clone();change(s);assert.throws(()=>validateExactLeasedDelivery(s,now),new RegExp(code));});
const request=()=>({destination:{url:t.receiverUrl,hostname:new URL(t.receiverUrl).hostname},payload:forecastEvent(original.job.event,original.job.subscription.scope),headers:{'x-jentra-event-id':t.eventId,'x-jentra-timestamp':String(Math.floor(now/1000)),'x-jentra-signature':'v1='+'a'.repeat(64)}});
for(const status of [200,503])test('one transport call for HTTP '+status+' even after another invocation',async()=>{
 let calls=0,intents=0;const send=createExactSinglePost({job:clone().job,now:()=>now,post:async()=>{calls++;return status;},persistIntent:async()=>{intents++;}}),r=request();
 assert.equal(await send(r.destination,r.payload,r.headers),status);
 await assert.rejects(send(r.destination,r.payload,r.headers),/ONE_SIGNED_REQUEST_LIMIT/);
 assert.equal(calls,1);assert.equal(intents,1);
});
test('uncertain network result cannot be retried',async()=>{
 let calls=0;const send=createExactSinglePost({job:clone().job,now:()=>now,post:async()=>{calls++;throw Error('UNKNOWN');},persistIntent:async()=>{}}),r=request();
 await assert.rejects(send(r.destination,r.payload,r.headers),/UNKNOWN/);await assert.rejects(send(r.destination,r.payload,r.headers),/ONE_SIGNED_REQUEST_LIMIT/);assert.equal(calls,1);
});
test('intent failure prevents transport and consumes the attempt',async()=>{
 let calls=0;const send=createExactSinglePost({job:clone().job,now:()=>now,post:async()=>{calls++;},persistIntent:async()=>{throw Error('INTENT_NOT_DURABLE');}}),r=request();
 await assert.rejects(send(r.destination,r.payload,r.headers),/INTENT_NOT_DURABLE/);await assert.rejects(send(r.destination,r.payload,r.headers),/ONE_SIGNED_REQUEST_LIMIT/);assert.equal(calls,0);
});
test('mismatched payload cannot reach transport',async()=>{
 let calls=0;const send=createExactSinglePost({job:clone().job,now:()=>now,post:async()=>{calls++;},persistIntent:async()=>{}}),r=request();
 await assert.rejects(send(r.destination,Buffer.from('{}'),r.headers),/EXACT_PAYLOAD_AND_DESTINATION_REQUIRED/);assert.equal(calls,0);
});
