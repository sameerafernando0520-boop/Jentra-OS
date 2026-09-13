-- Append to wave3_procurement_test.sql before outsider/finish/rollback in the same transaction.
select pg_temp.actor('creator');
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,code,name,created_by)
values(pg_temp.fid('warehouse'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'PO-WH','Procurement test warehouse',pg_temp.fid('creator'));
create function pg_temp.po() returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid('order'),'source_rfq_id',pg_temp.fid('rfq'),'source_rfq_version',4,
 'source_quote_id',pg_temp.fid('supplier_a.quote'),'source_quote_version',2,
 'warehouse_id',pg_temp.fid('warehouse'),'document_date','2026-09-13','promised_date','2026-09-30')$$;
insert into procurement_responses values('po',pg_temp.call('upsert_purchase_order',pg_temp.po(),null,'po-create'));
insert into procurement_test_results select is((select response#>>'{entity,total}' from procurement_responses where name='po'),'333.330000','PO copies selected exact price and terms');
insert into procurement_test_results select is(pg_temp.call('upsert_purchase_order',pg_temp.po(),null,'po-create'),(select response from procurement_responses where name='po'),'PO create replay returns original receipt');
insert into procurement_test_results select is((select source_line_id from procurement.purchase_order_lines where order_id=pg_temp.fid('order')),pg_temp.fid('request.line'),'PO source line is traceable to requisition');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_purchase_order',pg_temp.po()||jsonb_build_object('id',pg_temp.fid('duplicate-order')))$$,'55000','RFQ_ALREADY_ORDERED','second order cannot consume selected RFQ twice');
insert into procurement_test_results select is((select count(*)::integer from finance.journal_entries where tenant_id=pg_temp.fid('tenant')),0,'purchase commitment creates no journal');
create function pg_temp.po_version() returns bigint language sql as $$select version from procurement.purchase_orders where id=pg_temp.fid('order')$$;
create function pg_temp.po_transition(p_extra jsonb,p_key text default null) returns jsonb language sql as $$
 select pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid('order'))||p_extra,pg_temp.po_version(),p_key)$$;
insert into procurement_test_results select throws_ok($$select pg_temp.po_transition('{"action":"submit"}')$$,'55000','WORKFLOW_CONFIGURATION_ERROR','PO missing approval configuration fails closed');
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
select pg_temp.fid('po.workflow'),tenant_id,legal_entity_id,'purchase_order','Order approvals',status,
 jsonb_set(lifecycle,'{transitions}',lifecycle->'transitions'||'[["approved","cancelled"]]'::jsonb),created_by,updated_by
from workflow.workflow_definitions where id=pg_temp.fid('workflow');
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('po.step'),pg_temp.fid('tenant'),pg_temp.fid('po.workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'purchase_order','POTEST-',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.po_transition('{"action":"submit"}');
insert into procurement_test_results select throws_ok($$select pg_temp.po_transition('{"decision":"approved"}')$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','PO creator cannot self approve');
select pg_temp.actor('approver');select pg_temp.po_transition('{"decision":"approved"}');
insert into procurement_test_results select is((select status from procurement.purchase_orders where id=pg_temp.fid('order')),'approved','independent PO approval completes');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_purchase_order',pg_temp.po(),pg_temp.po_version())$$,'55000','ORDER_NOT_EDITABLE','approved PO cannot be overwritten');
insert into procurement_test_results select throws_ok($$select pg_temp.po_transition('{"action":"recall","reason":"bypass revision"}')$$,'55000','ORDER_NOT_RECALLABLE','recall cannot bypass commercial revision');
insert into procurement_test_results select throws_ok($$select pg_temp.po_transition('{"action":"revise"}')$$,'22023','REVISION_REASON_REQUIRED','material revision requires rationale');
select pg_temp.po_transition('{"action":"revise","reason":"Supplier price amendment"}');
insert into procurement_test_results select is((select revision from procurement.purchase_orders where id=pg_temp.fid('order')),2,'material revision increments revision');
insert into procurement_test_results select is((select status from procurement.purchase_orders where id=pg_temp.fid('order')),'draft','revision invalidates approved status');
insert into procurement_test_results select is((select snapshot->>'status' from procurement.purchase_order_revisions where order_id=pg_temp.fid('order') and version=3),'approved','prior approved history retained');
insert into procurement_test_results select throws_ok($$delete from procurement.purchase_order_revisions where order_id=pg_temp.fid('order')$$,'55000',null,'PO history cannot be rewritten');
select pg_temp.call('upsert_purchase_order',jsonb_set((select detail from api.purchase_orders where id=pg_temp.fid('order')),'{lines,0,unit_price}','"200"'),pg_temp.po_version());
insert into procurement_test_results select is((select total::text from procurement.purchase_orders where id=pg_temp.fid('order')),'540.000000','revised PO price is server recalculated');
select pg_temp.po_transition('{"action":"submit"}');
insert into procurement_test_results select is((select status from procurement.purchase_orders where id=pg_temp.fid('order')),'pending_approval','revised PO repeats approval');
create function pg_temp.direct_po() returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid('direct-order'),'source_requisition_id',pg_temp.fid('request'),'source_requisition_version',3,
 'warehouse_id',pg_temp.fid('warehouse'),'document_date','2026-09-13','promised_date','2026-09-30',
 'supplier_id',pg_temp.fid('supplier_b'),'currency_code','LKR','exchange_rate','1','rate_date','2026-09-13',
 'payment_terms','14 days','delivery_terms','Delivered',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('direct.line'),'source_line_id',pg_temp.fid('request.line'),
 'quantity','3','unit_price','100.123456','discount_percent','0','tax_definition_id',null)))$$;
insert into procurement_test_results select lives_ok($$select pg_temp.call('upsert_purchase_order',pg_temp.direct_po(),null,'direct-po')$$,'approved requisition can create a PO without an RFQ');
insert into procurement_test_results select is((select total::text from procurement.purchase_orders where id=pg_temp.fid('direct-order')),'300.370000','direct PO server recalculates price and rounds total');
insert into procurement_test_results select is((select source_line_id from procurement.purchase_order_lines where order_id=pg_temp.fid('direct-order')),pg_temp.fid('request.line'),'direct PO retains requisition line');
