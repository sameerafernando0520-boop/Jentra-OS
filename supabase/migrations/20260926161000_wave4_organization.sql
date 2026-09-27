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
