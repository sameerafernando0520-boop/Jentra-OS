import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),evidence=[];
async function json(relative,expected){const b=await fs.readFile(path.join(root,relative));if(expected)assert.equal(sha(b),expected);
 evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return JSON.parse(b);}
const source=await json('docs/verification/wave5/task3-completion-20261013/worker-v7-independent-deployment-and-probe-review-20261014.json',
 'd15f3a3941175dcd258b252069c881badb0f8670d1f3b07b3669d3257bc0220f');
const probe=await json('docs/verification/wave5/worker-v7-provider-fixed-unauthenticated-probe-20261014-r5.json');
assert.equal(source.returnedSourceRowsVerified,25);assert.equal(source.probeSourceApproved,true);
assert.equal(probe.target,'https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule');
assert.equal(probe.requests,1);assert.equal(probe.dispatched,true);assert.equal(probe.verifiedTls,true);assert.equal(probe.bodyBytes,2);
assert.equal(probe.status,403);assert.equal(probe.code,'WORKER_ACCESS_DENIED');assert.equal(probe.expectedUnauthenticatedHandlerDenial,true);
assert.equal(probe.responseSha256,sha(JSON.stringify({code:'WORKER_ACCESS_DENIED'})));assert.equal(probe.responseBytes,31);
assert.match(probe.responseRequestId,/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/);
assert.equal(probe.automaticRetries,0);assert.equal(probe.redirectsFollowed,0);assert.equal(probe.suppliedCredentials,false);
assert.equal(probe.cookies,false);assert.equal(probe.schedulesResumed,false);assert.equal(probe.actualProviderKeyAuthorizationVerified,false);
assert.ok(Date.parse(probe.finishedAt)-Date.parse(probe.startedAt)<=12000);
const report={kind:'independent-actual-worker-v7-unsigned-probe-result-review',reviewedAt:new Date().toISOString(),
 projectId:'xpdoufauvrbdmxgngetv',deployedVersion:7,returnedSourceRowsVerified:25,actualUnsignedProbePassed:true,
 serverRequestUuid:probe.responseRequestId,status:403,code:probe.code,actualRequests:1,
 previous503InitializationFailureResolvedAtUnsignedIngress:true,backendServiceKeyRoleOrValidityVerified:false,
 schedulesRemainPaused:true,scheduleResumeAuthorized:false,actualDelivery:false,actualTrustedModelUsage:false,
 authenticatedNative:false,targetScaleLoad:false,productionReleaseReady:false,reviewerNetworkRequests:0,evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'worker-v7-independent-actual-probe-result-20261014.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({passed:true,path:path.relative(root,output).replaceAll('\\','/'),sha256:sha(b)})+'\n');
