// NEW r5 successor; preserved r4 predecessor scripts/wave5/windows_delivery_inputs_20261010_r4.mjs SHA-256 db5762bdc0f4f957a5df280b0ccbdca281cb34673b2df63cb5cca8f499150941.
// NEW r5 variant; preserved predecessor windows_delivery_inputs_20261010_r3.mjs SHA-256 42031d11a02a503d8e127c7b6e75793839ef3aef937334d290b347a32cb930ff.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {lstat,readFile,readdir,realpath} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {readZipEntries,zipEntryBytes} from './record_continuation_windows.mjs';
import {auditInputs,auditStage,approvedSourcePath,execution} from './desktop_verification_inputs_20261010_r5.mjs';
export {readZipEntries,zipEntryBytes};
export const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
export const base='docs/verification/wave5/';
export const packageName='Jentra OS Windows Test 20261010 r5';
export const packageDirectory=path.join(root,'dist',packageName);
export const sha=b=>createHash('sha256').update(b).digest('hex');
export const assert=(ok,message)=>{if(!ok)throw Error(message);};
export const relative=p=>path.relative(root,p).split(path.sep).join('/');
export function inside(parent,p){const full=path.resolve(p),rel=path.relative(parent,full);assert(rel&&!rel.startsWith('..')&&!path.isAbsolute(rel),'PATH_ESCAPES_INTENDED_DIRECTORY');return full;}
export const workspacePath=p=>inside(root,path.resolve(root,p));
export async function bytes(p){const full=workspacePath(p);assert(!(await lstat(full)).isSymbolicLink(),'EVIDENCE_LINK_REFUSED');inside(root,await realpath(full));return readFile(full);}
export const hash=async p=>sha(await bytes(p));
export const r4ToolingPredecessors=Object.freeze([
 {
  "path": "scripts/wave5/prepare_windows_userflow_20261010_r4.mjs",
  "sha256": "e90bcbf6c7ed7ac986f8d091a3d44d732dfdd0cbceb0ef8152e3347d93d57d12",
  "bytes": 18706
 },
 {
  "path": "scripts/wave5/run_windows_userflow_20261010_r4.ps1",
  "sha256": "813d9e61c4638cfac5fd8f389e2725df3bc48fb54f27887802401649ca057191",
  "bytes": 10013
 },
 {
  "path": "scripts/wave5/run_windows_userflow_guarded_20261010_r4.mjs",
  "sha256": "47f52599044ac3507e7af7a6c60aa7417ea4b29a737ed9a09b1049b91a713038",
  "bytes": 7179
 },
 {
  "path": "scripts/wave5/windows_delivery_inputs_20261010_r4.mjs",
  "sha256": "db5762bdc0f4f957a5df280b0ccbdca281cb34673b2df63cb5cca8f499150941",
  "bytes": 14290
 },
 {
  "path": "scripts/wave5/package_windows_userflow_20261010_r4.mjs",
  "sha256": "8fd9cb64226a1f9c5b7187c179c96aae0c553c6cfde6602b2f21129636dfea94",
  "bytes": 9544
 },
 {
  "path": "scripts/wave5/inspect_windows_runner_identity_20261010_r4.ps1",
  "sha256": "4ca4f1093434fe09955b2290ab8a6fd87b47b56dceae2e8a6840c1de638233e2",
  "bytes": 2220
 },
 {
  "path": "scripts/wave5/finalize_windows_userflow_20261010_r4.ps1",
  "sha256": "c2a17ad1fcb1e9588bf96dcad7aacd7e9e92dbd6860c084810f67d4414711c1b",
  "bytes": 4404
 },
 {
  "path": "scripts/wave5/record_windows_userflow_20261010_r4.mjs",
  "sha256": "94e0db4cfcc5b843576e3a0b016eaf85a023db00734348c5a272a27f88cbedbc",
  "bytes": 13128
 },
 {
  "path": "scripts/wave5/observe_windows_userflow_storage_20261010_r4.ps1",
  "sha256": "b4bd43c95063a25c2d27e39bd56d3f7a7a9269b2164e602168bd351580dc2e09",
  "bytes": 3092
 },
 {
  "path": "scripts/wave5/observe_windows_userflow_storage_after_20261010_r4.ps1",
  "sha256": "627e51242cc917dde358e4b9b29bcbc11c5a9d146756e1b2f3b4ca5319b645ff",
  "bytes": 2430
 },
 {
  "path": "scripts/wave5/prepare_runtime_worker_adapter_20261010_r4.mjs",
  "sha256": "4ebf1b05bde18ce16199ef3487ffe6783f4dc49193090c3c672f99f8c02cdee4",
  "bytes": 8293
 },
 {
  "path": "scripts/wave5/record_native_preview_observations_20261010_r4.mjs",
  "sha256": "c7b8cbd5d0a22468851f21fdd070060902cc64200090e6f38b1f636f22ae17b0",
  "bytes": 11950
 },
 {
  "path": "scripts/wave5/prepare_current_runtime_review_20261010_r4.mjs",
  "sha256": "621577990b3f9cbc727b4abbf9ccd3159cd07dc72e53a0aaa5d642a1aeebe080",
  "bytes": 62723
 }
].map(record=>Object.freeze(record)));
export async function r4ToolingProvenance(){for(const record of r4ToolingPredecessors){const data=await bytes(record.path);assert(sha(data)===record.sha256&&data.length===record.bytes,'PRESERVED_R4_TOOLING_CHANGED');}return r4ToolingPredecessors;}
export function logText(b){
 if(b.length>=2&&b[0]===0xff&&b[1]===0xfe)return b.subarray(2).toString('utf16le');
 if(b.length>=2&&b[0]===0xfe&&b[1]===0xff){const swapped=Buffer.from(b.subarray(2));assert(swapped.length%2===0,'UTF16BE_LOG_LENGTH_INVALID');for(let i=0;i<swapped.length;i+=2)[swapped[i],swapped[i+1]]=[swapped[i+1],swapped[i]];return swapped.toString('utf16le');}
 return b.toString('utf8').replace(/^\uFEFF/,'');
}
export const json=async p=>JSON.parse((await bytes(p)).toString('utf8').replace(/^\uFEFF/,''));
export const exists=async p=>{try{await lstat(workspacePath(p));return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
export const equal=(a,b)=>JSON.stringify(Object.fromEntries(Object.entries(a).sort()))===JSON.stringify(Object.fromEntries(Object.entries(b).sort()));
const execute=promisify(execFile);
export async function sourceGuard(mode){
 const args=[path.join(root,'scripts/wave5/prepare_windows_userflow_20261010_r5.mjs'),'verify',mode];if(mode==='Connected')args.push('--config');
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
 const historicalToolingPredecessors=await r4ToolingProvenance();
 const inputPath=approvedSourcePath,input=await json(inputPath),inputSha256=await hash(inputPath);
 assert(input.revision==='r5'&&input.postImageApproval===true&&equal(input.sourceHashes,source.baseSourceHashes)&&input.selectedSources===Object.keys(source.baseSourceHashes).length,'POSTAPPROVAL_R5_CURRENT_BASE_SOURCE_REQUIRED');
 const auditBefore=await auditInputs(inputPath);
 const recordPath=base+'desktop-verification-approvedAll-20261010-r5.json',completed=await auditStage('approvedAll'),record=completed.recordData;
 assert(record.stage==='approvedAll'&&record.status==='complete'&&record.SDKExecuted===true&&record.exitCode===0&&record.spawnError===null&&record.integrityError===null&&record.fullSuitePassed===true&&record.sourceManifest.path===inputPath&&record.sourceManifest.sha256===inputSha256,'ACTUAL_POSTAPPROVAL_FULL_R5_SUITE_REQUIRED');
 const stage=input.stages.find(s=>s.stage==='approvedAll'),expected=stage?.expectedTestIdentities??input.expectedTestIdentities;
 assert(Array.isArray(expected)&&expected.length>0&&new Set(expected).size===expected.length,'FROZEN_POSTAPPROVAL_FULL_IDENTITIES_REQUIRED');
 if(input.expectedTestIdentities)assert(JSON.stringify(input.expectedTestIdentities)===JSON.stringify(expected),'FULL_MANIFEST_IDENTITY_SCOPE_MISMATCH');
 assert(record.workingDirectory===input.workingDirectory&&(!stage?.workingDirectory||record.workingDirectory===stage.workingDirectory)&&(!stage?.args||JSON.stringify(record.args)===JSON.stringify(stage.args)),'EXACT_POSTAPPROVAL_EXECUTION_SCOPE_REQUIRED');
 const raw=await bytes(record.log),actual=execution(Buffer.from(logText(raw),'utf8'),record.workingDirectory,expected),summary=actual.parsed;
 assert(sha(raw)===record.logSha256&&summary?.allTestsPassed&&summary.passedTests===expected.length&&summary.passedTests===record.counts.passed&&summary.failedTests===0&&summary.skippedTests===0&&record.counts.failed===0&&record.counts.skipped===0&&JSON.stringify(record.actualTestIdentities)===JSON.stringify(actual.identities),'EXACT_UNIQUE_POSTAPPROVAL_LOG_IDENTITIES_AND_COUNTS_REQUIRED');
 for(const a of [record.inputAuditBefore,record.inputAuditAfter])assert(a?.currentSourceMatchesFrozenInputs===true&&a.warmSourceMatchesFrozenInputs===true&&a.selectedSources===input.selectedSources&&equal(a.sourceHashes,input.sourceHashes)&&JSON.stringify(a.toolchain)===JSON.stringify(input.toolchain)&&JSON.stringify(a.resolution)===JSON.stringify(input.resolution),'POSTAPPROVAL_TEST_PRE_POST_SOURCE_SDK_RESOLUTION_GUARDS_REQUIRED');
 assert(input.exactApprovedImageDelta?.length===8,'EXACT_EIGHT_APPROVED_IMAGE_DELTA_REQUIRED');
 for(const ref of [input.ownerImageDecision,input.promotion,input.original83Approval,input.original83Promotion])assert(ref?.path&&ref.sha256===await hash(ref.path),'EXACT_IMAGE_DECISION_AND_PROMOTION_BINDINGS_REQUIRED');
 const auditAfter=await auditInputs(inputPath);
 assert(auditBefore.sourceManifest.sha256===auditAfter.sourceManifest.sha256&&await hash(inputPath)===inputSha256,'POSTAPPROVAL_INPUT_CHANGED_DURING_FULL_RUN_AUDIT');
 return {record:recordPath,recordSha256:await hash(recordPath),sourceManifest:inputPath,sourceManifestSha256:inputSha256,
  log:record.log,logSha256:sha(raw),passedTests:summary.passedTests,failedTests:0,skippedTests:0,fullSuitePassed:true,
  sdkExitRecord:{path:record.sdkExitRecord,sha256:record.sdkExitRecordSha256},runner:record.runner,inputAuditor:record.inputAuditor,
  actualTestIdentities:actual.identities,testFiles:actual.actualFiles.length,finishedAt:record.finishedAt,workingDirectory:record.workingDirectory,toolchain:input.toolchain,historicalToolingPredecessors,
  original83Approval:{path:input.original83Approval.path,sha256:input.original83Approval.sha256},original83Promotion:{path:input.original83Promotion.path,sha256:input.original83Promotion.sha256},
  ownerImageDecision:{path:input.ownerImageDecision.path,sha256:input.ownerImageDecision.sha256},promotion:{path:input.promotion.path,sha256:input.promotion.sha256},
  exactApprovedImageDelta:input.exactApprovedImageDelta,rerunInIdentityOverlayTree:false,strictOwnerReviewPending:false,
  boundary:'Fresh actual approvedAll execution in the exact postapproval r5 verification tree. Ordinary Windows copies share every base input with exactly three identity overlays; the suite was not rerun in those identity copies. Native user actions and authenticated runtime acceptance remain separate.'};
}
export async function stageEvidence(mode,stage,attempt='a1'){
 assert(['Preview','Connected'].includes(mode)&&['pubget','analyzer','build'].includes(stage)&&/^[a-z][a-z0-9]{0,8}$/.test(attempt),'STAGE_MODE_OR_ATTEMPT_INVALID');
 const recordPath=`${base}windows-test-${mode.toLowerCase()}-${stage}-20261010-r5-${attempt}.json`,record=await json(recordPath);
 const snapshot=path.join(root,'build/w5win10r5',mode.toLowerCase());
 assert(record.mode===mode&&record.stage===stage&&record.revision==='r5'&&record.date==='20261010'&&record.attempt===attempt&&record.status==='complete'&&record.passed===true&&record.exitCode===0&&record.failure===null&&record.SDKExecuted===true,'PASSED_EXACT_SDK_STAGE_REQUIRED');
 assert(path.resolve(record.workingDirectory)===(stage==='build'?path.join(snapshot,'apps/jentra_desktop'):snapshot),'SDK_STAGE_WORKING_DIRECTORY_MISMATCH');
 const manifestPath=`${base}windows-test-${mode.toLowerCase()}-source-20261010-r5.json`;
 for(const guard of [record.sourceGuardBefore,record.sourceGuardAfter])assert(guard?.currentSourceMatches===true&&guard.snapshotSourceMatches===true&&guard.manifest.path===manifestPath&&guard.manifest.sha256===await hash(manifestPath),'BEFORE_AFTER_SOURCE_GUARDS_REQUIRED');
 const log=await bytes(record.log),text=logText(log);assert(sha(log)===record.logSha256,'SDK_LOG_HASH_CHANGED');
 if(stage==='analyzer')assert(text.includes('No issues found!'),'SCOPED_ANALYSIS_SUCCESS_TEXT_REQUIRED');
 if(stage==='build'){
  assert(text.includes('Built build')&&record.args.includes('--target=lib/main.dart')&&record.args.includes('--release')&&record.args.includes('--no-pub'),'ORDINARY_RELEASE_BUILD_REQUIRED');
  assert(record.args.includes(mode==='Connected'?'--dart-define-from-file='+path.join(snapshot,'public-build-config.json'):'--dart-define=JENTRA_ENVIRONMENT=preview'),'EXACT_PUBLIC_BUILD_MODE_REQUIRED');
 }
 {
  const guardPath=`${base}windows-test-${mode.toLowerCase()}-${stage}-toolguard-20261010-r5-${attempt}.json`,guard=await json(guardPath);
  assert(guard.status==='passed'&&guard.exitCode===0&&guard.failure===null&&guard.sdkRecord===recordPath&&guard.sdkRecordSha256===await hash(recordPath)&&
    (stage==='pubget'||guard.resolutionChanged===false),'SDK_TOOLCHAIN_AND_RESOLUTION_GUARDS_REQUIRED');
  const preparation=await json(base+'windows-userflow-preparation-20261010-r5.json');
  const approved=await json(preparation.approvedInput.path);
  assert(approved.postImageApproval===true&&preparation.approvedInput.path===approvedSourcePath&&preparation.approvedInput.sha256===await hash(approvedSourcePath)&&preparation.fullDesktopEvidence.fullSuitePassed===true,'POSTAPPROVAL_STAGE_INPUT_REQUIRED');
  assert(guard.before.preparationSha256===await hash(base+'windows-userflow-preparation-20261010-r5.json')&&guard.after.preparationSha256===guard.before.preparationSha256,'TOOLGUARD_PREPARATION_DRIFT');
  for(const observation of [guard.before,guard.after]){
   assert(observation.approvedInputSha256===await hash(preparation.approvedInput.path),'TOOLGUARD_BASE_INPUT_DRIFT');
   assert(JSON.stringify(observation.tooling)===JSON.stringify(approved.toolchain.tooling),'EXACT_FOUR_APPROVED_TOOLCHAIN_PINS_REQUIRED');
   assert(equal(observation.scripts,preparation.scriptBindings),'TOOLGUARD_EXACT_SCRIPT_SET_REQUIRED');
   for(const [p,h] of Object.entries(observation.scripts))assert(await hash(p)===h,'TOOLGUARD_SCRIPT_DRIFT');
   assert(JSON.stringify(observation.resolution.map(r=>r.path))===JSON.stringify(['.dart_tool/package_config.json','.dart_tool/package_graph.json'].map(p=>relative(path.join(snapshot,p)))),'EXACT_SNAPSHOT_RESOLUTION_PATHS_REQUIRED');
   for(const resolved of observation.resolution){
    if(stage==='pubget'&&observation===guard.before&&resolved.exists===false)assert(resolved.sha256===null,'MISSING_PRE_PUBGET_RESOLUTION_SHOULD_HAVE_NULL_HASH');
    else assert(resolved.exists===true&&(stage==='pubget'&&observation===guard.before||await hash(resolved.path)===resolved.sha256),'PACKAGE_RESOLUTION_DRIFT');
   }
  }
  assert(record.sdkExitRecord===recordPath.replace(/\.json$/,'.sdk-exit.json'),'EXACT_SDK_EXIT_SIDECAR_PATH_REQUIRED');
  const sdkExit=await json(record.sdkExitRecord);
  assert(record.sdkExitCode===0&&sdkExit.sdkExitCode===0&&sdkExit.mode===mode&&sdkExit.stage===stage&&sdkExit.attempt===attempt&&sdkExit.revision==='r5'&&sdkExit.date==='20261010'&&sdkExit.workingDirectory===record.workingDirectory&&sdkExit.executable===record.executable&&JSON.stringify(sdkExit.args)===JSON.stringify(record.args)&&equal(sdkExit.sourceGuardBefore,record.sourceGuardBefore)&&record.sdkExitRecordSha256===await hash(record.sdkExitRecord),'DURABLE_ACTUAL_SDK_EXIT_REQUIRED');
  assert(record.runner==='scripts/wave5/run_windows_userflow_20261010_r5.ps1'&&record.runnerSha256===await hash(record.runner),'CORRECTED_RUNNER_BINDING_REQUIRED');
  assert(guard.before.scripts[record.runner]===record.runnerSha256&&guard.after.scripts[record.runner]===record.runnerSha256,'TOOLGUARD_CORRECTED_RUNNER_SHA_MISMATCH');
  record.toolchainGuard={path:guardPath,sha256:await hash(guardPath),before:guard.before,after:guard.after};
 }
 return {...record,record:recordPath,recordSha256:await hash(recordPath),logSha256:sha(log),SDKGuardClaim:'Four SDK files, exact script bytes, and source/config guarded before and after this invocation; dependency resolution may change only in pubget'};
}
export async function executableIdentity(mode,executable){
 const script='scripts/wave5/inspect_windows_runner_identity_20261010_r5.ps1';
 const result=await execute('powershell.exe',['-NoProfile','-NonInteractive','-File',path.join(root,script),'-Mode',mode,'-Executable',executable],{cwd:root,windowsHide:true,maxBuffer:1024*1024});
 const identity=JSON.parse(result.stdout.replace(/^\uFEFF/,''));
 assert(identity.readOnly===true&&identity.nativeLaunched===false&&identity.CompanyName==='com.jentra.test'&&identity.ProductName===`JentraOS_WindowsTest_20261010-r5_${mode}`&&identity.OriginalFilename==='Jentra_OS.exe','COMPILED_ISOLATED_IDENTITY_REQUIRED');
 assert(identity.sha256===await hash(executable),'IDENTITY_READ_EXECUTABLE_HASH_CHANGED');return {...identity,inspector:script,inspectorSha256:await hash(script)};
}
