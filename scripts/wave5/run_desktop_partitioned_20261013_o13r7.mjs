import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../../',import.meta.url)),snapshot=path.join(root,'build/w5win9o13r7/preview'),cwd=path.join(snapshot,'apps/jentra_desktop'),base='docs/verification/wave5/desktop-partitioned-20261013-o13r7/';
const sha=b=>createHash('sha256').update(b).digest('hex'),must=(v,c)=>{if(!v)throw Error(c);};
must(process.argv.length===2,'FIXED_CURRENT_DESKTOP_PARTITION_RUN_REQUIRED');
const manifestPath='docs/verification/wave5/windows-test-preview-source-20261009-o13r7.json',manifestBytes=await fs.readFile(path.join(root,manifestPath)),manifest=JSON.parse(manifestBytes);
must(manifest.revision==='o13r7'&&manifest.mode==='Preview'&&manifest.snapshot===snapshot&&manifest.controlledEvidence===false,'EXACT_CURRENT_PREVIEW_SNAPSHOT_REQUIRED');
async function verifySources(){let count=0;for(const [p,h]of Object.entries(manifest.buildSourceHashes)){const f=path.join(snapshot,p),s=await fs.lstat(f);must(!s.isSymbolicLink()&&s.isFile()&&sha(await fs.readFile(f))===h,'SNAPSHOT_SOURCE_DRIFT');count++;}must(count===1069,'EXACT_CURRENT_SOURCE_COUNT_REQUIRED');return count;}
async function files(dir){const out=[];for(const e of await fs.readdir(dir,{withFileTypes:true})){const f=path.join(dir,e.name);must(!e.isSymbolicLink(),'PLAIN_TEST_CATALOG_REQUIRED');if(e.isDirectory())out.push(...await files(f));else if(e.isFile()&&e.name.endsWith('_test.dart'))out.push(path.relative(cwd,f).replaceAll('\\','/'));}return out;}
const catalog=(await files(path.join(cwd,'test'))).sort();must(catalog.length===138&&new Set(catalog).size===138,'COMPLETE_138_TEST_FILE_CATALOG_REQUIRED');
for(const p of catalog)must(Object.hasOwn(manifest.buildSourceHashes,'apps/jentra_desktop/'+p),'BOUND_TEST_SOURCE_REQUIRED');
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe',tool='C:/src/flutter/bin/cache/flutter_tools.snapshot',wrapper=path.join(root,'scripts/wave5/run_flutter_with_capture_env.mjs');
const protectedFiles=[sdk,tool,wrapper,path.join(snapshot,'pubspec.lock'),path.join(snapshot,'.dart_tool/package_config.json')];
async function guardFiles(){return Promise.all(protectedFiles.map(async p=>({path:p,sha256:sha(await fs.readFile(p))})));}
const before=await guardFiles();await verifySources();
await fs.mkdir(path.join(root,base));
async function save(name,value){const b=JSON.stringify(value,null,2)+'\n';await fs.writeFile(path.join(root,base+name),b,{flag:'wx'});return {path:base+name,sha256:sha(b)};}
const batches=[];for(let i=0;i<catalog.length;i+=6)batches.push(catalog.slice(i,i+6));
const startedAt=new Date().toISOString(),sourceManifest={path:manifestPath,sha256:sha(manifestBytes)};
await save('00-intent.json',{kind:'fresh-full-desktop-suite-partitioned-on-exact-snapshot',startedAt,sourceManifest,sourceInputs:1069,catalog,batches,chunkSize:6,testConcurrency:1,heavySdkJobsSerialized:true,approvedGoldenBaselinesModified:false,priorFullVmFailurePreserved:true,sdkAndDependencyBefore:before,privateCredentialsRead:false,authenticatedNative:false});
const completed=[];let currentBatch=0;
try{
 for(let i=0;i<batches.length;i++){
  currentBatch=i+1;await verifySources();must(JSON.stringify(await guardFiles())===JSON.stringify(before),'SDK_OR_DEPENDENCY_DRIFT');
  const name=String(i+1).padStart(2,'0'),log=base+name+'-tests.log',start=new Date().toISOString(),handle=await fs.open(path.join(root,log),'wx');
  const args=[wrapper,sdk,tool,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded',...batches[i]];
  const env={...process.env};for(const k of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR'])delete env[k];
  let code;try{code=await new Promise((resolve,reject)=>{const child=spawn(process.execPath,args,{cwd,env,windowsHide:true,stdio:['ignore',handle.fd,handle.fd]});child.once('error',reject);child.once('exit',(c,signal)=>resolve(c??(signal?1:1)));});await handle.sync();}finally{await handle.close();}
  const bytes=await fs.readFile(path.join(root,log)),text=bytes.toString('utf8'),progress=[...text.matchAll(/\d+:\d+ \+(\d+)(?: ~(\d+))?(?: -(\d+))?:/g)],last=progress.at(-1);
  const passed=Number(last?.[1]??0),skipped=Number(last?.[2]??0),failed=Number(last?.[3]??0),terminalSuccess=text.includes('All tests passed!');
  const afterCount=await verifySources();must(JSON.stringify(await guardFiles())===JSON.stringify(before),'SDK_OR_DEPENDENCY_DRIFT');
  const record={batch:currentBatch,tests:batches[i],startedAt:start,finishedAt:new Date().toISOString(),command:[process.execPath,...args],exitCode:code,terminalSuccess,passed,skipped,failed,sourceInputsAfter:afterCount,log:{path:log,bytes:bytes.length,sha256:sha(bytes)},freshGoldenFailureMarker:/Golden.*(?:fail|mismatch)|golden.*(?:fail|mismatch)/i.test(text)};
  await save(name+'-result.json',record);completed.push(record);process.stdout.write(JSON.stringify({batch:currentBatch,totalBatches:batches.length,exitCode:code,terminalSuccess,passed,failed,skipped})+'\n');
  must(code===0&&terminalSuccess&&passed>0&&failed===0&&skipped===0,'CURRENT_DESKTOP_BATCH_NOT_COMPLETE');
 }
 const record={kind:'actual-complete-partitioned-desktop-test-suite',startedAt,finishedAt:new Date().toISOString(),sourceManifest,sourceInputsVerified:1069,testFilesExecuted:catalog.length,completeCatalog:catalog,batches:completed,passed:completed.reduce((n,r)=>n+r.passed,0),failed:0,skipped:0,allBatchesPassed:true,all138TestFilesExecuted:true,sdkAndDependenciesUnchanged:true,sourceSnapshotUnchanged:true,heavySdkJobsSerialized:true,approvedGoldenBaselinesModified:false,previousFailedWholeRunPreserved:true,authenticatedNative:false,nativeKeyboard:false,actualDelivery:false,ownerAcceptance:false};
 const binding=await save('99-result.json',record);process.stdout.write(JSON.stringify({completed:true,...binding,passed:record.passed,failed:0,skipped:0,testFiles:138})+'\n');
}catch(e){await save('99-stop.json',{kind:'preserved-partitioned-desktop-suite-stop',startedAt,stoppedAt:new Date().toISOString(),currentBatch,failureCode:e.message,completedBatches:completed,completeSuitePassed:false,automaticRetry:false,approvedGoldenBaselinesModified:false});throw e;}
