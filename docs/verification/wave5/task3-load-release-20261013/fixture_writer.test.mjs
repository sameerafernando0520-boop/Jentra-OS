import test from 'node:test';
import assert from 'node:assert/strict';
import {freshId, hashJson, PROJECT_ID} from '../../../../tools/wave5/runtime_contract.mjs';
import {MEMBERSHIP_FIXTURE_SQL} from '../../../../tools/wave5/supabase_membership_fixture.mjs';
import {createBoundedMembershipFixturePgDriver, FIXTURE_WRITER_ROLE} from './fixture_writer.mjs';
import {setup, config, beginState, deferred, tokenFreeAcknowledgment} from './fixture_writer_test_support.mjs';

const cleanup = (t, fixture) => { t.after(() => fixture.driver.close()); return fixture; };
const mutations = queries => queries.filter(query => Object.entries(MEMBERSHIP_FIXTURE_SQL)
  .filter(([name]) => ['suspend', 'restoreMember', 'seats', 'revokeExactUnused'].includes(name)).some(([, sql]) => sql === query.sql));

test('construction and reviewed operation wrapping perform no credential, connection or SQL I/O', async t => {
  const f = cleanup(t, setup()), signal = new AbortController().signal;
  const client = f.driver.runWithSignal(signal, () => new f.driver.PgClient(config()), {caseId: f.race('seats').caseId, action: 'prepare'});
  assert.equal(f.state.callbacks, 0); assert.deepEqual(f.state.configs, []); assert.deepEqual(f.state.queries, []);
  await client.end(); assert.equal(f.state.poolEnds, 0);
});

test('unreviewed execution context, actor population, pool and timeout bounds fail before I/O', t => {
  const f = cleanup(t, setup());
  const base = {executionContext: f.context, authIds: f.authIds, credentialProvider: async () => config(), PoolClass: f.FakePool};
  for (const changes of [{executionContext: {...f.context, plan: {...f.context.plan, production: true}}},
    {authIds: {...f.authIds, extra: freshId()}}, {authIds: {...f.authIds, operator: f.authIds.approver}},
    {maximumConnections: 9}, {maximumConnections: 0}, {statementTimeoutMs: 25001}, {acquireTimeoutMs: 10001}]) {
    assert.throws(() => createBoundedMembershipFixturePgDriver({...base, ...changes}));
  }
  assert.equal(f.state.callbacks, 0); assert.equal(f.state.connected, 0);
});

test('writer role, operation case, action and active AbortSignal are mandatory', t => {
  const f = cleanup(t, setup()), signal = new AbortController().signal;
  assert.throws(() => new f.driver.PgClient(config()), /FIXTURE_OPERATION_SIGNAL_REQUIRED/);
  for (const role of ['jentra-wave5-readonly-verification', 'other', undefined]) {
    assert.throws(() => f.driver.runWithSignal(signal, () => new f.driver.PgClient({...config(), application_name: role}),
      {caseId: f.race('seats').caseId, action: 'prepare'}), /FIXTURE_EXPLICIT_WRITER_ROLE_REQUIRED/);
  }
  assert.throws(() => f.driver.runWithSignal(signal, () => {}, {caseId: f.race('quota').caseId, action: 'prepare'}));
  assert.throws(() => f.driver.runWithSignal(signal, () => {}, {caseId: f.race('seats').caseId, action: 'unsafe'}));
  const aborted = new AbortController(); aborted.abort();
  assert.throws(() => f.driver.runWithSignal(aborted.signal, () => {}, {caseId: f.race('seats').caseId, action: 'prepare'}));
  assert.equal(f.state.callbacks, 0);
});

test('accessor-based role or database configuration is rejected without invoking getters', t => {
  const f = cleanup(t, setup()); let reads = 0;
  for (const key of ['application_name', 'password', 'ssl']) {
    const unsafe = {...config()}; Object.defineProperty(unsafe, key, {enumerable: true, get() { reads++; throw Error('CONTROLLED_SECRET'); }});
    assert.throws(() => f.driver.runWithSignal(new AbortController().signal, () => new f.driver.PgClient(unsafe),
      {caseId: f.race('seats').caseId, action: 'prepare'}));
  }
  assert.equal(reads, 0); assert.equal(f.state.callbacks, 0);
});

test('legitimate public fixture prepares seats and restores exact memberships, versions and unused invitations', async t => {
  const f = cleanup(t, setup()), original = structuredClone(f.state.database);
  const prepared = await f.run('prepare');
  assert.equal(prepared.committed, true); assert.equal(f.state.database.subscription.seats, 3);
  assert.ok(f.state.database.members.every(row => row.status === 'suspended'));
  const accepted = await f.createInvitation('approver'), unused = await f.createInvitation('executor');
  const winner = f.state.database.members.find(row => row.user_id === f.authIds.approver);
  winner.status = 'active'; winner.version = String(BigInt(winner.version) + 1n);
  f.state.database.invitations.find(row => row.id === accepted).status = 'accepted';
  const boundary = f.state.queries.length, restored = await f.run('restore');
  assert.equal(restored.committed, true); assert.equal(restored.noAcceptanceChanges, true);
  assert.equal(f.state.database.subscription.seats, 4);
  assert.ok(BigInt(f.state.database.subscription.version) > BigInt(original.subscription.version));
  for (const row of f.state.database.members) {
    assert.equal(row.status, 'active');
    const old = original.members.find(old => old.id === row.id);
    assert.equal(old.user_id, row.user_id); assert.ok(BigInt(row.version) > BigInt(old.version));
  }
  assert.deepEqual(f.state.database.assignments, original.assignments);
  assert.equal(f.state.database.invitations.find(row => row.id === accepted).status, 'accepted');
  assert.equal(f.state.database.invitations.find(row => row.id === unused).status, 'revoked');
  const restoreWrites = mutations(f.state.queries.slice(boundary));
  assert.equal(restoreWrites[0].sql, MEMBERSHIP_FIXTURE_SQL.seats);
  assert.equal(restoreWrites[0].values[1], 4);
  assert.equal(f.state.commits, 2); assert.deepEqual(f.state.releases, [false, false]);
});

test('admissions invitation winner restores observed cap 3 to original 4', async t => {
  const f = cleanup(t, setup()); await f.run('prepare', 'admissions'); await f.createInvitation('approver', 'admissions');
  const admitted = f.state.database.members.find(row => row.user_id === f.authIds.approver);
  admitted.status = 'active'; admitted.version = String(BigInt(admitted.version) + 1n);
  f.state.database.invitations[0].status = 'accepted';
  assert.equal(f.state.database.subscription.seats, 3); await f.run('restore', 'admissions');
  assert.equal(f.state.database.subscription.seats, 4); assert.ok(f.state.database.members.every(row => row.status === 'active'));
});

test('admissions activation winner restores observed cap 2 and occupied 2 to original 4', async t => {
  const f = cleanup(t, setup()); await f.run('prepare', 'admissions'); await f.createInvitation('approver', 'admissions');
  f.state.database.subscription.seats = 2; f.state.database.subscription.version = String(BigInt(f.state.database.subscription.version) + 1n);
  const start = f.state.queries.length; await f.run('restore', 'admissions');
  const restore = f.state.queries.slice(start), cap = restore.findIndex(query => query.sql === MEMBERSHIP_FIXTURE_SQL.seats);
  assert.ok(restore.slice(0, cap).some(query => query.sql === MEMBERSHIP_FIXTURE_SQL.occupied));
  assert.equal(f.state.database.subscription.seats, 4); assert.ok(f.state.database.members.every(row => row.status === 'active'));
  assert.equal(f.state.database.invitations[0].status, 'revoked');
});

test('successive seats and admissions cases preserve original identity and revoke only acknowledged returned invitations', async t => {
  const f = cleanup(t, setup()); await f.run('prepare'); await f.createInvitation('approver'); await f.createInvitation('executor');
  await f.run('restore'); await f.run('prepare', 'admissions'); await f.createInvitation('approver', 'admissions');
  await f.run('restore', 'admissions');
  assert.equal(f.state.database.subscription.seats, 4); assert.equal(f.state.database.invitations.length, 3);
  assert.ok(f.state.database.invitations.every(row => row.status === 'revoked'));
  assert.equal(f.state.commits, 4); assert.equal(f.driver.metrics().activeConnections, 0);
});

test('arbitrary SQL, foreign tenant, foreign actor and unauthorized seat values never reach PostgreSQL', async t => {
  const f = cleanup(t, setup()), client = await beginState(f), before = f.state.queries.length;
  const attempts = [
    ['UPDATE core.memberships SET status=\'active\'', []],
    [MEMBERSHIP_FIXTURE_SQL.subscription + '; SELECT 1', [f.target.tenantId]],
    [MEMBERSHIP_FIXTURE_SQL.subscription, [freshId()]],
    [MEMBERSHIP_FIXTURE_SQL.memberships, [f.target.tenantId, [f.authIds.approver, f.authIds.operator]]],
    [MEMBERSHIP_FIXTURE_SQL.memberships, [f.target.tenantId, [f.authIds.approver, f.authIds.approver]]],
    [MEMBERSHIP_FIXTURE_SQL.suspend, [f.target.tenantId, freshId(), f.authIds.operator, '1']],
    ...[0, 2, 5, 1000, '3'].map(seats => [MEMBERSHIP_FIXTURE_SQL.seats, [f.target.tenantId, seats, f.state.database.subscription.id, '1']]),
  ];
  for (const [sql, values] of attempts) await assert.rejects(client.query(sql, values));
  assert.equal(f.state.queries.length, before); assert.equal(mutations(f.state.queries).length, 0);
  await client.end(); assert.deepEqual(f.state.releases, [true]);
});

test('foreign membership identity, stale version and reordered cap update fail with no committed effect', async t => {
  for (const kind of ['foreign-member', 'stale-version', 'cap-before-suspend']) {
    const f = cleanup(t, setup()), client = await beginState(f), member = f.state.database.members[0], before = f.state.queries.length;
    const operation = kind === 'cap-before-suspend'
      ? [MEMBERSHIP_FIXTURE_SQL.seats, [f.target.tenantId, 3, f.state.database.subscription.id, '1']]
      : [MEMBERSHIP_FIXTURE_SQL.suspend, [f.target.tenantId, kind === 'foreign-member' ? freshId() : member.id,
        member.user_id, kind === 'stale-version' ? '2' : member.version]];
    await assert.rejects(client.query(...operation));
    assert.equal(f.state.queries.length, before); assert.equal(f.state.commits, 0); assert.ok(f.state.releases.every(value => value === true));
  }
});

test('server baseline, assignment or original seat drift is rejected before any fixture DML', async t => {
  for (const modify of [(db, actors) => { db.members[0].user_id = actors.operator; },
    db => { db.assignments[0].branch_id = freshId(); }, db => { db.subscription.seats = 3; }]) {
    const f = cleanup(t, setup({modifyDatabase: modify})); await assert.rejects(f.run('prepare'));
    assert.equal(mutations(f.state.queries).length, 0); assert.equal(f.state.commits, 0); assert.deepEqual(f.state.releases, [true]);
  }
});

test('restoration requires its committed case and rejects foreign subscription or unsupported outcomes', async t => {
  const first = cleanup(t, setup()); await assert.rejects(first.run('restore')); assert.equal(first.state.commits, 0);
  for (const change of [db => { db.subscription.id = freshId(); }, db => { db.subscription.seats = 2; },
    db => { db.subscription.seats = 4; }, db => { db.members[0].id = freshId(); }]) {
    const f = cleanup(t, setup()); await f.run('prepare'); change(f.state.database);
    const start = f.state.queries.length; await assert.rejects(f.run('restore'));
    assert.equal(mutations(f.state.queries.slice(start)).length, 0); assert.equal(f.state.commits, 1);
  }
});

test('unproved admissions cap 2 with an admitted member fails before restoration DML', async t => {
  const f = cleanup(t, setup()); await f.run('prepare', 'admissions');
  f.state.database.subscription.seats = 2; f.state.database.members[0].status = 'active';
  const start = f.state.queries.length; await assert.rejects(f.run('restore', 'admissions'));
  assert.equal(mutations(f.state.queries.slice(start)).length, 0); assert.equal(f.state.commits, 1);
});

test('restoration cannot COMMIT without fresh final subscription, memberships and assignment readback', async t => {
  const f = cleanup(t, setup()); await f.run('prepare'); const original = structuredClone(f.state.database);
  const client = await f.driver.runWithSignal(new AbortController().signal, async () => {
    const client = new f.driver.PgClient(config()); await client.connect(); await client.query('BEGIN');
    await client.query(MEMBERSHIP_FIXTURE_SQL.subscription, [f.target.tenantId]);
    await client.query(MEMBERSHIP_FIXTURE_SQL.memberships, [f.target.tenantId, [f.authIds.approver, f.authIds.executor]]);
    await client.query(MEMBERSHIP_FIXTURE_SQL.assignments, [f.target.tenantId, [f.authIds.approver, f.authIds.executor]]);
    await client.query(MEMBERSHIP_FIXTURE_SQL.seats, [f.target.tenantId, 4, original.subscription.id, original.subscription.version]);
    for (const member of original.members)
      await client.query(MEMBERSHIP_FIXTURE_SQL.restoreMember, [f.target.tenantId, member.id, member.user_id, member.version]);
    await client.query(MEMBERSHIP_FIXTURE_SQL.occupied, [f.target.tenantId]); return client;
  }, {caseId: f.race('seats').caseId, action: 'restore'});
  const before = f.state.queries.length; await assert.rejects(client.query('COMMIT'));
  assert.equal(f.state.queries.length, before); assert.equal(f.driver.metrics().uncertainCommit, false);
  assert.deepEqual(f.state.database, original); assert.equal(f.state.commits, 1);
});

function invitationRecord(f, changes = {}) {
  return {kind: 'wave5-private-preparation-journal-record', projectId: PROJECT_ID, runtimeBundleSha256: f.context.review.bundleSha256,
    planBodySha256: f.context.binding.planBodySha256, sourceSha256: f.context.plan.preparationJournalSourceSha256,
    sequence: 1, recordId: freshId(), observedAt: new Date().toISOString(), caseId: f.race('seats').caseId,
    scopeKey: 'load-001', action: 'rpc-create-invitation', phase: 'intent', operationId: freshId(),
    details: {actorId: f.authIds['billing-admin'], route: '/rest/v1/rpc/create_invitation', parameters: {
      p_tenant_id: f.target.tenantId, p_email: f.context.review.accounts.find(actor => actor.label === 'approver').email,
      p_role_id: f.roleId, p_legal_entity_id: f.target.entityId, p_branch_id: f.target.branchId, p_expires_in_hours: 1}}, ...changes};
}
test('only durable acknowledged intent/confirmed invitation pairs with exact reviewed actor and scope are adopted', async t => {
  for (const mutate of [record => { record.details.actorId = freshId(); },
    record => { record.details.parameters.p_tenant_id = freshId(); }, record => { record.details.parameters.p_role_id = freshId(); },
    record => { record.details.parameters.p_legal_entity_id = freshId(); }, record => { record.details.parameters.p_branch_id = freshId(); },
    record => { record.details.parameters.p_email = 'foreign@invalid.example'; }, record => { record.caseId = freshId(); }]) {
    const f = cleanup(t, setup()); await f.run('prepare'); const record = invitationRecord(f); mutate(record);
    assert.throws(() => f.observe(record, f.receipt(record)));
  }
  const f = cleanup(t, setup()); await f.run('prepare'); const intent = invitationRecord(f);
  assert.throws(() => f.observe(intent, {...f.receipt(intent), durable: false}));
  const confirmed = {...intent, phase: 'confirmed', details: {result: {ok: true, value: {invitation_id: freshId()}, transportEvidenceSha256: hashJson('controlled')}}};
  assert.throws(() => f.observe(confirmed, f.receipt(confirmed)), /FIXTURE_RETURNED_INVITATION_ID_REQUIRED/);
  f.observe(intent, f.receipt(intent));
  assert.equal(f.observe(confirmed, f.receipt(confirmed)).adopted, true);
  assert.throws(() => f.observe(confirmed, f.receipt(confirmed)));
});

test('arbitrary invitation IDs and billing-actor/email changes fail before revocation SQL', async t => {
  const f = cleanup(t, setup()); await f.run('prepare'); const own = await f.createInvitation('approver');
  const client = await f.driver.runWithSignal(new AbortController().signal, async () => {
    const client = new f.driver.PgClient(config()); await client.connect(); await client.query('BEGIN'); return client;
  }, {caseId: f.race('seats').caseId, action: 'restore'});
  const emails = ['approver', 'executor'].map(label => f.context.review.accounts.find(actor => actor.label === label).email);
  const before = f.state.queries.length;
  for (const values of [[f.target.tenantId, [freshId()], f.authIds['billing-admin'], emails],
    [f.target.tenantId, [own], f.authIds.executor, emails], [f.target.tenantId, [own], f.authIds['billing-admin'], ['foreign@invalid.example']]])
    await assert.rejects(client.query(MEMBERSHIP_FIXTURE_SQL.revokeExactUnused, values));
  assert.equal(f.state.queries.length, before); await client.end();
});

test('uncertain invitation acknowledgement adopts no result and blocks further fixture mutations', async t => {
  const f = cleanup(t, setup()); await f.run('prepare'); const intent = invitationRecord(f);
  f.observe(intent, f.receipt(intent));
  const uncertain = {...intent, phase: 'uncertain', details: {failureCode: 'TRANSPORT_UNCERTAIN'}};
  assert.deepEqual(f.observe(uncertain, f.receipt(uncertain)), {adopted: false, uncertain: true});
  assert.throws(() => f.observe({...intent, phase: 'confirmed'}, f.receipt(intent)));
  assert.throws(() => f.run('restore'), /FIXTURE_UNCERTAIN_INVITATION_REQUIRES_REVIEW/);
});

test('confirmed invitation observations reject raw tokens and unverified original-record claims', async t => {
  const f = cleanup(t, setup()); await f.run('prepare'); const intent = invitationRecord(f); f.observe(intent);
  const raw = {...intent, phase: 'confirmed', details: {result: {ok: true, value: {invitation_id: freshId(), token: 'PRIVATE_CONTROLLED_TOKEN'},
    transportEvidenceSha256: hashJson('controlled')}}};
  const projected = tokenFreeAcknowledgment(raw, f.receipt(raw));
  assert.ok(!JSON.stringify(projected).includes('PRIVATE_CONTROLLED_TOKEN'));
  assert.throws(() => f.driver.observeInvitationJournalRecord(projected.observation,
    {...projected.acknowledgment, originalRecordHashVerified: false}));
  const unsafe = {...projected.observation, details: raw.details};
  assert.throws(() => f.driver.observeInvitationJournalRecord(unsafe,
    {...projected.acknowledgment, observationSha256: hashJson(unsafe)}), /FIXTURE_RETURNED_INVITATION_ID_REQUIRED/);
});

test('TLS chain and hostname verification destroy unverified leases; target/URI overrides are rejected', async t => {
  for (const options of [{authorized: false}, {hostname: 'foreign.example'}]) {
    const f = cleanup(t, setup(options)); await assert.rejects(f.run('prepare'));
    assert.deepEqual(f.state.releases, [true]); assert.equal(f.state.queries.length, 0);
  }
  const f = cleanup(t, setup());
  for (const changes of [{host: 'production.example'}, {connectionString: 'postgres://override'}, {ssl: {rejectUnauthorized: false}},
    {ssl: {rejectUnauthorized: true, checkServerIdentity: () => undefined}}]) {
    assert.throws(() => f.driver.runWithSignal(new AbortController().signal, () => new f.driver.PgClient({...config(), ...changes}),
      {caseId: f.race('seats').caseId, action: 'prepare'}), /FIXTURE_EXACT_DATABASE_TARGET_REQUIRED/);
  }
  assert.equal(f.state.callbacks, 0);
});

test('abort while BEGIN is pending destroys the lease and never commits or recycles an open transaction', async t => {
  const gate = deferred(), f = cleanup(t, setup({beginGate: gate.promise})), controller = new AbortController();
  const pending = f.run('prepare', 'seats', controller); await f.beginStarted.promise; controller.abort();
  await assert.rejects(pending); assert.deepEqual(f.state.releases, [true]); assert.equal(f.state.commits, 0);
  gate.resolve(); await new Promise(resolve => setImmediate(resolve)); assert.equal(f.state.database.subscription.seats, 4);
  assert.equal(f.driver.metrics().activeConnections, 0);
});

test('abort during pending pool acquisition returns promptly and destroys the later lease', async t => {
  const gate = deferred(), f = cleanup(t, setup({acquireGate: gate.promise})), controller = new AbortController();
  const pending = f.run('prepare', 'seats', controller); await f.acquisitionStarted.promise; controller.abort();
  await assert.rejects(pending); assert.equal(f.state.queries.length, 0); gate.resolve();
  await new Promise(resolve => setImmediate(resolve)); assert.deepEqual(f.state.releases, [true]);
});

test('abort while the real preparation journal waits for COMMIT intent destroys staged writes', async t => {
  const gate = deferred(), reached = deferred();
  const f = cleanup(t, setup({beforeAcknowledge: async record => {
    if (record.action === 'membership-commit' && record.phase === 'intent') { reached.resolve(); await gate.promise; }
  }})), controller = new AbortController(), original = structuredClone(f.state.database);
  const pending = f.run('prepare', 'seats', controller); await reached.promise; controller.abort(); gate.resolve();
  await assert.rejects(pending); assert.equal(f.state.commits, 0); assert.deepEqual(f.state.database, original);
  assert.equal(f.state.implicitRollbacks, 1); assert.deepEqual(f.state.releases, [true]);
});

test('uncertain COMMIT has no automatic replay or restoration and exposes only a fixed code', async t => {
  const f = cleanup(t, setup({loseCommitReply: true}));
  await assert.rejects(f.run('prepare'), error => error.message === 'UNCERTAIN_MUTATION_REQUIRES_REVIEW'
    && !JSON.stringify(error).includes('SECRET'));
  assert.equal(f.state.commits, 1); assert.equal(f.state.database.subscription.seats, 3);
  assert.equal(f.driver.metrics().uncertainCommit, true);
  const before = f.state.queries.length;
  assert.throws(() => f.run('restore'), /FIXTURE_UNCERTAIN_COMMIT_REQUIRES_REVIEW/);
  assert.throws(() => f.run('prepare', 'admissions'), /FIXTURE_UNCERTAIN_COMMIT_REQUIRES_REVIEW/);
  assert.equal(f.state.queries.length, before); assert.deepEqual(f.state.releases, [true]);
});

test('query timeout, private callback error and target drift are bounded and sanitized', async t => {
  const gate = deferred(), timed = cleanup(t, setup({beginGate: gate.promise, statementTimeoutMs: 5}));
  await assert.rejects(timed.run('prepare')); gate.resolve(); assert.equal(timed.state.commits, 0); assert.deepEqual(timed.state.releases, [true]);
  const failing = cleanup(t, setup({credentialProvider: async () => { throw Error('CONTROLLED_PRIVATE_PASSWORD_SECRET'); }}));
  await assert.rejects(failing.run('prepare'), error => !error.message.includes('SECRET') && error.message === 'PROVIDER_FAILURE');
  const drift = cleanup(t, setup({credentialProvider: async () => ({...config(), password: 'CONTROLLED_DIFFERENT_VALUE'})}));
  await assert.rejects(drift.run('prepare')); assert.equal(drift.state.connected, 0);
  const missing = cleanup(t, setup({acquireTimeoutMs: 5, credentialProvider: () => new Promise(() => {})}));
  await assert.rejects(missing.run('prepare')); assert.equal(missing.state.connected, 0);
});

test('close destroys a still-open fixture transaction and blocks new connections', async t => {
  const f = cleanup(t, setup()), client = await beginState(f); await f.driver.close();
  assert.deepEqual(f.state.releases, [true]); assert.equal(f.state.implicitRollbacks, 1);
  assert.equal(f.driver.metrics().activeConnections, 0); assert.throws(() => f.run('prepare'));
  await client.end(); assert.deepEqual(f.state.releases, [true]);
  await f.driver.close(); assert.equal(f.state.poolEnds, 1);
});

test('per-operation cancellation leaves another independently acquired writer connection usable', async t => {
  const f = cleanup(t, setup()), first = new AbortController(), second = new AbortController();
  const connect = controller => f.driver.runWithSignal(controller.signal, async () => {
    const client = new f.driver.PgClient(config()); await client.connect(); return client;
  }, {caseId: f.race('seats').caseId, action: 'prepare'});
  const a = await connect(first), b = await connect(second); first.abort();
  assert.equal(second.signal.aborted, false); assert.equal(f.driver.metrics().activeConnections, 1);
  assert.ok(b.processID > 0); assert.equal(a.processID, undefined); await b.end();
  assert.deepEqual(f.state.releases, [true, false]); assert.equal(f.driver.metrics().activeConnections, 0);
});

test('closing during acquisition cancels the wait and destroys a late lease without aborting the owner signal', async t => {
  const gate = deferred(), f = cleanup(t, setup({acquireGate: gate.promise})), controller = new AbortController();
  const pending = f.run('prepare', 'seats', controller); await f.acquisitionStarted.promise; await f.driver.close();
  await assert.rejects(pending); assert.equal(controller.signal.aborted, false); gate.resolve();
  await new Promise(resolve => setImmediate(resolve)); assert.deepEqual(f.state.releases, [true]);
  await f.driver.close(); assert.equal(f.state.poolEnds, 1);
});

test('bounded pool preserves distinct acquired backend identities with queued clients', async t => {
  const f = cleanup(t, setup({maximumConnections: 2})), ids = await Promise.all(Array.from({length: 12}, () =>
    f.driver.runWithSignal(new AbortController().signal, async () => {
      const client = new f.driver.PgClient(config()); await client.connect();
      const id = client.connectionId; await new Promise(resolve => setImmediate(resolve)); await client.end(); return id;
    }, {caseId: f.race('seats').caseId, action: 'prepare'})));
  assert.equal(new Set(ids).size, 12); assert.equal(f.state.peak, 2); assert.equal(f.driver.metrics().peakConnections, 2);
  assert.equal(f.driver.metrics().activeConnections, 0);
});
