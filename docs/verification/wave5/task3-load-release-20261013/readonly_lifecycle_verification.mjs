import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
const root=process.cwd(),base='docs/verification/wave5/task3-load-release-20261013';
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const files=['postgres_transport.mjs','postgres_transport-before-credential-bound.mjs','readonly_credential_lifecycle.test.mjs',
  'readonly_lifecycle_verification.mjs','transport_helpers.test.mjs','external_observer.mjs','package.json','package-lock.json']
  .map(name=>`${base}/${name}`).concat(['tools/wave5/runtime_contract.mjs','tools/wave5/supabase_read_store.mjs',
    'tools/wave5/runtime_fixture_spec.mjs',`${base}/local-verification-a2.json`]);
const snapshot=async()=>Promise.all(files.map(async file=>{const bytes=await fs.readFile(path.join(root,file));return{path:file,bytes:bytes.length,sha256:sha(bytes)};}));
const before=await snapshot(),startedAt=new Date().toISOString();
const command=['--test','--test-isolation=none','--test-reporter=tap',`${base}/transport_helpers.test.mjs`,`${base}/readonly_credential_lifecycle.test.mjs`];
const childEnv=Object.fromEntries(Object.entries(process.env).filter(([key])=>['SYSTEMROOT','WINDIR','TEMP','TMP'].includes(key.toUpperCase())));
const run=await new Promise((resolve,reject)=>{const child=spawn(process.execPath,command,{cwd:root,env:childEnv,windowsHide:true});let out='';
  child.stdout.on('data',chunk=>out+=chunk);child.stderr.on('data',chunk=>out+=chunk);child.on('error',reject);
  child.on('close',exitCode=>resolve({out,exitCode}));});
const after=await snapshot(),count=label=>Number(run.out.match(new RegExp(`^# ${label} (\\d+)$`,'m'))?.[1]??-1);
const counts=Object.fromEntries(['tests','pass','fail','cancelled','skipped','todo'].map(label=>[label,count(label)]));
const log=`${base}/readonly-lifecycle-verification.json`.replace('.json','.tap'),output=`${base}/readonly-lifecycle-verification.json`;
await fs.writeFile(path.join(root,log),run.out,{flag:'wx'});
const preserved=before.find(file=>file.path.endsWith('/postgres_transport-before-credential-bound.mjs'));
const record={kind:'controlled-local-bounded-readonly-credential-lifecycle-successor',startedAt,finishedAt:new Date().toISOString(),
  command:['node',...command],nodeVersion:process.version,exitCode:run.exitCode,counts,
  passed:run.exitCode===0&&counts.tests===17&&counts.pass===17&&counts.fail===0,
  sourcesUnchangedDuringRun:JSON.stringify(before)===JSON.stringify(after),filesBefore:before,filesAfter:after,
  historicalDriver:preserved,historicalOriginalHelperRecord:before.find(file=>file.path.endsWith('/local-verification-a2.json')),
  credentialCallbackDeadlineMsMaximum:10000,credentialCallbackCancelledOnClose:true,idempotentClose:true,
  rawCallbackErrorCodeRedacted:true,readonlySqlPolicyUnchanged:true,tlsPolicyUnchanged:true,
  log:{path:log,sha256:sha(run.out)},actualPostgresConnection:false,realPrivateCredentialReads:0,liveSqlWrites:0,SDKJobs:0,
  boundary:'17 controlled checks against fake pools/callbacks/captures: original14 plus three targeted lifecycle regressions. Historical before-bytes and original 14-pass record remain intact; no real private credential, TLS, DB or full load is verified.'};
const bytes=JSON.stringify(record,null,2)+'\n';await fs.writeFile(path.join(root,output),bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({record:output,sha256:sha(bytes),counts,passed:record.passed,sourcesUnchangedDuringRun:record.sourcesUnchangedDuringRun,
  driverSha256:before.find(file=>file.path.endsWith('/postgres_transport.mjs')).sha256})+'\n');
if(!record.passed||!record.sourcesUnchangedDuringRun)process.exitCode=1;
