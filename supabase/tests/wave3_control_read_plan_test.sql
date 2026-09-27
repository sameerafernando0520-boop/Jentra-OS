-- Repeatable read-plan evidence on the complete synthetic accounting fixture.
select pg_temp.actor('creator');
insert into procurement_test_results select has_index('inventory','stock_movements',
 'stock_movements_finance_command_source','control basis has a scoped immutable-command/source index');
insert into procurement_test_results select is(current_setting('jit'),'on','final control read regression runs with JIT enabled');
insert into procurement_test_results select is((select p.provolatile::text from pg_proc p
 where p.oid='finance.close_inventory_accounts(uuid,uuid,date)'::regprocedure),'s',
 'optimized control basis retains a stable statement snapshot');
create temp table control_read_plans(plan jsonb);
create function pg_temp.record_control_read_plan(i integer) returns void language plpgsql as $$declare row record;begin
 for row in execute format('explain (analyze,buffers,format json) select finance.close_inventory_accounts(%L::uuid,%L::uuid,%L::date)',
  pg_temp.fid('tenant'),pg_temp.fid('entity'),'2026-09-25') loop
  insert into control_read_plans values(jsonb_build_object('iteration',i,'jit',current_setting('jit'),'plan',row."QUERY PLAN"));
 end loop;
end$$;
select pg_temp.record_control_read_plan(1);
select pg_temp.record_control_read_plan(2);
select pg_temp.record_control_read_plan(3);
