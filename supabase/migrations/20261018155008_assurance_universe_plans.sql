-- Corporate Audit & Assurance A3: audit universe, risk assessment, maker-checker
-- audit plans, engagement templates and recurring engagements (blueprint 68,
-- FR-6801, FR-6802, FR-6823 templates/recurrence).
--
-- CANDIDATE ONLY. Installs after A1, A2, A4 and A4b. Reuses the A1 helpers,
-- command receipts and forced-RLS API-only pattern. Universe items, plans and
-- templates have their own ordered history in assurance.plan_events; an
-- engagement instantiated from an approved plan starts its own A1 history at
-- version 1 and is then driven by the existing engagement commands.

create table assurance.universe_items (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{1,39}$'),
  name text not null check (length(btrim(name)) between 3 and 160),
  category text not null check (category in ('process','entity','system','compliance','project')),
  owner_id uuid not null references auth.users(id),
  status text not null default 'active' check (status in ('active','retired')),
  current_assessment_id uuid,
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id)
);

create table assurance.risk_assessments (
  id uuid primary key,
  universe_item_id uuid not null references assurance.universe_items(id),
  likelihood integer not null check (likelihood between 1 and 5),
  impact integer not null check (impact between 1 and 5),
  score integer generated always as (likelihood * impact) stored,
  rating text not null,
  rationale text not null check (length(btrim(rationale)) between 3 and 2000),
  assessed_by uuid not null references auth.users(id),
  assessed_at timestamptz not null default clock_timestamp(),
  check (rating = case when likelihood * impact >= 20 then 'critical'
                       when likelihood * impact >= 10 then 'high'
                       when likelihood * impact >= 5 then 'medium' else 'low' end)
);

alter table assurance.universe_items add constraint universe_items_current_assessment_fk
  foreign key (current_assessment_id) references assurance.risk_assessments(id);

create table assurance.templates (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{1,39}$'),
  version integer not null check (version > 0),
  name text not null check (length(btrim(name)) between 3 and 160),
  controls jsonb not null,
  requests jsonb not null,
  digest text not null check (digest ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id)
);

create table assurance.plans (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid,
  name text not null check (length(btrim(name)) between 3 and 160),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','submitted','approved','cancelled')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  approved_digest text check (approved_digest ~ '^[0-9a-f]{64}$'),
  check (period_end >= period_start),
  check ((submitted_by is null) = (submitted_at is null)),
  check ((status = 'approved') = (approved_digest is not null)),
  check ((approved_by is null) = (approved_digest is null) and (approved_at is null) = (approved_digest is null)),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id)
);

create table assurance.plan_items (
  id uuid primary key,
  plan_id uuid not null references assurance.plans(id),
  universe_item_id uuid not null references assurance.universe_items(id),
  assessment_id uuid not null references assurance.risk_assessments(id),
  rating text not null check (rating in ('low','medium','high','critical')),
  frequency text not null check (frequency in ('once','semiannual','quarterly','monthly')),
  template_id uuid references assurance.templates(id),
  lead_auditor_id uuid not null references auth.users(id),
  scope_summary text not null check (length(btrim(scope_summary)) between 3 and 2000),
  status text not null default 'active' check (status in ('active','removed')),
  added_by uuid not null references auth.users(id),
  added_at timestamptz not null default clock_timestamp()
);

create table assurance.plan_occurrences (
  plan_item_id uuid not null references assurance.plan_items(id),
  occurrence integer not null check (occurrence between 1 and 12),
  period_start date not null,
  period_end date not null,
  engagement_id uuid not null unique references assurance.engagements(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  primary key (plan_item_id, occurrence),
  check (period_end >= period_start)
);

create table assurance.plan_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  aggregate_type text not null check (aggregate_type in ('universe_item','plan','template')),
  aggregate_id uuid not null,
  aggregate_version bigint not null check (aggregate_version > 0),
  action text not null,
  from_status text,
  to_status text,
  actor_id uuid not null references auth.users(id),
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (aggregate_type, aggregate_id, aggregate_version)
);

create unique index assurance_universe_code_idx on assurance.universe_items
  (tenant_id, legal_entity_id, coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid), code);
create unique index assurance_template_version_idx on assurance.templates
  (tenant_id, legal_entity_id, coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid), code, version);
create unique index assurance_plan_item_active_idx on assurance.plan_items (plan_id, universe_item_id)
  where status = 'active';
create index assurance_plans_scope_idx on assurance.plans (tenant_id, legal_entity_id, branch_id, status);
create index assurance_assessments_item_idx on assurance.risk_assessments (universe_item_id, assessed_at);
create index assurance_plan_events_aggregate_idx on assurance.plan_events (aggregate_type, aggregate_id, aggregate_version);

do $$
declare t text;
begin
  foreach t in array array['universe_items','risk_assessments','templates','plans','plan_items',
    'plan_occurrences','plan_events'] loop
    execute format('alter table assurance.%I enable row level security', t);
    execute format('alter table assurance.%I force row level security', t);
    execute format('revoke all on assurance.%I from public, anon, authenticated, service_role', t);
  end loop;
  foreach t in array array['risk_assessments','templates','plan_occurrences','plan_events'] loop
    execute format('create trigger %I before update or delete on assurance.%I
      for each row execute function assurance.forbid_mutation()', t || '_immutable', t);
  end loop;
  foreach t in array array['universe_items','plans','plan_items'] loop
    execute format('create trigger %I before delete on assurance.%I
      for each row execute function assurance.forbid_mutation()', t || '_no_delete', t);
  end loop;
end $$;

create function assurance.universe_item_fixed() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.id, new.tenant_id, new.legal_entity_id, new.branch_id, new.code, new.owner_id,
      new.created_by, new.created_at)
     is distinct from (old.id, old.tenant_id, old.legal_entity_id, old.branch_id, old.code,
      old.owner_id, old.created_by, old.created_at)
     or (old.status = 'retired' and new.status <> 'retired') then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger universe_items_fixed before update on assurance.universe_items
  for each row execute function assurance.universe_item_fixed();

create function assurance.plan_fixed() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.id, new.tenant_id, new.legal_entity_id, new.branch_id, new.name, new.period_start,
      new.period_end, new.created_by, new.created_at)
     is distinct from (old.id, old.tenant_id, old.legal_entity_id, old.branch_id, old.name,
      old.period_start, old.period_end, old.created_by, old.created_at)
     or (old.approved_digest is not null
         and (new.status, new.approved_digest, new.approved_by, new.approved_at)
             is distinct from (old.status, old.approved_digest, old.approved_by, old.approved_at)) then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger plans_fixed before update on assurance.plans
  for each row execute function assurance.plan_fixed();

create function assurance.plan_item_fixed() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.id, new.plan_id, new.universe_item_id, new.assessment_id, new.rating, new.frequency,
      new.template_id, new.lead_auditor_id, new.scope_summary, new.added_by, new.added_at)
     is distinct from (old.id, old.plan_id, old.universe_item_id, old.assessment_id, old.rating,
      old.frequency, old.template_id, old.lead_auditor_id, old.scope_summary, old.added_by, old.added_at)
     or old.status <> 'active' then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger plan_items_fixed before update on assurance.plan_items
  for each row execute function assurance.plan_item_fixed();

-- Likelihood x impact (1..25): >= 20 critical, >= 10 high, >= 5 medium, else low.
create function assurance.risk_rating(p_score integer) returns text
language sql immutable set search_path = '' as $$
  select case when p_score >= 20 then 'critical' when p_score >= 10 then 'high'
              when p_score >= 5 then 'medium' else 'low' end;
$$;

create function assurance.frequency_count(p_frequency text) returns integer
language sql immutable set search_path = '' as $$
  select case p_frequency when 'once' then 1 when 'semiannual' then 2
    when 'quarterly' then 4 when 'monthly' then 12 end;
$$;

-- Occurrence k of n splits the plan period into n contiguous parts by day count.
create function assurance.occurrence_period(p_start date, p_end date, p_count integer, p_occurrence integer,
  out o_start date, out o_end date)
language sql immutable set search_path = '' as $$
  select p_start + ((p_occurrence - 1) * (p_end - p_start + 1) / p_count),
         p_start + (p_occurrence * (p_end - p_start + 1) / p_count) - 1;
$$;

create function assurance.template_valid(p_controls jsonb, p_requests jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  e jsonb;
  v_codes text[] := '{}';
begin
  if coalesce(jsonb_typeof(p_controls), '') <> 'array' or coalesce(jsonb_typeof(p_requests), '') <> 'array' then
    return false;
  end if;
  if jsonb_array_length(p_controls) not between 1 and 50 or jsonb_array_length(p_requests) > 100 then
    return false;
  end if;
  for e in select x from jsonb_array_elements(p_controls) x loop
    if jsonb_typeof(e) <> 'object' then
      return false;
    end if;
    if (select array_agg(k order by k) from jsonb_object_keys(e) k) <> array['control_code','risk','title'] then
      return false;
    end if;
    if coalesce(jsonb_typeof(e->'control_code'), '') <> 'string' or coalesce(jsonb_typeof(e->'title'), '') <> 'string'
       or coalesce(jsonb_typeof(e->'risk'), '') <> 'string' then
      return false;
    end if;
    if (e->>'control_code') !~ '^[A-Z0-9][A-Z0-9._-]{1,39}$' or length(btrim(e->>'title')) not between 3 and 160
       or (e->>'risk') not in ('low','medium','high','critical') or (e->>'control_code') = any (v_codes) then
      return false;
    end if;
    v_codes := v_codes || (e->>'control_code');
  end loop;
  for e in select x from jsonb_array_elements(p_requests) x loop
    if jsonb_typeof(e) <> 'object' then
      return false;
    end if;
    if (select array_agg(k order by k) from jsonb_object_keys(e) k) <> array['control_code','description','due_offset_days'] then
      return false;
    end if;
    if coalesce(jsonb_typeof(e->'control_code'), '') <> 'string' or coalesce(jsonb_typeof(e->'description'), '') <> 'string'
       or coalesce(jsonb_typeof(e->'due_offset_days'), '') <> 'number' then
      return false;
    end if;
    if not ((e->>'control_code') = any (v_codes)) or length(btrim(e->>'description')) not between 3 and 2000
       or (e->>'due_offset_days') !~ '^[1-9][0-9]{0,2}$' then
      return false;
    end if;
    if (e->>'due_offset_days')::integer > 365 then
      return false;
    end if;
  end loop;
  return true;
end $$;

create function assurance.plan_digest(p_plan_id uuid) returns text
language sql stable set search_path = '' as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'plan_id', p.id,
    'scope', jsonb_build_array(p.tenant_id, p.legal_entity_id, p.branch_id),
    'period', jsonb_build_array(p.period_start, p.period_end),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'universe_item_id', i.universe_item_id,
        'assessment_id', i.assessment_id, 'rating', i.rating, 'frequency', i.frequency,
        'template_id', i.template_id, 'lead_auditor_id', i.lead_auditor_id,
        'scope_summary', i.scope_summary) order by i.id)
      from assurance.plan_items i where i.plan_id = p.id and i.status = 'active'), '[]'::jsonb))::text,
    'UTF8'), 'sha256'), 'hex')
  from assurance.plans p where p.id = p_plan_id;
$$;

-- Active high/critical areas in the plan's exact scope that the plan does not cover.
create function assurance.plan_uncovered(p_plan_id uuid) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'code', u.code, 'rating', a.rating)
    order by u.code), '[]'::jsonb)
  from assurance.plans p
  join assurance.universe_items u on u.tenant_id = p.tenant_id and u.legal_entity_id = p.legal_entity_id
    and u.branch_id is not distinct from p.branch_id and u.status = 'active'
  join assurance.risk_assessments a on a.id = u.current_assessment_id and a.rating in ('high','critical')
  where p.id = p_plan_id
    and not exists (select 1 from assurance.plan_items i
                     where i.plan_id = p.id and i.universe_item_id = u.id and i.status = 'active');
$$;

create function assurance.plan_action_permission(p_action text)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_action in ('register_item','assess_risk','retire_item','create_template','create_plan',
      'add_plan_item','remove_plan_item','submit_plan','decide_plan','cancel_plan') then 'assurance.plan.manage'
    when p_action = 'instantiate_engagement' then 'assurance.engagement.manage'
  end;
$$;

create function assurance.plan_action_fields(p_action text)
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
    else null end;
$$;

create function api.assurance_plan_command(
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
  if v_action in ('register_item','create_template','create_plan') and p_expected_version <> 0 then
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
    if v_item.version <> p_expected_version then
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
    if v_plan.version <> p_expected_version then
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

-- Planners and evidence viewers read the universe; authority before existence.
create function api.assurance_universe(
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
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'code', u.code, 'name', u.name,
        'category', u.category, 'owner_id', u.owner_id, 'status', u.status, 'version', u.version,
        'assessment', case when a.id is null then null else jsonb_build_object('id', a.id,
          'likelihood', a.likelihood, 'impact', a.impact, 'score', a.score, 'rating', a.rating,
          'assessed_by', a.assessed_by, 'assessed_at', a.assessed_at) end,
        'assessments', (select count(*) from assurance.risk_assessments h where h.universe_item_id = u.id))
        order by u.code)
      from assurance.universe_items u left join assurance.risk_assessments a on a.id = u.current_assessment_id
      where u.tenant_id = p_tenant_id and u.legal_entity_id = p_legal_entity_id
        and u.branch_id is not distinct from p_branch_id), '[]'::jsonb),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code,
        'version', t.version, 'name', t.name, 'digest', t.digest, 'controls', t.controls,
        'requests', t.requests) order by t.code, t.version)
      from assurance.templates t
      where t.tenant_id = p_tenant_id and t.legal_entity_id = p_legal_entity_id
        and t.branch_id is not distinct from p_branch_id), '[]'::jsonb));
end $$;

create function api.assurance_plan(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_plan_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_plan assurance.plans%rowtype;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if not core.has_permission(p_tenant_id, 'assurance.plan.manage', p_legal_entity_id, p_branch_id) then
    perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  end if;
  select * into v_plan from assurance.plans
   where id = p_plan_id and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
     and branch_id is not distinct from p_branch_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_PLAN_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'plan', jsonb_build_object('id', v_plan.id, 'name', v_plan.name, 'status', v_plan.status,
      'version', v_plan.version, 'period_start', v_plan.period_start, 'period_end', v_plan.period_end,
      'created_by', v_plan.created_by, 'submitted_by', v_plan.submitted_by, 'submitted_at', v_plan.submitted_at,
      'approved_by', v_plan.approved_by, 'approved_at', v_plan.approved_at,
      'approved_digest', v_plan.approved_digest),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'universe_item_id', i.universe_item_id,
        'code', u.code, 'name', u.name, 'rating', i.rating, 'frequency', i.frequency,
        'occurrences_planned', assurance.frequency_count(i.frequency), 'template_id', i.template_id,
        'lead_auditor_id', i.lead_auditor_id, 'scope_summary', i.scope_summary, 'status', i.status,
        'occurrences', coalesce((select jsonb_agg(jsonb_build_object('occurrence', o.occurrence,
            'period_start', o.period_start, 'period_end', o.period_end, 'engagement_id', o.engagement_id,
            'engagement_status', g.status) order by o.occurrence)
          from assurance.plan_occurrences o join assurance.engagements g on g.id = o.engagement_id
          where o.plan_item_id = i.id), '[]'::jsonb)) order by u.code, i.id)
      from assurance.plan_items i join assurance.universe_items u on u.id = i.universe_item_id
      where i.plan_id = v_plan.id), '[]'::jsonb),
    'uncovered_high_risk', assurance.plan_uncovered(v_plan.id),
    'events', coalesce((select jsonb_agg(jsonb_build_object('version', e.aggregate_version,
        'action', e.action, 'from_status', e.from_status, 'to_status', e.to_status,
        'actor_id', e.actor_id, 'occurred_at', e.occurred_at) order by e.aggregate_version)
      from assurance.plan_events e where e.aggregate_type = 'plan' and e.aggregate_id = v_plan.id), '[]'::jsonb));
end $$;

revoke all on all functions in schema assurance from public, anon, authenticated, service_role;
revoke all on function api.assurance_plan_command(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
revoke all on function api.assurance_universe(uuid, uuid, uuid) from public, anon, service_role;
revoke all on function api.assurance_plan(uuid, uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_plan_command(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
grant execute on function api.assurance_universe(uuid, uuid, uuid) to authenticated;
grant execute on function api.assurance_plan(uuid, uuid, uuid, uuid) to authenticated;
