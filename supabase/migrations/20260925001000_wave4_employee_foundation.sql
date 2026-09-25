-- W4-01. Candidate migration: employee identity and effective-dated employment.
-- Keep unapplied until rollback tests and compatibility review pass.

insert into core.permissions(code, module, description, privileged) values
('people.employees.view', 'people', 'Read scoped operational employee records.', false),
('people.employees.manage', 'people', 'Create and revise scoped employee identity.', true),
('people.employment.manage', 'people', 'Change dated employment and assignments.', true),
('people.employees.history.view', 'people', 'Read scoped employment events.', true)
on conflict (code) do nothing;

-- Publishing this candidate does not enable People for any plan. Product
-- owners can enable individual plans after the native acceptance gate.
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
select code,'module.people',false from billing.plans
on conflict (plan_code,entitlement_code) do nothing;

-- The existing branch key is tenant/id; a scoped composite FK also proves entity.
alter table core.branches add constraint branches_tenant_entity_id_w4_key
  unique(tenant_id, legal_entity_id, id);

create table people.employees (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
  display_name text not null check(length(btrim(display_name)) between 1 and 160),
  work_email text check(work_email is null or length(work_email) <= 254),
  version bigint not null default 1 check(version between 1 and 9007199254740991),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(tenant_id, legal_entity_id, id),
  unique(tenant_id, legal_entity_id, code),
  foreign key(tenant_id, legal_entity_id)
    references core.legal_entities(tenant_id, id)
);

create table people.employment_spells (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  employee_id uuid not null,
  start_date date not null,
  end_date_exclusive date,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  check(end_date_exclusive is null or end_date_exclusive > start_date),
  unique(tenant_id, legal_entity_id, id),
  unique(tenant_id, legal_entity_id, id, employee_id),
  foreign key(tenant_id, legal_entity_id, employee_id)
    references people.employees(tenant_id, legal_entity_id, id)
);
create unique index employment_one_open_spell_idx
  on people.employment_spells(tenant_id, legal_entity_id, employee_id)
  where end_date_exclusive is null;
create index employment_spells_employee_idx
  on people.employment_spells(tenant_id, legal_entity_id, employee_id, start_date, id);

create table people.employment_assignments (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  employee_id uuid not null,
  spell_id uuid not null,
  branch_id uuid not null,
  start_date date not null,
  end_date_exclusive date,
  job_title text not null check(length(btrim(job_title)) between 1 and 160),
  employment_type text not null check(employment_type in
    ('permanent', 'fixed_term', 'casual', 'contractor')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  check(end_date_exclusive is null or end_date_exclusive > start_date),
  unique(tenant_id, legal_entity_id, id),
  foreign key(tenant_id, legal_entity_id, spell_id, employee_id)
    references people.employment_spells(tenant_id, legal_entity_id, id, employee_id),
  foreign key(tenant_id, branch_id) references core.branches(tenant_id, id),
  foreign key(tenant_id, legal_entity_id, branch_id)
    references core.branches(tenant_id, legal_entity_id, id)
);
create unique index employment_one_open_assignment_idx
  on people.employment_assignments(tenant_id, legal_entity_id, employee_id)
  where end_date_exclusive is null;
create index employment_assignments_scope_date_idx
  on people.employment_assignments(tenant_id, legal_entity_id, branch_id, start_date, end_date_exclusive, employee_id);
create index employment_assignments_employee_idx
  on people.employment_assignments(tenant_id, legal_entity_id, employee_id, start_date, id);

create table people.employment_events (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  employee_id uuid not null,
  branch_id uuid not null,
  source_branch_id uuid not null,
  action text not null check(action in
    ('create', 'identity', 'assignment', 'end', 'rehire', 'correct')),
  effective_date date not null,
  reason text,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  supersedes_event_id uuid,
  command_id uuid not null,
  request_id uuid not null,
  actor_id uuid not null references auth.users(id),
  recorded_at timestamptz not null default clock_timestamp(),
  foreign key(tenant_id, legal_entity_id, employee_id)
    references people.employees(tenant_id, legal_entity_id, id),
  foreign key(tenant_id, legal_entity_id, branch_id)
    references core.branches(tenant_id, legal_entity_id, id),
  foreign key(tenant_id, legal_entity_id, source_branch_id)
    references core.branches(tenant_id, legal_entity_id, id),
  unique(tenant_id, legal_entity_id, id),
  unique(tenant_id, legal_entity_id, command_id),
  foreign key(tenant_id, legal_entity_id, supersedes_event_id)
    references people.employment_events(tenant_id, legal_entity_id, id),
  check(jsonb_typeof(before_state) = 'object' and jsonb_typeof(after_state) = 'object')
);
create index employment_events_scope_idx
  on people.employment_events(tenant_id, legal_entity_id, employee_id, branch_id, recorded_at, id);
create index employment_events_source_scope_idx
  on people.employment_events(tenant_id, legal_entity_id, employee_id, source_branch_id, recorded_at, id);

create function people.reject_event_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception using errcode='55000', message='EMPLOYMENT_EVENT_IMMUTABLE';
end $$;
create trigger employment_events_immutable
before update or delete on people.employment_events
for each row execute function people.reject_event_change();

alter table people.employees enable row level security;
alter table people.employees force row level security;
alter table people.employment_spells enable row level security;
alter table people.employment_spells force row level security;
alter table people.employment_assignments enable row level security;
alter table people.employment_assignments force row level security;
alter table people.employment_events enable row level security;
alter table people.employment_events force row level security;
-- No base-table policy/grant for desktop roles. Scoped API functions are the only access.
revoke all on people.employees, people.employment_spells,
  people.employment_assignments, people.employment_events
  from public, anon, authenticated;

create function people.employee_payload(
  p_employee_id uuid, p_branch_id uuid
) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', e.id, 'tenant_id', e.tenant_id,
    'legal_entity_id', e.legal_entity_id, 'branch_id', p_branch_id,
    'code', e.code, 'display_name', e.display_name,
    'work_email', e.work_email, 'version', e.version,
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'spell_id', a.spell_id, 'branch_id', a.branch_id,
        'start_date', a.start_date, 'end_date_exclusive', a.end_date_exclusive,
        'job_title', a.job_title, 'employment_type', a.employment_type
      ) order by a.start_date, a.id)
      from people.employment_assignments a
      where a.tenant_id=e.tenant_id and a.legal_entity_id=e.legal_entity_id
        and a.employee_id=e.id and a.branch_id=p_branch_id
    ), '[]'::jsonb)
  )
  from people.employees e where e.id=p_employee_id
$$;
revoke all on function people.employee_payload(uuid,uuid) from public, anon, authenticated;

create function people.require_access(
  p_tenant_id uuid, p_entity_id uuid, p_branch_id uuid,
  p_permission text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_branch_id is null or p_entity_id is null or p_tenant_id is null then
    raise exception using errcode='42501',message='Permission denied.';
  end if;
  perform core.wave3_require_scope(p_tenant_id, 'people.view', p_entity_id, p_branch_id);
  perform core.wave3_require_scope(p_tenant_id, p_permission, p_entity_id, p_branch_id);
  if not exists(
    select 1 from billing.tenant_subscriptions s
    join billing.plan_entitlements e on e.plan_code=s.plan_code
    where s.tenant_id=p_tenant_id
      and e.entitlement_code='module.people' and e.enabled
      and ((s.status='trialing' and s.trial_ends_at>now())
        or (s.status='active' and
          (s.current_period_ends_at is null or s.current_period_ends_at>now())))
  ) then
    raise exception using errcode='42501',message='PEOPLE_ENTITLEMENT_REQUIRED';
  end if;
end $$;
revoke all on function people.require_access(uuid,uuid,uuid,text) from public, anon, authenticated;

create function api.people_employee_directory(
  p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_as_of date default null, p_status text default 'employed',
  p_search text default '', p_after uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rows jsonb;
  v_as_of date;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
    'people.employees.view');
  select coalesce(p_as_of,(now() at time zone le.timezone)::date)
    into v_as_of from core.legal_entities le
    where le.tenant_id=p_tenant_id and le.id=p_legal_entity_id;
  if v_as_of is null or p_status is null
     or p_status not in ('employed','future','ended')
     or length(coalesce(p_search,''))>160 then
    raise exception using errcode='22023',message='EMPLOYEE_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(people.employee_payload(q.employee_id,p_branch_id)
      order by q.employee_id),'[]'::jsonb) into v_rows
  from (
    select e.id employee_id
    from people.employees e
    where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id
      and (p_after is null or e.id>p_after)
      and (btrim(coalesce(p_search,''))='' or
        position(lower(btrim(p_search)) in lower(e.code||' '||e.display_name))>0)
      and exists (
        select 1 from people.employment_assignments a
        where a.tenant_id=e.tenant_id and a.legal_entity_id=e.legal_entity_id
          and a.employee_id=e.id and a.branch_id=p_branch_id
          and (case p_status
            when 'employed' then a.start_date<=v_as_of and
              (a.end_date_exclusive is null or a.end_date_exclusive>v_as_of)
            when 'future' then a.start_date>v_as_of
            else exists(select 1 from people.employment_spells s
              where s.tenant_id=e.tenant_id and s.legal_entity_id=e.legal_entity_id
                and s.employee_id=e.id and s.id=a.spell_id
                and s.end_date_exclusive<=v_as_of
                and a.end_date_exclusive=s.end_date_exclusive
                and not exists(select 1 from people.employment_spells newer
                  where newer.tenant_id=e.tenant_id
                    and newer.legal_entity_id=e.legal_entity_id
                    and newer.employee_id=e.id and newer.start_date>s.start_date)) end)
      )
    order by e.id limit 51
  ) q;
  return jsonb_build_object('items',(
      select coalesce(jsonb_agg(x.value),'[]'::jsonb)
      from (select value from jsonb_array_elements(v_rows) with ordinality t(value,ord)
        where ord<=50 order by ord) x),
    'next_cursor', case when jsonb_array_length(v_rows)>50
      then v_rows->49->>'id' else null end,
    'as_of',v_as_of,'status',p_status,'tenant_id',p_tenant_id,
    'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
end $$;

create function api.people_employee_detail(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_employee_id uuid,p_as_of date,p_status text default 'employed'
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
    'people.employees.view');
  if p_as_of is null or p_status is null
     or p_status not in ('employed','future','ended') then
    raise exception using errcode='22023',message='EMPLOYEE_DATE_REQUIRED';
  end if;
  select people.employee_payload(e.id,p_branch_id) into v_result
  from people.employees e
  where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id
    and e.id=p_employee_id and exists(
      select 1 from people.employment_assignments a
      where a.tenant_id=e.tenant_id and a.legal_entity_id=e.legal_entity_id
        and a.employee_id=e.id and a.branch_id=p_branch_id
        and (case p_status
          when 'employed' then a.start_date<=p_as_of and
            (a.end_date_exclusive is null or a.end_date_exclusive>p_as_of)
          when 'future' then a.start_date>p_as_of
          else exists(select 1 from people.employment_spells s
            where s.tenant_id=e.tenant_id and s.legal_entity_id=e.legal_entity_id
              and s.employee_id=e.id and s.id=a.spell_id
              and s.end_date_exclusive<=p_as_of
              and a.end_date_exclusive=s.end_date_exclusive
              and not exists(select 1 from people.employment_spells newer
                where newer.tenant_id=e.tenant_id
                  and newer.legal_entity_id=e.legal_entity_id
                  and newer.employee_id=e.id and newer.start_date>s.start_date)) end));
  if v_result is null then
    raise exception using errcode='42501',message='EMPLOYMENT_SCOPE_INVALID';
  end if;
  return v_result;
end $$;

create function api.people_employee_history(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_employee_id uuid,p_after uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rows jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
    'people.employees.history.view');
  if not exists(select 1 from people.employment_assignments a
    where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
      and a.employee_id=p_employee_id and a.branch_id=p_branch_id) then
    raise exception using errcode='42501',message='EMPLOYMENT_SCOPE_INVALID';
  end if;
  select coalesce(jsonb_agg(to_jsonb(h) order by h.id),'[]'::jsonb) into v_rows
  from (select ev.id,ev.action,ev.effective_date,ev.reason,
      ev.recorded_at,ev.actor_id,ev.supersedes_event_id
    from people.employment_events ev
    where ev.tenant_id=p_tenant_id and ev.legal_entity_id=p_legal_entity_id
      and ev.employee_id=p_employee_id
      and (ev.branch_id=p_branch_id or ev.source_branch_id=p_branch_id)
      and (p_after is null or ev.id>p_after)
    order by ev.id limit 51) h;
  return jsonb_build_object('items',(
    select coalesce(jsonb_agg(x.value),'[]'::jsonb)
    from (select value from jsonb_array_elements(v_rows) with ordinality t(value,ord)
      where ord<=50 order by ord) x),
    'next_cursor',case when jsonb_array_length(v_rows)>50 then v_rows->49->>'id' else null end,
    'employee_id',p_employee_id,'tenant_id',p_tenant_id,
    'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
end $$;

create function api.people_employee_branches(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_search text default ''
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
    'people.employment.manage');
  if length(coalesce(p_search,''))>160 then
    raise exception using errcode='22023',message='EMPLOYEE_SEARCH_INVALID';
  end if;
  return jsonb_build_object('items',(
    select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'code',b.code)
      order by b.name,b.id),'[]'::jsonb)
    from (select b.id,b.name,b.code from core.branches b
      where b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id
        and b.status='active'
        and core.has_permission(p_tenant_id,'people.employment.manage',p_legal_entity_id,b.id)
        and (btrim(coalesce(p_search,''))='' or
          position(lower(btrim(p_search)) in lower(b.code||' '||b.name))>0)
      order by b.name,b.id limit 50) b),
    'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
end $$;

revoke all on function api.people_employee_directory(uuid,uuid,uuid,date,text,text,uuid),
  api.people_employee_detail(uuid,uuid,uuid,uuid,date,text),
  api.people_employee_history(uuid,uuid,uuid,uuid,uuid),
  api.people_employee_branches(uuid,uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function api.people_employee_directory(uuid,uuid,uuid,date,text,text,uuid),
  api.people_employee_detail(uuid,uuid,uuid,uuid,date,text),
  api.people_employee_history(uuid,uuid,uuid,uuid,uuid),
  api.people_employee_branches(uuid,uuid,uuid,text)
  to authenticated;

create function people.assert_timeline(
  p_tenant_id uuid,p_entity_id uuid,p_employee_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare v_bad boolean;
begin
  select exists(
    select 1 from people.employment_spells a
    join people.employment_spells b
      on b.tenant_id=a.tenant_id and b.legal_entity_id=a.legal_entity_id
      and b.employee_id=a.employee_id and b.id>a.id
    where a.tenant_id=p_tenant_id and a.legal_entity_id=p_entity_id
      and a.employee_id=p_employee_id
      and daterange(a.start_date,a.end_date_exclusive,'[)') &&
          daterange(b.start_date,b.end_date_exclusive,'[)')
  ) into v_bad;
  if v_bad then raise exception using errcode='23514',message='EMPLOYMENT_OVERLAP'; end if;
  select exists(
    select 1 from people.employment_assignments a
    join people.employment_assignments b
      on b.tenant_id=a.tenant_id and b.legal_entity_id=a.legal_entity_id
      and b.employee_id=a.employee_id and b.spell_id=a.spell_id and b.id>a.id
    where a.tenant_id=p_tenant_id and a.legal_entity_id=p_entity_id
      and a.employee_id=p_employee_id
      and daterange(a.start_date,a.end_date_exclusive,'[)') &&
          daterange(b.start_date,b.end_date_exclusive,'[)')
  ) into v_bad;
  if v_bad then raise exception using errcode='23514',message='EMPLOYMENT_OVERLAP'; end if;
  select exists(
    select 1 from people.employment_spells s
    left join lateral (
      select min(a.start_date) first_date, max(a.end_date_exclusive) last_date,
        count(*) n, count(*) filter(where a.end_date_exclusive is null) open_n,
        sum(coalesce(a.end_date_exclusive, '9999-12-31'::date)-a.start_date) span_days
      from people.employment_assignments a
      where a.tenant_id=s.tenant_id and a.legal_entity_id=s.legal_entity_id
        and a.employee_id=s.employee_id and a.spell_id=s.id
    ) v on true
    where s.tenant_id=p_tenant_id and s.legal_entity_id=p_entity_id
      and s.employee_id=p_employee_id
      and (v.n=0 or v.first_date<>s.start_date
        or (s.end_date_exclusive is null and
          (v.open_n<>1 or v.span_days<>'9999-12-31'::date-s.start_date))
        or (s.end_date_exclusive is not null and
          (v.open_n<>0 or v.last_date<>s.end_date_exclusive
           or v.span_days<>s.end_date_exclusive-s.start_date)))
  ) into v_bad;
  if v_bad then raise exception using errcode='23514',message='EMPLOYMENT_TIMELINE_INVALID'; end if;
end $$;
revoke all on function people.assert_timeline(uuid,uuid,uuid) from public,anon,authenticated;

create function api.people_employee_command(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
  p_payload jsonb,p_expected_version bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := (select auth.uid());
  v_action text := p_payload->>'action';
  v_id uuid;
  v_request_hash text;
  v_replay jsonb;
  v_employee people.employees%rowtype;
  v_spell people.employment_spells%rowtype;
  v_assignment people.employment_assignments%rowtype;
  v_event people.employment_events%rowtype;
  v_branch uuid;
  v_source_branch uuid;
  v_date date;
  v_today date;
  v_timezone text;
  v_title text;
  v_type text;
  v_reason text;
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
  v_entity jsonb;
  v_request uuid := gen_random_uuid();
  v_event_id uuid := gen_random_uuid();
  v_new_id uuid;
  v_previous uuid;
  v_effective date;
  v_allowed text[];
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object'
     or p_client_timestamp is null or p_command_id is null
     or p_idempotency_key is null or p_payload->>'id' is null
     or (p_payload->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or v_action is null
     or v_action not in ('create','identity','assignment','end','rehire','correct') then
    raise exception using errcode='22023',message='EMPLOYEE_COMMAND_INVALID';
  end if;
  v_id := (p_payload->>'id')::uuid;
  v_allowed := case v_action
    when 'create' then array['action','id','code','display_name','work_email',
      'start_date','job_title','employment_type']
    when 'identity' then array['action','id','display_name','work_email','reason']
    when 'assignment' then array['action','id','effective_date','destination_branch_id',
      'job_title','employment_type','reason']
    when 'end' then array['action','id','spell_id','end_date_exclusive','reason']
    when 'rehire' then array['action','id','start_date','job_title','employment_type','reason']
    else array['action','id','event_id','correction_action','reason'] end;
  if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(v_allowed)) then
    raise exception using errcode='22023',message='EMPLOYEE_COMMAND_FIELDS_INVALID';
  end if;
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
    case when v_action in ('create','identity') then 'people.employees.manage'
      else 'people.employment.manage' end);
  select le.timezone into v_timezone from core.legal_entities le
    where le.tenant_id=p_tenant_id and le.id=p_legal_entity_id and le.status='active';
  if v_timezone is null then
    raise exception using errcode='42501',message='EMPLOYMENT_SCOPE_INVALID';
  end if;
  -- Replays cannot bypass a destination permission removed since confirmation.
  if v_action='assignment' then
    perform people.require_access(p_tenant_id,p_legal_entity_id,
      (p_payload->>'destination_branch_id')::uuid,'people.employment.manage');
  elsif v_action='correct' then
    select ev.branch_id,ev.source_branch_id into v_branch,v_source_branch
      from people.employment_events ev
      where ev.tenant_id=p_tenant_id and ev.legal_entity_id=p_legal_entity_id
        and ev.employee_id=v_id and ev.id=(p_payload->>'event_id')::uuid;
    if found then
      perform people.require_access(p_tenant_id,p_legal_entity_id,v_branch,
        'people.employment.manage');
      perform people.require_access(p_tenant_id,p_legal_entity_id,v_source_branch,
        'people.employment.manage');
    end if;
  end if;
  v_today := (now() at time zone v_timezone)::date;
  v_request_hash := core.wave3_request_hash('people.employee.'||v_action,
    p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
  v_replay := core.wave3_replay(p_tenant_id,'people.employee.'||v_action,
    p_command_id,p_idempotency_key,v_request_hash);
  if v_replay is not null then
    -- The permission check above applies again before any old response is revealed.
    return v_replay;
  end if;
  v_reason := nullif(btrim(p_payload->>'reason'),'');
  if v_action<>'create' and (v_reason is null or length(v_reason)>1000) then
    raise exception using errcode='22023',message='EMPLOYEE_REASON_REQUIRED';
  end if;
  if v_action in ('create','identity') and (
      p_payload->>'display_name' is null
      or length(btrim(p_payload->>'display_name')) not between 1 and 160
      or (p_payload ? 'work_email' and nullif(p_payload->>'work_email','') is not null
        and (length(p_payload->>'work_email')>254
          or p_payload->>'work_email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
    ) then raise exception using errcode='22023',message='EMPLOYEE_IDENTITY_INVALID';
  end if;
  if v_action in ('create','assignment','rehire') then
    v_title := btrim(p_payload->>'job_title');
    v_type := p_payload->>'employment_type';
    if v_title is null or length(v_title) not between 1 and 160
       or v_type is null
       or v_type not in ('permanent','fixed_term','casual','contractor') then
      raise exception using errcode='22023',message='EMPLOYEE_ASSIGNMENT_INVALID';
    end if;
  end if;
  if v_action='create' then
    if p_expected_version<>0 or p_expected_version is null then
      raise exception using errcode='40001',message='VERSION_CONFLICT';
    end if;
    if (p_payload->>'code') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' then
      raise exception using errcode='22023',message='EMPLOYEE_CODE_INVALID';
    end if;
    v_date := (p_payload->>'start_date')::date;
    if v_date is null then
      raise exception using errcode='22023',message='EMPLOYMENT_DATE_INVALID';
    end if;
    insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,
      work_email,created_by,updated_by)
    values(v_id,p_tenant_id,p_legal_entity_id,p_payload->>'code',
      btrim(p_payload->>'display_name'),nullif(btrim(p_payload->>'work_email'),''),
      v_actor,v_actor);
    v_new_id:=gen_random_uuid();
    insert into people.employment_spells(id,tenant_id,legal_entity_id,employee_id,
      start_date,created_by)
    values(v_new_id,p_tenant_id,p_legal_entity_id,v_id,v_date,v_actor);
    insert into people.employment_assignments(id,tenant_id,legal_entity_id,employee_id,
      spell_id,branch_id,start_date,job_title,employment_type,created_by)
    values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,v_id,v_new_id,
      p_branch_id,v_date,v_title,v_type,v_actor);
    v_branch:=p_branch_id;
    v_source_branch:=p_branch_id;
    v_effective:=v_date;
    v_after:=jsonb_build_object('code',p_payload->>'code','start_date',v_date);
  else
    select * into v_employee from people.employees e
      where e.id=v_id and e.tenant_id=p_tenant_id
        and e.legal_entity_id=p_legal_entity_id for update;
    if not found then
      raise exception using errcode='42501',message='EMPLOYMENT_SCOPE_INVALID';
    end if;
    perform core.wave3_assert_expected_version(v_employee.version,p_expected_version,
      jsonb_build_object('version',v_employee.version));
    if v_action not in ('rehire','correct') then
      select * into v_assignment from people.employment_assignments a
        where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
          and a.employee_id=v_id and a.branch_id=p_branch_id
          and a.end_date_exclusive is null
        order by a.start_date desc limit 1 for update;
      if not found then
        if v_action='assignment' and exists(
          select 1 from people.employment_assignments a
          where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
            and a.employee_id=v_id and a.branch_id=p_branch_id
            and a.end_date_exclusive>v_today)
          and exists(
          select 1 from people.employment_assignments a
          where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
            and a.employee_id=v_id and a.start_date>v_today) then
          raise exception using errcode='55000',
            message='EMPLOYMENT_FUTURE_EVENT_EXISTS';
        end if;
        raise exception using errcode='42501',message='EMPLOYMENT_SCOPE_INVALID';
      end if;
    elsif not exists(select 1 from people.employment_assignments a
      where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
        and a.employee_id=v_id and a.branch_id=p_branch_id) then
      raise exception using errcode='42501',message='EMPLOYMENT_SCOPE_INVALID';
    end if;
    v_branch:=p_branch_id;
    v_source_branch:=p_branch_id;
    v_effective:=v_today;
    v_before:=jsonb_build_object('version',v_employee.version,'code',v_employee.code);
    if v_action='identity' then
      update people.employees set display_name=btrim(p_payload->>'display_name'),
        work_email=nullif(btrim(p_payload->>'work_email'),''),
        version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
        where id=v_id;
    elsif v_action='assignment' then
      v_date:=(p_payload->>'effective_date')::date;
      v_branch:=(p_payload->>'destination_branch_id')::uuid;
      v_source_branch:=v_assignment.branch_id;
      perform people.require_access(p_tenant_id,p_legal_entity_id,v_branch,
        'people.employment.manage');
      if v_date is null or v_date<=v_today
         or v_assignment.start_date>=v_date then
        raise exception using errcode='22023',message='EMPLOYMENT_CORRECTION_REQUIRED';
      end if;
      if exists(select 1 from people.employment_assignments a
        where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
          and a.employee_id=v_id and a.start_date>v_today
          and a.id<>v_assignment.id) then
        raise exception using errcode='55000',message='EMPLOYMENT_FUTURE_EVENT_EXISTS';
      end if;
      v_previous:=v_assignment.id;
      v_new_id:=gen_random_uuid();
      update people.employment_assignments set end_date_exclusive=v_date
        where id=v_previous;
      insert into people.employment_assignments(id,tenant_id,legal_entity_id,
        employee_id,spell_id,branch_id,start_date,job_title,employment_type,created_by)
      values(v_new_id,p_tenant_id,p_legal_entity_id,v_id,v_assignment.spell_id,
        v_branch,v_date,v_title,v_type,v_actor);
      update people.employees set version=version+1,updated_by=v_actor,
        updated_at=clock_timestamp() where id=v_id;
      v_effective:=v_date;
      v_after:=jsonb_build_object('previous_assignment_id',v_previous,
        'new_assignment_id',v_new_id);
    elsif v_action='end' then
      v_date:=(p_payload->>'end_date_exclusive')::date;
      if v_assignment.spell_id is distinct from (p_payload->>'spell_id')::uuid
         or v_date is null or v_date<=v_today or v_date<=v_assignment.start_date
         or v_assignment.start_date>v_today then
        raise exception using errcode='22023',message='EMPLOYMENT_CORRECTION_REQUIRED';
      end if;
      update people.employment_assignments set end_date_exclusive=v_date
        where id=v_assignment.id;
      update people.employment_spells set end_date_exclusive=v_date
        where id=v_assignment.spell_id;
      update people.employees set version=version+1,updated_by=v_actor,
        updated_at=clock_timestamp() where id=v_id;
      v_effective:=v_date;
      v_after:=jsonb_build_object('spell_id',v_assignment.spell_id,
        'end_date_exclusive',v_date);
    elsif v_action='rehire' then
      -- Only the last employing branch may initiate a rehire in this scope.
      if (select a.branch_id from people.employment_assignments a
          join people.employment_spells s on s.id=a.spell_id
          where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
            and a.employee_id=v_id
          order by s.start_date desc,a.start_date desc,a.id desc limit 1)
          is distinct from p_branch_id then
        raise exception using errcode='42501',message='EMPLOYMENT_SCOPE_INVALID';
      end if;
      if exists(select 1 from people.employment_spells s
        where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id
          and s.employee_id=v_id and s.end_date_exclusive is null) then
        raise exception using errcode='23514',message='EMPLOYMENT_OVERLAP';
      end if;
      v_date:=(p_payload->>'start_date')::date;
      if v_date is null or v_date<=v_today or exists(
        select 1 from people.employment_spells s
        where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id
          and s.employee_id=v_id and s.end_date_exclusive>v_date) then
        raise exception using errcode='22023',message='EMPLOYMENT_DATE_INVALID';
      end if;
      v_new_id:=gen_random_uuid();
      insert into people.employment_spells(id,tenant_id,legal_entity_id,
        employee_id,start_date,created_by)
      values(v_new_id,p_tenant_id,p_legal_entity_id,v_id,v_date,v_actor);
      insert into people.employment_assignments(id,tenant_id,legal_entity_id,
        employee_id,spell_id,branch_id,start_date,job_title,employment_type,created_by)
      values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,v_id,v_new_id,
        p_branch_id,v_date,v_title,v_type,v_actor);
      update people.employees set version=version+1,updated_by=v_actor,
        updated_at=clock_timestamp() where id=v_id;
      v_effective:=v_date;
      v_after:=jsonb_build_object('spell_id',v_new_id,'start_date',v_date);
    else
      -- Historical consumer checks are deliberately conservative until those
      -- providers expose a governed lock/check API. Only future scheduled changes
      -- can be undone here; immutable event evidence remains.
      if p_payload->>'correction_action'<>'cancel' then
        raise exception using errcode='22023',message='EMPLOYMENT_CORRECTION_REQUIRED';
      end if;
      select * into v_event from people.employment_events ev
        where ev.id=(p_payload->>'event_id')::uuid
          and ev.tenant_id=p_tenant_id and ev.legal_entity_id=p_legal_entity_id
          and ev.employee_id=v_id and ev.action='assignment'
        for share;
      if not found or exists(select 1 from people.employment_events ev
        where ev.tenant_id=p_tenant_id and ev.legal_entity_id=p_legal_entity_id
          and ev.employee_id=v_id and ev.supersedes_event_id=v_event.id) then
        raise exception using errcode='22023',message='EMPLOYMENT_CORRECTION_REQUIRED';
      end if;
      v_previous:=(v_event.after_state->>'previous_assignment_id')::uuid;
      v_new_id:=(v_event.after_state->>'new_assignment_id')::uuid;
      select a.branch_id into v_branch from people.employment_assignments a
        where a.id=v_previous and a.tenant_id=p_tenant_id
          and a.legal_entity_id=p_legal_entity_id and a.employee_id=v_id;
      if v_branch is null then
        raise exception using errcode='22023',message='EMPLOYMENT_CORRECTION_REQUIRED';
      end if;
      perform people.require_access(p_tenant_id,p_legal_entity_id,v_branch,
        'people.employment.manage');
      select * into v_assignment from people.employment_assignments a
        where a.id=v_new_id and a.tenant_id=p_tenant_id
          and a.legal_entity_id=p_legal_entity_id and a.employee_id=v_id
          and a.end_date_exclusive is null for update;
      if not found or v_assignment.start_date<=v_today then
        raise exception using errcode='22023',message='EMPLOYMENT_CORRECTION_REQUIRED';
      end if;
      perform people.require_access(p_tenant_id,p_legal_entity_id,v_assignment.branch_id,
        'people.employment.manage');
      if not exists(select 1 from people.employment_assignments a
        where a.id=v_previous and a.employee_id=v_id
          and a.end_date_exclusive=v_assignment.start_date) then
        raise exception using errcode='22023',message='EMPLOYMENT_CORRECTION_REQUIRED';
      end if;
      delete from people.employment_assignments where id=v_new_id;
      update people.employment_assignments set end_date_exclusive=null
        where id=v_previous;
      update people.employees set version=version+1,updated_by=v_actor,
        updated_at=clock_timestamp() where id=v_id;
      v_source_branch:=v_branch;
      v_branch:=p_branch_id;
      v_effective:=v_assignment.start_date;
      v_after:=jsonb_build_object('cancelled_event_id',v_event.id);
    end if;
  end if;
  perform people.assert_timeline(p_tenant_id,p_legal_entity_id,v_id);
  insert into people.employment_events(id,tenant_id,legal_entity_id,employee_id,
    branch_id,source_branch_id,action,effective_date,reason,before_state,after_state,
    supersedes_event_id,command_id,request_id,actor_id)
  values(v_event_id,p_tenant_id,p_legal_entity_id,v_id,v_branch,v_source_branch,v_action,
    v_effective,v_reason,v_before,v_after,
    case when v_action='correct' then v_event.id else null end,
    p_command_id,v_request,v_actor);
  v_entity:=people.employee_payload(v_id,p_branch_id);
  return core.wave3_finish_command(
    p_tenant_id,'people.employee.'||v_action,p_command_id,'people.employee',
    v_id,p_idempotency_key,v_request_hash,v_before,v_entity,
    p_legal_entity_id,p_branch_id,
    jsonb_build_object('employment_event_id',v_event_id),
    jsonb_build_object('from_status',case when v_action='create' then null else 'employed' end,
      'to_status',v_action,'reason',v_reason),
    jsonb_build_array(jsonb_build_object('topic','people.employee.'||v_action,
      'payload',jsonb_build_object('employee_id',v_id,'event_id',v_event_id))),
    '[]'::jsonb,v_request,v_request);
end $$;

revoke all on function api.people_employee_command(
  uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
  from public,anon,authenticated;
grant execute on function api.people_employee_command(
  uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
  to authenticated;
notify pgrst, 'reload schema';
