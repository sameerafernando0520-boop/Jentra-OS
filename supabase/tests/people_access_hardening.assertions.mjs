import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

// Payroll reads need MFA, and nobody decides their own leave or attendance
// record. The leave and attendance rows are inserted without their policy and
// calendar parents (replica mode); only the decision update is under test.
export async function testPeopleAccessHardening(db) {
  const approver = randomUUID(), tenant = randomUUID(), entity = randomUUID(), branch = randomUUID();
  const own = randomUUID(), other = randomUUID();
  const rollback = new Error("Roll back people access hardening fixtures");
  try {
    await db.transaction(async (tx) => {
      const scalar = async (sql, args = []) => (await tx.query(sql, args)).rows[0].value;
      const session = (aal) => tx.query("select set_config('request.jwt.claims', $1, true)",
        [JSON.stringify({ sub: approver, role: "authenticated", aal })]);
      const rejects = async (fn, message) => {
        await tx.exec("savepoint failed_action");
        await assert.rejects(fn, message);
        await tx.exec("rollback to savepoint failed_action; release savepoint failed_action");
      };

      await tx.query("insert into auth.users(id,email) values ($1,'people-approver@fixture.invalid')", [approver]);
      await tx.query("insert into core.tenants(id,name,slug,status,created_by) values ($1,'People Hardening','people-hardening-fixture','active',$2)", [tenant, approver]);
      await tx.query("insert into core.legal_entities(id,tenant_id,name,code,timezone,created_by) values ($1,$2,'People Hardening','PHARD','UTC',$3)", [entity, tenant, approver]);
      await tx.query("insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values ($1,$2,$3,'Main','PH1',$4)", [branch, tenant, entity, approver]);
      await tx.query("insert into billing.plans(code,name) values ('people_hardening_fixture','People hardening fixture')");
      await tx.query("insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values ('people_hardening_fixture','module.people',true)");
      await tx.query(
        "insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at) values ($1,'people_hardening_fixture','trialing',5,now()+interval '2 days')",
        [tenant]);
      const membership = await scalar("insert into core.memberships(tenant_id,user_id) values ($1,$2) returning id as value", [tenant, approver]);
      const role = await scalar(
        "insert into core.roles(tenant_id,code,name,is_system,requires_mfa) values ($1,'fixture.payroll','Fixture payroll',false,false) returning id as value", [tenant]);
      await tx.query(
        "insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,$2,code from core.permissions " +
        "where code in ('people.view','people.payroll.view','people.payroll.payslip.view')", [tenant, role]);
      await tx.query("insert into core.role_assignments(tenant_id,membership_id,role_id,created_by) values ($1,$2,$3,$4)", [tenant, membership, role, approver]);

      // 1. Payroll reads need MFA; the payslip rule is unchanged.
      const payroll = (capability, write = false) => scalar(
        "select true as value from people_payroll.require_access($1,$2,$3,$4,$5)", [tenant, entity, branch, capability, write]);
      await session("aal1");
      await rejects(() => payroll("people.payroll.view"), /PAYROLL_MFA_REQUIRED/);
      await rejects(() => payroll("people.payroll.payslip.view", true), /PAYROLL_MFA_REQUIRED/);
      await session("aal2");
      assert.equal(await payroll("people.payroll.view"), true);
      assert.equal(await payroll("people.payroll.payslip.view", true), true);

      // 2. Decisions about your own record are refused.
      await tx.exec("set local session_replication_role = replica");
      for (const [employee, code] of [[own, "PH-OWN"], [other, "PH-OTHER"]]) {
        await tx.query(
          "insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by) values ($1,$2,$3,$4,$4,$5,$5)",
          [employee, tenant, entity, code, approver]);
        await tx.query(
          "insert into people.leave_requests(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,policy_version_id,calendar_version_id," +
          "start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,charge_seconds,status,reason,created_by) " +
          "values ($1,$2,$3,$4,$1,$5,$5,$5,'2026-12-01 09:00',0,'2026-12-01 10:00',0,'2026-12-01 09:00+00','2026-12-01 10:00+00',3600,'submitted','Fixture leave',$6)",
          [employee, tenant, entity, branch, randomUUID(), approver]);
        await tx.query(
          "insert into people.attendance_entries(id,tenant_id,legal_entity_id,branch_id,employee_id,current_revision_id,status,created_by) " +
          "values ($1,$2,$3,$4,$1,$5,'submitted',$6)", [employee, tenant, entity, branch, randomUUID(), approver]);
      }
      await tx.query(
        "insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at) " +
        "values ($1,$2,$3,$4,$5,$6,$7,'accepted',$7,now())", [randomUUID(), tenant, entity, branch, own, membership, approver]);
      await tx.exec("set local session_replication_role = origin");
      // Only the self-decision rule is under test: the parent rows are absent, so the
      // foreign key and notification triggers are switched off for these two tables.
      await tx.exec("alter table people.leave_requests disable trigger all; alter table people.leave_requests enable trigger leave_refuse_self_decision");
      await tx.exec("alter table people.attendance_entries disable trigger all; alter table people.attendance_entries enable trigger attendance_refuse_self_decision");

      const decide = (table, id, status, decider = approver) =>
        tx.query("update people." + table + " set status=$2, decided_by=$3, version=version+1 where id=$1", [id, status, decider]);
      for (const status of ["approved", "rejected"]) {
        await rejects(() => decide("leave_requests", own, status), /LEAVE_SELF_DECISION_DENIED/);
      }
      for (const status of ["approved", "rejected", "cancelled"]) {
        await rejects(() => decide("attendance_entries", own, status), /ATTENDANCE_SELF_DECISION_DENIED/);
      }
      // Withdrawing your own leave and deciding someone else's record still work.
      await tx.exec("savepoint own_withdrawal");
      await decide("leave_requests", own, "cancelled");
      await tx.exec("rollback to savepoint own_withdrawal; release savepoint own_withdrawal");
      await decide("leave_requests", other, "approved");
      await decide("attendance_entries", other, "approved");
      // A revoked link no longer makes the decider the subject.
      await tx.query("update people_private.account_links set status='revoked' where tenant_id=$1 and employee_id=$2", [tenant, own]);
      await decide("leave_requests", own, "approved");
      throw rollback;
    });
  } catch (error) {
    if (error !== rollback) throw error;
  }
  console.log("People access hardening passed payroll MFA and self-decision assertions.");
}
