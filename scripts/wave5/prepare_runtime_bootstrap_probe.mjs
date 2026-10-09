import {readFile,writeFile} from 'node:fs/promises';
import {accounts,id,roles,scopes} from './runtime_plan.mjs';
const base=new URL('../../docs/verification/wave5/',import.meta.url);
const scope=await readFile(new URL('../../supabase/migrations/20261008123000_wave5_runtime_scope.sql',import.meta.url),'utf8');
let sql='begin;\n'+scope.slice(0,scope.indexOf('create function api.wave5_runtime_delivery_worker('));
sql+=`create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table w5_runtime_tap(message text);
-- Test-only permission registration validates exact bootstrap mappings; it is
-- not installed provider evidence. Full 28-file checks are a separate gate.
insert into core.permissions(code,module,description,privileged)
 select value,'wave5-bootstrap-fixture','Rollback bootstrap permission mapping',false
 from jsonb_array_elements_text('${JSON.stringify([...new Set(Object.values(roles).flatMap(r=>r.permissions))])}'::jsonb)
 on conflict(code) do nothing;
`;
// Development-only Auth shapes. Real accounts will be created by Auth Admin
// after approval, never by this INSERT or constructed JWT assurance claims.
sql+=`insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at) values
 ${accounts.map(a=>`('${id('rollback-auth.'+a.label)}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','${a.email}','',now(),now(),now())`).join(',\n ')};\n`;
sql+=(await readFile(new URL('runtime-bootstrap-20261008.sql',base),'utf8')).replace(/^begin;\s*$/mg,'').replace(/^commit;\s*$/mg,'');
sql+=`select is((select count(*) from w5_runtime_scopes),500::bigint,'Reviewed bootstrap has exactly 500 new synthetic tenants');
select is((select count(*) from core.memberships where tenant_id in(select tenant_id from w5_runtime_scopes)),1997::bigint,'Exactly 1997 reviewed memberships');
select is((select count(*) from w5_runtime_roles),1003::bigint,'Exactly 1003 explicit synthetic roles');
select is((select count(*) from w5_runtime_assignment_keys),2003::bigint,'Exactly 2003 assignment keys');
select is((select count(*) from core.role_assignments where tenant_id in(select tenant_id from w5_runtime_scopes)),2003::bigint,'Every reviewed assignment resolves an explicit role');
select is((select count(*) from core.memberships where user_id=(select user_id from w5_runtime_accounts where label='operator')),0::bigint,'Separate operator has no business membership');
select is((select count(*) from intelligence_control.runtime_worker_scopes where runtime_id='${id('worker-runtime')}'),1::bigint,'Worker allowlist contains the runtime branch only');
select set_config('request.jwt.claims',jsonb_build_object('sub','${id('rollback-auth.proposer')}','role','authenticated','aal','aal2')::text,true);
select ok(core.has_permission('${scopes[0].tenantId}','analytics.view','${scopes[0].entityId}','${scopes[0].branchId}'),'Reviewed proposer reads main runtime analytics');
select ok(not core.has_permission('${scopes[0].tenantId}','analytics.view','${scopes[0].entityId}','${scopes[0].secondBranchId}'),'Reviewed proposer denied sibling branch analytics');
select ok(not core.has_permission('${scopes[1].tenantId}','analytics.view','${scopes[1].entityId}','${scopes[1].branchId}'),'Reviewed proposer denied foreign tenant analytics');
select * from finish(true);
select jsonb_agg(message) tap,
 (select count(*) from w5_runtime_roles) reviewed_roles,
 (select count(*) from w5_runtime_assignment_keys) reviewed_assignments
 from w5_runtime_tap;
rollback;
`;
sql=sql.replace(/^select (is|ok|throws_ok|lives_ok)\(/gm,'insert into w5_runtime_tap select $1(');
await writeFile(new URL('runtime-bootstrap-probe-20261008.sql',base),sql);
process.stdout.write(JSON.stringify({bytes:Buffer.byteLength(sql),rollback:true,realAccountsCreated:false}));
