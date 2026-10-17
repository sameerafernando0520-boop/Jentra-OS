import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const root='C:/Users/sheha/Desktop/Jentra OS';
const base='docs/verification/wave5/seven-area-completion-20261016/area1-windows/current-candidate-20261017';
const snapshot=path.join(root,'build/w5win20261017a1/preview');
const {sources}=await import(pathToFileURL(path.join(root,'scripts/wave5/cash_ui_evidence.mjs')));
const sha=b=>createHash('sha256').update(b).digest('hex');
const must=(v,c)=>{if(!v)throw Error(c);};
must(process.argv.length===2,'FIXED_CANDIDATE_PREPARATION_REQUIRED');
try{await fs.lstat(snapshot);throw Error('NEW_SNAPSHOT_REQUIRED');}catch(e){if(e.code!=='ENOENT')throw e;}
const scope=['apps/jentra_desktop','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'];
const select=m=>Object.fromEntries(Object.entries(m).filter(([p])=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||scope.some(s=>p.startsWith(s+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p)));
const before=select(await sources(root));
await fs.mkdir(snapshot,{recursive:true});
for(const [p,h]of Object.entries(before)){
 const target=path.join(snapshot,p);await fs.mkdir(path.dirname(target),{recursive:true});
 await fs.copyFile(path.join(root,p),target,fs.constants.COPYFILE_EXCL);
 must(sha(await fs.readFile(target))===h,'SOURCE_COPY_DRIFT:'+p);
}
const product='JentraOS_CurrentCandidate_20261017_a1_Preview';
const overlays=[];
async function overlay(p,replace){const target=path.join(snapshot,p),beforeBytes=await fs.readFile(target),after=replace(beforeBytes.toString('utf8'));must(after!==beforeBytes.toString('utf8'),'RUNNER_OVERLAY_REQUIRED:'+p);await fs.writeFile(target,after);overlays.push({path:p,baseSha256:sha(beforeBytes),candidateSha256:sha(Buffer.from(after))});}
await overlay('apps/jentra_desktop/windows/CMakeLists.txt',s=>s.replace('set(BINARY_NAME "jentra_desktop")','set(BINARY_NAME "Jentra_OS")'));
await overlay('apps/jentra_desktop/windows/runner/Runner.rc',s=>s.replace('VALUE "CompanyName", "com.jentra"','VALUE "CompanyName", "com.jentra.test"').replace('VALUE "ProductName", "jentra_desktop"',`VALUE "ProductName", "${product}"`).replace('VALUE "FileDescription", "jentra_desktop"','VALUE "FileDescription", "Jentra OS Current Source Candidate"').replace('VALUE "OriginalFilename", "jentra_desktop.exe"','VALUE "OriginalFilename", "Jentra_OS.exe"'));
await overlay('apps/jentra_desktop/windows/runner/main.cpp',s=>s.replace('window.Create(L"jentra_desktop"','window.Create(L"Jentra OS - 20261017 Candidate Preview"'));
const candidate=select(await sources(snapshot));
must(JSON.stringify(select(await sources(root)))===JSON.stringify(before),'CURRENT_SOURCE_CHANGED_DURING_PREPARATION');
const manifest={kind:'current-source-windows-candidate-snapshot',preparedAt:new Date().toISOString(),root,snapshot,mode:'Preview',product,scope,sourceCount:Object.keys(before).length,baseSourceHashes:before,candidateSourceHashes:candidate,overlays,SDKExecuted:false,networkCalls:0,credentialsRead:false,localStoresCopied:false,installed:false,authenticatedNative:false,goldenBaselinesUpdated:false,preparerSha256:sha(await fs.readFile(path.join(root,base,'prepare-candidate.mjs')))};
const manifestPath=path.join(root,base,'source-manifest.json');await fs.writeFile(manifestPath,JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
const desktopCatalog=Object.keys(before).filter(p=>p.startsWith('apps/jentra_desktop/test/')&&p.endsWith('_test.dart')).map(p=>p.replace('apps/jentra_desktop/','')).sort();
const platformCatalog=Object.keys(before).filter(p=>/^packages\/jentra_platform\/test\/(analytics|auth)\/.*_test\.dart$/.test(p)).map(p=>p.replace('packages/jentra_platform/','')).sort();
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe',tool='C:/src/flutter/bin/cache/flutter_tools.snapshot';
const batches=[];for(let i=0;i<desktopCatalog.length;i+=6)batches.push(desktopCatalog.slice(i,i+6));
const plan={kind:'current-source-candidate-serialized-sdk-plan',preparedAt:new Date().toISOString(),sourceManifest:{path:base+'/source-manifest.json',sha256:sha(await fs.readFile(manifestPath))},sdk,tool,wrapper:'scripts/wave5/run_flutter_with_capture_env.mjs',snapshot,desktopCatalog,platformCatalog,desktopBatches:batches,stages:['pubget-offline','analyze','platform-tests','desktop-batches','render-analytics','render-continuation','render-model','build-windows'],commands:{pubget:[tool,'--suppress-analytics','pub','get','--offline'],analyze:['analyze','apps/jentra_desktop/lib','apps/jentra_desktop/test/wave5_workspaces_test.dart','apps/jentra_desktop/test/wave5_continuation_test.dart','apps/jentra_desktop/test/reviewed_model_workspace_test.dart','apps/jentra_desktop/test/process_metric_workspace_test.dart','packages/jentra_platform/lib/src/analytics','packages/jentra_platform/lib/src/auth','packages/jentra_platform/test/analytics','packages/jentra_platform/test/auth'],testPrefix:[tool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded'],build:[tool,'--suppress-analytics','build','windows','--release','--no-pub','--target=lib/main.dart','--dart-define=JENTRA_ENVIRONMENT=preview']},renderEnvironment:{analytics:'W5_FRAME_DIR',continuation:'W5_CONTINUATION_FRAME_DIR',model:'W5_MODEL_FRAME_DIR'},nativeLaunched:false,noGoldenUpdateFlag:true,SDKSlotRequired:true};
await fs.writeFile(path.join(root,base,'execution-plan.json'),JSON.stringify(plan,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({snapshot,sources:manifest.sourceCount,desktopFiles:desktopCatalog.length,platformFiles:platformCatalog.length,batches:batches.length,manifestSha256:plan.sourceManifest.sha256,SDKExecuted:false}));
