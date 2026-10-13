import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { hashBytes, hashJson, PROJECT_ID, validateRuntimeReview, validateApproval } from './runtime_contract.mjs';

// Pure file/content audit. No SQL, query execution, account, SDK, network or UI.
const root = fileURLToPath(new URL('../../', import.meta.url));
const read = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { value: JSON.parse(bytes), ref: { path: relative, bytes: bytes.length, sha256: hashBytes(bytes) } }; };
const runtime = await read('docs/verification/wave5/complete-app-runtime-review-20261010-r5.json');
const owner = await read('docs/verification/wave5/runtime-owner-decision-20261012-r5.json');
const original = await read('docs/verification/wave5/installed-verification-plan-20261012-r5.json');
const successor = await read('docs/verification/wave5/installed-verification-plan-20261012-r5-a2.json');
validateRuntimeReview(runtime.value);
validateApproval(owner.value, runtime.value, { runtimeFileSha256: runtime.ref.sha256 });
assert.equal(successor.value.originalPlan.sha256, original.ref.sha256);
assert.equal(successor.value.review.fileSha256, runtime.ref.sha256);
assert.equal(successor.value.review.bundleSha256, runtime.value.bundleSha256);
const counts = { functionBodyExpectations: original.value.sourceFunctionInventory.length,
  directlyCreatedTables: original.value.sourceTableInventory.length,
  forceRlsPredicates: original.value.forcedRlsPredicates.length, grantPredicates: original.value.grantPredicates.length };
assert.deepEqual(counts, { functionBodyExpectations: 541, directlyCreatedTables: 215, forceRlsPredicates: 72, grantPredicates: 18 });
assert.equal(original.value.migrationInputs.length, 71);
const bindings = [];
for (const input of original.value.migrationInputs) {
  const approved = runtime.value.migrations.find(row => row.order === input.order);
  assert.ok(approved && approved.path === input.path && approved.sha256 === input.sha256);
  const bytes = await fs.readFile(path.join(root, input.path)); assert.equal(hashBytes(bytes), input.sha256);
  bindings.push({ path: input.path, sha256: hashBytes(bytes), bytes: bytes.length });
}
const queryBindings = [];
for (const query of successor.value.queries) {
  const bytes = await fs.readFile(path.join(root, query.path)), text = bytes.toString('utf8');
  assert.equal(hashBytes(bytes), query.sha256); assert.equal(bytes.length, query.bytes);
  assert.match(text.trim(), /^--|^BEGIN/i);
  assert.match(text.trim(), /ROLLBACK;$/i);
  assert.doesNotMatch(text, /\b(?:net\.http_post|vault\.create_secret|cron\.schedule|INSERT INTO auth\.|DELETE FROM auth\.|UPDATE auth\.)/i);
  queryBindings.push({ path: query.path, sha256: hashBytes(bytes), bytes: bytes.length, executed: false });
}
const body = { kind: 'independent-wave5-installed-plan-file-audit', observedAt: new Date().toISOString(), projectId: PROJECT_ID,
  runtime: runtime.ref, ownerDecision: owner.ref, originalPlan: original.ref, successorPlan: successor.ref,
  counts, migrationInputsMatched: 71, migrationBindings: bindings, migrationBindingDigestSha256: hashJson(bindings), queryBindings,
  passed: true, filesOnly: true, sqlExecuted: false, databaseCalls: 0, networkCalls: 0,
  authChanged: false, sourceChanged: false, sdkJobs: 0, nativeActions: 0, ownerAcceptedCriteria: 3, ownerCriteria: 109,
  installedSchemaVerified: false, dynamicRlsCoverageVerified: false,
  limitation: 'Checks current file bindings and prepared inventory counts only. Root must obtain actual installed catalog, strict metadata, preservation and baseline rename observations. No installed result or runtime acceptance is asserted.' };
const destination = 'docs/verification/wave5/installed-verification-plan-peer-audit-20261013-r5.json';
const bytes = JSON.stringify(body, null, 2) + '\n';
await fs.writeFile(path.join(root, destination), bytes, { flag: 'wx', mode: 0o600 });
process.stdout.write(JSON.stringify({ path: destination, sha256: hashBytes(bytes), passed: true, counts, migrationInputsMatched: 71 }) + '\n');
