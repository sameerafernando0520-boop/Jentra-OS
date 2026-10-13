import { PROJECT_ID, GuardError, requireGuard, isUuid, hashBytes, hashJson, immutableJson, safeCode } from './runtime_contract.mjs';
import { COMMITTED_READS, FIXTURE_CAPS } from './runtime_fixture_spec.mjs';

// A private factory supplies its reviewed PostgreSQL driver and credentials. No module
// import, constructor or validation opens a connection or reads an environment variable.
const SESSION_SQL = `SELECT id,user_id,created_at,updated_at,not_after,aal::text,factor_id
FROM auth.sessions WHERE id = $1::uuid AND user_id = $2::uuid`;
const TRANSACTION_SQL = `SELECT pg_backend_pid() AS backend_id,txid_current_snapshot()::text AS snapshot_id,
statement_timestamp() AS observed_at,current_setting('transaction_isolation') AS isolation,
current_setting('transaction_read_only') AS read_only`;
const CALENDAR_SQL = `SELECT statement_timestamp() AS observed_at`;
const FORECAST_IDS_SQL = `WITH reviewed AS (SELECT * FROM jsonb_to_recordset($1::jsonb)
AS x(tenant_id uuid,entity_id uuid,branch_id uuid))
SELECT DISTINCT ON (f.tenant_id) f.tenant_id,f.legal_entity_id,f.branch_id,f.id,f.horizon_start,f.horizon_end,f.source_hash,
f.observed_at,jsonb_array_length(f.evidence->'observations') AS source_count
FROM analytics.pipeline_forecasts f JOIN reviewed x ON x.tenant_id=f.tenant_id AND x.entity_id=f.legal_entity_id
AND x.branch_id IS NOT DISTINCT FROM f.branch_id ORDER BY f.tenant_id,f.observed_at DESC,f.id`;
const SUBSCRIPTION_SQL = `SELECT s.id,s.tenant_id,s.plan_code,s.status,s.seats,s.version::text,
coalesce(s.trial_started_at,s.created_at)::text AS period_start,s.trial_ends_at::text AS period_end,
p.numeric_limit::text AS delivery_cap,p.enabled AS delivery_enabled
FROM billing.tenant_subscriptions s LEFT JOIN billing.plan_entitlements p ON p.plan_code=s.plan_code
AND p.entitlement_code='quota.webhook.deliveries' WHERE s.tenant_id=$1::uuid`;
const LEASE_PREREQUISITE_SQL = `SELECT
(SELECT count(*) FROM intelligence_control.integration_subscriptions s WHERE s.tenant_id=$1::uuid AND s.enabled) AS enabled_subscriptions,
(SELECT coalesce(jsonb_agg(s.id ORDER BY s.id),'[]'::jsonb) FROM intelligence_control.integration_subscriptions s
WHERE s.tenant_id=$1::uuid AND s.enabled) AS enabled_subscription_ids,
(SELECT count(*) FROM intelligence_control.delivery_heads h WHERE h.tenant_id=$1::uuid
AND h.state IN ('pending','retry') AND h.available_at<=statement_timestamp() AND h.attempt<8) AS available_heads,
(SELECT count(*) FROM intelligence_control.integration_subscriptions s
JOIN analytics.pipeline_forecasts f ON f.tenant_id=s.tenant_id AND f.legal_entity_id=s.legal_entity_id AND f.branch_id IS NOT DISTINCT FROM s.branch_id
JOIN core.outbox_events e ON e.tenant_id=f.tenant_id AND e.aggregate_id=f.id AND e.aggregate_type='pipeline_forecast' AND e.topic='analytics.freeze_pipeline'
WHERE s.tenant_id=$1::uuid AND s.enabled AND e.created_at>=s.created_at
AND NOT EXISTS(SELECT 1 FROM intelligence_control.delivery_heads h WHERE h.tenant_id=s.tenant_id AND h.subscription_id=s.id
AND h.event_id=e.id AND h.generation=0)) AS unmaterialized_pairs,
(SELECT count(*) FROM intelligence_control.delivery_heads WHERE tenant_id=$1::uuid AND state='leased') AS leased_heads`;

export const READ_QUERIES = immutableJson(Object.fromEntries([
  ...Object.entries(COMMITTED_READS).filter(([, entry]) => typeof entry.sql === 'string').map(([name, entry]) => [name, entry.sql]),
  ['serverSession', SESSION_SQL], ['forecastIdentities', FORECAST_IDS_SQL], ['subscription', SUBSCRIPTION_SQL],
  ['calendar', CALENDAR_SQL], ['leasePrerequisites', LEASE_PREREQUISITE_SQL], ['transactionMetadata', TRANSACTION_SQL],
]));
export const READ_QUERY_SHA256 = immutableJson(Object.fromEntries(Object.entries(READ_QUERIES).map(([name, sql]) => [name, hashBytes(sql)])));
export function committedRecipeHash(names) {
  requireGuard(Array.isArray(names) && names.length > 0 && names.every(name => READ_QUERIES[name]), 'COMMITTED_SCOPED_READ_REQUIRED');
  return names.length === 1 ? READ_QUERY_SHA256[names[0]] : hashJson(names.map(name => ({ name, sql: READ_QUERIES[name] })));
}

export function exactInteger(value) {
  const text = typeof value === 'number' && Number.isSafeInteger(value) ? String(value) : value;
  requireGuard(typeof text === 'string' && /^(0|[1-9][0-9]*)(\.0+)?$/.test(text), 'COMMITTED_STATE_REQUIRED');
  const integer = BigInt(text.split('.')[0]);
  requireGuard(integer <= BigInt(Number.MAX_SAFE_INTEGER), 'COMMITTED_STATE_REQUIRED'); return Number(integer);
}
const iso = value => {
  const time = value instanceof Date ? value.getTime() : Date.parse(value);
  requireGuard(Number.isFinite(time), 'COMMITTED_SCOPED_READ_REQUIRED'); return new Date(time).toISOString();
};

export function validatePrivateDatabaseTarget(config) {
  requireGuard(config && typeof config.host === 'string' && config.database === 'postgres'
    && config.ssl?.rejectUnauthorized === true && [5432, 6543].includes(config.port ?? 5432)
    && typeof config.user === 'string' && typeof config.password === 'string' && config.password.length > 0,
    'EXACT_DEVELOPMENT_TARGET_REQUIRED');
  const direct = config.host === `db.${PROJECT_ID}.supabase.co`;
  const pooler = /^[a-z0-9-]+\.pooler\.supabase\.com$/.test(config.host)
    && config.user.endsWith(`.${PROJECT_ID}`);
  requireGuard(direct || pooler, 'EXACT_DEVELOPMENT_TARGET_REQUIRED');
  // Do not allow URI overrides or a non-verifying TLS wrapper to change the validated destination.
  requireGuard(!Object.keys(config).some(key => ['connectionString', 'stream', 'sslmode'].includes(key))
    && !config.ssl.checkServerIdentity && (!config.ssl.servername || config.ssl.servername === config.host),
    'EXACT_DEVELOPMENT_TARGET_REQUIRED'); return true;
}

export function snapshotPrivateDatabaseConfig(config) {
  validatePrivateDatabaseTarget(config);
  const cloneTlsValue = value => {
    if (Buffer.isBuffer(value)) return Buffer.from(value);
    if (Array.isArray(value)) return Object.freeze(value.map(cloneTlsValue));
    requireGuard(typeof value === 'string' || typeof value === 'boolean', 'EXACT_DEVELOPMENT_TARGET_REQUIRED'); return value;
  };
  const ssl = {};
  for (const [name, value] of Object.entries(config.ssl)) {
    requireGuard(['rejectUnauthorized', 'ca', 'cert', 'key', 'passphrase', 'minVersion', 'maxVersion', 'ciphers', 'servername'].includes(name),
      'EXACT_DEVELOPMENT_TARGET_REQUIRED'); ssl[name] = cloneTlsValue(value);
  }
  // Whitelist the connection fields rather than retain the caller's mutable
  // object/getters. No password or TLS credential is serialized or logged.
  const snapshot = Object.freeze({ host: config.host, port: config.port ?? 5432, database: config.database,
    user: config.user, password: config.password, ssl: Object.freeze(ssl) });
  validatePrivateDatabaseTarget(snapshot); return snapshot;
}

export function createSupabaseReadStore({ review, authIds, PgClient, databaseConfig }) {
  const privateDatabase = snapshotPrivateDatabaseConfig(databaseConfig);
  requireGuard(typeof PgClient === 'function', 'PRIVATE_PROVIDER_INCOMPLETE');
  const frozenScopes = immutableJson(review.syntheticScopes), scopes = new Map(frozenScopes.map(s => [s.key, s]));
  requireGuard(review.projectId === PROJECT_ID && scopes.size === 500, 'REVIEWED_SCOPES_REQUIRED');
  requireGuard(authIds && review.accounts.every(actor => isUuid(authIds[actor.label]))
    && Object.keys(authIds).length === 6 && new Set(Object.values(authIds)).size === 6, 'EXACT_REAL_AUTH_IDS_REQUIRED');
  const permittedActors = new Set(Object.values(authIds));
  const tenants = frozenScopes.map(s => s.tenantId), allowed = new Set(tenants), runtimeId = FIXTURE_CAPS.runtimeId;
  let closed = false; const active = new Set();
  const scope = key => { const value = scopes.get(key); requireGuard(value, 'INVALID_SCOPE_KEY'); return value; };
  const actorIds = values => requireGuard(Array.isArray(values) && values.length > 0 && values.every(isUuid)
    && new Set(values).size === values.length, 'EXACT_REAL_AUTH_IDS_REQUIRED');
  function parameters(name, args = {}) {
    if (name === 'installedSignaturesAndGrants' || name === 'calendar') return [];
    if (name === 'serverSession') {
      requireGuard(isUuid(args.sessionId) && permittedActors.has(args.actorId), 'ONLINE_SESSION_ROW_PROOF_REQUIRED'); return [args.sessionId, args.actorId];
    }
    if (name === 'loadLedgers') return [tenants, runtimeId];
    if (name === 'loadQuiescence') return [runtimeId];
    if (name === 'forecastIdentities') return [JSON.stringify(frozenScopes.map(s => ({ tenant_id: s.tenantId, entity_id: s.entityId, branch_id: s.branchId })))];
    const target = scope(args.scopeKey), result = [target.tenantId];
    if (name === 'leasePrerequisites') requireGuard(target.key === 'runtime', 'INVALID_REVIEWED_SCOPE');
    if (name === 'invitationProvenance') {
      requireGuard(target.key === 'load-001' && Array.isArray(args.cohort) && args.cohort.length >= 1 && args.cohort.length <= 2
        && args.cohort.every(item => isUuid(item.invitation_id) && [authIds.approver, authIds.executor].includes(item.actor_id))
        && new Set(args.cohort.map(item => item.invitation_id)).size === args.cohort.length, 'REVIEWED_CASE_BINDING_REQUIRED');
      result.push(JSON.stringify(args.cohort));
    } else if (name === 'invocationProvenance') {
      requireGuard(target.key === 'load-001' && Array.isArray(args.invocationIds)
        && [0, 20].includes(args.invocationIds.length), 'REVIEWED_CASE_BINDING_REQUIRED');
      if (args.invocationIds.length) actorIds(args.invocationIds); result.push(args.invocationIds);
    } else if (name === 'activationPrerequisites' || name === 'proposalPrerequisites') {
      requireGuard(isUuid(args.resourceId) && (name === 'activationPrerequisites'
        ? ['runtime', 'load-001'].includes(target.key) : target.key === 'runtime'), 'REVIEWED_CASE_BINDING_REQUIRED');
      result.push(args.resourceId);
    } else if (name === 'restorationBaseline') {
      requireGuard(target.key === 'load-001' && args.actorIds?.length === 2, 'EXACT_RESTORATION_PROOF_REQUIRED');
      actorIds(args.actorIds); requireGuard(args.actorIds.includes(authIds.approver) && args.actorIds.includes(authIds.executor),
        'EXACT_RESTORATION_PROOF_REQUIRED'); result.push(args.actorIds);
    }
    requireGuard(allowed.has(result[0]), 'INVALID_REVIEWED_SCOPE'); return result;
  }
  async function readBatch(entries, signal) {
    requireGuard(!closed && !signal?.aborted, 'RUN_ABORTED');
    requireGuard(Array.isArray(entries) && entries.length > 0 && entries.length <= 8
      && new Set(entries.map(entry => entry.name)).size === entries.length, 'COMMITTED_SCOPED_READ_REQUIRED');
    const queries = entries.map(({ name, args = {} }) => {
      const sql = name === 'serverSession' ? SESSION_SQL : name === 'calendar' ? CALENDAR_SQL
        : name === 'forecastIdentities' ? FORECAST_IDS_SQL : name === 'subscription' ? SUBSCRIPTION_SQL
        : name === 'leasePrerequisites' ? LEASE_PREREQUISITE_SQL : COMMITTED_READS[name]?.sql;
      requireGuard(typeof sql === 'string', 'COMMITTED_SCOPED_READ_REQUIRED'); return { name, sql, values: parameters(name, args) };
    });
    // Each dispatch receives a fresh private TLS copy, so a driver cannot mutate
    // the reviewed snapshot's buffers/options for a later connection.
    const client = new PgClient({ ...snapshotPrivateDatabaseConfig(privateDatabase), connectionTimeoutMillis: 25000,
      statement_timeout: 25000, application_name: 'jentra-wave5-readonly-verification' });
    active.add(client); let connected = false, begun = false;
    // Aborting destroys only this new read connection. Existing sessions/stores are never touched.
    const abort = () => { void client.end().catch(() => {}); };
    signal?.addEventListener('abort', abort, { once: true });
    try {
      await client.connect(); connected = true;
      requireGuard(!signal?.aborted, 'RUN_ABORTED');
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'); begun = true;
      const results = [];
      for (const query of queries) { requireGuard(!signal?.aborted, 'RUN_ABORTED'); results.push(await client.query(query.sql, query.values)); }
      const metadataResult = await client.query(TRANSACTION_SQL);
      const metadata = metadataResult.rows?.[0];
      requireGuard(metadata?.read_only === 'on' && metadata.isolation === 'repeatable read'
        && Number.isInteger(metadata.backend_id) && typeof metadata.snapshot_id === 'string', 'COMMITTED_SCOPED_READ_REQUIRED');
      requireGuard(!signal?.aborted, 'RUN_ABORTED');
      await client.query('COMMIT'); begun = false;
      const rows = immutableJson(Object.fromEntries(queries.map((query, index) => [query.name, results[index].rows]))), observedAt = iso(metadata.observed_at);
      const querySha256 = queries.length === 1 ? hashBytes(queries[0].sql) : hashJson(queries.map(query => ({ name: query.name, sql: query.sql }))),
        transactionEvidenceSha256 = hashJson({ projectId: PROJECT_ID,
        querySha256, bindingsSha256: hashJson(queries.map(query => query.values)), backendId: metadata.backend_id, snapshotId: metadata.snapshot_id,
        observedAt, committed: true, isolation: 'repeatable-read', readOnly: true });
      return Object.freeze({ rows, observedAt, querySha256, snapshotSha256: hashJson(rows), transactionEvidenceSha256,
        committed: true, readOnly: true, isolation: 'repeatable-read' });
    } catch (error) {
      if (connected && begun) { try { await client.query('ROLLBACK'); } catch {} }
      throw new GuardError(error instanceof GuardError ? safeCode(error.code) : signal?.aborted ? 'RUN_ABORTED' : 'PROVIDER_FAILURE');
    } finally {
      signal?.removeEventListener('abort', abort); active.delete(client);
      try { await client.end(); } catch {}
    }
  }
  async function read(name, args = {}, signal) {
    const proof = await readBatch([{ name, args }], signal); return Object.freeze({ ...proof, rows: proof.rows[name] });
  }
  return Object.freeze({ read, readBatch, async readServerSession({ sessionId, actorId, signal }) {
    const proof = await read('serverSession', { sessionId, actorId }, signal), row = proof.rows[0];
    requireGuard(proof.rows.length === 1 && row.id === sessionId && row.user_id === actorId, 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
    return Object.freeze({ id: row.id, userId: row.user_id, present: true, committed: true, readOnly: true,
      notAfter: row.not_after ? iso(row.not_after) : null, aal: row.aal, factorId: row.factor_id,
      evidenceSha256: hashJson({ snapshot: proof.snapshotSha256, transaction: proof.transactionEvidenceSha256 }) });
  }, async close() { closed = true; await Promise.allSettled([...active].map(client => client.end())); active.clear(); } });
}
