import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { PROJECT,BUNDLE,loadApprovedInputs,createManagementTransport } from './approved_management_installer.mjs';
import { hashBytes,isUuid } from './runtime_contract.mjs';
import { runtimeSealKey,readRuntimeSecret,appendRuntimeSecret } from './private_runtime_seal.mjs';
import { createPrivateKeyReader,selectExistingLegacyKeys } from './private_runtime_http.mjs';
import { createSupabaseHttpsTransport,decodeReceivedAccessToken,totpFromPrivateSecret } from './supabase_http_transport.mjs';
import { bindUuidSessionQuery,validateGenuineMfaResult } from './enroll_mfa_management_20261013_r5.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const mfaFile=base+'genuine-mfa-20261013-r5-1791878507585/99-result.json';
const authFile=base+'auth-admin-provisioning-20261013-r5-1791877892653/99-result.json';
const must=(v,code)=>{if(!v){const e=Error(code);e.publicCode=code;throw e;}};
async function save(file,value){const bytes=JSON.stringify(value,null,2)+'\n',h=await fs.open(path.join(root,file),'wx');
 try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(bytes)};}
export function validateSourceRead(value,scope){
 must(value?.source?.complete===true&&value.source.sourceCount===4&&value.source.tenantId===scope.tenantId
  &&value.source.legalEntityId===scope.entityId&&value.source.branchId===scope.branchId&&value.observations?.length===4
  &&new Set(value.observations.map(o=>o.id)).size===4&&value.observations.every(o=>o.tenantId===scope.tenantId&&o.legalEntityId===scope.entityId
   &&o.branchId===scope.branchId&&/^\d+\.\d{6}$/.test(o.activeMinutes)&&/^\d+\.\d{6}$/.test(o.waitMinutes)),'EXACT_NONEMPTY_PROCESS_PROJECTION_REQUIRED');
 const micros=text=>{const [whole,fraction]=text.split('.');return BigInt(whole)*1000000n+BigInt(fraction);};
 const active=value.observations.reduce((n,o)=>n+micros(o.activeMinutes),0n),wait=value.observations.reduce((n,o)=>n+micros(o.waitMinutes),0n);
 must(active===81250000n&&wait===34250000n&&value.observations.filter(o=>o.completedAt!==null).length===2,'EXACT_PROCESS_NUMERICS_REQUIRED');
 return {sourceCount:4,activeMinutes:'81.250000',waitMinutes:'34.250000',completed:2,open:2,sourceManifestHash:value.source.sourceManifestHash};
}
export function validateForecastRead(value,scope){
 must(isUuid(value?.id)&&hashBytes(value.canonicalText)===value.sourceHash&&value.evidence?.complete===true
  &&value.evidence.sourceCount===2&&value.evidence.tenantId===scope.tenantId&&value.evidence.legalEntityId===scope.entityId
  &&value.evidence.branchId===scope.branchId&&value.evidence.observations?.length===2,'EXACT_NONEMPTY_FORECAST_REQUIRED');
 const groups=value.evidence.currencies;must(groups?.length===2&&groups.some(g=>g.currency==='USD'&&g.population===1&&g.amount==='1000.000001'&&g.weightedAmount==='333.300000')
  &&groups.some(g=>g.currency==='LKR'&&g.population===1&&g.amount==='2000.125000'&&g.weightedAmount==='1000.062500'),'EXACT_FORECAST_DECIMALS_REQUIRED');
 return {id:value.id,sourceHash:value.sourceHash,sourceCount:2,currencies:groups};
}
async function main(){const mode=process.argv[2]??'--validate';must(['--validate','--execute'].includes(mode)&&process.argv.length<=3,'EXACT_SOURCE_WORKFLOW_MODE_REQUIRED');
 const {review}=await loadApprovedInputs();for(const [file,sha]of [[mfaFile,'af4e9dec3987f5d6ba8c49fc1162be1374f93a14c043e46065119297a73e0bba'],
  [authFile,'f8a67d9a2659bb4185d71c05c1a7644e5248e56c72fded4af297e3a2d3888abb']])must(hashBytes(await fs.readFile(path.join(root,file)))===sha,'EXACT_ACTUAL_AUTH_MFA_REQUIRED');
 const sourceProof=JSON.parse(await fs.readFile(path.join(root,base+'source-population-after-commit-20261013-r5.json'),'utf8'));
 must(sourceProof.passed&&sourceProof.exactScopes===500&&sourceProof.existingOutsideScopeHashesUnchanged,'GENUINE_SOURCE_POPULATION_REQUIRED');
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,sourceScopes:500,networkCalls:0,authEnrollment:0})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_INPUT_TOO_LONG');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_RUNTIME_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),management=createManagementTransport(config.ownerToken);
 const mfa=JSON.parse(await fs.readFile(path.join(root,mfaFile),'utf8')),auth=JSON.parse(await fs.readFile(path.join(root,authFile),'utf8'));
 const directory=base+'genuine-source-workflows-20261013-r5-'+Date.now()+'/';await fs.mkdir(path.join(root,directory));
 let phase='once-only-intent',calls=0,transport;const sessions={},completed=[];const started=Date.now();
 try{await save(base+'genuine-source-workflows-once-20261013-r5.json',{kind:'genuine-source-workflows-once-intent',actualStartedAt:new Date().toISOString(),directory,
  projectId:PROJECT,bundleSha256:BUNDLE,scopes:500,maximumForecastCommands:500,maximumDurationMs:900000,automaticRetryForbidden:true,newFactorEnrollmentForbidden:true});
  phase='private-keys';calls++;const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);
  transport=createSupabaseHttpsTransport({projectId:PROJECT,apiKey:keys.anon});
  const send=async(handle,route,options)=>{must(Date.now()-started<900000,'BOUNDED_SOURCE_DURATION_EXCEEDED');calls++;return transport.send(handle,route,options);};
  for(const label of ['proposer','foreign-member']){
   phase='existing-factor-real-session';const actor=auth.accounts.find(a=>a.label===label),prior=mfa.actors.find(a=>a.label===label);
   const credentials=await readRuntimeSecret(config.privateDirectory,key,actor.privateRecord,'account-created');
   const factor=await readRuntimeSecret(config.privateDirectory,key,prior.factorPrivateRecord,'factor-verified');
   must(credentials.authId===actor.authId&&factor.authId===actor.authId&&factor.factorId===prior.factorId,'EXACT_PRIVATE_ACTOR_FACTOR_REQUIRED');
   const handle=transport.connection(),signed=await send(handle,'/auth/v1/token?grant_type=password',{body:{email:actor.email,password:credentials.password}});
   must(signed.ok&&signed.value.user.id===actor.authId,'ACTUAL_PRIVATE_SIGNIN_REQUIRED');
   const challenge=await send(handle,`/auth/v1/factors/${factor.factorId}/challenge`,{bearer:signed.value.access_token,body:{}});must(challenge.ok&&isUuid(challenge.value?.id),'REAL_EXISTING_FACTOR_CHALLENGE_REQUIRED');
   calls++;const clock=await management('POST','/database/query',{query:'SELECT statement_timestamp()::text AS observed_at',read_only:true});
   const now=Date.parse(clock.value[0].observed_at);must(Number.isFinite(now),'ACTUAL_SERVER_CLOCK_REQUIRED');
   const verified=await send(handle,`/auth/v1/factors/${factor.factorId}/verify`,{bearer:signed.value.access_token,
    body:{challenge_id:challenge.value.id,code:totpFromPrivateSecret(factor.secret,now)}});must(verified.ok,'REAL_EXISTING_FACTOR_VERIFICATION_REQUIRED');
   const claims=decodeReceivedAccessToken(verified.value.access_token),online=await send(handle,'/auth/v1/user',{method:'GET',bearer:verified.value.access_token});
   must(online.ok,'REAL_ONLINE_AUTH_REQUIRED');calls++;const row=await management('POST','/database/query',{query:bindUuidSessionQuery(claims.session_id,actor.authId),read_only:true});
   const proof=validateGenuineMfaResult({claims,onlineUser:online.value,session:row.value[0],actor,factorId:factor.factorId});
   const privateRecord=await appendRuntimeSecret(config.privateDirectory,key,'source-session',{label,authId:actor.authId,accessToken:verified.value.access_token,
    refreshToken:verified.value.refresh_token,sessionId:claims.session_id,expiresAt:new Date(claims.exp*1000).toISOString()});
   sessions[label]={token:verified.value.access_token,handle,proof,privateRecord};await save(directory+label+'-real-session.json',{...proof,label,privateRecord});
  }
  phase='real-source-calendar';calls++;const clock=await management('POST','/database/query',{query:'SELECT statement_timestamp()::text AS observed_at',read_only:true});
  const serverTime=Date.parse(clock.value[0].observed_at),date=new Date(serverTime).toISOString().slice(0,10),end=new Date(serverTime+30*86400000).toISOString().slice(0,10);
  const calendar={windowStart:new Date(serverTime-3*86400000).toISOString(),windowEnd:new Date(serverTime-86400000).toISOString(),asOf:new Date(serverTime-1000).toISOString(),recordedThrough:new Date(serverTime-1000).toISOString()};
  let next=0,halted=false;
  const work=async()=>{const handle=transport.connection();try{while(!halted&&next<review.syntheticScopes.length){const scope=review.syntheticScopes[next++];
   phase='genuine-user-forecast-'+scope.key;const participant=sessions[scope.key==='foreign'?'foreign-member':'proposer'];
   const command=randomUUID(),body={p_tenant_id:scope.tenantId,p_legal_entity_id:scope.entityId,p_branch_id:scope.branchId,p_command_id:command,
    p_idempotency_key:command,p_client_timestamp:new Date(serverTime).toISOString(),p_horizon_start:date,p_horizon_end:end};
   await save(directory+scope.key+'-intent.json',{scope,commandId:command,body,actorId:participant.proof.actorId,actualIntentAt:new Date().toISOString()});
   const frozen=await send(handle,'/rest/v1/rpc/freeze_pipeline_forecast',{bearer:participant.token,profile:'api',body});
   must(frozen.ok&&isUuid(frozen.value?.entity?.id),'REAL_FORECAST_COMMAND_FAILED');
   const read=await send(handle,'/rest/v1/rpc/get_pipeline_forecast',{bearer:participant.token,profile:'api',body:{p_tenant_id:scope.tenantId,
    p_legal_entity_id:scope.entityId,p_branch_id:scope.branchId,p_forecast_id:frozen.value.entity.id}});must(read.ok,'REAL_FORECAST_READ_FAILED');
   const forecast=validateForecastRead(read.value,scope);
   const processBody={p_tenant_id:scope.tenantId,p_legal_entity_id:scope.entityId,p_branch_id:scope.branchId,p_window_start:calendar.windowStart,
    p_window_end:calendar.windowEnd,p_as_of:calendar.asOf,p_recorded_through:calendar.recordedThrough};
   const processResult=await send(handle,'/rest/v1/rpc/analytics_process_snapshot',{bearer:participant.token,profile:'api',body:processBody});must(processResult.ok,'REAL_PROCESS_READ_FAILED');
   const processProjection=validateSourceRead(processResult.value,scope);
   const value={scopeKey:scope.key,tenantId:scope.tenantId,actorId:participant.proof.actorId,commandId:command,forecast,process:processProjection,
    commandResponse:frozen.value,forecastResponse:read.value,processResponse:processResult.value,
    transport:[frozen.evidence,read.evidence,processResult.evidence],actualFinishedAt:new Date().toISOString()};
   await save(directory+scope.key+'-result.json',value);completed.push({scopeKey:scope.key,forecastId:forecast.id,sourceHash:forecast.sourceHash,commandId:command});
   if(scope.key==='runtime'){
    const replay=await send(handle,'/rest/v1/rpc/freeze_pipeline_forecast',{bearer:participant.token,profile:'api',body});
    must(replay.ok&&JSON.stringify(replay.value.entity)===JSON.stringify(frozen.value.entity),'REAL_ORIGINAL_COMMAND_REPLAY_FAILED');
    const denied=await send(sessions['foreign-member'].handle,'/rest/v1/rpc/analytics_process_snapshot',{bearer:sessions['foreign-member'].token,profile:'api',body:processBody});
    must(!denied.ok&&denied.value?.message==='PERMISSION_DENIED','REAL_FOREIGN_SOURCE_DENIAL_REQUIRED');
    const tooWide={...processBody,p_window_start:new Date(Date.parse(calendar.windowEnd)-367*86400000).toISOString()};
    const boundary=await send(handle,'/rest/v1/rpc/analytics_process_snapshot',{bearer:participant.token,profile:'api',body:tooWide});
    must(!boundary.ok&&boundary.value?.message==='LIMIT_EXCEEDED','REAL_367_DAY_BOUNDARY_DENIAL_REQUIRED');
    await save(directory+'runtime-replay-and-denials.json',{replay:{value:replay.value,transport:replay.evidence},foreignDenied:{value:denied.value,transport:denied.evidence},
     wideWindowDenied:{value:boundary.value,transport:boundary.evidence},expectedCodesVerified:true,ownerAcceptance:false});
   }
   if(completed.length%50===0)process.stdout.write(JSON.stringify({actualNonemptyScopesVerified:completed.length,forecastCommands:completed.length})+'\n');
  }}catch(error){halted=true;throw error;}finally{transport.closeConnection(handle);}};
  const workers=await Promise.allSettled([work(),work(),work(),work()]);
  const failed=workers.find(w=>w.status==='rejected');if(failed)throw failed.reason;
  must(completed.length===500,'ALL_APPROVED_SOURCE_SCOPES_REQUIRED');
  const result={kind:'actual-genuine-nonempty-process-pipeline-workflows',actualFinishedAt:new Date().toISOString(),projectId:PROJECT,bundleSha256:BUNDLE,
   passed:true,scopesVerified:500,actualForecastCommands:500,actualForecastReads:500,actualProcessReads:500,uniqueGenuineSessions:2,
   originalCommandReplay:true,foreignTenantDenied:true,wideWindowDenied:true,networkCalls:calls,completed,calendar,credentialsPrinted:false,
   newAuthAccounts:0,newMfaFactors:0,constructedJwtClaims:0,schedulesStarted:false,modelCalls:0,actualDelivery:false,
   authenticatedNative:false,independentSessionContention:false,targetScaleLoad:false,ownerAcceptedCriteria:3,production:false,realBilling:false};
  const evidence=await save(directory+'99-result.json',result);process.stdout.write(JSON.stringify({passed:true,scopesVerified:500,evidence})+'\n');
 }catch(error){await save(directory+'99-stop.json',{phase,actualStoppedAt:new Date().toISOString(),failureCode:error.publicCode??error.code??'GENUINE_SOURCE_WORKFLOW_FAILED',
  completed,networkCalls:calls,automaticRetryPerformed:false,credentialsPrinted:false});throw error;
 }finally{transport?.close();key.fill(0);config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'GENUINE_SOURCE_WORKFLOW_FAILED',rawErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;});
