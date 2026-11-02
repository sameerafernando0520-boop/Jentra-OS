import {constants} from 'node:fs';
import {copyFile,mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import assert from 'node:assert/strict';

const root=process.cwd();
const stage=path.join(root,'build/firebase-desktop/0.3.2-2305-development-55b9f85e70bc-1793280111153');
const native=path.join(root,'build/desktop-release/0.3.2-2305-development-20261029-131151-df77');
const web=path.join(root,'build/web-release/0.3.2-2305-development-20261029-131151-7492');
const evidence=path.join(root,'docs/verification/auth-installer-20261029-2305');
const output=path.join(root,'dist/Jentra-OS-0.3.2-2305-Development');
const json=async file=>JSON.parse(await readFile(file,'utf8'));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const manifest=await json(path.join(stage,'hosting-manifest.json'));
const delivery=await json(path.join(native,'delivery.json'));
const webDelivery=await json(path.join(web,'delivery.json'));
const staging=await json(path.join(native,'native-staging-verification.json'));
const preview=await json(path.join(stage,'preview-verification.json'));
const live=await json(path.join(stage,'live-verification.json'));
const previewAuth=await json(path.join(root,'build/auth-preview-browser-2305-rendered-message/preview-auth-verification.json'));
const liveAuth=await json(path.join(root,'build/auth-live-browser-2305/live-auth-verification.json'));
const deployment=await json(path.join(stage,'preview-deploy.json'));
const promotionText=await readFile(path.join(stage,'live-promotion.json'),'utf8');
const promotion=JSON.parse(promotionText.slice(promotionText.indexOf('{')));
const rollback=await json(path.join(stage,'rollback-live.json'));
const publicAuth=await json(path.join(root,'build/auth-public-settings-2305.json'));
assert.equal(delivery.identity.sourceSha256,webDelivery.identity.sourceSha256);
assert.equal(delivery.identity.sourceSha256,manifest.identity.sourceSha256);
assert.equal(delivery.identity.buildNumber,2305);
assert.equal(staging.passed,true);assert.equal(staging.verifiedFiles,48);
assert.equal(staging.registryChanged,false);assert.equal(staging.userProfileInstalled,false);
assert.equal(delivery.requiresDotNet,false);assert.equal(delivery.requiresPowerShell,false);
for(const proof of [preview,live]){
 assert.equal(proof.passed,true);assert.equal(proof.verifiedPublicFiles,manifest.files.length);
 assert.equal(proof.publicSha256,manifest.publicSha256);assert.equal(proof.passwordTypingVerified,true);
 assert.equal(proof.invalidSignupBlockedBeforeNetwork,true);assert.equal(proof.blockedWrites,0);
 assert.deepEqual(proof.consoleErrors,[]);assert.deepEqual(proof.failedRequests,[]);
}
for(const proof of [previewAuth,liveAuth]){
 assert.equal(proof.passed,true);assert.equal(proof.scenarios.length,4);
 assert.ok(proof.scenarios.every(item=>item.passed));
 assert.equal(proof.realEmailSent,false);assert.equal(proof.realAccountCreated,false);
}
assert.equal(deployment.result.desktop.version,'3759c87a7a2ec554');
assert.equal(promotion.status,'success');assert.equal(publicAuth.emailConfirmationRequired,true);
const tests=[['build/auth-repair-full-platform-20261029.log',1280],['build/auth-repair-full-desktop-20261029.log',2348],['build/auth-repair-platform-focused-2305.log',69],['build/auth-repair-desktop-focused-2305-corrected.log',40]];
for(const [file,count] of tests)assert.ok((await readFile(path.join(root,file),'utf8')).includes(`+${count}: All tests passed!`));
assert.match(await readFile(path.join(root,'build/auth-repair-analysis-clean-2305.log'),'utf8'),/No issues found!/);
assert.match(await readFile(path.join(root,'build/auth-repair-legacy-installer-2305.log'),'utf8'),/"passed": 14/);
assert.match(await readFile(path.join(root,'build/auth-repair-archive-2305.log'),'utf8'),/"passed": 3/);
const artifacts=[delivery.installer,delivery.portableZip,webDelivery.archive];
for(const artifact of artifacts){const bytes=await readFile(artifact.path);assert.equal(bytes.length,artifact.bytes);assert.equal(sha(bytes),artifact.sha256);}
const report={date:'2026-10-29',identity:delivery.identity,webUrl:live.origin,windowsDownloadUrl:live.origin+'/downloads/',firebaseVersion:'3759c87a7a2ec554',rollbackVersion:rollback.version,publicSha256:manifest.publicSha256,verifiedPublicFiles:manifest.files.length,fullTests:{platform:1280,desktop:2348,timing:'Before brace-only analyzer corrections; focused suites and clean analysis repeated afterward'},focusedTests:{platformAuth:69,desktopAuth:40},analysisClean:true,nativeStaging:staging,legacyRollbackChecks:14,archiveChecks:3,previewAuthPassed:true,liveAuthPassed:true,publicAuth,hostedAuthChanges:{approvedByOwner:true,siteUrl:'https://jentra-os-desktop.web.app/',redirectUrls:['https://jentra-os-desktop.web.app/','http://127.0.0.1:56327/auth/callback/*'],persistedAfterReload:true,smtpPublicFieldsPrepared:true,smtpSavedEnabled:false,smtpSavePerformedByAgent:false,smtpCredentialHandled:false,smtpDeliveryVerified:false},artifacts:artifacts.map(item=>({name:path.basename(item.path),bytes:item.bytes,sha256:item.sha256})),realEmailSent:false,realAccountCreated:false,otherPcAccepted:false,authenticode:'unsigned',migrationsInstalled:false,pushSenderDeployed:false,employeeSiteChanged:false,productionCertified:false};
await writeFile(path.join(evidence,'verification.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
for(const [source,name] of [[path.join(stage,'preview-verification.json'),'preview-verification.json'],[path.join(stage,'live-verification.json'),'live-verification.json'],[path.join(root,'build/auth-preview-browser-2305-rendered-message/preview-auth-verification.json'),'preview-auth-verification.json'],[path.join(root,'build/auth-live-browser-2305/live-auth-verification.json'),'live-auth-verification.json'],[path.join(native,'native-staging-verification.json'),'native-staging-verification.json'],[path.join(stage,live.screenshots[0]),'web-sign-in.png'],[path.join(stage,live.screenshots[1]),'web-signup-676.png']])await copyFile(source,path.join(evidence,name),constants.COPYFILE_EXCL);
await mkdir(output,{recursive:false});
for(const artifact of artifacts)await copyFile(artifact.path,path.join(output,path.basename(artifact.path)),constants.COPYFILE_EXCL);
await copyFile(path.join(evidence,'verification.json'),path.join(output,'verification.json'),constants.COPYFILE_EXCL);
await copyFile(path.join(root,'docs/user-guide/install-desktop-and-web.md'),path.join(output,'START HERE.md'),constants.COPYFILE_EXCL);
await copyFile(path.join(root,'tools/auth-readiness/README.md'),path.join(output,'PRIVATE EMAIL SETUP.md'),constants.COPYFILE_EXCL);
const names=[...artifacts.map(item=>path.basename(item.path)),'verification.json','START HERE.md','PRIVATE EMAIL SETUP.md'];
const hashes=[];for(const name of names)hashes.push(`${sha(await readFile(path.join(output,name)))}  ${name}`);
await writeFile(path.join(output,'CHECKSUMS.sha256'),hashes.join('\n')+'\n',{flag:'wx'});
console.log(JSON.stringify({output,evidence,version:delivery.identity.version,verifiedPublicFiles:manifest.files.length,nativeStagingPassed:true,productionCertified:false}));
