-- Corporate Audit & Assurance: reject a null expected version (PR #1 review).
-- CANDIDATE ONLY. Not installed. Requires A1-A5.
--
-- `version <> p_expected_version` is null when p_expected_version is null, so
-- the conflict branch never ran and a stale command could mutate the
-- aggregate. These are the installed A1, A2 and A3 command functions with
-- only the version comparisons changed: a null expected version is now a
-- version conflict, and creation requires exactly 0. `create or replace`
-- keeps the existing owners and grants.

create or replace function api.assurance_command(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_idempotency_key uuid,
  p_payload jsonb,
  p_expected_version bigint
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_action text;
  v_perm text;
  v_fields text[];
  v_hash text;
  v_receipt assurance.command_receipts%rowtype;
  v_eng assurance.engagements%rowtype;
  v_eid uuid;
  v_role text;
  v_agg_type text := 'engagement';
  v_agg_id uuid;
  v_from text;
  v_to text;
  v_details jsonb := '{}'::jsonb;
  v_req assurance.evidence_requests%rowtype;
  v_ctl assurance.engagement_controls%rowtype;
  v_exc assurance.exceptions%rowtype;
  v_fin assurance.findings%rowtype;
  v_hold assurance.retention_holds%rowtype;
  v_item_by uuid;
  v_uuid uuid;
  v_text text;
  v_date date;
  v_ts timestamptz;
  v_n bigint;
  v_snapshot jsonb;
  v_digest text;
  v_response jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or coalesce(jsonb_typeof(p_payload->'action'), '') <> 'string' then
    raise exception using errcode = '22023', message = 'ASSURANCE_ACTION_UNKNOWN';
  end if;
  v_action := p_payload->>'action';
  v_perm := assurance.action_permission(v_action);
  v_fields := assurance.action_fields(v_action);
  if v_perm is null or v_fields is null then
    raise exception using errcode = '22023', message = 'ASSURANCE_ACTION_UNKNOWN';
  end if;
  if exists (select 1 from jsonb_object_keys(p_payload) k where k <> all (v_fields)) then
    raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD';
  end if;

  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  -- Current authority is checked before replay, so revocation also hides replay.
  perform core.require_permission(p_tenant_id, v_perm, p_legal_entity_id, p_branch_id);

  v_hash := encode(extensions.digest(convert_to(jsonb_build_array(
    p_tenant_id, p_legal_entity_id, p_branch_id, p_expected_version, p_payload)::text, 'UTF8'),
    'sha256'), 'hex');
  select * into v_receipt from assurance.command_receipts
   where actor_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    if v_receipt.request_hash <> v_hash or v_receipt.tenant_id <> p_tenant_id then
      raise exception using errcode = '22023', message = 'IDEMPOTENCY_MISMATCH';
    end if;
    return v_receipt.response;
  end if;

  if assurance.mfa_action(v_action) and not assurance.recent_mfa() then
    perform assurance.deny('ASSURANCE_RECENT_MFA_REQUIRED');
  end if;

  v_eid := assurance.uuid_field(p_payload, 'engagement_id');
  v_agg_id := v_eid;

  if v_action = 'create_engagement' then
    if p_expected_version is distinct from 0 then
      raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
    end if;
    if exists (select 1 from assurance.engagements where id = v_eid) then
      raise exception using errcode = '23505', message = 'ASSURANCE_ENGAGEMENT_EXISTS';
    end if;
    v_uuid := assurance.uuid_field(p_payload, 'lead_auditor_id');
    if not assurance.active_member(p_tenant_id, v_uuid) then
      raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
    end if;
    if assurance.date_field(p_payload, 'period_end') < assurance.date_field(p_payload, 'period_start') then
      raise exception using errcode = '22023', message = 'ASSURANCE_PERIOD_INVALID';
    end if;
    insert into assurance.engagements(id, tenant_id, legal_entity_id, branch_id, name,
      period_start, period_end, scope_summary, lead_auditor_id, created_by)
    values (v_eid, p_tenant_id, p_legal_entity_id, p_branch_id,
      assurance.text_field(p_payload, 'name', 3, 160),
      assurance.date_field(p_payload, 'period_start'), assurance.date_field(p_payload, 'period_end'),
      assurance.text_field(p_payload, 'scope_summary', 3, 2000), v_uuid, v_uid)
    returning * into v_eng;
    insert into assurance.engagement_team(engagement_id, user_id, role, added_by)
    values (v_eid, v_uuid, 'lead', v_uid);
    v_to := 'planning';
  else
    select * into v_eng from assurance.engagements
     where id = v_eid and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
       and branch_id is not distinct from p_branch_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_ENGAGEMENT_NOT_FOUND';
    end if;
    if p_expected_version is null or v_eng.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
    end if;
    -- External reviewers are read-only even if a role grants command permissions.
    if exists (select 1 from assurance.engagement_team
                where engagement_id = v_eid and user_id = v_uid and role = 'external') then
      perform assurance.deny('ASSURANCE_EXTERNAL_READ_ONLY');
    end if;
    if v_eng.status in ('archived','cancelled') and v_action not in ('place_hold','release_hold') then
      perform assurance.state_error('ASSURANCE_ENGAGEMENT_CLOSED');
    end if;
    v_role := assurance.team_role(v_eid, v_uid);
  end if;

  case v_action
  when 'create_engagement' then
    null;

  when 'add_team_member' then
    if v_eng.status not in ('planning','fieldwork','reporting') then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    v_uuid := assurance.uuid_field(p_payload, 'user_id');
    v_text := p_payload->>'role';
    if v_text is null or v_text not in ('auditor','reviewer','external') then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'role';
    end if;
    if not assurance.active_member(p_tenant_id, v_uuid) then
      raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
    end if;
    if exists (select 1 from assurance.engagement_team where engagement_id = v_eid and user_id = v_uuid) then
      raise exception using errcode = '23505', message = 'ASSURANCE_TEAM_MEMBER_EXISTS';
    end if;
    if exists (select 1 from assurance.engagement_controls where engagement_id = v_eid and owner_id = v_uuid)
       or exists (select 1 from assurance.evidence_requests where engagement_id = v_eid and owner_id = v_uuid) then
      perform assurance.deny('ASSURANCE_INDEPENDENCE_REQUIRED');
    end if;
    if v_text = 'external' then
      if coalesce(jsonb_typeof(p_payload->'expires_at'), '') <> 'string' then
        raise exception using errcode = '22023', message = 'ASSURANCE_EXTERNAL_EXPIRY_REQUIRED';
      end if;
      v_ts := (p_payload->>'expires_at')::timestamptz;
      if v_ts <= now() or v_ts > now() + interval '90 days' then
        raise exception using errcode = '22023', message = 'ASSURANCE_EXTERNAL_EXPIRY_REQUIRED';
      end if;
    elsif p_payload ? 'expires_at' then
      raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD';
    else
      v_ts := null;
    end if;
    insert into assurance.engagement_team(engagement_id, user_id, role, expires_at, added_by)
    values (v_eid, v_uuid, v_text, v_ts, v_uid);
    v_agg_type := 'team_member'; v_agg_id := v_uuid;
    v_details := jsonb_build_object('role', v_text, 'expires_at', v_ts);

  when 'revoke_team_member' then
    v_uuid := assurance.uuid_field(p_payload, 'user_id');
    if v_uuid = v_eng.lead_auditor_id then
      perform assurance.state_error('ASSURANCE_LEAD_REQUIRED');
    end if;
    update assurance.engagement_team set revoked_at = clock_timestamp(), revoked_by = v_uid
     where engagement_id = v_eid and user_id = v_uuid and revoked_at is null;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_TEAM_MEMBER_NOT_FOUND';
    end if;
    v_agg_type := 'team_member'; v_agg_id := v_uuid;
    v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));

  when 'map_control' then
    if v_eng.status not in ('planning','fieldwork') then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    v_uuid := assurance.uuid_field(p_payload, 'owner_id');
    if not assurance.active_member(p_tenant_id, v_uuid) then
      raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
    end if;
    if exists (select 1 from assurance.engagement_team where engagement_id = v_eid and user_id = v_uuid) then
      perform assurance.deny('ASSURANCE_INDEPENDENCE_REQUIRED');
    end if;
    if (p_payload->>'risk') is null or (p_payload->>'risk') not in ('low','medium','high','critical')
       or (p_payload->>'control_code') is null
       or (p_payload->>'control_code') !~ '^[A-Z0-9][A-Z0-9._-]{1,39}$' then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID';
    end if;
    insert into assurance.engagement_controls(id, engagement_id, control_code, title, owner_id, risk, mapped_by)
    values (assurance.uuid_field(p_payload, 'control_id'), v_eid, p_payload->>'control_code',
      assurance.text_field(p_payload, 'title', 3, 160), v_uuid, p_payload->>'risk', v_uid);
    v_agg_type := 'control'; v_agg_id := (p_payload->>'control_id')::uuid;
    v_details := jsonb_build_object('control_code', p_payload->>'control_code', 'risk', p_payload->>'risk');

  when 'transition' then
    v_text := p_payload->>'to_status';
    v_from := v_eng.status;
    if v_from = 'planning' and v_text = 'fieldwork' then
      if not exists (select 1 from assurance.engagement_controls where engagement_id = v_eid) then
        perform assurance.state_error('ASSURANCE_CONTROLS_REQUIRED');
      end if;
    elsif v_from = 'fieldwork' and v_text = 'reporting' then
      if v_eng.evidence_frozen_at is null then
        perform assurance.state_error('ASSURANCE_EVIDENCE_FREEZE_REQUIRED');
      end if;
    elsif v_from = 'issued' and v_text = 'archived' then
      if exists (select 1 from assurance.findings
                  where engagement_id = v_eid and status not in ('closed','risk_accepted')
                    and not exists (select 1 from assurance.findings c where c.carried_from_finding_id = findings.id)) then
        perform assurance.state_error('ASSURANCE_OPEN_FINDINGS_NOT_CARRIED');
      end if;
    elsif v_from in ('planning','fieldwork','reporting') and v_text = 'cancelled' then
      null;
    else
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    update assurance.engagements set status = v_text where id = v_eid;
    v_to := v_text;
    v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));

  when 'request_evidence' then
    if v_eng.status not in ('planning','fieldwork') or v_eng.evidence_frozen_at is not null then
      perform assurance.state_error('ASSURANCE_EVIDENCE_FROZEN');
    end if;
    if v_role is null or v_role not in ('lead','auditor') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_ctl from assurance.engagement_controls
     where id = assurance.uuid_field(p_payload, 'control_id') and engagement_id = v_eid;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_CONTROL_NOT_FOUND';
    end if;
    v_uuid := assurance.uuid_field(p_payload, 'owner_id');
    if not assurance.active_member(p_tenant_id, v_uuid) then
      raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
    end if;
    if exists (select 1 from assurance.engagement_team where engagement_id = v_eid and user_id = v_uuid) then
      perform assurance.deny('ASSURANCE_INDEPENDENCE_REQUIRED');
    end if;
    v_date := assurance.date_field(p_payload, 'due_date');
    if v_date < current_date then
      raise exception using errcode = '22023', message = 'ASSURANCE_DUE_DATE_INVALID';
    end if;
    insert into assurance.evidence_requests(id, engagement_id, control_id, owner_id, description, due_date, requested_by)
    values (assurance.uuid_field(p_payload, 'request_id'), v_eid, v_ctl.id, v_uuid,
      assurance.text_field(p_payload, 'description', 3, 2000), v_date, v_uid);
    v_agg_type := 'evidence_request'; v_agg_id := (p_payload->>'request_id')::uuid;
    v_to := 'open';
    v_details := jsonb_build_object('control_id', v_ctl.id, 'owner_id', v_uuid, 'due_date', v_date);

  when 'cancel_request' then
    select * into v_req from assurance.evidence_requests
     where id = assurance.uuid_field(p_payload, 'request_id') and engagement_id = v_eid for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_REQUEST_NOT_FOUND';
    end if;
    if v_req.status <> 'open' or v_eng.evidence_frozen_at is not null then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    update assurance.evidence_requests set status = 'cancelled' where id = v_req.id;
    v_agg_type := 'evidence_request'; v_agg_id := v_req.id; v_from := 'open'; v_to := 'cancelled';
    v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));

  when 'submit_evidence' then
    if v_eng.status <> 'fieldwork' or v_eng.evidence_frozen_at is not null then
      perform assurance.state_error('ASSURANCE_EVIDENCE_FROZEN');
    end if;
    select * into v_req from assurance.evidence_requests
     where id = assurance.uuid_field(p_payload, 'request_id') and engagement_id = v_eid for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_REQUEST_NOT_FOUND';
    end if;
    if v_req.owner_id <> v_uid then
      perform assurance.deny('ASSURANCE_REQUEST_OWNER_REQUIRED');
    end if;
    if v_req.status <> 'open' then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    v_uuid := assurance.uuid_field(p_payload, 'evidence_id');
    if (p_payload->>'storage_ref') is distinct from
       format('assurance/%s/%s/%s', p_tenant_id, v_eid, v_uuid) then
      raise exception using errcode = '22023', message = 'ASSURANCE_STORAGE_REF_INVALID';
    end if;
    if coalesce(jsonb_typeof(p_payload->'byte_size'), '') <> 'number'
       or (p_payload->>'byte_size') !~ '^[1-9][0-9]{0,8}$' then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'byte_size';
    end if;
    v_ts := (assurance.text_field(p_payload, 'source_as_of', 10, 40))::timestamptz;
    if v_ts > now() then
      raise exception using errcode = '22023', message = 'ASSURANCE_SOURCE_CUTOFF_INVALID';
    end if;
    insert into assurance.evidence_items(id, engagement_id, request_id, source_module, source_reference,
      source_as_of, collection_method, query_version, sha256, byte_size, storage_ref, classification, collected_by)
    values (v_uuid, v_eid, v_req.id, p_payload->>'source_module',
      assurance.text_field(p_payload, 'source_reference', 1, 200), v_ts,
      p_payload->>'collection_method', p_payload->>'query_version',
      assurance.digest_field(p_payload, 'sha256'), (p_payload->>'byte_size')::bigint,
      p_payload->>'storage_ref', p_payload->>'classification', v_uid);
    update assurance.evidence_requests set status = 'submitted', current_evidence_id = v_uuid where id = v_req.id;
    v_agg_type := 'evidence_request'; v_agg_id := v_req.id; v_from := 'open'; v_to := 'submitted';
    v_details := jsonb_build_object('evidence_id', v_uuid, 'sha256', p_payload->>'sha256',
      'byte_size', (p_payload->>'byte_size')::bigint, 'source_module', p_payload->>'source_module',
      'source_as_of', v_ts, 'collection_method', p_payload->>'collection_method',
      'classification', p_payload->>'classification');

  when 'review_evidence' then
    if v_role is null or v_role not in ('lead','auditor','reviewer') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_req from assurance.evidence_requests
     where id = assurance.uuid_field(p_payload, 'request_id') and engagement_id = v_eid for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_REQUEST_NOT_FOUND';
    end if;
    if v_req.status <> 'submitted' or v_eng.evidence_frozen_at is not null then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    select collected_by into v_item_by from assurance.evidence_items where id = v_req.current_evidence_id;
    if v_item_by = v_uid then
      perform assurance.deny('ASSURANCE_SELF_REVIEW_FORBIDDEN');
    end if;
    v_text := p_payload->>'decision';
    if v_text = 'accept' then
      update assurance.evidence_requests set status = 'accepted' where id = v_req.id;
      v_to := 'accepted';
    elsif v_text = 'reject' then
      update assurance.evidence_requests set status = 'open', rework_count = rework_count + 1 where id = v_req.id;
      v_to := 'open';
    else
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'decision';
    end if;
    v_agg_type := 'evidence_request'; v_agg_id := v_req.id; v_from := 'submitted';
    v_details := jsonb_build_object('evidence_id', v_req.current_evidence_id,
      'reason', assurance.text_field(p_payload, 'reason', 3, 1000));

  when 'freeze_evidence' then
    if v_eng.status <> 'fieldwork' or v_eng.evidence_frozen_at is not null then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_uid <> v_eng.lead_auditor_id then
      perform assurance.deny('ASSURANCE_LEAD_REQUIRED');
    end if;
    if exists (select 1 from assurance.evidence_requests where engagement_id = v_eid and status in ('open','submitted')) then
      perform assurance.state_error('ASSURANCE_EVIDENCE_OUTSTANDING');
    end if;
    select count(*), encode(extensions.digest(convert_to(coalesce(string_agg(
             i.id::text || ':' || i.sha256 || ':' || i.byte_size::text, ',' order by i.id), ''), 'UTF8'), 'sha256'), 'hex')
      into v_n, v_digest
      from assurance.evidence_requests r join assurance.evidence_items i on i.id = r.current_evidence_id
     where r.engagement_id = v_eid and r.status = 'accepted';
    if v_n = 0 then
      perform assurance.state_error('ASSURANCE_EVIDENCE_OUTSTANDING');
    end if;
    update assurance.engagements set evidence_frozen_at = clock_timestamp(), evidence_cutoff_digest = v_digest
     where id = v_eid;
    v_details := jsonb_build_object('cutoff_digest', v_digest, 'evidence_count', v_n,
      'reason', assurance.text_field(p_payload, 'reason', 3, 1000));

  when 'record_exception' then
    if v_eng.status not in ('fieldwork','reporting') then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_role is null or v_role not in ('lead','auditor') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    if not exists (select 1 from assurance.engagement_controls
                    where id = assurance.uuid_field(p_payload, 'control_id') and engagement_id = v_eid) then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_CONTROL_NOT_FOUND';
    end if;
    if (p_payload->>'severity') is null or (p_payload->>'severity') not in ('low','medium','high','critical') then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'severity';
    end if;
    insert into assurance.exceptions(id, engagement_id, control_id, description, severity, recorded_by)
    values (assurance.uuid_field(p_payload, 'exception_id'), v_eid, (p_payload->>'control_id')::uuid,
      assurance.text_field(p_payload, 'description', 3, 4000), p_payload->>'severity', v_uid);
    v_agg_type := 'exception'; v_agg_id := (p_payload->>'exception_id')::uuid; v_to := 'candidate';
    v_details := jsonb_build_object('severity', p_payload->>'severity');

  when 'dismiss_exception', 'issue_finding' then
    if v_eng.status not in ('fieldwork','reporting') then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_role is null or v_role not in ('lead','auditor','reviewer') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_exc from assurance.exceptions
     where id = assurance.uuid_field(p_payload, 'exception_id') and engagement_id = v_eid for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_EXCEPTION_NOT_FOUND';
    end if;
    if v_exc.status <> 'candidate' then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_exc.recorded_by = v_uid then
      perform assurance.deny('ASSURANCE_INDEPENDENT_REVIEW_REQUIRED');
    end if;
    v_from := 'candidate';
    if v_action = 'dismiss_exception' then
      update assurance.exceptions set status = 'dismissed' where id = v_exc.id;
      v_agg_type := 'exception'; v_agg_id := v_exc.id; v_to := 'dismissed';
      v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));
    else
      v_uuid := assurance.uuid_field(p_payload, 'owner_id');
      if not assurance.active_member(p_tenant_id, v_uuid) then
        raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
      end if;
      if exists (select 1 from assurance.engagement_team where engagement_id = v_eid and user_id = v_uuid) then
        perform assurance.deny('ASSURANCE_INDEPENDENCE_REQUIRED');
      end if;
      if (p_payload->>'severity') is null or (p_payload->>'severity') not in ('low','medium','high','critical') then
        raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'severity';
      end if;
      update assurance.exceptions set status = 'promoted' where id = v_exc.id;
      insert into assurance.findings(id, engagement_id, exception_id, title, severity, owner_id, issued_by)
      values (assurance.uuid_field(p_payload, 'finding_id'), v_eid, v_exc.id,
        assurance.text_field(p_payload, 'title', 3, 160), p_payload->>'severity', v_uuid, v_uid);
      v_agg_type := 'finding'; v_agg_id := (p_payload->>'finding_id')::uuid; v_to := 'issued';
      v_details := jsonb_build_object('exception_id', v_exc.id, 'severity', p_payload->>'severity',
        'owner_id', v_uuid, 'exception_severity', v_exc.severity);
    end if;

  when 'respond', 'decide_risk', 'submit_remediation', 'retest', 'reopen_finding' then
    select * into v_fin from assurance.findings
     where id = assurance.uuid_field(p_payload, 'finding_id') and engagement_id = v_eid for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_FINDING_NOT_FOUND';
    end if;
    v_agg_type := 'finding'; v_agg_id := v_fin.id; v_from := v_fin.status;

    if v_action = 'respond' then
      if v_fin.owner_id <> v_uid then
        perform assurance.deny('ASSURANCE_FINDING_OWNER_REQUIRED');
      end if;
      if v_fin.status <> 'issued' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      v_date := assurance.date_field(p_payload, 'due_date');
      if v_date < current_date or coalesce(jsonb_typeof(p_payload->'accept_risk'), '') <> 'boolean' then
        raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID';
      end if;
      v_to := case when (p_payload->>'accept_risk')::boolean then 'risk_pending' else 'remediating' end;
      update assurance.findings set status = v_to, response = assurance.text_field(p_payload, 'response', 3, 4000),
        response_due = v_date where id = v_fin.id;
      v_details := jsonb_build_object('due_date', v_date, 'accept_risk', (p_payload->>'accept_risk')::boolean);

    elsif v_action = 'decide_risk' then
      if v_fin.status <> 'risk_pending' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      if v_fin.owner_id = v_uid or v_fin.issued_by = v_uid then
        perform assurance.deny('ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED');
      end if;
      v_text := p_payload->>'decision';
      if v_text is null or v_text not in ('approve','reject') then
        raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'decision';
      end if;
      v_to := case v_text when 'approve' then 'risk_accepted' else 'remediating' end;
      update assurance.findings set status = v_to where id = v_fin.id;
      v_details := jsonb_build_object('decision', v_text, 'reason', assurance.text_field(p_payload, 'reason', 3, 1000));

    elsif v_action = 'submit_remediation' then
      if v_fin.owner_id <> v_uid then
        perform assurance.deny('ASSURANCE_FINDING_OWNER_REQUIRED');
      end if;
      if v_fin.status <> 'remediating' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      update assurance.findings set status = 'retest_pending', remediation_submitted_by = v_uid,
        remediation_sha256 = assurance.digest_field(p_payload, 'evidence_sha256') where id = v_fin.id;
      v_to := 'retest_pending';
      v_details := jsonb_build_object('evidence_sha256', p_payload->>'evidence_sha256',
        'note', assurance.text_field(p_payload, 'note', 3, 2000));

    elsif v_action = 'retest' then
      if v_fin.status <> 'retest_pending' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      if v_role is null or v_role not in ('lead','auditor','reviewer') then
        perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
      end if;
      if v_uid in (v_fin.owner_id, v_fin.remediation_submitted_by)
         or exists (select 1 from assurance.engagement_controls c join assurance.exceptions x on x.control_id = c.id
                     where x.id = v_fin.exception_id and c.owner_id = v_uid) then
        perform assurance.deny('ASSURANCE_INDEPENDENT_RETEST_REQUIRED');
      end if;
      v_text := p_payload->>'result';
      if v_text is null or v_text not in ('pass','fail') then
        raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'result';
      end if;
      insert into assurance.retests(id, finding_id, result, evidence_sha256, note, performed_by)
      values (assurance.uuid_field(p_payload, 'retest_id'), v_fin.id, v_text,
        assurance.digest_field(p_payload, 'evidence_sha256'), assurance.text_field(p_payload, 'note', 3, 2000), v_uid);
      v_to := case v_text when 'pass' then 'closed' else 'remediating' end;
      update assurance.findings set status = v_to where id = v_fin.id;
      v_details := jsonb_build_object('retest_id', (p_payload->>'retest_id')::uuid, 'result', v_text,
        'evidence_sha256', p_payload->>'evidence_sha256');

    else -- reopen_finding
      if v_fin.status not in ('closed','risk_accepted') then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      if v_fin.owner_id = v_uid then
        perform assurance.deny('ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED');
      end if;
      update assurance.findings set status = 'remediating' where id = v_fin.id;
      v_to := 'remediating';
      v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));
    end if;

  when 'issue_report' then
    if v_eng.status <> 'reporting' or v_eng.evidence_frozen_at is null then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_uid = v_eng.lead_auditor_id then
      perform assurance.deny('ASSURANCE_INDEPENDENT_ISSUER_REQUIRED');
    end if;
    if exists (select 1 from assurance.exceptions where engagement_id = v_eid and status = 'candidate') then
      perform assurance.state_error('ASSURANCE_EXCEPTIONS_UNRESOLVED');
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'title', f.title, 'severity', f.severity,
             'status', f.status, 'owner_id', f.owner_id) order by f.id), '[]'::jsonb)
      into v_snapshot from assurance.findings f where f.engagement_id = v_eid;
    select coalesce(max(report_version), 0) + 1 into v_n from assurance.report_versions where engagement_id = v_eid;
    v_text := assurance.text_field(p_payload, 'summary', 3, 4000);
    v_digest := encode(extensions.digest(convert_to(jsonb_build_object(
      'engagement_id', v_eid, 'report_version', v_n, 'cutoff', v_eng.evidence_cutoff_digest,
      'period', jsonb_build_array(v_eng.period_start, v_eng.period_end),
      'findings', v_snapshot, 'summary', v_text)::text, 'UTF8'), 'sha256'), 'hex');
    insert into assurance.report_versions(id, engagement_id, report_version, summary, evidence_cutoff_digest,
      findings_snapshot, digest, issued_by)
    values (assurance.uuid_field(p_payload, 'report_id'), v_eid, v_n, v_text, v_eng.evidence_cutoff_digest,
      v_snapshot, v_digest, v_uid);
    update assurance.engagements set status = 'issued' where id = v_eid;
    v_from := 'reporting'; v_to := 'issued';
    v_details := jsonb_build_object('report_id', (p_payload->>'report_id')::uuid,
      'report_version', v_n, 'digest', v_digest);

  when 'reopen_report' then
    if v_eng.status <> 'issued' then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    update assurance.engagements set status = 'reporting' where id = v_eid;
    v_from := 'issued'; v_to := 'reporting';
    v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));

  when 'place_hold' then
    insert into assurance.retention_holds(id, engagement_id, reason, placed_by)
    values (assurance.uuid_field(p_payload, 'hold_id'), v_eid, assurance.text_field(p_payload, 'reason', 3, 1000), v_uid);
    v_agg_type := 'retention_hold'; v_agg_id := (p_payload->>'hold_id')::uuid; v_to := 'held';

  when 'release_hold' then
    select * into v_hold from assurance.retention_holds
     where id = assurance.uuid_field(p_payload, 'hold_id') and engagement_id = v_eid for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_HOLD_NOT_FOUND';
    end if;
    if v_hold.released_at is not null then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_hold.placed_by = v_uid then
      perform assurance.deny('ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED');
    end if;
    update assurance.retention_holds set released_by = v_uid, released_at = clock_timestamp(),
      release_reason = assurance.text_field(p_payload, 'reason', 3, 1000) where id = v_hold.id;
    v_agg_type := 'retention_hold'; v_agg_id := v_hold.id; v_from := 'held'; v_to := 'released';
  end case;

  if v_action <> 'create_engagement' then
    update assurance.engagements set version = version + 1, updated_at = clock_timestamp()
     where id = v_eid returning * into v_eng;
  end if;

  insert into assurance.events(tenant_id, engagement_id, engagement_version, action, aggregate_type,
    aggregate_id, from_status, to_status, actor_id, details)
  values (p_tenant_id, v_eid, v_eng.version, v_action, v_agg_type, v_agg_id, v_from, v_to, v_uid, v_details);

  v_response := jsonb_build_object('engagement_id', v_eid, 'version', v_eng.version,
    'status', v_eng.status, 'action', v_action, 'aggregate_type', v_agg_type,
    'aggregate_id', v_agg_id, 'to_status', v_to);
  insert into assurance.command_receipts(actor_id, idempotency_key, tenant_id, request_hash, response)
  values (v_uid, p_idempotency_key, p_tenant_id, v_hash, v_response);
  return v_response;
end $$;

create or replace function assurance.prepare_command(
  p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_idempotency_key uuid,
  p_payload jsonb, p_expected_version bigint, p_permission text, p_fields text[], p_mfa boolean,
  out o_hash text, out o_replay jsonb, out o_engagement assurance.engagements, out o_role text
) language plpgsql set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_receipt assurance.command_receipts%rowtype;
  v_eid uuid;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  if exists (select 1 from jsonb_object_keys(p_payload) k where k <> all (p_fields)) then
    raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD';
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, p_permission, p_legal_entity_id, p_branch_id);
  o_hash := encode(extensions.digest(convert_to(jsonb_build_array(
    p_tenant_id, p_legal_entity_id, p_branch_id, p_expected_version, p_payload)::text, 'UTF8'),
    'sha256'), 'hex');
  select * into v_receipt from assurance.command_receipts
   where actor_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    if v_receipt.request_hash <> o_hash or v_receipt.tenant_id <> p_tenant_id then
      raise exception using errcode = '22023', message = 'IDEMPOTENCY_MISMATCH';
    end if;
    o_replay := v_receipt.response;
    return;
  end if;
  if p_mfa and not assurance.recent_mfa() then
    perform assurance.deny('ASSURANCE_RECENT_MFA_REQUIRED');
  end if;
  v_eid := assurance.uuid_field(p_payload, 'engagement_id');
  select * into o_engagement from assurance.engagements
   where id = v_eid and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
     and branch_id is not distinct from p_branch_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_ENGAGEMENT_NOT_FOUND';
  end if;
  if p_expected_version is null or o_engagement.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
  end if;
  if exists (select 1 from assurance.engagement_team
              where engagement_id = v_eid and user_id = v_uid and role = 'external') then
    perform assurance.deny('ASSURANCE_EXTERNAL_READ_ONLY');
  end if;
  if o_engagement.status in ('archived','cancelled') then
    perform assurance.state_error('ASSURANCE_ENGAGEMENT_CLOSED');
  end if;
  o_role := assurance.team_role(v_eid, v_uid);
end $$;

create or replace function api.assurance_plan_command(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_idempotency_key uuid,
  p_payload jsonb,
  p_expected_version bigint
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_action text;
  v_perm text;
  v_fields text[];
  v_hash text;
  v_receipt assurance.command_receipts%rowtype;
  v_item assurance.universe_items%rowtype;
  v_plan assurance.plans%rowtype;
  v_pi assurance.plan_items%rowtype;
  v_tpl assurance.templates%rowtype;
  v_asm assurance.risk_assessments%rowtype;
  v_c record;
  v_agg_type text;
  v_agg_id uuid;
  v_version bigint := 1;
  v_status text;
  v_from text;
  v_to text;
  v_details jsonb := '{}'::jsonb;
  v_uuid uuid;
  v_text text;
  v_l integer;
  v_i integer;
  v_n integer;
  v_k integer;
  v_start date;
  v_end date;
  v_digest text;
  v_eid uuid;
  v_response jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or coalesce(jsonb_typeof(p_payload->'action'), '') <> 'string' then
    raise exception using errcode = '22023', message = 'ASSURANCE_ACTION_UNKNOWN';
  end if;
  v_action := p_payload->>'action';
  v_perm := assurance.plan_action_permission(v_action);
  v_fields := assurance.plan_action_fields(v_action);
  if v_perm is null or v_fields is null then
    raise exception using errcode = '22023', message = 'ASSURANCE_ACTION_UNKNOWN';
  end if;
  if exists (select 1 from jsonb_object_keys(p_payload) k where k <> all (v_fields)) then
    raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD';
  end if;

  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, v_perm, p_legal_entity_id, p_branch_id);

  v_hash := encode(extensions.digest(convert_to(jsonb_build_array(
    p_tenant_id, p_legal_entity_id, p_branch_id, p_expected_version, p_payload)::text, 'UTF8'),
    'sha256'), 'hex');
  select * into v_receipt from assurance.command_receipts
   where actor_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    if v_receipt.request_hash <> v_hash or v_receipt.tenant_id <> p_tenant_id then
      raise exception using errcode = '22023', message = 'IDEMPOTENCY_MISMATCH';
    end if;
    return v_receipt.response;
  end if;

  if v_action = 'decide_plan' and not assurance.recent_mfa() then
    perform assurance.deny('ASSURANCE_RECENT_MFA_REQUIRED');
  end if;
  if v_action in ('register_item','create_template','create_plan') and p_expected_version is distinct from 0 then
    raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
  end if;

  case v_action
  when 'register_item' then
    v_agg_type := 'universe_item';
    v_agg_id := assurance.uuid_field(p_payload, 'item_id');
    if exists (select 1 from assurance.universe_items where id = v_agg_id) then
      raise exception using errcode = '23505', message = 'ASSURANCE_ITEM_EXISTS';
    end if;
    if coalesce(jsonb_typeof(p_payload->'code'), '') <> 'string'
       or (p_payload->>'code') !~ '^[A-Z0-9][A-Z0-9._-]{1,39}$' then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'code';
    end if;
    if coalesce(p_payload->>'category', '') not in ('process','entity','system','compliance','project') then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'category';
    end if;
    v_uuid := assurance.uuid_field(p_payload, 'owner_id');
    if not assurance.active_member(p_tenant_id, v_uuid) then
      raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
    end if;
    insert into assurance.universe_items(id, tenant_id, legal_entity_id, branch_id, code, name, category,
      owner_id, created_by)
    values (v_agg_id, p_tenant_id, p_legal_entity_id, p_branch_id, p_payload->>'code',
      assurance.text_field(p_payload, 'name', 3, 160), p_payload->>'category', v_uuid, v_uid);
    v_status := 'active'; v_to := 'active';
    v_details := jsonb_build_object('code', p_payload->>'code', 'category', p_payload->>'category',
      'owner_id', v_uuid);

  when 'assess_risk', 'retire_item' then
    v_agg_type := 'universe_item';
    select * into v_item from assurance.universe_items
     where id = assurance.uuid_field(p_payload, 'item_id') and tenant_id = p_tenant_id
       and legal_entity_id = p_legal_entity_id and branch_id is not distinct from p_branch_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_ITEM_NOT_FOUND';
    end if;
    if p_expected_version is null or v_item.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
    end if;
    v_agg_id := v_item.id;
    if v_item.status <> 'active' then
      perform assurance.state_error('ASSURANCE_ITEM_RETIRED');
    end if;
    v_from := 'active';
    if v_action = 'assess_risk' then
      if v_item.owner_id = v_uid then
        perform assurance.deny('ASSURANCE_INDEPENDENCE_REQUIRED');
      end if;
      v_l := assurance.int_field(p_payload, 'likelihood', 1, 5);
      v_i := assurance.int_field(p_payload, 'impact', 1, 5);
      v_text := assurance.risk_rating(v_l * v_i);
      v_uuid := assurance.uuid_field(p_payload, 'assessment_id');
      insert into assurance.risk_assessments(id, universe_item_id, likelihood, impact, rating, rationale, assessed_by)
      values (v_uuid, v_item.id, v_l, v_i, v_text, assurance.text_field(p_payload, 'rationale', 3, 2000), v_uid);
      v_details := jsonb_build_object('assessment_id', v_uuid, 'likelihood', v_l, 'impact', v_i,
        'score', v_l * v_i, 'rating', v_text,
        'previous_rating', (select rating from assurance.risk_assessments where id = v_item.current_assessment_id));
      update assurance.universe_items set current_assessment_id = v_uuid where id = v_item.id;
      v_to := 'active';
    else
      if exists (select 1 from assurance.plan_items pi join assurance.plans p on p.id = pi.plan_id
                  where pi.universe_item_id = v_item.id and pi.status = 'active'
                    and p.status in ('draft','submitted')) then
        perform assurance.state_error('ASSURANCE_ITEM_IN_OPEN_PLAN');
      end if;
      v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));
      update assurance.universe_items set status = 'retired' where id = v_item.id;
      v_to := 'retired';
    end if;
    update assurance.universe_items set version = version + 1, updated_at = clock_timestamp()
     where id = v_item.id returning version, status into v_version, v_status;

  when 'create_template' then
    v_agg_type := 'template';
    v_agg_id := assurance.uuid_field(p_payload, 'template_id');
    if exists (select 1 from assurance.templates where id = v_agg_id) then
      raise exception using errcode = '23505', message = 'ASSURANCE_TEMPLATE_EXISTS';
    end if;
    if coalesce(jsonb_typeof(p_payload->'code'), '') <> 'string'
       or (p_payload->>'code') !~ '^[A-Z0-9][A-Z0-9._-]{1,39}$' then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'code';
    end if;
    v_text := assurance.text_field(p_payload, 'name', 3, 160);
    if not assurance.template_valid(p_payload->'controls', p_payload->'requests') then
      raise exception using errcode = '22023', message = 'ASSURANCE_TEMPLATE_INVALID';
    end if;
    select coalesce(max(version), 0) + 1 into v_n from assurance.templates
     where tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
       and branch_id is not distinct from p_branch_id and code = p_payload->>'code';
    v_digest := encode(extensions.digest(convert_to(jsonb_build_object('code', p_payload->>'code',
      'version', v_n, 'name', v_text, 'controls', p_payload->'controls',
      'requests', p_payload->'requests')::text, 'UTF8'), 'sha256'), 'hex');
    insert into assurance.templates(id, tenant_id, legal_entity_id, branch_id, code, version, name,
      controls, requests, digest, created_by)
    values (v_agg_id, p_tenant_id, p_legal_entity_id, p_branch_id, p_payload->>'code', v_n, v_text,
      p_payload->'controls', p_payload->'requests', v_digest, v_uid);
    v_status := 'active'; v_to := 'active';
    v_details := jsonb_build_object('code', p_payload->>'code', 'template_version', v_n, 'digest', v_digest,
      'controls', jsonb_array_length(p_payload->'controls'), 'requests', jsonb_array_length(p_payload->'requests'));

  when 'create_plan' then
    v_agg_type := 'plan';
    v_agg_id := assurance.uuid_field(p_payload, 'plan_id');
    if exists (select 1 from assurance.plans where id = v_agg_id) then
      raise exception using errcode = '23505', message = 'ASSURANCE_PLAN_EXISTS';
    end if;
    v_start := assurance.date_field(p_payload, 'period_start');
    v_end := assurance.date_field(p_payload, 'period_end');
    if v_end < v_start then
      raise exception using errcode = '22023', message = 'ASSURANCE_PERIOD_INVALID';
    end if;
    insert into assurance.plans(id, tenant_id, legal_entity_id, branch_id, name, period_start, period_end, created_by)
    values (v_agg_id, p_tenant_id, p_legal_entity_id, p_branch_id,
      assurance.text_field(p_payload, 'name', 3, 160), v_start, v_end, v_uid);
    v_status := 'draft'; v_to := 'draft';
    v_details := jsonb_build_object('period_start', v_start, 'period_end', v_end);

  else
    v_agg_type := 'plan';
    select * into v_plan from assurance.plans
     where id = assurance.uuid_field(p_payload, 'plan_id') and tenant_id = p_tenant_id
       and legal_entity_id = p_legal_entity_id and branch_id is not distinct from p_branch_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_PLAN_NOT_FOUND';
    end if;
    if p_expected_version is null or v_plan.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
    end if;
    v_agg_id := v_plan.id;
    v_from := v_plan.status;
    v_to := v_plan.status;

    case v_action
    when 'add_plan_item' then
      if v_plan.status <> 'draft' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      select * into v_item from assurance.universe_items
       where id = assurance.uuid_field(p_payload, 'item_id') and tenant_id = p_tenant_id
         and legal_entity_id = p_legal_entity_id and branch_id is not distinct from p_branch_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'ASSURANCE_ITEM_NOT_FOUND';
      end if;
      if v_item.status <> 'active' then
        perform assurance.state_error('ASSURANCE_ITEM_RETIRED');
      end if;
      if v_item.current_assessment_id is null then
        perform assurance.state_error('ASSURANCE_RISK_ASSESSMENT_REQUIRED');
      end if;
      v_n := assurance.frequency_count(p_payload->>'frequency');
      if v_n is null then
        raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'frequency';
      end if;
      if (v_plan.period_end - v_plan.period_start + 1) < v_n then
        raise exception using errcode = '22023', message = 'ASSURANCE_PERIOD_INVALID';
      end if;
      if coalesce(jsonb_typeof(p_payload->'template_id'), 'null') <> 'null' then
        select * into v_tpl from assurance.templates
         where id = assurance.uuid_field(p_payload, 'template_id') and tenant_id = p_tenant_id
           and legal_entity_id = p_legal_entity_id and branch_id is not distinct from p_branch_id;
        if not found then
          raise exception using errcode = 'P0002', message = 'ASSURANCE_TEMPLATE_NOT_FOUND';
        end if;
      end if;
      v_uuid := assurance.uuid_field(p_payload, 'lead_auditor_id');
      if not assurance.active_member(p_tenant_id, v_uuid) then
        raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
      end if;
      if v_uuid = v_item.owner_id then
        perform assurance.deny('ASSURANCE_INDEPENDENCE_REQUIRED');
      end if;
      if exists (select 1 from assurance.plan_items
                  where plan_id = v_plan.id and universe_item_id = v_item.id and status = 'active') then
        raise exception using errcode = '23505', message = 'ASSURANCE_PLAN_ITEM_EXISTS';
      end if;
      select * into v_asm from assurance.risk_assessments where id = v_item.current_assessment_id;
      insert into assurance.plan_items(id, plan_id, universe_item_id, assessment_id, rating, frequency,
        template_id, lead_auditor_id, scope_summary, added_by)
      values (assurance.uuid_field(p_payload, 'plan_item_id'), v_plan.id, v_item.id, v_asm.id, v_asm.rating,
        p_payload->>'frequency', v_tpl.id, v_uuid, assurance.text_field(p_payload, 'scope_summary', 3, 2000), v_uid);
      v_details := jsonb_build_object('plan_item_id', (p_payload->>'plan_item_id')::uuid, 'item_id', v_item.id,
        'rating', v_asm.rating, 'frequency', p_payload->>'frequency', 'template_id', v_tpl.id,
        'lead_auditor_id', v_uuid);

    when 'remove_plan_item' then
      if v_plan.status <> 'draft' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      select * into v_pi from assurance.plan_items
       where id = assurance.uuid_field(p_payload, 'plan_item_id') and plan_id = v_plan.id and status = 'active'
       for update;
      if not found then
        raise exception using errcode = 'P0002', message = 'ASSURANCE_PLAN_ITEM_NOT_FOUND';
      end if;
      v_details := jsonb_build_object('plan_item_id', v_pi.id,
        'reason', assurance.text_field(p_payload, 'reason', 3, 1000));
      update assurance.plan_items set status = 'removed' where id = v_pi.id;

    when 'submit_plan' then
      if v_plan.status <> 'draft' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      select count(*) into v_n from assurance.plan_items where plan_id = v_plan.id and status = 'active';
      if v_n = 0 then
        perform assurance.state_error('ASSURANCE_PLAN_EMPTY');
      end if;
      update assurance.plans set status = 'submitted', submitted_by = v_uid, submitted_at = clock_timestamp()
       where id = v_plan.id;
      v_to := 'submitted';
      v_details := jsonb_build_object('items', v_n,
        'uncovered_high_risk', jsonb_array_length(assurance.plan_uncovered(v_plan.id)));

    when 'decide_plan' then
      if v_plan.status <> 'submitted' then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      if v_uid = v_plan.created_by or v_uid = v_plan.submitted_by then
        perform assurance.deny('ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED');
      end if;
      v_text := p_payload->>'decision';
      v_details := jsonb_build_object('decision', v_text,
        'reason', assurance.text_field(p_payload, 'reason', 3, 1000));
      if v_text = 'approve' then
        v_digest := assurance.plan_digest(v_plan.id);
        update assurance.plans set status = 'approved', approved_by = v_uid, approved_at = clock_timestamp(),
          approved_digest = v_digest where id = v_plan.id;
        v_to := 'approved';
        v_details := v_details || jsonb_build_object('digest', v_digest);
      elsif v_text = 'return' then
        update assurance.plans set status = 'draft', submitted_by = null, submitted_at = null where id = v_plan.id;
        v_to := 'draft';
      else
        raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'decision';
      end if;

    when 'cancel_plan' then
      if v_plan.status not in ('draft','submitted') then
        perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
      end if;
      v_details := jsonb_build_object('reason', assurance.text_field(p_payload, 'reason', 3, 1000));
      update assurance.plans set status = 'cancelled' where id = v_plan.id;
      v_to := 'cancelled';

    when 'instantiate_engagement' then
      if v_plan.status <> 'approved' then
        perform assurance.state_error('ASSURANCE_PLAN_NOT_APPROVED');
      end if;
      select * into v_pi from assurance.plan_items
       where id = assurance.uuid_field(p_payload, 'plan_item_id') and plan_id = v_plan.id and status = 'active';
      if not found then
        raise exception using errcode = 'P0002', message = 'ASSURANCE_PLAN_ITEM_NOT_FOUND';
      end if;
      v_n := assurance.frequency_count(v_pi.frequency);
      v_k := assurance.int_field(p_payload, 'occurrence', 1, v_n);
      if exists (select 1 from assurance.plan_occurrences where plan_item_id = v_pi.id and occurrence = v_k) then
        raise exception using errcode = '23505', message = 'ASSURANCE_OCCURRENCE_EXISTS';
      end if;
      v_eid := assurance.uuid_field(p_payload, 'engagement_id');
      if exists (select 1 from assurance.engagements where id = v_eid) then
        raise exception using errcode = '23505', message = 'ASSURANCE_ENGAGEMENT_EXISTS';
      end if;
      select * into v_item from assurance.universe_items where id = v_pi.universe_item_id;
      if v_item.status <> 'active' then
        perform assurance.state_error('ASSURANCE_ITEM_RETIRED');
      end if;
      if not assurance.active_member(p_tenant_id, v_item.owner_id)
         or not assurance.active_member(p_tenant_id, v_pi.lead_auditor_id) then
        raise exception using errcode = '22023', message = 'ASSURANCE_MEMBER_REQUIRED';
      end if;
      select o_start, o_end into v_start, v_end
        from assurance.occurrence_period(v_plan.period_start, v_plan.period_end, v_n, v_k);
      insert into assurance.engagements(id, tenant_id, legal_entity_id, branch_id, name, period_start, period_end,
        scope_summary, lead_auditor_id, created_by)
      values (v_eid, p_tenant_id, p_legal_entity_id, p_branch_id, left(v_item.name || ' ' || v_k || '/' || v_n, 160),
        v_start, v_end, v_pi.scope_summary, v_pi.lead_auditor_id, v_uid);
      insert into assurance.engagement_team(engagement_id, user_id, role, added_by)
      values (v_eid, v_pi.lead_auditor_id, 'lead', v_uid);
      if v_pi.template_id is not null then
        select * into v_tpl from assurance.templates where id = v_pi.template_id;
        for v_c in select * from jsonb_to_recordset(v_tpl.controls) as x(control_code text, title text, risk text) loop
          insert into assurance.engagement_controls(id, engagement_id, control_code, title, owner_id, risk, mapped_by)
          values (gen_random_uuid(), v_eid, v_c.control_code, v_c.title, v_item.owner_id, v_c.risk, v_uid);
        end loop;
        insert into assurance.evidence_requests(id, engagement_id, control_id, owner_id, description, due_date, requested_by)
        select gen_random_uuid(), v_eid, c.id, v_item.owner_id, r.description, current_date + r.due_offset_days, v_uid
          from jsonb_to_recordset(v_tpl.requests) as r(control_code text, description text, due_offset_days integer)
          join assurance.engagement_controls c on c.engagement_id = v_eid and c.control_code = r.control_code;
      end if;
      insert into assurance.events(tenant_id, engagement_id, engagement_version, action, aggregate_type,
        aggregate_id, from_status, to_status, actor_id, details)
      values (p_tenant_id, v_eid, 1, 'create_engagement', 'engagement', v_eid, null, 'planning', v_uid,
        jsonb_build_object('plan_id', v_plan.id, 'plan_item_id', v_pi.id, 'occurrence', v_k,
          'template_id', v_tpl.id, 'template_version', v_tpl.version,
          'controls', (select count(*) from assurance.engagement_controls where engagement_id = v_eid),
          'requests', (select count(*) from assurance.evidence_requests where engagement_id = v_eid)));
      insert into assurance.plan_occurrences(plan_item_id, occurrence, period_start, period_end, engagement_id, created_by)
      values (v_pi.id, v_k, v_start, v_end, v_eid, v_uid);
      v_details := jsonb_build_object('plan_item_id', v_pi.id, 'occurrence', v_k, 'engagement_id', v_eid,
        'period_start', v_start, 'period_end', v_end);
    end case;

    update assurance.plans set version = version + 1, updated_at = clock_timestamp()
     where id = v_plan.id returning version, status into v_version, v_status;
  end case;

  insert into assurance.plan_events(tenant_id, aggregate_type, aggregate_id, aggregate_version, action,
    from_status, to_status, actor_id, details)
  values (p_tenant_id, v_agg_type, v_agg_id, v_version, v_action, v_from, v_to, v_uid, v_details);

  v_response := jsonb_build_object('aggregate_type', v_agg_type, 'aggregate_id', v_agg_id,
    'version', v_version, 'status', v_status, 'action', v_action, 'to_status', v_to)
    || case when v_eid is null then '{}'::jsonb else jsonb_build_object('engagement_id', v_eid) end;
  insert into assurance.command_receipts(actor_id, idempotency_key, tenant_id, request_hash, response)
  values (v_uid, p_idempotency_key, p_tenant_id, v_hash, v_response);
  return v_response;
end $$;

revoke all on function assurance.prepare_command(uuid, uuid, uuid, uuid, jsonb, bigint, text, text[], boolean) from public, anon, authenticated, service_role;
