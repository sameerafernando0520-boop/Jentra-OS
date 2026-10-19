-- Synthetic procurement-builder fragment. Insert after landed/provenance tests;
-- the owning builder supplies strict finish(true) and the final rollback.
select pg_temp.actor('creator');
set constraints all deferred;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),p from unnest(array[
 'inventory.valuation.post','inventory.cost.view','inventory.transfers.post','inventory.stock.view','finance.view'])p on conflict do nothing;
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,inventory_account_id,created_by,updated_by)
values(pg_temp.fid('lex.product'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'LEX','Landed extension synthetic stock','stocked',pg_temp.fid('unit'),'none',
 pg_temp.fid('inventory-account'),pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
values(pg_temp.fid('lex.destination'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'Landed extension destination','LEX-DEST',pg_temp.fid('creator'));
-- Two independent governed receipts at different original values.
create function pg_temp.lex_receipt(n text,price text) returns void language plpgsql as $$begin
 perform pg_temp.call('upsert_purchase_requisition',jsonb_set(pg_temp.header(n||'.req'),'{lines,0,product_id}',to_jsonb(pg_temp.fid('lex.product'))));
 perform pg_temp.transition(n||'.req','{"action":"submit"}');
 perform pg_temp.actor('approver');perform pg_temp.transition(n||'.req','{"decision":"approved"}');perform pg_temp.actor('creator');
 perform pg_temp.call('upsert_purchase_order',pg_temp.direct_po()||jsonb_build_object('id',pg_temp.fid(n||'.po'),'source_requisition_id',pg_temp.fid(n||'.req'),
  'lines',jsonb_build_array((pg_temp.direct_po()#>'{lines,0}')||jsonb_build_object('line_id',pg_temp.fid(n||'.po.line'),'source_line_id',pg_temp.fid(n||'.req.line'),'unit_price',price))));
 perform pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid(n||'.po'),'action','submit'),1);
 perform pg_temp.actor('approver');perform pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid(n||'.po'),'decision','approved'),2);perform pg_temp.actor('creator');
 perform pg_temp.call('post_goods_receipt',pg_temp.gr(n,'3','0')||jsonb_build_object('order_id',pg_temp.fid(n||'.po'),'document_date','2026-09-29',
  'lines',jsonb_build_array((pg_temp.gr(n,'3','0')#>'{lines,0}')||jsonb_build_object('order_line_id',pg_temp.fid(n||'.po.line')))),3);
end $$;
select pg_temp.lex_receipt('lex.receipt.a','10');
select pg_temp.lex_receipt('lex.receipt.b','20');
create function pg_temp.lex_line(n text) returns uuid language sql as $$select id from inventory.stock_movement_lines where source_line_id=pg_temp.fid(n||'.line')$$;
create function pg_temp.lex_payload(n text default 'lex.charge',mode text default 'quantity',amount text default '10.000001') returns jsonb language sql as $$
select jsonb_build_object('id',pg_temp.fid(n),'document_date','2026-09-29','reference','LEX-FREIGHT','reason','Allocate recorded synthetic freight',
 'total_amount',amount,'basis_mode',mode,'offset_account_id',pg_temp.fid('expense-account'),'variance_account_id',pg_temp.fid('expense-account'),
 'receipts',jsonb_build_array(jsonb_build_object('receipt_line_id',pg_temp.lex_line('lex.receipt.a'),'weight','1'),jsonb_build_object('receipt_line_id',pg_temp.lex_line('lex.receipt.b'),'weight','2')))$$;
create function pg_temp.lex_preview(p jsonb) returns jsonb language sql as $$select api.preview_landed_extension(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),p)$$;
create function pg_temp.lex_post(p jsonb,k text,version bigint default 0) returns jsonb language sql as $$select pg_temp.call('post_landed_extension',p||jsonb_build_object('basis_hash',pg_temp.lex_preview(p)->>'basis_hash'),version,k)$$;
create function pg_temp.lex_correction(n text,parent text,amount text) returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fid(n),'correction_of',pg_temp.fid(parent),
 'document_date','2026-09-29','reference','LEX-CORRECTION','reason','Correct original recorded freight at current attribution','total_amount',amount)$$;
create function pg_temp.lex_transfer(n text,op text,q text default '2',ver bigint default null) returns jsonb language sql as $$
select pg_temp.call('transfer_stock',jsonb_build_object('id',pg_temp.fid(n),'operation',op,'document_date','2026-09-29','reason','Synthetic extension transit','reference',n,
 'source_warehouse_id',pg_temp.fid('warehouse'),'destination_warehouse_id',pg_temp.fid('lex.destination'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(n||'.line'),'product_id',pg_temp.fid('lex.product'),'unit_id',pg_temp.fid('unit'),
 'quantity',q,'conversion_numerator','1','conversion_denominator','1','serial_ids','[]'::jsonb))),ver)$$;
create function pg_temp.lex_value(w text) returns numeric language sql as $$select v.carrying_value from inventory.stock_valuations v join inventory.stock_balances b on b.id=v.stock_balance_id
 where b.tenant_id=pg_temp.fid('tenant') and b.product_id=pg_temp.fid('lex.product') and b.warehouse_id=pg_temp.fid(w)$$;
create function pg_temp.lex_report(d text default '2026-09-29') returns jsonb language sql as $$select inventory.build_valuation_report(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 jsonb_build_object('id',pg_temp.fid('lex.report'),'as_of',d,'account_ids',jsonb_build_array(pg_temp.fid('inventory-account'))))$$;
insert into procurement_test_results select is((pg_temp.lex_preview(pg_temp.lex_payload())->>'amount')::numeric,10.000001::numeric,'multi-receipt exact total');
insert into procurement_test_results select is((select sum((r->>'target_allocation')::numeric) from jsonb_array_elements(pg_temp.lex_preview(pg_temp.lex_payload())->'receipts')r),10.000001::numeric,'cumulative receipt rounding conserves six-place remainder');
insert into procurement_test_results select is((select (r->>'target_allocation')::numeric from jsonb_array_elements(pg_temp.lex_preview(pg_temp.lex_payload('lex.value','original_value'))->'receipts')r
 where r->>'receipt_line_id'=pg_temp.lex_line('lex.receipt.a')::text),3.333334::numeric,'original value weights are explicit original receipt amounts');
insert into procurement_test_results select is((select (r->>'target_allocation')::numeric from jsonb_array_elements(pg_temp.lex_preview(pg_temp.lex_payload('lex.manual','manual'))->'receipts')r
 where r->>'receipt_line_id'=pg_temp.lex_line('lex.receipt.a')::text),3.333334::numeric,'manual positive decimal weights accepted');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(pg_temp.lex_payload()||'{"total_amount":1.2}')$$,'22023',null,'JSON floating amounts rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(jsonb_set(pg_temp.lex_payload('lex.manual','manual'),'{receipts,0,weight}','"0"'))$$,'22023',null,'zero manual weight rejected with no posting');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(jsonb_set(pg_temp.lex_payload(),'{receipts,0,receipt_line_id}',to_jsonb(pg_temp.fid('lex.foreign'))))$$,'22023','LANDED_EXTENSION_RECEIPT_INVALID','foreign or absent receipt rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(jsonb_set(pg_temp.lex_payload(),'{receipts,1,receipt_line_id}',to_jsonb(pg_temp.lex_line('lex.receipt.a'))))$$,'22023','LANDED_EXTENSION_RECEIPTS_INVALID','duplicate receipt cannot inflate basis');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_landed_extension',pg_temp.lex_payload()||'{"basis_hash":"stale"}',0)$$,'40001','LANDED_EXTENSION_PREVIEW_CHANGED','post requires current frozen basis');
insert into procurement_responses values('lex.quantity.before',jsonb_build_object('q',(select on_hand_quantity::text from inventory.stock_balances where product_id=pg_temp.fid('lex.product') and warehouse_id=pg_temp.fid('warehouse'))));
select pg_temp.lex_transfer('lex.transfer','dispatch');
insert into procurement_responses values('lex.preview.transit',pg_temp.lex_preview(pg_temp.lex_payload()));
insert into procurement_test_results select cmp_ok(((select response from procurement_responses where name='lex.preview.transit')->>'transit_amount')::numeric,'>',0::numeric,'explicit transit receives distinct landed share');
insert into procurement_test_results select is(((select response from procurement_responses where name='lex.preview.transit')->>'variance_amount')::numeric,0::numeric,'transit is never consumed variance');
insert into procurement_responses values('lex.command',pg_temp.lex_payload()||jsonb_build_object('basis_hash',pg_temp.lex_preview(pg_temp.lex_payload())->>'basis_hash'));
insert into procurement_responses values('lex.result',pg_temp.call('post_landed_extension',(select response from procurement_responses where name='lex.command'),0,'lex.charge'));
insert into procurement_test_results select is(pg_temp.call('post_landed_extension',(select response from procurement_responses where name='lex.command'),0,'lex.charge'),
 (select response from procurement_responses where name='lex.result'),'byte-identical command replay preserves receipt');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_landed_extension',(select response from procurement_responses where name='lex.command')||'{"reason":"Changed freight reason"}',0,'lex.charge')$$,'22023',null,'same command key with changed body is rejected');
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where source_line_id=pg_temp.fid('lex.charge')),0::numeric,'held and transit journals balance through existing engine');
insert into procurement_test_results select is((select sum(amount) from inventory.landed_extension_transit where extension_id=pg_temp.fid('lex.charge')),
 ((select response from procurement_responses where name='lex.preview.transit')->>'transit_amount')::numeric,'immutable transit supplement equals preview');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(pg_temp.lex_report()->'differences')r where r->>'evidence_key'='command:'||pg_temp.fid('lex.charge')::text),'dated report reconciles charge while in transit by command identity');
insert into procurement_test_results select throws_ok($$delete from inventory.landed_extensions where id=pg_temp.fid('lex.charge')$$,'55000',null,'posted extension is immutable');
insert into procurement_responses values('lex.destination.before',jsonb_build_object('original',(select carrying_value::text from inventory.transfer_lines where id=pg_temp.fid('lex.transfer.line'))));
select pg_temp.lex_transfer('lex.transfer','receive','2',1);
insert into procurement_test_results select is(pg_temp.lex_value('lex.destination'),
 ((select response from procurement_responses where name='lex.destination.before')->>'original')::numeric+
 ((select response from procurement_responses where name='lex.preview.transit')->>'transit_amount')::numeric,'transfer receipt settles extra value into pooled carrying cost');
insert into procurement_test_results select is((select carrying_value from inventory.transfer_lines where id=pg_temp.fid('lex.transfer.line')),
 ((select response from procurement_responses where name='lex.destination.before')->>'original')::numeric,'dispatch original cost is never rewritten');
insert into procurement_test_results select is((select count(*) from inventory.landed_extension_settlements where operation='transfer.receive'),1::bigint,'one immutable settlement clears one attributable transit share');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(pg_temp.lex_report()->'differences')r where r->>'evidence_key'='command:'||pg_temp.fid('lex.charge')::text),'settled charge remains source-reconciled');
insert into procurement_test_results select lives_ok($$select pg_temp.lex_transfer('lex.transfer','reverse','2',2)$$,'completed transfer reversal moves supplemental value exactly');
insert into procurement_test_results select is(pg_temp.lex_value('lex.destination'),0::numeric,'completed transfer reversal leaves no stranded destination value');
insert into procurement_test_results select is(pg_temp.lex_value('warehouse'),100.000001::numeric,'transfer reversal conserves original ninety plus exact ten freight');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(pg_temp.lex_report()->'differences')r where r->>'evidence_key'='command:'||pg_temp.fid('lex.charge')::text),'reverse settlement preserves source reconciliation');
-- Governed dispatch reversal also settles transit value at the source.
select pg_temp.lex_transfer('lex.transfer.reverse','dispatch','1');
select pg_temp.lex_post(pg_temp.lex_payload('lex.transit.reverse','manual','0.000009'),'lex.transit.reverse');
insert into procurement_responses values('lex.value.before.reverse',jsonb_build_object('v',(pg_temp.lex_value('warehouse')+
 (select carrying_value from inventory.transfer_lines where id=pg_temp.fid('lex.transfer.reverse.line'))+
 coalesce((select sum(amount) from inventory.landed_extension_transit where transfer_id=pg_temp.fid('lex.transfer.reverse')),0))::text));
select pg_temp.lex_transfer('lex.transfer.reverse','reverse','1',1);
insert into procurement_test_results select is(pg_temp.lex_value('warehouse'),((select response from procurement_responses where name='lex.value.before.reverse')->>'v')::numeric,'in-transit reversal settles supplemental amount without losing value');
-- Synthetic pooled issue uses the same exact final-residual costing rule and
-- genuine provenance trigger; quantities/history are only changed in this fixture.
create function pg_temp.lex_issue(n text,q numeric) returns void language plpgsql as $$declare b inventory.stock_balances%rowtype;v numeric;take numeric;mid uuid:=gen_random_uuid();begin
 select * into b from inventory.stock_balances where tenant_id=pg_temp.fid('tenant') and warehouse_id=pg_temp.fid('warehouse') and product_id=pg_temp.fid('lex.product');
 v:=pg_temp.lex_value('warehouse');take:=case when q=b.on_hand_quantity then v else round(v*q/b.on_hand_quantity,6) end;
 update inventory.stock_balances set on_hand_quantity=on_hand_quantity-q where id=b.id;
 update inventory.stock_valuations set carrying_value=carrying_value-take where stock_balance_id=b.id;
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(mid,pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'delivery',mid,pg_temp.fid('warehouse'),'2026-09-29','delivery',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),pg_temp.fid('creator'));
 insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,base_quantity,base_value,posting_date,created_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),mid,pg_temp.fid('warehouse'),pg_temp.fid('lex.product'),pg_temp.fid(n),-q,-take,'2026-09-29',pg_temp.fid('creator'));
end $$;
select pg_temp.lex_issue('lex.issue.partial',2);
insert into procurement_responses values('lex.correction.preview',pg_temp.lex_preview(pg_temp.lex_correction('lex.correction','lex.charge','0')));
insert into procurement_test_results select cmp_ok(((select response from procurement_responses where name='lex.correction.preview')->>'variance_amount')::numeric,'<',0::numeric,'later consumption produces distinct correction variance');
insert into procurement_test_results select is(((select response from procurement_responses where name='lex.correction.preview')->>'amount')::numeric,-10.000001::numeric,'reasoned correction posts only exact incremental delta');
select pg_temp.lex_post(pg_temp.lex_correction('lex.correction','lex.charge','0'),'lex.correction',1);
insert into procurement_test_results select is((select total_amount from inventory.landed_extensions where id=pg_temp.fid('lex.charge')),10.000001::numeric,'linked correction never rewrites original charge');
insert into procurement_test_results select is((select correction_of from inventory.landed_extensions where id=pg_temp.fid('lex.correction')),pg_temp.fid('lex.charge'),'correction retains immutable predecessor link');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(pg_temp.lex_correction('lex.second','lex.charge','1'))$$,'40001','LANDED_EXTENSION_CORRECTION_CHANGED','independent second correction of same predecessor rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(pg_temp.lex_correction('lex.changed','lex.correction','1')||'{"basis_mode":"quantity"}')$$,'22023','LANDED_EXTENSION_CORRECTION_BASIS_IMMUTABLE','correction cannot change allocation basis');
select pg_temp.lex_issue('lex.issue.final',4);
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(pg_temp.lex_payload('lex.consumed'))$$,'22023','LANDED_EXTENSION_CONSUMED_OR_UNCOVERED','EC327 wholly consumed new receipt allocation rejected');
insert into procurement_responses values('lex.consumed.correction',pg_temp.lex_preview(pg_temp.lex_correction('lex.consumed.correction','lex.correction','1.000001')));
insert into procurement_test_results select is(((select response from procurement_responses where name='lex.consumed.correction')->>'inventory_amount')::numeric,0::numeric,'wholly consumed later correction has zero held amount');
insert into procurement_test_results select is(((select response from procurement_responses where name='lex.consumed.correction')->>'variance_amount')::numeric,1.000001::numeric,'wholly consumed reasoned correction is exact variance');
select pg_temp.lex_post(pg_temp.lex_correction('lex.consumed.correction','lex.correction','1.000001'),'lex.consumed.correction',1);
insert into procurement_test_results select is(pg_temp.lex_value('warehouse'),0::numeric,'consumed correction does not restore quantity or create phantom stock value');
insert into procurement_test_results select is((select sum(base_quantity) from inventory.stock_movement_lines where product_id=pg_temp.fid('lex.product')),0::numeric,'new charges and corrections never change receipt quantity history');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(pg_temp.lex_correction('lex.backdated','lex.consumed.correction','2')||'{"document_date":"2026-09-28"}')$$,'22023','LANDED_EXTENSION_DATE_INVALID','correction cannot precede predecessor posting date');
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(pg_temp.lex_correction('lex.mfa','lex.consumed.correction','2'))$$,'42501',null,'privileged MFA is enforced before preview');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select pg_temp.lex_preview(pg_temp.lex_payload())$$,'42501',null,'nonmember cannot inspect landed evidence');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from inventory.landed_extension_transit$$,'42501',null,'private transit evidence has no authenticated table grant');
reset role;
insert into procurement_test_results select lives_ok('set constraints all immediate','all linked landed/transit/settlement evidence satisfies deferred constraints');
