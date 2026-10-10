import {readFile,writeFile,open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {auditGoldenInputs} from './golden_review_inputs_20261010_r2.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/golden-review-';
const snapshot=path.join(root,'build/w5goldens20261010/r1');
const stage=process.argv[2];
const attempt=process.argv[3]??'';
if(attempt&&!/^[a-z][a-z0-9]{1,20}$/.test(attempt))throw Error('ATTEMPT_INVALID');
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe';
const flutter='C:/src/flutter/bin/cache/flutter_tools.snapshot';
const sha=b=>createHash('sha256').update(b).digest('hex');
const definitions={
  pubget:{cwd:snapshot,args:[flutter,'--suppress-analytics','pub','get','--offline','--enforce-lockfile']},
  analyzer:{cwd:snapshot,args:['analyze','apps/jentra_desktop/lib','apps/jentra_desktop/test','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system']},
  controlAll:{cwd:path.join(snapshot,'apps/jentra_desktop'),args:[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded']},
  candidateAll:{cwd:path.join(snapshot,'apps/jentra_desktop'),args:[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded']},
  processDomain:{cwd:path.join(snapshot,'packages/jentra_domain'),args:['test','--reporter=expanded','test/analytics/process_metrics_test.dart','test/analytics/process_filter_contract_test.dart']},
  platformAll:{cwd:path.join(snapshot,'packages/jentra_platform'),args:[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded']},
  build:{cwd:path.join(snapshot,'apps/jentra_desktop'),args:[flutter,'--suppress-analytics','build','windows','--release','--no-pub','--target=lib/main.dart','--dart-define=JENTRA_ENVIRONMENT=preview']},
};
if(!definitions[stage])throw Error('STAGE_INVALID');
await readFile(path.join(root,'docs/verification/wave5/golden-review-source-20261010-r2.json'));
const def=definitions[stage],stem=base+stage+'-20261010-r2'+(attempt?'-'+attempt:'');
const before=await auditGoldenInputs(stage);
const runnerPath='scripts/wave5/run_golden_review_20261010_r2.mjs';
const helperPath='scripts/wave5/golden_review_inputs_20261010_r2.mjs';
const runnerStart=sha(await readFile(path.join(root,runnerPath)));
const helperStart=sha(await readFile(path.join(root,helperPath)));
const comparisonPath='docs/verification/wave5/continuation-goldens-comparison-20261009-r13.json';
const comparisonBytes=stage==='controlAll'?await readFile(path.join(root,comparisonPath)):null;
const log=await open(path.join(root,stem+'.log'),'wx');
const startedAt=new Date().toISOString();
const env={...process.env};
for(const n of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR'])delete env[n];
let bytes=0;
const child=spawn(sdk,def.args,{cwd:def.cwd,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
let chain=Promise.resolve();
for(const stream of [child.stdout,child.stderr])stream.on('data',b=>{bytes+=b.length;chain=chain.then(()=>log.write(b));});
const exitCode=await new Promise(resolve=>{child.on('error',()=>resolve(127));child.on('exit',c=>resolve(c??1));});
await chain;await log.close();
const rawBytes=await readFile(path.join(root,stem+'.log')),raw=rawBytes.toString('utf8');
const parsed=parseTestLog(raw);
const counts=parsed?{passed:parsed.passedTests,failed:parsed.failedTests,skipped:parsed.skippedTests}:null;
let after=null,integrityError=null;
try{
  after=await auditGoldenInputs(stage);
  for(const key of ['sourceManifest','candidateManifest','currentInputsSha256','snapshotInputsSha256','selectedSources','overlays','toolchain']){
    if(JSON.stringify(before[key])!==JSON.stringify(after[key]))throw Error('DECLARED_INPUTS_CHANGED_DURING_STAGE:'+key);
  }
  if(runnerStart!==sha(await readFile(path.join(root,runnerPath)))||helperStart!==sha(await readFile(path.join(root,helperPath))))throw Error('RUNNER_CHANGED_DURING_STAGE');
  if(stage==='controlAll'){
    if(sha(comparisonBytes)!==sha(await readFile(path.join(root,comparisonPath))))throw Error('CONTROL_CLASSIFICATION_CHANGED_DURING_STAGE');
    const comparison=JSON.parse(comparisonBytes),normal=n=>n.replaceAll('\\','/').slice(n.replaceAll('\\','/').indexOf('/test/')+6);
    const pairs=rows=>rows.map(r=>normal(r.name)+'|'+r.golden).sort();
    if(exitCode!==1||parsed?.passedTests!==1921||parsed.failedTests!==83||parsed.skippedTests!==0||parsed.failures.length!==83||
      parsed.failures.some(f=>f.kind!=='golden-comparison')||JSON.stringify(pairs(parsed.failures))!==JSON.stringify(pairs(comparison.cases)))throw Error('EXACT83_APPROVED_CONTROL_FAILURES_REQUIRED');
  }
}catch(e){integrityError=e.message;}
const result={stage,startedAt,finishedAt:new Date().toISOString(),workingDirectory:def.cwd,executable:sdk,args:def.args,log:stem+'.log',
  logSha256:sha(rawBytes),logBytes:bytes,exitCode,counts,inputAuditBefore:before,inputAuditAfter:after,integrityError,
  runner:{path:runnerPath,sha256:runnerStart},inputAuditor:{path:helperPath,sha256:helperStart},
  expectedControlComparison:comparisonBytes?{path:comparisonPath,sha256:sha(comparisonBytes)}:null,
  boundary:'Serialized exact-source r2 checks in the guarded reused r1 warm tree. Full control uses preserved approved images and requires the exact 83 diagnosed failures. CandidateAll uses declared overlays. No native launch, authenticated acceptance or owner decision.'};
await writeFile(path.join(root,stem+'.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({stage,exitCode,counts,integrityError,sourceStable:!!after,log:result.log}));
if(exitCode!==0||integrityError)console.log(raw.slice(-2500));
process.exitCode=integrityError?1:exitCode;
