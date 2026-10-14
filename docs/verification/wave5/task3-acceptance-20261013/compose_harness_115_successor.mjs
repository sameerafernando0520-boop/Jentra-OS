import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {validateRuntimeReview, validateApproval} from '../../../../tools/wave5/runtime_contract.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const folder = 'docs/verification/wave5/task3-acceptance-20261013';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = name => fs.readFileSync(path.resolve(root, name));
const bind = name => ({path: name, bytes: read(name).length, sha256: sha(read(name))});
const json = name => JSON.parse(read(name));
const previousPath = 'docs/verification/wave5/task3-peer-review-20261013/runtime-harness-review-20261013-peer-a2.json';
const localPath = `${folder}/runtime-provider-local-verification-20261014-acceptance-a3.json`;
const independentPath = `${folder}/load-baseline-115-independent-review.json`;
const previous = json(previousPath), local = json(localPath), independent = json(independentPath);
assert.equal(local.passed, true); assert.equal(local.sourcesUnchangedDuringRun, true);
assert.equal(local.summary.tests, 122); assert.equal(local.summary.passed, 122);
for (const name of ['failed', 'skipped', 'cancelled', 'todo']) assert.equal(local.summary[name], 0);
assert.equal(local.childExitCode, 0); assert.equal(local.childSignal, null);
assert.equal(local.coordinatorCaseCount, 41); assert.equal(local.exactAllCoordinatorIdentitiesObserved, true);
assert.deepEqual(local.filesBefore, local.filesAfter);
for (const binding of local.filesAfter) assert.deepEqual(bind(binding.path), binding);
assert.deepEqual(bind(local.log.path), local.log);
assert.equal(independent.technicalVerdict, 'approved within the unchanged bounded synthetic runtime scope');
assert.equal(independent.exactMinimalSourceDeltaVerified, true);
for (const change of independent.reviewedChanges) assert.deepEqual(bind(change.current.path), change.current);
const currentFiles = previous.files.map(binding => bind(binding.path));
const currentContracts = previous.contractSources.map(binding => bind(binding.path));
assert.equal(currentFiles.length + currentContracts.length, 18);
const changedBindings = [...previous.files, ...previous.contractSources].filter(binding => bind(binding.path).sha256 !== binding.sha256);
assert.deepEqual(changedBindings.map(binding => binding.path), ['tools/wave5/runtime_contract.mjs', 'tools/wave5/runtime_coordinator.test.mjs']);
const runtime = validateRuntimeReview(json(previous.runtimeReview.path));
assert.equal(bind(previous.runtimeReview.path).sha256, previous.runtimeReview.sha256);
assert.equal(runtime.liveBaseline.expectedLedgerAfterOnlyThisInstall, 114);
const ownerPath = 'docs/verification/wave5/runtime-owner-decision-20261012-r5.json';
const owner = validateApproval(json(ownerPath), runtime, {runtimeFileSha256: previous.runtimeReview.sha256});
const body = {
  kind: 'wave5-runtime-harness-review', projectId: runtime.projectId, observedAt: new Date().toISOString(),
  reviewer: 'Codex requirement_acceptance independent technical reviewer', ownerApproved: false,
  personalHumanSignatureClaimed: false, executedLive: false, privateProviderImplemented: false, privateProviderLoaded: false,
  publicProviderSourceImplemented: true, configuredPrivateProviderCertified: false,
  runtimeReview: previous.runtimeReview, operationScopeChanged: false,
  additionalOwnerAuthorizationForCoordinatorHashesRequired: false,
  ownerApprovedFieldMeaning: 'This additive technical source review records no personal owner signature or new operating scope. The separate existing runtime decision and the live-owner narrow source-ownership grant remain the authority records.',
  runtimeOwnerDecision: {...bind(ownerPath), decision: owner.decision, approvedAt: owner.approvedAt,
    sourceReference: owner.source.reference, authorizesOnlySameBoundedRuntime: true},
  predecessorReview: bind(previousPath), frozenReviewsOverwritten: false,
  files: currentFiles, contractSources: currentContracts, sourceBindingCount: 18,
  changedBindings: changedBindings.map(previous => ({path: previous.path, previous, current: bind(previous.path)})),
  localVerification: {...bind(localPath), actualStartedAt: local.actualStartedAt, actualFinishedAt: local.actualFinishedAt,
    command: local.command, childExitCode: local.childExitCode, nodeVersion: local.nodeVersion, summary: local.summary,
    coordinatorCaseCount: 41, providerTestFileCount: 11, relevantSourceCount: local.filesAfter.length,
    sourcesUnchangedDuringRun: true, log: local.log},
  baselineIndependentReview: bind(independentPath),
  currentPreflightBaseline: {requiredOnlineCount: 115, historical43Plus71CountRetained: 114,
    exactNumericEqualityRequired: true, malformedCountsRejected: [114, 116, 115.5, '115'],
    sourceApplication: independent.application, installedEvidence: independent.installationProof,
    recordedObservation: independent.independentRecordedEvidenceReadback,
    observationRewritten: false, freshCompleteOnlinePreflightStillRequired: true},
  independentLocalCodeReview: {verdict: 'approved within the unchanged bounded synthetic runtime scope',
    patchAuthoredByThisReviewer: false, minimalDeltaVerifiedAgainstPreservedBytes: true,
    inheritedCoordinatorReview: bind(previousPath), inheritedStartupCleanupIndependentReview:
      bind('docs/verification/wave5/task3-completion-20261013/startup-cleanup-independent-review.json'),
    explanation: 'The online preflight numeric ledger expectation and two controlled fixture counts are the only source changes. Four negative count variants exercise the existing guard. Every other bound harness source byte remains identical to peer-a2; current 11-file provider tests passed.'},
  currentFailedAttemptsPreserved: [1, 2].map(attempt => ({
    record: bind(`${folder}/runtime-provider-local-verification-20261014-acceptance-a${attempt}.json`),
    log: bind(`${folder}/runtime-provider-local-verification-20261014-acceptance-a${attempt}.tap`)})),
  failureRepairBoundary: 'The first attempt encountered sandbox junction EPERM; repository temporary directories then correctly triggered the private-sink guard. The successful run used an approved test-only unsandboxed runner and a new synthetic TEMP directory in the explicitly writable visualization root outside the repository. No product test, guard, expected result or private data was modified.',
  priorFailedAttemptPreserved: previous.priorFailedAttemptPreserved,
  historicalLocalArtifactsPreserved: [...previous.historicalLocalArtifactsPreserved,
    bind('docs/verification/wave5/task3-peer-review-20261013/runtime-harness-local-verification-20261013-peer-a2.json')],
  implementation: previous.implementation, sourceCorrections: [...previous.sourceCorrections,
    'Online preflight requires observed numeric migration count 115 after the separately installed cash repair. The immutable initial 43+71 installation expectation remains 114. Count equality does not replace ledger, signature, grant, RLS, source, capacity, session or quiescence proof.'],
  boundaryAvailability: previous.boundaryAvailability,
  remainingPrivateImplementation: [
    'Bind the new harness and current provider/driver/dependency hashes into an independently reviewed concrete private factory, plan and preparation before use.',
    'Perform a fresh full online installed ledger/signature/grant/forced-RLS/protected-source preflight with exact numeric 115 and supported database/generator capacity.',
    'Verify all 2,000 distinct genuine online Auth session rows, required real MFA and exact 500-scope actor distribution.',
    'Use the reviewed private fixture/journal/transport wrapper and preserve acknowledged invitation identities, versions and uncertain outcomes.',
    'Prove continuous reviewed job quiescence and actual no-egress observation throughout the full workload window.',
    'Execute every independent committed race and the real 60-second warmup plus 300-second measured protocol with honest transport timing, coverage and P95.',
    'Obtain all four actual invalid-limit fixture results, authenticated native keyboard/restart/revocation recovery and the separate production release evidence.',
  ],
  gates: {implementationCoordinator: true, privateSupabaseAdapter: false, installedSql: false, genuineMfa: false,
    independentSessionContention: false, targetScaleLoad: false, invalidBoundaryRejections: false,
    authenticatedNative: false, actualDelivery: false, actualModel: false, ownerAcceptance: false},
  exclusions: {production: false, realBilling: false, originalSixReplayed: false, globalAuthChanges: false,
    authRowsFabricated: false, credentialsRead: false, networkCalls: 0, SDKJobs: 0, nativeActions: 0,
    installations: 0, existingSourceEditsByThisReviewer: [], acceptanceStoreEdits: [], sessionStoreEdits: [],
    commits: 0, pushes: 0, writerAndWrapperTestsRepeated: false},
  evidenceBoundary: 'Current source-bound Node implementation and guard verification plus independent comparison of recorded narrow installed metadata. No full online preflight, genuine Auth, actual PostgreSQL contention, target workload latency, authenticated native or personal owner acceptance is established.',
  composer: bind(`${folder}/compose_harness_115_successor.mjs`),
};
const result = {...body, reviewBodySha256: sha(JSON.stringify(body))};
const stem = `${folder}/runtime-harness-review-20261014-acceptance-a1`;
const reviewPath = `${stem}.json`, markdownPath = `${stem}.md`;
fs.writeFileSync(path.resolve(root, reviewPath), JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
const markdown = [
  '# Wave 5 current 115-baseline runtime harness review', '',
  '**122 of 122 public provider cases passed**, including all 41 coordinator cases. Eleven test files ran on the current source with 43 relevant before/after source bindings unchanged. This additive successor binds the current 18 harness inputs.', '',
  'The independent review verifies the exact permitted three-file delta against preserved originals: numeric online ledger expectation 114 to 115, the two controlled fixtures, and four rejection variants in the existing guard test. Every other bound harness source remains identical to peer-a2.', '',
  'The recorded installed observation reports 115 migrations and 363 API functions. Both cash repair bodies match the reviewed successor hashes; non-body metadata matches before and after, and jobs 4, 5 and 6 are paused in that observation. A fresh complete online preflight remains required before execution.', '',
  'The immutable approved runtime review still retains its historical 43 + 71 = 114 expectation and its original owner decision. This technical successor records no new personal owner signature and does not expand the approved operations.', '',
  '| Evidence | Result |', '|---|---|',
  '| Current Node provider suite | 122 passed; zero failed, skipped, cancelled or todo; 41 coordinator cases observed |',
  '| Exact delta and narrow installed evidence | Independently verified against preserved bytes and saved connector readback |',
  '| Current harness bindings | 18 checked; contract and coordinator test are the only changed harness files |',
  '| Preserved failures | a1 sandbox junction error; a2 correctly rejected repository storage; product tests and guards unchanged |',
  '| Actual contention, target load and native acceptance | Remain unverified |', '',
  '[Machine harness review](runtime-harness-review-20261014-acceptance-a1.json) · [Current provider test record](runtime-provider-local-verification-20261014-acceptance-a3.json) · [Independent minimal-diff review](load-baseline-115-independent-review.json)', '',
  'Before live use, bind this new harness SHA and the current concrete provider/driver/dependency tree into the private plan and independent preparation. Then require fresh online contracts/capacity, genuine sessions and MFA, full no-egress/quiescence proof, committed overlapping races and measured load. Production release and native workflow/recovery remain separate gates.', '',
].join('\n');
fs.writeFileSync(path.resolve(root, markdownPath), markdown, {flag: 'wx'});
const environment = Object.fromEntries(['SystemRoot', 'WINDIR', 'TEMP', 'TMP'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
const command = ['tools/wave5/run_runtime_verification.mjs', '--review', previous.runtimeReview.path, '--harness-review', reviewPath];
const startedAt = new Date().toISOString();
const offline = spawnSync(process.execPath, command, {cwd: root, env: environment, windowsHide: true,
  encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024});
const finishedAt = new Date().toISOString();
let value = null; try { value = JSON.parse(offline.stdout); } catch {}
const passed = offline.status === 0 && value?.mode === 'offline-validation' && value.executedLive === false
  && value.networkCalls === 0 && value.harnessReviewSha256 === bind(reviewPath).sha256
  && value.independentSessionContention === false && value.targetScaleLoad === false && value.ownerAcceptance === false;
const offlineResult = {kind: 'current-115-harness-offline-cli-validation', actualStartedAt: startedAt, actualFinishedAt: finishedAt,
  passed, command: ['node', ...command], childExitCode: offline.status, childSignal: offline.signal,
  errorCode: offline.error ? 'OFFLINE_CLI_CHILD_FAILURE' : null, stdout: offline.stdout ?? '', stderr: offline.stderr ?? '',
  result: value, harness: bind(reviewPath), markdown: bind(markdownPath), sourceBindingsVerified: 18,
  sourceBindingsAfter: [...currentFiles, ...currentContracts].map(reference => bind(reference.path)),
  executeFlagProvided: false, privateProviderLoaded: false, networkCalls: 0, SDKJobs: 0, acceptanceDecisionsAdded: 0};
const offlinePath = `${folder}/runtime-harness-offline-validation-20261014-acceptance-a1.json`;
fs.writeFileSync(path.resolve(root, offlinePath), JSON.stringify(offlineResult, null, 2) + '\n', {flag: 'wx'});
assert.deepEqual(offlineResult.sourceBindingsAfter, [...currentFiles, ...currentContracts]);
console.log(JSON.stringify({passed, harness: bind(reviewPath), markdown: bind(markdownPath),
  offline: bind(offlinePath), sourceBindingCount: 18, tests: 122, coordinatorCases: 41}, null, 2));
assert.equal(passed, true);
