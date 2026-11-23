// Candidate-only local runner. Never resolves a linked project or database URL.
import { readFile, mkdtemp, writeFile, unlink, rmdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const root = fileURLToPath(new URL("../../", import.meta.url));
const includeVat = /^\\ir \.\.\/20261121090000_lk_vat_workpaper\.sql[\t ]*\r?$/m;
const includeWht = /^\\ir \.\.\/20261121110000_lk_wht_schedule\.sql[\t ]*\r?$/m;

export function buildSuite(vat, wht, harness) {
  if (!/^begin;/m.test(harness) || !/rollback;\s*$/i.test(harness)) {
    throw new Error("Candidate harness must wrap all work in a rollback transaction.");
  }
  if (harness.split(includeVat).length !== 2 || harness.split(includeWht).length !== 2
      || [vat, wht].some(sql => /^\s*(?:commit|rollback)\s*;/im.test(sql))) {
    throw new Error("Unexpected candidate include or transaction control.");
  }
  const combined = harness
    .replace(includeVat, () => `-- Inlined VAT candidate; no mounted-path dependency.\n${vat}`)
    .replace(includeWht, () => `-- Inlined WHT candidate.\n${wht}`);
  if (/^\\(?:i|ir|include|include_relative)\s/m.test(combined)) {
    throw new Error("The staged suite must have no external includes.");
  }
  return combined;
}

function invokeLocal(cli, args, cwd) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(cli, args, { cwd, stdio: "inherit", shell: false, windowsHide: true });
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (signal) reject(new Error("The local candidate runner was interrupted."));
      else resolvePromise(code ?? 1);
    });
  });
}

export async function stageAndRun({ suite, testsDir, cwd, cli = "supabase", invoke = invokeLocal }) {
  const staged = await mkdtemp(join(testsDir, "lk-wht-schedule-candidate-"));
  const output = join(staged, "lk_wht_schedule_test.sql");
  try {
    await writeFile(output, suite, { encoding: "utf8", flag: "wx" });
    return await invoke(cli, ["test", "db", "--local", staged], cwd);
  } finally {
    // Never recursively delete; an unexpected extra file prevents rmdir.
    await unlink(output).catch(error => { if (error.code !== "ENOENT") throw error; });
    await rmdir(staged);
  }
}

export async function main(args) {
  if (args.length !== 1 || !["--check", "--run-local"].includes(args[0])) {
    throw new Error("Use exactly --check or --run-local; hosted/linked targets are forbidden.");
  }
  const [vat, wht, harness] = await Promise.all([
    readFile(new URL("20261121090000_lk_vat_workpaper.sql", import.meta.url), "utf8"),
    readFile(new URL("20261121110000_lk_wht_schedule.sql", import.meta.url), "utf8"),
    readFile(new URL("tests/lk_wht_schedule_test.sql", import.meta.url), "utf8"),
  ]);
  const suite = buildSuite(vat, wht, harness);
  if (args[0] === "--check") {
    console.log("Candidate harness is self-contained; PostgreSQL has not been executed.");
    return 0;
  }
  return stageAndRun({ suite, testsDir: join(root, "supabase", "candidates"), cwd: root });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(code => { process.exitCode = code; }).catch(() => {
    console.error("Candidate suite could not complete. Use an isolated local Supabase stack and check the runner inputs.");
    process.exitCode = 1;
  });
}
