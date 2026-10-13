import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { createBoundedPgDriver, collectReadOnlyPreflight, CAPACITY_SQL } from './postgres_transport.mjs';
import { createCompleteExternalObserver } from './external_observer.mjs';
import { PROJECT_ID, hashJson } from '../../../../tools/wave5/runtime_contract.mjs';
import { READ_QUERIES } from '../../../../tools/wave5/supabase_read_store.mjs';

// Deliberately controlled driver/capture objects. No live database, Auth, TLS
// server, genuine session or egress capture is created by these tests.
const config = () => ({ host: `db.${PROJECT_ID}.supabase.co`, port: 5432, database: 'postgres',
  user: 'postgres', password: 'synthetic-controlled-test-secret', ssl: { rejectUnauthorized: true } });
const makeFakePool = ({ tlsAuthorised = true, hostname = config().host, failQuery = false, defer = false, beginGate = null,
  backendOffset = 0 } = {}) => {
  const state = { callbacks: 0, configs: [], released: [], queries: [], connected: 0, peak: 0, queue: [], pid: 100 };
  class FakePool {
    constructor(settings) { state.configs.push(settings); this.settings = settings; this.waitingCount = 0; }
    on() {}
    async connect() {
      if (state.connected >= this.settings.max) {
        this.waitingCount += 1; await new Promise(resolve => state.queue.push(resolve)); this.waitingCount -= 1;
      }
      state.connected += 1; state.peak = Math.max(state.peak, state.connected);
      const processID = ++state.pid;
      return { processID, connection: { stream: { encrypted: true, authorized: tlsAuthorised,
        getPeerCertificate: () => ({ subject: { CN: hostname }, subjectaltname: `DNS:${hostname}` }) } },
      query: async (sql, values) => {
        state.queries.push({ sql, values });
        if (sql === 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY' && beginGate) await beginGate;
        if (failQuery) throw Error('raw private server error synthetic-controlled-test-secret');
        if (defer) await new Promise(resolve => setTimeout(resolve, 2));
        if (sql === CAPACITY_SQL) return { rows: [{ observed_at: '2026-10-13T17:59:55.000Z', max_connections: 60,
          installed_migrations: 114, eligible_load_actor_session_rows: 16 }] };
        if (sql === READ_QUERIES.transactionMetadata) return { rows: [{ backend_id: processID + backendOffset,
          observed_at: '2026-10-13T17:59:55.000Z', snapshot_id: '100:100:', read_only: 'on', isolation: 'repeatable read' }] };
        return { rows: [], rowCount: 0 };
      }, release: destroy => { state.released.push(destroy); state.connected -= 1; state.queue.shift()?.(); } };
    }
    async end() {}
  }
  return { state, FakePool };
};
const setup = (options = {}) => {
  const fake = makeFakePool(options);
  const driver = createBoundedPgDriver({ credentialProvider: async () => { fake.state.callbacks += 1; return config(); },
    PoolClass: fake.FakePool, maximumConnections: 2 });
  return { ...fake, driver };
};

test('factory and client construction do not read credentials or connect', async () => {
  const { state, driver } = setup(); const client = new driver.PgClient(config());
  assert.equal(state.callbacks, 0); assert.equal(state.configs.length, 0);
  await client.connect(); assert.equal(state.callbacks, 1); assert.equal(state.configs[0].max, 2);
  assert.equal(state.configs[0].ssl.rejectUnauthorized, true); assert.equal(state.configs[0].connectionTimeoutMillis, 10000);
  assert.equal(state.configs[0].query_timeout, 25000); assert.ok(client.connectionId.startsWith('pg:'));
  await client.end(); await driver.close();
});
test('unverified TLS and mismatching certificate each destroy the acquired lease', async () => {
  for (const options of [{ tlsAuthorised: false }, { hostname: 'unreviewed.example' }]) {
    const { state, driver } = setup(options); const client = new driver.PgClient(config());
    await assert.rejects(client.connect(), /POSTGRES_TLS/); assert.deepEqual(state.released, [true]); await driver.close();
  }
});
test('endpoint and connection URI overrides fail before credential callback', async () => {
  const { driver, state } = setup();
  assert.throws(() => new driver.PgClient({ ...config(), host: 'prod.example' }));
  assert.throws(() => new driver.PgClient({ ...config(), connectionString: 'postgres://override' }));
  assert.equal(state.callbacks, 0); await driver.close();
});
test('SQL outside exact source allowlist and reads outside transaction are rejected', async () => {
  const { driver } = setup(); const client = new driver.PgClient(config()); await client.connect();
  await assert.rejects(client.query('UPDATE core.tenants SET name=$1', ['bad']), /SOURCE_BOUND_READ_QUERY_REQUIRED/);
  await assert.rejects(client.query(READ_QUERIES.calendar), /READ_ONLY_TRANSACTION_REQUIRED/);
  await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'); await client.query(READ_QUERIES.calendar);
  await client.query('COMMIT'); await client.end(); await driver.close();
});
test('queued clients preserve pool bound and actual lease identities remain distinct', async () => {
  const { driver, state } = setup({ defer: true });
  const identities = await Promise.all(Array.from({ length: 16 }, async () => {
    const client = new driver.PgClient(config()); await client.connect();
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'); await client.query(READ_QUERIES.calendar);
    await client.query('COMMIT'); const id = client.connectionId; await client.end(); return id;
  }));
  assert.equal(new Set(identities).size, 16); assert.equal(state.peak, 2);
  assert.equal(driver.metrics().peakConnections, 2); assert.equal(driver.metrics().activeConnections, 0); await driver.close();
});
test('server errors are redacted and failed or unfinished transactions destroy their lease', async () => {
  const { driver, state } = setup({ failQuery: true }); const client = new driver.PgClient(config()); await client.connect();
  await assert.rejects(client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'), error =>
    error.message === 'POSTGRES_QUERY_FAILED' && !JSON.stringify(error).includes(config().password));
  await client.end(); assert.deepEqual(state.released, [true]); await driver.close();
  const other = setup(); const unfinished = new other.driver.PgClient(config()); await unfinished.connect();
  await unfinished.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'); await unfinished.end();
  assert.deepEqual(other.state.released, [true]); await other.driver.close();
});
test('end during delayed BEGIN destroys the lease before it can be recycled', async () => {
  let releaseBegin; const gate = new Promise(resolve => { releaseBegin = resolve; });
  const { driver, state } = setup({ beginGate: gate }); const client = new driver.PgClient(config()); await client.connect();
  const pending = client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  await new Promise(resolve => setImmediate(resolve));
  await client.end(); assert.deepEqual(state.released, [true]);
  releaseBegin(); await assert.rejects(pending, /POSTGRES_QUERY_FAILED/); await driver.close();
});
test('preflight hashes actual controlled transaction and treats session counts as preliminary', async () => {
  const { driver } = setup(); const authIds = Object.fromEntries(['proposer', 'approver', 'executor', 'billing-admin', 'operator', 'foreign-member']
    .map(label => [label, crypto.randomUUID()]));
  const proof = await collectReadOnlyPreflight({ driver, databaseConfig: config(), authIds });
  assert.equal(proof.committed, true); assert.equal(proof.readOnly, true); assert.equal(proof.isolation, 'repeatable-read');
  assert.equal(proof.targetScaleLoadPassed, false); assert.equal(proof.modelKeyRequiredForLoad, false);
  assert.equal(proof.rows[0].eligible_load_actor_session_rows, 16); assert.match(proof.transactionEvidenceSha256, /^[a-f0-9]{64}$/);
  await driver.close();
});
test('credential callback errors and late private target drift expose fixed failure codes', async () => {
  const fake = makeFakePool(); const bad = createBoundedPgDriver({ PoolClass: fake.FakePool,
    credentialProvider: async () => { throw Error('secret private password'); } });
  await assert.rejects(new bad.PgClient(config()).connect(), { message: 'PRIVATE_DATABASE_CONFIG_UNAVAILABLE' }); await bad.close();
  const mismatch = createBoundedPgDriver({ PoolClass: fake.FakePool, credentialProvider: async () => ({ ...config(), password: 'different' }) });
  await assert.rejects(new mismatch.PgClient(config()).connect(), { message: 'PRIVATE_DATABASE_TARGET_DRIFT' }); await mismatch.close();
});
test('pooler startup identity stays separate from real transaction backend identity', async () => {
  const { driver } = setup({ backendOffset: 1000 });
  const authIds = Object.fromEntries(['proposer', 'approver', 'executor', 'billing-admin', 'operator', 'foreign-member']
    .map(label => [label, crypto.randomUUID()]));
  const proof = await collectReadOnlyPreflight({ driver, databaseConfig: config(), authIds });
  assert.notEqual(proof.backendId, proof.transportProcessId); assert.equal(proof.backendId - proof.transportProcessId, 1000);
  await driver.close();
});

const captureFixture = () => {
  const sha = hashJson('controlled-only'), runtimeId = crypto.randomUUID();
  const sources = { 'wave5-runtime': sha }, syntheticScopes = [{ key: 'controlled-test' }];
  const window = { startedAt: '2026-10-13T18:00:00Z', finishedAt: '2026-10-13T18:06:00Z' };
  const trace = { kind: 'trusted-complete-egress-capture', projectId: PROJECT_ID, runtimeId,
    observerSourceSha256: sha, captureMethod: 'source-bound-worker-transport-capture', workerSourceBindings: sources,
    observedFromAt: window.startedAt, observedUntilAt: window.finishedAt,
    droppedEvents: 0, captureStoppedUnexpectedly: false, captureIdentitySha256: sha,
    coveredTransports: ['wave5-runtime/model', 'wave5-runtime/webhook'], records: [
      { sequence: 1, kind: 'capture-open', observedAt: window.startedAt, evidenceSha256: sha },
      { sequence: 2, kind: 'capture-close', observedAt: window.finishedAt, evidenceSha256: sha }] };
  const jobs = { kind: 'actual-continuous-job-and-worker-quiescence', projectId: PROJECT_ID, runtimeId,
    observedFromAt: window.startedAt, observedUntilAt: window.finishedAt, inflightWorkerCount: 0,
    continuousWindowVerified: true, queryEvidenceSha256: sha, observationEvidenceSha256: sha,
    jobs: [4, 5, 6].map(id => ({ id, active: false })) };
  const options = { runtimeId, runtimeBundleSha256: sha, scopeDigestSha256: hashJson(syntheticScopes),
    observerSourceSha256: sha, reviewedWorkerSources: sources, traceReader: async () => trace,
    verifyTrustedCapture: async ({ traceSha256 }) => ({ kind: 'independently-verified-complete-egress-capture', captureAuthentic: true,
      traceSha256, completeReviewedTransports: true, continuousWindow: true, verificationEvidenceSha256: sha }),
    jobsReader: async () => jobs };
  return { trace, jobs, options, args: { review: { projectId: PROJECT_ID, bundleSha256: sha, syntheticScopes },
    plan: { externalObservationSourceSha256: sha }, window } };
};
test('complete observer accepts only source-bound authenticated continuous controlled captures', async () => {
  const fixture = captureFixture(); const proof = await createCompleteExternalObserver(fixture.options)(fixture.args);
  assert.equal(proof.modelDispatchesObserved, 0); assert.equal(proof.webhookDispatchesObserved, 0);
  assert.equal(proof.allReviewedModelDeliveryWorkersCovered, true); assert.match(proof.transportTraceSha256, /^[a-f0-9]{64}$/);
});
test('empty logs, missing coverage, sequence gaps and forged completeness are rejected', async () => {
  for (const modify of [fixture => { fixture.trace.records = []; }, fixture => { fixture.trace.coveredTransports.pop(); },
    fixture => { fixture.trace.records[1].sequence = 3; }, fixture => { fixture.trace.droppedEvents = 1; },
    fixture => { fixture.options.verifyTrustedCapture = async () => ({ captureAuthentic: true }); }]) {
    const fixture = captureFixture(); modify(fixture);
    await assert.rejects(createCompleteExternalObserver(fixture.options)(fixture.args));
  }
});
test('actual dispatch attempts fail zero-effect observation even without remote outcome rows', async () => {
  for (const transport of ['model', 'webhook']) {
    const fixture = captureFixture(); fixture.trace.records.splice(1, 0, { sequence: 2, kind: 'transport-dispatch',
      observedAt: '2026-10-13T18:01:00Z', worker: 'wave5-runtime', transport, attemptId: crypto.randomUUID(), evidenceSha256: hashJson('attempt') });
    fixture.trace.records[2].sequence = 3;
    await assert.rejects(createCompleteExternalObserver(fixture.options)(fixture.args), /EXTERNAL_TRANSPORT_DISPATCH_OBSERVED/);
  }
});
test('active job, inflight work, truncated interval and mismatched observer source fail closed', async () => {
  for (const modify of [fixture => { fixture.jobs.jobs[0].active = true; }, fixture => { fixture.jobs.inflightWorkerCount = 1; },
    fixture => { fixture.trace.observedUntilAt = fixture.args.window.startedAt; },
    fixture => { fixture.args.plan.externalObservationSourceSha256 = hashJson('different'); }]) {
    const fixture = captureFixture(); modify(fixture);
    await assert.rejects(createCompleteExternalObserver(fixture.options)(fixture.args));
  }
});
