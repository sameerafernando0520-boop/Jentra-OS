begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(7);

-- 1. Verify tables
select has_table('public', 'plans', 'plans table exists');
select has_table('public', 'company_subscriptions', 'company_subscriptions table exists');
select has_table('public', 'subscription_events', 'subscription_events table exists');

-- 2. Verify RPC existence
select has_function('public', 'get_company_subscription_status', ARRAY['uuid'], 'get_company_subscription_status RPC exists');

-- 3. Verify anon execute revoked
select ok(
  not has_function_privilege('anon', 'public.get_company_subscription_status(uuid)', 'execute'),
  'anon cannot execute get_company_subscription_status'
);

-- 4. Verify baseline plans seeded
select results_eq(
  $$ select count(*)::integer from public.plans $$,
  $$ VALUES (3) $$,
  'three default plans seeded'
);

-- 5. Verify direct write to company_subscriptions revoked from authenticated
select ok(
  not has_table_privilege('authenticated', 'public.company_subscriptions', 'insert'),
  'authenticated user cannot directly insert into company_subscriptions'
);

select * from finish();

rollback;
