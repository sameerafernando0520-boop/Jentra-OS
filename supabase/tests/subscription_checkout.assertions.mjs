import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function testSubscriptionCheckout(db) {
  const operator = randomUUID();
  const buyer = randomUUID();
  const owner = randomUUID();
  const outsider = randomUUID();
  const signupEmail = 'verified-buyer@fixture.test';
  const request = randomUUID();
  const recoveredRequest = randomUUID();
  const rollback = new Error('Roll back checkout fixtures');

  try {
    await db.transaction(async (tx) => {
      const value = async (sql, args = []) => (await tx.query(sql, args)).rows[0]?.value;
      const actor = async (user, aal = 'aal1', role = 'authenticated') => {
        await tx.exec('reset role');
        await tx.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({ sub: user, aal, role })]);
        await tx.exec('set local role ' + role);
      };
      const rejects = async (fn, expected) => {
        await tx.exec('savepoint checkout_failure');
        await assert.rejects(fn, expected);
        await tx.exec('rollback to savepoint checkout_failure; release savepoint checkout_failure');
      };
      const access = () => value('select api.subscription_checkout_access() as value');
      const catalog = () => value('select api.subscription_checkout_catalog() as value');
      const order = (plan, revision, name, id = randomUUID(), renewalTenant = null) => value(
        'select api.subscription_create_order($1,$2,$3,$4,$5) as value',
        [plan, revision, name, id, renewalTenant]);
      const submit = (id, ref) => value('select api.subscription_submit_payment($1,$2) as value', [id, ref]);
      const review = (id, approved, ref, amount, time, reason = null, exception = null) => value(
        'select api.platform_review_subscription_payment($1,$2,$3,$4,$5,$6,$7) as value',
        [id, approved, ref, amount, time, reason, exception]);
      const bootstrap = () => value("select api.bootstrap_tenant('Legacy trial','legacy-trial','Legacy trial','MAIN','HQ','HQ') as value");
      const verify = (id, email) => value('select api.subscription_record_buyer_verification($1,$2) as value', [id, email]);
      const publish = (plan) => value(`select api.platform_save_subscription_publication(
        $1,2,'Storefront description',array['Published feature'],'https://media.fixture.test/demo.mp4',
        'Accessible demo transcript',30,true) as value`, [plan]);
      const bank = (name, account) => value(
        "select api.platform_save_subscription_bank($1,'Fixture merchant',$2,'Colombo','Use the order reference') as value",
        [name, account]);

      await tx.query(`insert into auth.users(id,email) values
        ($1,'checkout-operator@fixture.test'),($2,$3),($4,'checkout-owner@fixture.test'),($5,'outsider@fixture.test')`,
        [operator, buyer, signupEmail, owner, outsider]);
      await tx.query('insert into intelligence_control.operators(actor_id,active,organization_manage) values ($1,true,true)', [operator]);

      await actor(buyer);
      assert.equal((await access()).enabled, false);
      assert.deepEqual(await catalog(), []);
      await rejects(() => order('starter', 1, 'Café Studio', request), /SUBSCRIPTION_CHECKOUT_UNAVAILABLE/);
      await rejects(() => verify(buyer, signupEmail), { code: '42501' });

      await actor(operator, 'aal1');
      await rejects(() => bank('Initial bank', '0012345'), /OPERATOR_ACCESS_REQUIRED/);
      await actor(operator, 'aal2');
      await value("select api.platform_save_package('starter','Published starter',125500,'LKR',0,'active',1) as value");
      await value("select api.platform_save_package('growth','Published zero cost',0,'LKR',0,'active',1) as value");
      await publish('starter');
      await publish('growth');
      await bank('Initial bank', '0012345');

      await tx.exec('reset role');
      await tx.exec('update billing.subscription_checkout_settings set enabled=true, enforce_checkout=true');
      await tx.query('insert into billing.subscription_trial_allowlist(user_id) values ($1)', [outsider]);
      await actor(outsider);
      assert.equal((await access()).requires_checkout, false);
      assert.ok(await bootstrap());
      await actor(buyer);
      assert.equal((await access()).requires_checkout, true);
      await rejects(bootstrap, /SUBSCRIPTION_CHECKOUT_REQUIRED/);
      await rejects(() => value(`select core.bootstrap_tenant_impl(
        'Bypass','bootstrap-bypass','Bypass','MAIN','HQ','HQ') as value`), /SUBSCRIPTION_CHECKOUT_REQUIRED/);
      await rejects(() => value(`select core.bootstrap_tenant_pre_checkout_impl(
        'Bypass','bootstrap-bypass','Bypass','MAIN','HQ','HQ') as value`), { code: '42501' });
      await tx.exec('reset role');
      await tx.exec('update billing.subscription_checkout_settings set enabled=false');
      await actor(buyer);
      assert.equal((await access()).requires_checkout, true);
      await rejects(bootstrap, /SUBSCRIPTION_CHECKOUT_REQUIRED/);
      await tx.exec('reset role');
      await tx.exec('update billing.subscription_checkout_settings set enabled=true');
      await actor(buyer);
      await rejects(() => order('starter', 3, 'Café Studio', request), /SUBSCRIPTION_EMAIL_REQUIRED/);
      await actor(null, null, 'service_role');
      await rejects(() => verify(buyer, 'wrong@fixture.test'), /SUBSCRIPTION_EMAIL_REQUIRED/);
      await verify(buyer, signupEmail.toUpperCase());

      await actor(buyer);
      assert.equal((await access()).email_verified, true);
      assert.deepEqual((await catalog()).map(row => row.code), ['growth', 'starter']);
      const opened = await order('starter', 3, 'Café Studio', request);
      assert.equal(opened.status, 'awaiting_payment');
      assert.match(opened.username, /^cafe-studio-j[0-9]{9,19}$/);
      assert.equal(opened.system_serial, opened.username.split('-').at(-1).toUpperCase());
      assert.equal(opened.price_minor, 125500);
      assert.equal(opened.bank.account_number, '0012345');
      assert.equal((await order('starter', 3, 'Café Studio', recoveredRequest)).id, opened.id);
      await rejects(() => order('growth', 3, 'Other name'), /SUBSCRIPTION_ORDER_OPEN/);
      await rejects(() => order('starter', 3, 'Other name', request), /SUBSCRIPTION_REQUEST_CHANGED/);
      const submitted = await submit(opened.id, 'submitted-ref');
      assert.equal(submitted.status, 'under_review');
      assert.equal((await submit(opened.id, 'SUBMITTED-REF')).id, opened.id);

      await tx.exec('reset role');
      await rejects(async () => {
        await tx.query(`insert into auth.users(id,email,raw_app_meta_data)
          values ($1,$2,'{"managed_org_admin":true}')`, [randomUUID(), opened.username + '@admin.jentra.invalid']);
        await tx.exec('set constraints all immediate');
      }, /SUBSCRIPTION_USERNAME_UNAVAILABLE/);

      await actor(outsider, 'aal2');
      assert.deepEqual(await value('select api.subscription_checkout_orders() as value'), []);
      await rejects(() => submit(opened.id, 'malicious-ref'), /SUBSCRIPTION_ORDER_UNAVAILABLE/);
      await rejects(() => value('select api.platform_subscription_checkout_queue() as value'), /OPERATOR_ACCESS_REQUIRED/);

      await actor(operator, 'aal2');
      const listed = await value('select api.platform_subscription_checkout_queue() as value');
      assert.equal(listed[0].signup_email, signupEmail);
      assert.equal(listed[0].handover_status, null);
      await value("select api.platform_save_package('starter','Repriced',150000,'LKR',0,'active',3) as value");
      await bank('Replacement bank', '0098765');
      const paidTime = await value('select clock_timestamp()::text as value');
      await rejects(() => review(opened.id, true, 'verified-ref', 125499, paidTime), /SUBSCRIPTION_VERIFIED_PAYMENT_REQUIRED/);
      await rejects(() => review(opened.id, true, 'verified-ref', 125500, paidTime, null, 'Bank memo differs'),
        /SUBSCRIPTION_PAYMENT_NOT_MATCHED/);
      assert.equal((await review(opened.id, false, 'verified-ref', 125500, paidTime,
        'Reference differs', 'Bank memo differs')).status, 'payment_rejected');
      await actor(buyer);
      await submit(opened.id, 'verified-ref');
      await actor(operator, 'aal2');
      const settled = await review(opened.id, true, 'verified-ref', 125500, paidTime);
      assert.equal(settled.status, 'paid');
      assert.equal(settled.bank.account_number, '0012345');
      assert.equal(settled.price_minor, 125500);
      assert.equal(settled.handover_status, 'pending');
      assert.equal((await review(opened.id, true, 'verified-ref', 125500, paidTime)).id, opened.id);
      const organization = (await value("select api.platform_list_organizations('',0,$1) as value", [settled.tenant_id]))[0];
      assert.equal(organization.checkout_managed, true);
      assert.equal(organization.system_serial, opened.system_serial);
      assert.equal(organization.term_expired, false);
      assert.equal(organization.term_ends_at, settled.term_ends_at);
      await value("select api.platform_rename_subscription_organization($1,'Renamed Cafe','Verified name correction') as value", [settled.tenant_id]);
      const legacyTenant = await value(`select api.platform_create_organization(
        'Legacy Paid','legacy-paid','legacy@fixture.test','starter','Asia/Colombo','LKR') as value`);
      await rejects(() => value(`select api.platform_confirm_organization_activation(
        $1,'legacy@fixture.test',' VERIFIED-ref ',150000,'LKR') as value`, [legacyTenant]), /duplicate key/);
      await value(`select api.platform_confirm_organization_activation(
        $1,'legacy@fixture.test','legacy-reference',150000,'LKR') as value`, [legacyTenant]);

      await actor(buyer);
      assert.equal((await order('starter', 3, 'Café Studio', recoveredRequest)).status, 'paid');
      assert.ok((await access()).renewable.some(row => row.tenant_id === settled.tenant_id));
      const zero = await order('growth', 3, 'Zero-cost studio');
      assert.equal(zero.status, 'paid');
      assert.equal(zero.bank, null);
      assert.equal(zero.handover_status, 'pending');
      const earlyRenewal = await order('growth', 3, null, randomUUID(), zero.tenant_id);
      assert.equal(earlyRenewal.status, 'paid');
      assert.equal(Date.parse(earlyRenewal.term_ends_at) - Date.parse(zero.term_ends_at), 30 * 86400000);

      await tx.exec('reset role');
      await tx.query(`with m as (
        insert into core.memberships(tenant_id,user_id) values ($1,$2) returning id
      ) insert into core.role_assignments(tenant_id,membership_id,role_id,created_by)
        select $1,m.id,r.id,$3 from m cross join core.roles r where r.tenant_id=$1 and r.code='tenant_owner'`,
        [settled.tenant_id, owner, operator]);
      await tx.query("update billing.tenant_subscriptions set current_period_ends_at=statement_timestamp()-interval '1 day' where tenant_id=$1",
        [settled.tenant_id]);
      await value('select organization_lifecycle.assert_purge_scope($1) as value', [settled.tenant_id]);

      await actor(owner);
      const paused = await access();
      assert.equal(paused.workspace_paused, true);
      assert.deepEqual(paused.paused_tenant_ids, [settled.tenant_id]);
      assert.equal(await value('select core.is_tenant_member($1) as value', [settled.tenant_id]), false);
      assert.equal(await value('select count(*)::int as value from api.legal_entities where tenant_id=$1', [settled.tenant_id]), 0);
      assert.equal(paused.renewable[0].organization_name, 'Renamed Cafe');
      const renewal = await order('starter', 4, null, randomUUID(), settled.tenant_id);
      assert.equal(renewal.kind, 'renewal');
      assert.equal(renewal.username, null);
      assert.equal(renewal.price_minor, 150000);
      assert.equal(renewal.bank.account_number, '0098765');
      await submit(renewal.id, 'legacy-reference');
      await actor(buyer);
      await rejects(() => order('starter', 4, null, randomUUID(), settled.tenant_id), /SUBSCRIPTION_ORDER_OPEN/);
      await actor(operator, 'aal2');
      const renewalTime = await value('select clock_timestamp()::text as value');
      await rejects(() => review(renewal.id, true, 'legacy-reference', 150000, renewalTime), /duplicate key/);
      assert.equal((await review(renewal.id, false, 'legacy-reference', 150000, renewalTime, 'Reference already used')).status, 'payment_rejected');
      await actor(owner);
      await submit(renewal.id, 'renewal-reference');
      await actor(operator, 'aal2');
      const renewed = await review(renewal.id, true, 'renewal-reference', 150000, renewalTime);
      assert.equal(renewed.status, 'paid');
      assert.equal(renewed.handover_status, null);
      assert.ok(Date.parse(renewed.term_ends_at) > Date.now() + 29 * 86400000);
      await actor(owner);
      assert.equal((await access()).workspace_paused, false);
      assert.equal(await value('select core.is_tenant_member($1) as value', [settled.tenant_id]), true);
      await actor(outsider);
      await rejects(() => order('starter', 4, null, randomUUID(), settled.tenant_id), /SUBSCRIPTION_RENEWAL_FORBIDDEN/);

      await actor(buyer);
      const old = await order('starter', 4, 'Café Studio');
      assert.match(old.username, /^cafe-studio-j[0-9]{9,19}$/);
      assert.notEqual(old.system_serial, opened.system_serial);
      await tx.exec('reset role');
      await tx.query(`update billing.subscription_checkout_orders
        set created_at=statement_timestamp()-interval '8 days', expires_at=statement_timestamp()-interval '1 day'
        where id=$1`, [old.id]);
      await actor(buyer);
      const history = await value('select api.subscription_checkout_orders() as value');
      assert.equal(history.find(entry => entry.id === old.id).status, 'expired');
      assert.equal((await submit(old.id, 'after-deadline-report')).status, 'under_review');
      await actor(operator, 'aal2');
      const late = await value('select clock_timestamp()::text as value');
      await rejects(() => review(old.id, true, 'after-deadline-report', 150000, late, null, 'Reported late'),
        /SUBSCRIPTION_PAYMENT_NOT_MATCHED/);
      await review(old.id, false, 'after-deadline-report', 150000, late, 'Payment received late', 'Late bank posting');
      await actor(buyer);
      await submit(old.id, 'corrected-report');
      await actor(operator, 'aal2');
      const onTime = await value("select (clock_timestamp() - interval '2 days')::text as value");
      assert.equal((await review(old.id, true, 'corrected-report', 150000, onTime)).status, 'paid');
      throw rollback;
    });
  } catch (error) {
    if (error !== rollback) throw error;
  }
  console.log('Subscription checkout pricing, scope, settlement, replays, entitlements and renewal assertions passed.');
}
