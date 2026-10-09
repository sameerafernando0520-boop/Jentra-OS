-- Synthetic policy/adapter fixture only; included in one strict rollback.
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid=any(array[
 'intelligence_control.edge_authorities'::regclass,'intelligence_control.edge_key_refs'::regclass,'intelligence_control.edge_ticks'::regclass,
 'intelligence_control.edge_tick_outcomes'::regclass,'intelligence_control.edge_receiver_receipts'::regclass])),'All Edge stores force RLS');
select ok(not has_function_privilege('authenticated','api.wave5_edge_control(uuid,text,jsonb)','execute'),'Clients cannot access Edge control or secrets');
select ok(has_function_privilege('service_role','api.wave5_edge_control(uuid,text,jsonb)','execute'),'Trusted runtime can access scoped Edge control');
select ok(not has_function_privilege('service_role','intelligence_control.edge_schedule_tick(text)','execute'),'Only database-owned scheduler can issue a tick');
update intelligence_control.runtime_worker_scopes set enabled=true where runtime_id=pg_temp.fid('runtime');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'begin_tick','{}')$$,'42501','RUNTIME_SCOPE_DENIED','Absent authority blocks before any work');
create temporary table edge_fixture_secrets as select vault.create_secret(repeat('a',64),'w5-rollback-only-edge-v1') id;
insert into intelligence_control.edge_authorities(runtime_id,enabled,expires_at,schedule_secret_id,schedule_secret_hash,publishable_key)
 select pg_temp.fid('runtime'),true,statement_timestamp()+interval '1 hour',id,encode(extensions.digest(repeat('c',64),'sha256'),'hex'),repeat('p',64) from edge_fixture_secrets;
insert into intelligence_control.edge_key_refs select pg_temp.fid('runtime'),'w5/runtime/20261008/delivery/v1',id from edge_fixture_secrets;
create function pg_temp.edge_tick(label text,kind text default 'health',secret_hash text default null) returns jsonb language sql as $$
 select jsonb_build_object('tickId',pg_temp.fid(label),'kind',kind,'secretHash',coalesce(secret_hash,encode(extensions.digest(repeat('c',64),'sha256'),'hex')))$$;
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'begin_tick',pg_temp.edge_tick('edge.bad','health',repeat('b',64)))$$,
 '42501','WORKER_ACCESS_DENIED','Wrong schedule secret creates no tick');
select is((select count(*) from intelligence_control.edge_ticks),0::bigint,'Denied tick has no effect');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'begin_tick',pg_temp.edge_tick('edge.health'))->>'permitted','true','Authorized bounded tick begins');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'begin_tick',pg_temp.edge_tick('edge.health'))->>'permitted','false','Duplicate tick cannot repeat work');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'begin_tick',pg_temp.edge_tick('edge.overlap'))->>'permitted','false','Overlapping kind cannot repeat work');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'begin_tick',pg_temp.edge_tick('edge.subscription','subscription'))->>'permitted','true','Different job kind has an independent lease');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'finish_tick',jsonb_build_object('tickId',pg_temp.fid('edge.health'),'success',true,'summary',jsonb_build_object('count',1,'states',jsonb_build_array('collected'))))->>'recorded','true','Outcome persists before completed response');
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'finish_tick',jsonb_build_object('tickId',pg_temp.fid('edge.health'),'success',true,'summary','{}'::jsonb))$$,
 '42501','LEASE_UNAVAILABLE','Completed tick cannot finish twice');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'begin_tick',pg_temp.edge_tick('edge.next'))->>'permitted','true','New tick can follow completed work');
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'key','{"ref":"other-project-secret"}')$$,'42501','DELIVERY_KEY_UNAVAILABLE','Arbitrary Vault names are inaccessible');
select is(length(api.wave5_edge_control(pg_temp.fid('runtime'),'key','{"ref":"w5/runtime/20261008/delivery/v1"}')->>'value'),64,'Only registered synthetic runtime key resolves');
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'invalid','{}')$$,'22023','WORKER_ACTION_INVALID','Unnamed dispatch is denied');
select is(intelligence_control.edge_schedule_tick('health'),null::bigint,'Unconfigured actual schedule performs no network');
select throws_ok($$select intelligence_control.edge_schedule_tick('invalid')$$,'22023','VALIDATION_ERROR','Unnamed schedule is denied');
-- Nonempty committed-event receipt contract; still policy-only rollback data.
insert into intelligence_control.integration_hosts values('xpdoufauvrbdmxgngetv.supabase.co');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'integrations.manage');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled,numeric_limit)
 values('starter','quota.webhook.deliveries',true,100)
 on conflict(plan_code,entitlement_code) do update set enabled=true,numeric_limit=100;
insert into intelligence_control.integration_subscriptions(id,tenant_id,legal_entity_id,branch_id,created_by,url,hostname,key_ref)
 select id,pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('owner'),
 'https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-receiver/'||mode,
 'xpdoufauvrbdmxgngetv.supabase.co','w5/runtime/20261008/delivery/v1'
 from(values('58699e8a-28fd-4356-8cad-87ce46e17ddd'::uuid,'accept'),('0961e194-dc0b-4632-8c2d-65686fc9f111'::uuid,'timeout'),
 ('2bdbd842-5b94-464b-85fc-22d722498831'::uuid,'redirect'),('360e7a9d-08a5-4349-854f-c2343ce2ff5d'::uuid,'reject')) x(id,mode);
insert into core.outbox_events(id,tenant_id,topic,aggregate_type,aggregate_id,payload)
 values(pg_temp.fid('edge.event'),pg_temp.fid('t'),'analytics.freeze_pipeline','pipeline_forecast',pg_temp.fid('runtime.model.source'),'{}');
create function pg_temp.edge_event(mode text default 'accept',hash_override text default null,age integer default 0) returns jsonb language sql as $$
 with event as(select jsonb_build_object('eventId',pg_temp.fid('edge.event'),'type','analytics.forecast.frozen.v1',
 'tenantId',pg_temp.fid('t'),'legalEntityId',pg_temp.fid('e'),'branchId',pg_temp.fid('b'),
 'forecastId',pg_temp.fid('runtime.model.source'),'definitionVersion',1,'sourceHash',encode(extensions.digest('{}','sha256'),'hex')) value)
 select jsonb_build_object('event',value,'mode',mode,'keyVersion',1,'payloadBase64',encode(convert_to(value::text,'UTF8'),'base64'),
 'sha256',coalesce(hash_override,encode(extensions.digest(convert_to(value::text,'UTF8'),'sha256'),'hex')),
 'timestamp',floor(extract(epoch from statement_timestamp()))::bigint+age) from event$$;
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event())$$,
 '42501','LEASE_UNAVAILABLE','Committed event without a delivery lease cannot be acknowledged');
insert into intelligence_control.delivery_heads(id,tenant_id,subscription_id,event_id,attempt,state,lease_id,lease_until)
 select pg_temp.fid('edge.delivery.'||url),tenant_id,id,pg_temp.fid('edge.event'),1,'leased',pg_temp.fid('edge.lease.'||url),statement_timestamp()+interval '1 minute'
 from intelligence_control.integration_subscriptions where hostname='xpdoufauvrbdmxgngetv.supabase.co';
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event())$$,
 '42501','LEASE_UNAVAILABLE','A lease without its persisted attempt cannot acknowledge');
insert into intelligence_control.delivery_attempts(tenant_id,delivery_id,attempt,lease_id,key_version,subscription_version)
 select d.tenant_id,d.id,d.attempt,d.lease_id,1,1 from intelligence_control.delivery_heads d
 join intelligence_control.integration_subscriptions s on s.id=d.subscription_id where s.hostname='xpdoufauvrbdmxgngetv.supabase.co';
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event('accept',repeat('b',64)))$$,
 '22023','EVENT_CONTRACT_MISMATCH','Digest mismatch is rejected before receipt creation');
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event('accept',null,-301))$$,
 '22023','EVENT_CONTRACT_MISMATCH','Expired signed timestamp is rejected before receipt creation');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event())->>'acknowledged','true','Matching committed event and active persisted lease store an ACK');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event())->>'duplicate','true','Duplicate exact event returns its durable receipt');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event('timeout'))->>'duplicate','false','Independent receiver subscription has its own durable receipt');
select is(api.wave5_edge_control(pg_temp.fid('runtime'),'receive_probe',pg_temp.edge_event('redirect'))->>'permitted','true','Reviewed redirect probe authenticates the actual source');
select is((select count(*) from intelligence_control.edge_receiver_receipts),2::bigint,'Redirect probe cannot create an acknowledgement');
update intelligence_control.integration_subscriptions set enabled=false where id='58699e8a-28fd-4356-8cad-87ce46e17ddd';
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'receive',pg_temp.edge_event())$$,
 '42501','INTEGRATION_ACCESS_DENIED','Revocation denies even a previously acknowledged duplicate');
select throws_ok($$update intelligence_control.edge_receiver_receipts set sha256=repeat('b',64)$$,
 '55000','IMMUTABLE_EVIDENCE','Receipt bytes and digest are immutable');
update intelligence_control.edge_authorities set enabled=false where runtime_id=pg_temp.fid('runtime');
select throws_ok($$select api.wave5_edge_control(pg_temp.fid('runtime'),'key','{"ref":"w5/runtime/20261008/delivery/v1"}')$$,'42501','RUNTIME_SCOPE_DENIED','Revocation precedes private key lookup');
select is((select count(*) from cron.job),0::bigint,'Candidate setup never scheduled a real job');
