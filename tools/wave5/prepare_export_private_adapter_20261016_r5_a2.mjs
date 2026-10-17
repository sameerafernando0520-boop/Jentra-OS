// Builds source only. Never starts PowerShell or opens private inputs.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
import {buildCandidate as buildOriginalCandidate,PREDECESSOR} from './prepare_export_private_adapter_20261015_r5_a1.mjs';
export {PREDECESSOR};
export const CANDIDATE='scripts/wave5/run_private_management_installer_20261016_r5_a2.candidate.ps1';
export const SOURCE='tools/wave5/finance_exports_20261016_r5_a7.mjs';
export const LOCK_SOURCE='docs/verification/wave5/root-export-adapter-20261016/public-read-holds-a2.ps1';
const root=fileURLToPath(new URL('../../',import.meta.url));
const recordPath='docs/verification/wave5/root-export-adapter-20261016/source-candidate-a2.json';
const builderBinding={path:'tools/wave5/prepare_export_private_adapter_20261015_r5_a1.mjs',sha256:'dd5fb37381a7671bd879b6e5a532f97aa66ed6d7b6f6f8410a0337240f173867'};
const must=(ok,code)=>{if(!ok)throw Error(code);};
export function buildCandidate(bytes,sourceSha256,lockSource){
 must(typeof lockSource==='string'&&lockSource.includes('[IO.FileShare]::Read')&&lockSource.includes('function Close-TaskReviewedReadHolds'),'EXACT_PUBLIC_HOLD_SOURCE_REQUIRED');
 let text=buildOriginalCandidate(bytes,sourceSha256).text;
 const once=(before,after)=>{must(text.split(before).length===2,'UNIQUE_A2_ADAPTER_ANCHOR_REQUIRED');text=text.replace(before,()=>after);};
 text=text.replaceAll('ExportsA6','ExportsA7').replaceAll('EXPORT_A6','EXPORT_A7')
  .replaceAll('tools/wave5/finance_exports_20261014_r5_a6.mjs',SOURCE)
  .replaceAll('task3-export-renewal-20261014/final-operation-review-a1.json','task3-export-renewal-20261016/final-operation-review-a1.json')
  .replaceAll('finance-exports-preparation-20261014-r5-a6.json','finance-exports-preparation-20261016-r5-a7.json');
 once('try {\n    if ((Get-FileHash -LiteralPath $taskInstaller',lockSource+'\ntry {\n    if ((Get-FileHash -LiteralPath $taskInstaller');
 once("        if ($Mode -eq 'ExecuteExportsA7') {\n            if ($ExportFinalReviewSha256", "        if ($Mode -in @('ValidateExportsA7','ExecuteExportsA7')) {\n            if ($ExportFinalReviewSha256");
 once('$taskExportReview.generatedPlan.sha256 -ne $taskExportPlanSha -or',`$taskExportReview.generatedPlan.path -cne 'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json' -or
                $taskExportReview.privateAdapter.path -cne '${PREDECESSOR.path}' -or
                $taskExportReview.generatedPlan.sha256 -ne $taskExportPlanSha -or`);
 once("    if ($Mode -eq 'ExecuteExportsA7') {\n        # Full source",`    if ($Mode -in @('ValidateExportsA7','ExecuteExportsA7')) {
        # Hold every reviewed public input before either child starts. No held file
        # may be replaced or opened for writing until that child has exited.
        foreach ($taskBinding in @($taskExportPlan.sourceBindings)) {
            Add-TaskReviewedReadHold $taskExecutionRoot $taskBinding.path $taskBinding.sha256
        }
        foreach ($taskBinding in @($taskExportPlan.publicBindings)) {
            Add-TaskReviewedReadHold $taskRoot $taskBinding.path $taskBinding.sha256
        }
        Add-TaskReviewedReadHold $taskExecutionRoot '${SOURCE}' '${sourceSha256}'
        Add-TaskReviewedReadHold $taskExecutionRoot 'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json' $taskExportPlanSha
        Add-TaskReviewedReadHold $taskRoot 'docs/verification/wave5/task3-export-renewal-20261016/final-operation-review-a1.json' $ExportFinalReviewSha256
        Add-TaskReviewedReadHold $taskRoot 'docs/verification/wave5/approved-isolated-execution-snapshot-20261013-r5-a2.json' '9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01'
        $taskSelfRelative = [IO.Path]::GetRelativePath($taskRoot,$PSCommandPath).Replace('\\','/')
        Add-TaskReviewedReadHold $taskRoot $taskSelfRelative $taskExportReview.privateAdapter.afterSha256
        # Full source`);
 once('        $taskNow = [DateTimeOffset]::UtcNow\n        $taskExportStart',`        if ($Mode -eq 'ValidateExportsA7') {
            @{passed=$true;networkCalls=0;privateInputsRead=$false;planSha256=$taskExportPlanSha;finalReviewSha256=$ExportFinalReviewSha256} | ConvertTo-Json -Compress
            exit 0
        }
        $taskNow = [DateTimeOffset]::UtcNow
        $taskExportStart`);
 once('(Get-FileHash -LiteralPath $taskExportReviewFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExportFinalReviewSha256 -or\n                [DateTimeOffset]::UtcNow',`(Get-FileHash -LiteralPath $taskExportReviewFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExportFinalReviewSha256 -or
                (Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne '${sourceSha256}' -or
                (Get-FileHash -LiteralPath $taskExportPlanPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskExportPlanSha -or
                [DateTimeOffset]::UtcNow`);
 once('    if ($null -ne $taskChild) { $taskChild.Dispose() }\n}',`    try {
        if ($null -ne $taskChild) {
            try {
                if ($Mode -in @('ValidateExportsA7','ExecuteExportsA7') -and -not $taskChild.HasExited) {
                    $taskChild.Kill($true)
                    if (-not $taskChild.WaitForExit(10000)) { throw 'EXPORT_CHILD_DID_NOT_EXIT' }
                }
            } finally { $taskChild.Dispose() }
        }
    } finally { Close-TaskReviewedReadHolds }
}`);
 return {text,sourceSha256,addedModes:['ValidateExportsA7','ExecuteExportsA7']};
}
async function main(){
 must(process.argv[2]==='--prepare-candidate'&&process.argv.length===4&&/^[a-f0-9]{64}$/.test(process.argv[3]),'FIXED_SOURCE_ONLY_A7_CANDIDATE_MODE_REQUIRED');
 const [before,source,builder,locks]=await Promise.all([fs.readFile(path.join(root,PREDECESSOR.path)),fs.readFile(path.join(root,SOURCE)),fs.readFile(path.join(root,builderBinding.path)),fs.readFile(path.join(root,LOCK_SOURCE),'utf8')]);
 must(hashBytes(builder)===builderBinding.sha256,'EXACT_PRESERVED_A1_BUILDER_REQUIRED');
 must(hashBytes(source)===process.argv[3],'FROZEN_A7_SOURCE_HASH_REQUIRED');
 const built=buildCandidate(before,process.argv[3],locks);
 for(const file of [CANDIDATE,recordPath]){let exists=false;try{await fs.lstat(path.join(root,file));exists=true;}catch(e){if(e.code!=='ENOENT')throw e;}must(!exists,'EXCLUSIVE_NEW_A2_CANDIDATE_REQUIRED');}
 const record={kind:'source-only-export-private-adapter-candidate-a2',createdAt:new Date().toISOString(),predecessor:PREDECESSOR,
  builderPredecessor:builderBinding,candidate:{path:CANDIDATE,sha256:hashBytes(built.text)},exportSource:{path:SOURCE,sha256:hashBytes(source)},
  readHoldSource:{path:LOCK_SOURCE,sha256:hashBytes(locks)},addedModes:built.addedModes,
  holdReviewedSourcesAndPublicInputsThroughChildExit:true,privateInputsRead:false,networkCalls:0,installed:false,intentsConsumed:false,
  directHumanDecisionCreated:false,independentReviewPending:true,sourceApprovalPending:true,actualPriorCharge:137,
  conditionalProposedBudgetOnly:{priorAtExports:141,ordinaryEnd:165,maximumThroughExports:166,overallMaximum:174}};
 must(hashBytes(await fs.readFile(path.join(root,PREDECESSOR.path)))===PREDECESSOR.sha256,'PREDECESSOR_CHANGED_DURING_PREPARATION');
 await fs.writeFile(path.join(root,CANDIDATE),built.text,{flag:'wx'});
 await fs.writeFile(path.join(root,recordPath),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
 process.stdout.write(JSON.stringify(record)+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:/^[A-Z][A-Z0-9_]+$/.test(error.message)?error.message:'A2_SOURCE_PREPARATION_STOPPED',networkCalls:0,privateInputsRead:false})+'\n');process.exitCode=1;
});
