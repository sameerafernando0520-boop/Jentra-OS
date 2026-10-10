// Evidence publication only. Default preview is read-only; root owns --write.
// Keep every criterion, direct owner decision and separate runtime gate intact.
import {access,copyFile,lstat,mkdir,open,readFile,realpath,rename,unlink,writeFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {verifyExecution,verifierProvenance} from './accounting_execution_verifier_20261010_r3.mjs';
import {files,stageEvidence,readZipEntries,zipEntryBytes} from './windows_delivery_inputs_20261010_r3.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),base='docs/verification/wave5/';
const publish=process.argv.includes('--write');
if(process.argv.slice(2).some(a=>a!=='--write')||process.argv.slice(2).length>1)throw Error('UNKNOWN_ARGUMENT');
const self='scripts/wave5/update_current_verification_status_20261010_r3_a2_guarded.mjs';
const p={matrix:base+'requirement-matrix-20261008.json',markdown:base+'requirement-matrix-20261008.md',status:'docs/development/wave5-status.md',
  paired:base+'windows-test-verification-20261010-r3.json',pairedMd:base+'windows-test-verification-20261010-r3.md',
  packageInputs:base+'windows-test-package-inputs-20261010-r3.json',delivery:base+'windows-test-delivery-20261010-r3.json',
  native:base+'native-preview-userflows-20261010-r3.json',nativeMd:base+'native-preview-userflows-20261010-r3.md',
  storage:base+'windows-userflow-storage-before-20261010-r3.json',postStorage:base+'windows-userflow-storage-after-20261010-r3.json',
  manifest:base+'golden-review-postapproval-source-20261010-r2.json',run:base+'golden-review-approvedAll-20261010-r2.json',
  accounting:base+'accounting-checks-source-20261010-r2.json',accountingMd:base+'accounting-checks-result-20261010-r2.md',
  domain:base+'accounting-checks-domain-20261010-r2.json',platform:base+'accounting-checks-platform-20261010-r2.json',
  live:base+'complete-live-preflight-20261010-r3-summary.json',liveIndex:base+'complete-live-preflight-20261010-r3-index.json',liveMd:base+'complete-live-preflight-20261010-r3.md',
  priorBefore:base+'postapproval-golden-status-before-20261010-r2-guarded.json',priorAfter:base+'postapproval-golden-status-after-20261010-r2-guarded.json',
  decision:base+'owner-criterion-decision-20261010-r2.json',acceptance:base+'owner-criterion-acceptance-after-20261010-r2-serial.json',
  before:base+'current-verification-status-before-20261010-r3-guarded.json',after:base+'current-verification-status-after-20261010-r3-guarded.json'};
const living=[p.matrix,p.markdown,p.status],acceptedIds=['AC-551','AC-552','AC-553'];
const sha=b=>createHash('sha256').update(b).digest('hex'),eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const must=(condition,message)=>{if(!condition)throw Error(message);};
const parse=b=>JSON.parse(b.toString('utf8').replace(/^\uFEFF/,''));
const mapEq=(a,b)=>eq(Object.fromEntries(Object.entries(a).sort()),Object.fromEntries(Object.entries(b).sort()));
function inside(file){
  must(typeof file==='string'&&!path.isAbsolute(file),'RELATIVE_PATH_REQUIRED');
  const absolute=path.resolve(root,file),rel=path.relative(root,absolute);
  must(rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'PATH_ESCAPES:'+file);return absolute;
}
async function bytes(file){
  const absolute=inside(file),stat=await lstat(absolute),resolved=await realpath(absolute),rel=path.relative(root,resolved);
  must(stat.isFile()&&!stat.isSymbolicLink()&&rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'REGULAR_INPUT_REQUIRED:'+file);
  return readFile(absolute);
}
async function exists(file){try{await lstat(inside(file));return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
const prerequisites=[p.paired,p.pairedMd,p.packageInputs,p.delivery,p.native,p.storage,p.manifest,p.run,p.accounting,p.accountingMd,p.domain,p.platform,p.live,p.liveIndex,p.liveMd];
const missing=[];for(const file of prerequisites)if(!await exists(file))missing.push(file);
if(missing.length){
  console.log(JSON.stringify({readyForPublication:false,missing,outputsWritten:false,SDKJobsExecuted:false,liveOperations:false}));
  if(publish)process.exitCode=1;
}else{
  const nativeProbe=parse(await bytes(p.native));
  if(nativeProbe.status!=='complete'){
    console.log(JSON.stringify({readyForPublication:false,reason:'ACTUAL_NATIVE_PREVIEW_COLLECTION_NOT_COMPLETE',status:nativeProbe.status,outputsWritten:false,SDKJobsExecuted:false}));
    if(publish)process.exitCode=1;
  }else await main();
}

async function main(){
  const original=new Map(await Promise.all(living.map(async file=>[file,await bytes(file)])));
  const expectedLiving=new Map([...original].map(([file,b])=>[file,sha(b)])),bound=new Map();
  async function bind(file,h){
    const b=original.has(file)?original.get(file):await bytes(file),actual=sha(b);
    must((!h||h===actual)&&(!bound.has(file)||bound.get(file).sha256===actual),'BOUND_INPUT_DRIFT:'+file);
    bound.set(file,{path:file,sha256:actual});return b;
  }
  const json=async(file,h)=>parse(await bind(file,h));
  const matrix=parse(original.get(p.matrix)),priorMatrix=structuredClone(matrix);
  must(matrix.requirementCount===109&&matrix.rows?.length===109&&new Set(matrix.rows.map(r=>r.id)).size===109&&matrix.ownerAcceptedCriteria===3&&
    eq(matrix.rows.filter(r=>r.ownerAccepted===true).map(r=>r.id),acceptedIds)&&matrix.rows.filter(r=>r.ownerAccepted===false).length===106,'EXACT_EXISTING_THREE_ACCEPTED_REQUIRED');
  const falseGates=['wholeWaveComplete','actualModelUsage','realMfa','actualWorkerDelivery','authenticatedNativeAcceptance',
    'independentSessionContention','targetScaleLoad','nativeKeyboardVerified','ownerSignoff','newRuntimeInstallationComplete'];
  for(const k of falseGates)must(matrix[k]===false,'SEPARATE_GATE_CHANGED:'+k);
  must(!Object.hasOwn(matrix,'currentR3Verification'),'NEW_R3_AMENDMENT_REQUIRED');
  const [priorBefore,priorAfter,decision,acceptance,manifest,run,paired,inputs,delivery,native,storage,accounting,domain,platform,live,index]=await Promise.all([
    json(p.priorBefore),json(p.priorAfter),json(p.decision),json(p.acceptance),json(p.manifest),json(p.run),json(p.paired),json(p.packageInputs),json(p.delivery),
    json(p.native),json(p.storage),json(p.accounting),json(p.domain),json(p.platform),json(p.live),json(p.liveIndex)]);
  for(const file of [p.pairedMd,p.accountingMd,p.liveMd])await bind(file);
  const nativeMarkdownPresent=await exists(p.nativeMd),postStoragePresent=await exists(p.postStorage);
  if(nativeMarkdownPresent)await bind(p.nativeMd);
  const postStorage=postStoragePresent?await json(p.postStorage):null;
  must(priorAfter.status==='complete'&&priorAfter.fullPublication===true&&priorAfter.publicationError===null&&priorAfter.cleanupErrors.length===0&&
    priorAfter.postVerificationErrors.length===0&&priorAfter.all109RowsUnchanged===true&&priorAfter.criterionAcceptanceUnchanged===true&&
    priorAfter.separateGatesUnchanged===true&&priorAfter.observedOwnerAcceptedCriteria===3&&eq(priorAfter.before,{path:p.priorBefore,sha256:bound.get(p.priorBefore).sha256}),
    'EXACT_PRIOR_STATUS_PUBLICATION_REQUIRED');
  for(const file of living){
    const observed=priorAfter.observedDocuments.find(d=>d.path===file),old=priorBefore.originalLivingDocuments.find(d=>d.path===file);
    must(observed?.matchesPlanned===true&&observed.sha256===expectedLiving.get(file)&&old&&sha(Buffer.from(old.utf8Base64,'base64'))===old.sha256,'CURRENT_LIVING_CHECKPOINT_CHANGED:'+file);
    const recovery=priorAfter.retainedRecoveries.find(r=>r.originalPath===file);
    must(recovery?.matchesOriginal===true&&recovery.matchesClaimed===true&&recovery.published===true&&recovery.sha256===old.sha256,'PRIOR_RECOVERY_CHANGED:'+file);
    await bind(recovery.path,old.sha256);
  }
  const priorOriginalMatrix=parse(Buffer.from(priorBefore.originalLivingDocuments.find(d=>d.path===p.matrix).utf8Base64,'base64'));
  must(eq(matrix.rows,priorOriginalMatrix.rows)&&eq(matrix.ownerCriterionAcceptance,priorOriginalMatrix.ownerCriterionAcceptance),'ALL109_ROWS_AND_DIRECT_ACCEPTANCE_MUST_REMAIN_EXACT');
  must(decision.kind==='direct-human-owner-decision'&&decision.authorizationKind==='direct-human-message'&&decision.sourceMessage?.role==='user'&&
    decision.submittedByOwner===true&&typeof decision.messageVerbatim==='string'&&decision.messageVerbatim.trim()&&decision.messageSha256===sha(Buffer.from(decision.messageVerbatim))&&
    eq(decision.criteria.map(c=>c.id),acceptedIds)&&decision.criteria.every(c=>c.decision==='accept-complete-criterion')&&
    eq(matrix.ownerCriterionAcceptance.criterionIds,acceptedIds)&&eq(matrix.ownerCriterionAcceptance.ownerDecision,bound.get(p.decision))&&
    acceptance.status==='complete'&&acceptance.fullPublication===true&&acceptance.observedOwnerAcceptedCriteria===3&&
    eq(acceptance.observedOwnerAcceptedIds,acceptedIds),'EXISTING_OWNER_DECISION_CHANGED');
  for(const row of matrix.rows){
    must(typeof row.specification==='string'&&Number.isInteger(row.specificationLine)&&typeof row.statement==='string'&&Array.isArray(row.evidence),'CRITERION_PROJECTION_INVALID:'+row.id);
    await bind(row.specification);
  }
  const scope=['apps/jentra_desktop','packages/jentra_design_system','packages/jentra_domain','packages/jentra_platform'];
  const selected=h=>Object.fromEntries(Object.entries(h).filter(([file])=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(file)||
    scope.some(s=>file.startsWith(s+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(file)));
  must(manifest.kind==='postapproval_desktop1068_source_manifest'&&manifest.selectedSources===1068&&Object.keys(manifest.sourceHashes).length===1068&&
    manifest.sourceInputsSha256===sha(Buffer.from(JSON.stringify(manifest.sourceHashes)))&&manifest.currentSourceMatchesApprovedInputs===true&&manifest.warmSourceMatchesApprovedInputs===true&&
    path.resolve(manifest.snapshot)===path.join(root,'build/w5goldens20261010/r1'),'EXACT_POSTAPPROVAL1068_REQUIRED');
  must(run.stage==='approvedAll'&&run.status==='complete'&&run.fullSuitePassed===true&&run.exitCode===0&&run.integrityError===null&&run.spawnError===null&&
    eq(run.counts,{passed:2004,failed:0,skipped:0})&&eq(run.sourceManifest,bound.get(p.manifest))&&
    eq(run.actualTestIdentities,manifest.expectedTestIdentities)&&manifest.expectedTestIdentities.length===2004&&new Set(manifest.expectedTestIdentities).size===2004,
    'ACTUAL_MATCHING_BASE_FULL2004_REQUIRED');
  const fullLog=await bind(run.log,run.logSha256),desktopFiles=[...new Set(manifest.expectedTestIdentities.map(id=>'test/'+id.slice(0,id.indexOf(': '))))].sort();
  const actualFull=verifyExecution(fullLog,run.workingDirectory,desktopFiles,run.exitCode);
  must(eq(actualFull.identities.map(id=>id.slice(5)),manifest.expectedTestIdentities),'EXACT_FULL2004_LOG_IDENTITIES_REQUIRED');
  for(const b of manifest.bindings)await bind(b.path,b.sha256);
  must(accounting.kind==='accounting_calculation_gateway_source_manifest'&&accounting.selectedSources===1068&&
    mapEq(accounting.sourceHashes,manifest.sourceHashes)&&accounting.sourceInputsSha256===manifest.sourceInputsSha256,'EXACT_CURRENT_ACCOUNTING_SOURCE_REQUIRED');
  const accountingKeys=['snapshot','selectedSources','sourceHashes','sourceInputsSha256','sourceManifest','approvedDesktopRun','currentSourceMatchesFrozenInputs',
    'warmSourceMatchesFrozenInputs','stages','toolchain','resolution','bindings','fixturePolicy','boundary'];
  for(const [stage,report,count,filesCount] of [['domain',domain,122,16],['platform',platform,406,22]]){
    const spec=accounting.stages.find(s=>s.stage===stage);
    must(spec?.files.length===filesCount&&report.stage===stage&&report.status==='complete'&&report.stagePassed===true&&report.exitCode===0&&
      report.spawnError===null&&report.integrityError===null&&eq(report.counts,{passed:count,failed:0,skipped:0})&&eq(report.sourceManifest,bound.get(p.accounting)),
      'ACTUAL_ACCOUNTING_STAGE_NOT_GREEN:'+stage);
    const actual=verifyExecution(await bind(report.log,report.logSha256),report.workingDirectory,spec.files,report.exitCode);
    must(actual.identities.length===count&&eq(actual.identities,report.actualTestIdentities)&&eq(actual.actualFiles,report.actualExecutedFiles)&&
      eq(actual.perFileCounts,report.perFileCounts),'ACCOUNTING_ACTUAL_IDENTITIES_CHANGED:'+stage);
    for(const k of accountingKeys)must(eq(report.inputAuditBefore[k],accounting[k])&&eq(report.inputAuditAfter[k],accounting[k]),'ACCOUNTING_SOURCE_AUDIT_CHANGED:'+stage+':'+k);
  }
  for(const b of accounting.bindings)await bind(b.path,b.sha256);
  must(paired.kind==='paired-ordinary-native-build-adapter'&&paired.revision==='r3'&&paired.currentSourceMatch===true&&paired.sourceFilesPerApp===1068&&
    paired.previewBuilt===true&&paired.connectedBuilt===true&&paired.ordinaryEntrypoint==='lib/main.dart'&&paired.builds.length===2&&
    paired.desktopBaseSourceSuite.record===p.run&&paired.desktopBaseSourceSuite.recordSha256===bound.get(p.run).sha256&&
    paired.desktopBaseSourceSuite.passedTests===2004&&paired.desktopBaseSourceSuite.rerunInIdentityOverlayTree===false,'EXACT_PAIRED_ORDINARY_R3_REQUIRED');
  for(const k of ['nativeLaunched','authenticatedNative','authenticatedNativeAcceptance','nativeKeyboardVerified','realMfa','actualAccountingPosting',
    'actualModelUsage','actualWorkerDelivery','independentSessionContention','targetScaleLoad','ownerAccepted','newMigrationsInstalled','formalRuntimeProfileProvisioned','acceptanceStoresReadOrCopied'])
    must(paired[k]===false,'PAIRED_CHECKPOINT_GATE_CHANGED:'+k);
  must(inputs.packageName==='Jentra OS Windows Test 20261010 r3'&&inputs.packageDirectory===path.join(root,'dist',inputs.packageName)&&
    inputs.compiledRunnerIdentitiesVerified===true&&inputs.nativeLaunched===false&&inputs.localStoresReadOrCopied===false&&
    paired.packageInputs===p.packageInputs&&paired.packageInputsSha256===bound.get(p.packageInputs).sha256&&
    paired.delivery===p.delivery&&paired.deliveryManifestSha256===bound.get(p.delivery).sha256,'EXACT_DELIVERY_INPUT_BINDINGS_REQUIRED');
  const packageFiles=await files(inputs.packageDirectory);
  must(inputs.packageFiles.length===new Set(inputs.packageFiles.map(f=>f.path)).size&&eq(inputs.packageFiles,packageFiles)&&
    paired.packageEntriesVerified===packageFiles.length&&delivery.verifiedPackageEntries===packageFiles.length&&delivery.packageInputs===p.packageInputs&&
    delivery.packageInputsSha256===bound.get(p.packageInputs).sha256&&delivery.zip===paired.zip&&delivery.zipSha256===paired.zipSha256&&
    delivery.zipBytes===paired.zipBytes&&delivery.nativeLaunched===false,'EXACT_PORTABLE_PACKAGE_REQUIRED');
  const zipPath=path.relative(root,delivery.zip).split(path.sep).join('/'),zip=await bind(zipPath,delivery.zipSha256),zipEntries=readZipEntries(zip);
  must(zip.length===delivery.zipBytes&&[...zipEntries.keys()].filter(n=>!n.endsWith('/')).length===packageFiles.length,'EXACT_ZIP_COUNTS_REQUIRED');
  for(const file of packageFiles){
    await bind(path.relative(root,path.join(inputs.packageDirectory,file.path)).split(path.sep).join('/'),file.sha256);
    const entry=zipEntries.get(inputs.packageName+'/'+file.path);
    must(entry&&sha(zipEntryBytes(zip,entry,file.bytes))===file.sha256,'ZIP_DECODED_ENTRY_CHANGED:'+file.path);
  }
  const r3Sources=[];let releaseCount=0;
  for(const mode of ['preview','connected']){
    const build=paired.builds.find(b=>b.mode===mode),pin=inputs.manifests.find(b=>b.mode===mode);
    must(build&&pin&&build.packageManifest===pin.path&&build.packageManifestSha256===pin.sha256,'EXACT_PAIR_MODE_REQUIRED:'+mode);
    const packaged=await json(pin.path,pin.sha256),source=await json(build.sourceManifest,build.sourceManifestSha256);
    must(source.sourceFileCount===1068&&mapEq(source.baseSourceHashes,manifest.sourceHashes)&&Object.keys(source.buildSourceHashes).length===1068&&
      source.overlays.length===3&&source.controlledEvidence===false&&source.revision==='r3'&&source.mode.toLowerCase()===mode&&
      source.approvedSourceInput.path===p.manifest&&source.approvedSourceInput.sha256===bound.get(p.manifest).sha256&&
      path.resolve(source.snapshot)===path.join(root,'build/w5win10r3',mode)&&
      packaged.sourceManifest===build.sourceManifest&&packaged.sourceManifestSha256===build.sourceManifestSha256&&
      packaged.current_source_match===true&&packaged.base_source_match===true&&mapEq(packaged.sourceHashes,manifest.sourceHashes)&&
      mapEq(packaged.buildSourceHashes,source.buildSourceHashes)&&packaged.entrypoint==='lib/main.dart','PAIRED_SOURCE_MANIFEST_CHANGED:'+mode);
    const differences=Object.keys(source.buildSourceHashes).filter(f=>source.buildSourceHashes[f]!==source.baseSourceHashes[f]);
    must(differences.length===3&&eq(differences.sort(),source.overlays.map(o=>o.path).sort()),'ONLY_THREE_RUNNER_OVERLAYS_REQUIRED:'+mode);
    const titleMode=mode==='preview'?'Preview':'Connected',product='JentraOS_WindowsTest_20261010-r3_'+titleMode;
    for(const identity of [packaged.executableIdentity.build,packaged.executableIdentity.packaged,build.executableIdentity.build,build.executableIdentity.packaged])
      must(identity.CompanyName==='com.jentra.test'&&identity.ProductName===product&&identity.OriginalFilename==='Jentra_OS.exe'&&identity.nativeLaunched===false,'EXACT_COMPILED_PRODUCT_REQUIRED:'+mode);
    const release=await files(packaged.releaseDirectory),copied=(await files(packaged.packageDirectory)).filter(f=>f.path!=='release-manifest.json');
    must(eq(release,packaged.releaseFiles)&&eq(copied,packaged.releaseFiles)&&build.releaseFiles===release.length,'RELEASE_FILE_SET_CHANGED:'+mode);
    for(const file of release)await bind(path.relative(root,path.join(packaged.releaseDirectory,file.path)).split(path.sep).join('/'),file.sha256);
    const buildRecord=await json(packaged.buildEvidence,packaged.buildEvidenceSha256);
    const actual=await stageEvidence(titleMode,'build',buildRecord.attempt);
    must(actual.record===packaged.buildEvidence&&actual.recordSha256===packaged.buildEvidenceSha256,'CURRENT_EXACT_BUILD_EVIDENCE_REQUIRED:'+mode);
    for(const b of [{path:actual.record,sha256:actual.recordSha256},{path:actual.log,sha256:actual.logSha256},actual.toolchainGuard,{path:actual.sdkExitRecord,sha256:actual.sdkExitRecordSha256}])
      await bind(b.path,b.sha256);
    for(const observation of [actual.toolchainGuard.before,actual.toolchainGuard.after]){
      for(const [file,h] of Object.entries(observation.scripts))await bind(file,h);
      for(const resolved of observation.resolution)await bind(resolved.path,resolved.sha256);
    }
    r3Sources.push(source);releaseCount+=release.length;
  }
  must(releaseCount===paired.releaseEntriesVerified&&releaseCount===delivery.verifiedReleaseEntries,'EXACT_RELEASE_COUNTS_REQUIRED');
  const analyzer=await stageEvidence('Preview','analyzer','a1');await bind(analyzer.record,analyzer.recordSha256);await bind(analyzer.log,analyzer.logSha256);
  for(const file of [inputs.packager,'scripts/wave5/windows_delivery_inputs_20261010_r3.mjs',paired.recorder])await bind(file);
  must(paired.recorderSha256===bound.get(paired.recorder).sha256&&paired.helperSha256===bound.get(paired.helper).sha256&&
    inputs.packagerSha256===bound.get(inputs.packager).sha256&&inputs.inputHelperSha256===bound.get(paired.helper).sha256,'DELIVERY_GENERATOR_DRIFT');
  must(storage.revision==='r3'&&storage.allExpectedPathsAbsent===true&&storage.pathContentsRead===false&&storage.defaultAcceptanceStoresRead===false&&
    storage.localStoresCopied===false&&storage.OSUserCreated===false&&storage.nativeLaunched===false&&storage.paths.length===4&&storage.paths.every(s=>s.exists===false),'EXACT_PRELAUNCH_ABSENCE_REQUIRED');
  const nativePackage=inputs.manifests.find(m=>m.mode==='preview');
  must(native.kind==='actual-native-preview-userflow-observations'&&native.status==='complete'&&native.revision==='r3'&&native.mode==='Preview'&&
    native.nativeLaunched===true&&eq(native.package,{path:nativePackage.path,sha256:nativePackage.sha256})&&eq(native.prelaunchPathObservation,bound.get(p.storage))&&
    Date.parse(native.startedAt)>=Date.parse(storage.observedAt)&&Date.parse(native.finishedAt)>=Date.parse(native.startedAt),'COMPLETE_ACTUAL_PREVIEW_OBSERVATIONS_REQUIRED');
  for(const k of ['authenticatedNative','fullNativeKeyboardGate','accountingTransactionsPosted','authoritativeReportsGenerated','actualDelivery','realMfa',
    'actualModelUsage','independentSessionContention','targetScaleLoad','ownerAcceptanceChanged'])must(native[k]===false,'NATIVE_PREVIEW_BOUNDARY_CHANGED:'+k);
  await bind(native.sourceManifest.path,native.sourceManifest.sha256);await bind(native.recorder.path,native.recorder.sha256);
  const preview=await json(nativePackage.path,nativePackage.sha256);
  must(native.executable===preview.executable&&native.executableSha256===preview.executableIdentity.packaged.sha256&&
    native.sourceManifest.path===preview.sourceManifest&&native.sourceManifest.sha256===preview.sourceManifestSha256,'EXACT_OBSERVED_PREVIEW_EXECUTABLE_REQUIRED');
  await bind(path.relative(root,native.executable).split(path.sep).join('/'),native.executableSha256);
  const normalized=s=>s.replace(/^process:/i,'').replaceAll('\\','/').toLowerCase();
  must(Array.isArray(native.observedWindows)&&native.observedWindows.length>0&&native.observedWindows.every(w=>Number.isInteger(w.id)&&
    normalized(w.app)===normalized(native.executable)&&w.title==='Jentra OS - 20261010 r3 Preview test'),'EXACT_NATIVE_WINDOWS_REQUIRED');
  must(native.observations?.length>0&&new Set(native.observations.map(o=>o.id)).size===native.observations.length,'UNIQUE_ACTUAL_NATIVE_CASES_REQUIRED');
  let screenshotCount=0;
  for(const o of native.observations){
    must(/^[A-Z][A-Z0-9_-]{1,49}$/.test(o.id)&&['pass','fail','blocked','observed'].includes(o.result)&&
      ['action','expected','observed'].every(k=>typeof o[k]==='string'&&o[k].trim())&&native.observedWindows.some(w=>w.id===o.window?.id&&w.app===o.window.app&&
        Date.parse(w.boundAt)<=Date.parse(o.observedAt))&&
      o.window.title==='Jentra OS - 20261010 r3 Preview test'&&Date.parse(o.observedAt)>=Date.parse(native.startedAt)&&
      Date.parse(o.observedAt)<=Date.parse(native.finishedAt)&&o.screenshots?.length>0,'EXACT_ACTUAL_NATIVE_CASE_REQUIRED:'+o.id);
    for(const image of o.screenshots){
      must(new RegExp('^docs/verification/wave5/native-preview-20261010-r3/'+o.id+'-\\d+\\.(?:png|jpg)$').test(image.path),'EXACT_NATIVE_SCREENSHOT_PATH_REQUIRED');
      const raw=await bind(image.path,image.sha256);must(raw.length===image.bytes&&raw.length>24,'ACTUAL_NATIVE_SCREENSHOT_BYTES_REQUIRED');
      if(image.path.endsWith('.png'))must(raw.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex'))&&raw.readUInt32BE(16)>0&&raw.readUInt32BE(20)>0,'NATIVE_PNG_HEADER_INVALID');
      else must(raw[0]===0xff&&raw[1]===0xd8&&raw[raw.length-2]===0xff&&raw[raw.length-1]===0xd9,'NATIVE_JPEG_HEADER_INVALID');
      screenshotCount++;
    }
  }
  const nativeCounts=Object.fromEntries(['pass','fail','blocked','observed'].map(result=>[result,native.observations.filter(o=>o.result===result).length]));
  must(eq(native.counts,nativeCounts)&&native.observations.length===14&&eq(nativeCounts,{pass:10,fail:2,blocked:2,observed:0}),'ACTUAL_NATIVE_CASE_COUNTS_CHANGED');
  const expectedNativeCases=['P01_STARTUP','K01_INITIAL_CTRL_K','K02_ESCAPE','K03_DIRECT_LETTER','P02_FINANCE_BLOCKED','P03_SETUP_LIST',
    'P04_REQUIRED_VALIDATION','K04_FORM_TAB','P05_DARK_THEME','P06_DENSITY','P07_THEME_RESTART','P08_PROCUREMENT_BLOCKED','P09_MAXIMIZED','K05_CTRL_K_RECHECK'];
  must(eq(native.observations.map(o=>o.id),expectedNativeCases)&&
    eq(native.observations.filter(o=>o.result==='fail').map(o=>o.id),['K01_INITIAL_CTRL_K','K05_CTRL_K_RECHECK'])&&
    eq(native.observations.filter(o=>o.result==='blocked').map(o=>o.id),['P02_FINANCE_BLOCKED','P08_PROCUREMENT_BLOCKED']),
    'EXACT_RECORDED_PREVIEW_CASES_AND_FAILURES_REQUIRED');
  if(postStorage){
    must(postStorage.kind==='exact-product-postlaunch-path-existence'&&postStorage.revision==='r3'&&postStorage.paths.length===4&&
      postStorage.pathContentsRead===false&&postStorage.defaultAcceptanceStoresRead===false&&postStorage.localStoresCopied===false&&
      postStorage.OSUserCreated===false&&postStorage.authenticatedNative===false&&postStorage.formalRuntimeProfileProvisioned===false&&
      Date.parse(postStorage.observedAt)>=Date.parse(native.finishedAt),'EXACT_POSTLAUNCH_METADATA_BOUNDARY_REQUIRED');
    for(const before of storage.paths){
      const after=postStorage.paths.filter(s=>s.mode===before.mode&&s.kind===before.kind&&s.expectedPath===before.expectedPath);
      must(after.length===1&&after[0].beforeExists===false&&after[0].afterExists===(before.mode==='Preview'&&before.kind==='applicationSupport'),
        'EXACT_NEW_PRODUCT_POSTLAUNCH_PATH_REQUIRED');
    }
  }
  must(index.kind==='read_only_live_preflight_artifact_index'&&index.projectId==='xpdoufauvrbdmxgngetv'&&
    index.summary.path===p.live&&index.summary.sha256===bound.get(p.live).sha256&&index.report.path===p.liveMd&&index.report.sha256===bound.get(p.liveMd).sha256,
    'EXACT_R3_PREFLIGHT_INDEX_REQUIRED');
  for(const b of index.immutableInputs)await bind(b.path,b.sha256);
  must(live.projectId==='xpdoufauvrbdmxgngetv'&&live.migrationCount===43&&live.apiFunctions===107&&live.checkedProviders===120&&
    live.unchangedProvidersSinceR2===120&&live.wave5Tables.length===15&&live.wave5Tables.every(t=>t.rlsEnabled&&t.rlsForced)&&
    Object.keys(live.collisions).length===14&&Object.values(live.collisions).every(n=>n===0)&&live.readOnly===true&&
    live.fullRuntimePreflightComplete===false&&live.currentRuntimeApprovalReady===false&&live.runtimeOwnerApproved===false&&
    live.originalSixLedger.migrationLedgerListRereadInR3===false&&live.edgeInventory.actualFunctionSourceBodyReread===false,'READ_ONLY_R3_PREFLIGHT_BOUNDARY_CHANGED');
  await bind(self);await bind('scripts/wave5/cash_ui_evidence.mjs');
  for(const b of verifierProvenance)await bind(b.path,b.sha256);
  await bind('scripts/wave5/accounting_execution_verifier_20261010_r3.mjs');
  await bind('scripts/wave5/update_current_verification_status_20261010_r3_guarded.mjs','96f588f854cc295d9d5ff592ba2619a7d819ec8d2c9780f74327598e42682525');
  const now=new Date().toISOString(),evidence={recordedAt:now,pairedNativeBuild:bound.get(p.paired),pairedReport:bound.get(p.pairedMd),delivery:bound.get(p.delivery),
    zip:{path:zipPath,sha256:delivery.zipSha256,bytes:delivery.zipBytes},sourceManifest:bound.get(p.manifest),sourceFileCount:1068,runnerIdentityOverlaysPerApp:3,
    previewAndConnectedOrdinaryBuilds:true,fullDesktopMatchingBase:{record:bound.get(p.run),passed:2004,failed:0,skipped:0,rerunInR3IdentityTrees:false},
    accounting:{report:bound.get(p.accountingMd),sourceManifest:bound.get(p.accounting),domain:bound.get(p.domain),platform:bound.get(p.platform),passed:528,failed:0,skipped:0,
      exactFiles:38,scope:'Controlled calculations and injected gateways/stores only; no user transaction.'},
    actualNativePreview:{record:bound.get(p.native),report:nativeMarkdownPresent?bound.get(p.nativeMd):null,counts:nativeCounts,screenshots:screenshotCount,
      uniqueScreenshotHashes:new Set(native.observations.flatMap(o=>o.screenshots.map(s=>s.sha256))).size,
      observedCaseIds:native.observations.map(o=>o.id),failedCaseIds:native.observations.filter(o=>o.result==='fail').map(o=>o.id),
      blockedCaseIds:native.observations.filter(o=>o.result==='blocked').map(o=>o.id),
      exactNewExecutableAndBoundWindows:true,prelaunchPathObservation:bound.get(p.storage),postlaunchPathObservation:postStoragePresent?bound.get(p.postStorage):null,
      actualAccountingTransactions:false,
      scope:'Ordinary offline Preview observations only. Authenticated native keyboard and native transaction acceptance remain open.'},
    readOnlyLivePreflight:{index:bound.get(p.liveIndex),summary:bound.get(p.live),report:bound.get(p.liveMd),observedAt:live.observedAt,
      migrations:43,apiFunctions:107,unchangedProviders:120,forcedRlsTables:15,zeroCollisionCounters:14,fullRuntimePreflightComplete:false,runtimeOwnerApproved:false},
    ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,all109RowsAndExistingAcceptanceUnchanged:true,authenticatedNativeAcceptance:false,nativeKeyboardVerified:false,
    realMfa:false,actualDelivery:false,actualModelUsage:false,independentSessionContention:false,targetScaleLoad:false,newRuntimeInstallationComplete:false,ownerSignoff:false,
    boundary:'Fresh bounded verification evidence only. Earlier records, including the predecision0/109 packet, remain historical. No new owner decision, installation, private operation, production or real billing.'};
  matrix.updatedAt=now;matrix.currentR3Verification=evidence;
  const projection=j=>Object.fromEntries(Object.entries(j).filter(([k])=>!['updatedAt','currentR3Verification'].includes(k)));
  must(eq(projection(matrix),projection(priorMatrix))&&eq(matrix.rows,priorMatrix.rows)&&eq(matrix.ownerCriterionAcceptance,priorMatrix.ownerCriterionAcceptance),'ONLY_NEW_METADATA_MAY_CHANGE');
  const link=(from,label,to)=>`[${label}](<${path.relative(path.dirname(from),to).split(path.sep).join('/')}>)`;
  function amended(file){
    const text=original.get(file).toString('utf8');must(!text.includes('## Current r3 verification amendment — October 10, 2026'),'DUPLICATE_R3_AMENDMENT');
    return text.replace(/\s*$/,'')+'\n\n## Current r3 verification amendment — October 10, 2026\n\n'+
      'The current paired ordinary Preview and Connected builds are source-bound to the same 1,068 approved base inputs, with exactly three native identity overlays each. '+
      link(file,'Paired build/package evidence',p.paired)+' and '+link(file,'the exact portable ZIP',zipPath)+' bind both release copies and decoded archive entries. '+
      'The separately executed matching base-source desktop suite passed 2,004/0/0; it was not rerun in the identity-overlay trees.\n\n'+
      link(file,'Fresh accounting checks',p.accountingMd)+' passed 528/0/0 across 38 existing files using controlled calculations, injected gateways and test-owned stores. '+
      'Actual native user transactions and authoritative report generation remain pending.\n\n'+
      link(file,'Actual offline Preview observations',nativeMarkdownPresent?p.nativeMd:p.native)+` record ${nativeCounts.pass} pass, ${nativeCounts.fail} fail, ${nativeCounts.blocked} blocked and ${nativeCounts.observed} observed cases, with ${screenshotCount} captured screenshots of the exact new package/window identities. `+
      'Both tested Ctrl+K cases failed to open the palette; Finance and Procurement accounting scenarios were blocked. These outcomes remain unresolved, with the input-tool versus application cause unconfirmed. '+
      'These case outcomes do not establish authenticated native keyboard, login, MFA or accounting acceptance. Operational accounting gateways are unavailable in Preview.\n\n'+
      (postStoragePresent?link(file,'Postlaunch directory metadata',p.postStorage)+' records only the new Preview Roaming/application-support directory as present; the other three exact product paths remain absent. No contents, credentials, sessions or existing acceptance stores were inspected.\n\n':'')+
      link(file,'Fresh read-only Supabase preflight',p.liveMd)+` observed 43 migrations/107 API functions at ${live.observedAt}; all 120 checked provider signatures/definition hashes and 15 forced/enabled RLS flags match the prior observation, and all 14 exact proposed-resource collision counters are zero. `+
      'The fresh Edge list contains the same two People deployments; Edge bodies and the six-item ledger list were not reread in this observation. Runtime approval and the additional 71-migration installation remain open.\n\n'+
      'Owner acceptance remains exactly 3/109 (AC-551, AC-552, AC-553); the other 106 criteria and every existing row/evidence/specification mapping are unchanged. '+
      'Native authenticated acceptance, full native keyboard, genuine MFA, actual export/model/worker delivery, contention, target-scale load and whole-system signoff remain false. '+
      'Earlier checkpoint prose and the 0/109 predecision review packet are historical. '+link(file,'Immutable publication checkpoint',p.before)+' and '+link(file,'actual publication result',p.after)+
      ' retain the original documents and actual partial/complete publication outcome. Production and real billing remain excluded.\n';
  }
  const outputs=new Map([[p.matrix,Buffer.from(JSON.stringify(matrix,null,2)+'\n')],[p.markdown,Buffer.from(amended(p.markdown))],[p.status,Buffer.from(amended(p.status))]]);
  const tableRows=text=>text.split(/\r?\n/).filter(line=>/^\| (?:FR|NFR|AC|EC)-\d+ \|/.test(line));
  must(tableRows(outputs.get(p.markdown).toString()).length===109&&eq(tableRows(outputs.get(p.markdown).toString()),tableRows(original.get(p.markdown).toString())),'ALL109_MARKDOWN_CELLS_MUST_REMAIN_EXACT');
  const toolPaths=['C:/src/flutter/bin/cache/flutter.version.json','C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe','C:/src/flutter/bin/cache/flutter_tools.snapshot',
    'C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe'];
  must(eq(manifest.toolchain.tooling.map(t=>t.path),toolPaths),'EXACT_FOUR_TOOL_PINS_REQUIRED');
  async function recheck(claimedFile=null){
    for(const[file,h]of expectedLiving)if(file!==claimedFile)must(sha(await bytes(file))===h,'CONCURRENT_LIVING_CHANGE:'+file);
    for(const b of bound.values())if(!living.includes(b.path))must(sha(await bytes(b.path))===b.sha256,'CONCURRENT_BOUND_CHANGE:'+b.path);
    const [current,warm,...r3]=await Promise.all([sources(root),sources(manifest.snapshot),...r3Sources.map(s=>sources(s.snapshot))]);
    must(mapEq(selected(current),manifest.sourceHashes)&&mapEq(selected(warm),manifest.sourceHashes),'ROOT_OR_WARM1068_DRIFT');
    for(let i=0;i<r3.length;i++)must(mapEq(selected(r3[i]),r3Sources[i].buildSourceHashes),'R3_IDENTITY_OVERLAY_TREE_DRIFT');
    for(const t of manifest.toolchain.tooling)must(sha(await readFile(t.path))===t.sha256,'SDK_TOOL_DRIFT:'+t.path);
    for(const r of accounting.resolution)must(sha(await readFile(path.join(accounting.snapshot,r.path)))===r.sha256,'ACCOUNTING_RESOLUTION_DRIFT');
    return {checkedAt:new Date().toISOString(),sourceManifest:bound.get(p.manifest),selectedSources:1068,sourceInputsSha256:manifest.sourceInputsSha256,
      rootAndWarmMatchApprovedInputs:true,bothR3CopiesMatchDeclaredIdentityOverlays:true,toolchain:manifest.toolchain,paired:bound.get(p.paired),native:bound.get(p.native)};
  }
  const audit=await recheck(),before={preparedAt:now,kind:'current-r3-verification-evidence-before',evidence,
    originalLivingDocuments:[...original].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length,utf8Base64:b.toString('base64')})),
    plannedDocuments:[...outputs].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length})),boundInputs:[...bound.values()],currentSourceAudit:audit,
    all109RowsUnchanged:true,criterionAcceptanceUnchanged:true,separateGatesUnchanged:true,ownerAcceptedCriteria:3,
    boundary:'Evidence-only amendment to three named living documents. No source, PNG, acceptance-store, SDK, live or native action.'};
  if(!publish){console.log(JSON.stringify({readyForPublication:true,write:false,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,passedAccountingTests:528,
    nativePreviewCounts:nativeCounts,nativePreviewScreenshots:screenshotCount,authenticatedNativeAcceptance:false,nativeKeyboardVerified:false,documents:before.plannedDocuments,
    immutableBefore:p.before,immutableAfter:p.after,all109RowsUnchanged:true,criterionAcceptanceUnchanged:true,separateGatesUnchanged:true,
    current1068AndBindingsVerified:true,outputsWritten:false,SDKJobsExecuted:false,liveOperations:false},null,2));return;}
  for(const file of [p.before,p.after]){try{await access(inside(file));throw Error('IMMUTABLE_RESULT_EXISTS:'+file);}catch(e){if(e.code!=='ENOENT')throw e;}}
  await recheck();
  const recoveryDirectory=base+'current-verification-status-recovery-20261010-r3-'+randomUUID();
  const states=[...outputs].map(([file,b])=>({path:file,target:inside(file),bytes:b,originalSha256:sha(original.get(file)),plannedSha256:sha(b),
    recoveryPath:recoveryDirectory+'/'+path.basename(file),recovery:inside(recoveryDirectory+'/'+path.basename(file)),temp:null,tempOwned:false,claimed:false,published:false,claimedSha256:null}));
  before.recoveryDirectory=recoveryDirectory;before.publicationPlans=states.map(({bytes,target,recovery,temp,...s})=>s);
  const beforeBytes=Buffer.from(JSON.stringify(before,null,2)+'\n');await writeFile(inside(p.before),beforeBytes,{flag:'wx'});
  const resultHandle=await open(inside(p.after),'wx');
  await resultHandle.writeFile(JSON.stringify({kind:'current-r3-verification-evidence-pending',before:{path:p.before,sha256:sha(beforeBytes)},fullPublication:false,
    recoveryDirectory,boundary:'Reserved before publication; interruption never establishes complete status publication.'},null,2)+'\n');
  const changed=[],cleanupErrors=[],postVerificationErrors=[];let publicationError=null,finalAudit=null;
  try{
    await mkdir(inside(recoveryDirectory));
    for(const s of states){
      await recheck();s.temp=inside(s.path+'.'+randomUUID()+'.tmp');const temp=await open(s.temp,'wx');s.tempOwned=true;
      try{await temp.writeFile(s.bytes);}finally{await temp.close();}
      await recheck();await rename(s.target,s.recovery);s.claimed=true;s.claimedSha256=sha(await readFile(s.recovery));
      must(s.claimedSha256===s.originalSha256,'CONCURRENT_CLAIMED_DOCUMENT_CHANGE:'+s.path);await recheck(s.path);
      must(sha(await readFile(s.recovery))===s.originalSha256&&sha(await readFile(s.temp))===s.plannedSha256,'OWNED_PUBLICATION_BYTES_CHANGED');
      await copyFile(s.temp,s.target,constants.COPYFILE_EXCL);s.published=true;expectedLiving.set(s.path,s.plannedSha256);changed.push(s.path);await recheck();
    }
  }catch(e){publicationError={message:e.message,code:e.code??null};}
  for(const s of states.filter(s=>s.tempOwned))try{await unlink(s.temp);}catch(e){if(e.code!=='ENOENT')cleanupErrors.push({path:path.relative(root,s.temp),message:e.message,code:e.code??null});}
  const observed=[],recoveries=[];
  for(const file of living)try{const b=await bytes(file);observed.push({path:file,sha256:sha(b),bytes:b.length,matchesPlanned:sha(b)===sha(outputs.get(file))});}catch(e){observed.push({path:file,error:e.message});}
  for(const s of states.filter(s=>s.claimed))try{const h=sha(await bytes(s.recoveryPath));recoveries.push({path:s.recoveryPath,originalPath:s.path,sha256:h,originalSha256:s.originalSha256,
    claimedSha256:s.claimedSha256,matchesOriginal:h===s.originalSha256,matchesClaimed:h===s.claimedSha256,published:s.published});}catch(e){recoveries.push({path:s.recoveryPath,error:e.message});}
  let actualOwnerAccepted=null,actualRowsPreserved=false,actualAcceptancePreserved=false,actualGatesPreserved=false,actualOtherMetadataPreserved=false,actualMarkdownRowsPreserved=false;
  try{
    const actual=parse(await bytes(p.matrix));actualOwnerAccepted=actual.ownerAcceptedCriteria;actualRowsPreserved=eq(actual.rows,priorMatrix.rows);
    actualAcceptancePreserved=eq(actual.ownerCriterionAcceptance,priorMatrix.ownerCriterionAcceptance);actualGatesPreserved=falseGates.every(k=>actual[k]===priorMatrix[k]);
    actualOtherMetadataPreserved=eq(projection(actual),projection(priorMatrix));
    actualMarkdownRowsPreserved=eq(tableRows((await bytes(p.markdown)).toString()),tableRows(original.get(p.markdown).toString()));
  }catch{}
  try{finalAudit=await recheck();}catch(e){postVerificationErrors.push({gate:'finalLivingSourceBoundAndToolAudit',message:e.message});publicationError??={message:e.message,code:e.code??null};}
  if(observed.some(x=>x.matchesPlanned!==true)||actualOwnerAccepted!==3||!actualRowsPreserved||!actualAcceptancePreserved||!actualGatesPreserved||!actualOtherMetadataPreserved||!actualMarkdownRowsPreserved){
    postVerificationErrors.push({gate:'actualDestinationHashesAndProjection',message:'ACTUAL_STATUS_DESTINATION_DRIFT'});publicationError??={message:'ACTUAL_STATUS_DESTINATION_DRIFT',code:null};}
  if(recoveries.length!==states.filter(s=>s.claimed).length||recoveries.some(r=>r.matchesOriginal!==true||r.matchesClaimed!==true)){
    postVerificationErrors.push({gate:'actualRetainedRecoveryHashes',message:'ACTUAL_STATUS_RECOVERY_DRIFT'});publicationError??={message:'ACTUAL_STATUS_RECOVERY_DRIFT',code:null};}
  if(cleanupErrors.length)publicationError??={message:'OWNED_TEMP_CLEANUP_FAILED',code:null};
  const fullPublication=changed.length===3&&publicationError===null&&cleanupErrors.length===0&&postVerificationErrors.length===0&&finalAudit!==null;
  const after={finishedAt:new Date().toISOString(),kind:'current-r3-verification-evidence-result',before:{path:p.before,sha256:sha(beforeBytes)},status:fullPublication?'complete':'failed',
    fullPublication,changedDocuments:changed,remainingDocuments:living.filter(file=>!changed.includes(file)),observedDocuments:observed,retainedRecoveries:recoveries,
    claimedWithoutPublication:states.filter(s=>s.claimed&&!s.published).map(s=>({path:s.path,recoveryPath:s.recoveryPath,claimedSha256:s.claimedSha256})),
    publicationError,cleanupErrors,postVerificationErrors,finalSourceAndToolAudit:finalAudit,validatedInputs:[...bound.values()],recoveryDirectory,evidence,
    observedOwnerAcceptedCriteria:actualOwnerAccepted,all109RowsUnchanged:actualRowsPreserved,criterionAcceptanceUnchanged:actualAcceptancePreserved,separateGatesUnchanged:actualGatesPreserved,
    allExistingMatrixMetadataPreserved:actualOtherMetadataPreserved,all109MarkdownCellsUnchanged:actualMarkdownRowsPreserved,
    sourceEdits:0,approvedBaselineEdits:0,acceptanceStoresTouched:false,SDKJobsExecuted:false,liveOperations:false,nativeActionsPerformed:false,
    boundary:'Only current evidence metadata and an appended amendment in the three named living documents change. Originals, concurrent bytes and actual partial results are retained; no rollback or extra acceptance.'};
  try{await resultHandle.truncate(0);await resultHandle.write(JSON.stringify(after,null,2)+'\n',0,'utf8');}finally{await resultHandle.close();}
  console.log(JSON.stringify({status:after.status,fullPublication,changedDocuments:changed,publicationError,cleanupErrors,postVerificationErrors,
    ownerAcceptedCriteria:actualOwnerAccepted,all109RowsUnchanged:actualRowsPreserved,criterionAcceptanceUnchanged:actualAcceptancePreserved,
    separateGatesUnchanged:actualGatesPreserved,before:p.before,after:p.after,SDKJobsExecuted:false,nativeActionsPerformed:false},null,2));
  if(!fullPublication)process.exitCode=1;
}
