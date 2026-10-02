begin;
create temporary table w4_before as select jsonb_build_object('functions',coalesce((select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('result',pg_get_function_result(p.oid),'source_md5',md5(pg_get_functiondef(p.oid)),'grants',p.proacl::text)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('api','core','people','workforce','projects','service','payroll','assets','finance','inventory','procurement','sales','workflow')),'{}'),'tables',coalesce((select jsonb_object_agg(n.nspname||'.'||c.relname,jsonb_build_object('forced_rls',c.relforcerowsecurity,'rls',c.relrowsecurity,'grants',c.relacl::text,'columns',(select jsonb_object_agg(a.attname,jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),'constraints',(select coalesce(jsonb_agg(pg_get_constraintdef(k.oid) order by k.conname),'[]') from pg_constraint k where k.conrelid=c.oid))) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p') and n.nspname in('core','people','workforce','projects','service','payroll','assets','finance','inventory','procurement','sales','workflow')),'{}')) catalog;
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

-- W4-03B synthetic leave policy, append-only grants/effects and independent decisions.
-- Candidate only; depends on 20260928082234 and reviewed W4-02A prerequisites.
insert into core.permissions(code,module,description,privileged) values
 ('people.leave.view','people','Read scoped leave requests and balance',false),
 ('people.leave.manage','people','Prepare and submit scoped leave requests',true),
 ('people.leave.approve','people','Independently decide and cancel leave',true),
 ('people.leave.policy.manage','people','Publish synthetic leave policy versions',true),
 ('people.leave.adjust','people','Post reasoned synthetic leave grants',true)
on conflict(code) do nothing;

create table people.leave_policies(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
 name text not null check(length(btrim(name)) between 1 and 160),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create index leave_policies_creator_idx on people.leave_policies(created_by);

create table people.leave_policy_versions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 policy_id uuid not null,version bigint not null check(version between 1 and 9007199254740991),
 start_date date not null,end_date_exclusive date not null,
 unit text not null check(unit in ('hours','days')),
 day_seconds integer not null check(day_seconds between 1 and 86400),
 accrual_frequency text not null check(accrual_frequency in ('monthly','once')),
 accrual_seconds bigint not null check(accrual_seconds between 1 and 9007199254740991),
 carry_cap_seconds bigint not null check(carry_cap_seconds between 0 and 9007199254740991),
 expiry_days integer not null check(expiry_days between 1 and 3650),
 eligible_types text[] not null check(cardinality(eligible_types) between 1 and 4
  and eligible_types <@ array['permanent','fixed_term','casual','contractor']::text[]),
 allow_unpaid boolean not null default false,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 published_by uuid not null references auth.users(id),published_at timestamptz not null default clock_timestamp(),
 check(end_date_exclusive>start_date and end_date_exclusive-start_date<=1830),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,policy_id,id),
 unique(tenant_id,legal_entity_id,policy_id,version),
 foreign key(tenant_id,legal_entity_id,policy_id) references people.leave_policies(tenant_id,legal_entity_id,id),
 exclude using gist(policy_id extensions.gist_uuid_ops with =,
  daterange(start_date,end_date_exclusive,'[)') with &&)
);
create index leave_versions_scope_idx on people.leave_policy_versions(tenant_id,legal_entity_id,policy_id,id);
create index leave_versions_publisher_idx on people.leave_policy_versions(published_by);

create table people.leave_grants(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,
 policy_id uuid not null,policy_version_id uuid not null,
 source_kind text not null check(source_kind in ('accrual','adjustment','carry')),
 source_key text not null check(length(btrim(source_key)) between 1 and 160),
 effective_date date not null,expiry_date date not null,
 seconds bigint not null check(seconds between 1 and 9007199254740991),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,policy_id,source_kind,source_key),
 unique(tenant_id,legal_entity_id,employee_id,id),
 unique(tenant_id,legal_entity_id,employee_id,policy_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references people.leave_policies(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id,policy_version_id)
  references people.leave_policy_versions(tenant_id,legal_entity_id,policy_id,id),
 check(expiry_date>effective_date)
);
create index leave_grants_balance_idx on people.leave_grants(tenant_id,legal_entity_id,employee_id,policy_id,expiry_date,id);
create index leave_grants_version_idx on people.leave_grants(policy_version_id);
create index leave_grants_actor_idx on people.leave_grants(recorded_by);

create table people.leave_accounts(
 tenant_id uuid not null,legal_entity_id uuid not null,employee_id uuid not null,
 policy_id uuid not null,version bigint not null default 0
  check(version between 0 and 9007199254740991),
 primary key(tenant_id,legal_entity_id,employee_id,policy_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references people.leave_policies(tenant_id,legal_entity_id,id)
);
create index leave_accounts_policy_idx on people.leave_accounts(tenant_id,legal_entity_id,policy_id);

create table people.leave_requests(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,
 policy_id uuid not null,policy_version_id uuid not null,calendar_version_id uuid not null,
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 start_local timestamp not null,start_offset_seconds integer not null,
 end_local timestamp not null,end_offset_seconds integer not null,
 start_utc timestamptz not null,end_utc timestamptz not null,
 charge_seconds bigint not null check(charge_seconds between 1 and 129600),
 unpaid_seconds bigint not null default 0 check(unpaid_seconds>=0 and unpaid_seconds<=charge_seconds),
 status text not null check(status in ('draft','submitted','approved','rejected','cancelled')),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 submitted_by uuid references auth.users(id),decided_by uuid references auth.users(id),
 active_claim_id uuid,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references people.leave_policies(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id,policy_version_id)
  references people.leave_policy_versions(tenant_id,legal_entity_id,policy_id,id),
 foreign key(tenant_id,legal_entity_id,calendar_version_id)
  references people.work_calendar_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,active_claim_id)
  references people.work_claims(tenant_id,legal_entity_id,employee_id,id),
 check(end_utc>start_utc and end_utc-start_utc<=interval '36 hours')
);
create index leave_requests_scope_idx on people.leave_requests(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index leave_requests_policy_idx on people.leave_requests(policy_version_id);
create index leave_requests_claim_idx on people.leave_requests(active_claim_id);
create index leave_requests_creator_idx on people.leave_requests(created_by);
create index leave_requests_submitter_idx on people.leave_requests(submitted_by);
create index leave_requests_decider_idx on people.leave_requests(decided_by);

create table people.leave_adjustments(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,policy_id uuid not null,
 policy_version_id uuid not null,source_key text not null check(length(btrim(source_key)) between 1 and 160),
 effective_date date not null,seconds bigint not null
  check(seconds<>0 and seconds between -9007199254740991 and 9007199254740991),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,policy_id,source_key),
 unique(tenant_id,legal_entity_id,employee_id,policy_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id,policy_version_id)
  references people.leave_policy_versions(tenant_id,legal_entity_id,policy_id,id)
);
create index leave_adjustments_scope_idx on people.leave_adjustments(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index leave_adjustments_actor_idx on people.leave_adjustments(recorded_by);

create table people.leave_carry_events(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,policy_id uuid not null,
 prior_version_id uuid not null,new_version_id uuid not null,
 boundary_date date not null,source_seconds bigint not null check(source_seconds>=0),
 carried_seconds bigint not null check(carried_seconds>=0 and carried_seconds<=source_seconds),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,policy_id,boundary_date),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id,prior_version_id)
  references people.leave_policy_versions(tenant_id,legal_entity_id,policy_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id,new_version_id)
  references people.leave_policy_versions(tenant_id,legal_entity_id,policy_id,id)
);
create index leave_carry_scope_idx on people.leave_carry_events(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index leave_carry_prior_idx on people.leave_carry_events(prior_version_id);
create index leave_carry_new_idx on people.leave_carry_events(new_version_id);
create index leave_carry_actor_idx on people.leave_carry_events(recorded_by);

create table people.leave_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 employee_id uuid not null,policy_id uuid not null,grant_id uuid not null,
 request_id uuid,adjustment_id uuid,effective_date date not null,
 seconds bigint not null check(seconds<>0 and seconds between -9007199254740991 and 9007199254740991),
 reversal_of uuid unique,recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,policy_id,grant_id)
  references people.leave_grants(tenant_id,legal_entity_id,employee_id,policy_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,request_id)
  references people.leave_requests(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,policy_id,adjustment_id)
  references people.leave_adjustments(tenant_id,legal_entity_id,employee_id,policy_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,reversal_of)
  references people.leave_effects(tenant_id,legal_entity_id,employee_id,id),
 check((request_id is null)<>(adjustment_id is null)),
 check((reversal_of is null and seconds<0) or (reversal_of is not null and seconds>0))
);
create index leave_effects_grant_idx on people.leave_effects(tenant_id,legal_entity_id,employee_id,grant_id);
create index leave_effects_request_idx on people.leave_effects(tenant_id,legal_entity_id,employee_id,request_id);
create index leave_effects_actor_idx on people.leave_effects(recorded_by);

create table people.leave_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,request_id uuid not null,
 action text not null check(action in ('create','submit','approve','reject','cancel')),
 before_status text,after_status text not null,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 command_id uuid not null,unique(tenant_id,legal_entity_id,command_id),
 foreign key(tenant_id,legal_entity_id,employee_id,request_id)
  references people.leave_requests(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index leave_events_request_idx on people.leave_events(tenant_id,legal_entity_id,branch_id,request_id,id);
create index leave_events_actor_idx on people.leave_events(actor_id);

do $$declare v_table regclass;begin
 foreach v_table in array array[
  'people.leave_policies'::regclass,'people.leave_policy_versions'::regclass,
  'people.leave_grants'::regclass,'people.leave_accounts'::regclass,
  'people.leave_requests'::regclass,
  'people.leave_adjustments'::regclass,'people.leave_carry_events'::regclass,
  'people.leave_effects'::regclass,
  'people.leave_events'::regclass] loop
  execute format('alter table %s enable row level security',v_table);
  execute format('alter table %s force row level security',v_table);
  execute format('revoke all on %s from public,anon,authenticated',v_table);
 end loop;
end $$;

create function people.leave_history_guard() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='LEAVE_HISTORY_IMMUTABLE';
end $$;
create trigger leave_version_immutable before update or delete on people.leave_policy_versions
 for each row execute function people.leave_history_guard();
create trigger leave_grant_immutable before update or delete on people.leave_grants
 for each row execute function people.leave_history_guard();
create trigger leave_adjustment_immutable before update or delete on people.leave_adjustments
 for each row execute function people.leave_history_guard();
create trigger leave_carry_immutable before update or delete on people.leave_carry_events
 for each row execute function people.leave_history_guard();
create trigger leave_effect_immutable before update or delete on people.leave_effects
 for each row execute function people.leave_history_guard();
create trigger leave_event_immutable before update or delete on people.leave_events
 for each row execute function people.leave_history_guard();
create function people.leave_effect_insert_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_original people.leave_effects%rowtype;begin
 if new.reversal_of is not null then
  select * into v_original from people.leave_effects where id=new.reversal_of;
  if v_original.id is null or v_original.tenant_id<>new.tenant_id
   or v_original.legal_entity_id<>new.legal_entity_id
   or v_original.employee_id<>new.employee_id or v_original.policy_id<>new.policy_id
   or v_original.grant_id<>new.grant_id or v_original.request_id is distinct from new.request_id
   or v_original.seconds>=0 or v_original.reversal_of is not null
   or new.seconds<>-v_original.seconds then
   raise exception using errcode='23514',message='LEAVE_REVERSAL_MISMATCH';end if;
 end if;
 return new;
end $$;
create trigger leave_effect_exact_reversal before insert on people.leave_effects
 for each row execute function people.leave_effect_insert_guard();

create function people.leave_slot_charge(p_t uuid,p_e uuid,p_b uuid,p_employee uuid,
 p_policy_version uuid,p_calendar_version uuid,p_start_local timestamp,p_end_local timestamp,
 p_start_utc timestamptz,p_end_utc timestamptz)
returns bigint language plpgsql stable security definer set search_path='' as $$
declare v_policy people.leave_policy_versions%rowtype;v_calendar people.work_calendar_versions%rowtype;
 v_slot jsonb;v_count integer;v_slot_start timestamp;v_slot_end timestamp;v_day date;
 v_type text;v_charge bigint;begin
 select * into v_policy from people.leave_policy_versions where tenant_id=p_t
  and legal_entity_id=p_e and id=p_policy_version;
 select * into v_calendar from people.work_calendar_versions where tenant_id=p_t
  and legal_entity_id=p_e and id=p_calendar_version;
 if v_policy.id is null or v_calendar.id is null or p_start_local is null or p_end_local is null
  or p_end_local<=p_start_local or p_end_utc<=p_start_utc
  or p_end_utc-p_start_utc>interval '36 hours' then
  raise exception using errcode='22023',message='LEAVE_SLOT_INVALID';end if;
 v_day:=p_start_local::date;
 if not daterange(v_policy.start_date,v_policy.end_date_exclusive,'[)') @>
  daterange(v_day,(p_end_local-interval '1 microsecond')::date+1,'[)') then
  raise exception using errcode='55000',message='LEAVE_POLICY_NOT_EFFECTIVE';end if;
 perform people.work_local_coverage(p_t,p_e,p_b,p_employee,p_calendar_version,p_start_local,p_end_local);
 if exists(select 1 from jsonb_array_elements(v_calendar.date_overrides) o
  where o->>'date'=v_day::text and (o->>'is_working_day')::boolean=false) then
  raise exception using errcode='55000',message='LEAVE_NONWORKING_DAY';end if;
 select count(*),jsonb_agg(value)->0 into v_count,v_slot
 from jsonb_array_elements(v_calendar.weekly_intervals) value
 where (value->>'day_of_week')::integer=extract(isodow from v_day)::integer;
 if v_count<>1 then
  raise exception using errcode='55000',message='LEAVE_SINGLE_WORK_SLOT_REQUIRED';end if;
 v_slot_start:=v_day::timestamp+(v_slot->>'start_minute')::integer*interval '1 minute';
 v_slot_end:=v_day::timestamp+(v_slot->>'end_day_offset')::integer*interval '1 day'
  +(v_slot->>'end_minute')::integer*interval '1 minute';
 if p_start_local<v_slot_start or p_end_local>v_slot_end then
  raise exception using errcode='22023',message='LEAVE_OUTSIDE_WORK_SLOT';end if;
 select a.employment_type into v_type from people.employment_assignments a
 where a.tenant_id=p_t and a.legal_entity_id=p_e and a.branch_id=p_b
  and a.employee_id=p_employee and daterange(a.start_date,a.end_date_exclusive,'[)') @> v_day;
 if v_type is null or not(v_type=any(v_policy.eligible_types)) then
  raise exception using errcode='42501',message='LEAVE_NOT_ELIGIBLE';end if;
 if v_policy.unit='days' then
  if p_start_local<>v_slot_start or p_end_local<>v_slot_end then
   raise exception using errcode='22023',message='LEAVE_FULL_DAY_REQUIRED';end if;
  v_charge:=v_policy.day_seconds;
 else v_charge:=extract(epoch from p_end_utc-p_start_utc)::bigint;end if;
 if v_charge<1 or v_charge>129600 then
  raise exception using errcode='22023',message='LEAVE_CHARGE_INVALID';end if;
 return v_charge;
end $$;

create function people.leave_policy_payload(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'version',p.version,
  'versions',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'version',v.version,
   'start_date',v.start_date,'end_date_exclusive',v.end_date_exclusive,
   'unit',v.unit,'day_seconds',v.day_seconds,'accrual_frequency',v.accrual_frequency,
   'accrual_seconds',v.accrual_seconds,'carry_cap_seconds',v.carry_cap_seconds,
   'expiry_days',v.expiry_days,'eligible_types',to_jsonb(v.eligible_types),
   'allow_unpaid',v.allow_unpaid,'reason',v.reason,'published_by',v.published_by,
   'published_at',v.published_at) order by v.version)
   from (select * from people.leave_policy_versions
    where policy_id=p.id order by version desc limit 1) v),'[]'::jsonb))
 from people.leave_policies p where p.id=p_id
$$;

create function api.people_leave_policies(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 select coalesce(jsonb_agg(people.leave_policy_payload(q.id) order by q.id),'[]'::jsonb)
 into v_items from(select id from people.leave_policies where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and (p_after is null or id>p_after)
  order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'items',v_items-50,
  'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_leave_policy_versions(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_policy_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 if p_policy_id is null or not exists(select 1 from people.leave_policies
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_policy_id) then
  raise exception using errcode='P0002',message='LEAVE_POLICY_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'version',q.version,
  'start_date',q.start_date,'end_date_exclusive',q.end_date_exclusive,
  'unit',q.unit,'day_seconds',q.day_seconds,'accrual_frequency',q.accrual_frequency,
  'accrual_seconds',q.accrual_seconds,'carry_cap_seconds',q.carry_cap_seconds,
  'expiry_days',q.expiry_days,'eligible_types',to_jsonb(q.eligible_types),
  'allow_unpaid',q.allow_unpaid,'reason',q.reason,'published_by',q.published_by,
  'published_at',q.published_at) order by q.id),'[]'::jsonb) into v_items
 from(select * from people.leave_policy_versions where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and policy_id=p_policy_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'policy_id',p_policy_id,'items',v_items-50,
  'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_leave_policy_for_version(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_version_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_policy uuid;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 select policy_id into v_policy from people.leave_policy_versions where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=p_version_id;
 if not found then raise exception using errcode='P0002',message='LEAVE_POLICY_VERSION_NOT_FOUND';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'policy_version_id',p_version_id,'policy',people.leave_policy_payload(v_policy));
end $$;

create function api.people_leave_policy_command(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_actor uuid:=auth.uid();v_id uuid;v_version_id uuid;
 v_policy people.leave_policies%rowtype;v_before jsonb:='{}'::jsonb;v_after jsonb;
 v_hash text;v_replay jsonb;v_start date;v_end date;v_types text[];
 v_request uuid:=gen_random_uuid();begin
 if true=any(array[
  p_command_id is null,p_idempotency_key is null,p_client_timestamp is null,
  coalesce(jsonb_typeof(p_payload),'null')<>'object',
  v_action is null or v_action not in ('create','publish'),
  coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  coalesce(p_payload->>'version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  coalesce(p_payload->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$',
  coalesce(p_payload->>'end_date_exclusive','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$',
  coalesce(jsonb_typeof(p_payload->'eligible_types'),'null')<>'array',
  p_expected_version is null]) then
  raise exception using errcode='22023',message='LEAVE_POLICY_INVALID';end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(
  case when v_action='create' then array['action','id','version_id','code','name',
   'start_date','end_date_exclusive','unit','day_seconds','accrual_frequency',
   'accrual_seconds','carry_cap_seconds','expiry_days','eligible_types','allow_unpaid','reason']
  else array['action','id','version_id','start_date','end_date_exclusive','unit',
   'day_seconds','accrual_frequency','accrual_seconds','carry_cap_seconds','expiry_days',
   'eligible_types','allow_unpaid','reason'] end)) then
  raise exception using errcode='22023',message='LEAVE_POLICY_FIELDS_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.policy.manage');
 perform core.require_permission(p_tenant_id,'people.leave.policy.manage',p_legal_entity_id,null);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='LEAVE_MFA_REQUIRED';end if;
 v_id:=(p_payload->>'id')::uuid;v_version_id:=(p_payload->>'version_id')::uuid;
 v_hash:=core.wave3_request_hash('people.leave.policy.'||v_action,p_command_id,
  p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.leave.policy.'||v_action,
  p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 v_start:=(p_payload->>'start_date')::date;v_end:=(p_payload->>'end_date_exclusive')::date;
 if not isfinite(v_start) or not isfinite(v_end) or v_end<=v_start
  or v_end-v_start>1830 or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000
  or p_payload->>'unit' not in ('hours','days')
  or p_payload->>'accrual_frequency' not in ('monthly','once')
  or coalesce(p_payload->>'day_seconds','') !~ '^[0-9]{1,5}$'
  or coalesce(p_payload->>'accrual_seconds','') !~ '^[0-9]{1,16}$'
  or coalesce(p_payload->>'carry_cap_seconds','') !~ '^[0-9]{1,16}$'
  or coalesce(p_payload->>'expiry_days','') !~ '^[0-9]{1,4}$'
  or jsonb_array_length(p_payload->'eligible_types') not between 1 and 4
  or coalesce(jsonb_typeof(p_payload->'allow_unpaid'),'null')<>'boolean' then
  raise exception using errcode='22023',message='LEAVE_POLICY_INVALID';end if;
 select array_agg(x order by x) into v_types
 from jsonb_array_elements_text(p_payload->'eligible_types') x;
 if v_types is null or cardinality(v_types)<>cardinality(array(select distinct unnest(v_types)))
  or not(v_types <@ array['permanent','fixed_term','casual','contractor']::text[])
  or (p_payload->>'day_seconds')::integer not between 1 and 86400
  or (p_payload->>'accrual_seconds')::bigint not between 1 and 9007199254740991
  or (p_payload->>'carry_cap_seconds')::bigint not between 0 and 9007199254740991
  or (p_payload->>'expiry_days')::integer not between 1 and 3650 then
  raise exception using errcode='22023',message='LEAVE_POLICY_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('people.leave.policy:'||p_tenant_id||':'||p_legal_entity_id,0));
 if v_action='create' then
  if p_expected_version<>0 or coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'
   or length(btrim(coalesce(p_payload->>'name',''))) not between 1 and 160 then
   raise exception using errcode='22023',message='LEAVE_POLICY_INVALID';end if;
  insert into people.leave_policies(id,tenant_id,legal_entity_id,code,name,created_by)
   values(v_id,p_tenant_id,p_legal_entity_id,p_payload->>'code',p_payload->>'name',v_actor);
 else
  select * into v_policy from people.leave_policies where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and id=v_id for update;
  if not found then raise exception using errcode='P0002',message='LEAVE_POLICY_NOT_FOUND';end if;
  v_before:=people.leave_policy_payload(v_id);
  perform core.wave3_assert_expected_version(v_policy.version,p_expected_version,v_before);
  update people.leave_policies set version=version+1 where id=v_id;
 end if;
 insert into people.leave_policy_versions(id,tenant_id,legal_entity_id,policy_id,version,
  start_date,end_date_exclusive,unit,day_seconds,accrual_frequency,accrual_seconds,
  carry_cap_seconds,expiry_days,eligible_types,allow_unpaid,reason,published_by)
 values(v_version_id,p_tenant_id,p_legal_entity_id,v_id,
  case when v_action='create' then 1 else v_policy.version+1 end,
  v_start,v_end,p_payload->>'unit',(p_payload->>'day_seconds')::integer,
  p_payload->>'accrual_frequency',(p_payload->>'accrual_seconds')::bigint,
  (p_payload->>'carry_cap_seconds')::bigint,(p_payload->>'expiry_days')::integer,
  v_types,(p_payload->>'allow_unpaid')::boolean,btrim(p_payload->>'reason'),v_actor);
 v_after:=people.leave_policy_payload(v_id);
 return core.wave3_finish_command(p_tenant_id,'people.leave.policy.'||v_action,p_command_id,
  'people.leave.policy',v_id,p_idempotency_key,v_hash,v_before,v_after,
  p_legal_entity_id,p_branch_id,p_request_id=>v_request);
end $$;

create function people.leave_available(p_t uuid,p_e uuid,p_employee uuid,p_policy uuid,
 p_on date,p_recorded_before timestamptz default null)
returns bigint language plpgsql stable security definer set search_path='' as $$
declare v_total numeric;begin
 select coalesce(sum(g.seconds+coalesce((select sum(x.seconds) from people.leave_effects x
   where x.tenant_id=p_t and x.legal_entity_id=p_e and x.employee_id=p_employee
    and x.policy_id=p_policy and x.grant_id=g.id
    and x.effective_date<=p_on and (p_recorded_before is null or x.recorded_at<=p_recorded_before)),0)),0)
 into v_total from people.leave_grants g where g.tenant_id=p_t and g.legal_entity_id=p_e
  and g.employee_id=p_employee and g.policy_id=p_policy
  and g.effective_date<=p_on and g.expiry_date>p_on
  and (p_recorded_before is null or g.recorded_at<=p_recorded_before);
 if v_total<0 or v_total>9007199254740991 then
  raise exception using errcode='23514',message='LEAVE_BALANCE_INVALID';end if;
 return v_total::bigint;
end $$;

create function people.allocate_leave(p_t uuid,p_e uuid,p_employee uuid,p_policy uuid,
 p_request uuid,p_adjustment uuid,p_valid_on date,p_effective date,p_seconds bigint,
 p_actor uuid,p_allow_partial boolean default false)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_grant people.leave_grants%rowtype;v_available numeric;v_take bigint;
 v_remaining bigint:=p_seconds;begin
 if (p_request is null)=(p_adjustment is null) or p_seconds is null or p_seconds<1
  or p_seconds>9007199254740991 or p_actor is null or p_valid_on is null
  or p_effective is null then
  raise exception using errcode='22023',message='LEAVE_ALLOCATION_INVALID';end if;
 -- The caller owns the employee row lock; grant row locks document and reinforce
 -- the same deterministic expiry/effective/ID allocation order.
 for v_grant in select * from people.leave_grants where tenant_id=p_t and legal_entity_id=p_e
  and employee_id=p_employee and policy_id=p_policy and effective_date<=p_valid_on
  and expiry_date>p_valid_on order by expiry_date,effective_date,id for update loop
  select v_grant.seconds+coalesce(sum(x.seconds),0) into v_available
   from people.leave_effects x where x.tenant_id=p_t and x.legal_entity_id=p_e
    and x.employee_id=p_employee and x.policy_id=p_policy and x.grant_id=v_grant.id;
  if v_available<0 or v_available>v_grant.seconds then
   raise exception using errcode='23514',message='LEAVE_GRANT_BALANCE_INVALID';end if;
  if v_available=0 then continue;end if;
  v_take:=least(v_remaining,v_available)::bigint;
  insert into people.leave_effects(tenant_id,legal_entity_id,employee_id,policy_id,grant_id,
   request_id,adjustment_id,effective_date,seconds,recorded_by)
  values(p_t,p_e,p_employee,p_policy,v_grant.id,p_request,p_adjustment,p_effective,-v_take,p_actor);
  v_remaining:=v_remaining-v_take;
  if v_remaining=0 then exit;end if;
 end loop;
 if v_remaining>0 and not p_allow_partial then
  raise exception using errcode='23514',message='LEAVE_BALANCE_INSUFFICIENT';end if;
 return v_remaining;
end $$;

create function api.people_leave_balance(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_employee_id uuid,p_policy_id uuid,p_as_of date,
 p_recorded_before timestamptz default null,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;v_total bigint;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 if p_employee_id is null or p_policy_id is null or p_as_of is null or not isfinite(p_as_of)
  or not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='LEAVE_SCOPE_DENIED';end if;
 v_total:=people.leave_available(p_tenant_id,p_legal_entity_id,p_employee_id,p_policy_id,
  p_as_of,p_recorded_before);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'source_kind',q.source_kind,
  'source_key',q.source_key,'effective_date',q.effective_date,'expiry_date',q.expiry_date,
  'seconds',q.seconds,'remaining_seconds',q.remaining_seconds,
  'policy_version_id',q.policy_version_id,'recorded_at',q.recorded_at) order by q.id),'[]'::jsonb)
 into v_items from(select g.*,
  g.seconds+coalesce((select sum(x.seconds) from people.leave_effects x
   where x.grant_id=g.id and x.effective_date<=p_as_of
    and (p_recorded_before is null or x.recorded_at<=p_recorded_before)),0) remaining_seconds
  from people.leave_grants g where g.tenant_id=p_tenant_id and g.legal_entity_id=p_legal_entity_id
   and g.employee_id=p_employee_id and g.policy_id=p_policy_id
   and (p_after is null or g.id>p_after) and
   (p_recorded_before is null or g.recorded_at<=p_recorded_before)
  order by g.id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',p_employee_id,'policy_id',p_policy_id,
  'as_of',p_as_of,'recorded_before',p_recorded_before,'available_seconds',v_total,
  'account_version',coalesce((select version from people.leave_accounts where
   tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employee_id=p_employee_id
   and policy_id=p_policy_id),0),
  'grants',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_leave_grant_command(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_actor uuid:=auth.uid();v_id uuid;v_employee uuid;
 v_policy people.leave_policy_versions%rowtype;v_prior people.leave_policy_versions%rowtype;
 v_account people.leave_accounts%rowtype;
 v_hash text;v_replay jsonb;v_effective date;v_today date;v_type text;
 v_amount bigint;v_source_amount numeric;v_source text;v_before jsonb;v_after jsonb;
 v_request uuid:=gen_random_uuid();begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or coalesce(jsonb_typeof(p_payload),'null')<>'object'
  or v_action is null or v_action not in ('accrue','adjust','carry')
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'employee_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'policy_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or p_expected_version is null then
  raise exception using errcode='22023',message='LEAVE_GRANT_INVALID';end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(
  case when v_action='accrue' then array['action','id','employee_id','policy_version_id',
   'period_start','reason']
  when v_action='carry' then array['action','id','employee_id','policy_version_id',
   'prior_version_id','boundary_date','reason']
  else array['action','id','employee_id','policy_version_id',
   'effective_date','source_key','seconds','reason'] end)) then
  raise exception using errcode='22023',message='LEAVE_GRANT_FIELDS_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when v_action in ('accrue','carry') then 'people.leave.policy.manage'
   else 'people.leave.adjust' end);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='LEAVE_MFA_REQUIRED';end if;
 v_id:=(p_payload->>'id')::uuid;v_employee:=(p_payload->>'employee_id')::uuid;
 select * into v_policy from people.leave_policy_versions where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=(p_payload->>'policy_version_id')::uuid;
 if not found then raise exception using errcode='P0002',message='LEAVE_POLICY_NOT_FOUND';end if;
 if not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and employee_id=v_employee) then
  raise exception using errcode='42501',message='LEAVE_SCOPE_DENIED';end if;
 v_hash:=core.wave3_request_hash('people.leave.grant.'||v_action,p_command_id,
  p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.leave.grant.'||v_action,
  p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and id=v_employee for update;
 if not found then raise exception using errcode='P0002',message='LEAVE_EMPLOYEE_NOT_FOUND';end if;
 insert into people.leave_accounts(tenant_id,legal_entity_id,employee_id,policy_id)
 values(p_tenant_id,p_legal_entity_id,v_employee,v_policy.policy_id) on conflict do nothing;
 select * into v_account from people.leave_accounts where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and employee_id=v_employee
  and policy_id=v_policy.policy_id for update;
 perform core.wave3_assert_expected_version(v_account.version,p_expected_version,
  jsonb_build_object('account_version',v_account.version));
 select timezone into v_type from core.legal_entities where tenant_id=p_tenant_id
  and id=p_legal_entity_id;
 v_today:=(now() at time zone v_type)::date;
 if v_action='accrue' then
  if coalesce(p_payload->>'period_start','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
   raise exception using errcode='22023',message='LEAVE_ACCRUAL_PERIOD_INVALID';end if;
  v_effective:=(p_payload->>'period_start')::date;
  if (v_policy.accrual_frequency='monthly' and extract(day from v_effective)<>1)
   or (v_policy.accrual_frequency='once' and v_effective<>v_policy.start_date)
   or v_effective>=v_policy.end_date_exclusive
   or v_effective+interval '1 month'<=v_policy.start_date then
   raise exception using errcode='22023',message='LEAVE_ACCRUAL_PERIOD_INVALID';end if;
  v_source:=to_char(v_effective,'YYYY-MM');
  v_effective:=greatest(v_effective,v_policy.start_date);
  v_amount:=v_policy.accrual_seconds;
 elsif v_action='carry' then
  if coalesce(p_payload->>'prior_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(p_payload->>'boundary_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
   raise exception using errcode='22023',message='LEAVE_CARRY_INVALID';end if;
  select * into v_prior from people.leave_policy_versions where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and policy_id=v_policy.policy_id
   and id=(p_payload->>'prior_version_id')::uuid;
  v_effective:=(p_payload->>'boundary_date')::date;
  if v_prior.id is null or v_prior.id=v_policy.id
   or v_prior.end_date_exclusive<>v_effective or v_policy.start_date<>v_effective then
   raise exception using errcode='22023',message='LEAVE_CARRY_INVALID';end if;
  v_source:='carry:'||v_prior.id::text||':'||v_effective::text;
  select coalesce(sum(g.seconds+coalesce((select sum(x.seconds) from people.leave_effects x
   where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id
    and x.employee_id=v_employee and x.policy_id=v_policy.policy_id and x.grant_id=g.id),0)),0)
  into v_source_amount from people.leave_grants g where g.tenant_id=p_tenant_id
   and g.legal_entity_id=p_legal_entity_id and g.employee_id=v_employee
   and g.policy_id=v_policy.policy_id and g.policy_version_id=v_prior.id
   and g.expiry_date=v_effective;
  if v_source_amount<0 or v_source_amount>9007199254740991 then
   raise exception using errcode='23514',message='LEAVE_CARRY_BALANCE_INVALID';end if;
  v_amount:=least(v_source_amount,v_policy.carry_cap_seconds)::bigint;
 else
  if coalesce(p_payload->>'effective_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(p_payload->>'seconds','') !~ '^-?[0-9]{1,16}$'
   or length(btrim(coalesce(p_payload->>'source_key',''))) not between 1 and 160 then
   raise exception using errcode='22023',message='LEAVE_ADJUSTMENT_INVALID';end if;
  v_effective:=(p_payload->>'effective_date')::date;
  v_amount:=(p_payload->>'seconds')::bigint;
  v_source:=btrim(p_payload->>'source_key');
  if v_amount=0 or abs(v_amount)>9007199254740991 then
   raise exception using errcode='22023',message='LEAVE_ADJUSTMENT_INVALID';end if;
 end if;
 if v_effective<v_policy.start_date or v_effective>=v_policy.end_date_exclusive
  or v_effective>v_today or v_effective+v_policy.expiry_days>date '9999-12-31'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='LEAVE_GRANT_DATE_INVALID';end if;
 select a.employment_type into v_type from people.employment_assignments a
 where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.branch_id=p_branch_id and a.employee_id=v_employee
  and daterange(a.start_date,a.end_date_exclusive,'[)') @> v_effective;
 if v_type is null or not(v_type=any(v_policy.eligible_types)) then
  raise exception using errcode='42501',message='LEAVE_NOT_ELIGIBLE';end if;
 v_before:=jsonb_build_object('account_version',v_account.version,
  'available_seconds',people.leave_available(p_tenant_id,p_legal_entity_id,
   v_employee,v_policy.policy_id,v_today));
 if v_action='adjust' then
  insert into people.leave_adjustments(id,tenant_id,legal_entity_id,branch_id,
   employee_id,policy_id,policy_version_id,source_key,effective_date,seconds,reason,recorded_by)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_policy.policy_id,
   v_policy.id,v_source,v_effective,v_amount,btrim(p_payload->>'reason'),v_actor);
 elsif v_action='carry' then
  insert into people.leave_carry_events(id,tenant_id,legal_entity_id,branch_id,
   employee_id,policy_id,prior_version_id,new_version_id,boundary_date,
   source_seconds,carried_seconds,reason,recorded_by)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_policy.policy_id,
   v_prior.id,v_policy.id,v_effective,v_source_amount::bigint,v_amount,
   btrim(p_payload->>'reason'),v_actor);
 end if;
 if v_amount>0 then
  insert into people.leave_grants(id,tenant_id,legal_entity_id,branch_id,
   employee_id,policy_id,policy_version_id,source_kind,source_key,
   effective_date,expiry_date,seconds,reason,recorded_by)
  values(case when v_action='accrue' then v_id else gen_random_uuid() end,
   p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_policy.policy_id,v_policy.id,
   case when v_action='accrue' then 'accrual'
    when v_action='carry' then 'carry' else 'adjustment' end,
   v_source,v_effective,v_effective+v_policy.expiry_days,v_amount,
   btrim(p_payload->>'reason'),v_actor);
 elsif v_amount<0 then
  perform people.allocate_leave(p_tenant_id,p_legal_entity_id,v_employee,v_policy.policy_id,
   null,v_id,v_effective,v_today,-v_amount,v_actor);
 end if;
 update people.leave_accounts set version=version+1 where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and employee_id=v_employee and policy_id=v_policy.policy_id;
 v_after:=jsonb_build_object('id',v_id,'employee_id',v_employee,'policy_id',v_policy.policy_id,
  'policy_version_id',v_policy.id,'source_kind',v_action,'source_key',v_source,
  'effective_date',v_effective,'seconds',v_amount,'account_version',v_account.version+1,
  'available_seconds',people.leave_available(p_tenant_id,p_legal_entity_id,
   v_employee,v_policy.policy_id,v_today));
 return core.wave3_finish_command(p_tenant_id,'people.leave.grant.'||v_action,p_command_id,
  'people.leave.grant',v_id,p_idempotency_key,v_hash,v_before,v_after,
  p_legal_entity_id,p_branch_id,p_request_id=>v_request);
end $$;

create function people.leave_request_summary(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',r.id,'employee_id',r.employee_id,'policy_id',r.policy_id,
  'policy_version_id',r.policy_version_id,'calendar_version_id',r.calendar_version_id,
  'version',r.version,'status',r.status,'start_utc',r.start_utc,'end_utc',r.end_utc,
  'charge_seconds',r.charge_seconds,'unpaid_seconds',r.unpaid_seconds,
  'active_claim_id',r.active_claim_id,'created_by',r.created_by,
  'submitted_by',r.submitted_by,'decided_by',r.decided_by)
 from people.leave_requests r where r.id=p_id
$$;
create function people.leave_request_private(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select people.leave_request_summary(r.id)||jsonb_build_object(
  'tenant_id',r.tenant_id,'legal_entity_id',r.legal_entity_id,'branch_id',r.branch_id,
  'start_local',r.start_local,'start_offset_seconds',r.start_offset_seconds,
  'end_local',r.end_local,'end_offset_seconds',r.end_offset_seconds,
  'reason',r.reason,'created_at',r.created_at)
 from people.leave_requests r where r.id=p_id
$$;
create function api.people_leave_requests(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_employee_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 if p_employee_id is null or not exists(select 1 from people.employment_assignments
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='LEAVE_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(people.leave_request_private(q.id) order by q.id),'[]'::jsonb)
 into v_items from(select id from people.leave_requests where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',p_employee_id,'items',v_items-50,
  'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;
create function api.people_leave_detail(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_request_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_request people.leave_requests%rowtype;v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 select * into v_request from people.leave_requests where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_request_id;
 if not found then raise exception using errcode='P0002',message='LEAVE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'action',q.action,
  'before_status',q.before_status,'after_status',q.after_status,
  'reason',q.reason,'actor_id',q.actor_id,'recorded_at',q.recorded_at) order by q.id),'[]'::jsonb)
 into v_items from(select * from people.leave_events where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and request_id=p_request_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'request',people.leave_request_private(p_request_id),
  'history',v_items-50,'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

create function api.people_leave_request_command(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_actor uuid:=auth.uid();v_id uuid;v_employee uuid;
 v_request people.leave_requests%rowtype;v_policy people.leave_policy_versions%rowtype;
 v_calendar people.work_calendar_versions%rowtype;v_account people.leave_accounts%rowtype;
 v_start_local timestamp;v_end_local timestamp;v_start timestamptz;v_end timestamptz;
 v_reason text;v_today date;v_timezone text;v_charge bigint;v_unpaid bigint;
 v_claim uuid;v_hash text;v_replay jsonb;v_before jsonb:='{}'::jsonb;v_after jsonb;
 v_request_id uuid:=gen_random_uuid();begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or coalesce(jsonb_typeof(p_payload),'null')<>'object'
  or v_action is null or v_action not in ('create','submit','approve','reject','cancel')
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'employee_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or p_expected_version is null then
  raise exception using errcode='22023',message='LEAVE_REQUEST_INVALID';end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(
  case when v_action='create' then array['action','id','employee_id','policy_version_id',
   'calendar_version_id','start_local','start_offset_seconds','end_local',
   'end_offset_seconds','reason']
  when v_action in ('approve','cancel') then array['action','id','employee_id','balance_version','reason']
  else array['action','id','employee_id','reason'] end)) then
  raise exception using errcode='22023',message='LEAVE_REQUEST_FIELDS_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when v_action in ('approve','reject','cancel') then 'people.leave.approve'
   else 'people.leave.manage' end);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='LEAVE_MFA_REQUIRED';end if;
 v_id:=(p_payload->>'id')::uuid;v_employee:=(p_payload->>'employee_id')::uuid;
 if not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and employee_id=v_employee) then
  raise exception using errcode='42501',message='LEAVE_SCOPE_DENIED';end if;
 v_hash:=core.wave3_request_hash('people.leave.request.'||v_action,p_command_id,
  p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.leave.request.'||v_action,
  p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and id=v_employee for update;
 if not found then raise exception using errcode='P0002',message='LEAVE_EMPLOYEE_NOT_FOUND';end if;
 v_reason:=btrim(coalesce(p_payload->>'reason',''));
 if length(v_reason) not between 1 and 1000 then
  raise exception using errcode='22023',message='LEAVE_REASON_REQUIRED';end if;
 select timezone into v_timezone from core.legal_entities where tenant_id=p_tenant_id
  and id=p_legal_entity_id;
 v_today:=(now() at time zone v_timezone)::date;
 if v_action='create' then
  if p_expected_version<>0
   or coalesce(p_payload->>'policy_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(p_payload->>'calendar_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(p_payload->>'start_local','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'
   or coalesce(p_payload->>'end_local','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'
   or coalesce(p_payload->>'start_offset_seconds','') !~ '^-?[0-9]{1,5}$'
   or coalesce(p_payload->>'end_offset_seconds','') !~ '^-?[0-9]{1,5}$' then
   raise exception using errcode='22023',message='LEAVE_BOUNDARY_INVALID';end if;
  select * into v_policy from people.leave_policy_versions where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and id=(p_payload->>'policy_version_id')::uuid;
  select * into v_calendar from people.work_calendar_versions where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and id=(p_payload->>'calendar_version_id')::uuid;
  if v_policy.id is null or v_calendar.id is null then
   raise exception using errcode='P0002',message='LEAVE_CONFIGURATION_NOT_FOUND';end if;
  v_start_local:=(p_payload->>'start_local')::timestamp;
  v_end_local:=(p_payload->>'end_local')::timestamp;
  v_start:=people.resolve_local_instant(v_calendar.timezone,v_start_local,
   (p_payload->>'start_offset_seconds')::integer);
  v_end:=people.resolve_local_instant(v_calendar.timezone,v_end_local,
   (p_payload->>'end_offset_seconds')::integer);
  v_charge:=people.leave_slot_charge(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,
   v_policy.id,v_calendar.id,v_start_local,v_end_local,v_start,v_end);
  insert into people.leave_requests(id,tenant_id,legal_entity_id,branch_id,employee_id,
   policy_id,policy_version_id,calendar_version_id,start_local,start_offset_seconds,
   end_local,end_offset_seconds,start_utc,end_utc,charge_seconds,status,reason,created_by)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_policy.policy_id,
   v_policy.id,v_calendar.id,v_start_local,(p_payload->>'start_offset_seconds')::integer,
   v_end_local,(p_payload->>'end_offset_seconds')::integer,v_start,v_end,v_charge,
   'draft',v_reason,v_actor);
 else
  select * into v_request from people.leave_requests where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and employee_id=v_employee and id=v_id for update;
  if not found then raise exception using errcode='P0002',message='LEAVE_NOT_FOUND';end if;
  v_before:=people.leave_request_summary(v_id);
  perform core.wave3_assert_expected_version(v_request.version,p_expected_version,v_before);
  if v_action='submit' then
   if v_request.status not in ('draft','rejected') then
    raise exception using errcode='55000',message='LEAVE_STATE_INVALID';end if;
   update people.leave_requests set version=version+1,status='submitted',submitted_by=v_actor,
    decided_by=null where id=v_id;
  elsif v_action in ('approve','reject') then
   if v_request.status<>'submitted' or v_request.submitted_by=v_actor
    or v_request.created_by=v_actor then
    raise exception using errcode='55000',message='LEAVE_INDEPENDENT_DECISION_REQUIRED';end if;
   if v_action='reject' then
    update people.leave_requests set version=version+1,status='rejected',decided_by=v_actor
     where id=v_id;
   else
    select * into v_policy from people.leave_policy_versions where id=v_request.policy_version_id;
    v_charge:=people.leave_slot_charge(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,
     v_policy.id,v_request.calendar_version_id,v_request.start_local,v_request.end_local,
     v_request.start_utc,v_request.end_utc);
    if v_charge<>v_request.charge_seconds then
     raise exception using errcode='55000',message='LEAVE_INPUT_CHANGED';end if;
    insert into people.leave_accounts(tenant_id,legal_entity_id,employee_id,policy_id)
     values(p_tenant_id,p_legal_entity_id,v_employee,v_request.policy_id) on conflict do nothing;
    select * into v_account from people.leave_accounts where tenant_id=p_tenant_id
     and legal_entity_id=p_legal_entity_id and employee_id=v_employee
     and policy_id=v_request.policy_id for update;
    if coalesce(p_payload->>'balance_version','') !~ '^[0-9]{1,16}$' then
     raise exception using errcode='22023',message='LEAVE_BALANCE_VERSION_REQUIRED';end if;
    perform core.wave3_assert_expected_version(v_account.version,
     (p_payload->>'balance_version')::bigint,jsonb_build_object('account_version',v_account.version));
    perform people.consume_organization(p_tenant_id,p_legal_entity_id,p_branch_id,
     v_employee,'leave',v_id,v_request.start_local::date,
     (v_request.end_local-interval '1 microsecond')::date+1);
    begin
     v_claim:=people.make_work_claim(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,
      'leave',v_id,v_request.start_utc,v_request.end_utc,'[]'::jsonb,
      v_request.calendar_version_id,v_actor);
    exception when exclusion_violation then
     raise exception using errcode='23514',message='WORK_INTERVAL_CONFLICT';
    end;
    v_unpaid:=people.allocate_leave(p_tenant_id,p_legal_entity_id,v_employee,
     v_request.policy_id,v_id,null,v_request.start_local::date,v_today,
     v_request.charge_seconds,v_actor,v_policy.allow_unpaid);
    update people.leave_accounts set version=version+1 where tenant_id=p_tenant_id
     and legal_entity_id=p_legal_entity_id and employee_id=v_employee
     and policy_id=v_request.policy_id;
    update people.leave_requests set version=version+1,status='approved',decided_by=v_actor,
     active_claim_id=v_claim,unpaid_seconds=v_unpaid where id=v_id;
   end if;
  else
   if v_request.status<>'approved' or v_request.active_claim_id is null
    or v_request.submitted_by=v_actor or v_request.created_by=v_actor then
    raise exception using errcode='55000',message='LEAVE_CANCELLATION_INVALID';end if;
   if coalesce(p_payload->>'balance_version','') !~ '^[0-9]{1,16}$' then
    raise exception using errcode='22023',message='LEAVE_BALANCE_VERSION_REQUIRED';end if;
   select * into v_account from people.leave_accounts where tenant_id=p_tenant_id
    and legal_entity_id=p_legal_entity_id and employee_id=v_employee
    and policy_id=v_request.policy_id for update;
   perform core.wave3_assert_expected_version(v_account.version,
    (p_payload->>'balance_version')::bigint,jsonb_build_object('account_version',v_account.version));
   perform people.revoke_work_claim(p_tenant_id,p_legal_entity_id,v_employee,v_request.active_claim_id);
   insert into people.leave_effects(tenant_id,legal_entity_id,employee_id,policy_id,
    grant_id,request_id,effective_date,seconds,reversal_of,recorded_by)
   select x.tenant_id,x.legal_entity_id,x.employee_id,x.policy_id,x.grant_id,x.request_id,
    v_today,-x.seconds,x.id,v_actor from people.leave_effects x
    where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id
     and x.employee_id=v_employee and x.request_id=v_id and x.seconds<0;
   update people.leave_accounts set version=version+1 where tenant_id=p_tenant_id
    and legal_entity_id=p_legal_entity_id and employee_id=v_employee
    and policy_id=v_request.policy_id;
   update people.leave_requests set version=version+1,status='cancelled',decided_by=v_actor,
    active_claim_id=null where id=v_id;
  end if;
 end if;
 v_after:=people.leave_request_summary(v_id);
 insert into people.leave_events(tenant_id,legal_entity_id,branch_id,employee_id,
  request_id,action,before_status,after_status,reason,actor_id,command_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_id,v_action,
  v_before->>'status',v_after->>'status',v_reason,v_actor,p_command_id);
 return core.wave3_finish_command(p_tenant_id,'people.leave.request.'||v_action,p_command_id,
  'people.leave.request',v_id,p_idempotency_key,v_hash,v_before,v_after,
  p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object(
   'employee_id',v_employee,'action',v_action),p_request_id=>v_request_id);
end $$;

create function api.people_workforce_authorize(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_employee_id uuid,p_capability text) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if p_capability is null or p_capability not in (
  'people.attendance.view','people.attendance.manage','people.attendance.import',
  'people.attendance.approve','people.work_claims.view','people.leave.view',
  'people.leave.manage','people.leave.approve','people.leave.policy.manage','people.leave.adjust') then
  raise exception using errcode='22023',message='WORKFORCE_CAPABILITY_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability);
 if p_employee_id is null and p_capability not in ('people.leave.view','people.leave.policy.manage')
  or p_employee_id is not null and not exists(select 1 from people.employment_assignments
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='WORKFORCE_SCOPE_DENIED';end if;
 return jsonb_build_object('authorized',true,'actor_id',auth.uid(),
  'employee_id',p_employee_id,'capability',p_capability);
end $$;

-- An expired encrypted draft keeps only its command identity locally. This
-- actor-scoped lookup permits reconciliation without retaining private reasons.
create function api.people_leave_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_receipt core.command_receipts%rowtype;v_action text;v_employee uuid;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 if p_command_id is null then raise exception using errcode='22023',message='LEAVE_COMMAND_REQUIRED';end if;
 select * into v_receipt from core.command_receipts where actor_id=auth.uid()
  and command_id=p_command_id and tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and command_name like 'people.leave.request.%';
 if not found then return null;end if;
 v_action:=substr(v_receipt.command_name,length('people.leave.request.')+1);
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when v_action in ('approve','reject','cancel') then 'people.leave.approve'
   else 'people.leave.manage' end);
 v_employee:=(v_receipt.response->'entity'->>'employee_id')::uuid;
 if v_employee is null or not exists(select 1 from people.employment_assignments
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and employee_id=v_employee) then
  raise exception using errcode='42501',message='LEAVE_SCOPE_DENIED';end if;
 return v_receipt.response;
end $$;

revoke all on function people.leave_history_guard(),people.leave_effect_insert_guard(),
 people.leave_slot_charge(uuid,uuid,uuid,uuid,uuid,uuid,timestamp,timestamp,timestamptz,timestamptz),
 people.leave_available(uuid,uuid,uuid,uuid,date,timestamptz),
 people.allocate_leave(uuid,uuid,uuid,uuid,uuid,uuid,date,date,bigint,uuid,boolean),
 people.leave_policy_payload(uuid),
 people.leave_request_summary(uuid),people.leave_request_private(uuid),
 api.people_leave_policies(uuid,uuid,uuid,uuid),
 api.people_leave_policy_versions(uuid,uuid,uuid,uuid,uuid),
 api.people_leave_policy_for_version(uuid,uuid,uuid,uuid),
 api.people_leave_balance(uuid,uuid,uuid,uuid,uuid,date,timestamptz,uuid),
 api.people_leave_grant_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_leave_requests(uuid,uuid,uuid,uuid,uuid),
 api.people_leave_detail(uuid,uuid,uuid,uuid,uuid),
 api.people_leave_request_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_leave_own_receipt(uuid,uuid,uuid,uuid),
 api.people_workforce_authorize(uuid,uuid,uuid,uuid,text),
 api.people_leave_policy_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated;
grant execute on function api.people_leave_policies(uuid,uuid,uuid,uuid),
 api.people_leave_policy_versions(uuid,uuid,uuid,uuid,uuid),
 api.people_leave_policy_for_version(uuid,uuid,uuid,uuid),
 api.people_leave_balance(uuid,uuid,uuid,uuid,uuid,date,timestamptz,uuid),
 api.people_leave_grant_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_leave_requests(uuid,uuid,uuid,uuid,uuid),
 api.people_leave_detail(uuid,uuid,uuid,uuid,uuid),
 api.people_leave_request_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_leave_own_receipt(uuid,uuid,uuid,uuid),
 api.people_workforce_authorize(uuid,uuid,uuid,uuid,text),
 api.people_leave_policy_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 to authenticated;
notify pgrst,'reload schema';

-- W4-04. Unapplied synthetic development candidate, isolated private payroll.
-- Dependencies: installed employee/calendar/private-HR; candidate resolver,
-- organization, attendance and leave. No plan or role grants.
create schema people_payroll;
revoke all on schema people_payroll from public,anon,authenticated;
insert into core.permissions(code,module,description,privileged) values
 ('people.payroll.view','people','Read scoped synthetic payroll configuration/runs',false),
 ('people.payroll.configure','people','Publish synthetic payroll configuration with MFA',true),
 ('people.payroll.prepare','people','Prepare synthetic frozen payroll with MFA',true),
 ('people.payroll.approve','people','Independently approve exact payroll revision with MFA',true),
 ('people.payroll.post','people','Post synthetic payroll obligations/journal with MFA',true),
 ('people.payroll.reverse','people','Reverse original synthetic payroll effects with MFA',true),
 ('people.payroll.payslip.view','people','Read private scoped synthetic payslips',true),
 ('people.payroll.payslip.self','people','Read own synthetic payslips through an accepted employee link',true),
 ('people.payroll.export','people','Export exact private synthetic payslip revision',true),
 ('people.payroll.settle','people','Record synthetic payroll settlement evidence with MFA',true)
on conflict(code) do nothing;

create table people_payroll.components(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 code text not null check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'),
 name text not null check(length(btrim(name)) between 1 and 160),
 classification text not null check(classification in('earning','deduction','employer_cost')),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,code),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create table people_payroll.rule_versions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,component_id uuid not null,
 version bigint not null check(version between 1 and 9007199254740991),
 start_date date not null,end_date_exclusive date not null,
 currency_code text not null references core.currencies(code),
 basis text not null check(basis in('fixed','hourly','earnings_ratio')),
 proration text not null check(proration in('none','eligible_days','paid_seconds')),
 rounding text not null check(rounding in('half_away','half_even','truncate','floor')),
 precision integer not null check(precision between 0 and 6),
 amount numeric(20,6) not null check(amount>=0),
 ratio_numerator bigint not null check(ratio_numerator between 0 and 9007199254740991),
 ratio_denominator bigint not null check(ratio_denominator between 1 and 9007199254740991),
 cap numeric(20,6) check(cap>=0),expense_account_id uuid,liability_account_id uuid,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 published_by uuid not null references auth.users(id),published_at timestamptz not null default clock_timestamp(),
 check(start_date>='0001-01-01'::date and end_date_exclusive<='9999-12-31'::date
  and end_date_exclusive>start_date and end_date_exclusive-start_date<=1830),
 check((basis='fixed' or proration='none') and
  ((basis='earnings_ratio' and amount=0) or (basis<>'earnings_ratio' and ratio_numerator=1 and ratio_denominator=1))),
 check(cap is null or cap=round(cap,precision)),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,component_id,id),
 unique(tenant_id,legal_entity_id,component_id,version),
 foreign key(tenant_id,legal_entity_id,component_id) references people_payroll.components(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,expense_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,liability_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 exclude using gist(component_id extensions.gist_uuid_ops with =,daterange(start_date,end_date_exclusive,'[)') with &&)
);
create index payroll_rules_scope_idx on people_payroll.rule_versions(tenant_id,legal_entity_id,component_id,id);
create index payroll_rules_expense_idx on people_payroll.rule_versions(tenant_id,legal_entity_id,expense_account_id);
create index payroll_rules_liability_idx on people_payroll.rule_versions(tenant_id,legal_entity_id,liability_account_id);
create index payroll_rules_actor_idx on people_payroll.rule_versions(published_by);
create table people_payroll.component_assignments(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,component_id uuid not null,start_date date not null,end_date_exclusive date not null,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 check(end_date_exclusive>start_date and end_date_exclusive-start_date<=1830),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,component_id) references people_payroll.components(tenant_id,legal_entity_id,id),
 exclude using gist(employee_id extensions.gist_uuid_ops with =,component_id extensions.gist_uuid_ops with =,
  daterange(start_date,end_date_exclusive,'[)') with &&)
);
create index payroll_assignments_scope_idx on people_payroll.component_assignments(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index payroll_assignments_component_idx on people_payroll.component_assignments(tenant_id,legal_entity_id,component_id);
create index payroll_assignments_actor_idx on people_payroll.component_assignments(recorded_by);
create table people_payroll.settings_versions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 version bigint not null check(version between 1 and 9007199254740991),
 net_account_id uuid not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 published_by uuid not null references auth.users(id),published_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,version),
 foreign key(tenant_id,legal_entity_id,net_account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
create index payroll_settings_account_idx on people_payroll.settings_versions(tenant_id,legal_entity_id,net_account_id);
create index payroll_settings_actor_idx on people_payroll.settings_versions(published_by);
create table people_payroll.runs(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 name text not null check(length(btrim(name)) between 1 and 160),
 start_date date not null,end_date_exclusive date not null,posting_date date not null,
 currency_code text not null references core.currencies(code),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 status text not null default 'draft' check(status in('draft','prepared','submitted','approved','posted','cancelled','reversed')),
 current_revision_id uuid,approved_revision_id uuid,approved_digest text check(approved_digest ~ '^[a-f0-9]{64}$'),
 prepared_by uuid references auth.users(id),submitted_by uuid references auth.users(id),approved_by uuid references auth.users(id),
 posted_journal_id uuid,reversal_journal_id uuid,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 check(start_date>='0001-01-01'::date and end_date_exclusive<='9999-12-31'::date
  and end_date_exclusive>start_date and end_date_exclusive-start_date<=366),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,posted_journal_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,reversal_journal_id) references finance.journal_entries(tenant_id,id)
);
create index payroll_runs_scope_idx on people_payroll.runs(tenant_id,legal_entity_id,branch_id,id);
create index payroll_runs_creator_idx on people_payroll.runs(created_by);
create index payroll_runs_preparer_idx on people_payroll.runs(prepared_by);
create index payroll_runs_submitter_idx on people_payroll.runs(submitted_by);
create index payroll_runs_approver_idx on people_payroll.runs(approved_by);
create index payroll_runs_journal_idx on people_payroll.runs(tenant_id,posted_journal_id);
create index payroll_runs_reverse_idx on people_payroll.runs(tenant_id,reversal_journal_id);
create table people_payroll.run_employees(
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,run_id uuid not null,employee_id uuid not null,
 primary key(tenant_id,legal_entity_id,run_id,employee_id),
 foreign key(tenant_id,legal_entity_id,branch_id,run_id) references people_payroll.runs(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create index payroll_run_employee_idx on people_payroll.run_employees(tenant_id,legal_entity_id,employee_id);
create table people_payroll.run_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,run_id uuid not null,
 version bigint not null,settings_version_id uuid not null,digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 employee_count integer not null check(employee_count between 1 and 200),
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,run_id,id),
 foreign key(tenant_id,legal_entity_id,run_id) references people_payroll.runs(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,settings_version_id) references people_payroll.settings_versions(tenant_id,legal_entity_id,id)
);
create index payroll_revision_run_idx on people_payroll.run_revisions(tenant_id,legal_entity_id,run_id,id);
create index payroll_revision_settings_idx on people_payroll.run_revisions(tenant_id,legal_entity_id,settings_version_id);
create index payroll_revision_actor_idx on people_payroll.run_revisions(prepared_by);
alter table people_payroll.runs add foreign key(tenant_id,legal_entity_id,id,current_revision_id)
 references people_payroll.run_revisions(tenant_id,legal_entity_id,run_id,id);
alter table people_payroll.runs add foreign key(tenant_id,legal_entity_id,id,approved_revision_id)
 references people_payroll.run_revisions(tenant_id,legal_entity_id,run_id,id);
create index payroll_runs_current_idx on people_payroll.runs(tenant_id,legal_entity_id,id,current_revision_id);
create index payroll_runs_approved_idx on people_payroll.runs(tenant_id,legal_entity_id,id,approved_revision_id);
create table people_payroll.employee_calculations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,run_id uuid not null,revision_id uuid not null,
 employee_id uuid not null,inputs jsonb not null check(jsonb_typeof(inputs)='object'),
 input_digest text not null check(input_digest ~ '^[a-f0-9]{64}$'),
 calculation jsonb not null check(jsonb_typeof(calculation)='object'),
 gross numeric(20,6) not null check(gross>=0),deductions numeric(20,6) not null check(deductions>=0 and deductions<=gross),
 employer_cost numeric(20,6) not null check(employer_cost>=0),net numeric(20,6) not null check(net=gross-deductions),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,revision_id,employee_id),
 unique(tenant_id,legal_entity_id,run_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,run_id,revision_id) references people_payroll.run_revisions(tenant_id,legal_entity_id,run_id,id) deferrable initially deferred,
 foreign key(tenant_id,legal_entity_id,run_id,employee_id) references people_payroll.run_employees(tenant_id,legal_entity_id,run_id,employee_id)
);
create index payroll_calculation_employee_idx on people_payroll.employee_calculations(tenant_id,legal_entity_id,employee_id);
create index payroll_calculation_run_idx on people_payroll.employee_calculations(tenant_id,legal_entity_id,run_id,revision_id,id);
create table people_payroll.payslips(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 run_id uuid not null,employee_id uuid not null,calculation_id uuid not null,
 revision_digest text not null check(revision_digest ~ '^[a-f0-9]{64}$'),
 issued_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,run_id,employee_id),
 foreign key(tenant_id,legal_entity_id,run_id,employee_id,calculation_id) references people_payroll.employee_calculations(tenant_id,legal_entity_id,run_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,run_id) references people_payroll.runs(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create index payroll_payslip_calculation_idx on people_payroll.payslips(tenant_id,legal_entity_id,calculation_id);
create index payroll_payslip_source_idx on people_payroll.payslips(tenant_id,legal_entity_id,run_id,employee_id,calculation_id);
create index payroll_payslip_employee_idx on people_payroll.payslips(tenant_id,legal_entity_id,branch_id,employee_id,id);
create table people_payroll.obligations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 run_id uuid not null,employee_id uuid not null,calculation_id uuid not null,rule_version_id uuid,
 kind text not null check(kind in('net','deduction','employer_cost')),account_id uuid not null,
 currency_code text not null references core.currencies(code),amount numeric(20,6) not null check(amount>0),
 created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,run_id,employee_id,calculation_id) references people_payroll.employee_calculations(tenant_id,legal_entity_id,run_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,run_id) references people_payroll.runs(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,rule_version_id) references people_payroll.rule_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 check((kind='net')=(rule_version_id is null))
);
create index payroll_obligations_run_idx on people_payroll.obligations(tenant_id,legal_entity_id,branch_id,run_id,id);
create index payroll_obligations_calculation_idx on people_payroll.obligations(tenant_id,legal_entity_id,calculation_id);
create index payroll_obligations_source_idx on people_payroll.obligations(tenant_id,legal_entity_id,run_id,employee_id,calculation_id);
create index payroll_obligations_rule_idx on people_payroll.obligations(tenant_id,legal_entity_id,rule_version_id);
create index payroll_obligations_employee_idx on people_payroll.obligations(tenant_id,legal_entity_id,employee_id);
create index payroll_obligations_account_idx on people_payroll.obligations(tenant_id,legal_entity_id,account_id);
create table people_payroll.obligation_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 obligation_id uuid not null,kind text not null check(kind in('issue','settle','settlement_reverse','run_reverse')),
 amount numeric(20,6) not null check(amount<>0),source_id uuid not null,reversal_of uuid unique,
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,obligation_id,kind,source_id),
 foreign key(tenant_id,legal_entity_id,obligation_id) references people_payroll.obligations(tenant_id,legal_entity_id,id),
 foreign key(reversal_of) references people_payroll.obligation_effects(id),
 check((kind in('settlement_reverse','run_reverse'))=(reversal_of is not null))
);
create index payroll_effects_scope_idx on people_payroll.obligation_effects(tenant_id,legal_entity_id,obligation_id,id);
create index payroll_effects_actor_idx on people_payroll.obligation_effects(recorded_by);
create table people_payroll.run_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,run_id uuid not null,revision_id uuid,action text not null,
 version bigint not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 actor_id uuid not null references auth.users(id),command_id uuid not null,recorded_at timestamptz not null default clock_timestamp(),
 foreign key(tenant_id,legal_entity_id,branch_id,run_id) references people_payroll.runs(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,run_id,revision_id) references people_payroll.run_revisions(tenant_id,legal_entity_id,run_id,id)
);
create index payroll_events_scope_idx on people_payroll.run_events(tenant_id,legal_entity_id,branch_id,run_id,id);
create index payroll_events_revision_idx on people_payroll.run_events(tenant_id,legal_entity_id,run_id,revision_id);
create index payroll_events_actor_idx on people_payroll.run_events(actor_id);

create function people_payroll.immutable() returns trigger language plpgsql set search_path='' as $$
begin raise exception using errcode='55000',message='PAYROLL_HISTORY_IMMUTABLE';end $$;
do $$declare v_table text;begin
 foreach v_table in array array['components','rule_versions','component_assignments','settings_versions','runs',
  'run_employees','run_revisions','employee_calculations','payslips','obligations','obligation_effects','run_events'] loop
  execute format('alter table people_payroll.%I enable row level security',v_table);
  execute format('alter table people_payroll.%I force row level security',v_table);
  execute format('revoke all on people_payroll.%I from public,anon,authenticated',v_table);
  if v_table not in('components','runs') then
   execute format('create trigger immutable before update or delete on people_payroll.%I for each row execute function people_payroll.immutable()',v_table);
  end if;
 end loop;
end $$;

create function people_payroll.digest(p jsonb) returns text language sql immutable set search_path='' as $$
 select encode(extensions.digest(p::text,'sha256'),'hex')
$$;
create function people_payroll.amount(p jsonb) returns numeric language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(p)<>'string' or coalesce(p#>>'{}','') !~ '^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' then
  raise exception using errcode='22023',message='PAYROLL_AMOUNT_INVALID';end if;
 return (p#>>'{}')::numeric;
end $$;
create function people_payroll.round_ratio(n numeric,d numeric,p_precision integer,mode text)
returns numeric language plpgsql immutable set search_path='' as $$
declare quantum numeric;divisor numeric;q numeric;remainder numeric;begin
 if n is null or d is null or n<>trunc(n) or d<>trunc(d) or d<=0 or p_precision is null
  or p_precision not between 0 and 6 or mode is null or mode not in('half_away','half_even','truncate','floor') then
  raise exception using errcode='22023',message='PAYROLL_ROUNDING_INVALID';end if;
 quantum:=power(10::numeric,6-p_precision);divisor:=d*quantum;
 q:=div(n,divisor);remainder:=abs(mod(n,divisor));
 if remainder<>0 and ((mode='half_away' and remainder*2>=divisor)
  or (mode='half_even' and (remainder*2>divisor or (remainder*2=divisor and mod(abs(q),2)=1)))) then
  q:=q+sign(n);
 elsif remainder<>0 and mode='floor' and n<0 then q:=q-1;end if;
 return q*quantum;
end $$;
-- Exact SQL oracle shared by preparation and correction. Inputs are server projections.
create function people_payroll.calculate(p_input jsonb,p_rules jsonb,p_currency text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare r jsonb;lines jsonb:='[]';n numeric;d numeric;units numeric;rounded numeric;cap numeric;
 amount numeric;gross numeric:=0;deductions numeric:=0;cost numeric:=0;paid bigint;planned bigint;
 eligible integer;period integer;basis text;proration text;class text;capped boolean;v_precision integer;begin
 if coalesce(jsonb_typeof(p_input),'null')<>'object' or coalesce(jsonb_typeof(p_rules),'null')<>'array'
  or jsonb_array_length(p_rules) not between 1 and 100 or p_currency is null or p_currency !~ '^[A-Z]{3}$'
  or coalesce(p_input->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or coalesce(p_input->>'end_date_exclusive','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or (select count(distinct x->>'id') from jsonb_array_elements(p_rules) x)<>jsonb_array_length(p_rules)
  or (select count(distinct x->>'code') from jsonb_array_elements(p_rules) x)<>jsonb_array_length(p_rules)
  or coalesce(p_input->>'paid_seconds','') !~ '^[0-9]{1,16}$'
  or coalesce(p_input->>'planned_seconds','') !~ '^[0-9]{1,16}$' then
  raise exception using errcode='22023',message='PAYROLL_CALCULATION_INVALID';end if;
 paid:=(p_input->>'paid_seconds')::bigint;planned:=(p_input->>'planned_seconds')::bigint;
 eligible:=(p_input->>'eligible_days')::integer;period:=(p_input->>'period_days')::integer;
 if paid>9007199254740991 or planned>9007199254740991 or eligible is null or period is null
  or period not between 1 and 366 or eligible not between 1 and period
  or (p_input->>'end_date_exclusive')::date-(p_input->>'start_date')::date<>period then
  raise exception using errcode='22023',message='PAYROLL_CALCULATION_INVALID';end if;
 for r in select value from jsonb_array_elements(p_rules)
  order by case when value->>'classification'='earning' then 0 else 1 end,value->>'code' loop
  basis:=r->>'basis';proration:=r->>'proration';class:=r->>'classification';v_precision:=(r->>'precision')::integer;
  if class is null or class not in('earning','deduction','employer_cost') or basis is null
   or basis not in('fixed','hourly','earnings_ratio') or proration is null
   or proration not in('none','eligible_days','paid_seconds') or v_precision is null or v_precision not between 0 and 6
   or coalesce(r->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(r->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'
   or coalesce(r->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(r->>'end_date_exclusive','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or r->>'currency_code' is distinct from p_currency or (r->>'start_date')::date>(p_input->>'start_date')::date
   or (r->>'end_date_exclusive')::date<(p_input->>'end_date_exclusive')::date
   or basis<>'fixed' and proration<>'none' or basis='earnings_ratio' and class='earning'
   or coalesce(r->>'ratio_numerator','') !~ '^[0-9]{1,16}$'
   or coalesce(r->>'ratio_denominator','') !~ '^[0-9]{1,16}$'
   or (r->>'ratio_numerator')::numeric>9007199254740991
   or (r->>'ratio_denominator')::numeric not between 1 and 9007199254740991 then
   raise exception using errcode='22023',message='PAYROLL_RULE_INVALID';end if;
  n:=people_payroll.amount(r->'amount')*1000000;d:=1;
  if basis='fixed' then
   if proration='eligible_days' then n:=n*eligible;d:=period;
   elsif proration='paid_seconds' then
    if planned=0 then raise exception using errcode='55000',message='PAYROLL_PLANNED_SECONDS_REQUIRED';end if;
    n:=n*least(paid,planned);d:=planned;end if;
  elsif basis='hourly' then n:=n*paid;d:=3600;
  else
   if n<>0 then raise exception using errcode='22023',message='PAYROLL_RULE_INVALID';end if;
   n:=gross*1000000*(r->>'ratio_numerator')::numeric;d:=(r->>'ratio_denominator')::numeric;
  end if;
  if basis<>'earnings_ratio' and ((r->>'ratio_numerator')::numeric<>1 or (r->>'ratio_denominator')::numeric<>1) then
   raise exception using errcode='22023',message='PAYROLL_RULE_INVALID';end if;
  units:=people_payroll.round_ratio(n,d,v_precision,r->>'rounding');rounded:=units/1000000;
  cap:=null;
  if r->'cap' is not null and r->'cap'<>'null'::jsonb then
   cap:=people_payroll.amount(r->'cap');
   if cap<>round(cap,v_precision) then raise exception using errcode='22023',message='PAYROLL_CAP_INVALID';end if;
  end if;
  capped:=cap is not null and rounded>cap;amount:=case when capped then cap else rounded end;
  if amount>99999999999999.999999 then raise exception using errcode='22023',message='PAYROLL_AMOUNT_OVERFLOW';end if;
  if class='earning' then gross:=gross+amount;
  elsif class='deduction' then deductions:=deductions+amount;else cost:=cost+amount;end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('rule_version_id',r->>'id','code',r->>'code',
   'classification',class,'basis',basis,'proration',proration,'raw_numerator_units',trunc(n)::text,
   'raw_denominator',trunc(d)::text,'rounding',r->>'rounding','precision',v_precision,
   'rounded_amount',round(rounded,6)::text,'cap',case when cap is not null then round(cap,6)::text end,
   'capped',capped,'amount',round(amount,6)::text));
 end loop;
 if deductions>gross then raise exception using errcode='55000',message='PAYROLL_NEGATIVE_NET';end if;
 if greatest(gross,deductions,cost)>99999999999999.999999 then
  raise exception using errcode='22023',message='PAYROLL_AMOUNT_OVERFLOW';end if;
 return jsonb_build_object('lines',lines,'gross',round(gross,6)::text,'deductions',round(deductions,6)::text,
  'employer_cost',round(cost,6)::text,'net',round(gross-deductions,6)::text);
end $$;

create function people_payroll.require_access(t uuid,e uuid,b uuid,cap text,p_write boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 if cap is null or cap not in('people.payroll.view','people.payroll.configure','people.payroll.prepare',
  'people.payroll.approve','people.payroll.post','people.payroll.reverse','people.payroll.payslip.view',
  'people.payroll.export','people.payroll.settle','people.payroll.payslip.self') then
  raise exception using errcode='42501',message='PAYROLL_SCOPE_DENIED';end if;
 perform people.require_access(t,e,b,cap);
 if p_write and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='PAYROLL_MFA_REQUIRED';end if;
end $$;
create function people_payroll.account(t uuid,e uuid,a uuid,kind text,currency text)
returns void language plpgsql security definer set search_path='' as $$
declare ap_used boolean:=false;begin
 perform id from finance.accounts where tenant_id=t and legal_entity_id=e and id=a for share;
 perform finance.flow_account(t,e,a,kind,currency);
 if kind='liability' then
  if to_regclass('procurement.supplier_bill_controls') is not null then
   execute 'select exists(select 1 from procurement.supplier_bill_controls where tenant_id=$1 and legal_entity_id=$2 and payable_account_id=$3)'
    into ap_used using t,e,a;
  end if;
  if ap_used or exists(select 1 from finance.posting_mappings where tenant_id=t and legal_entity_id=e
   and account_id=a and purpose in('receivable_control','payable_control')) then
   raise exception using errcode='55000',message='PAYROLL_SEPARATE_CONTROL_REQUIRED';end if;
 end if;
end $$;

create function people_payroll.rule_payload(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',r.id,'component_id',r.component_id,'code',c.code,'name',c.name,
  'classification',c.classification,'version',r.version,'start_date',r.start_date,
  'end_date_exclusive',r.end_date_exclusive,'currency_code',r.currency_code,'basis',r.basis,
  'proration',r.proration,'rounding',r.rounding,'precision',r.precision,'amount',r.amount::text,
  'ratio_numerator',r.ratio_numerator,'ratio_denominator',r.ratio_denominator,'cap',r.cap::text,
  'expense_account_id',r.expense_account_id,'liability_account_id',r.liability_account_id,
  'reason',r.reason,'published_by',r.published_by,'published_at',r.published_at)
 from people_payroll.rule_versions r join people_payroll.components c on c.id=r.component_id where r.id=p_id
$$;
create function people_payroll.run_summary(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',r.id,'tenant_id',r.tenant_id,'legal_entity_id',r.legal_entity_id,
  'branch_id',r.branch_id,'name',r.name,'start_date',r.start_date,'end_date_exclusive',r.end_date_exclusive,
  'posting_date',r.posting_date,'currency_code',r.currency_code,'version',r.version,'status',r.status,
  'current_revision_id',r.current_revision_id,'digest',v.digest,'employee_count',v.employee_count,
  'prepared_by',r.prepared_by,'submitted_by',r.submitted_by,'approved_by',r.approved_by,
  'posted_journal_id',r.posted_journal_id,'reversal_journal_id',r.reversal_journal_id,'created_by',r.created_by)
 from people_payroll.runs r left join people_payroll.run_revisions v on v.id=r.current_revision_id where r.id=p_id
$$;
create function api.people_payroll_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability,p_capability<>'people.payroll.view');
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'actor_id',auth.uid(),'capability',p_capability,'authorized',true);
end $$;
create function api.people_payroll_rules(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 select coalesce(jsonb_agg(people_payroll.rule_payload(q.id) order by q.id),'[]'::jsonb) into items
 from(select id from people_payroll.rule_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end,
  'settings',(select jsonb_build_object('id',id,'version',version,'net_account_id',net_account_id)
   from people_payroll.settings_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id order by version desc limit 1));
end $$;
create function api.people_payroll_configure(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare action text:=p_payload->>'action';id uuid;component uuid;employee uuid;currency text;reason text;
 version bigint;hash text;replay jsonb;after_context jsonb;r jsonb;class text;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.configure',true);
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or coalesce(jsonb_typeof(p_payload),'null')<>'object' or p_expected_version is null
  or p_expected_version not between 0 and 9007199254740991 or action is null or action not in('publish','assign','settings')
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='PAYROLL_CONFIG_INVALID';end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(case action
  when 'settings' then array['action','id','net_account_id','reason']
  when 'assign' then array['action','id','employee_id','component_id','start_date','end_date_exclusive','reason']
  else array['action','id','component_id','code','name','classification','start_date','end_date_exclusive',
   'basis','proration','rounding','precision','amount','ratio_numerator','ratio_denominator','cap',
   'expense_account_id','liability_account_id','reason'] end)) then
  raise exception using errcode='22023',message='PAYROLL_CONFIG_FIELDS_INVALID';end if;
 id:=(p_payload->>'id')::uuid;reason:=btrim(p_payload->>'reason');
 if action='assign' then
  employee:=(p_payload->>'employee_id')::uuid;
  if not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and employee_id=employee) then raise exception using errcode='42501',message='PAYROLL_SCOPE_DENIED';end if;
 else
  perform core.require_permission(p_tenant_id,'people.payroll.configure',p_legal_entity_id,null);
 end if;
 hash:=core.wave3_request_hash('people.payroll.config.'||action,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'people.payroll.config.'||action,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 select le.currency_code into currency from core.legal_entities le where le.tenant_id=p_tenant_id and le.id=p_legal_entity_id;
 if action='settings' then
  select coalesce(max(s.version),0) into version from people_payroll.settings_versions s
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id;
  if version<>p_expected_version then raise exception using errcode='40001',message='PAYROLL_VERSION_CONFLICT';end if;
  perform people_payroll.account(p_tenant_id,p_legal_entity_id,(p_payload->>'net_account_id')::uuid,'liability',currency);
  insert into people_payroll.settings_versions(id,tenant_id,legal_entity_id,version,net_account_id,reason,published_by)
   values(id,p_tenant_id,p_legal_entity_id,version+1,(p_payload->>'net_account_id')::uuid,reason,auth.uid());
  after_context:=jsonb_build_object('id',id,'version',version+1,'kind','settings');
 elsif action='assign' then
  perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and people.employees.id=employee for update;
  if p_expected_version<>0 or not exists(select 1 from people.employment_assignments a
   where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=employee
    and daterange(a.start_date,a.end_date_exclusive,'[)') @> daterange((p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,'[)')) then
   raise exception using errcode='55000',message='PAYROLL_ASSIGNMENT_COVERAGE_REQUIRED';end if;
  insert into people_payroll.component_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,component_id,
   start_date,end_date_exclusive,reason,recorded_by) values(id,p_tenant_id,p_legal_entity_id,p_branch_id,employee,
   (p_payload->>'component_id')::uuid,(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,reason,auth.uid());
  after_context:=jsonb_build_object('id',id,'version',1,'kind','assignment');
 else
  component:=(p_payload->>'component_id')::uuid;class:=p_payload->>'classification';
  if component is null or class is null or class not in('earning','deduction','employer_cost')
   or coalesce(p_payload->>'code','') !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'
   or length(btrim(coalesce(p_payload->>'name',''))) not between 1 and 160
   or (class='earning' and (p_payload->>'basis'='earnings_ratio' or p_payload->>'liability_account_id' is not null))
   or (class='deduction' and p_payload->>'expense_account_id' is not null) then
   raise exception using errcode='22023',message='PAYROLL_RULE_INVALID';end if;
  select c.version into version from people_payroll.components c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.id=component for update;
  if version is null then
   if p_expected_version<>0 then raise exception using errcode='40001',message='PAYROLL_VERSION_CONFLICT';end if;
   version:=1;
   insert into people_payroll.components(id,tenant_id,legal_entity_id,code,name,classification)
    values(component,p_tenant_id,p_legal_entity_id,p_payload->>'code',btrim(p_payload->>'name'),class);
  else
   if version<>p_expected_version then raise exception using errcode='40001',message='PAYROLL_VERSION_CONFLICT';end if;
   if not exists(select 1 from people_payroll.components c where c.id=component and c.code=p_payload->>'code'
    and c.name=btrim(p_payload->>'name') and c.classification=class) then
    raise exception using errcode='55000',message='PAYROLL_COMPONENT_IDENTITY_IMMUTABLE';end if;
   version:=version+1;update people_payroll.components c set version=p_expected_version+1 where c.id=component;
  end if;
  if class in('earning','employer_cost') then
   perform people_payroll.account(p_tenant_id,p_legal_entity_id,(p_payload->>'expense_account_id')::uuid,'expense',currency);end if;
  if class in('deduction','employer_cost') then
   perform people_payroll.account(p_tenant_id,p_legal_entity_id,(p_payload->>'liability_account_id')::uuid,'liability',currency);end if;
  insert into people_payroll.rule_versions(id,tenant_id,legal_entity_id,component_id,version,start_date,end_date_exclusive,
   currency_code,basis,proration,rounding,precision,amount,ratio_numerator,ratio_denominator,cap,
   expense_account_id,liability_account_id,reason,published_by)
  values(id,p_tenant_id,p_legal_entity_id,component,version,(p_payload->>'start_date')::date,(p_payload->>'end_date_exclusive')::date,
   currency,p_payload->>'basis',p_payload->>'proration',p_payload->>'rounding',(p_payload->>'precision')::integer,
   people_payroll.amount(p_payload->'amount'),(p_payload->>'ratio_numerator')::bigint,(p_payload->>'ratio_denominator')::bigint,
   case when p_payload->'cap' is not null and p_payload->'cap'<>'null'::jsonb then people_payroll.amount(p_payload->'cap') end,
   (p_payload->>'expense_account_id')::uuid,(p_payload->>'liability_account_id')::uuid,reason,auth.uid());
  after_context:=jsonb_build_object('id',id,'component_id',component,'version',version,'kind','rule');
 end if;
 after_context:=after_context||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
 return core.wave3_finish_command(p_tenant_id,'people.payroll.config.'||action,p_command_id,'people.payroll.config',id,
  p_idempotency_key,hash,'{}',after_context,p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object('action',action));
end $$;

-- Projection is bounded and retains complete dated and source evidence. No client totals.
create function people_payroll.freeze(t uuid,e uuid,b uuid,employee uuid,period_start date,period_end date,currency text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare assignment people.employment_assignments%rowtype;org people.organization_assignments%rowtype;
 calendar people.work_calendar_versions%rowtype;employee_row people.employees%rowtype;
 eligible_start date;eligible_end date;rules jsonb;facts jsonb;days jsonb:='[]';slot jsonb;day date;
 local_start timestamp;local_end timestamp;utc_start timestamptz;utc_end timestamptz;
 planned bigint:=0;paid bigint:=0;cnt integer;begin
 select * into employee_row from people.employees where tenant_id=t and legal_entity_id=e and id=employee;
 select count(*) into cnt from people.employment_assignments a where tenant_id=t and legal_entity_id=e
  and branch_id=b and employee_id=employee and daterange(a.start_date,a.end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 if cnt<>1 then raise exception using errcode='55000',message='PAYROLL_SINGLE_EMPLOYMENT_SLICE_REQUIRED';end if;
 select * into assignment from people.employment_assignments a where tenant_id=t and legal_entity_id=e
  and branch_id=b and employee_id=employee and daterange(a.start_date,a.end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 eligible_start:=greatest(period_start,assignment.start_date);eligible_end:=least(period_end,assignment.end_date_exclusive);
 select * into org from people.organization_assignments o where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and superseded_at is null and daterange(o.start_date,o.end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)');
 if org.id is null then raise exception using errcode='55000',message='PAYROLL_ORGANIZATION_COVERAGE_REQUIRED';end if;
 select * into calendar from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=org.calendar_version_id
  and daterange(start_date,end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)');
 if calendar.id is null then raise exception using errcode='55000',message='PAYROLL_CALENDAR_COVERAGE_REQUIRED';end if;
 select count(*) into cnt from people_payroll.component_assignments a where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and daterange(start_date,end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 if cnt not between 1 and 100 then raise exception using errcode='55000',message='PAYROLL_COMPONENT_BOUND_REQUIRED';end if;
 select coalesce(jsonb_agg(people_payroll.rule_payload(r.id)||jsonb_build_object('assignment_id',a.id) order by c.code),'[]'::jsonb) into rules
 from people_payroll.component_assignments a join people_payroll.components c on c.id=a.component_id
 join people_payroll.rule_versions r on r.component_id=a.component_id
 where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and a.employee_id=employee
  and daterange(a.start_date,a.end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)')
  and daterange(r.start_date,r.end_date_exclusive,'[)') @> daterange(period_start,period_end,'[)');
 if jsonb_array_length(rules)<>cnt then raise exception using errcode='55000',message='PAYROLL_RULE_COVERAGE_REQUIRED';end if;
 for day in select generate_series(eligible_start::timestamp,(eligible_end-1)::timestamp,interval '1 day')::date loop
  if exists(select 1 from jsonb_array_elements(calendar.date_overrides) x where x->>'date'=day::text and not(x->>'is_working_day')::boolean) then continue;end if;
  for slot in select value from jsonb_array_elements(calendar.weekly_intervals) where (value->>'day_of_week')::integer=extract(isodow from day)::integer loop
   local_start:=day::timestamp+(slot->>'start_minute')::integer*interval '1 minute';
   local_end:=day::timestamp+(slot->>'end_day_offset')::integer*interval '1 day'+(slot->>'end_minute')::integer*interval '1 minute';
   utc_start:=people.resolve_local_instant(calendar.timezone,local_start);
   utc_end:=people.resolve_local_instant(calendar.timezone,local_end);
   if local_end>eligible_end::timestamp then raise exception using errcode='55000',message='PAYROLL_OVERNIGHT_SLICE_REQUIRED';end if;
   planned:=planned+extract(epoch from utc_end-utc_start)::bigint;
   days:=days||jsonb_build_array(jsonb_build_object('date',day,'start_local',local_start,'end_local',local_end,
    'start_utc',utc_start,'end_utc',utc_end,'seconds',extract(epoch from utc_end-utc_start)::bigint));
   if jsonb_array_length(days)>2000 then raise exception using errcode='55000',message='PAYROLL_PLANNED_SLOT_BOUND_REQUIRED';end if;
  end loop;
 end loop;
 -- Any unresolved or boundary-straddling claim is explicit; never silently truncate.
 utc_start:=people.resolve_local_instant(calendar.timezone,eligible_start::timestamp);
 utc_end:=people.resolve_local_instant(calendar.timezone,eligible_end::timestamp);
 if exists(select 1 from people.work_claims w where w.tenant_id=t and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee
  and w.active and tstzrange(w.start_utc,w.end_utc,'[)') && tstzrange(utc_start,utc_end,'[)')
  and (w.start_utc<utc_start or w.end_utc>utc_end)) then
  raise exception using errcode='55000',message='PAYROLL_WORK_BOUNDARY_SLICE_REQUIRED';end if;
 select count(*) into cnt from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and active and start_utc>=utc_start and end_utc<=utc_end;
 if cnt>2000 then raise exception using errcode='55000',message='PAYROLL_SOURCE_BOUND_REQUIRED';end if;
 if exists(select 1 from people.work_claims w left join people.attendance_revisions ar on ar.id=w.source_id
  left join people.attendance_entries ae on ae.current_revision_id=ar.id and ae.status='approved' and ae.active_claim_id=w.id
  left join people.leave_requests lr on lr.id=w.source_id and lr.status='approved' and lr.active_claim_id=w.id
  where w.tenant_id=t and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee and w.active and w.start_utc>=utc_start and w.end_utc<=utc_end
   and ((w.source_kind='attendance' and ae.id is null) or (w.source_kind='leave' and lr.id is null) or w.source_kind not in('attendance','leave'))) then
  raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('claim_id',w.id,'source_kind',w.source_kind,'source_id',w.source_id,
  'source_version',case when w.source_kind='attendance' then ae.version else lr.version end,
  'calendar_version_id',w.calendar_version_id,'start_utc',w.start_utc,'end_utc',w.end_utc,
  'gross_seconds',w.gross_seconds,'break_seconds',w.break_seconds,
  'paid_seconds',case when w.source_kind='leave' then lr.charge_seconds-lr.unpaid_seconds else w.payable_seconds end,
  'leave_policy_version_id',lr.policy_version_id,'leave_charge_seconds',lr.charge_seconds,'unpaid_seconds',lr.unpaid_seconds,
  'leave_effects',case when w.source_kind='leave' then (select coalesce(jsonb_agg(jsonb_build_object('id',le.id,'grant_id',le.grant_id,'seconds',le.seconds,'reversal_of',le.reversal_of) order by le.id),'[]'::jsonb)
   from people.leave_effects le where le.request_id=lr.id) end) order by w.id),'[]'::jsonb) into facts
 from people.work_claims w left join people.attendance_revisions ar on ar.id=w.source_id and w.source_kind='attendance'
 left join people.attendance_entries ae on ae.current_revision_id=ar.id and ae.active_claim_id=w.id
 left join people.leave_requests lr on lr.id=w.source_id and w.source_kind='leave'
 where w.tenant_id=t and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee and w.active
  and w.start_utc>=utc_start and w.end_utc<=utc_end;
 select coalesce(sum((x->>'paid_seconds')::bigint),0) into paid from jsonb_array_elements(facts) x;
 return jsonb_build_object('employee_id',employee,'employee_version',employee_row.version,'employee_code',employee_row.code,
  'employee_name',employee_row.display_name,'employment_assignment',jsonb_build_object('id',assignment.id,'spell_id',assignment.spell_id,
   'start_date',assignment.start_date,'end_date_exclusive',assignment.end_date_exclusive,'type',assignment.employment_type,'job_title',assignment.job_title),
  'organization_assignment_id',org.id,'calendar_version_id',calendar.id,'timezone',calendar.timezone,
  'start_date',period_start,'end_date_exclusive',period_end,'eligible_start',eligible_start,'eligible_end_exclusive',eligible_end,
  'period_days',period_end-period_start,'eligible_days',eligible_end-eligible_start,
  'paid_seconds',paid,'planned_seconds',planned,'planned_slots',days,'sources',facts,'rules',rules);
end $$;

create table people_payroll.settlements(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,run_id uuid not null,
 posting_date date not null,bank_id uuid not null,bank_account_id uuid not null,currency_code text not null references core.currencies(code),
 bank_version bigint not null,evidence_reference text not null check(length(btrim(evidence_reference)) between 1 and 160),
 reason text not null check(length(btrim(reason)) between 1 and 1000),version bigint not null default 1,
 status text not null default 'recorded' check(status in('recorded','reversed')),journal_id uuid not null,reversal_journal_id uuid,
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,evidence_reference),
 foreign key(tenant_id,legal_entity_id,branch_id,run_id) references people_payroll.runs(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,bank_id) references finance.cash_bank_accounts(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,bank_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,journal_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,reversal_journal_id) references finance.journal_entries(tenant_id,id)
);
create index payroll_settlement_run_idx on people_payroll.settlements(tenant_id,legal_entity_id,branch_id,run_id,id);
create index payroll_settlement_bank_idx on people_payroll.settlements(tenant_id,bank_id);
create index payroll_settlement_account_idx on people_payroll.settlements(tenant_id,legal_entity_id,bank_account_id);
create index payroll_settlement_journal_idx on people_payroll.settlements(tenant_id,journal_id);
create index payroll_settlement_reversal_idx on people_payroll.settlements(tenant_id,reversal_journal_id);
create index payroll_settlement_actor_idx on people_payroll.settlements(recorded_by);
create table people_payroll.settlement_allocations(
 tenant_id uuid not null,legal_entity_id uuid not null,settlement_id uuid not null,obligation_id uuid not null,
 amount numeric(20,6) not null check(amount>0),primary key(tenant_id,legal_entity_id,settlement_id,obligation_id),
 foreign key(tenant_id,legal_entity_id,settlement_id) references people_payroll.settlements(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,obligation_id) references people_payroll.obligations(tenant_id,legal_entity_id,id)
);
create index payroll_allocations_obligation_idx on people_payroll.settlement_allocations(tenant_id,legal_entity_id,obligation_id);
create table people_payroll.exports(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,payslip_id uuid not null,
 content_digest text not null check(content_digest ~ '^[a-f0-9]{64}$'),
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,payslip_id) references people_payroll.payslips(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index payroll_exports_payslip_idx on people_payroll.exports(tenant_id,legal_entity_id,payslip_id);
create index payroll_exports_scope_idx on people_payroll.exports(tenant_id,legal_entity_id,branch_id,id);
create index payroll_exports_actor_idx on people_payroll.exports(prepared_by);
do $$declare name text;begin
 foreach name in array array['settlements','settlement_allocations','exports'] loop
  execute format('alter table people_payroll.%I enable row level security',name);
  execute format('alter table people_payroll.%I force row level security',name);
  execute format('revoke all on people_payroll.%I from public,anon,authenticated',name);
  if name<>'settlements' then execute format('create trigger immutable before update or delete on people_payroll.%I for each row execute function people_payroll.immutable()',name);end if;
 end loop;
end $$;

create function people_payroll.effect_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare original people_payroll.obligation_effects%rowtype;obligation people_payroll.obligations%rowtype;begin
 select * into obligation from people_payroll.obligations where tenant_id=new.tenant_id and legal_entity_id=new.legal_entity_id and id=new.obligation_id;
 if new.kind='issue' and new.amount<>obligation.amount or new.kind='settle' and new.amount>=0 then
  raise exception using errcode='23514',message='PAYROLL_EFFECT_INVALID';end if;
 if new.reversal_of is not null then
  select * into original from people_payroll.obligation_effects where id=new.reversal_of;
  if original.id is null or original.tenant_id<>new.tenant_id or original.legal_entity_id<>new.legal_entity_id
   or original.obligation_id<>new.obligation_id or original.reversal_of is not null
   or new.amount<>-original.amount
   or new.kind='run_reverse' and original.kind<>'issue'
   or new.kind='settlement_reverse' and original.kind<>'settle' then
   raise exception using errcode='23514',message='PAYROLL_REVERSAL_MISMATCH';end if;
 end if;return new;
end $$;
create trigger payroll_effect_guard before insert on people_payroll.obligation_effects for each row execute function people_payroll.effect_guard();
create function api.people_payroll_runs(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 select coalesce(jsonb_agg(people_payroll.run_summary(q.id) order by q.id),'[]'::jsonb) into items
 from(select id from people_payroll.runs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_run_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_run_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;summary jsonb;employees jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 select people_payroll.run_summary(id) into summary from people_payroll.runs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_run_id;
 if summary is null then raise exception using errcode='P0002',message='PAYROLL_RUN_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'employee_id',q.employee_id,
  'employee_name',q.inputs->>'employee_name','input_digest',q.input_digest,'gross',q.gross::text,
  'deductions',q.deductions::text,'employer_cost',q.employer_cost::text,'net',q.net::text) order by q.id),'[]'::jsonb) into items
 from(select * from people_payroll.employee_calculations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and run_id=p_run_id and revision_id=(summary->>'current_revision_id')::uuid
  and (p_after is null or id>p_after) order by id limit 51) q;
 select coalesce(jsonb_agg(employee_id order by employee_id),'[]'::jsonb) into employees from people_payroll.run_employees
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and run_id=p_run_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'run',summary,'employee_ids',employees,'calculations',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_calculation(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_calculation_id uuid,
 p_after_code text default null,p_source_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c people_payroll.employee_calculations%rowtype;lines jsonb;sources jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 select x.* into c from people_payroll.employee_calculations x join people_payroll.runs r on r.id=x.run_id
  where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and x.id=p_calculation_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_CALCULATION_NOT_FOUND';end if;
 select coalesce(jsonb_agg(value order by value->>'code'),'[]'::jsonb) into lines
  from(select value from jsonb_array_elements(c.calculation->'lines') where p_after_code is null or value->>'code'>p_after_code order by value->>'code' limit 51) q;
 select coalesce(jsonb_agg(value order by value->>'claim_id'),'[]'::jsonb) into sources
  from(select value from jsonb_array_elements(c.inputs->'sources') where p_source_after is null or (value->>'claim_id')::uuid>p_source_after order by (value->>'claim_id')::uuid limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'id',c.id,'run_id',c.run_id,'revision_id',c.revision_id,'employee_id',c.employee_id,'input_digest',c.input_digest,
  'input',c.inputs-array['sources','rules','planned_slots'],'gross',c.gross::text,'deductions',c.deductions::text,
  'employer_cost',c.employer_cost::text,'net',c.net::text,'lines',lines-50,'sources',sources-50,
  'next_code',case when jsonb_array_length(lines)>50 then lines->49->>'code' end,
  'next_source',case when jsonb_array_length(sources)>50 then sources->49->>'claim_id' end);
end $$;
create function api.people_payroll_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_id uuid;v_run people_payroll.runs%rowtype;
 v_settings people_payroll.settings_versions%rowtype;v_revision uuid;v_employee uuid;v_calculation uuid;v_digest text;
 v_inputs jsonb;v_calc jsonb;v_hash text;v_replay jsonb;v_before jsonb:='{}';v_after jsonb;v_reason text;
 v_currency text;v_sources jsonb;v_line jsonb;v_lines jsonb:='[]';v_obligation uuid;v_amount numeric;
 v_source jsonb;v_c people_payroll.employee_calculations%rowtype;v_rule people_payroll.rule_versions%rowtype;
 v_journal uuid;v_request uuid:=gen_random_uuid();v_count integer;v_original people_payroll.obligation_effects%rowtype;begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or coalesce(jsonb_typeof(p_payload),'null')<>'object' or p_expected_version is null
  or p_expected_version not between 0 and 9007199254740991 or v_action is null
  or v_action not in('create','prepare','submit','approve','cancel','post','reverse')
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='PAYROLL_COMMAND_INVALID';end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(case when v_action='create' then
  array['action','id','name','start_date','end_date_exclusive','posting_date','employee_ids','reason']
  when v_action in('submit','approve','post','reverse') then array['action','id','revision_id','digest','reason']
  else array['action','id','reason'] end)) then raise exception using errcode='22023',message='PAYROLL_COMMAND_FIELDS_INVALID';end if;
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,case v_action
  when 'approve' then 'people.payroll.approve' when 'post' then 'people.payroll.post'
  when 'reverse' then 'people.payroll.reverse' else 'people.payroll.prepare' end,true);
 v_id:=(p_payload->>'id')::uuid;v_reason:=btrim(p_payload->>'reason');
 if v_action<>'create' and not exists(select 1 from people_payroll.runs where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=v_id) then
  raise exception using errcode='P0002',message='PAYROLL_RUN_NOT_FOUND';end if;
 v_hash:=core.wave3_request_hash('people.payroll.run.'||v_action,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.payroll.run.'||v_action,p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 if v_action='create' then
  if p_expected_version<>0 or length(btrim(coalesce(p_payload->>'name',''))) not between 1 and 160
   or coalesce(jsonb_typeof(p_payload->'employee_ids'),'null')<>'array'
   or jsonb_array_length(p_payload->'employee_ids') not between 1 and 200
   or exists(select 1 from jsonb_array_elements(p_payload->'employee_ids') x where jsonb_typeof(x)<>'string' or x#>>'{}' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
   or (select count(distinct (x#>>'{}')::uuid) from jsonb_array_elements(p_payload->'employee_ids') x)<>jsonb_array_length(p_payload->'employee_ids') then
   raise exception using errcode='22023',message='PAYROLL_RUN_INVALID';end if;
  select currency_code into v_currency from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
  for v_employee in select (x#>>'{}')::uuid from jsonb_array_elements(p_payload->'employee_ids') x order by (x#>>'{}')::uuid loop
   perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=v_employee for update;
   if not found or not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and employee_id=v_employee) then raise exception using errcode='42501',message='PAYROLL_SCOPE_DENIED';end if;
  end loop;
  insert into people_payroll.runs(id,tenant_id,legal_entity_id,branch_id,name,start_date,end_date_exclusive,posting_date,currency_code,created_by)
   values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,btrim(p_payload->>'name'),(p_payload->>'start_date')::date,
    (p_payload->>'end_date_exclusive')::date,(p_payload->>'posting_date')::date,v_currency,auth.uid());
  insert into people_payroll.run_employees(tenant_id,legal_entity_id,branch_id,run_id,employee_id)
   select p_tenant_id,p_legal_entity_id,p_branch_id,v_id,(x#>>'{}')::uuid from jsonb_array_elements(p_payload->'employee_ids') x;
 else
  -- All source owners take employee locks; a current freeze cannot race correction.
  perform e.id from people.employees e join people_payroll.run_employees re on re.employee_id=e.id
   where re.tenant_id=p_tenant_id and re.legal_entity_id=p_legal_entity_id and re.run_id=v_id order by e.id for update of e;
  select * into v_run from people_payroll.runs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=v_id for update;
  if v_run.version<>p_expected_version then raise exception using errcode='40001',message='PAYROLL_VERSION_CONFLICT';end if;
  v_before:=people_payroll.run_summary(v_id);
  if v_action='prepare' then
   if v_run.status not in('draft','prepared','submitted','approved') then raise exception using errcode='55000',message='PAYROLL_RUN_STATE_INVALID';end if;
   select * into v_settings from people_payroll.settings_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id order by version desc limit 1;
   if v_settings.id is null then raise exception using errcode='55000',message='PAYROLL_SETTINGS_REQUIRED';end if;
   v_revision:=gen_random_uuid();
   for v_employee in select employee_id from people_payroll.run_employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and run_id=v_id order by employee_id loop
    v_inputs:=people_payroll.freeze(p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_run.start_date,v_run.end_date_exclusive,v_run.currency_code);
    v_calc:=people_payroll.calculate(v_inputs,v_inputs->'rules',v_run.currency_code);
    insert into people_payroll.employee_calculations(id,tenant_id,legal_entity_id,run_id,revision_id,employee_id,inputs,input_digest,calculation,gross,deductions,employer_cost,net)
     values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,v_id,v_revision,v_employee,v_inputs,people_payroll.digest(v_inputs),v_calc,
      (v_calc->>'gross')::numeric,(v_calc->>'deductions')::numeric,(v_calc->>'employer_cost')::numeric,(v_calc->>'net')::numeric);
   end loop;
   select count(*),people_payroll.digest(jsonb_build_object('settings_version_id',v_settings.id,
    'employee_digests',jsonb_agg(jsonb_build_object('employee_id',employee_id,'input_digest',input_digest,'calculation',calculation) order by employee_id)))
    into v_count,v_digest from people_payroll.employee_calculations where revision_id=v_revision;
   insert into people_payroll.run_revisions(id,tenant_id,legal_entity_id,run_id,version,settings_version_id,digest,employee_count,prepared_by)
    values(v_revision,p_tenant_id,p_legal_entity_id,v_id,v_run.version+1,v_settings.id,v_digest,v_count,auth.uid());
   update people_payroll.runs set status='prepared',version=version+1,current_revision_id=v_revision,prepared_by=auth.uid(),
    submitted_by=null,approved_by=null,approved_revision_id=null,approved_digest=null where id=v_id;
  elsif v_action='cancel' then
   if v_run.status not in('draft','prepared','submitted','approved') then raise exception using errcode='55000',message='PAYROLL_RUN_STATE_INVALID';end if;
   update people_payroll.runs set status='cancelled',version=version+1,approved_by=null,approved_revision_id=null,approved_digest=null where id=v_id;
  else
   v_revision:=(p_payload->>'revision_id')::uuid;v_digest:=p_payload->>'digest';
   if v_revision is null or v_digest is null or v_revision is distinct from v_run.current_revision_id
    or not exists(select 1 from people_payroll.run_revisions where id=v_revision and digest=v_digest) then
    raise exception using errcode='40001',message='PAYROLL_REVISION_CONFLICT';end if;
   if v_action='submit' then
    if v_run.status<>'prepared' then raise exception using errcode='55000',message='PAYROLL_RUN_STATE_INVALID';end if;
    update people_payroll.runs set status='submitted',submitted_by=auth.uid(),version=version+1 where id=v_id;
   elsif v_action='approve' then
    if v_run.status<>'submitted' then raise exception using errcode='55000',message='PAYROLL_RUN_STATE_INVALID';end if;
    if auth.uid()=v_run.prepared_by or auth.uid()=v_run.submitted_by then raise exception using errcode='42501',message='PAYROLL_INDEPENDENT_APPROVAL_REQUIRED';end if;
    update people_payroll.runs set status='approved',version=version+1,approved_by=auth.uid(),approved_revision_id=v_revision,approved_digest=v_digest where id=v_id;
   elsif v_action='post' then
    if v_run.status<>'approved' or v_run.approved_revision_id is distinct from v_revision or v_run.approved_digest is distinct from v_digest then
     raise exception using errcode='55000',message='PAYROLL_APPROVAL_REQUIRED';end if;
    if not exists(select 1 from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id and currency_code=v_run.currency_code) then
     raise exception using errcode='55000',message='PAYROLL_BASE_CURRENCY_PROVIDER_REQUIRED';end if;
    select * into v_settings from people_payroll.settings_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id order by version desc limit 1;
    if not exists(select 1 from people_payroll.run_revisions where id=v_revision and settings_version_id=v_settings.id) then
     raise exception using errcode='40001',message='PAYROLL_INPUTS_CHANGED';end if;
    perform people_payroll.account(p_tenant_id,p_legal_entity_id,v_settings.net_account_id,'liability',v_run.currency_code);
    for v_c in select * from people_payroll.employee_calculations where revision_id=v_revision order by employee_id loop
     v_inputs:=people_payroll.freeze(p_tenant_id,p_legal_entity_id,p_branch_id,v_c.employee_id,v_run.start_date,v_run.end_date_exclusive,v_run.currency_code);
     if people_payroll.digest(v_inputs)<>v_c.input_digest then raise exception using errcode='40001',message='PAYROLL_INPUTS_CHANGED';end if;
     if exists(select 1 from people.work_input_seals s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id
      and s.employee_id=v_c.employee_id and s.claim_id in(select (x->>'claim_id')::uuid from jsonb_array_elements(v_inputs->'sources') x)) then
      raise exception using errcode='55000',message='PAYROLL_SOURCE_ALREADY_CONSUMED';end if;
     -- Regular payable periods cannot pay the same employee twice even without work sources.
     if exists(select 1 from people_payroll.runs old join people_payroll.payslips ps on ps.run_id=old.id
      where old.tenant_id=p_tenant_id and old.legal_entity_id=p_legal_entity_id and ps.employee_id=v_c.employee_id
       and old.status in('posted','reversed') and daterange(old.start_date,old.end_date_exclusive,'[)') && daterange(v_run.start_date,v_run.end_date_exclusive,'[)')) then
      raise exception using errcode='55000',message='PAYROLL_PERIOD_ALREADY_CONSUMED';end if;
     for v_source in select value from jsonb_array_elements(v_inputs->'sources') loop
      insert into people.work_input_seals(id,tenant_id,legal_entity_id,employee_id,run_id,claim_id,source_version,seconds,digest)
       values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,v_c.employee_id,v_id,(v_source->>'claim_id')::uuid,
        (v_source->>'source_version')::bigint,(v_source->>'paid_seconds')::bigint,people_payroll.digest(v_source));
     end loop;
     perform people.consume_organization(p_tenant_id,p_legal_entity_id,p_branch_id,v_c.employee_id,'payroll',v_c.id,
      (v_inputs->>'eligible_start')::date,(v_inputs->>'eligible_end_exclusive')::date);
     insert into people_payroll.payslips(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,revision_digest)
      values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_c.employee_id,v_c.id,v_digest);
     if v_c.net>0 then
      v_obligation:=gen_random_uuid();
      insert into people_payroll.obligations(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,kind,account_id,currency_code,amount)
       values(v_obligation,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_c.employee_id,v_c.id,'net',v_settings.net_account_id,v_run.currency_code,v_c.net);
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_settings.net_account_id,'amount',(-v_c.net)::text,'base_amount',(-v_c.net)::text,'source_line_id',v_obligation));
     end if;
     for v_line in select value from jsonb_array_elements(v_c.calculation->'lines') loop
      v_amount:=(v_line->>'amount')::numeric;
      select * into v_rule from people_payroll.rule_versions where id=(v_line->>'rule_version_id')::uuid;
      if v_line->>'classification' in('earning','employer_cost') then
       perform people_payroll.account(p_tenant_id,p_legal_entity_id,v_rule.expense_account_id,'expense',v_run.currency_code);
       if v_amount>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_rule.expense_account_id,
        'amount',v_amount::text,'base_amount',v_amount::text,'source_line_id',v_c.id));end if;
      end if;
      if v_line->>'classification' in('deduction','employer_cost') then
       perform people_payroll.account(p_tenant_id,p_legal_entity_id,v_rule.liability_account_id,'liability',v_run.currency_code);
       if v_amount>0 then
        v_obligation:=gen_random_uuid();
        insert into people_payroll.obligations(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,rule_version_id,kind,account_id,currency_code,amount)
         values(v_obligation,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_c.employee_id,v_c.id,v_rule.id,v_line->>'classification',v_rule.liability_account_id,v_run.currency_code,v_amount);
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_rule.liability_account_id,'amount',(-v_amount)::text,'base_amount',(-v_amount)::text,'source_line_id',v_obligation));
       end if;
      end if;
     end loop;
    end loop;
    if jsonb_array_length(v_lines)=0 then raise exception using errcode='55000',message='PAYROLL_ZERO_RUN_UNPOSTABLE';end if;
    v_journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',v_run.posting_date,'currency_code',v_run.currency_code,'base_currency_code',v_run.currency_code,'exchange_rate','1.000000'),
     v_lines,'payroll',v_id,v_request,p_command_id);
    insert into people_payroll.obligation_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,recorded_by)
     select tenant_id,legal_entity_id,id,'issue',amount,v_id,auth.uid() from people_payroll.obligations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and run_id=v_id;
    update people_payroll.runs set status='posted',posted_journal_id=v_journal,version=version+1 where id=v_id;
   else
    if v_run.status<>'posted' then raise exception using errcode='55000',message='PAYROLL_RUN_STATE_INVALID';end if;
    if exists(select 1 from people_payroll.obligations o where o.run_id=v_id and
     (select sum(amount) from people_payroll.obligation_effects where obligation_id=o.id)<>o.amount) then
     raise exception using errcode='55000',message='PAYROLL_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL';end if;
    select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,
     'amount',(transaction_credit-transaction_debit)::text,'base_amount',(base_credit-base_debit)::text) order by line_number) into v_lines
     from finance.journal_lines where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=v_run.posted_journal_id;
    v_journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',v_run.posting_date,'currency_code',v_run.currency_code,'base_currency_code',v_run.currency_code,'exchange_rate','1.000000'),
     v_lines,'payroll_reverse',v_id,v_request,p_command_id);
    insert into people_payroll.obligation_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,reversal_of,recorded_by)
     select tenant_id,legal_entity_id,obligation_id,'run_reverse',-amount,v_id,id,auth.uid()
     from people_payroll.obligation_effects where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and kind='issue' and source_id=v_id;
    update people_payroll.runs set status='reversed',reversal_journal_id=v_journal,version=version+1 where id=v_id;
   end if;
  end if;
 end if;
 v_after:=people_payroll.run_summary(v_id);
 insert into people_payroll.run_events(tenant_id,legal_entity_id,branch_id,run_id,revision_id,action,version,reason,actor_id,command_id)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,v_id,(v_after->>'current_revision_id')::uuid,v_action,(v_after->>'version')::bigint,v_reason,auth.uid(),p_command_id);
 -- Only operational IDs/state enter generic audit/outbox/receipts; never amounts or private source bodies.
 return core.wave3_finish_command(p_tenant_id,'people.payroll.run.'||v_action,p_command_id,'people.payroll.run',v_id,
  p_idempotency_key,v_hash,v_before-array['name'],v_after-array['name'],p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('action',v_action),p_request_id=>v_request);
end $$;

create function api.people_payroll_obligations(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_run_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.settle');
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'run_id',q.run_id,'employee_id',q.employee_id,
  'kind',q.kind,'currency_code',q.currency_code,'amount',q.amount::text,'account_id',q.account_id,
  'outstanding',round((select coalesce(sum(amount),0) from people_payroll.obligation_effects where obligation_id=q.id),6)::text) order by q.id),'[]'::jsonb) into items
 from(select * from people_payroll.obligations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and run_id=p_run_id and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'run_id',p_run_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_accounts(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 if p_kind='bank' then
  perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.settle');
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.name,'account_id',q.account_id,'currency_code',q.currency_code,'version',q.version) order by q.id),'[]'::jsonb) into items
   from(select * from finance.cash_bank_accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and status='active' and (p_after is null or id>p_after) order by id limit 51) q;
 elsif p_kind in('expense','liability') then
  perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.configure');
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'code',q.code,'name',q.name,'currency_code',q.currency_code,'version',q.version) order by q.id),'[]'::jsonb) into items
   from(select * from finance.accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and account_type=p_kind and is_posting and status='active' and (p_after is null or id>p_after) order by id limit 51) q;
 else raise exception using errcode='22023',message='PAYROLL_ACCOUNT_KIND_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'kind',p_kind,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_settlement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_id uuid;v_run_id uuid;v_date date;v_run people_payroll.runs%rowtype;
 v_bank finance.cash_bank_accounts%rowtype;v_s people_payroll.settlements%rowtype;v_o people_payroll.obligations%rowtype;
 v_journal uuid;v_lines jsonb:='[]';v_line jsonb;v_amount numeric;v_total numeric:=0;v_outstanding numeric;
 v_hash text;v_replay jsonb;v_request uuid:=gen_random_uuid();v_after jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.settle',true);
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or coalesce(jsonb_typeof(p_payload),'null')<>'object' or v_action is null or v_action not in('record','reverse')
  or p_expected_version is null or p_expected_version not between 0 and 9007199254740991
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'run_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000
  or coalesce(p_payload->>'posting_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(case when v_action='record' then
   array['action','id','run_id','posting_date','bank_id','bank_version','evidence_reference','allocations','reason']
   else array['action','id','run_id','posting_date','reason'] end)) then
  raise exception using errcode='22023',message='PAYROLL_SETTLEMENT_INVALID';end if;
 v_id:=(p_payload->>'id')::uuid;v_run_id:=(p_payload->>'run_id')::uuid;v_date:=(p_payload->>'posting_date')::date;
 if not exists(select 1 from people_payroll.runs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=v_run_id) then
  raise exception using errcode='P0002',message='PAYROLL_RUN_NOT_FOUND';end if;
 v_hash:=core.wave3_request_hash('people.payroll.settlement.'||v_action,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.payroll.settlement.'||v_action,p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 select * into v_run from people_payroll.runs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=v_run_id for update;
 if v_run.status<>'posted' then raise exception using errcode='55000',message='PAYROLL_POSTED_OBLIGATION_REQUIRED';end if;
 if v_action='record' then
  if p_expected_version<>0 or length(btrim(coalesce(p_payload->>'evidence_reference',''))) not between 1 and 160
   or coalesce(jsonb_typeof(p_payload->'allocations'),'null')<>'array' or jsonb_array_length(p_payload->'allocations') not between 1 and 200
   or (select count(distinct x->>'obligation_id') from jsonb_array_elements(p_payload->'allocations') x)<>jsonb_array_length(p_payload->'allocations') then
   raise exception using errcode='22023',message='PAYROLL_SETTLEMENT_INVALID';end if;
  select * into v_bank from finance.cash_bank_accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and id=(p_payload->>'bank_id')::uuid and status='active' and currency_code=v_run.currency_code for share;
  if v_bank.id is null then raise exception using errcode='55000',message='PAYROLL_BANK_PROVIDER_REQUIRED';end if;
  if v_bank.version is distinct from (p_payload->>'bank_version')::bigint then raise exception using errcode='40001',message='PAYROLL_BANK_VERSION_CONFLICT';end if;
  perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_bank.account_id,'asset',v_run.currency_code);
  for v_line in select value from jsonb_array_elements(p_payload->'allocations') order by value->>'obligation_id' loop
   if jsonb_typeof(v_line)<>'object' or (select count(*) from jsonb_object_keys(v_line))<>2
    or not(v_line ? 'obligation_id' and v_line ? 'amount') then raise exception using errcode='22023',message='PAYROLL_SETTLEMENT_INVALID';end if;
   select * into v_o from people_payroll.obligations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and run_id=v_run_id and id=(v_line->>'obligation_id')::uuid for update;
   if v_o.id is null then raise exception using errcode='P0002',message='PAYROLL_OBLIGATION_NOT_FOUND';end if;
   v_amount:=people_payroll.amount(v_line->'amount');
   select coalesce(sum(amount),0) into v_outstanding from people_payroll.obligation_effects where obligation_id=v_o.id;
   if v_amount<=0 or v_amount>v_outstanding then raise exception using errcode='55000',message='PAYROLL_SETTLEMENT_EXCEEDS_DUE';end if;
   perform people_payroll.account(p_tenant_id,p_legal_entity_id,v_o.account_id,'liability',v_run.currency_code);
   v_total:=v_total+v_amount;
   v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_o.account_id,'amount',v_amount::text,'base_amount',v_amount::text,'source_line_id',v_o.id));
  end loop;
  if v_total>99999999999999.999999 then raise exception using errcode='22023',message='PAYROLL_AMOUNT_OVERFLOW';end if;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_id',v_bank.account_id,'amount',(-v_total)::text,'base_amount',(-v_total)::text,'source_line_id',v_id));
  v_journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
   'document_date',v_date,'currency_code',v_run.currency_code,'base_currency_code',v_run.currency_code,'exchange_rate','1.000000'),v_lines,'payroll_settlement',v_id,v_request,p_command_id);
  insert into people_payroll.settlements(id,tenant_id,legal_entity_id,branch_id,run_id,posting_date,bank_id,bank_account_id,currency_code,bank_version,evidence_reference,reason,journal_id,recorded_by)
   values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_run_id,v_date,v_bank.id,v_bank.account_id,v_run.currency_code,v_bank.version,btrim(p_payload->>'evidence_reference'),btrim(p_payload->>'reason'),v_journal,auth.uid());
  insert into people_payroll.settlement_allocations(tenant_id,legal_entity_id,settlement_id,obligation_id,amount)
   select p_tenant_id,p_legal_entity_id,v_id,(x->>'obligation_id')::uuid,people_payroll.amount(x->'amount') from jsonb_array_elements(p_payload->'allocations') x;
  insert into people_payroll.obligation_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,recorded_by)
   select p_tenant_id,p_legal_entity_id,obligation_id,'settle',-amount,v_id,auth.uid() from people_payroll.settlement_allocations where settlement_id=v_id;
  v_after:=jsonb_build_object('id',v_id,'run_id',v_run_id,'version',1,'status','recorded','journal_id',v_journal);
 else
  select * into v_s from people_payroll.settlements where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and run_id=v_run_id and id=v_id for update;
  if v_s.id is null then raise exception using errcode='P0002',message='PAYROLL_SETTLEMENT_NOT_FOUND';end if;
  if v_s.version<>p_expected_version then raise exception using errcode='40001',message='PAYROLL_VERSION_CONFLICT';end if;
  if v_s.status<>'recorded' then raise exception using errcode='55000',message='PAYROLL_SETTLEMENT_ALREADY_REVERSED';end if;
  select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,
   'amount',(transaction_credit-transaction_debit)::text,'base_amount',(base_credit-base_debit)::text) order by line_number) into v_lines
   from finance.journal_lines where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=v_s.journal_id;
  v_journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
   'document_date',v_date,'currency_code',v_run.currency_code,'base_currency_code',v_run.currency_code,'exchange_rate','1.000000'),v_lines,'payroll_settlement_reverse',v_id,v_request,p_command_id);
  insert into people_payroll.obligation_effects(tenant_id,legal_entity_id,obligation_id,kind,amount,source_id,reversal_of,recorded_by)
   select p_tenant_id,p_legal_entity_id,obligation_id,'settlement_reverse',-amount,v_id,id,auth.uid()
   from people_payroll.obligation_effects where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and kind='settle' and source_id=v_id;
  update people_payroll.settlements set status='reversed',version=version+1,reversal_journal_id=v_journal where id=v_id;
  v_after:=jsonb_build_object('id',v_id,'run_id',v_run_id,'version',v_s.version+1,'status','reversed','reversal_journal_id',v_journal);
 end if;
 v_after:=v_after||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id);
 return core.wave3_finish_command(p_tenant_id,'people.payroll.settlement.'||v_action,p_command_id,'people.payroll.settlement',v_id,
  p_idempotency_key,v_hash,'{}',v_after,p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object('action',v_action),p_request_id=>v_request);
end $$;

create function people_payroll.payslip_payload(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'run_id',p.run_id,'employee_id',p.employee_id,'revision_digest',p.revision_digest,
  'issued_at',p.issued_at,'currency_code',r.currency_code,'start_date',r.start_date,'end_date_exclusive',r.end_date_exclusive,
  'employee_code',c.inputs->>'employee_code','employee_name',c.inputs->>'employee_name','input_digest',c.input_digest,
  'calculation_id',c.id,'gross',c.gross::text,'deductions',c.deductions::text,'employer_cost',c.employer_cost::text,'net',c.net::text,
  'lines',c.calculation->'lines')
 from people_payroll.payslips p join people_payroll.employee_calculations c on c.id=p.calculation_id join people_payroll.runs r on r.id=p.run_id where p.id=p_id
$$;
create function api.people_payroll_payslips(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_employee_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.payslip.view',true);
 select coalesce(jsonb_agg((people_payroll.payslip_payload(q.id)-'lines') order by q.id),'[]'::jsonb) into items
 from(select id from people_payroll.payslips where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and employee_id=p_employee_id and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'employee_id',p_employee_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_payslip(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_payslip_id uuid,p_after_code text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare payload jsonb;lines jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.payslip.view',true);
 select people_payroll.payslip_payload(id) into payload from people_payroll.payslips where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_payslip_id;
 if payload is null then raise exception using errcode='P0002',message='PAYROLL_PAYSLIP_NOT_FOUND';end if;
 select coalesce(jsonb_agg(value order by value->>'code'),'[]'::jsonb) into lines from
  (select value from jsonb_array_elements(payload->'lines') where p_after_code is null or value->>'code'>p_after_code order by value->>'code' limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'payslip',payload-'lines',
  'lines',lines-50,'next_code',case when jsonb_array_length(lines)>50 then lines->49->>'code' end);
end $$;
create function api.people_payroll_export(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_payslip uuid;v_body jsonb;v_hash text;v_replay jsonb;v_digest text;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.export',true);
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null or p_expected_version is distinct from 0
  or coalesce(jsonb_typeof(p_payload),'null')<>'object' or p_payload->>'action' is distinct from 'prepare'
  or (select count(*) from jsonb_object_keys(p_payload))<>3 or not(p_payload ? 'id' and p_payload ? 'payslip_id') then
  raise exception using errcode='22023',message='PAYROLL_EXPORT_INVALID';end if;
 v_id:=(p_payload->>'id')::uuid;v_payslip:=(p_payload->>'payslip_id')::uuid;
 select people_payroll.payslip_payload(id) into v_body from people_payroll.payslips where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=v_payslip;
 if v_body is null then raise exception using errcode='P0002',message='PAYROLL_PAYSLIP_NOT_FOUND';end if;
 v_hash:=core.wave3_request_hash('people.payroll.export.prepare',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.payroll.export.prepare',p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 v_digest:=people_payroll.digest(v_body);
 insert into people_payroll.exports(id,tenant_id,legal_entity_id,branch_id,payslip_id,content_digest,prepared_by)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_payslip,v_digest,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'people.payroll.export.prepare',p_command_id,'people.payroll.export',v_id,
  p_idempotency_key,v_hash,'{}',jsonb_build_object('id',v_id,'payslip_id',v_payslip,'content_digest',v_digest,
  'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'version',1),p_legal_entity_id,p_branch_id);
end $$;
create function api.people_payroll_export_content(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_export_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_export people_payroll.exports%rowtype;v_body jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.export',true);
 select * into v_export from people_payroll.exports where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and id=p_export_id and prepared_by=auth.uid();
 if v_export.id is null then raise exception using errcode='P0002',message='PAYROLL_EXPORT_NOT_FOUND';end if;
 v_body:=people_payroll.payslip_payload(v_export.payslip_id);
 if people_payroll.digest(v_body)<>v_export.content_digest then raise exception using errcode='55000',message='PAYROLL_EXPORT_DIGEST_MISMATCH';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'id',v_export.id,
  'content_digest',v_export.content_digest,'synthetic',true,'payslip',v_body);
end $$;

create function api.people_payroll_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r core.command_receipts%rowtype;cap text;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability,true);
 select * into r from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and actor_id=auth.uid() and command_id=p_command_id and command_name like 'people.payroll.%';
 if r.command_id is null then return null;end if;
 cap:=case when r.command_name like 'people.payroll.config.%' then 'people.payroll.configure'
  when r.command_name like 'people.payroll.settlement.%' then 'people.payroll.settle'
  when r.command_name='people.payroll.export.prepare' then 'people.payroll.export'
  when r.command_name='people.payroll.run.approve' then 'people.payroll.approve'
  when r.command_name='people.payroll.run.post' then 'people.payroll.post'
  when r.command_name='people.payroll.run.reverse' then 'people.payroll.reverse'
  when r.command_name in('people.payroll.run.create','people.payroll.run.prepare','people.payroll.run.submit','people.payroll.run.cancel') then 'people.payroll.prepare' end;
 if cap is null or cap<>p_capability then raise exception using errcode='42501',message='PAYROLL_RECEIPT_SCOPE_DENIED';end if;
 return r.response;
end $$;
create function api.people_payroll_history(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_run_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 if not exists(select 1 from people_payroll.runs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_run_id) then
  raise exception using errcode='P0002',message='PAYROLL_RUN_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'revision_id',q.revision_id,'action',q.action,'version',q.version,
  'reason',q.reason,'actor_id',q.actor_id,'recorded_at',q.recorded_at) order by q.id),'[]'::jsonb) into items
 from(select * from people_payroll.run_events where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and run_id=p_run_id and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'run_id',p_run_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_settlements(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_run_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.settle');
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'run_id',q.run_id,'posting_date',q.posting_date,'bank_id',q.bank_id,
  'currency_code',q.currency_code,'evidence_reference',q.evidence_reference,'version',q.version,'status',q.status,
  'journal_id',q.journal_id,'reversal_journal_id',q.reversal_journal_id,'recorded_by',q.recorded_by,'recorded_at',q.recorded_at,
  'amount',(select round(sum(amount),6)::text from people_payroll.settlement_allocations where settlement_id=q.id)) order by q.id),'[]'::jsonb) into items
 from(select * from people_payroll.settlements where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and run_id=p_run_id and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'run_id',p_run_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_assignments(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_employee_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'employee_id',q.employee_id,'component_id',q.component_id,
  'component_code',c.code,'component_name',c.name,'start_date',q.start_date,'end_date_exclusive',q.end_date_exclusive,
  'reason',q.reason,'recorded_by',q.recorded_by,'recorded_at',q.recorded_at) order by q.id),'[]'::jsonb) into items
 from(select * from people_payroll.component_assignments where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and employee_id=p_employee_id and (p_after is null or id>p_after) order by id limit 51) q
 join people_payroll.components c on c.id=q.component_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'employee_id',p_employee_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_payroll_snapshot(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_calculation_id uuid,
 p_section text,p_after integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c people_payroll.employee_calculations%rowtype;items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 if p_section not in('rules','planned_slots') or p_section is null or p_after is null or p_after not between 0 and 2000 then
  raise exception using errcode='22023',message='PAYROLL_SNAPSHOT_CURSOR_INVALID';end if;
 select ec.* into c from people_payroll.employee_calculations ec join people_payroll.runs r on r.id=ec.run_id
  where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and ec.id=p_calculation_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_CALCULATION_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('position',position,'value',value) order by position),'[]'::jsonb) into items
  from(select value,ordinality::integer as position from jsonb_array_elements(c.inputs->p_section) with ordinality
   where ordinality>p_after order by ordinality limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'id',c.id,
  'run_id',c.run_id,'revision_id',c.revision_id,'employee_id',c.employee_id,'input_digest',c.input_digest,'section',p_section,
  'items',items-50,'next_position',case when jsonb_array_length(items)>50 then (items->49->>'position')::integer end);
end $$;
create function api.people_payroll_self_payslips(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid;items jsonb;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.payslip.self',true);
 select l.employee_id into employee from people_private.account_links l join core.memberships m
  on m.tenant_id=l.tenant_id and m.id=l.membership_id and m.user_id=l.user_id and m.status='active'
  where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.user_id=auth.uid() and l.status='accepted';
 if employee is null then raise exception using errcode='42501',message='HR_ACTIVE_LINK_REQUIRED';end if;
 select coalesce(jsonb_agg((people_payroll.payslip_payload(q.id)-'lines') order by q.id),'[]'::jsonb) into items
  from(select id from people_payroll.payslips where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and employee_id=employee and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'employee_id',employee,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

revoke all on all functions in schema people_payroll from public,anon,authenticated;
revoke all on function api.people_payroll_authorize(uuid,uuid,uuid,text),api.people_payroll_rules(uuid,uuid,uuid,uuid),
 api.people_payroll_configure(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.people_payroll_authorize(uuid,uuid,uuid,text),api.people_payroll_rules(uuid,uuid,uuid,uuid),
 api.people_payroll_configure(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
revoke all on function api.people_payroll_assignments(uuid,uuid,uuid,uuid,uuid),api.people_payroll_snapshot(uuid,uuid,uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function api.people_payroll_assignments(uuid,uuid,uuid,uuid,uuid),api.people_payroll_snapshot(uuid,uuid,uuid,uuid,text,integer) to authenticated;
revoke all on function api.people_payroll_runs(uuid,uuid,uuid,uuid),api.people_payroll_run_detail(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_calculation(uuid,uuid,uuid,uuid,text,uuid),api.people_payroll_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated;
grant execute on function api.people_payroll_runs(uuid,uuid,uuid,uuid),api.people_payroll_run_detail(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_calculation(uuid,uuid,uuid,uuid,text,uuid),api.people_payroll_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 to authenticated;
notify pgrst,'reload schema';
revoke all on function api.people_payroll_obligations(uuid,uuid,uuid,uuid,uuid),api.people_payroll_accounts(uuid,uuid,uuid,text,uuid),
 api.people_payroll_settlement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.people_payroll_payslips(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_payslip(uuid,uuid,uuid,uuid,text),api.people_payroll_export(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_export_content(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.people_payroll_obligations(uuid,uuid,uuid,uuid,uuid),api.people_payroll_accounts(uuid,uuid,uuid,text,uuid),
 api.people_payroll_settlement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.people_payroll_payslips(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_payslip(uuid,uuid,uuid,uuid,text),api.people_payroll_export(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_export_content(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function api.people_payroll_own_receipt(uuid,uuid,uuid,uuid,text),api.people_payroll_self_payslips(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.people_payroll_own_receipt(uuid,uuid,uuid,uuid,text),api.people_payroll_self_payslips(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function api.people_payroll_history(uuid,uuid,uuid,uuid,uuid),api.people_payroll_settlements(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.people_payroll_history(uuid,uuid,uuid,uuid,uuid),api.people_payroll_settlements(uuid,uuid,uuid,uuid,uuid) to authenticated;

create temporary table payroll_assertions(message text);
grant insert on payroll_assertions to authenticated,service_role;
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
insert into payroll_assertions select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='people_payroll' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity),15,
 'all payroll tables are forced RLS');
insert into payroll_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='people_payroll' and c.relkind='r' and has_table_privilege('authenticated',c.oid,'SELECT')),
 'payroll amounts cannot enter generic authenticated table reads');
insert into payroll_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='people_payroll' and has_function_privilege('authenticated',p.oid,'EXECUTE')),
 'trusted payroll helpers are denied to clients');
insert into payroll_assertions select is(people_payroll.round_ratio(125000,1,2,'half_even'),120000::numeric,'exact even tie');
insert into payroll_assertions select is(people_payroll.round_ratio(135000,1,2,'half_even'),140000::numeric,'exact odd tie');
insert into payroll_assertions select is(people_payroll.round_ratio(-125000,1,2,'half_away'),-130000::numeric,'signed away tie');
insert into payroll_assertions select is(people_payroll.round_ratio(-121000,1,2,'floor'),-130000::numeric,'signed floor');
insert into payroll_assertions select is(people_payroll.round_ratio(-129999,1,2,'truncate'),-120000::numeric,'signed truncation');
insert into payroll_assertions select is(people_payroll.round_ratio(99999999999999999999999999999999,9007199254740991,6,'half_away'),
 11102230246251567::numeric,'large exact rational quotient');
insert into payroll_assertions select throws_ok($q$select people_payroll.round_ratio(1,0,2,'half_even')$q$,'22023','PAYROLL_ROUNDING_INVALID','zero denominator rejected');
insert into payroll_assertions select throws_ok($q$select people_payroll.amount('1.1234567'::jsonb)$q$,'22023','PAYROLL_AMOUNT_INVALID','number and excess precision rejected');
insert into payroll_assertions select throws_ok($q$select people_payroll.amount('"1e3"'::jsonb)$q$,'22023','PAYROLL_AMOUNT_INVALID','exponent rejected');
create function pg_temp.pi(paid bigint default 5400,planned bigint default 28800) returns jsonb language sql as $$
 select jsonb_build_object('employee_id',pg_temp.wid('employee'),'start_date',pg_temp.wdate(),
  'end_date_exclusive',pg_temp.wdate()+1,'period_days',1,'eligible_days',1,'paid_seconds',paid,'planned_seconds',planned)
$$;
create function pg_temp.pr(code text,classification text,basis text,amount text,
 n bigint default 1,d bigint default 1,proration text default 'none',cap text default null)
returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.wid(code),'code',code,'classification',classification,
  'currency_code','LKR','start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+10,
  'basis',basis,'amount',amount,'ratio_numerator',n,'ratio_denominator',d,
  'proration',proration,'rounding','half_away','precision',2,'cap',cap)
$$;
create function pg_temp.prules() returns jsonb language sql as $$
 select jsonb_build_array(pg_temp.pr('BASE','earning','fixed','123.456789'),
  pg_temp.pr('HOURS','earning','hourly','312.750000'),
  pg_temp.pr('DEDUCT','deduction','earnings_ratio','0',1,10),
  pg_temp.pr('EMPLOYER','employer_cost','earnings_ratio','0',3,100))
$$;
insert into payroll_assertions select is(people_payroll.calculate(pg_temp.pi(),pg_temp.prules(),'LKR')->>'gross','592.590000','Dart parity exact gross');
insert into payroll_assertions select is(people_payroll.calculate(pg_temp.pi(),pg_temp.prules(),'LKR')->>'deductions','59.260000','Dart parity exact deductions');
insert into payroll_assertions select is(people_payroll.calculate(pg_temp.pi(),pg_temp.prules(),'LKR')->>'employer_cost','17.780000','Dart parity employer cost');
insert into payroll_assertions select is(people_payroll.calculate(pg_temp.pi(),pg_temp.prules(),'LKR')->>'net','533.330000','Dart parity net');
insert into payroll_assertions select is(people_payroll.calculate(pg_temp.pi(57600,28800),
 jsonb_build_array(pg_temp.pr('FIXED','earning','fixed','100',1,1,'paid_seconds')),'LKR')->>'gross',
 '100.000000','fixed paid-time basis caps at whole-period salary');
insert into payroll_assertions select is(people_payroll.calculate(pg_temp.pi(9007199254740991,1),
 jsonb_build_array(pg_temp.pr('CAP','earning','hourly','99999999999999.999999',1,1,'none','1.25')),'LKR')->>'gross',
 '1.250000','configured cap applies before journal bound');
insert into payroll_assertions select throws_ok($q$select people_payroll.calculate(pg_temp.pi(1,0),
 jsonb_build_array(pg_temp.pr('FIXED','earning','fixed','100',1,1,'paid_seconds')),'LKR')$q$,
 '55000','PAYROLL_PLANNED_SECONDS_REQUIRED','missing basis explicit');
insert into payroll_assertions select throws_ok($q$select people_payroll.calculate(pg_temp.pi(),
 jsonb_build_array(pg_temp.pr('BASE','earning','fixed','1'),pg_temp.pr('DEDUCT','deduction','fixed','2')),'LKR')$q$,
 '55000','PAYROLL_NEGATIVE_NET','negative net explicit');
insert into payroll_assertions select throws_ok($q$select people_payroll.calculate(pg_temp.pi(),pg_temp.prules()||pg_temp.prules(),'LKR')$q$,
 '22023','PAYROLL_CALCULATION_INVALID','duplicate rules rejected');
insert into payroll_assertions select throws_ok($q$select people_payroll.calculate(pg_temp.pi(),
 jsonb_build_array(pg_temp.pr('BASE','earning','fixed','1')||'{"currency_code":"USD"}'),'LKR')$q$,
 '22023','PAYROLL_RULE_INVALID','mixed currency rejected');

-- Full synthetic run against the installed journal provider, all inside rollback.
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.wid('pay.'||x),pg_temp.wid('tenant'),pg_temp.wid('entity'),upper(x),'Synthetic '||x,
 case when x in('wages','employer') then 'expense' when x='bank' then 'asset' else 'liability' end,
 case when x in('wages','employer','bank') then 'debit' else 'credit' end,pg_temp.wid('creator'),pg_temp.wid('creator')
from unnest(array['wages','employer','net','deduct','employer_control','bank']) x;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.wid('pay.period'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Synthetic payroll period',
 pg_temp.wdate()-10,pg_temp.wdate()+400,pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
values(pg_temp.wid('pay.bank.record'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'SYNTHETIC-BANK','Synthetic bank',
 'bank',pg_temp.wid('pay.bank'),'LKR',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'journal_entry','SYNTHETIC-PAY-',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into people.departments(id,tenant_id,legal_entity_id,code) values(pg_temp.wid('department'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'W4OPS');
insert into people.department_revisions(id,tenant_id,legal_entity_id,department_id,name,start_date,end_date_exclusive,reason,recorded_by)
values(pg_temp.wid('department-r1'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('department'),'Synthetic Operations',
 pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic payroll fixture',pg_temp.wid('creator'));
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,
 role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('organization-employee'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'),s.id,
 pg_temp.wid('department'),pg_temp.wid('calendar-version'),'Synthetic worker',pg_temp.wdate()-10,pg_temp.wdate()+400,
 'Synthetic payroll fixture',pg_temp.wid('creator') from people.employment_spells s where s.employee_id=pg_temp.wid('employee');
create function pg_temp.pc(p jsonb,v bigint,k text) returns jsonb language sql as $$
 select api.people_payroll_configure(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(k),pg_temp.wid(k),now(),p,v)
$$;
create function pg_temp.pcmd(p jsonb,v bigint,k text,b text default 'branch') returns jsonb language sql as $$
 select api.people_payroll_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid(b),pg_temp.wid(k),pg_temp.wid(k),now(),p,v)
$$;
create function pg_temp.publish(code text,class text,amount text,expense text,liability text,
 basis text default 'fixed',n bigint default 1,d bigint default 1) returns jsonb language sql as $$
 select jsonb_build_object('action','publish','id',pg_temp.wid('rule.'||code),'component_id',pg_temp.wid('component.'||code),
  'code',code,'name','Synthetic '||code,'classification',class,'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,
  'basis',basis,'proration','none','rounding','half_away','precision',2,'amount',amount,'ratio_numerator',n,'ratio_denominator',d,
  'cap',null,'expense_account_id',case when expense is not null then pg_temp.wid('pay.'||expense) end,
  'liability_account_id',case when liability is not null then pg_temp.wid('pay.'||liability) end,'reason','Synthetic rule')
$$;
create function pg_temp.run_create(k text default 'run') returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid(k),'name','Synthetic payroll',
  'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+1,'posting_date',pg_temp.wdate(),
  'employee_ids',jsonb_build_array(pg_temp.wid('employee')),'reason','Synthetic run')
$$;
create function pg_temp.run_action(action text,k text default 'run') returns jsonb language sql as $$
 select jsonb_build_object('action',action,'id',pg_temp.wid(k),'revision_id',current_revision_id,
  'digest',(select digest from people_payroll.run_revisions where id=current_revision_id),'reason','Synthetic transition')
 from people_payroll.runs where id=pg_temp.wid(k)
$$;
create function pg_temp.settle(amount text,evidence text default 'SYNTHETIC-TRANSFER-001') returns jsonb language sql security definer as $$
 select jsonb_build_object('action','record','id',pg_temp.wid('settlement'),'run_id',pg_temp.wid('run'),
  'posting_date',pg_temp.wdate(),'bank_id',pg_temp.wid('pay.bank.record'),'bank_version',1,
  'evidence_reference',evidence,'reason','Synthetic recorded evidence',
  'allocations',jsonb_build_array(jsonb_build_object('obligation_id',(select id from people_payroll.obligations where kind='net'),'amount',amount)))
$$;
create function pg_temp.ps(p jsonb,v bigint,k text) returns jsonb language sql as $$
 select api.people_payroll_settlement(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(k),pg_temp.wid(k),now(),p,v)
$$;
create temporary table payroll_responses(name text primary key,response jsonb);
grant select,insert on payroll_responses to authenticated;
-- Test fixture helpers read headers as their owner; the actual named APIs still
-- execute using current synthetic JWT claims and the authenticated SQL role.
alter function pg_temp.run_action(text,text) security definer;
select pg_temp.wactor('branch-manager');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select api.people_payroll_runs(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'))$q$,
 '42501',null,'wrong branch requires actual role scope');
reset role;
-- Entity-wide creator/reviewer grants deliberately authorize both branches.
select pg_temp.wactor('reader');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select api.people_payroll_rules(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501',null,'People directory permission does not read payroll');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_responses values('settings',pg_temp.pc(jsonb_build_object('action','settings','id',pg_temp.wid('settings'),
 'net_account_id',pg_temp.wid('pay.net'),'reason','Synthetic control'),0,'settings.cmd'));
insert into payroll_responses values('base',pg_temp.pc(pg_temp.publish('BASE','earning','1000','wages',null),0,'base.cmd'));
insert into payroll_responses values('deduct',pg_temp.pc(pg_temp.publish('DEDUCT','deduction','0',null,'deduct','earnings_ratio',1,10),0,'deduct.cmd'));
insert into payroll_responses values('employer',pg_temp.pc(pg_temp.publish('EMPLOYER','employer_cost','0','employer','employer_control','earnings_ratio',3,100),0,'employer.cmd'));
reset role;
insert into payroll_assertions select ok(not exists(select 1 from audit.events where tenant_id=pg_temp.wid('tenant') and event_type like 'people.payroll.%'
 and (after_context::text like '%1000%' or after_context ? 'amount')),'pay configuration never leaks amount to generic audit');
select pg_temp.wactor('creator');set local role authenticated;
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pay.clock.create'),pg_temp.wid('pay.clock.create'),now(),
 jsonb_build_object('action','create','id',pg_temp.wid('pay.attendance'),'employee_id',pg_temp.wid('employee'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(pg_temp.wdate()::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,'reason','Synthetic payroll time'),0);
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pay.clock.submit'),pg_temp.wid('pay.clock.submit'),now(),
 jsonb_build_object('action','submit','id',pg_temp.wid('pay.attendance'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic payroll time'),1);
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pay.clock.approve'),pg_temp.wid('pay.clock.approve'),now(),
 jsonb_build_object('action','approve','id',pg_temp.wid('pay.attendance'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic payroll time'),2);
reset role;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pc(jsonb_build_object('action','assign','id',pg_temp.wid('assign.'||x),'employee_id',pg_temp.wid('employee'),
 'component_id',pg_temp.wid('component.'||x),'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,'reason','Synthetic assignment'),0,'assign.'||x)
from unnest(array['BASE','DEDUCT','EMPLOYER']) x;
insert into payroll_responses values('create',pg_temp.pcmd(pg_temp.run_create(),0,'run.create'));
insert into payroll_responses values('prepare',pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('run'),'reason','Synthetic prepare'),1,'run.prepare'));
insert into payroll_assertions select is((api.people_payroll_run_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('run'))->'calculations'->0->>'net'),
 '900.000000','frozen employee exact net');
insert into payroll_responses values('submit',pg_temp.pcmd(pg_temp.run_action('submit'),2,'run.submit'));
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('approve'),3,'run.selfapprove')$q$,
 '42501','PAYROLL_INDEPENDENT_APPROVAL_REQUIRED','preparer cannot approve');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
insert into payroll_responses values('approve',pg_temp.pcmd(pg_temp.run_action('approve'),3,'run.approve'));
reset role;
-- A source identity change after approval invalidates the freeze.
update people.employees set version=version+1 where id=pg_temp.wid('employee');
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('post'),4,'run.stale.post')$q$,
 '40001','PAYROLL_INPUTS_CHANGED','source change blocks posting');
insert into payroll_responses values('reprepare',pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('run'),'reason','Synthetic reprepare'),4,'run.reprepare'));
insert into payroll_assertions select is((select response->'entity'->>'approved_by' from payroll_responses where name='reprepare'),null::text,'repreparation clears approval');
insert into payroll_responses values('resubmit',pg_temp.pcmd(pg_temp.run_action('submit'),5,'run.resubmit'));
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
insert into payroll_responses values('reapprove',pg_temp.pcmd(pg_temp.run_action('approve'),6,'run.reapprove'));
reset role;
create function pg_temp.payroll_fail_late() returns trigger language plpgsql as $$begin
 if new.command_id=pg_temp.wid('run.fail.post') then raise exception using errcode='P0001',message='SYNTHETIC_PAYROLL_LATE_FAILURE';end if;return new;
end $$;
create trigger synthetic_payroll_fail_late before insert on core.outbox_events for each row execute function pg_temp.payroll_fail_late();
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('post'),7,'run.fail.post')$q$,
 'P0001','SYNTHETIC_PAYROLL_LATE_FAILURE','late outbox failure rolls back the whole posting');
reset role;
insert into payroll_assertions select is((select count(*)::integer from people_payroll.obligations),0,'failed posting has no obligations');
insert into payroll_assertions select is((select count(*)::integer from people_payroll.payslips),0,'failed posting has no payslips');
insert into payroll_assertions select is((select count(*)::integer from finance.journal_entries where tenant_id=pg_temp.wid('tenant')),0,'failed posting has no journal');
insert into payroll_assertions select is((select count(*)::integer from people.work_input_seals),0,'failed posting has no input seals');
insert into payroll_assertions select is((select next_value from core.document_sequences where tenant_id=pg_temp.wid('tenant') and document_type='journal_entry'),1::bigint,'failed posting restores document number');
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_responses values('post',pg_temp.pcmd(pg_temp.run_action('post'),7,'run.post'));
insert into payroll_assertions select is(pg_temp.pcmd(pg_temp.run_action('post'),7,'run.post'),(select response from payroll_responses where name='post'),'exact posting replay');
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('post')||'{"reason":"changed"}',7,'run.post')$q$,'22023','IDEMPOTENCY_MISMATCH','changed body cannot reuse posting key');
reset role;
insert into payroll_assertions select is((select count(*)::integer from people_payroll.obligations),3,'net deduction employer obligations have separate attribution');
insert into payroll_assertions select is((select count(*)::integer from people_payroll.payslips),1,'one immutable payslip');
insert into payroll_assertions select is((select count(*)::integer from people.work_input_seals),1,'posting seals exact approved attendance revision');
insert into payroll_assertions select is((select sum(base_debit-base_credit) from finance.journal_lines where tenant_id=pg_temp.wid('tenant')),0::numeric,'posted journal balanced');
insert into payroll_assertions select is((select sum(amount) from people_payroll.obligations),1030::numeric,'obligation control total equals net deduction employer cost');
insert into payroll_assertions select ok(not exists(select 1 from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
 where j.source_type='payroll' and l.base_credit>0 and not exists(select 1 from people_payroll.obligations o where o.id=l.source_line_id and o.account_id=l.account_id)),
 'every payroll control credit names exact obligation source');
insert into payroll_assertions select throws_ok($q$update people_payroll.payslips set issued_at=now()$q$,'55000','PAYROLL_HISTORY_IMMUTABLE','payslip immutable');
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('sealed.cancel'),pg_temp.wid('sealed.cancel'),now(),
 jsonb_build_object('action','cancel','id',pg_temp.wid('pay.attendance'),'employee_id',pg_temp.wid('employee'),'reason','Synthetic correction'),3)$q$,
 '55000','PAYROLL_INPUT_SEALED','payroll-consumed attendance cannot be silently cancelled');
insert into payroll_assertions select is(api.people_payroll_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('run.post'),'people.payroll.post'),
 (select response from payroll_responses where name='post'),'minimal own receipt restores uncertain posting');
insert into payroll_assertions select throws_ok($q$select api.people_payroll_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('run.post'),'people.payroll.view')$q$,
 '42501','PAYROLL_RECEIPT_SCOPE_DENIED','receipt read cannot substitute another capability');
insert into payroll_assertions select throws_ok($q$select pg_temp.ps(pg_temp.settle('900.01'),0,'settle.overpay')$q$,'55000','PAYROLL_SETTLEMENT_EXCEEDS_DUE','no overpayment');
insert into payroll_responses values('settlement',pg_temp.ps(pg_temp.settle('200.00'),0,'settle.record'));
insert into payroll_assertions select is(pg_temp.ps(pg_temp.settle('200.00'),0,'settle.record'),(select response from payroll_responses where name='settlement'),'settlement retry is exact');
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('reverse'),8,'run.settled.reverse')$q$,
 '55000','PAYROLL_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL','active settlement prevents run reversal');
insert into payroll_assertions select is((api.people_payroll_payslips(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'))->'items'->0->>'net'),
 '900.000000','payslip separately authorized');
reset role;
insert into payroll_assertions select is((select sum(amount) from people_payroll.obligation_effects where obligation_id=(select id from people_payroll.obligations where kind='net')),700::numeric,
 'recorded settlement lowers own payroll obligation only');
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_responses values('settlement.reverse',pg_temp.ps(jsonb_build_object('action','reverse','id',pg_temp.wid('settlement'),
 'run_id',pg_temp.wid('run'),'posting_date',pg_temp.wdate(),'reason','Synthetic reversal'),1,'settle.reverse'));
insert into payroll_assertions select throws_ok($q$select pg_temp.ps(jsonb_build_object('action','reverse','id',pg_temp.wid('settlement'),'run_id',pg_temp.wid('run'),
 'posting_date',pg_temp.wdate(),'reason','Synthetic reversal'),2,'settle.reverse.again')$q$,
 '55000','PAYROLL_SETTLEMENT_ALREADY_REVERSED','settlement original only once');
reset role;
insert into payroll_assertions select is((select sum(amount) from people_payroll.obligation_effects where obligation_id=(select id from people_payroll.obligations where kind='net')),900::numeric,'settlement reversal restores original amount');
create function pg_temp.export_payload() returns jsonb language sql security definer as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid('export'),'payslip_id',(select id from people_payroll.payslips limit 1))
$$;
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_responses values('export',api.people_payroll_export(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('export.cmd'),pg_temp.wid('export.cmd'),now(),pg_temp.export_payload(),0));
insert into payroll_assertions select is(api.people_payroll_export_content(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('export'))->'payslip'->>'net',
 '900.000000','export freezes and verifies exact payslip');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select api.people_payroll_export_content(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('export'))$q$,
 'P0002','PAYROLL_EXPORT_NOT_FOUND','export content bound to original actor');
reset role;
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_responses values('reverse',pg_temp.pcmd(pg_temp.run_action('reverse'),8,'run.reverse'));
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('reverse'),9,'run.reverse.again')$q$,'55000','PAYROLL_RUN_STATE_INVALID','second original reversal denied');
reset role;
insert into payroll_assertions select is((select sum(amount) from people_payroll.obligation_effects),0::numeric,'original obligation effects reverse exactly');
insert into payroll_assertions select is((select sum(base_debit-base_credit) from finance.journal_lines where tenant_id=pg_temp.wid('tenant')),0::numeric,'reversed journals conserve');
insert into payroll_assertions select is((select count(*)::integer from people_payroll.payslips),1,'original payslip retained after reversal');
select pg_temp.wactor('creator','aal1');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('post'),7,'run.post')$q$,'42501',null,'MFA checked before posting replay');
reset role;
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select api.people_payroll_self_payslips(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501','HR_ACTIVE_LINK_REQUIRED','self payslips require an exact accepted account link');
select api.people_hr_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pay.policy.cmd'),pg_temp.wid('pay.policy.cmd'),now(),
 jsonb_build_object('action','policy_create','id',pg_temp.wid('pay.policy'),'purpose','Synthetic payroll account-link fixture'),0);
select api.people_hr_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pay.link.cmd'),pg_temp.wid('pay.link.cmd'),now(),
 jsonb_build_object('action','link_initiate','id',pg_temp.wid('pay.link'),'employee_id',pg_temp.wid('employee'),
 'membership_id',pg_temp.wid('reader.membership'),'user_id',pg_temp.wid('reader')),0);
reset role;select pg_temp.wactor('reader');set local role authenticated;
select api.people_hr_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('pay.link.accept'),pg_temp.wid('pay.link.accept'),now(),
 jsonb_build_object('action','link_accept','id',pg_temp.wid('pay.link'),'employee_id',pg_temp.wid('employee')),1);
insert into payroll_assertions select throws_ok($q$select api.people_payroll_self_payslips(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501',null,'accepted account link grants no payroll capability');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('reader.role'),'people.payroll.payslip.self');
select pg_temp.wactor('reader');set local role authenticated;
insert into payroll_assertions select is(api.people_payroll_self_payslips(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))->'items'->0->>'net',
 '900.000000','self-only permission reads only the accepted employee payslip');
insert into payroll_assertions select throws_ok($q$select api.people_payroll_runs(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501',null,'self-only permission cannot read payroll runs');
reset role;
update core.memberships set status='suspended' where id=pg_temp.wid('reader.membership');
select pg_temp.wactor('reader');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select api.people_payroll_self_payslips(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
 '42501',null,'membership revocation denies self payslip immediately');
reset role;
create function pg_temp.payroll_calculation_id() returns uuid language sql security definer as $$
 select id from people_payroll.employee_calculations order by id limit 1
$$;
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select is(jsonb_array_length(api.people_payroll_assignments(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('employee'))->'items'),
 3,'named scoped employee component assignments are inspectable');
insert into payroll_assertions select is(jsonb_array_length(api.people_payroll_snapshot(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.payroll_calculation_id(),'rules')->'items'),
 3,'original frozen rules remain inspectable after reversal');
insert into payroll_assertions select ok(jsonb_array_length(api.people_payroll_snapshot(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.payroll_calculation_id(),'planned_slots')->'items')>0,
 'original calendar slot evidence is paged');
insert into payroll_assertions select throws_ok($q$select api.people_payroll_snapshot(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.payroll_calculation_id(),'rules',2001)$q$,
 '22023','PAYROLL_SNAPSHOT_CURSOR_INVALID','frozen evidence cursor has an explicit bound');
reset role;
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.payroll.post';
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('post'),7,'run.post')$q$,'42501',null,'revoked posting permission blocks replay');
insert into payroll_assertions select throws_ok($q$select api.people_payroll_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('run.post'),'people.payroll.post')$q$,
 '42501',null,'revoked posting permission blocks own receipt');
reset role;


-- W4-04 additive candidate. Private, synthetic sealed eligibility adjustments.
-- No existing role/plan grants. Temporal source edits remain operational impacts.
insert into core.permissions(code,module,description,privileged) values
 ('people.payroll.correction.prepare','people','Prepare linked synthetic payroll eligibility corrections',true),
 ('people.payroll.correction.approve','people','Independently approve linked payroll corrections',true)
on conflict(code) do nothing;

create table people_payroll.corrections(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 original_calculation_id uuid not null,employee_id uuid not null,original_run_id uuid not null,
 predecessor_id uuid,chain_version bigint not null check(chain_version between 0 and 2000),
 posting_date date not null,currency_code text not null references core.currencies(code),
 status text not null default 'prepared' check(status in('prepared','approved','rejected','posted','reversed')),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 before_calculation jsonb not null,after_calculation jsonb not null,difference jsonb not null,
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 approved_by uuid references auth.users(id),approved_digest text,posted_journal_id uuid,reversal_journal_id uuid,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,original_calculation_id) references people_payroll.employee_calculations(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,original_run_id) references people_payroll.runs(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,predecessor_id) references people_payroll.corrections(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,posted_journal_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,reversal_journal_id) references finance.journal_entries(tenant_id,id)
);
create index payroll_correction_scope_idx on people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id);
create index payroll_correction_original_idx on people_payroll.corrections(tenant_id,legal_entity_id,original_calculation_id,id);
create index payroll_correction_run_idx on people_payroll.corrections(tenant_id,legal_entity_id,original_run_id);
create index payroll_correction_employee_idx on people_payroll.corrections(tenant_id,legal_entity_id,employee_id);
create index payroll_correction_predecessor_idx on people_payroll.corrections(tenant_id,legal_entity_id,predecessor_id);
create index payroll_correction_actor_idx on people_payroll.corrections(prepared_by);
create index payroll_correction_approver_idx on people_payroll.corrections(approved_by);
create index payroll_correction_journal_idx on people_payroll.corrections(tenant_id,posted_journal_id);
create index payroll_correction_reversal_idx on people_payroll.corrections(tenant_id,reversal_journal_id);
create table people_payroll.correction_sources(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,correction_id uuid not null,
 employee_id uuid not null,seal_id uuid not null,source_kind text not null check(source_kind in('attendance','leave','project','service')),
 source_id uuid not null,source_digest text not null check(source_digest ~ '^[a-f0-9]{64}$'),
 before_revision_id uuid not null,after_revision_id uuid not null unique,
 impact jsonb,
 before_version bigint not null check(before_version between 1 and 2001),
 before_seconds bigint not null check(before_seconds between 0 and 129600),
 after_seconds bigint not null check(after_seconds between 0 and 129600),
 original_seconds bigint not null check(original_seconds between 0 and 129600),
 check((impact is not null or(after_seconds<=original_seconds and before_seconds<=original_seconds)) and (impact is not null or before_seconds<>after_seconds)),
 unique(tenant_id,legal_entity_id,correction_id,seal_id),unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(seal_id) references people.work_input_seals(id)
);
create index payroll_correction_sources_seal_idx on people_payroll.correction_sources(seal_id);
create index payroll_correction_sources_employee_idx on people_payroll.correction_sources(tenant_id,legal_entity_id,employee_id);
create index payroll_correction_sources_scope_idx on people_payroll.correction_sources(tenant_id,legal_entity_id,correction_id,id);
create table people_payroll.correction_source_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 correction_id uuid not null,source_id uuid not null,seal_id uuid not null,
 revision_id uuid not null unique,version bigint not null check(version between 2 and 2002),
 seconds bigint not null check(seconds between 0 and 129600),kind text not null check(kind in('apply','reverse')),
 operational_claim_id uuid,operational_source_id uuid,operational_source_version bigint,operational_snapshot jsonb,
 reversal_of uuid unique,recorded_at timestamptz not null default clock_timestamp(),
 unique(seal_id,version),unique(correction_id,seal_id,kind),
 foreign key(tenant_id,legal_entity_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,source_id) references people_payroll.correction_sources(tenant_id,legal_entity_id,id),
 foreign key(seal_id) references people.work_input_seals(id),foreign key(reversal_of) references people_payroll.correction_source_effects(id),
 check((kind='reverse')=(reversal_of is not null))
);
create index payroll_correction_source_effect_scope_idx on people_payroll.correction_source_effects(tenant_id,legal_entity_id,correction_id,id);
create index payroll_correction_source_effect_source_idx on people_payroll.correction_source_effects(tenant_id,legal_entity_id,source_id);
create table people_payroll.correction_balances(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 correction_id uuid not null,employee_id uuid not null,rule_version_id uuid,kind text not null check(kind in('net','deduction','employer_cost')),
 account_id uuid not null,currency_code text not null references core.currencies(code),amount numeric(20,6) not null check(amount<>0),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,rule_version_id) references people_payroll.rule_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 check((kind='net')=(rule_version_id is null))
);
create index payroll_correction_balances_scope_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,branch_id,correction_id,id);
create index payroll_correction_balances_employee_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,employee_id);
create index payroll_correction_balances_rule_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,rule_version_id);
create index payroll_correction_balances_account_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,account_id);
create table people_payroll.correction_balance_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,balance_id uuid not null,
 kind text not null check(kind in('issue','settle','settlement_reverse','correction_reverse')),
 amount numeric(20,6) not null check(amount<>0),source_id uuid not null,reversal_of uuid unique,
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(balance_id,kind,source_id),
 foreign key(tenant_id,legal_entity_id,balance_id) references people_payroll.correction_balances(tenant_id,legal_entity_id,id),
 foreign key(reversal_of) references people_payroll.correction_balance_effects(id),
 check((kind in('settlement_reverse','correction_reverse'))=(reversal_of is not null))
);
create index payroll_correction_balance_effect_scope_idx on people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,id);
create index payroll_correction_balance_effect_actor_idx on people_payroll.correction_balance_effects(recorded_by);
create table people_payroll.correction_settlements(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,correction_id uuid not null,
 bank_id uuid not null,bank_account_id uuid not null,bank_version bigint not null,currency_code text not null,
 posting_date date not null,direction text not null check(direction in('pay','recover')),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 1 and 160),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 version bigint not null default 1,status text not null default 'recorded' check(status in('recorded','reversed')),
 journal_id uuid not null,reversal_journal_id uuid,recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,evidence_reference),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,bank_id) references finance.cash_bank_accounts(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,bank_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,journal_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,reversal_journal_id) references finance.journal_entries(tenant_id,id)
);
create index payroll_correction_settlement_scope_idx on people_payroll.correction_settlements(tenant_id,legal_entity_id,branch_id,correction_id,id);
create index payroll_correction_settlement_bank_idx on people_payroll.correction_settlements(tenant_id,legal_entity_id,bank_id);
create index payroll_correction_settlement_account_idx on people_payroll.correction_settlements(tenant_id,legal_entity_id,bank_account_id);
create index payroll_correction_settlement_journal_idx on people_payroll.correction_settlements(tenant_id,journal_id);
create index payroll_correction_settlement_reverse_idx on people_payroll.correction_settlements(tenant_id,reversal_journal_id);
create index payroll_correction_settlement_actor_idx on people_payroll.correction_settlements(recorded_by);
create table people_payroll.correction_settlement_allocations(
 tenant_id uuid not null,legal_entity_id uuid not null,settlement_id uuid not null,balance_id uuid not null,
 amount numeric(20,6) not null check(amount>0),primary key(settlement_id,balance_id),
 foreign key(tenant_id,legal_entity_id,settlement_id) references people_payroll.correction_settlements(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,balance_id) references people_payroll.correction_balances(tenant_id,legal_entity_id,id)
);
create index payroll_correction_settlement_allocation_balance_idx on people_payroll.correction_settlement_allocations(tenant_id,legal_entity_id,balance_id);
create table people_payroll.correction_payslips(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 correction_id uuid not null unique,employee_id uuid not null,payload jsonb not null,digest text not null,
 issued_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create index payroll_correction_payslip_scope_idx on people_payroll.correction_payslips(tenant_id,legal_entity_id,branch_id,employee_id,id);
create table people_payroll.correction_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,correction_id uuid not null,original_calculation_id uuid not null,
 action text not null,version bigint not null,chain_sequence bigint,actor_id uuid not null references auth.users(id),
 reason text not null,command_id uuid not null,recorded_at timestamptz not null default clock_timestamp(),
 unique(original_calculation_id,chain_sequence),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,original_calculation_id) references people_payroll.employee_calculations(tenant_id,legal_entity_id,id)
);
create index payroll_correction_event_scope_idx on people_payroll.correction_events(tenant_id,legal_entity_id,branch_id,correction_id,id);
create index payroll_correction_event_original_idx on people_payroll.correction_events(tenant_id,legal_entity_id,original_calculation_id,chain_sequence);
create index payroll_correction_event_actor_idx on people_payroll.correction_events(actor_id);

create function people_payroll.correction_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='UPDATE' and tg_table_name='corrections' and
  (to_jsonb(new)-array['status','version','approved_by','approved_digest','posted_journal_id','reversal_journal_id'])=
  (to_jsonb(old)-array['status','version','approved_by','approved_digest','posted_journal_id','reversal_journal_id']) then return new;end if;
 if tg_op='UPDATE' and tg_table_name='correction_settlements' and
  (to_jsonb(new)-array['status','version','reversal_journal_id'])=(to_jsonb(old)-array['status','version','reversal_journal_id']) then return new;end if;
 raise exception using errcode='55000',message='PAYROLL_CORRECTION_HISTORY_IMMUTABLE';end $$;
do $$declare n text;begin
 foreach n in array array['corrections','correction_sources','correction_source_effects','correction_balances',
  'correction_balance_effects','correction_settlements','correction_settlement_allocations','correction_payslips','correction_events'] loop
  execute format('alter table people_payroll.%I enable row level security',n);
  execute format('alter table people_payroll.%I force row level security',n);
  execute format('revoke all on people_payroll.%I from public,anon,authenticated',n);
  execute format('create trigger immutable before update or delete on people_payroll.%I for each row execute function people_payroll.correction_guard()',n);
 end loop;end $$;

create function people_payroll.correction_access(t uuid,e uuid,b uuid,cap text,p_write boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 if cap not in('people.payroll.view','people.payroll.correction.prepare','people.payroll.correction.approve',
  'people.payroll.post','people.payroll.reverse','people.payroll.settle','people.payroll.payslip.view') or cap is null then
  raise exception using errcode='42501',message='PAYROLL_CORRECTION_SCOPE_DENIED';end if;
 perform people.require_access(t,e,b,cap);
 if p_write and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='PAYROLL_MFA_REQUIRED';end if;
end $$;
create function api.people_payroll_correction_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability,true);
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'actor_id',auth.uid(),'capability',p_capability,'authorized',true);end $$;
create function people_payroll.approved_source(t uuid,e uuid,b uuid,employee uuid,claim uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w people.work_claims%rowtype;a people.attendance_entries%rowtype;l people.leave_requests%rowtype;r jsonb;begin
 select * into w from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and id=claim and active;
 if w.id is null then raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 if w.source_kind='attendance' then
  select * into a from people.attendance_entries where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and current_revision_id=w.source_id and active_claim_id=w.id and status='approved';
  if a.id is not null then r:=jsonb_build_object('source_id',w.source_id,'source_version',a.version,'paid_seconds',w.payable_seconds);end if;
 elsif w.source_kind='leave' then
  select * into l from people.leave_requests where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and active_claim_id=w.id and status='approved';
  if l.id is not null then r:=jsonb_build_object('source_id',w.source_id,'source_version',l.version,'paid_seconds',l.charge_seconds-l.unpaid_seconds);end if;
 elsif w.source_kind='project' and to_regprocedure('projects.payroll_source(uuid,uuid,uuid,uuid,uuid)') is not null then
  execute 'select projects.payroll_source($1,$2,$3,$4,$5)' into r using t,e,b,employee,claim;
 elsif w.source_kind='service' and to_regprocedure('service.payroll_source(uuid,uuid,uuid,uuid,uuid)') is not null then
  execute 'select service.payroll_source($1,$2,$3,$4,$5)' into r using t,e,b,employee,claim;
 end if;
 if r is null or r->>'source_id' is distinct from w.source_id::text or jsonb_typeof(r->'source_version')<>'number'
  or (r->>'source_version')::bigint not between 1 and 9007199254740991
  or jsonb_typeof(r->'paid_seconds')<>'number' or (r->>'paid_seconds')::bigint not between 0 and w.gross_seconds then
  raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 return r;end $$;
create function people_payroll.correction_source_permission(t uuid,e uuid,b uuid,kind text,decision boolean)
returns void language plpgsql security definer set search_path='' as $$begin
 perform people.require_access(t,e,b,case kind
  when 'attendance' then case when decision then 'people.attendance.approve' else 'people.attendance.manage' end
  when 'leave' then case when decision then 'people.leave.approve' else 'people.leave.manage' end
  when 'project' then case when decision then 'projects.time.approve' else 'projects.time.manage' end
  when 'service' then case when decision then 'service.time.approve' else 'service.time.manage' end
  else null end);end $$;
create function people_payroll.correction_summary(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'tenant_id',c.tenant_id,'legal_entity_id',c.legal_entity_id,'branch_id',c.branch_id,
  'original_calculation_id',c.original_calculation_id,'employee_id',c.employee_id,'original_run_id',c.original_run_id,
  'predecessor_id',c.predecessor_id,'chain_version',c.chain_version,'posting_date',c.posting_date,'currency_code',c.currency_code,
  'status',c.status,'version',c.version,'digest',c.digest,'prepared_by',c.prepared_by,'approved_by',c.approved_by,
  'posted_journal_id',c.posted_journal_id,'reversal_journal_id',c.reversal_journal_id)
 from people_payroll.corrections c where c.id=p_id $$;
create function people_payroll.correction_source_state(p_seal uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('seal_id',s.id,'revision_id',coalesce(x.revision_id,w.source_id),'version',coalesce(x.version,1),
  'paid_seconds',coalesce(x.seconds,s.seconds),'original_seconds',s.seconds,'source_kind',w.source_kind,'source_id',w.source_id,
  'source_digest',s.digest,'claim_id',case when x.id is null then w.id else x.operational_claim_id end,
  'operational_source_id',coalesce(x.operational_source_id,w.source_id),'operational_source_version',coalesce(x.operational_source_version,s.source_version),
  'operational_snapshot',x.operational_snapshot)
 from people.work_input_seals s join people.work_claims w on w.id=s.claim_id
 left join lateral(select * from people_payroll.correction_source_effects where seal_id=s.id order by version desc limit 1) x on true
 where s.id=p_seal $$;
create function people_payroll.correction_difference(before jsonb,after jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare lines jsonb;begin
 if jsonb_array_length(before->'lines')<>jsonb_array_length(after->'lines') then raise exception using errcode='22023',message='PAYROLL_CORRECTION_RULES_CHANGED';end if;
 select jsonb_agg(jsonb_build_object('rule_version_id',a->>'rule_version_id','code',a->>'code','classification',a->>'classification',
  'before',b,'after',a,'difference',round((a->>'amount')::numeric-(b->>'amount')::numeric,6)::text) order by a->>'code') into lines
 from jsonb_array_elements(after->'lines') a join jsonb_array_elements(before->'lines') b on b->>'rule_version_id'=a->>'rule_version_id';
 if jsonb_array_length(lines)<>jsonb_array_length(after->'lines') then raise exception using errcode='22023',message='PAYROLL_CORRECTION_RULES_CHANGED';end if;
 return jsonb_build_object('lines',lines,'gross',round((after->>'gross')::numeric-(before->>'gross')::numeric,6)::text,
  'deductions',round((after->>'deductions')::numeric-(before->>'deductions')::numeric,6)::text,
  'employer_cost',round((after->>'employer_cost')::numeric-(before->>'employer_cost')::numeric,6)::text,
  'net',round((after->>'net')::numeric-(before->>'net')::numeric,6)::text);end $$;

create function api.people_payroll_correction_originals(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.correction.prepare',true);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'run_id',q.run_id,'employee_id',q.employee_id,'employee_code',q.inputs->>'employee_code',
  'employee_name',q.inputs->>'employee_name','start_date',q.inputs->>'start_date','end_date_exclusive',q.inputs->>'end_date_exclusive',
  'currency_code',r.currency_code,'original_net',q.net::text) order by q.id),'[]') into items
 from(select ec.* from people_payroll.employee_calculations ec join people_payroll.runs r on r.id=ec.run_id
  where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.status='posted'
  and ec.revision_id=r.current_revision_id and (p_after is null or ec.id>p_after) order by ec.id limit 51) q
 join people_payroll.runs r on r.id=q.run_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.people_payroll_correction_sources(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_calculation_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare c people_payroll.employee_calculations%rowtype;items jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.correction.prepare',true);
 select ec.* into c from people_payroll.employee_calculations ec join people_payroll.runs r on r.id=ec.run_id
  where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and ec.id=p_calculation_id
  and r.status='posted' and ec.revision_id=r.current_revision_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_ORIGINAL_CALCULATION_NOT_FOUND';end if;
 select coalesce(jsonb_agg(people_payroll.correction_source_state(q.id)||jsonb_build_object('id',q.id,
  'start_utc',w.start_utc,'end_utc',w.end_utc,'calendar_version_id',w.calendar_version_id,
  'operational',people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,
   (people_payroll.correction_source_state(q.id)->>'claim_id')::uuid,gen_random_uuid(),jsonb_build_object('source_kind',w.source_kind),'read')) order by q.id),'[]') into items
 from(select * from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and run_id=c.run_id
  and employee_id=c.employee_id and claim_id in(select (value->>'claim_id')::uuid from jsonb_array_elements(c.inputs->'sources'))
  and (p_after is null or id>p_after) order by id limit 51) q join people.work_claims w on w.id=q.claim_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'calculation_id',p_calculation_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.people_payroll_corrections(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view',true);
 select coalesce(jsonb_agg(people_payroll.correction_summary(q.id) order by q.id),'[]') into items from
 (select id from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and(p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.people_payroll_correction_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_correction_id uuid,p_section text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare c people_payroll.corrections%rowtype;items jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,case when p_section='balances' then 'people.payroll.settle'
  when p_section='payslip' then 'people.payroll.payslip.view' else 'people.payroll.view' end,true);
 select * into c from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_correction_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_NOT_FOUND';end if;
 if p_section='calculation' then
  items:=jsonb_build_array(jsonb_build_object('id',c.id,'before',c.before_calculation,'after',c.after_calculation,'difference',c.difference,'reason',c.reason));
 elsif p_section='sources' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from
  (select * from people_payroll.correction_sources where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='balances' then select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('amount',q.amount::text,'outstanding',
  round((select coalesce(sum(amount),0) from people_payroll.correction_balance_effects where balance_id=q.id),6)::text) order by q.id),'[]') into items
  from(select * from people_payroll.correction_balances where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='settlements' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from
  (select * from people_payroll.correction_settlements where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='history' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from
  (select * from people_payroll.correction_events where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='payslip' then select coalesce(jsonb_agg(jsonb_build_object('id',id,'correction_id',correction_id,'employee_id',employee_id,
  'payload',payload,'digest',digest,'issued_at',issued_at)),'[]') into items from people_payroll.correction_payslips where correction_id=c.id;
 else raise exception using errcode='22023',message='PAYROLL_CORRECTION_SECTION_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'correction',people_payroll.correction_summary(c.id),
 'section',p_section,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;

create function api.people_payroll_correction_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare act text:=p_payload->>'action';cid uuid;cap text;c people_payroll.corrections%rowtype;
 original people_payroll.employee_calculations%rowtype;r people_payroll.runs%rowtype;src people_payroll.correction_sources%rowtype;
 x jsonb;state jsonb;inputs jsonb;sources jsonb:='[]';changes jsonb:='[]';before_calc jsonb;after_calc jsonb;diff jsonb;impact jsonb;operational jsonb;replacement_id uuid;
 seq bigint;predecessor uuid;paid bigint:=0;seen uuid[]:='{}';w people.work_input_seals%rowtype;
 hash text;replay jsonb;before_summary jsonb:='{}';after_summary jsonb;line jsonb;lines jsonb:='[]';v_amount numeric;
 account uuid;balance uuid;journal uuid;request uuid:=gen_random_uuid();rule people_payroll.rule_versions%rowtype;
 setting people_payroll.settings_versions%rowtype;latest people_payroll.correction_events%rowtype;
begin
 if act is null or act not in('prepare','approve','reject','post','reverse') or p_command_id is null or p_idempotency_key is null
  or p_client_timestamp is null or p_expected_version is null or p_expected_version not between 0 and 9007199254740991
  or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>65536
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='PAYROLL_CORRECTION_COMMAND_INVALID';end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(case when act='prepare' then
  array['action','id','original_calculation_id','posting_date','replacements','reason'] when act='reverse' then
  array['action','id','digest','posting_date','reason'] else array['action','id','digest','reason'] end)) then
  raise exception using errcode='22023',message='PAYROLL_CORRECTION_FIELDS_INVALID';end if;
 cap:=case act when 'prepare' then 'people.payroll.correction.prepare' when 'approve' then 'people.payroll.correction.approve'
  when 'post' then 'people.payroll.post' when 'reverse' then 'people.payroll.reverse' else 'people.payroll.correction.approve' end;
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 cid:=(p_payload->>'id')::uuid;
 hash:=core.wave3_request_hash('people.payroll.correction.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 -- Source-specific authority is checked before replay as well as business effects.
 if act='prepare' then
  select ec.* into original from people_payroll.employee_calculations ec join people_payroll.runs rr on rr.id=ec.run_id
   where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and rr.branch_id=p_branch_id
    and ec.id=(p_payload->>'original_calculation_id')::uuid and ec.revision_id=rr.current_revision_id and rr.status='posted';
 else
  select * into c from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=cid;
  select * into original from people_payroll.employee_calculations where id=c.original_calculation_id;
 end if;
 if original.id is null then raise exception using errcode='P0002',message='PAYROLL_ORIGINAL_CALCULATION_NOT_FOUND';end if;
 if act='prepare' then
  if jsonb_typeof(p_payload->'replacements')<>'array' or jsonb_array_length(p_payload->'replacements') not between 1 and 200 then
   raise exception using errcode='22023',message='PAYROLL_CORRECTION_REPLACEMENTS_INVALID';end if;
  for x in select value from jsonb_array_elements(p_payload->'replacements') loop
   select * into w from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and employee_id=original.employee_id and run_id=original.run_id and id=(x->>'seal_id')::uuid;
   if w.id is null then raise exception using errcode='42501',message='PAYROLL_CORRECTION_SOURCE_SCOPE_DENIED';end if;
   state:=people_payroll.correction_source_state(w.id);
   perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,state->>'source_kind',false);
  end loop;
 elsif act in('approve','reject') then
  for src in select * from people_payroll.correction_sources where correction_id=cid loop
   perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,src.source_kind,true);
  end loop;
 end if;
 replay:=core.wave3_replay(p_tenant_id,'people.payroll.correction.'||act,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=original.employee_id for update;
 select * into r from people_payroll.runs where id=original.run_id for update;
 if r.status<>'posted' then raise exception using errcode='55000',message='PAYROLL_ORIGINAL_RUN_NOT_POSTED';end if;
 select coalesce(max(chain_sequence),0) into seq from people_payroll.correction_events where original_calculation_id=original.id;
 select * into latest from people_payroll.correction_events where original_calculation_id=original.id and chain_sequence is not null order by chain_sequence desc limit 1;
 predecessor:=latest.correction_id;
 if seq>=2000 then raise exception using errcode='55000',message='PAYROLL_CORRECTION_CHAIN_BOUND_REQUIRED';end if;
 if act='prepare' then
  if p_expected_version<>0 or coalesce(p_payload->>'posting_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or(p_payload->>'posting_date')::date<r.end_date_exclusive then raise exception using errcode='22023',message='PAYROLL_OFFCYCLE_DATE_INVALID';end if;
  inputs:=original.inputs;
  for x in select value from jsonb_array_elements(original.inputs->'sources') order by value->>'claim_id' loop
   select * into w from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and run_id=r.id and employee_id=original.employee_id and claim_id=(x->>'claim_id')::uuid;
   if w.id is null or w.digest<>people_payroll.digest(x) then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   state:=people_payroll.correction_source_state(w.id);
   sources:=sources||jsonb_build_array(x||jsonb_build_object('paid_seconds',(state->>'paid_seconds')::bigint));
   paid:=paid+(state->>'paid_seconds')::bigint;
  end loop;
  inputs:=inputs||jsonb_build_object('sources',sources,'paid_seconds',paid);
  before_calc:=people_payroll.calculate(inputs,original.inputs->'rules',r.currency_code);
  paid:=0;sources:='[]';
  for x in select value from jsonb_array_elements(p_payload->'replacements') order by value->>'seal_id' loop
   if jsonb_typeof(x)<>'object' or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['seal_id','before_revision_id','expected_version','paid_seconds','impact']))
    or not(x ?& array['seal_id','before_revision_id','expected_version','paid_seconds'])
    or jsonb_typeof(x->'expected_version')<>'number' or jsonb_typeof(x->'paid_seconds')<>'number'
    or coalesce(x->>'paid_seconds','') !~ '^[0-9]{1,6}$' or(x->>'seal_id')::uuid=any(seen) then
    raise exception using errcode='22023',message='PAYROLL_CORRECTION_REPLACEMENTS_INVALID';end if;
   seen:=array_append(seen,(x->>'seal_id')::uuid);
   select * into w from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and run_id=r.id and employee_id=original.employee_id and id=(x->>'seal_id')::uuid;
   state:=people_payroll.correction_source_state(w.id);
   if state->>'revision_id' is distinct from x->>'before_revision_id' or(state->>'version')::bigint is distinct from(x->>'expected_version')::bigint then
    raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   if(x->>'paid_seconds')::bigint not between 0 and 129600 or(x->'impact' is null and((x->>'paid_seconds')::bigint>w.seconds or(x->>'paid_seconds')::bigint=(state->>'paid_seconds')::bigint)) then
    raise exception using errcode='22023',message='PAYROLL_CORRECTION_ELIGIBILITY_INVALID';end if;
   replacement_id:=gen_random_uuid();impact:=null;
   perform people_payroll.approved_source(p_tenant_id,p_legal_entity_id,p_branch_id,original.employee_id,(state->>'claim_id')::uuid);
   if x->'impact' is not null then
    impact:=x->'impact'||jsonb_build_object('correction_id',cid,'source_kind',state->>'source_kind');
    operational:=people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,original.employee_id,(state->>'claim_id')::uuid,replacement_id,impact,'validate');
    if impact->>'mode'='geometry' and((operational->'after'->>'start_utc')::timestamptz<people.resolve_local_instant(original.inputs->>'timezone',(original.inputs->>'eligible_start')::timestamp)
     or(operational->'after'->>'end_utc')::timestamptz>people.resolve_local_instant(original.inputs->>'timezone',(original.inputs->>'eligible_end_exclusive')::timestamp)) then
     raise exception using errcode='55000',message='PAYROLL_CORRECTION_ORIGINAL_PERIOD_REQUIRED';end if;
    if (operational->>'paid_seconds')::bigint is distinct from(x->>'paid_seconds')::bigint then raise exception using errcode='22023',message='PAYROLL_CORRECTION_SOURCE_AMOUNT_MISMATCH';end if;
    impact:=impact||jsonb_build_object('before',operational->'before','after',operational->'after');
   end if;
   changes:=changes||jsonb_build_array(state||jsonb_build_object('id',gen_random_uuid(),'after_revision_id',replacement_id,'after_seconds',(x->>'paid_seconds')::bigint,'impact',impact));
  end loop;
  for x in select value from jsonb_array_elements(inputs->'sources') loop
   select * into w from people.work_input_seals where run_id=r.id and employee_id=original.employee_id and claim_id=(x->>'claim_id')::uuid;
   state:=(select value from jsonb_array_elements(changes) where value->>'seal_id'=w.id::text);
   paid:=paid+coalesce((state->>'after_seconds')::bigint,(x->>'paid_seconds')::bigint);
   sources:=sources||jsonb_build_array(x||jsonb_build_object('paid_seconds',coalesce((state->>'after_seconds')::bigint,(x->>'paid_seconds')::bigint)));
  end loop;
  after_calc:=people_payroll.calculate(inputs||jsonb_build_object('paid_seconds',paid,'sources',sources),original.inputs->'rules',r.currency_code);
  diff:=people_payroll.correction_difference(before_calc,after_calc);
  insert into people_payroll.corrections(id,tenant_id,legal_entity_id,branch_id,original_calculation_id,employee_id,original_run_id,
   predecessor_id,chain_version,posting_date,currency_code,digest,before_calculation,after_calculation,difference,prepared_by,reason)
  values(cid,p_tenant_id,p_legal_entity_id,p_branch_id,original.id,original.employee_id,r.id,predecessor,seq,(p_payload->>'posting_date')::date,
   r.currency_code,people_payroll.digest(jsonb_build_object('original_calculation_id',original.id,'chain_version',seq,
   'sources',changes,'before',before_calc,'after',after_calc,'posting_date',p_payload->>'posting_date')),before_calc,after_calc,diff,auth.uid(),btrim(p_payload->>'reason'));
  insert into people_payroll.correction_sources(id,tenant_id,legal_entity_id,correction_id,employee_id,seal_id,source_kind,source_id,
   source_digest,before_revision_id,after_revision_id,before_version,before_seconds,after_seconds,original_seconds,impact)
  select(replacement->>'id')::uuid,p_tenant_id,p_legal_entity_id,cid,original.employee_id,(replacement->>'seal_id')::uuid,replacement->>'source_kind',(replacement->>'source_id')::uuid,
   replacement->>'source_digest',(replacement->>'revision_id')::uuid,(replacement->>'after_revision_id')::uuid,(replacement->>'version')::bigint,(replacement->>'paid_seconds')::bigint,
   (replacement->>'after_seconds')::bigint,(replacement->>'original_seconds')::bigint,nullif(replacement->'impact','null'::jsonb) from jsonb_array_elements(changes) replacement;
 else
  select * into c from people_payroll.corrections where id=cid for update;
  before_summary:=people_payroll.correction_summary(cid);
  if c.version<>p_expected_version or c.digest is distinct from p_payload->>'digest' then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_VERSION_CONFLICT';end if;
  if act in('approve','reject') then
   if c.status<>'prepared' then raise exception using errcode='55000',message='PAYROLL_CORRECTION_STATE_INVALID';end if;
   if c.prepared_by=auth.uid() then raise exception using errcode='42501',message='PAYROLL_INDEPENDENT_APPROVAL_REQUIRED';end if;
   if c.chain_version<>seq or c.predecessor_id is distinct from predecessor then raise exception using errcode='40001',message='PAYROLL_CORRECTION_CHAIN_CHANGED';end if;
   update people_payroll.corrections set status=case when act='approve' then 'approved' else 'rejected' end,version=version+1,
    approved_by=auth.uid(),approved_digest=case when act='approve' then digest else null end where id=cid;
  elsif act='post' then
   if c.status<>'approved' or c.approved_digest is distinct from c.digest then raise exception using errcode='55000',message='PAYROLL_CORRECTION_APPROVAL_REQUIRED';end if;
   if c.chain_version<>seq or c.predecessor_id is distinct from predecessor then raise exception using errcode='40001',message='PAYROLL_CORRECTION_CHAIN_CHANGED';end if;
   for src in select * from people_payroll.correction_sources where correction_id=cid order by seal_id loop
    state:=people_payroll.correction_source_state(src.seal_id);
    if(state->>'version')::bigint<>src.before_version or state->>'revision_id'<>src.before_revision_id::text
     or(state->>'paid_seconds')::bigint<>src.before_seconds then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
    perform people_payroll.approved_source(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid);
   end loop;
   select s.* into setting from people_payroll.settings_versions s join people_payroll.run_revisions rv on rv.settings_version_id=s.id where rv.id=original.revision_id;
   v_amount:=(c.difference->>'net')::numeric;
   if v_amount<>0 then
    perform people_payroll.account(p_tenant_id,p_legal_entity_id,setting.net_account_id,'liability',c.currency_code);
    balance:=gen_random_uuid();
    insert into people_payroll.correction_balances values(balance,p_tenant_id,p_legal_entity_id,p_branch_id,cid,c.employee_id,null,'net',setting.net_account_id,c.currency_code,v_amount);
    lines:=lines||jsonb_build_array(jsonb_build_object('account_id',setting.net_account_id,'amount',(-v_amount)::text,'base_amount',(-v_amount)::text,'source_line_id',balance));
   end if;
   for line in select value from jsonb_array_elements(c.difference->'lines') loop
    v_amount:=(line->>'difference')::numeric;
    if v_amount=0 then continue;end if;
    select * into rule from people_payroll.rule_versions where id=(line->>'rule_version_id')::uuid;
    if line->>'classification' in('earning','employer_cost') then
     perform people_payroll.account(p_tenant_id,p_legal_entity_id,rule.expense_account_id,'expense',c.currency_code);
     lines:=lines||jsonb_build_array(jsonb_build_object('account_id',rule.expense_account_id,'amount',v_amount::text,'base_amount',v_amount::text,'source_line_id',cid));
    end if;
    if line->>'classification' in('deduction','employer_cost') then
     perform people_payroll.account(p_tenant_id,p_legal_entity_id,rule.liability_account_id,'liability',c.currency_code);
     balance:=gen_random_uuid();
     insert into people_payroll.correction_balances values(balance,p_tenant_id,p_legal_entity_id,p_branch_id,cid,c.employee_id,rule.id,line->>'classification',rule.liability_account_id,c.currency_code,v_amount);
     lines:=lines||jsonb_build_array(jsonb_build_object('account_id',rule.liability_account_id,'amount',(-v_amount)::text,'base_amount',(-v_amount)::text,'source_line_id',balance));
    end if;
   end loop;
   -- Even a zero-amount correction needs an open date; it never invents a journal.
   perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,c.posting_date);
   if jsonb_array_length(lines)>0 then journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'document_date',c.posting_date,'currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
    lines,'payroll_correction',cid,request,p_command_id);end if;
   insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,recorded_by)
    select tenant_id,legal_entity_id,id,'issue',amount,cid,auth.uid() from people_payroll.correction_balances where correction_id=cid;
   for src in select * from people_payroll.correction_sources where correction_id=cid order by seal_id loop
    state:=people_payroll.correction_source_state(src.seal_id);
    if src.impact is not null then
     operational:=people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid,src.after_revision_id,src.impact,'apply');
    else operational:=jsonb_build_object('claim_id',state->'claim_id','source_id',state->'operational_source_id','source_version',state->'operational_source_version','after',state->'operational_snapshot');end if;
    insert into people_payroll.correction_source_effects(tenant_id,legal_entity_id,correction_id,source_id,seal_id,revision_id,version,seconds,kind,operational_claim_id,operational_source_id,operational_source_version,operational_snapshot)
     values(p_tenant_id,p_legal_entity_id,cid,src.id,src.seal_id,src.after_revision_id,src.before_version+1,src.after_seconds,'apply',
      (operational->>'claim_id')::uuid,(operational->>'source_id')::uuid,(operational->>'source_version')::bigint,operational->'after');
   end loop;
   inputs:=jsonb_build_object('original_calculation_id',original.id,'employee_id',c.employee_id,'employee_name',original.inputs->>'employee_name',
    'employee_code',original.inputs->>'employee_code','start_date',original.inputs->>'start_date','end_date_exclusive',original.inputs->>'end_date_exclusive',
    'posting_date',c.posting_date,'currency_code',c.currency_code,'before',c.before_calculation,'after',c.after_calculation,'difference',c.difference,'synthetic',true);
   insert into people_payroll.correction_payslips values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,p_branch_id,cid,c.employee_id,inputs,people_payroll.digest(inputs),clock_timestamp());
   update people_payroll.corrections set status='posted',posted_journal_id=journal,version=version+1 where id=cid;
  else
   if c.status<>'posted' then raise exception using errcode='55000',message='PAYROLL_CORRECTION_STATE_INVALID';end if;
   if exists(select 1 from people_payroll.corrections later join people_payroll.correction_events le on le.correction_id=later.id and le.action='post'
    where later.original_calculation_id=c.original_calculation_id and later.status='posted' and
    le.chain_sequence>(select chain_sequence from people_payroll.correction_events where correction_id=cid and action='post')) then
    raise exception using errcode='55000',message='PAYROLL_LATER_CORRECTION_BLOCKS_REVERSAL';end if;
   if exists(select 1 from people_payroll.correction_balances b where b.correction_id=cid and
    b.amount<>(select coalesce(sum(amount),0) from people_payroll.correction_balance_effects where balance_id=b.id)) then
    raise exception using errcode='55000',message='PAYROLL_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL';end if;
   if coalesce(p_payload->>'posting_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or(p_payload->>'posting_date')::date<c.posting_date then
    raise exception using errcode='22023',message='PAYROLL_OFFCYCLE_DATE_INVALID';end if;
   perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,(p_payload->>'posting_date')::date);
   if c.posted_journal_id is not null then
    select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,'amount',(transaction_credit-transaction_debit)::text,
     'base_amount',(base_credit-base_debit)::text) order by line_number) into lines from finance.journal_lines
     where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=c.posted_journal_id;
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',p_payload->>'posting_date','currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
     lines,'payroll_correction_reverse',cid,request,p_command_id);
   end if;
   insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,reversal_of,recorded_by)
    select tenant_id,legal_entity_id,balance_id,'correction_reverse',-amount,cid,id,auth.uid() from people_payroll.correction_balance_effects where source_id=cid and kind='issue';
   for src in select * from people_payroll.correction_sources where correction_id=cid order by seal_id loop
    state:=people_payroll.correction_source_state(src.seal_id);replacement_id:=gen_random_uuid();
    if src.impact is not null then
     perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,src.source_kind,true);
     operational:=people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid,replacement_id,src.impact,'reverse');
    else operational:=jsonb_build_object('claim_id',state->'claim_id','source_id',state->'operational_source_id','source_version',state->'operational_source_version','after',state->'operational_snapshot');end if;
    insert into people_payroll.correction_source_effects(tenant_id,legal_entity_id,correction_id,source_id,seal_id,revision_id,version,seconds,kind,reversal_of,operational_claim_id,operational_source_id,operational_source_version,operational_snapshot)
     values(p_tenant_id,p_legal_entity_id,cid,src.id,src.seal_id,replacement_id,(state->>'version')::bigint+1,src.before_seconds,'reverse',
      (select id from people_payroll.correction_source_effects where source_id=src.id and kind='apply'),(operational->>'claim_id')::uuid,
      (operational->>'source_id')::uuid,(operational->>'source_version')::bigint,operational->'after');
   end loop;
   update people_payroll.corrections set status='reversed',reversal_journal_id=journal,version=version+1 where id=cid;
  end if;
 end if;
 after_summary:=people_payroll.correction_summary(cid);
 insert into people_payroll.correction_events(tenant_id,legal_entity_id,branch_id,correction_id,original_calculation_id,action,version,chain_sequence,actor_id,reason,command_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,cid,original.id,act,(after_summary->>'version')::bigint,
  case when act in('post','reverse') then seq+1 end,auth.uid(),btrim(p_payload->>'reason'),p_command_id);
 return core.wave3_finish_command(p_tenant_id,'people.payroll.correction.'||act,p_command_id,'people.payroll.correction',cid,p_idempotency_key,hash,
  before_summary,after_summary,p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object('action',act),p_request_id=>request);
end $$;

create function people_payroll.original_run_correction_guard() returns trigger language plpgsql set search_path='' as $$begin
 if new.status='reversed' and old.status='posted' and exists(select 1 from people_payroll.corrections where original_run_id=old.id and status='posted') then
  raise exception using errcode='55000',message='PAYROLL_ACTIVE_CORRECTION_BLOCKS_REVERSAL';end if;return new;end $$;
create trigger payroll_original_correction_guard before update on people_payroll.runs for each row execute function people_payroll.original_run_correction_guard();

create function api.people_payroll_correction_settlement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare act text:=p_payload->>'action';sid uuid;cid uuid;c people_payroll.corrections%rowtype;s people_payroll.correction_settlements%rowtype;
 bank finance.cash_bank_accounts%rowtype;b people_payroll.correction_balances%rowtype;
 x jsonb;lines jsonb:='[]';v_amount numeric;outstanding numeric;total numeric:=0;signum integer;seen uuid[]:='{}';
 hash text;replay jsonb;journal uuid;request uuid:=gen_random_uuid();answer jsonb;posting date;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.settle',true);
 if act is null or act not in('record','reverse') or p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or p_expected_version is null or p_expected_version not between 0 and 9007199254740991 or jsonb_typeof(p_payload)<>'object'
  or octet_length(p_payload::text)>65536 or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000
  or coalesce(p_payload->>'posting_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'correction_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(case when act='record' then
  array['action','id','correction_id','posting_date','direction','bank_id','bank_version','allocations','evidence_reference','reason']
  else array['action','id','correction_id','posting_date','reason'] end)) then
  raise exception using errcode='22023',message='PAYROLL_CORRECTION_SETTLEMENT_INVALID';end if;
 sid:=(p_payload->>'id')::uuid;cid:=(p_payload->>'correction_id')::uuid;posting:=(p_payload->>'posting_date')::date;
 hash:=core.wave3_request_hash('people.payroll.correction_settlement.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'people.payroll.correction_settlement.'||act,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 select * into c from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=cid;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_NOT_FOUND';end if;
 perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=c.employee_id for update;
 select * into c from people_payroll.corrections where id=cid for update;
 if c.status<>'posted' or posting<c.posting_date then raise exception using errcode='55000',message='PAYROLL_CORRECTION_SETTLEMENT_STATE_INVALID';end if;
 if act='record' then
  if p_expected_version<>0 or p_payload->>'direction' not in('pay','recover') or p_payload->>'direction' is null
   or length(btrim(coalesce(p_payload->>'evidence_reference',''))) not between 1 and 160
   or jsonb_typeof(p_payload->'bank_version')<>'number' or(p_payload->>'bank_version')::bigint not between 1 and 9007199254740991
   or jsonb_typeof(p_payload->'allocations')<>'array' or jsonb_array_length(p_payload->'allocations') not between 1 and 200 then
   raise exception using errcode='22023',message='PAYROLL_CORRECTION_SETTLEMENT_INVALID';end if;
  signum:=case when p_payload->>'direction'='pay' then 1 else -1 end;
  select * into bank from finance.cash_bank_accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and id=(p_payload->>'bank_id')::uuid and status='active' and currency_code=c.currency_code for share;
  if bank.id is null then raise exception using errcode='55000',message='PAYROLL_BANK_PROVIDER_REQUIRED';end if;
  if bank.version<>(p_payload->>'bank_version')::bigint then raise exception using errcode='40001',message='PAYROLL_BANK_VERSION_CONFLICT';end if;
  perform finance.flow_account(p_tenant_id,p_legal_entity_id,bank.account_id,'asset',c.currency_code);
  for x in select value from jsonb_array_elements(p_payload->'allocations') order by value->>'balance_id' loop
   if jsonb_typeof(x)<>'object' or(select count(*) from jsonb_object_keys(x))<>2 or not(x ?& array['balance_id','amount'])
    or(x->>'balance_id')::uuid=any(seen) then raise exception using errcode='22023',message='PAYROLL_CORRECTION_SETTLEMENT_INVALID';end if;
   seen:=array_append(seen,(x->>'balance_id')::uuid);
   select * into b from people_payroll.correction_balances where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
    and correction_id=cid and id=(x->>'balance_id')::uuid for update;
   if b.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_BALANCE_NOT_FOUND';end if;
   v_amount:=people_payroll.amount(x->'amount');
   select coalesce(sum(amount),0) into outstanding from people_payroll.correction_balance_effects where balance_id=b.id;
   if v_amount<=0 or outstanding*signum<=0 or v_amount>outstanding*signum then
    raise exception using errcode='55000',message='PAYROLL_SETTLEMENT_EXCEEDS_DUE';end if;
   perform people_payroll.account(p_tenant_id,p_legal_entity_id,b.account_id,'liability',c.currency_code);
   total:=total+v_amount*signum;
   lines:=lines||jsonb_build_array(jsonb_build_object('account_id',b.account_id,'amount',(v_amount*signum)::text,'base_amount',(v_amount*signum)::text,'source_line_id',b.id));
  end loop;
  if abs(total)>99999999999999.999999 then raise exception using errcode='22023',message='PAYROLL_AMOUNT_OVERFLOW';end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank.account_id,'amount',(-total)::text,'base_amount',(-total)::text,'source_line_id',sid));
  journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
   'document_date',posting,'currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
   lines,'payroll_correction_settlement',sid,request,p_command_id);
  insert into people_payroll.correction_settlements(id,tenant_id,legal_entity_id,branch_id,correction_id,bank_id,bank_account_id,bank_version,currency_code,
   posting_date,direction,evidence_reference,reason,journal_id,recorded_by)
  values(sid,p_tenant_id,p_legal_entity_id,p_branch_id,cid,bank.id,bank.account_id,bank.version,c.currency_code,posting,p_payload->>'direction',
   btrim(p_payload->>'evidence_reference'),btrim(p_payload->>'reason'),journal,auth.uid());
  insert into people_payroll.correction_settlement_allocations select p_tenant_id,p_legal_entity_id,sid,(allocation->>'balance_id')::uuid,people_payroll.amount(allocation->'amount')
   from jsonb_array_elements(p_payload->'allocations') allocation;
  insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,recorded_by)
   select p_tenant_id,p_legal_entity_id,balance_id,'settle',-amount*signum,sid,auth.uid() from people_payroll.correction_settlement_allocations where settlement_id=sid;
  answer:=jsonb_build_object('id',sid,'correction_id',cid,'status','recorded','version',1,'journal_id',journal);
 else
  select * into s from people_payroll.correction_settlements where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and correction_id=cid and id=sid for update;
  if s.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_SETTLEMENT_NOT_FOUND';end if;
  if s.version<>p_expected_version then raise exception using errcode='40001',message='PAYROLL_CORRECTION_VERSION_CONFLICT';end if;
  if s.status<>'recorded' then raise exception using errcode='55000',message='PAYROLL_SETTLEMENT_ALREADY_REVERSED';end if;
  if posting<s.posting_date then raise exception using errcode='22023',message='PAYROLL_OFFCYCLE_DATE_INVALID';end if;
  select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,'amount',(transaction_credit-transaction_debit)::text,
   'base_amount',(base_credit-base_debit)::text) order by line_number) into lines from finance.journal_lines
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=s.journal_id;
  journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
   'document_date',posting,'currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
   lines,'payroll_correction_settlement_reverse',sid,request,p_command_id);
  insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,reversal_of,recorded_by)
   select tenant_id,legal_entity_id,balance_id,'settlement_reverse',-amount,sid,id,auth.uid() from people_payroll.correction_balance_effects where source_id=sid and kind='settle';
  update people_payroll.correction_settlements set status='reversed',version=version+1,reversal_journal_id=journal where id=sid;
  answer:=jsonb_build_object('id',sid,'correction_id',cid,'status','reversed','version',s.version+1,'reversal_journal_id',journal);
 end if;
 return core.wave3_finish_command(p_tenant_id,'people.payroll.correction_settlement.'||act,p_command_id,'people.payroll.correction_settlement',sid,p_idempotency_key,hash,
  '{}',answer||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id),p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('action',act),p_request_id=>request);end $$;

create function api.people_payroll_correction_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare cap text;result jsonb;begin
 cap:=case p_action when 'prepare' then 'people.payroll.correction.prepare' when 'approve' then 'people.payroll.correction.approve'
  when 'reject' then 'people.payroll.correction.approve' when 'post' then 'people.payroll.post' when 'reverse' then 'people.payroll.reverse'
  when 'settlement.record' then 'people.payroll.settle' when 'settlement.reverse' then 'people.payroll.settle' end;
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 select response into result from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and actor_id=auth.uid() and command_id=p_command_id
  and command_name=case when p_action like 'settlement.%' then 'people.payroll.correction_settlement.'||split_part(p_action,'.',2)
   else 'people.payroll.correction.'||p_action end;
 if result is not null and (result->'entity'->>'legal_entity_id' is distinct from p_legal_entity_id::text
  or result->'entity'->>'branch_id' is distinct from p_branch_id::text) then raise exception using errcode='42501',message='PAYROLL_RECEIPT_SCOPE_DENIED';end if;
 return result;end $$;

revoke all on all functions in schema people_payroll from public,anon,authenticated;
revoke all on function api.people_payroll_correction_authorize(uuid,uuid,uuid,text),
 api.people_payroll_correction_originals(uuid,uuid,uuid,uuid),api.people_payroll_correction_sources(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_corrections(uuid,uuid,uuid,uuid),api.people_payroll_correction_detail(uuid,uuid,uuid,uuid,text,uuid),
 api.people_payroll_correction_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_settlement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.people_payroll_correction_authorize(uuid,uuid,uuid,text),
 api.people_payroll_correction_originals(uuid,uuid,uuid,uuid),api.people_payroll_correction_sources(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_corrections(uuid,uuid,uuid,uuid),api.people_payroll_correction_detail(uuid,uuid,uuid,uuid,text,uuid),
 api.people_payroll_correction_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_settlement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function people_payroll.freeze(t uuid,e uuid,b uuid,employee uuid,period_start date,period_end date,currency text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare assignment people.employment_assignments%rowtype;org people.organization_assignments%rowtype;
 calendar people.work_calendar_versions%rowtype;employee_row people.employees%rowtype;
 eligible_start date;eligible_end date;rules jsonb;facts jsonb;days jsonb:='[]';slot jsonb;day date;
 local_start timestamp;local_end timestamp;utc_start timestamptz;utc_end timestamptz;
 planned bigint:=0;paid bigint:=0;cnt integer;begin
 select * into employee_row from people.employees where tenant_id=t and legal_entity_id=e and id=employee;
 select count(*) into cnt from people.employment_assignments a where tenant_id=t and legal_entity_id=e
  and branch_id=b and employee_id=employee and daterange(a.start_date,a.end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 if cnt<>1 then raise exception using errcode='55000',message='PAYROLL_SINGLE_EMPLOYMENT_SLICE_REQUIRED';end if;
 select * into assignment from people.employment_assignments a where tenant_id=t and legal_entity_id=e
  and branch_id=b and employee_id=employee and daterange(a.start_date,a.end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 eligible_start:=greatest(period_start,assignment.start_date);eligible_end:=least(period_end,assignment.end_date_exclusive);
 select * into org from people.organization_assignments o where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and superseded_at is null and daterange(o.start_date,o.end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)');
 if org.id is null then raise exception using errcode='55000',message='PAYROLL_ORGANIZATION_COVERAGE_REQUIRED';end if;
 select * into calendar from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=org.calendar_version_id
  and daterange(start_date,end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)');
 if calendar.id is null then raise exception using errcode='55000',message='PAYROLL_CALENDAR_COVERAGE_REQUIRED';end if;
 select count(*) into cnt from people_payroll.component_assignments a where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and daterange(start_date,end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 if cnt not between 1 and 100 then raise exception using errcode='55000',message='PAYROLL_COMPONENT_BOUND_REQUIRED';end if;
 select coalesce(jsonb_agg(people_payroll.rule_payload(r.id)||jsonb_build_object('assignment_id',a.id) order by c.code),'[]'::jsonb) into rules
 from people_payroll.component_assignments a join people_payroll.components c on c.id=a.component_id
 join people_payroll.rule_versions r on r.component_id=a.component_id
 where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and a.employee_id=employee
  and daterange(a.start_date,a.end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)')
  and daterange(r.start_date,r.end_date_exclusive,'[)') @> daterange(period_start,period_end,'[)');
 if jsonb_array_length(rules)<>cnt then raise exception using errcode='55000',message='PAYROLL_RULE_COVERAGE_REQUIRED';end if;
 for day in select generate_series(eligible_start::timestamp,(eligible_end-1)::timestamp,interval '1 day')::date loop
  if exists(select 1 from jsonb_array_elements(calendar.date_overrides) x where x->>'date'=day::text and not(x->>'is_working_day')::boolean) then continue;end if;
  for slot in select value from jsonb_array_elements(calendar.weekly_intervals) where (value->>'day_of_week')::integer=extract(isodow from day)::integer loop
   local_start:=day::timestamp+(slot->>'start_minute')::integer*interval '1 minute';
   local_end:=day::timestamp+(slot->>'end_day_offset')::integer*interval '1 day'+(slot->>'end_minute')::integer*interval '1 minute';
   utc_start:=people.resolve_local_instant(calendar.timezone,local_start);
   utc_end:=people.resolve_local_instant(calendar.timezone,local_end);
   if local_end>eligible_end::timestamp then raise exception using errcode='55000',message='PAYROLL_OVERNIGHT_SLICE_REQUIRED';end if;
   planned:=planned+extract(epoch from utc_end-utc_start)::bigint;
   days:=days||jsonb_build_array(jsonb_build_object('date',day,'start_local',local_start,'end_local',local_end,
    'start_utc',utc_start,'end_utc',utc_end,'seconds',extract(epoch from utc_end-utc_start)::bigint));
   if jsonb_array_length(days)>2000 then raise exception using errcode='55000',message='PAYROLL_PLANNED_SLOT_BOUND_REQUIRED';end if;
  end loop;
 end loop;
 -- Any unresolved or boundary-straddling claim is explicit; never silently truncate.
 utc_start:=people.resolve_local_instant(calendar.timezone,eligible_start::timestamp);
 utc_end:=people.resolve_local_instant(calendar.timezone,eligible_end::timestamp);
 if exists(select 1 from people.work_claims w where w.tenant_id=t and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee
  and w.active and tstzrange(w.start_utc,w.end_utc,'[)') && tstzrange(utc_start,utc_end,'[)')
  and (w.start_utc<utc_start or w.end_utc>utc_end)) then
  raise exception using errcode='55000',message='PAYROLL_WORK_BOUNDARY_SLICE_REQUIRED';end if;
 select count(*) into cnt from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and active and start_utc>=utc_start and end_utc<=utc_end;
 if cnt>2000 then raise exception using errcode='55000',message='PAYROLL_SOURCE_BOUND_REQUIRED';end if;
 for facts in select jsonb_build_array(people_payroll.approved_source(t,e,b,employee,id)) from people.work_claims
  where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and active and start_utc>=utc_start and end_utc<=utc_end loop
  null;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('claim_id',w.id,'source_kind',w.source_kind,'source_id',w.source_id,
  'source_version',(provider.body->>'source_version')::bigint,
  'calendar_version_id',w.calendar_version_id,'start_utc',w.start_utc,'end_utc',w.end_utc,
  'gross_seconds',w.gross_seconds,'break_seconds',w.break_seconds,'paid_seconds',(provider.body->>'paid_seconds')::bigint,
  'leave_policy_version_id',lr.policy_version_id,'leave_charge_seconds',lr.charge_seconds,'unpaid_seconds',lr.unpaid_seconds,
  'leave_effects',case when w.source_kind='leave' then(select coalesce(jsonb_agg(jsonb_build_object('id',le.id,'grant_id',le.grant_id,
   'seconds',le.seconds,'reversal_of',le.reversal_of) order by le.id),'[]'::jsonb) from people.leave_effects le where le.request_id=lr.id) end)
  order by w.id),'[]'::jsonb) into facts from people.work_claims w
  cross join lateral(select people_payroll.approved_source(t,e,b,employee,w.id) body) provider
  left join people.leave_requests lr on lr.active_claim_id=w.id and w.source_kind='leave'
  where w.tenant_id=t and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee and w.active
   and w.start_utc>=utc_start and w.end_utc<=utc_end;
 select coalesce(sum((x->>'paid_seconds')::bigint),0) into paid from jsonb_array_elements(facts) x;
 return jsonb_build_object('employee_id',employee,'employee_version',employee_row.version,'employee_code',employee_row.code,
  'employee_name',employee_row.display_name,'employment_assignment',jsonb_build_object('id',assignment.id,'spell_id',assignment.spell_id,
   'start_date',assignment.start_date,'end_date_exclusive',assignment.end_date_exclusive,'type',assignment.employment_type,'job_title',assignment.job_title),
  'organization_assignment_id',org.id,'calendar_version_id',calendar.id,'timezone',calendar.timezone,
  'start_date',period_start,'end_date_exclusive',period_end,'eligible_start',eligible_start,'eligible_end_exclusive',eligible_end,
  'period_days',period_end-period_start,'eligible_days',eligible_end-eligible_start,
  'paid_seconds',paid,'planned_seconds',planned,'planned_slots',days,'sources',facts,'rules',rules);
end $$;


revoke all on function people_payroll.freeze(uuid,uuid,uuid,uuid,date,date,text) from public,anon,authenticated;

-- Trusted operational impact adapters. Ordinary source commands continue to use
-- revoke_work_claim and its seal guard; this path requires an approved linked
-- correction and appends a new claim, never rewriting sealed geometry.
create function people_payroll.replace_claim(t uuid,e uuid,b uuid,employee uuid,old_claim uuid,
 kind text,source_id uuid,calendar uuid,p_start timestamptz,p_end timestamptz,p_breaks jsonb,correction_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c people_payroll.corrections%rowtype;w people.work_claims%rowtype;new_claim uuid;new_w people.work_claims%rowtype;begin
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform 1 from people.employees where tenant_id=t and legal_entity_id=e and id=employee for update;
 select * into c from people_payroll.corrections where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and id=correction_id and status in('approved','posted');
 if c.id is null or not exists(select 1 from people_payroll.correction_sources s where s.correction_id=c.id
  and s.source_kind=kind and s.impact is not null
  and (people_payroll.correction_source_state(s.seal_id)->>'claim_id')::uuid is not distinct from old_claim) then
  raise exception using errcode='42501',message='PAYROLL_APPROVED_LINKED_IMPACT_REQUIRED';end if;
 if old_claim is not null then
  select * into w from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and id=old_claim and source_kind=kind and active for update;
  if w.id is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if exists(select 1 from people.work_allocations where claim_id=w.id and active) then
   raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
  update people.work_claims set active=false,revoked_at=clock_timestamp() where id=w.id;
  update people.work_claim_segments set active=false where claim_id=w.id and active;
 end if;
 if source_id is null then return null;end if;
 new_claim:=people.make_work_claim(t,e,b,employee,kind,source_id,p_start,p_end,p_breaks,calendar,auth.uid());
 select * into new_w from people.work_claims where id=new_claim;
 insert into people.work_input_seals(tenant_id,legal_entity_id,employee_id,run_id,claim_id,source_version,seconds,digest)
  values(t,e,employee,c.original_run_id,new_claim,1,new_w.payable_seconds,people_payroll.digest(to_jsonb(new_w)));
 return new_claim;
end $$;

create function people_payroll.source_impact(t uuid,e uuid,b uuid,employee uuid,claim uuid,
 revision uuid,proposal jsonb,p_mode text) returns jsonb language plpgsql security definer set search_path='' as $$
declare w people.work_claims%rowtype;a people.attendance_entries%rowtype;r people.attendance_revisions%rowtype;
 l people.leave_requests%rowtype;account people.leave_accounts%rowtype;calendar people.work_calendar_versions%rowtype;
 body jsonb;before_body jsonb;after_body jsonb;target jsonb;result jsonb;effect jsonb;effects jsonb;
 start_local timestamp;end_local timestamp;start_utc timestamptz;end_utc timestamptz;break_seconds bigint;
 new_claim uuid;source_kind text:=proposal->>'source_kind';allocation people.work_allocations%rowtype;
 allocation_body jsonb;allocation_effects jsonb:='[]';
begin
 if p_mode not in('read','validate','apply','reverse') or revision is null then raise exception using errcode='22023',message='PAYROLL_SOURCE_IMPACT_INVALID';end if;
 select * into w from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and id=claim and active;
 source_kind:=coalesce(w.source_kind,source_kind);
 if source_kind in('project','service') then
  if to_regprocedure(source_kind||'s.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)') is not null and source_kind='project' then
   execute 'select projects.payroll_impact($1,$2,$3,$4,$5,$6,$7,$8)' into result using t,e,b,employee,claim,revision,proposal,p_mode;
  elsif source_kind='service' and to_regprocedure('service.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)') is not null then
   execute 'select service.payroll_impact($1,$2,$3,$4,$5,$6,$7,$8)' into result using t,e,b,employee,claim,revision,proposal,p_mode;
  else raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';end if;
  return result;
 end if;
 if source_kind='attendance' then
  select * into a from people.attendance_entries where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and active_claim_id=claim and status='approved';
  select * into r from people.attendance_revisions where id=a.current_revision_id;
  if a.id is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  before_body:=to_jsonb(r)||jsonb_build_object('entry_version',a.version,'claim_id',claim);
  if p_mode='read' then return jsonb_build_object('before',before_body,'source_id',r.id,'source_version',a.version,'paid_seconds',r.payable_seconds,'claim_id',claim);end if;
  if p_mode<>'reverse' and (a.version is distinct from(proposal->>'expected_source_version')::bigint
   or proposal->>'mode' is distinct from 'geometry') then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  target:=case when p_mode='reverse' then proposal->'before' else proposal end;
  if p_mode='apply' and proposal->'before' is distinct from before_body then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  select * into calendar from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=r.calendar_version_id;
  start_local:=(target->>'start_local')::timestamp;end_local:=(target->>'end_local')::timestamp;
  if extract(second from start_local)%1<>0 or extract(second from end_local)%1<>0 then raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
  perform people.work_local_coverage(t,e,b,employee,calendar.id,start_local,end_local);
  start_utc:=people.resolve_local_instant(calendar.timezone,start_local,(target->>'start_offset_seconds')::integer);
  end_utc:=people.resolve_local_instant(calendar.timezone,end_local,(target->>'end_offset_seconds')::integer);
  break_seconds:=people.work_break_seconds(start_utc,end_utc,target->'breaks');
  after_body:=jsonb_build_object('start_local',start_local,'end_local',end_local,'start_offset_seconds',(target->>'start_offset_seconds')::integer,
   'end_offset_seconds',(target->>'end_offset_seconds')::integer,'start_utc',start_utc,'end_utc',end_utc,'breaks',target->'breaks',
   'gross_seconds',extract(epoch from end_utc-start_utc)::bigint,'break_seconds',break_seconds,
   'payable_seconds',extract(epoch from end_utc-start_utc)::bigint-break_seconds,'calendar_version_id',calendar.id);
  for allocation in select * from people.work_allocations where claim_id=claim and active order by id loop
   if to_regprocedure(case allocation.source_kind when 'project' then 'projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' else 'service.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' end) is null then
    raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
   execute case allocation.source_kind when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
    into allocation_body using t,e,b,employee,allocation.id,revision,proposal||jsonb_build_object('attendance_after',after_body),case when p_mode in('apply','reverse') then 'validate' else p_mode end;
   allocation_effects:=allocation_effects||jsonb_build_array(jsonb_build_object('allocation_id',allocation.id,'source_kind',allocation.source_kind,'impact',allocation_body));
  end loop;
  after_body:=after_body||jsonb_build_object('allocation_impacts',allocation_effects);
  if p_mode in('apply','reverse') then
   if p_mode='apply' and after_body is distinct from proposal->'after' then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   -- Module hooks relinquish old allocations before the common claim replacement.
   for effect in select value from jsonb_array_elements(allocation_effects) loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,proposal||jsonb_build_object('attendance_after',after_body,'allocation_impact',effect->'impact'),'release';
   end loop;
   new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'attendance',revision,calendar.id,start_utc,end_utc,target->'breaks',(proposal->>'correction_id')::uuid);
   insert into people.attendance_revisions(id,tenant_id,legal_entity_id,branch_id,employee_id,entry_id,version,calendar_version_id,
    start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,breaks,gross_seconds,break_seconds,payable_seconds,
    reason,supersedes_revision_id,recorded_by)
   values(revision,t,e,b,employee,a.id,a.version+1,calendar.id,start_local,(target->>'start_offset_seconds')::integer,end_local,
    (target->>'end_offset_seconds')::integer,start_utc,end_utc,target->'breaks',extract(epoch from end_utc-start_utc)::bigint,
    break_seconds,extract(epoch from end_utc-start_utc)::bigint-break_seconds,'Linked sealed payroll source correction',r.id,auth.uid());
   update people.attendance_entries set current_revision_id=revision,active_claim_id=new_claim,version=version+1,decided_by=auth.uid() where id=a.id;
   for effect in select value from jsonb_array_elements(allocation_effects) loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,proposal||jsonb_build_object('attendance_after',after_body,'new_claim_id',new_claim,'allocation_impact',effect->'impact'),p_mode;
   end loop;
  else new_claim:=claim;end if;
  return jsonb_build_object('before',before_body,'after',after_body,'source_id',revision,'source_version',a.version+1,
   'paid_seconds',extract(epoch from end_utc-start_utc)::bigint-break_seconds,'claim_id',new_claim);
 elsif source_kind='leave' then
  select * into l from people.leave_requests where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and (active_claim_id=claim or (p_mode='reverse' and id=(proposal->'before'->>'id')::uuid));
  if l.id is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  select * into account from people.leave_accounts where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id for update;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into effects from people.leave_effects x where x.request_id=l.id
   and x.seconds<0 and not exists(select 1 from people.leave_effects y where y.reversal_of=x.id);
  before_body:=to_jsonb(l)||jsonb_build_object('balance_version',account.version,'effects',effects);
  if p_mode='read' then return jsonb_build_object('before',before_body,'source_id',w.source_id,'source_version',l.version,'paid_seconds',l.charge_seconds-l.unpaid_seconds,'claim_id',claim);end if;
  if p_mode<>'reverse' and (l.status<>'approved' or l.version is distinct from(proposal->>'expected_source_version')::bigint
   or proposal->>'mode' is distinct from 'cancel_leave') then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if p_mode='apply' and proposal->'before' is distinct from before_body then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  after_body:=jsonb_build_object('status','cancelled','request_id',l.id,'original_effects',effects);
  if p_mode='apply' then
   new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'leave',null,l.calendar_version_id,l.start_utc,l.end_utc,'[]',(proposal->>'correction_id')::uuid);
   insert into people.leave_effects(tenant_id,legal_entity_id,employee_id,policy_id,grant_id,request_id,effective_date,seconds,reversal_of,recorded_by)
    select tenant_id,legal_entity_id,employee_id,policy_id,grant_id,request_id,(clock_timestamp() at time zone 'UTC')::date,-seconds,id,auth.uid()
    from people.leave_effects x where x.request_id=l.id and x.seconds<0 and not exists(select 1 from people.leave_effects y where y.reversal_of=x.id);
   update people.leave_requests set status='cancelled',active_claim_id=null,version=version+1,decided_by=auth.uid() where id=l.id;
   update people.leave_accounts set version=version+1 where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id;
  elsif p_mode='reverse' then
   if l.status<>'cancelled' then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   for effect in select value from jsonb_array_elements(proposal->'before'->'effects') loop
    if not exists(select 1 from people.leave_grants g where g.id=(effect->>'grant_id')::uuid and g.tenant_id=t and g.legal_entity_id=e and g.employee_id=employee
     and g.seconds+coalesce((select sum(x.seconds) from people.leave_effects x where x.grant_id=g.id),0)>=-(effect->>'seconds')::bigint) then
     raise exception using errcode='55000',message='LEAVE_ORIGINAL_BALANCE_IMPACT_REQUIRED';end if;
    insert into people.leave_effects(tenant_id,legal_entity_id,employee_id,policy_id,grant_id,request_id,effective_date,seconds,recorded_by)
     values(t,e,employee,l.policy_id,(effect->>'grant_id')::uuid,l.id,(effect->>'effective_date')::date,(effect->>'seconds')::bigint,auth.uid());
   end loop;
   new_claim:=people_payroll.replace_claim(t,e,b,employee,null,'leave',revision,l.calendar_version_id,l.start_utc,l.end_utc,'[]',(proposal->>'correction_id')::uuid);
   update people.leave_requests set status='approved',active_claim_id=new_claim,version=version+1,decided_by=auth.uid() where id=l.id;
   update people.leave_accounts set version=version+1 where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id;
   after_body:=proposal->'before';
  else new_claim:=claim;end if;
  return jsonb_build_object('before',before_body,'after',after_body,'source_id',case when p_mode='reverse' then revision else l.id end,
   'source_version',l.version+1,'paid_seconds',case when p_mode='reverse' then l.charge_seconds-l.unpaid_seconds else 0 end,'claim_id',new_claim);
 end if;
 raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';
end $$;
revoke all on function people_payroll.replace_claim(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,timestamptz,timestamptz,jsonb,uuid),
 people_payroll.source_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text) from public,anon,authenticated;

reset role;
insert into payroll_assertions select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='people_payroll' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity),24,'nine correction tables forced RLS');
insert into payroll_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='people_payroll'
 and c.relkind='r' and has_table_privilege('authenticated',c.oid,'SELECT')),'all correction base-table reads denied');
insert into payroll_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='people_payroll'
 and has_function_privilege('authenticated',p.oid,'EXECUTE')),'all trusted correction helpers denied');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p
where p.code in('people.payroll.correction.prepare','people.payroll.correction.approve','people.payroll.post') on conflict do nothing;
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,
 role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('org.correction.manager'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),s.id,
 pg_temp.wid('department'),pg_temp.wid('calendar-version'),'Synthetic correction subject',pg_temp.wdate()-10,pg_temp.wdate()+400,
 'Synthetic correction fixture',pg_temp.wid('creator') from people.employment_spells s where s.employee_id=pg_temp.wid('manager');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pc(pg_temp.publish('CORRHOURS','earning','100','wages',null,'hourly'),0,'corr.rule');
select pg_temp.pc(jsonb_build_object('action','assign','id',pg_temp.wid('corr.assign'),'employee_id',pg_temp.wid('manager'),
 'component_id',pg_temp.wid('component.CORRHOURS'),'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,'reason','Synthetic hourly'),0,'corr.assign');
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.time.create'),pg_temp.wid('corr.time.create'),now(),
 jsonb_build_object('action','create','id',pg_temp.wid('corr.attendance'),'employee_id',pg_temp.wid('manager'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),'end_local',to_char(pg_temp.wdate()::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,'reason','Synthetic time'),0);
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.time.submit'),pg_temp.wid('corr.time.submit'),now(),
 jsonb_build_object('action','submit','id',pg_temp.wid('corr.attendance'),'employee_id',pg_temp.wid('manager'),'reason','Synthetic time'),1);
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select api.people_attendance_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.time.approve'),pg_temp.wid('corr.time.approve'),now(),
 jsonb_build_object('action','approve','id',pg_temp.wid('corr.attendance'),'employee_id',pg_temp.wid('manager'),'reason','Synthetic time'),2);
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_create('corr.original')||jsonb_build_object('employee_ids',jsonb_build_array(pg_temp.wid('manager'))),0,'corr.original.create');
select pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('corr.original'),'reason','Synthetic freeze'),1,'corr.original.prepare');
select pg_temp.pcmd(pg_temp.run_action('submit','corr.original'),2,'corr.original.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('approve','corr.original'),3,'corr.original.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('post','corr.original'),4,'corr.original.post');
reset role;
create temporary table correction_client_samples(name text primary key,response jsonb);
grant select,insert on correction_client_samples to authenticated;
create function pg_temp.correction_prepare(p_seconds bigint,key text default 'corr.one') returns jsonb language sql security definer as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid(key),'original_calculation_id',c.id,'posting_date',pg_temp.wdate()+1,
  'reason','Synthetic eligibility correction','replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,
  'before_revision_id',people_payroll.correction_source_state(s.id)->>'revision_id','expected_version',
  (people_payroll.correction_source_state(s.id)->>'version')::bigint,'paid_seconds',p_seconds)))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 where c.run_id=pg_temp.wid('corr.original') $$;
create function pg_temp.correction_action(act text,key text default 'corr.one') returns jsonb language sql security definer as $$
 select jsonb_build_object('action',act,'id',id,'digest',digest,'reason','Synthetic decision')||
 case when act='reverse' then jsonb_build_object('posting_date',pg_temp.wdate()+2) else '{}'::jsonb end from people_payroll.corrections where id=pg_temp.wid(key) $$;
create function pg_temp.cc(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_payroll_correction_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
create function pg_temp.cdetail(section text,key text default 'corr.one') returns jsonb language sql as $$
 select api.people_payroll_correction_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),section) $$;
create function pg_temp.csettle(p_amount text,direction text default 'recover') returns jsonb language sql security definer as $$
 select jsonb_build_object('action','record','id',pg_temp.wid('corr.settlement'),'correction_id',pg_temp.wid('corr.one'),
  'posting_date',pg_temp.wdate()+1,'bank_id',pg_temp.wid('pay.bank.record'),'bank_version',1,'direction',direction,
  'evidence_reference','SYNTHETIC-CORR-001','reason','Synthetic recorded recovery','allocations',
  jsonb_build_array(jsonb_build_object('balance_id',id,'amount',p_amount))) from people_payroll.correction_balances where correction_id=pg_temp.wid('corr.one') and kind='net' $$;
create function pg_temp.cs(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_payroll_correction_settlement(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
select pg_temp.wactor('creator','aal1');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.lowaal')$q$,'42501',null,'corrections need MFA');
reset role;select pg_temp.wactor('reader');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select api.people_payroll_corrections(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,'42501',null,'directory capability never reveals corrections');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(3601),0,'corr.excess')$q$,'22023','PAYROLL_CORRECTION_ELIGIBILITY_INVALID','eligibility cannot invent new worked seconds');
insert into correction_client_samples values('prepared',pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.prepare'));
insert into payroll_assertions select is(pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.prepare'),(select response from correction_client_samples where name='prepared'),'prepare exact replay');
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(1800)||'{"reason":"changed"}',0,'corr.prepare')$q$,'22023','IDEMPOTENCY_MISMATCH','changed correction body cannot reuse key');
insert into payroll_assertions select is(pg_temp.cdetail('calculation')->'items'->0->'difference'->>'net','-50.000000','full rounded calculation produces signed recovery');
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('approve'),1,'corr.self')$q$,'42501','PAYROLL_INDEPENDENT_APPROVAL_REQUIRED','preparer cannot independently approve');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
insert into correction_client_samples values('approved',pg_temp.cc(pg_temp.correction_action('approve'),1,'corr.approve'));
reset role;
create function pg_temp.correction_fail_late() returns trigger language plpgsql as $$begin
 if new.command_id=pg_temp.wid('corr.fail.post') then raise exception using errcode='P0001',message='SYNTHETIC_CORRECTION_LATE_FAILURE';end if;return new;end $$;
create trigger synthetic_correction_fail_late before insert on core.outbox_events for each row execute function pg_temp.correction_fail_late();
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post'),2,'corr.fail.post')$q$,'P0001','SYNTHETIC_CORRECTION_LATE_FAILURE','late outbox failure rolls back correction');
reset role;
insert into payroll_assertions select is((select count(*)::integer from people_payroll.correction_balances),0,'failed correction has no signed balances');
insert into payroll_assertions select is((select count(*)::integer from people_payroll.correction_payslips),0,'failed correction has no payslip');
insert into payroll_assertions select is((select count(*)::integer from people_payroll.correction_source_effects),0,'failed correction leaves source chain unchanged');
select pg_temp.wactor('creator');set local role authenticated;
insert into correction_client_samples values('posted',pg_temp.cc(pg_temp.correction_action('post'),2,'corr.post'));
insert into payroll_assertions select is(pg_temp.cc(pg_temp.correction_action('post'),2,'corr.post'),(select response from correction_client_samples where name='posted'),'post exact replay');
insert into payroll_assertions select is(api.people_payroll_correction_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.post'),'post'),
 (select response from correction_client_samples where name='posted'),'own receipt retains confirmed correction');
insert into payroll_assertions select throws_ok($q$select pg_temp.pcmd(pg_temp.run_action('reverse','corr.original'),5,'corr.original.reverse')$q$,'55000','PAYROLL_ACTIVE_CORRECTION_BLOCKS_REVERSAL','original regular run cannot reverse active correction');
insert into correction_client_samples values('calculation',pg_temp.cdetail('calculation'));
insert into correction_client_samples values('sources',pg_temp.cdetail('sources'));
insert into correction_client_samples values('balances',pg_temp.cdetail('balances'));
insert into correction_client_samples values('payslip',pg_temp.cdetail('payslip'));
insert into correction_client_samples values('originals',api.people_payroll_correction_originals(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch')));
insert into correction_client_samples values('sealed_sources',api.people_payroll_correction_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select response->'entity'->>'original_calculation_id' from correction_client_samples where name='prepared')::uuid));
insert into payroll_assertions select throws_ok($q$select pg_temp.cs(pg_temp.csettle('50.01'),0,'corr.overpay')$q$,'55000','PAYROLL_SETTLEMENT_EXCEEDS_DUE','signed recovery cannot be over-allocated');
insert into payroll_assertions select throws_ok($q$select pg_temp.cs(pg_temp.csettle('10','pay'),0,'corr.wrongdirection')$q$,'55000','PAYROLL_SETTLEMENT_EXCEEDS_DUE','recovery cannot be paid out');
insert into correction_client_samples values('settlement',pg_temp.cs(pg_temp.csettle('20'),0,'corr.settle'));
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('reverse'),3,'corr.settled.reverse')$q$,'55000','PAYROLL_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL','active recorded recovery blocks correction reversal');
select pg_temp.cs(jsonb_build_object('action','reverse','id',pg_temp.wid('corr.settlement'),'correction_id',pg_temp.wid('corr.one'),
 'posting_date',pg_temp.wdate()+2,'reason','Synthetic original recovery reversal'),1,'corr.settle.reverse');
insert into payroll_assertions select throws_ok($q$select pg_temp.cs(jsonb_build_object('action','reverse','id',pg_temp.wid('corr.settlement'),'correction_id',pg_temp.wid('corr.one'),
 'posting_date',pg_temp.wdate()+2,'reason','Synthetic repeat'),2,'corr.settle.reverse.again')$q$,'55000','PAYROLL_SETTLEMENT_ALREADY_REVERSED','settlement original reversed once');
insert into correction_client_samples values('restoration_prepared',pg_temp.cc(pg_temp.correction_prepare(3600,'corr.two'),0,'corr.two.prepare'));
insert into payroll_assertions select is(pg_temp.cdetail('calculation','corr.two')->'items'->0->'difference'->>'net','50.000000','restoration recomputes original full pay then subtracts last rounded pay');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','corr.two'),1,'corr.two.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','corr.two'),2,'corr.two.post');
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('reverse'),3,'corr.earlier.reverse')$q$,'55000','PAYROLL_LATER_CORRECTION_BLOCKS_REVERSAL','later correction protects original difference');
select pg_temp.cc(pg_temp.correction_action('reverse','corr.two'),3,'corr.two.reverse');
select pg_temp.cc(pg_temp.correction_action('reverse'),3,'corr.one.reverse');
insert into correction_client_samples values('history',pg_temp.cdetail('history'));
reset role;
insert into payroll_assertions select is((select sum(amount) from people_payroll.correction_balance_effects),0::numeric,'all original signed correction balances reverse exactly');
insert into payroll_assertions select is((select sum(base_debit-base_credit) from finance.journal_lines where tenant_id=pg_temp.wid('tenant')),0::numeric,'off-cycle and recovery journals conserve');
insert into payroll_assertions select is((select count(*)::integer from people_payroll.correction_payslips),2,'difference payslips remain immutable after reversals');
insert into payroll_assertions select throws_ok($q$update people_payroll.correction_payslips set digest='changed'$q$,'55000','PAYROLL_CORRECTION_HISTORY_IMMUTABLE','difference payslip immutable');
insert into payroll_assertions select is((select seconds from people_payroll.correction_source_effects order by version desc limit 1),3600::bigint,'reversal stack restores original eligibility with new source versions');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.payroll.post';
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post'),2,'corr.post')$q$,'42501',null,'revocation rechecked before correction replay');
insert into payroll_assertions select throws_ok($q$select api.people_payroll_correction_own_receipt(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.post'),'post')$q$,'42501',null,'revocation rechecked before own correction receipt');
reset role;

do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from payroll_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
select jsonb_object_agg(name,response) as samples from correction_client_samples;
select jsonb_build_object('before',(select catalog from w4_before),'after',(select jsonb_build_object('functions',coalesce((select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('result',pg_get_function_result(p.oid),'source_md5',md5(pg_get_functiondef(p.oid)),'grants',p.proacl::text)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('api','core','people','workforce','projects','service','payroll','assets','finance','inventory','procurement','sales','workflow')),'{}'),'tables',coalesce((select jsonb_object_agg(n.nspname||'.'||c.relname,jsonb_build_object('forced_rls',c.relforcerowsecurity,'rls',c.relrowsecurity,'grants',c.relacl::text,'columns',(select jsonb_object_agg(a.attname,jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),'constraints',(select coalesce(jsonb_agg(pg_get_constraintdef(k.oid) order by k.conname),'[]') from pg_constraint k where k.conrelid=c.oid))) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p') and n.nspname in('core','people','workforce','projects','service','payroll','assets','finance','inventory','procurement','sales','workflow')),'{}')))) as candidate_catalog;
rollback;
