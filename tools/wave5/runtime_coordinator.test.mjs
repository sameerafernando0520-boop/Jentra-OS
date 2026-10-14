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
} from './runtime_contract.mjs';
import { performAttempt, intervalOverlap, runBarrierBatch, runRace, runPacedWorkload, workloadClassAt, checkLoadResult, runLiveVerification,
  boundaryResult, validateExternalTransportObservation } from './runtime_coordinator.mjs';

// Controlled descriptors and virtual clocks test orchestration only. No JWTs, auth.users, network or live provider exists here.
const reviewBytes = fs.readFileSync(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json', import.meta.url));
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
  harnessReviewSha256: H, planSha256: H, observedAt: iso(-1000), validUntil: iso(3600000), installedMigrationCount: 115,
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

test('current runtime bundle is verified byte-for-byte and produces the exact 2,000-session distribution', () => {
  assert.equal(validateRuntimeReview(review), review);
  const slots = expectedSessionSlots(review);
  assert.equal(slots.length, 2000); assert.equal(slots.filter(s => s.actorLabel === 'foreign-member').length, 4);
  assert.equal(new Set(slots.map(s => s.scopeKey)).size, 500); assert.ok(slots.every(s => s.actorLabel !== 'operator'));
  const changed = structuredClone(review); changed.syntheticScopes[0].tenantId = freshId();
  assert.throws(() => validateRuntimeReview(changed), /RUNTIME_BUNDLE_HASH_MISMATCH/);
});

test('the endpoint inventory excludes model, webhook sending and unscoped worker dispatch', () => {
  assert.equal(OPERATIONS.claimLease.rpc, 'wave5_runtime_delivery_worker');
  assert.equal(OPERATIONS.indexedBillingRead.rpc, 'get_wave5_subscription');
  assert.ok(Object.values(OPERATIONS).every(op => !/model|external|wave5_delivery_worker/.test(op.rpc)));
  assert.equal(OPERATIONS.reserveOne.transport, 'trusted');
});

test('plan validation rejects a shortened, over-rate, wrong-target or incomplete workload', () => {
  assert.equal(validatePlan(plan, review), plan);
  for (const change of [{ warmupMs: 59999 }, { measuredMs: 1000 }, { maxRunMs: 900001 }, { maximumTimedRequests: 100001 },
    { requestsPerSecond: 400 }, { projectId: 'anotherproject' }, { url: `${PROJECT_URL}/redirect` }, { realBilling: true },
    { cases: plan.cases.slice(1) }, { maxInflight: 2001 }, { loadCommittedQuerySha256: null }]) {
    assert.throws(() => validatePlan({ ...plan, ...change }, review));
  }
});

test('owner decision binds the exact runtime scope; preparation binds the coordinator without inventing another owner approval', () => {
  assert.equal(validateApproval(approval, review, binding, now), approval);
  for (const change of [{ decision: 'pending' }, { source: { kind: 'agent_inference', reference: 'x', messageSha256: H } },
    { runtimeBundleSha256: H }, { runtimeFileSha256: 'a'.repeat(64) }, { approvedAt: iso(1) }, { installOriginalSix: true }]) {
    assert.throws(() => validateApproval({ ...approval, ...change }, review, binding, now));
  }
  assert.equal(validatePreparation(preparation, review, binding), preparation);
  for (const change of [{ planSha256: 'a'.repeat(64) }, { privateProviderSha256: 'a'.repeat(64) }, { sameApprovedOperationScope: false },
    { independentReview: { result: 'unreviewed', sha256: H, path: 'x' } }]) {
    assert.throws(() => validatePreparation({ ...preparation, ...change }, review, binding));
  }
});

test('live entry point refuses missing approval before invoking any private provider operation', async () => {
  let calls = 0;
  const provider = new Proxy({}, { get() { calls++; throw new Error('should never access private context'); } });
  await assert.rejects(runLiveVerification({ review, plan, approval: null, binding, provider, journal }), /EXPLICIT_OWNER_APPROVAL_REQUIRED/);
  assert.equal(calls, 0);
});

test('live entry revalidates canonical review and source-bound plan before touching private provider', async () => {
  let calls = 0;
  const provider = new Proxy({}, { get() { calls++; throw new Error('must not load private context'); } });
  const changedReview = structuredClone(review); changedReview.accounts[0].email = 'changed@example.invalid';
  const config = { review, plan, approval, preparation, independentReview, binding, provider, journal };
  await assert.rejects(runLiveVerification({ ...config, review: changedReview }), /RUNTIME_BUNDLE_HASH_MISMATCH/);
  await assert.rejects(runLiveVerification({ ...config, plan: { ...plan, requestsPerSecond: 100 } }), /PLAN_BODY_BINDING_MISMATCH/);
  assert.equal(calls, 0);
});

test('private factory context cannot mutate approved review, plan or bindings, and caller changes cannot affect its copy', () => {
  const editablePlan = structuredClone(plan);
  const context = reviewedExecutionContext({ review, plan: editablePlan, approval, preparation, independentReview, binding });
  assert.throws(() => { context.plan.cases[0].scopeKey = 'foreign'; }, TypeError);
  assert.throws(() => { context.review.syntheticScopes[0].tenantId = freshId(); }, TypeError);
  assert.throws(() => { context.binding.planBodySha256 = H; }, TypeError);
  editablePlan.requestsPerSecond = 20;
  assert.equal(context.plan.requestsPerSecond, 200);
  assert.equal(context.review.bundleSha256, review.bundleSha256);
});

test('a hashed independent review cannot be relabeled approved when its actual verdict or source bindings disagree', () => {
  assert.equal(validateIndependentPreparationReview(independentReview, preparation, review, binding), independentReview);
  for (const changed of [{ result: 'changes-requested' }, { planSha256: 'a'.repeat(64) }, { privateProviderSha256: 'a'.repeat(64) },
    { operationScopeSha256: H }, { additionalOwnerAuthorizationRequired: true }, { sourceBindingsVerified: false }]) {
    const other = { ...independentReview, ...changed };
    const rebound = { ...binding, independentReviewBodySha256: hashJson(other) };
    assert.throws(() => validateIndependentPreparationReview(other, preparation, review, rebound), /INDEPENDENT_PREPARATION_VERDICT_REQUIRED/);
  }
});

test('load-001 billing permission and duplicate execution require genuine MFA in the relevant real sessions', () => {
  const billingIndex = sessions.findIndex(s => s.scopeKey === 'load-001' && s.actorLabel === 'billing-admin');
  const changed = [...sessions]; changed[billingIndex] = { ...changed[billingIndex], aal: 'aal1', realMfaVerified: false };
  assert.throws(() => validateSessions(changed, review, preflight, now), /GENUINE_RUNTIME_MFA_REQUIRED/);
  const noPair = sessions.map(s => s.actorLabel === 'executor' && s.scopeKey !== 'runtime' ? { ...s, aal: 'aal1', realMfaVerified: false } : s);
  assert.throws(() => validateSessions(noPair, review, preflight, now), /GENUINE_EXECUTOR_SESSION_PAIR_REQUIRED/);
  const permitted = sessions.map(s => s.actorLabel === 'billing-admin' && !['runtime', 'load-001'].includes(s.scopeKey) ?
    { ...s, aal: 'aal1', realMfaVerified: false } : s);
  assert.equal(validateSessions(permitted, review, preflight, now), permitted);
});

test('fresh installed contracts, capacity, quiesced schedules and exact reviewed populations are mandatory', () => {
  assert.equal(validatePreflight(preflight, review, plan, binding, now), preflight);
  for (const change of [{ installedMigrationCount: 43 }, { installedMigrationCount: 114 }, { installedMigrationCount: 116 },
    { installedMigrationCount: 115.5 }, { installedMigrationCount: '115' }, { pending71Installed: false }, { observedAt: iso(-300001) },
    { scopeDigestSha256: 'b'.repeat(64) }, { capacitySupported: false }, { noFabricatedAuth: false }, { operatorMembershipCount: 1 },
    { nonemptyIndexedForecastsAll500: false }, { reviewedSchedulesQuiesced: false }, { noModelOrWebhookInLoad: false }]) {
    assert.throws(() => validatePreflight({ ...preflight, ...change }, review, plan, binding, now));
  }
});

test('real session validation requires 2,000 distinct online-verified server rows and exact actor slots', () => {
  assert.equal(validateSessions(sessions, review, preflight, now), sessions);
  for (const change of [{ sessionId: sessions[0].sessionId }, { serverSessionRowVerified: false }, { onlineAuthVerified: false },
    { actorId: authIds.operator }, { actorLabel: 'operator' }, { expiresAt: iso(899999) }, { revoked: true },
    { scopeKey: 'foreign' }, { issuer: 'https://wrong.example/auth/v1' }, { aal: 'aal1' }]) {
    const altered = [...sessions]; altered[1] = { ...sessions[1], ...change };
    assert.throws(() => validateSessions(altered, review, preflight, now));
  }
  assert.throws(() => validateSessions(sessions.slice(1), review, preflight, now), /TWO_THOUSAND_REAL_SESSIONS_REQUIRED/);
});

test('public records do not copy provider handles, raw tokens, response bodies or error details', async () => {
  const participant = controlledParticipant(0, { accessToken: 'private-test-value', handle: { secret: 'private-test-value' } });
  assert.ok(!JSON.stringify(publicParticipant(participant)).includes('private-test-value'));
  const events = []; const req = request();
  const result = await performAttempt({ participant, request: req, journal: async e => events.push(e), call: async (_p, r, c) => {
    c.onTransportStart(); c.onTransportEnd(); return response(r, { token: 'private-test-value', body: 'private-test-value' });
  } });
  assert.equal(result.outcome, 'applied'); assert.ok(!JSON.stringify(events).includes('private-test-value'));
  const failed = await performAttempt({ participant, request: request(), journal, call: async () => { throw new Error('private-test-value'); } });
  assert.equal(failed.failureCode, 'PROVIDER_FAILURE'); assert.ok(!JSON.stringify(failed).includes('private-test-value'));
});

test('provider GuardError text and uppercase private values are normalized instead of copied into public evidence', async () => {
  const events = [];
  for (const detail of ['private-controlled-detail', 'PRIVATE_TEST_VALUE']) {
    assert.equal(safeFailure(new GuardError(detail)), 'PROVIDER_FAILURE'); assert.equal(safeCode(detail), 'PROVIDER_FAILURE');
    const failed = await performAttempt({ participant: controlledParticipant(), request: request(), journal: async e => events.push(e),
      call: async () => { throw new GuardError(detail); } });
    assert.equal(failed.failureCode, 'PROVIDER_FAILURE'); assert.ok(!JSON.stringify(failed).includes(detail));
  }
  assert.ok(!JSON.stringify(events).includes('private-controlled-detail'));
  assert.ok(!JSON.stringify(events).includes('PRIVATE_TEST_VALUE'));
  assert.equal(safeFailure(new GuardError('TRANSPORT_TIMEOUT')), 'TRANSPORT_TIMEOUT');
});

test('slow evidence and provider queueing classify the actual send and prevent sends beyond the workload window', async () => {
  let virtualMs = 0, actualSends = 0;
  const clock = { wall: () => now + virtualMs, monotonic: () => virtualMs };
  const dispatchWindow = { epochMonoMs: 0, measurementStartMonoMs: 500, deadlineMonoMs: 1100,
    scheduledDueMonoMs: 0, maximumLagMs: 1000 };
  const config = { participant: controlledParticipant(), request: { ...request(), phase: 'timed' }, clock, dispatchWindow,
    journal: async e => { if (e.type === 'attempt-start') virtualMs += 600; },
    call: async (_p, r, c) => { if (virtualMs < 1000) virtualMs += 400; c.onTransportStart(); actualSends++; c.onTransportEnd(); return response(r); } };
  const first = await performAttempt(config);
  assert.equal(first.phase, 'measurement'); assert.equal(first.transportStartedMonoMs, 1000);
  const late = await performAttempt({ ...config, request: { ...request(), phase: 'timed' } });
  assert.equal(late.failureCode, 'WORKLOAD_DEADLINE_EXCEEDED'); assert.equal(late.phase, 'not-dispatched');
  assert.equal(late.transportStartedMonoMs, null); assert.equal(actualSends, 1);
});

test('a serial provider queue cannot send a timed request after the end or claim undispatched session coverage', async () => {
  let queue = Promise.resolve(), actualSends = 0;
  const result = await runPacedWorkload({ sessions: sessions.slice(0, 8), journal, durationMs: 30, warmupMs: 10,
    requestsPerSecond: 1000, maxRequests: 30, maxInflight: 100, timeoutMs: 200,
    call: async (_p, r, c) => {
      const task = queue.then(async () => { await delay(60, undefined, { signal: c.signal }); c.onTransportStart(); actualSends++;
        c.onTransportEnd(); return response(r); });
      queue = task.catch(() => {}); return task;
    } });
  assert.equal(actualSends, 0); assert.equal(result.requestsDispatched, 0); assert.ok(result.requestsScheduled > 0);
  assert.equal(result.measuredDistinctSessionIds, 0); assert.equal(result.measuredRequests, 0);
  assert.equal(result.failureCode, 'WORKLOAD_DEADLINE_EXCEEDED');
});

test('holding an entire warmup in the evidence queue fails actual dispatch lag instead of releasing a passing catch-up burst', async () => {
  let virtualMs = 0; const held = []; let actualSends = 0;
  const clock = { wall: () => now + virtualMs, monotonic: () => virtualMs,
    sleep: async ms => {
      for (let i = 0; i < 16; i++) await Promise.resolve();
      virtualMs += ms;
      if (virtualMs >= 60000) held.splice(0).forEach(resolve => resolve());
      await Promise.resolve();
    } };
  const result = await runPacedWorkload({ sessions, clock, durationMs: 360000, warmupMs: 60000,
    requestsPerSecond: 20, maxRequests: 7200, maxInflight: 2000,
    journal: async e => { if (e.type === 'attempt-start' && virtualMs < 60000) await new Promise(resolve => held.push(resolve)); },
    call: async (_p, r, c) => { c.onTransportStart(); actualSends++; c.onTransportEnd(); return response(r); } });
  assert.equal(result.failureCode, 'GENERATOR_CAPACITY_UNSUPPORTED'); assert.equal(result.warmupRequests, 0);
  assert.ok(result.maximumDispatchLagMs >= 60000); assert.equal(result.maximumSchedulerLagMs, 0);
  assert.ok(actualSends < 7200); assert.equal(result.requestsDispatched, actualSends);
  assert.throws(() => checkLoadResult(result, { ...plan, requestsPerSecond: 20, maximumTimedRequests: 7200 }));
});

test('response command mismatch, omitted transport hooks and unknown outcomes stay uncertain', async () => {
  const participant = controlledParticipant();
  const mismatch = await performAttempt({ participant, request: request(), journal, call: async (_p, r, c) => {
    c.onTransportStart(); c.onTransportEnd(); return response(r, { originalCommandId: freshId() });
  } });
  assert.equal(mismatch.outcome, 'uncertain'); assert.equal(mismatch.failureCode, 'RETURNED_COMMAND_ID_MISMATCH');
  const omitted = await performAttempt({ participant, request: request(), journal, call: async (_p, r) => response(r) });
  assert.equal(omitted.outcome, 'uncertain'); assert.equal(omitted.failureCode, 'ACTUAL_TRANSPORT_INTERVAL_REQUIRED');
  assert.throws(() => publicOutcome({ outcome: 'success' }), /INVALID_PROVIDER_OUTCOME/);
});

test('failed intent persistence prevents the request; pre-aborted runs do not dispatch', async () => {
  let dispatches = 0;
  await assert.rejects(performAttempt({ participant: controlledParticipant(), request: request(),
    journal: async () => { throw new Error('disk full'); }, call: async () => { dispatches++; } }));
  const aborted = new AbortController(); aborted.abort();
  const failed = await performAttempt({ participant: controlledParticipant(), request: request(), journal, signal: aborted.signal,
    call: async () => { dispatches++; } });
  assert.equal(dispatches, 0); assert.equal(failed.outcome, 'uncertain'); assert.equal(failed.failureCode, 'RUN_ABORTED');
});

test('public case-preparation intent retains exact reviewed identities and is acknowledged before any provider setup', async () => {
  const race = { ...plan.cases[0], privateInput: 'controlled-value-must-not-enter-public-case-intent' }, events = [], order = [];
  let acknowledged = false, acknowledgedAtPreparation = false;
  await assert.rejects(runRace({ race, review, preflight, sessions, clock: { wall: () => now, monotonic: () => 0 },
    journal: async event => { order.push('intent'); events.push(event); await Promise.resolve(); acknowledged = true; },
    provider: { prepareRace: async () => { order.push('prepare'); acknowledgedAtPreparation = acknowledged; throw new GuardError('RUN_ABORTED'); } } }),
  { code: 'RUN_ABORTED' });
  assert.deepEqual(order, ['intent', 'prepare']); assert.equal(acknowledgedAtPreparation, true); assert.equal(events.length, 1);
  const saved = events[0], scope = review.syntheticScopes.find(value => value.key === race.scopeKey);
  assert.equal(saved.type, 'case-preparation-intent'); assert.equal(saved.caseId, race.caseId); assert.equal(saved.kind, race.kind);
  assert.equal(saved.projectId, PROJECT_ID); assert.equal(saved.runtimeBundleSha256, review.bundleSha256);
  assert.equal(saved.scopeKey, race.scopeKey); assert.deepEqual(saved.scope, { tenantId: scope.tenantId, entityId: scope.entityId, branchId: scope.branchId });
  for (const name of ['fixturePlanSha256', 'preparationSha256', 'restorationSha256', 'committedQuerySha256']) assert.equal(saved[name], race[name]);
  assert.equal(saved.noExternalSend, true); assert.equal(saved.participants, race.participants); assert.equal(saved.intentAt, iso(0));
  assert.equal(JSON.stringify(saved).includes(race.privateInput), false);
});

test('failed public case-preparation persistence prevents the provider setup and every later case operation', async () => {
  let prepares = 0, reads = 0;
  await assert.rejects(runRace({ race: plan.cases[0], review, preflight, sessions,
    journal: async () => { throw new GuardError('EVIDENCE_WRITE_FAILED'); },
    provider: { prepareRace: async () => { prepares++; throw new GuardError('RUN_ABORTED'); },
      readCommitted: async () => { reads++; } } }), { code: 'EVIDENCE_WRITE_FAILED' });
  assert.equal(prepares, 0); assert.equal(reads, 0);
});

test('all readiness proofs precede the common release; real transport intervals overlap', async () => {
  const participants = [controlledParticipant(1), controlledParticipant(2)], requests = [request(), request()];
  let releaseSecond; const waitSecond = new Promise(resolve => { releaseSecond = resolve; });
  let dispatched = 0, readyCount = 0;
  const running = runBarrierBatch({ participants, requests, journal, arm: async (p, _r) => {
    if (p === participants[1]) await waitSecond;
    readyCount++; return { ready: true, connectionId: p.connectionId, evidenceSha256: H };
  }, call: async (_p, r, context) => {
    assert.equal(readyCount, 2); dispatched++; context.onTransportStart(); await delay(20); context.onTransportEnd(); return response(r);
  } });
  await delay(10); assert.equal(dispatched, 0); releaseSecond();
  const batch = await running;
  assert.equal(batch.clientOverlap.overlapped, true); assert.equal(batch.clientOverlap.peakConcurrent, 2);
  assert.ok(batch.clientOverlap.overlapMs > 0); assert.equal(batch.serverOverlap, null);
});

test('serial private transport is detected despite concurrently scheduled promises and slow journaling', async () => {
  let queue = Promise.resolve();
  const batch = await runBarrierBatch({ participants: [controlledParticipant(1), controlledParticipant(2)], requests: [request(), request()],
    journal: async () => delay(2), arm: async p => ({ ready: true, connectionId: p.connectionId, evidenceSha256: H }),
    call: async (_p, r, context) => {
      const task = queue.then(async () => { context.onTransportStart(); await delay(10); context.onTransportEnd(); return response(r); });
      queue = task.then(() => {}); return task;
    } });
  assert.equal(batch.clientOverlap.overlapped, false); assert.equal(batch.clientOverlap.peakConcurrent, 1);
});

test('duplicate Auth sessions and failed readiness cannot release a race', async () => {
  const a = controlledParticipant(1), b = controlledParticipant(2, { sessionId: a.sessionId }); let sent = 0;
  const config = { participants: [a, b], requests: [request(), request()], journal,
    arm: async p => ({ ready: true, connectionId: p.connectionId, evidenceSha256: H }), call: async () => { sent++; } };
  await assert.rejects(runBarrierBatch(config), /INDEPENDENT_AUTH_SESSIONS_REQUIRED/);
  config.participants[1] = controlledParticipant(2);
  config.arm = async () => ({ ready: false });
  await assert.rejects(runBarrierBatch(config), /ONLINE_BARRIER_READINESS_REQUIRED/); assert.equal(sent, 0);
});

test('a stalled transport times out once and is retained as uncertain without an automatic retry', async () => {
  let calls = 0;
  const attempt = await performAttempt({ participant: controlledParticipant(), request: request(), journal, timeoutMs: 10,
    call: async (_p, _r, context) => { calls++; context.onTransportStart(); return new Promise(() => {}); } });
  assert.equal(calls, 1); assert.equal(attempt.outcome, 'uncertain'); assert.equal(attempt.failureCode, 'TRANSPORT_TIMEOUT');
  assert.equal(attempt.transportFinishedAt, null);
});

test('overlap uses half-open actual transport intervals and never infers missing server spans', () => {
  const span = (start, end) => ({ transportStartedMonoMs: start, transportFinishedMonoMs: end });
  assert.equal(intervalOverlap([span(0, 10), span(10, 20)]).overlapped, false);
  assert.equal(intervalOverlap([span(0, 20), span(10, 30)]).overlapMs, 10);
  assert.equal(intervalOverlap([span(0, 20), { transportStartedMonoMs: null, transportFinishedMonoMs: null }]), null);
  assert.equal(intervalOverlap([span(0, 20), span(10, 30)], true), null);
});

test('committed snapshots reject rollback reads, wrong tenants, stale observations and losing effects', () => {
  const race = plan.cases[0], scope = review.syntheticScopes.find(s => s.key === race.scopeKey);
  const source = { kind: 'committed-state-snapshot', projectId: PROJECT_ID, caseId: race.caseId, scopeKey: scope.key,
    tenantId: scope.tenantId, readOnly: true, committed: true, isolation: 'repeatable-read', querySha256: H,
    snapshotSha256: H, transactionEvidenceSha256: H, observedAt: iso(0), ...snapshot() };
  assert.equal(validateCommittedSnapshot(source, race, scope, now).committed, true);
  for (const change of [{ committed: false }, { tenantId: freshId() }, { isolation: 'rollback-fixture' },
    { observedAt: iso(-1) }, { deniedAttemptEffects: [{ attemptId: freshId(), counters: { ...zeroCounters(), audit: 1 } }] }]) {
    assert.throws(() => validateCommittedSnapshot({ ...source, ...change }, race, scope, now));
  }
});

test('100 duplicate response successes still require exactly one committed business effect', () => {
  const entityId = freshId(), attempts = Array.from({ length: 100 }, () => ({ attemptId: freshId(), outcome: 'applied', entityId }));
  const before = snapshot(), after = snapshot({ business: 1, receipt: 1, audit: 1, outbox: 1 });
  assert.equal(checkRaceEffects('duplicates', before, after, attempts).business, 1);
  assert.throws(() => checkRaceEffects('duplicates', before, snapshot({ business: 100, receipt: 100, audit: 100, outbox: 100 }), attempts), /DUPLICATE_EFFECT_MISMATCH/);
});

test('20 quota reservations require ten units, ten denials and per-denial zero-effect evidence', () => {
  const attempts = Array.from({ length: 20 }, (_, i) => ({ attemptId: freshId(), outcome: i < 10 ? 'applied' : 'denied', code: i < 10 ? null : 'QUOTA_EXCEEDED' }));
  const after = snapshot({ usage: 10 }, { reservedUnits: 10 });
  after.deniedAttemptEffects = attempts.slice(10).map(a => ({ attemptId: a.attemptId, counters: zeroCounters() }));
  assert.equal(checkRaceEffects('quota', snapshot(), after, attempts).usage, 10);
  assert.throws(() => checkRaceEffects('quota', snapshot(), { ...after, deniedAttemptEffects: [] }, attempts), /DENIED_ZERO_EFFECT_PROOF_MISSING/);
  assert.throws(() => checkRaceEffects('quota', snapshot(), { ...after, state: state({ reservedUnits: 11 }) }, attempts), /QUOTA_EFFECT_MISMATCH/);
});

test('seat races enforce the final seat and do not forgive audit or receipt effects on a losing request', () => {
  const deniedId = freshId(), attempts = [{ attemptId: freshId(), outcome: 'applied' }, { attemptId: deniedId, outcome: 'denied', code: 'SEAT_QUOTA_EXCEEDED' }];
  const before = snapshot({}, { seatLimit: 3, activeAndInvited: 2 }), after = snapshot({ membership: 1, audit: 1 }, { seatLimit: 3, activeAndInvited: 3 });
  after.deniedAttemptEffects = [{ attemptId: deniedId, counters: zeroCounters() }];
  assert.equal(checkRaceEffects('seats', before, after, attempts).membership, 1);
  assert.throws(() => checkRaceEffects('seats', before, { ...after, state: state({ seatLimit: 3, activeAndInvited: 4 }) }, attempts), /SEAT_CAP_EXCEEDED/);
});

test('admission versus activation allows either lock winner while enforcing the shared seat cap', () => {
  const deniedId = freshId(), attempts = [{ attemptId: freshId(), outcome: 'applied' }, { attemptId: deniedId, outcome: 'denied', code: 'SEAT_QUOTA_EXCEEDED' }];
  const before = snapshot({}, { seatLimit: 3, activeAndInvited: 2 });
  for (const after of [snapshot({ membership: 1, audit: 1 }, { seatLimit: 3, activeAndInvited: 3 }),
    snapshot({ business: 1, activation: 1, receipt: 1, audit: 1, outbox: 1 }, { seatLimit: 2, activeAndInvited: 2 })]) {
    after.deniedAttemptEffects = [{ attemptId: deniedId, counters: zeroCounters() }];
    assert.ok(checkRaceEffects('admissions', before, after, attempts));
  }
});

test('activation, execution and lease response races require their own committed record counts', () => {
  assert.ok(checkRaceEffects('activation', snapshot(), snapshot({ activation: 1, business: 1, receipt: 1, audit: 1, outbox: 1 }, { subscriptionVersion: 2 }),
    [{ outcome: 'applied' }, { outcome: 'applied' }]));
  assert.ok(checkRaceEffects('execution', snapshot(), snapshot({ business: 2, receipt: 2, audit: 2, outbox: 2 }), [{ outcome: 'applied' }, { outcome: 'applied' }]));
  assert.ok(checkRaceEffects('outboxLeases', snapshot(), snapshot({ lease: 1 }), [{ outcome: 'applied' }, { outcome: 'empty' }]));
  assert.throws(() => checkRaceEffects('outboxLeases', snapshot(), snapshot({ lease: 1, usage: 1 }), [{ outcome: 'applied' }, { outcome: 'empty' }]), /LEASE_EFFECT_MISMATCH/);
  assert.throws(() => checkRaceEffects('outboxLeases', snapshot(), snapshot({ lease: 2, usage: 2 }), [{ outcome: 'applied' }, { outcome: 'applied' }]), /LEASE_EFFECT_MISMATCH/);
  assert.throws(() => checkRaceEffects('activation', snapshot(), snapshot(), [{ outcome: 'uncertain' }, { outcome: 'applied' }]), /UNCERTAIN_MUTATION_REQUIRES_REVIEW/);
});

test('the duplicate coordinator binds one original command, reads committed effects before and after overlap, and restores only reviewed state', async () => {
  const race = plan.cases.find(c => c.kind === 'duplicates'), scope = review.syntheticScopes.find(s => s.key === race.scopeKey);
  const originalCommandId = freshId(), idempotencyKey = freshId(), entityId = freshId();
  const events = [], sent = []; let reads = 0, restores = 0;
  const provider = { prepareRace: async () => ({ caseId: race.caseId, scopeKey: race.scopeKey, fixturePlanSha256: H,
    preparationSha256: H, restorationSha256: H, preparationEvidenceSha256: H, newReviewedScopesOnly: true,
    externalSendDisabled: true, originalCommandId, idempotencyKey, resourceId: freshId() }),
    readCommitted: async input => {
      assert.equal(input.scope.tenantId, scope.tenantId); reads++;
      if (reads === 1) assert.equal(sent.length, 0); else assert.equal(sent.length, 100);
      return { kind: 'committed-state-snapshot', projectId: PROJECT_ID, caseId: race.caseId, scopeKey: scope.key, tenantId: scope.tenantId,
        readOnly: true, committed: true, isolation: 'repeatable-read', querySha256: H, snapshotSha256: H,
        transactionEvidenceSha256: H, observedAt: new Date().toISOString(), ...snapshot(reads === 1 ? {} : { business: 1, receipt: 1, audit: 1, outbox: 1 }) };
    }, arm: async p => ({ ready: true, connectionId: p.connectionId, evidenceSha256: H }),
    call: async (_p, r, c) => { assert.equal(reads, 1); c.onTransportStart(); sent.push(r); await delay(10); c.onTransportEnd(); return response(r, { entityId }); },
    restoreRace: async input => { assert.equal(reads, 2); assert.equal(input.restorationSha256, H); restores++;
      return { exactReviewedRestoration: true, restorationSha256: H, evidenceSha256: H, noAcceptanceChanges: true }; } };
  const result = await runRace({ race, review, preflight, sessions, provider, journal: async e => events.push(e) });
  assert.equal(result.passed, true); assert.equal(result.effectDelta.business, 1); assert.equal(restores, 1);
  assert.equal(new Set(sent.map(r => r.commandId)).size, 1); assert.ok(sent.every(r => r.commandId === originalCommandId && r.idempotencyKey === idempotencyKey));
  assert.equal(new Set(result.attempts.map(a => a.participant.sessionId)).size, 100);
  assert.ok(events.findIndex(e => e.type === 'race-before') < events.findIndex(e => e.type === 'barrier-release'));
  assert.equal(events.at(-1).type, 'race-result'); assert.equal(result.serverOverlap, null);
});

test('unknown duplicate mutation preserves all original identities and skips restoration even when the committed read shows one effect', async () => {
  const race = plan.cases.find(c => c.kind === 'duplicates'), scope = review.syntheticScopes.find(s => s.key === race.scopeKey);
  const commandId = freshId(), key = freshId(), entityId = freshId(); let reads = 0, calls = 0, restored = false; const events = [];
  const provider = { prepareRace: async () => ({ caseId: race.caseId, scopeKey: race.scopeKey, fixturePlanSha256: H,
    preparationSha256: H, restorationSha256: H, preparationEvidenceSha256: H, newReviewedScopesOnly: true,
    externalSendDisabled: true, originalCommandId: commandId, idempotencyKey: key, resourceId: freshId() }),
    readCommitted: async () => ({ kind: 'committed-state-snapshot', projectId: PROJECT_ID, caseId: race.caseId, scopeKey: scope.key,
      tenantId: scope.tenantId, readOnly: true, committed: true, isolation: 'repeatable-read', querySha256: H, snapshotSha256: H,
      transactionEvidenceSha256: H, observedAt: new Date().toISOString(), ...snapshot(++reads === 1 ? {} : { business: 1, receipt: 1, audit: 1, outbox: 1 }) }),
    arm: async p => ({ ready: true, connectionId: p.connectionId, evidenceSha256: H }),
    call: async (_p, r, c) => { c.onTransportStart(); const ordinal = calls++; await delay(10); c.onTransportEnd();
      if (ordinal === 0) throw new Error('private-error-body'); return response(r, { entityId }); },
    restoreRace: async () => { restored = true; } };
  await assert.rejects(runRace({ race, review, preflight, sessions, provider, journal: async e => events.push(e) }), /UNCERTAIN_MUTATION_REQUIRES_REVIEW/);
  assert.equal(calls, 100); assert.equal(restored, false);
  const result = events.find(e => e.type === 'race-result'); assert.equal(result.restorationState, 'retained-for-owner-review');
  assert.ok(result.attempts.every(a => a.commandId === commandId)); assert.equal(result.attempts.filter(a => a.outcome === 'uncertain').length, 1);
  assert.ok(!JSON.stringify(events).includes('private-error-body'));
});

test('nearest-rank p95 uses measured samples and strict limits rather than averaging them', () => {
  assert.equal(nearestRankP95(Array.from({ length: 100 }, (_, index) => index + 1)), 95);
  assert.equal(nearestRankP95([100, 1]), 100); assert.throws(() => nearestRankP95([]));
  assert.deepEqual(Array.from({ length: 10 }, (_, i) => workloadClassAt(i)), [
    'indexedReads', 'indexedReads', 'indexedReads', 'indexedReads', 'indexedReads', 'indexedReads', 'indexedReads',
    'ordinaryForecastCommands', 'ordinaryForecastCommands', 'boundedAnalytics']);
});

test('unsupported limit fixtures remain blocked and never masquerade as actual rejection evidence', () => {
  const boundary = plan.boundaries[0];
  const source = { status: 'unsupported-under-reviewed-scope', caseId: boundary.caseId, fixturePlanSha256: boundary.fixturePlanSha256,
    noOperationAttempted: true, existingScopeOnly: true, fixtureEvidenceSha256: H, reasonCode: 'ROW_FIXTURE_EXCEEDS_REVIEWED_CAPS' };
  const result = boundaryResult(source, boundary);
  assert.equal(result.passed, false); assert.equal(result.executed, false); assert.equal(result.blocked, true);
  assert.throws(() => boundaryResult({ ...source, reasonCode: 'PRIVATE_TEST_VALUE' }, boundary), /UNSUPPORTED_BOUNDARY_PROOF_REQUIRED/);
  assert.throws(() => boundaryResult({ ...source, noOperationAttempted: false }, boundary), /UNSUPPORTED_BOUNDARY_PROOF_REQUIRED/);
  assert.throws(() => boundaryResult({ caseId: boundary.caseId, actualLimitRejection: true, code: 'LIMIT_EXCEEDED' }, boundary));
  const genuine = { caseId: boundary.caseId, fixturePlanSha256: H, querySha256: H, actualLimitRejection: true,
    code: 'LIMIT_EXCEEDED', responseSha256: H, committedEvidenceSha256: H, committedEffectDelta: zeroCounters() };
  assert.equal(boundaryResult(genuine, boundary).passed, true);
  assert.throws(() => boundaryResult({ ...genuine, committedEffectDelta: { ...zeroCounters(), audit: 1 } }, boundary));
});

test('database row counters never substitute for an actual no-send observation covering all reviewed workers and the full load window', () => {
  const window = { startedAt: iso(0), finishedAt: iso(360000) };
  const source = { kind: 'online-no-external-transport-observation', projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256,
    scopeDigestSha256: hashJson(review.syntheticScopes), observerSourceSha256: H, transportTraceSha256: H, jobsStateEvidenceSha256: H,
    observedFromAt: iso(-1), observedUntilAt: iso(360001), allReviewedModelDeliveryWorkersCovered: true,
    reviewedJobsInactiveAndNoInflight: true, modelDispatchesObserved: 0, webhookDispatchesObserved: 0 };
  assert.equal(validateExternalTransportObservation(source, review, plan, window).webhookDispatchesObserved, 0);
  for (const change of [{ kind: 'committed-load-population-snapshot' }, { transportTraceSha256: null },
    { allReviewedModelDeliveryWorkersCovered: false }, { reviewedJobsInactiveAndNoInflight: false },
    { observedFromAt: iso(1) }, { observedUntilAt: iso(359999) }, { modelDispatchesObserved: 1 }, { webhookDispatchesObserved: 1 }]) {
    assert.throws(() => validateExternalTransportObservation({ ...source, ...change }, review, plan, window), /ACTUAL_EXTERNAL_TRANSPORT_OBSERVATION_REQUIRED/);
  }
});

test('paced dispatch uses every measured session, gives billing actors read permission only and mints fresh command identities', async () => {
  let virtualMs = 0; const events = [];
  const clock = { wall: () => now + virtualMs, monotonic: () => virtualMs,
    sleep: async ms => { for (let i = 0; i < 16; i++) await Promise.resolve(); virtualMs += ms; await Promise.resolve(); } };
  const result = await runPacedWorkload({ sessions, call: transportResponse, journal: async e => { if (e.type === 'attempt-start') events.push(e); },
    durationMs: 360000, warmupMs: 60000, requestsPerSecond: 20, maxRequests: 7200, maxInflight: 2000, clock });
  assert.equal(result.requestsDispatched, 7200); assert.equal(result.measuredDistinctSessionIds, 2000);
  assert.equal(result.measuredDistinctScopes, 500); assert.equal(result.warmupRequests, 1200);
  assert.equal(result.summaries.indexedReads.samples, 4200); assert.equal(result.summaries.ordinaryForecastCommands.samples, 1200);
  assert.equal(result.summaries.boundedAnalytics.samples, 600);
  assert.ok(events.filter(e => e.participant.actorLabel === 'billing-admin').every(e => e.operation === 'indexedBillingRead'));
  const commands = events.filter(e => e.operation === 'forecast'); assert.equal(new Set(commands.map(e => e.commandId)).size, commands.length);
  assert.ok(result.samples.every(s => !s.failureCode));
  assert.equal(checkLoadResult(result, { ...plan, requestsPerSecond: 20, maximumTimedRequests: 7200 }), true);
  controlledCompleteLoad = structuredClone(result);
  // This controlled result is deliberately not a live result or an owner acceptance record.
  assert.equal(result.gates, undefined);
});

test('a rejected timed request aborts subsequent dispatch and cannot be renamed a successful workload', async () => {
  let virtualMs = 0, dispatchedDenials = 0;
  const clock = { wall: () => now + virtualMs, monotonic: () => virtualMs,
    sleep: async ms => { for (let i = 0; i < 16; i++) await Promise.resolve(); virtualMs += ms; await Promise.resolve(); } };
  const result = await runPacedWorkload({ sessions: sessions.slice(0, 8), call: async (_p, r, c) => {
    c.onTransportStart(); dispatchedDenials++; c.onTransportEnd(); return response(r, { outcome: 'denied', code: 'PERMISSION_DENIED' });
  }, journal, durationMs: 50, warmupMs: 0, requestsPerSecond: 1000, maxRequests: 50, maxInflight: 20, clock });
  assert.ok(dispatchedDenials >= 1); assert.equal(result.requestsDispatched, dispatchedDenials);
  assert.ok(result.samples.some(value => value.outcome === 'denied' && value.code === 'PERMISSION_DENIED'));
  assert.equal(result.failureCode, 'LOAD_REQUEST_REJECTED'); assert.ok(result.requestsDispatched < 50);
  assert.throws(() => checkLoadResult(result, plan), /TARGET_SCALE_DURATION_OR_COVERAGE_INCOMPLETE/);
});

test('unsupported generator inflight capacity is retained as incomplete without silently dropping samples', async () => {
  let virtualMs = 0, dispatched = 0, firstTransportHeld = false;
  const clock = { wall: () => now + virtualMs, monotonic: () => virtualMs,
    sleep: async ms => { for (let i = 0; i < 16; i++) await Promise.resolve(); virtualMs += ms; await Promise.resolve(); } };
  const result = await runPacedWorkload({ sessions: sessions.slice(0, 8), call: async (_p, r, c) => {
    c.onTransportStart(); dispatched++;
    await new Promise(resolve => { firstTransportHeld = true;
      const release = () => { c.signal.removeEventListener('abort', release); resolve(); };
      if (c.signal.aborted) release(); else c.signal.addEventListener('abort', release, { once: true });
    });
    c.onTransportEnd(); return response(r);
  }, journal, durationMs: 40, warmupMs: 0, requestsPerSecond: 1000, maxRequests: 40, maxInflight: 1, timeoutMs: 100, clock });
  assert.equal(firstTransportHeld, true); assert.equal(dispatched, 1); assert.equal(result.requestsDispatched, dispatched);
  assert.equal(result.samples.length, dispatched);
  assert.equal(result.failureCode, 'GENERATOR_CAPACITY_UNSUPPORTED'); assert.equal(result.peakInflightRequests, 1);
  assert.throws(() => checkLoadResult(result, plan));
});

test('a latency equal to the limit fails, and warmup, incomplete coverage or a cached command cannot pass the load gate', () => {
  const make = () => structuredClone(controlledCompleteLoad);
  const matchingPlan = { ...plan, requestsPerSecond: 20, maximumTimedRequests: 7200 };
  const limit = make(); limit.summaries.indexedReads.p95Ms = LOAD_LIMITS.p95Ms.indexedReads;
  assert.throws(() => checkLoadResult(limit, matchingPlan), /LOAD_P95_FAILED/);
  for (const change of [{ dispatchDurationMs: 359999 }, { requestedWarmupMs: 0 }, { warmupRequests: 0 },
    { maximumDispatchLagMs: 1001 }, { samples: [] }, { measuredDistinctSessionIds: 1999 }, { measuredDistinctScopes: 499 }]) {
    assert.throws(() => checkLoadResult({ ...make(), ...change }, matchingPlan));
  }
  const cached = make(); const commands = cached.samples.filter(s => s.operation === 'forecast');
  commands[1].commandId = commands[0].commandId; commands[1].originalCommandId = commands[0].originalCommandId;
  assert.throws(() => checkLoadResult(cached, matchingPlan), /FRESH_FORECAST_COMMANDS_REQUIRED/);
});

test('failed durable live-start journaling clears the run timer and closes the provider before a failed finish write', async () => {
  const nativeSetTimeout = globalThis.setTimeout, nativeClearTimeout = globalThis.clearTimeout;
  const runTimers = new Set(); let clearCalls = 0, closed = 0, operations = 0; const attemptedWrites = [];
  globalThis.setTimeout = (callback, ms, ...args) => {
    const handle = nativeSetTimeout(callback, ms, ...args);
    if (ms === LOAD_LIMITS.maxRunMs) runTimers.add(handle);
    return handle;
  };
  globalThis.clearTimeout = handle => {
    if (runTimers.has(handle)) clearCalls++;
    return nativeClearTimeout(handle);
  };
  const provider = Object.fromEntries(['verifyPreflight', 'openSessions', 'reverifySessions', 'openTrustedConnections',
    'prepareRace', 'arm', 'call', 'readCommitted', 'readLoadCommitted', 'readExternalTransportObservation',
    'restoreRace', 'runInvalidBoundary'].map(name => [name, async () => { operations++; throw new GuardError('RUN_ABORTED'); }]));
  provider.close = async options => {
    closed++;
    assert.equal(options.preserveUnknownEffects, true);
    assert.equal(options.noCleanupOfAccountsOrStores, true);
    assert.equal(options.signal.aborted, false);
  };
  try {
    await assert.rejects(runLiveVerification({ review, plan, approval, preparation, independentReview, binding, provider,
      journal: async entry => { attemptedWrites.push(entry); throw new GuardError('EVIDENCE_WRITE_FAILED'); } }),
    { code: 'EVIDENCE_WRITE_FAILED' });
    assert.equal(operations, 0); assert.equal(closed, 1);
    assert.equal(runTimers.size, 1); assert.equal(clearCalls, 1);
    assert.deepEqual(attemptedWrites.map(entry => entry.type), ['live-start', 'live-finish']);
    const finish = attemptedWrites.at(-1);
    assert.equal(finish.passed, false); assert.equal(finish.failureCode, 'EVIDENCE_WRITE_FAILED');
    assert.ok(Object.values(finish.gates).every(value => value === false));
    assert.equal(finish.load, null); assert.equal(finish.races.length, 0);
  } finally {
    globalThis.setTimeout = nativeSetTimeout; globalThis.clearTimeout = nativeClearTimeout;
    // Keep a failed regression bounded when tested against the uncorrected implementation.
    for (const handle of runTimers) nativeClearTimeout(handle);
  }
});
