import test from 'node:test';
import assert from 'node:assert/strict';
import { validateGenuineMfaResult, bindUuidSessionQuery } from './enroll_mfa_management_20261013_r5.mjs';
const actorId='11111111-1111-4111-8111-111111111111',sessionId='22222222-2222-4222-8222-222222222222',
 factorId='33333333-3333-4333-8333-333333333333';
const fixture=()=>({claims:{sub:actorId,aal:'aal2',session_id:sessionId},actor:{authId:actorId},factorId,
 onlineUser:{id:actorId,factors:[{id:factorId,status:'verified'}]},session:{id:sessionId,user_id:actorId,aal:'aal2',
  factor_id:factorId,factor_status:'verified',factor_type:'totp',read_only:'on',isolation:'repeatable read'}});
test('a token claim alone cannot establish genuine MFA',()=>{
 const good=fixture();assert.equal(validateGenuineMfaResult(good).aal,'aal2');
 for(const change of [{aal:'aal1'},{factor_status:'unverified'},{factor_type:'phone'},{read_only:'off'},
  {isolation:'read committed'},{id:'another-session'},{user_id:'another-actor'},{factor_id:'another-factor'}]){
  const value=fixture();Object.assign(value.session,change);
  assert.throws(()=>validateGenuineMfaResult(value),/GENUINE_SERVER_MFA_PROOF_REQUIRED/);
 }
});
test('online Auth and the committed session must agree on the exact newly verified factor',()=>{
 const missing=fixture();missing.onlineUser.factors=[];
 assert.throws(()=>validateGenuineMfaResult(missing),/GENUINE_SERVER_MFA_PROOF_REQUIRED/);
 const unrelated=fixture();unrelated.onlineUser.id='another-user';
 assert.throws(()=>validateGenuineMfaResult(unrelated),/GENUINE_SERVER_MFA_PROOF_REQUIRED/);
 const wrong=fixture();wrong.claims.session_id='another-session';
 assert.throws(()=>validateGenuineMfaResult(wrong),/GENUINE_SERVER_MFA_PROOF_REQUIRED/);
});
test('multi-statement session observation binds only validated non-secret UUIDs',()=>{
 const query=bindUuidSessionQuery(sessionId,actorId);
 assert.equal(query.includes('$1'),false);assert.equal(query.includes('$2'),false);
 assert.equal(query.includes(`s.id='${sessionId}'::uuid`),true);
 assert.throws(()=>bindUuidSessionQuery("'; DROP TABLE auth.users; --",actorId),/EXACT_REAL_SESSION_IDS_REQUIRED/);
});
