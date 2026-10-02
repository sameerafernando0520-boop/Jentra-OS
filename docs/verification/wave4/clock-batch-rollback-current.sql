begin;
set local lock_timeout='3s';
set local statement_timeout='60s';
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

-- W4-03 candidate: bounded raw clock evidence only, without payable claims.
create table people.raw_clock_batches(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,source_system text not null,
 manifest_digest text not null check(manifest_digest ~ '^[a-f0-9]{64}$'),
 row_count integer not null check(row_count between 1 and 200),
 imported_count integer not null check(imported_count>=0 and imported_count<=row_count),
 imported_by uuid not null references auth.users(id),imported_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index raw_clock_batches_scope_idx on people.raw_clock_batches(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index raw_clock_batches_actor_idx on people.raw_clock_batches(imported_by);
create table people.raw_clock_batch_rows(
 tenant_id uuid not null,legal_entity_id uuid not null,employee_id uuid not null,batch_id uuid not null,
 position integer not null check(position between 1 and 200),event_id uuid not null,reused boolean not null,
 primary key(batch_id,position),unique(batch_id,event_id),
 foreign key(tenant_id,legal_entity_id,employee_id,batch_id) references people.raw_clock_batches(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,event_id) references people.raw_clock_events(tenant_id,legal_entity_id,employee_id,id)
);
create index raw_clock_batch_rows_event_idx on people.raw_clock_batch_rows(event_id);
alter table people.raw_clock_batches enable row level security;
alter table people.raw_clock_batches force row level security;
alter table people.raw_clock_batch_rows enable row level security;
alter table people.raw_clock_batch_rows force row level security;
revoke all on people.raw_clock_batches,people.raw_clock_batch_rows from public,anon,authenticated;
create trigger raw_clock_batch_immutable before update or delete on people.raw_clock_batches
 for each row execute function people.work_history_guard();
create trigger raw_clock_batch_row_immutable before update or delete on people.raw_clock_batch_rows
 for each row execute function people.work_history_guard();

create function api.people_attendance_clock_batch(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_employee uuid;v_system text;v_digest text;v_hash text;v_replay jsonb;
 v_row jsonb;v_event people.raw_clock_events%rowtype;v_instant timestamptz;v_checksum text;
 v_checksums text[]:='{}';v_events jsonb:='[]';v_imported integer:=0;v_position integer:=0;
 v_uuid_pattern text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
 v_after jsonb;v_request uuid:=gen_random_uuid();begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or p_expected_version is distinct from 0 or coalesce(jsonb_typeof(p_payload),'null')<>'object'
  or p_payload->>'action' is distinct from 'raw_import_batch'
  or coalesce(p_payload->>'id','') !~ v_uuid_pattern
  or coalesce(p_payload->>'employee_id','') !~ v_uuid_pattern
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(array['action','id','employee_id','source_system','records','manifest_digest']))
  or coalesce(jsonb_typeof(p_payload->'records'),'null')<>'array'
  or jsonb_array_length(p_payload->'records') not between 1 and 200 then
  raise exception using errcode='22023',message='CLOCK_BATCH_INVALID';end if;
 v_id:=(p_payload->>'id')::uuid;v_employee:=(p_payload->>'employee_id')::uuid;
 v_system:=p_payload->>'source_system';
 if coalesce(jsonb_typeof(p_payload->'source_system'),'null')<>'string'
  or length(v_system) not between 1 and 80 or v_system<>btrim(v_system)
  or v_system ~ '[[:cntrl:]]' then raise exception using errcode='22023',message='CLOCK_SOURCE_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.import');
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='ATTENDANCE_MFA_REQUIRED';end if;
 if not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee) then
  raise exception using errcode='42501',message='ATTENDANCE_SCOPE_DENIED';end if;
 v_hash:=core.wave3_request_hash('people.attendance.raw_import_batch',p_command_id,
  p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.attendance.raw_import_batch',p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and id=v_employee for update;
 if not found then raise exception using errcode='P0002',message='ATTENDANCE_EMPLOYEE_NOT_FOUND';end if;
 for v_row in select value from jsonb_array_elements(p_payload->'records') loop
  if coalesce(jsonb_typeof(v_row),'null')<>'object'
   or exists(select 1 from jsonb_object_keys(v_row) k where k<>all(array['id','source_key','observed_utc','checksum']))
   or coalesce(v_row->>'id','') !~ v_uuid_pattern
   or coalesce(jsonb_typeof(v_row->'source_key'),'null')<>'string'
   or length(v_row->>'source_key') not between 1 and 160 or v_row->>'source_key'<>btrim(v_row->>'source_key')
   or v_row->>'source_key' ~ '[[:cntrl:]]'
   or coalesce(v_row->>'observed_utc','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
   or coalesce(v_row->>'checksum','') !~ '^[a-f0-9]{64}$' then
   raise exception using errcode='22023',message='CLOCK_ROW_INVALID';end if;
  v_instant:=(v_row->>'observed_utc')::timestamptz;
  if to_char(v_instant at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')<>v_row->>'observed_utc' then
   raise exception using errcode='22023',message='CLOCK_INSTANT_INVALID';end if;
  v_checksum:=encode(extensions.digest(convert_to(concat_ws(chr(10),p_tenant_id::text,p_legal_entity_id::text,
   p_branch_id::text,v_employee::text,v_system,v_row->>'source_key',v_row->>'observed_utc'),'UTF8'),'sha256'),'hex');
  if v_checksum<>v_row->>'checksum' then raise exception using errcode='22023',message='CLOCK_CHECKSUM_MISMATCH';end if;
  v_checksums:=array_append(v_checksums,v_checksum);
 end loop;
 if (select count(distinct value->>'source_key') from jsonb_array_elements(p_payload->'records'))<>jsonb_array_length(p_payload->'records')
  or (select count(distinct value->>'id') from jsonb_array_elements(p_payload->'records'))<>jsonb_array_length(p_payload->'records') then
  raise exception using errcode='22023',message='CLOCK_BATCH_DUPLICATE';end if;
 v_digest:=encode(extensions.digest(convert_to(concat_ws(chr(10),'w4-clock-batch-v1',p_tenant_id::text,
  p_legal_entity_id::text,p_branch_id::text,v_employee::text,v_system,array_to_string(v_checksums,chr(10))),'UTF8'),'sha256'),'hex');
 if v_digest is distinct from p_payload->>'manifest_digest' then
  raise exception using errcode='22023',message='CLOCK_MANIFEST_MISMATCH';end if;
 for v_row in select value from jsonb_array_elements(p_payload->'records') order by value->>'source_key' loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':clock:'||v_system||':'||(v_row->>'source_key'),0));
 end loop;
 for v_row in select value from jsonb_array_elements(p_payload->'records') loop
  select * into v_event from people.raw_clock_events where tenant_id=p_tenant_id
   and source_system=v_system and source_key=v_row->>'source_key' for update;
  if found then
   if v_event.legal_entity_id<>p_legal_entity_id or v_event.branch_id<>p_branch_id
    or v_event.employee_id<>v_employee or v_event.observed_utc<>(v_row->>'observed_utc')::timestamptz
    or v_event.checksum<>v_row->>'checksum' then
    raise exception using errcode='55000',message='CLOCK_SOURCE_CONFLICT';end if;
   v_events:=v_events||jsonb_build_array(jsonb_build_object('event_id',v_event.id,'reused',true));
  else
   insert into people.raw_clock_events(id,tenant_id,legal_entity_id,branch_id,employee_id,
    source_system,source_key,observed_utc,checksum,imported_by)
   values((v_row->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_system,
    v_row->>'source_key',(v_row->>'observed_utc')::timestamptz,v_row->>'checksum',auth.uid());
   v_imported:=v_imported+1;
   v_events:=v_events||jsonb_build_array(jsonb_build_object('event_id',v_row->>'id','reused',false));
  end if;
 end loop;
 insert into people.raw_clock_batches(id,tenant_id,legal_entity_id,branch_id,employee_id,source_system,
  manifest_digest,row_count,imported_count,imported_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_system,v_digest,
  jsonb_array_length(v_events),v_imported,auth.uid());
 for v_row in select value from jsonb_array_elements(v_events) loop
  v_position:=v_position+1;
  insert into people.raw_clock_batch_rows(tenant_id,legal_entity_id,employee_id,batch_id,position,event_id,reused)
  values(p_tenant_id,p_legal_entity_id,v_employee,v_id,v_position,(v_row->>'event_id')::uuid,(v_row->>'reused')::boolean);
 end loop;
 v_after:=jsonb_build_object('id',v_id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',v_employee,'version',1,'row_count',jsonb_array_length(v_events),
  'imported_count',v_imported,'reused_count',jsonb_array_length(v_events)-v_imported,'manifest_digest',v_digest);
 return core.wave3_finish_command(p_tenant_id,'people.attendance.raw_import_batch',p_command_id,
  'people.raw_clock_batch',v_id,p_idempotency_key,v_hash,'{}',v_after,p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('action','raw_import_batch'),p_request_id=>v_request);
end $$;
revoke all on function api.people_attendance_clock_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.people_attendance_clock_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function people.clock_batch_payload(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',id,'source_system',source_system,'manifest_digest',manifest_digest,
  'row_count',row_count,'imported_count',imported_count,'imported_by',imported_by,'imported_at',imported_at)
 from people.raw_clock_batches where id=p_id
$$;
create function api.people_attendance_clock_batches(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_after uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.view');
 if p_employee_id is null or not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='ATTENDANCE_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(people.clock_batch_payload(q.id) order by q.id),'[]') into items
 from(select id from people.raw_clock_batches where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and employee_id=p_employee_id and(p_after is null or id>p_after) order by id limit 51)q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'employee_id',p_employee_id,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_attendance_clock_batch_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_batch_id uuid,p_after integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.view');
 if p_after is null or p_after not between 0 and 200 then
  raise exception using errcode='22023',message='CLOCK_CURSOR_INVALID';end if;
 if not exists(select 1 from people.raw_clock_batches where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and employee_id=p_employee_id and id=p_batch_id) then
  raise exception using errcode='P0002',message='CLOCK_BATCH_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('position',q.position,'event_id',q.event_id,'reused',q.reused,
  'source_key',e.source_key,'observed_utc',to_char(e.observed_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'checksum',e.checksum) order by q.position),'[]') into items
 from(select * from people.raw_clock_batch_rows where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and employee_id=p_employee_id and batch_id=p_batch_id and position>p_after order by position limit 51)q
 join people.raw_clock_events e on e.id=q.event_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'employee_id',p_employee_id,'batch',people.clock_batch_payload(p_batch_id),'rows',items-50,
  'next_position',case when jsonb_array_length(items)>50 then(items->49->>'position')::integer end);
end $$;
revoke all on function people.clock_batch_payload(uuid),api.people_attendance_clock_batches(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_clock_batch_detail(uuid,uuid,uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function api.people_attendance_clock_batches(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_clock_batch_detail(uuid,uuid,uuid,uuid,uuid,integer) to authenticated;

create temporary table attendance_assertions(message text);
grant insert on attendance_assertions to authenticated,service_role;
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

insert into people.departments(id,tenant_id,legal_entity_id,code)
values(pg_temp.wid('department'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4OPS');
insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,
 start_date,end_date_exclusive,reason,recorded_by)
values(pg_temp.wid('department-r1'),pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('department'),'Synthetic Operations',pg_temp.wdate()-10,
 pg_temp.wdate()+400,'Synthetic attendance fixture',pg_temp.wid('creator'));
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,
 employee_id,spell_id,department_id,calendar_version_id,role_title,
 start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('organization-employee'),pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),s.id,pg_temp.wid('department'),
 pg_temp.wid('calendar-version'),'Synthetic worker',pg_temp.wdate()-10,
 pg_temp.wdate()+400,'Synthetic attendance fixture',pg_temp.wid('creator')
from people.employment_spells s where s.employee_id=pg_temp.wid('employee');

create function pg_temp.ac(p jsonb,v bigint,k text,p_branch text default 'branch')
returns jsonb language sql as $$
 select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid(p_branch),pg_temp.wid(k),pg_temp.wid(k),now(),p,v)
$$;
create function pg_temp.aentry(p_id text,p_start interval default interval '9 hours',
 p_end interval default interval '12 hours',p_break boolean default true)
returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid(p_id),
 'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+p_start,'YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,
 'end_local',to_char(pg_temp.wdate()::timestamp+p_end,'YYYY-MM-DD"T"HH24:MI:SS'),
 'end_offset_seconds',19800,
 'breaks',case when p_break then jsonb_build_array(jsonb_build_object(
  'start_utc',to_char(pg_temp.wdate()::timestamp+interval '4 hours 30 minutes',
    'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'end_utc',to_char(pg_temp.wdate()::timestamp+interval '4 hours 45 minutes',
    'YYYY-MM-DD"T"HH24:MI:SS"Z"'))) else '[]'::jsonb end,
 'reason','Synthetic time fixture')
$$;
create function pg_temp.astate(p_action text,p_id text) returns jsonb language sql as $$
 select jsonb_build_object('action',p_action,'id',pg_temp.wid(p_id),
  'employee_id',pg_temp.wid('employee'),'reason','Synthetic attendance transition')
$$;
create temporary table attendance_responses(name text primary key,response jsonb);
grant select,insert on attendance_responses to authenticated,service_role;

insert into attendance_assertions select ok((select bool_and(c.relrowsecurity and c.relforcerowsecurity)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='people'
 and c.relname in ('raw_clock_events','attendance_entries','attendance_revisions',
 'attendance_events','work_claims','work_claim_segments','work_allocations',
 'work_input_seals')),
 'AC-401 all attendance base tables force RLS');
insert into attendance_assertions select ok(not has_table_privilege('authenticated','people.work_allocations','SELECT'),
 'AC-411 common allocations are trusted API-only');
insert into attendance_assertions select ok(not has_table_privilege('authenticated','people.work_claims','SELECT'),
 'AC-401 no direct work claim read');
insert into attendance_assertions select ok(not has_table_privilege('authenticated','people.raw_clock_events','INSERT'),
 'AC-401 no direct raw import');
insert into attendance_assertions select ok(not has_function_privilege('anon',
 'api.people_attendance_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),
 'AC-401 anonymous command denied');
insert into attendance_assertions select ok(not has_function_privilege('authenticated',
 'people.make_work_claim(uuid,uuid,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb,uuid,uuid)',
 'EXECUTE'),'AC-411 direct claim creation denied');
insert into attendance_assertions select throws_ok($$select people.resolve_local_instant('America/New_York',
 '2026-03-08 02:30:00'::timestamp,-18000)$$,'22023','CALENDAR_LOCAL_TIME_NONEXISTENT',
 'AC-405 New York clock gap cannot become attendance');
insert into attendance_assertions select throws_ok($$select people.resolve_local_instant('America/New_York',
 '2026-11-01 01:30:00'::timestamp)$$,'22023','CALENDAR_OFFSET_SELECTION_REQUIRED',
 'AC-405 fold requires selected offset');
insert into attendance_assertions select is((people.resolve_local_instant('America/New_York',
 '2026-11-01 01:30:00'::timestamp,-18000) at time zone 'UTC')::text,
 '2026-11-01 06:30:00','AC-405 selected fold freezes UTC instant');

select pg_temp.wactor('creator');
set local role authenticated;
insert into attendance_responses values('raw-start',pg_temp.ac(jsonb_build_object(
 'action','raw_import','id',pg_temp.wid('raw-start'),'employee_id',pg_temp.wid('employee'),
 'source_system','synthetic-clock','source_key','SYN-START',
 'observed_utc',to_char(pg_temp.wdate()::timestamp+interval '3 hours 30 minutes',
  'YYYY-MM-DD"T"HH24:MI:SS"Z"'),'checksum',repeat('a',64)),0,'raw-start-command'));
insert into attendance_assertions select is(pg_temp.ac(jsonb_build_object('action','raw_import','id',pg_temp.wid('raw-start'),
 'employee_id',pg_temp.wid('employee'),'source_system','synthetic-clock',
 'source_key','SYN-START','observed_utc',to_char(pg_temp.wdate()::timestamp+
 interval '3 hours 30 minutes','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'checksum',repeat('a',64)),
 0,'raw-start-command'),(select response from attendance_responses where name='raw-start'),
 'AC-405 exact raw import replay');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(jsonb_build_object('action','raw_import',
 'id',pg_temp.wid('raw-duplicate'),'employee_id',pg_temp.wid('employee'),
 'source_system','synthetic-clock','source_key','SYN-START',
 'observed_utc',to_char(pg_temp.wdate()::timestamp+interval '3 hours 30 minutes',
  'YYYY-MM-DD"T"HH24:MI:SS"Z"'),'checksum',repeat('b',64)),0,'raw-duplicate-command')$$,
 '23505',null,'AC-405 duplicate raw key with changed checksum denied');
insert into attendance_responses values('create',pg_temp.ac(pg_temp.aentry('attendance'),0,'att-create'));
insert into attendance_assertions select is((select response#>>'{entity,revision,payable_seconds}' from attendance_responses
 where name='create'),'9900','AC-405 three UTC hours minus fifteen-minute break');
insert into attendance_assertions select is(pg_temp.ac(pg_temp.aentry('attendance'),0,'att-create'),
 (select response from attendance_responses where name='create'),'AC-401 exact create replay');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.aentry('attendance')||
 jsonb_build_object('reason','Changed body'),0,'att-create')$$,
 '22023','IDEMPOTENCY_MISMATCH','AC-401 changed request cannot replay');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.aentry('gap')||
 jsonb_build_object('start_local','2026-03-08T02:30:00'),0,'gap')$$,
 '22023',null,'AC-405 mismatched or nonexistent boundary denied');
insert into attendance_responses values('submit',pg_temp.ac(pg_temp.astate('submit','attendance'),1,'att-submit'));
insert into attendance_assertions select is((select response#>>'{entity,status}' from attendance_responses where name='submit'),
 'submitted','AC-405 submitted revision frozen');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.astate('approve','attendance'),2,'self-approve')$$,
 '55000','ATTENDANCE_INDEPENDENT_APPROVAL_REQUIRED','AC-405 self approval denied');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.aentry('cross-scope'),0,'cross-scope','branch2')$$,
 '42501','ATTENDANCE_SCOPE_DENIED','AC-401 other branch denied');

select pg_temp.wactor('reader');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.astate('approve','attendance'),2,'reader-approve')$$,
 '42501',null,'AC-401 reader cannot approve');
select pg_temp.wactor('reviewer');
insert into attendance_responses values('approve',pg_temp.ac(pg_temp.astate('approve','attendance'),2,'att-approve'));
insert into attendance_assertions select is((select response#>>'{entity,status}' from attendance_responses where name='approve'),
 'approved','AC-405 independent approval');
reset role;
insert into attendance_assertions select is((select payable_seconds::text from people.work_claims where
 source_kind='attendance' and source_id=(select current_revision_id from people.attendance_entries
 where id=pg_temp.wid('attendance'))),'9900','AC-411 approved claim owns payable seconds');
insert into attendance_assertions select is((select count(*)::text from people.work_claim_segments where claim_id=
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance'))),
 '2','AC-411 break excludes two separate payable segments');
insert into attendance_assertions select is((select count(*)::text from people.organization_consumptions where source_type='attendance'),
 '1','AC-403 exact organization revision consumed');
create temporary table test_allocations(id uuid);
insert into test_allocations select people.allocate_work(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')),
 'project',pg_temp.wid('project-time'),
 (pg_temp.wdate()::timestamp+interval '3 hours 30 minutes') at time zone 'UTC',
 (pg_temp.wdate()::timestamp+interval '4 hours 30 minutes') at time zone 'UTC',
 pg_temp.wid('reviewer'));
insert into attendance_assertions select is((select count(*)::text from people.work_allocations where active),
 '1','AC-411 project allocation references approved payable segment once');
insert into attendance_assertions select throws_ok($$select people.allocate_work(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')),
 'service',pg_temp.wid('service-time'),
 (pg_temp.wdate()::timestamp+interval '4 hours') at time zone 'UTC',
 (pg_temp.wdate()::timestamp+interval '4 hours 15 minutes') at time zone 'UTC',
 pg_temp.wid('reviewer'))$$,'23P01',null,
 'AC-411 project and service cannot allocate same payable seconds');
insert into attendance_assertions select throws_ok($$select people.allocate_work(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')),
 'service',pg_temp.wid('break-spanning'),
 (pg_temp.wdate()::timestamp+interval '4 hours 29 minutes') at time zone 'UTC',
 (pg_temp.wdate()::timestamp+interval '4 hours 46 minutes') at time zone 'UTC',
 pg_temp.wid('reviewer'))$$,'55000','WORK_ALLOCATION_SOURCE_INVALID',
 'AC-411 one allocation cannot cross an unpaid break');
insert into attendance_assertions select throws_ok($$select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('employee'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('attendance')))$$,
 '55000','WORK_ALLOCATION_IMPACT_REQUIRED',
 'AC-411 allocation blocks silent attendance correction');
select people.revoke_work_allocation(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('employee'),(select id from test_allocations));
set local role authenticated;
insert into attendance_assertions select is((api.people_attendance_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('attendance'))#>>'{entry,revision,payable_seconds}'),
 '9900','AC-405 scoped detail shows frozen payable duration');

select pg_temp.wactor('creator');
insert into attendance_responses values('overlap-create',pg_temp.ac(
 pg_temp.aentry('overlap',interval '11 hours',interval '13 hours',false),0,'overlap-create'));
insert into attendance_responses values('overlap-submit',pg_temp.ac(
 pg_temp.astate('submit','overlap'),1,'overlap-submit'));
select pg_temp.wactor('reviewer');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.astate('approve','overlap'),2,'overlap-approve')$$,
 '23514','WORK_INTERVAL_CONFLICT','AC-411 overlapping payable segment denied');
reset role;
insert into attendance_assertions select is((select status from people.attendance_entries where id=pg_temp.wid('overlap')),
 'submitted','AC-411 failed approval leaves no partial state');
set local role authenticated;

select pg_temp.wactor('creator');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.aentry('bad-break')||jsonb_build_object('breaks',
 jsonb_build_array(jsonb_build_object('start_utc','2026-01-01T00:00:00Z',
 'end_utc','2026-01-01T00:15:00Z'))),0,'bad-break')$$,
 '22023','WORK_BREAK_INVALID','AC-405 out-of-range break denied');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.aentry('unknown')||jsonb_build_object('salary','100'),
 0,'unknown')$$,'22023','ATTENDANCE_FIELDS_INVALID','AC-401 unknown field denied');

select pg_temp.wactor('creator','aal1');
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.astate('submit','attendance'),3,'att-submit')$$,
 '42501',null,'AC-401 MFA checked before replay');
reset role;
select pg_temp.wactor('creator');
insert into people.work_input_seals(tenant_id,legal_entity_id,employee_id,run_id,
 claim_id,source_version,seconds,digest)
select pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('employee'),
 pg_temp.wid('synthetic-payroll-run'),active_claim_id,1,9900,repeat('a',64)
from people.attendance_entries where id=pg_temp.wid('attendance');
set local role authenticated;
insert into attendance_assertions select throws_ok($$select pg_temp.ac(pg_temp.aentry('attendance')||
 jsonb_build_object('action','correct'),3,'sealed-correct')$$,
 '55000','PAYROLL_INPUT_SEALED','AC-407 sealed input cannot silently change');
reset role;
insert into attendance_assertions select ok(not exists(select 1 from core.role_permissions where tenant_id<>pg_temp.wid('tenant')
 and permission_code like 'people.attendance.%'),'AC-401 no existing role grants');
insert into attendance_assertions select is((select count(*)::text from people.work_claims where source_kind='attendance'),
 '1','AC-411 rejected overlaps and corrections create no claim');

-- Appended to the existing attendance rollback fixture. Never owner bootstrap.
create function pg_temp.clock_payload(p_id text,p_keys text[],p_shift integer default 0) returns jsonb language plpgsql as $$
declare k text;rows jsonb:='[]';checks text[]:='{}';utc text;checksum text;begin
 utc:=to_char((pg_temp.wdate()::timestamp+interval '3 hours'+make_interval(secs=>p_shift)),
  'YYYY-MM-DD"T"HH24:MI:SS"Z"');
 foreach k in array p_keys loop
  checksum:=encode(extensions.digest(convert_to(concat_ws(chr(10),pg_temp.wid('tenant')::text,
   pg_temp.wid('entity')::text,pg_temp.wid('branch')::text,pg_temp.wid('employee')::text,
   'synthetic-batch',k,utc),'UTF8'),'sha256'),'hex');
  rows:=rows||jsonb_build_array(jsonb_build_object('id',pg_temp.wid(p_id||':'||k),
   'source_key',k,'observed_utc',utc,'checksum',checksum));checks:=array_append(checks,checksum);
 end loop;
 return jsonb_build_object('action','raw_import_batch','id',pg_temp.wid(p_id),
  'employee_id',pg_temp.wid('employee'),'source_system','synthetic-batch','records',rows,
  'manifest_digest',encode(extensions.digest(convert_to(concat_ws(chr(10),'w4-clock-batch-v1',
   pg_temp.wid('tenant')::text,pg_temp.wid('entity')::text,pg_temp.wid('branch')::text,
   pg_temp.wid('employee')::text,'synthetic-batch',array_to_string(checks,chr(10))),'UTF8'),'sha256'),'hex'));
end $$;
create function pg_temp.clock_cmd(p jsonb,k text,v bigint default 0) returns jsonb language sql as $$
 select api.people_attendance_clock_batch(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid(k),pg_temp.wid(k),now(),p,v)
$$;
insert into attendance_assertions select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c
 join pg_namespace n on n.oid=c.relnamespace where n.nspname='people'
 and c.relname in('raw_clock_batches','raw_clock_batch_rows')),'AC-401 clock batch forced RLS');
insert into attendance_assertions select ok(not has_table_privilege('authenticated','people.raw_clock_batches','SELECT'),
 'AC-401 batch facts API only');
insert into attendance_assertions select ok(not has_function_privilege('anon',
 'api.people_attendance_clock_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),
 'AC-401 anonymous batch denied');
select pg_temp.wactor('creator');
set local role authenticated;
insert into attendance_responses values('clock-batch',pg_temp.clock_cmd(
 pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command'));
insert into attendance_assertions select is((select response#>>'{entity,imported_count}' from attendance_responses where name='clock-batch'),
 '2','AC-405 bounded batch imports all raw rows');
insert into attendance_assertions select is(pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command'),
 (select response from attendance_responses where name='clock-batch'),'AC-401 exact batch replay');
insert into attendance_assertions select is(pg_temp.clock_cmd(pg_temp.clock_payload('clock-reuse',array['SYN-A','SYN-C']),'clock-reuse-command')#>>'{entity,reused_count}',
 '1','AC-405 exact source reuse preserves original identity');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-conflict',array['SYN-NEW','SYN-A'],60),'clock-conflict-command')$$,
 '55000','CLOCK_SOURCE_CONFLICT','AC-405 changed duplicate rejects entire batch');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-C']),'clock-batch-command')$$,
 '22023','IDEMPOTENCY_MISMATCH','AC-401 reused key rejects changed batch');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-hash',array['SYN-D'])||jsonb_build_object('manifest_digest',repeat('a',64)),
 'clock-hash-command')$$,'22023','CLOCK_MANIFEST_MISMATCH','AC-405 server verifies manifest');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(jsonb_set(pg_temp.clock_payload('clock-row-hash',array['SYN-D']),
 '{records,0,checksum}',to_jsonb(repeat('a',64))),'clock-row-hash-command')$$,
 '22023','CLOCK_CHECKSUM_MISMATCH','AC-405 server verifies row checksum');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-dupe',array['SYN-D','SYN-D']),'clock-dupe-command')$$,
 '22023','CLOCK_BATCH_DUPLICATE','AC-405 repeated file keys denied');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-empty',array[]::text[]),'clock-empty-command')$$,
 '22023','CLOCK_BATCH_INVALID','NFR-405 empty batch denied');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-large',array(select 'SYN-'||x::text from generate_series(1,201)x)),
 'clock-large-command')$$,'22023','CLOCK_BATCH_INVALID','NFR-405 oversize batch denied');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-fields',array['SYN-D'])||jsonb_build_object('salary','100'),
 'clock-fields-command')$$,'22023','CLOCK_BATCH_INVALID','AC-401 unrelated fields denied');
select pg_temp.wactor('creator','aal1');
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command')$$,
 '42501',null,'AC-401 MFA required before batch replay');
reset role;
select pg_temp.wactor('creator');
insert into attendance_assertions select is((select count(*)::text from people.raw_clock_events where source_system='synthetic-batch'),
 '3','AC-405 conflict leaves no partial rows');
insert into attendance_assertions select is((select count(*)::text from people.raw_clock_batch_rows where batch_id=pg_temp.wid('clock-reuse') and reused),
 '1','AC-405 reuse lineage names original event');
set local role authenticated;
insert into attendance_assertions select is(jsonb_array_length(api.people_attendance_clock_batches(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'))->'items')::text,'2','AC-405 scoped batch history');
insert into attendance_assertions select is(api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-reuse'))#>>'{rows,0,reused}','true','AC-405 immutable original event lineage');
insert into attendance_assertions select throws_ok($$select api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'),
 pg_temp.wid('employee'),pg_temp.wid('clock-reuse'))$$,'P0002','CLOCK_BATCH_NOT_FOUND','AC-401 cross-branch batch unavailable');
insert into attendance_assertions select throws_ok($$select api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-reuse'),201)$$,'22023','CLOCK_CURSOR_INVALID','NFR-405 batch cursor bound');
reset role;
insert into attendance_assertions select is((select count(*)::text from people.work_claims where source_kind='attendance'),
 '1','AC-405 raw imports do not create payable time');
insert into attendance_assertions select throws_ok($$update people.raw_clock_batches set manifest_digest=repeat('b',64) where id=pg_temp.wid('clock-batch')$$,
 '55000','WORK_HISTORY_IMMUTABLE','AC-405 batch history immutable');
create function pg_temp.clock_fail_late() returns trigger language plpgsql as $$begin
 if new.command_id=pg_temp.wid('clock-late-command') then
  raise exception using errcode='P0001',message='SYNTHETIC_CLOCK_LATE_FAILURE';end if;return new;
end $$;
create trigger synthetic_clock_fail_late before insert on core.outbox_events
 for each row execute function pg_temp.clock_fail_late();
set local role authenticated;
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-late',array['SYN-LATE']),'clock-late-command')$$,
 'P0001','SYNTHETIC_CLOCK_LATE_FAILURE','AC-401 late outbox failure rolls back batch');
reset role;
insert into attendance_assertions select ok(not exists(select 1 from people.raw_clock_events where source_key='SYN-LATE')
 and not exists(select 1 from people.raw_clock_batches where id=pg_temp.wid('clock-late')),
 'AC-401 late failure leaves no clock evidence or batch');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.attendance.import';
-- Grant restored only inside this rollback fixture for the declared job boundary.
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'people.attendance.import');
set local role authenticated;
insert into attendance_assertions select is(pg_temp.clock_cmd(pg_temp.clock_payload('clock-max',array(select 'BOUND-'||x::text from generate_series(1,200)x)),
 'clock-max-command')#>>'{entity,imported_count}','200','NFR-405 declared 200-row batch succeeds');
insert into attendance_assertions select is(jsonb_array_length(api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-max'))->'rows')::text,'50','NFR-405 lineage pages bounded to fifty');
insert into attendance_assertions select is(api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-max'),150)->>'next_position',null::text,'NFR-405 final lineage page has no cursor');
reset role;
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.attendance.import';
set local role authenticated;
insert into attendance_assertions select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command')$$,
 '42501',null,'AC-401 revoked import denied before replay');
reset role;

do $$declare v_failed text;begin
 select string_agg(message,chr(10)) into v_failed from attendance_assertions where message like 'not ok%';
 if v_failed is not null then raise exception using errcode='P0001',message=v_failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
rollback;