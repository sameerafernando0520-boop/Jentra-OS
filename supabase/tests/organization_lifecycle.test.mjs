// Applies tracked migrations to a disposable PostgreSQL WASM instance.
// No hosted database, credentials, files or account are touched.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { testPlatformOrganizationControl } from "./platform_organization_control.assertions.mjs";

const defaultRuntime = new URL("../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js", import.meta.url);
const runtime = process.env.JENTRA_PGLITE_MODULE ? pathToFileURL(process.env.JENTRA_PGLITE_MODULE) : defaultRuntime;
const { PGlite } = await import(runtime.href);
const { pgcrypto } = await import(new URL("contrib/pgcrypto.js", runtime).href);
const { btree_gist } = await import(new URL("contrib/btree_gist.js", runtime).href);
const db = new PGlite({ extensions: { pgcrypto, btree_gist } });
const migrations = new URL("../migrations/", import.meta.url);

const operator = randomUUID(), member = randomUUID(), secondMember = randomUUID(), managed = randomUUID();
const first = randomUUID(), second = randomUUID();
const id = randomUUID(), archiveId = randomUUID(), oldId = randomUUID(), alternateId = randomUUID();

const scalar = async (sql, args = [], conn = db) => (await conn.query(sql, args)).rows[0]?.value;
const as = (user, aal, body, role = "authenticated") => db.transaction(async tx => {
  await tx.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({ sub: user, aal, role })]);
  await tx.exec("set local role " + role);
  return body(tx);
});
const lock = (locked, tx) => scalar("select api.platform_set_organization_lock($1,$2,'Fixture maintenance reason') as value", [first, locked], tx);
const snapshot = () => as(null, null, tx =>
  scalar("select api.platform_organization_archive_snapshot($1) as value", [first], tx), "service_role");

async function recordBackup(backupId, s) {
  await db.query("insert into storage.objects(bucket_id,name) values ('jentra-organization-archives', $1)", [backupId + ".bin"]);
  return as(null, null, tx => scalar(
    "select api.platform_organization_backup_commit($1,$2,$3,$4,$5,$6,$7,456,$8) as value",
    [first, backupId, s.lock_id, operator, s.database_sha256, "a".repeat(64), "b".repeat(64), JSON.stringify(s.files)], tx
  ), "service_role");
}

const startPurge = (backupId, slug = "org-first") => as(null, null, tx => scalar(
  "select api.platform_organization_purge_begin($1,$2,$3,$4) as value", [first, backupId, operator, slug], tx
), "service_role");
const finishPurge = backupId => as(null, null, tx => scalar(
  "select api.platform_organization_purge_finish($1,$2,$3) as value", [first, backupId, operator], tx
), "service_role");

try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create role authenticator;
    create schema extensions;
    create schema auth;
    create schema storage;
    create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text,
      updated_at timestamptz default now(), version text, owner_id text, metadata jsonb);
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated;
    grant select,insert,update on storage.objects to authenticated;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,
      raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',
      encrypted_password text, deleted_at timestamptz, banned_until timestamptz,
      is_sso_user boolean not null default false, created_at timestamptz default clock_timestamp());
    create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,
      not_after timestamptz,created_at timestamptz not null default clock_timestamp());
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
    $$;
    create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
    create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
    grant usage on schema auth,extensions to authenticated,anon,service_role;
  `);
  const names = (await readdir(migrations)).filter(name => name.endsWith(".sql") &&
    // Scheduler installation needs pg_cron and pg_net.
    name !== "20261009123000_wave5_supabase_schedule.sql").sort();
  for (const name of names) {
    try { await db.exec((await readFile(new URL(name, migrations), "utf8")).replaceAll("\r\n", "\n")); }
    catch (error) { throw Error("Migration " + name + ": " + error.message); }
  }
  await testPlatformOrganizationControl(db);
  assert.equal(await scalar("select to_regprocedure('api.platform_organization_cleanup_pending()') is not null as value"), true);
  await db.query("insert into auth.users(id, email) values ($1,'operator@fixture.invalid'),($2,'member@fixture.invalid'),($3,'second@fixture.invalid')",
    [operator, member, secondMember]);
  await db.query("insert into intelligence_control.operators(actor_id,active,organization_manage) values ($1,true,true)", [operator]);
  await db.query("insert into core.tenants(id,name,slug,status,created_by) values ($1,'Org One','org-first','trial',$3),($2,'Org Two','org-second','active',$3)",
    [first, second, operator]);
  await db.query("insert into core.memberships(tenant_id,user_id) values ($1,$3),($2,$3),($1,$4)",
    [first, second, member, secondMember]);
  await db.query(`insert into auth.users(id,email,raw_app_meta_data)
    values ($1,'retire-fixture@admin.jentra.invalid','{"managed_org_admin":true}')`, [managed]);
  await db.query("insert into core.organization_administrator_logins(tenant_id,user_id,username) values ($1,$2,'retire-fixture')",
    [first, managed]);
  await db.query("insert into core.organization_account_recovery(user_id,email,verified_at) values ($1,'private@fixture.invalid',now())",
    [managed]);
  await db.query("insert into core.memberships(tenant_id,user_id) values ($1,$2)", [first, managed]);
  await db.query("insert into core.legal_entities(tenant_id,name,code,created_by) values ($1,'First Legal','AA',$3),($2,'Second Legal','BB',$3)",
    [first, second, operator]);
  await db.query("insert into audit.events(tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id) values ($1,$3,$4,'fixture','tenant',$1),($2,$3,$4,'fixture','tenant',$2)",
    [first, second, operator, id]);
  await db.query("insert into storage.objects(bucket_id,name,owner_id,metadata) values " +
    "('jentra-attachments',$1,$3,'{\"size\":7}'),('jentra-attachments',$2,$3,'{\"size\":5}')",
    [first + "/a.txt", second + "/b.txt", member]);

  await assert.rejects(as(member, "aal2", tx => lock(true, tx)), { code: "42501" });
  await assert.rejects(as(operator, "aal1", tx => lock(true, tx)), { code: "42501" });
  await assert.rejects(snapshot(), /ORGANIZATION_LOCK_REQUIRED/);
  assert.equal(await as(member, "aal1", tx => scalar(
    "select count(*)::int as value from api.list_my_tenants()", [], tx)), 2);

  assert.deepEqual(await as(operator, "aal2", tx => lock(true, tx)), { locked: true });
  assert.equal(await as(member, "aal1", tx => scalar(
    "select count(*)::int as value from api.list_my_tenants()", [], tx)), 1);
  assert.equal(await as(member, "aal1", tx => scalar(
    "select count(*)::int as value from api.legal_entities where tenant_id = $1", [first], tx)), 0);
  await assert.rejects(db.query("update core.legal_entities set name = 'Changed' where tenant_id = $1", [first]), /ORGANIZATION_LOCKED/);
  await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values ('jentra-attachments',$1)", [first + "/new.txt"]), /ORGANIZATION_LOCKED/);
  await assert.rejects(as(member, "aal2", tx => scalar(
    "select api.platform_organization_archive_snapshot($1) as value", [first], tx)), { code: "42501" });

  const old = await snapshot();
  assert.equal(JSON.parse(old.database_json)["core.tenants"][0].id, first);
  assert.equal(JSON.parse(old.database_json)["audit.events"].length, 1);
  assert.equal(JSON.parse(old.database_json)["core.legal_entities"][0].name, "First Legal");
  assert.deepEqual(old.files.map(x => x.name), [first + "/a.txt"]);
  assert.equal(old.previous_status, "trial");
  assert.doesNotMatch(old.database_json, /encrypted_password|operator@fixture\.invalid|private@fixture\.invalid/);
  assert.equal((await recordBackup(oldId, old)).backup_id, oldId);
  assert.deepEqual(await as(operator, "aal2", tx => lock(false, tx)), { locked: false });
  assert.equal(await scalar("select status as value from core.tenants where id=$1", [first]), "trial");
  await as(operator, "aal2", tx => lock(true, tx));
  await assert.rejects(startPurge(oldId), /ORGANIZATION_CURRENT_BACKUP_REQUIRED/);
  const current = await snapshot();
  assert.equal((await recordBackup(archiveId, current)).backup_id, archiveId);
  await recordBackup(alternateId, current);
  await assert.rejects(startPurge(archiveId, "org-second"), /ORGANIZATION_CONFIRMATION_MISMATCH/);

  // A CASCADE in an unscoped table must block the entire operation.
  await db.exec("create table core.lifecycle_unclassified_fixture(tenant_ref uuid references core.tenants(id) on delete cascade)");
  await db.query("insert into core.lifecycle_unclassified_fixture values ($1)", [first]);
  await assert.rejects(startPurge(archiveId), /ORGANIZATION_PURGE_SCOPE_CONFLICT/);
  await db.exec("drop table core.lifecycle_unclassified_fixture");

  assert.deepEqual((await startPurge(archiveId)).files.map(x => x.name), [first + "/a.txt"]);
  await assert.rejects(as(operator, "aal2", tx => lock(false, tx)), /ORGANIZATION_PURGE_IN_PROGRESS/);
  await assert.rejects(startPurge(alternateId), /ORGANIZATION_PURGE_IN_PROGRESS/);
  await assert.rejects(finishPurge(archiveId), /ORGANIZATION_PURGE_NOT_READY/);
  // Simulate the Storage API having removed the actual blob and its metadata.
  await db.query("delete from storage.objects where name = $1", [first + "/a.txt"]);
  assert.deepEqual((await startPurge(archiveId)).files, []);
  assert.deepEqual(await finishPurge(archiveId), { deleted: true });
  assert.deepEqual((await db.query("select id from core.tenants order by id")).rows, [{ id: second }]);
  assert.equal(await scalar("select count(*)::int as value from audit.events where tenant_id=$1", [second]), 1);
  assert.equal(await scalar("select count(*)::int as value from storage.objects where name=$1", [second + "/b.txt"]), 1);
  assert.equal(await scalar("select count(*)::int as value from auth.users where id=$1", [member]), 1);
  assert.equal(await scalar("select count(*)::int as value from organization_lifecycle.events where action='purge'"), 1);
  await assert.rejects(db.query("delete from audit.events where tenant_id=$1", [second]), /append-only/);
  const queue = () => as(null, null, tx => scalar(
    "select api.platform_organization_purge_identity_queue($1,$2) as value", [first, archiveId], tx
  ), "service_role");
  assert.deepEqual(await queue(), [managed]);
  // Simulate GoTrue's hard delete after the service returns this exact account.
  await db.query("delete from auth.users where id=$1", [managed]);
  assert.deepEqual(await queue(), []);
  assert.equal(await scalar("select count(*)::int as value from core.organization_account_recovery where user_id=$1", [managed]), 0);
  const archives = await as(operator, "aal2", tx =>
    scalar("select api.platform_organization_archive_history() as value", [], tx));
  assert.ok(archives.some(x => x.backup_id === archiveId && x.tenant_id === first && x.deleted_at));
  await assert.rejects(as(member, "aal2", tx =>
    scalar("select api.platform_organization_archive_history() as value", [], tx)), { code: "42501" });

  // Restore the representative core and audit rows into the same disposable
  // instance after purge, retaining foreign-key enforcement. Actual hosted
  // restore also maps identities and uploads the manifest's Storage bytes.
  const restored = JSON.parse(current.database_json);
  restored["core.tenants"][0].status = current.previous_status;
  for (const table of ["core.tenants", "core.legal_entities", "audit.events"]) {
    await db.query(`insert into ${table} select * from jsonb_populate_recordset(null::${table}, $1)`,
      [JSON.stringify(restored[table])]);
  }
  assert.equal(await scalar("select status as value from core.tenants where id=$1", [first]), "trial");
  assert.equal(await scalar("select name as value from core.legal_entities where tenant_id=$1", [first]), "First Legal");
  assert.equal(await scalar("select count(*)::int as value from audit.events where tenant_id=$1", [first]), 1);
  console.log("Organization lifecycle verified: operator authorization, frozen access and writes, current backup, explicit confirmation, cross-tenant reference refusal, resumable purge, and unaffected tenant.");
} finally {
  await db.close();
}
