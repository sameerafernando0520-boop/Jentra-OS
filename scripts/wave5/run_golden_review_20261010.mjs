import {readFile,writeFile,open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/golden-review-';
const snapshot=path.join(root,'build/w5goldens20261010/r1');
const stage=process.argv[2];
const attempt=process.argv[3]??'';
if(attempt&&!/^[a-z][a-z0-9]{1,20}$/.test(attempt))throw Error('ATTEMPT_INVALID');
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe';
const flutter='C:/src/flutter/bin/cache/flutter_tools.snapshot';
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
await readFile(path.join(root,'docs/verification/wave5/golden-review-source-20261010-r1.json'));
const def=definitions[stage],stem=base+stage+'-20261010-r1'+(attempt?'-'+attempt:'');
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
const raw=await readFile(path.join(root,stem+'.log'),'utf8');
const summaries=[...raw.matchAll(/\+(\d+)(?: ~(\d+))?(?: -(\d+))?: (All tests passed!|Some tests failed\.)/g)];
const s=summaries.at(-1);
const counts=s?{passed:Number(s[1]),skipped:Number(s[2]??0),failed:Number(s[3]??0)}:null;
const result={stage,startedAt,finishedAt:new Date().toISOString(),workingDirectory:def.cwd,executable:sdk,args:def.args,log:stem+'.log',
  logSha256:createHash('sha256').update(raw).digest('hex'),logBytes:bytes,exitCode,counts,
  runner:{path:'scripts/wave5/run_golden_review_20261010.mjs',sha256:createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex')},
  boundary:'Serialized frozen-copy checks. Control uses preserved approved images; candidateAll uses only the declared83 baseline overlays. No native launch, authenticated acceptance or owner decision.'};
await writeFile(path.join(root,stem+'.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));
if(exitCode!==0)console.log(raw.slice(-2500));
process.exitCode=exitCode;
