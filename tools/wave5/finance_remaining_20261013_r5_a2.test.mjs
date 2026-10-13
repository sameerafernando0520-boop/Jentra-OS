import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { hashBytes,hashJson } from './runtime_contract.mjs';
import { FINANCE_JOURNALS,FINANCE_CALENDAR } from './finance_cash_fixture_20261013_r5.mjs';
import { financeWorkflowId as id,FINANCE_SCOPED_BODY,FINANCE_FACTS_SQL } from './finance_cash_workflows_20261013_r5.mjs';
import { financeDenial,createFinanceHttpsTransport } from './finance_https_transport_20261013_r5_a2.mjs';
import { ORIGINAL_SOURCE_HASH,CURRENT_WHOLE_SOURCE_HASH,STALE_COMMAND,EXPECTED_PROCESS_APPENDS,REMAINING_ACTIVITY_PATTERN,
 REMAINING_ACTIVITY_SQL,REMAINING_BASELINE_SQL,REMAINING_PRIOR_COMPLETE_SQL,REMAINING_FUNCTION_MD5,
 validateRemainingState,validateRemainingQuiescence,validateRemainingFunctions,validateRemainingReplay,createRemainingBudget,validateRemainingCommand,createRemainingCommandWriter } from './finance_remaining_20261013_r5_a2.mjs';

// Controlled offline probes only. These values are not authenticated-session,
// durable private-sink or live API evidence.
const clone=value=>structuredClone(value),digest=hashBytes('controlled-public-test'),stamp='2026-10-13 15:00:00.000001+00';
const actor=(approver=false)=>({proof:{actorId:approver?'0635081d-08ea-4ad1-b7f2-ad2f8721f67d':'8b740ab8-24f7-4455-a78b-aea0d99d20f6',
 aal:'aal2',onlineAuthVerified:true,serverSessionRowVerified:true}});
function dateBody(kind='payroll_correction',action='prepare'){
 const command=id('command.date.'+action+'.'+kind),payload={id:id('date.'+kind)};
 if(action==='prepare')Object.assign(payload,{sourceKind:kind,sourceId:id(kind==='payroll_correction'?'payroll.recovery':'reimbursement'),
  sourceHash:digest,dueDate:FINANCE_CALENDAR.dueDate,reasonCode:kind==='payroll_correction'?'correction_recovery':'payment_terms',expectedVersion:'0'});
 else payload.proposalHash=digest;
 return {p_command_id:command,p_idempotency_key:command,p_issued_at:stamp,p_action:action,p_payload:payload};
}
function exportBody(label='pipeline'){
 const command=id('command.export.'+label);return {p_command_id:command,p_idempotency_key:command,p_client_timestamp:stamp,p_expected_entity_version:'0',
 p_payload:{id:id('export.'+label),source_type:label==='pipeline'?'w5_pipeline':'statement',source_id:label==='pipeline'?id('controlled.pipeline'):id('statement.profit_loss'),
 section:label==='pipeline'?'currencies':'accounts',filters:{},source_hash:digest,file_sha256:digest,file_format:'csv',
 file_name:'Jentra-W5-Synthetic-'+label+'.csv',file_size:256,columns:['record_type','data.amount'],prepared_at:'2026-10-13T15:00:00.000Z'}};
}
function state(after=false){return {facts:{sourceHash:ORIGINAL_SOURCE_HASH,journals:9,lines:18,journalIds:FINANCE_JOURNALS.map(j=>j.id).sort(),
 publications:3,classifications:1,dateProposals:after?3:1,dateDecisions:after?3:1,scenarios:0,exports:after?2:0},
 observation:{staleReceipts:0,staleProposals:0,activeCashApiInvocations:0,originalProcessRows:4,
 processAppends:EXPECTED_PROCESS_APPENDS.slice(0,after?5:3).map((row,i)=>({...row,id:id('controlled.process.'+i),fromStatus:null}))}};}
const validate=()=>{},response=()=>({ok:true,status:200,value:{controlled:true},responseSha256:digest,evidence:{status:200}});
function writerOptions(overrides={}){return {planSha256:digest,appendPrivate:async()=> 'runtime-remaining-finance-command-intent-11111111-1111-1111-1111-111111111111.sealed.json',
 appendPublic:async entry=>({path:'controlled/'+entry.kind+'.json',sha256:hashJson(entry)}),send:async()=>response(),...overrides};}
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};

test('new mapper requires exact known 40/55 SQLSTATE, message and official HTTP500',()=>{
 for(const [code,message]of [['40001','CASH_DATE_VERSION_CONFLICT'],['40001','CASH_DATE_SOURCE_CHANGED'],['55000','CASH_MAPPING_HISTORY_REQUIRED']]){
  assert.equal(financeDenial({ok:false,status:500,value:{code,message}}),message);
  for(const status of [200,400,403,409,502])assert.equal(financeDenial({ok:false,status,value:{code,message}}),null);
 }
 for(const value of [{code:'XX000',message:'CASH_DATE_VERSION_CONFLICT'},{code:'40001',message:'unknown'},{code:'PT409',message:'CASH_DATE_VERSION_CONFLICT'},
  {code:'55000',message:'CASH_DATE_VERSION_CONFLICT'},null])assert.equal(financeDenial({ok:false,status:500,value}),null);
 assert.equal(financeDenial({ok:true,status:500,value:{code:'40001',message:'CASH_DATE_VERSION_CONFLICT'}}),null);
});
test('canonical permission and validation denials retain exact status requirements',()=>{
 assert.equal(financeDenial({ok:false,status:403,value:{code:'42501',message:'Permission denied or multi-factor authentication required.'}}),'PERMISSION_DENIED');
 assert.equal(financeDenial({ok:false,status:400,value:{code:'22023',message:'VALIDATION_ERROR'}}),'VALIDATION_ERROR');
 for(const value of [{code:'42501',message:'unknown'},{code:'42501',message:'PERMISSION_DENIED'},{code:'22023',message:'VALIDATION_ERROR'}])
  assert.equal(financeDenial({ok:false,status:500,value}),null);
});
test('remaining allowlist retains original intended IDs and rejects stale or completed commands',()=>{
 for(const kind of ['payroll_correction','project_reimbursement'])for(const action of ['prepare','approve'])assert.doesNotThrow(()=>validateRemainingCommand('wave5_cash_date_command',dateBody(kind,action)));
 for(const label of ['pipeline','statement'])assert.doesNotThrow(()=>validateRemainingCommand('record_report_export',exportBody(label)));
 const stale=dateBody();stale.p_command_id=STALE_COMMAND;stale.p_idempotency_key=STALE_COMMAND;
 assert.throws(()=>validateRemainingCommand('wave5_cash_date_command',stale),/EXACT_REMAINING_COMMAND_IDENTITY_REQUIRED/);
 assert.throws(()=>validateRemainingCommand('wave5_cash_date_command',dateBody('payroll_obligation')),/EXACT_REMAINING_PAYMENT_ID_REQUIRED/);
 assert.throws(()=>validateRemainingCommand('generate_financial_statement',dateBody()),/FIXED_REMAINING_WRITE_REQUIRED/);
});
test('date command cannot add scope overrides, future-phase actions or unreviewed payload fields',()=>{
 const changes=[body=>body.p_tenant_id=id('wrong.scope'),body=>body.p_action='reject',body=>body.p_issued_at='not-a-time',
 body=>body.p_payload.sourceHash='bad',body=>body.p_payload.expectedVersion='1',body=>body.p_payload.dueDate='2026-10-17',
 body=>body.p_payload.reasonCode='unreviewed',body=>body.p_payload.sourceId=id('wrong.source'),body=>body.p_payload.unreviewed=true];
 for(const change of changes){const body=dateBody();change(body);assert.throws(()=>validateRemainingCommand('wave5_cash_date_command',body));}
 const approval=dateBody('project_reimbursement','approve');approval.p_payload.proposalHash='bad';assert.throws(()=>validateRemainingCommand('wave5_cash_date_command',approval));
});
test('governed export envelope rejects filename, source, format and filters drift',()=>{
 for(const change of [body=>body.p_payload.file_name='overwrite.csv',body=>body.p_payload.file_format='xlsx',body=>body.p_payload.filters={all:true},
  body=>body.p_payload.source_hash='bad',body=>body.p_payload.file_sha256='bad',body=>body.p_payload.file_size=0,
  body=>body.p_payload.file_size=10485761,body=>body.p_payload.columns=['record_type','record_type'],body=>body.p_expected_entity_version='1',
  body=>body.p_client_timestamp='tomorrow',body=>body.p_payload.source_id=id('statement.balance_sheet')]){
  const body=exportBody('statement');change(body);assert.throws(()=>validateRemainingCommand('record_report_export',body));
 }
});
test('legitimate statement and export appends preserve original and complete prior source separately',()=>{
 const before=state();assert.equal(validateRemainingState(before.facts,before.observation,{wholeSourceHash:CURRENT_WHOLE_SOURCE_HASH}).documentedProcessAppends,3);
 const after=state(true);assert.equal(validateRemainingState(after.facts,after.observation,{after:true,wholeSourceHash:digest,priorCompleteSourceHash:CURRENT_WHOLE_SOURCE_HASH}).documentedProcessAppends,5);
 assert.throws(()=>validateRemainingState(after.facts,after.observation,{after:true,wholeSourceHash:digest,priorCompleteSourceHash:digest}),/EXPORT_PROCESS_APPEND_RAW_DIGEST_REQUIRED/);
 assert.throws(()=>validateRemainingState(after.facts,after.observation,{after:true,wholeSourceHash:CURRENT_WHOLE_SOURCE_HASH,priorCompleteSourceHash:CURRENT_WHOLE_SOURCE_HASH}));
});
test('preflight blocks any original source drift, additional dates/exports/scenarios or missing journal',()=>{
 for(const change of [facts=>facts.sourceHash=digest,facts=>facts.dateDecisions=2,facts=>facts.dateProposals=2,facts=>facts.exports=1,
  facts=>facts.scenarios=1,facts=>facts.journalIds.pop(),facts=>facts.lines=19,facts=>facts.publications=4]){
  const current=state();change(current.facts);assert.throws(()=>validateRemainingState(current.facts,current.observation,{wholeSourceHash:CURRENT_WHOLE_SOURCE_HASH}),/EXACT_REMAINING_FINANCE_STATE_REQUIRED/);
 }
});
test('no exact PID absence can bypass fresh all-invocation, receipt and proposal checks',()=>{
 for(const name of ['activeCashApiInvocations','staleReceipts','staleProposals']){
  const current=state();current.observation[name]=1;assert.throws(()=>validateRemainingState(current.facts,current.observation,{wholeSourceHash:CURRENT_WHOLE_SOURCE_HASH}),/ORIGINAL_CASH_UNCERTAINTY_MUST_BE_QUIESCENT/);
  assert.throws(()=>validateRemainingQuiescence(current.observation),/ORIGINAL_CASH_UNCERTAINTY_MUST_BE_QUIESCENT/);
 }
});
test('append manifest rejects duplicate identities, wrong command/source/actor and extra original rows',()=>{
 for(const change of [o=>o.originalProcessRows=5,o=>o.processAppends.pop(),o=>o.processAppends.push(clone(o.processAppends[0])),
  o=>o.processAppends[0].actorId=id('foreign'),o=>o.processAppends[0].documentId=id('wrong.report'),o=>o.processAppends[0].documentType='other',
  o=>o.processAppends[0].toStatus='draft',o=>o.processAppends[0].fromStatus='draft',o=>o.processAppends[0].id=o.processAppends[1].id]){
  const current=state();change(current.observation);assert.throws(()=>validateRemainingState(current.facts,current.observation,{wholeSourceHash:CURRENT_WHOLE_SOURCE_HASH}));
 }
});
test('immutable hash recipes exclude only the reviewed appended command IDs',()=>{
 const clause="FROM workflow.process_events x WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'";
 const list=rows=>rows.map(row=>`'${row.commandId}'::uuid`).join(',');
 assert.equal(REMAINING_BASELINE_SQL.replace(clause+` AND command_id NOT IN (${list(EXPECTED_PROCESS_APPENDS)})`,clause),FINANCE_FACTS_SQL);
 assert.equal(REMAINING_PRIOR_COMPLETE_SQL.replace(clause+` AND command_id NOT IN (${list(EXPECTED_PROCESS_APPENDS.slice(3))})`,clause),FINANCE_FACTS_SQL);
});
test('activity predicate has identifier boundaries and excludes observer SQL text',()=>{
 const localPattern=new RegExp(REMAINING_ACTIVITY_PATTERN.replaceAll('[[:alnum:]]','[A-Za-z0-9]').replaceAll('[:alnum:]','A-Za-z0-9').replaceAll('[[:space:]]','\\s'));
 for(const query of ['SELECT "api"."wave5_cash_date_command"(x)','SELECT api.wave5_cash_date_command(x)','SELECT api . "wave5_cash_date_command" (x)'])assert.equal(localPattern.test(query),true);
 for(const query of ['SELECT other_api.wave5_cash_date_command(x)','SELECT otherapi.wave5_cash_date_command(x)',
  'SELECT "other_api"."wave5_cash_date_command"(x)','SELECT "api.wave5_cash_date_command"(x)','SELECT api.wave5_cash_date_command_more(x)'])assert.equal(localPattern.test(query),false);
 assert.ok(REMAINING_ACTIVITY_SQL.includes(`query ~ '${REMAINING_ACTIVITY_PATTERN}'`));
 assert.ok(REMAINING_ACTIVITY_SQL.includes("position('pg_stat_activity' in query)=0"));
});
test('installed source guard requires all seven exact MD5s and rejects overloads',()=>{
 const rows=Object.entries(REMAINING_FUNCTION_MD5).map(([proname,definition_md5])=>({proname,definition_md5}));assert.doesNotThrow(()=>validateRemainingFunctions(rows));
 for(const changed of [rows.slice(1),[...rows,rows[0]],rows.map((row,i)=>i?row:{...row,definition_md5:'0'.repeat(32)})])assert.throws(()=>validateRemainingFunctions(changed));
});
test('deterministic request bound preserves 75 prior attempts and one original read-only resolution',()=>{
 const budget=createRemainingBudget({now:()=>1000,startedAt:1000});for(let i=0;i<74;i++)budget.claim();
 assert.deepEqual(budget.snapshot(),{priorRequestBound:75,actualRemainingAttempts:74,totalRequestBound:149,
  previousFirstAttemptObservedRequests:null,previousFirstAttemptConservativeReserve:40,previousResumeObservedRequests:35});
 assert.throws(()=>budget.claim(),/REMAINING_REQUEST_BOUND_EXCEEDED/);assert.equal(budget.snapshot().actualRemainingAttempts,74);
 budget.claim({resolution:true});assert.equal(budget.snapshot().totalRequestBound,150);assert.throws(()=>budget.claim({resolution:true}),/SINGLE_ORIGINAL_READONLY_RESOLUTION_REQUIRED/);
 assert.throws(()=>createRemainingBudget({priorRequestBound:35}),/EXACT_REMAINING_REQUEST_RESERVE_REQUIRED/);
});
test('deadline reserve uses a deterministic single observation and never increments failed dispatches',()=>{
 let now=0;const budget=createRemainingBudget({now:()=>now,startedAt:0});now=855000;budget.claim();
 for(const later of [855001,-1,NaN]){now=later;assert.throws(()=>budget.claim(),/REMAINING_EXECUTION_DEADLINE_REQUIRED/);}
 assert.equal(budget.snapshot().actualRemainingAttempts,1);
});
test('both acknowledged intents precede dispatch and acknowledged validation result precedes success',async()=>{
 const order=[],writer=createRemainingCommandWriter(writerOptions({appendPrivate:async()=>{order.push('private-intent');return writerOptions().appendPrivate();},
 appendPublic:async entry=>{order.push(entry.kind);return writerOptions().appendPublic(entry);},send:async()=>{order.push('send');return response();}}));
 await writer.write(actor(),'wave5_cash_date_command',dateBody(),()=>order.push('validate'));
 assert.deepEqual(order,['private-intent','remaining-finance-command-intent','send','validate','remaining-finance-command-result']);assert.equal(writer.pending(),null);
});
test('failed private or public intent append prevents all transport and stops subsequent commands',async()=>{
 for(const failing of ['appendPrivate','appendPublic']){
  let sends=0;const writer=createRemainingCommandWriter(writerOptions({[failing]:async()=>{throw Error('controlled append failure');},send:async()=>{sends++;return response();}}));
  await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody(),validate));assert.equal(sends,0);assert.equal(writer.pending().commandId,dateBody().p_command_id);
  await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody('project_reimbursement'),validate),/REMAINING_COMMAND_JOURNAL_STOPPED/);assert.equal(sends,0);
 }
});
test('missing intent receipt acknowledgements cannot authorize dispatch',async()=>{
 for(const override of [{appendPrivate:async()=>null},{appendPrivate:async()=>'unacknowledged'},
  {appendPublic:async()=>({path:'controlled.json',sha256:'bad'})}]){
  let sends=0;const writer=createRemainingCommandWriter(writerOptions({...override,send:async()=>{sends++;return response();}}));
  await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody(),validate));assert.equal(sends,0);
 }
});
test('caller body mutation during receipt wait cannot change the already journaled original',async()=>{
 const held=deferred(),entered=deferred(),body=dateBody(),original=clone(body);let sent;
 const writer=createRemainingCommandWriter(writerOptions({appendPrivate:async()=>{entered.resolve();await held.promise;return writerOptions().appendPrivate();},
 send:async(_actor,_name,payload)=>{sent=payload;return response();}}));
 const pending=writer.write(actor(),'wave5_cash_date_command',body,validate);await entered.promise;
 body.p_payload.sourceId=id('changed.after.intent');body.p_command_id=STALE_COMMAND;held.resolve();await pending;
 assert.deepEqual(sent,original);assert.equal(Object.isFrozen(sent.p_payload),true);
});
test('concurrent writes cannot dispatch a second preparation while the first waits for receipt',async()=>{
 const held=deferred(),entered=deferred();let sends=0;
 const writer=createRemainingCommandWriter(writerOptions({appendPrivate:async()=>{entered.resolve();await held.promise;return writerOptions().appendPrivate();},send:async()=>{sends++;return response();}}));
 const first=writer.write(actor(),'wave5_cash_date_command',dateBody(),validate);await entered.promise;
 await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody('project_reimbursement'),validate),/REMAINING_COMMAND_JOURNAL_STOPPED/);
 assert.equal(sends,0);held.resolve();await first;assert.equal(sends,1);
});
test('cancellation during either receipt wait prevents actual dispatch',async()=>{
 for(const stage of ['private','public']){
  const held=deferred(),entered=deferred(),abort=new AbortController();let sends=0;
  const options=writerOptions({signal:abort.signal,send:async()=>{sends++;return response();}});
  if(stage==='private')options.appendPrivate=async()=>{entered.resolve();await held.promise;return writerOptions().appendPrivate();};
  else options.appendPublic=async entry=>{entered.resolve();await held.promise;return writerOptions().appendPublic(entry);};
  const writer=createRemainingCommandWriter(options),pending=writer.write(actor(),'wave5_cash_date_command',dateBody(),validate);
  await entered.promise;abort.abort();held.resolve();await assert.rejects(pending,/REMAINING_COMMAND_JOURNAL_STOPPED/);assert.equal(sends,0);
 }
});
test('uncertain transport, rejected response, validator or result append retain original IDs and prohibit successor dispatch',async()=>{
 for(const failure of ['transport','response','validation','result']){
  let sends=0;const writer=createRemainingCommandWriter(writerOptions({send:async()=>{sends++;if(failure==='transport')throw Error('controlled unknown outcome');
   return failure==='response'?{ok:false,status:500,value:{code:'XX000'}}:response();},appendPublic:async entry=>{
    if(failure==='result'&&entry.kind==='remaining-finance-command-result')throw Error('controlled result append failure');return writerOptions().appendPublic(entry);}}));
  await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody(),()=>{if(failure==='validation')throw Error('controlled validation failure');}));
  assert.equal(writer.pending().commandId,dateBody().p_command_id);assert.equal(sends,1);
  await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody('project_reimbursement'),validate),/REMAINING_COMMAND_JOURNAL_STOPPED/);assert.equal(sends,1);
 }
});
test('wrong actor, unverified MFA and omitted response validator fail before journaling',async()=>{
 let appends=0;const writer=createRemainingCommandWriter(writerOptions({appendPrivate:async()=>{appends++;return writerOptions().appendPrivate();}}));
 await assert.rejects(writer.write(actor(true),'wave5_cash_date_command',dateBody(),validate),/GENUINE_REMAINING_ACTOR_REQUIRED/);
 const unverified=actor();unverified.proof.serverSessionRowVerified=false;await assert.rejects(writer.write(unverified,'wave5_cash_date_command',dateBody(),validate));
 await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody()),/REMAINING_RESPONSE_VALIDATOR_REQUIRED/);assert.equal(appends,0);
});
function localTransport(){const requests=[];let sends=0;
 const transport=createFinanceHttpsTransport({apiKey:'controlled-anon-key',agentFactory:()=>({destroy(){}}),requestFactory(url,options,receive){
  const request=new EventEmitter();request.destroy=()=>{};request.end=()=>{sends++;queueMicrotask(()=>{const response=new EventEmitter();response.statusCode=500;
   receive(response);response.emit('data',Buffer.from('{"code":"40001","message":"CASH_DATE_VERSION_CONFLICT"}'));response.emit('end');});};
  requests.push({url,options,request});return request;}});return {transport,requests,sends:()=>sends};
}
test('new transport still requires exact scope and verified TLS before private request bytes',async()=>{
 const local=localTransport(),handle=local.transport.connection();
 try{
  await assert.rejects(local.transport.send(handle,'/rest/v1/rpc/delete_user',{body:FINANCE_SCOPED_BODY,profile:'api',bearer:'controlled-token'}));
  await assert.rejects(local.transport.send(handle,'/rest/v1/rpc/wave5_cash_date_command',{body:{...FINANCE_SCOPED_BODY,p_tenant_id:id('foreign')},profile:'api',bearer:'controlled-token'}));
  assert.equal(local.requests.length,0);
  const pending=local.transport.send(handle,'/rest/v1/rpc/wave5_cash_date_command',{body:FINANCE_SCOPED_BODY,profile:'api',bearer:'controlled-token'});
  const socket=new EventEmitter();socket.encrypted=true;socket.authorized=false;local.requests[0].request.emit('socket',socket);assert.equal(local.sends(),0);
  socket.authorized=true;socket.emit('secureConnect');const received=await pending;assert.equal(local.sends(),1);assert.equal(financeDenial(received),'CASH_DATE_VERSION_CONFLICT');
  assert.equal(JSON.stringify(received).includes('controlled-token'),false);assert.equal(local.requests[0].options.rejectUnauthorized,true);
 }finally{local.transport.close();}
});
test('late verified TLS cannot send after a transport failure and exception detail stays private',async()=>{
 const local=localTransport();try{
  const pending=local.transport.send(local.transport.connection(),'/auth/v1/user',{method:'GET',bearer:'controlled-private-token'});
  const socket=new EventEmitter();socket.encrypted=true;socket.authorized=false;local.requests[0].request.emit('socket',socket);
  local.requests[0].request.emit('error',Error('controlled private detail'));
  await assert.rejects(pending,error=>error.publicCode==='FINANCE_TRANSPORT_UNCERTAIN'&&!error.message.includes('private detail'));
  socket.authorized=true;socket.emit('secureConnect');assert.equal(local.sends(),0);
 }finally{local.transport.close();}
});
test('original prepare replay requires full canonical value and actual raw response hash equality',()=>{
 const prepared={ok:true,value:{command_id:dateBody().p_command_id,entity:{id:dateBody().p_payload.id,version:'0',status:'prepared',proposalHash:digest}},responseSha256:digest};
 const replayed=clone(prepared);replayed.value={entity:{proposalHash:digest,status:'prepared',version:'0',id:dateBody().p_payload.id},command_id:dateBody().p_command_id};
 assert.deepEqual(validateRemainingReplay(prepared,replayed),{canonicalFullValueIdentical:true,rawResponseSha256Identical:true,
  originalPreparedResponseSha256:digest,originalReplayResponseSha256:digest});
});
test('a changed cached response cannot pass by retaining only original command and proposal hash',()=>{
 const prepared={ok:true,value:{command_id:dateBody().p_command_id,entity:{id:dateBody().p_payload.id,version:'0',status:'prepared',proposalHash:digest}},responseSha256:digest};
 for(const change of [value=>value.entity.status='approved',value=>value.entity.version='1',value=>value.entity.id=id('wrong.proposal'),value=>value.extra='unreviewed']){
  const replayed=clone(prepared);change(replayed.value);assert.throws(()=>validateRemainingReplay(prepared,replayed),/ACTUAL_ORIGINAL_REMAINING_DATE_REPLAY_REQUIRED/);
 }
});
test('canonical equality cannot conceal a changed raw body, missing hash or rejected replay',()=>{
 const prepared={ok:true,value:{command_id:dateBody().p_command_id,entity:{id:dateBody().p_payload.id,proposalHash:digest}},responseSha256:digest};
 for(const change of [value=>value.responseSha256=hashBytes('changed raw response'),value=>delete value.responseSha256,value=>value.ok=false]){
  const replayed=clone(prepared);change(replayed);assert.throws(()=>validateRemainingReplay(prepared,replayed),/ACTUAL_ORIGINAL_REMAINING_DATE_REPLAY_REQUIRED/);
 }
 const missing=clone(prepared);delete missing.responseSha256;assert.throws(()=>validateRemainingReplay(missing,missing));
});
test('altered replay fails inside response validation, retaining original ID and preventing a successor command',async()=>{
 const prepared={ok:true,value:{command_id:dateBody().p_command_id,entity:{id:dateBody().p_payload.id,status:'prepared',version:'0',proposalHash:digest}},responseSha256:digest};
 const changed=clone(prepared);changed.value.entity.status='approved';let sends=0,results=0;
 const writer=createRemainingCommandWriter(writerOptions({send:async()=>{sends++;return changed;},appendPublic:async entry=>{
  if(entry.kind==='remaining-finance-command-result')results++;return writerOptions().appendPublic(entry);}}));
 await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody(),(_value,replayed)=>validateRemainingReplay(prepared,replayed)),/ACTUAL_ORIGINAL_REMAINING_DATE_REPLAY_REQUIRED/);
 assert.equal(writer.pending().commandId,dateBody().p_command_id);assert.equal(results,0);assert.equal(sends,1);
 await assert.rejects(writer.write(actor(),'wave5_cash_date_command',dateBody('project_reimbursement'),validate),/REMAINING_COMMAND_JOURNAL_STOPPED/);assert.equal(sends,1);
});
