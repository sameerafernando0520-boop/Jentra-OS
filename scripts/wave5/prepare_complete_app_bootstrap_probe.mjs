import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {accounts,id,roles,scopes} from './complete_app_runtime_plan.mjs';
import {encode} from './candidate_transport.mjs';
const base='docs/verification/wave5/',sha=b=>createHash('sha256').update(b).digest('hex');
const candidate=JSON.parse(await readFile(base+'complete-app-candidate-20261009.hashes.json','utf8'));
const sources={},parts=['begin;'];
for(const [p,h] of Object.entries(candidate.sources).filter(([p])=>p.startsWith('supabase/migrations/'))){
 const sql=await readFile(p,'utf8');if(sha(sql)!==h)throw Error('VERIFIED_MIGRATION_DRIFT');sources[p]=h;parts.push(sql.replace(/^\s*begin;\s*$/gm,''));
}
parts.push(`create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table w5_runtime_tap(message text);
-- Test-only Auth shapes. No permission registration shim: all reviewed role
-- permissions must exist in the actual 71-file composition. Not real MFA.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
${accounts.map(a=>`('${id('rollback-auth.'+a.label)}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${a.email}','',now(),now(),now())`).join(',\n')};`);
parts.push(`-- Test-only IDs, never a runtime Auth binding.
select set_config('jentra.w5.created_auth_ids','${JSON.stringify(Object.fromEntries(accounts.map(a=>[a.label,id('rollback-auth.'+a.label)])))}',true);`);
const bootstrapPath=base+'runtime-bootstrap-complete-app-20261009.sql',bootstrap=await readFile(bootstrapPath,'utf8');sources[bootstrapPath]=sha(bootstrap);
parts.push(bootstrap.replace(/^begin;\s*$/mg,'').replace(/^commit;\s*$/mg,''));
const runtime=scopes[0],foreign=scopes[1],proposer=id('rollback-auth.proposer'),approver=id('rollback-auth.approver'),executor=id('rollback-auth.executor');
const roleIds=scopes.flatMap(s=>(s.key==='runtime'?['reader','financeAnchor','proposer','approver','executor','billing']:s.key==='foreign'?['foreignReader']:['loadReader',s.key==='load-001'?'billing':'loadBilling']).map(k=>id(s.key+'.role.'+k))).sort();
const at=s=>`'${s.tenantId}','${s.entityId}','${s.branchId}'`;
const actor=(a,aal='aal2')=>`select set_config('request.jwt.claims',jsonb_build_object('sub','${a}','role','authenticated','aal','${aal}')::text,true);`;
const access=(kind,action)=>`select analytics.cash_date_access(${at(runtime)},'${kind}','${action}')`;
const tests=`select is((select count(*) from w5_runtime_scopes),500::bigint,'Reviewed bootstrap has exactly 500 new synthetic tenants');
select is((select count(*) from core.memberships where tenant_id in(select tenant_id from w5_runtime_scopes)),1997::bigint,'Exactly 1997 reviewed memberships');
select is((select count(*) from w5_runtime_roles),1003::bigint,'Exactly 1003 explicit synthetic roles');
select is((select count(*) from w5_runtime_assignment_keys),2003::bigint,'Exactly 2003 assignment keys');
select is((select count(*) from core.role_assignments where tenant_id in(select tenant_id from w5_runtime_scopes)),2003::bigint,'Every reviewed assignment resolves an explicit role');
select is((select count(*) from core.memberships where user_id=(select user_id from w5_runtime_accounts where label='operator')),0::bigint,'Separate operator has no business membership');
select is((select count(*) from intelligence_control.runtime_worker_scopes where runtime_id='${id('worker-runtime')}'),1::bigint,'Worker allowlist contains the runtime branch only');
${actor(proposer)}
select ok(core.has_permission(${at(runtime).split(',').slice(0,1).join(',')},'analytics.view','${runtime.entityId}','${runtime.branchId}'),'Reviewed proposer reads runtime analytics');
select ok(not core.has_permission('${runtime.tenantId}','analytics.view','${runtime.entityId}','${runtime.secondBranchId}'),'Reviewed proposer denied sibling branch analytics');
select ok(not core.has_permission('${foreign.tenantId}','analytics.view','${foreign.entityId}','${foreign.branchId}'),'Reviewed proposer denied foreign tenant analytics');
select ok(exists(select 1 from billing.plan_entitlements where plan_code='w5_runtime_20261008' and entitlement_code='module.people' and enabled),'Exact runtime plan enables authoritative payroll date reads');
select lives_ok($t$${access('payroll_obligation','prepare')}$t$,'Reviewed proposer can prepare payroll dates');
select lives_ok($t$${access('payroll_correction','prepare')}$t$,'Reviewed proposer can prepare signed correction dates');
select lives_ok($t$${access('project_reimbursement','prepare')}$t$,'Reviewed proposer can prepare reimbursement dates');
select throws_ok($t$${access('payroll_obligation','approve')}$t$,'42501',null,'Proposer cannot approve dates');
${actor(approver)}
select lives_ok($t$${access('payroll_obligation','approve')}$t$,'Distinct reviewed approver can approve payroll dates');
select lives_ok($t$${access('payroll_correction','approve')}$t$,'Distinct reviewed approver can approve correction dates');
select lives_ok($t$${access('project_reimbursement','approve')}$t$,'Distinct reviewed approver can approve reimbursement dates');
select throws_ok($t$${access('payroll_obligation','prepare')}$t$,'42501',null,'Approver cannot prepare dates');
select is(api.wave5_classification_authorize(${at(runtime)}),'${approver}'::uuid,'Reviewed approver can review financial classifications');
${actor(executor)}
select throws_ok($t$${access('payroll_obligation','approve')}$t$,'42501',null,'Executor cannot approve dates');
select lives_ok($t$${access('payroll_obligation','read')}$t$,'Reviewed executor can reopen authorized cash sources with MFA');
${actor(proposer,'aal1')}
select throws_ok($t$${access('payroll_obligation','read')}$t$,'42501',null,'AAL1 cannot read private authoritative payment dates');
select is(api.wave5_proposal_authorize(${at(runtime)}),'${proposer}'::uuid,'Reviewed numeric model retrieval authority remains separate from private cash MFA');
select is((select encode(extensions.digest(string_agg(role_id::text,E'\\n' order by role_id::text),'sha256'),'hex') from w5_runtime_roles),'${sha(roleIds.join('\n'))}','All 1003 set-based role UUIDs match the independent exact reviewed IDs');
select * from finish(true);
select jsonb_agg(message) tap from w5_runtime_tap;
rollback;`;
parts.push(tests.replace(/^select (is|ok|throws_ok|lives_ok)\(/gm,'insert into w5_runtime_tap select $1('));
const original=parts.join('\n'),file=base+'complete-app-bootstrap-probe-20261009.sql';
await writeFile(file,original);
const body=original.replace(/^begin;\s*/,'').replace(/\s*rollback;\s*$/,''),bodyHash=sha(body),b64=encode(body,{level:9});
const transport=`begin;create temporary table w5_bootstrap_result(tap jsonb);
do $transport$ declare q bytea;r jsonb;begin
q:=extensions.pgp_sym_decrypt_bytea(decode('${b64}','base64'),'jentra-public-candidate-transport-v1');
if encode(extensions.digest(q,'sha256'),'hex')<>'${bodyHash}' then raise exception 'BOOTSTRAP_TRANSPORT_HASH_MISMATCH';end if;
execute convert_from(q,'UTF8') into r;insert into w5_bootstrap_result values(r);end $transport$;
select tap from w5_bootstrap_result;rollback;`;
await writeFile(base+'complete-app-bootstrap-transport-20261009.sql',transport);
await writeFile(base+'complete-app-bootstrap-probe-20261009.hashes.json',JSON.stringify({sources,sourceSha256:sha(original),bodySha256:bodyHash,
 transportSha256:sha(transport),strictAssertions:25,strictFinish:true,rolledBack:true,permissionShim:false,realAuth:false,noHttp:true},null,2)+'\n');
console.log(JSON.stringify({strictAssertions:25,rawBytes:Buffer.byteLength(original),transportBytes:Buffer.byteLength(transport),bodySha256:bodyHash}));
