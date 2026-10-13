import { PROJECT_ID, PROJECT_URL, GuardError, requireGuard, isUuid, isSha, hashJson, immutableJson, freshId,
  reviewedExecutionContext, validatePreflight, expectedSessionSlots, COUNTERS, zeroCounters, OPERATIONS, safeCode } from './runtime_contract.mjs';
import { FIXTURE_CAPS, SQL_CONTRACTS, RACE_FIXTURES, INVALID_BOUNDARIES } from './runtime_fixture_spec.mjs';
import { createSupabaseHttpsTransport, createAuthClient } from './supabase_http_transport.mjs';
import { createSupabaseReadStore, exactInteger, committedRecipeHash, READ_QUERY_SHA256 } from './supabase_read_store.mjs';
import { createMembershipFixture } from './supabase_membership_fixture.mjs';
import { createPreparationJournal } from './preparation_journal.mjs';

export const CASE_READ_RECIPES = immutableJson({ duplicates: ['scopeSnapshot'], seats: ['scopeSnapshot', 'invitationProvenance'],
  admissions: ['scopeSnapshot', 'invitationProvenance', 'activationPrerequisites'], activation: ['scopeSnapshot', 'activationPrerequisites'],
  execution: ['scopeSnapshot', 'proposalPrerequisites'], outboxLeases: ['scopeSnapshot', 'leasePrerequisites'],
  quota: ['scopeSnapshot', 'invocationProvenance'] });
const fail = code => { throw new GuardError(code); };
const finiteTime = value => typeof value === 'string' && Number.isFinite(Date.parse(value));
const validDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(`${value}T00:00:00.000Z`)) && new Date(`${value}T00:00:00.000Z`).toISOString().slice(0, 10) === value;
export function validateProviderCalendar(calendar) {
  requireGuard(calendar && validDate(calendar.horizonStart) && validDate(calendar.horizonEnd)
    && Date.parse(calendar.horizonEnd) > Date.parse(calendar.horizonStart)
    && Date.parse(calendar.horizonEnd) - Date.parse(calendar.horizonStart) <= 366 * 86400000
    && ['windowStart', 'windowEnd', 'asOf', 'recordedThrough', 'clientTimestamp'].every(key => finiteTime(calendar[key]))
    && Date.parse(calendar.windowStart) < Date.parse(calendar.windowEnd)
    && Date.parse(calendar.windowEnd) <= Date.parse(calendar.asOf) && Date.parse(calendar.asOf) <= Date.parse(calendar.recordedThrough)
    && Date.parse(calendar.recordedThrough) <= Date.now()
    && Date.parse(calendar.windowEnd) - Date.parse(calendar.windowStart) <= 366 * 86400000, 'REVIEWED_PREPARATION_REQUIRED');
  return immutableJson(calendar);
}

export function reviewedTrialWindow(review, target, subscription, seats, serverObservedAt) {
  const approvedScope = review.syntheticScopes.find(s => s.key === target.key),
    approvedPlan = review.syntheticPlans.find(p => p.code === approvedScope?.planCode);
  requireGuard(approvedScope?.tenantId === target.tenantId && ['runtime', 'load-001'].includes(target.key)
    && subscription.plan_code === approvedScope.planCode && approvedPlan?.trialDays === 7
    && seats === (target.key === 'runtime' ? approvedPlan.seats : 2)
    && finiteTime(serverObservedAt) && isUuid(subscription.id), 'EXACT_RACE_PREPARATION_REQUIRED');
  const starts = new Date(serverObservedAt).toISOString();
  return { planCode: approvedScope.planCode, starts, ends: new Date(Date.parse(starts) + approvedPlan.trialDays * 86400000).toISOString(),
    expectedVersion: String(exactInteger(subscription.version)), seats };
}

// Fixed scope, argument names and payloads taken from the actual SQL signatures.
// Private invitation tokens are never returned by this mapper to a public journal.
export function mappedRpcRequest({ operation, request, scope, fixture, calendar, forecastId, privateInvitation }) {
  const contract = SQL_CONTRACTS[operation]; requireGuard(contract && OPERATIONS[operation], 'PARTICIPANT_TRANSPORT_MISMATCH');
  requireGuard(isUuid(scope?.tenantId) && isUuid(scope.entityId) && isUuid(scope.branchId) && scope.key === request.scopeKey,
    'INVALID_REVIEWED_SCOPE');
  const scoped = { p_tenant_id: scope.tenantId, p_legal_entity_id: scope.entityId, p_branch_id: scope.branchId };
  let body;
  if (operation === 'forecast' || operation === 'executeProposal') {
    requireGuard(isUuid(request.commandId) && isUuid(request.idempotencyKey), 'ORIGINAL_COMMAND_ID_REQUIRED');
    const original = fixture?.public?.originalCommandId;
    if (request.phase === 'race') requireGuard(original === request.commandId && fixture.public.idempotencyKey === request.idempotencyKey,
      'RETURNED_COMMAND_ID_MISMATCH');
    body = { ...scoped, p_command_id: request.commandId, p_idempotency_key: request.idempotencyKey,
      p_client_timestamp: fixture?.clientTimestamp ?? calendar.clientTimestamp };
    requireGuard(finiteTime(body.p_client_timestamp), 'ORIGINAL_PREPARED_IDENTITIES_REQUIRED');
    if (operation === 'forecast') Object.assign(body, { p_horizon_start: calendar.horizonStart, p_horizon_end: calendar.horizonEnd });
    else { requireGuard(isUuid(fixture?.public?.resourceId), 'ORIGINAL_PREPARED_IDENTITIES_REQUIRED');
      Object.assign(body, { p_action: 'execute', p_payload: { proposalId: fixture.public.resourceId } }); }
  } else if (operation === 'indexedForecastRead') {
    requireGuard(isUuid(forecastId), 'NONEMPTY_REVIEWED_FIXTURES_REQUIRED'); body = { ...scoped, p_forecast_id: forecastId };
  } else if (operation === 'indexedBillingRead') body = { p_tenant_id: scope.tenantId };
  else if (operation === 'analytics') body = { ...scoped, p_window_start: calendar.windowStart, p_window_end: calendar.windowEnd,
    p_as_of: calendar.asOf, p_recorded_through: calendar.recordedThrough };
  else if (operation === 'acceptInvitation') {
    requireGuard(typeof privateInvitation?.token === 'string' && /^[a-f0-9]{64}$/.test(privateInvitation.token), 'EXACT_RACE_PREPARATION_REQUIRED');
    body = { p_token: privateInvitation.token };
  } else if (operation === 'reserveOne') {
    requireGuard(isUuid(request.commandId) && request.metric === 'webhook.deliveries' && request.quantity === '1'
      && finiteTime(fixture?.periodStart) && finiteTime(fixture.periodEnd), 'ONE_UNIT_QUOTA10_FIXTURE_REQUIRED');
    body = { p_tenant_id: scope.tenantId, p_invocation_id: request.commandId, p_metric_code: 'webhook.deliveries',
      p_period_start: fixture.periodStart, p_period_end: fixture.periodEnd, p_quantity: '1' };
  } else if (operation === 'activate') {
    requireGuard(isUuid(fixture?.public?.resourceId) && request.commandId === fixture.public.originalCommandId,
      'ORIGINAL_PREPARED_IDENTITIES_REQUIRED'); body = { p_tenant_id: scope.tenantId, p_revision_id: fixture.public.resourceId };
  } else if (operation === 'claimLease') {
    requireGuard(scope.key === 'runtime' && request.runtimeId === FIXTURE_CAPS.runtimeId, 'ONE_SCOPED_PENDING_LEASE_REQUIRED');
    body = { p_runtime_id: FIXTURE_CAPS.runtimeId, p_action: 'claim', p_payload: {} };
  }
  requireGuard(hashJson(Object.keys(body).sort()) === hashJson([...contract.parameters].sort()), 'INSTALLATION_CONTRACT_DRIFT');
  return { route: `/rest/v1/rpc/${contract.signature.split('(')[0].slice(4)}`, body };
}

export function outcomeFromRpc({ operation, request, response, scope }) {
  const value = response.value;
  const originalCommandId = ['forecast', 'executeProposal', 'activate', 'reserveOne'].includes(operation) ? request.commandId : null;
  const base = { responseSha256: response.responseSha256, transportEvidenceSha256: response.transportEvidenceSha256,
    originalCommandId, serverSpan: null, entityId: null };
  if (!response.ok) {
    // Only exact known Postgres rejection shapes are denials. Ambiguous HTTP failures remain uncertain.
    const allowed = { QUOTA_EXCEEDED: '54000', SEAT_QUOTA_EXCEEDED: '54000', LIMIT_EXCEEDED: '54000', PERMISSION_DENIED: '42501' };
    if (Object.hasOwn(allowed, value?.message) && value.code === allowed[value.message]) return { ...base, outcome: 'denied', code: value.message };
    // The installed shared permission function retains this exact message. Its
    // SQLSTATE and HTTP status must both match; arbitrary errors stay uncertain.
    if (value?.message === 'Permission denied or multi-factor authentication required.'
      && value.code === '42501' && response.status === 403) return { ...base, outcome: 'denied', code: 'PERMISSION_DENIED' };
    return { ...base, outcome: 'uncertain', code: null };
  }
  if (operation === 'claimLease' && value === null) return { ...base, outcome: 'empty' };
  if (['forecast', 'executeProposal'].includes(operation)) {
    // wave3_finish_command returns the caller's command separately from the
    // generated request/correlation IDs. Never relabel a request as a command.
    requireGuard(value?.command_id === request.commandId && isUuid(value.request_id)
      && isUuid(value.correlation_id) && isUuid(value.entity?.id), 'RETURNED_COMMAND_ID_MISMATCH');
    return { ...base, outcome: 'applied', entityId: value.entity.id };
  }
  if (operation === 'activate') {
    requireGuard(value?.request_id === request.commandId && isUuid(value.entity?.id), 'RETURNED_COMMAND_ID_MISMATCH');
    return { ...base, outcome: 'applied', entityId: value.entity.id };
  }
  if (operation === 'reserveOne') requireGuard(value?.invocationId === request.commandId && value.reservedUnits === '1', 'RETURNED_COMMAND_ID_MISMATCH');
  if (operation === 'acceptInvitation') requireGuard(isUuid(value?.membership_id) && isUuid(value.request_id), 'INVALID_PROVIDER_OUTCOME');
  if (operation === 'claimLease') requireGuard(isUuid(value?.deliveryId) && isUuid(value.leaseId), 'INVALID_PROVIDER_OUTCOME');
  if (operation === 'indexedForecastRead') requireGuard(isUuid(value?.id) && isSha(value.sourceHash) && value.evidence?.sourceCount > 0, 'NONEMPTY_REVIEWED_FIXTURES_REQUIRED');
  if (operation === 'analytics') requireGuard(value?.source?.complete === true && value.source.sourceCount > 0
    && Array.isArray(value.observations), 'NONEMPTY_REVIEWED_FIXTURES_REQUIRED');
  if (operation === 'indexedBillingRead') requireGuard(scope?.key === request.scopeKey && isUuid(scope.tenantId)
    && value?.contractRevision === 1 && isUuid(value.id) && value.tenantId === scope.tenantId
    && typeof value.version === 'string' && exactInteger(value.seats) >= 1
    && value.syntheticTarget === ['runtime', 'load-001'].includes(scope.key), 'INVALID_PROVIDER_OUTCOME');
  return { ...base, outcome: 'applied' };
}

const mapConcurrent = async (values, limit, work, signal) => {
  const results = new Array(values.length); let next = 0, failure;
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, async () => {
    while (!failure && !signal?.aborted) {
      const index = next++; if (index >= values.length) return;
      try { results[index] = await work(values[index], index); } catch (error) { failure ??= error; }
    }
  }));
  if (failure) throw failure; requireGuard(!signal?.aborted, 'RUN_ABORTED'); return results;
};

export function createSupabaseRuntimeProvider({ executionContext, privateConfig, requestFactory, agentFactory }) {
  // This is the guarded high-level factory. No private getter or I/O precedes canonical approvals/bindings.
  const context = reviewedExecutionContext(executionContext), { review, plan, binding } = context;
  requireGuard(privateConfig && ['privateActors', 'verifyOnlinePreflight', 'observeExternalTransport', 'appendPreparationEvidence'].every(key =>
    typeof privateConfig[key] === 'function') && typeof privateConfig.PgClient === 'function', 'PRIVATE_PROVIDER_INCOMPLETE');
  requireGuard(privateConfig.projectId === PROJECT_ID && ['privateConfigSourceSha256', 'postgresDriverSourceSha256', 'preparationJournalSourceSha256'].every(key => isSha(privateConfig[key])),
    'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
  const calendar = validateProviderCalendar(privateConfig.calendar);
  requireGuard(finiteTime(calendar.clientTimestamp), 'REVIEWED_PREPARATION_REQUIRED');
  requireGuard(plan.providerCalendarSha256 === hashJson(calendar)
    && privateConfig.privateConfigSourceSha256 === binding.privateProviderSha256
    && plan.postgresDriverSourceSha256 === privateConfig.postgresDriverSourceSha256
    && plan.preparationJournalSourceSha256 === privateConfig.preparationJournalSourceSha256
    && plan.cases.every(race => race.committedQuerySha256 === committedRecipeHash(CASE_READ_RECIPES[race.kind]))
    && plan.boundaries.every(boundary => boundary.committedQuerySha256 === READ_QUERY_SHA256.scopeSnapshot)
    && plan.loadCommittedQuerySha256 === READ_QUERY_SHA256.loadLedgers, 'PREPARATION_BINDING_MISMATCH');
  // Retain the reviewed callback/scalar references before any asynchronous work.
  // The read and fixture factories separately copy validated DB/TLS settings.
  // This does not certify the internals of privately supplied callback closures.
  privateConfig = Object.freeze(Object.fromEntries([
    'privateActors', 'verifyOnlinePreflight', 'observeExternalTransport', 'appendPreparationEvidence',
    'PgClient', 'databaseConfig', 'fixtureDatabaseConfig', 'authIds', 'anonKey',
    'privateSessions', 'persistPrivateSession', 'authConcurrency', 'serviceRoleKey'
  ].map(key => [key, privateConfig[key]])));
  const authIds = immutableJson(privateConfig.authIds), scopes = new Map(review.syntheticScopes.map(s => [s.key, s]));
  const preparationJournal = createPreparationJournal({ projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256,
    planBodySha256: binding.planBodySha256, sourceSha256: plan.preparationJournalSourceSha256,
    cases: [...plan.cases, ...plan.boundaries], appendPreparationEvidence: privateConfig.appendPreparationEvidence });
  const readStore = createSupabaseReadStore({ review, authIds, PgClient: privateConfig.PgClient, databaseConfig: privateConfig.databaseConfig });
  const memberships = createMembershipFixture({ executionContext: context, authIds, PgClient: privateConfig.PgClient,
    databaseConfig: privateConfig.fixtureDatabaseConfig ?? privateConfig.databaseConfig, preparationJournal });
  const transport = createSupabaseHttpsTransport({ projectId: PROJECT_ID, apiKey: privateConfig.anonKey, requestFactory, agentFactory });
  const actor = async label => {
    const value = await privateConfig.privateActors(label), wanted = review.accounts.find(a => a.label === label);
    requireGuard(wanted && value?.id === authIds[label] && value.email === wanted.email, 'SESSION_ACTOR_MISMATCH'); return value;
  };
  const auth = createAuthClient({ transport, privateActors: actor, privateSessions: privateConfig.privateSessions,
    readServerSession: readStore.readServerSession, persistPrivateSession: privateConfig.persistPrivateSession });
  const scope = key => { const value = scopes.get(key); requireGuard(value, 'INVALID_SCOPE_KEY'); return value; };
  const fixtures = new Map(), traces = [], trusted = new WeakMap(), attempts = new Map();
  let sessions = [], preflight = null, loadFrom = null, closed = false;
  const needsMfa = slot => slot.scopeKey === 'runtime' && ['proposer', 'approver', 'executor', 'billing-admin'].includes(slot.actorLabel)
    || slot.scopeKey === 'load-001' && ['billing-admin', 'executor'].includes(slot.actorLabel);
  const pick = (label, key = 'runtime') => { const value = sessions.find(s => s.actorLabel === label && s.scopeKey === key);
    requireGuard(value, 'ONLINE_SESSION_ROW_PROOF_REQUIRED'); return value; };
  function ready() { requireGuard(!closed && preflight, 'ONLINE_PREFLIGHT_BINDING_REQUIRED'); preparationJournal.assertHealthy(); }
  async function rpc(participant, route, body, signal, hooks = {}) {
    const hidden = participant.kind === 'auth' ? auth.privateConnection(participant) : trusted.get(participant);
    requireGuard(hidden, 'PARTICIPANT_TRANSPORT_MISMATCH');
    const response = await transport.send(hidden.handle, route, { body, bearer: hidden.token, profile: 'api', signal, ...hooks });
    traces.push(response.evidence); return response;
  }
  async function preparationRpc(participant, name, body, signal, caseId) {
    return preparationJournal.perform({ caseId, scopeKey: participant.scopeKey, action: `rpc-${name.replaceAll('_', '-')}`,
      intent: { actorId: participant.actorId, route: `/rest/v1/rpc/${name}`, parameters: body }, operation: async () => {
        const response = await rpc(participant, `/rest/v1/rpc/${name}`, body, signal);
        requireGuard(response.ok, 'EXACT_RACE_PREPARATION_REQUIRED'); return response;
      } });
  }
  const scoped = target => ({ p_tenant_id: target.tenantId, p_legal_entity_id: target.entityId, p_branch_id: target.branchId });
  async function sourceCheck(target, signal) {
    const proof = await readStore.read('sourcePopulation', { scopeKey: target.key }, signal), row = proof.rows[0];
    requireGuard(proof.rows.length === 1 && exactInteger(row.opportunity_rows) > 0 && exactInteger(row.process_event_rows) > 0
      && exactInteger(row.opportunity_rows) <= FIXTURE_CAPS.perTenant.opportunities
      && exactInteger(row.process_event_rows) <= FIXTURE_CAPS.perTenant.processEvents, 'NONEMPTY_REVIEWED_FIXTURES_REQUIRED'); return proof;
  }
  async function schedule(target, seats, signal, caseId) {
    const current = await readStore.read('subscription', { scopeKey: target.key }, signal), row = current.rows[0];
    requireGuard(current.rows.length === 1 && isUuid(row.id) && typeof row.plan_code === 'string', 'EXACT_RACE_PREPARATION_REQUIRED');
    const now = await readStore.read('calendar', {}, signal), window = reviewedTrialWindow(review, target, row, seats, now.rows[0].observed_at), command = freshId();
    const response = await preparationRpc(pick('billing-admin', target.key), 'schedule_synthetic_subscription', {
      p_tenant_id: target.tenantId, p_command_id: command, p_idempotency_key: command, p_client_timestamp: window.starts,
      p_expected_version: window.expectedVersion, p_plan_code: window.planCode, p_seats: window.seats,
      p_trial_starts_at: window.starts, p_trial_ends_at: window.ends }, signal, caseId);
    requireGuard(isUuid(response.value?.entity?.id), 'ORIGINAL_PREPARED_IDENTITIES_REQUIRED');
    const prerequisite = await readStore.read('activationPrerequisites', { scopeKey: target.key, resourceId: response.value.entity.id }, signal), actual = prerequisite.rows[0];
    requireGuard(prerequisite.rows.length === 1 && actual.actor_id === authIds['billing-admin'] && isUuid(actual.execution_id)
      && exactInteger(actual.busy_quota_periods) === 0 && exactInteger(actual.activation_rows) === 0
      && actual.expected_version === actual.subscription_version && actual.plan_code === window.planCode && actual.seats === window.seats
      && new Date(actual.trial_starts_at).toISOString() === window.starts && new Date(actual.trial_ends_at).toISOString() === window.ends,
      'EXACT_RACE_PREPARATION_REQUIRED');
    return { resourceId: actual.revision_id, originalCommandId: actual.execution_id, idempotencyKey: actual.execution_id,
      evidence: hashJson({ rpc: response.transportEvidenceSha256, prerequisite: prerequisite.snapshotSha256 }), prerequisite };
  }
  async function createInvitation(target, label, roleId, signal, caseId) {
    const owner = review.accounts.find(a => a.label === label);
    const response = await preparationRpc(pick('billing-admin', 'load-001'), 'create_invitation', { p_tenant_id: target.tenantId,
      p_email: owner.email, p_role_id: roleId, p_legal_entity_id: target.entityId, p_branch_id: target.branchId, p_expires_in_hours: 1 }, signal, caseId);
    requireGuard(isUuid(response.value?.invitation_id) && /^[a-f0-9]{64}$/.test(response.value?.token), 'EXACT_RACE_PREPARATION_REQUIRED');
    memberships.recordReturnedInvitation(response.value.invitation_id);
    return { label, actorId: authIds[label], invitationId: response.value.invitation_id, token: response.value.token,
      transportSha256: response.transportEvidenceSha256 };
  }
  async function entriesFor(race, fixture) {
    return CASE_READ_RECIPES[race.kind].map(name => ({ name, args: { scopeKey: race.scopeKey,
      ...(name === 'invitationProvenance' ? { cohort: fixture.invitations.map(i => ({ invitation_id: i.invitationId, actor_id: i.actorId })) } : {}),
      ...(name === 'activationPrerequisites' || name === 'proposalPrerequisites' ? { resourceId: fixture.public.resourceId } : {}),
      ...(name === 'invocationProvenance' ? { invocationIds: fixture.invocationIds } : {}) } }));
  }
  const readCase = async (race, fixture, signal) => readStore.readBatch(await entriesFor(race, fixture), signal);
  function deriveCounters(proof) {
    const row = proof.rows.scopeSnapshot?.[0]; requireGuard(proof.rows.scopeSnapshot?.length === 1
      && exactInteger(row.subscription_rows) === 1, 'COMMITTED_COUNTERS_REQUIRED');
    return { counters: Object.fromEntries(COUNTERS.map(key => [key, exactInteger(row[key])])), state: {
      reservedUnits: exactInteger(row.reserved_units_text), settledUnits: exactInteger(row.settled_units_text),
      seatLimit: exactInteger(row.seat_limit), activeAndInvited: exactInteger(row.active_and_invited), subscriptionVersion: exactInteger(row.subscription_version_text) } };
  }
  return Object.freeze({
    async verifyPreflight({ signal }) {
      const observed = await privateConfig.verifyOnlinePreflight({ context, signal });
      validatePreflight(observed, review, plan, binding);
      requireGuard(review.accounts.every(account => observed.authIds[account.label] === authIds[account.label]), 'EXACT_REAL_AUTH_IDS_REQUIRED');
      const installed = await readStore.read('installedSignaturesAndGrants', {}, signal);
      requireGuard(installed.rows.length === 12 && installed.rows.every(row => row.installed === true && row.required_role_execute === true
        && row.anon_execute === false && row.public_execute === false
        && (row.required_role !== 'service_role' || row.authenticated_execute === false)), 'INSTALLATION_CONTRACT_DRIFT');
      const quiescence = await readStore.read('loadQuiescence', {}, signal), quiet = quiescence.rows[0];
      requireGuard(exactInteger(quiet.running_tick_rows) === 0 && Array.isArray(quiet.reviewed_jobs)
        && quiet.reviewed_jobs.every(job => job.active === false), 'LOAD_EXTERNAL_EFFECTS_EXCLUDED');
      const forecastProof = await readStore.read('forecastIdentities', {}, signal);
      requireGuard(forecastProof.rows.length === 500 && new Set(forecastProof.rows.map(row => row.tenant_id)).size === 500
        && review.syntheticScopes.every(target => forecastProof.rows.some(row => row.tenant_id === target.tenantId && isUuid(row.id)
          && row.legal_entity_id === target.entityId && row.branch_id === target.branchId
          && exactInteger(row.source_count) > 0)), 'NONEMPTY_REVIEWED_FIXTURES_REQUIRED');
      for (const target of review.syntheticScopes) {
        const row = forecastProof.rows.find(row => row.tenant_id === target.tenantId); fixtures.set(`indexed/${target.key}`, { forecastId: row.id });
      }
      preflight = immutableJson(observed); return preflight;
    },
    async openSessions({ signal }) {
      ready(); const concurrency = privateConfig.authConcurrency ?? 16;
      requireGuard(Number.isInteger(concurrency) && concurrency >= 1 && concurrency <= 64, 'ACTUAL_CAPACITY_EVIDENCE_REQUIRED');
      sessions = await mapConcurrent(expectedSessionSlots(review), concurrency, slot => privateConfig.privateSessions
        ? auth.adopt(slot, needsMfa(slot), signal) : auth.acquire(slot, needsMfa(slot), signal), signal);
      return sessions;
    },
    async reverifySessions({ sessions: supplied, signal }) {
      ready(); requireGuard(supplied === sessions || hashJson(supplied) === hashJson(sessions), 'SESSION_IDENTITY_CHANGED_DURING_RUN');
      sessions = await mapConcurrent(supplied, privateConfig.authConcurrency ?? 16, value => auth.reverify(value, signal), signal); return sessions;
    },
    async openTrustedConnections({ kind, count, scopeKey, signal }) {
      ready(); requireGuard(['runtime', 'load-001'].includes(scopeKey) && Number.isInteger(count) && count >= 1 && count <= 20
        && typeof privateConfig.serviceRoleKey === 'string' && privateConfig.serviceRoleKey.length > 8, 'GENUINE_TRUSTED_CONNECTIONS_REQUIRED');
      const race = plan.cases.find(c => c.kind === kind && c.scopeKey === scopeKey), fixture = fixtures.get(race?.caseId);
      requireGuard(fixture && count === (kind === 'quota' ? 20 : kind === 'admissions' ? 1 : 2), 'GENUINE_TRUSTED_CONNECTIONS_REQUIRED');
      transport.drainIdleConnections();
      const participants = await mapConcurrent(Array.from({ length: count }), count, async () => {
        const handle = transport.connection(), provisional = Object.freeze({ kind: 'trusted' });
        trusted.set(provisional, { handle, token: privateConfig.serviceRoleKey, scopeKey });
        const response = await rpc(provisional, '/rest/v1/rpc/wave5_runtime_delivery_worker', {
          p_runtime_id: FIXTURE_CAPS.runtimeId, p_action: 'readiness', p_payload: {} }, signal);
        requireGuard(response.ok && response.value?.ready === true && response.value.contractRevision === 1, 'GENUINE_TRUSTED_CONNECTIONS_REQUIRED');
        const descriptor = Object.freeze({ kind: 'trusted', scopeKey, connectionId: handle.connectionId,
          connectionEvidenceSha256: hashJson({ connectionId: handle.connectionId, transport: response.transportEvidenceSha256 }),
          serviceRoleVerified: true, independentConnectionVerified: true, authorityEvidenceSha256: response.transportEvidenceSha256 });
        trusted.set(descriptor, trusted.get(provisional)); return descriptor;
      }, signal); fixture.trustedParticipants = participants; return participants;
    },
    async prepareRace({ race, signal }) {
      ready(); requireGuard(plan.cases.some(c => hashJson(c) === hashJson(race)), 'REVIEWED_CASE_BINDING_REQUIRED');
      const target = scope(race.scopeKey), command = freshId();
      const publicValue = { caseId: race.caseId, scopeKey: race.scopeKey, fixturePlanSha256: race.fixturePlanSha256,
        preparationSha256: race.preparationSha256, restorationSha256: race.restorationSha256,
        newReviewedScopesOnly: true, externalSendDisabled: true, originalCommandId: command, idempotencyKey: command,
        resourceId: fixtures.get(`indexed/${target.key}`).forecastId };
      const fixture = { public: publicValue, clientTimestamp: new Date().toISOString(), invocationIds: [], invitations: [] };
      return preparationJournal.perform({ caseId: race.caseId, scopeKey: race.scopeKey, action: 'race-preparation',
        intent: { original: publicValue, clientTimestamp: fixture.clientTimestamp }, operation: async () => {
      const source = await sourceCheck(target, signal);
      const evidence = [source.snapshotSha256];
      if (['seats', 'admissions'].includes(race.kind)) {
        const exact = await memberships.prepare({ signal, caseId: race.caseId }); evidence.push(exact.fixtureEvidenceSha256);
        for (const label of race.kind === 'seats' ? ['approver', 'executor'] : ['approver']) fixture.invitations.push(await createInvitation(target, label, exact.originalRoleId, signal, race.caseId));
        evidence.push(...fixture.invitations.map(i => i.transportSha256));
      }
      if (['admissions', 'activation'].includes(race.kind)) {
        const scheduled = await schedule(target, race.kind === 'activation' ? 5 : 2, signal, race.caseId);
        Object.assign(publicValue, { resourceId: scheduled.resourceId, originalCommandId: scheduled.originalCommandId,
          idempotencyKey: scheduled.idempotencyKey }); evidence.push(scheduled.evidence);
      }
      if (race.kind === 'execution') {
        const body = { ...scoped(target), p_command_id: command, p_idempotency_key: command, p_client_timestamp: fixture.clientTimestamp,
          p_action: 'create', p_payload: { sourceId: publicValue.resourceId, expiresAt: new Date(Date.now() + 3600000).toISOString() } };
        const created = await preparationRpc(pick('proposer'), 'wave5_proposal_command', body, signal, race.caseId), id = created.value?.entity?.id;
        requireGuard(isUuid(id) && isSha(created.value.entity.parametersHash), 'ORIGINAL_PREPARED_IDENTITIES_REQUIRED');
        const decisionCommand = freshId();
        const decided = await preparationRpc(pick('approver'), 'wave5_proposal_command', { ...body, p_command_id: decisionCommand,
          p_idempotency_key: decisionCommand, p_action: 'decide', p_payload: { proposalId: id,
            parametersHash: created.value.entity.parametersHash, decision: 'approved' } }, signal, race.caseId);
        const stored = await readStore.read('proposalPrerequisites', { scopeKey: target.key, resourceId: id }, signal), actual = stored.rows[0];
        requireGuard(stored.rows.length === 1 && actual.proposer_id === authIds.proposer && actual.approver_id === authIds.approver
          && actual.decision === 'approved' && actual.assurance === 'aal2' && actual.parameters_hash === actual.decision_parameters_hash
          && actual.target_revisions_unchanged === true && exactInteger(actual.execution_rows) === 0, 'REAL_DISTINCT_PROPOSAL_APPROVAL_REQUIRED');
        Object.assign(publicValue, { resourceId: id, originalCommandId: freshId(), idempotencyKey: freshId(), proposerActorId: authIds.proposer,
          approverActorId: authIds.approver, executorActorId: authIds.executor, realMfaApprovalVerified: pick('approver').realMfaVerified,
          approvalEvidenceSha256: hashJson({ created: created.transportEvidenceSha256, decided: decided.transportEvidenceSha256, stored: stored.snapshotSha256 }) });
        evidence.push(publicValue.approvalEvidenceSha256);
      }
      if (race.kind === 'outboxLeases') {
        const prior = await readStore.read('leasePrerequisites', { scopeKey: 'runtime' }, signal), row = prior.rows[0];
        requireGuard(exactInteger(row.enabled_subscriptions) === 0 && exactInteger(row.available_heads) === 0
          && exactInteger(row.unmaterialized_pairs) === 0 && exactInteger(row.leased_heads) === 0, 'ONE_SCOPED_PENDING_LEASE_REQUIRED');
        const receiver = review.workerConfiguration.receiver, keyRef = Object.keys(review.workerConfiguration.secrets.deliveryKeys)[0];
        const registered = await preparationRpc(pick('proposer'), 'wave5_integration_manage', { ...scoped(target), p_action: 'register',
          p_id: receiver.subscriptions.accept, p_expected_version: 0, p_payload: { url: receiver.paths.accept, keyRef } }, signal, race.caseId);
        requireGuard(registered.value?.id === receiver.subscriptions.accept && registered.value.enabled === true, 'ONE_SCOPED_PENDING_LEASE_REQUIRED');
        const seedCommand = freshId(), seed = await preparationRpc(pick('proposer'), 'freeze_pipeline_forecast', { ...scoped(target),
          p_command_id: seedCommand, p_idempotency_key: seedCommand, p_client_timestamp: new Date().toISOString(),
          p_horizon_start: calendar.horizonStart, p_horizon_end: calendar.horizonEnd }, signal, race.caseId);
        const available = await readStore.read('leasePrerequisites', { scopeKey: 'runtime' }, signal), pending = available.rows[0];
        requireGuard(exactInteger(pending.enabled_subscriptions) === 1 && pending.enabled_subscription_ids?.[0] === receiver.subscriptions.accept
          && exactInteger(pending.available_heads) + exactInteger(pending.unmaterialized_pairs) === 1, 'ONE_SCOPED_PENDING_LEASE_REQUIRED');
        Object.assign(publicValue, { pendingDeliveryCount: 1, runtimeId: FIXTURE_CAPS.runtimeId, runtimeScopeKey: 'runtime' });
        evidence.push(registered.transportEvidenceSha256, seed.transportEvidenceSha256, available.snapshotSha256);
      }
      if (race.kind === 'quota') {
        const current = await readStore.read('subscription', { scopeKey: target.key }, signal), row = current.rows[0];
        requireGuard(current.rows.length === 1 && row.status === 'trialing' && row.delivery_enabled === true
          && exactInteger(row.delivery_cap) === 10 && finiteTime(row.period_start) && finiteTime(row.period_end), 'ONE_UNIT_QUOTA10_FIXTURE_REQUIRED');
        Object.assign(fixture, { periodStart: row.period_start, periodEnd: row.period_end });
        Object.assign(publicValue, { quantity: '1', hardCap: '10', metric: 'webhook.deliveries' }); evidence.push(current.snapshotSha256);
      }
      publicValue.preparationEvidenceSha256 = hashJson({ sourceBindings: race.preparationSha256, evidence });
      fixtures.set(race.caseId, fixture); return immutableJson(publicValue);
      } });
    },
    async arm(participant, request, { signal }) {
      ready(); requireGuard(fixtures.has(request.caseId), 'EXACT_RACE_PREPARATION_REQUIRED');
      let proof;
      if (participant.kind === 'auth') proof = (await auth.reverify(participant, signal)).verificationEvidenceSha256;
      else {
        const response = await rpc(participant, '/rest/v1/rpc/wave5_runtime_delivery_worker', {
          p_runtime_id: FIXTURE_CAPS.runtimeId, p_action: 'readiness', p_payload: {} }, signal);
        requireGuard(response.ok && response.value?.ready === true, 'ONLINE_BARRIER_READINESS_REQUIRED'); proof = response.transportEvidenceSha256;
      }
      return { ready: true, onlineVerified: true, connectionId: participant.connectionId, evidenceSha256: proof };
    },
    async call(participant, request, { signal, onTransportStart, onTransportEnd }) {
      ready(); const target = scope(request.scopeKey), fixture = request.caseId ? fixtures.get(request.caseId) : null;
      requireGuard(OPERATIONS[request.operation]?.transport === participant.kind, 'PARTICIPANT_TRANSPORT_MISMATCH');
      if (request.phase === 'timed') requireGuard(participant.scopeKey === request.scopeKey
        && ['forecast', 'analytics', 'indexedForecastRead', 'indexedBillingRead'].includes(request.operation)
        && (request.operation !== 'forecast' || !['billing-admin', 'foreign-member'].includes(participant.actorLabel))
        && (request.operation !== 'analytics' || participant.actorLabel !== 'billing-admin'), 'PERMITTED_WORKLOAD_SESSIONS_REQUIRED');
      else requireGuard(fixture && plan.cases.some(c => c.caseId === request.caseId && c.fixturePlanSha256 === request.fixturePlanSha256
        && c.scopeKey === request.scopeKey && (RACE_FIXTURES[c.kind].operations ?? [RACE_FIXTURES[c.kind].operation]).includes(request.operation)), 'REVIEWED_CASE_BINDING_REQUIRED');
      if (participant.kind === 'trusted') requireGuard(trusted.get(participant)?.scopeKey === target.key, 'INVALID_REVIEWED_SCOPE');
      const invitation = fixture?.invitations.find(i => i.actorId === participant.actorId);
      const mapped = mappedRpcRequest({ operation: request.operation, request, scope: target, fixture, calendar,
        forecastId: fixtures.get(`indexed/${target.key}`)?.forecastId, privateInvitation: invitation });
      attempts.set(request.attemptId, { request, actorId: participant.actorId, invitationId: invitation?.invitationId });
      if (request.operation === 'reserveOne') fixture.invocationIds.push(request.commandId);
      const response = await rpc(participant, mapped.route, mapped.body, signal, { onTransportStart, onTransportEnd });
      const outcome = outcomeFromRpc({ operation: request.operation, request, response, scope: target });
      attempts.get(request.attemptId).outcome = outcome; return outcome;
    },
    async readCommitted({ race, attempts: supplied, signal }) {
      ready(); const fixture = fixtures.get(race.caseId); requireGuard(fixture, 'EXACT_RACE_PREPARATION_REQUIRED');
      // Quota IDs are created at the barrier. Before-snapshot proves no existing reservation;
      // after-snapshot proves each original denied invocation against actual rows.
      const proof = await readCase(race, fixture, signal);
      requireGuard(proof.querySha256 === race.committedQuerySha256, 'COMMITTED_SCOPED_READ_REQUIRED');
      const derived = deriveCounters(proof);
      if (race.kind === 'quota' && !supplied.length) requireGuard(derived.counters.usage === 0
        && derived.state.reservedUnits === 0 && derived.state.settledUnits === 0, 'ONE_UNIT_QUOTA10_FIXTURE_REQUIRED');
      if (!supplied.length) fixture.before = proof;
      const deniedAttemptEffects = [];
      for (const attempt of supplied.filter(item => item.outcome === 'denied')) {
        const actual = attempts.get(attempt.attemptId); requireGuard(actual?.outcome?.outcome === 'denied', 'DENIED_ZERO_EFFECT_PROOF_MISSING');
        if (actual.request.operation === 'reserveOne') {
          const row = proof.rows.invocationProvenance?.find(r => r.invocation_id === attempt.commandId);
          requireGuard(row && ['reservation_rows', 'usage_event_rows', 'receipt_rows', 'audit_rows', 'outbox_rows'].every(k => exactInteger(row[k]) === 0), 'DENIED_ZERO_EFFECT_PROOF_MISSING');
        } else if (actual.request.operation === 'acceptInvitation') {
          const prior = fixture.before.rows.invitationProvenance.find(r => r.invitation_id === actual.invitationId),
            row = proof.rows.invitationProvenance?.find(r => r.invitation_id === actual.invitationId);
          requireGuard(row && prior && row.invitation_status === prior.invitation_status && row.membership_status === prior.membership_status
            && row.accepted_by === prior.accepted_by && ['active_membership_rows', 'audit_rows', 'receipt_rows', 'outbox_rows'].every(k => exactInteger(row[k]) === exactInteger(prior[k])),
            'DENIED_ZERO_EFFECT_PROOF_MISSING');
        } else if (actual.request.operation === 'activate') {
          const row = proof.rows.activationPrerequisites?.[0], prior = fixture.before.rows.activationPrerequisites?.[0];
          requireGuard(row && prior && ['activation_rows', 'receipt_rows', 'audit_rows', 'outbox_rows'].every(k => exactInteger(row[k]) === exactInteger(prior[k])),
            'DENIED_ZERO_EFFECT_PROOF_MISSING');
        } else fail('DENIED_ZERO_EFFECT_PROOF_MISSING');
        // Categories outside each denied endpoint's atomic SQL footprint must also
        // remain unchanged at cohort level. An unrelated winner is never attributed to the loser.
        const unaffected = actual.request.operation === 'acceptInvitation' ? race.kind === 'admissions' ? ['usage', 'lease'] : ['business', 'usage', 'lease', 'activation']
          : actual.request.operation === 'reserveOne' ? COUNTERS.filter(k => k !== 'usage') : ['usage', 'lease'];
        const priorCounters = deriveCounters(fixture.before).counters;
        requireGuard(unaffected.every(k => derived.counters[k] === priorCounters[k]), 'DENIED_ZERO_EFFECT_PROOF_MISSING');
        deniedAttemptEffects.push({ attemptId: attempt.attemptId, counters: zeroCounters() });
      }
      return { kind: 'committed-state-snapshot', projectId: PROJECT_ID, caseId: race.caseId, scopeKey: race.scopeKey,
        tenantId: scope(race.scopeKey).tenantId, observedAt: proof.observedAt, readOnly: true, committed: true, isolation: 'repeatable-read',
        querySha256: proof.querySha256, snapshotSha256: proof.snapshotSha256,
        transactionEvidenceSha256: proof.transactionEvidenceSha256, ...derived, deniedAttemptEffects };
    },
    async restoreRace({ race, signal }) {
      ready(); let evidence;
      if (['seats', 'admissions'].includes(race.kind)) evidence = (await memberships.restore({ signal, caseId: race.caseId })).evidenceSha256;
      else { const proof = await readStore.read('scopeSnapshot', { scopeKey: race.scopeKey }, signal); evidence = hashJson({ retained: proof.snapshotSha256,
        noRetryReleaseDeletion: true, caseId: race.caseId }); }
      for (const participant of fixtures.get(race.caseId)?.trustedParticipants ?? []) {
        const privateValue = trusted.get(participant); if (privateValue) transport.closeConnection(privateValue.handle); trusted.delete(participant);
      }
      return { exactReviewedRestoration: true, restorationSha256: race.restorationSha256, evidenceSha256: evidence, noAcceptanceChanges: true };
    },
    async runInvalidBoundary({ boundary, signal }) {
      ready(); requireGuard(plan.boundaries.some(b => hashJson(b) === hashJson(boundary)), 'BOUNDARY_BINDING_REQUIRED');
      const target = scope('runtime'), population = await sourceCheck(target, signal);
      if (boundary.kind !== '367DayWindow') return { status: 'unsupported-under-reviewed-scope', caseId: boundary.caseId,
        fixturePlanSha256: boundary.fixturePlanSha256, noOperationAttempted: true, existingScopeOnly: true,
        reasonCode: { '10001Rows': 'ROW_FIXTURE_EXCEEDS_REVIEWED_CAPS', '101Groups': 'GROUP_FIXTURE_NOT_REVIEWED',
          '8MiBPlus1Byte': 'OUTPUT_FIXTURE_NOT_REVIEWED' }[boundary.kind], fixtureEvidenceSha256: hashJson({ population: population.snapshotSha256,
          source: INVALID_BOUNDARIES[boundary.kind] }) };
      const before = await readStore.readBatch([{ name: 'scopeSnapshot', args: { scopeKey: 'runtime' } }], signal);
      const start = '2020-01-01', end = new Date(Date.parse(start) + 367 * 86400000).toISOString().slice(0, 10), command = freshId();
      const invalidBody = { ...scoped(target), p_command_id: command,
        p_idempotency_key: command, p_client_timestamp: new Date().toISOString(), p_horizon_start: start, p_horizon_end: end };
      const rejected = await preparationJournal.perform({ caseId: boundary.caseId, scopeKey: 'runtime', action: 'boundary-forecast-rejection',
        intent: { actorId: pick('proposer').actorId, parameters: invalidBody },
        operation: () => rpc(pick('proposer'), '/rest/v1/rpc/freeze_pipeline_forecast', invalidBody, signal) });
      requireGuard(!rejected.ok && rejected.value?.code === '54000' && rejected.value.message === 'LIMIT_EXCEEDED', 'INVALID_BOUNDARY_ZERO_EFFECT_REQUIRED');
      const after = await readStore.readBatch([{ name: 'scopeSnapshot', args: { scopeKey: 'runtime' } }], signal);
      requireGuard(before.querySha256 === boundary.committedQuerySha256 && after.querySha256 === boundary.committedQuerySha256,
        'INVALID_BOUNDARY_ZERO_EFFECT_REQUIRED');
      const oldCounters = deriveCounters(before).counters, counters = deriveCounters(after).counters;
      const committedEffectDelta = Object.fromEntries(COUNTERS.map(key => [key, counters[key] - oldCounters[key]]));
      requireGuard(COUNTERS.every(key => committedEffectDelta[key] === 0), 'INVALID_BOUNDARY_ZERO_EFFECT_REQUIRED');
      return { caseId: boundary.caseId, fixturePlanSha256: boundary.fixturePlanSha256, querySha256: boundary.committedQuerySha256,
        actualLimitRejection: true, code: 'LIMIT_EXCEEDED', responseSha256: rejected.responseSha256, committedEffectDelta,
        committedEvidenceSha256: hashJson({ before, after, transport: rejected.transportEvidenceSha256 }) };
    },
    async readLoadCommitted({ signal }) {
      ready(); const proof = await readStore.read('loadLedgers', {}, signal), row = proof.rows[0];
      requireGuard(proof.rows.length === 1, 'COMMITTED_LOAD_POPULATION_REQUIRED'); loadFrom ??= proof.observedAt;
      return { kind: 'committed-load-population-snapshot', projectId: PROJECT_ID, committed: true, readOnly: true,
        isolation: 'repeatable-read', observedAt: proof.observedAt, querySha256: proof.querySha256, snapshotSha256: proof.snapshotSha256,
        transactionEvidenceSha256: proof.transactionEvidenceSha256, fixturePlanSha256: plan.loadFixturePlanSha256,
        scopeDigestSha256: hashJson(review.syntheticScopes), counters: Object.fromEntries(Object.entries({ forecasts: 'forecasts', receipts: 'receipts',
          audit: 'audit', outbox: 'outbox', modelInvocationRows: 'model_invocation_rows', deliveryAttemptRows: 'delivery_attempt_rows',
          deliveryOutcomeRows: 'delivery_outcome_rows', receiverReceiptRows: 'receiver_receipt_rows', workerTickRows: 'worker_tick_rows' })
          .map(([name, column]) => [name, exactInteger(row[column])])) };
    },
    async readExternalTransportObservation({ window, signal }) {
      ready(); requireGuard(loadFrom && finiteTime(window.startedAt) && finiteTime(window.finishedAt), 'ACTUAL_EXTERNAL_TRANSPORT_OBSERVATION_REQUIRED');
      // Own RPC traces plus DB rows cannot prove all remote workers stayed inactive.
      // A reviewed independent actual transport observer must cover the complete window.
      return privateConfig.observeExternalTransport({ context, window, rpcTraceSha256: hashJson(traces), signal });
    },
    async close() { closed = true; transport.close(); await readStore.close(); }
  });
}
