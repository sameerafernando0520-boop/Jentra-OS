// Generates reviewable SQL only. Never installs extensions, provisions secrets
// or schedules/deploys a worker. Public key is injected after explicit approval.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {edgeConfiguration as config} from '../../workers/wave5/edge_configuration.mjs';
import {scopes} from './runtime_plan.mjs';
const main=scopes[0],sha=s=>createHash('sha256').update(s).digest('hex');
const build=JSON.parse(await readFile('build/w5win9r2/connected/public-build-config.json','utf8'));
const publicKey=build.SUPABASE_PUBLISHABLE_KEY;
if(build.SUPABASE_URL!==config.url||typeof publicKey!=='string'||publicKey.length<32)throw Error('PUBLIC_BUILD_BINDING_MISMATCH');
const sql=`-- PREPARED ONLY. Requires the exact complete-app review and owner approval.
-- Inject ONLY the reviewed public/anon key into jentra.w5.publishable_key; its
-- SHA-256 is checked below. Private values are generated inside Vault and are
-- neither selected nor returned. This is persistent provisioning, NOT a test.
begin;
do $setup$ declare schedule_key text;v1 text;v2 text;schedule_id uuid;v1_id uuid;v2_id uuid;
 public_key text;job_ids bigint[];runtime uuid:='${config.runtimeId}';begin
 public_key:=current_setting('jentra.w5.publishable_key',true);
 if public_key is null or encode(extensions.digest(public_key,'sha256'),'hex')<>'${sha(publicKey)}' then
  raise exception 'REVIEWED_PUBLIC_KEY_REQUIRED';end if;
 if not intelligence_control.runtime_scope_allowed(runtime,'${main.tenantId}','${main.entityId}','${main.branchId}')
  or (select count(*) from intelligence_control.runtime_worker_scopes where runtime_id=runtime)<>1 then
  raise exception 'EXACT_RUNTIME_SCOPE_REQUIRED';end if;
 if exists(select 1 from intelligence_control.edge_authorities where runtime_id=runtime)
  or exists(select 1 from vault.secrets where name in('jentra-w5-runtime-20261009-schedule','jentra-w5-runtime-20261009-delivery-v1','jentra-w5-runtime-20261009-delivery-v2'))
  or exists(select 1 from cron.job where jobname in('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health')) then
  raise exception 'RUNTIME_CONFIGURATION_COLLISION';end if;
 schedule_key:=encode(extensions.gen_random_bytes(32),'hex');
 v1:=encode(extensions.gen_random_bytes(32),'hex');v2:=encode(extensions.gen_random_bytes(32),'hex');
 schedule_id:=vault.create_secret(schedule_key,'jentra-w5-runtime-20261009-schedule','New reviewed synthetic runtime schedule key; never an existing secret');
 v1_id:=vault.create_secret(v1,'jentra-w5-runtime-20261009-delivery-v1','New synthetic runtime HMAC v1');
 v2_id:=vault.create_secret(v2,'jentra-w5-runtime-20261009-delivery-v2','New synthetic runtime HMAC v2 rotation target');
 insert into intelligence_control.edge_authorities(runtime_id,enabled,expires_at,schedule_secret_id,schedule_secret_hash,publishable_key)
  values(runtime,true,statement_timestamp()+interval '24 hours',schedule_id,encode(extensions.digest(schedule_key,'sha256'),'hex'),public_key);
 insert into intelligence_control.edge_key_refs values(runtime,'w5/runtime/20261008/delivery/v1',v1_id),(runtime,'w5/runtime/20261008/delivery/v2',v2_id);
 insert into intelligence_control.integration_hosts(hostname) values('xpdoufauvrbdmxgngetv.supabase.co') on conflict do nothing;
 -- Register subscriptions through the authenticated MFA API afterwards. The
 -- worker discovers only committed events created after each registration.
 job_ids:=array[
  cron.schedule('jentra-w5-20261009-delivery','* * * * *',$job$select intelligence_control.edge_schedule_tick('delivery');$job$),
  cron.schedule('jentra-w5-20261009-subscription','* * * * *',$job$select intelligence_control.edge_schedule_tick('subscription');$job$),
  cron.schedule('jentra-w5-20261009-health','* * * * *',$job$select intelligence_control.edge_schedule_tick('health');$job$)];
 update intelligence_control.edge_authorities set job_ids=job_ids where runtime_id=runtime;
end $setup$;
commit;
`;
// Avoid ambiguity between the PL/pgSQL variable and table column.
await writeFile('docs/verification/wave5/supabase-runtime-setup-20261009.sql',sql.replaceAll('job_ids bigint[]','scheduled_ids bigint[]').replace('job_ids:=array[','scheduled_ids:=array[').replace('set job_ids=job_ids','set job_ids=scheduled_ids'));
await writeFile('docs/verification/wave5/supabase-runtime-stop-20261009.sql',`-- Reviewed stop: disables only this authority and its three recorded jobs.
begin;
update intelligence_control.edge_authorities set enabled=false where runtime_id='${config.runtimeId}';
update intelligence_control.runtime_worker_scopes set enabled=false where runtime_id='${config.runtimeId}';
select intelligence_control.edge_schedule_tick('health');
commit;
-- No existing account, tenant, function, secret or job is removed. New evidence
-- remains available for review; expiry/disable blocks its worker/receiver paths.
`);
console.log(JSON.stringify({preparedOnly:true,secretsCreated:0,jobsScheduled:0,proposedNewSecrets:3,proposedJobs:3,publicKeySha256:sha(publicKey)}));
