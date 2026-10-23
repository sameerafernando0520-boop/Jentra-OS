import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rmdir, writeFile, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildSuite, stageAndRun, main } from "../../candidates/run-employee-push-test.mjs";

test("isolated harness inlines exact candidate inside its rollback and matches assertion count", async () => {
  const candidate = await readFile(new URL("../../candidates/20261023090000_employee_push.sql", import.meta.url), "utf8");
  const harness = await readFile(new URL("../../candidates/tests/employee_push_candidate_test.sql", import.meta.url), "utf8");
  const combined = buildSuite(candidate, harness);
  assert.ok(combined.indexOf("begin;") < combined.indexOf("create schema employee_push;"));
  assert.match(combined, /rollback;\s*$/);
  assert.doesNotMatch(combined, /^\\(?:i|ir)\s/m);
  const planned = Number(harness.match(/select plan\((\d+)\)/)[1]);
  const assertions = [...harness.matchAll(/^select (?:ok|is|throws_ok|lives_ok)\(/gm)].length;
  assert.equal(planned, 47);
  assert.equal(assertions, planned);
  assert.throws(() => buildSuite("commit;", harness));
  assert.throws(() => buildSuite(candidate, harness.replace("rollback;", "commit;")));
});

test("local runner mounts self-contained owned directory and preserves other files", async () => {
  const dir = await mkdtemp(join(tmpdir(), "employee-push-runner-test-"));
  const existing = join(dir, "keep.txt");
  await writeFile(existing, "unrelated");
  try {
    const result = await stageAndRun({ suite: "synthetic suite", testsDir: dir, cwd: "synthetic-root", invoke: async (cli, args, cwd) => {
      assert.equal(cli, "supabase");
      assert.deepEqual(args.slice(0, 3), ["test", "db", "--local"]);
      assert.equal(cwd, "synthetic-root");
      assert.ok(args[3].startsWith(join(dir, "employee-push-candidate-")));
      assert.equal(await readFile(join(args[3], "employee_push_candidate_test.sql"), "utf8"), "synthetic suite");
      return 7;
    } });
    assert.equal(result, 7);
    assert.deepEqual(await readdir(dir), ["keep.txt"]);
    assert.equal(await readFile(existing, "utf8"), "unrelated");
    await assert.rejects(stageAndRun({ suite: "synthetic suite", testsDir: dir, cwd: dir,
      invoke: async () => { throw new Error("mock startup failure"); } }));
    assert.deepEqual(await readdir(dir), ["keep.txt"]);
  } finally {
    await unlink(existing);
    await rmdir(dir);
  }
});

test("runner refuses hosted connection, linked target and unknown options before execution", async () => {
  for (const args of [[], ["--linked"], ["--db-url", "synthetic"], ["--run-local", "--linked"], ["--check", "--run-local"]]) {
    await assert.rejects(main(args), /hosted\/linked targets are forbidden/);
  }
});
