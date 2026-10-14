import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
const root=process.cwd(),base='docs/verification/wave5/task3-load-release-20261013';
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=async file=>{const bytes=await fs.readFile(path.join(root,file));return{bytes,binding:{path:file,bytes:bytes.length,sha256:sha(bytes)}};};
const json=async file=>{const result=await read(file);return{...result,value:JSON.parse(result.bytes)};};
const assert=(ok,code)=>{if(!ok)throw new Error(code);};
async function inventory(relative){
  const directory=path.join(root,relative),files=[];
  for(const item of await fs.readdir(directory,{withFileTypes:true})){
    const file=`${relative}/${item.name}`;
    assert(!item.isSymbolicLink(),'NO_DEPENDENCY_REPARSE_POINT_ALLOWED');
    if(item.isDirectory())files.push(...await inventory(file));
    else if(item.isFile())files.push((await read(file)).binding);
  }return files.sort((a,b)=>a.path.localeCompare(b.path));
}
async function currentReleasePopulation(){
  const selected=new Set();
  async function walk(relative,accept){
    for(const item of await fs.readdir(path.join(root,relative),{withFileTypes:true}).catch(error=>{
      if(error.code==='ENOENT')return[];throw error;})){
      if(['build','.dart_tool','node_modules','.git','dist'].includes(item.name))continue;
      const file=`${relative}/${item.name}`;
      if(item.isDirectory())await walk(file,accept);else if(item.isFile()&&accept(file))selected.add(file);
    }
  }
  selected.add('pubspec.yaml');
  for(const surface of ['apps','packages'])for(const entry of await fs.readdir(path.join(root,surface),{withFileTypes:true})){
    if(!entry.isDirectory())continue;
    await walk(`${surface}/${entry.name}/lib`,file=>file.endsWith('.dart'));
    const manifest=`${surface}/${entry.name}/pubspec.yaml`;try{await fs.access(path.join(root,manifest));selected.add(manifest);}catch{}
  }
  for(const surface of ['workers','supabase/functions'])await walk(surface,file=>/\.(ts|js|mjs)$/.test(file)&&!file.includes('.test.'));
  await walk('supabase/migrations',file=>file.endsWith('.sql'));
  return Promise.all([...selected].sort().map(async file=>(await read(file)).binding));
}
const local=await json(`${base}/local-verification-a2.json`),router=await json(`${base}/provider-router-verification.json`);
const writer=await json(`${base}/fixture_writer-verification.json`);
const operation=await json(`${base}/provider-operation-verification.json`);
const lifecycle=await json(`${base}/readonly-lifecycle-verification.json`);
const live=await json(`${base}/read-only-live-audit.json`),source=await json(`${base}/source-release-checks.json`);
const pub=await json(`${base}/dart-dependency-audit.json`),npm=await json(`${base}/npm-dependency-audit.json`);
const input=await json('docs/verification/wave5/task3-completion-20261013/private-readiness-resume-readback.json');
const selected=process.argv.slice(2);
const successor=selected.length===4&&selected.at(-1)==='a2';
if(successor)selected.pop();
const suffix=successor?'-a2':'';
assert(selected.length===3&&selected.every(file=>/^docs\/verification\/wave5\/task3-acceptance-20261013\/[A-Za-z0-9-]+\.json$/.test(file)),
  'EXACT_PUBLIC_115_HARNESS_PROVIDER_OFFLINE_RECORDS_REQUIRED');
const peer=await json(selected[0]),peerTests=await json(selected[1]),peerOffline=await json(selected[2]);
const integration=await json('docs/verification/wave5/task3-completion-20261013/provider-integration-independent-review-20261014-a2.json');
const installed=await json('docs/verification/wave5/task3-completion-20261013/installed-cash-independent-readback-20261014.json');
const baseline=await json('docs/verification/wave5/task3-acceptance-20261013/load-baseline-115-independent-review.json');
const authQuota=await json('docs/verification/wave5/auth-token-quota-actual-private-readiness-20261014-r5.json');
assert(local.value.helper.counts.pass===14&&local.value.provider.counts.pass===121&&local.value.sourcesUnchangedDuringRun,'SAVED_ACTUAL_RESULTS_REQUIRED');
assert(!local.value.offlineHarnessPassed&&router.value.passed&&router.value.sourcesUnchangedDuringRun,'PRESERVED_FAILURE_AND_ROUTER_REQUIRED');
assert(writer.value.passed===true&&writer.value.sourcesUnchangedDuringRun===true,'PASSED_SOURCE_BOUND_WRITER_RECORD_REQUIRED');
assert(operation.value.passed===true&&operation.value.sourcesUnchangedDuringRun===true
  &&lifecycle.value.passed===true&&lifecycle.value.sourcesUnchangedDuringRun===true,'PASSED_OPERATION_AND_LIFECYCLE_RECORDS_REQUIRED');
assert(integration.value.passed===true&&integration.value.sourcesUnchangedDuringRun===true&&integration.value.counts.pass===61
  &&peerTests.value.childExitCode===0&&peerTests.value.summary.passed===122&&peerOffline.value.childExitCode===0,
  'PASSED_CURRENT_INDEPENDENT_115_RECORDS_REQUIRED');
assert(authQuota.value.jwtLifetimeSeconds===3600&&authQuota.value.tokenRefreshGrantQuotaPerFiveMinutes===150
  &&authQuota.value.numericFieldsOnly===true&&authQuota.value.settingsChanges===0,'ACTUAL_UNCHANGED_AUTH_CAPACITY_RECORD_REQUIRED');
const observedAt=new Date().toISOString(),dependencyFiles=await inventory(`${base}/node_modules`);
const providerSourceFiles=[];
for(const item of await fs.readdir(path.join(root,base),{withFileTypes:true})){
  if(item.isFile()&&(['postgres_transport.mjs','provider_pg_factory.mjs','provider_operation_wrapper.mjs','external_observer.mjs'].includes(item.name)
    ||(/^fixture_writer.*\.mjs$/.test(item.name)&&!item.name.includes('test')&&!item.name.includes('verification'))))
    providerSourceFiles.push((await read(`${base}/${item.name}`)).binding);
}
const dependencyManifest={kind:'exact-installed-pg-helper-dependency-file-manifest',observedAt,
  package:(await read(`${base}/package.json`)).binding,lockfile:(await read(`${base}/package-lock.json`)).binding,
  pinnedPgVersion:'8.23.1',files:dependencyFiles,providerSourceFiles:providerSourceFiles.sort((a,b)=>a.path.localeCompare(b.path)),
  publicSourceFiles:await Promise.all(['runtime_contract.mjs','runtime_fixture_spec.mjs','supabase_runtime_provider.mjs','supabase_read_store.mjs',
    'supabase_membership_fixture.mjs','preparation_journal.mjs','supabase_http_transport.mjs'].map(async name=>(await read(`tools/wave5/${name}`)).binding)),
  dependencyCount:npm.value.result.metadata.dependencies.total,
  boundary:'Exact local installed file hashes and package-lock integrity only; independently review this tree and transport before private use.'};
let dependencyBytes=Buffer.from(JSON.stringify(dependencyManifest,null,2)+'\n');
if(successor){
  const preserved=await json(`${base}/dependency-source-manifest.json`);
  for(const key of ['package','lockfile','pinnedPgVersion','files','providerSourceFiles','publicSourceFiles','dependencyCount'])
    assert(JSON.stringify(preserved.value[key])===JSON.stringify(dependencyManifest[key]),'PRESERVED_DEPENDENCY_MANIFEST_SOURCE_DRIFT');
  dependencyBytes=preserved.bytes;
}
const dependencyBinding={path:`${base}/dependency-source-manifest.json`,bytes:dependencyBytes.length,sha256:sha(dependencyBytes)};
const sourceDrift=[];
for(const original of source.value.sourcePopulation){try{const actual=(await read(original.path)).binding;if(actual.sha256!==original.sha256)sourceDrift.push({path:original.path,recordedSha256:original.sha256,actualSha256:actual.sha256});}
  catch{sourceDrift.push({path:original.path,currentFileUnavailable:true});}}
const currentPopulation=await currentReleasePopulation(),originalPopulation=new Set(source.value.sourcePopulation.map(file=>file.path));
for(const file of currentPopulation)if(!originalPopulation.has(file.path))sourceDrift.push({...file,notInRecordedSourceScan:true});
const peerDrift=[];
for(const original of peer.value.files){const actual=(await read(original.path)).binding;if(actual.sha256!==original.sha256)peerDrift.push({path:original.path,approvedSha256:original.sha256,actualSha256:actual.sha256});}
const integrationDrift=[];
for(const original of integration.value.sourceBindingsBefore){const actual=(await read(original.path)).binding;
  if(actual.sha256!==original.sha256)integrationDrift.push({path:original.path,reviewedSha256:original.sha256,actualSha256:actual.sha256});}
assert(peerDrift.length===0&&integrationDrift.length===0,'CURRENT_HARNESS_OR_INTEGRATION_SOURCE_DRIFT');
const routerBindings={routerSha256:(await read(`${base}/provider_pg_factory.mjs`)).binding.sha256,
  readOnlyDriverSha256:(await read(`${base}/postgres_transport.mjs`)).binding.sha256,
  fixtureDriverSha256:(await read(`${base}/fixture_writer.mjs`)).binding.sha256,dependencyManifestSha256:dependencyBinding.sha256};
const checklistTotals=source.value.checks.reduce((out,check)=>{out[check.status]=(out[check.status]??0)+1;return out;},{PASS:0,FAIL:0,MANUAL:0,SKIP:0});
const protocol={kind:'wave5-concurrency-load-and-release-protocol-result',observedAt,projectId:'xpdoufauvrbdmxgngetv',
  actualLoadPerformed:false,actualPostgresConnection:false,privateDatabaseCredentialRead:false,liveSqlWrites:0,liveAuthCreated:0,
  genuineLoadSessionsCreated:0,SDKJobs:0,productionReleased:false,
  controlledLocal:{originalHelper:{binding:local.binding,counts:local.value.helper.counts,passed:true},
    originalPublicProvider:{binding:local.binding,counts:local.value.provider.counts,passed:true,boundary:'Pre-startup-repair source population in the saved original record.'},
    constructorRouter:{binding:router.binding,counts:router.value.counts,passed:router.value.passed},
    fixtureWriter:{binding:writer.binding,counts:writer.value.counts??writer.value.summary,passed:writer.value.passed},
    historicalOperationIntegration:{binding:operation.binding,counts:operation.value.counts,passed:true,
      boundary:'Historical before later public baseline/driver/manifest successor changes.'},
    boundedReadonlyLifecycle:{binding:lifecycle.binding,counts:lifecycle.value.counts,passed:true},
    currentIndependentIntegration:{binding:integration.binding,counts:integration.value.counts,passed:true,sourcesCurrent:true},
    currentIndependentPublicProvider:{binding:peerTests.binding,counts:peerTests.value.summary,passed:true}},
  originalOfflineHarness:{binding:local.binding,failureCode:'HARNESS_SOURCE_DRIFT',passed:false,originalReviewPreserved:true,
    changedFiles:[{path:'tools/wave5/runtime_coordinator.mjs',approvedSha256:'e41ab3830523f030f7a3cf2bb42ebabf24387697afc521b1d94458ec30dbf9be',actualSha256:'1df1396865610b73614f5ba9b83a8d9b91d40bb642e26d7443934ef11bcd0f3c'},
      {path:'tools/wave5/runtime_coordinator.test.mjs',approvedSha256:'d5b8aba2a49673e540a87fd414be38419c65535902c3eff572afd005733b81c8',actualSha256:'d0582f1c33e3b869411bda08e50a495ecd4a287ae299b570186c271d614036db'}]},
  successorOfflineHarness:{review:peer.binding,testRecord:peerTests.binding,offlineRecord:peerOffline.binding,
    counts:peerTests.value.summary,offlineExitCode:peerOffline.value.childExitCode,planValidated:peerOffline.value.result.planValidated,
    currentSourceDrift:peerDrift,rootIndependentIntegrationReviewComplete:true,executedLive:false},
  strict115Baseline:{independentReview:baseline.binding,laterLiveReadback:installed.binding,actualInstalledMigrations:115,
    historicalOriginalInstalledMigrations:114,apiFunctions:363,livePreflightForThisRunVerified:false},
  authProvisioningCapacity:{binding:authQuota.binding,actualVerifiedAt:authQuota.value.actualVerifiedAt,
    jwtLifetimeSeconds:3600,tokenQuotaPerFiveMinutes:150,documentedBurstTokens:30,
    requiredMinimumRemainingLifetimeSeconds:900,maximumCohortIssuanceWindowSeconds:2700,
    minimum2000TokenIssuanceSecondsAtOneSourceIp:3940,maximumNewValidTokensAtOneSourceIpInRequiredWindow:1380,
    full2000CohortFeasibleAtOneSourceIp:false,actualGenuineProvisioningCapacityVerified:false,
    authSettingsChanged:false,forwardingIpSpoofed:false,tokenVerificationQuotaUnknown:true,
    inference:'At the actual documented token quota, (2000-30)/(150/300)=3940 seconds exceeds the JWT3600-900=2700-second cohort window. A genuine separately reviewed capacity arrangement is required; no global Auth change, spoofed IP or manufactured token is authorized.'},
  privateReadiness:{binding:input.binding,userReportedReady:true,successfulInputSaveEvidenced:false,
    lastCredentialPresenceObservation:input.value.readbacks.findLast(item=>Object.hasOwn(item,'sealedDatabaseFileExists')),
    credentialValuesRead:false,modelKeyRequiredForLoad:false},
  observedCapacity:{binding:live.binding,maxConnections:live.value.capacity.maxConnections,serverConnections:live.value.capacity.serverConnections,
    databaseBytes:live.value.capacity.databaseBytes,sharedBuffers:live.value.capacity.sharedBuffers,
    authSessionRowsTotal:live.value.capacity.authSessionsTotal,reviewedLoadActorSessionRowsExcludingOperator:live.value.capacity.eligibleReviewedLoadSessionRows,
    onlineVerifiedTargetPopulationCount:null,capacitySupportedFor2000Sessions:null},
  target:{scopes:500,distinctGenuineSessions:2000,warmupSeconds:60,measuredSeconds:300,maxRunSeconds:900,
    initialRequestsPerSecond:20,maximumTimedRequests:100000,maxInflight:2000,
    expectedScheduledSendsAtInitialRate:7200,expectedMeasuredSendsAtInitialRate:6000,
    measuredMixPercent:{indexedReads:70,ordinaryForecastCommands:20,boundedAnalytics:10},
    strictP95LimitsMs:{indexedReads:500,ordinaryForecastCommands:1500,boundedAnalytics:3000},
    raceParticipants:{duplicates:100,seats:2,admissions:2,activation:2,execution:2,outboxLeases:2,quota:20}},
  measuredResult:{sessionCount:null,scopeCount:null,warmupMs:null,measurementMs:null,operationCounts:null,p95Ms:null,
    errorCount:null,actualOverlap:null,committedRaceEffects:null,deniedZeroEffects:null,fixtureRestoration:null},
  implementation:{fullPublicProviderAlreadyExists:true,readOnlyAdapterImplemented:true,constructorRouterImplemented:true,
    exactFixtureWriterImplemented:true,fixtureWriterLiveConfigured:false,completeObserverValidationAdapterImplemented:true,
    completeAuthenticCaptureConfigured:false,continuousCurrentJobsAndWorkersQuiescenceVerified:false,
    actualSourceBindingsForIndependentReview:routerBindings},
  releaseAudit:{sourceCheckRecord:source.binding,sourceFiles:source.value.sourcePopulation.length,checkCount:source.value.checks.length,
    checklistTotals,sourceScanCurrentAtPackaging:sourceDrift.length===0,currentSourceDrift:sourceDrift,
    currentPopulationFileCount:currentPopulation.length,
    hostedDartAdvisoryRecord:pub.binding,localNpmAdvisoryRecord:npm.binding,productionReleaseReady:false},
  gates:{fullIndependentSessionContention:false,targetScaleLoad:false,productionRelease:false},
  requiredNextEvidence:['Bind final dependency manifest/current reviewed source digests into an outside-repository private provider and preparation review',
    'Successful sealed database input save observed by the live owner','2,000 distinct genuine fresh online-verified sessions with exact distribution/MFA',
    'Feasible separately reviewed genuine pre-provisioning capacity for the observed Auth150/5min and JWT3600s without changing global policy or fabricating IPs',
    'Actual region/tier/cache/generator capacity proof and nonempty reviewed 500-scope fixtures',
    'Authentic complete capture of all current reviewed worker transports plus continuous job/inflight quiescence',
    'Full seven-race committed effect/overlap/restoration evidence and exact 360-second load/P95 result',
    'Staging/production separation, isolated restore, delivered monitoring alerts, native accessibility, signed MSIX and controlled pilot'],
  boundary:'Local tests, dependency audits, source review and connector reads are completed preparation. No target-scale workload, live driver, fabricated JWT, hand-written capture or production acceptance is claimed.'};
const protocolBytes=Buffer.from(JSON.stringify(protocol,null,2)+'\n');
const protocolBinding={path:`${base}/protocol-result${suffix}.json`,bytes:protocolBytes.length,sha256:sha(protocolBytes)};
const ownFiles=[];
for(const item of await fs.readdir(path.join(root,base),{withFileTypes:true})){
  if(item.isFile()&&!['dependency-source-manifest.json',`protocol-result${suffix}.json`,`source-manifest${suffix}.json`].includes(item.name))
    ownFiles.push((await read(`${base}/${item.name}`)).binding);
}
const references=[...local.value.filesBefore.filter(item=>item.path.startsWith('docs/verification/')),
  input.binding,peer.binding,peerTests.binding,peerOffline.binding,integration.binding,baseline.binding,installed.binding,authQuota.binding];
for(const file of ['docs/verification/wave5/task3-completion-20261013/provider-integration-independent-review-20261014.json',
  'docs/verification/wave5/task3-completion-20261013/provider-integration-verifier-source-diagnostic-a1.json',
  'docs/verification/wave5/task3-acceptance-20261013/runtime-provider-local-verification-20261014-acceptance-a1.json',
  'docs/verification/wave5/task3-acceptance-20261013/runtime-provider-local-verification-20261014-acceptance-a2.json']){
  try{references.push((await read(file)).binding);}catch(error){if(error.code!=='ENOENT')throw error;}
}
const publicFiles=[];
for(const item of await fs.readdir(path.join(root,'tools/wave5'),{withFileTypes:true}))if(item.isFile()&&item.name.endsWith('.mjs'))publicFiles.push((await read(`tools/wave5/${item.name}`)).binding);
for(const file of ['pubspec.lock','.github/workflows/ci.yml','docs/blueprint/05_TEST_AND_DELIVERY.md','docs/verification/wave5/integrated-runtime-protocol-20261006.md'])publicFiles.push((await read(file)).binding);
const manifest={kind:'additive-load-release-source-and-evidence-manifest',observedAt,
  files:[...ownFiles,protocolBinding,dependencyBinding].sort((a,b)=>a.path.localeCompare(b.path)),
  currentPublicSourceFiles:publicFiles.sort((a,b)=>a.path.localeCompare(b.path)),historicalAndIndependentReferenceBindings:references,
  currentReleaseSourcePopulation:currentPopulation,
  driverSourcesForIndependentReview:routerBindings,completeDependencyManifest:dependencyBinding,
  sourceScanDriftSinceRecordedObservation:sourceDrift,successorHarnessCurrentDrift:peerDrift,
  rootIndependentIntegrationReviewComplete:true,actualLiveLoad:false,productionRelease:false,
  boundary:'Hashes bind observed file bytes. This manifest is an inventory for independent review, not reviewer signoff, owner waiver or a live-execution result.'};
const manifestBytes=Buffer.from(JSON.stringify(manifest,null,2)+'\n');
if(!successor)await fs.writeFile(path.join(root,dependencyBinding.path),dependencyBytes,{flag:'wx'});
await fs.writeFile(path.join(root,protocolBinding.path),protocolBytes,{flag:'wx'});
await fs.writeFile(path.join(root,base,`source-manifest${suffix}.json`),manifestBytes,{flag:'wx'});
process.stdout.write(JSON.stringify({protocol:protocolBinding,manifest:{path:`${base}/source-manifest${suffix}.json`,bytes:manifestBytes.length,sha256:sha(manifestBytes)},
  dependencyManifest:dependencyBinding,dependencyFiles:dependencyFiles.length,routerBindings,sourceScanDrift:sourceDrift.length,successorHarnessDrift:peerDrift.length})+'\n');
