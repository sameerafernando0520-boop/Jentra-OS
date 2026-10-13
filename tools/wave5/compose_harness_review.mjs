import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT_ID, hashBytes, hashJson, requireGuard, validateRuntimeReview, validateApproval } from './runtime_contract.mjs';

// Compose a separate evidence review from a completed real local run. Never modify a frozen runtime review.
const root = path.resolve(fileURLToPath(new URL('../../', import.meta.url)));
const folder = 'docs/verification/wave5';
const recordName = process.argv[2];
const stem = process.argv[3];
const ownerDecisionPath = process.argv[4];
requireGuard(/^runtime-harness-local-verification-20261012-r5-a[2-9][0-9]*\.json$/.test(recordName ?? '')
  && /^runtime-harness-review-20261012-r[5-9][0-9]*$/.test(stem ?? ''), 'NEW_EVIDENCE_FILENAME_REQUIRED');
const read = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { bytes, ref: { path: relative, sha256: hashBytes(bytes), bytes: bytes.length } }; };
const verification = await read(`${folder}/${recordName}`);
const record = JSON.parse(verification.bytes.toString('utf8'));
requireGuard(record.kind === 'controlled-wave5-harness-local-verification' && record.projectId === PROJECT_ID
  && record.passed === true && record.testsExecuted === true && record.childExitCode === 0 && record.childSignal === null
  && record.summary.tests === record.summary.passed && record.summary.tests > 0 && record.summary.failed === 0
  && record.summary.skipped === 0 && record.summary.cancelled === 0 && record.summary.todo === 0
  && record.selectedSourcesUnchanged === true && hashJson(record.filesBefore) === hashJson(record.filesAfter)
  && record.executedLive === false && record.networkCalls === 0 && record.sdkJobs === 0, 'HARNESS_SOURCE_BINDINGS_REQUIRED');
for (const expected of record.filesAfter) {
  const actual = await read(expected.path);
  requireGuard(actual.ref.sha256 === expected.sha256 && actual.ref.bytes === expected.bytes, 'HARNESS_SOURCE_DRIFT');
}
const log = await read(record.log.path);
requireGuard(log.ref.sha256 === record.log.sha256 && log.ref.bytes === record.log.bytes, 'HARNESS_SOURCE_DRIFT');
const runtimeFile = await read(record.runtimeReview.path);
const runtime = validateRuntimeReview(JSON.parse(runtimeFile.bytes.toString('utf8')));
requireGuard(runtimeFile.ref.sha256 === record.runtimeReview.sha256 && runtime.bundleSha256 === record.runtimeReview.bundleSha256,
  'RUNTIME_BUNDLE_HASH_MISMATCH');
const previousFailure = await read(`${folder}/failed-harness-tests-20261012-r5-a1.json`);
const historicalArtifacts = await Promise.all(['runtime-harness-local-verification-20261012-r5-a2.json',
  'runtime-harness-review-20261012-r5.json'].map(name => read(`${folder}/${name}`)));
let ownerDecision = null;
if (ownerDecisionPath) {
  requireGuard(/^docs\/verification\/wave5\/[a-z0-9_.-]+\.json$/.test(ownerDecisionPath), 'PUBLIC_REVIEW_MUST_BE_IN_WORKSPACE');
  const savedDecision = await read(ownerDecisionPath);
  const decision = validateApproval(JSON.parse(savedDecision.bytes.toString('utf8')), runtime, { runtimeFileSha256: runtimeFile.ref.sha256 });
  ownerDecision = { ...savedDecision.ref, decision: decision.decision, approvedAt: decision.approvedAt,
    sourceReference: decision.source.reference, authorizesOnlySameBoundedRuntime: true };
}
const composer = await read('tools/wave5/compose_harness_review.mjs');
const files = [...record.filesAfter.filter(ref => ref.path.startsWith('tools/wave5/')), composer.ref];
const contractSources = record.filesAfter.filter(ref => !ref.path.startsWith('tools/wave5/') && ref.path !== runtimeFile.ref.path);
const gates = { implementationCoordinator: true, privateSupabaseAdapter: false, installedSql: false,
  genuineMfa: false, independentSessionContention: false, targetScaleLoad: false, invalidBoundaryRejections: false,
  authenticatedNative: false, actualDelivery: false, actualModel: false, ownerAcceptance: false };
const body = {
  kind: 'wave5-runtime-harness-review', projectId: PROJECT_ID, observedAt: new Date().toISOString(),
  ownerApproved: false, executedLive: false, privateProviderImplemented: false, privateProviderLoaded: false,
  runtimeReview: { ...runtimeFile.ref, bundleSha256: runtime.bundleSha256,
    operationScopeSha256: runtime.sourceContinuation.unchangedRuntimeOperationScopeSha256 },
  operationScopeChanged: false, additionalOwnerAuthorizationForCoordinatorHashesRequired: false,
  ownerApprovedFieldMeaning: 'This technical local artifact contains no additional owner decision; existing runtime authorization is separate.',
  runtimeOwnerDecision: ownerDecision ?? { status: 'decision-recorded-separately-by-runtime-owner',
    noAdditionalOwnerDecisionForHarnessHashesRequired: true }, files, contractSources, localVerification: { ...verification.ref,
    actualStartedAt: record.actualStartedAt, actualFinishedAt: record.actualFinishedAt, command: record.command,
    childExitCode: record.childExitCode, nodeVersion: record.nodeVersion, summary: record.summary, log: log.ref },
  priorFailedAttemptPreserved: previousFailure.ref,
  historicalLocalArtifactsPreserved: historicalArtifacts.map(item => item.ref),
  supersededLocalEvidenceLimitation: 'The earlier 37-test result was genuine local evidence but missed a held-warmup catch-up false pass. Its files are retained; current source rejects actual dispatch lag and requires real nonempty rate-bounded warmup.',
  independentLocalCodeReview: 'published separately; cannot authorize an absent private provider',
  implementation: [
    'Exact immutable runtime target, all seven reviewed race definitions and concrete source hash checks.',
    'Common readiness barrier, original command identities, distinct Auth/trusted connections and actual client transport intervals.',
    'Committed before/after effects, losing-attempt zero effects, uncertain-state retention and exact reviewed restoration.',
    'Paced 60s warmup plus 300s measurement, 2,000-session/500-scope coverage, 70/20/10 mix and strict p95 limits.',
    'Synchronous actual-send phase/deadline guards, source-bound immutable factory inputs, fixed public error allowlist and exclusive evidence journal.',
    'Actual send-minus-scheduled-due lag guard including evidence/provider queues, independent scheduler lag and consistent rate-bounded warmup/sample counts.',
    'Separate unsupported-boundary, DB-row-count and actual external-transport observation evidence.',
  ],
  sourceCorrections: [
    'Scoped delivery claim creates one lease/attempt and zero usage reservations; actual send remains separate.',
    'load-001 billing-admin needs genuine AAL2; two distinct genuine AAL2 executor sessions are needed for execution contention.',
    'Cached duplicate replies cannot identify a unique winner; aggregate committed counts establish uniqueness.',
    'Invitation acceptance has no caller command/idempotency input; attempt UUID is correlation only.',
    'Model invocation/delivery attempt rows do not count actual remote sends; a complete reviewed transport observer is required.',
    'Synthetic activation/admission phases must precede quota buckets; existing busy billing periods cannot be cleared to force a pass.',
    'One-lease preparation needs only the reviewed accept subscription registered after earlier forecast effects, before the other three receiver paths; there is no public re-enable operation after revoke.',
  ],
  boundaryAvailability: [
    { kind: '10001Rows', status: 'unsupported-with-reviewed-per-tenant-source-caps' },
    { kind: '101Groups', status: 'actual-catalog-fixture-not-reviewed-or-proven' },
    { kind: '367DayWindow', status: 'source-mapped-feasible-invalid-request; not-executed' },
    { kind: '8MiBPlus1Byte', status: 'actual-output-fixture-not-reviewed-or-proven' },
  ],
  remainingPrivateImplementation: [
    'Genuine private Supabase Auth/session storage and online identity/server auth.sessions proof for all 2,000 distinct sessions; real MFA.',
    'Actual reviewed source-listed PostgREST/worker transport with independent connections and honest start/end/response evidence.',
    'Concrete source-bound new-scope fixture preparation/restoration and read-only committed SQL, including denied-attempt attribution.',
    'Fresh installed-ledger/signature/grant/RLS/preservation proof and supported database/generator capacity for the exact rate.',
    'Reviewed full transport observer and online no-inflight/inactive-job proof for model/webhook exclusion during load.',
    'Feasible separately reviewed excessive-source/group/output fixture scope if current approved caps cannot exercise required limits.',
    'Source-bound independent preparation review of the real private implementation, dependencies and concrete plan.',
  ],
  exclusions: { production: false, realBilling: false, originalSixReplayed: false, globalAuthChanges: false,
    authRowsFabricated: false, credentialsRead: false, networkCalls: 0, sdkJobs: 0, nativeActions: 0,
    installations: 0, existingSourceEdits: [], acceptanceStoreEdits: [], sessionStoreEdits: [], commits: 0, pushes: 0 },
  gates,
  evidenceBoundary: 'Actual local orchestration tests, including controlled transports and virtual-time load populations. No genuine Auth, installed runtime, actual database contention, target-scale latency or owner acceptance is established.',
};
const result = { ...body, reviewBodySha256: hashJson(body) };
const jsonPath = `${folder}/${stem}.json`, mdPath = `${folder}/${stem}.md`;
const markdown = `# Wave 5 reusable runtime coordinator review\n\n` +
  `The new reusable coordinator is implemented and locally verified: **${record.summary.passed}/${record.summary.tests} tests passed**, with no failures, skips, cancellations or todo cases. ` +
  `Node ${record.nodeVersion} ran the actual test command from ${record.actualStartedAt} to ${record.actualFinishedAt}. ` +
  `It is an executable coordinator with a private-provider interface; a genuine Supabase transport/private session provider has **not** been implemented.\n\n` +
  `This separate review binds [the immutable runtime review](./complete-app-runtime-review-20261010-r5.json), bundle \`${runtime.bundleSha256}\`, file \`${runtimeFile.ref.sha256}\`. ` +
  `The existing operation scope \`${runtime.sourceContinuation.unchangedRuntimeOperationScopeSha256}\` remains unchanged. ` +
  (ownerDecision ? `The [separate runtime owner decision](./${path.basename(ownerDecision.path)}) approved the exact bounded setup. ` :
    `The runtime owner decision is maintained separately by the runtime owner. `) +
  `The same runtime decision covers the same bounded operations; technical code/preparation review creates no second owner approval for file hashes.\n\n` +
  `## Actual local evidence\n\n` +
  `- [Recorded actual Node run](./${recordName}) and [complete TAP](./${path.basename(record.log.path)}): exit 0; ${record.summary.passed} passed; selected source hashes unchanged before/after.\n` +
  `- [Earlier failing attempt](./failed-harness-tests-20261012-r5-a1.json) is preserved: 25/26 passed; its duplicate-session negative fixture was corrected, not the guard.\n` +
  `- [Earlier 37-test run](./runtime-harness-local-verification-20261012-r5-a2.json) and [its review](./runtime-harness-review-20261012-r5.json) remain historical. The peer's held-warmup false pass exposed a missing actual lag check; the current source and successor run fix it.\n` +
  `- [Public source bindings](./${stem}.json) bind ${files.length} new implementation/evidence files and ${contractSources.length} authoritative protocol/bootstrap/SQL dependencies.\n` +
  `- [Private provider contract](../../../tools/wave5/PRIVATE_PROVIDER_CONTRACT.md) defines the still-missing real Auth/transport/committed-state interfaces.\n\n` +
  `The tests exercise actual coordinator barriers and client overlap, detect serial queues, preserve uncertain mutations, enforce committed effect counts, redact arbitrary provider errors, prevent post-deadline sends and freeze source-bound contexts. ` +
  `The held-warmup regression rejects a 60-second evidence-queue delay before send; scheduled timing cannot claim actual warmup or hide catch-up bursts. ` +
  `A controlled virtual-time run checks every 2,000-session/500-scope slot and 70/20/10 scheduling; it proves no live latency or real sessions.\n\n` +
  `## Source findings carried into implementation\n\n` +
  body.sourceCorrections.map(item => `- ${item}\n`).join('') + `\n` +
  `The 367-day invalid request is feasible from the mapped API. A 10001-row cohort exceeds approved caps, and real 101-group/8MiB output fixtures remain unproven. ` +
  `Unsupported limits record blocked/never executed/never passed. Independently authorized race/load investigation may continue, but the complete result stays false until all four required limits have genuine evidence.\n\n` +
  `## Remaining work and gates\n\n` +
  body.remainingPrivateImplementation.map(item => `- ${item}\n`).join('') + `\n` +
  `All live gates remain false: installed SQL, genuine MFA, independent-session contention, target-scale load, invalid-limit rejection, authenticated native, actual delivery/model usage and owner acceptance. ` +
  `No network, SDK/native job, Auth write, installation, credential access, acceptance/session-store edit, commit or push was performed. Production and real billing remain excluded.\n`;
await fs.writeFile(path.join(root, jsonPath), JSON.stringify(result, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
await fs.writeFile(path.join(root, mdPath), markdown, { flag: 'wx', mode: 0o600 });
const saved = await read(jsonPath);
process.stdout.write(JSON.stringify({ jsonPath, mdPath, sha256: saved.ref.sha256, reviewBodySha256: result.reviewBodySha256,
  tests: record.summary, executedLive: false, privateProviderImplemented: false }) + '\n');
