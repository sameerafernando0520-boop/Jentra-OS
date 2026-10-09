// Compose a new exact operation review without overwriting the original review.
// Inputs must contain current local build/test evidence and a fresh live read.
// This prepares files only; it does not approve or execute any reviewed action.
import {readFile,readdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const revision=process.argv[2],base='docs/verification/wave5/';
if(!/^r\d+$/.test(revision??''))throw Error('CONTINUATION_REVISION_REQUIRED');
const componentPath=process.argv[3]??base+`continuation-worker-component-20261009-${revision}.json`;
const livePath=process.argv[4]??base+'continuation-live-summary-20261010.json';
const nativePath=base+`windows-test-verification-20261009-${revision}.json`;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
const save=async(p,value)=>writeFile(p,JSON.stringify(value,null,2)+'\n',{flag:'wx'});
const originalPath=base+'complete-app-runtime-review-20261009.json';
const original=await json(originalPath),{bundleSha256:originalBundleSha256,...originalBody}=original;
if(sha(JSON.stringify(originalBody))!==originalBundleSha256||original.ownerApproved!==false)throw Error('ORIGINAL_REVIEW_CHANGED');
const component=await json(componentPath),native=await json(nativePath),live=await json(livePath);
if(component.originalReview.bundleSha256!==originalBundleSha256||component.migrationHashesUnchanged!==true||component.liveOperationsPerformed===true)throw Error('WORKER_COMPONENT_INVALID');
const source=await json(component.sourceRecord),tests=await json(component.testRecord),deno=await json(component.denoRecord);
if(tests.exitCode!==0||tests.passed<68||tests.passed!==tests.tests||tests.failed!==0||!tests.controlled||tests.externalCalls!==false||!deno.checksRerun||deno.entrypoints.some(c=>c.exitCode!==0))throw Error('CURRENT_WORKER_VERIFICATION_REQUIRED');
if(sha(await readFile(tests.log))!==tests.logSha256)throw Error('WORKER_TEST_LOG_DRIFT');
for(const f of source.files)if(sha(await readFile(f.path))!==f.sha256)throw Error('WORKER_SOURCE_DRIFT:'+f.path);
for(const c of deno.entrypoints)if(sha(await readFile(c.entrypoint))!==c.entrypointSha256||sha(await readFile(c.config))!==c.configSha256||sha(await readFile(c.log))!==c.logSha256)throw Error('DENO_SOURCE_LOG_DRIFT');
if(live.migrationCount!==43||live.apiFunctions!==107||live.rolePermissions!==87||live.roleAssignments!==1||live.entitlements!==28||live.memberships!==1||
 live.proposedRuntimeAccounts!==0||live.changedProviders?.length||live.edgeAuthorities||live.cronJobs||live.netQueue)throw Error('LIVE_BASELINE_DRIFT');
if(native.revision!==revision||native.currentSourceMatch!==true||native.previewBuilt!==true||native.connectedBuilt!==true||
 native.authenticatedNativeAcceptance!==false||native.realMfa!==false||native.ownerAccepted!==false)throw Error('CURRENT_NATIVE_GATE_REPORT_REQUIRED');
const nativeArtifacts=[nativePath];
const connectedManifest=base+`windows-test-connected-package-20261009-${revision}.json`;
let releaseCount=0;
for(const mode of ['preview','connected']){
 const manifest=base+`windows-test-${mode}-package-20261009-${revision}.json`,build=await json(manifest);
 if(build.mode!==mode||build.entrypoint!=='lib/main.dart'||build.controlledEvidence!==false||build.current_source_match!==true||build.base_source_match!==true||
  Object.keys(build.sourceHashes).length!==native.sourceFilesPerApp||mode==='connected'&&build.projectId!==original.projectId)throw Error('CURRENT_BUILD_BINDING_REQUIRED:'+mode);
 for(const [p,h] of Object.entries(build.sourceHashes))if(sha(await readFile(p))!==h)throw Error('NATIVE_SOURCE_DRIFT:'+p);
 for(const f of build.releaseFiles)if(sha(await readFile(path.join(build.packageDirectory,f.path)))!==f.sha256)throw Error('NATIVE_RELEASE_DRIFT:'+f.path);
 releaseCount+=build.releaseFiles.length;nativeArtifacts.push(manifest,build.sourceManifest,build.buildEvidence);
}
if(native.releaseEntriesVerified!==releaseCount)throw Error('NATIVE_RELEASE_COUNT_MISMATCH');
if(native.delivery){
 const delivery=await json(native.delivery);
 if(sha(await readFile(delivery.zip))!==delivery.zipSha256)throw Error('NATIVE_ZIP_DRIFT');
 nativeArtifacts.push(native.delivery);
}
for(const stage of native.stages??[])for(const p of [stage.record,stage.log])if(p)nativeArtifacts.push(p);
for(const frame of [...(native.cashFrames??[]),...(native.modelFrames??[]),...(native.authFrames??[])]){
 if(sha(await readFile(frame.path))!==frame.sha256)throw Error('NATIVE_RENDER_DRIFT:'+frame.path);
 nativeArtifacts.push(frame.path);
}
for(const m of original.migrations)if(sha(await readFile(m.path))!==m.sha256)throw Error('MIGRATION_DRIFT:'+m.path);
for(const d of component.deployments){
 const payload=await json(d.payloadPath);
 if(payload.name!==d.name||payload.project_id!==original.projectId||payload.verify_jwt!==false)throw Error('DEPLOYMENT_BINDING_MISMATCH');
 for(const f of payload.files)if(await readFile(f.name,'utf8')!==f.content)throw Error('DEPLOYMENT_SOURCE_DRIFT:'+f.name);
}
const excluded=/^docs\/verification\/wave5\/(windows-test-|supabase-deploy-wave5-|supabase-entrypoint-checks-|complete-app-worker-(?:source|tests)-)/;
const artifactPaths=[...original.artifacts.map(a=>a.path).filter(p=>!excluded.test(p)),...nativeArtifacts,
 base+`windows-test-verification-20261009-${revision}.md`,
 base+`windows-test-frame-inspections-20261009-${revision}.json`,
 base+`continuation-windows-recorder-attempt1-20261009-${revision}.json`,
 base+'continuation-goldens-native-20261009.md',base+'continuation-goldens-native-20261009.json',
 base+`continuation-goldens-comparison-20261009-${revision}.json`,
 base+'continuation-providers-cash-20261009.md',base+'continuation-workers-model-20261009.md',
 base+'desktop-test-login-20261009.md',base+'desktop-test-login-result-20261009.json',base+'desktop-test-login-signin-20261009.json',
 base+'windows-account-google-setup-20261009.md',base+'public-auth-settings-20261010.json',
 base+'continuation-live-preflight-20261009.json',base+'continuation-live-catalog-20261009.json',base+'continuation-live-core-catalog-20261009.json',
 base+'continuation-live-refresh-20261010.json',
 originalPath,componentPath,livePath,component.sourceRecord,component.testRecord,tests.log,component.denoRecord,
 ...deno.entrypoints.map(c=>c.log),...source.files.map(f=>f.path),...component.deployments.map(d=>d.payloadPath),
 ...component.deployments.flatMap(d=>d.files.map(f=>f.path)),
 'scripts/wave5/prepare_continuation_workers.mjs','scripts/wave5/prepare_continuation_runtime_review.mjs',
 'scripts/wave5/record_continuation_windows.mjs','scripts/wave5/run_cash_epoch_red.ps1',
 'scripts/wave5/update_continuation_status_20261010.mjs','scripts/wave5/finalize_windows_test_package.ps1'];
const artifacts=[];
for(const p of [...new Set(artifactPaths)].sort())artifacts.push({path:p,sha256:sha(await readFile(p))});
const originalArtifactDrift=[];
for(const a of original.artifacts){const current=sha(await readFile(a.path));if(current!==a.sha256)originalArtifactDrift.push({path:a.path,originalSha256:a.sha256,currentSha256:current});}
const workerConfiguration=structuredClone(original.workerConfiguration);
workerConfiguration.nativeIsolation.connectedBuildManifest=connectedManifest;
workerConfiguration.nativeIsolation.windowsSourceRevision=revision;
workerConfiguration.nativeIsolation.verifiedReleaseEntries=releaseCount;
const evidence={candidateStrictAssertions:105,candidateRolledBack:true,candidateChecksRerun:false,bootstrapMappingStrictAssertions:25,
 bootstrapMappingRolledBack:true,bootstrapPermissionShim:false,bootstrapChecksRerun:false,controlledWorkerTests:tests.passed,workerTestsRerun:true,
 entrypointsDenoChecked:true,entrypointsDenoChecksRerun:true,importedJavaScriptTypeChecked:false,workerComponent:componentPath,
 freshLiveSummary:livePath,checkedProviders:live.checkedProviders,unchangedProviders:live.unchangedProviders,
 nativeReport:nativePath,windowsSourceRevision:revision,desktopAnalysisClean:native.stages?.find(s=>s.stage==='analyzer')?.exitCode===0,
 windowsPreviewBuilt:true,windowsConnectedBuilt:true,ordinaryEntrypoint:'lib/main.dart',sourceFiles:native.sourceFilesPerApp,releaseEntries:releaseCount,
 nativeLaunched:native.nativeLaunched===true,nativeKeyboardVerified:native.nativeKeyboardVerified===true,
 installedNewMigrations:false,realMfa:false,authenticatedNative:false,actualWorkerDelivery:false,actualModelUsage:false,
 independentContention:false,targetScaleLoad:false,ownerSignoff:false,previousSixInstalledAssertions:126,
 historicalCandidateEvidence:'The unchanged SQL candidates retain their prior rollback probes; those probes were not rerun by this source continuation.',
 historicalNativeEvidence:'Original r10 native launch/full-suite observations remain preserved; no native launch/acceptance is inherited by the current source.'};
const body={...originalBody,reviewId:`jentra-complete-app-supabase-runtime-20261009-${revision}`,preparedAt:new Date().toISOString(),ownerApproved:false,
 supersedes:originalPath,approvalReady:true,liveBaseline:{...original.liveBaseline,observedAt:live.observedAt,migrations:live.migrationCount,apiFunctions:live.apiFunctions,
  rolePermissions:live.rolePermissions,roleAssignments:live.roleAssignments,entitlements:live.entitlements,memberships:live.memberships,
  refreshedBy:livePath,originalPostRollbackObservedAt:original.liveBaseline.postRollbackObservedAt},
 workerConfiguration,deployments:component.deployments,evidence,artifacts,
 sourceContinuation:{originalBundleSha256,originalArtifactDrift,component:componentPath,originalReviewAndPayloadsPreserved:true,
  originalApprovalCannotAuthorizeChangedSource:true,nativeBuildManifestMustMatchReviewedArtifact:true},
 remainingDevelopment:['Original 83 desktop golden failures retain separate investigation and owner visual gates; approved images remain preserved.',
  'Genuine MFA, authenticated native keyboard/restart/revocation, actual export/model/worker delivery, independent contention/load and owner acceptance remain open.',
  ...original.remainingDevelopment]};
const review={...body,bundleSha256:sha(JSON.stringify(body))},reviewPath=base+`complete-app-runtime-review-20261009-${revision}.json`;
await save(reviewPath,review);
const text=`# Jentra OS refreshed runtime review, ${revision}\n\n**Operation approval is absent. Nothing in this review authorizes execution until the owner approves its exact bundle SHA.**\n\nBundle SHA-256: \`${review.bundleSha256}\`. [Exact machine manifest](${path.posix.basename(reviewPath)}) binds all 71 unchanged additional migration hashes, 500 synthetic scopes, six real account labels, exact roles/plans/source caps/operator/native target, current worker deployment payloads and verified native build manifests.\n\nThe [original review](complete-app-runtime-review-20261009.md), bundle \`${originalBundleSha256}\`, remains preserved. Its operations and exclusions are unchanged; its hash cannot authorize the changed source. This refreshed manifest supersedes its source bindings. Production, real billing, unrelated accounts/stores, global Auth changes and Git publication remain excluded. Hosting remains the existing project \`xpdoufauvrbdmxgngetv\`. The six already installed Wave 5 migrations remain excluded.\n\nFresh read: ${live.observedAt}, ${live.migrationCount} migrations / ${live.apiFunctions} API functions; ${live.checkedProviders} provider fingerprints checked and ${live.unchangedProviders} unchanged. Role/access counts remain 87/1/28/1; the six runtime accounts, Edge authority, schedules and net queue remain absent. The separate privately created desktop trial account is outside this six-account bootstrap. Recheck live collisions and all hashes immediately before any approved operation.\n\nApprove only the original exact operations: 71 missing migrations in manifest order; private Auth Admin creation/binding of the six labels; reviewed synthetic 500-scope bootstrap/four plans/access/source caps; bounded separate operator; one new standard Windows profile; three new Vault values and privately configured model; two exact same-project Edge deployments; three expiring schedules; real bounded MFA/delivery/export/contention/load verification. Expected ledger after only these migrations remains 114. Owner acceptance remains a separate decision.\n\nCurrent controlled worker tests: **${tests.passed} passed / zero failed**. Four regressions reproduced unfinished-body/cancellation failures before the fix; eight current regressions also cover receiver delay, DNS/transport and subscription cancellation. Request body reads now observe the 65-second server deadline and caller abort; receiver downstream fetches share that deadline. Both current Edge entrypoints pass fresh Deno checking; imported JavaScript uses controlled Node verification. Exact ${component.deployments.map(d=>d.name+' '+d.files.length+'-file').join(' and ')} payloads match current source and retain reviewed custom authentication with \`verify_jwt=false\`. No worker/model call or deployment occurred.\n\nCurrent ordinary Preview/Connected builds bind ${native.sourceFilesPerApp} selected source inputs per app and ${releaseCount} shipped release hashes. [Current Windows evidence](${path.posix.basename(nativePath)}) records only its observed tests/build/renders. Native launch: ${native.nativeLaunched===true}; native keyboard: ${native.nativeKeyboardVerified===true}; authenticated native/MFA: false. The native provisioning script requires the exact Connected build manifest that is an artifact of this reviewed bundle, then rechecks every source/release byte before any account or file operation. Existing native profiles/packages collide and abort.\n\nThe unchanged 105-assertion candidate and 25-assertion bootstrap probes remain historical rollback evidence. Installation, private provisioning, distinct genuine MFA, nonempty authoritative source/provider checks, governed export download/hash/reopen, actual signed delivery/reconciliation/rotation/revocation/replay/restart, trusted actual model usage, independent-session contention, 500-tenant/2,000-session load and all 109 owner acceptance decisions remain open. No approval or acceptance is inferred from these source checks.\n`;
await writeFile(base+`complete-app-runtime-review-20261009-${revision}.md`,text,{flag:'wx'});
console.log(JSON.stringify({reviewPath,bundleSha256:review.bundleSha256,artifacts:artifacts.length,migrations:review.migrations.length,
 sourceFiles:native.sourceFilesPerApp,releaseEntries:releaseCount,ownerApproved:false,nativeLaunched:evidence.nativeLaunched,actualWorkerDelivery:false}));
