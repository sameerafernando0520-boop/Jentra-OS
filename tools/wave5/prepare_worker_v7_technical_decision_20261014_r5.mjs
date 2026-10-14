import fs from 'node:fs/promises';
import { hashBytes } from './runtime_contract.mjs';
const root = new URL('../../', import.meta.url), base = 'docs/verification/wave5/';
const must = (v, c) => { if (!v) throw Error(c); };
async function exact(file, expected) { const b = await fs.readFile(new URL(file,root)); must(hashBytes(b)===expected,'EXACT_V7_OPERATION_BINDING_REQUIRED'); return JSON.parse(b); }
const reviewPath = base+'worker-v7-provider-runtime-review-20261014-r5.json';
const review = await exact(reviewPath,'a87dc518efbb02623e147cbcde41e3d440e33fe31753aeccfbb0dae4602c1925');
const peerPath = base+'task3-completion-20261013/worker-v7-independent-operation-decision-20261014.json';
const peer = await exact(peerPath,'a5e0c69e6c6576d9c0dfbc7d4930786d900786c714882289ade3e77c62ee0bba');
const sourcePath = base+'task3-v7-independent-20261014/independent-source-review-a2.json';
const source = await exact(sourcePath,'f0e713a3b4e090bbc3a35d8ed0a2293600f5827c3fb35801573f89649ef5813d');
const {bundleSha256,...body}=review;
must(hashBytes(JSON.stringify(body))===bundleSha256 && bundleSha256==='24d74074ebc3b5e92e7fb047743b047952a85deeabe8a7def20470b0ed678493','EXACT_CANONICAL_V7_OPERATION_REQUIRED');
must(source.passed===true && source.candidateBundleSha256===review.candidateBundleSha256 && source.independentValidation.counts.pass===36 && source.independentValidation.counts.fail===0,'INDEPENDENT_V7_SOURCE_CHECKS_REQUIRED');
must(Date.now()<Date.parse(review.retainedLimits.authorityExpiresAt) && review.callerAuthenticationAndScopeUnchanged && review.routeEligibilityUnchanged && !review.environmentOrSecretsChanged,'ORIGINAL_V7_SCOPE_REQUIRED');
for(const d of review.deployments){ const p=await exact(d.payload.path,d.payload.sha256); for(const b of d.files){const f=p.files.filter(x=>x.name===b.path);must(f.length===1 && hashBytes(f[0].content)===b.sha256 && hashBytes(await fs.readFile(new URL(b.path,root)))===b.sha256,'CURRENT_EXACT_V7_SOURCE_REQUIRED');}}
const decision={kind:'delegated-technical-minimal-worker-v7-operation-decision',decision:'approve',recordedAt:new Date().toISOString(),projectId:review.projectId,
 candidateBundleSha256:review.candidateBundleSha256,operationBundleSha256:bundleSha256,
 runtimeReview:{path:reviewPath,sha256:'a87dc518efbb02623e147cbcde41e3d440e33fe31753aeccfbb0dae4602c1925'},
 independentOperationReview:{path:peerPath,sha256:'a5e0c69e6c6576d9c0dfbc7d4930786d900786c714882289ade3e77c62ee0bba'},
 independentSourceReview:{path:sourcePath,sha256:'f0e713a3b4e090bbc3a35d8ed0a2293600f5827c3fb35801573f89649ef5813d'},
 authority:{kind:'actual_direct_user_technical_delegation_verified_with_read_thread',threadId:'01a13650-c557-70d3-bb66-3c40b2a71efb',userMessageId:'01a13685-c880-7051-8e13-aaaa35479a99',quote:"do the best things. You decide all what is good and do it. don't ask me again."},
 personalHumanExactSourceSignatureClaimed:false,allowedActions:['Deploy only the two exact V7 payloads.','Verify all25 returned source modules and unchanged People metadata.','One credential-free bounded verified-TLS POST{} schedule probe; require403WORKER_ACCESS_DENIED.'],
 maximumPublicProbes:1,maximumPublicProbeMs:12000,maximumPublicProbeResponseBytes:1024,
 schedulesMustRemainPaused:true,scheduleResumeAuthorizedByThisDecision:false,customAuthenticationAndScopeUnchanged:true,
 originalSecretsAndEnvironmentAndDestinationsUnchanged:true,...review.retainedLimits,
 additionalRequirementAcceptance:0,production:false,realBilling:false};
const file=base+'worker-v7-provider-technical-operation-decision-20261014-r5.json',text=JSON.stringify(decision,null,2)+'\n';
await fs.writeFile(new URL(file,root),text,{flag:'wx'});
process.stdout.write(JSON.stringify({path:file,sha256:hashBytes(text),decisionRecorded:true,deployed:false,schedulesResumeAuthorized:false,peerDecisionKeys:Object.keys(peer)})+'\n');
