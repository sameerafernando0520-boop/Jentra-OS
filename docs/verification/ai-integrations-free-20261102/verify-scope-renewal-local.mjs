// In-memory PostgreSQL proof only. No hosted connection, Auth session or I/O.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {PGlite} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js';
const candidate=await readFile(new URL('runtime-scope-renewal-30m-candidate.sql',import.meta.url),'utf8');
const trial=await readFile(new URL('runtime-scope-renewal-30m-rollback.sql',import.meta.url),'utf8');
const migration=await readFile(new URL('../../../supabase/migrations/20261008123000_wave5_runtime_scope.sql',import.meta.url),'utf8');
const definition=migration.slice(migration.indexOf('create function intelligence_control.runtime_scope_allowed('),
 migration.indexOf('create function intelligence_control.runtime_tenant_allowed('));
assert.ok(definition.startsWith('create function intelligence_control.runtime_scope_allowed('));
const db=new PGlite(),checks=[];
const runtime='778237e3-3d4e-4871-8cc9-e08b07b989c7',tenant='babe6c86-a764-4d3a-80a3-952a7c096c2c',
 entity='caa2bb06-219a-47e9-8132-66d1271b0ffd',branch='3813692c-f0de-4c69-8e34-d56cf54695b1';
const baseline=async()=>db.exec(`
 truncate intelligence_control.runtime_worker_scopes,intelligence_control.edge_authorities,intelligence_control.synthetic_tenants,core.branches;
 insert into core.branches values('${tenant}','${entity}','${branch}','active');
 insert into intelligence_control.runtime_worker_scopes values('${runtime}','${tenant}','${entity}','${branch}',true,
  '2026-10-13T08:13:04.144135Z','2026-10-14T08:13:04.144135Z');
 insert into intelligence_control.edge_authorities values('${runtime}',true,'2026-10-13T09:57:07.481942Z','2026-10-14T09:57:07.481942Z');
 insert into intelligence_control.synthetic_tenants values('${tenant}',true);
`);
const state=async()=>JSON.stringify((await db.query(`select to_jsonb(s) scope,to_jsonb(a) authority
 from intelligence_control.runtime_worker_scopes s cross join intelligence_control.edge_authorities a`)).rows);
try{
 await db.exec(`create schema core;create schema intelligence_control;
  create table core.branches(tenant_id uuid,legal_entity_id uuid,id uuid,status text);
  create table intelligence_control.runtime_worker_scopes(runtime_id uuid,tenant_id uuid,legal_entity_id uuid,branch_id uuid,
   enabled boolean,issued_at timestamptz,expires_at timestamptz,primary key(runtime_id,tenant_id,legal_entity_id,branch_id),
   check(isfinite(expires_at) and expires_at>issued_at and expires_at<=issued_at+interval '7 days'));
  create table intelligence_control.edge_authorities(runtime_id uuid primary key,enabled boolean,issued_at timestamptz,expires_at timestamptz);
  create table intelligence_control.synthetic_tenants(tenant_id uuid primary key,allowed boolean);`);
 await db.exec(definition);
 await baseline();const before=await state();
 const outcomes=await db.exec(trial),proof=outcomes.find(value=>value.rows?.[0]?.runtime_scope_renewal_trial)?.rows[0].runtime_scope_renewal_trial;
 assert.ok(proof&&['rollbackOnly','privateTargetAllowAssertionPassed','otherBranchDenyAssertionPassed','baselineRestored','targetStillInactive','scheduleAuthorityStillInactive'].every(key=>proof[key]===true));
 assert.equal(await state(),before);checks.push('rollback proof restores the exact scope and edge-authority preimage');
 await baseline();const edgeBefore=JSON.stringify((await db.query('select * from intelligence_control.edge_authorities')).rows);
 await db.exec(candidate);
 const window=(await db.query(`select intelligence_control.runtime_scope_allowed('${runtime}','${tenant}','${entity}','${branch}') allowed,
  extract(epoch from expires_at-issued_at)::integer seconds from intelligence_control.runtime_worker_scopes`)).rows[0];
 assert.equal(window.allowed,true);assert.equal(window.seconds,1800);
 assert.equal(JSON.stringify((await db.query('select * from intelligence_control.edge_authorities')).rows),edgeBefore);
 checks.push('isolated commit grants exactly 30 minutes without renewing schedule authority');
 await baseline();await db.exec("update intelligence_control.runtime_worker_scopes set expires_at=expires_at+interval '1 second'");
 const drifted=await state();await assert.rejects(db.exec(candidate),/EXPIRED_SCOPE_PREIMAGE_CHANGED/);await db.exec('rollback;');assert.equal(await state(),drifted);
 checks.push('concurrent preimage change is rejected without overwrite');
 await baseline();await db.exec('update intelligence_control.synthetic_tenants set allowed=false');
 const disallowed=await state();await assert.rejects(db.exec(candidate),/SYNTHETIC_TENANT_NOT_APPROVED/);await db.exec('rollback;');assert.equal(await state(),disallowed);
 checks.push('unapproved synthetic tenant receives no renewed access');
 await baseline();await db.exec("update core.branches set status='inactive'");
 const inactive=await state();await assert.rejects(db.exec(candidate),/TARGET_SCOPE_NOT_ALLOWED/);await db.exec('rollback;');assert.equal(await state(),inactive);
 checks.push('inactive branch rolls back the attempted scope update');
 const report={kind:'jentra-runtime-scope-renewal-isolated-proof',recordedAt:new Date().toISOString(),passed:checks.length,checks,
  candidateSha256:createHash('sha256').update(candidate).digest('hex'),trialSha256:createHash('sha256').update(trial).digest('hex'),
  hostedDatabaseQueried:false,hostedPermissionRenewed:false,authSessionFabricated:false,
  boundary:'In-memory PGlite tables and the repository scope predicate only. Actual hosted allow/deny proof and explicit owner approval are still required.'};
 await writeFile(new URL('runtime-scope-renewal-local-result.json',import.meta.url),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({passed:checks.length,hostedDatabaseQueried:false,hostedPermissionRenewed:false}));
}finally{await db.close();}
