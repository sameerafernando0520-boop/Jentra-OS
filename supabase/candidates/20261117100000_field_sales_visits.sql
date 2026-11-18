-- CANDIDATE ONLY. Not installed on any hosted database. Applies after
-- 20261117090000_field_sales_reps.sql; see
-- docs/development/organization-control-rollout.md.
--
-- Live customer visits (Salesman App blueprint FR-7204). A rep records a visit
-- to a customer it is currently assigned: who (the rep), which customer, why,
-- the outcome and the next action. Location is optional and only taken at a
-- declared action (check in or complete) as two numbers; there is no tracking.
-- A visit is planned, checked in, completed or cancelled through one named
-- rep command with an idempotency key, an expected version and an immutable
-- receipt, like an order request.

insert into core.permissions(code, module, description, privileged) values
  ('sales.field.visits.record', 'sales', 'Plan and record visits to assigned customers.', false);
-- No role or grant is added. The field account allowlists in
-- 20261031090000_field_sales_governance.sql and
-- 20261105102000_organization_identity.sql carry this code, and the legacy
-- receipt guard there lets these visit commands through.

create table field_sales.visits (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  rep_id uuid not null,
  customer_id uuid not null,
  assignment_id uuid not null references field_sales.assignments(id),
  purpose text not null check (length(trim(purpose)) between 1 and 500),
  planned_for date,
  state text not null default 'planned'
    check (state in ('planned', 'checked_in', 'completed', 'cancelled')),
  checked_in_at timestamptz,
  check_in_latitude numeric(9, 6) check (check_in_latitude between -90 and 90),
  check_in_longitude numeric(9, 6) check (check_in_longitude between -180 and 180),
  completed_at timestamptz,
  complete_latitude numeric(9, 6) check (complete_latitude between -90 and 90),
  complete_longitude numeric(9, 6) check (complete_longitude between -180 and 180),
  outcome text check (length(trim(outcome)) between 1 and 2000),
  next_action text check (length(trim(next_action)) between 1 and 1000),
  next_action_due date,
  cancelled_at timestamptz,
  cancel_reason text check (length(trim(cancel_reason)) between 1 and 500),
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  foreign key (tenant_id, rep_id) references field_sales.principals(tenant_id, user_id),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id),
  foreign key (tenant_id, customer_id) references crm.parties(tenant_id, id),
  check ((check_in_latitude is null) = (check_in_longitude is null)),
  check ((complete_latitude is null) = (complete_longitude is null)),
  check (state <> 'planned' or checked_in_at is null),
  check (state not in ('checked_in', 'completed') or checked_in_at is not null),
  check (check_in_latitude is null or checked_in_at is not null),
  check ((state = 'completed') = (completed_at is not null)),
  check ((state = 'completed') = (outcome is not null)),
  check (complete_latitude is null or completed_at is not null),
  check (next_action_due is null or next_action is not null),
  check ((state = 'cancelled') = (cancelled_at is not null and cancel_reason is not null))
);
create index visits_scope on field_sales.visits(tenant_id, legal_entity_id, branch_id, rep_id, id);
alter table field_sales.visits enable row level security;
revoke all on field_sales.visits from public, anon, authenticated, service_role;
-- New tenant table: reinstall the organization lifecycle write guards.
select organization_lifecycle.install_write_guards();

create function field_sales.visit_entity(v field_sales.visits) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'version', v.version::text, 'tenant_id', v.tenant_id,
    'legal_entity_id', v.legal_entity_id, 'branch_id', v.branch_id, 'rep_id', v.rep_id,
    'customer_id', v.customer_id,
    'customer_name', (select coalesce(p.display_name, p.legal_name) from crm.parties as p
                       where p.tenant_id = v.tenant_id and p.id = v.customer_id),
    'purpose', v.purpose, 'planned_for', v.planned_for, 'state', v.state,
    'checked_in_at', v.checked_in_at,
    'check_in_location', case when v.check_in_latitude is not null then jsonb_build_object(
      'latitude', v.check_in_latitude::text, 'longitude', v.check_in_longitude::text) end,
    'completed_at', v.completed_at,
    'complete_location', case when v.complete_latitude is not null then jsonb_build_object(
      'latitude', v.complete_latitude::text, 'longitude', v.complete_longitude::text) end,
    'outcome', v.outcome, 'next_action', v.next_action, 'next_action_due', v.next_action_due,
    'cancelled_at', v.cancelled_at, 'cancel_reason', v.cancel_reason, 'created_at', v.created_at);
$$;

-- A coordinate is a decimal string with up to six places; JSON numbers are refused.
create function field_sales.coordinate(p_value jsonb, p_limit integer) returns numeric
language plpgsql immutable set search_path = '' as $$
declare v numeric;
begin
  if p_value is null or p_value = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') !~ '^-?[0-9]{1,3}([.][0-9]{1,6})?$' then
    raise exception using errcode = '22023', message = 'LOCATION_INVALID';
  end if;
  v := (p_value #>> '{}')::numeric;
  if abs(v) > p_limit then raise exception using errcode = '22023', message = 'LOCATION_INVALID'; end if;
  return v;
end;
$$;

create function field_sales.visit_text(p_value jsonb, p_max integer, p_required boolean) returns text
language plpgsql immutable set search_path = '' as $$
begin
  if p_value is null or p_value = 'null'::jsonb then
    if p_required then raise exception using errcode = '22023', message = 'VISIT_FIELDS_INVALID'; end if;
    return null;
  end if;
  if jsonb_typeof(p_value) <> 'string' or length(trim(p_value #>> '{}')) not between 1 and p_max then
    raise exception using errcode = '22023', message = 'VISIT_FIELDS_INVALID';
  end if;
  return trim(p_value #>> '{}');
end;
$$;

create function api.field_sales_visit_command(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_command_id uuid, p_idempotency_key uuid, p_client_timestamp timestamptz, p_action text, p_payload jsonb,
  p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_name text; v_hash text; v_replay jsonb; v_before jsonb; v_allowed text[];
  v field_sales.visits; a field_sales.assignments; v_lat numeric; v_lon numeric; v_date date;
begin
  perform field_sales.require_rep(p_tenant_id, p_legal_entity_id, p_branch_id, 'sales.field.visits.record');
  v_allowed := case p_action
    when 'plan' then array['id', 'customer_id', 'purpose', 'planned_for']
    when 'check_in' then array['id', 'latitude', 'longitude']
    when 'complete' then array['id', 'outcome', 'next_action', 'next_action_due', 'latitude', 'longitude']
    when 'cancel' then array['id', 'reason'] end;
  if v_allowed is null or p_client_timestamp is null or jsonb_typeof(p_payload) is distinct from 'object'
    or exists (select 1 from jsonb_object_keys(p_payload) as k where k <> all (v_allowed))
    or jsonb_typeof(p_payload->'id') is distinct from 'string' then
    raise exception using errcode = '22023', message = 'VISIT_COMMAND_INVALID';
  end if;
  if (p_action = 'plan') <> (p_expected_entity_version is null) then
    raise exception using errcode = '40001', message = 'VERSION_CONFLICT';
  end if;

  -- The current assignment is checked before any receipt is replayed, so a
  -- revoked portfolio cannot replay even an exact retry.
  if p_action = 'plan' then
    a := field_sales.assignment(p_tenant_id, p_legal_entity_id, p_branch_id,
      (p_payload->>'customer_id')::uuid, auth.uid());
  else
    select * into v from field_sales.visits where id = (p_payload->>'id')::uuid for update;
    if v.id is null or v.tenant_id <> p_tenant_id or v.legal_entity_id <> p_legal_entity_id
      or v.branch_id <> p_branch_id or v.rep_id <> auth.uid() then
      raise exception using errcode = '42501', message = 'VISIT_NOT_FOUND';
    end if;
    a := field_sales.assignment(p_tenant_id, p_legal_entity_id, p_branch_id, v.customer_id, auth.uid());
  end if;

  v_name := 'sales.field.visit.' || p_action;
  v_hash := core.wave3_request_hash(v_name, p_command_id, p_tenant_id, p_legal_entity_id, p_branch_id,
    p_payload, p_expected_entity_version);
  v_replay := core.wave3_replay(p_tenant_id, v_name, p_command_id, p_idempotency_key, v_hash);
  if v_replay is not null then return v_replay; end if;

  if p_action in ('check_in', 'complete') then
    v_lat := field_sales.coordinate(p_payload->'latitude', 90);
    v_lon := field_sales.coordinate(p_payload->'longitude', 180);
    if (v_lat is null) <> (v_lon is null) then
      raise exception using errcode = '22023', message = 'LOCATION_INVALID';
    end if;
  end if;

  if p_action = 'plan' then
    if p_payload ? 'planned_for' and p_payload->'planned_for' <> 'null'::jsonb then
      if jsonb_typeof(p_payload->'planned_for') <> 'string'
        or (p_payload->>'planned_for') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        raise exception using errcode = '22023', message = 'VISIT_FIELDS_INVALID';
      end if;
      v_date := (p_payload->>'planned_for')::date;
    end if;
    begin
      insert into field_sales.visits(id, tenant_id, legal_entity_id, branch_id, rep_id, customer_id,
        assignment_id, purpose, planned_for)
      values ((p_payload->>'id')::uuid, p_tenant_id, p_legal_entity_id, p_branch_id, auth.uid(), a.customer_id,
        a.id, field_sales.visit_text(p_payload->'purpose', 500, true), v_date)
      returning * into v;
    exception when unique_violation then
      raise exception using errcode = '40001', message = 'VERSION_CONFLICT';
    end;
  else
    v_before := field_sales.visit_entity(v);
    perform core.wave3_assert_expected_version(v.version, p_expected_entity_version, v_before);
    if p_action = 'check_in' then
      if v.state <> 'planned' then raise exception using errcode = '55000', message = 'VISIT_STATE_INVALID'; end if;
      update field_sales.visits set state = 'checked_in', checked_in_at = statement_timestamp(),
        check_in_latitude = v_lat, check_in_longitude = v_lon, version = version + 1,
        updated_at = statement_timestamp()
      where id = v.id returning * into v;
    elsif p_action = 'complete' then
      if v.state <> 'checked_in' then raise exception using errcode = '55000', message = 'VISIT_STATE_INVALID'; end if;
      if p_payload ? 'next_action_due' and p_payload->'next_action_due' <> 'null'::jsonb then
        if jsonb_typeof(p_payload->'next_action_due') <> 'string'
          or (p_payload->>'next_action_due') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
          raise exception using errcode = '22023', message = 'VISIT_FIELDS_INVALID';
        end if;
        v_date := (p_payload->>'next_action_due')::date;
      end if;
      update field_sales.visits set state = 'completed', completed_at = statement_timestamp(),
        complete_latitude = v_lat, complete_longitude = v_lon,
        outcome = field_sales.visit_text(p_payload->'outcome', 2000, true),
        next_action = field_sales.visit_text(p_payload->'next_action', 1000, v_date is not null),
        next_action_due = v_date, version = version + 1, updated_at = statement_timestamp()
      where id = v.id returning * into v;
    else
      if v.state not in ('planned', 'checked_in') then
        raise exception using errcode = '55000', message = 'VISIT_STATE_INVALID';
      end if;
      update field_sales.visits set state = 'cancelled', cancelled_at = statement_timestamp(),
        cancel_reason = field_sales.visit_text(p_payload->'reason', 500, true),
        version = version + 1, updated_at = statement_timestamp()
      where id = v.id returning * into v;
    end if;
  end if;
  return core.wave3_finish_command(p_tenant_id, v_name, p_command_id, 'field_visit', v.id,
    p_idempotency_key, v_hash, v_before, field_sales.visit_entity(v), p_legal_entity_id, p_branch_id);
end;
$$;

-- Recovery of a visit command whose response was lost. The customer must
-- still be assigned to the rep.
create function api.field_sales_visit_receipt(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r core.command_receipts; v field_sales.visits;
begin
  perform field_sales.require_rep(p_tenant_id, p_legal_entity_id, p_branch_id, 'sales.field.visits.record');
  select * into r from core.command_receipts where tenant_id = p_tenant_id and actor_id = auth.uid()
    and idempotency_key = p_idempotency_key
    and command_name in ('sales.field.visit.plan', 'sales.field.visit.check_in',
                         'sales.field.visit.complete', 'sales.field.visit.cancel');
  if r.id is null then return jsonb_build_object('state', 'not_found'); end if;
  select * into v from field_sales.visits where id = (r.response->'entity'->>'id')::uuid
    and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id and branch_id = p_branch_id
    and rep_id = auth.uid();
  if v.id is null then raise exception using errcode = '42501', message = 'RECEIPT_SCOPE_INVALID'; end if;
  perform field_sales.assignment(p_tenant_id, p_legal_entity_id, p_branch_id, v.customer_id, auth.uid());
  return jsonb_build_object('state', 'committed', 'receipt', r.response);
end;
$$;

-- The rep's own visits to customers it is currently assigned. A rep never
-- sees another rep's visits.
create function api.field_sales_visits(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_after uuid default null, p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_items jsonb;
begin
  perform field_sales.require_rep(p_tenant_id, p_legal_entity_id, p_branch_id, 'sales.field.visits.record');
  if p_limit is null or p_limit not between 1 and 200 then
    raise exception using errcode = '22023', message = 'PAGE_INVALID';
  end if;
  select coalesce(jsonb_agg(x.item order by x.id), '[]'::jsonb) into v_items from (
    select v.id, field_sales.visit_entity(v) as item from field_sales.visits as v
     where v.tenant_id = p_tenant_id and v.legal_entity_id = p_legal_entity_id and v.branch_id = p_branch_id
       and v.rep_id = auth.uid() and (p_after is null or v.id > p_after)
       and exists (select 1 from field_sales.assignments as a
                    where a.tenant_id = v.tenant_id and a.legal_entity_id = v.legal_entity_id
                      and a.branch_id = v.branch_id and a.customer_id = v.customer_id and a.rep_id = auth.uid()
                      and statement_timestamp() >= a.valid_from and statement_timestamp() < a.valid_until)
     order by v.id limit p_limit + 1) as x;
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(value order by ordinality), '[]'::jsonb)
                from jsonb_array_elements(v_items) with ordinality where ordinality <= p_limit),
    'next_cursor', case when jsonb_array_length(v_items) > p_limit then v_items->(p_limit - 1)->>'id' end,
    'as_of', statement_timestamp());
end;
$$;

-- Company read of the branch's visits in a period of company local dates (the
-- planned date, or the day the visit was recorded). Readers are those of the
-- rep list. Each visit carries the rep's HR-derived label.
create function api.field_sales_company_visits(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_from date, p_to date, p_after uuid default null, p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_permission text; v_zone text; v_items jsonb;
begin
  v_permission := case
    when core.has_permission(p_tenant_id, 'sales.field.portfolios.manage', p_legal_entity_id, p_branch_id)
      then 'sales.field.portfolios.manage'
    else 'sales.field.discounts.decide' end;
  perform field_sales.require_company(p_tenant_id, p_legal_entity_id, p_branch_id, v_permission);
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 366 then
    raise exception using errcode = '22023', message = 'PERIOD_INVALID';
  end if;
  if p_limit is null or p_limit not between 1 and 200 then
    raise exception using errcode = '22023', message = 'PAGE_INVALID';
  end if;
  select le.timezone into v_zone from core.legal_entities as le
   where le.tenant_id = p_tenant_id and le.id = p_legal_entity_id;
  select coalesce(jsonb_agg(x.item order by x.id), '[]'::jsonb) into v_items from (
    select v.id, field_sales.visit_entity(v)
             || jsonb_build_object('rep_label', field_sales.rep_label(v.tenant_id, v.rep_id)) as item
      from field_sales.visits as v
     where v.tenant_id = p_tenant_id and v.legal_entity_id = p_legal_entity_id and v.branch_id = p_branch_id
       and coalesce(v.planned_for, (v.created_at at time zone v_zone)::date) between p_from and p_to
       and (p_after is null or v.id > p_after)
     order by v.id limit p_limit + 1) as x;
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(value order by ordinality), '[]'::jsonb)
                from jsonb_array_elements(v_items) with ordinality where ordinality <= p_limit),
    'next_cursor', case when jsonb_array_length(v_items) > p_limit then v_items->(p_limit - 1)->>'id' end,
    'as_of', statement_timestamp());
end;
$$;

revoke all on function field_sales.visit_entity(field_sales.visits), field_sales.coordinate(jsonb, integer),
  field_sales.visit_text(jsonb, integer, boolean)
  from public, anon, authenticated, service_role;
revoke all on function
  api.field_sales_visit_command(uuid, uuid, uuid, uuid, uuid, timestamptz, text, jsonb, bigint),
  api.field_sales_visit_receipt(uuid, uuid, uuid, uuid),
  api.field_sales_visits(uuid, uuid, uuid, uuid, integer),
  api.field_sales_company_visits(uuid, uuid, uuid, date, date, uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function
  api.field_sales_visit_command(uuid, uuid, uuid, uuid, uuid, timestamptz, text, jsonb, bigint),
  api.field_sales_visit_receipt(uuid, uuid, uuid, uuid),
  api.field_sales_visits(uuid, uuid, uuid, uuid, integer),
  api.field_sales_company_visits(uuid, uuid, uuid, date, date, uuid, integer)
  to authenticated;
