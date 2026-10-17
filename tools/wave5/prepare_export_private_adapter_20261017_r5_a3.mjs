// Additive source-only correction. Keeps the rejected a2 candidate unchanged.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
import {buildCandidate as buildA2,PREDECESSOR,SOURCE,LOCK_SOURCE} from './prepare_export_private_adapter_20261016_r5_a2.mjs';
export {PREDECESSOR,SOURCE,LOCK_SOURCE};
export const CANDIDATE='scripts/wave5/run_private_management_installer_20261017_r5_a3.candidate.ps1';
export const RECORD='docs/verification/wave5/root-export-adapter-20261017/source-candidate-a3.json';
const root=fileURLToPath(new URL('../../',import.meta.url));
const predecessorBuilder={path:'tools/wave5/prepare_export_private_adapter_20261016_r5_a2.mjs',sha256:'f49815dc2f2b394a004669ecf7697b5676d51807bc9767cf5bd98902f94d7b41'};
const must=(ok,code)=>{if(!ok)throw Error(code);};
export function buildCandidate(bytes,sourceSha256,locks){
 let text=buildA2(bytes,sourceSha256,locks).text;
 const once=(before,after)=>{must(text.split(before).length===2,'UNIQUE_A3_REVIEWED_READ_ANCHOR_REQUIRED');text=text.replace(before,()=>after);};
 once('            $taskExportReview = Get-Content -Raw -LiteralPath $taskExportReviewFile',`            Add-TaskReviewedReadHold $taskRoot 'docs/verification/wave5/task3-export-renewal-20261016/final-operation-review-a1.json' $ExportFinalReviewSha256
            $taskExportReview = Get-Content -Raw -LiteralPath $taskExportReviewFile`);
 once('            $taskExportPlanSha = (Get-FileHash -LiteralPath $taskExportPlanPath',`            Add-TaskReviewedReadHold $taskExecutionRoot 'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json' $taskExportReview.generatedPlan.sha256
            $taskExportPlanSha = (Get-FileHash -LiteralPath $taskExportPlanPath`);
 return {text,sourceSha256,addedModes:['ValidateExportsA7','ExecuteExportsA7']};
}
async function main(){
 must(process.argv[2]==='--prepare-candidate'&&process.argv.length===4&&/^[a-f0-9]{64}$/.test(process.argv[3]),'FIXED_SOURCE_ONLY_A3_MODE_REQUIRED');
 const [before,source,builder,locks]=await Promise.all([fs.readFile(path.join(root,PREDECESSOR.path)),fs.readFile(path.join(root,SOURCE)),fs.readFile(path.join(root,predecessorBuilder.path)),fs.readFile(path.join(root,LOCK_SOURCE),'utf8')]);
 must(hashBytes(builder)===predecessorBuilder.sha256,'EXACT_PRESERVED_A2_BUILDER_REQUIRED');
 must(hashBytes(source)===process.argv[3],'FROZEN_A7_SOURCE_HASH_REQUIRED');
 const built=buildCandidate(before,process.argv[3],locks);
 for(const file of [CANDIDATE,RECORD]){let exists=false;try{await fs.lstat(path.join(root,file));exists=true;}catch(e){if(e.code!=='ENOENT')throw e;}must(!exists,'EXCLUSIVE_NEW_A3_CANDIDATE_REQUIRED');}
 await fs.mkdir(path.dirname(path.join(root,RECORD)),{recursive:true});
 const record={kind:'source-only-export-private-adapter-candidate-a3',createdAt:new Date().toISOString(),predecessor:PREDECESSOR,
  predecessorBuilder,candidate:{path:CANDIDATE,sha256:hashBytes(built.text)},exportSource:{path:SOURCE,sha256:hashBytes(source)},
  readHoldSource:{path:LOCK_SOURCE,sha256:hashBytes(locks)},addedModes:built.addedModes,
  reviewAndPlanHeldBeforeParsing:true,completeInventoryHeldThroughChildExit:true,installed:false,privateInputsRead:false,networkCalls:0,
  intentsConsumed:false,directHumanDecisionCreated:false,sourceApprovalPending:true,independentReviewPending:true,
  actualPriorCharge:137,conditionalBudgetOnly:{priorAtExports:141,ordinaryEnd:165,maximumThroughExports:166,overallMaximum:174}};
 must(hashBytes(await fs.readFile(path.join(root,PREDECESSOR.path)))===PREDECESSOR.sha256,'ORIGINAL_ADAPTER_CHANGED');
 await fs.writeFile(path.join(root,CANDIDATE),built.text,{flag:'wx'});
 await fs.writeFile(path.join(root,RECORD),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
 process.stdout.write(JSON.stringify(record)+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:/^[A-Z][A-Z0-9_]+$/.test(error.message)?error.message:'A3_SOURCE_PREPARATION_STOPPED',networkCalls:0,privateInputsRead:false})+'\n');process.exitCode=1;
});
