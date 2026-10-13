import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { PROJECT_ID, freshId, hashBytes, hashJson } from './runtime_contract.mjs';
import { createPreparationJournal } from './preparation_journal.mjs';
import * as sinkModule from './preparation_file_sink.mjs';

// Real file persistence of controlled synthetic records; no credential, network,
// PostgreSQL, Auth or user-account access. Cleanup touches only this exact temp dir.
const binding = Object.freeze({ projectId: PROJECT_ID, runtimeBundleSha256: 'a'.repeat(64),
  planBodySha256: 'b'.repeat(64), sourceSha256: 'c'.repeat(64) });
const cases = [{ caseId: freshId(), scopeKey: 'load-001' }];
const record = (sequence, details = {}) => ({ kind: 'wave5-private-preparation-journal-record', ...binding,
  sequence, recordId: freshId(), observedAt: new Date().toISOString(), ...cases[0], action: 'controlled-setup', phase: 'checkpoint', details });
async function fixture() {
  const parent = await fs.mkdtemp(path.join(os.tmpdir(), 'jentra-w5-sink-test-')),
    directory = path.join(parent, `jentra-w5-preparation-${freshId()}`);
  return { directory, async cleanup() {
    if (path.dirname(directory) !== parent || !path.basename(parent).startsWith('jentra-w5-sink-test-')) throw new Error('unexpected test path');
    try { for (const name of await fs.readdir(directory)) {
      if (!/^[0-9]{8}-[0-9a-f-]{36}\.w5prep$/.test(name)) throw new Error('unexpected test file');
      await fs.unlink(path.join(directory, name));
    } await fs.rmdir(directory); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await fs.rmdir(parent);
  } };
}
function make(directory, key) {
  assert.equal(typeof sinkModule.createEncryptedPreparationFileSink, 'function', 'Encrypted append-only private preparation storage is not implemented.');
  return sinkModule.createEncryptedPreparationFileSink({ directory, encryptionKey: key, expectedBinding: binding });
}
async function recover(directory, key) {
  assert.equal(typeof sinkModule.readEncryptedPreparationRecords, 'function', 'Read-only preparation recovery is not implemented.');
  const result = await sinkModule.readEncryptedPreparationRecords({ directory, encryptionKey: key, expectedBinding: binding });
  assert.equal(result.completenessVerified, false); assert.equal(result.automaticReplayAllowed, false); return result.records;
}

test('private preparation file acknowledgement follows actual encrypted file flush and supports read-only recovery of original identities', async () => {
  const temp = await fixture(), key = crypto.randomBytes(32), sink = make(temp.directory, key);
  try {
    await assert.rejects(fs.stat(temp.directory), { code: 'ENOENT' });
    const original = freshId(), returned = freshId(), privateValue = 'controlled-invitation-recovery-material';
    const journal = createPreparationJournal({ ...binding, cases, appendPreparationEvidence: sink.appendPreparationEvidence });
    await journal.perform({ ...cases[0], action: 'invitation-create', intent: { commandId: original },
      operation: async () => {
        const before = await recover(temp.directory, key); assert.equal(before.length, 1);
        assert.equal(before[0].details.commandId, original); return { invitationId: returned, privateRecovery: privateValue };
      } });
    const saved = await recover(temp.directory, key); assert.equal(saved.length, 2);
    assert.equal(saved[1].details.result.invitationId, returned); assert.equal(saved[1].details.result.privateRecovery, privateValue);
    assert.equal(saved[0].operationId, saved[1].operationId); assert.ok(Object.isFrozen(saved[1].details.result));
    for (const name of await fs.readdir(temp.directory)) {
      const bytes = await fs.readFile(path.join(temp.directory, name));
      assert.equal(bytes.includes(Buffer.from(privateValue)), false); assert.equal(bytes.includes(Buffer.from(returned)), false);
    }
  } finally { await sink.close(); await temp.cleanup(); key.fill(0); }
});

test('exclusive encrypted files preserve concurrent record order and chain storage receipt hashes without reusing an existing directory', async () => {
  const temp = await fixture(), key = crypto.randomBytes(32), sink = make(temp.directory, key), records = [record(1), record(2), record(3)];
  let other;
  try {
    const receipts = await Promise.all(records.map(value => sink.appendPreparationEvidence(value)));
    const files = (await fs.readdir(temp.directory)).sort(); assert.equal(files.length, 3);
    for (let i = 0; i < files.length; i++) {
      const bytes = await fs.readFile(path.join(temp.directory, files[i])), envelope = JSON.parse(bytes);
      assert.deepEqual(receipts[i], { durable: true, appendOnly: true, recordSha256: hashJson(records[i]), storageEvidenceSha256: hashBytes(bytes) });
      assert.equal(envelope.previousStorageSha256, i ? receipts[i - 1].storageEvidenceSha256 : null);
    }
    assert.deepEqual(await recover(temp.directory, key), records);
    other = make(temp.directory, key);
    await assert.rejects(other.appendPreparationEvidence(record(1)), { code: 'EVIDENCE_WRITE_FAILED' });
    assert.equal((await fs.readdir(temp.directory)).length, 3);
  } finally { await other?.close(); await sink.close(); await temp.cleanup(); key.fill(0); }
});

test('private encryption key and source binding are copied before caller mutation and closed sink cannot create another record', async () => {
  const temp = await fixture(), key = crypto.randomBytes(32), originalKey = Buffer.from(key), configBinding = { ...binding };
  assert.equal(typeof sinkModule.createEncryptedPreparationFileSink, 'function');
  const sink = sinkModule.createEncryptedPreparationFileSink({ directory: temp.directory, encryptionKey: key, expectedBinding: configBinding });
  try {
    key.fill(0); configBinding.planBodySha256 = 'd'.repeat(64);
    const value = record(1); await sink.appendPreparationEvidence(value);
    assert.deepEqual(await recover(temp.directory, originalKey), [value]); await sink.close();
    await assert.rejects(sink.appendPreparationEvidence(record(2)), { code: 'EVIDENCE_WRITE_FAILED' });
    assert.equal((await fs.readdir(temp.directory)).length, 1);
  } finally { await sink.close(); await temp.cleanup(); originalKey.fill(0); }
});

test('wrong project, source binding, sequence or original identifier stops encrypted persistence before any directory or file appears', async () => {
  for (const changed of [{ projectId: 'other-project' }, { sourceSha256: 'd'.repeat(64) }, { sequence: 2 }, { recordId: 'invalid' }]) {
    const temp = await fixture(), key = crypto.randomBytes(32), sink = make(temp.directory, key);
    try {
      await assert.rejects(sink.appendPreparationEvidence({ ...record(1), ...changed }), { code: 'EVIDENCE_WRITE_FAILED' });
      await assert.rejects(fs.stat(temp.directory), { code: 'ENOENT' });
      await assert.rejects(sink.appendPreparationEvidence(record(1)), { code: 'EVIDENCE_WRITE_FAILED' });
    } finally { await sink.close(); await temp.cleanup(); key.fill(0); }
  }
});

test('read-only recovery rejects wrong key, source drift, changed encrypted bytes, missing original records and partial files without modifying storage', async () => {
  const temp = await fixture(), key = crypto.randomBytes(32), sink = make(temp.directory, key);
  try {
    await sink.appendPreparationEvidence(record(1)); await sink.appendPreparationEvidence(record(2)); await sink.close();
    const files = (await fs.readdir(temp.directory)).sort(), first = path.join(temp.directory, files[0]), bytes = await fs.readFile(first);
    await assert.rejects(recover(temp.directory, crypto.randomBytes(32)), { code: 'EVIDENCE_WRITE_FAILED' });
    await assert.rejects(sinkModule.readEncryptedPreparationRecords({ directory: temp.directory, encryptionKey: key,
      expectedBinding: { ...binding, planBodySha256: 'd'.repeat(64) } }), { code: 'EVIDENCE_WRITE_FAILED' });
    assert.deepEqual(await fs.readFile(first), bytes);
    const changed = JSON.parse(bytes); changed.ciphertext = 'AAAA';
    await fs.writeFile(first, JSON.stringify(changed)); await assert.rejects(recover(temp.directory, key), { code: 'EVIDENCE_WRITE_FAILED' });
    await fs.writeFile(first, bytes); await fs.unlink(first);
    await assert.rejects(recover(temp.directory, key), { code: 'EVIDENCE_WRITE_FAILED' });
    await fs.writeFile(first, bytes, { flag: 'wx' }); await fs.writeFile(first, '{');
    await assert.rejects(recover(temp.directory, key), { code: 'EVIDENCE_WRITE_FAILED' });
    assert.equal((await fs.readFile(first, 'utf8')), '{');
  } finally { await sink.close(); await temp.cleanup(); key.fill(0); }
});

test('encrypted preparation storage refuses a repository destination or absent private key without filesystem access', () => {
  assert.equal(typeof sinkModule.createEncryptedPreparationFileSink, 'function');
  const key = crypto.randomBytes(32);
  try {
    assert.throws(() => make(path.join(process.cwd(), `jentra-w5-preparation-${freshId()}`), key), { code: 'REVIEWED_PREPARATION_REQUIRED' });
    assert.throws(() => make(path.join(os.tmpdir(), `jentra-w5-preparation-${freshId()}`), null), { code: 'REVIEWED_PREPARATION_REQUIRED' });
    assert.throws(() => make('relative-jentra-w5-preparation', key), { code: 'REVIEWED_PREPARATION_REQUIRED' });
  } finally { key.fill(0); }
});

test('recovery completeness requires an independent exact expected head and refuses a truncated tail without claiming replay authority', async () => {
  const temp = await fixture(), key = crypto.randomBytes(32), sink = make(temp.directory, key);
  try {
    await sink.appendPreparationEvidence(record(1)); const receipt = await sink.appendPreparationEvidence(record(2)); await sink.close();
    const expectedHead = { recordCount: 2, storageEvidenceSha256: receipt.storageEvidenceSha256 };
    const verified = await sinkModule.readEncryptedPreparationRecords({ directory: temp.directory, encryptionKey: key,
      expectedBinding: binding, expectedHead });
    assert.equal(verified.completenessVerified, true); assert.equal(verified.automaticReplayAllowed, false);
    assert.equal(verified.availableRecordCount, 2); assert.equal(verified.availableHeadSha256, receipt.storageEvidenceSha256);
    const last = (await fs.readdir(temp.directory)).sort().at(-1); await fs.unlink(path.join(temp.directory, last));
    const prefix = await sinkModule.readEncryptedPreparationRecords({ directory: temp.directory, encryptionKey: key, expectedBinding: binding });
    assert.equal(prefix.completenessVerified, false); assert.equal(prefix.availableRecordCount, 1);
    await assert.rejects(sinkModule.readEncryptedPreparationRecords({ directory: temp.directory, encryptionKey: key,
      expectedBinding: binding, expectedHead }), { code: 'EVIDENCE_WRITE_FAILED' });
  } finally { await sink.close(); await temp.cleanup(); key.fill(0); }
});

test('encrypted storage and recovery reject a directory junction or symbolic link before creating or reading any record', async () => {
  const temp = await fixture(), key = crypto.randomBytes(32), sink = make(temp.directory, key); let linked = false;
  try {
    await fs.symlink(path.dirname(temp.directory), temp.directory, process.platform === 'win32' ? 'junction' : 'dir'); linked = true;
    await assert.rejects(sink.appendPreparationEvidence(record(1)), { code: 'EVIDENCE_WRITE_FAILED' });
    await assert.rejects(recover(temp.directory, key), { code: 'EVIDENCE_WRITE_FAILED' });
  } finally {
    await sink.close(); if (linked) { try { await fs.unlink(temp.directory); }
      catch (error) { if (!['EPERM', 'EISDIR'].includes(error.code)) throw error; await fs.rmdir(temp.directory); } }
    await temp.cleanup(); key.fill(0);
  }
});
