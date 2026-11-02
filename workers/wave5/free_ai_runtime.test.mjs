import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createEdgeRuntime} from './edge_runtime.mjs';
import {edgeConfiguration as bindings} from './edge_configuration.mjs';
import {redactForecastEvidence} from './model_runtime.mjs';

const id='10000000-0000-0000-0000-000000000001';
const legacyAnon='a'.repeat(40)+'.'+'b'.repeat(40)+'.'+'c'.repeat(40);
const env={SUPABASE_URL:bindings.url,SUPABASE_SERVICE_ROLE_KEY:'sb_secret_'+'s'.repeat(40),SUPABASE_ANON_KEY:legacyAnon};
const accountId='a'.repeat(32),apiToken='x'.repeat(40),token='u'.repeat(40)+'.'+'v'.repeat(40)+'.'+'w'.repeat(40);
const configured={...env,W5_CLOUDFLARE_ACCOUNT_ID:accountId,W5_CLOUDFLARE_API_TOKEN:apiToken};
const request=(body={},token)=>new Request(bindings.workerUrl+'/model/suggestion',{method:'POST',
 headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});

test('canonical worker never falls back to a configured paid OpenAI key',async()=>{
 let providerCalls=0;
 const runtime=createEdgeRuntime({env:{...env,W5_OPENAI_API_KEY:'x'.repeat(40)},controlFactory:()=>({}),edgeRpcFactory:()=>()=>{},
  providerFactory:()=>{providerCalls++;throw Error('PAID_FALLBACK_MUST_NOT_BE_CREATED');}});
 const result=await runtime(request());
 assert.equal(result.status,503);assert.deepEqual(await result.json(),{code:'MODEL_PROVIDER_UNAVAILABLE'});
 assert.equal(providerCalls,0);
});

const scope={tenantId:id,legalEntityId:'20000000-0000-0000-0000-000000000002',branchId:null};
const evidence={contractRevision:1,modelProvider:'unavailable',sourceId:id,sourceHash:'a'.repeat(64),scope,
 currencies:[{currency:'LKR',population:3,amount:'123.450000',weightedAmount:'100.000000'}],horizonStart:'2026-11-01',horizonEnd:'2026-12-01'};
const suggestion={commandCode:'analytics.freeze_pipeline.v1',sourceId:id,sourceHash:evidence.sourceHash,
 horizonStart:evidence.horizonStart,horizonEnd:evidence.horizonEnd};
const body={sourceId:id,scope,invocationId:'30000000-0000-0000-0000-000000000003',usageEventId:'40000000-0000-0000-0000-000000000004',
 maxTokens:'2000',periodStart:'2026-11-01T00:00:00Z',periodEnd:'2026-12-01T00:00:00Z'};

function harness({providerStatus=200,revokeAfterResponse=false,legacyManifest}={}){
 const events=[],targets=[];let state=legacyManifest?'settled':'new',saved=legacyManifest?{tokens:'7',suggestion}:undefined,reads=0,manifest=legacyManifest;
 const control={
  beginModelInvocation:async value=>{
   events.push({kind:'begin',value});
   // Stored-request conflicts are IDEMPOTENCY_MISMATCH in SQL; the existing
   // privileged RPC transport sanitizes non-auth failures to this public code.
   if(manifest&&manifest!==value.manifestHash)throw Error('WORKER_PROVIDER_UNAVAILABLE');
   manifest=value.manifestHash;return state==='settled'?{state,...saved}:{state};
  },
  reserveUsage:async value=>events.push({kind:'reserve',value}),
  recordModelOutcome:async(invocationId,value)=>{state=value.state;saved=value;events.push({kind:'outcome',invocationId,value});},
  settleUsage:async value=>events.push({kind:'settle',value}),
 };
 const forAccount=account=>createEdgeRuntime({env:{...configured,W5_CLOUDFLARE_ACCOUNT_ID:account},controlFactory:()=>control,edgeRpcFactory:()=>()=>{},fetchImpl:async(url,options)=>{
  const target=new URL(url);targets.push(target.href);
  if(target.origin===bindings.url){
   assert.equal(target.pathname,'/rest/v1/rpc/get_ai_forecast_evidence');
   assert.equal(options.headers.authorization,`Bearer ${token}`);assert.equal(options.headers.apikey,env.SUPABASE_ANON_KEY);
   reads++;events.push({kind:'authorize',read:reads});
   return Response.json(revokeAfterResponse&&reads===3?{...evidence,sourceHash:'b'.repeat(64)}:evidence);
  }
  assert.equal(target.href,`https://api.cloudflare.com/client/v4/accounts/${account}/ai/run/@cf/meta/llama-3.3-70b-instruct-fp8-fast`);
  assert.equal(options.headers.authorization,`Bearer ${apiToken}`);events.push({kind:'provider'});
  return providerStatus===200?Response.json({success:true,errors:[],result:{response:JSON.stringify(suggestion),
   usage:{prompt_tokens:180,completion_tokens:100,total_tokens:280}}}):new Response('PRIVATE_PROVIDER_ERROR',{status:providerStatus});
 }});
 return {runtime:forAccount(accountId),forAccount,events,targets};
}

test('configured free worker still requires the requesting user before evidence or provider access',async()=>{
 const h=harness(),result=await h.runtime(request(body));
 assert.equal(result.status,403);assert.deepEqual(await result.json(),{code:'AUTH_REQUIRED'});
 assert.deepEqual(h.targets,[]);assert.deepEqual(h.events,[]);
});

test('free hosted entrypoint reserves before inference, settles exact tokens and reopens without another model call',async()=>{
 const h=harness(),result=await h.runtime(request(body,token));
 assert.equal(result.status,200);assert.deepEqual(await result.json(),suggestion);
 assert.deepEqual(h.events.map(event=>event.kind),['authorize','begin','reserve','authorize','provider','outcome','settle','authorize']);
 assert.equal(h.events.find(event=>event.kind==='reserve').value.quantity,'2000');
 const settled=h.events.find(event=>event.kind==='settle').value;
 assert.equal(settled.quantity,'280');assert.equal(settled.eventId,body.usageEventId);assert.equal(settled.invocationId,body.invocationId);
 const reopened=await h.runtime(request(body,token));
 assert.equal(reopened.status,200);assert.deepEqual(await reopened.json(),suggestion);
 assert.equal(h.events.filter(event=>event.kind==='provider').length,1);
});

test('free quota rejection retains the unknown invocation and cannot cause a resend or paid fallback',async()=>{
 const h=harness({providerStatus:429}),result=await h.runtime(request(body,token));
 assert.equal(result.status,503);assert.deepEqual(await result.json(),{code:'MODEL_OUTCOME_UNKNOWN'});
 assert.deepEqual(h.events.find(event=>event.kind==='outcome').value,{state:'unknown'});
 assert.equal(h.events.filter(event=>event.kind==='settle').length,0);
 const reopened=await h.runtime(request(body,token));
 assert.equal(reopened.status,503);assert.deepEqual(await reopened.json(),{code:'MODEL_OUTCOME_REQUIRES_REVIEW'});
 assert.equal(h.events.filter(event=>event.kind==='provider').length,1);
 assert.equal(h.targets.some(target=>target.includes('openai.com')),false);
});

test('changed source authority after settlement cannot return a suggestion',async()=>{
 const h=harness({revokeAfterResponse:true}),result=await h.runtime(request(body,token));
 assert.equal(result.status,403);assert.deepEqual(await result.json(),{code:'SOURCE_AUTHORITY_CHANGED'});
 assert.equal(h.events.filter(event=>event.kind==='provider').length,1);
 assert.equal(h.events.find(event=>event.kind==='settle').value.quantity,'280');
});

test('a historical OpenAI outcome cannot be reopened as a Cloudflare outcome',async()=>{
 const legacyManifest=createHash('sha256').update(JSON.stringify(redactForecastEvidence(evidence)),'utf8').digest('hex');
 const h=harness({legacyManifest}),result=await h.runtime(request(body,token));
 assert.equal(result.status,503);assert.deepEqual(await result.json(),{code:'WORKER_PROVIDER_UNAVAILABLE'});
 assert.equal(h.events.some(event=>['provider','reserve','settle','outcome'].includes(event.kind)),false);
});

test('a settled Cloudflare invocation cannot reopen against a different credential account',async()=>{
 const h=harness();assert.equal((await h.runtime(request(body,token))).status,200);
 const result=await h.forAccount('b'.repeat(32))(request(body,token));
 assert.equal(result.status,503);assert.deepEqual(await result.json(),{code:'WORKER_PROVIDER_UNAVAILABLE'});
 assert.equal(h.events.filter(event=>event.kind==='provider').length,1);
 assert.equal(h.events.filter(event=>event.kind==='settle').length,1);
});

test('deterministically insufficient budgets consume no invocation and can be corrected under the same identity',async()=>{
 for(const maxTokens of ['100','2001']){
  const h=harness(),result=await h.runtime(request({...body,maxTokens},token));
  assert.equal(result.status,400);assert.deepEqual(await result.json(),{code:'MODEL_INPUT_LIMIT'});
  assert.equal(h.events.some(event=>['begin','reserve','provider','outcome','settle'].includes(event.kind)),false);
  assert.equal((await h.runtime(request(body,token))).status,200);
  assert.equal(h.events.filter(event=>event.kind==='provider').length,1);
 }
});
