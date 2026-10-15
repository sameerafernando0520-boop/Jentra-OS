import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {EventEmitter} from 'node:events';
import {hashBytes,hashJson} from '../../../../tools/wave5/runtime_contract.mjs';
import {PROJECT,BUNDLE,ORGANIZATION} from '../../../../tools/wave5/approved_management_installer.mjs';
import {FINANCE_SCOPE,FINANCE_ACTOR,FINANCE_JOURNALS} from '../../../../tools/wave5/finance_cash_fixture_20261013_r5.mjs';
import {financeWorkflowId as id,receiptResolutionSql} from '../../../../tools/wave5/finance_cash_workflows_20261013_r5.mjs';
import {bindUuidSessionQuery} from '../../../../tools/wave5/enroll_mfa_management_20261013_r5.mjs';
import {createFinanceHttpsTransport,encodeFinanceCsv} from '../../../../tools/wave5/finance_https_transport_20261013_r5_a2.mjs';
import {REMAINING_FUNCTION_MD5,REMAINING_ACTIVITY_SQL,ORIGINAL_SOURCE_HASH,CURRENT_WHOLE_SOURCE_HASH,EXPECTED_PROCESS_APPENDS} from '../../../../tools/wave5/finance_remaining_20261014_r5_a3.mjs';
import {EXPORTS_PROFILE,EXPORTS_A5_SOURCE_BINDINGS,EXPORTS_DEPENDENCY,EXPORTS_REVIEWED_BUDGET,EXPORTS_ORIGINAL_WINDOW,EXPORTS_OWNER_REPLY,EXPORTS_RUNTIME_ID,EXPORTS_PROFILE_PATHS,EXPORTS_PRESERVED_BINDINGS,EXPORTS_SOURCE_PATHS,EXPORTS_COMMANDS,
 EXPORTS_FACTS_SQL,EXPORTS_SQL_SHA256,EXPORTS_FACTOR,EXPORTS_PIPELINE,EXPORTS_PIPELINE_BASIS,EXPORTS_ROWS,validateExportsWindow,validateExportsTime,
 EXPORTS_PLAN,createExportsCallGate,exportsCallDescriptors,runExportsContinuation,createExclusiveExportFiles,validateExportsDocument,
 validateExportsSessionPair,validateExportsProfile,validateExportsPreparation,validateExportsFinalReview,validateExportsConsumed,
 writeExportsEvidence,preflightExportsOperation} from '../../../../tools/wave5/finance_exports_20261014_r5_a6.mjs';
import {buildExportsPreparation} from '../../../../tools/wave5/prepare_finance_exports_20261014_r5_a6.mjs';

// Every Auth/database/request value below is controlled test data. None of these
// results is a genuine session, live export, database, native or release proof.
const base='docs/verification/wave5/task3-export-renewal-20261014';
const stamp='2026-10-14T14:00:00.000Z',now=()=>Date.parse(stamp),digest=hashBytes('controlled-evidence'),clone=structuredClone;
const testWindow={notBefore:'2026-10-14T13:30:00.000Z',edgeExpiresAt:'2026-10-14T15:30:00.000Z',scopeExpiresAt:'2026-10-14T15:30:00.000Z',privateExpiresAt:'2026-10-14T15:00:00.000Z',expiresAt:'2026-10-14T15:00:00.000Z'};
const writerId='11111111-1111-4111-8111-111111111111',freshId='22222222-2222-4222-8222-222222222222';
const response=value=>{const bytes=JSON.stringify(value);return {ok:true,status:200,value,responseSha256:hashBytes(bytes),responseBytes:Buffer.byteLength(bytes)};};
const readJson=file=>fs.readFile(file,'utf8').then(JSON.parse);
function publicState(after=false,registrations=[]){
 const facts={journals:9,lines:18,journalIds:FINANCE_JOURNALS.map(row=>row.id).sort(),publications:3,classifications:1,dateProposals:3,dateDecisions:3,
  scenarios:0,exports:after?2:0,sourceHash:ORIGINAL_SOURCE_HASH};
 return {observedAt:stamp,installedMigrationCount:115,installedApiFunctionCount:363,originalBaseline:clone(facts),
  wholeSource:{...facts,sourceHash:after?digest:CURRENT_WHOLE_SOURCE_HASH},sourceExcludingOnlyApprovedExportEvents:{...facts,sourceHash:CURRENT_WHOLE_SOURCE_HASH},
  observation:{observedAt:stamp,staleReceipts:0,staleProposals:0,activeCashApiInvocations:0,originalProcessRows:4,
   processAppends:EXPECTED_PROCESS_APPENDS.slice(0,after?5:3).map((row,i)=>({...row,id:id('controlled.process.'+i),fromStatus:null}))},
  functions:Object.entries(REMAINING_FUNCTION_MD5).map(([proname,definition_md5])=>({proname,definition_md5})),
  pipeline:{id:EXPORTS_PIPELINE,sourceCount:2,currencies:clone(EXPORTS_ROWS),sourceHash:EXPORTS_PIPELINE_BASIS,recordSha256:digest},
  statement:{id:id('statement.profit_loss'),kind:'profit_loss',recordSha256:digest},dateStateSha256:digest,
  approvedExportJobs:registrations.map(body=>({id:body.p_payload.id,actorId:FINANCE_ACTOR,resource:'wave3.'+body.p_payload.source_type,status:'completed',
   format:'csv',fileName:body.p_payload.file_name,fileSize:body.p_payload.file_size,rowCount:body.p_payload.source_type==='statement'?10:2,
   filters:{...body.p_payload,source_hash:body.p_payload.source_hash,file_sha256:body.p_payload.file_sha256},columns:body.p_payload.columns})),
  approvedExportReceipts:registrations.map(body=>({commandId:body.p_command_id,actorId:FINANCE_ACTOR,aggregateType:'report_export',aggregateId:body.p_payload.id,requestHash:digest}))};
}
function canonicalDocument(label){
 const pipeline=label==='pipeline',sourceId=pipeline?EXPORTS_PIPELINE:id('statement.profit_loss');
 return {version:1,metadata:{id:sourceId,version:1,tenant_id:FINANCE_SCOPE.tenantId,legal_entity_id:FINANCE_SCOPE.entityId,branch_id:FINANCE_SCOPE.branchId,
  working_branch_id:FINANCE_SCOPE.branchId,actor_id:FINANCE_ACTOR,source_type:pipeline?'w5_pipeline':'statement',source_id:sourceId,
  section:pipeline?'currencies':'accounts',filters:{},row_count:pipeline?2:10,...(pipeline?{source_basis_hash:EXPORTS_PIPELINE_BASIS}:{kind:'profit_loss'})},
  rows:pipeline?clone(EXPORTS_ROWS):Array.from({length:10},(_,i)=>({account_id:id('controlled.account.'+i),amount:i===0?'3000.000001':'0.000000',label:i===0?'Revenue, "quoted"\nline':'account '+i}))};
}
const preview=document=>{const canonical_text=JSON.stringify(document);return {canonical_text,source_hash:hashBytes(canonical_text)};};
async function scenario(options={}){
 const directory=await fs.mkdtemp(path.join(base,'controlled-export-')),files=await createExclusiveExportFiles(path.resolve(directory));
 const journal=[],calls=[],registrations=[],handles=[],documents={pipeline:canonicalDocument('pipeline'),statement:canonicalDocument('statement')};
 if(options.changeDocument)options.changeDocument(documents);
 const savedStatement={id:id('statement.profit_loss'),summary:{id:id('statement.profit_loss'),kind:'profit_loss',exactSaved:true}};
 let sequence=0,closed=false;
 const claim=(kind,route)=>{const ordinal=++sequence;calls.push({ordinal,kind,route});if(options.failOrdinal===ordinal){const error=Error('controlled network failure');error.publicCode='CONTROLLED_TRANSPORT_UNCERTAIN';throw error;}return ordinal;};
 const transport=createFinanceHttpsTransport({apiKey:'controlled-anonymous-api-key',requestFactory:(url,settings,onResponse)=>{
  const req=new EventEmitter();req.destroy=()=>{};
  req.end=bytes=>{try{
   const route=url.pathname+(url.search??''),body=bytes?JSON.parse(bytes):undefined;claim(route.startsWith('/auth/v1/')?'auth':'rpc',route);
   if(route.startsWith('/rest/v1/'))assert.equal(settings.rejectUnauthorized,true);
   let value={controlledAuth:true};
   if(route.endsWith('/report_export_preview'))value=preview(body.p_source_type==='w5_pipeline'?documents.pipeline:documents.statement);
   if(route.endsWith('/financial_statement_page'))value={summary:savedStatement.summary,items:documents.statement.rows,next_offset:null};
   if(route.endsWith('/record_report_export')){
    assert.deepEqual(Object.keys(body).filter(key=>key.startsWith('p_')&&['p_tenant_id','p_legal_entity_id','p_branch_id'].includes(key)).sort(),['p_branch_id','p_legal_entity_id','p_tenant_id']);
    registrations.push(clone(body));options.afterRegistration?.(body);
    if(options.failAfterRegistration)throw Error('controlled failure after an original dispatch');
    if(options.abortAfterRegistration){options.abortController.abort();req.emit('error',Error('controlled abort after dispatch'));return;}
    value={command_id:body.p_command_id,entity:{id:body.p_payload.id,actor_id:FINANCE_ACTOR,
     file_sha256:body.p_payload.file_sha256,source_hash:body.p_payload.source_hash}};
   }
   if(route.endsWith('/wave5_export_reopen')){const body=registrations[0].p_payload,p=preview(documents.pipeline);
    value={id:body.id,sourceHash:p.source_hash,fileHash:body.file_sha256,format:'csv',fileName:body.file_name,preparedAt:body.prepared_at,canonicalText:p.canonical_text};
    if(options.changeReopen)options.changeReopen(value);}
   const res=new EventEmitter();res.statusCode=200;onResponse(res);
   queueMicrotask(()=>{res.emit('data',Buffer.from(JSON.stringify(value)));res.emit('end');});
  }catch(error){req.emit('error',error);}};
  queueMicrotask(()=>{const socket=new EventEmitter();socket.encrypted=true;socket.authorized=options.badTls!==true;req.emit('socket',socket);
   if(!socket.authorized)socket.emit('secureConnect');});return req;
 }});
 const ports={
  async management(query){claim('management',query);
   let value;if(query===EXPORTS_FACTS_SQL){value=publicState(registrations.length===2,registrations);
    if(options.observedAt){value.observedAt=options.observedAt;value.observation.observedAt=options.observedAt;}
    if(options.changeState)options.changeState(value,registrations.length===2);
    value=[{export_continuation_facts:value}];}
   else if(query===REMAINING_ACTIVITY_SQL)value=[{observation:{...publicState().observation,observedAt:options.observedAt??stamp}}];
   else if(query.includes('FROM core.command_receipts'))value=[];
   else if(query.includes('FROM auth.sessions'))value=[{id:query.includes(writerId)?writerId:freshId}];
   else value=[{observed_at:stamp}];return response(value);
  },async keyReader(){claim('key','/api-keys?reveal=true');},
  async session(label,context){const handle=transport.connection();handles.push(handle);
   const sessionId=label==='writer'?writerId:(options.sameSession?writerId:freshId);
   for(const route of ['/auth/v1/token?grant_type=password',`/auth/v1/factors/${EXPORTS_FACTOR}/challenge`])await context.send(route,{},()=>transport.send(handle,route,{body:{}}));
   await context.management('POST','/database/query',{query:'SELECT statement_timestamp()::text AS observed_at',read_only:true});
   await context.send(`/auth/v1/factors/${EXPORTS_FACTOR}/verify`,{},()=>transport.send(handle,`/auth/v1/factors/${EXPORTS_FACTOR}/verify`,{body:{}}));
   await context.send('/auth/v1/user',{method:'GET'},()=>transport.send(handle,'/auth/v1/user',{method:'GET'}));
   await context.management('POST','/database/query',{query:bindUuidSessionQuery(sessionId,FINANCE_ACTOR),read_only:true});
   const proof={actorId:FINANCE_ACTOR,factorId:EXPORTS_FACTOR,sessionId,aal:'aal2',onlineAuthVerified:true,serverSessionRowVerified:true,constructedAalClaims:false};
   if(options.changeProof)options.changeProof(proof,label);
   return {proof,request:(route,body)=>transport.send(handle,route,{body,profile:'api',bearer:'controlled-opaque-test-bearer',signal:options.abortController?.signal})};
  },async appendPrivate(kind,record){journal.push({kind,record:clone(record),private:true});
   if(options.failPrivateIntent)throw Error('controlled unacknowledged private intent');
   return 'runtime-remaining-finance-command-intent-33333333-3333-4333-8333-333333333333.sealed.json';},
  async persist(file,value){journal.push({file,value:clone(value),persistedBeforeValidation:value.validationPending===true});
   if(options.failPersist?.(file,value))throw Error('controlled unacknowledged public evidence');
   return writeExportsEvidence('',file,value,{evidenceRoot:path.resolve(directory)});},
  writeFile:files.write,async readFile(file){const bytes=await files.read(file);return options.tamperBytes?Buffer.concat([bytes,Buffer.from('tamper')]):bytes;},
  async close(){closed=true;transport.close();}
 };
 return {ports,journal,calls,registrations,directory,savedStatement,documents,closed:()=>closed,
  run:(overrides={})=>runExportsContinuation({ports,planSha256:digest,savedStatement,now:options.now??now,signal:options.abortController?.signal,
   window:options.window??testWindow,...overrides})};
}

test('actual controlled TLS transport, durable journals and disk bytes complete the exact 24-call export contract',async()=>{
 const s=await scenario(),result=await s.run();assert.equal(result.actualOrdinaryAttempts,24);assert.equal(result.totalWorkflowRequestBound,162);
 assert.equal(s.calls.length,24);assert.equal(s.calls.filter(row=>row.kind==='auth').length,8);assert.equal(s.calls.filter(row=>row.kind==='management').length,8);
 assert.deepEqual(s.registrations.map(body=>body.p_command_id),EXPORTS_COMMANDS.map(row=>row.commandId));assert.equal(s.closed(),true);
 assert.equal(result.artifacts[0].rowCount,2);assert.equal(result.artifacts[1].rowCount,10);assert.equal(result.registeredStatementReopen,false);
 for(const artifact of result.artifacts){const bytes=await fs.readFile(path.join(s.directory,artifact.fileName));assert.equal(hashBytes(bytes),artifact.fileSha256);
  assert.ok(bytes.includes(Buffer.from('2000.125000'))||bytes.includes(Buffer.from('3000.000001')));}
 const firstPrivate=s.journal.findIndex(row=>row.private),firstPublic=s.journal.findIndex(row=>row.value?.kind==='remaining-finance-command-intent');
 assert.ok(firstPrivate>=0&&firstPublic>firstPrivate);assert.equal(s.journal.find(row=>row.file==='00-before-response.json').persistedBeforeValidation,true);
});
for(let ordinal=1;ordinal<=24;ordinal++)test(`network attempt ${ordinal} is charged once and stops without retry or extra business commands`,async()=>{
 const s=await scenario({failOrdinal:ordinal});let failure;try{await s.run();}catch(error){failure=error;}assert.ok(failure);
 const reserved=[17,22].includes(ordinal)?1:0;assert.equal(s.calls.length,ordinal+reserved);
 assert.equal(failure.exportStop.actualOrdinaryAttempts,ordinal);assert.equal(failure.exportStop.actualReadOnlyResolutionAttempts,reserved);
 assert.equal(failure.exportStop.totalWorkflowRequestBound,138+ordinal+reserved);assert.equal(s.closed(),true);
 assert.equal(new Set(s.registrations.map(body=>body.p_command_id)).size,s.registrations.length);
 assert.ok(s.calls.every(row=>row.kind!=='rpc'||!/cash_date|generate_financial_statement|wave5_cash_save/.test(row.route)));
});
test('unacknowledged result keeps original command pending and performs exactly one readonly resolution',async()=>{
 let failed=false;const s=await scenario({failPersist:(file,value)=>{if(!failed&&value.kind==='remaining-finance-command-result'){failed=true;return true;}return false;}});
 await assert.rejects(s.run(),error=>{assert.equal(error.exportStop.lastOriginalCommand.commandId,EXPORTS_COMMANDS[0].commandId);
  assert.equal(error.exportStop.actualOrdinaryAttempts,17);assert.equal(error.exportStop.actualReadOnlyResolutionAttempts,1);return true;});
 assert.equal(s.registrations.length,1);assert.equal(s.calls.at(-1).route,receiptResolutionSql(EXPORTS_COMMANDS[0].commandId));assert.equal(s.closed(),true);
});
test('failed private intent and failed public intent both prevent any registration dispatch',async()=>{
 for(const options of [{failPrivateIntent:true},{failPersist:(_file,value)=>value.kind==='remaining-finance-command-intent'}]){
  const s=await scenario(options);await assert.rejects(s.run());assert.equal(s.registrations.length,0);assert.equal(s.calls.length,15);assert.equal(s.closed(),true);}
});
test('invalid controlled returned state is durably recorded before validation blocks all Auth and exports',async()=>{
 const s=await scenario({changeState:value=>value.originalBaseline.dateDecisions=2});await assert.rejects(s.run());
 assert.equal(s.calls.length,1);assert.equal(s.journal[0].value.rows[0].export_continuation_facts.originalBaseline.dateDecisions,2);
 assert.equal(s.journal[0].persistedBeforeValidation,true);assert.equal(s.closed(),true);
});
test('lost preflight persistence blocks all following requests despite a successful transport',async()=>{
 const s=await scenario({failPersist:file=>file==='00-before-response.json'});await assert.rejects(s.run());assert.equal(s.calls.length,1);assert.equal(s.closed(),true);
});
for(const [name,change] of [['currency coercion',d=>d.pipeline.rows[1].currency='LKR'],['numeric amount',d=>d.pipeline.rows[0].amount=2000.125],
 ['wrong source',d=>d.pipeline.metadata.source_id=id('other.pipeline')],['source basis substituted with canonical hash',d=>d.pipeline.metadata.source_basis_hash=digest]])
 test(`immutable pipeline rejects ${name} before registration`,async()=>{const s=await scenario({changeDocument:change});await assert.rejects(s.run());assert.equal(s.registrations.length,0);});
test('registered pipeline raw canonical mismatch cannot be normalized into a valid CSV reopen',async()=>{
 const s=await scenario({changeReopen:value=>value.canonicalText+=' '});await assert.rejects(s.run());assert.equal(s.registrations.length,1);assert.equal(s.calls.length,18);
});
test('changed saved bytes prevent registration even when the generated CSV hash is correct',async()=>{
 const s=await scenario({tamperBytes:true});await assert.rejects(s.run());assert.equal(s.registrations.length,0);assert.equal(s.calls.length,15);
});
test('same session ID and weakened genuine proof flags stop before source preview',async()=>{
 for(const options of [{sameSession:true},{changeProof:p=>p.aal='aal1'},{changeProof:p=>p.onlineAuthVerified=false},{changeProof:p=>p.serverSessionRowVerified=false}]){
  const s=await scenario(options);await assert.rejects(s.run());assert.equal(s.calls.length,14);assert.equal(s.registrations.length,0);assert.equal(s.closed(),true);}
});
test('post-export source or date hash drift remains failure with both original receipts preserved',async()=>{
 const s=await scenario({changeState:(value,after)=>{if(after)value.dateStateSha256=hashBytes('changed dates');}});await assert.rejects(s.run());
 assert.equal(s.registrations.length,2);assert.equal(s.calls.length,24);assert.equal(s.journal.at(-1).value.liveGateComplete,false);
});
test('unverified TLS never sends synthetic credentials or reaches later operations',async()=>{
 const s=await scenario({badTls:true});await assert.rejects(s.run());assert.equal(s.calls.length,2);assert.equal(s.registrations.length,0);assert.equal(s.closed(),true);
});
test('gate rejects wrong order, altered SQL and overlapping dispatches before charging them',async()=>{
 const gate=createExportsCallGate({now,window:testWindow}),slots=exportsCallDescriptors();let releases,dispatched=0;
 await assert.rejects(gate.dispatch(slots[1],()=>{dispatched++;}));assert.equal(dispatched,0);
 await assert.rejects(gate.dispatch({...slots[0],query:'SELECT 1'},()=>{dispatched++;}));assert.equal(dispatched,0);
 const pending=gate.dispatch(slots[0],()=>new Promise(resolve=>{releases=resolve;}));await assert.rejects(gate.dispatch(slots[0],()=>{dispatched++;}));
 releases(response([]));await pending;assert.equal(gate.snapshot().actualOrdinaryAttempts,1);
});
test('ordinary dispatch reserves 45s in-flight plus 45s resolution at run and scope boundaries',async()=>{
 let clock=now();const started=clock,gate=createExportsCallGate({now:()=>clock,startedAt:started,window:testWindow});clock=started+810000;
 await gate.dispatch(exportsCallDescriptors()[0],async()=>response([]));clock++;
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[1],async()=>response([])),/RESERVED/);
 gate.stop();clock=started+855000;await gate.dispatch({kind:'resolution',method:'POST',route:'/database/query',query:receiptResolutionSql(EXPORTS_COMMANDS[0].commandId)},
  async()=>response([]),{resolutionCommand:EXPORTS_COMMANDS[0].commandId});
 await assert.rejects(gate.dispatch({kind:'resolution',method:'POST',route:'/database/query',query:receiptResolutionSql(EXPORTS_COMMANDS[0].commandId)},async()=>response([]),
  {resolutionCommand:EXPORTS_COMMANDS[0].commandId}));
 const expiresAt=new Date(started+90000).toISOString(),scopeGate=createExportsCallGate({now:()=>started+1,startedAt:started,window:{...testWindow,privateExpiresAt:expiresAt,expiresAt}});
 await assert.rejects(scopeGate.dispatch(exportsCallDescriptors()[0],async()=>response([])),/RESERVED/);
});
test('the 25th ordinary call and any unknown resolution identity are rejected without dispatch',async()=>{
 const gate=createExportsCallGate({now,window:testWindow});for(const slot of exportsCallDescriptors()){
  const request=slot.kind==='session-row'?{...slot,query:bindUuidSessionQuery(writerId,FINANCE_ACTOR)}:slot;await gate.dispatch(request,async()=>response([]));}
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[0],async()=>assert.fail('extra dispatch')));assert.equal(gate.snapshot().totalWorkflowRequestBound,162);
 gate.stop();await assert.rejects(gate.dispatch({kind:'resolution',method:'POST',route:'/database/query',query:receiptResolutionSql(id('unknown.command'))},async()=>assert.fail('unknown receipt'),
  {resolutionCommand:id('unknown.command')}));
});
test('disk artifacts are exclusive, bounded, correctly hashed and reject paths outside the two original names',async()=>{
 const directory=await fs.mkdtemp(path.join(base,'controlled-file-')),files=await createExclusiveExportFiles(path.resolve(directory));
 const document=canonicalDocument('pipeline'),artifact=encodeFinanceCsv(document,{exportId:EXPORTS_COMMANDS[0].documentId,preparedAt:stamp,sourceHash:hashJson(document)});
 const saved=await files.write('Jentra-W5-Synthetic-pipeline.csv',artifact.bytes);assert.equal(saved.sha256,artifact.sha256);
 await assert.rejects(files.write('Jentra-W5-Synthetic-pipeline.csv',Buffer.from('overwrite')),/EEXIST/);
 assert.ok((await files.read('Jentra-W5-Synthetic-pipeline.csv')).equals(artifact.bytes));
 await assert.rejects(files.write('../escape.csv',artifact.bytes));await assert.rejects(files.write('Jentra-W5-Synthetic-statement.csv',Buffer.alloc(10485761)));
});
test('CSV codec preserves quoted/newline text and exact decimal strings; canonical hash differs from source basis',()=>{
 const document=canonicalDocument('statement'),p=preview(document);validateExportsDocument(p,'statement');
 const csv=encodeFinanceCsv(document,{exportId:EXPORTS_COMMANDS[1].documentId,preparedAt:stamp,sourceHash:p.source_hash});
 assert.ok(csv.bytes.includes(Buffer.from('"Revenue, ""quoted""\nline"')));assert.ok(csv.bytes.includes(Buffer.from('3000.000001')));
 assert.notEqual(preview(canonicalDocument('pipeline')).source_hash,EXPORTS_PIPELINE_BASIS);assert.equal(hashBytes(EXPORTS_FACTS_SQL),EXPORTS_SQL_SHA256);
});
test('abort after registration dispatch still persists one resolution and stop without a resend',async()=>{
 const abortController=new AbortController(),s=await scenario({abortController,abortAfterRegistration:true});
 await assert.rejects(s.run(),error=>{assert.equal(error.exportStop.actualOrdinaryAttempts,17);assert.equal(error.exportStop.actualReadOnlyResolutionAttempts,1);
  assert.equal(error.exportStop.resolution.commandId,EXPORTS_COMMANDS[0].commandId);return true;});
 assert.equal(s.registrations.length,1);assert.equal(s.calls.length,18);assert.equal(s.closed(),true);
 assert.ok(s.journal.some(row=>row.file==='99-pending-original-export-resolution.json'));
 assert.ok(s.journal.some(row=>row.file==='99-stop.json'));
});
test('slow startup cannot reset the original run deadline or dispatch with less than90 seconds remaining',async()=>{
 const s=await scenario();await assert.rejects(s.run({startedAt:now()-810001}));assert.equal(s.calls.length,0);assert.equal(s.closed(),true);
});
test('a stalled evidence callback is bounded and closes the transport instead of waiting forever',async()=>{
 const s=await scenario(),persist=s.ports.persist;s.ports.persist=(file,value)=>file==='00-before-response.json'?new Promise(()=>{}):persist(file,value);
 const started=Date.now();await assert.rejects(s.run({portTimeoutMs:200}));assert.ok(Date.now()-started<2000);
 assert.equal(s.calls.length,1);assert.equal(s.closed(),true);
});
for(const boundary of ['run','authority'])test(`failure at exact ${boundary} expiry forbids a late resolution but persists stop after close`,async()=>{
 let clock=now();const end=boundary==='run'?now()+900000:now()+300000;
 const s=await scenario({now:()=>clock,afterRegistration:()=>clock=end,failAfterRegistration:true});
 await assert.rejects(s.run({startedAt:now(),window:{...testWindow,privateExpiresAt:new Date(boundary==='authority'?end:now()+3600000).toISOString(),expiresAt:new Date(boundary==='authority'?end:now()+3600000).toISOString()}}),error=>{
  assert.equal(error.exportStop.actualOrdinaryAttempts,17);assert.equal(error.exportStop.actualReadOnlyResolutionAttempts,0);
  assert.equal(error.exportStop.resolution.readOnlyResolutionUnavailable,true);return true;});
 assert.equal(s.calls.length,17);assert.equal(s.registrations.length,1);assert.equal(s.closed(),true);
 assert.equal(s.journal.at(-1).file,'99-stop.json');
});
// The following approval/readback/profile values are controlled test objects
// only. No future public control file is created by these tests.
async function publicPreparationInputs(){
 const snapshot='build/wave5-approved-execution-20261013-r5-a2/',preserved={};
 for(const [name,binding] of Object.entries(EXPORTS_PRESERVED_BINDINGS))preserved[name]=await readJson(snapshot+binding.path);
 const oldPlan=preserved.a3Plan,sourceBindings=[];
 for(const binding of [...oldPlan.sourceBindings,...Object.values(EXPORTS_PRESERVED_BINDINGS),...EXPORTS_A5_SOURCE_BINDINGS])
  if(!sourceBindings.some(row=>row.path===binding.path))sourceBindings.push(binding);
 const exportSourceBindings=[];
 for(const file of EXPORTS_SOURCE_PATHS){const binding={path:file,sha256:hashBytes(await fs.readFile(file))};sourceBindings.push(binding);exportSourceBindings.push(binding);}
 const controlBindings=Object.fromEntries(Object.entries(EXPORTS_PROFILE_PATHS).map(([name,file])=>[name,{path:file,sha256:digest}]));
 controlBindings.dependency=EXPORTS_DEPENDENCY;
 const sourcePolicy={kind:'source-only-export-a6-renewal-policy',projectId:PROJECT,runtimeBundleSha256:BUNDLE,runtimeId:EXPORTS_RUNTIME_ID,
  sourceImplementationOnly:true,liveExecutionAuthorized:false,originalConcreteCumulativeCap:150,budget:EXPORTS_REVIEWED_BUDGET,
  windowMode:'server-clock-at-application',maximumWindowMs:7200000,originalWindow:EXPORTS_ORIGINAL_WINDOW,dependencyBinding:EXPORTS_DEPENDENCY,
  permittedOriginalExportCommands:EXPORTS_COMMANDS,originalFixtureUtcDay:'2026-10-13',a5SourceBindings:EXPORTS_A5_SOURCE_BINDINGS,
  preservedOriginalSourceCount:68,consolidatedSqlSha256:EXPORTS_SQL_SHA256,maximumRunMs:900000,maximumRequestMs:45000,
  ordinaryReserveMs:90000,resolutionReserveMs:45000,transportRetries:0,unlistedCallsAllowed:0,schedulesMustRemainPaused:true,
  onlyTwoExpiryFieldsMayChange:true,renewalOperationBundleSha256:digest,exportSourceBindings:clone(exportSourceBindings)};
 const independentReview={kind:'independent-export-a6-policy-review',passed:true,sourceOnly:true,liveExecutionAuthorized:false,
  policyBinding:controlBindings.sourcePolicy,exportSourceBindings,budget:EXPORTS_REVIEWED_BUDGET,renewalOperationBundleSha256:digest,
  exactConsolidatedSqlSha256:EXPORTS_SQL_SHA256};
 const ownerDecision={kind:'direct-human-runtime-renewal-and-export-a6-decision',approved:true,approvalSource:'direct-user-reply',
  exactReply:EXPORTS_OWNER_REPLY,questionItemId:'CONTROLLED_TEST_ONLY_NEVER_AN_ACTUAL_HUMAN_REPLY',projectId:PROJECT,runtimeBundleSha256:BUNDLE,
  runtimeId:EXPORTS_RUNTIME_ID,sourcePolicyBinding:controlBindings.sourcePolicy,independentReviewBinding:controlBindings.independentReview,
  operationBundleSha256:digest,budget:EXPORTS_REVIEWED_BUDGET,maximumWindowMs:7200000,onlyTwoExpiryFieldsMayChange:true,schedulesMustRemainPaused:true,
  productionAuthorized:false,realBillingAuthorized:false,decidedAt:'2026-10-14T13:00:00.000Z'};
 const controlCallAccounting={attempts:3,failedAttempts:0,automaticRetries:0,receipts:['preflight','two-row-expiry-write','readback'].map((phase,i)=>
  ({ordinal:136+i,phase,successful:true,responseSha256:digest}))};
 const renewalReadback={kind:'actual-two-row-runtime-expiry-renewal-readback',actual:true,committed:true,projectId:PROJECT,runtimeId:EXPORTS_RUNTIME_ID,
  ownerDecisionBinding:controlBindings.ownerDecision,sourcePolicyBinding:controlBindings.sourcePolicy,operationBundleSha256:digest,
  appliedAt:testWindow.notBefore,observedAt:'2026-10-14T13:30:01.000Z',affectedRows:2,onlyTwoExpiryFieldsChanged:true,issuedAtUnchanged:true,
  nonWindowValuesUnchanged:true,jobsPaused:true,countersUnchanged:true,secretValuesRead:false,controlCallAccounting,
  scope:{count:1,runtimeId:EXPORTS_RUNTIME_ID,tenantId:FINANCE_SCOPE.tenantId,legalEntityId:FINANCE_SCOPE.entityId,branchId:FINANCE_SCOPE.branchId,
   issuedAt:EXPORTS_ORIGINAL_WINDOW.scopeIssuedAt,oldExpiresAt:EXPORTS_ORIGINAL_WINDOW.scopeExpiresAt,
   expiresAt:testWindow.scopeExpiresAt,nonWindowHash:EXPORTS_ORIGINAL_WINDOW.scopeNonWindowHash},
  edge:{count:1,runtimeId:EXPORTS_RUNTIME_ID,issuedAt:EXPORTS_ORIGINAL_WINDOW.edgeIssuedAt,oldExpiresAt:EXPORTS_ORIGINAL_WINDOW.edgeExpiresAt,
   expiresAt:testWindow.edgeExpiresAt,nonWindowHash:EXPORTS_ORIGINAL_WINDOW.edgeNonWindowHash}};
 const metadata={kind:'wave5-private-owner-input-metadata',projectId:PROJECT,runtimeBundleSha256:BUNDLE,metadataFilename:'metadata-renewed-a10.json',
  containsPlaintextCredential:false,reuseAuthorizationQuestionId:'["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]',
  createdAt:'2026-10-14T13:05:00.000Z',expiresAt:testWindow.privateExpiresAt,helperSha256:digest,refreshEvidence:controlBindings.refresh};
 const refresh={kind:'actual-private-owner-scope-refresh',projectId:PROJECT,organizationId:ORGANIZATION,actualStatus:'ACTIVE_HEALTHY',readOnlyOwnerApiCalls:1,
  actualVerifiedAt:metadata.createdAt,helperSha256:digest,databaseWrites:0,authWrites:0,settingsChanges:0};
 const dependency=await readJson(EXPORTS_DEPENDENCY.path);
 const accounting={kind:'conservative-renewed-export-a6-read-accounting',projectId:PROJECT,recordedPriorBinding:EXPORTS_DEPENDENCY,recordedPrior:134,
  chargedA10OwnerIdentityReads:1,chargedRenewalControlCalls:3,otherFinanceCallsSinceDependency:0,cumulativeChargedPriorCalls:138,
  actualA10Refresh:controlBindings.refresh,actualRenewalReadback:controlBindings.renewalReadback,renewalCallAccounting:controlCallAccounting};
 const profile={kind:'source-reviewed-renewed-export-a6-profile',projectId:PROJECT,runtimeBundleSha256:BUNDLE,priorConservativeBound:138,ordinaryAttempts:24,
  ordinaryLimit:162,cumulativeLimit:163,resolutionAttempts:1,originalFixtureUtcDay:'2026-10-13',personalHumanExactSourceSignatureClaimed:false,
  controlBindings,window:testWindow,privateAdapterPredecessor:{path:'scripts/wave5/run_private_management_installer_20261013_r5.ps1',sha256:digest}};
 return {profileBinding:{path:EXPORTS_PROFILE,sha256:digest},profile,documents:{sourcePolicy,independentReview,ownerDecision,renewalReadback,metadata,refresh,accounting,dependency},
  oldPlan,preserved,sourceBindings,preparedAt:stamp};
}
test('actual immutable evidence plus controlled renewal objects produce only a public plan for138/162/163',async()=>{
 const inputs=await publicPreparationInputs();assert.equal(validateExportsConsumed(inputs.preserved).reexecutionAllowed,false);
 const plan=buildExportsPreparation(inputs);assert.equal(plan.priorConservativeBound,138);assert.equal(plan.ordinaryLimit,162);assert.equal(plan.cumulativeLimit,163);
 assert.equal(plan.networkCallsDuringPreparation,0);assert.equal(plan.liveExecutionAuthorizedByPreparation,false);assert.equal(plan.publicBindings.length,9);
 assert.equal(plan.originalConcreteCap,150);assert.equal(plan.originalFixtureUtcDay,'2026-10-13');assert.equal(inputs.oldPlan.sourceBindings.length,68);
});
for(const [label,change] of [
 ['a5 profile',x=>x.profile.kind='source-reviewed-export-execution-profile'],
 ['stale132 prior',x=>x.profile.priorConservativeBound=132],['160 minimum',x=>x.profile.cumulativeLimit=160],
 ['unreviewed cap drift',x=>x.documents.sourcePolicy.budget={...EXPORTS_REVIEWED_BUDGET,total:164}],
 ['A9 metadata',x=>x.profile.controlBindings.metadata.path='docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json'],
 ['expired private proof',x=>x.documents.metadata.expiresAt='2026-10-14T05:53:48.705Z'],
 ['private TTL above2h',x=>x.documents.metadata.expiresAt='2026-10-14T15:05:00.001Z'],
 ['future private proof',x=>x.documents.metadata.createdAt='2026-10-14T14:00:00.001Z'],
 ['missing direct approval',x=>x.documents.ownerDecision.approved=false],
 ['delegated approval',x=>x.documents.ownerDecision.approvalSource='delegated-technical-decision'],
 ['old worker approval',x=>x.documents.ownerDecision.exactReply='Approve the exact V7 worker correction'],
 ['wrong approved bundle',x=>x.documents.ownerDecision.operationBundleSha256=hashBytes('different')],
 ['future approval',x=>x.documents.ownerDecision.decidedAt='2026-10-14T14:01:00.000Z'],
 ['wrong independent policy',x=>x.documents.independentReview.policyBinding={...x.profile.controlBindings.sourcePolicy,sha256:hashBytes('another')}],
 ['unreviewed source bytes',x=>x.documents.sourcePolicy.exportSourceBindings[0].sha256=hashBytes('another')],
 ['one row only',x=>x.documents.renewalReadback.affectedRows=1],
 ['scope row absent',x=>delete x.documents.renewalReadback.scope],
 ['edge row absent',x=>delete x.documents.renewalReadback.edge],
 ['old scope expiry',x=>x.documents.renewalReadback.scope.expiresAt=EXPORTS_ORIGINAL_WINDOW.scopeExpiresAt],
 ['unequal expiry rows',x=>x.documents.renewalReadback.edge.expiresAt='2026-10-14T15:29:00.000Z'],
 ['more than120min',x=>x.documents.renewalReadback.edge.expiresAt=x.documents.renewalReadback.scope.expiresAt='2026-10-14T15:30:00.001Z'],
 ['changed issued_at',x=>x.documents.renewalReadback.scope.issuedAt='2026-10-14T13:30:00.000Z'],
 ['changed row identity',x=>x.documents.renewalReadback.scope.branchId=writerId],
 ['changed non-window hash',x=>x.documents.renewalReadback.scope.nonWindowHash=digest],
 ['resumed jobs',x=>x.documents.renewalReadback.jobsPaused=false],
 ['reset counters',x=>x.documents.renewalReadback.countersUnchanged=false],
 ['readback before write',x=>x.documents.renewalReadback.observedAt='2026-10-14T13:29:59.000Z'],
 ['readback too delayed',x=>x.documents.renewalReadback.observedAt='2026-10-14T13:30:45.001Z'],
 ['future applied window',x=>x.documents.renewalReadback.appliedAt='2026-10-14T14:10:00.000Z'],
 ['uncommitted readback',x=>x.documents.renewalReadback.committed=false],
 ['missing renewal charges',x=>x.documents.accounting.chargedRenewalControlCalls=0],
 ['repeat refresh',x=>x.documents.refresh.readOnlyOwnerApiCalls=2],
 ['extra charged query',x=>x.documents.accounting.otherFinanceCallsSinceDependency=1],
 ['failed renewal attempt',x=>x.documents.renewalReadback.controlCallAccounting.failedAttempts=1],
 ['reset renewal ordinal',x=>x.documents.renewalReadback.controlCallAccounting.receipts[0].ordinal=1],
 ['missing receipt hash',x=>delete x.documents.renewalReadback.controlCallAccounting.receipts[0].responseSha256],
 ['unknown renewal phase',x=>x.documents.renewalReadback.controlCallAccounting.receipts[1].phase='unreviewed-write'],
 ['stale prior ledger',x=>x.documents.dependency.conservativeContinuationAccounting.cumulativeChargedCalls=133]
])test(`public profile refuses ${label} before preparation or execution`,async()=>{
 const inputs=clone(await publicPreparationInputs());change(inputs);assert.throws(()=>buildExportsPreparation(inputs));
});
test('omitted or changed original68, a5 sources and consumed intents fail public plan construction',async()=>{
 const inputs=await publicPreparationInputs();
 for(const file of [inputs.oldPlan.sourceBindings[0].path,EXPORTS_A5_SOURCE_BINDINGS[0].path,EXPORTS_PRESERVED_BINDINGS.a3Once.path]){
  const missing=clone(inputs);missing.sourceBindings=missing.sourceBindings.filter(row=>row.path!==file);assert.throws(()=>buildExportsPreparation(missing));
  const changed=clone(inputs);changed.sourceBindings=changed.sourceBindings.map(row=>({...row}));
  changed.sourceBindings.find(row=>row.path===file).sha256=digest;assert.throws(()=>buildExportsPreparation(changed));
 }
 const altered=clone(inputs);altered.oldPlan.sourceBindings.pop();assert.throws(()=>buildExportsPreparation(altered));
});
test('unlisted and duplicate public bindings are rejected',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs());
 for(const binding of [plan.profileBinding,{path:'private/unreviewed.env',sha256:digest}]){const altered=clone(plan);altered.publicBindings.push(binding);assert.throws(()=>validateExportsPreparation(altered));}
});
function finalReviewFor(plan){return {kind:'independent-renewed-export-a6-final-operation-review',technicalDecision:'approve',executionPermitted:true,
 projectId:PROJECT,runtimeBundleSha256:BUNDLE,generatedPlan:{path:EXPORTS_PLAN,sha256:digest},sourceBindings:plan.sourceBindings,
 executionProfileBinding:plan.profileBinding,controlBindings:plan.controlBindings,window:plan.window,
 privateAdapter:{beforeSha256:plan.privateAdapterPredecessor.sha256,afterSha256:digest},priorConservativeBound:138,ordinaryLimit:162,cumulativeLimit:163,
 ordinaryAttempts:24,resolutionAttempts:1,permittedOriginalExportCommands:EXPORTS_COMMANDS,originalFixtureUtcDay:'2026-10-13',
 directHumanDecisionVerified:true,actualTwoRowReadbackVerified:true,personalHumanExactSourceSignatureClaimed:false};}
test('final review binds exact owner, readback, policy, profile, window and adapter before private input',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs()),review=finalReviewFor(plan);
 assert.equal(validateExportsFinalReview(review,{plan,planSha256:digest},now()).executionPermitted,true);
 for(const change of [r=>r.executionPermitted=false,r=>r.generatedPlan.sha256=hashBytes('another plan'),r=>r.cumulativeLimit=160,
  r=>r.controlBindings={...r.controlBindings,ownerDecision:{...r.controlBindings.ownerDecision,sha256:hashBytes('wrong owner')}},
  r=>r.controlBindings={...r.controlBindings,renewalReadback:{...r.controlBindings.renewalReadback,sha256:hashBytes('wrong readback')}},
  r=>r.sourceBindings=r.sourceBindings.slice(1),r=>r.directHumanDecisionVerified=false,r=>r.actualTwoRowReadbackVerified=false,
  r=>r.technicalDecision='approve this source generally',r=>r.window={...r.window,expiresAt:'2026-10-14T15:30:00.000Z'}]){
  const changed=clone(review);change(changed);assert.throws(()=>validateExportsFinalReview(changed,{plan,planSha256:digest},now()));}
 assert.throws(()=>validateExportsFinalReview(review,{plan,planSha256:digest},Date.parse(plan.window.expiresAt)));
});
test('no missing or implicit deadline, malformed UTC, fabricated extra window fields or future not-before is accepted',()=>{
 for(const window of [undefined,{}, {...testWindow,scopeExpiresAt:undefined},{...testWindow,expiresAt:'2026-10-14T15:30:00.000Z'},
  {...testWindow,notBefore:'2026-10-14T14:00:01.000Z'},{...testWindow,notBefore:'2026-02-30T14:00:00.000Z'},
  {...testWindow,notBefore:'2026-10-14 13:30:00'},{...testWindow,notBefore:'2026-10-14T13:30:00+05:30'},
  {...testWindow,additionalAllowance:true}])assert.throws(()=>validateExportsTime(stamp,{now:now(),window}));
});
test('the approved window can span midnight while the immutable fixture day remainsUTC13',async()=>{
 const inputs=clone(await publicPreparationInputs()),start='2026-10-14T23:30:00.000Z',end='2026-10-15T01:30:00.000Z',current='2026-10-15T00:01:00.000Z';
 inputs.documents.ownerDecision.decidedAt='2026-10-14T23:00:00.000Z';
 inputs.documents.metadata.createdAt=inputs.documents.refresh.actualVerifiedAt='2026-10-14T23:20:00.000Z';
 inputs.documents.metadata.expiresAt='2026-10-15T01:20:00.000Z';
 inputs.documents.renewalReadback.appliedAt=start;inputs.documents.renewalReadback.observedAt='2026-10-14T23:30:01.000Z';
 inputs.documents.renewalReadback.edge.expiresAt=inputs.documents.renewalReadback.scope.expiresAt=end;
 inputs.profile.window={notBefore:start,edgeExpiresAt:end,scopeExpiresAt:end,privateExpiresAt:inputs.documents.metadata.expiresAt,expiresAt:inputs.documents.metadata.expiresAt};
 inputs.preparedAt=current;const plan=buildExportsPreparation(inputs);assert.equal(plan.originalFixtureUtcDay,'2026-10-13');
 assert.equal(validateExportsTime(current,{now:Date.parse(current),window:plan.window}),Date.parse(current));
 assert.throws(()=>validateExportsTime('2026-10-15T01:20:00.000Z',{now:Date.parse(current),window:plan.window}));
});
test('no mutable module window is shared by interleaved gates',async()=>{
 let clock=now();const short={...testWindow,privateExpiresAt:new Date(clock+90000).toISOString(),expiresAt:new Date(clock+90000).toISOString()},
  one=createExportsCallGate({now:()=>clock,window:short}),two=createExportsCallGate({now:()=>clock,window:testWindow});
 short.expiresAt=testWindow.expiresAt;clock++;
 await assert.rejects(one.dispatch(exportsCallDescriptors()[0],()=>assert.fail('expired reserve')));
 await two.dispatch(exportsCallDescriptors()[0],async()=>response([]));assert.equal(two.snapshot().actualOrdinaryAttempts,1);
});
test('actual prior134 dependency digest is immutable and no future actual control files were created',async()=>{
 assert.equal(hashBytes(await fs.readFile(EXPORTS_DEPENDENCY.path)),EXPORTS_DEPENDENCY.sha256);
 for(const file of [EXPORTS_PROFILE,...Object.entries(EXPORTS_PROFILE_PATHS).filter(([name])=>name!=='dependency').map(([,file])=>file)])
  await assert.rejects(fs.access(file),/ENOENT/);
 for(const binding of EXPORTS_A5_SOURCE_BINDINGS)assert.equal(hashBytes(await fs.readFile(binding.path)),binding.sha256);
});
test('public-only preflight reads only preparation, pinned final review and adapter and never requests private capabilities',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs()),review=finalReviewFor(plan),calls=[];
 const ready=await preflightExportsOperation({finalReviewSha256:digest,now,
  verifyPreparation:async()=>{calls.push('verify');return {plan,planSha256:digest};},
  readPublic:async(root,binding)=>{calls.push(binding.path);
   assert.equal(root,plan.publicEvidenceRoot);
   if(binding.path===plan.finalReviewPath)return Buffer.from(JSON.stringify(review));
   assert.equal(binding.path,plan.privateAdapterPredecessor.path);assert.equal(binding.sha256,review.privateAdapter.afterSha256);return Buffer.from('controlled adapter bytes');}
 });
 assert.deepEqual(calls,['verify',plan.finalReviewPath,plan.privateAdapterPredecessor.path]);
 assert.deepEqual(ready.publicResult,{passed:true,networkCalls:0,privateInputsRead:false,planSha256:digest,finalReviewSha256:digest});
 const source=await fs.readFile(EXPORTS_SOURCE_PATHS[0],'utf8'),body=source.slice(source.indexOf('export async function preflightExportsOperation('),source.indexOf('async function main()'));
 for(const forbidden of ['process.stdin','runtimeSealKey(','writeExportsEvidence(','appendRuntimeSecret(','createManagementTransport(','fs.open(','fs.mkdir('])assert.equal(body.includes(forbidden),false);
 assert.ok(source.indexOf("if(mode==='--preflight')")<source.indexOf('for await(const chunk of process.stdin)'));
});
test('invalid final review or its changed public bytes blocks adapter access during preflight',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs()),review=finalReviewFor(plan);review.directHumanDecisionVerified=false;
 let reads=0;await assert.rejects(preflightExportsOperation({finalReviewSha256:digest,now,verifyPreparation:async()=>({plan,planSha256:digest}),
  readPublic:async()=>{reads++;return Buffer.from(JSON.stringify(review));}}));assert.equal(reads,1);
 let verified=false;await assert.rejects(preflightExportsOperation({finalReviewSha256:'not-a-hash',now,
  verifyPreparation:async()=>{verified=true;return {plan,planSha256:digest};}}));assert.equal(verified,false);
 await assert.rejects(preflightExportsOperation({finalReviewSha256:digest,now,verifyPreparation:async()=>({plan,planSha256:digest}),
  readPublic:async()=>{throw Error('controlled exact public hash mismatch');}}),/hash mismatch/);
});
test('expiry during the public adapter read cannot return a valid preflight',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs()),review=finalReviewFor(plan);let clock=now();
 await assert.rejects(preflightExportsOperation({finalReviewSha256:digest,now:()=>clock,verifyPreparation:async()=>({plan,planSha256:digest}),
  readPublic:async(_root,binding)=>{if(binding.path===plan.finalReviewPath)return Buffer.from(JSON.stringify(review));
   clock=Date.parse(plan.window.expiresAt);return Buffer.from('adapter');}}),/WINDOW/);
});
test('all24 dispatches, genuine-session ports and CSV commands use an explicitly reviewed window spanning midnight',async()=>{
 const current='2026-10-15T00:01:00.000Z',window={notBefore:'2026-10-14T23:30:00.000Z',edgeExpiresAt:'2026-10-15T01:30:00.000Z',
  scopeExpiresAt:'2026-10-15T01:30:00.000Z',privateExpiresAt:'2026-10-15T01:20:00.000Z',expiresAt:'2026-10-15T01:20:00.000Z'};
 const s=await scenario({now:()=>Date.parse(current),observedAt:current,window}),result=await s.run();
 assert.equal(result.actualOrdinaryAttempts,24);assert.equal(result.totalWorkflowRequestBound,162);
 for(const body of s.registrations){assert.equal(body.p_payload.prepared_at,current);assert.equal(body.p_client_timestamp,current);}
 assert.deepEqual(s.registrations.map(body=>body.p_command_id),EXPORTS_COMMANDS.map(row=>row.commandId));
 assert.deepEqual(s.documents.pipeline.rows,EXPORTS_ROWS);
});
