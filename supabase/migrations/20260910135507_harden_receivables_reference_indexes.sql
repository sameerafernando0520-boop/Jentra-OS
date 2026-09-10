-- Additive AC-305–AC-308 advisor correction. Never rewrite applied migration history.
-- FK checks on a referenced actor/currency need the reference columns first;
-- existing tenant-leading indexes remain useful for scoped reads.
do $$ declare v_fk record; begin
 for v_fk in
 select c.conrelid,n.nspname,t.relname,c.conname,
  (select string_agg(quote_ident(a.attname),',' order by k.ordinality)
   from unnest(c.conkey) with ordinality k(num,ordinality)
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) as columns_sql
 from pg_constraint c join pg_class t on t.oid=c.conrelid
 join pg_namespace n on n.oid=t.relnamespace
 where c.contype='f' and n.nspname in ('sales','finance','inventory')
 and t.relname in ('posting_mappings','cash_bank_accounts','deliveries','delivery_lines',
  'sales_invoices','sales_invoice_lines','customer_receipts','customer_receipt_lines',
  'sales_returns','sales_return_lines','journal_entries','journal_lines','open_items',
  'open_item_allocations','lots','serials','lot_balances','stock_valuations',
  'stock_movements','stock_movement_lines')
 and not exists(select 1 from pg_index i where i.indrelid=c.conrelid
  and i.indisvalid and i.indisready and i.indpred is null
  and (i.indkey::smallint[])[0:cardinality(c.conkey)-1] @> c.conkey)
 loop
  execute format('create index %I on %I.%I(%s)',
   v_fk.relname||'_ref_'||left(md5(v_fk.conname),8),v_fk.nspname,v_fk.relname,v_fk.columns_sql);
 end loop;
end $$;

-- Postgres ORs permissive policies. Preserve that exact predicate when merging.
do $$ declare v_predicate text; v_count integer; begin
 select string_agg('('||pg_get_expr(polqual,polrelid)||')',' OR '),count(*)
 into v_predicate,v_count from pg_policy
 where polrelid='finance.cash_bank_accounts'::regclass and polcmd='r'
 and polname in ('permitted_read','setup_or_receipt_reference') and polpermissive;
 if v_count<>2 then raise exception 'CASH_BANK_READ_POLICY_CONTRACT_CHANGED';end if;
 execute format('alter policy permitted_read on finance.cash_bank_accounts using (%s)',v_predicate);
 drop policy setup_or_receipt_reference on finance.cash_bank_accounts;
end $$;
