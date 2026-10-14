import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(folder, '../../../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const observedPath = 'docs/verification/wave5/task3-completion-20261013/installed-cash-independent-verification-20261014.json';
const observedBytes = await fs.readFile(path.join(root, observedPath));
assert.equal(sha(observedBytes), '613e3f2871e023532a595c6fefec008def556dc579a92baa78b56991efbf55cf');
const observed = JSON.parse(observedBytes);
assert.equal(observed.installedMigrations, 115);
assert.equal(observed.routines.length, 2);
assert.ok(observed.routines.every(row => row.allNonBodyMetadataPreserved));
const changes = [
  {file: 'tools/wave5/runtime_contract.mjs', replacements: [
    ['requireGuard(proof.installedMigrationCount === 114 && proof.pending71Installed',
     'requireGuard(proof.installedMigrationCount === 115 && proof.pending71Installed']]},
  {file: 'tools/wave5/runtime_coordinator.test.mjs', replacements: [
    ['validUntil: iso(3600000), installedMigrationCount: 114,', 'validUntil: iso(3600000), installedMigrationCount: 115,'],
    ['for (const change of [{ installedMigrationCount: 43 }, { pending71Installed: false },',
     "for (const change of [{ installedMigrationCount: 43 }, { installedMigrationCount: 114 }, { installedMigrationCount: 116 },\n    { installedMigrationCount: 115.5 }, { installedMigrationCount: '115' }, { pending71Installed: false },"]]},
  {file: 'tools/wave5/supabase_provider.test.mjs', replacements: [
    ['installedMigrationCount: 114,', 'installedMigrationCount: 115,']]},
];
const before = [];
for (const change of changes) {
  const bytes = await fs.readFile(path.join(root, change.file));
  let text = bytes.toString('utf8');
  for (const [old, next] of change.replacements) {
    assert.equal(text.split(old).length, 2, `exact source site: ${change.file}`);
    text = text.replace(old, next);
  }
  const destination = path.join(folder, 'load-baseline-115-before', change.file);
  await fs.mkdir(path.dirname(destination), {recursive: true});
  await fs.writeFile(destination, bytes, {flag: 'wx'});
  before.push({path: change.file, bytes: bytes.length, sha256: sha(bytes),
    savedPath: path.relative(root, destination).replaceAll('\\', '/'), updatedBytes: Buffer.from(text)});
}
// Recheck all three originals before the first shared-source write.
for (const row of before) assert.equal(sha(await fs.readFile(path.join(root, row.path))), row.sha256);
const after = [];
for (const row of before) {
  await fs.writeFile(path.join(root, row.path), row.updatedBytes);
  after.push({path: row.path, bytes: row.updatedBytes.length, sha256: sha(row.updatedBytes)});
}
const report = {kind: 'installed-115-load-preflight-source-successor', appliedAt: new Date().toISOString(),
  authority: {kind: 'direct-user-delegation-and-live-owner-source-ownership-grant',
    userInstruction: "do the best things. You decide all what is good and do it. don't ask me again.",
    ownerChat: '01a121e1-81f0-76c1-8060-699f36ec225e',
    scope: 'narrow runtime_contract validator/test successor for actual installed 115-migration baseline',
    personalHumanExactSourceSignatureClaimed: false},
  installationEvidence: {path: observedPath, bytes: observedBytes.length, sha256: sha(observedBytes)},
  expectedOnlineCount: 115, historical71InstallCountRetained: 114,
  originalRuntimeReviewEdited: false, observationCountTransformed: false, migrationReplayPerformed: false,
  behavior: 'Require exactly the actual 115 ledger; reject old114, future116, fractional and string values. All other preflight requirements are unchanged.',
  before: before.map(({updatedBytes, ...binding}) => binding), after,
  independentReviewPending: true, actualNetworkRequests: 0, SQLMutations: 0, privateInputRead: false,
  fullLoadPerformed: false, productionReleaseReady: false};
const bytes = Buffer.from(JSON.stringify(report, null, 2) + '\n');
const reportPath = path.join(folder, 'load-baseline-115-source-application.json');
await fs.writeFile(reportPath, bytes, {flag: 'wx'});
process.stdout.write(JSON.stringify({applied: true, report: {path: path.relative(root, reportPath).replaceAll('\\', '/'), bytes: bytes.length, sha256: sha(bytes)}, after}) + '\n');
