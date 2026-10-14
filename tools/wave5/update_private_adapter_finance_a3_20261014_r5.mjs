import fs from 'node:fs/promises';
import {hashBytes} from './runtime_contract.mjs';
const root=new URL('../../',import.meta.url),file='scripts/wave5/run_private_management_installer_20261013_r5.ps1',b=await fs.readFile(new URL(file,root));
if(hashBytes(b)!=='bc9b5671013bed109d441c847373d97068f2d8a91c35219e4052ff91960a2e77')throw Error('EXACT_PRIVATE_ADAPTER_A7_REQUIRED');
let s=b.toString('utf8');function once(a,c){if(s.split(a).length!==2)throw Error('EXACT_FINANCE_A3_ADAPTER_ANCHOR_REQUIRED');s=s.replace(a,c);}
once("'ExecuteRemainingFinance')][string]", "'ExecuteRemainingFinance','ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3')][string]");
let privateLists=0;s=s.split('\n').map(line=>{if(line.startsWith('$taskNeedsPrivate =')||line.includes("if ($Mode -in @('ProvisionAuth','EnrollMfa'")){if(!line.includes("'ExecuteRemainingFinance')"))throw Error('EXACT_PRIVATE_FINANCE_LIST_REQUIRED');privateLists++;return line.replace("'ExecuteRemainingFinance')","'ExecuteRemainingFinance','ExecuteRemainingFinanceA3')");}return line;}).join('\n');
if(privateLists!==2)throw Error('EXACT_TWO_PRIVATE_FINANCE_LISTS_REQUIRED');
once("'ExecuteRemainingFinance' { '--execute' }", "'ExecuteRemainingFinance' { '--execute' } 'ExecuteRemainingFinanceA3' { '--execute' }");
const selector=`    if ($Mode -in @('ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3')) {
        $taskExecutionRoot = Join-Path $taskRoot 'build/wave5-approved-execution-20261013-r5-a2'
        $taskSnapshotManifest = Join-Path $taskRoot 'docs/verification/wave5/approved-isolated-execution-snapshot-20261013-r5-a2.json'
        if ((Get-FileHash -LiteralPath $taskSnapshotManifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01') { throw 'EXACT_APPROVED_EXECUTION_SNAPSHOT_REQUIRED' }
        $taskInstaller = Join-Path $taskExecutionRoot 'tools/wave5/finance_remaining_20261014_r5_a3.mjs'
        if ((Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '8cf6068a4f4863c27d234b96755b2e1f9332c13590a25e5b66ef4742da87bd52') { throw 'EXACT_FINANCE_A3_SOURCE_REQUIRED' }
        $taskRemainingPlan = Join-Path $taskExecutionRoot 'docs/verification/wave5/finance-remaining-preparation-20261014-r5-a3.json'
        if ((Get-FileHash -LiteralPath $taskRemainingPlan -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198') { throw 'EXACT_FINANCE_A3_PLAN_REQUIRED' }
        $taskFinanceA3RootReview = Join-Path $taskRoot 'docs/verification/wave5/finance-remaining-root-source-review-20261014-r5-a3.json'
        if ((Get-FileHash -LiteralPath $taskFinanceA3RootReview -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            'f661da3175194cdf472e8c24046804023b545485e13dbd40279d39991ff5d135') { throw 'EXACT_FINANCE_A3_ROOT_REVIEW_REQUIRED' }
        $taskFinanceA3Peer = Join-Path $taskRoot 'docs/verification/wave5/task3-completion-20261013/finance-a3-independent-source-and-plan-review.json'
        if ((Get-FileHash -LiteralPath $taskFinanceA3Peer -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '8399666dc0528532cd3462e26a70ac89a340b6484a7b3fe911172d291aae814e') { throw 'EXACT_FINANCE_A3_INDEPENDENT_REVIEW_REQUIRED' }
        $taskFinanceA3Decision = Get-Content -Raw -LiteralPath $taskFinanceA3Peer | ConvertFrom-Json
        if ($taskFinanceA3Decision.technicalVerdict -notlike 'approve exact*' -or
            $taskFinanceA3Decision.generatedPlan.sha256 -ne '6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198' -or
            $taskFinanceA3Decision.personalHumanExactSourceSignatureClaimed -ne $false) { throw 'PASSED_EXACT_FINANCE_A3_REVIEW_REQUIRED' }
    }
`;
once("    $taskNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source",selector+"    $taskNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source");
await fs.writeFile(new URL(file,root),s);
const record={kind:'public-finance-a3-private-adapter-source-preparation',preparedAt:new Date().toISOString(),adapterPath:file,beforeSha256:hashBytes(b),afterSha256:hashBytes(s),modesAdded:['ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3'],newPrivateMode:'ExecuteRemainingFinanceA3',validateUnsealsCredentials:false,privateListsUpdated:2,exactExecutionSourceSha256:'8cf6068a4f4863c27d234b96755b2e1f9332c13590a25e5b66ef4742da87bd52',generatedPlanSha256:'6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198',independentSourcePlanReviewSha256:'8399666dc0528532cd3462e26a70ac89a340b6484a7b3fe911172d291aae814e',oldFinanceModesAndConsumedIntentPreserved:true,frozenApprovalValidatorChanged:false,originalPrivateAclSidExpiryAndDpapiGuardsPreserved:true,rawPrivateValuesPrinted:false,liveOperations:0,independentAdapterReviewPending:true};
const p='docs/verification/wave5/finance-a3-private-adapter-source-preparation-20261014-r5.json';await fs.writeFile(new URL(p,root),JSON.stringify(record,null,2)+'\n',{flag:'wx'});process.stdout.write(JSON.stringify(record)+'\n');
