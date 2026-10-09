import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PersistentDeliveryControl,createWorkerRpc,runDeliveryBatch} from './persistent_control.mjs';

test('real RPC adapter binds service authorization and API schema without logging a key',async()=>{
 let observed;
 const rpc=createWorkerRpc({url:'https://xpdoufauvrbdmxgngetv.supabase.co',serviceKey:'test-only-key-'.repeat(4),
  fetchImpl:async(url,options)=>{observed={url,options};return {ok:true,text:async()=>'{"ready":true}'};}});
 assert.deepEqual(await rpc('wave5_delivery_worker',{p_action:'readiness',p_payload:{}}),{ready:true});
 assert.equal(observed.options.headers['content-profile'],'api');
 assert.equal(observed.options.redirect,'error');assert.equal(observed.url.pathname,'/rest/v1/rpc/wave5_delivery_worker');
});
test('control has no in-memory delivery or metering authority; original identity reaches persistent RPC',async()=>{
 const calls=[],control=new PersistentDeliveryControl(async(name,params)=>{calls.push({name,params});return null;});
 await control.claimCommittedDelivery();await control.authorizeDelivery({deliveryId:'d',leaseId:'l'});
 await control.recordDeliveryOutcome({deliveryId:'d',leaseId:'l'},{state:'unknown'});
 assert.deepEqual(calls.map(c=>c.params.p_action),['claim','authorize','outcome']);
 assert.deepEqual(calls[2].params.p_payload,{deliveryId:'d',leaseId:'l',state:'unknown',httpStatus:null});
});
test('scheduler reconciles acknowledged persisted attempts before claiming new work',async()=>{
 const calls=[];
 const control={reconcileAcknowledged:async()=>calls.push('reconcile'),
  readiness:async()=>({contractRevision:1,ready:true,providers:{'committed_webhook.v1':1}}),
  claimCommittedDelivery:async()=>{calls.push('claim');return null;}};
 assert.deepEqual(await runDeliveryBatch({control,now:()=>100,limit:5}),[]);
 assert.deepEqual(calls,['reconcile','claim']);
});
test('worker transport rejects unsafe URLs and bounds provider output/errors',async()=>{
 for(const url of ['http://x.supabase.co','https://secret@x.supabase.co','https://x.supabase.co/private','https://localhost']) {
  assert.throws(()=>createWorkerRpc({url,serviceKey:'x'.repeat(40)}),/CONFIGURATION/);
 }
 const rpc=createWorkerRpc({url:'https://x.supabase.co',serviceKey:'x'.repeat(40),
  fetchImpl:async()=>({ok:false,status:403,text:async()=>{throw Error('private');}})});
 await assert.rejects(rpc('wave5_delivery_worker',{}),/WORKER_ACCESS_DENIED/);
});
