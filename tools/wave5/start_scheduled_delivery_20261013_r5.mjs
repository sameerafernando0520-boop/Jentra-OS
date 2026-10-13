import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
import {runtimeSealKey,appendRuntimeSecret} from './private_runtime_seal.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(v,c)=>{if(!v){const e=Error(c);e.publicCode=c;throw e;}};
const binds=[['scheduled-delivery-start-intent-20261013-r5.json','f885fcf190bd017889915e9805d01194779f18b2d13662d4e15e4c1cb6ec8296'],['scheduled-delivery-start-20261013-r5.sql','94019d7ea0386ed21e04602f8678aed75ddcaaf1dfec8ae4810c714431641322'],['scheduled-delivery-start-read-20261013-r5.sql','a1646d8dc8fa7ee9927ec4785d87eade9db51aec97bcac20a3c43d0879a10c08']];
async function save(file,v){const b=JSON.stringify(v,null,2)+'\n',h=await fs.open(path.join(root,file),'wx');try{await h.writeFile(b);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(b)};}
function fixedWrite(token,sql){const b=JSON.stringify({query:sql,read_only:false});return new Promise((resolve,reject)=>{let req,timer,done=false,size=0;const chunks=[];
 const fail=c=>{if(done)return;done=true;clearTimeout(timer);req?.destroy();const e=Error(c);e.publicCode=c;reject(e);};
 req=https.request(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,{method:'POST',rejectUnauthorized:true,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(b)}},res=>{
  res.on('error',()=>fail('SCHEDULE_RESPONSE_UNCERTAIN'));res.on('data',c=>{size+=c.length;if(size>1048576)fail('SCHEDULE_RESPONSE_LIMIT');else chunks.push(c);});
  res.on('end',()=>{if(done)return;done=true;clearTimeout(timer);resolve({status:res.statusCode,raw:Buffer.concat(chunks)});});
 });req.on('error',()=>fail('SCHEDULE_TRANSPORT_UNCERTAIN'));timer=setTimeout(()=>fail('SCHEDULE_TIMEOUT_UNCERTAIN'),120000);
 req.once('socket',s=>{const send=()=>{if(s.encrypted!==true||s.authorized!==true)return fail('VERIFIED_SCHEDULE_TLS_REQUIRED');req.end(b);};if(s.authorized===true)send();else s.once('secureConnect',send);});
});}
async function main(){must(['--validate','--execute'].includes(process.argv[2])&&process.argv.length===3,'EXACT_START_MODE_REQUIRED');await loadApprovedInputs();
 const inputs=[];for(const [f,h] of binds){const b=await fs.readFile(path.join(root,base+f));must(hashBytes(b)===h,'EXACT_START_BINDING_REQUIRED');inputs.push(b.toString());}
 if(process.argv[2]==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,bindingCount:binds.length})+'\n');return;}
 let incoming='';for await(const c of process.stdin){incoming+=c;must(incoming.length<16000,'PRIVATE_INPUT_LIMIT');}const cfg=JSON.parse(incoming);incoming='';
 must(cfg.projectId===PROJECT&&cfg.bundleSha256===BUNDLE,'EXACT_PRIVATE_START_INPUT_REQUIRED');const key=runtimeSealKey(cfg.encryptionKey),management=createManagementTransport(cfg.ownerToken);
 const directory=base+'scheduled-delivery-start-20261013-r5-'+Date.now()+'/';await fs.mkdir(path.join(root,directory));let phase='once-intent';
 try{await save(base+'scheduled-delivery-start-once-20261013-r5.json',{kind:'exact-start-once-intent',actualStartedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,directory,bindings:binds,automaticRetry:false});
  const read=async()=>(await management('POST','/database/query',{query:inputs[2],read_only:true})).value[0].snapshot;
  phase='fresh-preflight';const before=await read();await save(directory+'00-before.json',before);
  must(before.scopeAllowed===true&&before.authority?.enabled===true&&before.ownJobs?.length===3&&before.ownJobs.every((j,i)=>j.jobId===i+4&&j.active===false)
   &&before.ticks===0&&before.quotaPeriods===0,'EXACT_UNSTARTED_OWN_JOBS_REQUIRED');
  await save(directory+'01-write-intent.json',{sqlSha256:binds[1][1],actualIntentAt:new Date().toISOString(),changesOnlyThreeReviewedJobs:true,secretsReadOrPrinted:false});
  phase='exact-start';const response=await fixedWrite(cfg.ownerToken,inputs[1]);let privateErrorRecord=null;
  if(response.status!==200){privateErrorRecord=await appendRuntimeSecret(cfg.privateDirectory,key,'schedule-error',{httpStatus:response.status,responseBase64:response.raw.toString('base64'),actualCapturedAt:new Date().toISOString()});}
  await save(directory+'02-response.json',{httpStatus:response.status,responseSha256:hashBytes(response.raw),privateErrorRecord,rawResponsePrinted:false});
  phase='actual-readback';const after=await read();await save(directory+'03-after.json',after);
  must(after.scopeAllowed===true&&after.authority?.enabled===true&&after.ownJobs?.length===3&&after.ownJobs.every((j,i)=>j.jobId===i+4&&j.active===true)
   &&before.outsideJobHash===after.outsideJobHash,'EXACT_ACTUAL_START_AND_PRESERVATION_REQUIRED');
  const evidence=await save(directory+'99-result.json',{kind:'actual-three-reviewed-schedules-started',passed:true,actualFinishedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,ownJobs:after.ownJobs,authority:after.authority,databaseObservedAt:after.observedAt,managementHttpStatus:response.status,privateErrorRecord,existingJobsPreserved:true,scheduledTransportOutcomeNotYetVerified:true,actualDelivery:false,actualModelCalls:null,fullProviderCoordinatorPassed:false,nativeAccepted:false,ownerAccepted:false,secretsPrinted:false});
  process.stdout.write(JSON.stringify({passed:true,evidence})+'\n');
 }catch(e){await save(directory+'99-stop.json',{passed:false,phase,failureCode:e.publicCode??e.code??'SCHEDULE_START_STOP',actualStoppedAt:new Date().toISOString(),mutationMayBeCommitted:phase==='exact-start'||phase==='actual-readback',automaticRetry:false,secretsPrinted:false});throw e;}
 finally{key.fill(0);cfg.ownerToken=null;cfg.encryptionKey=null;}
}
main().catch(e=>{process.stderr.write(JSON.stringify({failureCode:e.publicCode??e.code??'SCHEDULE_START_STOP',secretsPrinted:false})+'\n');process.exitCode=1;});
