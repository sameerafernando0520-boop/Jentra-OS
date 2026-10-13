import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { bindExactBootstrap, validateBootstrapPreservation, validateBootstrapResponse } from './bootstrap_management_20261013_r5.mjs';
const source=await fs.readFile('docs/verification/wave5/runtime-bootstrap-complete-app-20261009.sql','utf8');
const auth=JSON.parse(await fs.readFile('docs/verification/wave5/auth-admin-provisioning-20261013-r5-1791877892653/99-result.json','utf8'));
const ids=Object.fromEntries(auth.accounts.map(a=>[a.label,a.authId]));
test('bootstrap rejects changed source, duplicate identities and unreviewed modes',()=>{
 assert.throws(()=>bindExactBootstrap(source+'-- changed',ids,'persist'),/EXACT_BOOTSTRAP_SOURCE_REQUIRED/);
 assert.throws(()=>bindExactBootstrap(source,ids,'free-sql'),/EXACT_BOOTSTRAP_SOURCE_REQUIRED/);
 assert.throws(()=>bindExactBootstrap(source,{...ids,approver:ids.proposer},'persist'),/EXACT_RETURNED_SIX_AUTH_IDS_REQUIRED/);
 const malformed={...ids,proposer:"'; DELETE FROM auth.users; --"};
 assert.throws(()=>bindExactBootstrap(source,malformed,'persist'),/EXACT_RETURNED_SIX_AUTH_IDS_REQUIRED/);
 const rollback=bindExactBootstrap(source,ids,'rollback');
 assert.match(rollback,/rollback;\s*$/);assert.equal(/^commit;/mi.test(rollback),false);
 assert.equal(/request.jwt.claims|insert\s+into\s+auth\./i.test(rollback),false);
});
test('a successful HTTP status cannot replace the actual strict bootstrap result',()=>{
 const proof={bootstrap_verified:{passed:true,strictStructuralAssertions:12}};
 const counts={reviewed_counts:{tenants:500,accounts:6,memberships:1997,roles:1003,assignments:2003}};
 assert.equal(validateBootstrapResponse([proof]).strictStructuralAssertions,12);
 assert.equal(validateBootstrapResponse([counts,proof]).passed,true);
 assert.throws(()=>validateBootstrapResponse([counts]),/STRICT_REAL_AUTH_BOOTSTRAP_PROBE_REQUIRED/);
 assert.throws(()=>validateBootstrapResponse([{bootstrap_verified:{passed:false,strictStructuralAssertions:12}}]));
 assert.throws(()=>validateBootstrapResponse([{reviewed_counts:{...counts.reviewed_counts,memberships:1998}},proof]));
});
test('rollback must leave no scoped rows, and commit must preserve all outside-scope hashes',()=>{
 const before={migrationCount:114,existingDesktopAccountPreserved:true,existingAccessFingerprints:{memberships:'unchanged'},
  scopedCounts:{tenants:0,entities:0,branches:0,memberships:0,roles:0,assignments:0,subscriptions:0,plans:0}};
 assert.equal(validateBootstrapPreservation(before,structuredClone(before),false),true);
 const leftover=structuredClone(before);leftover.scopedCounts.tenants=1;
 assert.throws(()=>validateBootstrapPreservation(before,leftover,false),/EXACT_BOOTSTRAP_AFTER_COUNTS_REQUIRED/);
 const after=structuredClone(before);after.scopedCounts={tenants:500,entities:500,branches:501,memberships:1997,roles:1003,assignments:2003,subscriptions:500,plans:4};
 assert.equal(validateBootstrapPreservation(before,after,true),true);
 after.existingAccessFingerprints.memberships='changed';
 assert.throws(()=>validateBootstrapPreservation(before,after,true),/BOOTSTRAP_EXISTING_ACCESS_CHANGED/);
});
