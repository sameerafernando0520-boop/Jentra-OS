import crypto from 'node:crypto';
import tls from 'node:tls';
import { AsyncLocalStorage } from 'node:async_hooks';
import { Pool } from 'pg';
import { PROJECT_ID, hashBytes, hashJson, isUuid, isSha, immutableJson, safeCode,
  reviewedExecutionContext } from '../../../../tools/wave5/runtime_contract.mjs';
import { snapshotPrivateDatabaseConfig } from '../../../../tools/wave5/supabase_read_store.mjs';
import { MEMBERSHIP_FIXTURE_SQL } from '../../../../tools/wave5/supabase_membership_fixture.mjs';

export const FIXTURE_WRITER_ROLE = 'jentra-wave5-exact-new-membership-fixture';
export class FixtureWriterError extends Error {
  constructor(code) { super(code); this.name = 'FixtureWriterError'; this.code = code; }
}
const must = (value, code) => { if (!value) throw new FixtureWriterError(code); };
const CONTROL = new Set(['BEGIN', 'COMMIT', 'ROLLBACK']);
const SQL_NAMES = new Map(Object.entries(MEMBERSHIP_FIXTURE_SQL).map(([name, sql]) => [sql, name]));
const version = value => typeof value === 'string' && /^(0|[1-9][0-9]{0,18})$/.test(value)
  && BigInt(value) <= 9223372036854775807n;
const sameSet = (a, b) => Array.isArray(a) && a.length === b.length
  && new Set(a).size === a.length && a.every(item => b.includes(item));
const equalTarget = (a, b) => ['host', 'port', 'database', 'user', 'password'].every(key => a[key] === b[key])
  && hashJson(Object.fromEntries(Object.entries(a.ssl).filter(([key]) => key !== 'passphrase')))
    === hashJson(Object.fromEntries(Object.entries(b.ssl).filter(([key]) => key !== 'passphrase')))
  && a.ssl.passphrase === b.ssl.passphrase;
const ownKeys = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const signalValid = signal => signal instanceof AbortSignal;

// This is a separate write policy, not an extension of the read-only driver.
// Import, factory creation, operation wrapping and PgClient construction perform
// no credential read, SQL or network I/O. The current public fixture is unchanged.
export function createBoundedMembershipFixturePgDriver({ executionContext, authIds, credentialProvider,
  PoolClass = Pool, maximumConnections = 2, acquireTimeoutMs = 10000, statementTimeoutMs = 25000 }) {
  let context;
  try { context = reviewedExecutionContext(executionContext); }
  catch { throw new FixtureWriterError('FIXTURE_REVIEW_CONTEXT_INVALID'); }
  const { review, plan, binding } = context;
  const target = review.syntheticScopes.find(scope => scope.key === 'load-001');
  const labels = ['proposer', 'approver', 'executor', 'billing-admin', 'operator', 'foreign-member'];
  must(ownKeys(authIds, labels) && labels.every(label => {
    const descriptor = Object.getOwnPropertyDescriptor(authIds, label);
    return descriptor && !descriptor.get && !descriptor.set && isUuid(descriptor.value);
  })
    && new Set(Object.values(authIds)).size === 6, 'FIXTURE_EXACT_SIX_AUTH_IDS_REQUIRED');
  const actors = immutableJson(authIds), participants = [actors.approver, actors.executor];
  const emails = ['approver', 'executor'].map(label => review.accounts.find(actor => actor.label === label)?.email);
  must(target && isUuid(target.tenantId) && emails.every(email => typeof email === 'string'), 'FIXTURE_REVIEW_CONTEXT_INVALID');
  must(typeof credentialProvider === 'function' && typeof PoolClass === 'function', 'FIXTURE_PRIVATE_DATABASE_CALLBACK_REQUIRED');
  must(Number.isInteger(maximumConnections) && maximumConnections >= 1 && maximumConnections <= 8,
    'FIXTURE_BOUNDED_POOL_REQUIRED');
  must(Number.isInteger(acquireTimeoutMs) && acquireTimeoutMs > 0 && acquireTimeoutMs <= 10000
    && Number.isInteger(statementTimeoutMs) && statementTimeoutMs > 0 && statementTimeoutMs <= 25000,
    'FIXTURE_BOUNDED_TIMEOUT_REQUIRED');
  const operationStorage = new AsyncLocalStorage();
  const cases = new Map(plan.cases.filter(item => item.scopeKey === 'load-001'
    && ['seats', 'admissions'].includes(item.kind)).map(item => [item.caseId, item]));
  must(cases.size === 2, 'FIXTURE_REVIEW_CONTEXT_INVALID');
  let pool = null, privateTarget = null, initialising = null, closing = null, closed = false, failed = false;
  let uncertainCommit = false, invitationUncertain = false, baseline = null;
  let activeConnections = 0, peakConnections = 0, actualConnections = 0;
  const clients = new Set(), preparedCases = new Set(), restoredCases = new Set(), pendingInvitations = new Map(), ownedInvitations = new Map();
  const invitationSlots = new Map();
  const healthy = () => {
    must(!uncertainCommit, 'FIXTURE_UNCERTAIN_COMMIT_REQUIRES_REVIEW');
    must(!invitationUncertain, 'FIXTURE_UNCERTAIN_INVITATION_REQUIRES_REVIEW');
    must(!closed && !failed, 'FIXTURE_DRIVER_CLOSED_OR_FAILED');
  };
  const deadline = (promise, milliseconds, signal, timeoutCode, lateValue) => new Promise((resolve, reject) => {
    let settled = false;
    const cleanup = () => { clearTimeout(timer); signal.removeEventListener('abort', abort); };
    const finish = (callback, value) => { if (!settled) { settled = true; cleanup(); callback(value); } };
    const abort = () => finish(reject, new FixtureWriterError('FIXTURE_OPERATION_ABORTED'));
    const timer = setTimeout(() => finish(reject, new FixtureWriterError(timeoutCode)), milliseconds);
    signal.addEventListener('abort', abort, {once: true});
    Promise.resolve(promise).then(value => {
      if (settled) { try { lateValue?.(value); } catch {} }
      else finish(resolve, value);
    }, error => finish(reject, error));
    if (signal.aborted) abort();
  });
  const snapshotConfig = config => {
    try {
      must(config && ['host', 'database', 'user', 'password', 'ssl'].every(key => Object.hasOwn(config, key))
        && Object.values(Object.getOwnPropertyDescriptors(config)).every(value => !value.get && !value.set)
        && config.ssl && Object.values(Object.getOwnPropertyDescriptors(config.ssl)).every(value => !value.get && !value.set),
        'FIXTURE_EXACT_DATABASE_TARGET_REQUIRED');
      return snapshotPrivateDatabaseConfig(config);
    }
    catch { throw new FixtureWriterError('FIXTURE_EXACT_DATABASE_TARGET_REQUIRED'); }
  };
  async function initialise(requested, signal) {
    healthy();
    if (!initialising) initialising = (async () => {
      try {
        const credentials = await deadline(Promise.resolve().then(() => credentialProvider()),
          acquireTimeoutMs, signal, 'FIXTURE_PRIVATE_DATABASE_CONFIG_TIMEOUT');
        privateTarget = snapshotConfig(credentials); healthy();
        must(!signal.aborted && equalTarget(requested, privateTarget), 'FIXTURE_PRIVATE_DATABASE_TARGET_DRIFT');
        must(!privateTarget.ssl.minVersion || ['TLSv1.2', 'TLSv1.3'].includes(privateTarget.ssl.minVersion),
          'FIXTURE_TLS_MINIMUM_VERSION_REQUIRED');
        pool = new PoolClass({...snapshotConfig(privateTarget), ssl: {...snapshotConfig(privateTarget).ssl,
          minVersion: privateTarget.ssl.minVersion ?? 'TLSv1.2'}, max: maximumConnections,
          connectionTimeoutMillis: acquireTimeoutMs, idleTimeoutMillis: 10000,
          statement_timeout: statementTimeoutMs, query_timeout: statementTimeoutMs,
          idle_in_transaction_session_timeout: statementTimeoutMs, lock_timeout: 5000,
          application_name: FIXTURE_WRITER_ROLE, sslnegotiation: 'postgres', client_encoding: 'UTF8',
          options: '', keepAlive: true, enableChannelBinding: true});
        pool.on?.('error', () => { failed = true; for (const client of clients) void client.end(true).catch(() => {}); });
      } catch (error) {
        failed = true;
        const permitted = new Set(['FIXTURE_PRIVATE_DATABASE_CONFIG_TIMEOUT', 'FIXTURE_OPERATION_ABORTED',
          'FIXTURE_EXACT_DATABASE_TARGET_REQUIRED', 'FIXTURE_PRIVATE_DATABASE_TARGET_DRIFT',
          'FIXTURE_TLS_MINIMUM_VERSION_REQUIRED', 'FIXTURE_DRIVER_CLOSED_OR_FAILED']);
        throw new FixtureWriterError(error instanceof FixtureWriterError && permitted.has(error.code)
          ? error.code : 'FIXTURE_PRIVATE_DATABASE_CONFIG_UNAVAILABLE');
      }
    })();
    await initialising; healthy();
    must(equalTarget(requested, privateTarget), 'FIXTURE_PRIVATE_DATABASE_TARGET_DRIFT');
    return pool;
  }
  function runWithSignal(signal, callback, operation) {
    healthy();
    must(signalValid(signal) && !signal.aborted && typeof callback === 'function', 'FIXTURE_OPERATION_SIGNAL_REQUIRED');
    must(cases.has(operation?.caseId) && ['prepare', 'restore'].includes(operation?.action), 'FIXTURE_REVIEWED_OPERATION_REQUIRED');
    return operationStorage.run(Object.freeze({signal, caseId: operation.caseId, action: operation.action}), callback);
  }
  function observeInvitationJournalRecord(record, receipt) {
    if (record?.action !== 'rpc-create-invitation') return Object.freeze({ignored: true});
    healthy();
    // The source-reviewed private sink verifies the original raw record digest,
    // then supplies this minimal token-free observation and its digest. No raw
    // invitation token or full confirmed record enters or is retained here.
    must(ownKeys(record, ['kind', 'projectId', 'runtimeBundleSha256', 'planBodySha256', 'sourceSha256',
      'sequence', 'recordId', 'observedAt', 'caseId', 'scopeKey', 'action', 'phase', 'operationId', 'details', 'sourceRecordSha256'])
      && record.kind === 'wave5-private-preparation-journal-record' && record.projectId === PROJECT_ID
      && record.runtimeBundleSha256 === review.bundleSha256 && record.planBodySha256 === binding.planBodySha256
      && record.sourceSha256 === plan.preparationJournalSourceSha256 && record.scopeKey === target.key
      && cases.has(record.caseId) && isUuid(record.operationId) && isUuid(record.recordId)
      && Number.isSafeInteger(record.sequence) && record.sequence > 0 && Number.isFinite(Date.parse(record.observedAt))
      && isSha(record.sourceRecordSha256) && receipt?.originalRecordHashVerified === true
      && receipt?.durable === true && receipt.appendOnly === true && receipt.recordSha256 === record.sourceRecordSha256
      && receipt.observationSha256 === hashJson(record)
      && isSha(receipt.storageEvidenceSha256), 'FIXTURE_ACKNOWLEDGED_INVITATION_RECORD_REQUIRED');
    if (record.phase === 'uncertain') {
      must(ownKeys(record.details, ['failureCode']) && safeCode(record.details.failureCode) === record.details.failureCode,
        'FIXTURE_TOKEN_FREE_INVITATION_OBSERVATION_REQUIRED');
      invitationUncertain = true; return Object.freeze({adopted: false, uncertain: true});
    }
    must(preparedCases.has(record.caseId) && !restoredCases.has(record.caseId) && baseline, 'FIXTURE_COMMITTED_PREPARATION_REQUIRED');
    if (record.phase === 'intent') {
      const details = record.details, parameters = details?.parameters;
      const actor = review.accounts.find(item => ['approver', 'executor'].includes(item.label) && item.email === parameters?.p_email);
      const race = cases.get(record.caseId), slot = `${record.caseId}/${actor?.label}`;
      must(ownKeys(details, ['actorId', 'route', 'parameters'])
        && details?.actorId === actors['billing-admin'] && details.route === '/rest/v1/rpc/create_invitation'
        && ownKeys(parameters, ['p_tenant_id', 'p_email', 'p_role_id', 'p_legal_entity_id', 'p_branch_id', 'p_expires_in_hours'])
        && parameters.p_tenant_id === target.tenantId && parameters.p_legal_entity_id === target.entityId
        && parameters.p_branch_id === target.branchId && parameters.p_role_id === baseline.roleId
        && parameters.p_expires_in_hours === 1 && actor && (race.kind === 'seats' || actor.label === 'approver')
        && !pendingInvitations.has(record.operationId) && !invitationSlots.has(slot), 'FIXTURE_EXACT_INVITATION_SCOPE_REQUIRED');
      pendingInvitations.set(record.operationId, {caseId: record.caseId, label: actor.label, slot});
      invitationSlots.set(slot, record.operationId);
      return Object.freeze({adopted: false, intentRecorded: true});
    }
    must(record.phase === 'confirmed', 'FIXTURE_ACKNOWLEDGED_INVITATION_RECORD_REQUIRED');
    const intent = pendingInvitations.get(record.operationId), result = record.details?.result;
    const id = result?.value?.invitation_id;
    must(ownKeys(record.details, ['result']) && ownKeys(result, ['ok', 'value', 'transportEvidenceSha256'])
      && ownKeys(result.value, ['invitation_id']) && intent && intent.caseId === record.caseId && result?.ok === true && isUuid(id)
      && isSha(result.transportEvidenceSha256) && !ownedInvitations.has(id) && ownedInvitations.size < 3,
      'FIXTURE_RETURNED_INVITATION_ID_REQUIRED');
    ownedInvitations.set(id, intent); pendingInvitations.delete(record.operationId);
    return Object.freeze({adopted: true, ownedInvitationCount: ownedInvitations.size});
  }
  class PgClient {
    #config; #operation; #lease = null; #ended = false; #connecting = null; #poisoned = false;
    #transaction = false; #serial = Promise.resolve(); #pendingQueries = 0; #abort;
    #state = {}; #suspended = new Set(); #restored = new Set(); #capWritten = false;
    #revoked = false; #occupied = null; #restoreReadback = false;
    #mutationEpoch = 0; #readEpoch = {};
    #lifecycle = new AbortController(); #transportSignal;
    constructor(config) {
      healthy();
      const role = config && Object.getOwnPropertyDescriptor(config, 'application_name');
      must(role && !role.get && !role.set && role.value === FIXTURE_WRITER_ROLE,
        'FIXTURE_EXPLICIT_WRITER_ROLE_REQUIRED');
      this.#operation = operationStorage.getStore();
      must(this.#operation && signalValid(this.#operation.signal) && !this.#operation.signal.aborted,
        'FIXTURE_OPERATION_SIGNAL_REQUIRED');
      this.#transportSignal = AbortSignal.any([this.#operation.signal, this.#lifecycle.signal]);
      this.#config = snapshotConfig(config); clients.add(this);
      this.#abort = () => { void this.end(true).catch(() => {}); };
    }
    get connection() { return this.#lease?.connection; }
    get processID() { return this.#lease?.processID; }
    async connect() {
      healthy();
      must(!this.#ended && !this.#lease && !this.#connecting, 'FIXTURE_CONNECTION_LIFECYCLE_INVALID');
      const {signal} = this.#operation;
      must(!signal.aborted, 'FIXTURE_OPERATION_ABORTED');
      signal.addEventListener('abort', this.#abort, {once: true});
      this.#connecting = (async () => {
        let acquired = null;
        try {
          const targetPool = await initialise(this.#config, this.#transportSignal);
          acquired = await deadline(targetPool.connect(), acquireTimeoutMs, this.#transportSignal,
            'FIXTURE_CONNECT_TIMEOUT', late => late?.release(true));
          healthy(); must(!this.#ended && !signal.aborted, 'FIXTURE_OPERATION_ABORTED');
          const stream = acquired.connection?.stream;
          must(stream?.encrypted === true && stream.authorized === true && !stream.authorizationError
            && typeof stream.getPeerCertificate === 'function', 'FIXTURE_TLS_NOT_VERIFIED');
          const certificate = stream.getPeerCertificate();
          must(certificate && Object.keys(certificate).length > 0
            && !tls.checkServerIdentity(this.#config.host, certificate), 'FIXTURE_TLS_HOSTNAME_MISMATCH');
          must(Number.isSafeInteger(acquired.processID) && acquired.processID > 0, 'FIXTURE_ACTUAL_BACKEND_REQUIRED');
          this.#lease = acquired; acquired = null;
          this.connectionId = `pg:${this.#lease.processID}:${crypto.randomUUID()}`;
          actualConnections++; activeConnections++; peakConnections = Math.max(peakConnections, activeConnections);
        } catch (error) {
          try { acquired?.release(true); } catch {}
          const permitted = new Set(['FIXTURE_TLS_NOT_VERIFIED', 'FIXTURE_TLS_HOSTNAME_MISMATCH',
            'FIXTURE_ACTUAL_BACKEND_REQUIRED', 'FIXTURE_OPERATION_ABORTED', 'FIXTURE_CONNECT_TIMEOUT',
            'FIXTURE_PRIVATE_DATABASE_TARGET_DRIFT', 'FIXTURE_PRIVATE_DATABASE_CONFIG_TIMEOUT',
            'FIXTURE_PRIVATE_DATABASE_CONFIG_UNAVAILABLE', 'FIXTURE_EXACT_DATABASE_TARGET_REQUIRED',
            'FIXTURE_TLS_MINIMUM_VERSION_REQUIRED', 'FIXTURE_DRIVER_CLOSED_OR_FAILED']);
          throw new FixtureWriterError(error instanceof FixtureWriterError && permitted.has(error.code)
            ? error.code : 'FIXTURE_CONNECT_FAILED');
        }
      })();
      return this.#connecting;
    }
    #parameters(sql, values) {
      must(typeof sql === 'string' && (CONTROL.has(sql) || SQL_NAMES.has(sql)) && Array.isArray(values),
        'FIXTURE_EXACT_SOURCE_SQL_REQUIRED');
      if (CONTROL.has(sql)) { must(values.length === 0, 'FIXTURE_EXACT_PARAMETERS_REQUIRED'); return []; }
      const name = SQL_NAMES.get(sql);
      const count = {subscription: 1, memberships: 2, assignments: 2, occupied: 1,
        suspend: 4, seats: 4, restoreMember: 4, revokeExactUnused: 4}[name];
      must(values.length === count && values[0] === target.tenantId, 'FIXTURE_EXACT_TENANT_REQUIRED');
      if (['memberships', 'assignments'].includes(name))
        must(sameSet(values[1], participants), 'FIXTURE_EXACT_ACTOR_PAIR_REQUIRED');
      if (['suspend', 'restoreMember'].includes(name))
        must(isUuid(values[1]) && participants.includes(values[2]) && version(values[3]), 'FIXTURE_EXACT_MEMBER_REQUIRED');
      if (name === 'seats') must([3, 4].includes(values[1]) && isUuid(values[2]) && version(values[3]), 'FIXTURE_REVIEWED_SEATS_REQUIRED');
      if (name === 'revokeExactUnused') must(ownedInvitations.size > 0
        && sameSet(values[1], [...ownedInvitations.keys()]) && values[2] === actors['billing-admin']
        && sameSet(values[3], emails), 'FIXTURE_EXACT_RETURNED_INVITATIONS_REQUIRED');
      return values.map(value => Array.isArray(value) ? [...value] : value);
    }
    #bindState() {
      const {subscription, memberships, assignments} = this.#state;
      must(subscription && memberships && assignments, 'FIXTURE_LOCKED_BASELINE_REQUIRED');
      if (!baseline) {
        must(this.#operation.action === 'prepare' && subscription.seats === 4
          && memberships.every(row => row.status === 'active'), 'FIXTURE_ORIGINAL_FOUR_SEATS_REQUIRED');
        baseline = immutableJson({subscriptionId: subscription.id, seats: 4, roleId: assignments[0].role_id,
          members: memberships.map(({id, user_id}) => ({id, user_id})), assignmentsHash: hashJson(assignments)});
      }
      must(subscription.id === baseline.subscriptionId && memberships.every(row =>
        baseline.members.some(original => original.id === row.id && original.user_id === row.user_id))
        && hashJson(assignments) === baseline.assignmentsHash, 'FIXTURE_ORIGINAL_IDENTITIES_DRIFT');
    }
    async #before(sql, values) {
      const name = SQL_NAMES.get(sql), action = this.#operation.action;
      if (sql === 'BEGIN') {
        must(!this.#transaction && !restoredCases.has(this.#operation.caseId)
          && (action === 'prepare' ? !preparedCases.has(this.#operation.caseId) : preparedCases.has(this.#operation.caseId)),
          'FIXTURE_TRANSACTION_STATE_INVALID');
      }
      else must(this.#transaction, 'FIXTURE_TRANSACTION_REQUIRED');
      if (sql === 'COMMIT') {
        must(this.#capWritten && (action === 'prepare' ? this.#suspended.size === 2 && this.#occupied === 2
          : this.#restored.size === 2 && this.#restoreReadback && this.#occupied === 4), 'FIXTURE_COMPLETE_ACTION_REQUIRED');
        must(!ownedInvitations.size || this.#revoked, 'FIXTURE_UNUSED_INVITATION_REVOCATION_REQUIRED');
      }
      if (['suspend', 'seats', 'restoreMember', 'revokeExactUnused'].includes(name)) this.#bindState();
      if (['suspend', 'restoreMember'].includes(name)) {
        const row = this.#state.memberships.find(item => item.id === values[1] && item.user_id === values[2]);
        must(row && row.version === values[3], 'FIXTURE_EXACT_MEMBER_VERSION_REQUIRED');
        if (name === 'suspend') must(action === 'prepare' && this.#state.subscription.seats === 4
          && row.status === 'active' && !this.#suspended.has(row.id) && !this.#capWritten, 'FIXTURE_PREPARATION_ORDER_REQUIRED');
        else must(action === 'restore' && this.#capWritten && ['active', 'suspended'].includes(row.status)
          && !this.#restored.has(row.id), 'FIXTURE_RESTORATION_ORDER_REQUIRED');
      }
      if (name === 'seats') {
        must(values[2] === this.#state.subscription.id && values[3] === this.#state.subscription.version
          && !this.#capWritten, 'FIXTURE_EXACT_SUBSCRIPTION_VERSION_REQUIRED');
        must(action === 'prepare' ? values[1] === 3 && this.#suspended.size === 2 && this.#occupied === 2
          : values[1] === 4 && this.#suspended.size === 0, 'FIXTURE_SEAT_TRANSITION_ORDER_REQUIRED');
        if (action === 'restore' && this.#state.subscription.seats === 2) {
          must(cases.get(this.#operation.caseId).kind === 'admissions'
            && this.#state.memberships.every(row => row.status === 'suspended'), 'FIXTURE_ADMISSIONS_RESULT_REQUIRED');
          // The reviewed activation winner leaves cap=2 and occupied=2. Verify
          // that observed outcome using the same bounded, tenant-exact read
          // before raising it; this does not add a DML or accept the race result.
          const occupied = await deadline(this.#lease.query(MEMBERSHIP_FIXTURE_SQL.occupied, [target.tenantId]),
            statementTimeoutMs, this.#transportSignal, 'FIXTURE_QUERY_TIMEOUT');
          must(!this.#ended && occupied?.rows?.length === 1 && occupied.rows[0].occupied === '2',
            'FIXTURE_ADMISSIONS_RESULT_REQUIRED');
        }
      }
      if (name === 'revokeExactUnused') must(this.#capWritten && !this.#revoked
        && (action === 'prepare' || this.#restored.size === 2), 'FIXTURE_INVITATION_REVOCATION_ORDER_REQUIRED');
    }
    #after(sql, values, result) {
      const name = SQL_NAMES.get(sql), rows = result?.rows;
      must(Array.isArray(rows), 'FIXTURE_RESULT_SHAPE_INVALID');
      if (CONTROL.has(sql)) {
        must(result.command === sql, 'FIXTURE_CONTROL_RESULT_INVALID');
        if (sql === 'BEGIN') this.#transaction = true;
        else { this.#transaction = false; if (sql === 'COMMIT')
          (this.#operation.action === 'prepare' ? preparedCases : restoredCases).add(this.#operation.caseId); }
        return;
      }
      if (name === 'subscription') {
        const caps = this.#operation.action === 'prepare' ? [this.#capWritten ? 3 : 4]
          : this.#capWritten ? [4] : cases.get(this.#operation.caseId).kind === 'admissions' ? [2, 3] : [3];
        must(rows.length === 1 && isUuid(rows[0].id) && caps.includes(rows[0].seats) && version(rows[0].version), 'FIXTURE_SUBSCRIPTION_STATE_INVALID');
        this.#state.subscription = immutableJson(rows[0]);
        this.#readEpoch.subscription = this.#mutationEpoch;
      } else if (name === 'memberships') {
        must(rows.length === 2 && new Set(rows.map(row => row.id)).size === 2 && sameSet(rows.map(row => row.user_id), participants)
          && rows.every(row => isUuid(row.id) && ['active', 'suspended'].includes(row.status) && version(row.version)), 'FIXTURE_MEMBERSHIP_STATE_INVALID');
        this.#state.memberships = immutableJson(rows);
        this.#readEpoch.memberships = this.#mutationEpoch;
      } else if (name === 'assignments') {
        must(this.#state.memberships && rows.length === 2 && new Set(rows.map(row => row.id)).size === 2
          && sameSet(rows.map(row => row.membership_id), this.#state.memberships.map(row => row.id))
          && new Set(rows.map(row => row.role_id)).size === 1 && rows.every(row => isUuid(row.id) && isUuid(row.role_id)
            && row.legal_entity_id === target.entityId && row.branch_id === target.branchId), 'FIXTURE_ASSIGNMENT_SCOPE_INVALID');
        this.#state.assignments = immutableJson(rows); this.#bindState();
        this.#readEpoch.assignments = this.#mutationEpoch;
        if (this.#operation.action === 'restore' && this.#restored.size === 2 && this.#capWritten)
          this.#restoreReadback = this.#state.subscription.seats === 4 && this.#state.memberships.every(row => row.status === 'active')
            && ['subscription', 'memberships', 'assignments'].every(key => this.#readEpoch[key] === this.#mutationEpoch);
      } else if (name === 'occupied') {
        must(rows.length === 1 && /^(2|3|4)$/.test(rows[0].occupied), 'FIXTURE_OCCUPANCY_STATE_INVALID');
        this.#occupied = Number(rows[0].occupied);
      } else if (name === 'seats') {
        must(result.rowCount === 1 && rows.length === 1 && rows[0].id === values[2] && rows[0].seats === values[1]
          && version(rows[0].version) && BigInt(rows[0].version) > BigInt(values[3]), 'FIXTURE_SUBSCRIPTION_WRITE_MISMATCH');
        this.#capWritten = true;
        this.#mutationEpoch++;
      } else if (name === 'suspend' || name === 'restoreMember') {
        must(result.rowCount === 1 && rows.length === 1 && rows[0].id === values[1], 'FIXTURE_MEMBERSHIP_WRITE_MISMATCH');
        (name === 'suspend' ? this.#suspended : this.#restored).add(values[1]);
        this.#mutationEpoch++;
      } else if (name === 'revokeExactUnused') {
        must(Number.isInteger(result.rowCount) && result.rowCount === rows.length && rows.length <= values[1].length
          && rows.every(row => ownedInvitations.has(row.id)) && new Set(rows.map(row => row.id)).size === rows.length,
          'FIXTURE_INVITATION_WRITE_MISMATCH'); this.#revoked = true; this.#mutationEpoch++;
      }
    }
    async query(sql, values = []) {
      const parameters = this.#parameters(sql, values);
      healthy(); must(this.#lease && !this.#ended && !this.#poisoned, 'FIXTURE_CONNECTION_NOT_READY');
      // Increment before queueing: ending a connection during a queued/pending
      // BEGIN destroys the lease even before BEGIN has returned successfully.
      this.#pendingQueries++;
      const pending = this.#serial.then(async () => {
        healthy(); must(this.#lease && !this.#ended && !this.#poisoned && !this.#operation.signal.aborted,
          'FIXTURE_CONNECTION_NOT_READY');
        let dispatched = false;
        try {
          await this.#before(sql, parameters);
          dispatched = true;
          const result = await deadline(this.#lease.query(sql, parameters), statementTimeoutMs, this.#transportSignal,
            'FIXTURE_QUERY_TIMEOUT');
          must(!this.#ended && this.#lease && !this.#operation.signal.aborted, 'FIXTURE_OPERATION_ABORTED');
          this.#after(sql, parameters, result); return result;
        } catch {
          this.#poisoned = true;
          if (sql === 'COMMIT' && dispatched) uncertainCommit = true;
          try { await this.end(true); } catch {}
          throw new FixtureWriterError(sql === 'COMMIT' && dispatched ? 'FIXTURE_UNCERTAIN_COMMIT_REQUIRES_REVIEW' : 'FIXTURE_QUERY_FAILED');
        }
      });
      this.#serial = pending.catch(() => {});
      try { return await pending; } finally { this.#pendingQueries--; }
    }
    async end(destroy = false) {
      if (this.#ended) return;
      this.#ended = true; this.#lifecycle.abort(); this.#operation.signal.removeEventListener('abort', this.#abort); clients.delete(this);
      const lease = this.#lease; this.#lease = null;
      if (lease) { activeConnections--;
        try { lease.release(destroy || this.#poisoned || this.#transaction || this.#pendingQueries > 0); }
        catch { throw new FixtureWriterError('FIXTURE_CONNECTION_CLOSE_FAILED'); }
      }
    }
  }
  return Object.freeze({PgClient, runWithSignal, observeInvitationJournalRecord,
    limits: Object.freeze({maximumConnections, acquireTimeoutMs, statementTimeoutMs}),
    sqlBindings: immutableJson(Object.fromEntries(Object.entries(MEMBERSHIP_FIXTURE_SQL).map(([name, sql]) => [name, hashBytes(sql)]))),
    metrics: () => Object.freeze({actualConnections, activeConnections, peakConnections,
      waitingConnections: pool?.waitingCount ?? 0, driverFailed: failed, uncertainCommit, invitationUncertain}),
    close() {
      if (!closing) closing = (async () => {
        closed = true; const ended = await Promise.allSettled([...clients].map(client => client.end(true)));
        if (initialising) await initialising.catch(() => {});
        let closeFailed = ended.some(result => result.status === 'rejected');
        try { if (pool) await pool.end(); } catch { closeFailed = true; }
        if (closeFailed) throw new FixtureWriterError('FIXTURE_DRIVER_CLOSE_FAILED');
      })();
      return closing;
    }
  });
}
