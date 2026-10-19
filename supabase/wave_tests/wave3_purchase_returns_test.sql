-- Appended to the rollback-only procurement fixture. No persistent business writes.
set constraints all deferred;
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'procurement.returns.post');
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'purchase_return','RTTEST-',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.purchase_return(p_name text,p_source text,p_line text,p_quantity text,p_kind text default 'bill') returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fid(p_name),'source_kind',p_kind,'source_id',pg_temp.fid(p_source),
 'document_date','2026-09-15','reason','Supplier accepted the partial return','reference','RET-'||p_name,
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(p_name||'.line'),'source_line_id',pg_temp.fid(p_line),'quantity',p_quantity,'serial_ids','[]'::jsonb)))$$;
insert into procurement_test_results select has_function('api','post_purchase_return',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-312 purchase return command exists');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('excess','bill','bill.line','0.450001'))$$,'22023','RETURN_QUANTITY_UNAVAILABLE','return cannot exceed eligible original billed quantity');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',jsonb_set(pg_temp.purchase_return('number-return','bill','bill.line','0.1'),'{lines,0,quantity}','0.1'))$$,'22023',null,'return quantity rejects JSON numbers');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('wrong-line','bill','direct-bill.line','0.1'))$$,'22023','RETURN_SOURCE_LINE_INVALID','return source line must belong to selected scoped bill');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('no-reason','bill','bill.line','0.1')||'{"reason":" "}')$$,'22023','RETURN_INPUT_INVALID','return requires accountable reason');
insert into procurement_responses values('purchase-return',pg_temp.call('post_purchase_return',pg_temp.purchase_return('purchase-return','bill','bill.line','0.15'),null,'purchase-return'));
insert into procurement_test_results select is(pg_temp.call('post_purchase_return',pg_temp.purchase_return('purchase-return','bill','bill.line','0.15'),null,'purchase-return'),(select response from procurement_responses where name='purchase-return'),'return retry replays identical response');
insert into procurement_test_results select is((select original_amount::text from finance.open_items where source_id=pg_temp.fid('purchase-return')),'-16.670000','partial billed return creates exact supplier credit');
insert into procurement_test_results select is((select on_hand_quantity::text from inventory.stock_balances where tenant_id=pg_temp.fid('tenant')),'4.800000','purchase return issues frozen twelve-unit stock quantity exactly once');
insert into procurement_test_results select is((select received_quantity::text from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'0.550000','return preserves original received quantity history');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('second-excess','bill','bill.line','0.31'))$$,'22023','RETURN_QUANTITY_UNAVAILABLE','posted return reduces subsequent eligibility');
insert into procurement_test_results select throws_ok($$update procurement.purchase_returns set reason='rewrite' where id=pg_temp.fid('purchase-return')$$,'55000',null,'posted return header immutable');
insert into procurement_test_results select lives_ok('set constraints all immediate','stock return AP journal and movement invariants balance together');
set constraints all deferred;
-- Direct service debit notes reverse tax without a stock movement.
select pg_temp.call('post_purchase_return',pg_temp.purchase_return('service-return','direct-bill','direct-bill.line','1'));
insert into procurement_test_results select is((select original_amount::text from finance.open_items where source_id=pg_temp.fid('service-return')),'-147.660000','direct debit note uses cumulative net and tax rounding');
insert into procurement_test_results select is((select stock_movement_id from procurement.purchase_returns where id=pg_temp.fid('service-return')),null::uuid,'nonstock debit does not create stock');
select pg_temp.call('post_purchase_return',pg_temp.purchase_return('service-rest','direct-bill','direct-bill.line','1'));
insert into procurement_test_results select is((select sum(total)::text from procurement.purchase_returns where source_id=pg_temp.fid('direct-bill')),'295.300000','complete partial returns exhaust original bill total without a lost cent');
insert into procurement_test_results select is((select sum(base_credit)::text from finance.journal_lines where account_id=pg_temp.fid('input-tax-account') and journal_entry_id in(select journal_entry_id from procurement.purchase_returns where source_id=pg_temp.fid('direct-bill'))),'45.050000','complete debit notes reverse original input tax exactly');
select pg_temp.actor('approver');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('denied-return','bill','bill.line','0.1'))$$,'42501',null,'separate return permission required');
set local role authenticated;
insert into procurement_test_results select is((select count(*)::integer from api.purchase_returns where tenant_id=pg_temp.fid('tenant')),0,'bill reader cannot read return register without return permission');
insert into procurement_test_results select throws_ok($$delete from procurement.purchase_returns$$,'42501',null,'authenticated direct return write denied');
reset role;select pg_temp.actor('creator');
insert into procurement_test_results select lives_ok('set constraints all immediate','debit note posting preserves all deferred invariants');
set constraints all deferred;
insert into procurement_test_results select is(api.purchase_return_source(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'bill',pg_temp.fid('bill'))#>>'{lines,0,eligible_quantity}','0.300000','source detail shows exact remaining return eligibility');
insert into procurement_test_results select ok(jsonb_array_length(api.purchase_return_sources(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'bill')->'items')>0,'return source picker exposes eligible scoped bills');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('purchase-return','bill','bill.line','0.2'),null,'purchase-return')$$,'22023',null,'changed-body replay cannot change a posted return');
update inventory.stock_balances set allocated_quantity=on_hand_quantity where tenant_id=pg_temp.fid('tenant');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('reserved-return','bill','bill.line','0.1'))$$,'55000','RETURN_STOCK_UNAVAILABLE','return cannot consume reserved stock');
update inventory.stock_balances set allocated_quantity=0 where tenant_id=pg_temp.fid('tenant');
insert into procurement_test_results select is((select count(*)::integer from procurement.purchase_returns where id=pg_temp.fid('reserved-return')),0,'failed return creates no partial header');
-- New synthetic requisition/PO/receipt tests unbilled returns and later matching.
select pg_temp.call('upsert_purchase_requisition',jsonb_set(pg_temp.header('return-req'),'{lines,0,product_id}',to_jsonb(pg_temp.fid('product'))));
select pg_temp.transition('return-req','{"action":"submit"}');
select pg_temp.actor('approver');select pg_temp.transition('return-req','{"decision":"approved"}');select pg_temp.actor('creator');
select pg_temp.call('upsert_purchase_order',pg_temp.direct_po()||jsonb_build_object('id',pg_temp.fid('return-po'),'source_requisition_id',pg_temp.fid('return-req'),
 'lines',jsonb_build_array((pg_temp.direct_po()#>'{lines,0}')||jsonb_build_object('line_id',pg_temp.fid('return-po.line'),'source_line_id',pg_temp.fid('return-req.line'),'unit_price','10'))));
select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('return-po'),'action','submit'),1);
select pg_temp.actor('approver');select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('return-po'),'decision','approved'),2);select pg_temp.actor('creator');
select pg_temp.call('post_goods_receipt',pg_temp.gr('unbilled-receipt','3','0')||jsonb_build_object('order_id',pg_temp.fid('return-po'),'document_date','2026-09-15',
 'lines',jsonb_build_array((pg_temp.gr('unbilled-receipt','3','0')#>'{lines,0}')||jsonb_build_object('order_line_id',pg_temp.fid('return-po.line')))),3);
select pg_temp.call('post_purchase_return',pg_temp.purchase_return('unbilled-return','unbilled-receipt','unbilled-receipt.line','1','receipt'));
insert into procurement_test_results select is((select open_item_id from procurement.purchase_returns where id=pg_temp.fid('unbilled-return')),null::uuid,'unbilled return creates no AP or premature tax');
insert into procurement_test_results select is((select sum(base_debit)::text from finance.journal_lines where journal_entry_id=(select journal_entry_id from procurement.purchase_returns where id=pg_temp.fid('unbilled-return')) and account_id=pg_temp.fid('grni-account')),'10.000000','unbilled return reverses original GRNI share');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('unbilled-receipt'),'document_date','2026-09-15','reason','Duplicate reversal'),1)$$,'55000','RETURNED_RECEIPT_CANNOT_REVERSE','returned receipt cannot reverse its stock twice');
create function pg_temp.remaining_bill(p_name text,p_quantity text) returns jsonb language sql as $$select pg_temp.direct_bill(p_name)||jsonb_build_object('document_date','2026-09-15','due_date','2026-09-30',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(p_name||'.line'),'receipt_line_id',pg_temp.fid('unbilled-receipt.line'),
 'quantity',p_quantity,'unit_price','10','discount_percent','0','tax_definition_id',null)))$$;
select pg_temp.call('upsert_supplier_bill',pg_temp.remaining_bill('over-return-bill','3'));
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('over-return-bill')),1)$$,'55000','RECEIPT_QUANTITY_UNAVAILABLE','matching excludes goods already returned unbilled');
select pg_temp.call('upsert_supplier_bill',pg_temp.remaining_bill('remaining-return-bill','2'));
select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('remaining-return-bill')),1);
insert into procurement_test_results select is((select original_amount::text from finance.open_items where source_id=pg_temp.fid('remaining-return-bill')),'20.000000','remaining accepted quantity bills without cumulative rounding drift');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('double-unbilled','unbilled-receipt','unbilled-receipt.line','1','receipt'))$$,'22023','RETURN_QUANTITY_UNAVAILABLE','billed remainder cannot use unbilled return path');
insert into procurement_test_results select lives_ok('set constraints all immediate','unbilled return and later bill retain stock GRNI and AP invariants');
set constraints all deferred;
insert into procurement_responses values('before-failed-return',jsonb_build_object('stock',(select on_hand_quantity::text from inventory.stock_balances where tenant_id=pg_temp.fid('tenant')),
 'value',(select carrying_value::text from inventory.stock_valuations where tenant_id=pg_temp.fid('tenant')),'journals',(select count(*) from finance.journal_entries where tenant_id=pg_temp.fid('tenant'))));
delete from core.document_sequences where tenant_id=pg_temp.fid('tenant') and document_type='purchase_return';
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('late-failure','bill','bill.line','0.1'))$$,'55000',null,'missing return numbering rolls back after stock and journal construction');
insert into procurement_test_results select is(jsonb_build_object('stock',(select on_hand_quantity::text from inventory.stock_balances where tenant_id=pg_temp.fid('tenant')),
 'value',(select carrying_value::text from inventory.stock_valuations where tenant_id=pg_temp.fid('tenant')),'journals',(select count(*) from finance.journal_entries where tenant_id=pg_temp.fid('tenant'))),
 (select response from procurement_responses where name='before-failed-return'),'late failure leaves stock carrying value and journal count unchanged');
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'purchase_return','RT2TEST-',pg_temp.fid('creator'),pg_temp.fid('creator'));
-- Expired stock may be returned to its supplier while remaining unsaleable.
update inventory.lots set expiry_date='2026-09-14' where tenant_id=pg_temp.fid('tenant');
select pg_temp.call('post_purchase_return',pg_temp.purchase_return('lot-return','lot-bill','lot-bill.line','0.05'));
insert into procurement_test_results select is((select on_hand_quantity::text from inventory.lot_balances where tenant_id=pg_temp.fid('tenant')),'0.600000','supplier return consumes original expired lot without making it saleable');
insert into procurement_test_results select is((select detail->>'lot_id' from procurement.purchase_return_lines where return_id=pg_temp.fid('lot-return')),
 (select detail->>'lot_id' from procurement.goods_receipt_lines where id=pg_temp.fid('lot-receipt.line')),'lot return retains original receipt identity');
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('weak-auth-return','bill','bill.line','0.1'))$$,'42501',null,'return posting enforces privileged MFA role');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.purchase_return_source(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'bill',pg_temp.fid('bill'))$$,'42501',null,'known source ID cannot bypass return scope');
select pg_temp.actor('creator');
insert into procurement_test_results select lives_ok('set constraints all immediate','return review additions retain deferred invariants');
set constraints all deferred;
update inventory.products set tracking_mode='serial' where id=pg_temp.fid('product');
select pg_temp.call('upsert_purchase_requisition',jsonb_set(pg_temp.header('serial-return-req'),'{lines,0,product_id}',to_jsonb(pg_temp.fid('product'))));
select pg_temp.transition('serial-return-req','{"action":"submit"}');
select pg_temp.actor('approver');select pg_temp.transition('serial-return-req','{"decision":"approved"}');select pg_temp.actor('creator');
select pg_temp.call('upsert_purchase_order',pg_temp.direct_po()||jsonb_build_object('id',pg_temp.fid('serial-return-po'),'source_requisition_id',pg_temp.fid('serial-return-req'),
 'lines',jsonb_build_array((pg_temp.direct_po()#>'{lines,0}')||jsonb_build_object('line_id',pg_temp.fid('serial-return-po.line'),'source_line_id',pg_temp.fid('serial-return-req.line'),'unit_price','10'))));
select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('serial-return-po'),'action','submit'),1);
select pg_temp.actor('approver');select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('serial-return-po'),'decision','approved'),2);select pg_temp.actor('creator');
select pg_temp.call('post_goods_receipt',pg_temp.gr('serial-return-receipt','3','0')||jsonb_build_object('order_id',pg_temp.fid('serial-return-po'),'document_date','2026-09-15',
 'lines',jsonb_build_array((pg_temp.gr('serial-return-receipt','3','0')#>'{lines,0}')||jsonb_build_object('order_line_id',pg_temp.fid('serial-return-po.line'),'serial_codes',jsonb_build_array('RETURN-S1','RETURN-S2','RETURN-S3')))),3);
create function pg_temp.serial_return(p_name text) returns jsonb language sql as $$select jsonb_set(pg_temp.purchase_return(p_name,'serial-return-receipt','serial-return-receipt.line','1','receipt'),
 '{lines,0,serial_ids}',jsonb_build_array((select id from inventory.serials where tenant_id=pg_temp.fid('tenant') and code='RETURN-S1')))$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.purchase_return('no-return-serial','serial-return-receipt','serial-return-receipt.line','1','receipt'))$$,'22023','RETURN_SERIAL_INVALID','tracked return requires original serial selection');
select pg_temp.call('post_purchase_return',pg_temp.serial_return('serial-purchase-return'));
insert into procurement_test_results select is((select status from inventory.serials where tenant_id=pg_temp.fid('tenant') and code='RETURN-S1'),'disposed','supplier return removes selected serial from availability');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_purchase_return',pg_temp.serial_return('repeat-return-serial'))$$,'55000','RETURN_SERIAL_UNAVAILABLE','same serial cannot be returned twice even with remaining source quantity');
insert into procurement_test_results select is((select count(*)::integer from inventory.stock_movement_lines where tenant_id=pg_temp.fid('tenant') and (select id from inventory.serials where tenant_id=pg_temp.fid('tenant') and code='RETURN-S1')=any(serial_ids)),2,'serial retains one receipt and one return in immutable movement history');
insert into procurement_test_results select lives_ok('set constraints all immediate','serial return and failed duplicate retain all deferred invariants');
set local role authenticated;
insert into procurement_test_results select ok(not ((select detail#>'{lines,0}' from api.purchase_returns where id=pg_temp.fid('purchase-return')) ? 'stock_cost'),'return response does not disclose restricted moving-average cost');
insert into procurement_test_results select is((select count(*)::integer from inventory.stock_movement_lines where tenant_id=pg_temp.fid('tenant')),0,'return posting alone does not grant inventory movement cost access');
reset role;
