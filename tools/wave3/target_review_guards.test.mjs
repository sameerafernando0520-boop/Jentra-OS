import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { assertTarget, receiptCall, stableId } from './prepare-target-verification.mjs';
import { assertRaceClass, assertRacePostflightBindings, openNewEvidence } from './target_review_guards.mjs';

const seed = 'offline-wave3-review-20261002';
const uid = label => stableId(seed, label);
const scope = {tenant_id: uid('tenant'), legal_entity_id: uid('entity'), branch_id: uid('branch')};
const fixture = {synthetic: true, is_production: false, project_id: 'abcdefghijklmnopqrst',
  url: 'https://abcdefghijklmnopqrst.supabase.co', actor_id: uid('actor'), seed,
  posting_date: '2026-09-30', receipt_lanes: [{...scope, warehouse_id: uid('warehouse'),
    product_id: uid('product'), order_id: uid('order'), order_line_id: uid('order-line'),
    expected_version: Number.MAX_SAFE_INTEGER, receipt_count: 2,
    quantity_per_receipt: '1', reviewed_remaining_quantity: '2', reviewed_value_per_receipt: '1'}]};

test('Receipt plan rejects an ordinal crossing the exact optimistic version range', () => {
  assert.throws(() => assertTarget(fixture), /version/i);
});
test('Receipt command rejects raw lane overflow even when called without the plan compiler', () => {
  assert.throws(() => receiptCall(fixture, fixture.receipt_lanes[0], 1), /version/i);
});
test('The last safe receipt version remains exact and preserves original identity', () => {
  const lane = {...fixture.receipt_lanes[0], expected_version: Number.MAX_SAFE_INTEGER - 1};
  const safe = {...fixture, receipt_lanes: [lane]};
  assert.equal(assertTarget(safe), 2);
  assert.equal(receiptCall(safe, lane, 1).params.p_expected_entity_version, Number.MAX_SAFE_INTEGER);
  assert.deepEqual(receiptCall(safe, lane, 1), receiptCall(safe, lane, 1));
});

const command = (rpc,payload) => ({rpc,params:{p_payload:payload}});
const cases = {
  number_reservation: [0,1].map(i => command('transition_purchase_requisition',{document_id:uid('req'+i),action:'submit'})),
  order_allocation: [0,1].map(i => command('reserve_sales_order_stock',{sales_order_id:uid('so'+i),lines:[{sales_order_line_id:uid('so-line'+i),requested_base_quantity:'0.000001'}]})),
  stock_issue: [0,1].map(i => command('post_delivery',{document_id:uid('delivery'+i)})),
  receipt: [0,1].map(i => command('post_goods_receipt',{id:uid('receipt'+i),order_id:uid('order'),warehouse_id:uid('warehouse'),lines:[{order_line_id:uid('order-line'),accepted_quantity:'0.000001'}]})),
  matching: [0,1].map(i => command('bank_reconciliation_command',{id:uid('match'+i),action:'match',bank_id:uid('bank'),statement_line_ids:[uid('statement')],journal_line_ids:[uid('bank-journal')]})),
  allocation: [0,1].map(i => command('allocate_supplier_credit',{source_open_item_id:uid('source'+i),allocations:[{target_open_item_id:uid('target')}]})),
  posting: [0,1].map(() => command('post_manual_journal',{document_id:uid('journal')})),
  close: [0,1].map(i => command('period_governance_command',{id:uid('close'+i),action:'hard_lock',period_id:uid('period')})),
  reversal: [0,1].map(() => command('reverse_goods_receipt',{document_id:uid('original-receipt')}))
};
const postflight = {cases: {
  number_reservation:{document_ids:[uid('req0'),uid('req1')]},
  order_allocation:{sales_order_ids:[uid('so0'),uid('so1')]},
  stock_issue:{document_ids:[uid('delivery0'),uid('delivery1')]},
  receipt:{document_ids:[uid('receipt0'),uid('receipt1')],warehouse_id:uid('warehouse')},
  matching:{match_ids:[uid('match0'),uid('match1')],statement_line_id:uid('statement'),journal_line_id:uid('bank-journal')},
  allocation:{source_ids:[uid('source0'),uid('source1')],target_id:uid('target')},
  posting:{document_id:uid('journal')},close:{period_id:uid('period')},reversal:{receipt_id:uid('original-receipt')}
}};
const raceConfig = {races:Object.entries(cases).map(([kind,commands]) => ({kind,commands}))};
for (const [kind,commands] of Object.entries(cases)) {
  test(kind + ' accepts the actual scoped command class and intended contention sources', () => assertRaceClass(kind,commands));
  test(kind + ' refuses an unrelated otherwise-allowlisted mutation', () => {
    const wrong = structuredClone(commands); wrong[0].rpc='upsert_purchase_order';
    assert.throws(() => assertRaceClass(kind,wrong), /RPC and payload class/);
  });
  test(kind + ' refuses different supplemental invariant source IDs', () => {
    const wrong = structuredClone(postflight);
    const c=wrong.cases[kind]; const field=Object.keys(c).find(k => /(_ids|_id)$/.test(k));
    c[field]=Array.isArray(c[field])?[uid('unrelated'),c[field][1]]:uid('unrelated');
    assert.throws(() => assertRacePostflightBindings(raceConfig,wrong), /source IDs differ/);
  });
}
test('Postflight binds all nine classes to their real command document/source IDs', () => assertRacePostflightBindings(raceConfig,postflight));
test('Wrong lifecycle actions cannot stand in for number reservation, matching or close', () => {
  for (const kind of ['number_reservation','matching','close']) {
    const wrong=structuredClone(cases[kind]); wrong[0].params.p_payload.action='cancel';
    assert.throws(() => assertRaceClass(kind,wrong), /RPC and payload class/);
  }
});
test('Final-stock and allocation pairs must compete on distinct consumers and the same target', () => {
  const sameOrder=structuredClone(cases.order_allocation);sameOrder[1].params.p_payload.sales_order_id=sameOrder[0].params.p_payload.sales_order_id;
  assert.throws(() => assertRaceClass('order_allocation',sameOrder), /RPC and payload class/);
  const otherTarget=structuredClone(cases.allocation);otherTarget[1].params.p_payload.allocations[0].target_open_item_id=uid('other-target');
  assert.throws(() => assertRaceClass('allocation',otherTarget), /RPC and payload class/);
});
test('Reservation and receipt fixture quantities stay exact positive decimal strings', () => {
  for (const kind of ['order_allocation','receipt']) for(const amount of [0.1,'0','1e-6','-1','0.0000001']) {
    const wrong=structuredClone(cases[kind]);const field=kind==='receipt'?'accepted_quantity':'requested_base_quantity';
    wrong[0].params.p_payload.lines[0][field]=amount;
    assert.throws(() => assertRaceClass(kind,wrong), /RPC and payload class/);
  }
});
test('An existing or concurrently reserved evidence file is retained byte for byte', () => {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'wave3-offline-evidence-'));
  const output=path.join(root,'proof.json');let descriptor=null;
  try {
    descriptor=openNewEvidence(output,root);fs.writeFileSync(descriptor,'original offline evidence');
    assert.throws(() => openNewEvidence(output,root), /already exists/);
    assert.equal(fs.readFileSync(output,'utf8'),'original offline evidence');
    fs.closeSync(descriptor);descriptor=null;
    assert.throws(() => openNewEvidence(output,root), /already exists/);
    assert.equal(fs.readFileSync(output,'utf8'),'original offline evidence');
  }finally{if(descriptor!==null)fs.closeSync(descriptor);fs.unlinkSync(output);fs.rmdirSync(root);}
});
test('An out-of-boundary or wrong-format path fails before evidence creation', () => {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'wave3-offline-boundary-'));
  try {
    assert.throws(() => openNewEvidence(path.join(root,'..','escaped.json'),root), /path required/);
    assert.throws(() => openNewEvidence(path.join(root,'proof.txt'),root), /path required/);
    assert.deepEqual(fs.readdirSync(root),[]);
  }finally{fs.rmdirSync(root);}
});
