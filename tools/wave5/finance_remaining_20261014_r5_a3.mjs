import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport,decodePublicResult } from './approved_management_installer.mjs';
import { hashBytes,hashJson,isUuid,immutableJson } from './runtime_contract.mjs';
import { runtimeSealKey,appendRuntimeSecret } from './private_runtime_seal.mjs';
import { createPrivateKeyReader,selectExistingLegacyKeys } from './private_runtime_http.mjs';
import { existingActorSession } from './private_existing_actor_session_20261013_r5.mjs';
import { FINANCE_SCOPE as scope,FINANCE_CALENDAR as calendar,FINANCE_EXPECTED as expected,FINANCE_JOURNALS,validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';
import { financeWorkflowId as id,FINANCE_SCOPED_BODY,FINANCE_FACTS_SQL,receiptResolutionSql,sameFinanceJson } from './finance_cash_workflows_20261013_r5.mjs';
import { createFinanceHttpsTransport,financeDenial as legacyFinanceDenial,encodeFinanceCsv } from './finance_https_transport_20261013_r5_a2.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
export const EXECUTION_ROOT='C:/Users/sheha/Desktop/Jentra OS/build/wave5-approved-execution-20261013-r5-a2';
export const PUBLIC_EVIDENCE_ROOT='C:/Users/sheha/Desktop/Jentra OS';
export const REMAINING_PLAN=base+'finance-remaining-preparation-20261014-r5-a3.json';
export const REMAINING_ONCE=base+'finance-remaining-once-20261014-r5-a3.json';
export const PREVIOUS_ATTEMPT=immutableJson({
 plan:{path:base+'finance-remaining-preparation-20261013-r5-a2.json',sha256:'a7153af4d8585bee09ff9d9e17274f6aa847345e294a503475b9b6393414a456'},
 stop:{path:base+'genuine-finance-finance-20261013-r5-1791914813606/99-stop.json',sha256:'67e58a93c90471dbd7c32b7be6ee194e8b0dc50fb98c5701a38599cd6dd5246e'},
 once:{path:base+'finance-remaining-once-20261013-r5.json',sha256:'ec27f49a0cd76e792b70a256e79edad5f858373c7d4c71cd9ec027c5a5ef8919'}});
export const CASH_PATCH=immutableJson({sourceSha256:'99cd801ba156872fb8f6346cc74e667ef9398e3628f466ae0ff44f37b7fdf520',
 migrationVersion:'20261013184757',migrationName:'wave5_cash_conflict_http409_20261014_r5',
 functions:{wave5_cash_date_command:{beforeDefinitionMd5:'420fd1eb3fb3cf509d53ffc0e71701d0',definitionMd5:'1073f011cc41fd591ae30e37fee6f411',
  beforeBodyLfSha256:'509d9f2ef975ca30a355b6874603e1469564107eed911267454de54607e4a149',bodyLfSha256:'9c87b6aaf874e0a5061b7710b9341240ba982fc26731fe1e99f00646039bf482'},
 wave5_cash_save_v2:{beforeDefinitionMd5:'5dc4e9c4606ae3cc691c6041b6ec2e14',definitionMd5:'e176615ccb065549bf682467e89364f0',
  beforeBodyLfSha256:'a9e13fb88a940206bb7fc9d804f5dafd591fea5dce138a688f251fb5be684c91',bodyLfSha256:'98c96ad97956117996c8874d2ff8e1e7e69d827e72f71757c68034d1e5780564'}}});
export const CASH_PUBLIC_BINDINGS=immutableJson([
 {role:'source',path:'supabase/candidates/wave5_cash_conflict_http409_20261013_r5.sql',sha256:CASH_PATCH.sourceSha256},
 {role:'technical-decision',path:base+'cash-conflict-delegated-operation-decision-20261014-r5.json',sha256:'2e75d94f073fdf941827786f07451e13d7448aae0bdef90cf8d9aa0243503bdf'},
 {role:'installation-once',path:base+'cash-conflict-installation-once-intent-20261014-r5.json',sha256:'10282167e4b8aab6139384fd5cf3386dee419e9c290e05e67aa0c44552786c42'},
 {role:'quiescence-before-installation',path:base+'cash-conflict-immediate-quiescence-before-installation-20261014-r5.json',sha256:'5e10d2c62b6431049c9b49aa81c703342eb42ff23456bcefceed125d759d31f5'},
 {role:'installation-response',path:base+'cash-conflict-actual-installation-response-20261014-r5.json',sha256:'5f12ecc7dc13e5bcb5e6b978c7ca83fb2eb11f21a4c06795915b108fd51e647b'},
 {role:'before-installation',path:base+'cash-conflict-live-before-installation-20261014-r5.json',sha256:'8e4b7e2b2774730059f37032a11d86d1410008fa6db3713ab4b52f8f0b0b6246'},
 {role:'after-installation',path:base+'cash-conflict-live-after-installation-20261014-r5.json',sha256:'8e421753b5d948c50656cacaab30ef2686c7378ca308598e5c88be76890ad134'},
 {role:'migration-ledger',path:base+'cash-conflict-actual-migration-ledger-20261014-r5.json',sha256:'f88f04d2bf9e6734af199fef6c9ac3d9b5e2f9340cc239282d6cc3fb8aae634c'},
 {role:'independent-readback',path:base+'task3-completion-20261013/installed-cash-independent-readback-20261014.json',sha256:'b90d5514a3d602de970637ab06132eaec3728143433e03985b9e96449bc9fbf3'},
 {role:'independent-verification',path:base+'task3-completion-20261013/installed-cash-independent-verification-20261014.json',sha256:'613e3f2871e023532a595c6fefec008def556dc579a92baa78b56991efbf55cf'}]);
export const PRIOR_FINANCE=base+'genuine-finance-finance-20261013-r5-1791894738890/';
export const ORIGINAL_PLAN=base+'finance-cash-workflow-preparation-20261013-r5-a3.json';
export const ORIGINAL_SOURCE_HASH='ff90ee8cb1e1a33982eedfc1d05a8b8118a463d8e2bd9a36ac9f1469eb40be38';
export const CURRENT_WHOLE_SOURCE_HASH='6419aa1d51407cd016915da47a56ae28f5f3f50458c562b011e2b16da54bccb3';
export const STALE_COMMAND='92e523de-6d82-d54a-0bfe-e81a78593a96';
export const STALE_PROPOSAL='8337ca68-2add-d88a-a198-9019b10235cc';
export const PRIOR_REQUEST_BOUND=78; // 40 conservative + 35 resumed + 3 observed a2 read-only attempts.
export const REMAINING_KINDS=Object.freeze(['payroll_correction','project_reimbursement']);
export const REMAINING_RPCS=Object.freeze(['wave5_cash_date_sources','wave5_cash_date_get','wave5_cash_date_command',
 'report_export_preview','record_report_export','wave5_export_reopen','financial_statement_page']);
export const REMAINING_FUNCTION_MD5=Object.freeze({financial_statement_page:'411a49de3b16cb18743d1388fe4e6d7f',
 record_report_export:'8c27c35f2d47803cb9f213a35d2bb935',report_export_preview:'6add0cd5eee10a4dfea120608e73a625',
 wave5_cash_date_command:'1073f011cc41fd591ae30e37fee6f411',wave5_cash_date_get:'9cffa55ebb5785b32c9028cb87c31f12',
 wave5_cash_date_sources:'8e788ef2aeecdfd6ade8bb9347840a82',wave5_export_reopen:'0480817ae2c4fc0957c1d95051ef293f'});
const statementKinds=['profit_loss','balance_sheet','trial_balance'];
export const EXPECTED_PROCESS_APPENDS=immutableJson([
 ...statementKinds.map(kind=>({commandId:id('command.statement.'+kind),documentId:id('statement.'+kind),documentType:'financial_statement_report',
  toStatus:'generated',actorId:'8b740ab8-24f7-4455-a78b-aea0d99d20f6'})),
 ...['pipeline','statement'].map(label=>({commandId:id('command.export.'+label),documentId:id('export.'+label),documentType:'report_export',
  toStatus:'registered',actorId:'8b740ab8-24f7-4455-a78b-aea0d99d20f6'}))]);
const commandList=EXPECTED_PROCESS_APPENDS.map(row=>`'${row.commandId}'::uuid`).join(',');
const processClause=`FROM workflow.process_events x WHERE tenant_id='${scope.tenantId}'`;
must(FINANCE_FACTS_SQL.split(processClause).length===2,'FROZEN_FINANCE_HASH_RECIPE_REQUIRED');
export const REMAINING_BASELINE_SQL=FINANCE_FACTS_SQL.replace(processClause,processClause+` AND command_id NOT IN (${commandList})`);
export const REMAINING_PRIOR_COMPLETE_SQL=FINANCE_FACTS_SQL.replace(processClause,processClause+` AND command_id NOT IN (${EXPECTED_PROCESS_APPENDS.slice(3).map(row=>`'${row.commandId}'::uuid`).join(',')})`);
// Exact identifiers, including their boundaries, avoid treating other_api or
// a differently quoted identifier as the reviewed API schema/function.
export const REMAINING_ACTIVITY_PATTERN='(^|[^[:alnum:]_$"])("api"|api)[[:space:]]*[.][[:space:]]*("wave5_cash_date_command"|wave5_cash_date_command)[[:space:]]*[(]';
export const REMAINING_ACTIVITY_SQL=`SELECT jsonb_build_object('observedAt',statement_timestamp()::text,
 'staleReceipts',(SELECT count(*) FROM core.command_receipts WHERE tenant_id='${scope.tenantId}' AND command_id='${STALE_COMMAND}'),
 'staleProposals',(SELECT count(*) FROM analytics.cash_date_proposals WHERE tenant_id='${scope.tenantId}' AND id='${STALE_PROPOSAL}'),
 'activeCashApiInvocations',(SELECT count(*) FROM pg_stat_activity WHERE usename='authenticator' AND state='active' AND pid<>pg_backend_pid()
  AND query ~ '${REMAINING_ACTIVITY_PATTERN}' AND position('pg_stat_activity' in query)=0),
 'originalProcessRows',(SELECT count(*) FROM workflow.process_events WHERE tenant_id='${scope.tenantId}' AND command_id NOT IN (${commandList})),
 'processAppends',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'commandId',command_id,'documentId',document_id,
  'documentType',document_type,'toStatus',to_status,'actorId',actor_id,'fromStatus',from_status) ORDER BY command_id),'[]')
  FROM workflow.process_events WHERE tenant_id='${scope.tenantId}' AND command_id IN (${commandList}))) AS observation`;
export const REMAINING_FUNCTIONS_SQL=`SELECT proname,md5(pg_get_functiondef(p.oid)) AS definition_md5 FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api' AND p.proname IN (${Object.keys(REMAINING_FUNCTION_MD5).map(k=>`'${k}'`).join(',')}) ORDER BY proname`;

const fixedRoot=value=>typeof value==='string'?path.win32.resolve(value).toLowerCase():null;
export function validateRemainingRoots(executionRoot,publicEvidenceRoot){
 must(fixedRoot(executionRoot)===fixedRoot(EXECUTION_ROOT)&&fixedRoot(publicEvidenceRoot)===fixedRoot(PUBLIC_EVIDENCE_ROOT),
  'EXACT_REMAINING_EVIDENCE_ROOTS_REQUIRED');
}
export function validateRemainingActualDay(value){
 const date=new Date(value);must(Number.isFinite(date.getTime())&&date.toISOString().slice(0,10)===calendar.fixtureDay,
  'EXACT_REMAINING_ACTUAL_DAY_REQUIRED');
}
export async function verifyRemainingRoots(){
 validateRemainingRoots(root,PUBLIC_EVIDENCE_ROOT);
 validateRemainingRoots(await fs.realpath(EXECUTION_ROOT),await fs.realpath(PUBLIC_EVIDENCE_ROOT));
}
export async function readExactRemainingFile(evidenceRoot,binding){
 must([fixedRoot(EXECUTION_ROOT),fixedRoot(PUBLIC_EVIDENCE_ROOT)].includes(fixedRoot(evidenceRoot))
  &&typeof binding?.path==='string'&&/^[a-zA-Z0-9_./-]+$/.test(binding.path)&&!binding.path.includes('..')
  &&!path.win32.isAbsolute(binding.path)&&/^[a-f0-9]{64}$/.test(binding.sha256),'FIXED_REMAINING_PUBLIC_BINDING_REQUIRED');
 const file=path.resolve(evidenceRoot,binding.path),resolved=await fs.realpath(file);
 must(fixedRoot(resolved)===fixedRoot(file),'REMAINING_PUBLIC_FILE_REDIRECTION_FORBIDDEN');
 const bytes=await fs.readFile(file);must(hashBytes(bytes)===binding.sha256,'REMAINING_SOURCE_OR_EVIDENCE_DRIFT');return bytes;
}
export function validateConsumedRemainingAttempt({stop,once,priorPlan}){
 must(priorPlan?.kind==='source-bound-genuine-finance-remaining-preparation'&&priorPlan.projectId===PROJECT
  &&priorPlan.bundleSha256===BUNDLE&&priorPlan.priorRequestBound===75&&priorPlan.maximumTotalWorkflowRequestAttempts===150
  &&priorPlan.oneReadOnlyResolutionAttemptReserved===true&&priorPlan.maximumExecutionMs===900000
  &&priorPlan.maximumManagementOrActualTransportTimeoutMs===45000&&priorPlan.networkCallsDuringPreparation===0
  &&priorPlan.actualClockDateRequired===calendar.fixtureDay&&Array.isArray(priorPlan.sourceBindings)
  &&Array.isArray(priorPlan.priorEvidenceBindings),'EXACT_PRESERVED_A2_PLAN_REQUIRED');
 must(stop?.kind==='genuine-finance-remaining-stop'&&stop.phase==='fresh-quiescent-original-preflight'
  &&stop.failureCode==='ORIGINAL_CASH_UNCERTAINTY_MUST_BE_QUIESCENT'&&stop.priorRequestBound===75
  &&stop.actualRemainingAttempts===3&&stop.totalRequestBound===PRIOR_REQUEST_BOUND
  &&stop.previousFirstAttemptObservedRequests===null&&stop.previousFirstAttemptConservativeReserve===40
  &&stop.previousResumeObservedRequests===35&&Array.isArray(stop.completed)&&stop.completed.length===0
  &&stop.lastOriginalCommand===null&&stop.resolution===null&&stop.staleOriginalCommandId===STALE_COMMAND
  &&stop.staleOriginalCommandReplayed===false&&stop.automaticRetryPerformed===false&&stop.privateErrorPrinted===false
  &&stop.liveGateComplete===false,'EXACT_CONSUMED_A2_READONLY_STOP_REQUIRED');
 must(once?.kind==='once-only-remaining-finance-intent'&&once.projectId===PROJECT&&once.bundleSha256===BUNDLE
  &&once.planSha256===PREVIOUS_ATTEMPT.plan.sha256&&once.priorRequestBound===75
  &&once.directory===base+'genuine-finance-finance-20261013-r5-1791914813606/'
  &&once.staleOriginalCommandPreserved===STALE_COMMAND&&once.retryOrReplayOfStaleForbidden===true
  &&once.successfulPriorWorkWillNotBeRepeated===true
  &&sameFinanceJson(once.mutationKinds,['remaining-two-payment-date-commands','two-governed-csv-export-registrations'])
  &&Number.isFinite(Date.parse(once.actualStartedAt))&&Number.isFinite(Date.parse(stop.actualStoppedAt))
  &&Date.parse(stop.actualStoppedAt)>=Date.parse(once.actualStartedAt)
  &&Date.parse(stop.actualStoppedAt)-Date.parse(once.actualStartedAt)<=900000,'EXACT_CONSUMED_A2_ONCE_REQUIRED');
 return {priorRequestBound:PRIOR_REQUEST_BOUND,observedReadOnlyAttempts:3,completedCommands:0,pendingCommand:null,
  resolution:null,consumedIntentPreserved:true,newIntentSelectionAllowedOnlyForThisBoundSuccessor:true};
}
export async function loadConsumedRemainingAttempt(){
 const values={};for(const [name,binding]of Object.entries(PREVIOUS_ATTEMPT))values[name]=JSON.parse(await readExactRemainingFile(EXECUTION_ROOT,binding));
 const validation=validateConsumedRemainingAttempt({stop:values.stop,once:values.once,priorPlan:values.plan});
 return {...values,validation};
}
export function validateCashPatchEvidence(documents){
 const get=role=>documents[role];
 const decision=get('technical-decision'),intent=get('installation-once'),installation=get('installation-response');
 must(decision?.kind==='delegated-technical-cash-conflict-operation-decision'&&decision.decision==='approve_scoped_development_repair'
  &&decision.projectId===PROJECT&&decision.sourceSha256===CASH_PATCH.sourceSha256
  &&decision.authority?.kind==='direct_human_delegation_verified_with_read_thread'&&decision.personalHumanExactSourceSignatureClaimed===false,
  'EXACT_INSTALLED_CASH_TECHNICAL_DECISION_REQUIRED');
 for(const value of [intent,installation])must(value?.projectId===PROJECT&&value.sourceSha256===CASH_PATCH.sourceSha256
  &&value.migrationName===CASH_PATCH.migrationName&&value.automaticRetry===false
  &&value.personalHumanExactSourceSignatureClaimed===false,'EXACT_CASH_INSTALLATION_BINDING_REQUIRED');
 must(decodePublicResult(installation.result)?.success===true,'ACTUAL_CASH_INSTALLATION_SUCCESS_REQUIRED');
 const ledger=decodePublicResult(get('migration-ledger')?.result);
 must(sameFinanceJson(ledger,[{version:CASH_PATCH.migrationVersion,name:CASH_PATCH.migrationName}]),'EXACT_INSTALLED_CASH_LEDGER_REQUIRED');
 const historical=decodePublicResult(get('quiescence-before-installation')?.result);
 must(Array.isArray(historical)&&historical.length===1,'EXACT_HISTORICAL_CASH_QUIESCENCE_REQUIRED');
 validateRemainingQuiescence(historical[0].observation);
 const before=decodePublicResult(get('before-installation')?.result),after=decodePublicResult(get('after-installation')?.result);
 const independent=decodePublicResult(get('independent-readback')?.result);
 must(Array.isArray(before)&&before.length===2&&Array.isArray(after)&&after.length===2
  &&Array.isArray(independent)&&independent.length===1&&independent[0].installed_migrations===115&&independent[0].api_functions===363
  &&Array.isArray(independent[0].repaired_routines)&&independent[0].repaired_routines.length===2,
  'EXACT_INSTALLED_CASH_READBACK_REQUIRED');
 const review=get('independent-verification');
 must(review?.kind==='independent-installed-cash-source-review'&&review.projectId===PROJECT&&review.sourceRepairInstalled===true
  &&review.businessCommandsExecutedByReviewer===0&&review.uncertainOriginalCommandPreserved===true
  &&review.actualNewHttpConflictVerified===false&&review.productionReleaseReady===false
  &&Array.isArray(review.routines)&&review.routines.length===2,'EXACT_INDEPENDENT_CASH_VERIFICATION_REQUIRED');
 for(const [name,expected]of Object.entries(CASH_PATCH.functions)){
  const old=before.filter(row=>row.proname===name),fresh=after.filter(row=>row.proname===name);
  const readback=independent[0].repaired_routines.filter(row=>row.proname===name),verified=review.routines.filter(row=>row.name===name);
  must(old.length===1&&fresh.length===1&&readback.length===1&&verified.length===1
   &&old[0].definition_md5===expected.beforeDefinitionMd5&&old[0].body_lf_sha256===expected.beforeBodyLfSha256
   &&fresh[0].definition_md5===expected.definitionMd5&&fresh[0].body_lf_sha256===expected.bodyLfSha256
   &&readback[0].definition_md5===expected.definitionMd5&&readback[0].body_lf_sha256===expected.bodyLfSha256
   &&verified[0].definitionMd5===expected.definitionMd5&&verified[0].bodyLfSha256===expected.bodyLfSha256
   &&verified[0].allNonBodyMetadataPreserved===true&&old[0].preserved_metadata
   &&sameFinanceJson(old[0].preserved_metadata,fresh[0].preserved_metadata)
   &&sameFinanceJson(old[0].preserved_metadata,readback[0].preserved_metadata),
   'EXACT_INSTALLED_CASH_BODY_AND_METADATA_REQUIRED');
 }
 must(sameFinanceJson(independent[0].reviewed_schedule_state,[{jobid:4,active:false},{jobid:5,active:false},{jobid:6,active:false}]),
  'PRESERVED_PAUSED_SCHEDULE_EVIDENCE_REQUIRED');
 return {migrationVersion:CASH_PATCH.migrationVersion,cashDateDefinitionMd5:CASH_PATCH.functions.wave5_cash_date_command.definitionMd5,
  historicalInstallationReadbackVerified:true,freshRuntimeQuiescenceStillRequired:true,personalHumanExactSourceSignatureClaimed:false};
}
export async function loadCashPatchEvidence(){
 const documents={};for(const binding of CASH_PUBLIC_BINDINGS){const bytes=await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,binding);
  if(binding.role!=='source')documents[binding.role]=JSON.parse(bytes);}
 return {documents,validation:validateCashPatchEvidence(documents)};
}
// Only the installed date-command's three custom conflicts change mapping.
// The old 40001 forms and unrelated PT409 messages remain unknown failures.
export function financeDenial(response){
 const dateConflicts=['CASH_DATE_VERSION_CONFLICT','CASH_DATE_PROPOSAL_CHANGED','CASH_DATE_SOURCE_CHANGED'];
 const {code,message}=response?.value??{};
 if(dateConflicts.includes(message))return response?.ok===false&&code==='PT409'&&response.status===409?message:null;
 return legacyFinanceDenial(response);
}
export async function persistRemainingPreflightResponse({persist,file,query,response}){
 must(typeof persist==='function'&&/^[a-zA-Z0-9_-]+\.json$/.test(file)&&typeof query==='string','EXACT_PREFLIGHT_PERSISTENCE_REQUIRED');
 const sha=response?.responseSha256,rows=Array.isArray(response?.value)?response.value:null;
 const evidence=await persist(file,{kind:'read-only-remaining-preflight-response',querySha256:hashBytes(query),
  status:Number.isSafeInteger(response?.status)?response.status:null,responseSha256:typeof sha==='string'&&/^[a-f0-9]{64}$/.test(sha)?sha:null,
  responseBytes:Number.isSafeInteger(response?.responseBytes)?response.responseBytes:null,rows,validationPending:true,
  privateErrorBodyPublished:false,originalStaleCommandReplayed:false});
 must(typeof evidence?.path==='string'&&/^[a-f0-9]{64}$/.test(evidence.sha256),'ACKNOWLEDGED_PREFLIGHT_EVIDENCE_REQUIRED');
 must([200,201].includes(response?.status)&&rows!==null&&typeof sha==='string'&&/^[a-f0-9]{64}$/.test(sha),
  'ACTUAL_REMAINING_READONLY_RESPONSE_REQUIRED');return evidence;
}

export function validateRemainingQuiescence(observation){
 must(observation?.staleReceipts===0&&observation.staleProposals===0&&observation.activeCashApiInvocations===0,
  'ORIGINAL_CASH_UNCERTAINTY_MUST_BE_QUIESCENT');
}
export function validateRemainingState(facts,observation,{after=false,wholeSourceHash,priorCompleteSourceHash}={}){
 const dateCount=after?3:1,exportCount=after?2:0,appendCount=after?5:3;
 must(facts?.sourceHash===ORIGINAL_SOURCE_HASH&&facts.journals===9&&facts.lines===18
  &&sameFinanceJson(facts.journalIds,FINANCE_JOURNALS.map(j=>j.id).sort())&&facts.publications===3&&facts.classifications===1
  &&facts.dateProposals===dateCount&&facts.dateDecisions===dateCount&&facts.scenarios===0&&facts.exports===exportCount,'EXACT_REMAINING_FINANCE_STATE_REQUIRED');
 validateRemainingQuiescence(observation);
 must(observation.originalProcessRows===4&&Array.isArray(observation.processAppends)&&observation.processAppends.length===appendCount,
  'ORIGINAL_CASH_UNCERTAINTY_MUST_BE_QUIESCENT');
 const wanted=EXPECTED_PROCESS_APPENDS.slice(0,appendCount);
 for(const row of wanted){const matches=observation.processAppends.filter(event=>event.commandId===row.commandId);
  must(matches.length===1&&isUuid(matches[0].id)&&matches[0].fromStatus===null
   &&Object.entries(row).every(([key,value])=>matches[0][key]===value),'EXACT_LEGITIMATE_PROCESS_APPEND_REQUIRED');}
 must(new Set(observation.processAppends.map(e=>e.id)).size===appendCount,'UNIQUE_PROCESS_APPEND_IDENTITIES_REQUIRED');
 if(!after)must(wholeSourceHash===CURRENT_WHOLE_SOURCE_HASH,'CURRENT_RAW_FINANCE_SOURCE_REQUIRED');
 else must(priorCompleteSourceHash===CURRENT_WHOLE_SOURCE_HASH&&typeof wholeSourceHash==='string'&&/^[a-f0-9]{64}$/.test(wholeSourceHash)&&wholeSourceHash!==CURRENT_WHOLE_SOURCE_HASH,
  'EXPORT_PROCESS_APPEND_RAW_DIGEST_REQUIRED');
 return {originalBaselineHash:ORIGINAL_SOURCE_HASH,wholeSourceHash,originalProcessRows:4,documentedProcessAppends:appendCount};
}
export function validateRemainingFunctions(rows){
 must(Array.isArray(rows)&&rows.length===Object.keys(REMAINING_FUNCTION_MD5).length,'EXACT_REMAINING_INSTALLED_FUNCTIONS_REQUIRED');
 for(const [name,md5]of Object.entries(REMAINING_FUNCTION_MD5))must(rows.filter(row=>row.proname===name&&row.definition_md5===md5).length===1,
  'REMAINING_INSTALLED_FUNCTION_SOURCE_DRIFT');
}
export function validateRemainingReplay(prepared,replayed){
 must(prepared?.ok===true&&replayed?.ok===true&&sameFinanceJson(prepared.value,replayed.value)
  &&typeof prepared.responseSha256==='string'&&/^[a-f0-9]{64}$/.test(prepared.responseSha256)
  &&prepared.responseSha256===replayed.responseSha256,'ACTUAL_ORIGINAL_REMAINING_DATE_REPLAY_REQUIRED');
 return {canonicalFullValueIdentical:true,rawResponseSha256Identical:true,
  originalPreparedResponseSha256:prepared.responseSha256,originalReplayResponseSha256:replayed.responseSha256};
}
export function createRemainingBudget({now=Date.now,startedAt=now(),priorRequestBound=PRIOR_REQUEST_BOUND}={}){
 must(typeof now==='function'&&priorRequestBound===PRIOR_REQUEST_BOUND&&Number.isFinite(startedAt),'EXACT_REMAINING_REQUEST_RESERVE_REQUIRED');let attempted=0,resolutionAttempted=false;
 return Object.freeze({claim({resolution=false}={}){
  const elapsed=now()-startedAt;must(Number.isFinite(elapsed)&&elapsed>=0&&elapsed<=900000-45000,'REMAINING_EXECUTION_DEADLINE_REQUIRED');
  must(!resolution||!resolutionAttempted,'SINGLE_ORIGINAL_READONLY_RESOLUTION_REQUIRED');
  must(priorRequestBound+attempted+1<=(resolution?150:149),'REMAINING_REQUEST_BOUND_EXCEEDED');attempted++;if(resolution)resolutionAttempted=true;
 },snapshot(){return {priorRequestBound,actualRemainingAttempts:attempted,totalRequestBound:priorRequestBound+attempted,
  previousFirstAttemptObservedRequests:null,previousFirstAttemptConservativeReserve:40,previousResumeObservedRequests:35,
  previousA2ReadOnlyAttempts:3};}});
}
export function validateRemainingCommand(name,body){
 must(name==='wave5_cash_date_command'||name==='record_report_export','FIXED_REMAINING_WRITE_REQUIRED');
 must(isUuid(body?.p_command_id)&&body.p_command_id!==STALE_COMMAND&&body.p_idempotency_key===body.p_command_id,'EXACT_REMAINING_COMMAND_IDENTITY_REQUIRED');
 const exactKeys=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&sameFinanceJson(Object.keys(value).sort(),keys.slice().sort());
 const sha=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
 const actualTime=value=>typeof value==='string'&&Number.isFinite(Date.parse(value));
 if(name==='wave5_cash_date_command'){
  must(exactKeys(body,['p_command_id','p_idempotency_key','p_issued_at','p_action','p_payload'])&&actualTime(body.p_issued_at),'EXACT_REMAINING_DATE_ENVELOPE_REQUIRED');
  must(['prepare','approve'].includes(body.p_action),'FIXED_REMAINING_DATE_ACTION_REQUIRED');
  const kind=REMAINING_KINDS.find(k=>id('date.'+k)===body.p_payload?.id);
  must(kind&&body.p_command_id===id('command.date.'+body.p_action+'.'+kind),'EXACT_REMAINING_PAYMENT_ID_REQUIRED');
  if(body.p_action==='prepare')must(exactKeys(body.p_payload,['id','sourceKind','sourceId','sourceHash','dueDate','reasonCode','expectedVersion'])
   &&body.p_payload.sourceKind===kind&&body.p_payload.sourceId===id(kind==='payroll_correction'?'payroll.recovery':'reimbursement')
   &&sha(body.p_payload.sourceHash)&&body.p_payload.expectedVersion==='0'&&body.p_payload.dueDate===calendar.dueDate
   &&body.p_payload.reasonCode===(kind==='payroll_correction'?'correction_recovery':'payment_terms'),'EXACT_REMAINING_PAYMENT_PAYLOAD_REQUIRED');
  else must(exactKeys(body.p_payload,['id','proposalHash'])&&sha(body.p_payload.proposalHash),'EXACT_REMAINING_APPROVAL_PAYLOAD_REQUIRED');
 }else{
  must(exactKeys(body,['p_command_id','p_idempotency_key','p_client_timestamp','p_expected_entity_version','p_payload'])
   &&actualTime(body.p_client_timestamp)&&body.p_expected_entity_version==='0','EXACT_REMAINING_EXPORT_ENVELOPE_REQUIRED');
  const label=['pipeline','statement'].find(k=>id('export.'+k)===body.p_payload?.id);
  must(label&&body.p_command_id===id('command.export.'+label)&&body.p_payload.source_type===(label==='pipeline'?'w5_pipeline':'statement')
   &&body.p_payload.section===(label==='pipeline'?'currencies':'accounts')&&body.p_payload.file_format==='csv'
   &&exactKeys(body.p_payload,['id','source_type','source_id','section','filters','source_hash','file_sha256','file_format','file_name','file_size','columns','prepared_at'])
   &&isUuid(body.p_payload.source_id)&&(label==='pipeline'||body.p_payload.source_id===id('statement.profit_loss'))
   &&exactKeys(body.p_payload.filters,[])&&sha(body.p_payload.source_hash)&&sha(body.p_payload.file_sha256)
   &&body.p_payload.file_name==='Jentra-W5-Synthetic-'+label+'.csv'&&Number.isSafeInteger(body.p_payload.file_size)
   &&body.p_payload.file_size>0&&body.p_payload.file_size<=10485760&&actualTime(body.p_payload.prepared_at)
   &&Array.isArray(body.p_payload.columns)&&body.p_payload.columns.length>0&&body.p_payload.columns.length<=256
   &&body.p_payload.columns.every(column=>typeof column==='string'&&column.length>0)
   &&new Set(body.p_payload.columns).size===body.p_payload.columns.length,'EXACT_REMAINING_EXPORT_REQUIRED');
 }
}
// Both intent acknowledgements must finish before dispatch. A failed append,
// response, validator or result receipt permanently stops this writer instance.
export function createRemainingCommandWriter({appendPrivate,appendPublic,send,planSha256,signal}={}){
 must([appendPrivate,appendPublic,send].every(fn=>typeof fn==='function')&&/^[a-f0-9]{64}$/.test(planSha256),'EXACT_REMAINING_COMMAND_JOURNAL_REQUIRED');
 let failed=false,busy=false,pending=null,sequence=0;
 return Object.freeze({pending(){return pending;},async write(actor,name,body,validate){
  must(!failed&&!busy&&!signal?.aborted,'REMAINING_COMMAND_JOURNAL_STOPPED');validateRemainingCommand(name,body);
  must(typeof validate==='function','REMAINING_RESPONSE_VALIDATOR_REQUIRED');
  const expectedActor=name==='wave5_cash_date_command'&&body.p_action==='approve'?'0635081d-08ea-4ad1-b7f2-ad2f8721f67d':'8b740ab8-24f7-4455-a78b-aea0d99d20f6';
  must(actor?.proof?.actorId===expectedActor&&actor.proof.aal==='aal2'&&actor.proof.onlineAuthVerified===true
   &&actor.proof.serverSessionRowVerified===true,'GENUINE_REMAINING_ACTOR_REQUIRED');
  const command=immutableJson({projectId:PROJECT,bundleSha256:BUNDLE,planSha256,actorId:actor.proof.actorId,name,body,
   commandId:body.p_command_id,idempotencyKey:body.p_idempotency_key,sequence:++sequence});busy=true;pending=command;
  try{
   const privateRecord=await appendPrivate('remaining-finance-command-intent',command);
   must(typeof privateRecord==='string'&&/^runtime-[a-z0-9-]+-[a-f0-9-]{36}\.sealed\.json$/.test(privateRecord),'ACKNOWLEDGED_PRIVATE_REMAINING_INTENT_REQUIRED');
   const intentReceipt=await appendPublic({kind:'remaining-finance-command-intent',projectId:PROJECT,bundleSha256:BUNDLE,planSha256,sequence:command.sequence,
    actorId:command.actorId,name,commandId:command.commandId,idempotencyKey:command.idempotencyKey,bodySha256:hashJson(command.body),privateRecord});
   must(typeof intentReceipt?.path==='string'&&/^[a-f0-9]{64}$/.test(intentReceipt.sha256),'ACKNOWLEDGED_PUBLIC_REMAINING_INTENT_REQUIRED');
   must(!failed&&!signal?.aborted,'REMAINING_COMMAND_JOURNAL_STOPPED');
   const response=await send(actor,name,command.body);must(response?.ok===true,'ACTUAL_REMAINING_COMMAND_RESPONSE_REQUIRED');
   validate(response.value,response);
   const resultReceipt=await appendPublic({kind:'remaining-finance-command-result',projectId:PROJECT,bundleSha256:BUNDLE,planSha256,sequence:command.sequence,
    actorId:command.actorId,name,commandId:command.commandId,transport:response.evidence,responseSha256:response.responseSha256,
    actualFinishedAt:new Date().toISOString()});
   must(typeof resultReceipt?.path==='string'&&/^[a-f0-9]{64}$/.test(resultReceipt.sha256),'ACKNOWLEDGED_PUBLIC_REMAINING_RESULT_REQUIRED');pending=null;return response;
  }catch(error){failed=true;throw error;}finally{busy=false;}
 }});
}
async function save(file,value,raw=false){const bytes=raw?value:JSON.stringify(value,null,2)+'\n',handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}return {path:file,sha256:hashBytes(bytes)};}
export function validateRemainingPreparationPlan(plan){
 must(plan?.kind==='source-bound-genuine-finance-remaining-successor-preparation'&&plan.projectId===PROJECT&&plan.bundleSha256===BUNDLE
  &&plan.priorRequestBound===PRIOR_REQUEST_BOUND&&plan.operationScopeSha256==='fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63'
  &&plan.maximumTotalWorkflowRequestAttempts===150&&plan.maximumRemainingOrdinaryAttempts===71
  &&plan.oneReadOnlyResolutionAttemptReserved===true&&plan.maximumExecutionMs===900000
  &&plan.maximumManagementOrActualTransportTimeoutMs===45000&&plan.networkCallsDuringPreparation===0
  &&plan.actualClockDateRequired===calendar.fixtureDay&&plan.preflightResponsesPersistedBeforeValidation===true
  &&plan.oldConsumedIntentMustRemainUnchanged===true&&plan.newOnceIntentPath===REMAINING_ONCE
  &&sameFinanceJson(plan.previousAttempt,PREVIOUS_ATTEMPT)&&sameFinanceJson(plan.publicCashBindings,CASH_PUBLIC_BINDINGS)
  &&sameFinanceJson(plan.installedFunctionMd5Bindings,REMAINING_FUNCTION_MD5)
  &&sameFinanceJson(plan.priorRequestBoundBreakdown,{firstAttemptConservativeReserve:40,firstAttemptObservedCount:null,resumeObservedAttempts:35,stoppedA2ReadOnlyAttempts:3})
  &&sameFinanceJson(plan.allowedWrites,{paymentDateProposals:2,independentPaymentDateApprovals:2,exactOriginalPreparedCommandReplays:2,governedCsvExportRegistrations:2})
  &&plan.originalStaleCommandId===STALE_COMMAND&&plan.originalStaleProposalId===STALE_PROPOSAL
  &&plan.replayOrRetryOfStaleForbidden===true&&plan.cashBasisScenariosAndCashExportsExcluded===true
  &&plan.actualUserJournalPosting===false&&plan.newActorOrMfaEnrollment===false&&plan.newRoleOrGrant===false
  &&plan.production===false&&plan.ownerAcceptance===false&&plan.authenticatedNative===false&&plan.targetScaleLoad===false
  &&Array.isArray(plan.sourceBindings)&&plan.sourceBindings.length>23&&Array.isArray(plan.priorEvidenceBindings)&&plan.priorEvidenceBindings.length>0
  &&plan.sourceBindings.every(source=>typeof source.path==='string'&&/^[a-zA-Z0-9_./-]+$/.test(source.path)
   &&!source.path.includes('..')&&!path.win32.isAbsolute(source.path)&&/^[a-f0-9]{64}$/.test(source.sha256))
  &&new Set(plan.sourceBindings.map(source=>source.path)).size===plan.sourceBindings.length
  &&plan.priorEvidenceBindings.every(source=>plan.sourceBindings.some(binding=>binding.path===source.path&&binding.sha256===source.sha256)),
  'EXACT_REMAINING_PREPARATION_REQUIRED');
 validateRemainingRoots(plan.evidenceRoots?.executionRoot,plan.evidenceRoots?.publicCashEvidenceRoot);
}
export const REMAINING_NEW_SOURCES=Object.freeze(['tools/wave5/finance_remaining_20261014_r5_a3.mjs',
 'tools/wave5/prepare_finance_remaining_20261014_r5_a3.mjs','tools/wave5/finance_remaining_20261014_r5_a3.test.mjs']);
export function validatePreservedRemainingBindings(plan,priorPlan){
 const expected=[...priorPlan.sourceBindings,...Object.values(PREVIOUS_ATTEMPT)].map(binding=>binding.path);
 const unique=[...new Set([...expected,...REMAINING_NEW_SOURCES])].sort();
 must(sameFinanceJson(plan.sourceBindings.map(binding=>binding.path).sort(),unique)
  &&[...priorPlan.sourceBindings,...Object.values(PREVIOUS_ATTEMPT)].every(previous=>plan.sourceBindings.some(binding=>
   binding.path===previous.path&&binding.sha256===previous.sha256)),'PRESERVED_A2_SOURCE_BINDINGS_REQUIRED');
}
export async function verifyRemainingPreparation(){
 await verifyRemainingRoots();
 const bytes=await fs.readFile(path.join(root,REMAINING_PLAN)),plan=JSON.parse(bytes);validateRemainingPreparationPlan(plan);
 const previous=await loadConsumedRemainingAttempt();validatePreservedRemainingBindings(plan,previous.plan);
 for(const source of plan.sourceBindings)await readExactRemainingFile(EXECUTION_ROOT,source);
 const cash=await loadCashPatchEvidence();
 return {plan,planSha256:hashBytes(bytes),previousAttemptValidation:previous.validation,cashPatchValidation:cash.validation};
}
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute'].includes(mode)&&process.argv.length<=3,'FIXED_REMAINING_EXECUTION_MODE_REQUIRED');
 await verifyRemainingRoots();
 const {review}=await loadApprovedInputs();validateFinanceFixture(review);const {plan,planSha256}=await verifyRemainingPreparation();
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,sourceBindings:plan.sourceBindings.length,publicCashBindings:plan.publicCashBindings.length,
  networkCalls:0,priorRequestBound:PRIOR_REQUEST_BOUND})+'\n');return;}
 validateRemainingActualDay(Date.now());
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_REMAINING_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_REMAINING_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),rawManagement=createManagementTransport(config.ownerToken,{timeoutMs:45000});
 const directory=base+'genuine-finance-remaining-20261014-r5-a3-'+Date.now()+'/',startedAt=Date.now();await fs.mkdir(path.join(root,directory));
 const budget=createRemainingBudget({startedAt}),abort=new AbortController(),deadline=setTimeout(()=>abort.abort(),900000);
 let phase='once-only-remaining-intent',transport,writer,step=0;const completed=[];
 const persist=(file,value,raw)=>save(directory+file,value,raw);
 const management=(method,suffix,body)=>{must(method==='POST'&&suffix==='/database/query'&&body?.read_only===true,'FIXED_REMAINING_READONLY_MANAGEMENT_REQUIRED');
  validateRemainingActualDay(Date.now());
  budget.claim();return rawManagement(method,suffix,body);};
 const read=async(query,{resolution=false,evidenceFile}={})=>{validateRemainingActualDay(Date.now());budget.claim({resolution});
  const result=await rawManagement('POST','/database/query',{query,read_only:true});
  if(evidenceFile)await persistRemainingPreflightResponse({persist,file:evidenceFile,query,response:result});
  must([200,201].includes(result?.status)&&Array.isArray(result.value),'ACTUAL_REMAINING_READONLY_RESPONSE_REQUIRED');return result;};
 try{
  const priorStop=JSON.parse(await fs.readFile(path.join(root,PRIOR_FINANCE+'99-stop.json'),'utf8'));
  must(priorStop.lastOriginalCommand?.commandId===STALE_COMMAND&&priorStop.failureCode==='FINANCE_TIMEOUT_UNCERTAIN'
   &&priorStop.actualRequestAttempts===35&&priorStop.priorRequestBound===40&&priorStop.automaticRetryPerformed===false,'EXACT_PRIOR_UNCERTAIN_STOP_REQUIRED');
  const priorPayroll=JSON.parse(await fs.readFile(path.join(root,PRIOR_FINANCE+'date-payroll_obligation.json'),'utf8'));
  must(priorPayroll.readback?.id===id('date.payroll_obligation')&&priorPayroll.readback.decision==='approved'
   &&priorPayroll.readback.currentApproval?.version==='1'&&priorPayroll.genuineDistinctApprover==='0635081d-08ea-4ad1-b7f2-ad2f8721f67d','PRESERVED_GENUINE_PAYROLL_APPROVAL_REQUIRED');
  const previous=await loadConsumedRemainingAttempt();validateRemainingActualDay(Date.now());
  await save(REMAINING_ONCE,{kind:'once-only-remaining-finance-successor-intent',projectId:PROJECT,bundleSha256:BUNDLE,planSha256,directory,
   actualStartedAt:new Date(startedAt).toISOString(),priorRequestBound:PRIOR_REQUEST_BOUND,previousAttempt:PREVIOUS_ATTEMPT,
   previousStopValidation:previous.validation,publicCashBindings:CASH_PUBLIC_BINDINGS,
   staleOriginalCommandPreserved:STALE_COMMAND,retryOrReplayOfStaleForbidden:true,
   successfulPriorWorkWillNotBeRepeated:true,mutationKinds:['remaining-two-payment-date-commands','two-governed-csv-export-registrations']});
  phase='fresh-quiescent-original-preflight';
  const before=(await read(REMAINING_BASELINE_SQL,{evidenceFile:'00-original-baseline-response.json'})).value[0]?.facts;
  const wholeBefore=(await read(FINANCE_FACTS_SQL,{evidenceFile:'00-whole-source-response.json'})).value[0]?.facts;
  const beforeObservation=(await read(REMAINING_ACTIVITY_SQL,{evidenceFile:'00-quiescence-response.json'})).value[0]?.observation;
  await persist('00-source-and-uncertainty-before.json',{facts:before,wholeSource:wholeBefore,observation:beforeObservation,validationPending:true,
   originalConflictHttpResponseObserved:false,staleCommandReplayed:false});
  validateRemainingState(before,beforeObservation,{wholeSourceHash:wholeBefore?.sourceHash});
  must(await fs.realpath(path.join(root,'dist'))===path.join(await fs.realpath(root),'dist'),'EXACT_REMAINING_ARTIFACT_DIRECTORY_REQUIRED');
  for(const label of ['pipeline','statement']){
   let existing=false;try{await fs.lstat(path.join(root,'dist','Jentra-W5-Synthetic-'+label+'.csv'));existing=true;}catch(error){if(error.code!=='ENOENT')throw error;}
   must(!existing,'REMAINING_EXPORT_ARTIFACT_ALREADY_EXISTS');
  }
  await persist('00-preflight-validation.json',{originalRowsPreserved:true,originalStaleCommandReplayed:false,publicEvidenceSavedBeforeValidation:true});
  const functionRows=(await read(REMAINING_FUNCTIONS_SQL,{evidenceFile:'01-installed-function-response.json'})).value;
  await persist('01-installed-function-contracts.json',{functions:functionRows,sourceMd5BindingsVerified:false,validationPending:true});
  validateRemainingFunctions(functionRows);
  await persist('01-installed-function-validation.json',{sourceMd5BindingsVerified:true,installedCashDateDefinitionMd5:REMAINING_FUNCTION_MD5.wave5_cash_date_command,
   publicCashBindings:CASH_PUBLIC_BINDINGS,historicalCashInstallationClaim:true,freshHttpConflictClaim:false});
  const clock=(await read('SELECT statement_timestamp()::text AS observed_at',{evidenceFile:'02-actual-clock-response.json'})).value[0]?.observed_at;
  must(typeof clock==='string'&&Number.isFinite(Date.parse(clock)),'EXACT_REMAINING_ACTUAL_DAY_REQUIRED');validateRemainingActualDay(clock);
  validateRemainingActualDay(Date.now());
  budget.claim();const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken,{timeoutMs:45000})()).value);
  const concrete=createFinanceHttpsTransport({apiKey:keys.anon});keys.serviceRole=null;keys.anon=null;
  transport=Object.freeze({...concrete,send(handle,route,options={}){
   if(route.startsWith('/rest/v1/rpc/'))must(REMAINING_RPCS.includes(route.split('/').at(-1)),'FIXED_REMAINING_RPC_REQUIRED');
   validateRemainingActualDay(Date.now());budget.claim();return concrete.send(handle,route,{...options,signal:abort.signal});}});
  const actors={};for(const label of ['proposer','approver','foreign-member']){phase='actual-existing-mfa-'+label;
   actors[label]=await existingActorSession({root,config,key,label,transport,management,save:persist,file:'session-'+label+'.json'});}
  const actor=actors.proposer,approver=actors.approver;
  const request=async(who,name,body)=>{must(REMAINING_RPCS.includes(name),'FIXED_REMAINING_RPC_REQUIRED');
   if(name==='wave5_cash_date_command'||name==='record_report_export'){
    const number=String(++step).padStart(3,'0');
    const observation=(await read(REMAINING_ACTIVITY_SQL,{evidenceFile:number+'-quiescence-response.json'})).value[0]?.observation;
    await persist(number+'-original-command-quiescence.json',{commandId:body.p_command_id,observation,validationPending:true,
     readOnly:true,originalStaleCommandReplayed:false,originalConflictHttpResponseObserved:false});
    validateRemainingQuiescence(observation);
   }
   const response=await who.request('/rest/v1/rpc/'+name,{...FINANCE_SCOPED_BODY,...body});
   if(!response.ok){const privateRecord=await appendRuntimeSecret(config.privateDirectory,key,'remaining-finance-response-error',{phase,name,response});
    await persist(String(++step).padStart(3,'0')+'-private-error-reference.json',{phase,name,status:response.status,denialCode:financeDenial(response),privateRecord,transport:response.evidence});}
   return response;};
  const reading=async(who,name,body)=>{phase=name;const result=await request(who,name,body);must(result.ok,'ACTUAL_REMAINING_API_READ_REQUIRED');return result;};
  writer=createRemainingCommandWriter({signal:abort.signal,planSha256,
   appendPrivate:(kind,value)=>appendRuntimeSecret(config.privateDirectory,key,kind,value),
   appendPublic:entry=>persist(String(++step).padStart(3,'0')+'-'+entry.kind+'.json',entry),send:request});
  const writing=async(who,name,body,validate)=>{phase=name;const result=await writer.write(who,name,body,validate);
   completed.push({name,commandId:body.p_command_id,actorId:who.proof.actorId});return result;};
  for(const [kind,sourceLabel,amount]of [['payroll_correction','payroll.recovery',expected.recovery],['project_reimbursement','reimbursement',expected.reimbursement]]){
   const sources=(await reading(actor,'wave5_cash_date_sources',{p_kind:kind,p_after:null})).value;
   must(sources.next===null&&sources.rows?.length===1&&sources.rows[0].sourceId===id(sourceLabel)&&sources.rows[0].sourceKind===kind
    &&sources.rows[0].remainingAmount===amount&&sources.rows[0].approved===null&&sources.rows[0].currency==='LKR','ACTUAL_REMAINING_UNAPPROVED_SOURCE_REQUIRED');
   const source=sources.rows[0],proposal=id('date.'+kind),prepareCommand=id('command.date.prepare.'+kind),approveCommand=id('command.date.approve.'+kind);
   const prepare={p_command_id:prepareCommand,p_idempotency_key:prepareCommand,p_issued_at:clock,p_action:'prepare',p_payload:{id:proposal,sourceKind:kind,
    sourceId:source.sourceId,sourceHash:source.sourceHash,dueDate:calendar.dueDate,reasonCode:kind==='payroll_correction'?'correction_recovery':'payment_terms',expectedVersion:'0'}};
   const prepared=await writing(actor,'wave5_cash_date_command',prepare,value=>must(value.command_id===prepareCommand&&value.entity?.id===proposal
    &&value.entity.status==='prepared'&&/^[a-f0-9]{64}$/.test(value.entity.proposalHash),'ACTUAL_REMAINING_DATE_PREPARATION_REQUIRED'));
   const approve={p_command_id:approveCommand,p_idempotency_key:approveCommand,p_issued_at:clock,p_action:'approve',p_payload:{id:proposal,proposalHash:prepared.value.entity.proposalHash}};
   await writing(approver,'wave5_cash_date_command',approve,value=>must(value.command_id===approveCommand&&value.entity?.id===proposal
    &&value.entity.status==='approved'&&value.entity.version==='1','ACTUAL_REMAINING_DISTINCT_DATE_APPROVAL_REQUIRED'));
   const replay=await writing(actor,'wave5_cash_date_command',prepare,(_value,replayed)=>validateRemainingReplay(prepared,replayed));
   const readback=(await reading(actor,'wave5_cash_date_get',{p_id:proposal})).value;
   must(readback.preparedBy===actor.proof.actorId&&readback.decision==='approved'&&readback.sourceId===source.sourceId&&readback.sourceHash===source.sourceHash
    &&readback.dueDate===calendar.dueDate&&readback.currentApproval?.version==='1'&&readback.currentApproval.decisionId===approveCommand
    &&readback.currentApproval.proposalHash===prepared.value.entity.proposalHash&&actor.proof.actorId!==approver.proof.actorId,'ACTUAL_REMAINING_DATE_READBACK_REQUIRED');
   await persist('date-'+kind+'.json',{source,readback,actualDistinctApprover:approver.proof.actorId,originalReplaySha256:replay.responseSha256,
    originalPreparedResponseSha256:prepared.responseSha256,originalReplayResponseSha256:replay.responseSha256,
    canonicalFullValueIdentical:true,rawResponseSha256Identical:true,
    administrativeSourceFixture:true,operationalPayrollApproval:false});
  }
  phase='actual-foreign-source-denial';const foreign=await request(actors['foreign-member'],'wave5_cash_date_sources',{p_kind:'payroll_correction',p_after:null});
  must(financeDenial(foreign)==='PERMISSION_DENIED','EXACT_ACTUAL_FOREIGN_FINANCE_DENIAL_REQUIRED');
  await persist('foreign-source-denial.json',{actorId:actors['foreign-member'].proof.actorId,denialCode:'PERMISSION_DENIED',status:foreign.status,transport:foreign.evidence});
  const fresh=await existingActorSession({root,config,key,label:'proposer',transport,management,save:persist,file:'session-proposer-reopen.json'});
  must(fresh.proof.sessionId!==actor.proof.sessionId,'ACTUAL_INDEPENDENT_REOPEN_SESSION_REQUIRED');
  const pipeline=(await read(`SELECT id FROM analytics.pipeline_forecasts WHERE tenant_id='${scope.tenantId}' AND legal_entity_id='${scope.entityId}'
   AND branch_id='${scope.branchId}' AND (evidence->>'sourceCount')::integer=2 ORDER BY observed_at DESC,id DESC LIMIT 1`)).value[0]?.id;
  must(isUuid(pipeline),'ACTUAL_EXISTING_NONEMPTY_PIPELINE_REQUIRED');
  const preparedAt=(await read('SELECT statement_timestamp()::text AS observed_at')).value[0]?.observed_at;
  must(typeof preparedAt==='string'&&Number.isFinite(Date.parse(preparedAt)),'ACTUAL_REMAINING_EXPORT_CLOCK_REQUIRED');
  const exportPreparedAt=new Date(preparedAt).toISOString();
  for(const [label,type,sourceId,section]of [['pipeline','w5_pipeline',pipeline,'currencies'],['statement','statement',id('statement.profit_loss'),'accounts']]){
   const previewBody={p_source_type:type,p_source_id:sourceId,p_section:section,p_filters:{}},preview=(await reading(actor,'report_export_preview',previewBody)).value;
   must(typeof preview.canonical_text==='string'&&hashBytes(preview.canonical_text)===preview.source_hash,'ACTUAL_REMAINING_EXPORT_PREVIEW_HASH_REQUIRED');
   const document=JSON.parse(preview.canonical_text);
   if(label==='pipeline')must(document.rows?.length===1&&document.rows[0].population===2&&document.rows[0].currency==='LKR','ACTUAL_NONEMPTY_PIPELINE_EXPORT_REQUIRED');
   else{
    const saved=JSON.parse(await fs.readFile(path.join(root,PRIOR_FINANCE+'statement-profit_loss.json'),'utf8'));
    const page=(await reading(fresh,'financial_statement_page',{p_report_id:sourceId,p_section:'accounts',p_offset:0,p_account_id:null})).value;
    must(sameFinanceJson(page.summary,saved.summary)&&page.items?.length===10&&page.next_offset===null&&sameFinanceJson(page.items,document.rows),
     'ACTUAL_FRESH_STATEMENT_SOURCE_REPRODUCTION_REQUIRED');
    await persist('statement-source-fresh-session.json',{sourceId,summary:page.summary,rowCount:page.items.length,actualSessionId:fresh.proof.sessionId,
     priorPublicationUnchanged:true,publicationRepeated:false,responseSha256:hashJson(page)});
   }
   const exportId=id('export.'+label),artifact=encodeFinanceCsv(document,{exportId,preparedAt:exportPreparedAt,sourceHash:preview.source_hash});
   const fileName='Jentra-W5-Synthetic-'+label+'.csv',artifactEvidence=await save('dist/'+fileName,artifact.bytes,true);
   const commandId=id('command.export.'+label),body={p_command_id:commandId,p_idempotency_key:commandId,p_client_timestamp:preparedAt,p_expected_entity_version:'0',
    p_payload:{id:exportId,source_type:type,source_id:sourceId,section,filters:{},source_hash:preview.source_hash,file_sha256:artifact.sha256,file_format:'csv',
     file_name:fileName,file_size:artifact.bytes.length,columns:artifact.columns,prepared_at:exportPreparedAt}};
   await writing(actor,'record_report_export',body,value=>must(value.command_id===commandId&&value.entity?.id===exportId&&value.entity.file_sha256===artifact.sha256
    &&value.entity.source_hash===preview.source_hash&&value.entity.actor_id===actor.proof.actorId,'ACTUAL_REMAINING_GOVERNED_EXPORT_REQUIRED'));
   let reopened=false;
   if(label==='pipeline'){
    const opened=(await reading(fresh,'wave5_export_reopen',{p_export_id:exportId})).value;
    must(opened.id===exportId&&opened.sourceHash===preview.source_hash&&opened.fileHash===artifact.sha256&&opened.format==='csv'&&opened.fileName===fileName
     &&hashBytes(opened.canonicalText)===opened.sourceHash,'ACTUAL_REMAINING_PIPELINE_REOPEN_REQUIRED');
    const reproduced=encodeFinanceCsv(JSON.parse(opened.canonicalText),{exportId,preparedAt:opened.preparedAt,sourceHash:opened.sourceHash});
    must(reproduced.sha256===artifact.sha256&&reproduced.bytes.equals(await fs.readFile(path.join(root,artifactEvidence.path))),'ACTUAL_REMAINING_PIPELINE_BYTES_REQUIRED');reopened=true;
   }else{
    const reproducedPreview=(await reading(fresh,'report_export_preview',previewBody)).value;
    must(reproducedPreview.source_hash===preview.source_hash&&reproducedPreview.canonical_text===preview.canonical_text,'ACTUAL_FRESH_STATEMENT_EXPORT_SOURCE_REQUIRED');
    const reproduced=encodeFinanceCsv(JSON.parse(reproducedPreview.canonical_text),{exportId,preparedAt:exportPreparedAt,sourceHash:reproducedPreview.source_hash});
    must(reproduced.sha256===artifact.sha256&&reproduced.bytes.equals(await fs.readFile(path.join(root,artifactEvidence.path))),'ACTUAL_FRESH_STATEMENT_EXPORT_BYTES_REQUIRED');
   }
   await persist('export-'+label+'.json',{exportId,sourceId,sourceType:type,artifact:artifactEvidence,fileSha256:artifact.sha256,rowCount:artifact.rowCount,
    genuineRegisteredExportReopen:reopened,genuineFreshSourceReproduction:label==='statement',actualIndependentSessionId:fresh.proof.sessionId,
    authenticatedNativeSaveDialog:false,xlsx:false,production:false});
  }
  phase='original-baseline-and-bounded-effects-after';
  const after=(await read(REMAINING_BASELINE_SQL,{evidenceFile:'98-original-baseline-response.json'})).value[0]?.facts;
  const wholeAfter=(await read(FINANCE_FACTS_SQL,{evidenceFile:'98-whole-source-response.json'})).value[0]?.facts;
  const priorCompleteAfter=(await read(REMAINING_PRIOR_COMPLETE_SQL,{evidenceFile:'98-prior-complete-response.json'})).value[0]?.facts;
  const afterObservation=(await read(REMAINING_ACTIVITY_SQL,{evidenceFile:'98-quiescence-response.json'})).value[0]?.observation;
  await persist('98-source-and-uncertainty-after.json',{facts:after,wholeSource:wholeAfter,priorCompleteSource:priorCompleteAfter,
   observation:afterObservation,validationPending:true,originalStaleCommandReplayed:false,staleOriginalDenialHttpObserved:false});
  validateRemainingState(after,afterObservation,{after:true,wholeSourceHash:wholeAfter?.sourceHash,priorCompleteSourceHash:priorCompleteAfter?.sourceHash});
  must(Date.now()-startedAt<=900000&&!abort.signal.aborted,'REMAINING_EXECUTION_DEADLINE_REQUIRED');
  await persist('98-reconciliation-validation.json',{originalBaselineHashPreserved:true,publicEvidenceSavedBeforeValidation:true,
   exactlyTwoAdditionalLegitimateExportProcessEvents:true,staleOriginalCommandStillWithoutReceiptOrProposal:true,staleOriginalDenialHttpObserved:false});
  const result={kind:'actual-genuine-finance-remaining-workflows-on-administrative-fixtures',passed:true,slice:'finance',projectId:PROJECT,bundleSha256:BUNDLE,
   continuationPlanSha256:planSha256,actualFinishedAt:new Date().toISOString(),priorSuccessfulEvidence:plan.priorEvidenceBindings,completed,
   ...budget.snapshot(),networkRequestsAttempted:budget.snapshot().actualRemainingAttempts,totalWorkflowRequestAttempts:budget.snapshot().totalRequestBound,
   previousAttemptRequestReserve:40,previousAttemptObservedRequestCount:null,previousResumedAttemptObservedRequests:35,
   previousA2ReadOnlyAttemptCount:3,previousAttempt:PREVIOUS_ATTEMPT,consumedPreviousOnceIntentPreserved:true,
   installedCashPatch:CASH_PATCH,publicCashBindings:CASH_PUBLIC_BINDINGS,preflightResponsesPersistedBeforeValidation:true,
   sourceHash:wholeAfter.sourceHash,originalBaselineSourceHash:ORIGINAL_SOURCE_HASH,rawSourceHashBefore:wholeBefore.sourceHash,wholeSourceHashUnchanged:false,
   originalBaselinePreserved:true,priorStatementRowsAndOriginalSourceHashPreserved:true,expectedPriorStatementProcessAppends:3,actualNewExportProcessAppends:2,
   actualNewPaymentDateApprovals:2,totalLinkedActualPaymentDateApprovals:3,totalLinkedActualFinancialPublications:3,totalLinkedActualClassifications:1,
   actualCsvArtifacts:2,actualGovernedExportRegistrations:2,actualIndependentSessionPipelineReopens:1,actualFreshSessionStatementReproductions:1,
   actualForeignSourceDenial:true,originalStaleCommandId:STALE_COMMAND,originalStaleCommandReplayed:false,actualStaleVersionConflictHttpResponseObserved:false,
   originalUncertainRequestCauseEstablished:false,cashBasisOrScenariosExecuted:false,blockedCashBasis:true,
   actualUserJournalPosting:false,operationalPayrollApproval:false,administrativeSourceFixture:true,authenticatedNative:false,xlsx:false,
   targetScaleLoad:false,actualDelivery:false,ownerAcceptance:false,fullFinanceAndCashGatesComplete:false,production:false,realBilling:false};
  const evidence=await persist('99-result.json',result);
  await save(base+'finance-cash-finance-completed-20261013-r5.json',{kind:'genuine-finance-phase-completion-binding',
   planSha256:hashBytes(await fs.readFile(path.join(root,ORIGINAL_PLAN))),continuationPlan:{path:REMAINING_PLAN,sha256:planSha256},
   previousAttempts:plan.priorEvidenceBindings,result:evidence,actualCompletedAt:new Date().toISOString(),cashBasisStillBlocked:true,
   staleConflictHttpResponseObserved:false,cashSuccessorSourceReviewRequired:true,cashPreflightCompatibleOnly:true,fullFinanceAndCashGatesComplete:false});
  process.stdout.write(JSON.stringify({passed:true,evidence,actualNewPaymentDateApprovals:2,actualGovernedExportRegistrations:2,
   staleConflictHttpResponseObserved:false,fullFinanceAndCashGatesComplete:false})+'\n');
 }catch(error){const pending=writer?.pending();let resolution=null;
  if(pending){try{const result=await read(receiptResolutionSql(pending.commandId),{resolution:true});resolution={commandId:pending.commandId,rows:result.value,
   responseSha256:result.responseSha256,readOnly:true,replayPerformed:false};}catch{resolution={commandId:pending.commandId,readOnlyResolutionUnavailable:true,replayPerformed:false};}}
  await persist('99-stop.json',{kind:'genuine-finance-remaining-stop',phase,failureCode:error.publicCode??'FINANCE_REMAINING_STOPPED',actualStoppedAt:new Date().toISOString(),
   completed,...budget.snapshot(),previousAttempt:PREVIOUS_ATTEMPT,publicCashBindings:CASH_PUBLIC_BINDINGS,
   oldConsumedIntentMustRemainUnchanged:true,preflightResponsesPersistedBeforeValidation:true,
   lastOriginalCommand:pending?{name:pending.name,commandId:pending.commandId,actorId:pending.actorId}:null,resolution,
   staleOriginalCommandId:STALE_COMMAND,staleOriginalCommandReplayed:false,privateErrorPrinted:false,automaticRetryPerformed:false,liveGateComplete:false});throw error;
 }finally{clearTimeout(deadline);abort.abort();transport?.close();key.fill(0);config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'FINANCE_REMAINING_STOPPED',privateErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;});
