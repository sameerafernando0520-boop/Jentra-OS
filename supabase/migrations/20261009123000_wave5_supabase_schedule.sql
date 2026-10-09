-- UNINSTALLED infrastructure candidate. Enables the reviewed extensions but
-- creates no job/secret/authority. Jobs are a separate reviewed setup operation.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create function intelligence_control.edge_schedule_tick(p_kind text) returns bigint
language plpgsql security definer set search_path='' as $$
declare a intelligence_control.edge_authorities%rowtype;k text;j bigint;begin
 if p_kind not in('delivery','subscription','health') then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 select * into a from intelligence_control.edge_authorities where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7';
 if a.runtime_id is null then return null;end if;
 if not a.enabled or a.expires_at<=statement_timestamp() or not exists(select 1 from intelligence_control.runtime_worker_scopes s
  where s.runtime_id=a.runtime_id and intelligence_control.runtime_scope_allowed(a.runtime_id,s.tenant_id,s.legal_entity_id,s.branch_id)) then
  -- Only this authority's recorded job IDs and exact reviewed names are stopped.
  for j in select jobid from cron.job where jobid=any(a.job_ids)
   and jobname in('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health') loop
   perform cron.unschedule(j);end loop;
  update intelligence_control.edge_authorities set enabled=false where runtime_id=a.runtime_id;return null;
 end if;
 select decrypted_secret into k from vault.decrypted_secrets where id=a.schedule_secret_id;
 if k is null or encode(extensions.digest(k,'sha256'),'hex')<>a.schedule_secret_hash then raise exception using errcode='42501',message='WORKER_ACCESS_DENIED';end if;
 return net.http_post(url:='https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule',
  headers:=jsonb_build_object('content-type','application/json','apikey',a.publishable_key,'x-jentra-schedule-key',k),
  body:=jsonb_build_object('tickId',gen_random_uuid(),'kind',p_kind),timeout_milliseconds:=70000);
end$$;
revoke all on function intelligence_control.edge_schedule_tick(text) from public,anon,authenticated,service_role;
