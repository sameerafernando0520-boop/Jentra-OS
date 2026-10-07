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

-- UNAPPLIED W4-05 planning/common-time candidate. No persistent grants or plan changes.
create schema if not exists projects;
revoke all on schema projects from public,anon,authenticated;
insert into core.permissions(code,module,description,privileged) values
 ('projects.view','projects','Read scoped operational projects',false),
 ('projects.manage','projects','Prepare project plans and progress with MFA',true),
 ('projects.approve','projects','Independently approve frozen project plans with MFA',true),
 ('projects.cost.view','projects','Read separately protected synthetic project costing',true),
 ('projects.cost.manage','projects','Prepare synthetic costing bases with MFA',true),
 ('projects.time.manage','projects','Prepare exact project time revisions with MFA',true),
 ('projects.time.approve','projects','Independently decide project time with MFA',true),
 ('projects.billing.manage','projects','Govern whole project billing sources with MFA',true)
on conflict(code) do nothing;
create table projects.register(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),name text not null,
 customer_id uuid,manager_id uuid not null,currency_code text not null references core.currencies(code),
 precision integer not null check(precision between 0 and 6),start_date date not null,end_date_exclusive date not null,
 status text not null default 'open' check(status in('open','closed')),
 version bigint not null default 1 check(version between 1 and 9007199254740990),current_plan_id uuid,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
 check(length(name) between 1 and 160 and name=btrim(name) and name !~ '[[:cntrl:]]'),
 check(start_date>='0001-01-01'::date and end_date_exclusive<='9999-12-31'::date
  and end_date_exclusive-start_date between 1 and 366),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,manager_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id)
);
create table projects.plans(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,
 version bigint not null check(version between 1 and 9007199254740990),
 basis_digest text not null check(basis_digest ~ '^[a-f0-9]{64}$'),terms text not null,reason text not null,
 status text not null default 'pending' check(status in('pending','approved','rejected','superseded')),
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,project_id,id),unique(project_id,version),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id)
);
create table projects.tasks(
 tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,plan_id uuid not null,id uuid not null,
 name text not null,owner_id uuid not null,owner_name text not null,start_date date not null,end_date_exclusive date not null,planned_seconds bigint not null check(planned_seconds between 0 and 31622400),
 primary key(plan_id,id),unique(tenant_id,legal_entity_id,project_id,plan_id,id),
 check(length(name) between 1 and 160 and name=btrim(name) and name !~ '[[:cntrl:]]'),
 check(end_date_exclusive>start_date),check(length(owner_name) between 1 and 160),
 foreign key(tenant_id,legal_entity_id,owner_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id) references projects.plans(tenant_id,legal_entity_id,project_id,id)
);
create table projects.dependencies(
 tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,plan_id uuid not null,
 task_id uuid not null,prerequisite_id uuid not null,primary key(plan_id,task_id,prerequisite_id),
 check(task_id<>prerequisite_id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,task_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,prerequisite_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id)
);
create table projects.resource_slots(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,plan_id uuid not null,
 task_id uuid not null,employee_id uuid not null,calendar_version_id uuid not null,
 start_local timestamp not null,end_local timestamp not null,start_offset_seconds integer not null,end_offset_seconds integer not null,
 start_utc timestamptz not null,end_utc timestamptz not null,planned_seconds bigint not null,
 bill_rate numeric(20,6) not null check(bill_rate>=0),active boolean not null default false,
 check(end_utc>start_utc and planned_seconds=extract(epoch from end_utc-start_utc)::bigint and planned_seconds between 1 and 86400),
 unique(tenant_id,legal_entity_id,project_id,plan_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,task_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id) references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 exclude using gist(employee_id extensions.gist_uuid_ops with =,tstzrange(start_utc,end_utc,'[)') with &&) where(active)
);
-- Cost rates and budgets are physically separate from operational plan projections.
create table projects.cost_basis(
 tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,plan_id uuid primary key,
 budget numeric(20,6) not null check(budget>=0),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id) references projects.plans(tenant_id,legal_entity_id,project_id,id)
);
create table projects.resource_costs(
 tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,plan_id uuid not null,resource_slot_id uuid primary key,
 hourly_rate numeric(20,6) not null check(hourly_rate>=0),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,resource_slot_id) references projects.resource_slots(tenant_id,legal_entity_id,project_id,plan_id,id)
);
create table projects.plan_decisions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,plan_id uuid not null,
 decision text not null check(decision in('approved','rejected')),digest text not null,reason text not null,
 decided_by uuid not null references auth.users(id),decided_at timestamptz not null default clock_timestamp(),unique(plan_id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id) references projects.plans(tenant_id,legal_entity_id,project_id,id)
);
create table projects.task_progress(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,
 plan_id uuid not null,task_id uuid not null,progress integer not null check(progress between 0 and 10000),
 project_version bigint not null,reason text not null,recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),unique(project_id,project_version),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,task_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id)
);
create table projects.time_entries(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 employee_id uuid not null,version bigint not null default 1 check(version between 1 and 9007199254740990),
 current_revision_id uuid not null,status text not null default 'draft' check(status in('draft','submitted','approved','rejected','cancelled')),
 submitted_by uuid references auth.users(id),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create table projects.time_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,entry_id uuid not null,version bigint not null,
 plan_id uuid not null,task_id uuid not null,resource_slot_id uuid not null,
 start_local timestamp not null,end_local timestamp not null,start_offset_seconds integer not null,end_offset_seconds integer not null,
 start_utc timestamptz not null,end_utc timestamptz not null,breaks jsonb not null,payable_seconds bigint not null check(payable_seconds between 1 and 129600),
 attendance_claim_id uuid references people.work_claims(id),bill_amount numeric(20,6) not null check(bill_amount>=0),
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),reason text not null,supersedes_id uuid references projects.time_revisions(id),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,project_id,entry_id,id),unique(entry_id,version),
 foreign key(tenant_id,legal_entity_id,project_id,entry_id) references projects.time_entries(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,task_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,resource_slot_id) references projects.resource_slots(tenant_id,legal_entity_id,project_id,plan_id,id)
);
alter table projects.time_entries add foreign key(tenant_id,legal_entity_id,project_id,id,current_revision_id)
 references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id) deferrable initially deferred;
alter table projects.register add foreign key(tenant_id,legal_entity_id,id,current_plan_id)
 references projects.plans(tenant_id,legal_entity_id,project_id,id) deferrable initially deferred;
create table projects.time_allocations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,entry_id uuid not null,revision_id uuid not null,
 allocation_id uuid not null unique references people.work_allocations(id),claim_id uuid not null references people.work_claims(id),
 direct_claim boolean not null,
 foreign key(tenant_id,legal_entity_id,project_id,entry_id,revision_id) references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id)
);
create table projects.time_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,
 entry_id uuid not null,revision_id uuid not null,action text not null,version bigint not null,reason text not null,
 actor_id uuid not null references auth.users(id),command_id uuid not null,recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,command_id),
 foreign key(tenant_id,legal_entity_id,project_id,entry_id,revision_id) references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id)
);
create table projects.billable_units(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,branch_id uuid not null,
 source_kind text not null check(source_kind in('time','expense','milestone')),source_id uuid not null,source_version bigint not null,
 source_digest text not null check(source_digest ~ '^[a-f0-9]{64}$'),amount numeric(20,6) not null check(amount>=0),
 payable_seconds bigint check(payable_seconds between 1 and 129600),
 status text not null default 'available' check(status in('available','reserved','billed','waived','cancelled')),
 unique(tenant_id,legal_entity_id,source_kind,source_id),unique(tenant_id,legal_entity_id,project_id,id),
 check((source_kind='time')=(payable_seconds is not null)),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table projects.time_costs(
 tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,entry_id uuid not null,revision_id uuid primary key,
 hourly_rate numeric(20,6) not null check(hourly_rate>=0),amount numeric(20,6) not null check(amount>=0),
 foreign key(tenant_id,legal_entity_id,project_id,entry_id,revision_id) references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id)
);
create table projects.unit_decisions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,
 unit_id uuid not null,decision text not null check(decision in('waived','cancelled')),reason text not null,
 actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),unique(unit_id),
 foreign key(tenant_id,legal_entity_id,project_id,unit_id) references projects.billable_units(tenant_id,legal_entity_id,project_id,id)
);
create function projects.immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='PROJECT_HISTORY_IMMUTABLE';end $$;
create function projects.plan_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or (to_jsonb(new)-'status') is distinct from (to_jsonb(old)-'status')
  or not((old.status='pending' and new.status in('approved','rejected')) or(old.status='approved' and new.status='superseded')) then
  raise exception using errcode='55000',message='PROJECT_HISTORY_IMMUTABLE';end if;return new;end $$;
create trigger plan_guard before update or delete on projects.plans for each row execute function projects.plan_guard();
create function projects.slot_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or (to_jsonb(new)-'active') is distinct from(to_jsonb(old)-'active') or new.active=old.active then
  raise exception using errcode='55000',message='PROJECT_HISTORY_IMMUTABLE';end if;return new;end $$;
create trigger slot_guard before update or delete on projects.resource_slots for each row execute function projects.slot_guard();
do $$declare n text;begin
 foreach n in array array['register','plans','tasks','dependencies','resource_slots','cost_basis','plan_decisions','task_progress',
  'time_entries','time_revisions','time_allocations','time_events','billable_units','time_costs','resource_costs','unit_decisions'] loop
  execute format('alter table projects.%I enable row level security',n);
  execute format('alter table projects.%I force row level security',n);
  execute format('revoke all on projects.%I from public,anon,authenticated',n);
  if n not in('register','plans','resource_slots','time_entries','billable_units') then
   execute format('create trigger immutable before update or delete on projects.%I for each row execute function projects.immutable()',n);end if;
 end loop;
end $$;
create function projects.command_cap(act text) returns text language sql immutable set search_path='' as $$
 select case when act in('create','plan','progress','close') then 'projects.manage'
 when act in('approve_plan','reject_plan') then 'projects.approve'
 when act in('time_create','time_correct','time_submit') then 'projects.time.manage'
 when act in('time_approve','time_reject','time_cancel') then 'projects.time.approve'
 when act='waive' then 'projects.billing.manage' end $$;
-- The downstream finance migration replaces this guard atomically. Without that
-- provider no expense or invoice effects can exist; partial provider installs fail closed.
create function projects.finance_closure_guard(p_tenant uuid,p_entity uuid,p_project uuid)
returns void language plpgsql set search_path='' as $$begin
 if to_regclass('projects.expenses') is not null or to_regclass('projects.billing_batches') is not null then
  raise exception using errcode='55000',message='PROJECT_FINANCE_PROVIDER_REQUIRED';end if;
end $$;
create function projects.payroll_source(p_tenant uuid,p_entity uuid,p_branch uuid,p_employee uuid,p_claim uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare v jsonb;begin
 select jsonb_build_object('source_id',r.id,'source_version',e.version,'paid_seconds',r.payable_seconds) into v
 from projects.time_entries e join projects.time_revisions r on r.id=e.current_revision_id
 join people.work_claims c on c.id=p_claim
 where e.tenant_id=p_tenant and e.legal_entity_id=p_entity and e.branch_id=p_branch and e.employee_id=p_employee
  and e.status='approved' and r.attendance_claim_id is null and c.tenant_id=p_tenant and c.legal_entity_id=p_entity
  and c.branch_id=p_branch and c.employee_id=p_employee and c.source_kind='project' and c.source_id=r.id and c.active
  and c.payable_seconds=r.payable_seconds and exists(select 1 from projects.time_allocations a
   where a.revision_id=r.id and a.claim_id=c.id and a.direct_claim);
 if v is null then raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 return v;
end $$;
create function api.projects_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
<<project_work>>
declare act text:=p_payload->>'action';cap text;id uuid;project_id uuid;employee_id uuid;plan_id uuid;reason text;hash text;replay jsonb;
 r projects.register%rowtype;p projects.plans%rowtype;entry projects.time_entries%rowtype;revision projects.time_revisions%rowtype;
 slot projects.resource_slots%rowtype;c people.work_calendar_versions%rowtype;allowed text[];x jsonb;y jsonb;resolved jsonb;rates jsonb:='{}';
 amount numeric;bill_rate numeric;cost_rate numeric;budget numeric;total bigint;progress integer;task_id uuid;new_revision uuid:=gen_random_uuid();
 start_local timestamp;end_local timestamp;start_utc timestamptz;end_utc timestamptz;breaks jsonb;break_seconds bigint;payable bigint;
 claim uuid;attendance_claim uuid;link uuid;allocation uuid;cursor_utc timestamptz;break_start timestamptz;break_end timestamptz;
 before_state jsonb;after_state jsonb;request uuid:=gen_random_uuid();begin
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>65536
  or p_command_id is null or p_idempotency_key is null or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes'
  or p_expected_version is null or p_expected_version not between 0 and 9007199254740990
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  raise exception using errcode='22023',message='PROJECT_COMMAND_INVALID';end if;
 cap:=projects.command_cap(act);perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 reason:=projects.text(p_payload->'reason',1000);id:=(p_payload->>'id')::uuid;
 allowed:=case act when 'create' then array['action','id','code','name','customer_id','manager_id','currency_code','start_date','end_date_exclusive','reason']
  when 'plan' then array['action','id','plan_id','terms','tasks','resources','budget','reason']
  when 'approve_plan' then array['action','id','plan_id','digest','reason']
  when 'reject_plan' then array['action','id','plan_id','digest','reason']
  when 'progress' then array['action','id','task_id','progress','reason']
  when 'time_create' then array['action','id','project_id','employee_id','resource_slot_id','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','attendance_claim_id','reason']
  when 'time_correct' then array['action','id','project_id','employee_id','resource_slot_id','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','attendance_claim_id','reason']
  when 'waive' then array['action','id','unit_id','reason']
  when 'close' then array['action','id','reason']
  else array['action','id','project_id','employee_id','reason'] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then
  raise exception using errcode='22023',message='PROJECT_FIELDS_INVALID';end if;
 if act='plan' then perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.cost.manage',true);end if;
 if act in('approve_plan','reject_plan') then perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.cost.view',true);end if;
 -- Scope, entitlement, action and private-cost authority precede replay lookup.
 hash:=core.wave3_request_hash('projects.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'projects.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 project_id:=case when act like 'time_%' then (p_payload->>'project_id')::uuid else id end;
 if project_id is null then raise exception using errcode='22023',message='PROJECT_ID_REQUIRED';end if;
 -- One entity arbiter precedes sorted employee locks and project locks. No employee is acquired after a project row.
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 if act like 'time_%' then
  employee_id:=(p_payload->>'employee_id')::uuid;
  if employee_id is null then raise exception using errcode='22023',message='PROJECT_EMPLOYEE_REQUIRED';end if;
  perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employees.id=employee_id for update;
  if not found then raise exception using errcode='P0002',message='PROJECT_EMPLOYEE_NOT_FOUND';end if;
 elsif act='create' then
  employee_id:=(p_payload->>'manager_id')::uuid;
  perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employees.id=employee_id for update;
 elsif act='plan' then
  if jsonb_typeof(p_payload->'tasks') is distinct from 'array' or jsonb_array_length(p_payload->'tasks') not between 1 and 200 then
   raise exception using errcode='22023',message='PROJECT_TASK_LIMIT';end if;
  if jsonb_typeof(p_payload->'resources') is distinct from 'array' or jsonb_array_length(p_payload->'resources')>366 then
   raise exception using errcode='22023',message='PROJECT_RESOURCE_LIMIT';end if;
  perform e.id from people.employees e where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id and
   e.id in(select (value->>'employee_id')::uuid from jsonb_array_elements(p_payload->'resources')
    union select (value->>'owner_id')::uuid from jsonb_array_elements(p_payload->'tasks')) order by e.id for update;
 elsif act in('approve_plan','reject_plan','close') then
  perform e.id from people.employees e where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id and e.id in(
   select s.employee_id from projects.resource_slots s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id
    and s.project_id=project_id and (s.active or s.plan_id=(p_payload->>'plan_id')::uuid)
   union select t.owner_id from projects.tasks t where t.tenant_id=p_tenant_id and t.legal_entity_id=p_legal_entity_id
    and t.project_id=project_id and t.plan_id=(p_payload->>'plan_id')::uuid) order by e.id for update;
 end if;
 select * into r from projects.register q where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id
  and q.branch_id=p_branch_id and q.id=project_id for update;
 if act='create' then
  if r.id is not null or p_expected_version<>0 then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  if coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' or employee_id is null
   or p_payload->>'currency_code' is distinct from(select currency_code from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id)
   or (p_payload->>'start_date')::date is null or (p_payload->>'end_date_exclusive')::date is null then
   raise exception using errcode='22023',message='PROJECT_CREATE_INVALID';end if;
  if not exists(select 1 from people.employment_assignments a join people.employment_spells s on s.id=a.spell_id
   where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=employee_id
   and daterange(a.start_date,a.end_date_exclusive,'[)') @> daterange((p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,'[)')
   and daterange(s.start_date,s.end_date_exclusive,'[)') @> daterange((p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,'[)')) then
   raise exception using errcode='55000',message='PROJECT_MANAGER_COVERAGE_REQUIRED';end if;
  if p_payload->>'customer_id' is not null and not exists(select 1 from crm.parties where tenant_id=p_tenant_id
   and parties.id=(p_payload->>'customer_id')::uuid and status='active' and kind in('customer','both')) then
   raise exception using errcode='55000',message='PROJECT_CUSTOMER_INVALID';end if;
  insert into projects.register(id,tenant_id,legal_entity_id,branch_id,code,name,customer_id,manager_id,currency_code,precision,start_date,end_date_exclusive,created_by)
  select id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload->>'code',projects.text(p_payload->'name',160),(p_payload->>'customer_id')::uuid,
   employee_id,currency_code,rounding_scale,(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,auth.uid()
   from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
 elsif r.id is null then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';
 else
  if r.status<>'open' then raise exception using errcode='55000',message='PROJECT_CLOSED';end if;
  if act not like 'time_%' then
   before_state:=jsonb_build_object('id',r.id,'version',r.version,'status',r.status,'current_plan_id',r.current_plan_id);
   perform core.wave3_assert_expected_version(r.version,p_expected_version,before_state);
  end if;
  if act='plan' then
   plan_id:=(p_payload->>'plan_id')::uuid;
   if plan_id is null or jsonb_typeof(p_payload->'tasks') is distinct from 'array' or jsonb_array_length(p_payload->'tasks') not between 1 and 200 then
    raise exception using errcode='22023',message='PROJECT_TASK_LIMIT';end if;
   budget:=projects.amount(p_payload->'budget');
   if budget<>projects.ratio(budget*1000000,1,r.precision) then raise exception using errcode='22023',message='PROJECT_AMOUNT_PRECISION';end if;
   insert into projects.plans(id,tenant_id,legal_entity_id,project_id,version,basis_digest,terms,reason,prepared_by)
   values(plan_id,p_tenant_id,p_legal_entity_id,r.id,r.version+1,encode(extensions.digest(p_payload::text,'sha256'),'hex'),projects.text(p_payload->'terms',2000),reason,auth.uid());
   for x in select value from jsonb_array_elements(p_payload->'tasks') loop
    if jsonb_typeof(x) is distinct from 'object' or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['id','name','owner_id','start_date','end_date_exclusive','planned_seconds','dependencies']))
     or jsonb_typeof(x->'planned_seconds') is distinct from 'number' or coalesce(x->>'planned_seconds','') !~ '^(0|[1-9][0-9]{0,7})$'
     or jsonb_typeof(x->'dependencies') is distinct from 'array' or jsonb_array_length(x->'dependencies')>50
     or (x->>'start_date')::date<r.start_date or (x->>'end_date_exclusive')::date>r.end_date_exclusive
     or (x->>'planned_seconds')::bigint>((x->>'end_date_exclusive')::date-(x->>'start_date')::date)::bigint*86400 then
     raise exception using errcode='22023',message='PROJECT_TASK_INVALID';end if;
    resolved:=projects.task_owner_validate(p_tenant_id,p_legal_entity_id,p_branch_id,(x->>'owner_id')::uuid,
     (x->>'start_date')::date,(x->>'end_date_exclusive')::date);
    insert into projects.tasks values(p_tenant_id,p_legal_entity_id,r.id,plan_id,(x->>'id')::uuid,projects.text(x->'name',160),
     (x->>'owner_id')::uuid,resolved->>'name',
     (x->>'start_date')::date,(x->>'end_date_exclusive')::date,(x->>'planned_seconds')::bigint);
   end loop;
   for x in select value from jsonb_array_elements(p_payload->'tasks') loop
    for y in select value from jsonb_array_elements(x->'dependencies') loop
     insert into projects.dependencies values(p_tenant_id,p_legal_entity_id,r.id,plan_id,(x->>'id')::uuid,(y#>>'{}')::uuid);
    end loop;
   end loop;
   -- Distinct reachability is bounded to 200 x 200 pairs; enumerating every DAG path is unbounded.
   if exists(with recursive reach(root,node) as(
    select d.task_id,d.prerequisite_id from projects.dependencies d where d.plan_id=project_work.plan_id
    union select a.root,d.prerequisite_id from reach a
     join projects.dependencies d on d.plan_id=project_work.plan_id and d.task_id=a.node)
    select 1 from reach a where a.root=a.node) then raise exception using errcode='23514',message='PROJECT_TASK_CYCLE';end if;
   for x in select value from jsonb_array_elements(p_payload->'resources') loop
    if jsonb_typeof(x) is distinct from 'object' or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['id','task_id','employee_id','calendar_version_id','start_local','end_local','start_offset_seconds','end_offset_seconds','bill_rate','cost_rate'])) then
     raise exception using errcode='22023',message='PROJECT_RESOURCE_INVALID';end if;
    resolved:=projects.slot_validate(p_tenant_id,p_legal_entity_id,p_branch_id,(x->>'employee_id')::uuid,(x->>'calendar_version_id')::uuid,
     (x->>'start_local')::timestamp,(x->>'end_local')::timestamp,(x->>'start_offset_seconds')::integer,(x->>'end_offset_seconds')::integer);
    if not exists(select 1 from projects.tasks q where q.plan_id=project_work.plan_id and q.id=(x->>'task_id')::uuid
     and daterange(q.start_date,q.end_date_exclusive,'[)') @> daterange((x->>'start_local')::timestamp::date,
      (((x->>'end_local')::timestamp-interval '1 microsecond')::date+1),'[)')) then
     raise exception using errcode='22023',message='PROJECT_RESOURCE_OUTSIDE_TASK';end if;
    bill_rate:=projects.amount(x->'bill_rate');cost_rate:=projects.amount(x->'cost_rate');
    insert into projects.resource_slots(id,tenant_id,legal_entity_id,project_id,plan_id,task_id,employee_id,calendar_version_id,
     start_local,end_local,start_offset_seconds,end_offset_seconds,start_utc,end_utc,planned_seconds,bill_rate)
    values((x->>'id')::uuid,p_tenant_id,p_legal_entity_id,r.id,plan_id,(x->>'task_id')::uuid,(x->>'employee_id')::uuid,(x->>'calendar_version_id')::uuid,
     (x->>'start_local')::timestamp,(x->>'end_local')::timestamp,(x->>'start_offset_seconds')::integer,(x->>'end_offset_seconds')::integer,
     (resolved->>'start_utc')::timestamptz,(resolved->>'end_utc')::timestamptz,(resolved->>'planned_seconds')::bigint,bill_rate);
    insert into projects.resource_costs values(p_tenant_id,p_legal_entity_id,r.id,plan_id,(x->>'id')::uuid,cost_rate);
   end loop;
   if exists(select 1 from projects.tasks q where q.plan_id=project_work.plan_id and q.planned_seconds is distinct from
    (select coalesce(sum(s.planned_seconds),0) from projects.resource_slots s where s.plan_id=q.plan_id and s.task_id=q.id)) then
    raise exception using errcode='23514',message='PROJECT_PLANNED_SECONDS_MISMATCH';end if;
   insert into projects.cost_basis values(p_tenant_id,p_legal_entity_id,r.id,plan_id,budget);
   update projects.register set version=version+1 where register.id=r.id;
  elsif act in('approve_plan','reject_plan') then
   select * into p from projects.plans q where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.project_id=r.id
    and q.id=(p_payload->>'plan_id')::uuid for update;
   if p.id is null or p.status<>'pending' or (act='approve_plan' and p.version<>r.version) or p.basis_digest is distinct from p_payload->>'digest' then
    raise exception using errcode='55000',message='PROJECT_PLAN_STALE';end if;
   if p.prepared_by=auth.uid() then raise exception using errcode='42501',message='PROJECT_INDEPENDENT_APPROVAL_REQUIRED';end if;
   if act='approve_plan' then
    for x in select to_jsonb(q) from projects.tasks q where q.plan_id=p.id order by q.owner_id,q.id loop
     perform projects.task_owner_validate(p_tenant_id,p_legal_entity_id,p_branch_id,(x->>'owner_id')::uuid,
      (x->>'start_date')::date,(x->>'end_date_exclusive')::date);
    end loop;
    for slot in select * from projects.resource_slots q where q.plan_id=p.id order by q.employee_id,q.id loop
     perform projects.slot_validate(p_tenant_id,p_legal_entity_id,p_branch_id,slot.employee_id,slot.calendar_version_id,
      slot.start_local,slot.end_local,slot.start_offset_seconds,slot.end_offset_seconds);
    end loop;
    update projects.resource_slots set active=false where resource_slots.plan_id=r.current_plan_id and active;
    update projects.plans set status='superseded' where plans.id=r.current_plan_id;
    begin update projects.resource_slots set active=true where resource_slots.plan_id=p.id;
    exception when exclusion_violation then raise exception using errcode='23514',message='PROJECT_RESOURCE_CAPACITY_CONFLICT';end;
    update projects.register set current_plan_id=p.id where register.id=r.id;
   end if;
   update projects.plans set status=case act when 'approve_plan' then 'approved' else 'rejected' end where plans.id=p.id;
   insert into projects.plan_decisions(tenant_id,legal_entity_id,project_id,plan_id,decision,digest,reason,decided_by)
   values(p_tenant_id,p_legal_entity_id,r.id,p.id,case act when 'approve_plan' then 'approved' else 'rejected' end,p.basis_digest,reason,auth.uid());
   update projects.register set version=version+1 where register.id=r.id;
  elsif act='progress' then
   task_id:=(p_payload->>'task_id')::uuid;
   if jsonb_typeof(p_payload->'progress') is distinct from 'number' or coalesce(p_payload->>'progress','') !~ '^(0|[1-9][0-9]{0,4})$'
    or (p_payload->>'progress')::integer not between 0 and 10000 or not exists(select 1 from projects.tasks q where q.plan_id=r.current_plan_id and q.id=task_id) then
    raise exception using errcode='22023',message='PROJECT_PROGRESS_INVALID';end if;
   progress:=(p_payload->>'progress')::integer;
   if progress=10000 and exists(select 1 from projects.dependencies d where d.plan_id=r.current_plan_id and d.task_id=task_id and
    coalesce((select z.progress from projects.task_progress z where z.project_id=r.id and z.plan_id=r.current_plan_id and z.task_id=d.prerequisite_id order by z.project_version desc limit 1),0)<10000) then
    raise exception using errcode='55000',message='PROJECT_PREREQUISITES_INCOMPLETE';end if;
   if progress<10000 and exists(select 1 from projects.dependencies d where d.plan_id=r.current_plan_id and d.prerequisite_id=task_id and
    coalesce((select z.progress from projects.task_progress z where z.project_id=r.id and z.plan_id=r.current_plan_id and z.task_id=d.task_id order by z.project_version desc limit 1),0)=10000) then
    raise exception using errcode='55000',message='PROJECT_DEPENDENT_ALREADY_COMPLETE';end if;
   insert into projects.task_progress(tenant_id,legal_entity_id,project_id,plan_id,task_id,progress,project_version,reason,recorded_by)
   values(p_tenant_id,p_legal_entity_id,r.id,r.current_plan_id,task_id,progress,r.version+1,reason,auth.uid());
   update projects.register set version=version+1 where register.id=r.id;
  elsif act='close' then
   if to_regprocedure('projects.milestone_closure_guard(uuid,uuid,uuid)') is not null then
    execute 'select projects.milestone_closure_guard($1,$2,$3)' using p_tenant_id,p_legal_entity_id,r.id;
   end if;
   perform projects.finance_closure_guard(p_tenant_id,p_legal_entity_id,r.id);
   if r.current_plan_id is null or exists(select 1 from projects.plans where plans.project_id=r.id and status='pending')
    or exists(select 1 from projects.tasks q where q.plan_id=r.current_plan_id and coalesce((select z.progress from projects.task_progress z
     where z.project_id=r.id and z.plan_id=q.plan_id and z.task_id=q.id order by z.project_version desc limit 1),0)<10000)
    or exists(select 1 from projects.time_entries q where q.project_id=r.id and status in('draft','submitted','rejected'))
    or exists(select 1 from projects.billable_units q where q.project_id=r.id and status in('available','reserved')) then
    raise exception using errcode='55000',message='PROJECT_CLOSURE_IMPACT_REQUIRED';end if;
   update projects.resource_slots set active=false where resource_slots.project_id=r.id and active;
   update projects.register set version=version+1,status='closed' where register.id=r.id;
  elsif act='waive' then
   update projects.billable_units set status='waived' where billable_units.tenant_id=p_tenant_id and billable_units.legal_entity_id=p_legal_entity_id
    and billable_units.project_id=r.id and billable_units.id=(p_payload->>'unit_id')::uuid and status='available';
   if not found then raise exception using errcode='55000',message='PROJECT_UNIT_NOT_AVAILABLE';end if;
   insert into projects.unit_decisions(tenant_id,legal_entity_id,project_id,unit_id,decision,reason,actor_id)
   values(p_tenant_id,p_legal_entity_id,r.id,(p_payload->>'unit_id')::uuid,'waived',reason,auth.uid());
   update projects.register set version=version+1 where register.id=r.id;
  else
   if act<>'time_create' then
    select * into entry from projects.time_entries q where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.branch_id=p_branch_id
     and q.project_id=r.id and q.employee_id=project_work.employee_id and q.id=project_work.id for update;
    if entry.id is null then raise exception using errcode='P0002',message='PROJECT_TIME_NOT_FOUND';end if;
    before_state:=jsonb_build_object('id',entry.id,'version',entry.version,'status',entry.status,'revision_id',entry.current_revision_id);
    perform core.wave3_assert_expected_version(entry.version,p_expected_version,before_state);
    select * into revision from projects.time_revisions where time_revisions.id=entry.current_revision_id;
   elsif p_expected_version<>0 then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
   if act in('time_create','time_correct') then
    if act='time_correct' and entry.status not in('draft','rejected') then
     raise exception using errcode='55000',message='PROJECT_TIME_LINKED_IMPACT_REQUIRED';end if;
    select * into slot from projects.resource_slots q where q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.project_id=r.id
     and q.plan_id=r.current_plan_id and q.employee_id=project_work.employee_id and q.id=(p_payload->>'resource_slot_id')::uuid and q.active;
    if slot.id is null then raise exception using errcode='55000',message='PROJECT_APPROVED_RESOURCE_REQUIRED';end if;
    select * into c from people.work_calendar_versions where work_calendar_versions.id=slot.calendar_version_id;
    start_local:=(p_payload->>'start_local')::timestamp;end_local:=(p_payload->>'end_local')::timestamp;
    if start_local is null or end_local is null or extract(second from start_local)%1<>0 or extract(second from end_local)%1<>0 then
     raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
    start_utc:=people.resolve_local_instant(c.timezone,start_local,(p_payload->>'start_offset_seconds')::integer);
    end_utc:=people.resolve_local_instant(c.timezone,end_local,(p_payload->>'end_offset_seconds')::integer);
    if not(tstzrange(slot.start_utc,slot.end_utc,'[)') @> tstzrange(start_utc,end_utc,'[)')) then
     raise exception using errcode='55000',message='PROJECT_TIME_OUTSIDE_RESOURCE';end if;
    perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee_id,slot.calendar_version_id,start_local,end_local);
    breaks:=coalesce(p_payload->'breaks','[]');break_seconds:=people.work_break_seconds(start_utc,end_utc,breaks);
    payable:=extract(epoch from end_utc-start_utc)::bigint-break_seconds;attendance_claim:=(p_payload->>'attendance_claim_id')::uuid;
    if attendance_claim is not null and not exists(select 1 from people.work_claims q where q.id=attendance_claim and q.tenant_id=p_tenant_id
     and q.legal_entity_id=p_legal_entity_id and q.branch_id=p_branch_id and q.employee_id=project_work.employee_id and q.source_kind='attendance' and q.active
     and q.calendar_version_id=slot.calendar_version_id and tstzrange(q.start_utc,q.end_utc,'[)') @> tstzrange(start_utc,end_utc,'[)')) then
     raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
    amount:=projects.ratio(slot.bill_rate*1000000*payable,3600,r.precision);
    if act='time_create' then
     insert into projects.time_entries(id,tenant_id,legal_entity_id,branch_id,project_id,employee_id,current_revision_id,created_by)
     values(id,p_tenant_id,p_legal_entity_id,p_branch_id,r.id,employee_id,new_revision,auth.uid());
    else update projects.time_entries set version=version+1,current_revision_id=new_revision,status='draft',submitted_by=null where time_entries.id=entry.id;end if;
    insert into projects.time_revisions(id,tenant_id,legal_entity_id,project_id,entry_id,version,plan_id,task_id,resource_slot_id,
     start_local,end_local,start_offset_seconds,end_offset_seconds,start_utc,end_utc,breaks,payable_seconds,attendance_claim_id,bill_amount,digest,reason,supersedes_id,recorded_by)
    values(new_revision,p_tenant_id,p_legal_entity_id,r.id,id,case act when 'time_create' then 1 else entry.version+1 end,slot.plan_id,slot.task_id,slot.id,
     start_local,end_local,(p_payload->>'start_offset_seconds')::integer,(p_payload->>'end_offset_seconds')::integer,start_utc,end_utc,breaks,payable,
     attendance_claim,amount,encode(extensions.digest((p_payload||jsonb_build_object('revision_id',new_revision,'plan_id',slot.plan_id,'bill_amount',amount::text,'payable_seconds',payable))::text,'sha256'),'hex'),
     reason,case act when 'time_correct' then revision.id end,auth.uid());
   elsif act='time_submit' then
    if entry.status not in('draft','rejected') then raise exception using errcode='55000',message='PROJECT_TIME_STATE_INVALID';end if;
    update projects.time_entries set version=version+1,status='submitted',submitted_by=auth.uid() where time_entries.id=entry.id;
   elsif act in('time_approve','time_reject') then
    if entry.status<>'submitted' then raise exception using errcode='55000',message='PROJECT_TIME_STATE_INVALID';end if;
    if revision.recorded_by=auth.uid() or entry.submitted_by=auth.uid() then raise exception using errcode='42501',message='PROJECT_INDEPENDENT_APPROVAL_REQUIRED';end if;
    if act='time_approve' then
     select * into slot from projects.resource_slots q where q.id=revision.resource_slot_id and q.active and q.plan_id=r.current_plan_id;
     if slot.id is null then raise exception using errcode='55000',message='PROJECT_RESOURCE_CHANGED';end if;
     perform people.work_local_coverage(p_tenant_id,p_legal_entity_id,p_branch_id,employee_id,slot.calendar_version_id,revision.start_local,revision.end_local);
     perform people.consume_organization(p_tenant_id,p_legal_entity_id,p_branch_id,employee_id,'project_time',revision.id,
      revision.start_local::date,(revision.end_local-interval '1 microsecond')::date+1);
     claim:=revision.attendance_claim_id;
     begin
      if claim is null then claim:=people.make_work_claim(p_tenant_id,p_legal_entity_id,p_branch_id,employee_id,'project',revision.id,
       revision.start_utc,revision.end_utc,revision.breaks,slot.calendar_version_id,auth.uid());end if;
      if revision.attendance_claim_id is not null and not exists(select 1 from people.work_claims q where q.id=claim and q.source_kind='attendance' and q.active
       and q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.branch_id=p_branch_id and q.employee_id=project_work.employee_id
       and q.calendar_version_id=slot.calendar_version_id) then raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
      cursor_utc:=revision.start_utc;
      for x in select value from jsonb_array_elements(revision.breaks||jsonb_build_array(jsonb_build_object('start_utc',revision.end_utc,'end_utc',revision.end_utc))) loop
       break_start:=(x->>'start_utc')::timestamptz;break_end:=(x->>'end_utc')::timestamptz;
       if break_start>cursor_utc then
        link:=gen_random_uuid();allocation:=people.allocate_work(p_tenant_id,p_legal_entity_id,p_branch_id,employee_id,claim,'project',link,cursor_utc,break_start,auth.uid());
        insert into projects.time_allocations values(link,p_tenant_id,p_legal_entity_id,r.id,entry.id,revision.id,allocation,claim,revision.attendance_claim_id is null);
       end if;cursor_utc:=break_end;
      end loop;
     exception when exclusion_violation then raise exception using errcode='23514',message='WORK_INTERVAL_CONFLICT';end;
     select q.hourly_rate into cost_rate from projects.resource_costs q where q.resource_slot_id=slot.id and q.plan_id=slot.plan_id;
     if cost_rate is null then raise exception using errcode='55000',message='PROJECT_COST_BASIS_REQUIRED';end if;
     insert into projects.time_costs values(p_tenant_id,p_legal_entity_id,r.id,entry.id,revision.id,cost_rate,projects.ratio(cost_rate*1000000*revision.payable_seconds,3600,r.precision));
     insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount,payable_seconds)
     values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,r.id,p_branch_id,'time',revision.id,revision.version,revision.digest,revision.bill_amount,revision.payable_seconds);
    end if;
    update projects.time_entries set version=version+1,status=case act when 'time_approve' then 'approved' else 'rejected' end where time_entries.id=entry.id;
   else
    if entry.status<>'approved' or exists(select 1 from projects.billable_units q where q.source_kind='time' and q.source_id=revision.id and q.status<>'available') then
     raise exception using errcode='55000',message='PROJECT_TIME_LINKED_IMPACT_REQUIRED';end if;
    if exists(select 1 from projects.time_allocations a join people.work_input_seals s on s.claim_id=a.claim_id where a.revision_id=revision.id) then
     raise exception using errcode='55000',message='PAYROLL_INPUT_SEALED';end if;
    for allocation in select a.allocation_id from projects.time_allocations a where a.revision_id=revision.id order by a.id loop
     perform people.revoke_work_allocation(p_tenant_id,p_legal_entity_id,employee_id,allocation);
    end loop;
    for claim in select distinct a.claim_id from projects.time_allocations a where a.revision_id=revision.id and a.direct_claim order by a.claim_id loop
     perform people.revoke_work_claim(p_tenant_id,p_legal_entity_id,employee_id,claim);
    end loop;
    update projects.billable_units set status='cancelled' where source_kind='time' and source_id=revision.id;
    insert into projects.unit_decisions(tenant_id,legal_entity_id,project_id,unit_id,decision,reason,actor_id)
    select p_tenant_id,p_legal_entity_id,r.id,q.id,'cancelled',reason,auth.uid() from projects.billable_units q where q.source_kind='time' and q.source_id=revision.id;
    update projects.time_entries set version=version+1,status='cancelled' where time_entries.id=entry.id;
   end if;
   select current_revision_id,version into new_revision,total from projects.time_entries where time_entries.id=id;
   insert into projects.time_events(tenant_id,legal_entity_id,project_id,entry_id,revision_id,action,version,reason,actor_id,command_id)
   values(p_tenant_id,p_legal_entity_id,r.id,id,new_revision,act,total,reason,auth.uid(),p_command_id);
  end if;
 end if;
 -- Financial values and costing never enter generic audit, receipts, notifications or outbox payloads.
 if act like 'time_%' then select jsonb_build_object('id',q.id,'tenant_id',q.tenant_id,'legal_entity_id',q.legal_entity_id,'branch_id',q.branch_id,
  'project_id',q.project_id,'employee_id',q.employee_id,'version',q.version,'status',q.status,'revision_id',q.current_revision_id) into after_state from projects.time_entries q where q.id=id;
 else select jsonb_build_object('id',q.id,'tenant_id',q.tenant_id,'legal_entity_id',q.legal_entity_id,'branch_id',q.branch_id,
  'version',q.version,'status',q.status,'current_plan_id',q.current_plan_id) into after_state from projects.register q where q.id=id;end if;
 return core.wave3_finish_command(p_tenant_id,'projects.'||act,p_command_id,case when act like 'time_%' then 'projects.time' else 'projects.project' end,
  id,p_idempotency_key,hash,before_state,after_state,p_legal_entity_id,p_branch_id,p_request_id=>request);
end $$;
create index project_scope_idx on projects.register(tenant_id,legal_entity_id,branch_id,id);
create index project_customer_idx on projects.register(tenant_id,customer_id);
create index project_manager_idx on projects.register(tenant_id,legal_entity_id,manager_id);
create index project_creator_idx on projects.register(created_by);
create index plan_scope_idx on projects.plans(tenant_id,legal_entity_id,project_id,id);
create index plan_actor_idx on projects.plans(prepared_by);
create index task_scope_idx on projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id);
create index dependency_prerequisite_idx on projects.dependencies(plan_id,prerequisite_id);
create index slot_scope_idx on projects.resource_slots(tenant_id,legal_entity_id,project_id,plan_id,id);
create index slot_employee_idx on projects.resource_slots(tenant_id,legal_entity_id,employee_id);
create index slot_calendar_idx on projects.resource_slots(tenant_id,legal_entity_id,calendar_version_id);
create index decision_actor_idx on projects.plan_decisions(decided_by);
create index progress_scope_idx on projects.task_progress(tenant_id,legal_entity_id,project_id,plan_id,task_id,project_version desc);
create index progress_actor_idx on projects.task_progress(recorded_by);
create index project_time_scope_idx on projects.time_entries(tenant_id,legal_entity_id,branch_id,project_id,id);
create index project_time_employee_idx on projects.time_entries(tenant_id,legal_entity_id,employee_id);
create index project_time_creator_idx on projects.time_entries(created_by);
create index project_time_submitter_idx on projects.time_entries(submitted_by);
create index time_revision_slot_idx on projects.time_revisions(resource_slot_id);
create index time_revision_plan_idx on projects.time_revisions(plan_id,task_id);
create index time_revision_attendance_idx on projects.time_revisions(attendance_claim_id);
create index time_revision_supersedes_idx on projects.time_revisions(supersedes_id);
create index time_revision_actor_idx on projects.time_revisions(recorded_by);
create index time_allocation_revision_idx on projects.time_allocations(tenant_id,legal_entity_id,project_id,entry_id,revision_id);
create index time_allocation_claim_idx on projects.time_allocations(claim_id);
create index time_event_scope_idx on projects.time_events(tenant_id,legal_entity_id,project_id,entry_id,id);
create index time_event_actor_idx on projects.time_events(actor_id);
create index unit_decision_actor_idx on projects.unit_decisions(actor_id);
create index unit_decision_scope_idx on projects.unit_decisions(tenant_id,legal_entity_id,project_id,unit_id);
create index resource_cost_plan_idx on projects.resource_costs(tenant_id,legal_entity_id,project_id,plan_id,resource_slot_id);
create index time_cost_scope_idx on projects.time_costs(tenant_id,legal_entity_id,project_id,revision_id);
create index billable_scope_idx on projects.billable_units(tenant_id,legal_entity_id,project_id,status,id);
create index billable_branch_idx on projects.billable_units(tenant_id,legal_entity_id,branch_id,id);
create function projects.require_access(t uuid,e uuid,b uuid,cap text,w boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 if t is null or e is null or b is null or cap is null or cap not in('projects.view','projects.manage','projects.approve',
  'projects.cost.view','projects.cost.manage','projects.time.manage','projects.time.approve','projects.billing.manage') then
  raise exception using errcode='42501',message='PROJECT_SCOPE_DENIED';end if;
 perform core.wave3_require_scope(t,'projects.view',e,b);perform core.wave3_require_scope(t,cap,e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='module.projects' and p.enabled and
  ((s.status='trialing' and s.trial_ends_at>now()) or(s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>now())))) then
  raise exception using errcode='42501',message='PROJECT_ENTITLEMENT_REQUIRED';end if;
 if w and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='PROJECT_MFA_REQUIRED';end if;
end $$;
create function projects.text(p jsonb,max_length integer) returns text language plpgsql immutable set search_path='' as $$begin
 if jsonb_typeof(p) is distinct from 'string' or length(p#>>'{}') not between 1 and max_length
  or p#>>'{}'<>btrim(p#>>'{}') or p#>>'{}' ~ '[[:cntrl:]]' then
  raise exception using errcode='22023',message='PROJECT_TEXT_INVALID';end if;return p#>>'{}';end $$;
create function projects.amount(p jsonb) returns numeric language plpgsql immutable set search_path='' as $$begin
 if jsonb_typeof(p) is distinct from 'string' or p#>>'{}' !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then
  raise exception using errcode='22023',message='PROJECT_AMOUNT_INVALID';end if;return (p#>>'{}')::numeric;end $$;
create function projects.ratio(n numeric,d numeric,p_precision integer) returns numeric language plpgsql immutable set search_path='' as $$
declare q numeric;r numeric;divisor numeric;begin
 if n is null or d is null or p_precision is null or d<=0 or n<>trunc(n) or d<>trunc(d) or p_precision not between 0 and 6 then
  raise exception using errcode='22023',message='PROJECT_ROUNDING_INVALID';end if;
 divisor:=d*power(10::numeric,6-p_precision);q:=div(abs(n),divisor);r:=mod(abs(n),divisor);
 if r*2>divisor or(r*2=divisor and mod(q,2)=1) then q:=q+1;end if;
 return sign(n)*q*power(10::numeric,6-p_precision)/1000000;
end $$;
create function projects.task_owner_validate(t uuid,e uuid,b uuid,employee uuid,p_start date,p_end date)
returns jsonb language plpgsql stable set search_path='' as $$declare name text;begin
 if employee is null or p_start is null or p_end is null or p_end<=p_start then
  raise exception using errcode='22023',message='PROJECT_TASK_OWNER_REQUIRED';end if;
 select p.display_name into name from people.employees p where p.tenant_id=t and p.legal_entity_id=e and p.id=employee
 and exists(select 1 from people.employment_assignments a join people.employment_spells s on s.id=a.spell_id
  where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and a.employee_id=employee
  and daterange(a.start_date,a.end_date_exclusive,'[)') @> daterange(p_start,p_end,'[)')
  and daterange(s.start_date,s.end_date_exclusive,'[)') @> daterange(p_start,p_end,'[)'));
 if name is null then raise exception using errcode='55000',message='PROJECT_TASK_OWNER_COVERAGE_REQUIRED';end if;
 return jsonb_build_object('id',employee,'name',name);
end $$;
create function projects.slot_validate(t uuid,e uuid,b uuid,employee uuid,calendar uuid,start_local timestamp,end_local timestamp,
 start_offset integer,end_offset integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare c people.work_calendar_versions%rowtype;s timestamptz;z timestamptz;d date;pattern jsonb;x jsonb;start_min integer;end_min integer;matched boolean:=false;begin
 select * into c from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=calendar;
 if c.id is null then raise exception using errcode='P0002',message='PROJECT_CALENDAR_NOT_FOUND';end if;
 if start_local is null or end_local is null or extract(second from start_local)%1<>0 or extract(second from end_local)%1<>0 then
  raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
 s:=people.resolve_local_instant(c.timezone,start_local,start_offset);z:=people.resolve_local_instant(c.timezone,end_local,end_offset);
 perform people.work_local_coverage(t,e,b,employee,calendar,start_local,end_local);
 if z<=s or z-s>interval '24 hours' or extract(epoch from s)%1<>0 or extract(epoch from z)%1<>0 then
  raise exception using errcode='22023',message='PROJECT_CAPACITY_SLOT_INVALID';end if;
 -- A reservation must lie wholly in one calendar segment. Midnight holidays split overnight segments.
 for d in select (start_local::date-1+g)::date from generate_series(0,1) g loop
  for x in select value from jsonb_array_elements(c.weekly_intervals)
   where (value->>'day_of_week')::integer=extract(isodow from d)::integer loop
   if start_local>=d::timestamp+(x->>'start_minute')::integer*interval '1 minute'
    and end_local<=d::timestamp+((x->>'end_day_offset')::integer*1440+(x->>'end_minute')::integer)*interval '1 minute' then matched:=true;end if;
  end loop;
 end loop;
 if not matched or exists(select 1 from jsonb_array_elements(c.date_overrides) o where not(o->>'is_working_day')::boolean
  and (o->>'date')::date>=start_local::date and (o->>'date')::date<=(end_local-interval '1 microsecond')::date) then
  raise exception using errcode='55000',message='PROJECT_CAPACITY_OUTSIDE_CALENDAR';end if;
 return jsonb_build_object('start_utc',s,'end_utc',z,'planned_seconds',extract(epoch from z-s)::bigint);
end $$;
create function projects.summary(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',r.id,'tenant_id',r.tenant_id,'legal_entity_id',r.legal_entity_id,'branch_id',r.branch_id,
  'code',r.code,'name',r.name,'customer_id',r.customer_id,'customer_name',c.display_name,'manager_id',r.manager_id,'manager_name',m.display_name,
  'currency_code',r.currency_code,'precision',r.precision,'start_date',r.start_date,'end_date_exclusive',r.end_date_exclusive,
  'version',r.version,'status',r.status,'current_plan_id',r.current_plan_id)
 from projects.register r left join crm.parties c on c.tenant_id=r.tenant_id and c.id=r.customer_id
 join people.employees m on m.tenant_id=r.tenant_id and m.legal_entity_id=r.legal_entity_id and m.id=r.manager_id where r.id=p_id $$;
create function projects.time_summary(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',t.id,'tenant_id',t.tenant_id,'legal_entity_id',t.legal_entity_id,'branch_id',t.branch_id,
 'project_id',t.project_id,'employee_id',t.employee_id,'employee_name',m.display_name,'version',t.version,'status',t.status,
 'revision_id',r.id,'plan_id',r.plan_id,'task_id',r.task_id,'resource_slot_id',r.resource_slot_id,
 'start_local',to_char(r.start_local,'YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(r.end_local,'YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',r.start_offset_seconds,'end_offset_seconds',r.end_offset_seconds,
 'start_utc',to_char(r.start_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
 'end_utc',to_char(r.end_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'breaks',r.breaks,
 'payable_seconds',r.payable_seconds,'attendance_claim_id',r.attendance_claim_id,'bill_amount',r.bill_amount::text,'digest',r.digest,
 'reason',r.reason,'recorded_by',r.recorded_by)
 from projects.time_entries t join projects.time_revisions r on r.id=t.current_revision_id
 join people.employees m on m.id=t.employee_id and m.tenant_id=t.tenant_id and m.legal_entity_id=t.legal_entity_id where t.id=p_id $$;
create function api.projects_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability,p_capability<>'projects.view');
 return jsonb_build_object('actor_id',auth.uid(),'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
 'capability',p_capability,'authorized',true,'currency_code',(select currency_code from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
 'precision',(select rounding_scale from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id),
 'expense_evidence_provider',false,'supplier_bill_provider',false);
end $$;
create function api.projects_directory(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 select coalesce(jsonb_agg(projects.summary(q.id) order by q.id),'[]') into rows from(select id from projects.register
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after) order by id limit 50) q;
 return jsonb_build_object('rows',rows,'next_after',case when jsonb_array_length(rows)=50 then rows->49->>'id' end);
end $$;
create function api.projects_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,
 p_kind text,p_parent_id uuid default null,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_variable
declare r projects.register%rowtype;rows jsonb;plan uuid;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 if p_kind in('cost','resource_cost','time_cost') then perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.cost.view',true);end if;
 select * into r from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_project_id;
 if r.id is null then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 plan:=coalesce(p_parent_id,r.current_plan_id);
 if p_kind in('tasks','resources','cost','resource_cost') and not exists(select 1 from projects.plans where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id and id=plan) then
  raise exception using errcode='P0002',message='PROJECT_PLAN_NOT_FOUND';end if;
 if p_kind='plans' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'tenant_id',q.tenant_id,'legal_entity_id',q.legal_entity_id,'project_id',q.project_id,
   'version',q.version,'digest',q.basis_digest,'terms',q.terms,'reason',q.reason,'status',q.status,'prepared_by',q.prepared_by,'prepared_at',q.prepared_at,
   'decision',(select jsonb_build_object('decision',d.decision,'digest',d.digest,'reason',d.reason,'decided_by',d.decided_by,'decided_at',d.decided_at) from projects.plan_decisions d where d.plan_id=q.id)) order by q.id),'[]') into rows
   from(select * from projects.plans where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id and(p_parent_id is null or id=p_parent_id) and(p_after is null or id>p_after) order by id limit 50) q;
 elsif p_kind='tasks' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'project_id',q.project_id,'plan_id',q.plan_id,'name',q.name,'owner_id',q.owner_id,'owner_name',q.owner_name,'start_date',q.start_date,
   'end_date_exclusive',q.end_date_exclusive,'planned_seconds',q.planned_seconds,'dependencies',(select coalesce(jsonb_agg(d.prerequisite_id order by d.prerequisite_id),'[]') from projects.dependencies d where d.plan_id=q.plan_id and d.task_id=q.id),
   'progress',coalesce((select z.progress from projects.task_progress z where z.project_id=r.id and z.plan_id=q.plan_id and z.task_id=q.id order by z.project_version desc limit 1),0)) order by q.id),'[]') into rows
   from(select * from projects.tasks where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id and plan_id=plan and(p_after is null or id>p_after) order by id limit 50) q;
 elsif p_kind='resources' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'project_id',q.project_id,'plan_id',q.plan_id,'task_id',q.task_id,'employee_id',q.employee_id,
   'employee_name',(select display_name from people.employees e where e.id=q.employee_id and e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id),
   'calendar_version_id',q.calendar_version_id,'start_local',to_char(q.start_local,'YYYY-MM-DD"T"HH24:MI:SS'),
   'end_local',to_char(q.end_local,'YYYY-MM-DD"T"HH24:MI:SS'),'start_offset_seconds',q.start_offset_seconds,'end_offset_seconds',q.end_offset_seconds,
   'start_utc',to_char(q.start_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'end_utc',to_char(q.end_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
   'planned_seconds',q.planned_seconds,'bill_rate',q.bill_rate::text,'active',q.active) order by q.id),'[]') into rows
   from(select * from projects.resource_slots where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id and plan_id=plan and(p_after is null or id>p_after) order by id limit 50) q;
 elsif p_kind='cost' then
  select jsonb_build_array(jsonb_build_object('id',q.plan_id,'project_id',q.project_id,'plan_id',q.plan_id,'budget',q.budget::text)) into rows
  from projects.cost_basis q where q.plan_id=plan and q.tenant_id=p_tenant_id and q.legal_entity_id=p_legal_entity_id and q.project_id=r.id and(p_after is null or q.plan_id>p_after);
 elsif p_kind='resource_cost' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.resource_slot_id,'project_id',q.project_id,'plan_id',q.plan_id,'hourly_rate',q.hourly_rate::text) order by q.resource_slot_id),'[]') into rows
   from(select * from projects.resource_costs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id and plan_id=plan and(p_after is null or resource_slot_id>p_after) order by resource_slot_id limit 50) q;
 elsif p_kind='time' then
  select coalesce(jsonb_agg(projects.time_summary(q.id) order by q.id),'[]') into rows from(select id from projects.time_entries where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=r.id and(p_parent_id is null or id=p_parent_id) and(p_after is null or id>p_after) order by id limit 50) q;
 elsif p_kind='time_cost' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.revision_id,'project_id',q.project_id,'entry_id',q.entry_id,'revision_id',q.revision_id,
   'hourly_rate',q.hourly_rate::text,'amount',q.amount::text,'active',(select status='approved' and current_revision_id=q.revision_id from projects.time_entries t where t.id=q.entry_id)) order by q.revision_id),'[]') into rows
  from(select * from projects.time_costs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id
   and(p_after is null or revision_id>p_after) order by revision_id limit 50) q;
 elsif p_kind='units' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'project_id',q.project_id,'branch_id',q.branch_id,'source_kind',q.source_kind,
   'source_id',q.source_id,'source_version',q.source_version,'source_digest',q.source_digest,'amount',q.amount::text,
   'payable_seconds',q.payable_seconds,'status',q.status,'quantity','1.000000') order by q.id),'[]') into rows
  from(select * from projects.billable_units where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id and(p_after is null or id>p_after) order by id limit 50) q;
 elsif p_kind='time_events' then
  if not exists(select 1 from projects.time_entries where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=r.id and id=p_parent_id) then
   raise exception using errcode='P0002',message='PROJECT_TIME_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'project_id',q.project_id,'entry_id',q.entry_id,'revision_id',q.revision_id,'action',q.action,
   'version',q.version,'reason',q.reason,'actor_id',q.actor_id,'recorded_at',q.recorded_at) order by q.id),'[]') into rows from(select * from projects.time_events
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=r.id and entry_id=p_parent_id and(p_after is null or id>p_after) order by id limit 50) q;
 else raise exception using errcode='22023',message='PROJECT_DETAIL_KIND_INVALID';end if;
 rows:=coalesce(rows,'[]');return jsonb_build_object('project',projects.summary(r.id),'kind',p_kind,'rows',rows,'next_after',case when jsonb_array_length(rows)=50 then rows->49->>'id' end);
end $$;
create function api.projects_pickers(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 if p_kind='employees' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.display_name,'code',q.code,'version',q.version) order by q.id),'[]') into rows
  from(select * from people.employees e where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id and(p_after is null or e.id>p_after)
   and exists(select 1 from people.employment_assignments a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=e.id) order by e.id limit 50) q;
 elsif p_kind='customers' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.display_name,'code',q.code,'version',q.version) order by q.id),'[]') into rows
  from(select * from crm.parties where tenant_id=p_tenant_id and kind in('customer','both') and status='active' and(p_after is null or id>p_after) order by id limit 50) q;
 elsif p_kind='calendars' then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'code',q.code,'start_date',q.start_date,'end_date_exclusive',q.end_date_exclusive,'timezone',q.timezone) order by q.id),'[]') into rows
  from(select v.id,c.name,c.code,v.start_date,v.end_date_exclusive,v.timezone from people.work_calendar_versions v join people.work_calendars c on c.id=v.calendar_id
   where v.tenant_id=p_tenant_id and v.legal_entity_id=p_legal_entity_id and(p_after is null or v.id>p_after) order by v.id limit 50) q;
 else raise exception using errcode='22023',message='PROJECT_PICKER_KIND_INVALID';end if;
 return jsonb_build_object('rows',rows,'next_after',case when jsonb_array_length(rows)=50 then rows->49->>'id' end);
end $$;
create function api.projects_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_idempotency_key uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare r core.command_receipts%rowtype;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,projects.command_cap(p_action),true);
 if p_action='plan' then perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.cost.manage',true);end if;
 if p_action in('approve_plan','reject_plan') then perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.cost.view',true);end if;
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and actor_id=auth.uid() and idempotency_key=p_idempotency_key and command_name='projects.'||p_action;
 return case when r.id is null then null else jsonb_build_object('command_id',r.command_id,'idempotency_key',r.idempotency_key,'request_hash',r.request_hash,'response',r.response) end;
end $$;
revoke all on all functions in schema projects from public,anon,authenticated;
create function api.projects_calendar_candidates(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_version_id uuid,p_date date,p_minute integer,p_second integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare c people.work_calendar_versions%rowtype;l timestamp;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 select * into c from people.work_calendar_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_version_id;
 if c.id is null then raise exception using errcode='P0002',message='PROJECT_CALENDAR_NOT_FOUND';end if;
 if p_date is null or p_minute is null or p_minute not between 0 and 1439 or p_second is null or p_second not between 0 and 59 or p_date<c.start_date or p_date>=c.end_date_exclusive then
  raise exception using errcode='22023',message='PROJECT_CALENDAR_BOUNDARY_INVALID';end if;
 l:=p_date::timestamp+p_minute*interval '1 minute'+p_second*interval '1 second';
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'resolution',jsonb_build_object('calendar_version_id',c.id,'date',p_date,'minute',p_minute,'second',p_second,'timezone',c.timezone,
   'local_datetime',to_char(l,'YYYY-MM-DD"T"HH24:MI:SS'),'algorithm','pg-iana-roundtrip-v1','candidates',people.local_instant_candidates(c.timezone,l)));
end $$;
create function api.projects_attendance_claims(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_employee_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.time.manage',true);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'employee_id',q.employee_id,'calendar_version_id',q.calendar_version_id,
  'start_utc',to_char(q.start_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'end_utc',to_char(q.end_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'payable_seconds',q.payable_seconds) order by q.id),'[]') into rows
 from(select * from people.work_claims where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and employee_id=p_employee_id and source_kind='attendance' and active and(p_after is null or id>p_after) order by id limit 50) q;
 return jsonb_build_object('rows',rows,'next_after',case when jsonb_array_length(rows)=50 then rows->49->>'id' end);
end $$;
revoke all on function api.projects_calendar_candidates(uuid,uuid,uuid,uuid,date,integer,integer),api.projects_attendance_claims(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.projects_calendar_candidates(uuid,uuid,uuid,uuid,date,integer,integer),api.projects_attendance_claims(uuid,uuid,uuid,uuid,uuid) to authenticated;
revoke all on function api.projects_authorize(uuid,uuid,uuid,text),api.projects_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.projects_directory(uuid,uuid,uuid,uuid),api.projects_detail(uuid,uuid,uuid,uuid,text,uuid,uuid),api.projects_pickers(uuid,uuid,uuid,text,uuid),api.projects_own_receipt(uuid,uuid,uuid,uuid,text)
 from public,anon,authenticated;
grant execute on function api.projects_authorize(uuid,uuid,uuid,text),api.projects_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.projects_directory(uuid,uuid,uuid,uuid),api.projects_detail(uuid,uuid,uuid,uuid,text,uuid,uuid),api.projects_pickers(uuid,uuid,uuid,text,uuid),api.projects_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;

-- UNAPPLIED synthetic W4-05 finance candidate. No plans or roles receive grants.
-- Additive source support leaves immutable core migration definitions untouched.
do $$declare c record;begin
 for c in select conname from pg_constraint where conrelid='projects.billable_units'::regclass and contype='c' and pg_get_constraintdef(oid) like '%source_kind%' loop
  execute format('alter table projects.billable_units drop constraint %I',c.conname);
 end loop;
end $$;
alter table projects.billable_units add constraint billable_source_kind check(source_kind in('time','expense','milestone','service'));
alter table projects.billable_units add constraint billable_whole_seconds check((source_kind in('time','service'))=(payable_seconds is not null));
alter table projects.billable_units add column provider_source_id uuid;
alter table projects.billable_units add constraint billable_service_provider check((source_kind='service')=(provider_source_id is not null));
insert into core.permissions(code,module,description,privileged) values
 ('projects.expenses.manage','projects','Prepare project expense revisions',true),
 ('projects.expenses.approve','projects','Independently approve expenses',true),
 ('projects.expenses.post','projects','Post or reverse reimbursement obligations',true),
 ('projects.expenses.settle','projects','Record and reverse reimbursement settlement',true),
 ('projects.margin.view','projects','Read dated private cost and margin',true)
on conflict(code) do nothing;
create table projects.expenses(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 employee_id uuid not null,version bigint not null default 1 check(version between 1 and 9007199254740990),
 current_revision_id uuid not null,status text not null default 'draft' check(status in('draft','submitted','approved','rejected','posted','reversed','cancelled')),
 submitted_by uuid references auth.users(id),external_reference text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,project_id,id),unique(tenant_id,legal_entity_id,external_reference),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create table projects.expense_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,expense_id uuid not null,version bigint not null,
 service_date date not null,purpose text not null,evidence_reference text not null,evidence_documents jsonb not null default '[]' check(jsonb_typeof(evidence_documents)='array' and jsonb_array_length(evidence_documents)<=10),original_currency text not null references core.currencies(code),base_currency text not null references core.currencies(code),
 original_precision integer not null check(original_precision between 0 and 6),base_precision integer not null check(base_precision between 0 and 6),
 net numeric(20,6) not null check(net>=0),tax numeric(20,6) not null check(tax>=0),gross numeric(20,6) not null check(gross>0 and gross=net+tax),
 base_net numeric(20,6) not null check(base_net>=0),base_tax numeric(20,6) not null check(base_tax>=0),base_gross numeric(20,6) not null check(base_gross>0 and base_gross=base_net+base_tax),tax_rounding_residue numeric(20,6) not null,
 tax_definition_id uuid,tax_version bigint,tax_basis jsonb not null,no_tax_reason text,
 exchange_rate_id uuid,exchange_rate_version bigint,fx_numerator numeric not null check(fx_numerator>0 and fx_numerator=trunc(fx_numerator)),fx_denominator numeric not null check(fx_denominator>0 and fx_denominator=trunc(fx_denominator)),fx_basis jsonb not null,
 expense_account_id uuid not null,tax_account_id uuid,liability_account_id uuid not null,
 bill_amount numeric(20,6) not null check(bill_amount>=0),billable boolean not null,
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),reason text not null,recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 supersedes_id uuid references projects.expense_revisions(id),unique(expense_id,version),unique(tenant_id,legal_entity_id,project_id,expense_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,expense_id) references projects.expenses(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,expense_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,tax_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,liability_account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
alter table projects.expenses add foreign key(tenant_id,legal_entity_id,project_id,id,current_revision_id)
 references projects.expense_revisions(tenant_id,legal_entity_id,project_id,expense_id,id) deferrable initially deferred;
create table projects.expense_allocations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,expense_id uuid not null,revision_id uuid not null,
 plan_id uuid not null,task_id uuid not null,ordinal integer not null check(ordinal between 1 and 50),weight bigint not null check(weight between 1 and 9007199254740990),amount numeric(20,6) not null check(amount>=0),
 unique(revision_id,ordinal),unique(revision_id,task_id),
 foreign key(tenant_id,legal_entity_id,project_id,expense_id,revision_id) references projects.expense_revisions(tenant_id,legal_entity_id,project_id,expense_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,task_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id)
);
create table projects.expense_decisions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,expense_id uuid not null,revision_id uuid not null,
 decision text not null check(decision in('approved','rejected')),digest text not null,reason text not null,actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(revision_id),foreign key(expense_id) references projects.expenses(id),foreign key(revision_id) references projects.expense_revisions(id)
);
create table projects.expense_ownership(
 expense_id uuid primary key references projects.expenses(id),tenant_id uuid not null,legal_entity_id uuid not null,revision_id uuid not null references projects.expense_revisions(id),
 route text not null check(route='reimbursement'),claimed_by uuid not null references auth.users(id),claimed_at timestamptz not null default clock_timestamp()
);
create table projects.reimbursements(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,expense_id uuid not null unique references projects.expenses(id),
 revision_id uuid not null references projects.expense_revisions(id),currency_code text not null,amount numeric(20,6) not null check(amount>0),account_id uuid not null,
 posting_date date not null,journal_id uuid not null references finance.journal_entries(id),recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
create table projects.reimbursement_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,obligation_id uuid not null references projects.reimbursements(id),
 kind text not null check(kind in('issue','settle','settlement_reverse','expense_reverse')),amount numeric(20,6) not null,source_id uuid not null,
 journal_id uuid not null references finance.journal_entries(id),posting_date date not null,reversal_of uuid unique references projects.reimbursement_effects(id),recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(obligation_id,kind,source_id)
);
create table projects.expense_settlements(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,obligation_id uuid not null references projects.reimbursements(id),
 posting_date date not null,amount numeric(20,6) not null check(amount>0),bank_id uuid not null,bank_version bigint not null,bank_account_id uuid not null,evidence_reference text not null,
 journal_id uuid not null references finance.journal_entries(id),recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp()
);
create table projects.billing_batches(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 invoice_id uuid not null unique references sales.sales_invoices(id),version bigint not null default 1,status text not null default 'prepared' check(status in('prepared','posted','cancelled')),
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 posted_at timestamptz,cancelled_at timestamptz,unique(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id)
);
create table projects.billing_links(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,batch_id uuid not null,unit_id uuid not null references projects.billable_units(id),
 invoice_line_id uuid not null,source_version bigint not null,source_digest text not null,amount numeric(20,6) not null,product_id uuid not null,product_version bigint not null,
 tax_definition_id uuid,tax_version bigint,line_basis jsonb not null,
 unique(batch_id,unit_id),unique(invoice_line_id),
 foreign key(tenant_id,legal_entity_id,project_id,batch_id) references projects.billing_batches(tenant_id,legal_entity_id,project_id,id)
);
-- Reservation authority is the source row status under locks, not a caller field.
create table projects.billing_intents(
 invoice_id uuid primary key references sales.sales_invoices(id),tenant_id uuid not null,legal_entity_id uuid not null,
 transaction_id bigint not null,actor_id uuid not null references auth.users(id)
);
create table projects.finance_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 aggregate_id uuid not null,action text not null,version bigint not null,reason text not null,actor_id uuid not null references auth.users(id),command_id uuid not null,recorded_at timestamptz not null default clock_timestamp(),unique(tenant_id,command_id)
);
do $$declare n text;begin
 foreach n in array array['expenses','expense_revisions','expense_allocations','expense_decisions','expense_ownership','reimbursements','reimbursement_effects','expense_settlements','billing_batches','billing_links','billing_intents','finance_events'] loop
  execute format('alter table projects.%I enable row level security',n);execute format('alter table projects.%I force row level security',n);
  execute format('revoke all on projects.%I from public,anon,authenticated',n);
  if n not in('expenses','billing_batches','billing_intents') then execute format('create trigger immutable before update or delete on projects.%I for each row execute function projects.immutable()',n);end if;
 end loop;end $$;
create index expense_scope_idx on projects.expenses(tenant_id,legal_entity_id,branch_id,project_id,id);
create index expense_revision_scope_idx on projects.expense_revisions(tenant_id,legal_entity_id,project_id,recorded_at,id);
create index reimbursement_scope_idx on projects.reimbursements(tenant_id,legal_entity_id,branch_id,project_id,id);
create index reimbursement_effect_scope_idx on projects.reimbursement_effects(obligation_id,posting_date,recorded_at);
create index billing_scope_idx on projects.billing_batches(tenant_id,legal_entity_id,branch_id,project_id,id);
create index billing_link_source_idx on projects.billing_links(unit_id,batch_id);
create index finance_event_scope_idx on projects.finance_events(tenant_id,legal_entity_id,branch_id,project_id,id);
create table projects.service_cost_revisions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 provider_source_id uuid not null,source_revision_id uuid not null,source_version bigint not null check(source_version>0),source_digest text not null check(source_digest~'^[a-f0-9]{64}$'),
 currency_code text not null,precision integer not null check(precision between 0 and 6),service_date date not null,payable_seconds bigint not null check(payable_seconds>=0),
 hourly_cost numeric(20,6) not null check(hourly_cost>=0),amount numeric(20,6) not null check(amount>=0),status text not null check(status in('approved','cancelled')),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,provider_source_id,source_version),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id)
);
alter table projects.service_cost_revisions enable row level security;alter table projects.service_cost_revisions force row level security;
revoke all on projects.service_cost_revisions from public,anon,authenticated,service_role;
create trigger immutable before update or delete on projects.service_cost_revisions for each row execute function projects.immutable();
create index service_cost_scope_idx on projects.service_cost_revisions(tenant_id,legal_entity_id,branch_id,project_id,id);
create index service_cost_asof_idx on projects.service_cost_revisions(project_id,provider_source_id,source_version desc,recorded_at);
-- Provider-only: financial import captures internal cost without putting it in
-- the billing source response. Linked corrections call this after their new
-- immutable revision and effective pointer are stored in the same transaction.
create function projects.service_payroll_cost_impact(t uuid,e uuid,b uuid,labor uuid,revision uuid) returns void
language plpgsql security definer set search_path='' as $$
declare project uuid;source jsonb;old projects.service_cost_revisions%rowtype;currency text;cost numeric;rate numeric;seconds bigint;
 service_date date;timezone text;status text;version bigint;digest text;precision integer;begin
 select u.project_id into project from projects.billable_units u where u.tenant_id=t and u.legal_entity_id=e and u.branch_id=b
  and u.source_kind='service' and u.provider_source_id=labor order by u.id limit 1;
 if project is null then return;end if;
 if to_regprocedure('service.snapshot(text,uuid)') is null then raise exception using errcode='55000',message='PROJECT_SERVICE_COST_PROVIDER_REQUIRED';end if;
 execute 'select service.snapshot(''labor'',$1)' into source using labor;
 if source is null or source->>'tenant_id' is distinct from t::text or source->>'legal_entity_id' is distinct from e::text
  or source->>'branch_id' is distinct from b::text or coalesce(source->>'current_revision_id',source->>'id') is distinct from revision::text then
  raise exception using errcode='40001',message='PROJECT_SERVICE_SOURCE_CONFLICT';end if;
 select r.currency_code,r.precision into currency,precision from projects.register r where r.id=project;
 if source->>'currency_code' is distinct from currency or(source->>'precision')::integer is distinct from precision then
  raise exception using errcode='22023',message='PROJECT_SERVICE_COST_BASIS_INVALID';end if;
 status:=source->>'status';version:=(source->>'version')::bigint;digest:=source->>'digest';
 if status not in('approved','cancelled') or version is null or version<1 or digest is null or digest!~'^[a-f0-9]{64}$' then
  raise exception using errcode='22023',message='PROJECT_SERVICE_COST_BASIS_INVALID';end if;
 rate:=projects.amount(source->'hourly_cost');seconds:=case when status='cancelled' then 0 else(source->>'seconds')::bigint end;
 cost:=case when status='cancelled' then 0 else projects.amount(source->'amount') end;
 if seconds is null or seconds not between 0 and 2678400 or cost<>projects.ratio(rate*1000000*seconds,3600,precision) then
  raise exception using errcode='22023',message='PROJECT_SERVICE_COST_BASIS_INVALID';end if;
 if source->>'start_local' is not null then service_date:=(source->>'start_local')::timestamp::date;
 else select c.timezone into timezone from people.work_calendar_versions c where c.id=(source->>'calendar_version_id')::uuid;
  service_date:=((source->>'start_utc')::timestamptz at time zone timezone)::date;end if;
 if service_date is null then raise exception using errcode='22023',message='PROJECT_SERVICE_COST_BASIS_INVALID';end if;
 select * into old from projects.service_cost_revisions x where x.tenant_id=t and x.legal_entity_id=e and x.provider_source_id=labor and x.source_version=version;
 if old.id is not null then
  if old.project_id<>project or old.source_revision_id<>revision or old.source_digest<>digest or old.amount<>cost or old.payable_seconds<>seconds or old.status<>status
   or old.hourly_cost<>rate or old.currency_code<>currency or old.precision<>precision or old.service_date<>service_date then
   raise exception using errcode='40001',message='PROJECT_SERVICE_COST_SOURCE_CONFLICT';end if;return;end if;
 insert into projects.service_cost_revisions(tenant_id,legal_entity_id,branch_id,project_id,provider_source_id,source_revision_id,source_version,source_digest,currency_code,precision,service_date,payable_seconds,hourly_cost,amount,status,recorded_by)
 values(t,e,b,project,labor,revision,version,digest,currency,precision,service_date,seconds,rate,cost,status,auth.uid());
 if status='cancelled' then update projects.billable_units u set status='cancelled' where u.tenant_id=t and u.legal_entity_id=e and u.provider_source_id=labor and u.source_kind='service' and u.status='available';end if;
end $$;
create function projects.milestone_terms(t uuid,e uuid,b uuid,u projects.billable_units) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare terms jsonb;begin
 if u.source_kind<>'milestone' then return '{}'::jsonb;end if;
 if to_regprocedure('projects.milestone_billing_terms(uuid,uuid,uuid,uuid)') is null then raise exception using errcode='55000',message='PROJECT_MILESTONE_PROVIDER_REQUIRED';end if;
 execute 'select projects.milestone_billing_terms($1,$2,$3,$4)' into terms using t,e,b,u.source_id;
 if terms is null or jsonb_typeof(terms)<>'object' or not(terms ?& array['payment_due_days','payment_terms','customer_id','currency_code','amount','source_version','digest'])
  or exists(select 1 from jsonb_object_keys(terms) k where k<>all(array['payment_due_days','payment_terms','customer_id','currency_code','amount','source_version','digest']))
  or jsonb_typeof(terms->'payment_due_days') is distinct from 'number' or terms->>'payment_due_days'!~'^[0-9]+$'
  or(terms->>'payment_due_days')::numeric not between 0 and 365 then raise exception using errcode='22023',message='PROJECT_MILESTONE_TERMS_INVALID';end if;
 perform projects.text(terms->'payment_terms',500);
 if(terms->>'source_version')::bigint is distinct from u.source_version or terms->>'digest' is distinct from u.source_digest or projects.amount(terms->'amount') is distinct from u.amount
  or not exists(select 1 from projects.register r where r.id=u.project_id and r.tenant_id=t and r.legal_entity_id=e and r.branch_id=b
   and r.customer_id::text=terms->>'customer_id' and r.currency_code=terms->>'currency_code') then raise exception using errcode='40001',message='PROJECT_MILESTONE_SOURCE_CONFLICT';end if;
 return terms;
end $$;
create function projects.finance_access(t uuid,e uuid,b uuid,cap text,w boolean default true) returns void language plpgsql security definer set search_path='' as $$begin
 perform projects.require_access(t,e,b,'projects.view',w);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='module.finance' and p.enabled and
  ((s.status='trialing' and s.trial_ends_at>now()) or(s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>now())))) then
  raise exception using errcode='42501',message='PROJECT_FINANCE_ENTITLEMENT_REQUIRED';end if;
 if cap not in('projects.cost.view','projects.expenses.manage','projects.expenses.approve','projects.expenses.post','projects.expenses.settle','projects.billing.manage','projects.margin.view') then raise exception using errcode='42501',message='PROJECT_FINANCE_SCOPE_DENIED';end if;
 perform core.wave3_require_scope(t,cap,e,b);
 if cap<>'projects.billing.manage' then perform core.wave3_require_scope(t,'projects.cost.view',e,b);end if;
end $$;
create function projects.finance_cap(act text) returns text language sql immutable set search_path='' as $$
 select case when act in('expense_create','expense_correct','expense_submit','expense_cancel') then 'projects.expenses.manage'
 when act in('expense_approve','expense_reject') then 'projects.expenses.approve'
 when act in('expense_post','expense_reverse') then 'projects.expenses.post'
 when act in('settle','settlement_reverse') then 'projects.expenses.settle'
 when act in('service_source','billing_prepare','billing_submit','billing_decide','billing_post','billing_cancel') then 'projects.billing.manage' end $$;
create function projects.expense_proofs(t uuid,e uuid,b uuid,p uuid,x uuid,proofs jsonb,mode text) returns jsonb
language plpgsql security definer set search_path='' as $$declare canonical jsonb;begin
 if mode not in('freeze','read','decision') or jsonb_typeof(proofs) is distinct from 'array' or jsonb_array_length(proofs)>10 then
  raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';end if;
 if to_regprocedure('projects.expense_evidence_assert(uuid,uuid,uuid,uuid,uuid,jsonb,text)') is null then
  if jsonb_array_length(proofs)>0 then raise exception using errcode='55000',message='PROJECT_ATTACHMENT_PROVIDER_REQUIRED';end if;
  return '[]'::jsonb;
 end if;
 execute 'select projects.expense_evidence_assert($1,$2,$3,$4,$5,$6,$7)' into canonical using t,e,b,p,x,proofs,mode;
 if canonical is null or jsonb_typeof(canonical) is distinct from 'array' or jsonb_array_length(canonical)<>jsonb_array_length(proofs) then
  raise exception using errcode='55000',message='PROJECT_ATTACHMENT_PROVIDER_INVALID';end if;
 return canonical;
end $$;
create function projects.expense_summary(p uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',x.id,'tenant_id',x.tenant_id,'legal_entity_id',x.legal_entity_id,'branch_id',x.branch_id,'project_id',x.project_id,'employee_id',x.employee_id,
 'version',x.version,'status',x.status,'revision_id',x.current_revision_id) from projects.expenses x where id=p $$;
create function projects.finance_account(t uuid,e uuid,a uuid,kind text,c text) returns void language plpgsql security definer set search_path='' as $$begin
 perform finance.flow_account(t,e,a,kind,c);end $$;
create function projects.linked_invoice_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare invoice uuid;linked boolean;begin
 invoice:=(to_jsonb(old)->>case when tg_table_name='sales_invoices' then 'id' else 'document_id' end)::uuid;
 select exists(select 1 from projects.billing_batches where invoice_id=invoice) into linked;
 if not linked then return case when tg_op='DELETE' then old else new end;end if;
 if tg_table_name<>'sales_invoices' or tg_op='DELETE' then raise exception using errcode='55000',message='PROJECT_LINKED_INVOICE_IMMUTABLE';end if;
 if (to_jsonb(new)-array['status','version','submitted_by','submitted_at','approved_by','approved_at','posted_by','posted_at','cancelled_by','cancelled_at','updated_by','updated_at','workflow_snapshot','approval_request_id','document_number','request_id','command_id','correlation_id','client_timestamp'])
  is distinct from (to_jsonb(old)-array['status','version','submitted_by','submitted_at','approved_by','approved_at','posted_by','posted_at','cancelled_by','cancelled_at','updated_by','updated_at','workflow_snapshot','approval_request_id','document_number','request_id','command_id','correlation_id','client_timestamp']) then raise exception using errcode='55000',message='PROJECT_LINKED_INVOICE_IMMUTABLE';end if;
 if new.status is distinct from old.status and not exists(select 1 from projects.billing_intents where invoice_id=invoice and transaction_id=txid_current() and actor_id=auth.uid() and tenant_id=old.tenant_id and legal_entity_id=old.legal_entity_id) then raise exception using errcode='42501',message='PROJECT_BILLING_INTENT_REQUIRED';end if;
 return new;end $$;
create trigger project_link_guard before update or delete on sales.sales_invoices for each row execute function projects.linked_invoice_guard();
create trigger project_line_guard before update or delete on sales.sales_invoice_lines for each row execute function projects.linked_invoice_guard();
create function projects.linked_invoice_insert_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from projects.billing_batches where invoice_id=new.document_id) then raise exception using errcode='55000',message='PROJECT_LINKED_INVOICE_IMMUTABLE';end if;return new;end $$;
create trigger project_line_insert_guard before insert on sales.sales_invoice_lines for each row execute function projects.linked_invoice_insert_guard();
create function api.projects_finance_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare act text:=p_payload->>'action';id uuid:=(p_payload->>'id')::uuid;project uuid:=(p_payload->>'project_id')::uuid;reason text;hash text;replay jsonb;
 r projects.register%rowtype;x projects.expenses%rowtype;v projects.expense_revisions%rowtype;fx finance.exchange_rates%rowtype;taxdef finance.tax_definitions%rowtype;
 o projects.reimbursements%rowtype;s projects.expense_settlements%rowtype;b projects.billing_batches%rowtype;u projects.billable_units%rowtype;product inventory.products%rowtype;bank finance.cash_bank_accounts%rowtype;
 allowed text[];new_revision uuid:=gen_random_uuid();base text;scale integer;original_scale integer;net numeric;tax numeric;gross numeric;base_net numeric;base_tax numeric;base_gross numeric;bill numeric;ratio_n numeric:=10000000000;ratio_d numeric:=10000000000;
 fxdata jsonb;taxdata jsonb:='{}';allocation jsonb;weight_total numeric;weight_sum numeric:=0;allocated numeric:=0;part numeric;ord integer:=0;digest text;proofs jsonb:='[]';proof_revision uuid;proof_mode text;
 lines jsonb:='[]';doc jsonb;answer jsonb;outcome jsonb;before_state jsonb:='{}';journal uuid;request uuid:=gen_random_uuid();posting_date date;amount numeric;outstanding numeric;invoice uuid;invoice_version bigint;unit_ids uuid[];line uuid;service_ids uuid[];service_employees uuid[];
begin
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>65536 or id is null or project is null or p_command_id is null or p_idempotency_key is null or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 then raise exception using errcode='22023',message='PROJECT_FINANCE_COMMAND_INVALID';end if;
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,projects.finance_cap(act));reason:=projects.text(p_payload->'reason',1000);
 allowed:=case when act in('expense_create','expense_correct') then array['action','id','project_id','employee_id','external_reference','service_date','purpose','evidence_reference','evidence_documents','original_currency','original_precision','net','tax','gross','tax_definition_id','tax_version','no_tax_reason','exchange_rate_id','exchange_rate_version','expense_account_id','tax_account_id','liability_account_id','billable','bill_amount','allocations','reason']
 when act in('expense_approve','expense_reject') then array['action','id','project_id','digest','reason']
 when act in('expense_post','expense_reverse') then array['action','id','project_id','posting_date','reason']
 when act='settle' then array['action','id','project_id','obligation_id','posting_date','amount','bank_id','bank_version','evidence_reference','reason']
 when act='settlement_reverse' then array['action','id','project_id','posting_date','reason']
 when act='service_source' then array['action','id','project_id','service_source_id','source_version','source_digest','reason']
 when act='billing_prepare' then array['action','id','project_id','invoice_id','document_date','due_date','exchange_rate_id','units','reason']
 when act in('billing_submit','billing_post','billing_cancel') then array['action','id','project_id','invoice_version','reason']
 when act='billing_decide' then array['action','id','project_id','invoice_version','decision','reason']
 else array['action','id','project_id','reason'] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then raise exception using errcode='22023',message='PROJECT_FINANCE_FIELDS_INVALID';end if;
 -- Shared provider lock order: payroll -> projects -> service advisories,
 -- then sorted employees, tickets, work orders, labor and project source rows.
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 -- Financial evidence is current authority and active immutable content, even
 -- for a confirmed replay. Check documents before employee/project source rows.
 if act like 'expense_%' then
  if act<>'expense_create' then
   select (cr.response#>>'{entity,revision_id}')::uuid into proof_revision from core.command_receipts cr
    where cr.tenant_id=p_tenant_id and cr.actor_id=auth.uid() and cr.command_name='projects.finance.'||act and cr.command_id=p_command_id;
   if proof_revision is null then select xx.current_revision_id into proof_revision from projects.expenses xx where xx.tenant_id=p_tenant_id and xx.legal_entity_id=p_legal_entity_id and xx.branch_id=p_branch_id and xx.project_id=project and xx.id=id;end if;
   select * into v from projects.expense_revisions vv where vv.id=proof_revision and vv.tenant_id=p_tenant_id and vv.legal_entity_id=p_legal_entity_id and vv.project_id=project and vv.expense_id=id;
   if v.id is not null then
    proof_mode:=case when act in('expense_submit','expense_approve','expense_post') then 'decision' else 'read' end;
    perform projects.expense_proofs(p_tenant_id,p_legal_entity_id,p_branch_id,project,id,v.evidence_documents,proof_mode);
   end if;
  end if;
  if act in('expense_create','expense_correct') then proofs:=projects.expense_proofs(p_tenant_id,p_legal_entity_id,p_branch_id,project,id,coalesce(p_payload->'evidence_documents','[]'::jsonb),'freeze');end if;
 end if;
 hash:=core.wave3_request_hash('projects.finance.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'projects.finance.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 if act='service_source' then service_ids:=array[(p_payload->>'service_source_id')::uuid];
 elsif act='billing_prepare' then select array_agg(z.provider_source_id order by z.provider_source_id) into service_ids from projects.billable_units z where z.tenant_id=p_tenant_id and z.legal_entity_id=p_legal_entity_id and z.branch_id=p_branch_id and z.project_id=project and z.source_kind='service' and z.id in(select(value->>'unit_id')::uuid from jsonb_array_elements(p_payload->'units'));
 elsif act='billing_post' then select array_agg(z.provider_source_id order by z.provider_source_id) into service_ids from projects.billable_units z join projects.billing_links bl on bl.unit_id=z.id where bl.batch_id=id and z.tenant_id=p_tenant_id and z.legal_entity_id=p_legal_entity_id and z.branch_id=p_branch_id and z.project_id=project and z.source_kind='service';end if;
 if cardinality(service_ids)>0 then
  if to_regprocedure('service.billing_source(uuid,uuid,uuid,uuid)') is null then raise exception using errcode='55000',message='PROJECT_SERVICE_BILLING_PROVIDER_REQUIRED';end if;
  execute 'select array_agg(distinct employee_id order by employee_id) from service.labor where tenant_id=$1 and legal_entity_id=$2 and branch_id=$3 and id=any($4)' into service_employees using p_tenant_id,p_legal_entity_id,p_branch_id,service_ids;
  perform employees.id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employees.id=any(service_employees) order by employees.id for update;
  execute 'select t.id from service.tickets t where t.id in(select w.ticket_id from service.work_orders w join service.labor l on l.order_id=w.id where l.id=any($1)) order by t.id for update' using service_ids;
  execute 'select w.id from service.work_orders w where w.id in(select l.order_id from service.labor l where l.id=any($1)) order by w.id for update' using service_ids;
  execute 'select l.id from service.labor l where l.id=any($1) order by l.id for update' using service_ids;
 end if;
 -- Employee coverage is acquired before the project row, matching planning/time.
 if act in('expense_create','expense_correct') then
  perform employees.id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employees.id=(p_payload->>'employee_id')::uuid for update;
  if not found then raise exception using errcode='P0002',message='PROJECT_EXPENSE_EMPLOYEE_NOT_FOUND';end if;
 end if;
 select * into r from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and register.id=project for update;
 if r.id is null then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 if r.status<>'open' then raise exception using errcode='55000',message='PROJECT_CLOSED';end if;
 if act like 'expense_%' then
  select * into x from projects.expenses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=project and expenses.id=id for update;
  if act='expense_create' then
   if x.id is not null or p_expected_version<>0 then raise exception using errcode='40001',message='PROJECT_FINANCE_VERSION_CONFLICT';end if;
  else
   if x.id is null then raise exception using errcode='P0002',message='PROJECT_EXPENSE_NOT_FOUND';end if;
   if x.version<>p_expected_version then raise exception using errcode='40001',message='PROJECT_FINANCE_VERSION_CONFLICT';end if;
   before_state:=projects.expense_summary(id);select * into v from projects.expense_revisions where expense_revisions.id=x.current_revision_id;
  end if;
  if act in('expense_create','expense_correct') then
   if act='expense_correct' and (x.status not in('draft','rejected') or x.employee_id<>(p_payload->>'employee_id')::uuid or x.external_reference<>p_payload->>'external_reference') then raise exception using errcode='55000',message='PROJECT_EXPENSE_CORRECTION_IMPACT_REQUIRED';end if;
   if r.current_plan_id is null then raise exception using errcode='55000',message='PROJECT_PLAN_REQUIRED';end if;
   posting_date:=(p_payload->>'service_date')::date;
   if posting_date<r.start_date or posting_date>=r.end_date_exclusive or not exists(select 1 from people.employment_assignments a join people.employment_spells sp on sp.id=a.spell_id where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=(p_payload->>'employee_id')::uuid and daterange(a.start_date,a.end_date_exclusive,'[)') @> posting_date and daterange(sp.start_date,sp.end_date_exclusive,'[)') @> posting_date) then raise exception using errcode='55000',message='PROJECT_EXPENSE_EMPLOYEE_COVERAGE_REQUIRED';end if;
   perform projects.text(p_payload->'purpose',500);perform projects.text(p_payload->'evidence_reference',160);perform projects.text(p_payload->'external_reference',160);
   if p_payload->>'evidence_reference' ~* 'https?://|file:|[\\/]' then raise exception using errcode='22023',message='PROJECT_ATTACHMENT_PROVIDER_REQUIRED';end if;
   select currency_code,rounding_scale into base,scale from core.legal_entities where tenant_id=p_tenant_id and legal_entities.id=p_legal_entity_id;
   original_scale:=(p_payload->>'original_precision')::integer;
   -- Entity/project precision is the explicit synthetic source policy; no inferred foreign currency precision.
   if original_scale<>scale then raise exception using errcode='22023',message='PROJECT_EXPENSE_PRECISION_INVALID';end if;
   net:=projects.amount(p_payload->'net');tax:=projects.amount(p_payload->'tax');gross:=projects.amount(p_payload->'gross');bill:=projects.amount(p_payload->'bill_amount');
   if net+tax<>gross or gross<=0 or net<>round(net,scale) or tax<>round(tax,scale) or gross<>round(gross,scale) or bill<>round(bill,r.precision) or jsonb_typeof(p_payload->'billable') is distinct from 'boolean' or(not(p_payload->>'billable')::boolean and bill<>0) then raise exception using errcode='22023',message='PROJECT_EXPENSE_CONSERVATION_INVALID';end if;
   fxdata:=finance.flow_rate(p_tenant_id,p_legal_entity_id,p_payload->>'original_currency',posting_date,(p_payload->>'exchange_rate_id')::uuid);
   if p_payload->>'original_currency'<>base then
    select * into fx from finance.exchange_rates where exchange_rates.id=(p_payload->>'exchange_rate_id')::uuid for share;
    if fx.version is distinct from(p_payload->>'exchange_rate_version')::bigint then raise exception using errcode='40001',message='PROJECT_EXCHANGE_RATE_VERSION_CONFLICT';end if;
    ratio_n:=fx.rate*10000000000;if ratio_n<>trunc(ratio_n) then raise exception using errcode='55000',message='PROJECT_EXCHANGE_RATE_PRECISION_UNSUPPORTED';end if;
   elsif p_payload->>'exchange_rate_version' is not null then raise exception using errcode='22023',message='PROJECT_EXCHANGE_RATE_INVALID';end if;
   base_gross:=projects.ratio(gross*1000000*ratio_n,ratio_d,scale);base_net:=projects.ratio(net*1000000*ratio_n,ratio_d,scale);base_tax:=base_gross-base_net;
   if base_gross<=0 then raise exception using errcode='22023',message='PROJECT_EXPENSE_BELOW_PRECISION';end if;
   if p_payload->>'tax_definition_id' is null then
    if tax<>0 or p_payload->>'tax_version' is not null then raise exception using errcode='22023',message='PROJECT_EXPENSE_TAX_INVALID';end if;perform projects.text(p_payload->'no_tax_reason',1000);
   else
    select * into taxdef from finance.tax_definitions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and tax_definitions.id=(p_payload->>'tax_definition_id')::uuid and status='active' and kind in('input','zero','exempt') and posting_date>=valid_from and(valid_to is null or posting_date<=valid_to) for share;
    if taxdef.id is null or taxdef.version is distinct from(p_payload->>'tax_version')::bigint or p_payload->>'no_tax_reason' is not null or tax<>round(case when taxdef.inclusive then gross*taxdef.rate/(100+taxdef.rate) else net*taxdef.rate/100 end,scale) then raise exception using errcode='40001',message='PROJECT_EXPENSE_TAX_VERSION_INVALID';end if;
    taxdata:=jsonb_build_object('id',taxdef.id,'version',taxdef.version,'name',taxdef.name,'rate',taxdef.rate::text,'kind',taxdef.kind,'inclusive',taxdef.inclusive);
   end if;
   perform projects.finance_account(p_tenant_id,p_legal_entity_id,(p_payload->>'expense_account_id')::uuid,'expense',base);
   perform projects.finance_account(p_tenant_id,p_legal_entity_id,(p_payload->>'liability_account_id')::uuid,'liability',base);
   if base_tax>0 then perform projects.finance_account(p_tenant_id,p_legal_entity_id,(p_payload->>'tax_account_id')::uuid,'asset',base);end if;
   if jsonb_typeof(p_payload->'allocations') is distinct from 'array' or jsonb_array_length(p_payload->'allocations') not between 1 and 50 or(select count(distinct z->>'task_id') from jsonb_array_elements(p_payload->'allocations') z)<>jsonb_array_length(p_payload->'allocations') then raise exception using errcode='22023',message='PROJECT_EXPENSE_ALLOCATION_INVALID';end if;
   select sum((z->>'weight')::numeric) into weight_total from jsonb_array_elements(p_payload->'allocations') z;
   if weight_total>9007199254740990 or weight_total<=0 then raise exception using errcode='22023',message='PROJECT_EXPENSE_ALLOCATION_INVALID';end if;
   digest:=encode(extensions.digest(convert_to(((p_payload-array['action','reason'])||jsonb_build_object('evidence_documents',proofs))::text,'UTF8'),'sha256'),'hex');
   if act='expense_create' then insert into projects.expenses(id,tenant_id,legal_entity_id,branch_id,project_id,employee_id,current_revision_id,external_reference,created_by)
    values(id,p_tenant_id,p_legal_entity_id,p_branch_id,project,(p_payload->>'employee_id')::uuid,new_revision,p_payload->>'external_reference',auth.uid());
   else update projects.expenses set version=version+1,current_revision_id=new_revision,status='draft',submitted_by=null where expenses.id=id;end if;
   insert into projects.expense_revisions(id,tenant_id,legal_entity_id,project_id,expense_id,version,service_date,purpose,evidence_reference,evidence_documents,original_currency,base_currency,original_precision,base_precision,
    net,tax,gross,base_net,base_tax,base_gross,tax_rounding_residue,tax_definition_id,tax_version,tax_basis,no_tax_reason,exchange_rate_id,exchange_rate_version,fx_numerator,fx_denominator,fx_basis,
    expense_account_id,tax_account_id,liability_account_id,billable,bill_amount,digest,reason,recorded_by,supersedes_id)
   values(new_revision,p_tenant_id,p_legal_entity_id,project,id,p_expected_version+1,posting_date,p_payload->>'purpose',p_payload->>'evidence_reference',proofs,p_payload->>'original_currency',base,original_scale,scale,
    net,tax,gross,base_net,base_tax,base_gross,base_tax-projects.ratio(tax*1000000*ratio_n,ratio_d,scale),(p_payload->>'tax_definition_id')::uuid,(p_payload->>'tax_version')::bigint,taxdata,p_payload->>'no_tax_reason',
    (p_payload->>'exchange_rate_id')::uuid,(p_payload->>'exchange_rate_version')::bigint,ratio_n,ratio_d,fxdata,(p_payload->>'expense_account_id')::uuid,(p_payload->>'tax_account_id')::uuid,(p_payload->>'liability_account_id')::uuid,
    (p_payload->>'billable')::boolean,bill,digest,reason,auth.uid(),v.id);
   for allocation in select value from jsonb_array_elements(p_payload->'allocations') loop
    if jsonb_typeof(allocation) is distinct from 'object' or(select count(*) from jsonb_object_keys(allocation))<>2 or not(allocation?'task_id' and allocation?'weight') or jsonb_typeof(allocation->'weight') is distinct from 'number' or(allocation->>'weight')::numeric<>(allocation->>'weight')::bigint or(allocation->>'weight')::bigint<=0 then raise exception using errcode='22023',message='PROJECT_EXPENSE_ALLOCATION_INVALID';end if;
    ord:=ord+1;weight_sum:=weight_sum+(allocation->>'weight')::numeric;part:=projects.ratio(base_gross*1000000*weight_sum,weight_total,scale)-allocated;allocated:=allocated+part;
    insert into projects.expense_allocations(id,tenant_id,legal_entity_id,project_id,expense_id,revision_id,plan_id,task_id,ordinal,weight,amount)
     values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,project,id,new_revision,r.current_plan_id,(allocation->>'task_id')::uuid,ord,(allocation->>'weight')::bigint,part);
   end loop;
   if allocated<>base_gross then raise exception using errcode='23514',message='PROJECT_EXPENSE_CONSERVATION_INVALID';end if;
  elsif act='expense_submit' then
   if x.status<>'draft' then raise exception using errcode='55000',message='PROJECT_EXPENSE_STATE_INVALID';end if;
   update projects.expenses set status='submitted',submitted_by=auth.uid(),version=version+1 where expenses.id=id;
  elsif act in('expense_approve','expense_reject') then
   if x.status<>'submitted' then raise exception using errcode='55000',message='PROJECT_EXPENSE_STATE_INVALID';end if;
   if auth.uid() in(x.submitted_by,v.recorded_by) then raise exception using errcode='42501',message='PROJECT_INDEPENDENT_APPROVAL_REQUIRED';end if;
   if p_payload->>'digest' is distinct from v.digest then raise exception using errcode='40001',message='PROJECT_FINANCE_DIGEST_CONFLICT';end if;
   insert into projects.expense_decisions(tenant_id,legal_entity_id,expense_id,revision_id,decision,digest,reason,actor_id)
    values(p_tenant_id,p_legal_entity_id,id,v.id,case when act='expense_approve' then 'approved' else 'rejected' end,v.digest,reason,auth.uid());
   if act='expense_approve' then
    insert into projects.expense_ownership values(id,p_tenant_id,p_legal_entity_id,v.id,'reimbursement',auth.uid(),clock_timestamp());
    if v.billable then insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount)
     values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,project,p_branch_id,'expense',id,v.version,v.digest,v.bill_amount);end if;
   end if;
   update projects.expenses set status=case when act='expense_approve' then 'approved' else 'rejected' end,version=version+1 where expenses.id=id;
  elsif act='expense_cancel' then
   if x.status not in('draft','rejected') then raise exception using errcode='55000',message='PROJECT_EXPENSE_CORRECTION_IMPACT_REQUIRED';end if;
   update projects.expenses set status='cancelled',version=version+1 where expenses.id=id;
  elsif act in('expense_post','expense_reverse') then
   posting_date:=(p_payload->>'posting_date')::date;if posting_date is null or posting_date>(select (clock_timestamp() at time zone timezone)::date from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id) then raise exception using errcode='22023',message='PROJECT_POSTING_DATE_INVALID';end if;
   if act='expense_post' then
    if x.status<>'approved' then raise exception using errcode='55000',message='PROJECT_EXPENSE_STATE_INVALID';end if;
    perform projects.finance_account(p_tenant_id,p_legal_entity_id,v.expense_account_id,'expense',v.base_currency);perform projects.finance_account(p_tenant_id,p_legal_entity_id,v.liability_account_id,'liability',v.base_currency);
    lines:=jsonb_build_array(finance.flow_jline(v.expense_account_id,v.base_net,v.base_net,v.id),finance.flow_jline(v.liability_account_id,-v.base_gross,-v.base_gross,id));
    if v.base_tax>0 then perform projects.finance_account(p_tenant_id,p_legal_entity_id,v.tax_account_id,'asset',v.base_currency);lines:=lines||jsonb_build_array(finance.flow_jline(v.tax_account_id,v.base_tax,v.base_tax,v.id));end if;
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'document_date',posting_date,'currency_code',v.base_currency,'base_currency_code',v.base_currency,'exchange_rate','1.000000'),lines,'project_reimbursement',id,request,p_command_id);
    insert into projects.reimbursements values(id,p_tenant_id,p_legal_entity_id,p_branch_id,project,id,v.id,v.base_currency,v.base_gross,v.liability_account_id,posting_date,journal,auth.uid(),clock_timestamp());
    insert into projects.reimbursement_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,journal_id,posting_date,recorded_by) values(p_tenant_id,p_legal_entity_id,id,'issue',v.base_gross,id,journal,posting_date,auth.uid());
    update projects.expenses set status='posted',version=version+1 where expenses.id=id;
   else
    if x.status<>'posted' then raise exception using errcode='55000',message='PROJECT_EXPENSE_STATE_INVALID';end if;
    select * into o from projects.reimbursements where expense_id=id for update;
    select sum(reimbursement_effects.amount) into outstanding from projects.reimbursement_effects where obligation_id=o.id;
    if outstanding<>o.amount then raise exception using errcode='55000',message='PROJECT_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL';end if;
    if exists(select 1 from projects.billable_units where source_kind='expense' and source_id=id and status in('reserved','billed')) then raise exception using errcode='55000',message='PROJECT_BILLING_IMPACT_REQUIRED';end if;
    select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,'amount',(transaction_credit-transaction_debit)::text,'base_amount',(base_credit-base_debit)::text) order by line_number) into lines from finance.journal_lines where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=o.journal_id;
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'document_date',posting_date,'currency_code',v.base_currency,'base_currency_code',v.base_currency,'exchange_rate','1.000000'),lines,'project_reimbursement_reverse',id,request,p_command_id);
    insert into projects.reimbursement_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,journal_id,posting_date,reversal_of,recorded_by)
     select p_tenant_id,p_legal_entity_id,id,'expense_reverse',-reimbursement_effects.amount,id,journal,posting_date,reimbursement_effects.id,auth.uid() from projects.reimbursement_effects where obligation_id=o.id and kind='issue';
    update projects.billable_units set status='cancelled' where source_kind='expense' and source_id=id and status='available';
    update projects.expenses set status='reversed',version=version+1 where expenses.id=id;
   end if;
  end if;outcome:=projects.expense_summary(id);
 elsif act in('settle','settlement_reverse') then
  posting_date:=(p_payload->>'posting_date')::date;if posting_date is null or posting_date>(select (clock_timestamp() at time zone timezone)::date from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id) then raise exception using errcode='22023',message='PROJECT_POSTING_DATE_INVALID';end if;
  if act='settle' then
   if p_expected_version<>0 then raise exception using errcode='40001',message='PROJECT_FINANCE_VERSION_CONFLICT';end if;
   select * into o from projects.reimbursements where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=project and reimbursements.id=(p_payload->>'obligation_id')::uuid for update;
   if o.id is null then raise exception using errcode='P0002',message='PROJECT_OBLIGATION_NOT_FOUND';end if;
   select sum(reimbursement_effects.amount) into outstanding from projects.reimbursement_effects where obligation_id=o.id;
   amount:=projects.amount(p_payload->'amount');if amount<=0 or amount>outstanding or amount<>round(amount,r.precision) then raise exception using errcode='55000',message='PROJECT_SETTLEMENT_EXCEEDS_DUE';end if;
   select * into bank from finance.cash_bank_accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and cash_bank_accounts.id=(p_payload->>'bank_id')::uuid and status='active' and currency_code=o.currency_code for share;
   if bank.id is null then raise exception using errcode='55000',message='PROJECT_BANK_PROVIDER_REQUIRED';end if;
   if bank.version is distinct from(p_payload->>'bank_version')::bigint then raise exception using errcode='40001',message='PROJECT_BANK_VERSION_CONFLICT';end if;
   perform projects.finance_account(p_tenant_id,p_legal_entity_id,bank.account_id,'asset',o.currency_code);perform projects.finance_account(p_tenant_id,p_legal_entity_id,o.account_id,'liability',o.currency_code);
   perform projects.text(p_payload->'evidence_reference',160);
   lines:=jsonb_build_array(finance.flow_jline(o.account_id,amount,amount,o.id),finance.flow_jline(bank.account_id,-amount,-amount,id));
   journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'document_date',posting_date,'currency_code',o.currency_code,'base_currency_code',o.currency_code,'exchange_rate','1.000000'),lines,'project_settlement',id,request,p_command_id);
   insert into projects.expense_settlements values(id,p_tenant_id,p_legal_entity_id,p_branch_id,project,o.id,posting_date,amount,bank.id,bank.version,bank.account_id,p_payload->>'evidence_reference',journal,auth.uid(),clock_timestamp());
   insert into projects.reimbursement_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,journal_id,posting_date,recorded_by) values(p_tenant_id,p_legal_entity_id,o.id,'settle',-amount,id,journal,posting_date,auth.uid());
  else
   if p_expected_version<>1 then raise exception using errcode='40001',message='PROJECT_FINANCE_VERSION_CONFLICT';end if;
   select * into s from projects.expense_settlements where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=project and expense_settlements.id=id for update;
   if s.id is null then raise exception using errcode='P0002',message='PROJECT_SETTLEMENT_NOT_FOUND';end if;
   if exists(select 1 from projects.reimbursement_effects where kind='settlement_reverse' and source_id=id) then raise exception using errcode='55000',message='PROJECT_SETTLEMENT_ALREADY_REVERSED';end if;
   select * into o from projects.reimbursements where reimbursements.id=s.obligation_id for update;
   select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,'amount',(transaction_credit-transaction_debit)::text,'base_amount',(base_credit-base_debit)::text) order by line_number) into lines from finance.journal_lines where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=s.journal_id;
   journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'document_date',posting_date,'currency_code',o.currency_code,'base_currency_code',o.currency_code,'exchange_rate','1.000000'),lines,'project_settlement_reverse',id,request,p_command_id);
   insert into projects.reimbursement_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,journal_id,posting_date,reversal_of,recorded_by)
    select p_tenant_id,p_legal_entity_id,o.id,'settlement_reverse',-reimbursement_effects.amount,id,journal,posting_date,reimbursement_effects.id,auth.uid() from projects.reimbursement_effects where obligation_id=o.id and kind='settle' and source_id=id;
  end if;
  outcome:=jsonb_build_object('id',id,'project_id',project,'version',case when act='settle' then 1 else 2 end,'status',case when act='settle' then 'recorded' else 'reversed' end,'journal_id',journal);
 elsif act='service_source' then
  if p_expected_version<>0 or r.customer_id is null or to_regprocedure('service.billing_source(uuid,uuid,uuid,uuid)') is null then raise exception using errcode='55000',message='PROJECT_SERVICE_BILLING_PROVIDER_REQUIRED';end if;
  perform core.wave3_require_scope(p_tenant_id,'service.billing',p_legal_entity_id,p_branch_id);
  execute 'select service.billing_source($1,$2,$3,$4)' into doc using p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'service_source_id')::uuid;
  if doc->>'customer_id' is distinct from r.customer_id::text or doc->>'currency_code' is distinct from r.currency_code or(doc->>'source_version')::bigint is distinct from(p_payload->>'source_version')::bigint or doc->>'digest' is distinct from p_payload->>'source_digest' then raise exception using errcode='40001',message='PROJECT_SERVICE_SOURCE_CONFLICT';end if;
  amount:=projects.amount(doc->'amount');if amount<>round(amount,r.precision) or(doc->>'seconds')::bigint not between 1 and 2678400 then raise exception using errcode='22023',message='PROJECT_SERVICE_SOURCE_INVALID';end if;
  if exists(select 1 from projects.billable_units where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and source_kind='service' and provider_source_id=(p_payload->>'service_source_id')::uuid and project_id<>project) then raise exception using errcode='55000',message='PROJECT_SERVICE_PROJECT_IMPACT_REQUIRED';end if;
  insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,provider_source_id,source_version,source_digest,amount,payable_seconds)
   values(id,p_tenant_id,p_legal_entity_id,project,p_branch_id,'service',(doc->>'source_id')::uuid,(p_payload->>'service_source_id')::uuid,(doc->>'source_version')::bigint,doc->>'digest',amount,(doc->>'seconds')::bigint);
  perform projects.service_payroll_cost_impact(p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'service_source_id')::uuid,(doc->>'source_id')::uuid);
  outcome:=jsonb_build_object('id',id,'project_id',project,'version',1,'status','available');
 elsif act like 'billing_%' then
  if act='billing_prepare' then
   if p_expected_version<>0 or r.customer_id is null then raise exception using errcode='55000',message='PROJECT_BILLING_CUSTOMER_REQUIRED';end if;
   if jsonb_typeof(p_payload->'units') is distinct from 'array' or jsonb_array_length(p_payload->'units') not between 1 and 200 or(select count(distinct z->>'unit_id') from jsonb_array_elements(p_payload->'units') z)<>jsonb_array_length(p_payload->'units') then raise exception using errcode='22023',message='PROJECT_BILLING_SELECTION_INVALID';end if;
   invoice:=(p_payload->>'invoice_id')::uuid;posting_date:=(p_payload->>'document_date')::date;if invoice is null or posting_date is null then raise exception using errcode='22023',message='PROJECT_BILLING_SELECTION_INVALID';end if;
   for allocation in select value from jsonb_array_elements(p_payload->'units') order by value->>'unit_id' loop
    if jsonb_typeof(allocation) is distinct from 'object' or exists(select 1 from jsonb_object_keys(allocation) k where k<>all(array['unit_id','source_version','source_digest','product_id','product_version','tax_definition_id','tax_version','description'])) then raise exception using errcode='22023',message='PROJECT_BILLING_SELECTION_INVALID';end if;
    select * into u from projects.billable_units where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=project and billable_units.id=(allocation->>'unit_id')::uuid for update;
    if u.id is null or u.status<>'available' then raise exception using errcode='55000',message='PROJECT_BILLING_SOURCE_UNAVAILABLE';end if;
    if u.source_version is distinct from(allocation->>'source_version')::bigint or u.source_digest is distinct from allocation->>'source_digest' then raise exception using errcode='40001',message='PROJECT_BILLING_SOURCE_CONFLICT';end if;
    if u.source_kind='service' then
     perform core.wave3_require_scope(p_tenant_id,'service.billing',p_legal_entity_id,p_branch_id);
     execute 'select service.billing_source($1,$2,$3,$4)' into doc using p_tenant_id,p_legal_entity_id,p_branch_id,u.provider_source_id;
     if(doc->>'source_id')::uuid<>u.source_id or(doc->>'source_version')::bigint<>u.source_version or doc->>'digest'<>u.source_digest or(doc->>'amount')::numeric<>u.amount or doc->>'customer_id' is distinct from r.customer_id::text then raise exception using errcode='40001',message='PROJECT_SERVICE_SOURCE_CONFLICT';end if;
    end if;
    if u.source_kind='milestone' then
     doc:=projects.milestone_terms(p_tenant_id,p_legal_entity_id,p_branch_id,u);
     if(p_payload->>'due_date')::date is distinct from posting_date+(doc->>'payment_due_days')::integer then raise exception using errcode='22023',message='PROJECT_MILESTONE_DUE_DATE_REQUIRED';end if;
    end if;
    select * into product from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and products.id=(allocation->>'product_id')::uuid and status='active' and kind='service' and can_sell for share;
    if product.id is null or product.version is distinct from(allocation->>'product_version')::bigint then raise exception using errcode='40001',message='PROJECT_BILLING_PRODUCT_CONFLICT';end if;
    if allocation->>'tax_definition_id' is not null then
     select * into taxdef from finance.tax_definitions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and tax_definitions.id=(allocation->>'tax_definition_id')::uuid and status='active' and kind in('output','zero','exempt') and posting_date>=valid_from and(valid_to is null or posting_date<=valid_to) for share;
     if taxdef.id is null or taxdef.version is distinct from(allocation->>'tax_version')::bigint then raise exception using errcode='40001',message='PROJECT_BILLING_TAX_CONFLICT';end if;
    elsif allocation->>'tax_version' is not null then raise exception using errcode='22023',message='PROJECT_BILLING_TAX_CONFLICT';end if;
    line:=gen_random_uuid();lines:=lines||jsonb_build_array(jsonb_build_object('line_id',line,'product_id',product.id,'description',projects.text(allocation->'description',1000),'unit_id',product.base_unit_id,'quantity','1.000000','base_quantity','1.000000','conversion_numerator','1','conversion_denominator','1','unit_price',u.amount::text,'tax_definition_id',allocation->>'tax_definition_id'));
    unit_ids:=array_append(unit_ids,u.id);update projects.billable_units set status='reserved' where billable_units.id=u.id;
   end loop;
   answer:=api.upsert_sales_invoice(p_tenant_id,p_legal_entity_id,p_branch_id,gen_random_uuid(),gen_random_uuid(),p_issued_at,jsonb_build_object('id',invoice,'customer_id',r.customer_id,'document_date',posting_date,'due_date',p_payload->>'due_date','currency_code',r.currency_code,'exchange_rate_id',p_payload->>'exchange_rate_id','lines',lines,'reason',reason),null);
   doc:=sales.flow_document('sales_invoice',p_tenant_id,invoice);digest:=encode(extensions.digest(convert_to((doc-array['request_id','command_id','correlation_id','client_timestamp','created_at','updated_at'])::text,'UTF8'),'sha256'),'hex');
   insert into projects.billing_batches(id,tenant_id,legal_entity_id,branch_id,project_id,invoice_id,digest,prepared_by) values(id,p_tenant_id,p_legal_entity_id,p_branch_id,project,invoice,digest,auth.uid());
   ord:=0;for allocation in select value from jsonb_array_elements(p_payload->'units') order by value->>'unit_id' loop
    ord:=ord+1;select * into u from projects.billable_units where billable_units.id=(allocation->>'unit_id')::uuid;
    insert into projects.billing_links values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,project,id,u.id,(lines->(ord-1)->>'line_id')::uuid,u.source_version,u.source_digest,u.amount,(allocation->>'product_id')::uuid,(allocation->>'product_version')::bigint,(allocation->>'tax_definition_id')::uuid,(allocation->>'tax_version')::bigint,doc->'lines'->(ord-1));
   end loop;select * into b from projects.billing_batches where billing_batches.id=id;
  else
   select * into b from projects.billing_batches where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=project and billing_batches.id=id for update;
   if b.id is null then raise exception using errcode='P0002',message='PROJECT_BILLING_BATCH_NOT_FOUND';end if;
   if b.version<>p_expected_version then raise exception using errcode='40001',message='PROJECT_FINANCE_VERSION_CONFLICT';end if;
   if b.status<>'prepared' then raise exception using errcode='55000',message='PROJECT_BILLING_STATE_INVALID';end if;
   perform billable_units.id from projects.billable_units where billable_units.id in(select unit_id from projects.billing_links where batch_id=id) order by billable_units.id for update;
   if exists(select 1 from projects.billing_links l join projects.billable_units z on z.id=l.unit_id where l.batch_id=id and(z.status<>'reserved' or z.source_version<>l.source_version or z.source_digest<>l.source_digest or z.amount<>l.amount)) then raise exception using errcode='40001',message='PROJECT_BILLING_SOURCE_CONFLICT';end if;
   doc:=sales.flow_document('sales_invoice',p_tenant_id,b.invoice_id,true);invoice_version:=(p_payload->>'invoice_version')::bigint;
   if invoice_version is distinct from(doc->>'version')::bigint then raise exception using errcode='40001',message='PROJECT_INVOICE_VERSION_CONFLICT';end if;
   if act='billing_post' then
    for u in select z.* from projects.billable_units z where z.id in(select unit_id from projects.billing_links where batch_id=id) and z.source_kind='milestone' order by z.id loop
     outcome:=projects.milestone_terms(p_tenant_id,p_legal_entity_id,p_branch_id,u);
     if(doc->>'due_date')::date is distinct from(doc->>'document_date')::date+(outcome->>'payment_due_days')::integer then raise exception using errcode='22023',message='PROJECT_MILESTONE_DUE_DATE_REQUIRED';end if;
    end loop;
    for u in select z.* from projects.billable_units z where z.id in(select unit_id from projects.billing_links where batch_id=id) and z.source_kind='service' order by z.id loop
     perform core.wave3_require_scope(p_tenant_id,'service.billing',p_legal_entity_id,p_branch_id);
     execute 'select service.consume_billing_source($1,$2,$3,$4,$5,$6,$7)' using p_tenant_id,p_legal_entity_id,p_branch_id,u.provider_source_id,u.source_version,u.source_digest,id;
    end loop;
    insert into projects.billing_intents values(b.invoice_id,p_tenant_id,p_legal_entity_id,txid_current(),auth.uid());
    answer:=api.post_sales_invoice(p_tenant_id,p_legal_entity_id,p_branch_id,gen_random_uuid(),gen_random_uuid(),p_issued_at,jsonb_build_object('id',b.invoice_id),invoice_version);
    delete from projects.billing_intents where invoice_id=b.invoice_id;
    update projects.billable_units set status='billed' where billable_units.id in(select unit_id from projects.billing_links where batch_id=id);
    update projects.billing_batches set status='posted',posted_at=clock_timestamp(),version=version+1 where billing_batches.id=id;
   else
    insert into projects.billing_intents values(b.invoice_id,p_tenant_id,p_legal_entity_id,txid_current(),auth.uid());
    answer:=api.transition_operational_document(p_tenant_id,p_legal_entity_id,p_branch_id,gen_random_uuid(),gen_random_uuid(),p_issued_at,jsonb_build_object('document_type','sales_invoice','document_id',b.invoice_id,'action',case when act='billing_cancel' then 'cancel' when act='billing_submit' then 'submit' else null end,'decision',case when act='billing_decide' then projects.text(p_payload->'decision',10) else null end,'reason',reason,'note',reason),invoice_version);
    delete from projects.billing_intents where invoice_id=b.invoice_id;
    if act='billing_cancel' then update projects.billable_units set status='available' where billable_units.id in(select unit_id from projects.billing_links where batch_id=id);update projects.billing_batches set status='cancelled',cancelled_at=clock_timestamp(),version=version+1 where billing_batches.id=id;
    else update projects.billing_batches set version=version+1 where billing_batches.id=id;end if;
   end if;select * into b from projects.billing_batches where billing_batches.id=id;
  end if;
  outcome:=jsonb_build_object('id',id,'project_id',project,'version',b.version,'status',b.status,'invoice_id',b.invoice_id);
 end if;
 if outcome is null then raise exception using errcode='22023',message='PROJECT_FINANCE_ACTION_INVALID';end if;
 outcome:=outcome||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
 insert into projects.finance_events(tenant_id,legal_entity_id,branch_id,project_id,aggregate_id,action,version,reason,actor_id,command_id) values(p_tenant_id,p_legal_entity_id,p_branch_id,project,id,act,(outcome->>'version')::bigint,reason,auth.uid(),p_command_id);
 return core.wave3_finish_command(p_tenant_id,'projects.finance.'||act,p_command_id,'projects.finance',id,p_idempotency_key,hash,before_state,outcome,p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object('action',act),p_request_id=>request);
end $$;
create function api.projects_finance_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql security definer set search_path='' as $$declare attachments boolean:=false;access jsonb;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability);
 if to_regprocedure('api.projects_expense_evidence_access(uuid,uuid,uuid,uuid,uuid,text)') is not null then
  begin
   execute 'select api.projects_expense_evidence_access($1,$2,$3,null,null,$4)' into access using p_tenant_id,p_legal_entity_id,p_branch_id,'projects.expenses.evidence.view';
   attachments:=coalesce((access->>'available')::boolean,false);
  exception when insufficient_privilege then attachments:=false;end;
 end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'actor_id',auth.uid(),'capability',p_capability,'authorized',true,'supplier_ap_available',false,'attachments_available',attachments,'sales_available',true);
end $$;
create function api.projects_finance_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_kind text,p_after uuid default null,p_target_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare items jsonb;cap text;begin
 cap:=case when p_kind in('billing','units') then 'projects.billing.manage' when p_kind='obligations' or p_kind='settlements' then 'projects.expenses.settle' else 'projects.cost.view' end;
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap);
 if not exists(select 1 from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_project_id) then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 if p_kind='expenses' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select x.id,
   projects.expense_summary(x.id)||jsonb_build_object('employee_name',emp.display_name,'external_reference',x.external_reference,'purpose',v.purpose,'service_date',v.service_date,'evidence_reference',v.evidence_reference,
    'evidence_documents',projects.expense_proofs(p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,x.id,v.evidence_documents,'read'),
    'original_currency',v.original_currency,'base_currency',v.base_currency,'original_precision',v.original_precision,'base_precision',v.base_precision,'net',v.net::text,'tax',v.tax::text,'gross',v.gross::text,'base_net',v.base_net::text,'base_tax',v.base_tax::text,'base_gross',v.base_gross::text,'tax_rounding_residue',v.tax_rounding_residue::text,
    'tax_definition_id',v.tax_definition_id,'tax_version',v.tax_version,'tax_basis',v.tax_basis,'no_tax_reason',v.no_tax_reason,'exchange_rate_id',v.exchange_rate_id,'exchange_rate_version',v.exchange_rate_version,'fx_numerator',v.fx_numerator::text,'fx_denominator',v.fx_denominator::text,'fx_basis',v.fx_basis,
    'expense_account_id',v.expense_account_id,'tax_account_id',v.tax_account_id,'liability_account_id',v.liability_account_id,'billable',v.billable,'bill_amount',v.bill_amount::text,'digest',v.digest,'recorded_by',v.recorded_by,'reason',v.reason,
    'allocations',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'task_id',a.task_id,'task_name',t.name,'ordinal',a.ordinal,'weight',a.weight,'amount',a.amount::text) order by a.ordinal),'[]') from projects.expense_allocations a join projects.tasks t on t.plan_id=a.plan_id and t.id=a.task_id where a.revision_id=v.id)) body
   from projects.expenses x join projects.expense_revisions v on v.id=x.current_revision_id join people.employees emp on emp.id=x.employee_id
   where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.project_id=p_project_id and(p_after is null or x.id>p_after) and(p_target_id is null or x.id=p_target_id) order by x.id limit 50) q;
 elsif p_kind='obligations' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select o.id,jsonb_build_object('id',o.id,'expense_id',o.expense_id,'revision_id',o.revision_id,'currency_code',o.currency_code,'amount',o.amount::text,'outstanding',(select sum(amount)::text from projects.reimbursement_effects where obligation_id=o.id),'account_id',o.account_id,'journal_id',o.journal_id,'posting_date',o.posting_date) body
   from projects.reimbursements o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and o.branch_id=p_branch_id and o.project_id=p_project_id and(p_after is null or o.id>p_after) and(p_target_id is null or o.id=p_target_id) order by o.id limit 50) q;
 elsif p_kind='settlements' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select s.id,jsonb_build_object('id',s.id,'obligation_id',s.obligation_id,'posting_date',s.posting_date,'amount',s.amount::text,'bank_id',s.bank_id,'bank_version',s.bank_version,'evidence_reference',s.evidence_reference,'journal_id',s.journal_id,'status',case when exists(select 1 from projects.reimbursement_effects where source_id=s.id and kind='settlement_reverse') then 'reversed' else 'recorded' end,'version',case when exists(select 1 from projects.reimbursement_effects where source_id=s.id and kind='settlement_reverse') then 2 else 1 end) body
   from projects.expense_settlements s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.branch_id=p_branch_id and s.project_id=p_project_id and(p_after is null or s.id>p_after) and(p_target_id is null or s.id=p_target_id) order by s.id limit 50) q;
 elsif p_kind='billing' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select b.id,jsonb_build_object('id',b.id,'version',b.version,'status',b.status,'invoice_id',b.invoice_id,'digest',b.digest,'prepared_by',b.prepared_by,'invoice_status',i.status,'invoice_version',i.version,'document_date',i.document_date,'currency_code',i.currency_code,'total',i.grand_total::text,'unit_count',(select count(*) from projects.billing_links where batch_id=b.id)) body
   from projects.billing_batches b join sales.sales_invoices i on i.id=b.invoice_id where b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id and b.branch_id=p_branch_id and b.project_id=p_project_id and(p_after is null or b.id>p_after) and(p_target_id is null or b.id=p_target_id) order by b.id limit 50) q;
 elsif p_kind='units' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select u.id,jsonb_build_object('id',u.id,'source_kind',u.source_kind,'source_id',u.source_id,'source_version',u.source_version,'source_digest',u.source_digest,'source_name',case u.source_kind when 'time' then coalesce((select left(t.name,180)||' · '||v.start_local::date from projects.time_revisions v join projects.tasks t on t.id=v.task_id and t.plan_id=v.plan_id where v.id=u.source_id),'Approved project time') when 'expense' then coalesce((select left(v.purpose,180) from projects.expenses x join projects.expense_revisions v on v.id=x.current_revision_id where x.id=u.source_id),'Approved project expense') when 'service' then 'Approved service labor · '||u.payable_seconds||' seconds' else 'Approved project milestone' end,'amount',u.amount::text,'payable_seconds',u.payable_seconds,'status',u.status)
   ||case when u.source_kind='milestone' then projects.milestone_terms(p_tenant_id,p_legal_entity_id,p_branch_id,u)-array['customer_id','currency_code','amount','source_version','digest'] else '{}'::jsonb end body
   from projects.billable_units u where u.tenant_id=p_tenant_id and u.legal_entity_id=p_legal_entity_id and u.branch_id=p_branch_id and u.project_id=p_project_id and(p_after is null or u.id>p_after) and(p_target_id is null or u.id=p_target_id) order by u.id limit 50) q;
 elsif p_kind='serviceCosts' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select c.id,jsonb_build_object('id',c.id,'provider_source_id',c.provider_source_id,
   'source_revision_id',c.source_revision_id,'source_version',c.source_version,'source_digest',c.source_digest,'currency_code',c.currency_code,
   'precision',c.precision,'service_date',c.service_date,'payable_seconds',c.payable_seconds,'hourly_cost',c.hourly_cost::text,'amount',c.amount::text,'status',c.status,'recorded_at',c.recorded_at) body
   from projects.service_cost_revisions c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.branch_id=p_branch_id and c.project_id=p_project_id
   and(p_after is null or c.id>p_after) and(p_target_id is null or c.id=p_target_id) order by c.id limit 50) q;
 elsif p_kind='history' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select h.id,jsonb_build_object('id',h.id,'aggregate_id',h.aggregate_id,'action',h.action,'version',h.version,'reason',h.reason,'actor_id',h.actor_id,'recorded_at',h.recorded_at) body
   from projects.finance_events h where h.tenant_id=p_tenant_id and h.legal_entity_id=p_legal_entity_id and h.branch_id=p_branch_id and h.project_id=p_project_id and(p_after is null or h.id>p_after) and(p_target_id is null or h.id=p_target_id) order by h.id limit 50) q;
 else raise exception using errcode='22023',message='PROJECT_FINANCE_VIEW_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,'kind',p_kind,'rows',items,'next_after',case when jsonb_array_length(items)=50 then items->49->>'id' end);
end $$;
create function api.projects_finance_pickers(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_project_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,case when p_kind in('products','output_tax','service_sources') then 'projects.billing.manage' else 'projects.cost.view' end);
 if p_project_id is not null and not exists(select 1 from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_project_id) then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 if p_kind='employees' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select e.id,jsonb_build_object('id',e.id,'name',e.display_name,'code',e.code,'version',e.version) body from people.employees e where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id and exists(select 1 from people.employment_assignments a where a.employee_id=e.id and a.branch_id=p_branch_id) and(p_after is null or e.id>p_after) order by e.id limit 50) q;
 elsif p_kind in('expense_accounts','tax_accounts','liability_accounts') then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select a.id,jsonb_build_object('id',a.id,'name',a.name,'code',a.code,'version',a.version,'currency_code',a.currency_code) body from finance.accounts a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.is_posting and a.status='active' and a.account_type=case p_kind when 'expense_accounts' then 'expense' when 'tax_accounts' then 'asset' else 'liability' end and(p_after is null or a.id>p_after) order by a.id limit 50) q;
 elsif p_kind='banks' then
  perform core.wave3_require_scope(p_tenant_id,'projects.expenses.settle',p_legal_entity_id,p_branch_id);
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select a.id,jsonb_build_object('id',a.id,'name',a.name,'code',a.code,'version',a.version,'currency_code',a.currency_code) body from finance.cash_bank_accounts a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.status='active' and(p_after is null or a.id>p_after) order by a.id limit 50) q;
 elsif p_kind='products' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select a.id,jsonb_build_object('id',a.id,'name',a.name,'code',a.sku,'version',a.version,'unit_id',a.base_unit_id) body from inventory.products a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.kind='service' and a.can_sell and a.status='active' and(p_after is null or a.id>p_after) order by a.id limit 50) q;
 elsif p_kind in('input_tax','output_tax') then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select a.id,jsonb_build_object('id',a.id,'name',a.name,'code',a.code,'version',a.version,'rate',a.rate::text,'inclusive',a.inclusive,'valid_from',a.valid_from,'valid_to',a.valid_to) body from finance.tax_definitions a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.status='active' and a.kind in(case p_kind when 'input_tax' then 'input' else 'output' end,'zero','exempt') and(p_after is null or a.id>p_after) order by a.id limit 50) q;
 elsif p_kind='rates' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select a.id,jsonb_build_object('id',a.id,'name',a.source_currency_code||' → '||a.target_currency_code||' / '||a.effective_date,'code',a.rate_type,'version',a.version,'source_currency',a.source_currency_code,'target_currency',a.target_currency_code,'rate',a.rate::text,'effective_date',a.effective_date) body from finance.exchange_rates a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.status='active' and(p_after is null or a.id>p_after) order by a.id limit 50) q;
 elsif p_kind='tasks' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select a.id,jsonb_build_object('id',a.id,'name',a.name,'code','TASK','version',p.version) body from projects.tasks a join projects.plans p on p.id=a.plan_id join projects.register r on r.current_plan_id=p.id where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.id=p_project_id and(p_after is null or a.id>p_after) order by a.id limit 50) q;
 elsif p_kind='service_sources' then
  if to_regprocedure('service.billing_source(uuid,uuid,uuid,uuid)') is null then raise exception using errcode='55000',message='PROJECT_SERVICE_BILLING_PROVIDER_REQUIRED';end if;
  execute 'select service.require_access($1,$2,$3,$4)' using p_tenant_id,p_legal_entity_id,p_branch_id,'service.billing';
  execute $q$select coalesce(jsonb_agg(q.body order by q.id),'[]') from(select l.id,jsonb_build_object('id',l.id,'name','Approved labor · '||(service.snapshot('labor',l.id)->>'seconds')||' seconds','code','SERVICE','version',l.version,'source_version',l.version,'source_digest',service.snapshot('labor',l.id)->>'digest','seconds',(service.snapshot('labor',l.id)->>'seconds')::bigint,'amount',service.snapshot('labor',l.id)->>'billable_amount','currency_code',l.currency_code) body from service.labor l join service.work_orders w on w.id=l.order_id join service.tickets t on t.id=w.ticket_id join projects.register r on r.id=$4 where l.tenant_id=$1 and l.legal_entity_id=$2 and l.branch_id=$3 and l.status='approved' and l.billing_kind='billable' and l.billing_consumption_id is null and w.status in('completed','closed') and t.customer_id=r.customer_id and l.currency_code=r.currency_code and($5 is null or l.id>$5) order by l.id limit 50) q$q$ into items using p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,p_after;
 else raise exception using errcode='22023',message='PROJECT_FINANCE_PICKER_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,'rows',items,'next_after',case when jsonb_array_length(items)=50 then items->49->>'id' end);
end $$;
create function api.projects_payroll_credit_choices(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_source_revision_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.billing.manage');
 if p_source_revision_id is null then raise exception using errcode='22023',message='PROJECT_PAYROLL_SOURCE_REQUIRED';end if;
 select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(
  select cr.id,jsonb_build_object('id',cr.id,'name','Posted original credit · '||h.document_date||' · '||cr.line_total::text||' '||h.currency_code,'code','CREDIT','version',h.version,'amount',cr.line_total::text,'currency_code',h.currency_code,'invoice_line_id',cr.sales_invoice_line_id,'credit_document_id',h.id) body
  from sales.sales_return_lines cr join sales.sales_returns h on h.id=cr.document_id join projects.billing_links bl on bl.invoice_line_id=cr.sales_invoice_line_id join projects.billing_batches bb on bb.id=bl.batch_id join projects.billable_units u on u.id=bl.unit_id
  where u.tenant_id=p_tenant_id and u.legal_entity_id=p_legal_entity_id and u.branch_id=p_branch_id and u.source_id=p_source_revision_id and u.source_kind in('time','service') and u.status='billed' and bb.status='posted' and h.status='posted' and h.tenant_id=p_tenant_id and h.legal_entity_id=p_legal_entity_id and h.branch_id=p_branch_id and(p_after is null or cr.id>p_after) order by cr.id limit 50) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'source_revision_id',p_source_revision_id,'kind','billing_credits','rows',items,'next_after',case when jsonb_array_length(items)=50 then items->49->>'id' end);
end $$;
create or replace function projects.finance_closure_guard(p_tenant uuid,p_entity uuid,p_project uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from projects.expenses where tenant_id=p_tenant and legal_entity_id=p_entity and project_id=p_project and status in('draft','submitted','approved','rejected'))
 or exists(select 1 from projects.reimbursements o where o.tenant_id=p_tenant and o.legal_entity_id=p_entity and o.project_id=p_project and(select sum(amount) from projects.reimbursement_effects where obligation_id=o.id)>0)
 or exists(select 1 from projects.billing_batches where tenant_id=p_tenant and legal_entity_id=p_entity and project_id=p_project and status='prepared') then raise exception using errcode='55000',message='PROJECT_FINANCE_CLOSURE_IMPACT_REQUIRED';end if;
end $$;
create function api.projects_finance_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$declare response jsonb;v projects.expense_revisions%rowtype;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,projects.finance_cap(p_action));
 select r.response into response from core.command_receipts r where r.tenant_id=p_tenant_id and r.command_name='projects.finance.'||p_action and r.command_id=p_command_id and r.actor_id=auth.uid();
 if response is null then return null;end if;
 if(response#>>'{entity,tenant_id}')::uuid<>p_tenant_id or(response#>>'{entity,legal_entity_id}')::uuid<>p_legal_entity_id or(response#>>'{entity,branch_id}')::uuid<>p_branch_id then raise exception using errcode='42501',message='PROJECT_FINANCE_SCOPE_DENIED';end if;
 if p_action like 'expense_%' then
  select * into v from projects.expense_revisions vv where vv.id=(response#>>'{entity,revision_id}')::uuid and vv.tenant_id=p_tenant_id and vv.legal_entity_id=p_legal_entity_id and vv.expense_id=(response#>>'{entity,id}')::uuid and vv.project_id=(response#>>'{entity,project_id}')::uuid;
  if v.id is null then raise exception using errcode='55000',message='PROJECT_EXPENSE_EVIDENCE_REQUIRED';end if;
  perform projects.expense_proofs(p_tenant_id,p_legal_entity_id,p_branch_id,v.project_id,v.expense_id,v.evidence_documents,'read');
 end if;
 return response;
end $$;
create function api.projects_margin(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_as_of timestamptz,p_effective_date date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare revenue numeric;credits numeric;expense_cost numeric;time_cost numeric;service_cost numeric;commitments numeric;budget numeric;obligations numeric;plan uuid;currency text;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.margin.view');
 if p_as_of is null or p_effective_date is null or p_as_of>clock_timestamp() then raise exception using errcode='22023',message='PROJECT_MARGIN_DATE_INVALID';end if;
 select currency_code into currency from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_project_id;if currency is null then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 select p.id into plan from projects.plans p join projects.plan_decisions d on d.plan_id=p.id where p.project_id=p_project_id and d.decision='approved' and d.decided_at<=p_as_of order by d.decided_at desc,p.version desc limit 1;
 select coalesce(c.budget,0) into budget from projects.cost_basis c where c.plan_id=plan;budget:=coalesce(budget,0);
 select coalesce(sum(projects.ratio(s.planned_seconds*c.hourly_rate*1000000,3600,r.precision)),0) into commitments from projects.resource_slots s join projects.resource_costs c on c.resource_slot_id=s.id join projects.register r on r.id=s.project_id where s.plan_id=plan;
 select coalesce(sum(v.base_gross),0) into expense_cost from projects.expense_revisions v join projects.expense_decisions d on d.revision_id=v.id where v.project_id=p_project_id and d.decision='approved' and d.recorded_at<=p_as_of and v.service_date<=p_effective_date and not exists(select 1 from projects.reimbursement_effects ef join projects.reimbursements o on o.id=ef.obligation_id where o.revision_id=v.id and ef.kind='expense_reverse' and ef.recorded_at<=p_as_of and ef.posting_date<=p_effective_date);
 select coalesce(sum(c.amount),0) into time_cost from projects.time_costs c join projects.time_revisions v on v.id=c.revision_id where c.project_id=p_project_id and v.start_local::date<=p_effective_date and exists(select 1 from projects.time_events ev where ev.revision_id=v.id and ev.action='time_approve' and ev.recorded_at<=p_as_of) and not exists(select 1 from projects.time_events ev where ev.revision_id=v.id and ev.action='time_cancel' and ev.recorded_at<=p_as_of);
 select coalesce(sum(q.amount),0) into service_cost from(select distinct on(c.provider_source_id) c.amount,c.service_date from projects.service_cost_revisions c
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.branch_id=p_branch_id and c.project_id=p_project_id and c.recorded_at<=p_as_of
   order by c.provider_source_id,c.source_version desc,c.recorded_at desc) q where q.service_date<=p_effective_date;
 select coalesce(sum(round(l.taxable_amount*i.exchange_rate,i.rounding_scale)),0) into revenue from projects.billing_batches b join sales.sales_invoices i on i.id=b.invoice_id join sales.sales_invoice_lines l on l.document_id=i.id where b.project_id=p_project_id and i.status='posted' and i.posted_at<=p_as_of and i.document_date<=p_effective_date;
 select coalesce(sum(round(l.taxable_amount*i.exchange_rate,i.rounding_scale)),0) into credits from sales.sales_return_lines l join sales.sales_returns i on i.id=l.document_id join projects.billing_links bl on bl.invoice_line_id=l.sales_invoice_line_id join projects.billing_batches b on b.id=bl.batch_id where b.project_id=p_project_id and i.status='posted' and i.posted_at<=p_as_of and i.document_date<=p_effective_date;
 select coalesce(sum(ef.amount),0) into obligations from projects.reimbursements o join projects.reimbursement_effects ef on ef.obligation_id=o.id where o.project_id=p_project_id and ef.recorded_at<=p_as_of and ef.posting_date<=p_effective_date;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,'as_of',p_as_of,'effective_date',p_effective_date,'currency_code',currency,'budget',budget::text,'commitments',commitments::text,'time_cost',time_cost::text,'service_cost',service_cost::text,'expense_cost',expense_cost::text,'posted_revenue',revenue::text,'posted_credits',credits::text,'margin',(revenue-credits-time_cost-service_cost-expense_cost)::text,'outstanding_reimbursements',obligations::text);
end $$;
-- Cross-provider payroll hook. Never callable by client roles. Credits must
-- already be posted by the actual sales return workflow and consume each original
-- line completely; immutable original units and revenue are never rewritten.
create table projects.payroll_billing_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 correction_id uuid not null,source_revision_id uuid not null,mode text not null check(mode in('apply','reverse')),body jsonb not null,digest text not null check(digest~'^[a-f0-9]{64}$'),
 actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),constraint payroll_billing_effect_identity unique(tenant_id,legal_entity_id,correction_id,source_revision_id,mode),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id)
);
alter table projects.payroll_billing_effects enable row level security;alter table projects.payroll_billing_effects force row level security;
revoke all on projects.payroll_billing_effects from public,anon,authenticated,service_role;
create trigger immutable before update or delete on projects.payroll_billing_effects for each row execute function projects.immutable();
create function projects.billing_source_impact(t uuid,e uuid,b uuid,project uuid,source_kind_filter text,source_revision uuid,proposal jsonb,mode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u projects.billable_units%rowtype;ln record;ids uuid[];matched uuid[]:='{}';line_ids uuid[]:='{}';unit_ids uuid[]:='{}';body jsonb;prior jsonb;correction uuid:=(proposal->>'correction_id')::uuid;full_net numeric;full_tax numeric;full_total numeric;qty numeric;digest text;begin
 if mode not in('validate','apply','reverse') or correction is null or jsonb_typeof(proposal) is distinct from 'object' then raise exception using errcode='22023',message='PROJECT_PAYROLL_BILLING_IMPACT_INVALID';end if;
 if not exists(select 1 from projects.register where tenant_id=t and legal_entity_id=e and branch_id=b and id=project) then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 if jsonb_typeof(coalesce(proposal->'billing_credit_line_ids','[]')) is distinct from 'array' or jsonb_array_length(coalesce(proposal->'billing_credit_line_ids','[]'))>50 then raise exception using errcode='22023',message='PROJECT_PAYROLL_CREDIT_SELECTION_INVALID';end if;
 select coalesce(array_agg(value::uuid order by value),'{}') into ids from jsonb_array_elements_text(coalesce(proposal->'billing_credit_line_ids','[]'));
 if cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception using errcode='22023',message='PROJECT_PAYROLL_CREDIT_SELECTION_INVALID';end if;
 select fx.body into prior from projects.payroll_billing_effects fx where fx.tenant_id=t and fx.legal_entity_id=e and fx.branch_id=b and fx.project_id=project and fx.correction_id=correction and fx.source_revision_id=source_revision and fx.mode='apply';
 if mode='reverse' or mode='validate' and proposal->>'operational_mode'='reverse' then
  if prior is null then raise exception using errcode='55000',message='PROJECT_PAYROLL_BILLING_ORIGINAL_REQUIRED';end if;
  if exists(select 1 from projects.billable_units where id=(proposal->>'replacement_unit_id')::uuid and status in('reserved','billed')) then raise exception using errcode='55000',message='PROJECT_BILLING_IMPACT_REQUIRED';end if;
  -- Operational reverse appends a fresh approved revision and exactly one fresh
  -- unit. Original cancelled/consumed units always retain their original state.
  body:=prior||jsonb_build_object('reversed',true,'original_revenue_and_credits_retained',true);
 else
  select * into u from projects.billable_units where tenant_id=t and legal_entity_id=e and branch_id=b and project_id=project and source_kind=source_kind_filter and source_id=source_revision for update;
  if u.id is null then if cardinality(ids)>0 then raise exception using errcode='22023',message='PROJECT_PAYROLL_CREDIT_SELECTION_INVALID';end if;body:=jsonb_build_object('original_unit_ids','[]'::jsonb,'original_invoice_line_ids','[]'::jsonb,'credit_line_ids','[]'::jsonb,'original_amount','0','original_seconds',0);
  else
   if u.status='reserved' then raise exception using errcode='55000',message='PROJECT_BILLING_IMPACT_REQUIRED';end if;
   if mode='apply' and prior is not null then return prior;end if;
   if u.status not in('available','billed','waived') then raise exception using errcode='55000',message='PROJECT_BILLING_IMPACT_REQUIRED';end if;
   unit_ids:=array[u.id];
   if u.status='billed' then
    perform projects.finance_access(t,e,b,'projects.billing.manage');
    for ln in select l.* from sales.sales_invoice_lines l join projects.billing_links bl on bl.invoice_line_id=l.id join projects.billing_batches bb on bb.id=bl.batch_id where bl.unit_id=u.id and bb.status='posted' order by l.id loop
     select coalesce(sum(cr.taxable_amount),0),coalesce(sum(cr.tax_amount),0),coalesce(sum(cr.line_total),0),coalesce(sum(cr.base_quantity),0),coalesce(array_agg(cr.id order by cr.id),'{}')
      into full_net,full_tax,full_total,qty,matched from sales.sales_return_lines cr join sales.sales_returns h on h.id=cr.document_id join sales.sales_invoices original on original.id=ln.document_id
      where cr.id=any(ids) and cr.sales_invoice_line_id=ln.id and h.tenant_id=t and h.legal_entity_id=e and h.branch_id=b and h.status='posted' and h.customer_id=original.customer_id and h.currency_code=original.currency_code and cr.product_id=ln.product_id;
     if qty<>ln.base_quantity or full_net<>ln.taxable_amount or full_tax<>ln.tax_amount or full_total<>ln.line_total then raise exception using errcode='55000',message='PROJECT_POSTED_ORIGINAL_CREDIT_REQUIRED';end if;
     line_ids:=array_append(line_ids,ln.id);
    end loop;
    if cardinality(line_ids)=0 or cardinality(matched)<>cardinality(ids) then raise exception using errcode='22023',message='PROJECT_PAYROLL_CREDIT_LINEAGE_INVALID';end if;
   elsif cardinality(ids)>0 then raise exception using errcode='22023',message='PROJECT_PAYROLL_CREDIT_LINEAGE_INVALID';end if;
   body:=jsonb_build_object('original_unit_ids',unit_ids,'original_invoice_line_ids',line_ids,'credit_line_ids',ids,'original_status',u.status,'original_amount',u.amount::text,'original_seconds',u.payable_seconds,'source_version',u.source_version,'source_digest',u.source_digest);
   if mode='apply' and u.status='available' then update projects.billable_units set status='cancelled' where id=u.id;end if;
  end if;
  body:=body||jsonb_build_object('correction_id',correction,'project_id',project,'source_revision_id',source_revision);
 end if;
 digest:=encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex');body:=body||jsonb_build_object('digest',digest);
 if mode<>'validate' then insert into projects.payroll_billing_effects(tenant_id,legal_entity_id,branch_id,project_id,correction_id,source_revision_id,mode,body,digest,actor_id) values(t,e,b,project,correction,source_revision,mode,body,digest,auth.uid()) on conflict on constraint payroll_billing_effect_identity do nothing;end if;
 return body;
end $$;
create function projects.payroll_billing_impact(t uuid,e uuid,b uuid,project uuid,source_revision uuid,proposal jsonb,mode text)
returns jsonb language sql security definer set search_path='' as $$select projects.billing_source_impact(t,e,b,project,'time',source_revision,proposal,mode)$$;
create function projects.service_payroll_billing_impact(t uuid,e uuid,b uuid,labor uuid,source_revision uuid,proposal jsonb,mode text)
returns jsonb language plpgsql security definer set search_path='' as $$declare project uuid;begin
 select u.project_id into project from projects.billable_units u where u.tenant_id=t and u.legal_entity_id=e and u.branch_id=b and u.source_kind='service' and u.provider_source_id=labor and u.source_id=source_revision;
 if project is null then
  if jsonb_typeof(coalesce(proposal->'billing_credit_line_ids','[]')) is distinct from 'array' or jsonb_array_length(coalesce(proposal->'billing_credit_line_ids','[]'))>0 then raise exception using errcode='22023',message='PROJECT_PAYROLL_CREDIT_SELECTION_INVALID';end if;
  return jsonb_build_object('original_unit_ids','[]'::jsonb,'original_invoice_line_ids','[]'::jsonb,'credit_line_ids','[]'::jsonb,'original_amount','0','original_seconds',0);
 end if;
 return projects.billing_source_impact(t,e,b,project,'service',source_revision,proposal,mode);
end $$;
do $$declare p regprocedure;begin
 for p in select x.oid::regprocedure from pg_proc x join pg_namespace n on n.oid=x.pronamespace where n.nspname='projects' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',p);end loop;
 for p in select x.oid::regprocedure from pg_proc x join pg_namespace n on n.oid=x.pronamespace where n.nspname='api' and x.proname in('projects_finance_command','projects_finance_authorize','projects_finance_detail','projects_finance_pickers','projects_payroll_credit_choices','projects_finance_own_receipt','projects_margin') loop execute format('revoke all on function %s from public,anon,service_role',p);execute format('grant execute on function %s to authenticated',p);end loop;
end $$;

create temporary table project_assertions(message text);
grant insert on project_assertions to authenticated,service_role;
-- Included only inside a caller-owned BEGIN ... ROLLBACK. Never an owner bootstrap.
create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('wave4-integrated-rollback-20260926:'||p)::uuid$$;
create function pg_temp.wdate() returns date language sql stable as
  $$select (now() at time zone 'Asia/Colombo')::date$$;
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
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.projects',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer','branch-manager']) x
cross join core.permissions p where p.module='projects';
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reader.role'),'projects.view');
insert into people.departments(id,tenant_id,legal_entity_id,code) values(pg_temp.wid('department'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4OPS');
insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,start_date,end_date_exclusive,reason,recorded_by)
values(pg_temp.wid('department-r1'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('department'),'Synthetic Operations',pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic project fixture',pg_temp.wid('creator'));
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,
 role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('org-'||e.code),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),e.id,s.id,pg_temp.wid('department'),
 pg_temp.wid('calendar-version'),'Synthetic worker',pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic project fixture',pg_temp.wid('creator')
from people.employees e join people.employment_spells s on s.employee_id=e.id where e.tenant_id=pg_temp.wid('tenant') and e.code in('EMPLOYEE','THIRD');
create function pg_temp.pc(p jsonb,v bigint,k text,b text default 'branch') returns jsonb language sql as $$
 select api.projects_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid(k),pg_temp.wid(k),now(),p,v) $$;
create function pg_temp.project_create(p text default 'project') returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid(p),'code',upper(p),'name','Synthetic Project','manager_id',pg_temp.wid('manager'),
  'currency_code','LKR','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'reason','Synthetic project creation') $$;
create function pg_temp.project_plan(p text default 'project',pl text default 'plan') returns jsonb language sql as $$
 select jsonb_build_object('action','plan','id',pg_temp.wid(p),'plan_id',pg_temp.wid(pl),'terms','Synthetic whole-unit commercial terms','budget','1000.00','reason','Synthetic project plan',
 'tasks',jsonb_build_array(jsonb_build_object('id',pg_temp.wid('task'),'name','Delivery','owner_id',pg_temp.wid('employee'),'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',7200,'dependencies','[]'::jsonb),
 jsonb_build_object('id',pg_temp.wid('task2'),'name','Review','owner_id',pg_temp.wid('employee'),'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',0,'dependencies',jsonb_build_array(pg_temp.wid('task')))),
 'resources',jsonb_build_array(jsonb_build_object('id',pg_temp.wid(pl||'-slot'),'task_id',pg_temp.wid('task'),'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+interval '12 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'bill_rate','54.00','cost_rate','18.00'))) $$;
create function pg_temp.project_time(p text,s interval default interval '10 hours',z interval default interval '11 hours',cl boolean default true) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action','time_create','id',pg_temp.wid(p),'project_id',pg_temp.wid('project'),'employee_id',pg_temp.wid('employee'),
 'resource_slot_id',pg_temp.wid('plan-slot'),'start_local',to_char(pg_temp.wdate()::timestamp+s,'YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+z,'YYYY-MM-DD"T"HH24:MI:SS'),'start_offset_seconds',19800,'end_offset_seconds',19800,
 'breaks','[]'::jsonb,'attendance_claim_id',case when cl then(select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')) end,'reason','Synthetic project time') $$;
create function pg_temp.time_action(a text,p text) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid(p),'project_id',pg_temp.wid('project'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic project time transition') $$;
create function pg_temp.plan_action(a text,p text default 'project',pl text default 'plan') returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid(p),'plan_id',pg_temp.wid(pl),'digest',(select basis_digest from projects.plans where id=pg_temp.wid(pl)),'reason','Synthetic independent plan decision') $$;
create temporary table project_responses(label text primary key,body jsonb);grant insert,select on project_responses to authenticated;
create temporary table project_client_samples(label text primary key,body jsonb);grant insert,select on project_client_samples to authenticated;
insert into project_assertions select ok((select count(*)=16 and bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='projects' and c.relkind='r'
 and c.relname=any(array['register','plans','tasks','dependencies','resource_slots','resource_costs','cost_basis','plan_decisions','task_progress','time_entries','time_revisions','time_allocations','time_events','billable_units','time_costs','unit_decisions'])),'AC-401 all core project tables force RLS');
insert into project_assertions select ok(not has_table_privilege('authenticated','projects.cost_basis','SELECT'),'AC-404 no direct private cost read');
insert into project_assertions select ok(not has_table_privilege('authenticated','projects.resource_slots','UPDATE'),'AC-410 no direct planning bypass');
insert into project_assertions select ok(not has_function_privilege('anon','api.projects_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),'AC-401 anonymous commands denied');
insert into project_assertions select is(projects.ratio(18000000,3600,2)::numeric,0::numeric,'AC-411 exact even time tie');
insert into project_assertions select is(projects.ratio(54000000,3600,2)::numeric,0.02::numeric,'AC-411 exact odd time tie');
insert into project_assertions select is(projects.ratio(-15000,1,2)::numeric,-0.02::numeric,'AC-411 signed half-even');
select pg_temp.wactor('creator');set local role authenticated;
insert into project_responses values('create',pg_temp.pc(pg_temp.project_create(),0,'project-create'));
insert into project_assertions select is(pg_temp.pc(pg_temp.project_create(),0,'project-create'),(select body from project_responses where label='create'),'AC-401 exact project replay');
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.project_create()||jsonb_build_object('name','Changed'),0,'project-create')$$,'22023','IDEMPOTENCY_MISMATCH','AC-401 changed body cannot replay');
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.project_create('foreign'),0,'project-foreign','branch2')$$,'55000','PROJECT_MANAGER_COVERAGE_REQUIRED','AC-401 manager branch coverage enforced');
insert into project_assertions select throws_ok($$select pg_temp.pc((pg_temp.project_plan()#-'{tasks,0,owner_id}'),1,'missing-task-owner')$$,
 '22023','PROJECT_TASK_OWNER_REQUIRED','AC-410 every task needs an explicit accountable owner');
insert into project_assertions select throws_ok($$select pg_temp.pc(jsonb_set(pg_temp.project_plan(),'{tasks,0,owner_id}',to_jsonb(pg_temp.wid('foreign-owner'))),1,'foreign-task-owner')$$,
 '55000','PROJECT_TASK_OWNER_COVERAGE_REQUIRED','AC-401 task owner must have scoped dated employment');
insert into project_assertions select throws_ok($$select pg_temp.pc(jsonb_set(pg_temp.project_plan(),'{resources,0,start_local}',
 to_jsonb(pg_temp.wdate()::text||'T10:00:00.500')),1,'fractional-plan')$$,
 '22023','WORK_LOCAL_BOUNDARY_INVALID','AC-411 fractional resource boundaries cannot be rounded to whole UTC seconds');
insert into project_responses values('plan',pg_temp.pc(pg_temp.project_plan(),1,'project-plan'));
reset role;
insert into project_assertions select is((select owner_id from projects.tasks where plan_id=pg_temp.wid('plan') and id=pg_temp.wid('task')),
 pg_temp.wid('employee'),'AC-410 frozen task records the selected accountable employee');
insert into project_assertions select is((select owner_name from projects.tasks where plan_id=pg_temp.wid('plan') and id=pg_temp.wid('task')),
 (select display_name from people.employees where id=pg_temp.wid('employee')),'AC-410 original named task owner is retained');
select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.plan_action('approve_plan'),2,'plan-self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','AC-410 independent planning decision');
select pg_temp.wactor('reviewer');
insert into project_responses values('approve',pg_temp.pc(pg_temp.plan_action('approve_plan'),2,'plan-approve'));
insert into project_assertions select is((select body#>>'{entity,current_plan_id}' from project_responses where label='approve'),pg_temp.wid('plan')::text,'AC-410 approved plan becomes current');
insert into project_assertions select throws_ok($$select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('project'),'task_id',pg_temp.wid('task2'),'progress',10000,'reason','Synthetic early completion'),3,'early-complete')$$,'55000','PROJECT_PREREQUISITES_INCOMPLETE','AC-410 cannot finish before prerequisite');
reset role;
-- Existing attendance is the only payable claim; project approval allocates it.
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('att-create'),pg_temp.wid('att-create'),now(),
 jsonb_build_object('action','create','id',pg_temp.wid('attendance'),'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(pg_temp.wdate()::timestamp+interval '12 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,'reason','Synthetic attendance source'),0);
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('att-submit'),pg_temp.wid('att-submit'),now(),
 jsonb_build_object('action','submit','id',pg_temp.wid('attendance'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic attendance source'),1);
select pg_temp.wactor('creator');
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('att-approve'),pg_temp.wid('att-approve'),now(),
 jsonb_build_object('action','approve','id',pg_temp.wid('attendance'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic independent attendance'),2);
set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.project_time('fractional-time')||jsonb_build_object(
 'start_local',pg_temp.wdate()::text||'T10:00:00.500'),0,'fractional-time-create')$$,
 '22023','WORK_LOCAL_BOUNDARY_INVALID','AC-411 fractional time boundaries cannot silently change payable duration');
insert into project_responses values('time',pg_temp.pc(pg_temp.project_time('time'),0,'time-create'));
insert into project_responses values('submit',pg_temp.pc(pg_temp.time_action('time_submit','time'),1,'time-submit'));
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','time'),2,'time-self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','AC-411 time reviewer independent');
select pg_temp.wactor('reviewer');
insert into project_responses values('time-approved',pg_temp.pc(pg_temp.time_action('time_approve','time'),2,'time-approve'));
reset role;
insert into project_assertions select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('employee') and active),1,'AC-411 allocating attendance never makes another payable claim');
insert into project_assertions select is((select sum(extract(epoch from a.end_utc-a.start_utc))::bigint from people.work_allocations a where a.employee_id=pg_temp.wid('employee') and active),3600::bigint,'AC-411 exact allocated seconds');
insert into project_assertions select is((select amount from projects.time_costs),18::numeric,'AC-411 explicit synthetic costing separate from payroll');
insert into project_assertions select is((select amount from projects.billable_units),54::numeric,'AC-412 immutable whole unit retains exact commercial price');
insert into project_assertions select ok(not exists(select 1 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name like 'projects.%' and response::text~'bill_amount|cost_rate|hourly_rate|budget'),'AC-404 generic receipts exclude financial costing');
select pg_temp.wactor('reader');set local role authenticated;
insert into project_client_samples values('directory',api.projects_directory(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch')));
insert into project_client_samples values('plans',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'plans'));
insert into project_client_samples values('tasks',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'tasks'));
insert into project_client_samples values('resources',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'resources'));
insert into project_client_samples values('time',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'time'));
insert into project_client_samples values('units',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'units'));
insert into project_assertions select throws_ok($$select api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'cost')$$,'42501',null,'AC-404 operational viewer cannot read cost');
insert into project_assertions select throws_ok($$select api.projects_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project-plan'),'plan')$$,'42501',null,'AC-401 original capability required before receipt');
select pg_temp.wactor('creator');
insert into project_responses values('duplicate',pg_temp.pc(pg_temp.project_time('duplicate'),0,'duplicate-create'));
select pg_temp.pc(pg_temp.time_action('time_submit','duplicate'),1,'duplicate-submit');
select pg_temp.wactor('reviewer');
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','duplicate'),2,'duplicate-approve')$$,'23514','WORK_INTERVAL_CONFLICT','AC-411 same attendance segment cannot be allocated twice');
select pg_temp.wactor('creator');
select pg_temp.pc(pg_temp.project_time('direct',interval '11 hours',interval '12 hours',false),0,'direct-create');
select pg_temp.pc(pg_temp.time_action('time_submit','direct'),1,'direct-submit');
select pg_temp.wactor('reviewer');
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','direct'),2,'direct-approve')$$,'23514','WORK_INTERVAL_CONFLICT','AC-411 direct project claim cannot duplicate attendance pay');
insert into project_assertions select throws_ok($$select pg_temp.pc(jsonb_build_object('action','close','id',pg_temp.wid('project'),'reason','Synthetic closure'),3,'close-open')$$,'55000','PROJECT_CLOSURE_IMPACT_REQUIRED','AC-412 closure cannot hide open sources');
select pg_temp.wactor('creator');
select pg_temp.pc(pg_temp.project_create('competing'),0,'competing-create');
select pg_temp.pc(pg_temp.project_plan('competing','competing-plan'),1,'competing-plan-create');
select pg_temp.wactor('reviewer');
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.plan_action('approve_plan','competing','competing-plan'),2,'competing-approve')$$,'23514','PROJECT_RESOURCE_CAPACITY_CONFLICT','AC-410 approved projects cannot reserve the same employee capacity');
reset role;
insert into project_assertions select ok((select bool_and(not active) from projects.resource_slots where plan_id=pg_temp.wid('competing-plan')),'AC-410 failed competing approval is atomic');
select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.project_plan('competing','cycle-plan')||jsonb_build_object('tasks',
 jsonb_build_array(jsonb_build_object('id',pg_temp.wid('task'),'name','Delivery','owner_id',pg_temp.wid('employee'),'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',7200,'dependencies',jsonb_build_array(pg_temp.wid('task2'))),
 jsonb_build_object('id',pg_temp.wid('task2'),'name','Review','owner_id',pg_temp.wid('employee'),'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',0,'dependencies',jsonb_build_array(pg_temp.wid('task'))))),2,'cycle-plan')$$,'23514','PROJECT_TASK_CYCLE','AC-410 cycles rejected before effects');
select pg_temp.wactor('reviewer');
insert into project_client_samples values('cost',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'cost'));
insert into project_client_samples values('resource_cost',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'resource_cost'));
insert into project_client_samples values('time_cost',api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('project'),'time_cost'));
select pg_temp.pc(pg_temp.time_action('time_cancel','time'),3,'time-cancel');
reset role;
insert into project_assertions select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('employee') and active),1,'AC-411 cancellation releases allocation but preserves attendance claim');
insert into project_assertions select is((select count(*)::integer from people.work_allocations where employee_id=pg_temp.wid('employee') and active),0,'AC-411 cancellation reverses exact original allocations');
insert into project_assertions select is((select status from projects.billable_units where source_id=(select current_revision_id from projects.time_entries where id=pg_temp.wid('time'))),'cancelled','AC-412 cancellation retains immutable original unit');
-- A second employee establishes a real direct project claim, then a late
-- outbox failure proves claim/allocation/unit/cost/consumption atomicity.
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pc(pg_temp.project_create('dedicated'),0,'dedicated-create');
select pg_temp.pc(jsonb_set(pg_temp.project_plan('dedicated','dedicated-plan'),'{resources,0,employee_id}',to_jsonb(pg_temp.wid('third'))),1,'dedicated-plan');
select pg_temp.wactor('reviewer');
select pg_temp.pc(pg_temp.plan_action('approve_plan','dedicated','dedicated-plan'),2,'dedicated-approve');
select pg_temp.wactor('creator');
select pg_temp.pc(pg_temp.project_time('dedicated-time',interval '10 hours',interval '11 hours',false)||
 jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third'),'resource_slot_id',pg_temp.wid('dedicated-plan-slot')),0,'dedicated-time-create');
select pg_temp.pc(pg_temp.time_action('time_submit','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),1,'dedicated-time-submit');
reset role;
create function pg_temp.project_outbox_failure() returns trigger language plpgsql as $$begin
 if new.command_id=pg_temp.wid('dedicated-time-approve') then raise exception using errcode='P0001',message='SYNTHETIC_PROJECT_OUTBOX_FAILURE';end if;return new;end $$;
create trigger w4_project_rollback_failure before insert on core.outbox_events for each row execute function pg_temp.project_outbox_failure();
select pg_temp.wactor('reviewer');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_approve','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),2,'dedicated-time-approve')$$,
 'P0001','SYNTHETIC_PROJECT_OUTBOX_FAILURE','AC-411 late outbox failure rolls back the whole time approval');
reset role;
insert into project_assertions select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('third')),0,'AC-411 failed approval leaves no direct claim');
insert into project_assertions select is((select count(*)::integer from projects.billable_units where project_id=pg_temp.wid('dedicated')),0,'AC-412 failed approval leaves no billing unit');
insert into project_assertions select is((select count(*)::integer from projects.time_costs where project_id=pg_temp.wid('dedicated')),0,'AC-411 failed approval leaves no private cost');
insert into project_assertions select is((select status from projects.time_entries where id=pg_temp.wid('dedicated-time')),'submitted','AC-411 failed approval retains the exact submitted revision');
drop trigger w4_project_rollback_failure on core.outbox_events;
set local role authenticated;
select pg_temp.pc(pg_temp.time_action('time_approve','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),2,'dedicated-time-approve');
insert into project_assertions select is(jsonb_array_length(api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('dedicated'),'time',pg_temp.wid('dedicated-time'))->'rows'),1,'AC-411 exact target time read is available beyond directory pages');
insert into project_assertions select is(jsonb_array_length(api.projects_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('dedicated'),'plans',pg_temp.wid('dedicated-plan'))->'rows'),1,'AC-410 exact original plan read is bounded');
reset role;
insert into project_assertions select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('third') and active),1,'AC-411 successful direct time owns one payable claim');
insert into project_assertions select is((select projects.payroll_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('third'),id)->>'paid_seconds' from people.work_claims where employee_id=pg_temp.wid('third') and active),'3600','AC-411 payroll provider verifies exact approved direct claim');
insert into project_assertions select throws_ok($$select projects.payroll_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),(select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')))$$,
 '55000','PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED','AC-411 attendance allocations cannot duplicate project payroll eligibility');
insert into project_assertions select ok(not has_function_privilege('authenticated','projects.payroll_source(uuid,uuid,uuid,uuid,uuid)','EXECUTE'),'AC-404 payroll source provider is owner-only');
insert into people.work_input_seals(tenant_id,legal_entity_id,employee_id,run_id,claim_id,source_version,seconds,digest)
 select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('third'),pg_temp.wid('synthetic-payroll-run'),id,3,3600,repeat('a',64)
 from people.work_claims where employee_id=pg_temp.wid('third') and active;
set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.time_action('time_cancel','dedicated-time')||jsonb_build_object('project_id',pg_temp.wid('dedicated'),'employee_id',pg_temp.wid('third')),3,'sealed-project-cancel')$$,
 '55000','PAYROLL_INPUT_SEALED','AC-411 consumed direct time requires a linked payroll correction');
select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('dedicated'),'task_id',pg_temp.wid('task'),'progress',10000,'reason','Synthetic completed original task'),3,'dedicated-progress');
select pg_temp.wactor('creator');
select pg_temp.pc(jsonb_set(pg_temp.project_plan('dedicated','revised-plan'),'{resources,0,employee_id}',to_jsonb(pg_temp.wid('third'))),4,'dedicated-revise');
select pg_temp.wactor('reviewer');
select pg_temp.pc(pg_temp.plan_action('approve_plan','dedicated','revised-plan'),5,'dedicated-revise-approve');
insert into project_assertions select throws_ok($$select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('dedicated'),'task_id',pg_temp.wid('task2'),'progress',10000,'reason','Synthetic revised task'),6,'dedicated-revised-complete')$$,
 '55000','PROJECT_PREREQUISITES_INCOMPLETE','AC-410 revised plan cannot inherit completion from old dependency graph');
select pg_temp.wactor('creator');
insert into project_client_samples values('resolution',api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600));
insert into project_client_samples values('second_resolution',api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600,1));
insert into project_assertions select is(api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600,1)#>>'{resolution,local_datetime}',to_char(pg_temp.wdate()::timestamp+interval '10 hours 1 second','YYYY-MM-DD"T"HH24:MI:SS'),'AC-411 resolver retains original whole-second boundary');
insert into project_assertions select is(jsonb_array_length(api.projects_calendar_candidates(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('calendar-version'),pg_temp.wdate(),600)#>'{resolution,candidates}'),1,'AC-410 named project reservation resolves original published zone');
select pg_temp.pc(pg_temp.project_plan('project','stale-plan'),3,'stale-plan-create');
select pg_temp.pc(jsonb_build_object('action','progress','id',pg_temp.wid('project'),'task_id',pg_temp.wid('task'),'progress',10000,'reason','Synthetic independent current-plan progress'),4,'stale-plan-progress');
select pg_temp.wactor('reviewer');
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.plan_action('approve_plan','project','stale-plan'),5,'stale-plan-approve')$$,'55000','PROJECT_PLAN_STALE','AC-410 concurrent progress cannot approve a stale plan basis');
select pg_temp.pc(pg_temp.plan_action('reject_plan','project','stale-plan'),5,'stale-plan-reject');
reset role;
insert into project_assertions select is((select status from projects.plans where id=pg_temp.wid('stale-plan')),'rejected','AC-410 independent original-digest rejection resolves a stale pending basis');
select pg_temp.wactor('creator','aal1');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pc(pg_temp.project_create(),0,'project-create')$$,'42501',null,'AC-401 MFA checked before replay');
select pg_temp.wactor('outsider');
insert into project_assertions select throws_ok($$select api.projects_directory(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$$,'42501',null,'AC-401 outsider cannot read projects');
reset role;

-- Runs after the actual project candidate suite, inside the same outer rollback.
reset role;select pg_temp.wactor('creator');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.finance',true) on conflict(plan_code,entitlement_code) do update set enabled=true;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p where p.module in('sales','workflow','finance') on conflict do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p where p.code like 'projects.%' on conflict do nothing;
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by)
values(pg_temp.wid('pf.customer'),pg_temp.wid('tenant'),'PF-CUSTOMER','Synthetic customer','Synthetic customer','customer',1000000,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.wid('pf.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),'PF-'||upper(x),'Synthetic '||x,
 case when x in('receivable_control','bank','tax') then 'asset' when x='liability' then 'liability' when x='revenue' then 'revenue' else 'expense' end,
 case when x in('liability','revenue') then 'credit' else 'debit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
from unnest(array['expense','liability','tax','receivable_control','bank','revenue','rounding']) x;
insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),x,pg_temp.wid('pf.'||x),pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['receivable_control','rounding']) x;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.wid('pf.period'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Synthetic project period',pg_temp.wdate()-400,pg_temp.wdate()+400,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
values(pg_temp.wid('pf.bank'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'PF-BANK','Synthetic recorded bank','bank',pg_temp.wid('pf.bank'),'LKR',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.wid('pf.unit'),pg_temp.wid('tenant'),'PF-UNIT','Whole billing unit','ea','quantity',6,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,revenue_account_id,created_by,updated_by)
values(pg_temp.wid('pf.product'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'PF-SERVICE','Synthetic project service','service',pg_temp.wid('pf.unit'),'none',pg_temp.wid('pf.revenue'),pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),x,'PF-'||x||'-',pg_temp.wid('creator'),pg_temp.wid('creator') from unnest(array['sales_invoice','sales_return','journal_entry']) x;
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.wid('pf.workflow'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'sales_invoice','Synthetic independent project invoice','active',
'{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["approved","posted"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","cancelled"]],"requires_approval":true,"separate_poster":true}',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.wid('pf.step'),pg_temp.wid('tenant'),pg_temp.wid('pf.workflow'),pg_temp.wid('reviewer.role'),1,pg_temp.wid('creator'),pg_temp.wid('creator'));
select pg_temp.pc(pg_temp.project_create('finance')||jsonb_build_object('customer_id',pg_temp.wid('pf.customer')),0,'pf.create');
select pg_temp.pc(jsonb_set(jsonb_set(pg_temp.project_plan('finance','finance-plan'),'{resources}','[]'::jsonb),'{tasks,0,planned_seconds}','0'::jsonb),1,'pf.plan');select pg_temp.wactor('reviewer');select pg_temp.pc(pg_temp.plan_action('approve_plan','finance','finance-plan'),2,'pf.approve');
create function pg_temp.pfc(p jsonb,v bigint,k text) returns jsonb language sql as $$
select api.projects_finance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.command.'||k),pg_temp.wid('pf.command.'||k),now(),p,v) $$;
create function pg_temp.pfe(k text default 'expense') returns jsonb language sql as $$
 select jsonb_build_object('action','expense_create','id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'employee_id',pg_temp.wid('employee'),'external_reference','PF-'||k,'service_date',pg_temp.wdate(),'purpose','Synthetic approved travel','evidence_reference','SYNTHETIC-PF-01','original_currency','LKR','original_precision',2,'net','0.03','tax','0','gross','0.03','tax_definition_id',null,'tax_version',null,'no_tax_reason','Synthetic no tax','exchange_rate_id',null,'exchange_rate_version',null,'expense_account_id',pg_temp.wid('pf.expense'),'tax_account_id',null,'liability_account_id',pg_temp.wid('pf.liability'),'billable',true,'bill_amount','0.05','allocations',jsonb_build_array(jsonb_build_object('task_id',pg_temp.wid('task'),'weight',1),jsonb_build_object('task_id',pg_temp.wid('task2'),'weight',1)),'reason','Synthetic expense preparation') $$;
create function pg_temp.pfa(a text,k text default 'expense') returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'posting_date',pg_temp.wdate(),'digest',(select digest from projects.expense_revisions where expense_id=pg_temp.wid('pf.'||k) order by version desc limit 1),'reason','Synthetic expense decision')-case when a in('expense_approve','expense_reject') then array['posting_date'] when a in('expense_post','expense_reverse') then array['digest'] else array['posting_date','digest'] end $$;
create temporary table project_finance_client_samples(label text primary key,body jsonb);grant insert,select on project_finance_client_samples to authenticated;
insert into project_assertions select ok(not has_table_privilege('authenticated','projects.expense_revisions','SELECT'),'finance private revisions have no direct reads');
insert into project_assertions select ok(not has_function_privilege('authenticated','projects.finance_access(uuid,uuid,uuid,text,boolean)','EXECUTE'),'finance helpers cannot bypass API');
select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select is(pg_temp.pfc(pg_temp.pfe(),0,'create')->'entity'->>'status','draft','expense create preserves draft');
insert into project_assertions select is(pg_temp.pfc(pg_temp.pfe(),0,'create')->'entity'->>'version','1','exact expense replay');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfe()||'{"gross":"0.04"}',0,'create')$$,'22023','IDEMPOTENCY_MISMATCH','changed money cannot replay');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfe('bad')||'{"net":0.03}',0,'number')$$,'22023','PROJECT_AMOUNT_INVALID','numbers cannot replace decimal strings');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfe('bad')||'{"evidence_reference":"https://private.invalid"}',0,'url')$$,'22023','PROJECT_ATTACHMENT_PROVIDER_REQUIRED','unsafe attachment URL rejected');
select pg_temp.pfc(pg_temp.pfa('expense_submit'),1,'submit');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_approve'),2,'self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','expense approver independent');
select pg_temp.wactor('reviewer');select pg_temp.pfc(pg_temp.pfa('expense_approve'),2,'approve');
insert into project_finance_client_samples values('expenses',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses'));
reset role;
insert into project_assertions select is((select sum(amount) from projects.expense_allocations where expense_id=pg_temp.wid('pf.expense')),0.03::numeric,'ordered allocation preserves original gross');
insert into project_assertions select is((select amount from projects.expense_allocations where expense_id=pg_temp.wid('pf.expense') and ordinal=1),0.02::numeric,'half-even first allocation retained');
insert into project_assertions select is((select count(*)::integer from projects.expense_ownership where expense_id=pg_temp.wid('pf.expense')),1,'one liability ownership claim');
insert into project_assertions select throws_ok($$select projects.finance_closure_guard(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('finance'))$$,'55000','PROJECT_FINANCE_CLOSURE_IMPACT_REQUIRED','approved expense blocks closure');
set local role authenticated;select pg_temp.wactor('creator');select pg_temp.pfc(pg_temp.pfa('expense_post'),3,'post');
insert into project_finance_client_samples values('obligations',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'obligations'));
select pg_temp.pfc(jsonb_build_object('action','settle','id',pg_temp.wid('pf.settlement'),'project_id',pg_temp.wid('finance'),'obligation_id',pg_temp.wid('pf.expense'),'posting_date',pg_temp.wdate(),'amount','0.01','bank_id',pg_temp.wid('pf.bank'),'bank_version',1,'evidence_reference','SYNTHETIC-BANK-RECORD','reason','Synthetic recorded settlement'),0,'settle');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_reverse'),4,'reverse-blocked')$$,'55000','PROJECT_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL','active partial settlement blocks expense reversal');
insert into project_finance_client_samples values('settlements',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'settlements'));
select pg_temp.pfc(jsonb_build_object('action','settlement_reverse','id',pg_temp.wid('pf.settlement'),'project_id',pg_temp.wid('finance'),'posting_date',pg_temp.wdate(),'reason','Synthetic original settlement reversal'),1,'settlement-reverse');
reset role;
insert into project_assertions select is((select sum(amount) from projects.reimbursement_effects where obligation_id=pg_temp.wid('pf.expense')),0.03::numeric,'settlement reversal restores exact obligation');
insert into project_assertions select is((select sum(base_debit-base_credit) from finance.journal_lines where journal_entry_id in(select journal_id from projects.reimbursement_effects)),0::numeric,'expense and settlement journals conserved');
create function pg_temp.pfb(k text default 'batch') returns jsonb language sql security definer set search_path='' as $$
select jsonb_build_object('action','billing_prepare','id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'invoice_id',pg_temp.wid('pf.invoice.'||k),'document_date',(now() at time zone 'UTC')::date,'due_date',(now() at time zone 'UTC')::date,'exchange_rate_id',null,'units',jsonb_build_array(jsonb_build_object('unit_id',u.id,'source_version',u.source_version,'source_digest',u.source_digest,'product_id',pg_temp.wid('pf.product'),'product_version',1,'tax_definition_id',null,'tax_version',null,'description','Synthetic whole approved expense')),'reason','Synthetic billing preparation') from projects.billable_units u where u.source_kind='expense' and u.source_id=pg_temp.wid('pf.expense') $$;
create function pg_temp.pfba(a text,v bigint,k text default 'batch') returns jsonb language sql as $$select jsonb_build_object('action',a,'id',pg_temp.wid('pf.'||k),'project_id',pg_temp.wid('finance'),'invoice_version',v,'reason','Synthetic installed sales workflow') $$;
set local role authenticated;select pg_temp.pfc(pg_temp.pfb(),0,'billing-prepare');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfb('duplicate'),0,'billing-duplicate')$$,'55000','PROJECT_BILLING_SOURCE_UNAVAILABLE','source cannot reserve twice');
reset role;
insert into project_assertions select throws_ok($$update sales.sales_invoice_lines set quantity=2 where document_id=pg_temp.wid('pf.invoice.batch')$$,'55000','PROJECT_LINKED_INVOICE_IMMUTABLE','ordinary invoice line editing blocked');
insert into project_assertions select throws_ok($$update sales.sales_invoices set grand_total=1 where id=pg_temp.wid('pf.invoice.batch')$$,'55000','PROJECT_LINKED_INVOICE_IMMUTABLE','ordinary invoice money editing blocked');
insert into project_assertions select is((select quantity from sales.sales_invoice_lines where document_id=pg_temp.wid('pf.invoice.batch')),1::numeric,'whole unit avoids rounded fractional hours');
set local role authenticated;select pg_temp.pfc(pg_temp.pfba('billing_submit',1),1,'billing-submit');select pg_temp.wactor('reviewer');
select pg_temp.pfc(pg_temp.pfba('billing_decide',2)||'{"decision":"approved"}',2,'billing-decide');
insert into project_assertions select throws_ok($$select api.post_sales_invoice(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('id',pg_temp.wid('pf.invoice.batch')),3)$$,'42501','PROJECT_BILLING_INTENT_REQUIRED','direct sales posting cannot consume linked invoice');
reset role;
create function pg_temp.pf_billing_late_failure() returns trigger language plpgsql as $$begin if new.aggregate_id=pg_temp.wid('pf.batch') and new.action='billing_post' then raise exception using errcode='P0001',message='SYNTHETIC_BILLING_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_billing_late_failure before insert on projects.finance_events for each row execute function pg_temp.pf_billing_late_failure();
set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfba('billing_post',3),3,'billing-late')$$,'P0001','SYNTHETIC_BILLING_LATE_FAILURE','late billing failure rolls back installed journal and source consumption');
reset role;
insert into project_assertions select ok((select status='approved' and posted_at is null from sales.sales_invoices where id=pg_temp.wid('pf.invoice.batch')) and(select status='reserved' from projects.billable_units where source_kind='expense' and source_id=pg_temp.wid('pf.expense')) and not exists(select 1 from core.command_receipts where command_id=pg_temp.wid('pf.command.billing-late')) and not exists(select 1 from projects.billing_intents),'late billing failure retains exact original reservation without receipt or posting intent');
drop trigger synthetic_billing_late_failure on projects.finance_events;
set local role authenticated;
select pg_temp.pfc(pg_temp.pfba('billing_post',3),3,'billing-post');
insert into project_finance_client_samples values('billing',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'billing'));
insert into project_finance_client_samples values('units',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'units'));
insert into project_finance_client_samples values('margin',api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate()));
insert into project_finance_client_samples values('history',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'history'));
reset role;
insert into project_assertions select is((select status from projects.billable_units where source_kind='expense' and source_id=pg_temp.wid('pf.expense')),'billed','invoice posting consumes original source');
insert into project_assertions select is((select count(*)::integer from projects.billing_intents),0,'protected transaction intent leaves no residue');
insert into project_assertions select ok(not exists(select 1 from core.command_receipts where tenant_id=pg_temp.wid('tenant') and command_name like 'projects.finance.%' and response::text ~ 'base_gross|expense_account|bill_amount|gross|net|tax|evidence_reference'),'generic finance receipts exclude private values');
select pg_temp.wactor('reader');set local role authenticated;
insert into project_assertions select throws_ok($$select api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses')$$,'42501',null,'ordinary project viewer has no private costs');
select pg_temp.wactor('creator','aal1');select throws_ok($$select pg_temp.pfc(pg_temp.pfe(),0,'create')$$,'42501',null,'finance MFA checked before replay');reset role;
insert into project_assertions select ok((select count(*)=14 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class where relnamespace='projects'::regnamespace and relname=any(array['expenses','expense_revisions','expense_allocations','expense_decisions','expense_ownership','reimbursements','reimbursement_effects','expense_settlements','billing_batches','billing_links','billing_intents','finance_events','payroll_billing_effects','service_cost_revisions'])),'all finance-owned tables force RLS');
insert into project_assertions select ok(not has_function_privilege('authenticated','projects.payroll_billing_impact(uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'payroll billing impact is protected provider-only');
select pg_temp.wactor('creator');
create function pg_temp.pf_late_failure() returns trigger language plpgsql as $$begin if new.aggregate_id=pg_temp.wid('pf.late') then raise exception using errcode='P0001',message='SYNTHETIC_FINANCE_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_late_failure before insert on projects.finance_events for each row execute function pg_temp.pf_late_failure();
set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfe('late'),0,'late')$$,'P0001','SYNTHETIC_FINANCE_LATE_FAILURE','late event failure rolls back expense atomically');reset role;
insert into project_assertions select ok(not exists(select 1 from projects.expenses where id=pg_temp.wid('pf.late')) and not exists(select 1 from core.command_receipts where command_id=pg_temp.wid('pf.command.late')),'late failure leaves neither expense nor receipt');
insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount,payable_seconds) values(pg_temp.wid('pf.payroll.unit'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('finance'),pg_temp.wid('branch'),'time',pg_temp.wid('pf.payroll.revision'),1,repeat('a',64),12.00,1800);
insert into project_assertions select is(projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction')),'validate')->>'original_amount','12.000000','billing impact freezes original exact amount');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction')),'apply');
insert into project_assertions select is((select status from projects.billable_units where id=pg_temp.wid('pf.payroll.unit')),'cancelled','apply cancels original available source once');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction'),'operational_mode','reverse'),'validate');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.payroll.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.payroll.correction')),'reverse');
insert into project_assertions select is((select status from projects.billable_units where id=pg_temp.wid('pf.payroll.unit')),'cancelled','reverse retains original cancelled unit for fresh revision lineage');
insert into project_assertions select is((select count(*)::integer from projects.payroll_billing_effects where correction_id=pg_temp.wid('pf.payroll.correction')),2,'apply and reverse effects immutable separate records');
-- A second real installed sales workflow exercises immutable original credits.
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
select pg_temp.wid('pf.return.workflow'),tenant_id,legal_entity_id,'sales_return','Synthetic independent source credit',status,lifecycle,created_by,updated_by from workflow.workflow_definitions where id=pg_temp.wid('pf.workflow');
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.wid('pf.return.step'),pg_temp.wid('tenant'),pg_temp.wid('pf.return.workflow'),pg_temp.wid('reviewer.role'),1,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount,payable_seconds) values(pg_temp.wid('pf.credit.unit'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('finance'),pg_temp.wid('branch'),'time',pg_temp.wid('pf.credit.revision'),1,repeat('b',64),12.00,1800);
create function pg_temp.pf_credit_billing() returns jsonb language sql security definer set search_path='' as $$select pg_temp.pfb('credit')||jsonb_build_object('units',jsonb_build_array(jsonb_build_object('unit_id',pg_temp.wid('pf.credit.unit'),'source_version',1,'source_digest',repeat('b',64),'product_id',pg_temp.wid('pf.product'),'product_version',1,'tax_definition_id',null,'tax_version',null,'description','Synthetic original billed time'))) $$;
set local role authenticated;select pg_temp.wactor('creator');select pg_temp.pfc(pg_temp.pf_credit_billing(),0,'credit.prepare');
reset role;
insert into project_assertions select throws_ok($$update sales.sales_invoices set status='cancelled' where id=pg_temp.wid('pf.invoice.credit')$$,'42501','PROJECT_BILLING_INTENT_REQUIRED','protected linked draft status cannot bypass wrapper intent');
set local role authenticated;
insert into project_assertions select throws_ok($$select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('document_type','sales_invoice','document_id',pg_temp.wid('pf.invoice.credit'),'action','cancel','reason','Synthetic generic bypass'),1)$$,'55000','WORKFLOW_TRANSITION_INVALID','installed state rejects generic draft cancellation before source mutation');
select pg_temp.pfc(pg_temp.pfba('billing_submit',1,'credit'),1,'credit.submit');select pg_temp.wactor('reviewer');select pg_temp.pfc(pg_temp.pfba('billing_decide',2,'credit')||'{"decision":"approved"}',2,'credit.decide');select pg_temp.pfc(pg_temp.pfba('billing_post',3,'credit'),3,'credit.post');reset role;
insert into project_assertions select throws_ok($$select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.credit.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.credit.correction')),'validate')$$,'55000','PROJECT_POSTED_ORIGINAL_CREDIT_REQUIRED','billed source requires actual original posted credit');
create function pg_temp.pf_credit() returns jsonb language sql security definer set search_path='' as $$select jsonb_build_object('id',pg_temp.wid('pf.credit.document'),'customer_id',pg_temp.wid('pf.customer'),'document_date',(now() at time zone 'UTC')::date,'currency_code','LKR','reason','Synthetic original source credit','lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.wid('pf.credit.line'),'sales_invoice_line_id',l.id,'product_id',l.product_id,'base_quantity','1.000000','quantity','1.000000','unit_id',l.unit_id,'conversion_numerator','1','conversion_denominator','1','disposition','no_restock'))) from sales.sales_invoice_lines l where document_id=pg_temp.wid('pf.invoice.credit') $$;
set local role authenticated;select pg_temp.wactor('creator');
select api.upsert_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),pg_temp.pf_credit(),null);
select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('pf.credit.document'),'action','submit','reason','Synthetic credit submission'),1);
select pg_temp.wactor('reviewer');select api.transition_operational_document(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('document_type','sales_return','document_id',pg_temp.wid('pf.credit.document'),'action',null,'decision','approved','note','Synthetic independent original credit'),2);
select api.post_sales_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),gen_random_uuid(),gen_random_uuid(),now(),jsonb_build_object('id',pg_temp.wid('pf.credit.document')),3);reset role;
set local role authenticated;
insert into project_assertions select is(api.projects_payroll_credit_choices(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.credit.revision'))#>>'{rows,0,id}',pg_temp.wid('pf.credit.line')::text,'named correction selector returns exact posted original credit');reset role;
insert into project_assertions select ok(not has_function_privilege('authenticated','projects.service_payroll_billing_impact(uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'service billing impact remains protected provider-only');
insert into project_assertions select is(projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.credit.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.credit.correction'),'billing_credit_line_ids',jsonb_build_array(pg_temp.wid('pf.credit.line'))),'validate')->>'original_amount','12.000000','posted original credit freezes exact whole source impact');
select projects.payroll_billing_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.credit.revision'),jsonb_build_object('correction_id',pg_temp.wid('pf.credit.correction'),'billing_credit_line_ids',jsonb_build_array(pg_temp.wid('pf.credit.line'))),'apply');
insert into project_assertions select is((select status from projects.billable_units where id=pg_temp.wid('pf.credit.unit')),'billed','posted original credits never release billed source');
insert into project_assertions select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate())->>'posted_credits')::numeric,12::numeric,'as-of margin includes exact original credit revenue');
-- Private cost rows exercise exact source-version, recorded/effective cutoffs.
-- Real service imports and linked callbacks are exercised by the service suite.
insert into project_finance_client_samples values('cost_asof',to_jsonb(clock_timestamp()-interval '10 seconds'));
insert into projects.service_cost_revisions(id,tenant_id,legal_entity_id,branch_id,project_id,provider_source_id,source_revision_id,source_version,source_digest,currency_code,precision,service_date,payable_seconds,hourly_cost,amount,status,recorded_by,recorded_at)
select pg_temp.wid('pf.service.cost.'||v),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.service.labor'),pg_temp.wid('pf.service.revision.'||v),v,repeat('c',64),'LKR',2,pg_temp.wdate(),
 case when v=3 then 0 when v=2 then 1800 else 3600 end,18,case when v=3 then 0 when v=2 then 9 else 18 end,
 case when v=3 then 'cancelled' else 'approved' end,pg_temp.wid('creator'),
 ((select body#>>'{}' from project_finance_client_samples where label='cost_asof')::timestamptz)+(v-1)*interval '1 second'
from generate_series(1,4) v;
create function pg_temp.pf_cost_margin(v integer,d date default pg_temp.wdate()) returns jsonb language sql as $$
 select api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),
 ((select body#>>'{}' from project_finance_client_samples where label='cost_asof')::timestamptz)+(v-1)*interval '1 second',d) $$;
insert into project_assertions select is(pg_temp.pf_cost_margin(1)->>'service_cost','18.000000','AC-428 as-of margin includes original protected service cost');
insert into project_assertions select is(pg_temp.pf_cost_margin(2)->>'service_cost','9.000000','AC-428 correction replaces cost at its recorded cutoff');
insert into project_assertions select is(pg_temp.pf_cost_margin(3)->>'service_cost','0.000000','AC-428 immutable zero removal stops original service cost');
insert into project_assertions select is(pg_temp.pf_cost_margin(4)->>'service_cost','18.000000','AC-428 fresh reversal restores cost exactly once');
insert into project_assertions select is(pg_temp.pf_cost_margin(4,pg_temp.wdate()-1)->>'service_cost','0','AC-428 service date independently bounds margin');
insert into project_assertions select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate())->>'margin')::numeric,-17.98::numeric,'AC-428 service cost subtraction reconciles original revenue and expense');
insert into project_assertions select throws_ok($$update projects.service_cost_revisions set amount=0 where id=pg_temp.wid('pf.service.cost.1')$$,'55000','PROJECT_HISTORY_IMMUTABLE','AC-428 historical internal service cost cannot be edited');
insert into project_assertions select ok(not has_function_privilege('authenticated','projects.service_payroll_cost_impact(uuid,uuid,uuid,uuid,uuid)','EXECUTE') and not has_table_privilege('authenticated','projects.service_cost_revisions','SELECT'),'AC-428 private cost provider and table have no client access');
set local role authenticated;select pg_temp.wactor('creator');
insert into project_finance_client_samples values('serviceCosts',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'serviceCosts'));
reset role;
insert into projects.service_cost_revisions(id,tenant_id,legal_entity_id,branch_id,project_id,provider_source_id,source_revision_id,source_version,source_digest,currency_code,precision,service_date,payable_seconds,hourly_cost,amount,status,recorded_by)
values(pg_temp.wid('pf.service.cost.5'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.service.labor'),pg_temp.wid('pf.service.revision.5'),5,repeat('d',64),'LKR',2,pg_temp.wdate()+1,3600,18,18,'approved',pg_temp.wid('creator'));
insert into project_assertions select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate())->>'service_cost')::numeric,0::numeric,'AC-428 moving source date cannot resurrect superseded earlier cost');
insert into project_assertions select is((api.projects_margin(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),clock_timestamp(),pg_temp.wdate()+1)->>'service_cost')::numeric,18::numeric,'AC-428 current moved source cost appears once at its actual service date');
set local role authenticated;
select pg_temp.wactor('reader');
insert into project_assertions select throws_ok($$select api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'serviceCosts')$$,'42501',null,'AC-428 ordinary project view cannot reveal internal service costs');
reset role;update billing.plan_entitlements set enabled=false where plan_code='w4_integrated_rollback' and entitlement_code='module.finance';
select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfe(),0,'create')$$,'42501','PROJECT_FINANCE_ENTITLEMENT_REQUIRED','financial entitlement is checked before confirmed replay');
insert into project_assertions select throws_ok($$select pg_temp.pf_cost_margin(1)$$,'42501','PROJECT_FINANCE_ENTITLEMENT_REQUIRED','financial entitlement gates private margin reads');
reset role;update billing.plan_entitlements set enabled=true where plan_code='w4_integrated_rollback' and entitlement_code='module.finance';
delete from project_finance_client_samples where label='cost_asof';


-- UNAPPLIED protected project-expense evidence candidate. No role/plan grants.
-- Separate privacy unit, bucket and worker; no core.files or private-HR linkage.
create schema expense_private;
revoke all on schema expense_private from public,anon,authenticated,service_role;
insert into core.permissions(code,module,description,privileged) values
 ('projects.expenses.evidence.view','projects','Read a scoped private expense evidence document',true),
 ('projects.expenses.evidence.export','projects','Export a scoped expense evidence document',true),
 ('projects.expenses.retention.manage','projects','Set expense evidence retention and document holds',true)
on conflict(code) do nothing;
create table expense_private.policies(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 retention_days integer not null check(retention_days between 1 and 3650),
 purpose text not null,digest_key bytea not null default extensions.gen_random_bytes(32),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create table expense_private.documents(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 project_id uuid not null,expense_id uuid not null,policy_id uuid not null references expense_private.policies(id),
 version bigint not null default 1 check(version between 1 and 9007199254740990),
 content_version bigint not null default 1 check(content_version=1),digest text not null check(digest~'^[a-f0-9]{64}$'),
 mime text not null check(mime in('text/plain','image/png','image/jpeg','application/pdf')),
 byte_size integer not null check(byte_size between 1 and 10485760),checksum text not null check(checksum~'^[a-f0-9]{64}$'),
 purpose text not null,status text not null default 'reserved' check(status in('reserved','verified','active','retired','purging','purged')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 verified_at timestamptz,activated_at timestamptz,retired_at timestamptz,purge_after timestamptz,purged_at timestamptz,
 hold_reason text,hold_review_date date,
 unique(tenant_id,legal_entity_id,branch_id,project_id,expense_id,id),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check((hold_reason is null)=(hold_review_date is null))
);
create table expense_private.events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 document_id uuid not null references expense_private.documents(id),action text not null,
 version bigint not null,reason text,actor_id uuid references auth.users(id),recorded_at timestamptz not null default clock_timestamp()
);
create table expense_private.tickets(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references expense_private.documents(id),
 user_id uuid not null references auth.users(id),operation text not null check(operation in('upload','download','export')),
 issued_aal text not null,expires_at timestamptz not null default clock_timestamp()+interval '30 seconds',
 consumed_at timestamptz,verified_at timestamptz
);
create table expense_private.worker_readiness(
 contract text primary key check(contract='w4-expense-evidence-v1'),artifact_digest text not null check(artifact_digest~'^[a-f0-9]{64}$'),
 storage_probe_digest text not null check(storage_probe_digest~'^[a-f0-9]{64}$'),verified_at timestamptz not null default clock_timestamp()
);
create table expense_private.purge_jobs(
 id uuid primary key default gen_random_uuid(),document_id uuid not null unique references expense_private.documents(id),
 lease_id uuid,lease_until timestamptz,status text not null default 'pending' check(status in('pending','complete')),
 completed_at timestamptz
);
create index expense_evidence_scope on expense_private.documents(tenant_id,legal_entity_id,branch_id,project_id,expense_id,id);
create index expense_evidence_expiry on expense_private.documents(status,purge_after,created_at);
create index expense_evidence_tickets_expiry on expense_private.tickets(expires_at);
create trigger immutable before update or delete on expense_private.policies for each row execute function projects.immutable();
create trigger immutable before update or delete on expense_private.events for each row execute function projects.immutable();
create function expense_private.document_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or(to_jsonb(new)-array['version','status','verified_at','activated_at','retired_at','purge_after','purged_at','hold_reason','hold_review_date'])
  is distinct from(to_jsonb(old)-array['version','status','verified_at','activated_at','retired_at','purge_after','purged_at','hold_reason','hold_review_date']) then
  raise exception using errcode='55000',message='EXPENSE_EVIDENCE_IMMUTABLE';end if;
 return new;
end $$;
create trigger immutable_content before update or delete on expense_private.documents for each row execute function expense_private.document_guard();
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('jentra-project-expense-private','jentra-project-expense-private',false,10485760,array['text/plain','image/png','image/jpeg','application/pdf']);
create policy wave4_expense_evidence_no_direct_storage on storage.objects as restrictive
 for all to anon,authenticated using(bucket_id<>'jentra-project-expense-private') with check(bucket_id<>'jentra-project-expense-private');

create function expense_private.lock_scope(t uuid,e uuid) returns void language plpgsql set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
end $$;
create function expense_private.require_access(t uuid,e uuid,b uuid,p uuid,x uuid,cap text) returns void
language plpgsql security definer set search_path='' as $$begin
 perform projects.finance_access(t,e,b,'projects.cost.view',true);
 if cap not in('projects.cost.view','projects.expenses.manage','projects.expenses.evidence.view','projects.expenses.evidence.export','projects.expenses.retention.manage') then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 perform core.wave3_require_scope(t,'projects.expenses.evidence.view',e,b);
 perform core.wave3_require_scope(t,cap,e,b);
 if p is not null and not exists(select 1 from projects.register r where r.tenant_id=t and r.legal_entity_id=e and r.branch_id=b and r.id=p) then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 if x is not null and exists(select 1 from projects.expenses where id=x) and not exists(select 1 from projects.expenses z
  where z.tenant_id=t and z.legal_entity_id=e and z.branch_id=b and z.project_id=p and z.id=x) then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
end $$;
-- Service tickets recheck the actual human's current membership, scope, both
-- entitlements and MFA. Service credentials never stand in for human authority.
create function expense_private.user_has(t uuid,e uuid,b uuid,u uuid,cap text,aal text) returns boolean
language sql stable security definer set search_path='' as $$
 select aal='aal2' and exists(select 1 from core.memberships m join core.role_assignments a
  on a.tenant_id=m.tenant_id and a.membership_id=m.id join core.roles r on r.tenant_id=a.tenant_id and r.id=a.role_id
  join core.role_permissions rp on rp.tenant_id=r.tenant_id and rp.role_id=r.id
  where m.tenant_id=t and m.user_id=u and m.status='active' and rp.permission_code=cap
  and(a.legal_entity_id is null or a.legal_entity_id=e) and(a.branch_id is null or a.branch_id=b))
 and not exists(select 1 from unnest(array['module.projects','module.finance']) required where not exists(
  select 1 from billing.tenant_subscriptions s join billing.plan_entitlements pe on pe.plan_code=s.plan_code
  where s.tenant_id=t and pe.entitlement_code=required and pe.enabled and
  ((s.status='active' and(s.current_period_ends_at is null or s.current_period_ends_at>now())) or(s.status='trialing' and s.trial_ends_at>now()))))
 and exists(select 1 from core.tenants where id=t and status in('trial','active'))
 and exists(select 1 from core.legal_entities where tenant_id=t and id=e and status='active')
 and exists(select 1 from core.branches where tenant_id=t and legal_entity_id=e and id=b and status='active')
$$;
create function expense_private.service_only() returns void language plpgsql stable set search_path='' as $$begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception using errcode='42501',message='EXPENSE_TRUSTED_SERVICE_REQUIRED';end if;
end $$;
create function expense_private.ready(t uuid,e uuid,w boolean default false) returns void language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from expense_private.policies where tenant_id=t and legal_entity_id=e) then
  raise exception using errcode='55000',message='EXPENSE_RETENTION_POLICY_REQUIRED';end if;
 if w and not exists(select 1 from expense_private.worker_readiness where contract='w4-expense-evidence-v1' and verified_at>now()-interval '26 hours') then
  raise exception using errcode='55000',message='EXPENSE_RETENTION_WORKER_UNAVAILABLE';end if;
end $$;
create function expense_private.proof(d expense_private.documents) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('id',d.id,'version',d.content_version,'digest',d.digest) $$;
create function expense_private.summary(d expense_private.documents) returns jsonb language sql immutable set search_path='' as $$
 select expense_private.proof(d)||jsonb_build_object('record_version',d.version,'status',d.status,'purpose',d.purpose,
  'mime',d.mime,'byte_size',d.byte_size,'checksum',d.checksum,'policy_id',d.policy_id,'retired_at',d.retired_at,
  'purge_after',d.purge_after,'hold_review_date',d.hold_review_date) $$;

-- Owner-only integration: empty evidence is explicit and remains valid for
-- synthetic narrative fixtures. Real proofs cannot be inferred from text/URLs.
create function projects.expense_evidence_assert(t uuid,e uuid,b uuid,p uuid,x uuid,proofs jsonb,mode text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v jsonb;d expense_private.documents%rowtype;outcome jsonb:='[]';seen uuid[]:='{}';begin
 if mode not in('freeze','read','decision') or jsonb_typeof(proofs) is distinct from 'array' or jsonb_array_length(proofs)>10 then
  raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';end if;
 perform projects.finance_access(t,e,b,'projects.cost.view',true);
 perform expense_private.lock_scope(t,e);
 if jsonb_array_length(proofs)=0 then return '[]';end if;
 perform expense_private.require_access(t,e,b,p,x,case when mode='freeze' then 'projects.expenses.manage' else 'projects.expenses.evidence.view' end);
 perform expense_private.ready(t,e,mode<>'read');
 for v in select value from jsonb_array_elements(proofs) loop
  if jsonb_typeof(v) is distinct from 'object' or not(v ?& array['id','version','digest'])
   or exists(select 1 from jsonb_object_keys(v) k where k<>all(array['id','version','digest']))
   or jsonb_typeof(v->'version') is distinct from 'number' or v->>'version'<>'1' or v->>'digest'!~'^[a-f0-9]{64}$' then
   raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';end if;
  if(v->>'id')::uuid=any(seen) then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';end if;
  seen:=array_append(seen,(v->>'id')::uuid);
  select * into d from expense_private.documents where id=(v->>'id')::uuid and tenant_id=t and legal_entity_id=e
   and branch_id=b and project_id=p and expense_id=x for share;
  if d.id is null or expense_private.proof(d) is distinct from v then raise exception using errcode='40001',message='EXPENSE_EVIDENCE_CONFLICT';end if;
  -- Historical financial reads retain the original proof after an authorized
  -- retention purge; byte delivery and new decisions still require active data.
  if (mode='read' and d.status not in('active','retired','purging','purged')) or(mode<>'read' and d.status<>'active') then
   raise exception using errcode='55000',message='EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE';end if;
  outcome:=outcome||jsonb_build_array(expense_private.proof(d));
 end loop;
 return(select coalesce(jsonb_agg(value order by value->>'id'),'[]') from jsonb_array_elements(outcome));
exception when invalid_text_representation then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_PROOF_INVALID';
end $$;
create function api.projects_expense_evidence_access(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_expense_id uuid,p_capability text default 'projects.expenses.evidence.view')
returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,p_expense_id,p_capability);
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,
  'expense_id',p_expense_id,'actor_id',auth.uid(),'authorized',true,'available',exists(select 1 from expense_private.policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id)
  and exists(select 1 from expense_private.worker_readiness where contract='w4-expense-evidence-v1' and verified_at>now()-interval '26 hours'));
end $$;
create function api.projects_expense_evidence_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_expense_id uuid,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$declare rows jsonb;begin
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,p_expense_id,'projects.expenses.evidence.view');
 select coalesce(jsonb_agg(expense_private.summary(d) order by d.id),'[]') into rows from(select * from expense_private.documents
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=p_project_id and expense_id=p_expense_id
  and(p_after is null or id>p_after) order by id limit 51) d;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,
  'expense_id',p_expense_id,'items',rows-50,'next_after',case when jsonb_array_length(rows)>50 then rows->49->>'id' end);
end $$;

create function api.projects_expense_evidence_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare act text:=p_payload->>'action';id uuid:=(p_payload->>'id')::uuid;p uuid:=(p_payload->>'project_id')::uuid;x uuid:=(p_payload->>'expense_id')::uuid;
 cap text;allowed text[];hash text;replay jsonb;result jsonb;d expense_private.documents%rowtype;policy expense_private.policies%rowtype;body jsonb;v_digest text;reason text;begin
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192 or id is null or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 then
  raise exception using errcode='22023',message='EXPENSE_EVIDENCE_COMMAND_INVALID';end if;
 cap:=case when act in('policy_create','hold','release_hold','retire') then 'projects.expenses.retention.manage'
  when act in('reserve','complete') then 'projects.expenses.manage' end;
 allowed:=case act when 'policy_create' then array['action','id','retention_days','purpose']
  when 'reserve' then array['action','id','project_id','expense_id','mime','byte_size','checksum','purpose']
  when 'complete' then array['action','id','project_id','expense_id']
  when 'hold' then array['action','id','project_id','expense_id','reason','review_date']
  when 'release_hold' then array['action','id','project_id','expense_id','reason']
  when 'retire' then array['action','id','project_id','expense_id','reason'] end;
 if cap is null or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) or(act<>'policy_create' and(p is null or x is null)) then
  raise exception using errcode='22023',message='EXPENSE_EVIDENCE_FIELDS_INVALID';end if;
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p,x,cap);
 if act='policy_create' then perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
 perform expense_private.lock_scope(p_tenant_id,p_legal_entity_id);
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p,x,cap);
 if act='policy_create' then perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
 if act<>'policy_create' then perform expense_private.ready(p_tenant_id,p_legal_entity_id,act in('reserve','complete'));end if;
 hash:=core.wave3_request_hash('projects.expense_evidence.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 -- Mutable permissions and worker readiness were checked before receipt replay.
 replay:=core.wave3_replay(p_tenant_id,'projects.expense_evidence.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 if act='policy_create' then
  if p_expected_version<>0 or jsonb_typeof(p_payload->'retention_days') is distinct from 'number' or p_payload->>'retention_days'!~'^[0-9]+$'
   or(p_payload->>'retention_days')::numeric not between 1 and 3650 or exists(select 1 from expense_private.policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id) then
   raise exception using errcode='22023',message='EXPENSE_RETENTION_POLICY_INVALID';end if;
  insert into expense_private.policies(id,tenant_id,legal_entity_id,retention_days,purpose,created_by)
  values(id,p_tenant_id,p_legal_entity_id,(p_payload->>'retention_days')::integer,projects.text(p_payload->'purpose',160),auth.uid());
  result:=jsonb_build_object('id',id,'version',1,'action',act);
 else
  select * into policy from expense_private.policies where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id;
  select * into d from expense_private.documents where documents.id=id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and project_id=p and expense_id=x for update;
  if act='reserve' then
   if p_expected_version<>0 or d.id is not null or p_payload->>'mime' not in('text/plain','image/png','image/jpeg','application/pdf')
    or jsonb_typeof(p_payload->'byte_size') is distinct from 'number' or p_payload->>'byte_size'!~'^[0-9]+$'
    or(p_payload->>'byte_size')::numeric not between 1 and 10485760 or p_payload->>'checksum'!~'^[a-f0-9]{64}$'
    or p_payload->>'mime' is null or p_payload->>'checksum' is null then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_METADATA_INVALID';end if;
   if(select count(*) from expense_private.documents where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and project_id=p and expense_id=x and status<>'purged')>=10 then
    raise exception using errcode='55000',message='EXPENSE_EVIDENCE_DOCUMENT_LIMIT';end if;
   if exists(select 1 from projects.expenses where expenses.id=x and status not in('draft','rejected')) then raise exception using errcode='55000',message='EXPENSE_EVIDENCE_SOURCE_IMMUTABLE';end if;
   body:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p,'expense_id',x,
    'id',id,'version',1,'mime',p_payload->>'mime','byte_size',(p_payload->>'byte_size')::integer,'checksum',p_payload->>'checksum','policy_id',policy.id);
   v_digest:=encode(extensions.hmac(convert_to(body::text,'UTF8'),policy.digest_key,'sha256'),'hex');
   insert into expense_private.documents(id,tenant_id,legal_entity_id,branch_id,project_id,expense_id,policy_id,digest,mime,byte_size,checksum,purpose,created_by)
    values(id,p_tenant_id,p_legal_entity_id,p_branch_id,p,x,policy.id,v_digest,p_payload->>'mime',(p_payload->>'byte_size')::integer,p_payload->>'checksum',projects.text(p_payload->'purpose',160),auth.uid()) returning * into d;
  else
   if d.id is null or d.version<>p_expected_version then raise exception using errcode='40001',message='EXPENSE_EVIDENCE_CONFLICT';end if;
   if d.status in('purging','purged') then raise exception using errcode='55000',message='EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE';end if;
   if act='complete' then
    if d.status<>'verified' or d.verified_at is null then raise exception using errcode='55000',message='EXPENSE_EVIDENCE_VERIFICATION_REQUIRED';end if;
    update expense_private.documents set status='active',version=version+1,activated_at=clock_timestamp() where documents.id=id returning * into d;
   elsif act='hold' then
    reason:=projects.text(p_payload->'reason',1000);
    if(p_payload->>'review_date')::date<current_date or(p_payload->>'review_date')::date>current_date+366 or p_payload->>'review_date' is null then
     raise exception using errcode='22023',message='EXPENSE_RETENTION_HOLD_INVALID';end if;
    update expense_private.documents set hold_reason=reason,hold_review_date=(p_payload->>'review_date')::date,version=version+1 where documents.id=id returning * into d;
   elsif act='release_hold' then
    reason:=projects.text(p_payload->'reason',1000);
    if d.hold_reason is null then raise exception using errcode='55000',message='EXPENSE_RETENTION_HOLD_REQUIRED';end if;
    update expense_private.documents set hold_reason=null,hold_review_date=null,version=version+1 where documents.id=id returning * into d;
   elsif act='retire' then
    reason:=projects.text(p_payload->'reason',1000);
    if d.status not in('reserved','verified','active') or not exists(select 1 from projects.expenses z where z.id=x and z.tenant_id=p_tenant_id
     and z.legal_entity_id=p_legal_entity_id and z.branch_id=p_branch_id and z.project_id=p and z.status in('cancelled','rejected','reversed')) then
     raise exception using errcode='55000',message='EXPENSE_FINANCIAL_RETENTION_REQUIRED';end if;
    update expense_private.documents set status='retired',version=version+1,retired_at=clock_timestamp(),purge_after=clock_timestamp()+make_interval(days=>policy.retention_days)
     where documents.id=id returning * into d;
   end if;
  end if;
  insert into expense_private.events(tenant_id,legal_entity_id,document_id,action,version,reason,actor_id)
   values(p_tenant_id,p_legal_entity_id,id,act,d.version,reason,auth.uid());
  result:=expense_private.proof(d)||jsonb_build_object('record_version',d.version,'status',d.status,'project_id',p,'expense_id',x,'action',act);
 end if;
 result:=result||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
 return core.wave3_finish_command(p_tenant_id,'projects.expense_evidence.'||act,p_command_id,'projects.expense_evidence',id,p_idempotency_key,hash,'{}',result,p_legal_entity_id,p_branch_id);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception using errcode='22023',message='EXPENSE_EVIDENCE_FIELDS_INVALID';
end $$;

create function api.projects_expense_evidence_ticket(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_expense_id uuid,p_document_id uuid,p_operation text)
returns jsonb language plpgsql security definer set search_path='' as $$declare d expense_private.documents%rowtype;ticket uuid;begin
 if p_operation not in('upload','download','export') or p_operation is null then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_OPERATION_INVALID';end if;
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_project_id,p_expense_id,
  case when p_operation='upload' then 'projects.expenses.manage' when p_operation='export' then 'projects.expenses.evidence.export' else 'projects.cost.view' end);
 perform expense_private.lock_scope(p_tenant_id,p_legal_entity_id);
 perform expense_private.ready(p_tenant_id,p_legal_entity_id,p_operation='upload');
 select * into d from expense_private.documents where id=p_document_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and project_id=p_project_id and expense_id=p_expense_id for share;
 if d.id is null or(p_operation='upload' and d.status not in('reserved','verified','active')) or(p_operation<>'upload' and d.status<>'active') then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 insert into expense_private.tickets(document_id,user_id,operation,issued_aal) values(d.id,auth.uid(),p_operation,coalesce(auth.jwt()->>'aal','aal1')) returning id into ticket;
 return jsonb_build_object('ticket_id',ticket,'expires_at',clock_timestamp()+interval '30 seconds');
end $$;
create function api.projects_expense_evidence_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare r core.command_receipts%rowtype;act text;cap text;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.cost.view',true);
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and actor_id=auth.uid() and command_id=p_command_id and command_name like 'projects.expense_evidence.%';
 if r.command_id is null then return null;end if;
 act:=r.response->'entity'->>'action';
 cap:=case when act in('policy_create','hold','release_hold','retire') then 'projects.expenses.retention.manage' else 'projects.expenses.manage' end;
 perform expense_private.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,(r.response->'entity'->>'project_id')::uuid,
  (r.response->'entity'->>'expense_id')::uuid,cap);
 if act='policy_create' then perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
 if act in('reserve','complete') then perform expense_private.ready(p_tenant_id,p_legal_entity_id,true);end if;
 return r.response;
end $$;
create function expense_private.ticket_authority(v expense_private.tickets,d expense_private.documents,u uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if v.id is null or d.id is null or v.user_id is distinct from u or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,'projects.view',v.issued_aal)
  or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,'projects.cost.view',v.issued_aal)
  or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,'projects.expenses.evidence.view',v.issued_aal)
  or not expense_private.user_has(d.tenant_id,d.legal_entity_id,d.branch_id,u,
   case when v.operation='upload' then 'projects.expenses.manage' when v.operation='export' then 'projects.expenses.evidence.export' else 'projects.cost.view' end,v.issued_aal)
  or not exists(select 1 from projects.register where tenant_id=d.tenant_id and legal_entity_id=d.legal_entity_id and branch_id=d.branch_id and id=d.project_id) then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
end $$;
create function api.projects_expense_evidence_service_document(p_ticket_id uuid,p_user_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v expense_private.tickets%rowtype;d expense_private.documents%rowtype;begin
 perform expense_private.service_only();
 select * into v from expense_private.tickets where id=p_ticket_id;select * into d from expense_private.documents where id=v.document_id;
 perform expense_private.lock_scope(d.tenant_id,d.legal_entity_id);
 select * into v from expense_private.tickets where id=p_ticket_id for update;select * into d from expense_private.documents where id=v.document_id for share;
 perform expense_private.ticket_authority(v,d,p_user_id);
 if v.expires_at<=clock_timestamp() or v.consumed_at is not null or(v.operation='upload' and d.status not in('reserved','verified','active'))
  or(v.operation<>'upload' and d.status<>'active') then raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 perform expense_private.ready(d.tenant_id,d.legal_entity_id,v.operation='upload');
 update expense_private.tickets set consumed_at=clock_timestamp() where id=p_ticket_id;
 return expense_private.summary(d)||jsonb_build_object('ticket_id',v.id,'document_id',d.id,'tenant_id',d.tenant_id,'legal_entity_id',d.legal_entity_id,
  'branch_id',d.branch_id,'project_id',d.project_id,'expense_id',d.expense_id,'operation',v.operation,
  'object_path',d.tenant_id||'/'||d.legal_entity_id||'/'||d.project_id||'/'||d.expense_id||'/'||d.id);
end $$;
create function api.projects_expense_evidence_service_verify(p_ticket_id uuid,p_user_id uuid,p_checksum text,p_byte_size integer) returns jsonb
language plpgsql security definer set search_path='' as $$declare v expense_private.tickets%rowtype;d expense_private.documents%rowtype;begin
 perform expense_private.service_only();select * into v from expense_private.tickets where id=p_ticket_id;select * into d from expense_private.documents where id=v.document_id;
 perform expense_private.lock_scope(d.tenant_id,d.legal_entity_id);
 select * into v from expense_private.tickets where id=p_ticket_id for update;select * into d from expense_private.documents where id=v.document_id for update;
 perform expense_private.ticket_authority(v,d,p_user_id);
 if v.operation<>'upload' or v.consumed_at is null or v.expires_at+interval '2 minutes'<=clock_timestamp() or d.status not in('reserved','verified','active') then
  raise exception using errcode='42501',message='EXPENSE_EVIDENCE_DENIED';end if;
 perform expense_private.ready(d.tenant_id,d.legal_entity_id,true);
 if d.checksum is distinct from p_checksum or d.byte_size is distinct from p_byte_size then raise exception using errcode='22023',message='EXPENSE_EVIDENCE_BYTES_MISMATCH';end if;
 if d.status='reserved' then update expense_private.documents set status='verified',verified_at=clock_timestamp() where id=d.id;end if;
 update expense_private.tickets set verified_at=clock_timestamp() where id=p_ticket_id;return jsonb_build_object('verified',true);
end $$;
create function api.projects_expense_evidence_worker_register(p_artifact_digest text,p_storage_probe_digest text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform expense_private.service_only();
 if p_artifact_digest is null or p_storage_probe_digest is null or p_artifact_digest!~'^[a-f0-9]{64}$' or p_storage_probe_digest!~'^[a-f0-9]{64}$' then
  raise exception using errcode='22023',message='EXPENSE_WORKER_PROOF_INVALID';end if;
 insert into expense_private.worker_readiness(contract,artifact_digest,storage_probe_digest) values('w4-expense-evidence-v1',p_artifact_digest,p_storage_probe_digest)
 on conflict(contract) do update set artifact_digest=excluded.artifact_digest,storage_probe_digest=excluded.storage_probe_digest,verified_at=clock_timestamp();
 return jsonb_build_object('contract','w4-expense-evidence-v1','ready',true);
end $$;
create function api.projects_expense_evidence_worker_claim(p_limit integer default 50) returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate record;d expense_private.documents%rowtype;j expense_private.purge_jobs%rowtype;lease uuid;items jsonb:='[]';begin
 perform expense_private.service_only();
 if p_limit is null or p_limit not between 1 and 50 then raise exception using errcode='22023',message='EXPENSE_WORKER_LIMIT';end if;
 if not exists(select 1 from expense_private.worker_readiness where verified_at>now()-interval '26 hours') then
  raise exception using errcode='55000',message='EXPENSE_RETENTION_WORKER_UNAVAILABLE';end if;
 -- Bound the scan as well as response. No document lock precedes entity locks.
 for candidate in select id,tenant_id,legal_entity_id from expense_private.documents where hold_reason is null and
  ((status='retired' and purge_after<=clock_timestamp()) or(status in('reserved','verified') and created_at<clock_timestamp()-interval '24 hours') or status='purging')
  order by tenant_id,legal_entity_id,id limit 50 loop
  exit when jsonb_array_length(items)>=p_limit;
  perform expense_private.lock_scope(candidate.tenant_id,candidate.legal_entity_id);
  select * into d from expense_private.documents where id=candidate.id for update skip locked;
  if d.id is null or d.hold_reason is not null or not((d.status='retired' and d.purge_after<=clock_timestamp())
   or(d.status in('reserved','verified') and d.created_at<clock_timestamp()-interval '24 hours') or d.status='purging') then continue;end if;
  if exists(select 1 from projects.expenses z where z.id=d.expense_id and z.status not in('cancelled','rejected','reversed')) then continue;end if;
  insert into expense_private.purge_jobs(document_id) values(d.id) on conflict(document_id) do nothing;
  select * into j from expense_private.purge_jobs where document_id=d.id for update;
  if j.status='complete' or j.lease_until>clock_timestamp() then continue;end if;
  lease:=gen_random_uuid();update expense_private.purge_jobs set lease_id=lease,lease_until=clock_timestamp()+interval '30 minutes' where id=j.id;
  if d.status<>'purging' then update expense_private.documents set status='purging',version=version+1 where id=d.id;end if;
  items:=items||jsonb_build_array(jsonb_build_object('job_id',j.id,'lease_id',lease,'object_paths',jsonb_build_array(
   d.tenant_id||'/'||d.legal_entity_id||'/'||d.project_id||'/'||d.expense_id||'/'||d.id)));
 end loop;
 delete from expense_private.tickets where id in(select id from expense_private.tickets where expires_at<now()-interval '3 minutes' order by expires_at limit 500);
 return jsonb_build_object('items',items);
end $$;
create function api.projects_expense_evidence_worker_complete(p_job_id uuid,p_lease_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare j expense_private.purge_jobs%rowtype;d expense_private.documents%rowtype;begin
 perform expense_private.service_only();select * into j from expense_private.purge_jobs where id=p_job_id;select * into d from expense_private.documents where id=j.document_id;
 perform expense_private.lock_scope(d.tenant_id,d.legal_entity_id);
 select * into d from expense_private.documents where id=j.document_id for update;select * into j from expense_private.purge_jobs where id=p_job_id for update;
 if j.id is null or j.status<>'pending' or j.lease_id is distinct from p_lease_id or j.lease_until<=clock_timestamp() or d.status<>'purging' or d.hold_reason is not null then
  raise exception using errcode='42501',message='EXPENSE_WORKER_LEASE_INVALID';end if;
 update expense_private.documents set status='purged',version=version+1,purged_at=clock_timestamp() where id=d.id;
 insert into expense_private.events(tenant_id,legal_entity_id,document_id,action,version) values(d.tenant_id,d.legal_entity_id,d.id,'purged',d.version+1);
 update expense_private.purge_jobs set status='complete',completed_at=clock_timestamp(),lease_until=null where id=j.id;
 return jsonb_build_object('job_id',j.id,'complete',true);
end $$;
do $$declare v record;begin
 for v in select tablename from pg_tables where schemaname='expense_private' loop
  execute format('alter table expense_private.%I enable row level security',v.tablename);
  execute format('alter table expense_private.%I force row level security',v.tablename);
  execute format('revoke all on expense_private.%I from public,anon,authenticated,service_role',v.tablename);
 end loop;
 for v in select p.oid::regprocedure fn,p.proname,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='expense_private' or(n.nspname='api' and p.proname like 'projects_expense_evidence_%')
  or(n.nspname='projects' and p.proname='expense_evidence_assert') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',v.fn);
  if v.nspname='api' then
   if v.proname like 'projects_expense_evidence_worker_%' or v.proname like 'projects_expense_evidence_service_%' then
    execute format('grant execute on function %s to service_role',v.fn);
   else execute format('grant execute on function %s to authenticated',v.fn);end if;
  end if;
 end loop;
end $$;

-- Scoped role fixtures, inside the strict outer candidate rollback.
reset role;select pg_temp.wactor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p from unnest(array['creator','reviewer']) x
cross join unnest(array['projects.expenses.evidence.view','projects.expenses.evidence.export','projects.expenses.retention.manage']) p on conflict do nothing;
create temporary table expense_evidence_samples(label text primary key,body jsonb);
grant select,insert,update on expense_evidence_samples to authenticated,service_role;
create function pg_temp.eec(p jsonb,v bigint,k text) returns jsonb language sql as $$
 select api.projects_expense_evidence_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('ee.command.'||k),pg_temp.wid('ee.command.'||k),now(),p,v) $$;
create function pg_temp.eep(a text) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('ee.document'),'project_id',pg_temp.wid('finance'),'expense_id',pg_temp.wid('pf.evidence')) $$;
create function pg_temp.eer() returns jsonb language sql as $$
 select pg_temp.eep('reserve')||jsonb_build_object('mime','text/plain','byte_size',14,'checksum',repeat('c',64),'purpose','Synthetic receipt bytes') $$;
create function pg_temp.eet(operation text) returns jsonb language sql as $$
 select api.projects_expense_evidence_ticket(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.evidence'),pg_temp.wid('ee.document'),operation) $$;
-- Simulates the owner-only integration call while retaining the current human JWT.
create function pg_temp.eef(proofs jsonb,mode text default 'freeze',expense uuid default pg_temp.wid('pf.evidence')) returns jsonb
language sql security definer set search_path='' as $$
 select projects.expense_evidence_assert(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),expense,proofs,mode) $$;
insert into project_assertions select ok(not has_table_privilege('authenticated','expense_private.documents','SELECT') and not has_table_privilege('service_role','expense_private.documents','SELECT'),
 'FR426 private evidence base rows denied to both client and trusted role');
insert into project_assertions select ok(not has_function_privilege('authenticated','projects.expense_evidence_assert(uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),
 'FR426 attachment proof helper cannot be invoked directly by clients');
insert into project_assertions select ok(not(select public from storage.buckets where id='jentra-project-expense-private'),'FR426 bucket is physically private and separate');
set local role authenticated;
insert into project_assertions select is(pg_temp.eef('[]'),'[]'::jsonb,'FR426 explicit narrative-only synthetic evidence needs no provider activation');
insert into project_assertions select is(api.projects_expense_evidence_access(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.evidence'))->>'available','false',
 'FR426 attachment availability remains gated before policy and worker');
select pg_temp.eec(jsonb_build_object('action','policy_create','id',pg_temp.wid('ee.policy'),'retention_days',30,'purpose','Explicit synthetic financial retention choice'),0,'policy');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('branch-manager.role'),p from unnest(array['projects.expenses.evidence.view','projects.expenses.retention.manage']) p on conflict do nothing;
select pg_temp.wactor('branch-manager');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eec(jsonb_build_object('action','policy_create','id',pg_temp.wid('ee.branch.policy'),'retention_days',30,'purpose','Branch-only choice'),0,'branch.policy')$$,
 '42501',null,'FR426 branch-only retention manager cannot choose an entity-wide policy');
reset role;update core.role_assignments set branch_id=pg_temp.wid('branch') where tenant_id=pg_temp.wid('tenant') and membership_id=pg_temp.wid('creator.membership');
select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eec(jsonb_build_object('action','policy_create','id',pg_temp.wid('ee.policy'),'retention_days',30,'purpose','Explicit synthetic financial retention choice'),0,'policy')$$,
 '42501',null,'FR426 entity policy scope is rechecked before confirmed replay');
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('ee.command.policy'))$$,
 '42501',null,'FR426 entity policy receipt requires current entity-wide authority');
reset role;update core.role_assignments set branch_id=null where tenant_id=pg_temp.wid('tenant') and membership_id=pg_temp.wid('creator.membership');
select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eec(pg_temp.eer(),0,'reserve')$$,'55000','EXPENSE_RETENTION_WORKER_UNAVAILABLE','FR426 reserve denied until storage worker proof');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_register(repeat('a',64),repeat('b',64));
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into expense_evidence_samples values('reserved',pg_temp.eec(pg_temp.eer(),0,'reserve'));
insert into project_assertions select is((select body->'entity'->>'record_version' from expense_evidence_samples where label='reserved'),'1','FR426 reservation has exact initial lifecycle version');
insert into project_assertions select is(pg_temp.eec(pg_temp.eer(),0,'reserve'),(select body from expense_evidence_samples where label='reserved'),'FR426 exact reserve replay is immutable');
insert into project_assertions select throws_ok($$select pg_temp.eec(pg_temp.eer()||'{"byte_size":15}',0,'reserve')$$,'22023','IDEMPOTENCY_MISMATCH','FR426 changed reserved bytes cannot replay');
insert into project_assertions select throws_ok($$select pg_temp.eec(pg_temp.eep('complete'),1,'complete')$$,'55000','EXPENSE_EVIDENCE_VERIFICATION_REQUIRED','FR426 unverified content cannot be attached');
insert into expense_evidence_samples values('ticket',pg_temp.eet('upload'));
insert into expense_evidence_samples values('state-ticket',pg_temp.eet('upload'));
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into expense_evidence_samples values('service',api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator')));
insert into project_assertions select is((select body->>'object_path' from expense_evidence_samples where label='service'),
 pg_temp.wid('tenant')||'/'||pg_temp.wid('entity')||'/'||pg_temp.wid('finance')||'/'||pg_temp.wid('pf.evidence')||'/'||pg_temp.wid('ee.document'),
 'FR426 trusted ticket binds every document path to its expense privacy unit');
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 service ticket cannot be consumed twice');
reset role;update core.branches set status='inactive' where id=pg_temp.wid('branch');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='state-ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 issued ticket is denied after branch deactivation');
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14)$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 uploaded bytes cannot verify after branch deactivation');
reset role;update core.branches set status='active' where id=pg_temp.wid('branch');update core.legal_entities set status='inactive' where id=pg_temp.wid('entity');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='state-ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 issued ticket is denied after entity deactivation');
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14)$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 uploaded bytes cannot verify after entity deactivation');
reset role;update core.legal_entities set status='active' where id=pg_temp.wid('entity');update core.tenants set status='suspended' where id=pg_temp.wid('tenant');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='state-ticket'),pg_temp.wid('creator'))$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 issued ticket is denied after tenant suspension');
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14)$$,
 '42501','EXPENSE_EVIDENCE_DENIED','FR426 uploaded bytes cannot verify after tenant suspension');
reset role;update core.tenants set status='active' where id=pg_temp.wid('tenant');
insert into project_assertions select is((select status from expense_private.documents where id=pg_temp.wid('ee.document')),'reserved','FR426 deactivated scope never verifies or activates bytes');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('d',64),14)$$,
 '22023','EXPENSE_EVIDENCE_BYTES_MISMATCH','FR426 verification rejects different byte checksum');
select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from expense_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('c',64),14);
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into expense_evidence_samples values('active',pg_temp.eec(pg_temp.eep('complete'),1,'complete'));
insert into expense_evidence_samples select 'proof',jsonb_build_array((body->'entity')-array['tenant_id','legal_entity_id','branch_id','record_version','status','project_id','expense_id','action']) from expense_evidence_samples where label='active';
insert into project_assertions select is((select body->'entity'->>'record_version' from expense_evidence_samples where label='active'),'2','FR426 verified completion advances lifecycle once');
insert into project_assertions select is(pg_temp.eef((select body from expense_evidence_samples where label='proof')),(select body from expense_evidence_samples where label='proof'),'FR426 freeze stores only canonical immutable proof');
insert into project_assertions select throws_ok($$select pg_temp.eef((select body from expense_evidence_samples where label='proof'),'freeze',pg_temp.wid('pf.other-expense'))$$,
 '40001','EXPENSE_EVIDENCE_CONFLICT','FR426 document cannot be attached to another expense');
insert into project_assertions select throws_ok($$select pg_temp.eef((select body||body from expense_evidence_samples where label='proof'))$$,'22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 duplicate document proof rejected');
insert into project_assertions select throws_ok($$select pg_temp.eef((select jsonb_agg(p.body->0) from expense_evidence_samples p cross join generate_series(1,11) where label='proof'))$$,
 '22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 proof list is bounded before effects');
insert into project_assertions select throws_ok($$select pg_temp.eef((select jsonb_build_array((body->0)||'{"object_path":"guess"}') from expense_evidence_samples where label='proof'))$$,
 '22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 proof rejects caller paths and unknown private fields');
insert into project_assertions select is(api.projects_expense_evidence_list(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.evidence'))->'items'->0->>'status','active',
 'FR426 scoped private metadata names verified content');
insert into project_assertions select ok(not((select body::text from expense_evidence_samples where label='active')~'(object_path|checksum|Synthetic receipt bytes)'),
 'FR426 generic confirmation has no filename path bytes or private purpose');
reset role;
insert into project_assertions select throws_ok($$update expense_private.documents set checksum=repeat('e',64) where id=pg_temp.wid('ee.document')$$,'55000','EXPENSE_EVIDENCE_IMMUTABLE','FR426 document content basis is immutable');
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('creator.role') and permission_code='projects.expenses.evidence.view';
select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eec(pg_temp.eer(),0,'reserve')$$,'42501',null,'FR426 attachment view permission is rechecked before confirmed replay');
insert into project_assertions select is(pg_temp.eef('[]'),'[]'::jsonb,'FR426 evidence-free narrative does not require attachment view');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'projects.expenses.evidence.view');
select pg_temp.wactor('creator','aal1');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eet('download')$$,'42501',null,'FR426 private download requires fresh MFA');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eec(pg_temp.eep('retire')||'{"reason":"Synthetic terminal retention"}',2,'retire')$$,
 '55000','EXPENSE_FINANCIAL_RETENTION_REQUIRED','FR426 unlinked or active financial content cannot be retired');
select pg_temp.pfc(pg_temp.pfe('evidence'),0,'evidence.create');
select pg_temp.pfc(pg_temp.pfa('expense_cancel','evidence'),1,'evidence.cancel');
select pg_temp.eec(pg_temp.eep('retire')||'{"reason":"Synthetic terminal retention"}',2,'retire');
insert into project_assertions select is(pg_temp.eef((select body from expense_evidence_samples where label='proof'),'read'),(select body from expense_evidence_samples where label='proof'),
 'FR426 retired evidence retains original financial proof history');
reset role;
insert into project_assertions select ok((select purge_after>now()+interval '29 days' from expense_private.documents where id=pg_temp.wid('ee.document')),'FR426 chosen terminal retention is preserved before purge');
update expense_private.documents set purge_after=clock_timestamp()-interval '1 second' where id=pg_temp.wid('ee.document');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.eec(pg_temp.eep('hold')||jsonb_build_object('reason','Synthetic reviewed hold','review_date',current_date+30),3,'hold');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into project_assertions select is(jsonb_array_length(api.projects_expense_evidence_worker_claim(1)->'items'),0,'FR426 held evidence is not physically claimed');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.eec(pg_temp.eep('release_hold')||'{"reason":"Synthetic reviewed release"}',4,'release');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into expense_evidence_samples values('purge',api.projects_expense_evidence_worker_claim(1));
insert into project_assertions select is(jsonb_array_length((select body->'items' from expense_evidence_samples where label='purge')),1,'FR426 expired terminal document receives one bounded lease');
insert into project_assertions select throws_ok($$select api.projects_expense_evidence_worker_complete((select(body->'items'->0->>'job_id')::uuid from expense_evidence_samples where label='purge'),pg_temp.wid('wrong.lease'))$$,
 '42501','EXPENSE_WORKER_LEASE_INVALID','FR426 wrong worker lease cannot redact proof status');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eec(pg_temp.eep('hold')||jsonb_build_object('reason','Late hold','review_date',current_date+30),6,'latehold')$$,
 '55000','EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE','FR426 a hold cannot race an already claimed physical deletion');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_complete((select(body->'items'->0->>'job_id')::uuid from expense_evidence_samples where label='purge'),
 (select(body->'items'->0->>'lease_id')::uuid from expense_evidence_samples where label='purge'));
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.eet('download')$$,'42501','EXPENSE_EVIDENCE_DENIED','FR426 physically purged bytes cannot be downloaded');
insert into project_assertions select throws_ok($$select pg_temp.eef((select body from expense_evidence_samples where label='proof'),'decision')$$,
 '55000','EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE','FR426 a purged proof cannot authorize a new financial decision');
insert into project_assertions select is(pg_temp.eef((select body from expense_evidence_samples where label='proof'),'read'),(select body from expense_evidence_samples where label='proof'),
 'FR426 physical purge preserves authorized immutable financial history');
reset role;
insert into project_assertions select is((select content_version from expense_private.documents where id=pg_temp.wid('ee.document')),1::bigint,'FR426 retained immutable proof version survives physical purge');
insert into project_assertions select ok((select checksum=repeat('c',64) and purged_at is not null from expense_private.documents where id=pg_temp.wid('ee.document')),'FR426 purge retains original financial evidence basis and completion timestamp');


-- Actual candidate expense commands consume verified private provider proofs.
-- Every fixture row and trusted worker simulation is inside the outer rollback.
reset role;select pg_temp.wactor('creator');
create temporary table finance_evidence_samples(label text primary key,body jsonb);
grant insert,select on finance_evidence_samples to authenticated,service_role;
create function pg_temp.fe_command(a text) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.wid('fe.document'),'project_id',pg_temp.wid('finance'),'expense_id',pg_temp.wid('pf.attached')) $$;
create function pg_temp.fe_reserve() returns jsonb language sql as $$
 select pg_temp.fe_command('reserve')||jsonb_build_object('mime','text/plain','byte_size',14,'checksum',repeat('f',64),'purpose','Synthetic attached receipt') $$;
create function pg_temp.fe_create() returns jsonb language sql as $$
 select pg_temp.pfe('attached')||jsonb_build_object('billable',false,'bill_amount','0','evidence_documents',(select body from finance_evidence_samples where label='proof')) $$;
set local role authenticated;
select pg_temp.eec(pg_temp.fe_reserve(),0,'fe.reserve');
insert into finance_evidence_samples values('ticket',api.projects_expense_evidence_ticket(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),pg_temp.wid('pf.attached'),pg_temp.wid('fe.document'),'upload'));
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_service_document((select(body->>'ticket_id')::uuid from finance_evidence_samples where label='ticket'),pg_temp.wid('creator'));
select api.projects_expense_evidence_service_verify((select(body->>'ticket_id')::uuid from finance_evidence_samples where label='ticket'),pg_temp.wid('creator'),repeat('f',64),14);
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into finance_evidence_samples values('active',pg_temp.eec(pg_temp.fe_command('complete'),1,'fe.complete'));
insert into finance_evidence_samples select 'proof',jsonb_build_array((body->'entity')-array['tenant_id','legal_entity_id','branch_id','record_version','status','project_id','expense_id','action']) from finance_evidence_samples where label='active';
insert into project_assertions select is(api.projects_finance_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'projects.expenses.manage')->>'attachments_available','true','FR426 finance advertises only currently authorized ready evidence provider');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('evidence_documents',(select jsonb_build_array((body->0)||'{"version":2}') from finance_evidence_samples where label='proof')),0,'fe.invalid-version')$$,
 '22023','EXPENSE_EVIDENCE_PROOF_INVALID','FR426 expense rejects lifecycle version as immutable content proof');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('evidence_documents',(select jsonb_build_array((body->0)||jsonb_build_object('digest',repeat('0',64))) from finance_evidence_samples where label='proof')),0,'fe.invalid-digest')$$,
 '40001','EXPENSE_EVIDENCE_CONFLICT','FR426 expense cannot freeze a caller-invented digest');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('id',pg_temp.wid('pf.different-evidence')),0,'fe.foreign')$$,
 '40001','EXPENSE_EVIDENCE_CONFLICT','FR426 expense cannot borrow another expense document');
insert into finance_evidence_samples values('created',pg_temp.pfc(pg_temp.fe_create(),0,'fe.create'));
insert into project_assertions select is(pg_temp.pfc(pg_temp.fe_create(),0,'fe.create'),(select body from finance_evidence_samples where label='created'),'FR426 verified attached expense has immutable exact replay');
insert into project_finance_client_samples values('attachedExpenses',api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses',null,pg_temp.wid('pf.attached')));
reset role;
insert into project_assertions select is((select evidence_documents from projects.expense_revisions where expense_id=pg_temp.wid('pf.attached')),(select body from finance_evidence_samples where label='proof'),'FR426 immutable revision freezes canonical provider proof');
insert into project_assertions select ok((select digest=encode(extensions.digest(convert_to(((pg_temp.fe_create()-array['action','reason'])||jsonb_build_object('evidence_documents',evidence_documents))::text,'UTF8'),'sha256'),'hex') from projects.expense_revisions where expense_id=pg_temp.wid('pf.attached')),'FR426 revision digest binds actual canonical evidence');
insert into project_assertions select throws_ok($$update projects.expense_revisions set evidence_documents='[]' where expense_id=pg_temp.wid('pf.attached')$$,'55000','PROJECT_HISTORY_IMMUTABLE','FR426 original attached revision cannot lose evidence');
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('creator.role') and permission_code='projects.expenses.evidence.view';
set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.fe_create(),0,'fe.create')$$,'42501',null,'FR426 attachment authority checked before confirmed expense replay');
insert into project_assertions select throws_ok($$select api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses',null,pg_temp.wid('pf.attached'))$$,'42501',null,'FR426 private expense projection rechecks attachment view');
insert into project_assertions select throws_ok($$select api.projects_finance_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.command.fe.create'),'expense_create')$$,'42501',null,'FR426 own receipt cannot bypass original attachment authority');
insert into project_assertions select is(api.projects_finance_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'projects.expenses.manage')->>'attachments_available','false','FR426 attachment denial stays explicit without denying operational financial authority');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.fe_create()||jsonb_build_object('action','expense_correct','evidence_documents','[]'::jsonb),1,'fe.detach')$$,'42501',null,'FR426 correction cannot erase original evidence to bypass revoked attachment access');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'projects.expenses.evidence.view');
update expense_private.worker_readiness set verified_at=now()-interval '27 hours';
set local role authenticated;
insert into project_assertions select is(api.projects_finance_authorize(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'projects.expenses.manage')->>'attachments_available','false','FR426 stale worker is explicit in financial provider availability');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_submit','attached'),1,'fe.submit')$$,'55000','EXPENSE_RETENTION_WORKER_UNAVAILABLE','FR426 submitted expense requires current evidence worker');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_register(repeat('a',64),repeat('b',64));
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pfc(pg_temp.pfa('expense_submit','attached'),1,'fe.submit');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_approve','attached'),2,'fe.self')$$,'42501','PROJECT_INDEPENDENT_APPROVAL_REQUIRED','FR426 attached evidence preserves independent expense approval');
select pg_temp.wactor('reviewer');
insert into finance_evidence_samples values('approved',pg_temp.pfc(pg_temp.pfa('expense_approve','attached'),2,'fe.approve'));
reset role;
delete from core.role_permissions where tenant_id=pg_temp.wid('tenant') and role_id=pg_temp.wid('reviewer.role') and permission_code='projects.expenses.evidence.view';
set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_approve','attached'),2,'fe.approve')$$,'42501',null,'FR426 independent confirmed approval replay rechecks original proof access');
reset role;insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reviewer.role'),'projects.expenses.evidence.view');
set local role authenticated;
insert into finance_evidence_samples values('posted',pg_temp.pfc(pg_temp.pfa('expense_post','attached'),3,'fe.post'));
reset role;
insert into project_assertions select is((select amount from projects.reimbursements where expense_id=pg_temp.wid('pf.attached')),0.03::numeric,'FR426 evidence attachment keeps exact original journal obligation');
insert into project_assertions select ok(not exists(select 1 from core.command_receipts where command_id in(pg_temp.wid('pf.command.fe.create'),pg_temp.wid('pf.command.fe.approve'),pg_temp.wid('pf.command.fe.post')) and response::text~'evidence_documents|object_path|checksum|Synthetic attached receipt'),'FR426 generic financial confirmation excludes private attachment metadata');
update expense_private.worker_readiness set verified_at=now()-interval '27 hours';
set local role authenticated;
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_post','attached'),3,'fe.post')$$,'55000','EXPENSE_RETENTION_WORKER_UNAVAILABLE','FR426 confirmed journal post replay rechecks live worker readiness');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select api.projects_expense_evidence_worker_register(repeat('a',64),repeat('b',64));
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pfc(pg_temp.pfa('expense_reverse','attached'),4,'fe.reverse');
select pg_temp.eec(pg_temp.fe_command('retire')||'{"reason":"Synthetic financial reversal retention"}',2,'fe.retire');
insert into project_assertions select is(api.projects_finance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('finance'),'expenses',null,pg_temp.wid('pf.attached'))->'rows'->0->'evidence_documents',(select body from finance_evidence_samples where label='proof'),'FR426 retired bytes retain original immutable expense proof history');
insert into project_assertions select is(api.projects_finance_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pf.command.fe.post'),'expense_post'),(select body from finance_evidence_samples where label='posted'),'FR426 original actor can reconcile historical confirmed post after retirement');
insert into project_assertions select throws_ok($$select pg_temp.pfc(pg_temp.pfa('expense_post','attached'),3,'fe.post')$$,'55000','EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE','FR426 retired content cannot authorize confirmed financial decision replay');
reset role;

do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from project_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
select count(*) assertions from project_assertions;
select jsonb_object_agg(label,body) project_finance_client_samples,(select count(*) from project_assertions) assertions from project_finance_client_samples;
rollback;