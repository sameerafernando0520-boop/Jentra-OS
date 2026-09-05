-- Additive AC-302 corrections. Earlier applied migrations remain immutable.
-- Strict decimal JSON input, scoped workflow precedence, and durable conversion links.

create or replace function workflow.wave3_crm_transition(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_from_status text,
  p_to_status text
)
returns table (definition_id uuid, definition_revision integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_definition_id uuid;
  v_revision integer;
  v_lifecycle jsonb;
begin
  select wd.id, wd.revision, wd.lifecycle
    into v_definition_id, v_revision, v_lifecycle
  from workflow.workflow_definitions as wd
  where wd.tenant_id = p_tenant_id
    and wd.document_type = 'crm_lead'
    and wd.status = 'active'
    and (wd.legal_entity_id = p_legal_entity_id or wd.legal_entity_id is null)
  order by (wd.legal_entity_id = p_legal_entity_id) desc nulls last, wd.revision desc
  limit 1;

  if v_definition_id is null then
    raise exception using
      errcode = '55000',
      message = 'WORKFLOW_CONFIGURATION_ERROR';
  end if;
  if p_from_status is not null and not (
    (v_lifecycle->'transitions') @>
      jsonb_build_array(jsonb_build_array(p_from_status, p_to_status))
  ) then
    raise exception using
      errcode = '55000',
      message = 'WORKFLOW_TRANSITION_INVALID';
  end if;

  definition_id := v_definition_id;
  definition_revision := v_revision;
  return next;
end;
$$;

create or replace function api.upsert_lead(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_command_id uuid,
  p_idempotency_key uuid,
  p_client_timestamp timestamptz,
  p_payload jsonb,
  p_expected_entity_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_command_name constant text := 'upsert_lead';
  v_request_hash text;
  v_replay jsonb;
  v_is_update boolean;
  v_id uuid;
  v_before jsonb;
  v_entity jsonb;
  v_row crm.leads%rowtype;
  v_previous_stage text;
  v_previous_entered_at timestamptz;
  v_expected_value numeric(20, 6);
  v_party_id uuid;
  v_contact_id uuid;
  v_owner_id uuid;
  v_stage text;
  v_status text;
  v_qualification jsonb;
  v_source_context jsonb;
  v_workflow_id uuid;
  v_workflow_revision integer;
  v_process_event jsonb;
  v_request_id uuid := gen_random_uuid();
  v_correlation_id uuid := v_request_id;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'crm.leads.manage', p_legal_entity_id, p_branch_id
  );
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'Command payload must be an object.';
  end if;
  if p_command_id is null or p_idempotency_key is null
     or p_client_timestamp is null then
    raise exception using errcode = '22023', message = 'Operational command identity is incomplete.';
  end if;

  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id,
    p_payload || jsonb_build_object('_client_timestamp', p_client_timestamp),
    p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key,
    v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  if p_payload ? 'expected_value' and jsonb_typeof(p_payload->'expected_value') <> 'string' then
    raise exception using errcode='22023', message='Expected value must be a decimal string.';
  end if;

  v_source_context := coalesce(p_payload->'source_context', '{}'::jsonb);
  if jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Source context must be an object.';
  end if;
  v_is_update := nullif(p_payload->>'id', '') is not null;
  v_id := case
    when v_is_update then (p_payload->>'id')::uuid
    else gen_random_uuid()
  end;
  if not v_is_update and p_expected_entity_version is not null then
    raise exception using
      errcode = '22023',
      message = 'Expected version is only valid for an existing lead.';
  end if;

  if v_is_update then
    select l.* into v_row
    from crm.leads as l
    where l.id = v_id
      and l.tenant_id = p_tenant_id
      and l.legal_entity_id = p_legal_entity_id
      and l.branch_id is not distinct from p_branch_id
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'Lead was not found.';
    end if;
    v_before := crm.wave3_lead_json(v_row);
    perform core.wave3_assert_expected_version(
      v_row.version, p_expected_entity_version, v_before
    );
    if v_row.status = 'converted' then
      raise exception using errcode = '55000', message = 'CONVERTED_LEAD_IMMUTABLE';
    end if;
    v_previous_stage := v_row.stage;
    v_previous_entered_at := v_row.stage_entered_at;
  end if;

  if coalesce(trim(p_payload->>'code'), '') = ''
     or coalesce(trim(p_payload->>'name'), '') = ''
     or coalesce(trim(p_payload->>'source'), '') = '' then
    raise exception using
      errcode = '22023',
      message = 'Lead code, name, and source are required.';
  end if;
  if coalesce(p_payload->>'lead_type', '') not in ('person', 'organization') then
    raise exception using errcode = '22023', message = 'Lead type is invalid.';
  end if;

  v_owner_id := nullif(p_payload->>'owner_id', '')::uuid;
  perform crm.wave3_validate_owner(p_tenant_id, v_owner_id);
  v_party_id := nullif(p_payload->>'party_id', '')::uuid;
  v_contact_id := nullif(p_payload->>'contact_id', '')::uuid;
  perform crm.wave3_validate_party_contact(
    p_tenant_id, v_party_id, v_contact_id
  );

  v_expected_value := crm.wave3_decimal_6(
    p_payload->>'expected_value', 'Expected value'
  );
  if coalesce(p_payload->>'currency_code', '') !~ '^[A-Za-z]{3}$'
     or not exists (
       select 1 from core.currencies as c
       where c.code = upper(p_payload->>'currency_code') and c.active
     ) then
    raise exception using errcode = '22023', message = 'Currency code is invalid.';
  end if;

  v_stage := coalesce(nullif(p_payload->>'stage', ''), 'draft');
  v_status := coalesce(nullif(p_payload->>'status', ''), 'active');
  v_qualification := coalesce(p_payload->'qualification_data', '{}'::jsonb);
  if jsonb_typeof(v_qualification) <> 'object' then
    raise exception using errcode = '22023', message = 'Qualification data must be an object.';
  end if;
  if v_stage = 'approved' and v_qualification = '{}'::jsonb then
    raise exception using
      errcode = '22023',
      message = 'Qualification data is required before approval.';
  end if;
  if v_stage in ('rejected', 'cancelled')
     and coalesce(trim(p_payload->>'loss_reason'), '') = '' then
    raise exception using
      errcode = '22023',
      message = 'A loss reason is required for a rejected or cancelled lead.';
  end if;
  if v_stage = 'posted' or v_status = 'converted' then
    raise exception using
      errcode = '22023',
      message = 'Only convert_lead can mark a lead as converted.';
  end if;

  if not v_is_update then
    if v_stage <> 'draft' then
      raise exception using errcode = '22023', message = 'A new lead must start in draft.';
    end if;
    select transition.definition_id, transition.definition_revision
      into v_workflow_id, v_workflow_revision
    from workflow.wave3_crm_transition(
      p_tenant_id, p_legal_entity_id, null, v_stage
    ) as transition;
  elsif v_stage <> v_previous_stage then
    if coalesce(trim(p_payload->>'transition_reason'), '') = '' then
      raise exception using
        errcode = '22023',
        message = 'A stage transition reason is required.';
    end if;
    select transition.definition_id, transition.definition_revision
      into v_workflow_id, v_workflow_revision
    from workflow.wave3_crm_transition(
      p_tenant_id, p_legal_entity_id, v_previous_stage, v_stage
    ) as transition;
  end if;

  if v_is_update then
    update crm.leads set
      code = upper(trim(p_payload->>'code')),
      lead_type = p_payload->>'lead_type',
      name = trim(p_payload->>'name'),
      contact_name = nullif(trim(p_payload->>'contact_name'), ''),
      email = nullif(trim(p_payload->>'email'), ''),
      phone = nullif(trim(p_payload->>'phone'), ''),
      party_id = v_party_id,
      contact_id = v_contact_id,
      source = trim(p_payload->>'source'),
      owner_id = v_owner_id,
      stage = v_stage,
      stage_entered_at = case
        when v_stage <> v_previous_stage then clock_timestamp()
        else stage_entered_at
      end,
      expected_value = v_expected_value,
      currency_code = upper(p_payload->>'currency_code'),
      expected_close_date = (p_payload->>'expected_close_date')::date,
      qualification_data = v_qualification,
      loss_reason = nullif(trim(p_payload->>'loss_reason'), ''),
      status = v_status,
      request_id = v_request_id,
      command_id = p_command_id,
      correlation_id = v_correlation_id,
      source_context = v_source_context,
      client_timestamp = p_client_timestamp,
      updated_by = v_actor
    where id = v_id
    returning * into v_row;
  else
    insert into crm.leads (
      id, tenant_id, legal_entity_id, branch_id, code, lead_type, name,
      contact_name, email, phone, party_id, contact_id, source, owner_id,
      stage, expected_value, currency_code, expected_close_date,
      qualification_data, loss_reason, status, request_id, command_id,
      correlation_id, source_context, client_timestamp, created_by, updated_by
    ) values (
      v_id, p_tenant_id, p_legal_entity_id, p_branch_id,
      upper(trim(p_payload->>'code')), p_payload->>'lead_type',
      trim(p_payload->>'name'), nullif(trim(p_payload->>'contact_name'), ''),
      nullif(trim(p_payload->>'email'), ''),
      nullif(trim(p_payload->>'phone'), ''), v_party_id, v_contact_id,
      trim(p_payload->>'source'), v_owner_id, v_stage, v_expected_value,
      upper(p_payload->>'currency_code'),
      (p_payload->>'expected_close_date')::date, v_qualification,
      nullif(trim(p_payload->>'loss_reason'), ''), v_status,
      v_request_id, p_command_id, v_correlation_id, v_source_context,
      p_client_timestamp, v_actor, v_actor
    ) returning * into v_row;
  end if;

  v_entity := crm.wave3_lead_json(v_row);
  if not v_is_update then
    v_process_event := jsonb_build_object(
      'workflow_definition_id', v_workflow_id,
      'workflow_revision', v_workflow_revision,
      'to_status', v_stage,
      'owner_id', v_owner_id,
      'entered_at', v_row.stage_entered_at
    );
  elsif v_stage <> v_previous_stage then
    v_process_event := jsonb_build_object(
      'workflow_definition_id', v_workflow_id,
      'workflow_revision', v_workflow_revision,
      'from_status', v_previous_stage,
      'to_status', v_stage,
      'owner_id', v_owner_id,
      'entered_at', v_previous_entered_at,
      'completed_at', v_row.stage_entered_at,
      'active_minutes', round(
        greatest(
          extract(epoch from (v_row.stage_entered_at - v_previous_entered_at))
            / 60,
          0
        )::numeric,
        6
      )::text,
      'wait_minutes', '0.000000',
      'reason', trim(p_payload->>'transition_reason')
    );
  end if;

  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'crm_lead', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context, v_process_event,
    jsonb_build_array(jsonb_build_object(
      'topic', case when v_is_update then 'crm.lead.updated' else 'crm.lead.created' end,
      'payload', jsonb_build_object('stage', v_stage, 'status', v_status)
    )),
    '[]'::jsonb, v_request_id, v_correlation_id
  );
end;
$$;

create or replace function api.upsert_opportunity(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_command_id uuid,
  p_idempotency_key uuid,
  p_client_timestamp timestamptz,
  p_payload jsonb,
  p_expected_entity_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_command_name constant text := 'upsert_opportunity';
  v_request_hash text;
  v_replay jsonb;
  v_is_update boolean;
  v_id uuid;
  v_before jsonb;
  v_entity jsonb;
  v_row crm.opportunities%rowtype;
  v_previous_stage text;
  v_expected_value numeric(20, 6);
  v_probability numeric(5, 2);
  v_party_id uuid;
  v_contact_id uuid;
  v_source_lead_id uuid;
  v_owner_id uuid;
  v_stage text;
  v_status text;
  v_forecast_bucket text;
  v_products jsonb;
  v_source_context jsonb;
  v_process_event jsonb;
  v_request_id uuid := gen_random_uuid();
  v_correlation_id uuid := v_request_id;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'crm.opportunities.manage', p_legal_entity_id, p_branch_id
  );
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'Command payload must be an object.';
  end if;
  if p_command_id is null or p_idempotency_key is null
     or p_client_timestamp is null then
    raise exception using errcode = '22023', message = 'Operational command identity is incomplete.';
  end if;

  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id,
    p_payload || jsonb_build_object('_client_timestamp', p_client_timestamp),
    p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key,
    v_request_hash
  );
  if v_replay is not null then return v_replay; end if;

  if p_payload ? 'expected_value' and jsonb_typeof(p_payload->'expected_value') <> 'string' then
    raise exception using errcode='22023', message='Expected value must be a decimal string.';
  end if;
  if p_payload ? 'probability' and jsonb_typeof(p_payload->'probability') <> 'string' then
    raise exception using errcode='22023', message='Probability must be a decimal string.';
  end if;

  v_source_context := coalesce(p_payload->'source_context', '{}'::jsonb);
  if jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Source context must be an object.';
  end if;
  v_is_update := nullif(p_payload->>'id', '') is not null
    and exists (
      select 1 from crm.opportunities as o
      where o.id = (p_payload->>'id')::uuid
        and o.tenant_id = p_tenant_id
        and o.legal_entity_id = p_legal_entity_id
        and o.branch_id is not distinct from p_branch_id
    );
  v_id := coalesce(nullif(p_payload->>'id', '')::uuid, gen_random_uuid());
  if not v_is_update and p_expected_entity_version is not null then
    raise exception using
      errcode = '22023',
      message = 'Expected version is only valid for an existing opportunity.';
  end if;
  if v_is_update then
    select o.* into v_row
    from crm.opportunities as o
    where o.id = v_id and o.tenant_id = p_tenant_id
      and o.legal_entity_id = p_legal_entity_id
      and o.branch_id is not distinct from p_branch_id
    for update;
    v_before := crm.wave3_opportunity_json(v_row);
    perform core.wave3_assert_expected_version(
      v_row.version, p_expected_entity_version, v_before
    );
    v_previous_stage := v_row.stage;
  end if;

  if coalesce(trim(p_payload->>'code'), '') = '' then
    raise exception using errcode = '22023', message = 'Opportunity code is required.';
  end if;
  v_party_id := nullif(p_payload->>'party_id', '')::uuid;
  v_contact_id := nullif(p_payload->>'contact_id', '')::uuid;
  perform crm.wave3_validate_party_contact(
    p_tenant_id, v_party_id, v_contact_id
  );
  if v_party_id is null
     and coalesce(trim(p_payload->>'prospect_name'), '') = '' then
    raise exception using
      errcode = '22023',
      message = 'Opportunity requires a party or prospect name.';
  end if;
  v_source_lead_id := nullif(p_payload->>'source_lead_id', '')::uuid;
  if v_source_lead_id is not null and not exists (
    select 1 from crm.leads as l
    where l.tenant_id = p_tenant_id and l.id = v_source_lead_id
      and l.legal_entity_id = p_legal_entity_id
      and l.branch_id is not distinct from p_branch_id
  ) then
    raise exception using errcode = '22023', message = 'Source lead is outside the command scope.';
  end if;
  if v_is_update and exists (
    select 1 from crm.leads l where l.tenant_id=p_tenant_id
      and l.converted_opportunity_id=v_id
      and (v_source_lead_id is distinct from l.id
        or v_party_id is distinct from l.party_id
        or v_contact_id is distinct from l.contact_id)
  ) then
    raise exception using errcode='55000', message='CONVERSION_LINKS_IMMUTABLE';
  end if;
  v_owner_id := nullif(p_payload->>'owner_id', '')::uuid;
  perform crm.wave3_validate_owner(p_tenant_id, v_owner_id);
  v_probability := crm.wave3_probability(p_payload->>'probability');
  v_expected_value := crm.wave3_decimal_6(
    p_payload->>'expected_value', 'Expected value'
  );
  if coalesce(p_payload->>'currency_code', '') !~ '^[A-Za-z]{3}$'
     or not exists (
       select 1 from core.currencies as c
       where c.code = upper(p_payload->>'currency_code') and c.active
     ) then
    raise exception using errcode = '22023', message = 'Currency code is invalid.';
  end if;
  v_products := coalesce(p_payload->'products_of_interest', '[]'::jsonb);
  if jsonb_typeof(v_products) <> 'array' then
    raise exception using errcode = '22023', message = 'Products of interest must be an array.';
  end if;
  v_stage := coalesce(nullif(p_payload->>'stage', ''), 'draft');
  v_status := coalesce(nullif(p_payload->>'status', ''), 'open');
  v_forecast_bucket := coalesce(
    nullif(p_payload->>'forecast_bucket', ''), 'pipeline'
  );
  if v_status = 'won' and not (
    v_stage = 'closed' and v_probability = 100
    and v_forecast_bucket = 'closed'
    and coalesce(trim(p_payload->>'won_loss_reason'), '') <> ''
  ) then
    raise exception using
      errcode = '22023',
      message = 'Won opportunities require closed stage, 100 probability, closed forecast, and a reason.';
  end if;
  if v_status = 'lost' and not (
    v_stage in ('closed', 'rejected', 'cancelled') and v_probability = 0
    and v_forecast_bucket = 'closed'
    and coalesce(trim(p_payload->>'won_loss_reason'), '') <> ''
  ) then
    raise exception using
      errcode = '22023',
      message = 'Lost opportunities require a closed stage, zero probability, closed forecast, and a reason.';
  end if;
  if v_is_update and v_stage <> v_previous_stage
     and coalesce(trim(p_payload->>'transition_reason'), '') = '' then
    raise exception using
      errcode = '22023',
      message = 'A stage transition reason is required.';
  end if;

  if v_is_update then
    update crm.opportunities set
      code = upper(trim(p_payload->>'code')),
      source_lead_id = v_source_lead_id,
      party_id = v_party_id,
      contact_id = v_contact_id,
      prospect_name = nullif(trim(p_payload->>'prospect_name'), ''),
      owner_id = v_owner_id,
      stage = v_stage,
      probability = v_probability,
      expected_value = v_expected_value,
      currency_code = upper(p_payload->>'currency_code'),
      expected_close_date = (p_payload->>'expected_close_date')::date,
      next_action = nullif(trim(p_payload->>'next_action'), ''),
      products_of_interest = v_products,
      forecast_bucket = v_forecast_bucket,
      won_loss_reason = nullif(trim(p_payload->>'won_loss_reason'), ''),
      status = v_status,
      request_id = v_request_id,
      command_id = p_command_id,
      correlation_id = v_correlation_id,
      source_context = v_source_context,
      client_timestamp = p_client_timestamp,
      updated_by = v_actor
    where id = v_id
    returning * into v_row;
  else
    insert into crm.opportunities (
      id, tenant_id, legal_entity_id, branch_id, code, source_lead_id,
      party_id, contact_id, prospect_name, owner_id, stage, probability,
      expected_value, currency_code, expected_close_date, next_action,
      products_of_interest, forecast_bucket, won_loss_reason, status,
      request_id, command_id, correlation_id, source_context,
      client_timestamp, created_by, updated_by
    ) values (
      v_id, p_tenant_id, p_legal_entity_id, p_branch_id,
      upper(trim(p_payload->>'code')), v_source_lead_id, v_party_id,
      v_contact_id, nullif(trim(p_payload->>'prospect_name'), ''),
      v_owner_id, v_stage, v_probability, v_expected_value,
      upper(p_payload->>'currency_code'),
      (p_payload->>'expected_close_date')::date,
      nullif(trim(p_payload->>'next_action'), ''), v_products,
      v_forecast_bucket, nullif(trim(p_payload->>'won_loss_reason'), ''),
      v_status, v_request_id, p_command_id, v_correlation_id,
      v_source_context, p_client_timestamp, v_actor, v_actor
    ) returning * into v_row;
  end if;

  v_entity := crm.wave3_opportunity_json(v_row);
  if not v_is_update then
    v_process_event := jsonb_build_object(
      'to_status', v_stage, 'owner_id', v_owner_id,
      'entered_at', v_row.created_at
    );
  elsif v_stage <> v_previous_stage then
    v_process_event := jsonb_build_object(
      'from_status', v_previous_stage, 'to_status', v_stage,
      'owner_id', v_owner_id, 'entered_at', v_row.updated_at,
      'completed_at', v_row.updated_at,
      'reason', trim(p_payload->>'transition_reason')
    );
  end if;

  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'crm_opportunity', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context, v_process_event,
    jsonb_build_array(jsonb_build_object(
      'topic', case
        when v_is_update then 'crm.opportunity.updated'
        else 'crm.opportunity.created'
      end,
      'payload', jsonb_build_object(
        'stage', v_stage, 'status', v_status,
        'forecast_bucket', v_forecast_bucket
      )
    )),
    '[]'::jsonb, v_request_id, v_correlation_id
  );
end;
$$;

create or replace function api.convert_lead(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_command_id uuid,
  p_idempotency_key uuid,
  p_client_timestamp timestamptz,
  p_payload jsonb,
  p_expected_entity_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_command_name constant text := 'convert_lead';
  v_request_hash text;
  v_replay jsonb;
  v_lead_id uuid;
  v_lead crm.leads%rowtype;
  v_before jsonb;
  v_entity jsonb;
  v_party_id uuid;
  v_contact_id uuid;
  v_opportunity_id uuid;
  v_party_code text;
  v_opportunity_code text;
  v_probability numeric(5, 2);
  v_products jsonb;
  v_source_context jsonb;
  v_workflow_id uuid;
  v_workflow_revision integer;
  v_request_id uuid := gen_random_uuid();
  v_correlation_id uuid := v_request_id;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'crm.leads.convert', p_legal_entity_id, p_branch_id
  );
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'Command payload must be an object.';
  end if;
  if p_command_id is null or p_idempotency_key is null
     or p_client_timestamp is null then
    raise exception using errcode = '22023', message = 'Operational command identity is incomplete.';
  end if;

  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id,
    p_payload || jsonb_build_object('_client_timestamp', p_client_timestamp),
    p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key,
    v_request_hash
  );
  if v_replay is not null then return v_replay; end if;

  if p_payload ? 'opportunity_probability' and jsonb_typeof(p_payload->'opportunity_probability') <> 'string' then
    raise exception using errcode='22023', message='Opportunity probability must be a decimal string.';
  end if;

  v_source_context := coalesce(p_payload->'source_context', '{}'::jsonb);
  if jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Source context must be an object.';
  end if;
  v_lead_id := nullif(p_payload->>'lead_id', '')::uuid;
  select l.* into v_lead
  from crm.leads as l
  where l.id = v_lead_id
    and l.tenant_id = p_tenant_id
    and l.legal_entity_id = p_legal_entity_id
    and l.branch_id is not distinct from p_branch_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lead was not found.';
  end if;
  v_before := crm.wave3_lead_json(v_lead);

  if v_lead.status = 'converted' then
    v_entity := jsonb_build_object(
      'id', v_lead.id,
      'lead_id', v_lead.id,
      'party_id', v_lead.party_id,
      'contact_id', v_lead.contact_id,
      'opportunity_id', v_lead.converted_opportunity_id,
      'stage', v_lead.stage,
      'status', v_lead.status,
      'version', v_lead.version
    );
    return core.wave3_finish_command(
      p_tenant_id, v_command_name, p_command_id, 'crm_lead', v_lead.id,
      p_idempotency_key, v_request_hash, v_before, v_entity,
      p_legal_entity_id, p_branch_id, v_source_context, null,
      jsonb_build_array(jsonb_build_object(
        'topic', 'crm.lead.conversion_replayed',
        'payload', jsonb_build_object(
          'opportunity_id', v_lead.converted_opportunity_id
        )
      )),
      jsonb_build_array('Lead was already converted; existing links returned.'),
      v_request_id, v_correlation_id
    );
  end if;
  if v_lead.status <> 'active' then
    raise exception using errcode='55000', message='LEAD_NOT_ACTIVE';
  end if;
  perform crm.wave3_validate_owner(p_tenant_id, v_lead.owner_id);
  if v_lead.stage <> 'approved' then
    raise exception using errcode = '55000', message = 'LEAD_NOT_QUALIFIED';
  end if;
  perform core.wave3_assert_expected_version(
    v_lead.version, p_expected_entity_version, v_before
  );
  select transition.definition_id, transition.definition_revision
    into v_workflow_id, v_workflow_revision
  from workflow.wave3_crm_transition(
    p_tenant_id, p_legal_entity_id, v_lead.stage, 'posted'
  ) as transition;

  v_party_id := coalesce(
    nullif(p_payload->>'party_id', '')::uuid,
    v_lead.party_id
  );
  if v_party_id is not null then
    perform crm.wave3_validate_party_contact(p_tenant_id, v_party_id, null);
  else
    v_party_id := gen_random_uuid();
    v_party_code := upper(trim(coalesce(
      nullif(p_payload->>'party_code', ''),
      'CUS-' || substr(replace(v_party_id::text, '-', ''), 1, 12)
    )));
    insert into crm.parties (
      id, tenant_id, code, legal_name, display_name, kind, email, phone,
      credit_currency_code, request_id, command_id, correlation_id,
      source_context, client_timestamp, created_by, updated_by
    ) values (
      v_party_id, p_tenant_id, v_party_code, v_lead.name, v_lead.name,
      'customer', v_lead.email, v_lead.phone, v_lead.currency_code,
      v_request_id, p_command_id, v_correlation_id, v_source_context,
      p_client_timestamp, v_actor, v_actor
    );
  end if;

  v_contact_id := coalesce(
    nullif(p_payload->>'contact_id', '')::uuid,
    v_lead.contact_id
  );
  if v_contact_id is not null then
    perform crm.wave3_validate_party_contact(
      p_tenant_id, v_party_id, v_contact_id
    );
  else
    v_contact_id := gen_random_uuid();
    insert into crm.contacts (
      id, tenant_id, party_id, name, role, email, phone, is_primary,
      request_id, command_id, correlation_id, source_context,
      client_timestamp, created_by, updated_by
    ) values (
      v_contact_id, p_tenant_id, v_party_id,
      coalesce(
        nullif(trim(p_payload->>'contact_name'), ''),
        v_lead.contact_name,
        v_lead.name
      ),
      nullif(trim(p_payload->>'contact_role'), ''),
      v_lead.email, v_lead.phone,
      not exists (
        select 1 from crm.contacts as c
        where c.tenant_id = p_tenant_id and c.party_id = v_party_id
          and c.status = 'active' and c.is_primary
      ),
      v_request_id, p_command_id, v_correlation_id, v_source_context,
      p_client_timestamp, v_actor, v_actor
    );
  end if;

  v_probability := crm.wave3_probability(
    coalesce(nullif(p_payload->>'opportunity_probability', ''), '50.00')
  );
  v_products := coalesce(p_payload->'products_of_interest', '[]'::jsonb);
  if jsonb_typeof(v_products) <> 'array' then
    raise exception using errcode = '22023', message = 'Products of interest must be an array.';
  end if;
  v_opportunity_id := gen_random_uuid();
  v_opportunity_code := upper(trim(coalesce(
    nullif(p_payload->>'opportunity_code', ''),
    'OPP-' || substr(replace(v_opportunity_id::text, '-', ''), 1, 12)
  )));
  insert into crm.opportunities (
    id, tenant_id, legal_entity_id, branch_id, code, source_lead_id,
    party_id, contact_id, owner_id, stage, probability, expected_value,
    currency_code, expected_close_date, next_action, products_of_interest,
    forecast_bucket, status, request_id, command_id, correlation_id,
    source_context, client_timestamp, created_by, updated_by
  ) values (
    v_opportunity_id, p_tenant_id, p_legal_entity_id, p_branch_id,
    v_opportunity_code, v_lead.id, v_party_id, v_contact_id,
    v_lead.owner_id, 'draft', v_probability, v_lead.expected_value,
    v_lead.currency_code, v_lead.expected_close_date,
    nullif(trim(p_payload->>'next_action'), ''), v_products,
    'pipeline', 'open', v_request_id, p_command_id, v_correlation_id,
    v_source_context, p_client_timestamp, v_actor, v_actor
  );

  insert into workflow.process_events (
    tenant_id,legal_entity_id,branch_id,document_type,document_id,
    to_status,actor_id,owner_id,entered_at,request_id,command_id,correlation_id
  ) select p_tenant_id,p_legal_entity_id,p_branch_id,'crm_opportunity',o.id,
    o.stage,v_actor,o.owner_id,o.created_at,v_request_id,p_command_id,v_correlation_id
  from crm.opportunities o where o.id=v_opportunity_id;

  update crm.leads set
    party_id = v_party_id,
    contact_id = v_contact_id,
    stage = 'posted',
    stage_entered_at = clock_timestamp(),
    status = 'converted',
    converted_opportunity_id = v_opportunity_id,
    converted_at = clock_timestamp(),
    converted_by = v_actor,
    request_id = v_request_id,
    command_id = p_command_id,
    correlation_id = v_correlation_id,
    source_context = v_source_context,
    client_timestamp = p_client_timestamp,
    updated_by = v_actor
  where id = v_lead.id
  returning * into v_lead;

  v_entity := jsonb_build_object(
    'id', v_lead.id,
    'lead_id', v_lead.id,
    'party_id', v_party_id,
    'contact_id', v_contact_id,
    'opportunity_id', v_opportunity_id,
    'stage', v_lead.stage,
    'status', v_lead.status,
    'version', v_lead.version,
    'expected_value', v_lead.expected_value::text,
    'currency_code', v_lead.currency_code
  );

  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'crm_lead', v_lead.id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    jsonb_build_object(
      'workflow_definition_id', v_workflow_id,
      'workflow_revision', v_workflow_revision,
      'from_status', 'approved',
      'to_status', 'posted',
      'owner_id', v_lead.owner_id,
      'entered_at', (v_before->>'stage_entered_at')::timestamptz,
      'completed_at', v_lead.stage_entered_at,
      'active_minutes', round(
        greatest(
          extract(epoch from (
            v_lead.stage_entered_at
              - (v_before->>'stage_entered_at')::timestamptz
          )) / 60,
          0
        )::numeric,
        6
      )::text,
      'wait_minutes', '0.000000',
      'reason', coalesce(
        nullif(trim(p_payload->>'conversion_reason'), ''),
        'Qualified lead converted'
      )
    ),
    jsonb_build_array(jsonb_build_object(
      'topic', 'crm.lead.converted',
      'payload', jsonb_build_object(
        'party_id', v_party_id,
        'contact_id', v_contact_id,
        'opportunity_id', v_opportunity_id
      )
    )),
    '[]'::jsonb, v_request_id, v_correlation_id
  );
end;
$$;

-- Every revision is captured atomically with the source write. Server timestamps,
-- never the caller's client_timestamp, determine the UTC as-of reporting boundary.
create table crm.pipeline_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  entity_type text not null check (entity_type in ('lead','opportunity','activity')),
  entity_id uuid not null,
  version bigint not null check (version>0),
  recorded_at timestamptz not null,
  subject_type text,
  snapshot jsonb not null check (jsonb_typeof(snapshot)='object'),
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  command_id uuid not null,
  correlation_id uuid not null,
  unique(tenant_id,entity_type,entity_id,version),
  foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
  foreign key(tenant_id,branch_id) references core.branches(tenant_id,id)
);
create index pipeline_history_scope_asof_idx
  on crm.pipeline_history(tenant_id,legal_entity_id,branch_id,entity_type,entity_id,recorded_at desc,version desc);
create index pipeline_history_branch_fk_idx on crm.pipeline_history(tenant_id,branch_id);
create index pipeline_history_actor_fk_idx on crm.pipeline_history(actor_id);
alter table crm.pipeline_history enable row level security;
alter table crm.pipeline_history force row level security;

-- Reusable read predicate keeps history and current activity permissions aligned.
create function crm.wave3_pipeline_readable(
 p_type text,p_subject text,p_tenant uuid,p_entity uuid,p_branch uuid
) returns boolean language sql stable security invoker set search_path='' as $$
 select core.is_tenant_member(p_tenant) and case p_type
 when 'lead' then
  core.has_permission(p_tenant,'crm.leads.view',p_entity,p_branch)
  or core.has_permission(p_tenant,'crm.leads.manage',p_entity,p_branch)
  or core.has_permission(p_tenant,'crm.leads.convert',p_entity,p_branch)
 when 'opportunity' then
  core.has_permission(p_tenant,'crm.opportunities.view',p_entity,p_branch)
  or core.has_permission(p_tenant,'crm.opportunities.manage',p_entity,p_branch)
 when 'activity' then
  core.has_permission(p_tenant,'crm.activities.manage',p_entity,p_branch)
  or (p_subject='lead' and core.has_permission(p_tenant,'crm.leads.view',p_entity,p_branch))
  or (p_subject='opportunity' and core.has_permission(p_tenant,'crm.opportunities.view',p_entity,p_branch))
  or (p_subject in ('party','contact') and core.has_permission(p_tenant,'crm.parties.view',p_entity,p_branch))
 else false end;
$$;
revoke all on function crm.wave3_pipeline_readable(text,text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function crm.wave3_pipeline_readable(text,text,uuid,uuid,uuid) to authenticated;
drop policy activities_permitted_read on crm.activities;
create policy activities_permitted_read on crm.activities for select to authenticated using (
 crm.wave3_pipeline_readable('activity',aggregate_type,tenant_id,legal_entity_id,branch_id)
);
create policy pipeline_history_permitted_read on crm.pipeline_history for select to authenticated using (
 crm.wave3_pipeline_readable(entity_type,subject_type,tenant_id,legal_entity_id,branch_id)
);
revoke all on crm.pipeline_history from public,anon,authenticated;
grant select on crm.pipeline_history to authenticated;
create view api.crm_pipeline_history with (security_invoker=true) as
select id,tenant_id,legal_entity_id,branch_id,entity_type,entity_id,version,
 recorded_at,subject_type,snapshot,actor_id,request_id,command_id,correlation_id
from crm.pipeline_history;
revoke all on api.crm_pipeline_history from public,anon,authenticated;
grant select on api.crm_pipeline_history to authenticated;

create function crm.wave3_capture_pipeline_history()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_snapshot jsonb;
begin
 v_snapshot:=to_jsonb(new);
 if tg_table_name='leads' then
  v_snapshot:=v_snapshot || jsonb_build_object('expected_value',new.expected_value::text);
 elsif tg_table_name='opportunities' then
  v_snapshot:=v_snapshot || jsonb_build_object('expected_value',new.expected_value::text,
    'probability',new.probability::text,'weighted_value',new.weighted_value::text);
 end if;
 insert into crm.pipeline_history(
  tenant_id,legal_entity_id,branch_id,entity_type,entity_id,version,recorded_at,
  subject_type,snapshot,actor_id,request_id,command_id,correlation_id
 ) values (
  new.tenant_id,new.legal_entity_id,new.branch_id,tg_argv[0],new.id,new.version,new.updated_at,
  v_snapshot->>'aggregate_type',v_snapshot,new.updated_by,new.request_id,new.command_id,new.correlation_id
 );
 return new;
end;
$$;
revoke all on function crm.wave3_capture_pipeline_history() from public,anon,authenticated;
create trigger leads_capture_pipeline_history after insert or update on crm.leads
 for each row execute function crm.wave3_capture_pipeline_history('lead');
create trigger opportunities_capture_pipeline_history after insert or update on crm.opportunities
 for each row execute function crm.wave3_capture_pipeline_history('opportunity');
create trigger activities_capture_pipeline_history after insert or update on crm.activities
 for each row execute function crm.wave3_capture_pipeline_history('activity');

-- Legacy baseline: only the last persisted version is known. Never invent older
-- values. The approved development project currently has no persisted CRM rows.
insert into crm.pipeline_history(
 tenant_id,legal_entity_id,branch_id,entity_type,entity_id,version,recorded_at,
 subject_type,snapshot,actor_id,request_id,command_id,correlation_id
)
select tenant_id,legal_entity_id,branch_id,'lead',id,version,updated_at,null,
 crm.wave3_lead_json(l),updated_by,request_id,command_id,correlation_id from crm.leads l
union all
select tenant_id,legal_entity_id,branch_id,'opportunity',id,version,updated_at,null,
 crm.wave3_opportunity_json(o),updated_by,request_id,command_id,correlation_id from crm.opportunities o
union all
select tenant_id,legal_entity_id,branch_id,'activity',id,version,updated_at,aggregate_type,
 to_jsonb(a),updated_by,request_id,command_id,correlation_id from crm.activities a;

create function crm.wave3_reject_pipeline_history_change()
returns trigger language plpgsql set search_path='' as $$
begin
 raise exception using errcode='55000',message='CRM_PIPELINE_HISTORY_IMMUTABLE';
end;
$$;
revoke all on function crm.wave3_reject_pipeline_history_change() from public,anon,authenticated;
create trigger pipeline_history_immutable before update or delete on crm.pipeline_history
 for each row execute function crm.wave3_reject_pipeline_history_change();

create or replace function api.get_crm_pipeline_summary(
 p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_as_of_date date
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
 if p_legal_entity_id is null then
  raise exception using errcode='22023',message='Legal entity is required.';
 end if;
 if p_as_of_date is null then
  raise exception using errcode='22023',message='As-of date is required.';
 end if;
 if not (
  core.has_permission(p_tenant_id,'crm.opportunities.view',p_legal_entity_id,p_branch_id)
  or core.has_permission(p_tenant_id,'crm.opportunities.manage',p_legal_entity_id,p_branch_id)
 ) then
  raise exception using errcode='42501',message='Permission denied.';
 end if;

 with latest as materialized (
  select distinct on (h.entity_type,h.entity_id) h.*
  from api.crm_pipeline_history h
  where h.tenant_id=p_tenant_id and h.legal_entity_id=p_legal_entity_id
   and (p_branch_id is null or h.branch_id=p_branch_id)
   and h.recorded_at < ((p_as_of_date+1)::timestamp at time zone 'UTC')
  order by h.entity_type,h.entity_id,h.recorded_at desc,h.version desc
 ), opportunities as materialized (
  select r.* from latest h
  cross join lateral jsonb_to_record(h.snapshot) as r(
   status text,stage text,currency_code text,expected_value text,weighted_value text,
   forecast_bucket text,created_at timestamptz
  ) where h.entity_type='opportunity'
 ), currency_totals as (
  select currency_code,count(*) as opportunity_count,
   round(sum(expected_value::numeric),6)::text as expected_value,
   round(sum(weighted_value::numeric),6)::text as weighted_value
  from opportunities where status<>'inactive' group by currency_code
 ), stage_totals as (
  select stage,currency_code,count(*) as opportunity_count,
   round(sum(expected_value::numeric),6)::text as expected_value,
   round(sum(weighted_value::numeric),6)::text as weighted_value
  from opportunities where status<>'inactive' group by stage,currency_code
 ), forecast_totals as (
  select forecast_bucket,currency_code,count(*) as opportunity_count,
   round(sum(expected_value::numeric),6)::text as expected_value,
   round(sum(weighted_value::numeric),6)::text as weighted_value
  from opportunities where status<>'inactive' group by forecast_bucket,currency_code
 ), conversion as (
  select count(*) as total_leads,
   count(*) filter(where snapshot->>'status'='converted') as converted_leads
  from latest where entity_type='lead' and snapshot->>'status'<>'inactive'
 ), activity as (
  select count(*) as activity_count,max((snapshot->>'activity_at')::timestamptz) as latest_activity_at
  from latest where entity_type='activity'
   and (snapshot->>'activity_at')::timestamptz < ((p_as_of_date+1)::timestamp at time zone 'UTC')
 ), ages as (
  select greatest(p_as_of_date-(created_at at time zone 'UTC')::date,0) as days
  from opportunities where status='open'
 )
 select jsonb_build_object(
  'as_of_date',to_char(p_as_of_date,'YYYY-MM-DD'),
  'currency_totals',coalesce((select jsonb_agg(to_jsonb(t) order by currency_code) from currency_totals t),'[]'::jsonb),
  'stage_totals',coalesce((select jsonb_agg(to_jsonb(t) order by stage,currency_code) from stage_totals t),'[]'::jsonb),
  'forecast_totals',coalesce((select jsonb_agg(to_jsonb(t) order by forecast_bucket,currency_code) from forecast_totals t),'[]'::jsonb),
  'conversion',(select to_jsonb(c)||jsonb_build_object('conversion_rate',
   case when total_leads=0 then '0.000000'
   else round(converted_leads::numeric*100/total_leads,6)::text end) from conversion c),
  'activity_recency',(select to_jsonb(a) from activity a),
  'win_loss',(select jsonb_build_object('won',count(*) filter(where status='won'),
    'lost',count(*) filter(where status='lost'),'decided',count(*) filter(where status in ('won','lost')))
    from opportunities),
  'aging',(select jsonb_build_object('age_basis','created_at','stale_after_days',90,
    'open_opportunity_count',count(*),'average_age_days',round(coalesce(avg(days),0),6)::text,
    'oldest_age_days',coalesce(max(days),0),'stale_opportunity_count',count(*) filter(where days>90))
    from ages)
 ) into v_result;
 return v_result;
end;
$$;
-- The old helper must not remain an independently callable stale reporting path.
revoke all on function crm.wave3_pipeline_summary_base(uuid,uuid,uuid,date) from public,anon,authenticated;
revoke all on function api.get_crm_pipeline_summary(uuid,uuid,uuid,date) from public,anon,authenticated;
grant execute on function api.get_crm_pipeline_summary(uuid,uuid,uuid,date) to authenticated;
comment on table crm.pipeline_history is 'Append-only CRM revisions for exact UTC end-of-day as-of reporting; legacy baseline starts at the last known version.';
comment on function api.get_crm_pipeline_summary(uuid,uuid,uuid,date) is 'RLS-scoped CRM history as of UTC end of day; currency-separated arbitrary-precision aggregate totals.';
notify pgrst,'reload schema';
