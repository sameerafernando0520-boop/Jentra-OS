import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import { PROJECT_ID, PROJECT_URL, freshId, hashJson, GuardError, publicOutcome, safeFailure, RACE_KINDS } from './runtime_contract.mjs';
import { createSupabaseReadStore, READ_QUERIES, READ_QUERY_SHA256, committedRecipeHash, snapshotPrivateDatabaseConfig } from './supabase_read_store.mjs';
import { createSupabaseRuntimeProvider, mappedRpcRequest, outcomeFromRpc, CASE_READ_RECIPES } from './supabase_runtime_provider.mjs';
import { createSupabaseHttpsTransport } from './supabase_http_transport.mjs';
import { FIXTURE_CAPS, RACE_FIXTURES, INVALID_BOUNDARIES } from './runtime_fixture_spec.mjs';

// Independent local probes only. No real credential, JWT, connection, Auth row,
// server, network request, database mutation, SDK job or acceptance store is used.
const review = JSON.parse(await fs.readFile(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json', import.meta.url)));
const actorIds = Object.fromEntries(review.accounts.map(actor => [actor.label, freshId()]));
const load = review.syntheticScopes.find(scope => scope.key === 'load-001');
const calendar = { clientTimestamp: '2026-10-12T00:00:00.000Z' };
const response = value => ({ ok: true, value, responseSha256: hashJson(['controlled', value]), transportEvidenceSha256: hashJson('controlled-transport') });
const privateDatabase = () => ({ host: `db.${PROJECT_ID}.supabase.co`, port: 5432, database: 'postgres', user: 'postgres',
  password: 'LOCAL_CONTROLLED_PLACEHOLDER', ssl: { rejectUnauthorized: true, ca: Buffer.from('LOCAL_CONTROLLED_CA') } });

function captureDriver(readQueries = READ_QUERIES) {
  const configs = [], calls = [];
  class PgClient {
    constructor(config) { this.config = config; this.backendId = configs.push(config); }
    async connect() {}
    async end() {}
    async query(sql, values) {
      calls.push({ sql, values });
      if (sql === readQueries.transactionMetadata) return { rows: [{ backend_id: this.backendId, snapshot_id: '10:11:',
        observed_at: new Date(), isolation: 'repeatable read', read_only: 'on' }] };
      if (sql === readQueries.sourcePopulation) return { rows: [{ opportunity_rows: '2', process_event_rows: '4', active_currency_codes: '11' }] };
      return { rows: [] };
    }
  }
  return { PgClient, configs, calls };
}

async function verifyDatabaseIsolation(module = { createSupabaseReadStore, READ_QUERIES }) {
  const input = privateDatabase(), driver = captureDriver(module.READ_QUERIES);
  const store = module.createSupabaseReadStore({ review, authIds: actorIds, PgClient: driver.PgClient, databaseConfig: input });
  input.host = 'LOCAL_UNAUTHORIZED_TARGET.invalid'; input.password = 'LOCAL_CHANGED_PLACEHOLDER';
  input.ssl.rejectUnauthorized = false; input.ssl.ca.fill(120);
  await store.read('sourcePopulation', { scopeKey: 'runtime' });
  assert.equal(driver.configs[0].host, `db.${PROJECT_ID}.supabase.co`);
  assert.equal(driver.configs[0].password, 'LOCAL_CONTROLLED_PLACEHOLDER');
  assert.equal(driver.configs[0].ssl.rejectUnauthorized, true);
  assert.equal(driver.configs[0].ssl.ca.toString(), 'LOCAL_CONTROLLED_CA');
  driver.configs[0].ssl.ca.fill(121);
  await store.read('sourcePopulation', { scopeKey: 'runtime' });
  assert.equal(driver.configs[1].ssl.ca.toString(), 'LOCAL_CONTROLLED_CA');
  assert.notEqual(driver.configs[0].ssl.ca, driver.configs[1].ssl.ca);
  await store.close();
}

const exactPeriod = { periodStart: '2026-10-12 09:43:42.764619+00', periodEnd: '2026-10-19 09:43:42.764619+00' };
function verifyQuotaPrecision(mapper = mappedRpcRequest) {
  const request = { scopeKey: load.key, commandId: freshId(), metric: 'webhook.deliveries', quantity: '1' };
  const mapped = mapper({ operation: 'reserveOne', request, scope: load, fixture: exactPeriod, calendar });
  assert.equal(mapped.body.p_period_start, exactPeriod.periodStart);
  assert.equal(mapped.body.p_period_end, exactPeriod.periodEnd);
  assert.notEqual(mapped.body.p_period_start, new Date(exactPeriod.periodStart).toISOString());
}

function verifyBillingScopes(mapper = outcomeFromRpc) {
  for (const scope of review.syntheticScopes) {
    const value = { contractRevision: 1, id: freshId(), tenantId: scope.tenantId, version: '1', seats: scope.seats ?? 4,
      syntheticTarget: ['runtime', 'load-001'].includes(scope.key) };
    assert.equal(mapper({ operation: 'indexedBillingRead', request: { scopeKey: scope.key }, scope, response: response(value) }).outcome, 'applied');
    assert.throws(() => mapper({ operation: 'indexedBillingRead', request: { scopeKey: scope.key }, scope,
      response: response({ ...value, syntheticTarget: !value.syntheticTarget }) }), { code: 'INVALID_PROVIDER_OUTCOME' });
    assert.throws(() => mapper({ operation: 'indexedBillingRead', request: { scopeKey: scope.key }, scope,
      response: response({ ...value, tenantId: freshId() }) }), { code: 'INVALID_PROVIDER_OUTCOME' });
  }
}

async function mutatedModule(name, replacements) {
  const source = await fs.readFile(new URL(name, import.meta.url), 'utf8');
  let altered = source;
  for (const [before, after] of replacements) {
    assert.equal(altered.split(before).length - 1, 1, `Exact local mutation anchor absent: ${name}`);
    altered = altered.replace(before, after);
  }
  altered = altered.replace(/from '(\.\/[^']+)'/g, (_, relative) => `from '${new URL(relative, import.meta.url).href}'`);
  return import(`data:text/javascript;base64,${Buffer.from(altered).toString('base64')}`);
}

test('independent DB/TLS probe preserves target, password and CA bytes after caller and earlier driver mutation', async () => {
  await verifyDatabaseIsolation();
});

test('independent regression probe detects reintroduced mutable DB configuration without changing current files', async () => {
  const mutant = await mutatedModule('supabase_read_store.mjs', [
    ['const privateDatabase = snapshotPrivateDatabaseConfig(databaseConfig);', 'const privateDatabase = databaseConfig;'],
    ['...snapshotPrivateDatabaseConfig(privateDatabase), connectionTimeoutMillis', '...privateDatabase, connectionTimeoutMillis'],
  ]);
  await assert.rejects(verifyDatabaseIsolation(mutant), assert.AssertionError);
});

test('independent quota mapper preserves server microseconds; both query fields are lossless PostgreSQL text', () => {
  verifyQuotaPrecision();
  assert.match(READ_QUERIES.subscription, /coalesce\(s\.trial_started_at,s\.created_at\)::text AS period_start/);
  assert.match(READ_QUERIES.subscription, /s\.trial_ends_at::text AS period_end/);
});

test('independent regression probe detects reintroduced JavaScript Date quota truncation', async () => {
  const mutant = await mutatedModule('supabase_runtime_provider.mjs', [
    ['p_period_start: fixture.periodStart, p_period_end: fixture.periodEnd',
      'p_period_start: new Date(fixture.periodStart).toISOString(), p_period_end: new Date(fixture.periodEnd).toISOString()'],
  ]);
  assert.throws(() => verifyQuotaPrecision(mutant.mappedRpcRequest), assert.AssertionError);
});

test('independent billing response probe checks all500 reviewed scopes and rejects the wrong target flag or tenant', () => {
  verifyBillingScopes();
});

const approval = JSON.parse(await fs.readFile(new URL('../../docs/verification/wave5/runtime-owner-decision-20261012-r5.json', import.meta.url)));
function callbackProbeContext() {
  const providerCalendar = { horizonStart: '2026-10-01', horizonEnd: '2026-11-01',
    windowStart: '2026-10-01T00:00:00Z', windowEnd: '2026-10-08T00:00:00Z',
    asOf: '2026-10-08T00:00:00Z', recordedThrough: '2026-10-08T00:00:00Z',
    clientTimestamp: '2026-10-12T00:00:00Z' };
  const providerSha = hashJson('independent-controlled-factory-reference');
  const plan = { kind: 'wave5-runtime-harness-plan', projectId: PROJECT_ID, url: PROJECT_URL,
    production: false, realBilling: false, runtimeBundleSha256: review.bundleSha256,
    warmupMs: 60000, measuredMs: 300000, maxRunMs: 900000, maximumTimedRequests: 20000,
    maxInflight: 2000, requestsPerSecond: 20, providerCalendarSha256: hashJson(providerCalendar),
    postgresDriverSourceSha256: hashJson('independent-controlled-driver'), preparationJournalSourceSha256: hashJson('independent-controlled-sink'),
    cases: RACE_KINDS.map(kind => ({ kind, caseId: freshId(), scopeKey: ['seats', 'admissions', 'quota'].includes(kind) ? 'load-001' : 'runtime',
      participants: kind === 'duplicates' ? 100 : kind === 'quota' ? 20 : 2, noExternalSend: true,
      fixturePlanSha256: hashJson([kind, 'fixture']), committedQuerySha256: committedRecipeHash(CASE_READ_RECIPES[kind]),
      preparationSha256: hashJson([kind, 'preparation']), restorationSha256: hashJson([kind, 'restoration']) })),
    boundaries: ['10001Rows', '101Groups', '367DayWindow', '8MiBPlus1Byte'].map(kind => ({ kind, scopeKey: 'runtime', caseId: freshId(),
      fixturePlanSha256: hashJson([kind, 'fixture']), committedQuerySha256: READ_QUERY_SHA256.scopeSnapshot, expectedCode: 'LIMIT_EXCEEDED' })),
    loadCommittedQuerySha256: READ_QUERY_SHA256.loadLedgers, loadFixturePlanSha256: hashJson('independent-load-fixture'),
    externalObservationSourceSha256: hashJson('independent-controlled-observer') };
  const binding = { runtimeFileSha256: approval.runtimeFileSha256, harnessReviewSha256: hashJson('independent-controlled-harness'),
    planSha256: hashJson(plan), planBodySha256: hashJson(plan), privateProviderSha256: providerSha };
  const independentReview = { kind: 'wave5-runtime-harness-independent-preparation-review', result: 'approved-for-existing-bounded-scope',
    projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256,
    harnessReviewSha256: binding.harnessReviewSha256, planSha256: binding.planSha256, privateProviderSha256: providerSha,
    sourceBindingsVerified: true, operationScopeSha256: review.sourceContinuation.unchangedRuntimeOperationScopeSha256,
    sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
  binding.independentReviewBodySha256 = hashJson(independentReview);
  const preparation = { kind: 'wave5-runtime-harness-preparation', sourceBindingsVerified: true,
    runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256, harnessReviewSha256: binding.harnessReviewSha256,
    planSha256: binding.planSha256, privateProviderSha256: providerSha, independentReview: {
      result: independentReview.result, path: 'independent-controlled-reference-only.json', sha256: hashJson(independentReview) },
    sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
  return { context: { review, plan, approval, preparation, independentReview, binding }, providerCalendar };
}
async function verifyCallbackSnapshot(factory = createSupabaseRuntimeProvider) {
  const { context, providerCalendar } = callbackProbeContext(); let originalCalls = 0, replacementCalls = 0, databaseCalls = 0;
  class NeverConnectedDriver {
    async connect() { databaseCalls++; throw Error('LOCAL_NO_DATABASE_ALLOWED'); }
    async end() {}
  }
  const config = { projectId: PROJECT_ID, calendar: providerCalendar, privateActors: async () => {},
    verifyOnlinePreflight: async () => { originalCalls++; return { kind: 'uninstalled-controlled-only' }; },
    observeExternalTransport: async () => {}, appendPreparationEvidence: async record => ({ durable: true, appendOnly: true,
      recordSha256: hashJson(record), storageEvidenceSha256: hashJson(['controlled-sink', record]) }),
    PgClient: NeverConnectedDriver, databaseConfig: privateDatabase(), authIds: actorIds, anonKey: 'LOCAL_CONTROLLED_ANON_KEY',
    privateConfigSourceSha256: context.binding.privateProviderSha256, postgresDriverSourceSha256: context.plan.postgresDriverSourceSha256,
    preparationJournalSourceSha256: context.plan.preparationJournalSourceSha256 };
  const provider = factory({ executionContext: context, privateConfig: config });
  config.verifyOnlinePreflight = async () => { replacementCalls++; return { kind: 'uninstalled-controlled-only' }; };
  config.privateActors = async () => { replacementCalls++; throw Error('LOCAL_UNREVIEWED_ACTOR_REFERENCE'); };
  config.observeExternalTransport = async () => { replacementCalls++; throw Error('LOCAL_UNREVIEWED_OBSERVER_REFERENCE'); };
  config.authConcurrency = 2000; config.serviceRoleKey = 'LOCAL_UNREVIEWED_SERVICE_KEY';
  try {
    await assert.rejects(provider.verifyPreflight({}), { code: 'ONLINE_PREFLIGHT_BINDING_REQUIRED' });
    assert.equal(originalCalls, 1); assert.equal(replacementCalls, 0); assert.equal(databaseCalls, 0);
  } finally { await provider.close(); }
}
test('independent callback probe retains the reviewed preflight reference across caller replacements', async () => {
  await verifyCallbackSnapshot();
});
test('independent mutation probe detects removal of private callback snapshot without changing source bytes', async () => {
  const snapshot = "privateConfig = Object.freeze(Object.fromEntries([\n    'privateActors', 'verifyOnlinePreflight', 'observeExternalTransport', 'appendPreparationEvidence',\n    'PgClient', 'databaseConfig', 'fixtureDatabaseConfig', 'authIds', 'anonKey',\n    'privateSessions', 'persistPrivateSession', 'authConcurrency', 'serviceRoleKey'\n  ].map(key => [key, privateConfig[key]])));";
  const source = await fs.readFile(new URL('supabase_runtime_provider.mjs', import.meta.url), 'utf8');
  const exact = source.includes(snapshot) ? snapshot : snapshot.replaceAll('\n', '\r\n');
  const mutant = await mutatedModule('supabase_runtime_provider.mjs', [[exact, '/* controlled in-memory old caller reference */']]);
  await assert.rejects(verifyCallbackSnapshot(mutant.createSupabaseRuntimeProvider), assert.AssertionError);
});

test('independent regression probe detects an always-true synthetic target assumption', async () => {
  const mutant = await mutatedModule('supabase_runtime_provider.mjs', [
    ["value.syntheticTarget === ['runtime', 'load-001'].includes(scope.key)", 'value.syntheticTarget === true'],
  ]);
  assert.throws(() => verifyBillingScopes(mutant.outcomeFromRpc), { code: 'INVALID_PROVIDER_OUTCOME' });
});

test('independent private DB validator rejects URI, TLS bypass and foreign-project overrides', () => {
  for (const changed of [
    { connectionString: 'LOCAL_UNAUTHORIZED_URI' }, { ssl: { rejectUnauthorized: false } },
    { ssl: { rejectUnauthorized: true, checkServerIdentity() {} } },
    { host: 'db.LOCAL_OTHER_PROJECT.supabase.co' }, { database: 'LOCAL_OTHER_DATABASE' },
  ]) assert.throws(() => snapshotPrivateDatabaseConfig({ ...privateDatabase(), ...changed }), { code: 'EXACT_DEVELOPMENT_TARGET_REQUIRED' });
});

function noNetworkTransport() {
  const requests = [], agents = [];
  const transport = createSupabaseHttpsTransport({ projectId: PROJECT_ID, apiKey: 'LOCAL_CONTROLLED_API_KEY',
    requestFactory(url, options, onResponse) {
      const req = new EventEmitter(); req.setTimeout = () => {}; req.destroy = () => {};
      req.end = () => {
        requests.at(-1).writes++;
        queueMicrotask(() => {
          const res = new EventEmitter(); res.statusCode = 200; onResponse(res);
          res.emit('data', Buffer.from('{"local":true}')); res.emit('end');
        });
      };
      requests.push({ url: url.href, req, writes: 0, agent: options.agent }); return req;
    },
    agentFactory() { const agent = { destroy() {} }; agents.push(agent); return agent; },
  });
  return { transport, requests, agents };
}

test('independent transport probe requires verified TLS and the current deadline before any body write', async () => {
  const local = noNetworkTransport(), socket = new EventEmitter(); socket.encrypted = true; socket.authorized = false;
  let starts = 0;
  const pending = local.transport.send(local.transport.connection(), '/auth/v1/user', { method: 'GET',
    onTransportStart() { starts++; throw new GuardError('WORKLOAD_DEADLINE_EXCEEDED'); } });
  local.requests[0].req.emit('socket', socket); await Promise.resolve(); assert.equal(starts, 0);
  socket.authorized = true; socket.emit('secureConnect');
  await assert.rejects(pending, { code: 'WORKLOAD_DEADLINE_EXCEEDED' }); assert.equal(starts, 1);
  assert.equal(local.requests[0].writes, 0); local.transport.close();
});

test('independent transport probe allocates separate agents and rejects route redirects before creation', async () => {
  const local = noNetworkTransport(), first = local.transport.connection(), second = local.transport.connection();
  const pending = [first, second].map(handle => local.transport.send(handle, '/auth/v1/user', { method: 'GET' }));
  assert.notEqual(local.requests[0].agent, local.requests[1].agent);
  for (const request of local.requests) request.req.emit('socket', { encrypted: true, authorized: true });
  await Promise.all(pending);
  await assert.rejects(local.transport.send(first, `${PROJECT_URL}/auth/v1/user`, { method: 'GET' }), { code: 'EXACT_DEVELOPMENT_TARGET_REQUIRED' });
  await assert.rejects(local.transport.send(first, '/rest/v1/rpc/LOCAL_UNREVIEWED_RPC', { profile: 'api', bearer: 'LOCAL_CONTROLLED_BEARER' }));
  assert.equal(local.requests.length, 2); local.transport.close();
});

test('independent public evidence probe drops raw private fields and normalizes arbitrary error codes', () => {
  const item = publicOutcome({ outcome: 'applied', originalCommandId: null, responseSha256: hashJson('local-response'),
    transportEvidenceSha256: hashJson('local-transport'), rawResponse: 'LOCAL_SECRET_RESPONSE', password: 'LOCAL_SECRET_PASSWORD',
    accessToken: 'LOCAL_SECRET_ACCESS_TOKEN', refreshToken: 'LOCAL_SECRET_REFRESH_TOKEN', factorSecret: 'LOCAL_SECRET_FACTOR' });
  assert.ok(!JSON.stringify(item).includes('LOCAL_SECRET_'));
  assert.equal(safeFailure(new GuardError('LOCAL_PRIVATE_ERROR_TEXT')), 'PROVIDER_FAILURE');
});

test('independent fixture review retains caps, lease-only usage0, bounded activation scope and unsupported boundaries', () => {
  assert.deepEqual(FIXTURE_CAPS.syntheticActivationScopes, ['runtime', 'load-001']);
  assert.equal(FIXTURE_CAPS.perTenant.opportunities, 200); assert.equal(FIXTURE_CAPS.perTenant.processEvents, 800);
  assert.equal(RACE_FIXTURES.outboxLeases.sourceDeltaForClaimOnly.lease, 1);
  assert.equal(RACE_FIXTURES.outboxLeases.sourceDeltaForClaimOnly.usage, 0);
  assert.equal(INVALID_BOUNDARIES['10001Rows'].status, 'unavailable-with-reviewed-caps');
  assert.equal(INVALID_BOUNDARIES['8MiBPlus1Byte'].status, 'unavailable-with-reviewed-caps');
  assert.equal(INVALID_BOUNDARIES['367DayWindow'].status, 'source-supported-without-extra-seeding');
  assert.ok(Object.isFrozen(FIXTURE_CAPS.perTenant));
});
