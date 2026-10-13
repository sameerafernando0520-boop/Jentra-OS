// NEW r5 successor; preserved r4 predecessor scripts/wave5/record_native_preview_observations_20261010_r4.mjs SHA-256 c7b8cbd5d0a22468851f21fdd070060902cc64200090e6f38b1f636f22ae17b0.
// Evidence persistence only. Root supplies states from the supported native UI API.
// This module never launches an app, sends input, authenticates or reads stores.
import {readFile,writeFile,mkdir,lstat,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),base='docs/verification/wave5/';
const output=base+'native-preview-userflows-20261010-r5.json',packagePath=base+'windows-test-preview-package-20261010-r5.json';
const storagePath=base+'windows-userflow-storage-before-20261010-r5.json',helper='scripts/wave5/record_native_preview_observations_20261010_r5.mjs';
const predecessor={path:'scripts/wave5/record_native_preview_observations_20261010_r4.mjs',sha256:'c7b8cbd5d0a22468851f21fdd070060902cc64200090e6f38b1f636f22ae17b0'};
const historicalPredecessor={path:'scripts/wave5/record_native_preview_observations_20261010_r3.mjs',sha256:'0b111194571c225cb1962c6cf2f2d56c63d2579e013788621f1ba86b1cb4a8fa'};
const title='Jentra OS - 20261010 r5 Preview test',sha=b=>createHash('sha256').update(b).digest('hex');
const must=(ok,message)=>{if(!ok)throw Error(message);},normalized=s=>s.replace(/^process:/i,'').replaceAll('\\','/').toLowerCase();
const known=new WeakMap();
function inside(file){const full=path.resolve(root,file),rel=path.relative(root,full);must(rel&&!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel),'EVIDENCE_PATH_ESCAPES');return full;}
async function bytes(file){const full=inside(file),stat=await lstat(full);must(stat.isFile()&&!stat.isSymbolicLink()&&await realpath(full)===full,'UNLINKED_EVIDENCE_FILE_REQUIRED');return readFile(full);}
const binding=async file=>({path:file,sha256:sha(await bytes(file))});
const json=async file=>JSON.parse((await bytes(file)).toString('utf8').replace(/^\uFEFF/,''));
function imageDimensions(b){
 if(b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))){must(b.length>=24,'PNG_HEADER_REQUIRED');return{width:b.readUInt32BE(16),height:b.readUInt32BE(20)};}
 must(b.length>4&&b[0]===255&&b[1]===216,'ACTUAL_PNG_OR_JPEG_REQUIRED');let offset=2;
 while(offset<b.length){must(b[offset]===255,'JPEG_MARKER_INVALID');while(b[offset]===255)offset++;const marker=b[offset++];if(marker===217||marker===218)break;if(marker===1||marker>=208&&marker<=215)continue;
  must(offset+2<=b.length,'JPEG_SEGMENT_INCOMPLETE');const length=b.readUInt16BE(offset);must(length>=2&&offset+length<=b.length,'JPEG_SEGMENT_LENGTH_INVALID');
  if([192,193,194,195,197,198,199,201,202,203,205,206,207].includes(marker)){must(length>=8,'JPEG_FRAME_REQUIRED');return{width:b.readUInt16BE(offset+5),height:b.readUInt16BE(offset+3)};}offset+=length;
 }throw Error('ACTUAL_IMAGE_DIMENSIONS_REQUIRED');
}
async function assertBound(record,{source=false,screenshots=false}={}){
 must(record.kind==='actual-native-preview-userflow-observations'&&record.revision==='r5'&&record.mode==='Preview'&&record.executable===path.join(root,'dist/Jentra OS Windows Test 20261010 r5/Preview/Jentra_OS.exe'),'EXACT_R5_PREVIEW_RECORD_REQUIRED');
 for(const ref of [record.package,record.sourceManifest,record.prelaunchPathObservation,record.recorder,record.predecessor,record.historicalPredecessor])must(ref?.path&&(await binding(ref.path)).sha256===ref.sha256,'NATIVE_EVIDENCE_BINDING_DRIFT');
 must(sha(await bytes(record.executable))===record.executableSha256,'NATIVE_EXECUTABLE_DRIFT');
 if(source){const packaged=await json(packagePath);for(const [file,h]of Object.entries(packaged.sourceHashes))must(sha(await bytes(file))===h,'CURRENT_PRODUCT_SOURCE_CHANGED');}
 if(screenshots)for(const observation of record.observations)for(const screenshot of observation.screenshots){const data=await bytes(screenshot.path),size=imageDimensions(data);must(sha(data)===screenshot.sha256&&data.length===screenshot.bytes&&size.width===screenshot.width&&size.height===screenshot.height,'ACTUAL_NATIVE_SCREENSHOT_DRIFT');}
}
async function active(record){must(record.status==='in-progress'&&known.has(record),'REGISTERED_INCOMPLETE_OBSERVATION_REQUIRED');must(sha(await bytes(output))===known.get(record),'CONCURRENT_NATIVE_EVIDENCE_CHANGE');await assertBound(record);}
async function persist(record,{newFile=false}={}){
 const data=Buffer.from(JSON.stringify(record,null,2)+'\n');
 await writeFile(inside(output),data,{flag:newFile?'wx':'w'});known.set(record,sha(data));
 must(sha(await bytes(output))===sha(data),'NATIVE_EVIDENCE_PUBLICATION_FAILED');
}
export async function beginPreviewEvidence({inputToolEvidence}={}){
 must(inputToolEvidence?.provider==='@oai/sky'&&inputToolEvidence.bridge==='node_repl'&&typeof inputToolEvidence.documentationBundle==='string'&&inputToolEvidence.documentationBundle.trim()&&Number.isFinite(Date.parse(inputToolEvidence.documentationObservedAt))&&Date.parse(inputToolEvidence.documentationObservedAt)<=Date.now(),'ACTUAL_INPUT_TOOL_DOCUMENTATION_METADATA_REQUIRED');
 must(inputToolEvidence.packageVersion===null||typeof inputToolEvidence.packageVersion==='string'&&inputToolEvidence.packageVersion.trim(),'INPUT_PACKAGE_VERSION_OR_EXPLICIT_UNKNOWN_REQUIRED');
 must(typeof inputToolEvidence.packageVersionVerified==='boolean'&&(!inputToolEvidence.packageVersionVerified||inputToolEvidence.packageVersion!==null&&Number.isFinite(Date.parse(inputToolEvidence.packageVersionObservedAt))),'INPUT_TOOL_VERSION_PROVENANCE_REQUIRED');
 const packaged=await json(packagePath),storage=await json(storagePath),source=await json(packaged.sourceManifest);
 must(packaged.mode==='preview'&&packaged.revision==='r5'&&packaged.current_source_match===true&&packaged.base_source_match===true&&packaged.entrypoint==='lib/main.dart'&&packaged.controlledEvidence===false&&packaged.nativeLaunched===false&&packaged.fullDesktopEvidence?.fullSuitePassed===true&&packaged.executableIdentity.packaged.CompanyName==='com.jentra.test'&&packaged.executableIdentity.packaged.ProductName==='JentraOS_WindowsTest_20261010-r5_Preview','VERIFIED_POSTAPPROVAL_PREVIEW_PACKAGE_REQUIRED');
 must(storage.revision==='r5'&&storage.allExpectedPathsAbsent===true&&storage.pathContentsRead===false&&storage.defaultAcceptanceStoresRead===false&&storage.localStoresCopied===false&&storage.OSUserCreated===false&&storage.paths.length===4&&new Set(storage.paths.map(p=>p.mode+':'+p.kind)).size===4&&storage.paths.every(p=>p.exists===false),'EXACT_NEW_PRELAUNCH_METADATA_REQUIRED');
 must(source.revision==='r5'&&source.controlledEvidence===false&&source.mode==='Preview'&&packaged.sourceManifestSha256===(await binding(packaged.sourceManifest)).sha256,'EXACT_PREVIEW_SOURCE_MANIFEST_REQUIRED');
 must((await binding(predecessor.path)).sha256===predecessor.sha256,'PRESERVED_PREDECESSOR_RECORDER_CHANGED');
 must((await binding(historicalPredecessor.path)).sha256===historicalPredecessor.sha256,'PRESERVED_HISTORICAL_PREDECESSOR_RECORDER_CHANGED');
 const actualExeSha=sha(await bytes(packaged.executable));must(actualExeSha===packaged.executableIdentity.packaged.sha256,'PACKAGED_EXECUTABLE_CHANGED');
 const record={kind:'actual-native-preview-userflow-observations',startedAt:new Date().toISOString(),revision:'r5',mode:'Preview',
  executable:packaged.executable,executableSha256:actualExeSha,package:await binding(packagePath),sourceManifest:{path:packaged.sourceManifest,sha256:packaged.sourceManifestSha256},
  prelaunchPathObservation:await binding(storagePath),recorder:await binding(helper),predecessor,historicalPredecessor,
  inputToolEvidence:structuredClone(inputToolEvidence),inputToolVersionIsSeparateFromProductSdk:true,
  productSdk:structuredClone(packaged.fullDesktopEvidence.toolchain.sdkMetadata),productSuiteObservedAt:packaged.fullDesktopEvidence.finishedAt,
  productBuildEvidence:{path:packaged.buildEvidence,sha256:packaged.buildEvidenceSha256},
  actorLabel:'unconfigured development Preview',observations:[],observedWindows:[],status:'in-progress',nativeLaunched:false,authenticatedNative:false,fullNativeKeyboardGate:false,
  accountingTransactionsPosted:false,authoritativeReportsGenerated:false,actualDelivery:false,realMfa:false,actualModelUsage:false,independentSessionContention:false,targetScaleLoad:false,
  ownerAcceptanceChanged:false,productionExcluded:true,realBillingExcluded:true,
  boundary:'Actual ordinary offline Preview observations only. The input API documentation/version observation, product SDK/build and native action timestamps are separate. This record cannot establish authenticated native, real accounting or whole-system acceptance.'};
 await assertBound(record,{source:true});await persist(record,{newFile:true});return record;
}
export async function resumePreviewEvidence(){const record=await json(output);must(record.status==='in-progress','COMPLETED_NATIVE_EVIDENCE_IS_IMMUTABLE');await assertBound(record,{source:true,screenshots:true});known.set(record,sha(await bytes(output)));return record;}
export async function bindPreviewWindow(record,returnedWindow){
 await active(record);must(Number.isInteger(returnedWindow?.id)&&normalized(returnedWindow.app??'')===normalized(record.executable)&&returnedWindow.title===title,'RETURNED_EXACT_R5_PROCESS_WINDOW_REQUIRED');
 if(!record.observedWindows.some(window=>window.id===returnedWindow.id&&window.app===returnedWindow.app))record.observedWindows.push({id:returnedWindow.id,app:returnedWindow.app,title:returnedWindow.title,boundAt:new Date().toISOString()});
 await persist(record);return{windowId:returnedWindow.id,app:returnedWindow.app};
}
export async function appendPreviewObservation(record,{id,action,expected,observed,result,state,inputApi=null}){
 await active(record);must(/^[A-Z][A-Z0-9_-]{1,49}$/.test(id)&&['pass','fail','blocked','observed'].includes(result)&&!record.observations.some(row=>row.id===id)&&[action,expected,observed].every(value=>typeof value==='string'&&value.trim())&&state?.window?.title===title&&record.observedWindows.some(window=>window.id===state.window.id&&window.app===state.window.app),'EXACT_NEW_ACTUAL_PREVIEW_OBSERVATION_REQUIRED');
 must(Array.isArray(state.screenshots)&&state.screenshots.length>0,'ACTUAL_VISUAL_EVIDENCE_REQUIRED');
 must(inputApi===null||['sky.press_key','sky.type_text','sky.click','sky.launch_app','sky.get_window_state','sky.perform_secondary_action','multiple-supported-sky-actions'].includes(inputApi),'DOCUMENTED_INPUT_API_LABEL_REQUIRED');
 const observedAt=new Date().toISOString(),screenshots=[];
 for(let index=0;index<state.screenshots.length;index++){
  const screenshot=state.screenshots[index],match=screenshot.url.match(/^data:image\/(png|jpeg);base64,([A-Za-z0-9+/=]+)$/s);must(match,'SUPPORTED_NATIVE_IMAGE_DATA_REQUIRED');
  const data=Buffer.from(match[2],'base64'),size=imageDimensions(data);must(data.toString('base64')===match[2]&&size.width===screenshot.width&&size.height===screenshot.height&&typeof screenshot.id==='string'&&screenshot.id,'ACTUAL_NATIVE_SCREENSHOT_METADATA_REQUIRED');
  const file=base+`native-preview-20261010-r5/${id}-${index}.${match[1]==='jpeg'?'jpg':'png'}`;
  await mkdir(path.dirname(inside(file)),{recursive:true});await writeFile(inside(file),data,{flag:'wx'});
  screenshots.push({path:file,sha256:sha(data),bytes:data.length,width:size.width,height:size.height,screenshotId:screenshot.id});
 }
 record.observations.push({id,observedAt,action,expected,observed,result,inputApi,window:{id:state.window.id,app:state.window.app,title:state.window.title},accessibility:state.accessibility,screenshots});
 record.nativeLaunched=true;await persist(record);return{id,result,screenshots:screenshots.map(row=>row.path),observations:record.observations.length};
}
export async function finishPreviewEvidence(record){
 await active(record);must(record.observations.length>0&&record.observations.every(row=>row.result!=='observed'),'ACTUAL_COMPLETED_CASES_REQUIRED');
 await assertBound(record,{source:true,screenshots:true});record.status='complete';record.finishedAt=new Date().toISOString();
 record.counts=Object.fromEntries(['pass','fail','blocked','observed'].map(result=>[result,record.observations.filter(row=>row.result===result).length]));
 await persist(record);return{path:output,sha256:sha(await bytes(output)),counts:record.counts,authenticatedNative:false,ownerAcceptanceChanged:false};
}
