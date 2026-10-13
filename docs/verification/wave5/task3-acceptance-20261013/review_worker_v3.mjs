import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const repository=process.cwd();
const output='docs/verification/wave5/task3-acceptance-20261013';
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=name=>fs.readFileSync(path.join(repository,name));
const json=name=>JSON.parse(read(name));
const bind=name=>({path:name,bytes:read(name).length,sha256:sha(read(name))});
const candidatePath='docs/verification/wave5/worker-platform-origin-v3-candidate-review-20261013-r5.json';
const repairedPath='docs/verification/wave5/worker-platform-origin-v3-post-repair-root-verification-20261013-r5-a2.json';
const candidate=json(candidatePath),repaired=json(repairedPath);
assert.equal(sha(JSON.stringify(candidate.bundlePayload)),candidate.bundleSha256);
const checked=[];
for(const expected of [...candidate.bundlePayload.sourceFiles,...candidate.bundlePayload.closureFiles,...candidate.preservedOriginalSources,...candidate.evidence,...repaired.sourceFiles,...repaired.logs]){
 const actual=bind(expected.path);assert.equal(actual.sha256,expected.sha256,expected.path);
 if(expected.bytes!==undefined)assert.equal(actual.bytes,expected.bytes,expected.path);
 checked.push(actual);
}
for(const part of ['runtime','receiver']){
 const previous=read(`workers/wave5/edge_${part}_20261013_r5.mjs`).toString();
 const actual=read(`workers/wave5/edge_${part}_20261013_r5_v3.mjs`).toString();
 assert.equal(actual,previous.replace("'./edge_route_20261013_r5.mjs'","'./edge_route_20261013_r5_v3.mjs'"));
}
const selectedTests=fs.readdirSync(path.join(repository,'workers/wave5')).filter(name=>name.endsWith('.test.mjs')).map(name=>`workers/wave5/${name}`).sort();
const result=spawnSync(process.execPath,['--test','--test-isolation=none','--test-reporter=tap',...selectedTests],{cwd:repository,encoding:'utf8',timeout:60000,maxBuffer:4*1024*1024});
const logPath=`${output}/worker-v3-independent-tests.tap`;
fs.writeFileSync(path.join(repository,logPath),(result.stdout??'')+(result.stderr??''));
assert.equal(result.status,0,result.error?.message??'Worker test failure');
const counts={};for(const key of ['tests','pass','fail','cancelled','skipped','todo'])counts[key]=Number(new RegExp(`^# ${key} (\\d+)$`,'m').exec(result.stdout)?.[1]);
assert.equal(counts.fail,0);assert.equal(counts.skipped,0);assert.ok(counts.tests>=240);
const report={kind:'independent-v3-worker-source-review',reviewedAt:new Date().toISOString(),projectId:candidate.projectId,candidate:bind(candidatePath),repairedVerification:bind(repairedPath),candidateBundleSha256:candidate.bundleSha256,reviewer:'Codex technical reviewer, delegated by user',verifiedBindings:checked.length,sourceAndEvidenceBindings:checked,exactFactoryImportOnlyTransformation:true,customAuthenticationChecksUnchanged:true,localVerification:{command:[process.execPath,'--test','--test-isolation=none','--test-reporter=tap',...selectedTests],exitCode:result.status,counts,log:bind(logPath)},securityAssessment:['The selector accepts only the configured project HTTPS origin and exact platform HTTPS origin; the platform form requires the correct function namespace.','Caller-provided headers cannot select an origin or expand route allowlists. Exact canonical URLs reject userinfo, queries, fragments, alternate ports and encoded or extra suffix routes.','Schedule hash/server authority, external credentials, genuine caller Auth and byte-HMAC plus live source/subscription checks remain byte-identical to the deployed version 2 factory.','The new diagnostic prints only finite classifications, at most once per factory instance; no URL, headers, body, method, token or credentials are logged.','Timeouts, body caps, concurrency cap, delivery/subscription batch caps, expiring authority, scopes and original dependencies remain unchanged.'],findings:[],recommendation:'Accept the exact candidate source as a bounded synthetic routing repair. The current direct user delegation authorizes a technical decision; the live-owning chat must record the exact operation and perform deployments, readbacks, a bounded ingress probe and unchanged expiry-bound schedules.',limitations:['A local candidate test is not observation of managed Request.url. The actual origin/path remains an inference until the diagnostic is observed live.','Deno checks are verified from root saved logs; this reviewer did not invoke Deno.','No live mutation, auth provisioning, key access, SQL, scheduling or native actions were performed by this review.','Deployment approval and operation authority must be recorded for this exact bundle; the predecessor version 2 approval did not bind version 3.','No actual delivery, model usage, target-scale load or native acceptance is conferred.'],production:false,realBilling:false};
fs.writeFileSync(path.join(repository,`${output}/worker-v3-independent-review.json`),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({kind:report.kind,bundle:report.candidateBundleSha256,verifiedBindings:report.verifiedBindings,tests:counts,findings:report.findings.length,recommendation:report.recommendation},null,2));
