// Candidate-only local runner. Never resolves a linked project or database URL.
import { readFile, mkdtemp, writeFile, unlink, rmdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const root = fileURLToPath(new URL("../../", import.meta.url));
const include = /^\\ir \.\.\/20261120090000_lk_statutory_payroll\.sql[\t ]*\r?$/m;
const casesMarker = /^-- LK_STATUTORY_CASES[\t ]*\r?$/m;

export function buildSuite(candidate, harness, cases) {
  if (!/^begin;/m.test(harness) || !/rollback;\s*$/i.test(harness)) {
    throw new Error("Candidate harness must wrap all work in a rollback transaction.");
  }
  if (harness.split(include).length !== 2 || harness.split(casesMarker).length !== 2
      || /^\s*(?:commit|rollback)\s*;/im.test(candidate)) {
    throw new Error("Unexpected candidate include, case marker or transaction control.");
  }
  const parsed = JSON.parse(cases);
  if (!Array.isArray(parsed.cases) || parsed.cases.length === 0 || cases.includes("$lk$")) {
    throw new Error("The shared statutory cases are missing or unsafe to inline.");
  }
  const combined = harness
    .replace(include, () => `-- Inlined candidate; no mounted-path dependency.\n${candidate}`)
    .replace(casesMarker, () => `create temporary table lk_doc as select $lk$${JSON.stringify(parsed)}$lk$::jsonb as body;`);
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
  const staged = await mkdtemp(join(testsDir, "lk-statutory-payroll-candidate-"));
  const output = join(staged, "lk_statutory_payroll_test.sql");
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
  const [candidate, harness, cases] = await Promise.all([
    readFile(new URL("20261120090000_lk_statutory_payroll.sql", import.meta.url), "utf8"),
    readFile(new URL("tests/lk_statutory_payroll_test.sql", import.meta.url), "utf8"),
    readFile(join(root, "packages", "jentra_domain", "test", "fixtures", "lk_statutory_payroll_cases.json"), "utf8"),
  ]);
  const suite = buildSuite(candidate, harness, cases);
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
