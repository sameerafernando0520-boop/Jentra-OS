-- Corporate Audit & Assurance A9: tenant settings and plan revision.
-- CANDIDATE ONLY. Not installed. Requires A1-A5 and the version-guard
-- candidate (20261019090000), whose api.assurance_plan_command body it extends.
--
-- Reminder bands, the finding-response deadline, risk-rating bands and
-- monitoring-rule thresholds were fixed in source. They become settings per
-- tenant, optionally overridden per legal entity (the entity row replaces the
-- tenant row as a whole); without a row today's values apply:
--   due soon within 3 days, escalated more than 7 days late, findings answered
--   within 14 days, ratings critical >= 20, high >= 10, medium >= 5, and every
--   monitoring rule raised from one occurrence.
-- Existing risk assessments keep the rating they were recorded with.
--
-- An approved plan can be revised: supersede_plan creates a draft copy of its
-- period and active areas; approving that draft moves the original to the
-- terminal status superseded in the same transaction. Engagements already
-- created from the original are untouched.
--
-- Replaced functions are copied verbatim from their installed or candidate
-- source; every change is marked "-- A9:". The two-argument
-- assurance.reminder_level(date, date) and assurance.response_sla_days() stay
-- as the default-value helpers; the read models no longer call them.

create function assurance.default_monitoring() returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'ACCESS_PRIVILEGED_NO_MFA', jsonb_build_object('enabled', true, 'min_count', 1),
    'P2P_MATCH_OVERRIDE', jsonb_build_object('enabled', true, 'min_count', 1),
    'P2P_OVERRIDE_BY_CREATOR', jsonb_build_object('enabled', true, 'min_count', 1),
    'HR_ATTENDANCE_SELF_APPROVAL', jsonb_build_object('enabled', true, 'min_count', 1));
$$;

create table assurance.settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid,
  due_soon_days integer not null check (due_soon_days between 1 and 30),
  escalate_after_days integer not null check (escalate_after_days between 1 and 90),
  finding_response_days integer not null check (finding_response_days between 1 and 90),
  band_critical integer not null check (band_critical between 2 and 25),
  band_high integer not null check (band_high between 2 and 25),
  band_medium integer not null check (band_medium between 2 and 25),
  monitoring jsonb not null,
  version bigint not null default 1 check (version > 0),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default clock_timestamp(),
  check (band_critical > band_high and band_high > band_medium),
  unique nulls not distinct (tenant_id, legal_entity_id),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id, id)
);
create index assurance_settings_actor_idx on assurance.settings(updated_by);

create table assurance.settings_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  settings_id uuid not null references assurance.settings(id),
  level text not null check (level in ('tenant','entity')),
  version bigint not null check (version > 0),
  values_after jsonb not null,
  actor_id uuid not null references auth.users(id),
  occurred_at timestamptz not null default clock_timestamp(),
  unique (settings_id, version)
);
create index assurance_settings_events_tenant_idx on assurance.settings_events(tenant_id);
create index assurance_settings_events_actor_idx on assurance.settings_events(actor_id);
create trigger settings_events_immutable before update or delete on assurance.settings_events
  for each row execute function assurance.forbid_mutation();

alter table assurance.settings enable row level security;
alter table assurance.settings force row level security;
alter table assurance.settings_events enable row level security;
alter table assurance.settings_events force row level security;
revoke all on assurance.settings, assurance.settings_events from public, anon, authenticated, service_role;

create function assurance.effective_settings(p_tenant_id uuid, p_legal_entity_id uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object(
        'source', case when s.legal_entity_id is null then 'tenant' else 'entity' end,
        'due_soon_days', s.due_soon_days,
        'escalate_after_days', s.escalate_after_days,
        'finding_response_days', s.finding_response_days,
        'rating_bands', jsonb_build_object('critical', s.band_critical, 'high', s.band_high, 'medium', s.band_medium),
        'monitoring', s.monitoring)
       from assurance.settings s
      where s.tenant_id = p_tenant_id
        and (s.legal_entity_id is null or s.legal_entity_id = p_legal_entity_id)
      order by s.legal_entity_id nulls last
      limit 1),
    jsonb_build_object('source', 'default', 'due_soon_days', 3, 'escalate_after_days', 7,
      'finding_response_days', 14,
      'rating_bands', jsonb_build_object('critical', 20, 'high', 10, 'medium', 5),
      'monitoring', assurance.default_monitoring()));
$$;

-- Tenant-aware reminder level: on_track, due_soon (due within due_soon_days
-- or today), overdue (1 day late up to escalate_after_days), escalated.
create function assurance.reminder_level(p_tenant_id uuid, p_legal_entity_id uuid, p_due date, p_today date)
returns text language sql stable set search_path = '' as $$
  select case when p_due is null then 'on_track'
              when p_today - p_due > (x.s->>'escalate_after_days')::integer then 'escalated'
              when p_today - p_due >= 1 then 'overdue'
              when p_due - p_today <= (x.s->>'due_soon_days')::integer then 'due_soon'
              else 'on_track' end
    from (select assurance.effective_settings(p_tenant_id, p_legal_entity_id) s) x;
$$;

create function assurance.response_days(p_tenant_id uuid, p_legal_entity_id uuid) returns integer
language sql stable set search_path = '' as $$
  select (assurance.effective_settings(p_tenant_id, p_legal_entity_id)->>'finding_response_days')::integer;
$$;

create function assurance.risk_rating_for(p_tenant_id uuid, p_legal_entity_id uuid, p_score integer)
returns text language sql stable set search_path = '' as $$
  select case when p_score >= (x.b->>'critical')::integer then 'critical'
              when p_score >= (x.b->>'high')::integer then 'high'
              when p_score >= (x.b->>'medium')::integer then 'medium' else 'low' end
    from (select assurance.effective_settings(p_tenant_id, p_legal_entity_id)->'rating_bands' b) x;
$$;

-- The A4b rules with their occurrence counts, kept only when the rule is
-- enabled and the count reaches its minimum.
create function assurance.monitoring_rules(p_kind text, p_content jsonb, p_settings jsonb)
returns table (rule_code text, severity text, description text)
language sql immutable set search_path = '' as $$
  select r.rule_code, r.severity, r.description from (
    select 'ACCESS_PRIVILEGED_NO_MFA' rule_code, 'high' severity,
           format('%s active role(s) grant privileged capabilities without requiring MFA: %s',
             count(*), string_agg(x->>'code', ', ' order by x->>'code')) description,
           count(*)::integer hits
      from jsonb_array_elements(case when p_kind = 'it_control.access_review' then p_content->'roles' else '[]'::jsonb end) x
     where not (x->>'requires_mfa')::boolean and jsonb_array_length(x->'privileged_permissions') > 0
       and (x->>'active_assignments')::integer > 0
    having count(*) > 0
    union all
    select 'P2P_MATCH_OVERRIDE', 'medium',
           format('%s posted supplier bill(s) in the period required a three-way-match override',
             (p_content->>'bills_with_match_override')::integer),
           (p_content->>'bills_with_match_override')::integer
     where p_kind = 'procurement.three_way_match' and (p_content->>'bills_with_match_override')::integer > 0
    union all
    select 'P2P_OVERRIDE_BY_CREATOR', 'high',
           format('%s match override(s) were approved by the user who created the bill',
             (p_content->>'overrides_by_bill_creator')::integer),
           (p_content->>'overrides_by_bill_creator')::integer
     where p_kind = 'procurement.three_way_match' and (p_content->>'overrides_by_bill_creator')::integer > 0
    union all
    select 'HR_ATTENDANCE_SELF_APPROVAL', 'high',
           format('%s attendance decision(s) were made by the submitter or creator',
             (p_content->>'self_decided')::integer),
           (p_content->>'self_decided')::integer
     where p_kind = 'workforce.attendance_approvals' and (p_content->>'self_decided')::integer > 0
  ) r
  where coalesce((p_settings->r.rule_code->>'enabled')::boolean, true)
    and r.hits >= greatest(coalesce((p_settings->r.rule_code->>'min_count')::integer, 1), 1);
$$;

create function assurance.settings_int(p jsonb, k text, lo integer, hi integer) returns integer
language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(jsonb_typeof(p->k), '') <> 'number' or (p->>k) !~ '^[0-9]{1,5}$'
     or (p->>k)::integer not between lo and hi then
    raise exception using errcode = '22023', message = 'ASSURANCE_SETTINGS_INVALID', detail = k;
  end if;
  return (p->>k)::integer;
end $$;

create function api.assurance_settings(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if not core.has_permission(p_tenant_id, 'assurance.plan.manage', p_legal_entity_id, p_branch_id) then
    perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  end if;
  return jsonb_build_object(
    'effective', assurance.effective_settings(p_tenant_id, p_legal_entity_id),
    'tenant', (select jsonb_build_object('version', s.version, 'updated_at', s.updated_at)
                 from assurance.settings s where s.tenant_id = p_tenant_id and s.legal_entity_id is null),
    'entity', (select jsonb_build_object('version', s.version, 'updated_at', s.updated_at)
                 from assurance.settings s where s.tenant_id = p_tenant_id and s.legal_entity_id = p_legal_entity_id),
    'rules', jsonb_build_array(
      jsonb_build_object('code', 'ACCESS_PRIVILEGED_NO_MFA',
        'description', 'Roles that grant privileged capabilities without requiring MFA'),
      jsonb_build_object('code', 'P2P_MATCH_OVERRIDE',
        'description', 'Supplier bills posted with a three-way-match override'),
      jsonb_build_object('code', 'P2P_OVERRIDE_BY_CREATOR',
        'description', 'Match overrides approved by the bill''s creator'),
      jsonb_build_object('code', 'HR_ATTENDANCE_SELF_APPROVAL',
        'description', 'Attendance decided by the person who submitted or created it')));
end $$;

create function api.assurance_settings_command(
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
  v_hash text;
  v_receipt assurance.command_receipts%rowtype;
  v_level text;
  v_entity uuid;
  v_due integer;
  v_esc integer;
  v_resp integer;
  v_crit integer;
  v_high integer;
  v_med integer;
  v_mon jsonb;
  v_rule text;
  v_row assurance.settings%rowtype;
  v_response jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object'
     or exists (select 1 from jsonb_object_keys(p_payload) k
                 where k <> all (array['level','due_soon_days','escalate_after_days','finding_response_days',
                   'rating_bands','monitoring'])) then
    raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD';
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, 'assurance.plan.manage', p_legal_entity_id, p_branch_id);
  if p_expected_version is null then
    raise exception using errcode = '22023', message = 'ASSURANCE_VERSION_REQUIRED';
  end if;
  v_hash := encode(extensions.digest(convert_to(jsonb_build_array(
    p_tenant_id, p_legal_entity_id, p_branch_id, p_expected_version, p_payload)::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt from assurance.command_receipts
   where actor_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    if v_receipt.request_hash <> v_hash or v_receipt.tenant_id <> p_tenant_id then
      raise exception using errcode = '22023', message = 'IDEMPOTENCY_MISMATCH';
    end if;
    return v_receipt.response;
  end if;
  if not assurance.recent_mfa() then
    perform assurance.deny('ASSURANCE_RECENT_MFA_REQUIRED');
  end if;

  v_level := p_payload->>'level';
  if coalesce(jsonb_typeof(p_payload->'level'), '') <> 'string' or v_level not in ('tenant','entity') then
    raise exception using errcode = '22023', message = 'ASSURANCE_SETTINGS_INVALID', detail = 'level';
  end if;
  v_due := assurance.settings_int(p_payload, 'due_soon_days', 1, 30);
  v_esc := assurance.settings_int(p_payload, 'escalate_after_days', 1, 90);
  v_resp := assurance.settings_int(p_payload, 'finding_response_days', 1, 90);
  if coalesce(jsonb_typeof(p_payload->'rating_bands'), '') <> 'object'
     or (select count(*) from jsonb_object_keys(p_payload->'rating_bands')) <> 3 then
    raise exception using errcode = '22023', message = 'ASSURANCE_SETTINGS_INVALID', detail = 'rating_bands';
  end if;
  v_crit := assurance.settings_int(p_payload->'rating_bands', 'critical', 2, 25);
  v_high := assurance.settings_int(p_payload->'rating_bands', 'high', 2, 25);
  v_med := assurance.settings_int(p_payload->'rating_bands', 'medium', 2, 25);
  if not (v_crit > v_high and v_high > v_med) then
    raise exception using errcode = '22023', message = 'ASSURANCE_SETTINGS_INVALID', detail = 'rating_bands';
  end if;
  v_mon := p_payload->'monitoring';
  if coalesce(jsonb_typeof(v_mon), '') <> 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_mon) k)
        is distinct from (select array_agg(k order by k) from jsonb_object_keys(assurance.default_monitoring()) k) then
    raise exception using errcode = '22023', message = 'ASSURANCE_SETTINGS_INVALID', detail = 'monitoring';
  end if;
  for v_rule in select k from jsonb_object_keys(v_mon) k loop
    if coalesce(jsonb_typeof(v_mon->v_rule), '') <> 'object'
       or (select count(*) from jsonb_object_keys(v_mon->v_rule)) <> 2
       or coalesce(jsonb_typeof(v_mon->v_rule->'enabled'), '') <> 'boolean' then
      raise exception using errcode = '22023', message = 'ASSURANCE_SETTINGS_INVALID', detail = 'monitoring';
    end if;
    perform assurance.settings_int(v_mon->v_rule, 'min_count', 1, 10000);
  end loop;

  v_entity := case when v_level = 'entity' then p_legal_entity_id end;
  select * into v_row from assurance.settings
   where tenant_id = p_tenant_id and legal_entity_id is not distinct from v_entity
   for update;
  if not found then
    if p_expected_version <> 0 then
      raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
    end if;
    insert into assurance.settings(tenant_id, legal_entity_id, due_soon_days, escalate_after_days,
      finding_response_days, band_critical, band_high, band_medium, monitoring, updated_by)
    values (p_tenant_id, v_entity, v_due, v_esc, v_resp, v_crit, v_high, v_med, v_mon, v_uid)
    returning * into v_row;
  else
    if v_row.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
    end if;
    update assurance.settings set due_soon_days = v_due, escalate_after_days = v_esc,
      finding_response_days = v_resp, band_critical = v_crit, band_high = v_high, band_medium = v_med,
      monitoring = v_mon, version = version + 1, updated_by = v_uid, updated_at = clock_timestamp()
     where id = v_row.id returning * into v_row;
  end if;
  insert into assurance.settings_events(tenant_id, settings_id, level, version, values_after, actor_id)
  values (p_tenant_id, v_row.id, v_level, v_row.version, p_payload - 'level', v_uid);
  v_response := jsonb_build_object('level', v_level, 'version', v_row.version,
    'effective', assurance.effective_settings(p_tenant_id, p_legal_entity_id));
  insert into assurance.command_receipts(actor_id, idempotency_key, tenant_id, request_hash, response)
  values (v_uid, p_idempotency_key, p_tenant_id, v_hash, v_response);
  return v_response;
end $$;

-- A9: a risk assessment records the bands it was rated with, and the rating is
-- checked against them (rows without recorded bands were rated with the
-- defaults the original check enforced).
alter table assurance.risk_assessments add column rating_bands jsonb;
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'assurance.risk_assessments'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) like '%(likelihood * impact) >= 20%' loop
    execute format('alter table assurance.risk_assessments drop constraint %I', c.conname);
  end loop;
end $$;
alter table assurance.risk_assessments add constraint risk_assessments_rating_check check (
  rating = case when likelihood * impact >= coalesce((rating_bands->>'critical')::integer, 20) then 'critical'
                when likelihood * impact >= coalesce((rating_bands->>'high')::integer, 10) then 'high'
                when likelihood * impact >= coalesce((rating_bands->>'medium')::integer, 5) then 'medium'
                else 'low' end);

-- Plans: the terminal status superseded and the revision link.
alter table assurance.plans add column supersedes_plan_id uuid references assurance.plans(id);
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'assurance.plans'::regclass and contype = 'c'
              and (pg_get_constraintdef(oid) like '%status = ANY%'
                   or pg_get_constraintdef(oid) like '%status = ''approved''::text%') loop
    execute format('alter table assurance.plans drop constraint %I', c.conname);
  end loop;
end $$;
alter table assurance.plans add constraint plans_status_check
  check (status in ('draft','submitted','approved','cancelled','superseded'));
alter table assurance.plans add constraint plans_approval_digest_check
  check ((status in ('approved','superseded')) = (approved_digest is not null));
create index assurance_plans_supersedes_idx on assurance.plans(supersedes_plan_id);
create unique index assurance_plans_open_revision_idx on assurance.plans(supersedes_plan_id)
  where status in ('draft','submitted');

-- A9: an approved plan changes only once more, to superseded.
create or replace function assurance.plan_fixed() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.id, new.tenant_id, new.legal_entity_id, new.branch_id, new.name, new.period_start,
      new.period_end, new.created_by, new.created_at, new.supersedes_plan_id)
     is distinct from (old.id, old.tenant_id, old.legal_entity_id, old.branch_id, old.name,
      old.period_start, old.period_end, old.created_by, old.created_at, old.supersedes_plan_id)
     or (old.approved_digest is not null
         and ((new.approved_digest, new.approved_by, new.approved_at)
              is distinct from (old.approved_digest, old.approved_by, old.approved_at)
              or (new.status is distinct from old.status
                  and not (old.status = 'approved' and new.status = 'superseded')))) then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;

create or replace function assurance.plan_action_permission(p_action text)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_action in ('register_item','assess_risk','retire_item','create_template','create_plan',
      'add_plan_item','remove_plan_item','submit_plan','decide_plan','cancel_plan',
      'supersede_plan') then 'assurance.plan.manage'  -- A9: supersede_plan
    when p_action = 'instantiate_engagement' then 'assurance.engagement.manage'
  end;
$$;

create or replace function assurance.plan_action_fields(p_action text)
returns text[] language sql immutable set search_path = '' as $$
  select array['action'] || case p_action
    when 'register_item' then array['item_id','code','name','category','owner_id']
    when 'assess_risk' then array['item_id','assessment_id','likelihood','impact','rationale']
    when 'retire_item' then array['item_id','reason']
    when 'create_template' then array['template_id','code','name','controls','requests']
    when 'create_plan' then array['plan_id','name','period_start','period_end']
    when 'add_plan_item' then array['plan_id','plan_item_id','item_id','frequency','template_id',
      'lead_auditor_id','scope_summary']
    when 'remove_plan_item' then array['plan_id','plan_item_id','reason']
    when 'submit_plan' then array['plan_id']
    when 'decide_plan' then array['plan_id','decision','reason']
    when 'cancel_plan' then array['plan_id','reason']
    when 'instantiate_engagement' then array['plan_id','plan_item_id','occurrence','engagement_id']
    when 'supersede_plan' then array['plan_id','supersedes_plan_id','name']  -- A9
    else null end;
$$;

-- A9: copied from 20261018155041_assurance_workspace.sql (work_items, overview); levels and
-- the response deadline read the effective settings.
create or replace function assurance.work_items(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid)
returns table (engagement_id uuid, engagement_name text, engagement_version bigint, kind text,
  item_id uuid, title text, owner_id uuid, status text, due_date date, level text)
language sql stable set search_path = '' as $$
  select e.id, e.name, e.version, 'evidence_request', r.id, left(r.description, 160), r.owner_id,
         r.status, r.due_date, assurance.reminder_level(p_tenant_id, p_legal_entity_id, r.due_date, current_date)
    from assurance.engagements e join assurance.evidence_requests r on r.engagement_id = e.id
   where e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
     and e.branch_id is not distinct from p_branch_id
     and e.status in ('planning','fieldwork') and r.status = 'open'
  union all
  select e.id, e.name, e.version, 'finding', f.id, f.title, f.owner_id, f.status,
         case when f.status = 'issued' then (f.issued_at at time zone 'UTC')::date + assurance.response_days(p_tenant_id, p_legal_entity_id)
              else f.response_due end,
         assurance.reminder_level(p_tenant_id, p_legal_entity_id, case when f.status = 'issued'
           then (f.issued_at at time zone 'UTC')::date + assurance.response_days(p_tenant_id, p_legal_entity_id) else f.response_due end,
           current_date)
    from assurance.engagements e join assurance.findings f on f.engagement_id = e.id
   where e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
     and e.branch_id is not distinct from p_branch_id
     and e.status not in ('archived','cancelled') and f.status in ('issued','remediating');
$$;

create or replace function api.assurance_overview(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_mine jsonb;
  v_team jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  select coalesce(jsonb_agg(to_jsonb(w) order by w.due_date, w.item_id), '[]'::jsonb) into v_mine
    from (select * from assurance.work_items(p_tenant_id, p_legal_entity_id, p_branch_id) w
           where w.owner_id = v_uid order by w.due_date, w.item_id limit 100) w;
  select coalesce(jsonb_agg(to_jsonb(w) order by w.due_date, w.item_id), '[]'::jsonb) into v_team
    from (select * from assurance.work_items(p_tenant_id, p_legal_entity_id, p_branch_id) w
           where w.owner_id <> v_uid and w.level in ('overdue','escalated')
             and assurance.team_role(w.engagement_id, v_uid) in ('lead','auditor')
           order by w.due_date, w.item_id limit 100) w;
  return jsonb_build_object('as_of', current_date, 'response_sla_days', assurance.response_days(p_tenant_id, p_legal_entity_id),  -- A9
    'reminder_bands', (select jsonb_build_object('due_soon_days', (x.s->>'due_soon_days')::integer,
      'escalate_after_days', (x.s->>'escalate_after_days')::integer)
      from (select assurance.effective_settings(p_tenant_id, p_legal_entity_id) s) x),
    'mine', v_mine, 'team', v_team,
    'counts', jsonb_build_object(
      'due_soon', (select count(*) from jsonb_array_elements(v_mine || v_team) i where i->>'level' = 'due_soon'),
      'overdue', (select count(*) from jsonb_array_elements(v_mine || v_team) i where i->>'level' = 'overdue'),
      'escalated', (select count(*) from jsonb_array_elements(v_mine || v_team) i where i->>'level' = 'escalated')));
end $$;

-- A9: copied from 20261018154450_assurance_adapters_monitoring.sql; monitoring reads the
-- effective thresholds.
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
    for v_rule in select * from assurance.monitoring_rules(v_snap.kind, v_snap.content, assurance.effective_settings(p_tenant_id, p_legal_entity_id)->'monitoring') /* A9 */ loop
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

-- A9: copied from 20261019090000_assurance_version_guard.sql; settings-aware rating and
-- supersede_plan.
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
  if v_action in ('register_item','create_template','create_plan','supersede_plan') and p_expected_version is distinct from 0 then
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
      v_text := assurance.risk_rating_for(p_tenant_id, p_legal_entity_id, v_l * v_i);  -- A9
      v_uuid := assurance.uuid_field(p_payload, 'assessment_id');
      insert into assurance.risk_assessments(id, universe_item_id, likelihood, impact, rating, rationale, assessed_by,
        rating_bands)  -- A9: the bands used
      values (v_uuid, v_item.id, v_l, v_i, v_text, assurance.text_field(p_payload, 'rationale', 3, 2000), v_uid,
        assurance.effective_settings(p_tenant_id, p_legal_entity_id)->'rating_bands');
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

  -- A9: revise an approved plan through a superseding draft (a creation, version 0).
  when 'supersede_plan' then
    v_agg_type := 'plan';
    v_agg_id := assurance.uuid_field(p_payload, 'plan_id');
    if exists (select 1 from assurance.plans where id = v_agg_id) then
      raise exception using errcode = '23505', message = 'ASSURANCE_PLAN_EXISTS';
    end if;
    select * into v_plan from assurance.plans
     where id = assurance.uuid_field(p_payload, 'supersedes_plan_id') and tenant_id = p_tenant_id
       and legal_entity_id = p_legal_entity_id and branch_id is not distinct from p_branch_id
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_PLAN_NOT_FOUND';
    end if;
    if v_plan.status <> 'approved' then
      perform assurance.state_error('ASSURANCE_PLAN_NOT_APPROVED');
    end if;
    if exists (select 1 from assurance.plans
                where supersedes_plan_id = v_plan.id and status in ('draft','submitted')) then
      raise exception using errcode = '23505', message = 'ASSURANCE_PLAN_REVISION_OPEN';
    end if;
    insert into assurance.plans(id, tenant_id, legal_entity_id, branch_id, name, period_start, period_end,
      created_by, supersedes_plan_id)
    values (v_agg_id, p_tenant_id, p_legal_entity_id, p_branch_id,
      assurance.text_field(p_payload, 'name', 3, 160), v_plan.period_start, v_plan.period_end, v_uid, v_plan.id);
    insert into assurance.plan_items(id, plan_id, universe_item_id, assessment_id, rating, frequency,
      template_id, lead_auditor_id, scope_summary, added_by)
    select gen_random_uuid(), v_agg_id, i.universe_item_id, i.assessment_id, i.rating, i.frequency,
           i.template_id, i.lead_auditor_id, i.scope_summary, v_uid
      from assurance.plan_items i where i.plan_id = v_plan.id and i.status = 'active';
    get diagnostics v_n = row_count;
    v_status := 'draft'; v_to := 'draft';
    v_details := jsonb_build_object('supersedes_plan_id', v_plan.id, 'items', v_n,
      'period_start', v_plan.period_start, 'period_end', v_plan.period_end);

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
        -- A9: approving a revision supersedes the plan it revises, in the same transaction.
        if v_plan.supersedes_plan_id is not null then
          update assurance.plans set status = 'superseded', version = version + 1, updated_at = clock_timestamp()
           where id = v_plan.supersedes_plan_id and status = 'approved'
           returning version into v_k;
          if found then
            insert into assurance.plan_events(tenant_id, aggregate_type, aggregate_id, aggregate_version, action,
              from_status, to_status, actor_id, details)
            values (p_tenant_id, 'plan', v_plan.supersedes_plan_id, v_k, 'supersede_plan', 'approved', 'superseded',
              v_uid, jsonb_build_object('superseded_by', v_plan.id));
          end if;
          v_details := v_details || jsonb_build_object('supersedes_plan_id', v_plan.supersedes_plan_id);
        end if;
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

revoke all on function assurance.default_monitoring() from public, anon, authenticated, service_role;
revoke all on function assurance.effective_settings(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function assurance.reminder_level(uuid, uuid, date, date) from public, anon, authenticated, service_role;
revoke all on function assurance.response_days(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function assurance.risk_rating_for(uuid, uuid, integer) from public, anon, authenticated, service_role;
revoke all on function assurance.monitoring_rules(text, jsonb, jsonb) from public, anon, authenticated, service_role;
revoke all on function assurance.settings_int(jsonb, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function assurance.work_items(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function api.assurance_settings(uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_settings(uuid, uuid, uuid) to authenticated;
revoke all on function api.assurance_settings_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
grant execute on function api.assurance_settings_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
revoke all on function api.assurance_overview(uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_overview(uuid, uuid, uuid) to authenticated;
revoke all on function api.assurance_evidence_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
grant execute on function api.assurance_evidence_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
revoke all on function api.assurance_plan_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
grant execute on function api.assurance_plan_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
