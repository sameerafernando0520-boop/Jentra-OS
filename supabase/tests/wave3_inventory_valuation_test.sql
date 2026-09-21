select pg_temp.actor('creator');
set constraints all deferred;
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),x from unnest(array['inventory.stock.view','inventory.cost.view','finance.view'])x on conflict do nothing;
create function pg_temp.valuation_payload(n text default 'valuation.first',d text default '2026-09-19') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(n),'as_of',d,'account_ids',jsonb_build_array(pg_temp.fid('inventory-account')))$$;
create function pg_temp.valuation_page(n text,s text,k text default null) returns jsonb language sql as $$select api.inventory_valuation_report_page(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid(n),s,0,k)$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload()||'{"account_ids":[]}',0)$$,'22023','VALUATION_INPUT_INVALID','valuation requires explicit control accounts');
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload(),1)$$,'40001','VERSION_CONFLICT','report creation requires expected version zero');
insert into procurement_responses values('valuation.first',pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload(),0,'valuation.first'));
insert into procurement_test_results select is(pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload(),0,'valuation.first'),(select response from procurement_responses where name='valuation.first'),'saved report replay returns identical immutable summary');
insert into procurement_test_results select is((select (response#>>'{entity,warehouse_value}')::numeric from procurement_responses where name='valuation.first'),
 (select sum(base_value) from inventory.stock_movement_lines where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity') and posting_date<='2026-09-19'),'dated warehouse value derives from movement ledger not mutable projection');
insert into procurement_test_results select is((select (response#>>'{entity,gl_value}')::numeric from procurement_responses where name='valuation.first'),
 (select sum(base_debit-base_credit) from finance.journal_lines where tenant_id=pg_temp.fid('tenant') and account_id=pg_temp.fid('inventory-account') and posting_date<='2026-09-19'),'selected-control GL total is exact');
insert into procurement_test_results select is((select sum((x->>'difference')::numeric) from jsonb_array_elements((select evidence->'differences' from inventory.valuation_reports where id=pg_temp.fid('valuation.first')))x),
 (select (response#>>'{entity,difference}')::numeric from procurement_responses where name='valuation.first'),'every source difference reconciles to aggregate difference');
insert into procurement_test_results select throws_ok($$delete from inventory.valuation_reports where id=pg_temp.fid('valuation.first')$$,'55000',null,'report evidence cannot be rewritten or deleted');
insert into procurement_test_results select ok(not exists(
 select 1 from jsonb_array_elements((select evidence->'stock' from inventory.valuation_reports where id=pg_temp.fid('valuation.first')))s
 where (s->>'quantity')::numeric<>0 and (s->>'value')::numeric is distinct from (
  select sum((l->>'value')::numeric) from jsonb_array_elements((select evidence->'lots' from inventory.valuation_reports where id=pg_temp.fid('valuation.first')))l
  where l->>'id' like (s->>'id')||':%')),'pooled lot allocation conserves every nonempty product carrying value');
create function pg_temp.fail_valuation_outbox() returns trigger language plpgsql as $$begin raise exception using errcode='P0001',message='VALUATION_OUTBOX_FAILURE';end$$;
create trigger synthetic_valuation_failure before insert on core.outbox_events for each row execute function pg_temp.fail_valuation_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload('valuation.failed'),0)$$,'P0001','VALUATION_OUTBOX_FAILURE','late report outbox failure rolls back generated evidence');
drop trigger synthetic_valuation_failure on core.outbox_events;
insert into procurement_test_results select is((select count(*) from inventory.valuation_reports where id=pg_temp.fid('valuation.failed')),0::bigint,'failed generation leaves no saved report');
insert into procurement_responses values('valuation.stock.before',pg_temp.valuation_page('valuation.first','stock'));
select pg_temp.landed_post('valuation.later.landed');
insert into procurement_test_results select is(pg_temp.valuation_page('valuation.first','stock'),(select response from procurement_responses where name='valuation.stock.before'),'later backdated landed posting cannot change saved stock report');
insert into procurement_responses values('valuation.second',pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload('valuation.second'),0));
insert into procurement_test_results select is((select (response#>>'{entity,warehouse_value}')::numeric from procurement_responses where name='valuation.second')-
 (select (response#>>'{entity,warehouse_value}')::numeric from procurement_responses where name='valuation.first'),6.666667::numeric,'fresh snapshot includes later posted landed inventory share');
create function pg_temp.valuation_transfer(op text,ver bigint default null,d text default '2026-09-19') returns jsonb language sql as $$select pg_temp.call('transfer_stock',jsonb_build_object(
 'id',pg_temp.fid('valuation.transfer'),'operation',op,'document_date',d,'reason','Test as-of inventory including transit','reference','VAL-T1',
 'source_warehouse_id',pg_temp.fid('warehouse'),'destination_warehouse_id',pg_temp.fid('trace.hiddenwarehouse'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('valuation.transfer.line'),'product_id',pg_temp.fid('product'),'unit_id',pg_temp.fid('unit'),
 'quantity','1','conversion_numerator','1','conversion_denominator','1','serial_ids','[]'::jsonb))),ver)$$;
select pg_temp.valuation_transfer('dispatch');
insert into procurement_responses values('valuation.transit',pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload('valuation.transit'),0));
insert into procurement_test_results select is((select (response#>>'{entity,inventory_value}')::numeric from procurement_responses where name='valuation.transit'),
 (select (response#>>'{entity,inventory_value}')::numeric from procurement_responses where name='valuation.second'),'dispatch retains entity value including transit');
insert into procurement_test_results select is(jsonb_array_length(pg_temp.valuation_page('valuation.transit','transit')->'items'),1,'in-transit holding is visible with original source');
insert into procurement_test_results select is(jsonb_array_length(pg_temp.valuation_page('valuation.transit','differences','transfer:'||pg_temp.fid('valuation.transfer')) ->'items'),0,'internal transfer creates no false source reconciliation difference');
select pg_temp.valuation_transfer('receive',1,'2026-09-20');
insert into procurement_responses values('valuation.old.date',pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload('valuation.old.date'),0));
insert into procurement_test_results select is(jsonb_array_length(pg_temp.valuation_page('valuation.old.date','transit')->'items'),1,'later receipt does not clear earlier dated transit');
insert into procurement_responses values('valuation.completed',pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload('valuation.completed','2026-09-20'),0));
insert into procurement_test_results select is((select response#>>'{entity,transit_value}' from procurement_responses where name='valuation.completed'),'0','completed transfer clears dated transit value');
insert into procurement_test_results select is((select (response#>>'{entity,inventory_value}')::numeric from procurement_responses where name='valuation.completed'),
 (select (response#>>'{entity,inventory_value}')::numeric from procurement_responses where name='valuation.second'),'completion conserves exact inventory value');
insert into procurement_test_results select throws_ok($$select pg_temp.valuation_page('valuation.first','invalid')$$,'22023','VALUATION_PAGE_INVALID','unknown snapshot section denied');
insert into procurement_test_results select throws_ok($$select pg_temp.valuation_page('valuation.first',null)$$,'22023','VALUATION_PAGE_INVALID','null snapshot section denied');
delete from core.role_assignments where tenant_id=pg_temp.fid('tenant') and membership_id=pg_temp.fid('creator.membership') and branch_id is null;
insert into procurement_test_results select throws_ok($$select pg_temp.valuation_page('valuation.first','stock')$$,'42501',null,'partial branch grant cannot read whole-entity saved report');
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_inventory_valuation_report',pg_temp.valuation_payload(),0,'valuation.first')$$,'42501',null,'report replay rechecks all entity branches');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,created_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('creator.role'),pg_temp.fid('entity'),pg_temp.fid('creator'));
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from inventory.valuation_reports$$,'42501',null,'private report evidence cannot be read directly');
reset role;
insert into procurement_test_results select lives_ok('set constraints all immediate','report generation retains deferred business invariants');
