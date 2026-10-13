// New hash-only adapter. The r3 adapter and every dated r14 result are preserved.
// No tests, SDK, provider, worker, Auth or hosted operation is launched here.
import {readFile,writeFile,readdir} from 'node:fs/promises';
import path from 'node:path';
import {assert,base,root,sha,hash,json,exists,equal,sourceGuard,fullDesktop} from './windows_delivery_inputs_20261010_r4.mjs';
const self='scripts/wave5/prepare_runtime_worker_adapter_20261010_r4.mjs';
const output=base+'current-runtime-worker-adapter-20261010-r4.json';
assert(!await exists(output),'NEW_WORKER_ADAPTER_OUTPUT_REQUIRED');
const nativePath=base+'windows-test-verification-20261010-r4.json',native=await json(nativePath);
const sourcePath=base+'desktop-verification-source-20261010-r4-approved.json',source=await json(sourcePath);
const connectedPath=base+'windows-test-connected-package-20261010-r4.json',connected=await json(connectedPath);
assert(source.revision==='r4'&&source.postImageApproval===true&&native.kind==='paired-ordinary-native-build-adapter'&&native.revision==='r4'&&native.currentSourceMatch===true&&native.previewBuilt===true&&native.connectedBuilt===true&&native.sourceFilesPerApp===source.selectedSources,'PAIRED_CURRENT_POSTAPPROVAL_NATIVE_REPORT_REQUIRED');
assert(connected.controlledEvidence===false&&connected.mode==='connected'&&connected.projectId==='xpdoufauvrbdmxgngetv'&&connected.base_source_match===true&&connected.current_source_match===true&&equal(connected.sourceHashes,source.sourceHashes),'CURRENT_CONNECTED_BASE_SOURCE_REQUIRED');
const full=await fullDesktop({baseSourceHashes:source.sourceHashes});
assert(equal(full,native.desktopBaseSourceSuite)&&equal(full,connected.fullDesktopEvidence),'CURRENT_FULL_SUITE_BINDING_REQUIRED');
const componentPath=base+'continuation-worker-component-20261009-r14.json',component=await json(componentPath);
assert(component.revision==='r14'&&component.migrationHashesUnchanged===true&&component.actualModelUsage===false&&component.actualWorkerDelivery===false&&component.installedSql===false&&component.realMfa===false&&component.targetScaleLoad===false,'UNCHANGED_HISTORICAL_WORKER_COMPONENT_REQUIRED');
const worker=await json(component.sourceRecord),tests=await json(component.testRecord),deno=await json(component.denoRecord);
assert(worker.files.length===26&&new Set(worker.files.map(f=>f.path)).size===26&&tests.exitCode===0&&tests.passed===71&&tests.tests===71&&tests.failed===0&&tests.controlled===true&&tests.externalCalls===false,'EXACT_HISTORICAL_CONTROLLED_WORKER_EVIDENCE_REQUIRED');
assert(deno.checksRerun===true&&deno.entrypoints.length===2&&deno.entrypoints.every(e=>e.exitCode===0),'HISTORICAL_TWO_ENTRYPOINT_CHECKS_REQUIRED');
const currentInventory=(await readdir(path.join(root,'workers/wave5'))).filter(f=>f.endsWith('.mjs')).map(f=>'workers/wave5/'+f).sort();
assert(JSON.stringify(currentInventory)===JSON.stringify(worker.files.map(f=>f.path).sort()),'EXACT_UNCHANGED_WORKER_INVENTORY_REQUIRED');
const bindings=new Map();
async function bind(p,expected){const h=await hash(p);assert(!expected||h===expected,'HISTORICAL_BINDING_CHANGED:'+p);assert(!bindings.has(p)||bindings.get(p)===h,'BINDING_CHANGED_DURING_ADAPTER:'+p);bindings.set(p,h);return {path:p,sha256:h};}
const workerFiles=[];
for(const file of worker.files){await bind(file.path,file.sha256);workerFiles.push({path:file.path,sha256:file.sha256});}
await bind(tests.log,tests.logSha256);
const testLog=(await readFile(path.join(root,tests.log))).toString('utf8');
for(const [name,count]of [['tests',71],['pass',71],['fail',0],['cancelled',0],['skipped',0],['todo',0]]){
 const summaries=[...testLog.matchAll(new RegExp('^(?:#|ℹ) '+name+' (\\d+)\\r?$','gm'))];
 assert(summaries.length===1&&Number(summaries[0][1])===count,'EXACT_HISTORICAL_WORKER_LOG_COUNTS_REQUIRED:'+name);
}
for(const checked of deno.entrypoints){await bind(checked.entrypoint,checked.entrypointSha256);await bind(checked.config,checked.configSha256);await bind(checked.log,checked.logSha256);}
const originalPath=base+'complete-app-runtime-review-20261009.json',original=await json(originalPath),{bundleSha256,...originalBody}=original;
assert(sha(JSON.stringify(originalBody))===bundleSha256&&bundleSha256==='13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e'&&original.ownerApproved===false,'PRESERVED_ORIGINAL_UNAPPROVED_REVIEW_REQUIRED');
assert(original.migrations.length===71&&component.migrations===71,'EXACT_71_MIGRATIONS_REQUIRED');
for(const migration of original.migrations)await bind(migration.path,migration.sha256);
const deployments=[];
for(const deployment of component.deployments){
 const payload=await json(deployment.payloadPath),expectedCount=deployment.name==='wave5-runtime'?14:deployment.name==='wave5-receiver'?8:null;
 assert(expectedCount&&deployment.files.length===expectedCount&&payload.files.length===expectedCount&&new Set(payload.files.map(f=>f.name)).size===expectedCount&&payload.project_id===original.projectId&&payload.name===deployment.name&&payload.verify_jwt===false,'EXACT_DEPLOYMENT_SCOPE_REQUIRED');
 await bind(deployment.payloadPath);
 for(const file of payload.files){
  const current=await readFile(path.join(root,file.name),'utf8');assert(current===file.content,'PAYLOAD_CURRENT_SOURCE_CHANGED');
  const ref=deployment.files.find(f=>f.path===file.name);assert(ref&&sha(Buffer.from(current))===ref.sha256,'PAYLOAD_COMPONENT_HASH_CHANGED');await bind(file.name,ref.sha256);
 }
 deployments.push({name:deployment.name,payload:await bind(deployment.payloadPath),entrypoint:deployment.entrypoint,verifyJwt:false,files:deployment.files,sourceFileCount:expectedCount,deployed:false});
}
for(const p of [componentPath,component.sourceRecord,component.testRecord,component.denoRecord,nativePath,sourcePath,connectedPath,originalPath,
 self,'scripts/wave5/windows_delivery_inputs_20261010_r4.mjs',full.record,full.log])await bind(p);
for(const mode of ['Preview','Connected'])await sourceGuard(mode);
const adapter={observedAt:new Date().toISOString(),kind:'current-runtime-worker-adapter',revision:'r4',projectId:original.projectId,
 sourceManifest:await bind(sourcePath),nativeReport:await bind(nativePath),connectedManifest:await bind(connectedPath),historicalComponent:await bind(componentPath),
 currentDesktopSuite:{record:full.record,sha256:full.recordSha256,passed:full.passedTests,failed:0,skipped:0},
 historicalWorkerObservedAt:component.preparedAt,workerSourceRecord:await bind(component.sourceRecord),historicalTestRecord:await bind(component.testRecord),historicalDenoRecord:await bind(component.denoRecord),
 workerSourceUnchanged:true,workerTestsRerun:false,denoChecksRerun:false,workerFiles:26,workerSourceFiles:workerFiles,controlledTests:71,denoEntrypoints:2,
 historicalControlledTestsOnly:true,historicalImportedJavaScriptTypeChecked:false,deployments,deploymentSourceFileCounts:[14,8],migrationHashesUnchanged:true,migrationCount:71,
 bindings:[...bindings].sort(([a],[b])=>a.localeCompare(b)).map(([p,h])=>({path:p,sha256:h})),
 currentSourceMatchesNative:true,installedWorker:false,installedSql:false,newMigrationsInstalled:false,actualWorkerDelivery:false,actualModelUsage:false,realMfa:false,
 authenticatedNative:false,nativeKeyboardVerified:false,independentSessionContention:false,targetScaleLoad:false,ownerAccepted:false,liveOperationsPerformed:false,
 SDKExecuted:false,workerTestsExecuted:false,DenoExecuted:false,nativeLaunched:false,privateSecretsRead:false,AuthUsersCreatedOrDeleted:false,localStoresReadOrCopied:false,
 boundary:'Current hash-only revalidation against the fresh r4 paired source and package context. The 71 controlled worker tests and two Deno entrypoint checks retain their October 9 r14 observations. Prepared 14/8-file payloads are not installed or deployed; operation approval and actual runtime effects remain separate.'};
for(const binding of adapter.bindings)assert(await hash(binding.path)===binding.sha256,'WORKER_ADAPTER_INPUT_CHANGED_DURING_PREPARATION');
adapter.inputHashesStableDuringPreparation=true;
await writeFile(path.join(root,output),JSON.stringify(adapter,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({adapter:output,workerFiles:26,controlledTests:71,denoEntrypoints:2,workerTestsRerun:false,denoChecksRerun:false,liveOperationsPerformed:false}));
