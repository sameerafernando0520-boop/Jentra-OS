import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { handleOrganizationIdentity } from '../functions/org-identity/handler.mjs';
import { fault, handleSubscriptionHandover, handoverKey } from '../functions/subscription-handover/handler.mjs';

export async function testSubscriptionHandover(db) {
  const buyer = randomUUID();
  const admin = randomUUID();
  const buyerEmail = 'purchase-handover@fixture.test';
  const schedulerSecret = 'fixture-only-scheduler-secret-' + randomUUID();
  const rollback = new Error('Roll back handover fixtures');

  try {
    await db.transaction(async (tx) => {
      const value = async (sql, args = []) => (await tx.query(sql, args)).rows[0]?.value;
      const setActor = async (id, session = null, role = 'authenticated') => {
        await tx.exec('reset role');
        await tx.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
          sub: id, aal: 'aal1', session_id: session, role,
        })]);
        await tx.exec('set local role ' + role);
      };
      const adminRpc = (name, args) => value('select api.' + name + '(' + Object.keys(args)
        .map((key, index) => key + ' => $' + (index + 1)).join(',') + ') as value', Object.values(args));
      const useService = () => setActor(null, null, 'service_role');
      const flushAuth = () => tx.exec('set constraints all immediate; set constraints all deferred;');
      const rejects = async (action, pattern) => {
        await tx.exec('savepoint handover_check');
        await assert.rejects(action, pattern);
        await tx.exec('rollback to savepoint handover_check; release savepoint handover_check');
      };
      await tx.query('insert into auth.users(id,email,encrypted_password) values ($1,$2,$3)',
        [buyer, buyerEmail, randomUUID()]);
      await tx.exec("update billing.subscription_checkout_settings set enabled = true");
      await tx.exec("update billing.plans set price_minor = 0, price_currency_code = 'LKR', checkout_published = true,"
        + " checkout_description = 'Fixture', checkout_features = array['Fixture feature'],"
        + " checkout_demo_url = 'https://fixture.test/demo', checkout_demo_transcript = 'Fixture transcript',"
        + " checkout_term_days = 30 where code = 'starter'");

      const codes = [];
      const identity = async (action, extra = {}) => {
        const result = await handleOrganizationIdentity(new Request('https://fixture.test/identity', {
          method: 'POST', body: JSON.stringify({ action, ...extra }),
        }), {
          authenticate: () => ({ id: buyer, email: buyerEmail }),
          adminRpc,
          sendMail: (email, _subject, text) => codes.push({ email, code: text.match(/\b\d{8}\b/)[0] }),
          codeSecret: schedulerSecret,
          mailReady: true,
          log: () => {},
        });
        return result.status;
      };

      await useService();
      assert.equal(await identity('request_purchase_email_code', { email: 'override@fixture.test' }), 200);
      assert.equal(codes[0].email, buyerEmail);
      assert.equal(await identity('request_purchase_email_code'), 429);
      assert.equal(await identity('verify_purchase_email_code', { code: codes[0].code === '00000000' ? '00000001' : '00000000' }), 400);
      assert.equal(await identity('verify_purchase_email_code', { code: codes[0].code }), 200);
      assert.equal(await identity('verify_purchase_email_code', { code: codes[0].code }), 400);

      await setActor(buyer);
      const order = await value("select api.subscription_create_order('starter',1,'Handover Fixture',$1,null) as value",
        [randomUUID()]);
      assert.equal(order.status, 'paid');
      assert.equal(order.handover_status, 'pending');
      await rejects(() => adminRpc('subscription_claim_handover', {}), /permission denied/);

      const messages = [];
      const setPassword = async (user, metadata) => {
        await tx.exec('reset role');
        await tx.query('update auth.users set encrypted_password = $2 where id = $1', [user, randomUUID()]);
        await tx.query('update auth.users set raw_app_meta_data = raw_app_meta_data || $2 where id = $1', [user, metadata]);
        await flushAuth();
        await useService();
      };
      const worker = {
        secret: schedulerSecret,
        key: await handoverKey(Buffer.alloc(32, 91).toString('base64')),
        mailReady: true,
        log: () => {},
        rpc: adminRpc,
        createUser: async (email, password, metadata) => {
          assert.equal(email, order.username + '@admin.jentra.invalid');
          assert.match(password, /^Jt2-[0-9a-f]{48}$/);
          await tx.exec('reset role');
          await tx.query("insert into auth.users(id,email,encrypted_password) values ($1,$2,$3)",
            [admin, email, randomUUID()]);
          await tx.query('update auth.users set raw_app_meta_data = $2 where id = $1', [admin, metadata]);
          await flushAuth();
          await useService();
          return admin;
        },
        setPassword: (user, _password, metadata) => setPassword(user, metadata),
        sendMail: (message, key) => {
          messages.push({ message, key });
          if (messages.length === 1) throw fault('mail_unavailable');
          return 'fixture-' + messages.length;
        },
      };
      const tick = (secret = schedulerSecret) => handleSubscriptionHandover(new Request('https://fixture.test/tick', {
        method: 'POST', headers: { 'x-jentra-handover-secret': secret },
      }), worker);
      const sessionStart = (id = randomUUID()) => tx.query('insert into auth.sessions (id,user_id) values ($1,$2)', [id, admin]);
      const state = () => value('select status as value from billing.subscription_handover_jobs where order_id = $1', [order.id]);
      const identityPasswordAt = () => value(
        'select password_changed_at::text as value from core.organization_administrator_logins where user_id = $1', [admin]);
      const pendingPayload = () => value("select exists (select 1 from billing.subscription_handover_payloads) as value");

      assert.equal((await tick('incorrect-secret')).status, 401);
      await useService();
      assert.equal((await tick()).status, 200);
      await tx.exec('reset role');
      assert.equal(await state(), 'pending');
      assert.equal(await pendingPayload(), true);
      await rejects(sessionStart, /Temporary credential unavailable/);
      await tx.query("update billing.subscription_handover_jobs set next_attempt_at = clock_timestamp() where order_id = $1", [order.id]);
      await useService();
      assert.equal((await tick()).status, 200);
      assert.deepEqual(messages[0], messages[1], 'Retry keeps the password, recipient and Resend key');
      await tx.exec('reset role');
      assert.equal(await state(), 'sent');
      assert.equal(await pendingPayload(), false);
      const temporarySession = randomUUID();
      await sessionStart(temporarySession);
      await setActor(admin, temporarySession);
      assert.equal(await value('select core.is_tenant_member($1) as value', [order.tenant_id]), false);
      await tx.exec('reset role');
      const passwordAt = await identityPasswordAt();
      await rejects(async () => {
        await tx.query('update auth.users set encrypted_password = $2 where id = $1', [admin, randomUUID()]);
        await flushAuth();
      }, /Use the Jentra account setup/);

      await tx.exec('savepoint successful_rotation');
      await useService();
      const setupToken = await adminRpc('subscription_authorize_password_change',
        { p_user_id: admin, p_password_changed_at: passwordAt });
      await setPassword(admin, { jentra_subscription_reset_token: setupToken });
      await tx.exec('reset role');
      assert.equal(await state(), 'completed');
      const currentSession = randomUUID();
      await sessionStart(currentSession);
      await setActor(admin, currentSession);
      assert.equal(await value('select core.is_tenant_member($1) as value', [order.tenant_id]), true);
      await setActor(admin, temporarySession);
      assert.equal(await value('select core.is_tenant_member($1) as value', [order.tenant_id]), false);
      await tx.exec('rollback to savepoint successful_rotation; release savepoint successful_rotation; reset role');

      await tx.query("update core.organization_administrator_logins set temporary_password_expires_at = clock_timestamp() where user_id = $1", [admin]);
      await tx.query("update billing.subscription_handover_jobs set credential_expires_at = clock_timestamp(),"
        + " updated_at = clock_timestamp() - interval '2 minutes' where order_id = $1", [order.id]);
      await rejects(sessionStart, /Temporary credential unavailable/);
      await setActor(buyer);
      const expired = (await value('select api.subscription_checkout_orders() as value')).find((entry) => entry.id === order.id);
      assert.equal(expired.handover_status, 'expired');
      assert.equal(expired.handover_can_reissue, true);
      await adminRpc('subscription_reissue_handover', { p_order_id: order.id });

      await useService();
      assert.equal((await tick()).status, 200);
      assert.notEqual(messages[1].key, messages[2].key);
      assert.notEqual(messages[1].message.text, messages[2].message.text);
      await tx.exec('reset role');
      assert.equal(await state(), 'sent');
      await tx.query("update core.organization_administrator_logins set temporary_password_expires_at = clock_timestamp() where user_id = $1", [admin]);

      await useService();
      const hash = 'a'.repeat(64);
      const login = order.username + '@admin.jentra.invalid';
      assert.equal(await adminRpc('organization_issue_reset', { p_login_email: login, p_hash: hash }), buyerEmail);
      const recovery = await adminRpc('subscription_consume_password_reset', { p_login_email: login, p_hash: hash });
      assert.equal(recovery.user_id, admin);
      await setPassword(admin, { jentra_subscription_reset_token: recovery.reset_token });
      await tx.exec('reset role');
      assert.equal(await state(), 'completed');
      await setActor(buyer);
      await rejects(() => adminRpc('subscription_reissue_handover', { p_order_id: order.id }), /HANDOVER_UNAVAILABLE/);
      throw rollback;
    });
  } catch (cause) {
    if (cause !== rollback) throw cause;
  }
  console.log('Subscription verification, retry, expiry, reissue and verified recovery assertions passed.');
}
