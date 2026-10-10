// Evidence persistence only. Root supplies observations from the supported sky
// native UI API; this helper performs no app input, authentication or store read.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const output = base+'native-preview-userflows-20261010-r3.json';
const packagePath = base+'windows-test-preview-package-20261010-r3.json';
const storagePath = base+'windows-userflow-storage-before-20261010-r3.json';
const helper = 'scripts/wave5/record_native_preview_observations_20261010_r3.mjs';
const sha = b => createHash('sha256').update(b).digest('hex');
const binding = async p => ({path:p,sha256:sha(await readFile(path.join(root,p)))});
const json = async p => JSON.parse((await readFile(path.join(root,p))).toString('utf8').replace(/^\uFEFF/,''));
export async function beginPreviewEvidence() {
  const packaged = await json(packagePath), storage = await json(storagePath);
  if(packaged.mode !== 'preview' || packaged.current_source_match !== true ||
    packaged.executableIdentity.packaged.CompanyName !== 'com.jentra.test' ||
    packaged.executableIdentity.packaged.ProductName !== 'JentraOS_WindowsTest_20261010-r3_Preview' ||
    storage.allExpectedPathsAbsent !== true || storage.pathContentsRead !== false) throw Error('VERIFIED_NEW_PREVIEW_REQUIRED');
  const actualExeSha = sha(await readFile(packaged.executable));
  if(actualExeSha !== packaged.executableIdentity.packaged.sha256) throw Error('PACKAGED_EXECUTABLE_CHANGED');
  const record = {kind:'actual-native-preview-userflow-observations',startedAt:new Date().toISOString(),revision:'r3',mode:'Preview',
    executable:packaged.executable,executableSha256:actualExeSha,package:await binding(packagePath),sourceManifest:{path:packaged.sourceManifest,sha256:packaged.sourceManifestSha256},
    prelaunchPathObservation:await binding(storagePath),recorder:await binding(helper),actorLabel:'unconfigured development preview',
    observations:[],observedWindows:[],status:'in-progress',nativeLaunched:false,authenticatedNative:false,fullNativeKeyboardGate:false,
    accountingTransactionsPosted:false,authoritativeReportsGenerated:false,actualDelivery:false,realMfa:false,actualModelUsage:false,
    independentSessionContention:false,targetScaleLoad:false,ownerAcceptanceChanged:false,productionExcluded:true,realBillingExcluded:true,
    boundary:'Actual ordinary offline Preview observations only. Operational accounting gateways are unavailable. Keyboard checks here do not establish authenticated native or whole-system acceptance.'};
  await writeFile(path.join(root,output),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
  return record;
}
export async function bindPreviewWindow(record, returnedWindow) {
  const normalized = s => s.replace(/^process:/i,'').replaceAll('\\','/').toLowerCase();
  if(!Number.isInteger(returnedWindow?.id) || normalized(returnedWindow.app??'')!==normalized(record.executable) ||
    returnedWindow.title!=='Jentra OS - 20261010 r3 Preview test') throw Error('RETURNED_EXACT_PREVIEW_PROCESS_WINDOW_REQUIRED');
  if(!record.observedWindows.some(w=>w.id===returnedWindow.id&&w.app===returnedWindow.app))
    record.observedWindows.push({...returnedWindow,boundAt:new Date().toISOString()});
  await writeFile(path.join(root,output),JSON.stringify(record,null,2)+'\n');
  return {windowId:returnedWindow.id,app:returnedWindow.app};
}
export async function appendPreviewObservation(record, {id,action,expected,observed,result,state}) {
  if(!/^[A-Z][A-Z0-9_-]{1,49}$/.test(id) || !['pass','fail','blocked','observed'].includes(result) ||
    record.observations.some(o=>o.id===id) || !state?.window || state.window.title!=='Jentra OS - 20261010 r3 Preview test' ||
    !record.observedWindows.some(w=>w.id===state.window.id&&w.app===state.window.app)) throw Error('EXACT_PREVIEW_OBSERVATION_REQUIRED');
  if(!Array.isArray(state.screenshots)||state.screenshots.length===0) throw Error('ACTUAL_VISUAL_EVIDENCE_REQUIRED');
  if(sha(await readFile(record.executable))!==record.executableSha256) throw Error('EXECUTABLE_DRIFT');
  const screenshots=[];
  for(let i=0;i<(state.screenshots??[]).length;i++) {
    const screenshot=state.screenshots[i],match=screenshot.url.match(/^data:image\/(png|jpeg);base64,(.+)$/s);
    if(!match) throw Error('SUPPORTED_NATIVE_SCREENSHOT_REQUIRED');
    const p=base+`native-preview-20261010-r3/${id}-${i}.${match[1]==='jpeg'?'jpg':'png'}`;
    await mkdir(path.dirname(path.join(root,p)),{recursive:true});
    const bytes=Buffer.from(match[2],'base64');
    await writeFile(path.join(root,p),bytes,{flag:'wx'});
    screenshots.push({path:p,sha256:sha(bytes),bytes:bytes.length,width:screenshot.width,height:screenshot.height,screenshotId:screenshot.id});
  }
  record.observations.push({id,observedAt:new Date().toISOString(),action,expected,observed,result,window:state.window,
    accessibility:state.accessibility, screenshots});
  record.nativeLaunched=true;
  await writeFile(path.join(root,output),JSON.stringify(record,null,2)+'\n');
  return {id,result,screenshots:screenshots.map(s=>s.path),observations:record.observations.length};
}
export async function finishPreviewEvidence(record) {
  for(const b of [record.package,record.sourceManifest,record.prelaunchPathObservation,record.recorder])
    if((await binding(b.path)).sha256!==b.sha256) throw Error('NATIVE_EVIDENCE_BINDING_DRIFT');
  if(sha(await readFile(record.executable))!==record.executableSha256) throw Error('EXECUTABLE_DRIFT');
  record.status='complete';record.finishedAt=new Date().toISOString();
  record.counts=Object.fromEntries(['pass','fail','blocked','observed'].map(r=>[r,record.observations.filter(o=>o.result===r).length]));
  await writeFile(path.join(root,output),JSON.stringify(record,null,2)+'\n');
  return {path:output,sha256:sha(await readFile(path.join(root,output))),counts:record.counts,authenticatedNative:false,ownerAcceptanceChanged:false};
}
