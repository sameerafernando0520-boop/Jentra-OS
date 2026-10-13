// NEW r4 variant; preserved predecessor record_windows_userflow_20261010_r3.mjs SHA-256 db102798ea373e0910914c3c842bf8e06dadd03ccb9f067f5b282dc7f7570fab.
// Exact paired ordinary package adapter for the runtime-review composer.
// Native user-flow evidence is recorded separately by root after this checkpoint.
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
import {assert,base,root,packageDirectory,packageName,sha,bytes,hash,json,exists,equal,sourceGuard,files,fullDesktop,stageEvidence,executableIdentity,readZipEntries,zipEntryBytes} from './windows_delivery_inputs_20261010_r4.mjs';
const output=base+'windows-test-verification-20261010-r4.json',markdown=output.replace(/\.json$/,'.md');
assert(!await exists(output)&&!await exists(markdown),'NEW_NATIVE_ADAPTER_OUTPUT_REQUIRED');
const inputsPath=base+'windows-test-package-inputs-20261010-r4.json',inputs=await json(inputsPath);
assert(inputs.packageDirectory===packageDirectory&&inputs.packageName===packageName&&inputs.compiledRunnerIdentitiesVerified===true&&inputs.nativeLaunched===false,'EXACT_PAIRED_PACKAGE_INPUTS_REQUIRED');
assert(equal(Object.fromEntries(inputs.packageFiles.map(f=>[f.path,f.sha256])),Object.fromEntries((await files(packageDirectory)).map(f=>[f.path,f.sha256]))),'PACKAGE_FILE_SET_DRIFT');
const deliveryPath=base+'windows-test-delivery-20261010-r4.json',delivery=await json(deliveryPath);
assert(delivery.revision==='r4'&&delivery.packageInputs===inputsPath&&delivery.packageInputsSha256===await hash(inputsPath)&&delivery.packageDirectory===packageDirectory&&delivery.bothAppsIncluded===true,'PAIRED_DELIVERY_BINDING_REQUIRED');
const archive=await bytes(delivery.zip);assert(sha(archive)===delivery.zipSha256&&archive.length===delivery.zipBytes,'ZIP_HASH_OR_SIZE_DRIFT');
const entries=readZipEntries(archive),fileEntries=[...entries.keys()].filter(p=>!p.endsWith('/'));
assert(fileEntries.length===inputs.packageFiles.length,'ZIP_FILE_SET_COUNT_MISMATCH');
for(const file of inputs.packageFiles){
 const name=packageName+'/'+file.path,entry=entries.get(name);
 assert(entry&&sha(zipEntryBytes(archive,entry,file.bytes))===file.sha256,'ZIP_FILE_HASH_OR_SIZE_MISMATCH');
}
const builds=[],stages=[];let desktop,releaseEntriesVerified=0;
for(const mode of ['Preview','Connected']){
 const guarded=await sourceGuard(mode),source=await json(guarded.manifest.path);
 const packagePath=`${base}windows-test-${mode.toLowerCase()}-package-20261010-r4.json`,packaged=await json(packagePath);
 const bound=inputs.manifests.find(m=>m.mode===mode.toLowerCase());
 assert(bound?.path===packagePath&&bound.sha256===await hash(packagePath),'PACKAGE_INPUT_MANIFEST_DRIFT');
 assert(packaged.mode===mode.toLowerCase()&&packaged.revision==='r4'&&packaged.entrypoint==='lib/main.dart'&&packaged.controlledEvidence===false&&packaged.current_source_match===true&&packaged.base_source_match===true,'ORDINARY_CURRENT_PACKAGE_REQUIRED');
 assert(packaged.sourceManifest===guarded.manifest.path&&packaged.sourceManifestSha256===guarded.manifest.sha256&&equal(packaged.sourceHashes,source.baseSourceHashes)&&equal(packaged.buildSourceHashes,source.buildSourceHashes),'PACKAGE_SOURCE_BINDING_DRIFT');
 const expectedRelease=path.join(source.snapshot,'apps/jentra_desktop/build/windows/x64/runner/Release'),expectedPackage=path.join(packageDirectory,mode);
 assert(packaged.releaseDirectory===expectedRelease&&packaged.packageDirectory===expectedPackage&&packaged.projectId===(mode==='Connected'?'xpdoufauvrbdmxgngetv':null),'EXACT_PACKAGE_RELEASE_OR_PROJECT_REQUIRED');
 for(const directory of [expectedRelease,expectedPackage]){
  const actual=(await files(directory)).filter(f=>f.path!=='release-manifest.json');
  assert(equal(Object.fromEntries(actual.map(f=>[f.path,f.sha256])),Object.fromEntries(packaged.releaseFiles.map(f=>[f.path,f.sha256]))),'EXACT_RELEASE_FILE_SET_CHANGED');
  for(const f of actual)assert(packaged.releaseFiles.find(p=>p.path===f.path)?.bytes===f.bytes,'RELEASE_BYTE_COUNT_DRIFT');
 }
 const releaseIdentity=await executableIdentity(mode,path.join(expectedRelease,'Jentra_OS.exe')),packageIdentity=await executableIdentity(mode,path.join(expectedPackage,'Jentra_OS.exe'));
 assert(releaseIdentity.sha256===packageIdentity.sha256,'BUILD_AND_COPY_EXECUTABLE_MISMATCH');
 const buildAttempt=packaged.toolchainGuard.path.match(/-r4-([a-z][a-z0-9]{0,8})\.json$/)?.[1];
 assert(buildAttempt,'EXACT_R4_BUILD_ATTEMPT_REQUIRED');
 const build=await stageEvidence(mode,'build',buildAttempt);
 assert(build.record===packaged.buildEvidence&&build.recordSha256===packaged.buildEvidenceSha256,'PACKAGE_BUILD_STAGE_DRIFT');stages.push(build);
 const currentDesktop=await fullDesktop(source);if(desktop)assert(equal(desktop,currentDesktop),'PAIRED_BASE_SUITE_MISMATCH');else desktop=currentDesktop;
 builds.push({mode:mode.toLowerCase(),sourceManifest:guarded.manifest.path,sourceManifestSha256:guarded.manifest.sha256,packageManifest:packagePath,packageManifestSha256:await hash(packagePath),
  sourceFileCount:source.sourceFileCount,sourceHashesVerified:true,releaseFiles:packaged.releaseFiles.length,releaseDirectory:expectedRelease,packageDirectory:expectedPackage,
  entrypoint:'lib/main.dart',storageIdentity:source.stores,executableIdentity:{build:releaseIdentity,packaged:packageIdentity},nativeLaunched:false,nativeInspected:false});
 releaseEntriesVerified+=packaged.releaseFiles.length;
}
const analyzer=await stageEvidence('Preview','analyzer');stages.unshift(analyzer);
stages.unshift(await stageEvidence('Preview','pubget'));
stages.push(await stageEvidence('Connected','pubget'));
assert(delivery.verifiedReleaseEntries===releaseEntriesVerified&&delivery.verifiedPackageEntries===inputs.packageFiles.length,'DELIVERY_VERIFIED_ENTRY_COUNT_MISMATCH');
const ownerImagesPath=base+'owner-golden-decision-20261010-r2.json',ownerImages=await json(ownerImagesPath),promotionPath=base+'golden-promotion-result-20261010-r2.json',promotion=await json(promotionPath);
assert(ownerImages.kind==='direct-human-owner-decision'&&ownerImages.images.length===83&&ownerImages.images.every(i=>i.decision==='accept')&&promotion.status==='complete'&&promotion.fullPromotion===true&&promotion.publishedImageCount===83,'EXACT83_OWNER_IMAGE_PROMOTION_REQUIRED');
const criterionPath=base+'owner-criterion-decision-20261010-r2.json',criterion=await json(criterionPath);
assert(criterion.kind==='direct-human-owner-decision'&&criterion.criteria.length===3&&['AC-551','AC-552','AC-553'].every(id=>criterion.criteria.some(c=>c.id===id&&c.decision==='accept-complete-criterion')),'EXACT_THREE_OWNER_CRITERIA_REQUIRED');
assert(builds.length===2&&builds.every(b=>b.sourceFileCount===builds[0].sourceFileCount),'PAIRED_EXACT_SOURCE_COUNTS_REQUIRED');
assert(desktop.fullSuitePassed===true&&desktop.strictOwnerReviewPending===false&&desktop.failedTests===0&&desktop.skippedTests===0,'POSTAPPROVAL_PAIRED_SUITE_REQUIRED');
const latestOwnerImages=await json(desktop.ownerImageDecision.path),latestPromotion=await json(desktop.promotion.path);
assert(latestOwnerImages.kind==='direct-human-owner-decision'&&latestOwnerImages.submittedByOwner===true&&latestOwnerImages.images.length===8&&latestOwnerImages.images.every(i=>i.decision==='accept')&&new Set(latestOwnerImages.images.map(i=>i.approvedPath)).size===8,'EXACT_EIGHT_NEW_DIRECT_OWNER_IMAGE_DECISIONS_REQUIRED');
assert(latestPromotion.status==='complete'&&latestPromotion.fullPromotion===true&&latestPromotion.publishedImageCount===8&&latestPromotion.failure===null&&latestPromotion.cleanupErrors.length===0&&latestPromotion.postVerificationErrors.length===0&&equal(latestPromotion.ownerDecision,desktop.ownerImageDecision),'EXACT_EIGHT_NEW_ACTUAL_PROMOTIONS_REQUIRED');
for(const image of latestOwnerImages.images)assert(await hash(image.approvedPath)===image.candidateSha256,'NEW_APPROVED_IMAGE_BYTES_CHANGED');
const report={observedAt:new Date().toISOString(),revision:'r4',date:'20261010',kind:'paired-ordinary-native-build-adapter',currentSourceMatch:true,sourceFilesPerApp:builds[0].sourceFileCount,
 sourceScope:`Matching postapproval desktop base inputs (${builds[0].sourceFileCount} per app) and exactly three native runner identity overlays per copy`,ordinaryEntrypoint:'lib/main.dart',previewBuilt:true,connectedBuilt:true,
 releaseEntriesVerified,packageEntriesVerified:inputs.packageFiles.length,stages,builds,delivery:deliveryPath,deliveryManifestSha256:await hash(deliveryPath),zip:delivery.zip,zipSha256:delivery.zipSha256,zipBytes:delivery.zipBytes,
 packageInputs:inputsPath,packageInputsSha256:await hash(inputsPath),broaderSuites:{desktopAll:desktop},desktopBaseSourceSuite:desktop,
 ownerImageDecision:{path:ownerImagesPath,sha256:await hash(ownerImagesPath),approvedImages:83},promotion:{path:promotionPath,sha256:await hash(promotionPath)},
 laterOwnerImageDecision:{...desktop.ownerImageDecision,approvedImages:8},laterPromotion:desktop.promotion,exactApprovedImageDelta:desktop.exactApprovedImageDelta,
 ownerCriterionDecision:{path:criterionPath,sha256:await hash(criterionPath),acceptedIds:['AC-551','AC-552','AC-553'],remaining:106,total:109},
 fullDesktopFailures:[],goldenFailures:[],approvedGoldensPromoted:true,approvedGoldensRegeneratedByBuildPreparation:false,
 cashFrames:[],modelFrames:[],authFrames:[],freshCaptureStageExecutedInR4:false,nativeLaunched:false,nativeFramesInspected:0,
 authenticatedNative:false,authenticatedNativeAcceptance:false,nativeKeyboardVerified:false,nativeKeyboardReason:'Root native user-flow execution is separate and pending at this packaging checkpoint; native tooling is available.',
 realMfa:false,actualAccountingPosting:false,actualModelUsage:false,actualWorkerDelivery:false,independentSessionContention:false,targetScaleLoad:false,ownerAccepted:false,
 newMigrationsInstalled:false,formalRuntimeProfileProvisioned:false,acceptanceStoresReadOrCopied:false,
 recorder:'scripts/wave5/record_windows_userflow_20261010_r4.mjs',recorderSha256:await hash('scripts/wave5/record_windows_userflow_20261010_r4.mjs'),
 helper:'scripts/wave5/windows_delivery_inputs_20261010_r4.mjs',helperSha256:await hash('scripts/wave5/windows_delivery_inputs_20261010_r4.mjs'),
 boundary:`Paired ordinary current builds and copied/ZIP bytes only. The fresh ${desktop.passedTests}/0/0 full suite executed in the source-bound postapproval r4 verification tree and was not rerun in the identity copies. Native screenshots and actions, real transactions, MFA, delivery, load and remaining owner acceptance require separate actual evidence.`};
for(const mode of ['Preview','Connected'])await sourceGuard(mode);
await writeFile(path.join(root,output),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
await writeFile(path.join(root,markdown),`# Ordinary Windows paired build evidence — October 10, 2026 r4\n\n[Exact report](${path.basename(output)}) binds two ordinary lib/main.dart builds from ${builds[0].sourceFileCount.toLocaleString('en-US')} unchanged postapproval inputs per app, with exactly three identity overlays each. ${releaseEntriesVerified} release entries and ${inputs.packageFiles.length} total portable entries match their release directories, copied directories and decoded ZIP bytes. Read-only PE resources confirm the unique com.jentra.test products before launch.\n\nThe matching base-source [full desktop suite](${path.basename(desktop.record)}) passed ${desktop.passedTests}/0/0 at ${desktop.finishedAt}, with every frozen test identity verified from the actual log. It ran in its postapproval r4 verification tree; this report does not claim a second full suite in the Windows identity copies. Four SDK files, exact script bytes and each snapshot dependency-resolution file were guarded before and after every packaged SDK stage. Preview scoped analysis is clean.\n\nThe original 83 proposed image bytes retain their direct approval and promotion evidence. A separate [owner decision](${path.basename(desktop.ownerImageDecision.path)}) and [actual promotion](${path.basename(desktop.promotion.path)}) cover exactly eight later image replacements. The owner separately accepted AC-551, AC-552 and AC-553; the other 106 of 109 criteria remain open.\n\nThis report establishes packaging and controlled verification only. Native launch, keyboard and authentication checks, genuine MFA, real accounting posting, actual exports, model and worker delivery, contention, load, profile provisioning and whole-system acceptance require separate evidence. Root records subsequent native actions separately.\n\nPortable ZIP: [${path.basename(delivery.zip)}](<../../../dist/${path.basename(delivery.zip)}>), SHA-256 \`${delivery.zipSha256}\`. Preview has unavailable accounting gateways and Connected uses only the freshly verified public configuration of the existing development project. No acceptance stores or private credentials were copied. Production and real billing remain excluded.\n`,{flag:'wx'});
console.log(JSON.stringify({report:output,sourceFilesPerApp:builds[0].sourceFileCount,releaseEntriesVerified,packageEntriesVerified:inputs.packageFiles.length,fullDesktopBaseTests:desktop.passedTests,nativeLaunched:false}));
