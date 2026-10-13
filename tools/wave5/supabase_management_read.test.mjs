import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { EventEmitter } from 'node:events';
import { PROJECT_ID, freshId, hashBytes } from './runtime_contract.mjs';
import { READ_QUERY_SHA256 } from './supabase_read_store.mjs';
import * as implementation from './supabase_management_read.mjs';

const review = JSON.parse(fs.readFileSync(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json', import.meta.url)));
const scope = review.syntheticScopes.find(target => target.key === 'runtime');
const actualIds = Object.fromEntries(review.accounts.map(actor => [actor.label, freshId()]));
const privateToken = 'controlled-owner-pat-not-a-real-credential';
const packet = rows => [{ rows, backend_id: 19, snapshot_id: '42:44:', observed_at: '2026-10-13 01:23:45.123456+00',
  read_only: 'on', isolation: 'read committed' }];
function localTransport({ response = packet([{ opportunity_rows: '2', process_event_rows: '6' }]), status = 201,
  socketDeferred = false, responseError = false, requestError = false } = {}) {
  const calls = [], agents = []; let sent = 0, destroyed = 0;
  const requestFactory = (url, options, onResponse) => {
    const req = new EventEmitter(); req.destroy = () => { destroyed++; };
    req.end = bytes => {
      sent++; calls.at(-1).bytes = bytes;
      queueMicrotask(() => {
        if (requestError) { req.emit('error', new Error('private-token-in-error')); return; }
        const res = new EventEmitter(); res.statusCode = status; onResponse(res);
        if (responseError) { res.emit('error', new Error('private-token-in-response')); return; }
        res.emit('data', Buffer.from(typeof response === 'string' ? response : JSON.stringify(response))); res.emit('end');
      });
    };
    calls.push({ url: url.href, options, req });
    if (!socketDeferred) queueMicrotask(() => req.emit('socket', { encrypted: true, authorized: true }));
    return req;
  };
  const create = implementation.createSupabaseManagementReadBridge;
  assert.equal(typeof create, 'function', 'The fixed read-only Management API bridge is not implemented.');
  const bridge = create({ review, authIds: actualIds, privateManagementToken: privateToken, requestFactory,
    agentFactory: () => { const value = { destroy() {}, index: agents.length }; agents.push(value); return value; }, timeoutMs: 100 });
  return { bridge, calls, agents, sent: () => sent, destroyed: () => destroyed };
}

test('Management bridge performs a fixed typed SELECT over verified TLS and reports actual isolation without a repeatable-read claim', async () => {
  const local = localTransport(); assert.equal(local.calls.length, 0);
  const result = await local.bridge.read('sourcePopulation', { scopeKey: 'runtime' });
  assert.equal(local.calls[0].url, 'https://api.supabase.com/v1/projects/xpdoufauvrbdmxgngetv/database/query');
  assert.equal(local.calls[0].options.method, 'POST'); assert.equal(local.calls[0].options.rejectUnauthorized, true);
  const body = JSON.parse(local.calls[0].bytes); assert.equal(body.read_only, true); assert.deepEqual(body.parameters, [scope.tenantId]);
  assert.match(body.query, /FROM workflow\.process_events/); assert.match(body.query, /pg_catalog\.current_setting\('transaction_read_only'\)/);
  assert.equal(result.querySha256, READ_QUERY_SHA256.sourcePopulation); assert.equal(result.isolation, 'read committed');
  assert.equal(result.committedTransactionProof, false); assert.equal(result.readOnly, true); assert.equal(result.observedAt, '2026-10-13 01:23:45.123456+00');
  assert.deepEqual(result.rows, [{ opportunity_rows: '2', process_event_rows: '6' }]);
  assert.ok(!JSON.stringify(result).includes(privateToken)); local.bridge.close();
});

test('arbitrary SQL, unknown scopes and unsupported provenance reads are rejected before a Management request exists', async () => {
  const local = localTransport();
  for (const [name, args] of [['SELECT password FROM auth.users', {}], ['sourcePopulation', { scopeKey: 'not-reviewed' }],
    ['invocationProvenance', { scopeKey: 'load-001', invocationIds: [] }], ['transactionMetadata', {}],
    ['leasePrerequisites', { scopeKey: 'load-001' }], ['serverSession', { actorId: freshId(), sessionId: freshId() }]]) {
    await assert.rejects(local.bridge.read(name, args));
  }
  assert.equal(local.calls.length, 0); local.bridge.close();
});

test('Management transport does not send its private bearer before TLS verifies and rejects late or invalid handshakes', async () => {
  const local = localTransport({ socketDeferred: true }), socket = new EventEmitter(); socket.encrypted = true; socket.authorized = false;
  const pending = local.bridge.read('calendar'); local.calls[0].req.emit('socket', socket);
  await Promise.resolve(); assert.equal(local.sent(), 0);
  socket.emit('secureConnect'); await assert.rejects(pending, { code: 'EXACT_DEVELOPMENT_TARGET_REQUIRED' });
  socket.authorized = true; socket.emit('secureConnect'); assert.equal(local.sent(), 0); local.bridge.close();
  const failed = localTransport({ socketDeferred: true }); const next = failed.bridge.read('calendar');
  failed.calls[0].req.emit('error', new Error('private-pat-detail'));
  await assert.rejects(next, { code: 'TRANSPORT_UNCERTAIN' });
  failed.calls[0].req.emit('socket', { encrypted: true, authorized: true }); assert.equal(failed.sent(), 0); failed.bridge.close();
});

test('query error, redirect, malformed body, oversized body and unproved read-only mode fail closed without exposing private response text', async () => {
  for (const config of [{ requestError: true }, { responseError: true }, { status: 302, response: 'redirect-private-value' },
    { status: 401, response: { message: 'private-pat-value' } }, { response: 'not-json' }, { response: 'x'.repeat(8388610) },
    { response: [{ ...packet([])[0], read_only: 'off' }] }, { response: { rows: [] } }]) {
    const local = localTransport(config);
    await assert.rejects(local.bridge.read('calendar'), error => !error.message.includes('private') && !error.message.includes('not-json'));
    assert.equal(local.calls.length, 1); local.bridge.close();
  }
});

test('Management reads bind all 500 exact scopes and only a supplied genuine actor/session pair', async () => {
  const local = localTransport({ response: packet([]) });
  await local.bridge.read('loadLedgers'); const load = JSON.parse(local.calls[0].bytes);
  assert.equal(load.parameters[0].length, 500); assert.equal(new Set(load.parameters[0]).size, 500);
  assert.deepEqual(load.parameters[0], review.syntheticScopes.map(target => target.tenantId));
  assert.equal(load.parameters[1], '778237e3-3d4e-4871-8cc9-e08b07b989c7');
  const sessionId = freshId(); await local.bridge.read('serverSession', { actorId: actualIds.proposer, sessionId });
  const session = JSON.parse(local.calls[1].bytes); assert.deepEqual(session.parameters, [sessionId, actualIds.proposer]);
  assert.ok(!/refresh_token|password|ip_address|user_agent/.test(session.query)); local.bridge.close();
});

test('mutating caller review or Auth IDs after construction cannot retarget a later Management SELECT', async () => {
  const mutableReview = structuredClone(review), mutableIds = { ...actualIds }, local = localTransport();
  const create = implementation.createSupabaseManagementReadBridge;
  const bridge = create({ review: mutableReview, authIds: mutableIds, privateManagementToken: privateToken,
    requestFactory: (url, options, cb) => {
      const result = new EventEmitter(); result.destroy = () => {};
      result.end = bytes => { local.calls.push({ url: url.href, bytes }); queueMicrotask(() => {
        const res = new EventEmitter(); res.statusCode = 201; cb(res); res.emit('data', Buffer.from(JSON.stringify(packet([])))); res.emit('end');
      }); }; queueMicrotask(() => result.emit('socket', { encrypted: true, authorized: true })); return result;
    }, agentFactory: () => ({ destroy() {} }) });
  mutableReview.syntheticScopes.find(target => target.key === 'runtime').tenantId = freshId(); mutableIds.proposer = freshId();
  await bridge.read('sourcePopulation', { scopeKey: 'runtime' });
  assert.deepEqual(JSON.parse(local.calls[0].bytes).parameters, [scope.tenantId]);
  await assert.rejects(bridge.read('serverSession', { actorId: mutableIds.proposer, sessionId: freshId() })); bridge.close(); local.bridge.close();
});

test('Management abort and total queue timeout stop this bridge only and never retry the original request', async () => {
  const local = localTransport({ socketDeferred: true }), signal = new AbortController();
  const aborted = local.bridge.read('calendar', {}, signal.signal); signal.abort(); await assert.rejects(aborted, { code: 'RUN_ABORTED' });
  local.calls[0].req.emit('socket', { encrypted: true, authorized: true }); assert.equal(local.sent(), 0);
  const timedOut = local.bridge.read('calendar'); await assert.rejects(timedOut, { code: 'TRANSPORT_TIMEOUT' });
  assert.equal(local.calls.length, 2); local.bridge.close();
  await assert.rejects(local.bridge.read('calendar'), { code: 'RUN_ABORTED' }); assert.equal(local.calls.length, 2);
});

test('Management read metadata and result hashes change with actual server results and incomplete packet identity is rejected', async () => {
  const first = localTransport({ response: packet([{ value: 1 }]) }), second = localTransport({ response: packet([{ value: 2 }]) });
  const one = await first.bridge.read('calendar'), two = await second.bridge.read('calendar');
  assert.notEqual(one.snapshotSha256, two.snapshotSha256); assert.notEqual(one.transportEvidenceSha256, two.transportEvidenceSha256);
  assert.equal(one.snapshotSha256, hashBytes(JSON.stringify([{ value: 1 }]))); first.bridge.close(); second.bridge.close();
  for (const extra of [{ backend_id: null }, { snapshot_id: null }, { observed_at: 'invalid' }, { isolation: 'bogus' }]) {
    const invalid = localTransport({ response: [{ ...packet([])[0], ...extra }] }); await assert.rejects(invalid.bridge.read('calendar')); invalid.bridge.close();
  }
});
