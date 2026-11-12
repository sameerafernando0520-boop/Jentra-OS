import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { handleOrganizationIdentity } from '../functions/org-identity/handler.mjs';
import { handleSubscriptionHandover, handoverKey } from '../functions/subscription-handover/handler.mjs';

export async function testSystemSerials(db) {
  const rollback = new Error('Roll back system serial fixtures');
  const operator = randomUUID();
  const legacyOwner = randomUUID();
  const mailSecret = randomUUID() + randomUUID();
  try {
    await db.transaction(async tx => {
      const value = async (sql, args = []) => (await tx.query(sql, args)).rows[0]?.value;
      const rpc = (name, args = {}) => value('select api.' + name + '(' + Object.keys(args)
        .map((key, index) => key + ' => $' + (index + 1)).join(',') + ') as value', Object.values(args));
      const root = () => tx.exec('reset role');
      const actor = async (sub, aal = 'aal1', session_id = null, role = 'authenticated') => {
        await root();
        await tx.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({ sub, aal, session_id, role })]);
        await tx.exec('set local role ' + role);
      };
      const service = () => actor(null, null, null, 'service_role');
      const adminRpc = async (name, args) => {
        await service();
        return rpc(name, args);
      };
      const rejects = async (fn, expected) => {
        await tx.exec('savepoint system_failure');
        await assert.rejects(fn, expected);
        await tx.exec('rollback to savepoint system_failure; release savepoint system_failure');
      };
      const flushAuth = () => tx.exec('set constraints all immediate; set constraints all deferred');
      const createAuth = async (email, password, metadata) => {
        await root();
        const id = randomUUID();
        await tx.query(`insert into auth.users(id,email,email_confirmed_at,encrypted_password,raw_app_meta_data)
          values ($1,$2,clock_timestamp(),extensions.crypt($3,extensions.gen_salt('bf',4)),$4)`,
        [id, email, password, metadata]);
        await flushAuth();
        await service();
        return id;
      };
      const updateAuth = async (id, password, metadata) => {
        await root();
        await tx.query(`update auth.users set encrypted_password = extensions.crypt($2,extensions.gen_salt('bf',4)),
          raw_app_meta_data = raw_app_meta_data || $3 where id = $1`, [id, password, metadata]);
        await flushAuth();
        await service();
      };
      const session = async id => {
        await root();
        const key = randomUUID();
        await tx.query('insert into auth.sessions (id,user_id) values ($1,$2)', [key,id]);
        return key;
      };
      const authId = async username => {
        await root();
        return value('select id as value from auth.users where email = $1', [username + '@admin.jentra.invalid']);
      };
      const member = tenant => value('select core.is_tenant_member($1) as value', [tenant]);
      const rotate = async (id, managedStaff) => {
        await root();
        const passwordChangedAt = await value(
          'select password_changed_at::text as value from core.organization_administrator_logins where user_id = $1', [id]);
        const token = await adminRpc(managedStaff ? 'managed_staff_authorize_password_change' : 'subscription_authorize_password_change',
          { p_user_id: id, p_password_changed_at: passwordChangedAt });
        assert.ok(token);
        await updateAuth(id, 'Fixture-new-' + randomUUID(), {
          [managedStaff ? 'managed_staff_password_token' : 'jentra_subscription_reset_token']: token,
        });
        return session(id);
      };
      const mail = [];
      const identity = async (action, data, auth = null, aal = 'aal1', key = null) => {
        if (auth) await actor(auth, aal, key);
        const response = await handleOrganizationIdentity(new Request('https://fixture.test/org-identity', {
          method: 'POST', body: JSON.stringify({ action, ...data }),
        }), {
          authenticate: () => auth ? { id: auth } : null,
          isOperator: () => auth === operator && aal === 'aal2',
          callerRpc: rpc,
          adminRpc,
          createStaffUser: createAuth,
          updateStaffPassword: updateAuth,
          mailReady: true,
          codeSecret: mailSecret,
          ownerVerifyUrl: 'https://fixture.test/#/verify-system-owner',
          staffVerifyUrl: 'https://fixture.test/#/verify-staff',
          sendMail: (recipient, _subject, text) => mail.push({ recipient, text }),
          log: () => {},
        });
        return { status: response.status, data: await response.json() };
      };
      const worker = {
        secret: mailSecret,
        key: await handoverKey(Buffer.alloc(32, 91).toString('base64')),
        mailReady: true,
        log: () => {},
        rpc: adminRpc,
        createUser: createAuth,
        setPassword: updateAuth,
        sendMail: ({ to, text }) => {
          mail.push({ recipient: to, text });
          return randomUUID();
        },
      };
      const handover = async (target, email) => {
        const targetArgs = { verification_id: target.verification_id };
        const count = mail.length;
        assert.equal((await identity('system_owner_request_code', targetArgs, operator, 'aal1')).status, 403);
        assert.equal(mail.length, count);
        assert.equal((await identity('system_owner_request_code', { ...targetArgs, email: 'override@fixture.test' },
          operator, 'aal2')).status, 200);
        assert.equal(mail.at(-1).recipient, email);
        assert.match(mail.at(-1).text, /#\/verify-system-owner\?verification_id=/);
        const code = mail.at(-1).text.match(/Code: (\d{8})/)[1];
        assert.equal((await identity('system_owner_verify_code', { ...targetArgs, code })).status, 200);
        assert.equal((await identity('system_owner_verify_code', { ...targetArgs, code })).status, 400);
        const tick = await handleSubscriptionHandover(new Request('https://fixture.test/tick', {
          method: 'POST', headers: { 'x-jentra-handover-secret': mailSecret },
        }), worker);
        assert.equal(tick.status, 200);
        assert.equal(mail.at(-1).recipient, email);
        assert.ok(mail.at(-1).text.includes(target.username));
        assert.match(mail.at(-1).text, /Jt2-[a-f0-9]{48}/);
        return authId(target.username);
      };

      await tx.query(`insert into auth.users (id,email,email_confirmed_at) values
        ($1,'serial-operator@fixture.test',now()),($2,'legacy-owner@fixture.test',now())`, [operator,legacyOwner]);
      await tx.query('insert into intelligence_control.operators(actor_id,active,organization_manage) values ($1,true,true)', [operator]);
      await tx.exec(`update billing.plans set price_currency_code='LKR',price_minor=850000
        where code='starter'; update billing.plan_entitlements set enabled=true
        where plan_code='starter' and entitlement_code='module.people'`);
      const request = {
        p_name: 'ලක්මිණි වෙළඳාම',
        p_owner_email: 'serial-owner@fixture.test',
        p_plan_code: 'starter',
        p_expected_revision: 1,
        p_request_id: randomUUID(),
        p_mode: 'complimentary',
        p_reason: 'Controlled staging grant',
      };
      await actor(operator);
      await rejects(() => rpc('platform_create_system', request), /OPERATOR_ACCESS_REQUIRED/);
      await actor(operator, 'aal2');
      const created = await rpc('platform_create_system', request);
      assert.match(created.serial, /^J[0-9]{9}$/);
      assert.match(created.username, /^organization-[a-f0-9]{8}-j[0-9]{9}$/);
      assert.equal(created.owner_status, 'awaiting_verification');
      assert.deepEqual(await rpc('platform_create_system', request), created);
      await rejects(() => rpc('platform_create_system', { ...request, p_name: 'Different payload' }), /SYSTEM_REQUEST_CHANGED/);
      const paidRequest = {
        ...request, p_name: 'Lakmini Traders', p_request_id: randomUUID(), p_mode: 'paid', p_reason: null,
        p_payment_reference: 'SYSTEM-SERIAL-BANK-001', p_paid_amount_minor: 850000, p_paid_at: '2026-01-01T08:00:00Z',
      };
      await rejects(() => rpc('platform_create_system', { ...paidRequest, p_paid_amount_minor: 849999 }),
        /SUBSCRIPTION_VERIFIED_PAYMENT_REQUIRED/);
      const paid = await rpc('platform_create_system', paidRequest);
      assert.notEqual(paid.serial, created.serial);
      assert.equal(paid.username, 'lakmini-traders-' + paid.serial.toLowerCase());
      await rejects(() => rpc('platform_create_system', { ...paidRequest, p_request_id: randomUUID() }), { code: '23505' });
      await root();
      assert.equal(await value('select count(*)::int as value from billing.subscription_handover_jobs'), 0);
      await tx.query("update core.tenants set name='Renamed while awaiting handover' where id=$1", [created.tenant_id]);
      await rejects(() => tx.query("update core.tenants set system_serial='J999999999' where id=$1", [created.tenant_id]),
        /SYSTEM_SERIAL_IMMUTABLE/);
      await actor(operator, 'aal2');
      assert.equal((await rpc('platform_system_details', { p_tenant_id: created.tenant_id })).username, created.username);

      const owner = await handover(created, request.p_owner_email);
      const temporaryOwnerSession = await session(owner);
      await actor(owner, 'aal1', temporaryOwnerSession);
      assert.equal(await member(created.tenant_id), false);
      assert.equal(await rpc('system_registration_status'), null);
      const ownerSession = await rotate(owner, false);
      await actor(owner, 'aal1', ownerSession);
      const registration = await rpc('system_registration_status');
      assert.equal(registration.registration_required, true);
      assert.equal(registration.serial, created.serial);
      const register = {
        p_tenant_id: created.tenant_id,
        p_request_id: randomUUID(),
        p_entities: JSON.stringify([
          { name: 'Legal Alpha', code: 'ALPHA', branches: [{ name: 'Colombo', code: 'CB' }] },
          { name: 'Legal Beta', code: 'BETA', branches: [{ name: 'Kandy', code: 'KD' }] },
        ]),
      };
      await rejects(() => rpc('system_register_entities', { ...register, p_entities: JSON.stringify([
        { name: 'Legal Alpha', code: 'ALPHA', branches: [{ name: 'Colombo', code: 'CB' }] },
        { name: 'Bad Branch', code: 'BAD', branches: [] },
      ]) }), /INVALID_SYSTEM_REGISTRATION/);
      assert.deepEqual((await rpc('system_registration_status')).entities, []);
      const ready = await rpc('system_register_entities', register);
      assert.equal(ready.registration_required, false);
      assert.deepEqual(await rpc('system_register_entities', register), ready);
      assert.deepEqual(ready.entities.map(e => e.branches.length), [1, 1]);

      // The replacement owner may rotate while the original owner remains the only active owner.
      await actor(legacyOwner);
      const { tenant_id: legacy } = await value(`select api.bootstrap_tenant('Legacy Serial Fixture','legacy-serial-fixture',
        'Legacy Legal','LEG','Headquarters','HQ') as value`);
      await actor(operator, 'aal2');
      const cutover = await rpc('platform_begin_system_cutover', { p_tenant_id: legacy, p_request_id: randomUUID() });
      assert.equal(cutover.roster.length, 1);
      const commit = { p_migration_id: cutover.migration_id };
      await rejects(() => rpc('platform_commit_system_cutover', commit), /SYSTEM_CUTOVER_NOT_READY/);
      const replacement = await rpc('platform_stage_system_owner_cutover', {
        ...commit, p_owner_email: 'legacy-owner@fixture.test',
      });
      assert.equal(replacement.serial, cutover.serial);
      const newOwner = await handover(replacement, 'legacy-owner@fixture.test');
      const newSession = await rotate(newOwner, false);
      await actor(newOwner, 'aal1', newSession);
      assert.equal(await member(legacy), false);
      assert.deepEqual(await rpc('system_replacement_status'), { replacement_pending: true });
      await actor(legacyOwner);
      assert.equal(await member(legacy), true);
      await actor(operator, 'aal2');
      assert.equal((await rpc('platform_commit_system_cutover', commit)).status, 'completed');
      await actor(legacyOwner);
      assert.equal(await member(legacy), false);
      await actor(newOwner, 'aal1', newSession);
      assert.equal(await member(legacy), true);
      await actor(operator, 'aal2');
      assert.equal((await rpc('platform_rollback_system_cutover', { ...commit, p_reason: 'Rollback drill' })).status,
        'rolled_back');
      await actor(legacyOwner);
      assert.equal(await member(legacy), true);
      await actor(newOwner, 'aal1', newSession);
      assert.equal(await member(legacy), false);
      throw rollback;
    });
  } catch (error) {
    if (error !== rollback) throw error;
  }
  console.log('System serial, paid and complimentary creation, verified handover, group registration and owner cutover assertions passed.');
}
