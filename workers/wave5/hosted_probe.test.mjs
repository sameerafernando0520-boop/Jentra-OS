import test from 'node:test';
import assert from 'node:assert/strict';
import {probeHostedResponses} from '../../tools/wave5/hosted_probe.mjs';

const codes=['WORKER_ACCESS_DENIED','AUTH_REQUIRED','AUTH_REQUIRED','INTEGRATION_ACCESS_DENIED'];

test('public probe records four fixed credential-free denials and leaves positive gates open',async()=>{
 const journal=[],calls=[];
 const result=await probeHostedResponses({record:async row=>journal.push(row),fetchImpl:async(url,options)=>{
  const index=calls.length;
  assert.equal(journal.at(-1).type,'request-intent');
  assert.equal(journal.at(-1).endpointIndex,index);
  assert.equal(url.protocol,'https:');
  assert.equal(url.hostname,'xpdoufauvrbdmxgngetv.supabase.co');
  assert.equal(options.method,'POST');assert.equal(options.body,'{}');
  assert.equal(options.redirect,'manual');assert.equal(options.credentials,'omit');
  assert.deepEqual(Object.keys(options.headers),['content-type']);
  calls.push(url.href);
  return Response.json({code:codes[index]},{status:403,headers:{'sb-request-id':'00000000-0000-4000-8000-000000000001'}});
 }});
 assert.equal(calls.length,4);assert.equal(journal.length,8);
 assert.equal(result.unsignedAuthenticationVerified,true);
 assert.equal(result.hostedModelResponseVerified,false);
 assert.equal(result.usageAccountingVerified,false);
 assert.equal(result.externalDeliveryVerified,false);
 assert.equal(result.observations[0].requestId,'00000000-0000-4000-8000-000000000001');
 assert.match(result.observations[0].responseSha256,/^[a-f0-9]{64}$/);
});

test('missing model configuration is recorded as unavailable and cannot pass authentication or model readiness',async()=>{
 let index=0;
 const result=await probeHostedResponses({record:async()=>{},fetchImpl:async()=>{
  const n=index++;
  return Response.json({code:n===2?'MODEL_PROVIDER_UNAVAILABLE':codes[n]},{status:n===2?503:403});
 }});
 assert.equal(result.unsignedAuthenticationVerified,false);
 assert.equal(result.observations[2].state,'provider-unavailable');
 assert.equal(result.hostedModelResponseVerified,false);
});

test('redirects, unexpected success and private error details cannot become successful evidence',async()=>{
 const replies=[new Response(null,{status:307,headers:{location:'https://other.invalid'}}),
  Response.json({private:'NEVER_PUBLISH',code:'AUTH_REQUIRED'},{status:403}),
  Response.json({code:'AUTH_REQUIRED'},{status:200}),new Response('NEVER_PUBLISH',{status:503})];
 let calls=0;
 const journal=[];
 const result=await probeHostedResponses({record:async row=>journal.push(row),fetchImpl:async()=>replies[calls++]});
 assert.equal(calls,4);assert.equal(result.unsignedAuthenticationVerified,false);
 assert(result.observations.every(o=>o.state==='unexpected-response'));
 assert.equal(JSON.stringify({result,journal}).includes('NEVER_PUBLISH'),false);
 assert.equal(JSON.stringify(result).includes('other.invalid'),false);
});

test('a failed durable intent prevents dispatch, and a failed result journal prevents the next dispatch',async()=>{
 let calls=0;
 await assert.rejects(probeHostedResponses({record:async()=>{throw Error('DISK_FAILURE');},fetchImpl:async()=>{calls++;}}),/DISK_FAILURE/);
 assert.equal(calls,0);
 let records=0;
 await assert.rejects(probeHostedResponses({record:async()=>{if(++records===2)throw Error('DISK_FAILURE');},fetchImpl:async()=>{
  calls++;return Response.json({code:codes[0]},{status:403});
 }}),/DISK_FAILURE/);
 assert.equal(calls,1);
});

test('transport failures never retry or publish exception details',async()=>{
 let calls=0;
 const result=await probeHostedResponses({record:async()=>{},fetchImpl:async()=>{calls++;throw Error('PRIVATE_TOKEN');}});
 assert.equal(calls,4);
 assert(result.observations.every(o=>o.state==='transport-unconfirmed'));
 assert.equal(JSON.stringify(result).includes('PRIVATE_TOKEN'),false);
});

test('response byte and time limits also bound unfinished response bodies',async()=>{
 let cancelled=0,calls=0;
 const alive=setTimeout(()=>{},1000);
 try{
  const result=await probeHostedResponses({timeoutMs:20,record:async()=>{},fetchImpl:async()=>{
   calls++;
   return new Response(new ReadableStream({start(c){if(calls===1)c.enqueue(new Uint8Array(1025));},cancel(){cancelled++;}}),{status:403});
  }});
  assert.equal(calls,4);assert.equal(cancelled,4);
  assert(result.observations.every(o=>o.state==='transport-unconfirmed'));
 }finally{clearTimeout(alive);}
});
