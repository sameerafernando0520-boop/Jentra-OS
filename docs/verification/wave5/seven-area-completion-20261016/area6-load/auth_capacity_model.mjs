// Offline token-bucket arithmetic, using saved settings. This never contacts
// Auth, creates tokens, changes policy, or certifies deployed rate semantics.
export function modelAuthCapacity({ sessions = 2000, sourceGroups = 1, quota = 150, quotaWindowSeconds = 300,
  burst = 30, jwtLifetimeSeconds = 3600, minimumRemainingSeconds = 900, verificationTailSeconds = 0 } = {}) {
  const fields = { sessions, sourceGroups, quota, quotaWindowSeconds, burst, jwtLifetimeSeconds, minimumRemainingSeconds, verificationTailSeconds };
  if (!Object.values(fields).every(v => Number.isSafeInteger(v) && v >= 0)
    || [sessions, sourceGroups, quota, quotaWindowSeconds, jwtLifetimeSeconds, minimumRemainingSeconds].some(v => v === 0)
    || jwtLifetimeSeconds <= minimumRemainingSeconds + verificationTailSeconds) throw Error('INVALID_CAPACITY_MODEL');
  const total = BigInt(sessions), groups = BigInt(sourceGroups), period = BigInt(quotaWindowSeconds), rate = BigInt(quota), initial = BigInt(burst);
  const available = BigInt(jwtLifetimeSeconds - minimumRemainingSeconds - verificationTailSeconds);
  const perGroup = (total + groups - 1n) / groups;
  const missing = perGroup > initial ? perGroup - initial : 0n;
  const lowerBound = (missing * period + rate - 1n) / rate;
  const capacity = initial + available * rate / period;
  const minimumGroups = (total + capacity - 1n) / capacity;
  return { assumptions: fields, actualVerified: false, networkCalls: 0, genuineSessionsCreated: 0,
    interpretation: 'Necessary optimistic token-bucket bound only; shared project limits, deployed route limits, online verification throughput and genuine independent sources remain unverified.',
    maximumIssuanceSeconds: available.toString(), minimumCohortIssuanceSeconds: lowerBound.toString(),
    maximumTokensPerSourceInWindow: capacity.toString(), minimumGenuineSourceGroups: minimumGroups.toString(),
    arithmeticAllowsCohort: lowerBound <= available };
}
