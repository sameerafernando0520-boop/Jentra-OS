// Evidence of controlled local tests only. No private input or real dispatch.
import fs from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import * as scheduler from '../../../../tools/wave5/resume_worker_schedules_20261017_r5_a2.mjs';
const base='docs/verification/wave5/task3-schedule-resume-20261017/';
const tests=base+'resume_worker_schedules_20261017_r5_a2.test.mjs';
const sha=x=>createHash('sha256').update(x).digest('hex');
const archived=await scheduler.validateDeployedArchive();
const paths=[...new Set([...scheduler.PRESERVED,...archived.bindings,archived.currentProductCandidate].map(x=>x.path).concat([
 scheduler.SOURCE,tests,'tools/wave5/run_worker_v7_health_20261015_r5.mjs','tools/wave5/probe_worker_v7_health_20261014_r5.mjs',
 'tools/wave5/finance_exports_20261016_r5_a7.mjs',base+'run_controlled_verification_a1.mjs']))].sort();
async function inputs(){return Promise.all(paths.map(async path=>{const b=await fs.readFile(path);return {path,sha256:sha(b),bytes:b.length};}));}
const before=await inputs(),startedAt=new Date().toISOString();
const syntax=[];
for(const file of [scheduler.SOURCE,tests]){const r=spawnSync(process.execPath,['--check',file],{encoding:'utf8',maxBuffer:1048576});syntax.push({path:file,exitCode:r.status,stdout:r.stdout,stderr:r.stderr});}
const result=spawnSync(process.execPath,['--experimental-test-isolation=none','--test','--test-concurrency=1','--test-reporter=tap',tests],{encoding:'utf8',maxBuffer:8388608});
const log=Buffer.from(result.stdout+result.stderr),tap=base+'controlled-verification-a1.tap';
await fs.writeFile(tap,log,{flag:'wx'});
const after=await inputs(),sourceStable=JSON.stringify(before)===JSON.stringify(after);
const value={kind:'controlled-conditional-scheduler-successor-verification',sourceOnly:true,startedAt,finishedAt:new Date().toISOString(),
 syntax,testFile:tests,exitCode:result.status,signal:result.signal,log:{path:tap,sha256:sha(log),bytes:log.length},
 before,after,sourceStable,counts:Object.fromEntries(['tests','pass','fail','skipped'].map(k=>[k,Number(log.toString().match(new RegExp('^# '+k+' (\\d+)$','m'))?.[1]??-1)])),
 privateInputsRead:false,networkCalls:0,actualSqlExecutions:0,actualOwnerDecisionCreated:false,actualResume:false};
await fs.writeFile(base+'controlled-verification-a1.json',JSON.stringify(value,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({exitCode:result.status,sourceStable,counts:value.counts,log:value.log,syntax:syntax.map(r=>({path:r.path,exitCode:r.exitCode}))}));
if(result.status!==0||!sourceStable||syntax.some(r=>r.exitCode!==0))process.exitCode=1;
