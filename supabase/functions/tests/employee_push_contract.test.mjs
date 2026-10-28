// Static security-contract checks only. These do not execute/validate PostgreSQL
// or establish hosted installation, recipient isolation or external delivery.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const sql = fs.readFileSync(new URL("../../candidates/20261023090000_employee_push.sql", import.meta.url), "utf8");
const body = name => sql.match(new RegExp(`create function ${name.replaceAll(".", "\\.")}\\([^]*?as \\$\\$([^]*?)\\$\\$;`))?.[1] ?? "";

test("candidate never grants staff powers or exposes private token tables", () => {
  for (const table of ["devices", "receipts", "deliveries"]) {
    assert.ok(sql.includes(`alter table employee_push.${table} enable row level security;`));
    assert.ok(sql.includes(`alter table employee_push.${table} force row level security;`));
  }
  assert.ok(sql.includes("revoke all on all tables in schema employee_push from public,anon,authenticated,service_role;"));
  assert.doesNotMatch(sql, /insert into core\.(roles|role_assignments|role_permissions)|update billing\./i);
  assert.doesNotMatch(sql, /grant (select|all).*employee_push\./i);
});

test("own registration derives session and accepted employee, bounds platform/FID and expires", () => {
  const register = body("api.employee_push_register");
  assert.ok(register.length > 100);
  assert.match(register, /employee_push\.session\(\)/);
  assert.match(body("employee_push.session"), /a\.not_after is null or a\.not_after>statement_timestamp\(\)/);
  assert.match(register, /people\.require_access\([^]*?'people\.self\.view'\)/);
  assert.match(register, /a\.user_id=auth\.uid\(\) and a\.status='accepted'/);
  assert.match(register, /m\.status='active'/);
  assert.match(register, /p_platform is distinct from 'android'/);
  assert.match(register, /length\(p_token\) not between 20 and 4096/);
  assert.match(register, /interval '24 hours'/);
  assert.match(register, /PUSH_COMMAND_REUSED/);
  assert.match(register, /employee-push-user:/);
  assert.match(register, /d\.installation_id is null or d\.user_id<>auth\.uid\(\) or d\.status<>'active' or d\.expires_at<=statement_timestamp\(\)/);
  assert.match(register, /employee_push\.binding_current\(d\)/);
  const signature = sql.match(/create function api\.employee_push_register\(([^]*?)\) returns jsonb/)[1];
  assert.doesNotMatch(signature, /p_(user|employee|session)_id/);
  assert.doesNotMatch(register, /jsonb_build_object\([^;]*'token'/);
});

test("removal remains own-session authorized after People access is lost", () => {
  const remove = body("api.employee_push_remove");
  assert.match(remove, /employee_push\.session\(\)/);
  assert.match(remove, /user_id=auth\.uid\(\) and session_id=s/);
  assert.match(remove, /x\.state in \('pending','leased'\)/);
  assert.match(remove, /status='removed',token=null,token_hash=null/);
  assert.match(remove, /'removed',affected>0/);
  assert.match(remove, /r\.response\|\|jsonb_build_object\('removed',exists/);
  assert.doesNotMatch(remove, /people\.require_access|active_link|module\.people/);
});

test("binding recheck covers session, link revision, employment, modules and role MFA", () => {
  const current = body("employee_push.binding_current");
  for (const invariant of ["auth.sessions", "s.not_after is null or s.not_after>statement_timestamp()", "l.version=d.link_version", "l.status='accepted'", "m.status='active'",
    "people.employment_assignments", "module.people", "people.self.view", "r.requires_mfa", "d.expires_at>statement_timestamp()"])
    assert.ok(current.includes(invariant), invariant);
});

test("outbox cannot accept client-selected recipient/content and workers enforce leases", () => {
  const enqueue = body("employee_push.enqueue_notification");
  assert.match(enqueue, /new\.notification_type like 'people\.%'/);
  assert.match(enqueue, /d\.user_id=new\.recipient_id/);
  assert.doesNotMatch(enqueue, /new\.(title|body)|insert into workflow\.notifications/);
  const claim = body("api.employee_push_claim"), target = body("api.employee_push_target"), finish = body("api.employee_push_finish");
  for (const worker of [claim, target, finish]) assert.match(worker, /auth\.role\(\) is distinct from 'service_role'/);
  assert.match(claim, /for update skip locked limit p_limit/);
  assert.match(claim, /attempt<5/);
  assert.match(claim, /status='removed',token=null,token_hash=null/);
  assert.match(claim, /interval '7 days'/);
  assert.match(target, /employee_push\.binding_current\(d\)/);
  assert.match(target, /n\.recipient_id<>d\.user_id/);
  assert.match(target, /n\.read_at is not null/);
  assert.match(finish, /lease_id=p_lease_id[^]*lease_until>clock_timestamp\(\) for update/);
  assert.match(finish, /version=x\.binding_version/);
  assert.match(finish, /status='invalid',token=null,token_hash=null/);
  assert.match(finish, /p_outcome='retry' and attempt<5/);
  assert.ok(sql.includes("to service_role;"));
  assert.doesNotMatch(sql, /grant execute on function api\.employee_push_(claim|target|finish)[^;]*to authenticated/);
});
