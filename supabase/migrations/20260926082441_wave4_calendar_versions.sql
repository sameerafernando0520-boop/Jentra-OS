-- W4-02A calendar governance candidate. Keep unapplied until reviewed.
-- No employee assignment, instant/DST resolution or private HR storage is added.

create extension if not exists btree_gist with schema extensions;

insert into core.permissions(code,module,description,privileged) values
('people.calendars.view','people','Read scoped work calendar versions.',false),
('people.calendars.manage','people','Publish entity work calendar versions.',true)
on conflict(code) do nothing;

create table people.work_calendars (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
  name text not null check(length(btrim(name)) between 1 and 160),
  version bigint not null default 1 check(version between 1 and 9007199254740991),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(tenant_id,legal_entity_id,id),
  unique(tenant_id,legal_entity_id,code),
  foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create index work_calendars_created_actor_idx on people.work_calendars(created_by);
create index work_calendars_updated_actor_idx on people.work_calendars(updated_by);

create table people.work_calendar_versions (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  calendar_id uuid not null,
  start_date date not null,
  end_date_exclusive date not null,
  timezone text not null,
  weekly_intervals jsonb not null,
  date_overrides jsonb not null,
  published_by uuid not null references auth.users(id),
  published_at timestamptz not null default clock_timestamp(),
  check(start_date >= '0001-01-01'::date and end_date_exclusive <= '9999-12-31'::date
    and end_date_exclusive > start_date and end_date_exclusive-start_date <= 1830),
  unique(tenant_id,legal_entity_id,id),
  unique(tenant_id,legal_entity_id,calendar_id,id),
  foreign key(tenant_id,legal_entity_id,calendar_id)
    references people.work_calendars(tenant_id,legal_entity_id,id),
  exclude using gist(calendar_id extensions.gist_uuid_ops with =,
    daterange(start_date,end_date_exclusive,'[)') with &&)
);
create index work_calendar_versions_scope_idx
  on people.work_calendar_versions(tenant_id,legal_entity_id,calendar_id,id);
create index work_calendar_versions_publisher_idx
  on people.work_calendar_versions(published_by);

create table people.work_calendar_events (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  calendar_id uuid not null,
  branch_id uuid not null,
  action text not null check(action in ('create','publish','rename')),
  published_version_id uuid,
  effective_date date,
  reason text not null check(length(btrim(reason)) between 1 and 1000),
  before_state jsonb not null,
  after_state jsonb not null,
  actor_id uuid not null references auth.users(id),
  command_id uuid not null,
  request_id uuid not null,
  recorded_at timestamptz not null default clock_timestamp(),
  check(jsonb_typeof(before_state)='object' and jsonb_typeof(after_state)='object'),
  check((action='rename' and published_version_id is null and effective_date is null)
    or (action in ('create','publish') and published_version_id is not null and effective_date is not null)),
  unique(tenant_id,legal_entity_id,command_id),
  foreign key(tenant_id,legal_entity_id,calendar_id)
    references people.work_calendars(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,calendar_id,published_version_id)
    references people.work_calendar_versions(tenant_id,legal_entity_id,calendar_id,id),
  foreign key(tenant_id,legal_entity_id,branch_id)
    references core.branches(tenant_id,legal_entity_id,id)
);
create index work_calendar_events_scope_idx
  on people.work_calendar_events(tenant_id,legal_entity_id,calendar_id,id);
create index work_calendar_events_branch_idx
  on people.work_calendar_events(tenant_id,legal_entity_id,branch_id);
create index work_calendar_events_version_idx
  on people.work_calendar_events(tenant_id,legal_entity_id,calendar_id,published_version_id);
create index work_calendar_events_actor_idx on people.work_calendar_events(actor_id);

create function people.validate_calendar_pattern(
  p_timezone text,p_start date,p_end date,p_weekly jsonb,p_overrides jsonb
) returns void language plpgsql set search_path = '' as $$
declare v_item jsonb; v_date date; v_day integer; v_start integer;
  v_end integer; v_offset integer;
begin
  if p_timezone is null or not exists(select 1 from pg_catalog.pg_timezone_names
      where name=p_timezone) or p_start is null or p_end is null
      or p_end<=p_start or p_end-p_start>1830
      or p_start<'0001-01-01'::date or p_end>'9999-12-31'::date then
    raise exception using errcode='22023',message='CALENDAR_VERSION_INVALID';
  end if;
  if coalesce(jsonb_typeof(p_weekly),'null')<>'array'
      or coalesce(jsonb_typeof(p_overrides),'null')<>'array' then
    raise exception using errcode='22023',message='CALENDAR_PATTERN_INVALID';
  end if;
  if jsonb_array_length(p_weekly)>56 or jsonb_array_length(p_overrides)>366 then
    raise exception using errcode='22023',message='CALENDAR_PATTERN_LIMIT';
  end if;
  for v_item in select value from jsonb_array_elements(p_weekly) loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception using errcode='22023',message='CALENDAR_INTERVAL_INVALID';
    end if;
    if exists(select 1 from jsonb_object_keys(v_item) k
      where k<>all(array['day_of_week','start_minute','end_minute','end_day_offset']))
      or coalesce(v_item->>'day_of_week','') !~ '^[0-9]{1,4}$'
      or coalesce(v_item->>'start_minute','') !~ '^[0-9]{1,4}$'
      or coalesce(v_item->>'end_minute','') !~ '^[0-9]{1,4}$'
      or coalesce(v_item->>'end_day_offset','') !~ '^[0-9]{1,4}$'
      or jsonb_typeof(v_item->'day_of_week')<>'number'
      or jsonb_typeof(v_item->'start_minute')<>'number'
      or jsonb_typeof(v_item->'end_minute')<>'number'
      or jsonb_typeof(v_item->'end_day_offset')<>'number' then
      raise exception using errcode='22023',message='CALENDAR_INTERVAL_INVALID';
    end if;
    v_day:=(v_item->>'day_of_week')::integer;
    v_start:=(v_item->>'start_minute')::integer;
    v_end:=(v_item->>'end_minute')::integer;
    v_offset:=(v_item->>'end_day_offset')::integer;
    if v_day not between 1 and 7 or v_start not between 0 and 1439
      or v_end not between 0 and 1439 or v_offset not in (0,1)
      or v_offset*1440+v_end-v_start not between 1 and 1440 then
      raise exception using errcode='22023',message='CALENDAR_INTERVAL_INVALID';
    end if;
  end loop;
  if exists(
    with spans as (
      select ordinality n,((value->>'day_of_week')::integer-1)*1440+
        (value->>'start_minute')::integer s,
        ((value->>'day_of_week')::integer-1+(value->>'end_day_offset')::integer)*1440+
        (value->>'end_minute')::integer e
      from jsonb_array_elements(p_weekly) with ordinality),
    segments as (
      select n*2 n,s,least(e,10080) e from spans
      union all select n*2+1,0,e-10080 from spans where e>10080)
    select 1 from segments a join segments b on b.n>a.n
      where int4range(a.s,a.e,'[)') && int4range(b.s,b.e,'[)')
  ) then raise exception using errcode='23514',message='CALENDAR_INTERVAL_OVERLAP'; end if;
  for v_item in select value from jsonb_array_elements(p_overrides) loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception using errcode='22023',message='CALENDAR_OVERRIDE_INVALID';
    end if;
    if exists(select 1 from jsonb_object_keys(v_item) k
      where k<>all(array['date','is_working_day','reason']))
      or coalesce(v_item->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or coalesce(jsonb_typeof(v_item->'is_working_day'),'null')<>'boolean'
      or coalesce(jsonb_typeof(v_item->'reason'),'null')<>'string'
      or length(btrim(v_item->>'reason')) not between 1 and 500 then
      raise exception using errcode='22023',message='CALENDAR_OVERRIDE_INVALID';
    end if;
    v_date:=(v_item->>'date')::date;
    if v_date<p_start or v_date>=p_end then
      raise exception using errcode='22023',message='CALENDAR_OVERRIDE_OUTSIDE_VERSION';
    end if;
    if (v_item->>'is_working_day')::boolean and not exists(
      select 1 from jsonb_array_elements(p_weekly) w
      where (w->>'day_of_week')::integer=extract(isodow from v_date)::integer
        or ((w->>'day_of_week')::integer=(extract(isodow from v_date)::integer+5)%7+1
          and (w->>'end_day_offset')::integer=1 and (w->>'end_minute')::integer>0)
    ) then raise exception using errcode='22023',message='CALENDAR_WORKING_OVERRIDE_UNCONFIGURED'; end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_overrides) x
    group by x->>'date' having count(*)>1) then
    raise exception using errcode='23514',message='CALENDAR_OVERRIDE_DUPLICATE';
  end if;
end $$;
revoke all on function people.validate_calendar_pattern(text,date,date,jsonb,jsonb)
  from public,anon,authenticated;

create function people.guard_calendar_version() returns trigger
language plpgsql set search_path = '' as $$begin
  if tg_op<>'INSERT' then
    raise exception using errcode='55000',message='CALENDAR_VERSION_IMMUTABLE';
  end if;
  perform people.validate_calendar_pattern(new.timezone,new.start_date,
    new.end_date_exclusive,new.weekly_intervals,new.date_overrides);
  return new;
end $$;
create trigger work_calendar_version_guard before insert or update or delete
  on people.work_calendar_versions for each row execute function people.guard_calendar_version();
create function people.guard_calendar_identity() returns trigger
language plpgsql set search_path = '' as $$begin
  if new.id<>old.id or new.tenant_id<>old.tenant_id
      or new.legal_entity_id<>old.legal_entity_id or new.code<>old.code then
    raise exception using errcode='55000',message='CALENDAR_IDENTITY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger work_calendar_identity_guard before update on people.work_calendars
  for each row execute function people.guard_calendar_identity();
create trigger work_calendars_touch before update on people.work_calendars
  for each row execute function core.touch_mutable_record();
create function people.reject_calendar_event_change() returns trigger
language plpgsql set search_path = '' as $$begin
  raise exception using errcode='55000',message='CALENDAR_EVENT_IMMUTABLE';
end $$;
create trigger work_calendar_events_immutable before update or delete on people.work_calendar_events
  for each row execute function people.reject_calendar_event_change();
revoke all on function people.guard_calendar_version(),people.guard_calendar_identity(),
  people.reject_calendar_event_change() from public,anon,authenticated;

alter table people.work_calendars enable row level security;
alter table people.work_calendars force row level security;
alter table people.work_calendar_versions enable row level security;
alter table people.work_calendar_versions force row level security;
alter table people.work_calendar_events enable row level security;
alter table people.work_calendar_events force row level security;
revoke all on people.work_calendars,people.work_calendar_versions,people.work_calendar_events
  from public,anon,authenticated;

create function people.calendar_summary(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',c.id,'tenant_id',c.tenant_id,
    'legal_entity_id',c.legal_entity_id,'code',c.code,'name',c.name,'version',c.version)
  from people.work_calendars c where c.id=p_id
$$;
create function people.calendar_version_payload(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',v.id,'calendar_id',v.calendar_id,
    'tenant_id',v.tenant_id,'legal_entity_id',v.legal_entity_id,
    'start_date',v.start_date,'end_date_exclusive',v.end_date_exclusive,
    'timezone',v.timezone,'weekly_intervals',v.weekly_intervals,
    'date_overrides',v.date_overrides,'published_by',v.published_by,'published_at',v.published_at)
  from people.work_calendar_versions v where v.id=p_id
$$;
revoke all on function people.calendar_summary(uuid),people.calendar_version_payload(uuid)
  from public,anon,authenticated;

create function api.people_calendar_directory(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_as_of date default null,p_search text default '',p_after uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_date date; v_items jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.view');
  select coalesce(p_as_of,(now() at time zone e.timezone)::date) into v_date
    from core.legal_entities e where e.tenant_id=p_tenant_id and e.id=p_legal_entity_id;
  if v_date is null or not isfinite(v_date) or length(coalesce(p_search,''))>160 then
    raise exception using errcode='22023',message='CALENDAR_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(people.calendar_summary(q.id)||jsonb_build_object(
    'selected_version',q.selected_version) order by q.id),'[]'::jsonb) into v_items
  from (select c.id,(select jsonb_build_object('id',v.id,'start_date',v.start_date,
      'end_date_exclusive',v.end_date_exclusive,'timezone',v.timezone)
    from people.work_calendar_versions v where v.calendar_id=c.id
      and v.start_date<=v_date and v.end_date_exclusive>v_date) selected_version
    from people.work_calendars c where c.tenant_id=p_tenant_id
      and c.legal_entity_id=p_legal_entity_id and (p_after is null or c.id>p_after)
      and (btrim(coalesce(p_search,''))='' or position(lower(btrim(p_search))
        in lower(c.code||' '||c.name))>0) order by c.id limit 50) q;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'as_of',v_date,'items',v_items);
end $$;

create function api.people_calendar_detail(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_calendar_id uuid,p_version_id uuid
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.view');
  if not exists(select 1 from people.work_calendars c join people.work_calendar_versions v
      on v.calendar_id=c.id where c.tenant_id=p_tenant_id
      and c.legal_entity_id=p_legal_entity_id and c.id=p_calendar_id and v.id=p_version_id) then
    raise exception using errcode='P0002',message='CALENDAR_NOT_FOUND';
  end if;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'calendar',people.calendar_summary(p_calendar_id),
    'calendar_version',people.calendar_version_payload(p_version_id));
end $$;

create function api.people_calendar_versions(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_calendar_id uuid,p_after uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_items jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.view');
  if not exists(select 1 from people.work_calendars c where c.id=p_calendar_id
      and c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id) then
    raise exception using errcode='P0002',message='CALENDAR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'start_date',q.start_date,
    'end_date_exclusive',q.end_date_exclusive,'timezone',q.timezone,
    'published_by',q.published_by,'published_at',q.published_at) order by q.id),'[]'::jsonb)
    into v_items from (select v.* from people.work_calendar_versions v
    where v.calendar_id=p_calendar_id and (p_after is null or v.id>p_after)
    order by v.id limit 50) q;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'calendar_id',p_calendar_id,'items',v_items);
end $$;

create function api.people_calendar_history(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_calendar_id uuid,p_after uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_items jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.view');
  if not exists(select 1 from people.work_calendars c where c.id=p_calendar_id
      and c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id) then
    raise exception using errcode='P0002',message='CALENDAR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'action',q.action,
    'published_version_id',q.published_version_id,'effective_date',q.effective_date,
    'reason',q.reason,'actor_id',q.actor_id,'recorded_at',q.recorded_at,
    'before_state',q.before_state,'after_state',q.after_state) order by q.id),'[]'::jsonb)
    into v_items from (select e.* from people.work_calendar_events e
    where e.calendar_id=p_calendar_id and (p_after is null or e.id>p_after)
    order by e.id limit 50) q;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'calendar_id',p_calendar_id,'items',v_items);
end $$;

create function api.people_calendar_command(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
  p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=(select auth.uid()); v_action text:=p_payload->>'action';
  v_id uuid; v_version_id uuid; v_start date; v_end date; v_today date;
  v_allowed text[]; v_reason text; v_name text; v_hash text; v_replay jsonb;
  v_calendar people.work_calendars%rowtype; v_before jsonb:='{}'::jsonb;
  v_entity jsonb; v_request uuid:=gen_random_uuid();
begin
  if coalesce(jsonb_typeof(p_payload),'null')<>'object' or p_command_id is null
    or p_idempotency_key is null or p_client_timestamp is null or v_action is null
    or v_action not in ('create','publish','rename')
    or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode='22023',message='CALENDAR_COMMAND_INVALID';
  end if;
  v_allowed:=case v_action when 'create' then array['action','id','code','name',
    'version_id','start_date','end_date_exclusive','timezone','weekly_intervals','date_overrides','reason']
    when 'publish' then array['action','id','version_id','start_date','end_date_exclusive',
      'timezone','weekly_intervals','date_overrides','reason']
    else array['action','id','name','reason'] end;
  if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(v_allowed)) then
    raise exception using errcode='22023',message='CALENDAR_COMMAND_FIELDS_INVALID';
  end if;
  v_id:=(p_payload->>'id')::uuid; v_reason:=btrim(p_payload->>'reason');
  if coalesce(jsonb_typeof(p_payload->'reason'),'null')<>'string'
    or length(v_reason) not between 1 and 1000 then
    raise exception using errcode='22023',message='CALENDAR_REASON_REQUIRED';
  end if;
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.view');
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.manage');
  -- A branch-limited manager cannot change a calendar shared by the whole entity.
  perform core.require_permission(p_tenant_id,'people.calendars.manage',p_legal_entity_id,null);
  v_hash:=core.wave3_request_hash('people.calendar.'||v_action,p_command_id,
    p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
  v_replay:=core.wave3_replay(p_tenant_id,'people.calendar.'||v_action,
    p_command_id,p_idempotency_key,v_hash);
  if v_replay is not null then return v_replay; end if;
  if v_action='create' then
    if p_expected_version is distinct from 0
      or coalesce(jsonb_typeof(p_payload->'code'),'null')<>'string'
      or coalesce(p_payload->>'code','')
      !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' then
      raise exception using errcode='22023',message='CALENDAR_CREATE_INVALID';
    end if;
  else
    select c.* into v_calendar from people.work_calendars c
      where c.id=v_id and c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id for update;
    if not found then raise exception using errcode='P0002',message='CALENDAR_NOT_FOUND'; end if;
    perform core.wave3_assert_expected_version(v_calendar.version,p_expected_version,
      people.calendar_summary(v_id));
    v_before:=people.calendar_summary(v_id);
  end if;
  if v_action in ('create','rename') then
    v_name:=btrim(p_payload->>'name');
    if coalesce(jsonb_typeof(p_payload->'name'),'null')<>'string'
      or length(v_name) not between 1 and 160 then
      raise exception using errcode='22023',message='CALENDAR_NAME_INVALID';
    end if;
  end if;
  if v_action in ('create','publish') then
    if coalesce(p_payload->>'version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or coalesce(p_payload->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or coalesce(p_payload->>'end_date_exclusive','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception using errcode='22023',message='CALENDAR_VERSION_INVALID';
    end if;
    v_version_id:=(p_payload->>'version_id')::uuid;
    v_start:=(p_payload->>'start_date')::date; v_end:=(p_payload->>'end_date_exclusive')::date;
    perform people.validate_calendar_pattern(p_payload->>'timezone',v_start,v_end,
      p_payload->'weekly_intervals',p_payload->'date_overrides');
    select (now() at time zone e.timezone)::date into v_today from core.legal_entities e
      where e.tenant_id=p_tenant_id and e.id=p_legal_entity_id;
    if v_action='publish' and v_start<=v_today then
      raise exception using errcode='55000',message='CALENDAR_RETROACTIVE_CHANGE_REQUIRED';
    end if;
  end if;
  if v_action='create' then
    insert into people.work_calendars(id,tenant_id,legal_entity_id,code,name,created_by,updated_by)
      values(v_id,p_tenant_id,p_legal_entity_id,p_payload->>'code',v_name,v_actor,v_actor);
  else
    update people.work_calendars set name=case when v_action='rename' then v_name else name end,
      updated_by=v_actor where id=v_id;
  end if;
  if v_action in ('create','publish') then
    insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,
      start_date,end_date_exclusive,timezone,weekly_intervals,date_overrides,published_by)
    values(v_version_id,p_tenant_id,p_legal_entity_id,v_id,v_start,v_end,
      p_payload->>'timezone',p_payload->'weekly_intervals',p_payload->'date_overrides',v_actor);
  end if;
  v_entity:=people.calendar_summary(v_id)||jsonb_build_object('published_version_id',v_version_id);
  insert into people.work_calendar_events(id,tenant_id,legal_entity_id,calendar_id,branch_id,
    action,published_version_id,effective_date,reason,before_state,after_state,actor_id,command_id,request_id)
  values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,v_id,p_branch_id,v_action,
    v_version_id,v_start,v_reason,v_before,v_entity,v_actor,p_command_id,v_request);
  return core.wave3_finish_command(p_tenant_id,'people.calendar.'||v_action,p_command_id,
    'people.calendar',v_id,p_idempotency_key,v_hash,v_before,v_entity,
    p_legal_entity_id,p_branch_id,p_request_id=>v_request);
end $$;

revoke all on function api.people_calendar_directory(uuid,uuid,uuid,date,text,uuid),
  api.people_calendar_detail(uuid,uuid,uuid,uuid,uuid),
  api.people_calendar_versions(uuid,uuid,uuid,uuid,uuid),
  api.people_calendar_history(uuid,uuid,uuid,uuid,uuid),
  api.people_calendar_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
  from public,anon,authenticated;
grant execute on function api.people_calendar_directory(uuid,uuid,uuid,date,text,uuid),
  api.people_calendar_detail(uuid,uuid,uuid,uuid,uuid),
  api.people_calendar_versions(uuid,uuid,uuid,uuid,uuid),
  api.people_calendar_history(uuid,uuid,uuid,uuid,uuid),
  api.people_calendar_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
  to authenticated;
