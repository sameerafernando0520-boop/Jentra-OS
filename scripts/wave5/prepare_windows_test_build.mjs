import {copyFile,lstat,mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const buildRoot=path.join(root,'build/w5win9b1');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const desktopMembers=['apps/jentra_desktop','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'];
const selected=p=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||
 desktopMembers.some(m=>p.startsWith(m+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p);
const jsonWrite=(p,value)=>writeFile(p,JSON.stringify(value,null,2)+'\n');
const exists=async p=>{try{await lstat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
if(await exists(buildRoot))throw Error('NEW_BUILD_DIRECTORY_REQUIRED');
const original=await sources(root);
const selectedOriginal=Object.fromEntries(Object.entries(original).filter(([p])=>selected(p)));
await mkdir(buildRoot,{recursive:true});
for(const mode of ['Preview','Connected']){
 const snapshot=path.join(buildRoot,mode.toLowerCase());
 await mkdir(snapshot);
 // Copy only repository sources and dependency manifests. No .env, AppData,
 // database, tokens, generated builds or other-chat state enter this package.
 for(const [p,h] of Object.entries(selectedOriginal)){
  const target=path.join(snapshot,p);await mkdir(path.dirname(target),{recursive:true});
  await copyFile(path.join(root,p),target);
  if(sha(await readFile(target))!==h)throw Error('SOURCE_CHANGED_DURING_COPY');
 }
 const company='com.jentra.test',product=`JentraOS_WindowsTest_20261009_${mode}`;
 const overlays=[];
 async function overlay(p,replace){
  const location=path.join(snapshot,p),before=await readFile(location,'utf8');
  const after=replace(before);if(after===before)throw Error('RUNNER_OVERLAY_MISSING');
  await writeFile(location,after);overlays.push({path:p,baseSha256:sha(Buffer.from(before)),buildSha256:sha(Buffer.from(after))});
 }
 await overlay('apps/jentra_desktop/windows/CMakeLists.txt',s=>s.replace('set(BINARY_NAME "jentra_desktop")','set(BINARY_NAME "Jentra_OS")'));
 await overlay('apps/jentra_desktop/windows/runner/Runner.rc',s=>s
  .replace('VALUE "CompanyName", "com.jentra"','VALUE "CompanyName", "'+company+'"')
  .replace('VALUE "ProductName", "jentra_desktop"','VALUE "ProductName", "'+product+'"')
  .replace('VALUE "FileDescription", "jentra_desktop"','VALUE "FileDescription", "Jentra OS Windows Test - '+mode+'"')
  .replace('VALUE "OriginalFilename", "jentra_desktop.exe"','VALUE "OriginalFilename", "Jentra_OS.exe"'));
 await overlay('apps/jentra_desktop/windows/runner/main.cpp',s=>s.replace('window.Create(L"jentra_desktop"','window.Create(L"Jentra OS - '+mode+' test"'));
 const buildHashes=Object.fromEntries(await Promise.all(Object.keys(selectedOriginal).map(async p=>[p,sha(await readFile(path.join(snapshot,p)))])));
 await jsonWrite(path.join(root,base+`windows-test-${mode.toLowerCase()}-source-20261009.json`),{
  capturedAt:new Date().toISOString(),workspace:root,snapshot,mode,entrypoint:'lib/main.dart',controlledEvidence:false,
  baseSourceHashes:selectedOriginal,buildSourceHashes:buildHashes,overlays,
  desktopDependencyScope:desktopMembers,allWorkspaceManifestsIncluded:true,
  stores:{company,product,applicationSupport:`%APPDATA%\\${company}\\${product}`,
   applicationCache:`%LOCALAPPDATA%\\${company}\\${product}`,secureStorage:'DPAPI file in the same unique applicationSupport directory; WindowsOptions defaults to no legacy migration',
   defaultAcceptanceIdentity:'com.jentra/jentra_desktop',defaultStoresRead:false,newOsUserCreated:false},
  projectId:mode==='Connected'?'xpdoufauvrbdmxgngetv':null,
  previewData:mode==='Preview',authenticatedAcceptance:false,realMfa:false,ownerAccepted:false
 });
}
const fresh=await sources(root);
const drift=Object.keys(selectedOriginal).filter(p=>fresh[p]!==selectedOriginal[p]);
if(drift.length)throw Error('DESKTOP_SOURCES_CHANGED_DURING_PREPARATION');
console.log(JSON.stringify({buildRoot,modes:['Preview','Connected'],selectedSources:Object.keys(selectedOriginal).length,sourceStable:true,sharedSourceChanged:false}));
