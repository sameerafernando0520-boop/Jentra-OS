import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const evidence=[];
async function read(relative,expected){assert.ok(!path.win32.isAbsolute(relative)&&!relative.split('/').includes('..'));
 const b=await fs.readFile(path.join(root,relative));if(expected)assert.equal(sha(b),expected,relative);
 if(!evidence.some(x=>x.path===relative))evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return b;}
async function json(relative,expected){return JSON.parse(await read(relative,expected));}
const peerPath=process.argv[2],peerSha=process.argv[3];assert.match(peerPath??'',/^docs\/verification\/wave5\/task3-v7-independent-20261014\/[^/]+\.json$/);
assert.match(peerSha??'',/^[a-f0-9]{64}$/);
const peer=await json(peerPath,peerSha);assert.equal(peer.passed,true);
const packetPath='docs/verification/wave5/worker-v7-provider-runtime-review-20261014-r5.json';
const packet=await json(packetPath,'a87dc518efbb02623e147cbcde41e3d440e33fe31753aeccfbb0dae4602c1925');
const {bundleSha256,...body}=packet;assert.equal(sha(JSON.stringify(body)),bundleSha256);
assert.equal(bundleSha256,'24d74074ebc3b5e92e7fb047743b047952a85deeabe8a7def20470b0ed678493');
const candidate=await json(packet.candidateManifest.path,packet.candidateManifest.sha256);
assert.equal(packet.candidateManifest.sha256,'49a943f5a26de7d17c49ac3fef3f3bd43a2a53122297cebb55c786792523bbc6');
assert.equal(packet.authorProof.sha256,'ea94c14e3ee120216796546f6f57e5a6b4820c0ae01b53266816c9efc3688013');
assert.equal(packet.candidateBundleSha256,candidate.candidateBundleSha256);
const integrity=await json('docs/verification/wave5/task3-completion-20261013/worker-v7-independent-candidate-integrity-20261014.json',
 '3d38fc0762edd5e4d1322a5d889dbef7b35b4ea79657f8c9328f8ba7aaaa72a4');
assert.equal(integrity.technicalSourceIntegrityPassed,true);assert.equal(integrity.exactPayloadRowsVerified,27);
for(const binding of packet.evidence){const b=await read(binding.path,binding.sha256);assert.equal(b.length,binding.bytes);}
const files=[];
for(const item of packet.deployments){const expected=candidate.deployments.find(x=>x.name===item.name);assert.ok(expected);
 assert.equal(item.entrypoint,expected.entrypoint);assert.deepEqual(item.files,expected.files);
 assert.deepEqual(item.payload,expected.payload);assert.equal(item.verifyJwt,false);
 const payload=await json(item.payload.path,item.payload.sha256);assert.equal(payload.project_id,packet.projectId);
 assert.equal(payload.name,item.name);assert.equal(payload.verify_jwt,false);assert.equal(payload.entrypoint_path,item.entrypoint);
 assert.equal(payload.files.length,item.name==='wave5-runtime'?17:10);
 assert.deepEqual(payload.files.map(x=>x.name).sort(),item.files.map(x=>x.path).sort());
 for(const row of item.files){const b=await read(row.path,row.sha256);assert.equal(b.length,row.bytes);
  assert.equal(payload.files.find(x=>x.name===row.path).content,b.toString('utf8'));files.push({worker:item.name,...row});}}
assert.equal(files.length,27);assert.equal(new Set(files.map(x=>x.path)).size,20);
assert.equal(packet.returnedSourceRowsExpected,25);assert.equal(packet.uniqueSourceFiles,18);
for(const key of ['callerAuthenticationAndScopeUnchanged','routeEligibilityUnchanged','vaultReferencesAndDestinationsUnchanged',
 'schedulesRemainPausedUntilSourceAndProbeVerified','scheduleResumeRequiresExactCurrentResumeSourceReview'])assert.equal(packet[key],true);
for(const key of ['environmentOrSecretsChanged','personalHumanExactSourceSignatureClaimed','production','realBilling'])assert.equal(packet[key],false);
assert.deepEqual(packet.retainedLimits,candidate.retainedLimits);
assert.equal(packet.retainedLimits.authorityExpiresAt,'2026-10-14T09:57:07.481942Z');
assert.equal(packet.localVerification.passed,21);assert.equal(packet.localVerification.failed,0);
assert.equal(packet.localVerification.cachedOnly,true);assert.equal(packet.localVerification.importedJavaScriptTypeChecked,false);
for(const check of packet.localVerification.denoChecks){assert.equal(check.exitCode,0);await read(check.log.path,check.log.sha256);}
const report={kind:'primary-independent-exact-worker-v7-operation-decision',reviewedAt:new Date().toISOString(),
 projectId:packet.projectId,technicalVerdict:'approve the exact V7 compatibility deployment, source readback and one bounded unsigned probe under direct user delegation',
 operationReview:evidence.find(x=>x.path===packetPath),runtimeBundleSha256:bundleSha256,
 candidateBinding:packet.candidateManifest,independentSourceReview:{path:peerPath,sha256:peerSha},
 primaryCandidateIntegrity:evidence.find(x=>x.path.includes('candidate-integrity')),payloadRowsVerified:27,
 returnedSourceRowsExpected:25,uniqueDeploymentFiles:20,uniqueSourceModules:18,sourceFiles:files,
 scopedAndDefaultPrivilegedTransport:'strict legacy JWT or opaque sb_secret; opaque keys on apikey only',
 userJwtPathUnchanged:true,sourceKeyFormatIsAuthenticityProof:false,
 maximumDeployments:2,maximumPublicProbeRequests:1,publicProbeTarget:'https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule',
 publicProbeMethod:'POST',publicProbeBody:'{}',probeMustContainNoCredentialsOrCookies:true,
 probeDeadlineMs:12000,redirectsOrAutomaticRetries:0,requiredProbeStatus:403,requiredProbeCode:'WORKER_ACCESS_DENIED',
 requireEveryReturnedSourceHashAndUnchangedPeopleMetadata:true,schedulesMustRemainPaused:true,
 scheduleResumeAuthorizedByThisDecision:false,separateExactResumeHelperReviewRequired:true,
 newEnvironmentAliasesOrSecrets:0,originalExpiryRetained:packet.retainedLimits.authorityExpiresAt,originalOperationalCapsRetained:true,
 personalHumanExactSourceSignatureClaimed:false,networkRequestsByReviewer:0,privateInputsRead:false,
 actualV7ProviderAuthorizationEstablished:false,actualDeliveryEstablished:false,nativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,
 decision:'The live owner may bind this exact decision, deploy only both reviewed payloads, verify25 returned source modules and unchanged People metadata, then perform one bounded credential-free public HTTPS probe. Keep jobs4/5/6 paused. A separate exact source and live-state review is required for resuming them.',evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'worker-v7-independent-operation-decision-20261014.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({approved:true,path:path.relative(root,output).replaceAll('\\','/'),sha256:sha(b)})+'\n');
