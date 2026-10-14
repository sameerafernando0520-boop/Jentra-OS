import crypto from 'node:crypto';

export const PROJECT_ID = 'xpdoufauvrbdmxgngetv';
export const PROJECT_URL = `https://${PROJECT_ID}.supabase.co`;
export const BUSINESS_ACTORS = Object.freeze(['proposer', 'approver', 'executor', 'billing-admin']);
export const RACE_KINDS = Object.freeze(['duplicates', 'seats', 'admissions', 'activation', 'execution', 'outboxLeases', 'quota']);
export const LOAD_CLASSES = Object.freeze(['indexedReads', 'ordinaryForecastCommands', 'boundedAnalytics']);
export const LOAD_LIMITS = Object.freeze({ tenants: 500, sessions: 2000, warmupMs: 60000, measuredMs: 300000,
  maxRunMs: 900000, maxRequests: 100000, maxInflight: 2000, requestTimeoutMs: 30000,
  p95Ms: Object.freeze({ indexedReads: 500, ordinaryForecastCommands: 1500, boundedAnalytics: 3000 }) });
export const COUNTERS = Object.freeze(['business', 'membership', 'receipt', 'usage', 'audit', 'outbox', 'lease', 'activation']);
export const BOUNDARY_KINDS = Object.freeze(['10001Rows', '101Groups', '367DayWindow', '8MiBPlus1Byte']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA = /^[a-f0-9]{64}$/;

// These are source-verified contracts, not an arbitrary RPC dispatcher.
export const OPERATIONS = Object.freeze({
  indexedForecastRead: Object.freeze({ rpc: 'get_pipeline_forecast', transport: 'auth', source: 'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql' }),
  indexedBillingRead: Object.freeze({ rpc: 'get_wave5_subscription', transport: 'auth', source: 'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql' }),
  forecast: Object.freeze({ rpc: 'freeze_pipeline_forecast', transport: 'auth', source: 'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql' }),
  analytics: Object.freeze({ rpc: 'analytics_process_snapshot', transport: 'auth', source: 'supabase/migrations/20261006140000_wave5_process_metrics.sql' }),
  acceptInvitation: Object.freeze({ rpc: 'accept_invitation', transport: 'auth', source: 'supabase/migrations/20260831193714_create_greenfield_foundation.sql' }),
  reserveOne: Object.freeze({ rpc: 'wave5_reserve_usage', transport: 'trusted', source: 'supabase/migrations/20261006150000_wave5_trusted_metering.sql' }),
  activate: Object.freeze({ rpc: 'apply_synthetic_subscription', transport: 'trusted', source: 'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql' }),
  executeProposal: Object.freeze({ rpc: 'wave5_proposal_command', action: 'execute', transport: 'auth', source: 'supabase/migrations/20261006160000_wave5_human_proposals.sql' }),
  claimLease: Object.freeze({ rpc: 'wave5_runtime_delivery_worker', action: 'claim', transport: 'trusted', source: 'supabase/migrations/20261008123000_wave5_runtime_scope.sql' }),
});

export class GuardError extends Error {
  constructor(code) { super(code); this.name = 'GuardError'; this.code = code; }
}
export const requireGuard = (value, code) => { if (!value) throw new GuardError(code); };
export const isUuid = value => typeof value === 'string' && UUID.test(value);
export const isSha = value => typeof value === 'string' && SHA.test(value);
export const hashBytes = value => crypto.createHash('sha256').update(value).digest('hex');
export const hashJson = value => hashBytes(JSON.stringify(value));
export const freshId = () => crypto.randomUUID();
export const zeroCounters = () => Object.fromEntries(COUNTERS.map(key => [key, 0]));
const sameJson = (a, b) => hashJson(a) === hashJson(b);
const millis = value => typeof value === 'string' ? Date.parse(value) : NaN;
// A provider can throw GuardError too. Never copy arbitrary exception text, even if it looks like a code.
const PUBLIC_CODES = new Set(`
ACTIVATION_EFFECT_MISMATCH ACTUAL_CAPACITY_EVIDENCE_REQUIRED ACTUAL_OWNER_DECISION_TIME_REQUIRED
ACTUAL_TRANSPORT_EVIDENCE_REQUIRED ACTUAL_TRANSPORT_INTERVAL_REQUIRED ADMISSION_ACTIVATION_EFFECT_MISMATCH
ALL_INVALID_BOUNDARIES_REQUIRED ALL_REVIEWED_RACES_REQUIRED APPROVAL_BINDING_MISMATCH APPROVAL_SCOPE_MISMATCH
BOUNDARY_BINDING_REQUIRED COMMITTED_COUNTERS_REQUIRED COMMITTED_EFFECT_REGRESSION COMMITTED_LOAD_POPULATION_REQUIRED
COMMITTED_SCOPED_READ_REQUIRED COMMITTED_STATE_REQUIRED CURRENT_COORDINATOR_BINDINGS_REQUIRED CURRENT_RUNTIME_BUNDLE_CHANGED
CURRENT_RUNTIME_FILE_CHANGED DENIED_ATTEMPT_EFFECT_REQUIRED DENIED_ZERO_EFFECT_PROOF_MISSING DUPLICATE_ARGUMENT
DUPLICATE_EFFECT_MISMATCH DUPLICATE_ENTITY_MISMATCH DUPLICATE_HARNESS_BINDING DUPLICATE_TRANSPORT_START
EVIDENCE_DIRECTORY_SYMLINK_BOUNDARY EVIDENCE_WRITE_FAILED EXACT_DEVELOPMENT_TARGET_REQUIRED EXACT_EXECUTION_HASHES_REQUIRED
EXACT_RACE_PREPARATION_REQUIRED EXACT_REAL_AUTH_IDS_REQUIRED EXACT_RESTORATION_PROOF_REQUIRED EXACT_SCOPE_DISTRIBUTION_REQUIRED
EXACT_SESSION_DISTRIBUTION_REQUIRED EXECUTION_EFFECT_MISMATCH EXPLICIT_OWNER_APPROVAL_REQUIRED FRESH_FORECAST_COMMANDS_REQUIRED
FRESH_PREFLIGHT_REQUIRED FRESH_UNREVOKED_SESSION_REQUIRED GENERATOR_CAPACITY_UNSUPPORTED GENERATOR_INTERRUPTED
GENUINE_RUNTIME_MFA_REQUIRED GENUINE_EXECUTOR_SESSION_PAIR_REQUIRED GENUINE_TRUSTED_CONNECTIONS_REQUIRED HARNESS_FILE_OUTSIDE_WORKSPACE HARNESS_SOURCE_BINDINGS_REQUIRED
HARNESS_SOURCE_DRIFT HASH_BOUND_HARNESS_REVIEW_REQUIRED INDEPENDENT_AUTH_SESSIONS_REQUIRED
INDEPENDENT_BARRIER_PARTICIPANTS_REQUIRED INDEPENDENT_PREPARATION_REVIEW_DRIFT INDEPENDENT_PREPARATION_REVIEW_REQUIRED
INDEPENDENT_PREPARATION_VERDICT_REQUIRED INDEPENDENT_SESSION_REQUIRED INSTALLATION_CONTRACT_DRIFT
INSTALLED_CONTRACT_DRIFT_DURING_RUN INSTALLED_CONTRACT_OR_PRESERVATION_MISSING INVALID_ARGUMENT
INVALID_BOUNDARY_ZERO_EFFECT_REQUIRED INVALID_DISPATCH_WINDOW INVALID_HARNESS_FILE_BINDING INVALID_PROVIDER_OUTCOME
REQUIRED_BOUNDARY_FIXTURES_UNAVAILABLE UNSUPPORTED_BOUNDARY_PROOF_REQUIRED
INVALID_REVIEWED_SCOPE INVALID_SCOPE_KEY INVALID_TRANSPORT_END LEASE_EFFECT_MISMATCH LIMIT_EXCEEDED
LOAD_COMMITTED_BINDING_REQUIRED LOAD_COMMITTED_EFFECT_MISMATCH LOAD_ERRORS_PRESENT LOAD_EXTERNAL_EFFECTS_EXCLUDED
ACTUAL_EXTERNAL_TRANSPORT_OBSERVATION_REQUIRED
LOAD_LIMITS_REQUIRED LOAD_P95_FAILED LOAD_REQUEST_REJECTED MEASURED_MIX_DRIFT NEW_EVIDENCE_FILENAME_REQUIRED
NEW_LOCAL_ATTEMPT_REQUIRED NONEMPTY_REVIEWED_FIXTURES_REQUIRED ONE_SCOPED_PENDING_LEASE_REQUIRED
ONE_UNIT_QUOTA10_FIXTURE_REQUIRED ONLINE_BARRIER_READINESS_REQUIRED ONLINE_PREFLIGHT_BINDING_REQUIRED
ONLINE_SESSION_ROW_PROOF_REQUIRED ORIGINAL_COMMAND_ID_REQUIRED ORIGINAL_PREPARED_IDENTITIES_REQUIRED
PACED_WORKLOAD_BOUNDS_REQUIRED PARTICIPANT_TRANSPORT_MISMATCH PERMITTED_WORKLOAD_SESSIONS_REQUIRED
PLAN_BODY_BINDING_MISMATCH PREFLIGHT_EVIDENCE_HASH_REQUIRED PREPARATION_BINDING_MISMATCH PRIVATE_PROVIDER_CLOSE_FAILED
PRIVATE_PROVIDER_FACTORY_REQUIRED PRIVATE_PROVIDER_INCOMPLETE PRIVATE_PROVIDER_MUST_BE_OUTSIDE_REPOSITORY
PRIVATE_PROVIDER_SOURCE_DRIFT PROVIDER_FAILURE PUBLIC_AUTH_IDENTITY_REQUIRED PUBLIC_REVIEW_MUST_BE_IN_WORKSPACE
PUBLIC_REVIEW_SYMLINK_BOUNDARY QUOTA_EFFECT_MISMATCH QUOTA_EXCEEDED RACE_FAILED RACE_PARTICIPANT_BOUNDARY
RACE_PARTICIPANT_COUNT_MISMATCH REAL_AAL_REQUIRED REAL_AUTH_CONTRACT_REQUIRED REAL_DISTINCT_PROPOSAL_APPROVAL_REQUIRED
REAL_TIMINGS_REQUIRED REQUEST_RATE_OUTSIDE_BOUND REQUESTS_DID_NOT_OVERLAP RESPONSE_HASH_REQUIRED RETURNED_COMMAND_ID_MISMATCH
REVIEW_ARGUMENTS_REQUIRED REVIEWED_CASE_BINDING_REQUIRED REVIEWED_PREPARATION_REQUIRED REVIEWED_PRIVATE_PROVIDER_REQUIRED
REVIEWED_SCOPES_REQUIRED RUN_ABORTED RUN_DURATION_LIMIT_EXCEEDED RUNTIME_BUNDLE_HASH_MISMATCH RUNTIME_CONTENTION_DRIFT
RUNTIME_LOAD_CONTRACT_DRIFT RUNTIME_WORKLOAD_DRIFT SEAT_CAP_EXCEEDED SEAT_EFFECT_MISMATCH SEAT_QUOTA_EXCEEDED
SERVER_SPAN_PROOF_REQUIRED SESSION_ACTOR_MISMATCH SESSION_IDENTITY_CHANGED_DURING_RUN
TARGET_SCALE_DURATION_OR_COVERAGE_INCOMPLETE TRANSPORT_TIMEOUT TRANSPORT_UNCERTAIN TRUSTED_INDEPENDENT_CONNECTION_REQUIRED
TWO_THOUSAND_REAL_SESSIONS_REQUIRED UNCERTAIN_MUTATION_REQUIRES_REVIEW UNKNOWN_CONNECTION_KIND UNKNOWN_RACE
VERIFIED_CONNECTION_REQUIRED WORKLOAD_DEADLINE_EXCEEDED WORKLOAD_NOT_STARTED EARLY_WORKLOAD_DISPATCH WRONG_RUNTIME_REVIEW
PERMISSION_DENIED
`.trim().split(/\s+/));
export const safeCode = value => PUBLIC_CODES.has(value) ? value : 'PROVIDER_FAILURE';
export const safeFailure = error => error instanceof GuardError ? safeCode(error.code) : 'PROVIDER_FAILURE';

export function immutableJson(value) {
  const copy = JSON.parse(JSON.stringify(value));
  const freeze = object => { if (object && typeof object === 'object') { Object.values(object).forEach(freeze); Object.freeze(object); } return object; };
  return freeze(copy);
}

export function validateRuntimeReview(review) {
  const { bundleSha256, ...body } = review ?? {};
  requireGuard(isSha(bundleSha256) && hashJson(body) === bundleSha256, 'RUNTIME_BUNDLE_HASH_MISMATCH');
  requireGuard(review.projectId === PROJECT_ID && review.ownerApproved === false, 'WRONG_RUNTIME_REVIEW');
  const load = review.execution?.load;
  requireGuard(load?.tenants === 500 && load.concurrentSessions === 2000 && load.uniqueAuthSessionIdsRequired === true
    && load.noConstructedJwtClaims === true && load.noGlobalAuthRateLimitOrSingleSessionChanges === true
    && load.warmupSeconds === 60 && load.measuredSeconds === 300 && load.maxRunSeconds === 900
    && load.connectionLimit === 2000 && load.maximumTimedRequests === 100000
    && load.apiModelAndWebhookDeliveryExcludedFromLoad === true, 'RUNTIME_LOAD_CONTRACT_DRIFT');
  requireGuard(sameJson(load.workloadPercent, { indexedReads: 70, ordinaryForecastCommands: 20, boundedAnalytics: 10 })
    && sameJson(load.p95LimitsMs, { indexedReads: 500, ordinaryCommands: 1500, boundedAnalytics: 3000 }), 'RUNTIME_WORKLOAD_DRIFT');
  requireGuard(review.execution.contention?.duplicates === 100 && review.execution.contention.quotaLimit === '10'
    && review.execution.contention.independentSessions === true, 'RUNTIME_CONTENTION_DRIFT');
  requireGuard(review.syntheticScopes?.length === 500 && new Set(review.syntheticScopes.map(s => s.key)).size === 500
    && new Set(review.syntheticScopes.map(s => s.tenantId)).size === 500, 'REVIEWED_SCOPES_REQUIRED');
  for (const scope of review.syntheticScopes) {
    requireGuard(isUuid(scope.tenantId) && isUuid(scope.entityId) && isUuid(scope.branchId), 'INVALID_REVIEWED_SCOPE');
    requireGuard(scope.key === 'runtime' || scope.key === 'foreign' || /^load-\d{3}$/.test(scope.key), 'INVALID_SCOPE_KEY');
  }
  requireGuard(review.syntheticScopes.filter(s => s.key.startsWith('load-')).length === 498
    && review.syntheticScopes.some(s => s.key === 'runtime') && review.syntheticScopes.some(s => s.key === 'foreign')
    && review.syntheticScopes.some(s => s.key === 'load-001'), 'EXACT_SCOPE_DISTRIBUTION_REQUIRED');
  requireGuard(review.migrations?.length === 71 && review.liveBaseline.installedSixNeverReplayed === true
    && review.liveBaseline.expectedLedgerAfterOnlyThisInstall === 114, 'INSTALLATION_CONTRACT_DRIFT');
  requireGuard(review.accounts?.length === 6 && review.bootstrap.authAdminOnly === true
    && review.bootstrap.authIdsMustMatchExactReturnedAdminCreateIds === true, 'REAL_AUTH_CONTRACT_REQUIRED');
  return review;
}

export function expectedSessionSlots(review) {
  const slots = review.syntheticScopes.filter(s => s.key !== 'foreign').flatMap(scope =>
    BUSINESS_ACTORS.map(actorLabel => ({ scopeKey: scope.key, actorLabel, ordinal: 0 })));
  slots.push(...Array.from({ length: 4 }, (_, ordinal) => ({ scopeKey: 'foreign', actorLabel: 'foreign-member', ordinal })));
  requireGuard(slots.length === 2000, 'EXACT_SESSION_DISTRIBUTION_REQUIRED');
  return slots;
}

export function validateApproval(approval, review, binding, nowMs = Date.now()) {
  requireGuard(approval?.kind === 'wave5-runtime-owner-decision' && approval.decision === 'approve'
    && approval.source?.kind === 'direct_user_message' && typeof approval.source.reference === 'string'
    && approval.source.reference.length > 0 && isSha(approval.source.messageSha256), 'EXPLICIT_OWNER_APPROVAL_REQUIRED');
  requireGuard(approval.runtimeBundleSha256 === review.bundleSha256 && approval.runtimeFileSha256 === binding.runtimeFileSha256,
    'APPROVAL_BINDING_MISMATCH');
  requireGuard(approval.projectId === PROJECT_ID && approval.production === false && approval.realBilling === false
    && approval.installOriginalSix === false && approval.noGlobalAuthChanges === true, 'APPROVAL_SCOPE_MISMATCH');
  requireGuard(millis(approval.approvedAt) <= nowMs, 'ACTUAL_OWNER_DECISION_TIME_REQUIRED');
  return approval;
}

export function validatePreparation(preparation, review, binding) {
  requireGuard(preparation?.kind === 'wave5-runtime-harness-preparation' && preparation.sourceBindingsVerified === true
    && preparation.runtimeBundleSha256 === review.bundleSha256 && preparation.runtimeFileSha256 === binding.runtimeFileSha256
    && preparation.harnessReviewSha256 === binding.harnessReviewSha256 && preparation.planSha256 === binding.planSha256
    && preparation.privateProviderSha256 === binding.privateProviderSha256, 'PREPARATION_BINDING_MISMATCH');
  requireGuard(preparation.independentReview?.result === 'approved-for-existing-bounded-scope'
    && isSha(preparation.independentReview.sha256) && typeof preparation.independentReview.path === 'string'
    && preparation.independentReview.path.length > 0 && preparation.sameApprovedOperationScope === true
    && preparation.additionalOwnerAuthorizationRequired === false && preparation.production === false
    && preparation.realBilling === false && preparation.installOriginalSix === false, 'INDEPENDENT_PREPARATION_REVIEW_REQUIRED');
  return preparation;
}

export function validateIndependentPreparationReview(independent, preparation, review, binding) {
  requireGuard(independent?.kind === 'wave5-runtime-harness-independent-preparation-review'
    && independent.result === 'approved-for-existing-bounded-scope' && independent.projectId === PROJECT_ID
    && independent.runtimeBundleSha256 === review.bundleSha256 && independent.runtimeFileSha256 === binding.runtimeFileSha256
    && independent.harnessReviewSha256 === binding.harnessReviewSha256 && independent.planSha256 === binding.planSha256
    && independent.privateProviderSha256 === binding.privateProviderSha256 && independent.sourceBindingsVerified === true
    && independent.operationScopeSha256 === review.sourceContinuation.unchangedRuntimeOperationScopeSha256
    && independent.sameApprovedOperationScope === true && independent.additionalOwnerAuthorizationRequired === false
    && independent.production === false && independent.realBilling === false && independent.installOriginalSix === false
    && preparation.independentReview.result === independent.result, 'INDEPENDENT_PREPARATION_VERDICT_REQUIRED');
  requireGuard(isSha(binding.independentReviewBodySha256) && hashJson(independent) === binding.independentReviewBodySha256,
    'INDEPENDENT_PREPARATION_REVIEW_DRIFT');
  return independent;
}

export function reviewedExecutionContext({ review, plan, approval, preparation, independentReview, binding }) {
  // Revalidate canonical review and plan before any provider getter/call. Freeze private-factory inputs too.
  validateRuntimeReview(review); validatePlan(plan, review); validateApproval(approval, review, binding);
  validatePreparation(preparation, review, binding);
  requireGuard(isSha(binding.planBodySha256) && hashJson(plan) === binding.planBodySha256, 'PLAN_BODY_BINDING_MISMATCH');
  validateIndependentPreparationReview(independentReview, preparation, review, binding);
  return immutableJson({ review, plan, approval, preparation, independentReview, binding });
}

export function validatePlan(plan, review) {
  requireGuard(plan?.kind === 'wave5-runtime-harness-plan' && plan.projectId === PROJECT_ID && plan.url === PROJECT_URL
    && plan.production === false && plan.realBilling === false && plan.runtimeBundleSha256 === review.bundleSha256,
    'EXACT_DEVELOPMENT_TARGET_REQUIRED');
  requireGuard(plan.warmupMs === 60000 && plan.measuredMs === 300000 && plan.maxRunMs === 900000
    && plan.maximumTimedRequests <= 100000 && Number.isSafeInteger(plan.maximumTimedRequests)
    && plan.maximumTimedRequests >= 20000 && plan.maxInflight === 2000, 'LOAD_LIMITS_REQUIRED');
  requireGuard(Number.isFinite(plan.requestsPerSecond) && plan.requestsPerSecond >= 20
    && plan.requestsPerSecond * 360 <= plan.maximumTimedRequests && plan.requestsPerSecond <= 100000 / 360,
    'REQUEST_RATE_OUTSIDE_BOUND');
  requireGuard(plan.cases?.length === RACE_KINDS.length && RACE_KINDS.every(kind => plan.cases.filter(c => c.kind === kind).length === 1),
    'ALL_REVIEWED_RACES_REQUIRED');
  for (const race of plan.cases) {
    const permittedScope = ['quota', 'seats', 'admissions'].includes(race.kind) ? 'load-001' : 'runtime';
    requireGuard(race.scopeKey === permittedScope && isUuid(race.caseId) && isSha(race.fixturePlanSha256)
      && isSha(race.committedQuerySha256) && isSha(race.preparationSha256) && isSha(race.restorationSha256), 'REVIEWED_CASE_BINDING_REQUIRED');
    const count = race.kind === 'duplicates' ? 100 : race.kind === 'quota' ? 20 : 2;
    requireGuard(race.participants === count && race.noExternalSend === true, 'RACE_PARTICIPANT_BOUNDARY');
  }
  requireGuard(plan.boundaries?.length === 4 && BOUNDARY_KINDS.every(kind => plan.boundaries.filter(b => b.kind === kind).length === 1),
    'ALL_INVALID_BOUNDARIES_REQUIRED');
  for (const boundary of plan.boundaries) {
    requireGuard(boundary.scopeKey === 'runtime' && isUuid(boundary.caseId) && isSha(boundary.fixturePlanSha256)
      && isSha(boundary.committedQuerySha256) && boundary.expectedCode === 'LIMIT_EXCEEDED', 'BOUNDARY_BINDING_REQUIRED');
  }
  requireGuard(isSha(plan.loadCommittedQuerySha256) && isSha(plan.loadFixturePlanSha256)
    && isSha(plan.externalObservationSourceSha256), 'LOAD_COMMITTED_BINDING_REQUIRED');
  return plan;
}

export function validatePreflight(proof, review, plan, binding, nowMs = Date.now()) {
  requireGuard(proof?.kind === 'online-installed-wave5-harness-preflight' && proof.projectId === PROJECT_ID
    && proof.url === PROJECT_URL && proof.runtimeBundleSha256 === review.bundleSha256
    && proof.harnessReviewSha256 === binding.harnessReviewSha256 && proof.planSha256 === binding.planSha256,
    'ONLINE_PREFLIGHT_BINDING_REQUIRED');
  requireGuard(nowMs - millis(proof.observedAt) >= 0 && nowMs - millis(proof.observedAt) <= 300000
    && millis(proof.validUntil) >= nowMs + LOAD_LIMITS.maxRunMs, 'FRESH_PREFLIGHT_REQUIRED');
  requireGuard(proof.installedMigrationCount === 114 && proof.pending71Installed === true && proof.originalSixPreserved === true
    && proof.signaturesGrantsForcedRlsVerified === true && proof.protectedSourcesUnchanged === true
    && proof.scopeDigestSha256 === hashJson(review.syntheticScopes) && proof.capacitySupported === true
    && proof.noGlobalAuthChanges === true && proof.noFabricatedAuth === true && proof.noAcceptanceScopes === true,
    'INSTALLED_CONTRACT_OR_PRESERVATION_MISSING');
  for (const key of ['ledgerSha256', 'contractFingerprintSha256', 'capacityEvidenceSha256', 'rowDistributionSha256', 'authCreationEvidenceSha256']) {
    requireGuard(isSha(proof[key]), 'PREFLIGHT_EVIDENCE_HASH_REQUIRED');
  }
  const env = proof.environment;
  requireGuard(env && ['region', 'databaseTier', 'postgresVersion', 'generatorHost', 'cacheConditions'].every(k =>
    typeof env[k] === 'string' && /^[A-Za-z0-9 ._:/()+-]{1,160}$/.test(env[k]))
    && isSha(env.hardwareSha256) && env.maximumConcurrentSessions >= 2000
    && env.maximumRequestsPerSecond >= plan.requestsPerSecond, 'ACTUAL_CAPACITY_EVIDENCE_REQUIRED');
  requireGuard(proof.authIds && review.accounts.every(a => isUuid(proof.authIds[a.label]))
    && new Set(Object.values(proof.authIds)).size === 6 && Object.keys(proof.authIds).length === 6
    && proof.operatorMembershipCount === 0, 'EXACT_REAL_AUTH_IDS_REQUIRED');
  requireGuard(isSha(proof.fixturePopulationSha256) && proof.fixtureCapsVerified === true
    && proof.nonemptyIndexedForecastsAll500 === true && proof.nonemptyProcessSourcesAll500 === true,
    'NONEMPTY_REVIEWED_FIXTURES_REQUIRED');
  requireGuard(proof.reviewedSchedulesQuiesced === true && proof.noModelOrWebhookInLoad === true, 'LOAD_EXTERNAL_EFFECTS_EXCLUDED');
  return proof;
}

export function validateSessions(sessions, review, preflight, nowMs = Date.now()) {
  requireGuard(sessions?.length === 2000, 'TWO_THOUSAND_REAL_SESSIONS_REQUIRED');
  const wanted = new Set(expectedSessionSlots(review).map(s => `${s.scopeKey}/${s.actorLabel}/${s.ordinal}`));
  const ids = new Set(); const connections = new Set();
  for (const session of sessions) {
    requireGuard(session.kind === 'auth' && isUuid(session.sessionId) && isUuid(session.actorId)
      && session.actorId === preflight.authIds[session.actorLabel] && session.actorLabel !== 'operator', 'SESSION_ACTOR_MISMATCH');
    const slot = `${session.scopeKey}/${session.actorLabel}/${session.ordinal}`;
    requireGuard(wanted.delete(slot) && !ids.has(session.sessionId) && !connections.has(session.connectionId), 'INDEPENDENT_SESSION_REQUIRED');
    ids.add(session.sessionId); connections.add(session.connectionId);
    validateConnection(session);
    requireGuard(session.onlineAuthVerified === true && session.serverSessionRowVerified === true
      && session.serverSessionActorId === session.actorId && session.serverSessionId === session.sessionId
      && session.issuer === `${PROJECT_URL}/auth/v1` && session.authRole === 'authenticated'
      && isSha(session.verificationEvidenceSha256), 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
    requireGuard(nowMs - millis(session.verifiedAt) >= 0 && nowMs - millis(session.verifiedAt) <= 300000
      && millis(session.expiresAt) >= nowMs + LOAD_LIMITS.maxRunMs && session.revoked === false,
      'FRESH_UNREVOKED_SESSION_REQUIRED');
    requireGuard(session.aal === 'aal1' || session.aal === 'aal2', 'REAL_AAL_REQUIRED');
    if ((session.scopeKey === 'runtime' && ['approver', 'executor', 'billing-admin'].includes(session.actorLabel))
      || (session.scopeKey === 'load-001' && session.actorLabel === 'billing-admin')) {
      requireGuard(session.aal === 'aal2' && isUuid(session.verifiedFactorId) && session.realMfaVerified === true, 'GENUINE_RUNTIME_MFA_REQUIRED');
    }
  }
  requireGuard(wanted.size === 0, 'EXACT_SESSION_DISTRIBUTION_REQUIRED');
  requireGuard(sessions.filter(s => s.actorLabel === 'executor' && s.aal === 'aal2' && s.realMfaVerified === true
    && isUuid(s.verifiedFactorId)).length >= 2, 'GENUINE_EXECUTOR_SESSION_PAIR_REQUIRED');
  return sessions;
}

export function validateConnection(participant) {
  requireGuard(typeof participant.connectionId === 'string' && /^[A-Za-z0-9._:-]{1,100}$/.test(participant.connectionId)
    && isSha(participant.connectionEvidenceSha256), 'VERIFIED_CONNECTION_REQUIRED');
  if (participant.kind === 'trusted') requireGuard(participant.serviceRoleVerified === true && participant.independentConnectionVerified === true
    && isSha(participant.authorityEvidenceSha256), 'TRUSTED_INDEPENDENT_CONNECTION_REQUIRED');
  else requireGuard(participant.kind === 'auth', 'UNKNOWN_CONNECTION_KIND');
}

export function publicParticipant(participant) {
  validateConnection(participant);
  if (participant.kind === 'auth') requireGuard([...BUSINESS_ACTORS, 'foreign-member'].includes(participant.actorLabel)
    && isUuid(participant.actorId) && isUuid(participant.sessionId) && isSha(participant.verificationEvidenceSha256), 'PUBLIC_AUTH_IDENTITY_REQUIRED');
  return { kind: participant.kind, actorLabel: participant.kind === 'auth' ? participant.actorLabel : null,
    actorId: participant.kind === 'auth' ? participant.actorId : null,
    sessionId: participant.kind === 'auth' ? participant.sessionId : null,
    connectionId: participant.connectionId, connectionEvidenceSha256: participant.connectionEvidenceSha256,
    verificationEvidenceSha256: participant.kind === 'auth' ? participant.verificationEvidenceSha256 : participant.authorityEvidenceSha256 };
}

export function publicOutcome(raw) {
  requireGuard(raw && ['applied', 'replayed', 'denied', 'empty', 'uncertain'].includes(raw.outcome), 'INVALID_PROVIDER_OUTCOME');
  requireGuard(isSha(raw.responseSha256), 'RESPONSE_HASH_REQUIRED');
  requireGuard(isSha(raw.transportEvidenceSha256), 'ACTUAL_TRANSPORT_EVIDENCE_REQUIRED');
  requireGuard(raw.originalCommandId === null || isUuid(raw.originalCommandId), 'ORIGINAL_COMMAND_ID_REQUIRED');
  let serverSpan = null;
  if (raw.serverSpan !== undefined && raw.serverSpan !== null) {
    const s = raw.serverSpan;
    requireGuard(Number.isFinite(millis(s.startedAt)) && millis(s.finishedAt) >= millis(s.startedAt)
      && typeof s.backendId === 'string' && /^[A-Za-z0-9._:-]{1,100}$/.test(s.backendId) && isSha(s.evidenceSha256), 'SERVER_SPAN_PROOF_REQUIRED');
    serverSpan = { startedAt: s.startedAt, finishedAt: s.finishedAt, backendId: s.backendId, evidenceSha256: s.evidenceSha256 };
  }
  return { outcome: raw.outcome, code: raw.outcome === 'denied' ? safeCode(raw.code) : null,
    responseSha256: raw.responseSha256, transportEvidenceSha256: raw.transportEvidenceSha256, originalCommandId: raw.originalCommandId,
    entityId: isUuid(raw.entityId) ? raw.entityId : null, serverSpan };
}

export function validateCommittedSnapshot(raw, caseBinding, scope, earliestMs) {
  requireGuard(raw?.kind === 'committed-state-snapshot' && raw.projectId === PROJECT_ID && raw.caseId === caseBinding.caseId
    && raw.scopeKey === scope.key && raw.tenantId === scope.tenantId && raw.readOnly === true && raw.committed === true
    && raw.isolation === 'repeatable-read' && raw.querySha256 === caseBinding.committedQuerySha256
    && isSha(raw.snapshotSha256) && isSha(raw.transactionEvidenceSha256) && millis(raw.observedAt) >= earliestMs,
    'COMMITTED_SCOPED_READ_REQUIRED');
  requireGuard(COUNTERS.every(k => Number.isSafeInteger(raw.counters?.[k]) && raw.counters[k] >= 0)
    && Object.keys(raw.counters).length === COUNTERS.length, 'COMMITTED_COUNTERS_REQUIRED');
  requireGuard(['reservedUnits', 'settledUnits', 'seatLimit', 'activeAndInvited', 'subscriptionVersion'].every(k =>
    Number.isSafeInteger(raw.state?.[k]) && raw.state[k] >= 0), 'COMMITTED_STATE_REQUIRED');
  requireGuard(Array.isArray(raw.deniedAttemptEffects) && raw.deniedAttemptEffects.every(item =>
    isUuid(item.attemptId) && COUNTERS.every(k => item.counters?.[k] === 0)), 'DENIED_ATTEMPT_EFFECT_REQUIRED');
  return { kind: raw.kind, caseId: raw.caseId, scopeKey: raw.scopeKey, tenantId: raw.tenantId, observedAt: raw.observedAt,
    querySha256: raw.querySha256, snapshotSha256: raw.snapshotSha256, transactionEvidenceSha256: raw.transactionEvidenceSha256,
    isolation: raw.isolation, committed: true, counters: { ...raw.counters }, state: Object.fromEntries(
      ['reservedUnits', 'settledUnits', 'seatLimit', 'activeAndInvited', 'subscriptionVersion'].map(k => [k, raw.state[k]])),
    deniedAttemptEffects: raw.deniedAttemptEffects.map(item => ({ attemptId: item.attemptId, counters: zeroCounters() })) };
}

export function checkRaceEffects(kind, before, after, attempts) {
  const delta = Object.fromEntries(COUNTERS.map(k => [k, after.counters[k] - before.counters[k]]));
  requireGuard(COUNTERS.every(k => delta[k] >= 0), 'COMMITTED_EFFECT_REGRESSION');
  const denied = attempts.filter(a => a.outcome === 'denied');
  requireGuard(denied.every(a => after.deniedAttemptEffects.some(d => d.attemptId === a.attemptId)), 'DENIED_ZERO_EFFECT_PROOF_MISSING');
  const count = outcome => attempts.filter(a => a.outcome === outcome).length;
  requireGuard(count('uncertain') === 0, 'UNCERTAIN_MUTATION_REQUIRES_REVIEW');
  requireGuard(after.state.activeAndInvited <= after.state.seatLimit, 'SEAT_CAP_EXCEEDED');
  if (kind === 'duplicates') {
    requireGuard(delta.business === 1 && delta.receipt === 1 && delta.audit === 1 && delta.outbox === 1
      && delta.membership === 0 && delta.usage === 0 && delta.lease === 0 && delta.activation === 0
      && count('applied') + count('replayed') === 100, 'DUPLICATE_EFFECT_MISMATCH');
    requireGuard(new Set(attempts.map(a => a.entityId)).size === 1 && isUuid(attempts[0].entityId), 'DUPLICATE_ENTITY_MISMATCH');
  } else if (kind === 'quota') {
    requireGuard(before.state.reservedUnits === 0 && before.state.settledUnits === 0 && delta.usage === 10
      && after.state.reservedUnits === 10 && after.state.settledUnits === 0 && count('applied') === 10 && count('denied') === 10
      && denied.every(a => a.code === 'QUOTA_EXCEEDED') && COUNTERS.filter(k => k !== 'usage').every(k => delta[k] === 0), 'QUOTA_EFFECT_MISMATCH');
  } else if (kind === 'seats') {
    requireGuard(before.state.seatLimit === 3 && before.state.activeAndInvited === 2 && after.state.seatLimit === 3
      && after.state.activeAndInvited === 3 && delta.membership === 1 && delta.audit === 1
      && count('applied') === 1 && count('denied') === 1 && denied[0].code === 'SEAT_QUOTA_EXCEEDED'
      && COUNTERS.filter(k => !['membership', 'audit'].includes(k)).every(k => delta[k] === 0), 'SEAT_EFFECT_MISMATCH');
  } else if (kind === 'activation') {
    requireGuard(delta.activation === 1 && delta.business === 1 && delta.receipt === 1 && delta.audit === 1 && delta.outbox === 1
      && delta.membership === 0 && delta.usage === 0 && delta.lease === 0 && count('applied') + count('replayed') === 2
      && after.state.subscriptionVersion === before.state.subscriptionVersion + 1, 'ACTIVATION_EFFECT_MISMATCH');
  } else if (kind === 'execution') {
    requireGuard(delta.business === 2 && delta.receipt === 2 && delta.audit === 2 && delta.outbox === 2
      && delta.membership === 0 && delta.usage === 0 && delta.lease === 0 && delta.activation === 0
      && count('applied') + count('replayed') === 2, 'EXECUTION_EFFECT_MISMATCH');
  } else if (kind === 'outboxLeases') {
    // Scoped claim creates one lease/attempt; authorization does not reserve usage or send a webhook.
    requireGuard(delta.lease === 1 && count('applied') === 1 && count('empty') === 1
      && COUNTERS.filter(k => k !== 'lease').every(k => delta[k] === 0), 'LEASE_EFFECT_MISMATCH');
  } else if (kind === 'admissions') {
    // Acceptance and a reduction to the two occupied seats share the billing row lock.
    const accepted = delta.membership === 1 && delta.audit === 1 && delta.activation === 0 && delta.business === 0
      && delta.receipt === 0 && delta.outbox === 0 && after.state.seatLimit === 3 && after.state.activeAndInvited === 3;
    const activated = delta.membership === 0 && delta.activation === 1 && delta.business === 1 && delta.receipt === 1
      && delta.audit === 1 && delta.outbox === 1 && after.state.seatLimit === 2 && after.state.activeAndInvited === 2;
    requireGuard(before.state.seatLimit === 3 && before.state.activeAndInvited === 2 && (accepted || activated)
      && delta.usage === 0 && delta.lease === 0 && count('applied') === 1 && count('denied') === 1
      && denied[0].code === 'SEAT_QUOTA_EXCEEDED', 'ADMISSION_ACTIVATION_EFFECT_MISMATCH');
  } else throw new GuardError('UNKNOWN_RACE');
  return delta;
}

export function nearestRankP95(samples) {
  requireGuard(samples.length > 0 && samples.every(v => Number.isFinite(v) && v >= 0), 'REAL_TIMINGS_REQUIRED');
  const ordered = [...samples].sort((a, b) => a - b);
  return ordered[Math.ceil(ordered.length * 0.95) - 1];
}
