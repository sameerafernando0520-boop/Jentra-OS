import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

// Organization creation and module control. Runs before any harness relaxes
// checkout enforcement for legacy self-service fixtures, so the installed
// default is what is asserted here.
export async function testOrganizationCreationControl(db) {
  const operator = randomUUID();
  const visitor = randomUUID();
  const rollback = new Error("Roll back organization creation control fixtures");
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
      const bootstrap = (slug) => scalar(
        "select api.bootstrap_tenant('Self Service',$1,'Self Service','MAIN','HQ','HQ') as value", [slug],
      );
      const enforce = (value, reason) => scalar(
        "select api.platform_set_checkout_enforcement($1,$2) is null as value", [value, reason],
      );
      const modules = async (code) => (await scalar("select api.platform_package_modules() as value"))
        .find((row) => row.code === code);
      const saveModules = (code, value, revision) => scalar(
        "select api.platform_save_package_modules($1,$2,$3) is null as value", [code, JSON.stringify(value), revision],
      );
      const setPackage = (tenant, code, reason) => scalar(
        "select api.platform_set_organization_package($1,$2,$3) is null as value", [tenant, code, reason],
      );
      const enabled = async (tenant, code) => {
        await tx.exec("reset role");
        return scalar("select billing.organization_module_enabled($1,$2) as value", [tenant, code]);
      };

      await tx.query("insert into auth.users(id,email) values ($1,'creation-operator@fixture.test'),($2,'visitor@fixture.test')",
        [operator, visitor]);
      await tx.query("insert into intelligence_control.operators(actor_id,active,organization_manage) values ($1,true,true)", [operator]);

      // 1. Self-created organizations are blocked by default.
      assert.equal(await scalar("select enforce_checkout as value from billing.subscription_checkout_settings"), true);
      assert.equal(await scalar(
        "select column_default as value from information_schema.columns where table_schema='billing' " +
        "and table_name='subscription_checkout_settings' and column_name='enforce_checkout'"), "true");
      await actor(visitor, "aal2");
      await rejects(() => bootstrap("self-service-blocked"), /SUBSCRIPTION_CHECKOUT_REQUIRED/);

      // 2. Only an operator with MFA changes the rule, with a reason, and it is recorded.
      await rejects(() => enforce(false, "Visitor attempt"), /OPERATOR_ACCESS_REQUIRED/);
      await actor(operator, "aal1");
      await rejects(() => enforce(false, "Password-only operator"), /OPERATOR_ACCESS_REQUIRED/);
      await actor(operator, "aal2");
      await rejects(() => enforce(false, "no"), /INVALID_CHECKOUT_ENFORCEMENT/);
      await rejects(() => enforce(null, "Missing value given"), /INVALID_CHECKOUT_ENFORCEMENT/);
      await enforce(false, "Open self-service for a pilot");
      await actor(visitor, "aal2");
      const created = await bootstrap("self-service-open");
      assert.ok(created.tenant_id, "self-service works while enforcement is off");
      await actor(operator, "aal2");
      await enforce(true, "Pilot finished");
      await enforce(true, "Pilot finished");
      await actor(visitor, "aal2");
      await rejects(() => bootstrap("self-service-closed"), /SUBSCRIPTION_CHECKOUT_REQUIRED/);
      await tx.exec("reset role");
      const events = (await tx.query(
        "select before_context->>'enforce_checkout' as before, after_context->>'enforce_checkout' as after, reason, actor_id " +
        "from billing.platform_control_events where event_type='checkout_enforcement' and actor_id=$1 order by occurred_at, id",
        [operator])).rows;
      assert.deepEqual(events.map((row) => [row.before, row.after, row.reason]), [
        ["true", "false", "Open self-service for a pilot"], ["false", "true", "Pilot finished"],
      ], "only real changes are recorded");

      // 3. The operator trial path sets a trial end, so an unactivated trial expires.
      await actor(operator, "aal2");
      await scalar("select api.platform_save_package('modules-base','Modules Base',100000,'LKR',14,'active',null,'starter') is null as value");
      await scalar("select api.platform_save_package('modules-other','Modules Other',200000,'LKR',14,'active',null,'starter') is null as value");
      const tenant = await scalar(
        "select api.platform_create_organization('Module Org','module-org','module-org@fixture.test','modules-base','Asia/Colombo','LKR') as value");
      await tx.exec("reset role");
      assert.equal(await scalar(
        "select trial_ends_at between statement_timestamp() + interval '13 days' and statement_timestamp() + interval '15 days' as value " +
        "from billing.tenant_subscriptions where tenant_id=$1", [tenant]), true);

      // 4. Module switches belong to a package and are enforced by the entitlement check.
      await actor(visitor, "aal2");
      await rejects(() => scalar("select api.platform_package_modules() as value"), /OPERATOR_ACCESS_REQUIRED/);
      await rejects(() => saveModules("modules-base", { "module.people": true }, 1), /OPERATOR_ACCESS_REQUIRED/);
      await actor(operator, "aal2");
      const before = await modules("modules-base");
      assert.deepEqual(Object.keys(before.modules).sort(), [
        "analytics", "module.ai", "module.assets", "module.field_sales", "module.finance",
        "module.people", "module.projects", "module.service",
      ]);
      assert.equal(before.modules["module.field_sales"], false, "Field Sales starts switched off");
      assert.equal(before.modules["module.people"], false);
      assert.equal(await enabled(tenant, "module.people"), false);
      await actor(operator, "aal2");
      await rejects(() => saveModules("modules-base", { "module.unknown": true }, before.revision), /INVALID_PACKAGE_MODULES/);
      await rejects(() => saveModules("modules-base", { "module.people": "yes" }, before.revision), /INVALID_PACKAGE_MODULES/);
      await rejects(() => saveModules("modules-base", { users: true }, before.revision), /INVALID_PACKAGE_MODULES/);
      await rejects(() => saveModules("modules-base", {}, before.revision), /INVALID_PACKAGE_MODULES/);
      await rejects(() => saveModules("modules-base", { "module.people": true }, before.revision + 1), /PACKAGE_CHANGED/);
      await rejects(() => saveModules("missing-package", { "module.people": true }, 1), /PACKAGE_CHANGED/);
      await saveModules("modules-base", { "module.people": true, "module.field_sales": true }, before.revision);
      const after = await modules("modules-base");
      assert.equal(after.revision, before.revision + 1);
      assert.equal(after.modules["module.people"], true);
      assert.equal(after.modules["module.field_sales"], true);
      assert.equal(after.modules["module.assets"], false, "unnamed modules keep their state");
      assert.equal((await modules("modules-other")).modules["module.people"], false, "other packages are untouched");
      assert.equal(await enabled(tenant, "module.people"), true);
      assert.equal(await enabled(tenant, "module.field_sales"), true);
      assert.equal(await enabled(tenant, "module.assets"), false);
      assert.equal(await scalar(
        "select (after_context->'modules'->>'module.people')::boolean and not (before_context->'modules'->>'module.people')::boolean as value " +
        "from billing.package_events where plan_code='modules-base' order by occurred_at desc, id desc limit 1"), true);
      await actor(operator, "aal2");
      await rejects(() => saveModules("modules-base", { "module.people": false }, before.revision), /PACKAGE_CHANGED/);

      // 5. Moving an organization to another package changes its modules.
      await actor(visitor, "aal2");
      await rejects(() => setPackage(tenant, "modules-other", "Visitor attempt"), /OPERATOR_ACCESS_REQUIRED/);
      await actor(operator, "aal2");
      await rejects(() => setPackage(tenant, "modules-other", "no"), /INVALID_PACKAGE_CHANGE/);
      await rejects(() => setPackage(randomUUID(), "modules-other", "Unknown organization"), /ORGANIZATION_UNAVAILABLE/);
      await rejects(() => setPackage(tenant, "missing-package", "Unknown package"), /PACKAGE_UNAVAILABLE/);
      await scalar("select api.platform_save_package('modules-retired','Modules Retired',100000,'LKR',14,'retired',null,'starter') is null as value");
      await rejects(() => setPackage(tenant, "modules-retired", "Retired package"), /PACKAGE_UNAVAILABLE/);
      await setPackage(tenant, "modules-other", "Customer downgraded modules");
      assert.equal(await enabled(tenant, "module.people"), false);
      assert.equal(await scalar("select plan_code as value from billing.tenant_subscriptions where tenant_id=$1", [tenant]), "modules-other");
      assert.equal(await scalar(
        "select before_context->>'plan_code' = 'modules-base' and after_context->>'plan_code' = 'modules-other' " +
        "and metadata->>'reason' = 'Customer downgraded modules' as value from audit.events " +
        "where tenant_id=$1 and event_type='organization.package_changed'", [tenant]), true);
      await actor(operator, "aal2");
      await setPackage(tenant, "modules-other", "Repeat is a no-op");
      await tx.exec("reset role");
      assert.equal(await scalar(
        "select count(*)::int as value from audit.events where tenant_id=$1 and event_type='organization.package_changed'", [tenant]), 1);

      // 6. An expired trial or ended term switches every module off.
      await actor(operator, "aal2");
      await setPackage(tenant, "modules-base", "Customer restored modules");
      assert.equal(await enabled(tenant, "module.people"), true);
      await tx.query("update billing.tenant_subscriptions set trial_ends_at = now() - interval '1 second' where tenant_id=$1", [tenant]);
      assert.equal(await enabled(tenant, "module.people"), false, "an expired trial has no modules");
      await tx.query("update billing.tenant_subscriptions set status='active', current_period_ends_at=null where tenant_id=$1", [tenant]);
      assert.equal(await enabled(tenant, "module.people"), true, "an open-ended active term keeps its modules");
      await tx.query("update billing.tenant_subscriptions set current_period_ends_at = now() - interval '1 second' where tenant_id=$1", [tenant]);
      assert.equal(await enabled(tenant, "module.people"), false, "an ended term has no modules");

      // 7. The helper and the event table are not reachable by clients.
      await actor(visitor, "aal2");
      await rejects(() => scalar("select billing.organization_module_enabled($1,'module.people') as value", [tenant]), /permission denied/);
      await rejects(() => scalar("select count(*)::int as value from billing.platform_control_events"), /permission denied/);
      throw rollback;
    });
  } catch (error) {
    if (error !== rollback) throw error;
  }
  console.log("Organization creation control passed enforcement default, operator switch, trial end, package modules, package change and expiry assertions.");
}
