import fs from 'node:fs/promises';
import { PROJECT_ID, PROJECT_URL, hashJson, RACE_KINDS, freshId } from '../../../../tools/wave5/runtime_contract.mjs';
import { createMembershipFixture, MEMBERSHIP_FIXTURE_SQL } from '../../../../tools/wave5/supabase_membership_fixture.mjs';
import { createPreparationJournal } from '../../../../tools/wave5/preparation_journal.mjs';
import { CASE_READ_RECIPES } from '../../../../tools/wave5/supabase_runtime_provider.mjs';
import { READ_QUERY_SHA256, committedRecipeHash } from '../../../../tools/wave5/supabase_read_store.mjs';
import { createBoundedMembershipFixturePgDriver, FIXTURE_WRITER_ROLE } from './fixture_writer.mjs';

// Only public review files and controlled fake identities are used. Nothing here
// is a real Auth session, private credential, PostgreSQL result or live approval.
export const review = JSON.parse(await fs.readFile(new URL('../complete-app-runtime-review-20261010-r5.json', import.meta.url)));
const approval = JSON.parse(await fs.readFile(new URL('../runtime-owner-decision-20261012-r5.json', import.meta.url)));
export const config = () => ({host: `db.${PROJECT_ID}.supabase.co`, port: 5432, database: 'postgres', user: 'postgres',
  password: 'CONTROLLED_TEST_VALUE_ONLY', ssl: {rejectUnauthorized: true}, application_name: FIXTURE_WRITER_ROLE});
export const deferred = () => { let resolve; const promise = new Promise(value => { resolve = value; }); return {promise, resolve}; };
export function tokenFreeAcknowledgment(record, receipt) {
  // Models the reviewed private sink wrapper: original receipt verification is
  // done in that private wrapper before this token-free allowlisted projection.
  const headers = Object.fromEntries(['kind', 'projectId', 'runtimeBundleSha256', 'planBodySha256', 'sourceSha256',
    'sequence', 'recordId', 'observedAt', 'caseId', 'scopeKey', 'action', 'phase', 'operationId'].map(key => [key, record[key]]));
  const details = record.phase === 'intent' ? structuredClone(record.details)
    : record.phase === 'confirmed' ? {result: {ok: record.details?.result?.ok,
      value: {invitation_id: record.details?.result?.value?.invitation_id},
      transportEvidenceSha256: record.details?.result?.transportEvidenceSha256}}
      : {failureCode: record.details?.failureCode};
  const observation = {...headers, details, sourceRecordSha256: receipt.recordSha256};
  return {observation, acknowledgment: {...receipt, originalRecordHashVerified: receipt.recordSha256 === hashJson(record),
    observationSha256: hashJson(observation)}};
}
export function controlledContext() {
  const providerSha = hashJson('controlled-private-factory-placeholder');
  const plan = {kind: 'wave5-runtime-harness-plan', projectId: PROJECT_ID, url: PROJECT_URL,
    production: false, realBilling: false, runtimeBundleSha256: review.bundleSha256,
    warmupMs: 60000, measuredMs: 300000, maxRunMs: 900000, maximumTimedRequests: 20000,
    maxInflight: 2000, requestsPerSecond: 20, providerCalendarSha256: hashJson('controlled-calendar'),
    postgresDriverSourceSha256: hashJson('controlled-driver'), preparationJournalSourceSha256: hashJson('controlled-durable-sink'),
    cases: RACE_KINDS.map(kind => ({kind, caseId: freshId(), scopeKey: ['seats', 'admissions', 'quota'].includes(kind) ? 'load-001' : 'runtime',
      participants: kind === 'duplicates' ? 100 : kind === 'quota' ? 20 : 2, noExternalSend: true,
      fixturePlanSha256: hashJson([kind, 'fixture']), committedQuerySha256: committedRecipeHash(CASE_READ_RECIPES[kind]),
      preparationSha256: hashJson([kind, 'prepare']), restorationSha256: hashJson([kind, 'restore'])})),
    boundaries: ['10001Rows', '101Groups', '367DayWindow', '8MiBPlus1Byte'].map(kind => ({kind, scopeKey: 'runtime', caseId: freshId(),
      fixturePlanSha256: hashJson([kind, 'fixture']), committedQuerySha256: READ_QUERY_SHA256.scopeSnapshot, expectedCode: 'LIMIT_EXCEEDED'})),
    loadCommittedQuerySha256: READ_QUERY_SHA256.loadLedgers, loadFixturePlanSha256: hashJson('controlled-load'),
    externalObservationSourceSha256: hashJson('controlled-observer')};
  const binding = {runtimeFileSha256: approval.runtimeFileSha256, harnessReviewSha256: hashJson('controlled-review'),
    planSha256: hashJson(plan), planBodySha256: hashJson(plan), privateProviderSha256: providerSha};
  const independentReview = {kind: 'wave5-runtime-harness-independent-preparation-review', result: 'approved-for-existing-bounded-scope',
    projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256,
    harnessReviewSha256: binding.harnessReviewSha256, planSha256: binding.planSha256, privateProviderSha256: providerSha,
    sourceBindingsVerified: true, operationScopeSha256: review.sourceContinuation.unchangedRuntimeOperationScopeSha256,
    sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false};
  binding.independentReviewBodySha256 = hashJson(independentReview);
  const preparation = {kind: 'wave5-runtime-harness-preparation', sourceBindingsVerified: true,
    runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256,
    harnessReviewSha256: binding.harnessReviewSha256, planSha256: binding.planSha256, privateProviderSha256: providerSha,
    independentReview: {result: independentReview.result, path: 'controlled-independent-placeholder.json', sha256: hashJson(independentReview)},
    sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false};
  return {review, approval, plan, binding, independentReview, preparation};
}
export function setup(options = {}) {
  const context = controlledContext(), target = review.syntheticScopes.find(scope => scope.key === 'load-001');
  const authIds = Object.fromEntries(review.accounts.map(actor => [actor.label, freshId()])), roleId = freshId();
  const members = ['approver', 'executor'].map(label => ({id: freshId(), user_id: authIds[label], status: 'active', version: '1'}))
    .sort((a, b) => a.user_id.localeCompare(b.user_id));
  const assignments = members.map(member => ({id: freshId(), membership_id: member.id, role_id: roleId,
    legal_entity_id: target.entityId, branch_id: target.branchId})).sort((a, b) => a.id.localeCompare(b.id));
  const state = {database: {subscription: {id: freshId(), seats: 4, version: '1'}, members, assignments, invitations: []},
    queries: [], configs: [], releases: [], callbacks: 0, active: 0, peak: 0, connected: 0, commits: 0,
    implicitRollbacks: 0, poolEnds: 0, journalRecords: []};
  options.modifyDatabase?.(state.database, authIds, target);
  let backend = 1000; const queue = [], beginStarted = deferred(), acquisitionStarted = deferred();
  class FakePool {
    constructor(poolConfig) { this.options = poolConfig; state.configs.push(poolConfig); }
    on() {}
    get waitingCount() { return queue.length; }
    async connect() {
      if (state.active >= this.options.max) await new Promise(resolve => queue.push(resolve));
      state.active++; state.peak = Math.max(state.peak, state.active); acquisitionStarted.resolve();
      if (options.acquireGate) await options.acquireGate;
      state.connected++; let working = null, released = false;
      const lease = {processID: ++backend, connection: {stream: {encrypted: true, authorized: options.authorized !== false,
        getPeerCertificate: () => ({subject: {CN: options.hostname ?? config().host}, subjectaltname: `DNS:${options.hostname ?? config().host}`})}},
        async query(sql, values = []) {
          state.queries.push({sql, values: structuredClone(values)});
          if (sql === 'BEGIN') { beginStarted.resolve(); if (options.beginGate) await options.beginGate; }
          if (released) throw Error('CONTROLLED_SOCKET_CLOSED');
          if (options.failQuery === sql) throw Error('CONTROLLED_SERVER_SECRET_MUST_BE_REDACTED');
          if (sql === 'BEGIN') { working = structuredClone(state.database); return {command: 'BEGIN', rows: [], rowCount: null}; }
          if (sql === 'ROLLBACK') { working = null; return {command: 'ROLLBACK', rows: [], rowCount: null}; }
          if (sql === 'COMMIT') {
            state.database = working; working = null; state.commits++;
            if (options.loseCommitReply) throw Error('CONTROLLED_COMMIT_REPLY_LOST_SECRET');
            return {command: 'COMMIT', rows: [], rowCount: null};
          }
          if (!working) throw Error('CONTROLLED_TRANSACTION_REQUIRED');
          const response = rows => ({rows: structuredClone(rows), rowCount: rows.length});
          if (sql === MEMBERSHIP_FIXTURE_SQL.subscription) return response([working.subscription]);
          if (sql === MEMBERSHIP_FIXTURE_SQL.memberships) return response(working.members);
          if (sql === MEMBERSHIP_FIXTURE_SQL.assignments) return response(working.assignments);
          if (sql === MEMBERSHIP_FIXTURE_SQL.occupied) return response([{occupied: String(2 + working.members.filter(row => ['active', 'invited'].includes(row.status)).length)}]);
          if (sql === MEMBERSHIP_FIXTURE_SQL.seats) {
            const row = working.subscription;
            if (row.id !== values[2] || row.version !== values[3]) return response([]);
            row.seats = values[1]; row.version = String(BigInt(row.version) + 1n); return response([row]);
          }
          if ([MEMBERSHIP_FIXTURE_SQL.suspend, MEMBERSHIP_FIXTURE_SQL.restoreMember].includes(sql)) {
            const row = working.members.find(row => row.id === values[1] && row.user_id === values[2] && row.version === values[3]);
            if (!row || (sql === MEMBERSHIP_FIXTURE_SQL.suspend ? row.status !== 'active' : !['active', 'suspended'].includes(row.status))) return response([]);
            row.status = sql === MEMBERSHIP_FIXTURE_SQL.suspend ? 'suspended' : 'active'; row.version = String(BigInt(row.version) + 1n);
            return response([{id: row.id}]);
          }
          if (sql === MEMBERSHIP_FIXTURE_SQL.revokeExactUnused) {
            const rows = working.invitations.filter(row => values[1].includes(row.id) && row.status === 'pending'
              && row.tenant_id === values[0] && row.invited_by === values[2] && values[3].includes(row.email));
            for (const row of rows) row.status = 'revoked'; return response(rows.map(row => ({id: row.id})));
          }
          throw Error('CONTROLLED_UNRECOGNIZED_SQL');
        }, release(destroy) {
          if (released) throw Error('CONTROLLED_DOUBLE_RELEASE');
          released = true; state.releases.push(destroy);
          if (working) state.implicitRollbacks++;
          working = null; state.active--; queue.shift()?.();
        }};
      return lease;
    }
    async end() { state.poolEnds++; }
  }
  const driver = createBoundedMembershipFixturePgDriver({executionContext: context, authIds,
    credentialProvider: options.credentialProvider ?? (async () => { state.callbacks++; return config(); }),
    PoolClass: FakePool, maximumConnections: options.maximumConnections ?? 2,
    acquireTimeoutMs: options.acquireTimeoutMs ?? 10000, statementTimeoutMs: options.statementTimeoutMs ?? 25000});
  const receipt = record => ({durable: true, appendOnly: true, recordSha256: hashJson(record), storageEvidenceSha256: hashJson(['controlled-durable-ack', record])});
  const journal = createPreparationJournal({projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256,
    planBodySha256: context.binding.planBodySha256, sourceSha256: context.plan.preparationJournalSourceSha256,
    cases: [...context.plan.cases, ...context.plan.boundaries], appendPreparationEvidence: async record => {
      state.journalRecords.push(record); await options.beforeAcknowledge?.(record);
      const acknowledged = receipt(record);
      if (record.action === 'rpc-create-invitation') {
        const projected = tokenFreeAcknowledgment(record, acknowledged);
        driver.observeInvitationJournalRecord(projected.observation, projected.acknowledgment);
      }
      return acknowledged;
    }});
  const fixture = createMembershipFixture({executionContext: context, authIds, PgClient: driver.PgClient,
    databaseConfig: config(), preparationJournal: journal});
  const race = kind => context.plan.cases.find(row => row.kind === kind);
  const run = (action, kind = 'seats', controller = new AbortController()) => driver.runWithSignal(controller.signal,
    () => fixture[action]({signal: controller.signal, caseId: race(kind).caseId}), {caseId: race(kind).caseId, action});
  async function createInvitation(label, kind = 'seats') {
    const id = freshId(), actor = review.accounts.find(actor => actor.label === label), caseId = race(kind).caseId;
    const result = await journal.perform({caseId, scopeKey: target.key, action: 'rpc-create-invitation',
      intent: {actorId: authIds['billing-admin'], route: '/rest/v1/rpc/create_invitation', parameters: {
        p_tenant_id: target.tenantId, p_email: actor.email, p_role_id: roleId, p_legal_entity_id: target.entityId,
        p_branch_id: target.branchId, p_expires_in_hours: 1}}, operation: async () => {
        state.database.invitations.push({id, tenant_id: target.tenantId, email: actor.email, invited_by: authIds['billing-admin'], status: 'pending'});
        return {ok: true, value: {invitation_id: id, token: 'c'.repeat(64)}, transportEvidenceSha256: hashJson('controlled-invitation-transport')};
      }});
    fixture.recordReturnedInvitation(result.value.invitation_id); return id;
  }
  const observe = (record, acknowledged = receipt(record)) => {
    const projected = tokenFreeAcknowledgment(record, acknowledged);
    return driver.observeInvitationJournalRecord(projected.observation, projected.acknowledgment);
  };
  return {context, authIds, target, roleId, state, FakePool, driver, fixture, journal, receipt, observe,
    race, run, createInvitation, beginStarted, acquisitionStarted};
}
export async function beginState(fixture) {
  const {driver, race, target, authIds} = fixture, controller = new AbortController();
  return driver.runWithSignal(controller.signal, async () => {
    const client = new driver.PgClient(config()); await client.connect(); await client.query('BEGIN');
    await client.query(MEMBERSHIP_FIXTURE_SQL.subscription, [target.tenantId]);
    await client.query(MEMBERSHIP_FIXTURE_SQL.memberships, [target.tenantId, [authIds.approver, authIds.executor]]);
    await client.query(MEMBERSHIP_FIXTURE_SQL.assignments, [target.tenantId, [authIds.approver, authIds.executor]]);
    return client;
  }, {caseId: race('seats').caseId, action: 'prepare'});
}
