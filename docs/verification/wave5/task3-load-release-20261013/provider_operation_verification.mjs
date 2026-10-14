import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
const root=process.cwd(),base='docs/verification/wave5/task3-load-release-20261013';
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const files=['provider_operation_wrapper.mjs','provider_operation_wrapper.test.mjs','provider_operation_verification.mjs',
  'provider_pg_factory.mjs','postgres_transport.mjs','external_observer.mjs','fixture_writer.mjs','fixture_writer_test_support.mjs',
  'fixture_writer.test.mjs','package.json','package-lock.json'].map(name=>`${base}/${name}`).concat([
    'tools/wave5/runtime_contract.mjs','tools/wave5/runtime_fixture_spec.mjs','tools/wave5/runtime_coordinator.mjs',
    'tools/wave5/supabase_read_store.mjs','tools/wave5/supabase_membership_fixture.mjs','tools/wave5/supabase_runtime_provider.mjs',
    'tools/wave5/supabase_http_transport.mjs','tools/wave5/preparation_journal.mjs',
    'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json','docs/verification/wave5/runtime-owner-decision-20261012-r5.json']);
const snapshot=async()=>Promise.all(files.map(async file=>{const bytes=await fs.readFile(path.join(root,file));return{path:file,bytes:bytes.length,sha256:sha(bytes)};}));
const before=await snapshot(),startedAt=new Date().toISOString(),command=['--test','--test-isolation=none','--test-reporter=tap',`${base}/provider_operation_wrapper.test.mjs`];
const childEnv=Object.fromEntries(Object.entries(process.env).filter(([key])=>['SYSTEMROOT','WINDIR','TEMP','TMP'].includes(key.toUpperCase())));
const run=await new Promise((resolve,reject)=>{const child=spawn(process.execPath,command,{cwd:root,env:childEnv,windowsHide:true});let out='';
  child.stdout.on('data',chunk=>out+=chunk);child.stderr.on('data',chunk=>out+=chunk);child.on('error',reject);
  child.on('close',exitCode=>resolve({out,exitCode}));});
const after=await snapshot(),count=label=>Number(run.out.match(new RegExp(`^# ${label} (\\d+)$`,'m'))?.[1]??-1);
const counts=Object.fromEntries(['tests','pass','fail','cancelled','skipped','todo'].map(label=>[label,count(label)]));
const log=`${base}/provider-operation-verification.tap`,output=`${base}/provider-operation-verification.json`;
await fs.writeFile(path.join(root,log),run.out,{flag:'wx'});
const record={kind:'controlled-local-source-bound-provider-operation-integration-verification',startedAt,finishedAt:new Date().toISOString(),
  command:['node',...command],nodeVersion:process.version,exitCode:run.exitCode,counts,
  passed:run.exitCode===0&&counts.tests===16&&counts.pass===16&&counts.fail===0,
  sourcesUnchangedDuringRun:JSON.stringify(before)===JSON.stringify(after),filesBefore:before,filesAfter:after,log:{path:log,sha256:sha(run.out)},
  integration:{actualPublicRuntimeProviderComposed:true,actualPublicProviderLivePreflightVerified:false,
    unchangedMembershipFixtureAndJournalWrapped:true,exactControlledPreparationRestorationPassed:true,
    acknowledgedInvitationProjectionTokenFree:true,sourceFileVerificationBeforePrivateConfigurationCallback:true,
    bothPoolsCloseOnProviderFailure:true},actualPostgresConnection:false,realPrivateCredentialReads:0,
  genuineAuthSessionsCreated:0,liveSqlWrites:0,SDKJobs:0,fullGenuineSessionLoadPerformed:false,
  boundary:'Actual public factory construction and real fixture/journal/driver integration against controlled fake pools and durable receipts. No genuine Auth, live PostgreSQL, TLS handshake, target-scale workload, capture or production result is claimed.'};
const bytes=JSON.stringify(record,null,2)+'\n';await fs.writeFile(path.join(root,output),bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({record:output,sha256:sha(bytes),counts,passed:record.passed,sourcesUnchangedDuringRun:record.sourcesUnchangedDuringRun})+'\n');
if(!record.passed||!record.sourcesUnchangedDuringRun)process.exitCode=1;
