begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
-- W4-02A exact civil boundary resolution. Unapplied development candidate.
-- Existing employee/calendar migrations are immutable. No grants to roles/plans.

create function people.local_instant_candidates(p_timezone text,p_local timestamp)
returns jsonb language plpgsql stable set search_path = '' as $$
declare v_result jsonb;
begin
  if p_timezone is null or p_local is null or not isfinite(p_local)
    or p_local<'0001-01-01'::timestamp or p_local>='10000-01-01'::timestamp
    or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone) then
    raise exception using errcode='22023',message='CALENDAR_LOCAL_BOUNDARY_INVALID';
  end if;
  -- Sample both sides of all civil-date offset transitions, including 24-hour
  -- date-line jumps. Round-trip verification, not PostgreSQL's implicit fold/gap
  -- preference, determines whether a candidate is a valid local instant.
  with probes as (
    select (p_local at time zone 'UTC')+g*interval '1 hour' instant
    from pg_catalog.generate_series(-48,48) g
  ), offsets as (
    select distinct extract(epoch from
      (instant at time zone p_timezone)-(instant at time zone 'UTC'))::integer seconds
    from probes
  ), candidates as (
    select (p_local-seconds*interval '1 second') at time zone 'UTC' utc,seconds
    from offsets
  )
  select coalesce(jsonb_agg(jsonb_build_object('utc',
    to_char(utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'offset_seconds',seconds)
    order by utc),'[]'::jsonb) into v_result from candidates
    where utc at time zone p_timezone=p_local;
  return v_result;
end $$;

create function people.resolve_local_instant(
  p_timezone text,p_local timestamp,p_offset_seconds integer default null
) returns timestamptz language plpgsql stable set search_path = '' as $$
declare v_candidates jsonb; v_utc timestamptz;
begin
  v_candidates:=people.local_instant_candidates(p_timezone,p_local);
  if jsonb_array_length(v_candidates)=0 then
    raise exception using errcode='22023',message='CALENDAR_LOCAL_TIME_NONEXISTENT';
  end if;
  if jsonb_array_length(v_candidates)>1 and p_offset_seconds is null then
    raise exception using errcode='22023',message='CALENDAR_OFFSET_SELECTION_REQUIRED';
  end if;
  select (value->>'utc')::timestamptz into v_utc
    from jsonb_array_elements(v_candidates)
    where p_offset_seconds is null or (value->>'offset_seconds')::integer=p_offset_seconds;
  if v_utc is null then
    raise exception using errcode='22023',message='CALENDAR_OFFSET_INVALID';
  end if;
  return v_utc;
end $$;

create function api.people_calendar_local_candidates(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_version_id uuid,p_date date,p_minute integer
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_version people.work_calendar_versions%rowtype; v_local timestamp;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.view');
  select v.* into v_version from people.work_calendar_versions v
    where v.tenant_id=p_tenant_id and v.legal_entity_id=p_legal_entity_id and v.id=p_version_id;
  if not found then raise exception using errcode='P0002',message='CALENDAR_NOT_FOUND'; end if;
  if p_date is null or not isfinite(p_date) or p_minute is null
    or p_minute not between 0 and 1439
    or p_date<v_version.start_date or p_date>=v_version.end_date_exclusive then
    raise exception using errcode='22023',message='CALENDAR_LOCAL_BOUNDARY_INVALID';
  end if;
  v_local:=p_date::timestamp+p_minute*interval '1 minute';
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'resolution',jsonb_build_object(
    'calendar_version_id',v_version.id,'date',p_date,'minute',p_minute,
    'timezone',v_version.timezone,'local_datetime',to_char(v_local,'YYYY-MM-DD"T"HH24:MI:SS'),
    'algorithm','pg-iana-roundtrip-v1',
    'candidates',people.local_instant_candidates(v_version.timezone,v_local)));
end $$;

revoke all on function people.local_instant_candidates(text,timestamp),
  people.resolve_local_instant(text,timestamp,integer),
  api.people_calendar_local_candidates(uuid,uuid,uuid,uuid,date,integer)
  from public,anon,authenticated;
grant execute on function api.people_calendar_local_candidates(uuid,uuid,uuid,uuid,date,integer)
  to authenticated;

-- W4-02A dated organization. Unapplied, additive synthetic development candidate.
insert into core.permissions(code,module,description,privileged) values
('people.organization.view','people','Read scoped organization history.',false),
('people.organization.manage','people','Manage dated organization with MFA.',true)
on conflict(code) do nothing;

create table people.departments (
  id uuid primary key, tenant_id uuid not null, legal_entity_id uuid not null,
  code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
  version bigint not null default 1 check(version between 1 and 9007199254740991),
  unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
  foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create table people.department_revisions (
  id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
  department_id uuid not null,parent_id uuid,name text not null check(length(btrim(name)) between 1 and 160),
  start_date date not null,end_date_exclusive date,
  reason text not null check(length(btrim(reason)) between 1 and 1000),
  recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
  supersedes_id uuid references people.department_revisions(id),superseded_at timestamptz,
  check(start_date>='0001-01-01'::date and start_date<='9999-12-31'::date
    and (end_date_exclusive is null or (end_date_exclusive>start_date and end_date_exclusive<='9999-12-31'::date))),
  unique(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,department_id) references people.departments(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,parent_id) references people.departments(tenant_id,legal_entity_id,id),
  exclude using gist(department_id extensions.gist_uuid_ops with =,
    daterange(start_date,end_date_exclusive,'[)') with &&) where(superseded_at is null)
);
create index department_revisions_scope_idx on people.department_revisions(tenant_id,legal_entity_id,department_id,id);
create index department_revisions_parent_idx on people.department_revisions(tenant_id,legal_entity_id,parent_id);
create index department_revisions_actor_idx on people.department_revisions(recorded_by);
create index department_revisions_supersedes_idx on people.department_revisions(supersedes_id);
create table people.organization_assignments (
  id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
  employee_id uuid not null,spell_id uuid not null,department_id uuid not null,manager_id uuid,
  calendar_version_id uuid not null,role_title text not null check(length(btrim(role_title)) between 1 and 160),
  start_date date not null,end_date_exclusive date not null,
  reason text not null check(length(btrim(reason)) between 1 and 1000),
  recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
  supersedes_id uuid references people.organization_assignments(id),superseded_at timestamptz,
  check(start_date>='0001-01-01'::date and end_date_exclusive<='9999-12-31'::date
    and end_date_exclusive>start_date and end_date_exclusive-start_date<=1830),
  unique(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,spell_id,employee_id) references people.employment_spells(tenant_id,legal_entity_id,id,employee_id),
  foreign key(tenant_id,legal_entity_id,department_id) references people.departments(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,manager_id) references people.employees(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
  exclude using gist(employee_id extensions.gist_uuid_ops with =,
    daterange(start_date,end_date_exclusive,'[)') with &&) where(superseded_at is null)
);
create index organization_assignments_scope_idx on people.organization_assignments(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index organization_assignments_employee_idx on people.organization_assignments(tenant_id,legal_entity_id,employee_id);
create index organization_assignments_spell_idx on people.organization_assignments(tenant_id,legal_entity_id,spell_id);
create index organization_assignments_department_idx on people.organization_assignments(tenant_id,legal_entity_id,department_id);
create index organization_assignments_manager_idx on people.organization_assignments(tenant_id,legal_entity_id,manager_id);
create index organization_assignments_calendar_idx on people.organization_assignments(tenant_id,legal_entity_id,calendar_version_id);
create index organization_assignments_actor_idx on people.organization_assignments(recorded_by);
create index organization_assignments_supersedes_idx on people.organization_assignments(supersedes_id);
create table people.organization_withdrawals (
  id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
  employee_id uuid not null,revision_id uuid not null unique,
  reason text not null check(length(btrim(reason)) between 1 and 1000),
  recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
  foreign key(tenant_id,legal_entity_id,revision_id) references people.organization_assignments(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
  foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index organization_withdrawals_scope_idx on people.organization_withdrawals(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index organization_withdrawals_employee_idx on people.organization_withdrawals(tenant_id,legal_entity_id,employee_id);
create index organization_withdrawals_revision_idx on people.organization_withdrawals(tenant_id,legal_entity_id,revision_id);
create index organization_withdrawals_actor_idx on people.organization_withdrawals(recorded_by);

-- Only trusted module commands can seal dated organization inputs. A consumed
-- revision remains immutable even after an unchanged prefix is superseded.
create table people.organization_consumptions (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null,
  legal_entity_id uuid not null, revision_id uuid not null,
  source_type text not null check(source_type in ('attendance','leave','payroll','project_time','service_time')),
  source_id uuid not null, start_date date not null,end_date_exclusive date not null,
  recorded_at timestamptz not null default clock_timestamp(),
  check(end_date_exclusive>start_date),
  unique(tenant_id,legal_entity_id,source_type,source_id),
  foreign key(tenant_id,legal_entity_id,revision_id)
    references people.organization_assignments(tenant_id,legal_entity_id,id)
);
create index organization_consumptions_revision_idx on people.organization_consumptions(tenant_id,legal_entity_id,revision_id);
create function people.guard_organization_consumption() returns trigger language plpgsql set search_path='' as $$
begin raise exception using errcode='55000',message='ORGANIZATION_CONSUMPTION_IMMUTABLE'; end $$;
create trigger organization_consumption_immutable before update or delete on people.organization_consumptions
  for each row execute function people.guard_organization_consumption();
create trigger organization_withdrawal_immutable before update or delete on people.organization_withdrawals
  for each row execute function people.guard_organization_consumption();
create function people.consume_organization(p_tenant uuid,p_entity uuid,p_branch uuid,p_employee uuid,
  p_source_type text,p_source_id uuid,p_start date,p_end date) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  perform id from people.employees where id=p_employee and tenant_id=p_tenant and legal_entity_id=p_entity for update;
  perform pg_advisory_xact_lock(hashtextextended('people.organization:'||p_tenant||':'||p_entity,0));
  select id into v_id from people.organization_assignments where employee_id=p_employee
    and tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and superseded_at is null
    and daterange(start_date,end_date_exclusive,'[)') @> daterange(p_start,p_end,'[)');
  if v_id is null or p_start is null or p_end is null or p_end<=p_start then
    raise exception using errcode='55000',message='ORGANIZATION_ASSIGNMENT_REQUIRED';
  end if;
  insert into people.organization_consumptions(tenant_id,legal_entity_id,revision_id,source_type,source_id,start_date,end_date_exclusive)
    values(p_tenant,p_entity,v_id,p_source_type,p_source_id,p_start,p_end) on conflict do nothing;
  if not exists(select 1 from people.organization_consumptions where tenant_id=p_tenant and legal_entity_id=p_entity
    and revision_id=v_id and source_type=p_source_type and source_id=p_source_id and start_date=p_start and end_date_exclusive=p_end) then
    raise exception using errcode='22023',message='ORGANIZATION_CONSUMPTION_MISMATCH';
  end if;
  return v_id;
end $$;

create function people.guard_organization_revision() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' or new.superseded_at is null or old.superseded_at is not null
    or (to_jsonb(new)-'superseded_at') is distinct from (to_jsonb(old)-'superseded_at') then
    raise exception using errcode='55000',message='ORGANIZATION_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger department_history_immutable before update or delete on people.department_revisions
  for each row execute function people.guard_organization_revision();
create trigger organization_history_immutable before update or delete on people.organization_assignments
  for each row execute function people.guard_organization_revision();

create function people.assert_organization(p_tenant uuid,p_entity uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from people.department_revisions d where d.tenant_id=p_tenant
    and d.legal_entity_id=p_entity and d.superseded_at is null and d.parent_id is not null
    and not coalesce(daterange(d.start_date,d.end_date_exclusive,'[)') <@
      (select range_agg(daterange(p.start_date,p.end_date_exclusive,'[)'))
       from people.department_revisions p where p.department_id=d.parent_id and p.superseded_at is null),false)) then
    raise exception using errcode='23514',message='DEPARTMENT_PARENT_COVERAGE_REQUIRED';
  end if;
  if exists(with recursive walk as (
    select d.department_id,d.parent_id,daterange(d.start_date,d.end_date_exclusive,'[)') span,
      array[d.department_id] path,false cycle from people.department_revisions d
      where d.tenant_id=p_tenant and d.legal_entity_id=p_entity and d.superseded_at is null
    union all select p.department_id,p.parent_id,w.span*daterange(p.start_date,p.end_date_exclusive,'[)'),
      w.path||p.department_id,p.department_id=any(w.path)
      from walk w join people.department_revisions p on p.department_id=w.parent_id
      and p.superseded_at is null and w.span && daterange(p.start_date,p.end_date_exclusive,'[)')
      where not w.cycle and cardinality(w.path)<=64
  ) select 1 from walk where cycle or cardinality(path)>64) then
    raise exception using errcode='23514',message='DEPARTMENT_CYCLE_OR_DEPTH';
  end if;
  if exists(select 1 from people.organization_assignments o
    where o.tenant_id=p_tenant and o.legal_entity_id=p_entity and o.superseded_at is null and (
      not exists(select 1 from people.employment_spells s where s.id=o.spell_id and s.employee_id=o.employee_id
        and daterange(s.start_date,s.end_date_exclusive,'[)') @> daterange(o.start_date,o.end_date_exclusive,'[)'))
      or not coalesce(daterange(o.start_date,o.end_date_exclusive,'[)') <@
        (select range_agg(daterange(a.start_date,a.end_date_exclusive,'[)')) from people.employment_assignments a
         where a.employee_id=o.employee_id and a.spell_id=o.spell_id and a.branch_id=o.branch_id),false)
      or not exists(select 1 from people.work_calendar_versions c where c.id=o.calendar_version_id
        and daterange(c.start_date,c.end_date_exclusive,'[)') @> daterange(o.start_date,o.end_date_exclusive,'[)'))
      or not coalesce(daterange(o.start_date,o.end_date_exclusive,'[)') <@
        (select range_agg(daterange(d.start_date,d.end_date_exclusive,'[)')) from people.department_revisions d
         where d.department_id=o.department_id and d.superseded_at is null),false)
      or (o.manager_id is not null and (o.manager_id=o.employee_id or not coalesce(
        daterange(o.start_date,o.end_date_exclusive,'[)') <@
        (select range_agg(daterange(s.start_date,s.end_date_exclusive,'[)')) from people.employment_spells s
          where s.employee_id=o.manager_id),false)))
    )) then raise exception using errcode='23514',message='ORGANIZATION_IMPACT_REQUIRED'; end if;
  if exists(with recursive walk as (
    select o.employee_id,o.manager_id,daterange(o.start_date,o.end_date_exclusive,'[)') span,
      array[o.employee_id] path,false cycle from people.organization_assignments o
      where o.tenant_id=p_tenant and o.legal_entity_id=p_entity and o.superseded_at is null
    union all select m.employee_id,m.manager_id,w.span*daterange(m.start_date,m.end_date_exclusive,'[)'),
      w.path||m.employee_id,m.employee_id=any(w.path) from walk w
      join people.organization_assignments m on m.employee_id=w.manager_id and m.superseded_at is null
        and w.span && daterange(m.start_date,m.end_date_exclusive,'[)')
      where not w.cycle and cardinality(w.path)<=64
  ) select 1 from walk where cycle or cardinality(path)>64) then
    raise exception using errcode='23514',message='MANAGER_CYCLE_OR_DEPTH';
  end if;
end $$;
create function people.check_organization_compatibility() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform people.assert_organization(coalesce(new.tenant_id,old.tenant_id),
    coalesce(new.legal_entity_id,old.legal_entity_id));
  return null;
end $$;
create constraint trigger organization_after_employment_spell after insert or update or delete on people.employment_spells
  deferrable initially deferred for each row execute function people.check_organization_compatibility();
create constraint trigger organization_after_employment_assignment after insert or update or delete on people.employment_assignments
  deferrable initially deferred for each row execute function people.check_organization_compatibility();
create constraint trigger organization_assignment_compatible after insert or update on people.organization_assignments
  deferrable initially deferred for each row execute function people.check_organization_compatibility();
create constraint trigger department_revision_compatible after insert or update on people.department_revisions
  deferrable initially deferred for each row execute function people.check_organization_compatibility();

create function people.organization_assignment_payload(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',o.id,'tenant_id',o.tenant_id,'legal_entity_id',o.legal_entity_id,
    'branch_id',o.branch_id,'employee_id',o.employee_id,'spell_id',o.spell_id,
    'department_id',o.department_id,'manager_id',o.manager_id,'calendar_version_id',o.calendar_version_id,
    'role_title',o.role_title,'start_date',o.start_date,'end_date_exclusive',o.end_date_exclusive,
    'reason',o.reason,'recorded_by',o.recorded_by,'recorded_at',o.recorded_at,
    'supersedes_id',o.supersedes_id,'superseded_at',o.superseded_at)
    ||jsonb_build_object('department_name_at_start',(select name from people.department_revisions d
      where d.department_id=o.department_id and d.superseded_at is null
        and daterange(d.start_date,d.end_date_exclusive,'[)') @> o.start_date),
      'manager_display_name',(select display_name from people.employees where id=o.manager_id),
      'withdrawal',(select jsonb_build_object('id',w.id,'reason',w.reason,'recorded_by',w.recorded_by,'recorded_at',w.recorded_at)
        from people.organization_withdrawals w where w.revision_id=o.id),
      'calendar_name',(select c.name from people.work_calendars c join people.work_calendar_versions v on v.calendar_id=c.id
        where v.id=o.calendar_version_id),'calendar_timezone',(select timezone from people.work_calendar_versions where id=o.calendar_version_id))
  from people.organization_assignments o where o.id=p_id
$$;
create function api.people_organization_department(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_department_id uuid,p_as_of date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_item jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.organization.view');
  if p_as_of is null or not isfinite(p_as_of) or p_as_of<'0001-01-01'::date or p_as_of>'9999-12-31'::date then
    raise exception using errcode='22023',message='ORGANIZATION_FILTER_INVALID';
  end if;
  select jsonb_build_object('id',d.id,'code',d.code,'version',d.version,'revision_id',r.id,'name',r.name,
    'parent_id',r.parent_id,'start_date',r.start_date,'end_date_exclusive',r.end_date_exclusive) into v_item
    from people.departments d join people.department_revisions r on r.department_id=d.id and r.superseded_at is null
      and daterange(r.start_date,r.end_date_exclusive,'[)') @> p_as_of
    where d.id=p_department_id and d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id;
  if v_item is null then raise exception using errcode='P0002',message='DEPARTMENT_NOT_FOUND'; end if;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
    'as_of',p_as_of,'department',v_item);
end $$;
create function api.people_organization_departments(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_as_of date,p_search text default '',p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.organization.view');
  if p_as_of is null or not isfinite(p_as_of) or p_as_of<'0001-01-01'::date
    or p_as_of>'9999-12-31'::date or length(coalesce(p_search,''))>160 then
    raise exception using errcode='22023',message='ORGANIZATION_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'version',q.version,
    'revision_id',q.revision_id,'name',q.name,'parent_id',q.parent_id,
    'start_date',q.start_date,'end_date_exclusive',q.end_date_exclusive) order by q.id),'[]') into v_items
  from (select d.id,d.code,d.version,r.id revision_id,r.name,r.parent_id,r.start_date,r.end_date_exclusive
    from people.departments d join people.department_revisions r on r.department_id=d.id
    and r.superseded_at is null and daterange(r.start_date,r.end_date_exclusive,'[)') @> p_as_of
    where d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id and (p_after is null or d.id>p_after)
    and (btrim(coalesce(p_search,''))='' or position(lower(btrim(p_search)) in lower(d.code||' '||r.name))>0)
    order by d.id limit 50) q;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'as_of',p_as_of,'items',v_items);
end $$;
create function api.people_organization_employee(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_employee_id uuid,p_as_of date,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb; v_version bigint;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.organization.view');
  perform api.people_employee_detail(p_tenant_id,p_legal_entity_id,p_branch_id,p_employee_id,p_as_of);
  select version into v_version from people.employees where id=p_employee_id;
  select coalesce(jsonb_agg(people.organization_assignment_payload(q.id) order by q.id),'[]') into v_items
    from (select id from people.organization_assignments where employee_id=p_employee_id and branch_id=p_branch_id
      and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and (p_after is null or id>p_after)
      order by id limit 50) q;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
    'employee_id',p_employee_id,'employee_version',v_version,'as_of',p_as_of,'items',v_items);
end $$;
create function api.people_organization_department_history(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_department_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;
begin
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.organization.view');
  if not exists(select 1 from people.departments where id=p_department_id and tenant_id=p_tenant_id
    and legal_entity_id=p_legal_entity_id) then raise exception using errcode='P0002',message='DEPARTMENT_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'parent_id',q.parent_id,
    'start_date',q.start_date,'end_date_exclusive',q.end_date_exclusive,'reason',q.reason,
    'recorded_by',q.recorded_by,'recorded_at',q.recorded_at,'supersedes_id',q.supersedes_id,
    'superseded_at',q.superseded_at) order by q.id),'[]') into v_items
    from (select * from people.department_revisions where department_id=p_department_id
      and (p_after is null or id>p_after) order by id limit 50) q;
  return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'department_id',p_department_id,'items',v_items);
end $$;

create function api.people_organization_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_actor uuid:=auth.uid();v_id uuid;v_revision uuid;
  v_employee uuid;v_manager uuid;v_start date;v_end date;v_hash text;v_replay jsonb;v_allowed text[];
  v_before jsonb:='{}';v_entity jsonb;v_current bigint;v_old people.department_revisions%rowtype;
  v_old_org people.organization_assignments%rowtype;v_name text;v_reason text;v_parent uuid;
begin
  if coalesce(jsonb_typeof(p_payload),'null')<>'object' or v_action is null
    or v_action not in ('department_create','department_revise','assign','replace','end_assignment','withdraw_assignment')
    or p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
    or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode='22023',message='ORGANIZATION_COMMAND_INVALID';
  end if;
  v_allowed:=case v_action
    when 'department_create' then array['action','id','revision_id','code','name','parent_id','start_date','end_date_exclusive','reason']
    when 'department_revise' then array['action','id','revision_id','name','parent_id','start_date','end_date_exclusive','reason','replace_revision_id']
    when 'assign' then array['action','id','employee_id','spell_id','department_id','manager_id','calendar_version_id',
      'role_title','start_date','end_date_exclusive','reason']
    when 'replace' then array['action','id','employee_id','spell_id','department_id','manager_id','calendar_version_id',
      'role_title','start_date','end_date_exclusive','reason','replace_revision_id']
    else array['action','id','employee_id','start_date','end_date_exclusive','reason','replace_revision_id'] end;
  if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(v_allowed))
    or coalesce(jsonb_typeof(p_payload->'reason'),'null')<>'string'
    or length(btrim(p_payload->>'reason')) not between 1 and 1000
    or coalesce(p_payload->>'start_date','') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception using errcode='22023',message='ORGANIZATION_COMMAND_FIELDS_INVALID';
  end if;
  v_id:=(p_payload->>'id')::uuid;v_start:=(p_payload->>'start_date')::date;
  v_end:=nullif(p_payload->>'end_date_exclusive','')::date;v_reason:=btrim(p_payload->>'reason');
  if v_start<'0001-01-01'::date or v_start>'9999-12-31'::date or not isfinite(v_start)
    or (v_end is not null and (not isfinite(v_end) or v_end<=v_start or v_end>'9999-12-31'::date)) then
    raise exception using errcode='22023',message='ORGANIZATION_DATES_INVALID';
  end if;
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.organization.view');
  perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.organization.manage');
  -- Hierarchy/manager changes can affect every branch: entity-wide management is required.
  perform core.require_permission(p_tenant_id,'people.organization.manage',p_legal_entity_id,null);
  if v_action in ('assign','replace','end_assignment','withdraw_assignment') then
    v_employee:=(p_payload->>'employee_id')::uuid;v_manager:=nullif(p_payload->>'manager_id','')::uuid;
    perform api.people_employee_detail(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_start);
    perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.calendars.view');
    if v_employee is null or v_end is null or v_end-v_start>1830 or
      (v_action not in ('end_assignment','withdraw_assignment') and (coalesce(jsonb_typeof(p_payload->'role_title'),'null')<>'string'
      or length(btrim(p_payload->>'role_title')) not between 1 and 160)) then
      raise exception using errcode='22023',message='ORGANIZATION_ASSIGNMENT_INVALID';
    end if;
  end if;
  v_hash:=core.wave3_request_hash('people.organization.'||v_action,p_command_id,
    p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
  v_replay:=core.wave3_replay(p_tenant_id,'people.organization.'||v_action,p_command_id,p_idempotency_key,v_hash);
  if v_replay is not null then return v_replay; end if;
  if v_employee is not null then
    perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
      and id in (v_employee,v_manager) order by id for update;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('people.organization:'||p_tenant_id||':'||p_legal_entity_id,0));
  if v_action like 'department_%' then
    v_name:=btrim(p_payload->>'name');v_parent:=nullif(p_payload->>'parent_id','')::uuid;
    v_revision:=(p_payload->>'revision_id')::uuid;
    if v_revision is null or coalesce(jsonb_typeof(p_payload->'name'),'null')<>'string'
      or length(v_name) not between 1 and 160 then
      raise exception using errcode='22023',message='DEPARTMENT_FIELDS_INVALID';
    end if;
    if v_action='department_create' then
      if p_expected_version is distinct from 0 or coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'
        or (select count(*) from people.departments where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id)>=2000 then
        raise exception using errcode='22023',message='DEPARTMENT_CREATE_INVALID';
      end if;
      insert into people.departments(id,tenant_id,legal_entity_id,code)
      values(v_id,p_tenant_id,p_legal_entity_id,p_payload->>'code');
    else
      select version into v_current from people.departments where id=v_id
        and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id for update;
      if not found then raise exception using errcode='P0002',message='DEPARTMENT_NOT_FOUND'; end if;
      perform core.wave3_assert_expected_version(v_current,p_expected_version,'{}');
      select * into v_old from people.department_revisions where id=(p_payload->>'replace_revision_id')::uuid
        and department_id=v_id and superseded_at is null;
      if not found or not daterange(v_old.start_date,v_old.end_date_exclusive,'[)') @> daterange(v_start,v_end,'[)') then
        raise exception using errcode='22023',message='DEPARTMENT_REPLACEMENT_INVALID';
      end if;
      v_before:=jsonb_build_object('id',v_id,'version',v_current,'revision_id',v_old.id);
      if exists(select 1 from people.organization_consumptions c join people.organization_assignments o on o.id=c.revision_id
        where o.department_id=v_id and daterange(c.start_date,c.end_date_exclusive,'[)') && daterange(v_start,v_end,'[)')) then
        raise exception using errcode='55000',message='ORGANIZATION_CONSUMED_IMPACT_REQUIRED';
      end if;
      update people.department_revisions set superseded_at=clock_timestamp() where id=v_old.id;
      if v_old.start_date<v_start then
        insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,parent_id,name,
          start_date,end_date_exclusive,reason,recorded_by,supersedes_id)
        values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,v_id,v_old.parent_id,v_old.name,
          v_old.start_date,v_start,v_reason,v_actor,v_old.id);
      end if;
      if v_end is not null and (v_old.end_date_exclusive is null or v_end<v_old.end_date_exclusive) then
        insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,parent_id,name,
          start_date,end_date_exclusive,reason,recorded_by,supersedes_id)
        values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,v_id,v_old.parent_id,v_old.name,
          v_end,v_old.end_date_exclusive,v_reason,v_actor,v_old.id);
      end if;
      update people.departments set version=version+1 where id=v_id;
    end if;
    insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,parent_id,name,
      start_date,end_date_exclusive,reason,recorded_by,supersedes_id)
    values(v_revision,p_tenant_id,p_legal_entity_id,v_id,v_parent,v_name,v_start,v_end,v_reason,v_actor,
      case when v_action='department_revise' then v_old.id end);
    select jsonb_build_object('id',id,'tenant_id',tenant_id,'legal_entity_id',legal_entity_id,
      'code',code,'version',version,'revision_id',v_revision)
      into v_entity from people.departments where id=v_id;
  else
    select version into v_current from people.employees where id=v_employee;
    perform core.wave3_assert_expected_version(v_current,p_expected_version,'{}');
    if v_action in ('replace','end_assignment','withdraw_assignment') then
      select * into v_old_org from people.organization_assignments where id=(p_payload->>'replace_revision_id')::uuid
        and employee_id=v_employee and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
        and branch_id=p_branch_id and superseded_at is null;
      -- Full revision replacement retains its original dates. Partial changes use
      -- explicit successor revisions rather than silently trimming original facts.
      if not found or v_start<>v_old_org.start_date
        or (v_action in ('replace','withdraw_assignment') and v_end<>v_old_org.end_date_exclusive)
        or (v_action='end_assignment' and v_end>=v_old_org.end_date_exclusive) then
        raise exception using errcode='22023',message='ORGANIZATION_REPLACEMENT_INVALID';
      end if;
      v_before:=people.organization_assignment_payload(v_old_org.id);
      if v_action='withdraw_assignment' and v_start <=
        (clock_timestamp() at time zone (select timezone from core.legal_entities where id=p_legal_entity_id))::date then
        raise exception using errcode='55000',message='ORGANIZATION_FUTURE_WITHDRAWAL_REQUIRED';
      end if;
      if exists(select 1 from people.organization_consumptions c where c.revision_id=v_old_org.id
        and (v_action in ('replace','withdraw_assignment') or c.end_date_exclusive>v_end)) then
        raise exception using errcode='55000',message='ORGANIZATION_CONSUMED_IMPACT_REQUIRED';
      end if;
      update people.organization_assignments set superseded_at=clock_timestamp() where id=v_old_org.id;
    end if;
    if v_action='withdraw_assignment' then
      insert into people.organization_withdrawals(id,tenant_id,legal_entity_id,branch_id,employee_id,revision_id,reason,recorded_by)
        values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_old_org.id,v_reason,v_actor);
      update people.employees set version=version+1,updated_by=v_actor,updated_at=clock_timestamp() where id=v_employee;
      select jsonb_build_object('id',w.id,'tenant_id',w.tenant_id,'legal_entity_id',w.legal_entity_id,'branch_id',w.branch_id,
        'employee_id',w.employee_id,'revision_id',w.revision_id,'reason',w.reason,'recorded_by',w.recorded_by,
        'recorded_at',w.recorded_at,'employee_version',v_current+1) into v_entity from people.organization_withdrawals w where id=v_id;
    else
    insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,
      department_id,manager_id,calendar_version_id,role_title,start_date,end_date_exclusive,reason,recorded_by,supersedes_id)
    values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,
      case when v_action='end_assignment' then v_old_org.spell_id else (p_payload->>'spell_id')::uuid end,
      case when v_action='end_assignment' then v_old_org.department_id else (p_payload->>'department_id')::uuid end,
      case when v_action='end_assignment' then v_old_org.manager_id else v_manager end,
      case when v_action='end_assignment' then v_old_org.calendar_version_id else (p_payload->>'calendar_version_id')::uuid end,
      case when v_action='end_assignment' then v_old_org.role_title else btrim(p_payload->>'role_title') end,
      v_start,v_end,v_reason,v_actor,case when v_action in ('replace','end_assignment') then v_old_org.id end);
    update people.employees set version=version+1,updated_by=v_actor,updated_at=clock_timestamp() where id=v_employee;
    v_entity:=people.organization_assignment_payload(v_id)||jsonb_build_object('employee_version',v_current+1);
    end if;
  end if;
  perform people.assert_organization(p_tenant_id,p_legal_entity_id);
  return core.wave3_finish_command(p_tenant_id,'people.organization.'||v_action,p_command_id,
    case when v_employee is null then 'people.department' else 'people.organization' end,
    v_id,p_idempotency_key,v_hash,v_before,v_entity,p_legal_entity_id,p_branch_id);
end $$;

alter table people.departments enable row level security;
alter table people.departments force row level security;
alter table people.department_revisions enable row level security;
alter table people.department_revisions force row level security;
alter table people.organization_assignments enable row level security;
alter table people.organization_assignments force row level security;
alter table people.organization_consumptions enable row level security;
alter table people.organization_consumptions force row level security;
alter table people.organization_withdrawals enable row level security;
alter table people.organization_withdrawals force row level security;
revoke all on people.departments,people.department_revisions,people.organization_assignments,people.organization_consumptions,
  people.organization_withdrawals from public,anon,authenticated;
revoke all on function people.guard_organization_revision(),people.assert_organization(uuid,uuid),
  people.guard_organization_consumption(),people.consume_organization(uuid,uuid,uuid,uuid,text,uuid,date,date),
  api.people_organization_department(uuid,uuid,uuid,uuid,date),
  people.check_organization_compatibility(),people.organization_assignment_payload(uuid),
  api.people_organization_departments(uuid,uuid,uuid,date,text,uuid),
  api.people_organization_employee(uuid,uuid,uuid,uuid,date,uuid),
  api.people_organization_department_history(uuid,uuid,uuid,uuid,uuid),
  api.people_organization_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.people_organization_departments(uuid,uuid,uuid,date,text,uuid),
  api.people_organization_department(uuid,uuid,uuid,uuid,date),
  api.people_organization_employee(uuid,uuid,uuid,uuid,date,uuid),
  api.people_organization_department_history(uuid,uuid,uuid,uuid,uuid),
  api.people_organization_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

-- W4-03A synthetic attendance and the shared payable interval arbiter.
-- Candidate only; depends on W4-02A organization and IANA resolver installation.
-- No existing role, plan, subscriber or employee/calendar fact is changed.
create extension if not exists btree_gist with schema extensions;

insert into core.permissions(code,module,description,privileged) values
 ('people.attendance.view','people','Read scoped attendance and work history',false),
 ('people.attendance.manage','people','Prepare scoped attendance revisions',true),
 ('people.attendance.import','people','Import immutable raw clock events',true),
 ('people.attendance.approve','people','Independently decide attendance',true),
 ('people.work_claims.view','people','Read authorized payable interval claims',false)
on conflict(code) do nothing;

create table people.raw_clock_events(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,
 source_system text not null check(length(btrim(source_system)) between 1 and 80),
 source_key text not null check(length(btrim(source_key)) between 1 and 160),
 observed_utc timestamptz not null,checksum text not null check(checksum ~ '^[a-f0-9]{64}$'),
 imported_by uuid not null references auth.users(id),imported_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,source_system,source_key),unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index raw_clock_events_scope_idx on people.raw_clock_events(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index raw_clock_events_actor_idx on people.raw_clock_events(imported_by);

create table people.attendance_entries(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 current_revision_id uuid not null,
 status text not null check(status in ('draft','submitted','approved','rejected','cancelled')),
 submitted_by uuid references auth.users(id),decided_by uuid references auth.users(id),
 active_claim_id uuid,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index attendance_entries_scope_idx on people.attendance_entries(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index attendance_entries_creator_idx on people.attendance_entries(created_by);
create index attendance_entries_submitter_idx on people.attendance_entries(submitted_by);
create index attendance_entries_decider_idx on people.attendance_entries(decided_by);

create table people.attendance_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,entry_id uuid not null,
 version bigint not null check(version between 1 and 9007199254740991),
 calendar_version_id uuid not null,
 start_local timestamp not null,start_offset_seconds integer not null,
 end_local timestamp not null,end_offset_seconds integer not null,
 start_utc timestamptz not null,end_utc timestamptz not null,
 breaks jsonb not null default '[]'::jsonb,
 gross_seconds bigint not null check(gross_seconds between 1 and 129600),
 break_seconds bigint not null check(break_seconds>=0),
 payable_seconds bigint not null check(payable_seconds>0 and payable_seconds<=129600),
 raw_start_id uuid,raw_end_id uuid,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 supersedes_revision_id uuid,
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,entry_id,version),
 unique(tenant_id,legal_entity_id,employee_id,entry_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,entry_id)
  references people.attendance_entries(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id)
  references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,raw_start_id)
  references people.raw_clock_events(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,raw_end_id)
  references people.raw_clock_events(tenant_id,legal_entity_id,employee_id,id),
 foreign key(supersedes_revision_id) references people.attendance_revisions(id),
 check(end_utc>start_utc and gross_seconds=extract(epoch from end_utc-start_utc)::bigint
   and gross_seconds=break_seconds+payable_seconds),
 check((raw_start_id is null and raw_end_id is null) or
   (raw_start_id is not null and raw_end_id is not null and raw_start_id<>raw_end_id))
);
create index attendance_revisions_entry_idx on people.attendance_revisions(tenant_id,legal_entity_id,entry_id,id);
create index attendance_revisions_calendar_idx on people.attendance_revisions(tenant_id,legal_entity_id,calendar_version_id);
create index attendance_revisions_raw_start_idx on people.attendance_revisions(raw_start_id);
create index attendance_revisions_raw_end_idx on people.attendance_revisions(raw_end_id);
create index attendance_revisions_actor_idx on people.attendance_revisions(recorded_by);
create index attendance_revisions_supersedes_idx on people.attendance_revisions(supersedes_revision_id);
alter table people.attendance_entries add foreign key(tenant_id,legal_entity_id,employee_id,id,current_revision_id)
 references people.attendance_revisions(tenant_id,legal_entity_id,employee_id,entry_id,id)
 deferrable initially deferred;

create table people.work_claims(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,
 source_kind text not null check(source_kind in ('attendance','project','service','leave')),
 source_id uuid not null,
 start_utc timestamptz not null,end_utc timestamptz not null,
 gross_seconds bigint not null check(gross_seconds between 1 and 129600),
 break_seconds bigint not null check(break_seconds>=0),
 payable_seconds bigint not null check(payable_seconds>=0),
 calendar_version_id uuid not null,
 active boolean not null default true,revoked_at timestamptz,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,id),
 unique(tenant_id,legal_entity_id,source_kind,source_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id)
  references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 check(end_utc>start_utc and gross_seconds=extract(epoch from end_utc-start_utc)::bigint),
 check((source_kind='leave' and break_seconds=0 and payable_seconds=0) or
   (source_kind<>'leave' and gross_seconds=break_seconds+payable_seconds)),
 check(active=(revoked_at is null)),
 check((source_kind='leave' and payable_seconds=0) or
   (source_kind<>'leave' and payable_seconds>0))
);
create index work_claims_scope_idx on people.work_claims(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index work_claims_calendar_idx on people.work_claims(tenant_id,legal_entity_id,calendar_version_id);
create index work_claims_creator_idx on people.work_claims(created_by);
create table people.work_claim_segments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 employee_id uuid not null,claim_id uuid not null,
 start_utc timestamptz not null,end_utc timestamptz not null,
 active boolean not null default true,
 foreign key(tenant_id,legal_entity_id,employee_id,claim_id)
  references people.work_claims(tenant_id,legal_entity_id,employee_id,id),
 check(end_utc>start_utc),
 exclude using gist(employee_id extensions.gist_uuid_ops with =,
   tstzrange(start_utc,end_utc,'[)') with &&) where(active)
);
create index work_claim_segments_claim_idx on people.work_claim_segments(claim_id);
create table people.work_allocations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,claim_id uuid not null,
 source_kind text not null check(source_kind in ('project','service')),
 source_id uuid not null,start_utc timestamptz not null,end_utc timestamptz not null,
 active boolean not null default true,revoked_at timestamptz,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,source_kind,source_id),
 foreign key(tenant_id,legal_entity_id,employee_id,claim_id)
  references people.work_claims(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(end_utc>start_utc and active=(revoked_at is null)),
 exclude using gist(employee_id extensions.gist_uuid_ops with =,
  tstzrange(start_utc,end_utc,'[)') with &&) where(active)
);
create index work_allocations_claim_idx on people.work_allocations(claim_id);
create index work_allocations_scope_idx on people.work_allocations(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index work_allocations_actor_idx on people.work_allocations(created_by);
create table people.work_input_seals(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 employee_id uuid not null,run_id uuid not null,claim_id uuid not null,
 source_version bigint not null check(source_version>0),seconds bigint not null check(seconds>=0),
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),sealed_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,run_id,claim_id),
 foreign key(tenant_id,legal_entity_id,employee_id,claim_id)
  references people.work_claims(tenant_id,legal_entity_id,employee_id,id)
);
create index work_input_seals_claim_idx on people.work_input_seals(claim_id);

create table people.attendance_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,entry_id uuid not null,revision_id uuid not null,
 action text not null check(action in ('create','correct','submit','approve','reject','cancel')),
 before_status text,after_status text not null,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 command_id uuid not null,unique(tenant_id,legal_entity_id,command_id),
 foreign key(tenant_id,legal_entity_id,employee_id,entry_id,revision_id)
  references people.attendance_revisions(tenant_id,legal_entity_id,employee_id,entry_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index attendance_events_entry_idx on people.attendance_events(tenant_id,legal_entity_id,branch_id,entry_id,id);
create index attendance_events_actor_idx on people.attendance_events(actor_id);

do $$declare v_table regclass;begin
 foreach v_table in array array[
  'people.raw_clock_events'::regclass,'people.attendance_entries'::regclass,
  'people.attendance_revisions'::regclass,'people.work_claims'::regclass,
  'people.work_claim_segments'::regclass,'people.work_allocations'::regclass,
  'people.work_input_seals'::regclass,
  'people.attendance_events'::regclass] loop
  execute format('alter table %s enable row level security',v_table);
  execute format('alter table %s force row level security',v_table);
  execute format('revoke all on %s from public,anon,authenticated',v_table);
 end loop;
end $$;

create function people.work_history_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='UPDATE' and tg_table_name='work_claims' then
  if old.active and not new.active and new.revoked_at is not null
   and (to_jsonb(new)-'active'-'revoked_at')=(to_jsonb(old)-'active'-'revoked_at') then
   return new;end if;
 elsif tg_op='UPDATE' and tg_table_name='work_claim_segments' then
  if old.active and not new.active
   and (to_jsonb(new)-'active')=(to_jsonb(old)-'active') then return new;end if;
 elsif tg_op='UPDATE' and tg_table_name='work_allocations' then
  if old.active and not new.active and new.revoked_at is not null
   and (to_jsonb(new)-'active'-'revoked_at')=(to_jsonb(old)-'active'-'revoked_at') then
   return new;end if;
 end if;
 raise exception using errcode='55000',message='WORK_HISTORY_IMMUTABLE';
end $$;
create trigger raw_clock_immutable before update or delete on people.raw_clock_events
 for each row execute function people.work_history_guard();
create trigger attendance_revision_immutable before update or delete on people.attendance_revisions
 for each row execute function people.work_history_guard();
create trigger attendance_event_immutable before update or delete on people.attendance_events
 for each row execute function people.work_history_guard();
create trigger work_claim_guard before update or delete on people.work_claims
 for each row execute function people.work_history_guard();
create trigger work_segment_guard before update or delete on people.work_claim_segments
 for each row execute function people.work_history_guard();
create trigger work_allocation_guard before update or delete on people.work_allocations
 for each row execute function people.work_history_guard();
create trigger work_seal_immutable before update or delete on people.work_input_seals
 for each row execute function people.work_history_guard();

create function people.work_break_seconds(p_start timestamptz,p_end timestamptz,p_breaks jsonb)
returns bigint language plpgsql immutable set search_path='' as $$
declare v jsonb;v_start timestamptz;v_end timestamptz;v_cursor timestamptz:=p_start;
 v_seconds bigint:=0;begin
 if p_start is null or p_end is null or p_end<=p_start
  or extract(epoch from p_start)%1<>0 or extract(epoch from p_end)%1<>0
  or p_end-p_start>interval '36 hours'
  or coalesce(jsonb_typeof(p_breaks),'null')<>'array'
  or jsonb_array_length(p_breaks)>16 then
  raise exception using errcode='22023',message='WORK_INTERVAL_INVALID';end if;
 for v in select value from jsonb_array_elements(p_breaks) loop
  if jsonb_typeof(v)<>'object' or not(v ? 'start_utc' and v ? 'end_utc')
   or (select count(*) from jsonb_object_keys(v))<>2
   or coalesce(v->>'start_utc','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
   or coalesce(v->>'end_utc','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' then
   raise exception using errcode='22023',message='WORK_BREAK_INVALID';end if;
  v_start:=(v->>'start_utc')::timestamptz;v_end:=(v->>'end_utc')::timestamptz;
  if v_start<v_cursor or v_end<=v_start or v_end>p_end
   or extract(epoch from v_start)%1<>0 or extract(epoch from v_end)%1<>0 then
   raise exception using errcode='22023',message='WORK_BREAK_INVALID';end if;
  v_seconds:=v_seconds+extract(epoch from v_end-v_start)::bigint;
  v_cursor:=v_end;
 end loop;
 if v_seconds>=extract(epoch from p_end-p_start)::bigint then
  raise exception using errcode='22023',message='WORK_BREAK_INVALID';end if;
 return v_seconds;
end $$;

create function people.work_local_coverage(p_t uuid,p_e uuid,p_b uuid,p_employee uuid,
 p_calendar_version uuid,p_start_local timestamp,p_end_local timestamp)
returns void language plpgsql security definer set search_path='' as $$
declare v_start date;v_end date;begin
 if p_start_local is null or p_end_local is null
  or p_start_local<'0001-01-01'::timestamp or p_end_local>='10000-01-01'::timestamp then
  raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
 v_start:=p_start_local::date;
 v_end:=greatest((p_end_local-interval '1 microsecond')::date+1,v_start+1);
 if v_end-v_start>3 then raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
 if not exists(select 1 from people.organization_assignments o
  join people.work_calendar_versions c on c.id=o.calendar_version_id
  where o.tenant_id=p_t and o.legal_entity_id=p_e and o.branch_id=p_b
   and o.employee_id=p_employee and o.calendar_version_id=p_calendar_version
   and o.superseded_at is null
   and daterange(o.start_date,o.end_date_exclusive,'[)') @> daterange(v_start,v_end,'[)')
   and daterange(c.start_date,c.end_date_exclusive,'[)') @> daterange(v_start,v_end,'[)'))
  or not exists(select 1 from people.employment_assignments a
   join people.employment_spells s on s.id=a.spell_id
   where a.tenant_id=p_t and a.legal_entity_id=p_e and a.branch_id=p_b
    and a.employee_id=p_employee
    and daterange(a.start_date,a.end_date_exclusive,'[)') @> daterange(v_start,v_end,'[)')
    and daterange(s.start_date,s.end_date_exclusive,'[)') @> daterange(v_start,v_end,'[)')) then
  raise exception using errcode='55000',message='WORK_COVERAGE_REQUIRED';end if;
end $$;

create function people.make_work_claim(p_t uuid,p_e uuid,p_b uuid,p_employee uuid,
 p_kind text,p_source uuid,p_start timestamptz,p_end timestamptz,p_breaks jsonb,
 p_calendar_version uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid();v_break bigint;v_gross bigint;
 v jsonb;v_cursor timestamptz:=p_start;v_start timestamptz;v_end timestamptz;begin
 if p_kind not in ('attendance','project','service','leave') or p_source is null
  or p_actor is null or p_employee is null or p_calendar_version is null then
  raise exception using errcode='22023',message='WORK_CLAIM_INVALID';end if;
 v_break:=people.work_break_seconds(p_start,p_end,p_breaks);
 v_gross:=extract(epoch from p_end-p_start)::bigint;
 if p_kind='leave' and v_break<>0 then
  raise exception using errcode='22023',message='WORK_CLAIM_INVALID';end if;
 insert into people.work_claims(id,tenant_id,legal_entity_id,branch_id,employee_id,
  source_kind,source_id,start_utc,end_utc,gross_seconds,break_seconds,payable_seconds,
  calendar_version_id,created_by)
 values(v_id,p_t,p_e,p_b,p_employee,p_kind,p_source,p_start,p_end,v_gross,v_break,
  case when p_kind='leave' then 0 else v_gross-v_break end,p_calendar_version,p_actor);
 if p_kind='leave' then
  insert into people.work_claim_segments(tenant_id,legal_entity_id,employee_id,claim_id,start_utc,end_utc)
   values(p_t,p_e,p_employee,v_id,p_start,p_end);
 else
  for v in select value from jsonb_array_elements(p_breaks) loop
   v_start:=(v->>'start_utc')::timestamptz;v_end:=(v->>'end_utc')::timestamptz;
   if v_start>v_cursor then
    insert into people.work_claim_segments(tenant_id,legal_entity_id,employee_id,claim_id,start_utc,end_utc)
     values(p_t,p_e,p_employee,v_id,v_cursor,v_start);end if;
   v_cursor:=v_end;
  end loop;
  if v_cursor<p_end then
   insert into people.work_claim_segments(tenant_id,legal_entity_id,employee_id,claim_id,start_utc,end_utc)
    values(p_t,p_e,p_employee,v_id,v_cursor,p_end);end if;
 end if;
 return v_id;
end $$;

create function people.revoke_work_claim(p_t uuid,p_e uuid,p_employee uuid,p_claim uuid)
returns void language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from people.work_allocations where tenant_id=p_t and legal_entity_id=p_e
  and employee_id=p_employee and claim_id=p_claim and active) then
  raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
 if exists(select 1 from people.work_input_seals where tenant_id=p_t and legal_entity_id=p_e
  and employee_id=p_employee and claim_id=p_claim) then
  raise exception using errcode='55000',message='PAYROLL_INPUT_SEALED';end if;
 update people.work_claims set active=false,revoked_at=clock_timestamp()
 where tenant_id=p_t and legal_entity_id=p_e and employee_id=p_employee
  and id=p_claim and active;
 if not found then raise exception using errcode='55000',message='WORK_CLAIM_NOT_ACTIVE';end if;
 update people.work_claim_segments set active=false where claim_id=p_claim and active;
end $$;

create function people.allocate_work(p_t uuid,p_e uuid,p_b uuid,p_employee uuid,
 p_claim uuid,p_source_kind text,p_source uuid,p_start timestamptz,p_end timestamptz,p_actor uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_claim people.work_claims%rowtype;v_id uuid:=gen_random_uuid();begin
 if p_source_kind not in ('project','service') or p_source is null or p_actor is null
  or p_start is null or p_end is null or p_end<=p_start
  or extract(epoch from p_start)%1<>0 or extract(epoch from p_end)%1<>0 then
  raise exception using errcode='22023',message='WORK_ALLOCATION_INVALID';end if;
 perform id from people.employees where tenant_id=p_t and legal_entity_id=p_e
  and id=p_employee for update;
 select * into v_claim from people.work_claims where tenant_id=p_t and legal_entity_id=p_e
  and branch_id=p_b and employee_id=p_employee and id=p_claim and active for update;
 if v_claim.id is null or v_claim.source_kind='leave'
  or not exists(select 1 from people.work_claim_segments s where s.claim_id=p_claim and s.active
   and tstzrange(s.start_utc,s.end_utc,'[)') @> tstzrange(p_start,p_end,'[)')) then
  raise exception using errcode='55000',message='WORK_ALLOCATION_SOURCE_INVALID';end if;
 insert into people.work_allocations(id,tenant_id,legal_entity_id,branch_id,
  employee_id,claim_id,source_kind,source_id,start_utc,end_utc,created_by)
 values(v_id,p_t,p_e,p_b,p_employee,p_claim,p_source_kind,p_source,p_start,p_end,p_actor);
 return v_id;
end $$;
create function people.revoke_work_allocation(p_t uuid,p_e uuid,p_employee uuid,p_allocation uuid)
returns void language plpgsql security definer set search_path='' as $$begin
 update people.work_allocations set active=false,revoked_at=clock_timestamp()
 where tenant_id=p_t and legal_entity_id=p_e and employee_id=p_employee
  and id=p_allocation and active;
 if not found then raise exception using errcode='55000',message='WORK_ALLOCATION_NOT_ACTIVE';end if;
end $$;

alter table people.attendance_entries add foreign key(tenant_id,legal_entity_id,employee_id,active_claim_id)
 references people.work_claims(tenant_id,legal_entity_id,employee_id,id);

create function people.attendance_payload(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',e.id,'tenant_id',e.tenant_id,'legal_entity_id',e.legal_entity_id,
  'branch_id',e.branch_id,'employee_id',e.employee_id,'version',e.version,
  'status',e.status,'submitted_by',e.submitted_by,'decided_by',e.decided_by,
  'active_claim_id',e.active_claim_id,'created_by',e.created_by,'created_at',e.created_at,
  'revision',jsonb_build_object('id',r.id,'version',r.version,
   'calendar_version_id',r.calendar_version_id,'start_local',r.start_local,
   'start_offset_seconds',r.start_offset_seconds,'end_local',r.end_local,
   'end_offset_seconds',r.end_offset_seconds,'start_utc',r.start_utc,'end_utc',r.end_utc,
   'breaks',r.breaks,'gross_seconds',r.gross_seconds,'break_seconds',r.break_seconds,
   'payable_seconds',r.payable_seconds,'raw_start_id',r.raw_start_id,'raw_end_id',r.raw_end_id,
   'reason',r.reason,'supersedes_revision_id',r.supersedes_revision_id,
   'recorded_by',r.recorded_by,'recorded_at',r.recorded_at))
 from people.attendance_entries e join people.attendance_revisions r on r.id=e.current_revision_id
 where e.id=p_id
$$;

create function api.people_attendance_entries(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_employee_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.view');
 if p_employee_id is null or not exists(select 1 from people.employment_assignments
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='ATTENDANCE_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(people.attendance_payload(q.id) order by q.id),'[]'::jsonb)
 into v_items from(select id from people.attendance_entries where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',p_employee_id,'items',v_items-50,
  'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_attendance_detail(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_entry_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_entry people.attendance_entries%rowtype;v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.view');
 select * into v_entry from people.attendance_entries where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_entry_id;
 if not found then raise exception using errcode='P0002',message='ATTENDANCE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'version',q.version,
  'start_utc',q.start_utc,'end_utc',q.end_utc,'breaks',q.breaks,
  'payable_seconds',q.payable_seconds,'reason',q.reason,
  'supersedes_revision_id',q.supersedes_revision_id,'recorded_by',q.recorded_by,
  'recorded_at',q.recorded_at) order by q.id),'[]'::jsonb) into v_items
 from(select * from people.attendance_revisions where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and entry_id=p_entry_id and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'entry',people.attendance_payload(p_entry_id),
  'history',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_attendance_raw_events(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_employee_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.view');
 if p_employee_id is null or not exists(select 1 from people.employment_assignments
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='ATTENDANCE_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'source_system',q.source_system,
  'source_key',q.source_key,'observed_utc',q.observed_utc,'checksum',q.checksum,
  'imported_by',q.imported_by,'imported_at',q.imported_at) order by q.id),'[]'::jsonb)
 into v_items from(select * from people.raw_clock_events where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',p_employee_id,'items',v_items-50,
  'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_work_claims(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_employee_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.work_claims.view');
 if p_employee_id is null then raise exception using errcode='22023',message='WORK_EMPLOYEE_REQUIRED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'source_kind',q.source_kind,
  'source_id',q.source_id,'start_utc',q.start_utc,'end_utc',q.end_utc,
  'gross_seconds',q.gross_seconds,'break_seconds',q.break_seconds,
  'payable_seconds',q.payable_seconds,'active',q.active,'revoked_at',q.revoked_at,
  'calendar_version_id',q.calendar_version_id) order by q.id),'[]'::jsonb)
 into v_items from(select * from people.work_claims where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',p_employee_id,'items',v_items-50,
  'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_attendance_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_action text:=p_payload->>'action';v_id uuid;
 v_employee_id uuid;v_allowed text[];v_cap text;v_hash text;v_replay jsonb;
 v_entry people.attendance_entries%rowtype;v_rev people.attendance_revisions%rowtype;
 v_calendar people.work_calendar_versions%rowtype;v_reason text;v_before jsonb:='{}'::jsonb;
 v_after jsonb;v_start_local timestamp;v_end_local timestamp;
 v_start timestamptz;v_end timestamptz;v_breaks jsonb;v_break_seconds bigint;
 v_gross bigint;v_new_revision uuid;v_claim uuid;v_raw_start uuid;v_raw_end uuid;
 v_start_date date;v_end_date date;v_request uuid:=gen_random_uuid();begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or p_payload is null or jsonb_typeof(p_payload)<>'object'
  or p_expected_version is null or p_expected_version<0
  or p_expected_version>9007199254740991
  or v_action is null or v_action not in ('raw_import','create','correct','submit','approve','reject','cancel')
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'employee_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  raise exception using errcode='22023',message='ATTENDANCE_COMMAND_INVALID';end if;
 v_id:=(p_payload->>'id')::uuid;v_employee_id:=(p_payload->>'employee_id')::uuid;
 v_allowed:=case v_action
  when 'raw_import' then array['action','id','employee_id','source_system','source_key','observed_utc','checksum']
  when 'create' then array['action','id','employee_id','calendar_version_id','start_local',
   'start_offset_seconds','end_local','end_offset_seconds','breaks','raw_start_id','raw_end_id','reason']
  when 'correct' then array['action','id','employee_id','calendar_version_id','start_local',
   'start_offset_seconds','end_local','end_offset_seconds','breaks','raw_start_id','raw_end_id','reason']
  else array['action','id','employee_id','reason'] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(v_allowed)) then
  raise exception using errcode='22023',message='ATTENDANCE_FIELDS_INVALID';end if;
 v_cap:=case when v_action='raw_import' then 'people.attendance.import'
  when v_action in ('approve','reject','cancel') then 'people.attendance.approve'
  else 'people.attendance.manage' end;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,v_cap);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='ATTENDANCE_MFA_REQUIRED';end if;
 if not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee_id) then
  raise exception using errcode='42501',message='ATTENDANCE_SCOPE_DENIED';end if;
 v_hash:=core.wave3_request_hash('people.attendance.'||v_action,p_command_id,
  p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.attendance.'||v_action,
  p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and id=v_employee_id for update;
 if not found then raise exception using errcode='P0002',message='ATTENDANCE_EMPLOYEE_NOT_FOUND';end if;
 if v_action='raw_import' then
  if p_expected_version<>0 or length(btrim(coalesce(p_payload->>'source_system',''))) not between 1 and 80
   or length(btrim(coalesce(p_payload->>'source_key',''))) not between 1 and 160
   or coalesce(p_payload->>'checksum','') !~ '^[a-f0-9]{64}$'
   or coalesce(p_payload->>'observed_utc','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' then
   raise exception using errcode='22023',message='ATTENDANCE_RAW_INVALID';end if;
  insert into people.raw_clock_events(id,tenant_id,legal_entity_id,branch_id,employee_id,
   source_system,source_key,observed_utc,checksum,imported_by)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,
   p_payload->>'source_system',p_payload->>'source_key',(p_payload->>'observed_utc')::timestamptz,
   p_payload->>'checksum',v_actor);
  v_after:=jsonb_build_object('id',v_id,'employee_id',v_employee_id,
   'source_system',p_payload->>'source_system','source_key',p_payload->>'source_key',
   'observed_utc',p_payload->>'observed_utc','checksum',p_payload->>'checksum');
 else
  if v_action<>'create' then
   select * into v_entry from people.attendance_entries where tenant_id=p_tenant_id
    and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee_id
    and id=v_id for update;
   if not found then raise exception using errcode='P0002',message='ATTENDANCE_NOT_FOUND';end if;
   v_before:=people.attendance_payload(v_id);
   perform core.wave3_assert_expected_version(v_entry.version,p_expected_version,v_before);
   select * into v_rev from people.attendance_revisions where id=v_entry.current_revision_id;
  elsif p_expected_version<>0 then
   raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  v_reason:=btrim(coalesce(p_payload->>'reason',''));
  if length(v_reason) not between 1 and 1000 then
   raise exception using errcode='22023',message='ATTENDANCE_REASON_REQUIRED';end if;
  if v_action in ('create','correct') then
   if v_action='correct' and v_entry.status not in ('draft','rejected','approved') then
    raise exception using errcode='55000',message='ATTENDANCE_STATE_INVALID';end if;
   if coalesce(p_payload->>'start_local','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'
    or coalesce(p_payload->>'end_local','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'
    or coalesce(p_payload->>'calendar_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or coalesce(p_payload->>'start_offset_seconds','') !~ '^-?[0-9]{1,5}$'
    or coalesce(p_payload->>'end_offset_seconds','') !~ '^-?[0-9]{1,5}$' then
    raise exception using errcode='22023',message='ATTENDANCE_BOUNDARY_INVALID';end if;
   select * into v_calendar from people.work_calendar_versions where tenant_id=p_tenant_id
    and legal_entity_id=p_legal_entity_id and id=(p_payload->>'calendar_version_id')::uuid;
   if not found then raise exception using errcode='P0002',message='ATTENDANCE_CALENDAR_NOT_FOUND';end if;
   v_start_local:=(p_payload->>'start_local')::timestamp;
   v_end_local:=(p_payload->>'end_local')::timestamp;
   v_start:=people.resolve_local_instant(v_calendar.timezone,v_start_local,
    (p_payload->>'start_offset_seconds')::integer);
   v_end:=people.resolve_local_instant(v_calendar.timezone,v_end_local,
    (p_payload->>'end_offset_seconds')::integer);
   perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,
    v_calendar.id,v_start_local,v_end_local);
   v_breaks:=coalesce(p_payload->'breaks','[]'::jsonb);
   v_break_seconds:=people.work_break_seconds(v_start,v_end,v_breaks);
   v_gross:=extract(epoch from v_end-v_start)::bigint;
   v_raw_start:=nullif(p_payload->>'raw_start_id','')::uuid;
   v_raw_end:=nullif(p_payload->>'raw_end_id','')::uuid;
   if (v_raw_start is null)<>(v_raw_end is null) or
    (v_raw_start is not null and
     (not exists(select 1 from people.raw_clock_events where id=v_raw_start
       and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
       and employee_id=v_employee_id and observed_utc=v_start)
      or not exists(select 1 from people.raw_clock_events where id=v_raw_end
       and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
       and employee_id=v_employee_id and observed_utc=v_end))) then
    raise exception using errcode='22023',message='ATTENDANCE_RAW_PAIR_INVALID';end if;
   if v_action='correct' and v_entry.active_claim_id is not null then
    perform people.revoke_work_claim(p_tenant_id,p_legal_entity_id,v_employee_id,v_entry.active_claim_id);
   end if;
   v_new_revision:=gen_random_uuid();
   if v_action='create' then
    insert into people.attendance_entries(id,tenant_id,legal_entity_id,branch_id,employee_id,
     current_revision_id,status,created_by)
    values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,v_new_revision,'draft',v_actor);
   else
    update people.attendance_entries set version=version+1,current_revision_id=v_new_revision,
     status='draft',submitted_by=null,decided_by=null,active_claim_id=null where id=v_id;
   end if;
   insert into people.attendance_revisions(id,tenant_id,legal_entity_id,branch_id,employee_id,
    entry_id,version,calendar_version_id,start_local,start_offset_seconds,end_local,
    end_offset_seconds,start_utc,end_utc,breaks,gross_seconds,break_seconds,payable_seconds,
    raw_start_id,raw_end_id,reason,supersedes_revision_id,recorded_by)
   values(v_new_revision,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,v_id,
    case when v_action='create' then 1 else v_entry.version+1 end,v_calendar.id,
    v_start_local,(p_payload->>'start_offset_seconds')::integer,
    v_end_local,(p_payload->>'end_offset_seconds')::integer,v_start,v_end,
    v_breaks,v_gross,v_break_seconds,v_gross-v_break_seconds,
    v_raw_start,v_raw_end,v_reason,case when v_action='correct' then v_rev.id end,v_actor);
  elsif v_action='submit' then
   if v_entry.status not in ('draft','rejected') then
    raise exception using errcode='55000',message='ATTENDANCE_STATE_INVALID';end if;
   update people.attendance_entries set version=version+1,status='submitted',
    submitted_by=v_actor,decided_by=null where id=v_id;
  elsif v_action='approve' then
   if v_entry.status<>'submitted' or v_entry.submitted_by=v_actor or v_rev.recorded_by=v_actor then
    raise exception using errcode='55000',message='ATTENDANCE_INDEPENDENT_APPROVAL_REQUIRED';end if;
   perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,
    v_rev.calendar_version_id,v_rev.start_local,v_rev.end_local);
   v_start_date:=v_rev.start_local::date;
   v_end_date:=greatest((v_rev.end_local-interval '1 microsecond')::date+1,v_start_date+1);
   perform people.consume_organization(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,
    'attendance',v_rev.id,v_start_date,v_end_date);
   begin
    v_claim:=people.make_work_claim(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,
     'attendance',v_rev.id,v_rev.start_utc,v_rev.end_utc,v_rev.breaks,
     v_rev.calendar_version_id,v_actor);
   exception when exclusion_violation then
    raise exception using errcode='23514',message='WORK_INTERVAL_CONFLICT';
   end;
   update people.attendance_entries set version=version+1,status='approved',
    decided_by=v_actor,active_claim_id=v_claim where id=v_id;
  elsif v_action='reject' then
   if v_entry.status<>'submitted' or v_entry.submitted_by=v_actor or v_rev.recorded_by=v_actor then
    raise exception using errcode='55000',message='ATTENDANCE_INDEPENDENT_APPROVAL_REQUIRED';end if;
   update people.attendance_entries set version=version+1,status='rejected',decided_by=v_actor
    where id=v_id;
  else
   if v_entry.status<>'approved' or v_entry.active_claim_id is null then
    raise exception using errcode='55000',message='ATTENDANCE_STATE_INVALID';end if;
   perform people.revoke_work_claim(p_tenant_id,p_legal_entity_id,v_employee_id,v_entry.active_claim_id);
   update people.attendance_entries set version=version+1,status='cancelled',
    active_claim_id=null,decided_by=v_actor where id=v_id;
  end if;
  select current_revision_id into v_new_revision from people.attendance_entries where id=v_id;
  v_after:=people.attendance_payload(v_id);
  insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,
   entry_id,revision_id,action,before_status,after_status,reason,actor_id,command_id)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee_id,v_id,v_new_revision,
   v_action,v_before->>'status',v_after->>'status',v_reason,v_actor,p_command_id);
 end if;
 return core.wave3_finish_command(p_tenant_id,'people.attendance.'||v_action,p_command_id,
  case when v_action='raw_import' then 'people.raw_clock' else 'people.attendance' end,
  v_id,p_idempotency_key,v_hash,v_before,v_after,p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('employee_id',v_employee_id,'action',v_action),
  p_request_id=>v_request);
end $$;

revoke all on function people.work_history_guard(),people.work_break_seconds(timestamptz,timestamptz,jsonb),
 people.work_local_coverage(uuid,uuid,uuid,uuid,uuid,timestamp,timestamp),
 people.make_work_claim(uuid,uuid,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb,uuid,uuid),
 people.revoke_work_claim(uuid,uuid,uuid,uuid),people.attendance_payload(uuid),
 people.allocate_work(uuid,uuid,uuid,uuid,uuid,text,uuid,timestamptz,timestamptz,uuid),
 people.revoke_work_allocation(uuid,uuid,uuid,uuid),
 api.people_attendance_entries(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_detail(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_raw_events(uuid,uuid,uuid,uuid,uuid),
 api.people_work_claims(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated;
grant execute on function api.people_attendance_entries(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_detail(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_raw_events(uuid,uuid,uuid,uuid,uuid),
 api.people_work_claims(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 to authenticated;
notify pgrst,'reload schema';

-- W4-06 UNAPPLIED synthetic service candidate. No plan/role grants or provider activation.
revoke all on schema service from public,anon,authenticated;
insert into core.permissions(code,module,description,privileged) values
 ('service.configure','service','Configure synthetic equipment, coverage, SLA and maintenance',true),
 ('service.triage','service','Create and triage scoped service tickets',true),
 ('service.dispatch','service','Dispatch eligible service personnel',true),
 ('service.work','service','Accept, work and complete scoped work orders',true),
 ('service.approve','service','Independently approve service labor and close work orders',true),
 ('service.cost.view','service','Read scoped internal service cost',true),
 ('service.maintenance','service','Record readings and generate original maintenance occurrences',true),
 ('service.billing','service','Consume approved service billing sources',true)
on conflict(code) do nothing;
create table service.equipment(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),name text not null,
 identity text not null,kind text not null check(kind in('customer','asset','stock')),
 customer_id uuid,provider_id uuid,version bigint not null default 1,status text not null default 'active',
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),unique(tenant_id,legal_entity_id,identity),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(length(name) between 1 and 160 and name=btrim(name) and name !~ '[[:cntrl:]]'),
 check(length(identity) between 1 and 160 and identity=btrim(identity) and identity !~ '[[:cntrl:]]'),
 check((kind='customer' and customer_id is not null and provider_id is null) or(kind in('asset','stock') and provider_id is not null)),
 check(version between 1 and 9007199254740991 and status in('active','retired'))
);
create table service.coverage_versions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,equipment_id uuid not null,
 kind text not null check(kind in('contract','warranty')),start_date date not null,end_date_exclusive date not null,
 name text not null,evidence_reference text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),check(end_date_exclusive>start_date)
);
create table service.sla_policies(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 name text not null,calendar_version_id uuid not null,start_date date not null,end_date_exclusive date not null,
 response_seconds bigint not null check(response_seconds between 1 and 31622400),resolution_seconds bigint not null check(resolution_seconds between 1 and 31622400),
 windows jsonb not null,independent_closure boolean not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(end_date_exclusive>start_date and end_date_exclusive-start_date<=366 and response_seconds<=resolution_seconds and jsonb_typeof(windows)='array' and jsonb_array_length(windows) between 1 and 2000)
);
create table service.tickets(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,code text not null,
 name text not null,classification text not null,customer_id uuid not null,contact_id uuid,equipment_id uuid not null,coverage_id uuid,
 policy_id uuid not null,priority text not null check(priority in('low','normal','high','urgent')),owner_id uuid,
 status text not null default 'open' check(status in('open','paused','resolved','closed','cancelled')),version bigint not null default 1,
 started_utc timestamptz not null,clock_start_utc timestamptz not null,consumed_seconds bigint not null default 0,
 response_due timestamptz not null,resolution_due timestamptz not null,response_at timestamptz,resolution_at timestamptz,
 response_breached boolean not null default false,resolution_breached boolean not null default false,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,coverage_id) references service.coverage_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references service.sla_policies(tenant_id,legal_entity_id,id),
 check(version between 1 and 9007199254740991 and consumed_seconds>=0)
);
create table service.work_orders(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,ticket_id uuid not null,
 status text not null default 'planned' check(status in('planned','dispatched','accepted','working','completed','closed','cancelled')),
 version bigint not null default 1,employee_id uuid,accepted_by uuid,completed_by uuid,closed_by uuid,
 accepted_utc timestamptz,work_started_utc timestamptz,completed_utc timestamptz,closed_at timestamptz,
 resolution text,customer_confirmed boolean,exception_reason text,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,ticket_id) references service.tickets(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 check(version between 1 and 9007199254740991)
);
create table service.dispatch_bookings(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,order_id uuid not null,employee_id uuid not null,
 calendar_version_id uuid not null,start_utc timestamptz not null,end_utc timestamptz not null,active boolean not null default true,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,order_id) references service.work_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(end_utc>start_utc and end_utc-start_utc<=interval '36 hours' and extract(epoch from start_utc)%1=0 and extract(epoch from end_utc)%1=0),
 exclude using gist(employee_id with =,tstzrange(start_utc,end_utc,'[)') with &&) where(active)
);
create table service.labor(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,order_id uuid not null,employee_id uuid not null,
 calendar_version_id uuid not null,start_utc timestamptz not null,end_utc timestamptz not null,breaks jsonb not null,
 seconds bigint not null,claim_id uuid,allocation_ids uuid[] not null default '{}',owns_claim boolean not null default false,
 hourly_cost numeric(20,6) not null,amount numeric(20,6) not null,currency_code text not null references core.currencies(code),precision integer not null,
 billing_kind text not null default 'nonbillable' check(billing_kind in('billable','nonbillable')),
 hourly_billing numeric(20,6) not null default 0,billable_amount numeric(20,6) not null default 0,billing_reference text not null default 'Synthetic nonbillable work',
 digest text not null,status text not null default 'submitted' check(status in('submitted','approved','cancelled')),
 version bigint not null default 1,submitted_by uuid not null references auth.users(id),approved_by uuid references auth.users(id),
 billing_consumption_id uuid,reason text not null,created_at timestamptz not null default clock_timestamp(),
 current_revision_id uuid,
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,order_id) references service.work_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(seconds between 1 and 129600 and hourly_cost>=0 and amount>=0 and hourly_billing>=0 and billable_amount>=0 and precision between 0 and 6 and digest ~ '^[a-f0-9]{64}$'),
 check(length(billing_reference) between 1 and 160 and billing_reference=btrim(billing_reference) and billing_reference !~ '[[:cntrl:]]'),
 check(billing_kind='billable' or hourly_billing=0 and billable_amount=0)
);
create table service.labor_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 labor_id uuid not null,employee_id uuid not null,version bigint not null,correction_id uuid not null,
 supersedes_id uuid,snapshot jsonb not null,recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,labor_id,version),unique(tenant_id,legal_entity_id,labor_id,id),
 foreign key(tenant_id,legal_entity_id,labor_id) references service.labor(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(supersedes_id) references service.labor_revisions(id),
 check(version between 1 and 9007199254740991 and jsonb_typeof(snapshot)='object')
);
alter table service.labor add foreign key(tenant_id,legal_entity_id,id,current_revision_id)
 references service.labor_revisions(tenant_id,legal_entity_id,labor_id,id) deferrable initially deferred;
create index service_revision_scope on service.labor_revisions(tenant_id,legal_entity_id,branch_id,labor_id,id);
-- Allocation identity survives release/removal and points to one labor revision.
create table service.labor_allocations(
 allocation_id uuid primary key references people.work_allocations(id),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,labor_id uuid not null,revision_id uuid not null,claim_id uuid not null references people.work_claims(id),direct_claim boolean not null,
 foreign key(tenant_id,legal_entity_id,labor_id) references service.labor(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index service_allocation_revision on service.labor_allocations(tenant_id,legal_entity_id,labor_id,revision_id,allocation_id);
create table service.payroll_labor_impacts(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 labor_id uuid not null,correction_id uuid not null,original_revision_id uuid not null,replacement_revision_id uuid not null,
 mode text not null check(mode in('apply','reverse')),approved_body jsonb not null,body jsonb not null,actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,correction_id,labor_id,mode),
 foreign key(tenant_id,legal_entity_id,labor_id) references service.labor(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,labor_id,replacement_revision_id) references service.labor_revisions(tenant_id,legal_entity_id,labor_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index service_payroll_impact_scope on service.payroll_labor_impacts(tenant_id,legal_entity_id,branch_id,labor_id,correction_id);
create table service.maintenance_plans(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,equipment_id uuid not null,policy_id uuid not null,
 name text not null,basis text not null check(basis in('calendar','meter')),interval_units bigint not null,
 next_date date,next_meter bigint,version bigint not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references service.sla_policies(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(interval_units between 1 and 9007199254740991 and (basis='calendar' and interval_units<=366 and next_date is not null and next_meter is null or basis='meter' and next_meter>0 and next_date is null))
);
create table service.meter_readings(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,equipment_id uuid not null,
 kind text not null check(kind in('initial','reading','reset','rollover')),raw_value bigint not null,logical_value bigint not null,
 previous_id uuid,rollover_max bigint,observed_utc timestamptz not null,reason text not null,recorded_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,previous_id) references service.meter_readings(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(raw_value between 0 and 9007199254740991 and logical_value between 0 and 9007199254740991)
);
create unique index service_meter_initial on service.meter_readings(equipment_id) where previous_id is null;
create unique index service_meter_successor on service.meter_readings(previous_id) where previous_id is not null;
create table service.maintenance_occurrences(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,plan_id uuid not null,plan_version bigint not null,
 occurrence_key text not null,original_due_date date,original_due_meter bigint,deferred_until date,
 ticket_id uuid not null,order_id uuid not null,reading_id uuid,version bigint not null default 1,reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(plan_id,occurrence_key),
 foreign key(tenant_id,legal_entity_id,plan_id) references service.maintenance_plans(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,ticket_id) references service.tickets(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,order_id) references service.work_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,reading_id) references service.meter_readings(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table service.events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 aggregate_id uuid not null,kind text not null,version bigint not null,action text not null,reason text not null,
 facts jsonb not null,actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index service_equipment_scope on service.equipment(tenant_id,legal_entity_id,branch_id,id);
create index service_policy_scope on service.sla_policies(tenant_id,legal_entity_id,branch_id,id);
create index service_coverage_scope on service.coverage_versions(tenant_id,legal_entity_id,branch_id,equipment_id,id);
create index service_ticket_scope on service.tickets(tenant_id,legal_entity_id,branch_id,id);
create index service_order_scope on service.work_orders(tenant_id,legal_entity_id,branch_id,ticket_id,id);
create index service_dispatch_scope on service.dispatch_bookings(tenant_id,legal_entity_id,branch_id,order_id,id);
create index service_labor_scope on service.labor(tenant_id,legal_entity_id,branch_id,order_id,id);
create index service_plan_scope on service.maintenance_plans(tenant_id,legal_entity_id,branch_id,id);
create index service_meter_scope on service.meter_readings(tenant_id,legal_entity_id,branch_id,equipment_id,observed_utc desc,id);
create index service_occurrence_scope on service.maintenance_occurrences(tenant_id,legal_entity_id,branch_id,plan_id,id);
create index service_event_scope on service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,id);
do $$declare r record;begin for r in select tablename from pg_tables where schemaname='service' loop
 execute format('alter table service.%I enable row level security',r.tablename);
 execute format('alter table service.%I force row level security',r.tablename);end loop;end $$;
revoke all on all tables in schema service from public,anon,authenticated;
create function service.immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='SERVICE_HISTORY_IMMUTABLE';end $$;
create trigger service_coverage_immutable before update or delete on service.coverage_versions for each row execute function service.immutable();
create trigger service_policy_immutable before update or delete on service.sla_policies for each row execute function service.immutable();
create trigger service_meter_immutable before update or delete on service.meter_readings for each row execute function service.immutable();
create trigger service_event_immutable before update or delete on service.events for each row execute function service.immutable();
create trigger service_labor_revision_immutable before update or delete on service.labor_revisions for each row execute function service.immutable();
create trigger service_labor_allocation_immutable before update or delete on service.labor_allocations for each row execute function service.immutable();
create trigger service_payroll_impact_immutable before update or delete on service.payroll_labor_impacts for each row execute function service.immutable();
create function service.require_access(t uuid,e uuid,b uuid,cap text) returns void language plpgsql security definer set search_path='' as $$begin
 if cap is null or cap not in('service.view','service.configure','service.triage','service.dispatch','service.work','service.approve','service.cost.view','service.maintenance','service.billing') then
  raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
 perform core.wave3_require_scope(t,'service.view',e,b);perform core.wave3_require_scope(t,cap,e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code where s.tenant_id=t and p.entitlement_code='module.service' and p.enabled
  and(s.status='trialing' and s.trial_ends_at>now() or s.status='active' and(s.current_period_ends_at is null or s.current_period_ends_at>now()))) then
  raise exception using errcode='42501',message='SERVICE_ENTITLEMENT_REQUIRED';end if;
 if cap<>'service.view' and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='SERVICE_MFA_REQUIRED';end if;
end $$;
create function service.payroll_source(p_t uuid,p_e uuid,p_b uuid,p_employee uuid,p_claim uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare l service.labor%rowtype;begin
 select x.* into l from service.labor x join people.work_claims c on c.id=x.claim_id where x.tenant_id=p_t and x.legal_entity_id=p_e and x.branch_id=p_b and x.employee_id=p_employee
  and x.claim_id=p_claim and x.status='approved' and x.owns_claim and c.active and c.source_kind='service' and c.source_id=coalesce(x.current_revision_id,x.id) and c.employee_id=x.employee_id and c.branch_id=x.branch_id
  and c.payable_seconds=(service.snapshot('labor',x.id)->>'seconds')::bigint;
 if l.id is null then raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 return jsonb_build_object('source_id',coalesce(l.current_revision_id,l.id),'source_version',l.version,'paid_seconds',(service.snapshot('labor',l.id)->>'seconds')::bigint);end $$;
create function service.billing_source(p_t uuid,p_e uuid,p_b uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare l service.labor%rowtype;customer uuid;begin
 select x.* into l from service.labor x join service.work_orders w on w.id=x.order_id where x.tenant_id=p_t and x.legal_entity_id=p_e and x.branch_id=p_b and x.id=p_id
  and x.status='approved' and x.billing_kind='billable' and x.billing_consumption_id is null and w.status in('completed','closed');
 if l.id is null then raise exception using errcode='55000',message='SERVICE_BILLING_SOURCE_UNAVAILABLE';end if;
 select t.customer_id into customer from service.tickets t join service.work_orders w on w.ticket_id=t.id where w.id=l.order_id;
 return jsonb_build_object('source_id',coalesce(l.current_revision_id,l.id),'provider_source_id',l.id,'source_version',l.version,'digest',service.snapshot('labor',l.id)->>'digest','customer_id',customer,'seconds',(service.snapshot('labor',l.id)->>'seconds')::bigint,'amount',service.snapshot('labor',l.id)->>'billable_amount','currency_code',l.currency_code,'order_id',l.order_id);end $$;
create function service.consume_billing_source(p_t uuid,p_e uuid,p_b uuid,p_id uuid,p_version bigint,p_digest text,p_consumption uuid) returns void
language plpgsql security definer set search_path='' as $$declare l service.labor%rowtype;begin
 select * into l from service.labor where tenant_id=p_t and legal_entity_id=p_e and branch_id=p_b and id=p_id for update;
 if l.id is null or l.status<>'approved' or l.billing_kind<>'billable' or l.version<>p_version or service.snapshot('labor',l.id)->>'digest'<>p_digest or l.billing_consumption_id is not null or p_consumption is null
  or not exists(select 1 from service.work_orders where id=l.order_id and status in('completed','closed')) then raise exception using errcode='55000',message='SERVICE_BILLING_SOURCE_UNAVAILABLE';end if;
 update service.labor set billing_consumption_id=p_consumption where id=p_id;end $$;
create function service.public_snapshot(kind text,id uuid,p_cost boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb:=service.snapshot(kind,id);begin
 if kind='policy' then r:=r-'windows';end if;
 if kind='labor' and not p_cost then r:=r-array['hourly_cost','amount'];end if;return r;end $$;
create function service.table_for(kind text) returns text language sql immutable set search_path='' as $$select case kind
 when 'equipment' then 'equipment' when 'coverage' then 'coverage_versions' when 'policy' then 'sla_policies' when 'ticket' then 'tickets' when 'order' then 'work_orders'
 when 'labor' then 'labor' when 'plan' then 'maintenance_plans' when 'reading' then 'meter_readings' when 'occurrence' then 'maintenance_occurrences' end $$;
create function api.service_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_parent uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare items jsonb;tablename text:=service.table_for(p_kind);parent_column text;cost boolean;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');
 if tablename is null then raise exception using errcode='22023',message='SERVICE_KIND_INVALID';end if;
 cost:=core.has_permission(p_tenant_id,'service.cost.view',p_legal_entity_id,p_branch_id);
 parent_column:=case p_kind when 'coverage' then 'equipment_id' when 'order' then 'ticket_id' when 'labor' then 'order_id' when 'reading' then 'equipment_id' when 'occurrence' then 'plan_id' end;
 if p_parent is not null and parent_column is null then raise exception using errcode='22023',message='SERVICE_PARENT_INVALID';end if;
 execute format('select coalesce(jsonb_agg(service.public_snapshot($1,q.id,$6) order by q.id),''[]''::jsonb) from(select id from service.%I where tenant_id=$2 and legal_entity_id=$3 and branch_id=$4 and($5 is null or id>$5)%s order by id limit 51) q',
  tablename,case when p_parent is null then '' else format(' and %I=$7',parent_column) end)
 into items using p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,p_after,cost,p_parent;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.service_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r jsonb;events jsonb;cost boolean;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');cost:=core.has_permission(p_tenant_id,'service.cost.view',p_legal_entity_id,p_branch_id);
 r:=service.public_snapshot(p_kind,p_id,cost);
 if r is null or r->>'tenant_id'<>p_tenant_id::text or r->>'legal_entity_id'<>p_legal_entity_id::text or r->>'branch_id'<>p_branch_id::text then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('facts',case when x.kind='labor' and not cost then x.facts-array['hourly_cost','amount'] when x.kind='policy' then x.facts-'windows' else x.facts end) order by x.id),'[]') into events
 from(select * from service.events where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and aggregate_id=p_id and kind=p_kind and(p_after is null or id>p_after) order by id limit 51) x;
 return jsonb_build_object('record',r,'events',events-50,'next_cursor',case when jsonb_array_length(events)>50 then events->49->>'id' end);end $$;
create function api.service_choices(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_parent uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');
 if p_kind='customer' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select id,display_name name,version from crm.parties where tenant_id=p_tenant_id and status='active' and kind in('customer','both') and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='contact' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select id,name,version from crm.contacts where tenant_id=p_tenant_id and party_id=p_parent and status='active' and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='employee' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select x.id,x.display_name name,x.version from people.employees x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and exists(select 1 from people.employment_assignments a where a.employee_id=x.id and a.branch_id=p_branch_id and daterange(a.start_date,a.end_date_exclusive,'[)') @> current_date) and(p_after is null or x.id>p_after) order by x.id limit 51) q;
 elsif p_kind='calendar' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select v.id,c.name||' / '||v.start_date::text name,c.version from people.work_calendar_versions v join people.work_calendars c on c.id=v.calendar_id where v.tenant_id=p_tenant_id and v.legal_entity_id=p_legal_entity_id and(p_after is null or v.id>p_after) order by v.id limit 51) q;
 elsif p_kind='claim' then
  perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.work');
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(
   select x.id,employee.display_name||' / '||to_char(x.start_utc at time zone cal.timezone,'YYYY-MM-DD HH24:MI')||' to '||to_char(x.end_utc at time zone cal.timezone,'HH24:MI')||' / approved attendance' name,1::bigint version
   from people.work_claims x join people.employees employee on employee.id=x.employee_id join people.work_calendar_versions cal on cal.id=x.calendar_version_id
   join people.attendance_entries a on a.active_claim_id=x.id and a.status='approved'
   where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.employee_id=p_parent and x.active and x.source_kind='attendance'
    and(p_after is null or x.id>p_after) order by x.id limit 51) q;
 else raise exception using errcode='22023',message='SERVICE_CHOICE_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.service_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid,p_action text) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r core.command_receipts%rowtype;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,service.capability(p_action));
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and actor_id=auth.uid() and idempotency_key=p_idempotency_key and command_name='service.'||p_action;
 return case when r.idempotency_key is not null then r.response end;end $$;
create function service.text(p jsonb,n integer) returns text language plpgsql immutable set search_path='' as $$declare s text;begin
 if p is null or jsonb_typeof(p)<>'string' then raise exception using errcode='22023',message='SERVICE_TEXT_INVALID';end if;s:=p#>>'{}';
 if s<>btrim(s) or length(s) not between 1 and n or s ~ '[[:cntrl:]]' then raise exception using errcode='22023',message='SERVICE_TEXT_INVALID';end if;return s;end $$;
create function service.integer(p jsonb,maximum bigint,p_min bigint default 0) returns bigint language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'number' or p::text !~ '^(0|[1-9][0-9]*)$' or p::text::numeric not between p_min and maximum then
  raise exception using errcode='22023',message='SERVICE_INTEGER_INVALID';end if;return p::text::bigint;end $$;
create function service.utc(p jsonb) returns timestamptz language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'string' or p#>>'{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' then
  raise exception using errcode='22023',message='SERVICE_UTC_INVALID';end if;return (p#>>'{}')::timestamptz;end $$;
create function service.amount(p jsonb) returns numeric language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'string' or p#>>'{}' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then
  raise exception using errcode='22023',message='SERVICE_AMOUNT_INVALID';end if;return (p#>>'{}')::numeric;end $$;
create function service.round_ratio(n numeric,d numeric,p integer) returns numeric language plpgsql immutable set search_path='' as $$declare q numeric;r numeric;den numeric;begin
 if n<0 or d<=0 or p not between 0 and 6 or n<>trunc(n) or d<>trunc(d) then raise exception using errcode='22023',message='SERVICE_RATIO_INVALID';end if;
 den:=d*power(10::numeric,6-p);q:=div(n,den);r:=mod(n,den);if r*2>den or r*2=den and mod(q,2)=1 then q:=q+1;end if;
 return q*power(10::numeric,6-p)/1000000;end $$;
create function service.windows(t uuid,e uuid,p_calendar uuid,p_start date,p_end date,offsets jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare c people.work_calendar_versions%rowtype;d date;daypart date;x jsonb;o jsonb;boundary jsonb;sl timestamp;el timestamp;ps timestamp;pe timestamp;su timestamptz;eu timestamptz;so integer;eo integer;result jsonb:='[]';begin
 select * into c from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=p_calendar;
 if c.id is null or p_end<=p_start or p_end-p_start>366 or p_start<c.start_date or p_end>c.end_date_exclusive or coalesce(jsonb_typeof(offsets),'null')<>'array' or jsonb_array_length(offsets)>2000 then
  raise exception using errcode='22023',message='SERVICE_CALENDAR_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(offsets) q where jsonb_typeof(q)<>'object' or not(q ?& array['date','start_minute','start_offset_seconds','end_offset_seconds'])
  or exists(select 1 from jsonb_object_keys(q) k where k<>all(array['date','start_minute','start_offset_seconds','end_offset_seconds']))
  or q->>'date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or jsonb_typeof(q->'start_minute')<>'number' or q->>'start_minute' !~ '^[0-9]+$'
  or (q->>'start_minute')::integer not between 0 and 1439 or jsonb_typeof(q->'start_offset_seconds')<>'number' or jsonb_typeof(q->'end_offset_seconds')<>'number'
  or q->>'start_offset_seconds' !~ '^-?[0-9]+$' or q->>'end_offset_seconds' !~ '^-?[0-9]+$'
  or (q->>'start_offset_seconds')::integer not between -86400 and 86400 or (q->>'end_offset_seconds')::integer not between -86400 and 86400)
  or exists(select 1 from jsonb_array_elements(offsets) q group by q->>'date',q->>'start_minute' having count(*)>1) then raise exception using errcode='22023',message='SERVICE_CALENDAR_OFFSET_INVALID';end if;
 for d in select g::date from generate_series(greatest(p_start-1,c.start_date)::timestamp,(p_end-1)::timestamp,interval '1 day') g loop
  for x in select value from jsonb_array_elements(c.weekly_intervals) where(value->>'day_of_week')::integer=extract(isodow from d)::integer loop
   sl:=d::timestamp+(x->>'start_minute')::integer*interval '1 minute';el:=d::timestamp+(x->>'end_day_offset')::integer*interval '1 day'+(x->>'end_minute')::integer*interval '1 minute';
   select q into o from jsonb_array_elements(offsets) q where q->>'date'=d::text and(q->>'start_minute')::integer=(x->>'start_minute')::integer;
   for daypart in select g::date from generate_series(greatest(sl::date,p_start)::timestamp,least((el-interval '1 microsecond')::date,p_end-1)::timestamp,interval '1 day') g loop
    if exists(select 1 from jsonb_array_elements(c.date_overrides) q where q->>'date'=daypart::text and not(q->>'is_working_day')::boolean) then continue;end if;
    ps:=greatest(sl,daypart::timestamp);pe:=least(el,(daypart+1)::timestamp);so:=null;eo:=null;
    if ps=sl then so:=(o->>'start_offset_seconds')::integer;else
     select q into boundary from jsonb_array_elements(offsets) q where q->>'date'=ps::date::text and(q->>'start_minute')::integer=0;so:=(boundary->>'start_offset_seconds')::integer;end if;
    if pe=el then eo:=(o->>'end_offset_seconds')::integer;else
     select q into boundary from jsonb_array_elements(offsets) q where q->>'date'=pe::date::text and(q->>'start_minute')::integer=0;eo:=(boundary->>'start_offset_seconds')::integer;end if;
    su:=people.resolve_local_instant(c.timezone,ps,so);eu:=people.resolve_local_instant(c.timezone,pe,eo);
    if eu<=su or eu-su>interval '36 hours' then raise exception using errcode='22023',message='SERVICE_CALENDAR_INVALID';end if;
    result:=result||jsonb_build_array(jsonb_build_object('start_utc',to_char(su at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'end_utc',to_char(eu at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
     'start_local',ps,'end_local',pe,'timezone',c.timezone,'start_offset_seconds',extract(epoch from ps-(su at time zone 'UTC'))::integer,'end_offset_seconds',extract(epoch from pe-(eu at time zone 'UTC'))::integer));
   end loop;
  end loop;
 end loop;
 if jsonb_array_length(result)=0 or jsonb_array_length(result)>2000 then raise exception using errcode='22023',message='SERVICE_CALENDAR_EMPTY';end if;
 if exists(with spans as(select value,lag(value->>'end_utc') over(order by value->>'start_utc') previous from jsonb_array_elements(result)) select 1 from spans where value->>'start_utc'<previous) then raise exception using errcode='22023',message='SERVICE_CALENDAR_OVERLAP';end if;
 return (select jsonb_agg(value order by value->>'start_utc') from jsonb_array_elements(result));end $$;
create function service.elapsed(w jsonb,s timestamptz,e timestamptz) returns bigint language sql immutable set search_path='' as $$
 select coalesce(sum(greatest(0,extract(epoch from least(e,(x->>'end_utc')::timestamptz)-greatest(s,(x->>'start_utc')::timestamptz)))::bigint),0) from jsonb_array_elements(w) x $$;
create function service.due(w jsonb,s timestamptz,remaining bigint) returns timestamptz language plpgsql immutable set search_path='' as $$declare x jsonb;a timestamptz;b timestamptz;seconds bigint;begin
 if remaining<=0 then return s;end if;
 for x in select value from jsonb_array_elements(w) loop a:=greatest(s,(x->>'start_utc')::timestamptz);b:=(x->>'end_utc')::timestamptz;
  if b<=a then continue;end if;seconds:=extract(epoch from b-a)::bigint;if remaining<=seconds then return a+remaining*interval '1 second';end if;remaining:=remaining-seconds;end loop;
 raise exception using errcode='55000',message='SERVICE_SLA_HORIZON_EXHAUSTED';end $$;
create function service.check_customer(t uuid,customer uuid,contact uuid) returns void language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from crm.parties where tenant_id=t and id=customer and status='active' and kind in('customer','both')) or contact is not null and not exists(select 1 from crm.contacts where tenant_id=t and id=contact and party_id=customer and status='active') then
  raise exception using errcode='22023',message='SERVICE_CUSTOMER_INVALID';end if;end $$;
create function api.service_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability);
 return jsonb_build_object('actor_id',auth.uid(),'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'capability',p_capability,'authorized',true,
  'parts_provider',false,'billing_provider',false,'asset_provider',false,
  'currency_code',(select currency_code from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
  'precision',(select rounding_scale from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id));end $$;
create function service.capability(act text) returns text language sql immutable set search_path='' as $$select case
 when act in('equipment','coverage','policy','plan') then 'service.configure'
 when act in('ticket','pause','resume','reprioritize','evaluate','cancel_ticket') then 'service.triage'
 when act in('order','dispatch','cancel_order') then 'service.dispatch'
 when act in('accept','start','complete','labor') then 'service.work'
 when act in('approve_labor','cancel_labor','close') then 'service.approve'
 when act in('reading','generate','defer') then 'service.maintenance'
 when act in('parts_reserve','parts_issue','parts_return','bill') then 'service.billing' end $$;
create function service.fields(act text) returns text[] language sql immutable set search_path='' as $$select array['action','id','reason']||case act
 when 'equipment' then array['code','name','identity','kind','customer_id','provider_id']
 when 'coverage' then array['equipment_id','kind','name','start_date','end_date_exclusive','evidence_reference']
 when 'policy' then array['name','calendar_version_id','start_date','end_date_exclusive','response_seconds','resolution_seconds','independent_closure','offsets']
 when 'ticket' then array['code','name','classification','customer_id','contact_id','equipment_id','coverage_id','policy_id','priority','owner_id','observed_utc']
 when 'order' then array['ticket_id'] when 'dispatch' then array['employee_id','calendar_version_id','start_utc','end_utc','booking_id']
 when 'complete' then array['observed_utc','resolution','customer_confirmed','exception_reason']
 when 'accept' then array['observed_utc'] when 'start' then array['observed_utc']
 when 'labor' then array['order_id','employee_id','calendar_version_id','start_utc','end_utc','breaks','claim_id','hourly_cost','currency_code','precision','billing_kind','hourly_billing','billing_reference']
 when 'plan' then array['equipment_id','policy_id','name','basis','interval_units','next_date','next_meter']
 when 'reading' then array['equipment_id','kind','raw_value','rollover_max','observed_utc']
 when 'generate' then array['ticket_id','order_id','occurrence_id','observed_utc']
 when 'defer' then array['deferred_until'] when 'reprioritize' then array['policy_id','priority','observed_utc']
 when 'pause' then array['observed_utc'] when 'resume' then array['observed_utc'] when 'evaluate' then array['observed_utc']
 else '{}'::text[] end $$;
create function service.ticket_create(t uuid,e uuid,b uuid,id uuid,p jsonb) returns void language plpgsql security definer set search_path='' as $$
declare policy service.sla_policies%rowtype;equipment service.equipment%rowtype;at timestamptz:=service.utc(p->'observed_utc');begin
 perform service.check_customer(t,(p->>'customer_id')::uuid,(p->>'contact_id')::uuid);
 select q.* into equipment from service.equipment q where q.tenant_id=t and q.legal_entity_id=e and q.branch_id=b and q.id=(p->>'equipment_id')::uuid and q.status='active';
 select * into policy from service.sla_policies where tenant_id=t and legal_entity_id=e and branch_id=b and sla_policies.id=(p->>'policy_id')::uuid;
 if equipment.id is null or policy.id is null or equipment.customer_id is distinct from (p->>'customer_id')::uuid
  or(p->>'coverage_id') is not null and not exists(select 1 from service.coverage_versions c where c.tenant_id=t and c.legal_entity_id=e and c.branch_id=b and c.id=(p->>'coverage_id')::uuid and c.equipment_id=equipment.id
    and daterange(c.start_date,c.end_date_exclusive,'[)') @> (at at time zone (select timezone from core.legal_entities where tenant_id=t and legal_entities.id=e))::date)
  or p->>'code' !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or p->>'priority' not in('low','normal','high','urgent') or at>clock_timestamp()+interval '5 minutes' then
  raise exception using errcode='22023',message='SERVICE_TICKET_INVALID';end if;
 insert into service.tickets(id,tenant_id,legal_entity_id,branch_id,code,name,classification,customer_id,contact_id,equipment_id,coverage_id,policy_id,priority,owner_id,started_utc,clock_start_utc,response_due,resolution_due,created_by)
 values(id,t,e,b,p->>'code',service.text(p->'name',160),service.text(p->'classification',80),(p->>'customer_id')::uuid,(p->>'contact_id')::uuid,equipment.id,(p->>'coverage_id')::uuid,policy.id,p->>'priority',(p->>'owner_id')::uuid,
  at,at,service.due(policy.windows,at,policy.response_seconds),service.due(policy.windows,at,policy.resolution_seconds),auth.uid());end $$;
create function service.snapshot(kind text,id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 case kind when 'equipment' then select to_jsonb(x) into r from service.equipment x where x.id=snapshot.id;
 when 'coverage' then select to_jsonb(x)||jsonb_build_object('version',1) into r from service.coverage_versions x where x.id=snapshot.id;
 when 'policy' then select to_jsonb(x)||jsonb_build_object('version',1) into r from service.sla_policies x where x.id=snapshot.id;
 when 'ticket' then select to_jsonb(x) into r from service.tickets x where x.id=snapshot.id;
 when 'order' then select to_jsonb(x) into r from service.work_orders x where x.id=snapshot.id;
 when 'labor' then select to_jsonb(x)||jsonb_build_object('hourly_cost',x.hourly_cost::text,'amount',x.amount::text,'hourly_billing',x.hourly_billing::text,'billable_amount',x.billable_amount::text)
  ||coalesce((select v.snapshot from service.labor_revisions v where v.id=x.current_revision_id),'{}')
  ||jsonb_build_object('version',x.version,'claim_id',x.claim_id,'allocation_ids',x.allocation_ids,'current_revision_id',x.current_revision_id,'billing_consumption_id',x.billing_consumption_id,'status',x.status) into r from service.labor x where x.id=snapshot.id;
 when 'plan' then select to_jsonb(x) into r from service.maintenance_plans x where x.id=snapshot.id;
 when 'reading' then select to_jsonb(x)||jsonb_build_object('version',1) into r from service.meter_readings x where x.id=snapshot.id;
 when 'occurrence' then select to_jsonb(x) into r from service.maintenance_occurrences x where x.id=snapshot.id;
 end case;return r;end $$;
create function api.service_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
<<command_work>>
declare act text:=p_payload->>'action';cap text:=service.capability(act);id uuid;kind text;hash text;replay jsonb;reason text;before_state jsonb;after_state jsonb;event_state jsonb;
 t service.tickets%rowtype;w service.work_orders%rowtype;policy service.sla_policies%rowtype;eq service.equipment%rowtype;labor service.labor%rowtype;plan service.maintenance_plans%rowtype;meter service.meter_readings%rowtype;
 observed timestamptz;start_utc timestamptz;end_utc timestamptz;segment_cursor timestamptz;employee uuid;calendar uuid;claim uuid;allocation uuid;allocations uuid[]:='{}';owns boolean:=false;
 calendar_row people.work_calendar_versions%rowtype;seconds bigint;cost numeric;amount numeric;billrate numeric;billamount numeric;billkind text;billref text;precision integer;currency text;digest text;raw bigint;logical bigint;delta bigint;rollmax bigint;
 windows jsonb;segment record;occurrence_key text;occurrence uuid;newticket uuid;neworder uuid;version bigint:=1;begin
 if cap is null or coalesce(jsonb_typeof(p_payload),'null')<>'object' or octet_length(p_payload::text)>65536 or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(service.fields(act))) then raise exception using errcode='22023',message='SERVICE_COMMAND_INVALID';end if;
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap);
 id:=(p_payload->>'id')::uuid;reason:=service.text(p_payload->'reason',1000);
 hash:=core.wave3_request_hash('service.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'service.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 if act in('parts_reserve','parts_issue','parts_return') then raise exception using errcode='55000',message='SERVICE_PARTS_PROVIDER_UNAVAILABLE';end if;
 if act='bill' then raise exception using errcode='55000',message='SERVICE_BILLING_ADAPTER_UNAVAILABLE';end if;
 if act in('dispatch','labor') then employee:=(p_payload->>'employee_id')::uuid;
 elsif act in('approve_labor','cancel_labor') then select l.employee_id into employee from service.labor l where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.id=command_work.id;
 elsif act in('accept','start','complete','close','cancel_order') then select employee_id into employee from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=command_work.id;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 if employee is not null then perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employees.id=employee for update;end if;
 -- Entity serialization gives one lock order for ticket/order and meter/occurrence work.
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 if act in('equipment','coverage','policy','ticket','order','labor','plan','reading') and p_expected_version<>0 then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;
 if act='equipment' then kind:='equipment';perform service.text(p_payload->'name',160);perform service.text(p_payload->'identity',160);
  if p_payload->>'kind'<>'customer' then raise exception using errcode='55000',message='SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE';end if;
  perform service.check_customer(p_tenant_id,(p_payload->>'customer_id')::uuid,null);
  insert into service.equipment(id,tenant_id,legal_entity_id,branch_id,code,name,identity,kind,customer_id,provider_id,created_by)
   values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',p_payload->>'name',p_payload->>'identity',p_payload->>'kind',(p_payload->>'customer_id')::uuid,(p_payload->>'provider_id')::uuid,auth.uid());
 elsif act='coverage' then kind:='coverage';
  if not exists(select 1 from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment.id=(p_payload->>'equipment_id')::uuid and status='active') then raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
  insert into service.coverage_versions(id,tenant_id,legal_entity_id,branch_id,equipment_id,kind,start_date,end_date_exclusive,name,evidence_reference,created_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'equipment_id')::uuid,p_payload->>'kind',(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,
   service.text(p_payload->'name',160),service.text(p_payload->'evidence_reference',160),auth.uid());
 elsif act='policy' then kind:='policy';windows:=service.windows(p_tenant_id,p_legal_entity_id,(p_payload->>'calendar_version_id')::uuid,(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,p_payload->'offsets');
  if jsonb_typeof(p_payload->'independent_closure') is distinct from 'boolean' then raise exception using errcode='22023',message='SERVICE_POLICY_INVALID';end if;
  insert into service.sla_policies(id,tenant_id,legal_entity_id,branch_id,name,calendar_version_id,start_date,end_date_exclusive,response_seconds,resolution_seconds,windows,independent_closure,created_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,service.text(p_payload->'name',160),(p_payload->>'calendar_version_id')::uuid,(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,
  service.integer(p_payload->'response_seconds',31622400,1),service.integer(p_payload->'resolution_seconds',31622400,1),windows,(p_payload->>'independent_closure')::boolean,auth.uid());
 elsif act='ticket' then kind:='ticket';perform service.ticket_create(p_tenant_id,p_legal_entity_id,p_branch_id,id,p_payload);
 elsif act in('pause','resume','evaluate','reprioritize','cancel_ticket') then kind:='ticket';
  select * into t from service.tickets where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and tickets.id=command_work.id for update;
  if t.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
  if t.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  if t.status in('closed','cancelled','resolved') then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
  observed:=case when act='cancel_ticket' then date_trunc('second',clock_timestamp()) else service.utc(p_payload->'observed_utc') end;
  if observed<t.clock_start_utc or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;
  select * into policy from service.sla_policies where sla_policies.id=t.policy_id;
  t.response_breached:=t.response_breached or(t.response_at is null and t.status='open' and observed>t.response_due);
  t.resolution_breached:=t.resolution_breached or(t.resolution_at is null and t.status='open' and observed>t.resolution_due);
  if t.status='open' then t.consumed_seconds:=t.consumed_seconds+service.elapsed(policy.windows,t.clock_start_utc,observed);end if;
  if act='pause' then if t.status<>'open' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;t.status:='paused';
  elsif act='resume' then if t.status<>'paused' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;t.status:='open';
  elsif act='reprioritize' then
   select * into policy from service.sla_policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and sla_policies.id=(p_payload->>'policy_id')::uuid;
   if policy.id is null or p_payload->>'priority' not in('low','normal','high','urgent') then raise exception using errcode='22023',message='SERVICE_POLICY_INVALID';end if;t.policy_id:=policy.id;t.priority:=p_payload->>'priority';
  elsif act='cancel_ticket' then
   if exists(select 1 from service.work_orders where ticket_id=t.id and status<>'cancelled') then raise exception using errcode='55000',message='SERVICE_DEPENDENT_WORK';end if;t.status:='cancelled';end if;
  t.response_breached:=t.response_breached or(t.response_at is null and t.consumed_seconds>policy.response_seconds);
  t.resolution_breached:=t.resolution_breached or(t.resolution_at is null and t.consumed_seconds>policy.resolution_seconds);
  if t.status='open' then t.response_due:=case when t.response_at is null then service.due(policy.windows,observed,policy.response_seconds-t.consumed_seconds) else t.response_due end;
   t.resolution_due:=service.due(policy.windows,observed,policy.resolution_seconds-t.consumed_seconds);end if;
  update service.tickets set status=t.status,policy_id=t.policy_id,priority=t.priority,clock_start_utc=observed,consumed_seconds=t.consumed_seconds,response_due=t.response_due,resolution_due=t.resolution_due,
   response_breached=t.response_breached,resolution_breached=t.resolution_breached,version=tickets.version+1 where tickets.id=id;
 elsif act='order' then kind:='order';
  select * into t from service.tickets where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and tickets.id=(p_payload->>'ticket_id')::uuid for update;
  if t.id is null or t.status<>'open' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
  insert into service.work_orders(id,tenant_id,legal_entity_id,branch_id,ticket_id,created_by) values(id,p_tenant_id,p_legal_entity_id,p_branch_id,t.id,auth.uid());
 elsif act in('dispatch','accept','start','complete','close','cancel_order') then kind:='order';
  select ticket_id into newticket from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=command_work.id;
  select * into t from service.tickets where tickets.id=newticket for update;
  select * into w from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=command_work.id for update;
  if w.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
  if w.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  select * into policy from service.sla_policies where sla_policies.id=t.policy_id;
  if act='dispatch' then
   if w.status<>'planned' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
   calendar:=(p_payload->>'calendar_version_id')::uuid;start_utc:=service.utc(p_payload->'start_utc');end_utc:=service.utc(p_payload->'end_utc');
   select * into calendar_row from people.work_calendar_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and work_calendar_versions.id=calendar;
   perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee,calendar,start_utc at time zone calendar_row.timezone,end_utc at time zone calendar_row.timezone);
   if t.status<>'open' or service.elapsed(service.windows(p_tenant_id,p_legal_entity_id,calendar,(start_utc at time zone calendar_row.timezone)::date,((end_utc-interval '1 microsecond') at time zone calendar_row.timezone)::date+1,'[]'),start_utc,end_utc)<>extract(epoch from end_utc-start_utc)::bigint
    or exists(select 1 from service.maintenance_occurrences where order_id=w.id and deferred_until>(start_utc at time zone calendar_row.timezone)::date) then raise exception using errcode='55000',message='SERVICE_STAFF_UNAVAILABLE';end if;
   if exists(select 1 from people.work_claim_segments s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.employee_id=employee and s.active and tstzrange(s.start_utc,s.end_utc,'[)') && tstzrange(start_utc,end_utc,'[)')
    and exists(select 1 from people.work_claims c where c.id=s.claim_id and c.source_kind='leave')) then raise exception using errcode='55000',message='SERVICE_STAFF_UNAVAILABLE';end if;
   insert into service.dispatch_bookings(id,tenant_id,legal_entity_id,branch_id,order_id,employee_id,calendar_version_id,start_utc,end_utc,created_by)
    values((p_payload->>'booking_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,id,employee,calendar,start_utc,end_utc,auth.uid());w.status:='dispatched';w.employee_id:=employee;
  elsif act='accept' then
   if w.status<>'dispatched' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
   observed:=service.utc(p_payload->'observed_utc');if t.status<>'open' or observed<t.clock_start_utc or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;
   w.status:='accepted';w.accepted_by:=auth.uid();w.accepted_utc:=observed;
   update service.tickets set response_at=coalesce(response_at,observed),response_breached=response_breached or(response_at is null and observed>response_due and status='open'),version=tickets.version+1 where tickets.id=t.id;
  elsif act='start' then if w.status<>'accepted' or t.status<>'open' then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
   observed:=service.utc(p_payload->'observed_utc');if observed<t.clock_start_utc or observed<w.accepted_utc or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;w.status:='working';w.work_started_utc:=observed;
  elsif act='complete' then
   if w.status not in('accepted','working') or exists(select 1 from service.labor where order_id=w.id and status='submitted') then raise exception using errcode='55000',message='SERVICE_PENDING_WORK';end if;
   observed:=service.utc(p_payload->'observed_utc');if t.status<>'open' or observed<t.clock_start_utc or observed<coalesce(w.work_started_utc,w.accepted_utc) or observed>clock_timestamp()+interval '5 minutes'
    or exists(select 1 from service.labor where order_id=w.id and status='approved' and end_utc>observed) then raise exception using errcode='22023',message='SERVICE_CLOCK_INVALID';end if;
   if jsonb_typeof(p_payload->'customer_confirmed') is distinct from 'boolean' then raise exception using errcode='22023',message='SERVICE_CONFIRMATION_INVALID';end if;
   w.customer_confirmed:=(p_payload->>'customer_confirmed')::boolean;w.exception_reason:=case when w.customer_confirmed then null else service.text(p_payload->'exception_reason',1000) end;
   w.resolution:=service.text(p_payload->'resolution',1000);w.completed_by:=auth.uid();w.status:='completed';w.completed_utc:=observed;
   update service.dispatch_bookings set active=false where order_id=w.id and active;
   if not exists(select 1 from service.work_orders where ticket_id=t.id and work_orders.id<>w.id and status not in('completed','closed','cancelled')) then
    update service.tickets set resolution_at=observed,resolution_breached=resolution_breached or(observed>resolution_due and status='open'),status='resolved',version=tickets.version+1 where tickets.id=t.id;end if;
  elsif act='close' then
   if w.status<>'completed' or policy.independent_closure and w.completed_by=auth.uid() or exists(select 1 from service.dispatch_bookings where order_id=w.id and active)
    or exists(select 1 from service.labor where order_id=w.id and(status='submitted' or status='approved' and billing_kind='billable' and billing_consumption_id is null)) then
    raise exception using errcode='55000',message='SERVICE_INDEPENDENT_CLOSURE_REQUIRED';end if;w.status:='closed';w.closed_by:=auth.uid();w.closed_at:=date_trunc('second',clock_timestamp());
   if not exists(select 1 from service.work_orders where ticket_id=t.id and work_orders.id<>w.id and status not in('closed','cancelled')) then update service.tickets set status='closed',version=tickets.version+1 where tickets.id=t.id;end if;
  elsif act='cancel_order' then
   if w.status in('completed','closed','cancelled') or exists(select 1 from service.labor where order_id=w.id and status<>'cancelled') then raise exception using errcode='55000',message='SERVICE_DEPENDENT_WORK';end if;
   w.status:='cancelled';update service.dispatch_bookings set active=false where order_id=w.id and active;end if;
  update service.work_orders set status=w.status,employee_id=w.employee_id,accepted_by=w.accepted_by,completed_by=w.completed_by,closed_by=w.closed_by,resolution=w.resolution,
   customer_confirmed=w.customer_confirmed,exception_reason=w.exception_reason,accepted_utc=w.accepted_utc,work_started_utc=w.work_started_utc,completed_utc=w.completed_utc,closed_at=w.closed_at,version=work_orders.version+1 where work_orders.id=id;
 elsif act='labor' then kind:='labor';
  select * into w from service.work_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and work_orders.id=(p_payload->>'order_id')::uuid for update;
  calendar:=(p_payload->>'calendar_version_id')::uuid;start_utc:=service.utc(p_payload->'start_utc');end_utc:=service.utc(p_payload->'end_utc');
  if w.id is null or w.status not in('accepted','working') or w.employee_id is distinct from employee then raise exception using errcode='55000',message='SERVICE_STATE_CONFLICT';end if;
  if not exists(select 1 from service.dispatch_bookings s where s.order_id=w.id and s.employee_id=employee and s.active and tstzrange(s.start_utc,s.end_utc,'[)') @> tstzrange(command_work.start_utc,command_work.end_utc,'[)')) then
   raise exception using errcode='55000',message='SERVICE_LABOR_BOOKING_REQUIRED';end if;
  select * into calendar_row from people.work_calendar_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and work_calendar_versions.id=calendar;
  perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee,calendar,start_utc at time zone calendar_row.timezone,end_utc at time zone calendar_row.timezone);
  seconds:=extract(epoch from end_utc-start_utc)::bigint-people.work_break_seconds(start_utc,end_utc,p_payload->'breaks');cost:=service.amount(p_payload->'hourly_cost');precision:=service.integer(p_payload->'precision',6)::integer;
  select currency_code into currency from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
  if p_payload->>'currency_code' is distinct from currency then raise exception using errcode='22023',message='SERVICE_CURRENCY_INVALID';end if;
  billkind:=coalesce(p_payload->>'billing_kind','nonbillable');billrate:=case when p_payload ? 'hourly_billing' then service.amount(p_payload->'hourly_billing') else 0 end;
  billref:=case when p_payload ? 'billing_reference' then service.text(p_payload->'billing_reference',160) else 'Synthetic nonbillable work' end;
  if billkind not in('billable','nonbillable') or billkind='nonbillable' and billrate<>0 then raise exception using errcode='22023',message='SERVICE_BILLING_TERMS_INVALID';end if;
  amount:=service.round_ratio(cost*1000000*seconds,3600,precision);billamount:=service.round_ratio(billrate*1000000*seconds,3600,precision);
  digest:=encode(extensions.digest(p_payload::text||':'||seconds::text||':'||amount::text||':'||billkind||':'||billamount::text||':'||billref,'sha256'),'hex');
  insert into service.labor(id,tenant_id,legal_entity_id,branch_id,order_id,employee_id,calendar_version_id,start_utc,end_utc,breaks,seconds,claim_id,hourly_cost,amount,currency_code,precision,digest,submitted_by,reason,billing_kind,hourly_billing,billable_amount,billing_reference)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,w.id,employee,calendar,start_utc,end_utc,p_payload->'breaks',seconds,(p_payload->>'claim_id')::uuid,cost,amount,currency,precision,digest,auth.uid(),reason,billkind,billrate,billamount,billref);
 elsif act in('approve_labor','cancel_labor') then kind:='labor';
  select l.* into labor from service.labor l where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.id=command_work.id for update;
  if labor.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;if labor.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  if act='approve_labor' then
 if labor.status<>'submitted' or labor.submitted_by=auth.uid() or not exists(select 1 from service.work_orders where work_orders.id=labor.order_id and status in('accepted','working')) then raise exception using errcode='55000',message='SERVICE_INDEPENDENT_APPROVAL_REQUIRED';end if;
   select * into calendar_row from people.work_calendar_versions where work_calendar_versions.id=labor.calendar_version_id;
   perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee,labor.calendar_version_id,labor.start_utc at time zone calendar_row.timezone,labor.end_utc at time zone calendar_row.timezone);
   claim:=labor.claim_id;
   if claim is null then owns:=true;claim:=people.make_work_claim(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'service',labor.id,labor.start_utc,labor.end_utc,labor.breaks,labor.calendar_version_id,auth.uid());
    for segment in select s.start_utc,s.end_utc from people.work_claim_segments s where s.claim_id=claim and s.active order by s.start_utc loop
     allocation:=people.allocate_work(p_tenant_id,p_legal_entity_id,p_branch_id,employee,claim,'service',gen_random_uuid(),segment.start_utc,segment.end_utc,auth.uid());allocations:=array_append(allocations,allocation);end loop;
   else
    if not exists(select 1 from people.work_claims x where x.id=claim and x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.employee_id=employee and x.source_kind='attendance' and x.active and x.calendar_version_id=labor.calendar_version_id
     and exists(select 1 from people.attendance_entries a where a.active_claim_id=x.id and a.status='approved')) then raise exception using errcode='55000',message='SERVICE_ATTENDANCE_SOURCE_INVALID';end if;
    segment_cursor:=labor.start_utc;
    for segment in select (value->>'start_utc')::timestamptz start_utc,(value->>'end_utc')::timestamptz end_utc from jsonb_array_elements(labor.breaks||jsonb_build_array(jsonb_build_object('start_utc',labor.end_utc,'end_utc',labor.end_utc))) loop
     if segment.start_utc>segment_cursor then
      allocation:=people.allocate_work(p_tenant_id,p_legal_entity_id,p_branch_id,employee,claim,'service',gen_random_uuid(),segment_cursor,segment.start_utc,auth.uid());allocations:=array_append(allocations,allocation);
     end if;segment_cursor:=segment.end_utc;
    end loop;
   end if;
   foreach allocation in array allocations loop
    insert into service.labor_allocations values(allocation,p_tenant_id,p_legal_entity_id,p_branch_id,labor.id,labor.id,claim,owns);
   end loop;
   perform people.consume_organization(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'service_time',labor.id,(labor.start_utc at time zone calendar_row.timezone)::date,((labor.end_utc-interval '1 microsecond') at time zone calendar_row.timezone)::date+1);
   update service.labor set claim_id=claim,allocation_ids=allocations,owns_claim=owns,status='approved',approved_by=auth.uid(),version=service.labor.version+1 where service.labor.id=id;
  else
   if labor.status='cancelled' or labor.billing_consumption_id is not null then raise exception using errcode='55000',message='SERVICE_CONSUMED_IMPACT_REQUIRED';end if;
   perform service.assert_billing_mutable(p_tenant_id,p_legal_entity_id,labor.id);
   if exists(select 1 from people.work_input_seals where claim_id=labor.claim_id) then raise exception using errcode='55000',message='PAYROLL_INPUT_SEALED';end if;
   foreach allocation in array labor.allocation_ids loop perform people.revoke_work_allocation(p_tenant_id,p_legal_entity_id,employee,allocation);end loop;
   if labor.owns_claim then perform people.revoke_work_claim(p_tenant_id,p_legal_entity_id,employee,labor.claim_id);end if;
   update service.labor set status='cancelled',version=service.labor.version+1 where service.labor.id=id;
   if to_regprocedure('projects.service_payroll_cost_impact(uuid,uuid,uuid,uuid,uuid)') is not null then
    execute 'select projects.service_payroll_cost_impact($1,$2,$3,$4,$5)' using p_tenant_id,p_legal_entity_id,p_branch_id,labor.id,coalesce(labor.current_revision_id,labor.id);
   end if;
  end if;
 elsif act='plan' then kind:='plan';
  select * into eq from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment.id=(p_payload->>'equipment_id')::uuid and status='active';
  select * into policy from service.sla_policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and sla_policies.id=(p_payload->>'policy_id')::uuid;
  if eq.id is null or policy.id is null then raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
  insert into service.maintenance_plans(id,tenant_id,legal_entity_id,branch_id,equipment_id,policy_id,name,basis,interval_units,next_date,next_meter,created_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,eq.id,policy.id,service.text(p_payload->'name',160),p_payload->>'basis',service.integer(p_payload->'interval_units',9007199254740991,1),
   (p_payload->>'next_date')::date,case when p_payload->'next_meter'<> 'null'::jsonb then service.integer(p_payload->'next_meter',9007199254740991,1) end,auth.uid());
 elsif act='reading' then kind:='reading';
  select * into eq from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment.id=(p_payload->>'equipment_id')::uuid and status='active' for update;
  if eq.id is null then raise exception using errcode='42501',message='SERVICE_SCOPE_DENIED';end if;
  raw:=service.integer(p_payload->'raw_value',9007199254740991);observed:=service.utc(p_payload->'observed_utc');
  select * into meter from service.meter_readings where equipment_id=eq.id order by observed_utc desc,id desc limit 1;
  if observed>clock_timestamp()+interval '5 minutes' or meter.id is not null and observed<=meter.observed_utc then raise exception using errcode='22023',message='SERVICE_METER_CLOCK_INVALID';end if;
  if meter.id is null then if p_payload->>'kind'<>'initial' then raise exception using errcode='22023',message='SERVICE_METER_INITIAL_REQUIRED';end if;logical:=raw;
  elsif p_payload->>'kind'='reading' then if raw<meter.raw_value then raise exception using errcode='22023',message='SERVICE_METER_DECREASE';end if;logical:=meter.logical_value+raw-meter.raw_value;
  elsif p_payload->>'kind'='reset' then logical:=meter.logical_value+raw;
  elsif p_payload->>'kind'='rollover' then rollmax:=service.integer(p_payload->'rollover_max',9007199254740991,1);
   if raw>=meter.raw_value or rollmax<meter.raw_value or raw>rollmax then raise exception using errcode='22023',message='SERVICE_METER_ROLLOVER_INVALID';end if;logical:=meter.logical_value+(rollmax-meter.raw_value)+1+raw;
  else raise exception using errcode='22023',message='SERVICE_METER_KIND_INVALID';end if;
  insert into service.meter_readings(id,tenant_id,legal_entity_id,branch_id,equipment_id,kind,raw_value,logical_value,previous_id,rollover_max,observed_utc,reason,recorded_by)
  values(id,p_tenant_id,p_legal_entity_id,p_branch_id,eq.id,p_payload->>'kind',raw,logical,meter.id,rollmax,observed,reason,auth.uid());
 elsif act='generate' then kind:='plan';
  select * into plan from service.maintenance_plans where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and maintenance_plans.id=command_work.id for update;
  if plan.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;if plan.version<>p_expected_version then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;before_state:=service.snapshot(kind,id);
  observed:=service.utc(p_payload->'observed_utc');select * into eq from service.equipment where equipment.id=plan.equipment_id and status='active';
  if eq.id is null or observed>clock_timestamp()+interval '5 minutes' then raise exception using errcode='55000',message='SERVICE_MAINTENANCE_NOT_DUE';end if;
  if plan.basis='calendar' then
   if (observed at time zone(select timezone from core.legal_entities where legal_entities.id=p_legal_entity_id))::date<plan.next_date then raise exception using errcode='55000',message='SERVICE_MAINTENANCE_NOT_DUE';end if;
   occurrence_key:='date:'||plan.next_date::text;
  else select * into meter from service.meter_readings where equipment_id=eq.id and observed_utc<=observed order by observed_utc desc,id desc limit 1;
   if meter.id is null or meter.logical_value<plan.next_meter then raise exception using errcode='55000',message='SERVICE_MAINTENANCE_NOT_DUE';end if;occurrence_key:='meter:'||plan.next_meter::text;end if;
  newticket:=(p_payload->>'ticket_id')::uuid;neworder:=(p_payload->>'order_id')::uuid;occurrence:=(p_payload->>'occurrence_id')::uuid;
  perform service.ticket_create(p_tenant_id,p_legal_entity_id,p_branch_id,newticket,jsonb_build_object('code','PM-'||upper(substr(occurrence::text,1,8)),
    'name',plan.name,'classification','preventive-maintenance','customer_id',eq.customer_id,'equipment_id',eq.id,'policy_id',plan.policy_id,'priority','normal','observed_utc',p_payload->'observed_utc'));
  insert into service.work_orders(id,tenant_id,legal_entity_id,branch_id,ticket_id,created_by) values(neworder,p_tenant_id,p_legal_entity_id,p_branch_id,newticket,auth.uid());
  insert into service.maintenance_occurrences(id,tenant_id,legal_entity_id,branch_id,plan_id,plan_version,occurrence_key,original_due_date,original_due_meter,ticket_id,order_id,reading_id,reason,created_by)
   values(occurrence,p_tenant_id,p_legal_entity_id,p_branch_id,id,plan.version,occurrence_key,plan.next_date,plan.next_meter,newticket,neworder,meter.id,reason,auth.uid());
  update service.maintenance_plans set next_date=case when basis='calendar' then next_date+interval_units::integer else null end,next_meter=case when basis='meter' then next_meter+interval_units else null end,version=maintenance_plans.version+1 where maintenance_plans.id=id;
 elsif act='defer' then kind:='occurrence';
  before_state:=service.snapshot(kind,id);if before_state is null or before_state->>'tenant_id'<>p_tenant_id::text or before_state->>'legal_entity_id'<>p_legal_entity_id::text or before_state->>'branch_id'<>p_branch_id::text then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
  if p_expected_version<>(before_state->>'version')::bigint then raise exception using errcode='40001',message='SERVICE_VERSION_CONFLICT';end if;
  if (p_payload->>'deferred_until') is null or (p_payload->>'deferred_until')::date<=coalesce((before_state->>'deferred_until')::date,(before_state->>'original_due_date')::date,'0001-01-01'::date) or exists(select 1 from service.work_orders where work_orders.id=(before_state->>'order_id')::uuid and status<>'planned') then raise exception using errcode='55000',message='SERVICE_DEFERRAL_INVALID';end if;
  update service.maintenance_occurrences set deferred_until=(p_payload->>'deferred_until')::date,version=maintenance_occurrences.version+1 where maintenance_occurrences.id=id;
 end if;
 after_state:=service.snapshot(kind,id);version:=(after_state->>'version')::bigint;
 if act in('accept','complete','close') and (select x.version from service.tickets x where x.id=t.id)>t.version then
  insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
   select p_tenant_id,p_legal_entity_id,p_branch_id,t.id,'ticket',x.version,act,reason,service.snapshot('ticket',t.id),auth.uid() from service.tickets x where x.id=t.id;
 end if;
 if act='generate' then
  insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
   select p_tenant_id,p_legal_entity_id,p_branch_id,x.id,x.kind,1,act,reason,service.snapshot(x.kind,x.id),auth.uid()
   from(values(newticket,'ticket'),(neworder,'order'),(occurrence,'occurrence')) x(id,kind);
 end if;
 event_state:=after_state;
 insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,id,kind,version,act,reason,event_state,auth.uid());
 -- Telemetry is deliberately minimal; rich facts are service-scoped read projections.
 return core.wave3_finish_command(p_tenant_id,'service.'||act,p_command_id,'service.'||kind,id,p_idempotency_key,hash,
  case when before_state is not null then jsonb_build_object('id',id,'version',before_state->'version') end,
  jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',kind,'version',version,'status',after_state->>'status'),p_legal_entity_id,p_branch_id);
end $$;
-- Owner-only linked payroll impacts preserve original geometry, allocation identity,
-- invoices and credits. One labor revision owns every payable segment.
create function service.assert_billing_mutable(t uuid,e uuid,p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare blocked boolean;rid uuid;begin
 select coalesce(current_revision_id,id) into rid from service.labor where tenant_id=t and legal_entity_id=e and id=p_id;
 if to_regclass('projects.billable_units') is not null then
  if exists(select 1 from pg_attribute where attrelid=to_regclass('projects.billable_units') and attname='provider_source_id' and not attisdropped) then
   execute 'select exists(select 1 from projects.billable_units where tenant_id=$1 and legal_entity_id=$2 and source_kind=''service'' and provider_source_id=$3 and source_id=$4 and status in(''reserved'',''billed''))' into blocked using t,e,p_id,rid;
  else
   execute 'select exists(select 1 from projects.billable_units where tenant_id=$1 and legal_entity_id=$2 and source_kind=''service'' and source_id=$3 and status in(''reserved'',''billed''))' into blocked using t,e,rid;
  end if;
  if blocked then raise exception using errcode='55000',message='SERVICE_BILLED_IMPACT_REQUIRED';end if;
 end if;
end $$;
create function service.payroll_billing_impact(t uuid,e uuid,b uuid,p_id uuid,rid uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if to_regprocedure('projects.service_payroll_billing_impact(uuid,uuid,uuid,uuid,uuid,jsonb,text)') is not null then
  execute 'select projects.service_payroll_billing_impact($1,$2,$3,$4,$5,$6,$7)' into result using t,e,b,p_id,rid,proposal,p_mode;
  return result;
 end if;
 perform service.assert_billing_mutable(t,e,p_id);
 if exists(select 1 from service.labor where tenant_id=t and legal_entity_id=e and branch_id=b and id=p_id and billing_consumption_id is not null) then
  raise exception using errcode='55000',message='SERVICE_BILLED_IMPACT_REQUIRED';end if;
 return jsonb_build_object('status','unimported','source_id',rid);
end $$;
create function service.payroll_impact_guard(t uuid,e uuid,b uuid,employee uuid,claim uuid,cid uuid,direct_claim boolean)
returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from people_payroll.corrections q join people_payroll.correction_sources x on x.correction_id=q.id
  where q.id=cid and q.tenant_id=t and q.legal_entity_id=e and q.branch_id=b and q.employee_id=employee
   and q.status in('approved','posted') and x.source_kind=case when direct_claim then 'service' else 'attendance' end
   and x.impact is not null and (people_payroll.correction_source_state(x.seal_id)->>'claim_id')::uuid=claim) then
  raise exception using errcode='42501',message='PAYROLL_APPROVED_LINKED_IMPACT_REQUIRED';end if;
end $$;
create function service.payroll_revision_impact(t uuid,e uuid,b uuid,employee uuid,entry uuid,claim uuid,
 revision uuid,proposal jsonb,p_mode text,direct_claim boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare l service.labor%rowtype;c people.work_calendar_versions%rowtype;w service.work_orders%rowtype;ticket service.tickets%rowtype;
 before_body jsonb;after_body jsonb;target jsonb;change jsonb;result jsonb;approved_result jsonb;billing jsonb;billing_proposal jsonb;current_credit jsonb;
 previous service.payroll_labor_impacts%rowtype;original service.payroll_labor_impacts%rowtype;
 attendance jsonb:=proposal->'attendance_after';br jsonb;breaks jsonb;cid uuid:=(proposal->>'correction_id')::uuid;
 actual_mode text;rid uuid;oldrid uuid;new_claim uuid;allocation uuid;allocs uuid[]:='{}';
 s timestamptz;z timestamptz;sl timestamp;el timestamp;cursor_utc timestamptz;bs timestamptz;be timestamptz;seconds bigint;
 remove_source boolean:=false;order_reopened boolean:=false;
begin
 if p_mode not in('read','validate','release','apply','reverse') or revision is null or proposal is null or jsonb_typeof(proposal)<>'object' then
  raise exception using errcode='22023',message='SERVICE_PAYROLL_IMPACT_INVALID';end if;
 actual_mode:=case when p_mode='reverse' or proposal->>'operational_mode'='reverse' then 'reverse' else 'apply' end;
 perform service.require_access(t,e,b,case when p_mode='read' then 'service.view' else 'service.approve' end);
 perform service.require_access(t,e,b,'service.cost.view');
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
 perform 1 from people.employees where tenant_id=t and legal_entity_id=e and id=employee for update;
 select x.* into l from service.labor x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.id=entry;
 if l.id is null or l.owns_claim is distinct from direct_claim then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 select x.* into ticket from service.tickets x join service.work_orders q on q.ticket_id=x.id where q.id=l.order_id for update of x;
 select * into w from service.work_orders where id=l.order_id for update;
 select * into l from service.labor where id=l.id for update;
 oldrid:=coalesce(l.current_revision_id,l.id);
 select * into previous from service.payroll_labor_impacts x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.labor_id=l.id and x.correction_id=cid and x.mode=actual_mode;
 if previous.id is not null and p_mode in('apply','reverse') then
  if l.current_revision_id is distinct from previous.replacement_revision_id or l.version is distinct from(previous.body->>'source_version')::bigint
   or l.claim_id is distinct from(previous.body->>'claim_id')::uuid then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  return previous.body;
 end if;
 if l.status<>'approved' and not(actual_mode='reverse' and l.status='cancelled') or l.claim_id is distinct from claim then
  raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 select * into c from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=l.calendar_version_id;
 before_body:=service.snapshot('labor',l.id);
 before_body:=before_body||jsonb_build_object('start_local',to_char((before_body->>'start_utc')::timestamptz at time zone c.timezone,'YYYY-MM-DD"T"HH24:MI:SS'),
  'end_local',to_char((before_body->>'end_utc')::timestamptz at time zone c.timezone,'YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',extract(epoch from ((before_body->>'start_utc')::timestamptz at time zone c.timezone)-((before_body->>'start_utc')::timestamptz at time zone 'UTC'))::integer,
  'end_offset_seconds',extract(epoch from ((before_body->>'end_utc')::timestamptz at time zone c.timezone)-((before_body->>'end_utc')::timestamptz at time zone 'UTC'))::integer);
 if p_mode='read' then
  if not exists(select 1 from people.work_claims x where x.id=claim and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.active
   and x.source_kind=case when direct_claim then 'service' else 'attendance' end and(not direct_claim or x.source_id=oldrid)) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  return jsonb_build_object('before',before_body,'source_id',oldrid,'source_version',l.version,'paid_seconds',(before_body->>'seconds')::bigint,
   'claim_id',claim,'entry_id',l.id,'order_id',w.id,'order_name',ticket.code||' / '||ticket.name,
   'ticket_id',ticket.id,'ticket_code',ticket.code,'ticket_name',ticket.name);
 end if;
 if actual_mode='reverse' then
  select * into original from service.payroll_labor_impacts x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.labor_id=l.id and x.correction_id=cid and x.mode='apply';
  if original.id is null or original.replacement_revision_id is distinct from l.current_revision_id
   or (original.body->>'source_version')::bigint is distinct from l.version or (original.body->>'claim_id')::uuid is distinct from claim then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if direct_claim then
   if proposal->'before' is distinct from original.approved_body->'before' or proposal->'after' is distinct from original.approved_body->'after' then
    raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   target:=proposal->'before';
  else
   if ((proposal->'allocation_impact')-'allocation_id') is distinct from original.approved_body then
    raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   target:=proposal->'allocation_impact'->'before';
  end if;
  if direct_claim then
   current_credit:=jsonb_build_object('source_revision_id',proposal->'current_source_revision_id','expected_source_version',proposal->'current_source_version','billing_credit_line_ids',coalesce(proposal->'current_billing_credit_line_ids','[]'));
  else
   if jsonb_typeof(coalesce(proposal->'current_allocation_credits','[]')) is distinct from 'array' or jsonb_array_length(coalesce(proposal->'current_allocation_credits','[]'))>50
    or(select count(*) from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]')) x where(x->>'entry_id')::uuid=l.id)>1 then
    raise exception using errcode='22023',message='SERVICE_CURRENT_CREDIT_INVALID';end if;
   select value into current_credit from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]')) where(value->>'entry_id')::uuid=l.id;
  end if;
  if current_credit is not null and(current_credit->>'source_revision_id' is not null or jsonb_array_length(coalesce(current_credit->'billing_credit_line_ids','[]'))>0)
   and((current_credit->>'source_revision_id')::uuid is distinct from oldrid or(current_credit->>'expected_source_version')::bigint is distinct from l.version) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 else
  if direct_claim then
   if l.version is distinct from(proposal->>'expected_source_version')::bigint or proposal->>'mode' is distinct from 'geometry'
    or not exists(select 1 from people.work_claims x where x.id=claim and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee
     and x.active and x.source_kind='service' and x.source_id=oldrid) then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   target:=proposal;
  else
   if jsonb_typeof(coalesce(proposal->'allocation_changes','[]')) is distinct from 'array' or jsonb_array_length(coalesce(proposal->'allocation_changes','[]'))>50 then
    raise exception using errcode='22023',message='SERVICE_ALLOCATION_CHANGE_INVALID';end if;
   if(select count(*) from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) x where(x->>'entry_id')::uuid=l.id)>1 then
    raise exception using errcode='22023',message='SERVICE_ALLOCATION_CHANGE_INVALID';end if;
   select value into change from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) where(value->>'entry_id')::uuid=l.id;
   if change is not null and(change->>'mode' not in('retain','geometry','remove') or exists(select 1 from jsonb_object_keys(change) k
    where k<>all(array['entry_id','mode','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','billing_credit_line_ids']))) then
    raise exception using errcode='22023',message='SERVICE_ALLOCATION_CHANGE_INVALID';end if;
   target:=case when change->>'mode'='geometry' then change else before_body end;
   remove_source:=change->>'mode'='remove';
   remove_source:=coalesce(remove_source,false);
  end if;
 end if;
 if not direct_claim then revision:=md5(revision::text||':'||l.id::text||':service-allocation')::uuid;end if;
 rid:=revision;
 sl:=(target->>'start_local')::timestamp;el:=(target->>'end_local')::timestamp;
 if sl is null or el is null or extract(second from sl)%1<>0 or extract(second from el)%1<>0 then raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
 s:=people.resolve_local_instant(c.timezone,sl,(target->>'start_offset_seconds')::integer);
 z:=people.resolve_local_instant(c.timezone,el,(target->>'end_offset_seconds')::integer);
 perform people.work_local_coverage(t,e,b,employee,c.id,sl,el);
 breaks:=coalesce(target->'breaks','[]');seconds:=extract(epoch from z-s)::bigint-people.work_break_seconds(s,z,breaks);
 if seconds not between 1 and 129600 then raise exception using errcode='22023',message='WORK_DURATION_INVALID';end if;
 if not exists(select 1 from service.dispatch_bookings x where x.order_id=l.order_id and x.employee_id=employee and x.calendar_version_id=c.id and tstzrange(x.start_utc,x.end_utc,'[)') @> tstzrange(s,z,'[)')) then
  raise exception using errcode='55000',message='SERVICE_LABOR_BOOKING_REQUIRED';end if;
 if w.status in('completed','closed') and z>w.completed_utc then raise exception using errcode='55000',message='SERVICE_COMPLETION_IMPACT_REQUIRED';end if;
 if not direct_claim and not remove_source then
  if attendance is null or(attendance->>'calendar_version_id')::uuid is distinct from c.id then raise exception using errcode='55000',message='SERVICE_ATTENDANCE_SOURCE_INVALID';end if;
  cursor_utc:=s;
  for br in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',z,'end_utc',z))) loop
   bs:=(br->>'start_utc')::timestamptz;be:=(br->>'end_utc')::timestamptz;
   if bs>cursor_utc and(cursor_utc<(attendance->>'start_utc')::timestamptz or bs>(attendance->>'end_utc')::timestamptz
    or exists(select 1 from jsonb_array_elements(attendance->'breaks') x where tstzrange((x->>'start_utc')::timestamptz,(x->>'end_utc')::timestamptz,'[)') && tstzrange(cursor_utc,bs,'[)'))) then
    raise exception using errcode='55000',message='SERVICE_ALLOCATION_GEOMETRY_IMPACT_REQUIRED';end if;
   cursor_utc:=be;
  end loop;
 end if;
 billing_proposal:=(proposal-'operational_mode')||jsonb_build_object('current_source_revision_id',oldrid,
  'billing_credit_line_ids',case when actual_mode='reverse' then coalesce(current_credit->'billing_credit_line_ids','[]') else coalesce(change->'billing_credit_line_ids',proposal->'billing_credit_line_ids','[]') end);
 billing:=service.payroll_billing_impact(t,e,b,l.id,oldrid,billing_proposal,'validate');
 after_body:=before_body||jsonb_build_object('start_local',to_char(sl,'YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(el,'YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',(target->>'start_offset_seconds')::integer,'end_offset_seconds',(target->>'end_offset_seconds')::integer,
  'start_utc',to_char(s at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'end_utc',to_char(z at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'breaks',breaks,'seconds',case when remove_source then 0 else seconds end,'amount',case when remove_source then 0 else service.round_ratio(l.hourly_cost*1000000*seconds,3600,l.precision) end::numeric(20,6)::text,
  'billable_amount',case when remove_source then 0 else service.round_ratio(l.hourly_billing*1000000*seconds,3600,l.precision) end::numeric(20,6)::text,
  'billing_consumption_id',null,'status',case when remove_source then 'cancelled' else 'approved' end);
 after_body:=after_body||jsonb_build_object('digest',encode(extensions.digest((after_body-array['digest','current_revision_id','version','claim_id','allocation_ids','billing_consumption_id'])::text||':'||cid||':'||rid,'sha256'),'hex'));
 result:=jsonb_build_object('before',before_body,'after',after_body,'billing',billing,'source_id',rid,'source_version',l.version+1,
  'paid_seconds',case when remove_source then 0 else seconds end,'claim_id',claim,'entry_id',l.id,'order_id',w.id,
  'order_name',ticket.code||' / '||ticket.name,'ticket_id',ticket.id,'ticket_code',ticket.code,'ticket_name',ticket.name);
 if p_mode='validate' then return result;end if;
 perform service.payroll_impact_guard(t,e,b,employee,claim,cid,direct_claim);
 if actual_mode<>'reverse' then
  if direct_claim and(proposal->'before' is distinct from before_body or proposal->'after' is distinct from after_body)
   or not direct_claim and((proposal->'allocation_impact')-'allocation_id') is distinct from result then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 end if;
 if p_mode='release' then
  -- Release all segments once; repeated callbacks see identical immutable IDs.
  update people.work_allocations set active=false,revoked_at=clock_timestamp() where id=any(l.allocation_ids) and active;
  return result;
 end if;
 approved_result:=result;
 if direct_claim then
  update people.work_allocations set active=false,revoked_at=clock_timestamp() where id=any(l.allocation_ids) and active;
  if exists(select 1 from people.work_allocations where claim_id=claim and active) then raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
  new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'service',rid,c.id,s,z,breaks,cid);
 else
  new_claim:=(proposal->>'new_claim_id')::uuid;
  if exists(select 1 from people.work_allocations where id=any(l.allocation_ids) and active)
   or not exists(select 1 from people.work_claims x where x.id=new_claim and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.source_kind='attendance' and x.active
    and x.calendar_version_id=c.id and x.start_utc=(attendance->>'start_utc')::timestamptz and x.end_utc=(attendance->>'end_utc')::timestamptz
    and x.break_seconds=people.work_break_seconds(x.start_utc,x.end_utc,attendance->'breaks')) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 end if;
 perform service.payroll_billing_impact(t,e,b,l.id,oldrid,billing_proposal,'apply');
 if not remove_source then
  cursor_utc:=s;
  for br in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',z,'end_utc',z))) loop
   bs:=(br->>'start_utc')::timestamptz;be:=(br->>'end_utc')::timestamptz;
   if bs>cursor_utc then
    allocation:=people.allocate_work(t,e,b,employee,new_claim,'service',gen_random_uuid(),cursor_utc,bs,auth.uid());
    allocs:=array_append(allocs,allocation);
    insert into service.labor_allocations values(allocation,t,e,b,l.id,rid,new_claim,direct_claim);
   end if;cursor_utc:=be;
  end loop;
 end if;
 after_body:=after_body||jsonb_build_object('version',l.version+1,'current_revision_id',rid,'claim_id',new_claim,'allocation_ids',to_jsonb(allocs));
 insert into service.labor_revisions(id,tenant_id,legal_entity_id,branch_id,labor_id,employee_id,version,correction_id,supersedes_id,snapshot,recorded_by)
  values(rid,t,e,b,l.id,employee,l.version+1,cid,l.current_revision_id,after_body,auth.uid());
 update service.labor set version=version+1,current_revision_id=rid,claim_id=new_claim,allocation_ids=allocs,billing_consumption_id=null,status=case when remove_source then 'cancelled' else 'approved' end where id=l.id;
 if to_regprocedure('projects.service_payroll_cost_impact(uuid,uuid,uuid,uuid,uuid)') is not null then
  execute 'select projects.service_payroll_cost_impact($1,$2,$3,$4,$5)' using t,e,b,l.id,rid;
 end if;
 perform people.consume_organization(t,e,b,employee,'service_time',rid,sl::date,((el-interval '1 microsecond')::date)+1);
 if w.status='closed' and not remove_source and l.billing_kind='billable' then
  update service.work_orders set status='completed',closed_by=null,closed_at=null,version=version+1 where id=w.id;
  update service.tickets set status='resolved',version=version+1 where id=ticket.id and status='closed';
  insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
   select t,e,b,x.id,x.kind,(service.snapshot(x.kind,x.id)->>'version')::bigint,'payroll_reopen','Linked revision requires separate financial review',service.snapshot(x.kind,x.id),auth.uid()
    from(values(w.id,'order'),(ticket.id,'ticket')) x(id,kind);
  order_reopened:=true;
 end if;
 insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
  values(t,e,b,l.id,'labor',l.version+1,case when direct_claim then 'payroll_' else 'attendance_' end||actual_mode,
   'Independently approved linked payroll source correction',service.snapshot('labor',l.id),auth.uid());
 result:=result||jsonb_build_object('after',after_body,'claim_id',new_claim,'order_reopened_for_financial_review',order_reopened);
 insert into service.payroll_labor_impacts(tenant_id,legal_entity_id,branch_id,labor_id,correction_id,original_revision_id,replacement_revision_id,mode,approved_body,body,actor_id)
  values(t,e,b,l.id,cid,oldrid,rid,actual_mode,approved_result,result,auth.uid());
 return result;
end $$;
create function service.payroll_impact(t uuid,e uuid,b uuid,employee uuid,claim uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$declare entry uuid;begin
 select x.id into entry from service.labor x join people.work_claims c on c.id=x.claim_id where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee
  and x.claim_id=claim and x.owns_claim and c.active and c.source_kind='service' and c.source_id=coalesce(x.current_revision_id,x.id);
 if entry is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 return service.payroll_revision_impact(t,e,b,employee,entry,claim,revision,proposal,p_mode,true);
end $$;
create function service.payroll_allocation_impact(t uuid,e uuid,b uuid,employee uuid,p_allocation uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a people.work_allocations%rowtype;entry uuid;body jsonb;begin
 select * into a from people.work_allocations x where x.id=p_allocation and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee and x.source_kind='service';
 select x.labor_id into entry from service.labor_allocations x where x.allocation_id=a.id and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and not x.direct_claim;
 if entry is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 -- Original inactive IDs remain usable only with the frozen reversal lineage.
 if not a.active and p_mode='read' then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 body:=service.payroll_revision_impact(t,e,b,employee,entry,coalesce((proposal->>'current_claim_id')::uuid,a.claim_id),revision,proposal,p_mode,false);
 return body||jsonb_build_object('allocation_id',a.id);
end $$;
revoke all on all functions in schema service from public,anon,authenticated;
revoke all on function api.service_authorize(uuid,uuid,uuid,text),api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_list(uuid,uuid,uuid,text,uuid,uuid),api.service_detail(uuid,uuid,uuid,text,uuid,uuid),api.service_choices(uuid,uuid,uuid,text,uuid,uuid),api.service_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.service_authorize(uuid,uuid,uuid,text),api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_list(uuid,uuid,uuid,text,uuid,uuid),api.service_detail(uuid,uuid,uuid,text,uuid,uuid),api.service_choices(uuid,uuid,uuid,text,uuid,uuid),api.service_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;

-- W4-07 UNAPPLIED synthetic candidate. Installed journal/period provider only.
-- Procurement, stock and equipment providers are explicitly unavailable here.
-- No subscriptions, existing plan entitlements, roles or grants are changed.
create schema assets;
revoke all on schema assets from public,anon,authenticated;
insert into core.permissions(code,module,description,privileged) values
 ('assets.view','assets','Read scoped asset register and immutable books',false),
 ('assets.configure','assets','Configure named scoped asset locations with MFA',true),
 ('assets.prepare','assets','Prepare governed synthetic asset changes with MFA',true),
 ('assets.approve','assets','Independently approve exact asset proposal with MFA',true),
 ('assets.post','assets','Post approved asset effects with MFA',true),
 ('assets.depreciate','assets','Post exact immutable asset schedule periods with MFA',true),
 ('assets.reverse','assets','Reverse original asset effects with MFA',true),
 ('assets.transfer','assets','Authorize asset transfers in both branches with MFA',true)
on conflict(code) do nothing;
create table assets.locations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),name text not null check(length(btrim(name)) between 1 and 160),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,branch_id,id),unique(tenant_id,legal_entity_id,branch_id,code),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table assets.register(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,original_branch_id uuid not null,branch_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),name text not null check(length(btrim(name)) between 1 and 160),
 ownership text not null check(length(btrim(ownership)) between 1 and 160),currency_code text not null references core.currencies(code),
 in_service date not null,location_id uuid not null,custodian_id uuid,
 status text not null default 'draft' check(status in('draft','active','disposed','reversed')),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 cost numeric(20,6) not null default 0 check(cost>=0),accumulated numeric(20,6) not null default 0 check(accumulated>=0),
 impairment numeric(20,6) not null default 0 check(impairment>=0),
 cost_account_id uuid not null,accumulated_account_id uuid not null,impairment_account_id uuid not null,
 current_book_id uuid,posted_periods integer not null default 0 check(posted_periods between 0 and 1200),
 current_proposal_id uuid,last_effect_id uuid,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 check(in_service between '0001-01-01'::date and '9999-12-31'::date and accumulated+impairment<=cost),
 check(status<>'active' or cost>0),check(cost_account_id<>accumulated_account_id and cost_account_id<>impairment_account_id
  and accumulated_account_id<>impairment_account_id),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
 foreign key(tenant_id,legal_entity_id,original_branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,location_id) references assets.locations(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,custodian_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,cost_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,accumulated_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,impairment_account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
create table assets.opening_sources(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,
 source_reference text not null check(length(source_reference) between 1 and 160 and source_reference=upper(btrim(source_reference))),
 cost numeric(20,6) not null check(cost>0),opening_accumulated numeric(20,6) not null check(opening_accumulated between 0 and cost),
 components jsonb not null check(jsonb_typeof(components)='array' and jsonb_array_length(components) between 1 and 50),
 reason text not null check(length(btrim(reason)) between 1 and 1000),recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),unique(tenant_id,legal_entity_id,asset_id),
 unique(tenant_id,legal_entity_id,source_reference),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id)
);
create table assets.books(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,version bigint not null,
 basis jsonb not null check(jsonb_typeof(basis)='object'),reason text not null check(length(btrim(reason)) between 1 and 1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id,id),unique(tenant_id,legal_entity_id,asset_id,version),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id)
);
create table assets.schedules(
 tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,book_id uuid not null,
 period_index integer not null check(period_index between 1 and 1200),facts jsonb not null check(jsonb_typeof(facts)='object'),
 primary key(book_id,period_index),
 foreign key(tenant_id,legal_entity_id,asset_id,book_id) references assets.books(tenant_id,legal_entity_id,asset_id,id)
);
create table assets.proposals(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,branch_id uuid not null,
 kind text not null check(kind in('capitalize','book_revision','transfer','impair','revalue','dispose')),
 data jsonb not null check(jsonb_typeof(data)='object'),digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 posting_date date not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table assets.approvals(
 proposal_id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),approved_by uuid not null references auth.users(id),
 reason text not null check(length(btrim(reason)) between 1 and 1000),approved_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,legal_entity_id,asset_id,proposal_id) references assets.proposals(tenant_id,legal_entity_id,asset_id,id)
);
create table assets.effects(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,asset_id uuid not null,branch_id uuid not null,
 kind text not null check(kind in('capitalize','book_revision','transfer','impair','revalue','dispose','depreciate','reverse')),
 proposal_id uuid unique,book_id uuid,period_index integer,posting_date date not null,
 original_effect_id uuid unique,prior_effect_id uuid,journal_id uuid,
 before_context jsonb not null,after_context jsonb not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id,id),unique(book_id,period_index),
 check((kind='reverse')=(original_effect_id is not null)),
 check((kind='depreciate')=(period_index is not null)),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,proposal_id) references assets.proposals(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,book_id) references assets.books(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,original_effect_id) references assets.effects(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id,prior_effect_id) references assets.effects(tenant_id,legal_entity_id,asset_id,id),
 foreign key(tenant_id,journal_id) references finance.journal_entries(tenant_id,id)
);
alter table assets.register add foreign key(tenant_id,legal_entity_id,id,current_book_id)
 references assets.books(tenant_id,legal_entity_id,asset_id,id) deferrable initially deferred;
alter table assets.register add foreign key(tenant_id,legal_entity_id,id,current_proposal_id)
 references assets.proposals(tenant_id,legal_entity_id,asset_id,id) deferrable initially deferred;
alter table assets.register add foreign key(tenant_id,legal_entity_id,id,last_effect_id)
 references assets.effects(tenant_id,legal_entity_id,asset_id,id) deferrable initially deferred;
create function assets.immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='ASSET_HISTORY_IMMUTABLE';end $$;
do $$declare n text;begin
 foreach n in array array['locations','register','opening_sources','books','schedules','proposals','approvals','effects'] loop
  execute format('alter table assets.%I enable row level security',n);
  execute format('alter table assets.%I force row level security',n);
  execute format('revoke all on assets.%I from public,anon,authenticated',n);
  if n<>'register' then execute format('create trigger immutable before update or delete on assets.%I for each row execute function assets.immutable()',n);end if;
 end loop;
end $$;
create index asset_locations_scope_idx on assets.locations(tenant_id,legal_entity_id,branch_id,id);
create index asset_register_scope_idx on assets.register(tenant_id,legal_entity_id,branch_id,id);
create index asset_register_custodian_idx on assets.register(tenant_id,legal_entity_id,custodian_id);
create index asset_register_original_branch_idx on assets.register(tenant_id,legal_entity_id,original_branch_id);
create index asset_register_location_idx on assets.register(tenant_id,legal_entity_id,branch_id,location_id);
create index asset_register_cost_account_idx on assets.register(tenant_id,legal_entity_id,cost_account_id);
create index asset_register_accumulated_account_idx on assets.register(tenant_id,legal_entity_id,accumulated_account_id);
create index asset_register_impairment_account_idx on assets.register(tenant_id,legal_entity_id,impairment_account_id);
create index asset_register_creator_idx on assets.register(created_by);
create index asset_location_creator_idx on assets.locations(created_by);
create index asset_opening_actor_idx on assets.opening_sources(recorded_by);
create index asset_book_actor_idx on assets.books(created_by);
create index asset_proposal_actor_idx on assets.proposals(prepared_by);
create index asset_proposal_branch_idx on assets.proposals(tenant_id,legal_entity_id,branch_id);
create index asset_approval_actor_idx on assets.approvals(approved_by);
create index asset_effect_actor_idx on assets.effects(recorded_by);
create index asset_effect_journal_idx on assets.effects(tenant_id,journal_id);
create index asset_effect_branch_idx on assets.effects(tenant_id,legal_entity_id,branch_id);
create index asset_effects_scope_idx on assets.effects(tenant_id,legal_entity_id,asset_id,id);
create index asset_proposals_scope_idx on assets.proposals(tenant_id,legal_entity_id,asset_id,id);
create function assets.require_access(t uuid,e uuid,b uuid,cap text,p_write boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 if t is null or e is null or b is null or cap is null or cap not in('assets.view','assets.configure','assets.prepare',
  'assets.approve','assets.post','assets.depreciate','assets.reverse','assets.transfer') then
  raise exception using errcode='42501',message='ASSET_SCOPE_DENIED';end if;
 perform core.wave3_require_scope(t,'assets.view',e,b);perform core.wave3_require_scope(t,cap,e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='module.assets' and p.enabled and
  ((s.status='trialing' and s.trial_ends_at>now()) or(s.status='active' and
    (s.current_period_ends_at is null or s.current_period_ends_at>now())))) then
  raise exception using errcode='42501',message='ASSET_ENTITLEMENT_REQUIRED';end if;
 if p_write and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='ASSET_MFA_REQUIRED';end if;
end $$;
create function assets.amount(p jsonb) returns numeric language plpgsql immutable set search_path='' as $$begin
 if p is null or jsonb_typeof(p)<>'string' or p#>>'{}' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then
  raise exception using errcode='22023',message='ASSET_AMOUNT_INVALID';end if;return (p#>>'{}')::numeric;end $$;
create function assets.ratio(n numeric,d numeric,p integer) returns numeric language plpgsql immutable set search_path='' as $$
declare q numeric;r numeric;divisor numeric;begin
 if n is null or d is null or p is null or n<0 or d<=0 or p not between 0 and 6 or n<>trunc(n) or d<>trunc(d) then
  raise exception using errcode='22023',message='ASSET_ROUNDING_INVALID';end if;
 divisor:=d*power(10::numeric,6-p);q:=div(n,divisor);r:=mod(n,divisor);
 if r*2>divisor or(r*2=divisor and mod(q,2)=1) then q:=q+1;end if;return q*power(10::numeric,6-p);
end $$;
create function assets.round_even(n numeric,p integer) returns numeric language sql immutable set search_path='' as $$
 select assets.ratio(n*1000000,1,p)/1000000 $$;
create function assets.schedule(cost text,accum text,impair text,residual text,months integer,method text,
 n bigint,d bigint,p_precision integer,first_date date) returns jsonb language plpgsql immutable set search_path='' as $$
declare c numeric:=assets.amount(to_jsonb(cost));a numeric:=assets.amount(to_jsonb(accum));
 m numeric:=assets.amount(to_jsonb(impair));r numeric:=assets.amount(to_jsonb(residual));
 carrying numeric;depreciable numeric;last_target numeric:=0;target numeric;dep numeric;i integer;s date;ed date;rows jsonb:='[]';begin
 -- Exact validation is separate from all date/amount computations.
 if months is null or months not between 1 and 1200 or method is null or method not in('straight_line','reducing_balance')
  or n is null or d is null or n not between 1 and 9007199254740991 or d not between 1 and 9007199254740991 or n>d
  or p_precision is null or p_precision not between 0 and 6 or first_date is null
  or first_date<>date_trunc('month',first_date)::date or first_date<'0001-01-01'::date
  or (first_date+make_interval(months=>months))::date>'9999-12-31'::date
  or c<=0 or a+m>c or r>c-a-m or c<>round(c,p_precision) or a<>round(a,p_precision)
  or m<>round(m,p_precision) or r<>round(r,p_precision) then
  raise exception using errcode='22023',message='ASSET_BOOK_INVALID';end if;
 carrying:=c-a-m;depreciable:=carrying-r;
 for i in 1..months loop
  s:=(first_date+make_interval(months=>i-1))::date;ed:=(first_date+make_interval(months=>i))::date;
  if i=months then dep:=carrying-r;
  elsif method='straight_line' then target:=assets.ratio(depreciable*1000000*i,months,p_precision)/1000000;
   dep:=target-last_target;last_target:=target;
  else dep:=least(carrying-r,assets.ratio(carrying*1000000*n,d,p_precision)/1000000);end if;
  if dep<0 or dep>carrying-r then raise exception using errcode='22023',message='ASSET_SCHEDULE_INVALID';end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('period_index',i,'start_date',s,'end_date_exclusive',ed,'posting_date',ed-1,
   'opening_carrying',round(carrying,6)::text,'depreciation',round(dep,6)::text,'closing_carrying',round(carrying-dep,6)::text,
   'accumulated_closing',round(a+dep,6)::text));carrying:=carrying-dep;a:=a+dep;
 end loop;return rows;
end $$;
create function assets.account(t uuid,e uuid,p_id uuid,kind text,currency text) returns void
language plpgsql security definer set search_path='' as $$declare ap boolean:=false;begin
 perform 1 from finance.accounts where tenant_id=t and legal_entity_id=e and id=p_id for share;
 perform finance.flow_account(t,e,p_id,kind,currency);
 if exists(select 1 from finance.posting_mappings where tenant_id=t and legal_entity_id=e and account_id=p_id
  and purpose in('receivable_control','payable_control')) then
  raise exception using errcode='55000',message='ASSET_SEPARATE_CONTROL_REQUIRED';end if;
 if to_regclass('procurement.supplier_bill_controls') is not null then
  execute 'select exists(select 1 from procurement.supplier_bill_controls where tenant_id=$1 and legal_entity_id=$2 and payable_account_id=$3)'
   into ap using t,e,p_id;
 end if;if ap then raise exception using errcode='55000',message='ASSET_SEPARATE_CONTROL_REQUIRED';end if;
end $$;
create function assets.place(t uuid,e uuid,b uuid,location uuid,custodian uuid,on_date date) returns void
language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from assets.locations where tenant_id=t and legal_entity_id=e and branch_id=b and id=location) then
  raise exception using errcode='55000',message='ASSET_LOCATION_INVALID';end if;
 if custodian is not null and not exists(select 1 from people.employees x join people.employment_assignments a
  on a.employee_id=x.id and a.tenant_id=x.tenant_id and a.legal_entity_id=x.legal_entity_id
  join people.employment_spells s on s.id=a.spell_id and s.tenant_id=a.tenant_id and s.legal_entity_id=a.legal_entity_id and s.employee_id=a.employee_id
  where x.tenant_id=t and x.legal_entity_id=e and x.id=custodian and a.branch_id=b
  and a.start_date<=on_date and(a.end_date_exclusive is null or a.end_date_exclusive>on_date)
  and s.start_date<=on_date and(s.end_date_exclusive is null or s.end_date_exclusive>on_date)) then
  raise exception using errcode='55000',message='ASSET_CUSTODIAN_INVALID';end if;
end $$;
create function assets.snapshot(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('branch_id',branch_id,'location_id',location_id,'custodian_id',custodian_id,'status',status,
  'cost',cost::text,'accumulated',accumulated::text,'impairment',impairment::text,'book_id',current_book_id,
  'posted_periods',posted_periods,'last_effect_id',last_effect_id) from assets.register where id=p_id $$;
create function assets.summary(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',id,'tenant_id',tenant_id,'legal_entity_id',legal_entity_id,'branch_id',branch_id,
  'original_branch_id',original_branch_id,'code',code,'name',name,'ownership',ownership,'currency_code',currency_code,
  'in_service',in_service,'location_id',location_id,'custodian_id',custodian_id,'status',status,'version',version,
  'cost',cost::text,'accumulated',accumulated::text,'impairment',impairment::text,'carrying',(cost-accumulated-impairment)::text,
  'cost_account_id',cost_account_id,'accumulated_account_id',accumulated_account_id,'impairment_account_id',impairment_account_id,
  'book_id',current_book_id,'posted_periods',posted_periods,'proposal_id',current_proposal_id,'last_effect_id',last_effect_id)
 from assets.register where id=p_id $$;
create function assets.book_validate(data jsonb,cost numeric,accum numeric,impair numeric,start_date date,in_service date,
 currency text,t uuid,e uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if coalesce(jsonb_typeof(data),'null')<>'object' or exists(select 1 from jsonb_object_keys(data) k where k<>all(
  array['residual','remaining_months','method','convention','rate_numerator','rate_denominator','precision','expense_account_id']))
 or data->>'convention' is null or data->>'convention' not in('in_service_month','next_month')
  or start_date<(date_trunc('month',in_service)+case when data->>'convention'='next_month' then interval '1 month' else interval '0' end)::date
  or coalesce(data->>'remaining_months','') !~ '^[0-9]{1,4}$' or coalesce(data->>'precision','') !~ '^[0-6]$'
  or coalesce(data->>'rate_numerator','') !~ '^[0-9]{1,16}$' or coalesce(data->>'rate_denominator','') !~ '^[0-9]{1,16}$'
  or jsonb_typeof(data->'remaining_months') is distinct from 'number' or jsonb_typeof(data->'precision') is distinct from 'number'
  or jsonb_typeof(data->'rate_numerator') is distinct from 'number' or jsonb_typeof(data->'rate_denominator') is distinct from 'number'
  then raise exception using errcode='22023',message='ASSET_BOOK_INVALID';end if;
 perform assets.schedule(cost::text,accum::text,impair::text,assets.amount(data->'residual')::text,(data->>'remaining_months')::integer,
  data->>'method',(data->>'rate_numerator')::bigint,(data->>'rate_denominator')::bigint,(data->>'precision')::integer,start_date);
 perform assets.account(t,e,(data->>'expense_account_id')::uuid,'expense',currency);
 result:=data||jsonb_build_object('cost',cost::text,'opening_accumulated',accum::text,'opening_impairment',impair::text,
  'start_date',start_date,'in_service',in_service,'currency_code',currency,'residual',round(assets.amount(data->'residual'),6)::text);
 return result;
end $$;
create function assets.materialize_book(t uuid,e uuid,asset uuid,proposal uuid,basis jsonb,reason text) returns void
language plpgsql security definer set search_path='' as $$declare v bigint;begin
 select coalesce(max(version),0)+1 into v from assets.books where tenant_id=t and legal_entity_id=e and asset_id=asset;
 insert into assets.books(id,tenant_id,legal_entity_id,asset_id,version,basis,reason,created_by)
  values(proposal,t,e,asset,v,basis,reason,auth.uid());
 insert into assets.schedules(tenant_id,legal_entity_id,asset_id,book_id,period_index,facts)
  select t,e,asset,proposal,(x->>'period_index')::integer,x from jsonb_array_elements(assets.schedule(
   basis->>'cost',basis->>'opening_accumulated',basis->>'opening_impairment',basis->>'residual',
   (basis->>'remaining_months')::integer,basis->>'method',(basis->>'rate_numerator')::bigint,
   (basis->>'rate_denominator')::bigint,(basis->>'precision')::integer,(basis->>'start_date')::date)) x;
end $$;
create function api.assets_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability,p_capability<>'assets.view');
 return jsonb_build_object('actor_id',auth.uid(),'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'capability',p_capability,'authorized',true,'procurement_provider',false,'stock_provider',false,'equipment_provider',false,
  'currency_code',(select currency_code from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
  'currency_precision',(select rounding_scale from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
  'business_date',(select (now() at time zone timezone)::date from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id));
end $$;
create function api.assets_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
<<asset_work>>
declare act text:=p_payload->>'action';cap text;id uuid;prop uuid;reason text;hash text;replay jsonb;request uuid:=gen_random_uuid();
 r assets.register%rowtype;p assets.proposals%rowtype;original assets.effects%rowtype;book jsonb;data jsonb;basis jsonb;
 before_state jsonb;after_state jsonb;cost numeric;accum numeric;impair numeric;amount numeric;proceeds numeric;delta numeric;
 start_date date;posting date;today date;rows jsonb;lines jsonb:='[]';journal uuid;effect uuid:=gen_random_uuid();
 next_branch uuid;location uuid;custodian uuid;offset_id uuid;gain_id uuid;loss_id uuid;proceeds_id uuid;current_period jsonb;
 component jsonb;total numeric:=0;source_reference text;allowed text[];transfer_branch uuid;begin
 if coalesce(jsonb_typeof(p_payload),'null')<>'object' or act is null or act not in('location','opening','propose','approve','post','depreciate','reverse','cancel')
  or p_command_id is null or p_idempotency_key is null or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes'
  or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 or octet_length(p_payload::text)>65536
  or jsonb_typeof(p_payload->'reason') is distinct from 'string'
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='ASSET_COMMAND_INVALID';end if;
 allowed:=case act when 'location' then array['action','id','code','name','reason']
  when 'opening' then array['action','id','proposal_id','source_id','source_reference','code','name','ownership','in_service','location_id','custodian_id',
   'cost','opening_accumulated','cost_components','cost_account_id','accumulated_account_id','impairment_account_id','offset_account_id','book','posting_date','currency_code','reason']
  when 'propose' then array['action','id','proposal_id','kind','book','destination_branch_id','location_id','custodian_id','amount','cost',
   'surplus_account_id','loss_account_id','proceeds','proceeds_account_id','gain_account_id','posting_date','reason']
  when 'depreciate' then array['action','id','book_id','period_index','reason']
  when 'reverse' then array['action','id','effect_id','reason'] else array['action','id','proposal_id','digest','reason'] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then
  raise exception using errcode='22023',message='ASSET_COMMAND_FIELDS_INVALID';end if;
 cap:=case act when 'location' then 'assets.configure' when 'approve' then 'assets.approve' when 'post' then 'assets.post'
  when 'depreciate' then 'assets.depreciate' when 'reverse' then 'assets.reverse' else 'assets.prepare' end;
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 id:=(p_payload->>'id')::uuid;reason:=btrim(p_payload->>'reason');
 -- All original transfer authorities are rechecked before actor-bound replay.
 if act='propose' and p_payload->>'kind'='transfer' then transfer_branch:=(p_payload->>'destination_branch_id')::uuid;
 elsif act in('approve','post','cancel') then
  select (q.data->>'branch_id')::uuid into transfer_branch from assets.proposals q
   where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.branch_id=p_branch_id
    and q.asset_id=id and q.id=(p_payload->>'proposal_id')::uuid and q.kind='transfer';
 elsif act='reverse' then
  select (q.before_context->>'branch_id')::uuid into transfer_branch from assets.effects q
   where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.asset_id=id
    and q.id=(p_payload->>'effect_id')::uuid and q.kind='transfer';
 end if;
 if transfer_branch is not null then
  perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
  perform assets.require_access(p_tenant_id,p_legal_entity_id,transfer_branch,'assets.transfer',true);
 end if;
 hash:=core.wave3_request_hash('assets.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'assets.'||act,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 select (now() at time zone timezone)::date into today from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
 if act in('location','opening') then
  if p_expected_version<>0 or jsonb_typeof(p_payload->'code') is distinct from 'string' or jsonb_typeof(p_payload->'name') is distinct from 'string'
   or coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'
   or length(btrim(coalesce(p_payload->>'name',''))) not between 1 and 160 then
   raise exception using errcode='22023',message='ASSET_CREATE_INVALID';end if;
  if act='location' then
   insert into assets.locations(id,tenant_id,legal_entity_id,branch_id,code,name,created_by)
    values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',btrim(p_payload->>'name'),auth.uid());
   return core.wave3_finish_command(p_tenant_id,'assets.location',p_command_id,'assets.location',id,p_idempotency_key,hash,null,
    jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'version',1),
    p_legal_entity_id,p_branch_id,p_request_id=>request);
  end if;
  prop:=(p_payload->>'proposal_id')::uuid;cost:=assets.amount(p_payload->'cost');accum:=assets.amount(p_payload->'opening_accumulated');
  if p_payload->>'currency_code' is distinct from(select currency_code from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id) then
   raise exception using errcode='55000',message='ASSET_BASE_CURRENCY_CHANGED';end if;
  posting:=(p_payload->>'posting_date')::date;source_reference:=upper(btrim(p_payload->>'source_reference'));
  if prop is null or (p_payload->>'source_id')::uuid is null or cost<=0 or accum>cost
   or length(btrim(coalesce(p_payload->>'ownership',''))) not between 1 and 160
   or jsonb_typeof(p_payload->'ownership') is distinct from 'string' or jsonb_typeof(p_payload->'source_reference') is distinct from 'string'
   or length(coalesce(source_reference,'')) not between 1 and 160 or source_reference ~ '[[:cntrl:]]'
   or posting is null or posting>today or (p_payload->>'in_service')::date is null or posting<(p_payload->>'in_service')::date
   or coalesce(jsonb_typeof(p_payload->'cost_components'),'null')<>'array'
   or jsonb_array_length(p_payload->'cost_components') not between 1 and 50 then
   raise exception using errcode='22023',message='ASSET_OPENING_INVALID';end if;
  for component in select value from jsonb_array_elements(p_payload->'cost_components') loop
   if coalesce(jsonb_typeof(component),'null')<>'object' or exists(select 1 from jsonb_object_keys(component) k where k<>all(array['code','name','amount']))
    or jsonb_typeof(component->'code') is distinct from 'string' or jsonb_typeof(component->'name') is distinct from 'string'
    or coalesce(component->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or length(btrim(coalesce(component->>'name',''))) not between 1 and 160 then
    raise exception using errcode='22023',message='ASSET_COMPONENT_INVALID';end if;
   total:=total+assets.amount(component->'amount');
  end loop;
  if total<>cost or(select count(distinct x->>'code') from jsonb_array_elements(p_payload->'cost_components') x)<>jsonb_array_length(p_payload->'cost_components') then
   raise exception using errcode='22023',message='ASSET_COMPONENT_INVALID';end if;
  perform pg_advisory_xact_lock(hashtextextended('assets.opening:'||p_tenant_id||':'||p_legal_entity_id||':'||source_reference,0));
  if exists(select 1 from assets.opening_sources where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and opening_sources.source_reference=asset_work.source_reference) then
   raise exception using errcode='55000',message='ASSET_SOURCE_ALREADY_OWNED';end if;
  perform assets.place(p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'location_id')::uuid,(p_payload->>'custodian_id')::uuid,posting);
  -- The register holds no authoritative cost until independent approval/posting.
  insert into assets.register(id,tenant_id,legal_entity_id,original_branch_id,branch_id,code,name,ownership,currency_code,in_service,location_id,custodian_id,
   cost_account_id,accumulated_account_id,impairment_account_id,current_proposal_id,created_by)
   select id,p_tenant_id,p_legal_entity_id,p_branch_id,p_branch_id,p_payload->>'code',btrim(p_payload->>'name'),btrim(p_payload->>'ownership'),currency_code,
    (p_payload->>'in_service')::date,(p_payload->>'location_id')::uuid,(p_payload->>'custodian_id')::uuid,
    (p_payload->>'cost_account_id')::uuid,(p_payload->>'accumulated_account_id')::uuid,(p_payload->>'impairment_account_id')::uuid,prop,auth.uid()
   from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
  select * into r from assets.register where register.id=id;
  perform assets.account(p_tenant_id,p_legal_entity_id,r.cost_account_id,'asset',r.currency_code);
  perform assets.account(p_tenant_id,p_legal_entity_id,r.accumulated_account_id,'asset',r.currency_code);
  perform assets.account(p_tenant_id,p_legal_entity_id,r.impairment_account_id,'asset',r.currency_code);
  offset_id:=(p_payload->>'offset_account_id')::uuid;perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,'equity',r.currency_code);
  start_date:=(date_trunc('month',r.in_service)+case when p_payload->'book'->>'convention'='next_month' then interval '1 month' else interval '0' end)::date;
  basis:=assets.book_validate(p_payload->'book',cost,accum,0,start_date,r.in_service,r.currency_code,p_tenant_id,p_legal_entity_id);
  insert into assets.opening_sources(id,tenant_id,legal_entity_id,asset_id,source_reference,cost,opening_accumulated,components,reason,recorded_by)
   values((p_payload->>'source_id')::uuid,p_tenant_id,p_legal_entity_id,id,source_reference,cost,accum,p_payload->'cost_components',reason,auth.uid());
  data:=jsonb_build_object('book',basis,'offset_account_id',offset_id,'source_id',p_payload->>'source_id');
  insert into assets.proposals(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,data,digest,posting_date,reason,prepared_by)
   values(prop,p_tenant_id,p_legal_entity_id,id,p_branch_id,'capitalize',data,encode(extensions.digest(convert_to(data::text,'UTF8'),'sha256'),'hex'),posting,reason,auth.uid());
 else
  select * into r from assets.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and register.id=id for update;
  if r.id is null then raise exception using errcode='P0002',message='ASSET_NOT_FOUND';end if;
  if r.version<>p_expected_version then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  if r.currency_code is distinct from(select currency_code from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id) then
   raise exception using errcode='55000',message='ASSET_BASE_CURRENCY_CHANGED';end if;
  before_state:=assets.snapshot(id);
  if act='propose' then
   if r.status<>'active' or r.current_proposal_id is not null then raise exception using errcode='55000',message='ASSET_STATE_INVALID';end if;
   prop:=(p_payload->>'proposal_id')::uuid;posting:=(p_payload->>'posting_date')::date;
   if prop is null or posting is null or posting>today or p_payload->>'kind' is null
    or p_payload->>'kind' not in('book_revision','transfer','impair','revalue','dispose') then
    raise exception using errcode='22023',message='ASSET_PROPOSAL_INVALID';end if;
   allowed:=array['action','id','proposal_id','kind','posting_date','reason']||case p_payload->>'kind'
    when 'book_revision' then array['book'] when 'transfer' then array['destination_branch_id','location_id','custodian_id']
    when 'impair' then array['amount','loss_account_id'] when 'revalue' then array['cost','surplus_account_id','loss_account_id']
    else array['proceeds','proceeds_account_id','gain_account_id','loss_account_id'] end;
   if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then
    raise exception using errcode='22023',message='ASSET_COMMAND_FIELDS_INVALID';end if;
   if exists(select 1 from assets.effects where effects.id=r.last_effect_id and posting_date>posting) then
    raise exception using errcode='55000',message='ASSET_EFFECT_DATE_INVALID';end if;
   select b.basis into book from assets.books b where b.id=r.current_book_id;
   if p_payload->>'kind'='transfer' then
    next_branch:=(p_payload->>'destination_branch_id')::uuid;location:=(p_payload->>'location_id')::uuid;custodian:=(p_payload->>'custodian_id')::uuid;
    perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
    perform assets.require_access(p_tenant_id,p_legal_entity_id,next_branch,'assets.transfer',true);
    perform assets.place(p_tenant_id,p_legal_entity_id,next_branch,location,custodian,posting);
    data:=jsonb_build_object('branch_id',next_branch,'location_id',location,'custodian_id',custodian);
   elsif p_payload->>'kind'='dispose' then
    proceeds:=assets.amount(p_payload->'proceeds');proceeds_id:=(p_payload->>'proceeds_account_id')::uuid;
    gain_id:=(p_payload->>'gain_account_id')::uuid;loss_id:=(p_payload->>'loss_account_id')::uuid;
    perform assets.account(p_tenant_id,p_legal_entity_id,proceeds_id,'asset',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,gain_id,'revenue',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
    if proceeds_id in(r.cost_account_id,r.accumulated_account_id,r.impairment_account_id) or proceeds<>round(proceeds,(book->>'precision')::integer) then
     raise exception using errcode='22023',message='ASSET_DISPOSAL_INVALID';end if;
    data:=jsonb_build_object('proceeds',round(proceeds,6)::text,'proceeds_account_id',proceeds_id,'gain_account_id',gain_id,'loss_account_id',loss_id,
     'cost',r.cost::text,'accumulated',r.accumulated::text,'impairment',r.impairment::text,'carrying',(r.cost-r.accumulated-r.impairment)::text,
     'gain_loss',round(proceeds-r.cost+r.accumulated+r.impairment,6)::text);
   else
    select (s.facts->>'start_date')::date into start_date from assets.schedules s where s.book_id=r.current_book_id and s.period_index=r.posted_periods+1;
    if start_date is null then raise exception using errcode='55000',message='ASSET_UNPOSTED_PERIOD_REQUIRED';end if;
    cost:=r.cost;impair:=r.impairment;
    if p_payload->>'kind'='book_revision' then basis:=p_payload->'book';
    else
     basis:=book-array['cost','opening_accumulated','opening_impairment','start_date','in_service','currency_code'];
     basis:=basis||jsonb_build_object('remaining_months',(book->>'remaining_months')::integer-r.posted_periods);
     if p_payload->>'kind'='impair' then
      amount:=assets.amount(p_payload->'amount');if amount<=0 then raise exception using errcode='22023',message='ASSET_IMPAIRMENT_INVALID';end if;
      impair:=impair+amount;loss_id:=(p_payload->>'loss_account_id')::uuid;
      perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
      data:=jsonb_build_object('amount',round(amount,6)::text,'loss_account_id',loss_id);
     else
      cost:=assets.amount(p_payload->'cost');if cost=r.cost then raise exception using errcode='22023',message='ASSET_REVALUATION_INVALID';end if;
      offset_id:=(p_payload->>'surplus_account_id')::uuid;loss_id:=(p_payload->>'loss_account_id')::uuid;
      perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,'equity',r.currency_code);
      perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
      data:=jsonb_build_object('cost',round(cost,6)::text,'surplus_account_id',offset_id,'loss_account_id',loss_id);
     end if;
    end if;
    basis:=assets.book_validate(basis,cost,r.accumulated,impair,start_date,r.in_service,r.currency_code,p_tenant_id,p_legal_entity_id);
    data:=coalesce(data,'{}')||jsonb_build_object('book',basis);
   end if;
   data:=data||jsonb_build_object('before',before_state);
   insert into assets.proposals(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,data,digest,posting_date,reason,prepared_by)
    values(prop,p_tenant_id,p_legal_entity_id,id,p_branch_id,p_payload->>'kind',data,encode(extensions.digest(convert_to(data::text,'UTF8'),'sha256'),'hex'),posting,reason,auth.uid());
   update assets.register set current_proposal_id=prop,version=version+1 where register.id=id;
  elsif act in('approve','post','cancel') then
   prop:=(p_payload->>'proposal_id')::uuid;
   select * into p from assets.proposals where proposals.id=prop and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=id;
   if p.id is null or r.current_proposal_id is distinct from prop or p.digest is distinct from p_payload->>'digest' then
    raise exception using errcode='55000',message='ASSET_PROPOSAL_STALE';end if;
   if p.kind='transfer' then
    perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
    perform assets.require_access(p_tenant_id,p_legal_entity_id,(p.data->>'branch_id')::uuid,'assets.transfer',true);
   end if;
   if act='approve' then
    if auth.uid()=p.prepared_by or exists(select 1 from assets.approvals where proposal_id=prop) then
     raise exception using errcode='42501',message='ASSET_INDEPENDENT_APPROVAL_REQUIRED';end if;
    insert into assets.approvals(proposal_id,tenant_id,legal_entity_id,asset_id,digest,approved_by,reason)
     values(prop,p_tenant_id,p_legal_entity_id,id,p.digest,auth.uid(),reason);
    update assets.register set version=version+1 where register.id=id;
   elsif act='cancel' then update assets.register set current_proposal_id=null,version=version+1 where register.id=id;
   else
    if not exists(select 1 from assets.approvals where proposal_id=prop and digest=p.digest and approved_by<>p.prepared_by) then
     raise exception using errcode='55000',message='ASSET_APPROVAL_REQUIRED';end if;
    if p.posting_date>today or(p.kind<>'capitalize' and p.data->'before' is distinct from before_state) then
     raise exception using errcode='55000',message='ASSET_PROPOSAL_STALE';end if;
    perform assets.account(p_tenant_id,p_legal_entity_id,r.cost_account_id,'asset',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,r.accumulated_account_id,'asset',r.currency_code);
    perform assets.account(p_tenant_id,p_legal_entity_id,r.impairment_account_id,'asset',r.currency_code);
    if p.kind in('capitalize','book_revision','impair','revalue') then
     basis:=p.data->'book';perform assets.account(p_tenant_id,p_legal_entity_id,(basis->>'expense_account_id')::uuid,'expense',r.currency_code);
    end if;
    if p.kind='capitalize' then
     if r.status<>'draft' or exists(select 1 from assets.effects where asset_id=id and kind='capitalize') then
      raise exception using errcode='55000',message='ASSET_SOURCE_ALREADY_OWNED';end if;
     cost:=(basis->>'cost')::numeric;accum:=(basis->>'opening_accumulated')::numeric;offset_id:=(p.data->>'offset_account_id')::uuid;
     perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,'equity',r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',r.cost_account_id,'amount',cost::text,'base_amount',cost::text,'source_line_id',p.data->>'source_id'),
      jsonb_build_object('account_id',r.accumulated_account_id,'amount',(-accum)::text,'base_amount',(-accum)::text,'source_line_id',p.data->>'source_id'),
      jsonb_build_object('account_id',offset_id,'amount',(-(cost-accum))::text,'base_amount',(-(cost-accum))::text,'source_line_id',p.data->>'source_id'));
     update assets.register set cost=asset_work.cost,accumulated=accum,status='active' where register.id=id;
    elsif p.kind='transfer' then
     next_branch:=(p.data->>'branch_id')::uuid;location:=(p.data->>'location_id')::uuid;custodian:=(p.data->>'custodian_id')::uuid;
     perform assets.place(p_tenant_id,p_legal_entity_id,next_branch,location,custodian,p.posting_date);
     update assets.register set branch_id=next_branch,location_id=location,custodian_id=custodian where register.id=id;
    elsif p.kind='impair' then
     amount:=(p.data->>'amount')::numeric;loss_id:=(p.data->>'loss_account_id')::uuid;
     perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',loss_id,'amount',amount::text,'base_amount',amount::text,'source_line_id',prop),
      jsonb_build_object('account_id',r.impairment_account_id,'amount',(-amount)::text,'base_amount',(-amount)::text,'source_line_id',prop));
     update assets.register set impairment=impairment+amount where register.id=id;
    elsif p.kind='revalue' then
     cost:=(p.data->>'cost')::numeric;delta:=cost-r.cost;
     offset_id:=case when delta>0 then (p.data->>'surplus_account_id')::uuid else(p.data->>'loss_account_id')::uuid end;
     perform assets.account(p_tenant_id,p_legal_entity_id,offset_id,case when delta>0 then 'equity' else 'expense' end,r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',r.cost_account_id,'amount',delta::text,'base_amount',delta::text,'source_line_id',prop),
      jsonb_build_object('account_id',offset_id,'amount',(-delta)::text,'base_amount',(-delta)::text,'source_line_id',prop));
     update assets.register set cost=asset_work.cost where register.id=id;
    elsif p.kind='dispose' then
     proceeds:=(p.data->>'proceeds')::numeric;delta:=(p.data->>'gain_loss')::numeric;
     proceeds_id:=(p.data->>'proceeds_account_id')::uuid;gain_id:=(p.data->>'gain_account_id')::uuid;loss_id:=(p.data->>'loss_account_id')::uuid;
     perform assets.account(p_tenant_id,p_legal_entity_id,proceeds_id,'asset',r.currency_code);
     perform assets.account(p_tenant_id,p_legal_entity_id,gain_id,'revenue',r.currency_code);
     perform assets.account(p_tenant_id,p_legal_entity_id,loss_id,'expense',r.currency_code);
     lines:=jsonb_build_array(jsonb_build_object('account_id',r.cost_account_id,'amount',(-r.cost)::text,'base_amount',(-r.cost)::text,'source_line_id',prop),
      jsonb_build_object('account_id',r.accumulated_account_id,'amount',r.accumulated::text,'base_amount',r.accumulated::text,'source_line_id',prop),
      jsonb_build_object('account_id',r.impairment_account_id,'amount',r.impairment::text,'base_amount',r.impairment::text,'source_line_id',prop),
      jsonb_build_object('account_id',proceeds_id,'amount',proceeds::text,'base_amount',proceeds::text,'source_line_id',prop),
      jsonb_build_object('account_id',case when delta>0 then gain_id else loss_id end,'amount',(-delta)::text,'base_amount',(-delta)::text,'source_line_id',prop));
     update assets.register set status='disposed' where register.id=id;
    end if;
    if jsonb_array_length(lines)>0 then
     journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
      'document_date',p.posting_date,'currency_code',r.currency_code,'base_currency_code',r.currency_code,'exchange_rate','1.000000'),
      lines,'asset_'||p.kind,effect,request,p_command_id);
    end if;
    if p.kind in('capitalize','book_revision','impair','revalue') then
     perform assets.materialize_book(p_tenant_id,p_legal_entity_id,id,prop,basis,p.reason);
     update assets.register set current_book_id=prop,posted_periods=0 where register.id=id;
    end if;
    update assets.register set current_proposal_id=null,last_effect_id=effect,version=version+1 where register.id=id;
    after_state:=assets.snapshot(id);
    insert into assets.effects(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,proposal_id,book_id,posting_date,prior_effect_id,journal_id,before_context,after_context,reason,recorded_by)
     values(effect,p_tenant_id,p_legal_entity_id,id,p_branch_id,p.kind,prop,case when p.kind in('capitalize','book_revision','impair','revalue') then prop else r.current_book_id end,
      p.posting_date,r.last_effect_id,journal,before_state,after_state,reason,auth.uid());
   end if;
  elsif act='depreciate' then
   if r.status<>'active' or r.current_proposal_id is not null or r.current_book_id is distinct from(p_payload->>'book_id')::uuid
    or jsonb_typeof(p_payload->'period_index') is distinct from 'number'
    or coalesce(p_payload->>'period_index','') !~ '^[0-9]{1,4}$' or(p_payload->>'period_index')::integer<>r.posted_periods+1 then
    raise exception using errcode='55000',message='ASSET_SCHEDULE_STALE';end if;
   select s.facts into current_period from assets.schedules s where s.book_id=r.current_book_id and s.period_index=r.posted_periods+1;
   select b.basis into book from assets.books b where b.id=r.current_book_id;
   if current_period is null or(current_period->>'posting_date')::date>today
    or(current_period->>'opening_carrying')::numeric<>r.cost-r.accumulated-r.impairment then
    raise exception using errcode='55000',message='ASSET_SCHEDULE_STALE';end if;
   if exists(select 1 from assets.effects where book_id=r.current_book_id and period_index=r.posted_periods+1) then
    raise exception using errcode='55000',message='ASSET_REBOOK_AFTER_REVERSAL_REQUIRED';end if;
   perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,(current_period->>'posting_date')::date);
   perform assets.account(p_tenant_id,p_legal_entity_id,(book->>'expense_account_id')::uuid,'expense',r.currency_code);
   perform assets.account(p_tenant_id,p_legal_entity_id,r.accumulated_account_id,'asset',r.currency_code);
   amount:=(current_period->>'depreciation')::numeric;
   if amount>0 then
    lines:=jsonb_build_array(jsonb_build_object('account_id',book->>'expense_account_id','amount',amount::text,'base_amount',amount::text,'source_line_id',effect),
     jsonb_build_object('account_id',r.accumulated_account_id,'amount',(-amount)::text,'base_amount',(-amount)::text,'source_line_id',effect));
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',current_period->>'posting_date','currency_code',r.currency_code,'base_currency_code',r.currency_code,'exchange_rate','1.000000'),
     lines,'asset_depreciate',effect,request,p_command_id);
   end if;
   update assets.register set accumulated=accumulated+amount,posted_periods=posted_periods+1,last_effect_id=effect,version=version+1 where register.id=id;
   insert into assets.effects(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,book_id,period_index,posting_date,prior_effect_id,journal_id,before_context,after_context,reason,recorded_by)
    values(effect,p_tenant_id,p_legal_entity_id,id,p_branch_id,'depreciate',r.current_book_id,r.posted_periods+1,(current_period->>'posting_date')::date,
     r.last_effect_id,journal,before_state,assets.snapshot(id),reason,auth.uid());
  else
   if r.current_proposal_id is not null then raise exception using errcode='55000',message='ASSET_STATE_INVALID';end if;
   select * into original from assets.effects where effects.id=(p_payload->>'effect_id')::uuid and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=id;
   if original.id is null or original.kind='reverse' or r.last_effect_id is distinct from original.id
    or exists(select 1 from assets.effects where original_effect_id=original.id) then
    raise exception using errcode='55000',message='ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL';end if;
   next_branch:=(original.before_context->>'branch_id')::uuid;
   if original.kind='transfer' then
    perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
    perform assets.require_access(p_tenant_id,p_legal_entity_id,next_branch,'assets.transfer',true);
   end if;
   if original.journal_id is not null then
    select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,
     'amount',(transaction_credit-transaction_debit)::text,'base_amount',(base_credit-base_debit)::text) order by line_number) into lines
     from finance.journal_lines where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=original.journal_id;
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',original.posting_date,'currency_code',r.currency_code,'base_currency_code',r.currency_code,'exchange_rate','1.000000'),
     lines,'asset_reverse',effect,request,p_command_id);
   else perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,original.posting_date);end if;
   data:=original.before_context;
   update assets.register set branch_id=next_branch,location_id=(data->>'location_id')::uuid,custodian_id=(data->>'custodian_id')::uuid,
    status=case when original.kind='capitalize' then 'reversed' else data->>'status' end,cost=(data->>'cost')::numeric,
    accumulated=(data->>'accumulated')::numeric,impairment=(data->>'impairment')::numeric,current_book_id=(data->>'book_id')::uuid,
    posted_periods=(data->>'posted_periods')::integer,last_effect_id=original.prior_effect_id,version=version+1 where register.id=id;
   insert into assets.effects(id,tenant_id,legal_entity_id,asset_id,branch_id,kind,posting_date,original_effect_id,prior_effect_id,journal_id,before_context,after_context,reason,recorded_by)
    values(effect,p_tenant_id,p_legal_entity_id,id,p_branch_id,'reverse',original.posting_date,original.id,r.last_effect_id,journal,before_state,assets.snapshot(id),reason,auth.uid());
  end if;
 end if;
 select * into r from assets.register where register.id=id;
 -- Only IDs/version/state enter generic receipts/audit/outbox, never evidence or financial values.
 after_state:=jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'current_branch_id',r.branch_id,
  'version',r.version,'status',r.status,'proposal_id',r.current_proposal_id,'book_id',r.current_book_id,'last_effect_id',r.last_effect_id);
 return core.wave3_finish_command(p_tenant_id,'assets.'||act,p_command_id,'assets.asset',id,p_idempotency_key,hash,null,after_state,
  p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object('action',act,'transfer_branch_id',transfer_branch),p_request_id=>request);
end $$;
create function api.assets_register(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select coalesce(jsonb_agg(assets.summary(q.id) order by q.id),'[]'::jsonb) into items from(select id from assets.register
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function assets.label(t uuid,e uuid,kind text,p_id uuid) returns text language plpgsql stable set search_path='' as $$
declare label text;begin
 if kind='account' then select code||' · '||name into label from finance.accounts where tenant_id=t and legal_entity_id=e and id=p_id;
 elsif kind='location' then select code||' · '||name into label from assets.locations where tenant_id=t and legal_entity_id=e and id=p_id;
 elsif kind='custodian' then select code||' · '||display_name into label from people.employees where tenant_id=t and legal_entity_id=e and id=p_id;
 elsif kind='branch' then select code||' · '||name into label from core.branches where tenant_id=t and legal_entity_id=e and id=p_id;end if;
 return label;
end $$;
create function api.assets_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_asset_id uuid,p_kind text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;prop jsonb;opening jsonb;summary jsonb;labels jsonb;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if p_kind is null or p_kind not in('books','effects','proposals') then raise exception using errcode='22023',message='ASSET_PAGE_INVALID';end if;
 if not exists(select 1 from assets.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_asset_id) then
  raise exception using errcode='P0002',message='ASSET_NOT_FOUND';end if;
 if p_kind='books' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select * from assets.books
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='effects' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from(select * from assets.effects
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id and(p_after is null or id>p_after) order by id limit 51) q;
 else select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('approval',(select to_jsonb(a) from assets.approvals a where a.proposal_id=q.id)) order by q.id),'[]') into items
  from(select * from assets.proposals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id
   and(p_after is null or id>p_after) order by id limit 51) q;end if;
 select to_jsonb(p)||jsonb_build_object('approval',(select to_jsonb(a) from assets.approvals a where a.proposal_id=p.id)) into prop
  from assets.proposals p join assets.register r on r.current_proposal_id=p.id where r.id=p_asset_id;
 select to_jsonb(s)||jsonb_build_object('cost',s.cost::text,'opening_accumulated',s.opening_accumulated::text)
  into opening from assets.opening_sources s where s.asset_id=p_asset_id;
 summary:=assets.summary(p_asset_id);
 labels:=jsonb_build_object(
  'cost_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(summary->>'cost_account_id')::uuid),
  'accumulated_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(summary->>'accumulated_account_id')::uuid),
  'impairment_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(summary->>'impairment_account_id')::uuid),
  'location_id',assets.label(p_tenant_id,p_legal_entity_id,'location',(summary->>'location_id')::uuid),
  'custodian_id',assets.label(p_tenant_id,p_legal_entity_id,'custodian',(summary->>'custodian_id')::uuid),
  'branch_id',assets.label(p_tenant_id,p_legal_entity_id,'branch',(summary->>'branch_id')::uuid),
  'expense_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->'book'->>'expense_account_id')::uuid),
  'offset_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'offset_account_id')::uuid),
  'loss_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'loss_account_id')::uuid),
  'surplus_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'surplus_account_id')::uuid),
  'proceeds_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'proceeds_account_id')::uuid),
  'gain_account_id',assets.label(p_tenant_id,p_legal_entity_id,'account',(prop->'data'->>'gain_account_id')::uuid),
  'destination_branch_id',assets.label(p_tenant_id,p_legal_entity_id,'branch',(prop->'data'->>'branch_id')::uuid),
  'destination_location_id',assets.label(p_tenant_id,p_legal_entity_id,'location',(prop->'data'->>'location_id')::uuid),
  'destination_custodian_id',assets.label(p_tenant_id,p_legal_entity_id,'custodian',(prop->'data'->>'custodian_id')::uuid));
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'asset',summary,
  'kind',p_kind,'proposal',prop,'opening',opening,'labels',labels,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.assets_schedule(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_asset_id uuid,p_book_id uuid,p_after integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;basis jsonb;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if p_after is null or p_after not between 0 and 1200 then raise exception using errcode='22023',message='ASSET_PAGE_INVALID';end if;
 if not exists(select 1 from assets.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_asset_id) then
  raise exception using errcode='P0002',message='ASSET_NOT_FOUND';end if;
 select b.basis into basis from assets.books b where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and asset_id=p_asset_id and id=p_book_id;
 if basis is null then raise exception using errcode='P0002',message='ASSET_BOOK_NOT_FOUND';end if;
 select coalesce(jsonb_agg(q.facts order by q.period_index),'[]') into items from(select * from assets.schedules where book_id=p_book_id
  and period_index>p_after order by period_index limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'asset_id',p_asset_id,'book_id',p_book_id,
  'basis',basis,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'period_index' end);
end $$;
create function api.assets_pickers(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;today date;begin
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if p_kind='locations' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.name) order by q.id),'[]') into items from(select * from assets.locations
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind='custodians' then
  select (now() at time zone timezone)::date into today from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.display_name) order by q.id),'[]') into items from(select * from people.employees e
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and(p_after is null or id>p_after) and exists(select 1 from people.employment_assignments a
    where a.employee_id=e.id and a.tenant_id=e.tenant_id and a.legal_entity_id=e.legal_entity_id and a.branch_id=p_branch_id
    and a.start_date<=today and(a.end_date_exclusive is null or a.end_date_exclusive>today)
    and exists(select 1 from people.employment_spells s where s.id=a.spell_id and s.tenant_id=a.tenant_id and s.legal_entity_id=a.legal_entity_id
     and s.employee_id=a.employee_id and s.start_date<=today and(s.end_date_exclusive is null or s.end_date_exclusive>today))) order by id limit 51) q;
 elsif p_kind in('asset','expense','equity','revenue') then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.name,'kind',q.account_type,'currency_code',q.currency_code,'version',q.version) order by q.id),'[]') into items
   from(select * from finance.accounts a where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and is_posting and account_type=p_kind
    and(currency_code is null or currency_code=(select e.currency_code from core.legal_entities e where e.tenant_id=p_tenant_id and e.id=p_legal_entity_id))
    and(p_after is null or id>p_after) and not exists(select 1 from finance.posting_mappings m where m.tenant_id=a.tenant_id and m.legal_entity_id=a.legal_entity_id
     and m.account_id=a.id and m.purpose in('receivable_control','payable_control')) order by id limit 51) q;
 else raise exception using errcode='22023',message='ASSET_PICKER_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.assets_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare r core.command_receipts%rowtype;cap text;begin
 cap:=case p_action when 'location' then 'assets.configure' when 'opening' then 'assets.prepare' when 'propose' then 'assets.prepare'
  when 'cancel' then 'assets.prepare' when 'approve' then 'assets.approve' when 'post' then 'assets.post'
  when 'depreciate' then 'assets.depreciate' when 'reverse' then 'assets.reverse' end;
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and actor_id=auth.uid() and idempotency_key=p_idempotency_key and command_name='assets.'||p_action;
 if r.source_context->>'transfer_branch_id' is not null then
  perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.transfer',true);
  perform assets.require_access(p_tenant_id,p_legal_entity_id,(r.source_context->>'transfer_branch_id')::uuid,'assets.transfer',true);
 end if;
 return case when r.id is null then null else jsonb_build_object('command_id',r.command_id,'idempotency_key',r.idempotency_key,
  'request_hash',r.request_hash,'response',r.response) end;
end $$;
revoke all on all functions in schema assets from public,anon,authenticated;
revoke all on function api.assets_authorize(uuid,uuid,uuid,text),api.assets_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.assets_register(uuid,uuid,uuid,uuid),api.assets_detail(uuid,uuid,uuid,uuid,text,uuid),api.assets_schedule(uuid,uuid,uuid,uuid,uuid,integer),
 api.assets_pickers(uuid,uuid,uuid,text,uuid),api.assets_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.assets_authorize(uuid,uuid,uuid,text),api.assets_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.assets_register(uuid,uuid,uuid,uuid),api.assets_detail(uuid,uuid,uuid,uuid,text,uuid),api.assets_schedule(uuid,uuid,uuid,uuid,uuid,integer),
 api.assets_pickers(uuid,uuid,uuid,text,uuid),api.assets_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;

-- UNAPPLIED additive Service + Assets operational association. No capitalization.
create table service.asset_equipment_links(
 equipment_id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 asset_id uuid not null,asset_version bigint not null check(asset_version between 1 and 9007199254740991),
 source_digest text not null check(source_digest ~ '^[0-9a-f]{64}$'),source_basis jsonb not null,
 reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,asset_id),
 foreign key(tenant_id,legal_entity_id,equipment_id) references service.equipment(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,asset_id) references assets.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
alter table service.asset_equipment_links enable row level security;
alter table service.asset_equipment_links force row level security;
revoke all on service.asset_equipment_links from public,anon,authenticated;
create trigger service_asset_link_immutable before update or delete on service.asset_equipment_links
 for each row execute function service.immutable();
alter table service.tickets alter column customer_id drop not null;

create function service.asset_source(t uuid,e uuid,b uuid,p_asset uuid,p_lock boolean default false,p_eligible boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a assets.register%rowtype;basis jsonb;begin
 perform service.require_access(t,e,b,'service.view');perform assets.require_access(t,e,b,'assets.view');
 if p_lock then select * into a from assets.register where tenant_id=t and legal_entity_id=e and id=p_asset for update;
 else select * into a from assets.register where tenant_id=t and legal_entity_id=e and id=p_asset;end if;
 if a.id is null or p_eligible and(a.status<>'active' or a.branch_id<>b) then
  raise exception using errcode='55000',message='SERVICE_ASSET_NOT_ELIGIBLE';end if;
 basis:=jsonb_build_object('id',a.id,'tenant_id',t,'legal_entity_id',e,'branch_id',a.branch_id,
  'code',a.code,'name',a.name,'ownership',a.ownership,'in_service',a.in_service,'location_id',a.location_id,
  'location_name',(select name from assets.locations where id=a.location_id),'custodian_id',a.custodian_id,
  'custodian_name',(select display_name from people.employees where tenant_id=t and legal_entity_id=e and id=a.custodian_id),
  'status',a.status,'version',a.version);
 return basis||jsonb_build_object('digest',encode(extensions.digest(basis::text,'sha256'),'hex'));
end $$;
create function service.asset_equipment_for(p_kind text,p_id uuid) returns uuid language plpgsql stable security definer set search_path='' as $$
declare eq uuid;begin
 case p_kind
 when 'equipment' then eq:=p_id;
 when 'ticket' then select equipment_id into eq from service.tickets where id=p_id;
 when 'coverage' then select equipment_id into eq from service.coverage_versions where id=p_id;
 when 'order' then select t.equipment_id into eq from service.work_orders w join service.tickets t on t.id=w.ticket_id where w.id=p_id;
 when 'labor' then select t.equipment_id into eq from service.labor l join service.work_orders w on w.id=l.order_id join service.tickets t on t.id=w.ticket_id where l.id=p_id;
 when 'plan' then select equipment_id into eq from service.maintenance_plans where id=p_id;
 when 'reading' then select equipment_id into eq from service.meter_readings where id=p_id;
 when 'occurrence' then select p.equipment_id into eq from service.maintenance_occurrences o join service.maintenance_plans p on p.id=o.plan_id where o.id=p_id;
 else eq:=null;end case;
 return eq;
end $$;
create function service.asset_equipment_guard(t uuid,e uuid,b uuid,p_equipment uuid,p_lock boolean default false,p_eligible boolean default true)
returns void language plpgsql security definer set search_path='' as $$
declare l service.asset_equipment_links%rowtype;q service.equipment%rowtype;begin
 select * into q from service.equipment where tenant_id=t and legal_entity_id=e and branch_id=b and id=p_equipment;
 if q.id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
 if q.kind='asset' then
  select * into l from service.asset_equipment_links where tenant_id=t and legal_entity_id=e and branch_id=b and equipment_id=q.id and asset_id=q.provider_id;
  if l.equipment_id is null or q.customer_id is not null then raise exception using errcode='55000',message='SERVICE_ASSET_LINK_REQUIRED';end if;
  perform service.asset_source(t,e,b,l.asset_id,p_lock,p_eligible);
 end if;
end $$;

create function api.service_asset_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability);
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 return jsonb_build_object('actor_id',auth.uid(),'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'capability',p_capability,'authorized',true);
end $$;
create function api.service_asset_sources(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare items jsonb;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.configure');
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select coalesce(jsonb_agg(service.asset_source(p_tenant_id,p_legal_entity_id,p_branch_id,q.id) order by q.id),'[]') into items
 from(select a.id from assets.register a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.status='active'
  and(p_after is null or a.id>p_after) and not exists(select 1 from service.asset_equipment_links l where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.asset_id=a.id)
  order by a.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.service_asset_equipment_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare id uuid;source jsonb;hash text;replay jsonb;reason text;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.configure');
 perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192
  or p_payload->>'action' is distinct from 'equipment' or p_payload->>'kind' is distinct from 'asset' or p_payload->>'customer_id' is not null
  or p_expected_version is distinct from 0 or p_command_id is null or p_idempotency_key is null or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes'
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'provider_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(array['action','id','reason','code','name','identity','kind','customer_id','provider_id','provider_version','provider_digest'])) then
  raise exception using errcode='22023',message='SERVICE_ASSET_COMMAND_INVALID';end if;
 id:=(p_payload->>'id')::uuid;reason:=service.text(p_payload->'reason',1000);
 perform service.text(p_payload->'name',160);perform service.text(p_payload->'identity',160);
 if coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or jsonb_typeof(p_payload->'provider_version') is distinct from 'number'
  or coalesce(p_payload->>'provider_digest','') !~ '^[0-9a-f]{64}$' then raise exception using errcode='22023',message='SERVICE_ASSET_COMMAND_INVALID';end if;
 hash:=core.wave3_request_hash('service.asset_equipment',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 -- Fresh authorities above precede actor replay. Historical exact replay remains an original receipt.
 replay:=core.wave3_replay(p_tenant_id,'service.asset_equipment',p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 source:=service.asset_source(p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'provider_id')::uuid,true);
 if source->'version'<>p_payload->'provider_version' or source->>'digest'<>p_payload->>'provider_digest' then raise exception using errcode='40001',message='SERVICE_ASSET_SOURCE_CHANGED';end if;
 insert into service.equipment(id,tenant_id,legal_entity_id,branch_id,code,name,identity,kind,customer_id,provider_id,created_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',p_payload->>'name',p_payload->>'identity','asset',null,(p_payload->>'provider_id')::uuid,auth.uid());
 insert into service.asset_equipment_links(equipment_id,tenant_id,legal_entity_id,branch_id,asset_id,asset_version,source_digest,source_basis,reason,created_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(source->>'id')::uuid,(source->>'version')::bigint,source->>'digest',source,reason,auth.uid());
 insert into service.events(tenant_id,legal_entity_id,branch_id,aggregate_id,kind,version,action,reason,facts,actor_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,id,'equipment',1,'asset_equipment',reason,service.snapshot('equipment',id),auth.uid());
 return core.wave3_finish_command(p_tenant_id,'service.asset_equipment',p_command_id,'service.equipment',id,p_idempotency_key,hash,null,
  jsonb_build_object('id',id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind','equipment','version',1,'status','active'),p_legal_entity_id,p_branch_id);
end $$;
create function api.service_asset_link(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_equipment_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare l service.asset_equipment_links%rowtype;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select * into l from service.asset_equipment_links where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and equipment_id=p_equipment_id;
 if l.equipment_id is null then raise exception using errcode='P0002',message='SERVICE_NOT_FOUND';end if;
 return to_jsonb(l);
end $$;
create function api.service_asset_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.configure');perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
 select response into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and actor_id=auth.uid() and command_name='service.asset_equipment' and idempotency_key=p_idempotency_key;
 if r is not null and(r->'entity'->>'legal_entity_id'<>p_legal_entity_id::text or r->'entity'->>'branch_id'<>p_branch_id::text) then return null;end if;return r;
end $$;

-- Preserve the reviewed customer implementation while governing internal sources.
alter function service.ticket_create(uuid,uuid,uuid,uuid,jsonb) rename to ticket_create_customer;
create function service.ticket_create(t uuid,e uuid,b uuid,id uuid,p jsonb) returns void language plpgsql security definer set search_path='' as $$
declare eq service.equipment%rowtype;policy service.sla_policies%rowtype;at timestamptz;begin
 select * into eq from service.equipment where tenant_id=t and legal_entity_id=e and branch_id=b and equipment.id=(p->>'equipment_id')::uuid and status='active';
 if eq.kind is distinct from 'asset' then perform service.ticket_create_customer(t,e,b,id,p);return;end if;
 perform service.asset_equipment_guard(t,e,b,eq.id,true);
 at:=service.utc(p->'observed_utc');select * into policy from service.sla_policies where tenant_id=t and legal_entity_id=e and branch_id=b and sla_policies.id=(p->>'policy_id')::uuid;
 if p->>'customer_id' is not null or p->>'contact_id' is not null or policy.id is null
  or coalesce(p->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or coalesce(p->>'priority','') not in('low','normal','high','urgent') or at>clock_timestamp()+interval '5 minutes'
  or p->>'coverage_id' is not null and not exists(select 1 from service.coverage_versions c where c.tenant_id=t and c.legal_entity_id=e and c.branch_id=b and c.id=(p->>'coverage_id')::uuid and c.equipment_id=eq.id
   and daterange(c.start_date,c.end_date_exclusive,'[)') @> (at at time zone(select timezone from core.legal_entities where tenant_id=t and legal_entities.id=e))::date) then
  raise exception using errcode='22023',message='SERVICE_INTERNAL_TICKET_INVALID';end if;
 insert into service.tickets(id,tenant_id,legal_entity_id,branch_id,code,name,classification,customer_id,contact_id,equipment_id,coverage_id,policy_id,priority,owner_id,started_utc,clock_start_utc,response_due,resolution_due,created_by)
 values(id,t,e,b,p->>'code',service.text(p->'name',160),service.text(p->'classification',80),null,null,eq.id,(p->>'coverage_id')::uuid,policy.id,p->>'priority',(p->>'owner_id')::uuid,
  at,at,service.due(policy.windows,at,policy.response_seconds),service.due(policy.windows,at,policy.resolution_seconds),auth.uid());
end $$;
alter function api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) rename to service_command_customer_base;
create function api.service_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$declare act text:=p_payload->>'action';eq uuid;original jsonb;begin
 if service.capability(act) is null or coalesce(jsonb_typeof(p_payload),'null')<>'object' or octet_length(p_payload::text)>65536 or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(service.fields(act))) then raise exception using errcode='22023',message='SERVICE_COMMAND_INVALID';end if;
 perform service.text(p_payload->'reason',1000);
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,service.capability(act));
 eq:=case when act in('ticket','coverage','plan','reading') then(p_payload->>'equipment_id')::uuid
  when act='order' then service.asset_equipment_for('ticket',(p_payload->>'ticket_id')::uuid)
  when act='labor' then service.asset_equipment_for('order',(p_payload->>'order_id')::uuid)
  else null end;
 -- The ordinary action-to-kind helper is explicit; no provider identity comes from client labels.
 if eq is null then eq:=service.asset_equipment_for(case when act in('dispatch','accept','start','complete','close','cancel_order') then 'order'
  when act in('approve_labor','cancel_labor') then 'labor' when act='generate' then 'plan' when act='defer' then 'occurrence'
  when act in('pause','resume','evaluate','reprioritize','cancel_ticket') then 'ticket' else null end,(p_payload->>'id')::uuid);end if;
 if exists(select 1 from service.equipment where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=eq and kind='asset') then
  perform assets.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'assets.view');
  original:=core.wave3_replay(p_tenant_id,'service.'||act,p_command_id,p_idempotency_key,
   core.wave3_request_hash('service.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version));
  if original is not null then return original;end if;
  perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
  perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
  perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
  perform service.asset_equipment_guard(p_tenant_id,p_legal_entity_id,p_branch_id,eq,true,act in('ticket','coverage','plan','reading','generate','order','dispatch','accept','start','labor'));
  if act='labor' and coalesce(p_payload->>'billing_kind','nonbillable')<>'nonbillable' then raise exception using errcode='55000',message='SERVICE_INTERNAL_NONBILLABLE';end if;
  if act='complete' and(p_payload->>'customer_confirmed' is distinct from 'false' or nullif(btrim(p_payload->>'exception_reason'),'') is null) then
   raise exception using errcode='22023',message='SERVICE_INTERNAL_CONFIRMATION_REQUIRED';end if;
 end if;
 return api.service_command_customer_base(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_issued_at,p_payload,p_expected_version);
end $$;
create or replace function api.service_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_parent uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare items jsonb;tablename text:=service.table_for(p_kind);parent_column text;cost boolean;begin
 perform service.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'service.view');
 if tablename is null then raise exception using errcode='22023',message='SERVICE_KIND_INVALID';end if;
 cost:=core.has_permission(p_tenant_id,'service.cost.view',p_legal_entity_id,p_branch_id);
 parent_column:=case p_kind when 'coverage' then 'equipment_id' when 'order' then 'ticket_id' when 'labor' then 'order_id' when 'reading' then 'equipment_id' when 'occurrence' then 'plan_id' end;
 if p_parent is not null and parent_column is null then raise exception using errcode='22023',message='SERVICE_PARENT_INVALID';end if;
 execute format('select coalesce(jsonb_agg(service.public_snapshot($1,q.id,$6) order by q.id),''[]''::jsonb) from(select id from service.%I where tenant_id=$2 and legal_entity_id=$3 and branch_id=$4 and($5 is null or id>$5) and service.asset_read_allowed($2,$3,$4,$1,id)%s order by id limit 51) q',
  tablename,case when p_parent is null then '' else format(' and %I=$7',parent_column) end)
 into items using p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,p_after,cost,p_parent;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;

-- Scope/asset authority is checked before all historical internal projections.
create function service.asset_read_allowed(t uuid,e uuid,b uuid,p_kind text,p_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare eq uuid:=service.asset_equipment_for(p_kind,p_id);begin
 if not exists(select 1 from service.equipment where id=eq and kind='asset') then return true;end if;
 return core.has_permission(t,'assets.view',e,b) and exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='module.assets' and p.enabled and
   ((s.status='trialing' and s.trial_ends_at>now()) or(s.status='active' and(s.current_period_ends_at is null or s.current_period_ends_at>now()))));
end $$;
-- Guard snapshots centrally: customer rows remain readable; internal rows require both authorities.
alter function service.public_snapshot(text,uuid,boolean) rename to public_snapshot_customer_base;
create function service.public_snapshot(kind text,id uuid,cost boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb;begin
 r:=service.public_snapshot_customer_base(kind,id,cost);
 if r is not null and not service.asset_read_allowed((r->>'tenant_id')::uuid,(r->>'legal_entity_id')::uuid,(r->>'branch_id')::uuid,kind,id) then
  raise exception using errcode='42501',message='SERVICE_ASSET_ACCESS_REQUIRED';end if;return r;
end $$;
alter function api.service_own_receipt(uuid,uuid,uuid,uuid,text) rename to service_own_receipt_customer_base;
create function api.service_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 r:=api.service_own_receipt_customer_base(p_tenant_id,p_legal_entity_id,p_branch_id,p_idempotency_key,p_action);
 if r is not null and not service.asset_read_allowed(p_tenant_id,p_legal_entity_id,p_branch_id,r#>>'{entity,kind}',(r#>>'{entity,id}')::uuid) then
  raise exception using errcode='42501',message='SERVICE_ASSET_ACCESS_REQUIRED';end if;return r;
end $$;
create function service.internal_ticket_invariant() returns trigger language plpgsql set search_path='' as $$declare k text;begin
 select kind into k from service.equipment where tenant_id=new.tenant_id and legal_entity_id=new.legal_entity_id and id=new.equipment_id;
 if(k='asset' and(new.customer_id is not null or new.contact_id is not null)) or(k='customer' and new.customer_id is null) then
  raise exception using errcode='22023',message='SERVICE_INTERNAL_TICKET_INVALID';end if;return new;
end $$;
create trigger service_internal_ticket_invariant before insert or update on service.tickets for each row execute function service.internal_ticket_invariant();
create function service.internal_labor_invariant() returns trigger language plpgsql set search_path='' as $$begin
 if new.billing_kind<>'nonbillable' and exists(select 1 from service.work_orders w join service.tickets t on t.id=w.ticket_id
  where w.id=new.order_id and t.customer_id is null) then raise exception using errcode='55000',message='SERVICE_INTERNAL_NONBILLABLE';end if;return new;
end $$;
create trigger service_internal_labor_invariant before insert or update on service.labor for each row execute function service.internal_labor_invariant();
alter function service.billing_source(uuid,uuid,uuid,uuid) rename to billing_source_customer_base;
create function service.billing_source(t uuid,e uuid,b uuid,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from service.labor l join service.work_orders w on w.id=l.order_id join service.tickets q on q.id=w.ticket_id
  where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.id=p_id and q.customer_id is null) then raise exception using errcode='55000',message='SERVICE_INTERNAL_NONBILLABLE';end if;
 return service.billing_source_customer_base(t,e,b,p_id);
end $$;
revoke all on all functions in schema service from public,anon,authenticated;
revoke all on function api.service_command_customer_base(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.service_own_receipt_customer_base(uuid,uuid,uuid,uuid,text),
 api.service_asset_authorize(uuid,uuid,uuid,text),api.service_asset_sources(uuid,uuid,uuid,uuid),api.service_asset_equipment_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_asset_link(uuid,uuid,uuid,uuid),api.service_asset_own_receipt(uuid,uuid,uuid,uuid),
 api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.service_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.service_asset_authorize(uuid,uuid,uuid,text),api.service_asset_sources(uuid,uuid,uuid,uuid),api.service_asset_equipment_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.service_asset_link(uuid,uuid,uuid,uuid),api.service_asset_own_receipt(uuid,uuid,uuid,uuid),
 api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.service_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;

create temporary table service_assertions(message text);create temporary table asset_assertions(message text);create temporary table link_assertions(message text);
grant insert on service_assertions,asset_assertions,link_assertions to authenticated;
-- Included only inside a caller-owned BEGIN ... ROLLBACK. Never an owner bootstrap.
create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('wave4-integrated-rollback-20260926:'||p)::uuid$$;
create function pg_temp.wdate() returns date language sql stable as
  $$select ((now()-interval '1 day') at time zone 'Asia/Colombo')::date$$;
create function pg_temp.wactor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(p),'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(p)::text,true);
end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@wave4.rollback.jentra.test','',now(),now(),now()
from unnest(array['creator','reviewer','reader','branch-manager','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values
  (pg_temp.wid('tenant'),'Wave 4 Rollback','w4-integrated-rollback',pg_temp.wid('creator')),
  (pg_temp.wid('other-tenant'),'Other Rollback','w4-other-integrated-rollback',pg_temp.wid('outsider'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by) values
  (pg_temp.wid('entity'),pg_temp.wid('tenant'),'Synthetic Operations','W4OPS','LKR','Asia/Colombo',2,pg_temp.wid('creator')),
  (pg_temp.wid('entity2'),pg_temp.wid('tenant'),'Other Operations','W4OTHER','LKR','Asia/Colombo',2,pg_temp.wid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
  (pg_temp.wid('branch'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Head Office','HQ',pg_temp.wid('creator')),
  (pg_temp.wid('branch2'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Second Branch','B2',pg_temp.wid('creator')),
  (pg_temp.wid('entity2-branch'),pg_temp.wid('tenant'),pg_temp.wid('entity2'),'Other HQ','HQ',pg_temp.wid('creator'));
insert into billing.plans(code,name) values('w4_integrated_rollback','Wave 4 rollback');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.wid('tenant'),'w4_integrated_rollback','trialing',10,now()+interval '30 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.wid(x||'.membership'),pg_temp.wid('tenant'),pg_temp.wid(x),'active'
from unnest(array['creator','reviewer','reader','branch-manager']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.wid(x||'.role'),pg_temp.wid('tenant'),x,x,true
from unnest(array['creator','reviewer','reader','branch-manager']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code
from unnest(array['creator','reviewer','branch-manager']) x cross join core.permissions p
where p.module='people';
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('reader.role'),p.code
from unnest(array['people.view','people.employees.view','people.employees.history.view',
  'people.calendars.view','people.organization.view']) p(code)
join core.permissions c on c.code=p.code;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.membership'),pg_temp.wid(x||'.role'),pg_temp.wid('entity'),
  case when x in ('creator','reviewer') then null else pg_temp.wid('branch') end,pg_temp.wid('creator')
from unnest(array['creator','reviewer','reader','branch-manager']) x;
create function pg_temp.wemployee(p text) returns jsonb language sql as $$
  select api.people_employee_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
    pg_temp.wid(p||'.create'),pg_temp.wid(p||'.create'),now(),jsonb_build_object('action','create',
      'id',pg_temp.wid(p),'code',upper(p),'display_name','Synthetic '||p,'work_email',null,
      'start_date',pg_temp.wdate()-10,'job_title','Synthetic role','employment_type','permanent'),0)
$$;
select pg_temp.wactor('creator');
select pg_temp.wemployee('employee');
select pg_temp.wemployee('manager');
select pg_temp.wemployee('third');
insert into people.work_calendars(id,tenant_id,legal_entity_id,code,name,created_by,updated_by)
values(pg_temp.wid('calendar'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4CAL','Synthetic Calendar',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,start_date,end_date_exclusive,
  timezone,weekly_intervals,date_overrides,published_by)
values(pg_temp.wid('calendar-version'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('calendar'),
  pg_temp.wdate()-10,pg_temp.wdate()+400,'Asia/Colombo',
  jsonb_build_array(jsonb_build_object(
    'day_of_week',extract(isodow from pg_temp.wdate())::integer,
    'start_minute',540,'end_minute',1020,'end_day_offset',0)),
  '[]',pg_temp.wid('creator'));

create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.service',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer','branch-manager']) x cross join core.permissions p where p.module='service';
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reader.role'),'service.view');
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,status,created_by,updated_by)
values(pg_temp.wid('customer'),pg_temp.wid('tenant'),'W4SERVICE','Synthetic Service Customer','Synthetic Customer','customer','active',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into people.departments(id,tenant_id,legal_entity_id,code) values(pg_temp.wid('department'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4OPS');
insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,start_date,end_date_exclusive,reason,recorded_by)
values(pg_temp.wid('department-r1'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('department'),'Synthetic Operations',pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic service fixture',pg_temp.wid('creator'));
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('org-service'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),s.id,pg_temp.wid('department'),pg_temp.wid('calendar-version'),'Synthetic engineer',pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic service fixture',pg_temp.wid('creator')
from people.employment_spells s where s.employee_id=pg_temp.wid('employee');
create function pg_temp.sutc(hour integer) returns text language sql as $$select to_char(pg_temp.wdate()::timestamp+hour*interval '1 hour'-interval '5 hours 30 minutes','YYYY-MM-DD"T"HH24:MI:SS"Z"')$$;
create function pg_temp.sc(action text,id text,data jsonb default '{}',version bigint default 0,k text default null) returns jsonb language sql as $$
 select api.service_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(coalesce(k,id||'.'||action)),pg_temp.wid(coalesce(k,id||'.'||action)),now(),
 jsonb_build_object('action',action,'id',pg_temp.wid(id),'reason','Synthetic service evidence')||data,version) $$;
create function pg_temp.spolicy(seconds bigint default 3600) returns jsonb language sql as $$select jsonb_build_object('name','Synthetic SLA','calendar_version_id',pg_temp.wid('calendar-version'),
 'start_date',pg_temp.wdate()-1,'end_date_exclusive',pg_temp.wdate()+29,'response_seconds',seconds,'resolution_seconds',10800,'independent_closure',true,'offsets','[]'::jsonb)$$;
create function pg_temp.sticket(code text default 'W4-SERVICE') returns jsonb language sql as $$select jsonb_build_object('code',code,'name','Synthetic fault','classification','repair',
 'customer_id',pg_temp.wid('customer'),'contact_id',null,'equipment_id',pg_temp.wid('equipment'),'coverage_id',null,'policy_id',pg_temp.wid('policy'),'priority','normal','owner_id',null,'observed_utc',pg_temp.sutc(9))$$;
create temporary table service_responses(name text primary key,body jsonb);
create temporary table service_samples(name text primary key,body jsonb);
grant select,insert on service_responses,service_samples to authenticated;
insert into service_assertions select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='service' and c.relkind='r'),'AC-401 all service tables force RLS');
insert into service_assertions select ok(not has_table_privilege('authenticated','service.labor','SELECT'),'AC-401 labor API only');
insert into service_assertions select ok(not has_function_privilege('authenticated','service.consume_billing_source(uuid,uuid,uuid,uuid,bigint,text,uuid)','EXECUTE'),'AC-411 consumption owner only');
insert into service_assertions select ok(not has_function_privilege('anon','api.service_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),'AC-401 anonymous writes denied');
insert into service_assertions select is(service.round_ratio(5000,1,2)::numeric(20,6)::text,'0.000000','AC-414 half-even exact tie');
insert into service_assertions select is(service.round_ratio(15000,1,2)::numeric(20,6)::text,'0.020000','AC-414 half-even odd tie');
select pg_temp.wactor('creator');set local role authenticated;
insert into service_responses values('equipment',pg_temp.sc('equipment','equipment',jsonb_build_object('code','EQ-W4','name','Synthetic Pump','identity','W4-PUMP-0001','kind','customer','customer_id',pg_temp.wid('customer'),'provider_id',null)));
insert into service_assertions select is((select body->'entity'->>'version' from service_responses where name='equipment'),'1','AC-415 equipment created');
insert into service_assertions select is(pg_temp.sc('equipment','equipment',jsonb_build_object('code','EQ-W4','name','Synthetic Pump','identity','W4-PUMP-0001','kind','customer','customer_id',pg_temp.wid('customer'),'provider_id',null)),(select body from service_responses where name='equipment'),'EC-402 exact replay');
insert into service_assertions select throws_ok($$select pg_temp.sc('equipment','equipment',jsonb_build_object('code','CHANGED','name','Synthetic Pump','identity','W4-PUMP-0001','kind','customer','customer_id',pg_temp.wid('customer'),'provider_id',null))$$,'22023','IDEMPOTENCY_MISMATCH','EC-402 changed-body replay rejected');
insert into service_responses values('policy',pg_temp.sc('policy','policy',pg_temp.spolicy()));
insert into service_responses values('policy2',pg_temp.sc('policy','policy2',pg_temp.spolicy(1800)));
insert into service_responses values('coverage',pg_temp.sc('coverage','coverage',jsonb_build_object('equipment_id',pg_temp.wid('equipment'),'kind','warranty','name','Synthetic warranty','start_date',pg_temp.wdate()-1,'end_date_exclusive',pg_temp.wdate()+30,'evidence_reference','W4-WARRANTY-001')));
insert into service_responses values('ticket',pg_temp.sc('ticket','ticket',pg_temp.sticket()));
insert into service_samples values('ticket-initial',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'ticket',pg_temp.wid('ticket')));
insert into service_assertions select ok((select (body->'record'->>'response_due')::timestamptz from service_samples where name='ticket-initial')=pg_temp.sutc(10)::timestamptz,'AC-413 calendar due instant exact');
insert into service_responses values('pause',pg_temp.sc('pause','ticket',jsonb_build_object('observed_utc',pg_temp.sutc(10)),1));
insert into service_responses values('resume',pg_temp.sc('resume','ticket',jsonb_build_object('observed_utc',pg_temp.sutc(11)),2));
insert into service_responses values('reprioritize',pg_temp.sc('reprioritize','ticket',jsonb_build_object('observed_utc',pg_temp.sutc(12),'policy_id',pg_temp.wid('policy2'),'priority','urgent'),3));
insert into service_samples values('ticket-reprioritized',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'ticket',pg_temp.wid('ticket')));
insert into service_assertions select is((select body->'record'->>'version' from service_samples where name='ticket-reprioritized'),'4','AC-413 pause resume repriority keep versions');
insert into service_assertions select is((select body->'record'->>'consumed_seconds' from service_samples where name='ticket-reprioritized'),'7200','AC-413 paused hour not consumed');
insert into service_assertions select is((select body->'record'->>'response_breached' from service_samples where name='ticket-reprioritized'),'true','AC-413 earlier breach retained');
insert into service_assertions select throws_ok($$select pg_temp.sc('evaluate','ticket',jsonb_build_object('observed_utc',pg_temp.sutc(12)),1)$$,'40001','SERVICE_VERSION_CONFLICT','EC-415 stale SLA rejected');
insert into service_responses values('order',pg_temp.sc('order','order',jsonb_build_object('ticket_id',pg_temp.wid('ticket'))));
insert into service_responses values('dispatch',pg_temp.sc('dispatch','order',jsonb_build_object('employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),'start_utc',pg_temp.sutc(12),'end_utc',pg_temp.sutc(14),'booking_id',pg_temp.wid('booking')),1));
insert into service_responses values('accept',pg_temp.sc('accept','order',jsonb_build_object('observed_utc',pg_temp.sutc(12)),2));
insert into service_responses values('start',pg_temp.sc('start','order',jsonb_build_object('observed_utc',pg_temp.sutc(12)),3));
insert into service_responses values('labor',pg_temp.sc('labor','labor',jsonb_build_object('order_id',pg_temp.wid('order'),'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_utc',pg_temp.sutc(12),'end_utc',pg_temp.sutc(13),'breaks','[]'::jsonb,'claim_id',null,'hourly_cost','123.455000','currency_code','LKR','precision',2,'billing_kind','billable','hourly_billing','250.005000','billing_reference','Synthetic contract rate')));
insert into service_assertions select throws_ok($$select pg_temp.sc('approve_labor','labor','{}',1)$$,'55000','SERVICE_INDEPENDENT_APPROVAL_REQUIRED','AC-414 preparer cannot approve labor');
select pg_temp.wactor('reviewer');
insert into service_responses values('approved',pg_temp.sc('approve_labor','labor','{}',1));
insert into service_samples values('labor-approved',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'labor',pg_temp.wid('labor')));
insert into service_assertions select is((select body->'record'->>'amount' from service_samples where name='labor-approved'),'123.460000','AC-414 exact labor cost');
select pg_temp.wactor('creator');
insert into service_responses values('complete',pg_temp.sc('complete','order',jsonb_build_object('observed_utc',pg_temp.sutc(14),'resolution','Synthetic repair complete','customer_confirmed',false,'exception_reason','Synthetic customer unavailable'),4));
insert into service_samples values('order-completed',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'order',pg_temp.wid('order')));
insert into service_assertions select throws_ok($$select pg_temp.sc('close','order','{}',5)$$,'55000','SERVICE_INDEPENDENT_CLOSURE_REQUIRED','AC-414 independent closure and unbilled sources required');
insert into service_assertions select throws_ok($$select pg_temp.sc('parts_issue','order','{}',5)$$,'55000','SERVICE_PARTS_PROVIDER_UNAVAILABLE','EC-416 no fabricated service parts');
insert into service_responses values('plan',pg_temp.sc('plan','plan',jsonb_build_object('equipment_id',pg_temp.wid('equipment'),'policy_id',pg_temp.wid('policy'),'name','Synthetic meter maintenance','basis','meter','interval_units',100,'next_date',null,'next_meter',100)));
insert into service_responses values('reading0',pg_temp.sc('reading','reading0',jsonb_build_object('equipment_id',pg_temp.wid('equipment'),'kind','initial','raw_value',90,'rollover_max',null,'observed_utc',pg_temp.sutc(9))));
insert into service_assertions select throws_ok($$select pg_temp.sc('reading','bad-reading',jsonb_build_object('equipment_id',pg_temp.wid('equipment'),'kind','reading','raw_value',80,'rollover_max',null,'observed_utc',pg_temp.sutc(10)))$$,'22023','SERVICE_METER_DECREASE','AC-415 decreases require reset');
insert into service_responses values('reading1',pg_temp.sc('reading','reading1',jsonb_build_object('equipment_id',pg_temp.wid('equipment'),'kind','rollover','raw_value',9,'rollover_max',99,'observed_utc',pg_temp.sutc(10))));
insert into service_responses values('reading2',pg_temp.sc('reading','reading2',jsonb_build_object('equipment_id',pg_temp.wid('equipment'),'kind','reset','raw_value',0,'rollover_max',null,'observed_utc',pg_temp.sutc(11))));
insert into service_samples values('reading-reset',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'reading',pg_temp.wid('reading2')));
insert into service_assertions select is((select body->'record'->>'logical_value' from service_samples where name='reading-reset'),'109','AC-415 rollover reset conserve logical units');
insert into service_responses values('generate',pg_temp.sc('generate','plan',jsonb_build_object('ticket_id',pg_temp.wid('pm-ticket'),'order_id',pg_temp.wid('pm-order'),'occurrence_id',pg_temp.wid('pm-occurrence'),'observed_utc',pg_temp.sutc(12)),1));
insert into service_assertions select is(pg_temp.sc('generate','plan',jsonb_build_object('ticket_id',pg_temp.wid('pm-ticket'),'order_id',pg_temp.wid('pm-order'),'occurrence_id',pg_temp.wid('pm-occurrence'),'observed_utc',pg_temp.sutc(12)),1),(select body from service_responses where name='generate'),'EC-413 generation retry original identity');
insert into service_assertions select throws_ok($$select pg_temp.sc('generate','plan',jsonb_build_object('ticket_id',pg_temp.wid('pm-ticket2'),'order_id',pg_temp.wid('pm-order2'),'occurrence_id',pg_temp.wid('pm-occurrence2'),'observed_utc',pg_temp.sutc(12)),1,'duplicate-generate')$$,'40001','SERVICE_VERSION_CONFLICT','EC-413 stale generation cannot duplicate occurrence');
insert into service_samples values('occurrence',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'occurrence',pg_temp.wid('pm-occurrence')));
select pg_temp.wactor('reader');
insert into service_samples values('labor-redacted',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'labor',pg_temp.wid('labor')));
insert into service_assertions select ok(not((select body->'record' from service_samples where name='labor-redacted')?'amount'),'AC-404 internal service cost separately protected');
insert into service_assertions select ok(not exists(select 1 from jsonb_array_elements((select body->'events' from service_samples where name='labor-redacted')) x where x->'facts'?'amount'),'AC-404 history does not leak cost');
insert into service_assertions select throws_ok($$select pg_temp.sc('evaluate','ticket',jsonb_build_object('observed_utc',pg_temp.sutc(12)),4)$$,'42501','Permission denied or multi-factor authentication required.','AC-401 directory role cannot mutate service');
select pg_temp.wactor('outsider');
insert into service_assertions select throws_ok($$select api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'ticket',pg_temp.wid('ticket'))$$,'42501','Permission denied or multi-factor authentication required.','AC-401 outsider denied');
reset role;select pg_temp.wactor('reviewer');
delete from core.role_permissions where role_id=pg_temp.wid('reviewer.role') and permission_code='service.work';
insert into service_assertions select is(service.payroll_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),(select claim_id from service.labor where id=pg_temp.wid('labor')))->>'paid_seconds','3600','AC-411 one direct payroll claim');
insert into service_assertions select is(service.billing_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('labor'))->>'source_version','2','AC-412 immutable approved billing source');
insert into service_assertions select ok(not exists(select 1 from core.outbox_events where command_id in(select command_id from core.command_receipts where command_name like 'service.%') and payload::text like '%hourly_cost%'),'AC-404 generic outbox excludes internal cost');
insert into service_assertions select is(service.billing_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('labor'))->>'amount','250.000000','AC-412 billing price independent of internal cost');
insert into service_assertions select is(service.payroll_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select claim_id from service.labor where id=pg_temp.wid('labor')),pg_temp.wid('source-revision'),'{}','read')->>'paid_seconds','3600','AC-411 correction read retains original service seconds');
insert into service_assertions select is(service.payroll_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select claim_id from service.labor where id=pg_temp.wid('labor')),pg_temp.wid('source-revision'),jsonb_build_object('expected_source_version',2,'mode','geometry',
 'start_local',pg_temp.wdate()::text||'T12:00:00','end_local',pg_temp.wdate()::text||'T12:30:00','start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb),'validate')->>'paid_seconds','1800','AC-411 revised service seconds exact');
insert into service_assertions select is(service.payroll_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select claim_id from service.labor where id=pg_temp.wid('labor')),pg_temp.wid('source-revision'),jsonb_build_object('expected_source_version',2,'mode','geometry',
 'start_local',pg_temp.wdate()::text||'T12:00:00','end_local',pg_temp.wdate()::text||'T12:30:00','start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb),'validate')->'after'->>'amount','61.730000','AC-411 frozen service cost revised exactly');
insert into service_assertions select is((select version from service.labor where id=pg_temp.wid('labor')),2::bigint,'AC-411 validation does not mutate source');
insert into service_assertions select ok(not core.has_permission(pg_temp.wid('tenant'),'service.work',pg_temp.wid('entity'),pg_temp.wid('branch')),
 'AC-404 independent reviewer inspects and validates without service work');
delete from core.role_permissions where role_id=pg_temp.wid('reviewer.role') and permission_code='service.approve';
insert into service_assertions select throws_ok($q$select service.payroll_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select claim_id from service.labor where id=pg_temp.wid('labor')),pg_temp.wid('source-revision'),'{}','validate')$q$,
 '42501','Permission denied or multi-factor authentication required.','AC-401 source validation requires operational approval');
insert into service_assertions select is(service.payroll_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select claim_id from service.labor where id=pg_temp.wid('labor')),pg_temp.wid('source-revision'),'{}','read')->>'paid_seconds',
 '3600','AC-404 read requires view and cost without work or approval');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reviewer.role'),'service.approve');
insert into service_assertions select ok(not has_function_privilege('authenticated','service.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'AC-401 correction hook owner only');
insert into service_assertions select ok(not has_function_privilege('authenticated','service.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'AC-401 allocation hook owner only');
insert into service_assertions select is((select count(*) from service.events where aggregate_id=pg_temp.wid('ticket') and action in('accept','complete')),2::bigint,'AC-413 indirect ticket clocks retain history');
insert into service_assertions select is((select count(*) from service.events where aggregate_id=pg_temp.wid('pm-order')),1::bigint,'AC-415 generated work order has provenance');
create function pg_temp.service_fail_outbox() returns trigger language plpgsql as $$begin raise exception 'SERVICE_TEST_OUTBOX_FAILURE';end $$;
create trigger service_test_outbox_failure before insert on core.outbox_events for each row execute function pg_temp.service_fail_outbox();
select pg_temp.wactor('creator');set local role authenticated;
insert into service_assertions select throws_ok($$select pg_temp.sc('ticket','atomic-ticket',pg_temp.sticket('ATOMIC-SERVICE'))$$,'P0001','SERVICE_TEST_OUTBOX_FAILURE','EC-415 late outbox failure rolls back service');
reset role;
-- Civil holidays clip overnight working windows at local midnight.
insert into people.work_calendars(id,tenant_id,legal_entity_id,code,name,created_by,updated_by)
values(pg_temp.wid('sla.overnight'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'SLA-OVERNIGHT','Synthetic overnight calendar',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,start_date,end_date_exclusive,timezone,weekly_intervals,date_overrides,published_by)
values(pg_temp.wid('sla.overnight.holiday'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('sla.overnight'),pg_temp.wdate()-10,pg_temp.wdate()+10,'Asia/Colombo',
 jsonb_build_array(jsonb_build_object('day_of_week',extract(isodow from pg_temp.wdate()-1)::integer,'start_minute',1320,'end_minute',120,'end_day_offset',1)),
 jsonb_build_array(jsonb_build_object('date',pg_temp.wdate(),'is_working_day',false,'reason','Synthetic civil holiday')),pg_temp.wid('creator'));
insert into service_assertions select is(service.elapsed(service.windows(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('sla.overnight.holiday'),pg_temp.wdate()-1,pg_temp.wdate()+1,'[]'),
 ((pg_temp.wdate()-1)::timestamp at time zone 'Asia/Colombo'),((pg_temp.wdate()+1)::timestamp at time zone 'Asia/Colombo')),7200::bigint,'overnight holiday excludes incoming civil holiday hours');
insert into people.work_calendar_versions(id,tenant_id,legal_entity_id,calendar_id,start_date,end_date_exclusive,timezone,weekly_intervals,date_overrides,published_by)
values(pg_temp.wid('sla.overnight.working'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('sla.overnight'),pg_temp.wdate()+10,pg_temp.wdate()+20,'Asia/Colombo',
 jsonb_build_array(jsonb_build_object('day_of_week',extract(isodow from pg_temp.wdate()+10)::integer,'start_minute',1320,'end_minute',120,'end_day_offset',1)),
 '[]',pg_temp.wid('creator'));
insert into service_assertions select is(service.elapsed(service.windows(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('sla.overnight.working'),pg_temp.wdate()+11,pg_temp.wdate()+12,'[]'),
 ((pg_temp.wdate()+11)::timestamp at time zone 'Asia/Colombo'),((pg_temp.wdate()+12)::timestamp at time zone 'Asia/Colombo')),7200::bigint,'policy horizon captures incoming overnight work');
insert into service_assertions select throws_ok($q$select service.windows(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('sla.overnight.holiday'),pg_temp.wdate()-1,pg_temp.wdate()+1,
 jsonb_build_array(jsonb_build_object('date',pg_temp.wdate()-1,'start_minute',1320,'start_offset_seconds',19800,'end_offset_seconds',19800),
 jsonb_build_object('date',pg_temp.wdate()-1,'start_minute',1320,'start_offset_seconds',19800,'end_offset_seconds',19800)))$q$,'22023','SERVICE_CALENDAR_OFFSET_INVALID','duplicate ambiguous boundary choices rejected');
drop trigger service_test_outbox_failure on core.outbox_events;
insert into service_assertions select ok(not exists(select 1 from service.tickets where id=pg_temp.wid('atomic-ticket')) and not exists(select 1 from service.events where aggregate_id=pg_temp.wid('atomic-ticket'))
 and not exists(select 1 from core.command_receipts where command_id=pg_temp.wid('atomic-ticket.ticket')),'EC-415 no partial ticket event or receipt');
select pg_temp.wactor('creator','aal1');set local role authenticated;
insert into service_assertions select throws_ok($$select pg_temp.sc('ticket','mfa-ticket',pg_temp.sticket('MFA-SERVICE'))$$,'42501','Permission denied or multi-factor authentication required.','AC-401 privileged service requires MFA');
reset role;select pg_temp.wactor('reviewer');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='service.configure';
select pg_temp.wactor('creator');set local role authenticated;
insert into service_assertions select throws_ok($$select api.service_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('equipment.equipment'),'equipment')$$,'42501','Permission denied or multi-factor authentication required.','EC-402 revocation before receipt lookup');
reset role;

-- Governed synthetic fixed-asset candidate. Included only in BEGIN/ROLLBACK.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;

create temporary table asset_client_samples(label text primary key,body jsonb not null);
create function pg_temp.asset_capture(label text,k text default 'a',b text default 'branch') returns void language plpgsql as $$
declare item jsonb; section text;begin
 foreach section in array array['books','effects','proposals'] loop
  item:=api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid('asset.'||k),section,null);
  insert into asset_client_samples values(label||'.'||section,item);
 end loop;
end $$;
insert into asset_assertions select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='assets' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity),8,
 'all eight asset tables are forced RLS');
insert into asset_assertions select is(assets.round_even(0.005,2),0::numeric,'asset exact even tie');
insert into asset_assertions select is(assets.round_even(0.015,2),0.02::numeric,'asset exact odd tie');
insert into asset_assertions select is(assets.ratio(99999999999999999999::numeric*9007199254740991-1,9007199254740991,6),99999999999999999999::numeric,
 'large rational quotient does not acquire a rounded division increment');
insert into asset_assertions select is((assets.schedule('0.03','0','0','0',5,'straight_line',1,1,2,'2026-01-01')->4->>'depreciation'),
 '0.010000','asset tiny final residue conserves exactly');
insert into asset_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='assets' and c.relkind='r' and has_table_privilege('authenticated',c.oid,'SELECT')),'no direct asset table reads');
insert into asset_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='assets' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'asset helpers denied to authenticated clients');
insert into asset_assertions select throws_ok($q$select assets.schedule('1','0','0','2',3,'straight_line',1,1,2,'2026-01-01')$q$,
 '22023','ASSET_BOOK_INVALID','residual exceeds carrying');
insert into asset_assertions select throws_ok($q$select assets.schedule('1.001','0','0','0',3,'straight_line',1,1,2,'2026-01-01')$q$,
 '22023','ASSET_BOOK_INVALID','unrepresentable currency precision rejected');
insert into asset_assertions select is(assets.schedule('1000','0','0','100',3,'reducing_balance',1,5,2,'2026-01-01')->2->>'depreciation',
 '540.000000','exact declining balance final residue');
insert into asset_assertions select is(assets.schedule('1000','200','300','100',2,'straight_line',1,1,2,'2026-01-01')->1->>'accumulated_closing',
 '600.000000','impairment stays separate from depreciation history');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.assets',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer','branch-manager']) x
 cross join core.permissions p where p.module='assets';
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reader.role'),'assets.view');
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
 select pg_temp.wid('asset.account.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),upper(x),'Synthetic asset '||x,
 case when x in('cost','accum','impair','bank') then 'asset' when x in('expense','loss') then 'expense' when x='gain' then 'revenue' else 'equity' end,
 case when x in('accum','impair','gain','offset','surplus') then 'credit' else 'debit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['cost','accum','impair','bank','expense','loss','gain','offset','surplus']) x;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 values(pg_temp.wid('asset.period'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Synthetic asset period',pg_temp.wdate()-400,pg_temp.wdate()+400,
 pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
 select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(x),'journal_entry','SYNTHETIC-ASSET-'||x||'-',pg_temp.wid('creator'),pg_temp.wid('creator')
 from unnest(array['branch','branch2']) x;
create function pg_temp.acmd(payload jsonb,v bigint,k text,b text default 'branch') returns jsonb language sql as $$
 select api.assets_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid('asset.command.'||k),
  pg_temp.wid('asset.command.'||k),now(),payload,v) $$;
create function pg_temp.abook(resid text default '100',months integer default 3) returns jsonb language sql as $$
 select jsonb_build_object('residual',resid,'remaining_months',months,'method','straight_line','convention','in_service_month',
  'rate_numerator',1,'rate_denominator',1,'precision',2,'expense_account_id',pg_temp.wid('asset.account.expense')) $$;
create function pg_temp.aopening(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','opening','id',pg_temp.wid('asset.'||k),'proposal_id',pg_temp.wid('asset.proposal.'||k),
 'source_id',pg_temp.wid('asset.source.'||k),'source_reference','SYNTHETIC-'||upper(k),'code',upper(k),'name','Synthetic asset '||k,
 'ownership','Synthetic owned','currency_code','LKR','in_service',(date_trunc('month',pg_temp.wdate())-interval '3 months')::date,
 'location_id',pg_temp.wid('asset.location.branch'),'custodian_id',null,'cost','1000','opening_accumulated','400',
 'cost_components',jsonb_build_array(jsonb_build_object('code','OPENING','name','Governed synthetic opening','amount','1000')),
 'cost_account_id',pg_temp.wid('asset.account.cost'),'accumulated_account_id',pg_temp.wid('asset.account.accum'),
 'impairment_account_id',pg_temp.wid('asset.account.impair'),'offset_account_id',pg_temp.wid('asset.account.offset'),
 'book',pg_temp.abook(),'posting_date',(date_trunc('month',pg_temp.wdate())-interval '3 months')::date,'reason','Synthetic governed opening') $$;
create function pg_temp.astate(k text default 'a') returns jsonb language sql as $$select assets.summary(pg_temp.wid('asset.'||k)) $$;
create function pg_temp.aproposal(action text,k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action',action,'id',r.id,'proposal_id',p.id,'digest',p.digest,'reason','Synthetic exact proposal '||action)
 from assets.register r join assets.proposals p on p.id=r.current_proposal_id where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.adep(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','depreciate','id',r.id,'book_id',r.current_book_id,'period_index',r.posted_periods+1,'reason','Synthetic exact period')
 from assets.register r where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.areverse(k text default 'a') returns jsonb language sql as $$
 select jsonb_build_object('action','reverse','id',r.id,'effect_id',r.last_effect_id,'reason','Synthetic original effect reversal')
 from assets.register r where r.id=pg_temp.wid('asset.'||k) $$;
create function pg_temp.aprop(kind text,extra jsonb,k text default 'a',proposal text default 'p') returns jsonb language sql as $$
 select jsonb_build_object('action','propose','id',pg_temp.wid('asset.'||k),'proposal_id',pg_temp.wid('asset.proposal.'||proposal),
  'kind',kind,'posting_date',pg_temp.wdate(),'reason','Synthetic governed '||kind)||extra $$;
select pg_temp.wactor('creator');
select pg_temp.acmd(jsonb_build_object('action','location','id',pg_temp.wid('asset.location.branch'),'code','LAB','name','Synthetic lab','reason','Synthetic location'),0,'location');
select pg_temp.acmd(jsonb_build_object('action','location','id',pg_temp.wid('asset.location.branch2'),'code','LAB','name','Synthetic second lab','reason','Synthetic location'),0,'location2','branch2');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aopening(),0,'opening')->'entity'->>'status','draft','opening creates no authoritative cost');
insert into asset_assertions select is(pg_temp.astate()->>'cost','0.000000','cost remains zero until independent approval');
select pg_temp.asset_capture('opening');
insert into asset_assertions select is(api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.a'),'books',null)->'labels'->>'expense_account_id',
 'EXPENSE · Synthetic asset expense','approval review exposes the exact scoped named expense mapping');
insert into asset_assertions select is(assets.label(pg_temp.wid('other-tenant'),pg_temp.wid('entity'),'account',pg_temp.wid('asset.account.expense')),null::text,
 'named reference projection cannot read another tenant');
insert into asset_assertions select is(jsonb_typeof(api.assets_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.a'),'books',null)->'opening'->'cost'),
 'string','opening wire amounts retain exact decimal strings');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('currency')||'{"currency_code":"USD"}',0,'currency-mismatch')$q$,
 '55000','ASSET_BASE_CURRENCY_CHANGED','opening cannot reinterpret a client-frozen currency');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aopening(),0,'opening')->'entity'->>'version','1','exact opening replay is stable');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening()||'{"name":"Changed body"}',0,'opening')$q$,
 '22023','IDEMPOTENCY_MISMATCH','changed opening body cannot replay');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('b')||'{"source_reference":"synthetic-a"}',0,'duplicate')$q$,
 '55000','ASSET_SOURCE_ALREADY_OWNED','opening evidence cannot be owned twice even under a new source UUID');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('post'),1,'unapproved')$q$,
 '55000','ASSET_APPROVAL_REQUIRED','capitalization requires exact approval');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('approve'),1,'self-approve')$q$,
 '42501','ASSET_INDEPENDENT_APPROVAL_REQUIRED','preparer cannot approve own opening');
select pg_temp.wactor('creator','aal1');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening(),0,'opening')$q$,'42501','Permission denied or multi-factor authentication required.','MFA rechecked before replay');
select pg_temp.wactor('reviewer');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aproposal('approve'),1,'approve')->'entity'->>'version','2','independent approval binds exact proposal');
select pg_temp.wactor('creator');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aproposal('post'),2,'capitalize')->'entity'->>'status','active','governed opening posts atomically');
insert into asset_assertions select is(pg_temp.astate()->>'carrying','600.000000','opening cost minus original accumulation');
insert into asset_assertions select is((select count(*)::integer from assets.schedules where book_id=pg_temp.wid('asset.proposal.a')),3,'original immutable schedule materialized');
insert into asset_assertions select is((select sum(base_debit-base_credit) from finance.journal_lines where journal_entry_id=(select journal_id from assets.effects where kind='capitalize')),0::numeric,'capitalization journal balanced');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.adep(),3,'dep1')->'entity'->>'version','4','first period posts once');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','exact cumulative allocation matches Dart');
select pg_temp.asset_capture('active');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),3,'stale-period')$q$,'40001','VERSION_CONFLICT','stale asset version cannot post');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(jsonb_build_object('action','reverse','id',pg_temp.wid('asset.a'),'effect_id',
 (select id from assets.effects where kind='capitalize'),'reason','Synthetic reversal'),4,'dependent-reverse')$q$,
 '55000','ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL','later depreciation blocks capitalization reversal');
insert into asset_assertions select throws_ok($q$update assets.schedules set facts='{}' where book_id=pg_temp.wid('asset.proposal.a')$q$,
 '55000','ASSET_HISTORY_IMMUTABLE','schedule facts cannot be overwritten');
insert into asset_assertions select is(pg_temp.acmd(pg_temp.aprop('book_revision',jsonb_build_object('book',pg_temp.abook('100',2)),proposal=>'book2'),4,'book2-propose')->'entity'->>'version','5','prospective book proposed');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),5,'blocked-period')$q$,'55000','ASSET_SCHEDULE_STALE','pending book freezes competing depreciation');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),5,'book2-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),6,'book2-post');
insert into asset_assertions select is((select basis->>'opening_accumulated' from assets.books where id=pg_temp.wid('asset.proposal.book2')),'566.670000','prospective book retains posted accumulation');
insert into asset_assertions select is((select basis->>'start_date' from assets.books where id=pg_temp.wid('asset.proposal.book2')),
 ((date_trunc('month',pg_temp.wdate())-interval '2 months')::date)::text,'prospective book begins at first unposted month');
select pg_temp.acmd(pg_temp.adep(),7,'book2-dep');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','733.330000','prospective half-even amount preserves total');
select pg_temp.acmd(pg_temp.areverse(),8,'book2-dep-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','original period reversal restores exact prior accumulation');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),9,'same-period-again')$q$,
 '55000','ASSET_REBOOK_AFTER_REVERSAL_REQUIRED','reversed period requires a new governed book');
select pg_temp.acmd(pg_temp.areverse(),9,'book2-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'book_id',pg_temp.wid('asset.proposal.a')::text,'book reversal restores original schedule identity');
select pg_temp.acmd(pg_temp.aprop('impair',jsonb_build_object('amount','100','loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'impair'),10,'impair-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),11,'impair-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),12,'impair-post');
select pg_temp.asset_capture('impaired');
insert into asset_assertions select is(pg_temp.astate()->>'impairment','100.000000','impairment reserve is explicit');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','impairment does not rewrite depreciation history');
select pg_temp.acmd(pg_temp.areverse(),13,'impair-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'impairment','0.000000','original impairment reversal restores reserve');
select pg_temp.acmd(pg_temp.aprop('revalue',jsonb_build_object('cost','1100','surplus_account_id',pg_temp.wid('asset.account.surplus'),
 'loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'revalue'),14,'revalue-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),15,'revalue-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),16,'revalue-post');
insert into asset_assertions select is(pg_temp.astate()->>'cost','1100.000000','configured revaluation retains revised gross cost');
select pg_temp.acmd(pg_temp.areverse(),17,'revalue-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'cost','1000.000000','original revaluation reversal restores cost');
select pg_temp.acmd(pg_temp.aprop('dispose',jsonb_build_object('proceeds','500','proceeds_account_id',pg_temp.wid('asset.account.bank'),
 'gain_account_id',pg_temp.wid('asset.account.gain'),'loss_account_id',pg_temp.wid('asset.account.loss')),proposal=>'dispose'),18,'dispose-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),19,'dispose-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post'),20,'dispose-post');
select pg_temp.asset_capture('disposed');
insert into asset_assertions select is(pg_temp.astate()->>'status','disposed','disposal commits with original cost and accumulation');
insert into asset_assertions select is((select sum(base_credit-base_debit) from finance.journal_lines where account_id=pg_temp.wid('asset.account.gain')),66.67::numeric,'exact disposal gain matches original carrying');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),21,'disposed-dep')$q$,'55000','ASSET_SCHEDULE_STALE','disposed asset denies depreciation');
select pg_temp.acmd(pg_temp.areverse(),21,'dispose-reverse');
insert into asset_assertions select is(pg_temp.astate()->>'status','active','original disposal reversal restores active state');
insert into asset_assertions select is(pg_temp.astate()->>'carrying','433.330000','original disposal reversal restores exact carrying');
-- Both branch authorities are required on original command and replay.
select pg_temp.wactor('branch-manager');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aprop('transfer',jsonb_build_object('destination_branch_id',pg_temp.wid('branch2'),
 'location_id',pg_temp.wid('asset.location.branch2'),'custodian_id',null),proposal=>'transfer'),22,'narrow-transfer')$q$,
 '42501','Permission denied or multi-factor authentication required.','source-only branch role cannot authorize destination');
select pg_temp.wactor('creator');
select pg_temp.acmd(pg_temp.aprop('transfer',jsonb_build_object('destination_branch_id',pg_temp.wid('branch2'),
 'location_id',pg_temp.wid('asset.location.branch2'),'custodian_id',null),proposal=>'transfer'),22,'transfer-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve'),23,'transfer-approve');
select pg_temp.wactor('creator');
create temporary table asset_saved_requests as select pg_temp.aproposal('post') as transfer_post;
grant select on asset_saved_requests to authenticated;
insert into asset_assertions select is(pg_temp.acmd((select transfer_post from asset_saved_requests),24,'transfer-post')->'entity'->>'current_branch_id',
 pg_temp.wid('branch2')::text,'transfer retains command branch and resulting accountable branch separately');
insert into asset_assertions select is((api.assets_register(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'))->'items'->0->>'original_branch_id'),
 pg_temp.wid('branch')::text,'original ownership branch survives transfer');
-- Narrow the creator to its source branch after completion; destination replay must deny.
update core.role_assignments set branch_id=pg_temp.wid('branch') where role_id=pg_temp.wid('creator.role');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd((select transfer_post from asset_saved_requests),24,'transfer-post')$q$,
 '42501','Permission denied or multi-factor authentication required.','revoked destination authority denies completed transfer replay');
insert into asset_assertions select throws_ok($q$select api.assets_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('asset.command.transfer-post'),'post')$q$,'42501','Permission denied or multi-factor authentication required.',
 'receipt lookup rechecks original destination transfer authority');
update core.role_assignments set branch_id=null where role_id=pg_temp.wid('creator.role');
select pg_temp.acmd(pg_temp.areverse(),25,'transfer-reverse','branch2');
insert into asset_assertions select is(pg_temp.astate()->>'branch_id',pg_temp.wid('branch')::text,'original transfer reversal restores branch and location');
insert into asset_assertions select is(pg_temp.astate()->>'location_id',pg_temp.wid('asset.location.branch')::text,'original location restored exactly');
update finance.fiscal_periods set state='soft_locked' where id=pg_temp.wid('asset.period');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep(),26,'closed-dep')$q$,'55000','PERIOD_CLOSED','closed period denies exact scheduled posting');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.areverse(),26,'closed-reverse')$q$,'55000','PERIOD_CLOSED','closed original period denies reversal');
insert into asset_assertions select is(pg_temp.astate()->>'accumulated','566.670000','closed-period failures preserve all balances');
update finance.fiscal_periods set state='open' where id=pg_temp.wid('asset.period');
select pg_temp.acmd(pg_temp.adep(),26,'a-dep2');
select pg_temp.acmd(pg_temp.adep(),27,'a-dep3');
insert into asset_assertions select is(pg_temp.astate()->>'carrying','100.000000','original full life preserves exact residual after correction chain');
-- A late failure must roll back journal numbering, books, asset state and effects.
select pg_temp.acmd(pg_temp.aopening('b'),0,'b-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','b'),1,'b-approve');
select pg_temp.wactor('creator');
create temporary table asset_late_before as select to_jsonb(s) as sequence from core.document_sequences s
 where tenant_id=pg_temp.wid('tenant') and branch_id=pg_temp.wid('branch') and document_type='journal_entry';
create function pg_temp.asset_fail_outbox() returns trigger language plpgsql as $$begin
 if new.topic='assets.post' then raise exception using errcode='P0001',message='SYNTHETIC_ASSET_LATE_FAIL';end if;return new;end $$;
create trigger asset_synthetic_late_fail before insert on core.outbox_events for each row execute function pg_temp.asset_fail_outbox();
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aproposal('post','b'),2,'b-post')$q$,
 'P0001','SYNTHETIC_ASSET_LATE_FAIL','late outbox failure aborts entire capitalization');
insert into asset_assertions select is(pg_temp.astate('b')->>'cost','0.000000','late failure restores provisional zero cost');
insert into asset_assertions select is(pg_temp.astate('b')->>'version','2','late failure restores approved version');
insert into asset_assertions select is((select count(*)::integer from assets.books where asset_id=pg_temp.wid('asset.b')),0,'late failure leaves no materialized books');
insert into asset_assertions select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.b')),0,'late failure leaves no authoritative effects');
insert into asset_assertions select is((select to_jsonb(s) from core.document_sequences s where tenant_id=pg_temp.wid('tenant') and branch_id=pg_temp.wid('branch') and document_type='journal_entry'),
 (select sequence from asset_late_before),'late failure rolls back document numbering');
drop trigger asset_synthetic_late_fail on core.outbox_events;
select pg_temp.acmd(pg_temp.aproposal('post','b'),2,'b-post');
select pg_temp.acmd(pg_temp.areverse('b'),3,'b-reverse');
insert into asset_assertions select is(pg_temp.astate('b')->>'status','reversed','opening reversal retains terminal ownership history');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('c')||'{"source_reference":"SYNTHETIC-B"}',0,'b-source-again')$q$,
 '55000','ASSET_SOURCE_ALREADY_OWNED','reversal does not release the same opening evidence for another capitalization');
-- Final schedule conservation and explicit zero periods against the installed journal.
select pg_temp.acmd(pg_temp.aopening('tiny')||jsonb_build_object('cost','0.03','opening_accumulated','0',
 'cost_components',jsonb_build_array(jsonb_build_object('code','TINY','name','Synthetic tiny value','amount','0.03')),
 'book',pg_temp.abook('0',5),'in_service',(date_trunc('month',pg_temp.wdate())-interval '6 months')::date,
 'posting_date',(date_trunc('month',pg_temp.wdate())-interval '6 months')::date),0,'tiny-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','tiny'),1,'tiny-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','tiny'),2,'tiny-post');
select pg_temp.acmd(pg_temp.adep('tiny'),3,'tiny-dep1');
select pg_temp.acmd(pg_temp.adep('tiny'),4,'tiny-dep2');
select pg_temp.acmd(pg_temp.adep('tiny'),5,'tiny-dep3');
select pg_temp.acmd(pg_temp.adep('tiny'),6,'tiny-dep4');
select pg_temp.acmd(pg_temp.adep('tiny'),7,'tiny-dep5');
insert into asset_assertions select is(pg_temp.astate('tiny')->>'carrying','0.000000','final period conserves exact depreciable value');
insert into asset_assertions select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate'),5,'zero periods are retained facts');
insert into asset_assertions select is((select count(*)::integer from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate' and journal_id is null),2,'zero periods do not fabricate zero journals');
insert into asset_assertions select is((select sum(base_debit) from finance.journal_lines where account_id=pg_temp.wid('asset.account.expense') and source_line_id in
 (select id from assets.effects where asset_id=pg_temp.wid('asset.tiny') and kind='depreciate')),0.03::numeric,'tiny journals conserve original cost');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.adep('tiny'),8,'tiny-beyond-life')$q$,'55000','ASSET_SCHEDULE_STALE','posting beyond final life rejected');
select pg_temp.acmd(pg_temp.aopening('paged')||jsonb_build_object('book',pg_temp.abook('100',1200)),0,'paged-opening');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','paged'),1,'paged-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','paged'),2,'paged-post');
insert into asset_assertions select is(jsonb_array_length(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'))->'items'),50,'1200-month schedule response remains bounded at 50');
insert into asset_assertions select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'))->>'next_cursor','50','ordinal schedule cursor identifies the final returned period');
insert into asset_assertions select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1150)->'items'->49->>'closing_carrying','100.000000','last bounded page retains original final residual');
insert into asset_assertions select is(api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1150)->>'next_cursor',null::text,'terminal schedule page has no false continuation');
insert into asset_assertions select throws_ok($q$select api.assets_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('asset.paged'),
 pg_temp.wid('asset.proposal.paged'),1201)$q$,'22023','ASSET_PAGE_INVALID','unbounded schedule cursor rejected');
insert into asset_assertions select is(api.assets_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'assets.view')->>'procurement_provider','false','unimplemented procurement provider explicit');
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening('x')||'{"action":"procurement"}',0,'fake-procurement')$q$,
 '22023','ASSET_COMMAND_INVALID','invented procurement metadata cannot capitalize');
select pg_temp.wactor('branch-manager');
set local role authenticated;
insert into asset_assertions select throws_ok($q$select api.assets_register(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'))$q$,
 '42501','Permission denied or multi-factor authentication required.','authenticated branch actor cannot read other branch register');
insert into asset_assertions select throws_ok($q$select api.assets_register(pg_temp.wid('other-tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501','Permission denied or multi-factor authentication required.','cross-tenant scope denied before data');
insert into asset_assertions select throws_ok($q$select count(*) from assets.register$q$,'42501',null,'authenticated direct asset table access denied');
reset role;
select pg_temp.wactor('creator');
update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
insert into asset_assertions select throws_ok($q$select pg_temp.acmd(pg_temp.aopening(),0,'opening')$q$,'42501','ASSET_ENTITLEMENT_REQUIRED','entitlement rechecked before replay');
update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
insert into asset_assertions select ok(not exists(select 1 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name like 'assets.%'
 and(response::text like '%600.000000%' or response::text like '%Synthetic owned%' or response::text like '%SYNTHETIC-A%')),'generic receipts contain no source/financial evidence');
insert into asset_assertions select ok(not exists(select 1 from audit.events where tenant_id=pg_temp.wid('tenant') and event_type like 'assets.%'
 and(after_context::text like '%600.000000%' or after_context::text like '%Synthetic owned%')),'generic audit contains no financial/ownership evidence');

-- Actual operational link to governed fixed-asset opening, depreciation and transfer.
reset role;select pg_temp.wactor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'service.configure');
-- Test-only snapshot builders read synthetic owner facts; all mutations still use named APIs.
alter function pg_temp.adep(text) security definer;
alter function pg_temp.aproposal(text,text) security definer;
alter function pg_temp.areverse(text) security definer;
create temporary table asset_equipment_samples(label text primary key,body jsonb);
grant select,insert on asset_equipment_samples to authenticated;
create temporary table asset_equipment_input as select jsonb_build_object('action','equipment','id',pg_temp.wid('internal-equipment'),'kind','asset','customer_id',null,
 'code','INTERNAL-EQ','name','Internal fixed asset equipment','identity','INTERNAL-ASSET-PAGED','provider_id',pg_temp.wid('asset.paged'),
 'provider_version',a.version,'provider_digest',service.asset_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),a.id)->>'digest','reason','Governed internal maintenance association') body
 from assets.register a where a.id=pg_temp.wid('asset.paged');
grant select on asset_equipment_input to authenticated;
create function pg_temp.aec(p jsonb,k text,b text default 'branch') returns jsonb language sql as $$select api.service_asset_equipment_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid('link.'||k),pg_temp.wid('link.'||k),now(),p,0)$$;
insert into link_assertions select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='service.asset_equipment_links'::regclass),'AC-401 immutable link forces RLS');
insert into link_assertions select ok(not has_table_privilege('authenticated','service.asset_equipment_links','SELECT') and not has_function_privilege('authenticated','service.asset_source(uuid,uuid,uuid,uuid,boolean,boolean)','EXECUTE'),'AC-401 source helper and table are owner-only');
insert into link_assertions select ok(not has_function_privilege('authenticated','api.service_command_customer_base(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),'AC-401 original command cannot bypass asset guards');
create temporary table link_before_effects as select count(*) n from assets.effects;
set local role authenticated;
insert into asset_equipment_samples values('sources',api.service_asset_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch')));
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from asset_equipment_input)||jsonb_build_object('provider_version',1),'stale')$$,'40001','SERVICE_ASSET_SOURCE_CHANGED','AC-414 stale selected asset version rejected');
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from asset_equipment_input)||jsonb_build_object('provider_digest',repeat('0',64)),'digest')$$,'40001','SERVICE_ASSET_SOURCE_CHANGED','AC-414 changed operational source digest rejected');
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from asset_equipment_input)||jsonb_build_object('customer_id',pg_temp.wid('customer')),'fakecustomer')$$,'22023','SERVICE_ASSET_COMMAND_INVALID','AC-414 no invented customer for internal asset');
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from asset_equipment_input),'otherbranch','branch2')$$,'55000','SERVICE_ASSET_NOT_ELIGIBLE','AC-401 internal asset must belong to current accountable branch');
insert into asset_equipment_samples values('receipt',pg_temp.aec((select body from asset_equipment_input),'create'));
insert into link_assertions select is(pg_temp.aec((select body from asset_equipment_input),'create'),(select body from asset_equipment_samples where label='receipt'),'AC-414 exact actor replay gives original link receipt');
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from asset_equipment_input)||jsonb_build_object('id',pg_temp.wid('duplicate-link'),'code','DUPLICATE','identity','DUPLICATE-LINK'),'duplicate')$$,'23505',null,'AC-416 asset links only once');
insert into asset_equipment_samples values('link',api.service_asset_link(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('internal-equipment')));
reset role;
insert into link_assertions select is((select count(*) from assets.effects),(select n from link_before_effects),'AC-416 equipment association creates no capitalization or accounting effect');
insert into link_assertions select ok(not ((select body from asset_equipment_samples where label='sources')::text ~ '"(cost|book_id|accumulated|impairment|cost_account_id)"'),'AC-401 public operational source contains no asset book or cost');
insert into link_assertions select throws_ok($$update service.asset_equipment_links set reason='Changed' where equipment_id=pg_temp.wid('internal-equipment')$$,'55000','SERVICE_HISTORY_IMMUTABLE','AC-415 original association basis cannot be overwritten');
update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
set local role authenticated;
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from asset_equipment_input),'create')$$,'42501','ASSET_ENTITLEMENT_REQUIRED','AC-401 asset entitlement checked before original receipt replay');
insert into link_assertions select throws_ok($$select api.service_asset_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('link.create'))$$,'42501','ASSET_ENTITLEMENT_REQUIRED','AC-401 own receipt rechecks both entitlements');
reset role;update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback' and entitlement_code='module.assets';
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('creator.role') and permission_code='assets.view';
set local role authenticated;
insert into link_assertions select throws_ok($$select api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'equipment',pg_temp.wid('internal-equipment'))$$,'42501','SERVICE_ASSET_ACCESS_REQUIRED','AC-401 internal equipment historical read requires asset permission');
insert into link_assertions select ok(exists(select 1 from jsonb_array_elements(api.service_list(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'equipment')->'items') x where x->>'kind'='customer') and not exists(select 1 from jsonb_array_elements(api.service_list(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'equipment')->'items') x where x->>'kind'='asset'),'AC-401 mixed register preserves authorized customer equipment and filters internal rows before paging');
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from asset_equipment_input),'create')$$,'42501','Permission denied or multi-factor authentication required.','AC-401 revoked asset permission checked before replay');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'assets.view');
set local role authenticated;
select pg_temp.sc('ticket','internal-ticket',pg_temp.sticket('INTERNAL-TICKET')||jsonb_build_object('customer_id',null,'equipment_id',pg_temp.wid('internal-equipment')));
select pg_temp.sc('order','internal-order',jsonb_build_object('ticket_id',pg_temp.wid('internal-ticket')));
insert into link_assertions select throws_ok($$select pg_temp.sc('labor','internal-labor',jsonb_build_object('order_id',pg_temp.wid('internal-order'),'billing_kind','billable'))$$,'55000','SERVICE_INTERNAL_NONBILLABLE','AC-414 internal labor cannot create customer billing');
insert into link_assertions select throws_ok($$select pg_temp.sc('complete','internal-order',jsonb_build_object('customer_confirmed',true),1,'fakeconfirm')$$,'22023','SERVICE_INTERNAL_CONFIRMATION_REQUIRED','AC-414 internal completion cannot fabricate customer acceptance');
select pg_temp.sc('plan','internal-plan',jsonb_build_object('equipment_id',pg_temp.wid('internal-equipment'),'policy_id',pg_temp.wid('policy'),'name','Internal annual maintenance','basis','calendar','interval_units',30,'next_date',pg_temp.wdate(),'next_meter',null));
select pg_temp.sc('generate','internal-plan',jsonb_build_object('ticket_id',pg_temp.wid('internal-pm-ticket'),'order_id',pg_temp.wid('internal-pm-order'),'occurrence_id',pg_temp.wid('internal-occurrence'),'observed_utc',pg_temp.sutc(12)),1,'internal-generate');
insert into asset_equipment_samples values('internal-ticket',api.service_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'ticket',pg_temp.wid('internal-pm-ticket')));
reset role;
insert into link_assertions select ok((select customer_id is null and contact_id is null from service.tickets where id=pg_temp.wid('internal-pm-ticket')),'AC-415 actual maintenance occurrence retains internal identity with no customer');
insert into link_assertions select is((select count(*)::integer from service.maintenance_occurrences where plan_id=pg_temp.wid('internal-plan')),1,'AC-415 internal occurrence has one attributable work order');
set local role authenticated;
select pg_temp.acmd(pg_temp.adep('paged'),3,'link-depreciate');
insert into link_assertions select is(pg_temp.aec((select body from asset_equipment_input),'create'),(select body from asset_equipment_samples where label='receipt'),'AC-415 harmless depreciation retains original link replay');
select pg_temp.sc('dispatch','internal-order',jsonb_build_object('employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),'start_utc',pg_temp.sutc(15),'end_utc',pg_temp.sutc(16),'booking_id',pg_temp.wid('internal-booking')),1,'internal-dispatch');
select pg_temp.sc('accept','internal-order',jsonb_build_object('observed_utc',pg_temp.sutc(15)),2,'internal-accept');
select pg_temp.sc('start','internal-order',jsonb_build_object('observed_utc',pg_temp.sutc(15)),3,'internal-start');
select pg_temp.sc('labor','internal-nonbillable-labor',jsonb_build_object('order_id',pg_temp.wid('internal-order'),'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),'start_utc',pg_temp.sutc(15),'end_utc',pg_temp.sutc(16),'breaks','[]'::jsonb,'claim_id',null,'hourly_cost','12','currency_code','LKR','precision',2,'billing_kind','nonbillable','hourly_billing','0','billing_reference','Internal maintenance, no customer billing'));
select pg_temp.wactor('reviewer');select pg_temp.sc('approve_labor','internal-nonbillable-labor','{}',1,'internal-approve');
select pg_temp.wactor('creator');
select pg_temp.sc('complete','internal-order',jsonb_build_object('observed_utc',pg_temp.sutc(16),'resolution','Internal maintenance completed','customer_confirmed',false,'exception_reason','Internal custodian confirmed maintenance; no customer exists'),4,'internal-complete');
reset role;
insert into link_assertions select ok((select status='approved' and billing_kind='nonbillable' and seconds=3600 and billable_amount=0 from service.labor where id=pg_temp.wid('internal-nonbillable-labor')),'AC-414 internal actual labor retains common work and exact nonbillable cost');
insert into link_assertions select throws_ok($$select service.billing_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('internal-nonbillable-labor'))$$,'55000','SERVICE_INTERNAL_NONBILLABLE','AC-414 protected billing provider explicitly rejects internal no-customer source');
insert into link_assertions select lives_ok($$select service.asset_equipment_guard(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('internal-equipment'),true)$$,'AC-414 current eligibility tolerates harmless asset version change');
set local role authenticated;
select pg_temp.acmd(pg_temp.aprop('transfer',jsonb_build_object('destination_branch_id',pg_temp.wid('branch2'),'location_id',pg_temp.wid('asset.location.branch2'),'custodian_id',null),'paged','link-transfer'),4,'link-transfer-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','paged'),5,'link-transfer-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','paged'),6,'link-transfer-post');
insert into link_assertions select throws_ok($$select pg_temp.sc('dispatch','internal-order','{}',1,'after-transfer')$$,'55000','SERVICE_ASSET_NOT_ELIGIBLE','AC-414 transferred asset blocks governed dispatch before staffing mutation');
insert into link_assertions select throws_ok($$select pg_temp.sc('generate','internal-plan',jsonb_build_object('observed_utc',pg_temp.sutc(12)),2,'generate-transferred')$$,'55000','SERVICE_ASSET_NOT_ELIGIBLE','AC-415 transferred asset blocks occurrence before creation');
insert into link_assertions select lives_ok($$select pg_temp.sc('generate','internal-plan',jsonb_build_object('ticket_id',pg_temp.wid('internal-pm-ticket'),'order_id',pg_temp.wid('internal-pm-order'),'occurrence_id',pg_temp.wid('internal-occurrence'),'observed_utc',pg_temp.sutc(12)),1,'internal-generate')$$,'AC-415 exact original occurrence replay remains historical after transfer');
insert into link_assertions select throws_ok($$select api.service_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('internal-generate'),pg_temp.wid('internal-generate'),null,
 jsonb_build_object('action','generate','id',pg_temp.wid('internal-plan'),'reason','Synthetic service evidence','ticket_id',pg_temp.wid('internal-pm-ticket'),'order_id',pg_temp.wid('internal-pm-order'),'occurrence_id',pg_temp.wid('internal-occurrence'),'observed_utc',pg_temp.sutc(12)),1)$$,'22023','SERVICE_COMMAND_INVALID','AC-401 internal original replay still rejects null issued timestamp');
insert into link_assertions select throws_ok($$select api.service_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('internal-generate'),pg_temp.wid('internal-generate'),clock_timestamp()+interval '10 minutes',
 jsonb_build_object('action','generate','id',pg_temp.wid('internal-plan'),'reason','Synthetic service evidence','ticket_id',pg_temp.wid('internal-pm-ticket'),'order_id',pg_temp.wid('internal-pm-order'),'occurrence_id',pg_temp.wid('internal-occurrence'),'observed_utc',pg_temp.sutc(12)),1)$$,'22023','SERVICE_COMMAND_INVALID','AC-401 internal original replay still rejects future issued timestamp');
reset role;
insert into link_assertions select is((select source_basis from service.asset_equipment_links where equipment_id=pg_temp.wid('internal-equipment')),(select body->'source_basis' from asset_equipment_samples where label='link'),'AC-415 transfer never rewrites original operational source');
set local role authenticated;
select pg_temp.acmd(pg_temp.areverse('paged'),7,'link-transfer-reverse','branch2');
select pg_temp.acmd(pg_temp.aprop('dispose',jsonb_build_object('proceeds','0','proceeds_account_id',pg_temp.wid('asset.account.bank'),'gain_account_id',pg_temp.wid('asset.account.gain'),'loss_account_id',pg_temp.wid('asset.account.loss')),'paged','link-dispose'),8,'link-dispose-propose');
select pg_temp.wactor('reviewer');select pg_temp.acmd(pg_temp.aproposal('approve','paged'),9,'link-dispose-approve');
select pg_temp.wactor('creator');select pg_temp.acmd(pg_temp.aproposal('post','paged'),10,'link-dispose-post');
insert into link_assertions select throws_ok($$select pg_temp.sc('dispatch','internal-pm-order','{}',1,'after-disposal')$$,'55000','SERVICE_ASSET_NOT_ELIGIBLE','AC-414 disposed asset blocks dispatch before mutation');
insert into link_assertions select throws_ok($$select pg_temp.sc('generate','internal-plan',jsonb_build_object('observed_utc',pg_temp.sutc(12)),2,'generate-disposed')$$,'55000','SERVICE_ASSET_NOT_ELIGIBLE','AC-415 disposed asset blocks new occurrence');
reset role;
-- Late immutable event failure leaves no equipment or immutable link residue.
create function pg_temp.link_late_failure() returns trigger language plpgsql as $$begin if new.aggregate_id=pg_temp.wid('late-link') then raise exception using errcode='P0001',message='SYNTHETIC_LINK_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_link_failure before insert on service.events for each row execute function pg_temp.link_late_failure();
create temporary table late_link_input as select(select body from asset_equipment_input)||jsonb_build_object('id',pg_temp.wid('late-link'),'code','LATE-LINK','identity','LATE-LINK','provider_id',a.id,'provider_version',a.version,'provider_digest',service.asset_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),a.id)->>'digest') body from assets.register a where a.id=pg_temp.wid('asset.a') and a.branch_id=pg_temp.wid('branch');
-- Asset a may have transferred in its own suite; use an eligible unlinked active asset instead.
delete from late_link_input;
insert into late_link_input select(select body from asset_equipment_input)||jsonb_build_object('id',pg_temp.wid('late-link'),'code','LATE-LINK','identity','LATE-LINK','provider_id',a.id,'provider_version',a.version,'provider_digest',service.asset_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),a.id)->>'digest') from assets.register a where a.tenant_id=pg_temp.wid('tenant') and a.branch_id=pg_temp.wid('branch') and a.status='active' and not exists(select 1 from service.asset_equipment_links l where l.asset_id=a.id) order by a.id limit 1;
grant select on late_link_input to authenticated;
set local role authenticated;
insert into link_assertions select throws_ok($$select pg_temp.aec((select body from late_link_input),'late')$$,'P0001','SYNTHETIC_LINK_LATE_FAILURE','AC-414 late audit failure rolls back complete asset association');
reset role;
insert into link_assertions select ok(not exists(select 1 from service.equipment where id=pg_temp.wid('late-link')) and not exists(select 1 from service.asset_equipment_links where equipment_id=pg_temp.wid('late-link')) and not exists(select 1 from core.command_receipts where command_id=pg_temp.wid('link.late')),'AC-414 late failure has no equipment/link/receipt residue');
drop trigger synthetic_link_failure on service.events;

do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from(select message from service_assertions union all select message from asset_assertions union all select message from link_assertions) q where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
select(select count(*) from service_assertions)+(select count(*) from asset_assertions)+(select count(*) from link_assertions) assertion_count,jsonb_object_agg(label,body) asset_equipment_client_samples from asset_equipment_samples;
rollback;