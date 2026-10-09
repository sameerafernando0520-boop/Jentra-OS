import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {startRuntime,validateBoundReview} from './runtime_launcher.mjs';
import {workerConfig} from '../../scripts/wave5/runtime_plan.mjs';
const bind=body=>({...body,bundleSha256:createHash('sha256').update(JSON.stringify(body)).digest('hex')});
test('unbound review refuses launch before credentials or network',async()=>{
 const review=bind({approvalReady:false,workerConfiguration:workerConfig});
 const approval={ownerApproved:true,approvedBundleSha256:review.bundleSha256,ownerMessageReference:'injected-policy-test-only'};
 let reads=0,calls=0;const env=new Proxy({},{get(){reads++;throw Error('secret accessed');}});
 await assert.rejects(startRuntime({review,approval,env,fetchImpl:()=>{calls++;}}),/RUNTIME_BINDINGS_REQUIRED/);
 assert.equal(reads,0);assert.equal(calls,0);
});
test('approval binds exact review bytes and an explicit human reference',()=>{
 const review=bind({approvalReady:false,workerConfiguration:workerConfig});
 assert.throws(()=>validateBoundReview(review,{}),/OWNER_APPROVAL_REQUIRED/);
 assert.throws(()=>validateBoundReview({...review,approvalReady:true},{}),/REVIEW_HASH_MISMATCH/);
});
test('bound receiver rejects alternate host and URL credentials',()=>{
 const c=structuredClone(workerConfig);c.hostBinding.publicBaseUrl='https://worker.example.test';c.receiver.url='https://receiver.example.test/signed';c.receiver.allowedHosts=['unreviewed.example.test'];
 let review=bind({approvalReady:true,workerConfiguration:c});let approval={ownerApproved:true,ownerMessageReference:'injected-policy-test-only',approvedBundleSha256:review.bundleSha256};
 assert.throws(()=>validateBoundReview(review,approval),/RUNTIME_CONFIGURATION_INVALID/);
 c.receiver.url='https://user:password@receiver.example.test/signed';review=bind({approvalReady:true,workerConfiguration:c});approval={...approval,approvedBundleSha256:review.bundleSha256};
 assert.throws(()=>validateBoundReview(review,approval),/RUNTIME_BINDINGS_INVALID/);
});
