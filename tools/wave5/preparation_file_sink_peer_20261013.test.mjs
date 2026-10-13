import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { PROJECT_ID, freshId, hashJson, hashBytes } from './runtime_contract.mjs';
import { createEncryptedPreparationFileSink, readEncryptedPreparationRecords } from './preparation_file_sink.mjs';

// Actual temporary-file persistence of controlled synthetic records only. No
// user file, configured private key/sink, Auth, driver or network is accessed.
test('independent encrypted recovery distinguishes an available prefix from a complete journal and never modifies the prefix', async () => {
  const parent = await fs.mkdtemp(path.join(os.tmpdir(), 'jentra-w5-peer-recovery-')),
    directory = path.join(parent, `jentra-w5-preparation-${freshId()}`), key = crypto.randomBytes(32),
    binding = { projectId: PROJECT_ID, runtimeBundleSha256: hashJson('peer-bundle'),
      planBodySha256: hashJson('peer-plan'), sourceSha256: hashJson('peer-sink') };
  const caseId = freshId(), operationId = freshId(), records = [1, 2, 3].map(sequence => ({
    kind: 'wave5-private-preparation-journal-record', ...binding, sequence, recordId: freshId(),
    observedAt: new Date().toISOString(), caseId, scopeKey: 'load-001', action: 'peer-setup',
    phase: sequence === 1 ? 'checkpoint' : sequence === 2 ? 'intent' : 'confirmed', operationId,
    details: { originalId: freshId(), controlledRecoveryMaterial: 'LOCAL_CONTROLLED_RECOVERY_VALUE' } }));
  const sink = createEncryptedPreparationFileSink({ directory, encryptionKey: key, expectedBinding: binding });
  try {
    const receipts = [];
    for (const record of records) receipts.push(await sink.appendPreparationEvidence(record));
    await sink.close();
    const config = { directory, encryptionKey: key, expectedBinding: binding },
      expectedHead = { recordCount: 3, storageEvidenceSha256: receipts[2].storageEvidenceSha256 };
    const withoutHead = await readEncryptedPreparationRecords(config);
    assert.equal(withoutHead.completenessVerified, false);
    assert.equal(withoutHead.automaticReplayAllowed, false);
    assert.deepEqual(withoutHead.records, records);
    const complete = await readEncryptedPreparationRecords({ ...config, expectedHead });
    assert.equal(complete.completenessVerified, true);
    assert.equal(complete.automaticReplayAllowed, false);
    assert.equal(complete.availableHeadSha256, receipts[2].storageEvidenceSha256);
    const names = (await fs.readdir(directory)).sort();
    assert.equal(names.length, 3);
    const lastPath = path.join(directory, names[2]), lastBytes = await fs.readFile(lastPath);
    assert.equal(hashBytes(lastBytes), expectedHead.storageEvidenceSha256);
    assert.equal(lastBytes.includes(Buffer.from('LOCAL_CONTROLLED_RECOVERY_VALUE')), false);
    assert.equal(lastBytes.includes(Buffer.from(records[2].details.originalId)), false);
    // Remove only the final file created by this test to simulate lost tail data.
    assert.equal(path.dirname(lastPath), directory); await fs.unlink(lastPath);
    const prefixBytes = await Promise.all(names.slice(0, 2).map(name => fs.readFile(path.join(directory, name))));
    const prefix = await readEncryptedPreparationRecords(config);
    assert.equal(prefix.availableRecordCount, 2);
    assert.equal(prefix.completenessVerified, false);
    assert.equal(prefix.automaticReplayAllowed, false);
    assert.deepEqual(prefix.records, records.slice(0, 2));
    await assert.rejects(readEncryptedPreparationRecords({ ...config, expectedHead }), { code: 'EVIDENCE_WRITE_FAILED' });
    assert.deepEqual(await fs.readdir(directory), names.slice(0, 2));
    for (let i = 0; i < 2; i++) assert.deepEqual(await fs.readFile(path.join(directory, names[i])), prefixBytes[i]);
  } finally {
    await sink.close(); key.fill(0);
    if (path.dirname(directory) !== parent || !path.basename(parent).startsWith('jentra-w5-peer-recovery-'))
      throw new Error('UNEXPECTED_PEER_TEMPORARY_PATH');
    try {
      for (const name of await fs.readdir(directory)) {
        if (!/^[0-9]{8}-[0-9a-f-]{36}\.w5prep$/.test(name)) throw new Error('UNEXPECTED_PEER_TEMPORARY_FILE');
        await fs.unlink(path.join(directory, name));
      }
      await fs.rmdir(directory);
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await fs.rmdir(parent);
  }
});
