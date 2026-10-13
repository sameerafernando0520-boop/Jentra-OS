import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';
import { validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';
import { REMAINING_PLAN,PRIOR_FINANCE,ORIGINAL_PLAN,ORIGINAL_SOURCE_HASH,CURRENT_WHOLE_SOURCE_HASH,STALE_COMMAND,STALE_PROPOSAL,
 PRIOR_REQUEST_BOUND,REMAINING_FUNCTION_MD5,EXPECTED_PROCESS_APPENDS } from './finance_remaining_20261013_r5_a2.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const previousRemainingPlan=base+'finance-remaining-preparation-20261013-r5-a1.json';
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
export const REMAINING_DIRECT_SOURCES=Object.freeze(['tools/wave5/finance_remaining_20261013_r5_a2.mjs',
 'tools/wave5/prepare_finance_remaining_20261013_r5_a2.mjs','tools/wave5/finance_remaining_20261013_r5_a2.test.mjs',
 'tools/wave5/finance_remaining_20261013_r5.mjs',
 'tools/wave5/prepare_finance_remaining_20261013_r5.mjs','tools/wave5/finance_remaining_20261013_r5.test.mjs',
 'tools/wave5/finance_https_transport_20261013_r5_a2.mjs','tools/wave5/finance_cash_workflows_20261013_r5.mjs',
 'tools/wave5/finance_cash_fixture_20261013_r5.mjs','tools/wave5/finance_https_transport_20261013_r5.mjs',
 'tools/wave5/approved_management_installer.mjs','tools/wave5/runtime_contract.mjs','tools/wave5/runtime_fixture_spec.mjs',
 'tools/wave5/private_existing_actor_session_20261013_r5.mjs','tools/wave5/private_runtime_seal.mjs','tools/wave5/private_runtime_http.mjs',
 'tools/wave5/supabase_http_transport.mjs','tools/wave5/enroll_mfa_management_20261013_r5.mjs',
 'docs/verification/wave5/auth-admin-provisioning-20261013-r5-1791877892653/99-result.json',
 'docs/verification/wave5/genuine-mfa-20261013-r5-1791878507585/99-result.json',ORIGINAL_PLAN,
 'docs/verification/wave5/finance-stale-command-read-only-resolution-20261013-r5-a1.json',
 'docs/verification/wave5/finance-remaining-readonly-observation-20261013-r5-a1.json',
 'docs/verification/wave5/finance-remaining-readonly-reconciliation-20261013-r5-a2.json',
 'docs/verification/wave5/finance-stale-backend-metadata-20261013-r5-a1.json',
 'docs/verification/wave5/finance-runtime-independent-evidence-review-20261013-r5-a1.json',previousRemainingPlan]);
export async function prepareRemainingFinance(){
 const {review}=await loadApprovedInputs();validateFinanceFixture(review);
 const priorRemainingBytes=await fs.readFile(path.join(root,previousRemainingPlan)),priorRemaining=JSON.parse(priorRemainingBytes);
 must(priorRemaining.kind==='source-bound-genuine-finance-remaining-preparation'&&priorRemaining.projectId===PROJECT
  &&priorRemaining.bundleSha256===BUNDLE&&priorRemaining.priorRequestBound===75&&priorRemaining.networkCallsDuringPreparation===0,
  'PRESERVED_REMAINING_PREPARATION_REQUIRED');
 const frozen={'tools/wave5/finance_cash_workflows_20261013_r5.mjs':'15758ebee2def57d0b3796cd9911090207ba7c9d49bbcbaa8b4201b9a420b64c',
  'tools/wave5/finance_https_transport_20261013_r5.mjs':'5eb2b839a9249fd457073d4b63523d311f06ecc2d392710db2f823259395ba0f',
  [ORIGINAL_PLAN]:'2290874b4d90865fea02d0c070c0342962a440f391fb9863df052fcbcc1f4913',
  [PRIOR_FINANCE+'99-stop.json']:'7448f80d2a38b4b06d5d0a7abc3fafbc9b0a82614cff3f00c0b054b124dcab31',
  [PRIOR_FINANCE+'date-payroll_obligation.json']:'6c1b79d4bef6c28c281bad88109f670ebefc457e78c39f378d1a8c7b3f0a6da7'};
 for(const [file,sha]of Object.entries(frozen))must(hashBytes(await fs.readFile(path.join(root,file)))===sha,'PRESERVED_FINANCE_INPUT_DRIFT');
 const priorEvidenceBindings=[];
 for(const directory of [base+'genuine-finance-finance-20261013-r5-1791894436593/',PRIOR_FINANCE]){
  for(const file of (await fs.readdir(path.join(root,directory))).sort()){
   must(/^[a-zA-Z0-9_-]+\.json$/.test(file),'FIXED_PUBLIC_PRIOR_FINANCE_EVIDENCE_REQUIRED');
   const relative=directory+file;priorEvidenceBindings.push({path:relative,sha256:hashBytes(await fs.readFile(path.join(root,relative)))});
  }
 }
 const sourceBindings=[];for(const file of REMAINING_DIRECT_SOURCES)sourceBindings.push({path:file,sha256:hashBytes(await fs.readFile(path.join(root,file)))});
 sourceBindings.push(...priorEvidenceBindings);
 const plan={kind:'source-bound-genuine-finance-remaining-preparation',preparedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,
  operationScopeSha256:review.sourceContinuation.unchangedRuntimeOperationScopeSha256,sourceBindings,priorEvidenceBindings,
  previousRemainingPlan:{path:previousRemainingPlan,sha256:hashBytes(priorRemainingBytes)},preservedOriginalRemainingSourceBindings:true,
  priorRequestBound:PRIOR_REQUEST_BOUND,priorRequestBoundBreakdown:{firstAttemptConservativeReserve:40,firstAttemptObservedCount:null,resumeObservedAttempts:35},
  maximumTotalWorkflowRequestAttempts:150,oneReadOnlyResolutionAttemptReserved:true,maximumExecutionMs:900000,networkCallsDuringPreparation:0,
  maximumManagementOrActualTransportTimeoutMs:45000,actualClockDateRequired:'2026-10-13',
  originalBaselineSourceHash:ORIGINAL_SOURCE_HASH,currentRawWholeSourceHash:CURRENT_WHOLE_SOURCE_HASH,
  expectedPriorStatementProcessAppends:EXPECTED_PROCESS_APPENDS.slice(0,3),expectedNewExportProcessAppends:EXPECTED_PROCESS_APPENDS.slice(3),
  originalProcessRows:4,baselineHashMustRemainExact:true,rawWholeDigestExpectedToChangeForExactlyTwoExportProcessEvents:true,
  originalStaleCommandId:STALE_COMMAND,originalStaleProposalId:STALE_PROPOSAL,replayOrRetryOfStaleForbidden:true,
  successfulStatementsClassificationAndPayrollDateWillNotBeRepeated:true,expectedConflictHttpResponseStillUnobserved:true,
  originalPrepareReplayRequiresCanonicalFullValueEquality:true,originalPrepareReplayRequiresRawResponseSha256Equality:true,
  originalPreparedAndReplayResponseHashesPersisted:true,
  freshZeroReceiptProposalAndActualInvocationRequiredBeforeAnyWrite:true,repeatedOriginalCommandQuiescenceBeforeEachAllowedDispatch:true,
  installedFunctionMd5Bindings:REMAINING_FUNCTION_MD5,
  allowedWrites:{paymentDateProposals:2,independentPaymentDateApprovals:2,exactOriginalPreparedCommandReplays:2,governedCsvExportRegistrations:2},
  genuineExistingActors:['proposer','approver','foreign-member'],actualIndependentPipelineReopenPlanned:true,actualFreshStatementSourceReproductionPlanned:true,
  cashBasisScenariosAndCashExportsExcluded:true,operationalPayrollApproval:false,administrativeSourceFixture:true,newActorOrMfaEnrollment:false,
  newRoleOrGrant:false,schemaMutation:false,existingBusinessSourceRowsModified:false,actualUserJournalPosting:false,actualRuntimeVerification:false,
  primaryErrorStatusSource:'https://docs.postgrest.org/en/v14/references/errors.html',known40And55SqlstateRequiresExactMessageAndHttp500:true,
  incompleteGateFlagsRequired:true,independentReviewRequired:true,authenticatedNative:false,xlsx:false,targetScaleLoad:false,actualDelivery:false,
  ownerAcceptance:false,production:false,realBilling:false};
 const bytes=JSON.stringify(plan,null,2)+'\n',handle=await fs.open(path.join(root,REMAINING_PLAN),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {prepared:true,evidence:{path:REMAINING_PLAN,sha256:hashBytes(bytes)},sourceBindings:sourceBindings.length,liveOperations:0};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv.length>2){process.stderr.write(JSON.stringify({failureCode:'FIXED_REMAINING_PREPARATION_MODE_REQUIRED'})+'\n');process.exitCode=1;}
 else prepareRemainingFinance().then(result=>process.stdout.write(JSON.stringify(result)+'\n')).catch(error=>{
  process.stderr.write(JSON.stringify({failureCode:error.publicCode??'REMAINING_PREPARATION_FAILED',privateErrorPrinted:false})+'\n');process.exitCode=1;});
}
