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
 name text not null,start_date date not null,end_date_exclusive date not null,planned_seconds bigint not null check(planned_seconds between 0 and 31622400),
 primary key(plan_id,id),unique(tenant_id,legal_entity_id,project_id,plan_id,id),
 check(length(name) between 1 and 160 and name=btrim(name) and name !~ '[[:cntrl:]]'),
 check(end_date_exclusive>start_date),
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
  if jsonb_typeof(p_payload->'resources') is distinct from 'array' or jsonb_array_length(p_payload->'resources')>366 then
   raise exception using errcode='22023',message='PROJECT_RESOURCE_LIMIT';end if;
  perform e.id from people.employees e where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id and
   e.id in(select (value->>'employee_id')::uuid from jsonb_array_elements(p_payload->'resources')) order by e.id for update;
 elsif act in('approve_plan','reject_plan','close') then
  perform e.id from people.employees e where e.tenant_id=p_tenant_id and e.legal_entity_id=p_legal_entity_id and e.id in(
   select s.employee_id from projects.resource_slots s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id
    and s.project_id=project_id and (s.active or s.plan_id=(p_payload->>'plan_id')::uuid)) order by e.id for update;
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
    if jsonb_typeof(x) is distinct from 'object' or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['id','name','start_date','end_date_exclusive','planned_seconds','dependencies']))
     or jsonb_typeof(x->'planned_seconds') is distinct from 'number' or coalesce(x->>'planned_seconds','') !~ '^(0|[1-9][0-9]{0,7})$'
     or jsonb_typeof(x->'dependencies') is distinct from 'array' or jsonb_array_length(x->'dependencies')>50
     or (x->>'start_date')::date<r.start_date or (x->>'end_date_exclusive')::date>r.end_date_exclusive
     or (x->>'planned_seconds')::bigint>((x->>'end_date_exclusive')::date-(x->>'start_date')::date)::bigint*86400 then
     raise exception using errcode='22023',message='PROJECT_TASK_INVALID';end if;
    insert into projects.tasks values(p_tenant_id,p_legal_entity_id,r.id,plan_id,(x->>'id')::uuid,projects.text(x->'name',160),
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
create function projects.slot_validate(t uuid,e uuid,b uuid,employee uuid,calendar uuid,start_local timestamp,end_local timestamp,
 start_offset integer,end_offset integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare c people.work_calendar_versions%rowtype;s timestamptz;z timestamptz;d date;pattern jsonb;x jsonb;start_min integer;end_min integer;matched boolean:=false;begin
 select * into c from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=calendar;
 if c.id is null then raise exception using errcode='P0002',message='PROJECT_CALENDAR_NOT_FOUND';end if;
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
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'project_id',q.project_id,'plan_id',q.plan_id,'name',q.name,'start_date',q.start_date,
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
 'tasks',jsonb_build_array(jsonb_build_object('id',pg_temp.wid('task'),'name','Delivery','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',7200,'dependencies','[]'::jsonb),
 jsonb_build_object('id',pg_temp.wid('task2'),'name','Review','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',0,'dependencies',jsonb_build_array(pg_temp.wid('task')))),
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
insert into project_responses values('plan',pg_temp.pc(pg_temp.project_plan(),1,'project-plan'));
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
 jsonb_build_array(jsonb_build_object('id',pg_temp.wid('task'),'name','Delivery','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',7200,'dependencies',jsonb_build_array(pg_temp.wid('task2'))),
 jsonb_build_object('id',pg_temp.wid('task2'),'name','Review','start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+2,'planned_seconds',0,'dependencies',jsonb_build_array(pg_temp.wid('task'))))),2,'cycle-plan')$$,'23514','PROJECT_TASK_CYCLE','AC-410 cycles rejected before effects');
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

do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from project_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
select jsonb_object_agg(label,body) project_client_samples from project_client_samples;
rollback;
