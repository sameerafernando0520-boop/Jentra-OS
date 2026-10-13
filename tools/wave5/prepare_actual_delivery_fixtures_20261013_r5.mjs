import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes,isUuid} from './runtime_contract.mjs';
import {runtimeSealKey,readRuntimeSecret} from './private_runtime_seal.mjs';
import {createPrivateKeyReader,selectExistingLegacyKeys} from './private_runtime_http.mjs';
import {createSupabaseHttpsTransport,decodeReceivedAccessToken} from './delivery_transport_20261013_r5.mjs';
import {bindUuidSessionQuery,validateGenuineMfaResult} from './enroll_mfa_management_20261013_r5.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const prior=base+'genuine-delivery-lease-20261013-r5-1791885923843/',tenant='babe6c86-a764-4d3a-80a3-952a7c096c2c';
const entity='caa2bb06-219a-47e9-8132-66d1271b0ffd',branch='3813692c-f0de-4c69-8e34-d56cf54695b1';
const must=(v,c)=>{if(!v){const e=Error(c);e.publicCode=c;throw e;}};
async function save(file,value){const bytes=JSON.stringify(value,null,2)+'\n',h=await fs.open(path.join(root,file),'wx');
 try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(bytes)};}
const snapshot=`SELECT jsonb_build_object('observedAt',statement_timestamp(),'subscriptions',
 (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'url',url,'version',version,'enabled',enabled,'keyVersion',key_version)),'[]')
  FROM intelligence_control.integration_subscriptions WHERE tenant_id='${tenant}'),
 'heads',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'state',state,'attempt',attempt,'eventId',event_id)),'[]')
  FROM intelligence_control.delivery_heads WHERE tenant_id='${tenant}'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='${tenant}'),
 'activeOwnJobs',(SELECT count(*) FROM cron.job WHERE jobid IN(4,5,6) AND jobname IN
  ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health') AND active),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7')) AS snapshot`;
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute'].includes(mode)&&process.argv.length<=3,'EXACT_DELIVERY_FIXTURE_MODE_REQUIRED');
 const {review}=await loadApprovedInputs(),leaseBytes=await fs.readFile(path.join(root,prior+'99-result.json'));
 must(hashBytes(leaseBytes)==='e35cf55c3f093a17416bf132e89783eb4e4a337c808eda69fd747238c2322076'&&JSON.parse(leaseBytes).passed,'ACTUAL_RECOVERED_LEASE_REQUIRED');
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,additionalSubscriptions:3,forecastCommands:1,
  existingGenuineMfaSessionAdopted:true,noWorkerScheduleStarted:true})+'\n');return;}
 let incoming='';for await(const c of process.stdin){incoming+=c;must(incoming.length<=16000,'PRIVATE_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_DELIVERY_FIXTURE_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),management=createManagementTransport(config.ownerToken),directory=base+'actual-delivery-fixtures-20261013-r5-'+Date.now()+'/';
 await fs.mkdir(path.join(root,directory));let phase='once-intent',transport;
 try{await save(base+'actual-delivery-fixtures-once-20261013-r5.json',{kind:'actual-delivery-fixtures-once-intent',projectId:PROJECT,bundleSha256:BUNDLE,
  actualStartedAt:new Date().toISOString(),directory,additionalSubscriptions:['redirect','timeout','reject'],maximumForecastCommands:1,
  workerNetworkSend:false,automaticRetry:false,preserveOriginalRecoveredDelivery:true});
  const read=async()=>(await management('POST','/database/query',{query:snapshot,read_only:true})).value[0].snapshot;
  phase='before-read';const before=await read();await save(directory+'00-before.json',before);
  const lease=JSON.parse(leaseBytes);must(before.subscriptions.length===1&&before.subscriptions[0].id===lease.subscriptionId
   &&before.heads.length===1&&before.heads[0].id===lease.deliveryId&&before.heads[0].state==='retry'
   &&before.quotaPeriods===0&&before.activeOwnJobs===0&&before.ticks===0,'EXACT_RECOVERED_LEASE_BEFORE_OTHER_PATHS_REQUIRED');
  const sessionPublic=JSON.parse(await fs.readFile(path.join(root,prior+'01-proposer-session.json')));
  const secret=await readRuntimeSecret(config.privateDirectory,key,sessionPublic.privateRecord,'phase-session');
  const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);transport=createSupabaseHttpsTransport({projectId:PROJECT,apiKey:keys.anon});
  const handle=transport.connection(),claims=decodeReceivedAccessToken(secret.accessToken);
  must(claims.sub===lease.proposerMfa.actorId&&claims.session_id===lease.proposerMfa.sessionId&&claims.exp*1000>Date.now()+180000,'FRESH_ORIGINAL_PROPOSER_SESSION_REQUIRED');
  const online=await transport.send(handle,'/auth/v1/user',{method:'GET',bearer:secret.accessToken});must(online.ok,'ACTUAL_ONLINE_PROPOSER_REQUIRED');
  const server=await management('POST','/database/query',{query:bindUuidSessionQuery(claims.session_id,claims.sub),read_only:true});
  const proof=validateGenuineMfaResult({claims,onlineUser:online.value,session:server.value[0],actor:{authId:claims.sub},factorId:sessionPublic.factorId});
  await save(directory+'01-reverified-proposer-session.json',{...proof,privateRecord:sessionPublic.privateRecord,newAuthSession:false,newFactor:false});
  const request=(route,body)=>transport.send(handle,route,{bearer:secret.accessToken,profile:'api',body});
  for(const mode of ['redirect','timeout','reject']){phase='genuine-registration-'+mode;
   const body={p_tenant_id:tenant,p_legal_entity_id:entity,p_branch_id:branch,p_action:'register',p_id:review.workerConfiguration.receiver.subscriptions[mode],
    p_expected_version:0,p_payload:{url:review.workerConfiguration.receiver.paths[mode],keyRef:'w5/runtime/20261008/delivery/v1'}};
   await save(directory+mode+'-intent.json',{body,actorId:proof.actorId,actualIntentAt:new Date().toISOString()});
   const response=await request('/rest/v1/rpc/wave5_integration_manage',body);await save(directory+mode+'-response.json',response);
   must(response.ok&&response.value?.id===body.p_id&&response.value.enabled===true,'ACTUAL_REVIEWED_SUBSCRIPTION_REQUIRED');
  }
  phase='genuine-post-registration-forecast';const now=Date.parse((await management('POST','/database/query',
   {query:'SELECT statement_timestamp()::text AS observed_at',read_only:true})).value[0].observed_at),commandId=randomUUID();
  const body={p_tenant_id:tenant,p_legal_entity_id:entity,p_branch_id:branch,p_command_id:commandId,p_idempotency_key:commandId,
   p_client_timestamp:new Date(now).toISOString(),p_horizon_start:new Date(now).toISOString().slice(0,10),p_horizon_end:new Date(now+30*86400000).toISOString().slice(0,10)};
  await save(directory+'02-forecast-intent.json',{body,commandId,actualIntentAt:new Date().toISOString()});
  const forecast=await request('/rest/v1/rpc/freeze_pipeline_forecast',body);await save(directory+'03-forecast-response.json',forecast);
  must(forecast.ok&&isUuid(forecast.value?.entity?.id)&&forecast.value.command_id===commandId,'ACTUAL_NEW_RECEIVER_EVENT_REQUIRED');
  const after=await read();await save(directory+'04-after.json',after);
  must(after.subscriptions.length===4&&Object.values(review.workerConfiguration.receiver.subscriptions).every(id=>after.subscriptions.some(s=>s.id===id&&s.enabled))
   &&after.heads.length===1&&after.heads[0].id===lease.deliveryId&&after.quotaPeriods===0&&after.activeOwnJobs===0&&after.ticks===0,'EXACT_DELIVERY_FIXTURES_AND_PAUSED_JOBS_REQUIRED');
  const evidence=await save(directory+'99-result.json',{kind:'actual-four-path-delivery-fixtures-ready',passed:true,projectId:PROJECT,bundleSha256:BUNDLE,
   actualFinishedAt:new Date().toISOString(),proposerMfa:proof,forecastId:forecast.value.entity.id,commandId,
   subscriptions:after.subscriptions,originalRecoveredDeliveryId:lease.deliveryId,expectedEligibleEvents:5,ownJobsPaused:true,
   actualDelivery:false,workerScheduleStarted:false,actualModelCalls:0,fullProviderCoordinatorPassed:false,nativeAccepted:false,ownerAccepted:false});
  secret.accessToken=null;secret.refreshToken=null;process.stdout.write(JSON.stringify({passed:true,evidence})+'\n');
 }catch(error){await save(directory+'99-stop.json',{passed:false,phase,failureCode:error.publicCode??error.code??'BOUNDED_DELIVERY_FIXTURE_STOP',
   actualStoppedAt:new Date().toISOString(),automaticRetry:false,earlierMutationMayBeCommitted:true,credentialsPrinted:false});throw error;}
 finally{transport?.close();key.fill(0);config.ownerToken=null;config.encryptionKey=null;}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'BOUNDED_DELIVERY_FIXTURE_STOP',credentialsPrinted:false})+'\n');process.exitCode=1;});
