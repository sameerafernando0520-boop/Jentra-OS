import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {edgeRoute,classifyEdgeIngress,withBoundedIngressDiagnostic} from './edge_route_20261014_r5_v4.mjs';
import {edgeRoute as oldRoute} from './edge_route_20261013_r5_v3.mjs';
const endpoint='https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime',routes=['/schedule','/external/forecast','/model/suggestion'];
test('HTTP platform is classified exactly and remains denied by the diagnostic-only revision',()=>{
 const url='http://edge-runtime.supabase.com/wave5-runtime/schedule';
 assert.deepEqual(classifyEdgeIngress(url,endpoint,routes),{originClass:'platform_runtime_http',pathClass:'function_namespace',hostnameClass:'platform_host',portClass:'default',https:false,query:false,hash:false,userinfo:false,routeRecognized:false});
 assert.equal(edgeRoute(url,endpoint,routes),null);
});
test('finite classes separate lookalikes, ports, credentials and malformed requests without logging values',()=>{
 for(const url of ['http://PRIVATE_FIXTURE.invalid:7777/wave5-runtime/schedule','http://edge-runtime.supabase.com.other.invalid/wave5-runtime/schedule','http://PRIVATE_SECRET@edge-runtime.supabase.com/wave5-runtime/schedule?PRIVATE_BODY#PRIVATE_FRAGMENT','PRIVATE_INVALID']){
  const d=classifyEdgeIngress(url,endpoint,routes);assert.equal(edgeRoute(url,endpoint,routes),null);assert.equal(/PRIVATE_/.test(JSON.stringify(d)),false);
  for(const v of Object.values(d))assert.ok(typeof v==='boolean'||['invalid','platform_runtime_http','platform_runtime','public_project','other','function_namespace','public_function','platform_host','project_host','default'].includes(v));
 }
});
test('v4 keeps every v3 allowed or rejected route outcome unchanged',()=>{
 const origins=['https://xpdoufauvrbdmxgngetv.supabase.co','https://edge-runtime.supabase.com','http://edge-runtime.supabase.com','https://other.invalid'];
 const paths=['/functions/v1/wave5-runtime/schedule','/wave5-runtime/schedule','/wave5-runtime/model/suggestion','/wave5-runtime/unknown','/wave5-receiver/accept'];
 for(const o of origins)for(const p of paths)for(const suffix of ['','?','#','/extra'])assert.equal(edgeRoute(o+p+suffix,endpoint,routes),oldRoute(o+p+suffix,endpoint,routes));
});
test('one finite diagnostic is emitted across concurrent handlers without accessing private request fields',async()=>{
 const seen=[],req={url:'http://edge-runtime.supabase.com/wave5-runtime/schedule'};
 for(const k of ['headers','body','method'])Object.defineProperty(req,k,{get(){throw Error('PRIVATE_FIELDS_NOT_ALLOWED');}});
 let calls=0;const wrapped=withBoundedIngressDiagnostic({handler:()=>{calls++;return 404;},endpointUrl:endpoint,allowedRoutes:routes,worker:'runtime',observe:d=>seen.push(d)});
 assert.deepEqual(await Promise.all(Array.from({length:32},()=>wrapped(req))),Array(32).fill(404));assert.equal(calls,32);assert.equal(seen.length,1);assert.equal(seen[0].kind,'wave5_ingress_v4');assert.equal(seen[0].routeRecognized,false);
 assert.deepEqual(Object.keys(seen[0]),['kind','worker','originClass','pathClass','hostnameClass','portClass','https','query','hash','userinfo','routeRecognized']);
});
test('sink failure leaves the authenticated handler and its return unchanged',()=>{
 let calls=0,observations=0;const wrapped=withBoundedIngressDiagnostic({handler:()=>{calls++;return 403;},endpointUrl:endpoint,allowedRoutes:routes,worker:'runtime',observe:()=>{observations++;throw Error('DIAGNOSTIC_SINK_FAILED');}});
 assert.equal(wrapped({url:'invalid'}),403);assert.equal(wrapped({url:endpoint+'/schedule'}),403);assert.equal(calls,2);assert.equal(observations,1);
});
test('both v4 factories preserve the full v3 handler source except for the route import',async()=>{
 for(const role of ['runtime','receiver']){
  const old=await fs.readFile(new URL(`./edge_${role}_20261013_r5_v3.mjs`,import.meta.url),'utf8'),current=await fs.readFile(new URL(`./edge_${role}_20261014_r5_v4.mjs`,import.meta.url),'utf8');
  assert.equal(current,old.replace('./edge_route_20261013_r5_v3.mjs','./edge_route_20261014_r5_v4.mjs'));
 }
});
