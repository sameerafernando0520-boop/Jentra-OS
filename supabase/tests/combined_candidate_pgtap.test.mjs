// Runs the company access and Employee pgTAP harnesses against the combined
// install: tracked migrations, then every uninstalled candidate in timestamp
// order, organization control last.
//
// The harnesses normally include their candidate inside one rollback. Here the
// candidates are already installed, so the include lines are removed. Their
// "original functions unchanged" assertions then compare the installed state
// with itself; the behaviour assertions are the point of this run.
//
// Needs the official pgTAP 1.3.4 SQL template, as the company access probe in
// docs/verification/company-access-20261028 does: build/pgtap-1.3.4.sql.in, or
// the file named by JENTRA_PGTAP_SOURCE.
// No hosted database, credentials, files or account are touched.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { applySqlFiles, openIsolatedDatabase, pendingInstall } from "./isolated_database.mjs";

const harnesses = [
  ["company_access_administration_test", 31],
  ["employee_push_candidate_test", 47],
  ["employee_self_service_candidate_test", 121],
  ["employee_cases_documents_test", 92],
  ["employee_hr_event_producers_test", 77],
];
const source = process.env.JENTRA_PGTAP_SOURCE ? pathToFileURL(process.env.JENTRA_PGTAP_SOURCE)
  : new URL("../../build/pgtap-1.3.4.sql.in", import.meta.url);
const template = await readFile(source, "utf8").catch(error => {
  throw new Error("pgTAP 1.3.4 template not found. Set JENTRA_PGTAP_SOURCE to pgtap.sql.in from the v1.3.4 release.", { cause: error });
});
assert.equal(createHash("sha256").update(template).digest("hex"),
  "383ecd73edfd1c7ed5f3b835134ee1fe74e201ee31599346c92ea029b65dcdce", "Pinned pgTAP 1.3.4 template.");
// The substitutions the upstream Makefile makes for modern PostgreSQL.
const pgtap = template.replaceAll("__OS__", "linux").replaceAll("__VERSION__", "1.3").replaceAll("MODULE_PATHNAME", "pgtap");

const { migrations, candidates, tracked, pending } = await pendingInstall();
const db = await openIsolatedDatabase();
try {
  // The harness fixtures use more of Auth and the migration ledger than the shared stand-ins have.
  await db.exec(`
    alter table auth.users add column instance_id uuid, add column aud text, add column role text, add column updated_at timestamptz;
    alter table auth.sessions add column updated_at timestamptz;
    create schema supabase_migrations;
    create table supabase_migrations.schema_migrations(version text primary key, statements text[], name text);
  `);
  await applySqlFiles(db, [...tracked.map(name => [name, migrations]), ...pending.map(name => [name, candidates])]);
  await db.exec("begin; set local search_path = extensions, public, pg_catalog; " + pgtap + "; commit;");

  const include = /^\\ir \.\.\/\d{14}_[a-z0-9_]+\.sql[\t ]*$/gm;
  const extension = "create extension if not exists pgtap with schema extensions;";
  let total = 0;
  for (const [name, expected] of harnesses) {
    const harness = (await readFile(new URL("tests/" + name + ".sql", candidates), "utf8")).replaceAll("\r\n", "\n");
    const included = harness.match(include) ?? [];
    assert.ok(included.length > 0, name + " includes its candidate.");
    for (const line of included) assert.ok(pending.includes(line.trim().slice("\\ir ../".length)), name + " includes an installed candidate: " + line);
    assert.equal(harness.split(extension).length, 2, name + " loads pgTAP once.");
    const suite = harness.replace(include, "-- Candidate already installed.").replace(extension, "-- pgTAP already loaded.");
    assert.ok(!/^\s*\\/m.test(suite), name + " has no other psql command.");
    assert.ok(/^begin;/m.test(suite) && /rollback;\s*$/.test(suite) && !/^\s*commit\s*;/im.test(suite), name + " stays inside one rollback.");

    let results;
    try { results = await db.exec(suite); }
    catch (error) {
      await db.exec("rollback").catch(() => {});
      throw new Error(name + ": " + error.message + (error.where ? " (" + error.where + ")" : ""), { cause: error });
    }
    const tap = results.flatMap(result => result.rows.flatMap(row => Object.values(row)))
      .filter(value => typeof value === "string" && /^(?:not ok|ok |[0-9]+\.\.[0-9]+)/.test(value));
    const failed = tap.filter(line => line.startsWith("not ok"));
    assert.deepEqual(failed, [], name + " has failing assertions.");
    const passed = tap.filter(line => /^ok [0-9]+\b/.test(line)).length;
    assert.ok(tap.includes("1.." + passed), name + " plan matches its assertion count.");
    assert.ok(passed >= expected, name + " ran " + passed + " of at least " + expected + " assertions.");
    total += passed;
    await db.exec("reset role; reset search_path;");
  }
  console.log("Company access and Employee pgTAP harnesses verified on the combined install: " + total +
    " assertions across " + harnesses.length + " harnesses.");
} finally {
  await db.close();
}
