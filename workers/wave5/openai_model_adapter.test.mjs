import test from 'node:test';import assert from 'node:assert/strict';
import {OpenAIResponsesProvider} from './openai_model_adapter.mjs';
import {readBoundedJson} from './bounded_json.mjs';
import {runDeliverySchedule} from './delivery_schedule.mjs';
const id='10000000-0000-0000-0000-000000000001',evidence={sourceId:id,sourceHash:'a'.repeat(64),horizonStart:'2026-10-01',horizonEnd:'2026-11-01'};
const suggestion={commandCode:'analytics.freeze_pipeline.v1',...evidence};
test('HTTP model adapter counts full input, fixes schema, refuses tools and trusts only provider usage',async()=>{
 const calls=[],p=new OpenAIResponsesProvider({apiKey:'x'.repeat(32),review:{approved:true,revision:1,provider:'openai.responses.v1',model:'reviewed-model'},fetchImpl:async(url,options)=>{
  const body=JSON.parse(options.body);calls.push({url,body});
  return new Response(JSON.stringify(url.endsWith('input_tokens')?{input_tokens:100}:{status:'completed',output:[{type:'message',role:'assistant',content:[{type:'output_text',text:JSON.stringify(suggestion)}]}],usage:{input_tokens:100,output_tokens:50,total_tokens:150}}));}});
 assert.deepEqual(await p.generate({evidence,maxTokens:'1000',invocationId:id}),{tokens:'150',suggestion});
 assert.equal(calls.length,2);assert.equal(calls[1].body.max_output_tokens,900);assert.equal(calls[1].body.store,false);assert.deepEqual(calls[1].body.tools,[]);
 assert.deepEqual(calls[0].body.text,calls[1].body.text);
});
test('unreviewed model and insufficient token budget cannot issue model generation',async()=>{
 assert.throws(()=>new OpenAIResponsesProvider({apiKey:'x'.repeat(32),review:{approved:false}}),/UNAVAILABLE/);
 let calls=0;const p=new OpenAIResponsesProvider({apiKey:'x'.repeat(32),review:{approved:true,revision:1,provider:'openai.responses.v1',model:'reviewed-model'},fetchImpl:async()=>{calls++;return new Response('{"input_tokens":999}');}});
 await assert.rejects(p.generate({evidence,maxTokens:'1000',invocationId:id}),/INPUT_LIMIT/);assert.equal(calls,1);
});
test('RPC/model response limit is enforced while streaming',async()=>{
 let cancelled=false;const response={body:new ReadableStream({start(c){c.enqueue(new Uint8Array(11));},cancel(){cancelled=true;}})};
 await assert.rejects(readBoundedJson(response,10),/OUTPUT_LIMIT/);assert.equal(cancelled,true);
});
test('delivery scheduling serializes batches and wakes on shutdown',async()=>{
 const abort=new AbortController();let active=0,max=0,batches=0;
 const control={async reconcileAcknowledged(){active++;max=Math.max(max,active);await Promise.resolve();active--;},async readiness(){return {contractRevision:1,ready:true,providers:{'committed_webhook.v1':1}};},async claimCommittedDelivery(){return null;}};
 const result=await runDeliverySchedule({control,signal:abort.signal,wait:async()=>{},onResult:async()=>{if(++batches===2)abort.abort();}});
 assert.equal(result.state,'stopped');assert.equal(max,1);assert.equal(batches,2);
});
