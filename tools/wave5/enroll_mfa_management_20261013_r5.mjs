import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT, BUNDLE, loadApprovedInputs, createManagementTransport } from './approved_management_installer.mjs';
import { hashBytes, isUuid } from './runtime_contract.mjs';
import { runtimeSealKey, appendRuntimeSecret, readRuntimeSecret } from './private_runtime_seal.mjs';
import { createPrivateKeyReader, selectExistingLegacyKeys } from './private_runtime_http.mjs';
import { createSupabaseHttpsTransport, decodeReceivedAccessToken, totpFromPrivateSecret } from './supabase_http_transport.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const provisioningPath=base+'auth-admin-provisioning-20261013-r5-1791877892653/99-result.json';
const provisioningSha='f8a67d9a2659bb4185d71c05c1a7644e5248e56c72fded4af297e3a2d3888abb';
const localSources={
 'tools/wave5/private_runtime_http.mjs':'d52ae919e4c13bd1745ef806658744dfc2c52df7b61d24d9f87afac06de7be2c',
 'tools/wave5/private_runtime_seal.mjs':'1395a91ee666d40c5504c8977b5d4f64aa4d54b383dfe147fe78eb07a5d7a206',
 'tools/wave5/supabase_http_transport.mjs':'7815b9c8c18bd5d2375480706579c7dd9583b1e95e0424a2178f7b9b5db265c9',
 'tools/wave5/runtime_contract.mjs':'2f518fdffa0f8b6e947118a259f10fbfb20b41e7fcc7e6ef3146461030f8747f'
};
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
const sessionSql=`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT s.id,s.user_id,s.aal::text,s.factor_id,s.not_after::text,s.created_at::text,
 f.status::text AS factor_status,f.factor_type::text AS factor_type,
 statement_timestamp()::text AS observed_at,current_setting('transaction_isolation') AS isolation,
 current_setting('transaction_read_only') AS read_only
FROM auth.sessions s LEFT JOIN auth.mfa_factors f ON f.id=s.factor_id AND f.user_id=s.user_id
WHERE s.id=$1::uuid AND s.user_id=$2::uuid;
ROLLBACK;`;
export function bindUuidSessionQuery(sessionId, actorId) {
 must(isUuid(sessionId)&&isUuid(actorId),'EXACT_REAL_SESSION_IDS_REQUIRED');
 return sessionSql.replace('$1',`'${sessionId}'`).replace('$2',`'${actorId}'`);
}
export function validateGenuineMfaResult({claims,onlineUser,session,actor,factorId}) {
 must(claims?.sub===actor.authId && claims.aal==='aal2' && isUuid(claims.session_id)
  && onlineUser?.id===actor.authId && onlineUser.factors?.some(f=>f.id===factorId&&f.status==='verified')
  && session?.id===claims.session_id && session.user_id===actor.authId && session.aal==='aal2'
  && session.factor_id===factorId && session.factor_status==='verified' && session.factor_type==='totp'
  && session.read_only==='on' && session.isolation==='repeatable read','GENUINE_SERVER_MFA_PROOF_REQUIRED');
 return {actorId:actor.authId,factorId,sessionId:claims.session_id,aal:'aal2',factorStatus:'verified',
  serverObservedAt:session.observed_at,onlineAuthVerified:true,serverSessionRowVerified:true,constructedAalClaims:false};
}
async function save(file,value){const text=JSON.stringify(value,null,2)+'\n',handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(text);await handle.sync();}finally{await handle.close();}return {path:file,sha256:hashBytes(text)};}
async function prepare(){const inputs=await loadApprovedInputs();
 for(const [file,sha]of Object.entries({...localSources,[provisioningPath]:provisioningSha}))
  must(hashBytes(await fs.readFile(path.join(root,file)))===sha,'EXACT_MFA_SOURCE_BINDING_REQUIRED');
 const provisioning=JSON.parse(await fs.readFile(path.join(root,provisioningPath),'utf8'));
 must(provisioning.passed===true&&provisioning.accountsCreated===6&&provisioning.genuineAdminCreates===true
  && provisioning.constructedAuthRows===0&&provisioning.accounts.every(a=>inputs.review.accounts.some(b=>b.label===a.label&&b.email===a.email)),
 'GENUINE_SIX_CREATED_ACCOUNTS_REQUIRED');return {inputs,provisioning};}

async function main(){const mode=process.argv[2]??'--validate';
 must(process.argv.length<=3&&['--validate','--enroll'].includes(mode),'EXACT_MFA_MODE_REQUIRED');
 const prepared=await prepare();if(mode==='--validate'){process.stdout.write(JSON.stringify({kind:'genuine-mfa-preparation',passed:true,
  exactCreatedAccounts:6,realTotpEnrollmentChallengeAndVerificationRequired:true,networkCalls:0,authWrites:0})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_INPUT_TOO_LONG');}
 const config=JSON.parse(incoming);incoming='';must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE,'EXACT_PRIVATE_RUNTIME_INPUT_REQUIRED');
 const key=runtimeSealKey(config.encryptionKey),management=createManagementTransport(config.ownerToken);
 const evidenceDirectory=base+'genuine-mfa-20261013-r5-'+Date.now()+'/';await fs.mkdir(path.join(root,evidenceDirectory));
 const publicSave=(file,value)=>save(evidenceDirectory+file,value);let phase='once-only-intent',networkCalls=0,authMutatingCalls=0,transport;
 const verifiedActors=[];
 try{
  await save(base+'genuine-mfa-once-20261013-r5.json',{kind:'genuine-mfa-once-only-intent',projectId:PROJECT,bundleSha256:BUNDLE,
   actualStartedAt:new Date().toISOString(),evidenceDirectory,accountProvisioning:{path:provisioningPath,sha256:provisioningSha},
   existingUsersOrFactorsMustNotBeChanged:true,automaticRetryForbidden:true});
  phase='private-existing-key-read';networkCalls++;
  const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value);
  transport=createSupabaseHttpsTransport({projectId:PROJECT,apiKey:keys.anon});
  for(const actor of prepared.provisioning.accounts){
   phase='private-created-account-binding';const privateActor=await readRuntimeSecret(config.privateDirectory,key,actor.privateRecord,'account-created');
   must(privateActor.authId===actor.authId&&privateActor.email===actor.email&&privateActor.label===actor.label
    && privateActor.status==='returned-by-auth-admin','EXACT_PRIVATE_CREATED_ACTOR_REQUIRED');
   const handle=transport.connection();
   const send=async(route,options)=>{networkCalls++;if(options?.method!=='GET')authMutatingCalls++;
    const result=await transport.send(handle,route,options);must(result.ok,'GENUINE_MFA_HTTP_NOT_SUCCESS');return result;};
   phase='genuine-password-sign-in';
   const signed=await send('/auth/v1/token?grant_type=password',{body:{email:actor.email,password:privateActor.password}});
   const initialClaims=decodeReceivedAccessToken(signed.value.access_token);
   must(signed.value.user?.id===actor.authId&&initialClaims.sub===actor.authId&&initialClaims.aal==='aal1','GENUINE_INITIAL_SIGNIN_REQUIRED');
   const beforeUser=await send('/auth/v1/user',{method:'GET',bearer:signed.value.access_token});
   must(beforeUser.value.id===actor.authId&&!(beforeUser.value.factors?.length>0),'NEW_ACTOR_FACTOR_COLLISION');
   const initialSessionRecord=await appendRuntimeSecret(config.privateDirectory,key,'session-initial',
    {label:actor.label,authId:actor.authId,accessToken:signed.value.access_token,refreshToken:signed.value.refresh_token,
     sessionId:initialClaims.session_id,status:'genuine-aal1-before-enrollment'});
   await publicSave(actor.label+'-signin.json',{label:actor.label,authId:actor.authId,sessionId:initialClaims.session_id,
    aal:'aal1',onlineAuthVerified:true,initialSessionRecord,responseSha256:signed.responseSha256});
   phase='genuine-totp-enrollment';
   await publicSave(actor.label+'-enroll-intent.json',{label:actor.label,authId:actor.authId,
    actualIntentAt:new Date().toISOString(),newFactorOnly:true,factorType:'totp'});
   const enrolled=await send('/auth/v1/factors',{bearer:signed.value.access_token,
    body:{factor_type:'totp',friendly_name:'Jentra bounded runtime',issuer:'Jentra OS'}});
   must(isUuid(enrolled.value?.id)&&typeof enrolled.value.totp?.secret==='string','GENUINE_ENROLLED_FACTOR_REQUIRED');
   const factorId=enrolled.value.id,secret=enrolled.value.totp.secret;
   phase='durable-private-factor-before-challenge';
   const enrolledPrivateRecord=await appendRuntimeSecret(config.privateDirectory,key,'factor-enrolled',
    {label:actor.label,authId:actor.authId,factorId,secret,status:'genuine-server-enrolled-unverified',
     initialSessionRecord,enrollResponseSha256:enrolled.responseSha256});
   await publicSave(actor.label+'-enrolled.json',{label:actor.label,authId:actor.authId,factorId,enrolledPrivateRecord,
    status:'unverified',responseSha256:enrolled.responseSha256});
   phase='genuine-factor-challenge';
   const challenged=await send(`/auth/v1/factors/${factorId}/challenge`,{bearer:signed.value.access_token,body:{}});
   must(isUuid(challenged.value?.id),'GENUINE_FACTOR_CHALLENGE_REQUIRED');
   // Align the private authenticator to a fresh server clock observation. The
   // client and server clocks are recorded separately; no OS clock is changed.
   networkCalls++;
   const serverClock=await management('POST','/database/query',{
    query:'SELECT statement_timestamp()::text AS observed_at',read_only:true});
   const serverTime=Date.parse(serverClock.value?.[0]?.observed_at);
   must(Number.isFinite(serverTime),'REAL_TOTP_SERVER_CLOCK_REQUIRED');
   const clockReceivedAt=Date.now();
   phase='genuine-factor-verification';
   const code=totpFromPrivateSecret(secret,serverTime+(Date.now()-clockReceivedAt));
   const verified=await send(`/auth/v1/factors/${factorId}/verify`,{bearer:signed.value.access_token,
    body:{challenge_id:challenged.value.id,code}});
   const claims=decodeReceivedAccessToken(verified.value.access_token);
   phase='online-user-and-server-session-proof';
   const online=await send('/auth/v1/user',{method:'GET',bearer:verified.value.access_token});networkCalls++;
   const actualSessionQuery=bindUuidSessionQuery(claims.session_id,actor.authId);
   const rowProof=await management('POST','/database/query',{query:actualSessionQuery,read_only:true});
   must(rowProof.value?.length===1,'ONE_REAL_SESSION_ROW_REQUIRED');
   const proof=validateGenuineMfaResult({claims,onlineUser:online.value,session:rowProof.value[0],actor,factorId});
   phase='private-verified-factor-and-session-persistence';
   const factorPrivateRecord=await appendRuntimeSecret(config.privateDirectory,key,'factor-verified',
    {label:actor.label,authId:actor.authId,factorId,secret,status:'genuine-server-verified',rowProofSha256:rowProof.responseSha256});
   const sessionPrivateRecord=await appendRuntimeSecret(config.privateDirectory,key,'session-verified',
    {label:actor.label,authId:actor.authId,factorId,sessionId:claims.session_id,aal:'aal2',accessToken:verified.value.access_token,
     refreshToken:verified.value.refresh_token,expiresAt:new Date(claims.exp*1000).toISOString()});
   const publicProof={...proof,label:actor.label,factorPrivateRecord,sessionPrivateRecord,actualFinishedAt:new Date().toISOString(),
    realEnrollmentResponseSha256:enrolled.responseSha256,realChallengeResponseSha256:challenged.responseSha256,
    realVerifyResponseSha256:verified.responseSha256,onlineUserResponseSha256:online.responseSha256,
    sessionRowResponseSha256:rowProof.responseSha256,sessionQuerySha256:hashBytes(actualSessionQuery),sessionQueryTemplateSha256:hashBytes(sessionSql)};
   verifiedActors.push(publicProof);await publicSave(actor.label+'-verified.json',publicProof);
   process.stdout.write(JSON.stringify({genuineMfaVerified:true,label:actor.label,authId:actor.authId,factorId,aal:'aal2'})+'\n');
   transport.closeConnection(handle);
  }
  phase='private-mfa-index';const privateIndex=await appendRuntimeSecret(config.privateDirectory,key,'mfa-index',
   {projectId:PROJECT,bundleSha256:BUNDLE,verifiedAt:new Date().toISOString(),actors:verifiedActors});
  const result={kind:'actual-genuine-auth-totp-mfa-verification',actualFinishedAt:new Date().toISOString(),projectId:PROJECT,
   bundleSha256:BUNDLE,passed:true,genuineMfaVerifiedActors:verifiedActors.length,actors:verifiedActors,privateIndex,
   realAuthPasswordSignIns:6,realTotpEnrollments:6,realTotpChallenges:6,realTotpVerifications:6,networkCalls,authMutatingCalls,
   constructedAuthRows:0,constructedJwtOrAalClaims:0,factorSeedsOrCodesOrTokensPrinted:false,existingAccountMutations:0,
   accountProvisioning:{path:provisioningPath,sha256:provisioningSha},databaseBehaviorTested:false,authenticatedNative:false,
   independentSessionContention:false,targetScaleLoad:false,actualDelivery:false,actualModelUsage:false,ownerAcceptedCriteria:3,
   production:false,realBilling:false,limitation:'Real Auth API enrollment, verification, online user and server session/factor evidence. This is not authenticated native or load acceptance.'};
  const evidence=await publicSave('99-result.json',result);
  process.stdout.write(JSON.stringify({passed:true,genuineMfaVerifiedActors:verifiedActors.length,credentialsStoredPrivately:true,evidence})+'\n');
 }catch(error){await publicSave('99-stop.json',{phase,failureCode:error.publicCode??error.code??'GENUINE_MFA_FAILED',
  actualFailedAt:new Date().toISOString(),networkCalls,authMutatingCalls,verifiedActors,automaticRetryPerformed:false,
  factorSeedsOrCodesOrTokensPrinted:false,existingAccountMutations:0});throw error;
 }finally{transport?.close();key.fill(0);config.ownerToken='';config.encryptionKey='';}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'GENUINE_MFA_FAILED',rawErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;
});
