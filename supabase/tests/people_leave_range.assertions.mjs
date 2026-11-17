import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

// Multi-day leave: one command creates the per-day requests for a date range
// as a batch, and the batch is submitted, approved, rejected and cancelled
// together through the existing one-slot leave ledger. Needs the
// 20261114110000_people_leave_range.sql candidate; the Employee App part also
// needs the Employee self-service candidate.
export async function testPeopleLeaveRange(db) {
  const id = new Map();
  const uid = (name) => { if (!id.has(name)) id.set(name, randomUUID()); return id.get(name); };
  const tenant = uid("tenant"), entity = uid("entity"), branch = uid("branch");
  const rollback = new Error("Roll back multi-day leave fixtures");
  let checks = 0;
  try {
    await db.transaction(async (tx) => {
      const rows = async (sql, args = []) => (await tx.query(sql, args)).rows;
      const scalar = async (sql, args = []) => (await rows(sql, args))[0].value;
      const actor = async (name, extra = {}) => {
        await tx.exec("reset role");
        await tx.query("select set_config('request.jwt.claims', $1, true)",
          [JSON.stringify({ sub: uid(name), role: "authenticated", aal: "aal2", ...extra })]);
        await tx.exec("set local role authenticated");
      };
      const owner = async () => tx.exec("reset role");
      const rejects = async (fn, message) => {
        await tx.exec("savepoint failed_action");
        await assert.rejects(fn, message);
        await tx.exec("rollback to savepoint failed_action; release savepoint failed_action");
        checks++;
      };
      const ok = (value, message) => { assert.ok(value, message); checks++; };
      const equal = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };

      // Fixture: Monday to Friday 09:00-17:00 in Colombo, an hours policy.
      const users = ["creator", "reviewer", "worker"];
      for (const name of users) {
        await tx.query("insert into auth.users(id,email) values ($1,$2)", [uid(name), name + "@leave-range.fixture.invalid"]);
      }
      await tx.query("insert into core.tenants(id,name,slug,status,created_by) values ($1,'Leave Range','leave-range-fixture','active',$2)", [tenant, uid("creator")]);
      await tx.query("insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by) values ($1,$2,'Leave Range','LRANGE','LKR','Asia/Colombo',2,$3)",
        [entity, tenant, uid("creator")]);
      await tx.query("insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values ($1,$2,$3,'Head Office','LR1',$4)", [branch, tenant, entity, uid("creator")]);
      await tx.query("insert into billing.plans(code,name) values ('leave_range_fixture','Leave range fixture')");
      await tx.query("insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values ('leave_range_fixture','module.people',true)");
      await tx.query("insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at) values ($1,'leave_range_fixture','trialing',10,now()+interval '30 days')", [tenant]);
      for (const name of users) {
        await tx.query("insert into core.memberships(id,tenant_id,user_id,status) values ($1,$2,$3,'active')", [uid(name + ".membership"), tenant, uid(name)]);
        await tx.query("insert into core.roles(id,tenant_id,code,name,requires_mfa) values ($1,$2,$3,$3,false)", [uid(name + ".role"), tenant, "fixture." + name]);
        await tx.query("insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,created_by) values ($1,$2,$3,$4,$5)",
          [tenant, uid(name + ".membership"), uid(name + ".role"), entity, uid("creator")]);
      }
      for (const name of ["creator", "reviewer"]) {
        await tx.query("insert into core.role_permissions(tenant_id,role_id,permission_code) select $1,$2,code from core.permissions where module='people'",
          [tenant, uid(name + ".role")]);
      }
      const selfService = await scalar("select to_regprocedure('api.employee_self_leave_range_submit(uuid,uuid,uuid,uuid,uuid,jsonb,bigint)') is not null as value");
      if (selfService) {
        await tx.query("insert into core.role_permissions(tenant_id,role_id,permission_code) values ($1,$2,'people.view'),($1,$2,'people.self.view'),($1,$2,'people.leave.self.manage')",
          [tenant, uid("worker.role")]);
      }

      const today = await scalar("select (now() at time zone 'Asia/Colombo')::date::text as value");
      // The first Thursday at least three days ahead: Thursday to Monday spans a weekend.
      const thursday = await scalar(
        "select (d + ((4 - extract(isodow from d)::integer + 7) % 7))::text as value from (select $1::date + 3 as d) x", [today]);
      const D = (await rows("select ($1::date + g)::text as d from generate_series(0,31) g order by g", [thursday])).map((row) => row.d);

      await actor("creator");
      for (const name of ["employee", "manager"]) {
        await scalar(
          "select api.people_employee_command($1,$2,$3,$4,$4,now(),jsonb_build_object('action','create','id',$5::uuid,'code',$6::text," +
          "'display_name',$6::text,'work_email',null,'start_date',$7::date-10,'job_title','Fixture role','employment_type','permanent'),0) is not null as value",
          [tenant, entity, branch, uid(name + ".create"), uid(name), name.toUpperCase(), today]);
      }
      await owner();
      const weekdays = JSON.stringify([1, 2, 3, 4, 5].map((dow) => ({ day_of_week: dow, start_minute: 540, end_minute: 1020, end_day_offset: 0 })));
      const overrides = JSON.stringify([{ date: D[8], is_working_day: false, reason: "Fixture holiday" }]);
      await tx.query("insert into people.work_calendars(id,tenant_id,legal_entity_id,code,name,created_by,updated_by) values ($1,$2,$3,'LRCAL','Fixture calendar',$4,$4)",
        [uid("calendar"), tenant, entity, uid("creator")]);
      await tx.query(
        "insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,start_date,end_date_exclusive,timezone,weekly_intervals,date_overrides,published_by) " +
        "values ($1,$2,$3,$4,$5::date-10,$5::date+400,'Asia/Colombo',$6,$7,$8)",
        [uid("calendar-version"), tenant, entity, uid("calendar"), today, weekdays, overrides, uid("creator")]);
      await tx.query("insert into people.departments(id,tenant_id,legal_entity_id,code) values ($1,$2,$3,'LROPS')", [uid("department"), tenant, entity]);
      await tx.query(
        "insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,start_date,end_date_exclusive,reason,recorded_by) " +
        "values ($1,$2,$3,$4,'Operations',$5::date-10,$5::date+400,'Fixture',$6)", [uid("department-r1"), tenant, entity, uid("department"), today, uid("creator")]);
      for (const name of ["employee", "manager"]) {
        await tx.query(
          "insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,role_title," +
          "start_date,end_date_exclusive,reason,recorded_by) select $1,$2,$3,$4,$5,s.id,$6,$7,'Fixture worker',$8::date-10,$8::date+400,'Fixture',$9 " +
          "from people.employment_spells s where s.employee_id=$5",
          [uid(name + ".organization"), tenant, entity, branch, uid(name), uid("department"), uid("calendar-version"), today, uid("creator")]);
      }

      const command = (fn, key, payload, version) => scalar(
        "select api." + fn + "($1,$2,$3,$4,$4,now(),$5::jsonb" + (version === undefined ? "" : ",$6") + ") as value",
        version === undefined ? [tenant, entity, branch, uid(key), JSON.stringify(payload)] : [tenant, entity, branch, uid(key), JSON.stringify(payload), version]);
      await actor("creator");
      await command("people_leave_policy_command", "policy", {
        action: "create", id: uid("policy"), version_id: uid("policy.v1"), code: "LRLEAVE", name: "Fixture leave",
        start_date: await scalar("select ($1::date-10)::text as value", [today]), end_date_exclusive: await scalar("select ($1::date+400)::text as value", [today]),
        unit: "hours", day_seconds: 28800, accrual_frequency: "monthly", accrual_seconds: 28800, carry_cap_seconds: 57600, expiry_days: 365,
        eligible_types: ["permanent"], allow_unpaid: false, reason: "Fixture policy",
      }, 0);
      const balance = async (employee = "employee") => (await scalar(
        "select api.people_leave_balance($1,$2,$3,$4,$5,$6::date) as value", [tenant, entity, branch, uid(employee), uid("policy"), today]));
      const grant = async (key, seconds, employee = "employee") => command("people_leave_grant_command", key, {
        action: "adjust", id: uid(key), employee_id: uid(employee), policy_version_id: uid("policy.v1"), effective_date: today,
        source_key: key.toUpperCase(), seconds, reason: "Fixture grant",
      }, Number((await balance(employee)).account_version));
      await grant("grant-1", 57600);
      await grant("grant-manager", 28800, "manager");

      const range = (batch, start, end, extra = {}) => ({
        batch_id: uid(batch), employee_id: uid("employee"), policy_version_id: uid("policy.v1"), calendar_version_id: uid("calendar-version"),
        start_date: start, end_date: end, reason: "PRIVATE_RANGE_REASON", ...extra,
      });
      const create = (key, payload) => command("people_leave_request_range", key, payload);
      const batchAction = (key, action, batch, employee = "employee") =>
        command("people_leave_batch_command", key, { action, batch_id: uid(batch), employee_id: uid(employee), reason: "Fixture " + action });
      const requests = async (batch) => {
        await owner();
        const result = await rows(
          "select d.leave_date::text as leave_date, r.status, r.charge_seconds::integer as charge from people.leave_request_batch_days d " +
          "join people.leave_requests r on r.id=d.request_id where d.batch_id=$1 order by d.leave_date", [uid(batch)]);
        return result;
      };

      // 1. A five-day range over a weekend creates the three working days only.
      const created = await create("create-a", range("batch-a", thursday, D[4]));
      const expectedDays = [thursday, D[1], D[4]];
      equal(created.entity.days.map((item) => item.leave_date), expectedDays, "only Thursday, Friday and Monday are requested");
      equal(created.entity.status, "draft", "a staff range is created as drafts");
      equal(created.entity.charge_seconds, 3 * 28800, "the batch charges one work slot per working day");
      equal((await requests("batch-a")).map((item) => [item.leave_date, item.status, item.charge]),
        expectedDays.map((date) => [date, "draft", 28800]), "one draft request per working day is linked to the batch");
      ok(!JSON.stringify(created).includes("PRIVATE_RANGE_REASON"), "the private reason stays out of the receipt");

      // 2. Replaying the same command returns the same answer and creates nothing more.
      await actor("creator");
      equal(await create("create-a", range("batch-a", thursday, D[4])), created, "an exact replay returns the first answer");
      equal((await requests("batch-a")).length, 3, "a replay creates no further requests");
      await actor("creator");
      await rejects(() => create("create-a", range("batch-a", thursday, D[3])), /IDEMPOTENCY_MISMATCH/);
      await rejects(() => create("create-a-again", range("batch-a", thursday, D[4])), /LEAVE_BATCH_EXISTS/);

      // 3. Ranges that cannot be a batch are refused.
      await rejects(() => create("weekend", range("batch-weekend", D[2], D[3])), /LEAVE_RANGE_NO_WORKING_DAY/);
      await rejects(() => create("too-long", range("batch-long", thursday, D[31])), /LEAVE_RANGE_INVALID/);
      await rejects(() => create("backwards", range("batch-back", D[1], thursday)), /LEAVE_RANGE_INVALID/);
      await rejects(() => create("extra-field", range("batch-extra", thursday, thursday, { unpaid: true })), /LEAVE_RANGE_INVALID/);

      // 4. A failure on one day creates nothing: the Monday request id is already taken.
      await owner();
      const takenMonday = await scalar("select people.leave_range_id('request',$1,$2::date) as value", [uid("batch-atomic"), D[11]]);
      await actor("creator");
      await command("people_leave_request_command", "taken-monday", {
        action: "create", id: takenMonday, employee_id: uid("employee"), policy_version_id: uid("policy.v1"), calendar_version_id: uid("calendar-version"),
        start_local: (D[11]) + "T09:00:00", start_offset_seconds: 19800, end_local: (D[11]) + "T17:00:00", end_offset_seconds: 19800, reason: "Taken",
      }, 0);
      await rejects(() => create("atomic", range("batch-atomic", D[7], D[11])), /duplicate key|23505/);
      await owner();
      equal(await scalar("select count(*)::integer as value from people.leave_request_batches where id=$1", [uid("batch-atomic")]), 0, "the failed batch is not kept");
      equal(await scalar("select count(*)::integer as value from people.leave_requests where id=people.leave_range_id('request',$1,$2::date)",
        [uid("batch-atomic"), D[7]]), 0, "the failed batch keeps no request for its earlier day");

      // 5. Submit and decide together; the author cannot decide.
      await actor("creator");
      const submitted = await batchAction("submit-a", "submit", "batch-a");
      equal(submitted.entity.status, "submitted", "submit moves every day");
      equal(await batchAction("submit-a", "submit", "batch-a"), submitted, "a batch action replays exactly");
      await rejects(() => batchAction("self-approve-a", "approve", "batch-a"), /LEAVE_INDEPENDENT_DECISION_REQUIRED/);

      // Two days of balance for three days: the third day fails and nothing is approved.
      await actor("reviewer");
      const before = await balance();
      await rejects(() => batchAction("approve-a-short", "approve", "batch-a"), /LEAVE_BALANCE_INSUFFICIENT/);
      equal((await requests("batch-a")).map((item) => item.status), ["submitted", "submitted", "submitted"], "a failed approval leaves every day submitted");
      equal(await scalar("select count(*)::integer as value from people.leave_effects x join people.leave_request_batch_days d on d.request_id=x.request_id where d.batch_id=$1",
        [uid("batch-a")]), 0, "a failed approval debits nothing");

      await actor("creator");
      await grant("grant-2", 57600);
      await actor("reviewer");
      const funded = await balance();
      const approved = await batchAction("approve-a", "approve", "batch-a");
      equal(approved.entity.status, "approved", "approve moves every day");
      const after = await balance();
      equal(Number(funded.available_seconds) - Number(after.available_seconds), 3 * 28800, "the balance is charged once per day");
      equal(Number(after.account_version) - Number(funded.account_version), 3, "the leave account advances once per day");
      ok(Number(funded.available_seconds) > Number(before.available_seconds), "the second grant funded the approval");
      await owner();
      equal((await rows(
        "select sum(x.seconds)::integer as seconds from people.leave_request_batch_days d join people.leave_effects x on x.request_id=d.request_id " +
        "where d.batch_id=$1 group by d.leave_date order by d.leave_date", [uid("batch-a")])).map((row) => row.seconds),
        [-28800, -28800, -28800], "each day is debited exactly one work slot");
      await actor("reviewer");
      equal(await batchAction("approve-a", "approve", "batch-a"), approved, "an approval replays without charging again");
      equal(Number((await balance()).available_seconds), Number(after.available_seconds), "a replayed approval charges nothing");

      // 6. Cancel together restores every day.
      const cancelled = await batchAction("cancel-a", "cancel", "batch-a");
      equal(cancelled.entity.status, "cancelled", "cancel moves every day");
      equal(Number((await balance()).available_seconds), Number(funded.available_seconds), "cancellation restores every day's debit");

      // 7. Reject together; an override day is skipped.
      await actor("creator");
      const second = await create("create-b", range("batch-b", D[7], D[10]));
      equal(second.entity.days.map((item) => item.leave_date), [D[7]], "the non-working override Friday and the weekend are skipped");
      await batchAction("submit-b", "submit", "batch-b");
      await actor("reviewer");
      equal((await batchAction("reject-b", "reject", "batch-b")).entity.status, "rejected", "reject moves every day");
      equal((await requests("batch-b")).map((item) => item.status), ["rejected"], "the rejected day is recorded");

      // 8. Nobody decides their own batch: the reviewer is linked to the manager.
      await actor("creator");
      await create("create-c", { ...range("batch-c", D[21], D[21]), employee_id: uid("manager") });
      await batchAction("submit-c", "submit", "batch-c", "manager");
      await owner();
      await tx.query(
        "insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at) " +
        "values ($1,$2,$3,$4,$5,$6,$7,'accepted',$8,now())",
        [uid("reviewer-link"), tenant, entity, branch, uid("manager"), uid("reviewer.membership"), uid("reviewer"), uid("creator")]);
      await actor("reviewer");
      await rejects(() => batchAction("approve-c", "approve", "batch-c", "manager"), /LEAVE_SELF_DECISION_DENIED/);

      // 9. A batch reads as one item with its days.
      const listed = await scalar("select api.people_leave_batches($1,$2,$3,$4) as value", [tenant, entity, branch, uid("employee")]);
      equal(listed.items.map((item) => [item.id, item.status, item.days.length]).sort(),
        [[uid("batch-a"), "cancelled", 3], [uid("batch-b"), "rejected", 1]].sort(), "staff see each batch with its days");

      // 10. MFA and anonymous access.
      await actor("creator", { aal: "aal1" });
      await rejects(() => create("no-mfa", range("batch-mfa", thursday, thursday)), /LEAVE_MFA_REQUIRED/);
      await owner();
      ok(!(await scalar("select has_function_privilege('anon','api.people_leave_request_range(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb)','EXECUTE') as value")),
        "anonymous callers cannot create a range");
      ok(await scalar("select bool_and(c.relrowsecurity and c.relforcerowsecurity) as value from pg_class c join pg_namespace n on n.oid=c.relnamespace " +
        "where n.nspname='people' and c.relname in ('leave_request_batches','leave_request_batch_days')"), "batch tables force RLS");
      ok(!(await scalar("select has_table_privilege('authenticated','people.leave_request_batches','SELECT') as value")), "batch tables are API-only");

      // 11. Employee App: an employee submits their own range in one step.
      if (selfService) {
        const session = uid("worker-session");
        await tx.query("insert into auth.sessions(id,user_id,created_at) values ($1,$2,now())", [session, uid("worker")]);
        await tx.query(
          "insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at) " +
          "values ($1,$2,$3,$4,$5,$6,$7,'accepted',$8,now())",
          [uid("worker-link"), tenant, entity, branch, uid("employee"), uid("worker.membership"), uid("worker"), uid("creator")]);
        const own = async (key, payload, balanceVersion) => scalar(
          "select api.employee_self_leave_range_submit($1,$2,$3,$4,$5,$6::jsonb,$7) as value",
          [tenant, entity, branch, uid(key), payload.batch_id, JSON.stringify(payload.body), balanceVersion]);
        const ownRange = (batch, start, end) => ({ batch_id: uid(batch), body: {
          policy_version_id: uid("policy.v1"), calendar_version_id: uid("calendar-version"), start_date: start, end_date: end, reason: "Own range" } });
        const version = Number((await balance()).account_version);
        await actor("worker", { session_id: session });
        const mine = await own("own-range", ownRange("batch-own", D[14], D[18]), version);
        equal(mine.days.map((item) => item.leave_date), [D[14], D[15], D[18]], "the employee's own range skips the weekend");
        equal(mine.status, "submitted", "the employee's own range is submitted for approval");
        equal([mine.request_id, mine.version, mine.approval_required], [uid("batch-own"), 1, true], "the receipt names the batch as its request");
        const lookup = await scalar("select api.employee_self_receipt($1,$2,$3,$4,$5,'employee_self_leave_range_submit') as value",
          [tenant, entity, branch, uid("own-range"), uid("batch-own")]);
        equal([lookup.abandoned, lookup.receipt], [false, mine], "a saved range request is reconciled from its receipt");
        equal(await own("own-range", ownRange("batch-own", D[14], D[18]), version), mine, "the employee's own range replays exactly");
        await rejects(() => own("own-weekend", ownRange("batch-own-weekend", D[16], D[16]), version), /LEAVE_RANGE_NO_WORKING_DAY/);
        const ownList = await scalar("select api.employee_self_leave_batches($1,$2,$3) as value", [tenant, entity, branch]);
        equal(ownList.items.map((item) => [item.id, item.days.length]).sort(),
          [[uid("batch-a"), 3], [uid("batch-b"), 1], [uid("batch-own"), 3]].sort(), "the employee sees each of their batches with its days");
        ok(ownList.items.every((item) => !("created_by" in item)), "the employee list leaves out who created each batch");
        await actor("reviewer");
        equal((await batchAction("approve-own", "approve", "batch-own")).entity.status, "approved", "staff approve the employee's batch together");
      }
      throw rollback;
    });
  } catch (error) {
    if (error !== rollback) throw error;
  }
  console.log("Multi-day leave passed " + checks + " range, batch decision and self-service assertions.");
}
