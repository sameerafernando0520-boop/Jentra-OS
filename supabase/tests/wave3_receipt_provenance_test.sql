-- Privileged synthetic fixtures are inside the builder's mandatory outer rollback.
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),x from unnest(array['inventory.valuation.post','inventory.cost.view','inventory.transfers.post'])x on conflict do nothing;
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,inventory_account_id,created_by,updated_by)
 values(pg_temp.fid('trace.product'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'TRACE','Trace paper','stocked',pg_temp.fid('unit'),'none',pg_temp.fid('inventory-account'),pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
 values(pg_temp.fid('trace.balance'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('trace.product'),0,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('trace.balance'),0,pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.trace_move(n text,q numeric,kind text default 'goods_receipt',original text default null,prefix text default 'trace') returns void language plpgsql as $$begin
 update inventory.stock_balances set on_hand_quantity=on_hand_quantity+q where id=pg_temp.fid(prefix||'.balance');
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid(n||'.movement'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),kind,pg_temp.fid(n),pg_temp.fid('warehouse'),'2026-09-19','stock_adjustment',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),pg_temp.fid('creator'));
 insert into inventory.stock_movement_lines(id,tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,original_movement_line_id,base_quantity,base_value,posting_date,created_by)
 values(pg_temp.fid(n||'.ml'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid(n||'.movement'),pg_temp.fid('warehouse'),pg_temp.fid(prefix||'.product'),pg_temp.fid(n||'.source'),pg_temp.fid(original||'.ml'),q,0,'2026-09-19',pg_temp.fid('creator'));
end $$;
create function pg_temp.trace(n text) returns jsonb language sql as $$select api.receipt_trace_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid(n||'.ml'))$$;
insert into procurement_test_results select is((select sum(p.quantity) from inventory.receipt_provenance_positions p join inventory.stock_movement_lines ml on ml.id=p.origin_line_id
 where ml.source_line_id=pg_temp.fid('serial-return-receipt.line')),2::numeric,'supplier serial return leaves exactly the two original receipt identities');
insert into procurement_test_results select is((select sum(p.quantity) from inventory.receipt_provenance_positions p join inventory.stock_movement_lines ml on ml.id=p.origin_line_id
 where ml.source_line_id=pg_temp.fid('lot-receipt.line')),0.6::numeric,'lot receipt attribution agrees with the original lot after a supplier return');
select pg_temp.trace_move('trace.first',10);
select pg_temp.trace_move('trace.second',5);
select pg_temp.trace_move('trace.issue',-12,'delivery');
insert into procurement_test_results select is(pg_temp.trace('trace.first')->>'held_quantity','0.000000','oldest receipt cohort consumed first without changing weighted-average cost');
insert into procurement_test_results select is(pg_temp.trace('trace.second')->>'held_quantity','3.000000','mixed receipt provenance retains only the second receipt remainder');
select pg_temp.trace_move('trace.return',5,'sales_return','trace.issue');
insert into procurement_test_results select is(pg_temp.trace('trace.first')->>'held_quantity','5.000000','partial customer return restores exact original issue cohort');
select pg_temp.trace_move('trace.return2',7,'sales_return','trace.issue');
insert into procurement_test_results select is(pg_temp.trace('trace.second')->>'held_quantity','5.000000','final customer return restores the other cohort exactly');
insert into procurement_test_results select throws_ok($$select pg_temp.trace_move('trace.overrestore',1,'sales_return','trace.issue')$$,'55000','PROVENANCE_RESTORE_EXCEEDS_SOURCE','original issue cannot be restored twice');
insert into procurement_test_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('trace.balance')),15::numeric,'failed restoration rolls back stock and movement together');
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
 values(pg_temp.fid('trace.destination'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'Trace destination','TRACE-DEST',pg_temp.fid('creator'));
create function pg_temp.trace_transfer(op text,ver bigint default null) returns jsonb language sql as $$select pg_temp.call('transfer_stock',jsonb_build_object(
 'id',pg_temp.fid('trace.transfer'),'operation',op,'document_date','2026-09-19','reason','Traceability transfer test','reference','TRACE-T1',
 'source_warehouse_id',pg_temp.fid('warehouse'),'destination_warehouse_id',pg_temp.fid('trace.destination'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('trace.transfer.line'),'product_id',pg_temp.fid('trace.product'),'unit_id',pg_temp.fid('unit'),
 'quantity','2','conversion_numerator','1','conversion_denominator','1','serial_ids','[]'::jsonb))),ver)$$;
select pg_temp.trace_transfer('dispatch');
insert into procurement_test_results select is(pg_temp.trace('trace.second')->>'in_transit_quantity','2.000000','transfer dispatch preserves receipt identity in transit');
select pg_temp.trace_transfer('receive',1);
insert into procurement_test_results select is(pg_temp.trace('trace.second')->>'in_transit_quantity','0.000000','receipt completion clears attributable transit');
insert into procurement_test_results select is(jsonb_array_length(pg_temp.trace('trace.second')->'holdings'),2,'receipt has exact holdings across both warehouses');
select pg_temp.trace_transfer('reverse',2);
insert into procurement_test_results select is(jsonb_array_length(pg_temp.trace('trace.second')->'holdings'),1,'completed transfer reversal restores source attribution');
insert into procurement_test_results select is(pg_temp.trace('trace.second')->>'held_quantity','5.000000','completed transfer reversal conserves original receipt quantity');
insert into procurement_test_results select throws_ok($$delete from inventory.receipt_provenance_entries where origin_line_id=pg_temp.fid('trace.first.ml')$$,'55000',null,'quantity attribution history is immutable');
-- History is paged by numeric sequence, not lexicographic decimal strings.
do $$begin for i in 1..26 loop
 perform pg_temp.trace_move('trace.page.issue.'||i,-0.000001,'delivery');
 perform pg_temp.trace_move('trace.page.return.'||i,0.000001,'sales_return','trace.page.issue.'||i);
end loop;end $$;
insert into procurement_test_results select is(jsonb_array_length(pg_temp.trace('trace.second')->'items'),50,'receipt history is bounded to fifty events');
insert into procurement_test_results select ok(pg_temp.trace('trace.second')->>'next_cursor' is not null,'receipt history exposes an independent continuation cursor');
insert into procurement_test_results select throws_ok($$select api.receipt_trace_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),null,pg_temp.fid('trace.first.ml'))$$,'42501',null,'missing branch cannot broaden trace access');
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,created_by,updated_by)
 values(pg_temp.fid('legacy.product'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'LEGACY','Older stock','stocked',pg_temp.fid('unit'),'none',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
 values(pg_temp.fid('legacy.balance'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('legacy.product'),0,pg_temp.fid('creator'),pg_temp.fid('creator'));
-- Model pre-installation history only inside this rollback fixture.
alter table inventory.stock_movement_lines disable trigger receipt_provenance;
select pg_temp.trace_move('legacy.old',10,'goods_receipt',null,'legacy');
alter table inventory.stock_movement_lines enable trigger receipt_provenance;
insert into procurement_test_results select is(pg_temp.trace('legacy.old')->>'held_quantity',null::text,'historical receipt cannot claim current aggregate stock');
select pg_temp.trace_move('legacy.new',2,'goods_receipt',null,'legacy');
insert into procurement_test_results select is((select sum(quantity) from inventory.receipt_provenance_positions where product_id=pg_temp.fid('legacy.product') and origin_line_id is null),10::numeric,'pre-coverage stock captures an explicitly unknown baseline');
select pg_temp.trace_move('legacy.issue',-5,'delivery',null,'legacy');
insert into procurement_test_results select is(pg_temp.trace('legacy.new')->>'held_quantity','2.000000','older unknown stock is consumed before new known receipts');
update inventory.stock_balances set on_hand_quantity=on_hand_quantity+1 where id=pg_temp.fid('legacy.balance');
insert into procurement_test_results select throws_ok($$select pg_temp.trace_move('legacy.drift',-1,'delivery',null,'legacy')$$,'55000','PROVENANCE_STOCK_MISMATCH','projection drift blocks instead of inventing receipt attribution');
update inventory.stock_balances set on_hand_quantity=on_hand_quantity-1 where id=pg_temp.fid('legacy.balance');
insert into procurement_test_results select is((select count(*) from inventory.stock_movements where id=pg_temp.fid('legacy.drift.movement')),0::bigint,'drift rejection rolls back the entire attempted movement');
-- Partial scope revocation must deny complete detail rather than hide affected rows.
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
 values(pg_temp.fid('trace.hiddenbranch'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'Restricted trace branch','TRACE-HIDDEN',pg_temp.fid('creator'));
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
 values(pg_temp.fid('trace.hiddenwarehouse'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('trace.hiddenbranch'),'Restricted warehouse','TRACE-RESTRICTED',pg_temp.fid('creator'));
select pg_temp.call('transfer_stock',jsonb_build_object('id',pg_temp.fid('trace.hidden.transfer'),'operation','immediate','document_date','2026-09-19',
 'reason','Verify affected-branch access','reference','TRACE-SCOPE','source_warehouse_id',pg_temp.fid('warehouse'),'destination_warehouse_id',pg_temp.fid('trace.hiddenwarehouse'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('trace.hidden.line'),'product_id',pg_temp.fid('trace.product'),'unit_id',pg_temp.fid('unit'),
 'quantity','15','conversion_numerator','1','conversion_denominator','1','serial_ids','[]'::jsonb))));
delete from core.role_assignments where tenant_id=pg_temp.fid('tenant') and membership_id=pg_temp.fid('creator.membership') and branch_id is null;
insert into procurement_test_results select throws_ok($$select pg_temp.trace('trace.first')$$,'42501','RECEIPT_TRACE_BRANCH_SCOPE_REQUIRED','out-of-scope history denies all receipt totals');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select pg_temp.trace('trace.first')$$,'42501',null,'nonmember cannot inspect receipt quantities');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from inventory.receipt_provenance_positions$$,'42501',null,'authenticated clients cannot directly read private provenance positions');
reset role;

