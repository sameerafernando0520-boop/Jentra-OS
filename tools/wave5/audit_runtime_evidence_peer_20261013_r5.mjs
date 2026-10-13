import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { hashBytes, hashJson, PROJECT_ID, isUuid } from './runtime_contract.mjs';
import { decodePublicResult, BUNDLE } from './approved_management_installer.mjs';
import { validateForecastRead, validateSourceRead } from './source_workflow_management_20261013_r5.mjs';
import { verifyActivationDelta } from './synthetic_activation_contention_20261013_r5.mjs';
import { outcomeFromRpc } from './supabase_runtime_provider.mjs';

// Offline scrutiny of exact public saved responses. No private file, live client,
// credential, SDK, browser, native application or transport is invoked.
const root = fileURLToPath(new URL('../../', import.meta.url));
const attempt = process.argv[2];
if (!/^a[1-9][0-9]*$/.test(attempt ?? '') || process.argv.length !== 3) throw Error('NEW_PUBLIC_PEER_ATTEMPT_REQUIRED');
const base = 'docs/verification/wave5/';
const prefix = `${base}runtime-evidence-independent-review-20261013-r5-${attempt}`;
const sources = ['tools/wave5/audit_runtime_evidence_peer_20261013_r5.mjs',
  'tools/wave5/runtime_contract.mjs', 'tools/wave5/approved_management_installer.mjs',
  'tools/wave5/supabase_runtime_provider.mjs', 'tools/wave5/supabase_http_transport.mjs',
  'tools/wave5/source_workflow_management_20261013_r5.mjs', 'tools/wave5/continue_source_workflows_20261013_r5_a3.mjs',
  'tools/wave5/synthetic_activation_contention_20261013_r5.mjs', 'tools/wave5/genuine_delivery_lease_20261013_r5.mjs',
  'tools/wave5/prepare_actual_delivery_fixtures_20261013_r5.mjs', 'tools/wave5/delivery_transport_20261013_r5.mjs',
  'tools/wave5/private_existing_actor_session_20261013_r5.mjs', 'tools/wave5/enroll_mfa_management_20261013_r5.mjs',
  'tools/wave5/verify_persistent_setup_committed_20261013_r5.mjs',
  'scripts/wave5/run_private_management_installer_20261013_r5.ps1'];
const bind = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, bytes: bytes.length, sha256: hashBytes(bytes) }; };
const evidence = new Map();
async function read(relative, wantedSha) {
  const bytes = await fs.readFile(path.join(root, relative)), binding = { path: relative, bytes: bytes.length, sha256: hashBytes(bytes) };
  if (wantedSha) assert.equal(binding.sha256, wantedSha, 'EXACT_PUBLIC_EVIDENCE_BYTES_REQUIRED');
  evidence.set(relative, binding); return JSON.parse(bytes);
}
const started = new Date().toISOString(), filesBefore = await Promise.all(sources.map(bind));
const review = await read(`${base}complete-app-runtime-review-20261010-r5.json`, 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3');
const owner = await read(`${base}runtime-owner-decision-20261012-r5.json`, '90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab');
assert.equal(review.projectId, PROJECT_ID); assert.equal(review.bundleSha256, BUNDLE);
assert.equal(owner.decision, 'approve'); assert.equal(owner.runtimeBundleSha256, BUNDLE);
const workflowDir = `${base}genuine-source-workflows-completed-20261013-r5-a3-1791883333161/`;
const workflow = await read(`${workflowDir}99-result.json`, 'e71b6d78578ab5261d39243c493abdde045b0dddfe587486363190848b676428');
assert.equal(workflow.passed, true); assert.equal(workflow.scopesVerified, 500); assert.equal(workflow.newForecastCommands, 491);
assert.equal(workflow.existingForecastIdentitiesPreserved, 9); assert.equal(workflow.completed.length, 500);
assert.equal(new Set(workflow.completed.map(row => row.scopeKey)).size, 500);
assert.equal(new Set(workflow.completed.map(row => row.forecastId)).size, 500);
assert.equal(new Set(workflow.completed.map(row => row.commandId)).size, 500);
const known = await read(`${workflowDir}00-nine-original-identities.json`);
assert.equal(known.actualReturnedRows.length, 9);
let forecastSources = 0, processSources = 0, preserved = 0, newResponses = 0;
const signatures = new Set();
for (const scope of review.syntheticScopes) {
  const row = workflow.completed.find(value => value.scopeKey === scope.key);
  assert.ok(row); assert.equal(row.tenantId, scope.tenantId); assert.ok(isUuid(row.commandId));
  const packet = await read(`${workflowDir}${scope.key}-result.json`);
  assert.equal(packet.scopeKey, scope.key); assert.equal(packet.commandId, row.commandId);
  const forecast = validateForecastRead(packet.forecastResponse, scope), process = validateSourceRead(packet.processResponse, scope);
  assert.equal(forecast.id, row.forecastId); assert.equal(forecast.sourceHash, row.sourceHash);
  assert.deepEqual(forecast, packet.forecast); assert.deepEqual(process, packet.process);
  forecastSources += forecast.sourceCount; processSources += process.sourceCount;
  assert.equal(packet.transport.length, 2);
  for (const trace of packet.transport) {
    assert.equal(trace.projectId, PROJECT_ID); assert.equal(trace.status, 200);
    assert.ok(Date.parse(trace.sentAt) <= Date.parse(trace.finishedAt)); signatures.add(trace.connectionId);
  }
  const previous = known.actualReturnedRows.find(value => value.tenant_id === scope.tenantId);
  if (previous) { assert.equal(packet.priorForecastPreserved, true); preserved++;
    assert.equal(previous.id, row.forecastId); assert.equal(previous.source_hash, row.sourceHash); assert.equal(previous.command_id, row.commandId);
  } else {
    assert.equal(packet.priorForecastPreserved, false);
    const intent = await read(`${workflowDir}${scope.key}-intent.json`), response = await read(`${workflowDir}${scope.key}-command-response.json`);
    assert.equal(intent.commandId, row.commandId); assert.equal(intent.body.p_command_id, row.commandId);
    assert.equal(intent.body.p_idempotency_key, row.commandId); assert.equal(intent.body.p_tenant_id, scope.tenantId);
    assert.equal(response.ok, true); assert.equal(response.value.entity.id, row.forecastId);
    assert.equal(outcomeFromRpc({ operation: 'forecast', request: { commandId: row.commandId }, response }).outcome, 'applied');
    newResponses++;
  }
}
assert.equal(forecastSources, 1000); assert.equal(processSources, 2000); assert.equal(preserved, 9); assert.equal(newResponses, 491);
const replay = await read(`${workflowDir}runtime-replay-and-denials.json`);
const runtimeCommand = workflow.completed.find(row => row.scopeKey === 'runtime').commandId;
assert.equal(replay.replay.ok, true); assert.equal(replay.replay.value.command_id, runtimeCommand);
assert.notEqual(replay.replay.value.request_id, runtimeCommand);
assert.equal(replay.foreign.ok, false); assert.equal(replay.foreign.evidence.status, 403);
assert.equal(replay.foreign.value.code, '42501'); assert.equal(replay.foreign.value.message, 'Permission denied or multi-factor authentication required.');
assert.equal(replay.wide.ok, false); assert.equal(replay.wide.value.message, 'LIMIT_EXCEEDED');
for (const gate of ['actualDelivery', 'actualModelUsage', 'authenticatedNative', 'independentSessionContention', 'targetScaleLoad']) assert.equal(workflow[gate], false);

const deployments = [];
for (const slug of ['runtime', 'receiver']) {
  const value = decodePublicResult(await read(`${base}worker-deployment-${slug}-readback-20261013-r5.json`));
  const wanted = review.deployments.find(item => item.entrypoint === `supabase/functions/wave5-${slug}/index.ts`);
  assert.equal(value.slug, `wave5-${slug}`); assert.equal(value.status, 'ACTIVE'); assert.equal(value.verify_jwt, wanted.verifyJwt);
  const available = value.files.map(file => {
    const expected = wanted.files.find(entry => entry.path === file.name); assert.ok(expected);
    assert.equal(hashBytes(file.content), expected.sha256); return { path: file.name, sha256: expected.sha256 };
  });
  assert.equal(new Set(available.map(file => file.path)).size, available.length);
  const omitted = wanted.files.filter(file => !available.some(row => row.path === file.path));
  assert.deepEqual(omitted.map(file => file.path), [`supabase/functions/wave5-${slug}/deno.json`]);
  deployments.push({ slug: value.slug, returnedSourceFilesMatched: available.length, available,
    omittedByReadback: omitted.map(file => file.path), omittedFileInstalledBytesVerified: false });
}
assert.equal(deployments.reduce((n, deployment) => n + deployment.returnedSourceFilesMatched, 0), 20);
const activationDir = `${base}synthetic-activation-contention-20261013-r5-1791884748470/`;
const activation = await read(`${activationDir}99-result.json`, 'cdb366e5c4c597d8379ecb86634dfae8674bbf5c96c0609af96fee86df8dcb4f');
const scheduled = await read(`${activationDir}04-after-schedule.json`), afterActivation = await read(`${activationDir}07-after-activation.json`);
const activationResponses = await read(`${activationDir}06-contention-responses.json`);
assert.equal(activationResponses.length, 2); assert.ok(activationResponses.every(row => row.ok && row.status === 200));
assert.deepEqual(activationResponses[0].value, activationResponses[1].value);
verifyActivationDelta(scheduled, afterActivation, activationResponses[0].value, activation.executionId, activation.revisionId);
assert.equal(activationResponses[0].value.entity.id, afterActivation.subscription.id);
function overlap(responses) {
  assert.notEqual(responses[0].evidence.connectionId, responses[1].evidence.connectionId);
  const starts = responses.map(row => Date.parse(row.evidence.sentAt)), ends = responses.map(row => Date.parse(row.evidence.finishedAt));
  assert.ok(starts.every(Number.isFinite) && ends.every(Number.isFinite));
  const milliseconds = Math.min(...ends) - Math.max(...starts); assert.ok(milliseconds > 0); return milliseconds;
}
const activationClientOverlapMs = overlap(activationResponses);
assert.equal(activation.genuineBillingAal2.aal, 'aal2'); assert.equal(activation.fullProviderCoordinatorPassed, false);
const setup = await read(`${base}persistent-setup-actual-verification-20261013-r5-a3.json`, 'acfcf0b58bff2d3da4855612978395ba481e3d8cac76300d6086bca4d2ecfd4f');
const setupBefore = await read(setup.bindings.before.path, setup.bindings.before.sha256);
const setupAfter = decodePublicResult(await read(setup.bindings.after.path, setup.bindings.after.sha256))[0].snapshot;
assert.equal(setupBefore.authorities.length, 0); assert.equal(setupBefore.ownJobs.length, 0); assert.equal(setupBefore.ownVault.length, 0);
assert.equal(setupAfter.authorities.length, 1); assert.equal(setupAfter.ownJobs.length, 3); assert.equal(setupAfter.ownVault.length, 3); assert.equal(setupAfter.keyRefs.length, 2);
assert.ok(setupAfter.ownJobs.every(job => job.active === false && job.schedule === '* * * * *'));
assert.deepEqual(setup.authority, setupAfter.authorities[0]); assert.deepEqual(setup.ownJobs, setupAfter.ownJobs);
assert.equal(setupBefore.outsideJobHash, setupAfter.outsideJobHash); assert.equal(setupBefore.outsideVaultIdentityHash, setupAfter.outsideVaultIdentityHash);
assert.equal(setup.scheduledExecution, false);
const stops = [];
for (const directory of ['persistent-setup-20261013-r5-1791885065132', 'persistent-setup-20261013-r5-a2-1791885218584',
  'persistent-setup-20261013-r5-a3-1791885422750', 'persistent-setup-20261013-r5-a4-1791885619454',
  'genuine-source-workflows-20261013-r5-1791882165675', 'genuine-source-workflows-resumed-20261013-r5-1791882899175']) {
  const relative = `${base}${directory}/99-stop.json`, value = await read(relative);
  stops.push({ ...evidence.get(relative), phase: value.phase ?? null, failureCode: value.failureCode });
}
assert.equal(stops.find(row => row.path.includes('a4-1791885619454')).failureCode, 'PERSISTENT_SETUP_COLLISION_FORBIDDEN');
const leaseDir = `${base}genuine-delivery-lease-20261013-r5-1791885923843/`;
const lease = await read(`${leaseDir}99-result.json`, 'e35cf55c3f093a17416bf132e89783eb4e4a337c808eda69fd747238c2322076');
const claimBefore = await read(`${leaseDir}06-before-claim.json`), claims = await read(`${leaseDir}08-claim-responses.json`);
const claimAfter = await read(`${leaseDir}09-after-claim.json`), unknown = await read(`${leaseDir}11-unknown-before-review.json`);
const naturalExpiry = await read(`${leaseDir}10-natural-expiry-claim.json`), recovered = await read(`${leaseDir}14-after-recovery.json`);
assert.equal(claims.filter(row => row.ok && row.value !== null).length, 1); assert.equal(claims.filter(row => row.ok && row.value === null).length, 1);
const leaseClientOverlapMs = overlap(claims);
assert.equal(claimBefore.heads.length, 0); assert.equal(claimAfter.heads.length, 1); assert.equal(claimAfter.attempts, 1);
assert.equal(claimAfter.heads[0].id, lease.deliveryId); assert.equal(claimAfter.heads[0].leaseId, lease.leaseId);
assert.equal(claimAfter.heads[0].state, 'leased'); assert.equal(unknown.heads[0].state, 'unknown');
assert.ok(Date.parse(unknown.observedAt) > Date.parse(claimAfter.heads[0].leaseUntil));
assert.equal(naturalExpiry.ok, true); assert.equal(naturalExpiry.value, null);
assert.equal(recovered.heads[0].id, lease.deliveryId); assert.equal(recovered.heads[0].state, 'retry'); assert.equal(recovered.reviews, 1);
for (const packet of [claimAfter, unknown, recovered]) {
  assert.equal(packet.quotaPeriods, 0); assert.equal(packet.receiverReceipts, 0); assert.equal(packet.activeOwnJobs, 0); assert.equal(packet.ticks, 0);
}
assert.equal(lease.actualDelivery, false); assert.equal(lease.unobservedExternalSendCounts, null);
const fixtureDir = `${base}actual-delivery-fixtures-20261013-r5-1791886204826/`;
const fixture = await read(`${fixtureDir}99-result.json`, 'a39892480eb4009eac5a3c6cbf0debbc1a74860eec63ceca5f39a65c240ddd79');
const fixtureAfter = await read(`${fixtureDir}04-after.json`);
assert.equal(fixture.subscriptions.length, 4); assert.equal(fixture.originalRecoveredDeliveryId, lease.deliveryId);
for (const [name, id] of Object.entries(review.workerConfiguration.receiver.subscriptions)) {
  const row = fixture.subscriptions.find(value => value.id === id); assert.ok(row?.enabled);
  assert.equal(row.url, review.workerConfiguration.receiver.paths[name]);
}
assert.equal(fixtureAfter.heads[0].id, lease.deliveryId); assert.equal(fixtureAfter.heads[0].state, 'retry');
assert.equal(fixture.actualDelivery, false); assert.equal(fixture.workerScheduleStarted, false); assert.equal(fixtureAfter.activeOwnJobs, 0);
const filesAfter = await Promise.all(sources.map(bind)), evidenceAfter = await Promise.all([...evidence.values()].map(value => bind(value.path)));
assert.equal(hashJson(filesBefore), hashJson(filesAfter), 'REVIEWED_SOURCE_CHANGED_DURING_OFFLINE_CHECK');
assert.deepEqual([...evidence.values()], evidenceAfter, 'PUBLIC_EVIDENCE_CHANGED_DURING_OFFLINE_CHECK');
const providerSource = await fs.readFile(path.join(root, 'tools/wave5/supabase_runtime_provider.mjs'), 'utf8');
const mutablePrivateConfigLiveReferences = ['privateActors', 'verifyOnlinePreflight', 'observeExternalTransport', 'authConcurrency', 'serviceRoleKey']
  .filter(field => providerSource.includes(`privateConfig.${field}`));
const report = { kind: 'independent-offline-wave5-public-runtime-evidence-review', reviewer: '/root/provider_review_20261013',
  projectId: PROJECT_ID, runtimeBundleSha256: BUNDLE, actualStartedAt: started, actualFinishedAt: new Date().toISOString(),
  passed: true, selectedSourcesUnchanged: true, savedEvidenceUnchanged: true, filesBefore, filesAfter, evidenceBindings: evidenceAfter,
  sourceWorkflows: { scopesRevalidated: 500, forecastSourceObservations: forecastSources, processSourceObservations: processSources,
    originalForecastIdsPreserved: preserved, newCommandResponsesChecked: newResponses, actualScopedReadsEach: 500,
    originalCommandReplayChecked: true, exactForeignPermissionDenialChecked: true, wideWindowLimitDenialChecked: true,
    workloadTlsConnectionIds: signatures.size, genuineSessionsInSavedResult: 2, targetScaleLoadProved: false },
  workerReadback: deployments,
  activation: { verifiedSavedCommittedEffect: 1, participants: 2, distinctVerifiedTlsAgents: true, clientOverlapMs: activationClientOverlapMs,
    backendExecutionOverlapVerified: false, genuineUserSessionRace: false, trustedServiceRoleRace: true, fullCoordinatorProof: false },
  persistentSetup: { savedCommittedAuthority: 1, savedVaultIdentities: 3, savedKeyRefs: 2, exactOwnJobs: 3, jobsPaused: true,
    precedingHttpFailurePreserved: true, collisionGuardStoppedReplay: true, actualScheduledExecutionProved: false },
  lease: { savedWinners: 1, savedNullResponses: 1, clientOverlapMs: leaseClientOverlapMs, backendExecutionOverlapVerified: false,
    naturalExpiryChecked: true, genuineMfaReviewInSavedRecord: true, originalDeliveryRecovered: true, savedUsageDelta: 0,
    actualDeliveryProved: false, completeExternalSendCounts: null },
  fixtures: { exactApprovedPaths: 4, originalRecoveredDeliveryPreserved: true, jobsPaused: true, actualSendProved: false },
  actionableFindings: mutablePrivateConfigLiveReferences.length ? [{ id: 'P-10', status: 'open-source-review-finding',
    title: 'Private configuration retains caller-mutable live references after source binding', fields: mutablePrivateConfigLiveReferences,
    requiredChange: 'Snapshot documented callback and scalar references after canonical binding; retain copied nested values and add a caller-mutation regression. This does not attest to private callback closure internals or facility readiness.' }] : [],
  preservedStops: stops, actualLiveQueriesExecutedByReviewer: false, privateFilesRead: false, credentialsReadOrPrinted: false,
  databaseCalls: 0, providerNetworkCalls: 0, authWrites: 0, sdkJobs: 0, nativeActions: 0,
  privatePostgresDriverReviewed: false, actualConcretePrivateFactoryReviewed: false, completeExternalObserverReviewed: false,
  fullProviderCoordinatorPassed: false, twoThousandSessionsProved: false, targetScaleLoadPassed: false,
  ownerAcceptedCriteria: 3, ownerCriteria: 109, newOwnerAcceptance: false, production: false, realBilling: false,
  limitation: 'An independent re-evaluation of exact saved public live traces and current public helper source. These files retain evidence of bounded live checks executed by root; this reviewer did not execute new live checks. Selected results cannot establish full provider, server overlap, complete outbound observation, target-scale load, native or owner acceptance.' };
const bytes = JSON.stringify(report, null, 2) + '\n';
const markdown = `# Independent runtime evidence review — 2026-10-13\n\nThe offline peer check revalidated all **500** saved company projections, **9** preserved forecast identities and **491** new command responses. All **20 returned deployed source files** matched the approved hashes; the two deno.json files were omitted by readback and their installed bytes were not independently checked.\n\nThe activation and lease traces have distinct TLS connections and client overlap (${activationClientOverlapMs} ms and ${leaseClientOverlapMs} ms). Saved database readbacks show one activation and one lease, followed by natural expiry and a genuine MFA recovery review. These remain bounded trusted worker checks; backend execution overlap, whole provider and 2,000-session load are unproved.\n\nThe saved setup readback shows the authority, three Vault identities, two key references and three paused jobs. All four HTTP failure attempts and the later collision stop remain intact. Four delivery paths are registered; no actual send is proved by these fixtures.\n\n${report.actionableFindings.length ? 'The public provider still reads caller-mutable private configuration references after binding; copy the documented references and add a regression before claiming that source issue is closed.' : 'No caller-mutable reference pattern from the previously recorded finding remains; closure internals and concrete private facilities still require separate review.'}\n\nAll source and saved evidence hashes remained unchanged during this check. The JSON records every inspected public input. This peer made **zero** network, SQL, Auth, SDK or native calls, read no credentials and recorded no further owner acceptance. Acceptance stays **3/109**.\n`;
await fs.writeFile(path.join(root, `${prefix}.json`), bytes, { flag: 'wx', mode: 0o600 });
await fs.writeFile(path.join(root, `${prefix}.md`), markdown, { flag: 'wx', mode: 0o600 });
process.stdout.write(JSON.stringify({ path: `${prefix}.json`, sha256: hashBytes(bytes), markdown: `${prefix}.md`,
  markdownSha256: hashBytes(markdown), passed: true, scopes: 500, returnedWorkerSourceFiles: 20,
  openSourceFindings: report.actionableFindings.length, fullProviderCoordinatorPassed: false, targetScaleLoadPassed: false }) + '\n');
