-- Exact provisioning SQL compile/behavior probe, entirely rolled back.
-- These are test-only source shapes and injected claims; not real Auth setup.
insert into core.tenants(id,name,slug,created_by) values('babe6c86-a764-4d3a-80a3-952a7c096c2c','Rollback Edge Setup','rollback-edge-setup',pg_temp.fid('owner'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
 values('caa2bb06-219a-47e9-8132-66d1271b0ffd','babe6c86-a764-4d3a-80a3-952a7c096c2c','Rollback Edge Setup','W5EDGERB','LKR','UTC',6,pg_temp.fid('owner'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
 values('3813692c-f0de-4c69-8e34-d56cf54695b1','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','Rollback Edge Setup','RT1',pg_temp.fid('owner'));
insert into intelligence_control.runtime_worker_scopes(runtime_id,tenant_id,legal_entity_id,branch_id,enabled,expires_at)
 values('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1',true,statement_timestamp()+interval '24 hours');
select set_config('jentra.w5.publishable_key','sb_publishable_3Y69O3VKnAlOipxPBc1MaA_sVJpVR8i',true);
-- PREPARED ONLY. Requires the exact complete-app review and owner approval.
-- Inject ONLY the reviewed public/anon key into jentra.w5.publishable_key; its
-- SHA-256 is checked below. Private values are generated inside Vault and are
-- neither selected nor returned. This is persistent provisioning, NOT a test.

do $setup$ declare schedule_key text;v1 text;v2 text;schedule_id uuid;v1_id uuid;v2_id uuid;
 public_key text;scheduled_ids bigint[];runtime uuid:='778237e3-3d4e-4871-8cc9-e08b07b989c7';begin
 public_key:=current_setting('jentra.w5.publishable_key',true);
 if public_key is null or encode(extensions.digest(public_key,'sha256'),'hex')<>'e3ea9ff3f18e6bb24be674430cc494a31c4cd7d92482367b60383b5aedd6fa9d' then
  raise exception 'REVIEWED_PUBLIC_KEY_REQUIRED';end if;
 if not intelligence_control.runtime_scope_allowed(runtime,'babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1')
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
 scheduled_ids:=array[
  cron.schedule('jentra-w5-20261009-delivery','* * * * *',$job$select intelligence_control.edge_schedule_tick('delivery');$job$),
  cron.schedule('jentra-w5-20261009-subscription','* * * * *',$job$select intelligence_control.edge_schedule_tick('subscription');$job$),
  cron.schedule('jentra-w5-20261009-health','* * * * *',$job$select intelligence_control.edge_schedule_tick('health');$job$)];
 update intelligence_control.edge_authorities set job_ids=scheduled_ids where runtime_id=runtime;
end $setup$;

select is((select count(*) from cron.job where jobname like 'jentra-w5-20261009-%'),3::bigint,'Exact setup registers only three named jobs');
select is((select count(*) from vault.secrets where name like 'jentra-w5-runtime-20261009-%'),3::bigint,'Exact setup provisions only three new runtime keys');
select is((select cardinality(job_ids) from intelligence_control.edge_authorities where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),3,'Authority records all three job IDs');
select is((select count(*) from intelligence_control.edge_key_refs where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),2::bigint,'Only v1/v2 HMAC references are registered');
select ok((select expires_at=issued_at+interval '24 hours' from intelligence_control.edge_authorities where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'New authority is bounded to exactly 24 hours');
select is((select count(*) from intelligence_control.integration_subscriptions where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'),0::bigint,'Setup cannot register a human integration or send an event');
select cron.schedule('w5-rollback-only-protected-job','* * * * *','select 1');
-- Reviewed stop: disables only this authority and its three recorded jobs.

update intelligence_control.edge_authorities set enabled=false where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7';
update intelligence_control.runtime_worker_scopes set enabled=false where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7';
select intelligence_control.edge_schedule_tick('health');

-- No existing account, tenant, function, secret or job is removed. New evidence
-- remains available for review; expiry/disable blocks its worker/receiver paths.

select is((select count(*) from cron.job where jobname like 'jentra-w5-20261009-%'),0::bigint,'Stop removes only authority-owned jobs');
select is((select count(*) from cron.job where jobname='w5-rollback-only-protected-job'),1::bigint,'Unrelated scheduler job is preserved');
select ok(not(select enabled from intelligence_control.edge_authorities where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'),'Stop disables the authority before key/network access');
select ok(not intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7','babe6c86-a764-4d3a-80a3-952a7c096c2c','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1'),'Stop revokes the exact worker scope');
