import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/',evidence=[];
const must=(v,c)=>{if(!v)throw Error(c);};
async function read(file,pin){const b=await fs.readFile(path.join(root,file)),sha256=hashBytes(b);if(pin)must(sha256===pin,'EXACT_DEPLOYMENT_EVIDENCE_REQUIRED');evidence.push({path:file,bytes:b.length,sha256});return JSON.parse(b);}
const decode=r=>JSON.parse(r.content.find(c=>c.type==='text').text);
const review=await read(base+'worker-v6-diagnostic-runtime-review-20261014-r5.json','7023830c0d803b59662a6ea55ef4855063a992c7caabaf244f89040ebdecef25');
const owner=await read(base+'worker-v6-diagnostic-technical-operation-decision-20261014-r5.json','abcb2b26f069f60193e583d14b1ccbc26aa45a1759227199d8b2958a6f17de31');
must(owner.decision==='approve'&&owner.candidateBundleSha256===review.bundleSha256,'EXACT_V6_OWNER_DECISION_REQUIRED');
const before=decode((await read(base+'worker-v6-diagnostic-deployment-before-20261014-r5.json')).result).functions;
const after=decode(await read(base+'worker-v6-diagnostic-after-functions-20261014-r5.json')).functions;
const canonical=v=>JSON.stringify(Array.isArray(v)?v.map(x=>JSON.parse(canonical(x))):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,JSON.parse(canonical(v[k]))])):v);
must(before.length===after.length&&before.length===4,'EXISTING_FUNCTION_INVENTORY_REQUIRED');
for(const old of before.filter(x=>x.name.startsWith('people-'))){const found=after.filter(x=>x.name===old.name);must(found.length===1&&canonical(found[0])===canonical(old),'PEOPLE_FUNCTION_METADATA_CHANGED');}
const functions=[],sourceRows=[];
for(let i=0;i<2;i++){
 const d=review.deployments[i],label=i===0?'runtime':'receiver';
 const deployed=decode((await read(base+`worker-v6-diagnostic-${label}-deployment-20261014-r5.json`)).result);
 const returned=decode(await read(base+`worker-v6-diagnostic-${label}-readback-20261014-r5.json`));
 const listed=after.filter(x=>x.name===d.name);
 must(listed.length===1&&listed[0].version===6&&listed[0].status==='ACTIVE'&&listed[0].verify_jwt===false&&returned.version===6&&returned.verify_jwt===false&&returned.id===deployed.id&&returned.ezbr_sha256===deployed.ezbr_sha256,'ACTIVE_DEPLOYED_V6_REQUIRED');
 const expected=d.files.filter(x=>!x.path.endsWith('/deno.json'));
 must(returned.files.length===expected.length&&new Set(returned.files.map(x=>x.name)).size===expected.length,'EXACT_RETURNED_MODULE_SET_REQUIRED');
 for(const b of expected){const matches=returned.files.filter(x=>x.name===b.path);must(matches.length===1&&hashBytes(matches[0].content)===b.sha256,'RETURNED_V6_SOURCE_MISMATCH');must(hashBytes(await fs.readFile(path.join(root,b.path)))===b.sha256,'CURRENT_V6_SOURCE_CHANGED');sourceRows.push({function:d.name,path:b.path,expectedSha256:b.sha256,actualReturnedSha256:hashBytes(matches[0].content),matched:true});}
 functions.push({name:d.name,id:returned.id,version:6,status:returned.status,gatewayVerifyJwt:returned.verify_jwt,customAuthenticationUnchanged:true,ezbrSha256:returned.ezbr_sha256,submittedFiles:d.files.length,returnedSourceFiles:expected.length,allReturnedSourceHashesMatch:true,compilerConfigurationSubmitted:true,compilerConfigurationReturned:false});
}
must(sourceRows.length===22,'EXACT_22_RETURNED_MODULES_REQUIRED');
const record={kind:'actual-delegated-diagnostic-only-v6-source-verification',actualVerifiedAt:new Date().toISOString(),projectId:owner.projectId,candidateBundleSha256:review.bundleSha256,technicalOperationDecisionVerified:true,personalHumanExactSourceSignatureClaimed:false,functions,existingPeopleFunctionsUnchanged:true,peoplePreservationBasis:'All independently returned function inventory metadata, including version and bundle checksum, equals the predeployment observation.',independentlyReturnedSourceModules:22,sourceRows,allReturnedSourceHashesMatch:true,schedulesResumedByThisVerifier:false,actualDelivery:false,actualTrustedModelUsage:false,authenticatedNative:false,targetScaleLoad:false,additionalCriteriaAccepted:0,production:false,realBilling:false,evidence};
const file=base+'worker-v6-diagnostic-deployment-source-verification-20261014-r5.json';const bytes=JSON.stringify(record,null,2)+'\n';await fs.writeFile(path.join(root,file),bytes,{flag:'wx'});process.stdout.write(JSON.stringify({verified:true,file,sha256:hashBytes(bytes),modules:22,version:6,existingPeopleFunctionsUnchanged:true,schedulesResumed:false})+'\n');
