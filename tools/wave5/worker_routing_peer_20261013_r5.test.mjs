import test from 'node:test';
import assert from 'node:assert/strict';
import { createEdgeRuntime as candidateRuntime } from '../../workers/wave5/edge_runtime_20261013_r5.mjs';
import { createEdgeReceiver as candidateReceiver } from '../../workers/wave5/edge_receiver_20261013_r5.mjs';
import { createEdgeRuntime as approvedRuntime } from '../../workers/wave5/edge_runtime.mjs';
import { createEdgeReceiver as approvedReceiver } from '../../workers/wave5/edge_receiver.mjs';
import { edgeRoute } from '../../workers/wave5/edge_route_20261013_r5.mjs';
import { edgeConfiguration as config } from '../../workers/wave5/edge_configuration.mjs';
import { forecastEvent, signDelivery } from '../../workers/wave5/integration_policy.mjs';

// Controlled values only: no actual credentials, Auth session, network, SQL or
// installed worker is used. The fake service-key-shaped string is a test stub.
const env = { SUPABASE_URL: config.url, SUPABASE_SERVICE_ROLE_KEY: 'a'.repeat(40) + '.' + 'b'.repeat(40) + '.' + 'c'.repeat(40) };
const id = '00000000-0000-4000-8000-000000000001';
test('independent original-versus-candidate probe isolates the platform path failure', async () => {
  const results = [];
  for (const make of [approvedRuntime, candidateRuntime]) {
    let effects = 0;
    const handler = make({ env, edgeRpcFactory: () => async () => { effects++; return { permitted: false }; } });
    const answer = await handler(new Request(config.url + '/wave5-runtime/schedule', { method: 'POST',
      headers: { 'content-type': 'application/json', 'x-jentra-schedule-key': 'd'.repeat(64) },
      body: JSON.stringify({ tickId: id, kind: 'health' }) }));
    results.push({ status: answer.status, value: await answer.json(), effects });
  }
  assert.deepEqual(results[0], { status: 404, value: { code: 'NOT_FOUND' }, effects: 0 });
  assert.deepEqual(results[1], { status: 200, value: { state: 'already_running' }, effects: 1 });
  const unsigned = new Request(config.url + '/wave5-receiver/accept', { method: 'POST' });
  assert.equal((await approvedReceiver({ env })(unsigned.clone())).status, 404);
  assert.equal((await candidateReceiver({ env })(unsigned.clone())).status, 403);
});
test('both complete namespaces exclude other functions, nested prefixes and private URL credentials', () => {
  for (const publicPrefix of ['/functions/v1/', '/']) {
    for (const name of ['wave5-runtime', 'wave5-receiver']) {
      const endpoint = config.url + '/functions/v1/' + name;
      assert.equal(edgeRoute(config.url + publicPrefix + name + '/accept', endpoint, ['/accept']), '/accept');
      for (const suffix of ['x/accept', '/accept/extra', '//accept', '/%61ccept', '/accept?x=1', '/accept#x'])
        assert.equal(edgeRoute(config.url + publicPrefix + name + suffix, endpoint, ['/accept']), null);
      assert.equal(edgeRoute(config.url + publicPrefix + (name === 'wave5-runtime' ? 'wave5-receiver' : 'wave5-runtime') + '/accept', endpoint, ['/accept']), null);
      for (const origin of ['https://user@xpdoufauvrbdmxgngetv.supabase.co', 'https://user:pass@xpdoufauvrbdmxgngetv.supabase.co',
        'https://xpdoufauvrbdmxgngetv.supabase.co:8443', 'https://xpdoufauvrbdmxgngetv.supabase.co.other.invalid', 'http://xpdoufauvrbdmxgngetv.supabase.co'])
        assert.equal(edgeRoute(origin + publicPrefix + name + '/accept', endpoint, ['/accept']), null);
    }
  }
});
test('candidate runtime keeps method and signed-schedule authorization before trusted effects', async () => {
  for (const prefix of ['/functions/v1/', '/']) {
    let reads = 0, effects = 0;
    const handler = candidateRuntime({ env: { get(name) { reads++; return env[name]; } },
      edgeRpcFactory: () => async () => { effects++; throw Error('UNEXPECTED_CONTROLLED_EFFECT'); } });
    for (const method of ['GET', 'PUT', 'DELETE', 'PATCH', 'OPTIONS', 'HEAD']) {
      assert.equal((await handler(new Request(config.url + prefix + 'wave5-runtime/schedule', { method }))).status, 404);
    }
    assert.equal(reads, 0); assert.equal(effects, 0);
    for (const header of [undefined, '', 'd'.repeat(63), 'D'.repeat(64)]) {
      const headers = header === undefined ? {} : { 'x-jentra-schedule-key': header };
      assert.equal((await handler(new Request(config.url + prefix + 'wave5-runtime/schedule', { method: 'POST', headers, body: '{}' }))).status, 403);
    }
    assert.equal(effects, 0);
  }
});
test('candidate receiver unsigned and malformed route matrix never reads private keys', async () => {
  let reads = 0, effects = 0;
  const handler = candidateReceiver({ env: { get() { reads++; throw Error('PRIVATE_READ_FORBIDDEN'); } },
    rpcFactory: () => { effects++; throw Error('TRUSTED_RPC_FORBIDDEN'); } });
  for (const prefix of ['/functions/v1/', '/']) for (const route of ['accept', 'redirect', 'timeout', 'reject']) {
    assert.equal((await handler(new Request(config.url + prefix + 'wave5-receiver/' + route, { method: 'POST' }))).status, 403);
    for (const suffix of ['/extra', '?x=1', '#x']) {
      assert.equal((await handler(new Request(config.url + prefix + 'wave5-receiver/' + route + suffix, { method: 'POST' }))).status, 404);
    }
  }
  assert.equal(reads, 0); assert.equal(effects, 0);
});
test('receiver byte authentication and server revocation are invariant across old public and new platform routing', async () => {
  const timestamp = 1791529200, key = Buffer.from('a'.repeat(64), 'hex');
  const event = { eventId: id, type: 'analytics.forecast.frozen.v1', tenantId: id, legalEntityId: id, branchId: id,
    forecastId: id, definitionVersion: 1, sourceHash: 'a'.repeat(64) }, payload = forecastEvent(event, event);
  for (const [make, prefix] of [[approvedReceiver, '/functions/v1/'], [candidateReceiver, '/functions/v1/'], [candidateReceiver, '/']]) {
    for (const forged of [false, true]) {
      const effects = [];
      const handler = make({ env, now: () => timestamp, rpcFactory: () => async (_name, parameters) => {
        effects.push(parameters.p_action); if (parameters.p_action === 'key') return { value: 'a'.repeat(64) };
        throw Error('RUNTIME_SCOPE_DENIED');
      } });
      const answer = await handler(new Request(config.url + prefix + 'wave5-receiver/accept', { method: 'POST',
        headers: { 'content-type': 'application/json', 'x-jentra-event-id': id, 'x-jentra-timestamp': String(timestamp),
          'x-jentra-signature': forged ? 'v1=' + 'b'.repeat(64) : signDelivery({ payload, eventId: id, timestamp, key, keyVersion: 1 }) }, body: payload }));
      assert.equal(answer.status, forged ? 403 : 503); assert.deepEqual(effects, forged ? ['key'] : ['key', 'receive']);
      assert.ok(!JSON.stringify(await answer.json()).includes('RUNTIME_SCOPE_DENIED'));
    }
  }
});
