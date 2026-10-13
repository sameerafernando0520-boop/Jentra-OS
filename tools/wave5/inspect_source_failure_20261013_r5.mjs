import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
import {runtimeSealKey,readRuntimeSecret} from './private_runtime_seal.mjs';
import {createPrivateKeyReader,selectExistingLegacyKeys} from './private_runtime_http.mjs';
import {createSupabaseHttpsTransport,decodeReceivedAccessToken} from './supabase_http_transport.mjs';
import {bindUuidSessionQuery,validateGenuineMfaResult} from './enroll_mfa_management_20261013_r5.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const prior=base+'genuine-source-workflows-20261013-r5-1791882165675/';
const must=(v,code)=>{if(!v){const e=Error(code);e.publicCode=code;throw e;}};
async function save(name,value){const text=JSON.stringify(value,null,2)+'\n',h=await fs.open(path.join(root,base+name),'wx');
 try{await h.writeFile(text);await h.sync();}finally{await h.close();}return {path:base+name,sha256:hashBytes(text)};}
const stateSql=`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT jsonb_build_object(
 'forecasts',(SELECT count(*) FROM analytics.pipeline_forecasts WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'receipts',(SELECT count(*) FROM core.command_receipts WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'audit',(SELECT count(*) FROM audit.events WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),
 'outbox',(SELECT count(*) FROM core.outbox_events WHERE tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c')) AS state;ROLLBACK;`;
function publicResponse(response){const value=response.value;
 const safeText=text=>typeof text==='string'&&text.length<=1500&&!/sbp_|eyJ[A-Za-z0-9_-]{12}|sk-[A-Za-z0-9]{12}/.test(text)?text:null;
 return {ok:response.ok,status:response.status,evidence:response.evidence,
  result:response.ok?value:{code:safeText(value?.code),message:safeText(value?.message),details:safeText(value?.details),hint:safeText(value?.hint)}};}
async function main(){await loadApprovedInputs();const mode=process.argv[2]??'--validate';
 must(process.argv.length<=3&&['--validate','--inspect'].includes(mode),'EXACT_SOURCE_INSPECTION_MODE_REQUIRED');
 const intent=JSON.parse(await fs.readFile(path.join(root,prior+'runtime-intent.json'),'utf8')),
  actor=JSON.parse(await fs.readFile(path.join(root,prior+'proposer-real-session.json'),'utf8'));
 must(intent.body.p_command_id==='ad46d9da-607f-446d-b3c2-1c0e8a1adbc9'&&intent.scope.tenantId==='babe6c86-a764-4d3a-80a3-952a7c096c2c'
  &&actor.actorId==='8b740ab8-24f7-4455-a78b-aea0d99d20f6','EXACT_PREVIOUS_ORIGINAL_IDENTITIES_REQUIRED');
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,newCommands:0,originalCommandOnly:true})+'\n');return;}
 let incoming='';for await(const c of process.stdin){incoming+=c;must(incoming.length<16000,'PRIVATE_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),management=createManagementTransport(config.ownerToken);let transport;
 try{await save('source-failure-inspection-once-20261013-r5.json',{kind:'actual-source-failure-inspection-intent',actualIntentAt:new Date().toISOString(),
   projectId:PROJECT,bundleSha256:BUNDLE,originalCommandId:intent.commandId,newCommandIds:0,automaticRetryForbidden:true});
  const privateSession=await readRuntimeSecret(config.privateDirectory,key,actor.privateRecord,'source-session');
  const claims=decodeReceivedAccessToken(privateSession.accessToken);must(claims.sub===actor.actorId&&claims.aal==='aal2','GENUINE_SOURCE_SESSION_REQUIRED');
  const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);
  transport=createSupabaseHttpsTransport({projectId:PROJECT,apiKey:keys.anon});const handle=transport.connection();
  const online=await transport.send(handle,'/auth/v1/user',{method:'GET',bearer:privateSession.accessToken});must(online.ok,'REAL_ONLINE_USER_REQUIRED');
  const session=await management('POST','/database/query',{query:bindUuidSessionQuery(claims.session_id,actor.actorId),read_only:true});
  const mfa=validateGenuineMfaResult({claims,onlineUser:online.value,session:session.value[0],actor:{authId:actor.actorId},factorId:actor.factorId});
  const before=await management('POST','/database/query',{query:stateSql,read_only:true});
  must(before.value[0].state.forecasts===0&&before.value[0].state.receipts===0,'PREVIOUS_RUNTIME_COMMAND_OUTCOME_RECONCILIATION_REQUIRED');
  const now=Date.parse(session.value[0].observed_at),processBody={p_tenant_id:intent.scope.tenantId,p_legal_entity_id:intent.scope.entityId,p_branch_id:intent.scope.branchId,
   p_window_start:new Date(now-3*86400000).toISOString(),p_window_end:new Date(now-86400000).toISOString(),p_as_of:new Date(now-1000).toISOString(),p_recorded_through:new Date(now-1000).toISOString()};
  const processResult=await transport.send(handle,'/rest/v1/rpc/analytics_process_snapshot',{profile:'api',bearer:privateSession.accessToken,body:processBody});
  const original=await transport.send(handle,'/rest/v1/rpc/freeze_pipeline_forecast',{profile:'api',bearer:privateSession.accessToken,body:intent.body});
  const after=await management('POST','/database/query',{query:stateSql,read_only:true});
  const result={kind:'actual-genuine-runtime-source-failure-inspection',actualFinishedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,
   mfa,before:before.value[0].state,after:after.value[0].state,process:publicResponse(processResult),originalCommand:publicResponse(original),
   originalCommandId:intent.commandId,newCommands:0,originalCommandRepeatedOnlyAfterFreshZeroOutcomeProof:true,
   zeroEffects:JSON.stringify(before.value[0].state)===JSON.stringify(after.value[0].state),networkCalls:7,credentialsPrinted:false,
   automaticRetryPerformed:false,allSourceWorkflowsPassed:false,ownerAcceptedCriteria:3,production:false,realBilling:false};
  const evidence=await save('source-failure-inspection-result-20261013-r5.json',result);
  process.stdout.write(JSON.stringify({observed:true,processStatus:processResult.status,originalCommandStatus:original.status,
   originalErrorCode:original.ok?null:original.value?.code,evidence})+'\n');
 }finally{transport?.close();key.fill(0);config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'SOURCE_FAILURE_INSPECTION_FAILED',rawErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;});
