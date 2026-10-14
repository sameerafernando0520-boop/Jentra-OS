import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const read=async relative=>{assert.ok(!path.isAbsolute(relative)&&!relative.split('/').includes('..'));
 const bytes=await fs.readFile(path.join(root,relative));return{path:relative,bytes:bytes.length,sha256:sha(bytes),text:bytes.toString('utf8')};};
const ref=({text,...binding})=>binding;
const packet=await read('docs/verification/wave5/worker-v5-routing-runtime-review-20261014-r5.json');
const review=JSON.parse(packet.text),{bundleSha256,...body}=review;
assert.equal(sha(JSON.stringify(body)),bundleSha256);
assert.equal(bundleSha256,'ba2bf259fa0d8f39d069001a44f795076a93f94652d354fc7b942866d19e5599');
assert.equal(review.projectId,'xpdoufauvrbdmxgngetv');
assert.equal(review.predecessorRuntimeBundleSha256,'d2c5ae38aefcb8120ea3b3ca85520c142eb79f0c9e14f1f902ae9fc84c34c4c4');
assert.equal(review.handlerAuthenticationAndScopeUnchanged,true);
assert.equal(review.publicHttpsEndpointsUnchanged,true);
assert.equal(review.forwardedHeadersNeverTrusted,true);
assert.equal(review.maximumDiagnosticsPerIsolate,1);
assert.equal(review.privateOrRawRequestDataLogged,false);
assert.equal(review.schedulesRemainPausedUntilSourceAndProbeVerified,true);
assert.equal(review.retainedLimits.maximumModelCalls,4);
assert.equal(review.retainedLimits.maximumScheduleRequestsOriginal,4320);
assert.equal(review.retainedLimits.scheduledRequestsAlreadyObserved,24);
assert.equal(review.retainedLimits.authorityExpiresAt,'2026-10-14T09:57:07.481942Z');
assert.equal(review.retainedLimits.extendedExpiry,false);
for(const key of ['newUsers','newPermissions','newSecrets','newDestinations'])assert.equal(review.retainedLimits[key],0);
for(const key of ['production','realBilling'])assert.equal(review[key],false);
assert.equal(review.additionalRequirementAcceptance,0);
const sourceFile=await read('docs/verification/wave5/task3-completion-20261013/worker-v5-independent-source-review.json');
assert.equal(sourceFile.sha256,'9cf30391ae145b87babf5b1959593ed187f12e7e1217a85d7b0294d6b19bbcee');
const evidence=[];
for(const binding of [review.sourcePreparation,...review.evidence]){const actual=await read(binding.path);
 assert.equal(actual.sha256,binding.sha256,binding.path);assert.equal(actual.bytes,binding.bytes);evidence.push(ref(actual));}
assert.deepEqual(review.deployments.map(row=>row.name),['wave5-runtime','wave5-receiver']);
const files=[],payloads=[];
for(const deployment of review.deployments){
 const file=await read(deployment.payload.path);assert.equal(file.sha256,deployment.payload.sha256);assert.equal(file.bytes,deployment.payload.bytes);
 const payload=JSON.parse(file.text);
 assert.deepEqual(Object.keys(payload).sort(),['entrypoint_path','files','name','project_id','verify_jwt']);
 assert.equal(payload.project_id,review.projectId);assert.equal(payload.name,deployment.name);assert.equal(payload.verify_jwt,false);
 assert.equal(payload.entrypoint_path,deployment.entrypoint);
 assert.equal(payload.files.length,deployment.name==='wave5-runtime'?15:9);
 assert.equal(new Set(payload.files.map(row=>row.name)).size,payload.files.length);
 assert.deepEqual(payload.files.map(row=>row.name).sort(),deployment.files.map(row=>row.path).sort());
 const oldPayload=JSON.parse((await read(`docs/verification/wave5/supabase-deploy-${deployment.name}-diagnostic-v4-20261014-r5.json`)).text);
 assert.deepEqual(oldPayload.files.map(row=>row.name.replaceAll('20261014_r5_v4','20261014_r5_v5')).sort(),payload.files.map(row=>row.name).sort());
 for(const binding of deployment.files){const actual=await read(binding.path);assert.equal(actual.sha256,binding.sha256);assert.equal(actual.bytes,binding.bytes);
  const embedded=payload.files.find(row=>row.name===binding.path);assert.equal(embedded.content,actual.text);
  const oldEmbedded=oldPayload.files.find(row=>row.name.replaceAll('20261014_r5_v4','20261014_r5_v5')===binding.path);
  if(!binding.path.includes('20261014_r5_v5'))assert.equal(embedded.content,oldEmbedded.content);
  files.push({worker:deployment.name,...ref(actual)});}
 payloads.push(ref(file));
}
assert.equal(files.length,24);
const completeTests=await read('docs/verification/wave5/worker-v5-routing-all-worker-tests-20261014-r5.tap');
assert.match(completeTests.text,/^# tests 256$/m);assert.match(completeTests.text,/^# pass 256$/m);
assert.match(completeTests.text,/^# fail 0$/m);assert.match(completeTests.text,/^# skipped 0$/m);
const report={kind:'independent-complete-worker-v5-development-operation-review',reviewedAt:new Date().toISOString(),
 projectId:review.projectId,technicalVerdict:'approve exact bounded existing-development V5 operation under verified direct delegation',
 runtimeBundleSha256:bundleSha256,operationReview:ref(packet),sourceReview:ref(sourceFile),payloads,payloadFileRowsVerified:24,files,evidence,
 unchangedPayloadClosureAndAuthenticationPreserved:true,sourceEqualsPayload:true,personalHumanExactSourceSignatureClaimed:false,
 maximumUnauthenticatedProbe:1,externalProbeMustUsePublicHttps:true,
 requiredBeforeScheduleResume:['all returned source modules equal reviewed payloads','existing People metadata unchanged',
 'the fixed public HTTPS probe returns403','matching saved server UUID has finite public_project_http/namespace/default-port recognized tuple',
 'same existing jobs, original expiry and cumulative bounds remain valid'],
 originalAuthorityExpiry:review.retainedLimits.authorityExpiresAt,expiryExtended:false,newAccountsOrDestinations:0,
 deploymentPerformedByReviewer:false,networkRequestsByReviewer:0,actualDeliveryEstablished:false,productionReleaseReady:false,
 nextAction:'Live owner binds this decision, deploys only the two exact payloads, reads back sources, executes one bounded probe, and resumes the same schedules only after every guard passes.'};
const bytes=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'worker-v5-independent-operation-review.json');
await fs.writeFile(output,bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({approved:true,payloadRows:24,bundleSha256,report:{path:path.relative(root,output).replaceAll('\\','/'),bytes:bytes.length,sha256:sha(bytes)}})+'\n');
