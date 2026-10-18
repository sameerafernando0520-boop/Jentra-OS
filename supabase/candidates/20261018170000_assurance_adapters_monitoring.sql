-- Corporate Audit & Assurance - candidate slice A4b (blueprint 68).
-- CANDIDATE ONLY. Requires A1, A2 and A4. Adds procurement (three-way match)
-- and workforce (attendance approval) period snapshots, and continuous
-- monitoring that turns snapshot rules into *candidate* exceptions only.
-- Monitoring never issues findings or closes controls; candidates follow the
-- existing independent dismiss/promote workflow.
--
-- Snapshots contain counts, amounts and record identifiers only: no supplier,
-- employee or personal identities.

alter table assurance.system_snapshots drop constraint system_snapshots_kind_check;
alter table assurance.system_snapshots add constraint system_snapshots_kind_check
  check (kind in ('it_control.access_review','procurement.three_way_match','workforce.attendance_approvals'));

create table assurance.monitoring_hits (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references assurance.engagements(id),
  evidence_id uuid not null references assurance.evidence_items(id),
  rule_code text not null check (rule_code ~ '^[A-Z0-9_]{3,64}$'),
  exception_id uuid not null unique references assurance.exceptions(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique (evidence_id, rule_code)
);
alter table assurance.monitoring_hits enable row level security;
alter table assurance.monitoring_hits force row level security;
revoke all on assurance.monitoring_hits from public, anon, authenticated, service_role;
create trigger monitoring_hits_immutable before update or delete on assurance.monitoring_hits
  for each row execute function assurance.forbid_mutation();

create or replace function assurance.source_kind(p_kind text,
  out o_module text, out o_query_version text, out o_classification text)
language sql immutable set search_path = '' as $$
  select v.m, v.q, v.c from (values
    ('finance.financial_statement','finance','fin.financial_reports.v1','confidential'),
    ('finance.close_review','finance','fin.close_control_reviews.v1','confidential'),
    ('finance.control_reconciliation','finance','fin.control_reports.v1','confidential'),
    ('finance.tax_summary','finance','fin.tax_reports.v1','confidential'),
    ('inventory.valuation','inventory','inv.valuation_reports.v1','confidential'),
    ('it_control.access_review','it_control','core.access_review.v1','restricted'),
    ('procurement.three_way_match','procurement','proc.supplier_bill_match.v1','confidential'),
    ('workforce.attendance_approvals','workforce','people.attendance_approvals.v1','restricted')
  ) v(k, m, q, c) where v.k = p_kind;
$$;

-- Snapshot kinds are generated (no authoritative report row exists) and are
-- stored in assurance.system_snapshots.
create function assurance.is_snapshot_kind(p_kind text) returns boolean
language sql immutable set search_path = '' as $$
  select p_kind in ('it_control.access_review','procurement.three_way_match','workforce.attendance_approvals');
$$;

create function assurance.snapshot_document(p_kind text, p_tenant_id uuid, p_legal_entity_id uuid,
  p_branch_id uuid, p_period_start date, p_period_end date)
returns jsonb language plpgsql set search_path = '' as $$
begin
  case p_kind
  when 'it_control.access_review' then
    return assurance.access_review_document(p_tenant_id, p_legal_entity_id, p_branch_id);

  when 'procurement.three_way_match' then
    perform core.wave3_require_scope(p_tenant_id, 'procurement.view', p_legal_entity_id, p_branch_id);
    perform core.wave3_require_scope(p_tenant_id, 'procurement.bills.view', p_legal_entity_id, p_branch_id);
    return (
      with bills as (
        select b.id, b.document_date, b.base_total, b.created_by
          from procurement.supplier_bills b
         where b.tenant_id = p_tenant_id and b.legal_entity_id = p_legal_entity_id
           and b.branch_id = p_branch_id and b.status = 'posted'
           and b.document_date between p_period_start and p_period_end),
      overrides as (
        select b.id as bill_id, b.document_date, b.base_total,
               bool_or(a.approved_by = b.created_by) as by_creator, max(a.created_at) as approved_at
          from bills b join procurement.supplier_bill_match_approvals a
            on a.tenant_id = p_tenant_id and a.bill_id = b.id
         group by b.id, b.document_date, b.base_total)
      select jsonb_build_object(
        'kind', p_kind, 'legal_entity_id', p_legal_entity_id, 'branch_id', p_branch_id,
        'period_start', p_period_start, 'period_end', p_period_end,
        'posted_bills', (select count(*) from bills),
        'posted_base_total', (select coalesce(sum(base_total), 0)::text from bills),
        'bills_with_match_override', (select count(*) from overrides),
        'overrides_by_bill_creator', (select count(*) from overrides where by_creator),
        'overrides', coalesce((select jsonb_agg(jsonb_build_object('bill_id', o.bill_id,
            'document_date', o.document_date, 'base_total', o.base_total::text,
            'approved_by_bill_creator', o.by_creator, 'approved_at', o.approved_at) order by o.bill_id)
          from overrides o), '[]'::jsonb)));

  when 'workforce.attendance_approvals' then
    perform people.require_access(p_tenant_id, p_legal_entity_id, p_branch_id, 'people.attendance.view');
    return (
      with entries as (
        select a.status, a.submitted_by, a.decided_by, a.created_by
          from people.attendance_entries a
         where a.tenant_id = p_tenant_id and a.legal_entity_id = p_legal_entity_id
           and a.branch_id = p_branch_id
           and a.created_at >= p_period_start::timestamptz
           and a.created_at < (p_period_end + 1)::timestamptz)
      select jsonb_build_object(
        'kind', p_kind, 'legal_entity_id', p_legal_entity_id, 'branch_id', p_branch_id,
        'period_start', p_period_start, 'period_end', p_period_end,
        'entries', (select count(*) from entries),
        'by_status', coalesce((select jsonb_object_agg(status, n) from
            (select status, count(*) n from entries group by status) s), '{}'::jsonb),
        'decided', (select count(*) from entries where decided_by is not null),
        'self_decided', (select count(*) from entries where decided_by is not null
                           and (decided_by = submitted_by or decided_by = created_by)),
        'awaiting_decision', (select count(*) from entries where status = 'submitted')));
  else
    raise exception using errcode = '22023', message = 'ASSURANCE_SOURCE_KIND_INVALID';
  end case;
end $$;

-- Deterministic monitoring rules over one snapshot. Returns zero or more
-- (rule_code, severity, description) rows; descriptions hold no identities.
create function assurance.monitoring_rules(p_kind text, p_content jsonb)
returns table (rule_code text, severity text, description text)
language sql immutable set search_path = '' as $$
  select 'ACCESS_PRIVILEGED_NO_MFA', 'high',
         format('%s active role(s) grant privileged capabilities without requiring MFA: %s',
           count(*), string_agg(r->>'code', ', ' order by r->>'code'))
    from jsonb_array_elements(case when p_kind = 'it_control.access_review' then p_content->'roles' else '[]'::jsonb end) r
   where not (r->>'requires_mfa')::boolean and jsonb_array_length(r->'privileged_permissions') > 0
     and (r->>'active_assignments')::integer > 0
  having count(*) > 0
  union all
  select 'P2P_MATCH_OVERRIDE', 'medium',
         format('%s posted supplier bill(s) in the period required a three-way-match override',
           (p_content->>'bills_with_match_override')::integer)
   where p_kind = 'procurement.three_way_match' and (p_content->>'bills_with_match_override')::integer > 0
  union all
  select 'P2P_OVERRIDE_BY_CREATOR', 'high',
         format('%s match override(s) were approved by the user who created the bill',
           (p_content->>'overrides_by_bill_creator')::integer)
   where p_kind = 'procurement.three_way_match' and (p_content->>'overrides_by_bill_creator')::integer > 0
  union all
  select 'HR_ATTENDANCE_SELF_APPROVAL', 'high',
         format('%s attendance decision(s) were made by the submitter or creator',
           (p_content->>'self_decided')::integer)
   where p_kind = 'workforce.attendance_approvals' and (p_content->>'self_decided')::integer > 0;
$$;

create or replace function assurance.evidence_action_permission(p_action text)
returns text language sql immutable set search_path = '' as $$
  select case p_action
    when 'collect_system_evidence' then 'assurance.evidence.request'
    when 'export_pack' then 'assurance.report.export'
    when 'run_monitoring' then 'assurance.test.perform'
  end;
$$;

create or replace function assurance.evidence_action_fields(p_action text)
returns text[] language sql immutable set search_path = '' as $$
  select array['action','engagement_id'] || case p_action
    when 'collect_system_evidence' then array['request_id','evidence_id','source_kind','source_id']
    when 'export_pack' then array['export_id','report_id']
    when 'run_monitoring' then array['evidence_id','control_id']
    else null end;
$$;

-- Replaces the A4 definition: snapshot kinds generalised beyond the access
-- review, plus run_monitoring. Everything else is unchanged.
create or replace function api.assurance_evidence_command(
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
  v_prep record;
  v_eng assurance.engagements%rowtype;
  v_role text;
  v_req assurance.evidence_requests%rowtype;
  v_item assurance.evidence_items%rowtype;
  v_snap assurance.system_snapshots%rowtype;
  v_ctl assurance.engagement_controls%rowtype;
  v_rule record;
  v_hits jsonb := '[]'::jsonb;
  v_exc uuid;
  v_module text;
  v_query_version text;
  v_classification text;
  v_as_of_ts timestamptz;
  v_doc jsonb;
  v_as_of date;
  v_text text;
  v_sha text;
  v_bytes bigint;
  v_uuid uuid;
  v_source uuid;
  v_ref text;
  v_report assurance.report_versions%rowtype;
  v_manifest jsonb;
  v_agg_type text;
  v_agg_id uuid;
  v_from text;
  v_to text;
  v_details jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or coalesce(jsonb_typeof(p_payload->'action'), '') <> 'string' then
    raise exception using errcode = '22023', message = 'ASSURANCE_ACTION_UNKNOWN';
  end if;
  v_action := p_payload->>'action';
  v_perm := assurance.evidence_action_permission(v_action);
  v_fields := assurance.evidence_action_fields(v_action);
  if v_perm is null or v_fields is null then
    raise exception using errcode = '22023', message = 'ASSURANCE_ACTION_UNKNOWN';
  end if;

  select * into v_prep from assurance.prepare_command(p_tenant_id, p_legal_entity_id, p_branch_id,
    p_idempotency_key, p_payload, p_expected_version, v_perm, v_fields, v_action = 'export_pack');
  if v_prep.o_replay is not null then
    return v_prep.o_replay;
  end if;
  v_eng := v_prep.o_engagement;
  v_role := v_prep.o_role;

  case v_action
  when 'collect_system_evidence' then
    if v_eng.status <> 'fieldwork' or v_eng.evidence_frozen_at is not null then
      perform assurance.state_error('ASSURANCE_EVIDENCE_FROZEN');
    end if;
    if v_role is null or v_role not in ('lead','auditor') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_req from assurance.evidence_requests
     where id = assurance.uuid_field(p_payload, 'request_id') and engagement_id = v_eng.id for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_REQUEST_NOT_FOUND';
    end if;
    if v_req.status <> 'open' then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    v_text := p_payload->>'source_kind';
    select o_module, o_query_version, o_classification into v_module, v_query_version, v_classification
      from assurance.source_kind(v_text);
    if v_text is null or v_module is null then
      raise exception using errcode = '22023', message = 'ASSURANCE_SOURCE_KIND_INVALID';
    end if;
    v_uuid := assurance.uuid_field(p_payload, 'evidence_id');
    if assurance.is_snapshot_kind(v_text) then
      if p_payload->'source_id' is not null and p_payload->'source_id' <> 'null'::jsonb then
        raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD', detail = 'source_id';
      end if;
      v_doc := assurance.snapshot_document(v_text, p_tenant_id, p_legal_entity_id, p_branch_id,
        v_eng.period_start, v_eng.period_end);
      v_as_of_ts := clock_timestamp();
      v_ref := format('assurance.system_snapshots/%s', v_uuid);
    else
      v_source := assurance.uuid_field(p_payload, 'source_id');
      select * into v_doc, v_as_of from assurance.source_document(v_text, p_tenant_id, p_legal_entity_id,
        p_branch_id, v_source);
      if v_as_of not between v_eng.period_start and v_eng.period_end then
        raise exception using errcode = '22023', message = 'ASSURANCE_SOURCE_OUTSIDE_PERIOD';
      end if;
      v_ref := format('%s/%s', v_text, v_source);
      v_as_of_ts := ((v_as_of + 1)::timestamp at time zone 'UTC') - interval '1 microsecond';
    end if;
    v_bytes := octet_length(v_doc::text);
    if v_bytes > 104857600 then
      raise exception using errcode = '22023', message = 'ASSURANCE_EVIDENCE_TOO_LARGE';
    end if;
    v_sha := encode(extensions.digest(convert_to(v_doc::text, 'UTF8'), 'sha256'), 'hex');
    if assurance.is_snapshot_kind(v_text) then
      insert into assurance.system_snapshots(id, engagement_id, kind, content, sha256, byte_size, created_by)
      values (v_uuid, v_eng.id, v_text, v_doc, v_sha, v_bytes, v_uid);
    end if;
    insert into assurance.evidence_items(id, engagement_id, request_id, source_module, source_reference,
      source_as_of, collection_method, query_version, sha256, byte_size, storage_ref, classification, collected_by)
    values (v_uuid, v_eng.id, v_req.id, v_module, v_ref, v_as_of_ts, 'system', v_query_version,
      v_sha, v_bytes, v_ref, v_classification, v_uid);
    update assurance.evidence_requests set status = 'submitted', current_evidence_id = v_uuid where id = v_req.id;
    v_agg_type := 'evidence_request'; v_agg_id := v_req.id; v_from := 'open'; v_to := 'submitted';
    v_details := jsonb_build_object('evidence_id', v_uuid, 'source_kind', v_text, 'source_reference', v_ref,
      'source_as_of', v_as_of_ts, 'sha256', v_sha, 'byte_size', v_bytes, 'collection_method', 'system');

  when 'run_monitoring' then
    if v_eng.status not in ('fieldwork','reporting') then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_role is null or v_role not in ('lead','auditor') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_ctl from assurance.engagement_controls
     where id = assurance.uuid_field(p_payload, 'control_id') and engagement_id = v_eng.id;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_CONTROL_NOT_FOUND';
    end if;
    select * into v_item from assurance.evidence_items
     where id = assurance.uuid_field(p_payload, 'evidence_id') and engagement_id = v_eng.id;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_EVIDENCE_NOT_FOUND';
    end if;
    select * into v_snap from assurance.system_snapshots where id = v_item.id;
    if not found then
      perform assurance.state_error('ASSURANCE_MONITORING_SOURCE_INVALID');
    end if;
    for v_rule in select * from assurance.monitoring_rules(v_snap.kind, v_snap.content) loop
      if not exists (select 1 from assurance.monitoring_hits
                      where evidence_id = v_item.id and rule_code = v_rule.rule_code) then
        v_exc := gen_random_uuid();
        insert into assurance.exceptions(id, engagement_id, control_id, description, severity, status, source, recorded_by)
        values (v_exc, v_eng.id, v_ctl.id, left(v_rule.description, 4000), v_rule.severity, 'candidate',
          'continuous_monitoring', v_uid);
        insert into assurance.monitoring_hits(engagement_id, evidence_id, rule_code, exception_id, created_by)
        values (v_eng.id, v_item.id, v_rule.rule_code, v_exc, v_uid);
        v_hits := v_hits || jsonb_build_object('rule_code', v_rule.rule_code, 'severity', v_rule.severity,
          'exception_id', v_exc);
      end if;
    end loop;
    v_agg_type := 'evidence'; v_agg_id := v_item.id; v_to := 'monitored';
    v_details := jsonb_build_object('source_kind', v_snap.kind, 'evidence_sha256', v_item.sha256,
      'new_candidates', v_hits);

  when 'export_pack' then
    if v_eng.status not in ('issued','archived') then
      perform assurance.state_error('ASSURANCE_REPORT_NOT_ISSUED');
    end if;
    select * into v_report from assurance.report_versions
     where id = assurance.uuid_field(p_payload, 'report_id') and engagement_id = v_eng.id;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_REPORT_NOT_FOUND';
    end if;
    if v_report.report_version <> (select max(report_version) from assurance.report_versions
                                    where engagement_id = v_eng.id) then
      perform assurance.state_error('ASSURANCE_REPORT_SUPERSEDED');
    end if;
    v_manifest := assurance.pack_manifest(v_report.id);
    v_sha := encode(extensions.digest(convert_to(v_manifest::text, 'UTF8'), 'sha256'), 'hex');
    insert into assurance.exports(id, engagement_id, report_version_id, manifest_sha256, manifest_bytes,
      evidence_count, exported_by)
    values (assurance.uuid_field(p_payload, 'export_id'), v_eng.id, v_report.id, v_sha,
      octet_length(v_manifest::text), jsonb_array_length(v_manifest->'evidence'), v_uid);
    v_agg_type := 'export'; v_agg_id := (p_payload->>'export_id')::uuid; v_to := 'exported';
    v_details := jsonb_build_object('report_id', v_report.id, 'report_version', v_report.report_version,
      'manifest_sha256', v_sha, 'evidence_count', jsonb_array_length(v_manifest->'evidence'));
  end case;

  return assurance.complete_command(p_tenant_id, v_eng.id, p_idempotency_key, v_prep.o_hash,
    v_action, v_agg_type, v_agg_id, v_from, v_to, v_details);
end $$;

revoke all on all functions in schema assurance from public, anon, authenticated, service_role;
revoke all on function api.assurance_evidence_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
grant execute on function api.assurance_evidence_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
