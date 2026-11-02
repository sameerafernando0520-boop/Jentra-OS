import {constants} from 'node:fs';
import {copyFile, readFile, writeFile, readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import path from 'node:path';
const root=process.cwd();
const proof=path.join(root,'docs/verification/desktop-web-20261029');
const output=path.join(root,'dist/Jentra-OS-0.3.1-2302-Development');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const delivery=JSON.parse(await readFile(path.join(output,'delivery.json'),'utf8'));
for(const file of delivery.files){
 const bytes=await readFile(path.join(output,file.name));
 assert.equal(bytes.length,file.bytes,file.name);assert.equal(sha(bytes),file.sha256,file.name);
}
const storage=JSON.parse(await readFile(path.join(proof,'browser-storage-probe.json'),'utf8'));
const smoke=JSON.parse(await readFile(path.join(proof,'web-smoke.json'),'utf8'));
assert.equal(storage.passed,true);assert.equal(storage.scenarios.length,4);assert.deepEqual(storage.consoleErrors,[]);
assert.equal(smoke.passed,true);assert.deepEqual(smoke.consoleErrors,[]);assert.deepEqual(smoke.failedRequests,[]);
for(const name of ['README.md','browser-storage-probe.json','web-smoke.json']){
 await copyFile(path.join(proof,name),path.join(output,name==='README.md'?'Verification.md':name),constants.COPYFILE_EXCL);
}
const guidePath=path.join(output,'Detailed Install Guide.md');
let guide=await readFile(guidePath,'utf8');
guide=guide.replace('(README.md)','(<Company Setup and Operating Guide.docx>)')
 .replace('(company-access-administration.md)','(<Company Access Administration Addendum.docx>)')
 .replace('[feature completeness record](feature-completeness.md)','[release limits](<START HERE.md>)')
 .replace('[launch readiness record](../development/launch-readiness-20261028.md)','[delivery verification](Verification.md)');
await writeFile(guidePath,guide);
await writeFile(path.join(output,'START HERE.md'),(await readFile(path.join(output,'START HERE.md'),'utf8'))+'\nFour shared browser storage scenarios also passed through a compiled release probe: protected key reopen, competing lease, missing-key preservation and exact encrypted SQLite command recovery. Read Verification.md for detailed scope and the SDK test-harness limitation.\n');
delivery.verification={installerStaged:true,runtimeFiles:47,installerAssertions:14,zipAssertions:3,platformTests:1262,focusedDesktopTests:73,browserStorageScenarios:4,webSignInSmoke:true,analysisClean:true,authenticatedNativeAcceptance:false,userProfileInstalled:false,publicHosting:false};
delivery.files=[];
for(const name of (await readdir(output)).sort()){
 if(['CHECKSUMS.sha256','delivery.json'].includes(name))continue;
 const bytes=await readFile(path.join(output,name));
 delivery.files.push({name,bytes:bytes.length,sha256:sha(bytes)});
}
await writeFile(path.join(output,'delivery.json'),JSON.stringify(delivery,null,2)+'\n');
const finalManifest=await readFile(path.join(output,'delivery.json'));
await writeFile(path.join(output,'CHECKSUMS.sha256'),[...delivery.files,{name:'delivery.json',sha256:sha(finalManifest)}].map(file=>`${file.sha256}  ${file.name}`).join('\n')+'\n');
console.log(JSON.stringify({directory:output,verifiedFiles:delivery.files.length+1,verification:delivery.verification,companyLaunchComplete:false}));
