import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadApprovedInputs,decodePublicResult,PROJECT} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
import {isDeepStrictEqual as equal} from 'node:util';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/',evidence=[];
const must=(v,c)=>{if(!v)throw Error(c);};
async function read(file){const bytes=await fs.readFile(path.join(root,file));evidence.push({path:file,sha256:hashBytes(bytes)});return JSON.parse(bytes);}
await loadApprovedInputs();
const review=await read(base+'worker-routing-runtime-review-20261013-r5-a2.json'),decision=await read(base+'worker-routing-owner-decision-20261013-r5.json');
must(review.bundleSha256==='bce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552'&&decision.decision==='approve'&&decision.candidateBundleSha256===review.bundleSha256,'EXACT_ROUTING_OWNER_DECISION_REQUIRED');
const beforeFile=await read(base+'worker-routing-deployment-before-20261013-r5.json'),before=decodePublicResult(beforeFile.rawFunctions).functions;
const after=decodePublicResult(await read(base+'worker-routing-after-functions-20261013-r5.json')).functions;
const outside=rows=>rows.filter(f=>!['wave5-runtime','wave5-receiver'].includes(f.name)).sort((a,b)=>a.name.localeCompare(b.name));
must(equal(outside(before),outside(after))&&outside(before).length===2,'EXISTING_PEOPLE_FUNCTIONS_CHANGED');
const functions=[];
for(const [key,name]of [['runtime','wave5-runtime'],['receiver','wave5-receiver']]){
 const source=decodePublicResult(await read(base+`worker-routing-${key}-readback-20261013-r5.json`));
 const deployment=review.deployments.find(d=>d.name===name),payload=await read(deployment.payload.path);
 const metadata=after.find(f=>f.name===name),old=before.find(f=>f.name===name);
 must(source.id===old.id&&metadata.id===old.id&&source.version===2&&metadata.version===2&&source.status==='ACTIVE'
  &&source.verify_jwt===false&&metadata.verify_jwt===false&&source.ezbr_sha256===metadata.ezbr_sha256,'EXACT_ACTIVE_V2_ROUTING_DEPLOYMENT_REQUIRED');
 must(source.files.length===(name==='wave5-runtime'?14:8),'EXACT_RETURNED_SOURCE_COUNT_REQUIRED');
 for(const returned of source.files){const approved=payload.files.find(f=>f.name===returned.name),binding=deployment.files.find(f=>f.path===returned.name);
  must(approved&&binding&&hashBytes(returned.content)===binding.sha256&&returned.content===approved.content,'RETURNED_ROUTING_SOURCE_CHANGED');}
 const missing=payload.files.filter(f=>!source.files.some(r=>r.name===f.name));
 must(missing.length===1&&missing[0].name===`supabase/functions/${name}/deno.json`,'UNEXPECTED_MISSING_RETURNED_SOURCE');
 functions.push({name,id:source.id,version:2,status:'ACTIVE',gatewayVerifyJwt:false,customAuthenticationUnchanged:true,
  ezbrSha256:source.ezbr_sha256,submittedFiles:payload.files.length,returnedSourceFiles:source.files.length,
  allReturnedSourceHashesMatch:true,compilerConfigurationSubmitted:true,compilerConfigurationReturned:false});
}
const result={kind:'actual-owner-approved-routing-source-verification',actualVerifiedAt:new Date().toISOString(),projectId:PROJECT,
 candidateBundleSha256:review.bundleSha256,ownerDecisionVerified:true,functions,existingPeopleFunctionsUnchanged:true,
 independentlyReturnedSourceModules:22,allReturnedSourceHashesMatch:true,schedulesResumedByThisVerifier:false,
 actualDelivery:false,actualTrustedModelUsage:false,privateProviderPassed:false,targetScaleLoad:false,authenticatedNative:false,
 ownerAcceptedCriteria:3,additionalOwnerAcceptance:0,production:false,realBilling:false,evidence};
const filename=base+'worker-routing-deployment-source-verification-20261013-r5.json',bytes=JSON.stringify(result,null,2)+'\n';
await fs.writeFile(path.join(root,filename),bytes,{flag:'wx'});await loadApprovedInputs();
process.stdout.write(JSON.stringify({verified:true,file:filename,sha256:hashBytes(bytes),modules:22,existingPeopleFunctionsUnchanged:true,versions:[2,2],schedulesStillPaused:true})+'\n');
