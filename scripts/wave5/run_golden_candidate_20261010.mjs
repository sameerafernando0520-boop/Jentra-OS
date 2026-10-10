import {readFile,writeFile,open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {auditGoldenInputs} from './golden_review_inputs_20261010.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/golden-review-';
const snapshot=path.join(root,'build/w5goldens20261010/r1');
const stage=process.argv[2];
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe';
const flutter='C:/src/flutter/bin/cache/flutter_tools.snapshot';
const sha=b=>createHash('sha256').update(b).digest('hex');
const definitions={
  analyzer:{cwd:snapshot,args:['analyze','apps/jentra_desktop/lib','apps/jentra_desktop/test','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system']},
  candidateGoldens:{cwd:path.join(snapshot,'apps/jentra_desktop'),args:[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded']},
  processDomain:{cwd:path.join(snapshot,'packages/jentra_domain'),args:['test','--reporter=expanded','test/analytics/process_metrics_test.dart','test/analytics/process_filter_contract_test.dart']},
  platformAll:{cwd:path.join(snapshot,'packages/jentra_platform'),args:[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded']},
  build:{cwd:path.join(snapshot,'apps/jentra_desktop'),args:[flutter,'--suppress-analytics','build','windows','--release','--no-pub','--target=lib/main.dart','--dart-define=JENTRA_ENVIRONMENT=preview']},
};
if(!definitions[stage])throw Error('STAGE_INVALID');
const def=definitions[stage],stem=base+stage+'-20261010-r1';
let expectedNames=[];
if(stage==='candidateGoldens'){
  const c=JSON.parse(await readFile(path.join(root,'docs/verification/wave5/golden-review-candidate-20261010-r1.json'),'utf8'));
  const split=c.cases.map(r=>{const m=r.test.match(/^(.+\.dart): (.+)$/);if(!m)throw Error('TEST_IDENTITY_INVALID');return{file:'test/'+m[1],name:m[2],identity:r.test};});
  const regex=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  def.args.push('--name=^(?:'+[...new Set(split.map(r=>r.name))].map(regex).join('|')+')$',...[...new Set(split.map(r=>r.file))].sort());
  expectedNames=split.map(r=>r.identity).sort();
  if(expectedNames.length!==83||new Set(expectedNames).size!==83)throw Error('EXACT83_TESTS_REQUIRED');
}
const before=await auditGoldenInputs(stage);
const runnerPath='scripts/wave5/run_golden_candidate_20261010.mjs';
const runnerStart=sha(await readFile(path.join(root,runnerPath)));
const helperPath='scripts/wave5/golden_review_inputs_20261010.mjs';
const helperStart=sha(await readFile(path.join(root,helperPath)));
const log=await open(path.join(root,stem+'.log'),'wx');
const startedAt=new Date().toISOString(),env={...process.env};
for(const n of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR'])delete env[n];
const child=spawn(sdk,def.args,{cwd:def.cwd,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
let chain=Promise.resolve();
for(const stream of [child.stdout,child.stderr])stream.on('data',b=>{chain=chain.then(()=>log.write(b));});
const exitCode=await new Promise(resolve=>{child.on('error',()=>resolve(127));child.on('exit',c=>resolve(c??1));});
await chain;await log.close();
const raw=await readFile(path.join(root,stem+'.log'));
const parsed=parseTestLog(raw.toString('utf8'));
let after=null,integrityError=null;
try{
  after=await auditGoldenInputs(stage);
  const stableKeys=['sourceManifest','candidateManifest','currentInputsSha256','snapshotInputsSha256','selectedSources','overlays'];
  for(const key of stableKeys)if(JSON.stringify(before[key])!==JSON.stringify(after[key]))throw Error('DECLARED_INPUTS_CHANGED_DURING_STAGE:'+key);
  if(JSON.stringify(before.toolchain)!==JSON.stringify(after.toolchain))throw Error('TOOLCHAIN_CHANGED_DURING_STAGE');
  if(runnerStart!==sha(await readFile(path.join(root,runnerPath)))||helperStart!==sha(await readFile(path.join(root,helperPath))))throw Error('RUNNER_CHANGED_DURING_STAGE');
  if(stage==='candidateGoldens'){
    const entries=[...raw.toString('utf8').replace(/\r/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\/test\/(.+\.dart): (.+))$/gm)]
      .filter(m=>!m[3].startsWith('(')&&!m[3].endsWith('[E]')).map(m=>m[2]+': '+m[3]).filter(n=>expectedNames.includes(n)).sort();
    if(parsed?.passedTests!==83||parsed.failedTests!==0||parsed.skippedTests!==0||JSON.stringify(entries)!==JSON.stringify(expectedNames))throw Error('EXACT83_CANDIDATE_EXECUTIONS_NOT_GREEN');
  }
}catch(e){integrityError=e.message;}
const result={stage,startedAt,finishedAt:new Date().toISOString(),workingDirectory:def.cwd,executable:sdk,args:def.args,log:stem+'.log',logSha256:sha(raw),
  exitCode,counts:parsed?{passed:parsed.passedTests,failed:parsed.failedTests,skipped:parsed.skippedTests}:null,
  expectedCaseIdentities:expectedNames,inputAuditBefore:before,inputAuditAfter:after,integrityError,
  runner:{path:runnerPath,sha256:runnerStart},inputAuditor:{path:helperPath,sha256:helperStart},
  boundary:'Strict candidate checks in a frozen copy with exactly83 declared image overlays. Full current approved-image control and focused candidate image gate remain separate. No owner/native/runtime acceptance.'};
await writeFile(path.join(root,stem+'.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({stage,exitCode,counts:result.counts,integrityError,sourceStable:!!after,log:result.log}));
if(exitCode!==0||integrityError)console.log(raw.toString('utf8').slice(-2500));
process.exitCode=exitCode===0&&!integrityError?0:1;
