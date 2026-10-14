import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const evidence=[];
async function read(relative){const b=await fs.readFile(path.join(root,relative));evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return JSON.parse(b);}
function returned(document){assert.equal(document.result.isError,false);
 const value=JSON.parse(document.result.content.find(x=>x.type==='text').text).result;
 const opening=value.match(/<untrusted-data-[^>]+>(?:\s|\\n)*(?=\[|\{)/);assert.ok(opening);
 const start=opening.index+opening[0].length,end=value.indexOf('</untrusted-data-',start);assert.ok(end>start);
 const raw=value.slice(start,end).replace(/(?:\s|\\n)+$/,'');
 try{return JSON.parse(raw);}catch{return JSON.parse(JSON.parse('"'+raw+'"'));}}
const deployment=await read('docs/verification/wave5/worker-v6-diagnostic-deployment-source-verification-20261014-r5.json');
const probe=await read('docs/verification/wave5/worker-v6-diagnostic-fixed-unauthenticated-probe-20261014-r5.json');
const finite=await read('docs/verification/wave5/worker-v6-diagnostic-actual-finite-provider-20261014-r5.json');
assert.equal(deployment.independentlyReturnedSourceModules,22);assert.equal(deployment.sourceRows.length,22);
assert.equal(deployment.existingPeopleFunctionsUnchanged,true);
for(const row of deployment.sourceRows){assert.equal(row.actualReturnedSha256,row.expectedSha256);assert.equal(row.matched,true);
 const actual=await fs.readFile(path.join(root,row.path));assert.equal(sha(actual),row.expectedSha256);}
for(const item of deployment.functions){assert.equal(item.version,6);assert.equal(item.status,'ACTIVE');assert.equal(item.gatewayVerifyJwt,false);assert.equal(item.customAuthenticationUnchanged,true);}
assert.equal(probe.requests,1);assert.equal(probe.status,503);assert.equal(probe.code,'WORKER_PROVIDER_UNAVAILABLE');
assert.equal(probe.suppliedCredentials,false);assert.equal(probe.automaticRetries,0);assert.equal(probe.schedulesResumed,false);
const records=returned(finite).result;assert.ok(records.length>=1&&records.length<=5);
const row=records.find(x=>x.request_id===probe.responseRequestId);assert.ok(row);
assert.equal(row.function_id,'f292d0dd-5907-439e-8687-0f7d8789bb42');assert.equal(row.version,'6');
const classified=JSON.parse(row.event_message);
assert.deepEqual(classified,{kind:'wave5_provider_v6',worker:'runtime',supabaseUrlClass:'exact_configured_https',serviceRoleShape:'opaque_secret_style',secretKeysDictionaryPresent:true});
assert.equal(finite.savedProbeServerUuid,probe.responseRequestId);assert.equal(finite.schedulesRemainPaused,true);
const report={kind:'independent-saved-live-worker-v6-observation-verification',reviewedAt:new Date().toISOString(),
 projectId:'xpdoufauvrbdmxgngetv',sourceRowsVerified:22,deployedVersion:6,peopleFunctionsPreserved:true,
 probeServerUuid:probe.responseRequestId,actualProbeStatus:503,actualProbeCode:probe.code,matchingProviderClassification:classified,
 sourceInference:'The exact-HTTPS URL check passes and the JWT-only service-key guard rejects the observed opaque key shape before request authentication.',
 keyAuthenticityOrRoleVerified:false,sourceRepairNeeded:true,liveReviewerRequests:0,rawPrivateValuesRead:false,
 schedulesRemainPaused:true,deliverySuccess:false,authenticatedNativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'worker-v6-independent-live-observation-20261014.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({passed:true,path:path.relative(root,output).replaceAll('\\','/'),sha256:sha(b)})+'\n');
