import {copyFile, mkdir, readFile, writeFile, stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import path from 'node:path';

const root=process.cwd();
const native=path.join(root,'build/desktop-release/0.3.1-2302-development-20261029-080935-9c39');
const web=path.join(root,'build/web-release/0.3.1-2302-development-20261029-083551-7c02');
const output=path.join(root,'dist/Jentra-OS-0.3.1-2302-Development');
const readJson=async file=>JSON.parse(await readFile(file,'utf8'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const [windowsDelivery,webDelivery,windowsSource,webSource]=await Promise.all([
 readJson(path.join(native,'delivery.json')),readJson(path.join(web,'delivery.json')),
 readJson(path.join(native,'source-manifest.json')),readJson(path.join(web,'source-manifest.json')),
]);
assert.equal(windowsDelivery.identity.channel,'development');
assert.equal(webDelivery.identity.channel,'development');
assert.equal(windowsDelivery.identity.projectRef,webDelivery.identity.projectRef);
const previous=new Map(windowsSource.buildFiles.map(file=>[file.path,file.sha256]));
const differences=webSource.buildFiles.filter(file=>previous.get(file.path)!==file.sha256).map(file=>file.path);
assert.ok(differences.every(file=>file.startsWith('tools/web-release/')),'Compiled application sources must match both client releases');
assert.equal(windowsSource.buildFiles.length,webSource.buildFiles.length);
await mkdir(output,{recursive:false});
const files=[];
async function include(source,name,expected){
 const bytes=await readFile(source);
 if(expected){assert.equal(hash(bytes),expected.sha256);assert.equal(bytes.length,expected.bytes);}
 await copyFile(source,path.join(output,name));
 const copied=await readFile(path.join(output,name));
 assert.equal(hash(bytes),hash(copied));
 files.push({name,bytes:copied.length,sha256:hash(copied)});
}
for(const artifact of [windowsDelivery.installer,windowsDelivery.portableZip,webDelivery.archive])await include(artifact.path,path.basename(artifact.path),artifact);
await include(path.join(root,'docs/user-guide/Jentra OS Company Setup and Operating Guide.docx'),'Company Setup and Operating Guide.docx');
await include(path.join(root,'docs/user-guide/Jentra OS Company Access Administration Addendum.docx'),'Company Access Administration Addendum.docx');
await include(path.join(root,'docs/user-guide/install-desktop-and-web.md'),'Detailed Install Guide.md');
await include(path.join(root,'docs/verification/desktop-web-20261029/web-sign-in-1440.png'),'Web Sign-in Preview.png');
await include(path.join(native,'build-identity.json'),'windows-build-identity.json');
await include(path.join(web,'build-identity.json'),'web-build-identity.json');
await include(path.join(native,'source-manifest.json'),'windows-source-manifest.json');
await include(path.join(web,'source-manifest.json'),'web-source-manifest.json');
const setup=path.basename(windowsDelivery.installer.path);
const webZip=path.basename(webDelivery.archive.path);
const portable=path.basename(windowsDelivery.portableZip.path);
const quick=`# Jentra OS 0.3.1+2302 Development\n\nPrepared 29 October 2026. Existing Development backend; unsigned Windows installer.\nAll company-launch gates are not complete.\n\n## Install Windows\n\nRun ${setup}. Open Jentra OS (Development) from Start, sign in with your own verified account, complete MFA and select the correct company/entity/branch. No backend is installed by this setup. The Windows ZIP is an alternative containing the same runtime and scripts.\n\n## Open the web app\n\nExtract ${webZip} completely and double-click Start Jentra OS Web.cmd. Keep its console open. Open http://127.0.0.1:8485/ in current Chrome or Edge. Close the console to stop. Internet is required for company operations. Use one editing tab and allow persistent storage; do not clear browser data while a command is unconfirmed.\n\nTo host for other users, publish only the ZIP's site folder to a reviewed HTTPS host and apply its supplied headers/routing. This task has not published a public website. Confirm the real backend and auth redirect allowlist before company use.\n\n## Instructions\n\nRead Company Setup and Operating Guide.docx and Company Access Administration Addendum.docx together. Detailed Install Guide.md contains installation, browser storage and hosting notes. All files have SHA-256 hashes in CHECKSUMS.sha256. Development installs separately from a Production-channel client; it still connects to the existing Development database.\n\n## Remaining launch work\n\nSeparate Jentra Sales app; reviewed company/access and employee backend rollout; hosted AI verification; push activation; statutory payroll approval; restoration and monitoring; signing; real-company pilot acceptance. Named test-company cleanup also remains pending verified project and company inventory. No migration was installed, sender deployed or company/account deleted by this delivery.\n\n## Verification limits\n\nRelease builds compiled. Actual Setup.exe staged successfully without profile installation, shortcuts or registry changes. The installed runtime's 47 files verified; 14 installer rollback checks and 3 ZIP checks passed. 1262 platform and 73 focused desktop tests passed; static analysis clean. Actual compiled web sign-in rendered in fresh Chrome with no runtime/console errors or failed requests. This does not establish authenticated company workflows or production readiness.\n`;
await writeFile(path.join(output,'START HERE.md'),quick,{flag:'wx'});
files.push({name:'START HERE.md',bytes:Buffer.byteLength(quick),sha256:hash(quick)});
const html=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Jentra OS downloads</title><style>body{margin:0;background:#eef3f8;color:#10273d;font:17px/1.6 system-ui}main{max-width:900px;margin:60px auto;padding:36px;background:white;border-radius:20px}h1{line-height:1.2}a{color:#075dc3}.button{display:inline-block;margin:8px 12px 8px 0;padding:12px 18px;border-radius:9px;background:#075dc3;color:white;text-decoration:none}.notice{padding:16px;background:#fff4d6;border-radius:10px}img{max-width:100%;border-radius:10px}small{color:#536578}</style><main><small>JENTRA OS · 29 OCTOBER 2026</small><h1>Desktop and web app</h1><p>Version 0.3.1+2302 · Development</p><p class="notice">These clients connect to the existing Development backend. The Windows installer is unsigned. Company-launch gates remain open.</p><p><a class="button" href="${setup}" download>Windows installer</a><a class="button" href="${webZip}" download>Web app ZIP</a><a href="${portable}" download>Windows ZIP</a></p><h2>Get started</h2><p>Windows: run Setup.exe, then open <strong>Jentra OS (Development)</strong> from Start.</p><p>Web: extract the Web ZIP and double-click <strong>Start Jentra OS Web.cmd</strong>. Keep its console open and visit <strong>http://127.0.0.1:8485/</strong>. This is local access; the web app has not been published to an Internet domain.</p><p><a href="Company%20Setup%20and%20Operating%20Guide.docx">Company operating guide</a> · <a href="Company%20Access%20Administration%20Addendum.docx">Administration addendum</a> · <a href="START%20HERE.md">Read release limits</a> · <a href="CHECKSUMS.sha256">SHA-256 checksums</a></p><img src="Web%20Sign-in%20Preview.png" alt="Verified Jentra OS Development sign-in screen"><h2>Still required before company launch</h2><p>Sales mobile app, reviewed backend rollout, hosted AI and push verification, statutory payroll approval, recovery and monitoring, signing and real-company pilot acceptance.</p><small>No migration installed, sender deployed or company/account deleted.</small></main></html>`;
await writeFile(path.join(output,'index.html'),html,{flag:'wx'});
files.push({name:'index.html',bytes:Buffer.byteLength(html),sha256:hash(html)});
await writeFile(path.join(output,'CHECKSUMS.sha256'),files.map(file=>`${file.sha256}  ${file.name}`).join('\n')+'\n',{flag:'wx'});
const result={version:'0.3.1+2302',channel:'development',directory:output,files,windowsSource:windowsDelivery.identity.sourceSha256,webSource:webDelivery.identity.sourceSha256,toolingDifferences:differences,compiledApplicationSourcesMatch:true,hosted:false,unsigned:true,backendChanged:false,companyLaunchComplete:false};
await writeFile(path.join(output,'delivery.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({directory:output,files:files.length,compiledApplicationSourcesMatch:true,artifactsVerified:3,companyLaunchComplete:false}));
