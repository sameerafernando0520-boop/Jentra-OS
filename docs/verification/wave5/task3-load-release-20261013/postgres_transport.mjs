import crypto from 'node:crypto';
import tls from 'node:tls';
import { Pool } from 'pg';
import { PROJECT_ID, hashBytes, hashJson, isUuid } from '../../../../tools/wave5/runtime_contract.mjs';
import { READ_QUERIES, snapshotPrivateDatabaseConfig } from '../../../../tools/wave5/supabase_read_store.mjs';

export const PINNED_PG_VERSION = '8.23.1';
export class PrivatePgError extends Error {
  constructor(code) { super(code); this.name = 'PrivatePgError'; this.code = code; }
}
const must = (ok, code) => { if (!ok) throw new PrivatePgError(code); };
export const CAPACITY_SQL = `SELECT statement_timestamp() AS observed_at,
current_setting('server_version') AS postgres_version,
current_setting('max_connections')::int AS max_connections,
current_setting('shared_buffers') AS shared_buffers,
pg_database_size(current_database())::text AS database_bytes,
(SELECT count(*)::int FROM pg_stat_activity) AS server_connections,
(SELECT count(*)::int FROM pg_stat_activity WHERE state='active') AS active_queries,
(SELECT count(*)::int FROM pg_stat_activity WHERE wait_event_type='Lock') AS lock_waiters,
(SELECT count(*)::int FROM supabase_migrations.schema_migrations) AS installed_migrations,
(SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api') AS api_functions,
(SELECT count(*)::int FROM auth.sessions WHERE user_id=ANY($1::uuid[])) AS reviewed_actor_session_rows,
(SELECT count(*)::int FROM auth.sessions WHERE user_id=ANY($1::uuid[]) AND user_id<>$2::uuid) AS eligible_load_actor_session_rows,
(SELECT coalesce(jsonb_object_agg(user_id::text,n),'{}'::jsonb) FROM
 (SELECT user_id,count(*)::int AS n FROM auth.sessions WHERE user_id=ANY($1::uuid[]) GROUP BY user_id) s) AS sessions_by_actor`;
const CONTROLS = ['BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY', 'COMMIT', 'ROLLBACK'];
const permittedQueries = new Set([...Object.values(READ_QUERIES), CAPACITY_SQL, ...CONTROLS]);
const equalPrivateTarget = (a, b) => ['host', 'port', 'database', 'user', 'password'].every(k => a[k] === b[k])
  && a.ssl.rejectUnauthorized === true && b.ssl.rejectUnauthorized === true
  && hashJson(Object.fromEntries(Object.entries(a.ssl).filter(([k]) => k !== 'passphrase')))
    === hashJson(Object.fromEntries(Object.entries(b.ssl).filter(([k]) => k !== 'passphrase')))
  && a.ssl.passphrase === b.ssl.passphrase;

// Factory construction and PgClient construction perform no credential read or network I/O.
// Only connect invokes the private callback. No environment-based connection defaults are used.
export function createBoundedPgDriver({ credentialProvider, PoolClass = Pool, maximumConnections = 8,
  acquireTimeoutMs = 10000, statementTimeoutMs = 25000 }) {
  must(typeof credentialProvider === 'function' && typeof PoolClass === 'function', 'PRIVATE_DATABASE_CALLBACK_REQUIRED');
  must(Number.isInteger(maximumConnections) && maximumConnections >= 1 && maximumConnections <= 8,
    'BOUNDED_DATABASE_POOL_REQUIRED');
  must(Number.isInteger(acquireTimeoutMs) && acquireTimeoutMs > 0 && acquireTimeoutMs <= 10000
    && Number.isInteger(statementTimeoutMs) && statementTimeoutMs > 0 && statementTimeoutMs <= 25000,
    'BOUNDED_DATABASE_TIMEOUT_REQUIRED');
  let pool = null, target = null, initialising = null, closing = null, closed = false, poolFailure = false;
  const lifecycle = new AbortController();
  let activeConnections = 0, peakConnections = 0, actualConnections = 0;
  const wrappers = new Set();
  const boundedCredentials = () => new Promise((resolve, reject) => {
    let settled = false;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true; clearTimeout(timer); lifecycle.signal.removeEventListener('abort', abort); callback(value);
    };
    const abort = () => finish(reject, new PrivatePgError('POSTGRES_DRIVER_CLOSED_OR_FAILED'));
    const timer = setTimeout(() => finish(reject, new PrivatePgError('PRIVATE_DATABASE_CONFIG_TIMEOUT')), acquireTimeoutMs);
    lifecycle.signal.addEventListener('abort', abort, { once: true });
    Promise.resolve().then(() => {
      must(!lifecycle.signal.aborted, 'POSTGRES_DRIVER_CLOSED_OR_FAILED'); return credentialProvider();
    }).then(value => finish(resolve, value), () => finish(reject, new PrivatePgError('PRIVATE_DATABASE_CONFIG_UNAVAILABLE')));
    if (lifecycle.signal.aborted) abort();
  });
  async function initialise(requested) {
    must(!closed && !poolFailure, 'POSTGRES_DRIVER_CLOSED_OR_FAILED');
    if (!initialising) initialising = (async () => {
      try {
        target = snapshotPrivateDatabaseConfig(await boundedCredentials());
        must(!closed, 'POSTGRES_DRIVER_CLOSED_OR_FAILED');
        must(equalPrivateTarget(requested, target), 'PRIVATE_DATABASE_TARGET_DRIFT');
        must(!target.ssl.minVersion || ['TLSv1.2', 'TLSv1.3'].includes(target.ssl.minVersion),
          'POSTGRES_TLS_MINIMUM_VERSION_REQUIRED');
        pool = new PoolClass({ ...snapshotPrivateDatabaseConfig(target),
          ssl: { ...snapshotPrivateDatabaseConfig(target).ssl, minVersion: target.ssl.minVersion ?? 'TLSv1.2' }, max: maximumConnections,
          connectionTimeoutMillis: acquireTimeoutMs, idleTimeoutMillis: 10000,
          statement_timeout: statementTimeoutMs, query_timeout: statementTimeoutMs,
          idle_in_transaction_session_timeout: statementTimeoutMs, lock_timeout: 5000,
          application_name: 'jentra-wave5-bounded-readonly', sslnegotiation: 'postgres',
          client_encoding: 'UTF8', options: '', keepAlive: true, enableChannelBinding: true });
        pool.on?.('error', () => { poolFailure = true; });
      } catch (error) {
        poolFailure = true;
        throw new PrivatePgError(error instanceof PrivatePgError ? error.code : 'PRIVATE_DATABASE_CONFIG_UNAVAILABLE');
      }
    })();
    await initialising;
    must(equalPrivateTarget(requested, target), 'PRIVATE_DATABASE_TARGET_DRIFT');
    return pool;
  }
  class PgClient {
    #config; #lease = null; #ended = false; #connecting = null; #poisoned = false;
    #transaction = false; #serial = Promise.resolve(); #pendingQueries = 0;
    constructor(config) { this.#config = snapshotPrivateDatabaseConfig(config); }
    get connection() { return this.#lease?.connection; }
    get processID() { return this.#lease?.processID; }
    async connect() {
      must(!this.#ended && !this.#lease && !this.#connecting, 'POSTGRES_CONNECTION_LIFECYCLE_INVALID');
      this.#connecting = (async () => {
        let acquired = null;
        try {
          acquired = await (await initialise(this.#config)).connect();
          const stream = acquired.connection?.stream;
          must(!this.#ended && !closed && !poolFailure, 'POSTGRES_DRIVER_CLOSED_OR_FAILED');
          must(stream?.encrypted === true && stream.authorized === true && !stream.authorizationError
            && typeof stream.getPeerCertificate === 'function', 'POSTGRES_TLS_NOT_VERIFIED');
          const certificate = stream.getPeerCertificate();
          must(certificate && Object.keys(certificate).length > 0
            && !tls.checkServerIdentity(this.#config.host, certificate), 'POSTGRES_TLS_HOSTNAME_MISMATCH');
          must(Number.isSafeInteger(acquired.processID) && acquired.processID > 0, 'ACTUAL_POSTGRES_BACKEND_REQUIRED');
          this.#lease = acquired; acquired = null;
          this.connectionId = `pg:${this.#lease.processID}:${crypto.randomUUID()}`;
          actualConnections += 1; activeConnections += 1; peakConnections = Math.max(peakConnections, activeConnections);
          wrappers.add(this);
        } catch (error) {
          acquired?.release(true);
          throw new PrivatePgError(error instanceof PrivatePgError ? error.code : 'POSTGRES_CONNECT_FAILED');
        }
      })();
      return this.#connecting;
    }
    async query(sql, values = []) {
      must(typeof sql === 'string' && permittedQueries.has(sql) && Array.isArray(values), 'SOURCE_BOUND_READ_QUERY_REQUIRED');
      must(this.#lease && !this.#ended && !this.#poisoned && !poolFailure, 'POSTGRES_CONNECTION_NOT_READY');
      this.#pendingQueries += 1;
      const query = this.#serial.then(async () => {
        must(this.#lease && !this.#ended && !this.#poisoned, 'POSTGRES_CONNECTION_NOT_READY');
        if (sql === CONTROLS[0]) must(!this.#transaction, 'POSTGRES_TRANSACTION_STATE_INVALID');
        else if (sql !== 'ROLLBACK') must(this.#transaction, 'READ_ONLY_TRANSACTION_REQUIRED');
        try {
          const result = await this.#lease.query(sql, values);
          must(!this.#ended && this.#lease, 'POSTGRES_CONNECTION_ENDED_DURING_QUERY');
          if (sql === CONTROLS[0]) this.#transaction = true;
          if (sql === 'COMMIT' || sql === 'ROLLBACK') this.#transaction = false;
          return result;
        } catch {
          this.#poisoned = true;
          throw new PrivatePgError('POSTGRES_QUERY_FAILED');
        }
      });
      this.#serial = query.catch(() => {});
      try { return await query; } finally { this.#pendingQueries -= 1; }
    }
    async end() {
      if (this.#ended) return;
      this.#ended = true;
      const lease = this.#lease; this.#lease = null;
      if (lease) { wrappers.delete(this); activeConnections -= 1;
        lease.release(this.#poisoned || this.#transaction || this.#pendingQueries > 0); }
    }
  }
  return Object.freeze({ PgClient, limits: Object.freeze({ maximumConnections, acquireTimeoutMs, statementTimeoutMs }),
    metrics: () => Object.freeze({ actualConnections, activeConnections, peakConnections,
      waitingConnections: pool?.waitingCount ?? 0, driverFailed: poolFailure }),
    close() { return closing ??= (async () => {
      closed = true; lifecycle.abort();
      await Promise.allSettled([...wrappers].map(client => client.end()));
      if (initialising) await initialising.catch(() => {}); if (pool) await pool.end();
    })(); }
  });
}

export async function collectReadOnlyPreflight({ driver, databaseConfig, authIds, signal }) {
  must(authIds && Object.keys(authIds).length === 6 && Object.values(authIds).every(isUuid)
    && new Set(Object.values(authIds)).size === 6 && isUuid(authIds.operator), 'EXACT_SIX_REVIEWED_AUTH_IDS_REQUIRED');
  const client = new driver.PgClient(databaseConfig); let committed = false;
  const abort = () => { void client.end(); }; signal?.addEventListener('abort', abort, { once: true });
  try {
    must(!signal?.aborted, 'READ_ONLY_PREFLIGHT_ABORTED'); await client.connect();
    await client.query(CONTROLS[0]);
    const capacity = await client.query(CAPACITY_SQL, [Object.values(authIds), authIds.operator]);
    const transaction = (await client.query(READ_QUERIES.transactionMetadata)).rows?.[0];
    must(transaction?.read_only === 'on' && transaction.isolation === 'repeatable read'
      && Number.isSafeInteger(transaction.backend_id) && transaction.backend_id > 0 && typeof transaction.snapshot_id === 'string'
      && Number.isFinite(Date.parse(transaction.observed_at)), 'ACTUAL_REPEATABLE_READ_PROOF_REQUIRED');
    must(!signal?.aborted && capacity.rows?.length === 1, 'READ_ONLY_PREFLIGHT_ABORTED');
    await client.query('COMMIT'); committed = true;
    const rows = capacity.rows;
    const evidence = { kind: 'actual-local-postgres-readonly-preflight', projectId: PROJECT_ID,
      observedAt: new Date(transaction.observed_at).toISOString(), committed: true, readOnly: true,
      isolation: 'repeatable-read', backendId: transaction.backend_id, snapshotId: transaction.snapshot_id,
      transportProcessId: client.processID, connectionId: client.connectionId,
      querySha256: hashBytes(CAPACITY_SQL), snapshotSha256: hashJson(rows),
      rows, limits: driver.limits, modelKeyRequiredForLoad: false, targetScaleLoadPassed: false,
      boundary: 'Actual local PostgreSQL read/COMMIT evidence only. Server session rows are not online Auth verification or load capacity.' };
    return Object.freeze({ ...evidence, transactionEvidenceSha256: hashJson(evidence) });
  } finally {
    signal?.removeEventListener('abort', abort);
    // On failure, release destroys a still-open/poisoned transaction; no retry is performed.
    await client.end();
    if (!committed && signal?.aborted) { /* No credential, server error or token is exposed. */ }
  }
}
