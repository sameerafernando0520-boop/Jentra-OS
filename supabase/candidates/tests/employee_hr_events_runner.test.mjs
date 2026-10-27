import test from "node:test";
import assert from "node:assert/strict";
import { buildSuite, main } from "../run-employee-hr-events-test.mjs";

const names = [
  "20261023090000_employee_push.sql",
  "20261025090000_employee_self_service.sql",
  "20261025100000_employee_cases_documents_notifications.sql",
  "20261027100000_employee_hr_event_producers.sql",
];
const candidates = Object.fromEntries(names.map((name, i) => [name, `select ${i};`]));
const harness = `begin;\n${names.map(name => `\\ir ../${name}`).join("\n")}\nrollback;\n`;

test("runner composes exact prerequisites and producers inside one rollback", () => {
  const result = buildSuite(candidates, harness);
  assert.ok(result.startsWith("begin;"));
  assert.match(result, /rollback;\s*$/);
  assert.doesNotMatch(result, /^\\(?:i|ir)\s/m);
  let last = result.indexOf("begin;");
  for (let i = 0; i < names.length; i++) {
    const current = result.indexOf(`select ${i};`);
    assert.ok(current > last, `${names[i]} remains in dependency order`);
    last = current;
  }
  assert.ok(last < result.lastIndexOf("rollback;"));
  assert.ok(buildSuite(candidates, harness.replaceAll("\n", "\r\n")).includes("select 3;"));
});

test("runner refuses absent, repeated, external or altered includes", () => {
  assert.throws(() => buildSuite(candidates, harness.replace(`\\ir ../${names[2]}\n`, "")));
  assert.throws(() => buildSuite(candidates, harness.replace("rollback;", `\\ir ../${names[0]}\nrollback;`)));
  assert.throws(() => buildSuite(candidates, harness.replace("rollback;", "\\ir ../unreviewed.sql\nrollback;")));
  assert.throws(() => buildSuite(candidates, harness.replace(`\\ir ../${names[3]}`, `\\ir ../${names[3]}.extra`)));
  assert.throws(() => buildSuite({ ...candidates, [names[1]]: undefined }, harness));
});

test("runner refuses commits and nested candidate transaction control", () => {
  assert.throws(() => buildSuite(candidates, harness.replace("rollback;", "commit;")));
  assert.throws(() => buildSuite(candidates, harness.replace("begin;", "begin;\ncommit;")));
  assert.throws(() => buildSuite(candidates, harness.replace("begin;\n", "")));
  assert.throws(() => buildSuite(candidates, `select 123;\n${harness}`));
  assert.throws(() => buildSuite(candidates, harness.replace("begin;", "begin;\nrollback;\nbegin;")));
  assert.throws(() => buildSuite(candidates, harness.replace(`\\ir ../${names[0]}`, `rollback;\n\\ir ../${names[0]}`)));
  for (const control of ["commit;", "rollback;", "begin;", "  COMMIT ;"]) {
    assert.throws(() => buildSuite({ ...candidates, [names[3]]: control }, harness));
  }
});

test("real HR source composition stays enclosed by the single rollback", async () => {
  assert.equal(await main(["--check"]), 0);
});

test("runner rejects hosted URLs, linked targets and unknown flags before any CLI work", async () => {
  for (const args of [[], ["--linked"], ["--db-url", "postgresql://synthetic.invalid"],
    ["--run-local", "--linked"], ["--run-local", "--db-url", "synthetic"],
    ["--check", "--run-local"], ["--unknown"]]) {
    await assert.rejects(main(args), /hosted\/linked targets are forbidden/);
  }
});
