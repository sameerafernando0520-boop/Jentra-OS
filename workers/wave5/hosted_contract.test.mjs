import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createEdgeRuntime} from './edge_runtime.mjs';
import {createEdgeReceiver} from './edge_receiver.mjs';
import {createWorkerRpc} from './persistent_control.mjs';
import {edgeConfiguration as config} from './edge_configuration.mjs';
import {forecastEvent,signDelivery} from './integration_policy.mjs';

const id='00000000-0000-4000-8000-000000000001';
const legacyKey='a'.repeat(40)+'.'+'b'.repeat(40)+'.'+'c'.repeat(40);
const secretKey='sb_secret_'+'s'.repeat(40);
const request=url=>new Request(url,{method:'POST',headers:{'content-type':'application/json'},body:'{}'});
const origins=[
 ['public',config.url+'/functions/v1'],
 ['project namespace',config.url],
 ['managed HTTPS','https://edge-runtime.supabase.com'],
 ['managed project HTTP',config.url.replace('https:','http:')],
];

for(const [label,origin] of origins){
 test(`current runtime reaches authentication through ${label} without a backend call`,async()=>{
  let calls=0;
  const runtime=createEdgeRuntime({env:{SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:legacyKey},
   controlFactory:()=>({}),edgeRpcFactory:()=>async()=>{calls++;throw Error('MUST_NOT_CALL');}});
  const result=await runtime(request(origin+'/wave5-runtime/schedule'));
  assert.equal(result.status,403);
  assert.deepEqual(await result.json(),{code:'WORKER_ACCESS_DENIED'});
  assert.equal(calls,0);
 });
 test(`current receiver rejects unsigned ${label} input before private configuration`,async()=>{
  const receiver=createEdgeReceiver({env:{get(){throw Error('MUST_NOT_READ_PRIVATE_CONFIG');}}});
  const result=await receiver(request(origin+'/wave5-receiver/accept'));
  assert.equal(result.status,403);
  assert.deepEqual(await result.json(),{code:'INTEGRATION_ACCESS_DENIED'});
 });
}

test('current runtime accepts platform-supplied opaque service keys and still requires schedule authority',async()=>{
 let calls=0;
 const runtime=createEdgeRuntime({env:{SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:secretKey},
  controlFactory:()=>({}),edgeRpcFactory:()=>async(name,p)=>{
   calls++;
   assert.equal(name,'wave5_edge_control');
   assert.equal(p.p_action,'begin_tick');
   return {permitted:false};
  }});
 const unsigned=await runtime(request(config.workerUrl+'/schedule'));
 assert.equal(unsigned.status,403);assert.equal(calls,0);
 const signed=new Request(config.workerUrl+'/schedule',{method:'POST',headers:{
  'content-type':'application/json','x-jentra-schedule-key':'c'.repeat(64)},body:JSON.stringify({tickId:id,kind:'health'})});
 assert.deepEqual(await (await runtime(signed)).json(),{state:'already_running'});
 assert.equal(calls,1);
});

for(const [key,label] of [[secretKey,'opaque'],[legacyKey,'legacy']]){
 test(`current RPC transport uses the correct ${label} credential headers`,async()=>{
  let observed;
  const rpc=createWorkerRpc({url:config.url,serviceKey:key,fetchImpl:async(url,options)=>{
   observed={url,options};return new Response('{"ready":true}');
  }});
  assert.deepEqual(await rpc('wave5_runtime_worker',{p_runtime_id:config.runtimeId,p_action:'readiness'}),{ready:true});
  assert.equal(observed.options.headers.apikey,key);
  assert.equal(observed.options.headers.authorization,label==='legacy'?`Bearer ${key}`:undefined);
  assert.equal(observed.options.headers['content-profile'],'api');
  assert.equal(observed.options.redirect,'error');
 });
}

test('publishable and malformed keys never reach a privileged RPC',()=>{
 for(const key of ['sb_publishable_'+'p'.repeat(40),'sb_secret_'+'!'.repeat(40),'x'.repeat(40)]){
  assert.throws(()=>createWorkerRpc({url:config.url,serviceKey:key}),/WORKER_CONFIGURATION_INVALID/);
 }
});

test('current receiver authenticates a signed managed-hop delivery using opaque-key RPC headers',async()=>{
 const timestamp=1791529200,key=Buffer.from('a'.repeat(64),'hex'),calls=[];
 const event={eventId:id,type:'analytics.forecast.frozen.v1',tenantId:id,legalEntityId:id,branchId:id,
  forecastId:id,definitionVersion:1,sourceHash:'b'.repeat(64)};
 const payload=forecastEvent(event,event),sha256=createHash('sha256').update(payload).digest('hex');
 const receiver=createEdgeReceiver({env:{SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:secretKey},now:()=>timestamp,
  fetchImpl:async(url,options)=>{
   assert.equal(url.pathname,'/rest/v1/rpc/wave5_edge_control');
   assert.equal(options.headers.apikey,secretKey);assert.equal(options.headers.authorization,undefined);
   const body=JSON.parse(options.body);calls.push(body.p_action);
   return Response.json(body.p_action==='key'?{value:'a'.repeat(64)}:{acknowledged:true,sha256,duplicate:false});
  }});
 const result=await receiver(new Request('https://edge-runtime.supabase.com/wave5-receiver/accept',{
  method:'POST',headers:{'content-type':'application/json','x-jentra-event-id':id,'x-jentra-timestamp':String(timestamp),
   'x-jentra-signature':signDelivery({payload,eventId:id,timestamp,key,keyVersion:1})},body:payload}));
 assert.equal(result.status,200);
 assert.deepEqual(await result.json(),{eventId:id,sha256,duplicate:false,acknowledged:true});
 assert.deepEqual(calls,['key','receive']);
});

test('routing cannot be widened with a different project, platform HTTP, query or foreign path',async()=>{
 let calls=0;
 const runtime=createEdgeRuntime({env:{get(){calls++;throw Error('MUST_NOT_READ');}}});
 for(const url of [
  'https://different.supabase.co/wave5-runtime/schedule',
  'http://edge-runtime.supabase.com/wave5-runtime/schedule',
  config.workerUrl+'/schedule?forwarded=1',
  config.workerUrl+'/schedule#fragment',
  config.url+'/unrelated/schedule',
 ])assert.equal((await runtime(request(url))).status,404);
 assert.equal(calls,0);
});
