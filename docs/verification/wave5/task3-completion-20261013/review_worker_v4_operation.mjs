import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(folder, '../../../..');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = async relative => {
  assert.ok(!path.isAbsolute(relative) && !relative.split('/').includes('..'));
  const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, bytes: bytes.length, sha256: hash(bytes), text: bytes.toString('utf8') };
};
const ref = ({ text, ...binding }) => binding;
const reviewFile = await read('docs/verification/wave5/worker-v4-diagnostic-runtime-review-20261014-r5.json');
assert.equal(reviewFile.sha256, 'c0a10d1722df154a460e67ba5eff876e0396c1e2acf52edeb8c79a6b03a21f72');
const review = JSON.parse(reviewFile.text);
const { bundleSha256, ...body } = review;
assert.equal(hash(JSON.stringify(body)), bundleSha256);
assert.equal(bundleSha256, 'd2c5ae38aefcb8120ea3b3ca85520c142eb79f0c9e14f1f902ae9fc84c34c4c4');
assert.equal(review.projectId, 'xpdoufauvrbdmxgngetv');
assert.equal(review.routeAllowlistExpanded, false);
assert.equal(review.httpRoutesAllowed, false);
assert.equal(review.customAuthenticationUnchanged, true);
assert.equal(review.schedulesMustRemainPaused, true);
assert.equal(review.maximumDiagnosticsPerIsolate, 1);
assert.equal(review.privateOrRawRequestDataLogged, false);
assert.equal(review.retainedLimits.maximumModelCalls, 4);
assert.equal(review.retainedLimits.maximumScheduleRequestsOriginal, 4320);
for (const key of ['newUsers', 'newPermissions', 'newSecrets', 'newDestinations']) assert.equal(review.retainedLimits[key], 0);
assert.equal(review.retainedLimits.extendedExpiry, false);
assert.equal(review.production, false);
assert.equal(review.realBilling, false);
assert.equal(review.additionalRequirementAcceptance, 0);
assert.deepEqual(review.deployments.map(item => item.name), ['wave5-runtime', 'wave5-receiver']);
const sourceReviewFile = await read('docs/verification/wave5/task3-completion-20261013/worker-v4-independent-source-review.json');
const sourceReview = JSON.parse(sourceReviewFile.text);
assert.equal(sourceReview.technicalVerdict, 'approved for the bounded diagnostic-only development successor');
const evidence = [];
for (const binding of [review.sourcePreparation, ...review.evidence]) {
  const actual = await read(binding.path);
  assert.equal(actual.sha256, binding.sha256, binding.path);
  assert.equal(actual.bytes, binding.bytes, binding.path);
  evidence.push(ref(actual));
}
const files = [], payloads = [];
for (const deployment of review.deployments) {
  const payloadFile = await read(deployment.payload.path);
  assert.equal(payloadFile.sha256, deployment.payload.sha256);
  assert.equal(payloadFile.bytes, deployment.payload.bytes);
  const payload = JSON.parse(payloadFile.text);
  assert.deepEqual(Object.keys(payload).sort(), ['entrypoint_path', 'files', 'name', 'project_id', 'verify_jwt']);
  assert.equal(payload.project_id, review.projectId);
  assert.equal(payload.name, deployment.name);
  assert.equal(payload.entrypoint_path, deployment.entrypoint);
  assert.equal(payload.verify_jwt, false);
  assert.equal(payload.files.length, deployment.name === 'wave5-runtime' ? 15 : 9);
  assert.equal(new Set(payload.files.map(item => item.name)).size, payload.files.length);
  assert.deepEqual(payload.files.map(item => item.name).sort(), deployment.files.map(item => item.path).sort());
  const oldPayload = JSON.parse((await read(`docs/verification/wave5/supabase-deploy-${deployment.name}-platform-origin-v3-20261013-r5.json`)).text);
  assert.equal(oldPayload.files.length, payload.files.length);
  assert.deepEqual(oldPayload.files.map(item => item.name.replaceAll('20261013_r5_v3', '20261014_r5_v4')).sort(), payload.files.map(item => item.name).sort());
  for (const file of deployment.files) {
    const actual = await read(file.path);
    assert.equal(actual.sha256, file.sha256, file.path);
    assert.equal(actual.bytes, file.bytes, file.path);
    const embedded = payload.files.find(item => item.name === file.path);
    assert.equal(embedded.content, actual.text, file.path);
    const oldEmbedded = oldPayload.files.find(item => item.name.replaceAll('20261013_r5_v3', '20261014_r5_v4') === file.path);
    if (!file.path.includes('20261014_r5_v4')) assert.equal(embedded.content, oldEmbedded.content, file.path);
    files.push({ worker: deployment.name, ...ref(actual), payloadContentSha256: hash(embedded.content) });
  }
  payloads.push(ref(payloadFile));
}
const result = {
  kind: 'primary-independent-complete-worker-v4-operation-review',
  reviewedAt: new Date().toISOString(), projectId: review.projectId,
  technicalVerdict: 'approved within the verified delegated diagnostic development scope',
  runtimeBundleSha256: bundleSha256,
  operationReview: ref(reviewFile),
  sourceReview: ref(sourceReviewFile),
  payloads, payloadFileRowsVerified: files.length, files,
  evidenceBindingsVerified: evidence,
  originalV3PayloadClosureRetained: true,
  unchangedPayloadModulesExactlyPreserved: true,
  sourceContentEqualsPayloadContent: true,
  routeAllowlistExpanded: false, httpRoutesAllowed: false,
  customAuthenticationUnchanged: true,
  maximumUnauthenticatedDiagnosticProbes: 1,
  schedulesMustRemainPaused: true,
  expiryOrOperationalCapsExtended: false,
  authority: 'Direct user delegation retained in resumed-autonomy-delegation.json; concrete source and payload decision made by the primary agent.',
  personalHumanExactSourceSignatureClaimed: false,
  deploymentPerformedByThisReview: false,
  networkCalls: 0, privateCredentialsRead: false, acceptanceDecisionsAdded: 0,
  production: false, realBilling: false,
  nextBoundedAction: 'Live owner records its delegated operation decision, deploys only these exact two payloads, verifies all returned modules and People preservation, sends at most one diagnostic probe and retains the schedule pause.'
};
const text = JSON.stringify(result, null, 2) + '\n';
await fs.writeFile(path.join(folder, 'worker-v4-independent-operation-review.json'), text, { flag: 'wx' });
process.stdout.write(JSON.stringify({ approved: true, payloadRows: files.length, bundleSha256, artifactSha256: hash(text) }) + '\n');
