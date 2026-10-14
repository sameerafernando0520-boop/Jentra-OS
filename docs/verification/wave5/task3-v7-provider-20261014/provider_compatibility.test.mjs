import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {serviceCredentialKind,serviceProviderHeaders} from '../../../../workers/wave5/provider_credentials_20261014_r5_v7.mjs';
import {createWorkerRpc as v7Rpc} from '../../../../workers/wave5/persistent_control_20261014_r5_v7.mjs';
import {createWorkerRpc as legacyRpc} from '../../../../workers/wave5/persistent_control.mjs';
import {createScopedWorkerRpc} from '../../../../workers/wave5/scoped_runtime_20261014_r5_v7.mjs';
import {createEdgeRuntime} from '../../../../workers/wave5/edge_runtime_20261014_r5_v7.mjs';
import {createEdgeReceiver} from '../../../../workers/wave5/edge_receiver_20261014_r5_v7.mjs';
import {edgeConfiguration as config} from '../../../../workers/wave5/edge_configuration.mjs';
import {forecastEvent,signDelivery} from '../../../../workers/wave5/integration_policy.mjs';

// Every credential, actor, server response and provider below is a controlled
// fake fixture. No process environment, credentials, DNS or live backend is read.
const opaque='sb_secret_DELIBERATELY_FAKE_CONTROLLED_FIXTURE_0123456789';
const legacy='DELIBERATELY_FAKE_CONTROLLED_HEADER.PAYLOAD.SIGNATURE';
const publishable='sb_publishable_DELIBERATELY_FAKE_CONTROLLED_FIXTURE_0123456789';
const userJwt='DELIBERATELY_FAKE_REAL_USER_PATH.JWT_PAYLOAD.JWT_SIGNATURE';
const uid=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const env=serviceKey=>({SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:serviceKey});
const json=value=>new Response(JSON.stringify(value),{status:200,headers:{'content-type':'application/json'}});
const request=(worker,route,body={},headers={})=>new Request(config.url+'/wave5-'+worker+'/'+route,
 {method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body)});
const schedule=(kind='health')=>request('runtime','schedule',{tickId:uid(1),kind},{'x-jentra-schedule-key':'c'.repeat(64)});
function fetchHarness(answer){const calls=[];return {calls,fetchImpl:async(target,options)=>{
 const call={target:String(target),options,body:JSON.parse(options.body)};calls.push(call);return answer(call);}};}
function checkServiceCalls(calls,serviceKey){
 for(const call of calls){assert.ok(call.target.startsWith(config.url+'/rest/v1/rpc/'));
  assert.equal(call.options.headers.apikey,serviceKey);assert.equal(call.options.method,'POST');
  assert.equal(call.options.redirect,'error');assert.ok(call.options.signal instanceof AbortSignal);
  assert.equal(call.options.headers['content-profile'],'api');assert.equal(call.options.headers['accept-profile'],'api');
  if(serviceKey===legacy)assert.equal(call.options.headers.authorization,'Bearer '+legacy);
  else assert.equal(Object.hasOwn(call.options.headers,'authorization'),false);
 }
}

test('only >=32-character legacy JWT shapes or opaque secret shapes produce immutable service headers',()=>{
 assert.equal(serviceCredentialKind(legacy),'legacy_jwt');assert.equal(serviceCredentialKind(opaque),'opaque_secret');
 assert.deepEqual(serviceProviderHeaders(legacy),{apikey:legacy,authorization:'Bearer '+legacy});
 assert.deepEqual(serviceProviderHeaders(opaque),{apikey:opaque});assert.equal(Object.isFrozen(serviceProviderHeaders(opaque)),true);
 assert.equal(serviceCredentialKind('sb_secret_'+'a'.repeat(22)),'opaque_secret');
 assert.equal(serviceCredentialKind('sb_secret_'+'a'.repeat(21)),null);
});

test('publishable, malformed, prefixed, whitespace, short and non-string service inputs fail before RPC dispatch',()=>{
 let dispatched=0;const noFetch=()=>{dispatched++;throw Error('NETWORK_NOT_ALLOWED');};
 for(const key of [publishable,'a'.repeat(40),'a.b.c','sb_secret_','sb_secret_'+'a'.repeat(21),
  'Bearer '+legacy,opaque+'\n',opaque+' ',opaque+'=',opaque+'.',opaque+'/',opaque+'?',legacy+'\r\n',
  '',null,undefined,32,{},new Proxy({}, {get(){throw Error('NO_KEY_COERCION');}})]){
  assert.equal(serviceCredentialKind(key),null);assert.throws(()=>serviceProviderHeaders(key),/WORKER_CONFIGURATION_INVALID/);
  assert.throws(()=>v7Rpc({url:config.url,serviceKey:key,fetchImpl:noFetch}),/WORKER_CONFIGURATION_INVALID/);
 }assert.equal(dispatched,0);
});

test('reserved API-key prefixes cannot become legacy service JWTs by appending dot-separated segments',()=>{
 for(const key of [publishable+'.payload.signature',opaque+'.payload.signature',
  'sb_other_DELIBERATELY_FAKE_CONTROLLED_KEY.payload.signature']){
  assert.equal(serviceCredentialKind(key),null);assert.throws(()=>serviceProviderHeaders(key),/WORKER_CONFIGURATION_INVALID/);
 }
 assert.equal(serviceCredentialKind(legacy),'legacy_jwt');assert.equal(serviceCredentialKind(opaque),'opaque_secret');
});

test('modern RPC sends only apikey with unchanged URL/profile/redirect/body and 15-second request signal',async()=>{
 const h=fetchHarness(()=>json({controlled:true}));const rpc=v7Rpc({url:config.url,serviceKey:opaque,fetchImpl:h.fetchImpl});
 assert.deepEqual(await rpc('wave5_edge_control',{p_runtime_id:config.runtimeId,p_action:'begin_tick',p_payload:{tickId:uid(1)}}),{controlled:true});
 assert.equal(h.calls.length,1);checkServiceCalls(h.calls,opaque);
 assert.equal(h.calls[0].target,config.url+'/rest/v1/rpc/wave5_edge_control');
 assert.equal(h.calls[0].options.headers['content-type'],'application/json');
});

test('legacy RPC headers, method, body and redirect behavior remain byte-for-byte predecessor equivalents',async()=>{
 const before=fetchHarness(()=>json({same:true})),after=fetchHarness(()=>json({same:true}));
 const params={p_runtime_id:config.runtimeId,p_action:'fixed',p_payload:{controlled:true}};
 await legacyRpc({url:config.url,serviceKey:legacy,fetchImpl:before.fetchImpl})('wave5_edge_control',params);
 await v7Rpc({url:config.url,serviceKey:legacy,fetchImpl:after.fetchImpl})('wave5_edge_control',params);
 assert.equal(after.calls[0].target,before.calls[0].target);
 const excludeSignal=options=>{const {signal,...rest}=options;assert.ok(signal instanceof AbortSignal);return rest;};
 assert.deepEqual(excludeSignal(after.calls[0].options),excludeSignal(before.calls[0].options));
});

test('existing HTTPS and URL-boundary guards reject unsafe targets before any header-bearing request',()=>{
 for(const url of ['http://xpdoufauvrbdmxgngetv.supabase.co','https://other.invalid','https://user:password@xpdoufauvrbdmxgngetv.supabase.co',
  config.url+'/unexpected','not-a-url'])assert.throws(()=>v7Rpc({url,serviceKey:opaque,fetchImpl:()=>assert.fail('no request')}));
});

test('server 401/403 remain access denials and private failure bodies are never promoted to error messages',async()=>{
 for(const status of [401,403,503]){
  const rpc=v7Rpc({url:config.url,serviceKey:opaque,fetchImpl:async()=>new Response('CONTROLLED_FAKE_SECRET_FAILURE',{status})});
  await assert.rejects(rpc('wave5_edge_control',{}),error=>error.message===(status===503?'WORKER_PROVIDER_UNAVAILABLE':'WORKER_ACCESS_DENIED'));
 }
});

test('every scoped persistent-control family uses the V7 modern transport and exact original runtime envelope',async()=>{
 const h=fetchHarness(()=>json({fixed:true}));const rpc=createScopedWorkerRpc({runtimeId:config.runtimeId,url:config.url,serviceKey:opaque,fetchImpl:h.fetchImpl});
 const cases=[['wave5_delivery_worker',{p_action:'readiness',p_payload:{}},'delivery.readiness',{}],
  ['wave5_model_worker',{p_action:'begin',p_payload:{invocationId:uid(1)}},'model.begin',{invocationId:uid(1)}],
  ['wave5_external_worker',{p_action:'credential',p_payload:{tokenHash:'a'.repeat(64)}},'external.credential',{tokenHash:'a'.repeat(64)}],
  ['wave5_worker_entitlement',{p_scope:{tenantId:uid(2)}},'entitlement',{scope:{tenantId:uid(2)}}],
  ['wave5_reserve_usage',{p_tenant_id:uid(2),p_invocation_id:uid(3),p_metric_code:'ai.tokens',p_period_start:'start',p_period_end:'end',p_quantity:'20'},
   'usage.reserve',{tenantId:uid(2),invocationId:uid(3),metric:'ai.tokens',periodStart:'start',periodEnd:'end',quantity:'20'}],
  ['wave5_settle_usage',{p_tenant_id:uid(2),p_invocation_id:uid(3),p_event_id:uid(4),p_quantity:'7'},
   'usage.settle',{tenantId:uid(2),invocationId:uid(3),eventId:uid(4),quantity:'7'}],
  ['wave5_subscription_due',{p_after:null},'subscription.due',{after:null}],
  ['apply_synthetic_subscription',{p_tenant_id:uid(2),p_revision_id:uid(3)},'subscription.apply',{tenantId:uid(2),revisionId:uid(3)}],
  ['wave5_health_collect',{p_collection_id:uid(1),p_tenant_id:uid(2)},'health.collect',{collectionId:uid(1),tenantId:uid(2)}]];
 for(const [name,params,action,payload]of cases){await rpc(name,params);assert.deepEqual(h.calls.at(-1).body,
  {p_runtime_id:config.runtimeId,p_action:action,p_payload:payload});}
 assert.equal(h.calls.length,9);checkServiceCalls(h.calls,opaque);
 assert.ok(h.calls.every(call=>call.target===config.url+'/rest/v1/rpc/wave5_runtime_worker'));
 for(const denied of ['wave5_edge_control','post_manual_journal','delete_user','unreviewed'])
  await assert.rejects(rpc(denied,{}),/WORKER_RPC_NOT_ALLOWLISTED/);
 assert.equal(h.calls.length,9);
});

test('default runtime accepts either provider format but unsigned schedule still denies before any backend work',async()=>{
 for(const key of [opaque,legacy]){
  let calls=0;const handler=createEdgeRuntime({env:env(key),fetchImpl:()=>{calls++;assert.fail('unsigned backend');}});
  const response=await handler(request('runtime','schedule'));
  assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'WORKER_ACCESS_DENIED'});assert.equal(calls,0);
 }
});

function healthAnswer(call){
 const action=call.body.p_action;
 if(action==='begin_tick')return json({permitted:true,tenantId:uid(2)});
 if(action==='delivery.readiness'||action==='model.readiness')return json({contractRevision:1,ready:true,
  providers:{'committed_webhook.v1':1,'synthetic_subscription.v1':1}});
 return json({recorded:true});
}
test('default real runtime ports use corrected modern headers on raw edge and scoped readiness/health calls',async()=>{
 for(const key of [opaque,legacy]){
  const h=fetchHarness(healthAnswer),handler=createEdgeRuntime({env:env(key),fetchImpl:h.fetchImpl});
  const response=await handler(schedule());assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{state:'completed',count:1,states:['collected']});
  assert.deepEqual(h.calls.map(call=>call.body.p_action),['begin_tick','delivery.readiness','model.readiness','health.collect','finish_tick']);
  checkServiceCalls(h.calls,key);assert.ok(h.calls.every(call=>call.body.p_runtime_id===config.runtimeId));
  assert.equal(h.calls[0].body.p_payload.secretHash,createHash('sha256').update('c'.repeat(64)).digest('hex'));
  assert.equal(h.calls[3].body.p_payload.tenantId,uid(2));assert.equal(h.calls[4].body.p_payload.success,true);
 }
});

test('default runtime preserves malformed-body and backend-denial gates without retries',async()=>{
 let calls=0;const forbidden=createEdgeRuntime({env:env(opaque),fetchImpl:()=>{calls++;assert.fail('invalid backend');}});
 const malformed=request('runtime','schedule',{tickId:uid(1),kind:'health',tenantId:uid(2)},{'x-jentra-schedule-key':'c'.repeat(64)});
 assert.equal((await forbidden(malformed)).status,400);assert.equal(calls,0);
 const denied=createEdgeRuntime({env:env(opaque),fetchImpl:async()=>{calls++;return new Response('CONTROLLED_PRIVATE_DETAIL',{status:403});}});
 const response=await denied(schedule());assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'WORKER_ACCESS_DENIED'});
 assert.equal(calls,1);
});

test('default delivery control retains the exact lazy worker-runtime module and performs no external send for an empty queue',async()=>{
 const h=fetchHarness(call=>call.body.p_action==='delivery.claim'?json(null):healthAnswer(call));let sends=0;
 const handler=createEdgeRuntime({env:env(opaque),fetchImpl:h.fetchImpl,post:()=>{sends++;assert.fail('no delivery');},resolve:()=>assert.fail('no DNS')});
 const response=await handler(schedule('delivery'));assert.equal(response.status,200);
 assert.deepEqual(await response.json(),{state:'completed',count:0,states:[]});assert.equal(sends,0);
 assert.ok(h.calls.some(call=>call.body.p_action==='delivery.settle_acknowledged'));
 assert.ok(h.calls.some(call=>call.body.p_action==='delivery.claim'));checkServiceCalls(h.calls,opaque);
});

test('provider compatibility never bypasses the existing durable readiness provider contract',async()=>{
 const h=fetchHarness(call=>call.body.p_action==='delivery.readiness'
  ?json({contractRevision:1,ready:true,providers:{}}):healthAnswer(call));
 const handler=createEdgeRuntime({env:env(opaque),fetchImpl:h.fetchImpl,post:()=>assert.fail('not ready delivery')});
 const response=await handler(schedule('delivery'));assert.equal(response.status,503);
 assert.deepEqual(await response.json(),{code:'WORKER_PROVIDER_UNAVAILABLE'});
 assert.equal(h.calls.some(call=>call.body.p_action==='delivery.claim'),false);
 assert.equal(h.calls.at(-1).body.p_action,'finish_tick');assert.equal(h.calls.at(-1).body.p_payload.success,false);
 checkServiceCalls(h.calls,opaque);
});

const timestamp=1791529200,keyBytes=Buffer.from('a'.repeat(64),'hex');
const event={eventId:uid(1),type:'analytics.forecast.frozen.v1',tenantId:uid(2),legalEntityId:uid(3),branchId:uid(4),forecastId:uid(5),definitionVersion:1,sourceHash:'a'.repeat(64)};
const payload=forecastEvent(event,event);
function receiverRequest(route='accept',headers={}){
 return new Request(config.url+'/wave5-receiver/'+route,{method:'POST',headers:{'content-type':'application/json','x-jentra-event-id':event.eventId,
  'x-jentra-timestamp':String(timestamp),'x-jentra-signature':signDelivery({payload,eventId:event.eventId,timestamp,key:keyBytes,keyVersion:1}),...headers},body:payload});
}
const receiverAnswer=call=>call.body.p_action==='key'?json({value:'a'.repeat(64)}):json({acknowledged:true,sha256:createHash('sha256').update(payload).digest('hex')});

test('default signed receiver uses V7 modern or unchanged legacy headers for exact key lookup and receipt RPC',async()=>{
 for(const key of [opaque,legacy]){
  const h=fetchHarness(receiverAnswer),handler=createEdgeReceiver({env:env(key),fetchImpl:h.fetchImpl,now:()=>timestamp});
  const response=await handler(receiverRequest());assert.equal(response.status,200);assert.equal((await response.json()).acknowledged,true);
  assert.deepEqual(h.calls.map(call=>call.body.p_action),['key','receive']);checkServiceCalls(h.calls,key);
  assert.ok(h.calls.every(call=>call.target===config.url+'/rest/v1/rpc/wave5_edge_control'&&call.body.p_runtime_id===config.runtimeId));
  assert.equal(h.calls[1].body.p_payload.payloadBase64,payload.toString('base64'));
 }
});

test('all unsigned receiver routes retain authentication denials and cannot invoke backend or fault responses',async()=>{
 let calls=0;const handler=createEdgeReceiver({env:env(opaque),fetchImpl:()=>{calls++;assert.fail('unsigned backend');},now:()=>timestamp});
 for(const route of ['accept','redirect','timeout','reject']){
  const response=await handler(request('receiver',route));assert.equal(response.status,403);
  assert.deepEqual(await response.json(),{code:'INTEGRATION_ACCESS_DENIED'});assert.equal(response.headers.has('location'),false);
 }assert.equal(calls,0);
});

test('forged HMAC and stale timestamp preserve original denial order under modern credentials',async()=>{
 const h=fetchHarness(receiverAnswer),handler=createEdgeReceiver({env:env(opaque),fetchImpl:h.fetchImpl,now:()=>timestamp});
 assert.equal((await handler(receiverRequest('accept',{'x-jentra-signature':'v1='+'b'.repeat(64)}))).status,403);
 assert.deepEqual(h.calls.map(call=>call.body.p_action),['key']);
 assert.equal((await handler(receiverRequest('accept',{'x-jentra-timestamp':String(timestamp-301)}))).status,403);
 assert.equal(h.calls.length,1);checkServiceCalls(h.calls,opaque);
});

test('malformed or publishable service keys never enter signed receiver/default runtime backend paths',async()=>{
 for(const serviceKey of [publishable,'sb_secret_short','a.b.c','a'.repeat(40),opaque+' ',null]){
  let calls=0;const options={env:env(serviceKey),fetchImpl:()=>{calls++;assert.fail('invalid service key');}};
  const receiver=createEdgeReceiver({...options,now:()=>timestamp});assert.equal((await receiver(receiverRequest())).status,503);
  const runtime=createEdgeRuntime(options);assert.equal((await runtime(schedule())).status,503);assert.equal(calls,0);
 }
});

const forecast={contractRevision:1,modelProvider:'unavailable',sourceId:uid(5),sourceHash:'a'.repeat(64),
 scope:{tenantId:uid(2),legalEntityId:uid(3),branchId:null},currencies:[{currency:'LKR',population:1,amount:'10.000000',weightedAmount:'5.000000'}],
 horizonStart:'2026-10-01',horizonEnd:'2026-11-01'};
const suggestion={commandCode:'analytics.freeze_pipeline.v1',sourceId:forecast.sourceId,sourceHash:forecast.sourceHash,
 horizonStart:forecast.horizonStart,horizonEnd:forecast.horizonEnd};
const modelRequest={sourceId:forecast.sourceId,scope:forecast.scope,invocationId:uid(6),usageEventId:uid(7),maxTokens:'20',
 periodStart:'2026-10-01T00:00:00Z',periodEnd:'2026-11-01T00:00:00Z'};
test('default model path keeps the caller JWT/public apikey while all service-control RPCs use V7 modern apikey-only',async()=>{
 const h=fetchHarness(call=>call.target.endsWith('/get_ai_forecast_evidence')?json(forecast)
  :call.body.p_action==='model.begin'?json({state:'settled',tokens:'7',suggestion}):json({recorded:true}));let generated=0;
 const handler=createEdgeRuntime({env:{...env(opaque),SUPABASE_ANON_KEY:publishable,W5_OPENAI_API_KEY:'DELIBERATELY_FAKE_MODEL_KEY_CONTROLLED_FIXTURE'},
  fetchImpl:h.fetchImpl,providerFactory:()=>({policyRevision:1,trustedUsage:true,generate:()=>{generated++;assert.fail('settled does not generate');}})});
 const response=await handler(request('runtime','model/suggestion',modelRequest,{authorization:'Bearer '+userJwt}));
 assert.equal(response.status,200);assert.deepEqual(await response.json(),suggestion);assert.equal(generated,0);
 const userCalls=h.calls.filter(call=>call.target.endsWith('/get_ai_forecast_evidence'));
 const serviceCalls=h.calls.filter(call=>call.target.endsWith('/wave5_runtime_worker'));
 assert.equal(userCalls.length,2);assert.equal(serviceCalls.length,2);
 for(const call of userCalls){assert.equal(call.options.headers.apikey,publishable);assert.equal(call.options.headers.authorization,'Bearer '+userJwt);}
 checkServiceCalls(serviceCalls,opaque);assert.deepEqual(serviceCalls.map(call=>call.body.p_action),['model.begin','usage.settle']);
});

test('missing public model caller JWT still denies without service fallback, user read or provider call',async()=>{
 let calls=0;const handler=createEdgeRuntime({env:{...env(opaque),SUPABASE_ANON_KEY:publishable,W5_OPENAI_API_KEY:'DELIBERATELY_FAKE_MODEL_KEY_CONTROLLED_FIXTURE'},
  fetchImpl:()=>{calls++;assert.fail('no caller backend');},providerFactory:()=>({})});
 const response=await handler(request('runtime','model/suggestion',modelRequest));
 assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'AUTH_REQUIRED'});assert.equal(calls,0);
});

test('factory construction performs no env reads, network operations or dictionary parsing',()=>{
 const locked={get(){assert.fail('construction key access');}};
 assert.equal(typeof createEdgeRuntime({env:locked,fetchImpl:()=>assert.fail('construction network')}),'function');
 assert.equal(typeof createEdgeReceiver({env:locked,fetchImpl:()=>assert.fail('construction network')}),'function');
 for(const value of [0,65001,NaN])assert.throws(()=>createEdgeRuntime({env:locked,requestTimeoutMs:value}),/WORKER_CONFIGURATION_INVALID/);
});

test('scope, routes, caller checks, caps and lazy imports are preserved by exact minimal source transformations',async()=>{
 const read=name=>fs.readFile(new URL('../../../../workers/wave5/'+name,import.meta.url),'utf8');
 const scoped=await read('scoped_runtime_20261014_r5_v7.mjs');
 assert.equal(scoped.replace('./persistent_control_20261014_r5_v7.mjs','./persistent_control.mjs'),await read('scoped_runtime.mjs'));
 const helperImport="import {serviceCredentialKind} from './provider_credentials_20261014_r5_v7.mjs';\n";
 for(const role of ['runtime','receiver']){
  let current=await read(`edge_${role}_20261014_r5_v7.mjs`);assert.ok(current.startsWith(helperImport));current=current.slice(helperImport.length);
  current=current.replace('./persistent_control_20261014_r5_v7.mjs','./persistent_control.mjs');
  if(role==='runtime')current=current.replace('./scoped_runtime_20261014_r5_v7.mjs','./scoped_runtime.mjs');
  current=current.replace("if(serviceCredentialKind(serviceKey)===null)throw Error('WORKER_PROVIDER_UNAVAILABLE');",
   role==='runtime'?"if(!/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(serviceKey))throw Error('WORKER_PROVIDER_UNAVAILABLE');"
    :"if(!/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(serviceKey??''))throw Error('WORKER_PROVIDER_UNAVAILABLE');");
  assert.equal(current,await read(`edge_${role}_20261014_r5_v6.mjs`));
 }
 const helper=await read('provider_credentials_20261014_r5_v7.mjs');
 assert.equal(/JSON\.parse|atob\(|process\.env|Deno\.env|SUPABASE_SECRET_KEYS/.test(helper),false);
 const persistent=await read('persistent_control_20261014_r5_v7.mjs');
 assert.ok(persistent.includes("await import('./worker_runtime.mjs')"));assert.ok(persistent.includes('AbortSignal.timeout(15000)'));
});
