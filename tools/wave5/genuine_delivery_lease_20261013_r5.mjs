import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes,isUuid} from './runtime_contract.mjs';
import {runtimeSealKey} from './private_runtime_seal.mjs';
import {createPrivateKeyReader,selectExistingLegacyKeys} from './private_runtime_http.mjs';
import {createSupabaseHttpsTransport} from './delivery_transport_20261013_r5.mjs';
import {existingActorSession} from './private_existing_actor_session_20261013_r5.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const tenant='babe6c86-a764-4d3a-80a3-952a7c096c2c',entity='caa2bb06-219a-47e9-8132-66d1271b0ffd',branch='3813692c-f0de-4c69-8e34-d56cf54695b1';
const runtime='778237e3-3d4e-4871-8cc9-e08b07b989c7',subscription='58699e8a-28fd-4356-8cad-87ce46e17ddd';
const must=(v,c)=>{if(!v){const e=Error(c);e.publicCode=c;throw e;}};
async function save(file,value){const bytes=JSON.stringify(value,null,2)+'\n',h=await fs.open(path.join(root,file),'wx');
 try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(bytes)};}
const snapshot=`SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'subscriptions',(SELECT count(*) FROM intelligence_control.integration_subscriptions WHERE tenant_id='${tenant}'),
 'heads',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'subscriptionId',subscription_id,'eventId',event_id,'leaseId',lease_id,
  'leaseUntil',lease_until,'state',state,'attempt',attempt,'generation',generation)),'[]') FROM intelligence_control.delivery_heads WHERE tenant_id='${tenant}'),
 'attempts',(SELECT count(*) FROM intelligence_control.delivery_attempts WHERE tenant_id='${tenant}'),
 'outcomes',(SELECT count(*) FROM intelligence_control.delivery_outcomes WHERE tenant_id='${tenant}'),
 'reviews',(SELECT count(*) FROM intelligence_control.delivery_reviews WHERE tenant_id='${tenant}'),
 'receiverReceipts',(SELECT count(*) FROM intelligence_control.edge_receiver_receipts WHERE tenant_id='${tenant}'),
 'receipt',(SELECT count(*) FROM core.command_receipts WHERE tenant_id='${tenant}'),
 'audit',(SELECT count(*) FROM audit.events WHERE tenant_id='${tenant}'),
 'outbox',(SELECT count(*) FROM core.outbox_events WHERE tenant_id='${tenant}'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='${tenant}'),
 'activeOwnJobs',(SELECT count(*) FROM cron.job WHERE jobid IN (4,5,6) AND jobname IN
  ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health') AND active),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='${runtime}')) AS snapshot`;
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute'].includes(mode)&&process.argv.length<=3,'EXACT_LEASE_MODE_REQUIRED');
 const {review}=await loadApprovedInputs();must(review.workerConfiguration.receiver.subscriptions.accept===subscription,'EXACT_ACCEPT_SUBSCRIPTION_REQUIRED');
 const setupFile=base+'persistent-setup-actual-verification-20261013-r5-a3.json',setupBytes=await fs.readFile(path.join(root,setupFile));
 must(hashBytes(setupBytes)==='acfcf0b58bff2d3da4855612978395ba481e3d8cac76300d6086bca4d2ecfd4f'&&JSON.parse(setupBytes).passed,'ACTUAL_PAUSED_SETUP_REQUIRED');
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,registrations:1,forecastCommands:1,concurrentClaims:2,
  expiresNaturally:true,realMfaRecoveryRequired:true})+'\n');return;}
 let incoming='';for await(const c of process.stdin){incoming+=c;must(incoming.length<=16000,'PRIVATE_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_LEASE_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),management=createManagementTransport(config.ownerToken),directory=base+'genuine-delivery-lease-20261013-r5-'+Date.now()+'/';
 await fs.mkdir(path.join(root,directory));let phase='once-intent',transport;const started=Date.now();
 try{await save(base+'genuine-delivery-lease-once-20261013-r5.json',{kind:'actual-delivery-lease-once-intent',projectId:PROJECT,bundleSha256:BUNDLE,
  actualStartedAt:new Date().toISOString(),directory,subscriptionId:subscription,maximumDurationMs:240000,registrations:1,forecastCommands:1,
  concurrentClaims:2,naturalExpiryClaim:1,mfaNotSentReview:1,automaticRetry:false,noManualLeaseTimeMutation:true});
  const read=async()=>(await management('POST','/database/query',{query:snapshot,read_only:true})).value[0].snapshot;
  phase='before-read';const before=await read();await save(directory+'00-before.json',before);
  must(before.subscriptions===0&&before.heads.length===0&&before.attempts===0&&before.outcomes===0&&before.reviews===0
   &&before.receiverReceipts===0&&before.activeOwnJobs===0&&before.ticks===0&&before.quotaPeriods===0,'EXACT_ONE_PENDING_LEASE_PREPARATION_REQUIRED');
  const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);transport=createSupabaseHttpsTransport({projectId:PROJECT,apiKey:keys.anon});
  phase='genuine-proposer-mfa';const proposer=await existingActorSession({root,config,key,label:'proposer',transport,management,save,file:directory+'01-proposer-session.json'});
  const registration={p_tenant_id:tenant,p_legal_entity_id:entity,p_branch_id:branch,p_action:'register',p_id:subscription,p_expected_version:0,
   p_payload:{url:review.workerConfiguration.receiver.paths.accept,keyRef:'w5/runtime/20261008/delivery/v1'}};
  await save(directory+'02-register-intent.json',{body:registration,actorId:proposer.proof.actorId,actualIntentAt:new Date().toISOString()});
  phase='genuine-accept-registration';const registered=await proposer.request('/rest/v1/rpc/wave5_integration_manage',registration);
  await save(directory+'03-register-response.json',registered);must(registered.ok&&registered.value?.id===subscription,'ACTUAL_ACCEPT_REGISTRATION_REQUIRED');
  phase='genuine-new-event';const clock=(await management('POST','/database/query',{query:'SELECT statement_timestamp()::text AS observed_at',read_only:true})).value[0];
  const now=Date.parse(clock.observed_at),commandId=randomUUID(),body={p_tenant_id:tenant,p_legal_entity_id:entity,p_branch_id:branch,p_command_id:commandId,
   p_idempotency_key:commandId,p_client_timestamp:new Date(now).toISOString(),p_horizon_start:new Date(now).toISOString().slice(0,10),
   p_horizon_end:new Date(now+30*86400000).toISOString().slice(0,10)};
  await save(directory+'04-event-intent.json',{body,commandId,actualIntentAt:new Date().toISOString()});
  const forecast=await proposer.request('/rest/v1/rpc/freeze_pipeline_forecast',body);await save(directory+'05-event-response.json',forecast);
  must(forecast.ok&&isUuid(forecast.value?.entity?.id)&&forecast.value.command_id===commandId,'GENUINE_POST_REGISTRATION_EVENT_REQUIRED');
  const beforeClaim=await read();await save(directory+'06-before-claim.json',beforeClaim);
  must(beforeClaim.subscriptions===1&&beforeClaim.heads.length===0&&beforeClaim.attempts===0&&beforeClaim.quotaPeriods===0,'ONE_NEW_EVENT_BEFORE_CLAIM_REQUIRED');
  phase='two-independent-lease-claims';const left=transport.connection(),right=transport.connection(),claimBody={p_runtime_id:runtime,p_action:'claim',p_payload:{}};
  await save(directory+'07-claim-intent.json',{body:claimBody,actualIntentAt:new Date().toISOString(),connectionIds:[left.connectionId,right.connectionId],
   trustedServiceRole:true,genuineUserSessionNotApplicable:true});
  const claims=await Promise.allSettled([left,right].map(h=>transport.send(h,'/rest/v1/rpc/wave5_runtime_delivery_worker',{bearer:keys.serviceRole,profile:'api',body:claimBody})));
  await save(directory+'08-claim-responses.json',claims.map((r,i)=>r.status==='fulfilled'?{participant:i,...r.value}:{participant:i,status:r.status,failureCode:r.reason?.code??'CLAIM_UNCERTAIN'}));
  must(claims.every(r=>r.status==='fulfilled'&&r.value.ok),'TWO_ACTUAL_LEASE_RESPONSES_REQUIRED');
  const winners=claims.map(r=>r.value).filter(r=>r.value!==null),losers=claims.map(r=>r.value).filter(r=>r.value===null);
  must(winners.length===1&&losers.length===1&&isUuid(winners[0].value?.deliveryId)&&isUuid(winners[0].value?.leaseId),'ONE_ACTUAL_LEASE_WINNER_REQUIRED');
  const afterClaim=await read();await save(directory+'09-after-claim.json',afterClaim);
  const head=afterClaim.heads[0];must(afterClaim.heads.length===1&&head.id===winners[0].value.deliveryId&&head.leaseId===winners[0].value.leaseId
   &&head.state==='leased'&&head.attempt===1&&afterClaim.attempts===1&&afterClaim.quotaPeriods===0&&afterClaim.outcomes===0
   &&afterClaim.receiverReceipts===0&&afterClaim.receipt===beforeClaim.receipt&&afterClaim.audit===beforeClaim.audit
   &&afterClaim.outbox===beforeClaim.outbox&&afterClaim.activeOwnJobs===0&&afterClaim.ticks===0,'EXACT_ONE_LEASE_COMMITTED_DELTA_REQUIRED');
  process.stdout.write(JSON.stringify({phase:'one-lease-proved-waiting-for-natural-expiry',deliveryId:head.id,leaseUntil:head.leaseUntil})+'\n');
  phase='natural-expiry';while(true){must(Date.now()-started<240000,'BOUNDED_LEASE_DURATION_EXCEEDED');
   const actual=await read();if(Date.parse(actual.observedAt)>Date.parse(head.leaseUntil))break;
   await new Promise(resolve=>setTimeout(resolve,15000));}
  const expiry=await transport.send(left,'/rest/v1/rpc/wave5_runtime_delivery_worker',{bearer:keys.serviceRole,profile:'api',body:claimBody});
  await save(directory+'10-natural-expiry-claim.json',expiry);must(expiry.ok&&expiry.value===null,'NATURAL_EXPIRED_LEASE_NO_AUTOMATIC_SEND_REQUIRED');
  const unknown=await read();await save(directory+'11-unknown-before-review.json',unknown);
  must(unknown.heads.length===1&&unknown.heads[0].state==='unknown'&&unknown.quotaPeriods===0&&unknown.receiverReceipts===0,'ACTUAL_UNKNOWN_LEASE_STATE_REQUIRED');
  phase='genuine-mfa-not-sent-review';const reviewId=randomUUID(),reviewBody={p_tenant_id:tenant,p_legal_entity_id:entity,p_branch_id:branch,
   p_delivery_id:head.id,p_review_id:reviewId,p_action:'not_sent',p_reason:'The bounded lease-only test invoked no reservation or network send; exact SQL, TLS requests and committed attempts are retained.'};
  await save(directory+'12-recovery-intent.json',{body:reviewBody,actorId:proposer.proof.actorId,actualIntentAt:new Date().toISOString()});
  const recovery=await proposer.request('/rest/v1/rpc/wave5_delivery_review',reviewBody);await save(directory+'13-recovery-response.json',recovery);
  must(recovery.ok&&recovery.value?.id===head.id&&recovery.value.state==='retry','GENUINE_MFA_LEASE_RECOVERY_REQUIRED');
  const after=await read();await save(directory+'14-after-recovery.json',after);
  must(after.heads.length===1&&after.heads[0].id===head.id&&after.heads[0].state==='retry'&&after.attempts===1&&after.reviews===1
   &&after.quotaPeriods===0&&after.receiverReceipts===0&&after.ticks===0&&after.activeOwnJobs===0,'EXACT_RECOVERED_LEASE_EVIDENCE_REQUIRED');
  const evidence=await save(directory+'99-result.json',{kind:'genuine-one-pending-delivery-lease-and-mfa-recovery',passed:true,projectId:PROJECT,bundleSha256:BUNDLE,
   actualFinishedAt:new Date().toISOString(),proposerMfa:proposer.proof,subscriptionId:subscription,forecastId:forecast.value.entity.id,commandId,
   deliveryId:head.id,leaseId:head.leaseId,reviewId,independentTlsConnections:[left.connectionId,right.connectionId],oneWinnerOneNull:true,
   genuineNaturalExpiry:true,genuineMfaNotSentRecovery:true,leaseDelta:1,usageDelta:0,afterState:'retry',actualDelivery:false,
   externalTransportObserverAvailable:false,unobservedExternalSendCounts:null,fullProviderCoordinatorPassed:false,
   privatePostgresDriverVerified:false,ownerAccepted:false,nativeAccepted:false});
  process.stdout.write(JSON.stringify({passed:true,evidence})+'\n');
 }catch(error){await save(directory+'99-stop.json',{passed:false,phase,failureCode:error.publicCode??error.code??'BOUNDED_LEASE_STOP',
   actualStoppedAt:new Date().toISOString(),automaticRetry:false,earlierMutationMayBeCommitted:true,credentialsPrinted:false});throw error;}
 finally{transport?.close();key.fill(0);config.ownerToken=null;config.encryptionKey=null;}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'BOUNDED_LEASE_STOP',credentialsPrinted:false})+'\n');process.exitCode=1;});
