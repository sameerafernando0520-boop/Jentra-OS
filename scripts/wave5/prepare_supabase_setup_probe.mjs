// Composes the exact setup/stop bodies into the same strict rollback fixture.
// Cron metadata stays uncommitted; no schedule tick or HTTP send is performed.
import {readFile,writeFile} from 'node:fs/promises';
import {scopes} from './runtime_plan.mjs';
import {edgeConfiguration as config} from '../../workers/wave5/edge_configuration.mjs';
const s=scopes[0],build=JSON.parse(await readFile('build/w5win9r2/connected/public-build-config.json','utf8'));
const body=async name=>(await readFile('docs/verification/wave5/'+name,'utf8')).replace(/^begin;\s*$/gm,'').replace(/^commit;\s*$/gm,'');
const sql=`-- Exact provisioning SQL compile/behavior probe, entirely rolled back.
-- These are test-only source shapes and injected claims; not real Auth setup.
insert into core.tenants(id,name,slug,created_by) values('${s.tenantId}','Rollback Edge Setup','rollback-edge-setup',pg_temp.fid('owner'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
 values('${s.entityId}','${s.tenantId}','Rollback Edge Setup','W5EDGERB','LKR','UTC',6,pg_temp.fid('owner'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
 values('${s.branchId}','${s.tenantId}','${s.entityId}','Rollback Edge Setup','RT1',pg_temp.fid('owner'));
insert into intelligence_control.runtime_worker_scopes(runtime_id,tenant_id,legal_entity_id,branch_id,enabled,expires_at)
 values('${config.runtimeId}','${s.tenantId}','${s.entityId}','${s.branchId}',true,statement_timestamp()+interval '24 hours');
select set_config('jentra.w5.publishable_key','${build.SUPABASE_PUBLISHABLE_KEY}',true);
${await body('supabase-runtime-setup-20261009.sql')}
select is((select count(*) from cron.job where jobname like 'jentra-w5-20261009-%'),3::bigint,'Exact setup registers only three named jobs');
select is((select count(*) from vault.secrets where name like 'jentra-w5-runtime-20261009-%'),3::bigint,'Exact setup provisions only three new runtime keys');
select is((select cardinality(job_ids) from intelligence_control.edge_authorities where runtime_id='${config.runtimeId}'),3,'Authority records all three job IDs');
select is((select count(*) from intelligence_control.edge_key_refs where runtime_id='${config.runtimeId}'),2::bigint,'Only v1/v2 HMAC references are registered');
select ok((select expires_at=issued_at+interval '24 hours' from intelligence_control.edge_authorities where runtime_id='${config.runtimeId}'),'New authority is bounded to exactly 24 hours');
select is((select count(*) from intelligence_control.integration_subscriptions where tenant_id='${s.tenantId}'),0::bigint,'Setup cannot register a human integration or send an event');
select cron.schedule('w5-rollback-only-protected-job','* * * * *','select 1');
${await body('supabase-runtime-stop-20261009.sql')}
select is((select count(*) from cron.job where jobname like 'jentra-w5-20261009-%'),0::bigint,'Stop removes only authority-owned jobs');
select is((select count(*) from cron.job where jobname='w5-rollback-only-protected-job'),1::bigint,'Unrelated scheduler job is preserved');
select ok(not(select enabled from intelligence_control.edge_authorities where runtime_id='${config.runtimeId}'),'Stop disables the authority before key/network access');
select ok(not intelligence_control.runtime_scope_allowed('${config.runtimeId}','${s.tenantId}','${s.entityId}','${s.branchId}'),'Stop revokes the exact worker scope');
`;
await writeFile('supabase/tests/wave5_supabase_setup_test.sql',sql);
console.log(JSON.stringify({preparedOnly:true,outerRollbackRequired:true,expectedAssertions:10,httpCalls:0}));
