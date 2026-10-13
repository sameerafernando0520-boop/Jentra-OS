import test from 'node:test';
import assert from 'node:assert/strict';
import { PROJECT_ID, hashJson, freshId, GuardError } from './runtime_contract.mjs';
import { createPreparationJournal } from './preparation_journal.mjs';

// Independent local persistence ordering probes. Every receipt and identifier is
// controlled; no private facility, file journal, credential or server is invoked.
const input = { projectId: PROJECT_ID, runtimeBundleSha256: hashJson('peer-reviewed-bundle'),
  planBodySha256: hashJson('peer-bound-plan'), sourceSha256: hashJson('peer-private-sink'),
  cases: [{ caseId: freshId(), scopeKey: 'load-001' }] };
const receipt = record => ({ durable: true, appendOnly: true, recordSha256: hashJson(record),
  storageEvidenceSha256: hashJson(['peer-controlled-storage', record]) });

test('independent preparation record preserves its reserved source-bound envelope against caller entry overrides', async () => {
  let persisted;
  const journal = createPreparationJournal({ ...input, appendPreparationEvidence: async record => {
    persisted = record; return receipt(record);
  } });
  await journal.append({ ...input.cases[0], phase: 'checkpoint', action: 'membership-baseline', details: { baseline: [] },
    kind: 'caller-overridden-kind', projectId: 'caller-overridden-project',
    runtimeBundleSha256: hashJson('wrong-bundle'), planBodySha256: hashJson('wrong-plan'), sourceSha256: hashJson('wrong-sink'),
    sequence: -1, recordId: 'caller-overridden-record', observedAt: 'caller-overridden-time' });
  assert.equal(persisted.kind, 'wave5-private-preparation-journal-record');
  assert.equal(persisted.projectId, input.projectId);
  assert.equal(persisted.runtimeBundleSha256, input.runtimeBundleSha256);
  assert.equal(persisted.planBodySha256, input.planBodySha256);
  assert.equal(persisted.sourceSha256, input.sourceSha256);
  assert.equal(persisted.sequence, 1);
  assert.match(persisted.recordId, /^[a-f0-9-]{36}$/);
  assert.ok(Number.isFinite(Date.parse(persisted.observedAt)));
});

test('independent waiting preparation never dispatches after another acknowledged operation becomes uncertain', async () => {
  let acknowledgeFirst, firstIntent, mutations = 0;
  const journal = createPreparationJournal({ ...input, appendPreparationEvidence: async record => {
    if (record.phase === 'intent' && record.action === 'waiting-setup') {
      firstIntent = record;
      return new Promise(resolve => { acknowledgeFirst = () => resolve(receipt(record)); });
    }
    return receipt(record);
  } });
  const waiting = journal.perform({ ...input.cases[0], action: 'waiting-setup', intent: { commandId: freshId() },
    operation: async () => { mutations++; return { id: freshId() }; } });
  assert.ok(firstIntent && acknowledgeFirst, 'The first intent must already be waiting for its durable receipt.');
  await assert.rejects(journal.perform({ ...input.cases[0], action: 'uncertain-setup', intent: { commandId: freshId() },
    operation: async () => { throw new GuardError('TRANSPORT_UNCERTAIN'); } }), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  acknowledgeFirst();
  await assert.rejects(waiting, { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  assert.equal(mutations, 0, 'An uncertain sibling must stop a later dispatch even if its intent receipt arrives.');
});
