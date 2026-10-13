import test from 'node:test';
import assert from 'node:assert/strict';
import { hashJson, freshId } from './runtime_contract.mjs';
import * as journalModule from './preparation_journal.mjs';

// Controlled private sink receipts only; no credential or live operation.
const binding = { projectId: 'xpdoufauvrbdmxgngetv', runtimeBundleSha256: 'a'.repeat(64),
  planBodySha256: 'b'.repeat(64), sourceSha256: 'c'.repeat(64),
  cases: [{ caseId: freshId(), scopeKey: 'load-001' }] };
function journal(append) {
  assert.equal(typeof journalModule.createPreparationJournal, 'function', 'Private durable preparation guarding is not implemented.');
  return journalModule.createPreparationJournal({ ...binding, appendPreparationEvidence: append });
}
const receipt = record => ({ durable: true, appendOnly: true, recordSha256: hashJson(record), storageEvidenceSha256: hashJson(['stored', record]) });

test('preparation persistence acknowledges original identities before a mutation starts and saves returned identities before resolving', async () => {
  const order = [], original = freshId(), returned = freshId(); let persistedIntent, persistedResult;
  const guard = journal(async record => { order.push(record.phase); if (record.phase === 'intent') persistedIntent = record;
    else persistedResult = record; return receipt(record); });
  const result = await guard.perform({ ...binding.cases[0], action: 'setup-rpc', intent: { originalCommandId: original },
    operation: async () => { order.push('mutation'); assert.equal(persistedIntent.details.originalCommandId, original); return { id: returned }; } });
  assert.deepEqual(order, ['intent', 'mutation', 'confirmed']); assert.equal(result.id, returned);
  assert.equal(persistedResult.details.result.id, returned); assert.equal(persistedIntent.operationId, persistedResult.operationId);
  assert.equal(persistedResult.planBodySha256, binding.planBodySha256); assert.equal(persistedResult.runtimeBundleSha256, binding.runtimeBundleSha256);
});

test('failed intent persistence, invalid durable receipt or changed case scope prevents every mutation and further attempt', async () => {
  for (const sink of [async () => { throw new Error('private sink error'); }, async record => ({ ...receipt(record), durable: false }),
    async record => ({ ...receipt(record), recordSha256: 'd'.repeat(64) })]) {
    const guard = journal(sink); let mutations = 0;
    const task = { ...binding.cases[0], action: 'setup', intent: { baseline: [] }, operation: async () => { mutations++; } };
    await assert.rejects(guard.perform(task), error => !error.message.includes('private'));
    await assert.rejects(guard.perform(task)); assert.equal(mutations, 0);
  }
  const guard = journal(async record => receipt(record)); let mutations = 0;
  await assert.rejects(guard.perform({ ...binding.cases[0], scopeKey: 'runtime', action: 'setup', intent: {}, operation: async () => { mutations++; } }));
  assert.equal(mutations, 0);
});

test('uncertain commit retains its original intent and blocks retry or restoration without exposing arbitrary error text', async () => {
  const records = [], guard = journal(async record => { records.push(record); return receipt(record); }), original = freshId(); let sends = 0;
  const task = { ...binding.cases[0], action: 'fixture-commit', intent: { transactionId: original },
    operation: async () => { sends++; throw new Error('private ambiguous failure'); } };
  await assert.rejects(guard.perform(task), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  assert.deepEqual(records.map(record => record.phase), ['intent', 'uncertain']); assert.equal(records[0].details.transactionId, original);
  assert.equal(records[1].details.failureCode, 'PROVIDER_FAILURE');
  await assert.rejects(guard.perform(task), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  assert.throws(() => guard.assertHealthy(), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' }); assert.equal(sends, 1);
});

test('failed confirmed-result persistence stops after exactly one send and attempts to preserve returned recovery identifiers', async () => {
  const records = [], returned = freshId(), guard = journal(async record => {
    records.push(record); if (record.phase === 'confirmed') throw new Error('private disk failure'); return receipt(record);
  }); let sends = 0;
  await assert.rejects(guard.perform({ ...binding.cases[0], action: 'invitation-create', intent: { email: 'w5-approver@jentra.invalid' },
    operation: async () => { sends++; return { invitation_id: returned, token: 'controlled-private-recovery-token' }; } }), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  assert.equal(sends, 1); assert.deepEqual(records.map(record => record.phase), ['intent', 'confirmed', 'uncertain']);
  assert.equal(records[2].details.result.invitation_id, returned); assert.equal(records[2].details.result.token, 'controlled-private-recovery-token');
  assert.throws(() => guard.assertHealthy(), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
});

test('preparation checkpoint copies the original mutable baseline before acknowledged persistence', async () => {
  const baseline = { membershipId: freshId(), version: '1' }; let saved;
  const guard = journal(async record => { saved = record; return receipt(record); });
  await guard.append({ ...binding.cases[0], action: 'membership-baseline', phase: 'checkpoint', details: { baseline } });
  baseline.version = '9'; assert.equal(saved.details.baseline.version, '1'); assert.ok(Object.isFrozen(saved.details.baseline));
});

test('caller fields cannot overwrite the source-bound preparation envelope or sequence', async () => {
  let saved; const guard = journal(async record => { saved = record; return receipt(record); });
  await guard.append({ ...binding.cases[0], action: 'baseline', phase: 'checkpoint', details: {},
    projectId: 'other', sourceSha256: 'x', planBodySha256: 'y', runtimeBundleSha256: 'z', sequence: 99, recordId: 'not-an-id' });
  assert.equal(saved.projectId, binding.projectId); assert.equal(saved.sourceSha256, binding.sourceSha256);
  assert.equal(saved.planBodySha256, binding.planBodySha256); assert.equal(saved.runtimeBundleSha256, binding.runtimeBundleSha256);
  assert.equal(saved.sequence, 1); assert.notEqual(saved.recordId, 'not-an-id');
});

test('a waiting acknowledged intent cannot dispatch after another preparation has become uncertain', async () => {
  let release, entered; const held = new Promise(resolve => { release = resolve; }), started = new Promise(resolve => { entered = resolve; });
  const guard = journal(async record => { if (record.action === 'waiting-setup' && record.phase === 'intent') { entered(); await held; }
    return receipt(record); }); let lateSends = 0;
  const waiting = guard.perform({ ...binding.cases[0], action: 'waiting-setup', intent: {}, operation: async () => { lateSends++; } });
  await started;
  await assert.rejects(guard.perform({ ...binding.cases[0], action: 'unknown-setup', intent: {}, operation: async () => { throw new Error('ambiguous'); } }),
    { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  release(); await assert.rejects(waiting, { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' }); assert.equal(lateSends, 0);
});
