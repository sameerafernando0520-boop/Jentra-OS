import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport } from './approved_management_installer.mjs';
import { hashBytes,hashJson,isUuid,immutableJson } from './runtime_contract.mjs';
import { runtimeSealKey,appendRuntimeSecret } from './private_runtime_seal.mjs';
import { createPrivateKeyReader,selectExistingLegacyKeys } from './private_runtime_http.mjs';
import { existingActorSession } from './private_existing_actor_session_20261013_r5.mjs';
import { FINANCE_SCOPE as scope,FINANCE_CALENDAR as calendar,FINANCE_EXPECTED as expected,FINANCE_JOURNALS,validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';
import { financeWorkflowId as id,FINANCE_SCOPED_BODY,FINANCE_FACTS_SQL,receiptResolutionSql,sameFinanceJson } from './finance_cash_workflows_20261013_r5.mjs';
import { createFinanceHttpsTransport,financeDenial,encodeFinanceCsv } from './finance_https_transport_20261013_r5_a2.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
export const REMAINING_PLAN=base+'finance-remaining-preparation-20261013-r5-a1.json';
export const PRIOR_FINANCE=base+'genuine-finance-finance-20261013-r5-1791894738890/';
export const ORIGINAL_PLAN=base+'finance-cash-workflow-preparation-20261013-r5-a3.json';
export const ORIGINAL_SOURCE_HASH='ff90ee8cb1e1a33982eedfc1d05a8b8118a463d8e2bd9a36ac9f1469eb40be38';
export const CURRENT_WHOLE_SOURCE_HASH='6419aa1d51407cd016915da47a56ae28f5f3f50458c562b011e2b16da54bccb3';
export const STALE_COMMAND='92e523de-6d82-d54a-0bfe-e81a78593a96';
export const STALE_PROPOSAL='8337ca68-2add-d88a-a198-9019b10235cc';
export const PRIOR_REQUEST_BOUND=75; // 40 conservative first-attempt reserve + 35 observed resumed attempts.
export const REMAINING_KINDS=Object.freeze(['payroll_correction','project_reimbursement']);
export const REMAINING_RPCS=Object.freeze(['wave5_cash_date_sources','wave5_cash_date_get','wave5_cash_date_command',
 'report_export_preview','record_report_export','wave5_export_reopen','financial_statement_page']);
export const REMAINING_FUNCTION_MD5=Object.freeze({financial_statement_page:'411a49de3b16cb18743d1388fe4e6d7f',
 record_report_export:'8c27c35f2d47803cb9f213a35d2bb935',report_export_preview:'6add0cd5eee10a4dfea120608e73a625',
 wave5_cash_date_command:'420fd1eb3fb3cf509d53ffc0e71701d0',wave5_cash_date_get:'9cffa55ebb5785b32c9028cb87c31f12',
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
export function createRemainingBudget({now=Date.now,startedAt=now(),priorRequestBound=PRIOR_REQUEST_BOUND}={}){
 must(typeof now==='function'&&priorRequestBound===PRIOR_REQUEST_BOUND&&Number.isFinite(startedAt),'EXACT_REMAINING_REQUEST_RESERVE_REQUIRED');let attempted=0,resolutionAttempted=false;
 return Object.freeze({claim({resolution=false}={}){
  const elapsed=now()-startedAt;must(Number.isFinite(elapsed)&&elapsed>=0&&elapsed<=900000-45000,'REMAINING_EXECUTION_DEADLINE_REQUIRED');
  must(!resolution||!resolutionAttempted,'SINGLE_ORIGINAL_READONLY_RESOLUTION_REQUIRED');
  must(priorRequestBound+attempted+1<=(resolution?150:149),'REMAINING_REQUEST_BOUND_EXCEEDED');attempted++;if(resolution)resolutionAttempted=true;
 },snapshot(){return {priorRequestBound,actualRemainingAttempts:attempted,totalRequestBound:priorRequestBound+attempted,
  previousFirstAttemptObservedRequests:null,previousFirstAttemptConservativeReserve:40,previousResumeObservedRequests:35};}});
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
   if(validate)validate(response.value);
   const resultReceipt=await appendPublic({kind:'remaining-finance-command-result',projectId:PROJECT,bundleSha256:BUNDLE,planSha256,sequence:command.sequence,
    actorId:command.actorId,name,commandId:command.commandId,transport:response.evidence,responseSha256:response.responseSha256,
    actualFinishedAt:new Date().toISOString()});
   must(typeof resultReceipt?.path==='string'&&/^[a-f0-9]{64}$/.test(resultReceipt.sha256),'ACKNOWLEDGED_PUBLIC_REMAINING_RESULT_REQUIRED');pending=null;return response;
  }catch(error){failed=true;throw error;}finally{busy=false;}
 }});
}
async function save(file,value,raw=false){const bytes=raw?value:JSON.stringify(value,null,2)+'\n',handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}return {path:file,sha256:hashBytes(bytes)};}
export async function verifyRemainingPreparation(){
 const bytes=await fs.readFile(path.join(root,REMAINING_PLAN)),plan=JSON.parse(bytes);
 must(plan.kind==='source-bound-genuine-finance-remaining-preparation'&&plan.projectId===PROJECT&&plan.bundleSha256===BUNDLE
  &&plan.priorRequestBound===PRIOR_REQUEST_BOUND&&plan.operationScopeSha256==='fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63'
  &&Array.isArray(plan.sourceBindings)&&plan.sourceBindings.length>23&&Array.isArray(plan.priorEvidenceBindings)&&plan.priorEvidenceBindings.length>0
  &&plan.sourceBindings.every(source=>typeof source.path==='string'&&!source.path.includes('..')&&!path.isAbsolute(source.path)&&/^[a-f0-9]{64}$/.test(source.sha256))
  &&new Set(plan.sourceBindings.map(source=>source.path)).size===plan.sourceBindings.length
  &&plan.priorEvidenceBindings.every(source=>plan.sourceBindings.some(binding=>binding.path===source.path&&binding.sha256===source.sha256)),
  'EXACT_REMAINING_PREPARATION_REQUIRED');
 for(const source of plan.sourceBindings)must(hashBytes(await fs.readFile(path.join(root,source.path)))===source.sha256,'REMAINING_SOURCE_OR_EVIDENCE_DRIFT');
 return {plan,planSha256:hashBytes(bytes)};
}
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute'].includes(mode)&&process.argv.length<=3,'FIXED_REMAINING_EXECUTION_MODE_REQUIRED');
 const {review}=await loadApprovedInputs();validateFinanceFixture(review);const {plan,planSha256}=await verifyRemainingPreparation();
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,sourceBindings:plan.sourceBindings.length,networkCalls:0,priorRequestBound:75})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_REMAINING_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_REMAINING_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),rawManagement=createManagementTransport(config.ownerToken,{timeoutMs:45000});
 const directory=base+'genuine-finance-finance-20261013-r5-'+Date.now()+'/',startedAt=Date.now();await fs.mkdir(path.join(root,directory));
 const budget=createRemainingBudget({startedAt}),abort=new AbortController(),deadline=setTimeout(()=>abort.abort(),900000);
 let phase='once-only-remaining-intent',transport,writer,step=0;const completed=[];
 const persist=(file,value,raw)=>save(directory+file,value,raw);
 const management=(method,suffix,body)=>{must(method==='POST'&&suffix==='/database/query'&&body?.read_only===true,'FIXED_REMAINING_READONLY_MANAGEMENT_REQUIRED');
  budget.claim();return rawManagement(method,suffix,body);};
 const read=async(query,{resolution=false}={})=>{budget.claim({resolution});const result=await rawManagement('POST','/database/query',{query,read_only:true});
  must([200,201].includes(result?.status)&&Array.isArray(result.value),'ACTUAL_REMAINING_READONLY_RESPONSE_REQUIRED');return result;};
 try{
  const priorStop=JSON.parse(await fs.readFile(path.join(root,PRIOR_FINANCE+'99-stop.json'),'utf8'));
  must(priorStop.lastOriginalCommand?.commandId===STALE_COMMAND&&priorStop.failureCode==='FINANCE_TIMEOUT_UNCERTAIN'
   &&priorStop.actualRequestAttempts===35&&priorStop.priorRequestBound===40&&priorStop.automaticRetryPerformed===false,'EXACT_PRIOR_UNCERTAIN_STOP_REQUIRED');
  const priorPayroll=JSON.parse(await fs.readFile(path.join(root,PRIOR_FINANCE+'date-payroll_obligation.json'),'utf8'));
  must(priorPayroll.readback?.id===id('date.payroll_obligation')&&priorPayroll.readback.decision==='approved'
   &&priorPayroll.readback.currentApproval?.version==='1'&&priorPayroll.genuineDistinctApprover==='0635081d-08ea-4ad1-b7f2-ad2f8721f67d','PRESERVED_GENUINE_PAYROLL_APPROVAL_REQUIRED');
  await save(base+'finance-remaining-once-20261013-r5.json',{kind:'once-only-remaining-finance-intent',projectId:PROJECT,bundleSha256:BUNDLE,planSha256,directory,
   actualStartedAt:new Date(startedAt).toISOString(),priorRequestBound:75,staleOriginalCommandPreserved:STALE_COMMAND,retryOrReplayOfStaleForbidden:true,
   successfulPriorWorkWillNotBeRepeated:true,mutationKinds:['remaining-two-payment-date-commands','two-governed-csv-export-registrations']});
  phase='fresh-quiescent-original-preflight';
  const before=(await read(REMAINING_BASELINE_SQL)).value[0]?.facts,wholeBefore=(await read(FINANCE_FACTS_SQL)).value[0]?.facts;
  const beforeObservation=(await read(REMAINING_ACTIVITY_SQL)).value[0]?.observation;
  validateRemainingState(before,beforeObservation,{wholeSourceHash:wholeBefore?.sourceHash});
  must(await fs.realpath(path.join(root,'dist'))===path.join(await fs.realpath(root),'dist'),'EXACT_REMAINING_ARTIFACT_DIRECTORY_REQUIRED');
  for(const label of ['pipeline','statement']){
   let existing=false;try{await fs.lstat(path.join(root,'dist','Jentra-W5-Synthetic-'+label+'.csv'));existing=true;}catch(error){if(error.code!=='ENOENT')throw error;}
   must(!existing,'REMAINING_EXPORT_ARTIFACT_ALREADY_EXISTS');
  }
  await persist('00-source-and-uncertainty-before.json',{facts:before,wholeSource:wholeBefore,observation:beforeObservation,originalRowsPreserved:true,
   originalConflictHttpResponseObserved:false,staleCommandReplayed:false});
  const functionRows=(await read(REMAINING_FUNCTIONS_SQL)).value;validateRemainingFunctions(functionRows);
  await persist('01-installed-function-contracts.json',{functions:functionRows,sourceMd5BindingsVerified:true});
  const clock=(await read('SELECT statement_timestamp()::text AS observed_at')).value[0]?.observed_at;
  must(typeof clock==='string'&&Number.isFinite(Date.parse(clock))&&new Date(clock).toISOString().slice(0,10)===calendar.fixtureDay,'EXACT_REMAINING_ACTUAL_DAY_REQUIRED');
  budget.claim();const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken,{timeoutMs:45000})()).value);
  const concrete=createFinanceHttpsTransport({apiKey:keys.anon});keys.serviceRole=null;keys.anon=null;
  transport=Object.freeze({...concrete,send(handle,route,options={}){
   if(route.startsWith('/rest/v1/rpc/'))must(REMAINING_RPCS.includes(route.split('/').at(-1)),'FIXED_REMAINING_RPC_REQUIRED');
   budget.claim();return concrete.send(handle,route,{...options,signal:abort.signal});}});
  const actors={};for(const label of ['proposer','approver','foreign-member']){phase='actual-existing-mfa-'+label;
   actors[label]=await existingActorSession({root,config,key,label,transport,management,save:persist,file:'session-'+label+'.json'});}
  const actor=actors.proposer,approver=actors.approver;
  const request=async(who,name,body)=>{must(REMAINING_RPCS.includes(name),'FIXED_REMAINING_RPC_REQUIRED');
   if(name==='wave5_cash_date_command'||name==='record_report_export'){
    const observation=(await read(REMAINING_ACTIVITY_SQL)).value[0]?.observation;validateRemainingQuiescence(observation);
    await persist(String(++step).padStart(3,'0')+'-original-command-quiescence.json',{commandId:body.p_command_id,observation,
     readOnly:true,originalStaleCommandReplayed:false,originalConflictHttpResponseObserved:false});
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
   const replay=await writing(actor,'wave5_cash_date_command',prepare,value=>must(value.command_id===prepareCommand&&value.entity?.proposalHash===prepared.value.entity.proposalHash,
    'ACTUAL_ORIGINAL_REMAINING_DATE_REPLAY_REQUIRED'));
   const readback=(await reading(actor,'wave5_cash_date_get',{p_id:proposal})).value;
   must(readback.preparedBy===actor.proof.actorId&&readback.decision==='approved'&&readback.sourceId===source.sourceId&&readback.sourceHash===source.sourceHash
    &&readback.dueDate===calendar.dueDate&&readback.currentApproval?.version==='1'&&readback.currentApproval.decisionId===approveCommand
    &&readback.currentApproval.proposalHash===prepared.value.entity.proposalHash&&actor.proof.actorId!==approver.proof.actorId,'ACTUAL_REMAINING_DATE_READBACK_REQUIRED');
   await persist('date-'+kind+'.json',{source,readback,actualDistinctApprover:approver.proof.actorId,originalReplaySha256:replay.responseSha256,
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
  const after=(await read(REMAINING_BASELINE_SQL)).value[0]?.facts,wholeAfter=(await read(FINANCE_FACTS_SQL)).value[0]?.facts;
  const priorCompleteAfter=(await read(REMAINING_PRIOR_COMPLETE_SQL)).value[0]?.facts;
  const afterObservation=(await read(REMAINING_ACTIVITY_SQL)).value[0]?.observation;
  validateRemainingState(after,afterObservation,{after:true,wholeSourceHash:wholeAfter?.sourceHash,priorCompleteSourceHash:priorCompleteAfter?.sourceHash});
  must(Date.now()-startedAt<=900000&&!abort.signal.aborted,'REMAINING_EXECUTION_DEADLINE_REQUIRED');
  await persist('98-source-and-uncertainty-after.json',{facts:after,wholeSource:wholeAfter,priorCompleteSource:priorCompleteAfter,observation:afterObservation,originalBaselineHashPreserved:true,
   exactlyTwoAdditionalLegitimateExportProcessEvents:true,staleOriginalCommandStillWithoutReceiptOrProposal:true,staleOriginalDenialHttpObserved:false});
  const result={kind:'actual-genuine-finance-remaining-workflows-on-administrative-fixtures',passed:true,slice:'finance',projectId:PROJECT,bundleSha256:BUNDLE,
   continuationPlanSha256:planSha256,actualFinishedAt:new Date().toISOString(),priorSuccessfulEvidence:plan.priorEvidenceBindings,completed,
   ...budget.snapshot(),networkRequestsAttempted:budget.snapshot().actualRemainingAttempts,totalWorkflowRequestAttempts:budget.snapshot().totalRequestBound,
   previousAttemptRequestReserve:40,previousAttemptObservedRequestCount:null,previousResumedAttemptObservedRequests:35,
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
   completed,...budget.snapshot(),lastOriginalCommand:pending?{name:pending.name,commandId:pending.commandId,actorId:pending.actorId}:null,resolution,
   staleOriginalCommandId:STALE_COMMAND,staleOriginalCommandReplayed:false,privateErrorPrinted:false,automaticRetryPerformed:false,liveGateComplete:false});throw error;
 }finally{clearTimeout(deadline);abort.abort();transport?.close();key.fill(0);config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'FINANCE_REMAINING_STOPPED',privateErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;});
