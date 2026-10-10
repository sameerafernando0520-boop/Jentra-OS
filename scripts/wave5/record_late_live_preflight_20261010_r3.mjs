// Metadata only: compare actual saved connector results and create a new audit.
import {readFile,writeFile,lstat,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual as eq} from 'node:util';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const self='scripts/wave5/record_late_live_preflight_20261010_r3.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
const must=(test,message)=>{if(!test)throw Error(message);};
must(process.argv.length===2,'NO_ARGUMENTS_ALLOWED');
const bindings=new Map();
async function bind(file,expected){
  must(typeof file==='string'&&!path.isAbsolute(file),'RELATIVE_INPUT_REQUIRED');
  const target=path.resolve(root,file),relative=path.relative(root,target);
  must(relative&&!relative.startsWith('..')&&!path.isAbsolute(relative),'INPUT_OUTSIDE_WORKSPACE');
  const stat=await lstat(target),resolved=await realpath(target),resolvedRelative=path.relative(root,resolved);
  must(stat.isFile()&&!stat.isSymbolicLink()&&resolvedRelative&&!resolvedRelative.startsWith('..')&&!path.isAbsolute(resolvedRelative),'REGULAR_WORKSPACE_INPUT_REQUIRED');
  const bytes=await readFile(target),hash=sha(bytes);
  must(!expected||hash===expected,'EXACT_INPUT_HASH_CHANGED:'+file);
  must(!bindings.has(file)||bindings.get(file).sha256===hash,'BOUND_INPUT_CHANGED:'+file);
  bindings.set(file,{path:file,sha256:hash,bytes:bytes.length});return bytes;
}
const parse=b=>JSON.parse(b.toString('utf8').replace(/^\uFEFF/,''));
async function json(file,expected){return parse(await bind(file,expected));}
function decode(value){
  if(typeof value==='string')return decode(JSON.parse(value));
  if(value.rawConnectorResult)return decode(value.rawConnectorResult);
  must(value.isError!==true,'CONNECTOR_READ_ERROR');
  if(Array.isArray(value.content)){
    const texts=value.content.filter(c=>c.type==='text');must(texts.length===1,'SINGLE_CONNECTOR_TEXT_REQUIRED');return decode(texts[0].text);
  }
  if(typeof value.result==='string'){
    const block=value.result.match(/\n<untrusted-data-([a-f0-9-]+)>\n([\s\S]*?)\n<\/untrusted-data-\1>/);
    must(block,'SINGLE_DELIMITED_DATA_BLOCK_REQUIRED');return JSON.parse(block[2]);
  }
  return value;
}
const paths={priorRaw:base+'complete-live-preflight-20261010-r3-raw.json',priorSummary:base+'complete-live-preflight-20261010-r3-summary.json',
  priorIndex:base+'complete-live-preflight-20261010-r3-index.json',priorEdge:base+'complete-live-preflight-20261010-r3-edge-list.json',
  raw:base+'complete-live-preflight-20261010-r3-late-raw.json',ledger:base+'complete-live-preflight-20261010-r3-late-ledger.json',
  edge:base+'complete-live-preflight-20261010-r3-late-edge-list.json',context:base+'complete-live-preflight-20261010-r3-late-read-context.json',
  installation:base+'installation-result-20261008.json',query:base+'complete-live-preflight-20261010-r2.sql',
  summary:base+'complete-live-preflight-20261010-r3-late-summary.json',index:base+'complete-live-preflight-20261010-r3-late-index.json'};
const [priorWrapper,priorSummary,priorIndex,priorEdgeWrapper,raw,ledgerWrapper,edgeWrapper,context,installation]=await Promise.all([
  json(paths.priorRaw,'928a3650e416c53e4e105b5bc949cae36f46bc7d8d7249ce0cadb4a1729d09fd'),
  json(paths.priorSummary,'3671734f3f69b04aa412449ec5a1b36d6960a8e6f970f65e0b46dfcd19507788'),json(paths.priorIndex),json(paths.priorEdge),
  json(paths.raw,'3aff3b965f4382ddb25282a78aa287afcb20b83b709b1efea3c9d3af54f56e73'),
  json(paths.ledger,'7be1b5e55f5362590b30b2f1c294592eb6570db8235e1c32bccc93a53fab3228'),
  json(paths.edge,'7d6e5e79f4bfbc40af59f46e4834604485d109a76d7d3cc0ed23077bba5877fa'),
  json(paths.context,'01d5ecd734b569833b5dab8ae89eb6caf9d9ee8525d2027692e15e744e3ab532'),json(paths.installation)]);
await bind(paths.query,'cf886dbb2fac359b530626b50d99312c14b5398a7d620b22100852154594e250');await bind(self);
const priorRows=decode(priorWrapper),lateRows=decode(raw);
must(priorRows.length===1&&lateRows.length===1,'ONE_SQL_RESULT_REQUIRED');const old=priorRows[0],current=lateRows[0];
must(eq(Object.keys(old).sort(),Object.keys(current).sort())&&Object.keys(current).length===40,'EXACT40_METADATA_FIELDS_REQUIRED');
const changedFields=Object.keys(current).filter(k=>!eq(old[k],current[k]));
must(eq(changedFields,['observed_at']),'UNEXPECTED_LIVE_METADATA_DRIFT:'+changedFields.join(','));
must(current.migration_count===43&&current.api_functions===107&&current.functions.length===120,'LIVE_BASELINE_CHANGED');
must(current.wave5_tables.length===15&&current.wave5_tables.every(t=>t.rlsEnabled===true&&t.rlsForced===true),'FORCED_RLS_BASELINE_CHANGED');
must(current.role_permissions===87&&current.role_assignments===1&&current.entitlements===28&&current.memberships===1,'ACCESS_COUNTS_CHANGED');
must(current.proposed_runtime_accounts===0&&current.edge_authorities===null&&current.cron_jobs===null,'RUNTIME_RESOURCES_APPEARED');
must(context.projectId==='xpdoufauvrbdmxgngetv'&&context.readOnly===true&&context.observedAt===current.observed_at&&
  eq(context.query,{path:paths.query,sha256:bindings.get(paths.query).sha256}),'READ_CONTEXT_CHANGED');
must(priorSummary.projectId===context.projectId&&priorIndex.projectId===context.projectId&&priorSummary.observedAt===old.observed_at&&
  priorIndex.summary.sha256===bindings.get(paths.priorSummary).sha256,'PRIOR_INDEX_BINDING_CHANGED');
const ledger=decode(ledgerWrapper).migrations,edge=decode(edgeWrapper).functions,priorEdge=decode(priorEdgeWrapper).functions;
must(Array.isArray(ledger)&&ledger.length===43&&new Set(ledger.map(m=>m.version)).size===43,'ACTUAL43_LEDGER_REQUIRED');
must(installation.targetProjectId===context.projectId&&installation.approvedMigrationsInstalled===6&&installation.migrationsInOrder.length===6&&
  installation.installationComplete===true,'ORIGINAL_SIX_INSTALLATION_RECORD_CHANGED');
const preservedSix=installation.migrationsInOrder.map(m=>{const hits=ledger.filter(row=>row.name===m.ledgerEntry.name&&row.version===m.ledgerEntry.version);
  must(hits.length===1,'INSTALLED_SIX_LEDGER_ENTRY_CHANGED:'+m.name);return {sourcePath:m.path,ledgerEntry:m.ledgerEntry,currentMatches:1,reinstalled:false};});
must(edge.length===2&&eq(edge,priorEdge),'EDGE_INVENTORY_CHANGED');
must(new Set(edge.map(e=>e.slug)).size===2&&edge.every(e=>e.status==='ACTIVE'&&e.version===1),'EXACT_PEOPLE_EDGE_BASELINE_REQUIRED');
const summary={kind:'read_only_late_live_preflight_comparison',recordedAt:new Date().toISOString(),projectId:context.projectId,observedAt:current.observed_at,
  priorObservedAt:old.observed_at,comparedFields:40,onlyChangedFields:changedFields,migrationCount:43,apiFunctions:107,checkedProviders:120,
  unchangedProviders:120,changedProviders:[],wave5ForcedAndEnabledRlsTables:15,rolePermissions:87,roleAssignments:1,entitlements:28,memberships:1,
  collisionCounters:priorSummary.collisions,allPriorCollisionFieldsUnchanged:true,currentTrialAccount:current.trial_account,
  originalSixLedger:{migrationLedgerListReread:true,ledgerRows:43,sixOriginalEntriesMatch:true,preservedEntries:preservedSix,sourceMigrationNamesReplayed:false},
  edgeInventory:{actualListReread:true,actualFunctionSourceBodyReread:false,unchangedSincePriorR3:true,deployments:edge.map(e=>({id:e.id,slug:e.slug,version:e.version,status:e.status,metadataBodyHash:e.ezbr_sha256}))},
  immutableInputs:[...bindings.values()],readOnly:true,fullRuntimePreflightComplete:false,runtimeOwnerApproved:false,newRuntimeInstallationComplete:false,
  authenticatedNative:false,fullNativeKeyboardGate:false,realMfa:false,actualDelivery:false,actualModelUsage:false,independentSessionContention:false,targetScaleLoad:false,
  ownerAcceptanceChanged:false,wholeSystemOwnerSignoff:false,sqlInstalled:false,AuthAccountsCreatedOrDeleted:false,privateSecretsRead:false,SDKJobsExecuted:false,
  productionExcluded:true,realBillingExcluded:true,boundary:'Actual saved metadata and migration/Edge-list reads only. No deployment, account, private credential, auth, delivery, load or owner acceptance action.'};
must(summary.collisionCounters&&Object.keys(summary.collisionCounters).length===14&&Object.values(summary.collisionCounters).every(n=>n===0),'EXACT14_UNCHANGED_ZERO_COLLISIONS_REQUIRED');
for(const b of bindings.values())must(sha(await readFile(path.join(root,b.path)))===b.sha256,'INPUT_CHANGED_BEFORE_PUBLICATION:'+b.path);
const bytes=Buffer.from(JSON.stringify(summary,null,2)+'\n');await writeFile(path.join(root,paths.summary),bytes,{flag:'wx'});
const index={kind:'read_only_late_live_preflight_artifact_index',recordedAt:new Date().toISOString(),projectId:context.projectId,observedAt:current.observed_at,
  summary:{path:paths.summary,sha256:sha(bytes),bytes:bytes.length},immutableInputs:[...bindings.values()],readOnly:true,
  summaryPublished:true,sqlInstalled:false,accountsChanged:false,fullRuntimePreflightComplete:false,runtimeOwnerApproved:false};
await writeFile(path.join(root,paths.index),JSON.stringify(index,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({summary:index.summary,index:paths.index,observedAt:current.observed_at,migrationCount:43,apiFunctions:107,unchangedProviders:120,
  onlyChangedFields:changedFields,sixLedgerEntriesPreserved:true,readOnly:true,liveMutations:false,SDKJobsExecuted:false},null,2));
