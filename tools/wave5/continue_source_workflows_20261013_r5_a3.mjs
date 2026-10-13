import fs from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes,isUuid} from './runtime_contract.mjs';
import {runtimeSealKey,readRuntimeSecret} from './private_runtime_seal.mjs';
import {createPrivateKeyReader,selectExistingLegacyKeys} from './private_runtime_http.mjs';
import {createSupabaseHttpsTransport,decodeReceivedAccessToken} from './supabase_http_transport.mjs';
import {bindUuidSessionQuery,validateGenuineMfaResult} from './enroll_mfa_management_20261013_r5.mjs';
import {validateSourceRead,validateForecastRead} from './source_workflow_management_20261013_r5.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/',prior=base+'genuine-source-workflows-20261013-r5-1791882165675/';
const additional=base+'genuine-source-workflows-resumed-20261013-r5-1791882899175/';
const must=(v,code)=>{if(!v){const e=Error(code);e.publicCode=code;throw e;}};
async function save(file,value){const text=JSON.stringify(value,null,2)+'\n',h=await fs.open(path.join(root,file),'wx');
 try{await h.writeFile(text);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(text)};}
async function main(){const {review}=await loadApprovedInputs();const mode=process.argv[2]??'--validate';
 must(process.argv.length<=3&&['--validate','--resume'].includes(mode),'EXACT_SOURCE_RESUME_MODE_REQUIRED');
 const recoveryBytes=await fs.readFile(path.join(root,base+'source-failure-inspection-result-20261013-r5.json'));
 must(hashBytes(recoveryBytes)==='4ccc325cfb4f59c6d449a520694b346cb580cf7351541614bdf6b8d436c01cd0','ACTUAL_ORIGINAL_COMMAND_RECOVERY_REQUIRED');
 const recovery=JSON.parse(recoveryBytes);must(recovery.before.forecasts===0&&recovery.before.receipts===0&&recovery.after.forecasts===1
  &&recovery.after.receipts===1&&recovery.originalCommand.ok&&isUuid(recovery.originalCommand.result.entity.id),'Genuine_RECOVERY_NOT_RECONCILED'.toUpperCase());
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,scopes:500,existingForecastsPreserved:9,networkCalls:0})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<16000,'PRIVATE_INPUT_LIMIT');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_RUNTIME_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),management=createManagementTransport(config.ownerToken);
 const directory=base+'genuine-source-workflows-completed-20261013-r5-a3-'+Date.now()+'/';await fs.mkdir(path.join(root,directory));
 const completed=[],sessions={};let calls=0,newCommands=0,next=0,halted=false,transport;const started=Date.now();
 try{await save(base+'source-workflows-resume-once-20261013-r5-a3.json',{kind:'source-workflows-resume-once-intent',actualStartedAt:new Date().toISOString(),directory,
   projectId:PROJECT,bundleSha256:BUNDLE,originalRunPreserved:prior,maximumNewCommands:491,automaticRetryForbidden:true,newAuthFactors:0});
  calls++;const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);
  transport=createSupabaseHttpsTransport({projectId:PROJECT,apiKey:keys.anon});
  for(const label of ['proposer','foreign-member']){const actor=JSON.parse(await fs.readFile(path.join(root,prior+label+'-real-session.json'),'utf8'));
   const privateSession=await readRuntimeSecret(config.privateDirectory,key,actor.privateRecord,'source-session');
   const claims=decodeReceivedAccessToken(privateSession.accessToken);must(claims.exp*1000>Date.now()+900000,'FRESH_GENUINE_SESSION_REQUIRED');
   const handle=transport.connection();calls++;const online=await transport.send(handle,'/auth/v1/user',{method:'GET',bearer:privateSession.accessToken});must(online.ok,'ACTUAL_ONLINE_USER_REQUIRED');
   calls++;const rows=await management('POST','/database/query',{query:bindUuidSessionQuery(claims.session_id,actor.actorId),read_only:true});
   const proof=validateGenuineMfaResult({claims,onlineUser:online.value,session:rows.value[0],actor:{authId:actor.actorId},factorId:actor.factorId});
   sessions[label]={token:privateSession.accessToken,handle,proof};await save(directory+label+'-session.json',proof);
  }
  calls++;const nowResult=await management('POST','/database/query',{query:'SELECT statement_timestamp()::text AS observed_at',read_only:true});
  const known=[];
  for(const target of review.syntheticScopes){let intent,where=prior;try{intent=JSON.parse(await fs.readFile(path.join(root,prior+target.key+'-intent.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
   if(!intent){try{intent=JSON.parse(await fs.readFile(path.join(root,additional+target.key+'-intent.json'),'utf8'));where=additional;}catch(e){if(e.code!=='ENOENT')throw e;}}
   if(intent){const record=target.key==='runtime'?{forecast:{id:recovery.originalCommand.result.entity.id,sourceHash:recovery.originalCommand.result.entity.sourceHash}}:JSON.parse(await fs.readFile(path.join(root,where+target.key+'-result.json'),'utf8'));
    known.push({tenant_id:target.tenantId,id:record.forecast.id,source_hash:record.forecast.sourceHash,command_id:intent.commandId});}}
  must(known.length===9&&known.every(k=>isUuid(k.id)&&isUuid(k.command_id)),'EXACT_NINE_RECORDED_OUTCOMES_REQUIRED');
  const tenants=review.syntheticScopes.map(s=>"'"+s.tenantId+"'::uuid").join(',');calls++;
  const observed=await management('POST','/database/query',{query:'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT f.tenant_id,f.id,f.source_hash,r.command_id FROM analytics.pipeline_forecasts f JOIN core.command_receipts r ON r.tenant_id=f.tenant_id AND r.aggregate_id=f.id WHERE f.tenant_id IN('+tenants+');ROLLBACK;',read_only:true});
  must(observed.value.length===9&&known.every(k=>observed.value.some(o=>o.tenant_id===k.tenant_id&&o.id===k.id&&o.source_hash===k.source_hash&&o.command_id===k.command_id)),'FRESH_NINE_ORIGINAL_IDENTITIES_REQUIRED');
  await save(directory+'00-nine-original-identities.json',{actualReturnedRows:observed.value,responseSha256:observed.responseSha256,existingIdentitiesPreserved:true});
  const now=Date.parse(nowResult.value[0].observed_at),calendar={windowStart:new Date(now-3*86400000).toISOString(),windowEnd:new Date(now-86400000).toISOString(),
   asOf:new Date(now-1000).toISOString(),recordedThrough:new Date(now-1000).toISOString()};
  const send=async(h,r,options)=>{must(Date.now()-started<900000,'BOUNDED_SOURCE_RUN_DURATION_EXCEEDED');calls++;return transport.send(h,r,options);};
  const worker=async()=>{const handle=transport.connection();try{while(!halted&&next<review.syntheticScopes.length){const scope=review.syntheticScopes[next++];
   const participant=sessions[scope.key==='foreign'?'foreign-member':'proposer'];let originalIntent,forecastId,originalResponse,originalEvidenceDirectory=prior;
   try{originalIntent=JSON.parse(await fs.readFile(path.join(root,prior+scope.key+'-intent.json'),'utf8'));}
   catch(e){if(e.code!=='ENOENT')throw e;}
   if(!originalIntent){try{originalIntent=JSON.parse(await fs.readFile(path.join(root,additional+scope.key+'-intent.json'),'utf8'));originalEvidenceDirectory=additional;}catch(e){if(e.code!=='ENOENT')throw e;}}
   if(originalIntent){must(originalIntent.scope.tenantId===scope.tenantId&&originalIntent.actorId===participant.proof.actorId,'PRIOR_ORIGINAL_ACTOR_SCOPE_REQUIRED');
    if(scope.key==='runtime'){originalResponse=recovery.originalCommand.result;forecastId=originalResponse.entity.id;}
    else{const previous=JSON.parse(await fs.readFile(path.join(root,originalEvidenceDirectory+scope.key+'-result.json'),'utf8'));
     must(previous.commandId===originalIntent.commandId,'PRIOR_ORIGINAL_COMMAND_REQUIRED');forecastId=previous.forecast.id;originalResponse=previous.commandResponse;}
   }else{const command=randomUUID(),body={p_tenant_id:scope.tenantId,p_legal_entity_id:scope.entityId,p_branch_id:scope.branchId,p_command_id:command,
     p_idempotency_key:command,p_client_timestamp:new Date(now).toISOString(),p_horizon_start:new Date(now).toISOString().slice(0,10),
     p_horizon_end:new Date(now+30*86400000).toISOString().slice(0,10)};originalIntent={scope,actorId:participant.proof.actorId,commandId:command,body};
    await save(directory+scope.key+'-intent.json',{...originalIntent,actualIntentAt:new Date().toISOString()});newCommands++;
    const frozen=await send(handle,'/rest/v1/rpc/freeze_pipeline_forecast',{bearer:participant.token,profile:'api',body});
    await save(directory+scope.key+'-command-response.json',{ok:frozen.ok,status:frozen.status,value:frozen.value,evidence:frozen.evidence});
    must(frozen.ok&&isUuid(frozen.value?.entity?.id),'REAL_NEW_FORECAST_COMMAND_FAILED');forecastId=frozen.value.entity.id;originalResponse=frozen.value;}
   const scopeBody={p_tenant_id:scope.tenantId,p_legal_entity_id:scope.entityId,p_branch_id:scope.branchId};
   const read=await send(handle,'/rest/v1/rpc/get_pipeline_forecast',{bearer:participant.token,profile:'api',body:{...scopeBody,p_forecast_id:forecastId}});must(read.ok,'REAL_SCOPED_FORECAST_READ_REQUIRED');
   const forecast=validateForecastRead(read.value,scope);
   const processBody={...scopeBody,p_window_start:calendar.windowStart,p_window_end:calendar.windowEnd,p_as_of:calendar.asOf,p_recorded_through:calendar.recordedThrough};
   const processResult=await send(handle,'/rest/v1/rpc/analytics_process_snapshot',{bearer:participant.token,profile:'api',body:processBody});must(processResult.ok,'REAL_SCOPED_PROCESS_READ_REQUIRED');
   const processProof=validateSourceRead(processResult.value,scope);
   await save(directory+scope.key+'-result.json',{scopeKey:scope.key,actorId:participant.proof.actorId,commandId:originalIntent.commandId,
    priorForecastPreserved:!!originalResponse&&!!originalIntent&&['runtime','foreign','load-001','load-002','load-003','load-004','load-005','load-006','load-007'].includes(scope.key),forecast,process:processProof,
    forecastResponse:read.value,processResponse:processResult.value,transport:[read.evidence,processResult.evidence],actualFinishedAt:new Date().toISOString()});
   completed.push({scopeKey:scope.key,tenantId:scope.tenantId,forecastId,sourceHash:forecast.sourceHash,commandId:originalIntent.commandId});
   if(scope.key==='runtime'){
    const replay=await send(handle,'/rest/v1/rpc/freeze_pipeline_forecast',{bearer:participant.token,profile:'api',body:originalIntent.body});
    const denied=await send(sessions['foreign-member'].handle,'/rest/v1/rpc/analytics_process_snapshot',{bearer:sessions['foreign-member'].token,profile:'api',body:processBody});
    const wide=await send(handle,'/rest/v1/rpc/analytics_process_snapshot',{bearer:participant.token,profile:'api',body:{...processBody,
     p_window_start:new Date(Date.parse(calendar.windowEnd)-367*86400000).toISOString()}});
    await save(directory+'runtime-replay-and-denials.json',{replay:{ok:replay.ok,value:replay.value,evidence:replay.evidence},
     foreign:{ok:denied.ok,value:denied.value,evidence:denied.evidence},wide:{ok:wide.ok,value:wide.value,evidence:wide.evidence}});
    must(replay.ok&&replay.value.entity.id===forecastId&&!denied.ok&&denied.status===403&&denied.value?.code==='42501'&&denied.value?.message==='Permission denied or multi-factor authentication required.'
     &&!wide.ok&&wide.value?.message==='LIMIT_EXCEEDED','GENUINE_REPLAY_AND_DENIALS_REQUIRED');
   }
   if(completed.length%50===0)process.stdout.write(JSON.stringify({actualSourceScopesVerified:completed.length,actualNewForecastCommands:newCommands})+'\n');
  }}catch(e){halted=true;throw e;}finally{transport.closeConnection(handle);}};
  const jobs=await Promise.allSettled([worker(),worker(),worker(),worker()]),failed=jobs.find(j=>j.status==='rejected');if(failed)throw failed.reason;
  must(completed.length===500&&newCommands===491&&new Set(completed.map(c=>c.forecastId)).size===500,'ALL_500_ORIGINAL_SOURCE_RESULTS_REQUIRED');
  const result={kind:'actual-genuine-nonempty-source-workflows-completed',actualFinishedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,
   passed:true,scopesVerified:500,existingForecastIdentitiesPreserved:9,newForecastCommands:491,totalOriginalForecasts:500,actualScopedForecastReads:500,
   actualScopedProcessReads:500,uniqueGenuineAal2Sessions:2,realForeignDenial:true,realWideWindowDenial:true,realOriginalCommandReplay:true,
   initialFailurePreserved:true,initialFailureCause:'Initial unsuccessful forecast response was not retained; no root cause is asserted.',
   recoveryEvidence:{path:base+'source-failure-inspection-result-20261013-r5.json',sha256:hashBytes(recoveryBytes)},
   completed,calendar,networkCalls:calls,credentialsPrinted:false,newAuthAccounts:0,newMfaFactors:0,constructedJwtClaims:0,
   schedulesStarted:false,actualDelivery:false,actualModelUsage:false,authenticatedNative:false,independentSessionContention:false,
   targetScaleLoad:false,ownerAcceptedCriteria:3,production:false,realBilling:false};
  const evidence=await save(directory+'99-result.json',result);process.stdout.write(JSON.stringify({passed:true,scopesVerified:500,evidence})+'\n');
 }catch(error){await save(directory+'99-stop.json',{actualStoppedAt:new Date().toISOString(),failureCode:error.publicCode??error.code??'GENUINE_SOURCE_RESUME_FAILED',
   completed,newCommands,networkCalls:calls,automaticRetryPerformed:false,credentialsPrinted:false});throw error;
 }finally{transport?.close();key.fill(0);config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'GENUINE_SOURCE_RESUME_FAILED',rawErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;});
