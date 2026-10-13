import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyActivationDelta } from './synthetic_activation_contention_20261013_r5.mjs';
const execution='058364e8-c9f7-457f-bf4e-d6a8e2855f69',revision='496be77a-ef47-4f02-a2ac-fbe7026b0548',id='f6d4d9af-0d5d-47ad-9d3b-62cdd6f534a4';
const before={activation:0,revision:1,receipt:2,audit:2,outbox:2,quotaPeriods:0,memberships:4,
 subscription:{id,version:1,seats:5,plan_code:'w5_runtime_20261008'}};
const after={...before,activation:1,receipt:3,audit:3,outbox:3,subscription:{...before.subscription,version:2}};
const response={request_id:execution,entity:{id,revisionId:revision,version:'2'}};
test('activation accepts the original server execution identity with one committed effect',()=>{
 assert.equal(verifyActivationDelta(before,after,response,execution,revision),true);
});
test('activation cannot pass from two writes, unchanged version or the schedule command identity',()=>{
 for(const changed of [{...after,activation:2},{...after,receipt:4},{...after,audit:4},{...after,outbox:4},
  {...after,quotaPeriods:1},{...after,subscription:{...after.subscription,version:1}}]){
  assert.throws(()=>verifyActivationDelta(before,changed,response,execution,revision));
 }
 assert.throws(()=>verifyActivationDelta(before,after,{...response,request_id:revision},execution,revision));
});
