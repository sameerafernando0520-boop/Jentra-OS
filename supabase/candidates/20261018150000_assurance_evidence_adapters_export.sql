-- Corporate Audit & Assurance - candidate slice A4 (blueprint 68).
-- CANDIDATE ONLY. Requires A1 and A2 (uses assurance.prepare_command and
-- assurance.complete_command). Adds system evidence adapters over the
-- authoritative, immutable module reports and a governed audit-pack export.
--
-- Adapters never widen access: each one calls the owning module's own scope
-- guard as the current user before reading the source, and binds only the
-- source reference, cutoff and a canonical SHA-256. Module report bytes are not
-- copied; the generated access-review snapshot (which has no source table) is
-- stored in a protected, immutable table.

create table assurance.system_snapshots (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  kind text not null check (kind = 'it_control.access_review'),
  content jsonb not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint not null check (byte_size between 1 and 104857600),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp()
);

create table assurance.exports (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  report_version_id uuid not null references assurance.report_versions(id),
  manifest_sha256 text not null check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  manifest_bytes bigint not null check (manifest_bytes > 0),
  evidence_count integer not null check (evidence_count >= 0),
  exported_by uuid not null references auth.users(id),
  exported_at timestamptz not null default clock_timestamp()
);

create index assurance_exports_engagement_idx on assurance.exports (engagement_id, exported_at);

do $$
declare t text;
begin
  foreach t in array array['system_snapshots','exports'] loop
    execute format('alter table assurance.%I enable row level security', t);
    execute format('alter table assurance.%I force row level security', t);
    execute format('revoke all on assurance.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger %I before update or delete on assurance.%I
      for each row execute function assurance.forbid_mutation()', t || '_immutable', t);
  end loop;
end $$;

-- Source kinds, owning module, query version and classification.
create function assurance.source_kind(p_kind text,
  out o_module text, out o_query_version text, out o_classification text)
language sql immutable set search_path = '' as $$
  select v.m, v.q, v.c from (values
    ('finance.financial_statement','finance','fin.financial_reports.v1','confidential'),
    ('finance.close_review','finance','fin.close_control_reviews.v1','confidential'),
    ('finance.control_reconciliation','finance','fin.control_reports.v1','confidential'),
    ('finance.tax_summary','finance','fin.tax_reports.v1','confidential'),
    ('inventory.valuation','inventory','inv.valuation_reports.v1','confidential'),
    ('it_control.access_review','it_control','core.access_review.v1','restricted')
  ) v(k, m, q, c) where v.k = p_kind;
$$;

-- Reads one authoritative source document after the owning module's guard has
-- accepted the current user for this scope. Unknown or out-of-scope sources
-- are indistinguishable (P0002) once the guard has passed.
create function assurance.source_document(p_kind text, p_tenant_id uuid, p_legal_entity_id uuid,
  p_branch_id uuid, p_source_id uuid, out o_document jsonb, out o_as_of date)
language plpgsql set search_path = '' as $$
begin
  case p_kind
  when 'finance.financial_statement' then
    perform core.wave3_require_scope(p_tenant_id, 'finance.view', p_legal_entity_id, null);
    perform core.wave3_require_scope(p_tenant_id, 'finance.view', p_legal_entity_id, p_branch_id);
    select to_jsonb(r), r.as_of into o_document, o_as_of from finance.financial_reports r
     where r.id = p_source_id and r.tenant_id = p_tenant_id and r.legal_entity_id = p_legal_entity_id;
  when 'finance.close_review' then
    perform finance.require_close_review_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
    select to_jsonb(r), r.as_of into o_document, o_as_of from finance.close_control_reviews r
     where r.id = p_source_id and r.tenant_id = p_tenant_id and r.legal_entity_id = p_legal_entity_id;
  when 'finance.control_reconciliation' then
    perform finance.require_control_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
    select to_jsonb(r), r.as_of into o_document, o_as_of from finance.control_reports r
     where r.id = p_source_id and r.tenant_id = p_tenant_id and r.legal_entity_id = p_legal_entity_id
       and r.branch_id = p_branch_id;
  when 'finance.tax_summary' then
    perform core.wave3_require_scope(p_tenant_id, 'finance.view', p_legal_entity_id, null);
    perform core.wave3_require_scope(p_tenant_id, 'finance.view', p_legal_entity_id, p_branch_id);
    select to_jsonb(r), r.as_of into o_document, o_as_of from finance.tax_reports r
     where r.id = p_source_id and r.tenant_id = p_tenant_id and r.legal_entity_id = p_legal_entity_id
       and r.requested_branch_id = p_branch_id;
  when 'inventory.valuation' then
    perform inventory.require_valuation_report_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
    select to_jsonb(r), r.as_of into o_document, o_as_of from inventory.valuation_reports r
     where r.id = p_source_id and r.tenant_id = p_tenant_id and r.legal_entity_id = p_legal_entity_id
       and r.branch_id = p_branch_id;
  else
    raise exception using errcode = '22023', message = 'ASSURANCE_SOURCE_KIND_INVALID';
  end case;
  if o_document is null then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_SOURCE_NOT_FOUND';
  end if;
end $$;

-- Point-in-time privileged-access review for the tenant: roles, MFA
-- requirement, privileged capabilities and active assignment counts. No user
-- identities, emails or secrets are included.
create function assurance.access_review_document(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
begin
  perform core.require_permission(p_tenant_id, 'audit.read', p_legal_entity_id, p_branch_id);
  return jsonb_build_object('tenant_id', p_tenant_id, 'roles', coalesce((
    select jsonb_agg(jsonb_build_object('role_id', r.id, 'code', r.code, 'requires_mfa', r.requires_mfa,
      'privileged_permissions', coalesce((select jsonb_agg(rp.permission_code order by rp.permission_code)
        from core.role_permissions rp join core.permissions p on p.code = rp.permission_code
        where rp.tenant_id = r.tenant_id and rp.role_id = r.id and p.privileged), '[]'::jsonb),
      'active_assignments', (select count(*) from core.role_assignments ra
        join core.memberships m on m.tenant_id = ra.tenant_id and m.id = ra.membership_id
        where ra.tenant_id = r.tenant_id and ra.role_id = r.id and m.status = 'active'))
      order by r.code)
    from core.roles r where r.tenant_id = p_tenant_id), '[]'::jsonb));
end $$;

-- Deterministic audit-pack manifest for one issued report version. Built only
-- from immutable rows, so re-deriving it later must reproduce the digest.
create function assurance.pack_manifest(p_report_version_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'format', 'jentra.assurance.audit_pack.v1',
    'engagement', jsonb_build_object('id', e.id, 'tenant_id', e.tenant_id,
      'legal_entity_id', e.legal_entity_id, 'branch_id', e.branch_id, 'name', e.name,
      'period_start', e.period_start, 'period_end', e.period_end,
      'evidence_cutoff_digest', e.evidence_cutoff_digest),
    'report', jsonb_build_object('id', v.id, 'report_version', v.report_version, 'digest', v.digest,
      'issued_by', v.issued_by, 'issued_at', v.issued_at, 'findings', v.findings_snapshot),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'request_id', i.request_id,
        'source_module', i.source_module, 'source_reference', i.source_reference,
        'source_as_of', i.source_as_of, 'collection_method', i.collection_method,
        'query_version', i.query_version, 'sha256', i.sha256, 'byte_size', i.byte_size,
        'classification', i.classification, 'collected_by', i.collected_by) order by i.id)
      from assurance.evidence_requests r join assurance.evidence_items i on i.id = r.current_evidence_id
      where r.engagement_id = e.id and r.status = 'accepted'), '[]'::jsonb))
  from assurance.report_versions v join assurance.engagements e on e.id = v.engagement_id
  where v.id = p_report_version_id;
$$;

create function assurance.evidence_action_permission(p_action text)
returns text language sql immutable set search_path = '' as $$
  select case p_action
    when 'collect_system_evidence' then 'assurance.evidence.request'
    when 'export_pack' then 'assurance.report.export'
  end;
$$;

create function assurance.evidence_action_fields(p_action text)
returns text[] language sql immutable set search_path = '' as $$
  select array['action','engagement_id'] || case p_action
    when 'collect_system_evidence' then array['request_id','evidence_id','source_kind','source_id']
    when 'export_pack' then array['export_id','report_id']
    else null end;
$$;

create function api.assurance_evidence_command(
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
    if v_text = 'it_control.access_review' then
      if p_payload->'source_id' is not null and p_payload->'source_id' <> 'null'::jsonb then
        raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD', detail = 'source_id';
      end if;
      v_doc := assurance.access_review_document(p_tenant_id, p_legal_entity_id, p_branch_id);
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
      -- A dated report is evidence as at the end of its as-of day (UTC).
      v_as_of_ts := ((v_as_of + 1)::timestamp at time zone 'UTC') - interval '1 microsecond';
    end if;
    v_bytes := octet_length(v_doc::text);
    if v_bytes > 104857600 then
      raise exception using errcode = '22023', message = 'ASSURANCE_EVIDENCE_TOO_LARGE';
    end if;
    v_sha := encode(extensions.digest(convert_to(v_doc::text, 'UTF8'), 'sha256'), 'hex');
    if v_text = 'it_control.access_review' then
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

-- Re-derives a system evidence item from its authoritative source under the
-- caller's current module authority and reports whether the digest still holds.
create function api.assurance_verify_evidence(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_evidence_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_item assurance.evidence_items%rowtype;
  v_kind text;
  v_doc jsonb;
  v_as_of date;
  v_sha text;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  select i.* into v_item from assurance.evidence_items i join assurance.engagements e on e.id = i.engagement_id
   where i.id = p_evidence_id and e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
     and e.branch_id is not distinct from p_branch_id;
  if not found or v_item.collection_method <> 'system' then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_EVIDENCE_NOT_FOUND';
  end if;
  v_kind := split_part(v_item.source_reference, '/', 1);
  if v_kind = 'assurance.system_snapshots' then
    select s.content into v_doc from assurance.system_snapshots s where s.id = v_item.id;
  else
    select o_document into v_doc from assurance.source_document(v_kind, p_tenant_id, p_legal_entity_id,
      p_branch_id, split_part(v_item.source_reference, '/', 2)::uuid);
  end if;
  v_sha := encode(extensions.digest(convert_to(v_doc::text, 'UTF8'), 'sha256'), 'hex');
  return jsonb_build_object('evidence_id', v_item.id, 'recorded_sha256', v_item.sha256,
    'current_sha256', v_sha, 'matches', v_sha = v_item.sha256 and octet_length(v_doc::text) = v_item.byte_size);
end $$;

-- Returns the manifest for a recorded export, re-derived from immutable rows,
-- with its recorded digest so the client can hash, compare and reopen.
create function api.assurance_export_manifest(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_export_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_export assurance.exports%rowtype;
  v_manifest jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  select x.* into v_export from assurance.exports x join assurance.engagements e on e.id = x.engagement_id
   where x.id = p_export_id and e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
     and e.branch_id is not distinct from p_branch_id;
  if not found then
    -- Authority first, so the absence of an export is not disclosed to outsiders.
    perform core.require_permission(p_tenant_id, 'assurance.report.export', p_legal_entity_id, p_branch_id);
    raise exception using errcode = 'P0002', message = 'ASSURANCE_EXPORT_NOT_FOUND';
  end if;
  if assurance.team_role(v_export.engagement_id, v_uid) = 'external' then
    if not core.has_permission(p_tenant_id, 'assurance.external_review', p_legal_entity_id, p_branch_id) then
      perform assurance.deny('ASSURANCE_EXTERNAL_ACCESS_EXPIRED');
    end if;
  elsif exists (select 1 from assurance.engagement_team
                 where engagement_id = v_export.engagement_id and user_id = v_uid and role = 'external') then
    perform assurance.deny('ASSURANCE_EXTERNAL_ACCESS_EXPIRED');
  else
    perform core.require_permission(p_tenant_id, 'assurance.report.export', p_legal_entity_id, p_branch_id);
  end if;
  v_manifest := assurance.pack_manifest(v_export.report_version_id);
  -- manifest_text is the exact UTF-8 text that was hashed, so a client can verify
  -- the downloaded bytes without re-serialising JSON.
  return jsonb_build_object('export_id', v_export.id, 'manifest', v_manifest, 'manifest_text', v_manifest::text,
    'manifest_sha256', v_export.manifest_sha256, 'manifest_bytes', v_export.manifest_bytes,
    'exported_by', v_export.exported_by, 'exported_at', v_export.exported_at);
end $$;

revoke all on all functions in schema assurance from public, anon, authenticated, service_role;
revoke all on function api.assurance_evidence_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
revoke all on function api.assurance_verify_evidence(uuid, uuid, uuid, uuid) from public, anon, service_role;
revoke all on function api.assurance_export_manifest(uuid, uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_evidence_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
grant execute on function api.assurance_verify_evidence(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function api.assurance_export_manifest(uuid, uuid, uuid, uuid) to authenticated;
