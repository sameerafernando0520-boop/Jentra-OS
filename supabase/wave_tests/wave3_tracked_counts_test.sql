-- Included only inside the rollback-only inventory fixture, after ordinary counts.
set constraints all deferred;
select pg_temp.actor('actor');
create function pg_temp.tracked_payload(n text,p text) returns jsonb language sql as $$
 select jsonb_set(pg_temp.count_payload(n,'0'),'{lines,0,product_id}',to_jsonb(pg_temp.fid(p)))||'{"capture_only":true}'$$;
create function pg_temp.saved_count(n text) returns jsonb language sql as $$
 select to_jsonb(c) from inventory.stock_counts c where id=pg_temp.fid(n)$$;
create function pg_temp.approve_count(n text) returns void language plpgsql as $$begin
 perform pg_temp.actor('actor');
 perform pg_temp.count_call('transition_stock_count',pg_temp.count_action('submit',n),pg_temp.count_version(n));
 perform pg_temp.actor('approver');
 perform pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid(n),'decision','approved'),pg_temp.count_version(n));
 perform pg_temp.actor('actor');
end $$;
select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('lot-count','lot'));
insert into transfer_results select is((select (lines->0->'identities'->0->>'baseline_quantity')::numeric from inventory.stock_counts where id=pg_temp.fid('lot-count')),5::numeric,'lot cutoff captures original warehouse lot quantity');
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('lot-count'),'{lines,0,identities,0,counted_quantity}','"3"'),1);
insert into transfer_results select is((select (lines->0->>'counted_quantity')::numeric from inventory.stock_counts where id=pg_temp.fid('lot-count')),3::numeric,'lot identities determine aggregate quantity');
select pg_temp.approve_count('lot-count');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','lot-count'),pg_temp.count_version('lot-count'));
insert into transfer_results select is((select on_hand_quantity from inventory.lot_balances where warehouse_id=pg_temp.fid('w') and lot_id=pg_temp.fid('lot.id')),3::numeric,'approved lot shortage updates original lot');
insert into transfer_results select is((select lot_id from inventory.stock_movement_lines ml join inventory.stock_movements m on m.id=ml.stock_movement_id where m.source_id=pg_temp.fid('lot-count')),pg_temp.fid('lot.id'),'count movement preserves lot identity');
select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('serial-count','serial'));
insert into transfer_results select is((select jsonb_array_length(lines->0->'identities') from inventory.stock_counts where id=pg_temp.fid('serial-count')),7,'serial cutoff lists every warehouse identity');
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('serial-count'),'{lines,0,identities,0,counted_quantity}','"0"'),1);
select pg_temp.approve_count('serial-count');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','serial-count'),pg_temp.count_version('serial-count'));
insert into transfer_results select is((select count(*) from inventory.serials where tenant_id=pg_temp.fid('t') and status='count_missing'),1::bigint,'missing serial is excluded from availability');
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('serial.bal')),6::numeric,'serial absence changes stock by exactly one');
select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('serial-restore','serial')||jsonb_build_object('corrects_count_id',pg_temp.fid('serial-count')));
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('serial-restore'),'{lines,0,identities,0,counted_quantity}','"1"'),1);
select pg_temp.approve_count('serial-restore');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','serial-restore'),pg_temp.count_version('serial-restore'));
insert into transfer_results select is((select count(*) from inventory.serials where tenant_id=pg_temp.fid('t') and status='available'),10::bigint,'linked approved recount restores the same serial');
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('serial.bal')),7::numeric,'serial restoration conserves exact stock');
-- Identity edits cannot replace the server's snapshot or resurrect moved stock.
select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('serial-guard','serial'));
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('serial-guard'),'{lines,0,identities,0,id}',to_jsonb(pg_temp.fid('foreign-serial'))),1)$$,'22023','COUNT_IDENTITIES_IMMUTABLE','unknown serial cannot replace a captured identity');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('serial-guard'),'{lines,0,identities,0,counted_quantity}','"0.5"'),1)$$,'22023','COUNT_SERIAL_PRESENCE_REQUIRED','serial counts reject fractional presence');
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('serial-guard'),'{lines,0,identities,0,counted_quantity}','"0"'),1);
select pg_temp.approve_count('serial-guard');
update inventory.serials set status='quarantine' where id=(pg_temp.saved_count('serial-guard')#>>'{lines,0,identities,0,id}')::uuid;
insert into transfer_results select throws_ok($$select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','serial-guard'),pg_temp.count_version('serial-guard'))$$,'55000','COUNT_SERIAL_CHANGED','changed serial cannot post using stale approval');
select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('quarantine-loss','serial'));
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('quarantine-loss'),'{lines,0,identities,0,counted_quantity}','"0"'),1);
select pg_temp.approve_count('quarantine-loss');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','quarantine-loss'),pg_temp.count_version('quarantine-loss'));
insert into transfer_results select is((select count_previous_status from inventory.serials where status='count_missing' and tenant_id=pg_temp.fid('t')),'quarantine','missing serial retains quarantine disposition');
insert into transfer_results select throws_ok($$select pg_temp.call(jsonb_set(pg_temp.payload('missing-issue','dispatch','serial','1'),'{lines,0,serial_ids}',jsonb_build_array((pg_temp.saved_count('quarantine-loss')#>>'{lines,0,identities,0,id}')::uuid))||jsonb_build_object('document_date',(clock_timestamp() at time zone 'UTC')::date))$$,'55000','TRANSFER_SERIAL_UNAVAILABLE','missing serial cannot be dispatched');
select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('quarantine-restore','serial')||jsonb_build_object('corrects_count_id',pg_temp.fid('quarantine-loss')));
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('quarantine-restore'),'{lines,0,identities,0,counted_quantity}','"1"'),1);
select pg_temp.approve_count('quarantine-restore');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','quarantine-restore'),pg_temp.count_version('quarantine-restore'));
insert into transfer_results select is((select status from inventory.serials where id=(pg_temp.saved_count('quarantine-restore')#>>'{lines,0,identities,0,id}')::uuid),'quarantine','restoring missing stock does not make quarantined stock saleable');
insert into inventory.lots(id,tenant_id,legal_entity_id,product_id,code,created_by,updated_by)
values(pg_temp.fid('lot.second'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('lot'),'LOT-2',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
values(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid('lot'),pg_temp.fid('lot.second'),0,pg_temp.fid('actor'),pg_temp.fid('actor'));
select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('lot-redistribute','lot'));
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.saved_count('lot-redistribute'),'{lines,0,identities}',
 (select jsonb_agg(z||jsonb_build_object('counted_quantity',case when z->>'id'=pg_temp.fid('lot.id')::text then '1' else '2' end)) from jsonb_array_elements(pg_temp.saved_count('lot-redistribute')#>'{lines,0,identities}')z)),1);
insert into transfer_results select ok((select grand_total>0 and (lines->0->>'variance_quantity')::numeric=0 from inventory.stock_counts where id=pg_temp.fid('lot-redistribute')),'offsetting lot deltas retain a nonzero approval basis');
select pg_temp.approve_count('lot-redistribute');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','lot-redistribute'),pg_temp.count_version('lot-redistribute'));
insert into transfer_results select is((select on_hand_quantity from inventory.lot_balances where warehouse_id=pg_temp.fid('w') and lot_id=pg_temp.fid('lot.second')),2::numeric,'net-zero product count still posts identity redistribution');
insert into transfer_results select is((select sum(base_value) from inventory.stock_movement_lines ml join inventory.stock_movements m on m.id=ml.stock_movement_id where m.source_id=pg_temp.fid('lot-redistribute')),0::numeric,'identity cumulative rounding conserves exact product value');
set constraints all immediate;
insert into transfer_results select ok(not (api.stock_counts_page(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'))->'items'->0 ? 'lines'),'register pages omit identity detail');
insert into transfer_results select ok(api.stock_count_detail(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('serial-count')) ? 'lines','scoped detail retains count identities');
insert into transfer_results select throws_ok($$select api.stock_count_detail(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2'),pg_temp.fid('serial-count'))$$,'P0002','DOCUMENT_NOT_FOUND','detail cannot cross branch boundary');
-- Limit boundary: no prefix of a large identity set can silently become a cutoff.
insert into inventory.serials(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,code,created_by,updated_by)
select pg_temp.fid('limit.serial.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid('serial'),'LIMIT-'||x,pg_temp.fid('actor'),pg_temp.fid('actor')
from generate_series(1,500-(select count(*)::integer from inventory.serials where tenant_id=pg_temp.fid('t') and warehouse_id=pg_temp.fid('w') and product_id=pg_temp.fid('serial') and status in('available','quarantine','count_missing')))x;
insert into transfer_results select is(jsonb_array_length(inventory.count_identities(pg_temp.fid('t'),pg_temp.fid('w'),pg_temp.fid('serial'),'serial',null,null)),500,'500 captured identities are accepted in full');
insert into inventory.serials(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,code,created_by,updated_by)
values(pg_temp.fid('limit.serial.excess'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid('serial'),'LIMIT-EXCESS',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',pg_temp.tracked_payload('too-many-identities','serial'))$$,'22023','COUNT_IDENTITY_LIMIT','501 identities reject capture without truncation');
insert into transfer_results select is((select count(*) from inventory.stock_counts where id=pg_temp.fid('too-many-identities')),0::bigint,'oversized identity rejection leaves no partial count');
