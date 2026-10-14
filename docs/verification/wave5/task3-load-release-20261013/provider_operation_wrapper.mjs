import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { GuardError, requireGuard, isSha, hashBytes, hashJson, reviewedExecutionContext } from '../../../../tools/wave5/runtime_contract.mjs';
import { createSupabaseRuntimeProvider } from '../../../../tools/wave5/supabase_runtime_provider.mjs';
import { createProviderPgClientFactory } from './provider_pg_factory.mjs';

const base='docs/verification/wave5/task3-load-release-20261013';
const localDirectory=path.dirname(fileURLToPath(import.meta.url)),workspace=path.resolve(localDirectory,'../../../..');
const bindingKeys=['routerSha256','readOnlyDriverSha256','fixtureDriverSha256','dependencyManifestSha256'];
const requiredSources=['postgres_transport.mjs','fixture_writer.mjs','provider_pg_factory.mjs','provider_operation_wrapper.mjs','external_observer.mjs'];
const publicSources=['runtime_contract.mjs','runtime_fixture_spec.mjs','supabase_runtime_provider.mjs','supabase_read_store.mjs',
  'supabase_membership_fixture.mjs','preparation_journal.mjs','supabase_http_transport.mjs'].map(name=>`tools/wave5/${name}`);
function reviewedBindings(actual,reviewed){
  const exact=value=>value&&Object.keys(value).length===bindingKeys.length&&bindingKeys.every(key=>isSha(value[key]));
  requireGuard(exact(actual)&&exact(reviewed)&&hashJson(actual)===hashJson(reviewed),'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
}

// Public source/package bytes only. Restrict every path before reading it.
// The caller's claimed digests alone do not replace actual file verification.
export async function verifyProviderManifestFiles(manifest,readBytes){
  requireGuard(manifest?.kind==='exact-installed-pg-helper-dependency-file-manifest'
    &&manifest.pinnedPgVersion==='8.23.1'&&typeof readBytes==='function'
    &&Array.isArray(manifest.files)&&manifest.files.length>0&&Array.isArray(manifest.providerSourceFiles)
    &&Array.isArray(manifest.publicSourceFiles)&&manifest.publicSourceFiles.length===publicSources.length,
    'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
  const entries=[manifest.package,manifest.lockfile,...manifest.files,...manifest.providerSourceFiles,...manifest.publicSourceFiles];
  const allowed=file=>typeof file==='string'&&!file.includes('\\')&&!file.includes('..')
    &&(file===`${base}/package.json`||file===`${base}/package-lock.json`
      ||file.startsWith(`${base}/node_modules/`)
      ||requiredSources.some(name=>file===`${base}/${name}`)
      ||new RegExp(`^${base}/fixture_writer[^/]*\\.mjs$`).test(file)||publicSources.includes(file));
  requireGuard(entries.every(entry=>entry&&allowed(entry.path)&&isSha(entry.sha256)
    &&Number.isSafeInteger(entry.bytes)&&entry.bytes>=0)
    &&new Set(entries.map(entry=>entry.path)).size===entries.length
    &&requiredSources.every(name=>manifest.providerSourceFiles.some(entry=>entry.path===`${base}/${name}`))
    &&publicSources.every(file=>manifest.publicSourceFiles.some(entry=>entry.path===file)),
    'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
  for(const entry of entries){
    const bytes=await readBytes(entry.path);
    requireGuard(bytes.length===entry.bytes&&hashBytes(bytes)===entry.sha256,'PRIVATE_PROVIDER_SOURCE_DRIFT');
  }
  return Object.freeze({verified:true,sourceFileCount:manifest.providerSourceFiles.length,
    publicSourceFileCount:manifest.publicSourceFiles.length,dependencyFileCount:manifest.files.length});
}

async function verifyActualSourceFiles(actual,reviewed,manifestName='dependency-source-manifest.json'){
  reviewedBindings(actual,reviewed);
  requireGuard(typeof manifestName==='string'&&/^[A-Za-z0-9-]+\.json$/.test(manifestName),'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
  let bytes,manifest;
  try{bytes=await fs.readFile(path.join(localDirectory,manifestName));manifest=JSON.parse(bytes);}
  catch{throw new GuardError('REVIEWED_PRIVATE_PROVIDER_REQUIRED');}
  requireGuard(hashBytes(bytes)===actual.dependencyManifestSha256,'PRIVATE_PROVIDER_SOURCE_DRIFT');
  requireGuard(Array.isArray(manifest?.providerSourceFiles),'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
  const named=Object.fromEntries(manifest.providerSourceFiles.map(item=>[path.basename(item.path),item.sha256]));
  requireGuard(named['provider_pg_factory.mjs']===actual.routerSha256&&named['postgres_transport.mjs']===actual.readOnlyDriverSha256
    &&named['fixture_writer.mjs']===actual.fixtureDriverSha256,'PRIVATE_PROVIDER_SOURCE_DRIFT');
  await verifyProviderManifestFiles(manifest,async file=>{
    const resolved=path.resolve(workspace,file),relative=path.relative(workspace,resolved);
    requireGuard(relative!==''&&!relative.startsWith(`..${path.sep}`)&&!path.isAbsolute(relative),'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
    const actualPath=await fs.realpath(resolved);
    requireGuard(actualPath===resolved,'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
    return fs.readFile(resolved);
  });
}

function invitationObservation(record,sourceRecordSha256){
  const headers=Object.fromEntries(['kind','projectId','runtimeBundleSha256','planBodySha256','sourceSha256','sequence',
    'recordId','observedAt','caseId','scopeKey','action','phase','operationId'].map(key=>[key,record[key]]));
  const details=record.details??{};
  let safeDetails;
  if(record.phase==='intent')safeDetails={actorId:details.actorId,route:details.route,parameters:
    Object.fromEntries(['p_tenant_id','p_email','p_role_id','p_legal_entity_id','p_branch_id','p_expires_in_hours']
      .map(key=>[key,details.parameters?.[key]]))};
  else if(record.phase==='confirmed')safeDetails={result:{ok:details.result?.ok,
    value:{invitation_id:details.result?.value?.invitation_id},transportEvidenceSha256:details.result?.transportEvidenceSha256}};
  else safeDetails={failureCode:typeof details.failureCode==='string'&&/^[A-Z0-9_]{1,96}$/.test(details.failureCode)
    ?details.failureCode:'PROVIDER_FAILURE'};
  return Object.freeze({...headers,sourceRecordSha256,details:safeDetails});
}

// Raw recovery tokens go only to the original private durable sink. The writer
// receives a bounded token-free projection after the raw record's hash matches.
export function createAcknowledgedInvitationSink({appendPreparationEvidence,fixtureDriver}){
  requireGuard(typeof appendPreparationEvidence==='function'&&typeof fixtureDriver?.observeInvitationJournalRecord==='function',
    'PRIVATE_PROVIDER_INCOMPLETE');
  return async record=>{
    const receipt=await appendPreparationEvidence(record);
    requireGuard(receipt?.durable===true&&receipt.appendOnly===true&&receipt.recordSha256===hashJson(record)
      &&isSha(receipt.storageEvidenceSha256),'EVIDENCE_WRITE_FAILED');
    if(record.action==='rpc-create-invitation'){
      const observation=invitationObservation(record,receipt.recordSha256);
      await fixtureDriver.observeInvitationJournalRecord(observation,Object.freeze({durable:true,appendOnly:true,
        recordSha256:receipt.recordSha256,storageEvidenceSha256:receipt.storageEvidenceSha256,
        originalRecordHashVerified:true,observationSha256:hashJson(observation)}));
    }
    return receipt;
  };
}

export function createProviderOperationWrapper({provider,reviewedCases,readDriver,fixtureDriver}){
  requireGuard(provider&&Array.isArray(reviewedCases)&&typeof provider.prepareRace==='function'
    &&typeof provider.restoreRace==='function'&&typeof provider.close==='function'&&typeof readDriver?.close==='function'
    &&typeof fixtureDriver?.close==='function'&&typeof fixtureDriver.runWithSignal==='function','PRIVATE_PROVIDER_INCOMPLETE');
  const cases=new Map(reviewedCases.map(race=>[race.caseId,hashJson(race)]));
  const wrapped=Object.fromEntries(Object.entries(provider).map(([key,value])=>[key,
    typeof value==='function'?(...args)=>Reflect.apply(value,provider,args):value]));
  for(const [method,action] of [['prepareRace','prepare'],['restoreRace','restore']]){
    wrapped[method]=args=>{
      if(!['seats','admissions'].includes(args?.race?.kind))return provider[method](args);
      requireGuard(args.race.scopeKey==='load-001'&&cases.get(args.race.caseId)===hashJson(args.race),'REVIEWED_CASE_BINDING_REQUIRED');
      return fixtureDriver.runWithSignal(args.signal,()=>provider[method](args),{caseId:args.race.caseId,action});
    };
  }
  let closing;
  wrapped.close=()=>closing??=(async()=>{
    const results=await Promise.allSettled([()=>provider.close(),()=>readDriver.close(),()=>fixtureDriver.close()]
      .map(operation=>Promise.resolve().then(operation)));
    if(results.some(result=>result.status==='rejected'))throw new GuardError('PROVIDER_FAILURE');
  })();
  return Object.freeze(wrapped);
}

// Canonical reviewed context and actual source verification both precede the
// first private configuration callback. No driver opens a connection here.
export async function createReviewedSupabaseProvider(input){
  const context=reviewedExecutionContext(input?.executionContext);
  const {actualSourceBindings,independentlyReviewedSourceBindings,sourceManifestName}=input;
  await verifyActualSourceFiles(actualSourceBindings,independentlyReviewedSourceBindings,sourceManifestName);
  const {readDriver,fixtureDriver}=input;
  const PgClient=createProviderPgClientFactory({readOnlyPgClient:readDriver?.PgClient,fixturePgClient:fixtureDriver?.PgClient,
    actualSourceBindings,independentlyReviewedSourceBindings});
  requireGuard(typeof input.privateConfigProvider==='function'&&typeof fixtureDriver.runWithSignal==='function'
    &&typeof fixtureDriver.close==='function'&&typeof readDriver.close==='function',
    'PRIVATE_PROVIDER_INCOMPLETE');
  try{
    const config=await input.privateConfigProvider();
    requireGuard(config&&typeof config==='object','PRIVATE_PROVIDER_INCOMPLETE');
    const privateConfig={...config,PgClient,appendPreparationEvidence:createAcknowledgedInvitationSink({
      appendPreparationEvidence:config.appendPreparationEvidence,fixtureDriver})};
    const provider=createSupabaseRuntimeProvider({executionContext:context,privateConfig,
      requestFactory:input.requestFactory,agentFactory:input.agentFactory});
    return createProviderOperationWrapper({provider,reviewedCases:context.plan.cases,readDriver,fixtureDriver});
  }catch(error){
    await Promise.allSettled([()=>readDriver.close(),()=>fixtureDriver.close()].map(operation=>Promise.resolve().then(operation)));
    throw error instanceof GuardError?error:new GuardError('PROVIDER_FAILURE');
  }
}
