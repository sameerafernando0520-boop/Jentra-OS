import fs from 'node:fs/promises';
import { PROJECT } from './approved_management_installer.mjs';
import { hashBytes,isUuid } from './runtime_contract.mjs';
import { readRuntimeSecret,appendRuntimeSecret } from './private_runtime_seal.mjs';
import { decodeReceivedAccessToken,totpFromPrivateSecret } from './supabase_http_transport.mjs';
import { bindUuidSessionQuery,validateGenuineMfaResult } from './enroll_mfa_management_20261013_r5.mjs';

const actualAuth='docs/verification/wave5/auth-admin-provisioning-20261013-r5-1791877892653/99-result.json';
const actualMfa='docs/verification/wave5/genuine-mfa-20261013-r5-1791878507585/99-result.json';
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};

// Existing approved users and factors only. Import performs no I/O. Tokens and
// TOTP seeds stay private; callers receive a closure and a public server proof.
export async function existingActorSession({root,config,key,label,transport,management,save,file,kind='phase-session'}) {
  const authBytes=await fs.readFile(new URL('../../'+actualAuth,import.meta.url));
  const mfaBytes=await fs.readFile(new URL('../../'+actualMfa,import.meta.url));
  must(hashBytes(authBytes)==='f8a67d9a2659bb4185d71c05c1a7644e5248e56c72fded4af297e3a2d3888abb'
    &&hashBytes(mfaBytes)==='af4e9dec3987f5d6ba8c49fc1162be1374f93a14c043e46065119297a73e0bba','ACTUAL_AUTH_MFA_BINDINGS_REQUIRED');
  const actor=JSON.parse(authBytes).accounts.find(a=>a.label===label), prior=JSON.parse(mfaBytes).actors.find(a=>a.label===label);
  must(actor&&prior&&config.projectId===PROJECT,'EXACT_APPROVED_ACTOR_REQUIRED');
  const credential=await readRuntimeSecret(config.privateDirectory,key,actor.privateRecord,'account-created');
  const factor=await readRuntimeSecret(config.privateDirectory,key,prior.factorPrivateRecord,'factor-verified');
  must(credential.authId===actor.authId&&credential.email===actor.email&&factor.authId===actor.authId
    &&factor.factorId===prior.factorId,'EXACT_APPROVED_ACTOR_FACTOR_REQUIRED');
  const handle=transport.connection();
  const signed=await transport.send(handle,'/auth/v1/token?grant_type=password',{body:{email:actor.email,password:credential.password}});
  credential.password=null;must(signed.ok&&signed.value?.user?.id===actor.authId,'ACTUAL_EXISTING_ACTOR_SIGNIN_REQUIRED');
  const challenge=await transport.send(handle,`/auth/v1/factors/${factor.factorId}/challenge`,{bearer:signed.value.access_token,body:{}});
  must(challenge.ok&&isUuid(challenge.value?.id),'ACTUAL_EXISTING_FACTOR_CHALLENGE_REQUIRED');
  const clock=await management('POST','/database/query',{query:'SELECT statement_timestamp()::text AS observed_at',read_only:true});
  const serverNow=Date.parse(clock.value[0]?.observed_at);must(Number.isFinite(serverNow),'ACTUAL_SERVER_CLOCK_REQUIRED');
  const verified=await transport.send(handle,`/auth/v1/factors/${factor.factorId}/verify`,{bearer:signed.value.access_token,
    body:{challenge_id:challenge.value.id,code:totpFromPrivateSecret(factor.secret,serverNow)}});
  factor.secret=null; signed.value.access_token=null;signed.value.refresh_token=null;
  must(verified.ok,'ACTUAL_EXISTING_FACTOR_VERIFICATION_REQUIRED');
  const claims=decodeReceivedAccessToken(verified.value.access_token);
  const online=await transport.send(handle,'/auth/v1/user',{method:'GET',bearer:verified.value.access_token});
  must(online.ok,'ACTUAL_ONLINE_USER_REQUIRED');
  const session=await management('POST','/database/query',{query:bindUuidSessionQuery(claims.session_id,actor.authId),read_only:true});
  const proof=validateGenuineMfaResult({claims,onlineUser:online.value,session:session.value[0],actor,factorId:factor.factorId});
  const privateRecord=await appendRuntimeSecret(config.privateDirectory,key,kind,{label,authId:actor.authId,
    sessionId:claims.session_id,accessToken:verified.value.access_token,refreshToken:verified.value.refresh_token,
    expiresAt:new Date(claims.exp*1000).toISOString()});
  await save(file,{...proof,label,privateRecord,actualAuthTransport:[signed.evidence,challenge.evidence,verified.evidence,online.evidence],
    existingUser:true,existingFactor:true,newUserOrFactorCreated:false});
  const token=verified.value.access_token; verified.value.access_token=null;verified.value.refresh_token=null;
  return Object.freeze({proof,privateRecord,request(route,body,connection=handle){
    must(Date.now()<claims.exp*1000-15000,'FRESH_ACTUAL_ACTOR_SESSION_REQUIRED');
    return transport.send(connection,route,{bearer:token,profile:'api',body});
  }});
}
