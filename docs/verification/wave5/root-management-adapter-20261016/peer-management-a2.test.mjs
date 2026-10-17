// Source and injected public-interface controls only. No real adapter/private/network operation.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {buildManagementCandidate,TEMPLATE} from '../../../../tools/wave5/prepare_management_private_adapter_20261016_r5_a2.mjs';
import {healthPlanBinding,PLAN as HEALTH_PLAN,main as healthMain} from '../../../../tools/wave5/run_worker_v7_health_20261015_r5.mjs';
import {schedulePlanBinding,PLAN as SCHEDULE_PLAN,main as scheduleMain} from '../../../../tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';
import {main as renewalMain} from '../../../../tools/wave5/renew_runtime_authority_20261015_r5_a1.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const read=file=>fs.readFile(path.join(root,file));
const sha=x=>createHash('sha256').update(x).digest('hex');
const [bytes,template,locksBytes,recordBytes]=await Promise.all([
 read('scripts/wave5/run_private_health_scheduler_20261016_r5_a2.candidate.ps1'),read(TEMPLATE.path),
 read('docs/verification/wave5/root-export-adapter-20261016/public-read-holds-a2.ps1'),
 read('docs/verification/wave5/root-management-adapter-20261016/source-candidate-a2.json')]);
const text=bytes.toString('utf8'),locks=locksBytes.toString('utf8'),record=JSON.parse(recordBytes);
const hashes=Object.fromEntries(['Renewal','Health','Scheduler','OwnerRefresh'].map((key,i)=>[key,record.sourceBindings[i].sha256]));
const reviewHash='e'.repeat(64),planHash='d'.repeat(64);
const publicResult={passed:true,networkCalls:0,privateInputsRead:false,planSha256:planHash,finalReviewSha256:reviewHash};
const poison=()=>{throw Error('CONTROLLED_PRIVATE_OR_NETWORK_CAPABILITY_MUST_NOT_BE_USED');};
const poisonStdin={[Symbol.asyncIterator]:poison};

test('frozen management candidate, template and helper hashes are exact',()=>{
 assert.equal(sha(bytes),'7d3559d196932587ea76eafbd527bd6943362ad5c321b5c58873aa822343cce7');
 assert.equal(sha(template),TEMPLATE.sha256);assert.equal(sha(locksBytes),'f8b82f70c0cce59208ebe670459e5cc2dbffede6496a238524a7b8f277f44388');
 assert.ok(text.includes(locks));assert.ok(!/__[A-Z_]+__/.test(text));
});
test('pure builder reproduces the exact candidate and rejects a changed template',()=>{
 assert.equal(buildManagementCandidate(template,locks,hashes),text);
 assert.throws(()=>buildManagementCandidate(Buffer.concat([template,Buffer.from('\n')]),locks,hashes),/EXACT_PRESERVED_MANAGEMENT_TEMPLATE_REQUIRED/);
 assert.throws(()=>buildManagementCandidate(template,locks,{...hashes,Extra:'f'.repeat(64)}),/EXACT_MANAGEMENT_SOURCE_HASHES_REQUIRED/);
});
test('all three child files and the A10 refresh binding match actual frozen bytes',async()=>{
 assert.equal(record.sourceBindings.length,4);
 for(const row of record.sourceBindings){assert.equal(sha(await read(row.path)),row.sha256);assert.ok(text.includes(row.sha256));}
});
test('review and plan are held before every parse and inventory derivation',()=>{
 const reviewHold=text.indexOf('Add-TaskReviewedReadHold $taskRoot $taskSelected.review $FinalReviewSha256');
 const reviewRead=text.indexOf('$taskReview = Get-Content'),planHold=text.indexOf('Add-TaskReviewedReadHold $taskRoot $taskSelected.plan $taskReview.generatedPlan.sha256');
 const planAssert=text.indexOf('$taskPlanFile = Assert-TaskFile'),planRead=text.indexOf('$taskPlan = Get-Content');
 const inventory=text.indexOf('foreach ($taskBinding in @($taskPlan.sourceBindings) + @($taskPlan.publicBindings))');
 assert.ok(reviewHold>0&&reviewHold<reviewRead&&reviewRead<planHold&&planHold<planAssert&&planAssert<planRead&&planRead<inventory);
});
test('complete inventories, metadata, exact source/plan/review and self are held before preflight',()=>{
 const inventory=text.indexOf('foreach ($taskBinding in @($taskPlan.sourceBindings) + @($taskPlan.publicBindings))');
 const publicStart=text.indexOf("$taskPhase = 'public-preflight'");assert.ok(inventory>0&&inventory<publicStart);
 const block=text.slice(inventory,publicStart);for(const expected of ['Add-TaskReviewedReadHold $taskRoot $taskSelected.source $taskSelected.sha256',
  'Add-TaskReviewedReadHold $taskRoot $taskSelected.plan $taskReview.generatedPlan.sha256','Add-TaskReviewedReadHold $taskRoot $taskSelected.review $FinalReviewSha256',
  'Add-TaskReviewedReadHold $taskRoot $taskMetadataPath $taskPlan.controlBindings.metadata.sha256','Add-TaskReviewedReadHold $taskRoot $taskSelfRelative $taskReview.privateAdapter.afterSha256'])assert.ok(block.includes(expected),expected);
});
test('public preflight and Validate exit precede SID/private metadata and DPAPI use',()=>{
 const preflight=text.indexOf("$taskChild = New-TaskProcess '--preflight'"),validate=text.indexOf("if ($Action -eq 'Validate')"),sid=text.indexOf('[Security.Principal.WindowsIdentity]::GetCurrent()'),dpapi=text.indexOf('$taskSecret = ConvertTo-SecureString');
 assert.ok(preflight>0&&preflight<validate&&validate<sid&&sid<dpapi);
 const block=text.slice(preflight,validate);for(const value of ['$taskChild.StandardInput.Close()','$taskChild.WaitForExit(60000)',
  '$taskProof.planSha256 -cne $taskReview.generatedPlan.sha256','$taskProof.finalReviewSha256 -cne $FinalReviewSha256'])assert.ok(block.includes(value),value);
});
test('fresh A10 metadata is bound to exact project, bundle, helper, SID, private paths and ACL',()=>{
 const block=text.slice(text.indexOf("$taskPhase = 'private-metadata-validation'"),text.indexOf("$taskPhase = 'private-handoff'"));
 for(const value of ['$taskMetadata.projectId -cne $taskProject','$taskMetadata.runtimeBundleSha256 -cne $taskBundle','$taskMetadata.ownerSid -cne $taskSid.Value',
  hashes.OwnerRefresh,"$taskMetadata.metadataFilename -cne 'metadata-renewed-a10.json'",'$taskMetadata.containsPlaintextCredential -ne $false',
  '$taskExpires -lt $taskEnd','$taskExpires -le $taskCreated','Assert-TaskPrivateAcl $taskFolder $taskSid $true','Assert-TaskPrivateAcl $taskSealed $taskSid $false',
  'Assert-TaskPrivateAcl $taskPrivateMetadata $taskSid $false','PRIVATE_METADATA_CHANGED'])assert.ok(block.includes(value),value);
});
test('last checks use held source, metadata, review, plan and reviewed deadline before DPAPI',()=>{
 const block=text.slice(text.indexOf("throw 'PRIVATE_METADATA_CHANGED'"),text.indexOf('$taskSecret = ConvertTo-SecureString'));
 for(const value of ['Assert-TaskFile $taskMetadataPath','Assert-TaskFile $taskSelected.source','Assert-TaskFile $taskSelected.review','Assert-TaskFile $taskSelected.plan',
  '[DateTimeOffset]::UtcNow.AddSeconds(90) -ge $taskEnd'])assert.ok(block.includes(value),value);
 assert.ok(text.includes('($taskEnd - $taskStart).TotalMinutes -gt 120'));assert.ok(!text.includes('AddHours('));
});
test('private handoff contains only project, bundle and owner token and emits whitelisted public summaries',()=>{
 assert.ok(text.includes('$taskPlain = @{projectId=$taskProject;bundleSha256=$taskBundle;ownerToken=$taskPlain} | ConvertTo-Json -Compress'));
 assert.ok(!text.includes('runtime-seal.dpapi'));assert.ok(!text.includes('encryptionKey='));
 assert.ok(text.includes('$taskChild.StandardInput.WriteLine($taskPlain)'));assert.ok(text.includes('ZeroFreeBSTR($taskBstr)'));
 assert.ok(text.includes('$taskSecret.Dispose(); $taskSecret = $null'));
 assert.ok(!text.includes('$taskResult | ConvertTo-Json'));assert.ok(!text.includes('$taskOutput | Write-Output'));
 assert.ok(text.includes("'^[A-Z][A-Z0-9_]{3,100}$'"));assert.ok(text.includes('privateValuesPrinted=$false'));
});
test('execution has a reviewed deadline and all exceptional paths close child and held files',()=>{
 for(const value of ['$taskChild.WaitForExit([int]$taskWaitMs)','$taskChild.Kill($true)','$taskChild.WaitForExit(10000)',
  '} finally { Close-TaskReviewedReadHolds }',"$taskPlain = $null; $taskOutput = $null; $taskError = $null"])assert.ok(text.includes(value),value);
});
test('Health and Scheduler accept canonical generatedPlan and refuse conflicting legacy aliases',()=>{
 for(const [validate,plan]of [[healthPlanBinding,HEALTH_PLAN],[schedulePlanBinding,SCHEDULE_PLAN]]){
  const generatedPlan={path:plan,sha256:planHash};assert.deepEqual(validate({generatedPlan}),generatedPlan);
  assert.deepEqual(validate({generatedPlan,planBinding:{...generatedPlan}}),generatedPlan);
  assert.throws(()=>validate({generatedPlan,planBinding:{...generatedPlan,sha256:reviewHash}}));
 }
});
for(const [label,main]of [['Renewal',renewalMain],['Health',healthMain]])test(`${label} public --preflight returns the exact adapter proof without stdin or private/runtime ports`,async()=>{
 let output='',calls=0;const result=await main(['--preflight',reviewHash],{stdin:poisonStdin,stdout:{write:value=>{output+=value;}},
  preflight:async({finalReviewSha256})=>{calls++;assert.equal(finalReviewSha256,reviewHash);return {publicResult};},run:poison,transportFactory:poison});
 assert.equal(calls,1);assert.deepEqual(result,publicResult);assert.deepEqual(JSON.parse(output),publicResult);
});
test('Scheduler public --preflight returns the exact adapter proof without stdin or private/runtime ports',async()=>{
 let output='',calls=0;const result=await scheduleMain(['--preflight',reviewHash],{stdin:poisonStdin,stdout:{write:value=>{output+=value;}},
  publicGate:async(hash)=>{calls++;assert.equal(hash,reviewHash);return {planSha256:planHash};},run:poison,requestFactory:poison});
 assert.equal(calls,1);assert.deepEqual(result,publicResult);assert.deepEqual(JSON.parse(output),publicResult);
});
