import {constants} from 'node:fs';
import {copyFile,mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=process.cwd();
const stage=path.join(root,'build/firebase-desktop/0.3.1-2303-development-bdde547047e5-1793270874919');
const web=path.join(root,'build/web-release/0.3.1-2303-development-20261029-104501-2713');
const evidence=path.join(root,'docs/verification/firebase-web-20261029');
const output=path.join(root,'dist/Jentra-OS-Web-0.3.1-2303-Development');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=async file=>JSON.parse(await readFile(file,'utf8'));
const [preview,live,manifest,delivery,deployment]=await Promise.all([
 json(path.join(stage,'preview-verification.json')),json(path.join(stage,'live-verification.json')),
 json(path.join(stage,'hosting-manifest.json')),json(path.join(web,'delivery.json')),json(path.join(stage,'preview-deploy.json')),
]);
for(const proof of [preview,live]){
 assert.equal(proof.passed,true);assert.equal(proof.formEmailAccepted,true);assert.equal(proof.passwordTypingVerified,true);
 assert.equal(proof.verifiedPublicFiles,58);assert.equal(proof.blockedWrites,0);
 assert.deepEqual(proof.consoleErrors,[]);assert.deepEqual(proof.failedRequests,[]);
 assert.equal(proof.publicSha256,manifest.publicSha256);
}
assert.equal(deployment.result.desktop.version,'96336e1a1ad6619c');
assert.match(await readFile(path.join(stage,'live-promotion.json'),'utf8'),/"status": "success"/);
assert.match(await readFile(path.join(root,'build/auth-password-tests-20261029-2303.log'),'utf8'),/\+39: All tests passed!/);
assert.match(await readFile(path.join(root,'build/auth-password-analysis-20261029-2303.log'),'utf8'),/No issues found!/);
const report={date:'2026-10-29',url:live.origin,firebaseProject:'jentra-os',hostingSite:'jentra-os-desktop',version:delivery.identity.version,firebaseVersion:'96336e1a1ad6619c',identity:delivery.identity,publicSha256:manifest.publicSha256,verifiedFiles:58,previewPassed:true,livePassed:true,passwordVisibility:true,signupFormPolicy:'12 Unicode code points; letters, decimal digits and punctuation/symbols',validEmailRetained:true,invalidPasswordRejectedBeforeNetwork:true,focusedAuthTests:39,analysisClean:true,webZip:delivery.archive,employeeHostingPreserved:true,realLoginPerformed:false,backendChanged:false,migrationInstalled:false,senderDeployed:false,companyLaunchComplete:false,serverPasswordPolicyChanged:false,hostedOAuthAndEmailRedirectAcceptance:false};
await writeFile(path.join(evidence,'verification.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
for(const [source,destination] of [['live-verification.json','live-verification.json'],['preview-verification.json','preview-verification.json']])await copyFile(path.join(stage,source),path.join(evidence,destination),constants.COPYFILE_EXCL);
await copyFile(path.join(stage,live.screenshots[0]),path.join(evidence,'web-sign-in.png'),constants.COPYFILE_EXCL);
await copyFile(path.join(stage,live.screenshots[1]),path.join(evidence,'web-signup-676.png'),constants.COPYFILE_EXCL);
await mkdir(output,{recursive:false});
const zip=await readFile(delivery.archive.path);
assert.equal(sha(zip),delivery.archive.sha256);assert.equal(zip.length,delivery.archive.bytes);
await copyFile(delivery.archive.path,path.join(output,path.basename(delivery.archive.path)),constants.COPYFILE_EXCL);
await copyFile(path.join(evidence,'verification.json'),path.join(output,'verification.json'),constants.COPYFILE_EXCL);
const guide=`# Jentra OS web app\n\nOpen https://jentra-os-desktop.web.app in current Chrome or Edge. Version 0.3.1+2303 Development. Firebase hosts the client; the existing Supabase Development project still handles accounts and company records. Sign in with your own verified account and select the correct company/entity/branch.\n\nUse the eye beside Password or Confirm password to show/hide that field. New-account forms require at least 12 characters, letters, numbers and symbols. Existing account passwords remain usable for sign-in. Hosted password-strength settings, Google and email callback acceptance remain separate backend checks.\n\nUse one editing tab. Before changing from localhost to Firebase, reconcile unconfirmed commands on the original address. Browser recovery is origin-scoped and does not transfer automatically.\n\nThe included Web ZIP is an optional local/portable copy. Extract it and double-click Start Jentra OS Web.cmd; keep its console open. Internet is required for company operations.\n\nVerification: 39 focused auth tests; clean analysis; 58 actual served files matched hashes on preview and live; password eyes and invalid signup checked in fresh Chrome; no real registration/email or backend writes. The Firebase site version is 96336e1a1ad6619c. No database migration or sender was deployed. Remaining company-launch gates still apply.\n`;
await writeFile(path.join(output,'START HERE.md'),guide,{flag:'wx'});
const names=[path.basename(delivery.archive.path),'verification.json','START HERE.md'];
const hashes=[];
for(const name of names)hashes.push(`${sha(await readFile(path.join(output,name)))}  ${name}`);
await writeFile(path.join(output,'CHECKSUMS.sha256'),hashes.join('\n')+'\n',{flag:'wx'});
console.log(JSON.stringify({url:report.url,version:report.version,verifiedFiles:58,focusedAuthTests:39,output,evidence,backendChanged:false}));
