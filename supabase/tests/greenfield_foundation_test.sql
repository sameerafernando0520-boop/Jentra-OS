begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(30);

select has_schema('core', 'core schema exists');
select has_schema('api', 'dedicated api schema exists');
select has_schema('audit', 'audit schema exists');
select has_table('core', 'tenants', 'tenant table exists');
select has_table('core', 'memberships', 'membership table exists');
select has_table('audit', 'events', 'audit event table exists');

select ok(
  (
    select bool_and(c.relrowsecurity)
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname in ('core', 'workflow', 'billing', 'audit')
      and c.relkind = 'r'
  ),
  'RLS is enabled on every foundation table'
);

select ok(
  (
    select bool_and(
      coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']
    )
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'api' and c.relkind = 'v'
  ),
  'every API view uses security_invoker'
);

select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where grantee = 'PUBLIC' and specific_schema in ('core', 'audit', 'api')
  ),
  'PUBLIC cannot execute Jentra functions'
);
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where grantee = 'anon' and specific_schema in ('core', 'audit', 'api')
  ),
  'anon cannot execute Jentra functions'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('core', 'audit')
      and p.prosecdef
      and not exists (
        select 1
        from unnest(coalesce(p.proconfig, '{}'::text[])) as config
        where config = 'search_path=""'
      )
  ),
  'every private security-definer function has an empty search path'
);
select ok(
  not has_table_privilege('authenticated', 'core.tenants', 'INSERT'),
  'authenticated cannot insert base tenants directly'
);
select ok(
  not has_table_privilege('authenticated', 'core.memberships', 'UPDATE'),
  'authenticated cannot update memberships directly'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '10000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'owner-one@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'owner-two@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

insert into core.tenants (
  id, name, slug, created_by
) values
  (
    '20000000-0000-0000-0000-000000000001',
    'Tenant One', 'tenant-one', '10000000-0000-0000-0000-000000000001'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    'Tenant Two', 'tenant-two', '10000000-0000-0000-0000-000000000002'
  );

insert into core.legal_entities (
  id, tenant_id, name, code, created_by
) values
  (
    '30000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'Entity One', 'ONE', '10000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000002',
    'Entity Two', 'TWO', '10000000-0000-0000-0000-000000000002'
  );

insert into core.memberships (
  id, tenant_id, user_id, status, joined_at
) values
  (
    '40000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001', 'active', now()
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000002', 'active', now()
  );

insert into core.roles (
  id, tenant_id, code, name, requires_mfa, is_system
) values (
  '50000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'test_owner', 'Test owner', true, true
);
insert into core.role_permissions (tenant_id, role_id, permission_code) values (
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  'audit.read'
);
insert into core.role_assignments (
  tenant_id, membership_id, role_id, created_by
) values (
  '20000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001'
);
insert into audit.events (
  id, tenant_id, actor_id, request_id, event_type,
  aggregate_type, aggregate_id
) values (
  '60000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000001',
  'test.created', 'tenant', '20000000-0000-0000-0000-000000000001'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","email":"owner-one@jentra.test","aal":"aal1"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from api.my_tenants),
  1::bigint,
  'member sees only their own tenant'
);
select is(
  (select count(*) from api.legal_entities),
  1::bigint,
  'security-invoker view denies the other tenant legal entity'
);
select ok(
  core.is_tenant_member('20000000-0000-0000-0000-000000000001'),
  'membership helper permits the current tenant'
);
select ok(
  not core.is_tenant_member('20000000-0000-0000-0000-000000000002'),
  'membership helper denies the other tenant'
);
select is(
  (select count(*) from api.get_my_capabilities(
    '20000000-0000-0000-0000-000000000001'
  )),
  0::bigint,
  'privileged capability is withheld at AAL1'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","email":"owner-one@jentra.test","aal":"aal2"}',
  true
);
select is(
  (select count(*) from api.get_my_capabilities(
    '20000000-0000-0000-0000-000000000001'
  )),
  1::bigint,
  'privileged capability is available at AAL2'
);
select is(
  (select count(*) from audit.events),
  1::bigint,
  'AAL2 user with audit permission can read tenant audit events'
);

reset role;
select throws_ok(
  $$update audit.events set event_type = 'tampered' where id = '60000000-0000-0000-0000-000000000001'$$,
  '55000',
  'Audit events are append-only.',
  'audit events reject update even for the table owner'
);
select ok(
  not has_table_privilege('authenticated', 'core.permissions', 'SELECT'),
  'authenticated cannot bypass the API to read permission reference data'
);
select ok(
  not has_table_privilege('authenticated', 'core.outbox_events', 'SELECT'),
  'authenticated has no outbox table privilege'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","email":"owner-one@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;

create temporary table bootstrap_results as
select
  api.bootstrap_tenant(
    'Idempotent Business', 'idempotent-business', 'Idempotent Entity', 'IDEM',
    'Head Office', 'HQ', 'Asia/Colombo', 'LKR',
    '80000000-0000-0000-0000-000000000001'
  ) as first_response,
  api.bootstrap_tenant(
    'Idempotent Business', 'idempotent-business', 'Idempotent Entity', 'IDEM',
    'Head Office', 'HQ', 'Asia/Colombo', 'LKR',
    '80000000-0000-0000-0000-000000000001'
  ) as second_response;

select is(
  (select first_response from bootstrap_results),
  (select second_response from bootstrap_results),
  'replayed bootstrap command returns the original response'
);
select is(
  (select count(*) from api.my_tenants where tenant_slug = 'idempotent-business'),
  1::bigint,
  'idempotent bootstrap creates exactly one tenant'
);
select is(
  (
    select count(*) from core.command_receipts
    where idempotency_key = '80000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'idempotent bootstrap stores exactly one command receipt'
);
select ok(
  (select (first_response->>'tenant_id')::uuid is not null from bootstrap_results),
  'bootstrap returns the new tenant context'
);

reset role;
select ok(
  (
    select c.relrowsecurity
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'billing' and c.relname = 'plans'
  ),
  'plan reference table has RLS'
);
select ok(
  (
    select c.relrowsecurity
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'core' and c.relname = 'permissions'
  ),
  'permission reference table has RLS'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_db_role_setting as s
    join pg_catalog.pg_roles as r on r.oid = s.setrole
    cross join unnest(s.setconfig) as config
    where r.rolname = 'authenticator'
      and config = 'pgrst.db_schemas=api, graphql_public'
  ),
  'PostgREST exposes the dedicated API schema'
);

select * from finish();
rollback;
