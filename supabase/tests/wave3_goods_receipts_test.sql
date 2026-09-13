-- Included by the rollback-only candidate builder after product-unit fixtures.
select pg_temp.actor('creator');
insert into procurement_test_results select has_function('api','post_goods_receipt',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-310 has an authenticated goods receipt command');
insert into procurement_test_results select has_function('api','reverse_goods_receipt',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-310 has a linked receipt reversal command');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),p from unnest(array['procurement.receipts.post','finance.setup.manage']) p on conflict do nothing;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid(n),pg_temp.fid('tenant'),pg_temp.fid('entity'),c,n,t,b,pg_temp.fid('creator'),pg_temp.fid('creator')
from (values('inventory-account','1300','asset','debit'),('grni-account','2300','liability','credit'),('expense-account','5300','expense','debit')) x(n,c,t,b);
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.fid('period'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'Receipt period','2026-09-01','2026-09-30',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),t,p,pg_temp.fid('creator'),pg_temp.fid('creator')
from(values('goods_receipt','GRTEST-'),('journal_entry','GJTEST-')) x(t,p);
update inventory.products set inventory_account_id=pg_temp.fid('inventory-account') where id=pg_temp.fid('product');
-- Restore the governed ratio only to approve the saved order, then change it again.
select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit(),4);
select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('converted.order'),'action','submit'),1);
select pg_temp.actor('approver');
select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('converted.order'),'decision','approved'),2);
select pg_temp.actor('creator');
select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit()||'{"numerator":"24"}',5);
create function pg_temp.gr(p_name text default 'receipt',p_accepted text default '0.25',p_rejected text default '0.1') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(p_name),'order_id',pg_temp.fid('converted.order'),'document_date','2026-09-14',
 'warehouse_id',pg_temp.fid('warehouse'),'reference','Supplier delivery 001',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(p_name||'.line'),
 'order_line_id',(select id from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),
 'accepted_quantity',p_accepted,'rejected_quantity',p_rejected,'rejection_reason','Damaged packaging','serial_codes','[]'::jsonb)))$$;
create function pg_temp.gr_version() returns bigint language sql as $$select version from procurement.purchase_orders where id=pg_temp.fid('converted.order')$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr(),pg_temp.gr_version())$$,'55000','RECEIPT_CONTROLS_REQUIRED','missing GRNI configuration blocks atomically');
select pg_temp.call('upsert_receipt_controls',jsonb_build_object('id',pg_temp.fid('entity'),'grni_account_id',pg_temp.fid('grni-account'),'expense_account_id',pg_temp.fid('expense-account')));
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr(),3)$$,'22023','GOVERNED_CONVERSION_REQUIRED','EC-320 changed conversion master cannot silently change approved receipt basis');
select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit(),6);
insert into procurement_responses values('receipt',pg_temp.call('post_goods_receipt',pg_temp.gr(),3,'receipt-post'));
insert into procurement_test_results select is(pg_temp.call('post_goods_receipt',pg_temp.gr(),3,'receipt-post'),(select response from procurement_responses where name='receipt'),'receipt exact replay after source version advances');
insert into procurement_test_results select is((select on_hand_quantity::text from inventory.stock_balances where tenant_id=pg_temp.fid('tenant')),'3.000000','only accepted stock uses frozen twelve-unit conversion');
insert into procurement_test_results select is((select received_quantity::text from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'0.250000','rejected quantity does not consume PO remaining');
insert into procurement_test_results select is((select carrying_value::text from inventory.stock_valuations where tenant_id=pg_temp.fid('tenant')),'27.780000','receipt net value excludes bill input tax');
insert into procurement_test_results select is((select sum(base_debit-base_credit)::text from finance.journal_lines where tenant_id=pg_temp.fid('tenant')),'0.000000','receipt inventory and GRNI journal balances');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr('excess','0.3','0'),pg_temp.gr_version())$$,'22023','RECEIPT_EXCEEDS_REMAINING','excess receipt blocked');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr('stale'),3)$$,'40001','VERSION_CONFLICT','concurrent source version prevents stale receipt');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',jsonb_set(pg_temp.gr('numeric'),'{lines,0,accepted_quantity}','0.25'),pg_temp.gr_version())$$,'22023',null,'receipt quantities must be decimal strings');
insert into procurement_test_results select is((select count(*)::integer from procurement.goods_receipts where tenant_id=pg_temp.fid('tenant')),1,'failed posting creates no receipt or partial stock effects');
insert into procurement_test_results select throws_ok($$delete from procurement.goods_receipt_lines where receipt_id=pg_temp.fid('receipt')$$,'55000',null,'posted receipt lines immutable');
select pg_temp.actor('approver');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr('denied'),4)$$,'42501',null,'approval permission alone cannot post receipts');
select pg_temp.actor('creator');
insert into procurement_responses values('reverse',pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('receipt'),'document_date','2026-09-14','reason','Supplier delivery recorded twice'),1,'receipt-reverse'));
insert into procurement_test_results select is((select on_hand_quantity::text from inventory.stock_balances where tenant_id=pg_temp.fid('tenant')),'0.000000','reversal restores stock quantity');
insert into procurement_test_results select is((select carrying_value::text from inventory.stock_valuations where tenant_id=pg_temp.fid('tenant')),'0.000000','reversal restores carrying value');
insert into procurement_test_results select is((select received_quantity::text from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'0.000000','reversal restores PO remaining');
insert into procurement_test_results select is((select count(*)::integer from procurement.goods_receipts where tenant_id=pg_temp.fid('tenant')),1,'original receipt remains immutable after reversal');
insert into procurement_test_results select is((select count(*)::integer from finance.journal_entries where tenant_id=pg_temp.fid('tenant') and status='posted'),2,'reversal links a second posted journal');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('receipt'),'document_date','2026-09-14','reason','Again'),1)$$,'40001','VERSION_CONFLICT','second reversal cannot repeat stock restoration');
select pg_temp.call('post_goods_receipt',pg_temp.gr('rejected-only','0','0.2'),pg_temp.gr_version());
insert into procurement_test_results select ok((select stock_movement_id is null and journal_entry_id is null from procurement.goods_receipts where id=pg_temp.fid('rejected-only')),'all-rejected receipt records evidence without a movement or journal');
update inventory.products set tracking_mode='lot' where id=pg_temp.fid('product');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr('missing-lot','0.1','0'),pg_temp.gr_version())$$,'22023','LOT_IDENTITY_INVALID','tracked receipt requires lot identity');
select pg_temp.call('post_goods_receipt',jsonb_set(pg_temp.gr('lot-receipt','0.1','0'),'{lines,0,lot_code}','"LOT-001"'),pg_temp.gr_version());
insert into procurement_test_results select is((select on_hand_quantity::text from inventory.lot_balances where tenant_id=pg_temp.fid('tenant')),'1.200000','lot balance retains exact accepted base units');
update inventory.products set tracking_mode='serial' where id=pg_temp.fid('product');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',jsonb_set(pg_temp.gr('fractional-serial','0.1','0'),'{lines,0,serial_codes}','["SER-1"]'),pg_temp.gr_version())$$,'22023','SERIAL_COUNT_INVALID','serial receipt requires whole base units');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',jsonb_set(pg_temp.gr('duplicate-serial','0.25','0'),'{lines,0,serial_codes}','["SER-1","SER-1","SER-3"]'),pg_temp.gr_version())$$,'23505',null,'duplicate serials roll back the complete receipt');
insert into procurement_test_results select is((select count(*)::integer from inventory.serials where tenant_id=pg_temp.fid('tenant')),0,'failed duplicate serial post leaves no partial identities');
select pg_temp.call('post_goods_receipt',jsonb_set(pg_temp.gr('serial-receipt','0.25','0'),'{lines,0,serial_codes}','["SER-1","SER-2","SER-3"]'),pg_temp.gr_version());
insert into procurement_test_results select is((select count(*)::integer from inventory.serials where tenant_id=pg_temp.fid('tenant') and status='available'),3,'accepted serial receipt creates each unique identity');
update inventory.stock_balances set allocated_quantity=2 where tenant_id=pg_temp.fid('tenant');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('serial-receipt'),'document_date','2026-09-14','reason','Wrong delivery'),1)$$,'55000','CONSUMED_RECEIPT_REQUIRES_RETURN','receipt reversal cannot consume reserved stock');
update inventory.stock_balances set allocated_quantity=0 where tenant_id=pg_temp.fid('tenant');
select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('serial-receipt'),'document_date','2026-09-14','reason','Wrong delivery'),1);
insert into procurement_test_results select is((select count(*)::integer from inventory.serials where tenant_id=pg_temp.fid('tenant') and status='disposed'),3,'reversed serial identities remain in immutable movement history');
insert into procurement_test_results select lives_ok('set constraints all immediate','all deferred journal and source constraints hold before rollback');
set constraints all deferred;
select pg_temp.call('upsert_receipt_controls',jsonb_build_object('id',pg_temp.fid('entity'),'grni_account_id',pg_temp.fid('grni-account'),
 'expense_account_id',pg_temp.fid('expense-account'),'maximum_over_receipt_percent','10'),1);
create function pg_temp.allowance(p_extra text default '0.05') returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fid('allowance'),
 'order_id',pg_temp.fid('converted.order'),'order_line_id',(select id from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),
 'extra_quantity',p_extra,'reason','Supplier pack-size variance')$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('approve_receipt_allowance',pg_temp.allowance(),pg_temp.gr_version())$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','PO author cannot approve over-receipt allowance');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('approver.role'),'procurement.receipts.post');
select pg_temp.actor('approver');
insert into procurement_test_results select throws_ok($$select pg_temp.call('approve_receipt_allowance',pg_temp.allowance('0.06'),pg_temp.gr_version())$$,'22023','ALLOWANCE_EXCEEDS_CONTROL','allowance cannot exceed configured exact percentage');
insert into procurement_responses values('allowance',pg_temp.call('approve_receipt_allowance',pg_temp.allowance(),pg_temp.gr_version(),'allowance-approve'));
update inventory.products set tracking_mode='none' where id=pg_temp.fid('product');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr('own-allowance','0.45','0'),pg_temp.gr_version())$$,'22023','RECEIPT_EXCEEDS_REMAINING','allowance approver cannot post their own override');
select pg_temp.actor('creator');
select pg_temp.call('post_goods_receipt',pg_temp.gr('allowed-receipt','0.45','0'),pg_temp.gr_version());
insert into procurement_test_results select is((select received_quantity::text from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'0.550000','independently approved extra quantity received without rewriting ordered quantity');
insert into procurement_test_results select is((select quantity::text from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'0.500000','commercial PO quantity remains immutable');
insert into procurement_test_results select is((select detail#>>'{allowance,reason}' from procurement.goods_receipt_lines where receipt_id=pg_temp.fid('allowed-receipt')),'Supplier pack-size variance','receipt retains accountable allowance snapshot');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',pg_temp.gr('reused-allowance','0.01','0'),pg_temp.gr_version())$$,'22023','RECEIPT_EXCEEDS_REMAINING','source version advance expires allowance');
insert into procurement_test_results select lives_ok('set constraints all immediate','tolerance posting retains all deferred invariants');
