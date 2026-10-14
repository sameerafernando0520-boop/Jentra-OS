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
import {EXPORTS_PROFILE,EXPORTS_DECISION,EXPORTS_PROFILE_PATHS,EXPORTS_PRESERVED_BINDINGS,EXPORTS_SOURCE_PATHS,EXPORTS_COMMANDS,
 EXPORTS_FACTS_SQL,EXPORTS_SQL_SHA256,EXPORTS_FACTOR,EXPORTS_PIPELINE,EXPORTS_PIPELINE_BASIS,EXPORTS_ROWS,EXPORTS_RUNTIME_EXPIRY,
 EXPORTS_PLAN,EXPORTS_BUDGET_REVIEW_SHA,createExportsCallGate,exportsCallDescriptors,runExportsContinuation,createExclusiveExportFiles,validateExportsDocument,
 validateExportsSessionPair,validateExportsProfile,validateExportsPreparation,validateExportsFinalReview,validateExportsConsumed,
 writeExportsEvidence} from '../../../../tools/wave5/finance_exports_20261014_r5_a5.mjs';
import {buildExportsPreparation} from '../../../../tools/wave5/prepare_finance_exports_20261014_r5_a5.mjs';

// Every Auth/database/request value below is controlled test data. None of these
// results is a genuine session, live export, database, native or release proof.
const base='docs/verification/wave5/task3-export-source-independent-20261014';
const stamp='2026-10-14T07:00:00.000Z',now=()=>Date.parse(stamp),digest=hashBytes('controlled-evidence'),clone=structuredClone;
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
   let value;if(query===EXPORTS_FACTS_SQL){value=publicState(registrations.length===2,registrations);if(options.changeState)options.changeState(value,registrations.length===2);
    value=[{export_continuation_facts:value}];}
   else if(query===REMAINING_ACTIVITY_SQL)value=[{observation:publicState().observation}];
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
   expiresAt:'2026-10-14T09:00:00.000Z',...overrides})};
}

test('actual controlled TLS transport, durable journals and disk bytes complete the exact 24-call export contract',async()=>{
 const s=await scenario(),result=await s.run();assert.equal(result.actualOrdinaryAttempts,24);assert.equal(result.totalWorkflowRequestBound,156);
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
 assert.equal(failure.exportStop.totalWorkflowRequestBound,132+ordinal+reserved);assert.equal(s.closed(),true);
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
 const gate=createExportsCallGate({now}),slots=exportsCallDescriptors();let releases,dispatched=0;
 await assert.rejects(gate.dispatch(slots[1],()=>{dispatched++;}));assert.equal(dispatched,0);
 await assert.rejects(gate.dispatch({...slots[0],query:'SELECT 1'},()=>{dispatched++;}));assert.equal(dispatched,0);
 const pending=gate.dispatch(slots[0],()=>new Promise(resolve=>{releases=resolve;}));await assert.rejects(gate.dispatch(slots[0],()=>{dispatched++;}));
 releases(response([]));await pending;assert.equal(gate.snapshot().actualOrdinaryAttempts,1);
});
test('ordinary dispatch reserves 45s in-flight plus 45s resolution at run and scope boundaries',async()=>{
 let clock=now();const started=clock,gate=createExportsCallGate({now:()=>clock,startedAt:started});clock=started+810000;
 await gate.dispatch(exportsCallDescriptors()[0],async()=>response([]));clock++;
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[1],async()=>response([])),/RESERVED/);
 gate.stop();clock=started+855000;await gate.dispatch({kind:'resolution',method:'POST',route:'/database/query',query:receiptResolutionSql(EXPORTS_COMMANDS[0].commandId)},
  async()=>response([]),{resolutionCommand:EXPORTS_COMMANDS[0].commandId});
 await assert.rejects(gate.dispatch({kind:'resolution',method:'POST',route:'/database/query',query:receiptResolutionSql(EXPORTS_COMMANDS[0].commandId)},async()=>response([]),
  {resolutionCommand:EXPORTS_COMMANDS[0].commandId}));
 const expiresAt=new Date(started+90000).toISOString(),scopeGate=createExportsCallGate({now:()=>started+1,startedAt:started,expiresAt});
 await assert.rejects(scopeGate.dispatch(exportsCallDescriptors()[0],async()=>response([])),/RESERVED/);
});
test('the 25th ordinary call and any unknown resolution identity are rejected without dispatch',async()=>{
 const gate=createExportsCallGate({now});for(const slot of exportsCallDescriptors()){
  const request=slot.kind==='session-row'?{...slot,query:bindUuidSessionQuery(writerId,FINANCE_ACTOR)}:slot;await gate.dispatch(request,async()=>response([]));}
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[0],async()=>assert.fail('extra dispatch')));assert.equal(gate.snapshot().totalWorkflowRequestBound,156);
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
 await assert.rejects(s.run({startedAt:now(),expiresAt:new Date(boundary==='authority'?end:now()+7200000).toISOString()}),error=>{
  assert.equal(error.exportStop.actualOrdinaryAttempts,17);assert.equal(error.exportStop.actualReadOnlyResolutionAttempts,0);
  assert.equal(error.exportStop.resolution.readOnlyResolutionUnavailable,true);return true;});
 assert.equal(s.calls.length,17);assert.equal(s.registrations.length,1);assert.equal(s.closed(),true);
 assert.equal(s.journal.at(-1).file,'99-stop.json');
});
async function publicPreparationInputs(){
 const snapshot='build/wave5-approved-execution-20261013-r5-a2/',preserved={};
 for(const [name,binding] of Object.entries(EXPORTS_PRESERVED_BINDINGS))preserved[name]=await readJson(snapshot+binding.path);
 const oldPlan=preserved.a3Plan,sourceBindings=[];
 for(const binding of [...oldPlan.sourceBindings,...Object.values(EXPORTS_PRESERVED_BINDINGS)])if(!sourceBindings.some(row=>row.path===binding.path))sourceBindings.push(binding);
 for(const file of EXPORTS_SOURCE_PATHS)sourceBindings.push({path:file,sha256:hashBytes(await fs.readFile(file))});
 const decision=await readJson(EXPORTS_DECISION.path),budgetReview=await readJson(EXPORTS_PROFILE_PATHS.budgetReview);
 // Hypothetical controlled A10 values exist only in this pure test object.
 // This test does not create or claim a real readiness file or refreshed input.
 const controlBindings=Object.fromEntries(Object.entries(EXPORTS_PROFILE_PATHS).map(([name,file])=>[name,{path:file,sha256:digest}]));
 controlBindings.decision=EXPORTS_DECISION;controlBindings.budgetReview.sha256=EXPORTS_BUDGET_REVIEW_SHA;
 const metadata={kind:'wave5-private-owner-input-metadata',projectId:PROJECT,runtimeBundleSha256:BUNDLE,metadataFilename:'metadata-renewed-a10.json',
  containsPlaintextCredential:false,reuseAuthorizationQuestionId:'["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]',
  createdAt:'2026-10-14T06:50:00.000Z',expiresAt:'2026-10-14T08:50:00.000Z',helperSha256:digest,refreshEvidence:controlBindings.refresh};
 const refresh={kind:'actual-private-owner-scope-refresh',projectId:PROJECT,organizationId:ORGANIZATION,actualStatus:'ACTIVE_HEALTHY',readOnlyOwnerApiCalls:1,
  actualVerifiedAt:metadata.createdAt,helperSha256:digest,databaseWrites:0,authWrites:0,settingsChanges:0};
 const accounting={kind:'conservative-finance-continuation-read-accounting',projectId:PROJECT,recordedAfterA3Stop:128,shapeInvestigationCalls:1,
  chargedA8OwnerIdentityReads:1,chargedA9OwnerIdentityReads:1,chargedA10OwnerIdentityReads:1,cumulativeChargedPriorCalls:132,actualA10Refresh:controlBindings.refresh};
 const profile={kind:'source-reviewed-export-execution-profile',projectId:PROJECT,runtimeBundleSha256:BUNDLE,priorConservativeBound:132,ordinaryAttempts:24,
  ordinaryLimit:156,cumulativeLimit:157,resolutionAttempts:1,requiredActualExportUtcDay:'2026-10-14',personalHumanExactSourceSignatureClaimed:false,
  controlBindings,authorizationExpiresAt:metadata.expiresAt,runtimeAuthorityExpiresAt:EXPORTS_RUNTIME_EXPIRY,
  privateAdapterPredecessor:{path:'scripts/wave5/run_private_management_installer_20261013_r5.ps1',sha256:digest}};
 return {profileBinding:{path:EXPORTS_PROFILE,sha256:digest},profile,documents:{decision,budgetReview,metadata,refresh,accounting},oldPlan,preserved,sourceBindings,preparedAt:stamp};
}
test('actual dated source/consumed evidence and conditional budget review build a public-only controlled plan',async()=>{
 const inputs=await publicPreparationInputs();assert.equal(validateExportsConsumed(inputs.preserved).reexecutionAllowed,false);
 const plan=buildExportsPreparation(inputs);assert.equal(plan.priorConservativeBound,132);assert.equal(plan.cumulativeLimit,157);
 assert.equal(plan.networkCallsDuringPreparation,0);assert.equal(plan.liveExecutionAuthorizedByPreparation,false);assert.equal(plan.publicBindings.length,6);
 assert.equal(plan.originalConcreteCap,150);assert.equal(plan.originalFixtureUtcDay,'2026-10-13');assert.equal(inputs.oldPlan.maximumTotalWorkflowRequestAttempts,150);
});
test('expired A9, another day, repeated owner refresh or a silently enlarged cap cannot build a plan',async()=>{
 const inputs=await publicPreparationInputs();
 for(const change of [x=>x.profile.cumulativeLimit=158,x=>x.profile.priorConservativeBound=131,
  x=>x.profile.controlBindings.metadata.path='docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json',
  x=>x.documents.metadata.expiresAt='2026-10-14T05:53:48.705Z',x=>x.preparedAt='2026-10-15T00:01:00.000Z',
  x=>x.documents.refresh.readOnlyOwnerApiCalls=2,x=>x.documents.accounting.chargedA10OwnerIdentityReads=2]){
  const value=clone(inputs);change(value);assert.throws(()=>buildExportsPreparation(value));}
});
test('changed old source hashes or omitted consumed intents are rejected by public plan construction',async()=>{
 const inputs=await publicPreparationInputs(),tampered=clone(inputs);tampered.sourceBindings=tampered.sourceBindings.map(row=>({...row}));
 tampered.sourceBindings[0].sha256=digest;
 assert.throws(()=>buildExportsPreparation(tampered));const missing=clone(inputs);missing.sourceBindings=missing.sourceBindings.filter(row=>row.path!==EXPORTS_PRESERVED_BINDINGS.a3Once.path);
 assert.throws(()=>buildExportsPreparation(missing));
});
test('extra and duplicate public file bindings fail before the profile/source verifier may read them',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs());
 for(const binding of [plan.profileBinding,{path:'private/unreviewed.env',sha256:digest}]){
  const altered=clone(plan);altered.publicBindings.push(binding);assert.throws(()=>validateExportsPreparation(altered));}
});
test('exact independent final review binds the plan, profile, current owner proofs and adapter; prose approval has no effect',async()=>{
 const plan=buildExportsPreparation(await publicPreparationInputs()),review={kind:'independent-export-only-final-operation-review',technicalDecision:'approve',
  executionPermitted:true,projectId:PROJECT,runtimeBundleSha256:BUNDLE,generatedPlan:{path:EXPORTS_PLAN,sha256:digest},sourceBindings:plan.sourceBindings,
  executionProfileBinding:plan.profileBinding,ownerMetadataBinding:plan.controlBindings.metadata,ownerRefreshBinding:plan.controlBindings.refresh,
  sourceOnlyDecisionBinding:EXPORTS_DECISION,independentBudgetReviewBinding:plan.controlBindings.budgetReview,
  privateAdapter:{beforeSha256:plan.privateAdapterPredecessor.sha256,afterSha256:digest},priorConservativeBound:132,ordinaryLimit:156,cumulativeLimit:157,
  ordinaryAttempts:24,resolutionAttempts:1,permittedOriginalExportCommands:EXPORTS_COMMANDS,requiredActualExportUtcDay:'2026-10-14',
  authorizationExpiresAt:plan.authorizationExpiresAt,personalHumanExactSourceSignatureClaimed:false};
 assert.equal(validateExportsFinalReview(review,{plan,planSha256:digest},now()).executionPermitted,true);
 for(const change of [r=>r.executionPermitted=false,r=>r.generatedPlan.sha256=hashBytes('another plan'),r=>r.cumulativeLimit=156,
  r=>r.ownerMetadataBinding={path:EXPORTS_PROFILE_PATHS.metadata,sha256:hashBytes('wrong owner scope')},r=>r.sourceBindings=r.sourceBindings.slice(1),
  r=>r.technicalDecision='approve this source generally']){
  const altered=clone(review);change(altered);assert.throws(()=>validateExportsFinalReview(altered,{plan,planSha256:digest},now()));}
 assert.throws(()=>validateExportsFinalReview(review,{plan,planSha256:digest},Date.parse(plan.authorizationExpiresAt)));
});

// This is an append-only controlled-test fragment for the preserved author
// suite. The review runner redirects only that suite's output base to this
// independent directory before appending these cases. No live ports are used.

test('peer: an already cancelled run saves its stop, dispatches nothing, and closes', async () => {
 const controller = new AbortController(); controller.abort();
 const s = await scenario({abortController: controller});
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'EXPORT_EXECUTION_ABORTED');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 0);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0);
  return true;
 });
 assert.equal(s.calls.length, 0); assert.equal(s.closed(), true);
 const saved = await readJson(path.join(s.directory, '99-stop.json'));
 assert.equal(saved.completed.length, 0); assert.equal(saved.lastOriginalCommand, null);
});

test('peer: cancellation after CSV persistence prevents the private intent and registration', async () => {
 const controller = new AbortController(), s = await scenario({abortController: controller});
 const save = s.ports.writeFile;
 s.ports.writeFile = async (...args) => { const receipt = await save(...args); controller.abort(); return receipt; };
 await assert.rejects(s.run());
 assert.equal(s.calls.length, 15); assert.equal(s.registrations.length, 0);
 assert.equal(s.journal.some(row => row.private), false); assert.equal(s.closed(), true);
 const saved = await readJson(path.join(s.directory, '99-stop.json'));
 assert.equal(saved.actualReadOnlyResolutionAttempts, 0); assert.equal(saved.lastOriginalCommand, null);
});

test('peer: a stale pre-registration server clock is saved before rejection and never resolved as a sent command', async () => {
 const s = await scenario(), read = s.ports.management;
 s.ports.management = async query => {
  const value = await read(query);
  if (query === REMAINING_ACTIVITY_SQL) { value.value[0].observation.observedAt = '2026-10-14T06:59:14.999Z'; return response(value.value); }
  return value;
 };
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'FRESH_EXPORT_SERVER_CLOCK_REQUIRED');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 16);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0);
  assert.equal(error.exportStop.lastOriginalCommand.writeAttempted, false);
  return true;
 });
 assert.equal(s.registrations.length, 0); assert.equal(s.closed(), true);
 const evidence = s.journal.find(row => row.file?.startsWith('quiescence-'));
 assert.equal(evidence.persistedBeforeValidation, true);
 assert.equal(evidence.value.rows[0].observation.observedAt, '2026-10-14T06:59:14.999Z');
});

test('peer: failed stop persistence is explicitly unavailable and still closes', async () => {
 const s = await scenario({failOrdinal: 1, failPersist: file => file === '99-stop.json'});
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'EXPORT_STOP_EVIDENCE_UNAVAILABLE');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 1); return true;
 });
 assert.equal(s.calls.length, 1); assert.equal(s.closed(), true);
 await assert.rejects(fs.readFile(path.join(s.directory, '99-stop.json')), {code: 'ENOENT'});
});

test('peer: a constructed MFA claim or foreign factor stops before any preview', async () => {
 for (const changeProof of [proof => { proof.constructedAalClaims = true; }, proof => { proof.factorId = writerId; }]) {
  const s = await scenario({changeProof}); await assert.rejects(s.run(), /GENUINE_INDEPENDENT_EXPORT_MFA_SESSIONS_REQUIRED/);
  assert.equal(s.calls.length, 14); assert.equal(s.registrations.length, 0); assert.equal(s.closed(), true);
 }
});

test('peer: tampered statement disk bytes preserve the confirmed pipeline and prevent the second registration', async () => {
 const s = await scenario(), read = s.ports.readFile;
 s.ports.readFile = async file => { const bytes = await read(file); return file.includes('statement') ? Buffer.concat([bytes, Buffer.from('\nchanged')]) : bytes; };
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'ACTUAL_SAVED_EXPORT_BYTES_REQUIRED');
  assert.equal(error.exportStop.actualOrdinaryAttempts, 20);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0);
  assert.equal(error.exportStop.completed.length, 1); return true;
 });
 assert.equal(s.registrations.length, 1); assert.equal(s.registrations[0].p_command_id, EXPORTS_COMMANDS[0].commandId);
 assert.equal(s.closed(), true);
});

test('peer: an extra date mutation fails final reconciliation without replaying either confirmed export', async () => {
 const s = await scenario({changeState: (value, after) => { if (after) value.wholeSource.dateProposals = 4; }});
 await assert.rejects(s.run(), error => {
  assert.equal(error.publicCode, 'EXACT_UNCHANGED_EXPORT_FINANCE_COUNTS_REQUIRED');
  assert.equal(error.exportStop.completed.length, 2); assert.equal(error.exportStop.actualOrdinaryAttempts, 24);
  assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0); return true;
 });
 assert.equal(s.registrations.length, 2); assert.equal(new Set(s.registrations.map(row => row.p_command_id)).size, 2);
 assert.equal(s.closed(), true);
});

test('peer: the original authority expiry reserves both request windows even with a later run deadline', async () => {
 const expiry = Date.parse(EXPORTS_RUNTIME_EXPIRY), clock = expiry - 89999;
 const gate = createExportsCallGate({now: () => clock, startedAt: clock, expiresAt: EXPORTS_RUNTIME_EXPIRY});
 let sends = 0;
 await assert.rejects(gate.dispatch(exportsCallDescriptors()[0], async () => { sends++; }), /EXPORT_INFLIGHT_AND_RESOLUTION_TIME_RESERVED_REQUIRED/);
 assert.equal(sends, 0); assert.equal(gate.snapshot().actualOrdinaryAttempts, 0);
});

for (const [boundary, elapsed] of [['run', 900000], ['owner scope', 90000]]) {
 test(`peer: a request failure at the exact ${boundary} deadline still saves a local stop without late requests`, async () => {
  let clock = now(); const originalStart = clock, s = await scenario(), read = s.ports.management;
  s.ports.management = async query => {
   await read(query); clock = originalStart + elapsed;
   const error = Error('controlled deadline-bound failure'); error.publicCode = 'CONTROLLED_AT_EXECUTION_END'; throw error;
  };
  const options = {now: () => clock, startedAt: originalStart,
   ...(boundary === 'owner scope' ? {expiresAt: new Date(originalStart + elapsed).toISOString()} : {})};
  await assert.rejects(s.run(options), error => {
   assert.equal(error.publicCode, 'CONTROLLED_AT_EXECUTION_END');
   assert.equal(error.exportStop.actualOrdinaryAttempts, 1); assert.equal(error.exportStop.actualReadOnlyResolutionAttempts, 0); return true;
  });
  assert.equal(s.calls.length, 1); assert.equal(s.closed(), true);
  const stop = await readJson(path.join(s.directory, '99-stop.json'));
  assert.equal(stop.failureCode, 'CONTROLLED_AT_EXECUTION_END'); assert.equal(stop.lastOriginalCommand, null);
 });
}
