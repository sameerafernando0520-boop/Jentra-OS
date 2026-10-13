import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import { PROJECT_ID, PROJECT_URL, hashJson, hashBytes, GuardError, RACE_KINDS, freshId } from './runtime_contract.mjs';
import { createSupabaseHttpsTransport, createAuthClient, totpFromPrivateSecret, decodeReceivedAccessToken } from './supabase_http_transport.mjs';
import { createSupabaseReadStore, READ_QUERIES, READ_QUERY_SHA256, committedRecipeHash, exactInteger, validatePrivateDatabaseTarget } from './supabase_read_store.mjs';
import { createMembershipFixture, MEMBERSHIP_FIXTURE_SQL } from './supabase_membership_fixture.mjs';
import { createPreparationJournal } from './preparation_journal.mjs';
import { createSupabaseRuntimeProvider, mappedRpcRequest, outcomeFromRpc, CASE_READ_RECIPES, validateProviderCalendar, reviewedTrialWindow } from './supabase_runtime_provider.mjs';

// Controlled local objects only. No server, socket, Auth row, JWT, credential store,
// live SQL, SDK or network is created by this suite.
const review = JSON.parse(fs.readFileSync(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json', import.meta.url)));
const owner = JSON.parse(fs.readFileSync(new URL('../../docs/verification/wave5/runtime-owner-decision-20261012-r5.json', import.meta.url)));
const sha = value => hashJson(value);
const authIds = Object.fromEntries(review.accounts.map(actor => [actor.label, freshId()]));
const scope = review.syntheticScopes.find(value => value.key === 'runtime');
const calendar = { horizonStart: '2026-10-01', horizonEnd: '2026-11-01', windowStart: '2026-10-01T00:00:00Z',
  windowEnd: '2026-10-08T00:00:00Z', asOf: '2026-10-08T00:00:00Z', recordedThrough: '2026-10-08T00:00:00Z',
  clientTimestamp: '2026-10-12T00:00:00Z' };
const databaseConfig = { host: `db.${PROJECT_ID}.supabase.co`, database: 'postgres', user: 'postgres',
  password: 'controlled-private-value', ssl: { rejectUnauthorized: true } };
function context() {
  const providerSha = sha('controlled-private-factory'), driverSha = sha('controlled-driver');
  const plan = { kind: 'wave5-runtime-harness-plan', projectId: PROJECT_ID, url: PROJECT_URL, production: false, realBilling: false,
    runtimeBundleSha256: review.bundleSha256, warmupMs: 60000, measuredMs: 300000, maxRunMs: 900000,
    maximumTimedRequests: 20000, maxInflight: 2000, requestsPerSecond: 20, providerCalendarSha256: hashJson(calendar),
    postgresDriverSourceSha256: driverSha, preparationJournalSourceSha256: sha('controlled-private-preparation-sink'),
    cases: RACE_KINDS.map(kind => ({ kind, caseId: freshId(), scopeKey: ['seats', 'admissions', 'quota'].includes(kind) ? 'load-001' : 'runtime',
      participants: kind === 'duplicates' ? 100 : kind === 'quota' ? 20 : 2, noExternalSend: true,
      fixturePlanSha256: sha([kind, 'fixture']), committedQuerySha256: committedRecipeHash(CASE_READ_RECIPES[kind]),
      preparationSha256: sha([kind, 'preparation']), restorationSha256: sha([kind, 'restoration']) })),
    boundaries: ['10001Rows', '101Groups', '367DayWindow', '8MiBPlus1Byte'].map(kind => ({ kind, scopeKey: 'runtime', caseId: freshId(),
      fixturePlanSha256: sha([kind, 'fixture']), committedQuerySha256: READ_QUERY_SHA256.scopeSnapshot, expectedCode: 'LIMIT_EXCEEDED' })),
    loadCommittedQuerySha256: READ_QUERY_SHA256.loadLedgers, loadFixturePlanSha256: sha('load-fixture'), externalObservationSourceSha256: sha('observer') };
  const binding = { runtimeFileSha256: owner.runtimeFileSha256, harnessReviewSha256: sha('controlled-harness-review'),
    planSha256: sha(plan), planBodySha256: sha(plan), privateProviderSha256: providerSha };
  const independentReview = { kind: 'wave5-runtime-harness-independent-preparation-review', result: 'approved-for-existing-bounded-scope',
    projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256,
    harnessReviewSha256: binding.harnessReviewSha256, planSha256: binding.planSha256, privateProviderSha256: providerSha,
    sourceBindingsVerified: true, operationScopeSha256: review.sourceContinuation.unchangedRuntimeOperationScopeSha256,
    sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
  binding.independentReviewBodySha256 = sha(independentReview);
  const preparation = { kind: 'wave5-runtime-harness-preparation', sourceBindingsVerified: true,
    runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256, harnessReviewSha256: binding.harnessReviewSha256,
    planSha256: binding.planSha256, privateProviderSha256: providerSha, independentReview: { result: independentReview.result,
      path: 'controlled-not-live.json', sha256: sha(independentReview) }, sameApprovedOperationScope: true,
    additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
  return { review, plan, approval: owner, preparation, independentReview, binding };
}
function controlledHttps({ delaySocket = false, status = 200, response = { id: 'local-fixture' }, failure } = {}) {
  const requests = [], agents = []; let ended = 0;
  function requestFactory(url, options, onResponse) {
    const req = new EventEmitter(); req.destroy = () => {}; req.setTimeout = () => {};
    req.end = bytes => { ended++; requests.at(-1).bytes = bytes;
      queueMicrotask(() => {
        if (failure) { req.emit('error', new Error(failure)); return; }
        const res = new EventEmitter(); res.statusCode = status; onResponse(res);
        const payload = typeof response === 'string' ? response : JSON.stringify(response);
        res.emit('data', Buffer.from(payload)); res.emit('end');
      });
    };
    requests.push({ url: url.href, options, req });
    if (!delaySocket) queueMicrotask(() => req.emit('socket', { encrypted: true, authorized: true })); return req;
  }
  const transport = createSupabaseHttpsTransport({ projectId: PROJECT_ID, apiKey: 'controlled-anon-key', requestFactory,
    agentFactory: () => { const agent = { destroy() {}, local: agents.length }; agents.push(agent); return agent; } });
  return { transport, requests, agents, ended: () => ended };
}
const privateRpc = handle => ({ profile: 'api', bearer: 'controlled-only-token', handle });
const preparationReceipt = record => ({ durable: true, appendOnly: true, recordSha256: hashJson(record), storageEvidenceSha256: hashJson(['controlled-sink', record]) });
const privatePreparationConfig = (input, append = async record => preparationReceipt(record)) => ({
  appendPreparationEvidence: append, preparationJournalSourceSha256: input.plan.preparationJournalSourceSha256 });
const controlledPreparationJournal = (input, append = async record => preparationReceipt(record)) => createPreparationJournal({
  projectId: PROJECT_ID, runtimeBundleSha256: input.review.bundleSha256, planBodySha256: input.binding.planBodySha256,
  sourceSha256: input.plan.preparationJournalSourceSha256, cases: [...input.plan.cases, ...input.plan.boundaries], appendPreparationEvidence: append });

test('HTTPS resolves actual socket queue before send hook, uses fixed target/schema, and exposes hashes without credentials', async () => {
  const local = controlledHttps({ delaySocket: true }), handle = local.transport.connection(), order = [];
  const pending = local.transport.send(handle, '/rest/v1/rpc/get_wave5_subscription', { ...privateRpc(handle), body: { p_tenant_id: scope.tenantId },
    onTransportStart() { order.push('start'); }, onTransportEnd() { order.push('end'); } });
  await Promise.resolve(); assert.equal(local.ended(), 0); local.requests[0].req.emit('socket', { encrypted: true, authorized: true });
  const result = await pending; assert.equal(local.ended(), 1); assert.deepEqual(order, ['start', 'end']);
  assert.equal(local.requests[0].url, `${PROJECT_URL}/rest/v1/rpc/get_wave5_subscription`);
  assert.equal(local.requests[0].options.headers['Content-Profile'], 'api');
  assert.ok(!JSON.stringify(result.evidence).includes('controlled-only-token')); assert.equal(result.evidence.sentAt !== null, true);
  assert.equal(result.transportEvidenceSha256, sha(result.evidence)); local.transport.close();
});
test('deadline hook failure leaves queued request unsent and arbitrary private GuardError detail is normalized', async () => {
  const local = controlledHttps({ delaySocket: true }), handle = local.transport.connection();
  const pending = local.transport.send(handle, '/rest/v1/rpc/get_wave5_subscription', { ...privateRpc(handle),
    onTransportStart() { throw new GuardError('private-owner-detail'); } });
  local.requests[0].req.emit('socket', { encrypted: true, authorized: true });
  await assert.rejects(pending, { code: 'PROVIDER_FAILURE' }); assert.equal(local.ended(), 0);
});
test('late socket assignment after a request error cannot invoke transport hooks or write bytes', async () => {
  const local = controlledHttps({ delaySocket: true }), handle = local.transport.connection(); let starts = 0;
  const pending = local.transport.send(handle, '/auth/v1/user', { method: 'GET', onTransportStart() { starts++; } });
  local.requests[0].req.emit('error', new Error('controlled-before-socket'));
  await assert.rejects(pending, { code: 'TRANSPORT_UNCERTAIN' });
  local.requests[0].req.emit('socket', { encrypted: true, authorized: true });
  await Promise.resolve(); assert.equal(starts, 0); assert.equal(local.ended(), 0);
});

test('new TLS handshake queues remain unsent and run the current deadline hook only after certificate verification', async () => {
  const local = controlledHttps({ delaySocket: true }), handle = local.transport.connection(), socket = new EventEmitter();
  socket.encrypted = true; socket.authorized = false; let expired = false, starts = 0;
  const pending = local.transport.send(handle, '/auth/v1/user', { method: 'GET', onTransportStart() {
    starts++; if (expired) throw new GuardError('WORKLOAD_DEADLINE_EXCEEDED');
  } });
  local.requests[0].req.emit('socket', socket); await Promise.resolve();
  assert.equal(starts, 0); assert.equal(local.ended(), 0);
  expired = true; socket.authorized = true; socket.emit('secureConnect');
  await assert.rejects(pending, { code: 'WORKLOAD_DEADLINE_EXCEEDED' }); assert.equal(starts, 1); assert.equal(local.ended(), 0);
});

test('TLS verification failures and late handshake events after request failure cannot write credential-bearing bytes', async () => {
  for (const lateError of [false, true]) {
    const local = controlledHttps({ delaySocket: true }), socket = new EventEmitter(); socket.encrypted = true; socket.authorized = false;
    let starts = 0; const pending = local.transport.send(local.transport.connection(), '/auth/v1/user', {
      method: 'GET', bearer: 'controlled-private-token', onTransportStart() { starts++; } });
    local.requests[0].req.emit('socket', socket);
    if (lateError) local.requests[0].req.emit('error', new Error('controlled-handshake-failure'));
    else socket.emit('secureConnect');
    await assert.rejects(pending, { code: lateError ? 'TRANSPORT_UNCERTAIN' : 'EXACT_DEVELOPMENT_TARGET_REQUIRED' });
    socket.authorized = true; socket.emit('secureConnect'); await Promise.resolve();
    assert.equal(starts, 0); assert.equal(local.ended(), 0);
  }
});
test('transport denies arbitrary routes, wrong verbs/profiles, foreign connections and malformed factor IDs before request creation', async () => {
  const local = controlledHttps(), handle = local.transport.connection();
  for (const [route, options] of [ ['https://attacker.invalid/auth/v1/user', { method: 'GET' }], ['/rest/v1/rpc/delete_user', {}],
    ['/auth/v1/user', { method: 'POST' }], ['/auth/v1/factors/------------------------------------/challenge', {}],
    ['/rest/v1/rpc/get_wave5_subscription', { bearer: 'controlled-only-token', profile: 'public' }] ]) {
    await assert.rejects(local.transport.send(handle, route, options));
  }
  await assert.rejects(local.transport.send({}, '/auth/v1/user', { method: 'GET' })); assert.equal(local.requests.length, 0);
});
test('each HTTP participant uses a separate agent and private transport errors never reveal raw text', async () => {
  const local = controlledHttps({ failure: 'password=controlled-sensitive' });
  const handles = [local.transport.connection(), local.transport.connection()];
  await Promise.all(handles.map(handle => assert.rejects(local.transport.send(handle, '/auth/v1/user', { method: 'GET', bearer: 'private-token' }),
    error => error.code === 'TRANSPORT_UNCERTAIN' && !error.message.includes('sensitive'))));
  assert.notEqual(local.requests[0].options.agent, local.requests[1].options.agent);
});
test('malformed response and bounded response overflow fail closed', async () => {
  for (const response of ['not-json', 'x'.repeat(8388610)]) {
    const local = controlledHttps({ response }); await assert.rejects(local.transport.send(local.transport.connection(), '/auth/v1/user', { method: 'GET' }),
      error => ['LIMIT_EXCEEDED', 'INVALID_PROVIDER_OUTCOME'].includes(error.code));
  }
});
test('TOTP uses published RFC 6238 secret and counters; it neither synthesizes Auth claims nor accepts malformed secrets', () => {
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  assert.equal(totpFromPrivateSecret(secret, 59000), '287082'); assert.equal(totpFromPrivateSecret(secret, 1111111109000), '081804');
  assert.throws(() => totpFromPrivateSecret('bad-secret'), { code: 'GENUINE_RUNTIME_MFA_REQUIRED' });
  assert.throws(() => decodeReceivedAccessToken('opaque-controlled-token'), { code: 'ONLINE_SESSION_ROW_PROOF_REQUIRED' });
});
test('real sign-in path keeps password private and rejects substituted returned Auth ID before row verification', async () => {
  let rows = 0; const local = controlledHttps({ response: { user: { id: freshId() }, access_token: 'opaque-controlled-token' } });
  const auth = createAuthClient({ transport: local.transport, privateActors: async () => ({ id: authIds.proposer,
    email: 'w5-proposer@jentra.invalid', password: 'controlled-only-password' }), readServerSession: async () => { rows++; } });
  await assert.rejects(auth.acquire({ scopeKey: 'runtime', actorLabel: 'proposer', ordinal: 0 }, false), { code: 'ONLINE_SESSION_ROW_PROOF_REQUIRED' });
  assert.equal(rows, 0); assert.equal(local.requests.length, 1); assert.equal(local.requests[0].url, `${PROJECT_URL}/auth/v1/token?grant_type=password`);
  assert.equal(JSON.parse(local.requests[0].bytes).password, 'controlled-only-password');
});
test('operator cannot enter Auth load acquisition or read another private session', async () => {
  let accesses = 0; const local = controlledHttps(); const auth = createAuthClient({ transport: local.transport,
    privateActors: async () => { accesses++; }, readServerSession: async () => {} });
  await assert.rejects(auth.acquire({ actorLabel: 'operator' }, false), { code: 'SESSION_ACTOR_MISMATCH' });
  assert.throws(() => auth.privateConnection({}), { code: 'SESSION_ACTOR_MISMATCH' }); assert.equal(accesses, 0);
});

function controlledPg(rowsByQuery = {}) {
  const calls = []; let clients = 0, connected = 0, commits = 0, rollbacks = 0;
  class PgClient {
    constructor(config) { this.id = ++clients; this.config = config; }
    async connect() { connected++; }
    async end() {}
    async query(sql, values) {
      calls.push({ client: this.id, sql, values });
      if (sql === 'COMMIT') { commits++; return { rows: [] }; }
      if (sql === 'ROLLBACK') { rollbacks++; return { rows: [] }; }
      if (sql === READ_QUERIES.transactionMetadata) return { rows: [{ backend_id: this.id, snapshot_id: '1:2:',
        observed_at: new Date(), isolation: 'repeatable read', read_only: 'on' }] };
      const value = rowsByQuery[sql]; if (value instanceof Error) throw value;
      return { rows: value ?? [] };
    }
  }
  return { PgClient, calls, counts: () => ({ clients, connected, commits, rollbacks }) };
}
test('read store constructor performs no I/O; exact catalog query runs in committed read-only repeatable-read transaction', async () => {
  const local = controlledPg({ [READ_QUERIES.sourcePopulation]: [{ opportunity_rows: '2', process_event_rows: '6', active_currency_codes: '11' }] });
  const store = createSupabaseReadStore({ review, authIds, PgClient: local.PgClient, databaseConfig }); assert.equal(local.counts().connected, 0);
  const proof = await store.read('sourcePopulation', { scopeKey: 'runtime' }); assert.equal(proof.querySha256, READ_QUERY_SHA256.sourcePopulation);
  assert.equal(proof.committed, true); assert.deepEqual(local.calls.map(call => call.sql), [
    'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY', READ_QUERIES.sourcePopulation, READ_QUERIES.transactionMetadata, 'COMMIT' ]);
  assert.deepEqual(local.calls[1].values, [scope.tenantId]); assert.ok(!JSON.stringify(proof).includes(databaseConfig.password));
});
test('batch proofs bind actual SQL recipe and share one fresh backend/snapshot', async () => {
  const local = controlledPg(), store = createSupabaseReadStore({ review, authIds, PgClient: local.PgClient, databaseConfig });
  const proof = await store.readBatch([{ name: 'scopeSnapshot', args: { scopeKey: 'load-001' } },
    { name: 'invocationProvenance', args: { scopeKey: 'load-001', invocationIds: [] } }]);
  assert.equal(proof.querySha256, committedRecipeHash(CASE_READ_RECIPES.quota)); assert.equal(local.counts().clients, 1);
  assert.ok(local.calls.every(call => call.client === 1)); assert.equal(proof.rows.invocationProvenance.length, 0);
});

test('quota request preserves the exact PostgreSQL microsecond trial period through committed reads and RPC mapping', async () => {
  const periodStart = '2026-10-12 09:43:42.764619+00', periodEnd = '2026-10-19 09:43:42.764619+00',
    target = review.syntheticScopes.find(s => s.key === 'load-001'),
    local = controlledPg({ [READ_QUERIES.subscription]: [{ id: freshId(), tenant_id: target.tenantId,
      period_start: periodStart, period_end: periodEnd, delivery_cap: '10', delivery_enabled: true, status: 'trialing' }] });
  const store = createSupabaseReadStore({ review, authIds, PgClient: local.PgClient, databaseConfig });
  const proof = await store.read('subscription', { scopeKey: target.key }), row = proof.rows[0],
    request = { scopeKey: target.key, commandId: freshId(), metric: 'webhook.deliveries', quantity: '1' },
    mapped = mappedRpcRequest({ operation: 'reserveOne', request, scope: target,
      fixture: { periodStart: row.period_start, periodEnd: row.period_end }, calendar });
  assert.match(local.calls[1].sql, /coalesce\(s\.trial_started_at,s\.created_at\)::text AS period_start/);
  assert.match(local.calls[1].sql, /s\.trial_ends_at::text AS period_end/);
  assert.equal(mapped.body.p_period_start, periodStart); assert.equal(mapped.body.p_period_end, periodEnd);
  assert.notEqual(mapped.body.p_period_start, new Date(periodStart).toISOString()); await store.close();
});
test('invalid query, unknown tenant, extra Auth actor and non-reviewed invitation cohort cannot open DB connections', async () => {
  const local = controlledPg(), store = createSupabaseReadStore({ review, authIds, PgClient: local.PgClient, databaseConfig });
  for (const [name, args] of [['SELECT password FROM auth.users', {}], ['scopeSnapshot', { scopeKey: 'other-company' }],
    ['serverSession', { actorId: freshId(), sessionId: freshId() }], ['invitationProvenance', { scopeKey: 'runtime', cohort: [] }]]) {
    await assert.rejects(store.read(name, args));
  }
  assert.equal(local.counts().connected, 0);
});
test('private DB targets require exact project or official project-suffixed pooler with verified TLS', () => {
  assert.equal(validatePrivateDatabaseTarget(databaseConfig), true);
  assert.equal(validatePrivateDatabaseTarget({ ...databaseConfig, host: 'aws-1-ap-south-1.pooler.supabase.com', user: `postgres.${PROJECT_ID}` }), true);
  for (const extra of [{ host: 'db.another.supabase.co' }, { ssl: { rejectUnauthorized: false } }, { connectionString: 'private://override' },
    { host: 'aws-1-ap-south-1.pooler.supabase.com', user: 'postgres.other' }, { ssl: { rejectUnauthorized: true, checkServerIdentity() {} } }]) {
    assert.throws(() => validatePrivateDatabaseTarget({ ...databaseConfig, ...extra }), { code: 'EXACT_DEVELOPMENT_TARGET_REQUIRED' });
  }
});
test('post-construction target/TLS changes cannot redirect later read or membership connections', async () => {
  const input = context(), config = { ...databaseConfig, ssl: { rejectUnauthorized: true, ca: Buffer.from('controlled-ca') } },
    configs = [];
  const base = controlledPg();
  class CaptureClient extends base.PgClient { constructor(connection) { super(connection); configs.push(connection); } }
  const store = createSupabaseReadStore({ review, authIds, PgClient: CaptureClient, databaseConfig: config }),
    fixture = createMembershipFixture({ executionContext: input, authIds, PgClient: CaptureClient, databaseConfig: config,
      preparationJournal: controlledPreparationJournal(input) });
  config.host = 'attacker.invalid'; config.user = 'another-project'; config.database = 'other'; config.ssl.rejectUnauthorized = false;
  config.ssl.checkServerIdentity = () => {}; config.ssl.ca.fill(120);
  await store.read('sourcePopulation', { scopeKey: 'runtime' });
  // Controlled rows absent: fixture fails at exact preparation after its correctly bound connection.
  await assert.rejects(fixture.prepare({}), { code: 'EXACT_RACE_PREPARATION_REQUIRED' });
  assert.equal(configs.length, 2);
  for (const sent of configs) {
    assert.equal(sent.host, databaseConfig.host); assert.equal(sent.user, 'postgres'); assert.equal(sent.database, 'postgres');
    assert.equal(sent.ssl.rejectUnauthorized, true); assert.equal(sent.ssl.checkServerIdentity, undefined); assert.equal(sent.ssl.ca.toString(), 'controlled-ca');
  }
  configs[0].ssl.ca.fill(100); await store.read('sourcePopulation', { scopeKey: 'runtime' });
  assert.equal(configs[2].ssl.ca.toString(), 'controlled-ca'); await store.close();
});
test('failed read rolls back, never commits, and redacts PostgreSQL private error', async () => {
  const local = controlledPg({ [READ_QUERIES.sourcePopulation]: new Error('private-password=in-error') });
  const store = createSupabaseReadStore({ review, authIds, PgClient: local.PgClient, databaseConfig });
  await assert.rejects(store.read('sourcePopulation', { scopeKey: 'runtime' }), { code: 'PROVIDER_FAILURE' });
  assert.equal(local.counts().commits, 0); assert.equal(local.counts().rollbacks, 1);
});
test('only exact integer strings convert; fractional/overflow/rounded quotas and versions are rejected', () => {
  assert.equal(exactInteger('10.000000'), 10); assert.equal(exactInteger('9007199254740991'), Number.MAX_SAFE_INTEGER);
  for (const value of ['10.000001', '9007199254740992', '-1', '01', 1.2, Infinity, '1e3']) assert.throws(() => exactInteger(value));
});
test('server session proof requires a committed row for the exact six actual actor IDs and selects no credential columns', async () => {
  const sessionId = freshId(), local = controlledPg({ [READ_QUERIES.serverSession]: [{ id: sessionId, user_id: authIds.proposer,
    aal: 'aal1', factor_id: null, not_after: null }] });
  const store = createSupabaseReadStore({ review, authIds, PgClient: local.PgClient, databaseConfig });
  const proof = await store.readServerSession({ sessionId, actorId: authIds.proposer }); assert.equal(proof.id, sessionId); assert.equal(proof.committed, true);
  assert.ok(!/refresh_token|password|user_agent|ip\b/.test(READ_QUERIES.serverSession));
});

test('every mapped load/race operation uses exact reviewed signature parameters and private tokens have no invented command', () => {
  const command = freshId(), resource = freshId(); const fixture = { public: { originalCommandId: command, idempotencyKey: command, resourceId: resource },
    clientTimestamp: calendar.clientTimestamp, periodStart: calendar.windowStart, periodEnd: calendar.windowEnd };
  const request = { scopeKey: scope.key, commandId: command, idempotencyKey: command, phase: 'race', metric: 'webhook.deliveries',
    quantity: '1', runtimeId: '778237e3-3d4e-4871-8cc9-e08b07b989c7' };
  const token = 'a'.repeat(64), expected = { forecast: 8, analytics: 7, indexedForecastRead: 4, indexedBillingRead: 1,
    acceptInvitation: 1, reserveOne: 6, activate: 2, executeProposal: 8, claimLease: 3 };
  for (const [operation, count] of Object.entries(expected)) {
    const value = mappedRpcRequest({ operation, request, scope, fixture, calendar, forecastId: resource, privateInvitation: { token } });
    assert.equal(Object.keys(value.body).length, count); assert.ok(value.route.startsWith('/rest/v1/rpc/'));
    if (operation === 'acceptInvitation') assert.deepEqual(value.body, { p_token: token });
    if (operation === 'activate') assert.deepEqual(value.body, { p_tenant_id: scope.tenantId, p_revision_id: resource });
    if (operation === 'reserveOne') assert.equal(value.body.p_quantity, '1');
  }
});
test('mapper rejects changed command, wrong runtime, changed scope and arbitrary operations', () => {
  const command = freshId(), request = { scopeKey: 'runtime', phase: 'race', commandId: command, idempotencyKey: command },
    fixture = { public: { originalCommandId: command, idempotencyKey: command, resourceId: freshId() }, clientTimestamp: calendar.clientTimestamp };
  for (const extra of [{ operation: 'forecast', request: { ...request, commandId: freshId() } }, { operation: 'claimLease' },
    { operation: 'forecast', scope: { ...scope, key: 'foreign' } }, { operation: 'arbitraryRpc' }]) {
    assert.throws(() => mappedRpcRequest({ operation: 'forecast', request, scope, fixture, calendar, ...extra }));
  }
});
test('outcomes verify returned original command; only exact actual Postgres denials are accepted and server spans stay absent', () => {
  const command = freshId(), request = { commandId: command }, response = { ok: true, value: { command_id: command, request_id: freshId(), correlation_id: freshId(), entity: { id: freshId() } },
    responseSha256: sha('response'), transportEvidenceSha256: sha('transport') };
  const success = outcomeFromRpc({ operation: 'forecast', request, response }); assert.equal(success.serverSpan, null);
  assert.equal(success.originalCommandId, command);
  assert.throws(() => outcomeFromRpc({ operation: 'forecast', request, response: { ...response, value: { ...response.value, command_id: freshId() } } }));
  assert.throws(() => outcomeFromRpc({ operation: 'forecast', request, response: { ...response, value: { request_id: command, entity: { id: freshId() } } } }));
  assert.equal(outcomeFromRpc({ operation: 'activate', request,
    response: { ...response, value: { request_id: command, entity: { id: freshId() } } } }).outcome, 'applied');
  for (const [value, outcome] of [[{ message: 'QUOTA_EXCEEDED', code: '54000' }, 'denied'], [{ message: 'QUOTA_EXCEEDED', code: '42501' }, 'uncertain'],
    [{ message: 'password=in-error', code: '54000' }, 'uncertain']]) {
    assert.equal(outcomeFromRpc({ operation: 'reserveOne', request, response: { ...response, ok: false, value } }).outcome, outcome);
  }
  assert.equal(outcomeFromRpc({ operation: 'claimLease', request, response: { ...response, value: null } }).outcome, 'empty');
});

test('indexed billing reads bind the exact tenant and the existing runtime/load-001 activation allowlist', () => {
  for (const scopeKey of ['runtime', 'load-001', 'load-002']) {
    const target = review.syntheticScopes.find(s => s.key === scopeKey), request = { scopeKey },
      value = { contractRevision: 1, id: freshId(), tenantId: target.tenantId, version: '3', seats: '4',
        syntheticTarget: ['runtime', 'load-001'].includes(scopeKey) },
      response = { ok: true, value, responseSha256: sha('response'), transportEvidenceSha256: sha('transport') },
      invoke = result => outcomeFromRpc({ operation: 'indexedBillingRead', request, scope: target, response: { ...response, value: result } });
    assert.equal(invoke(value).outcome, 'applied');
    assert.throws(() => invoke({ ...value, tenantId: freshId() }), { code: 'INVALID_PROVIDER_OUTCOME' });
    assert.throws(() => invoke({ ...value, syntheticTarget: !value.syntheticTarget }), { code: 'INVALID_PROVIDER_OUTCOME' });
    assert.throws(() => outcomeFromRpc({ operation: 'indexedBillingRead', request: { scopeKey: 'foreign' }, scope: target, response }),
      { code: 'INVALID_PROVIDER_OUTCOME' });
  }
});
test('calendar rejects impossible dates, inverted windows, future recorded evidence and 367-day supported workload', () => {
  assert.equal(validateProviderCalendar(calendar).horizonStart, calendar.horizonStart);
  for (const extra of [{ horizonStart: '2026-02-30' }, { horizonEnd: calendar.horizonStart }, { windowEnd: calendar.windowStart },
    { recordedThrough: '2100-01-01T00:00:00Z' }, { horizonEnd: '2028-01-01' }, { clientTimestamp: null }]) assert.throws(() => validateProviderCalendar({ ...calendar, ...extra }));
});
test('scheduled activation binds exact approved synthetic plan, seven-day server window and allowed race seats', () => {
  for (const scopeKey of ['runtime', 'load-001']) {
    const target = review.syntheticScopes.find(s => s.key === scopeKey), actual = { id: freshId(), plan_code: target.planCode, version: '19' },
      serverAt = '2026-10-12T09:43:42.764Z', seats = scopeKey === 'runtime' ? 5 : 2;
    const window = reviewedTrialWindow(review, target, actual, seats, serverAt);
    assert.equal(window.planCode, target.planCode); assert.equal(window.expectedVersion, '19');
    assert.equal(Date.parse(window.ends) - Date.parse(window.starts), 7 * 86400000);
    assert.throws(() => reviewedTrialWindow(review, target, { ...actual, plan_code: 'arbitrary-plan' }, seats, serverAt));
    assert.throws(() => reviewedTrialWindow(review, target, actual, 100, serverAt));
    assert.throws(() => reviewedTrialWindow(review, { ...target, tenantId: freshId() }, actual, seats, serverAt));
  }
});
test('provider revalidates approval and bundle before touching any private getter or client', () => {
  let accesses = 0; const privateConfig = new Proxy({}, { get() { accesses++; return undefined; } });
  const input = context(); input.review = { ...input.review, projectId: 'other' };
  assert.throws(() => createSupabaseRuntimeProvider({ executionContext: input, privateConfig }), { code: 'RUNTIME_BUNDLE_HASH_MISMATCH' }); assert.equal(accesses, 0);
});
test('provider denies wrong query/calendar/dependency bindings before constructing any DB/HTTPS clients', () => {
  const local = controlledPg(), input = context(); let agentCalls = 0;
  const config = { projectId: PROJECT_ID, privateActors: async () => {}, verifyOnlinePreflight: async () => {}, observeExternalTransport: async () => {},
    PgClient: local.PgClient, databaseConfig, authIds, anonKey: 'controlled-anon-key', calendar,
    privateConfigSourceSha256: input.binding.privateProviderSha256, postgresDriverSourceSha256: input.plan.postgresDriverSourceSha256,
    ...privatePreparationConfig(input) };
  assert.throws(() => createSupabaseRuntimeProvider({ executionContext: input, privateConfig: { ...config, calendar: { ...calendar, clientTimestamp: '2026-10-11T00:00:00Z' } },
    agentFactory() { agentCalls++; } }), { code: 'PREPARATION_BINDING_MISMATCH' });
  const provider = createSupabaseRuntimeProvider({ executionContext: input, privateConfig: config, agentFactory() { agentCalls++; } });
  assert.equal(local.counts().connected, 0); assert.equal(agentCalls, 0); assert.equal(typeof provider.openSessions, 'function');
});
test('uninstalled/capacity-incomplete preflight fails before Auth acquisition or user RPC/fixture mutation', async () => {
  const local = controlledPg(), input = context(); let actors = 0;
  const provider = createSupabaseRuntimeProvider({ executionContext: input, privateConfig: { projectId: PROJECT_ID,
    privateActors: async () => { actors++; }, verifyOnlinePreflight: async () => ({ kind: 'not-installed' }), observeExternalTransport: async () => {},
    PgClient: local.PgClient, databaseConfig, authIds, anonKey: 'controlled-anon-key', calendar,
    privateConfigSourceSha256: input.binding.privateProviderSha256, postgresDriverSourceSha256: input.plan.postgresDriverSourceSha256,
    ...privatePreparationConfig(input) } });
  await assert.rejects(provider.verifyPreflight({}), { code: 'ONLINE_PREFLIGHT_BINDING_REQUIRED' });
  await assert.rejects(provider.openSessions({}), { code: 'ONLINE_PREFLIGHT_BINDING_REQUIRED' }); assert.equal(actors, 0); assert.equal(local.counts().connected, 0);
});

test('caller callback replacement after construction cannot replace the reviewed preflight path', async () => {
  const local = controlledPg(), input = context(); let originalCalls = 0, replacementCalls = 0;
  const config = { projectId: PROJECT_ID, privateActors: async () => {},
    verifyOnlinePreflight: async () => { originalCalls++; return { kind: 'not-installed' }; },
    observeExternalTransport: async () => {}, PgClient: local.PgClient, databaseConfig,
    authIds, anonKey: 'controlled-anon-key', calendar,
    privateConfigSourceSha256: input.binding.privateProviderSha256,
    postgresDriverSourceSha256: input.plan.postgresDriverSourceSha256, ...privatePreparationConfig(input) };
  const provider = createSupabaseRuntimeProvider({ executionContext: input, privateConfig: config });
  config.verifyOnlinePreflight = async () => { replacementCalls++; throw Error('unreviewed callback'); };
  config.privateActors = async () => { replacementCalls++; throw Error('unreviewed actor factory'); };
  config.authConcurrency = 2000; config.serviceRoleKey = 'unreviewed-private-key';
  await assert.rejects(provider.verifyPreflight({}), { code: 'ONLINE_PREFLIGHT_BINDING_REQUIRED' });
  assert.equal(originalCalls, 1); assert.equal(replacementCalls, 0); assert.equal(local.counts().connected, 0);
  await provider.close();
});
test('Auth ID labels are order-independent, but a substituted creation ID stops before any installed read', async () => {
  const input = context(), controlledProof = { kind: 'online-installed-wave5-harness-preflight', projectId: PROJECT_ID, url: PROJECT_URL,
    runtimeBundleSha256: review.bundleSha256, harnessReviewSha256: input.binding.harnessReviewSha256, planSha256: input.binding.planSha256,
    observedAt: new Date().toISOString(), validUntil: new Date(Date.now() + 1800000).toISOString(), installedMigrationCount: 114,
    pending71Installed: true, originalSixPreserved: true, signaturesGrantsForcedRlsVerified: true, protectedSourcesUnchanged: true,
    scopeDigestSha256: hashJson(review.syntheticScopes), capacitySupported: true, noGlobalAuthChanges: true, noFabricatedAuth: true,
    noAcceptanceScopes: true, ledgerSha256: sha('local-ledger-input'), contractFingerprintSha256: sha('local-contract-input'),
    capacityEvidenceSha256: sha('local-capacity-input'), rowDistributionSha256: sha('local-distribution-input'), authCreationEvidenceSha256: sha('local-creation-input'),
    fixturePopulationSha256: sha('local-population-input'), fixtureCapsVerified: true, nonemptyIndexedForecastsAll500: true,
    nonemptyProcessSourcesAll500: true, reviewedSchedulesQuiesced: true, noModelOrWebhookInLoad: true, operatorMembershipCount: 0,
    environment: { region: 'controlled', databaseTier: 'controlled', postgresVersion: 'controlled', generatorHost: 'controlled',
      cacheConditions: 'controlled', hardwareSha256: sha('local-hardware-input'), maximumConcurrentSessions: 2000, maximumRequestsPerSecond: 20 } };
  for (const substitute of [false, true]) {
    const local = controlledPg(), orderedIds = Object.fromEntries(Object.entries(authIds).reverse());
    if (substitute) orderedIds.proposer = freshId();
    const provider = createSupabaseRuntimeProvider({ executionContext: input, privateConfig: { projectId: PROJECT_ID, privateActors: async () => {},
      verifyOnlinePreflight: async () => ({ ...controlledProof, authIds: orderedIds }), observeExternalTransport: async () => {},
      PgClient: local.PgClient, databaseConfig, authIds, anonKey: 'controlled-anon-key', calendar,
      privateConfigSourceSha256: input.binding.privateProviderSha256, postgresDriverSourceSha256: input.plan.postgresDriverSourceSha256,
      ...privatePreparationConfig(input) } });
    await assert.rejects(provider.verifyPreflight({}), { code: substitute ? 'EXACT_REAL_AUTH_IDS_REQUIRED' : 'INSTALLATION_CONTRACT_DRIFT' });
    assert.equal(local.counts().connected, substitute ? 0 : 1); await provider.close();
  }
});

test('membership fixture requires reviewed context before constructing a mutation client', () => {
  const local = controlledPg(), input = context(); input.approval = { ...owner, decision: 'deny' };
  assert.throws(() => createMembershipFixture({ executionContext: input, authIds, PgClient: local.PgClient, databaseConfig }), { code: 'EXPLICIT_OWNER_APPROVAL_REQUIRED' });
  assert.equal(local.counts().clients, 0);
});
test('membership fixture SQL never deletes history, rewinds versions, touches Auth or changes targets through interpolation', () => {
  for (const sql of Object.values(MEMBERSHIP_FIXTURE_SQL)) assert.ok(!/\bdelete\b|auth\.|set\s+version|truncate|alter|disable\s+trigger/i.test(sql));
  for (const name of ['suspend', 'seats', 'restoreMember', 'revokeExactUnused']) assert.ok(MEMBERSHIP_FIXTURE_SQL[name].includes('tenant_id=$1::uuid'));
});

test('membership preparation/restoration commit exact rows and raise original cap before reactivation', async () => {
  const input = context(), target = review.syntheticScopes.find(s => s.key === 'load-001'), roleId = freshId();
  const subscription = { id: freshId(), seats: 4, version: '1' };
  const members = ['approver', 'executor'].map(label => ({ id: freshId(), user_id: authIds[label], status: 'active', version: '1' }));
  const assignments = members.map(row => ({ id: freshId(), membership_id: row.id, role_id: roleId, legal_entity_id: target.entityId, branch_id: target.branchId }));
  const order = [];
  class FixtureClient {
    async connect() {} async end() {}
    async query(sql, values) {
      order.push({ sql, values });
      if (sql === MEMBERSHIP_FIXTURE_SQL.subscription) return { rows: [structuredClone(subscription)] };
      if (sql === MEMBERSHIP_FIXTURE_SQL.memberships) return { rows: structuredClone(members) };
      if (sql === MEMBERSHIP_FIXTURE_SQL.assignments) return { rows: structuredClone(assignments) };
      if (sql === MEMBERSHIP_FIXTURE_SQL.occupied) return { rows: [{ occupied: String(2 + members.filter(m => m.status === 'active').length) }] };
      if (sql === MEMBERSHIP_FIXTURE_SQL.suspend || sql === MEMBERSHIP_FIXTURE_SQL.restoreMember) {
        const row = members.find(m => m.id === values[1]);
        // Independent controlled seat trigger: this would reject a restore in the wrong order.
        if (sql === MEMBERSHIP_FIXTURE_SQL.restoreMember && row.status !== 'active'
          && 2 + members.filter(m => m.status === 'active').length >= subscription.seats) throw new Error('seat cap');
        assert.equal(values[0], target.tenantId); assert.equal(values[2], row.user_id); assert.equal(values[3], row.version);
        row.status = sql === MEMBERSHIP_FIXTURE_SQL.suspend ? 'suspended' : 'active'; row.version = String(Number(row.version) + 1);
        return { rowCount: 1, rows: [{ id: row.id }] };
      }
      if (sql === MEMBERSHIP_FIXTURE_SQL.seats) {
        assert.equal(values[0], target.tenantId); assert.equal(values[2], subscription.id); assert.equal(values[3], subscription.version);
        subscription.seats = values[1]; subscription.version = String(Number(subscription.version) + 1); return { rowCount: 1, rows: [structuredClone(subscription)] };
      }
      return { rows: [] };
    }
  }
  const fixture = createMembershipFixture({ executionContext: input, authIds, PgClient: FixtureClient, databaseConfig,
    preparationJournal: controlledPreparationJournal(input) });
  const prepared = await fixture.prepare({}); assert.equal(prepared.committed, true); assert.equal(subscription.seats, 3);
  assert.ok(members.every(row => row.status === 'suspended')); const preparedVersions = members.map(row => row.version);
  subscription.seats = 2; subscription.version = String(Number(subscription.version) + 1); // controlled activation-wins branch
  const beforeRestore = order.length, restored = await fixture.restore({});
  assert.equal(restored.committed, true); assert.equal(subscription.seats, 4); assert.ok(members.every(row => row.status === 'active'));
  const restoreQueries = order.slice(beforeRestore), raiseAt = restoreQueries.findIndex(call => call.sql === MEMBERSHIP_FIXTURE_SQL.seats),
    reactivateAt = restoreQueries.findIndex(call => call.sql === MEMBERSHIP_FIXTURE_SQL.restoreMember);
  assert.ok(raiseAt >= 0 && raiseAt < reactivateAt); assert.ok(members.every((row, i) => Number(row.version) > Number(preparedVersions[i])));
  assert.equal(order.filter(call => call.sql === 'COMMIT').length, 2); assert.equal(order.filter(call => call.sql === 'ROLLBACK').length, 0);
});
test('unknown membership COMMIT outcome retains original state evidence and forbids subsequent retries/restoration', async () => {
  const input = context(), target = review.syntheticScopes.find(s => s.key === 'load-001'), roleId = freshId(), members = ['approver', 'executor']
    .map(label => ({ id: freshId(), user_id: authIds[label], status: 'active', version: '1' })); let connects = 0;
  class UncertainClient {
    async connect() { connects++; } async end() {}
    async query(sql) {
      if (sql === MEMBERSHIP_FIXTURE_SQL.subscription) return { rows: [{ id: freshId(), seats: 4, version: '1' }] };
      if (sql === MEMBERSHIP_FIXTURE_SQL.memberships) return { rows: members };
      if (sql === MEMBERSHIP_FIXTURE_SQL.assignments) return { rows: members.map(row => ({ id: freshId(), membership_id: row.id, role_id: roleId,
        legal_entity_id: target.entityId, branch_id: target.branchId })) };
      if (sql === MEMBERSHIP_FIXTURE_SQL.occupied) return { rows: [{ occupied: '2' }] };
      if (sql === 'COMMIT') throw new Error('private ambiguous connection failure');
      return { rowCount: 1, rows: [] };
    }
  }
  const fixture = createMembershipFixture({ executionContext: input, authIds, PgClient: UncertainClient, databaseConfig,
    preparationJournal: controlledPreparationJournal(input) });
  await assert.rejects(fixture.prepare({}), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  await assert.rejects(fixture.restore({}), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' });
  await assert.rejects(fixture.prepare({}), { code: 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' }); assert.equal(connects, 1);
});

test('membership baseline, original assignments and SQL intent persist before any suspend/cap change or COMMIT', async () => {
  const input = context(), target = review.syntheticScopes.find(s => s.key === 'load-001'), roleId = freshId(), records = [], order = [],
    subscription = { id: freshId(), seats: 4, version: '1' }, members = ['approver', 'executor']
      .map(label => ({ id: freshId(), user_id: authIds[label], status: 'active', version: '1' })),
    assignments = members.map(row => ({ id: freshId(), membership_id: row.id, role_id: roleId, legal_entity_id: target.entityId, branch_id: target.branchId }));
  class FixtureClient {
    async connect() {} async end() {}
    async query(sql, values) {
      order.push({ sql, values });
      if (sql === MEMBERSHIP_FIXTURE_SQL.subscription) return { rows: [subscription] };
      if (sql === MEMBERSHIP_FIXTURE_SQL.memberships) return { rows: members };
      if (sql === MEMBERSHIP_FIXTURE_SQL.assignments) return { rows: assignments };
      if (sql === MEMBERSHIP_FIXTURE_SQL.occupied) return { rows: [{ occupied: '2' }] };
      return { rows: [], rowCount: 1 };
    }
  }
  const preparationJournal = controlledPreparationJournal(input, async record => { records.push(record); order.push({ phase: record.phase, action: record.action });
    return preparationReceipt(record); });
  const fixture = createMembershipFixture({ executionContext: input, authIds, PgClient: FixtureClient, databaseConfig, preparationJournal });
  await fixture.prepare({ caseId: input.plan.cases.find(value => value.kind === 'seats').caseId });
  const baseline = records.find(record => record.action === 'membership-baseline'); assert.ok(baseline);
  assert.deepEqual(baseline.details.original.memberships, members); assert.deepEqual(baseline.details.original.assignments, assignments);
  const firstWrite = order.findIndex(row => row.sql === MEMBERSHIP_FIXTURE_SQL.suspend);
  assert.ok(order.findIndex(row => row.action === 'membership-baseline') < firstWrite);
  assert.ok(order.findIndex(row => row.action === 'membership-suspend' && row.phase === 'intent') < firstWrite);
  const commit = order.findIndex(row => row.sql === 'COMMIT'); assert.ok(commit > 0);
  assert.ok(order.findIndex(row => row.action === 'membership-commit' && row.phase === 'intent') < commit);
  assert.ok(order.findIndex(row => row.action === 'membership-commit' && row.phase === 'confirmed') > commit);
});

test('failed membership baseline persistence prevents administrative writes and never falls back to an in-memory-only fixture', async () => {
  const input = context(), target = review.syntheticScopes.find(s => s.key === 'load-001'), roleId = freshId(), writes = [],
    members = ['approver', 'executor'].map(label => ({ id: freshId(), user_id: authIds[label], status: 'active', version: '1' }));
  class FixtureClient {
    async connect() {} async end() {}
    async query(sql) {
      if (sql === MEMBERSHIP_FIXTURE_SQL.subscription) return { rows: [{ id: freshId(), seats: 4, version: '1' }] };
      if (sql === MEMBERSHIP_FIXTURE_SQL.memberships) return { rows: members };
      if (sql === MEMBERSHIP_FIXTURE_SQL.assignments) return { rows: members.map(row => ({ id: freshId(), membership_id: row.id,
        role_id: roleId, legal_entity_id: target.entityId, branch_id: target.branchId })) };
      if (sql === MEMBERSHIP_FIXTURE_SQL.occupied) return { rows: [{ occupied: '2' }] };
      if (/^UPDATE|^COMMIT/.test(sql)) writes.push(sql); return { rows: [], rowCount: 1 };
    }
  }
  const fixture = createMembershipFixture({ executionContext: input, authIds, PgClient: FixtureClient, databaseConfig,
    preparationJournal: controlledPreparationJournal(input, async () => { throw new Error('private persistence failure'); }) });
  await assert.rejects(fixture.prepare({ caseId: input.plan.cases.find(value => value.kind === 'seats').caseId })); assert.equal(writes.length, 0);
});
