import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
import {createPrivateKeyReader,selectExistingLegacyKeys} from './private_runtime_http.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const sqlFile=base+'supabase-runtime-setup-20261009.sql',sqlSha='c2ae865c9bae23be94dec512dd15645a85c9a7a82b4edbd32fbccf92a7462e41';
const runtime='778237e3-3d4e-4871-8cc9-e08b07b989c7';
const must=(ok,code)=>{if(!ok){const e=Error(code);e.publicCode=code;throw e;}};
async function save(file,value){const bytes=JSON.stringify(value,null,2)+'\n',h=await fs.open(path.join(root,file),'wx');
 try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(bytes)};}
const names=['jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'];
const query=`SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'authorities',(SELECT coalesce(jsonb_agg(jsonb_build_object('runtimeId',runtime_id,'enabled',enabled,'expiresAt',expires_at,
   'jobIds',job_ids,'scheduleSecretId',schedule_secret_id)), '[]') FROM intelligence_control.edge_authorities WHERE runtime_id='${runtime}'),
 'ownJobs',(SELECT coalesce(jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'active',active,'schedule',schedule)), '[]')
   FROM cron.job WHERE jobname IN (${names.map(n=>`'${n}'`).join(',')})),
 'ownVault',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)), '[]') FROM vault.secrets WHERE name IN
   ('jentra-w5-runtime-20261009-schedule','jentra-w5-runtime-20261009-delivery-v1','jentra-w5-runtime-20261009-delivery-v2')),
 'keyRefs',(SELECT count(*) FROM intelligence_control.edge_key_refs WHERE runtime_id='${runtime}'),
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex')
   FROM cron.job j WHERE jobname NOT IN (${names.map(n=>`'${n}'`).join(',')})),
 'outsideVaultIdentityHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'createdAt',created_at) ORDER BY id)::text,'[]'),'sha256'),'hex')
   FROM vault.secrets WHERE name NOT IN ('jentra-w5-runtime-20261009-schedule','jentra-w5-runtime-20261009-delivery-v1','jentra-w5-runtime-20261009-delivery-v2'))
 ) AS snapshot`;
export function reviewedPausedSetup(source,publicKey){
 must(hashBytes(source)===sqlSha,'EXACT_REVIEWED_SETUP_BYTES_REQUIRED');
 must(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(publicKey)
   &&hashBytes(publicKey)==='e3ea9ff3f18e6bb24be674430cc494a31c4cd7d92482367b60383b5aedd6fa9d','EXACT_REVIEWED_PUBLIC_KEY_REQUIRED');
 const pause=`\ndo $pause_own_jobs$ declare a intelligence_control.edge_authorities%rowtype;begin
 select * into a from intelligence_control.edge_authorities where runtime_id='${runtime}';
 if cardinality(a.job_ids)<>3 or (select count(*) from cron.job where jobid=any(a.job_ids)
   and jobname in (${names.map(n=>`'${n}'`).join(',')}))<>3 then raise exception 'EXACT_THREE_OWN_JOBS_REQUIRED';end if;
 update cron.job set active=false where jobid=any(a.job_ids) and jobname in (${names.map(n=>`'${n}'`).join(',')});
 end $pause_own_jobs$;\ncommit;\n`;
 must(source.includes('\nbegin;\n')&&/\ncommit;\s*$/.test(source),'EXACT_REVIEWED_TRANSACTION_REQUIRED');
 return source.replace('\nbegin;\n',`\nbegin;\nSELECT set_config('jentra.w5.publishable_key','${publicKey}',true);\n`)
  .replace(/\ncommit;\s*$/,pause);
}
function executeFixedSetup(token,sql){
 const bytes=JSON.stringify({query:sql,read_only:false});
 return new Promise((resolve,reject)=>{let req,timer,settled=false,size=0;const chunks=[];
  const fail=code=>{if(settled)return;settled=true;clearTimeout(timer);req?.destroy();const e=Error(code);e.publicCode=code;reject(e);};
  req=https.request(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`,{method:'POST',rejectUnauthorized:true,
   headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(bytes)}},res=>{
   res.on('error',()=>fail('FIXED_SETUP_RESPONSE_UNCERTAIN'));res.on('data',c=>{size+=c.length;if(size>1048576)fail('FIXED_SETUP_RESPONSE_LIMIT');else chunks.push(c);});
   res.on('end',()=>{if(settled)return;const raw=Buffer.concat(chunks);if(res.statusCode!==200)return fail('FIXED_SETUP_HTTP_FAILURE');
    let value;try{value=JSON.parse(raw);}catch{return fail('FIXED_SETUP_RESPONSE_INVALID');}
    settled=true;clearTimeout(timer);resolve({status:res.statusCode,responseSha256:hashBytes(raw),resultRows:Array.isArray(value)?value.length:null});});
  });
  req.on('error',()=>fail('FIXED_SETUP_TRANSPORT_UNCERTAIN'));timer=setTimeout(()=>fail('FIXED_SETUP_TIMEOUT_UNCERTAIN'),120000);
  req.once('socket',socket=>{const send=()=>{if(socket.encrypted!==true||socket.authorized!==true)return fail('VERIFIED_SETUP_TLS_REQUIRED');req.end(bytes);};
   if(socket.authorized===true)send();else socket.once('secureConnect',send);});
 });
}
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute'].includes(mode)&&process.argv.length<=3,'EXACT_SETUP_MODE_REQUIRED');
 const {review}=await loadApprovedInputs();const source=await fs.readFile(path.join(root,sqlFile),'utf8');
 must(hashBytes(source)===sqlSha&&review.workerConfiguration.runtimeId===runtime,'EXACT_APPROVED_PERSISTENT_SETUP_REQUIRED');
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,sourceSha256:sqlSha,
  change:'The three new reviewed jobs start paused in the same setup transaction until ordered contention and delivery fixtures are ready.'})+'\n');return;}
 let incoming='';for await(const c of process.stdin){incoming+=c;must(incoming.length<=16000,'PRIVATE_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_SETUP_INPUT_REQUIRED');
 const management=createManagementTransport(config.ownerToken),directory=base+'persistent-setup-20261013-r5-'+Date.now()+'/';await fs.mkdir(path.join(root,directory));
 let phase='once-intent';try{
  await save(base+'persistent-setup-once-20261013-r5.json',{kind:'approved-persistent-setup-once-intent',projectId:PROJECT,bundleSha256:BUNDLE,
   actualStartedAt:new Date().toISOString(),directory,source:{path:sqlFile,sha256:sqlSha},ownJobNames:names,
   sameTransactionJobPause:true,pauseReason:'Required ordered lease fixture and inactive/drained jobs for later timed load.',automaticRetry:false,
   secretsGeneratedInsideVault:true,secretValuesSelectedOrReturned:false,production:false,realBilling:false});
  const read=async()=>(await management('POST','/database/query',{query,read_only:true})).value[0].snapshot;
  phase='preflight';const before=await read();await save(directory+'00-before.json',before);
  must(before.authorities.length===0&&before.ownJobs.length===0&&before.ownVault.length===0&&before.keyRefs===0,'PERSISTENT_SETUP_COLLISION_FORBIDDEN');
  const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value),sql=reviewedPausedSetup(source,keys.anon);
  await save(directory+'01-fixed-write-intent.json',{sqlSha256:hashBytes(sql),reviewedSourceSha256:sqlSha,actualIntentAt:new Date().toISOString(),
   creates:{authority:1,vaultSecrets:3,keyRefs:2,jobs:3},initialJobsActive:false,publicKeySha256:hashBytes(keys.anon),credentialPrinted:false});
  phase='persistent-commit';const written=await executeFixedSetup(config.ownerToken,sql);await save(directory+'02-management-response.json',written);
  phase='committed-read';const after=await read();await save(directory+'03-after.json',after);
  must(after.authorities.length===1&&after.authorities[0].enabled&&after.authorities[0].jobIds.length===3
   &&after.ownJobs.length===3&&after.ownJobs.every(j=>j.active===false&&j.schedule==='* * * * *')
   &&after.ownVault.length===3&&after.keyRefs===2&&before.outsideJobHash===after.outsideJobHash
   &&before.outsideVaultIdentityHash===after.outsideVaultIdentityHash,'EXACT_PERSISTENT_SETUP_AND_PRESERVATION_REQUIRED');
  const evidence=await save(directory+'99-result.json',{kind:'actual-reviewed-persistent-setup',passed:true,projectId:PROJECT,bundleSha256:BUNDLE,
   actualFinishedAt:new Date().toISOString(),reviewedSourceSha256:sqlSha,authority:after.authorities[0],ownJobs:after.ownJobs,
   vaultSecretIdentities:after.ownVault,keyRefs:2,existingJobAndVaultIdentitiesPreserved:true,secretValuesSelectedOrReturned:false,
   scheduledTransportNotYetExecuted:true,actualDelivery:false,modelCalls:0,ownerAcceptance:false,production:false,realBilling:false});
  process.stdout.write(JSON.stringify({passed:true,evidence})+'\n');
 }catch(error){await save(directory+'99-stop.json',{passed:false,phase,failureCode:error.publicCode??error.code??'FIXED_SETUP_STOP',
   actualStoppedAt:new Date().toISOString(),automaticRetry:false,mutationMayBeCommitted:true,secretsPrinted:false});throw error;}
 finally{config.ownerToken=null;}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'FIXED_SETUP_STOP',secretsPrinted:false})+'\n');process.exitCode=1;});
