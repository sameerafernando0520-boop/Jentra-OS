-- Jentra OS Wave 3 operational foundation.
--
-- Implements the shared command, attribution, approval, telemetry, RLS, and
-- fiscal-period primitives required by FR-301..FR-312, NFR-301..NFR-306, and
-- AC-301. Feature migrations call these private helpers from named api RPCs;
-- desktop roles never execute them directly.

-- ---------------------------------------------------------------------------
-- Extend the Wave 1 command/audit/outbox records without rewriting history.
-- ---------------------------------------------------------------------------

alter table core.command_receipts
  add column command_id uuid,
  add column correlation_id uuid,
  add column aggregate_type text,
  add column aggregate_id uuid,
  add column legal_entity_id uuid,
  add column branch_id uuid,
  add column source_context jsonb not null default '{}'::jsonb,
  add column completed_at timestamptz;

alter table core.command_receipts
  add constraint command_receipts_wave3_aggregate_pair_check
    check ((aggregate_type is null) = (aggregate_id is null)) not valid,
  add constraint command_receipts_wave3_aggregate_type_check
    check (
      aggregate_type is null
      or aggregate_type ~ '^[a-z][a-z0-9_.-]{1,79}$'
    ) not valid,
  add constraint command_receipts_wave3_request_hash_check
    check (request_hash is null or request_hash ~ '^[a-f0-9]{64}$') not valid,
  add constraint command_receipts_wave3_source_context_check
    check (jsonb_typeof(source_context) = 'object') not valid,
  add constraint command_receipts_wave3_legal_entity_fkey
    foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  add constraint command_receipts_wave3_branch_fkey
    foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id);

alter table core.command_receipts
  validate constraint command_receipts_wave3_aggregate_pair_check;
alter table core.command_receipts
  validate constraint command_receipts_wave3_aggregate_type_check;
alter table core.command_receipts
  validate constraint command_receipts_wave3_request_hash_check;
alter table core.command_receipts
  validate constraint command_receipts_wave3_source_context_check;

create unique index command_receipts_command_uidx
  on core.command_receipts (tenant_id, command_id)
  where command_id is not null;
create index command_receipts_aggregate_idx
  on core.command_receipts (
    tenant_id, aggregate_type, aggregate_id, created_at desc, id
  ) where aggregate_id is not null;
create index command_receipts_correlation_idx
  on core.command_receipts (tenant_id, correlation_id, id)
  where correlation_id is not null;

alter table audit.events
  add column command_id uuid,
  add column correlation_id uuid,
  add column source_context jsonb not null default '{}'::jsonb;

alter table audit.events
  add constraint audit_events_wave3_source_context_check
    check (jsonb_typeof(source_context) = 'object') not valid;
alter table audit.events
  validate constraint audit_events_wave3_source_context_check;

create index audit_events_correlation_idx
  on audit.events (tenant_id, correlation_id, occurred_at desc, id)
  where correlation_id is not null;
create index audit_events_command_idx
  on audit.events (tenant_id, command_id, occurred_at desc, id)
  where command_id is not null;

alter table core.outbox_events
  add column actor_id uuid references auth.users(id),
  add column request_id uuid,
  add column command_id uuid,
  add column correlation_id uuid,
  add column source_context jsonb not null default '{}'::jsonb;

alter table core.outbox_events
  add constraint outbox_events_topic_format
    check (topic ~ '^[a-z][a-z0-9_.-]{2,99}$') not valid,
  add constraint outbox_events_aggregate_type_format
    check (aggregate_type ~ '^[a-z][a-z0-9_.-]{1,79}$') not valid,
  add constraint outbox_events_payload_object_check
    check (jsonb_typeof(payload) = 'object') not valid,
  add constraint outbox_events_source_context_check
    check (jsonb_typeof(source_context) = 'object') not valid;

alter table core.outbox_events validate constraint outbox_events_topic_format;
alter table core.outbox_events
  validate constraint outbox_events_aggregate_type_format;
alter table core.outbox_events
  validate constraint outbox_events_payload_object_check;
alter table core.outbox_events
  validate constraint outbox_events_source_context_check;

create index outbox_events_tenant_correlation_idx
  on core.outbox_events (tenant_id, correlation_id, status, available_at, id)
  where correlation_id is not null;
create index outbox_events_tenant_command_idx
  on core.outbox_events (tenant_id, command_id, id)
  where command_id is not null;

alter table workflow.notifications
  add column legal_entity_id uuid,
  add column branch_id uuid,
  add column actor_id uuid references auth.users(id),
  add column request_id uuid,
  add column command_id uuid,
  add column correlation_id uuid,
  add column source_context jsonb not null default '{}'::jsonb;

alter table workflow.notifications
  add constraint notifications_wave3_legal_entity_fkey
    foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  add constraint notifications_wave3_branch_fkey
    foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  add constraint notifications_wave3_scope_check
    check (branch_id is null or legal_entity_id is not null) not valid,
  add constraint notifications_wave3_source_context_check
    check (jsonb_typeof(source_context) = 'object') not valid,
  add constraint notifications_wave3_aggregate_pair_check
    check ((aggregate_type is null) = (aggregate_id is null)) not valid,
  add constraint notifications_wave3_aggregate_type_check
    check (
      aggregate_type is null
      or aggregate_type ~ '^[a-z][a-z0-9_.-]{1,79}$'
    ) not valid,
  add constraint notifications_wave3_attribution_check
    check (
      command_id is null
      or (
        actor_id is not null
        and request_id is not null
        and correlation_id is not null
        and aggregate_type is not null
        and aggregate_id is not null
      )
    ) not valid;

alter table workflow.notifications
  validate constraint notifications_wave3_scope_check;
alter table workflow.notifications
  validate constraint notifications_wave3_source_context_check;
alter table workflow.notifications
  validate constraint notifications_wave3_aggregate_pair_check;
alter table workflow.notifications
  validate constraint notifications_wave3_aggregate_type_check;
alter table workflow.notifications
  validate constraint notifications_wave3_attribution_check;

create index notifications_tenant_correlation_idx
  on workflow.notifications (tenant_id, correlation_id, recipient_id, id)
  where correlation_id is not null;
create index notifications_tenant_command_idx
  on workflow.notifications (tenant_id, command_id, recipient_id, id)
  where command_id is not null;

-- ---------------------------------------------------------------------------
-- Versioned approval requests and append-only Wave 3 workflow history.
-- ---------------------------------------------------------------------------

alter table workflow.workflow_definitions
  add constraint workflow_definitions_wave3_revision_key
    unique (tenant_id, id, revision);

alter table workflow.approval_matrix_steps
  add constraint approval_matrix_steps_wave3_identity_key
    unique (tenant_id, id, workflow_definition_id, step_order);

alter table workflow.approval_requests
  add column workflow_definition_id uuid,
  add column workflow_revision integer,
  add column current_step integer,
  add column amount numeric(20, 6),
  add column currency_code text,
  add column command_id uuid,
  add column request_id uuid,
  add column correlation_id uuid;

alter table workflow.approval_requests
  add constraint approval_requests_tenant_id_id_key unique (tenant_id, id),
  add constraint approval_requests_wave3_identity_key
    unique (tenant_id, id, workflow_definition_id, workflow_revision),
  add constraint approval_requests_wave3_workflow_fkey
    foreign key (tenant_id, workflow_definition_id, workflow_revision)
    references workflow.workflow_definitions(tenant_id, id, revision),
  add constraint approval_requests_wave3_currency_fkey
    foreign key (currency_code) references core.currencies(code),
  add constraint approval_requests_wave3_revision_check
    check (workflow_revision is null or workflow_revision > 0) not valid,
  add constraint approval_requests_wave3_step_check
    check (current_step is null or current_step between 1 and 100) not valid,
  add constraint approval_requests_wave3_amount_check
    check (amount is null or amount >= 0) not valid,
  add constraint approval_requests_wave3_amount_currency_check
    check ((amount is null) = (currency_code is null)) not valid,
  add constraint approval_requests_wave3_workflow_revision_pair_check
    check ((workflow_definition_id is null) = (workflow_revision is null)) not valid;

alter table workflow.approval_requests
  validate constraint approval_requests_wave3_revision_check;
alter table workflow.approval_requests
  validate constraint approval_requests_wave3_step_check;
alter table workflow.approval_requests
  validate constraint approval_requests_wave3_amount_check;
alter table workflow.approval_requests
  validate constraint approval_requests_wave3_amount_currency_check;
alter table workflow.approval_requests
  validate constraint approval_requests_wave3_workflow_revision_pair_check;

create unique index approval_requests_active_document_uidx
  on workflow.approval_requests (tenant_id, document_type, document_id)
  where status = 'submitted';
create index approval_requests_workflow_idx
  on workflow.approval_requests (
    tenant_id, workflow_definition_id, workflow_revision, status, submitted_at desc, id
  ) where workflow_definition_id is not null;
create index approval_requests_correlation_idx
  on workflow.approval_requests (tenant_id, correlation_id, id)
  where correlation_id is not null;

create table workflow.process_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid,
  branch_id uuid,
  workflow_instance_id uuid,
  workflow_definition_id uuid,
  workflow_revision integer,
  document_type text not null
    check (document_type ~ '^[a-z][a-z0-9_.-]{2,79}$'),
  document_id uuid not null,
  from_status text
    check (from_status is null or from_status ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  to_status text not null
    check (to_status ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  actor_id uuid not null references auth.users(id),
  owner_id uuid references auth.users(id),
  entered_at timestamptz not null default now(),
  completed_at timestamptz,
  active_minutes numeric(20, 6) not null default 0
    check (active_minutes >= 0),
  wait_minutes numeric(20, 6) not null default 0
    check (wait_minutes >= 0),
  reason text check (reason is null or length(trim(reason)) between 1 and 1000),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id)
    references core.branches(tenant_id, id),
  foreign key (tenant_id, workflow_definition_id, workflow_revision)
    references workflow.workflow_definitions(tenant_id, id, revision),
  check (from_status is null or from_status <> to_status),
  check (completed_at is null or completed_at >= entered_at),
  check ((workflow_definition_id is null) = (workflow_revision is null)),
  check (workflow_revision is null or workflow_revision > 0)
);

create table workflow.approval_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  approval_request_id uuid not null,
  workflow_definition_id uuid not null,
  workflow_revision integer not null check (workflow_revision > 0),
  approval_matrix_step_id uuid not null,
  step_order integer not null check (step_order between 1 and 100),
  actor_id uuid not null references auth.users(id),
  decision text not null check (decision in ('approved', 'rejected')),
  note text check (note is null or length(trim(note)) between 1 and 4000),
  amount numeric(20, 6),
  currency_code text references core.currencies(code),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  decided_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (
    tenant_id, approval_request_id, approval_matrix_step_id, actor_id
  ),
  foreign key (
    tenant_id, approval_request_id, workflow_definition_id, workflow_revision
  ) references workflow.approval_requests(
    tenant_id, id, workflow_definition_id, workflow_revision
  ),
  foreign key (tenant_id, workflow_definition_id, workflow_revision)
    references workflow.workflow_definitions(tenant_id, id, revision),
  foreign key (
    tenant_id, approval_matrix_step_id, workflow_definition_id, step_order
  ) references workflow.approval_matrix_steps(
    tenant_id, id, workflow_definition_id, step_order
  ),
  check ((amount is null) = (currency_code is null)),
  check (amount is null or amount >= 0),
  check (decision = 'approved' or note is not null)
);

create index process_events_document_idx
  on workflow.process_events (
    tenant_id, document_type, document_id, entered_at desc, id
  );
create index process_events_stage_idx
  on workflow.process_events (
    tenant_id, to_status, entered_at desc, document_id, id
  );
create index process_events_owner_idx
  on workflow.process_events (
    tenant_id, owner_id, to_status, entered_at desc, id
  ) where owner_id is not null;
create index process_events_correlation_idx
  on workflow.process_events (tenant_id, correlation_id, id);
create index approval_decisions_request_idx
  on workflow.approval_decisions (
    tenant_id, approval_request_id, step_order, decided_at, id
  );
create index approval_decisions_actor_idx
  on workflow.approval_decisions (tenant_id, actor_id, decided_at desc, id);
create index approval_decisions_correlation_idx
  on workflow.approval_decisions (tenant_id, correlation_id, id);

create function workflow.reject_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'Workflow history is append-only.';
end;
$$;

create trigger process_events_immutable
before update or delete on workflow.process_events
for each row execute function workflow.reject_history_mutation();

create trigger approval_decisions_immutable
before update or delete on workflow.approval_decisions
for each row execute function workflow.reject_history_mutation();

-- ---------------------------------------------------------------------------
-- RLS and security-invoker read models.
-- ---------------------------------------------------------------------------

alter table core.command_receipts enable row level security;
alter table core.command_receipts force row level security;
alter table core.outbox_events enable row level security;
alter table core.outbox_events force row level security;
alter table audit.events enable row level security;
alter table audit.events force row level security;
alter table workflow.notifications enable row level security;
alter table workflow.notifications force row level security;
alter table workflow.approval_requests enable row level security;
alter table workflow.approval_requests force row level security;
alter table workflow.process_events enable row level security;
alter table workflow.process_events force row level security;
alter table workflow.approval_decisions enable row level security;
alter table workflow.approval_decisions force row level security;

drop policy if exists approvals_member_read on workflow.approval_requests;
create policy approval_requests_permitted_read on workflow.approval_requests
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    submitted_by = (select auth.uid())
    or assigned_to = (select auth.uid())
    or decision_by = (select auth.uid())
    or core.has_permission(
      tenant_id, 'workflow.approvals.view', legal_entity_id, branch_id
    )
    or core.has_permission(
      tenant_id, 'workflow.approvals.decide', legal_entity_id, branch_id
    )
  )
);

create policy process_events_permitted_read on workflow.process_events
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    actor_id = (select auth.uid())
    or owner_id = (select auth.uid())
    or core.has_permission(
      tenant_id, 'workflow.process.view', legal_entity_id, branch_id
    )
  )
);

create policy approval_decisions_permitted_read on workflow.approval_decisions
for select to authenticated
using (
  core.is_tenant_member(tenant_id)
  and (
    actor_id = (select auth.uid())
    or exists (
      select 1
      from workflow.approval_requests as ar
      where ar.tenant_id = approval_decisions.tenant_id
        and ar.id = approval_decisions.approval_request_id
        and (
          ar.submitted_by = (select auth.uid())
          or ar.assigned_to = (select auth.uid())
          or ar.decision_by = (select auth.uid())
          or core.has_permission(
            ar.tenant_id,
            'workflow.approvals.view',
            ar.legal_entity_id,
            ar.branch_id
          )
          or core.has_permission(
            ar.tenant_id,
            'workflow.approvals.decide',
            ar.legal_entity_id,
            ar.branch_id
          )
        )
    )
  )
);

create or replace view api.my_notifications
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id,
  notification_type as code, title as name, recipient_id,
  notification_type, title, body, aggregate_type, aggregate_id,
  case when read_at is null then 'unread' else 'read' end as status,
  read_at, version, created_at, updated_at, branch_id, actor_id,
  request_id, command_id, correlation_id, source_context
from workflow.notifications;

create view api.approval_requests
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, document_type, document_id,
  status, submitted_by, assigned_to, decision_by, decision_note,
  submitted_at, decided_at, workflow_definition_id, workflow_revision,
  current_step, amount, currency_code, command_id, request_id,
  correlation_id, version, created_at, updated_at
from workflow.approval_requests;

create view api.approval_decisions
with (security_invoker = true)
as
select
  id, tenant_id, approval_request_id, workflow_definition_id,
  workflow_revision, approval_matrix_step_id, step_order, actor_id,
  decision, note, amount, currency_code, request_id, command_id,
  correlation_id, decided_at, created_at
from workflow.approval_decisions;

create view api.process_events
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, workflow_instance_id,
  workflow_definition_id, workflow_revision, document_type, document_id,
  from_status, to_status, actor_id, owner_id, entered_at, completed_at,
  active_minutes, wait_minutes, reason, request_id, command_id,
  correlation_id, created_at
from workflow.process_events;

-- ---------------------------------------------------------------------------
-- Wave 3 capability vocabulary. High-risk financial and override operations
-- remain separate so roles, MFA, and segregation rules can distinguish them.
-- ---------------------------------------------------------------------------

insert into core.permissions (code, module, description, privileged) values
  ('crm.leads.view', 'crm', 'View leads and their pipeline state.', false),
  ('crm.leads.manage', 'crm', 'Create and update leads.', true),
  ('crm.leads.convert', 'crm', 'Convert qualified leads into business records.', true),
  ('crm.activities.manage', 'crm', 'Record CRM activities and outcomes.', true),
  ('crm.opportunities.view', 'crm', 'View opportunities and forecasts.', false),
  ('crm.opportunities.manage', 'crm', 'Create and update opportunities.', true),
  ('sales.quotations.view', 'sales', 'View quotations and revisions.', false),
  ('sales.quotations.manage', 'sales', 'Create and update quotation drafts.', true),
  ('sales.orders.view', 'sales', 'View sales orders and fulfillment state.', false),
  ('sales.orders.manage', 'sales', 'Create and update sales orders.', true),
  ('sales.deliveries.post', 'sales', 'Post delivery and fulfillment effects.', true),
  ('sales.invoices.view', 'sales', 'View sales invoices and receivable state.', true),
  ('sales.invoices.manage', 'sales', 'Create and update sales invoice drafts.', true),
  ('sales.invoices.post', 'sales', 'Post sales invoices and ledger effects.', true),
  ('sales.returns.post', 'sales', 'Post sales returns and credit effects.', true),
  ('sales.price.override', 'sales', 'Override governed commercial prices.', true),
  ('procurement.requisitions.manage', 'procurement', 'Manage purchase requisitions.', true),
  ('procurement.rfq.manage', 'procurement', 'Manage requests for quote.', true),
  ('procurement.orders.view', 'procurement', 'View purchase orders.', false),
  ('procurement.orders.manage', 'procurement', 'Create and update purchase orders.', true),
  ('procurement.receipts.post', 'procurement', 'Post goods receipts and accruals.', true),
  ('procurement.bills.view', 'procurement', 'View supplier bills and payable state.', true),
  ('procurement.bills.manage', 'procurement', 'Create and match supplier bill drafts.', true),
  ('procurement.bills.post', 'procurement', 'Post supplier bills and ledger effects.', true),
  ('procurement.returns.post', 'procurement', 'Post purchase returns and debit effects.', true),
  ('inventory.stock.view', 'inventory', 'View permitted stock quantities.', false),
  ('inventory.reservations.manage', 'inventory', 'Create and release stock reservations.', true),
  ('inventory.transfers.post', 'inventory', 'Post traced stock transfers.', true),
  ('inventory.adjustments.post', 'inventory', 'Post approved stock adjustments.', true),
  ('inventory.valuation.post', 'inventory', 'Post inventory value adjustments.', true),
  ('inventory.cost.view', 'inventory', 'View restricted inventory cost and value.', true),
  ('inventory.stock.override', 'inventory', 'Override governed stock availability.', true),
  ('finance.receipts.post', 'finance', 'Post customer receipts and allocations.', true),
  ('finance.payments.manage', 'finance', 'Prepare supplier payment proposals.', true),
  ('finance.payments.post', 'finance', 'Post approved supplier payments.', true),
  ('finance.journals.post', 'finance', 'Post approved balanced journals.', true),
  ('finance.reversals.post', 'finance', 'Post one attributable linked reversal.', true),
  ('finance.bank.manage', 'finance', 'Manage operational cash and bank accounts.', true),
  ('finance.bank.import', 'finance', 'Import bounded bank statements.', true),
  ('finance.bank.reconcile', 'finance', 'Create and reverse bank reconciliations.', true),
  ('finance.bank.adjust', 'finance', 'Post governed bank adjustments.', true),
  ('finance.period.close', 'finance', 'Soft-lock or hard-lock fiscal periods.', true),
  ('finance.period.reopen', 'finance', 'Reopen eligible fiscal periods with MFA.', true),
  ('finance.fx.post', 'finance', 'Post period-end exchange revaluation.', true),
  ('finance.budgets.manage', 'finance', 'Manage versioned budgets.', true),
  ('workflow.approvals.view', 'workflow', 'View scoped operational approvals.', false),
  ('workflow.approvals.decide', 'workflow', 'Record scoped approval decisions.', true),
  ('workflow.process.view', 'workflow', 'View scoped process telemetry.', false)
on conflict (code) do update set
  module = excluded.module,
  description = excluded.description,
  privileged = excluded.privileged;

insert into core.role_permissions (tenant_id, role_id, permission_code)
select r.tenant_id, r.id, p.code
from core.roles as r
cross join core.permissions as p
where r.code = 'tenant_owner'
  and p.code in (
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
on conflict (role_id, permission_code) do nothing;

-- ---------------------------------------------------------------------------
-- Private Wave 3 command helpers.
-- ---------------------------------------------------------------------------

create function core.wave3_request_hash(
  p_command_name text,
  p_command_id uuid,
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_payload jsonb,
  p_expected_version bigint
)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(
    extensions.digest(
      concat_ws(
        '|',
        p_command_name,
        p_command_id::text,
        p_tenant_id::text,
        coalesce(p_legal_entity_id::text, ''),
        coalesce(p_branch_id::text, ''),
        coalesce(p_expected_version::text, ''),
        coalesce(p_payload, 'null'::jsonb)::text
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create function core.wave3_replay(
  p_tenant_id uuid,
  p_command_name text,
  p_command_id uuid,
  p_idempotency_key uuid,
  p_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_receipt core.command_receipts%rowtype;
begin
  if v_actor is null or not core.is_tenant_member(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Permission denied.';
  end if;
  if p_command_id is null or p_idempotency_key is null then
    raise exception using
      errcode = '22023',
      message = 'Command and idempotency identifiers are required.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_actor::text || ':' || p_idempotency_key::text,
      0
    )
  );

  select cr.* into v_receipt
  from core.command_receipts as cr
  where cr.actor_id = v_actor
    and cr.idempotency_key = p_idempotency_key;

  if found then
    if v_receipt.tenant_id <> p_tenant_id
       or v_receipt.command_name <> p_command_name
       or v_receipt.command_id is distinct from p_command_id
       or v_receipt.request_hash is distinct from p_request_hash then
      raise exception using
        errcode = '22023',
        message = 'IDEMPOTENCY_MISMATCH';
    end if;
    return v_receipt.response;
  end if;

  return null;
end;
$$;

create function core.wave3_assert_expected_version(
  p_current_version bigint,
  p_expected_version bigint,
  p_current_entity jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_expected_version is null or p_current_version <> p_expected_version then
    raise exception using
      errcode = '40001',
      message = 'VERSION_CONFLICT',
      detail = jsonb_build_object(
        'code', 'VERSION_CONFLICT',
        'current_version', p_current_version,
        'current', coalesce(p_current_entity, '{}'::jsonb)
      )::text;
  end if;
end;
$$;

create function core.wave3_require_scope(
  p_tenant_id uuid,
  p_permission_code text,
  p_legal_entity_id uuid default null,
  p_branch_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform core.require_permission(
    p_tenant_id, p_permission_code, p_legal_entity_id, p_branch_id
  );

  if not exists (
    select 1 from core.tenants as t
    where t.id = p_tenant_id and t.status in ('trial', 'active')
  ) then
    raise exception using errcode = '42501', message = 'TENANT_SCOPE_INVALID';
  end if;

  if p_legal_entity_id is not null and not exists (
    select 1 from core.legal_entities as le
    where le.tenant_id = p_tenant_id
      and le.id = p_legal_entity_id
      and le.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'LEGAL_ENTITY_SCOPE_INVALID';
  end if;

  if p_branch_id is not null then
    if p_legal_entity_id is null or not exists (
      select 1 from core.branches as b
      where b.tenant_id = p_tenant_id
        and b.legal_entity_id = p_legal_entity_id
        and b.id = p_branch_id
        and b.status = 'active'
    ) then
      raise exception using errcode = '42501', message = 'BRANCH_SCOPE_INVALID';
    end if;
  end if;
end;
$$;

create function finance.wave3_lock_open_period(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_posting_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period_id uuid;
begin
  if (select auth.uid()) is null or not core.is_tenant_member(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if p_posting_date is null then
    raise exception using errcode = '22023', message = 'Posting date is required.';
  end if;

  select fp.id into v_period_id
  from finance.fiscal_periods as fp
  where fp.tenant_id = p_tenant_id
    and fp.legal_entity_id = p_legal_entity_id
    and fp.status = 'active'
    and fp.state = 'open'
    and p_posting_date between fp.start_date and fp.end_date
  for update;

  if v_period_id is null then
    raise exception using errcode = '55000', message = 'PERIOD_CLOSED';
  end if;

  return v_period_id;
end;
$$;

create function core.wave3_finish_command(
  p_tenant_id uuid,
  p_command_name text,
  p_command_id uuid,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_idempotency_key uuid,
  p_request_hash text,
  p_before jsonb,
  p_entity jsonb,
  p_legal_entity_id uuid default null,
  p_branch_id uuid default null,
  p_source_context jsonb default '{}'::jsonb,
  p_process_event jsonb default null,
  p_outbox_events jsonb default '[]'::jsonb,
  p_warnings jsonb default '[]'::jsonb,
  p_request_id uuid default null,
  p_correlation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_request_id uuid := coalesce(p_request_id, gen_random_uuid());
  v_correlation_id uuid := coalesce(p_correlation_id, v_request_id);
  v_response jsonb;
  v_outbox_events jsonb := coalesce(p_outbox_events, '[]'::jsonb);
  v_event jsonb;
  v_process_id uuid;
  v_workflow_definition_id uuid;
  v_workflow_revision integer;
begin
  if v_actor is null or not core.is_tenant_member(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if p_command_id is null or p_idempotency_key is null
     or p_aggregate_id is null or p_request_hash is null then
    raise exception using errcode = '22023', message = 'Command identity is incomplete.';
  end if;
  if p_command_name !~ '^[a-z][a-z0-9_.-]{2,99}$'
     or p_aggregate_type !~ '^[a-z][a-z0-9_.-]{1,79}$' then
    raise exception using errcode = '22023', message = 'Command identity is invalid.';
  end if;
  if p_request_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'Request hash is invalid.';
  end if;
  if jsonb_typeof(p_entity) <> 'object'
     or jsonb_typeof(coalesce(p_source_context, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_warnings, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(v_outbox_events) <> 'array' then
    raise exception using errcode = '22023', message = 'Command JSON contract is invalid.';
  end if;
  if p_process_event is not null and jsonb_typeof(p_process_event) <> 'object' then
    raise exception using errcode = '22023', message = 'Process event must be an object.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_actor::text || ':' || p_idempotency_key::text,
      0
    )
  );
  if exists (
    select 1 from core.command_receipts as cr
    where cr.actor_id = v_actor and cr.idempotency_key = p_idempotency_key
  ) then
    raise exception using
      errcode = '55000',
      message = 'IDEMPOTENCY_REPLAY_REQUIRED';
  end if;

  v_response := jsonb_build_object(
    'request_id', v_request_id,
    'command_id', p_command_id,
    'correlation_id', v_correlation_id,
    'entity', p_entity,
    'warnings', coalesce(p_warnings, '[]'::jsonb)
  );

  insert into audit.events (
    tenant_id, actor_id, request_id, command_id, correlation_id,
    event_type, aggregate_type, aggregate_id, legal_entity_id, branch_id,
    before_context, after_context, source_context, metadata
  ) values (
    p_tenant_id, v_actor, v_request_id, p_command_id, v_correlation_id,
    p_command_name, p_aggregate_type, p_aggregate_id,
    p_legal_entity_id, p_branch_id, p_before, p_entity,
    coalesce(p_source_context, '{}'::jsonb),
    jsonb_build_object(
      'idempotency_key', p_idempotency_key,
      'request_hash', p_request_hash
    )
  );

  if p_process_event is not null then
    v_workflow_definition_id :=
      nullif(p_process_event->>'workflow_definition_id', '')::uuid;
    v_workflow_revision :=
      nullif(p_process_event->>'workflow_revision', '')::integer;

    if v_workflow_definition_id is not null and not exists (
      select 1
      from workflow.workflow_definitions as wd
      where wd.tenant_id = p_tenant_id
        and wd.id = v_workflow_definition_id
        and wd.revision = v_workflow_revision
        and wd.status = 'active'
    ) then
      raise exception using
        errcode = '55000',
        message = 'WORKFLOW_CONFIGURATION_ERROR';
    end if;

    v_process_id := coalesce(
      nullif(p_process_event->>'id', '')::uuid,
      gen_random_uuid()
    );
    insert into workflow.process_events (
      id, tenant_id, legal_entity_id, branch_id, workflow_instance_id,
      workflow_definition_id, workflow_revision, document_type, document_id,
      from_status, to_status, actor_id, owner_id, entered_at, completed_at,
      active_minutes, wait_minutes, reason, request_id, command_id,
      correlation_id
    ) values (
      v_process_id, p_tenant_id, p_legal_entity_id, p_branch_id,
      nullif(p_process_event->>'workflow_instance_id', '')::uuid,
      v_workflow_definition_id, v_workflow_revision,
      p_aggregate_type, p_aggregate_id,
      nullif(p_process_event->>'from_status', ''),
      nullif(p_process_event->>'to_status', ''),
      v_actor,
      nullif(p_process_event->>'owner_id', '')::uuid,
      coalesce(
        nullif(p_process_event->>'entered_at', '')::timestamptz,
        clock_timestamp()
      ),
      nullif(p_process_event->>'completed_at', '')::timestamptz,
      coalesce(nullif(p_process_event->>'active_minutes', '')::numeric, 0),
      coalesce(nullif(p_process_event->>'wait_minutes', '')::numeric, 0),
      nullif(trim(p_process_event->>'reason'), ''),
      v_request_id, p_command_id, v_correlation_id
    );
  end if;

  if jsonb_array_length(v_outbox_events) = 0 then
    v_outbox_events := jsonb_build_array(
      jsonb_build_object('topic', p_command_name, 'payload', '{}'::jsonb)
    );
  end if;

  for v_event in select value from jsonb_array_elements(v_outbox_events)
  loop
    insert into core.outbox_events (
      tenant_id, actor_id, request_id, command_id, correlation_id,
      topic, aggregate_type, aggregate_id, payload, source_context
    ) values (
      p_tenant_id, v_actor, v_request_id, p_command_id, v_correlation_id,
      v_event->>'topic', p_aggregate_type, p_aggregate_id,
      coalesce(v_event->'payload', '{}'::jsonb)
        || jsonb_build_object(
          'request_id', v_request_id,
          'command_id', p_command_id,
          'correlation_id', v_correlation_id,
          'actor_id', v_actor
        ),
      coalesce(p_source_context, '{}'::jsonb)
    );
  end loop;

  insert into core.command_receipts (
    tenant_id, actor_id, idempotency_key, command_name, request_id,
    request_hash, response, command_id, correlation_id, aggregate_type,
    aggregate_id, legal_entity_id, branch_id, source_context, completed_at
  ) values (
    p_tenant_id, v_actor, p_idempotency_key, p_command_name, v_request_id,
    p_request_hash, v_response, p_command_id, v_correlation_id,
    p_aggregate_type, p_aggregate_id, p_legal_entity_id, p_branch_id,
    coalesce(p_source_context, '{}'::jsonb), clock_timestamp()
  );

  return v_response;
end;
$$;

revoke all on function workflow.reject_history_mutation()
  from public, anon, authenticated;
revoke all on function core.wave3_request_hash(
  text, uuid, uuid, uuid, uuid, jsonb, bigint
) from public, anon, authenticated;
revoke all on function core.wave3_replay(uuid, text, uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function core.wave3_assert_expected_version(bigint, bigint, jsonb)
  from public, anon, authenticated;
revoke all on function core.wave3_require_scope(uuid, text, uuid, uuid)
  from public, anon, authenticated;
revoke all on function finance.wave3_lock_open_period(uuid, uuid, date)
  from public, anon, authenticated;
revoke all on function core.wave3_finish_command(
  uuid, text, uuid, text, uuid, uuid, text, jsonb, jsonb,
  uuid, uuid, jsonb, jsonb, jsonb, jsonb, uuid, uuid
) from public, anon, authenticated;

revoke all on workflow.process_events, workflow.approval_decisions
  from public, anon, authenticated;
grant select on workflow.process_events, workflow.approval_decisions
  to authenticated;
grant select on api.approval_requests, api.approval_decisions,
  api.process_events to authenticated;

comment on table workflow.process_events is
  'Append-only Wave 3 lifecycle telemetry correlated to one command and request.';
comment on table workflow.approval_decisions is
  'Append-only Wave 3 approval decisions bound to a workflow revision and step.';
comment on function core.wave3_finish_command(
  uuid, text, uuid, text, uuid, uuid, text, jsonb, jsonb,
  uuid, uuid, jsonb, jsonb, jsonb, jsonb, uuid, uuid
) is
  'Private atomic finalizer for receipt, audit, lifecycle telemetry, and outbox effects.';

notify pgrst, 'reload schema';
