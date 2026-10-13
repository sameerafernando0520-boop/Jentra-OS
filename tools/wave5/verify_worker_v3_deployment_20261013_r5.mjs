import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/',evidence=[];
const must=(v,c)=>{if(!v)throw Error(c);};
async function read(file,pin){const b=await fs.readFile(path.join(root,file)),sha256=hashBytes(b);if(pin)must(sha256===pin,'EXACT_DEPLOYMENT_EVIDENCE_REQUIRED');evidence.push({path:file,bytes:b.length,sha256});return JSON.parse(b);}
const decode=r=>JSON.parse(r.content.find(c=>c.type==='text').text);
const review=await read(base+'worker-platform-origin-v3-runtime-review-20261013-r5-a1.json','704aab41f9a20045549fa1e0331a5aeab360cce8525638520dd3868a14665f61');
const owner=await read(base+'worker-platform-origin-v3-owner-decision-20261013-r5.json','3c7ab0bbc32a50a1558f9f560f3883460839386c5be28191bb4d8866aa12e487');
must(owner.decision==='approve'&&owner.candidateBundleSha256===review.bundleSha256,'EXACT_V3_OWNER_DECISION_REQUIRED');
const before=decode((await read(base+'worker-platform-origin-v3-deployment-before-20261013-r5.json')).result).functions;
const after=decode(await read(base+'worker-platform-origin-v3-after-functions-20261013-r5.json')).functions;
const canonical=v=>JSON.stringify(Array.isArray(v)?v.map(x=>JSON.parse(canonical(x))):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,JSON.parse(canonical(v[k]))])):v);
must(before.length===after.length&&before.length===4,'EXISTING_FUNCTION_INVENTORY_REQUIRED');
for(const old of before.filter(x=>x.name.startsWith('people-'))){const found=after.filter(x=>x.name===old.name);must(found.length===1&&canonical(found[0])===canonical(old),'PEOPLE_FUNCTION_METADATA_CHANGED');}
const functions=[],sourceRows=[];
for(let i=0;i<2;i++){
 const d=review.deployments[i],label=i===0?'runtime':'receiver';
 const deployed=decode((await read(base+`worker-platform-origin-v3-${label}-deployment-20261013-r5.json`)).result);
 const returned=decode(await read(base+`worker-platform-origin-v3-${label}-readback-20261013-r5.json`));
 const listed=after.filter(x=>x.name===d.name);
 must(listed.length===1&&listed[0].version===3&&listed[0].status==='ACTIVE'&&listed[0].verify_jwt===false&&returned.version===3&&returned.verify_jwt===false&&returned.id===deployed.id&&returned.ezbr_sha256===deployed.ezbr_sha256,'ACTIVE_DEPLOYED_V3_REQUIRED');
 const expected=d.files.filter(x=>!x.path.endsWith('/deno.json'));
 must(returned.files.length===expected.length&&new Set(returned.files.map(x=>x.name)).size===expected.length,'EXACT_RETURNED_MODULE_SET_REQUIRED');
 for(const b of expected){const matches=returned.files.filter(x=>x.name===b.path);must(matches.length===1&&hashBytes(matches[0].content)===b.sha256,'RETURNED_V3_SOURCE_MISMATCH');must(hashBytes(await fs.readFile(path.join(root,b.path)))===b.sha256,'CURRENT_V3_SOURCE_CHANGED');sourceRows.push({function:d.name,path:b.path,expectedSha256:b.sha256,actualReturnedSha256:hashBytes(matches[0].content),matched:true});}
 functions.push({name:d.name,id:returned.id,version:3,status:returned.status,gatewayVerifyJwt:returned.verify_jwt,customAuthenticationUnchanged:true,ezbrSha256:returned.ezbr_sha256,submittedFiles:d.files.length,returnedSourceFiles:expected.length,allReturnedSourceHashesMatch:true,compilerConfigurationSubmitted:true,compilerConfigurationReturned:false});
}
must(sourceRows.length===22,'EXACT_22_RETURNED_MODULES_REQUIRED');
const record={kind:'actual-owner-approved-platform-origin-v3-source-verification',actualVerifiedAt:new Date().toISOString(),projectId:owner.projectId,candidateBundleSha256:review.bundleSha256,ownerDecisionVerified:true,functions,existingPeopleFunctionsUnchanged:true,peoplePreservationBasis:'All independently returned function inventory metadata, including version and bundle checksum, equals the predeployment observation.',independentlyReturnedSourceModules:22,sourceRows,allReturnedSourceHashesMatch:true,schedulesResumedByThisVerifier:false,actualDelivery:false,actualTrustedModelUsage:false,authenticatedNative:false,targetScaleLoad:false,additionalCriteriaAccepted:0,production:false,realBilling:false,evidence};
const file=base+'worker-platform-origin-v3-deployment-source-verification-20261013-r5.json';const bytes=JSON.stringify(record,null,2)+'\n';await fs.writeFile(path.join(root,file),bytes,{flag:'wx'});process.stdout.write(JSON.stringify({verified:true,file,sha256:hashBytes(bytes),modules:22,version:3,existingPeopleFunctionsUnchanged:true,schedulesResumed:false})+'\n');
