import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(folder, '../../../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = async relative => {
  const bytes = await fs.readFile(path.join(root, relative));
  return {path: relative, bytes: bytes.length, sha256: sha(bytes), text: bytes.toString('utf8')};
};
const ref = ({text, ...binding}) => binding;
const file = await read('docs/verification/wave5/desktop-partitioned-20261013-o13r7/99-result.json');
const actual = JSON.parse(file.text), sourceFile = await read(actual.sourceManifest.path);
assert.equal(sourceFile.sha256, actual.sourceManifest.sha256);
const source = JSON.parse(sourceFile.text);
assert.equal(actual.kind, 'actual-complete-partitioned-desktop-test-suite');
assert.equal(actual.testFilesExecuted, 138);
assert.equal(actual.passed, 2026);
assert.equal(actual.failed, 0); assert.equal(actual.skipped, 0);
assert.equal(actual.batches.length, 23);
assert.equal(actual.sourceInputsVerified, 1069);
assert.equal(actual.allBatchesPassed, true);
const catalog = actual.batches.flatMap(batch => batch.tests);
assert.equal(catalog.length, 138); assert.equal(new Set(catalog).size, 138);
assert.deepEqual([...catalog].sort(), [...actual.completeCatalog].sort());
let passed = 0; const logs = [];
for (const batch of actual.batches) {
  assert.equal(batch.exitCode, 0); assert.equal(batch.terminalSuccess, true);
  assert.equal(batch.failed, 0); assert.equal(batch.skipped, 0);
  assert.equal(batch.sourceInputsAfter, 1069); assert.equal(batch.freshGoldenFailureMarker, false);
  const log = await read(batch.log.path);
  assert.equal(log.sha256, batch.log.sha256); assert.equal(log.bytes, batch.log.bytes);
  assert.match(log.text, /All tests passed!/);
  assert.match(log.text, new RegExp('\\+' + batch.passed + '[: ]'));
  passed += batch.passed; logs.push(ref(log));
}
assert.equal(passed, actual.passed);
const files = [];
async function walk(relative) {
  for (const entry of await fs.readdir(path.join(source.snapshot, relative), {withFileTypes: true})) {
    const next = path.posix.join(relative, entry.name);
    if (entry.isDirectory()) await walk(next);
    else if (entry.isFile() && entry.name.endsWith('_test.dart')) files.push(next.replace('apps/jentra_desktop/', ''));
  }
}
await walk('apps/jentra_desktop/test');
assert.deepEqual(files.sort(), [...actual.completeCatalog].sort());
assert.equal(Object.keys(source.baseSourceHashes).length, 1069);
assert.equal(Object.keys(source.buildSourceHashes).length, 1069);
for (const [relative, expected] of Object.entries(source.baseSourceHashes))
  assert.equal(sha(await fs.readFile(path.join(root, relative))), expected, 'current base ' + relative);
for (const [relative, expected] of Object.entries(source.buildSourceHashes))
  assert.equal(sha(await fs.readFile(path.join(source.snapshot, relative))), expected, 'tested snapshot ' + relative);
const report = {kind: 'independent-saved-full-desktop-suite-review', reviewedAt: new Date().toISOString(),
  actualRunFinishedAt: actual.finishedAt, verdict: 'Complete current desktop catalog and all saved passing batch logs verified.',
  testFiles: 138, testCasesPassed: passed, failed: 0, skipped: 0, batches: 23,
  currentBaseInputsVerified: 1069, testedSnapshotInputsVerified: 1069,
  testedSnapshot: source.snapshot, fullCatalogCoverageIndependentlyVerified: true,
  expensiveSdkTestsRepeatedByReviewer: false, authenticatedNativeAcceptance: false,
  actualNativeKeyboardAcceptance: false, restartRecoveryAcceptance: false, targetScaleLoad: false,
  productionReleaseReady: false, evidence: [ref(file), ref(sourceFile), ...logs]};
const output = path.join(folder, 'desktop-partitioned-independent-verification-20261014.json');
const bytes = Buffer.from(JSON.stringify(report, null, 2) + '\n');
await fs.writeFile(output, bytes, {flag: 'wx'});
process.stdout.write(JSON.stringify({passed: true, report: {path: path.relative(root, output).replaceAll('\\', '/'), bytes: bytes.length, sha256: sha(bytes)}}) + '\n');
