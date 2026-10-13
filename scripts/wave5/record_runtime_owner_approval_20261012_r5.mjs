// Record the actual human reply separately from the immutable reviewed packet.
// This script cannot infer approval or alter that packet.
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateApproval} from '../../tools/wave5/runtime_contract.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const reviewPath = base + 'complete-app-runtime-review-20261010-r5.json';
const sha = value => createHash('sha256').update(value).digest('hex');
const must = (condition, message) => { if (!condition) throw Error(message); };
must(process.argv.length === 2, 'NO_ARGUMENTS_ALLOWED');
const raw = await readFile(path.join(root, reviewPath));
const review = JSON.parse(raw);
const expectedFile = 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3';
const expectedBundle = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
const scope = 'fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63';
const {bundleSha256, ...body} = review;
must(sha(raw) === expectedFile && sha(JSON.stringify(body)) === expectedBundle && bundleSha256 === expectedBundle, 'EXACT_REVIEW_REQUIRED');
must(review.sourceContinuation.unchangedRuntimeOperationScopeSha256 === scope && review.migrations.length === 71 && review.accounts.length === 6 && review.syntheticScopes.length === 500, 'EXACT_APPROVED_SCOPE_REQUIRED');
const reply = [{
  questionItemId: '["request_user_input_async","call_jWM2s7uP5XYGWSTfgZGkFgLq",0]',
  question: 'Do you approve the exact isolated runtime test setup in [the owner review](<C:/Users/sheha/Desktop/Jentra OS/dist/Jentra OS Runtime Approval 20261012 r5 a2.html>)? Bundle SHA-256: db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b. It covers 71 pending migrations on xpdoufauvrbdmxgngetv (excluding the six installed), six private Auth Admin test accounts, 500 synthetic company scopes, a separate Windows test profile, the reviewed workers/Vault/schedules, at most four bounded model calls, and genuine MFA/delivery/export/contention/load checks. Existing accounts and sessions are preserved; production and real billing stay excluded. This approval is required by your original instruction to execute these steps only after approval. It does not accept the remaining 106 requirements; I will test the accounting workflows for you.',
  answer: 'Approve the exact bounded test setup'
}];
const recordedAt = new Date().toISOString();
const record = {
  kind: 'wave5-runtime-owner-decision', decision: 'approve',
  source: {kind: 'direct_user_message', reference: reply[0].questionItemId,
    messageSha256: sha(JSON.stringify(reply)), hashEncoding: 'SHA-256 of UTF-8 JSON.stringify of the preserved reply array', preservedReply: reply},
  approvedAt: recordedAt, approvedAtBasis: 'Actual recording time of the received direct human approval; original message timestamp is not available.',
  runtimeBundleSha256: expectedBundle, runtimeFileSha256: expectedFile,
  operationScopeSha256: scope, projectId: 'xpdoufauvrbdmxgngetv',
  production: false, realBilling: false, installOriginalSix: false, noGlobalAuthChanges: true,
  reviewedPacket: {path: reviewPath, sha256: sha(raw)},
  humanPage: {path: 'dist/Jentra OS Runtime Approval 20261012 r5 a2.html', sha256: '32ba73f8ea4ca1c605ce25d73b88a663c9d2802b73ed5cfb137e296e1da01fa8'},
  pendingMigrationsApproved: 71, testAccountsApproved: 6, syntheticScopesApproved: 500,
  maximumModelInvocations: 4, existingAccountsAndSessionsPreserved: true,
  ownerAcceptedCriteria: 3, additionalCriteriaAccepted: 0,
  installationPerformedByThisRecorder: false, runtimeEvidencePromotedByThisRecorder: false
};
validateApproval(record, review, {runtimeFileSha256: expectedFile});
const pageBytes = await readFile(path.join(root, record.humanPage.path));
must(sha(pageBytes) === record.humanPage.sha256, 'HUMAN_REVIEW_BYTES_CHANGED');
const bytes = Buffer.from(JSON.stringify(record, null, 2) + '\n');
const out = base + 'runtime-owner-decision-20261012-r5.json';
await writeFile(path.join(root, out), bytes, {flag: 'wx'});
must(sha(await readFile(path.join(root, reviewPath))) === expectedFile, 'FROZEN_REVIEW_CHANGED');
console.log(JSON.stringify({path: out, sha256: sha(bytes), approvedAt: recordedAt, decision: record.decision, additionalCriteriaAccepted: 0, liveOperations: false}));
