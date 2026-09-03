-- Wave 2 private command infrastructure. These functions are not exposed by
-- PostgREST; named api wrappers are granted later.

create function core.wave2_permission(
  p_resource text,
  p_manage boolean default false
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_resource in ('exchange_rates', 'tax_definitions', 'accounts', 'fiscal_periods')
      then case when p_manage then 'finance.setup.manage' else 'finance.setup.view' end
    when p_resource in ('parties', 'contacts')
      then case when p_manage then 'crm.parties.manage' else 'crm.parties.view' end
    when p_resource in ('units', 'products')
      then case when p_manage then 'inventory.catalog.manage' else 'inventory.catalog.view' end
    when p_resource = 'document_sequences'
      then case when p_manage then 'core.setup.manage' else 'core.setup.view' end
    when p_resource in ('workflow_definitions', 'approval_matrix_steps')
      then 'workflow.configure'
    when p_resource = 'report_definitions'
      then case when p_manage then 'analytics.reports.manage' else 'analytics.reports.view' end
    else null
  end;
$$;

create function core.wave2_request_hash(
  p_command_name text,
  p_tenant_id uuid,
  p_legal_entity_id uuid,
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
        p_tenant_id::text,
        coalesce(p_legal_entity_id::text, ''),
        coalesce(p_expected_version::text, ''),
        coalesce(p_payload, 'null'::jsonb)::text
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create function core.wave2_replay(
  p_tenant_id uuid,
  p_command_name text,
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
  if v_actor is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required.';
  end if;
  if p_idempotency_key is null then
    raise exception using
      errcode = '22023',
      message = 'Idempotency key is required.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text || ':' || p_idempotency_key::text, 0)
  );

  select cr.* into v_receipt
  from core.command_receipts as cr
  where cr.actor_id = v_actor
    and cr.idempotency_key = p_idempotency_key;

  if found then
    if v_receipt.tenant_id <> p_tenant_id
       or v_receipt.command_name <> p_command_name
       or v_receipt.request_hash is distinct from p_request_hash then
      raise exception using
        errcode = '22023',
        message = 'Idempotency key was used for a different request.';
    end if;
    return v_receipt.response;
  end if;

  return null;
end;
$$;

create function core.wave2_assert_expected_version(
  p_current_version bigint,
  p_expected_version bigint
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
      message = 'Entity version does not match the expected version.';
  end if;
end;
$$;

create function core.wave2_finish_command(
  p_tenant_id uuid,
  p_command_name text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_idempotency_key uuid,
  p_request_hash text,
  p_before jsonb,
  p_entity jsonb,
  p_legal_entity_id uuid default null,
  p_branch_id uuid default null,
  p_warnings jsonb default '[]'::jsonb,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_request_id uuid := coalesce(p_request_id, gen_random_uuid());
  v_response jsonb;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if jsonb_typeof(coalesce(p_warnings, '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = 'Warnings must be an array.';
  end if;

  v_response := jsonb_build_object(
    'request_id', v_request_id,
    'entity', p_entity,
    'warnings', coalesce(p_warnings, '[]'::jsonb)
  );

  insert into audit.events (
    tenant_id, actor_id, request_id, event_type, aggregate_type,
    aggregate_id, legal_entity_id, branch_id, before_context,
    after_context, metadata
  ) values (
    p_tenant_id,
    v_actor,
    v_request_id,
    p_command_name,
    p_aggregate_type,
    p_aggregate_id,
    p_legal_entity_id,
    p_branch_id,
    p_before,
    p_entity,
    jsonb_build_object('idempotency_key', p_idempotency_key)
  );

  insert into core.outbox_events (
    tenant_id, topic, aggregate_type, aggregate_id, payload
  ) values (
    p_tenant_id,
    p_command_name,
    p_aggregate_type,
    p_aggregate_id,
    jsonb_build_object(
      'request_id', v_request_id,
      'actor_id', v_actor,
      'entity_version', p_entity->'version'
    )
  );

  insert into core.command_receipts (
    tenant_id, actor_id, idempotency_key, command_name,
    request_id, request_hash, response
  ) values (
    p_tenant_id,
    v_actor,
    p_idempotency_key,
    p_command_name,
    v_request_id,
    p_request_hash,
    v_response
  );

  return v_response;
end;
$$;

create function core.report_contract_allowed(
  p_source_view text,
  p_columns jsonb,
  p_filters jsonb default '{}'::jsonb,
  p_sort jsonb default '[]'::jsonb
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_allowed text[];
begin
  v_allowed := case p_source_view
    when 'exchange_rates' then array[
      'id', 'tenant_id', 'legal_entity_id', 'code', 'name',
      'source_currency_code', 'target_currency_code', 'rate',
      'effective_date', 'rate_type', 'source', 'status', 'version',
      'created_at', 'updated_at'
    ]
    when 'tax_definitions' then array[
      'id', 'tenant_id', 'legal_entity_id', 'code', 'name', 'rate', 'kind',
      'inclusive', 'recoverable', 'valid_from', 'valid_to', 'status',
      'version', 'created_at', 'updated_at'
    ]
    when 'accounts' then array[
      'id', 'tenant_id', 'legal_entity_id', 'code', 'name', 'account_type',
      'normal_balance', 'parent_id', 'is_posting', 'currency_code', 'status',
      'version', 'created_at', 'updated_at'
    ]
    when 'fiscal_periods' then array[
      'id', 'tenant_id', 'legal_entity_id', 'code', 'name', 'start_date',
      'end_date', 'state', 'status', 'version', 'created_at', 'updated_at'
    ]
    when 'parties' then array[
      'id', 'tenant_id', 'code', 'name', 'legal_name', 'display_name', 'kind',
      'tax_identifier', 'email', 'phone', 'city', 'country_code',
      'credit_limit', 'credit_currency_code', 'payment_terms_days', 'status',
      'version', 'created_at', 'updated_at'
    ]
    when 'contacts' then array[
      'id', 'tenant_id', 'party_id', 'code', 'name', 'role', 'email', 'phone',
      'is_primary', 'status', 'version', 'created_at', 'updated_at'
    ]
    when 'units' then array[
      'id', 'tenant_id', 'code', 'name', 'symbol', 'category', 'precision',
      'status', 'version', 'created_at', 'updated_at'
    ]
    when 'products' then array[
      'id', 'tenant_id', 'legal_entity_id', 'code', 'sku', 'name', 'kind',
      'base_unit_id', 'tracking_mode', 'can_sell', 'can_purchase',
      'tax_definition_id', 'status', 'version', 'created_at', 'updated_at'
    ]
    when 'document_sequences' then array[
      'id', 'tenant_id', 'legal_entity_id', 'branch_id', 'code', 'name',
      'document_type', 'prefix', 'suffix', 'padding', 'reset_policy',
      'next_value', 'status', 'version', 'created_at', 'updated_at'
    ]
    when 'workflow_definitions' then array[
      'id', 'tenant_id', 'legal_entity_id', 'code', 'name', 'document_type',
      'revision', 'lifecycle', 'status', 'version', 'created_at', 'updated_at'
    ]
    when 'approval_matrix_steps' then array[
      'id', 'tenant_id', 'workflow_definition_id', 'code', 'name', 'role_id',
      'step_order', 'minimum_amount', 'maximum_amount', 'currency_code',
      'status', 'version', 'created_at', 'updated_at'
    ]
    when 'report_definitions' then array[
      'id', 'tenant_id', 'code', 'name', 'title', 'source_view', 'columns',
      'filters', 'sort', 'row_limit', 'is_shared', 'owner_id', 'status',
      'version', 'created_at', 'updated_at'
    ]
    else null
  end;

  if v_allowed is null
     or jsonb_typeof(p_columns) <> 'array'
     or jsonb_array_length(p_columns) = 0
     or jsonb_typeof(p_filters) <> 'object'
     or jsonb_typeof(p_sort) <> 'array' then
    return false;
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_columns) as item
    where jsonb_typeof(item) <> 'string'
      or item #>> '{}' <> all(v_allowed)
  ) then
    return false;
  end if;

  if exists (
    select 1 from jsonb_object_keys(p_filters) as key
    where key <> all(v_allowed)
  ) then
    return false;
  end if;

  if exists (
    select 1 from jsonb_array_elements_text(p_sort) as item(value)
    where ltrim(item.value, '-') <> all(v_allowed)
  ) then
    return false;
  end if;

  return true;
end;
$$;

revoke execute on function core.wave2_permission(text, boolean),
  core.wave2_request_hash(text, uuid, uuid, jsonb, bigint),
  core.wave2_replay(uuid, text, uuid, text),
  core.wave2_assert_expected_version(bigint, bigint),
  core.wave2_finish_command(
    uuid, text, text, uuid, uuid, text, jsonb, jsonb, uuid, uuid, jsonb, uuid
  ),
  core.report_contract_allowed(text, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
