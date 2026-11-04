import test from 'node:test';
import assert from 'node:assert/strict';
import {createReviewedModelHandler} from './worker_endpoints.mjs';
import {createEdgeRuntime} from './edge_runtime.mjs';
import {freeAiConfiguration} from './free_ai_configuration.mjs';
const token='x'.repeat(40);
test('invalid input reports only caller-key kind and fixed error enums',async()=>{
 const events=[];
 const handler=createReviewedModelHandler({control:{},provider:{},policy:{approved:true,revision:1},url:'https://example.supabase.co',publishableKey:'sb_publishable_privatevalue',reportFailure:e=>events.push(e)});
 const response=await handler(new Request('https://worker.example/model',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:'{}'}));
 assert.equal(response.status,400);assert.deepEqual(await response.json(),{code:'VALIDATION_ERROR'});
 assert.equal(events[0].event,'wave5_model_handler_failure');assert.equal(events[0].callerKeyKind,'opaque_publishable');assert.equal(events[0].code,'VALIDATION_ERROR');assert.equal(events[0].stage,'request.validate');
 assert.ok(!JSON.stringify(events).includes('privatevalue'));
});
test('reader construction failure reports a safe source frame without private text',async()=>{
 const events=[],error=new TypeError('private credential value');error.stack='TypeError: private credential value\n at file:///private/path/model_reader.mjs:17:2';
 const request={sourceId:'00000000-0000-4000-8000-000000000001',scope:{tenantId:'00000000-0000-4000-8000-000000000002',legalEntityId:'00000000-0000-4000-8000-000000000003',branchId:null},invocationId:'00000000-0000-4000-8000-000000000004',usageEventId:'00000000-0000-4000-8000-000000000005',maxTokens:'2000',periodStart:'2026-11-02T00:00:00Z',periodEnd:'2026-11-02T00:30:00Z'};
 const handler=createReviewedModelHandler({control:{},provider:{},policy:{approved:true,revision:1},publishableKey:'sb_publishable_privatevalue',readerFactory:()=>{throw error;},reportFailure:e=>events.push(e)});
 const response=await handler(new Request('https://worker.example/model',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(request)}));
 assert.equal(response.status,503);assert.deepEqual(await response.json(),{code:'WORKER_PROVIDER_UNAVAILABLE'});
 assert.deepEqual(events,[{event:'wave5_model_handler_failure',callerKeyKind:'opaque_publishable',stage:'reader.create',frame:'model_reader.mjs:17:2',code:'OTHER',errorKind:'TypeError'}]);
 assert.ok(!JSON.stringify(events).includes('private'));
});
test('failed diagnostic consumer leaves ordinary denial unchanged',async()=>{
 const handler=createReviewedModelHandler({control:{},provider:{},policy:{approved:true,revision:1},reportFailure:()=>{throw Error('logger unavailable');}});
 const response=await handler(new Request('https://worker.example/model',{method:'POST'}));
 assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'AUTH_REQUIRED'});
});
test('initialization failure reports only credential kinds and fixed enums',async()=>{
 const events=[];let sends=0;
 const handler=createEdgeRuntime({env:{SUPABASE_URL:freeAiConfiguration.url,SUPABASE_SERVICE_ROLE_KEY:'private'.repeat(10),SUPABASE_ANON_KEY:'sb_publishable_privatevalue'},fetchImpl:()=>{sends++;throw Error('NO_IO_ALLOWED');},reportFailure:e=>events.push(e)});
 const response=await handler(new Request(freeAiConfiguration.workerUrl+'/model/suggestion',{method:'POST',body:'{}'}));
 assert.equal(response.status,503);assert.equal(sends,0);
 assert.deepEqual(events,[{event:'wave5_edge_failure',stage:'edge.initialize',urlMatchesConfigured:true,serviceKeyKind:'unsupported',callerKeyKind:'opaque_publishable',code:'WORKER_PROVIDER_UNAVAILABLE',errorKind:'Error'}]);
 assert.ok(!JSON.stringify(events).includes('private'));
});
