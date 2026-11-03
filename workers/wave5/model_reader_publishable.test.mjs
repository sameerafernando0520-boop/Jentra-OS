import test from 'node:test';
import assert from 'node:assert/strict';
import {AuthenticatedForecastReader} from './model_reader.mjs';
import {createWorkerRpc} from './persistent_control.mjs';

const url='https://example.supabase.co',publishable='sb_publishable_'+'p'.repeat(40);
const legacy='a'.repeat(40)+'.'+'b'.repeat(40)+'.'+'c'.repeat(40),caller='user_session_'.repeat(5);
const request={sourceId:'00000000-0000-4000-8000-000000000001',scope:{tenantId:'00000000-0000-4000-8000-000000000002',legalEntityId:'00000000-0000-4000-8000-000000000003',branchId:'00000000-0000-4000-8000-000000000004'}};
const evidence={sourceId:request.sourceId,sourceHash:'a'.repeat(64),scope:request.scope};
function fixture(key=publishable){
 const calls=[];
 const reader=new AuthenticatedForecastReader({url,publishableKey:key,accessToken:caller,fetchImpl:async(target,options)=>{calls.push({url:String(target),...options});return new Response(JSON.stringify(evidence));}});
 return {reader,calls};
}
test('publishable-key forecast reads and reauthorizes with only the caller bearer',async()=>{
 const {reader,calls}=fixture();assert.deepEqual(await reader.forecast(request),evidence);await reader.authorize(request,evidence);
 assert.equal(calls.length,2);
 for(const c of calls){
  assert.equal(c.url,url+'/rest/v1/rpc/get_ai_forecast_evidence');assert.equal(c.method,'POST');assert.equal(c.redirect,'error');
  assert.equal(c.headers.apikey,publishable);assert.equal(c.headers.authorization,'Bearer '+caller);
  assert.equal(c.headers['content-profile'],'api');assert.equal(c.headers['accept-profile'],'api');
  assert.deepEqual(JSON.parse(c.body),{p_tenant_id:request.scope.tenantId,p_legal_entity_id:request.scope.legalEntityId,p_branch_id:request.scope.branchId,p_forecast_id:request.sourceId});
 }
});
test('legacy anon format retains the same caller-scoped forecast behavior',async()=>{
 const {reader,calls}=fixture(legacy);await reader.forecast(request);
 assert.equal(calls[0].headers.apikey,legacy);assert.equal(calls[0].headers.authorization,'Bearer '+caller);
});
test('publishable credentials remain rejected by the privileged worker transport',()=>{
 assert.throws(()=>createWorkerRpc({url,serviceKey:publishable}),/WORKER_CONFIGURATION_INVALID/);
});
test('caller transport rejects opaque secret keys and malformed public keys before I/O',()=>{
 let calls=0;
 for(const key of ['sb_secret_'+'s'.repeat(40),'sb_publishable_'+'p'.repeat(40)+'\r\nextra','not_a_valid_key'.repeat(4)]){
  assert.throws(()=>new AuthenticatedForecastReader({url,publishableKey:key,accessToken:caller,fetchImpl:()=>{calls++;}}),/WORKER_CONFIGURATION_INVALID/);
 }
 assert.equal(calls,0);
});
test('caller transport rejects missing or header-injection tokens before I/O',()=>{
 let calls=0;
 for(const token of [undefined,'short',caller+'\r\nextra'])assert.throws(()=>new AuthenticatedForecastReader({url,publishableKey:legacy,accessToken:token,fetchImpl:()=>{calls++;}}),/AUTH_REQUIRED/);
 assert.equal(calls,0);
});
test('backend denials stay denials and do not expose response content',async()=>{
 for(const status of [401,403,400,503]){
  const reader=new AuthenticatedForecastReader({url,publishableKey:legacy,accessToken:caller,fetchImpl:async()=>new Response('private database response',{status})});
  await assert.rejects(reader.forecast(request),new RegExp(status===401||status===403?'^Error: WORKER_ACCESS_DENIED$':'^Error: WORKER_PROVIDER_UNAVAILABLE$'));
 }
});
