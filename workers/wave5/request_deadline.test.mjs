import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createEdgeRuntime} from './edge_runtime.mjs';
import {createEdgeReceiver} from './edge_receiver.mjs';
import {createExternalCommandHandler} from './worker_endpoints.mjs';
import {readBoundedJson} from './bounded_json.mjs';
import {edgeConfiguration as config} from './edge_configuration.mjs';
import {forecastEvent,signDelivery,deliverForecast} from './integration_policy.mjs';
import {createHash} from 'node:crypto';
import {runSyntheticSubscriptionBatch} from './subscription_schedule.mjs';

const env={SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:'a'.repeat(40)+'.'+'b'.repeat(40)+'.'+'c'.repeat(40)};
const id='00000000-0000-4000-8000-000000000001';
function unfinishedRequest(url,headers={},signal){
 let controller,cancelled=false;
 const body=new ReadableStream({start(c){controller=c;c.enqueue(new TextEncoder().encode('{'));},cancel(){cancelled=true;}});
 return {request:new Request(url,{method:'POST',headers:{'content-type':'application/json',...headers},body,duplex:'half',signal}),
  close:()=>{if(!cancelled)controller.close();},get cancelled(){return cancelled;}};
}
async function boundedOutcome(run,source){
 let timer;
 const deadline=new Promise(resolve=>{timer=setTimeout(()=>resolve(null),200);});
 const outcome=await Promise.race([run,deadline]);clearTimeout(timer);
 if(outcome===null){source.close();await run;}
 assert.notEqual(outcome,null,'an unfinished request body outlived the configured deadline');
 return outcome;
}
test('scheduled request deadline cancels an unfinished body before trusted work and frees its slot',async()=>{
 let effects=0;
 const runtime=createEdgeRuntime({env,requestTimeoutMs:10,config:{...config,maxConcurrentRequests:1},
  edgeRpcFactory:()=>async()=>{effects++;return {permitted:true,tenantId:id};},
  controlFactory:()=>({readiness:async()=>{},collectHealth:async()=>{effects++;}})});
 const source=unfinishedRequest(config.workerUrl+'/schedule',{'x-jentra-schedule-key':'c'.repeat(64)});
 const response=await boundedOutcome(runtime(source.request),source);
 assert.equal(response.status,408);assert.equal((await response.json()).code,'REQUEST_TIMEOUT');
 assert.equal(source.cancelled,true);assert.equal(effects,0);
 const next=await runtime(new Request(config.workerUrl+'/schedule',{method:'POST',headers:{'content-type':'application/json'},body:'{}'}));
 assert.equal(next.status,403,'deadline must release the per-isolate request slot');
});
test('receiver deadline cancels an unfinished signed request without key lookup or receipt',async()=>{
 let effects=0;const timestamp=1791529200;
 const handler=createEdgeReceiver({env,requestTimeoutMs:10,now:()=>timestamp,rpcFactory:()=>async()=>{effects++;return {};}});
 const source=unfinishedRequest(config.receiverUrl,{'x-jentra-event-id':id,'x-jentra-timestamp':String(timestamp),'x-jentra-signature':'v1='+'a'.repeat(64)});
 const response=await boundedOutcome(handler(source.request),source);
 assert.equal(response.status,408);assert.equal(source.cancelled,true);assert.equal(effects,0);
});
test('receiver timeout-probe delay observes the deadline after its durable receipt',async()=>{
 const timestamp=1791529200,key=Buffer.from('a'.repeat(64),'hex'),calls=[];
 const event={eventId:id,type:'analytics.forecast.frozen.v1',tenantId:id,legalEntityId:id,branchId:id,forecastId:id,definitionVersion:1,sourceHash:'a'.repeat(64)};
 const payload=forecastEvent(event,event);
 const handler=createEdgeReceiver({env,requestTimeoutMs:10,now:()=>timestamp,rpcFactory:()=>async(_name,p)=>{
  calls.push(p.p_action);return p.p_action==='key'?{value:'a'.repeat(64)}:{acknowledged:true,sha256:createHash('sha256').update(payload).digest('hex')};
 }});
 const request=new Request(config.receiverUrl.replace(/accept$/,'timeout'),{method:'POST',headers:{'content-type':'application/json',
  'x-jentra-event-id':id,'x-jentra-timestamp':String(timestamp),'x-jentra-signature':signDelivery({payload,eventId:id,timestamp,key,keyVersion:1})},body:payload});
 const response=await boundedOutcome(handler(request),{close(){}});
 assert.equal(response.status,408);assert.deepEqual(calls,['key','receive']);
 assert.equal((await response.json()).code,'REQUEST_TIMEOUT');
});
test('external endpoint observes caller cancellation before any persistent control call',async()=>{
 const abort=new AbortController();let effects=0;
 const source=unfinishedRequest(config.workerUrl+'/external/forecast',{'authorization':'Bearer '+'x'.repeat(40)},abort.signal);
 const result=createExternalCommandHandler({control:{readiness:async()=>{effects++;}}})(source.request);
 abort.abort();const response=await boundedOutcome(result,source);
 assert.equal(response.status,408);assert.equal(source.cancelled,true);assert.equal(effects,0);
});
test('bounded response reader applies an explicit abort signal and preserves byte limits',async()=>{
 const abort=new AbortController(),source=unfinishedRequest('https://response.invalid');
 const result=readBoundedJson(source.request,1024,{signal:abort.signal});abort.abort();
 let timer;try{await assert.rejects(Promise.race([result,new Promise((_,reject)=>{timer=setTimeout(()=>{source.close();reject(Error('BODY_READ_NOT_ABORTED'));},200);})]),/WORKER_REQUEST_TIMEOUT/);}
 finally{clearTimeout(timer);}
 assert.equal(source.cancelled,true);
 assert.deepEqual(await readBoundedJson(new Response('{"ok":true}'),11),{ok:true});
 await assert.rejects(readBoundedJson(new Response('{"ok":true}'),10),/WORKER_OUTPUT_LIMIT/);
});
function deliveryOptions(signal){
 const event={eventId:id,type:'analytics.forecast.frozen.v1',tenantId:id,legalEntityId:id,branchId:id,forecastId:id,definitionVersion:1,sourceHash:'a'.repeat(64)};
 return {event,subscription:{id,scope:{tenantId:id,legalEntityId:id,branchId:id},enabled:true,keyVersion:1,url:config.receiverUrl,
  allowedHosts:[new URL(config.receiverUrl).hostname]},attempt:1,timestamp:1791529200,key:Buffer.from('a'.repeat(64),'hex'),signal,authorizeCommittedEvent:async()=>{}};
}
test('delivery cancellation during DNS discards a late answer and sends no request',async()=>{
 const abort=new AbortController();let dnsReady,finishDns,sends=0;
 const ready=new Promise(resolve=>{dnsReady=resolve;});
 const result=deliverForecast({...deliveryOptions(abort.signal),resolve:()=>{dnsReady();return new Promise(resolve=>{finishDns=resolve;});},post:async()=>{sends++;return 200;}});
 await ready;abort.abort();await assert.rejects(result,/WORKER_REQUEST_TIMEOUT/);
 finishDns(['8.8.8.8']);await Promise.resolve();assert.equal(sends,0);
});
test('delivery cancellation during transport remains unknown and passes the abort signal to transport',async()=>{
 const abort=new AbortController();let posted;
 const result=await deliverForecast({...deliveryOptions(abort.signal),resolve:async()=>['8.8.8.8'],post:(_target,_bytes,_headers,signal)=>{
  posted=signal;queueMicrotask(()=>abort.abort());return new Promise(()=>{});
 }});
 assert.equal(posted,abort.signal);assert.equal(result.state,'unknown');assert.equal(result.httpStatus,null);
});
test('subscription cancellation during readiness prevents activation after the awaited provider',async()=>{
 const abort=new AbortController();let readinessStarted,completeReadiness,activations=0;
 const started=new Promise(resolve=>{readinessStarted=resolve;});
 const control={dueSyntheticSubscriptions:async()=>({contractRevision:1,items:[{tenantId:id,revisionId:id}],nextCursor:null}),
  readiness:()=>{readinessStarted();return new Promise(resolve=>{completeReadiness=resolve;});},applySyntheticSubscription:async()=>{activations++;}};
 const result=runSyntheticSubscriptionBatch({control,signal:abort.signal});
 await started;abort.abort();completeReadiness({contractRevision:1,ready:true,providers:{'synthetic_subscription.v1':1}});
 assert.deepEqual((await result).results,[{revisionId:id,state:'unconfirmed'}]);assert.equal(activations,0);
});
