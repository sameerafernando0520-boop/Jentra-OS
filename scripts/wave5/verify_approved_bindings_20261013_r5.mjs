// Immediate local byte guard; no installation, SDK or native operation.
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateApproval} from '../../tools/wave5/runtime_contract.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const sha = value => createHash('sha256').update(value).digest('hex');
const must = (condition, message) => { if (!condition) throw Error(message); };
must(process.argv.length === 2, 'NO_ARGUMENTS_ALLOWED');
const reviewPath = base + 'complete-app-runtime-review-20261010-r5.json';
const approvalPath = base + 'runtime-owner-decision-20261012-r5.json';
const raw = await readFile(path.join(root, reviewPath));
const approvalBytes = await readFile(path.join(root, approvalPath));
const review = JSON.parse(raw), approval = JSON.parse(approvalBytes);
const {bundleSha256, ...body} = review;
must(sha(raw) === 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3' && sha(JSON.stringify(body)) === bundleSha256, 'EXACT_IMMUTABLE_REVIEW_REQUIRED');
validateApproval(approval, review, {runtimeFileSha256: sha(raw)});
must(review.artifacts.length === 5468 && review.migrations.length === 71 && review.liveBaseline.expectedLedgerAfterOnlyThisInstall === 114, 'EXACT_APPROVED_COUNTS_REQUIRED');
const startedAt = new Date().toISOString(), failures = [], checked = [];
const verify = async binding => {
  try {
    const bytes = await readFile(path.isAbsolute(binding.path) ? binding.path : path.join(root, binding.path));
    const actual = sha(bytes);
    checked.push({path: binding.path, sha256: actual, bytes: bytes.length});
    if (actual !== binding.sha256) failures.push({path: binding.path, expected: binding.sha256, actual, reason: 'hash-mismatch'});
  } catch (error) { failures.push({path: binding.path, reason: error.code || 'unreadable'}); }
};
for (let i = 0; i < review.artifacts.length; i += 12) await Promise.all(review.artifacts.slice(i, i + 12).map(verify));
for (const migration of review.migrations) await verify(migration);
must(sha(await readFile(path.join(root, reviewPath))) === sha(raw) && sha(await readFile(path.join(root, approvalPath))) === sha(approvalBytes), 'BINDING_FILES_CHANGED_DURING_CHECK');
const result = {kind: 'wave5-approved-runtime-immediate-byte-check', startedAt, finishedAt: new Date().toISOString(),
  runtimeBundleSha256: bundleSha256, runtimeFileSha256: sha(raw), projectId: review.projectId,
  ownerDecision: {path: approvalPath, sha256: sha(approvalBytes)},
  approvedArtifacts: review.artifacts.length, approvedMigrationFiles: review.migrations.length,
  inspectedBindings: checked.length, matchedBindings: checked.length - failures.filter(x => x.reason === 'hash-mismatch').length,
  failures, passed: failures.length === 0, livePreflightPerformed: false, liveOperationsPerformed: false, sdkJobsExecuted: false,
  originalSixReinstalled: false, ownerAcceptanceChanged: false, checked};
const bytes = Buffer.from(JSON.stringify(result, null, 2) + '\n');
const out = base + 'approved-runtime-byte-check-20261013-r5.json';
await writeFile(path.join(root, out), bytes, {flag: 'wx'});
console.log(JSON.stringify({path: out, sha256: sha(bytes), passed: result.passed, inspectedBindings: result.inspectedBindings, failures}));
if (!result.passed) process.exitCode = 1;
