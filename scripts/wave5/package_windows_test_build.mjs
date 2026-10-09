import {copyFile,lstat,mkdir,readFile,readdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const mode=process.argv[2];if(!['preview','connected'].includes(mode))throw Error('PACKAGE_MODE_REQUIRED');
const readJson=async p=>JSON.parse(await readFile(path.join(root,p),'utf8'));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const source=await readJson(base+`windows-test-${mode}-source-20261009.json`);
const snapshot=source.snapshot;
const sourceChanges=[];
for(const [p,h] of Object.entries(source.buildSourceHashes)){
 if(sha(await readFile(path.join(snapshot,p)))!==h)sourceChanges.push(p);
 if(sha(await readFile(path.join(root,p)))!==source.baseSourceHashes[p])sourceChanges.push('workspace:'+p);
}
if(sourceChanges.length)throw Error('BUILD_SOURCE_DRIFT');
const current=await sources(root);
const members=source.desktopDependencyScope;
const additionalSources=Object.keys(current).filter(p=>members.some(m=>p.startsWith(m+'/'))&&!source.baseSourceHashes[p]);
if(additionalSources.length)throw Error('NEW_DESKTOP_SOURCE_REQUIRES_REBUILD');
const build=await readJson(base+`windows-test-${mode}-build-20261009.json`);
if(build.exitCode!==0||!String(await readFile(path.join(root,build.log))).includes('Built build'))throw Error('BUILD_NOT_PASSED');
const release=path.join(snapshot,'apps/jentra_desktop/build/windows/x64/runner/Release');
const packageRoot=path.join(root,'dist/Jentra OS Windows Test 20261009');
const target=path.join(packageRoot,mode==='preview'?'Preview':'Connected');
try{await lstat(target);throw Error('PACKAGE_ALREADY_EXISTS');}catch(e){if(e.code!=='ENOENT')throw e;}
await mkdir(target,{recursive:true});
const releaseFiles=[];
async function copyDirectory(directory){
 for(const entry of await readdir(directory,{withFileTypes:true})){
  if(entry.isSymbolicLink())throw Error('RELEASE_LINK_REFUSED');
  const full=path.join(directory,entry.name),relative=path.relative(release,full);
  const destination=path.join(target,relative);
  if(path.relative(target,destination).startsWith('..'))throw Error('PACKAGE_PATH_ESCAPE');
  if(entry.isDirectory()){await mkdir(destination);await copyDirectory(full);}
  else{
   const bytes=await readFile(full);await copyFile(full,destination);
   if(sha(await readFile(destination))!==sha(bytes))throw Error('COPIED_RELEASE_HASH_CHANGED');
   releaseFiles.push({path:relative.split(path.sep).join('/'),sha256:sha(bytes),bytes:bytes.length});
  }
 }
}
await copyDirectory(release);releaseFiles.sort((a,b)=>a.path.localeCompare(b.path));
if(!releaseFiles.some(f=>f.path==='Jentra_OS.exe'))throw Error('NATIVE_EXECUTABLE_MISSING');
const evidence={builtAt:new Date().toISOString(),mode,entrypoint:'lib/main.dart',controlledEvidence:false,
 projectId:source.projectId,sourceManifest:base+`windows-test-${mode}-source-20261009.json`,sourceHashes:source.baseSourceHashes,
 base_source_match:true,current_source_match:true,buildSourceHashes:source.buildSourceHashes,runnerOverlays:source.overlays,
 sourceAttributionScope:'Desktop transitive workspace source and all workspace dependency manifests; three declared runner identity overlays only in the build copy',
 packageDirectory:target,releaseDirectory:release,executable:path.join(target,'Jentra_OS.exe'),releaseFiles,buildEvidence:base+`windows-test-${mode}-build-20261009.json`,
 storageIdentity:source.stores,publicKeyOnly:mode==='connected',previewData:mode==='preview',nativeLaunched:false,authenticatedNativeAcceptance:false,
 realMfa:false,actualWorkerDelivery:false,independentSessionContention:false,targetScaleLoad:false,ownerAccepted:false,newMigrationsInstalled:false};
await writeFile(path.join(root,base+`windows-test-${mode}-package-20261009.json`),JSON.stringify(evidence,null,2)+'\n');
await writeFile(path.join(target,'release-manifest.json'),JSON.stringify({mode,storageIdentity:source.stores,releaseFiles},null,2)+'\n');
console.log(JSON.stringify({mode,packageDirectory:target,releaseFiles:releaseFiles.length,baseSourceMatch:true,runnerIdentityOverlays:3,bytes:releaseFiles.reduce((a,f)=>a+f.bytes,0)}));
