// Independent local source tests. No private adapter, private files, or network.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {buildCandidate,PREDECESSOR} from '../../../../tools/wave5/prepare_export_private_adapter_20261015_r5_a1.mjs';
import {preflightExportsOperation} from '../../../../tools/wave5/finance_exports_20261014_r5_a6.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const read=file=>fs.readFile(path.join(root,file));
const candidatePath='scripts/wave5/run_private_management_installer_20261015_r5_a1.candidate.ps1';
const sourcePath='tools/wave5/finance_exports_20261014_r5_a6.mjs';
const [before,after,childBytes]=await Promise.all([read(PREDECESSOR.path),read(candidatePath),read(sourcePath)]);
const original=before.toString('utf8'),candidate=after.toString('utf8'),child=childBytes.toString('utf8');
const firstDecrypt=candidate.indexOf('$taskSecret = ConvertTo-SecureString -String');
const finalGuardStart=candidate.indexOf("        if ($Mode -eq 'ExecuteExportsA6') {",candidate.indexOf("throw 'PRIVATE_METADATA_CHANGED'"));
const finalGuard=candidate.slice(finalGuardStart,firstDecrypt);

test('all three reviewed input hashes are exact',()=>{
 assert.equal(sha(before),'b01b6c20cb2819cb419fa10423bce37c0cba86b44ee7e2f5b9c0c9387d19be1f');
 assert.equal(sha(after),'a0b0babf2cf2806016e5f7d5293df0079e370edd2c95d35f7b2e955dfed5f891');
 assert.equal(sha(childBytes),'2b265ea5c5f4921923a1feafb8daf8b8d2538daa20a9cc97deb1bd6b51ccf559');
});
test('pure builder reproduces the candidate bytes without running it',()=>{
 const built=buildCandidate(before,sha(childBytes));assert.equal(built.text,candidate);assert.equal(built.privateLists,2);
 assert.deepEqual(built.addedModes,['ValidateExportsA6','ExecuteExportsA6']);
});
test('changed predecessor and malformed source hashes are refused',()=>{
 assert.throws(()=>buildCandidate(Buffer.concat([before,Buffer.from('\n')]),sha(childBytes)),/EXACT_PRESERVED_PRIVATE_ADAPTER_REQUIRED/);
 for(const value of ['',undefined,'A'.repeat(64),'f'.repeat(63),'x'.repeat(64)])
  assert.throws(()=>buildCandidate(before,value),/EXACT_A6_SOURCE_HASH_REQUIRED/);
});
test('all legacy parameter modes retain their order and only two export modes are added',()=>{
 const modes=text=>[...text.split('\n')[0].matchAll(/'([^']+)'/g)].map(x=>x[1]);
 const old=modes(original),current=modes(candidate);
 assert.deepEqual(current.slice(0,old.length-1),old.slice(0,-1));
 assert.deepEqual(current.slice(old.length-1,old.length+1),['ValidateExportsA6','ExecuteExportsA6']);
 assert.ok(candidate.split('\n')[0].endsWith("[string]$ExportFinalReviewSha256 = '')"));
});
test('validation exports gain no private mode or runtime seal permission',()=>{
 const lists=candidate.split('\n').filter(x=>x.startsWith('$taskNeedsPrivate =')||x.includes("if ($Mode -in @('ProvisionAuth','EnrollMfa'"));
 assert.equal(lists.length,2);for(const line of lists){assert.ok(line.includes("'ExecuteExportsA6'"));assert.ok(!line.includes("'ValidateExportsA6'"));}
 assert.equal((candidate.match(/\$Mode -ne 'ProvisionAuth'/g)||[]).length,(original.match(/\$Mode -ne 'ProvisionAuth'/g)||[]).length);
});
test('exact manifest, isolated child, A10 metadata, review and self hash are selected',()=>{
 for(const expected of ['9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01',sha(childBytes),
  'build/wave5-approved-execution-20261013-r5-a2',sourcePath,'private-owner-input-ready-20261014-r5-a10.json',
  '$taskExportReview.generatedPlan.sha256 -ne $taskExportPlanSha','$taskExportReview.privateAdapter.afterSha256 -ne (Get-FileHash -LiteralPath $PSCommandPath'])
  assert.ok(candidate.includes(expected),expected);
});
test('mandatory public preflight precedes private metadata validation and every DPAPI read',()=>{
 const publicStart=candidate.indexOf("$taskPhase = 'public-export-preflight'"),privateStart=candidate.indexOf("$taskPhase = 'private-metadata-validation'");
 assert.ok(publicStart>0&&publicStart<privateStart&&privateStart<firstDecrypt);
 const preflight=candidate.slice(publicStart,privateStart);assert.ok(preflight.includes("ArgumentList.Add('--preflight')"));
 assert.ok(preflight.includes('ArgumentList.Add($ExportFinalReviewSha256)'));
 assert.ok(preflight.includes('$taskPreflightProof.planSha256 -ne $taskExportPlanSha'));
 assert.ok(preflight.includes('$taskPreflightProof.finalReviewSha256 -ne $ExportFinalReviewSha256'));
});
test('public child has closed stdin, hidden direct execution and bounded wait',()=>{
 const preflight=candidate.slice(candidate.indexOf("$taskPhase = 'public-export-preflight'"),candidate.indexOf("$taskPhase = 'private-metadata-validation'"));
 for(const expected of ['$taskPreflight.StandardInput.Close()','$taskPreflightInfo.UseShellExecute = $false',
  '$taskPreflightInfo.CreateNoWindow = $true','$taskPreflight.WaitForExit(60000)','$taskPreflight.Kill($true)',
  "$taskPreflightInfo.EnvironmentVariables.Remove('SUPABASE_ACCESS_TOKEN')"])
  assert.ok(preflight.includes(expected),expected);
});
test('final pre-DPAPI guard rechecks the exact metadata, final review and immutable deadline',()=>{
 assert.ok(finalGuardStart>0&&firstDecrypt>finalGuardStart);
 for(const expected of ['Get-FileHash -LiteralPath $taskReadyFile','Get-FileHash -LiteralPath $taskExportReviewFile',
  '$taskExportPlan.controlBindings.metadata.sha256','$ExportFinalReviewSha256','[DateTimeOffset]::UtcNow -lt $taskExportStart',
  '[DateTimeOffset]::UtcNow.AddSeconds(90) -ge $taskExportEnd'])assert.ok(finalGuard.includes(expected),expected);
});
test('required final source and plan rechecks before DPAPI are present',()=>{
 // This is an intentional regression requirement. The frozen a1 fails it.
 assert.ok(finalGuard.includes('Get-FileHash -LiteralPath $taskInstaller'),'MISSING_FINAL_CHILD_SOURCE_HASH_CHECK');
 assert.ok(finalGuard.includes('Get-FileHash -LiteralPath $taskExportPlanPath'),'MISSING_FINAL_PLAN_HASH_CHECK');
});
test('private window is serialized from the reviewed object without deriving a new expiry',()=>{
 assert.ok(candidate.includes('$taskExportWindow = $taskExportPlan.window'));
 assert.ok(candidate.includes('Add-Member -NotePropertyName exportWindow -NotePropertyValue $taskExportWindow'));
 assert.ok(candidate.includes('$taskExportConfig.ownerToken = $null; $taskExportConfig.encryptionKey = $null; $taskExportConfig = $null'));
 assert.ok(!candidate.slice(candidate.indexOf("if ($Mode -in @('ValidateExportsA6','ExecuteExportsA6'))")).includes('AddHours('));
});
test('the bounded review hash is a separate command-line argument in the existing Arguments path',()=>{
 assert.ok(candidate.includes("'ExecuteExportsA6' { '--execute ' + $ExportFinalReviewSha256 }"));
 assert.ok(candidate.includes("$taskInfo.Arguments = '\"' + $taskInstaller + '\" ' + $taskFlag"));
 assert.ok(candidate.includes("[ValidatePattern('^$|^[a-f0-9]{64}$')][string]$ExportFinalReviewSha256"));
});
test('public export preflight refuses an invalid hash before all supplied reads',async()=>{
 let calls=0;await assert.rejects(preflightExportsOperation({finalReviewSha256:'not-a-hash',
  verifyPreparation:async()=>{calls++;},readPublic:async()=>{calls++;}}),/PINNED_PUBLIC_EXPORT_FINAL_REVIEW_SHA_REQUIRED/);
 assert.equal(calls,0);
});
test('public source preflight returns before stdin and actual execution rechecks its public bindings',()=>{
 assert.ok(child.indexOf("if(mode==='--preflight')")<child.indexOf('for await(const chunk of process.stdin)'));
 assert.ok(child.includes("must(reverified.planSha256===verified.planSha256,'EXPORT_PUBLIC_INPUT_CHANGED_BEFORE_UNSEAL')"));
 assert.ok(child.includes('sha256:finalReview.privateAdapter.afterSha256'));
 assert.ok(child.includes("must(sameFinanceJson(config.exportWindow,verified.plan.window),'EXACT_PRIVATE_ADAPTER_WINDOW_REQUIRED')"));
});
test('bound export child writes explicit public summaries and clears private configuration',()=>{
 const outputs=child.split('\n').filter(x=>x.includes('process.stdout.write(')||x.includes('process.stderr.write('));
 assert.equal(outputs.length,4);for(const line of outputs)assert.ok(!/ownerToken|encryptionKey|incoming|config[.,]/.test(line));
 assert.ok(child.includes("config.ownerToken='';config.encryptionKey=''"));
});
test('legacy public output and error sanitization blocks are preserved exactly',()=>{
 const suffix="    $taskPhase = 'public-child-output'";
 assert.equal(candidate.slice(candidate.indexOf(suffix)),original.slice(original.indexOf(suffix)));
});
