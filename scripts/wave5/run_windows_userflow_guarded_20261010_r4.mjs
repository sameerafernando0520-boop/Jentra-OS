// NEW r4 variant; preserved predecessor run_windows_userflow_guarded_20261010_r3_a2.mjs SHA-256 959b87b076a01ed374507bf50c7e204158ec0aef50aaf469bd5eca91e42a8595.
// Root invokes this wrapper to launch one serialized SDK stage. Do not infer a
// before-check for any earlier stage that ran without this wrapper.
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstat, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const wrapperPath = 'scripts/wave5/run_windows_userflow_guarded_20261010_r4.mjs';
const approvedPath = `${base}desktop-verification-source-20261010-r4-approved.json`;
const prepPath = `${base}windows-userflow-preparation-20261010-r4.json`;
const [mode, stage, ...options] = process.argv.slice(2);
const stages = ['pubget','analyzer','startupTests','keyboardTests','accountingTests','authTests','cashTests','platformAll','desktopAll','build'];
if (!['Preview','Connected'].includes(mode) || !stages.includes(stage)) throw Error('GUARDED_MODE_STAGE_REQUIRED');
let attempt = 'a1', offline = false;
for (let i=0;i<options.length;i++) {
  if (options[i] === '--attempt' && /^[a-z][a-z0-9]{0,8}$/.test(options[i+1] ?? '')) attempt = options[++i];
  else if (options[i] === '--offline') offline = true;
  else throw Error('GUARDED_STAGE_OPTION_INVALID');
}
const recordPath = `${base}windows-test-${mode.toLowerCase()}-${stage}-toolguard-20261010-r4-${attempt}.json`;
const sdkRecordPath = `${base}windows-test-${mode.toLowerCase()}-${stage}-20261010-r4-${attempt}.json`;
const sha = b => createHash('sha256').update(b).digest('hex');
const bytes = p => readFile(path.isAbsolute(p) ? p : path.join(root,p));
const hash = async p => sha(await bytes(p));
const json = async p => JSON.parse((await bytes(p)).toString('utf8').replace(/^\uFEFF/,''));
const exists = async p => {try {await lstat(path.join(root,p)); return true;} catch(e) {if(e.code==='ENOENT') return false; throw e;}};
if (await exists(recordPath) || await exists(sdkRecordPath)) throw Error('NEW_GUARD_AND_SDK_OUTPUT_REQUIRED');
const prep = await json(prepPath), approved = await json(approvedPath);
if(approved.postImageApproval!==true||prep.approvedInput.path!==approvedPath||prep.approvedInput.sha256!==await hash(approvedPath)||prep.fullDesktopEvidence?.fullSuitePassed!==true)throw Error('POSTAPPROVAL_PREPARATION_AND_FULL_SUITE_REQUIRED');
const snapshot = path.join(root,'build/w5win10r4',mode.toLowerCase());
if (approved.toolchain.tooling.length !== 4) throw Error('FOUR_APPROVED_TOOLCHAIN_BINDINGS_REQUIRED');
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
async function observation() {
  const tooling = [];
  for (const binding of approved.toolchain.tooling) {
    const current = await hash(binding.path);
    if (current !== binding.sha256) throw Error('APPROVED_SDK_TOOLCHAIN_CHANGED');
    tooling.push({path:binding.path,sha256:current});
  }
  const scripts = {};
  for (const [p,h] of Object.entries(prep.scriptBindings)) {
    if (await hash(p) !== h) throw Error('FROZEN_PREPARER_RUNNER_CHANGED');
    scripts[p]=h;
  }
  scripts[wrapperPath]=await hash(wrapperPath);
  scripts['scripts/wave5/run_windows_userflow_20261010_r4.ps1']=await hash('scripts/wave5/run_windows_userflow_20261010_r4.ps1');
  const resolution = [];
  for (const name of ['.dart_tool/package_config.json','.dart_tool/package_graph.json']) {
    const absolute = path.join(snapshot,name);
    let stat;
    try {stat=await lstat(absolute);} catch(e) {if(e.code !== 'ENOENT') throw e;}
    if (!stat) {
      if (stage !== 'pubget') throw Error('FRESH_SNAPSHOT_DEPENDENCY_RESOLUTION_REQUIRED');
      resolution.push({path:path.relative(root,absolute).split(path.sep).join('/'),exists:false,sha256:null});
    } else {
      if (stat.isSymbolicLink() || !stat.isFile()) throw Error('DEPENDENCY_RESOLUTION_LINK_REFUSED');
      resolution.push({path:path.relative(root,absolute).split(path.sep).join('/'),exists:true,sha256:await hash(absolute)});
    }
  }
  return {observedAt:new Date().toISOString(),tooling,scripts,resolution,approvedInputSha256:await hash(approvedPath),preparationSha256:await hash(prepPath)};
}
const result = {startedAt:new Date().toISOString(),mode,stage,attempt,revision:'r4',date:'20261010',status:'running',
  sdkRecord:sdkRecordPath,before:null,after:null,exitCode:null,failure:null,SDKStageInvoked:false,
  nativeLaunched:false,authenticatedAcceptance:false,liveOperations:false,
  boundary:'Only this invocation has before/after SDK and package-resolution guards. Earlier direct SDK stages retain their own narrower evidence.'};
await writeFile(path.join(root,recordPath),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
try {
  result.before=await observation();
  await writeFile(path.join(root,recordPath),JSON.stringify(result,null,2)+'\n');
  const args=['-NoProfile','-NonInteractive','-File',path.join(root,'scripts/wave5/run_windows_userflow_20261010_r4.ps1'),'-Mode',mode,'-Stage',stage,'-Attempt',attempt];
  if(offline) args.push('-Offline');
  result.SDKStageInvoked=true;
  const exitCode=await new Promise((resolve,reject)=>{
    const child=spawn('powershell.exe',args,{cwd:root,stdio:'inherit',windowsHide:true});
    child.once('error',reject);child.once('exit',code=>resolve(code??1));
  });
  result.exitCode=exitCode;
  result.after=await observation();
  if(!equal(result.before.tooling,result.after.tooling) || !equal(result.before.scripts,result.after.scripts) ||
    result.before.approvedInputSha256!==result.after.approvedInputSha256 || result.before.preparationSha256!==result.after.preparationSha256) throw Error('SDK_OR_FROZEN_BINDINGS_CHANGED_DURING_STAGE');
  result.resolutionChanged=!equal(result.before.resolution,result.after.resolution);
  if(stage!=='pubget' && result.resolutionChanged) throw Error('PACKAGE_RESOLUTION_CHANGED_DURING_STAGE');
  const sdk=await json(sdkRecordPath);
  if(sdk.exitCode!==exitCode || sdk.mode!==mode || sdk.stage!==stage || sdk.attempt!==attempt || sdk.SDKExecuted!==true || sdk.failure) throw Error('SDK_STAGE_RECORD_FAILED_OR_MISMATCHED');
  if(exitCode!==0) throw Error('SDK_STAGE_RETURNED_NONZERO');
  const sdkExit=await json(sdk.sdkExitRecord);
  if(sdk.sdkExitCode!==0 || sdkExit.sdkExitCode!==0 || sdkExit.mode!==mode || sdkExit.stage!==stage || sdkExit.attempt!==attempt || await hash(sdk.sdkExitRecord)!==sdk.sdkExitRecordSha256) throw Error('DURABLE_ACTUAL_SDK_EXIT_REQUIRED');
  result.sdkExitRecord={path:sdk.sdkExitRecord,sha256:sdk.sdkExitRecordSha256};
  result.sdkRecordSha256=await hash(sdkRecordPath);
  result.status='passed';
} catch(e) {
  result.status='failed';result.failure=e.message;result.exitCode=1;
} finally {
  result.finishedAt=new Date().toISOString();
  await writeFile(path.join(root,recordPath),JSON.stringify(result,null,2)+'\n');
}
console.log(JSON.stringify({record:recordPath,status:result.status,exitCode:result.exitCode,failure:result.failure,SDKStageInvoked:result.SDKStageInvoked}));
process.exitCode=result.exitCode;
