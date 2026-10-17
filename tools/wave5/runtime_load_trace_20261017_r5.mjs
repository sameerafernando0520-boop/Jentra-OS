import { BUSINESS_ACTORS, LOAD_CLASSES, LOAD_LIMITS, hashJson, isUuid, nearestRankP95, requireGuard } from './runtime_contract.mjs';

// Recompute acceptance fields from the dispatch trace. Report summaries are not
// independent evidence of coverage, timing or which operation actually ran.
export function validateLoadTrace(result, plan) {
  const incomplete = 'TARGET_SCALE_DURATION_OR_COVERAGE_INCOMPLETE';
  requireGuard(Array.isArray(result.samples) && result.requestTraceSha256 === hashJson(result.samples), incomplete);
  const epoch = result.startedMonoMs, measurementStart = result.measurementStartMonoMs;
  requireGuard(Number.isFinite(epoch) && measurementStart === epoch + 60000
    && Number.isFinite(result.finishedMonoMs) && result.finishedMonoMs >= epoch + 360000
    && Number.isFinite(plan.requestsPerSecond) && plan.requestsPerSecond >= 20, incomplete);
  const attempts = new Set(), slots = new Set(), identities = new Map(), connections = new Map(), intervals = [];
  let actualMaximumLag = 0;
  const measured = [], sessions = new Set(), scopes = new Set();
  const maximumLag = Math.max(1000, 10000 / plan.requestsPerSecond);
  for (const s of result.samples) {
    requireGuard(isUuid(s.attemptId) && !attempts.has(s.attemptId), incomplete); attempts.add(s.attemptId);
    const times = [s.startedMonoMs, s.transportStartedMonoMs, s.transportFinishedMonoMs, s.finishedMonoMs];
    requireGuard(times.every(Number.isFinite) && times.every((t, i) => i === 0 || t >= times[i - 1])
      && s.finishedMonoMs <= result.finishedMonoMs
      && Number.isFinite(s.elapsedMs) && s.elapsedMs === s.finishedMonoMs - s.startedMonoMs,
    'REAL_TIMINGS_REQUIRED');
    requireGuard(Number.isFinite(s.scheduledDueMonoMs), incomplete);
    const ordinal = Math.round((s.scheduledDueMonoMs - epoch) * plan.requestsPerSecond / 1000);
    const due = epoch + ordinal * 1000 / plan.requestsPerSecond;
    const tolerance = Math.max(0.000001, Math.abs(due) * Number.EPSILON * 8);
    requireGuard(Number.isSafeInteger(ordinal) && ordinal >= 0 && ordinal < Math.ceil(360 * plan.requestsPerSecond)
      && Math.abs(due - s.scheduledDueMonoMs) <= tolerance && !slots.has(ordinal), incomplete); slots.add(ordinal);
    const lag = s.transportStartedMonoMs - s.scheduledDueMonoMs;
    const phase = s.transportStartedMonoMs < measurementStart ? 'warmup' : 'measurement';
    requireGuard(s.transportStartedMonoMs >= epoch && s.transportStartedMonoMs < epoch + 360000
      && lag >= 0 && lag <= maximumLag && s.dispatchLagMs === lag && s.phase === phase, incomplete);
    actualMaximumLag = Math.max(actualMaximumLag, lag);
    if (s.transportFinishedMonoMs > s.transportStartedMonoMs) intervals.push([s.transportStartedMonoMs, 1], [s.transportFinishedMonoMs, -1]);
    const category = ordinal % 10 < 7 ? 'indexedReads' : ordinal % 10 < 9 ? 'ordinaryForecastCommands' : 'boundedAnalytics';
    const p = s.participant;
    requireGuard(p?.kind === 'auth' && isUuid(p.sessionId) && isUuid(p.actorId) && typeof p.connectionId === 'string'
      && p.connectionId.length > 0 && [...BUSINESS_ACTORS, 'foreign-member'].includes(p.actorLabel)
      && typeof s.scopeKey === 'string' && s.scopeKey.length > 0, incomplete);
    const identity = hashJson([p.actorId, p.actorLabel, p.connectionId, s.scopeKey]);
    requireGuard(!identities.has(p.sessionId) || identities.get(p.sessionId) === identity, incomplete);
    identities.set(p.sessionId, identity);
    requireGuard(!connections.has(p.connectionId) || connections.get(p.connectionId) === p.sessionId, incomplete);
    connections.set(p.connectionId, p.sessionId);
    const operation = category === 'ordinaryForecastCommands' ? 'forecast' : category === 'boundedAnalytics' ? 'analytics'
      : p.actorLabel === 'billing-admin' ? 'indexedBillingRead' : 'indexedForecastRead';
    requireGuard(s.class === category && s.operation === operation
      && (category === 'indexedReads' || p.actorLabel !== 'billing-admin')
      && (category !== 'ordinaryForecastCommands' || p.actorLabel !== 'foreign-member'), incomplete);
    if (phase === 'measurement') { measured.push(s); sessions.add(p.sessionId); scopes.add(s.scopeKey); }
  }
  requireGuard(sessions.size === 2000 && scopes.size === 500 && identities.size === 2000
    && sessions.size === result.measuredDistinctSessionIds && scopes.size === result.measuredDistinctScopes
    && result.authenticatedSessionPopulation === 2000 && result.measuredRequests === measured.length, incomplete);
  let active = 0, peak = 0;
  for (const [, movement] of intervals.sort((a, b) => a[0] - b[0] || a[1] - b[1])) { active += movement; peak = Math.max(peak, active); }
  // The coordinator's in-flight count includes pending journal/verification work,
  // so real transport concurrency may be lower, but cannot exceed its reported peak.
  requireGuard(peak <= result.peakInflightRequests && result.peakInflightRequests <= 2000
    && actualMaximumLag === result.maximumDispatchLagMs, incomplete);
  for (const category of LOAD_CLASSES) {
    const samples = measured.filter(s => s.class === category), summary = result.summaries[category];
    const errors = samples.filter(s => s.outcome !== 'applied' || s.failureCode).length;
    const p95 = nearestRankP95(samples.map(s => s.elapsedMs));
    requireGuard(summary.samples === samples.length && summary.errors === errors && summary.p95Ms === p95
      && errors === 0 && p95 < LOAD_LIMITS.p95Ms[category], 'LOAD_P95_FAILED');
  }
  return { measuredSessions: sessions.size, measuredScopes: scopes.size, scheduledSlots: slots.size };
}
