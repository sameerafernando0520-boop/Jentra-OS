// Source-only candidate builder. Never executes PowerShell, private input, or HTTP.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
export const PREDECESSOR={path:'scripts/wave5/run_private_management_installer_20261013_r5.ps1',
 sha256:'b01b6c20cb2819cb419fa10423bce37c0cba86b44ee7e2f5b9c0c9387d19be1f'};
export const CANDIDATE='scripts/wave5/run_private_management_installer_20261015_r5_a1.candidate.ps1';
const recordPath='docs/verification/wave5/root-export-adapter-20261015/source-candidate-a1.json';
const sourcePath='tools/wave5/finance_exports_20261014_r5_a6.mjs';
const must=(ok,code)=>{if(!ok)throw Error(code);};
export function buildCandidate(bytes,sourceSha256){
 must(hashBytes(bytes)===PREDECESSOR.sha256,'EXACT_PRESERVED_PRIVATE_ADAPTER_REQUIRED');
 must(/^[a-f0-9]{64}$/.test(sourceSha256),'EXACT_A6_SOURCE_HASH_REQUIRED');
 let text=bytes.toString('utf8');
 const once=(before,after)=>{must(text.split(before).length===2,'UNIQUE_PRIVATE_ADAPTER_ANCHOR_REQUIRED');text=text.replace(before,()=>after);};
 once("'ExecuteRemainingFinanceA3')][string]$Mode = 'ValidateOnly')",
  "'ExecuteRemainingFinanceA3','ValidateExportsA6','ExecuteExportsA6')][string]$Mode = 'ValidateOnly', [ValidatePattern('^$|^[a-f0-9]{64}$')][string]$ExportFinalReviewSha256 = '')");
 let privateLists=0;
 text=text.split('\n').map(line=>{
  if(line.startsWith('$taskNeedsPrivate =')||line.includes("if ($Mode -in @('ProvisionAuth','EnrollMfa'")){
   must(line.includes("'ExecuteRemainingFinanceA3')"),'EXACT_PRIVATE_MODE_LIST_REQUIRED');privateLists++;
   return line.replace("'ExecuteRemainingFinanceA3')","'ExecuteRemainingFinanceA3','ExecuteExportsA6')");
  }return line;
 }).join('\n');
 must(privateLists===2,'EXACT_TWO_PRIVATE_MODE_LISTS_REQUIRED');
 once("'ExecuteRemainingFinanceA3' { '--execute' }", "'ExecuteRemainingFinanceA3' { '--execute' } 'ExecuteExportsA6' { '--execute ' + $ExportFinalReviewSha256 }");
 const selector=`    if ($Mode -in @('ValidateExportsA6','ExecuteExportsA6')) {
        $taskExecutionRoot = Join-Path $taskRoot 'build/wave5-approved-execution-20261013-r5-a2'
        $taskManifest = Join-Path $taskRoot 'docs/verification/wave5/approved-isolated-execution-snapshot-20261013-r5-a2.json'
        if ((Get-FileHash -LiteralPath $taskManifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01') { throw 'EXACT_APPROVED_EXECUTION_SNAPSHOT_REQUIRED' }
        $taskInstaller = Join-Path $taskExecutionRoot '${sourcePath}'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '${sourceSha256}') { throw 'EXACT_EXPORT_A6_SOURCE_REQUIRED' }
        $taskReadyFile = Join-Path $taskRoot 'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json'
        if ($Mode -eq 'ExecuteExportsA6') {
            if ($ExportFinalReviewSha256 -notmatch '^[a-f0-9]{64}$') { throw 'PINNED_EXPORT_FINAL_REVIEW_REQUIRED' }
            $taskExportReviewFile = Join-Path $taskRoot 'docs/verification/wave5/task3-export-renewal-20261014/final-operation-review-a1.json'
            if ((Get-FileHash -LiteralPath $taskExportReviewFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExportFinalReviewSha256) { throw 'EXACT_EXPORT_FINAL_REVIEW_REQUIRED' }
            $taskExportReview = Get-Content -Raw -LiteralPath $taskExportReviewFile | ConvertFrom-Json -DateKind String
            $taskExportPlanPath = Join-Path $taskExecutionRoot 'docs/verification/wave5/finance-exports-preparation-20261014-r5-a6.json'
            $taskExportPlanSha = (Get-FileHash -LiteralPath $taskExportPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($taskExportReview.generatedPlan.sha256 -ne $taskExportPlanSha -or
                $taskExportReview.privateAdapter.afterSha256 -ne (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()) { throw 'EXACT_REVIEWED_EXPORT_ADAPTER_AND_PLAN_REQUIRED' }
            $taskExportPlan = Get-Content -Raw -LiteralPath $taskExportPlanPath | ConvertFrom-Json -DateKind String
            $taskExportWindow = $taskExportPlan.window
            if ((Get-FileHash -LiteralPath $taskReadyFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne
                $taskExportPlan.controlBindings.metadata.sha256) { throw 'EXACT_REVIEWED_EXPORT_METADATA_REQUIRED' }
        }
    }
`;
 once("    $taskNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source",selector+"    $taskNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source");
 const preflight=`    if ($Mode -eq 'ExecuteExportsA6') {
        # Full source, human decision, actual two-row readback, and final review
        # are verified by the public-only child BEFORE any DPAPI input is read.
        $taskPhase = 'public-export-preflight'
        $taskPreflightInfo = [Diagnostics.ProcessStartInfo]::new()
        $taskPreflightInfo.FileName = $taskNode
        [void]$taskPreflightInfo.ArgumentList.Add($taskInstaller)
        [void]$taskPreflightInfo.ArgumentList.Add('--preflight')
        [void]$taskPreflightInfo.ArgumentList.Add($ExportFinalReviewSha256)
        $taskPreflightInfo.WorkingDirectory = $taskRoot
        $taskPreflightInfo.UseShellExecute = $false
        $taskPreflightInfo.CreateNoWindow = $true
        $taskPreflightInfo.RedirectStandardInput = $true
        $taskPreflightInfo.RedirectStandardOutput = $true
        $taskPreflightInfo.RedirectStandardError = $true
        [void]$taskPreflightInfo.EnvironmentVariables.Remove('SUPABASE_ACCESS_TOKEN')
        $taskPreflight = [Diagnostics.Process]::new()
        try {
            $taskPreflight.StartInfo = $taskPreflightInfo
            if (-not $taskPreflight.Start()) { throw 'EXPORT_PUBLIC_PREFLIGHT_START_FAILED' }
            $taskPreflight.StandardInput.Close()
            $taskPreflightOut = $taskPreflight.StandardOutput.ReadToEndAsync()
            $taskPreflightErr = $taskPreflight.StandardError.ReadToEndAsync()
            if (-not $taskPreflight.WaitForExit(60000)) {
                $taskPreflight.Kill($true)
                throw 'EXPORT_PUBLIC_PREFLIGHT_TIMEOUT'
            }
            $taskPreflightText = $taskPreflightOut.GetAwaiter().GetResult()
            $taskPreflightError = $taskPreflightErr.GetAwaiter().GetResult()
            if ($taskPreflight.ExitCode -ne 0 -or $taskPreflightText.Length -gt 16000 -or $taskPreflightError.Trim().Length -ne 0) { throw 'EXPORT_PUBLIC_PREFLIGHT_FAILED' }
            $taskPreflightProof = $taskPreflightText | ConvertFrom-Json -DateKind String
            if ($taskPreflightProof.passed -ne $true -or $taskPreflightProof.networkCalls -ne 0 -or $taskPreflightProof.privateInputsRead -ne $false -or
                $taskPreflightProof.planSha256 -ne $taskExportPlanSha -or $taskPreflightProof.finalReviewSha256 -ne $ExportFinalReviewSha256) { throw 'EXACT_EXPORT_PUBLIC_PREFLIGHT_PROOF_REQUIRED' }
        } finally { $taskPreflight.Dispose(); $taskPreflightText = $null; $taskPreflightError = $null }
        $taskNow = [DateTimeOffset]::UtcNow
        $taskExportStart = Convert-TaskUtcTimestamp $taskExportWindow.notBefore
        $taskExportEnd = Convert-TaskUtcTimestamp $taskExportWindow.expiresAt
        if ($taskNow -lt $taskExportStart -or $taskExportEnd -le $taskNow.AddSeconds(90)) { throw 'FRESH_EXPORT_WINDOW_BEFORE_PRIVATE_INPUT_REQUIRED' }
    }
`;
 const privateAnchor='    if ($taskNeedsPrivate) {\n';
 once(privateAnchor,preflight+privateAnchor);
 once("        $taskSecret = ConvertTo-SecureString -String (Get-Content -Raw -LiteralPath $taskSealedPath)",`        if ($Mode -eq 'ExecuteExportsA6') {
            if ((Get-FileHash -LiteralPath $taskReadyFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskExportPlan.controlBindings.metadata.sha256 -or
                (Get-FileHash -LiteralPath $taskExportReviewFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExportFinalReviewSha256 -or
                [DateTimeOffset]::UtcNow -lt $taskExportStart -or [DateTimeOffset]::UtcNow.AddSeconds(90) -ge $taskExportEnd) { throw 'EXPORT_PUBLIC_INPUT_CHANGED_BEFORE_PRIVATE_INPUT' }
        }
        $taskSecret = ConvertTo-SecureString -String (Get-Content -Raw -LiteralPath $taskSealedPath)`);
 once('ownerToken=$taskPlain;privateDirectory=$taskFolder;encryptionKey=$taskKeyText } | ConvertTo-Json -Compress',
  'ownerToken=$taskPlain;privateDirectory=$taskFolder;encryptionKey=$taskKeyText } | ConvertTo-Json -Compress\n                if ($Mode -eq \'ExecuteExportsA6\') {\n                    $taskExportConfig = $taskPlain | ConvertFrom-Json -DateKind String\n                    $taskExportConfig | Add-Member -NotePropertyName exportWindow -NotePropertyValue $taskExportWindow\n                    $taskPlain = $taskExportConfig | ConvertTo-Json -Compress -Depth 12\n                    $taskExportConfig.ownerToken = $null; $taskExportConfig.encryptionKey = $null; $taskExportConfig = $null\n                }');
 // Legacy branches retain their exact output and secret-handling paths.
 return {text,sourceSha256,privateLists,addedModes:['ValidateExportsA6','ExecuteExportsA6']};
}
async function main(){
 must(process.argv[2]==='--prepare-candidate'&&process.argv.length===4,'FIXED_SOURCE_ONLY_CANDIDATE_MODE_REQUIRED');
 const before=await fs.readFile(path.join(root,PREDECESSOR.path)),source=await fs.readFile(path.join(root,sourcePath));
 must(hashBytes(source)===process.argv[3],'FROZEN_A6_SOURCE_HASH_REQUIRED');
 const result=buildCandidate(before,process.argv[3]);
 const outputs=[CANDIDATE,recordPath];
 for(const file of outputs){let exists=false;try{await fs.lstat(path.join(root,file));exists=true;}catch(e){if(e.code!=='ENOENT')throw e;}must(!exists,'EXCLUSIVE_NEW_CANDIDATE_OUTPUT_REQUIRED');}
 await fs.mkdir(path.dirname(path.join(root,recordPath)),{recursive:true});
 const record={kind:'source-only-export-private-adapter-candidate',createdAt:new Date().toISOString(),predecessor:PREDECESSOR,
  candidate:{path:CANDIDATE,sha256:hashBytes(result.text)},exportSource:{path:sourcePath,sha256:hashBytes(source)},
  addedModes:result.addedModes,privateLists:result.privateLists,originalAdapterChanged:false,installed:false,
  directHumanDecisionCreated:false,renewalPerformed:false,sourceApprovalPending:true,independentReviewPending:true,
  networkCalls:0,privateInputsRead:false,intentsConsumed:false};
 must(hashBytes(await fs.readFile(path.join(root,PREDECESSOR.path)))===PREDECESSOR.sha256,'ADAPTER_CHANGED_DURING_PREPARATION');
 await fs.writeFile(path.join(root,CANDIDATE),result.text,{flag:'wx'});
 await fs.writeFile(path.join(root,recordPath),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
 process.stdout.write(JSON.stringify(record)+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.message,networkCalls:0,privateInputsRead:false})+'\n');process.exitCode=1;
});
