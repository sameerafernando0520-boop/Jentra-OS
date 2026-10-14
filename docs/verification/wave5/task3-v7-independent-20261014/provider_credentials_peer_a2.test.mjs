import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {serviceCredentialKind,serviceProviderHeaders} from '../../../../workers/wave5/provider_credentials_20261014_r5_v7.mjs';
import {createScopedWorkerRpc} from '../../../../workers/wave5/scoped_runtime_20261014_r5_v7.mjs';
import {createEdgeRuntime} from '../../../../workers/wave5/edge_runtime_20261014_r5_v7.mjs';
import {createEdgeReceiver} from '../../../../workers/wave5/edge_receiver_20261014_r5_v7.mjs';
import {createEdgeReceiver as predecessorReceiver} from '../../../../workers/wave5/edge_receiver_20261014_r5_v6.mjs';
import {edgeConfiguration as config} from '../../../../workers/wave5/edge_configuration.mjs';
import {forecastEvent,signDelivery} from '../../../../workers/wave5/integration_policy.mjs';

// All keys, identities, clocks and transport replies here are controlled fakes.
// The test never reads the process environment, opens a socket or resolves DNS.
const opaque='sb_secret_PEER_CONTROLLED_FAKE_0123456789abcdefghijklmnop';
const legacy='PEER_FAKE_LEGACY_HEADER.FAKE_PAYLOAD.FAKE_SIGNATURE';
const publishable='sb_publishable_PEER_CONTROLLED_FAKE_0123456789abcdef';
const caller='PEER_FAKE_USER_HEADER.FAKE_USER_PAYLOAD.FAKE_USER_SIGNATURE';
const sentinel='PEER_CONTROLLED_PRIVATE_ERROR_MUST_NOT_ESCAPE';
const uid=n=>`20000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const env=()=>({SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:opaque});
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
const request=(role,path,body={},headers={},options={})=>new Request(config.url+`/wave5-${role}/${path}`,{
 method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body),...options});
const tick=()=>request('runtime','schedule',{tickId:uid(1),kind:'health'},{'x-jentra-schedule-key':'e'.repeat(64)});
const noFetch=()=>assert.fail('controlled test forbids this backend dispatch');

test('peer: credential validation does not coerce objects or accept a reserved family through legacy fallback',()=>{
 let coercions=0;const object={toString(){coercions++;throw Error('MUST_NOT_COERCE');}};
 for(const key of [object,new String(opaque),Symbol('fake'),[opaque],true,32n,null,undefined,
  'sb_publishable_'+legacy,'sb_other_'+legacy,'sb_SECRET_'+legacy,'sb_secret_'+legacy]){
  assert.equal(serviceCredentialKind(key),null);
  assert.throws(()=>serviceProviderHeaders(key),error=>error.message==='WORKER_CONFIGURATION_INVALID');
 }assert.equal(coercions,0);
});

test('peer: whitespace, URL-like, dictionary, authorization and unicode key forms never produce service headers',()=>{
 for(const key of [opaque+'\r',opaque+'\n',opaque+'\r\n',opaque+'\t',opaque+'\u2028',opaque+'\u0000',
  legacy+'\n',' '+legacy,opaque+'%2e',opaque+'?',opaque+'#',opaque+'/',opaque+'=',
  'Bearer '+legacy,JSON.stringify({default:opaque}),'https://'+opaque,opaque+'\u00e9']){
  assert.equal(serviceCredentialKind(key),null);assert.throws(()=>serviceProviderHeaders(key),/WORKER_CONFIGURATION_INVALID/);
 }
 for(const key of [opaque,legacy])assert.equal(Object.isFrozen(serviceProviderHeaders(key)),true);
 assert.deepEqual(serviceProviderHeaders(opaque),{apikey:opaque});
 assert.deepEqual(serviceProviderHeaders(legacy),{apikey:legacy,authorization:'Bearer '+legacy});
});

test('peer: unrecognized origins, suffixes, query and fragment routes stop before reading even fake environment',async()=>{
 const locked={get(){assert.fail('route denial must precede key reads');}};
 const runtime=createEdgeRuntime({env:locked,fetchImpl:noFetch});
 const receiver=createEdgeReceiver({env:locked,fetchImpl:noFetch});
 const denied=[
  'https://foreign.invalid/wave5-runtime/schedule',
  'http://edge-runtime.supabase.com/wave5-runtime/schedule',
  config.url+'/wave5-runtime/schedule?x=1',config.url+'/wave5-runtime/schedule#x',
  config.url+'/wave5-runtime/schedule/extra',config.url+'/other/schedule',
 ];
 for(const url of denied){
  assert.equal((await runtime(new Request(url,{method:'POST',body:'{}'}))).status,404);
  assert.equal((await receiver(new Request(url.replace('runtime','receiver').replace('schedule','accept'),{method:'POST',body:'{}'}))).status,404);
 }
});

test('peer: exact existing project configuration remains required without dictionary or alias fallback',async()=>{
 for(const url of [config.url+'/',config.url.replace('https:','http:'),'https://foreign.supabase.co',undefined]){
  const reads=[];const fakeEnv={get(name){reads.push(name);if(name==='SUPABASE_URL')return url;assert.fail('URL denial precedes key access');}};
  const runtime=createEdgeRuntime({env:fakeEnv,fetchImpl:noFetch});
  assert.equal((await runtime(tick())).status,503);assert.deepEqual(reads,['SUPABASE_URL']);
 }
});

test('peer: a correctly shaped service key never authorizes an unsigned or malformed scheduler request',async()=>{
 const runtime=createEdgeRuntime({env:env(),fetchImpl:noFetch});
 for(const token of [undefined,'f'.repeat(63),'f'.repeat(65),'F'.repeat(64),opaque]){
  const headers=token===undefined?{}:{'x-jentra-schedule-key':token};
  const response=await runtime(request('runtime','schedule',{tickId:uid(1),kind:'health'},headers));
  assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'WORKER_ACCESS_DENIED'});
 }
 const bad=await runtime(request('runtime','schedule',{tickId:uid(1),kind:'health',tenantId:uid(2)},
  {'x-jentra-schedule-key':'e'.repeat(64)}));assert.equal(bad.status,400);
});

test('peer: server tick refusal stays a no-op with one hashed-secret RPC and no control or finish work',async()=>{
 const calls=[];const handler=createEdgeRuntime({env:env(),fetchImpl:async(url,options)=>{
  calls.push({url:String(url),options,p:JSON.parse(options.body)});return json({permitted:false});}});
 const response=await handler(tick());assert.equal(response.status,200);
 assert.deepEqual(await response.json(),{state:'already_running'});assert.equal(calls.length,1);
 assert.equal(calls[0].p.p_action,'begin_tick');
 assert.equal(calls[0].p.p_payload.secretHash,createHash('sha256').update('e'.repeat(64)).digest('hex'));
 assert.equal(calls[0].options.headers.apikey,opaque);assert.equal(Object.hasOwn(calls[0].options.headers,'authorization'),false);
 assert.equal(calls[0].options.body.includes(opaque),false);
});

test('peer: the original eight request slots throttle the ninth and are released after settlement',async()=>{
 const releases=[];let entered;const barrier=new Promise(resolve=>{entered=resolve;});
 const handler=createEdgeRuntime({env:env(),fetchImpl:()=>new Promise(resolve=>{
  releases.push(()=>resolve(json({permitted:false})));if(releases.length===config.maxConcurrentRequests)entered();})});
 assert.equal(config.maxConcurrentRequests,8);
 const pending=Array.from({length:8},()=>handler(tick()));await barrier;
 const excess=await handler(tick());assert.equal(excess.status,429);assert.deepEqual(await excess.json(),{code:'THROTTLED'});
 assert.equal(releases.length,8);for(const release of releases)release();
 assert.ok((await Promise.all(pending)).every(response=>response.status===200));
 const after=handler(tick());await new Promise(resolve=>setImmediate(resolve));
 assert.equal(releases.length,9);releases.at(-1)();assert.equal((await after).status,200);
});

test('peer: unfinished scheduler body observes cancellation, cancels the stream and performs zero RPCs',async()=>{
 let cancelled=0;const abort=new AbortController();
 const stream=new ReadableStream({start(controller){controller.enqueue(new TextEncoder().encode('{'));},cancel(){cancelled++;}});
 const req=new Request(config.url+'/wave5-runtime/schedule',{method:'POST',
  headers:{'content-type':'application/json','x-jentra-schedule-key':'e'.repeat(64)},body:stream,duplex:'half',signal:abort.signal});
 const handler=createEdgeRuntime({env:env(),fetchImpl:noFetch});
 const timer=setTimeout(()=>abort.abort(),20);
 try{const response=await handler(req);assert.equal(response.status,408);assert.deepEqual(await response.json(),{code:'REQUEST_TIMEOUT'});}
 finally{clearTimeout(timer);}assert.equal(cancelled,1);
});

test('peer: caller abort reaches the default service fetch signal and produces no replay or additional RPC',async()=>{
 const abort=new AbortController();let dispatched=0,seenSignal;
 const handler=createEdgeRuntime({env:env(),fetchImpl:(_url,options)=>{
  dispatched++;seenSignal=options.signal;return new Promise((_resolve,reject)=>{
   const rejectAbort=()=>reject(Error(sentinel));seenSignal.addEventListener('abort',rejectAbort,{once:true});
   if(seenSignal.aborted)rejectAbort();});}});
 const req=new Request(tick(),{signal:abort.signal});const pending=handler(req);
 await new Promise(resolve=>setImmediate(resolve));abort.abort();const response=await pending;
 assert.equal(response.status,503);assert.deepEqual(await response.json(),{code:'WORKER_PROVIDER_UNAVAILABLE'});
 assert.equal(seenSignal.aborted,true);assert.equal(dispatched,1);
});

test('peer: raw backend denial bodies and thrown details stay absent from scheduler response with no retry',async()=>{
 for(const failure of [401,403,500,'throw']){
  let calls=0;const handler=createEdgeRuntime({env:env(),fetchImpl:async()=>{
   calls++;if(failure==='throw')throw Error(sentinel+' '+opaque);
   return new Response(sentinel+' '+opaque,{status:failure});}});
  const response=await handler(tick());assert.equal(response.status,failure===401||failure===403?403:503);
  const body=await response.text();assert.equal(body.includes(sentinel),false);assert.equal(body.includes(opaque),false);assert.equal(calls,1);
 }
});

const timestamp=1791529200,key=Buffer.from('b'.repeat(64),'hex');
const event={eventId:uid(1),type:'analytics.forecast.frozen.v1',tenantId:uid(2),legalEntityId:uid(3),branchId:uid(4),
 forecastId:uid(5),definitionVersion:1,sourceHash:'f'.repeat(64)};
const bytes=forecastEvent(event,event);
function signedReceiver(route='accept',{body=bytes,signature=signDelivery({payload:body,eventId:event.eventId,timestamp,key,keyVersion:1})}={}){
 return new Request(config.url+'/wave5-receiver/'+route,{method:'POST',headers:{'content-type':'application/json',
  'x-jentra-event-id':event.eventId,'x-jentra-timestamp':String(timestamp),'x-jentra-signature':signature},body});
}

test('peer: alternate signed serializations or extra event fields remain invalid before key lookup',async()=>{
 let currentDispatches=0,oldDispatches=0;
 const handler=createEdgeReceiver({env:env(),fetchImpl:()=>{currentDispatches++;assert.fail('invalid event backend');},now:()=>timestamp});
 const predecessor=predecessorReceiver({env:{SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:legacy},
  fetchImpl:()=>{oldDispatches++;assert.fail('predecessor invalid event backend');},now:()=>timestamp});
 for(const [body,status,code] of [
  [Buffer.from(bytes.toString()+'\n'),400,'EVENT_CONTRACT_MISMATCH'],
  [Buffer.from(JSON.stringify({...event,extra:true})),503,'RECEIVER_UNAVAILABLE'],
  [Buffer.from(JSON.stringify(Object.fromEntries(Object.entries(event).reverse()))),400,'EVENT_CONTRACT_MISMATCH']]){
  const response=await handler(signedReceiver('accept',{body}));
  const previous=await predecessor(signedReceiver('accept',{body}));
  assert.equal(response.status,status);assert.equal(response.status,previous.status);
  assert.deepEqual(await response.json(),{code});assert.deepEqual(await previous.json(),{code});
 }assert.equal(currentDispatches,0);assert.equal(oldDispatches,0);
});

test('peer: every forged-HMAC fault route performs only the modern key lookup, with no receipt or fault effect',async()=>{
 const calls=[];const handler=createEdgeReceiver({env:env(),now:()=>timestamp,fetchImpl:async(url,options)=>{
  calls.push({url:String(url),options,p:JSON.parse(options.body)});return json({value:'b'.repeat(64)});},wait:noFetch});
 for(const route of ['accept','redirect','timeout','reject']){
  const response=await handler(signedReceiver(route,{signature:'v1='+'a'.repeat(64)}));
  assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'INTEGRATION_ACCESS_DENIED'});
  assert.equal(response.headers.has('location'),false);
 }
 assert.equal(calls.length,4);for(const call of calls){assert.equal(call.p.p_action,'key');
  assert.equal(call.p.p_runtime_id,config.runtimeId);assert.equal(call.options.headers.apikey,opaque);
  assert.equal(Object.hasOwn(call.options.headers,'authorization'),false);}
});

test('peer: unknown and path-shaped scoped RPC names cannot cause service dispatch',async()=>{
 const rpc=createScopedWorkerRpc({url:config.url,runtimeId:config.runtimeId,serviceKey:opaque,fetchImpl:noFetch});
 for(const name of ['wave5_edge_control','wave5_runtime_worker','wave5_delivery_worker/other','../other','wave5_delivery_worker?x',
  'wave5_delivery_worker\u0000','WAVE5_DELIVERY_WORKER','delete_user','',null,undefined])
  await assert.rejects(rpc(name,{}),error=>error.message==='WORKER_RPC_NOT_ALLOWLISTED');
});

const forecast={contractRevision:1,modelProvider:'unavailable',sourceId:uid(5),sourceHash:'a'.repeat(64),
 scope:{tenantId:uid(2),legalEntityId:uid(3),branchId:null},currencies:[{currency:'LKR',population:1,amount:'3.000000',weightedAmount:'1.500000'}],
 horizonStart:'2026-10-01',horizonEnd:'2026-11-01'};
const modelRequest={sourceId:uid(5),scope:forecast.scope,invocationId:uid(6),usageEventId:uid(7),maxTokens:'20',
 periodStart:'2026-10-01T00:00:00Z',periodEnd:'2026-11-01T00:00:00Z'};

test('peer: a denied caller-owned JWT read cannot fall back to the privileged service transport',async()=>{
 const calls=[];const handler=createEdgeRuntime({env:{...env(),SUPABASE_ANON_KEY:publishable,W5_OPENAI_API_KEY:'PEER_CONTROLLED_FAKE_MODEL_KEY_0123456789'},
  providerFactory:()=>({policyRevision:1,generate:noFetch}),fetchImpl:async(url,options)=>{
   calls.push({url:String(url),options});return new Response(sentinel,{status:401});}});
 const response=await handler(request('runtime','model/suggestion',modelRequest,{authorization:'Bearer '+caller}));
 assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'WORKER_ACCESS_DENIED'});
 assert.equal(calls.length,1);assert.equal(calls[0].url,config.url+'/rest/v1/rpc/get_ai_forecast_evidence');
 assert.equal(calls[0].options.headers.apikey,publishable);assert.equal(calls[0].options.headers.authorization,'Bearer '+caller);
 assert.equal(Object.values(calls[0].options.headers).includes(opaque),false);
});

test('peer: changed public authority on settled model reopen denies before usage settlement or generation',async()=>{
 const calls=[];let reads=0;const suggestion={commandCode:'analytics.freeze_pipeline.v1',sourceId:forecast.sourceId,sourceHash:forecast.sourceHash,
  horizonStart:forecast.horizonStart,horizonEnd:forecast.horizonEnd};
 const handler=createEdgeRuntime({env:{...env(),SUPABASE_ANON_KEY:publishable,W5_OPENAI_API_KEY:'PEER_CONTROLLED_FAKE_MODEL_KEY_0123456789'},
  providerFactory:()=>({policyRevision:1,generate:noFetch}),fetchImpl:async(url,options)=>{
   const call={url:String(url),options,p:JSON.parse(options.body)};calls.push(call);
   if(call.url.endsWith('/get_ai_forecast_evidence'))return json(++reads===1?forecast:{...forecast,sourceHash:'b'.repeat(64)});
   assert.equal(call.p.p_action,'model.begin');return json({state:'settled',tokens:'7',suggestion});}});
 const response=await handler(request('runtime','model/suggestion',modelRequest,{authorization:'Bearer '+caller}));
 assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'SOURCE_AUTHORITY_CHANGED'});
 assert.equal(calls.length,3);assert.equal(reads,2);
 const service=calls.filter(call=>call.url.endsWith('/wave5_runtime_worker'));
 assert.equal(service.length,1);assert.equal(service[0].options.headers.apikey,opaque);
 assert.equal(Object.hasOwn(service[0].options.headers,'authorization'),false);
 for(const call of calls.filter(call=>call.url.endsWith('/get_ai_forecast_evidence'))){
  assert.equal(call.options.headers.apikey,publishable);assert.equal(call.options.headers.authorization,'Bearer '+caller);
 }
});
