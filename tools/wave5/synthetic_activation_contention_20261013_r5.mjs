import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport } from './approved_management_installer.mjs';
import { hashBytes,isUuid } from './runtime_contract.mjs';
import { runtimeSealKey } from './private_runtime_seal.mjs';
import { createPrivateKeyReader,selectExistingLegacyKeys } from './private_runtime_http.mjs';
import { createSupabaseHttpsTransport } from './supabase_http_transport.mjs';
import { existingActorSession } from './private_existing_actor_session_20261013_r5.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const tenant='babe6c86-a764-4d3a-80a3-952a7c096c2c';
const must=(ok,code)=>{if(!ok){const e=Error(code);e.publicCode=code;throw e;}};
async function save(file,value){const bytes=JSON.stringify(value,null,2)+'\n',handle=await fs.open(path.join(root,file),'wx');
  try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}return {path:file,sha256:hashBytes(bytes)};}
const snapshotQuery=`SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'subscription',(SELECT to_jsonb(s) FROM billing.tenant_subscriptions s WHERE tenant_id='${tenant}'),
 'activation',(SELECT count(*) FROM intelligence_control.subscription_activations WHERE tenant_id='${tenant}'),
 'revision',(SELECT count(*) FROM intelligence_control.subscription_revisions WHERE tenant_id='${tenant}'),
 'receipt',(SELECT count(*) FROM core.command_receipts WHERE tenant_id='${tenant}'),
 'audit',(SELECT count(*) FROM audit.events WHERE tenant_id='${tenant}'),
 'outbox',(SELECT count(*) FROM core.outbox_events WHERE tenant_id='${tenant}'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='${tenant}'),
 'memberships',(SELECT count(*) FROM core.memberships WHERE tenant_id='${tenant}' AND status IN ('active','invited')),
 'ownJobs',(SELECT count(*) FROM cron.job WHERE jobname IN ('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'))
 ) AS snapshot`;

export function verifyActivationDelta(before,after,response,executionId,revisionId){
  must(response?.request_id===executionId&&isUuid(response?.entity?.id)&&response.entity.revisionId===revisionId
    &&String(response.entity.version)===String(after.subscription.version),'EXACT_ACTUAL_ACTIVATION_RESPONSE_REQUIRED');
  must(after.activation-before.activation===1&&after.receipt-before.receipt===1&&after.audit-before.audit===1
    &&after.outbox-before.outbox===1&&after.revision===before.revision&&after.memberships===before.memberships
    &&after.quotaPeriods===0&&after.subscription.version-before.subscription.version===1
    &&after.subscription.id===before.subscription.id&&after.subscription.seats===before.subscription.seats
    &&after.subscription.plan_code===before.subscription.plan_code,'EXACT_SINGLE_ACTIVATION_COMMIT_REQUIRED');
  return true;
}
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute'].includes(mode)&&process.argv.length<=3,'EXACT_ACTIVATION_MODE_REQUIRED');
 const {review}=await loadApprovedInputs();must(review.syntheticScopes.find(s=>s.key==='runtime')?.tenantId===tenant,'EXACT_REVIEWED_RUNTIME_SCOPE_REQUIRED');
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,scope:'runtime',networkCalls:0,newAccounts:0,newFactors:0})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),management=createManagementTransport(config.ownerToken);
 const directory=base+'synthetic-activation-contention-20261013-r5-'+Date.now()+'/';await fs.mkdir(path.join(root,directory));
 let phase='once-intent',transport;const started=Date.now();
 try{await save(base+'synthetic-activation-contention-once-20261013-r5.json',{kind:'actual-synthetic-activation-once-intent',projectId:PROJECT,
    bundleSha256:BUNDLE,directory,actualStartedAt:new Date().toISOString(),maximumDurationMs:180000,maximumRevisionCommands:1,
    maximumActivationRequests:2,automaticRetry:false,production:false,realBilling:false});
   const read=async(query=snapshotQuery)=>{must(Date.now()-started<180000,'BOUNDED_ACTIVATION_DURATION_EXCEEDED');
     return (await management('POST','/database/query',{query,read_only:true})).value;};
   phase='before-read';const before=(await read())[0].snapshot;await save(directory+'00-before.json',before);
   must(before.quotaPeriods===0&&before.activation===0&&before.revision===0&&before.ownJobs===0
     &&before.subscription.version===1&&before.subscription.seats===5&&before.memberships<=5,'ACTIVATION_BEFORE_USAGE_REQUIRED');
   const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);
   transport=createSupabaseHttpsTransport({projectId:PROJECT,apiKey:keys.anon});
   phase='genuine-billing-mfa';const billing=await existingActorSession({root,config,key,label:'billing-admin',transport,management,save,
     file:directory+'01-billing-session.json'});
   phase='schedule-original-revision';const now=Date.parse((await read('SELECT statement_timestamp()::text AS observed_at'))[0].observed_at);
   const commandId=randomUUID(),body={p_tenant_id:tenant,p_command_id:commandId,p_idempotency_key:commandId,p_client_timestamp:new Date(now).toISOString(),
     p_expected_version:before.subscription.version,p_plan_code:before.subscription.plan_code,p_seats:before.subscription.seats,
     p_trial_starts_at:new Date(now-1000).toISOString(),p_trial_ends_at:before.subscription.trial_ends_at};
   await save(directory+'02-schedule-intent.json',{commandId,body,actorId:billing.proof.actorId,actualIntentAt:new Date().toISOString()});
   const scheduled=await billing.request('/rest/v1/rpc/schedule_synthetic_subscription',body);
   await save(directory+'03-schedule-response.json',scheduled);must(scheduled.ok&&isUuid(scheduled.value?.entity?.id),'ACTUAL_SYNTHETIC_SCHEDULE_REQUIRED');
   const revisionId=scheduled.value.entity.id;
   const rows=await read(`SELECT id,tenant_id,actor_id,request_id,execution_id,expected_version FROM intelligence_control.subscription_revisions WHERE tenant_id='${tenant}' AND id='${revisionId}'`);
   must(rows.length===1&&rows[0].request_id===commandId&&rows[0].actor_id===billing.proof.actorId&&isUuid(rows[0].execution_id),'ACTUAL_REVISION_PROVENANCE_REQUIRED');
   const afterSchedule=(await read())[0].snapshot;await save(directory+'04-after-schedule.json',{...afterSchedule,revision:rows[0]});
   must(afterSchedule.revision===1&&afterSchedule.activation===0&&afterSchedule.receipt-before.receipt===1
     &&afterSchedule.audit-before.audit===1&&afterSchedule.outbox-before.outbox===1&&afterSchedule.subscription.version===before.subscription.version
     &&afterSchedule.quotaPeriods===0,'EXACT_SCHEDULE_COMMIT_REQUIRED');
   phase='two-independent-trusted-connections';const left=transport.connection(),right=transport.connection();
   must(left.connectionId!==right.connectionId,'INDEPENDENT_TLS_CONNECTIONS_REQUIRED');
   const activationBody={p_tenant_id:tenant,p_revision_id:revisionId};
   await save(directory+'05-contention-intent.json',{revisionId,executionId:rows[0].execution_id,body:activationBody,
     actualIntentAt:new Date().toISOString(),connections:[left.connectionId,right.connectionId],trustedServiceRole:true,
     genuineUserSessionNotApplicable:true,method:'Two separate verified TLS agents issuing the same original revision concurrently.'});
   const results=await Promise.allSettled([left,right].map(handle=>transport.send(handle,'/rest/v1/rpc/apply_synthetic_subscription',
     {bearer:keys.serviceRole,profile:'api',body:activationBody})));
   await save(directory+'06-contention-responses.json',results.map((r,i)=>r.status==='fulfilled'?{participant:i,status:r.status,...r.value}:
     {participant:i,status:r.status,failureCode:r.reason?.publicCode??r.reason?.code??'ACTIVATION_TRANSPORT_UNCERTAIN'}));
   must(results.every(r=>r.status==='fulfilled'&&r.value.ok),'TWO_ACTUAL_ACTIVATION_RESPONSES_REQUIRED');
   const responses=results.map(r=>r.value);must(JSON.stringify(responses[0].value)===JSON.stringify(responses[1].value),'ORIGINAL_ACTIVATION_REPLAY_REQUIRED');
   phase='committed-after-read';const after=(await read())[0].snapshot;await save(directory+'07-after-activation.json',after);
   verifyActivationDelta(afterSchedule,after,responses[0].value,rows[0].execution_id,revisionId);
   const evidence=await save(directory+'99-result.json',{kind:'actual-synthetic-activation-contention',passed:true,projectId:PROJECT,bundleSha256:BUNDLE,
     actualFinishedAt:new Date().toISOString(),tenantId:tenant,genuineBillingAal2:billing.proof,
     revisionId,executionId:rows[0].execution_id,participants:2,independentTlsConnectionIds:[left.connectionId,right.connectionId],
     originalResponsesIdentical:true,committedActivationRowsAdded:1,subscriptionVersionDelta:1,receiptAuditOutboxDeltaEach:1,
     quotaPeriods:0,privatePostgresDriverVerified:false,fullProviderCoordinatorPassed:false,fullExternalTransportObserverAvailable:false,
     unobservedModelOrDeliveryTransportCounts:null,nativeAccepted:false,ownerAccepted:false,realBilling:false,production:false});
   process.stdout.write(JSON.stringify({passed:true,evidence})+'\n');
 }catch(error){const failureCode=error.publicCode??error.code??'BOUNDED_ACTIVATION_STOP';
   await save(directory+'99-stop.json',{passed:false,phase,failureCode,actualStoppedAt:new Date().toISOString(),automaticRetry:false,
     earlierMutationMayBeCommitted:true,credentialPrinted:false});throw error;
 }finally{transport?.close();key.fill(0);config.ownerToken=null;config.encryptionKey=null;}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'BOUNDED_ACTIVATION_STOP',credentialPrinted:false})+'\n');process.exitCode=1;});
