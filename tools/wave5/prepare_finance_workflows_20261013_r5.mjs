import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';
import { validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),file='docs/verification/wave5/finance-cash-workflow-preparation-20261013-r5-a3.json';
async function main(){if(process.argv.length>2)throw Error('FIXED_FINANCE_PREPARATION_MODE_REQUIRED');
 const {review}=await loadApprovedInputs();validateFinanceFixture(review);
 const sourceBindings=[];for(const source of ['tools/wave5/finance_cash_fixture_20261013_r5.mjs','tools/wave5/finance_cash_workflows_20261013_r5.mjs',
  'tools/wave5/finance_https_transport_20261013_r5.mjs','tools/wave5/prepare_finance_workflows_20261013_r5.mjs',
  'tools/wave5/private_existing_actor_session_20261013_r5.mjs','tools/wave5/private_runtime_seal.mjs','tools/wave5/private_runtime_http.mjs',
  'tools/wave5/supabase_http_transport.mjs','tools/wave5/enroll_mfa_management_20261013_r5.mjs','tools/wave5/runtime_contract.mjs',
  'docs/verification/wave5/auth-admin-provisioning-20261013-r5-1791877892653/99-result.json',
  'docs/verification/wave5/genuine-mfa-20261013-r5-1791878507585/99-result.json',
  'docs/verification/wave5/finance-cash-fixture-preparation-20261013-r5-a1.json'])
  sourceBindings.push({path:source,sha256:hashBytes(await fs.readFile(path.join(root,source)))});
 const plan={kind:'source-bound-genuine-finance-workflow-preparation',preparedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,
  operationScopeSha256:review.sourceContinuation.unchangedRuntimeOperationScopeSha256,sourceBindings,networkCallsDuringPreparation:0,
  maximumTotalWorkflowRequestAttempts:150,maximumExecutionMs:900000,genuineExistingActors:['proposer','approver','foreign-member'],
  executionModes:['--execute-finance','--resume-finance','--execute-cash'],financePhase:{financialPublications:3,classifications:1,paymentDateApprovals:3,governedExports:2},
  cashPhase:{scenarioRevisions:2,governedExports:2,requiresActualDate:'2026-10-14',requiresCompletedFinanceBinding:true},
  futureHorizonInstalledGuard:true,cashPhaseCurrentlyBlocked:true,actualMissingDateBasisNotProved:true,
  newActorOrMfaEnrollment:false,permissionMutation:false,originalIdentitiesRetainedBeforeEachWrite:true,uncertaintyStopsBeforeSuccessor:true,
  administrativeSourceFixture:true,actualUserPosting:false,actualRuntimeVerification:false,independentReviewRequired:true,
  authenticatedNative:false,ownerAcceptance:false,production:false,realBilling:false};
 const bytes=JSON.stringify(plan,null,2)+'\n',handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 process.stdout.write(JSON.stringify({prepared:true,evidence:{path:file,sha256:hashBytes(bytes)},liveOperations:0})+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(()=>{
 process.stderr.write(JSON.stringify({failureCode:'FINANCE_WORKFLOW_PREPARATION_FAILED',noCredentialOutput:true})+'\n');process.exitCode=1;});
