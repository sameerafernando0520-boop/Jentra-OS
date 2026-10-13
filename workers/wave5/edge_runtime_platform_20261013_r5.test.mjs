import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createEdgeRuntime,resolvePublicAddresses} from './edge_runtime_20261013_r5.mjs';
import {createEdgeReceiver} from './edge_receiver_20261013_r5.mjs';
import {edgeConfiguration as config} from './edge_configuration.mjs';
import {forecastEvent,signDelivery} from './integration_policy.mjs';

const id='00000000-0000-4000-8000-000000000001';
const env={SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:'a'.repeat(40)+'.'+'b'.repeat(40)+'.'+'c'.repeat(40),SUPABASE_ANON_KEY:'p'.repeat(40)};
const request=(route,body={},headers={})=>new Request(config.workerUrl.replace('/functions/v1/','/')+route,{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body)});
const schedule=(body={tickId:id,kind:'health'},key='c'.repeat(64))=>request('/schedule',body,{'x-jentra-schedule-key':key});
function harness({permit={permitted:true,tenantId:id},fail,control={}}={}){
 const calls=[];
 const runtime=createEdgeRuntime({env,edgeRpcFactory:()=>async(name,p)=>{calls.push({action:p.p_action,payload:p.p_payload});if(fail)throw Error(fail);return p.p_action==='begin_tick'?permit:{recorded:true};},
  controlFactory:()=>({readiness:async()=>({contractRevision:1,ready:true,providers:{'synthetic_subscription.v1':1,'committed_webhook.v1':1}}),collectHealth:async()=>calls.push({health:true}),dueSyntheticSubscriptions:async()=>({contractRevision:1,items:[],nextCursor:null}),reconcileAcknowledged:async()=>{},claimCommittedDelivery:async()=>null,...control})});
 return {runtime,calls};
}
test('unsigned schedule is rejected before any trusted RPC/effect',async()=>{const h=harness();assert.equal((await h.runtime(request('/schedule'))).status,403);assert.equal(h.calls.length,0);});
test('schedule secret is hashed and server denial precedes health',async()=>{const h=harness({fail:'WORKER_ACCESS_DENIED'});assert.equal((await h.runtime(schedule())).status,403);assert.equal(h.calls.length,1);assert.equal(h.calls[0].payload.secretHash,createHash('sha256').update('c'.repeat(64)).digest('hex'));assert(!JSON.stringify(h.calls).includes('c'.repeat(64)));});
test('expired/revoked runtime denies before scheduled work',async()=>{const h=harness({fail:'RUNTIME_SCOPE_DENIED'});assert.equal((await h.runtime(schedule())).status,403);assert.equal(h.calls.length,1);});
test('duplicate/overlapping tick does not collect or finish again',async()=>{const h=harness({permit:{permitted:false}});assert.equal((await (await h.runtime(schedule())).json()).state,'already_running');assert.equal(h.calls.length,1);});
test('health is collected for server-selected scope and outcome persisted',async()=>{const h=harness();assert.equal((await (await h.runtime(schedule())).json()).state,'completed');assert.deepEqual(h.calls.map(c=>c.action??'health'),['begin_tick','health','finish_tick']);assert.equal(h.calls.at(-1).payload.success,true);});
test('subscription tick uses a bounded persistent page',async()=>{const h=harness();const result=await h.runtime(schedule({tickId:id,kind:'subscription'}));assert.equal((await result.json()).count,0);assert.equal(h.calls.at(-1).action,'finish_tick');});
test('empty delivery tick reconciles and performs no network send',async()=>{const h=harness();assert.equal((await (await h.runtime(schedule({tickId:id,kind:'delivery'}))).json()).count,0);});
test('failed provider readiness persists failure instead of completed',async()=>{const h=harness({control:{readiness:async()=>{throw Error('PRIVATE_VALUE_MUST_NOT_LEAK');}}});const res=await h.runtime(schedule());assert.equal(res.status,503);assert.equal(h.calls.at(-1).payload.success,false);assert(!await res.text().then(t=>t.includes('PRIVATE_VALUE')));});
test('invalid routes/origins never access trusted backend',async()=>{const h=harness();assert.equal((await h.runtime(new Request('https://other.invalid/schedule',{method:'POST'}))).status,404);assert.equal((await h.runtime(request('/schedule?x=1'))).status,404);assert.equal(h.calls.length,0);});
test('malformed schedule schema is rejected before authorization',async()=>{const h=harness();assert.equal((await h.runtime(schedule({tickId:id,kind:'health',tenantId:id}))).status,400);assert.equal(h.calls.length,0);});
test('missing model key yields explicit provider absence without invocation',async()=>{const h=harness();assert.equal((await (await h.runtime(request('/model/suggestion'))).json()).code,'MODEL_PROVIDER_UNAVAILABLE');assert.equal(h.calls.length,0);});
test('platform DNS records are normalized to the pinned transport address contract',async()=>{
 const addresses=await resolvePublicAddresses('receiver.test',async(host,options)=>{
  assert.equal(host,'receiver.test');assert.deepEqual(options,{all:true});
  return [{address:'8.8.8.8',family:4},{address:'2606:4700:4700::1111',family:6}];
 });assert.deepEqual(addresses,['8.8.8.8','2606:4700:4700::1111']);
});
test('nonempty scheduled delivery signs exact bytes, persists outcome and settles within batch cap',async()=>{
 const seen=[],privateBuffers=[];let claims=0;
 const control={readiness:async()=>({contractRevision:1,ready:true,providers:{'committed_webhook.v1':1}}),
  reconcileAcknowledged:async()=>seen.push('reconcile'),
  claimCommittedDelivery:async()=>{claims++;return {invocationId:id,usageEventId:id,periodStart:'2026-10-09T00:00:00Z',periodEnd:'2026-10-10T00:00:00Z',attempt:1,
   event,subscription:{id,scope:{tenantId:id,legalEntityId:id,branchId:id},enabled:true,keyVersion:1,url:config.receiverUrl,allowedHosts:[new URL(config.receiverUrl).hostname]}};},
  authorizeDelivery:async()=>seen.push('authorize'),reserveUsage:async()=>seen.push('reserve'),
  deliverySecret:async(_job,vault)=>{const b=await vault.read('w5/runtime/20261008/delivery/v1');privateBuffers.push(b);return b;},
  recordDeliveryOutcome:async(_job,outcome)=>{assert.equal(outcome.state,'acknowledged');seen.push('outcome');},settleUsage:async()=>seen.push('settle')};
 const runtime=createEdgeRuntime({env,controlFactory:()=>control,resolve:async()=>['8.8.8.8'],
  edgeRpcFactory:()=>async(_name,p)=>p.p_action==='begin_tick'?{permitted:true,tenantId:id}:p.p_action==='key'?{value:'a'.repeat(64)}:{recorded:true},
  post:async(destination,body,headers)=>{assert.equal(destination.address,'8.8.8.8');assert(body.equals(payload));
   assert.equal(headers['x-jentra-signature'],signDelivery({payload:body,eventId:id,timestamp:Number(headers['x-jentra-timestamp']),key,keyVersion:1}));seen.push('post');return 200;}});
 const result=await runtime(schedule({tickId:id,kind:'delivery'}));assert.equal(result.status,200);assert.equal((await result.json()).count,3);
 assert.equal(claims,3);assert.equal(seen.filter(s=>s==='post').length,3);assert(seen.indexOf('reserve')<seen.indexOf('post'));
 assert(seen.indexOf('post')<seen.indexOf('outcome'));assert(seen.indexOf('outcome')<seen.indexOf('settle'));assert(privateBuffers.every(b=>b.every(v=>v===0)));
});

const event={eventId:id,type:'analytics.forecast.frozen.v1',tenantId:id,legalEntityId:id,branchId:id,forecastId:id,definitionVersion:1,sourceHash:'a'.repeat(64)};
const payload=forecastEvent(event,event),key=Buffer.from('a'.repeat(64),'hex'),timestamp=1791529200;
function receiverRequest(mode='accept',changes={}){
 const bytes=changes.payload??payload;
 return new Request(config.receiverUrl.replace('/functions/v1/','/').replace(/accept$/,mode),{method:'POST',headers:{'content-type':'application/json','x-jentra-event-id':id,'x-jentra-timestamp':String(timestamp),
  'x-jentra-signature':signDelivery({payload:bytes,eventId:id,timestamp,key,keyVersion:1}),...changes.headers},body:bytes});
}
function receiverHarness({duplicate=false,fail,wait}={}){
 const calls=[];const handler=createEdgeReceiver({env,now:()=>timestamp,wait,rpcFactory:()=>async(name,p)=>{calls.push(p.p_action);if(fail&&p.p_action!=='key')throw Error(fail);
  return p.p_action==='key'?{value:'a'.repeat(64)}:p.p_action==='receive_probe'?{permitted:true}:{acknowledged:true,duplicate,sha256:createHash('sha256').update(payload).digest('hex')};}});
 return {handler,calls};
}
test('receiver verifies bytes before durable ACK',async()=>{const h=receiverHarness();const res=await h.handler(receiverRequest());assert.equal(res.status,200);assert.equal((await res.json()).acknowledged,true);assert.deepEqual(h.calls,['key','receive']);});
test('receiver returns persisted deduplication result',async()=>{const h=receiverHarness({duplicate:true});assert.equal((await (await h.handler(receiverRequest())).json()).duplicate,true);});
test('forged signature cannot create receipt',async()=>{const h=receiverHarness();assert.equal((await h.handler(receiverRequest('accept',{headers:{'x-jentra-signature':'v1='+'b'.repeat(64)}}))).status,403);assert.deepEqual(h.calls,['key']);});
test('stale timestamp is rejected before private key lookup',async()=>{const h=receiverHarness();assert.equal((await h.handler(receiverRequest('accept',{headers:{'x-jentra-timestamp':String(timestamp-301)}}))).status,403);assert.equal(h.calls.length,0);});
test('noncanonical signed event is rejected before private key lookup',async()=>{const h=receiverHarness();assert.equal((await h.handler(receiverRequest('accept',{payload:Buffer.from(' '+payload)}))).status,400);assert.equal(h.calls.length,0);});
test('oversized receiver body is rejected before key lookup',async()=>{const h=receiverHarness(),small=receiverRequest();const large=new Request(small.url,{method:'POST',headers:small.headers,body:Buffer.alloc(8193)});assert.equal((await h.handler(large)).status,400);assert.equal(h.calls.length,0);});
test('server revocation after signature prevents ACK',async()=>{const h=receiverHarness({fail:'RUNTIME_SCOPE_DENIED'});assert.equal((await h.handler(receiverRequest())).status,503);assert.deepEqual(h.calls,['key','receive']);});
test('redirect probe authenticates source but creates no ACK',async()=>{const h=receiverHarness();const res=await h.handler(receiverRequest('redirect'));assert.equal(res.status,307);assert.equal(res.headers.get('location'),config.receiverUrl);assert.deepEqual(h.calls,['key','receive_probe']);});
test('timeout probe persists ACK before delayed response',async()=>{let h;h=receiverHarness({wait:async ms=>{assert.equal(ms,12000);assert.deepEqual(h.calls,['key','receive']);}});assert.equal((await h.handler(receiverRequest('timeout'))).status,200);});
test('reject probe authenticates before bounded failure',async()=>{const h=receiverHarness();assert.equal((await h.handler(receiverRequest('reject'))).status,503);assert.deepEqual(h.calls,['key','receive_probe']);});
