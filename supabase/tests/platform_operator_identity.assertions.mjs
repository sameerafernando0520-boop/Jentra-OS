import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { handleOrganizationIdentity } from '../functions/org-identity/handler.mjs';

export async function testPlatformOperatorIdentity(db) {
  const operator = randomUUID();
  const outsider = randomUUID();
  const login = 'operator-identity@fixture.test';
  const recovery = 'operator-recovery@fixture.test';
  const other = 'operator-other@fixture.test';
  const passwords = ['Fixture initial pass 3', 'Fixture changed pass 4', 'Fixture reset pass 5'];
  const rollback = new Error('Roll back operator fixtures');
  const mail = [];
  const background = [];

  try {
    await db.transaction(async (tx) => {
      const value = async (sql, args = []) => (await tx.query(sql, args)).rows[0]?.value;
      let actor = operator;
      let session;
      let aal = 'aal2';
      let password;
      const setClaims = async (role = 'authenticated') => {
        await tx.exec('reset role');
        await tx.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
          sub: actor, aal, session_id: session, role,
        })]);
        await tx.exec('set local role ' + role);
      };
      const caller = async (sql, args = []) => {
        await setClaims();
        return value(sql, args);
      };
      const rpc = async (name, args) => {
        await setClaims('service_role');
        const placeholders = Object.keys(args).map((key, index) => key + ' => $' + (index + 1));
        return value('select api.' + name + '(' + placeholders.join(',') + ') as value', Object.values(args));
      };
      const platformSession = async () => {
        await tx.exec('reset role');
        session = randomUUID();
        await tx.query('insert into auth.sessions (id,user_id) values ($1,$2)', [session, operator]);
      };
      const expectForbidden = async (action, pattern) => {
        await tx.exec('savepoint operator_scope');
        await assert.rejects(action, pattern);
        await tx.exec('rollback to savepoint operator_scope; release savepoint operator_scope');
      };
      const services = {
        authenticate: () => ({ id: actor, email: actor === operator ? login : other }),
        operatorProfile: async () => {
          await tx.exec('savepoint operator_profile');
          try {
            const profile = await caller('select api.platform_operator_identity_profile() as value');
            await tx.exec('release savepoint operator_profile');
            return profile;
          } catch (cause) {
            await tx.exec('rollback to savepoint operator_profile; release savepoint operator_profile');
            throw Object.assign(cause, { code: cause.code === '42501' ? 'forbidden' : cause.code });
          }
        },
        adminRpc: rpc,
        codeSecret: 'operator-test-key-' + randomUUID(),
        mailReady: true,
        background: (job) => background.push(job),
        log: () => {},
        checkPassword: (_actor, current) => password === current,
        setOperatorPassword: async (id, next, token) => {
          await tx.exec('reset role');
          await tx.query('update auth.users set encrypted_password = $2 where id = $1', [id, randomUUID()]);
          await tx.query('update auth.users set raw_app_meta_data = raw_app_meta_data || $2 where id = $1',
            [id, { jentra_operator_password_token: token }]);
          await tx.exec('set constraints all immediate; set constraints all deferred');
          password = next;
        },
        sendMail: (email, _subject, text) => mail.push({ email, code: text.match(/\b\d{8}\b/)[0] }),
      };
      const invoke = async (action, fields = {}) => {
        const response = await handleOrganizationIdentity(new Request('https://fixture.test/identity', {
          method: 'POST', body: JSON.stringify({ action, ...fields }),
        }), services);
        await Promise.all(background.splice(0));
        return [response.status, await response.json()];
      };

      await tx.query('insert into auth.users(id,email) values ($1,$2),($3,$4)', [operator, login, outsider, other]);
      await tx.query('insert into intelligence_control.operators (actor_id, active, organization_manage) values ($1,true,true)', [operator]);
      await platformSession();
      actor = outsider;
      assert.equal((await invoke('operator_profile'))[0], 403);
      actor = operator;
      aal = 'aal1';
      assert.equal((await invoke('operator_profile'))[0], 403);
      aal = 'aal2';
      const initial = await invoke('operator_profile');
      assert.equal(initial[0], 200);
      assert.equal(initial[1].has_password, false);
      assert.equal(initial[1].email, login);
      assert.equal(initial[1].recovery_verified, false);

      await expectForbidden(() => caller(
        'select api.platform_operator_issue_recovery_verification($1,null,$2,$3) as value',
        [operator, recovery, 'a'.repeat(64)]), /permission denied/);
      assert.equal((await invoke('set_operator_password', { new_password: passwords[0], actor_id: outsider }))[0], 200);
      assert.equal(await caller('select api.platform_organization_access() as value'), false);
      await platformSession();
      assert.equal((await invoke('set_operator_password', { new_password: passwords[1] }))[0], 409);
      assert.equal((await invoke('change_operator_password', { current_password: 'incorrect', new_password: passwords[1] }))[0], 403);
      assert.equal((await invoke('change_operator_password', { current_password: passwords[0], new_password: passwords[1] }))[0], 200);
      assert.equal((await invoke('operator_profile'))[0], 403);
      await platformSession();

      assert.equal((await invoke('request_operator_recovery_email', { email: login, current_password: passwords[1] }))[0], 400);
      assert.equal((await invoke('request_operator_recovery_email', { email: recovery, current_password: passwords[1] }))[0], 200);
      assert.equal(mail[0].email, recovery);
      assert.equal((await invoke('operator_profile'))[1].pending_recovery_email, recovery);
      assert.deepEqual(await invoke('request_operator_reset', { login }), [200, { ok: true }]);
      assert.equal(mail.length, 1, 'unverified mailbox cannot receive a reset code');
      assert.equal((await invoke('verify_operator_recovery_email', { code: mail[0].code }))[0], 200);
      assert.equal((await invoke('verify_operator_recovery_email', { code: mail[0].code }))[0], 400);
      assert.equal((await invoke('operator_profile'))[1].recovery_email, recovery);

      await tx.exec('reset role');
      await tx.query('update core.organization_account_recovery set email = $2, verified_at = now() where user_id = $1',
        [operator, other]);
      assert.deepEqual(await invoke('request_reset', { login }), [200, { ok: true }]);
      assert.deepEqual(await invoke('request_operator_reset', { login: other }), [200, { ok: true }]);
      assert.equal(mail.length, 1, 'operator and tenant recovery do not cross over');
      assert.deepEqual(await invoke('request_operator_reset', { login }), [200, { ok: true }]);
      assert.equal(mail[1].email, recovery);
      const reset = { login, code: mail[1].code, new_password: passwords[2] };
      assert.equal((await invoke('reset_operator_password', reset))[0], 200);
      assert.equal((await invoke('reset_operator_password', reset))[0], 400);
      assert.equal(await caller('select api.platform_organization_access() as value'), false);
      await platformSession();
      aal = 'aal1';
      assert.equal(await caller('select api.platform_organization_access() as value'), false);
      aal = 'aal2';
      assert.equal(await caller('select api.platform_organization_access() as value'), true);
      await tx.exec('reset role');
      await tx.query('update intelligence_control.operators set active = false where actor_id = $1', [operator]);
      await tx.query("update core.organization_identity_challenges set issued_at = now() - interval '2 minutes'"
        + " where user_id = $1 and purpose = 'operator_reset'", [operator]);
      assert.equal((await invoke('operator_profile'))[0], 403);
      assert.deepEqual(await invoke('request_operator_reset', { login }), [200, { ok: true }]);
      assert.equal(mail.length, 2, 'disabled operators receive no reset email');
      throw rollback;
    });
  } catch (cause) {
    if (cause !== rollback) throw cause;
  }
  console.log('Platform operator password setup, change, verified recovery and MFA scope assertions passed.');
}
