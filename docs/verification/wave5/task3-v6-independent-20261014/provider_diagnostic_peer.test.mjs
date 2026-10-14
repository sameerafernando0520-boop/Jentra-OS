import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

const configuredUrl='https://xpdoufauvrbdmxgngetv.supabase.co';
const moduleUrl=new URL('../../../../workers/wave5/edge_route_20261014_r5_v6.mjs',import.meta.url);
const isolate=()=>import(moduleUrl.href+'?independent-controlled-isolate='+randomUUID());
const wrap=(module,handler,env,observe,worker='runtime')=>module.withBoundedProviderDiagnostic({handler,env,configuredUrl,worker,observe});

test('sink catch-property failure cannot replace the original sync or async response',async()=>{
 for(const asynchronous of [false,true]){
  const module=await isolate(),response=new Response('exact original',{status:503}),events=[];
  const pending=Object.defineProperty({},'catch',{get(){events.push('sink-catch');throw Error('CONTROLLED_PRIVATE_VALUE');}});
  const handler=()=>{events.push('handler');return asynchronous?Promise.resolve(response):response;};
  const actual=await wrap(module,handler,{SUPABASE_URL:configuredUrl},()=>{events.push('observe');return pending;})({});
  assert.equal(actual,response);assert.equal(actual.status,503);assert.equal(await actual.text(),'exact original');
  assert.deepEqual(events,['handler','observe','sink-catch']);
 }
});

test('a failed first diagnostic consumes the isolate attempt across later and separately constructed wrappers',async()=>{
 const module=await isolate(),response=new Response('same'),names=[];let sinkCalls=0,handlers=0;
 const failing={get(name){names.push(name);throw Error('CONTROLLED_PRIVATE_VALUE');}};
 const first=wrap(module,()=>{handlers++;return response;},failing,()=>sinkCalls++);
 const second=wrap(module,()=>{handlers++;return response;},{SUPABASE_URL:configuredUrl},()=>sinkCalls++,'receiver');
 assert.equal(first({}),response);assert.equal(first({}),response);assert.equal(second({}),response);
 assert.deepEqual(names,['SUPABASE_URL']);assert.equal(sinkCalls,0);assert.equal(handlers,3);
});

test('service-role and dictionary accessors can fail after the original response without exposing their value',async()=>{
 for(const failing of ['SUPABASE_SERVICE_ROLE_KEY','SUPABASE_SECRET_KEYS']){
  const module=await isolate(),response=new Response('untouched'),names=[];let emitted=0;
  const env={get(name){names.push(name);if(name===failing)throw Error('CONTROLLED_PRIVATE_VALUE');return configuredUrl;}};
  assert.equal(await wrap(module,async()=>response,env,()=>emitted++)({}),response);
  assert.equal(emitted,0);assert.equal(names.includes(failing),true);
  assert.equal(await response.text(),'untouched');
 }
});

test('closed descriptor classification cannot coerce raw objects or read unknown environment properties',async()=>{
 const module=await isolate(),names=[],response=new Response('same'),emitted=[];
 const hostile=new Proxy({}, {get(){throw Error('RAW_VALUE_INSPECTION');},ownKeys(){throw Error('RAW_VALUE_ENUMERATION');}});
 const env=new Proxy({}, {get(_target,name){assert.ok(['get','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_SECRET_KEYS'].includes(name));
  if(name==='get')return undefined;names.push(name);return hostile;},ownKeys(){throw Error('RAW_ENV_ENUMERATION');}});
 assert.equal(wrap(module,()=>response,env,record=>emitted.push(record))({}),response);
 assert.deepEqual(names,['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_SECRET_KEYS']);
 assert.deepEqual(emitted,[{kind:'wave5_provider_v6',worker:'runtime',supabaseUrlClass:'other',serviceRoleShape:'other',secretKeysDictionaryPresent:false}]);
 assert.equal(Object.isFrozen(emitted[0]),true);
});

test('diagnostic does not become a provider repair or an authentication statement for JWT-shaped fixture data',async()=>{
 const module=await isolate(),records=[],response=new Response('same');
 const env={SUPABASE_URL:configuredUrl+'/',SUPABASE_SERVICE_ROLE_KEY:'deliberately_fake.payload.signature',SUPABASE_SECRET_KEYS:'malformed-json'};
 assert.equal(wrap(module,()=>response,env,record=>records.push(record))({}),response);
 assert.deepEqual(records,[{kind:'wave5_provider_v6',worker:'runtime',supabaseUrlClass:'exact_configured_https_with_slash',
  serviceRoleShape:'legacy_jwt',secretKeysDictionaryPresent:true}]);
 assert.equal(env.SUPABASE_URL,configuredUrl+'/');assert.equal(env.SUPABASE_SECRET_KEYS,'malformed-json');
 assert.equal(Object.keys(records[0]).length,5);
});
