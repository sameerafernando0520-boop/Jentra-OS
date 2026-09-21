select pg_temp.actor('creator');
set constraints all deferred;
-- New real governed receipt avoids the earlier return/disposition cases.
update inventory.products set tracking_mode='none' where id=pg_temp.fid('product');
select pg_temp.call('upsert_purchase_requisition',jsonb_set(pg_temp.header('landed.req'),'{lines,0,product_id}',to_jsonb(pg_temp.fid('product'))));
select pg_temp.transition('landed.req','{"action":"submit"}');
select pg_temp.actor('approver');select pg_temp.transition('landed.req','{"decision":"approved"}');select pg_temp.actor('creator');
select pg_temp.call('upsert_purchase_order',pg_temp.direct_po()||jsonb_build_object('id',pg_temp.fid('landed.po'),'source_requisition_id',pg_temp.fid('landed.req'),
 'lines',jsonb_build_array((pg_temp.direct_po()#>'{lines,0}')||jsonb_build_object('line_id',pg_temp.fid('landed.po.line'),'source_line_id',pg_temp.fid('landed.req.line'),'unit_price','10'))));
select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('landed.po'),'action','submit'),1);
select pg_temp.actor('approver');select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('landed.po'),'decision','approved'),2);select pg_temp.actor('creator');
select pg_temp.call('post_goods_receipt',pg_temp.gr('landed.receipt','3','0')||jsonb_build_object('order_id',pg_temp.fid('landed.po'),'document_date','2026-09-19',
 'lines',jsonb_build_array((pg_temp.gr('landed.receipt','3','0')#>'{lines,0}')||jsonb_build_object('order_line_id',pg_temp.fid('landed.po.line')))),3);
create function pg_temp.landed_payload(n text default 'landed.adjust') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(n),'receipt_line_id',(select id from inventory.stock_movement_lines where source_line_id=pg_temp.fid('landed.receipt.line')),
 'amount','10.000001','document_date','2026-09-19','reference','FREIGHT-42','reason','Reclassify recorded freight cost',
 'offset_account_id',pg_temp.fid('expense-account'),'variance_account_id',pg_temp.fid('expense-account'))$$;
create function pg_temp.landed_preview(p jsonb) returns jsonb language sql as $$select api.preview_inventory_value_adjustment(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),p)$$;
create function pg_temp.landed_post(n text default 'landed.adjust') returns jsonb language sql as $$select pg_temp.call('post_inventory_value_adjustment',pg_temp.landed_payload(n)||jsonb_build_object('basis_hash',pg_temp.landed_preview(pg_temp.landed_payload(n))->>'basis_hash'),0,n)$$;
insert into procurement_test_results select is(pg_temp.landed_preview(pg_temp.landed_payload())->>'inventory_amount','10.000001','landed preview keeps exact six-decimal freight amount');
insert into procurement_test_results select throws_ok($$select pg_temp.landed_preview(pg_temp.landed_payload()||'{"amount":1.2}')$$,'22023',null,'landed value rejects floating JSON input');
insert into procurement_test_results select throws_ok($$select pg_temp.landed_preview(pg_temp.landed_payload()||'{"amount":"0"}')$$,'22023',null,'zero allocation amount rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_inventory_value_adjustment',pg_temp.landed_payload()||'{"basis_hash":"old"}',0)$$,'40001','LANDED_PREVIEW_CHANGED','stale allocation preview cannot post');
insert into procurement_responses values('landed.before',jsonb_build_object('quantity',(select on_hand_quantity::text from inventory.stock_balances where tenant_id=pg_temp.fid('tenant') and product_id=pg_temp.fid('product') and warehouse_id=pg_temp.fid('warehouse')),
 'value',(select carrying_value::text from inventory.stock_valuations where stock_balance_id=(select id from inventory.stock_balances where tenant_id=pg_temp.fid('tenant') and product_id=pg_temp.fid('product') and warehouse_id=pg_temp.fid('warehouse')))));
insert into procurement_responses values('landed.command',pg_temp.landed_payload()||jsonb_build_object('basis_hash',pg_temp.landed_preview(pg_temp.landed_payload())->>'basis_hash'));
create temporary table landed_sequences as select * from core.document_sequences where tenant_id=pg_temp.fid('tenant') and document_type='journal_entry';
delete from core.document_sequences where tenant_id=pg_temp.fid('tenant') and document_type='journal_entry';
insert into procurement_test_results select throws_ok($$select pg_temp.landed_post('landed.failed')$$,'55000',null,'late journal numbering failure rolls back landed posting');
insert into procurement_test_results select is((select carrying_value::text from inventory.stock_valuations where stock_balance_id=(select id from inventory.stock_balances where tenant_id=pg_temp.fid('tenant') and product_id=pg_temp.fid('product') and warehouse_id=pg_temp.fid('warehouse'))),
 (select response->>'value' from procurement_responses where name='landed.before'),'failed journal construction leaves valuation unchanged');
insert into core.document_sequences select * from landed_sequences;
insert into procurement_responses values('landed.result',pg_temp.call('post_inventory_value_adjustment',(select response from procurement_responses where name='landed.command'),0,'landed.adjust'));
insert into procurement_test_results select is(pg_temp.call('post_inventory_value_adjustment',(select response from procurement_responses where name='landed.command'),0,'landed.adjust'),(select response from procurement_responses where name='landed.result'),'landed replay retains the original posted evidence');
insert into procurement_test_results select is((select on_hand_quantity::text from inventory.stock_balances where tenant_id=pg_temp.fid('tenant') and product_id=pg_temp.fid('product') and warehouse_id=pg_temp.fid('warehouse')),
 (select response->>'quantity' from procurement_responses where name='landed.before'),'landed posting changes no historical or current quantity');
insert into procurement_test_results select is((select sum(base_value) from inventory.stock_movement_lines where source_line_id=pg_temp.fid('landed.adjust')),10.000001::numeric,'value-only stock ledger receives exact allocation');
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where source_line_id=pg_temp.fid('landed.adjust')),0::numeric,'landed journal uses balanced existing posting engine');
insert into procurement_test_results select throws_ok($$delete from inventory.value_adjustments where id=pg_temp.fid('landed.adjust')$$,'55000',null,'posted landed evidence is immutable');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('landed.receipt'),'document_date','2026-09-19','reason','Wrong receipt'),1)$$,'55000','REVERSE_LANDED_VALUE_FIRST','original-cost receipt reversal cannot strand landed value');
insert into procurement_responses values('landed.reverse',pg_temp.call('post_inventory_value_adjustment',jsonb_build_object('id',pg_temp.fid('landed.reverse'),'reverse_of',pg_temp.fid('landed.adjust'),
 'document_date','2026-09-19','reason','Freight attributed to wrong receipt','reference','CORR-42'),1,'landed.reverse'));
insert into procurement_test_results select is((select sum(base_value) from inventory.stock_movement_lines where source_line_id in(pg_temp.fid('landed.adjust'),pg_temp.fid('landed.reverse'))),0::numeric,'linked reversal restores original value exactly');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_inventory_value_adjustment',jsonb_build_object('id',gen_random_uuid(),'reverse_of',pg_temp.fid('landed.adjust'),'document_date','2026-09-19','reason','Again','reference','AGAIN'),1)$$,'40001','VERSION_CONFLICT','second landed reversal is blocked by expected version');
-- Rollback-only synthetic delivery isolates the exact partially consumed basis.
do $$declare q numeric;mid uuid:=gen_random_uuid();begin
 select sum(quantity)-2 into q from inventory.receipt_provenance_positions where tenant_id=pg_temp.fid('tenant') and warehouse_id=pg_temp.fid('warehouse') and product_id=pg_temp.fid('product') and lot_id is null and serial_id is null;
 update inventory.stock_balances set on_hand_quantity=on_hand_quantity-q where tenant_id=pg_temp.fid('tenant') and warehouse_id=pg_temp.fid('warehouse') and product_id=pg_temp.fid('product');
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(mid,pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'delivery',mid,pg_temp.fid('warehouse'),'2026-09-19','delivery',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),pg_temp.fid('creator'));
 insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,base_quantity,base_value,posting_date,created_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),mid,pg_temp.fid('warehouse'),pg_temp.fid('product'),gen_random_uuid(),-q,0,'2026-09-19',pg_temp.fid('creator'));
end $$;
insert into procurement_test_results select is(pg_temp.landed_preview(pg_temp.landed_payload())->>'inventory_amount','6.666667','partial consumption allocates exact remaining receipt share');
insert into procurement_test_results select is(pg_temp.landed_preview(pg_temp.landed_payload())->>'variance_amount','3.333334','consumed variance receives exact rounding remainder');
-- Real governed dispatch/completion across branches, within the rollback fixture.
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('trace.hiddenbranch'),'journal_entry','HIDDEN-JE',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,created_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('creator.role'),pg_temp.fid('entity'),pg_temp.fid('creator'));
create function pg_temp.landed_transfer(op text,ver bigint default null) returns jsonb language sql as $$select pg_temp.call('transfer_stock',jsonb_build_object(
 'id',pg_temp.fid('landed.transfer'),'operation',op,'document_date','2026-09-19','reason','Test landed attribution across branches','reference','LANDED-T1',
 'source_warehouse_id',pg_temp.fid('warehouse'),'destination_warehouse_id',pg_temp.fid('trace.hiddenwarehouse'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('landed.transfer.line'),'product_id',pg_temp.fid('product'),'unit_id',pg_temp.fid('unit'),
 'quantity','1','conversion_numerator','1','conversion_denominator','1','serial_ids','[]'::jsonb))),ver)$$;
select pg_temp.landed_transfer('dispatch');
insert into procurement_test_results select throws_ok($$select pg_temp.landed_preview(pg_temp.landed_payload())$$,'55000','LANDED_RECEIPT_IN_TRANSIT','in-transit value cannot be silently omitted from landed allocation');
select pg_temp.landed_transfer('receive',1);
-- An unrelated rollback-only receipt leaves stock after transfer reversal, exercising
-- the landed guard independently of the existing empty-warehouse value guard.
do $$declare mid uuid:=gen_random_uuid();begin
 update inventory.stock_balances set on_hand_quantity=on_hand_quantity+1 where tenant_id=pg_temp.fid('tenant') and warehouse_id=pg_temp.fid('trace.hiddenwarehouse') and product_id=pg_temp.fid('product');
 update inventory.stock_valuations set carrying_value=carrying_value+10 where stock_balance_id=(select id from inventory.stock_balances where tenant_id=pg_temp.fid('tenant') and warehouse_id=pg_temp.fid('trace.hiddenwarehouse') and product_id=pg_temp.fid('product'));
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(mid,pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('trace.hiddenbranch'),'goods_receipt',mid,pg_temp.fid('trace.hiddenwarehouse'),'2026-09-19','stock_adjustment',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),pg_temp.fid('creator'));
 insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,base_quantity,base_value,posting_date,created_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('trace.hiddenbranch'),mid,pg_temp.fid('trace.hiddenwarehouse'),pg_temp.fid('product'),gen_random_uuid(),1,10,'2026-09-19',pg_temp.fid('creator'));
end $$;
insert into procurement_test_results select is(jsonb_array_length(pg_temp.landed_preview(pg_temp.landed_payload())->'legs'),2,'completed transfer allocates across both warehouses');
create temporary table landed_missing_valuation as select v.* from inventory.stock_valuations v join inventory.stock_balances b on b.id=v.stock_balance_id
 where b.tenant_id=pg_temp.fid('tenant') and b.warehouse_id=pg_temp.fid('trace.hiddenwarehouse') and b.product_id=pg_temp.fid('product');
delete from inventory.stock_valuations where id in(select id from landed_missing_valuation);
insert into procurement_test_results select throws_ok($$select pg_temp.landed_preview(pg_temp.landed_payload())$$,'55000','LANDED_PROVENANCE_MISMATCH','missing valuation projection cannot misclassify held stock as consumed');
insert into inventory.stock_valuations select * from landed_missing_valuation;
insert into procurement_responses values('landed.multi.command',pg_temp.landed_payload('landed.multi')||jsonb_build_object('basis_hash',pg_temp.landed_preview(pg_temp.landed_payload('landed.multi'))->>'basis_hash'));
insert into procurement_responses values('landed.multi.result',pg_temp.call('post_inventory_value_adjustment',(select response from procurement_responses where name='landed.multi.command'),0,'landed.multi'));
insert into procurement_test_results select is((select sum(base_value) from inventory.stock_movement_lines where source_line_id=pg_temp.fid('landed.multi')),6.666667::numeric,'multi-warehouse cumulative rounding conserves exact inventory share');
insert into procurement_test_results select is((select count(distinct journal_entry_id) from finance.journal_lines where source_line_id=pg_temp.fid('landed.multi')),3::bigint,'two warehouses and consumed variance have separate balanced journals');
insert into procurement_test_results select throws_ok($$select pg_temp.landed_transfer('reverse',2)$$,'55000','TRANSFER_VALUE_CHANGED','frozen-cost transfer reversal cannot strand later landed value');
delete from core.role_assignments where tenant_id=pg_temp.fid('tenant') and membership_id=pg_temp.fid('creator.membership') and branch_id is null;
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_inventory_value_adjustment',(select response from procurement_responses where name='landed.multi.command'),0,'landed.multi')$$,'42501',null,'landed replay rechecks every affected branch');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(api.inventory_value_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'posted')->'items') x where x->>'id'=pg_temp.fid('landed.multi')::text),'posted register hides complete cross-branch detail after revocation');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,created_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('creator.role'),pg_temp.fid('entity'),pg_temp.fid('creator'));
select pg_temp.call('post_inventory_value_adjustment',jsonb_build_object('id',pg_temp.fid('landed.multi.reverse'),'reverse_of',pg_temp.fid('landed.multi'),
 'document_date','2026-09-19','reason','Undo landed value before reversing transfer','reference','CORR-MULTI'),1);
insert into procurement_test_results select lives_ok($$select pg_temp.landed_transfer('reverse',2)$$,'transfer can reverse after linked landed correction');
select pg_temp.landed_post('landed.second');
-- Privileged synthetic valuation drift remains inside outer rollback.
update inventory.stock_valuations set carrying_value=carrying_value+1 where stock_balance_id=(select id from inventory.stock_balances where tenant_id=pg_temp.fid('tenant') and product_id=pg_temp.fid('product') and warehouse_id=pg_temp.fid('warehouse'));
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_inventory_value_adjustment',jsonb_build_object('id',gen_random_uuid(),'reverse_of',pg_temp.fid('landed.second'),'document_date','2026-09-19','reason','After stock change','reference','CORR-43'),1)$$,'55000','LANDED_REVERSAL_STOCK_CHANGED','intervening valuation prevents unsafe exact reversal');
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.landed_preview(pg_temp.landed_payload())$$,'42501',null,'landed preview enforces privileged MFA scope');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$insert into inventory.value_adjustments(id) values(gen_random_uuid())$$,'42501',null,'authenticated direct landed writes denied');
reset role;
insert into procurement_test_results select lives_ok('set constraints all immediate','landed stock and journal deferred constraints balance');
