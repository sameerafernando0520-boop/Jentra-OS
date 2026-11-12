// Run with Node and the local PGlite package. All users and mail are fixtures.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { handleOrganizationIdentity } from '../functions/org-identity/handler.mjs';

const localRuntime = new URL('../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js', import.meta.url);
const runtime = process.env.JENTRA_PGLITE_MODULE ? pathToFileURL(process.env.JENTRA_PGLITE_MODULE) : localRuntime;
const { PGlite } = await import(runtime.href);
const { pgcrypto } = await import(new URL('contrib/pgcrypto.js', runtime).href);
const db = new PGlite({ extensions: { pgcrypto } });
const operator = randomUUID();
const signupAddress = 'subscriber@fixture.example';
const replacementAddress = 'recovery@fixture.example';
const initialPassword = 'Fixture temporary password 1';
const nextPassword = 'Fixture replacement password 2';
const resetPassword = 'Fixture final reset password 3';
const mail = [];
const jobs = [];
const passwords = new Map();
let actor;
let session;
let rejectMail = false;

const query = async (sql, params = [], target = db) => (await target.query(sql, params)).rows[0]?.value;
const sessionAs = async (currentActor, aal, run, currentSession = session) => db.transaction(async (tx) => {
  await tx.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
    role: 'authenticated', sub: currentActor.id, email: currentActor.email,
    session_id: currentSession, aal,
  })]);
  await tx.exec('set local role authenticated');
  return run(tx);
});
const setSession = async (id, email) => {
  session = randomUUID();
  actor = { id, email };
  await db.query('insert into auth.sessions(id,user_id) values ($1,$2)', [session, id]);
};

const serviceRpc = async (name, args) => {
  const values = Object.values(args);
  try {
    return await db.transaction(async (tx) => {
      await tx.exec('set local role service_role');
      return query(`select api.${name}(${values.map((_, index) => `$${index + 1}`).join(',')}) as value`, values, tx);
    });
  } catch (cause) {
    throw Object.assign(new Error(cause.message), { code: ({ '42501': 'forbidden', '22023': 'invalid_input' })[cause.code] });
  }
};

const services = {
  log: () => {},
  codeSecret: randomUUID(),
  mailReady: true,
  background: (job) => jobs.push(job),
  authenticate: () => actor,
  profile: () => sessionAs(actor, 'aal1', (tx) => query('select api.organization_identity_profile() as value', [], tx)),
  isOperator: () => sessionAs(actor, 'aal2', (tx) => query('select api.platform_organization_access() as value', [], tx)),
  operatorAssigned: () => sessionAs(actor, 'aal1',
    (tx) => query('select api.platform_organization_assignment() as value', [], tx)),
  staffCanProvision: (tenant) => sessionAs(actor, 'aal1',
    (tx) => query('select api.organization_staff_can_provision($1) as value', [tenant], tx)),
  adminRpc: serviceRpc,
  consumeReset: async (args) => ({ user_id: await serviceRpc('organization_consume_reset', args) }),
  authorizeChange: async () => null,
  createUser: async (email, password, tenant, department) => {
    const id = randomUUID();
    try {
      await db.transaction(async (tx) => {
        // GoTrue sets app_metadata after creating the row, in one transaction.
        await tx.query('insert into auth.users(id,email,encrypted_password,email_confirmed_at) values ($1,$2,$3,now())', [id, email, randomUUID()]);
        await tx.query(`update auth.users set raw_app_meta_data = jsonb_build_object(
          'managed_org_admin',true,'provisioned_tenant_id',$2::text,'department_account',$3::text) where id = $1`,
          [id, tenant, department ?? null]);
      });
    } catch (cause) {
      if (cause.code === '23505') throw Object.assign(Error('username unavailable'), { code: 'username_unavailable' });
      throw cause;
    }
    passwords.set(id, password);
    return id;
  },
  deleteUser: async (id) => db.query('delete from auth.users where id = $1', [id]),
  checkPassword: ({ id }, password) => passwords.get(id) === password,
  setPassword: async (id, password, generation) => {
    await db.transaction(async (tx) => {
      await tx.query('update auth.users set encrypted_password = $2 where id = $1', [id, randomUUID()]);
      if (generation) await tx.query(`update auth.users set raw_app_meta_data = raw_app_meta_data ||
        jsonb_build_object('jentra_handover_generation',$2::text) where id = $1`, [id, generation]);
    });
    passwords.set(id, password);
  },
  sendMail: async (address, subject, body) => {
    if (rejectMail) throw Error('simulated mail failure');
    mail.push({ address, subject, body });
  },
};

const invoke = async (action, data = {}) => {
  const response = await handleOrganizationIdentity(new Request('http://fixture.test', {
    method: 'POST', body: JSON.stringify({ action, ...data }),
  }), services);
  return { status: response.status, body: await response.json() };
};

const codeFromLatestMail = () => mail.at(-1).body.match(/\b[0-9]{8}\b/)[0];
const waitForMail = () => Promise.all(jobs.splice(0));

try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create role authenticator;
    create schema extensions;
    create schema auth;
    create schema intelligence_control;
    create table auth.users (id uuid primary key, email text unique, encrypted_password text,
      raw_app_meta_data jsonb not null default '{}', deleted_at timestamptz, banned_until timestamptz,
      email_confirmed_at timestamptz,
      created_at timestamptz not null default clock_timestamp());
    create table auth.sessions (id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
      created_at timestamptz not null default clock_timestamp(), not_after timestamptz);
    create table intelligence_control.operators (actor_id uuid primary key references auth.users(id),
      active boolean not null, health_read boolean not null default false, grant_manage boolean not null default false);
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
    $$;
    create function auth.uid() returns uuid language sql stable as $$ select (auth.jwt()->>'sub')::uuid $$;
    grant usage on schema auth, extensions to authenticated, service_role, anon;
  `);
  for (const name of ['20260831193714_create_greenfield_foundation', '20261105100000_organization_availability',
    '20261105101000_platform_organization_control', '20261105102000_organization_identity',
    '20261105103000_platform_organization_activity', '20261106090000_organization_department_accounts']) {
    try {
      const folder = name.startsWith('202611') ? 'candidates' : 'migrations';
      await db.exec(await readFile(new URL(`../${folder}/${name}.sql`, import.meta.url), 'utf8'));
    } catch (cause) {
      throw Error(`${name}: ${cause.message}`);
    }
  }
  await db.exec('grant usage on schema api to service_role;');
  await assert.rejects(db.query('insert into auth.users(id,email) values ($1,$2)', [randomUUID(), 'reserved@admin.jentra.invalid']),
    /Managed login address is reserved/);
  await db.query('insert into auth.users(id,email) values ($1,$2)', [operator, 'operator@fixture.example']);
  await db.query('insert into intelligence_control.operators(actor_id,active,organization_manage) values ($1,true,true)', [operator]);
  await db.exec("update billing.plans set price_minor = 0, price_currency_code = 'LKR' where code = 'starter'");
  await setSession(operator, 'operator@fixture.example');
  const createOrganization = (name, slug, email) => sessionAs(actor, 'aal2', (tx) => query(
    "select api.platform_create_organization($1,$2,$3,'starter','Asia/Colombo','LKR') as value", [name, slug, email], tx));
  const activate = (tenant, email) => sessionAs(actor, 'aal2', (tx) => query(
    "select api.platform_confirm_organization_activation($1,$2,null,0,'LKR') as value", [tenant, email], tx));
  const tenant = await createOrganization('Customer One', 'customer-one', signupAddress);
  const secondTenant = await createOrganization('Customer Two', 'customer-two', 'second@fixture.example');
  const signup = { tenant_id: tenant, username: 'customer.owner', signup_email: signupAddress, password: initialPassword };

  assert.deepEqual(await invoke('provision_admin', signup), { status: 403, body: { error: 'forbidden' } });
  assert.equal(mail.length, 0, 'no credential is sent before purchase confirmation');
  await activate(tenant, signupAddress);
  await activate(secondTenant, 'second@fixture.example');
  assert.deepEqual(await invoke('provision_admin', { ...signup, signup_email: 'wrong@fixture.example' }),
    { status: 400, body: { error: 'invalid_input' } });
  const abandoned = await services.createUser('customer.owner@admin.jentra.invalid', nextPassword, tenant);
  assert.equal((await invoke('provision_admin', signup)).status, 409, 'in-flight registration cannot be reclaimed');
  await db.query("update auth.users set created_at = now() - interval '2 minutes' where id = $1", [abandoned]);
  const first = await invoke('provision_admin', signup);
  assert.equal(first.status, 200);
  const owner = first.body.user_id;
  assert.notEqual(owner, abandoned, 'operator can retry an abandoned identity from the same tenant');
  assert.deepEqual(Object.keys(first.body).sort(), ['ok', 'user_id']);
  assert.equal(mail[0].address, signupAddress);
  assert.match(mail[0].body, /Username: customer\.owner/);
  assert.ok(mail[0].body.includes(initialPassword));

  rejectMail = true;
  const second = await invoke('provision_admin', { ...signup, username: 'customer.coowner', signup_email: replacementAddress });
  assert.deepEqual(second.body, { error: 'handover_failed', user_id: second.body.user_id });
  assert.equal(second.status, 502);
  assert.equal(await query('select handover_sent_at as value from core.organization_administrator_logins where user_id = $1', [second.body.user_id]), null);
  await db.query("update core.organization_administrator_logins set handover_requested_at = now()-interval '2 minutes' where user_id = $1", [second.body.user_id]);
  rejectMail = false;
  assert.equal((await invoke('reissue_admin', { ...signup, username: 'customer.coowner', password: resetPassword })).status, 200);
  assert.equal(mail.at(-1).address, replacementAddress);
  assert.equal(await query('select must_change_password as value from core.organization_administrator_logins where user_id = $1', [second.body.user_id]), true);

  await setSession(owner, 'customer.owner@admin.jentra.invalid');
  const originalSession = session;
  const profile = await invoke('profile');
  assert.equal(profile.body.must_change_password, true);
  assert.equal(profile.body.is_administrator, true);
  assert.equal(profile.body.recovery_email, signupAddress);
  const membership = (tx) => query('select core.is_tenant_member($1) as value', [tenant], tx);
  assert.equal(await sessionAs(actor, 'aal1', membership), false, 'temporary password does not unlock workspace data');
  assert.equal((await invoke('provision_admin', signup)).status, 403, 'tenant owner cannot provision from operator API');
  await assert.rejects(db.query('insert into core.memberships(tenant_id,user_id) values ($1,$2)', [secondTenant, owner]),
    /Managed account is assigned to one organization/);
  await assert.rejects(db.query('update auth.users set email = $2 where id = $1', [owner, replacementAddress]),
    /Managed login address cannot be changed/);

  assert.equal((await invoke('change_password', { current_password: 'wrong', new_password: nextPassword })).status, 403);
  assert.equal((await invoke('change_password', { current_password: initialPassword, new_password: nextPassword })).status, 200);
  assert.equal(await sessionAs(actor, 'aal1', membership, originalSession), false, 'pre-rotation session remains locked');
  await setSession(owner, 'customer.owner@admin.jentra.invalid');
  assert.equal(await sessionAs(actor, 'aal1', membership), true);
  const capabilities = (tx) => query('select array_agg(permission_code order by permission_code) as value from api.get_my_capabilities($1)', [tenant], tx);
  assert.ok((await sessionAs(actor, 'aal1', capabilities)).includes('core.members.invite'));
  assert.ok(!(await sessionAs(actor, 'aal1', capabilities)).includes('workflow.approve'));
  assert.ok((await sessionAs(actor, 'aal2', capabilities)).includes('workflow.approve'));
  await db.query("update core.tenants set status = 'suspended' where id = $1", [tenant]);
  assert.equal((await invoke('profile')).body.organization_locked, true);
  assert.equal(await sessionAs(actor, 'aal1', membership), false);
  await db.query("update core.tenants set status = 'active' where id = $1", [tenant]);
  assert.equal((await invoke('profile')).body.organization_locked, false);

  const staff = {
    tenant_id: tenant, name: 'Fixture Sales Staff', username: 'Fixture Sales Staff', department: 'sales',
    password: initialPassword, confirm_password: initialPassword, current_password: nextPassword,
  };
  assert.equal((await invoke('create_department_account', { ...staff, department: 'hr' })).status, 400);
  assert.equal((await invoke('create_department_account', { ...staff, tenant_id: secondTenant })).status, 403);
  assert.equal((await invoke('create_department_account', { ...staff, confirm_password: 'different' })).status, 400);
  assert.deepEqual(await invoke('create_department_account', staff),
    { status: 200, body: { ok: true, username: 'fixture-sales-staff' } });
  const staffId = await query('select user_id as value from core.organization_administrator_logins where username = $1',
    ['fixture-sales-staff']);
  const accounts = await sessionAs(actor, 'aal1',
    (tx) => query('select api.organization_department_staff($1) as value', [tenant], tx));
  assert.equal(accounts[0].department, 'sales');
  await setSession(staffId, 'fixture-sales-staff@admin.jentra.invalid');
  assert.equal((await invoke('profile')).body.is_administrator, false);
  assert.equal(await sessionAs(actor, 'aal1', membership), false);
  assert.equal((await invoke('change_password', { current_password: initialPassword, new_password: resetPassword })).status, 200);
  await setSession(staffId, 'fixture-sales-staff@admin.jentra.invalid');
  assert.equal(await sessionAs(actor, 'aal1', membership), true);
  assert.ok((await sessionAs(actor, 'aal1', capabilities)).some(code => code.startsWith('sales.')));
  assert.ok(!(await sessionAs(actor, 'aal1', capabilities)).includes('core.members.invite'));
  assert.equal(await sessionAs(actor, 'aal1',
    (tx) => query('select api.platform_organization_access() as value', [], tx)), false);
  assert.equal((await invoke('create_department_account', staff)).status, 403);
  await setSession(owner, 'customer.owner@admin.jentra.invalid');

  assert.equal((await invoke('request_recovery_email', { email: replacementAddress, current_password: nextPassword })).status, 200);
  assert.equal((await invoke('profile')).body.recovery_email, signupAddress, 'new email does not replace verified recovery until proven');
  assert.equal((await invoke('verify_recovery_email', { code: codeFromLatestMail() })).status, 200);
  assert.equal((await invoke('profile')).body.recovery_email, replacementAddress);

  const beforeReset = mail.length;
  const unknown = await invoke('request_reset', { login: 'unknown' });
  await waitForMail();
  assert.equal(mail.length, beforeReset);
  const existing = await invoke('request_reset', { login: 'Customer.Owner' });
  assert.deepEqual(existing, unknown, 'reset acknowledgement does not reveal registered identifiers');
  await waitForMail();
  assert.equal(mail.at(-1).address, replacementAddress);
  const code = codeFromLatestMail();
  await invoke('request_reset', { login: 'Customer.Owner' });
  await waitForMail();
  assert.equal(mail.length, beforeReset + 1, 'repeated requests are cooled down per account');
  const wrong = code === '00000000' ? '11111111' : '00000000';
  const reset = (givenCode) => invoke('reset_password', { login: 'Customer.Owner', code: givenCode, new_password: resetPassword });
  for (let index = 0; index < 5; index++) assert.equal((await reset(wrong)).status, 400);
  assert.equal((await reset(code)).status, 400, 'guess limit invalidates even a correct code');
  await db.query(`update core.organization_identity_challenges set issued_at = now()-interval '2 minutes'
    where user_id = $1 and purpose = 'reset'`, [owner]);
  await invoke('request_reset', { login: 'Customer.Owner' });
  await waitForMail();
  const replacementCode = codeFromLatestMail();
  await db.query(`update core.organization_identity_challenges set issued_at = now()-interval '11 minutes',
    expires_at = now()-interval '1 minute' where user_id = $1 and purpose = 'reset'`, [owner]);
  assert.equal((await reset(replacementCode)).status, 400, 'expired code cannot reset a password');
  await invoke('request_reset', { login: 'Customer.Owner' });
  await waitForMail();
  const finalCode = codeFromLatestMail();
  assert.deepEqual(await invoke('reset_password', {
    login: 'Customer.Owner', code: finalCode, new_password: 'no uppercase or number',
  }), { status: 400, body: { error: 'weak_password' } });
  assert.equal((await reset(finalCode)).status, 200);
  assert.equal((await reset(finalCode)).status, 400, 'successful code cannot be reused');
  assert.equal(passwords.get(owner), resetPassword);
  assert.equal(await sessionAs(actor, 'aal1', membership), false, 'password reset invalidates existing workspace access');
  console.log('Organization identity passed provisioning, recovery, tenant scope, permission and password rotation checks.');
} finally {
  await db.close();
}
