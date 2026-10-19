-- Execute inside the procurement rollback fixture before its final outsider checks.
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.catalog.manage');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('creator.role'),pg_temp.fid('entity'),pg_temp.fid('creator'));
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.fid('carton'),pg_temp.fid('tenant'),'CARTON','Carton','ct','quantity',6,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,created_by,updated_by)
values(pg_temp.fid('product'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'PAPER-UNIT','Paper','stocked',pg_temp.fid('unit'),pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.product_unit() returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fid('conversion'),
 'product_id',pg_temp.fid('product'),'unit_id',pg_temp.fid('carton'),'numerator','12','denominator','1','status','active')$$;
insert into procurement_responses values('unit',pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit(),null,'unit-save'));
insert into procurement_test_results select is(pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit(),null,'unit-save'),(select response from procurement_responses where name='unit'),'product unit command replay');
insert into procurement_test_results select is(inventory.resolve_product_unit(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('product'),pg_temp.fid('carton'),'"0.5"','"12"','"1"')->>'base_quantity','6.000000','product-specific rational quantity is exact');
insert into procurement_test_results select throws_ok($$select inventory.resolve_product_unit(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('product'),pg_temp.fid('carton'),'"0.5"','"24"','"1"')$$,'22023','GOVERNED_CONVERSION_REQUIRED','invented conversion ratio denied');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit()||'{"numerator":12}',1)$$,'22023',null,'conversion JSON numeric input denied');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit(),99)$$,'40001','VERSION_CONFLICT','conversion stale update denied');
select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit()||'{"numerator":"1","denominator":"3"}',1);
insert into procurement_test_results select throws_ok($$select inventory.resolve_product_unit(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('product'),pg_temp.fid('carton'),'"1"','"1"','"3"')$$,'22023','BASE_QUANTITY_PRECISION_INVALID','nonterminating base quantity rejected');
insert into procurement_test_results select is((select snapshot->>'numerator' from inventory.product_unit_history where conversion_id=pg_temp.fid('conversion') and version=1),'12','prior conversion history retains exact ratio');
insert into procurement_test_results select throws_ok($$delete from inventory.product_unit_history where conversion_id=pg_temp.fid('conversion')$$,'55000',null,'conversion history is immutable');
select pg_temp.actor('approver');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit(),2)$$,'42501',null,'procurement approval permission does not grant catalogue writes');
select pg_temp.actor('creator');

select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit(),2);
select pg_temp.call('upsert_purchase_requisition',jsonb_set(pg_temp.header('converted'),'{lines,0}',
 (pg_temp.header('converted')#>'{lines,0}')||jsonb_build_object('product_id',pg_temp.fid('product'),'unit_id',pg_temp.fid('carton'),'quantity','0.5','conversion_numerator','12','conversion_denominator','1')));
insert into procurement_test_results select is((select base_quantity::text from procurement.requisition_lines where requisition_id=pg_temp.fid('converted')),'6.000000','requisition persists governed base quantity');
select pg_temp.transition('converted','{"action":"submit"}');
select pg_temp.actor('approver');select pg_temp.transition('converted','{"decision":"approved"}');select pg_temp.actor('creator');
select pg_temp.call('upsert_request_for_quote',pg_temp.rfq()||jsonb_build_object('id',pg_temp.fid('converted.rfq'),'requisition_id',pg_temp.fid('converted'),'requisition_version',3));
select pg_temp.call('upsert_request_for_quote',pg_temp.q()||jsonb_build_object('id',pg_temp.fid('converted.rfq'),'quote_id',pg_temp.fid('converted.quote'),
 'lines',jsonb_build_array((pg_temp.q()#>'{lines,0}')||jsonb_build_object('source_line_id',pg_temp.fid('converted.line'),'quantity','0.5'))),1);
select pg_temp.call('upsert_request_for_quote',jsonb_build_object('id',pg_temp.fid('converted.rfq'),'operation','select','quote_id',pg_temp.fid('converted.quote'),'selection_reason','Carton coverage'),2);
select pg_temp.call('upsert_purchase_order',pg_temp.po()||jsonb_build_object('id',pg_temp.fid('converted.order'),'source_rfq_id',pg_temp.fid('converted.rfq'),
 'source_rfq_version',3,'source_quote_id',pg_temp.fid('converted.quote'),'source_quote_version',1));
insert into procurement_test_results select is((select detail->>'base_quantity' from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'6.000000','non-base quantity survives requisition RFQ quotation and PO');
insert into procurement_test_results select is((select detail->>'conversion_numerator' from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'12','PO preserves governed numerator string');
select pg_temp.call('upsert_product_unit_conversion',pg_temp.product_unit()||'{"numerator":"24"}',3);
insert into procurement_test_results select is((select detail->>'base_quantity' from procurement.purchase_order_lines where order_id=pg_temp.fid('converted.order')),'6.000000','changing master does not rewrite document base quantity');

