// Replays the Field Sales rollout sequence with organization control present.
//
// Each Field Sales exercise is written to run right after its own candidate is
// applied, on the fixtures the earlier exercises leave behind, so the sequence
// cannot run against the final installed state. Here organization control is
// applied after the first two Field Sales candidates and before any exercise,
// and the later Field Sales candidates are applied on top of it. That is not
// the hosted install order; it shows that every exercise holds with
// organization control installed. combined_candidate_install.test.mjs covers
// the real order with the governance exercise.
// No hosted database, credentials, files or account are touched.
import assert from "node:assert/strict";
import { applySqlFiles, openIsolatedDatabase, organizationCandidates, pendingInstall } from "./isolated_database.mjs";

const { migrations, candidates, tracked, pending } = await pendingInstall();
const emailConfirmation = "20261102090000_field_order_email_confirmation.sql";
const stages = [
  [null, "field_sales_governance", 88],
  [null, "field_confirmation", 46],
  ["20261102120000_field_confirmation_company_workspace.sql", "field_company", 16],
  ["20261103090000_field_sales_mail_worker.sql", "field_mail", 17],
  ["20261103100000_field_sales_company_progression.sql", "field_progression", 20],
  ["20261103110000_field_sales_delivery_acknowledgement.sql", "field_delivery", 35],
];
const first = pending.filter(name => name <= emailConfirmation);
for (const name of [emailConfirmation, ...stages.map(([candidate]) => candidate).filter(Boolean)]) {
  assert.ok(pending.includes(name), "Field Sales candidate is present: " + name);
}

const db = await openIsolatedDatabase();
try {
  await applySqlFiles(db, [
    ...tracked.map(name => [name, migrations]),
    ...first.map(name => [name, candidates]),
    ...organizationCandidates.map(name => [name, candidates]),
  ]);

  // The exercises use transaction-local roles and savepoints, and share fixtures.
  await db.exec("begin");
  let context, total = 0;
  try {
    for (const [candidate, file, expected] of stages) {
      await db.exec("reset role");
      if (candidate) await applySqlFiles(db, [[candidate, candidates]]);
      const checks = [];
      const { exercise } = await import(new URL("../candidates/tests/" + file + ".test.mjs", import.meta.url).href);
      let result;
      try { result = await exercise(db, checks, context); }
      catch (error) {
        throw new Error(file + " failed after " + checks.length + " checks (last passed: " +
          (checks.at(-1) ?? "none") + "): " + error.message, { cause: error });
      }
      if (file === "field_progression") context = result;
      assert.ok(checks.length >= expected, file + " ran " + checks.length + " of at least " + expected + " checks.");
      total += checks.length;
    }
  } finally {
    await db.exec("rollback");
  }
  console.log("Field Sales staged sequence verified with organization control installed: " + total +
    " checks across governance, confirmation, company workspace, mail, progression and delivery.");
} finally {
  await db.close();
}
