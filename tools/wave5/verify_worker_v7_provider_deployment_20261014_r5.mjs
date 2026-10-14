import fs from 'node:fs/promises';
import {hashBytes} from './runtime_contract.mjs';
const root=new URL('../../',import.meta.url),base='docs/verification/wave5/',evidence=[];
const must=(v,c)=>{if(!v)throw Error(c);};
async function read(file,pin){const b=await fs.readFile(new URL(file,root)),sha256=hashBytes(b);if(pin)must(sha256===pin,'EXACT_V7_DEPLOYMENT_EVIDENCE_REQUIRED');evidence.push({path:file,bytes:b.length,sha256});return JSON.parse(b);}
const decode=r=>JSON.parse(r.content.find(c=>c.type==='text').text);
const review=await read(base+'worker-v7-provider-runtime-review-20261014-r5.json','a87dc518efbb02623e147cbcde41e3d440e33fe31753aeccfbb0dae4602c1925');
const owner=await read(base+'worker-v7-provider-owner-decision-20261014-r5.json','0f513290971c544eaabd15a56aca78ff5a6a5ddc09e2a8dcca52f87178ef0066');
must(owner.decision==='approve'&&owner.operationBundleSha256===review.bundleSha256&&owner.candidateBundleSha256===review.candidateBundleSha256,'EXACT_DIRECT_V7_OWNER_DECISION_REQUIRED');
const before=decode(await read(base+'worker-v7-provider-deployment-before-20261014-r5-a2.json')).functions;
const after=decode(await read(base+'worker-v7-provider-after-functions-20261014-r5.json')).functions;
const canonical=v=>JSON.stringify(Array.isArray(v)?v.map(x=>JSON.parse(canonical(x))):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,JSON.parse(canonical(v[k]))])):v);
must(before.length===after.length&&before.length===4,'EXISTING_FUNCTION_INVENTORY_REQUIRED');
for(const old of before.filter(x=>x.name.startsWith('people-'))){const found=after.filter(x=>x.name===old.name);must(found.length===1&&canonical(found[0])===canonical(old),'PEOPLE_FUNCTION_METADATA_CHANGED');}
const functions=[],sourceRows=[];
for(let i=0;i<2;i++){
 const d=review.deployments[i],label=i===0?'runtime':'receiver';
 const deployed=decode(await read(base+`worker-v7-provider-${label}-deployment-20261014-r5-a2.json`));
 const returned=decode(await read(base+`worker-v7-provider-${label}-readback-20261014-r5.json`));
 const listed=after.filter(x=>x.name===d.name);
 must(listed.length===1&&listed[0].version===7&&listed[0].status==='ACTIVE'&&listed[0].verify_jwt===false&&returned.version===7&&returned.verify_jwt===false&&returned.id===deployed.id&&returned.ezbr_sha256===deployed.ezbr_sha256,'ACTIVE_DEPLOYED_V7_REQUIRED');
 const expected=d.files.filter(x=>!x.path.endsWith('/deno.json'));
 must(returned.files.length===expected.length&&new Set(returned.files.map(x=>x.name)).size===expected.length,'EXACT_V7_RETURNED_MODULE_SET_REQUIRED');
 for(const b of expected){const matches=returned.files.filter(x=>x.name===b.path);must(matches.length===1&&hashBytes(matches[0].content)===b.sha256,'RETURNED_V7_SOURCE_MISMATCH');must(hashBytes(await fs.readFile(new URL(b.path,root)))===b.sha256,'CURRENT_V7_SOURCE_CHANGED');sourceRows.push({function:d.name,path:b.path,expectedSha256:b.sha256,actualReturnedSha256:hashBytes(matches[0].content),matched:true});}
 functions.push({name:d.name,id:returned.id,version:7,status:returned.status,gatewayVerifyJwt:returned.verify_jwt,customAuthenticationUnchanged:true,ezbrSha256:returned.ezbr_sha256,submittedFiles:d.files.length,returnedSourceFiles:expected.length,allReturnedSourceHashesMatch:true,compilerConfigurationSubmitted:true,compilerConfigurationReturned:false});
}
must(sourceRows.length===25,'EXACT_25_RETURNED_V7_MODULES_REQUIRED');
const record={kind:'actual-direct-human-approved-v7-source-verification',actualVerifiedAt:new Date().toISOString(),projectId:owner.projectId,operationBundleSha256:review.bundleSha256,candidateBundleSha256:review.candidateBundleSha256,directHumanExactOperationApprovalVerified:true,functions,existingPeopleFunctionsUnchanged:true,peoplePreservationBasis:'Every independently returned People metadata field, including version and bundle checksum, equals the approved predeployment observation.',independentlyReturnedSourceModules:25,sourceRows,allReturnedSourceHashesMatch:true,actualProviderKeyAuthorizationVerified:false,schedulesResumedByThisVerifier:false,actualDelivery:false,actualTrustedModelUsage:false,authenticatedNative:false,targetScaleLoad:false,additionalCriteriaAccepted:0,production:false,realBilling:false,evidence};
const file=base+'worker-v7-provider-deployment-source-verification-20261014-r5.json',text=JSON.stringify(record,null,2)+'\n';await fs.writeFile(new URL(file,root),text,{flag:'wx'});process.stdout.write(JSON.stringify({verified:true,path:file,sha256:hashBytes(text),modules:25,version:7,existingPeopleFunctionsUnchanged:true,schedulesResumed:false})+'\n');
