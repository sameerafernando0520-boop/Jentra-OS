// Checks the exact public candidate and generated management text; no private execution.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {buildCandidate,PREDECESSOR,SOURCE,LOCK_SOURCE,CANDIDATE} from '../../../../tools/wave5/prepare_export_private_adapter_20261017_r5_a3.mjs';
import {buildManagementCandidate,TEMPLATE} from '../../../../tools/wave5/prepare_management_private_adapter_20261016_r5_a2.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url)),hash=x=>createHash('sha256').update(x).digest('hex');
const read=file=>fs.readFile(path.join(root,file));
const [before,source,locks,template,after,a2]=await Promise.all([read(PREDECESSOR.path),read(SOURCE),read(LOCK_SOURCE),read(TEMPLATE.path),read(CANDIDATE),read('scripts/wave5/run_private_management_installer_20261016_r5_a2.candidate.ps1')]);
const text=after.toString('utf8'),lockText=locks.toString('utf8');
const managementRecord=JSON.parse(await read('docs/verification/wave5/root-management-adapter-20261016/source-candidate-a2.json'));
const management=(await read(managementRecord.candidate.path)).toString('utf8');
test('exact generated management candidate reproduces all four frozen source pins',async()=>{
 assert.equal(hash(management),'7d3559d196932587ea76eafbd527bd6943362ad5c321b5c58873aa822343cce7');
 for(const row of managementRecord.sourceBindings)assert.equal(hash(await read(row.path)),row.sha256);
 const hashes=Object.fromEntries(['Renewal','Health','Scheduler','OwnerRefresh'].map((key,i)=>[key,managementRecord.sourceBindings[i].sha256]));
 assert.equal(buildManagementCandidate(template,lockText,hashes),management);
 assert.equal(managementRecord.installed,false);assert.equal(managementRecord.privateInputsRead,false);
});
test('a3 reproduces exact candidate bytes and preserves the rejected a2 candidate',()=>{
 assert.equal(hash(after),'aba5237681017897064118d2529c9401d92e6054257a19d4c01a6196f076dcf3');
 assert.equal(hash(a2),'4dd4911e892fa75dfdaaa0e0ea9036ddaa2e93d5a040c736515b55cec9053c15');
 assert.equal(buildCandidate(before,hash(source),lockText).text,text);
 const reduced=text.replace("            Add-TaskReviewedReadHold $taskRoot 'docs/verification/wave5/task3-export-renewal-20261016/final-operation-review-a1.json' $ExportFinalReviewSha256\n",'')
  .replace("            Add-TaskReviewedReadHold $taskExecutionRoot 'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json' $taskExportReview.generatedPlan.sha256\n",'');
 assert.equal(reduced,a2.toString('utf8'));
});
test('exact export review and plan are held before their first parse and all inventory enumeration',()=>{
 const reviewHold=text.indexOf("Add-TaskReviewedReadHold $taskRoot 'docs/verification/wave5/task3-export-renewal-20261016/final-operation-review-a1.json'"),
  reviewParse=text.indexOf('$taskExportReview = Get-Content'),planHold=text.indexOf("Add-TaskReviewedReadHold $taskExecutionRoot 'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json'"),
  planHash=text.indexOf('$taskExportPlanSha = (Get-FileHash'),planParse=text.indexOf('$taskExportPlan = Get-Content'),inventory=text.indexOf('foreach ($taskBinding in @($taskExportPlan.sourceBindings))');
 assert.ok(reviewHold>0&&reviewHold<reviewParse&&reviewParse<planHold&&planHold<planHash&&planHash<planParse&&planParse<inventory);
 assert.ok(text.includes('} finally { Close-TaskReviewedReadHolds }'));
});
test('management draft applies the same hold-before-parse order before public child launch',()=>{
 const reviewHold=management.indexOf('Add-TaskReviewedReadHold $taskRoot $taskSelected.review $FinalReviewSha256'),reviewParse=management.indexOf('$taskReview = Get-Content'),
  planHold=management.indexOf('Add-TaskReviewedReadHold $taskRoot $taskSelected.plan $taskReview.generatedPlan.sha256'),planParse=management.indexOf('$taskPlan = Get-Content'),
  inventory=management.indexOf('foreach ($taskBinding in @($taskPlan.sourceBindings) + @($taskPlan.publicBindings))'),child=management.indexOf("$taskChild = New-TaskProcess '--preflight'");
 assert.ok(reviewHold>0&&reviewHold<reviewParse&&reviewParse<planHold&&planHold<planParse&&planParse<inventory&&inventory<child);
});
test('PowerShell AST parses the exact a3 candidate and repaired management text without running them',async()=>{
 const script="$ErrorActionPreference='Stop'; $taskTexts=[Console]::In.ReadToEnd()|ConvertFrom-Json; $taskCount=0; foreach($taskText in $taskTexts){ $taskTokens=$null; $taskErrors=$null; $null=[Management.Automation.Language.Parser]::ParseInput($taskText,[ref]$taskTokens,[ref]$taskErrors); if($taskErrors.Count -ne 0){throw 'PUBLIC_AST_PARSE_FAILED'}; $taskCount++ }; [Console]::Out.WriteLine((@{parsed=$taskCount;executed=$false}|ConvertTo-Json -Compress))";
 const child=spawn('C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe',['-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{windowsHide:true,stdio:['pipe','pipe','pipe']});
 let out='',err='';child.stdout.on('data',x=>{out+=x;});child.stderr.on('data',x=>{err+=x;});const closed=once(child,'close');
 child.stdin.end(JSON.stringify([text,management]));const timer=setTimeout(()=>child.kill(),15000);
 try{const [code]=await closed;assert.equal(code,0);assert.equal(err,'');assert.deepEqual(JSON.parse(out),{parsed:2,executed:false});}finally{clearTimeout(timer);}
});
