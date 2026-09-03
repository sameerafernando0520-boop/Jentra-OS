begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(99);

-- AC-201 / NFR-203..NFR-208: normalized private schemas and hardened API.
select has_table('core', 'currencies', 'currency reference table exists');
select has_table('finance', 'exchange_rates', 'exchange-rate table exists');
select has_table('finance', 'tax_definitions', 'tax-definition table exists');
select has_table('finance', 'accounts', 'chart-of-accounts table exists');
select has_table('finance', 'fiscal_periods', 'fiscal-period table exists');
select has_table('crm', 'parties', 'party table exists');
select has_table('crm', 'contacts', 'contact table exists');
select has_table('inventory', 'units', 'unit table exists');
select has_table('inventory', 'products', 'product table exists');
select has_table('core', 'document_sequences', 'document sequence table exists');
select has_table('workflow', 'workflow_definitions', 'workflow definition table exists');
select has_table('workflow', 'approval_matrix_steps', 'approval matrix table exists');
select has_table('core', 'attachments', 'attachment metadata table exists');
select has_table('workflow', 'notifications', 'notification table exists');
select has_table('core', 'import_jobs', 'import job table exists');
select has_table('core', 'export_jobs', 'export job table exists');
select has_table('core', 'report_definitions', 'report definition table exists');
select is(
  (select count(*) from core.currencies where code = 'SAR' and active),
  1::bigint,
  'required SAR reference currency is active'
);

select ok(
  (
    select bool_and(c.relrowsecurity)
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname in ('core', 'finance', 'crm', 'inventory', 'workflow')
      and c.relkind = 'r'
      and c.relname in (
        'currencies', 'exchange_rates', 'tax_definitions', 'accounts',
        'fiscal_periods', 'parties', 'contacts', 'units', 'products',
        'document_sequences', 'workflow_definitions', 'approval_matrix_steps',
        'attachments', 'notifications', 'import_jobs', 'export_jobs',
        'report_definitions'
      )
  ),
  'RLS is enabled on every Wave 2 table'
);
select ok(
  (
    select count(*) = 17 and bool_and(
      coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']
    )
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'api'
      and c.relkind = 'v'
      and c.relname in (
        'currencies', 'exchange_rates', 'tax_definitions', 'accounts',
        'fiscal_periods', 'parties', 'contacts', 'units', 'products',
        'document_sequences', 'workflow_definitions', 'approval_matrix_steps',
        'attachments', 'my_notifications', 'import_jobs', 'export_jobs',
        'report_definitions'
      )
  ),
  'all 17 Wave 2 API views use security_invoker'
);
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where grantee = 'PUBLIC'
      and specific_schema in ('core', 'finance', 'crm', 'inventory', 'workflow', 'api')
  ),
  'PUBLIC cannot execute Wave 2 routines'
);
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where grantee = 'anon'
      and specific_schema in ('core', 'finance', 'crm', 'inventory', 'workflow', 'api')
  ),
  'anon cannot execute Wave 2 routines'
);
select ok(
  not has_table_privilege('authenticated', 'finance.exchange_rates', 'INSERT'),
  'authenticated cannot insert finance base rows directly'
);
select ok(
  not has_table_privilege('authenticated', 'crm.parties', 'UPDATE'),
  'authenticated cannot update CRM base rows directly'
);
select ok(
  (
    select count(*) = 13
    from core.permissions
    where code in (
      'core.setup.view', 'core.setup.manage',
      'finance.setup.view', 'finance.setup.manage',
      'crm.parties.view', 'crm.parties.manage',
      'inventory.catalog.view', 'inventory.catalog.manage',
      'workflow.configure', 'core.files.view', 'core.files.manage',
      'analytics.reports.view', 'analytics.reports.manage'
    )
  ),
  'Wave 2 permission vocabulary is seeded'
);
select ok(
  (select count(*) >= 10 from core.currencies where active),
  'a useful ISO currency reference set is seeded'
);
select is(
  (select public from storage.buckets where id = 'jentra-attachments'),
  false,
  'attachment bucket is private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'jentra-attachments'),
  26214400::bigint,
  'attachment bucket enforces 25 MiB'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('core', 'finance', 'crm', 'inventory', 'workflow', 'api')
      and p.prosecdef
      and p.proname like '%setup%'
      and not exists (
        select 1
        from unnest(coalesce(p.proconfig, '{}'::text[])) as config
        where config = 'search_path=""'
      )
  ),
  'Wave 2 security-definer setup routines use an empty search path'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and p.proname in (
        'upsert_exchange_rate', 'upsert_tax_definition', 'upsert_account',
        'upsert_fiscal_period', 'upsert_party', 'upsert_contact', 'upsert_unit',
        'upsert_product', 'upsert_document_sequence', 'reserve_document_number',
        'upsert_workflow_definition', 'upsert_approval_matrix_step',
        'register_attachment', 'complete_attachment', 'mark_notification_read',
        'import_setup_records', 'create_export_job', 'upsert_report_definition'
      )
  ),
  18::bigint,
  'all 18 explicit Wave 2 RPC commands exist'
);
select ok(
  position(
    'for update' in lower(pg_get_functiondef(
      'core.reserve_document_number_impl(uuid,uuid,date,uuid)'::regprocedure
    ))
  ) > 0,
  'document-number command serializes its sequence row'
);
select ok(
  position(
    'pg_advisory_xact_lock' in pg_get_functiondef(
      'core.wave2_replay(uuid,text,uuid,text)'::regprocedure
    )
  ) > 0,
  'command replay serializes each actor idempotency key'
);
select ok(
  exists (
    select 1 from pg_catalog.pg_constraint as con
    where con.conrelid = 'core.document_sequences'::regclass
      and con.contype = 'u'
      and con.conkey = array[2, 3, 4, 5]::smallint[]
  ),
  'document sequence scope has a database uniqueness constraint'
);
select ok(
  exists (
    select 1 from pg_catalog.pg_constraint as con
    where con.conrelid = 'finance.fiscal_periods'::regclass
      and con.contype = 'x'
  ),
  'fiscal periods have a concurrent overlap exclusion constraint'
);
select has_function(
  'workflow',
  'lifecycle_contract_valid',
  array['jsonb'],
  'workflow lifecycle validator exists'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint as con
    where con.conrelid = 'workflow.workflow_definitions'::regclass
      and con.conname = 'workflow_definitions_lifecycle_contract_check'
      and con.convalidated
  ),
  'workflow lifecycle constraint is validated'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint as con
    where con.conrelid = 'core.report_definitions'::regclass
      and con.conname = 'report_definitions_row_limit_check'
      and con.convalidated
      and pg_catalog.pg_get_constraintdef(con.oid) like '%row_limit >= 1%'
      and pg_catalog.pg_get_constraintdef(con.oid) like '%row_limit <= 200%'
  ),
  'saved report row limit is bounded to 200'
);

-- Two isolated businesses and AAL2 owners.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '11000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'wave2-one@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '11000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'wave2-two@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

insert into core.tenants (id, name, slug, default_currency_code, created_by) values
  (
    '21000000-0000-0000-0000-000000000001', 'Wave Two One', 'wave-two-one',
    'LKR', '11000000-0000-0000-0000-000000000001'
  ),
  (
    '21000000-0000-0000-0000-000000000002', 'Wave Two Two', 'wave-two-two',
    'USD', '11000000-0000-0000-0000-000000000002'
  );
insert into core.legal_entities (
  id, tenant_id, name, code, currency_code, created_by
) values
  (
    '31000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'Wave Entity One', 'WONE', 'LKR',
    '11000000-0000-0000-0000-000000000001'
  ),
  (
    '31000000-0000-0000-0000-000000000002',
    '21000000-0000-0000-0000-000000000002',
    'Wave Entity Two', 'WTWO', 'USD',
    '11000000-0000-0000-0000-000000000002'
  );
insert into core.branches (
  id, tenant_id, legal_entity_id, name, code, created_by
) values (
  '32000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  'Head Office', 'HQ', '11000000-0000-0000-0000-000000000001'
);
insert into core.memberships (id, tenant_id, user_id, status, joined_at) values
  (
    '41000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001', 'active', now()
  ),
  (
    '41000000-0000-0000-0000-000000000002',
    '21000000-0000-0000-0000-000000000002',
    '11000000-0000-0000-0000-000000000002', 'active', now()
  );
insert into core.roles (id, tenant_id, code, name, requires_mfa, is_system) values
  (
    '51000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'wave2_owner', 'Wave 2 owner', true, true
  ),
  (
    '51000000-0000-0000-0000-000000000002',
    '21000000-0000-0000-0000-000000000002',
    'wave2_owner', 'Wave 2 owner', true, true
  );
insert into core.role_permissions (tenant_id, role_id, permission_code)
select '21000000-0000-0000-0000-000000000001',
       '51000000-0000-0000-0000-000000000001', code
from core.permissions;
insert into core.role_permissions (tenant_id, role_id, permission_code)
select '21000000-0000-0000-0000-000000000002',
       '51000000-0000-0000-0000-000000000002', code
from core.permissions;
insert into core.role_assignments (
  tenant_id, membership_id, role_id, created_by
) values
  (
    '21000000-0000-0000-0000-000000000001',
    '41000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001'
  ),
  (
    '21000000-0000-0000-0000-000000000002',
    '41000000-0000-0000-0000-000000000002',
    '51000000-0000-0000-0000-000000000002',
    '11000000-0000-0000-0000-000000000002'
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"11000000-0000-0000-0000-000000000001","role":"authenticated","email":"wave2-one@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;

-- AC-202: exchange rate exactness, idempotency, validation, attribution.
create temporary table wave2_exchange_result as
select
  api.upsert_exchange_rate(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"source_currency_code":"USD","target_currency_code":"LKR","rate":"312.1234567891","effective_date":"2026-09-01","rate_type":"spot","source":"manual","status":"active"}',
    null,
    '61000000-0000-0000-0000-000000000001'
  ) as first_response,
  api.upsert_exchange_rate(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"source_currency_code":"USD","target_currency_code":"LKR","rate":"312.1234567891","effective_date":"2026-09-01","rate_type":"spot","source":"manual","status":"active"}',
    null,
    '61000000-0000-0000-0000-000000000001'
  ) as replay_response;
select is(
  (select first_response from wave2_exchange_result),
  (select replay_response from wave2_exchange_result),
  'exchange-rate replay returns the original response'
);
select is(
  (select count(*) from finance.exchange_rates),
  1::bigint,
  'exchange-rate replay creates one row'
);
select is(
  (select rate::text from finance.exchange_rates),
  '312.1234567891',
  'exchange rate preserves ten exact decimal places'
);
select is(
  (
    select count(*) from core.command_receipts
    where idempotency_key = '61000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'exchange-rate command stores one receipt'
);
select is(
  (
    select count(*) from audit.events
    where aggregate_type = 'exchange_rate'
  ),
  1::bigint,
  'exchange-rate command writes one audit event'
);
select throws_ok(
  $$select api.upsert_exchange_rate(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"source_currency_code":"LKR","target_currency_code":"LKR","rate":"1","effective_date":"2026-09-01","rate_type":"spot","source":"manual","status":"active"}',
    null,
    '61000000-0000-0000-0000-000000000002'
  )$$,
  '22023',
  'Source and target currencies must differ.',
  'same-currency exchange rate is rejected'
);

-- AC-203..AC-205: finance master constraints and lifecycle.
select lives_ok(
  $$select api.upsert_tax_definition(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"code":"VAT18","name":"VAT 18%","rate":"18.000000","kind":"output","inclusive":false,"recoverable":false,"valid_from":"2026-01-01","status":"active"}',
    null,
    '62000000-0000-0000-0000-000000000001'
  )$$,
  'valid tax definition is accepted'
);
select is(
  (select rate::text from finance.tax_definitions where code = 'VAT18'),
  '18.000000',
  'tax percentage preserves six exact decimals'
);
create temporary table wave2_account_result as
select api.upsert_account(
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  '{"code":"1000","name":"Assets","account_type":"asset","normal_balance":"debit","is_posting":false,"status":"active"}',
  null,
  '63000000-0000-0000-0000-000000000001'
) as response;
select is(
  (select count(*) from finance.accounts where code = '1000'),
  1::bigint,
  'valid account is accepted'
);
create temporary table wave2_child_account_result as
select api.upsert_account(
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  jsonb_build_object(
    'code', '1010', 'name', 'Cash', 'account_type', 'asset',
    'normal_balance', 'debit',
    'parent_id', (select response->'entity'->>'id' from wave2_account_result),
    'is_posting', true, 'status', 'active'
  ),
  null,
  '63000000-0000-0000-0000-000000000002'
) as response;
select is(
  (select count(*) from finance.accounts where code = '1010'),
  1::bigint,
  'posting child account is accepted under a non-posting parent'
);
create temporary table wave2_group_account_result as
select api.upsert_account(
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  jsonb_build_object(
    'code', '1100', 'name', 'Current assets', 'account_type', 'asset',
    'normal_balance', 'debit',
    'parent_id', (select response->'entity'->>'id' from wave2_account_result),
    'is_posting', false, 'status', 'active'
  ),
  null,
  '63000000-0000-0000-0000-000000000004'
) as response;
select is(
  (select count(*) from finance.accounts where code = '1100'),
  1::bigint,
  'non-posting account group is accepted'
);
select throws_ok(
  format(
    'select api.upsert_account(%L, %L, %L::jsonb, 1, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'id', (select response->'entity'->>'id' from wave2_account_result),
      'code', '1000', 'name', 'Assets', 'account_type', 'asset',
      'normal_balance', 'debit',
      'parent_id', (select response->'entity'->>'id' from wave2_group_account_result),
      'is_posting', false, 'status', 'active'
    )::text,
    '63000000-0000-0000-0000-000000000003'
  ),
  '22023',
  'Account hierarchy contains a cycle.',
  'cyclic account update is rejected atomically'
);
create temporary table wave2_fiscal_result as
select api.upsert_fiscal_period(
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  '{"name":"January 2026","start_date":"2026-01-01","end_date":"2026-01-31","state":"open","status":"active"}',
  null,
  '64000000-0000-0000-0000-000000000001'
) as response;
select is(
  (select count(*) from finance.fiscal_periods where name = 'January 2026'),
  1::bigint,
  'valid fiscal period is accepted'
);
select throws_ok(
  $$select api.upsert_fiscal_period(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"name":"January overlap","start_date":"2026-01-15","end_date":"2026-02-14","state":"open","status":"active"}',
    null,
    '64000000-0000-0000-0000-000000000002'
  )$$,
  '22023',
  'Fiscal period dates overlap.',
  'overlapping fiscal period is rejected'
);
select throws_ok(
  $$select api.upsert_fiscal_period(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"name":"December 2030","start_date":"2030-12-01","end_date":"2030-12-31","state":"hard_locked","status":"active"}',
    null,
    '64000000-0000-0000-0000-000000000006'
  )$$,
  '55000',
  'A new fiscal period must start open.',
  'new fiscal periods cannot bypass the lifecycle'
);
select lives_ok(
  format(
    'select api.upsert_fiscal_period(%L, %L, %L::jsonb, 1, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'id', (select response->'entity'->>'id' from wave2_fiscal_result),
      'name', 'January 2026', 'start_date', '2026-01-01',
      'end_date', '2026-01-31', 'state', 'soft_locked', 'status', 'active'
    )::text,
    '64000000-0000-0000-0000-000000000003'
  ),
  'open fiscal period can be soft locked'
);
select lives_ok(
  format(
    'select api.upsert_fiscal_period(%L, %L, %L::jsonb, 2, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'id', (select response->'entity'->>'id' from wave2_fiscal_result),
      'name', 'January 2026', 'start_date', '2026-01-01',
      'end_date', '2026-01-31', 'state', 'hard_locked', 'status', 'active'
    )::text,
    '64000000-0000-0000-0000-000000000004'
  ),
  'soft-locked fiscal period can be hard locked'
);
select throws_ok(
  format(
    'select api.upsert_fiscal_period(%L, %L, %L::jsonb, 3, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'id', (select response->'entity'->>'id' from wave2_fiscal_result),
      'name', 'January 2026', 'start_date', '2026-01-01',
      'end_date', '2026-01-31', 'state', 'open', 'status', 'active'
    )::text,
    '64000000-0000-0000-0000-000000000005'
  ),
  '55000',
  'A hard-locked fiscal period cannot be reopened.',
  'hard-locked fiscal period cannot be reopened'
);

-- AC-206: tenant parties and one active primary contact.
create temporary table wave2_party_result as
select api.upsert_party(
  '21000000-0000-0000-0000-000000000001',
  '{"code":"CUS-001","legal_name":"Ceylon Tea Holdings","display_name":"Ceylon Tea","kind":"both","email":"accounts@ceylontea.test","credit_limit":"500000.000000","credit_currency_code":"LKR","status":"active"}',
  null,
  '65000000-0000-0000-0000-000000000001'
) as response;
select is(
  (select count(*) from crm.parties where code = 'CUS-001'),
  1::bigint,
  'party is created once'
);
select throws_ok(
  $$select api.upsert_party(
    '21000000-0000-0000-0000-000000000001',
    '{"code":"DIFFERENT","legal_name":"Different request","display_name":"Different request","kind":"customer","status":"active"}',
    null,
    '65000000-0000-0000-0000-000000000001'
  )$$,
  '22023',
  'Idempotency key was used for a different request.',
  'idempotency key reuse with a different payload is rejected'
);
select throws_ok(
  format(
    'select api.upsert_party(%L, %L::jsonb, 99, %L)',
    '21000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'id', (select response->'entity'->>'id' from wave2_party_result),
      'code', 'CUS-001', 'legal_name', 'Ceylon Tea Holdings',
      'display_name', 'Ceylon Tea', 'kind', 'both',
      'credit_limit', '500000.000000', 'credit_currency_code', 'LKR',
      'status', 'active'
    )::text,
    '65000000-0000-0000-0000-000000000004'
  ),
  '40001',
  'Entity version does not match the expected version.',
  'stale optimistic version is rejected without changing the party'
);
select lives_ok(
  format(
    'select api.upsert_contact(%L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'party_id', (select response->'entity'->>'id' from wave2_party_result),
      'name', 'Primary contact', 'role', 'Finance',
      'email', 'finance@ceylontea.test', 'is_primary', true, 'status', 'active'
    )::text,
    '65000000-0000-0000-0000-000000000002'
  ),
  'first active primary contact is accepted'
);
select throws_ok(
  format(
    'select api.upsert_contact(%L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'party_id', (select response->'entity'->>'id' from wave2_party_result),
      'name', 'Second primary', 'role', 'Owner',
      'email', 'owner@ceylontea.test', 'is_primary', true, 'status', 'active'
    )::text,
    '65000000-0000-0000-0000-000000000003'
  ),
  '22023',
  'An active primary contact already exists.',
  'second active primary contact is rejected'
);
select is(
  (select count(*) from crm.contacts where is_primary and status = 'active'),
  1::bigint,
  'only one active primary contact remains'
);

-- AC-207: unit and product references stay in tenant scope.
create temporary table wave2_unit_result as
select api.upsert_unit(
  '21000000-0000-0000-0000-000000000001',
  '{"code":"EA","name":"Each","symbol":"ea","category":"quantity","precision":0,"status":"active"}',
  null,
  '66000000-0000-0000-0000-000000000001'
) as response;
select is(
  (select count(*) from inventory.units where code = 'EA'),
  1::bigint,
  'unit is created once'
);
select lives_ok(
  format(
    'select api.upsert_product(%L, %L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'sku', 'TEA-001', 'name', 'Ceylon tea pack', 'kind', 'stocked',
      'base_unit_id', (select response->'entity'->>'id' from wave2_unit_result),
      'tracking_mode', 'none', 'can_sell', true, 'can_purchase', true,
      'status', 'active'
    )::text,
    '66000000-0000-0000-0000-000000000002'
  ),
  'valid scoped product is accepted'
);
select is(
  (select count(*) from inventory.products where sku = 'TEA-001'),
  1::bigint,
  'product is created once'
);
reset role;
insert into inventory.units (
  id, tenant_id, code, name, symbol, category, precision,
  status, created_by, updated_by
) values (
  '76000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000002',
  'FOREIGN', 'Foreign unit', 'fu', 'quantity', 0, 'active',
  '11000000-0000-0000-0000-000000000002',
  '11000000-0000-0000-0000-000000000002'
);
set local role authenticated;
select throws_ok(
  $$select api.upsert_product(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"sku":"FOREIGN-UNIT","name":"Foreign unit product","kind":"stocked","base_unit_id":"76000000-0000-0000-0000-000000000001","tracking_mode":"none","can_sell":true,"can_purchase":true,"status":"active"}',
    null,
    '66000000-0000-0000-0000-000000000003'
  )$$,
  '22023',
  'Product base unit is invalid.',
  'foreign-tenant unit reference is rejected'
);

create temporary table wave2_inactive_unit_result as
select api.upsert_unit(
  '21000000-0000-0000-0000-000000000001',
  '{"code":"OLD","name":"Retired unit","symbol":"old","category":"quantity","precision":0,"status":"inactive"}',
  null,
  '66000000-0000-0000-0000-000000000004'
) as response;
select throws_ok(
  format(
    'select api.upsert_product(%L, %L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'sku', 'INACTIVE-UNIT', 'name', 'Inactive unit product',
      'kind', 'stocked',
      'base_unit_id', (select response->'entity'->>'id' from wave2_inactive_unit_result),
      'tracking_mode', 'none', 'status', 'active'
    )::text,
    '66000000-0000-0000-0000-000000000005'
  ),
  '22023',
  'Product base unit is invalid.',
  'inactive base unit reference is rejected'
);

create temporary table wave2_inactive_tax_result as
select api.upsert_tax_definition(
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  '{"code":"OLDTAX","name":"Retired tax","rate":"18.000000","kind":"output","valid_from":"2026-01-01","status":"inactive"}',
  null,
  '66000000-0000-0000-0000-000000000006'
) as response;
select throws_ok(
  format(
    'select api.upsert_product(%L, %L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'sku', 'INACTIVE-TAX', 'name', 'Inactive tax product',
      'kind', 'stocked',
      'base_unit_id', (select response->'entity'->>'id' from wave2_unit_result),
      'tax_definition_id', (select response->'entity'->>'id' from wave2_inactive_tax_result),
      'tracking_mode', 'none', 'status', 'active'
    )::text,
    '66000000-0000-0000-0000-000000000007'
  ),
  '22023',
  'Product tax definition must be active in this entity.',
  'inactive tax reference is rejected'
);

create temporary table wave2_inactive_account_result as
select api.upsert_account(
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  '{"code":"4999","name":"Retired revenue","account_type":"revenue","normal_balance":"credit","is_posting":true,"status":"inactive"}',
  null,
  '66000000-0000-0000-0000-000000000008'
) as response;
select throws_ok(
  format(
    'select api.upsert_product(%L, %L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'sku', 'INACTIVE-ACCOUNT', 'name', 'Inactive account product',
      'kind', 'stocked',
      'base_unit_id', (select response->'entity'->>'id' from wave2_unit_result),
      'revenue_account_id', (select response->'entity'->>'id' from wave2_inactive_account_result),
      'tracking_mode', 'none', 'status', 'active'
    )::text,
    '66000000-0000-0000-0000-000000000009'
  ),
  '22023',
  'Product revenue account must be an active posting account in this entity.',
  'inactive product account reference is rejected'
);

-- AC-208: serialized document numbering is gap-safe across retries.
create temporary table wave2_sequence_result as
select api.upsert_document_sequence(
  '21000000-0000-0000-0000-000000000001',
  '{"legal_entity_id":"31000000-0000-0000-0000-000000000001","branch_id":"32000000-0000-0000-0000-000000000001","document_type":"sales_invoice","prefix":"INV-","padding":6,"reset_policy":"never","next_value":42,"status":"active"}',
  null,
  '67000000-0000-0000-0000-000000000001'
) as response;
create temporary table wave2_number_result as
select
  api.reserve_document_number(
    '21000000-0000-0000-0000-000000000001',
    (select (response->'entity'->>'id')::uuid from wave2_sequence_result),
    '2026-09-01',
    '67000000-0000-0000-0000-000000000002'
  ) as first_response,
  api.reserve_document_number(
    '21000000-0000-0000-0000-000000000001',
    (select (response->'entity'->>'id')::uuid from wave2_sequence_result),
    '2026-09-01',
    '67000000-0000-0000-0000-000000000003'
  ) as second_response;
select is(
  (select first_response->'entity'->>'number' from wave2_number_result),
  'INV-000042',
  'first reservation formats sequence 42'
);
select is(
  (select second_response->'entity'->>'number' from wave2_number_result),
  'INV-000043',
  'second reservation formats sequence 43'
);
select is(
  (
    select api.reserve_document_number(
      '21000000-0000-0000-0000-000000000001',
      (select (response->'entity'->>'id')::uuid from wave2_sequence_result),
      '2026-09-01',
      '67000000-0000-0000-0000-000000000002'
    )->'entity'->>'number'
  ),
  'INV-000042',
  'replayed reservation returns the first number'
);
select is(
  (select next_value from core.document_sequences),
  44::bigint,
  'replay does not increment the sequence again'
);

-- AC-209: workflow configuration and amount ranges.
create temporary table wave2_workflow_result as
select api.upsert_workflow_definition(
  '21000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  '{"document_type":"purchase_order","name":"Purchase order lifecycle","lifecycle":{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["draft","cancelled"],["submitted","approved"],["submitted","rejected"],["submitted","cancelled"],["rejected","draft"],["rejected","cancelled"],["approved","posted"],["approved","cancelled"],["posted","settled"],["posted","fulfilled"],["posted","closed"],["posted","reversed"],["settled","closed"],["fulfilled","closed"]]},"status":"active"}',
  null,
  '68000000-0000-0000-0000-000000000001'
) as response;
select is(
  (select count(*) from workflow.workflow_definitions),
  1::bigint,
  'workflow definition is created'
);
select throws_ok(
  $$select api.upsert_workflow_definition(
    '21000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '{"document_type":"unsafe_workflow","name":"Unsafe lifecycle","lifecycle":{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["posted","draft"]]},"status":"active"}',
    null,
    '68000000-0000-0000-0000-000000000099'
  )$$,
  '22023',
  'Workflow lifecycle is invalid.',
  'non-canonical workflow transition is rejected'
);
select lives_ok(
  format(
    'select api.upsert_approval_matrix_step(%L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'workflow_definition_id',
      (select response->'entity'->>'id' from wave2_workflow_result),
      'role_id', '51000000-0000-0000-0000-000000000001',
      'step_order', 1, 'minimum_amount', '0.000000',
      'maximum_amount', '1000000.000000', 'currency_code', 'LKR',
      'status', 'active'
    )::text,
    '68000000-0000-0000-0000-000000000002'
  ),
  'valid approval step is accepted'
);
select is(
  (select count(*) from workflow.approval_matrix_steps),
  1::bigint,
  'approval step is created once'
);
select throws_ok(
  format(
    'select api.upsert_approval_matrix_step(%L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'workflow_definition_id',
      (select response->'entity'->>'id' from wave2_workflow_result),
      'role_id', '51000000-0000-0000-0000-000000000001',
      'step_order', 2, 'minimum_amount', '2000.000000',
      'maximum_amount', '1000.000000', 'currency_code', 'LKR',
      'status', 'active'
    )::text,
    '68000000-0000-0000-0000-000000000003'
  ),
  '22023',
  'Approval amount range is invalid.',
  'reversed approval amount range is rejected'
);
select throws_ok(
  format(
    'select api.upsert_approval_matrix_step(%L, %L::jsonb, null, %L)',
    '21000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'workflow_definition_id',
      (select response->'entity'->>'id' from wave2_workflow_result),
      'role_id', '51000000-0000-0000-0000-000000000002',
      'step_order', 2, 'minimum_amount', '1000000.000001',
      'maximum_amount', '2000000.000000', 'currency_code', 'LKR',
      'status', 'active'
    )::text,
    '68000000-0000-0000-0000-000000000004'
  ),
  '22023',
  'Approval role is invalid.',
  'foreign-tenant approval role is rejected'
);

-- AC-210: private attachment registration and upload confirmation.
create temporary table wave2_attachment_result as
select api.register_attachment(
  '21000000-0000-0000-0000-000000000001',
  jsonb_build_object(
    'aggregate_type', 'party',
    'aggregate_id', (select response->'entity'->>'id' from wave2_party_result),
    'file_name', 'registration.pdf',
    'mime_type', 'application/pdf',
    'byte_size', 1024
  ),
  '69000000-0000-0000-0000-000000000001'
) as response;
select ok(
  (select response->'entity'->>'object_path' like '21000000-0000-0000-0000-000000000001/%' from wave2_attachment_result),
  'attachment path is generated under the tenant prefix'
);
reset role;
insert into storage.objects (bucket_id, name, owner, metadata) values
  (
    'jentra-attachments',
    (select response->'entity'->>'object_path' from wave2_attachment_result),
    '11000000-0000-0000-0000-000000000001',
    '{"mimetype":"application/pdf","size":1024}'
  ),
  (
    'jentra-attachments',
    '21000000-0000-0000-0000-000000000002/private/foreign.pdf',
    '11000000-0000-0000-0000-000000000002',
    '{"mimetype":"application/pdf","size":1024}'
  );
set local role authenticated;
select lives_ok(
  format(
    'select api.complete_attachment(%L, %L, %L, 1, %L)',
    '21000000-0000-0000-0000-000000000001',
    (select response->'entity'->>'id' from wave2_attachment_result),
    repeat('a', 64),
    '69000000-0000-0000-0000-000000000002'
  ),
  'uploaded attachment can be confirmed ready'
);
select is(
  (select status from api.attachments where name = 'registration.pdf'),
  'ready',
  'completed attachment is ready through the API view'
);
select is(
  (
    select count(*) from storage.objects
    where bucket_id = 'jentra-attachments'
      and name like '21000000-0000-0000-0000-000000000002/%'
  ),
  0::bigint,
  'storage RLS hides another tenant object'
);
select throws_ok(
  $$select api.register_attachment(
    '21000000-0000-0000-0000-000000000001',
    '{"aggregate_type":"party","aggregate_id":"21000000-0000-0000-0000-000000000001","file_name":"../unsafe.exe","mime_type":"application/x-msdownload","byte_size":1024}',
    '69000000-0000-0000-0000-000000000003'
  )$$,
  '22023',
  'Attachment file name is unsafe.',
  'unsafe attachment file name is rejected before MIME processing'
);

-- AC-211 / AC-218: recipient and tenant isolation through API views.
reset role;
insert into workflow.notifications (
  id, tenant_id, recipient_id, notification_type, title, body,
  aggregate_type, aggregate_id, created_by, updated_by
) values
  (
    '71000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001',
    'setup.ready', 'Your setup is ready', 'Wave 2 setup completed.',
    'tenant', '21000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001'
  ),
  (
    '71000000-0000-0000-0000-000000000002',
    '21000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000002',
    'setup.ready', 'Other notification', 'Must remain private.',
    'tenant', '21000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001'
  );
set local role authenticated;
select is(
  (select count(*) from api.my_notifications),
  1::bigint,
  'user sees only their own notification'
);
select lives_ok(
  $$select api.mark_notification_read(
    '21000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000001',
    1,
    '71000000-0000-0000-0000-000000000003'
  )$$,
  'recipient can mark own notification read'
);
select ok(
  (select read_at is not null from api.my_notifications),
  'marked notification has a read timestamp'
);
select throws_ok(
  $$select api.mark_notification_read(
    '21000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000002',
    1,
    '71000000-0000-0000-0000-000000000004'
  )$$,
  'P0002',
  'Notification was not found.',
  'recipient cannot mutate another notification'
);

-- AC-212 / AC-219: bounded atomic import records failure without partial masters.
create temporary table wave2_failed_import as
select api.import_setup_records(
  '21000000-0000-0000-0000-000000000001',
  null,
  'parties', 'csv', 'parties.csv', 128,
  '[{"code":"IMP-1","legal_name":"Valid Import","display_name":"Valid Import","kind":"customer","status":"active"},{"code":"","legal_name":"Invalid Import","display_name":"Invalid Import","kind":"customer","status":"active"}]',
  '72000000-0000-0000-0000-000000000001'
) as response;
select is(
  (select response->'entity'->>'status' from wave2_failed_import),
  'failed',
  'invalid atomic import is recorded as failed'
);
select is(
  (select count(*) from crm.parties where code like 'IMP-%'),
  0::bigint,
  'failed import creates no master rows'
);
select is(
  (select count(*) from core.import_jobs where status = 'failed'),
  1::bigint,
  'failed import job remains attributable'
);
select lives_ok(
  $$select api.import_setup_records(
    '21000000-0000-0000-0000-000000000001',
    null,
    'parties', 'csv', 'parties-corrected.csv', 128,
    '[{"code":"IMP-1","legal_name":"Import One","display_name":"Import One","kind":"customer","status":"active"},{"code":"IMP-2","legal_name":"Import Two","display_name":"Import Two","kind":"supplier","status":"active"}]',
    '72000000-0000-0000-0000-000000000002'
  )$$,
  'corrected bounded import succeeds'
);
select is(
  (select count(*) from crm.parties where code like 'IMP-%'),
  2::bigint,
  'successful import applies all rows'
);

-- AC-214 / AC-215: attributable exports and allowlisted saved reports.
select lives_ok(
  $$select api.create_export_job(
    '21000000-0000-0000-0000-000000000001',
    'products', 'xlsx', '{"status":"active"}',
    '["sku","name","status"]', 1, 'products.xlsx', 4096,
    '73000000-0000-0000-0000-000000000001'
  )$$,
  'bounded export job is recorded'
);
select is(
  (select count(*) from core.export_jobs where status = 'completed'),
  1::bigint,
  'completed export job is attributable'
);
select lives_ok(
  $$select api.upsert_report_definition(
    '21000000-0000-0000-0000-000000000001',
    '{"code":"ACTIVE_PRODUCTS","title":"Active products","source_view":"products","columns":["sku","name","status"],"filters":{"status":"active"},"sort":["sku"],"is_shared":true,"status":"active"}',
    null,
    '74000000-0000-0000-0000-000000000001'
  )$$,
  'allowlisted report definition is accepted'
);
select throws_ok(
  $$select api.upsert_report_definition(
    '21000000-0000-0000-0000-000000000001',
    '{"code":"RAW_SQL","title":"Unsafe","source_view":"pg_catalog.pg_authid","columns":["rolpassword"],"filters":{},"sort":[],"is_shared":false,"status":"active"}',
    null,
    '74000000-0000-0000-0000-000000000002'
  )$$,
  '22023',
  'Report source or columns are not allowed.',
  'arbitrary report source is rejected'
);

-- Cross-tenant denial and complete mutation attribution.
select is(
  (select count(*) from api.parties where tenant_id = '21000000-0000-0000-0000-000000000002'),
  0::bigint,
  'tenant one cannot read tenant two parties'
);
select ok(
  not exists (
    select 1
    from audit.events as e
    where e.actor_id is null or e.tenant_id is null or e.request_id is null
  ),
  'all audit events retain actor tenant and request attribution'
);
select ok(
  not exists (
    select 1
    from core.command_receipts as r
    where r.actor_id = '11000000-0000-0000-0000-000000000001'
      and (r.tenant_id is null or r.request_id is null or r.response is null)
  ),
  'all Wave 2 command receipts are complete'
);

select * from finish();
rollback;
