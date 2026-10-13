import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import {
  PROJECT_ID, PROJECT_URL, RACE_KINDS, BOUNDARY_KINDS, COUNTERS, LOAD_CLASSES, LOAD_LIMITS, OPERATIONS,
  freshId, hashJson, hashBytes, zeroCounters, validateRuntimeReview, expectedSessionSlots, validatePlan,
  validateApproval, validatePreparation, validatePreflight, validateSessions, publicParticipant, publicOutcome,
  validateCommittedSnapshot, checkRaceEffects, nearestRankP95, GuardError, safeFailure, safeCode, reviewedExecutionContext,
  validateIndependentPreparationReview,
} from '../../../../tools/wave5/runtime_contract.mjs';
import { performAttempt, intervalOverlap, runBarrierBatch, runRace, runPacedWorkload, workloadClassAt, checkLoadResult, runLiveVerification,
  boundaryResult, validateExternalTransportObservation } from '../../../../tools/wave5/runtime_coordinator.mjs';

// Controlled descriptors and virtual clocks test orchestration only. No JWTs, auth.users, network or live provider exists here.
const reviewBytes = fs.readFileSync(new URL('../complete-app-runtime-review-20261010-r5.json', import.meta.url));
const review = JSON.parse(reviewBytes.toString('utf8'));
const H = hashBytes('controlled test evidence, never live proof');
const now = Date.parse('2026-10-12T00:00:00Z');
const iso = offset => new Date(now + offset).toISOString();
const authIds = Object.fromEntries(review.accounts.map(a => [a.label, freshId()]));
const binding = { runtimeFileSha256: hashBytes(reviewBytes), harnessReviewSha256: H, planSha256: H, privateProviderSha256: H };
const plan = {
  kind: 'wave5-runtime-harness-plan', projectId: PROJECT_ID, url: PROJECT_URL, production: false, realBilling: false,
  runtimeBundleSha256: review.bundleSha256, warmupMs: 60000, measuredMs: 300000, maxRunMs: 900000,
  maximumTimedRequests: 72000, maxInflight: 2000, requestsPerSecond: 200, loadCommittedQuerySha256: H, loadFixturePlanSha256: H,
  externalObservationSourceSha256: H,
  cases: RACE_KINDS.map(kind => ({ kind, scopeKey: ['quota', 'seats', 'admissions'].includes(kind) ? 'load-001' : 'runtime',
    caseId: freshId(), participants: kind === 'duplicates' ? 100 : kind === 'quota' ? 20 : 2,
    fixturePlanSha256: H, committedQuerySha256: H, preparationSha256: H, restorationSha256: H, noExternalSend: true })),
  boundaries: BOUNDARY_KINDS.map(kind => ({ kind, scopeKey: 'runtime', caseId: freshId(), fixturePlanSha256: H,
    committedQuerySha256: H, expectedCode: 'LIMIT_EXCEEDED' })),
};
binding.planBodySha256 = hashJson(plan);
const approval = { kind: 'wave5-runtime-owner-decision', decision: 'approve', source: {
  kind: 'direct_user_message', reference: 'CONTROLLED-UNIT-TEST-NOT-A-USER-DECISION', messageSha256: H },
  runtimeBundleSha256: review.bundleSha256, ...binding, projectId: PROJECT_ID, production: false, realBilling: false,
  installOriginalSix: false, noGlobalAuthChanges: true, approvedAt: iso(-1000) };
const preparation = { kind: 'wave5-runtime-harness-preparation', sourceBindingsVerified: true,
  runtimeBundleSha256: review.bundleSha256, ...binding, independentReview: { result: 'approved-for-existing-bounded-scope', sha256: H,
    path: 'CONTROLLED-UNIT-TEST-NOT-AN-INDEPENDENT-REVIEW.json' }, sameApprovedOperationScope: true,
  additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
const independentReview = { kind: 'wave5-runtime-harness-independent-preparation-review', projectId: PROJECT_ID,
  result: 'approved-for-existing-bounded-scope', runtimeBundleSha256: review.bundleSha256, ...binding,
  sourceBindingsVerified: true, operationScopeSha256: review.sourceContinuation.unchangedRuntimeOperationScopeSha256,
  sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
binding.independentReviewBodySha256 = hashJson(independentReview);
const preflight = {
  kind: 'online-installed-wave5-harness-preflight', projectId: PROJECT_ID, url: PROJECT_URL, runtimeBundleSha256: review.bundleSha256,
  harnessReviewSha256: H, planSha256: H, observedAt: iso(-1000), validUntil: iso(3600000), installedMigrationCount: 114,
  pending71Installed: true, originalSixPreserved: true, signaturesGrantsForcedRlsVerified: true, protectedSourcesUnchanged: true,
  scopeDigestSha256: hashJson(review.syntheticScopes), capacitySupported: true, noGlobalAuthChanges: true,
  noFabricatedAuth: true, noAcceptanceScopes: true, ledgerSha256: H, contractFingerprintSha256: H, capacityEvidenceSha256: H,
  rowDistributionSha256: H, authCreationEvidenceSha256: H, fixturePopulationSha256: H, fixtureCapsVerified: true,
  nonemptyIndexedForecastsAll500: true, nonemptyProcessSourcesAll500: true, reviewedSchedulesQuiesced: true, noModelOrWebhookInLoad: true,
  authIds, operatorMembershipCount: 0, environment: { region: 'controlled', databaseTier: 'controlled', postgresVersion: 'controlled',
    generatorHost: 'controlled', cacheConditions: 'controlled', hardwareSha256: H, maximumConcurrentSessions: 2000, maximumRequestsPerSecond: 200 },
};
function controlledParticipant(index = 0, overrides = {}) {
  const id = freshId();
  return { kind: 'auth', actorLabel: 'proposer', actorId: authIds.proposer, sessionId: id, serverSessionId: id,
    serverSessionActorId: authIds.proposer, scopeKey: 'runtime', ordinal: 0, connectionId: `controlled-${index}-${id}`,
    connectionEvidenceSha256: H, verificationEvidenceSha256: H, onlineAuthVerified: true, serverSessionRowVerified: true,
    issuer: `${PROJECT_URL}/auth/v1`, authRole: 'authenticated', verifiedAt: iso(-1000), expiresAt: iso(3600000),
    revoked: false, aal: 'aal2', realMfaVerified: true, verifiedFactorId: freshId(), ...overrides };
}
const sessions = expectedSessionSlots(review).map((slot, index) => controlledParticipant(index, { ...slot,
  actorId: authIds[slot.actorLabel], serverSessionActorId: authIds[slot.actorLabel] }));
const request = () => { const id = freshId(); return { attemptId: freshId(), commandId: id, idempotencyKey: id,
  operation: 'forecast', scopeKey: 'runtime', phase: 'race' }; };
const response = (req, extra = {}) => ({ outcome: 'applied', originalCommandId: req.commandId ?? null, entityId: freshId(),
  responseSha256: H, transportEvidenceSha256: H, ...extra });
const journal = async () => {};
const transportResponse = async (_participant, req, context) => { context.onTransportStart(); context.onTransportEnd(); return response(req); };
const state = extra => ({ reservedUnits: 0, settledUnits: 0, seatLimit: 4, activeAndInvited: 2, subscriptionVersion: 1, ...extra });
const snapshot = (counters = {}, values = {}) => ({ counters: { ...zeroCounters(), ...counters }, state: state(values), deniedAttemptEffects: [] });
let controlledCompleteLoad;


const nativeSetTimeout=globalThis.setTimeout, nativeClearTimeout=globalThis.clearTimeout;
const runTimers=new Set(); let coordinatorClearCalls=0, providerCloseCalls=0, providerOperationCalls=0, journalCalls=0;
const before=hashBytes(fs.readFileSync(new URL('../../../../tools/wave5/runtime_coordinator.mjs',import.meta.url)));
assert.equal(before,'1df1396865610b73614f5ba9b83a8d9b91d40bb642e26d7443934ef11bcd0f3c');
globalThis.setTimeout=(fn,ms,...args)=>{const handle=nativeSetTimeout(fn,ms,...args);if(ms===LOAD_LIMITS.maxRunMs)runTimers.add(handle);return handle;};
globalThis.clearTimeout=handle=>{if(runTimers.has(handle))coordinatorClearCalls++;return nativeClearTimeout(handle);};
const provider=Object.fromEntries(['verifyPreflight','openSessions','reverifySessions','openTrustedConnections','prepareRace','arm','call','readCommitted','readLoadCommitted','readExternalTransportObservation','restoreRace','runInvalidBoundary'].map(name=>[name,async()=>{providerOperationCalls++;throw new GuardError('RUN_ABORTED');}]));
provider.close=async()=>{providerCloseCalls++;};
let failureCode=null, result;
const actualStartedAt=new Date().toISOString();
try {await runLiveVerification({review,plan,approval,preparation,independentReview,binding,provider,journal:async()=>{journalCalls++;throw new GuardError('EVIDENCE_WRITE_FAILED');}});}
catch(error){failureCode=safeFailure(error);}
finally {
  result={kind:'controlled-startup-journal-cleanup-diagnostic',actualStartedAt,actualFinishedAt:new Date().toISOString(),coordinatorSourceSha256:before,failureCode,journalCalls,providerOperationCalls,providerCloseCalls,runTimersCreated:runTimers.size,coordinatorClearCalls,issueReproduced:failureCode==='EVIDENCE_WRITE_FAILED'&&runTimers.size===1&&coordinatorClearCalls===0&&providerCloseCalls===0,probeExplicitlyClearedRetainedTimers:true,controlledProviderOnly:true,genuineAuth:false,networkCalls:0,executedLive:false,SDKJobs:0,nativeActions:0,privateInputRead:false};
  globalThis.setTimeout=nativeSetTimeout;globalThis.clearTimeout=nativeClearTimeout;
  for(const handle of runTimers)nativeClearTimeout(handle);
}
result.coordinatorSourceUnchanged=hashBytes(fs.readFileSync(new URL('../../../../tools/wave5/runtime_coordinator.mjs',import.meta.url)))===before;
fs.writeFileSync(new URL('./runtime-harness-startup-journal-diagnostic-20261013-peer-a1.json',import.meta.url),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(result));
assert.equal(result.issueReproduced,true);assert.equal(result.coordinatorSourceUnchanged,true);assert.equal(providerOperationCalls,0);
