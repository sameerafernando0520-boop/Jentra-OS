import test from 'node:test';
import assert from 'node:assert/strict';
import {assessHostedAccounting} from '../../tools/wave5/hosted_accounting.mjs';

function snapshot(){return {contractRevision:1,projectId:'xpdoufauvrbdmxgngetv',
 runtimeId:'778237e3-3d4e-4871-8cc9-e08b07b989c7',observedAt:new Date().toISOString(),
 authorityActive:true,truncated:false,
 models:[{state:'settled',reserved:'2000',tokens:'150',quantity:'150',metric:'ai.tokens',eventMatches:true,reservationMatches:true,sourceMatches:true}],
 deliveries:[{state:'acknowledged',attempt:1,outcome:'acknowledged',httpStatus:200,reserved:'1',quantity:'1',
  metric:'webhook.deliveries',receiptPresent:true,receiptHashMatches:true,receiptKeyMatches:true,eventMatches:true}],
 quotas:[{settled:'151',expectedSettled:'151',reserved:'0',expectedReserved:'0'}]};}

test('nonempty matching hosted ledger can reconcile without asserting actual provider or transport observations',()=>{
 const result=assessHostedAccounting(snapshot());
 assert.equal(result.ledgerReconciled,true);
 assert.equal(result.settledModels,1);assert.equal(result.acknowledgedDeliveries,1);
 assert.equal(result.hostedModelResponseVerified,false);
 assert.equal(result.externalDeliveryVerified,false);
 assert.deepEqual(result.failures,[]);
});

test('unknown model outcomes retain their reservations and cannot masquerade as settled usage',()=>{
 const input=snapshot();
 input.models=[{state:'unknown',reserved:'2000',tokens:null,quantity:null,metric:'ai.tokens',eventMatches:false}];
 input.quotas=[{settled:'1',expectedSettled:'1',reserved:'2000',expectedReserved:'2000'}];
 const result=assessHostedAccounting(input);
 assert.equal(result.ledgerReconciled,false);assert.equal(result.unresolvedModels,1);
 assert.deepEqual(result.failures,['MODEL_OUTCOME_UNRESOLVED']);
 input.models[0].quantity='0';
 assert(assessHostedAccounting(input).failures.includes('MODEL_SETTLEMENT_MISMATCH'));
});

test('wrong token amount, metric, original event or quota balance fails reconciliation',()=>{
 for(const [field,value] of [['quantity','149'],['metric','webhook.deliveries'],['eventMatches',false],['reserved','100'],
  ['reservationMatches',false],['sourceMatches',false]]){
  const input=snapshot();input.models[0][field]=value;
  assert(assessHostedAccounting(input).failures.includes('MODEL_SETTLEMENT_MISMATCH'));
 }
 const input=snapshot();input.quotas[0].reserved='1';
 assert(assessHostedAccounting(input).failures.includes('QUOTA_BALANCE_MISMATCH'));
});

test('acknowledged delivery requires a matching receipt, attempt, HTTP result, key and one settled unit',()=>{
 for(const [field,value] of [['receiptPresent',false],['receiptHashMatches',false],['receiptKeyMatches',false],
  ['eventMatches',false],['httpStatus',307],['quantity','0'],['metric','ai.tokens'],['attempt',0]]){
  const input=snapshot();input.deliveries[0][field]=value;
  assert(assessHostedAccounting(input).failures.includes('DELIVERY_ACKNOWLEDGEMENT_MISMATCH'));
 }
});

test('unknown delivery does not settle quota even if the receiver recorded a receipt',()=>{
 const input=snapshot();Object.assign(input.deliveries[0],{state:'unknown',outcome:'unknown',httpStatus:null,quantity:null});
 const result=assessHostedAccounting(input);
 assert.equal(result.ledgerReconciled,false);assert.equal(result.unresolvedDeliveries,1);
 assert.deepEqual(result.failures,['DELIVERY_OUTCOME_UNRESOLVED']);
});

test('empty, stale, truncated, expired or malformed evidence never passes',()=>{
 const now=Date.now();
 for(const change of [{models:[],deliveries:[],quotas:[]},{authorityActive:false},{truncated:true},
  {observedAt:new Date(now-300001).toISOString()},{observedAt:new Date(now+1).toISOString()},
  {projectId:'other'},{models:[{state:'settled',tokens:'1e3'}]}]){
  assert.equal(assessHostedAccounting({...snapshot(),...change},{now}).ledgerReconciled,false);
 }
});

test('quota values stay exact beyond JavaScript safe integers and corrections are already reflected in expected totals',()=>{
 const input=snapshot();input.quotas=[{settled:'99999999999999999999',expectedSettled:'99999999999999999998',reserved:'0',expectedReserved:'0'}];
 assert(assessHostedAccounting(input).failures.includes('QUOTA_BALANCE_MISMATCH'));
 input.quotas[0].expectedSettled=input.quotas[0].settled;
 assert.equal(assessHostedAccounting(input).ledgerReconciled,true);
});
