-- Additive synthetic regression proposal, after the full policy fixture only.
-- A public catalog change must not let tracked goods receipts settle an older
-- untracked deficit without its cover and variance lineage. The enclosing
-- strict finish(true) transaction rolls every candidate/fixture effect back.
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.catalog.manage') on conflict do nothing;
select pg_temp.ns_product('tracking-drift',1,5);
select pg_temp.ns_issue('tracking-drift.issue','tracking-drift','2');
insert into procurement_test_results select is(pg_temp.ns_open('tracking-drift'),1::numeric,'tracking change regression begins with one genuine open untracked deficit');
insert into procurement_test_results select lives_ok($$select api.upsert_product(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 jsonb_build_object('id',pg_temp.fid('negative.tracking-drift'),'sku','NS-TRACKING-DRIFT','name','Negative stock tracking-drift','kind','stocked',
 'base_unit_id',pg_temp.fid('unit'),'tracking_mode','lot','revenue_account_id',pg_temp.fid('negative.revenue'),
 'inventory_account_id',pg_temp.fid('negative.inventory'),'cogs_account_id',pg_temp.fid('negative.cogs')),
 (select version from inventory.products where id=pg_temp.fid('negative.tracking-drift')),pg_temp.fid('negative.tracking-drift.catalog'))$$,
 'public catalog update can change the current tracking master while the original issue remains immutable');
insert into procurement_test_results select is((select tracking_mode from inventory.products where id=pg_temp.fid('negative.tracking-drift')),'lot','tracking regression uses the actual changed catalog master');
select pg_temp.ns_po('tracking-drift.po','tracking-drift',1,7);
insert into negative_stock_responses values('tracking-drift.receipt.payload',jsonb_set(pg_temp.ns_receipt_payload('tracking-drift.receipt','tracking-drift.po','1'),
 '{lines,0,lot_code}','"TRACKING-DRIFT-LOT"'));
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_goods_receipt',
 (select response from negative_stock_responses where name='tracking-drift.receipt.payload'),
 (select version from procurement.purchase_orders where id=pg_temp.fid('negative.tracking-drift.po')),'negative.tracking-drift.receipt')$$,
 '55000','NEGATIVE_STOCK_TRACKING_REQUIRES_CORRECTION','tracked goods receipt cannot bypass the original untracked deficit cover');
insert into procurement_test_results select is(pg_temp.ns_q('tracking-drift'),-1::numeric,'refused tracked receipt leaves the signed stock quantity unchanged');
insert into procurement_test_results select is(pg_temp.ns_v('tracking-drift'),-5::numeric,'refused tracked receipt leaves the provisional carrying value unchanged');
insert into procurement_test_results select is(pg_temp.ns_open('tracking-drift'),1::numeric,'refused tracked receipt preserves the original uncovered deficit');
insert into procurement_test_results select is((select count(*) from procurement.goods_receipts where command_id=pg_temp.fid('negative.tracking-drift.receipt')),0::bigint,'refused tracked receipt leaves no completed receipt');
insert into procurement_test_results select is((select count(*) from inventory.lots where product_id=pg_temp.fid('negative.tracking-drift') and code='TRACKING-DRIFT-LOT'),0::bigint,'refused tracked receipt rolls back its new lot identity');
