import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
const root=process.cwd(), base='docs/verification/wave5/task3-load-release-20261013';
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const files=['provider_pg_factory.mjs','provider_pg_factory.test.mjs','verify_provider_router.mjs','postgres_transport.mjs','package-lock.json']
  .map(value=>`${base}/${value}`).concat(['tools/wave5/supabase_read_store.mjs','tools/wave5/supabase_membership_fixture.mjs','tools/wave5/supabase_runtime_provider.mjs']);
const snapshots=async()=>Promise.all(files.map(async file=>{const bytes=await fs.readFile(path.join(root,file));return{path:file,bytes:bytes.length,sha256:sha(bytes)};}));
const before=await snapshots(),startedAt=new Date().toISOString();
const command=['--test','--test-isolation=none','--test-reporter=tap',`${base}/provider_pg_factory.test.mjs`];
const childEnv=Object.fromEntries(Object.entries(process.env).filter(([key])=>['SYSTEMROOT','WINDIR','TEMP','TMP'].includes(key.toUpperCase())));
const run=await new Promise((resolve,reject)=>{const child=spawn(process.execPath,command,{cwd:root,env:childEnv,windowsHide:true});let out='';
  child.stdout.on('data',chunk=>out+=chunk);child.stderr.on('data',chunk=>out+=chunk);child.on('error',reject);
  child.on('close',exitCode=>resolve({out,exitCode}));});
const count=label=>Number(run.out.match(new RegExp(`^# ${label} (\\d+)$`,'m'))?.[1]??-1);
const after=await snapshots(),counts=Object.fromEntries(['tests','pass','fail','cancelled','skipped','todo'].map(label=>[label,count(label)]));
const log=`${base}/provider-router-verification.tap`,output=`${base}/provider-router-verification.json`;
await fs.writeFile(path.join(root,log),run.out,{flag:'wx'});
const record={kind:'controlled-local-provider-constructor-router-verification',startedAt,finishedAt:new Date().toISOString(),
  command:['node',...command],nodeVersion:process.version,exitCode:run.exitCode,counts,
  passed:run.exitCode===0&&counts.tests===6&&counts.pass===6&&counts.fail===0,
  sourcesUnchangedDuringRun:JSON.stringify(before)===JSON.stringify(after),filesBefore:before,filesAfter:after,
  log:{path:log,sha256:sha(run.out)},actualPostgresConnection:false,credentialReads:0,liveSqlWrites:0,SDKJobs:0,
  fixtureWriterImplemented:false,fullProviderTransportConfigured:false,
  boundary:'Constructor routing with controlled stub classes only. The required separately reviewed exact-SQL fixture driver and actual private configuration remain unsupplied.'};
const bytes=JSON.stringify(record,null,2)+'\n';await fs.writeFile(path.join(root,output),bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({record:output,sha256:sha(bytes),counts,passed:record.passed,sourcesUnchangedDuringRun:record.sourcesUnchangedDuringRun})+'\n');
if(!record.passed||!record.sourcesUnchangedDuringRun) process.exitCode=1;
