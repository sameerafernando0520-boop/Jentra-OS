import test from 'node:test';import assert from 'node:assert/strict';
import {createExternalCommandHandler,createReviewedModelHandler} from './worker_endpoints.mjs';
import {runSyntheticSubscriptionBatch} from './subscription_schedule.mjs';
const id=i=>`10000000-0000-0000-0000-${String(i).padStart(12,'0')}`;
function req(body,token='x'.repeat(40)){return new Request('https://worker.jentra.test',{method:'POST',headers:{'content-type':'application/json','authorization':`Bearer ${token}`},body:JSON.stringify(body)});}
test('external endpoint rejects arbitrary dispatch and does not leak provider diagnostics',async()=>{
 let invoked=false;const control={readiness:async()=>{invoked=true;return {contractRevision:1,ready:true,providers:{'external_forecast.v1':1}};}};
 const result=await createExternalCommandHandler({control})(req({commandCode:'execute_sql',sql:'private'}));
 assert.equal(result.status,400);assert.equal(invoked,true);assert.equal((await result.text()).includes('private'),false);
 const rejected=await createExternalCommandHandler({control})(req({},'invalid'));assert.equal(rejected.status,403);
});
test('unreviewed model endpoint cannot retrieve a caller source or invoke a provider',async()=>{
 let invoked=false;const handle=createReviewedModelHandler({policy:{revision:1,approved:false},provider:{generate(){invoked=true;}}});
 assert.equal((await handle(req({}))).status,503);assert.equal(invoked,false);
});
test('model endpoint binds only the request caller and rejects extra private payload fields',async()=>{
 let seen;const handle=createReviewedModelHandler({control:{},provider:{},policy:{revision:1,approved:true},readerFactory:token=>{seen=token;return {forecast:async()=>{throw Error('private diagnostic');}};}});
 const payload={sourceId:id(1),scope:{tenantId:id(2),legalEntityId:id(3),branchId:null},invocationId:id(4),usageEventId:id(5),maxTokens:'20',periodStart:'2026-10-01T00:00:00Z',periodEnd:'2026-11-01T00:00:00Z'};
 const result=await handle(req(payload));assert.equal(seen,'x'.repeat(40));assert.equal(result.status,503);assert.equal((await result.text()).includes('private'),false);
 assert.equal((await handle(req({...payload,email:'private'}))).status,400);
});
test('synthetic subscription scan is bounded and resumes original revision after a stopped batch',async()=>{
 const seen=[],control={dueSyntheticSubscriptions:async()=>({contractRevision:1,items:[{tenantId:id(1),revisionId:id(2)},{tenantId:id(1),revisionId:id(3)}],nextCursor:null}),
  readiness:async()=>({contractRevision:1,ready:true,providers:{'synthetic_subscription.v1':1}}),applySyntheticSubscription:async(t,r)=>seen.push([t,r])};
 const result=await runSyntheticSubscriptionBatch({control,limit:1});assert.deepEqual(seen,[[id(1),id(2)]]);assert.equal(result.nextCursor,id(2));
});
