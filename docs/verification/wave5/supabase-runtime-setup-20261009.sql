-- PREPARED ONLY. Requires the exact complete-app review and owner approval.
-- Inject ONLY the reviewed public/anon key into jentra.w5.publishable_key; its
-- SHA-256 is checked below. Private values are generated inside Vault and are
-- neither selected nor returned. This is persistent provisioning, NOT a test.
begin;
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
commit;
