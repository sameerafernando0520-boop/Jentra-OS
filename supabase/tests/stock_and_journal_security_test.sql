begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(11);

-- 1. Verify direct mutation privileges on stock_balances are revoked from authenticated
select hasnt_table_privilege('authenticated', 'public.stock_balances', 'insert', 'authenticated cannot insert into stock_balances directly');
select hasnt_table_privilege('authenticated', 'public.stock_balances', 'update', 'authenticated cannot update stock_balances directly');

-- 2. Verify direct insert privileges on journal_entries and journal_lines are revoked from authenticated
select hasnt_table_privilege('authenticated', 'public.journal_entries', 'insert', 'authenticated cannot insert into journal_entries directly');
select hasnt_table_privilege('authenticated', 'public.journal_lines', 'insert', 'authenticated cannot insert into journal_lines directly');

-- 3. Verify SELECT privileges remain intact
select has_table_privilege('authenticated', 'public.stock_balances', 'select', 'authenticated can select stock_balances');
select has_table_privilege('authenticated', 'public.journal_entries', 'select', 'authenticated can select journal_entries');
select has_table_privilege('authenticated', 'public.journal_lines', 'select', 'authenticated can select journal_lines');

-- 4. Verify post_stock_movement RPC function structure and execute privileges
select has_function('public', 'post_stock_movement', ARRAY['uuid', 'uuid', 'uuid', 'text', 'numeric', 'numeric', 'text', 'text', 'text'], 'post_stock_movement function exists');

select ok(
  has_function_privilege('authenticated', 'public.post_stock_movement(uuid, uuid, uuid, text, numeric, numeric, text, text, text)', 'execute'),
  'authenticated can execute post_stock_movement'
);

select ok(
  not has_function_privilege('anon', 'public.post_stock_movement(uuid, uuid, uuid, text, numeric, numeric, text, text, text)', 'execute'),
  'anon cannot execute post_stock_movement'
);

-- 5. Verify tenant isolation: non-member cannot post a stock movement
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000099", "role": "authenticated"}';

select throws_ok(
  $$ select public.post_stock_movement('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'in', 10) $$,
  '42501',
  'Permission denied.',
  'non-company member cannot post stock movements'
);

select * from finish();

rollback;
