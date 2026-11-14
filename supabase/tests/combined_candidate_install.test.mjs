// Applies the tracked migrations, then every uninstalled candidate in timestamp
// order: the company, Employee and Sales candidates first, the organization
// control candidates after them. The two sets are otherwise verified apart.
// No hosted database, credentials, files or account are touched.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { openIsolatedDatabase, organizationCandidates } from "./isolated_database.mjs";
import { testPlatformOrganizationControl } from "./platform_organization_control.assertions.mjs";
import { testSubscriptionCheckout } from "./subscription_checkout.assertions.mjs";
import { testSubscriptionHandover } from "./subscription_handover.assertions.mjs";
import { testPlatformOperatorIdentity } from "./platform_operator_identity.assertions.mjs";
import { testSystemSerials } from "./system_serials.assertions.mjs";

const migrations = new URL("../migrations/", import.meta.url);
const candidates = new URL("../candidates/", import.meta.url);
// The last tracked migration. Later candidates are not installed anywhere yet.
const installedThrough = "20261020999999";
const db = await openIsolatedDatabase();

try {
  const tracked = (await readdir(migrations)).filter(name => name.endsWith(".sql") &&
    // Scheduler installation needs pg_cron and pg_net.
    name !== "20261009123000_wave5_supabase_schedule.sql").sort();
  const pending = (await readdir(candidates)).filter(name => /^\d{14}_.+\.sql$/.test(name) && name > installedThrough).sort();
  const earlier = pending.filter(name => !organizationCandidates.includes(name));
  assert.deepEqual(pending.filter(name => organizationCandidates.includes(name)), organizationCandidates,
    "Every organization control candidate is present, in order.");
  assert.ok(earlier.length > 0 && earlier.at(-1) < organizationCandidates[0],
    "Company, Employee and Sales candidates precede organization control.");
  for (const [name, directory] of [
    ...tracked.map(name => [name, migrations]),
    ...pending.map(name => [name, candidates]),
  ]) {
    try { await db.exec((await readFile(new URL(name, directory), "utf8")).replaceAll("\r\n", "\n")); }
    catch (error) {
      throw new Error("Migration " + name + ": " + error.message +
        (error.where ? " (" + error.where + ")" : ""), { cause: error });
    }
  }

  // Organization control still works above company administration: handover,
  // system provisioning and cutover create and restore memberships.
  await testPlatformOrganizationControl(db);
  await testSubscriptionCheckout(db);
  await testSubscriptionHandover(db);
  await testPlatformOperatorIdentity(db);
  await testSystemSerials(db);

  const owner = randomUUID(), rep = randomUUID(), outsider = randomUUID(), tenant = randomUUID();
  const field = "sales.field.customers.view", office = "core.members.invite";
  await db.query("insert into auth.users(id,email) values ($1,'owner@fixture.invalid'),($2,'rep@fixture.invalid'),($3,'outsider@fixture.invalid')",
    [owner, rep, outsider]);
  await db.query("insert into core.tenants(id,name,slug,status,created_by) values ($1,'Combined','combined-fixture','active',$2)", [tenant, owner]);
  const role = (await db.query(
    "insert into core.roles(tenant_id,code,name,is_system,requires_mfa) values ($1,'fixture.rep','Fixture rep',false,false) returning id", [tenant]
  )).rows[0].id;
  await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) values ($1,$2,$3),($1,$2,$4)", [tenant, role, field, office]);
  const membership = (await db.query("insert into core.memberships(tenant_id,user_id) values ($1,$2) returning id", [tenant, rep])).rows[0].id;
  await db.query("insert into core.role_assignments(tenant_id,membership_id,role_id,created_by) values ($1,$2,$3,$4)", [tenant, membership, role, owner]);

  const as = (user, role_, body) => db.transaction(async tx => {
    await tx.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({ sub: user, aal: "aal1", role: role_ })]);
    await tx.exec("set local role " + role_);
    return body(tx);
  });
  const permitted = code => as(rep, "authenticated", async tx =>
    (await tx.query("select core.has_permission($1,$2) as value", [tenant, code])).rows[0].value);
  const capabilities = () => as(rep, "authenticated", async tx =>
    (await tx.query("select permission_code from core.list_capabilities($1) order by 1", [tenant])).rows.map(row => row.permission_code));

  // An unrestricted member holds both role permissions.
  assert.equal(await permitted(field), true);
  assert.equal(await permitted(office), true);
  assert.deepEqual(await capabilities(), [office, field].sort());

  // Organization control replaces the permission functions after Field Sales.
  // A restricted companion account must keep only its field permissions.
  await db.query("insert into field_sales.principals(tenant_id,user_id) values ($1,$2)", [tenant, rep]);
  assert.equal(await permitted(field), true);
  assert.equal(await permitted(office), false);
  assert.deepEqual(await capabilities(), [field]);

  // The company administration guard still covers an ordinary account: a
  // service worker cannot add its membership, and a revoked one stays revoked.
  await assert.rejects(as(null, "service_role", tx =>
    tx.query("insert into core.memberships(tenant_id,user_id) values ($1,$2)", [tenant, outsider])), { code: "42501" });
  await db.query("update core.memberships set status='revoked' where id=$1", [membership]);
  await assert.rejects(as(null, "service_role", tx =>
    tx.query("update core.memberships set status='active' where id=$1", [membership])), { code: "42501" });

  console.log("Combined candidate install verified: all candidates apply in order, organization control passes above " +
    "company administration, the Field Sales restriction survives, and ordinary memberships remain guarded.");
} finally {
  await db.close();
}
