import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const evidence=[];
async function read(relative,expected){const b=await fs.readFile(path.join(root,relative));if(expected)assert.equal(sha(b),expected,relative);
 evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return b;}
const json=async(relative,expected)=>JSON.parse(await read(relative,expected));
function returned(record){assert.equal(record.isError,false);return JSON.parse(record.content.find(x=>x.type==='text').text);}
const candidate=await json('docs/verification/wave5/task3-v7-provider-20261014/candidate-manifest.json',
 '49a943f5a26de7d17c49ac3fef3f3bd43a2a53122297cebb55c786792523bbc6');
const owner=await json('docs/verification/wave5/worker-v7-provider-owner-decision-20261014-r5.json',
 '0f513290971c544eaabd15a56aca78ff5a6a5ddc09e2a8dcca52f87178ef0066');
assert.equal(owner.decision,'approve');assert.equal(owner.source.answer,'Approve the exact V7 worker correction');
assert.equal(owner.operationBundleSha256,'24d74074ebc3b5e92e7fb047743b047952a85deeabe8a7def20470b0ed678493');
assert.equal(owner.scheduleResumeAuthorizedByThisDecision,false);
const saved=await json('docs/verification/wave5/worker-v7-provider-deployment-source-verification-20261014-r5-a2.json',
 '9deaf816923888e44b7b35fa0b961b2915f3ce7c6df41df5b184a3391adfa9e6');
const before=returned(await json('docs/verification/wave5/worker-v7-provider-deployment-before-20261014-r5-a2.json')).functions;
const after=returned(await json('docs/verification/wave5/worker-v7-provider-after-functions-20261014-r5.json')).functions;
assert.equal(after.length,before.length);
for(const item of before.filter(x=>!['wave5-runtime','wave5-receiver'].includes(x.name)))assert.deepEqual(after.find(x=>x.id===item.id),item);
const checked=[];
for(const deployment of candidate.deployments){const role=deployment.name==='wave5-runtime'?'runtime':'receiver';
 const actual=returned(await json(`docs/verification/wave5/worker-v7-provider-${role}-readback-20261014-r5.json`));
 assert.equal(actual.name,deployment.name);assert.equal(actual.version,7);assert.equal(actual.status,'ACTIVE');assert.equal(actual.verify_jwt,false);
 assert.equal(actual.ezbr_sha256,after.find(x=>x.name===deployment.name).ezbr_sha256);
 assert.ok(actual.entrypoint_path.endsWith('/source/'+deployment.entrypoint));
 const expected=deployment.files.filter(x=>x.path!==`supabase/functions/${deployment.name}/deno.json`);
 assert.equal(actual.files.length,expected.length);assert.equal(new Set(actual.files.map(x=>x.name)).size,actual.files.length);
 assert.deepEqual(actual.files.map(x=>x.name).sort(),expected.map(x=>{assert.ok(x.path.startsWith('workers/'));return x.path.slice('workers/'.length);}).sort());
 for(const item of expected){const actualName=item.path.slice('workers/'.length),row=actual.files.find(x=>x.name===actualName);assert.ok(row);
  const b=await read(item.path,item.sha256);assert.equal(b.length,item.bytes);assert.equal(row.content,b.toString('utf8'));
  const summary=saved.sourceRows.find(x=>x.function===deployment.name&&x.path===item.path);assert.ok(summary);
  assert.equal(summary.actualReturnedPath,actualName);assert.equal(summary.expectedSha256,item.sha256);assert.equal(summary.actualReturnedSha256,sha(row.content));
  checked.push({worker:deployment.name,path:item.path,returnedPath:actualName,sha256:item.sha256});}}
assert.equal(checked.length,25);assert.equal(saved.independentlyReturnedSourceModules,25);assert.equal(saved.existingPeopleFunctionsUnchanged,true);
const helperPath='tools/wave5/probe_worker_v7_provider_ingress_20261014_r5.mjs';
const helper=(await read(helperPath)).toString('utf8');
assert.ok(helper.includes("const startedAt=new Date().toISOString(),target='https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule',bytes=Buffer.from('{}')"));
assert.ok(helper.includes("rejectUnauthorized:true,agent:false"));assert.ok(helper.includes("socket.encrypted!==true||socket.authorized!==true"));
assert.ok(helper.includes("size>1024"));assert.ok(helper.includes("12000"));assert.ok(helper.includes("{flag:'wx'}"));
assert.ok(!/authorization\s*:|apikey\s*:|cookie\s*:|rejectUnauthorized:false/i.test(helper));
assert.ok(helper.includes(owner.operationBundleSha256));assert.ok(helper.includes('0f513290971c544eaabd15a56aca78ff5a6a5ddc09e2a8dcca52f87178ef0066'));
assert.ok(helper.includes('9deaf816923888e44b7b35fa0b961b2915f3ce7c6df41df5b184a3391adfa9e6'));
const report={kind:'independent-actual-worker-v7-readback-and-bounded-probe-source-review',reviewedAt:new Date().toISOString(),
 projectId:candidate.projectId,deployedVersion:7,returnedSourceRowsVerified:25,
 exactMapping:'Each approved source path beginning workers/ maps only by removing that common prefix; full returned name population and every byte must match.',
 arbitraryPathNormalizationAllowed:false,peopleFunctionMetadataUnchanged:true,directExactHumanOperationApprovalBound:true,
 probeHelper:evidence.find(x=>x.path===helperPath),maximumPublicProbeRequests:1,probeDeadlineMs:12000,probeResponseMaximumBytes:1024,
 credentialFreeVerifiedTls:true,automaticRetries:0,redirectsFollowed:0,probeSourceApproved:true,
 liveOwnerMayPerformOnlyAlreadyApprovedSingleProbe:true,scheduleResumeAuthorized:false,schedulesMustRemainPaused:true,
 originalRuntimeExpiry:owner.originalAuthorityExpiresAt,actualProbePassed:false,serviceKeyRoleOrValidityProven:false,
 reviewerNetworkRequests:0,privateInputsRead:false,actualDelivery:false,nativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,
 sources:checked,evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'worker-v7-independent-deployment-and-probe-review-20261014.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({passed:true,path:path.relative(root,output).replaceAll('\\','/'),sha256:sha(b)})+'\n');
