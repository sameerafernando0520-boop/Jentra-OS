-- Candidate-only planning evidence. Small synthetic timings are not target-scale/p95 proof.
reset role;
select pg_temp.actor('creator');
create temporary table representative_read_plans(evidence jsonb);
grant insert on representative_read_plans to authenticated;

insert into procurement_test_results
select ok(exists(select 1 from pg_index i join pg_attribute a
 on a.attrelid=i.indrelid and a.attnum=i.indkey[0]
 where i.indrelid=relation::regclass and i.indisvalid and a.attname='tenant_id'),
 relation||' has a valid tenant-leading index')
from unnest(array['finance.open_items','finance.open_item_allocations',
 'inventory.stock_movement_lines','inventory.stock_balances','inventory.stock_reservations',
 'finance.journal_lines','finance.journal_entries','finance.bank_statement_lines',
 'finance.bank_match_claims','procurement.requisitions']) relation;

create function pg_temp.record_representative_read_plan(p_name text,p_query text)
returns void language plpgsql as $$declare r record;begin
 for r in execute 'explain (analyze,buffers,settings,format json) '||p_query loop
  insert into representative_read_plans values(jsonb_build_object(
   'name',p_name,'query',p_query,'query_md5',md5(p_query),'database_role',current_user,
   'actor',auth.uid(),'plan',r."QUERY PLAN",
   'boundary',case when current_user='authenticated' then
    'Authenticated SQL role with synthetic JWT claims; small rolled-back fixture, not native authentication or target-scale/p95 proof'
    else 'Privileged synthetic fixture role for private bank basis only; no authenticated read or target-scale/p95 claim' end));
 end loop;
end$$;

set local role authenticated;
insert into procurement_test_results select is(current_user::text,'authenticated','representative reads plan with authenticated database role');
insert into procurement_test_results select is(auth.uid(),pg_temp.fid('creator'),'representative reads use the synthetic scoped actor');

select pg_temp.record_representative_read_plan('open_item_aging_basis',format(
 'select id,posting_date,due_date,original_amount from finance.open_items where tenant_id=%L::uuid and legal_entity_id=%L::uuid and branch_id=%L::uuid and party_id=(select party_id from finance.open_items where tenant_id=%L::uuid order by id limit 1) and currency_code=''LKR'' and posting_date<=''2026-09-30'' order by posting_date,due_date,id limit 200',
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('tenant')));
select pg_temp.record_representative_read_plan('allocation_history_basis',format(
 'select id,source_amount,transaction_amount from finance.open_item_allocations where tenant_id=%L::uuid and source_open_item_id=(select id from finance.open_items where tenant_id=%L::uuid order by id limit 1) and posting_date<=''2026-09-30'' order by posting_date,id limit 500',pg_temp.fid('tenant'),pg_temp.fid('tenant')));
select pg_temp.record_representative_read_plan('stock_asof_basis',format(
 'select id,base_quantity,base_value from inventory.stock_movement_lines where tenant_id=%L::uuid and warehouse_id=(select warehouse_id from inventory.stock_movement_lines where tenant_id=%L::uuid order by id limit 1) and product_id=(select product_id from inventory.stock_movement_lines where tenant_id=%L::uuid order by id limit 1) and posting_date<=''2026-09-30'' order by posting_date,id limit 200',pg_temp.fid('tenant'),pg_temp.fid('tenant'),pg_temp.fid('tenant')));
select pg_temp.record_representative_read_plan('journal_report_filter',format(
 'select id,base_debit,base_credit from finance.journal_lines where tenant_id=%L::uuid and legal_entity_id=%L::uuid and account_id=(select account_id from finance.journal_lines where tenant_id=%L::uuid order by id limit 1) and posting_date between ''2026-09-01'' and ''2026-09-30'' order by posting_date,id limit 200',pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('tenant')));
reset role;
insert into procurement_test_results select ok(not has_table_privilege('authenticated','finance.bank_statement_lines','select'),
 'private bank statement basis remains unavailable to authenticated direct SELECT');
insert into procurement_test_results select ok(not has_table_privilege('authenticated','finance.bank_match_claims','select'),
 'private bank claims remain unavailable to authenticated direct SELECT');
select pg_temp.record_representative_read_plan('bank_statement_matching_basis',format(
 'select id,reference,amount from finance.bank_statement_lines where tenant_id=%L::uuid and bank_id=(select bank_id from finance.bank_statement_lines where tenant_id=%L::uuid order by id limit 1) and posting_date<=''2026-09-30'' order by posting_date,id limit 200',pg_temp.fid('tenant'),pg_temp.fid('tenant')));
select pg_temp.record_representative_read_plan('bank_claim_uniqueness',format(
 'select source_id,match_id from finance.bank_match_claims where tenant_id=%L::uuid and kind=''journal'' order by source_id limit 200',pg_temp.fid('tenant')));
set local role authenticated;
select pg_temp.record_representative_read_plan('requisition_lifecycle_cursor',format(
 'select id,status from procurement.requisitions where tenant_id=%L::uuid and legal_entity_id=%L::uuid and branch_id=%L::uuid and status=''pending_approval'' order by id limit 50',pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch')));
select pg_temp.record_representative_read_plan('reservation_lifecycle_cursor',format(
 'select id,sales_order_id,base_quantity from inventory.stock_reservations where tenant_id=%L::uuid and legal_entity_id=%L::uuid and branch_id=%L::uuid and status=''active'' and expires_at<=''2026-09-30T00:00:00Z'' order by sales_order_id,id limit 50',pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch')));
select pg_temp.record_representative_read_plan('scoped_stock_availability_view',format(
 'select id,available_quantity from api.stock_availability where tenant_id=%L::uuid and legal_entity_id=%L::uuid and branch_id=%L::uuid order by id limit 200',pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch')));
select pg_temp.record_representative_read_plan('scoped_receivable_balances_view',format(
 'select * from api.receivable_balances where tenant_id=%L::uuid and legal_entity_id=%L::uuid and branch_id=%L::uuid order by id limit 200',pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch')));
select pg_temp.record_representative_read_plan('scoped_payable_balances_view',format(
 'select * from api.payable_balances where tenant_id=%L::uuid and legal_entity_id=%L::uuid and branch_id=%L::uuid order by id limit 200',pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch')));
reset role;

insert into representative_read_plans values(jsonb_build_object('name','source_and_fixture_metadata',
 'relations',(select jsonb_agg(jsonb_build_object('relation',n.nspname||'.'||c.relname,'view_md5',md5(pg_get_viewdef(c.oid))))
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='api' and c.relname in ('stock_availability','receivable_balances','payable_balances')),
 'functions',(select jsonb_agg(jsonb_build_object('name',p.oid::regprocedure::text,'source_md5',md5(pg_get_functiondef(p.oid))))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('api','finance') and p.proname in
 ('customer_statement','supplier_statement','stock_reservation_queue','bank_reconciliation_options','close_inventory_accounts','flow_residual')),
 'indexes',(select jsonb_agg(jsonb_build_object('relation',i.indrelid::regclass::text,'index',ci.relname,'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid))
 from pg_index i join pg_class ci on ci.oid=i.indexrelid where i.indrelid in
 ('finance.open_items'::regclass,'finance.open_item_allocations'::regclass,'inventory.stock_movement_lines'::regclass,
 'inventory.stock_balances'::regclass,'inventory.stock_reservations'::regclass,'finance.journal_lines'::regclass,
 'finance.bank_statement_lines'::regclass,'finance.bank_match_claims'::regclass,'procurement.requisitions'::regclass)),
 'fixture_counts',jsonb_build_object('open_items',(select count(*) from finance.open_items where tenant_id=pg_temp.fid('tenant')),
 'stock_movement_lines',(select count(*) from inventory.stock_movement_lines where tenant_id=pg_temp.fid('tenant')),
 'journal_lines',(select count(*) from finance.journal_lines where tenant_id=pg_temp.fid('tenant')),
 'bank_statement_lines',(select count(*) from finance.bank_statement_lines where tenant_id=pg_temp.fid('tenant')),
 'reservations',(select count(*) from inventory.stock_reservations where tenant_id=pg_temp.fid('tenant'))),
 'boundary','Scoped production-query components only. The enclosing PL/pgSQL report plans do not expose nested plans; representative target-scale EXPLAIN and p95 remain open.'));
