// Self-contained rollback suite, deliberately refusing all hosted targets.
import {readFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {stageAndRun} from "./run-employee-push-test.mjs";

const names=["20261023090000_employee_push.sql","20261025090000_employee_self_service.sql","20261025100000_employee_cases_documents_notifications.sql"];
export function buildSuite(candidates,harness) {
  if(!/^begin;/m.test(harness)||!/rollback;\s*$/i.test(harness))throw Error("Rollback harness required.");
  let result=harness;
  for(const name of names) {
    const include=`\\ir ../${name}`;
    const source=candidates[name];
    if(typeof source!=="string"||result.split(include).length!==2||/^\s*(commit|rollback)\s*;/im.test(source))throw Error("Candidate/include mismatch.");
    result=result.replace(include,()=>`-- Inlined ${name}; isolated rollback only.\n${source}`);
  }
  if(/^\\(?:i|ir|include|include_relative)\s/m.test(result))throw Error("Unresolved include.");
  return result;
}
export async function main(args) {
  if(args.length!==1||!["--check","--run-local"].includes(args[0]))throw Error("Use --check or --run-local only.");
  const candidates=Object.fromEntries(await Promise.all(names.map(async n=>[n,await readFile(new URL(n,import.meta.url),"utf8")])));
  const suite=buildSuite(candidates,await readFile(new URL("tests/employee_cases_documents_test.sql",import.meta.url),"utf8"));
  if(args[0]==="--check") {console.log("Cases/documents suite is self-contained; PostgreSQL has not run.");return 0;}
  const root=fileURLToPath(new URL("../../",import.meta.url));
  return stageAndRun({suite,testsDir:join(root,"supabase","candidates"),cwd:root});
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2)).then(code=>{process.exitCode=code;}).catch(()=>{
  console.error("Cases/documents candidate suite could not complete. Check local isolated stack and inputs.");process.exitCode=1;
});
