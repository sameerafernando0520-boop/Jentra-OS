import test from 'node:test';
import assert from 'node:assert/strict';
const moduleName=process.env.W5_ROUTE_MODULE??'./edge_route_20261014_r5_v5.mjs';
const {edgeRoute,classifyEdgeIngress,withBoundedIngressDiagnostic}=await import(moduleName);
const project='https://xpdoufauvrbdmxgngetv.supabase.co',http='http://xpdoufauvrbdmxgngetv.supabase.co';
const runtime=project+'/functions/v1/wave5-runtime',receiver=project+'/functions/v1/wave5-receiver';
const runtimeRoutes=['/schedule','/external/forecast','/model/suggestion'],receiverRoutes=['/accept','/redirect','/timeout','/reject'];

test('the observed project namespace reaches only the exact existing runtime routes',()=>{
 for(const route of runtimeRoutes)assert.equal(edgeRoute(http+'/wave5-runtime'+route,runtime,runtimeRoutes),route);
});
test('the same exact managed origin admits only the reviewed receiver namespace',()=>{
 for(const route of receiverRoutes)assert.equal(edgeRoute(http+'/wave5-receiver'+route,receiver,receiverRoutes),route);
 assert.equal(edgeRoute(http+'/wave5-runtime/accept',receiver,receiverRoutes),null);
 assert.equal(edgeRoute(http+'/wave5-receiver/schedule',runtime,runtimeRoutes),null);
});
test('HTTP public prefixes, platform hosts, lookalikes, credentials, ports and noncanonical URLs stay denied',()=>{
 const urls=[http+'/functions/v1/wave5-runtime/schedule','http://edge-runtime.supabase.com/wave5-runtime/schedule','http://localhost/wave5-runtime/schedule','http://127.0.0.1/wave5-runtime/schedule',http+':80/wave5-runtime/schedule',http+':81/wave5-runtime/schedule','HTTP://xpdoufauvrbdmxgngetv.supabase.co/wave5-runtime/schedule','http://XPDOUFAUVRBDMXGNGETV.supabase.co/wave5-runtime/schedule','http://xpdoufauvrbdmxgngetv.supabase.co.other.invalid/wave5-runtime/schedule','http://PRIVATE_KEY@xpdoufauvrbdmxgngetv.supabase.co/wave5-runtime/schedule',http+'/wave5-runtime/x/../schedule',http+'/wave5-runtime/%73chedule',http+'/wave5-runtime//schedule'];
 for(const suffix of ['?','#','?PRIVATE_KEY=1','#PRIVATE_KEY','/extra','/'])urls.push(http+'/wave5-runtime/schedule'+suffix);
 for(const url of urls)assert.equal(edgeRoute(url,runtime,runtimeRoutes),null,url);
});
test('endpoint configuration remains canonical public HTTPS, and per-handler route subsets still restrict access',()=>{
 assert.equal(edgeRoute(http+'/wave5-runtime/schedule',http+'/functions/v1/wave5-runtime',runtimeRoutes),null);
 assert.equal(edgeRoute(http+'/wave5-runtime/schedule',runtime+'?',runtimeRoutes),null);
 assert.equal(edgeRoute(http+'/wave5-runtime/model/suggestion',runtime,['/schedule']),null);
 for(const route of runtimeRoutes){assert.equal(edgeRoute(runtime+route,runtime,runtimeRoutes),route);assert.equal(edgeRoute('https://edge-runtime.supabase.com/wave5-runtime'+route,runtime,runtimeRoutes),route);}
});
test('the finite diagnostic proves the exact HTTP project class without raw request data',()=>{
 const tuple=classifyEdgeIngress(http+'/wave5-runtime/schedule',runtime,runtimeRoutes);
 assert.deepEqual(tuple,{originClass:'public_project_http',pathClass:'function_namespace',hostnameClass:'project_host',portClass:'default',https:false,query:false,hash:false,userinfo:false,routeRecognized:true});
 const privateTuple=classifyEdgeIngress('http://PRIVATE_KEY@xpdoufauvrbdmxgngetv.supabase.co/wave5-runtime/schedule?PRIVATE_BODY#PRIVATE_FRAGMENT',runtime,runtimeRoutes);
 assert.equal(privateTuple.routeRecognized,false);assert.equal(JSON.stringify(privateTuple).includes('PRIVATE_'),false);
});
test('a factory emits one finite v5 diagnostic across concurrent calls, and preserves handler authentication results',async()=>{
 const seen=[],req={url:http+'/wave5-runtime/schedule'};
 for(const k of ['headers','body','method'])Object.defineProperty(req,k,{get(){throw Error('PRIVATE_FIELDS_UNEXPECTED');}});
 let calls=0;const wrapped=withBoundedIngressDiagnostic({handler:()=>{calls++;return 403;},endpointUrl:runtime,allowedRoutes:runtimeRoutes,worker:'runtime',observe:x=>seen.push(x)});
 assert.deepEqual(await Promise.all(Array.from({length:32},()=>wrapped(req))),Array(32).fill(403));
 assert.equal(calls,32);assert.equal(seen.length,1);assert.equal(seen[0].kind,'wave5_ingress_v5');assert.equal(seen[0].routeRecognized,true);
});
