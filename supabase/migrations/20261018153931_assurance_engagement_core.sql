-- Corporate Audit & Assurance — candidate slice A1 (blueprint 68).
-- CANDIDATE ONLY. Not installed. Kept outside supabase/migrations so the local
-- ledger continues to match the live 115-migration ledger. Installation needs
-- explicit approval and refreshed live/source hashes (see
-- docs/development/corporate-audit-installation-runbook.md).
--
-- Business audit engagements live in the dedicated `assurance` schema and are
-- separate from the technical append-only `audit.events` table.

create schema assurance;
revoke all on schema assurance from public, anon, authenticated, service_role;

insert into core.permissions(code, module, description, privileged) values
 ('assurance.plan.manage','assurance','Manage audit universe, risk assessment and audit plans',true),
 ('assurance.engagement.manage','assurance','Create engagements, team, scope and control mapping',true),
 ('assurance.evidence.request','assurance','Issue evidence/PBC requests',false),
 ('assurance.evidence.submit','assurance','Submit evidence for an assigned request',false),
 ('assurance.evidence.view','assurance','View evidence metadata, provenance and digests',false),
 ('assurance.test.perform','assurance','Record test results and exceptions',false),
 ('assurance.test.review','assurance','Review evidence and test workpapers',false),
 ('assurance.finding.issue','assurance','Issue formal findings from exceptions',true),
 ('assurance.response.manage','assurance','Record management responses',false),
 ('assurance.remediation.manage','assurance','Submit remediation evidence',false),
 ('assurance.retest.perform','assurance','Perform independent remediation retests',true),
 ('assurance.engagement.close','assurance','Issue/reopen reports, decide risk acceptance, reopen findings',true),
 ('assurance.report.export','assurance','Export issued audit reports and evidence packages',true),
 ('assurance.retention.manage','assurance','Place and release assurance legal holds',true),
 ('assurance.external_review','assurance','Time-bound read-only external auditor access',false)
on conflict (code) do nothing;

create table assurance.engagements (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  name text not null check (length(btrim(name)) between 3 and 160),
  period_start date not null,
  period_end date not null,
  scope_summary text not null check (length(btrim(scope_summary)) between 3 and 2000),
  lead_auditor_id uuid not null references auth.users(id),
  status text not null default 'planning'
    check (status in ('planning','fieldwork','reporting','issued','archived','cancelled')),
  evidence_frozen_at timestamptz,
  evidence_cutoff_digest text check (evidence_cutoff_digest ~ '^[0-9a-f]{64}$'),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (period_end >= period_start),
  check ((evidence_frozen_at is null) = (evidence_cutoff_digest is null)),
  unique (tenant_id, id),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id)
);

create table assurance.engagement_team (
  engagement_id uuid not null references assurance.engagements(id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('lead','auditor','reviewer','external')),
  expires_at timestamptz,
  added_by uuid not null references auth.users(id),
  added_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id),
  primary key (engagement_id, user_id),
  check ((role = 'external') = (expires_at is not null)),
  check ((revoked_at is null) = (revoked_by is null))
);

create table assurance.engagement_controls (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  control_code text not null check (control_code ~ '^[A-Z0-9][A-Z0-9._-]{1,39}$'),
  title text not null check (length(btrim(title)) between 3 and 160),
  owner_id uuid not null references auth.users(id),
  risk text not null check (risk in ('low','medium','high','critical')),
  mapped_by uuid not null references auth.users(id),
  mapped_at timestamptz not null default clock_timestamp(),
  unique (engagement_id, control_code)
);

create table assurance.evidence_requests (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  control_id uuid not null references assurance.engagement_controls(id),
  owner_id uuid not null references auth.users(id),
  description text not null check (length(btrim(description)) between 3 and 2000),
  due_date date not null,
  status text not null default 'open'
    check (status in ('open','submitted','accepted','cancelled')),
  rework_count integer not null default 0 check (rework_count >= 0),
  current_evidence_id uuid,
  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default clock_timestamp()
);

create table assurance.evidence_items (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  request_id uuid not null references assurance.evidence_requests(id),
  source_module text not null
    check (source_module in ('finance','procurement','inventory','workforce','it_control','manual')),
  source_reference text not null check (length(btrim(source_reference)) between 1 and 200),
  source_as_of timestamptz not null,
  collection_method text not null check (collection_method in ('system','manual')),
  query_version text check (query_version is null or query_version ~ '^[a-z0-9._-]{1,64}$'),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint not null check (byte_size between 1 and 104857600),
  storage_ref text not null,
  classification text not null check (classification in ('internal','confidential','restricted')),
  collected_by uuid not null references auth.users(id),
  collected_at timestamptz not null default clock_timestamp(),
  check ((source_module = 'manual') = (collection_method = 'manual'))
);

create table assurance.exceptions (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  control_id uuid not null references assurance.engagement_controls(id),
  description text not null check (length(btrim(description)) between 3 and 4000),
  severity text not null check (severity in ('low','medium','high','critical')),
  status text not null default 'candidate' check (status in ('candidate','promoted','dismissed')),
  source text not null default 'manual' check (source in ('manual','continuous_monitoring')),
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default clock_timestamp()
);

create table assurance.findings (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  exception_id uuid not null unique references assurance.exceptions(id),
  title text not null check (length(btrim(title)) between 3 and 160),
  severity text not null check (severity in ('low','medium','high','critical')),
  owner_id uuid not null references auth.users(id),
  status text not null default 'issued' check (status in
    ('issued','remediating','risk_pending','risk_accepted','retest_pending','closed')),
  response text,
  response_due date,
  remediation_submitted_by uuid references auth.users(id),
  remediation_sha256 text check (remediation_sha256 ~ '^[0-9a-f]{64}$'),
  carried_from_finding_id uuid references assurance.findings(id),
  issued_by uuid not null references auth.users(id),
  issued_at timestamptz not null default clock_timestamp()
);

create table assurance.retests (
  id uuid primary key,
  finding_id uuid not null references assurance.findings(id),
  result text not null check (result in ('pass','fail')),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  note text not null check (length(btrim(note)) between 3 and 2000),
  performed_by uuid not null references auth.users(id),
  performed_at timestamptz not null default clock_timestamp()
);

create table assurance.report_versions (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  report_version integer not null check (report_version > 0),
  summary text not null check (length(btrim(summary)) between 3 and 4000),
  evidence_cutoff_digest text not null check (evidence_cutoff_digest ~ '^[0-9a-f]{64}$'),
  findings_snapshot jsonb not null,
  digest text not null check (digest ~ '^[0-9a-f]{64}$'),
  issued_by uuid not null references auth.users(id),
  issued_at timestamptz not null default clock_timestamp(),
  unique (engagement_id, report_version)
);

create table assurance.retention_holds (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  placed_by uuid not null references auth.users(id),
  placed_at timestamptz not null default clock_timestamp(),
  released_by uuid references auth.users(id),
  released_at timestamptz,
  release_reason text,
  check ((released_at is null) = (released_by is null)),
  check (released_by is null or released_by <> placed_by)
);

create table assurance.events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  engagement_id uuid not null references assurance.engagements(id),
  engagement_version bigint not null,
  action text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  from_status text,
  to_status text,
  actor_id uuid not null references auth.users(id),
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (engagement_id, engagement_version)
);

create table assurance.command_receipts (
  actor_id uuid not null references auth.users(id),
  idempotency_key uuid not null,
  tenant_id uuid not null references core.tenants(id),
  request_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (actor_id, idempotency_key)
);

create index assurance_engagements_scope_idx
  on assurance.engagements (tenant_id, legal_entity_id, branch_id, status, id);
create index assurance_requests_engagement_idx
  on assurance.evidence_requests (engagement_id, status, due_date);
create index assurance_requests_owner_idx on assurance.evidence_requests (owner_id, status);
create index assurance_findings_engagement_idx
  on assurance.findings (engagement_id, status, severity);
create index assurance_findings_owner_idx on assurance.findings (owner_id, status);
create index assurance_events_engagement_idx
  on assurance.events (engagement_id, occurred_at, id);
create index assurance_items_request_idx on assurance.evidence_items (request_id);
create index assurance_controls_engagement_idx on assurance.engagement_controls (engagement_id);
create index assurance_exceptions_engagement_idx on assurance.exceptions (engagement_id, status);
create index assurance_retests_finding_idx on assurance.retests (finding_id);
create index assurance_holds_engagement_idx on assurance.retention_holds (engagement_id)
  where released_at is null;

do $$
declare t text;
begin
  foreach t in array array['engagements','engagement_team','engagement_controls',
    'evidence_requests','evidence_items','exceptions','findings','retests',
    'report_versions','retention_holds','events','command_receipts'] loop
    execute format('alter table assurance.%I enable row level security', t);
    execute format('alter table assurance.%I force row level security', t);
    execute format('revoke all on assurance.%I from public, anon, authenticated, service_role', t);
  end loop;
end $$;

-- Immutable history: evidence provenance, retests, issued reports, events and
-- receipts are never updated or deleted. Current-state rows are never deleted.
create function assurance.forbid_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
end $$;

do $$
declare t text;
begin
  foreach t in array array['evidence_items','retests','report_versions','events','command_receipts'] loop
    execute format('create trigger %I before update or delete on assurance.%I
      for each row execute function assurance.forbid_mutation()', t || '_immutable', t);
  end loop;
  foreach t in array array['engagements','engagement_team','engagement_controls',
    'evidence_requests','exceptions','findings','retention_holds'] loop
    execute format('create trigger %I before delete on assurance.%I
      for each row execute function assurance.forbid_mutation()', t || '_no_delete', t);
  end loop;
end $$;

create function assurance.hold_release_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.released_at is not null
     or (new.id, new.engagement_id, new.reason, new.placed_by, new.placed_at)
        is distinct from (old.id, old.engagement_id, old.reason, old.placed_by, old.placed_at) then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger retention_holds_release_only before update on assurance.retention_holds
  for each row execute function assurance.hold_release_only();

-- Engagement scope fields never change after creation.
create function assurance.engagement_scope_fixed() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.id, new.tenant_id, new.legal_entity_id, new.branch_id, new.lead_auditor_id,
      new.created_by, new.created_at)
     is distinct from (old.id, old.tenant_id, old.legal_entity_id, old.branch_id,
      old.lead_auditor_id, old.created_by, old.created_at)
     or (old.evidence_frozen_at is not null
         and (new.evidence_frozen_at, new.evidence_cutoff_digest)
             is distinct from (old.evidence_frozen_at, old.evidence_cutoff_digest)) then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger engagements_scope_fixed before update on assurance.engagements
  for each row execute function assurance.engagement_scope_fixed();

create function assurance.recent_mfa(p_window_seconds integer default 900)
returns boolean language sql stable set search_path = '' as $$
  select coalesce((select auth.jwt()->>'aal'), 'aal1') = 'aal2'
    and exists (
      select 1 from jsonb_array_elements(
        case when jsonb_typeof((select auth.jwt())->'amr') = 'array'
             then (select auth.jwt())->'amr' else '[]'::jsonb end) a
      where a->>'method' in ('totp','webauthn','phone')
        and (a->>'timestamp') ~ '^[0-9]{1,12}$'
        and (a->>'timestamp')::bigint >= extract(epoch from now())::bigint - p_window_seconds
    );
$$;

create function assurance.action_permission(p_action text)
returns text language sql immutable set search_path = '' as $$
  select case p_action
    when 'create_engagement' then 'assurance.engagement.manage'
    when 'add_team_member' then 'assurance.engagement.manage'
    when 'revoke_team_member' then 'assurance.engagement.manage'
    when 'map_control' then 'assurance.engagement.manage'
    when 'transition' then 'assurance.engagement.manage'
    when 'freeze_evidence' then 'assurance.engagement.manage'
    when 'request_evidence' then 'assurance.evidence.request'
    when 'cancel_request' then 'assurance.evidence.request'
    when 'submit_evidence' then 'assurance.evidence.submit'
    when 'review_evidence' then 'assurance.test.review'
    when 'record_exception' then 'assurance.test.perform'
    when 'dismiss_exception' then 'assurance.test.review'
    when 'issue_finding' then 'assurance.finding.issue'
    when 'respond' then 'assurance.response.manage'
    when 'decide_risk' then 'assurance.engagement.close'
    when 'submit_remediation' then 'assurance.remediation.manage'
    when 'retest' then 'assurance.retest.perform'
    when 'reopen_finding' then 'assurance.engagement.close'
    when 'issue_report' then 'assurance.engagement.close'
    when 'reopen_report' then 'assurance.engagement.close'
    when 'place_hold' then 'assurance.retention.manage'
    when 'release_hold' then 'assurance.retention.manage'
  end;
$$;

create function assurance.action_fields(p_action text)
returns text[] language sql immutable set search_path = '' as $$
  select array['action','engagement_id'] || case p_action
    when 'create_engagement' then array['name','period_start','period_end','scope_summary','lead_auditor_id']
    when 'add_team_member' then array['user_id','role','expires_at']
    when 'revoke_team_member' then array['user_id','reason']
    when 'map_control' then array['control_id','control_code','title','owner_id','risk']
    when 'transition' then array['to_status','reason']
    when 'freeze_evidence' then array['reason']
    when 'request_evidence' then array['request_id','control_id','owner_id','due_date','description']
    when 'cancel_request' then array['request_id','reason']
    when 'submit_evidence' then array['request_id','evidence_id','source_module','source_reference',
      'source_as_of','collection_method','query_version','sha256','byte_size','storage_ref','classification']
    when 'review_evidence' then array['request_id','decision','reason']
    when 'record_exception' then array['exception_id','control_id','description','severity']
    when 'dismiss_exception' then array['exception_id','reason']
    when 'issue_finding' then array['finding_id','exception_id','title','severity','owner_id']
    when 'respond' then array['finding_id','response','due_date','accept_risk']
    when 'decide_risk' then array['finding_id','decision','reason']
    when 'submit_remediation' then array['finding_id','evidence_sha256','note']
    when 'retest' then array['finding_id','retest_id','result','evidence_sha256','note']
    when 'reopen_finding' then array['finding_id','reason']
    when 'issue_report' then array['report_id','summary']
    when 'reopen_report' then array['reason']
    when 'place_hold' then array['hold_id','reason']
    when 'release_hold' then array['hold_id','reason']
    else null end;
$$;

create function assurance.mfa_action(p_action text)
returns boolean language sql immutable set search_path = '' as $$
  select p_action in ('freeze_evidence','issue_finding','decide_risk','retest',
    'reopen_finding','issue_report','reopen_report','release_hold');
$$;

create function assurance.uuid_field(p jsonb, k text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(jsonb_typeof(p->k), '') <> 'string'
     or (p->>k) !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = k;
  end if;
  return (p->>k)::uuid;
end $$;

create function assurance.text_field(p jsonb, k text, lo integer, hi integer) returns text
language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(jsonb_typeof(p->k), '') <> 'string' or length(btrim(p->>k)) not between lo and hi then
    raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = k;
  end if;
  return p->>k;
end $$;

create function assurance.date_field(p jsonb, k text) returns date
language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(jsonb_typeof(p->k), '') <> 'string' or (p->>k) !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = k;
  end if;
  return (p->>k)::date;
exception when datetime_field_overflow or invalid_datetime_format then
  raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = k;
end $$;

create function assurance.digest_field(p jsonb, k text) returns text
language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(jsonb_typeof(p->k), '') <> 'string' or (p->>k) !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'ASSURANCE_DIGEST_INVALID', detail = k;
  end if;
  return p->>k;
end $$;

create function assurance.active_member(p_tenant_id uuid, p_user_id uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from core.memberships m
    where m.tenant_id = p_tenant_id and m.user_id = p_user_id and m.status = 'active');
$$;

create function assurance.team_role(p_engagement_id uuid, p_user_id uuid) returns text
language sql stable set search_path = '' as $$
  select t.role from assurance.engagement_team t
  where t.engagement_id = p_engagement_id and t.user_id = p_user_id
    and t.revoked_at is null
    and (t.expires_at is null or t.expires_at > now());
$$;

create function assurance.deny(p_message text) returns void
language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '42501', message = p_message;
end $$;

create function assurance.state_error(p_message text) returns void
language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '55000', message = p_message;
end $$;

create function assurance.require_scope(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid)
returns void language plpgsql stable set search_path = '' as $$
begin
  if not exists (select 1 from core.tenants t where t.id = p_tenant_id and t.status in ('trial','active'))
     or not exists (select 1 from core.legal_entities e
       where e.tenant_id = p_tenant_id and e.id = p_legal_entity_id and e.status = 'active')
     or (p_branch_id is not null and not exists (select 1 from core.branches b
       where b.tenant_id = p_tenant_id and b.legal_entity_id = p_legal_entity_id
         and b.id = p_branch_id and b.status = 'active')) then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_SCOPE_NOT_FOUND';
  end if;
end $$;

create function api.assurance_command(
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
    if p_expected_version <> 0 then
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
    if v_eng.version <> p_expected_version then
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

create function api.assurance_engagement(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_engagement_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_eng assurance.engagements%rowtype;
  v_external boolean;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  v_external := exists (select 1 from assurance.engagement_team
    where engagement_id = p_engagement_id and user_id = v_uid and role = 'external');
  -- Authority is checked before existence so unauthorized callers cannot probe engagements.
  if v_external then
    -- Time-bound, engagement-scoped and read-only; revocation or expiry is immediate.
    if assurance.team_role(p_engagement_id, v_uid) is distinct from 'external'
       or not core.has_permission(p_tenant_id, 'assurance.external_review', p_legal_entity_id, p_branch_id) then
      perform assurance.deny('ASSURANCE_EXTERNAL_ACCESS_EXPIRED');
    end if;
  else
    perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  end if;
  select * into v_eng from assurance.engagements
   where id = p_engagement_id and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
     and branch_id is not distinct from p_branch_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_ENGAGEMENT_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'engagement', jsonb_build_object('id', v_eng.id, 'name', v_eng.name, 'status', v_eng.status,
      'version', v_eng.version, 'period_start', v_eng.period_start, 'period_end', v_eng.period_end,
      'scope_summary', v_eng.scope_summary, 'lead_auditor_id', v_eng.lead_auditor_id,
      'evidence_frozen_at', v_eng.evidence_frozen_at, 'evidence_cutoff_digest', v_eng.evidence_cutoff_digest),
    'controls', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'control_code', c.control_code,
      'title', c.title, 'owner_id', c.owner_id, 'risk', c.risk) order by c.control_code)
      from assurance.engagement_controls c where c.engagement_id = p_engagement_id), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'control_id', r.control_id,
      'owner_id', r.owner_id, 'due_date', r.due_date, 'status', r.status, 'rework_count', r.rework_count,
      'evidence', case when i.id is null then null else jsonb_build_object('id', i.id,
        'source_module', i.source_module, 'source_reference', i.source_reference,
        'source_as_of', i.source_as_of, 'collection_method', i.collection_method,
        'query_version', i.query_version, 'sha256', i.sha256, 'byte_size', i.byte_size,
        'classification', i.classification, 'collected_by', i.collected_by, 'collected_at', i.collected_at,
        'storage_ref', case when v_external then null else i.storage_ref end) end) order by r.due_date, r.id)
      from assurance.evidence_requests r left join assurance.evidence_items i on i.id = r.current_evidence_id
      where r.engagement_id = p_engagement_id), '[]'::jsonb),
    'exceptions', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'control_id', x.control_id,
      'severity', x.severity, 'status', x.status, 'source', x.source) order by x.recorded_at, x.id)
      from assurance.exceptions x where x.engagement_id = p_engagement_id), '[]'::jsonb),
    'findings', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'title', f.title,
      'severity', f.severity, 'status', f.status, 'owner_id', f.owner_id, 'response_due', f.response_due,
      'issued_at', f.issued_at) order by f.issued_at, f.id)
      from assurance.findings f where f.engagement_id = p_engagement_id), '[]'::jsonb),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'report_version', v.report_version,
      'digest', v.digest, 'issued_by', v.issued_by, 'issued_at', v.issued_at) order by v.report_version)
      from assurance.report_versions v where v.engagement_id = p_engagement_id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('version', e.engagement_version,
      'action', e.action, 'aggregate_type', e.aggregate_type, 'aggregate_id', e.aggregate_id,
      'from_status', e.from_status, 'to_status', e.to_status, 'actor_id', e.actor_id,
      'occurred_at', e.occurred_at) order by e.engagement_version)
      from assurance.events e where e.engagement_id = p_engagement_id), '[]'::jsonb)
  );
end $$;

revoke all on all functions in schema assurance from public, anon, authenticated, service_role;
revoke all on function api.assurance_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
revoke all on function api.assurance_engagement(uuid, uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
grant execute on function api.assurance_engagement(uuid, uuid, uuid, uuid) to authenticated;
