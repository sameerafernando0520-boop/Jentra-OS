// Public source preparation only. No private input, PowerShell or network execution.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
export const TEMPLATE={path:'docs/verification/wave5/root-management-adapter-20261015/adapter-template-a1.ps1',sha256:'d75e67d9daf2214c865bd0570c5d9c223116b1f7ed361de9de1d6b2535f96587'};
export const LOCK_SOURCE='docs/verification/wave5/root-export-adapter-20261016/public-read-holds-a2.ps1';
export const CANDIDATE='scripts/wave5/run_private_health_scheduler_20261016_r5_a2.candidate.ps1';
export const SOURCES=Object.freeze({Renewal:'tools/wave5/renew_runtime_authority_20261015_r5_a1.mjs',Health:'tools/wave5/run_worker_v7_health_20261015_r5.mjs',Scheduler:'tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs'});
const refreshSource='tools/wave5/refresh_private_owner_scope_20261014_r5_a10.mjs';
const recordPath='docs/verification/wave5/root-management-adapter-20261016/source-candidate-a2.json';
const must=(ok,code)=>{if(!ok)throw Error(code);};
export function buildManagementCandidate(template,locks,hashes){
 must(hashBytes(template)===TEMPLATE.sha256,'EXACT_PRESERVED_MANAGEMENT_TEMPLATE_REQUIRED');
 must(typeof locks==='string'&&locks.includes('[IO.FileShare]::Read'),'EXACT_PUBLIC_READ_HOLDS_REQUIRED');
 must(Object.keys(hashes).sort().join(',')==='Health,OwnerRefresh,Renewal,Scheduler'&&Object.values(hashes).every(v=>/^[a-f0-9]{64}$/.test(v)),'EXACT_MANAGEMENT_SOURCE_HASHES_REQUIRED');
 let text=template.toString('utf8');
 const once=(before,after)=>{must(text.split(before).length===2,'UNIQUE_MANAGEMENT_A2_ANCHOR_REQUIRED');text=text.replace(before,()=>after);};
 for(const [key,marker] of Object.entries({Renewal:'__RENEWAL_SOURCE_SHA256__',Health:'__HEALTH_SOURCE_SHA256__',Scheduler:'__SCHEDULER_SOURCE_SHA256__',OwnerRefresh:'__OWNER_REFRESH_SOURCE_SHA256__'}))once(marker,hashes[key]);
 once('try {\n    $taskSelected',locks+'\ntry {\n    $taskSelected');
 once('    $taskReview = Get-Content -Raw -LiteralPath $taskReviewFile',`    Add-TaskReviewedReadHold $taskRoot $taskSelected.review $FinalReviewSha256
    $taskReview = Get-Content -Raw -LiteralPath $taskReviewFile`);
 once('    $taskPlanFile = Assert-TaskFile $taskSelected.plan $taskReview.generatedPlan.sha256',`    Add-TaskReviewedReadHold $taskRoot $taskSelected.plan $taskReview.generatedPlan.sha256
    $taskPlanFile = Assert-TaskFile $taskSelected.plan $taskReview.generatedPlan.sha256`);
 once("    $taskNode = (Get-Command node",`    if (@($taskPlan.sourceBindings).Count -lt 1 -or @($taskPlan.publicBindings).Count -lt 1) { throw 'EXPLICIT_REVIEWED_MANAGEMENT_FILE_INVENTORY_REQUIRED' }
    foreach ($taskBinding in @($taskPlan.sourceBindings) + @($taskPlan.publicBindings)) {
        Add-TaskReviewedReadHold $taskRoot $taskBinding.path $taskBinding.sha256
    }
    Add-TaskReviewedReadHold $taskRoot $taskSelected.source $taskSelected.sha256
    Add-TaskReviewedReadHold $taskRoot $taskSelected.plan $taskReview.generatedPlan.sha256
    Add-TaskReviewedReadHold $taskRoot $taskSelected.review $FinalReviewSha256
    Add-TaskReviewedReadHold $taskRoot $taskMetadataPath $taskPlan.controlBindings.metadata.sha256
    $taskSelfRelative = [IO.Path]::GetRelativePath($taskRoot,$PSCommandPath).Replace('\\','/')
    Add-TaskReviewedReadHold $taskRoot $taskSelfRelative $taskReview.privateAdapter.afterSha256
    $taskNode = (Get-Command node`);
 once('    if ($null -ne $taskChild) { $taskChild.Dispose() }\n}',`    try {
        if ($null -ne $taskChild) {
            try {
                if (-not $taskChild.HasExited) {
                    $taskChild.Kill($true)
                    if (-not $taskChild.WaitForExit(10000)) { throw 'MANAGEMENT_CHILD_DID_NOT_EXIT' }
                }
            } finally { $taskChild.Dispose() }
        }
    } finally { Close-TaskReviewedReadHolds }
}`);
 must(!/__[A-Z_]+__/.test(text),'UNRESOLVED_MANAGEMENT_SOURCE_MARKER');
 return text;
}
async function main(){
 must(process.argv[2]==='--prepare-candidate'&&process.argv.length===6&&process.argv.slice(3).every(v=>/^[a-f0-9]{64}$/.test(v)),'FIXED_PUBLIC_MANAGEMENT_SOURCE_HASHES_REQUIRED');
 const template=await fs.readFile(path.join(root,TEMPLATE.path)),locks=await fs.readFile(path.join(root,LOCK_SOURCE),'utf8'),hashes={},sourceBindings=[];
 for(const [i,[name,file]] of Object.entries(SOURCES).entries()){
  const bytes=await fs.readFile(path.join(root,file));must(hashBytes(bytes)===process.argv[i+3],'MANAGEMENT_SOURCE_HASH_CHANGED');
  hashes[name]=hashBytes(bytes);sourceBindings.push({path:file,sha256:hashes[name]});
 }
 const refresh=await fs.readFile(path.join(root,refreshSource));hashes.OwnerRefresh=hashBytes(refresh);sourceBindings.push({path:refreshSource,sha256:hashes.OwnerRefresh});
 const text=buildManagementCandidate(template,locks,hashes);
 for(const file of [CANDIDATE,recordPath]){let exists=false;try{await fs.lstat(path.join(root,file));exists=true;}catch(e){if(e.code!=='ENOENT')throw e;}must(!exists,'EXCLUSIVE_MANAGEMENT_A2_OUTPUT_REQUIRED');}
 await fs.mkdir(path.dirname(path.join(root,recordPath)),{recursive:true});
 const record={kind:'source-only-management-private-adapter-a2',createdAt:new Date().toISOString(),template:TEMPLATE,
  readHoldSource:{path:LOCK_SOURCE,sha256:hashBytes(locks)},sourceBindings,candidate:{path:CANDIDATE,sha256:hashBytes(text)},
  actualFuturePath:'scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1',installed:false,networkCalls:0,privateInputsRead:false,
  publicInputsHeldThroughChildExit:true,sourceApprovalPending:true,independentReviewPending:true,intentsConsumed:false,directHumanDecisionCreated:false};
 await fs.writeFile(path.join(root,CANDIDATE),text,{flag:'wx'});
 await fs.writeFile(path.join(root,recordPath),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
 process.stdout.write(JSON.stringify(record)+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:/^[A-Z][A-Z0-9_]+$/.test(error.message)?error.message:'MANAGEMENT_SOURCE_PREPARATION_STOPPED',networkCalls:0,privateInputsRead:false})+'\n');process.exitCode=1;
});
