// Applies the tracked migrations and every uninstalled candidate in order,
// then runs only the multi-day leave assertions. No hosted database is used.
import { readFile } from "node:fs/promises";
import { allowLegacySelfServiceFixtures, openIsolatedDatabase, pendingInstall } from "./isolated_database.mjs";
import { testPeopleLeaveRange } from "./people_leave_range.assertions.mjs";

const { migrations, candidates, tracked, pending } = await pendingInstall();
const db = await openIsolatedDatabase();
try {
  for (const [name, directory] of [...tracked.map(name => [name, migrations]), ...pending.map(name => [name, candidates])]) {
    try { await db.exec((await readFile(new URL(name, directory), "utf8")).replaceAll("\r\n", "\n")); }
    catch (error) {
      throw new Error("Migration " + name + ": " + error.message + (error.where ? " (" + error.where + ")" : ""), { cause: error });
    }
  }
  await allowLegacySelfServiceFixtures(db);
  await testPeopleLeaveRange(db);
} finally {
  await db.close();
}
