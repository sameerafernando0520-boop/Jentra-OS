import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs} from './approved_management_installer.mjs';
import {hashBytes,immutableJson} from './runtime_contract.mjs';
import {validateFinanceFixture} from './finance_cash_fixture_20261013_r5.mjs';
import {EXECUTION_ROOT,PUBLIC_EVIDENCE_ROOT,REMAINING_PLAN,REMAINING_ONCE,REMAINING_NEW_SOURCES,
 PREVIOUS_ATTEMPT,CASH_PATCH,CASH_PUBLIC_BINDINGS,PRIOR_REQUEST_BOUND,REMAINING_FUNCTION_MD5,
 verifyRemainingRoots,validateRemainingActualDay,readExactRemainingFile,loadConsumedRemainingAttempt,
 loadCashPatchEvidence,validateRemainingPreparationPlan,validatePreservedRemainingBindings} from './finance_remaining_20261014_r5_a3.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
export const REMAINING_DIRECT_SOURCES=REMAINING_NEW_SOURCES;

// The old a2 plan is hash-pinned, so its exact source and evidence population
// is retained. No directory scan, old-file copy or replacement is performed.
export function buildRemainingPreparation({previous,sourceBindings,cashValidation,preparedAt}){
 must(previous?.validation?.priorRequestBound===PRIOR_REQUEST_BOUND
  &&previous.validation.observedReadOnlyAttempts===3&&previous.validation.completedCommands===0
  &&previous.validation.pendingCommand===null&&previous.validation.resolution===null
  &&cashValidation?.migrationVersion===CASH_PATCH.migrationVersion
  &&cashValidation.cashDateDefinitionMd5===REMAINING_FUNCTION_MD5.wave5_cash_date_command
  &&typeof preparedAt==='string'&&Number.isFinite(Date.parse(preparedAt)),'VALIDATED_REMAINING_SUCCESSOR_INPUTS_REQUIRED');
 validateRemainingActualDay(preparedAt);
 const priorEvidenceBindings=[...previous.plan.priorEvidenceBindings,PREVIOUS_ATTEMPT.stop,PREVIOUS_ATTEMPT.once];
 const plan=immutableJson({...previous.plan,kind:'source-bound-genuine-finance-remaining-successor-preparation',preparedAt,
  projectId:PROJECT,bundleSha256:BUNDLE,sourceBindings,priorEvidenceBindings,
  previousRemainingPlan:PREVIOUS_ATTEMPT.plan,previousAttempt:PREVIOUS_ATTEMPT,
  previousStopValidation:previous.validation,preservedOriginalRemainingSourceBindings:true,
  evidenceRoots:{executionRoot:EXECUTION_ROOT,publicCashEvidenceRoot:PUBLIC_EVIDENCE_ROOT},
  publicCashBindings:CASH_PUBLIC_BINDINGS,installedCashPatch:CASH_PATCH,installedCashValidation:cashValidation,
  historicalInstallationEvidenceDoesNotReplaceFreshRuntimePreflight:true,personalHumanExactSourceSignatureClaimed:false,
  priorRequestBound:PRIOR_REQUEST_BOUND,priorRequestBoundBreakdown:{firstAttemptConservativeReserve:40,
   firstAttemptObservedCount:null,resumeObservedAttempts:35,stoppedA2ReadOnlyAttempts:3},
  maximumRemainingOrdinaryAttempts:71,maximumTotalWorkflowRequestAttempts:150,oneReadOnlyResolutionAttemptReserved:true,
  maximumExecutionMs:900000,maximumManagementOrActualTransportTimeoutMs:45000,networkCallsDuringPreparation:0,
  oldConsumedIntentMustRemainUnchanged:true,newOnceIntentPath:REMAINING_ONCE,
  priorStopAndConsumedIntentValidatedBeforeNewIntentSelection:true,preflightResponsesPersistedBeforeValidation:true,
  preflightResponseRawSha256AndRequestSqlSha256Persisted:true,invalidPreflightRowsPersistedBeforeStop:true,
  installedFunctionMd5Bindings:REMAINING_FUNCTION_MD5,
  known40And55SqlstateRequiresExactMessageAndHttp500:true,
  installedCashDateConflict:{sqlstate:'PT409',httpStatus:409,
   exactMessages:['CASH_DATE_VERSION_CONFLICT','CASH_DATE_PROPOSAL_CHANGED','CASH_DATE_SOURCE_CHANGED']},
  oldCustomCashDate40001FormsRejected:true,unrelatedPt409MessagesRejected:true,
  preparationIsReadOnlyAndDoesNotSelectExecutionIntent:true,independentReviewRequired:true,
  actualRuntimeVerification:false,authenticatedNative:false,targetScaleLoad:false,ownerAcceptance:false,
  fullFinanceAndCashGatesComplete:false,production:false,realBilling:false});
 validateRemainingPreparationPlan(plan);validatePreservedRemainingBindings(plan,previous.plan);return plan;
}

export async function prepareRemainingFinance(){
 await verifyRemainingRoots();validateRemainingActualDay(Date.now());
 const {review}=await loadApprovedInputs();validateFinanceFixture(review);
 const previous=await loadConsumedRemainingAttempt(),cash=await loadCashPatchEvidence();
 const sourceBindings=[];
 for(const binding of [...previous.plan.sourceBindings,...Object.values(PREVIOUS_ATTEMPT)]){
  await readExactRemainingFile(EXECUTION_ROOT,binding);
  const existing=sourceBindings.find(value=>value.path===binding.path);
  must(!existing||existing.sha256===binding.sha256,'PRESERVED_REMAINING_BINDING_COLLISION');
  if(!existing)sourceBindings.push({path:binding.path,sha256:binding.sha256});
 }
 for(const file of REMAINING_DIRECT_SOURCES){
  const exact=path.resolve(root,file);must(path.resolve(await fs.realpath(exact))===exact,'REMAINING_PUBLIC_FILE_REDIRECTION_FORBIDDEN');
  must(!sourceBindings.some(binding=>binding.path===file),'NEW_REMAINING_SOURCE_COLLISION');
  sourceBindings.push({path:file,sha256:hashBytes(await fs.readFile(exact))});
 }
 const plan=buildRemainingPreparation({previous,sourceBindings,cashValidation:cash.validation,preparedAt:new Date().toISOString()});
 const bytes=JSON.stringify(plan,null,2)+'\n',handle=await fs.open(path.join(root,REMAINING_PLAN),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {prepared:true,evidence:{path:REMAINING_PLAN,sha256:hashBytes(bytes)},sourceBindings:sourceBindings.length,
  publicCashBindings:CASH_PUBLIC_BINDINGS.length,priorRequestBound:PRIOR_REQUEST_BOUND,oldConsumedIntentPreserved:true,
  newExecutionIntentSelected:false,liveOperations:0};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv.length>2){process.stderr.write(JSON.stringify({failureCode:'FIXED_REMAINING_PREPARATION_MODE_REQUIRED'})+'\n');process.exitCode=1;}
 else prepareRemainingFinance().then(result=>process.stdout.write(JSON.stringify(result)+'\n')).catch(error=>{
  process.stderr.write(JSON.stringify({failureCode:error.publicCode??'REMAINING_PREPARATION_FAILED',privateErrorPrinted:false})+'\n');process.exitCode=1;});
}
