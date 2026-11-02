import test from 'node:test';
import assert from 'node:assert/strict';
import {CloudflareFreeProvider} from './cloudflare_model_adapter.mjs';

const accountId='a'.repeat(32),apiToken='x'.repeat(40);
const model='@cf/meta/llama-3.3-70b-instruct-fp8-fast';
const review={approved:true,revision:1,provider:'cloudflare.workers-ai.free.v1',model,freeOnly:true,paidFallback:false,maxTokensPerInvocation:'2000'};
const evidence={policyVersion:1,projection:'pipeline.current_weighted.v1',sourceId:'10000000-0000-0000-0000-000000000001',
 sourceHash:'a'.repeat(64),scope:{tenantId:'20000000-0000-0000-0000-000000000001',legalEntityId:'20000000-0000-0000-0000-000000000002',branchId:null},
 currencies:[{currency:'LKR',population:3,amount:'123.450000',weightedAmount:'100.000000'}],horizonStart:'2026-11-01',horizonEnd:'2026-12-01'};
const suggestion={commandCode:'analytics.freeze_pipeline.v1',sourceId:evidence.sourceId,sourceHash:evidence.sourceHash,
 horizonStart:evidence.horizonStart,horizonEnd:evidence.horizonEnd};
const success=(response=suggestion,usage={prompt_tokens:180,completion_tokens:100,total_tokens:280})=>new Response(JSON.stringify({success:true,errors:[],messages:[],result:{response,usage}}));

test('free provider sends only proposal references to its fixed account and settles exact provider tokens',async()=>{
 const calls=[];
 const provider=new CloudflareFreeProvider({accountId,apiToken,review,fetchImpl:async(url,options)=>{calls.push({url,options});return success();}});
 assert.deepEqual(await provider.generate({evidence,maxTokens:'2000'}),{tokens:'280',suggestion});
 assert.equal(calls.length,1);
 assert.equal(calls[0].url,`https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/${model}`);
 assert.equal(calls[0].options.redirect,'error');
 assert.equal(calls[0].options.headers.authorization,`Bearer ${apiToken}`);
 const body=JSON.parse(calls[0].options.body);
 assert.equal(body.raw,true);assert.equal(body.stream,false);assert.equal(body.temperature,0);
 assert.equal(body.response_format.type,'json_schema');
 assert.deepEqual(body.response_format.json_schema.properties.sourceHash.enum,[evidence.sourceHash]);
 assert.equal(Object.hasOwn(body,'tools'),false);
 assert.equal(body.prompt.includes('123.450000'),false);
 assert.equal(body.prompt.includes(evidence.scope.tenantId),false);
 assert.equal(body.prompt.includes(evidence.sourceHash),true);
 assert.ok(body.max_tokens>=256&&body.max_tokens<=512);
 assert.equal(provider.trustedUsage,true);assert.equal(provider.policyRevision,1);
 assert.equal(JSON.stringify(provider).includes(apiToken),false);
});

test('constructed free provider cannot be retargeted to another model or account',async()=>{
 const targets=[],mutableReview={...review};
 const provider=new CloudflareFreeProvider({accountId,apiToken,review:mutableReview,fetchImpl:async url=>{targets.push(url);return success();}});
 mutableReview.model='@cf/moonshotai/kimi-k2.7-code';
 assert.throws(()=>{provider.review={...review,model:mutableReview.model};},TypeError);
 assert.throws(()=>{provider.accountId='b'.repeat(32);},TypeError);
 await provider.generate({evidence,maxTokens:'2000'});
 assert.deepEqual(targets,[`https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/${model}`]);
});

test('unapproved providers, paid options and malformed credentials are rejected before transport',()=>{
 for(const change of [{review:{...review,approved:false}},{review:{...review,freeOnly:false}},
  {review:{...review,paidFallback:true}},{review:{...review,model:'@cf/moonshotai/kimi-k2.7-code'}},
  {review:{...review,provider:'openai.responses.v1'}},{review:{...review,maxTokensPerInvocation:'9999'}},
  {accountId:'a'.repeat(31)},{accountId:'a'.repeat(32)+'/other'},{apiToken:'short'},{apiToken:apiToken+'\n'}]){
  assert.throws(()=>new CloudflareFreeProvider({accountId,apiToken,review,...change}),/MODEL_PROVIDER_UNAVAILABLE/);
 }
});

test('invalid input or insufficient reserved tokens cannot issue a provider call',async()=>{
 let calls=0;
 const provider=new CloudflareFreeProvider({accountId,apiToken,review,fetchImpl:async()=>{calls++;return success();}});
 for(const maxTokens of ['0','100','2001','9999999999999999',2000])
  await assert.rejects(provider.generate({evidence,maxTokens}),/MODEL_INPUT_LIMIT/);
 for(const change of [{sourceId:'unreviewed text'},{sourceHash:'bad'},{horizonStart:'2026-02-30'},
  {horizonEnd:evidence.horizonStart},{horizonEnd:'2028-01-01'}])
  await assert.rejects(provider.generate({evidence:{...evidence,...change},maxTokens:'2000'}),/MODEL_CONTRACT_MISMATCH/);
 assert.equal(calls,0);
});

test('quota exhaustion, provider errors and redirects never retry or select another origin',async()=>{
 for(const [status,code] of [[429,'MODEL_FREE_QUOTA_EXCEEDED'],[503,'MODEL_PROVIDER_UNAVAILABLE'],[302,'MODEL_PROVIDER_UNAVAILABLE']]){
  let calls=0;
  const provider=new CloudflareFreeProvider({accountId,apiToken,review,fetchImpl:async(url,options)=>{
   calls++;assert.equal(url,`https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/${model}`);
   assert.equal(options.redirect,'error');return new Response('PRIVATE_PROVIDER_DIAGNOSTIC',{status,headers:{location:'https://paid.invalid'}});
  }});
  await assert.rejects(provider.generate({evidence,maxTokens:'2000'}),new RegExp('^Error: '+code+'$'));
  assert.equal(calls,1);
 }
});

test('missing, inconsistent, unsafe and out-of-budget provider token counts cannot settle',async()=>{
 for(const usage of [undefined,{prompt_tokens:180,completion_tokens:100,total_tokens:281},
  {prompt_tokens:180,completion_tokens:0,total_tokens:180},{prompt_tokens:-1,completion_tokens:1,total_tokens:0},
  {prompt_tokens:1900,completion_tokens:100,total_tokens:2000},{prompt_tokens:180,completion_tokens:513,total_tokens:693},
  {prompt_tokens:Number.MAX_SAFE_INTEGER+1,completion_tokens:100,total_tokens:Number.MAX_SAFE_INTEGER+101}]){
  const provider=new CloudflareFreeProvider({accountId,apiToken,review,fetchImpl:async()=>new Response(JSON.stringify({
   success:true,errors:[],result:{response:suggestion,usage}}))});
  await assert.rejects(provider.generate({evidence,maxTokens:'2000'}),/TRUSTED_USAGE_MISMATCH/);
 }
});

test('malformed envelopes, tools and changed proposal references are rejected',async()=>{
 const usage={prompt_tokens:180,completion_tokens:100,total_tokens:280};
 for(const envelope of [{success:false,errors:[],result:{response:suggestion,usage}},
  {success:true,errors:[{code:1}],result:{response:suggestion,usage}},
  {success:true,errors:[],result:{response:suggestion,usage,tool_calls:[{name:'execute'}]}},
  {success:true,errors:[],result:{response:{...suggestion,sourceHash:'b'.repeat(64)},usage}},
  {success:true,errors:[],result:{response:{...suggestion,extra:'execute'},usage}},
  {success:true,errors:[],result:{response:'not JSON',usage}},
  {success:true,errors:[],result:{response:'x'.repeat(8193),usage}}]){
  const provider=new CloudflareFreeProvider({accountId,apiToken,review,fetchImpl:async()=>new Response(JSON.stringify(envelope))});
  await assert.rejects(provider.generate({evidence,maxTokens:'2000'}));
 }
 const provider=new CloudflareFreeProvider({accountId,apiToken,review,fetchImpl:async()=>success(JSON.stringify(suggestion))});
 assert.deepEqual(await provider.generate({evidence,maxTokens:'2000'}),{tokens:'280',suggestion});
});

test('oversized provider bodies are cancelled while streaming',async()=>{
 let cancelled=false;
 const response={ok:true,body:new ReadableStream({start(controller){controller.enqueue(new Uint8Array(65537));},cancel(){cancelled=true;}})};
 const provider=new CloudflareFreeProvider({accountId,apiToken,review,fetchImpl:async()=>response});
 await assert.rejects(provider.generate({evidence,maxTokens:'2000'}),/WORKER_OUTPUT_LIMIT/);
 assert.equal(cancelled,true);
});
