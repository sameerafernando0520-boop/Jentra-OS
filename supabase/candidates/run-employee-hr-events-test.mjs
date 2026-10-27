// Candidate-only local composition. Never resolves a linked project or DB URL.
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { stageAndRun } from "./run-employee-push-test.mjs";

const names = [
  "20261023090000_employee_push.sql",
  "20261025090000_employee_self_service.sql",
  "20261025100000_employee_cases_documents_notifications.sql",
  "20261027100000_employee_hr_event_producers.sql",
];

export function buildSuite(candidates, harness) {
  const controls = [...harness.matchAll(/^[\t ]*(begin|commit|rollback)\s*;/gim)]
    .map(match => match[1].toLowerCase());
  if (!/^(?:\s|--[^\r\n]*(?:\r?\n|$))*begin;[\t ]*(?:\r?\n|$)/i.test(harness)
    || !/rollback;\s*$/i.test(harness) || controls.join(",") !== "begin,rollback") {
    throw new Error("Rollback harness required; committed work is forbidden.");
  }
  let result = harness;
  for (const name of names) {
    const include = new RegExp(`^\\\\ir \\.\\.\\/${name.replaceAll(".", "\\.")}[\\t ]*\\r?$`, "m");
    const source = candidates[name];
    if (typeof source !== "string" || result.split(include).length !== 2
      || /^\s*(?:begin|commit|rollback)\s*;/im.test(source)) {
      throw new Error("Candidate/include mismatch or nested transaction control.");
    }
    result = result.replace(include, () => `-- Inlined ${name}; isolated rollback only.\n${source}`);
  }
  if (/^\s*\\(?:i|ir|include|include_relative)\s/m.test(result)) {
    throw new Error("Unresolved include.");
  }
  return result;
}

export async function main(args) {
  if (args.length !== 1 || !["--check", "--run-local"].includes(args[0])) {
    throw new Error("Use --check or --run-local only; hosted/linked targets are forbidden.");
  }
  const candidates = Object.fromEntries(await Promise.all(names.map(async name => [name,
    await readFile(new URL(name, import.meta.url), "utf8")])));
  const harness = await readFile(new URL("tests/employee_hr_event_producers_test.sql", import.meta.url), "utf8");
  const suite = buildSuite(candidates, harness);
  if (args[0] === "--check") {
    console.log("HR event producer suite is self-contained; PostgreSQL has not been executed.");
    return 0;
  }
  const root = fileURLToPath(new URL("../../", import.meta.url));
  return stageAndRun({ suite, testsDir: join(root, "supabase", "candidates"), cwd: root });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(code => { process.exitCode = code; }).catch(() => {
    console.error("HR event producer candidate suite could not complete. Check the isolated local stack and runner inputs.");
    process.exitCode = 1;
  });
}
