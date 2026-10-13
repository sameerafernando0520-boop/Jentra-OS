import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {edgeRoute,classifyEdgeIngress,withBoundedIngressDiagnostic} from './edge_route_20261013_r5_v3.mjs';
import {createEdgeRuntime} from './edge_runtime_20261013_r5_v3.mjs';
import {createEdgeReceiver} from './edge_receiver_20261013_r5_v3.mjs';
import {edgeConfiguration as config} from './edge_configuration.mjs';
import {forecastEvent,signDelivery} from './integration_policy.mjs';

// The original RED run against v2 is saved separately before this GREEN source.
// Every request below is a local synthetic fixture, not an observed managed URL.
const platform = 'https://edge-runtime.supabase.com';
const namespaces = [
 {base:config.workerUrl,name:'wave5-runtime',routes:['/schedule','/external/forecast','/model/suggestion']},
 {base:config.receiverUrl.slice(0,-'/accept'.length),name:'wave5-receiver',routes:['/accept','/redirect','/timeout','/reject']},
];
for(const {base,name,routes} of namespaces){
 for(const route of routes){
  for(const [form,url] of [
   ['public',`${base}${route}`],
   ['project namespace',`${config.url}/${name}${route}`],
   ['platform namespace',`${platform}/${name}${route}`],
  ])test(`${form} ${name}${route} selects the fixed route`,()=>assert.equal(edgeRoute(url,base,routes),route));
  test(`platform public prefix ${name}${route} is excluded`,()=>assert.equal(edgeRoute(`${platform}/functions/v1/${name}${route}`,base,routes),null));
 }
 const known=routes[0],namespace=`/${name}${known}`,cross=name==='wave5-runtime'?'wave5-receiver':'wave5-runtime';
 const cases=[
  ['other host',`https://other.invalid${namespace}`],
  ['platform lookalike',`https://edge-runtime.supabase.com.other.invalid${namespace}`],
  ['platform subdomain',`https://sub.edge-runtime.supabase.com${namespace}`],
  ['project lookalike',`${config.url}.other.invalid${namespace}`],
  ['platform HTTP',`http://edge-runtime.supabase.com${namespace}`],
  ['project HTTP',config.url.replace('https:','http:')+namespace],
  ['platform other port',`${platform}:444${namespace}`],
  ['platform explicit default port',`${platform}:443${namespace}`],
  ['username',`https://fixture@edge-runtime.supabase.com${namespace}`],
  ['empty userinfo',`https://@edge-runtime.supabase.com${namespace}`],
  ['password',`https://fixture:fixture@edge-runtime.supabase.com${namespace}`],
  ['query',`${platform}${namespace}?fixture=1`],
  ['empty query',`${platform}${namespace}?`],
  ['hash',`${platform}${namespace}#fixture`],
  ['empty hash',`${platform}${namespace}#`],
  ['bare route',`${platform}${known}`],
  ['other function',`${platform}/${cross}${known}`],
  ['unrelated function',`${platform}/unreviewed${known}`],
  ['unknown route',`${platform}/${name}/unreviewed`],
  ['extra suffix',`${platform}${namespace}/extra`],
  ['trailing slash',`${platform}${namespace}/`],
  ['doubled namespace slash',`${platform}//${name}${known}`],
  ['doubled route slash',`${platform}/${name}/${known}`],
  ['encoded namespace',`${platform}/%77${name.slice(1)}${known}`],
  ['encoded route slash',`${platform}/${name}/%2f${known.slice(1)}`],
  ['raw path normalization',`${platform}/${name}/unused/..${known}`],
  ['backslash normalization',`${platform}\\${name}${known}`],
  ['leading whitespace',` ${platform}${namespace}`],
  ['invalid URL','not a URL'],
  ['unsupported URL value',null],
 ];
 for(const [reason,url] of cases)test(`${name} rejects ${reason}`,()=>assert.equal(edgeRoute(url,base,routes),null));
 test(`${name} caller cannot expand fixed routes`,()=>assert.equal(edgeRoute(`${platform}/${name}/unreviewed`,base,[...routes,'/unreviewed']),null));
 test(`${name} caller can only narrow routes`,()=>assert.equal(edgeRoute(`${platform}${namespace}`,base,[]),null));
 for(const endpoint of [base+'/',base+'?',base+'#',base.replace(config.url,'https://other.invalid'),base.replace('https:','http:'),`${config.url}/functions/v1/unreviewed`])
  test(`${name} rejects unreviewed endpoint ${endpoint.replace(config.url,'PROJECT')}`,()=>assert.equal(edgeRoute(`${platform}${namespace}`,endpoint,routes),null));
}

test('diagnostics contain only fixed enum and boolean fields, never supplied data',()=>{
 const marker='PRIVATE_FIXTURE_MUST_NOT_LEAK';
 const classification=classifyEdgeIngress(`https://${marker}:${marker}@edge-runtime.supabase.com/wave5-runtime/schedule?${marker}#${marker}`,config.workerUrl,namespaces[0].routes);
 assert.deepEqual(classification,{originClass:'platform_runtime',pathClass:'function_namespace',https:true,query:true,hash:true,userinfo:true,routeRecognized:false});
 assert.equal(JSON.stringify(classification).includes(marker),false);assert.equal(Object.isFrozen(classification),true);
});
test('diagnostics distinguish the exact proposed internal namespace',()=>assert.deepEqual(
 classifyEdgeIngress(`${platform}/wave5-runtime/schedule`,config.workerUrl,namespaces[0].routes),
 {originClass:'platform_runtime',pathClass:'function_namespace',https:true,query:false,hash:false,userinfo:false,routeRecognized:true}));
test('diagnostics distinguish the preserved public prefix',()=>assert.deepEqual(
 classifyEdgeIngress(config.workerUrl+'/schedule',config.workerUrl,namespaces[0].routes),
 {originClass:'public_project',pathClass:'public_function',https:true,query:false,hash:false,userinfo:false,routeRecognized:true}));
test('diagnostics classify invalid URL input without echoing it',()=>assert.deepEqual(
 classifyEdgeIngress('PRIVATE_FIXTURE_NOT_A_URL',config.workerUrl,namespaces[0].routes),
 {originClass:'invalid',pathClass:'invalid',https:false,query:false,hash:false,userinfo:false,routeRecognized:false}));
test('diagnostics classify an unknown origin without echoing it',()=>{
 const diagnostic=classifyEdgeIngress('https://PRIVATE_FIXTURE.invalid/unknown',config.workerUrl,namespaces[0].routes);
 assert.equal(diagnostic.originClass,'other');assert.equal(diagnostic.pathClass,'other');assert.equal(diagnostic.routeRecognized,false);
 assert.equal(JSON.stringify(diagnostic).includes('PRIVATE_FIXTURE'),false);
});
test('one diagnostic survives 32 concurrent requests without reading headers/body/method',async()=>{
 const observations=[],requests=[],req={url:`${platform}/wave5-runtime/schedule`};
 for(const name of ['headers','body','method'])Object.defineProperty(req,name,{get(){throw Error('PRIVATE_FIXTURE_MUST_NOT_BE_READ');}});
 const wrapped=withBoundedIngressDiagnostic({handler:async request=>{requests.push(request);return 403;},endpointUrl:config.workerUrl,allowedRoutes:namespaces[0].routes,worker:'runtime',observe:item=>observations.push(item)});
 assert.deepEqual(await Promise.all(Array.from({length:32},()=>wrapped(req))),Array(32).fill(403));
 assert.equal(requests.length,32);assert.equal(observations.length,1);
 assert.deepEqual(Object.keys(observations[0]),['kind','worker','originClass','pathClass','https','query','hash','userinfo','routeRecognized']);
 assert.equal(observations[0].kind,'wave5_ingress_v3');assert.equal(observations[0].worker,'runtime');assert.equal(Object.isFrozen(observations[0]),true);
});
test('diagnostic sink failure cannot interrupt or repeat the authenticated handler',async()=>{
 let observed=0,called=0;const wrapped=withBoundedIngressDiagnostic({handler:()=>{called++;return 403;},endpointUrl:namespaces[1].base,allowedRoutes:namespaces[1].routes,worker:'receiver',observe:()=>{observed++;throw Error('PRIVATE_FIXTURE');}});
 assert.equal(wrapped({url:`${platform}/wave5-receiver/accept`}),403);assert.equal(wrapped({url:'invalid'}),403);
 assert.equal(observed,1);assert.equal(called,2);
});
test('diagnostic configuration cannot inject a dynamic worker label',()=>assert.throws(()=>withBoundedIngressDiagnostic({handler:()=>{},endpointUrl:config.workerUrl,allowedRoutes:namespaces[0].routes,worker:'PRIVATE_FIXTURE',observe:()=>{}}),/INGRESS_CONFIGURATION_INVALID/));

for(const stem of ['edge_runtime','edge_receiver'])test(`${stem} successor changes only the route import bytes`,async()=>{
 const original=await readFile(new URL(`./${stem}_20261013_r5.mjs`,import.meta.url));
 const successor=await readFile(new URL(`./${stem}_20261013_r5_v3.mjs`,import.meta.url));
 const before="import {edgeRoute} from './edge_route_20261013_r5.mjs';",after="import {edgeRoute} from './edge_route_20261013_r5_v3.mjs';";
 assert.equal(original.subarray(0,Buffer.byteLength(before)).toString(),before);
 assert(successor.equals(Buffer.concat([Buffer.from(after),original.subarray(Buffer.byteLength(before))])));
});

const id='00000000-0000-4000-8000-000000000001';
// Synthetic local strings, never owner/project credentials.
const env={SUPABASE_URL:config.url,SUPABASE_SERVICE_ROLE_KEY:'a'.repeat(40)+'.'+'b'.repeat(40)+'.'+'c'.repeat(40),SUPABASE_ANON_KEY:'p'.repeat(40)};
const request=(route,body={},headers={})=>new Request(`${platform}/wave5-runtime${route}`,{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body)});
const schedule=(body={tickId:id,kind:'health'},key='c'.repeat(64))=>request('/schedule',body,{'x-jentra-schedule-key':key});
function runtimeHarness({permit={permitted:true,tenantId:id},fail,control={},environment=env}={}){
 const calls=[];
 const handler=createEdgeRuntime({env:environment,edgeRpcFactory:()=>async(_name,p)=>{calls.push({action:p.p_action,payload:p.p_payload});if(fail)throw Error(fail);return p.p_action==='begin_tick'?permit:{recorded:true};},
  controlFactory:()=>({readiness:async()=>({contractRevision:1,ready:true,providers:{'synthetic_subscription.v1':1,'committed_webhook.v1':1}}),collectHealth:async()=>calls.push({health:true}),dueSyntheticSubscriptions:async()=>({contractRevision:1,items:[],nextCursor:null}),reconcileAcknowledged:async()=>{},claimCommittedDelivery:async()=>null,...control})});
 return {handler,calls};
}
test('internal schedule still rejects unsigned requests before a trusted RPC',async()=>{const h=runtimeHarness();assert.equal((await h.handler(request('/schedule'))).status,403);assert.equal(h.calls.length,0);});
test('internal schedule preserves hashed secret and server denial before health',async()=>{
 const h=runtimeHarness({fail:'WORKER_ACCESS_DENIED'});assert.equal((await h.handler(schedule())).status,403);assert.equal(h.calls.length,1);
 assert.equal(h.calls[0].payload.secretHash,createHash('sha256').update('c'.repeat(64)).digest('hex'));assert.equal(JSON.stringify(h.calls).includes('c'.repeat(64)),false);
});
test('internal schedule preserves revoked runtime denial',async()=>{const h=runtimeHarness({fail:'RUNTIME_SCOPE_DENIED'});assert.equal((await h.handler(schedule())).status,403);assert.equal(h.calls.length,1);});
test('internal duplicate tick still performs no health or finish effect',async()=>{const h=runtimeHarness({permit:{permitted:false}});assert.equal((await (await h.handler(schedule())).json()).state,'already_running');assert.equal(h.calls.length,1);});
test('internal allowed tick preserves server-selected scope and durable finish order',async()=>{
 const h=runtimeHarness();assert.equal((await (await h.handler(schedule())).json()).state,'completed');
 assert.deepEqual(h.calls.map(c=>c.action??'health'),['begin_tick','health','finish_tick']);assert.equal(h.calls.at(-1).payload.success,true);
});
test('internal schedule cannot add a client-selected tenant',async()=>{const h=runtimeHarness();assert.equal((await h.handler(schedule({tickId:id,kind:'health',tenantId:id}))).status,400);assert.equal(h.calls.length,0);});
test('internal request cannot select a different Supabase project through environment',async()=>{const h=runtimeHarness({environment:{...env,SUPABASE_URL:'https://other.invalid'}});assert.equal((await h.handler(schedule())).status,503);assert.equal(h.calls.length,0);});
test('internal model route still reports provider absence without invoking anything',async()=>{const h=runtimeHarness();assert.equal((await (await h.handler(request('/model/suggestion'))).json()).code,'MODEL_PROVIDER_UNAVAILABLE');assert.equal(h.calls.length,0);});
test('unsupported internal runtime method remains 404 before backend access',async()=>{const h=runtimeHarness();assert.equal((await h.handler(new Request(`${platform}/wave5-runtime/schedule`))).status,404);assert.equal(h.calls.length,0);});
test('unreviewed origins and paths do not even read platform credentials',async()=>{
 let reads=0;const h=runtimeHarness({environment:{get(){reads++;throw Error('PRIVATE_FIXTURE_MUST_NOT_BE_READ');}}});
 for(const url of [`https://other.invalid/wave5-runtime/schedule`,`${platform}/schedule`,`${platform}/wave5-runtime/schedule?fixture=1`,`${platform}/wave5-receiver/schedule`])assert.equal((await h.handler(new Request(url,{method:'POST'}))).status,404);
 assert.equal(reads,0);assert.equal(h.calls.length,0);
});
test('internal requests retain the configured concurrent request cap',async()=>{
 let release,started=0;const gate=new Promise(resolve=>{release=resolve;});
 const h=runtimeHarness({control:{collectHealth:async()=>{started++;await gate;}}});
 const pending=Array.from({length:config.maxConcurrentRequests},()=>h.handler(schedule()));
 while(started<config.maxConcurrentRequests)await new Promise(resolve=>setImmediate(resolve));
 assert.equal((await h.handler(schedule())).status,429);release();assert((await Promise.all(pending)).every(res=>res.status===200));
});

const event={eventId:id,type:'analytics.forecast.frozen.v1',tenantId:id,legalEntityId:id,branchId:id,forecastId:id,definitionVersion:1,sourceHash:'a'.repeat(64)};
const payload=forecastEvent(event,event),key=Buffer.from('a'.repeat(64),'hex'),timestamp=1791529200;
function receiverRequest(mode='accept',changes={}){
 const bytes=changes.payload??payload;
 return new Request(`${platform}/wave5-receiver/${mode}`,{method:'POST',headers:{'content-type':'application/json','x-jentra-event-id':id,'x-jentra-timestamp':String(timestamp),
  'x-jentra-signature':signDelivery({payload:bytes,eventId:id,timestamp,key,keyVersion:1}),...changes.headers},body:bytes});
}
function receiverHarness({fail,environment=env}={}){
 const calls=[];const handler=createEdgeReceiver({env:environment,now:()=>timestamp,rpcFactory:()=>async(_name,p)=>{calls.push(p.p_action);if(fail&&p.p_action!=='key')throw Error(fail);
  return p.p_action==='key'?{value:'a'.repeat(64)}:p.p_action==='receive_probe'?{permitted:true}:{acknowledged:true,duplicate:false,sha256:createHash('sha256').update(payload).digest('hex')};}});
 return {handler,calls};
}
for(const mode of ['accept','redirect','timeout','reject'])test(`internal receiver ${mode} still requires signed headers before private key lookup`,async()=>{
 const h=receiverHarness();assert.equal((await h.handler(new Request(`${platform}/wave5-receiver/${mode}`,{method:'POST',body:'{}'}))).status,403);assert.equal(h.calls.length,0);
});
test('internal receiver still validates exact bytes before durable ACK',async()=>{const h=receiverHarness();assert.equal((await (await h.handler(receiverRequest())).json()).acknowledged,true);assert.deepEqual(h.calls,['key','receive']);});
test('internal receiver forged signature cannot create a receipt',async()=>{const h=receiverHarness();assert.equal((await h.handler(receiverRequest('accept',{headers:{'x-jentra-signature':'v1='+'b'.repeat(64)}}))).status,403);assert.deepEqual(h.calls,['key']);});
test('internal receiver rejects stale signed time before key lookup',async()=>{const h=receiverHarness();assert.equal((await h.handler(receiverRequest('accept',{headers:{'x-jentra-timestamp':String(timestamp-301)}}))).status,403);assert.equal(h.calls.length,0);});
test('internal receiver rejects noncanonical signed payload before key lookup',async()=>{const h=receiverHarness();assert.equal((await h.handler(receiverRequest('accept',{payload:Buffer.from(' '+payload)}))).status,400);assert.equal(h.calls.length,0);});
test('internal receiver still denies server-revoked scope after HMAC verification',async()=>{const h=receiverHarness({fail:'RUNTIME_SCOPE_DENIED'});assert.equal((await h.handler(receiverRequest())).status,503);assert.deepEqual(h.calls,['key','receive']);});
test('internal receiver still rejects another injected project before key lookup',async()=>{const h=receiverHarness({environment:{...env,SUPABASE_URL:'https://other.invalid'}});assert.equal((await h.handler(receiverRequest())).status,503);assert.equal(h.calls.length,0);});
