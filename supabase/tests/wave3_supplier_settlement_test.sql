set constraints all deferred;
select pg_temp.actor('creator');
insert into procurement_test_results select has_function('api','upsert_payment_proposal',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-312 payment proposal command exists');
insert into procurement_test_results select has_function('api','post_supplier_payment',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-312 recorded payment command exists');
