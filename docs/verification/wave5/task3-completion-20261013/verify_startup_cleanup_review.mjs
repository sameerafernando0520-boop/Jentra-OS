import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const folder = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(folder, '../../../..');
const peer = 'docs/verification/wave5/task3-peer-review-20261013';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = async relative => {
  const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, bytes: bytes.length, sha256: sha(bytes), text: bytes.toString('utf8') };
};
const ref = ({ text, ...binding }) => binding;
const beforeCode = await read(`${peer}/harness-startup-cleanup-before-a2/tools/wave5/runtime_coordinator.mjs`);
const beforeTests = await read(`${peer}/harness-startup-cleanup-before-a2/tools/wave5/runtime_coordinator.test.mjs`);
const code = await read('tools/wave5/runtime_coordinator.mjs');
const tests = await read('tools/wave5/runtime_coordinator.test.mjs');
const oldStart = "  await journal({ type: 'live-start', ...report });\n  try {\n";
const newStart = "  try {\n    await journal({ type: 'live-start', ...report });\n";
assert.equal(beforeCode.text.split(oldStart).length, 2);
assert.equal(code.text, beforeCode.text.replace(oldStart, newStart));
assert.ok(tests.text.startsWith(beforeTests.text));
assert.match(tests.text.slice(beforeTests.text.length), /failed durable live-start journaling clears the run timer/);
const verificationFile = await read(`${peer}/runtime-harness-local-verification-20261013-peer-a2.json`);
const verification = JSON.parse(verificationFile.text);
assert.equal(verification.childExitCode, 0);
assert.equal(verification.summary.tests, 41);
assert.equal(verification.summary.passed, 41);
for (const key of ['failed', 'skipped', 'cancelled', 'todo']) assert.equal(verification.summary[key], 0);
const log = await read(verification.log.path);
assert.equal(log.sha256, verification.log.sha256);
assert.match(log.text, /^# tests 41$/m);
assert.match(log.text, /^# pass 41$/m);
assert.match(log.text, /^# fail 0$/m);
const harnessFile = await read(`${peer}/runtime-harness-review-20261013-peer-a2.json`);
const harness = JSON.parse(harnessFile.text);
const checked = [];
for (const binding of [...harness.files, ...harness.contractSources]) {
  const actual = await read(binding.path);
  assert.equal(actual.sha256, binding.sha256, binding.path);
  assert.equal(actual.bytes, binding.bytes, binding.path);
  checked.push(ref(actual));
}
assert.equal(new Set(checked.map(item => item.path)).size, checked.length);
assert.equal(harness.operationScopeChanged, false);
assert.equal(harness.additionalOwnerAuthorizationForCoordinatorHashesRequired, false);
assert.equal(harness.executedLive, false);
const offlineFile = await read(`${peer}/runtime-harness-offline-validation-20261013-peer-a2.json`);
const offline = JSON.parse(offlineFile.text);
assert.equal(offline.childExitCode, 0);
assert.equal(offline.harness.sha256, harnessFile.sha256);
assert.equal(offline.result.mode, 'offline-validation');
assert.equal(offline.result.executedLive, false);
assert.equal(offline.result.networkCalls, 0);
const result = {
  kind: 'primary-independent-runtime-startup-cleanup-review',
  reviewedAt: new Date().toISOString(),
  projectId: 'xpdoufauvrbdmxgngetv',
  reviewer: 'Primary Codex agent; implementation authored by completion_peer',
  technicalVerdict: 'approved within the unchanged reviewed runtime operation scope',
  personalHumanSignatureClaimed: false,
  exactPreservedBeforeDeltaVerified: true,
  exactFrozenR6DeltaClaimed: false,
  change: 'Move the first durable live-start journal write into the existing cleanup try/finally.',
  reasoning: 'Any first-write failure now follows the existing catch/finally: the run controller aborts, the 900-second timer is cleared and the provider closes while preserving unknown effects. Failure of the final write remains a rejected run. No provider preflight, session setup or dispatch starts after a failed initial write.',
  regressionReviewed: {
    failedStartAndFinishWrites: true,
    timerClearedExactlyOnce: true,
    providerClosedExactlyOnce: true,
    noProviderOperations: true,
    allLiveGatesRemainFalse: true,
    restorationOfTimerGlobalsInFinally: true,
    failedRegressionAgainstOldSourceRemainsBounded: true
  },
  localVerification: { ...ref(verificationFile), childExitCode: 0, summary: verification.summary, log: ref(log) },
  offlineValidation: { ...ref(offlineFile), childExitCode: 0, executedLive: false },
  harness: ref(harnessFile),
  before: [ref(beforeCode), ref(beforeTests)],
  after: [ref(code), ref(tests)],
  currentSourceBindingsChecked: checked,
  networkCalls: 0, liveWrites: 0, sdkJobs: 0, nativeActions: 0,
  acceptanceDecisionsAdded: 0,
  boundary: 'Current source, saved actual Node results and offline validation only; genuine load, authenticated native acceptance and production release remain separate.'
};
await fs.writeFile(path.join(folder, 'startup-cleanup-independent-review.json'), JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
process.stdout.write(JSON.stringify({ approved: true, checkedSourceBindings: checked.length, localTests: 41, offlineValidationPassed: true, artifact: 'startup-cleanup-independent-review.json', sha256: sha(Buffer.from(JSON.stringify(result, null, 2) + '\n')) }) + '\n');
