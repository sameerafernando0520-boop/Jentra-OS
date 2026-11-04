import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=process.cwd();
const load=async file=>JSON.parse((await readFile(file,'utf8')).replace(/^\uFEFF/,''));
const before=await load('build/sales-release/reviewed-input-manifest-20261030.json');
const after=await load('build/sales-release/after-input-manifest-20261030.json');
assert.equal(after.sourceSha256,before.sourceSha256,'Source changed across compilation');
const deliverySource=await load('build/sales-release/delivery-input-manifest-20261030.json');
assert.equal(deliverySource.sourceSha256,before.sourceSha256,'Delivery source differs');
const finalSource=await load('build/sales-release/final-input-manifest-20261031.json');
assert.equal(finalSource.sourceSha256,before.sourceSha256,'Final workspace source differs');
const tests=await readFile('build/sales-release/tests-reviewed-20261030.log','utf8');
const analyzer=await readFile('build/sales-release/analyzer-reviewed-20261030.log','utf8');
assert.match(tests,/\+19: All tests passed!/);assert.match(analyzer,/No issues found!/);
const preview=await load('build/sales-release/preview-hosting-accepted-20261031.json');
const live=await load('build/sales-release/live-hosting-verification.json');
assert.equal(preview.passed,true);assert.equal(live.passed,true);
assert.deepEqual(live.files,preview.files,'Preview/live public content differs');
const browserPreview=await load('output/playwright/jentra-sales-preview-accepted-r2/browser-verification.json');
const browserLive=await load('output/playwright/jentra-sales-live-final-tcp-r4/browser-verification.json');
const normalLive=await load('output/playwright/jentra-sales-live-accepted-r3/browser-verification.json');
assert.equal(browserPreview.baseUrl,preview.baseUrl);assert.equal(browserLive.baseUrl,live.baseUrl);
const defaultBrowser=await load('output/playwright/jentra-sales-preview-final/browser-verification.json');
const parseCli=async file=>{const raw=(await readFile(file,'utf8')).replace(/^\uFEFF/,'');return JSON.parse(raw.slice(raw.indexOf('{'),raw.lastIndexOf('}')+1));};
const deployed=await parseCli('build/sales-release/firebase-preview-final-20261030.json');
const promoted=await parseCli('build/sales-release/firebase-live-20261030.json');
const restored=await parseCli('build/sales-release/firebase-preview-restored-20261031.json');
assert.equal(deployed.status,'success');assert.equal(promoted.status,'success');
assert.equal(restored.status,'success');
assert.equal(deployed.result.sales.site,'jentra-os-sales');
assert.equal(deployed.result.sales.url,preview.baseUrl);
assert.match(deployed.result.sales.version,/^[a-f0-9]{16}$/);
assert.ok(!browserPreview.launchArgs.includes('--disable-quic'));
assert.ok(browserLive.launchArgs.includes('--disable-quic'));
for(const record of [browserPreview,browserLive]) {
  assert.equal(record.results.length,3);
  for(const result of record.results) {
    assert.equal(result.passed,true,result.name);assert.deepEqual(result.errors,[]);
    assert.deepEqual(result.backendRequests,[]);assert.deepEqual(result.failedRequests,[]);
    for(const abort of result.navigationAborts||[]) {
      assert.equal(abort.error,'net::ERR_ABORTED');
      assert.ok(['explicit reload','test context close'].includes(abort.reason));
    }
  }
}
const signature=await readFile('build/sales-release/apk-signature-20261030.log','utf8');
const manifest=await readFile('build/sales-release/apk-manifest-20261030.log','utf8');
assert.match(signature,/Verifies/);
assert.match(manifest,/package: name='com\.jentra\.sales\.dev'/);
assert.match(manifest,/native-code: 'arm64-v8a'/);
const delivery='dist/Jentra-Sales-0.1.0-1-Development';
const artifacts=[];
for(const file of ['Jentra-Sales-0.1.0-1-Development.apk','Jentra-Sales-0.1.0-1-Development-APK.zip']) {
  const bytes=await readFile(path.join(delivery,file));
  artifacts.push({path:`${delivery}/${file}`,size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
}
const archive=await load('build/sales-release/apk-archive-20261030.json');
assert.equal(archive.passed,true);assert.equal(archive.matchesDirectApk,true);
assert.equal(archive.apkSha256,artifacts[0].sha256);
const target='docs/verification/jentra-sales-20261030';
await mkdir(target,{recursive:false});
for(const [source,dest] of [
  ['build/sales-release/tests-reviewed-20261030.log','tests.log'],
  ['build/sales-release/analyzer-reviewed-20261030.log','analyzer.log'],
  ['build/sales-release/apk-signature-20261030.log','apk-signature.log'],
  ['build/sales-release/apk-manifest-20261030.log','apk-manifest.log'],
  ['build/sales-release/apk-archive-20261030.json','apk-archive.json'],
  ['build/sales-release/android-arm64-build-20261030.log','android-build.log'],
  ['build/sales-release/web-build-reviewed-r2-20261030.log','web-build.log'],
  ['build/sales-release/reviewed-input-manifest-20261030.json','source-manifest.json'],
  ['build/sales-release/delivery-input-manifest-20261030.json','delivery-source-manifest.json'],
  ['build/sales-release/final-input-manifest-20261031.json','final-source-manifest.json'],
  ['build/sales-release/backend-readonly-20261030.json','backend-readonly.json'],
  ['build/sales-release/preview-hosting-accepted-20261031.json','preview-hosting.json'],
  ['build/sales-release/live-hosting-verification.json','live-hosting.json'],
  ['build/sales-release/hosting-reviewed-r3/public-manifest.json','public-manifest.json'],
  ['build/sales-release/hosting-reviewed-r3/firebase.json','firebase.json'],
  ['build/sales-release/firebase-preview-final-20261030.json','firebase-preview.json'],
  ['build/sales-release/firebase-live-20261030.json','firebase-promotion.log'],
  ['build/sales-release/firebase-preview-restored-20261031.json','firebase-preview-restored.log'],
  ['output/playwright/jentra-sales-local-final-r2/browser-verification.json','local-browser.json'],
  ['output/playwright/jentra-sales-preview-accepted-r2/browser-verification.json','preview-browser.json'],
  ['output/playwright/jentra-sales-live-final-tcp-r4/browser-verification.json','live-browser.json'],
  ['output/playwright/jentra-sales-live-accepted-r3/browser-verification.json','live-normal-browser.json'],
  ['output/playwright/jentra-sales-live-alias-default/diagnostic.json','alternate-domain-diagnostic.json'],
  ['output/playwright/jentra-sales-live-native-input-r2/diagnostic.json','native-input-diagnostic.json'],
  ['output/playwright/jentra-sales-live-final-tcp/browser-verification.json','live-first-automation.json'],
  ['output/playwright/jentra-sales-preview-final/browser-verification.json','preview-default-transport.json'],
  ['output/playwright/jentra-sales-preview-network-tcp/diagnostic.json','tcp-startup-diagnostic.json'],
]) await copyFile(source,path.join(target,dest));
for(const file of ['desktop-today.png','tablet-today.png','phone-today.png','desktop-customers.png','desktop-order-review.png','desktop-dark.png']) {
  await copyFile(path.join('output/playwright/jentra-sales-live-final-tcp-r4',file),path.join(target,file));
}
const report={app:'Jentra Sales',version:'0.1.0+1',channel:'development',mode:'interactive-preview',verifiedOn:'2026-10-31',
  sourceSha256:before.sourceSha256,sourceInputs:before.files.length,sourceUnchangedAcrossBuilds:true,
  tests:{passed:19,analyzer:'no issues'},
  android:{applicationId:'com.jentra.sales.dev',abi:'arm64-v8a',signatureVerified:true,zipMatchesApk:true,signingIdentity:'local development',physicalDeviceAcceptance:false},
  firebase:{project:'jentra-os',site:'jentra-os-sales',url:live.baseUrl,previewUrl:preview.baseUrl,version:deployed.result.sales.version,promotedExactPreviewVersion:true,servedFiles:live.files.length,exactContentVerified:true,browserViewports:3},
  browserTransport:{launchArgs:browserLive.launchArgs,previewNormalPassed:browserPreview.results.filter(r=>r.passed).length,liveTcpPassed:browserLive.results.filter(r=>r.passed).length,latestLiveNormalPassed:normalLive.results.filter(r=>r.passed).length,normalLiveAcceptanceComplete:false,initialDefaultPreviewTimeouts:defaultBrowser.results.filter(r=>!r.passed&&/Timeout/.test(r.error||'')).length,note:'Normal Chrome live startup/reload remains intermittent on this network. Full live flow evidence uses HTTP/3-disabled Chrome; the cause is unconfirmed. An ignored Alt-Svc experiment was reverted; live remained on the original verified version. Earlier failures and input-focus test corrections are retained separately.'},
  artifacts,limits:{liveFieldSalesEnabled:false,backendInstallation:'not performed or certified',customerEmailActivated:false,
    productionStoreSigning:false,physicalDeviceAcceptance:false,normalBrowserAcceptance:false,fullS1Acceptance:false,languages:['en'],unsavedProcessDeathRecovery:false},
};
await writeFile(path.join(target,'verification.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(report,null,2));
