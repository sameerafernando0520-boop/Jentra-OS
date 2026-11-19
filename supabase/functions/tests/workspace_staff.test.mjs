import test from 'node:test';
import assert from 'node:assert/strict';
import { handleWorkspaceStaff } from '../workspace-staff/handler.mjs';

const actor = '10000000-0000-0000-0000-000000000001';
const tenant = '20000000-0000-0000-0000-000000000001';
const requestId = '30000000-0000-0000-0000-000000000001';
const role = '40000000-0000-0000-0000-000000000001';
const userId = '50000000-0000-0000-0000-000000000001';
const member = '60000000-0000-0000-0000-000000000001';
const body = () => ({ operation: 'create', tenant_id: tenant, request_id: requestId,
  username: 'company_sales', display_name: 'Sales colleague', role_ids: [role], password: 'Synthetic-password-12!' });
function fixture() {
  const calls = [];
  const reservation = { request_id: requestId, tenant_id: tenant, created_by: actor,
    username: 'company_sales', display_name: 'Sales colleague', role_ids: [role],
    email: `staff.${requestId.replaceAll('-', '')}@accounts.jentra.invalid`, user_id: null, completed: false };
  const dependencies = {
    authenticate: async () => actor,
    reserve: async args => { calls.push(['reserve', args]); return reservation; },
    createUser: async args => { calls.push(['create', args]); return { id: userId }; },
    complete: async args => { calls.push(['complete', args]); return { request_id: requestId,
      tenant_id: tenant, username: reservation.username, user_id: userId, membership_id: member, status: 'active' }; },
    loginTarget: async username => { calls.push(['resolve', username]); return { email: reservation.email, limited: false }; },
    signIn: async (email, password) => { calls.push(['password', email, password]); return { refresh_token: 'synthetic-refresh', user: { id: userId } }; },
  };
  return { calls, reservation, dependencies };
}
const request = payload => new Request('https://example.test/workspace-staff', {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload),
});

test('oversized request cancels the unread body before staff or Auth work', async () => {
  const f = fixture();
  let pulls = 0;
  let cancelled = false;
  const body = new ReadableStream({
    pull(controller) {
      if (++pulls === 1) controller.enqueue(new Uint8Array(8193));
      else controller.close();
    },
    cancel() { cancelled = true; },
  }, { highWaterMark: 0 });
  const response = await handleWorkspaceStaff(new Request('https://example.test/workspace-staff', {
    method: 'POST', body, duplex: 'half',
  }), f.dependencies);
  assert.equal(response.status, 413);
  assert.deepEqual(await response.json(), { code: 'REQUEST_TOO_LARGE' });
  assert.equal(pulls, 1);
  assert.equal(cancelled, true);
  assert.deepEqual(f.calls, []);
});

test('admin creation binds trusted identity metadata and grants only after reservation', async () => {
  const f = fixture();
  const response = await handleWorkspaceStaff(request(body()), f.dependencies);
  assert.equal(response.status, 200);
  assert.deepEqual(f.calls.map(call => call[0]), ['reserve', 'create', 'complete']);
  assert.equal(f.calls[1][1].password, body().password);
  assert.equal(f.calls[1][1].app_metadata.jentra_created_by, actor);
  assert.equal(f.calls[1][1].app_metadata.jentra_tenant_id, tenant);
  assert.equal(f.calls[1][1].email_confirm, true);
  for (const [name, args] of f.calls) if (name !== 'create') assert(!JSON.stringify(args).includes(body().password));
  assert(!JSON.stringify(await response.json()).includes(body().password));
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('oversized request refusal does not wait for peer cancellation cleanup', async () => {
  const f = fixture();
  let cancelled = false;
  const bodyStream = new ReadableStream({
    pull(controller) { controller.enqueue(new Uint8Array(8193)); },
    cancel() { cancelled = true; return new Promise(() => {}); },
  }, { highWaterMark: 0 });
  let timer;
  try {
    const response = await Promise.race([
      handleWorkspaceStaff(new Request('https://example.test/workspace-staff', {
        method: 'POST', body: bodyStream, duplex: 'half',
      }), f.dependencies),
      new Promise((_, reject) => { timer = setTimeout(() => reject(Error('cancellation blocked refusal')), 1000); }),
    ]);
    assert.equal(response.status, 413);
    assert.equal(cancelled, true);
    assert.deepEqual(f.calls, []);
  } finally {
    clearTimeout(timer);
  }
});
test('unauthenticated caller cannot reserve or create an account', async () => {
  const f = fixture(); f.dependencies.authenticate = async () => null;
  assert.equal((await handleWorkspaceStaff(request(body()), f.dependencies)).status, 401);
  assert.deepEqual(f.calls, []);
});
test('MFA or permission refusal happens before Auth Admin creation', async () => {
  const f = fixture(); f.dependencies.reserve = async () => { throw { code: '42501' }; };
  assert.equal((await handleWorkspaceStaff(request(body()), f.dependencies)).status, 403);
  assert.deepEqual(f.calls, []);
});
test('completed request rechecks completion and never resets a password', async () => {
  const f = fixture(); f.reservation.user_id = userId; f.reservation.completed = true;
  assert.equal((await handleWorkspaceStaff(request(body()), f.dependencies)).status, 200);
  assert.deepEqual(f.calls.map(call => call[0]), ['reserve', 'password', 'complete']);
});
test('lost Auth creation response resumes only a matching reserved identity', async () => {
  const f = fixture();
  f.dependencies.createUser = async () => { f.reservation.user_id = userId; throw Error('timeout'); };
  assert.equal((await handleWorkspaceStaff(request(body()), f.dependencies)).status, 200);
  assert.deepEqual(f.calls.map(call => call[0]), ['reserve', 'reserve', 'password', 'complete']);
});
test('foreign reservation identity cannot authorize server-side creation', async () => {
  for (const field of ['tenant_id', 'created_by', 'request_id', 'username', 'email', 'display_name']) {
    const f = fixture(); f.reservation[field] = 'foreign';
    assert.equal((await handleWorkspaceStaff(request(body()), f.dependencies)).status, 503);
    assert.deepEqual(f.calls.map(call => call[0]), ['reserve']);
  }
});
test('recovery with a different password cannot falsely confirm credentials', async () => {
  const f=fixture(); f.reservation.user_id=userId;
  f.dependencies.signIn=async()=>{throw Error('wrong original password');};
  const response=await handleWorkspaceStaff(request(body()),f.dependencies);
  assert.equal(response.status,400);
  assert.deepEqual(await response.json(),{code:'STAFF_ORIGINAL_PASSWORD_REQUIRED'});
  assert.deepEqual(f.calls.map(call=>call[0]),['reserve']);
});
test('recovery requires a session belonging to the reserved Auth identity', async () => {
  for (const session of [null, {}, { user: { id: userId } },
    { user: { id: userId }, refresh_token: '' },
    { user: { id: actor }, refresh_token: 'synthetic-refresh' }]) {
    const f = fixture();
    f.reservation.user_id = userId;
    f.dependencies.signIn = async () => session;
    const response = await handleWorkspaceStaff(request(body()), f.dependencies);
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { code: 'STAFF_ORIGINAL_PASSWORD_REQUIRED' });
    assert.deepEqual(f.calls.map(call => call[0]), ['reserve']);
  }
});

test('request limit counts UTF-8 bytes rather than characters', async () => {
  const f = fixture();
  const response = await handleWorkspaceStaff(request({ ...body(), display_name: 'é'.repeat(4096) }), f.dependencies);
  assert.equal(response.status, 413);
  assert.deepEqual(f.calls, []);
});

test('request stream permits exactly the byte limit and rejects the next chunk', async () => {
  for (const extra of [0, 1]) {
    const f = fixture();
    const json = JSON.stringify(body());
    const text = json + ' '.repeat(8192 - new TextEncoder().encode(json).length);
    let chunk = 0;
    let cancelled = false;
    const bodyStream = new ReadableStream({
      pull(controller) {
        if (chunk++ === 0) controller.enqueue(new TextEncoder().encode(text));
        else if (extra && chunk === 2) controller.enqueue(new Uint8Array([32]));
        else controller.close();
      },
      cancel() { cancelled = true; },
    }, { highWaterMark: 0 });
    const response = await handleWorkspaceStaff(new Request('https://example.test/workspace-staff', {
      method: 'POST', body: bodyStream, duplex: 'half',
    }), f.dependencies);
    assert.equal(response.status, extra ? 413 : 200);
    assert.equal(cancelled, Boolean(extra));
    if (extra) assert.deepEqual(f.calls, []);
  }
});
test('unknown fields, weak password and invalid role IDs are rejected', async () => {
  for (const patch of [{ password: 'short' }, { role_ids: [] }, { role_ids: ['owner'] }, { service_role: true }]) {
    const f = fixture();
    assert.equal((await handleWorkspaceStaff(request({ ...body(), ...patch }), f.dependencies)).status, 400);
    assert.deepEqual(f.calls, []);
  }
});
test('final authorization refusal neither reports success nor returns credentials', async () => {
  const f = fixture(); f.dependencies.complete = async () => { throw { code: '42501', message: body().password }; };
  const response = await handleWorkspaceStaff(request(body()), f.dependencies);
  assert.equal(response.status, 403);
  assert(!JSON.stringify(await response.json()).includes(body().password));
});
test('unexpected Auth diagnostics are sanitized', async () => {
  const f = fixture(); f.dependencies.createUser = async () => { throw Error(body().password); };
  const response = await handleWorkspaceStaff(request(body()), f.dependencies);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { code: 'STAFF_RESULT_UNCONFIRMED' });
});
test('changed delegation is a distinct terminal result without resetting access', async () => {
  const f=fixture();f.dependencies.complete=async()=>{throw {code:'42501',message:'STAFF_ACCESS_CHANGED'};};
  const response=await handleWorkspaceStaff(request(body()),f.dependencies);
  assert.equal(response.status,409);
  assert.deepEqual(await response.json(),{code:'STAFF_ACCESS_CHANGED'});
});
test('username sign-in returns a refresh credential only after password verification', async () => {
  const f = fixture();
  const response = await handleWorkspaceStaff(request({ operation: 'login', username: ' Company_Sales ', password: 'supplied-password' }), f.dependencies);
  assert.equal(response.status, 200);
  assert.deepEqual(f.calls.map(call => call[0]), ['resolve', 'password']);
  assert.deepEqual(await response.json(), { refresh_token: 'synthetic-refresh' });
});
test('unknown and incorrect usernames have identical failures', async () => {
  const f = fixture(); f.dependencies.loginTarget = async () => ({ email: null, limited: false });
  const unknown = await handleWorkspaceStaff(request({ operation: 'login', username: 'unknown_user', password: 'wrong' }), f.dependencies);
  const g = fixture(); g.dependencies.signIn = async () => { throw Error('private Auth details'); };
  const wrong = await handleWorkspaceStaff(request({ operation: 'login', username: 'company_sales', password: 'wrong' }), g.dependencies);
  assert.equal(unknown.status, 401); assert.equal(wrong.status, 401);
  assert.deepEqual(await unknown.json(), await wrong.json());
  assert.deepEqual(f.calls.map(call => call[0]), ['password']);
});
test('application rate limits run before password authentication', async () => {
  const f = fixture(); f.dependencies.loginTarget = async () => ({ email: null, limited: true });
  assert.equal((await handleWorkspaceStaff(request({ operation: 'login', username: 'company_sales', password: 'wrong' }), f.dependencies)).status, 429);
  assert.deepEqual(f.calls, []);
});
