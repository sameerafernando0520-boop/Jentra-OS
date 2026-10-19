-- Read-only diagnostic after the original activation; enclosing strict query
-- preserves its exact request and rolls back all candidate/fixture effects.
do $$declare stored core.command_receipts%rowtype;expected text;begin
 select * into stored from core.command_receipts where command_id=pg_temp.fid('negative.enable');
 expected:=core.wave3_request_hash('inventory.stock.policy.configure',pg_temp.fid('negative.enable'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
  '{"active":true,"reason":"Approved synthetic policy decision"}'::jsonb,0);
 if stored.request_hash is distinct from expected then
  raise exception using errcode='P0001',message='NEGATIVE_POLICY_REPLAY_HASH_DIAGNOSTIC',detail=jsonb_build_object(
   'stored_hash',stored.request_hash,'expected_zero_hash',expected,'actor',stored.actor_id,'expected_actor',pg_temp.fid('creator'),
   'command',stored.command_id,'expected_command',pg_temp.fid('negative.enable'),'command_name',stored.command_name,'current_policy_version',pg_temp.ns_version())::text;
 end if;
end $$;
insert into procurement_test_results select is(pg_temp.call('configure_negative_stock_policy','{"active":true,"reason":"Approved synthetic policy decision"}',0,'negative.enable'),
 (select response from negative_stock_responses where name='enable'),'diagnostic original policy activation replays unchanged');
