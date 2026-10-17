import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { main } from '../../../../../tools/wave5/run_runtime_verification.mjs';
import { hashBytes } from '../../../../../tools/wave5/runtime_contract.mjs';

const folder = 'docs/verification/wave5/seven-area-completion-20261016/area6-load';
const runtime = 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json';
const tracePath = 'tools/wave5/runtime_load_trace_20261017_r5.mjs';
async function fixture() {
  const source = JSON.parse(await fs.readFile('docs/verification/wave5/task3-acceptance-20261013/runtime-harness-review-20261014-acceptance-a1.json', 'utf8'));
  for (const ref of [...source.files, ...source.contractSources]) {
    const bytes = await fs.readFile(ref.path); ref.sha256 = hashBytes(bytes); ref.bytes = bytes.length;
  }
  const bytes = await fs.readFile(tracePath); source.files.push({ path: tracePath, bytes: bytes.length, sha256: hashBytes(bytes) });
  source.controlledFixture = true;
  source.fixtureMeaning = 'Controlled offline source binding fixture only; no independent verdict, human decision or live authority.';
  return source;
}
async function validate(source) {
  const filename = path.join(folder, `controlled-cli-fixture-${crypto.randomUUID()}.json`);
  await fs.writeFile(filename, JSON.stringify(source), { flag: 'wx' });
  return main(['--review', runtime, '--harness-review', filename]);
}
test('offline CLI accepts a controlled fixture that binds the actual trace module without private imports', async () => {
  const result = await validate(await fixture());
  assert.equal(result.executedLive, false); assert.equal(result.networkCalls, 0);
});
test('offline CLI rejects a missing mandatory trace source binding', async () => {
  const source = await fixture(); source.files = source.files.filter(ref => ref.path !== tracePath);
  await assert.rejects(validate(source), /CURRENT_COORDINATOR_BINDINGS_REQUIRED/);
});
test('offline CLI rejects trace source drift even when coordinator bytes match', async () => {
  const source = await fixture(); source.files.find(ref => ref.path === tracePath).sha256 = '0'.repeat(64);
  await assert.rejects(validate(source), /HARNESS_SOURCE_DRIFT/);
});
