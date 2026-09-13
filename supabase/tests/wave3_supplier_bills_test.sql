-- Appended inside the procurement rollback fixture; no persistent identities.
set constraints all deferred;
select pg_temp.actor('creator');
insert into procurement_test_results select has_function('api','upsert_supplier_bill',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-311 supplier bill draft command exists');
insert into procurement_test_results select has_function('api','post_supplier_bill',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-311 atomic bill posting command exists');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid(x||'.role'),p from unnest(array['creator','approver']) x
cross join unnest(array['procurement.bills.view','procurement.bills.manage','procurement.bills.post']) p on conflict do nothing;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid(n),pg_temp.fid('tenant'),pg_temp.fid('entity'),c,n,t,b,pg_temp.fid('creator'),pg_temp.fid('creator')
from(values('ap-account','2400','liability','credit'),('input-tax-account','1400','asset','debit'))x(n,c,t,b);
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'supplier_bill','SBTEST-',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_supplier_bill_controls',jsonb_build_object('id',pg_temp.fid('entity'),'payable_account_id',pg_temp.fid('ap-account'),
 'input_tax_account_id',pg_temp.fid('input-tax-account'),'variance_account_id',pg_temp.fid('expense-account'),'amount_tolerance','0.02','price_percent_tolerance','0'));
create function pg_temp.bill(p_name text default 'bill',p_price text default '123.456789') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(p_name),'supplier_id',pg_temp.fid('supplier_a'),'supplier_reference','INV-'||p_name,'document_date','2026-09-14','due_date','2026-10-14',
 'currency_code','LKR','exchange_rate_id',null,'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(p_name||'.line'),
 'receipt_line_id',pg_temp.fid('allowed-receipt.line'),'quantity','0.45','unit_price',p_price,'discount_percent','10','tax_definition_id',null)))$$;
insert into procurement_responses values('bill',pg_temp.call('upsert_supplier_bill',pg_temp.bill(),null,'bill-save'));
insert into procurement_test_results select is(pg_temp.call('upsert_supplier_bill',pg_temp.bill(),null,'bill-save'),(select response from procurement_responses where name='bill'),'supplier bill draft exact replay');
insert into procurement_test_results select is((select total::text from procurement.supplier_bills where id=pg_temp.fid('bill')),'50.000000','supplier bill amount recalculated with entity rounding');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_supplier_bill',pg_temp.bill('duplicate')||'{"supplier_reference":" inv-BILL "}')$$,'23505',null,'supplier reference uniqueness is case and surrounding-space insensitive');
select pg_temp.call('upsert_supplier_bill',pg_temp.bill('price-exception','130'));
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('price-exception')),1)$$,'55000','MATCH_APPROVAL_REQUIRED','out-of-tolerance price blocks posting');
insert into procurement_test_results select throws_ok($$select pg_temp.call('approve_supplier_bill_match',jsonb_build_object('document_id',pg_temp.fid('price-exception'),'reason','Accept price'),1)$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','bill editor cannot approve own match exception');
select pg_temp.actor('approver');
select pg_temp.call('approve_supplier_bill_match',jsonb_build_object('document_id',pg_temp.fid('price-exception'),'reason','Supplier amended freight inclusive price'),1);
select pg_temp.actor('creator');
insert into procurement_responses values('bill-post',pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('bill')),1,'bill-post'));
insert into procurement_test_results select is(pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('bill')),1,'bill-post'),(select response from procurement_responses where name='bill-post'),'posted bill replay creates no second AP item');
insert into procurement_test_results select is((select original_amount::text from finance.open_items where source_id=pg_temp.fid('bill')),'50.000000','bill creates exact payable open item');
insert into procurement_test_results select is((select kind from finance.open_items where source_id=pg_temp.fid('bill')),'AP','bill uses existing AP open-item engine');
insert into procurement_test_results select is((select carrying_value::text from inventory.stock_valuations where tenant_id=pg_temp.fid('tenant')),'61.120000','bill does not duplicate received stock carrying value');
insert into procurement_test_results select is((select billed_quantity::text from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'0.450000','bill advances source PO billed quantity atomically');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('price-exception')),1)$$,'55000','RECEIPT_QUANTITY_UNAVAILABLE','approved exception cannot overbill a concurrently consumed receipt');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_supplier_bill',pg_temp.bill(),2)$$,'55000','BILL_NOT_EDITABLE','posted bill immutable');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('allowed-receipt'),'document_date','2026-09-14','reason','Reverse billed receipt'),1)$$,'55000','BILLED_RECEIPT_REQUIRES_RETURN','billed receipt cannot be reversed without a return');
insert into procurement_test_results select lives_ok('set constraints all immediate','supplier bill AP and accrual posting balances atomically');
set constraints all deferred;
insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,rate,kind,inclusive,valid_from,created_by,updated_by)
values(pg_temp.fid('input-tax'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'INPUT18','Synthetic input tax',18,'input',false,'2026-01-01',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.direct_bill(p_name text default 'direct-bill') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(p_name),'supplier_id',pg_temp.fid('supplier_b'),'supplier_reference','DIRECT-'||p_name,'document_date','2026-09-14','due_date','2026-09-30',
 'currency_code','LKR','exchange_rate_id',null,'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(p_name||'.line'),
 'description','Professional services','quantity','2','unit_price','125.123456','discount_percent','0','tax_definition_id',pg_temp.fid('input-tax'),'expense_account_id',pg_temp.fid('expense-account'))))$$;
select pg_temp.call('upsert_supplier_bill',pg_temp.direct_bill());
select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('direct-bill')),1);
-- 2 * 125.123456 rounds to 250.25; 18% = 45.045 rounds half-away to 45.05.
insert into procurement_test_results select is((select original_amount::text from finance.open_items where source_id=pg_temp.fid('direct-bill')),'295.300000','direct bill posts exact expense plus input tax');
insert into procurement_test_results select is((select base_debit::text from finance.journal_lines where journal_entry_id=(select journal_entry_id from procurement.supplier_bills where id=pg_temp.fid('direct-bill')) and account_id=pg_temp.fid('input-tax-account')),'45.050000','direct bill input tax debits the configured tax asset');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_supplier_bill',jsonb_set(pg_temp.direct_bill('stock-direct'),'{lines,0,product_id}',to_jsonb(pg_temp.fid('product'))))$$,'22023','DIRECT_BILL_NONSTOCK_REQUIRED','direct stocked invoice cannot bypass accepted stock receipt');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_supplier_bill',jsonb_set(pg_temp.direct_bill('numeric-bill'),'{lines,0,unit_price}','125.123456'))$$,'22023',null,'bill financial JSON numeric denied');
select pg_temp.call('upsert_supplier_bill',pg_temp.direct_bill('cancelled-bill'));
select pg_temp.call('cancel_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('cancelled-bill'),'reason','Supplier cancelled invoice'),1);
insert into procurement_test_results select lives_ok($$select pg_temp.call('upsert_supplier_bill',pg_temp.direct_bill('replacement')||'{"supplier_reference":"DIRECT-cancelled-bill"}')$$,'cancelled draft releases supplier reference without deleting history');
select pg_temp.call('upsert_supplier_bill',jsonb_set(pg_temp.bill('lot-bill','130'),'{lines,0}',
 (pg_temp.bill('lot-bill','130')#>'{lines,0}')||jsonb_build_object('receipt_line_id',pg_temp.fid('lot-receipt.line'),'quantity','0.1')));
select pg_temp.actor('approver');select pg_temp.call('approve_supplier_bill_match',jsonb_build_object('document_id',pg_temp.fid('lot-bill'),'reason','Approved quoted freight'),1);
select pg_temp.actor('creator');
select pg_temp.call('upsert_supplier_bill',jsonb_set((select detail from api.supplier_bills where id=pg_temp.fid('lot-bill')),'{lines,0,unit_price}','"131"'),1);
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('lot-bill')),2)$$,'55000','MATCH_APPROVAL_REQUIRED','editing a bill invalidates its exact match approval');
select pg_temp.actor('approver');select pg_temp.call('approve_supplier_bill_match',jsonb_build_object('document_id',pg_temp.fid('lot-bill'),'reason','Updated freight approved'),2);
select pg_temp.actor('creator');select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('lot-bill')),2);
insert into procurement_test_results select is((select status from procurement.supplier_bills where id=pg_temp.fid('lot-bill')),'posted','fresh independent match approval permits corrected invoice');
-- A receivables-only actor must not gain AP through the old shared helper or view.
delete from core.role_permissions where role_id=pg_temp.fid('approver.role') and permission_code like 'procurement.bills.%';
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('approver.role'),'finance.receivables.view');
grant select on procurement_responses to authenticated;
select pg_temp.actor('approver');set local role authenticated;
insert into procurement_test_results select is((select count(*)::integer from api.receivable_balances where tenant_id=pg_temp.fid('tenant')),0,'AR register excludes AP even with receivables permission');
insert into procurement_test_results select is(finance.flow_visible_residual(pg_temp.fid('tenant'),(select (response#>>'{entity,open_item_id}')::uuid from procurement_responses where name='bill-post')),null::jsonb,'AR residual helper cannot leak AP balance by known ID');
insert into procurement_test_results select is((select count(*)::integer from finance.open_items where tenant_id=pg_temp.fid('tenant')),0,'AR-only RLS denies AP rows');
reset role;select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code) select pg_temp.fid('tenant'),pg_temp.fid('approver.role'),p from unnest(array['procurement.bills.view','procurement.bills.manage','procurement.bills.post'])p;
insert into procurement_test_results select lives_ok('set constraints all immediate','direct and exception bills retain deferred ledger invariants');
