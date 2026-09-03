-- Wave 2 versioned Data API. Reads are security-invoker views; every write is
-- an explicit named RPC with a validated private implementation.

-- ---------------------------------------------------------------------------
-- Security-invoker read models
-- ---------------------------------------------------------------------------

create view api.currencies
with (security_invoker = true)
as
select
  code as id,
  null::uuid as tenant_id,
  null::uuid as legal_entity_id,
  code,
  name,
  case when active then 'active' else 'inactive' end as status,
  numeric_code,
  minor_units,
  symbol,
  active,
  1::bigint as version,
  created_at,
  created_at as updated_at
from core.currencies;

create view api.exchange_rates
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id,
  source_currency_code || '/' || target_currency_code as code,
  source_currency_code || ' to ' || target_currency_code as name,
  source_currency_code, target_currency_code, rate::text as rate,
  effective_date, rate_type, source, status, version, created_at, updated_at
from finance.exchange_rates;

create view api.tax_definitions
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, code, name, rate::text as rate, kind,
  inclusive, recoverable, valid_from, valid_to, status, version,
  created_at, updated_at
from finance.tax_definitions;

create view api.accounts
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, code, name, account_type, normal_balance,
  parent_id, is_posting, currency_code, status, version, created_at, updated_at
from finance.accounts;

create view api.fiscal_periods
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id,
  to_char(start_date, 'YYYY-MM-DD') || ':' || to_char(end_date, 'YYYY-MM-DD') as code,
  name, start_date, end_date, state, status, version, created_at, updated_at
from finance.fiscal_periods;

create view api.parties
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id, code,
  display_name as name, legal_name, display_name, kind, tax_identifier,
  email, phone, address_line_1, address_line_2, city, country_code,
  credit_limit::text as credit_limit, credit_currency_code,
  payment_terms_days, status, version, created_at, updated_at
from crm.parties;

create view api.contacts
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id, party_id,
  left(name, 24) as code, name, role, email, phone, is_primary,
  status, version, created_at, updated_at
from crm.contacts;

create view api.units
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id, code, name, symbol,
  category, precision, status, version, created_at, updated_at
from inventory.units;

create view api.products
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, sku as code, sku, name, description,
  kind, base_unit_id, tracking_mode, can_sell, can_purchase,
  tax_definition_id, revenue_account_id, expense_account_id,
  inventory_account_id, cogs_account_id, status, version, created_at, updated_at
from inventory.products;

create view api.document_sequences
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, branch_id, document_type as code,
  replace(initcap(replace(document_type, '_', ' ')), '.', ' ') as name,
  document_type, prefix, suffix, padding, reset_policy, next_value,
  last_reset_key, status, version, created_at, updated_at
from core.document_sequences;

create view api.workflow_definitions
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id, document_type as code, name,
  document_type, revision, lifecycle, status, version, created_at, updated_at
from workflow.workflow_definitions;

create view api.approval_matrix_steps
with (security_invoker = true)
as
select
  am.id, am.tenant_id, wd.legal_entity_id,
  'STEP-' || am.step_order::text as code,
  'Approval step ' || am.step_order::text as name,
  am.workflow_definition_id, am.role_id, am.step_order,
  am.minimum_amount::text as minimum_amount,
  am.maximum_amount::text as maximum_amount,
  am.currency_code, am.status, am.version, am.created_at, am.updated_at
from workflow.approval_matrix_steps as am
join workflow.workflow_definitions as wd
  on wd.tenant_id = am.tenant_id and wd.id = am.workflow_definition_id;

create view api.attachments
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id,
  left(file_name, 48) as code, file_name as name,
  aggregate_type, aggregate_id, file_name, mime_type, byte_size,
  bucket_id, object_path, checksum_sha256, upload_status as status,
  version, created_at, updated_at
from core.attachments;

create view api.my_notifications
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id,
  notification_type as code, title as name, recipient_id,
  notification_type, title, body, aggregate_type, aggregate_id,
  case when read_at is null then 'unread' else 'read' end as status,
  read_at, version, created_at, updated_at
from workflow.notifications;

create view api.import_jobs
with (security_invoker = true)
as
select
  id, tenant_id, legal_entity_id,
  'IMPORT-' || left(id::text, 8) as code, file_name as name,
  actor_id, resource, file_format, file_name, file_size, status,
  total_rows, accepted_rows, rejected_rows, errors, request_id,
  version, created_at, updated_at
from core.import_jobs;

create view api.export_jobs
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id,
  'EXPORT-' || left(id::text, 8) as code, file_name as name,
  actor_id, resource, file_format, filters, columns_json as columns,
  status, row_count, file_name, file_size, request_id,
  version, created_at, updated_at
from core.export_jobs;

create view api.report_definitions
with (security_invoker = true)
as
select
  id, tenant_id, null::uuid as legal_entity_id, code, title as name,
  title, source_view, columns_json as columns, filters, sort_json as sort,
  row_limit, is_shared, owner_id, status, version, created_at, updated_at
from core.report_definitions;

-- ---------------------------------------------------------------------------
-- Named setup commands
-- ---------------------------------------------------------------------------

create function api.upsert_exchange_rate(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'exchange_rates', p_tenant_id, p_legal_entity_id, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_tax_definition(
  p_tenant_id uuid, p_legal_entity_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'tax_definitions', p_tenant_id, p_legal_entity_id, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_account(
  p_tenant_id uuid, p_legal_entity_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'accounts', p_tenant_id, p_legal_entity_id, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_fiscal_period(
  p_tenant_id uuid, p_legal_entity_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'fiscal_periods', p_tenant_id, p_legal_entity_id, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_party(
  p_tenant_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'parties', p_tenant_id, null, p_payload, p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_contact(
  p_tenant_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'contacts', p_tenant_id, null, p_payload, p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_unit(
  p_tenant_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'units', p_tenant_id, null, p_payload, p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_product(
  p_tenant_id uuid, p_legal_entity_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'products', p_tenant_id, p_legal_entity_id, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_document_sequence(
  p_tenant_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'document_sequences', p_tenant_id, null, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.reserve_document_number(
  p_tenant_id uuid,
  p_sequence_id uuid,
  p_document_date date default current_date,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.reserve_document_number_impl(
    p_tenant_id, p_sequence_id, p_document_date, p_idempotency_key
  );
$$;

create function api.upsert_workflow_definition(
  p_tenant_id uuid, p_legal_entity_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'workflow_definitions', p_tenant_id, p_legal_entity_id, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.upsert_approval_matrix_step(
  p_tenant_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'approval_matrix_steps', p_tenant_id, null, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.register_attachment(
  p_tenant_id uuid,
  p_payload jsonb,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.register_attachment_impl(p_tenant_id, p_payload, p_idempotency_key);
$$;

create function api.complete_attachment(
  p_tenant_id uuid,
  p_attachment_id uuid,
  p_checksum_sha256 text,
  p_expected_version bigint,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.complete_attachment_impl(
    p_tenant_id, p_attachment_id, p_checksum_sha256,
    p_expected_version, p_idempotency_key
  );
$$;

create function api.mark_notification_read(
  p_tenant_id uuid,
  p_notification_id uuid,
  p_expected_version bigint,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.mark_notification_read_impl(
    p_tenant_id, p_notification_id, p_expected_version, p_idempotency_key
  );
$$;

create function api.import_setup_records(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_resource text,
  p_file_format text,
  p_file_name text,
  p_file_size bigint,
  p_rows jsonb,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.import_setup_records_impl(
    p_tenant_id, p_legal_entity_id, p_resource, p_file_format,
    p_file_name, p_file_size, p_rows, p_idempotency_key
  );
$$;

create function api.create_export_job(
  p_tenant_id uuid,
  p_resource text,
  p_file_format text,
  p_filters jsonb,
  p_columns jsonb,
  p_row_count integer,
  p_file_name text,
  p_file_size bigint,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.create_export_job_impl(
    p_tenant_id, p_resource, p_file_format, p_filters, p_columns,
    p_row_count, p_file_name, p_file_size, p_idempotency_key
  );
$$;

create function api.upsert_report_definition(
  p_tenant_id uuid, p_payload jsonb,
  p_expected_version bigint default null,
  p_idempotency_key uuid default gen_random_uuid()
)
returns jsonb language sql volatile security definer set search_path = ''
as $$
  select core.upsert_setup_record_impl(
    'report_definitions', p_tenant_id, null, p_payload,
    p_expected_version, p_idempotency_key
  );
$$;

-- ---------------------------------------------------------------------------
-- Explicit grants
-- ---------------------------------------------------------------------------

grant usage on schema api, core, finance, crm, inventory, workflow
  to authenticated;

grant select on core.currencies, finance.exchange_rates,
  finance.tax_definitions, finance.accounts, finance.fiscal_periods,
  crm.parties, crm.contacts, inventory.units, inventory.products,
  core.document_sequences, workflow.workflow_definitions,
  workflow.approval_matrix_steps, core.attachments,
  workflow.notifications, core.import_jobs, core.export_jobs,
  core.report_definitions
  to authenticated;

grant select on api.currencies, api.exchange_rates, api.tax_definitions,
  api.accounts, api.fiscal_periods, api.parties, api.contacts, api.units,
  api.products, api.document_sequences, api.workflow_definitions,
  api.approval_matrix_steps, api.attachments, api.my_notifications,
  api.import_jobs, api.export_jobs, api.report_definitions
  to authenticated;

grant execute on function core.storage_object_tenant(text) to authenticated;

revoke execute on function api.upsert_exchange_rate(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_tax_definition(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_account(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_fiscal_period(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_party(uuid, jsonb, bigint, uuid),
  api.upsert_contact(uuid, jsonb, bigint, uuid),
  api.upsert_unit(uuid, jsonb, bigint, uuid),
  api.upsert_product(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_document_sequence(uuid, jsonb, bigint, uuid),
  api.reserve_document_number(uuid, uuid, date, uuid),
  api.upsert_workflow_definition(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_approval_matrix_step(uuid, jsonb, bigint, uuid),
  api.register_attachment(uuid, jsonb, uuid),
  api.complete_attachment(uuid, uuid, text, bigint, uuid),
  api.mark_notification_read(uuid, uuid, bigint, uuid),
  api.import_setup_records(uuid, uuid, text, text, text, bigint, jsonb, uuid),
  api.create_export_job(uuid, text, text, jsonb, jsonb, integer, text, bigint, uuid),
  api.upsert_report_definition(uuid, jsonb, bigint, uuid)
  from public, anon, authenticated;

grant execute on function api.upsert_exchange_rate(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_tax_definition(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_account(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_fiscal_period(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_party(uuid, jsonb, bigint, uuid),
  api.upsert_contact(uuid, jsonb, bigint, uuid),
  api.upsert_unit(uuid, jsonb, bigint, uuid),
  api.upsert_product(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_document_sequence(uuid, jsonb, bigint, uuid),
  api.reserve_document_number(uuid, uuid, date, uuid),
  api.upsert_workflow_definition(uuid, uuid, jsonb, bigint, uuid),
  api.upsert_approval_matrix_step(uuid, jsonb, bigint, uuid),
  api.register_attachment(uuid, jsonb, uuid),
  api.complete_attachment(uuid, uuid, text, bigint, uuid),
  api.mark_notification_read(uuid, uuid, bigint, uuid),
  api.import_setup_records(uuid, uuid, text, text, text, bigint, jsonb, uuid),
  api.create_export_job(uuid, text, text, jsonb, jsonb, integer, text, bigint, uuid),
  api.upsert_report_definition(uuid, jsonb, bigint, uuid)
  to authenticated;
