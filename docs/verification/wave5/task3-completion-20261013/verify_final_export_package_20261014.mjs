import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),evidence=[];
async function json(relative,expected){const b=await fs.readFile(path.join(root,relative));if(expected)assert.equal(sha(b),expected);
 evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return JSON.parse(b);}
const proof=await json('docs/verification/wave5/task3-export-continuation-20261014/export-source-proof-a1.json',
 'a2e2dcbac7393fa7eac5c315988497428eabd7956e3d25f95ff54099432e307f');
const peer=await json('docs/verification/wave5/task3-export-source-independent-20261014/independent-source-review-a1.json',
 '1223b1efdd7b85d73742f2f6aa5f4192d90907b6bbd6e45bd20d567649a0dd9d');
assert.equal(peer.sourceCandidateApproved,true);assert.equal(peer.liveExecutionAuthorizedByThisReview,false);
assert.equal(peer.actualTests.total,64);assert.equal(peer.actualTests.passed,64);assert.equal(peer.actualTests.failed,0);
assert.equal(peer.actualTests.syntaxChecks,3);assert.equal(peer.all112BindingsUnchanged,true);
assert.deepEqual(peer.authoredSources,proof.sources);
for(const binding of proof.sources){const b=await fs.readFile(path.join(root,binding.path));assert.equal(sha(b),binding.sha256);assert.equal(b.length,binding.bytes);}
const author=await json(proof.localVerification.path,proof.localVerification.sha256);
const verification=await json(peer.verification.path,peer.verification.sha256);
assert.equal(author.counts.pass,54);assert.equal(author.counts.fail,0);assert.equal(verification.tests.passed,64);assert.equal(verification.tests.failed,0);
assert.equal(verification.tests.exitCode,0);assert.equal(verification.sourcesUnchanged,true);
for(const log of [author.testTap,verification.tests.tap]){assert.ok(log);
 const b=await fs.readFile(path.join(root,log.path));assert.equal(sha(b),log.sha256);evidence.push({path:log.path,bytes:b.length,sha256:sha(b)});}
assert.equal(proof.actualA10RefreshByAuthor,false);assert.equal(proof.actualExportRegistrations,0);
assert.equal(proof.expiryExtended,false);assert.equal(proof.originalRuntimeExpiry,'2026-10-14T09:57:07.481942Z');
assert.ok(Date.now()>=Date.parse(proof.originalRuntimeExpiry));
const report={kind:'primary-independent-final-export-source-package-verification',reviewedAt:new Date().toISOString(),
 projectId:proof.projectId,sourceImplementationComplete:true,independentSourceReviewComplete:true,
 actualAuthoredTestsPassed:54,actualCombinedIndependentTestsPassed:64,syntaxChecksPassed:3,
 inputBindingsVerifiedByIndependentReviewer:112,currentThreeSourceHashesMatched:true,sources:proof.sources,
 actualLiveExportsVerified:false,actualA10RefreshVerified:false,originalRuntimeExpiry:proof.originalRuntimeExpiry,
 originalAuthorityExpired:true,executionApprovedByThisReview:false,
 futurePrerequisites:['new concrete authorized runtime window','updated cumulative accounting including the post-expiry read',
  'source-reviewed corresponding expiry and budget successor','actual fresh private readiness','generated execution profile and plan',
  'exact private adapter and final operation review'],
 privateInputsRead:false,reviewerNetworkRequests:0,snapshotMutated:false,authenticatedNativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'export-source-package-independent-final-verification-20261014.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({passed:true,path:path.relative(root,output).replaceAll('\\','/'),sha256:sha(b)})+'\n');
