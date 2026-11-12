import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { command, raceConfig, stableId } from './prepare-target-verification.mjs';

// These plans are only validated offline. No sessions, database or HTTP calls
// are supplied, and command results below are not concurrency evidence.
const seed = 'offline-race-identities-20261105';
const uid = value => stableId(seed, value);
const scope = { tenant_id: uid('tenant'), legal_entity_id: uid('entity'), branch_id: uid('branch') };
const project = 'abcdefghijklmnopqrst';
const fixture = { synthetic: true, is_production: false, project_id: project,
  url: `https://${project}.supabase.co`, actor_id: uid('actor-a'), seed,
  posting_date: '2026-09-30', receipt_lanes: [{ ...scope, warehouse_id: uid('warehouse'),
    product_id: uid('product'), order_id: uid('order'), order_line_id: uid('order-line'),
    expected_version: 1, receipt_count: 2, quantity_per_receipt: '1',
    reviewed_remaining_quantity: '2', reviewed_value_per_receipt: '1' }] };
const cases = {
  number_reservation: [0, 1].map(i => ['transition_purchase_requisition', { document_id: uid('req' + i), action: 'submit' }]),
  order_allocation: [0, 1].map(i => ['reserve_sales_order_stock', { sales_order_id: uid('so' + i),
    lines: [{ sales_order_line_id: uid('so-line' + i), requested_base_quantity: '1' }] }]),
  stock_issue: [0, 1].map(i => ['post_delivery', { document_id: uid('delivery' + i) }]),
  receipt: [0, 1].map(i => ['post_goods_receipt', { id: uid('receipt' + i), order_id: uid('order'),
    warehouse_id: uid('warehouse'), lines: [{ order_line_id: uid('order-line'), accepted_quantity: '1' }] }]),
  matching: [0, 1].map(i => ['bank_reconciliation_command', { id: uid('match' + i), action: 'match',
    bank_id: uid('bank'), statement_line_ids: [uid('statement')], journal_line_ids: [uid('journal-line')] }]),
  allocation: [0, 1].map(i => ['allocate_supplier_credit', { source_open_item_id: uid('credit' + i),
    allocations: [{ target_open_item_id: uid('target') }] }]),
  posting: [0, 1].map(() => ['post_manual_journal', { document_id: uid('journal') }]),
  close: [0, 1].map(i => ['period_governance_command', { id: uid('close' + i), action: 'hard_lock', period_id: uid('period') }]),
  reversal: [0, 1].map(() => ['reverse_goods_receipt', { document_id: uid('original-receipt') }]),
};
const races = Object.entries(cases).map(([kind, calls]) => ({ kind, expected_successes: 1,
  allowed_conflict_codes: ['VERSION_CONFLICT'],
  commands: calls.map(([rpc, payload]) => ({ rpc, payload })),
  invariants: [{ rpc: 'wave3_dashboard', params: {}, checks: [{ pointer: '/count', equals: 1 }] }],
}));
function plan() {
  return raceConfig({ fixture, scope, actors: [uid('actor-a'), uid('actor-b')], races });
}
function validate(config) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'jentra-race-identities-'));
  const filename = path.join(root, 'offline-plan.json');
  try {
    fs.writeFileSync(filename, JSON.stringify(config));
    return spawnSync(process.execPath, ['tools/wave3/run-independent-sessions.mjs', filename], {
      cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8', timeout: 15000,
    });
  } finally {
    fs.unlinkSync(filename);
    fs.rmdirSync(root);
  }
}

test('prepared race plan has 36 distinct command/idempotency IDs and remains offline', () => {
  const config = plan();
  const identities = config.races.flatMap(r => r.commands.flatMap(c => [c.params.p_command_id, c.params.p_idempotency_key]));
  assert.equal(new Set(identities).size, 36);
  const result = validate(config);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).executed, false);
});

for (const [name, mutate] of [
  ['command IDs reused by competing requests', c => { c.races[0].commands[1].params.p_command_id = c.races[0].commands[0].params.p_command_id; }],
  ['idempotency IDs reused by competing requests', c => { c.races[0].commands[1].params.p_idempotency_key = c.races[0].commands[0].params.p_idempotency_key; }],
  ['one identity reused across command and idempotency fields', c => { c.races[0].commands[0].params.p_idempotency_key = c.races[0].commands[0].params.p_command_id; }],
  ['an identity reused by different races', c => { c.races[8].commands[1].params.p_command_id = c.races[0].commands[0].params.p_idempotency_key; }],
  ['a repeated UUID with different letter case', c => { c.races[8].commands[1].params.p_command_id = c.races[0].commands[0].params.p_command_id.toUpperCase(); }],
]) {
  test('offline concurrency validation refuses ' + name, () => {
    const config = plan();
    mutate(config);
    const result = validate(config);
    assert.notEqual(result.status, 0, 'Replayed mutation identity was accepted as a fresh race plan');
    assert.match(result.stderr, /fresh.*identit/i);
  });
}

test('plan preparation stays deterministic and preserves command recovery identities', () => {
  assert.deepEqual(plan(), plan());
  const first = command(fixture, 'approved-recovery-command', scope, 'post_manual_journal', { document_id: uid('journal') });
  assert.deepEqual(first, command(fixture, 'approved-recovery-command', scope, 'post_manual_journal', { document_id: uid('journal') }));
});
