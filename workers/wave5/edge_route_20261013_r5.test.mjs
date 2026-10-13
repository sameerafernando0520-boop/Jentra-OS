import test from 'node:test';
import assert from 'node:assert/strict';
import {edgeRoute} from './edge_route_20261013_r5.mjs';
import {createEdgeRuntime} from './edge_runtime_20261013_r5.mjs';
import {createEdgeReceiver} from './edge_receiver_20261013_r5.mjs';
import {edgeConfiguration as config} from './edge_configuration.mjs';
test('gateway and documented in-function namespaces select the same exact route',()=>{
 for(const route of ['/schedule','/external/forecast','/model/suggestion']){
  assert.equal(edgeRoute(config.workerUrl+route,config.workerUrl,[route]),route);
  assert.equal(edgeRoute(config.workerUrl.replace('/functions/v1/','/')+route,config.workerUrl,[route]),route);
 }
});
test('unreviewed hosts, namespaces, routes, queries and fragments remain rejected',()=>{
 const urls=['https://other.invalid/wave5-runtime/schedule','http://xpdoufauvrbdmxgngetv.supabase.co/wave5-runtime/schedule',
  config.url+'/wave5-runtimex/schedule',config.url+'/schedule',config.url+'/wave5-runtime/schedule/extra',
  config.url+'/wave5-runtime/schedule?x=1',config.url+'/wave5-runtime/schedule#x',
  config.url+'/wave5-runtime/%73chedule',config.url+'/wave5-runtime//schedule'];
 for(const url of urls)assert.equal(edgeRoute(url,config.workerUrl,['/schedule']),null,url);
});
test('documented platform paths reach auth denial before credentials or backend effects',async()=>{
 let privateReads=0,effects=0;const env={get(){privateReads++;throw Error('PRIVATE_READ_FORBIDDEN');}};
 const runtime=createEdgeRuntime({env,edgeRpcFactory:()=>{effects++;}});
 const receiver=createEdgeReceiver({env,rpcFactory:()=>{effects++;}});
 // Runtime requires its platform variables before checking the schedule secret,
 // but a bad route must never read them; receiver checks signed headers first.
 assert.equal((await runtime(new Request(config.url+'/wave5-runtime/unknown',{method:'POST'}))).status,404);
 assert.equal((await receiver(new Request(config.url+'/wave5-receiver/accept',{method:'POST'}))).status,403);
 assert.equal(privateReads,0);assert.equal(effects,0);
});
