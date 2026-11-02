// Actual foundation/candidate SQL in an isolated PostgreSQL engine. No network.
// npm install --prefix build/launch-validation-runtime --ignore-scripts --no-audit
//   --no-fund --save-exact @electric-sql/pglite@0.5.12
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {PGlite} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js';
import {pgcrypto} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
import {btree_gist} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/btree_gist.js';

const db=new PGlite({extensions:{pgcrypto,btree_gist}}),checks=[],sources={};
const owner=randomUUID(),staff=randomUUID(),invitee=randomUUID(),foreign=randomUUID(),limited=randomUUID(),legacy=randomUUID();
const check=(name,test)=>{assert.ok(test,name);checks.push(name);};
const one=async(sql,params=[])=>(await db.query(sql,params)).rows[0];
const scalar=async(sql,params=[])=>Object.values(await one(sql,params))[0];
const claims=async(id,{aal='aal2',age=0,email}={})=>{
 await db.exec('reset role');
 const canonical=email??await scalar('select email from auth.users where id=$1',[id]);
 await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:id,email:canonical,aal,
  amr:[{method:'totp',timestamp:Math.floor(Date.now()/1000)-age}]})]);
 await db.exec('set local role authenticated');
};
const denied=async(name,code,work)=>{
 await db.exec('savepoint rejection');let caught;
 try{await work();}catch(error){caught=error;}
 await db.exec('rollback to savepoint rejection;release savepoint rejection');
 assert.equal(caught?.code,code,`${name}: ${caught?.message??'no rejection'}`);checks.push(name);
};
const command=async(t,action,payload,version=null,key=randomUUID(),id=randomUUID(),at=new Date().toISOString())=>
 scalar('select api.workspace_admin_command($1,$2,$3,$4,$5,$6,$7)',[t,id,key,at,action,payload,version]);
try{
 await db.exec(`begin;create role anon;create role authenticated;create role service_role bypassrls;create role authenticator;
 create schema extensions;create schema auth;
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}');
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 grant usage on schema auth to anon,authenticated,service_role;`);
 for(const path of ['supabase/migrations/20260831193714_create_greenfield_foundation.sql',
  'supabase/migrations/20260831193857_harden_foundation_rls_and_indexes.sql',
  'supabase/migrations/20260901090317_create_wave2_shared_foundation_schema.sql',
  'supabase/migrations/20260901090331_create_wave2_command_helpers.sql']){
  const sql=await readFile(new URL('../../../'+path,import.meta.url),'utf8');sources[path]=createHash('sha256').update(sql).digest('hex');
  // Execute the exact Wave 2 business schema prefix; storage providers require
  // Supabase and are outside this administration fixture.
  await db.exec(path.endsWith('create_wave2_shared_foundation_schema.sql')
   ? sql.slice(0,sql.indexOf('insert into storage.buckets')) : sql);
 }
 for(const [id,email] of [[owner,'owner@company.invalid'],[staff,'staff@company.invalid'],[invitee,'invitee@company.invalid'],[foreign,'foreign@company.invalid'],[limited,'limited@company.invalid'],[legacy,'legacy@company.invalid']])
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,email]);
 await claims(owner);
 const bootstrap=await scalar(`select api.bootstrap_tenant('Pilot Group','pilot-group','Pilot Company','PC','Main Branch','HQ',
  'Asia/Colombo','LKR',$1)`,[randomUUID()]);
 const t=bootstrap.tenant_id,e=bootstrap.legal_entity_id,b=bootstrap.branch_id;
 assert.ok(t&&e&&b,JSON.stringify(bootstrap));
 await claims(foreign);
 const other=await scalar(`select api.bootstrap_tenant('Other Group','other-group','Other Company','OC','Other Branch','OB',
  'Asia/Colombo','LKR',$1)`,[randomUUID()]);
 await db.exec('reset role');
 const before=await db.query(`select p.oid,p.proacl::text,pg_get_functiondef(p.oid) definition from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname in('api','core') and p.prokind='f' order by p.oid`);
 const candidate='supabase/candidates/20261028130000_company_access_administration.sql';
 const sql=await readFile(new URL('../../../'+candidate,import.meta.url),'utf8');sources[candidate]=createHash('sha256').update(sql).digest('hex');
 await db.exec(sql);
 const after=await db.query(`select p.oid,p.proacl::text,pg_get_functiondef(p.oid) definition from pg_proc p
  where p.oid=any($1::oid[]) order by p.oid`,[before.rows.map(x=>x.oid)]);
 assert.deepEqual(after.rows,before.rows);checks.push('candidate preserves every original API/core definition and execution grant');
 await claims(owner);
 await denied('anonymous has no API execution authority','42501',async()=>{
  await db.exec('reset role;set local role anon');await scalar("select api.workspace_admin_list($1,'entities')",[t]);});
 await denied('foreign tenant owner cannot read this group','42501',async()=>{await claims(foreign);await scalar("select api.workspace_admin_list($1,'entities')",[t]);});
 await denied('AAL1 is refused for administration','42501',async()=>{await claims(owner,{aal:'aal1'});await scalar("select api.workspace_admin_list($1,'entities')",[t]);});
 const list=await scalar("select api.workspace_admin_list($1,'entities')",[t]);
 check('MFA owner lists only the selected tenant company',list.items.length===1&&list.items[0].id===e);
 const permissionsPage=await scalar("select api.workspace_admin_list($1,'permissions',null,200)",[t]);
 const permissionIds=permissionsPage.items.map(row=>row.id);
 check('permission cursor order uses the same ordinal comparison as the client',JSON.stringify(permissionIds)===JSON.stringify([...permissionIds].sort()));
 await denied('recent MFA required','42501',async()=>{await claims(owner,{age:1000});await scalar("select api.workspace_admin_list($1,'entities')",[t]);});
 await claims(owner);
 await denied('future MFA timestamps are refused','42501',async()=>{await claims(owner,{age:-3600});await scalar("select api.workspace_admin_list($1,'entities')",[t]);});
 await denied('null resource is rejected','22023',()=>scalar('select api.workspace_admin_list($1,null)',[t]));
 await denied('oversized page is rejected','22023',()=>scalar("select api.workspace_admin_list($1,'members',null,201)",[t]));
 await denied('private helpers are not callable by authenticated clients','42501',()=>scalar("select workspace_admin.require_seat($1,$2)",[t,owner]));
 await denied('starter company limit enforced','23514',()=>command(t,'create_entity',{name:'Second Company',code:'SC',currency_code:'LKR',timezone:'Asia/Colombo'}));
 await db.exec('reset role');await db.query("update billing.tenant_subscriptions set plan_code='growth' where tenant_id=$1",[t]);await claims(owner);
 const secondPayload={name:'Second Company',code:'SC',currency_code:'LKR',timezone:'Asia/Colombo'},secondKey=randomUUID(),secondCommand=randomUUID(),secondTime=new Date().toISOString();
 const second=await command(t,'create_entity',secondPayload,null,secondKey,secondCommand,secondTime);
 check('company created with the existing core version authority',second.entity.version===1&&second.entity.tenant_id===t);
 assert.deepEqual(await command(t,'create_entity',secondPayload,null,secondKey,secondCommand,secondTime),second);checks.push('exact command replay returns the original confirmation');
 check('replay creates only one company',(await scalar("select api.workspace_admin_list($1,'entities')",[t])).items.length===2);
 await denied('fractional company limits are never rounded upward','23514',async()=>{await db.exec('reset role');await db.exec("update billing.plan_entitlements set numeric_limit=2.5 where plan_code='growth' and entitlement_code='legal_entities'");await claims(owner);await command(t,'create_entity',{...secondPayload,code:'TH',name:'Third company'});});
 await denied('changed payload cannot reuse an idempotency key','22023',()=>command(t,'create_entity',{...secondPayload,name:'Different Company'},null,secondKey,secondCommand,secondTime));
 await denied('changed command identity cannot reuse an idempotency key','22023',()=>command(t,'create_entity',secondPayload,null,secondKey,randomUUID(),secondTime));
 await denied('unknown currency is refused','22023',()=>command(t,'create_entity',{...secondPayload,code:'XX',currency_code:'ZZZ'}));
 await denied('invalid timezone is refused','22023',()=>command(t,'create_entity',{...secondPayload,code:'XX',timezone:'Invalid/Timezone'}));
 await denied('unexpected privileged fields are refused','22023',()=>command(t,'create_entity',{...secondPayload,code:'XX',service_role:true}));
 await denied('duplicate company code is atomic','23505',()=>command(t,'create_entity',secondPayload));
 await denied('company currency cannot be changed through an edit','22023',()=>command(t,'update_entity',{id:second.entity.id,name:'Changed',currency_code:'USD'},1));
 await denied('stale company edits are refused','40001',()=>command(t,'update_entity',{id:second.entity.id,name:'Stale edit'},2));
 const companyEdit=await command(t,'update_entity',{id:second.entity.id,name:'Second Company Renamed',registration_number:'SYNTHETIC-REG'},1);
 check('company edits confirm the exact version',companyEdit.entity.version===2);
 const nameEdit=await command(t,'update_entity',{id:second.entity.id,name:'Second Company Final'},2);
 check('omitting a registered detail preserves its prior value',nameEdit.entity.registration_number==='SYNTHETIC-REG');
 await denied('foreign company cannot receive a branch','22023',()=>command(t,'create_branch',{name:'Foreign branch',code:'FB',legal_entity_id:other.legal_entity_id,timezone:'Asia/Colombo'}));
 const branch=await command(t,'create_branch',{name:'Second Office',code:'SO',legal_entity_id:second.entity.id,timezone:'Asia/Colombo'});
 check('branch binds the requested company',branch.entity.legal_entity_id===second.entity.id);
 const edited=await command(t,'update_branch',{id:branch.entity.id,name:'Second Office Updated'},1);
 check('branch edit advances one optimistic version',edited.entity.version===2);
 const role=await command(t,'create_role',{name:'Sales reader',code:'sales_reader',permissions:['sales.view'],requires_mfa:false});
 check('custom role contains only the requested permission',JSON.stringify(role.entity.permissions)==='["sales.view"]');
 await denied('privileged custom role requires MFA','22023',()=>command(t,'create_role',{name:'Unsafe role',code:'unsafe',permissions:['finance.view'],requires_mfa:false}));
 const managerRole=await command(t,'create_role',{name:'Limited administrator',code:'limited_admin',permissions:['core.roles.manage'],requires_mfa:true});
 await db.exec('reset role');
 const m=await scalar('insert into core.memberships(tenant_id,user_id,status) values($1,$2,\'active\') returning id',[t,staff]);
 const lm=await scalar('insert into core.memberships(tenant_id,user_id,status) values($1,$2,\'active\') returning id',[t,limited]);
 const managerAssignment=await scalar('insert into core.role_assignments(tenant_id,membership_id,role_id,created_by) values($1,$2,$3,$4) returning id',[t,lm,managerRole.entity.id,owner]);
 const ownerMember=await scalar('select id from core.memberships where tenant_id=$1 and user_id=$2',[t,owner]);
 const ownerRole=await scalar("select id from core.roles where tenant_id=$1 and code='tenant_owner'",[t]);
 await claims(limited);
 await denied('manager cannot delegate permissions they do not hold','42501',()=>command(t,'create_role',{name:'Escalated role',code:'escalated',permissions:['sales.view'],requires_mfa:false}));
 await denied('manager cannot alter their own assigned role','42501',()=>command(t,'update_role',{id:managerRole.entity.id,name:'Self edit',permissions:['core.roles.manage'],requires_mfa:true},1));
 await denied('owner membership remains protected from other managers','42501',()=>command(t,'set_member_status',{id:ownerMember,status:'suspended'},1));
 await db.exec('reset role');await db.query('update core.role_assignments set legal_entity_id=$1,branch_id=$2 where id=$3',[e,b,managerAssignment]);await claims(limited);
 await denied('branch-scoped manager cannot read global staff','42501',()=>scalar("select api.workspace_admin_list($1,'members')",[t]));
 await db.exec('reset role');await db.query('update core.role_assignments set legal_entity_id=null,branch_id=null where id=$1',[managerAssignment]);
 await claims(owner);
 await denied('system owner role cannot be edited','42501',()=>command(t,'update_role',{id:ownerRole,name:'Owner changed',permissions:['sales.view'],requires_mfa:false},1));
 await denied('self role changes are refused','42501',()=>command(t,'set_assignment',{id:ownerMember,role_id:role.entity.id,granted:true},1));
 await denied('branch cannot be assigned under another company','22023',()=>command(t,'set_assignment',{id:m,role_id:role.entity.id,legal_entity_id:e,branch_id:branch.entity.id,granted:true},1));
 const grant=await command(t,'set_assignment',{id:m,role_id:role.entity.id,legal_entity_id:second.entity.id,branch_id:branch.entity.id,granted:true},1);
 check('scoped assignment advances the membership version',grant.entity.version===2);
 await claims(staff);
 check('assigned permission is available in its exact scope',await scalar("select core.has_permission($1,'sales.view',$2,$3)",[t,second.entity.id,branch.entity.id]));
 check('assigned permission does not leak into a different company',!await scalar("select core.has_permission($1,'sales.view',$2,$3)",[t,e,b]));
 await claims(owner);
 await denied('stale assignment changes are rejected','40001',()=>command(t,'set_assignment',{id:m,role_id:role.entity.id,legal_entity_id:second.entity.id,branch_id:branch.entity.id,granted:false},1));
 const revoked=await command(t,'set_assignment',{id:m,role_id:role.entity.id,legal_entity_id:second.entity.id,branch_id:branch.entity.id,granted:false},2);
 check('revocation advances the current membership version',revoked.entity.version===3);
 await claims(staff);check('revocation removes live authority immediately',!await scalar("select core.has_permission($1,'sales.view',$2,$3)",[t,second.entity.id,branch.entity.id]));await claims(owner);
 await denied('owner role cannot be delegated by invitation','42501',()=>command(t,'create_invitation',{email:'invitee@company.invalid',role_id:ownerRole}));
 const staffInvitation=await command(t,'create_invitation',{email:'staff@company.invalid',role_id:role.entity.id});
 const suspended=await command(t,'set_member_status',{id:m,status:'suspended'},3);
 check('suspension advances membership version',suspended.entity.status==='suspended'&&suspended.entity.version===4);
 check('suspension revokes pending invitations for that account',(await scalar("select api.workspace_admin_list($1,'invitations')",[t])).items.find(i=>i.id===staffInvitation.entity.id)?.status==='revoked');
 await denied('new invitation cannot implicitly restore suspended membership','42501',()=>command(t,'create_invitation',{email:'staff@company.invalid',role_id:role.entity.id}));
 await claims(staff);await denied('revoked invitation cannot restore suspended membership','42501',()=>scalar('select api.workspace_accept_invitation($1,$2)',[staffInvitation.entity.id,randomUUID()]));await claims(owner);
 const restored=await command(t,'set_member_status',{id:m,status:'active'},4);check('reviewed restore confirms a new version',restored.entity.version===5&&restored.entity.status==='active');
 const invitation=await command(t,'create_invitation',{email:'invitee@company.invalid',role_id:role.entity.id,legal_entity_id:second.entity.id,branch_id:branch.entity.id});
 check('invitation receipt exposes no token or token hash',!JSON.stringify(invitation).includes('token'));
 await claims(foreign);await denied('another verified email cannot accept the invitation','42501',()=>scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,randomUUID()]));
 await claims(invitee);
 await denied('JWT email must match the canonical verified account','42501',async()=>{await claims(invitee,{email:'someoneelse@company.invalid'});await scalar('select api.workspace_my_invitations()');});
 await denied('unverified account cannot list invitations','42501',async()=>{await db.exec('reset role');await db.query('update auth.users set email_confirmed_at=null where id=$1',[invitee]);await claims(invitee);await scalar('select api.workspace_my_invitations()');});
 const invitations=await scalar('select api.workspace_my_invitations()');
 check('verified invitee sees their own pending invitation',invitations.items.length===1&&invitations.items[0].id===invitation.entity.id);
 check('invitee sees readable company and branch scope',invitations.items[0].legal_entity_name==='Second Company Final'&&invitations.items[0].branch_name==='Second Office Updated');
 await denied('acceptance cannot resurrect retained revoked roles','42501',async()=>{await db.exec('reset role');await db.query("insert into core.memberships(tenant_id,user_id,status) values($1,$2,'revoked')",[t,invitee]);await claims(invitee);await scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,randomUUID()]);});
 await denied('expired invitation cannot be accepted','42501',async()=>{await db.exec('reset role');await db.query("update core.invitations set expires_at=now()-interval '1 second' where id=$1",[invitation.entity.id]);await claims(invitee);await scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,randomUUID()]);});
 await denied('inviter revocation is rechecked at acceptance','42501',async()=>{await db.exec('reset role');await db.query("update core.memberships set status='suspended' where tenant_id=$1 and user_id=$2",[t,owner]);await claims(invitee);await scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,randomUUID()]);});
 await denied('seat limit is rechecked at acceptance','23514',async()=>{await db.exec('reset role');await db.query("update billing.tenant_subscriptions set seats=(select count(*) from core.memberships where tenant_id=$1 and status in('active','invited')) where tenant_id=$1",[t]);await claims(invitee);await scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,randomUUID()]);});
 const acceptKey=randomUUID(),accepted=await scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,acceptKey]);
 check('verified invitee accepts without a raw token',accepted.entity.user_id===invitee&&accepted.entity.status==='active');
 assert.deepEqual(await scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,acceptKey]),accepted);checks.push('identical acceptance replay preserves the original receipt');
 await denied('closed group cannot replay acceptance','42501',async()=>{await db.exec('reset role');await db.query("update core.tenants set status='closed' where id=$1",[t]);await claims(invitee);await scalar('select api.workspace_accept_invitation($1,$2)',[invitation.entity.id,acceptKey]);});
 await db.exec('reset role');
 check('acceptance creates one scoped assignment',Number(await scalar('select count(*) from core.role_assignments where tenant_id=$1 and membership_id=$2',[t,accepted.entity.id]))===1);
 await claims(owner);
 const legacyInvite=()=>scalar('select api.create_invitation($1,$2,$3,$4,$5,72)',[t,'legacy@company.invalid',role.entity.id,second.entity.id,branch.entity.id]);
 await denied('legacy issuer must complete recent MFA','42501',async()=>{await claims(owner,{age:1000});await legacyInvite();});
 await denied('legacy invitation cannot delegate the owner role','42501',()=>scalar('select api.create_invitation($1,$2,$3)',[t,'legacy@company.invalid',ownerRole]));
 await denied('legacy issuer cannot delegate authority they do not hold','42501',async()=>{
  await db.exec('reset role');await db.query("insert into core.role_permissions(tenant_id,role_id,permission_code) values($1,$2,'core.members.invite')",[t,managerRole.entity.id]);
  await claims(limited);await legacyInvite();});
 const legacyInvitation=await legacyInvite();
 await claims(legacy);
 await denied('legacy acceptance requires canonical email verification','42501',async()=>{await db.exec('reset role');await db.query('update auth.users set email_confirmed_at=null where id=$1',[legacy]);await claims(legacy);await scalar('select api.accept_invitation($1)',[legacyInvitation.token]);});
 await denied('legacy acceptance rechecks the inviter after issue','42501',async()=>{await db.exec('reset role');await db.query("update core.memberships set status='suspended' where tenant_id=$1 and user_id=$2",[t,owner]);await claims(legacy);await scalar('select api.accept_invitation($1)',[legacyInvitation.token]);});
 await denied('legacy acceptance cannot oversubscribe seats','23514',async()=>{await db.exec('reset role');await db.query("update billing.tenant_subscriptions set seats=(select count(*) from core.memberships where tenant_id=$1 and status in('active','invited')) where tenant_id=$1",[t]);await claims(legacy);await scalar('select api.accept_invitation($1)',[legacyInvitation.token]);});
 const legacyAccepted=await scalar('select api.accept_invitation($1)',[legacyInvitation.token]);
 check('valid legacy acceptance still works under the added guards',legacyAccepted.tenant_id===t&&typeof legacyAccepted.membership_id==='string');
 await claims(owner);const laterInvitation=await legacyInvite();
 await denied('legacy token cannot reactivate an inactive membership and its retained roles','42501',async()=>{
  await db.exec('reset role');await db.query("update core.memberships set status='suspended' where tenant_id=$1 and user_id=$2",[t,legacy]);
  await claims(legacy);await scalar('select api.accept_invitation($1)',[laterInvitation.token]);});
 await db.exec('reset role;rollback');
 check('candidate and fixtures roll back',await scalar("select to_regnamespace('workspace_admin') is null"));
 const report={atUtc:new Date().toISOString(),engine:'PGlite 0.5.12 / PostgreSQL 18',passed:checks.length,checks,sources,
  hostedAccess:false,supabaseStackExecuted:false,installedMigration:false,
  fixtureBoundary:'Auth users/JWT functions are simulated. Actual Wave 1 migrations, the exact Wave 2 business-schema prefix before storage provider setup, command helpers, candidate SQL and pgcrypto execute; Supabase storage/runtime is not installed.'};
 await writeFile(new URL('postgres-result.json',import.meta.url),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
}catch(error){console.error(JSON.stringify({message:error.message,code:error.code,where:error.where,detail:error.detail,passed:checks},null,2));process.exitCode=1;
}finally{await db.close();}
