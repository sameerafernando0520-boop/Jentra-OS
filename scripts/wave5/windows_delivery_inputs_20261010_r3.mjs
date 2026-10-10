import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {lstat,readFile,readdir,realpath} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseTestLog,readZipEntries,zipEntryBytes} from './record_continuation_windows.mjs';
export {readZipEntries,zipEntryBytes};
export const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
export const base='docs/verification/wave5/';
export const packageName='Jentra OS Windows Test 20261010 r3';
export const packageDirectory=path.join(root,'dist',packageName);
export const sha=b=>createHash('sha256').update(b).digest('hex');
export const assert=(ok,message)=>{if(!ok)throw Error(message);};
export const relative=p=>path.relative(root,p).split(path.sep).join('/');
export function inside(parent,p){const full=path.resolve(p),rel=path.relative(parent,full);assert(rel&&!rel.startsWith('..')&&!path.isAbsolute(rel),'PATH_ESCAPES_INTENDED_DIRECTORY');return full;}
export const workspacePath=p=>inside(root,path.resolve(root,p));
export async function bytes(p){const full=workspacePath(p);assert(!(await lstat(full)).isSymbolicLink(),'EVIDENCE_LINK_REFUSED');inside(root,await realpath(full));return readFile(full);}
export const hash=async p=>sha(await bytes(p));
export function logText(b){
 if(b.length>=2&&b[0]===0xff&&b[1]===0xfe)return b.subarray(2).toString('utf16le');
 return b.toString('utf8').replace(/^\uFEFF/,'');
}
export const json=async p=>JSON.parse((await bytes(p)).toString('utf8').replace(/^\uFEFF/,''));
export const exists=async p=>{try{await lstat(workspacePath(p));return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
export const equal=(a,b)=>JSON.stringify(Object.fromEntries(Object.entries(a).sort()))===JSON.stringify(Object.fromEntries(Object.entries(b).sort()));
const execute=promisify(execFile);
export async function sourceGuard(mode){
 const args=[path.join(root,'scripts/wave5/prepare_windows_userflow_20261010_r3.mjs'),'verify',mode];if(mode==='Connected')args.push('--config');
 const result=await execute(process.execPath,args,{cwd:root,windowsHide:true,maxBuffer:1024*1024});
 const guard=JSON.parse(result.stdout);assert(guard.currentSourceMatches&&guard.snapshotSourceMatches&&guard.runnerOverlayCount===3,'CURRENT_SOURCE_GUARD_REQUIRED');return guard;
}
export async function files(directory){
 inside(root,await realpath(directory));assert(!(await lstat(directory)).isSymbolicLink(),'OUTPUT_DIRECTORY_LINK_REFUSED');
 const result=[];
 async function walk(current){
  for(const entry of await readdir(current,{withFileTypes:true})){
   assert(!entry.isSymbolicLink(),'OUTPUT_LINK_REFUSED');const p=path.join(current,entry.name);inside(directory,await realpath(p));
   if(entry.isDirectory())await walk(p);else{assert(entry.isFile(),'REGULAR_OUTPUT_FILE_REQUIRED');const b=await readFile(p);result.push({path:path.relative(directory,p).split(path.sep).join('/'),sha256:sha(b),bytes:b.length});}
  }
 }
 await walk(directory);return result.sort((a,b)=>a.path.localeCompare(b.path));
}
export async function fullDesktop(source){
 const recordPath=base+'golden-review-approvedAll-20261010-r2.json',record=await json(recordPath);
 const inputPath=base+'golden-review-postapproval-source-20261010-r2.json',input=await json(inputPath);
 assert(record.status==='complete'&&record.exitCode===0&&record.spawnError===null&&record.integrityError===null&&record.fullSuitePassed===true,'COMPLETE_DESKTOP_SUITE_REQUIRED');
 assert(record.sourceManifest.path===inputPath&&record.sourceManifest.sha256===await hash(inputPath)&&equal(input.sourceHashes,source.baseSourceHashes),'DESKTOP_SUITE_CURRENT_BASE_SOURCE_BINDING_REQUIRED');
 assert(input.currentSourceMatchesApprovedInputs===true&&input.warmSourceMatchesApprovedInputs===true,'APPROVED_INPUT_GUARDS_REQUIRED');
 const log=await bytes(record.log),summary=parseTestLog(logText(log));
 assert(sha(log)===record.logSha256&&summary?.allTestsPassed&&summary.passedTests===record.counts.passed&&summary.failedTests===0&&summary.skippedTests===0&&record.counts.failed===0&&record.counts.skipped===0,'DESKTOP_SUITE_LOG_COUNT_BINDING_REQUIRED');
 for(const pin of input.toolchain.tooling)assert(sha(await readFile(pin.path))===pin.sha256,'APPROVED_TOOLCHAIN_CHANGED');
 return {record:recordPath,recordSha256:await hash(recordPath),sourceManifest:inputPath,sourceManifestSha256:await hash(inputPath),log:record.log,logSha256:sha(log),passedTests:summary.passedTests,failedTests:0,skippedTests:0,finishedAt:record.finishedAt,workingDirectory:record.workingDirectory,toolchain:input.toolchain,
  rerunInIdentityOverlayTree:false,boundary:'Executed in the existing warm postapproval tree. R3 shares the exact base inputs with only three native identity overlays; this is not a new r3 full-suite execution.'};
}
export async function stageEvidence(mode,stage,attempt='a1'){
 assert(['Preview','Connected'].includes(mode)&&/^[a-z][a-z0-9]{0,8}$/.test(attempt),'STAGE_MODE_OR_ATTEMPT_INVALID');
 const recordPath=`${base}windows-test-${mode.toLowerCase()}-${stage}-20261010-r3-${attempt}.json`,record=await json(recordPath);
 const snapshot=path.join(root,'build/w5win10r3',mode.toLowerCase());
 assert(record.mode===mode&&record.stage===stage&&record.revision==='r3'&&record.date==='20261010'&&record.attempt===attempt&&record.exitCode===0&&record.failure===null&&record.SDKExecuted===true,'PASSED_EXACT_SDK_STAGE_REQUIRED');
 assert(path.resolve(record.workingDirectory)===(stage==='build'?path.join(snapshot,'apps/jentra_desktop'):snapshot),'SDK_STAGE_WORKING_DIRECTORY_MISMATCH');
 const manifestPath=`${base}windows-test-${mode.toLowerCase()}-source-20261010-r3.json`;
 for(const guard of [record.sourceGuardBefore,record.sourceGuardAfter])assert(guard?.currentSourceMatches===true&&guard.snapshotSourceMatches===true&&guard.manifest.path===manifestPath&&guard.manifest.sha256===await hash(manifestPath),'BEFORE_AFTER_SOURCE_GUARDS_REQUIRED');
 const log=await bytes(record.log),text=logText(log);assert(sha(log)===record.logSha256,'SDK_LOG_HASH_CHANGED');
 if(stage==='analyzer')assert(text.includes('No issues found!'),'SCOPED_ANALYSIS_SUCCESS_TEXT_REQUIRED');
 if(stage==='build'){
  assert(text.includes('Built build')&&record.args.includes('--target=lib/main.dart')&&record.args.includes('--release')&&record.args.includes('--no-pub'),'ORDINARY_RELEASE_BUILD_REQUIRED');
  assert(record.args.includes(mode==='Connected'?'--dart-define-from-file='+path.join(snapshot,'public-build-config.json'):'--dart-define=JENTRA_ENVIRONMENT=preview'),'EXACT_PUBLIC_BUILD_MODE_REQUIRED');
  const guardPath=`${base}windows-test-${mode.toLowerCase()}-${stage}-toolguard-20261010-r3-${attempt}.json`,guard=await json(guardPath);
  assert(guard.status==='passed'&&guard.exitCode===0&&guard.failure===null&&guard.sdkRecord===recordPath&&guard.sdkRecordSha256===await hash(recordPath)&&guard.resolutionChanged===false,'BUILD_TOOLCHAIN_AND_RESOLUTION_GUARDS_REQUIRED');
  const preparation=await json(base+'windows-userflow-preparation-20261010-r3.json');
  const approved=await json(preparation.approvedInput.path);
  assert(guard.before.preparationSha256===await hash(base+'windows-userflow-preparation-20261010-r3.json')&&guard.after.preparationSha256===guard.before.preparationSha256,'TOOLGUARD_PREPARATION_DRIFT');
  for(const observation of [guard.before,guard.after]){
   assert(observation.approvedInputSha256===await hash(preparation.approvedInput.path),'TOOLGUARD_BASE_INPUT_DRIFT');
   assert(JSON.stringify(observation.tooling)===JSON.stringify(approved.toolchain.tooling),'EXACT_FOUR_APPROVED_TOOLCHAIN_PINS_REQUIRED');
   for(const [p,h] of Object.entries(observation.scripts))assert(await hash(p)===h,'TOOLGUARD_SCRIPT_DRIFT');
   for(const resolved of observation.resolution)assert(resolved.exists===true&&await hash(resolved.path)===resolved.sha256,'PACKAGE_RESOLUTION_DRIFT');
  }
  assert(record.sdkExitRecord===recordPath.replace(/\.json$/,'.sdk-exit.json'),'EXACT_SDK_EXIT_SIDECAR_PATH_REQUIRED');
  const sdkExit=await json(record.sdkExitRecord);
  assert(record.sdkExitCode===0&&sdkExit.sdkExitCode===0&&sdkExit.mode===mode&&sdkExit.stage===stage&&sdkExit.attempt===attempt&&record.sdkExitRecordSha256===await hash(record.sdkExitRecord),'DURABLE_ACTUAL_SDK_EXIT_REQUIRED');
  assert(record.runner==='scripts/wave5/run_windows_userflow_20261010_r3_a2.ps1'&&record.runnerSha256===await hash(record.runner),'CORRECTED_RUNNER_BINDING_REQUIRED');
  assert(guard.before.scripts[record.runner]===record.runnerSha256&&guard.after.scripts[record.runner]===record.runnerSha256,'TOOLGUARD_CORRECTED_RUNNER_SHA_MISMATCH');
  record.toolchainGuard={path:guardPath,sha256:await hash(guardPath),before:guard.before,after:guard.after};
 }
 return {...record,record:recordPath,recordSha256:await hash(recordPath),logSha256:sha(log),SDKGuardClaim:stage==='build'?'Four SDK files and snapshot package resolution guarded before and after this invocation':'Source/config guard only; no retroactive SDK/package-resolution before claim'};
}
export async function executableIdentity(mode,executable){
 const script='scripts/wave5/inspect_windows_runner_identity_20261010_r3.ps1';
 const result=await execute('powershell.exe',['-NoProfile','-NonInteractive','-File',path.join(root,script),'-Mode',mode,'-Executable',executable],{cwd:root,windowsHide:true,maxBuffer:1024*1024});
 const identity=JSON.parse(result.stdout.replace(/^\uFEFF/,''));
 assert(identity.readOnly===true&&identity.nativeLaunched===false&&identity.CompanyName==='com.jentra.test'&&identity.ProductName===`JentraOS_WindowsTest_20261010-r3_${mode}`&&identity.OriginalFilename==='Jentra_OS.exe','COMPILED_ISOLATED_IDENTITY_REQUIRED');
 assert(identity.sha256===await hash(executable),'IDENTITY_READ_EXECUTABLE_HASH_CHANGED');return {...identity,inspector:script,inspectorSha256:await hash(script)};
}
