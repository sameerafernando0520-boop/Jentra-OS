begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(15);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'companies', 'companies table exists');
select has_table('public', 'branches', 'branches table exists');
select has_table('public', 'roles', 'roles table exists');
select has_table('public', 'permissions', 'permissions table exists');
select has_table('public', 'role_permissions', 'role_permissions table exists');
select has_table('public', 'company_memberships', 'company_memberships table exists');
select has_table('public', 'company_member_branches', 'company_member_branches table exists');
select has_table('public', 'company_settings', 'company_settings table exists');

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in (
        'profiles', 'companies', 'branches', 'roles', 'permissions',
        'role_permissions', 'company_memberships',
        'company_member_branches', 'company_settings'
      )
      and c.relrowsecurity
  ),
  9::bigint,
  'RLS is enabled on every Phase 1 table'
);

select is(
  (select count(*) from pg_policies where schemaname = 'public'),
  29::bigint,
  'all Phase 1 RLS policies exist'
);

select is(
  (select count(*) from public.permissions),
  12::bigint,
  'the permission catalog is seeded'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.is_company_member(uuid)',
    'execute'
  ),
  'anonymous clients cannot execute private tenant helpers'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'company_memberships_role_company_fk'
      and contype = 'f'
  ),
  'membership roles use a tenant-composite foreign key'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'company_member_branches_branch_company_fk'
      and contype = 'f'
  ),
  'branch assignments use a tenant-composite foreign key'
);

select * from finish();

rollback;
