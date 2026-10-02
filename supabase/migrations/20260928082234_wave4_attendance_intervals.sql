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
