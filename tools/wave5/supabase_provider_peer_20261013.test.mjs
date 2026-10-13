import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import { PROJECT_ID, PROJECT_URL, freshId, hashJson, GuardError, publicOutcome, safeFailure } from './runtime_contract.mjs';
import { createSupabaseReadStore, READ_QUERIES, snapshotPrivateDatabaseConfig } from './supabase_read_store.mjs';
import { mappedRpcRequest, outcomeFromRpc } from './supabase_runtime_provider.mjs';
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
