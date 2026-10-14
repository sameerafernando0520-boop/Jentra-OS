import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const output = 'docs/verification/wave5/task3-acceptance-20261013';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const bytes = name => fs.readFileSync(path.resolve(root, name));
const bind = name => ({path: name, bytes: bytes(name).length, sha256: sha(bytes(name))});
const json = name => JSON.parse(bytes(name));
const applicationPath = 'docs/verification/wave5/task3-completion-20261013/load-baseline-115-source-application.json';
const installationPath = 'docs/verification/wave5/task3-completion-20261013/installed-cash-independent-verification-20261014.json';
const predecessorPath = 'docs/verification/wave5/task3-peer-review-20261013/runtime-harness-review-20261013-peer-a2.json';
assert.equal(bind(applicationPath).sha256, '8a5427720e6288bc386dd18883026e8298ea22a37c82caadf459a31f437197e0');
assert.equal(bind(installationPath).sha256, '613e3f2871e023532a595c6fefec008def556dc579a92baa78b56991efbf55cf');
const application = json(applicationPath), installed = json(installationPath), predecessor = json(predecessorPath);
const changes = [
  {path: 'tools/wave5/runtime_contract.mjs', replacements: [
    ['requireGuard(proof.installedMigrationCount === 114 && proof.pending71Installed',
      'requireGuard(proof.installedMigrationCount === 115 && proof.pending71Installed']]},
  {path: 'tools/wave5/runtime_coordinator.test.mjs', replacements: [
    ['validUntil: iso(3600000), installedMigrationCount: 114,', 'validUntil: iso(3600000), installedMigrationCount: 115,'],
    ['for (const change of [{ installedMigrationCount: 43 }, { pending71Installed: false },',
      "for (const change of [{ installedMigrationCount: 43 }, { installedMigrationCount: 114 }, { installedMigrationCount: 116 },\n    { installedMigrationCount: 115.5 }, { installedMigrationCount: '115' }, { pending71Installed: false },"]]},
  {path: 'tools/wave5/supabase_provider.test.mjs', replacements: [['installedMigrationCount: 114,', 'installedMigrationCount: 115,']]},
];
const reviewedChanges = [];
for (const change of changes) {
  const before = application.before.find(row => row.path === change.path), after = application.after.find(row => row.path === change.path);
  assert.ok(before && after); assert.equal(bind(before.savedPath).sha256, before.sha256);
  assert.equal(bind(change.path).sha256, after.sha256); assert.equal(bind(change.path).bytes, after.bytes);
  let expected = bytes(before.savedPath).toString('utf8');
  for (const [original, replacement] of change.replacements) {
    assert.equal(expected.split(original).length - 1, 1, `${change.path} unique approved source site`);
    expected = expected.replace(original, replacement);
  }
  assert.deepEqual(Buffer.from(expected), bytes(change.path), `${change.path} exact permitted minimal diff`);
  const predecessorBinding = [...predecessor.files, ...predecessor.contractSources].find(row => row.path === change.path);
  if (predecessorBinding) assert.equal(predecessorBinding.sha256, before.sha256);
  reviewedChanges.push({path: change.path, preservedBefore: bind(before.savedPath), current: bind(change.path),
    exactPermittedDeltaOnly: true, sourceSitesChanged: change.replacements.length});
}
const contract = bytes(changes[0].path).toString('utf8');
assert.equal((contract.match(/proof\.installedMigrationCount === 115/g) ?? []).length, 1);
assert.ok(contract.includes('review.liveBaseline.expectedLedgerAfterOnlyThisInstall === 114'));
assert.ok(!contract.includes('proof.installedMigrationCount === 114'));
const runtimePath = predecessor.runtimeReview.path, runtime = json(runtimePath);
assert.equal(bind(runtimePath).sha256, predecessor.runtimeReview.sha256);
assert.equal(runtime.liveBaseline.expectedLedgerAfterOnlyThisInstall, 114);
assert.equal(runtime.liveBaseline.migrations, 43);
assert.equal(runtime.migrations.length, 71);
assert.equal(runtime.ownerApproved, false);
const readbackPath = 'docs/verification/wave5/task3-completion-20261013/installed-cash-independent-readback-20261014.json';
const beforeCashPath = 'docs/verification/wave5/cash-conflict-live-before-installation-20261014-r5.json';
const afterCashPath = 'docs/verification/wave5/cash-conflict-live-after-installation-20261014-r5.json';
const candidatePath = 'docs/verification/wave5/task3-peer-review-20261013/cash-conflict-independent-source-review-20261013-peer-a1.json';
for (const evidence of installed.evidence) assert.equal(bind(evidence.path).sha256, evidence.sha256);
function returnedRows(document) {
  assert.equal(document.result.isError, false);
  const envelope = JSON.parse(document.result.content.find(item => item.type === 'text').text).result;
  const opening = envelope.match(/<untrusted-data-[^>]+>(?:\s|\\n)*(?=\[|\{)/);
  assert.ok(opening);
  const start = opening.index + opening[0].length, end = envelope.indexOf('</untrusted-data-', start);
  assert.ok(end > start);
  const raw = envelope.slice(start, end).replace(/(?:\s|\\n)+$/, '');
  try { return JSON.parse(raw); } catch { return JSON.parse(JSON.parse('"' + raw + '"')); }
}
const [observed] = returnedRows(json(readbackPath));
const beforeCash = returnedRows(json(beforeCashPath)), afterCash = returnedRows(json(afterCashPath));
const candidate = json(candidatePath);
assert.equal(observed.installed_migrations, 115); assert.equal(observed.api_functions, 363);
assert.equal(installed.installedMigrations, observed.installed_migrations); assert.equal(installed.apiFunctions, observed.api_functions);
assert.equal(observed.repaired_routines.length, 2);
const routines = [];
for (const row of observed.repaired_routines) {
  const before = beforeCash.find(old => old.proname === row.proname), after = afterCash.find(item => item.proname === row.proname);
  const derivation = candidate.derivations.find(item => item.signature.startsWith(`api.${row.proname}(`));
  assert.ok(before && after && derivation);
  assert.equal(row.body_lf_sha256, derivation.afterNormalizedBodySha256);
  assert.equal(row.definition_md5, after.definition_md5);
  assert.deepEqual(row.preserved_metadata, before.preserved_metadata); assert.deepEqual(row.preserved_metadata, after.preserved_metadata);
  assert.equal(row.security_definer, true); assert.deepEqual(row.configuration, ['search_path=""']);
  routines.push({name: row.proname, observedBodySha256: row.body_lf_sha256, matchesReviewedBody: true, nonBodyMetadataUnchanged: true});
}
assert.deepEqual(observed.reviewed_schedule_state, [4, 5, 6].map(jobid => ({jobid, active: false})));
const oldBody = {...predecessor}; delete oldBody.reviewBodySha256;
assert.equal(sha(JSON.stringify(oldBody)), predecessor.reviewBodySha256);
const report = {
  kind: 'independent-115-online-preflight-minimal-source-review', reviewedAt: new Date().toISOString(),
  reviewer: 'Codex requirement_acceptance independent reviewer; patch authored by root',
  technicalVerdict: 'approved within the unchanged bounded synthetic runtime scope',
  personalHumanSignatureClaimed: false, implementationAuthoredByThisReviewer: false,
  application: bind(applicationPath), installationProof: bind(installationPath), predecessor: bind(predecessorPath),
  exactMinimalSourceDeltaVerified: true, reviewedChanges,
  onlineRequiredMigrationCount: 115, historicalOriginal43Plus71ExpectationRetained: 114,
  immutableApprovedRuntimeReviewUnchanged: bind(runtimePath), observationsRewritten: false,
  negativeCasesReviewed: [43, 114, 116, 115.5, '115'],
  reasoning: 'The observed ledger gained the separately installed cash conflict repair. Strict online equality now requires number 115; the immutable historical 43+71 installation review still correctly says 114. No other authorization, source fingerprint, actor, capacity, population, freshness, quiescence or load guard changed.',
  independentRecordedEvidenceReadback: {observedAt: observed.observed_at, installedMigrations: 115, apiFunctions: 363,
    routines, schedulesPaused: [4, 5, 6], evidenceBindings: [readbackPath, beforeCashPath, afterCashPath, candidatePath].map(bind),
    boundary: 'This reviewer independently parsed and compared the recorded connector readback; no fresh network query or broad live fingerprint/online capacity certification was performed.'},
  remainingGates: ['Current full ledger/signature/grant/RLS and protected-source preflight',
    'Actual private provider/dependency/plan preparation bindings', 'Genuine online 2,000-session population and required MFA',
    'Complete quiescence and actual no-egress observation', 'Every independent committed race and target workload P95',
    'All actual limit fixtures, native authentication/keyboard/recovery and production release'],
  networkCalls: 0, privateInputRead: false, SQLWrites: 0, SDKJobs: 0, sharedSourceEdits: [],
  acceptanceDecisionsAdded: 0, productionReleaseReady: false,
};
const recordPath = `${output}/load-baseline-115-independent-review.json`;
fs.writeFileSync(path.resolve(root, recordPath), JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify({passed: true, report: bind(recordPath), sources: reviewedChanges.map(row => row.current)}, null, 2));
