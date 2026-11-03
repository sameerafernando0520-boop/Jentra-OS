import test from 'node:test';
import assert from 'node:assert/strict';
import {createRpcFailureDiagnosticFetch} from './rpc_failure_diagnostics.mjs';

const url='https://example.supabase.co',rpc=url+'/rest/v1/rpc/wave5_runtime_worker';
test('successful RPC is passed through once without a diagnostic',async()=>{
 const response=new Response('{"ready":true}'),events=[];let sends=0;
 const observed=createRpcFailureDiagnosticFetch({url,fetchImpl:async()=>{sends++;return response;},emit:e=>events.push(e)});
 assert.equal(await observed(rpc),response);assert.equal(sends,1);assert.deepEqual(events,[]);
});
test('failed RPC emits only reviewed metadata and preserves its response',async()=>{
 const body=JSON.stringify({code:'23514',message:'private SQL content',details:'private caller'}),response=new Response(body,{status:400}),events=[];
 let sends=0;
 const observed=createRpcFailureDiagnosticFetch({url,fetchImpl:async()=>{sends++;return response;},emit:e=>events.push(e)});
 const result=await observed(rpc,{headers:{authorization:'Bearer private'},body:'private payload'});
 assert.equal(result,response);assert.equal(await result.text(),body);assert.equal(sends,1);
 assert.deepEqual(events,[{event:'wave5_rpc_failure',rpc:'wave5_runtime_worker',stage:'response',status:400,code:'23514'}]);
 assert.ok(!JSON.stringify(events).includes('private'));
});
test('transport failure preserves original error without logging its message',async()=>{
 const failure=new TypeError('private token in error'),events=[];let sends=0;
 const observed=createRpcFailureDiagnosticFetch({url,fetchImpl:async()=>{sends++;throw failure;},emit:e=>events.push(e)});
 await assert.rejects(observed(rpc),error=>error===failure);assert.equal(sends,1);
 assert.deepEqual(events,[{event:'wave5_rpc_failure',rpc:'wave5_runtime_worker',stage:'transport',errorKind:'TypeError'}]);
});
test('provider and unrecognized RPC responses emit no diagnostic',async()=>{
 const events=[];let sends=0;
 const observed=createRpcFailureDiagnosticFetch({url,fetchImpl:async()=>{sends++;return new Response('{}',{status:503});},emit:e=>events.push(e)});
 await observed('https://api.cloudflare.com/client/v4/private');await observed(url+'/rest/v1/rpc/private_function');
 assert.equal(sends,2);assert.deepEqual(events,[]);
});
test('diagnostic consumer failure cannot change the original HTTP result',async()=>{
 const response=new Response('{"code":"PGRST202"}',{status:404});
 const observed=createRpcFailureDiagnosticFetch({url,fetchImpl:async()=>response,emit:()=>{throw Error('logging unavailable');}});
 assert.equal(await observed(rpc),response);assert.equal(await response.text(),'{"code":"PGRST202"}');
});
test('unrecognized machine codes and oversized response content are not emitted',async()=>{
 const events=[],responses=[new Response('{"code":"private message"}',{status:500}),new Response('x'.repeat(5000),{status:500})];
 const observed=createRpcFailureDiagnosticFetch({url,fetchImpl:async()=>responses.shift(),emit:e=>events.push(e)});
 await observed(rpc);await observed(rpc);
 assert.equal(events.length,2);assert.ok(events.every(e=>e.code===null));assert.ok(!JSON.stringify(events).includes('private'));
});
