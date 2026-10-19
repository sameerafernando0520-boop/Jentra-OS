-- Corporate Audit & Assurance - candidate slice A2 (blueprint 68).
-- CANDIDATE ONLY. Requires A1 (20261018090000_assurance_engagement_core.sql).
-- Adds test procedures with server-computed samples, immutable test runs,
-- independent test review and governed carry-forward of open findings into a
-- later engagement. A1 objects are not replaced; A2 commands share A1's
-- receipts, engagement version and event history.

alter table assurance.exceptions drop constraint exceptions_source_check;
alter table assurance.exceptions add constraint exceptions_source_check
  check (source in ('manual','continuous_monitoring','carry_forward'));

create unique index assurance_findings_carried_once
  on assurance.findings (carried_from_finding_id) where carried_from_finding_id is not null;

create table assurance.test_procedures (
  id uuid primary key,
  engagement_id uuid not null references assurance.engagements(id),
  control_id uuid not null references assurance.engagement_controls(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{1,39}$'),
  objective text not null check (length(btrim(objective)) between 3 and 2000),
  control_risk text not null check (control_risk in ('low','medium','high','critical')),
  population_size integer not null check (population_size between 1 and 100000000),
  sample_size integer not null check (sample_size between 1 and 60),
  sample_start integer not null,
  sample_positions integer[] not null,
  status text not null default 'designed' check (status in ('designed','executed','reviewed')),
  current_run_id uuid,
  designed_by uuid not null references auth.users(id),
  designed_at timestamptz not null default clock_timestamp(),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  unique (engagement_id, code),
  check (sample_size <= population_size),
  check (sample_start between 1 and population_size),
  check (cardinality(sample_positions) = sample_size),
  check ((status = 'reviewed') = (reviewed_by is not null))
);

create table assurance.test_runs (
  id uuid primary key,
  procedure_id uuid not null references assurance.test_procedures(id),
  items_tested integer not null check (items_tested >= 1),
  exceptions_found integer not null,
  conclusion text not null check (conclusion in ('effective','ineffective')),
  sample_digest text not null check (sample_digest ~ '^[0-9a-f]{64}$'),
  workpaper_sha256 text not null check (workpaper_sha256 ~ '^[0-9a-f]{64}$'),
  performed_by uuid not null references auth.users(id),
  performed_at timestamptz not null default clock_timestamp(),
  check (exceptions_found between 0 and items_tested),
  check (conclusion = 'ineffective' or exceptions_found = 0)
);

create index assurance_procedures_engagement_idx on assurance.test_procedures (engagement_id, status);
create index assurance_runs_procedure_idx on assurance.test_runs (procedure_id);

do $$
declare t text;
begin
  foreach t in array array['test_procedures','test_runs'] loop
    execute format('alter table assurance.%I enable row level security', t);
    execute format('alter table assurance.%I force row level security', t);
    execute format('revoke all on assurance.%I from public, anon, authenticated, service_role', t);
  end loop;
end $$;

create trigger test_runs_immutable before update or delete on assurance.test_runs
  for each row execute function assurance.forbid_mutation();
create trigger test_procedures_no_delete before delete on assurance.test_procedures
  for each row execute function assurance.forbid_mutation();

-- The designed population and sample never change once recorded.
create function assurance.test_design_fixed() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.id, new.engagement_id, new.control_id, new.code, new.objective, new.control_risk,
      new.population_size, new.sample_size, new.sample_start, new.sample_positions,
      new.designed_by, new.designed_at)
     is distinct from (old.id, old.engagement_id, old.control_id, old.code, old.objective,
      old.control_risk, old.population_size, old.sample_size, old.sample_start,
      old.sample_positions, old.designed_by, old.designed_at) then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger test_procedures_design_fixed before update on assurance.test_procedures
  for each row execute function assurance.test_design_fixed();

-- Same table as jentra_domain assuranceSampleSize: capped at population.
create function assurance.sample_size(p_population integer, p_risk text)
returns integer language sql immutable set search_path = '' as $$
  select least(p_population, case p_risk when 'low' then 10 when 'medium' then 25
    when 'high' then 40 when 'critical' then 60 end);
$$;

-- Same as jentra_domain assuranceSystematicSample (1-based, integer arithmetic).
create function assurance.systematic_sample(p_population integer, p_size integer, p_start integer)
returns integer[] language sql immutable set search_path = '' as $$
  select coalesce(array_agg(((p_start - 1 + (i::bigint * p_population / p_size)) % p_population)::integer + 1
    order by i), '{}'::integer[])
  from generate_series(0, p_size - 1) i;
$$;

create function assurance.int_field(p jsonb, k text, lo integer, hi integer) returns integer
language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(jsonb_typeof(p->k), '') <> 'number' or (p->>k) !~ '^(0|[1-9][0-9]{0,8})$'
     or (p->>k)::integer not between lo and hi then
    raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = k;
  end if;
  return (p->>k)::integer;
end $$;

create function assurance.test_action_permission(p_action text)
returns text language sql immutable set search_path = '' as $$
  select case p_action
    when 'design_test' then 'assurance.test.perform'
    when 'execute_test' then 'assurance.test.perform'
    when 'review_test' then 'assurance.test.review'
    when 'carry_forward' then 'assurance.finding.issue'
  end;
$$;

create function assurance.test_action_fields(p_action text)
returns text[] language sql immutable set search_path = '' as $$
  select array['action','engagement_id'] || case p_action
    when 'design_test' then array['procedure_id','control_id','code','objective','population_size','sample_start']
    when 'execute_test' then array['run_id','procedure_id','items_tested','exceptions_found','conclusion','workpaper_sha256']
    when 'review_test' then array['procedure_id','decision','reason']
    when 'carry_forward' then array['finding_id','source_finding_id','exception_id','control_id']
    else null end;
$$;

-- Shared command prelude: payload shape, scope, current authority (before
-- replay), idempotent replay, recent MFA, engagement lock, version, external
-- read-only and closed-engagement checks. Same order as api.assurance_command.
create function assurance.prepare_command(
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
  if o_engagement.version <> p_expected_version then
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

-- Shared completion: one version, one attributable event, one sealed receipt.
create function assurance.complete_command(
  p_tenant_id uuid, p_engagement_id uuid, p_idempotency_key uuid, p_hash text, p_action text,
  p_aggregate_type text, p_aggregate_id uuid, p_from text, p_to text, p_details jsonb
) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_eng assurance.engagements%rowtype;
  v_response jsonb;
begin
  update assurance.engagements set version = version + 1, updated_at = clock_timestamp()
   where id = p_engagement_id returning * into v_eng;
  insert into assurance.events(tenant_id, engagement_id, engagement_version, action, aggregate_type,
    aggregate_id, from_status, to_status, actor_id, details)
  values (p_tenant_id, p_engagement_id, v_eng.version, p_action, p_aggregate_type, p_aggregate_id,
    p_from, p_to, v_uid, p_details);
  v_response := jsonb_build_object('engagement_id', p_engagement_id, 'version', v_eng.version,
    'status', v_eng.status, 'action', p_action, 'aggregate_type', p_aggregate_type,
    'aggregate_id', p_aggregate_id, 'to_status', p_to);
  insert into assurance.command_receipts(actor_id, idempotency_key, tenant_id, request_hash, response)
  values (v_uid, p_idempotency_key, p_tenant_id, p_hash, v_response);
  return v_response;
end $$;

create function api.assurance_test_command(
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
  v_ctl assurance.engagement_controls%rowtype;
  v_proc assurance.test_procedures%rowtype;
  v_run assurance.test_runs%rowtype;
  v_src assurance.findings%rowtype;
  v_src_eng assurance.engagements%rowtype;
  v_pop integer;
  v_size integer;
  v_start integer;
  v_items integer;
  v_found integer;
  v_text text;
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
  v_perm := assurance.test_action_permission(v_action);
  v_fields := assurance.test_action_fields(v_action);
  if v_perm is null or v_fields is null then
    raise exception using errcode = '22023', message = 'ASSURANCE_ACTION_UNKNOWN';
  end if;

  select * into v_prep from assurance.prepare_command(p_tenant_id, p_legal_entity_id, p_branch_id,
    p_idempotency_key, p_payload, p_expected_version, v_perm, v_fields, v_action = 'carry_forward');
  if v_prep.o_replay is not null then
    return v_prep.o_replay;
  end if;
  v_eng := v_prep.o_engagement;
  v_role := v_prep.o_role;

  case v_action
  when 'design_test' then
    if v_eng.status not in ('planning','fieldwork') then
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
    if (p_payload->>'code') is null or (p_payload->>'code') !~ '^[A-Z0-9][A-Z0-9._-]{1,39}$' then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'code';
    end if;
    v_pop := assurance.int_field(p_payload, 'population_size', 1, 100000000);
    v_start := assurance.int_field(p_payload, 'sample_start', 1, v_pop);
    v_size := assurance.sample_size(v_pop, v_ctl.risk);
    insert into assurance.test_procedures(id, engagement_id, control_id, code, objective, control_risk,
      population_size, sample_size, sample_start, sample_positions, designed_by)
    values (assurance.uuid_field(p_payload, 'procedure_id'), v_eng.id, v_ctl.id, p_payload->>'code',
      assurance.text_field(p_payload, 'objective', 3, 2000), v_ctl.risk, v_pop, v_size, v_start,
      assurance.systematic_sample(v_pop, v_size, v_start), v_uid);
    v_agg_type := 'test_procedure'; v_agg_id := (p_payload->>'procedure_id')::uuid; v_to := 'designed';
    v_details := jsonb_build_object('control_id', v_ctl.id, 'control_risk', v_ctl.risk,
      'population_size', v_pop, 'sample_size', v_size, 'sample_start', v_start);

  when 'execute_test' then
    if v_eng.status <> 'fieldwork' then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_eng.evidence_frozen_at is null then
      perform assurance.state_error('ASSURANCE_EVIDENCE_FREEZE_REQUIRED');
    end if;
    if v_role is null or v_role not in ('lead','auditor') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_proc from assurance.test_procedures
     where id = assurance.uuid_field(p_payload, 'procedure_id') and engagement_id = v_eng.id for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_PROCEDURE_NOT_FOUND';
    end if;
    if v_proc.status <> 'designed' then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    v_items := assurance.int_field(p_payload, 'items_tested', 1, 60);
    if v_items <> v_proc.sample_size then
      raise exception using errcode = '22023', message = 'ASSURANCE_SAMPLE_INCOMPLETE';
    end if;
    v_found := assurance.int_field(p_payload, 'exceptions_found', 0, v_items);
    v_text := p_payload->>'conclusion';
    if v_text is null or v_text not in ('effective','ineffective') then
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'conclusion';
    end if;
    if v_text = 'effective' and v_found > 0 then
      raise exception using errcode = '22023', message = 'ASSURANCE_CONCLUSION_INCONSISTENT';
    end if;
    insert into assurance.test_runs(id, procedure_id, items_tested, exceptions_found, conclusion,
      sample_digest, workpaper_sha256, performed_by)
    values (assurance.uuid_field(p_payload, 'run_id'), v_proc.id, v_items, v_found, v_text,
      encode(extensions.digest(array_to_string(v_proc.sample_positions, ','), 'sha256'), 'hex'),
      assurance.digest_field(p_payload, 'workpaper_sha256'), v_uid)
    returning * into v_run;
    update assurance.test_procedures set status = 'executed', current_run_id = v_run.id where id = v_proc.id;
    v_agg_type := 'test_procedure'; v_agg_id := v_proc.id; v_from := 'designed'; v_to := 'executed';
    v_details := jsonb_build_object('run_id', v_run.id, 'items_tested', v_items,
      'exceptions_found', v_found, 'conclusion', v_text, 'sample_digest', v_run.sample_digest,
      'workpaper_sha256', v_run.workpaper_sha256);

  when 'review_test' then
    if v_eng.status not in ('fieldwork','reporting') then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_role is null or v_role not in ('lead','auditor','reviewer') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_proc from assurance.test_procedures
     where id = assurance.uuid_field(p_payload, 'procedure_id') and engagement_id = v_eng.id for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_PROCEDURE_NOT_FOUND';
    end if;
    if v_proc.status <> 'executed' then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    select * into v_run from assurance.test_runs where id = v_proc.current_run_id;
    if v_run.performed_by = v_uid or v_proc.designed_by = v_uid then
      perform assurance.deny('ASSURANCE_INDEPENDENT_REVIEW_REQUIRED');
    end if;
    v_text := p_payload->>'decision';
    if v_text = 'accept' then
      update assurance.test_procedures set status = 'reviewed', reviewed_by = v_uid,
        reviewed_at = clock_timestamp() where id = v_proc.id;
      v_to := 'reviewed';
    elsif v_text = 'return' then
      update assurance.test_procedures set status = 'designed', current_run_id = null where id = v_proc.id;
      v_to := 'designed';
    else
      raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'decision';
    end if;
    v_agg_type := 'test_procedure'; v_agg_id := v_proc.id; v_from := 'executed';
    v_details := jsonb_build_object('run_id', v_run.id, 'decision', v_text,
      'reason', assurance.text_field(p_payload, 'reason', 3, 1000));

  when 'carry_forward' then
    if v_eng.status not in ('planning','fieldwork') then
      perform assurance.state_error('ASSURANCE_TRANSITION_INVALID');
    end if;
    if v_role is null or v_role not in ('lead','auditor','reviewer') then
      perform assurance.deny('ASSURANCE_TEAM_MEMBER_REQUIRED');
    end if;
    select * into v_ctl from assurance.engagement_controls
     where id = assurance.uuid_field(p_payload, 'control_id') and engagement_id = v_eng.id;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_CONTROL_NOT_FOUND';
    end if;
    -- The source must be in the same tenant, entity and branch scope.
    select f.* into v_src from assurance.findings f join assurance.engagements s on s.id = f.engagement_id
     where f.id = assurance.uuid_field(p_payload, 'source_finding_id')
       and s.tenant_id = p_tenant_id and s.legal_entity_id = p_legal_entity_id
       and s.branch_id is not distinct from p_branch_id
     for update of f;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_FINDING_NOT_FOUND';
    end if;
    select * into v_src_eng from assurance.engagements where id = v_src.engagement_id;
    if v_src_eng.id = v_eng.id or v_src_eng.status not in ('issued','archived') then
      perform assurance.state_error('ASSURANCE_SOURCE_NOT_ISSUED');
    end if;
    if v_src.status in ('closed','risk_accepted') then
      perform assurance.state_error('ASSURANCE_FINDING_NOT_OPEN');
    end if;
    if exists (select 1 from assurance.findings where carried_from_finding_id = v_src.id) then
      raise exception using errcode = '23505', message = 'ASSURANCE_ALREADY_CARRIED';
    end if;
    if exists (select 1 from assurance.engagement_team where engagement_id = v_eng.id and user_id = v_src.owner_id) then
      perform assurance.deny('ASSURANCE_INDEPENDENCE_REQUIRED');
    end if;
    insert into assurance.exceptions(id, engagement_id, control_id, description, severity, status, source, recorded_by)
    values (assurance.uuid_field(p_payload, 'exception_id'), v_eng.id, v_ctl.id,
      left('Carried forward: ' || v_src.title, 4000), v_src.severity, 'promoted', 'carry_forward', v_uid);
    insert into assurance.findings(id, engagement_id, exception_id, title, severity, owner_id,
      carried_from_finding_id, issued_by)
    values (assurance.uuid_field(p_payload, 'finding_id'), v_eng.id, (p_payload->>'exception_id')::uuid,
      v_src.title, v_src.severity, v_src.owner_id, v_src.id, v_uid);
    v_agg_type := 'finding'; v_agg_id := (p_payload->>'finding_id')::uuid; v_to := 'issued';
    v_details := jsonb_build_object('source_finding_id', v_src.id, 'source_engagement_id', v_src_eng.id,
      'source_status', v_src.status, 'severity', v_src.severity, 'owner_id', v_src.owner_id);
  end case;

  return assurance.complete_command(p_tenant_id, v_eng.id, p_idempotency_key, v_prep.o_hash,
    v_action, v_agg_type, v_agg_id, v_from, v_to, v_details);
end $$;

-- Read model for test work (same authority rules as api.assurance_engagement).
create function api.assurance_tests(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_engagement_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if exists (select 1 from assurance.engagement_team
              where engagement_id = p_engagement_id and user_id = v_uid and role = 'external') then
    if assurance.team_role(p_engagement_id, v_uid) is distinct from 'external'
       or not core.has_permission(p_tenant_id, 'assurance.external_review', p_legal_entity_id, p_branch_id) then
      perform assurance.deny('ASSURANCE_EXTERNAL_ACCESS_EXPIRED');
    end if;
  else
    perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  end if;
  if not exists (select 1 from assurance.engagements
                  where id = p_engagement_id and tenant_id = p_tenant_id
                    and legal_entity_id = p_legal_entity_id and branch_id is not distinct from p_branch_id) then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_ENGAGEMENT_NOT_FOUND';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'control_id', t.control_id,
      'code', t.code, 'control_risk', t.control_risk, 'population_size', t.population_size,
      'sample_size', t.sample_size, 'sample_start', t.sample_start, 'sample_positions', t.sample_positions,
      'status', t.status, 'reviewed_by', t.reviewed_by,
      'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'items_tested', r.items_tested,
        'exceptions_found', r.exceptions_found, 'conclusion', r.conclusion,
        'sample_digest', r.sample_digest, 'workpaper_sha256', r.workpaper_sha256,
        'performed_by', r.performed_by, 'performed_at', r.performed_at) order by r.performed_at, r.id)
        from assurance.test_runs r where r.procedure_id = t.id), '[]'::jsonb)) order by t.code)
    from assurance.test_procedures t where t.engagement_id = p_engagement_id), '[]'::jsonb);
end $$;

revoke all on all functions in schema assurance from public, anon, authenticated, service_role;
revoke all on function api.assurance_test_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
revoke all on function api.assurance_tests(uuid, uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_test_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
grant execute on function api.assurance_tests(uuid, uuid, uuid, uuid) to authenticated;
