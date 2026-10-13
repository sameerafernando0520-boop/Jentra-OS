import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { EventEmitter } from 'node:events';
import { FINANCE_SCOPE,FINANCE_CALENDAR,FINANCE_EXPECTED,FINANCE_ACCOUNTS,FINANCE_JOURNALS,financeId,financeFixtureSql,validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';
import { createFinanceHttpsTransport,financeDenial,exactRatio,encodeFinanceCsv } from './finance_https_transport_20261013_r5.mjs';
import { FINANCE_SCOPED_BODY,receiptResolutionSql,canonicalFinance,sameFinanceJson,validateCompleteCash,financePhasePreflight,observableCashHorizon,financeWorkflowId } from './finance_cash_workflows_20261013_r5.mjs';
import { hashBytes } from './runtime_contract.mjs';
const review=JSON.parse(fs.readFileSync(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',import.meta.url)));
const micros=text=>{const [whole,fraction]=text.split('.');return BigInt(whole)*1000000n+BigInt(fraction);};
const decimal=value=>(value<0n?'-':'')+(value<0n?-value:value)/1000000n+'.'+((value<0n?-value:value)%1000000n).toString().padStart(6,'0');
test('fixture stays in exact approved scope and creates synthetic sources without actor approvals or role/Auth writes',()=>{
 assert.equal(validateFinanceFixture(review).administrativeSourceFixture,true);
 assert.throws(()=>validateFinanceFixture({...review,syntheticScopes:review.syntheticScopes.map(s=>({...s,tenantId:financeId('wrong.scope')}))}));
 const sql=financeFixtureSql(),commit=financeFixtureSql({commit:true});
 assert.equal(commit.replace(/COMMIT;\n$/,'ROLLBACK;\n'),sql);assert.match(sql,/^BEGIN;/m);assert.match(sql,/ROLLBACK;\n$/);
 assert.ok(!/(?:insert into|update|delete from)\s+(?:auth\.|core\.(?:roles|role_permissions|role_assignments|command_receipts))/i.test(sql));
 assert.ok(!/request\.jwt|disable\s+trigger|approved_by|approved_digest|expense_decisions|\bdelete\b|\btruncate\b/i.test(sql));
 assert.match(sql,/FINANCE_FIXTURE_COLLISION_INSPECT_ORIGINAL_IDS/);assert.match(sql,/PROTECTED_OUTSIDE_FINANCE_SCOPE_CHANGED/);assert.match(sql,/SET CONSTRAINTS ALL IMMEDIATE/);
});
test('independent integer ledger oracle verifies every journal balance and current financial/cash projections',()=>{
 const balances=new Map(FINANCE_ACCOUNTS.map(a=>[a.id,0n]));let totalDebit=0n,totalCredit=0n;
 for(const j of FINANCE_JOURNALS){const amount=micros(j.amount);assert.ok(amount>0n&&j.debit!==j.credit);
  if(j.date<=FINANCE_CALENDAR.fixtureDay){balances.set(j.debit,balances.get(j.debit)+amount);balances.set(j.credit,balances.get(j.credit)-amount);totalDebit+=amount;totalCredit+=amount;}}
 assert.equal(totalDebit,totalCredit);assert.equal([...balances.values()].reduce((a,b)=>a+b,0n),0n);
 const byType=type=>FINANCE_ACCOUNTS.filter(a=>a.type===type).reduce((n,a)=>n+balances.get(a.id),0n);
 assert.equal(decimal(byType('asset')),FINANCE_EXPECTED.assets);assert.equal(decimal(-byType('liability')),FINANCE_EXPECTED.liabilities);
 assert.equal(decimal(-byType('revenue')),FINANCE_EXPECTED.revenue);assert.equal(decimal(byType('expense')),FINANCE_EXPECTED.expenses);
 assert.equal(decimal(-byType('revenue')-byType('expense')),FINANCE_EXPECTED.netProfit);
 assert.equal(decimal(balances.get(financeId('account.bank'))),FINANCE_EXPECTED.openingCash);
 const final=balances.get(financeId('account.bank'))+3000000001n+2000002n-1200000002n-7000001n-4000004n;
 assert.equal(decimal(final),FINANCE_EXPECTED.cashFinalBalance);assert.equal(decimal(final+1000001n),FINANCE_EXPECTED.hypotheticalFinalBalance);
});
test('ratio oracle uses signed half-away rounding and explicit nonpositive denominators',()=>{
 assert.deepEqual(exactRatio('1','6'),{exactValue:'0.166667',unavailableReason:null});
 assert.equal(exactRatio('-1','6').exactValue,'-0.166667');assert.equal(exactRatio('0.000001','2').exactValue,'0.000001');
 assert.equal(exactRatio('-0.000001','2').exactValue,'-0.000001');
 assert.deepEqual(exactRatio('1','0'),{exactValue:null,unavailableReason:'ZERO_DENOMINATOR'});
 assert.deepEqual(exactRatio('1','-1'),{exactValue:null,unavailableReason:'NEGATIVE_DENOMINATOR'});
 assert.throws(()=>exactRatio(0.1,'1'));assert.throws(()=>exactRatio('0.0000001','1'));
});
function localTransport(){const requests=[];let sends=0;const transport=createFinanceHttpsTransport({apiKey:'controlled-anon-key',agentFactory:()=>({destroy(){}}),
 requestFactory(url,options,responseCallback){const request=new EventEmitter();request.destroy=()=>{};request.end=()=>{sends++;
  queueMicrotask(()=>{const response=new EventEmitter();response.statusCode=200;responseCallback(response);response.emit('data',Buffer.from('{"ok":true}'));response.emit('end');});};
  requests.push({url,options,request});return request;}});return {transport,requests,sends:()=>sends};}
test('finance transport rejects arbitrary route/scope/profile and requires genuine verified TLS before bytes',async()=>{
 const local=localTransport(),handle=local.transport.connection();
 for(const [route,body,profile]of [['/rest/v1/rpc/delete_user',FINANCE_SCOPED_BODY,'api'],['/rest/v1/rpc/wave5_cash_basis',{...FINANCE_SCOPED_BODY,p_tenant_id:financeId('other')},'api'],
  ['/rest/v1/rpc/wave5_cash_basis',FINANCE_SCOPED_BODY,'public']])await assert.rejects(local.transport.send(handle,route,{body,profile,bearer:'controlled-token'}));
 assert.equal(local.requests.length,0);
 const result=local.transport.send(handle,'/rest/v1/rpc/wave5_cash_basis',{body:FINANCE_SCOPED_BODY,profile:'api',bearer:'controlled-token'});
 const socket=new EventEmitter();socket.encrypted=true;socket.authorized=false;local.requests[0].request.emit('socket',socket);assert.equal(local.sends(),0);
 socket.authorized=true;socket.emit('secureConnect');const actual=await result;assert.equal(local.sends(),1);assert.ok(actual.evidence.sentAt);assert.ok(!JSON.stringify(actual).includes('controlled-token'));local.transport.close();
});
test('late TLS after transport uncertainty does not dispatch and private exception detail is discarded',async()=>{
 const local=localTransport(),result=local.transport.send(local.transport.connection(),'/auth/v1/user',{method:'GET',bearer:'controlled-private-token'});
 const socket=new EventEmitter();socket.encrypted=true;socket.authorized=false;local.requests[0].request.emit('socket',socket);
 local.requests[0].request.emit('error',Error('private password detail'));await assert.rejects(result,error=>error.publicCode==='FINANCE_TRANSPORT_UNCERTAIN'&&!error.message.includes('password'));
 socket.authorized=true;socket.emit('secureConnect');assert.equal(local.sends(),0);local.transport.close();
});
test('only installed exact SQLSTATE/status denial shapes are classified; arbitrary server errors stay uncertain',()=>{
 assert.equal(financeDenial({ok:false,status:403,value:{code:'42501',message:'Permission denied or multi-factor authentication required.'}}),'PERMISSION_DENIED');
 assert.equal(financeDenial({ok:false,status:409,value:{code:'40001',message:'CASH_DATE_VERSION_CONFLICT'}}),'CASH_DATE_VERSION_CONFLICT');
 for(const response of [{ok:false,status:500,value:{code:'40001',message:'CASH_DATE_VERSION_CONFLICT'}},{ok:false,status:403,value:{code:'42501',message:'unexpected private text'}},
  {ok:true,status:200,value:{code:'42501',message:'PERMISSION_DENIED'}}])assert.equal(financeDenial(response),null);
});
test('CSV preserves exact money, quotes cells and neutralizes spreadsheet formula cells while keeping signed numerics',()=>{
 const document={version:1,metadata:{row_count:1,label:'=SUM(1,2)'},rows:[{amount:'-2.000002',description:'"receipt",synthetic',note:'@danger'}]};
 const artifact=encodeFinanceCsv(document,{exportId:financeId('export.test'),preparedAt:'2026-10-13T00:00:00Z',sourceHash:hashBytes('actual-canonical')});
 assert.equal(artifact.sha256,hashBytes(artifact.bytes));assert.match(artifact.bytes.toString(),/'=SUM/);assert.match(artifact.bytes.toString(),/'@danger/);
 assert.match(artifact.bytes.toString(),/-2\.000002/);assert.match(artifact.bytes.toString(),/""receipt""/);
 assert.throws(()=>encodeFinanceCsv({...document,rows:[{amount:2.000002}]},{exportId:financeId('export.test'),preparedAt:'2026-10-13T00:00:00Z',sourceHash:hashBytes('x')}));
});
test('cash validation requires all five providers, source digests, directions and exact populated amounts',()=>{
 const data={contractRevision:3,scope:{tenantId:FINANCE_SCOPE.tenantId,legalEntityId:FINANCE_SCOPE.entityId,branchId:FINANCE_SCOPE.branchId},
  horizonStart:FINANCE_CALENDAR.horizonStart,horizonEnd:FINANCE_CALENDAR.horizonEnd,completeProviders:['bank_cash','receivables','payables','payroll','project_reimbursements'],
  providerStatus:Object.fromEntries(['bank_cash','receivables','payables','payroll','project_reimbursements'].map(k=>[k,'available'])),controls:[{amount:FINANCE_EXPECTED.openingCash}],
  obligations:[['open.ar','3000.000001',true],['open.ap','1200.000002',false],['payroll.obligation',FINANCE_EXPECTED.payrollOpening,false],['payroll.recovery','2.000002',true],['reimbursement',FINANCE_EXPECTED.reimbursement,false]]
   .map(([label,amount,inflow])=>({id:financeId(label),amount,inflow,currency:'LKR',dueDate:FINANCE_CALENDAR.dueDate}))};
 const canonicalText=JSON.stringify(data),value={canonicalText,sourceHash:hashBytes(canonicalText)};assert.equal(validateCompleteCash(value).obligations.length,5);
 assert.throws(()=>canonicalFinance({...value,sourceHash:hashBytes('tampered')}));
 const changed={...data,completeProviders:['bank_cash']},text=JSON.stringify(changed);assert.throws(()=>validateCompleteCash({canonicalText:text,sourceHash:hashBytes(text)}));
});
test('receipt recovery is fixed read-only original identity, and JSONB key ordering does not cause a false scenario mismatch',()=>{
 const sql=receiptResolutionSql(financeId('command.test'));assert.match(sql,/^SELECT /);assert.ok(!/INSERT|UPDATE|DELETE|auth\./i.test(sql));assert.throws(()=>receiptResolutionSql("' OR TRUE"));
 assert.equal(sameFinanceJson({b:{x:1,y:2},a:[]},{a:[],b:{y:2,x:1}}),true);assert.equal(sameFinanceJson({x:['a','b']},{x:['b','a']}),false);
});

test('finance phase stops on any prior publication or changed fixture identity before user commands',()=>{
 const facts={journals:9,lines:18,journalIds:FINANCE_JOURNALS.map(j=>j.id).sort(),publications:0,classifications:0,dateProposals:0,dateDecisions:0,scenarios:0,exports:0};
 assert.doesNotThrow(()=>financePhasePreflight(facts,'finance'));
 for(const changed of [{...facts,publications:1},{...facts,exports:1},{...facts,journalIds:[financeId('other.journal')]},{...facts,dateDecisions:1}])
  assert.throws(()=>financePhasePreflight(changed,'finance'),/EXACT_COMMITTED_FINANCE_PHASE_FIXTURE_REQUIRED/);
 assert.throws(()=>financePhasePreflight(facts,'unknown'),/FIXED_FINANCE_PHASE_REQUIRED/);
});

test('cash phase requires the completed finance counts and a genuinely observed opening cutoff',()=>{
 const facts={journals:9,lines:18,journalIds:FINANCE_JOURNALS.map(j=>j.id).sort(),publications:3,classifications:1,dateProposals:3,dateDecisions:3,scenarios:0,exports:2};
 assert.doesNotThrow(()=>financePhasePreflight(facts,'cash'));
 assert.throws(()=>financePhasePreflight({...facts,dateDecisions:2},'cash'));
 assert.throws(()=>financePhasePreflight({...facts,scenarios:1},'cash'));
 assert.equal(observableCashHorizon('2026-10-13T23:59:59.999Z'),false);
 assert.equal(observableCashHorizon('2026-10-14T00:00:00.000Z'),true);
 assert.throws(()=>observableCashHorizon('tomorrow'),/ACTUAL_CASH_CLOCK_REQUIRED/);
});

test('fixed API enum names produce distinct workflow identities while retaining all fixture identities',()=>{
 for(const name of ['period','payroll.obligation','command.posting-denial'])assert.equal(financeWorkflowId(name),financeId(name));
 const names=['statement.profit_loss','statement.balance_sheet','statement.trial_balance','date.payroll_obligation','date.payroll_correction','date.project_reimbursement'];
 const ids=names.map(name=>financeWorkflowId(name));assert.equal(new Set(ids).size,names.length);
 for(let i=0;i<names.length;i++)assert.equal(ids[i],financeId(names[i].replaceAll('_','-')));
 assert.throws(()=>financeWorkflowId("statement/' OR TRUE"));
});
