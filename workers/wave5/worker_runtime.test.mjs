import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {runDelivery,runExternalForecast,activateScheduledTrial} from './worker_runtime.mjs';
const id=i=>`10000000-0000-0000-0000-${String(i).padStart(12,'0')}`;
const scope={tenantId:id(1),legalEntityId:id(2),branchId:null};
const job={invocationId:id(3),usageEventId:id(4),periodStart:'2026-10-01T00:00:00Z',periodEnd:'2026-11-01T00:00:00Z',attempt:1,
 event:{eventId:id(5),type:'analytics.forecast.frozen.v1',...scope,forecastId:id(6),definitionVersion:1,sourceHash:'a'.repeat(64)},
 subscription:{id:id(7),scope,enabled:true,url:'https://events.jentra.test/hook',allowedHosts:['events.jentra.test'],keyVersion:1}};
function deliveryControl() {
 let claimed=false;
 const trace=[];
 return {trace,readiness:async()=>({contractRevision:1,ready:true,providers:{'committed_webhook.v1':1}}),
  claimCommittedDelivery:async()=>{if(claimed) return null;claimed=true;trace.push('claim');return job;},
  authorizeDelivery:async()=>{trace.push('authorize');},reserveUsage:async()=>{trace.push('reserve');},
  recordDeliveryOutcome:async(_j,o)=>{trace.push(o.state);},settleUsage:async q=>{assert.equal(q.quantity,'1');trace.push('settle');}};
}
const options=c=>({control:c,secrets:{deliveryKey:async()=>Buffer.alloc(32,7)},resolve:async()=>['8.8.8.8'],post:async()=>204,now:100});
test('missing providers fail before claiming or executing',async()=>{
 const c=deliveryControl();c.readiness=async()=>({ready:false});
 await assert.rejects(runDelivery(options(c)),/PROVIDER_UNAVAILABLE/);assert.deepEqual(c.trace,[]);
});
test('claimed committed job reserves before sending and records ACK before settlement',async()=>{
 const c=deliveryControl();const o=options(c);o.post=async()=>{c.trace.push('send');return 204;};
 assert.equal((await runDelivery(o)).state,'acknowledged');
 assert.ok(c.trace.indexOf('reserve')<c.trace.indexOf('send'));assert.ok(c.trace.indexOf('acknowledged')<c.trace.indexOf('settle'));
 for(let i=0;i<100;i++) assert.equal((await runDelivery(o)).state,'idle');
 assert.equal(c.trace.filter(x=>x==='send').length,1);
});
test('unknown transport persists review state and keeps its reservation without settlement',async()=>{
 const c=deliveryControl(),o=options(c);o.post=async()=>{throw Error('private remote diagnostic');};
 const result=await runDelivery(o);
 assert.equal(result.state,'unknown');assert.equal(result.retryAfterSeconds,null);
 assert.ok(c.trace.includes('unknown'));assert.equal(c.trace.includes('settle'),false);
});
test('revocation during DNS prevents send and settlement',async()=>{
 const c=deliveryControl(),o=options(c);let n=0;
 c.authorizeDelivery=async()=>{if(++n===3) throw Error('PERMISSION_DENIED');};o.post=async()=>{throw Error('should never send');};
 await assert.rejects(runDelivery(o),/PERMISSION_DENIED/);assert.equal(c.trace.includes('settle'),false);
});
test('subscription worker invokes existing server activation with exact identities',async()=>{
 let args;
 const c={readiness:async()=>({contractRevision:1,ready:true,providers:{'synthetic_subscription.v1':1}}),applySyntheticSubscription:async(...v)=>{args=v;return {state:'trialing'};}};
 assert.deepEqual(await activateScheduledTrial({control:c,tenantId:id(1),revisionId:id(8)}),{state:'trialing'});assert.deepEqual(args,[id(1),id(8)]);
});
test('external command validates request, credentials and durable allowance before dispatch',async()=>{
 const token='synthetic-only-token-'.repeat(3),credential={scope,tokenHash:createHash('sha256').update(token).digest('hex'),startsAt:1,expiresAt:200,revokedAt:null,commands:['analytics.freeze_pipeline.v1']};
 const trace=[],request={schemaVersion:1,scope,commandCode:'analytics.freeze_pipeline.v1',commandId:id(9),idempotencyKey:id(10),clientTimestamp:'2026-10-06T00:00:00Z',horizonStart:'2026-10-01',horizonEnd:'2026-11-01'};
 const c={readiness:async()=>({contractRevision:1,ready:true,providers:{'external_forecast.v1':1}}),findCredential:async()=>credential,
  entitlement:async()=>true,reserveExternalRequest:async()=>{trace.push('reserve');return {quotaReserved:true,throttleReserved:true};},dispatchForecast:async(_c,r)=>{trace.push('dispatch');return r.commandId;}};
 assert.equal(await runExternalForecast({control:c,token,request,now:100}),id(9));assert.deepEqual(trace,['reserve','dispatch']);
 for(const change of [{commandCode:'arbitrary.sql'},{horizonStart:'2026-02-30'},{clientTimestamp:'2026-02-30T00:00:00Z'},{secret:'private'},
  {scope:{...scope,privateBusinessRows:[]}},{scope:{...scope,branchId:id(12)}}]) {
  await assert.rejects(runExternalForecast({control:c,token,request:{...request,...change},now:100}));
 }
 const before=trace.length;c.reserveExternalRequest=async()=>({quotaReserved:true,throttleReserved:false});
 await assert.rejects(runExternalForecast({control:c,token,request,now:100}),/INTEGRATION_ACCESS_DENIED/);assert.equal(trace.length,before);
});
