begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
set local search_path=extensions,pg_temp;
create temporary table w4_composition_before as select
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by role_id,permission_code)::text,'')) from core.role_permissions r) roles,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by plan_code,entitlement_code)::text,'')) from billing.plan_entitlements r) plans,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by tenant_id)::text,'')) from billing.tenant_subscriptions r) subscriptions,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by version)::text,'')) from supabase_migrations.schema_migrations r) ledger,
 (select md5(coalesce(jsonb_agg(jsonb_build_object('id',p.oid,'definition',pg_get_functiondef(p.oid)) order by p.oid)::text,''))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('core','finance') and p.prokind='f'
  and p.proname ~ '(journal|period|residual|allocate)') finance;
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
 perform projects.text(terms->'payment_terms',1000);
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
 if kind='project' then
  if to_regprocedure('projects.require_access(uuid,uuid,uuid,text,boolean)') is null then raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';end if;
  execute 'select projects.require_access($1,$2,$3,$4,true)' using t,e,b,case when decision then 'projects.time.approve' else 'projects.view' end;
  execute 'select projects.require_access($1,$2,$3,$4,true)' using t,e,b,'projects.cost.view';
  return;
 end if;
 if kind='service' then
  if to_regprocedure('service.require_access(uuid,uuid,uuid,text)') is null then raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';end if;
  execute 'select service.require_access($1,$2,$3,$4)' using t,e,b,case when decision then 'service.approve' else 'service.view' end;
  execute 'select service.require_access($1,$2,$3,$4)' using t,e,b,'service.cost.view';
  return;
 end if;
 perform people.require_access(t,e,b,case kind
  when 'attendance' then case when decision then 'people.attendance.approve' else 'people.attendance.view' end
  when 'leave' then case when decision then 'people.leave.approve' else 'people.leave.view' end
  else null end);
end $$;
create function people_payroll.correction_source_prepare(t uuid,e uuid,b uuid,kind text)
returns void language plpgsql security definer set search_path='' as $$begin
 perform people_payroll.correction_source_permission(t,e,b,kind,false);
 if kind='project' then
  execute 'select projects.require_access($1,$2,$3,$4,true)' using t,e,b,'projects.time.manage';
 elsif kind='service' then
  execute 'select service.require_access($1,$2,$3,$4)' using t,e,b,'service.work';
 else
  perform people.require_access(t,e,b,case kind when 'attendance' then 'people.attendance.manage' when 'leave' then 'people.leave.manage' else null end);
 end if;
end $$;
create function people_payroll.correction_billing_permission(t uuid,e uuid,b uuid,proof jsonb)
returns void language plpgsql security definer set search_path='' as $$begin
 if proof->>'original_status'='billed'
  or jsonb_array_length(coalesce(proof->'original_invoice_line_ids','[]'))>0
  or jsonb_array_length(coalesce(proof->'billing_credit_line_ids',proof->'credit_line_ids','[]'))>0 then
  if to_regprocedure('projects.finance_access(uuid,uuid,uuid,text,boolean)') is null then
   raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';end if;
  execute 'select projects.finance_access($1,$2,$3,$4,true)' using t,e,b,'projects.billing.manage';
 end if;
end $$;
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
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view',true);
 select ec.* into c from people_payroll.employee_calculations ec join people_payroll.runs r on r.id=ec.run_id
  where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and ec.id=p_calculation_id
  and r.status='posted' and ec.revision_id=r.current_revision_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_ORIGINAL_CALCULATION_NOT_FOUND';end if;
 select coalesce(jsonb_agg(people_payroll.correction_source_state(q.id)||jsonb_build_object('id',q.id,
  'start_utc',w.start_utc,'end_utc',w.end_utc,'calendar_version_id',w.calendar_version_id,
  'operational',people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,
   (people_payroll.correction_source_state(q.id)->>'claim_id')::uuid,gen_random_uuid(),jsonb_build_object('source_kind',w.source_kind,
    'original_source_id',w.source_id,'snapshot',people_payroll.correction_source_state(q.id)->'operational_snapshot'),'read')) order by q.id),'[]') into items
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
returns jsonb language plpgsql stable security definer set search_path='' as $$declare c people_payroll.corrections%rowtype;items jsonb;source people_payroll.correction_sources%rowtype;effect jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,case when p_section='balances' then 'people.payroll.settle'
  when p_section='payslip' then 'people.payroll.payslip.view' else 'people.payroll.view' end,true);
 select * into c from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_correction_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_NOT_FOUND';end if;
 if p_section='calculation' then
  items:=jsonb_build_array(jsonb_build_object('id',c.id,'before',c.before_calculation,'after',c.after_calculation,'difference',c.difference,'reason',c.reason));
 elsif p_section='sources' then
  for source in select * from people_payroll.correction_sources where correction_id=c.id loop
   perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,source.source_kind,false);
   perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,coalesce(source.impact->'billing',source.impact->'after'->'billing'));
   for effect in select value from jsonb_array_elements(coalesce(source.impact->'after'->'allocation_impacts','[]')) loop
    perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,effect->>'source_kind',false);
    perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,coalesce(effect->'impact'->'billing',effect->'impact'->'after'->'billing'));
   end loop;
  end loop;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from
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
 allocation people.work_allocations%rowtype;linked_effect jsonb;
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
  array['action','id','digest','posting_date','reason','current_billing_impacts'] else array['action','id','digest','reason'] end)) then
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
   perform people_payroll.correction_source_prepare(p_tenant_id,p_legal_entity_id,p_branch_id,state->>'source_kind');
   perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,x->'impact');
   for linked_effect in select value from jsonb_array_elements(coalesce(x->'impact'->'allocation_changes','[]')) loop
    perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,linked_effect);
   end loop;
   if state->>'source_kind'='attendance' then
    for allocation in select * from people.work_allocations where claim_id=(state->>'claim_id')::uuid and active loop
     perform people_payroll.correction_source_prepare(p_tenant_id,p_legal_entity_id,p_branch_id,allocation.source_kind);
    end loop;
   end if;
  end loop;
 elsif act in('approve','reject','post','reverse') then
  for src in select * from people_payroll.correction_sources where correction_id=cid loop
   perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,src.source_kind,true);
   perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,coalesce(src.impact->'billing',src.impact->'after'->'billing'));
   for linked_effect in select value from jsonb_array_elements(coalesce(src.impact->'after'->'allocation_impacts','[]')) loop
    perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,linked_effect->>'source_kind',true);
    perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,coalesce(linked_effect->'impact'->'billing',linked_effect->'impact'->'after'->'billing'));
   end loop;
  end loop;
 end if;
 if act='reverse' then
  if jsonb_typeof(coalesce(p_payload->'current_billing_impacts','[]')) is distinct from 'array'
   or jsonb_array_length(coalesce(p_payload->'current_billing_impacts','[]'))>50 then
   raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
  for x in select value from jsonb_array_elements(coalesce(p_payload->'current_billing_impacts','[]')) loop
   -- Reject impossible source/credit combinations before looking up a linked
   -- finance provider, including on a confirmed command replay.
   if jsonb_typeof(x) is distinct from 'object' or coalesce(x->>'seal_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or jsonb_typeof(x->'billing_credit_line_ids') is distinct from 'array' or jsonb_typeof(x->'allocation_credits') is distinct from 'array' then
    raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   select * into src from people_payroll.correction_sources where correction_id=cid and seal_id=(x->>'seal_id')::uuid;
   if src.id is null or src.impact is null or src.source_kind not in('attendance','project','service')
    or(src.source_kind='attendance' and jsonb_array_length(x->'billing_credit_line_ids')<>0)
    or(src.source_kind<>'attendance' and jsonb_array_length(x->'allocation_credits')<>0) then
    raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   perform people_payroll.current_credit_ids(x->'billing_credit_line_ids');
   perform people_payroll.current_allocation_credits(x->'allocation_credits');
   perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,x);
   for linked_effect in select value from jsonb_array_elements(coalesce(x->'allocation_credits','[]')) loop
    perform people_payroll.correction_billing_permission(p_tenant_id,p_legal_entity_id,p_branch_id,linked_effect);
   end loop;
  end loop;
 end if;
 replay:=core.wave3_replay(p_tenant_id,'people.payroll.correction.'||act,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
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
    if jsonb_typeof(x->'impact') is distinct from 'object' or exists(select 1 from jsonb_object_keys(x->'impact') k
     where k<>all(array['mode','expected_source_version','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','billing_credit_line_ids','allocation_changes']))
     or jsonb_typeof(x->'impact'->'expected_source_version') is distinct from 'number'
     or (x->'impact'->>'expected_source_version') !~ '^[1-9][0-9]{0,15}$' then raise exception using errcode='22023',message='PAYROLL_SOURCE_IMPACT_INVALID';end if;
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
   if jsonb_typeof(coalesce(p_payload->'current_billing_impacts','[]')) is distinct from 'array'
    or jsonb_array_length(coalesce(p_payload->'current_billing_impacts','[]'))>50 then
    raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   seen:='{}';
   for x in select value from jsonb_array_elements(coalesce(p_payload->'current_billing_impacts','[]')) loop
    if jsonb_typeof(x) is distinct from 'object' or not(x ?& array['seal_id','source_revision_id','expected_source_version','billing_credit_line_ids','allocation_credits'])
     or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['seal_id','source_revision_id','expected_source_version','billing_credit_line_ids','allocation_credits']))
     or coalesce(x->>'seal_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or coalesce(x->>'source_revision_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or jsonb_typeof(x->'expected_source_version') is distinct from 'number' or coalesce(x->>'expected_source_version','') !~ '^[1-9][0-9]{0,15}$'
     or (x->>'seal_id')::uuid=any(seen) or not exists(select 1 from people_payroll.correction_sources s where s.correction_id=cid and s.seal_id=(x->>'seal_id')::uuid and s.impact is not null and s.source_kind in('attendance','project','service'))
     or jsonb_typeof(x->'billing_credit_line_ids') is distinct from 'array' or jsonb_array_length(x->'billing_credit_line_ids')>50
     or jsonb_typeof(x->'allocation_credits') is distinct from 'array' or jsonb_array_length(x->'allocation_credits')>50 then
     raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
    seen:=array_append(seen,(x->>'seal_id')::uuid);
    state:=people_payroll.correction_source_state((x->>'seal_id')::uuid);
    operational:=people_payroll.approved_source(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid);
    if x->>'source_revision_id' is distinct from operational->>'source_id'
     or (x->>'expected_source_version')::bigint is distinct from (operational->>'source_version')::bigint then
     raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
    perform people_payroll.current_credit_ids(x->'billing_credit_line_ids');
    perform people_payroll.current_allocation_credits(x->'allocation_credits');
    if (state->>'source_kind'='attendance' and jsonb_array_length(x->'billing_credit_line_ids')<>0)
     or(state->>'source_kind'<>'attendance' and jsonb_array_length(x->'allocation_credits')<>0) then
     raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   end loop;
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
     x:=(select value from jsonb_array_elements(coalesce(p_payload->'current_billing_impacts','[]')) where value->>'seal_id'=src.seal_id::text);
     operational:=people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid,replacement_id,
      src.impact||jsonb_build_object('current_billing_credit_line_ids',coalesce(x->'billing_credit_line_ids','[]'),
       'current_source_revision_id',x->'source_revision_id','current_source_version',x->'expected_source_version',
       'current_allocation_credits',coalesce(x->'allocation_credits','[]')),'reverse');
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
create function people_payroll.current_credit_ids(ids jsonb) returns void language plpgsql set search_path='' as $$begin
 if jsonb_typeof(ids) is distinct from 'array' or jsonb_array_length(ids)>50
  or exists(select 1 from jsonb_array_elements(ids) x where jsonb_typeof(x) is distinct from 'string'
   or (x#>>'{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (select count(distinct x#>>'{}') from jsonb_array_elements(ids) x)<>jsonb_array_length(ids) then
  raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
end $$;
create function people_payroll.current_allocation_credits(rows jsonb) returns void language plpgsql set search_path='' as $$
declare x jsonb;seen uuid[]:='{}';begin
 if jsonb_typeof(rows) is distinct from 'array' or jsonb_array_length(rows)>50 then
  raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
 for x in select value from jsonb_array_elements(rows) loop
  if jsonb_typeof(x) is distinct from 'object' or not(x ?& array['entry_id','source_revision_id','expected_source_version','billing_credit_line_ids'])
   or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['entry_id','source_revision_id','expected_source_version','billing_credit_line_ids']))
   or coalesce(x->>'entry_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(x->>'source_revision_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or jsonb_typeof(x->'expected_source_version') is distinct from 'number' or coalesce(x->>'expected_source_version','') !~ '^[1-9][0-9]{0,15}$'
   or (x->>'entry_id')::uuid=any(seen) then raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
  seen:=array_append(seen,(x->>'entry_id')::uuid);
  perform people_payroll.current_credit_ids(x->'billing_credit_line_ids');
 end loop;
end $$;
create function people_payroll.linked_allocation_bound(t uuid,e uuid,b uuid,employee uuid,claim uuid,frozen jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare a people.work_allocations%rowtype;entry uuid;key text;seen text[]:='{}';x jsonb;begin
 for a in select * from people.work_allocations where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and claim_id=claim and active loop
  entry:=null;
  if a.source_kind='project' and to_regclass('projects.time_allocations') is not null then
   execute 'select entry_id from projects.time_allocations where tenant_id=$1 and legal_entity_id=$2 and allocation_id=$3'
    into entry using t,e,a.id;
  elsif a.source_kind='service' and to_regclass('service.labor_allocations') is not null then
   execute 'select labor_id from service.labor_allocations where tenant_id=$1 and legal_entity_id=$2 and branch_id=$3 and allocation_id=$4'
    into entry using t,e,b,a.id;
  end if;
  key:=a.source_kind||':'||coalesce(entry,a.source_id)::text;
  if not(key=any(seen)) then seen:=array_append(seen,key);end if;
  if cardinality(seen)>50 then raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_BOUND_REQUIRED';end if;
 end loop;
 for x in select value from jsonb_array_elements(coalesce(frozen,'[]')) loop
  key:=(x->>'source_kind')||':'||coalesce(x->'impact'->>'entry_id',x->'impact'->'before'->>'entry_id',x->'impact'->'before'->>'id');
  if key is null then raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
  if not(key=any(seen)) then seen:=array_append(seen,key);end if;
  if cardinality(seen)>50 then raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_BOUND_REQUIRED';end if;
 end loop;
end $$;
create function people_payroll.replace_claim(t uuid,e uuid,b uuid,employee uuid,old_claim uuid,
 kind text,source_id uuid,calendar uuid,p_start timestamptz,p_end timestamptz,p_breaks jsonb,correction_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c people_payroll.corrections%rowtype;w people.work_claims%rowtype;new_claim uuid;new_w people.work_claims%rowtype;begin
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
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
 allocation_body jsonb;allocation_effects jsonb:='[]';change jsonb;change_ids uuid[]:='{}';linked_ids uuid[]:='{}';linked_entry uuid;
begin
 if p_mode not in('read','validate','apply','reverse') or revision is null then raise exception using errcode='22023',message='PAYROLL_SOURCE_IMPACT_INVALID';end if;
 select * into w from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and id=claim and active;
 source_kind:=coalesce(w.source_kind,source_kind);
 if p_mode='read' then perform people_payroll.correction_source_permission(t,e,b,source_kind,false);end if;
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
  perform people_payroll.linked_allocation_bound(t,e,b,employee,claim,
   case when p_mode='read' then proposal->'snapshot'->'allocation_impacts' when p_mode='reverse' then proposal->'after'->'allocation_impacts' else '[]'::jsonb end);
  if p_mode='read' then
   for allocation in select * from people.work_allocations where claim_id=claim and active order by id loop
    perform people_payroll.correction_source_permission(t,e,b,allocation.source_kind,false);
    if to_regprocedure(case allocation.source_kind when 'project' then 'projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' else 'service.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' end) is null then
     raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';
    else
     execute case allocation.source_kind when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
      into allocation_body using t,e,b,employee,allocation.id,revision,proposal,'read';
    end if;
    linked_entry:=coalesce((allocation_body->>'entry_id')::uuid,(allocation_body->'before'->>'entry_id')::uuid,(allocation_body->'before'->>'id')::uuid);
    if linked_entry is null then raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
    if not(linked_entry=any(linked_ids)) then
     linked_ids:=array_append(linked_ids,linked_entry);
     allocation_effects:=allocation_effects||jsonb_build_array(jsonb_build_object('allocation_id',allocation.id,'source_kind',allocation.source_kind,
      'source_id',allocation.source_id,'active',true,'operational',allocation_body));
    end if;
   end loop;
   -- Removed allocations retain a frozen origin but reversal must inspect the
   -- current module revision. Never reuse the historical credit selection.
   for effect in select value from jsonb_array_elements(coalesce(proposal->'snapshot'->'allocation_impacts','[]')) loop
    linked_entry:=coalesce((effect->'impact'->>'entry_id')::uuid,(effect->'impact'->'before'->>'entry_id')::uuid,(effect->'impact'->'before'->>'id')::uuid);
    if linked_entry is null then raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
    if linked_entry=any(linked_ids) then continue;end if;
    perform people_payroll.correction_source_permission(t,e,b,effect->>'source_kind',false);
    if to_regprocedure(case effect->>'source_kind' when 'project' then 'projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' else 'service.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' end) is null then
     raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,
      proposal||jsonb_build_object('operational_mode','reverse','current_claim_id',claim,'allocation_impact',coalesce(effect->'original_impact',effect->'impact')),'read';
    linked_ids:=array_append(linked_ids,linked_entry);
    allocation_effects:=allocation_effects||jsonb_build_array(jsonb_build_object('allocation_id',effect->'allocation_id','source_kind',effect->'source_kind',
     'source_id',allocation_body->'source_id','active',false,'operational',allocation_body));
   end loop;
   return jsonb_build_object('before',before_body,'source_id',r.id,'source_version',a.version,'paid_seconds',r.payable_seconds,'claim_id',claim,'allocations',allocation_effects);
  end if;
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
  if p_mode<>'reverse' then
   for allocation in select * from people.work_allocations where claim_id=claim and active order by id loop
    perform people_payroll.correction_source_permission(t,e,b,allocation.source_kind,true);
    execute case allocation.source_kind when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,allocation.id,revision,proposal,'read';
    if coalesce((allocation_body->>'entry_id')::uuid,(allocation_body->'before'->>'entry_id')::uuid,(allocation_body->'before'->>'id')::uuid) is null then
     raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
    linked_ids:=array_append(linked_ids,coalesce((allocation_body->>'entry_id')::uuid,(allocation_body->'before'->>'entry_id')::uuid,(allocation_body->'before'->>'id')::uuid));
   end loop;
   if jsonb_typeof(coalesce(proposal->'allocation_changes','[]')) is distinct from 'array'
    or jsonb_array_length(coalesce(proposal->'allocation_changes','[]'))>50 then raise exception using errcode='22023',message='WORK_ALLOCATION_IMPACT_INVALID';end if;
   for change in select value from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) loop
    if jsonb_typeof(change) is distinct from 'object' or exists(select 1 from jsonb_object_keys(change) k where k<>all(array['entry_id','mode','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','billing_credit_line_ids']))
     or coalesce(change->>'mode','') not in('retain','geometry','remove')
     or coalesce(change->>'entry_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or (change->>'entry_id')::uuid=any(change_ids)
     or not ((change->>'entry_id')::uuid=any(linked_ids)) then
     raise exception using errcode='22023',message='WORK_ALLOCATION_IMPACT_INVALID';end if;
    change_ids:=array_append(change_ids,(change->>'entry_id')::uuid);
   end loop;
  end if;
  if p_mode='reverse' then
   for effect in select value from jsonb_array_elements(proposal->'after'->'allocation_impacts') loop
    perform people_payroll.correction_source_permission(t,e,b,effect->>'source_kind',true);
    if coalesce((effect->'impact'->>'entry_id')::uuid,(effect->'impact'->'before'->>'entry_id')::uuid,(effect->'impact'->'before'->>'id')::uuid) is null then
     raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
    linked_ids:=array_append(linked_ids,coalesce((effect->'impact'->>'entry_id')::uuid,(effect->'impact'->'before'->>'entry_id')::uuid,(effect->'impact'->'before'->>'id')::uuid));
   end loop;
   for change in select value from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]')) loop
    if not ((change->>'entry_id')::uuid=any(linked_ids)) or linked_ids is null then
     raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   end loop;
   for effect in select value from jsonb_array_elements(proposal->'after'->'allocation_impacts') loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,
      proposal||jsonb_build_object('attendance_after',after_body,'operational_mode','reverse','current_claim_id',claim,'allocation_impact',effect->'impact'),'validate';
    allocation_effects:=allocation_effects||jsonb_build_array(effect||jsonb_build_object('impact',allocation_body,'original_impact',effect->'impact'));
   end loop;
  else
  for allocation in select * from people.work_allocations where claim_id=claim and active order by id loop
   if to_regprocedure(case allocation.source_kind when 'project' then 'projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' else 'service.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' end) is null then
    raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
   execute case allocation.source_kind when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
    into allocation_body using t,e,b,employee,allocation.id,revision,proposal||jsonb_build_object('attendance_after',after_body),case when p_mode in('apply','reverse') then 'validate' else p_mode end;
   allocation_effects:=allocation_effects||jsonb_build_array(jsonb_build_object('allocation_id',allocation.id,'source_kind',allocation.source_kind,'impact',allocation_body));
  end loop;
  end if;
  after_body:=after_body||jsonb_build_object('allocation_impacts',allocation_effects);
  if p_mode in('apply','reverse') then
   if p_mode='apply' and after_body is distinct from proposal->'after' then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   -- Module hooks relinquish old allocations before the common claim replacement.
   for effect in select value from jsonb_array_elements(allocation_effects) loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,proposal||jsonb_build_object('attendance_after',after_body,'operational_mode',p_mode,'current_claim_id',claim,'allocation_impact',coalesce(effect->'original_impact',effect->'impact')),'release';
   end loop;
   new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'attendance',revision,calendar.id,start_utc,end_utc,target->'breaks',(proposal->>'correction_id')::uuid);
   insert into people.attendance_revisions(id,tenant_id,legal_entity_id,branch_id,employee_id,entry_id,version,calendar_version_id,
    start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,breaks,gross_seconds,break_seconds,payable_seconds,
    reason,supersedes_revision_id,recorded_by)
   values(revision,t,e,b,employee,a.id,a.version+1,calendar.id,start_local,(target->>'start_offset_seconds')::integer,end_local,
    (target->>'end_offset_seconds')::integer,start_utc,end_utc,target->'breaks',extract(epoch from end_utc-start_utc)::bigint,
    break_seconds,extract(epoch from end_utc-start_utc)::bigint-break_seconds,'Linked sealed payroll source correction',r.id,auth.uid());
   update people.attendance_entries set current_revision_id=revision,active_claim_id=new_claim,version=version+1,decided_by=auth.uid() where id=a.id;
   insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,entry_id,revision_id,
    action,before_status,after_status,reason,actor_id,command_id)
    values(t,e,b,employee,a.id,revision,'correct','approved','approved',
     case when p_mode='reverse' then 'Original geometry restored by linked payroll correction reversal' else 'Approved geometry appended by linked payroll source correction' end,
     auth.uid(),revision);
   for effect in select value from jsonb_array_elements(allocation_effects) loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,proposal||jsonb_build_object('attendance_after',after_body,'new_claim_id',new_claim,'operational_mode',p_mode,'current_claim_id',claim,'allocation_impact',coalesce(effect->'original_impact',effect->'impact')),p_mode;
   end loop;
  else new_claim:=claim;end if;
  return jsonb_build_object('before',before_body,'after',after_body,'source_id',revision,'source_version',a.version+1,
   'paid_seconds',extract(epoch from end_utc-start_utc)::bigint-break_seconds,'claim_id',new_claim);
 elsif source_kind='leave' then
  select * into l from people.leave_requests where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and (active_claim_id=claim or (p_mode='reverse' and id=(proposal->'before'->>'id')::uuid)
    or (p_mode='read' and claim is null and id=coalesce((proposal->'snapshot'->>'request_id')::uuid,(proposal->>'original_source_id')::uuid)));
  if l.id is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  select * into account from people.leave_accounts where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id;
  if p_mode in('apply','reverse') then select * into account from people.leave_accounts where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id for update;end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into effects from people.leave_effects x where x.request_id=l.id
   and x.seconds<0 and not exists(select 1 from people.leave_effects y where y.reversal_of=x.id);
  before_body:=to_jsonb(l)||jsonb_build_object('balance_version',account.version,'effects',effects);
  if p_mode='read' then return jsonb_build_object('before',before_body,'source_id',coalesce(w.source_id,l.id),'source_version',l.version,'paid_seconds',case when l.status='cancelled' then 0 else l.charge_seconds-l.unpaid_seconds end,'claim_id',claim);end if;
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
  if p_mode in('apply','reverse') then
   insert into people.leave_events(tenant_id,legal_entity_id,branch_id,employee_id,request_id,
    action,before_status,after_status,reason,actor_id,command_id)
    values(t,e,b,employee,l.id,case when p_mode='apply' then 'cancel' else 'approve' end,l.status,
     case when p_mode='apply' then 'cancelled' else 'approved' end,
     case when p_mode='apply' then 'Original grant debits restored by linked payroll leave cancellation' else 'Original grant debits reconsumed by linked payroll correction reversal' end,
     auth.uid(),revision);
  end if;
  return jsonb_build_object('before',before_body,'after',after_body,'source_id',case when p_mode='reverse' then revision else l.id end,
   'source_version',l.version+1,'paid_seconds',case when p_mode='reverse' then l.charge_seconds-l.unpaid_seconds else 0 end,'claim_id',new_claim);
 end if;
 raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';
end $$;
revoke all on function people_payroll.correction_source_prepare(uuid,uuid,uuid,text),
 people_payroll.correction_billing_permission(uuid,uuid,uuid,jsonb),people_payroll.linked_allocation_bound(uuid,uuid,uuid,uuid,uuid,jsonb),
 people_payroll.replace_claim(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,timestamptz,timestamptz,jsonb,uuid),
 people_payroll.source_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),people_payroll.current_credit_ids(jsonb),
 people_payroll.current_allocation_credits(jsonb) from public,anon,authenticated;

-- Unapplied W4 linked-source candidate. Requires project finance and payroll
-- corrections. No API, plan, role, or entitlement grants are introduced.
create table projects.payroll_time_impacts(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,project_id uuid not null,entry_id uuid not null,correction_id uuid not null,
 original_revision_id uuid not null,replacement_revision_id uuid not null,mode text not null,
 body jsonb not null,actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 check(mode in('apply','reverse')),unique(correction_id,entry_id,mode),
 foreign key(tenant_id,legal_entity_id,project_id,entry_id,original_revision_id)
  references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,entry_id,replacement_revision_id)
  references projects.time_revisions(tenant_id,legal_entity_id,project_id,entry_id,id),
 foreign key(tenant_id,legal_entity_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,id)
);
create index project_payroll_impact_scope_idx on projects.payroll_time_impacts(tenant_id,legal_entity_id,branch_id,project_id,id);
create index project_payroll_impact_original_idx on projects.payroll_time_impacts(original_revision_id);
create index project_payroll_impact_replacement_idx on projects.payroll_time_impacts(replacement_revision_id);
alter table projects.payroll_time_impacts enable row level security;
alter table projects.payroll_time_impacts force row level security;
revoke all on projects.payroll_time_impacts from public,anon,authenticated,service_role;
create trigger immutable before update or delete on projects.payroll_time_impacts
 for each row execute function projects.immutable();

create function projects.payroll_impact_guard(t uuid,e uuid,b uuid,employee uuid,claim uuid,correction uuid)
returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from people_payroll.corrections c join people_payroll.correction_sources s on s.correction_id=c.id
  where c.id=correction and c.tenant_id=t and c.legal_entity_id=e and c.branch_id=b and c.employee_id=employee
   and c.status in('approved','posted') and s.impact is not null
   and (people_payroll.correction_source_state(s.seal_id)->>'claim_id')::uuid=claim) then
  raise exception using errcode='42501',message='PAYROLL_APPROVED_LINKED_IMPACT_REQUIRED';end if;
end $$;

-- One operational revision owns all its break-separated allocations. Repeated
-- allocation callbacks append that revision once and return its frozen result.
create function projects.payroll_revision_impact(t uuid,e uuid,b uuid,employee uuid,entry_id uuid,claim uuid,
 revision_id uuid,proposal jsonb,p_mode text,direct_claim boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare entry projects.time_entries%rowtype;r projects.time_revisions%rowtype;pr projects.register%rowtype;
 slot projects.resource_slots%rowtype;cal people.work_calendar_versions%rowtype;
 correction uuid:=(proposal->>'correction_id')::uuid;actual_mode text;
 before_body jsonb;after_body jsonb;target jsonb;change jsonb;billing jsonb;body jsonb;prior jsonb;
 allocation_ids jsonb;breaks jsonb;break_row jsonb;attendance jsonb:=proposal->'attendance_after';
 current_credit jsonb;credit_ids jsonb;
 start_local timestamp;end_local timestamp;start_utc timestamptz;end_utc timestamptz;
 cursor_utc timestamptz;break_start timestamptz;break_end timestamptz;break_seconds bigint;seconds bigint;
 bill_amount numeric;cost_amount numeric;cost_rate numeric;new_claim uuid;link uuid;allocation uuid;unit uuid;
 digest text;remove_source boolean:=false;original_revision uuid;original_effect projects.payroll_time_impacts%rowtype;
begin
 if p_mode not in('read','validate','release','apply','reverse') or proposal is null or jsonb_typeof(proposal)<>'object' then
  raise exception using errcode='22023',message='PROJECT_PAYROLL_IMPACT_INVALID';end if;
 actual_mode:=case when p_mode='reverse' or proposal->>'operational_mode'='reverse' then 'reverse' else 'apply' end;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
 perform 1 from people.employees where tenant_id=t and legal_entity_id=e and id=employee for update;
 select * into entry from projects.time_entries x where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b
  and x.employee_id=employee and x.id=entry_id for update;
 if entry.id is null then raise exception using errcode='P0002',message='PROJECT_TIME_NOT_FOUND';end if;
 select * into pr from projects.register where id=entry.project_id for update;
 select * into r from projects.time_revisions where id=entry.current_revision_id;
 select * into slot from projects.resource_slots where id=r.resource_slot_id;
 select * into cal from people.work_calendar_versions where id=slot.calendar_version_id;
 perform core.wave3_require_scope(t,'projects.cost.view',e,b);
 if p_mode<>'read' then perform core.wave3_require_scope(t,'projects.time.approve',e,b);end if;
 select x.body into prior from projects.payroll_time_impacts x where x.correction_id=correction and x.entry_id=entry.id and x.mode=actual_mode;
 if prior is not null and p_mode in('apply','reverse') then
  if entry.current_revision_id is distinct from(prior->>'source_id')::uuid
   or entry.version is distinct from(prior->>'source_version')::bigint
   or claim is distinct from(prior->>'claim_id')::uuid then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  return prior;
 end if;
 if entry.status<>'approved' and not(actual_mode='reverse' and entry.status='cancelled') then
  raise exception using errcode='55000',message='PROJECT_TIME_LINKED_IMPACT_REQUIRED';end if;
 select coalesce(jsonb_agg(a.allocation_id order by a.allocation_id),'[]') into allocation_ids
  from projects.time_allocations a where a.revision_id=r.id;
 select c.hourly_rate into cost_rate from projects.time_costs c where c.revision_id=r.id;
 if cost_rate is null then select c.hourly_rate into cost_rate from projects.resource_costs c where c.resource_slot_id=slot.id;end if;
 if cost_rate is null then raise exception using errcode='55000',message='PROJECT_COST_BASIS_REQUIRED';end if;
 before_body:=jsonb_build_object('revision',to_jsonb(r),'entry_id',entry.id,'entry_version',entry.version,'status',entry.status,
  'claim_id',claim,'allocation_ids',allocation_ids,'project_id',pr.id,'project_code',pr.code,'project_name',pr.name,
  'employee_id',employee,'employee_name',(select display_name from people.employees where id=employee),
  'calendar_version_id',cal.id,'timezone',cal.timezone,'cost_rate',cost_rate::text);
 if p_mode='read' then return jsonb_build_object('before',before_body,'source_id',r.id,'source_version',entry.version,
  'paid_seconds',r.payable_seconds,'claim_id',claim,'entry_id',entry.id,'project_id',pr.id,'project_code',pr.code,'project_name',pr.name);end if;
 if actual_mode='reverse' then
  select * into original_effect from projects.payroll_time_impacts x where x.tenant_id=t and x.legal_entity_id=e
   and x.branch_id=b and x.entry_id=entry.id and x.correction_id=correction and x.mode='apply';
  if original_effect.id is null or original_effect.replacement_revision_id is distinct from r.id
   or entry.version is distinct from(original_effect.body->>'source_version')::bigint
   or claim is distinct from(original_effect.body->>'claim_id')::uuid then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if direct_claim and(proposal->'before' is distinct from original_effect.body->'before'
    or proposal->'after' is distinct from original_effect.body->'after')
   or not direct_claim and(proposal->'allocation_impact'->'before' is distinct from original_effect.body->'before'
    or proposal->'allocation_impact'->'after' is distinct from original_effect.body->'after') then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 end if;
 if direct_claim then
  if not exists(select 1 from people.work_claims w where w.id=claim and w.tenant_id=t and w.legal_entity_id=e
   and w.branch_id=b and w.employee_id=employee and w.source_kind='project' and w.source_id=r.id and w.active)
   or r.attendance_claim_id is not null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if actual_mode<>'reverse' and entry.version is distinct from(proposal->>'expected_source_version')::bigint then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  target:=case actual_mode when 'reverse' then proposal->'before'->'revision' else proposal end;
 else
  if jsonb_typeof(coalesce(proposal->'allocation_changes','[]')) is distinct from 'array'
   or jsonb_array_length(coalesce(proposal->'allocation_changes','[]'))>50 then
   raise exception using errcode='22023',message='PROJECT_ALLOCATION_CHANGE_INVALID';end if;
  if(select count(*) from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) x where (x->>'entry_id')::uuid=entry.id)>1 then
   raise exception using errcode='22023',message='PROJECT_ALLOCATION_CHANGE_INVALID';end if;
  select value into change from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) where (value->>'entry_id')::uuid=entry.id;
  if change is not null and change->>'mode' not in('retain','geometry','remove') then raise exception using errcode='22023',message='PROJECT_ALLOCATION_CHANGE_INVALID';end if;
  target:=case when actual_mode='reverse' then proposal->'allocation_impact'->'before'->'revision'
   when change->>'mode'='geometry' then change else to_jsonb(r) end;
  remove_source:=actual_mode<>'reverse' and coalesce(change->>'mode'='remove',false);
  revision_id:=md5(revision_id::text||':'||entry.id::text)::uuid;
 end if;
 if target is null then raise exception using errcode='22023',message='PROJECT_PAYROLL_IMPACT_INVALID';end if;
 if p_mode in('release','apply','reverse') then perform projects.payroll_impact_guard(t,e,b,employee,claim,correction);end if;
 start_local:=(target->>'start_local')::timestamp;end_local:=(target->>'end_local')::timestamp;
 if start_local is null or end_local is null or extract(second from start_local)%1<>0 or extract(second from end_local)%1<>0 then
  raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
 start_utc:=people.resolve_local_instant(cal.timezone,start_local,(target->>'start_offset_seconds')::integer);
 end_utc:=people.resolve_local_instant(cal.timezone,end_local,(target->>'end_offset_seconds')::integer);
 if not(tstzrange(slot.start_utc,slot.end_utc,'[)') @> tstzrange(start_utc,end_utc,'[)')) then
  raise exception using errcode='55000',message='PROJECT_TIME_OUTSIDE_RESOURCE';end if;
 perform people.work_local_coverage(t,e,b,employee,cal.id,start_local,end_local);
 breaks:=coalesce(target->'breaks','[]');break_seconds:=people.work_break_seconds(start_utc,end_utc,breaks);
 seconds:=extract(epoch from end_utc-start_utc)::bigint-break_seconds;
 if seconds not between 1 and 129600 then raise exception using errcode='22023',message='WORK_DURATION_INVALID';end if;
 -- Every new allocation segment must remain inside one payable attendance
 -- segment. An invalid interval needs an explicit removal/revision decision.
 if not direct_claim and not remove_source then
  if attendance is null or (attendance->>'calendar_version_id')::uuid<>cal.id then
   raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
  cursor_utc:=start_utc;
  for break_row in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',end_utc,'end_utc',end_utc))) loop
   break_start:=(break_row->>'start_utc')::timestamptz;break_end:=(break_row->>'end_utc')::timestamptz;
   if break_start>cursor_utc and (cursor_utc<(attendance->>'start_utc')::timestamptz or break_start>(attendance->>'end_utc')::timestamptz
    or exists(select 1 from jsonb_array_elements(attendance->'breaks') z where
     tstzrange((z->>'start_utc')::timestamptz,(z->>'end_utc')::timestamptz,'[)') && tstzrange(cursor_utc,break_start,'[)'))) then
    raise exception using errcode='55000',message='PROJECT_ALLOCATION_GEOMETRY_IMPACT_REQUIRED';end if;
   cursor_utc:=break_end;
  end loop;
 end if;
 bill_amount:=case when remove_source then 0 else projects.ratio(slot.bill_rate*1000000*seconds,3600,pr.precision) end;
 cost_amount:=case when remove_source then 0 else projects.ratio(cost_rate*1000000*seconds,3600,pr.precision) end;
 if actual_mode='reverse' then
  if direct_claim then
   current_credit:=case when proposal->>'current_source_revision_id' is not null then jsonb_build_object(
    'source_revision_id',proposal->'current_source_revision_id','expected_source_version',proposal->'current_source_version',
    'billing_credit_line_ids',proposal->'current_billing_credit_line_ids') end;
  else
   select value into current_credit from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]'))
    where (value->>'entry_id')::uuid=entry.id;
  end if;
  if current_credit is not null and ((current_credit->>'source_revision_id')::uuid is distinct from r.id
   or (current_credit->>'expected_source_version')::bigint is distinct from entry.version) then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  credit_ids:=coalesce(current_credit->'billing_credit_line_ids',proposal->'current_billing_credit_line_ids','[]');
 else credit_ids:=coalesce(change->'billing_credit_line_ids',proposal->'billing_credit_line_ids','[]');end if;
 billing:=projects.payroll_billing_impact(t,e,b,pr.id,r.id,
  (proposal-'operational_mode')||jsonb_build_object('billing_credit_line_ids',credit_ids),'validate');
 after_body:=jsonb_build_object('start_local',start_local,'end_local',end_local,'start_offset_seconds',(target->>'start_offset_seconds')::integer,
  'end_offset_seconds',(target->>'end_offset_seconds')::integer,'start_utc',start_utc,'end_utc',end_utc,'breaks',breaks,
  'payable_seconds',seconds,'calendar_version_id',cal.id,'bill_amount',bill_amount::text,'cost_amount',cost_amount::text,
  'status',case when remove_source then 'cancelled' else 'approved' end,'billing',billing);
 if p_mode='apply' and direct_claim and (proposal->'before' is distinct from before_body or proposal->'after' is distinct from after_body) then
  raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 if p_mode in('release','apply','reverse') and not direct_claim and actual_mode<>'reverse' and
  (proposal->'allocation_impact'->'before' is distinct from before_body
   or proposal->'allocation_impact'->'after' is distinct from after_body) then
  raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 body:=jsonb_build_object('before',before_body,'after',after_body,'source_id',revision_id,'source_version',entry.version+1,
  'paid_seconds',case when remove_source then 0 else seconds end,'claim_id',claim,'entry_id',entry.id,'project_id',pr.id,
  'project_code',pr.code,'project_name',pr.name);
 if p_mode='validate' then return body;end if;
 if p_mode='release' then
  for allocation in select a.allocation_id from projects.time_allocations a join people.work_allocations w on w.id=a.allocation_id
   where a.revision_id=r.id and w.active order by a.allocation_id loop perform people.revoke_work_allocation(t,e,employee,allocation);end loop;
  return body;
 end if;
 -- Claim and history changes are in the same outer payroll posting transaction.
 if direct_claim then
  for allocation in select a.allocation_id from projects.time_allocations a join people.work_allocations w on w.id=a.allocation_id
   where a.revision_id=r.id and w.active order by a.allocation_id loop perform people.revoke_work_allocation(t,e,employee,allocation);end loop;
  new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'project',revision_id,cal.id,start_utc,end_utc,breaks,correction);
 else new_claim:=(proposal->>'new_claim_id')::uuid;
  if new_claim is null or not exists(select 1 from people.work_claims w where w.id=new_claim and w.tenant_id=t
   and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee and w.active and w.source_kind='attendance'
   and w.calendar_version_id=cal.id and w.start_utc=(attendance->>'start_utc')::timestamptz
   and w.end_utc=(attendance->>'end_utc')::timestamptz
   and w.break_seconds=people.work_break_seconds(w.start_utc,w.end_utc,attendance->'breaks')) then
   raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
 end if;
 perform projects.payroll_billing_impact(t,e,b,pr.id,r.id,
  (proposal-'operational_mode')||jsonb_build_object('billing_credit_line_ids',credit_ids),'apply');
 digest:=encode(extensions.digest((after_body||jsonb_build_object('correction_id',correction,'revision_id',revision_id,'supersedes_id',r.id))::text,'sha256'),'hex');
 insert into projects.time_revisions(id,tenant_id,legal_entity_id,project_id,entry_id,version,plan_id,task_id,resource_slot_id,
  start_local,end_local,start_offset_seconds,end_offset_seconds,start_utc,end_utc,breaks,payable_seconds,attendance_claim_id,bill_amount,digest,reason,supersedes_id,recorded_by)
 values(revision_id,t,e,pr.id,entry.id,entry.version+1,r.plan_id,r.task_id,r.resource_slot_id,start_local,end_local,
  (target->>'start_offset_seconds')::integer,(target->>'end_offset_seconds')::integer,start_utc,end_utc,breaks,seconds,
  case when direct_claim then null else new_claim end,bill_amount,digest,'Linked sealed payroll source correction',r.id,auth.uid());
 insert into projects.time_costs values(t,e,pr.id,entry.id,revision_id,cost_rate,cost_amount);
 if not remove_source then
  cursor_utc:=start_utc;
  for break_row in select value from jsonb_array_elements(breaks||jsonb_build_array(jsonb_build_object('start_utc',end_utc,'end_utc',end_utc))) loop
   break_start:=(break_row->>'start_utc')::timestamptz;break_end:=(break_row->>'end_utc')::timestamptz;
   if break_start>cursor_utc then link:=gen_random_uuid();
    allocation:=people.allocate_work(t,e,b,employee,new_claim,'project',link,cursor_utc,break_start,auth.uid());
    insert into projects.time_allocations values(link,t,e,pr.id,entry.id,revision_id,allocation,new_claim,direct_claim);
   end if;cursor_utc:=break_end;
  end loop;
  unit:=gen_random_uuid();insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,
   source_version,source_digest,amount,payable_seconds) values(unit,t,e,pr.id,b,'time',revision_id,entry.version+1,digest,bill_amount,seconds);
 end if;
 perform people.consume_organization(t,e,b,employee,'project_time',revision_id,start_local::date,(end_local-interval '1 microsecond')::date+1);
 update projects.time_entries set current_revision_id=revision_id,version=version+1,status=case when remove_source then 'cancelled' else 'approved' end where id=entry.id;
 insert into projects.time_events(tenant_id,legal_entity_id,project_id,entry_id,revision_id,action,version,reason,actor_id,command_id)
 values(t,e,pr.id,entry.id,r.id,'time_cancel',entry.version+1,'Superseded by linked payroll correction',auth.uid(),gen_random_uuid());
 if not remove_source then insert into projects.time_events(tenant_id,legal_entity_id,project_id,entry_id,revision_id,action,version,reason,actor_id,command_id)
  values(t,e,pr.id,entry.id,revision_id,'time_approve',entry.version+1,'Independently approved linked payroll correction',auth.uid(),gen_random_uuid());end if;
 body:=body||jsonb_build_object('claim_id',new_claim,'replacement_unit_id',unit);
 if pr.status='closed' and not remove_source then
  update projects.register set status='open',version=version+1 where id=pr.id;
  body:=body||jsonb_build_object('project_reopened_for_financial_review',true);
 end if;
 insert into projects.payroll_time_impacts(tenant_id,legal_entity_id,branch_id,project_id,entry_id,correction_id,original_revision_id,replacement_revision_id,mode,body,actor_id)
 values(t,e,b,pr.id,entry.id,correction,r.id,revision_id,actual_mode,body,auth.uid());
 return body;
end $$;

create function projects.payroll_impact(t uuid,e uuid,b uuid,employee uuid,claim uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$declare entry uuid;begin
 select x.id into entry from projects.time_entries x join projects.time_revisions r on r.id=x.current_revision_id
  join people.work_claims w on w.source_id=r.id where w.id=claim and w.source_kind='project' and w.active
   and x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.employee_id=employee;
 if entry is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
 return projects.payroll_revision_impact(t,e,b,employee,entry,claim,revision,proposal,p_mode,true);
end $$;
create function projects.payroll_allocation_impact(t uuid,e uuid,b uuid,employee uuid,allocation_id uuid,revision uuid,proposal jsonb,p_mode text)
returns jsonb language plpgsql security definer set search_path='' as $$declare a people.work_allocations%rowtype;entry uuid;body jsonb;begin
 select * into a from people.work_allocations w where w.id=allocation_id and w.tenant_id=t and w.legal_entity_id=e
  and w.branch_id=b and w.employee_id=employee and w.source_kind='project';
 select x.entry_id into entry from projects.time_allocations x where x.allocation_id=a.id and not x.direct_claim;
 if entry is null then raise exception using errcode='55000',message='PROJECT_ATTENDANCE_SOURCE_INVALID';end if;
 body:=projects.payroll_revision_impact(t,e,b,employee,entry,
  coalesce((proposal->>'current_claim_id')::uuid,a.claim_id),revision,proposal,p_mode,false);
 return body||jsonb_build_object('allocation_id',a.id);
end $$;
revoke all on function projects.payroll_impact_guard(uuid,uuid,uuid,uuid,uuid,uuid),
 projects.payroll_revision_impact(uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,boolean),
 projects.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),
 projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)
 from public,anon,authenticated,service_role;

-- Uninstalled additive milestone candidate. Requires projects/time and finance.
-- Existing permission codes are used; no role, plan, entitlement or provider activation.
create table projects.milestones(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 version bigint not null default 1 check(version between 1 and 9007199254740990),current_revision_id uuid not null,
 status text not null default 'draft' check(status in('draft','submitted','approved','rejected','cancelled')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),submitted_by uuid references auth.users(id),
 unique(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table projects.milestone_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,milestone_id uuid not null,version bigint not null,
 plan_id uuid not null,task_id uuid not null,task_name text not null,owner_id uuid not null,owner_name text not null,
 customer_id uuid not null,customer_name text not null,currency_code text not null references core.currencies(code),precision integer not null check(precision between 0 and 6),
 name text not null,due_date date not null,amount numeric(20,6) not null check(amount>=0),commercial_terms text not null,
 payment_terms text not null,payment_due_days integer not null check(payment_due_days between 0 and 365),evidence_reference text not null,
 digest text not null check(digest~'^[a-f0-9]{64}$'),reason text not null,supersedes_id uuid references projects.milestone_revisions(id),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,project_id,milestone_id,id),unique(milestone_id,version),
 foreign key(tenant_id,legal_entity_id,project_id,milestone_id) references projects.milestones(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,task_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id),
 foreign key(tenant_id,legal_entity_id,owner_id) references people.employees(tenant_id,legal_entity_id,id),foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id)
);
alter table projects.milestones add constraint milestone_current_revision foreign key(tenant_id,legal_entity_id,project_id,id,current_revision_id)
 references projects.milestone_revisions(tenant_id,legal_entity_id,project_id,milestone_id,id) deferrable initially deferred;
create table projects.milestone_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 milestone_id uuid not null,revision_id uuid not null,version bigint not null,action text not null,digest text not null,reason text not null,
 eligibility jsonb not null default '{}',actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(milestone_id,version),foreign key(tenant_id,legal_entity_id,project_id,milestone_id,revision_id)
 references projects.milestone_revisions(tenant_id,legal_entity_id,project_id,milestone_id,id)
);
create index milestone_scope_idx on projects.milestones(tenant_id,legal_entity_id,branch_id,project_id,id);
create index milestone_revision_scope_idx on projects.milestone_revisions(tenant_id,legal_entity_id,project_id,milestone_id,id);
create index milestone_event_scope_idx on projects.milestone_events(tenant_id,legal_entity_id,branch_id,project_id,milestone_id,id);
do $$declare n text;begin foreach n in array array['milestones','milestone_revisions','milestone_events'] loop
 execute format('alter table projects.%I enable row level security',n);execute format('alter table projects.%I force row level security',n);
 execute format('revoke all on projects.%I from public,anon,authenticated,service_role',n);
 if n<>'milestones' then execute format('create trigger immutable before update or delete on projects.%I for each row execute function projects.immutable()',n);end if;
end loop;end $$;
create function projects.milestone_cap(a text) returns text language sql immutable set search_path='' as $$
 select case when a in('create','correct','submit','cancel') then 'projects.manage' when a in('approve','reject') then 'projects.approve' end $$;
create function projects.milestone_summary(p uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',m.id,'tenant_id',m.tenant_id,'legal_entity_id',m.legal_entity_id,'branch_id',m.branch_id,'project_id',m.project_id,
 'version',m.version,'status',m.status,'revision_id',r.id,'plan_id',r.plan_id,'task_id',r.task_id,'task_name',r.task_name,'owner_id',r.owner_id,'owner_name',r.owner_name,
 'customer_id',r.customer_id,'customer_name',r.customer_name,'currency_code',r.currency_code,'precision',r.precision,'name',r.name,'due_date',r.due_date,
 'amount',r.amount::text,'commercial_terms',r.commercial_terms,'payment_terms',r.payment_terms,'payment_due_days',r.payment_due_days,
 'evidence_reference',r.evidence_reference,'digest',r.digest,'recorded_by',r.recorded_by,'reason',r.reason,'unit_status',u.status)
 from projects.milestones m join projects.milestone_revisions r on r.id=m.current_revision_id
 left join projects.billable_units u on u.source_kind='milestone' and u.source_id=r.id where m.id=p $$;
create function projects.milestone_owner(t uuid,e uuid,b uuid,employee uuid,d date) returns text language plpgsql security definer set search_path='' as $$
declare answer text;begin
 select x.display_name into answer from people.employees x where x.tenant_id=t and x.legal_entity_id=e and x.id=employee
 and exists(select 1 from people.employment_assignments a join people.employment_spells s on s.id=a.spell_id
  where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and a.employee_id=x.id
  and daterange(a.start_date,a.end_date_exclusive,'[)') @> d and daterange(s.start_date,s.end_date_exclusive,'[)') @> d);
 if answer is null then raise exception using errcode='55000',message='MILESTONE_OWNER_COVERAGE_REQUIRED';end if;return answer;end $$;
create function api.project_milestone_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare act text:=p_payload->>'action';id uuid;project uuid;cap text;hash text;replay jsonb;reason text;allowed text[];
 pr projects.register%rowtype;m projects.milestones%rowtype;r projects.milestone_revisions%rowtype;task projects.tasks%rowtype;
 new_revision uuid:=gen_random_uuid();owner uuid;owner_name text;customer_name text;amount numeric;due date;digest text;version bigint;
 before_state jsonb:='{}';after_state jsonb;progress projects.task_progress%rowtype;eligibility jsonb:='{}';begin
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>65536 or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 then
  raise exception using errcode='22023',message='MILESTONE_COMMAND_INVALID';end if;
 cap:=projects.milestone_cap(act);perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 id:=(p_payload->>'id')::uuid;project:=(p_payload->>'project_id')::uuid;reason:=projects.text(p_payload->'reason',1000);
 if id is null or project is null then raise exception using errcode='22023',message='MILESTONE_ID_REQUIRED';end if;
 allowed:=case when act in('create','correct') then array['action','id','project_id','plan_id','task_id','owner_id','name','due_date','amount','commercial_terms','payment_terms','payment_due_days','evidence_reference','reason'] else array['action','id','project_id','digest','reason'] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then raise exception using errcode='22023',message='MILESTONE_FIELDS_INVALID';end if;
 hash:=core.wave3_request_hash('projects.milestone.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'projects.milestone.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 select x.* into m from projects.milestones x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.project_id=project and x.id=id;
 select x.* into r from projects.milestone_revisions x where x.id=m.current_revision_id;
 owner:=case when act in('create','correct') then(p_payload->>'owner_id')::uuid else r.owner_id end;
 perform x.id from people.employees x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.id=owner for update;
 select x.* into pr from projects.register x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.id=project for update;
 if pr.id is null then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 if pr.status<>'open' then raise exception using errcode='55000',message='PROJECT_CLOSED';end if;
 select x.* into m from projects.milestones x where x.id=id and x.project_id=project for update;
 if act='create' then
  if m.id is not null or p_expected_version<>0 then raise exception using errcode='40001',message='MILESTONE_VERSION_CONFLICT';end if;version:=1;
 else
  if m.id is null then raise exception using errcode='P0002',message='MILESTONE_NOT_FOUND';end if;
  before_state:=jsonb_build_object('id',m.id,'version',m.version,'status',m.status,'revision_id',m.current_revision_id);
  perform core.wave3_assert_expected_version(m.version,p_expected_version,before_state);version:=m.version+1;
 end if;
 if act in('create','correct') then
  if act='correct' then
   if m.status not in('draft','rejected','approved') then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   if exists(select 1 from projects.billable_units where source_kind='milestone' and source_id=m.current_revision_id and status not in('available','cancelled')) then
    raise exception using errcode='55000',message='MILESTONE_BILLING_IMPACT_REQUIRED';end if;
   update projects.billable_units set status='cancelled' where source_kind='milestone' and source_id=m.current_revision_id and status='available';
  end if;
  if pr.customer_id is null or pr.current_plan_id is distinct from(p_payload->>'plan_id')::uuid or not exists(select 1 from projects.plans x where x.id=pr.current_plan_id and x.status='approved') then
   raise exception using errcode='55000',message='MILESTONE_APPROVED_PLAN_REQUIRED';end if;
  select x.* into task from projects.tasks x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.project_id=project and x.plan_id=pr.current_plan_id and x.id=(p_payload->>'task_id')::uuid;
  if coalesce(p_payload->>'due_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception using errcode='22023',message='MILESTONE_DUE_TASK_INVALID';end if;
  due:=(p_payload->>'due_date')::date;
  if task.id is null or due is null or due<task.start_date or due>=task.end_date_exclusive or due<pr.start_date or due>=pr.end_date_exclusive then
   raise exception using errcode='22023',message='MILESTONE_DUE_TASK_INVALID';end if;
  owner_name:=projects.milestone_owner(p_tenant_id,p_legal_entity_id,p_branch_id,owner,due);
  select x.display_name into customer_name from crm.parties x where x.tenant_id=p_tenant_id and x.id=pr.customer_id and x.status='active' and x.kind in('customer','both');
  if customer_name is null then raise exception using errcode='55000',message='MILESTONE_ACTIVE_CUSTOMER_REQUIRED';end if;
  amount:=projects.amount(p_payload->'amount');if amount<>projects.ratio(amount*1000000,1,pr.precision) then raise exception using errcode='22023',message='PROJECT_AMOUNT_PRECISION';end if;
  if jsonb_typeof(p_payload->'payment_due_days') is distinct from 'number' or coalesce(p_payload->>'payment_due_days','') !~ '^(0|[1-9][0-9]{0,2})$'
   or(p_payload->>'payment_due_days')::integer>365 then raise exception using errcode='22023',message='MILESTONE_PAYMENT_DAYS_INVALID';end if;
  digest:=encode(extensions.digest((p_payload||jsonb_build_object('customer_id',pr.customer_id,'currency_code',pr.currency_code,'precision',pr.precision,'plan_terms',(select terms from projects.plans where id=pr.current_plan_id)))::text,'sha256'),'hex');
  if act='create' then insert into projects.milestones(id,tenant_id,legal_entity_id,branch_id,project_id,current_revision_id,created_by)
   values(id,p_tenant_id,p_legal_entity_id,p_branch_id,project,new_revision,auth.uid());end if;
  insert into projects.milestone_revisions(id,tenant_id,legal_entity_id,project_id,milestone_id,version,plan_id,task_id,task_name,owner_id,owner_name,customer_id,customer_name,
   currency_code,precision,name,due_date,amount,commercial_terms,payment_terms,payment_due_days,evidence_reference,digest,reason,supersedes_id,recorded_by)
  values(new_revision,p_tenant_id,p_legal_entity_id,project,id,version,pr.current_plan_id,task.id,task.name,owner,owner_name,pr.customer_id,customer_name,pr.currency_code,pr.precision,
   projects.text(p_payload->'name',160),due,amount,projects.text(p_payload->'commercial_terms',2000),projects.text(p_payload->'payment_terms',1000),
   (p_payload->>'payment_due_days')::integer,projects.text(p_payload->'evidence_reference',160),digest,reason,m.current_revision_id,auth.uid());
  if act='correct' then update projects.milestones set current_revision_id=new_revision,version=version,status='draft',submitted_by=null where milestones.id=id;end if;
 else
  if r.digest is distinct from p_payload->>'digest' then raise exception using errcode='40001',message='MILESTONE_VERSION_CONFLICT';end if;
  if act='submit' then
   if m.status<>'draft' then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   update projects.milestones set status='submitted',submitted_by=auth.uid(),version=version where milestones.id=id;
  elsif act in('approve','reject') then
   if m.status<>'submitted' then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   if auth.uid() in(r.recorded_by,m.submitted_by) then raise exception using errcode='42501',message='MILESTONE_INDEPENDENT_APPROVAL_REQUIRED';end if;
   if act='approve' then
    if pr.current_plan_id is distinct from r.plan_id or not exists(select 1 from projects.plans where plans.id=r.plan_id and status='approved') then raise exception using errcode='55000',message='MILESTONE_APPROVED_PLAN_REQUIRED';end if;
    select x.* into progress from projects.task_progress x where x.project_id=project and x.plan_id=r.plan_id and x.task_id=r.task_id order by x.project_version desc limit 1;
    if progress.id is null or progress.progress<>10000 then raise exception using errcode='55000',message='MILESTONE_TASK_INCOMPLETE';end if;
    perform projects.milestone_owner(p_tenant_id,p_legal_entity_id,p_branch_id,r.owner_id,r.due_date);
    if not exists(select 1 from crm.parties x where x.tenant_id=p_tenant_id and x.id=r.customer_id and x.status='active' and x.kind in('customer','both')) then
     raise exception using errcode='55000',message='MILESTONE_ACTIVE_CUSTOMER_REQUIRED';end if;
    eligibility:=jsonb_build_object('plan_id',r.plan_id,'task_id',r.task_id,'progress_event_id',progress.id,'project_version',pr.version,'progress',10000,'completion_evidence',r.evidence_reference);
    insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount)
     values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,project,p_branch_id,'milestone',r.id,version,r.digest,r.amount);
   end if;
   update projects.milestones set status=case act when 'approve' then 'approved' else 'rejected' end,version=version where milestones.id=id;
  elsif act='cancel' then
   if m.status='cancelled' then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   if exists(select 1 from projects.billable_units where source_kind='milestone' and source_id=r.id and status not in('available','cancelled')) then raise exception using errcode='55000',message='MILESTONE_BILLING_IMPACT_REQUIRED';end if;
   update projects.billable_units set status='cancelled' where source_kind='milestone' and source_id=r.id and status='available';
   update projects.milestones set status='cancelled',version=version where milestones.id=id;
  end if;
  new_revision:=r.id;digest:=r.digest;
 end if;
 insert into projects.milestone_events(tenant_id,legal_entity_id,branch_id,project_id,milestone_id,revision_id,version,action,digest,reason,eligibility,actor_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,project,id,new_revision,version,act,digest,reason,eligibility,auth.uid());
 select jsonb_build_object('id',x.id,'tenant_id',x.tenant_id,'legal_entity_id',x.legal_entity_id,'branch_id',x.branch_id,'project_id',x.project_id,
 'version',x.version,'status',x.status,'revision_id',x.current_revision_id) into after_state from projects.milestones x where x.id=id;
 return core.wave3_finish_command(p_tenant_id,'projects.milestone.'||act,p_command_id,'projects.milestone',id,p_idempotency_key,hash,before_state,after_state,p_legal_entity_id,p_branch_id);
end $$;
create function api.project_milestones(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 if not exists(select 1 from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_project_id) then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 select coalesce(jsonb_agg(projects.milestone_summary(x.id) order by x.id),'[]') into items from(select id from projects.milestones where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=p_project_id and(p_after is null or id>p_after) order by id limit 50) x;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,'items',items,'next_after',case when jsonb_array_length(items)=50 then items->49->>'id' end);end $$;
create function api.project_milestone_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_id uuid,p_after uuid default null,p_kind text default 'events')
returns jsonb language plpgsql stable security definer set search_path='' as $$declare body jsonb;events jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 if not exists(select 1 from projects.milestones where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=p_project_id and id=p_id) then raise exception using errcode='P0002',message='MILESTONE_NOT_FOUND';end if;
 body:=projects.milestone_summary(p_id);
 if p_kind='events' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into events from(select * from projects.milestone_events where milestone_id=p_id and(p_after is null or id>p_after) order by id limit 50) x;
 elsif p_kind='revisions' then
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('amount',x.amount::text) order by x.id),'[]') into events from(select * from projects.milestone_revisions where milestone_id=p_id and(p_after is null or id>p_after) order by id limit 50) x;
 else raise exception using errcode='22023',message='MILESTONE_DETAIL_KIND_INVALID';end if;
 return jsonb_build_object('record',body,'kind',p_kind,'rows',events,'next_after',case when jsonb_array_length(events)=50 then events->49->>'id' end);end $$;
create function api.project_milestone_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_idempotency_key uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare body jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,projects.milestone_cap(p_action),true);
 select response into body from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
 and actor_id=auth.uid() and command_name='projects.milestone.'||p_action and idempotency_key=p_idempotency_key and(response#>>'{entity,project_id}')::uuid=p_project_id;
 return body;end $$;
create function projects.milestone_billing_terms(t uuid,e uuid,b uuid,source uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare body jsonb;begin
 select jsonb_build_object('customer_id',r.customer_id,'currency_code',r.currency_code,'amount',r.amount::text,'source_version',u.source_version,'digest',r.digest,
 'payment_due_days',r.payment_due_days,'payment_terms',r.payment_terms) into body
 from projects.milestone_revisions r join projects.milestones m on m.id=r.milestone_id join projects.billable_units u on u.source_id=r.id and u.source_kind='milestone'
 where m.tenant_id=t and m.legal_entity_id=e and m.branch_id=b and r.id=source
 and u.tenant_id=t and u.legal_entity_id=e and u.branch_id=b and u.project_id=m.project_id and u.source_digest=r.digest and u.amount=r.amount
 and exists(select 1 from projects.milestone_events a where a.milestone_id=m.id and a.revision_id=r.id and a.version=u.source_version and a.action='approve' and a.digest=r.digest);
 if body is null then raise exception using errcode='55000',message='MILESTONE_BILLING_SOURCE_CHANGED';end if;return body;end $$;
create function projects.milestone_closure_guard(t uuid,e uuid,project uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from projects.milestones where tenant_id=t and legal_entity_id=e and project_id=project and status in('draft','submitted','rejected'))
 or exists(select 1 from projects.billable_units where tenant_id=t and legal_entity_id=e and project_id=project and source_kind='milestone' and status in('available','reserved')) then
  raise exception using errcode='55000',message='MILESTONE_CLOSURE_IMPACT_REQUIRED';end if;end $$;
revoke all on function projects.milestone_cap(text),projects.milestone_summary(uuid),projects.milestone_owner(uuid,uuid,uuid,uuid,date),
 projects.milestone_billing_terms(uuid,uuid,uuid,uuid),projects.milestone_closure_guard(uuid,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function api.project_milestone_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.project_milestones(uuid,uuid,uuid,uuid,uuid),
 api.project_milestone_detail(uuid,uuid,uuid,uuid,uuid,uuid,text),api.project_milestone_own_receipt(uuid,uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function api.project_milestone_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.project_milestones(uuid,uuid,uuid,uuid,uuid),
 api.project_milestone_detail(uuid,uuid,uuid,uuid,uuid,uuid,text),api.project_milestone_own_receipt(uuid,uuid,uuid,uuid,uuid,text) to authenticated;

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
 if p_project_id is null and p_capability='projects.expenses.retention.manage' then
  perform core.wave3_require_scope(p_tenant_id,'projects.expenses.retention.manage',p_legal_entity_id,null);end if;
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

create temporary table w4_composition_assertions(message text);
select no_plan();
insert into w4_composition_assertions select is((select count(*)::integer from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname||'.'||c.relname in('assets.approvals','assets.books','assets.effects','assets.locations','assets.opening_sources','assets.proposals','assets.register','assets.schedules','expense_private.documents','expense_private.events','expense_private.policies','expense_private.purge_jobs','expense_private.tickets','expense_private.worker_readiness','people.attendance_entries','people.attendance_events','people.attendance_revisions','people.department_revisions','people.departments','people.leave_accounts','people.leave_adjustments','people.leave_carry_events','people.leave_effects','people.leave_events','people.leave_grants','people.leave_policies','people.leave_policy_versions','people.leave_requests','people.organization_assignments','people.organization_consumptions','people.organization_withdrawals','people.raw_clock_batch_rows','people.raw_clock_batches','people.raw_clock_events','people.work_allocations','people.work_claim_segments','people.work_claims','people.work_input_seals','people_payroll.component_assignments','people_payroll.components','people_payroll.correction_balance_effects','people_payroll.correction_balances','people_payroll.correction_events','people_payroll.correction_payslips','people_payroll.correction_settlement_allocations','people_payroll.correction_settlements','people_payroll.correction_source_effects','people_payroll.correction_sources','people_payroll.corrections','people_payroll.employee_calculations','people_payroll.exports','people_payroll.obligation_effects','people_payroll.obligations','people_payroll.payslips','people_payroll.rule_versions','people_payroll.run_employees','people_payroll.run_events','people_payroll.run_revisions','people_payroll.runs','people_payroll.settings_versions','people_payroll.settlement_allocations','people_payroll.settlements','projects.billable_units','projects.billing_batches','projects.billing_intents','projects.billing_links','projects.cost_basis','projects.dependencies','projects.expense_allocations','projects.expense_decisions','projects.expense_ownership','projects.expense_revisions','projects.expense_settlements','projects.expenses','projects.finance_events','projects.milestone_events','projects.milestone_revisions','projects.milestones','projects.payroll_billing_effects','projects.payroll_time_impacts','projects.plan_decisions','projects.plans','projects.register','projects.reimbursement_effects','projects.reimbursements','projects.resource_costs','projects.resource_slots','projects.service_cost_revisions','projects.task_progress','projects.tasks','projects.time_allocations','projects.time_costs','projects.time_entries','projects.time_events','projects.time_revisions','projects.unit_decisions','service.asset_equipment_links','service.coverage_versions','service.dispatch_bookings','service.equipment','service.events','service.labor','service.labor_allocations','service.labor_revisions','service.maintenance_occurrences','service.maintenance_plans','service.meter_readings','service.payroll_labor_impacts','service.sla_policies','service.tickets','service.work_orders')),111,'All candidate tables compose together');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname||'.'||c.relname in('assets.approvals','assets.books','assets.effects','assets.locations','assets.opening_sources','assets.proposals','assets.register','assets.schedules','expense_private.documents','expense_private.events','expense_private.policies','expense_private.purge_jobs','expense_private.tickets','expense_private.worker_readiness','people.attendance_entries','people.attendance_events','people.attendance_revisions','people.department_revisions','people.departments','people.leave_accounts','people.leave_adjustments','people.leave_carry_events','people.leave_effects','people.leave_events','people.leave_grants','people.leave_policies','people.leave_policy_versions','people.leave_requests','people.organization_assignments','people.organization_consumptions','people.organization_withdrawals','people.raw_clock_batch_rows','people.raw_clock_batches','people.raw_clock_events','people.work_allocations','people.work_claim_segments','people.work_claims','people.work_input_seals','people_payroll.component_assignments','people_payroll.components','people_payroll.correction_balance_effects','people_payroll.correction_balances','people_payroll.correction_events','people_payroll.correction_payslips','people_payroll.correction_settlement_allocations','people_payroll.correction_settlements','people_payroll.correction_source_effects','people_payroll.correction_sources','people_payroll.corrections','people_payroll.employee_calculations','people_payroll.exports','people_payroll.obligation_effects','people_payroll.obligations','people_payroll.payslips','people_payroll.rule_versions','people_payroll.run_employees','people_payroll.run_events','people_payroll.run_revisions','people_payroll.runs','people_payroll.settings_versions','people_payroll.settlement_allocations','people_payroll.settlements','projects.billable_units','projects.billing_batches','projects.billing_intents','projects.billing_links','projects.cost_basis','projects.dependencies','projects.expense_allocations','projects.expense_decisions','projects.expense_ownership','projects.expense_revisions','projects.expense_settlements','projects.expenses','projects.finance_events','projects.milestone_events','projects.milestone_revisions','projects.milestones','projects.payroll_billing_effects','projects.payroll_time_impacts','projects.plan_decisions','projects.plans','projects.register','projects.reimbursement_effects','projects.reimbursements','projects.resource_costs','projects.resource_slots','projects.service_cost_revisions','projects.task_progress','projects.tasks','projects.time_allocations','projects.time_costs','projects.time_entries','projects.time_events','projects.time_revisions','projects.unit_decisions','service.asset_equipment_links','service.coverage_versions','service.dispatch_bookings','service.equipment','service.events','service.labor','service.labor_allocations','service.labor_revisions','service.maintenance_occurrences','service.maintenance_plans','service.meter_readings','service.payroll_labor_impacts','service.sla_policies','service.tickets','service.work_orders') and(not c.relrowsecurity or not c.relforcerowsecurity)),'Every candidate tenant table forces RLS');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname||'.'||c.relname in('assets.approvals','assets.books','assets.effects','assets.locations','assets.opening_sources','assets.proposals','assets.register','assets.schedules','expense_private.documents','expense_private.events','expense_private.policies','expense_private.purge_jobs','expense_private.tickets','expense_private.worker_readiness','people.attendance_entries','people.attendance_events','people.attendance_revisions','people.department_revisions','people.departments','people.leave_accounts','people.leave_adjustments','people.leave_carry_events','people.leave_effects','people.leave_events','people.leave_grants','people.leave_policies','people.leave_policy_versions','people.leave_requests','people.organization_assignments','people.organization_consumptions','people.organization_withdrawals','people.raw_clock_batch_rows','people.raw_clock_batches','people.raw_clock_events','people.work_allocations','people.work_claim_segments','people.work_claims','people.work_input_seals','people_payroll.component_assignments','people_payroll.components','people_payroll.correction_balance_effects','people_payroll.correction_balances','people_payroll.correction_events','people_payroll.correction_payslips','people_payroll.correction_settlement_allocations','people_payroll.correction_settlements','people_payroll.correction_source_effects','people_payroll.correction_sources','people_payroll.corrections','people_payroll.employee_calculations','people_payroll.exports','people_payroll.obligation_effects','people_payroll.obligations','people_payroll.payslips','people_payroll.rule_versions','people_payroll.run_employees','people_payroll.run_events','people_payroll.run_revisions','people_payroll.runs','people_payroll.settings_versions','people_payroll.settlement_allocations','people_payroll.settlements','projects.billable_units','projects.billing_batches','projects.billing_intents','projects.billing_links','projects.cost_basis','projects.dependencies','projects.expense_allocations','projects.expense_decisions','projects.expense_ownership','projects.expense_revisions','projects.expense_settlements','projects.expenses','projects.finance_events','projects.milestone_events','projects.milestone_revisions','projects.milestones','projects.payroll_billing_effects','projects.payroll_time_impacts','projects.plan_decisions','projects.plans','projects.register','projects.reimbursement_effects','projects.reimbursements','projects.resource_costs','projects.resource_slots','projects.service_cost_revisions','projects.task_progress','projects.tasks','projects.time_allocations','projects.time_costs','projects.time_entries','projects.time_events','projects.time_revisions','projects.unit_decisions','service.asset_equipment_links','service.coverage_versions','service.dispatch_bookings','service.equipment','service.events','service.labor','service.labor_allocations','service.labor_revisions','service.maintenance_occurrences','service.maintenance_plans','service.meter_readings','service.payroll_labor_impacts','service.sla_policies','service.tickets','service.work_orders') and(has_table_privilege('authenticated',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'INSERT') or has_table_privilege('authenticated',c.oid,'UPDATE') or has_table_privilege('authenticated',c.oid,'DELETE'))),'Authenticated callers cannot bypass candidate APIs through tables');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname in('api.assets_authorize','api.assets_command','api.assets_detail','api.assets_own_receipt','api.assets_pickers','api.assets_register','api.assets_schedule','api.people_attendance_clock_batch','api.people_attendance_clock_batch_detail','api.people_attendance_clock_batches','api.people_attendance_command','api.people_attendance_detail','api.people_attendance_entries','api.people_attendance_raw_events','api.people_calendar_local_candidates','api.people_leave_balance','api.people_leave_detail','api.people_leave_grant_command','api.people_leave_own_receipt','api.people_leave_policies','api.people_leave_policy_command','api.people_leave_policy_for_version','api.people_leave_policy_versions','api.people_leave_request_command','api.people_leave_requests','api.people_organization_command','api.people_organization_department','api.people_organization_department_history','api.people_organization_departments','api.people_organization_employee','api.people_payroll_accounts','api.people_payroll_assignments','api.people_payroll_authorize','api.people_payroll_calculation','api.people_payroll_command','api.people_payroll_configure','api.people_payroll_correction_authorize','api.people_payroll_correction_command','api.people_payroll_correction_detail','api.people_payroll_correction_originals','api.people_payroll_correction_own_receipt','api.people_payroll_correction_settlement','api.people_payroll_correction_sources','api.people_payroll_corrections','api.people_payroll_export','api.people_payroll_export_content','api.people_payroll_history','api.people_payroll_obligations','api.people_payroll_own_receipt','api.people_payroll_payslip','api.people_payroll_payslips','api.people_payroll_rules','api.people_payroll_run_detail','api.people_payroll_runs','api.people_payroll_self_payslips','api.people_payroll_settlement','api.people_payroll_settlements','api.people_payroll_snapshot','api.people_work_claims','api.people_workforce_authorize','api.project_milestone_command','api.project_milestone_detail','api.project_milestone_own_receipt','api.project_milestones','api.projects_attendance_claims','api.projects_authorize','api.projects_calendar_candidates','api.projects_command','api.projects_detail','api.projects_directory','api.projects_expense_evidence_access','api.projects_expense_evidence_command','api.projects_expense_evidence_list','api.projects_expense_evidence_own_receipt','api.projects_expense_evidence_service_document','api.projects_expense_evidence_service_verify','api.projects_expense_evidence_ticket','api.projects_expense_evidence_worker_claim','api.projects_expense_evidence_worker_complete','api.projects_expense_evidence_worker_register','api.projects_finance_authorize','api.projects_finance_command','api.projects_finance_detail','api.projects_finance_own_receipt','api.projects_finance_pickers','api.projects_margin','api.projects_own_receipt','api.projects_payroll_credit_choices','api.projects_pickers','api.service_asset_authorize','api.service_asset_equipment_command','api.service_asset_link','api.service_asset_own_receipt','api.service_asset_sources','api.service_authorize','api.service_choices','api.service_command','api.service_command_customer_base','api.service_detail','api.service_list','api.service_own_receipt','api.service_own_receipt_customer_base','assets.account','assets.amount','assets.book_validate','assets.immutable','assets.label','assets.materialize_book','assets.place','assets.ratio','assets.require_access','assets.round_even','assets.schedule','assets.snapshot','assets.summary','expense_private.document_guard','expense_private.lock_scope','expense_private.proof','expense_private.ready','expense_private.require_access','expense_private.service_only','expense_private.summary','expense_private.ticket_authority','expense_private.user_has','people.allocate_leave','people.allocate_work','people.assert_organization','people.attendance_payload','people.check_organization_compatibility','people.clock_batch_payload','people.consume_organization','people.guard_organization_consumption','people.guard_organization_revision','people.leave_available','people.leave_effect_insert_guard','people.leave_history_guard','people.leave_policy_payload','people.leave_request_private','people.leave_request_summary','people.leave_slot_charge','people.local_instant_candidates','people.make_work_claim','people.organization_assignment_payload','people.resolve_local_instant','people.revoke_work_allocation','people.revoke_work_claim','people.work_break_seconds','people.work_history_guard','people.work_local_coverage','people_payroll.account','people_payroll.amount','people_payroll.approved_source','people_payroll.calculate','people_payroll.correction_access','people_payroll.correction_billing_permission','people_payroll.correction_difference','people_payroll.correction_guard','people_payroll.correction_source_permission','people_payroll.correction_source_prepare','people_payroll.correction_source_state','people_payroll.correction_summary','people_payroll.current_allocation_credits','people_payroll.current_credit_ids','people_payroll.digest','people_payroll.effect_guard','people_payroll.freeze','people_payroll.immutable','people_payroll.linked_allocation_bound','people_payroll.original_run_correction_guard','people_payroll.payslip_payload','people_payroll.replace_claim','people_payroll.require_access','people_payroll.round_ratio','people_payroll.rule_payload','people_payroll.run_summary','people_payroll.source_impact','projects.amount','projects.billing_source_impact','projects.command_cap','projects.expense_evidence_assert','projects.expense_proofs','projects.expense_summary','projects.finance_access','projects.finance_account','projects.finance_cap','projects.finance_closure_guard','projects.immutable','projects.linked_invoice_guard','projects.linked_invoice_insert_guard','projects.milestone_billing_terms','projects.milestone_cap','projects.milestone_closure_guard','projects.milestone_owner','projects.milestone_summary','projects.milestone_terms','projects.payroll_allocation_impact','projects.payroll_billing_impact','projects.payroll_impact','projects.payroll_impact_guard','projects.payroll_revision_impact','projects.payroll_source','projects.plan_guard','projects.ratio','projects.require_access','projects.service_payroll_billing_impact','projects.service_payroll_cost_impact','projects.slot_guard','projects.slot_validate','projects.summary','projects.task_owner_validate','projects.text','projects.time_summary','service.amount','service.assert_billing_mutable','service.asset_equipment_for','service.asset_equipment_guard','service.asset_read_allowed','service.asset_source','service.billing_source','service.billing_source_customer_base','service.capability','service.check_customer','service.consume_billing_source','service.due','service.elapsed','service.fields','service.immutable','service.integer','service.internal_labor_invariant','service.internal_ticket_invariant','service.payroll_allocation_impact','service.payroll_billing_impact','service.payroll_impact','service.payroll_impact_guard','service.payroll_revision_impact','service.payroll_source','service.public_snapshot','service.public_snapshot_customer_base','service.require_access','service.round_ratio','service.snapshot','service.table_for','service.text','service.ticket_create','service.ticket_create_customer','service.utc','service.windows') and n.nspname='api' and(not p.prosecdef or not coalesce(p.proconfig @> array['search_path=""'],false))),'All candidate API functions have protected empty search paths');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname in('api.assets_authorize','api.assets_command','api.assets_detail','api.assets_own_receipt','api.assets_pickers','api.assets_register','api.assets_schedule','api.people_attendance_clock_batch','api.people_attendance_clock_batch_detail','api.people_attendance_clock_batches','api.people_attendance_command','api.people_attendance_detail','api.people_attendance_entries','api.people_attendance_raw_events','api.people_calendar_local_candidates','api.people_leave_balance','api.people_leave_detail','api.people_leave_grant_command','api.people_leave_own_receipt','api.people_leave_policies','api.people_leave_policy_command','api.people_leave_policy_for_version','api.people_leave_policy_versions','api.people_leave_request_command','api.people_leave_requests','api.people_organization_command','api.people_organization_department','api.people_organization_department_history','api.people_organization_departments','api.people_organization_employee','api.people_payroll_accounts','api.people_payroll_assignments','api.people_payroll_authorize','api.people_payroll_calculation','api.people_payroll_command','api.people_payroll_configure','api.people_payroll_correction_authorize','api.people_payroll_correction_command','api.people_payroll_correction_detail','api.people_payroll_correction_originals','api.people_payroll_correction_own_receipt','api.people_payroll_correction_settlement','api.people_payroll_correction_sources','api.people_payroll_corrections','api.people_payroll_export','api.people_payroll_export_content','api.people_payroll_history','api.people_payroll_obligations','api.people_payroll_own_receipt','api.people_payroll_payslip','api.people_payroll_payslips','api.people_payroll_rules','api.people_payroll_run_detail','api.people_payroll_runs','api.people_payroll_self_payslips','api.people_payroll_settlement','api.people_payroll_settlements','api.people_payroll_snapshot','api.people_work_claims','api.people_workforce_authorize','api.project_milestone_command','api.project_milestone_detail','api.project_milestone_own_receipt','api.project_milestones','api.projects_attendance_claims','api.projects_authorize','api.projects_calendar_candidates','api.projects_command','api.projects_detail','api.projects_directory','api.projects_expense_evidence_access','api.projects_expense_evidence_command','api.projects_expense_evidence_list','api.projects_expense_evidence_own_receipt','api.projects_expense_evidence_service_document','api.projects_expense_evidence_service_verify','api.projects_expense_evidence_ticket','api.projects_expense_evidence_worker_claim','api.projects_expense_evidence_worker_complete','api.projects_expense_evidence_worker_register','api.projects_finance_authorize','api.projects_finance_command','api.projects_finance_detail','api.projects_finance_own_receipt','api.projects_finance_pickers','api.projects_margin','api.projects_own_receipt','api.projects_payroll_credit_choices','api.projects_pickers','api.service_asset_authorize','api.service_asset_equipment_command','api.service_asset_link','api.service_asset_own_receipt','api.service_asset_sources','api.service_authorize','api.service_choices','api.service_command','api.service_command_customer_base','api.service_detail','api.service_list','api.service_own_receipt','api.service_own_receipt_customer_base','assets.account','assets.amount','assets.book_validate','assets.immutable','assets.label','assets.materialize_book','assets.place','assets.ratio','assets.require_access','assets.round_even','assets.schedule','assets.snapshot','assets.summary','expense_private.document_guard','expense_private.lock_scope','expense_private.proof','expense_private.ready','expense_private.require_access','expense_private.service_only','expense_private.summary','expense_private.ticket_authority','expense_private.user_has','people.allocate_leave','people.allocate_work','people.assert_organization','people.attendance_payload','people.check_organization_compatibility','people.clock_batch_payload','people.consume_organization','people.guard_organization_consumption','people.guard_organization_revision','people.leave_available','people.leave_effect_insert_guard','people.leave_history_guard','people.leave_policy_payload','people.leave_request_private','people.leave_request_summary','people.leave_slot_charge','people.local_instant_candidates','people.make_work_claim','people.organization_assignment_payload','people.resolve_local_instant','people.revoke_work_allocation','people.revoke_work_claim','people.work_break_seconds','people.work_history_guard','people.work_local_coverage','people_payroll.account','people_payroll.amount','people_payroll.approved_source','people_payroll.calculate','people_payroll.correction_access','people_payroll.correction_billing_permission','people_payroll.correction_difference','people_payroll.correction_guard','people_payroll.correction_source_permission','people_payroll.correction_source_prepare','people_payroll.correction_source_state','people_payroll.correction_summary','people_payroll.current_allocation_credits','people_payroll.current_credit_ids','people_payroll.digest','people_payroll.effect_guard','people_payroll.freeze','people_payroll.immutable','people_payroll.linked_allocation_bound','people_payroll.original_run_correction_guard','people_payroll.payslip_payload','people_payroll.replace_claim','people_payroll.require_access','people_payroll.round_ratio','people_payroll.rule_payload','people_payroll.run_summary','people_payroll.source_impact','projects.amount','projects.billing_source_impact','projects.command_cap','projects.expense_evidence_assert','projects.expense_proofs','projects.expense_summary','projects.finance_access','projects.finance_account','projects.finance_cap','projects.finance_closure_guard','projects.immutable','projects.linked_invoice_guard','projects.linked_invoice_insert_guard','projects.milestone_billing_terms','projects.milestone_cap','projects.milestone_closure_guard','projects.milestone_owner','projects.milestone_summary','projects.milestone_terms','projects.payroll_allocation_impact','projects.payroll_billing_impact','projects.payroll_impact','projects.payroll_impact_guard','projects.payroll_revision_impact','projects.payroll_source','projects.plan_guard','projects.ratio','projects.require_access','projects.service_payroll_billing_impact','projects.service_payroll_cost_impact','projects.slot_guard','projects.slot_validate','projects.summary','projects.task_owner_validate','projects.text','projects.time_summary','service.amount','service.assert_billing_mutable','service.asset_equipment_for','service.asset_equipment_guard','service.asset_read_allowed','service.asset_source','service.billing_source','service.billing_source_customer_base','service.capability','service.check_customer','service.consume_billing_source','service.due','service.elapsed','service.fields','service.immutable','service.integer','service.internal_labor_invariant','service.internal_ticket_invariant','service.payroll_allocation_impact','service.payroll_billing_impact','service.payroll_impact','service.payroll_impact_guard','service.payroll_revision_impact','service.payroll_source','service.public_snapshot','service.public_snapshot_customer_base','service.require_access','service.round_ratio','service.snapshot','service.table_for','service.text','service.ticket_create','service.ticket_create_customer','service.utc','service.windows') and has_function_privilege('anon',p.oid,'EXECUTE')),'Anonymous callers cannot execute candidate APIs or helpers');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname in('api.assets_authorize','api.assets_command','api.assets_detail','api.assets_own_receipt','api.assets_pickers','api.assets_register','api.assets_schedule','api.people_attendance_clock_batch','api.people_attendance_clock_batch_detail','api.people_attendance_clock_batches','api.people_attendance_command','api.people_attendance_detail','api.people_attendance_entries','api.people_attendance_raw_events','api.people_calendar_local_candidates','api.people_leave_balance','api.people_leave_detail','api.people_leave_grant_command','api.people_leave_own_receipt','api.people_leave_policies','api.people_leave_policy_command','api.people_leave_policy_for_version','api.people_leave_policy_versions','api.people_leave_request_command','api.people_leave_requests','api.people_organization_command','api.people_organization_department','api.people_organization_department_history','api.people_organization_departments','api.people_organization_employee','api.people_payroll_accounts','api.people_payroll_assignments','api.people_payroll_authorize','api.people_payroll_calculation','api.people_payroll_command','api.people_payroll_configure','api.people_payroll_correction_authorize','api.people_payroll_correction_command','api.people_payroll_correction_detail','api.people_payroll_correction_originals','api.people_payroll_correction_own_receipt','api.people_payroll_correction_settlement','api.people_payroll_correction_sources','api.people_payroll_corrections','api.people_payroll_export','api.people_payroll_export_content','api.people_payroll_history','api.people_payroll_obligations','api.people_payroll_own_receipt','api.people_payroll_payslip','api.people_payroll_payslips','api.people_payroll_rules','api.people_payroll_run_detail','api.people_payroll_runs','api.people_payroll_self_payslips','api.people_payroll_settlement','api.people_payroll_settlements','api.people_payroll_snapshot','api.people_work_claims','api.people_workforce_authorize','api.project_milestone_command','api.project_milestone_detail','api.project_milestone_own_receipt','api.project_milestones','api.projects_attendance_claims','api.projects_authorize','api.projects_calendar_candidates','api.projects_command','api.projects_detail','api.projects_directory','api.projects_expense_evidence_access','api.projects_expense_evidence_command','api.projects_expense_evidence_list','api.projects_expense_evidence_own_receipt','api.projects_expense_evidence_service_document','api.projects_expense_evidence_service_verify','api.projects_expense_evidence_ticket','api.projects_expense_evidence_worker_claim','api.projects_expense_evidence_worker_complete','api.projects_expense_evidence_worker_register','api.projects_finance_authorize','api.projects_finance_command','api.projects_finance_detail','api.projects_finance_own_receipt','api.projects_finance_pickers','api.projects_margin','api.projects_own_receipt','api.projects_payroll_credit_choices','api.projects_pickers','api.service_asset_authorize','api.service_asset_equipment_command','api.service_asset_link','api.service_asset_own_receipt','api.service_asset_sources','api.service_authorize','api.service_choices','api.service_command','api.service_command_customer_base','api.service_detail','api.service_list','api.service_own_receipt','api.service_own_receipt_customer_base','assets.account','assets.amount','assets.book_validate','assets.immutable','assets.label','assets.materialize_book','assets.place','assets.ratio','assets.require_access','assets.round_even','assets.schedule','assets.snapshot','assets.summary','expense_private.document_guard','expense_private.lock_scope','expense_private.proof','expense_private.ready','expense_private.require_access','expense_private.service_only','expense_private.summary','expense_private.ticket_authority','expense_private.user_has','people.allocate_leave','people.allocate_work','people.assert_organization','people.attendance_payload','people.check_organization_compatibility','people.clock_batch_payload','people.consume_organization','people.guard_organization_consumption','people.guard_organization_revision','people.leave_available','people.leave_effect_insert_guard','people.leave_history_guard','people.leave_policy_payload','people.leave_request_private','people.leave_request_summary','people.leave_slot_charge','people.local_instant_candidates','people.make_work_claim','people.organization_assignment_payload','people.resolve_local_instant','people.revoke_work_allocation','people.revoke_work_claim','people.work_break_seconds','people.work_history_guard','people.work_local_coverage','people_payroll.account','people_payroll.amount','people_payroll.approved_source','people_payroll.calculate','people_payroll.correction_access','people_payroll.correction_billing_permission','people_payroll.correction_difference','people_payroll.correction_guard','people_payroll.correction_source_permission','people_payroll.correction_source_prepare','people_payroll.correction_source_state','people_payroll.correction_summary','people_payroll.current_allocation_credits','people_payroll.current_credit_ids','people_payroll.digest','people_payroll.effect_guard','people_payroll.freeze','people_payroll.immutable','people_payroll.linked_allocation_bound','people_payroll.original_run_correction_guard','people_payroll.payslip_payload','people_payroll.replace_claim','people_payroll.require_access','people_payroll.round_ratio','people_payroll.rule_payload','people_payroll.run_summary','people_payroll.source_impact','projects.amount','projects.billing_source_impact','projects.command_cap','projects.expense_evidence_assert','projects.expense_proofs','projects.expense_summary','projects.finance_access','projects.finance_account','projects.finance_cap','projects.finance_closure_guard','projects.immutable','projects.linked_invoice_guard','projects.linked_invoice_insert_guard','projects.milestone_billing_terms','projects.milestone_cap','projects.milestone_closure_guard','projects.milestone_owner','projects.milestone_summary','projects.milestone_terms','projects.payroll_allocation_impact','projects.payroll_billing_impact','projects.payroll_impact','projects.payroll_impact_guard','projects.payroll_revision_impact','projects.payroll_source','projects.plan_guard','projects.ratio','projects.require_access','projects.service_payroll_billing_impact','projects.service_payroll_cost_impact','projects.slot_guard','projects.slot_validate','projects.summary','projects.task_owner_validate','projects.text','projects.time_summary','service.amount','service.assert_billing_mutable','service.asset_equipment_for','service.asset_equipment_guard','service.asset_read_allowed','service.asset_source','service.billing_source','service.billing_source_customer_base','service.capability','service.check_customer','service.consume_billing_source','service.due','service.elapsed','service.fields','service.immutable','service.integer','service.internal_labor_invariant','service.internal_ticket_invariant','service.payroll_allocation_impact','service.payroll_billing_impact','service.payroll_impact','service.payroll_impact_guard','service.payroll_revision_impact','service.payroll_source','service.public_snapshot','service.public_snapshot_customer_base','service.require_access','service.round_ratio','service.snapshot','service.table_for','service.text','service.ticket_create','service.ticket_create_customer','service.utc','service.windows') and n.nspname<>'api' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'Authenticated callers cannot bypass named APIs through owner helpers');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname in('api.assets_authorize','api.assets_command','api.assets_detail','api.assets_own_receipt','api.assets_pickers','api.assets_register','api.assets_schedule','api.people_attendance_clock_batch','api.people_attendance_clock_batch_detail','api.people_attendance_clock_batches','api.people_attendance_command','api.people_attendance_detail','api.people_attendance_entries','api.people_attendance_raw_events','api.people_calendar_local_candidates','api.people_leave_balance','api.people_leave_detail','api.people_leave_grant_command','api.people_leave_own_receipt','api.people_leave_policies','api.people_leave_policy_command','api.people_leave_policy_for_version','api.people_leave_policy_versions','api.people_leave_request_command','api.people_leave_requests','api.people_organization_command','api.people_organization_department','api.people_organization_department_history','api.people_organization_departments','api.people_organization_employee','api.people_payroll_accounts','api.people_payroll_assignments','api.people_payroll_authorize','api.people_payroll_calculation','api.people_payroll_command','api.people_payroll_configure','api.people_payroll_correction_authorize','api.people_payroll_correction_command','api.people_payroll_correction_detail','api.people_payroll_correction_originals','api.people_payroll_correction_own_receipt','api.people_payroll_correction_settlement','api.people_payroll_correction_sources','api.people_payroll_corrections','api.people_payroll_export','api.people_payroll_export_content','api.people_payroll_history','api.people_payroll_obligations','api.people_payroll_own_receipt','api.people_payroll_payslip','api.people_payroll_payslips','api.people_payroll_rules','api.people_payroll_run_detail','api.people_payroll_runs','api.people_payroll_self_payslips','api.people_payroll_settlement','api.people_payroll_settlements','api.people_payroll_snapshot','api.people_work_claims','api.people_workforce_authorize','api.project_milestone_command','api.project_milestone_detail','api.project_milestone_own_receipt','api.project_milestones','api.projects_attendance_claims','api.projects_authorize','api.projects_calendar_candidates','api.projects_command','api.projects_detail','api.projects_directory','api.projects_expense_evidence_access','api.projects_expense_evidence_command','api.projects_expense_evidence_list','api.projects_expense_evidence_own_receipt','api.projects_expense_evidence_service_document','api.projects_expense_evidence_service_verify','api.projects_expense_evidence_ticket','api.projects_expense_evidence_worker_claim','api.projects_expense_evidence_worker_complete','api.projects_expense_evidence_worker_register','api.projects_finance_authorize','api.projects_finance_command','api.projects_finance_detail','api.projects_finance_own_receipt','api.projects_finance_pickers','api.projects_margin','api.projects_own_receipt','api.projects_payroll_credit_choices','api.projects_pickers','api.service_asset_authorize','api.service_asset_equipment_command','api.service_asset_link','api.service_asset_own_receipt','api.service_asset_sources','api.service_authorize','api.service_choices','api.service_command','api.service_command_customer_base','api.service_detail','api.service_list','api.service_own_receipt','api.service_own_receipt_customer_base','assets.account','assets.amount','assets.book_validate','assets.immutable','assets.label','assets.materialize_book','assets.place','assets.ratio','assets.require_access','assets.round_even','assets.schedule','assets.snapshot','assets.summary','expense_private.document_guard','expense_private.lock_scope','expense_private.proof','expense_private.ready','expense_private.require_access','expense_private.service_only','expense_private.summary','expense_private.ticket_authority','expense_private.user_has','people.allocate_leave','people.allocate_work','people.assert_organization','people.attendance_payload','people.check_organization_compatibility','people.clock_batch_payload','people.consume_organization','people.guard_organization_consumption','people.guard_organization_revision','people.leave_available','people.leave_effect_insert_guard','people.leave_history_guard','people.leave_policy_payload','people.leave_request_private','people.leave_request_summary','people.leave_slot_charge','people.local_instant_candidates','people.make_work_claim','people.organization_assignment_payload','people.resolve_local_instant','people.revoke_work_allocation','people.revoke_work_claim','people.work_break_seconds','people.work_history_guard','people.work_local_coverage','people_payroll.account','people_payroll.amount','people_payroll.approved_source','people_payroll.calculate','people_payroll.correction_access','people_payroll.correction_billing_permission','people_payroll.correction_difference','people_payroll.correction_guard','people_payroll.correction_source_permission','people_payroll.correction_source_prepare','people_payroll.correction_source_state','people_payroll.correction_summary','people_payroll.current_allocation_credits','people_payroll.current_credit_ids','people_payroll.digest','people_payroll.effect_guard','people_payroll.freeze','people_payroll.immutable','people_payroll.linked_allocation_bound','people_payroll.original_run_correction_guard','people_payroll.payslip_payload','people_payroll.replace_claim','people_payroll.require_access','people_payroll.round_ratio','people_payroll.rule_payload','people_payroll.run_summary','people_payroll.source_impact','projects.amount','projects.billing_source_impact','projects.command_cap','projects.expense_evidence_assert','projects.expense_proofs','projects.expense_summary','projects.finance_access','projects.finance_account','projects.finance_cap','projects.finance_closure_guard','projects.immutable','projects.linked_invoice_guard','projects.linked_invoice_insert_guard','projects.milestone_billing_terms','projects.milestone_cap','projects.milestone_closure_guard','projects.milestone_owner','projects.milestone_summary','projects.milestone_terms','projects.payroll_allocation_impact','projects.payroll_billing_impact','projects.payroll_impact','projects.payroll_impact_guard','projects.payroll_revision_impact','projects.payroll_source','projects.plan_guard','projects.ratio','projects.require_access','projects.service_payroll_billing_impact','projects.service_payroll_cost_impact','projects.slot_guard','projects.slot_validate','projects.summary','projects.task_owner_validate','projects.text','projects.time_summary','service.amount','service.assert_billing_mutable','service.asset_equipment_for','service.asset_equipment_guard','service.asset_read_allowed','service.asset_source','service.billing_source','service.billing_source_customer_base','service.capability','service.check_customer','service.consume_billing_source','service.due','service.elapsed','service.fields','service.immutable','service.integer','service.internal_labor_invariant','service.internal_ticket_invariant','service.payroll_allocation_impact','service.payroll_billing_impact','service.payroll_impact','service.payroll_impact_guard','service.payroll_revision_impact','service.payroll_source','service.public_snapshot','service.public_snapshot_customer_base','service.require_access','service.round_ratio','service.snapshot','service.table_for','service.text','service.ticket_create','service.ticket_create_customer','service.utc','service.windows') and n.nspname='api' and p.proname like '%_customer_base' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'Renamed base commands cannot bypass the new internal asset guards');
insert into w4_composition_assertions select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname in('api.assets_authorize','api.assets_command','api.assets_detail','api.assets_own_receipt','api.assets_pickers','api.assets_register','api.assets_schedule','api.people_attendance_clock_batch','api.people_attendance_clock_batch_detail','api.people_attendance_clock_batches','api.people_attendance_command','api.people_attendance_detail','api.people_attendance_entries','api.people_attendance_raw_events','api.people_calendar_local_candidates','api.people_leave_balance','api.people_leave_detail','api.people_leave_grant_command','api.people_leave_own_receipt','api.people_leave_policies','api.people_leave_policy_command','api.people_leave_policy_for_version','api.people_leave_policy_versions','api.people_leave_request_command','api.people_leave_requests','api.people_organization_command','api.people_organization_department','api.people_organization_department_history','api.people_organization_departments','api.people_organization_employee','api.people_payroll_accounts','api.people_payroll_assignments','api.people_payroll_authorize','api.people_payroll_calculation','api.people_payroll_command','api.people_payroll_configure','api.people_payroll_correction_authorize','api.people_payroll_correction_command','api.people_payroll_correction_detail','api.people_payroll_correction_originals','api.people_payroll_correction_own_receipt','api.people_payroll_correction_settlement','api.people_payroll_correction_sources','api.people_payroll_corrections','api.people_payroll_export','api.people_payroll_export_content','api.people_payroll_history','api.people_payroll_obligations','api.people_payroll_own_receipt','api.people_payroll_payslip','api.people_payroll_payslips','api.people_payroll_rules','api.people_payroll_run_detail','api.people_payroll_runs','api.people_payroll_self_payslips','api.people_payroll_settlement','api.people_payroll_settlements','api.people_payroll_snapshot','api.people_work_claims','api.people_workforce_authorize','api.project_milestone_command','api.project_milestone_detail','api.project_milestone_own_receipt','api.project_milestones','api.projects_attendance_claims','api.projects_authorize','api.projects_calendar_candidates','api.projects_command','api.projects_detail','api.projects_directory','api.projects_expense_evidence_access','api.projects_expense_evidence_command','api.projects_expense_evidence_list','api.projects_expense_evidence_own_receipt','api.projects_expense_evidence_service_document','api.projects_expense_evidence_service_verify','api.projects_expense_evidence_ticket','api.projects_expense_evidence_worker_claim','api.projects_expense_evidence_worker_complete','api.projects_expense_evidence_worker_register','api.projects_finance_authorize','api.projects_finance_command','api.projects_finance_detail','api.projects_finance_own_receipt','api.projects_finance_pickers','api.projects_margin','api.projects_own_receipt','api.projects_payroll_credit_choices','api.projects_pickers','api.service_asset_authorize','api.service_asset_equipment_command','api.service_asset_link','api.service_asset_own_receipt','api.service_asset_sources','api.service_authorize','api.service_choices','api.service_command','api.service_command_customer_base','api.service_detail','api.service_list','api.service_own_receipt','api.service_own_receipt_customer_base','assets.account','assets.amount','assets.book_validate','assets.immutable','assets.label','assets.materialize_book','assets.place','assets.ratio','assets.require_access','assets.round_even','assets.schedule','assets.snapshot','assets.summary','expense_private.document_guard','expense_private.lock_scope','expense_private.proof','expense_private.ready','expense_private.require_access','expense_private.service_only','expense_private.summary','expense_private.ticket_authority','expense_private.user_has','people.allocate_leave','people.allocate_work','people.assert_organization','people.attendance_payload','people.check_organization_compatibility','people.clock_batch_payload','people.consume_organization','people.guard_organization_consumption','people.guard_organization_revision','people.leave_available','people.leave_effect_insert_guard','people.leave_history_guard','people.leave_policy_payload','people.leave_request_private','people.leave_request_summary','people.leave_slot_charge','people.local_instant_candidates','people.make_work_claim','people.organization_assignment_payload','people.resolve_local_instant','people.revoke_work_allocation','people.revoke_work_claim','people.work_break_seconds','people.work_history_guard','people.work_local_coverage','people_payroll.account','people_payroll.amount','people_payroll.approved_source','people_payroll.calculate','people_payroll.correction_access','people_payroll.correction_billing_permission','people_payroll.correction_difference','people_payroll.correction_guard','people_payroll.correction_source_permission','people_payroll.correction_source_prepare','people_payroll.correction_source_state','people_payroll.correction_summary','people_payroll.current_allocation_credits','people_payroll.current_credit_ids','people_payroll.digest','people_payroll.effect_guard','people_payroll.freeze','people_payroll.immutable','people_payroll.linked_allocation_bound','people_payroll.original_run_correction_guard','people_payroll.payslip_payload','people_payroll.replace_claim','people_payroll.require_access','people_payroll.round_ratio','people_payroll.rule_payload','people_payroll.run_summary','people_payroll.source_impact','projects.amount','projects.billing_source_impact','projects.command_cap','projects.expense_evidence_assert','projects.expense_proofs','projects.expense_summary','projects.finance_access','projects.finance_account','projects.finance_cap','projects.finance_closure_guard','projects.immutable','projects.linked_invoice_guard','projects.linked_invoice_insert_guard','projects.milestone_billing_terms','projects.milestone_cap','projects.milestone_closure_guard','projects.milestone_owner','projects.milestone_summary','projects.milestone_terms','projects.payroll_allocation_impact','projects.payroll_billing_impact','projects.payroll_impact','projects.payroll_impact_guard','projects.payroll_revision_impact','projects.payroll_source','projects.plan_guard','projects.ratio','projects.require_access','projects.service_payroll_billing_impact','projects.service_payroll_cost_impact','projects.slot_guard','projects.slot_validate','projects.summary','projects.task_owner_validate','projects.text','projects.time_summary','service.amount','service.assert_billing_mutable','service.asset_equipment_for','service.asset_equipment_guard','service.asset_read_allowed','service.asset_source','service.billing_source','service.billing_source_customer_base','service.capability','service.check_customer','service.consume_billing_source','service.due','service.elapsed','service.fields','service.immutable','service.integer','service.internal_labor_invariant','service.internal_ticket_invariant','service.payroll_allocation_impact','service.payroll_billing_impact','service.payroll_impact','service.payroll_impact_guard','service.payroll_revision_impact','service.payroll_source','service.public_snapshot','service.public_snapshot_customer_base','service.require_access','service.round_ratio','service.snapshot','service.table_for','service.text','service.ticket_create','service.ticket_create_customer','service.utc','service.windows') and n.nspname='api' and p.proname ~ '^projects_expense_evidence_(service|worker)_' and has_function_privilege('authenticated',p.oid,'EXECUTE')),'Human callers cannot invoke trusted private byte or worker APIs');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by role_id,permission_code)::text,'')) from core.role_permissions r),(select roles from w4_composition_before),'Existing role grants are unchanged');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by plan_code,entitlement_code)::text,'')) from billing.plan_entitlements r),(select plans from w4_composition_before),'Existing plan entitlements are unchanged');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by tenant_id)::text,'')) from billing.tenant_subscriptions r),(select subscriptions from w4_composition_before),'Existing subscriptions are unchanged');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(to_jsonb(r) order by version)::text,'')) from supabase_migrations.schema_migrations r),(select ledger from w4_composition_before),'Composition verification does not install migrations');
insert into w4_composition_assertions select is((select md5(coalesce(jsonb_agg(jsonb_build_object('id',p.oid,'definition',pg_get_functiondef(p.oid)) order by p.oid)::text,'')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('core','finance') and p.prokind='f' and p.proname ~ '(journal|period|residual|allocate)'),(select finance from w4_composition_before),'Installed finance posting and period providers are unchanged');
insert into w4_composition_assertions select ok((select not public from storage.buckets where id='jentra-project-expense-private') and not exists(select 1 from expense_private.worker_readiness),'Private expense bucket is private and its worker is not activated');
do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from w4_composition_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
select count(*) assertion_count,15 candidate_migrations,111 candidate_tables from w4_composition_assertions;
rollback;
