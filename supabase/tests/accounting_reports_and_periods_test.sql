begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(10);

-- 1. Verify accounting_periods table structure
select has_table('public', 'accounting_periods', 'accounting_periods table exists');

-- 2. Verify RLS enabled on accounting_periods
select ok(
  (
    select relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'accounting_periods'
  ),
  'RLS is enabled on accounting_periods'
);

-- 3. Verify RPC function existence
select has_function('public', 'post_manual_journal', ARRAY['uuid', 'date', 'text', 'jsonb'], 'post_manual_journal RPC exists');
select has_function('public', 'reverse_journal_entry', ARRAY['uuid', 'uuid', 'date', 'text'], 'reverse_journal_entry RPC exists');
select has_function('public', 'get_trial_balance', ARRAY['uuid', 'date'], 'get_trial_balance RPC exists');
select has_function('public', 'get_profit_and_loss', ARRAY['uuid', 'date', 'date'], 'get_profit_and_loss RPC exists');
select has_function('public', 'get_balance_sheet', ARRAY['uuid', 'date'], 'get_balance_sheet RPC exists');

-- 4. Verify anon execute privileges revoked
select ok(
  not has_function_privilege('anon', 'public.post_manual_journal(uuid, date, text, jsonb)', 'execute'),
  'anon cannot execute post_manual_journal'
);

select ok(
  not has_function_privilege('anon', 'public.reverse_journal_entry(uuid, uuid, date, text)', 'execute'),
  'anon cannot execute reverse_journal_entry'
);

-- 5. Verify tenant isolation on post_manual_journal
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000099", "role": "authenticated"}';

select throws_ok(
  $$ select public.post_manual_journal('00000000-0000-0000-0000-000000000001', '2026-08-01'::date, 'Test', '[{"account_code":"1010","debit":100},{"account_code":"4000","credit":100}]'::jsonb) $$,
  '42501',
  'Permission denied to post manual journals.',
  'non-company member cannot post manual journal'
);

select * from finish();

rollback;
