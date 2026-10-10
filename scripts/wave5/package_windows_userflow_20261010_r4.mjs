// NEW r4 variant; preserved predecessor package_windows_userflow_20261010_r3.mjs SHA-256 e4d3351349ae90c2d3e15a2454368f7bddf0918665d8d4a32c4dd2d0b7074638.
// Root may run after both guarded builds complete. Copy/hash/PE inspection only;
// no executable, SDK, Auth, store or live operation is launched here.
import {copyFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {assert,base,root,packageDirectory,packageName,sha,bytes,hash,json,exists,equal,sourceGuard,files,fullDesktop,stageEvidence,executableIdentity} from './windows_delivery_inputs_20261010_r4.mjs';
const options=process.argv.slice(2);let previewAttempt='a1',connectedAttempt='a1';
for(let i=0;i<options.length;i++){
 const option=options[i],value=options[++i];assert(/^[a-z][a-z0-9]{0,8}$/.test(value??''),'BUILD_ATTEMPT_INVALID');
 if(option==='--preview-attempt')previewAttempt=value;else if(option==='--connected-attempt')connectedAttempt=value;else throw Error('PACKAGE_OPTION_INVALID');
}
const outputs=[packageDirectory,...['preview','connected'].map(m=>`${base}windows-test-${m}-package-20261010-r4.json`),base+'windows-test-package-inputs-20261010-r4.json'];
for(const p of outputs)assert(!await exists(p),'NEW_PACKAGE_OUTPUT_REQUIRED_PRESERVE_EXISTING_R4');
const prepared=[];
for(const mode of ['Preview','Connected']){
 const guard=await sourceGuard(mode),source=await json(guard.manifest.path);
 const build=await stageEvidence(mode,'build',mode==='Preview'?previewAttempt:connectedAttempt);
 const desktop=await fullDesktop(source);
 const releaseDirectory=path.join(source.snapshot,'apps/jentra_desktop/build/windows/x64/runner/Release');
 const releaseFiles=await files(releaseDirectory);assert(releaseFiles.some(f=>f.path==='Jentra_OS.exe'),'NATIVE_EXECUTABLE_REQUIRED');
 assert(releaseFiles.every(f=>!/(^|\/)\.env|\.(sqlite(?:3)?|db|key)$/i.test(f.path)),'LOCAL_STORE_OR_PRIVATE_CONFIG_FILE_REFUSED');
 const identity=await executableIdentity(mode,path.join(releaseDirectory,'Jentra_OS.exe'));
 prepared.push({mode,guard,source,build,desktop,releaseDirectory,releaseFiles,identity});
}
const analyzer=await stageEvidence('Preview','analyzer');
await mkdir(packageDirectory);
const manifests=[];
for(const p of prepared){
 const target=path.join(packageDirectory,p.mode);await mkdir(target);
 for(const file of p.releaseFiles){
  const destination=path.join(target,file.path);await mkdir(path.dirname(destination),{recursive:true});await copyFile(path.join(p.releaseDirectory,file.path),destination);
  assert(await hash(destination)===file.sha256,'COPIED_RELEASE_HASH_CHANGED');
 }
 assert(equal(Object.fromEntries((await files(p.releaseDirectory)).map(f=>[f.path,f.sha256])),Object.fromEntries(p.releaseFiles.map(f=>[f.path,f.sha256]))),'RELEASE_FILE_SET_CHANGED_DURING_COPY');
 const packagedIdentity=await executableIdentity(p.mode,path.join(target,'Jentra_OS.exe'));
 const evidence={packagedAt:new Date().toISOString(),mode:p.mode.toLowerCase(),revision:'r4',date:'20261010',entrypoint:'lib/main.dart',controlledEvidence:false,
  projectId:p.source.projectId,sourceManifest:p.guard.manifest.path,sourceManifestSha256:p.guard.manifest.sha256,sourceHashes:p.source.baseSourceHashes,buildSourceHashes:p.source.buildSourceHashes,
  base_source_match:true,current_source_match:true,runnerOverlays:p.source.overlays,packageDirectory:target,releaseDirectory:p.releaseDirectory,executable:path.join(target,'Jentra_OS.exe'),
  releaseFiles:p.releaseFiles,buildEvidence:p.build.record,buildEvidenceSha256:p.build.recordSha256,buildLog:p.build.log,buildLogSha256:p.build.logSha256,toolchainGuard:p.build.toolchainGuard,
  executableIdentity:{build:p.identity,packaged:packagedIdentity},storageIdentity:p.source.stores,publicConfig:p.source.publicConfig,
  fullDesktopEvidence:p.desktop,analysisEvidence:{record:analyzer.record,recordSha256:analyzer.recordSha256,log:analyzer.log,logSha256:analyzer.logSha256,exitCode:0},
  previewData:p.mode==='Preview',publicKeyOnly:p.mode==='Connected',nativeLaunched:false,authenticatedNativeAcceptance:false,nativeKeyboardVerified:false,
  realMfa:false,actualAccountingPosting:false,actualWorkerDelivery:false,independentSessionContention:false,targetScaleLoad:false,ownerAccepted:false,newMigrationsInstalled:false,
  localStoresReadOrCopied:false,formalRuntimeProfileProvisioned:false,
  boundary:'Ordinary public portable test build only. Full2004 executes in the matching base-source warm tree; only native runner identities differ. Compiled identity read is not native launch or native storage-path acceptance.'};
 const output=`${base}windows-test-${p.mode.toLowerCase()}-package-20261010-r4.json`;
 await writeFile(path.join(root,output),JSON.stringify(evidence,null,2)+'\n',{flag:'wx'});
 await writeFile(path.join(target,'release-manifest.json'),JSON.stringify({mode:p.mode.toLowerCase(),storageIdentity:p.source.stores,releaseFiles:p.releaseFiles,executableIdentity:packagedIdentity},null,2)+'\n',{flag:'wx'});
 manifests.push({mode:p.mode.toLowerCase(),path:output,sha256:await hash(output),releaseFiles:p.releaseFiles.length});
}
for(const mode of ['Preview','Connected'])await writeFile(path.join(packageDirectory,`Start ${mode}.cmd`),`@echo off\r\nstart "" "%~dp0${mode}\\Jentra_OS.exe"\r\n`,{flag:'wx'});
const readme=`JENTRA OS — WINDOWS TEST — OCTOBER 10, 2026 r3\n\nExtract the entire ZIP and keep each EXE, DLL and data directory together.\nStart Preview.cmd explores ordinary offline shell/setup examples. Operational accounting gateways are unavailable there; invoices, journals and financial statements cannot be posted/generated in this mode. Preview setup saves are in-memory demonstrations and reset on refresh.\nStart Connected.cmd opens the existing development Supabase project xpdoufauvrbdmxgngetv. The privately owner-created trial account desktop-test-20261009@jentra.invalid is confirmed and had an earlier real sign-in; use only your private password. Its last recorded business memberships are zero. Sign-in does not itself authorize a business workspace or genuine MFA.\n\nTry keyboard navigation, Ctrl+K, arrows, Enter, Escape, light/dark themes, compact/comfortable density and window resizing. Record the actual observed outcome. These instructions do not claim native keyboard or real transaction acceptance.\n\nFresh isolated product directories use com.jentra.test/JentraOS_WindowsTest_20261010-r4_Preview and com.jentra.test/JentraOS_WindowsTest_20261010-r4_Connected under application support/cache. No earlier session, credential or acceptance database was copied. They are separate products on the same Windows account, not a new OS security boundary.\n\nThe 83 proposed golden images were explicitly approved and promoted; the matching base-source full desktop suite passed2004/0/0. The native build copies apply exactly three identity-only overlays. Genuine native/MFA, actual posting/export/model/worker delivery, independent-session contention/load and most owner criteria remain open. Additional71 runtime migrations remain unapproved. This package installs no backend, account, entitlement, worker, schedule or installer. Production and real billing are excluded.\n\nEach app's release-manifest.json records its exact shipped release hashes and compiled identity. No password, MFA seed, model key or Google secret is included. Record mode/page/action, expected versus actual behavior, theme/density/window size, screenshot and exact package identity while keeping private data out of feedback.\n`;
await writeFile(path.join(packageDirectory,'Start Here.txt'),readme,{flag:'wx'});
await writeFile(path.join(packageDirectory,'Accounting test plan.md'),await bytes(base+'end-user-accounting-test-plan-20261010-r2.md'),{flag:'wx'});
await writeFile(path.join(packageDirectory,'Desktop test login.md'),(await bytes(base+'desktop-test-login-20261009.md')).toString('utf8').replaceAll('[creation verification](desktop-test-login-result-20261009.json)','creation verification in the source workspace').replaceAll('[sign-in verification](desktop-test-login-signin-20261009.json)','sign-in verification in the source workspace').replaceAll('[private configuration steps](windows-account-google-setup-20261009.md)','private configuration steps in the source workspace'),{flag:'wx'});
for(const mode of ['Preview','Connected'])await sourceGuard(mode);
const packageFiles=await files(packageDirectory);
await writeFile(path.join(root,base+'windows-test-package-inputs-20261010-r4.json'),JSON.stringify({preparedAt:new Date().toISOString(),packageName,packageDirectory,manifests,packageFiles,ordinaryEntrypoint:'lib/main.dart',compiledRunnerIdentitiesVerified:true,nativeLaunched:false,SDKExecutedByPackager:false,localStoresReadOrCopied:false,packager:'scripts/wave5/package_windows_userflow_20261010_r4.mjs',packagerSha256:await hash('scripts/wave5/package_windows_userflow_20261010_r4.mjs'),inputHelperSha256:await hash('scripts/wave5/windows_delivery_inputs_20261010_r4.mjs')},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({packageDirectory,manifests,packageFiles:packageFiles.length,nativeLaunched:false}));
