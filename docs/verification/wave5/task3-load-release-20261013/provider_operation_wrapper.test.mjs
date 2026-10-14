import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { hashBytes,hashJson,freshId } from '../../../../tools/wave5/runtime_contract.mjs';
import { createAcknowledgedInvitationSink,createProviderOperationWrapper,verifyProviderManifestFiles,
  createReviewedSupabaseProvider } from './provider_operation_wrapper.mjs';
import { createBoundedPgDriver } from './postgres_transport.mjs';
import { createBoundedMembershipFixturePgDriver } from './fixture_writer.mjs';
import { controlledContext,config,review,deferred,setup } from './fixture_writer_test_support.mjs';
import { createMembershipFixture } from '../../../../tools/wave5/supabase_membership_fixture.mjs';
import { createPreparationJournal } from '../../../../tools/wave5/preparation_journal.mjs';
import { createProviderPgClientFactory } from './provider_pg_factory.mjs';

// Controlled local integration only: no Auth token, server, private credential,
// real TLS socket, live SQL, SDK or load outcome is manufactured by this suite.
const base='docs/verification/wave5/task3-load-release-20261013';
const directory=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(directory,'../../../..');
const publicSources=['runtime_contract.mjs','runtime_fixture_spec.mjs','supabase_runtime_provider.mjs','supabase_read_store.mjs',
  'supabase_membership_fixture.mjs','preparation_journal.mjs','supabase_http_transport.mjs'].map(name=>`tools/wave5/${name}`);
const cases=['seats','admissions','duplicates'].map(kind=>({kind,caseId:freshId(),scopeKey:kind==='duplicates'?'runtime':'load-001'}));
function operationFixture(){
  const calls=[],result=Object.freeze({controlledResult:true});
  const provider={prepareRace:args=>{calls.push(['prepare',args]);return result;},restoreRace:args=>{calls.push(['restore',args]);return result;},
    other(...args){calls.push(['other',this,args]);return result;},close:()=>{calls.push(['public-close']);}};
  const readDriver={close:()=>calls.push(['read-close'])};
  const fixtureDriver={runWithSignal:(signal,callback,metadata)=>{calls.push(['signal',signal,metadata]);return callback();},
    close:()=>calls.push(['fixture-close'])};
  return {calls,result,provider,readDriver,fixtureDriver,wrapper:createProviderOperationWrapper({provider,reviewedCases:cases,readDriver,fixtureDriver})};
}
test('exact seats and admissions prepare/restore use the original operation signal and reviewed writer role',()=>{
  for(const race of cases.filter(value=>value.kind!=='duplicates'))for(const [method,action] of [['prepareRace','prepare'],['restoreRace','restore']]){
    const f=operationFixture(),args={race,signal:new AbortController().signal};
    assert.equal(f.wrapper[method](args),f.result);
    assert.deepEqual(f.calls[0],['signal',args.signal,{caseId:race.caseId,action}]);assert.equal(f.calls[1][1],args);
  }
});
test('other races and public methods preserve arguments, return values and receiver',()=>{
  const f=operationFixture(),args={race:cases[2]};
  assert.equal(f.wrapper.prepareRace(args),f.result);assert.deepEqual(f.calls[0],['prepare',args]);
  assert.equal(f.wrapper.other('one',{two:2}),f.result);assert.equal(f.calls[1][1],f.provider);assert.deepEqual(f.calls[1][2],['one',{two:2}]);
});
test('altered case hashes or foreign membership scopes fail before writer context or public operation',()=>{
  for(const race of [{...cases[0],scopeKey:'foreign'},{...cases[0],unexpected:true},{...cases[1],caseId:freshId()}]){
    const f=operationFixture();assert.throws(()=>f.wrapper.prepareRace({race,signal:new AbortController().signal}),{code:'REVIEWED_CASE_BINDING_REQUIRED'});
    assert.equal(f.calls.length,0);
  }
});
test('a failing public close still closes both pools and repeated close shares one completion',async()=>{
  const f=operationFixture();f.provider.close=()=>{f.calls.push(['public-close']);throw new Error('CONTROLLED_PRIVATE_FAILURE');};
  const first=f.wrapper.close(),second=f.wrapper.close();assert.equal(first,second);
  await assert.rejects(first,{code:'PROVIDER_FAILURE'});
  assert.deepEqual(f.calls.map(call=>call[0]).sort(),['fixture-close','public-close','read-close']);
});
test('a failing pool close cannot skip closing the other pool or expose its raw error',async()=>{
  const f=operationFixture();f.readDriver.close=()=>{f.calls.push(['read-close']);throw new Error('CONTROLLED_PRIVATE_FAILURE');};
  await assert.rejects(f.wrapper.close(),error=>error.code==='PROVIDER_FAILURE'&&!error.message.includes('CONTROLLED_PRIVATE'));
  assert.deepEqual(f.calls.map(call=>call[0]).sort(),['fixture-close','public-close','read-close']);
});
const receipt=record=>({durable:true,appendOnly:true,recordSha256:hashJson(record),storageEvidenceSha256:hashJson('controlled-durable-storage')});
const record=phase=>({kind:'wave5-private-preparation-journal-record',projectId:review.projectId,runtimeBundleSha256:review.bundleSha256,
  planBodySha256:hashJson('controlled-plan'),sourceSha256:hashJson('controlled-sink'),sequence:1,recordId:freshId(),
  observedAt:new Date().toISOString(),caseId:cases[0].caseId,scopeKey:'load-001',action:'rpc-create-invitation',phase,operationId:freshId(),
  details:phase==='confirmed'?{result:{ok:true,value:{invitation_id:freshId(),token:'CONTROLLED_RECOVERY_VALUE'},
    transportEvidenceSha256:hashJson('controlled-transport'),unneeded:'CONTROLLED_EXTRA'}}:phase==='intent'?
    {actorId:freshId(),route:'/rest/v1/rpc/create_invitation',parameters:{p_tenant_id:freshId(),p_email:'controlled@jentra.invalid',
      p_role_id:freshId(),p_legal_entity_id:freshId(),p_branch_id:freshId(),p_expires_in_hours:1,unneeded:'CONTROLLED_EXTRA'}}:
    {failureCode:'PROVIDER_FAILURE',result:{value:{token:'CONTROLLED_RECOVERY_VALUE'}}}});
test('invitation adoption follows actual durable acknowledgment and receives no raw recovery or extra fields',async()=>{
  const gate=deferred(),raw=record('confirmed'),seen=[];let originalSeen;
  const sink=createAcknowledgedInvitationSink({appendPreparationEvidence:async value=>{originalSeen=value;await gate.promise;return receipt(value);},
    fixtureDriver:{observeInvitationJournalRecord:(observation,ack)=>seen.push({observation,ack})}});
  const operation=sink(raw);assert.equal(seen.length,0);assert.equal(originalSeen,raw);gate.resolve();
  const result=await operation;assert.equal(result.recordSha256,hashJson(raw));assert.equal(seen.length,1);
  assert.equal(JSON.stringify(seen).includes('CONTROLLED_RECOVERY_VALUE'),false);assert.equal(JSON.stringify(seen).includes('CONTROLLED_EXTRA'),false);
  assert.deepEqual(seen[0].observation.details.result.value,{invitation_id:raw.details.result.value.invitation_id});
  assert.equal(seen[0].ack.recordSha256,hashJson(raw));assert.equal(seen[0].ack.observationSha256,hashJson(seen[0].observation));
  assert.equal(seen[0].ack.originalRecordHashVerified,true);
});
test('invalid or absent durable receipt prevents any invitation adoption',async()=>{
  for(const alter of [()=>null,value=>({...receipt(value),durable:false}),value=>({...receipt(value),appendOnly:false}),
    value=>({...receipt(value),recordSha256:hashJson('wrong')}),value=>({...receipt(value),storageEvidenceSha256:'invalid'})]){
    let adopted=0;const sink=createAcknowledgedInvitationSink({appendPreparationEvidence:async value=>alter(value),
      fixtureDriver:{observeInvitationJournalRecord:()=>adopted++}});
    await assert.rejects(sink(record('confirmed')),{code:'EVIDENCE_WRITE_FAILED'});assert.equal(adopted,0);
  }
});
test('intent and uncertain invitation projection contains only allowed fields and retains original digest',async()=>{
  for(const phase of ['intent','uncertain']){
    const raw=record(phase),seen=[];const sink=createAcknowledgedInvitationSink({appendPreparationEvidence:async value=>receipt(value),
      fixtureDriver:{observeInvitationJournalRecord:value=>seen.push(value)}});await sink(raw);
    assert.equal(seen[0].sourceRecordSha256,hashJson(raw));assert.equal(JSON.stringify(seen).includes('CONTROLLED_EXTRA'),false);
    assert.equal(JSON.stringify(seen).includes('CONTROLLED_RECOVERY_VALUE'),false);
    assert.deepEqual(Object.keys(seen[0].details).sort(),phase==='intent'?['actorId','parameters','route']:['failureCode']);
  }
});
test('non-invitation journal record keeps the original private sink behavior without writer adoption',async()=>{
  const raw={...record('confirmed'),action:'membership-baseline'},expected=receipt(raw);let seen;
  const sink=createAcknowledgedInvitationSink({appendPreparationEvidence:async value=>{seen=value;return expected;},
    fixtureDriver:{observeInvitationJournalRecord:()=>assert.fail('not an invitation')}});
  assert.equal(await sink(raw),expected);assert.equal(seen,raw);
});
function controlledManifest(){
  const bytes=new Map(),entry=file=>{const value=Buffer.from(`CONTROLLED_SOURCE:${file}`);bytes.set(file,value);return{path:file,bytes:value.length,sha256:hashBytes(value)};};
  const manifest={kind:'exact-installed-pg-helper-dependency-file-manifest',pinnedPgVersion:'8.23.1',
    package:entry(`${base}/package.json`),lockfile:entry(`${base}/package-lock.json`),files:[entry(`${base}/node_modules/pg/lib/index.js`)],
    providerSourceFiles:['postgres_transport.mjs','fixture_writer.mjs','provider_pg_factory.mjs','provider_operation_wrapper.mjs','external_observer.mjs'].map(name=>entry(`${base}/${name}`)),
    publicSourceFiles:publicSources.map(entry)};
  return{manifest,bytes};
}
test('all source/dependency bytes must match the reviewed manifest',async()=>{
  const {manifest,bytes}=controlledManifest();let reads=0;
  assert.deepEqual(await verifyProviderManifestFiles(manifest,async file=>{reads++;return bytes.get(file);}),
    {verified:true,sourceFileCount:5,publicSourceFileCount:7,dependencyFileCount:1});assert.equal(reads,15);
  bytes.set(manifest.providerSourceFiles[0].path,Buffer.from('ALTERED'));
  await assert.rejects(verifyProviderManifestFiles(manifest,async file=>bytes.get(file)),{code:'PRIVATE_PROVIDER_SOURCE_DRIFT'});
});
test('unsafe manifest paths, duplicate paths or omitted wrapper cannot trigger private file reads',async()=>{
  for(const alter of [m=>m.files.push({path:'C:/private/database-password.dpapi',bytes:1,sha256:hashJson('x')}),
    m=>m.files.push(m.files[0]),m=>m.providerSourceFiles.pop(),m=>m.publicSourceFiles.pop()]){
    const {manifest}=controlledManifest();alter(manifest);let reads=0;
    await assert.rejects(verifyProviderManifestFiles(manifest,async()=>{reads++;return Buffer.from('x');}),{code:'REVIEWED_PRIVATE_PROVIDER_REQUIRED'});
    assert.equal(reads,0);
  }
});
test('canonical approval/context rejection precedes private configuration and driver getters',async()=>{
  let accesses=0;const input={executionContext:controlledContext()};input.executionContext.review={...input.executionContext.review,bundleSha256:hashJson('wrong')};
  for(const key of ['privateConfigProvider','readDriver','fixtureDriver'])Object.defineProperty(input,key,{get(){accesses++;throw new Error('PRIVATE_GETTER_CALLED');}});
  await assert.rejects(createReviewedSupabaseProvider(input));assert.equal(accesses,0);
});

async function actualManifest(){
  const entry=async file=>{const bytes=await fs.readFile(path.join(root,file));return{path:file,bytes:bytes.length,sha256:hashBytes(bytes)};};
  const files=[];async function walk(relative){for(const item of await fs.readdir(path.join(root,relative),{withFileTypes:true})){
    assert.equal(item.isSymbolicLink(),false);const file=`${relative}/${item.name}`;if(item.isDirectory())await walk(file);else files.push(await entry(file));}}
  await walk(`${base}/node_modules`);
  const manifest={kind:'exact-installed-pg-helper-dependency-file-manifest',pinnedPgVersion:'8.23.1',controlOnly:true,
    package:await entry(`${base}/package.json`),lockfile:await entry(`${base}/package-lock.json`),files,
    providerSourceFiles:await Promise.all(['postgres_transport.mjs','fixture_writer.mjs','provider_pg_factory.mjs','provider_operation_wrapper.mjs','external_observer.mjs'].map(name=>entry(`${base}/${name}`))),
    publicSourceFiles:await Promise.all(publicSources.map(entry))};
  const content=JSON.stringify(manifest,null,2)+'\n',name=`provider-operation-control-source-manifest-${freshId()}.json`;
  await fs.writeFile(path.join(directory,name),content,{flag:'wx'});
  const sources=Object.fromEntries(manifest.providerSourceFiles.map(value=>[path.basename(value.path),value.sha256]));
  return{name,bindings:{routerSha256:sources['provider_pg_factory.mjs'],readOnlyDriverSha256:sources['postgres_transport.mjs'],
    fixtureDriverSha256:sources['fixture_writer.mjs'],dependencyManifestSha256:hashBytes(content)}};
}
function contextAndCalendar(){
  const context=controlledContext(),calendar={horizonStart:'2026-10-01',horizonEnd:'2026-11-01',windowStart:'2026-10-01T00:00:00Z',
    windowEnd:'2026-10-08T00:00:00Z',asOf:'2026-10-08T00:00:00Z',recordedThrough:'2026-10-08T00:00:00Z',clientTimestamp:'2026-10-12T00:00:00Z'};
  context.plan.providerCalendarSha256=hashJson(calendar);context.binding.planSha256=hashJson(context.plan);context.binding.planBodySha256=hashJson(context.plan);
  context.independentReview.planSha256=context.binding.planSha256;context.binding.independentReviewBodySha256=hashJson(context.independentReview);
  context.preparation.planSha256=context.binding.planSha256;context.preparation.independentReview.sha256=hashJson(context.independentReview);
  return{context,calendar};
}
test('actual public runtime provider composes with both real driver classes, protected sink and operation wrapper without I/O',async()=>{
  const {context,calendar}=contextAndCalendar(),authIds=Object.fromEntries(review.accounts.map(actor=>[actor.label,freshId()]));
  let credentials=0,configCallbacks=0,actorCallbacks=0,agents=0;
  const credentialProvider=()=>{credentials++;throw new Error('CONNECTION_NOT_ALLOWED_IN_CONTROLLED_CONSTRUCTION');};
  const readDriver=createBoundedPgDriver({credentialProvider});
  const fixtureDriver=createBoundedMembershipFixturePgDriver({executionContext:context,authIds,credentialProvider});
  const source=await actualManifest();
  const provider=await createReviewedSupabaseProvider({executionContext:context,actualSourceBindings:source.bindings,
    independentlyReviewedSourceBindings:{...source.bindings},sourceManifestName:source.name,readDriver,fixtureDriver,
    privateConfigProvider:async()=>{configCallbacks++;return{projectId:review.projectId,calendar,authIds,
      privateConfigSourceSha256:context.binding.privateProviderSha256,postgresDriverSourceSha256:context.plan.postgresDriverSourceSha256,
      preparationJournalSourceSha256:context.plan.preparationJournalSourceSha256,databaseConfig:config(),anonKey:'CONTROLLED_PUBLIC_KEY',
      privateActors:async()=>{actorCallbacks++;},verifyOnlinePreflight:async()=>({}),observeExternalTransport:async()=>{},
      appendPreparationEvidence:async value=>receipt(value)};},agentFactory:()=>{agents++;throw new Error('NETWORK_NOT_ALLOWED');}});
  assert.equal(configCallbacks,1);assert.equal(credentials,0);assert.equal(agents,0);assert.equal(actorCallbacks,0);
  const signal=new AbortController().signal;
  await assert.rejects(provider.verifyPreflight({signal}),{code:'ONLINE_PREFLIGHT_BINDING_REQUIRED'});
  for(const kind of ['seats','admissions']){
    const race=context.plan.cases.find(value=>value.kind===kind);
    await assert.rejects(provider.prepareRace({race,signal}),{code:'ONLINE_PREFLIGHT_BINDING_REQUIRED'});
    await assert.rejects(provider.restoreRace({race,signal}),{code:'ONLINE_PREFLIGHT_BINDING_REQUIRED'});
  }
  await provider.close();assert.equal(credentials,0);assert.equal(readDriver.metrics().actualConnections,0);
  assert.equal(fixtureDriver.metrics().actualConnections,0);assert.equal(actorCallbacks,0);assert.equal(agents,0);
});
test('changed source review rejects before the private config callback or driver getter',async()=>{
  const {context}=contextAndCalendar(),source=await actualManifest();let accesses=0;
  const input={executionContext:context,actualSourceBindings:source.bindings,
    independentlyReviewedSourceBindings:{...source.bindings,fixtureDriverSha256:hashJson('changed')},sourceManifestName:source.name};
  for(const key of ['privateConfigProvider','readDriver','fixtureDriver'])Object.defineProperty(input,key,{get(){accesses++;throw new Error('PRIVATE_GETTER_CALLED');}});
  await assert.rejects(createReviewedSupabaseProvider(input),{code:'REVIEWED_PRIVATE_PROVIDER_REQUIRED'});assert.equal(accesses,0);
});
test('actual factory failure closes both pools and does not return raw private callback errors',async()=>{
  const {context}=contextAndCalendar(),source=await actualManifest(),closed=[];
  const readDriver={PgClient:class {},close:()=>closed.push('read')};
  const fixtureDriver={PgClient:class {},runWithSignal:()=>{},close:()=>closed.push('fixture')};
  await assert.rejects(createReviewedSupabaseProvider({executionContext:context,actualSourceBindings:source.bindings,
    independentlyReviewedSourceBindings:{...source.bindings},sourceManifestName:source.name,readDriver,fixtureDriver,
    privateConfigProvider:async()=>{throw new Error('CONTROLLED_PRIVATE_CALLBACK_ERROR');}}),
    error=>error.code==='PROVIDER_FAILURE'&&!error.message.includes('CONTROLLED_PRIVATE'));
  assert.deepEqual(closed.sort(),['fixture','read']);
});
test('unchanged actual membership fixture/journal completes exact seats preparation and restoration through router, wrapper and token-free sink',async()=>{
  const f=setup(),records=[],bindings={routerSha256:hashJson('controlled-router'),readOnlyDriverSha256:hashJson('controlled-reader'),
    fixtureDriverSha256:hashJson('controlled-writer'),dependencyManifestSha256:hashJson('controlled-dependencies')};
  const sink=createAcknowledgedInvitationSink({appendPreparationEvidence:async value=>{records.push(value);return receipt(value);},fixtureDriver:f.driver});
  const journal=createPreparationJournal({projectId:review.projectId,runtimeBundleSha256:review.bundleSha256,
    planBodySha256:f.context.binding.planBodySha256,sourceSha256:f.context.plan.preparationJournalSourceSha256,
    cases:[...f.context.plan.cases,...f.context.plan.boundaries],appendPreparationEvidence:sink});
  const readDriver={PgClient:class {constructor(){assert.fail('write operation must select the exact writer role');}},close:async()=>{}};
  const PgClient=createProviderPgClientFactory({readOnlyPgClient:readDriver.PgClient,fixturePgClient:f.driver.PgClient,
    actualSourceBindings:bindings,independentlyReviewedSourceBindings:{...bindings}});
  const fixture=createMembershipFixture({executionContext:f.context,authIds:f.authIds,PgClient,databaseConfig:config(),preparationJournal:journal});
  const returned=[];
  const provider={async prepareRace({race,signal}){
    const prepared=await fixture.prepare({signal,caseId:race.caseId});
    for(const label of ['approver','executor']){
      const actor=review.accounts.find(value=>value.label===label),id=freshId();returned.push(id);
      const result=await journal.perform({caseId:race.caseId,scopeKey:'load-001',action:'rpc-create-invitation',
        intent:{actorId:f.authIds['billing-admin'],route:'/rest/v1/rpc/create_invitation',parameters:{p_tenant_id:f.target.tenantId,
          p_email:actor.email,p_role_id:f.roleId,p_legal_entity_id:f.target.entityId,p_branch_id:f.target.branchId,p_expires_in_hours:1}},
        operation:async()=>{f.state.database.invitations.push({id,tenant_id:f.target.tenantId,email:actor.email,invited_by:f.authIds['billing-admin'],status:'pending'});
          return{ok:true,value:{invitation_id:id,token:'e'.repeat(64)},transportEvidenceSha256:hashJson(['controlled-transport',id])};}});
      fixture.recordReturnedInvitation(result.value.invitation_id);
    }return prepared;
  },restoreRace:({race,signal})=>fixture.restore({signal,caseId:race.caseId}),close:async()=>{}};
  const wrapped=createProviderOperationWrapper({provider,reviewedCases:f.context.plan.cases,readDriver,fixtureDriver:f.driver});
  const race=f.race('seats'),signal=new AbortController().signal;
  assert.equal((await wrapped.prepareRace({race,signal})).committed,true);
  assert.equal(f.state.database.subscription.seats,3);assert.ok(f.state.database.members.every(value=>value.status==='suspended'));
  assert.equal((await wrapped.restoreRace({race,signal})).committed,true);
  assert.equal(f.state.database.subscription.seats,4);assert.ok(f.state.database.members.every(value=>value.status==='active'));
  assert.equal(f.state.database.invitations.filter(value=>returned.includes(value.id)&&value.status==='revoked').length,2);
  assert.ok(f.state.database.members.every(value=>BigInt(value.version)>1n));assert.equal(f.state.commits,2);
  assert.ok(records.some(value=>value.action==='rpc-create-invitation'&&value.details?.result?.value?.token==='e'.repeat(64)));
  await wrapped.close();assert.equal(f.state.active,0);assert.equal(f.state.poolEnds,1);
});
