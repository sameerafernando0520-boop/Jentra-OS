import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assertOrdinaryReportBinding, agedTotals, collectAgedReport } from './target_review_aging.mjs';
import { stableId } from './prepare-target-verification.mjs';
import { liveRpcSourceSql } from './run-reviewed-target-verification.mjs';

const uid=label=>stableId('offline-entity-aging-20261002',label);
const scope={tenant_id:uid('tenant'),legal_entity_id:uid('entity'),branch_id:uid('branch')};
const asOf='2026-09-30';
const row=(n,due='2026-10-01',amount='0.000001',original=amount,currency='LKR')=>({id:uid('item'+n),party_id:uid('party'+n%3),posting_date:'2026-01-01',due_date:due,
  currency_code:currency,base_currency_code:'LKR',original_amount:original,open_amount:amount,open_base_amount:amount});
const rows=Array.from({length:52},(_,n)=>row(n));
rows[0]=row(0,'2026-09-30','90071992547409.123456');
rows[1]=row(1,'2026-09-29');rows[2]=row(2,'2026-08-31');rows[3]=row(3,'2026-08-30');
rows[4]=row(4,'2026-08-01');rows[5]=row(5,'2026-07-31');rows[6]=row(6,'2026-07-02');
rows[7]=row(7,'2026-07-01');rows[8]=row(8,'2026-01-01','-2.000001','-3.000000');
rows[9]=row(9,'2026-10-01','1.000000','1.000000','USD');
const expectations=agedTotals(rows,asOf);
const call=(kind='AR')=>({rpc:'generate_control_reconciliation_report',params:{p_payload:{id:uid('report'),kind,as_of:asOf}},aging:structuredClone(expectations)});
const summary=c=>({id:c.params.p_payload.id,kind:c.params.p_payload.kind,as_of:asOf,...scope,item_count:52});
const page=(c,offset)=>({summary:summary(c),section:'items',evidence_key:null,items:rows.slice(offset,offset+50),next_cursor:offset===0?'50':null});

test('Entity AR/AP aged metrics use complete control generation and reject per-party statements',()=>{
  for(const [metric,kind]of[['aged_receivables','AR'],['aged_payables','AP']]){
    assertOrdinaryReportBinding(metric,call(kind));
    assert.throws(()=>assertOrdinaryReportBinding(metric,{...call(kind),rpc:'generate_operational_report',params:{p_payload:{kind:kind==='AR'?'customer_statement':'supplier_statement'}}}),/actual generation/);
  }
});
test('Aged source bindings reject party filters, wrong kind, one-party populations and partial expected buckets',()=>{
  for(const mutate of[c=>c.params.p_payload.party_id=uid('party'),c=>c.params.p_payload.kind='AP',c=>c.aging.party_count=1,c=>c.aging.buckets.pop()]){
    const c=call();mutate(c);assert.throws(()=>assertOrdinaryReportBinding('aged_receivables',c));
  }
});
test('Exact buckets separate credits, boundary due dates and currencies without unsafe financial numbers',()=>{
  const totals=agedTotals(rows,asOf);
  assert.equal(totals.item_count,52);assert.equal(totals.party_count,3);
  const current=totals.buckets.find(b=>b.currency_code==='LKR'&&b.bucket===0);
  assert.equal(current.amount,'90071992547409.123498');
  assert.equal(totals.buckets.find(b=>b.bucket===-1).amount,'-2.000001');
  for(const bucket of[1,2,3])assert.equal(totals.buckets.find(b=>b.bucket===bucket).item_count,2);
  assert.equal(totals.buckets.find(b=>b.bucket===4).item_count,1);
  assert.equal(totals.buckets.find(b=>b.currency_code==='USD').amount,'1.000000');
});
test('Aged aggregation rejects duplicate originals, inexact values and future posting dates',()=>{
  assert.throws(()=>agedTotals([rows[0],rows[0]],asOf),/Unique/);
  assert.throws(()=>agedTotals([{...rows[0],open_amount:0.1}],asOf),/decimal/);
  assert.throws(()=>agedTotals([{...rows[0],posting_date:'2026-10-01'}],asOf),/cutoff/);
  assert.throws(()=>agedTotals([{...rows[0],due_date:'2026-02-30'}],asOf),/date/);
});
test('The measured entity-aged operation includes every frozen item page with exact same scope',async()=>{
  const c=call(),reads=[];
  const actual=await collectAgedReport(c,summary(c),scope,async read=>{reads.push(read);return page(c,read.params.p_after);});
  assert.equal(actual.source_read_count,2);assert.equal(actual.item_count,52);assert.equal(actual.party_count,3);
  assert.deepEqual(reads.map(r=>r.params.p_after),[0,50]);
  for(const r of reads){assert.equal(r.rpc,'control_reconciliation_report_page');assert.equal(r.params.p_id,c.params.p_payload.id);for(const [key,value]of Object.entries(scope))assert.equal(r.params['p_'+key],value);}
});
test('The AP aged operation preserves the same exact signed residual and unapplied-credit basis',async()=>{
  const c=call('AP');const actual=await collectAgedReport(c,summary(c),scope,async read=>page(c,read.params.p_after));
  assert.deepEqual(actual.buckets,expectations.buckets);
});
for(const [name,mutate]of[
  ['foreign scope',p=>p.summary.legal_entity_id=uid('foreign')],
  ['stale cutoff',p=>p.summary.as_of='2026-09-29'],
  ['filtered evidence',p=>p.evidence_key=uid('account')],
  ['truncated population',p=>{p.items=p.items.slice(0,1);p.next_cursor=null;}],
  ['skipped cursor',p=>p.next_cursor='100'],
  ['repeated cursor',p=>p.next_cursor='0'],
  ['oversized page',p=>p.items=rows],
  ['duplicate source',p=>p.items[1]=p.items[0]]
])test('Aged operation refuses '+name+' instead of timing partial success',async()=>{
  const c=call();await assert.rejects(()=>collectAgedReport(c,summary(c),scope,async read=>{const p=structuredClone(page(c,read.params.p_after));if(read.params.p_after===0)mutate(p);return p;}));
});
test('Wrong exact aging totals fail after complete source collection',async()=>{
  const c=call();c.aging.buckets[0].amount='1.000000';
  await assert.rejects(()=>collectAgedReport(c,summary(c),scope,async read=>page(c,read.params.p_after)),/aged balances differ/);
});
test('Nested frozen-item read source is included in actual installed RPC fingerprint preflight',()=>{
  const source=liveRpcSourceSql({workloads:[{calls:[call()]}]});
  assert.equal(Object.keys(source.expected).length,2);
  assert.ok(Object.keys(source.expected).some(k=>k.startsWith('api.control_reconciliation_report_page(')));
});
