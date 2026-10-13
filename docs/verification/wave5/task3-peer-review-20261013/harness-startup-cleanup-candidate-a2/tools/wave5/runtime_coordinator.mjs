import { performance } from 'node:perf_hooks';
import { setTimeout as sleep } from 'node:timers/promises';
import { setMaxListeners } from 'node:events';
import {
  PROJECT_ID, PROJECT_URL, LOAD_CLASSES, LOAD_LIMITS, OPERATIONS, COUNTERS, RACE_KINDS, GuardError,
  requireGuard, hashJson, freshId, isSha, isUuid, safeFailure, reviewedExecutionContext,
  validatePreflight, validateSessions, validateConnection, publicParticipant, publicOutcome,
  validateCommittedSnapshot, checkRaceEffects, nearestRankP95,
} from './runtime_contract.mjs';

export const realClock = Object.freeze({ monotonic: () => performance.now(), wall: () => Date.now(),
  sleep: (ms, signal) => sleep(Math.max(0, ms), undefined, { signal }) });
const stamp = clock => new Date(clock.wall()).toISOString();

async function boundedCall(operation, timeoutMs, parentSignal) {
  requireGuard(!parentSignal?.aborted, 'RUN_ABORTED');
  const controller = new AbortController();
  const abort = () => controller.abort();
  parentSignal?.addEventListener('abort', abort, { once: true });
  if (parentSignal?.aborted) abort();
  let timer;
  try {
    return await Promise.race([
      Promise.resolve().then(() => operation(controller.signal)),
      new Promise((_, reject) => { timer = setTimeout(() => { reject(new GuardError('TRANSPORT_TIMEOUT')); abort(); }, timeoutMs); }),
      new Promise((_, reject) => controller.signal.addEventListener('abort', () => reject(new GuardError('RUN_ABORTED')), { once: true })),
    ]);
  } finally { clearTimeout(timer); parentSignal?.removeEventListener('abort', abort); }
}

// Only fixed public fields reach the evidence writer. Provider errors/raw responses/handles never do.
export async function performAttempt({ participant, request, call, journal, clock = realClock, signal,
  timeoutMs = LOAD_LIMITS.requestTimeoutMs, dispatchWindow = null }) {
  if (dispatchWindow) requireGuard(['epochMonoMs', 'measurementStartMonoMs', 'deadlineMonoMs', 'scheduledDueMonoMs',
    'maximumLagMs'].every(k => Number.isFinite(dispatchWindow[k]))
    && dispatchWindow.epochMonoMs <= dispatchWindow.measurementStartMonoMs
    && dispatchWindow.measurementStartMonoMs < dispatchWindow.deadlineMonoMs && dispatchWindow.maximumLagMs >= 0
    && dispatchWindow.scheduledDueMonoMs >= dispatchWindow.epochMonoMs
    && dispatchWindow.scheduledDueMonoMs < dispatchWindow.deadlineMonoMs, 'INVALID_DISPATCH_WINDOW');
  const entry = { attemptId: request.attemptId, commandId: request.commandId ?? null,
    idempotencyKey: request.idempotencyKey ?? null, operation: request.operation,
    scopeKey: request.scopeKey, phase: dispatchWindow ? 'not-dispatched' : request.phase ?? 'race', class: request.class ?? null,
    requestSha256: hashJson(request), participant: publicParticipant(participant), intentAt: stamp(clock),
    outcome: 'uncertain', failureCode: null, transportStartedAt: null, transportStartedMonoMs: null,
    transportFinishedAt: null, transportFinishedMonoMs: null,
    scheduledDueMonoMs: dispatchWindow?.scheduledDueMonoMs ?? null, dispatchLagMs: null };
  // Persist original identities before dispatch. Failure to persist stops the send.
  await journal({ type: 'attempt-start', ...entry });
  entry.startedAt = stamp(clock); entry.startedMonoMs = clock.monotonic();
  let outcome;
  try {
    let notified = false, ended = false;
    const raw = await boundedCall(childSignal => call(participant, request, { signal: childSignal, onTransportStart: () => {
      requireGuard(!notified, 'DUPLICATE_TRANSPORT_START');
      requireGuard(!childSignal.aborted, 'RUN_ABORTED');
      const actualStart = clock.monotonic();
      // This synchronous hook is called after provider queueing, immediately before the real send.
      // A provider must stop when it throws; journal/provider delays cannot extend the reviewed workload.
      if (dispatchWindow) {
        entry.dispatchLagMs = actualStart - dispatchWindow.scheduledDueMonoMs;
        requireGuard(actualStart >= dispatchWindow.epochMonoMs, 'WORKLOAD_NOT_STARTED');
        requireGuard(entry.dispatchLagMs >= 0, 'EARLY_WORKLOAD_DISPATCH');
        requireGuard(actualStart < dispatchWindow.deadlineMonoMs, 'WORKLOAD_DEADLINE_EXCEEDED');
        requireGuard(entry.dispatchLagMs <= dispatchWindow.maximumLagMs, 'GENERATOR_CAPACITY_UNSUPPORTED');
        entry.phase = actualStart < dispatchWindow.measurementStartMonoMs ? 'warmup' : 'measurement';
      }
      notified = true; entry.transportStartedAt = stamp(clock); entry.transportStartedMonoMs = actualStart;
    }, onTransportEnd: () => {
      requireGuard(notified && !ended, 'INVALID_TRANSPORT_END'); ended = true;
      entry.transportFinishedAt = stamp(clock); entry.transportFinishedMonoMs = clock.monotonic();
    } }), timeoutMs, signal);
    requireGuard(notified && ended, 'ACTUAL_TRANSPORT_INTERVAL_REQUIRED');
    outcome = publicOutcome(raw);
    requireGuard(outcome.originalCommandId === entry.commandId, 'RETURNED_COMMAND_ID_MISMATCH');
    Object.assign(entry, outcome);
  } catch (error) { entry.failureCode = safeFailure(error); }
  entry.finishedAt = stamp(clock); entry.finishedMonoMs = clock.monotonic();
  entry.elapsedMs = entry.finishedMonoMs - entry.startedMonoMs;
  await journal({ type: 'attempt-finish', ...entry });
  return entry;
}

export function intervalOverlap(entries, server = false) {
  const spans = entries.map(e => server && e.serverSpan ?
    [Date.parse(e.serverSpan.startedAt), Date.parse(e.serverSpan.finishedAt)] :
    server ? null : e.transportStartedMonoMs === null || e.transportStartedMonoMs === undefined
      || e.transportFinishedMonoMs === null || e.transportFinishedMonoMs === undefined ? null : [e.transportStartedMonoMs, e.transportFinishedMonoMs]);
  if (spans.some(s => s === null)) return null;
  const ordered = spans.filter(s => s && s[1] > s[0]).flatMap(([start, end]) => [[start, 1], [end, -1]])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  let active = 0, peak = 0, overlapMs = 0, last = null;
  for (const [time, movement] of ordered) {
    if (last !== null && active >= 2) overlapMs += time - last;
    active += movement; peak = Math.max(peak, active); last = time;
  }
  return { peakConcurrent: peak, overlapMs, overlapped: peak >= 2 && overlapMs > 0 };
}

export async function runBarrierBatch({ participants, requests, arm, call, journal, clock = realClock, signal,
  timeoutMs = LOAD_LIMITS.requestTimeoutMs }) {
  requireGuard(participants.length === requests.length && participants.length >= 2
    && new Set(participants.map(p => p.connectionId)).size === participants.length, 'INDEPENDENT_BARRIER_PARTICIPANTS_REQUIRED');
  for (const participant of participants) validateConnection(participant);
  const auth = participants.filter(p => p.kind === 'auth');
  requireGuard(new Set(auth.map(p => p.sessionId)).size === auth.length, 'INDEPENDENT_AUTH_SESSIONS_REQUIRED');
  const barrierId = freshId();
  const ready = await Promise.all(participants.map(async (participant, index) => {
    const proof = await boundedCall(s => arm(participant, requests[index], { barrierId, signal: s }), timeoutMs, signal);
    requireGuard(proof?.ready === true && proof.connectionId === participant.connectionId && isSha(proof.evidenceSha256), 'ONLINE_BARRIER_READINESS_REQUIRED');
    return { participant: publicParticipant(participant), readyAt: stamp(clock), readyMonoMs: clock.monotonic(), evidenceSha256: proof.evidenceSha256 };
  }));
  const releasedAt = stamp(clock), releasedMonoMs = clock.monotonic();
  await journal({ type: 'barrier-release', barrierId, releasedAt, releasedMonoMs, ready });
  // Readiness completes before a single common release. There is no sequential retry loop.
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const pending = participants.map(async (participant, index) => {
    await gate;
    return performAttempt({ participant, request: requests[index], call, journal, clock, signal, timeoutMs });
  });
  release();
  const attempts = await Promise.all(pending);
  const clientOverlap = intervalOverlap(attempts), serverOverlap = intervalOverlap(attempts, true);
  return { barrierId, releasedAt, releasedMonoMs, ready, attempts, clientOverlap, serverOverlap,
    overlapClaim: 'Client request intervals; backend spans are separate and absent unless the provider supplies actual server evidence.' };
}

function raceOperations(kind) {
  return { duplicates: ['forecast'], seats: ['acceptInvitation'], admissions: ['acceptInvitation', 'activate'],
    activation: ['activate'], execution: ['executeProposal'], outboxLeases: ['claimLease'], quota: ['reserveOne'] }[kind];
}

function validatePreparedCase(prepared, race, review, preflight) {
  requireGuard(prepared?.caseId === race.caseId && prepared.scopeKey === race.scopeKey && prepared.fixturePlanSha256 === race.fixturePlanSha256
    && prepared.preparationSha256 === race.preparationSha256 && prepared.restorationSha256 === race.restorationSha256
    && prepared.newReviewedScopesOnly === true && prepared.externalSendDisabled === true && isSha(prepared.preparationEvidenceSha256),
    'EXACT_RACE_PREPARATION_REQUIRED');
  if (['duplicates', 'execution', 'activation', 'admissions'].includes(race.kind)) requireGuard(isUuid(prepared.originalCommandId)
    && isUuid(prepared.idempotencyKey) && isUuid(prepared.resourceId), 'ORIGINAL_PREPARED_IDENTITIES_REQUIRED');
  if (race.kind === 'execution') requireGuard(prepared.proposerActorId === preflight.authIds.proposer
    && prepared.approverActorId === preflight.authIds.approver && prepared.executorActorId === preflight.authIds.executor
    && prepared.approverActorId !== prepared.proposerActorId && prepared.realMfaApprovalVerified === true
    && isSha(prepared.approvalEvidenceSha256), 'REAL_DISTINCT_PROPOSAL_APPROVAL_REQUIRED');
  if (race.kind === 'quota') requireGuard(prepared.quantity === '1' && prepared.hardCap === '10'
    && prepared.metric === 'webhook.deliveries', 'ONE_UNIT_QUOTA10_FIXTURE_REQUIRED');
  if (race.kind === 'outboxLeases') requireGuard(prepared.pendingDeliveryCount === 1
    && prepared.runtimeId === review.workerConfiguration.runtimeId && prepared.runtimeScopeKey === 'runtime', 'ONE_SCOPED_PENDING_LEASE_REQUIRED');
  return prepared;
}

async function chooseRaceParticipants(kind, sessions, provider, race, signal) {
  if (kind === 'duplicates') return sessions.filter(s => s.actorLabel === 'proposer').slice(0, 100);
  if (kind === 'execution') return sessions.filter(s => s.actorLabel === 'executor' && s.aal === 'aal2'
    && s.realMfaVerified === true && isUuid(s.verifiedFactorId)).slice(0, 2);
  if (kind === 'seats') return ['approver', 'executor'].map(label => sessions.find(s => s.actorLabel === label && s.scopeKey === 'load-001'));
  const count = kind === 'quota' ? 20 : kind === 'admissions' ? 1 : 2;
  const trusted = await boundedCall(s => provider.openTrustedConnections({ kind, count, scopeKey: race.scopeKey, signal: s }), 30000, signal);
  requireGuard(trusted?.length === count && trusted.every(p => p.kind === 'trusted'), 'GENUINE_TRUSTED_CONNECTIONS_REQUIRED');
  for (const p of trusted) validateConnection(p);
  return kind === 'admissions' ? [sessions.find(s => s.actorLabel === 'approver' && s.scopeKey === 'load-001'), ...trusted] : trusted;
}

function caseRequests(race, prepared, participants) {
  const operations = raceOperations(race.kind);
  return participants.map((participant, index) => {
    const operation = operations.length === 1 ? operations[0] : operations[index];
    requireGuard(OPERATIONS[operation].transport === participant.kind, 'PARTICIPANT_TRANSPORT_MISMATCH');
    const commandId = ['forecast', 'executeProposal', 'activate'].includes(operation) ? prepared.originalCommandId :
      operation === 'reserveOne' ? freshId() : null;
    const request = { attemptId: freshId(), caseId: race.caseId, scopeKey: race.scopeKey, operation,
      commandId, idempotencyKey: commandId ? (operation === 'reserveOne' ? commandId : prepared.idempotencyKey) : null,
      resourceId: isUuid(prepared.resourceId) ? prepared.resourceId : null,
      fixturePlanSha256: race.fixturePlanSha256, phase: 'race', class: null };
    if (operation === 'reserveOne') Object.assign(request, { quantity: '1', metric: 'webhook.deliveries' });
    if (operation === 'claimLease') request.runtimeId = prepared.runtimeId;
    // Invitation tokens stay private. Correlation attemptId does not invent an idempotency input on this older endpoint.
    return request;
  });
}

export async function runRace({ race, review, preflight, sessions, provider, journal, clock = realClock, signal }) {
  const scope = review.syntheticScopes.find(s => s.key === race.scopeKey);
  requireGuard(scope, 'INVALID_REVIEWED_SCOPE');
  // Preparation can itself create invitations or change exact synthetic fixture
  // memberships. Save only these public original bindings before touching it;
  // private recovery material is retained by the separate preparation journal.
  await journal({ type: 'case-preparation-intent', projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256,
    caseId: race.caseId, kind: race.kind, scopeKey: race.scopeKey,
    scope: { tenantId: scope.tenantId, entityId: scope.entityId, branchId: scope.branchId },
    fixturePlanSha256: race.fixturePlanSha256, preparationSha256: race.preparationSha256,
    restorationSha256: race.restorationSha256, committedQuerySha256: race.committedQuerySha256,
    participants: race.participants, noExternalSend: race.noExternalSend === true, intentAt: stamp(clock) });
  const prepared = validatePreparedCase(await boundedCall(s => provider.prepareRace({ race, scope, signal: s }), 30000, signal), race, review, preflight);
  const beforeAt = clock.wall();
  const before = validateCommittedSnapshot(await boundedCall(s => provider.readCommitted({ race, scope, attempts: [], signal: s }), 30000, signal), race, scope, beforeAt);
  await journal({ type: 'race-before', kind: race.kind, snapshot: before });
  const participants = await chooseRaceParticipants(race.kind, sessions, provider, race, signal);
  requireGuard(participants.length === race.participants && participants.every(Boolean), 'RACE_PARTICIPANT_COUNT_MISMATCH');
  const requests = caseRequests(race, prepared, participants);
  const batch = await runBarrierBatch({ participants, requests, arm: provider.arm.bind(provider), call: provider.call.bind(provider), journal, clock, signal });
  // Never blindly retry an unknown mutation. Committed reads may explain it but cannot erase the uncertain transport.
  const afterAt = clock.wall();
  const after = validateCommittedSnapshot(await boundedCall(s => provider.readCommitted({ race, scope, attempts: batch.attempts.map(a =>
    ({ attemptId: a.attemptId, commandId: a.commandId, outcome: a.outcome })), signal: s }), 30000, signal), race, scope, afterAt);
  const result = { kind: race.kind, caseId: race.caseId, scopeKey: race.scopeKey, preparationEvidenceSha256: prepared.preparationEvidenceSha256,
    before, after, ...batch, passed: false, effectDelta: null, failureCode: null, restorationEvidenceSha256: null };
  try {
    requireGuard(batch.clientOverlap?.overlapped, 'REQUESTS_DID_NOT_OVERLAP');
    result.effectDelta = checkRaceEffects(race.kind, before, after, batch.attempts); result.passed = true;
  } catch (error) { result.failureCode = safeFailure(error); }
  if (batch.attempts.some(a => a.outcome === 'uncertain')) {
    result.restorationState = 'retained-for-owner-review';
  } else {
    const restored = await boundedCall(s => provider.restoreRace({ race, scope, restorationSha256: race.restorationSha256, signal: s }), 30000, signal);
    requireGuard(restored?.exactReviewedRestoration === true && restored.restorationSha256 === race.restorationSha256
      && isSha(restored.evidenceSha256) && restored.noAcceptanceChanges === true, 'EXACT_RESTORATION_PROOF_REQUIRED');
    result.restorationEvidenceSha256 = restored.evidenceSha256; result.restorationState = 'reviewed-restoration-verified';
  }
  await journal({ type: 'race-result', ...result });
  requireGuard(result.passed, result.failureCode ?? 'RACE_FAILED');
  return result;
}

// 70/20/10 in each complete ten-request block. Read dispatch includes billing-only actors.
export const workloadClassAt = ordinal => ordinal % 10 < 7 ? 'indexedReads' : ordinal % 10 < 9 ? 'ordinaryForecastCommands' : 'boundedAnalytics';

export async function runPacedWorkload({ sessions, call, journal, durationMs, warmupMs, requestsPerSecond,
  maxRequests, maxInflight, clock = realClock, signal, timeoutMs = LOAD_LIMITS.requestTimeoutMs }) {
  requireGuard(Number.isFinite(durationMs) && durationMs > warmupMs && warmupMs >= 0 && requestsPerSecond > 0
    && Number.isSafeInteger(maxRequests) && maxRequests > 0 && Number.isSafeInteger(maxInflight) && maxInflight > 0,
    'PACED_WORKLOAD_BOUNDS_REQUIRED');
  const readers = sessions, analytics = sessions.filter(s => s.actorLabel !== 'billing-admin'),
    commands = analytics.filter(s => s.actorLabel !== 'foreign-member');
  requireGuard(readers.length > 0 && analytics.length > 0 && commands.length > 0, 'PERMITTED_WORKLOAD_SESSIONS_REQUIRED');
  const pools = { indexedReads: readers, ordinaryForecastCommands: commands, boundedAnalytics: analytics };
  const next = Object.fromEntries(LOAD_CLASSES.map(k => [k, 0]));
  const inFlight = new Set(), samples = [], coverage = new Set(), tenantCoverage = new Set();
  const epoch = clock.monotonic(), startedAt = stamp(clock), measurementStart = epoch + warmupMs;
  let ordinal = 0, peakInflight = 0, lagMaxMs = 0, failureCode = null, dropped = 0;
  const localAbort = new AbortController();
  setMaxListeners(maxInflight + 1, localAbort.signal);
  const parentAbort = () => localAbort.abort(); signal?.addEventListener('abort', parentAbort, { once: true });
  if (signal?.aborted) parentAbort();
  try {
    for (; ordinal < maxRequests && !localAbort.signal.aborted; ordinal++) {
      const due = epoch + ordinal * 1000 / requestsPerSecond;
      if (due >= epoch + durationMs) break;
      await clock.sleep(Math.max(0, due - clock.monotonic()), localAbort.signal);
      const now = clock.monotonic();
      if (now >= epoch + durationMs) { dropped++; break; }
      // A busy generator cannot catch up with a burst, silently skip slots, or call a short run a pass.
      const lag = now - due; lagMaxMs = Math.max(lagMaxMs, lag);
      if (lag > Math.max(1000, 10000 / requestsPerSecond) || inFlight.size >= maxInflight) {
        failureCode = 'GENERATOR_CAPACITY_UNSUPPORTED'; localAbort.abort(); break;
      }
      const category = workloadClassAt(ordinal), pool = pools[category], participant = pool[next[category]++ % pool.length];
      const operation = category === 'ordinaryForecastCommands' ? 'forecast' : category === 'boundedAnalytics' ? 'analytics' :
        participant.actorLabel === 'billing-admin' ? 'indexedBillingRead' : 'indexedForecastRead';
      const commandId = operation === 'forecast' ? freshId() : null;
      const request = { attemptId: freshId(), ordinal, operation, class: category, scopeKey: participant.scopeKey,
        commandId, idempotencyKey: commandId, phase: 'timed' };
      let task;
      task = performAttempt({ participant, request, call, journal, clock, signal: localAbort.signal, timeoutMs,
        dispatchWindow: { epochMonoMs: epoch, measurementStartMonoMs: measurementStart, deadlineMonoMs: epoch + durationMs,
          scheduledDueMonoMs: due, maximumLagMs: Math.max(1000, 10000 / requestsPerSecond) } }).then(sample => {
        samples.push(sample);
        if (sample.transportStartedMonoMs !== null && sample.phase === 'measurement') { coverage.add(participant.sessionId); tenantCoverage.add(participant.scopeKey); }
        if (sample.outcome !== 'applied' || sample.failureCode) {
          failureCode ??= sample.failureCode ?? (sample.outcome === 'uncertain' ? 'TRANSPORT_UNCERTAIN' : 'LOAD_REQUEST_REJECTED');
          localAbort.abort();
        }
      }).catch(() => { failureCode ??= 'EVIDENCE_WRITE_FAILED'; localAbort.abort(); }).finally(() => inFlight.delete(task));
      inFlight.add(task); peakInflight = Math.max(peakInflight, inFlight.size);
    }
    if (!failureCode && !localAbort.signal.aborted) await clock.sleep(Math.max(0, epoch + durationMs - clock.monotonic()), localAbort.signal);
  } catch { failureCode ??= signal?.aborted ? 'RUN_ABORTED' : 'GENERATOR_INTERRUPTED'; }
  finally { await Promise.allSettled(inFlight); signal?.removeEventListener('abort', parentAbort); }
  const finishedAt = stamp(clock), finishedMonoMs = clock.monotonic();
  const dispatched = samples.filter(s => s.transportStartedMonoMs !== null);
  const measured = dispatched.filter(s => s.phase === 'measurement');
  const summaries = Object.fromEntries(LOAD_CLASSES.map(category => {
    const subset = measured.filter(s => s.class === category);
    return [category, { samples: subset.length, errors: subset.filter(s => s.outcome !== 'applied' || s.failureCode).length,
      p95Ms: subset.length ? nearestRankP95(subset.map(s => s.elapsedMs)) : null,
      limitMs: LOAD_LIMITS.p95Ms[category], latencyIncludesTransportAndResponseVerification: true }];
  }));
  const result = { startedAt, finishedAt, startedMonoMs: epoch, measurementStartMonoMs: measurementStart, finishedMonoMs,
    requestedDurationMs: durationMs, requestedWarmupMs: warmupMs, dispatchDurationMs: Math.min(durationMs, finishedMonoMs - epoch),
    requestsScheduled: samples.length, requestsDispatched: dispatched.length, warmupRequests: dispatched.length - measured.length, measuredRequests: measured.length,
    requestedRatePerSecond: requestsPerSecond, peakInflightRequests: peakInflight, authenticatedSessionPopulation: sessions.length,
    measuredDistinctSessionIds: coverage.size, measuredDistinctScopes: tenantCoverage.size, maximumSchedulerLagMs: lagMaxMs,
    maximumDispatchLagMs: samples.reduce((maximum, sample) => Math.max(maximum, sample.dispatchLagMs ?? 0), 0),
    droppedSlots: dropped, failureCode, summaries, requestTraceSha256: hashJson(samples), samples };
  await journal({ type: 'load-result', ...result, samples: undefined });
  return result;
}

export function checkLoadResult(result, plan) {
  const actualDispatched = result.samples.filter(s => s.transportStartedMonoMs !== null);
  const actualMeasured = actualDispatched.filter(s => s.phase === 'measurement');
  const actualWarmup = actualDispatched.filter(s => s.phase === 'warmup');
  const maximumLagMs = Math.max(1000, 10000 / plan.requestsPerSecond);
  const minimumWarmupRequests = Math.max(1, Math.floor(60 * plan.requestsPerSecond) - Math.ceil(maximumLagMs * plan.requestsPerSecond / 1000) - 1);
  requireGuard(!result.failureCode && result.droppedSlots === 0 && result.dispatchDurationMs >= 360000
    && result.requestedWarmupMs === 60000 && result.requestedDurationMs === 360000
    && result.measuredDistinctSessionIds === 2000 && result.measuredDistinctScopes === 500
    && result.requestsDispatched <= plan.maximumTimedRequests && result.peakInflightRequests <= 2000
    && result.requestedRatePerSecond === plan.requestsPerSecond && result.maximumDispatchLagMs <= maximumLagMs
    && result.requestsScheduled === result.samples.length && result.requestsDispatched === actualDispatched.length
    && result.measuredRequests === actualMeasured.length && result.warmupRequests === actualWarmup.length
    && result.warmupRequests >= minimumWarmupRequests && result.requestsDispatched === Math.ceil(360 * plan.requestsPerSecond),
    'TARGET_SCALE_DURATION_OR_COVERAGE_INCOMPLETE');
  requireGuard(result.samples.every(s => s.outcome === 'applied' && !s.failureCode), 'LOAD_ERRORS_PRESENT');
  for (const category of LOAD_CLASSES) {
    const summary = result.summaries[category];
    requireGuard(summary.samples >= 100 && summary.errors === 0 && summary.p95Ms < LOAD_LIMITS.p95Ms[category], 'LOAD_P95_FAILED');
  }
  const measured = result.measuredRequests;
  for (const [category, percentage] of Object.entries({ indexedReads: .7, ordinaryForecastCommands: .2, boundedAnalytics: .1 })) {
    requireGuard(Math.abs(result.summaries[category].samples - measured * percentage) <= 10, 'MEASURED_MIX_DRIFT');
  }
  const commands = result.samples.filter(s => s.operation === 'forecast');
  requireGuard(new Set(commands.map(s => s.commandId)).size === commands.length
    && commands.every(s => s.commandId === s.originalCommandId), 'FRESH_FORECAST_COMMANDS_REQUIRED');
  return true;
}

function loadSnapshot(raw, plan, review, earliestMs) {
  requireGuard(raw?.kind === 'committed-load-population-snapshot' && raw.projectId === PROJECT_ID && raw.committed === true
    && raw.readOnly === true && raw.isolation === 'repeatable-read' && raw.querySha256 === plan.loadCommittedQuerySha256
    && raw.fixturePlanSha256 === plan.loadFixturePlanSha256 && raw.scopeDigestSha256 === hashJson(review.syntheticScopes)
    && Date.parse(raw.observedAt) >= earliestMs && isSha(raw.snapshotSha256) && isSha(raw.transactionEvidenceSha256)
    && ['forecasts', 'receipts', 'audit', 'outbox', 'modelInvocationRows', 'deliveryAttemptRows', 'deliveryOutcomeRows',
      'receiverReceiptRows', 'workerTickRows'].every(k =>
      Number.isSafeInteger(raw.counters?.[k]) && raw.counters[k] >= 0), 'COMMITTED_LOAD_POPULATION_REQUIRED');
  return { observedAt: raw.observedAt, querySha256: raw.querySha256, snapshotSha256: raw.snapshotSha256,
    transactionEvidenceSha256: raw.transactionEvidenceSha256, counters: Object.fromEntries(
      ['forecasts', 'receipts', 'audit', 'outbox', 'modelInvocationRows', 'deliveryAttemptRows', 'deliveryOutcomeRows',
        'receiverReceiptRows', 'workerTickRows'].map(k => [k, raw.counters[k]])) };
}

export function validateExternalTransportObservation(raw, review, plan, window) {
  requireGuard(raw?.kind === 'online-no-external-transport-observation' && raw.projectId === PROJECT_ID
    && raw.runtimeBundleSha256 === review.bundleSha256 && raw.scopeDigestSha256 === hashJson(review.syntheticScopes)
    && raw.observerSourceSha256 === plan.externalObservationSourceSha256 && isSha(raw.transportTraceSha256)
    && isSha(raw.jobsStateEvidenceSha256) && Date.parse(raw.observedFromAt) <= Date.parse(window.startedAt)
    && Date.parse(raw.observedUntilAt) >= Date.parse(window.finishedAt) && raw.allReviewedModelDeliveryWorkersCovered === true
    && raw.reviewedJobsInactiveAndNoInflight === true && raw.modelDispatchesObserved === 0 && raw.webhookDispatchesObserved === 0,
    'ACTUAL_EXTERNAL_TRANSPORT_OBSERVATION_REQUIRED');
  return { kind: raw.kind, observedFromAt: raw.observedFromAt, observedUntilAt: raw.observedUntilAt,
    observerSourceSha256: raw.observerSourceSha256, transportTraceSha256: raw.transportTraceSha256,
    jobsStateEvidenceSha256: raw.jobsStateEvidenceSha256, allReviewedModelDeliveryWorkersCovered: true,
    reviewedJobsInactiveAndNoInflight: true, modelDispatchesObserved: 0, webhookDispatchesObserved: 0 };
}

export function boundaryResult(raw, boundary) {
  const entry = { kind: boundary.kind, caseId: boundary.caseId, passed: false, executed: false, blocked: false };
  if (raw?.status === 'unsupported-under-reviewed-scope') {
    requireGuard(raw.caseId === boundary.caseId && raw.fixturePlanSha256 === boundary.fixturePlanSha256
      && raw.noOperationAttempted === true && raw.existingScopeOnly === true && isSha(raw.fixtureEvidenceSha256)
      && ['ROW_FIXTURE_EXCEEDS_REVIEWED_CAPS', 'GROUP_FIXTURE_NOT_REVIEWED', 'OUTPUT_FIXTURE_NOT_REVIEWED'].includes(raw.reasonCode),
      'UNSUPPORTED_BOUNDARY_PROOF_REQUIRED');
    return { ...entry, blocked: true, code: raw.reasonCode, fixtureEvidenceSha256: raw.fixtureEvidenceSha256 };
  }
  requireGuard(raw?.caseId === boundary.caseId && raw.fixturePlanSha256 === boundary.fixturePlanSha256
    && raw.querySha256 === boundary.committedQuerySha256 && raw.actualLimitRejection === true
    && raw.code === 'LIMIT_EXCEEDED' && isSha(raw.responseSha256) && isSha(raw.committedEvidenceSha256)
    && COUNTERS.every(k => raw.committedEffectDelta?.[k] === 0), 'INVALID_BOUNDARY_ZERO_EFFECT_REQUIRED');
  return { ...entry, executed: true, code: raw.code, responseSha256: raw.responseSha256,
    committedEvidenceSha256: raw.committedEvidenceSha256, passed: true };
}

export async function runLiveVerification(input) {
  // The only live entry point always uses actual clocks and the full, unshortened contract.
  const { review, plan, approval, preparation, binding } = reviewedExecutionContext(input);
  const { provider, journal } = input;
  requireGuard(['verifyPreflight', 'openSessions', 'reverifySessions', 'openTrustedConnections', 'prepareRace', 'arm', 'call', 'readCommitted',
    'readLoadCommitted', 'readExternalTransportObservation', 'restoreRace', 'runInvalidBoundary', 'close'].every(method => typeof provider?.[method] === 'function'), 'PRIVATE_PROVIDER_INCOMPLETE');
  const begun = performance.now(), controller = new AbortController();
  setMaxListeners(LOAD_LIMITS.maxInflight + 1, controller.signal);
  const timer = setTimeout(() => controller.abort(), LOAD_LIMITS.maxRunMs);
  const report = { kind: 'wave5-runtime-harness-live-result', projectId: PROJECT_ID, executed: true, passed: false,
    runtimeBundleSha256: review.bundleSha256, harnessReviewSha256: binding.harnessReviewSha256, planSha256: binding.planSha256,
    startedAt: new Date().toISOString(), races: [], invalidBoundaries: [], load: null,
    gates: { independentSessionContention: false, targetScaleLoad: false, invalidBoundaryRejections: false, ownerAcceptance: false,
      authenticatedNative: false, actualDelivery: false, actualModel: false }, failureCode: null };
  try {
    await journal({ type: 'live-start', ...report });
    const proof = await boundedCall(signal => provider.verifyPreflight({ review, plan, approval, binding, signal }), 30000, controller.signal);
    validatePreflight(proof, review, plan, binding);
    report.preflight = { observedAt: proof.observedAt, ledgerSha256: proof.ledgerSha256, contractFingerprintSha256: proof.contractFingerprintSha256,
      capacityEvidenceSha256: proof.capacityEvidenceSha256, rowDistributionSha256: proof.rowDistributionSha256,
      authCreationEvidenceSha256: proof.authCreationEvidenceSha256, fixturePopulationSha256: proof.fixturePopulationSha256,
      environment: Object.fromEntries(['region', 'databaseTier', 'postgresVersion', 'generatorHost', 'cacheConditions', 'hardwareSha256',
        'maximumConcurrentSessions', 'maximumRequestsPerSecond'].map(k => [k, proof.environment[k]])) };
    let sessions = await boundedCall(signal => provider.openSessions({ review, signal }), 120000, controller.signal);
    validateSessions(sessions, review, proof);
    report.sessionPopulationSha256 = hashJson(sessions.map(s => ({ ...publicParticipant(s), scopeKey: s.scopeKey, ordinal: s.ordinal })));
    await journal({ type: 'session-population', sessions: sessions.map(s => ({ ...publicParticipant(s), scopeKey: s.scopeKey, ordinal: s.ordinal })) });
    for (const kind of RACE_KINDS) report.races.push(await runRace({ race: plan.cases.find(c => c.kind === kind), review, preflight: proof,
      sessions, provider, journal, signal: controller.signal }));
    report.gates.independentSessionContention = true;
    for (const boundary of plan.boundaries) {
      const raw = await boundedCall(signal => provider.runInvalidBoundary({ boundary, review, signal }), 30000, controller.signal);
      const entry = boundaryResult(raw, boundary);
      report.invalidBoundaries.push(entry); await journal({ type: 'invalid-boundary-result', ...entry });
    }
    report.gates.invalidBoundaryRejections = report.invalidBoundaries.length === 4 && report.invalidBoundaries.every(b => b.passed);
    // Recheck capacity/contracts/session rows immediately before the timed workload after setup/races.
    const loadProof = await boundedCall(signal => provider.verifyPreflight({ review, plan, approval, binding, signal }), 30000, controller.signal);
    validatePreflight(loadProof, review, plan, binding);
    requireGuard(loadProof.ledgerSha256 === proof.ledgerSha256 && loadProof.contractFingerprintSha256 === proof.contractFingerprintSha256,
      'INSTALLED_CONTRACT_DRIFT_DURING_RUN');
    const oldIdentities = hashJson(sessions.map(s => ({ sessionId: s.sessionId, actorId: s.actorId, connectionId: s.connectionId,
      scopeKey: s.scopeKey, actorLabel: s.actorLabel, ordinal: s.ordinal })));
    sessions = await boundedCall(signal => provider.reverifySessions({ sessions, signal }), 120000, controller.signal);
    requireGuard(hashJson(sessions.map(s => ({ sessionId: s.sessionId, actorId: s.actorId, connectionId: s.connectionId,
      scopeKey: s.scopeKey, actorLabel: s.actorLabel, ordinal: s.ordinal }))) === oldIdentities, 'SESSION_IDENTITY_CHANGED_DURING_RUN');
    validateSessions(sessions, review, loadProof);
    const beforeAt = Date.now();
    const beforeLoad = loadSnapshot(await boundedCall(signal => provider.readLoadCommitted({ review, plan, signal }), 30000, controller.signal), plan, review, beforeAt);
    await journal({ type: 'load-committed-before', ...beforeLoad });
    report.load = await runPacedWorkload({ sessions, call: provider.call.bind(provider), journal, durationMs: 360000, warmupMs: 60000,
      requestsPerSecond: plan.requestsPerSecond, maxRequests: plan.maximumTimedRequests, maxInflight: 2000, signal: controller.signal });
    const afterAt = Date.now();
    const afterLoad = loadSnapshot(await boundedCall(signal => provider.readLoadCommitted({ review, plan, signal }), 30000, controller.signal), plan, review, afterAt);
    report.load.committedBefore = beforeLoad; report.load.committedAfter = afterLoad;
    await journal({ type: 'load-committed-after', ...afterLoad });
    report.load.externalTransportObservation = validateExternalTransportObservation(await boundedCall(signal =>
      provider.readExternalTransportObservation({ review, plan, window: { startedAt: beforeLoad.observedAt, finishedAt: afterLoad.observedAt }, signal }),
      30000, controller.signal), review, plan, { startedAt: beforeLoad.observedAt, finishedAt: afterLoad.observedAt });
    await journal({ type: 'load-external-transport-observation', ...report.load.externalTransportObservation });
    checkLoadResult(report.load, plan);
    const commandCount = report.load.samples.filter(s => s.operation === 'forecast').length;
    requireGuard(['forecasts', 'receipts', 'audit', 'outbox'].every(k => afterLoad.counters[k] - beforeLoad.counters[k] === commandCount)
      && ['modelInvocationRows', 'deliveryAttemptRows', 'deliveryOutcomeRows', 'receiverReceiptRows', 'workerTickRows'].every(k =>
        afterLoad.counters[k] === beforeLoad.counters[k]), 'LOAD_COMMITTED_EFFECT_MISMATCH');
    report.gates.targetScaleLoad = true; report.passed = report.gates.invalidBoundaryRejections;
    if (!report.passed) report.failureCode = 'REQUIRED_BOUNDARY_FIXTURES_UNAVAILABLE';
  } catch (error) { report.failureCode = safeFailure(error); }
  finally {
    controller.abort(); clearTimeout(timer);
    try { await boundedCall(signal => provider.close({ preserveUnknownEffects: true, noCleanupOfAccountsOrStores: true, signal }), 10000); }
    catch { report.failureCode ??= 'PRIVATE_PROVIDER_CLOSE_FAILED'; report.passed = false; }
    report.finishedAt = new Date().toISOString(); report.totalElapsedMs = performance.now() - begun;
    if (report.totalElapsedMs > LOAD_LIMITS.maxRunMs) { report.failureCode ??= 'RUN_DURATION_LIMIT_EXCEEDED'; report.passed = false; report.gates.targetScaleLoad = false; }
    await journal({ type: 'live-finish', ...report, load: report.load ? { ...report.load, samples: undefined } : null });
  }
  return report;
}
