// Root invokes this prepared runner only after other heavy jobs finish.
// New serial evidence; original r2 concurrent evidence remains unchanged.
import {readFile,writeFile,open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {auditGoldenInputs} from './golden_review_inputs_20261010_r2.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
if (process.argv.length>3 || (process.argv[2] && process.argv[2]!=='processDomain')) throw Error('ONLY_PROCESS_DOMAIN_STAGE_ALLOWED');
const stage='processDomain',snapshot=path.join(root,'build/w5goldens20261010/r1');
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe';
const workingDirectory=path.join(snapshot,'packages/jentra_domain');
const files=['test/analytics/process_metrics_test.dart','test/analytics/process_filter_contract_test.dart'];
const args=['test','--concurrency=1','--reporter=expanded',...files];
const stem='docs/verification/wave5/golden-review-processDomain-20261010-r2-serial';
const sha=b=>createHash('sha256').update(b).digest('hex');
const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const before=await auditGoldenInputs(stage);
const sourceFixtureBindings=[],expectedCaseIdentities=[];
for (const [index,file] of files.entries()) {
  const bytes=await readFile(path.join(workingDirectory,file));
  const names=[...bytes.toString('utf8').matchAll(/\btest\(\s*'([^']+)'/g)].map(m=>m[1]);
  if (names.length!==(index===0?25:2) || new Set(names).size!==names.length) throw Error('EXACT_FOCUSED_FIXTURE_DECLARATIONS_REQUIRED');
  sourceFixtureBindings.push({path:'packages/jentra_domain/'+file,sha256:sha(bytes),declaredTests:names.length});
  expectedCaseIdentities.push(...names.map(name=>file+': '+name));
}
expectedCaseIdentities.sort();
if (expectedCaseIdentities.length!==27 || new Set(expectedCaseIdentities).size!==27) throw Error('EXACT27_UNIQUE_PROCESS_IDENTITIES_REQUIRED');
const runnerPath='scripts/wave5/run_golden_process_serial_20261010_r2.mjs';
const helperPath='scripts/wave5/golden_review_inputs_20261010_r2.mjs';
const runnerStart=sha(await readFile(path.join(root,runnerPath))),helperStart=sha(await readFile(path.join(root,helperPath)));
const log=await open(path.join(root,stem+'.log'),'wx');
const startedAt=new Date().toISOString(),env={...process.env};
for (const n of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR']) delete env[n];
const child=spawn(sdk,args,{cwd:workingDirectory,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
let chain=Promise.resolve();
for (const stream of [child.stdout,child.stderr]) stream.on('data',b=>{chain=chain.then(()=>log.write(b));});
const exitCode=await new Promise(resolve=>{child.on('error',()=>resolve(127));child.on('exit',c=>resolve(c??1));});
await chain;await log.close();
const raw=await readFile(path.join(root,stem+'.log')),text=raw.toString('utf8');
const parsed=parseTestLog(text);
let after=null,integrityError=null,executedCaseIdentities=[];
try {
  after=await auditGoldenInputs(stage);
  for (const key of ['sourceManifest','candidateManifest','currentInputsSha256','snapshotInputsSha256','selectedSources','overlays','toolchain']) {
    if (!eq(before[key],after[key])) throw Error('DECLARED_INPUTS_CHANGED_DURING_STAGE:'+key);
  }
  if (runnerStart!==sha(await readFile(path.join(root,runnerPath))) || helperStart!==sha(await readFile(path.join(root,helperPath)))) throw Error('RUNNER_CHANGED_DURING_STAGE');
  for (const fixture of sourceFixtureBindings) {
    if (sha(await readFile(path.join(root,fixture.path)))!==fixture.sha256 || sha(await readFile(path.join(snapshot,fixture.path)))!==fixture.sha256) throw Error('TEST_FIXTURE_CHANGED_DURING_STAGE');
  }
  const entries=[...text.replace(/\r/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)]
    .filter(m=>!m[2].startsWith('(')&&!m[2].endsWith('[E]'));
  executedCaseIdentities=entries.map(m=>{
    const actual=m[1].replaceAll('\\','/'),file=files.find(file=>actual===file||actual.endsWith('/'+file));
    if (!file) throw Error('UNDECLARED_PROCESS_TEST_FILE:'+actual);
    return file+': '+m[2];
  }).sort();
  if (exitCode!==0 || !parsed?.allTestsPassed || parsed.passedTests!==27 || parsed.failedTests!==0 || parsed.skippedTests!==0 ||
      new Set(executedCaseIdentities).size!==27 || !eq(executedCaseIdentities,expectedCaseIdentities)) throw Error('EXACT27_SERIAL_EXECUTIONS_NOT_GREEN');
} catch(e) { integrityError=e.message; }
const result={stage,startedAt,finishedAt:new Date().toISOString(),workingDirectory,executable:sdk,args,log:stem+'.log',logSha256:sha(raw),exitCode,
  counts:parsed?{passed:parsed.passedTests,failed:parsed.failedTests,skipped:parsed.skippedTests}:null,
  expectedCaseIdentities,executedCaseIdentities,sourceFixtureBindings,serialFileConcurrency:1,
  inputAuditBefore:before,inputAuditAfter:after,integrityError,runner:{path:runnerPath,sha256:runnerStart},inputAuditor:{path:helperPath,sha256:helperStart},
  boundary:'Serialized exact-source process calculation evidence: all25 metric and2 filter test identities must appear exactly once. 83 declared PNG overlays remain isolated fixture inputs; no native/runtime/delivery or owner acceptance.'};
await writeFile(path.join(root,stem+'.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({stage,exitCode,counts:result.counts,integrityError,sourceStable:!!after,executedUniqueTests:new Set(executedCaseIdentities).size,log:result.log}));
if (exitCode!==0||integrityError) console.log(text.slice(-2500));
process.exitCode=exitCode===0&&!integrityError?0:1;
