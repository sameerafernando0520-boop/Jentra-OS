import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {edgeConfiguration} from '../../../../workers/wave5/edge_configuration.mjs';
import {edgeRoute as beforeRoute} from '../../../../workers/wave5/edge_route_20261014_r5_v5.mjs';
import {edgeRoute,classifyProviderEnvironment} from '../../../../workers/wave5/edge_route_20261014_r5_v6.mjs';
import {createEdgeRuntime as createBeforeRuntime} from '../../../../workers/wave5/edge_runtime_20261014_r5_v5.mjs';
import {createEdgeReceiver as createBeforeReceiver} from '../../../../workers/wave5/edge_receiver_20261014_r5_v5.mjs';
import {createEdgeRuntime} from '../../../../workers/wave5/edge_runtime_20261014_r5_v6.mjs';
import {createEdgeReceiver} from '../../../../workers/wave5/edge_receiver_20261014_r5_v6.mjs';
const configured=edgeConfiguration.url,http=configured.replace('https:','http:');
const fixtureJwt='DELIBERATELY_FAKE_TEST_FIXTURE_000000000.a.b';
const opaqueFixture='sb_secret_CONTROLLED_PLACEHOLDER_ONLY';
const allowedNames=['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_SECRET_KEYS'];
const freshModule=()=>import(new URL(`../../../../workers/wave5/edge_route_20261014_r5_v6.mjs?controlled-isolate=${randomUUID()}`,import.meta.url));
const request=(worker='runtime')=>new Request(`${http}/wave5-${worker}/${worker==='runtime'?'schedule':'accept'}`,
  {method:'POST',headers:{'content-type':'application/json'},body:'{}'});
const descriptorKeys=['kind','worker','supabaseUrlClass','serviceRoleShape','secretKeysDictionaryPresent'].sort();
const wrap=(module,handler,env,observe,worker='runtime')=>module.withBoundedProviderDiagnostic({handler,env,configuredUrl:configured,worker,observe});

test('URL classifier has only the five approved exact classes without parsing or normalizing aliases',()=>{
  for(const [value,expected] of [[configured,'exact_configured_https'],[configured+'/','exact_configured_https_with_slash'],
    [http,'exact_project_http'],[undefined,'missing'],[null,'missing'],['','missing'],[' ','other'],[http+'/','other'],
    [configured+'?PRIVATE_URL_VALUE','other'],[configured+':443','other'],[configured.toUpperCase(),'other'],
    ['https://PRIVATE_VALUE@xpdoufauvrbdmxgngetv.supabase.co','other'],['http://edge-runtime.supabase.com','other'],
    [new Proxy({}, {get(){throw Error('NO_OBJECT_COERCION');}}),'other']]){
    const actual=classifyProviderEnvironment({SUPABASE_URL:value},configured);assert.equal(actual.supabaseUrlClass,expected);
    assert.equal(JSON.stringify(actual).includes('PRIVATE'),false);
  }
});
test('service role classifier reports shape only and never decodes, parses or publishes key content',()=>{
  for(const [value,expected] of [[fixtureJwt,'legacy_jwt'],[opaqueFixture,'opaque_secret_style'],[undefined,'missing'],[null,'missing'],
    ['','missing'],['a.b','other'],['Bearer '+fixtureJwt,'other'],['sb_secret_','other'],['sb_secret_@@PRIVATE','other'],
    [new Proxy({}, {get(){throw Error('NO_OBJECT_COERCION');}}),'other']]){
    const actual=classifyProviderEnvironment({SUPABASE_SERVICE_ROLE_KEY:value},configured);assert.equal(actual.serviceRoleShape,expected);
    assert.equal(JSON.stringify(actual).includes('PLACEHOLDER'),false);assert.equal(JSON.stringify(actual).includes('FIXTURE'),false);
  }
});
test('only the three fixed approved names are read and dictionary JSON is never parsed or emitted',()=>{
  const reads=[];const env={get(name){reads.push(name);assert.ok(allowedNames.includes(name));
    return{name:undefined,SUPABASE_URL:configured,SUPABASE_SERVICE_ROLE_KEY:opaqueFixture,
      SUPABASE_SECRET_KEYS:'{"default":"DO_NOT_PUBLISH_SECRET","unknownName":"DO_NOT_PUBLISH_NAME"}'}[name];}};
  const actual=classifyProviderEnvironment(env,configured);assert.deepEqual(reads,allowedNames);
  assert.equal(actual.secretKeysDictionaryPresent,true);assert.equal(JSON.stringify(actual).includes('DO_NOT_PUBLISH'),false);
  assert.equal(JSON.stringify(actual).includes('unknownName'),false);
  assert.equal(classifyProviderEnvironment({SUPABASE_SECRET_KEYS:'not-json-private'},configured).secretKeysDictionaryPresent,true);
  assert.equal(classifyProviderEnvironment({SUPABASE_SECRET_KEYS:''},configured).secretKeysDictionaryPresent,false);
});
test('factory/import construction performs no diagnostic environment access or observation',async()=>{
  const module=await freshModule();let reads=0,observations=0;
  wrap(module,()=>new Response('same'),{get(){reads++;throw Error('PRIVATE_READ_NOT_ALLOWED');}},()=>observations++);
  assert.equal(reads,0);assert.equal(observations,0);
});
test('one module/isolate emits at most one closed record across concurrent requests and multiple wrappers',async()=>{
  const module=await freshModule(),seen=[],response=new Response('unchanged');let reads=0;
  const env={get(name){reads++;return{SUPABASE_URL:configured,SUPABASE_SERVICE_ROLE_KEY:fixtureJwt,SUPABASE_SECRET_KEYS:'PRIVATE_DICTIONARY'}[name];}};
  const runtime=wrap(module,async()=>{await Promise.resolve();return response;},env,value=>seen.push(value));
  const receiver=wrap(module,async()=>response,env,value=>seen.push(value),'receiver');
  const outputs=await Promise.all(Array.from({length:40},(_,index)=>(index%2?runtime:receiver)(request())));
  assert.ok(outputs.every(output=>output===response));assert.equal(seen.length,1);assert.equal(reads,3);
  assert.deepEqual(Object.keys(seen[0]).sort(),descriptorKeys);assert.equal(Object.isFrozen(seen[0]),true);
  assert.equal(JSON.stringify(seen).includes('PRIVATE'),false);assert.equal(JSON.stringify(seen).includes(fixtureJwt),false);
});
test('diagnostic environment getter failure is swallowed after the exact original response and consumes the single attempt',async()=>{
  const module=await freshModule();let handlerCalls=0,reads=0,observations=0;const response=new Response('same',{status:503});
  const wrapped=wrap(module,()=>{handlerCalls++;return response;},{get(){reads++;throw Error('DO_NOT_PUBLISH_PRIVATE_VALUE');}},()=>observations++);
  assert.equal(wrapped(request()),response);assert.equal(wrapped(request()),response);
  assert.equal(handlerCalls,2);assert.equal(reads,1);assert.equal(observations,0);assert.equal(await response.text(),'same');
});
test('throwing env.get property and rejected/throwing sinks preserve response bytes and status',async()=>{
  for(const failure of ['get-property','sink-throw','sink-reject']){
    const module=await freshModule(),response=new Response('exact unchanged response',{status:403});
    const env=failure==='get-property'?Object.defineProperty({},'get',{get(){throw Error('DO_NOT_PUBLISH_PRIVATE_VALUE');}}):{SUPABASE_URL:configured};
    const observed=()=>{if(failure==='sink-reject')return Promise.reject(Error('DO_NOT_PUBLISH_PRIVATE_VALUE'));throw Error('DO_NOT_PUBLISH_PRIVATE_VALUE');};
    const output=await wrap(module,async()=>response,env,observed)(request());assert.equal(output,response);
    assert.equal(output.status,403);assert.equal(await output.text(),'exact unchanged response');await new Promise(resolve=>setImmediate(resolve));
  }
});
test('a diagnostic never delays handler output waiting for an unresolved sink promise',async()=>{
  const module=await freshModule(),response=new Response('same');let observed=0;
  const wrapped=wrap(module,async()=>response,{SUPABASE_URL:configured},()=>{observed++;return new Promise(()=>{});});
  assert.equal(await wrapped(request()),response);assert.equal(observed,1);
});
test('diagnostic is sequenced after the original handler so a one-shot failing diagnostic getter cannot alter that outcome',async()=>{
  const module=await freshModule(),events=[],response=new Response('original');
  const wrapped=wrap(module,async()=>{events.push('handler');return response;},{get(){events.push('diagnostic');throw Error('PRIVATE');}},()=>assert.fail('getter failed'));
  assert.equal(await wrapped(request()),response);assert.deepEqual(events,['handler','diagnostic']);
});
test('original synchronous throw or rejected handler error remains the exact same object',async()=>{
  for(const asyncFailure of [false,true]){
    const module=await freshModule(),error=Error('ORIGINAL_HANDLER_ERROR');let observed=0;
    const handler=asyncFailure?async()=>{throw error;}:()=>{throw error;};
    const wrapped=wrap(module,handler,{get(){throw Error('DIAGNOSTIC_ONLY');}},()=>observed++);
    if(asyncFailure)await assert.rejects(wrapped(request()),actual=>actual===error);else assert.throws(()=>wrapped(request()),actual=>actual===error);
    assert.equal(observed,0);
  }
});
test('diagnostic does not inspect request URL, headers, body or stringify raw request values',async()=>{
  const module=await freshModule(),response=new Response('same'),seen=[];
  const req=new Proxy({}, {get(){throw Error('RAW_REQUEST_INSPECTION_NOT_ALLOWED');}});
  assert.equal(wrap(module,()=>response,{SUPABASE_URL:configured},value=>seen.push(value))(req),response);
  assert.equal(seen.length,1);assert.deepEqual(Object.keys(seen[0]).sort(),descriptorKeys);
});
test('actual runtime provider-unavailable response is identical to V5 including diagnostic getter/sink failures',async()=>{
  for(const diagnosticFailure of ['none','get','sink']){
    const module=await freshModule(),env={SUPABASE_URL:http,SUPABASE_SERVICE_ROLE_KEY:opaqueFixture};let backend=0;
    const fetchImpl=()=>{backend++;throw Error('NETWORK_NOT_ALLOWED');};
    const baseline=await createBeforeRuntime({env,fetchImpl})(request());
    const diagnosticEnv=diagnosticFailure==='get'?{get(){throw Error('PRIVATE_DIAGNOSTIC_ERROR');}}:env;
    const seen=[],handler=wrap(module,createEdgeRuntime({env,fetchImpl}),diagnosticEnv,value=>{
      if(diagnosticFailure==='sink')throw Error('PRIVATE_DIAGNOSTIC_ERROR');seen.push(value);});
    const output=await handler(request());assert.equal(output.status,baseline.status);assert.equal(await output.text(),await baseline.text());
    assert.equal(output.status,503);assert.equal(backend,0);if(diagnosticFailure==='none'){
      assert.equal(seen[0].supabaseUrlClass,'exact_project_http');assert.equal(seen[0].serviceRoleShape,'opaque_secret_style');}
  }
});
test('actual schedule denial and every unsigned receiver route stay identical to V5 without backend/fault responses',async()=>{
  const env={SUPABASE_URL:configured,SUPABASE_SERVICE_ROLE_KEY:fixtureJwt};let backend=0;
  const forbidden=()=>{backend++;throw Error('NETWORK_NOT_ALLOWED');};
  const options={env,fetchImpl:forbidden,controlFactory:()=>({}),edgeRpcFactory:()=>forbidden};
  const baseline=await createBeforeRuntime(options)(request()),runtime=wrap(await freshModule(),createEdgeRuntime(options),env,()=>{});
  const after=await runtime(request());assert.equal(after.status,403);assert.equal(await after.text(),await baseline.text());
  const receiver=wrap(await freshModule(),createEdgeReceiver({env,fetchImpl:forbidden}),env,()=>{},'receiver');
  const before=createBeforeReceiver({env,fetchImpl:forbidden});
  for(const route of ['accept','redirect','timeout','reject']){
    const make=()=>new Request(http+'/wave5-receiver/'+route,{method:'POST',headers:{'content-type':'application/json'},body:'{}'});
    const original=await before(make()),output=await receiver(make());assert.equal(output.status,original.status);
    assert.equal(await output.text(),await original.text());assert.equal(output.status,403);assert.equal(output.headers.has('location'),false);
  }assert.equal(backend,0);
});
test('V5 route bytes and every authenticated handler body are exact prefix/import-only predecessors',async()=>{
  const path=name=>new URL('../../../../'+name,import.meta.url);
  const original=await fs.readFile(path('workers/wave5/edge_route_20261014_r5_v5.mjs'));
  const successor=await fs.readFile(path('workers/wave5/edge_route_20261014_r5_v6.mjs'));
  assert.ok(successor.subarray(0,original.length).equals(original));assert.equal(edgeRoute.toString(),beforeRoute.toString());
  for(const role of ['runtime','receiver']){
    const before=await fs.readFile(path(`workers/wave5/edge_${role}_20261014_r5_v5.mjs`),'utf8');
    const after=await fs.readFile(path(`workers/wave5/edge_${role}_20261014_r5_v6.mjs`),'utf8');
    assert.equal(after,before.replace('./edge_route_20261014_r5_v5.mjs','./edge_route_20261014_r5_v6.mjs'));
  }
});
test('the full accepted/denied routing matrix is unchanged and aliases/forwarded fields remain untrusted',()=>{
  const variants=['https://xpdoufauvrbdmxgngetv.supabase.co','http://xpdoufauvrbdmxgngetv.supabase.co','https://edge-runtime.supabase.com',
    'http://edge-runtime.supabase.com','http://127.0.0.1','http://xpdoufauvrbdmxgngetv.supabase.co.other.invalid'];
  for(const worker of ['runtime','receiver']){
    const routes=worker==='runtime'?['/schedule','/external/forecast','/model/suggestion']:['/accept','/redirect','/timeout','/reject'];
    const endpoint=configured+'/functions/v1/wave5-'+worker;
    for(const origin of variants)for(const prefix of ['/functions/v1/wave5-'+worker,'/wave5-'+worker])for(const route of routes)
      for(const suffix of ['','?PRIVATE','#PRIVATE','/extra'])assert.equal(edgeRoute(origin+prefix+route+suffix,endpoint,routes),beforeRoute(origin+prefix+route+suffix,endpoint,routes));
  }
});
test('both new entrypoints install exactly one provider diagnostic without the old ingress wrapper or added startup env reads',async()=>{
  for(const worker of ['runtime','receiver']){
    const source=await fs.readFile(new URL(`../../../../supabase/functions/wave5-${worker}/index_20261014_r5_v6.ts`,import.meta.url),'utf8');
    assert.equal(source.match(/Deno\.serve\(/g)?.length,1);assert.equal(source.match(/withBoundedProviderDiagnostic\(\{/g)?.length,1);
    assert.equal(source.includes('withBoundedIngressDiagnostic'),false);assert.equal(source.includes('Deno.env.get'),false);
    assert.equal(source.includes('configuredUrl:edgeConfiguration.url'),true);
  }
});
