import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';
import { financeFixtureSql,validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
async function save(file,bytes){const handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:file,sha256:hashBytes(bytes)};}
async function main(){if(process.argv.length>2)throw Error('FIXED_FINANCE_PREPARATION_MODE_REQUIRED');
 const {review}=await loadApprovedInputs(),fixture=validateFinanceFixture(review);
 const sourceBindings=[];for(const file of ['tools/wave5/finance_cash_fixture_20261013_r5.mjs','tools/wave5/prepare_finance_fixture_20261013_r5.mjs'])
  sourceBindings.push({path:file,sha256:hashBytes(await fs.readFile(path.join(root,file)))});
 const rollback=await save(base+'finance-cash-fixture-20261013-r5-a1-rollback.sql',financeFixtureSql()),
  commit=await save(base+'finance-cash-fixture-20261013-r5-a1-commit.sql',financeFixtureSql({commit:true}));
 const plan={kind:'source-bound-approved-runtime-finance-fixture-preparation',preparedAt:new Date().toISOString(),
  projectId:PROJECT,bundleSha256:BUNDLE,operationScopeSha256:review.sourceContinuation.unchangedRuntimeOperationScopeSha256,
  fixture,sourceBindings,rollback,commit,maximumCreatedJournals:9,maximumCreatedLines:18,maximumCreatedOpenItems:2,
  existingScopesPreserved:true,exactRuntimeOnly:true,transactionCollisionGuard:true,allConstraintsEnabled:true,
  noAutomaticRetry:true,unknownOutcomeAction:'read exact intended IDs and hashes before any successor',
  actualRollbackExecuted:false,actualCommitExecuted:false,actualUserPosting:false,authOrRoleMutation:false,
  fabricatedAuthOrJwt:false,workerDeployment:false,ownerAcceptance:false,production:false,realBilling:false};
 const evidence=await save(base+'finance-cash-fixture-preparation-20261013-r5-a1.json',JSON.stringify(plan,null,2)+'\n');
 process.stdout.write(JSON.stringify({prepared:true,liveOperations:0,evidence,rollback,commit})+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(()=>{
 process.stderr.write(JSON.stringify({failureCode:'FINANCE_FIXTURE_PREPARATION_FAILED',noCredentialOutput:true})+'\n');process.exitCode=1;});
