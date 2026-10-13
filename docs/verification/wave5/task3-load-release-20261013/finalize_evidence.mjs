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
const local=await json(`${base}/local-verification-a2.json`),router=await json(`${base}/provider-router-verification.json`);
const writer=await json(`${base}/fixture_writer-verification.json`);
const live=await json(`${base}/read-only-live-audit.json`),source=await json(`${base}/source-release-checks.json`);
const pub=await json(`${base}/dart-dependency-audit.json`),npm=await json(`${base}/npm-dependency-audit.json`);
const input=await json('docs/verification/wave5/task3-completion-20261013/private-readiness-resume-readback.json');
const peerBase='docs/verification/wave5/task3-peer-review-20261013';
const peer=await json(`${peerBase}/runtime-harness-review-20261013-peer-a2.json`);
const peerTests=await json(`${peerBase}/runtime-harness-local-verification-20261013-peer-a2.json`);
const peerOffline=await json(`${peerBase}/runtime-harness-offline-validation-20261013-peer-a2.json`);
assert(local.value.helper.counts.pass===14&&local.value.provider.counts.pass===121&&local.value.sourcesUnchangedDuringRun,'SAVED_ACTUAL_RESULTS_REQUIRED');
assert(!local.value.offlineHarnessPassed&&router.value.passed&&router.value.sourcesUnchangedDuringRun,'PRESERVED_FAILURE_AND_ROUTER_REQUIRED');
assert(writer.value.passed===true&&writer.value.sourcesUnchangedDuringRun===true,'PASSED_SOURCE_BOUND_WRITER_RECORD_REQUIRED');
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
  dependencyCount:npm.value.result.metadata.dependencies.total,
  boundary:'Exact local installed file hashes and package-lock integrity only; independently review this tree and transport before private use.'};
const dependencyBytes=Buffer.from(JSON.stringify(dependencyManifest,null,2)+'\n');
const dependencyBinding={path:`${base}/dependency-source-manifest.json`,bytes:dependencyBytes.length,sha256:sha(dependencyBytes)};
const sourceDrift=[];
for(const original of source.value.sourcePopulation){try{const actual=(await read(original.path)).binding;if(actual.sha256!==original.sha256)sourceDrift.push({path:original.path,recordedSha256:original.sha256,actualSha256:actual.sha256});}
  catch{sourceDrift.push({path:original.path,currentFileUnavailable:true});}}
const peerDrift=[];
for(const original of peer.value.files){const actual=(await read(original.path)).binding;if(actual.sha256!==original.sha256)peerDrift.push({path:original.path,approvedSha256:original.sha256,actualSha256:actual.sha256});}
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
    fixtureWriter:{binding:writer.binding,counts:writer.value.counts??writer.value.summary,passed:writer.value.passed}},
  originalOfflineHarness:{binding:local.binding,failureCode:'HARNESS_SOURCE_DRIFT',passed:false,originalReviewPreserved:true,
    changedFiles:[{path:'tools/wave5/runtime_coordinator.mjs',approvedSha256:'e41ab3830523f030f7a3cf2bb42ebabf24387697afc521b1d94458ec30dbf9be',actualSha256:'1df1396865610b73614f5ba9b83a8d9b91d40bb642e26d7443934ef11bcd0f3c'},
      {path:'tools/wave5/runtime_coordinator.test.mjs',approvedSha256:'d5b8aba2a49673e540a87fd414be38419c65535902c3eff572afd005733b81c8',actualSha256:'d0582f1c33e3b869411bda08e50a495ecd4a287ae299b570186c271d614036db'}]},
  successorOfflineHarness:{review:peer.binding,testRecord:peerTests.binding,offlineRecord:peerOffline.binding,
    counts:peerTests.value.summary,offlineExitCode:peerOffline.value.childExitCode,planValidated:peerOffline.value.result.planValidated,
    currentSourceDrift:peerDrift,rootIndependentIntegrationReviewComplete:false,executedLive:false},
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
    hostedDartAdvisoryRecord:pub.binding,localNpmAdvisoryRecord:npm.binding,productionReleaseReady:false},
  gates:{fullIndependentSessionContention:false,targetScaleLoad:false,productionRelease:false},
  requiredNextEvidence:['Root independent driver/router/dependency integration review and source-bound private configuration',
    'Successful sealed database input save observed by the live owner','2,000 distinct genuine fresh online-verified sessions with exact distribution/MFA',
    'Actual Auth token quota/JWT lifetime and feasible authorized pre-provisioning without changing global policy or fabricating IPs',
    'Actual region/tier/cache/generator capacity proof and nonempty reviewed 500-scope fixtures',
    'Authentic complete capture of all current reviewed worker transports plus continuous job/inflight quiescence',
    'Full seven-race committed effect/overlap/restoration evidence and exact 360-second load/P95 result',
    'Staging/production separation, isolated restore, delivered monitoring alerts, native accessibility, signed MSIX and controlled pilot'],
  boundary:'Local tests, dependency audits, source review and connector reads are completed preparation. No target-scale workload, live driver, fabricated JWT, hand-written capture or production acceptance is claimed.'};
const protocolBytes=Buffer.from(JSON.stringify(protocol,null,2)+'\n');
const protocolBinding={path:`${base}/protocol-result.json`,bytes:protocolBytes.length,sha256:sha(protocolBytes)};
const ownFiles=[];
for(const item of await fs.readdir(path.join(root,base),{withFileTypes:true})){
  if(item.isFile()&&!['source-manifest.json','dependency-source-manifest.json','protocol-result.json'].includes(item.name))ownFiles.push((await read(`${base}/${item.name}`)).binding);
}
const references=[...local.value.filesBefore.filter(item=>item.path.startsWith('docs/verification/')),
  input.binding,peer.binding,peerTests.binding,peerOffline.binding];
const publicFiles=[];
for(const item of await fs.readdir(path.join(root,'tools/wave5'),{withFileTypes:true}))if(item.isFile()&&item.name.endsWith('.mjs'))publicFiles.push((await read(`tools/wave5/${item.name}`)).binding);
for(const file of ['pubspec.lock','.github/workflows/ci.yml','docs/blueprint/05_TEST_AND_DELIVERY.md','docs/verification/wave5/integrated-runtime-protocol-20261006.md'])publicFiles.push((await read(file)).binding);
const manifest={kind:'additive-load-release-source-and-evidence-manifest',observedAt,
  files:[...ownFiles,protocolBinding,dependencyBinding].sort((a,b)=>a.path.localeCompare(b.path)),
  currentPublicSourceFiles:publicFiles.sort((a,b)=>a.path.localeCompare(b.path)),historicalAndIndependentReferenceBindings:references,
  driverSourcesForIndependentReview:routerBindings,completeDependencyManifest:dependencyBinding,
  sourceScanDriftSinceRecordedObservation:sourceDrift,successorHarnessCurrentDrift:peerDrift,
  rootIndependentIntegrationReviewComplete:false,actualLiveLoad:false,productionRelease:false,
  boundary:'Hashes bind observed file bytes. This manifest is an inventory for independent review, not reviewer signoff, owner waiver or a live-execution result.'};
const manifestBytes=Buffer.from(JSON.stringify(manifest,null,2)+'\n');
await fs.writeFile(path.join(root,dependencyBinding.path),dependencyBytes,{flag:'wx'});
await fs.writeFile(path.join(root,protocolBinding.path),protocolBytes,{flag:'wx'});
await fs.writeFile(path.join(root,base,'source-manifest.json'),manifestBytes,{flag:'wx'});
process.stdout.write(JSON.stringify({protocol:protocolBinding,manifest:{path:`${base}/source-manifest.json`,bytes:manifestBytes.length,sha256:sha(manifestBytes)},
  dependencyManifest:dependencyBinding,dependencyFiles:dependencyFiles.length,routerBindings,sourceScanDrift:sourceDrift.length,successorHarnessDrift:peerDrift.length})+'\n');
