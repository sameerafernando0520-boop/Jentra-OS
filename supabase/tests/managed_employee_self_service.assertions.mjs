import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

// A company-issued Employee App login is activated through the real
// activation function and must be able to use Employee self-service for its
// own entity and branch, and nothing else. Needs the Employee self-service
// and managed HR identity candidates.
export async function testManagedEmployeeSelfService(db) {
  const owner = randomUUID(), employeeUser = randomUUID(), session = randomUUID();
  const tenant = randomUUID(), entity = randomUUID(), branch = randomUUID(), otherBranch = randomUUID();
  const employee = randomUUID(), spell = randomUUID(), identity = randomUUID();
  const selfPermissions = [
    "people.self.view", "people.attendance.self.request", "people.leave.self.manage",
    "people.payroll.payslip.self", "people.hr.cases.self.manage", "people.hr.documents.self.view",
  ];
  const rollback = new Error("Roll back managed employee fixtures");
  try {
    await db.transaction(async (tx) => {
      const scalar = async (sql, args = []) => (await tx.query(sql, args)).rows[0].value;
      const asEmployee = () => tx.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({
        sub: employeeUser, role: "authenticated", aal: "aal1", session_id: session,
        app_metadata: { managed_org_admin: "true" },
      })]);
      const rejects = async (fn, message) => {
        await tx.exec("savepoint failed_action");
        await assert.rejects(fn, message);
        await tx.exec("rollback to savepoint failed_action; release savepoint failed_action");
      };
      const access = (permission, b = branch) =>
        scalar("select true as value from people.require_access($1,$2,$3,$4)", [tenant, entity, b, permission]);
      const subject = (permission) =>
        scalar("select employee_self.require_subject($1,$2,$3,$4) as value", [tenant, entity, branch, permission]);

      await tx.query(
        "insert into auth.users(id,email,raw_app_meta_data) values ($1,'managed-owner@fixture.invalid','{}'),($2,$3,$4)",
        [owner, employeeUser, "managed.employee@admin.jentra.invalid", JSON.stringify({ managed_org_admin: "true" })]);
      await tx.query("insert into core.tenants(id,name,slug,status,created_by) values ($1,'Managed Self','managed-self-fixture','active',$2)", [tenant, owner]);
      await tx.query("insert into core.legal_entities(id,tenant_id,name,code,timezone,created_by) values ($1,$2,'Managed Self','MSELF','UTC',$3)", [entity, tenant, owner]);
      await tx.query(
        "insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values ($1,$3,$4,'Main','MS1',$5),($2,$3,$4,'Other','MS2',$5)",
        [branch, otherBranch, tenant, entity, owner]);
      await tx.query("insert into billing.plans(code,name) values ('managed_self_fixture','Managed self fixture')");
      await tx.query("insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values ('managed_self_fixture','module.people',true)");
      await tx.query(
        "insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at) values ($1,'managed_self_fixture','trialing',5,now()+interval '2 days')",
        [tenant]);
      await tx.query(
        "insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by) values ($1,$2,$3,'MS-1','Managed Employee',$4,$4)",
        [employee, tenant, entity, owner]);
      await tx.query(
        "insert into people.employment_spells(id,tenant_id,legal_entity_id,employee_id,start_date,created_by) values ($1,$2,$3,$4,current_date-40,$5)",
        [spell, tenant, entity, employee, owner]);
      await tx.query(
        "insert into people.employment_assignments(id,tenant_id,legal_entity_id,employee_id,spell_id,branch_id,start_date,job_title,employment_type,created_by) " +
        "values ($1,$2,$3,$4,$5,$6,current_date-40,'Fixture employee','permanent',$7)",
        [randomUUID(), tenant, entity, employee, spell, branch, owner]);
      await tx.query(
        "insert into core.organization_administrator_logins(user_id,tenant_id,username,password_changed_at,must_change_password) " +
        "values ($1,$2,'managed.employee',now()-interval '1 hour',false)", [employeeUser, tenant]);
      await tx.query("insert into auth.sessions(id,user_id,created_at) values ($1,$2,now())", [session, employeeUser]);
      await tx.query(
        "insert into people_private.managed_staff_identities(id,tenant_id,kind,username,display_name,legal_entity_id,branch_id," +
        "employee_id,employee_number,created_by,request_id,delivery,status,user_id,password_ready_at) " +
        "values ($1,$2,'employee','managed.employee','Managed Employee',$3,$4,$5,'MS-1',$6,$7,'reveal','ready',$8,now())",
        [identity, tenant, entity, branch, employee, owner, randomUUID(), employeeUser]);

      await scalar("select people_private.activate_managed_staff_identity($1,$2) as value", [identity, owner]);
      const granted = (await tx.query(
        "select rp.permission_code from core.roles r join core.role_permissions rp on rp.role_id = r.id " +
        "where r.tenant_id = $1 and r.code = 'people.employee_app' order by 1", [tenant])).rows.map((row) => row.permission_code);
      assert.deepEqual(granted, [...selfPermissions].sort(), "the Employee App role carries exactly the self-service permissions");

      await asEmployee();
      for (const permission of selfPermissions) {
        assert.equal(await access(permission), true, permission + " is allowed for the employee's own branch");
        assert.equal(await subject(permission), employee, permission + " resolves the employee's own record");
      }
      for (const permission of ["people.view", "people.employees.view", "people.leave.approve", "people.payroll.view"]) {
        await rejects(() => access(permission), /EMPLOYEE_SELF_SCOPE_DENIED/);
      }
      await rejects(() => access("people.leave.self.manage", otherBranch), /EMPLOYEE_SELF_SCOPE_DENIED/);

      // Revoking the login's link ends self-service at once.
      await tx.query("update people_private.account_links set status='revoked', version=version+1 where tenant_id=$1 and user_id=$2", [tenant, employeeUser]);
      await rejects(() => access("people.leave.self.manage"), /EMPLOYEE_SELF_SCOPE_DENIED|Permission denied/);
      throw rollback;
    });
  } catch (error) {
    if (error !== rollback) throw error;
  }
  console.log("Managed Employee App login passed self-service scope assertions.");
}
