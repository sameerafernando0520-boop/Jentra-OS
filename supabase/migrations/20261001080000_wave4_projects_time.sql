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
