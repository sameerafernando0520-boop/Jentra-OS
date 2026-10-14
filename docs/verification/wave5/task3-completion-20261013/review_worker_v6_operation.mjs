import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const read=async relative=>{assert.ok(!path.win32.isAbsolute(relative)&&!relative.split('/').includes('..'));
 const bytes=await fs.readFile(path.join(root,relative));return{path:relative,bytes:bytes.length,sha256:sha(bytes),text:bytes.toString('utf8')};};
const ref=({text,...binding})=>binding;
const packet=await read('docs/verification/wave5/worker-v6-diagnostic-runtime-review-20261014-r5.json');
assert.equal(packet.sha256,'7023830c0d803b59662a6ea55ef4855063a992c7caabaf244f89040ebdecef25');
const review=JSON.parse(packet.text),{bundleSha256,...body}=review;
assert.equal(sha(JSON.stringify(body)),bundleSha256);
assert.equal(bundleSha256,'091d42d339733ae73838bdbc720a714c9a9b673b03ce41b972b9b61cd2017718');
assert.equal(review.projectId,'xpdoufauvrbdmxgngetv');
assert.equal(review.predecessorRuntimeBundleSha256,'ba2bf259fa0d8f39d069001a44f795076a93f94652d354fc7b942866d19e5599');
for(const key of ['routeEligibilityUnchanged','handlerAuthenticationAndScopeUnchanged','providerBehaviorUnchanged',
 'diagnosticAfterOriginalHandler','schedulesMustRemainPaused'])assert.equal(review[key],true);
for(const key of ['environmentOrSecretsChanged','rawRequestOrEnvironmentValuesPublished','production','realBilling'])assert.equal(review[key],false);
assert.equal(review.maximumProviderDiagnosticAttemptsPerIsolate,1);
assert.equal(review.retainedLimits.maximumModelCalls,4);assert.equal(review.retainedLimits.maximumScheduleRequestsOriginal,4320);
assert.equal(review.retainedLimits.scheduledRequestsAlreadyObserved,24);
assert.equal(review.retainedLimits.authorityExpiresAt,'2026-10-14T09:57:07.481942Z');assert.equal(review.retainedLimits.extendedExpiry,false);
assert.deepEqual(review.closedPublishedFields,['supabaseUrlClass','serviceRoleShape','secretKeysDictionaryPresent']);
const correctedFile=await read('docs/verification/wave5/task3-v6-diagnostic-20261014/source-proof-a2.json');
assert.equal(correctedFile.sha256,'e20a9de5f0124c1ae1941172e57c8e8eb6bf5418603b5d9b23dc03ab8ada0e7a');
const corrected=JSON.parse(correctedFile.text);assert.equal(corrected.countCorrection.sourceOrTestChanges,false);
assert.equal(corrected.retainedPayloadRowCount,24);assert.equal(corrected.retainedSourceRowCountAcrossDeployments,22);
const peerFile=await read('docs/verification/wave5/task3-v6-independent-20261014/independent-source-review-a2.json');
assert.equal(peerFile.sha256,'7855a68218814aa5788e63fb743b632da7e55f334590399d6a1b9d714e65b504');
const peer=JSON.parse(peerFile.text);assert.match(peer.technicalVerdict,/approve exact source successor/);
const actualTestsFile=await read('docs/verification/wave5/task3-v6-independent-20261014/independent-local-verification-a1.json');
assert.equal(actualTestsFile.sha256,'405f00c75bdf8e35d3b7aaa6052c79d90450ec24151115592472f4d7034915cf');
assert.equal(JSON.parse(actualTestsFile.text).counts.pass,21);
const evidence=[];
for(const binding of [review.sourceProof,...review.evidence]){const actual=await read(binding.path);
 assert.equal(actual.sha256,binding.sha256);assert.equal(actual.bytes,binding.bytes);evidence.push(ref(actual));}
const files=[],payloads=[];
for(const deployment of review.deployments){const file=await read(deployment.payload.path);
 assert.equal(file.sha256,deployment.payload.sha256);assert.equal(file.bytes,deployment.payload.bytes);
 const payload=JSON.parse(file.text);assert.equal(payload.project_id,review.projectId);assert.equal(payload.name,deployment.name);
 assert.equal(payload.verify_jwt,false);assert.equal(payload.entrypoint_path,deployment.entrypoint);
 assert.equal(payload.files.length,deployment.name==='wave5-runtime'?15:9);
 assert.equal(new Set(payload.files.map(row=>row.name)).size,payload.files.length);
 assert.deepEqual(payload.files.map(row=>row.name).sort(),deployment.files.map(row=>row.path).sort());
 const oldPayload=JSON.parse((await read(`docs/verification/wave5/supabase-deploy-${deployment.name}-routing-v5-20261014-r5.json`)).text);
 assert.deepEqual(oldPayload.files.map(row=>row.name.replaceAll('20261014_r5_v5','20261014_r5_v6')).sort(),payload.files.map(row=>row.name).sort());
 for(const binding of deployment.files){const actual=await read(binding.path);assert.equal(actual.sha256,binding.sha256);assert.equal(actual.bytes,binding.bytes);
  const embedded=payload.files.find(row=>row.name===binding.path);assert.equal(embedded.content,actual.text);
  const oldEmbedded=oldPayload.files.find(row=>row.name.replaceAll('20261014_r5_v5','20261014_r5_v6')===binding.path);
  if(!binding.path.includes('20261014_r5_v6'))assert.equal(embedded.content,oldEmbedded.content);
  files.push({worker:deployment.name,...ref(actual)});}payloads.push(ref(file));}
assert.equal(files.length,24);
const oldRoute=await read('workers/wave5/edge_route_20261014_r5_v5.mjs'),newRoute=await read('workers/wave5/edge_route_20261014_r5_v6.mjs');
assert.equal(newRoute.text.slice(0,oldRoute.text.length),oldRoute.text);
const report={kind:'primary-independent-exact-worker-v6-diagnostic-operation-decision',reviewedAt:new Date().toISOString(),
 projectId:review.projectId,technicalVerdict:'approve exact diagnostic-only V6 development operation under verified direct user delegation',
 operationReview:ref(packet),runtimeBundleSha256:bundleSha256,correctedSourceProof:ref(correctedFile),independentPeerReview:ref(peerFile),
 actualIndependentTestRecord:ref(actualTestsFile),testsPassed:21,payloadRowsVerified:24,sourceRowsAcrossDeployments:22,
 uniqueDeploymentFiles:18,uniqueSourceModules:16,staticReachableGraphs:{runtime:14,receiver:7},
 literalDynamicInclusiveGraphs:{runtime:14,receiver:8},receiverLazyDependency:'persistent_control.mjs:47 imports worker_runtime.mjs inside runDeliveryBatch',
 exactV5RoutingPrefixPreserved:true,providerAndAuthenticationBehaviorUnchanged:true,payloads,files,evidence,
 maximumProviderDiagnosticAttemptsPerIsolate:1,rawEnvironmentOrRequestValuesPublished:false,
 maximumPublicProbeRequests:1,externalProbeMustUsePublicHttps:true,probeDeadlineMs:12000,redirectsOrAutomaticRetries:0,
 schedulesMustRemainPaused:true,originalExpiryRetained:review.retainedLimits.authorityExpiresAt,
 originalOperationalCapsRetained:true,providerFixAuthorizedByThisDecision:false,newEnvironmentAliasesOrSecrets:0,
 personalHumanExactSourceSignatureClaimed:false,privateInputsRead:false,networkRequestsByReviewer:0,
 actualLiveProviderClassificationEstablished:false,actualDeliveryEstablished:false,nativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,
 decision:'The live owner may bind this concrete technical decision, deploy only both exact payloads, read back source and People metadata, send one bounded credential-free public HTTPS probe, and read only the finite provider diagnostic matching its server UUID. Keep all reviewed jobs paused; provider correction requires a separate exact source/operation review.'};
const bytes=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'worker-v6-independent-operation-decision.json');
await fs.writeFile(output,bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({approved:true,payloadRows:24,report:{path:path.relative(root,output).replaceAll('\\','/'),bytes:bytes.length,sha256:sha(bytes)}})+'\n');
