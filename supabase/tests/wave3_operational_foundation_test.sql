begin;
-- 20260924185321_wave3_period_governance forbids a direct period state change;
-- fixture steps take the governed event path wave3_period_test.sql uses.
create function pg_temp.fixture_period_state(p_id uuid,p_target text) returns void
language plpgsql as $fixture_period$
declare p finance.fiscal_periods%rowtype;next_state text;claims text;
begin
 claims:=current_setting('request.jwt.claims',true);
 loop
  select * into p from finance.fiscal_periods where id=p_id;
  exit when not found or p.state=p_target;
  if auth.uid() is null then
   perform set_config('request.jwt.claims',jsonb_build_object('sub',p.created_by)::text,true);
  end if;
  next_state:=case p.state when 'open' then 'soft_locked' when 'soft_locked' then 'hard_locked' else 'open' end;
  insert into finance.period_events(id,tenant_id,legal_entity_id,period_id,action,from_state,to_state,period_version,
   reason,exceptions,actor_id,transaction_id)
  values(gen_random_uuid(),p.tenant_id,p.legal_entity_id,p.id,
   case next_state when 'soft_locked' then 'soft_lock' when 'hard_locked' then 'hard_lock' else 'reopened' end,
   p.state,next_state,p.version,'Synthetic fixture period state','[]',auth.uid(),txid_current());
  update finance.fiscal_periods set state=next_state where id=p.id;
 end loop;
 perform set_config('request.jwt.claims',coalesce(claims,''),true);
end $fixture_period$;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(50);

-- AC-301 / FR-301..FR-312 / NFR-301..NFR-306:
-- shared Wave 3 command, approval, telemetry, RLS, and attribution contracts.
select has_table('workflow', 'process_events', 'process telemetry table exists');
select has_table('workflow', 'approval_decisions', 'append-only approval decisions exist');
select ok(
  (
    select count(*) = 3 and bool_and(
      coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']
    )
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'api'
      and c.relkind = 'v'
      and c.relname in ('approval_requests', 'approval_decisions', 'process_events')
  ),
  'Wave 3 workflow read models are security-invoker API views'
);
select ok(
  (
    select count(*) = 4
    from information_schema.columns
    where table_schema = 'core' and table_name = 'command_receipts'
      and column_name in ('command_id', 'correlation_id', 'aggregate_type', 'aggregate_id')
  ),
  'command receipts retain command, correlation, and aggregate identity'
);
select ok(
  (
    select count(*) = 11
    from information_schema.columns
    where (
      table_schema = 'core' and table_name = 'outbox_events'
      and column_name in ('request_id', 'actor_id', 'command_id', 'correlation_id')
    ) or (
      table_schema = 'workflow' and table_name = 'notifications'
      and column_name in (
        'legal_entity_id', 'branch_id', 'actor_id', 'request_id',
        'command_id', 'correlation_id', 'source_context'
      )
    )
  ),
  'outbox events and notifications retain complete command attribution'
);
select ok(
  (
    select count(*) = 2
    from information_schema.columns
    where table_schema = 'audit' and table_name = 'events'
      and column_name in ('command_id', 'correlation_id')
  ),
  'audit events retain command and correlation identity'
);
select ok(
  (
    select count(*) = 4
    from information_schema.columns
    where table_schema = 'workflow' and table_name = 'approval_requests'
      and column_name in (
        'workflow_definition_id', 'workflow_revision', 'command_id', 'correlation_id'
      )
  ),
  'approval requests snapshot their workflow and command context'
);
select ok(
  (
    select count(*) = 7 and bool_and(c.relrowsecurity and c.relforcerowsecurity)
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and (n.nspname, c.relname) in (
        ('core', 'command_receipts'),
        ('core', 'outbox_events'),
        ('audit', 'events'),
        ('workflow', 'notifications'),
        ('workflow', 'approval_requests'),
        ('workflow', 'approval_decisions'),
        ('workflow', 'process_events')
      )
  ),
  'all Wave 3 command-history tables enable and force RLS'
);
select ok(
  not has_table_privilege('authenticated', 'workflow.process_events', 'INSERT')
  and not has_table_privilege('authenticated', 'workflow.approval_decisions', 'UPDATE'),
  'desktop roles cannot mutate workflow history directly'
);
select ok(
  not exists (
    select 1
    from information_schema.role_routine_grants as g
    where g.grantee in ('PUBLIC', 'anon')
      and g.specific_schema in ('core', 'finance')
      and g.routine_name like 'wave3_%'
  ),
  'PUBLIC and anon cannot execute Wave 3 internal routines'
);
select ok(
  not exists (
    select 1
    from information_schema.role_routine_grants as g
    where g.grantee = 'authenticated'
      and g.specific_schema in ('core', 'finance')
      and g.routine_name like 'wave3_%'
  ),
  'authenticated clients cannot bypass named API commands through Wave 3 helpers'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('core', 'finance')
      and p.proname like 'wave3_%'
      and p.prosecdef
      and not exists (
        select 1
        from unnest(coalesce(p.proconfig, '{}'::text[])) as config
        where config = 'search_path=""'
      )
  ),
  'Wave 3 security-definer helpers use an empty search path'
);
select is(
  (
    select count(*)
    from core.permissions
    where code in (
      'crm.leads.view', 'crm.leads.manage', 'crm.leads.convert',
      'crm.activities.manage', 'crm.opportunities.view', 'crm.opportunities.manage',
      'sales.quotations.view', 'sales.quotations.manage',
      'sales.orders.view', 'sales.orders.manage',
      'sales.deliveries.post', 'sales.invoices.view', 'sales.invoices.manage',
      'sales.invoices.post', 'sales.returns.post', 'sales.price.override',
      'procurement.requisitions.manage', 'procurement.rfq.manage',
      'procurement.orders.view', 'procurement.orders.manage',
      'procurement.receipts.post', 'procurement.bills.view',
      'procurement.bills.manage', 'procurement.bills.post',
      'procurement.returns.post', 'inventory.stock.view',
      'inventory.reservations.manage', 'inventory.transfers.post',
      'inventory.adjustments.post', 'inventory.valuation.post',
      'inventory.cost.view', 'inventory.stock.override',
      'finance.receipts.post', 'finance.payments.manage', 'finance.payments.post',
      'finance.journals.post', 'finance.reversals.post', 'finance.bank.manage',
      'finance.bank.import', 'finance.bank.reconcile', 'finance.bank.adjust',
      'finance.period.close', 'finance.period.reopen', 'finance.fx.post',
      'finance.budgets.manage', 'workflow.approvals.view',
      'workflow.approvals.decide', 'workflow.process.view'
    )
  ),
  48::bigint,
  'Wave 3 permission vocabulary separates sensitive commercial and finance actions'
);
select has_function(
  'core', 'wave3_request_hash',
  array['text', 'uuid', 'uuid', 'uuid', 'uuid', 'jsonb', 'bigint'],
  'canonical Wave 3 request hashing exists'
);
select has_function(
  'core', 'wave3_replay',
  array['uuid', 'text', 'uuid', 'uuid', 'text'],
  'serialized Wave 3 idempotency replay exists'
);
select has_function(
  'core', 'wave3_assert_expected_version',
  array['bigint', 'bigint', 'jsonb'],
  'structured optimistic-version assertion exists'
);
select has_function(
  'core', 'wave3_require_scope',
  array['uuid', 'text', 'uuid', 'uuid'],
  'active tenant/entity/branch scope assertion exists'
);
select ok(
  to_regprocedure(
    'core.wave3_finish_command(uuid,text,uuid,text,uuid,uuid,text,jsonb,jsonb,uuid,uuid,jsonb,jsonb,jsonb,jsonb,uuid,uuid)'
  ) is not null,
  'atomic Wave 3 command finalizer exists'
);
select has_function(
  'finance', 'wave3_lock_open_period',
  array['uuid', 'uuid', 'date'],
  'posting can lock and validate an open fiscal period'
);
select ok(
  to_regclass('workflow.process_events_immutable') is null
  and exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'workflow.process_events'::regclass
      and tgname = 'process_events_immutable' and not tgisinternal
  )
  and exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'workflow.approval_decisions'::regclass
      and tgname = 'approval_decisions_immutable' and not tgisinternal
  ),
  'workflow event and decision rows have append-only triggers'
);
select ok(
  to_regclass('workflow.process_events_document_idx') is not null
  and to_regclass('workflow.process_events_stage_idx') is not null
  and to_regclass('workflow.approval_decisions_request_idx') is not null
  and to_regclass('core.command_receipts_command_uidx') is not null
  and to_regclass('core.command_receipts_legal_entity_fk_idx') is not null
  and to_regclass('core.command_receipts_branch_fk_idx') is not null
  and to_regclass('core.outbox_events_actor_fk_idx') is not null
  and to_regclass('workflow.approval_requests_currency_fk_idx') is not null
  and to_regclass('workflow.approval_decisions_actor_fk_idx') is not null
  and to_regclass('workflow.approval_decisions_currency_fk_idx') is not null
  and to_regclass('workflow.approval_decisions_request_workflow_fk_idx') is not null
  and to_regclass('workflow.approval_decisions_workflow_fk_idx') is not null
  and to_regclass('workflow.approval_decisions_matrix_step_fk_idx') is not null
  and to_regclass('workflow.notifications_actor_fk_idx') is not null
  and to_regclass('workflow.notifications_legal_entity_fk_idx') is not null
  and to_regclass('workflow.notifications_branch_fk_idx') is not null
  and to_regclass('workflow.process_events_actor_fk_idx') is not null
  and to_regclass('workflow.process_events_owner_fk_idx') is not null
  and to_regclass('workflow.process_events_legal_entity_fk_idx') is not null
  and to_regclass('workflow.process_events_branch_fk_idx') is not null
  and to_regclass('workflow.process_events_workflow_fk_idx') is not null,
  'Wave 3 command, workflow, and foreign-key paths have covering indexes'
);
select ok(
  (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(20,6)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'workflow.approval_decisions'::regclass
      and a.attname = 'amount' and not a.attisdropped
  )
  and (
    select format_type(a.atttypid, a.atttypmod) = 'numeric(20,6)'
    from pg_catalog.pg_attribute as a
    where a.attrelid = 'workflow.process_events'::regclass
      and a.attname = 'active_minutes' and not a.attisdropped
  ),
  'financial and duration values use explicit PostgreSQL numeric precision'
);

-- Two synthetic tenants and users exercise tenant, entity, branch, and role scope.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '13000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'wave3-one@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '13000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'wave3-two@jentra.test', '',
    now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

insert into core.tenants (id, name, slug, default_currency_code, created_by) values
  (
    '23000000-0000-0000-0000-000000000001', 'Wave Three One', 'wave-three-one',
    'LKR', '13000000-0000-0000-0000-000000000001'
  ),
  (
    '23000000-0000-0000-0000-000000000002', 'Wave Three Two', 'wave-three-two',
    'USD', '13000000-0000-0000-0000-000000000002'
  );

insert into core.legal_entities (
  id, tenant_id, name, code, currency_code, created_by
) values
  (
    '33000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000001',
    'Wave Three Entity One', 'W3ONE', 'LKR',
    '13000000-0000-0000-0000-000000000001'
  ),
  (
    '33000000-0000-0000-0000-000000000002',
    '23000000-0000-0000-0000-000000000002',
    'Wave Three Entity Two', 'W3TWO', 'USD',
    '13000000-0000-0000-0000-000000000002'
  );

insert into core.branches (
  id, tenant_id, legal_entity_id, name, code, created_by
) values
  (
    '34000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    'Wave Three Head Office', 'W3HQ',
    '13000000-0000-0000-0000-000000000001'
  ),
  (
    '34000000-0000-0000-0000-000000000002',
    '23000000-0000-0000-0000-000000000002',
    '33000000-0000-0000-0000-000000000002',
    'Wave Three Other Office', 'W3OT',
    '13000000-0000-0000-0000-000000000002'
  );

insert into core.memberships (id, tenant_id, user_id, status, joined_at) values
  (
    '43000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001', 'active', now()
  ),
  (
    '43000000-0000-0000-0000-000000000002',
    '23000000-0000-0000-0000-000000000002',
    '13000000-0000-0000-0000-000000000002', 'active', now()
  );

insert into core.roles (
  id, tenant_id, code, name, requires_mfa, is_system
) values (
  '53000000-0000-0000-0000-000000000001',
  '23000000-0000-0000-0000-000000000001',
  'wave3_owner', 'Wave 3 owner', true, true
);

insert into core.role_permissions (tenant_id, role_id, permission_code)
select
  '23000000-0000-0000-0000-000000000001',
  '53000000-0000-0000-0000-000000000001',
  p.code
from core.permissions as p
where p.code like 'sales.%'
   or p.code like 'workflow.%';

insert into core.role_assignments (
  tenant_id, membership_id, role_id, created_by
) values (
  '23000000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000001',
  '53000000-0000-0000-0000-000000000001',
  '13000000-0000-0000-0000-000000000001'
);

insert into workflow.workflow_definitions (
  id, tenant_id, legal_entity_id, document_type, name, revision,
  lifecycle, status, created_by, updated_by
) values (
  '63000000-0000-0000-0000-000000000001',
  '23000000-0000-0000-0000-000000000001',
  '33000000-0000-0000-0000-000000000001',
  'sales_quotation', 'Wave 3 quotation lifecycle', 1,
  '{
    "states":[
      "draft","submitted","approved","rejected","posted",
      "settled","fulfilled","closed","cancelled","reversed"
    ],
    "transitions":[
      ["draft","submitted"],["submitted","approved"],
      ["submitted","rejected"],["approved","posted"],
      ["posted","closed"],["posted","reversed"]
    ]
  }',
  'active',
  '13000000-0000-0000-0000-000000000001',
  '13000000-0000-0000-0000-000000000001'
);

insert into workflow.approval_matrix_steps (
  id, tenant_id, workflow_definition_id, role_id, step_order,
  minimum_amount, maximum_amount, currency_code, created_by, updated_by
) values (
  '64000000-0000-0000-0000-000000000001',
  '23000000-0000-0000-0000-000000000001',
  '63000000-0000-0000-0000-000000000001',
  '53000000-0000-0000-0000-000000000001',
  1, 0.000000, 1000000.000000, 'LKR',
  '13000000-0000-0000-0000-000000000001',
  '13000000-0000-0000-0000-000000000001'
);

insert into finance.fiscal_periods (
  id, tenant_id, legal_entity_id, name, start_date, end_date,
  state, status, created_by, updated_by
) values
  (
    '65000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    'Wave 3 Open Half', '2026-01-01', '2026-06-30', 'open', 'active',
    '13000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001'
  ),
  (
    '65000000-0000-0000-0000-000000000002',
    '23000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    'Wave 3 Locked Half', '2026-07-01', '2026-12-31', 'open', 'active',
    '13000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001'
  );
select pg_temp.fixture_period_state(id,'soft_locked') from finance.fiscal_periods where id = '65000000-0000-0000-0000-000000000002';

select set_config(
  'request.jwt.claims',
  '{"sub":"13000000-0000-0000-0000-000000000001","role":"authenticated","email":"wave3-one@jentra.test","aal":"aal2"}',
  true
);

select lives_ok(
  $$select core.wave3_require_scope(
    '23000000-0000-0000-0000-000000000001',
    'sales.quotations.manage',
    '33000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000001'
  )$$,
  'permitted AAL2 actor passes active tenant, entity, and branch scope'
);
select throws_ok(
  $$select core.wave3_require_scope(
    '23000000-0000-0000-0000-000000000002',
    'sales.quotations.manage',
    '33000000-0000-0000-0000-000000000002',
    '34000000-0000-0000-0000-000000000002'
  )$$,
  '42501',
  'Permission denied or multi-factor authentication required.',
  'actor cannot cross tenant scope'
);
select lives_ok(
  $$select core.wave3_assert_expected_version(3, 3, '{"id":"73000000-0000-0000-0000-000000000001","version":3}')$$,
  'matching optimistic version is accepted'
);
select throws_ok(
  $$select core.wave3_assert_expected_version(4, 3, '{"id":"73000000-0000-0000-0000-000000000001","version":4}')$$,
  '40001',
  'VERSION_CONFLICT',
  'stale optimistic version returns a stable conflict code'
);
select is(
  finance.wave3_lock_open_period(
    '23000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    '2026-03-15'
  ),
  '65000000-0000-0000-0000-000000000001'::uuid,
  'posting date resolves and locks the active open fiscal period'
);
select throws_ok(
  $$select finance.wave3_lock_open_period(
    '23000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    '2026-09-15'
  )$$,
  '55000',
  'PERIOD_CLOSED',
  'soft-locked period rejects posting'
);

create temporary table wave3_command_result as
with command_input as (
  select core.wave3_request_hash(
    'upsert_sales_quotation',
    '83000000-0000-0000-0000-000000000001',
    '23000000-0000-0000-0000-000000000001',
    '33000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000001',
    '{"status":"submitted","grand_total":"1250.000000"}',
    1
  ) as request_hash
)
select
  request_hash,
  core.wave3_finish_command(
    '23000000-0000-0000-0000-000000000001',
    'upsert_sales_quotation',
    '83000000-0000-0000-0000-000000000001',
    'sales_quotation',
    '73000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000001',
    request_hash,
    '{"status":"draft","version":1}',
    '{
      "id":"73000000-0000-0000-0000-000000000001",
      "document_type":"sales_quotation",
      "status":"submitted",
      "version":2,
      "transaction_currency":"LKR",
      "subtotal":"1250.000000",
      "discount_total":"0.000000",
      "tax_total":"0.000000",
      "grand_total":"1250.000000",
      "base_total":"1250.000000"
    }',
    '33000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000001',
    '{"source":"wave3_operational_foundation_test","client_timestamp":"2026-09-04T00:00:00Z"}',
    '{
      "workflow_definition_id":"63000000-0000-0000-0000-000000000001",
      "workflow_revision":1,
      "from_status":"draft",
      "to_status":"submitted",
      "owner_id":"13000000-0000-0000-0000-000000000001",
      "entered_at":"2026-09-04T00:00:00Z",
      "completed_at":"2026-09-04T00:12:30Z",
      "active_minutes":"12.500000",
      "wait_minutes":"0.000000",
      "reason":"Submitted for approval"
    }',
    '[{"topic":"workflow.document.submitted","payload":{"status":"submitted"}}]',
    '[]',
    '85000000-0000-0000-0000-000000000001',
    '86000000-0000-0000-0000-000000000001'
  ) as response
from command_input;

select is(
  (select response->>'request_id' from wave3_command_result),
  '85000000-0000-0000-0000-000000000001',
  'command response carries the request identifier'
);
select is(
  (select response->>'command_id' from wave3_command_result),
  '83000000-0000-0000-0000-000000000001',
  'command response carries the stable command identifier'
);
select is(
  (select response->>'correlation_id' from wave3_command_result),
  '86000000-0000-0000-0000-000000000001',
  'command response carries the shared correlation identifier'
);
select is(
  (
    select count(*) from core.command_receipts
    where idempotency_key = '84000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'successful command stores one receipt'
);
select is(
  (
    select count(*) from audit.events
    where aggregate_id = '73000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'successful command appends one audit event'
);
select is(
  (
    select count(*) from workflow.process_events
    where document_id = '73000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'lifecycle change appends one process event'
);
select is(
  (
    select count(*) from core.outbox_events
    where aggregate_id = '73000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'successful command enqueues one required outbox event'
);
select ok(
  (
    select count(distinct correlation_id) = 1
      and min(correlation_id::text) = '86000000-0000-0000-0000-000000000001'
    from (
      select correlation_id from core.command_receipts
      where aggregate_id = '73000000-0000-0000-0000-000000000001'
      union all
      select correlation_id from audit.events
      where aggregate_id = '73000000-0000-0000-0000-000000000001'
      union all
      select correlation_id from workflow.process_events
      where document_id = '73000000-0000-0000-0000-000000000001'
      union all
      select correlation_id from core.outbox_events
      where aggregate_id = '73000000-0000-0000-0000-000000000001'
    ) as effects
  ),
  'receipt, audit, telemetry, and outbox share one correlation identifier'
);
select is(
  (
    select source_context->>'source' from audit.events
    where aggregate_id = '73000000-0000-0000-0000-000000000001'
  ),
  'wave3_operational_foundation_test',
  'audit history retains attributable source context'
);
select ok(
  (
    select active_minutes = 12.500000::numeric
      and wait_minutes = 0.000000::numeric
    from workflow.process_events
    where document_id = '73000000-0000-0000-0000-000000000001'
  ),
  'process telemetry retains exact active and wait durations'
);
select is(
  core.wave3_replay(
    '23000000-0000-0000-0000-000000000001',
    'upsert_sales_quotation',
    '83000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000001',
    (select request_hash from wave3_command_result)
  ),
  (select response from wave3_command_result),
  'retry returns the original command result without duplicate effects'
);
select throws_ok(
  $$select core.wave3_replay(
    '23000000-0000-0000-0000-000000000001',
    'upsert_sales_quotation',
    '83000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000001',
    repeat('0', 64)
  )$$,
  '22023',
  'IDEMPOTENCY_MISMATCH',
  'idempotency key reuse with a different payload is rejected'
);
select throws_ok(
  $$update workflow.process_events
    set reason = 'tampered'
    where document_id = '73000000-0000-0000-0000-000000000001'$$,
  '55000',
  'Workflow history is append-only.',
  'process history cannot be updated'
);
select throws_ok(
  $$delete from workflow.process_events
    where document_id = '73000000-0000-0000-0000-000000000001'$$,
  '55000',
  'Workflow history is append-only.',
  'process history cannot be deleted'
);

insert into workflow.approval_requests (
  id, tenant_id, legal_entity_id, branch_id, document_type, document_id,
  status, submitted_by, assigned_to, workflow_definition_id,
  workflow_revision, current_step, amount, currency_code,
  command_id, request_id, correlation_id
) values (
  '87000000-0000-0000-0000-000000000001',
  '23000000-0000-0000-0000-000000000001',
  '33000000-0000-0000-0000-000000000001',
  '34000000-0000-0000-0000-000000000001',
  'sales_quotation', '73000000-0000-0000-0000-000000000001',
  'submitted',
  '13000000-0000-0000-0000-000000000001',
  '13000000-0000-0000-0000-000000000001',
  '63000000-0000-0000-0000-000000000001', 1, 1,
  1250.000000, 'LKR',
  '83000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000001',
  '86000000-0000-0000-0000-000000000001'
);
insert into workflow.approval_decisions (
  id, tenant_id, approval_request_id, workflow_definition_id,
  workflow_revision, approval_matrix_step_id, step_order, actor_id,
  decision, note, amount, currency_code, request_id, command_id,
  correlation_id, decided_at
) values (
  '88000000-0000-0000-0000-000000000001',
  '23000000-0000-0000-0000-000000000001',
  '87000000-0000-0000-0000-000000000001',
  '63000000-0000-0000-0000-000000000001', 1,
  '64000000-0000-0000-0000-000000000001', 1,
  '13000000-0000-0000-0000-000000000001',
  'approved', 'Within delegated authority', 1250.000000, 'LKR',
  '85000000-0000-0000-0000-000000000001',
  '83000000-0000-0000-0000-000000000001',
  '86000000-0000-0000-0000-000000000001',
  '2026-09-04T00:15:00Z'
);
select throws_ok(
  $$update workflow.approval_decisions
    set note = 'tampered'
    where id = '88000000-0000-0000-0000-000000000001'$$,
  '55000',
  'Workflow history is append-only.',
  'approval decisions cannot be mutated'
);

insert into workflow.process_events (
  id, tenant_id, legal_entity_id, branch_id, document_type, document_id,
  from_status, to_status, actor_id, owner_id, entered_at,
  request_id, command_id, correlation_id
) values (
  '89000000-0000-0000-0000-000000000002',
  '23000000-0000-0000-0000-000000000002',
  '33000000-0000-0000-0000-000000000002',
  '34000000-0000-0000-0000-000000000002',
  'sales_quotation', '73000000-0000-0000-0000-000000000002',
  'draft', 'submitted',
  '13000000-0000-0000-0000-000000000002',
  '13000000-0000-0000-0000-000000000002',
  '2026-09-04T00:00:00Z',
  '85000000-0000-0000-0000-000000000002',
  '83000000-0000-0000-0000-000000000002',
  '86000000-0000-0000-0000-000000000002'
);

set local role authenticated;
select is(
  (
    select count(*) from api.process_events
    where tenant_id = '23000000-0000-0000-0000-000000000002'
  ),
  0::bigint,
  'security-invoker view hides another tenant process history'
);
select is(
  (
    select count(*) from api.process_events
    where tenant_id = '23000000-0000-0000-0000-000000000001'
      and document_id = '73000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'permitted actor can read own scoped process history'
);
reset role;

update core.memberships
set status = 'revoked'
where id = '43000000-0000-0000-0000-000000000001';
set local role authenticated;
select is(
  (
    select count(*) from api.process_events
    where tenant_id = '23000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'revoked membership immediately removes workflow-history visibility'
);
reset role;
select throws_ok(
  $$select core.wave3_replay(
    '23000000-0000-0000-0000-000000000001',
    'upsert_sales_quotation',
    '83000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000001',
    (select request_hash from wave3_command_result)
  )$$,
  '42501',
  'Permission denied.',
  'revoked membership cannot replay a prior command receipt'
);
update core.memberships
set status = 'active'
where id = '43000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select core.wave3_finish_command(
    '23000000-0000-0000-0000-000000000001',
    'upsert_sales_quotation',
    '83000000-0000-0000-0000-000000000003',
    'sales_quotation',
    '73000000-0000-0000-0000-000000000003',
    '84000000-0000-0000-0000-000000000003',
    repeat('3', 64), null,
    '{"id":"73000000-0000-0000-0000-000000000003","status":"submitted","version":1}',
    '33000000-0000-0000-0000-000000000001',
    '34000000-0000-0000-0000-000000000001',
    '{"source":"fault_injection"}',
    '{"from_status":"draft","to_status":"submitted"}',
    '[{"topic":"INVALID TOPIC","payload":{}}]',
    '[]',
    '85000000-0000-0000-0000-000000000003',
    '86000000-0000-0000-0000-000000000003'
  )$$,
  '23514',
  'new row for relation "outbox_events" violates check constraint "outbox_events_topic_format"',
  'injected late outbox failure aborts the command'
);
select ok(
  not exists (
    select 1 from core.command_receipts
    where aggregate_id = '73000000-0000-0000-0000-000000000003'
  )
  and not exists (
    select 1 from audit.events
    where aggregate_id = '73000000-0000-0000-0000-000000000003'
  )
  and not exists (
    select 1 from workflow.process_events
    where document_id = '73000000-0000-0000-0000-000000000003'
  )
  and not exists (
    select 1 from core.outbox_events
    where aggregate_id = '73000000-0000-0000-0000-000000000003'
  ),
  'failed command leaves no receipt, audit, telemetry, or outbox partial effect'
);
select ok(
  not exists (
    select 1 from core.command_receipts
    where aggregate_id = '73000000-0000-0000-0000-000000000001'
      and (
        actor_id is null or tenant_id is null or request_id is null
        or command_id is null or correlation_id is null or response is null
      )
  )
  and not exists (
    select 1 from audit.events
    where aggregate_id = '73000000-0000-0000-0000-000000000001'
      and (
        actor_id is null or tenant_id is null or request_id is null
        or command_id is null or correlation_id is null
        or before_context is null or after_context is null
      )
  )
  and not exists (
    select 1 from workflow.process_events
    where document_id = '73000000-0000-0000-0000-000000000001'
      and (
        actor_id is null or tenant_id is null or request_id is null
        or command_id is null or correlation_id is null
      )
  )
  and not exists (
    select 1 from core.outbox_events
    where aggregate_id = '73000000-0000-0000-0000-000000000001'
      and (
        actor_id is null or tenant_id is null or request_id is null
        or command_id is null or correlation_id is null
      )
  ),
  'successful Wave 3 side effects retain complete tenant, actor, request, command, and correlation attribution'
);

select * from finish();
rollback;
