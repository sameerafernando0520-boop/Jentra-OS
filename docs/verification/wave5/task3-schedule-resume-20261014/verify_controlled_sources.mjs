import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {SOURCE,PRESERVED,READ_SQL,EXPIRES} from '../../../../tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const folder='docs/verification/wave5/task3-schedule-resume-20261014/';
const tests=folder+'resume_worker_schedules.test.mjs';
const revision=process.argv[2];if(!['a1','a2','a3'].includes(revision))throw Error('FIXED_CONTROLLED_REVISION_REQUIRED');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
async function bind(file){const b=await fs.readFile(path.join(root,file));return {path:file,sha256:sha(b),bytes:b.length};}
async function write(file,value){const bytes=Buffer.from(typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
 await fs.writeFile(path.join(root,file),bytes,{flag:'wx'});return {path:file,sha256:sha(bytes),bytes:bytes.length};}
const sources=await Promise.all([SOURCE,tests,folder+'verify_controlled_sources.mjs',...PRESERVED.map(r=>r.path)].map(bind));
const startedAt=new Date().toISOString();
if(revision==='a1'){
 await write(folder+'helper-before-durability-fix.mjs',await fs.readFile(path.join(root,SOURCE),'utf8'));
 await write(folder+'test-before-durability-fix.mjs',await fs.readFile(path.join(root,tests),'utf8'));
}
const command=[process.execPath,'--test','--test-isolation=none','--test-reporter=tap','--test-timeout=5000',tests];
const run=spawnSync(command[0],command.slice(1),{cwd:root,encoding:'utf8',timeout:30000,maxBuffer:1048576,windowsHide:true});
const counts={};for(const name of ['tests','pass','fail','cancelled','skipped','todo'])counts[name]=Number(new RegExp(`^# ${name} (\\d+)$`,'m').exec(run.stdout??'')?.[1]??NaN);
const identities=[...(run.stdout??'').matchAll(/^(ok|not ok) (\d+) - (.*)$/gm)].map(m=>({status:m[1],index:Number(m[2]),name:m[3]}));
const log=await write(folder+'controlled-verification-'+revision+'.tap',(run.stdout??'')+(run.stderr??''));
const syntax=spawnSync(process.execPath,['--check',SOURCE],{cwd:root,encoding:'utf8',timeout:10000,windowsHide:true});
const validate=spawnSync(process.execPath,[SOURCE,'--validate'],{cwd:root,encoding:'utf8',timeout:30000,windowsHide:true});
const expiredExecute=spawnSync(process.execPath,[SOURCE,'--execute','a'.repeat(64)],{cwd:root,encoding:'utf8',timeout:10000,windowsHide:true,input:'NOT_A_PRIVATE_CONFIG'});
const changed=[];for(const binding of sources)if((await bind(binding.path)).sha256!==binding.sha256)changed.push(binding.path);
const passed=run.status===0&&counts.tests===identities.length&&counts.fail===0&&counts.cancelled===0&&counts.skipped===0
 &&syntax.status===0&&validate.status===0&&changed.length===0&&Date.now()>=Date.parse(EXPIRES)
 &&expiredExecute.status===1&&expiredExecute.stderr.includes('ORIGINAL_SCHEDULE_AUTHORITY_EXPIRED');
const evidence=await write(folder+'controlled-verification-'+revision+'.json',{kind:'source-only-schedule-resume-controlled-verification',
 startedAt,finishedAt:new Date().toISOString(),passed,command,nodeVersion:process.version,exitCode:run.status,error:run.error?.message??null,
 counts,testIdentities:identities,log,syntax:{exitCode:syntax.status,stdout:syntax.stdout,stderr:syntax.stderr},
 offlineValidation:{exitCode:validate.status,stdout:validate.stdout,stderr:validate.stderr,privateInputsRead:false,networkRequests:0},
 expiredExecute:{exitCode:expiredExecute.status,stdout:expiredExecute.stdout,stderr:expiredExecute.stderr,input:'Only a deliberately malformed public sentinel was supplied; expiry must reject before JSON parsing or any stdin consumption.',privateInputParsed:false,networkRequests:0},
 sourceBindingsBefore:sources,sourcesUnchangedDuringRun:changed.length===0,changedFiles:changed,readSqlSha256:sha(READ_SQL),
 originalExpiry:EXPIRES,networkRequests:0,privateInputsRead:0,liveSqlExecuted:0,SDKJobs:0,oldSourcesChanged:0});
console.log(JSON.stringify({passed,counts,evidence,log,changedFiles:changed}));
if(!passed)process.exitCode=1;
