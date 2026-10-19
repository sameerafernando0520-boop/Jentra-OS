-- Synthetic page fixture is restored to its prior projections by release.
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('actor'),'role','authenticated','aal','aal2')::text,true);
select set_config('request.jwt.claim.sub',pg_temp.fid('actor')::text,true);
update inventory.stock_balances set allocated_quantity=allocated_quantity+1
 where id=pg_temp.fid('stock.balance');
update sales.sales_order_lines set allocated_quantity=allocated_quantity+1
 where id=pg_temp.fid('order.stock');
insert into inventory.stock_reservations select (jsonb_populate_record(null::inventory.stock_reservations,
 to_jsonb(r)||jsonb_build_object('id',pg_temp.fid('maintenance.reservation'),'base_quantity','1',
 'status','active','version',1,'expires_at',clock_timestamp()-interval '1 minute',
 'released_at',null,'release_reason',null,'created_at',clock_timestamp()))).*
 from inventory.stock_reservations r where r.id=(select id from release_before);
create function pg_temp.maintenance_payload(n text default 'maintenance.report') returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fid(n),'mode','expired','reason','Bounded expiry maintenance',
 'limit',1)$$;
insert into final_stack_results select throws_ok($$select pg_temp.call('maintain_stock_reservations',
 pg_temp.maintenance_payload()||'{"limit":51}'::jsonb,0,'maintenance.invalid')$$,
 '22023','RESERVATION_MAINTENANCE_INPUT_INVALID','maintenance refuses an unbounded page');
create trigger synthetic_maintenance_failure before insert on core.outbox_events
 for each row execute function pg_temp.fail_outbox();
insert into final_stack_results select throws_ok($$select pg_temp.call('maintain_stock_reservations',
 pg_temp.maintenance_payload(),0,'maintenance.report')$$,'P0001','SYNTHETIC_OUTBOX_FAILURE',
 'late maintenance failure rolls back child release and outer receipt');
drop trigger synthetic_maintenance_failure on core.outbox_events;
insert into final_stack_results select is((select status from inventory.stock_reservations
 where id=pg_temp.fid('maintenance.reservation')),'active',
 'failed maintenance preserves the held reservation');
insert into final_stack_results select is((select allocated_quantity from inventory.stock_balances
 where id=pg_temp.fid('stock.balance')),1::numeric,
 'failed maintenance preserves exact stock allocation');
create temp table maintenance_response as select pg_temp.call('maintain_stock_reservations',
 pg_temp.maintenance_payload(),0,'maintenance.report') result;
insert into final_stack_results select is((select result#>>'{entity,processed_count}' from maintenance_response),
 '1','maintenance processes one eligible reservation');
insert into final_stack_results select is((select result#>>'{entity,has_more}' from maintenance_response),
 'false','maintenance reports the complete bounded page');
insert into final_stack_results select is((select status from inventory.stock_reservations
 where id=pg_temp.fid('maintenance.reservation')),'expired',
 'governed child command records expiry in immutable reservation history');
insert into final_stack_results select is((select allocated_quantity from inventory.stock_balances
 where id=pg_temp.fid('stock.balance')),0::numeric,
 'maintenance releases projection without changing physical stock');
insert into final_stack_results select is(pg_temp.call('maintain_stock_reservations',
 pg_temp.maintenance_payload(),0,'maintenance.report'),(select result from maintenance_response),
 'same maintenance command replays its original receipt');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('foreign_actor'),'role','authenticated','aal','aal2')::text,true);
select set_config('request.jwt.claim.sub',pg_temp.fid('foreign_actor')::text,true);
insert into final_stack_results select throws_ok($$select pg_temp.call('maintain_stock_reservations',
 pg_temp.maintenance_payload('maintenance.foreign'),0,'maintenance.foreign')$$,'42501',null,
 'foreign actor cannot enumerate or release another tenant maintenance page');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('actor'),'role','authenticated','aal','aal2')::text,true);
select set_config('request.jwt.claim.sub',pg_temp.fid('actor')::text,true);
