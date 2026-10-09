// Evidence collection only. No launch, network, provisioning or source mutation.
import {readFile,readdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const base='docs/verification/wave5/',revision=process.argv[2]??'r5';
if(!/^r\d+$/.test(revision))throw Error('CURRENT_EVIDENCE_REVISION_REQUIRED');
const sha=b=>createHash('sha256').update(b).digest('hex');
const json=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
const save=async(p,v)=>writeFile(p,JSON.stringify(v,null,2)+'\n');
const priorDeno=await json(base+'supabase-entrypoint-checks-20261009.json');
const denoEntries=await Promise.all(['runtime','receiver'].map(async name=>{
 const entrypoint=`supabase/functions/wave5-${name}/index.ts`,log=base+`supabase-${name}-deno-20261009.log`;
 const bytes=await readFile(log);
 const prior=priorDeno.entrypoints.find(c=>c.entrypoint===entrypoint);
 if(!bytes.toString('utf8').includes('Check '+entrypoint)||!prior||prior.exitCode!==0||prior.entrypointSha256!==sha(await readFile(entrypoint))||prior.logSha256!==sha(bytes))throw Error('DENO_CHECK_ATTRIBUTION_REQUIRED');
 return prior;
}));
await save(base+'supabase-entrypoint-checks-20261009.json',{observedAt:priorDeno.observedAt,collectedAt:new Date().toISOString(),checksRerun:false,entrypoints:denoEntries,
 command:'deno check --reload --config <per-entrypoint deno.json> <index.ts>',sdk:'Deno 2; installed executable',
 importedJavaScriptTypeChecked:false,javaScriptVerification:'63 controlled Node tests; entrypoint checking is separate from deployed source/delivery',deployed:false});
const expected={analyzer:null,modelGatewayTests:15,modelTests:20,keyboardTests:6,cashTests:96,cashFrames:12,modelFrames:12,startupTests:2};
if(revision!=='r5'){expected.authGatewayTests=Number(process.argv[4]??11);expected.authTests=Number(process.argv[3]);expected.authFrames=2;if(!Number.isSafeInteger(expected.authTests)||expected.authTests<1||!Number.isSafeInteger(expected.authGatewayTests)||expected.authGatewayTests<11)throw Error('AUTH_SUITE_COUNT_REQUIRED');}
const stages=[];
for(const [stage,count]of Object.entries(expected)){
 const record=base+`windows-test-preview-${stage}-20261009-${revision}.json`,data=await json(record),bytes=await readFile(data.log);
 if(data.exitCode!==0)throw Error('CURRENT_STAGE_FAILED:'+stage);
 const text=bytes.toString('utf8');
 if(stage==='analyzer'?!text.includes('No issues found!'):!text.includes(`+${count}: All tests passed!`))throw Error('CURRENT_STAGE_RESULT_REQUIRED:'+stage);
 stages.push({...data,record,logSha256:sha(bytes),passedTests:count});
}
const builds=[];
const sourceFiles=Object.keys((await json(base+`windows-test-preview-package-20261009-${revision}.json`)).sourceHashes).length;
for(const mode of ['preview','connected']){
 const p=base+`windows-test-${mode}-package-20261009-${revision}.json`,b=await json(p);
 if(!b.current_source_match||!b.base_source_match||b.entrypoint!=='lib/main.dart'||b.controlledEvidence||Object.keys(b.sourceHashes).length!==sourceFiles)throw Error('ORDINARY_SOURCE_MATCHED_PACKAGE_REQUIRED');
 for(const [f,h]of Object.entries(b.sourceHashes))if(sha(await readFile(f))!==h)throw Error('CURRENT_DESKTOP_SOURCE_DRIFT:'+f);
 for(const f of b.releaseFiles)if(sha(await readFile(path.join(b.packageDirectory,f.path)))!==f.sha256)throw Error('CURRENT_RELEASE_DRIFT:'+f.path);
 const launchPath=base+`windows-test-${mode}-launch-20261009-${revision}.json`,launch=await json(launchPath);
 if(!launch.nativeLaunched||launch.executable!==b.executable||launch.authenticatedAcceptance||!launch.capture)throw Error('OWN_NATIVE_LAUNCH_REQUIRED');
 const build=await json(b.buildEvidence);
 if(build.exitCode!==0)throw Error('WINDOWS_BUILD_REQUIRED');
 builds.push({mode,packageManifest:p,sourceFileCount:Object.keys(b.sourceHashes).length,releaseFiles:b.releaseFiles.length,
  launchManifest:launchPath,pid:launch.pid,capture:launch.capture,captureSha256:sha(await readFile(launch.capture)),
  nativeInspected:true,entrypoint:b.entrypoint,storageIdentity:b.storageIdentity,build});
}
const deliveryPath=base+`windows-test-delivery-20261009-${revision}.json`,delivery=await json(deliveryPath);
if(delivery.verifiedReleaseEntries!==68||sha(await readFile(delivery.zip))!==delivery.zipSha256)throw Error('CURRENT_ZIP_REQUIRED');
const inspectedCash=['cash-1024-720-light-compact-top.png','cash-1024-720-dark-comfortable-dates.png','cash-1440-900-light-comfortable-approval.png','cash-1920-1080-dark-compact-lower.png',
 'cash-1024-720-dark-compact-providers.png','cash-1440-900-dark-comfortable-approval.png','cash-1920-1080-light-compact-dates.png','cash-1920-1080-light-comfortable-top.png'];
const inspectedModel=['model-1024-720-light-compact-top.png','model-1024-720-dark-comfortable-review.png','model-1440-900-light-comfortable-review.png','model-1920-1080-dark-compact-top.png'];
async function frames(kind,expectedCount,inspected){
 const directory=base+`windows-test-${kind}-frames-20261009-${revision}`,names=(await readdir(directory)).filter(n=>n.endsWith('.png')).sort();
 if(names.length!==expectedCount||inspected.some(n=>!names.includes(n)))throw Error('CURRENT_RENDER_FILES_REQUIRED');
 return Promise.all(names.map(async n=>({path:directory+'/'+n,sha256:sha(await readFile(directory+'/'+n)),visuallyInspected:inspected.includes(n)})));
}
const cash=await frames('cash',60,inspectedCash),model=await frames('model',24,inspectedModel);
const auth=revision!=='r5'?await frames('auth',2,(await readdir(base+`windows-test-auth-frames-20261009-${revision}`)).filter(n=>n.endsWith('.png'))):[];
const authSettingsPath=base+'public-auth-settings-20261009.json';
const authSettings=revision!=='r5'?await json(authSettingsPath):null;
if(authSettings&&(authSettings.projectId!=='xpdoufauvrbdmxgngetv'||typeof authSettings.googleEnabled!=='boolean'||typeof authSettings.emailEnabled!=='boolean'||typeof authSettings.signupDisabled!=='boolean'||typeof authSettings.emailAutoconfirm!=='boolean'||authSettings.privateConfigurationRead!==false||authSettings.accountCreated!==false))throw Error('PUBLIC_AUTH_SETTINGS_EVIDENCE_REQUIRED');
const broaderSuites=[];
for(const stage of ['platformAll','desktopAll']){
 try{
  const record=base+`windows-test-preview-${stage}-20261009-${revision}.json`,data=await json(record),bytes=await readFile(data.log),log=bytes.toString('utf8');
  const totals=[...log.matchAll(/\+(\d+)(?:\s+-(\d+))?: (?:All tests passed!|Some tests failed\.)/g)].at(-1);
  if(!totals)throw Error('FULL_SUITE_RESULT_REQUIRED:'+stage);
  broaderSuites.push({...data,record,logSha256:sha(bytes),passedTests:Number(totals[1]),failedTests:Number(totals[2]??0),failureList:[...log.matchAll(/^\d+:\d+ \+\d+(?: -\d+)?: (.*) \[E\]$/gm)].map(m=>m[1])});
 }catch(error){if(error.code!=='ENOENT')throw error;}
}
const deadlineRegressionPath=base+`pkce-deadline-red-20261009-${revision}.json`;
const keyboardFocusPath=base+`windows-test-preview-keyboard-focus-failure-20261009-${revision}.json`;
let keyboardFocus=null;
try{keyboardFocus=await json(keyboardFocusPath);if(keyboardFocus.verified||keyboardFocus.exitCode!==1||keyboardFocus.keysSent!==0||keyboardFocus.code!=='OWN_PREVIEW_FOCUS_REQUIRED_NO_KEYS_SENT')throw Error('KEYBOARD_FOCUS_EVIDENCE_MISMATCH');}catch(error){if(error.code!=='ENOENT')throw error;}
let deadlineRegression=null;
try{
 const regression=await json(deadlineRegressionPath),bytes=await readFile(regression.log);
 if(!regression.redObserved||!regression.sourceRestored||regression.exitCode===0||!bytes.toString('utf8').includes('TimeoutException')||!bytes.toString('utf8').includes('SDK headers deadline aborts without a late session'))throw Error('EXPECTED_PKCE_REGRESSION_RED_REQUIRED');
 deadlineRegression={...regression,record:deadlineRegressionPath,logSha256:sha(bytes),greenSuite:base+`windows-test-preview-authGatewayTests-20261009-${revision}.json`};
}catch(error){if(error.code!=='ENOENT')throw error;}
const report={observedAt:new Date().toISOString(),revision,currentSourceMatch:true,sourceFilesPerApp:sourceFiles,sourceScope:'Desktop transitive workspace source plus all workspace dependency manifests; three explicit runner identity overlays in each build copy',
 ordinaryEntrypoint:'lib/main.dart',previewBuilt:true,connectedBuilt:true,nativeLaunched:true,releaseEntriesVerified:68,
 stages,builds,delivery:deliveryPath,zip:delivery.zip,zipSha256:delivery.zipSha256,zipBytes:delivery.zipBytes,
 cashRenderCases:12,cashFrames:cash,modelRenderCases:12,modelFrames:model,cashFramesInspected:8,modelFramesInspected:4,nativeFramesInspected:2,textScale:2,
 authFrames:auth,authFramesInspected:auth.length,authGatewayTests:expected.authGatewayTests??0,authTests:expected.authTests??0,newAccountUiImplemented:revision!=='r5',googleWindowsReturnImplemented:revision!=='r5',realGoogleSignIn:false,emailConfirmationDeliveryVerified:false,
 publicAuthSettings:authSettings,publicAuthSettingsEvidence:authSettings?authSettingsPath:null,
 broaderSuites,
 pkceDeadlineRegression:deadlineRegression,
 visualFindings:['Model recovery shows the immutable saved source and UTC horizon fields; explicit selection fills the human form without dispatch.',
  'Cash controls, provider completeness, date review and recovery actions remain legible across inspected viewport/theme/density combinations.',
  'Adjacent cash floating labels touch shared field borders at 200 percent text; visual polish and owner review remain open. Scrolled frames intentionally crop viewport edges.'],
 nativeKeyboardVerified:false,nativeKeyboardReason:keyboardFocus?'The r10 keyboard images did not show a command palette. The repeat own-window probe could not acquire foreground and aborted before keys. Six widget keyboard tests pass; native keyboard remains open.':'Earlier r2 own-window probe could not acquire foreground; it aborted before sending any keys. Six widget keyboard tests pass; native keyboard evidence remains open.',nativeKeyboardFocusEvidence:keyboardFocus?keyboardFocusPath:null,
 sharedGoldenFailures:13,sharedGoldensRerun:broaderSuites.some(s=>s.stage==='desktopAll'),approvedGoldensRegenerated:false,
 authenticatedNativeAcceptance:false,realMfa:false,actualModelUsage:false,actualWorkerDelivery:false,independentSessionContention:false,targetScaleLoad:false,ownerAccepted:false,
 newMigrationsInstalled:false,newAccountsCreated:false,formalRuntimeProfileProvisioned:false,acceptanceStoresReadOrCopied:false};
await save(base+`windows-test-verification-20261009-${revision}.json`,report);
await writeFile(base+`windows-test-verification-20261009-${revision}.md`,
`# Fresh Windows test delivery — October 9, revision ${revision}\n\nThe [portable Windows ZIP](../../../${path.relative('.',delivery.zip).split(path.sep).join('/')}) contains Preview and Connected x64 apps built from ordinary \`lib/main.dart\`. Both launched and their fresh Preview workspace and Connected sign-in windows were inspected. All 68 packaged release hashes and each app's ${sourceFiles} selected desktop dependency input hashes match. Three runner identity overlays exist only in the isolated build copies; preferences, sessions and encrypted drafts use separate identities from acceptance. Existing stores were not copied.\n\nZIP SHA-256: \`${delivery.zipSha256}\`; ${delivery.zipBytes} bytes. Extract the whole ZIP and use \`Start Preview.cmd\` or \`Start Connected.cmd\`. Preview supplies the existing sample dashboard; Connected uses the current development backend. Six proposed Wave 5 accounts remain uncreated. ${revision!=='r5'?'The Connected app now includes Create account and Windows Google PKCE return. Follow the [account/Google setup guide](windows-account-google-setup-20261009.md); Google is disabled live until privately configured. '+expected.authGatewayTests+' loopback, provider availability and transport tests and '+expected.authTests+' authentication UI/capability tests pass; two new auth renders were inspected. No real Google session or email confirmation delivery is claimed.':''}\n\nScoped Dart analysis is clean. Fresh suites pass: 15 model gateway/control, 20 model workspace/controller/render, six command-palette keyboard, 96 cash/analytics workspace and two startup/navigation tests. The separate cash/model image captures rerun 12 variants each at 200% text, producing 60/24 images; these capture tests overlap the workspace suites and are not additional independent feature coverage. Eight cash, four model and two native startup images were visually inspected. [Machine evidence](windows-test-verification-20261009-${revision}.json) records hashes, source attribution, commands, times, process IDs and inspection lists.\n\nCash date, scenarios/recovery and reviewed-model request/recovery screens are implemented as source candidates. Recovered model fields show the saved source and UTC horizon. Explicit suggestion selection transfers the source to the human proposal form without issuing a command. Adjacent cash floating labels meet shared borders at 200% text; further visual polish and owner review remain open.\n\n${report.nativeKeyboardReason} Native keyboard/restart/revocation, actual login/MFA/export/model/worker behavior, independent contention, target-scale load and owner acceptance remain unverified. The 13 shared golden failures remain open and no approved golden was replaced. Original installed SQL, candidate rollback, controlled tests/renders and authenticated acceptance are separate evidence gates. No new migration, account, entitlement, secret, worker or standard OS profile was provisioned.\n`);
console.log(JSON.stringify({revision,sourceFilesPerApp:sourceFiles,releaseEntriesVerified:68,zipSha256:delivery.zipSha256,visualInspections:14+auth.length,authenticatedAcceptance:false}));
if(broaderSuites.length){
 const text='\n## Broader current-source regression suites\n\n'+broaderSuites.map(s=>`[${s.stage} log](${path.posix.basename(s.log)}): ${s.passedTests} passed, ${s.failedTests} failed; exit ${s.exitCode}.`+(s.failureList.length?'\n\n'+s.failureList.map(n=>'- '+n).join('\n'):'')).join('\n\n')+'\n\nApproved golden images were not changed. These full-suite results do not replace authenticated acceptance.\n';
 await writeFile(base+`windows-test-verification-20261009-${revision}.md`,text,{flag:'a'});
}
