begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(88);

-- AC-302 / FR-313..FR-318 / NFR-301..NFR-306:
-- exact, tenant-scoped CRM commands, conversion, telemetry, and forecasts.
select is(
  (
    select count(*)
    from information_schema.tables
    where table_schema = 'crm'
      and table_name in ('leads', 'activities', 'opportunities')
  ),
  3::bigint,
  'Wave 3 CRM foundation has lead, activity, and opportunity tables'
);
select ok(
  (
    select count(*) = 4 and bool_and(
      coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']
    )
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'api'
      and c.relkind = 'v'
      and c.relname in (
        'crm_leads', 'crm_activities', 'crm_opportunities',
        'crm_pipeline_entries'
      )
  ),
  'CRM read models are security-invoker API views'
);
select ok(
  (
    select count(*) = 3 and bool_and(c.relrowsecurity and c.relforcerowsecurity)
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and (n.nspname, c.relname) in (
        ('crm', 'leads'), ('crm', 'activities'), ('crm', 'opportunities')
      )
  ),
  'all CRM foundation tables enable and force RLS'
);
select ok(
  (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(20,6)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'crm.leads'::regclass
      and a.attname = 'expected_value' and not a.attisdropped
  )
  and (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(20,6)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'crm.opportunities'::regclass
      and a.attname = 'expected_value' and not a.attisdropped
  )
  and (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(5,2)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'crm.opportunities'::regclass
      and a.attname = 'probability' and not a.attisdropped
  ),
  'commercial values use explicit PostgreSQL numeric precision'
);
select ok(
  (
    select a.attgenerated = 's'
      and format_type(a.atttypid, a.atttypmod) = 'numeric(20,6)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'crm.opportunities'::regclass
      and a.attname = 'weighted_value' and not a.attisdropped
  ),
  'opportunity weighted value is an exact stored generated value'
);
select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'crm'
      and table_name in ('leads', 'activities', 'opportunities')
      and column_name in (
        'request_id', 'command_id', 'correlation_id', 'source_context',
        'client_timestamp', 'created_by', 'updated_by'
      )
  ),
  21::bigint,
  'each CRM aggregate retains full command and actor attribution'
);
select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'crm'
      and table_name in ('parties', 'contacts')
      and column_name in (
        'request_id', 'command_id', 'correlation_id', 'source_context',
        'client_timestamp'
      )
  ),
  10::bigint,
  'conversion-created shared party records can retain Wave 3 attribution'
);
select ok(
  to_regclass('crm.leads_scope_stage_idx') is not null
  and to_regclass('crm.leads_owner_fk_idx') is not null
  and to_regclass('crm.leads_party_fk_idx') is not null
  and to_regclass('crm.leads_contact_fk_idx') is not null
  and to_regclass('crm.leads_converted_opportunity_fk_idx') is not null
  and to_regclass('crm.activities_aggregate_idx') is not null
  and to_regclass('crm.activities_owner_fk_idx') is not null
  and to_regclass('crm.opportunities_scope_forecast_idx') is not null
  and to_regclass('crm.opportunities_owner_fk_idx') is not null
  and to_regclass('crm.opportunities_party_fk_idx') is not null
  and to_regclass('crm.opportunities_contact_fk_idx') is not null
  and to_regclass('crm.opportunities_source_lead_fk_idx') is not null,
  'CRM scope, forecast, activity, and foreign-key paths are indexed'
);
select ok(
  has_table_privilege('authenticated', 'crm.leads', 'SELECT')
  and has_table_privilege('authenticated', 'crm.activities', 'SELECT')
  and has_table_privilege('authenticated', 'crm.opportunities', 'SELECT')
  and not has_table_privilege('authenticated', 'crm.leads', 'INSERT')
  and not has_table_privilege('authenticated', 'crm.activities', 'UPDATE')
  and not has_table_privilege('authenticated', 'crm.opportunities', 'DELETE'),
  'authenticated clients have select-only base-table access'
);
select ok(
  not has_table_privilege('anon', 'crm.leads', 'SELECT')
  and not has_table_privilege('anon', 'api.crm_leads', 'SELECT')
  and not exists (
    select 1
    from information_schema.table_privileges as p
    where p.grantee = 'PUBLIC'
      and p.table_schema in ('crm', 'api')
      and p.table_name in ('leads', 'opportunities', 'crm_leads')
  ),
  'anonymous and PUBLIC roles cannot read CRM data'
);
select has_function(
  'api', 'upsert_lead',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named lead command exists'
);
select has_function(
  'api', 'record_crm_activity',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named activity command exists'
);
select has_function(
  'api', 'upsert_opportunity',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'named opportunity command exists'
);
select has_function(
  'api', 'convert_lead',
  array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
  'idempotent lead conversion command exists'
);
select has_function(
  'api', 'get_crm_pipeline_summary',
  array['uuid','uuid','uuid','date'],
  'as-of pipeline summary function exists'
);
select ok(
  (
    select count(*) = 4 and bool_and(
      p.prosecdef
      and exists (
        select 1
        from unnest(coalesce(p.proconfig, '{}'::text[])) as config
        where config = 'search_path=""'
      )
    )
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and p.proname in (
        'upsert_lead', 'record_crm_activity', 'upsert_opportunity', 'convert_lead'
      )
  ),
  'CRM mutation commands are security definer functions with empty search paths'
);
select ok(
  not exists (
    select 1
    from information_schema.role_routine_grants as g
    where g.grantee in ('PUBLIC', 'anon')
      and g.specific_schema = 'api'
      and g.routine_name in (
        'upsert_lead', 'record_crm_activity', 'upsert_opportunity',
        'convert_lead', 'get_crm_pipeline_summary'
      )
  ),
  'PUBLIC and anon cannot execute CRM API functions'
);
select ok(
  (
    select count(distinct g.routine_name) = 5
    from information_schema.role_routine_grants as g
    where g.grantee = 'authenticated'
      and g.specific_schema = 'api'
      and g.routine_name in (
        'upsert_lead', 'record_crm_activity', 'upsert_opportunity',
        'convert_lead', 'get_crm_pipeline_summary'
      )
  ),
  'authenticated clients can execute only the named CRM API surface'
);
select ok(
  (
    select count(*) = 3 and bool_and(data_type = 'text')
    from information_schema.columns
    where table_schema = 'api'
      and (
        (table_name = 'crm_leads' and column_name = 'expected_value')
        or (table_name = 'crm_opportunities'
          and column_name in ('expected_value', 'probability'))
      )
  ),
  'public CRM read models expose exact commercial numbers as strings'
);
select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'api' and table_name = 'parties'
      and column_name = 'correlation_id'
  )
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'api' and table_name = 'contacts'
      and column_name = 'correlation_id'
  ),
  'shared party API views expose conversion attribution'
);

-- Synthetic tenants and users exercise tenant, entity, branch, and role scope.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '14000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'crm-one@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '14000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'crm-two@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

insert into core.tenants (id, name, slug, default_currency_code, created_by) values
  (
    '24000000-0000-0000-0000-000000000001', 'CRM Tenant One', 'crm-tenant-one',
    'LKR', '14000000-0000-0000-0000-000000000001'
  ),
  (
    '24000000-0000-0000-0000-000000000002', 'CRM Tenant Two', 'crm-tenant-two',
    'USD', '14000000-0000-0000-0000-000000000002'
  );

insert into core.legal_entities (
  id, tenant_id, name, code, currency_code, created_by
) values
  (
    '34000000-0000-0000-0000-000000000011',
    '24000000-0000-0000-0000-000000000001',
    'CRM Entity One', 'CRMONE', 'LKR',
    '14000000-0000-0000-0000-000000000001'
  ),
  (
    '34000000-0000-0000-0000-000000000012',
    '24000000-0000-0000-0000-000000000002',
    'CRM Entity Two', 'CRMTWO', 'USD',
    '14000000-0000-0000-0000-000000000002'
  );

insert into core.branches (
  id, tenant_id, legal_entity_id, name, code, created_by
) values
  (
    '44000000-0000-0000-0000-000000000011',
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    'CRM Head Office', 'CRMHO',
    '14000000-0000-0000-0000-000000000001'
  ),
  (
    '44000000-0000-0000-0000-000000000012',
    '24000000-0000-0000-0000-000000000002',
    '34000000-0000-0000-0000-000000000012',
    'CRM Other Office', 'CRMOT',
    '14000000-0000-0000-0000-000000000002'
  );

insert into core.memberships (id, tenant_id, user_id, status, joined_at) values
  (
    '45000000-0000-0000-0000-000000000011',
    '24000000-0000-0000-0000-000000000001',
    '14000000-0000-0000-0000-000000000001', 'active', now()
  ),
  (
    '45000000-0000-0000-0000-000000000012',
    '24000000-0000-0000-0000-000000000002',
    '14000000-0000-0000-0000-000000000002', 'active', now()
  );

insert into core.roles (
  id, tenant_id, code, name, requires_mfa, is_system
) values (
  '54000000-0000-0000-0000-000000000011',
  '24000000-0000-0000-0000-000000000001',
  'crm_owner', 'CRM owner', true, true
);

insert into core.role_permissions (tenant_id, role_id, permission_code)
select
  '24000000-0000-0000-0000-000000000001',
  '54000000-0000-0000-0000-000000000011',
  p.code
from core.permissions as p
where p.code in (
  'crm.leads.view', 'crm.leads.manage', 'crm.leads.convert',
  'crm.activities.manage', 'crm.opportunities.view',
  'crm.opportunities.manage', 'crm.parties.view', 'crm.parties.manage'
);

insert into core.role_assignments (
  tenant_id, membership_id, role_id, created_by
) values (
  '24000000-0000-0000-0000-000000000001',
  '45000000-0000-0000-0000-000000000011',
  '54000000-0000-0000-0000-000000000011',
  '14000000-0000-0000-0000-000000000001'
);

insert into workflow.workflow_definitions (
  id, tenant_id, legal_entity_id, document_type, name, revision,
  lifecycle, status, created_by, updated_by
) values (
  '64000000-0000-0000-0000-000000000011',
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  'crm_lead', 'CRM lead lifecycle', 1,
  '{
    "states":[
      "draft","submitted","approved","rejected","posted",
      "settled","fulfilled","closed","cancelled","reversed"
    ],
    "transitions":[
      ["draft","submitted"],["draft","cancelled"],
      ["submitted","approved"],["submitted","rejected"],
      ["submitted","cancelled"],["rejected","draft"],
      ["rejected","cancelled"],["approved","posted"],
      ["approved","cancelled"],["posted","closed"],
      ["posted","reversed"]
    ]
  }',
  'active',
  '14000000-0000-0000-0000-000000000001',
  '14000000-0000-0000-0000-000000000001'
);

-- An out-of-tenant row makes view-isolation checks meaningful.
insert into crm.leads (
  id, tenant_id, legal_entity_id, branch_id, code, lead_type, name,
  source, owner_id, stage, stage_entered_at, expected_value,
  currency_code, expected_close_date, qualification_data, status,
  version, request_id, command_id, correlation_id, source_context,
  client_timestamp, created_by, updated_by
) values (
  '74000000-0000-0000-0000-000000000099',
  '24000000-0000-0000-0000-000000000002',
  '34000000-0000-0000-0000-000000000012',
  '44000000-0000-0000-0000-000000000012',
  'LEAD-OTHER', 'organization', 'Other Tenant Prospect', 'referral',
  '14000000-0000-0000-0000-000000000002', 'draft', now(),
  900.000000, 'USD', '2026-12-31', '{}', 'active', 1,
  '91000000-0000-0000-0000-000000000099',
  '92000000-0000-0000-0000-000000000099',
  '93000000-0000-0000-0000-000000000099',
  '{"source":"crm_test_fixture"}', '2026-09-04T01:00:00Z',
  '14000000-0000-0000-0000-000000000002',
  '14000000-0000-0000-0000-000000000002'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"14000000-0000-0000-0000-000000000001","role":"authenticated","email":"crm-one@jentra.test","aal":"aal2"}',
  true
);
set local role authenticated;

create temporary table crm_lead_create_result as
select api.upsert_lead(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000011',
  '83000000-0000-0000-0000-000000000011',
  '2026-09-04T02:00:00Z',
  '{
    "code":"LEAD-001",
    "lead_type":"organization",
    "name":"Acme Trading",
    "contact_name":"Asha Perera",
    "email":"asha@acme.test",
    "phone":"+94-770000001",
    "source":"referral",
    "owner_id":"14000000-0000-0000-0000-000000000001",
    "stage":"draft",
    "expected_value":"1000.100000",
    "currency_code":"LKR",
    "expected_close_date":"2026-12-31",
    "qualification_data":{},
    "status":"active",
    "source_context":{"source":"wave3_crm_pipeline_test"}
  }'::jsonb,
  null
) as response;

select ok(
  (select nullif(response#>>'{entity,id}', '')::uuid is not null
    from crm_lead_create_result),
  'lead command returns its server-assigned aggregate identity'
);
select is(
  (select response#>>'{entity,expected_value}' from crm_lead_create_result),
  '1000.100000',
  'lead response preserves the exact expected-value string'
);
select ok(
  (
    select request_id = (response->>'request_id')::uuid
      and command_id = (response->>'command_id')::uuid
      and correlation_id = (response->>'correlation_id')::uuid
      and source_context->>'source' = 'wave3_crm_pipeline_test'
      and client_timestamp = '2026-09-04T02:00:00Z'::timestamptz
    from crm.leads
    cross join crm_lead_create_result
    where id = (
      select (response#>>'{entity,id}')::uuid from crm_lead_create_result
    )
  ),
  'lead row retains request, command, correlation, source, and client time'
);
reset role;
select ok(
  (
    select count(*) = 4 and count(distinct correlation_id) = 1
    from (
      select correlation_id from core.command_receipts
      where aggregate_id = (
        select (response#>>'{entity,id}')::uuid from crm_lead_create_result
      )
      union all
      select correlation_id from audit.events
      where aggregate_id = (
        select (response#>>'{entity,id}')::uuid from crm_lead_create_result
      )
      union all
      select correlation_id from workflow.process_events
      where document_id = (
        select (response#>>'{entity,id}')::uuid from crm_lead_create_result
      )
      union all
      select correlation_id from core.outbox_events
      where aggregate_id = (
        select (response#>>'{entity,id}')::uuid from crm_lead_create_result
      )
    ) as effects
  ),
  'lead command atomically records receipt, audit, process, and outbox effects'
);
set local role authenticated;
select is(
  api.upsert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000011',
    '83000000-0000-0000-0000-000000000011',
    '2026-09-04T02:00:00Z',
    '{
      "code":"LEAD-001","lead_type":"organization","name":"Acme Trading",
      "contact_name":"Asha Perera","email":"asha@acme.test",
      "phone":"+94-770000001","source":"referral",
      "owner_id":"14000000-0000-0000-0000-000000000001",
      "stage":"draft","expected_value":"1000.100000","currency_code":"LKR",
      "expected_close_date":"2026-12-31","qualification_data":{},
      "status":"active","source_context":{"source":"wave3_crm_pipeline_test"}
    }'::jsonb,
    null
  ),
  (select response from crm_lead_create_result),
  'identical lead retry returns the original response'
);
select throws_ok(
  $$select api.upsert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000011',
    '83000000-0000-0000-0000-000000000011',
    '2026-09-04T02:00:00Z',
    '{"code":"DIFFERENT"}'::jsonb,
    null
  )$$,
  '22023', 'IDEMPOTENCY_MISMATCH',
  'idempotency-key reuse with a different lead payload is rejected'
);
select throws_ok(
  $$select api.upsert_lead(
    '24000000-0000-0000-0000-000000000002',
    '34000000-0000-0000-0000-000000000012',
    '44000000-0000-0000-0000-000000000012',
    '82000000-0000-0000-0000-000000000012',
    '83000000-0000-0000-0000-000000000012',
    '2026-09-04T02:01:00Z', '{}'::jsonb, null
  )$$,
  '42501', 'Permission denied or multi-factor authentication required.',
  'CRM command cannot cross tenant scope'
);
select throws_ok(
  $$select api.upsert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000013',
    '83000000-0000-0000-0000-000000000013',
    '2026-09-04T02:02:00Z',
    '{"code":"LEAD-BAD","lead_type":"person","name":"Bad Amount","source":"web","owner_id":"14000000-0000-0000-0000-000000000001","stage":"draft","expected_value":"10.1234567","currency_code":"LKR","expected_close_date":"2026-12-31","qualification_data":{},"status":"active"}'::jsonb,
    null
  )$$,
  '22023', 'Expected value must be a non-negative decimal string with at most six fractional digits.',
  'lead command rejects an inexact commercial amount'
);
select throws_ok(
  $$select api.upsert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000014',
    '83000000-0000-0000-0000-000000000014',
    '2026-09-04T02:03:00Z',
    (select response->'entity' || jsonb_build_object(
      'stage', 'approved', 'transition_reason', 'Qualified',
      'qualification_data', '{}'::jsonb
    ) from crm_lead_create_result),
    1
  )$$,
  '22023', 'Qualification data is required before approval.',
  'lead cannot be qualified without qualification evidence'
);
select throws_ok(
  $$select api.upsert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000015',
    '83000000-0000-0000-0000-000000000015',
    '2026-09-04T02:04:00Z',
    (select response->'entity' || jsonb_build_object(
      'stage', 'approved', 'transition_reason', 'Skip ahead',
      'qualification_data', '{"need":"confirmed"}'::jsonb
    ) from crm_lead_create_result),
    1
  )$$,
  '55000', 'WORKFLOW_TRANSITION_INVALID',
  'lead stage cannot skip its active workflow'
);

create temporary table crm_lead_submitted_result as
select api.upsert_lead(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000016',
  '83000000-0000-0000-0000-000000000016',
  '2026-09-04T02:05:00Z',
  (select response->'entity' || jsonb_build_object(
    'stage', 'submitted', 'transition_reason', 'Begin qualification',
    'qualification_data', '{"need":"confirmed"}'::jsonb
  ) from crm_lead_create_result),
  1
) as response;
select is(
  (select response#>>'{entity,version}' from crm_lead_submitted_result),
  '2',
  'draft-to-submitted transition advances the lead version'
);
select throws_ok(
  $$select api.upsert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000017',
    '83000000-0000-0000-0000-000000000017',
    '2026-09-04T02:06:00Z',
    (select response->'entity' || jsonb_build_object(
      'stage', 'submitted',
      'qualification_data', '{"need":"confirmed"}'::jsonb
    ) from crm_lead_create_result),
    1
  )$$,
  '40001', 'VERSION_CONFLICT',
  'stale lead update returns the stable version-conflict code'
);

create temporary table crm_lead_approved_result as
select api.upsert_lead(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000018',
  '83000000-0000-0000-0000-000000000018',
  '2026-09-04T02:07:00Z',
  (select response->'entity' || jsonb_build_object(
    'stage', 'approved',
    'transition_reason', 'Budget and authority confirmed',
    'qualification_data', '{"need":"confirmed","budget":"approved"}'::jsonb
  ) from crm_lead_submitted_result),
  2
) as response;
select is(
  (select response#>>'{entity,version}' from crm_lead_approved_result),
  '3',
  'submitted-to-approved transition qualifies the lead at version three'
);
select ok(
  (
    select count(*) = 3
      and count(*) filter (where completed_at is not null) = 2
      and bool_and(workflow_definition_id = '64000000-0000-0000-0000-000000000011')
    from workflow.process_events
    where document_type = 'crm_lead'
      and document_id = (
        select (response#>>'{entity,id}')::uuid from crm_lead_create_result
      )
  ),
  'lead stage history is complete and bound to the active workflow revision'
);

create temporary table crm_activity_result as
select api.record_crm_activity(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000021',
  '83000000-0000-0000-0000-000000000021',
  '2026-09-04T02:10:00Z',
  jsonb_build_object(
    'id', '75000000-0000-0000-0000-000000000011',
    'aggregate_type', 'lead',
    'aggregate_id', (select response#>>'{entity,id}' from crm_lead_create_result),
    'activity_type', 'call', 'subject', 'Qualification call',
    'owner_id', '14000000-0000-0000-0000-000000000001',
    'activity_at', '2026-09-04T02:08:00Z',
    'due_at', '2026-09-04T02:09:00Z',
    'completed_at', '2026-09-04T02:10:00Z',
    'outcome', 'Budget confirmed', 'notes', 'Decision maker attended',
    'status', 'completed',
    'source_context', '{"source":"wave3_crm_pipeline_test"}'::jsonb
  ),
  null
) as response;
select ok(
  (select response#>>'{entity,id}' from crm_activity_result)
    = '75000000-0000-0000-0000-000000000011'
  and (select response#>>'{entity,status}' from crm_activity_result) = 'completed',
  'CRM activity command records a completed customer interaction'
);
select ok(
  (
    select request_id is not null and command_id is not null
      and correlation_id is not null
      and source_context->>'source' = 'wave3_crm_pipeline_test'
      and outcome = 'Budget confirmed'
    from crm.activities
    where id = '75000000-0000-0000-0000-000000000011'
  ),
  'CRM activity retains outcome and complete command attribution'
);
select throws_ok(
  $$select api.record_crm_activity(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000022',
    '83000000-0000-0000-0000-000000000022',
    '2026-09-04T02:11:00Z',
    '{"aggregate_type":"lead","aggregate_id":"74000000-0000-0000-0000-000000000099","activity_type":"call","subject":"Foreign lead","owner_id":"14000000-0000-0000-0000-000000000001","activity_at":"2026-09-04T02:11:00Z","status":"planned"}'::jsonb,
    null
  )$$,
  '22023', 'CRM aggregate is outside the command scope.',
  'CRM activity cannot target another tenant aggregate'
);

create temporary table crm_opportunity_result as
select api.upsert_opportunity(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000031',
  '83000000-0000-0000-0000-000000000031',
  '2026-09-04T02:20:00Z',
  '{"id":"76000000-0000-0000-0000-000000000011","code":"OPP-001","prospect_name":"Independent Prospect","owner_id":"14000000-0000-0000-0000-000000000001","stage":"draft","probability":"40.00","expected_value":"750.250000","currency_code":"LKR","expected_close_date":"2026-11-30","next_action":"Product demonstration","products_of_interest":["ERP-Core"],"forecast_bucket":"pipeline","status":"open","source_context":{"source":"wave3_crm_pipeline_test"}}'::jsonb,
  null
) as response;
create temporary table crm_opportunity_updated_result as
select api.upsert_opportunity(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000034',
  '83000000-0000-0000-0000-000000000034',
  '2026-09-04T02:20:30Z',
  (select response->'entity' || jsonb_build_object(
    'probability', '60.00',
    'next_action', 'Send proposal'
  ) from crm_opportunity_result),
  1
) as response;
select ok(
  (select response#>>'{entity,expected_value}' from crm_opportunity_result) = '750.250000'
  and (select response#>>'{entity,probability}' from crm_opportunity_result) = '40.00'
  and (select response#>>'{entity,weighted_value}' from crm_opportunity_result) = '300.100000'
  and (select response#>>'{entity,version}' from crm_opportunity_updated_result) = '2'
  and (select response#>>'{entity,probability}' from crm_opportunity_updated_result) = '60.00'
  and (select response#>>'{entity,weighted_value}' from crm_opportunity_updated_result) = '450.150000'
  and (select response#>>'{entity,next_action}' from crm_opportunity_updated_result) = 'Send proposal',
  'opportunity creation and revision preserve exact expected, probability, and weighted values'
);
select throws_ok(
  $$select api.upsert_opportunity(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000032',
    '83000000-0000-0000-0000-000000000032',
    '2026-09-04T02:21:00Z',
    '{"code":"OPP-BAD","prospect_name":"Bad Probability","owner_id":"14000000-0000-0000-0000-000000000001","stage":"draft","probability":"50.001","expected_value":"100.000000","currency_code":"LKR","expected_close_date":"2026-11-30","products_of_interest":[],"forecast_bucket":"pipeline","status":"open"}'::jsonb,
    null
  )$$,
  '22023', 'Probability must be a decimal string from zero to one hundred with at most two fractional digits.',
  'opportunity rejects an inexact probability'
);
select throws_ok(
  $$select api.upsert_opportunity(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000033',
    '83000000-0000-0000-0000-000000000033',
    '2026-09-04T02:22:00Z',
    '{"code":"OPP-WON","prospect_name":"Invalid Win","owner_id":"14000000-0000-0000-0000-000000000001","stage":"closed","probability":"80.00","expected_value":"100.000000","currency_code":"LKR","expected_close_date":"2026-11-30","products_of_interest":[],"forecast_bucket":"closed","won_loss_reason":"Selected","status":"won"}'::jsonb,
    null
  )$$,
  '22023', 'Won opportunities require closed stage, 100 probability, closed forecast, and a reason.',
  'won opportunity invariant is enforced'
);

-- A valid but unqualified lead proves conversion is stage-gated.
create temporary table crm_unqualified_lead_result as
select api.upsert_lead(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000041',
  '83000000-0000-0000-0000-000000000041',
  '2026-09-04T02:30:00Z',
  '{"code":"LEAD-002","lead_type":"person","name":"Unqualified Lead","source":"web","owner_id":"14000000-0000-0000-0000-000000000001","stage":"draft","expected_value":"50.000000","currency_code":"LKR","expected_close_date":"2026-12-31","qualification_data":{},"status":"active"}'::jsonb,
  null
) as response;
select throws_ok(
  $$select api.convert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000042',
    '83000000-0000-0000-0000-000000000042',
    '2026-09-04T02:31:00Z',
    jsonb_build_object(
      'lead_id', (select response#>>'{entity,id}' from crm_unqualified_lead_result)
    ),
    1
  )$$,
  '55000', 'LEAD_NOT_QUALIFIED',
  'unqualified lead cannot be converted'
);

create temporary table crm_conversion_result as
select api.convert_lead(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000043',
  '83000000-0000-0000-0000-000000000043',
  '2026-09-04T02:32:00Z',
  jsonb_build_object(
    'lead_id', (select response#>>'{entity,id}' from crm_lead_create_result),
    'party_code', 'CUS-ACME', 'opportunity_code', 'OPP-ACME',
    'opportunity_probability', '50.00',
    'next_action', 'Prepare solution workshop',
    'products_of_interest', '["ERP-Core"]'::jsonb,
    'source_context', '{"source":"wave3_crm_pipeline_test"}'::jsonb
  ),
  3
) as response;
select ok(
  (select response#>>'{entity,status}' from crm_conversion_result) = 'converted'
  and (select response#>>'{entity,stage}' from crm_conversion_result) = 'posted'
  and (select response#>>'{entity,party_id}' from crm_conversion_result) is not null
  and (select response#>>'{entity,contact_id}' from crm_conversion_result) is not null
  and (select response#>>'{entity,opportunity_id}' from crm_conversion_result) is not null,
  'qualified lead conversion returns one linked party, contact, and opportunity'
);
select ok(
  (
    select count(*) = 1 from crm.parties
    where id = (select (response#>>'{entity,party_id}')::uuid from crm_conversion_result)
  )
  and (
    select count(*) = 1 from crm.contacts
    where id = (select (response#>>'{entity,contact_id}')::uuid from crm_conversion_result)
  )
  and (
    select count(*) = 1 from crm.opportunities
    where id = (select (response#>>'{entity,opportunity_id}')::uuid from crm_conversion_result)
      and source_lead_id = (
        select (response#>>'{entity,id}')::uuid from crm_lead_create_result
      )
  ),
  'conversion persists exactly one linked aggregate of each kind'
);
select ok(
  (
    select count(*) = 3 and count(distinct request_id) = 1
      and count(distinct command_id) = 1 and count(distinct correlation_id) = 1
      and bool_and(source_context->>'source' = 'wave3_crm_pipeline_test')
    from (
      select request_id, command_id, correlation_id, source_context
      from crm.parties
      where id = (select (response#>>'{entity,party_id}')::uuid from crm_conversion_result)
      union all
      select request_id, command_id, correlation_id, source_context
      from crm.contacts
      where id = (select (response#>>'{entity,contact_id}')::uuid from crm_conversion_result)
      union all
      select request_id, command_id, correlation_id, source_context
      from crm.opportunities
      where id = (select (response#>>'{entity,opportunity_id}')::uuid from crm_conversion_result)
    ) as converted
  ),
  'conversion-created records share complete command attribution'
);

create temporary table crm_conversion_retry_result as
select api.convert_lead(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  '82000000-0000-0000-0000-000000000044',
  '83000000-0000-0000-0000-000000000044',
  '2026-09-04T02:33:00Z',
  jsonb_build_object(
    'lead_id', (select response#>>'{entity,id}' from crm_lead_create_result),
    'source_context', '{"source":"wave3_crm_pipeline_test"}'::jsonb
  ),
  3
) as response;
select ok(
  (select response#>>'{entity,party_id}' from crm_conversion_retry_result)
    = (select response#>>'{entity,party_id}' from crm_conversion_result)
  and (select response#>>'{entity,contact_id}' from crm_conversion_retry_result)
    = (select response#>>'{entity,contact_id}' from crm_conversion_result)
  and (select response#>>'{entity,opportunity_id}' from crm_conversion_retry_result)
    = (select response#>>'{entity,opportunity_id}' from crm_conversion_result),
  'second conversion command returns the original linked aggregates'
);
select ok(
  (select count(*) from crm.parties where code = 'CUS-ACME') = 1
  and (
    select count(*) from crm.contacts
    where party_id = (select (response#>>'{entity,party_id}')::uuid from crm_conversion_result)
  ) = 1
  and (
    select count(*) from crm.opportunities
    where source_lead_id = (
      select (response#>>'{entity,id}')::uuid from crm_lead_create_result
    )
  ) = 1,
  'semantic conversion retry creates no duplicate party, contact, or opportunity'
);

create temporary table crm_pipeline_result as
select api.get_crm_pipeline_summary(
  '24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011',
  '44000000-0000-0000-0000-000000000011',
  current_date
) as summary;
select ok(
  (select summary->>'as_of_date' from crm_pipeline_result) = current_date::text
  and (select summary#>>'{currency_totals,0,currency_code}' from crm_pipeline_result) = 'LKR'
  and (select summary#>>'{currency_totals,0,opportunity_count}' from crm_pipeline_result) = '2'
  and (select summary#>>'{currency_totals,0,expected_value}' from crm_pipeline_result) = '1750.350000'
  and (select summary#>>'{currency_totals,0,weighted_value}' from crm_pipeline_result) = '950.200000'
  and (select summary#>>'{conversion,total_leads}' from crm_pipeline_result) = '2'
  and (select summary#>>'{conversion,converted_leads}' from crm_pipeline_result) = '1'
  and (select summary#>>'{conversion,conversion_rate}' from crm_pipeline_result) = '50.000000'
  and (select summary#>>'{activity_recency,activity_count}' from crm_pipeline_result) = '1'
  and (select summary#>>'{aging,age_basis}' from crm_pipeline_result) = 'created_at'
  and (select summary#>>'{aging,stale_after_days}' from crm_pipeline_result) = '90'
  and (select summary#>>'{aging,open_opportunity_count}' from crm_pipeline_result) = '2'
  and (select summary#>>'{aging,average_age_days}' from crm_pipeline_result) = '0.000000'
  and (select summary#>>'{aging,stale_opportunity_count}' from crm_pipeline_result) = '0',
  'pipeline summary is as-of, currency-separated, exact, and operationally complete'
);

select ok(
  (select count(*) from api.crm_leads
    where tenant_id = '24000000-0000-0000-0000-000000000001') = 2
  and (select count(*) from api.crm_leads
    where tenant_id = '24000000-0000-0000-0000-000000000002') = 0
  and (select count(*) from api.crm_opportunities
    where tenant_id = '24000000-0000-0000-0000-000000000001') = 2,
  'security-invoker CRM views show permitted rows and hide another tenant'
);

reset role;
update core.memberships
set status = 'revoked'
where id = '45000000-0000-0000-0000-000000000011';
set local role authenticated;
select ok(
  (select count(*) from api.crm_leads
    where tenant_id = '24000000-0000-0000-0000-000000000001') = 0
  and (select count(*) from api.crm_activities
    where tenant_id = '24000000-0000-0000-0000-000000000001') = 0
  and (select count(*) from api.crm_opportunities
    where tenant_id = '24000000-0000-0000-0000-000000000001') = 0,
  'revoked membership immediately removes CRM read visibility'
);
select throws_ok(
  $$select api.upsert_lead(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011',
    '82000000-0000-0000-0000-000000000050',
    '83000000-0000-0000-0000-000000000050',
    '2026-09-04T03:00:00Z', '{}'::jsonb, null
  )$$,
  '42501', 'Permission denied or multi-factor authentication required.',
  'revoked membership cannot execute a CRM mutation command'
);
reset role;

-- AC-302 review regressions. Re-enable the fixture member after the revocation
-- assertions; every change in this file is still rolled back.
update core.memberships set status = 'active'
where id = '45000000-0000-0000-0000-000000000011';

create function pg_temp.crm_review_command(
  p_name text, p_payload jsonb, p_version bigint default null,
  p_entity uuid default '34000000-0000-0000-0000-000000000011',
  p_branch uuid default '44000000-0000-0000-0000-000000000011',
  p_command uuid default gen_random_uuid(), p_key uuid default gen_random_uuid()
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_result jsonb;
begin
  execute format('select api.%I($1,$2,$3,$4,$5,$6,$7,$8)', p_name)
  into v_result using '24000000-0000-0000-0000-000000000001'::uuid,
    p_entity, p_branch, p_command, p_key,
    '2026-09-04T04:00:00Z'::timestamptz, p_payload, p_version;
  return v_result;
end;
$$;

create function pg_temp.crm_review_summary(p_date date)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
  return api.get_crm_pipeline_summary(
    '24000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000011',
    '44000000-0000-0000-0000-000000000011', p_date);
exception when others then
  return jsonb_build_object('test_sqlstate', sqlstate, 'test_error', sqlerrm);
end;
$$;

set local role authenticated;
select throws_ok(
  $$select pg_temp.crm_review_command('upsert_lead',
    (select ((response->'entity') - 'id') || '{"code":"NUMERIC-LEAD","expected_value":0.1}'::jsonb
     from crm_lead_create_result))$$,
  '22023', 'Expected value must be a decimal string.',
  'lead input rejects JSON numbers before decimal coercion'
);
select throws_ok(
  $$select pg_temp.crm_review_command('upsert_opportunity',
    (select ((response->'entity') - 'id') || '{"code":"NUMERIC-OPP","probability":33.33}'::jsonb
     from crm_opportunity_result))$$,
  '22023', 'Probability must be a decimal string.',
  'opportunity input rejects binary-number-shaped probability payloads'
);
select throws_ok(
  $$select pg_temp.crm_review_command('convert_lead',
    (select jsonb_build_object('lead_id',response#>>'{entity,id}',
       'opportunity_probability',33.33) from crm_lead_create_result),3)$$,
  '22023', 'Opportunity probability must be a decimal string.',
  'conversion probability also requires an exact string'
);

reset role;
insert into workflow.workflow_definitions (
  id, tenant_id, legal_entity_id, document_type, name, revision,
  lifecycle, status, created_by, updated_by
)
select '64000000-0000-0000-0000-000000000022', tenant_id, null,
  document_type, 'Tenant fallback workflow', 2, lifecycle, status,
  created_by, updated_by
from workflow.workflow_definitions where id='64000000-0000-0000-0000-000000000011';
set local role authenticated;
create temporary table crm_scoped_workflow_result as
select pg_temp.crm_review_command('upsert_lead',
  (select ((response->'entity') - 'id') || '{"code":"SCOPE-LEAD"}'::jsonb
   from crm_lead_create_result)) as response;
select is(
  (select workflow_definition_id from workflow.process_events
   where document_id=(select (response#>>'{entity,id}')::uuid from crm_scoped_workflow_result)),
  '64000000-0000-0000-0000-000000000011'::uuid,
  'entity-specific qualification workflow outranks the tenant fallback'
);

select is(
  pg_temp.crm_review_command('convert_lead',
    jsonb_build_object('lead_id',(select response#>>'{entity,id}' from crm_lead_create_result),
      'party_code','CUS-ACME','opportunity_code','OPP-ACME',
      'opportunity_probability','50.00','next_action','Prepare solution workshop',
      'products_of_interest','["ERP-Core"]'::jsonb,
      'source_context','{"source":"wave3_crm_pipeline_test"}'::jsonb),
    3, p_command=>'82000000-0000-0000-0000-000000000143',
    p_key=>'83000000-0000-0000-0000-000000000143'),
  pg_temp.crm_review_command('convert_lead',
    jsonb_build_object('lead_id',(select response#>>'{entity,id}' from crm_lead_create_result),
      'party_code','CUS-ACME','opportunity_code','OPP-ACME',
      'opportunity_probability','50.00','next_action','Prepare solution workshop',
      'products_of_interest','["ERP-Core"]'::jsonb,
      'source_context','{"source":"wave3_crm_pipeline_test"}'::jsonb),
    3, p_command=>'82000000-0000-0000-0000-000000000143',
    p_key=>'83000000-0000-0000-0000-000000000143'),
  'identical conversion envelope replays its byte-equivalent JSON response'
);
select throws_ok(
  $$select pg_temp.crm_review_command('convert_lead',
    (select jsonb_build_object('lead_id',response#>>'{entity,id}','party_code','CHANGED')
      from crm_lead_create_result),3,
    p_command=>'82000000-0000-0000-0000-000000000143',
    p_key=>'83000000-0000-0000-0000-000000000143')$$,
  '22023','IDEMPOTENCY_MISMATCH','conversion replay rejects a changed payload'
);

reset role;
select ok(
  (select count(*)=2 and count(distinct correlation_id)=1
   from workflow.process_events where command_id='82000000-0000-0000-0000-000000000043'),
  'conversion records both the completed lead stage and initial opportunity stage'
);
select ok(
  (select count(*)=1 and bool_and(actor_id='14000000-0000-0000-0000-000000000001'
    and legal_entity_id='34000000-0000-0000-0000-000000000011'
    and branch_id='44000000-0000-0000-0000-000000000011')
   from audit.events where command_id='82000000-0000-0000-0000-000000000043')
  and (select count(*)=1 from core.command_receipts
   where command_id='82000000-0000-0000-0000-000000000043')
  and (select count(*)=1 from core.outbox_events
   where command_id='82000000-0000-0000-0000-000000000043'),
  'conversion audit, receipt, and outbox retain the authenticated actor and scope'
);

-- Same-tenant scope isolation is distinct from cross-tenant isolation.
insert into core.legal_entities(id,tenant_id,name,code,currency_code,created_by)
values ('34000000-0000-0000-0000-000000000013',
 '24000000-0000-0000-0000-000000000001','Second entity','CRMSECOND','LKR',
 '14000000-0000-0000-0000-000000000001');
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
 ('44000000-0000-0000-0000-000000000013','24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000013','Second entity branch','CRME2',
  '14000000-0000-0000-0000-000000000001'),
 ('44000000-0000-0000-0000-000000000014','24000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000011','Sibling branch','CRMSIB',
  '14000000-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$select pg_temp.crm_review_command('upsert_lead','{}',null,
   p_branch=>'44000000-0000-0000-0000-000000000013')$$,
  '42501','BRANCH_SCOPE_INVALID','command rejects a branch from another legal entity'
);
select throws_ok(
  $$select pg_temp.crm_review_command('record_crm_activity',
   (select (response->'entity') - 'id' from crm_activity_result),null,
   p_branch=>'44000000-0000-0000-0000-000000000014')$$,
  '22023','CRM aggregate is outside the command scope.',
  'activity cannot attach a lead from a sibling branch'
);
select throws_ok(
  $$select pg_temp.crm_review_command('convert_lead',
   (select jsonb_build_object('lead_id',response#>>'{entity,id}') from crm_lead_create_result),3,
   p_branch=>'44000000-0000-0000-0000-000000000014')$$,
  'P0002','Lead was not found.','conversion does not disclose a sibling-branch lead'
);
create temporary table crm_sibling_result as
select pg_temp.crm_review_command('upsert_opportunity',
 (select ((response->'entity') - 'id') || '{"code":"SIBLING-OPP"}'::jsonb from crm_opportunity_result),
 null,p_branch=>'44000000-0000-0000-0000-000000000014') as response;
reset role;
update core.role_assignments set legal_entity_id='34000000-0000-0000-0000-000000000011',
 branch_id='44000000-0000-0000-0000-000000000011'
where tenant_id='24000000-0000-0000-0000-000000000001';
set local role authenticated;
select is((select count(*) from api.crm_opportunities
 where id=(select (response#>>'{entity,id}')::uuid from crm_sibling_result)),0::bigint,
 'forced RLS hides sibling-branch opportunities from a branch-scoped role');
select throws_ok(
 $$select pg_temp.crm_review_command('upsert_opportunity','{}',null,
 p_entity=>'34000000-0000-0000-0000-000000000013',
 p_branch=>'44000000-0000-0000-0000-000000000013')$$,
 '42501','Permission denied or multi-factor authentication required.',
 'branch-scoped role cannot mutate a different legal entity');
reset role;
update core.role_assignments set legal_entity_id=null,branch_id=null
where tenant_id='24000000-0000-0000-0000-000000000001';

-- Seed one older version as a trusted test fixture, then revise it today.
insert into crm.opportunities (
 id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,stage,
 probability,expected_value,currency_code,expected_close_date,request_id,
 command_id,correlation_id,client_timestamp,created_by,updated_by,created_at,updated_at
) values (
 '76000000-0000-0000-0000-000000000055','24000000-0000-0000-0000-000000000001',
 '34000000-0000-0000-0000-000000000011','44000000-0000-0000-0000-000000000011',
 'HISTORICAL-OPP','Historical prospect','14000000-0000-0000-0000-000000000001','draft',
 25.00,10.100000,'USD',current_date+30,gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
 now(),'14000000-0000-0000-0000-000000000001','14000000-0000-0000-0000-000000000001',
 (current_date-10)::timestamp at time zone 'UTC',
 (current_date-10)::timestamp at time zone 'UTC');
set local role authenticated;
create temporary table crm_historical_before as
select pg_temp.crm_review_summary(current_date-1) as summary;
select pg_temp.crm_review_command('upsert_opportunity',
 (select to_jsonb(o) || '{"expected_value":"20.100000","probability":"75.00"}'::jsonb
  from api.crm_opportunities o where id='76000000-0000-0000-0000-000000000055'),1);
select is(pg_temp.crm_review_summary(current_date-1),
 (select summary from crm_historical_before),
 'later opportunity revisions cannot rewrite a prior as-of pipeline summary');
select is((select summary#>>'{currency_totals,0,weighted_value}' from crm_historical_before),
 '2.525000','historical weighted value is exact and excludes later-created rows');

select pg_temp.crm_review_command('upsert_opportunity',
 (select ((response->'entity') - 'id') ||
 '{"code":"LARGE-USD-1","currency_code":"USD","expected_value":"90071992547409.123456","probability":"33.33"}'::jsonb
 from crm_opportunity_result));
select pg_temp.crm_review_command('upsert_opportunity',
 (select ((response->'entity') - 'id') ||
 '{"code":"LARGE-USD-2","currency_code":"USD","expected_value":"90071992547409.123456","probability":"33.33"}'::jsonb
 from crm_opportunity_result));
select is(pg_temp.crm_review_summary(current_date)#>>'{currency_totals,1,expected_value}',
 '180143985094838.346912','currency totals support sums larger than one numeric(20,6) row');
select is(pg_temp.crm_review_summary(current_date)#>>'{currency_totals,1,weighted_value}',
 '60041990232117.996696','large probability-weighted sums preserve all six decimal places');
select is(pg_temp.crm_review_summary(current_date)#>>'{currency_totals,0,expected_value}',
 '1750.350000','USD values never enter the LKR pipeline total');
select ok(to_regclass('crm.pipeline_history') is not null,
 'immutable CRM pipeline version history exists for reproducible as-of reports');
select throws_ok($$select api.get_crm_pipeline_summary(
 '24000000-0000-0000-0000-000000000001',null,null,current_date)$$,
 '22023','Legal entity is required.','pipeline summary requires an explicit legal entity');
reset role;

-- Conversion linkage is durable, not an editable pointer on the opportunity.
set local role authenticated;
select throws_ok($$select pg_temp.crm_review_command('upsert_opportunity',
 (select to_jsonb(o) || '{"source_lead_id":null}'::jsonb
  from api.crm_opportunities o where id=
   (select (response#>>'{entity,opportunity_id}')::uuid from crm_conversion_result)),1)$$,
 '55000','CONVERSION_LINKS_IMMUTABLE','opportunity edits cannot detach a converted lead');

-- Lead-only visibility must not expose opportunity activity content.
select pg_temp.crm_review_command('record_crm_activity',
 (select ((response->'entity') - 'id') || jsonb_build_object(
  'aggregate_type','opportunity','aggregate_id',
  (select response#>>'{entity,id}' from crm_opportunity_result),
  'subject','Opportunity confidential activity') from crm_activity_result));
reset role;
delete from core.role_permissions where role_id='54000000-0000-0000-0000-000000000011'
 and permission_code <> 'crm.leads.view';
set local role authenticated;
select is((select count(*) from api.crm_activities where aggregate_type='opportunity'),
 0::bigint,'lead-only capability cannot read opportunity activities');
select is((select count(*) from api.crm_activities where aggregate_type='lead'),
 1::bigint,'lead-only capability retains permitted lead activity visibility');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select '24000000-0000-0000-0000-000000000001',
 '54000000-0000-0000-0000-000000000011',code from core.permissions
where code in ('crm.leads.manage','crm.leads.convert','crm.activities.manage',
 'crm.opportunities.view','crm.opportunities.manage','crm.parties.view','crm.parties.manage');
set local role authenticated;
create temporary table crm_review_submitted as
select pg_temp.crm_review_command('upsert_lead',
 (select response->'entity' || '{"stage":"submitted","transition_reason":"Review"}'::jsonb
 from crm_scoped_workflow_result),1) as response;
create temporary table crm_review_qualified as
select pg_temp.crm_review_command('upsert_lead',
 (select response->'entity' || '{"stage":"approved","qualification_data":{"need":"CRM"},
 "transition_reason":"Qualified","status":"inactive"}'::jsonb from crm_review_submitted),2) as response;
select throws_ok($$select pg_temp.crm_review_command('convert_lead',
 (select jsonb_build_object('lead_id',response#>>'{entity,id}') from crm_review_qualified),3)$$,
 '55000','LEAD_NOT_ACTIVE','inactive qualified leads cannot be converted');
create temporary table crm_review_active as
select pg_temp.crm_review_command('upsert_lead',
 (select response->'entity' || '{"status":"active"}'::jsonb from crm_review_qualified),3) as response;
select throws_ok($$select pg_temp.crm_review_command('convert_lead',
 (select jsonb_build_object('lead_id',response#>>'{entity,id}') from crm_review_active),3)$$,
 '40001','VERSION_CONFLICT','first conversion requires the current lead version');

-- Force a late failure after all conversion writes, proving transactional rollback.
reset role;
create function pg_temp.crm_fail_outbox() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.command_id='82000000-0000-0000-0000-000000000199' then
  raise exception using errcode='P0001',message='CRM_TEST_OUTBOX_FAILURE';
 end if;
 return new;
end;
$$;
create trigger crm_review_outbox_failure before insert on core.outbox_events
for each row execute function pg_temp.crm_fail_outbox();
set local role authenticated;
select throws_ok($$select pg_temp.crm_review_command('convert_lead',
 (select jsonb_build_object('lead_id',response#>>'{entity,id}','party_code','ROLLBACK-CUSTOMER')
 from crm_review_active),4,p_command=>'82000000-0000-0000-0000-000000000199')$$,
 'P0001','CRM_TEST_OUTBOX_FAILURE','conversion surfaces injected late outbox failure');
reset role;
select ok(
 not exists(select 1 from crm.parties where code='ROLLBACK-CUSTOMER')
 and not exists(select 1 from crm.contacts where command_id='82000000-0000-0000-0000-000000000199')
 and not exists(select 1 from crm.opportunities where command_id='82000000-0000-0000-0000-000000000199')
 and not exists(select 1 from audit.events where command_id='82000000-0000-0000-0000-000000000199')
 and not exists(select 1 from workflow.process_events where command_id='82000000-0000-0000-0000-000000000199')
 and not exists(select 1 from core.command_receipts where command_id='82000000-0000-0000-0000-000000000199')
 and not exists(select 1 from core.outbox_events where command_id='82000000-0000-0000-0000-000000000199')
 and (select stage='approved' and status='active' and version=4 and converted_opportunity_id is null
 from crm.leads where id=(select (response#>>'{entity,id}')::uuid from crm_review_active)),
 'failed conversion leaves no aggregate, audit, telemetry, receipt, or outbox partial effects');
set local role authenticated;
create temporary table crm_review_linked as
select pg_temp.crm_review_command('convert_lead',
 (select jsonb_build_object('lead_id',response#>>'{entity,id}',
 'party_id',(select response#>>'{entity,party_id}' from crm_conversion_result),
 'contact_id',(select response#>>'{entity,contact_id}' from crm_conversion_result))
 from crm_review_active),4) as response;
select ok(
 (select response#>>'{entity,party_id}' from crm_review_linked)=
 (select response#>>'{entity,party_id}' from crm_conversion_result)
 and (select response#>>'{entity,contact_id}' from crm_review_linked)=
 (select response#>>'{entity,contact_id}' from crm_conversion_result)
 and (select count(*) from crm.parties where code='CUS-ACME')=1
 and (select count(*) from crm.contacts where party_id=
 (select (response#>>'{entity,party_id}')::uuid from crm_conversion_result))=1,
 'conversion links selected existing party and contact without duplication');
reset role;

-- History itself must not introduce a read or mutation bypass.
select ok(
 (select relrowsecurity and relforcerowsecurity from pg_class
  where oid='crm.pipeline_history'::regclass)
 and (select reloptions @> array['security_invoker=true'] from pg_class
  where oid='api.crm_pipeline_history'::regclass),
 'pipeline history forces RLS and exposes a security-invoker API view');
select ok(
 has_table_privilege('authenticated','crm.pipeline_history','SELECT')
 and not has_table_privilege('authenticated','crm.pipeline_history','INSERT')
 and not has_table_privilege('authenticated','crm.pipeline_history','UPDATE')
 and not has_table_privilege('authenticated','crm.pipeline_history','DELETE')
 and not has_table_privilege('anon','api.crm_pipeline_history','SELECT')
 and not has_function_privilege('authenticated','crm.wave3_pipeline_summary_base(uuid,uuid,uuid,date)','EXECUTE')
 and not has_function_privilege('authenticated','crm.wave3_capture_pipeline_history()','EXECUTE')
 and (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
  where oid='crm.wave3_capture_pipeline_history()'::regprocedure),
 'history has read-only grants, guarded trigger execution, and no stale summary bypass');
select ok(
 (select count(*)=2 and bool_and(
 actor_id='14000000-0000-0000-0000-000000000001'
 and request_id=(select (response->>'request_id')::uuid from crm_conversion_result)
 and correlation_id=(select (response->>'correlation_id')::uuid from crm_conversion_result)
 and jsonb_typeof(snapshot->'expected_value')='string')
 from crm.pipeline_history where command_id='82000000-0000-0000-0000-000000000043'),
 'conversion history preserves exact strings and authenticated command attribution');
select is((select count(*) from crm.pipeline_history
 where command_id='82000000-0000-0000-0000-000000000199'),0::bigint,
 'late conversion failure also rolls back pipeline history');
select throws_ok($$update crm.pipeline_history set recorded_at=recorded_at-interval '1 day'$$,
 '55000','CRM_PIPELINE_HISTORY_IMMUTABLE','even trusted history updates are rejected');
select throws_ok($$delete from crm.pipeline_history$$,
 '55000','CRM_PIPELINE_HISTORY_IMMUTABLE','even trusted history deletions are rejected');
update core.role_assignments set legal_entity_id='34000000-0000-0000-0000-000000000011',
 branch_id='44000000-0000-0000-0000-000000000011'
where tenant_id='24000000-0000-0000-0000-000000000001';
set local role authenticated;
select is((select count(*) from api.crm_pipeline_history
 where branch_id in ('44000000-0000-0000-0000-000000000012','44000000-0000-0000-0000-000000000014')),
 0::bigint,'history hides both foreign tenants and sibling branches');
create temporary table crm_timezone_before as
select pg_temp.crm_review_summary(current_date-1)->'currency_totals' as totals;
set local timezone='Pacific/Honolulu';
select is(pg_temp.crm_review_summary((now() at time zone 'UTC')::date-1)->'currency_totals',
 (select totals from crm_timezone_before),'UTC as-of totals do not depend on connection timezone');
set local timezone='UTC';
reset role;
delete from core.role_permissions where role_id='54000000-0000-0000-0000-000000000011'
 and permission_code <> 'crm.leads.view';
set local role authenticated;
select ok(
 (select count(*) from api.crm_pipeline_history where entity_type='lead')>0
 and (select count(*) from api.crm_pipeline_history where entity_type='opportunity')=0
 and (select count(*) from api.crm_pipeline_history
  where entity_type='activity' and subject_type='opportunity')=0,
 'history enforces aggregate-specific capabilities as well as row scope');
reset role;
update core.memberships set status='revoked'
where id='45000000-0000-0000-0000-000000000011';
set local role authenticated;
select is((select count(*) from api.crm_pipeline_history),0::bigint,
 'revoked membership immediately hides historical pipeline data');
reset role;

select * from finish(true);
rollback;
