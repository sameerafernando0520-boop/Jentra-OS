import https from 'node:https';
import { PROJECT_ID, GuardError, requireGuard, isUuid, hashBytes, hashJson, immutableJson, validateRuntimeReview } from './runtime_contract.mjs';
import { READ_QUERIES, READ_QUERY_SHA256 } from './supabase_read_store.mjs';
import { FIXTURE_CAPS } from './runtime_fixture_spec.mjs';

// This is a fixed SELECT bridge, not a PostgreSQL client replacement. It records
// the actual Management API isolation and never invents a repeatable-read COMMIT
// proof. The owner PAT is injected privately; import/constructor do no I/O.
const ENDPOINT = `https://api.supabase.com/v1/projects/${PROJECT_ID}/database/query`;
const MAX_RESPONSE_BYTES = 8 * 1024 * 1024 + 1;
const NAMES = new Set(['installedSignaturesAndGrants', 'calendar', 'forecastIdentities', 'sourcePopulation',
  'scopeSnapshot', 'subscription', 'loadLedgers', 'loadQuiescence', 'leasePrerequisites', 'serverSession']);
const WRAP_START = 'WITH wave5_result AS MATERIALIZED (SELECT COALESCE(jsonb_agg(to_jsonb(wave5_row)),\'[]\'::jsonb) AS rows FROM (';
const WRAP_END = `) AS wave5_row)
SELECT wave5_result.rows,pg_catalog.pg_backend_pid() AS backend_id,
pg_catalog.txid_current_snapshot()::text AS snapshot_id,pg_catalog.statement_timestamp()::text AS observed_at,
pg_catalog.current_setting('transaction_read_only') AS read_only,
pg_catalog.current_setting('transaction_isolation') AS isolation FROM wave5_result`;

export function createSupabaseManagementReadBridge({ review, authIds, privateManagementToken, requestFactory = https.request,
  agentFactory = () => new https.Agent({ keepAlive: true, maxSockets: 1, maxFreeSockets: 1, rejectUnauthorized: true }), timeoutMs = 25000 }) {
  validateRuntimeReview(review);
  requireGuard(typeof privateManagementToken === 'string' && privateManagementToken.length > 8
    && typeof requestFactory === 'function' && typeof agentFactory === 'function'
    && Number.isInteger(timeoutMs) && timeoutMs >= 1 && timeoutMs <= 30000, 'PRIVATE_PROVIDER_INCOMPLETE');
  const scopes = immutableJson(review.syntheticScopes), scopeByKey = new Map(scopes.map(target => [target.key, target])),
    actors = authIds === undefined ? null : immutableJson(authIds);
  if (actors) requireGuard(review.accounts.every(actor => isUuid(actors[actor.label])) && Object.keys(actors).length === 6
    && new Set(Object.values(actors)).size === 6, 'EXACT_REAL_AUTH_IDS_REQUIRED');
  const permittedActors = new Set(Object.values(actors ?? {})), requests = new Map(); let closed = false;
  function parameters(name, args) {
    requireGuard(NAMES.has(name) && args && typeof args === 'object' && !Array.isArray(args), 'COMMITTED_SCOPED_READ_REQUIRED');
    if (name === 'installedSignaturesAndGrants' || name === 'calendar') return [];
    if (name === 'serverSession') {
      requireGuard(isUuid(args.sessionId) && permittedActors.has(args.actorId), 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
      return [args.sessionId, args.actorId];
    }
    if (name === 'loadQuiescence') return [FIXTURE_CAPS.runtimeId];
    if (name === 'loadLedgers') return [scopes.map(target => target.tenantId), FIXTURE_CAPS.runtimeId];
    if (name === 'forecastIdentities') return [JSON.stringify(scopes.map(target => ({ tenant_id: target.tenantId,
      entity_id: target.entityId, branch_id: target.branchId })))];
    const target = scopeByKey.get(args.scopeKey); requireGuard(target, 'INVALID_SCOPE_KEY');
    if (name === 'leasePrerequisites') requireGuard(target.key === 'runtime', 'INVALID_REVIEWED_SCOPE');
    return [target.tenantId];
  }
  function post(query, values, signal) {
    const bytes = JSON.stringify({ query, parameters: values, read_only: true }), startedAt = new Date().toISOString();
    return new Promise((resolve, reject) => {
      let settled = false, req, timer, agent; const chunks = []; let size = 0, sentAt = null;
      const clean = () => { clearTimeout(timer); signal?.removeEventListener('abort', abort); requests.delete(req); agent?.destroy(); };
      const fail = code => { if (settled) return; settled = true; clean(); reject(new GuardError(code)); req?.destroy(); };
      const abort = () => fail('RUN_ABORTED');
      try {
        agent = agentFactory();
        req = requestFactory(new URL(ENDPOINT), { method: 'POST', agent, rejectUnauthorized: true,
          headers: { Authorization: `Bearer ${privateManagementToken}`, 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bytes) } }, res => {
          // No redirects, retry, alternate target or raw private API error body.
          if (![200, 201].includes(res.statusCode)) { fail('PROVIDER_FAILURE'); return; }
          res.on('data', chunk => { if (settled) return; size += chunk.length;
            if (size > MAX_RESPONSE_BYTES) fail('LIMIT_EXCEEDED'); else chunks.push(chunk); });
          res.on('error', () => fail('TRANSPORT_UNCERTAIN'));
          res.on('end', () => {
            if (settled) return;
            try {
              const raw = Buffer.concat(chunks), result = JSON.parse(raw.toString('utf8'));
              requireGuard(Array.isArray(result) && result.length === 1 && Array.isArray(result[0]?.rows), 'INVALID_PROVIDER_OUTCOME');
              const packet = result[0];
              requireGuard(packet.read_only === 'on' && Number.isInteger(packet.backend_id) && packet.backend_id > 0
                && typeof packet.snapshot_id === 'string' && packet.snapshot_id.length > 0
                && typeof packet.observed_at === 'string' && Number.isFinite(Date.parse(packet.observed_at))
                && ['read committed', 'repeatable read', 'serializable'].includes(packet.isolation), 'COMMITTED_SCOPED_READ_REQUIRED');
              const transportEvidence = { projectId: PROJECT_ID, endpoint: ENDPOINT, method: 'POST',
                startedAt, sentAt, finishedAt: new Date().toISOString(), status: res.statusCode,
                querySha256: hashBytes(query), bindingsSha256: hashJson(values), responseSha256: hashBytes(raw), responseBytes: raw.length };
              settled = true; clean(); resolve({ packet: immutableJson(packet), transportEvidenceSha256: hashJson(transportEvidence) });
            } catch (error) { fail(error instanceof GuardError ? error.code : 'INVALID_PROVIDER_OUTCOME'); }
          });
        });
        requests.set(req, abort); req.on('error', () => fail(signal?.aborted ? 'RUN_ABORTED' : 'TRANSPORT_UNCERTAIN'));
        signal?.addEventListener('abort', abort, { once: true }); timer = setTimeout(() => fail('TRANSPORT_TIMEOUT'), timeoutMs);
        if (signal?.aborted) { abort(); return; }
        req.once('socket', socket => {
          const write = () => {
            if (settled) { req.destroy(); return; }
            if (signal?.aborted || closed) { fail('RUN_ABORTED'); return; }
            if (socket?.encrypted !== true || socket.authorized !== true) { fail('EXACT_DEVELOPMENT_TARGET_REQUIRED'); return; }
            sentAt = new Date().toISOString(); req.end(bytes);
          };
          if (settled) { req.destroy(); return; }
          if (socket?.encrypted !== true) { fail('EXACT_DEVELOPMENT_TARGET_REQUIRED'); return; }
          if (socket.authorized === true) write(); else socket.once('secureConnect', write);
        });
      } catch { fail('PROVIDER_FAILURE'); }
    });
  }
  return Object.freeze({ async read(name, args = {}, signal) {
    requireGuard(!closed && !signal?.aborted, 'RUN_ABORTED');
    const values = parameters(name, args), query = `${WRAP_START}${READ_QUERIES[name]}${WRAP_END}`;
    const { packet, transportEvidenceSha256 } = await post(query, values, signal);
    return Object.freeze({ kind: 'management-api-fixed-read-result', projectId: PROJECT_ID, name, rows: packet.rows,
      querySha256: READ_QUERY_SHA256[name], executedQuerySha256: hashBytes(query), bindingsSha256: hashJson(values),
      snapshotSha256: hashJson(packet.rows), transportEvidenceSha256, observedAt: packet.observed_at,
      serverBackendId: packet.backend_id, serverSnapshotId: packet.snapshot_id, readOnly: true,
      isolation: packet.isolation, committedTransactionProof: false, repeatableReadProof: false });
  }, close() { closed = true; for (const abort of [...requests.values()]) abort(); } });
}
