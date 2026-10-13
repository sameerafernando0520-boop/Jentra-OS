import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport } from './approved_management_installer.mjs';
import { hashBytes,hashJson,isUuid } from './runtime_contract.mjs';
import { runtimeSealKey,appendRuntimeSecret } from './private_runtime_seal.mjs';
import { createPrivateKeyReader,selectExistingLegacyKeys } from './private_runtime_http.mjs';
import { existingActorSession } from './private_existing_actor_session_20261013_r5.mjs';
import { FINANCE_SCOPE as scope,FINANCE_CALENDAR as calendar,FINANCE_EXPECTED as expected,FINANCE_ACCOUNTS,FINANCE_JOURNALS,financeId as financeFixtureId,validateFinanceFixture } from './finance_cash_fixture_20261013_r5.mjs';
import { createFinanceHttpsTransport,financeDenial,exactRatio,encodeFinanceCsv } from './finance_https_transport_20261013_r5.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
// API enum names contain underscores; fixture labels use hyphens. Keep the
// frozen fixture IDs unchanged and derive each fixed workflow identity once.
export function financeWorkflowId(label){must(typeof label==='string','EXACT_FINANCE_WORKFLOW_LABEL_REQUIRED');return financeFixtureId(label.replaceAll('_','-'));}
const financeId=financeWorkflowId;
export const FINANCE_SCOPED_BODY=Object.freeze({p_tenant_id:scope.tenantId,p_legal_entity_id:scope.entityId,p_branch_id:scope.branchId});
export const FINANCE_FACTS_SQL=`SELECT jsonb_build_object(
 'journals',(SELECT count(*) FROM finance.journal_entries WHERE tenant_id='${scope.tenantId}'),
 'lines',(SELECT count(*) FROM finance.journal_lines WHERE tenant_id='${scope.tenantId}'),
 'journalIds',(SELECT jsonb_agg(id ORDER BY id) FROM finance.journal_entries WHERE tenant_id='${scope.tenantId}'),
 'sourceHash',encode(extensions.digest(jsonb_build_object(
  'journals',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM finance.journal_entries x WHERE tenant_id='${scope.tenantId}'),
  'lines',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM finance.journal_lines x WHERE tenant_id='${scope.tenantId}'),
  'openItems',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM finance.open_items x WHERE tenant_id='${scope.tenantId}'),
  'payroll',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM people_payroll.obligation_effects x WHERE tenant_id='${scope.tenantId}'),
  'correction',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM people_payroll.correction_balance_effects x WHERE tenant_id='${scope.tenantId}'),
  'reimbursement',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM projects.reimbursement_effects x WHERE tenant_id='${scope.tenantId}'),
  'crm',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM crm.opportunities x WHERE tenant_id='${scope.tenantId}'),
  'process',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM workflow.process_events x WHERE tenant_id='${scope.tenantId}')
 )::text,'sha256'),'hex'),
 'publications',(SELECT count(*) FROM finance.financial_reports WHERE tenant_id='${scope.tenantId}'),
 'classifications',(SELECT count(*) FROM analytics.statement_classifications WHERE tenant_id='${scope.tenantId}'),
 'dateProposals',(SELECT count(*) FROM analytics.cash_date_proposals WHERE tenant_id='${scope.tenantId}'),
 'dateDecisions',(SELECT count(*) FROM analytics.cash_date_decisions WHERE tenant_id='${scope.tenantId}'),
 'scenarios',(SELECT count(*) FROM analytics.cash_scenario_revisions WHERE tenant_id='${scope.tenantId}'),
 'exports',(SELECT count(*) FROM core.export_jobs WHERE tenant_id='${scope.tenantId}')) AS facts`;
export function receiptResolutionSql(commandId){must(isUuid(commandId),'ORIGINAL_FINANCE_COMMAND_REQUIRED');
 return `SELECT command_id,actor_id,aggregate_type,aggregate_id,request_hash FROM core.command_receipts WHERE tenant_id='${scope.tenantId}' AND command_id='${commandId}'::uuid`;}
export function canonicalFinance(value){must(typeof value?.canonicalText==='string'&&hashBytes(value.canonicalText)===value.sourceHash,'ACTUAL_CANONICAL_FINANCE_HASH_REQUIRED');return JSON.parse(value.canonicalText);}
export function sameFinanceJson(a,b){const sorted=value=>Array.isArray(value)?value.map(sorted):value&&typeof value==='object'?
 Object.fromEntries(Object.keys(value).sort().map(k=>[k,sorted(value[k])])):value;return JSON.stringify(sorted(a))===JSON.stringify(sorted(b));}
export function validateCompleteCash(value){const data=canonicalFinance(value),families=['bank_cash','receivables','payables','payroll','project_reimbursements'];
 must(data.contractRevision===3&&data.scope.tenantId===scope.tenantId&&data.scope.legalEntityId===scope.entityId&&data.scope.branchId===scope.branchId
  &&data.horizonStart===calendar.horizonStart&&data.horizonEnd===calendar.horizonEnd&&families.every(k=>data.completeProviders.includes(k)&&data.providerStatus[k]==='available'),
  'ALL_FIVE_ACTUAL_CASH_PROVIDERS_REQUIRED');
 must(data.controls.length===1&&data.controls[0].amount===expected.openingCash&&data.obligations.length===5,'EXACT_CASH_SOURCE_POPULATION_REQUIRED');
 for(const [id,amount,inflow]of [[financeId('open.ar'),'3000.000001',true],[financeId('open.ap'),'1200.000002',false],
  [financeId('payroll.obligation'),expected.payrollOpening,false],[financeId('payroll.recovery'),'2.000002',true],[financeId('reimbursement'),expected.reimbursement,false]])
  must(data.obligations.some(o=>o.id===id&&o.amount===amount&&o.inflow===inflow&&o.currency==='LKR'&&o.dueDate===calendar.dueDate),'EXACT_CASH_DECIMALS_DIRECTIONS_REQUIRED');
 return data;
}
async function save(file,value,raw=false){const bytes=raw?value:JSON.stringify(value,null,2)+'\n',handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}return {path:file,sha256:hashBytes(bytes)};}
async function verifySources(){const file=base+'finance-cash-workflow-preparation-20261013-r5-a3.json',plan=JSON.parse(await fs.readFile(path.join(root,file),'utf8'));
 must(plan.kind==='source-bound-genuine-finance-workflow-preparation'&&plan.projectId===PROJECT&&plan.bundleSha256===BUNDLE,'EXACT_FINANCE_WORKFLOW_PLAN_REQUIRED');
 for(const binding of plan.sourceBindings)must(hashBytes(await fs.readFile(path.join(root,binding.path)))===binding.sha256,'FINANCE_WORKFLOW_SOURCE_DRIFT');return plan;}

export function financePhasePreflight(facts,phase){
 must(['finance','cash'].includes(phase),'FIXED_FINANCE_PHASE_REQUIRED');
 const prior=phase==='cash';must(facts?.journals===9&&facts.lines===18&&sameFinanceJson(facts.journalIds,FINANCE_JOURNALS.map(j=>j.id).sort())
  &&facts.publications===(prior?3:0)&&facts.classifications===(prior?1:0)&&facts.dateProposals===(prior?3:0)&&facts.dateDecisions===(prior?3:0)
  &&facts.scenarios===0&&facts.exports===(prior?2:0),'EXACT_COMMITTED_FINANCE_PHASE_FIXTURE_REQUIRED');
}
export function observableCashHorizon(actualClock){
 must(typeof actualClock==='string'&&Number.isFinite(Date.parse(actualClock)),'ACTUAL_CASH_CLOCK_REQUIRED');
 return Date.parse(actualClock)>=Date.parse(calendar.horizonStart+'T00:00:00.000Z');
}
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute-finance','--resume-finance','--execute-cash'].includes(mode)&&process.argv.length<=3,'FIXED_FINANCE_WORKFLOW_MODE_REQUIRED');
 const {review}=await loadApprovedInputs();validateFinanceFixture(review);const plan=await verifySources();
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,sourceBindings:plan.sourceBindings.length})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_FINANCE_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_FINANCE_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),privateManagement=createManagementTransport(config.ownerToken);
 const slice=mode==='--execute-cash'?'cash':'finance',directory=base+'genuine-finance-'+slice+'-20261013-r5-'+Date.now()+'/';await fs.mkdir(path.join(root,directory));
 let phase='once-only-intent',transport,calls=0,priorCalls=0,priorResult=null,step=0,lastMutation=null;const completed=[],started=Date.now();
 const persist=(file,value,raw)=>save(directory+file,value,raw);
 const bounded=()=>must(Date.now()-started<900000&&++calls+priorCalls<=150,'FINANCE_WORKFLOW_BOUND_EXCEEDED');
 const management=(...args)=>{bounded();return privateManagement(...args);};
 const read=query=>management('POST','/database/query',{query,read_only:true});
 try{
  const planSha256=hashBytes(await fs.readFile(path.join(root,base+'finance-cash-workflow-preparation-20261013-r5-a3.json')));
  if(mode==='--resume-finance'){
   const stopPath=base+'genuine-finance-finance-20261013-r5-1791894436593/99-stop.json',stopBytes=await fs.readFile(path.join(root,stopPath));
   must(hashBytes(stopBytes)==='1fd29a42a57741f59f3467c3fb3be86897955a3d84f5b6d7655155227ab3a61b','EXACT_IDENTIFIER_STOP_REQUIRED');
   const stop=JSON.parse(stopBytes);
   must(stop.lastOriginalCommand===null&&stop.resolution===null&&stop.completed.length===1&&stop.completed[0].name==='post_manual_journal'
    &&stop.completed[0].commandId===financeId('command.posting-denial')&&stop.completed[0].denialCode==='PERMISSION_DENIED','NO_UNCERTAIN_FINANCE_COMMAND_REQUIRED');
   const proofBytes=await fs.readFile(path.join(root,base+'genuine-finance-finance-20261013-r5-1791894436593/002-post_manual_journal-result.json'));
   must(hashBytes(proofBytes)==='572bc7b5f6c7ab059934a56618844f91af6ad8bb08d31d77a0f8880232142242','EXACT_PRIOR_POSTING_DENIAL_REQUIRED');
   completed.push({...stop.completed[0],priorAttemptEvidence:stopPath});
   // The earlier stop lacks a request counter. Reserve a conservative upper
   // bound rather than invent an observed count; preserve the total 150 cap.
   priorCalls=40;
  }
  if(slice==='cash'){
   const binding=JSON.parse(await fs.readFile(path.join(root,base+'finance-cash-finance-completed-20261013-r5.json'),'utf8'));
   must(binding.kind==='genuine-finance-phase-completion-binding'&&binding.planSha256===planSha256
    &&/^docs\/verification\/wave5\/genuine-finance-finance-20261013-r5-\d+\/99-result\.json$/.test(binding.result?.path),'EXACT_COMPLETED_FINANCE_PHASE_REQUIRED');
   const bytes=await fs.readFile(path.join(root,binding.result.path));must(hashBytes(bytes)===binding.result.sha256,'COMPLETED_FINANCE_RESULT_DRIFT');
   priorResult=JSON.parse(bytes);must(priorResult.passed===true&&priorResult.slice==='finance'&&priorResult.projectId===PROJECT&&priorResult.bundleSha256===BUNDLE
    &&Number.isSafeInteger(priorResult.totalWorkflowRequestAttempts)&&priorResult.totalWorkflowRequestAttempts>0,'ACTUAL_COMPLETED_FINANCE_PHASE_REQUIRED');priorCalls=priorResult.totalWorkflowRequestAttempts;
  }
  await save(base+'finance-cash-'+slice+(mode==='--resume-finance'?'-resume':'')+'-once-20261013-r5.json',{kind:'once-only-genuine-finance-workflow-intent',slice,projectId:PROJECT,bundleSha256:BUNDLE,
   directory,planSha256:hashBytes(await fs.readFile(path.join(root,base+'finance-cash-workflow-preparation-20261013-r5-a3.json'))),startedAt:new Date().toISOString(),
   automaticRetryForbidden:true,newAuthOrRolesForbidden:true,sourceFixtureIsAdministrative:true});
  phase='fixed-source-preflight';const before=(await read(FINANCE_FACTS_SQL)).value[0]?.facts;
  financePhasePreflight(before,slice);if(priorResult)must(before.sourceHash===priorResult.sourceHash,'PRIOR_FINANCE_SOURCE_DRIFT');
  await persist('00-source-before.json',{facts:before,administrativeSourceFixture:true,actualUserPosting:false});
  const clock=(await read('SELECT statement_timestamp()::text AS observed_at')).value[0]?.observed_at;
  must(typeof clock==='string'&&Number.isFinite(Date.parse(clock)),'ACTUAL_FINANCE_WORKFLOW_CLOCK_REQUIRED');
  if(slice==='finance')must(new Date(clock).toISOString().slice(0,10)===calendar.fixtureDay,'EXACT_FINANCE_WORKFLOW_DAY_REQUIRED');
  else must(observableCashHorizon(clock)&&new Date(clock).toISOString().slice(0,10)===calendar.horizonStart,'CASH_HORIZON_NOT_YET_OBSERVABLE');
  bounded();const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);
  const concreteTransport=createFinanceHttpsTransport({apiKey:keys.anon});
  transport=Object.freeze({...concreteTransport,send(...args){bounded();return concreteTransport.send(...args);}});keys.serviceRole=null;keys.anon=null;
  const sessions={};for(const label of slice==='finance'?['proposer','approver','foreign-member']:['proposer']){phase='genuine-existing-actor-'+label;
   sessions[label]=await existingActorSession({root,config,key,label,transport,management,save:persist,file:'session-'+label+'.json'});}
  const actor=sessions.proposer,approver=sessions.approver;
  const request=async(who,name,body)=>{
   const response=await who.request('/rest/v1/rpc/'+name,{...FINANCE_SCOPED_BODY,...body});
   if(!response.ok){const record=await appendRuntimeSecret(config.privateDirectory,key,'finance-response-error',{phase,name,response});
    await persist(String(++step).padStart(3,'0')+'-private-error-reference.json',{phase,name,status:response.status,denialCode:financeDenial(response),privateRecord:record,transport:response.evidence});}
   return response;};
  const reading=async(who,name,body={})=>{const response=await request(who,name,body);must(response.ok,'ACTUAL_FINANCE_READ_REQUIRED');return response;};
  const writing=async(who,name,body,{denial=null,validate}={})=>{
   const identity=body.p_command_id??body.p_id;must(isUuid(identity),'ORIGINAL_FINANCE_COMMAND_REQUIRED');
   phase=name;lastMutation={name,commandId:identity,actorId:who.proof.actorId,body};
   const privateRecord=await appendRuntimeSecret(config.privateDirectory,key,'finance-command-intent',{...lastMutation,actualIntentAt:new Date().toISOString()});
   await persist(String(++step).padStart(3,'0')+'-'+name+'-intent.json',{...lastMutation,privateRecord});
   const response=await request(who,name,body);
   if(denial){must(!response.ok&&financeDenial(response)===denial,'EXACT_ACTUAL_FINANCE_DENIAL_REQUIRED');}
   else{must(response.ok,'ACTUAL_FINANCE_WRITE_REQUIRED');validate?.(response.value);}
   await persist(String(step).padStart(3,'0')+'-'+name+'-result.json',{commandId:identity,actorId:who.proof.actorId,denialCode:denial,transport:response.evidence,
    responseSha256:response.responseSha256,actualFinishedAt:new Date().toISOString()});
   completed.push({name,commandId:identity,denialCode:denial});lastMutation=null;return response;
  };
  const command=(label,payload,expectedVersion='0')=>({p_command_id:financeId('command.'+label),p_idempotency_key:financeId('command.'+label),
   p_client_timestamp:clock,p_payload:payload,p_expected_entity_version:expectedVersion});
  if(slice==='finance'){
  if(mode!=='--resume-finance'){phase='genuine-posting-denial';await writing(actor,'post_manual_journal',command('posting-denial',{id:financeId('manual.denied')}),{denial:'PERMISSION_DENIED'});}
  for(const kind of ['profit_loss','balance_sheet','trial_balance']){
   const reportId=financeId('statement.'+kind),body=command('statement.'+kind,{id:reportId,kind,period_id:financeId('period'),as_of:calendar.fixtureDay});
   const result=await writing(actor,'generate_financial_statement',body,{validate:value=>{
    const entity=value.entity;must(value.command_id===body.p_command_id&&entity.id===reportId&&entity.kind===kind&&entity.account_count===10&&entity.journal_count===16,
     'ACTUAL_STATEMENT_COMMAND_SOURCE_REQUIRED');
    const checks=kind==='profit_loss'?{revenue:expected.revenue,expenses:expected.expenses,net_profit:expected.netProfit}:kind==='balance_sheet'?
     {assets:expected.assets,liabilities:expected.liabilities,equity:expected.equity,current_earnings:expected.currentEarnings,difference:'0.000000'}:{difference:'0.000000'};
    for(const [field,wanted]of Object.entries(checks))must(entity[field]===wanted,'EXACT_STATEMENT_ARITHMETIC_REQUIRED');
   }});
   await persist('statement-'+kind+'.json',{id:reportId,summary:result.value.entity,actorId:actor.proof.actorId,sourceFixture:'administrative synthetic'});
  }
  const ratioBody={p_profit_loss_id:financeId('statement.profit_loss'),p_balance_sheet_id:financeId('statement.balance_sheet'),p_classification_id:null};
  const ratiosBase=canonicalFinance((await reading(actor,'wave5_financial_ratios',ratioBody)).value);
  const labels=Object.fromEntries(FINANCE_ACCOUNTS.map(a=>[a.id,a.label]));
  const classification=await writing(approver,'wave5_classification_publish',{p_id:financeId('classification'),p_profit_loss_id:ratioBody.p_profit_loss_id,
   p_balance_sheet_id:ratioBody.p_balance_sheet_id,p_labels:labels,p_reason:'Reviewed classifications for approved synthetic admin finance fixtures'},
   {validate:value=>must(value.entity?.id===financeId('classification'),'ACTUAL_CLASSIFICATION_PUBLICATION_REQUIRED')});
  const ratios=canonicalFinance((await reading(actor,'wave5_financial_ratios',{...ratioBody,p_classification_id:financeId('classification')})).value);
  must(Object.keys(ratiosBase.ratios).length===3&&Object.keys(ratios.ratios).length===6,'EXACT_AVAILABLE_RATIO_POPULATION_REQUIRED');
  for(const result of Object.values(ratios.ratios)){const check=exactRatio(result.numerator,result.denominator);
   must(result.exactValue===check.exactValue&&result.unavailableReason===check.unavailableReason,'EXACT_RATIO_HALF_AWAY_ARITHMETIC_REQUIRED');}
  await persist('ratios-and-classification.json',{ratiosBase,ratios,classificationId:classification.value.entity.id,genuineApprover:approver.proof.actorId});
  const blocked=await request(actor,'wave5_cash_basis',{p_start:calendar.horizonStart,p_end:calendar.horizonEnd,p_recorded_through:clock});
  must(financeDenial(blocked)==='VALIDATION_ERROR','ACTUAL_FUTURE_HORIZON_GUARD_REQUIRED');
  await persist('future-horizon-guard.json',{observedAt:clock,horizonStart:calendar.horizonStart,denialCode:'VALIDATION_ERROR',transport:blocked.evidence,
   completeCashBasisProved:false,reason:'installed v2 forbids horizon start later than the actual observed cutoff'});
  for(const [kind,sourceLabel,wanted]of [['payroll_obligation','payroll.obligation',expected.payrollOpening],['payroll_correction','payroll.recovery',expected.recovery],['project_reimbursement','reimbursement',expected.reimbursement]]){
   const sources=(await reading(actor,'wave5_cash_date_sources',{p_kind:kind,p_after:null})).value;
   must(sources.rows.length===1&&sources.next===null&&sources.rows[0].sourceId===financeId(sourceLabel)&&sources.rows[0].remainingAmount===wanted&&sources.rows[0].approved===null,
    'ACTUAL_NONEMPTY_DATED_SOURCE_REQUIRED');const source=sources.rows[0],proposal=financeId('date.'+kind);
   const prepareBody={p_command_id:financeId('command.date.prepare.'+kind),p_idempotency_key:financeId('command.date.prepare.'+kind),p_issued_at:clock,p_action:'prepare',
    p_payload:{id:proposal,sourceKind:kind,sourceId:source.sourceId,sourceHash:source.sourceHash,dueDate:calendar.dueDate,reasonCode:kind==='payroll_correction'?'correction_recovery':'payment_terms',expectedVersion:'0'}};
   const prepared=await writing(actor,'wave5_cash_date_command',prepareBody,{validate:value=>must(value.command_id===prepareBody.p_command_id&&value.entity?.id===proposal&&value.entity.status==='prepared','ACTUAL_DATE_PREPARATION_REQUIRED')});
   const approveBody={p_command_id:financeId('command.date.approve.'+kind),p_idempotency_key:financeId('command.date.approve.'+kind),p_issued_at:clock,p_action:'approve',
    p_payload:{id:proposal,proposalHash:prepared.value.entity.proposalHash}};
   await writing(approver,'wave5_cash_date_command',approveBody,{validate:value=>must(value.command_id===approveBody.p_command_id&&value.entity?.status==='approved'&&value.entity.version==='1','ACTUAL_DISTINCT_DATE_APPROVAL_REQUIRED')});
   const replay=await writing(actor,'wave5_cash_date_command',prepareBody,{validate:value=>must(value.entity.proposalHash===prepared.value.entity.proposalHash,'ORIGINAL_DATE_REPLAY_REQUIRED')});
   const readback=(await reading(actor,'wave5_cash_date_get',{p_id:proposal})).value;
   must(readback.preparedBy===actor.proof.actorId&&readback.decision==='approved'&&readback.currentApproval.version==='1','ACTUAL_DATE_APPROVAL_READBACK_REQUIRED');
   await persist('date-'+kind+'.json',{source,readback,originalReplaySha256:replay.responseSha256,genuineDistinctApprover:approver.proof.actorId});
   if(kind==='payroll_obligation'){
    const staleCommand=financeId('command.date.stale'),stale={...prepareBody,p_command_id:staleCommand,p_idempotency_key:staleCommand,
     p_payload:{...prepareBody.p_payload,id:financeId('date.stale')}};
    await writing(actor,'wave5_cash_date_command',stale,{denial:'CASH_DATE_VERSION_CONFLICT'});
    const foreign=await request(sessions['foreign-member'],'wave5_cash_date_sources',{p_kind:kind,p_after:null});
    must(financeDenial(foreign)==='PERMISSION_DENIED','ACTUAL_FOREIGN_FINANCE_DENIAL_REQUIRED');
    await persist('foreign-source-denial.json',{actorId:sessions['foreign-member'].proof.actorId,denialCode:'PERMISSION_DENIED',transport:foreign.evidence});
   }
  }
  }
  const now=(await read('SELECT statement_timestamp()::text AS observed_at')).value[0].observed_at;
  if(slice==='cash'){
  const basisBody={p_start:calendar.horizonStart,p_end:calendar.horizonEnd,p_recorded_through:now};
  const complete=(await reading(actor,'wave5_cash_basis',{...basisBody,p_recorded_through:now})).value;validateCompleteCash(complete);
  await persist('complete-cash-basis.json',complete);
  const parameters={horizonStart:calendar.horizonStart,horizonEnd:calendar.horizonEnd,recordedThrough:now,overrides:{}};
  for(const [label,overrides]of [['base',{}],['hypothetical',{[financeId('payroll.obligation')]:{dueDate:calendar.delayedDate,remainingUnits:'6000000',reasonCode:'reviewed_amount'}}]]){
   const id=financeId('scenario.'+label),body={p_id:id,p_source_hash:complete.sourceHash,p_parameters:{...parameters,overrides}};
   await writing(actor,'wave5_cash_save',body,{validate:value=>must(value.id===id&&value.sourceHash===complete.sourceHash,'ACTUAL_IMMUTABLE_SCENARIO_REQUIRED')});
   const saved=(await reading(actor,'wave5_cash_get',{p_id:id})).value;must(saved.canonicalText===complete.canonicalText&&sameFinanceJson(saved.parameters,body.p_parameters),'ACTUAL_FROZEN_SCENARIO_READBACK_REQUIRED');
   await persist('scenario-'+label+'.json',saved);
   const replay=await writing(actor,'wave5_cash_save',body,{validate:value=>must(value.id===id&&value.sourceHash===complete.sourceHash,'ORIGINAL_SCENARIO_REPLAY_REQUIRED')});
   await persist('scenario-'+label+'-original-replay.json',{id,responseSha256:replay.responseSha256,originalCommandUnchanged:true});
  }
  }
  const fresh=await existingActorSession({root,config,key,label:'proposer',transport,management,save:persist,file:'session-proposer-reopen.json'});
  must(fresh.proof.sessionId!==actor.proof.sessionId,'INDEPENDENT_REAL_REOPEN_SESSION_REQUIRED');
  const pipeline=(await read(`SELECT id FROM analytics.pipeline_forecasts WHERE tenant_id='${scope.tenantId}' AND legal_entity_id='${scope.entityId}' AND branch_id='${scope.branchId}' ORDER BY observed_at,id LIMIT 1`)).value[0]?.id;
  must(isUuid(pipeline),'ACTUAL_EXISTING_FORECAST_REQUIRED');
  const exportCases=slice==='cash'?[['cash-base','w5_cash',financeId('scenario.base'),'buckets'],['cash-hypothetical','w5_cash',financeId('scenario.hypothetical'),'buckets']]:
   [['pipeline','w5_pipeline',pipeline,'currencies'],['statement','statement',financeId('statement.profit_loss'),'accounts']];
  for(const [label,type,sourceId,section]of exportCases){
   const preview=(await reading(actor,'report_export_preview',{p_source_type:type,p_source_id:sourceId,p_section:section,p_filters:{}})).value;
   must(hashBytes(preview.canonical_text)===preview.source_hash,'ACTUAL_EXPORT_PREVIEW_HASH_REQUIRED');
   const document=JSON.parse(preview.canonical_text),id=financeId('export.'+label),preparedAt=new Date(now).toISOString();
   if(type==='w5_cash')must(document.rows.length===7&&document.rows.at(-1).balance===(label==='cash-base'?expected.cashFinalBalance:expected.hypotheticalFinalBalance),
    'EXACT_ACTUAL_CASH_EXPORT_PROJECTION_REQUIRED');
   const artifact=encodeFinanceCsv(document,{exportId:id,preparedAt,sourceHash:preview.source_hash});
   const fileName='Jentra-W5-Synthetic-'+label+'.csv';
   const artifactEvidence=await save('dist/'+fileName,artifact.bytes,true);
   const body=command('export.'+label,{id,source_type:type,source_id:sourceId,section,filters:{},source_hash:preview.source_hash,file_sha256:artifact.sha256,
    file_format:'csv',file_name:fileName,file_size:artifact.bytes.length,columns:artifact.columns,prepared_at:preparedAt});
   await writing(actor,'record_report_export',body,{validate:value=>must(value.command_id===body.p_command_id&&value.entity?.id===id&&value.entity.file_sha256===artifact.sha256,'ACTUAL_GOVERNED_EXPORT_RECORD_REQUIRED')});
   let reopened=false;if(type.startsWith('w5_')){const opened=(await reading(fresh,'wave5_export_reopen',{p_id:id})).value;
    must(opened.sourceHash===preview.source_hash&&opened.fileHash===artifact.sha256&&opened.format==='csv'&&opened.fileName===fileName,'ACTUAL_EXPORT_REOPEN_REQUIRED');
    const reproduced=encodeFinanceCsv(JSON.parse(opened.canonicalText),{exportId:id,preparedAt:opened.preparedAt,sourceHash:opened.sourceHash});
    must(reproduced.sha256===artifact.sha256&&reproduced.bytes.equals(await fs.readFile(path.join(root,artifactEvidence.path))),'ACTUAL_REOPEN_BYTES_REQUIRED');reopened=true;}
   await persist('export-'+label+'.json',{id,sourceType:type,sourceId,artifact:artifactEvidence,columns:artifact.columns,rowCount:artifact.rowCount,
    fileSha256:artifact.sha256,genuineReopen:reopened,reopenSessionId:fresh.proof.sessionId,authenticatedNativeSaveDialog:false,xlsx:false});
  }
  phase='immutable-source-after';const after=(await read(FINANCE_FACTS_SQL)).value[0].facts;
  must(after.sourceHash===before.sourceHash&&after.journals===9&&after.lines===18&&after.publications===3&&after.classifications===1
   &&after.dateProposals===3&&after.dateDecisions===3&&after.scenarios===(slice==='cash'?2:0)&&after.exports===(slice==='cash'?4:2),'EXACT_IMMUTABLE_FINANCE_SOURCE_AND_CAPS_REQUIRED');
  await persist('98-source-after.json',{facts:after,unchangedSourceHash:true});
  const result={kind:'actual-genuine-finance-cash-workflows-on-administrative-fixtures',actualFinishedAt:new Date().toISOString(),passed:true,projectId:PROJECT,bundleSha256:BUNDLE,
   slice,completed,networkRequestsAttempted:calls,totalWorkflowRequestAttempts:calls+priorCalls,previousAttemptRequestReserve:mode==='--resume-finance'?40:null,
   previousAttemptObservedRequestCount:mode==='--resume-finance'?null:undefined,sourceHash:after.sourceHash,sourceHashUnchanged:true,
   actualFinancialPublications:slice==='finance'?3:0,actualClassificationPublications:slice==='finance'?1:0,actualApprovedPaymentDates:slice==='finance'?3:0,
   actualImmutableScenarios:slice==='cash'?2:0,actualCsvArtifacts:2,actualGovernedExportRegistrations:2,actualIndependentSessionReopens:slice==='cash'?2:1,
   reviewedTwoPhaseProbeComplete:slice==='cash',fullFinanceAndCashGatesComplete:false,blockedCashBasis:slice==='finance',actualMissingProviderBasis:false,actualIncompleteBasisSaveDenial:false,
   actualUserJournalPosting:false,genuinePostingDenied:slice==='finance',
   administrativeSourceFixture:true,operationalPayrollApproval:false,authenticatedNative:false,xlsx:false,actualDelivery:false,targetScaleLoad:false,
   newAuthUsers:0,newMfaFactors:0,newRolesOrPermissions:0,ownerAcceptance:false,production:false,realBilling:false};
  const evidence=await persist('99-result.json',result);
  if(slice==='finance')await save(base+'finance-cash-finance-completed-20261013-r5.json',{kind:'genuine-finance-phase-completion-binding',planSha256,result:evidence,
   actualCompletedAt:new Date().toISOString(),cashBasisStillBlocked:true});
  process.stdout.write(JSON.stringify({passed:true,slice,evidence,actualUserJournalPosting:false,reviewedTwoPhaseProbeComplete:slice==='cash',fullFinanceAndCashGatesComplete:false})+'\n');
 }catch(error){let resolution=null;
  if(lastMutation){try{const observed=await read(receiptResolutionSql(lastMutation.commandId));resolution={commandId:lastMutation.commandId,rows:observed.value,responseSha256:observed.responseSha256,readOnly:true,replayPerformed:false};}
   catch{resolution={commandId:lastMutation.commandId,readOnlyResolutionUnavailable:true,replayPerformed:false};}}
  await persist('99-stop.json',{phase,failureCode:error.publicCode??'FINANCE_WORKFLOW_STOPPED',actualStoppedAt:new Date().toISOString(),completed,
   lastOriginalCommand:lastMutation?{commandId:lastMutation.commandId,actorId:lastMutation.actorId,name:lastMutation.name}:null,resolution,
   actualRequestAttempts:calls,priorRequestBound:priorCalls,
   automaticRetryPerformed:false,privateErrorPrinted:false,liveGateComplete:false});throw error;
 }finally{transport?.close();key.fill(0);config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'FINANCE_WORKFLOW_STOPPED',privateErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;});
