-- Appended to the real order/delivery fixture; never run persistently.
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('actor'),'role','authenticated','aal','aal2')::text,true);
select set_config('request.jwt.claim.sub',pg_temp.fid('actor')::text,true);
create temporary table release_before as select r.*,b.on_hand_quantity,b.allocated_quantity as stock_allocated,v.carrying_value,
 (select count(*) from inventory.stock_movements) movement_count,(select count(*) from finance.journal_entries) journal_count,
 (select count(*) from inventory.reservation_history) history_count
 from inventory.stock_reservations r join inventory.stock_balances b on b.product_id=r.product_id and b.warehouse_id=r.warehouse_id
 join inventory.stock_valuations v on v.stock_balance_id=b.id where r.sales_order_line_id=pg_temp.fid('order.stock') and r.status='active';
create function pg_temp.release_payload(p_mode text default 'manual',p_reason text default 'Customer changed delivery plan') returns jsonb language sql as $$
 select jsonb_build_object('id',id,'mode',p_mode,'reason',p_reason) from release_before $$;
create temporary table release_cutoff as select clock_timestamp() instant;
select is((select count(*) from inventory.reservation_history where snapshot->>'status'='active' and snapshot->>'base_quantity'='10.000000'),1::bigint,'history retains original allocation before partial delivery');
select ok(exists(select 1 from inventory.reservation_history where snapshot->>'base_quantity'='7.000000'),'history retains exact residual after delivery');
select throws_ok($$select pg_temp.call('release_stock_reservation',pg_temp.release_payload('expired'),(select version from release_before))$$,'55000','RESERVATION_NOT_EXPIRED','early expiry cannot release stock');
select throws_ok($$select pg_temp.call('release_stock_reservation',pg_temp.release_payload('retired'),(select version from release_before))$$,'55000','PRODUCT_STILL_ACTIVE','retirement mode verifies product status');
select throws_ok($$select pg_temp.call('release_stock_reservation',pg_temp.release_payload('manual','x'),(select version from release_before))$$,'22023','RESERVATION_RELEASE_INPUT_INVALID','release needs a meaningful reason');
select throws_ok($$select pg_temp.call('release_stock_reservation',pg_temp.release_payload(),0)$$,'40001',null,'stale reservation cannot release newer allocation');
create trigger synthetic_release_outbox_failure before insert on core.outbox_events for each row execute function pg_temp.fail_outbox();
select throws_ok($$select pg_temp.call('release_stock_reservation',pg_temp.release_payload(),(select version from release_before),'release.command')$$,'P0001','SYNTHETIC_OUTBOX_FAILURE','late outbox failure rolls back release');
drop trigger synthetic_release_outbox_failure on core.outbox_events;
select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('stock.balance')),(select stock_allocated from release_before),'failed release preserves stock allocation');
select is((select count(*) from inventory.reservation_history),(select history_count from release_before),'failed release leaves no history');
insert into flow_results select 'release.confirmed',pg_temp.call('release_stock_reservation',pg_temp.release_payload(),(select version from release_before),'release.command');
select is((select status from inventory.stock_reservations where id=(select id from release_before)),'released','whole remaining reservation released');
select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('stock.balance')),0::numeric,'stock allocation reduced exactly');
select is((select allocated_quantity from sales.sales_order_lines where id=pg_temp.fid('order.stock')),0::numeric,'order allocation reduced exactly');
select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('stock.balance')),(select on_hand_quantity from release_before),'release preserves physical stock');
select is((select carrying_value from inventory.stock_valuations where stock_balance_id=pg_temp.fid('stock.balance')),(select carrying_value from release_before),'release preserves valuation');
select is((select count(*) from inventory.stock_movements),(select movement_count from release_before),'release creates no stock movement');
select is((select count(*) from finance.journal_entries),(select journal_count from release_before),'release creates no journal');
select is(pg_temp.call('release_stock_reservation',pg_temp.release_payload(),(select version from release_before),'release.command'),(select result from flow_results where name='release.confirmed'),'identical release retries return original receipt');
select throws_ok($$select pg_temp.call('release_stock_reservation',pg_temp.release_payload('manual','Changed reason'),(select version from release_before),'release.command')$$,'22023',null,'same key cannot change release reason');
select is((select count(*) from inventory.reservation_history),(select history_count+1 from release_before),'one release produces one immutable history event');
select is((select z->>'base_quantity' from jsonb_array_elements(api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select instant from release_cutoff))->'items')z where z->>'id'=(select id::text from release_before)),'7.000000','as-of report retains held residual before later release');
select is(jsonb_array_length(api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),clock_timestamp())->'items'),2,'current as-of report excludes released allocation');
select is(jsonb_array_length(api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select starts_at from inventory.reservation_history_coverage))->'items'),0,'as-of report excludes reservations created after cutoff');
select throws_ok($$select api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select starts_at-interval '1 microsecond' from inventory.reservation_history_coverage))$$,'22023','RESERVATION_ASOF_OUTSIDE_COVERAGE','as-of cannot invent pre-coverage reservations');
select throws_ok($$select api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),clock_timestamp()+interval '1 day')$$,'22023','RESERVATION_ASOF_OUTSIDE_COVERAGE','future reservation report rejected');
select throws_ok($$update inventory.reservation_history set snapshot='{}'$$,'55000',null,'reservation history cannot be rewritten');
select ok(not has_table_privilege('authenticated','inventory.reservation_history','INSERT'),'clients cannot forge reservation history');
select is(jsonb_array_length(api.stock_reservation_queue(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->'items'),2,'active queue excludes released stock');
select ok((api.stock_reservation_history(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select id from release_before))->>'coverage_start') is not null,'history reports explicit coverage start');
-- Synthetic expiry and retirement are confined to this rollback fixture.
update inventory.stock_reservations set expires_at=clock_timestamp()-interval '1 second' where sales_order_line_id=pg_temp.fid('tracked.lot') and status='active';
select is(jsonb_array_length(api.stock_reservation_queue(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'expired')->'items'),1,'expiry queue uses server time');
select is(jsonb_array_length(api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),clock_timestamp())->'items'),2,'expiry alone does not silently rewrite held quantity');
select lives_ok($$select pg_temp.call('release_stock_reservation',jsonb_build_object('id',id,'mode','expired','reason','Expired reservation reviewed'),version) from inventory.stock_reservations where sales_order_line_id=pg_temp.fid('tracked.lot') and status='active'$$,'expired reservation releases through governed command');
update inventory.products set status='inactive' where id=pg_temp.fid('serial');
select lives_ok($$select pg_temp.call('release_stock_reservation',jsonb_build_object('id',id,'mode','retired','reason','Retired product reviewed'),version) from inventory.stock_reservations where sales_order_line_id=pg_temp.fid('tracked.serial') and status='active'$$,'retired product allocation releases through governed command');
-- Synthetic history volume verifies cursor boundaries, not contention or load.
do $$begin for i in 1..55 loop
 update inventory.stock_reservations set release_reason='History paging fixture '||i where id=(select id from release_before);
end loop;end$$;
create temporary table history_first_page as select api.stock_reservation_history(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select id from release_before)) result;
select is(jsonb_array_length((select result->'items' from history_first_page)),50,'history page is bounded to fifty versions');
select is((select (result->>'next_version')::bigint from history_first_page),(select (result#>>'{items,49,version}')::bigint from history_first_page),'history cursor pins the last returned version');
select ok(not exists(select 1 from jsonb_array_elements(api.stock_reservation_history(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select id from release_before),(select (result->>'next_version')::bigint from history_first_page))->'items')z
 where (z->>'version')::bigint >= (select (result->>'next_version')::bigint from history_first_page)),'older history page cannot duplicate the cursor version');
-- Model a reservation that existed before candidate installation. Trigger changes
-- and synthetic rows are contained by the outer rollback, never installed.
alter table inventory.stock_reservations disable trigger reservation_history_capture;
insert into inventory.stock_reservations select (jsonb_populate_record(null::inventory.stock_reservations,
 to_jsonb(r)||jsonb_build_object('id',pg_temp.fid('legacy.reservation'),'status','active','version',1,'released_at',null,'release_reason',null,
 'created_at',(select starts_at-interval '1 day' from inventory.reservation_history_coverage)))).*
 from inventory.stock_reservations r where r.id=(select id from release_before);
alter table inventory.stock_reservations enable trigger reservation_history_capture;
select ok(exists(select 1 from jsonb_array_elements(api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select instant from release_cutoff))->'items')z where z->>'id'=pg_temp.fid('legacy.reservation')::text),'untouched legacy reservation is known at the coverage baseline');
update inventory.stock_reservations set status='released',released_at=clock_timestamp(),release_reason='Legacy history fixture' where id=pg_temp.fid('legacy.reservation');
select is((select count(*) from inventory.reservation_history where reservation_id=pg_temp.fid('legacy.reservation') and baseline),1::bigint,'first legacy change preserves exactly one coverage baseline');
select ok(exists(select 1 from jsonb_array_elements(api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select instant from release_cutoff))->'items')z where z->>'id'=pg_temp.fid('legacy.reservation')::text),'legacy history preserves prior held quantity after release');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('foreign_actor'),'role','authenticated','aal','aal2')::text,true);
select set_config('request.jwt.claim.sub',pg_temp.fid('foreign_actor')::text,true);
select throws_ok($$select api.stock_reservation_history(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select id from release_before))$$,'42501',null,'foreign actor cannot read reservation history');
select throws_ok($$select pg_temp.call('release_stock_reservation',pg_temp.release_payload(),(select version from release_before),'foreign.release')$$,'42501',null,'foreign actor cannot release stock');
select throws_ok($$select api.stock_reservations_as_of(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),clock_timestamp())$$,'42501',null,'foreign actor cannot read dated allocation report');
