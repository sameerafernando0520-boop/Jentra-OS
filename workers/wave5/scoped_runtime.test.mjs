import test from 'node:test';
import assert from 'node:assert/strict';
import {createScopedWorkerRpc} from './scoped_runtime.mjs';
import {PersistentInvocationControl} from './persistent_control.mjs';
const runtime='11111111-1111-4111-8111-111111111111';
function ports(){const calls=[];const rpc=createScopedWorkerRpc({runtimeId:runtime,url:'https://xpdoufauvrbdmxgngetv.supabase.co',
 serviceKey:'synthetic-worker-test-value-000000000000',fetchImpl:async(url,options)=>{calls.push({url:String(url),body:JSON.parse(options.body)});return new Response('{}');}});
 return {calls,rpc,control:new PersistentInvocationControl(rpc)};}
test('worker claims, reconciliation and scheduler use the scoped server port',async()=>{
 const {calls,control}=ports();await control.claimCommittedDelivery();await control.reconcileAcknowledged();await control.dueSyntheticSubscriptions();
 assert.deepEqual(calls.map(c=>c.body.p_action),['delivery.claim','delivery.settle_acknowledged','subscription.due']);
 assert.ok(calls.every(c=>c.url.endsWith('/rpc/wave5_runtime_worker')&&c.body.p_runtime_id===runtime));
});
test('quota, activation and health retain their exact tenant identity',async()=>{
 const {calls,control}=ports();await control.reserveUsage({tenantId:runtime,invocationId:runtime,metric:'ai.tokens',periodStart:'a',periodEnd:'b',quantity:'10'});
 await control.settleUsage({tenantId:runtime,invocationId:runtime,eventId:runtime,quantity:'4'});
 await control.applySyntheticSubscription(runtime,runtime);await control.collectHealth(runtime,runtime);
 assert.deepEqual(calls.map(c=>c.body.p_action),['usage.reserve','usage.settle','subscription.apply','health.collect']);
 assert.ok(calls.every(c=>c.body.p_payload.tenantId===runtime));
});
test('model and external requests keep scope data for SQL authorization',async()=>{
 const {calls,control}=ports();await control.findCredential('synthetic-credential');await control.entitlement({tenantId:runtime});
 await control.beginModelInvocation({tenantId:runtime,sourceId:runtime});await control.recordModelOutcome(runtime,{state:'unknown'});
 assert.deepEqual(calls.map(c=>c.body.p_action),['external.credential','entitlement','model.begin','model.outcome']);
 assert.equal(calls[2].body.p_payload.tenantId,runtime);
});
test('unapproved RPC names fail before any transport',async()=>{
 const {rpc,calls}=ports();await assert.rejects(rpc('record_wave5_health_probe',{}),/WORKER_RPC_NOT_ALLOWLISTED/);assert.equal(calls.length,0);
 assert.throws(()=>createScopedWorkerRpc({runtimeId:'not-a-runtime'}),/WORKER_CONFIGURATION_INVALID/);
});
