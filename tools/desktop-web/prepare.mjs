import {createHash} from 'node:crypto';
import {copyFile, lstat, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {assertPublicContent} from '../employee-web/prepare.mjs';

const tool=path.dirname(fileURLToPath(import.meta.url));
const repo=path.resolve(tool,'../..');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=async file=>JSON.parse(await readFile(file,'utf8'));
const excluded=new Set(['site/.last_build_id','site/_headers','site/_redirects']);

function publicPath(relative){
  if(!relative.startsWith('site/')||relative.includes('\\')||relative.split('/').some(part=>!part||part==='.'||part==='..'))throw Error('Invalid public artifact path.');
  return relative.slice(5);
}
async function readFileTree(root,prefix=''){
  const files=[];
  for(const item of await readdir(path.join(root,prefix),{withFileTypes:true})){
    const relative=prefix+item.name;
    if(/\.(exe|dll|bat|apk|ipa)$/i.test(relative))throw Error('Executable file type is not supported by the current Firebase Spark plan.');
    if(item.isDirectory())files.push(...await readFileTree(root,relative+'/'));
    else if(item.isFile()){
      const bytes=await readFile(path.join(root,relative));
      assertPublicContent(bytes,relative);
      files.push({path:relative,bytes:bytes.length,sha256:digest(bytes)});
    }else throw Error('Non-regular public artifact rejected.');
  }
  return files.sort((a,b)=>a.path.localeCompare(b.path));
}
export async function stageRelease(releaseDirectory,windowsReleaseDirectory){
  const input=path.resolve(releaseDirectory);
  const delivery=await json(path.join(input,'delivery.json'));
  const identity=delivery.identity;
  if(delivery.platform!=='web'||identity.channel!=='development'||identity.projectRef!=='xpdoufauvrbdmxgngetv'||!/^[a-f0-9]{64}$/.test(identity.sourceSha256))throw Error('Reviewed Development web release required.');
  const output=path.join(repo,'build/firebase-desktop',`${identity.releaseId}-${Date.now()}`);
  await mkdir(output,{recursive:true});
  await mkdir(path.join(output,'public'));
  for(const file of delivery.files.filter(file=>file.path.startsWith('site/')&&!excluded.has(file.path))){
    const relative=publicPath(file.path);
    const source=path.join(input,'package',file.path);
    const info=await lstat(source);
    if(!info.isFile()||info.isSymbolicLink())throw Error('Regular reviewed release file required.');
    const bytes=await readFile(source);
    if(bytes.length!==file.bytes||digest(bytes)!==file.sha256)throw Error('Reviewed release changed before staging.');
    assertPublicContent(bytes,relative);
    const destination=path.join(output,'public',relative);
    await mkdir(path.dirname(destination),{recursive:true});
    await writeFile(destination,bytes,{flag:'wx'});
  }
  const root=path.join(output,'public');
  for(const required of ['index.html','main.dart.js','flutter_bootstrap.js','manifest.json','canvaskit/chromium/canvaskit.wasm','assets/packages/jentra_platform/assets/web/sqlite3.wasm','assets/packages/jentra_platform/assets/web/drift_worker.js'])await lstat(path.join(root,required));
  const index=await readFile(path.join(root,'index.html'),'utf8');
  if(!index.includes('<base href="/">'))throw Error('Hosting origin-root build required.');
  const program=await readFile(path.join(root,'main.dart.js'),'utf8');
  if(!program.includes('https://xpdoufauvrbdmxgngetv.supabase.co'))throw Error('Expected Development backend missing.');
  const main=await readFile(path.join(root,'main.dart.js'));
  await writeFile(path.join(root,'release.json'),JSON.stringify({identity,hostingProject:'jentra-os',hostingSite:'jentra-os-desktop',mainDartJsSha256:digest(main),companyLaunchComplete:false},null,2)+'\n',{flag:'wx'});
  await writeFile(path.join(root,'404.html'),'<!doctype html><html lang="en"><meta charset="utf-8"><title>Not found · Jentra OS</title><h1>Page not found</h1><p>Return to <a href="/">Jentra OS</a>.</p></html>\n',{flag:'wx'});
  await writeFile(path.join(root,'robots.txt'),'User-agent: *\nDisallow: /\n',{flag:'wx'});
  let desktopDownloads;
  if(windowsReleaseDirectory){
    const nativeRoot=path.resolve(windowsReleaseDirectory);
    const desktop=await json(path.join(nativeRoot,'delivery.json'));
    const proof=await json(path.join(nativeRoot,'native-staging-verification.json'));
    if(desktop.identity.sourceSha256!==identity.sourceSha256||desktop.identity.buildNumber!==identity.buildNumber||desktop.identity.channel!=='development'||desktop.installerKind!=='native-inno'||!proof.passed||proof.releaseId!==desktop.identity.releaseId)throw Error('Matching, staged native Windows release required.');
    const downloads=path.join(root,'downloads');await mkdir(downloads);
    const stem=`Jentra-OS-${identity.versionName}-${identity.buildNumber}-Development`;
    const artifacts=[];
    // Publish the existing portable archive in its normal format. The native
    // installer remains a separate local artifact; Spark forbids raw EXE files.
    for(const [artifact,name] of [[desktop.portableZip,`${stem}-Windows.zip`]]){
      const info=await lstat(artifact.path);
      if(!info.isFile()||info.isSymbolicLink())throw Error('Regular native release file required.');
      const bytes=await readFile(artifact.path);
      if(bytes.length!==artifact.bytes||digest(bytes)!==artifact.sha256)throw Error('Native release artifact changed.');
      await writeFile(path.join(downloads,name),bytes,{flag:'wx'});
      artifacts.push({path:name,bytes:bytes.length,sha256:digest(bytes)});
    }
    desktopDownloads={identity:desktop.identity,distribution:'portable-zip',nativeInstallerHosted:false,unsigned:desktop.unsigned,portableLauncher:'Launch.cmd',requiresDotNet:false,requiresPowerShell:false,stagingPassed:true,otherPcAccepted:false,artifacts};
    await writeFile(path.join(downloads,'release.json'),JSON.stringify(desktopDownloads,null,2)+'\n',{flag:'wx'});
    await writeFile(path.join(downloads,'checksums.sha256'),artifacts.map(file=>`${file.sha256}  ${file.path}`).join('\n')+'\n',{flag:'wx'});
    const html=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Jentra OS desktop download</title><style>body{max-width:780px;margin:64px auto;padding:24px;font:17px/1.6 system-ui;color:#10273d;background:#f2f6fa}a{color:#075fc7}.button{display:inline-block;padding:12px 20px;background:#075fc7;color:white;text-decoration:none;border-radius:8px}section{padding:28px;background:white;border-radius:14px}</style><section><h1>Jentra OS for Windows</h1><p>Version ${identity.version} · Development · Windows 10/11, 64-bit</p><p><a class="button" href="${artifacts[0].path}">Download Windows ZIP</a></p><p>Extract the <strong>whole ZIP</strong>, then double-click <strong>Launch.cmd</strong>. Keep Payload and all its files together. This portable launcher needs no .NET or PowerShell. Internet is required for account and company operations.</p><p>This build is unsigned. Company security policy may require an approved signed release; contact your IT administrator if Windows blocks it. Do not disable security software.</p><h2>Native installer</h2><p>A separate native Setup.exe is included in the local release handoff. Firebase's current Spark plan does not host raw Windows executables. The ZIP above contains the portable application, not the native installer.</p><p><a href="checksums.sha256">SHA-256 checksums</a> · <a href="release.json">Release identity</a> · <a href="/">Open the web app</a></p><p>The application uses the existing Development backend. Signing, real-company acceptance and verified mail delivery remain separate launch gates.</p></section></html>`;
    await writeFile(path.join(downloads,'index.html'),html+'\n',{flag:'wx'});
  }
  for(const name of ['firebase.json','.firebaserc'])await copyFile(path.join(tool,name),path.join(output,name));
  const files=await readFileTree(root);
  const manifest={identity,project:'jentra-os',site:'jentra-os-desktop',target:'desktop',originalRelease:input,createdAtUtc:new Date().toISOString(),hostingConfigSha256:digest(await readFile(path.join(output,'firebase.json'))),targetConfigSha256:digest(await readFile(path.join(output,'.firebaserc'))),publicSha256:digest(JSON.stringify(files)),files,desktopDownloads,backendChanged:false};
  await writeFile(path.join(output,'hosting-manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  return {releaseDirectory:output,site:manifest.site,files:files.length,publicSha256:manifest.publicSha256};
}
export async function verifyRelease(directory){
  const root=path.resolve(directory);
  const manifest=await json(path.join(root,'hosting-manifest.json'));
  if(manifest.project!=='jentra-os'||manifest.site!=='jentra-os-desktop'||manifest.identity.channel!=='development')throw Error('Unexpected Hosting destination.');
  const files=await readFileTree(path.join(root,'public'));
  if(JSON.stringify(files)!==JSON.stringify(manifest.files)||digest(JSON.stringify(files))!==manifest.publicSha256)throw Error('Staged public files changed.');
  for(const [file,key] of [['firebase.json','hostingConfigSha256'],['.firebaserc','targetConfigSha256']]){
    const bytes=await readFile(path.join(root,file));
    if(digest(bytes)!==manifest[key]||!bytes.equals(await readFile(path.join(tool,file))))throw Error('Reviewed Hosting configuration changed.');
  }
  return {releaseDirectory:root,publicSha256:manifest.publicSha256,files:files.length,site:manifest.site};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const [mode,directory,native]=process.argv.slice(2);
 if(!['stage','verify'].includes(mode)||!directory||process.argv.length<4||process.argv.length>5||mode==='verify'&&native)throw Error('Usage: node tools/desktop-web/prepare.mjs stage <web-release-directory> [native-release-directory] | verify <hosting-release-directory>');
 console.log(JSON.stringify(await(mode==='stage'?stageRelease(directory,native):verifyRelease(directory))));
}
