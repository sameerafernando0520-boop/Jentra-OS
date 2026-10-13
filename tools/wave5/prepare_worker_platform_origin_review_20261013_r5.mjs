import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT, BUNDLE, loadApprovedInputs, decodePublicResult } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const base = 'docs/verification/wave5/';
const must = (ok, code) => { if (!ok) throw Error(code); };
const pins = [
  [base + 'worker-platform-origin-v3-candidate-review-20261013-r5.json', '8ff87014c4de9931c1df5d9e638982aec89c9834d5954bd39a5745ad4857305a'],
  [base + 'worker-platform-origin-v3-whole-suite-20261013-r5-a2.log', '8c6860bd7a71cdd07f75bd366cade599a4d80c108fb9359f6cccdc1f84a71e4f'],
  [base + 'worker-platform-origin-v3-runtime-deno-20261013-r5-a2.log', '07a7a1cafaa5bc4e022031725f54a4139a22e60b373c653b15b091bfa1057e9b'],
  [base + 'worker-platform-origin-v3-receiver-deno-20261013-r5-a2.log', '2f8c516e66c62db00be3fd5cd4f018b70c6fd40f6dbdaee407ac60fc81c88888'],
  [base + 'worker-routing-deployment-source-verification-20261013-r5.json', 'a3032f6c0e137bbc05723b63d32ba6f3f4d014404ff1510c3a2b532f54fc2c0f'],
  [base + 'runtime-global-readonly-snapshot-20261013-r5-a3.json', 'ba0a22befcfc2b6333d7ada1fec01ce584ec49a4dda4422ce0eec7924a6f14fa'],
];
await loadApprovedInputs();
const inputs = new Map();
for (const [file, sha256] of pins) {
  const bytes = await fs.readFile(path.join(root, file));
  must(hashBytes(bytes) === sha256, 'EXACT_PLATFORM_REVIEW_EVIDENCE_REQUIRED');
  inputs.set(file, bytes);
}
const sourcePacket = JSON.parse(inputs.get(pins[0][0]));
must(hashBytes(JSON.stringify(sourcePacket.bundlePayload)) === sourcePacket.bundleSha256, 'EXACT_V3_SOURCE_PACKET_REQUIRED');
for (const binding of sourcePacket.bundlePayload.sourceFiles) {
  must(hashBytes(await fs.readFile(path.join(root, binding.path))) === binding.sha256, 'V3_CANDIDATE_SOURCE_CHANGED');
}
const suite = inputs.get(pins[1][0]).toString('utf8');
must(/tests 240\s/.test(suite) && /pass 240\s/.test(suite) && /fail 0\s/.test(suite) && /skipped 0\s/.test(suite), 'FRESH_WHOLE_WORKER_TESTS_REQUIRED');
for (const [file] of pins.slice(2, 4)) {
  const log = inputs.get(file).toString('utf8');
  must(log.includes('Check ') && !log.includes('[ERROR]') && !log.includes('error:'), 'FRESH_REPAIRED_DENO_ENTRYPOINT_REQUIRED');
}
const live = decodePublicResult(JSON.parse(inputs.get(pins[5][0])).result)[0].snapshot;
must(live.migrationCount === 114 && live.apiFunctionCount === 363 && live.netResponseCount === 24 && live.allKnownHandler404
  && live.ownJobs.length === 3 && live.ownJobs.every(job => !job.active)
  && ['ticks', 'deliveryOutcomes', 'receiverReceipts', 'quotaPeriods'].every(key => live[key] === 0), 'EXACT_FAILED_ROUTING_V2_STATE_REQUIRED');
const deployments = [];
async function binding(file) {
  const bytes = await fs.readFile(path.join(root, file));
  return { path: file, bytes: bytes.length, sha256: hashBytes(bytes) };
}
async function save(file, value) {
  const bytes = JSON.stringify(value, null, 2) + '\n';
  const handle = await fs.open(path.join(root, file), 'wx');
  try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
  return { path: file, bytes: Buffer.byteLength(bytes), sha256: hashBytes(bytes) };
}
for (const name of ['wave5-runtime', 'wave5-receiver']) {
  const entrypoint = `supabase/functions/${name}/index_20261013_r5_v3.ts`;
  const config = `supabase/functions/${name}/deno.json`;
  const closure = new Map();
  async function visit(file) {
    if (closure.has(file)) return;
    must(/^(supabase\/functions|workers\/wave5)\//.test(file) && !file.split('/').includes('..'), 'FIXED_V3_DEPENDENCY_ROOT_REQUIRED');
    const content = await fs.readFile(path.join(root, file), 'utf8');
    closure.set(file, content);
    for (const match of content.matchAll(/(?:from\s+|import\s*)['"](\.{1,2}\/[^'"]+)['"]/g)) {
      await visit(path.posix.normalize(path.posix.join(path.posix.dirname(file), match[1])));
    }
  }
  await visit(entrypoint);
  closure.set(config, await fs.readFile(path.join(root, config), 'utf8'));
  const original = JSON.parse(await fs.readFile(path.join(root, base + `supabase-deploy-${name}-20261009-r14.json`), 'utf8'));
  for (const file of original.files) {
    if (file.name.endsWith('/index.ts') || ['workers/wave5/edge_runtime.mjs', 'workers/wave5/edge_receiver.mjs'].includes(file.name)) continue;
    await visit(file.name);
  }
  const files = [...closure].sort(([a], [b]) => a.localeCompare(b)).map(([name, content]) => ({ name, content }));
  const payload = { project_id: PROJECT, name, entrypoint_path: entrypoint, verify_jwt: false, files };
  const payloadBinding = await save(base + `supabase-deploy-${name}-platform-origin-v3-20261013-r5.json`, payload);
  deployments.push({ name, entrypoint, verifyJwt: false, customAuthenticationUnchanged: true,
    files: await Promise.all(files.map(file => binding(file.name))), payload: payloadBinding });
}
must(deployments[0].files.length === 15 && deployments[1].files.length === 9, 'EXACT_V3_DEPLOYMENT_CLOSURES_REQUIRED');
const testedSource = [];
for (const file of (await fs.readdir(path.join(root, 'workers/wave5'))).filter(file => file.endsWith('.mjs')).sort()) {
  testedSource.push(await binding('workers/wave5/' + file));
}
for (const deployment of deployments) {
  testedSource.push(await binding(deployment.entrypoint));
  testedSource.push(await binding(`supabase/functions/${deployment.name}/deno.json`));
}
const verification = { kind: 'root-fresh-platform-origin-v3-local-verification', recordedAt: new Date().toISOString(),
  actualExecChunkId: 'e87a96', passed: true, tests: 240, failed: 0, skipped: 0, testConcurrency: 1,
  deno: { version: '2.9.7', runtimeExitCode: 0, receiverExitCode: 0, executableSha256: 'e020f3e232bd16e33768dee528e5983349c962952051ced0a5d58ad42f5d9b33',
    importedJavaScriptTypeChecked: false, javaScriptVerification: '240 passing Node tests' },
  firstCompilerFailurePreserved: true, repairedCallbackType: 'unknown', logs: pins.slice(1, 4).map(([path, sha256]) => ({ path, sha256 })),
  sourcePacket: { path: pins[0][0], sha256: pins[0][1] }, testedSource, liveOperationsPerformed: false,
  deploymentsPerformed: false, authenticatedNative: false, nativeKeyboard: false, actualDelivery: false, ownerAcceptance: false };
const verificationBinding = await save(base + 'worker-platform-origin-v3-root-local-verification-20261013-r5.json', verification);
const body = { kind: 'focused-platform-origin-v3-runtime-review', preparedAt: new Date().toISOString(), projectId: PROJECT,
  originalApprovedBundleSha256: BUNDLE, predecessorRoutingBundleSha256: 'bce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552',
  ownerApproved: false, independentReviewPending: true, sourceCandidate: { path: pins[0][0], sha256: pins[0][1], bundleSha256: sourcePacket.bundleSha256 },
  changes: 'Permit only the exact HTTPS Supabase runtime origin with the fixed function-name namespace. Public project routes remain allowed. One finite enum/boolean ingress diagnostic per isolate records no request values, headers, bodies or secrets.',
  customAuthenticationUnchanged: true, factoryChanges: 'Only the route-module import changes; authorization/HMAC/limits remain byte-identical to routing v2.',
  requestUrlDiagnosis: { actualManagedRequestUrlObserved: false, inference: true, successfulLiveCorrectionObserved: false },
  liveFailure: { evidence: { path: pins[5][0], sha256: pins[5][1] }, observedAt: live.observedAt, scheduledResponses: 24,
    allHandlerNotFound: true, schedulesPaused: true, deliveryOutcomes: 0, receiverReceipts: 0 },
  verification: verificationBinding, deployments,
  actionsAfterExactSourceApproval: ['Replace only these two existing Wave 5 deployments.', 'Independently verify returned source modules and unchanged People functions.',
    'Use one fixed bounded unauthenticated request to inspect the finite diagnostic before any schedule resume.',
    'Resume only original jobs 4, 5 and 6 within original expiry/caps, collect actual signed transport/receipts and pause on failure.'],
  retainedLimits: { maximumModelCalls: 4, maximumScheduleRequestsOriginal: 4320, scheduledRequestsAlreadyObserved: 24,
    authorityExpiresAt: '2026-10-14T09:57:07.481942Z', scopeMayExpireEarlier: true, newMigrations: 0, newUsers: 0, newSecrets: 0,
    newPermissions: 0, newDestinations: 0, extendedExpiry: false, production: false, realBilling: false },
  implementationVerified: true, deployed: false, actualDelivery: false, actualTrustedModelUsage: false,
  fullProviderCoordinatorPassed: false, authenticatedNative: false, nativeKeyboard: false, targetScaleLoad: false,
  ownerAcceptedCriteria: 3, remainingUnacceptedCriteria: 106 };
const review = { ...body, bundleSha256: hashBytes(JSON.stringify(body)) };
const reviewBinding = await save(base + 'worker-platform-origin-v3-runtime-review-20261013-r5-a1.json', review);
await loadApprovedInputs();
process.stdout.write(JSON.stringify({ prepared: true, review: reviewBinding, localVerification: verificationBinding,
  bundleSha256: review.bundleSha256, independentReviewPending: true, ownerApproved: false, liveOperationsPerformed: false }) + '\n');
