-- Wave 3 CRM pipeline commands.
--
-- Public mutations use the OperationalCommand envelope, replay through the
-- shared Wave 3 receipt contract, and finish receipt/audit/process/outbox
-- effects atomically. Exact commercial values are accepted only as strings.

-- ---------------------------------------------------------------------------
-- Private validation and serialization helpers.
-- ---------------------------------------------------------------------------

create function crm.wave3_decimal_6(
  p_value text,
  p_label text
)
returns numeric(20, 6)
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null
     or p_value !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then
    raise exception using
      errcode = '22023',
      message = p_label
        || ' must be a non-negative decimal string with at most six fractional digits.';
  end if;
  return p_value::numeric(20, 6);
end;
$$;

create function crm.wave3_probability(p_value text)
returns numeric(5, 2)
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null
     or p_value !~ '^(100(\.0{1,2})?|([0-9]|[1-9][0-9])(\.[0-9]{1,2})?)$' then
    raise exception using
      errcode = '22023',
      message = 'Probability must be a decimal string from zero to one hundred with at most two fractional digits.';
  end if;
  return p_value::numeric(5, 2);
end;
$$;

create function crm.wave3_validate_owner(
  p_tenant_id uuid,
  p_owner_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_owner_id is null or not exists (
    select 1
    from core.memberships as m
    where m.tenant_id = p_tenant_id
      and m.user_id = p_owner_id
      and m.status = 'active'
  ) then
    raise exception using
      errcode = '22023',
      message = 'CRM owner must be an active tenant member.';
  end if;
end;
$$;

create function crm.wave3_validate_party_contact(
  p_tenant_id uuid,
  p_party_id uuid,
  p_contact_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_party_id is not null and not exists (
    select 1 from crm.parties as p
    where p.tenant_id = p_tenant_id
      and p.id = p_party_id and p.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'CRM party is invalid.';
  end if;
  if p_contact_id is not null and (
    p_party_id is null or not exists (
      select 1 from crm.contacts as c
      where c.tenant_id = p_tenant_id
        and c.id = p_contact_id
        and c.party_id = p_party_id
        and c.status = 'active'
    )
  ) then
    raise exception using
      errcode = '22023',
      message = 'CRM contact does not belong to the selected party.';
  end if;
end;
$$;

create function workflow.wave3_crm_transition(
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
  order by (wd.legal_entity_id = p_legal_entity_id) desc, wd.revision desc
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

create function crm.wave3_lead_json(p_row crm.leads)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(p_row) || jsonb_build_object(
    'expected_value', p_row.expected_value::text
  );
$$;

create function crm.wave3_opportunity_json(p_row crm.opportunities)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(p_row) || jsonb_build_object(
    'probability', p_row.probability::text,
    'expected_value', p_row.expected_value::text,
    'weighted_value', p_row.weighted_value::text
  );
$$;

revoke all on function crm.wave3_decimal_6(text, text)
  from public, anon, authenticated;
revoke all on function crm.wave3_probability(text)
  from public, anon, authenticated;
revoke all on function crm.wave3_validate_owner(uuid, uuid)
  from public, anon, authenticated;
revoke all on function crm.wave3_validate_party_contact(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function workflow.wave3_crm_transition(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function crm.wave3_lead_json(crm.leads)
  from public, anon, authenticated;
revoke all on function crm.wave3_opportunity_json(crm.opportunities)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Lead create/revise command.
-- ---------------------------------------------------------------------------

create function api.upsert_lead(
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

-- ---------------------------------------------------------------------------
-- Timestamped CRM activity command.
-- ---------------------------------------------------------------------------

create function api.record_crm_activity(
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
  v_command_name constant text := 'record_crm_activity';
  v_request_hash text;
  v_replay jsonb;
  v_is_update boolean;
  v_id uuid;
  v_before jsonb;
  v_entity jsonb;
  v_row crm.activities%rowtype;
  v_aggregate_type text;
  v_aggregate_id uuid;
  v_aggregate_exists boolean;
  v_owner_id uuid;
  v_activity_at timestamptz;
  v_due_at timestamptz;
  v_completed_at timestamptz;
  v_status text;
  v_source_context jsonb;
  v_request_id uuid := gen_random_uuid();
  v_correlation_id uuid := v_request_id;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'crm.activities.manage', p_legal_entity_id, p_branch_id
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

  v_source_context := coalesce(p_payload->'source_context', '{}'::jsonb);
  if jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Source context must be an object.';
  end if;
  v_is_update := nullif(p_payload->>'id', '') is not null
    and exists (
      select 1 from crm.activities as a
      where a.id = (p_payload->>'id')::uuid
        and a.tenant_id = p_tenant_id
        and a.legal_entity_id = p_legal_entity_id
        and a.branch_id is not distinct from p_branch_id
    );
  v_id := coalesce(nullif(p_payload->>'id', '')::uuid, gen_random_uuid());
  if not v_is_update and p_expected_entity_version is not null then
    raise exception using
      errcode = '22023',
      message = 'Expected version is only valid for an existing CRM activity.';
  end if;
  if v_is_update then
    select a.* into v_row
    from crm.activities as a
    where a.id = v_id and a.tenant_id = p_tenant_id
      and a.legal_entity_id = p_legal_entity_id
      and a.branch_id is not distinct from p_branch_id
    for update;
    v_before := to_jsonb(v_row);
    perform core.wave3_assert_expected_version(
      v_row.version, p_expected_entity_version, v_before
    );
  end if;

  v_aggregate_type := p_payload->>'aggregate_type';
  v_aggregate_id := nullif(p_payload->>'aggregate_id', '')::uuid;
  if v_aggregate_type not in ('lead', 'opportunity', 'party', 'contact')
     or v_aggregate_id is null then
    raise exception using errcode = '22023', message = 'CRM aggregate is invalid.';
  end if;
  v_aggregate_exists := case v_aggregate_type
    when 'lead' then exists (
      select 1 from crm.leads as l
      where l.tenant_id = p_tenant_id and l.id = v_aggregate_id
        and l.legal_entity_id = p_legal_entity_id
        and l.branch_id is not distinct from p_branch_id
    )
    when 'opportunity' then exists (
      select 1 from crm.opportunities as o
      where o.tenant_id = p_tenant_id and o.id = v_aggregate_id
        and o.legal_entity_id = p_legal_entity_id
        and o.branch_id is not distinct from p_branch_id
    )
    when 'party' then exists (
      select 1 from crm.parties as p
      where p.tenant_id = p_tenant_id and p.id = v_aggregate_id
    )
    when 'contact' then exists (
      select 1 from crm.contacts as c
      where c.tenant_id = p_tenant_id and c.id = v_aggregate_id
    )
    else false
  end;
  if not v_aggregate_exists then
    raise exception using
      errcode = '22023',
      message = 'CRM aggregate is outside the command scope.';
  end if;

  if coalesce(p_payload->>'activity_type', '')
       !~ '^[a-z][a-z0-9_.-]{1,39}$'
     or coalesce(trim(p_payload->>'subject'), '') = '' then
    raise exception using errcode = '22023', message = 'Activity type and subject are required.';
  end if;
  v_owner_id := nullif(p_payload->>'owner_id', '')::uuid;
  perform crm.wave3_validate_owner(p_tenant_id, v_owner_id);
  v_activity_at := nullif(p_payload->>'activity_at', '')::timestamptz;
  v_due_at := nullif(p_payload->>'due_at', '')::timestamptz;
  v_completed_at := nullif(p_payload->>'completed_at', '')::timestamptz;
  v_status := coalesce(nullif(p_payload->>'status', ''), 'planned');
  if v_activity_at is null then
    raise exception using errcode = '22023', message = 'Activity timestamp is required.';
  end if;
  if v_due_at is not null and v_due_at < v_activity_at then
    raise exception using errcode = '22023', message = 'Activity due time is invalid.';
  end if;
  if (v_status = 'completed' and (
        v_completed_at is null or coalesce(trim(p_payload->>'outcome'), '') = ''
      ))
     or (v_status <> 'completed' and v_completed_at is not null) then
    raise exception using errcode = '22023', message = 'Activity completion state is invalid.';
  end if;

  if v_is_update then
    update crm.activities set
      aggregate_type = v_aggregate_type,
      aggregate_id = v_aggregate_id,
      activity_type = p_payload->>'activity_type',
      subject = trim(p_payload->>'subject'),
      owner_id = v_owner_id,
      activity_at = v_activity_at,
      due_at = v_due_at,
      completed_at = v_completed_at,
      outcome = nullif(trim(p_payload->>'outcome'), ''),
      notes = nullif(p_payload->>'notes', ''),
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
    insert into crm.activities (
      id, tenant_id, legal_entity_id, branch_id, aggregate_type,
      aggregate_id, activity_type, subject, owner_id, activity_at, due_at,
      completed_at, outcome, notes, status, request_id, command_id,
      correlation_id, source_context, client_timestamp, created_by, updated_by
    ) values (
      v_id, p_tenant_id, p_legal_entity_id, p_branch_id, v_aggregate_type,
      v_aggregate_id, p_payload->>'activity_type', trim(p_payload->>'subject'),
      v_owner_id, v_activity_at, v_due_at, v_completed_at,
      nullif(trim(p_payload->>'outcome'), ''), nullif(p_payload->>'notes', ''),
      v_status, v_request_id, p_command_id, v_correlation_id,
      v_source_context, p_client_timestamp, v_actor, v_actor
    ) returning * into v_row;
  end if;

  v_entity := to_jsonb(v_row);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'crm_activity', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context, null,
    jsonb_build_array(jsonb_build_object(
      'topic', 'crm.activity.recorded',
      'payload', jsonb_build_object(
        'aggregate_type', v_aggregate_type,
        'aggregate_id', v_aggregate_id,
        'status', v_status
      )
    )),
    '[]'::jsonb, v_request_id, v_correlation_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Opportunity create/revise command.
-- ---------------------------------------------------------------------------

create function api.upsert_opportunity(
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

-- ---------------------------------------------------------------------------
-- Qualified lead conversion. The lead lock and unique source-lead index make
-- semantic retries return one stable party/contact/opportunity aggregate set.
-- ---------------------------------------------------------------------------

create function api.convert_lead(
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

-- ---------------------------------------------------------------------------
-- Currency-separated, as-of pipeline summary. This is security invoker and
-- reads only the security-invoker API views, so the base RLS remains active.
-- ---------------------------------------------------------------------------

create function api.get_crm_pipeline_summary(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_as_of_date date
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_currency_totals jsonb;
  v_stage_totals jsonb;
  v_forecast_totals jsonb;
  v_total_leads bigint;
  v_converted_leads bigint;
  v_activity_count bigint;
  v_latest_activity timestamptz;
  v_won bigint;
  v_lost bigint;
begin
  if p_as_of_date is null then
    raise exception using errcode = '22023', message = 'As-of date is required.';
  end if;
  if not (
    core.has_permission(
      p_tenant_id, 'crm.opportunities.view', p_legal_entity_id, p_branch_id
    )
    or core.has_permission(
      p_tenant_id, 'crm.opportunities.manage', p_legal_entity_id, p_branch_id
    )
  ) then
    raise exception using errcode = '42501', message = 'Permission denied.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'currency_code', totals.currency_code,
        'opportunity_count', totals.opportunity_count,
        'expected_value', totals.expected_value,
        'weighted_value', totals.weighted_value
      ) order by totals.currency_code
    ),
    '[]'::jsonb
  ) into v_currency_totals
  from (
    select
      o.currency_code,
      count(*) as opportunity_count,
      sum(o.expected_value::numeric)::numeric(20, 6)::text as expected_value,
      sum(o.weighted_value::numeric)::numeric(20, 6)::text as weighted_value
    from api.crm_opportunities as o
    where o.tenant_id = p_tenant_id
      and o.legal_entity_id = p_legal_entity_id
      and (p_branch_id is null or o.branch_id = p_branch_id)
      and o.created_at::date <= p_as_of_date
      and o.status <> 'inactive'
    group by o.currency_code
  ) as totals;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'stage', stages.stage,
        'currency_code', stages.currency_code,
        'opportunity_count', stages.opportunity_count,
        'expected_value', stages.expected_value,
        'weighted_value', stages.weighted_value
      ) order by stages.stage, stages.currency_code
    ),
    '[]'::jsonb
  ) into v_stage_totals
  from (
    select o.stage, o.currency_code, count(*) as opportunity_count,
      sum(o.expected_value::numeric)::numeric(20, 6)::text as expected_value,
      sum(o.weighted_value::numeric)::numeric(20, 6)::text as weighted_value
    from api.crm_opportunities as o
    where o.tenant_id = p_tenant_id
      and o.legal_entity_id = p_legal_entity_id
      and (p_branch_id is null or o.branch_id = p_branch_id)
      and o.created_at::date <= p_as_of_date
      and o.status <> 'inactive'
    group by o.stage, o.currency_code
  ) as stages;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'forecast_bucket', forecasts.forecast_bucket,
        'currency_code', forecasts.currency_code,
        'opportunity_count', forecasts.opportunity_count,
        'expected_value', forecasts.expected_value,
        'weighted_value', forecasts.weighted_value
      ) order by forecasts.forecast_bucket, forecasts.currency_code
    ),
    '[]'::jsonb
  ) into v_forecast_totals
  from (
    select o.forecast_bucket, o.currency_code, count(*) as opportunity_count,
      sum(o.expected_value::numeric)::numeric(20, 6)::text as expected_value,
      sum(o.weighted_value::numeric)::numeric(20, 6)::text as weighted_value
    from api.crm_opportunities as o
    where o.tenant_id = p_tenant_id
      and o.legal_entity_id = p_legal_entity_id
      and (p_branch_id is null or o.branch_id = p_branch_id)
      and o.created_at::date <= p_as_of_date
      and o.status <> 'inactive'
    group by o.forecast_bucket, o.currency_code
  ) as forecasts;

  select count(*), count(*) filter (where l.status = 'converted')
    into v_total_leads, v_converted_leads
  from api.crm_leads as l
  where l.tenant_id = p_tenant_id
    and l.legal_entity_id = p_legal_entity_id
    and (p_branch_id is null or l.branch_id = p_branch_id)
    and l.created_at::date <= p_as_of_date
    and l.status <> 'inactive';

  select count(*), max(a.activity_at)
    into v_activity_count, v_latest_activity
  from api.crm_activities as a
  where a.tenant_id = p_tenant_id
    and a.legal_entity_id = p_legal_entity_id
    and (p_branch_id is null or a.branch_id = p_branch_id)
    and a.activity_at::date <= p_as_of_date;

  select count(*) filter (where o.status = 'won'),
         count(*) filter (where o.status = 'lost')
    into v_won, v_lost
  from api.crm_opportunities as o
  where o.tenant_id = p_tenant_id
    and o.legal_entity_id = p_legal_entity_id
    and (p_branch_id is null or o.branch_id = p_branch_id)
    and o.created_at::date <= p_as_of_date;

  return jsonb_build_object(
    'as_of_date', to_char(p_as_of_date, 'YYYY-MM-DD'),
    'currency_totals', v_currency_totals,
    'stage_totals', v_stage_totals,
    'forecast_totals', v_forecast_totals,
    'conversion', jsonb_build_object(
      'total_leads', v_total_leads,
      'converted_leads', v_converted_leads,
      'conversion_rate', case
        when v_total_leads = 0 then '0.000000'
        else round(
          v_converted_leads::numeric * 100 / v_total_leads::numeric,
          6
        )::numeric(20, 6)::text
      end
    ),
    'win_loss', jsonb_build_object(
      'won', v_won, 'lost', v_lost,
      'decided', v_won + v_lost
    ),
    'activity_recency', jsonb_build_object(
      'activity_count', v_activity_count,
      'latest_activity_at', v_latest_activity
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Explicit execution surface. PostgreSQL grants function execution to PUBLIC
-- by default, so every signature is revoked before authenticated is granted.
-- ---------------------------------------------------------------------------

revoke all on function api.upsert_lead(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.record_crm_activity(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.upsert_opportunity(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.convert_lead(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  from public, anon, authenticated;

grant execute on function api.upsert_lead(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.record_crm_activity(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.upsert_opportunity(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.convert_lead(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  to authenticated;

comment on function api.upsert_lead(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) is 'Idempotent Wave 3 lead create/revise command with workflow telemetry.';
comment on function api.convert_lead(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) is 'Idempotently converts one qualified lead into one party, contact, and opportunity.';
comment on function api.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  is 'Currency-separated exact CRM pipeline totals for an explicit as-of date.';

notify pgrst, 'reload schema';
