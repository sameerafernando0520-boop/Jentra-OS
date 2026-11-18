import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

export async function testPlatformOrganizationControl(db) {
  const operator = randomUUID();
  const member = randomUUID();
  const rollback = new Error("Roll back platform control fixtures");
  try {
    await db.transaction(async (tx) => {
      const scalar = async (sql, args = []) => (await tx.query(sql, args)).rows[0].value;
      const actor = async (user, aal) => {
        await tx.exec("reset role");
        await tx.query("select set_config('request.jwt.claims', $1, true)", [
          JSON.stringify({ sub: user, role: "authenticated", aal }),
        ]);
        await tx.exec("set local role authenticated");
      };
      const rejects = async (fn, message) => {
        await tx.exec("savepoint failed_action");
        await assert.rejects(fn, message);
        await tx.exec("rollback to savepoint failed_action; release savepoint failed_action");
      };
      const savePackage = (code, price, revision) => scalar(
        "select api.platform_save_package($1,'Fixture Package',$2,'LKR',30,'active',$3) as value",
        [code, price, revision],
      );
      const create = (slug, plan) => scalar(
        "select api.platform_create_organization($1,$1,$2,$3,'Asia/Colombo','LKR') as value",
        [slug, slug + "@fixture.test", plan],
      );
      const offer = (ids, amount) => scalar(
        "select api.platform_apply_organization_offer($1,$2,'LKR',null,'Fixture offer') as value",
        [JSON.stringify(ids.map((id) => typeof id === "string"
          ? { tenant_id: id, plan_code: "starter", revision: 2 }
          : id)), amount],
      );
      const activate = (id, slug, amount, payment) => scalar(
        "select api.platform_confirm_organization_activation($1,$2,$3,$4,'LKR') as value",
        [id, slug + "@fixture.test", payment, amount],
      );

      await tx.query("insert into auth.users(id,email) values ($1,'operator@fixture.test'),($2,'member@fixture.test')", [operator, member]);
      await tx.query("insert into intelligence_control.operators(actor_id,active,organization_manage) values ($1,true,true)", [operator]);

      await actor(operator, "aal1");
      assert.equal(await scalar("select api.platform_organization_assignment() as value"), true);
      assert.equal(await scalar("select api.platform_organization_access() as value"), false);
      await rejects(() => scalar("select api.platform_list_packages() as value"), /OPERATOR_ACCESS_REQUIRED/);

      await actor(operator, "aal2");
      assert.equal(await scalar("select api.platform_organization_access() as value"), true);
      await savePackage("starter", 100000, 1);
      await savePackage("growth", 200000, 1);
      await rejects(() => savePackage("starter", 1, 1), /PACKAGE_CHANGED/);
      const first = await create("control-test-first", "starter");
      const second = await create("control-test-second", "starter");
      const paid = await create("control-test-paid", "starter");
      const otherPlan = await create("control-test-other", "growth");

      await tx.exec("reset role");
      assert.equal(await scalar("select count(*)::int as value from core.memberships where tenant_id = $1", [first]), 0);
      const membership = await scalar(
        "insert into core.memberships (tenant_id,user_id) values ($1,$2) returning id as value", [first, member],
      );
      await tx.query(
        "insert into core.role_assignments (tenant_id,membership_id,role_id,created_by) select $1,$2,id,$3 from core.roles where tenant_id=$1 and code='tenant_owner'",
        [first, membership, operator],
      );
      await actor(member, "aal2");
      assert.equal(await scalar("select api.platform_organization_assignment() as value"), false);
      await rejects(() => scalar("select api.platform_list_organizations() as value"), /OPERATOR_ACCESS_REQUIRED/);
      await rejects(() => offer([first], 0), /OPERATOR_ACCESS_REQUIRED/);

      await actor(operator, "aal2");
      await rejects(() => offer([first, otherPlan], 0), /OFFER_ORGANIZATIONS_CHANGED/);
      const pending = await scalar("select api.platform_list_organizations('control-test') as value");
      assert.equal(pending.every((row) => row.offer_minor === null && row.activated_at === null), true);
      assert.equal(await offer([first, second, { tenant_id: otherPlan, plan_code: "growth", revision: 2 }], 0), 3);
      const offered = await scalar("select api.platform_list_organizations('control-test') as value");
      assert.deepEqual(offered.filter((row) => row.offer_minor === 0).map((row) => row.id), [first, otherPlan, second]);
      assert.equal(await offer([{ tenant_id: otherPlan, plan_code: "growth", revision: 2 }], null), 1);
      await rejects(() => activate(first, "control-test-first", 100000, "wrong-quote"), /ORGANIZATION_QUOTE_CHANGED/);
      await rejects(() => activate(first, "other-email", 0, null), /SIGNUP_EMAIL_REQUIRED/);
      const firstReceipt = await activate(first, "control-test-first", 0, null);
      assert.deepEqual(await activate(first, "control-test-first", 0, null), firstReceipt);
      await rejects(() => activate(paid, "control-test-paid", 100000, null), /INVALID_PAYMENT_CONFIRMATION/);
      await activate(paid, "control-test-paid", 100000, "receipt-ref-001");
      await rejects(() => activate(otherPlan, "control-test-other", 200000, "Receipt-Ref-001"), /duplicate key/);
      await savePackage("starter", 0, 2);
      const rows = await scalar("select api.platform_list_organizations('control-test') as value");
      const paidRow = rows.find((row) => row.id === paid);
      assert.equal(paidRow.paid_minor, 100000);
      assert.equal(paidRow.price_minor, 0);
      assert.equal(paidRow.subscription_status, "active");
      throw rollback;
    });
  } catch (error) {
    if (error !== rollback) throw error;
  }
  console.log("Platform organization operator, pricing, activation and bulk offer assertions passed.");
}
