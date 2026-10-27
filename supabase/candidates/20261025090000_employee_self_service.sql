-- CANDIDATE ONLY. Depends on the installed workforce/private-HR/payroll migrations.
-- No production installation, permission assignment or entitlement change is implied.
create schema employee_self;
revoke all on schema employee_self from public,anon,authenticated,service_role;

insert into core.permissions(code,module,description,privileged) values
 ('people.attendance.self.request','people','Submit own pending attendance evidence; never approve time.',true),
 ('people.leave.self.manage','people','Submit and withdraw own unapproved leave; request approved cancellation.',true)
on conflict(code) do nothing;

-- This helper deliberately never delegates to the broader staff subject endpoints.
-- All public functions revalidate authority before reading a saved command receipt.
create function employee_self.require_subject(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_permission text default 'people.self.view',p_mfa boolean default false) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare employee uuid;session_id uuid;begin
 if auth.uid() is null or coalesce(auth.jwt()->>'session_id','') !~*
  '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  raise exception using errcode='42501',message='EMPLOYEE_SESSION_REQUIRED';end if;
 session_id:=(auth.jwt()->>'session_id')::uuid;
 if not exists(select 1 from auth.sessions s where s.id=session_id and s.user_id=auth.uid()
  and (s.not_after is null or s.not_after>clock_timestamp())) then
  raise exception using errcode='42501',message='EMPLOYEE_SESSION_REQUIRED';end if;
 if p_permission is null or p_permission not in ('people.self.view','people.attendance.self.request',
  'people.leave.self.manage','people.payroll.payslip.self','people.hr.cases.self.manage',
  'people.hr.documents.self.view') then
  raise exception using errcode='42501',message='EMPLOYEE_CAPABILITY_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.self.view');
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_permission);
 if p_mfa and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='EMPLOYEE_MFA_REQUIRED';end if;
 select l.employee_id into employee from people_private.account_links l
 join core.memberships m on m.tenant_id=l.tenant_id and m.id=l.membership_id and m.user_id=l.user_id
 join core.legal_entities e on e.tenant_id=l.tenant_id and e.id=l.legal_entity_id
 where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id
  and l.user_id=auth.uid() and l.status='accepted' and m.status='active'
  and exists(select 1 from people.employment_assignments a join people.employment_spells s
   on s.tenant_id=a.tenant_id and s.legal_entity_id=a.legal_entity_id and s.employee_id=a.employee_id and s.id=a.spell_id
   where a.tenant_id=l.tenant_id and a.legal_entity_id=l.legal_entity_id and a.branch_id=l.branch_id
    and a.employee_id=l.employee_id
    and daterange(a.start_date,a.end_date_exclusive,'[)') @> (statement_timestamp() at time zone e.timezone)::date
    and daterange(s.start_date,s.end_date_exclusive,'[)') @> (statement_timestamp() at time zone e.timezone)::date);
 if employee is null then raise exception using errcode='42501',message='EMPLOYEE_ACTIVE_LINK_REQUIRED';end if;
 return employee;
end $$;

-- Mutations share-lock the accepted link and membership before their final
-- authority check. Revocation/removal then serializes against the command.
create function employee_self.lock_subject(t uuid,e uuid,b uuid,cap text) returns uuid
language plpgsql security definer set search_path='' as $$declare employee uuid;begin
 employee:=employee_self.require_subject(t,e,b,cap,true);
 -- Match the installed private-HR/leave owner order: employee, then link.
 perform p.id from people.employees p where p.tenant_id=t and p.legal_entity_id=e and p.id=employee for update;
 perform l.id from people_private.account_links l join core.memberships m
  on m.tenant_id=l.tenant_id and m.id=l.membership_id and m.user_id=l.user_id
 where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.employee_id=employee
  and l.user_id=auth.uid() and l.status='accepted' and m.status='active' for share of l,m;
 if not found then raise exception using errcode='42501',message='EMPLOYEE_ACTIVE_LINK_REQUIRED';end if;
 return employee_self.require_subject(t,e,b,cap,true);
end $$;

create function employee_self.envelope(t uuid,e uuid,b uuid,employee uuid) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object('tenant_id',t,'legal_entity_id',e,'branch_id',b,'employee_id',employee)
$$;

create table employee_self.receipts(
 user_id uuid not null references auth.users(id),command_id uuid not null,
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,employee_id uuid not null,
 rpc text not null check(rpc in ('employee_self_attendance_request','employee_self_leave_submit','employee_self_leave_intent')),
 request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),response jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '24 hours',
 primary key(user_id,command_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check(expires_at>created_at and expires_at<=created_at+interval '24 hours 1 second')
);
create index employee_self_receipts_scope_idx on employee_self.receipts(tenant_id,legal_entity_id,branch_id,employee_id);
create index employee_self_receipts_employee_idx on employee_self.receipts(tenant_id,legal_entity_id,employee_id);

-- Receipt-only reconciliation closes an absent opaque command under the same
-- advisory lock as dispatch. A delayed original request then cannot commit
-- after the employee has safely cleared its local tombstone.
create table employee_self.abandoned_commands(
 user_id uuid not null references auth.users(id),command_id uuid not null,
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,employee_id uuid not null,
 rpc text not null check(rpc in ('employee_self_attendance_request','employee_self_leave_submit','employee_self_leave_intent','employee_case_command')),
 request_id uuid not null,created_at timestamptz not null default clock_timestamp(),primary key(user_id,command_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index employee_self_abandoned_scope_idx on employee_self.abandoned_commands(tenant_id,legal_entity_id,branch_id,employee_id);
create index employee_self_abandoned_employee_idx on employee_self.abandoned_commands(tenant_id,legal_entity_id,employee_id);

-- Only pending evidence, never raw clock imports, approved intervals or payroll claims.
create table employee_self.attendance_requests(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,employee_id uuid not null,
 action text not null check(action in ('capture','correction')),entry_id uuid,expected_version bigint,
 observed_at timestamptz not null,reason text not null check(length(btrim(reason)) between 1 and 1000),
 status text not null default 'pending_evidence' check(status='pending_evidence'),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 command_id uuid not null,unique(created_by,command_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,entry_id) references people.attendance_entries(tenant_id,legal_entity_id,employee_id,id),
 check((action='capture' and entry_id is null and expected_version is null)
  or (action='correction' and entry_id is not null and expected_version between 1 and 9007199254740991))
);
create index employee_self_attendance_scope_idx on employee_self.attendance_requests(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index employee_self_attendance_source_idx on employee_self.attendance_requests(tenant_id,legal_entity_id,employee_id,entry_id);
create index employee_self_attendance_limit_idx on employee_self.attendance_requests(employee_id,created_at);

create table employee_self.leave_intents(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,employee_id uuid not null,
 request_id uuid not null,request_version bigint not null,action text not null check(action in ('submit','withdraw','cancel_request')),
 status text not null check(status in ('submitted','withdrawn','cancellation_requested')),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),command_id uuid not null,
 unique(created_by,command_id),
 foreign key(tenant_id,legal_entity_id,employee_id,request_id) references people.leave_requests(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index employee_self_leave_intents_scope_idx on employee_self.leave_intents(tenant_id,legal_entity_id,branch_id,employee_id,request_id,id);
create index employee_self_leave_intents_source_idx on employee_self.leave_intents(tenant_id,legal_entity_id,employee_id,request_id);
create unique index employee_self_leave_cancel_once_idx on employee_self.leave_intents(request_id,request_version)
 where action='cancel_request';

create table employee_self.request_resolutions(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('attendance','leave_cancel')),
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,employee_id uuid not null,
 attendance_request_id uuid unique references employee_self.attendance_requests(id),
 leave_intent_id uuid unique references employee_self.leave_intents(id),
 decision text not null check(decision in ('resolved','declined')),canonical_id uuid,canonical_version bigint,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 command_id uuid not null,unique(created_by,command_id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 check((kind='attendance' and attendance_request_id is not null and leave_intent_id is null)
  or (kind='leave_cancel' and leave_intent_id is not null and attendance_request_id is null)),
 check((decision='resolved' and canonical_id is not null and canonical_version between 1 and 9007199254740991)
  or (decision='declined' and canonical_id is null and canonical_version is null))
);
create index employee_self_resolutions_scope_idx on employee_self.request_resolutions(tenant_id,legal_entity_id,branch_id,employee_id);
create index employee_self_resolutions_employee_idx on employee_self.request_resolutions(tenant_id,legal_entity_id,employee_id);
create table employee_self.staff_receipts(
 user_id uuid not null references auth.users(id),command_id uuid not null,
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 request_hash text not null check(request_hash ~ '^[a-f0-9]{64}$'),response jsonb not null,
 created_at timestamptz not null default clock_timestamp(),primary key(user_id,command_id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index employee_self_staff_receipts_scope_idx on employee_self.staff_receipts(tenant_id,legal_entity_id,branch_id);

create function employee_self.immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception using errcode='55000',message='EMPLOYEE_HISTORY_IMMUTABLE';end $$;
create trigger employee_self_attendance_immutable before update or delete on employee_self.attendance_requests
 for each row execute function employee_self.immutable();
create trigger employee_self_leave_intents_immutable before update or delete on employee_self.leave_intents
 for each row execute function employee_self.immutable();
create trigger employee_self_receipts_immutable before update or delete on employee_self.receipts
 for each row execute function employee_self.immutable();
create trigger employee_self_abandoned_immutable before update or delete on employee_self.abandoned_commands
 for each row execute function employee_self.immutable();
create trigger employee_self_resolutions_immutable before update or delete on employee_self.request_resolutions
 for each row execute function employee_self.immutable();
create trigger employee_self_staff_receipts_immutable before update or delete on employee_self.staff_receipts
 for each row execute function employee_self.immutable();
do $$declare item regclass;begin
 foreach item in array array['employee_self.receipts'::regclass,'employee_self.abandoned_commands'::regclass,
  'employee_self.attendance_requests'::regclass,'employee_self.leave_intents'::regclass,
  'employee_self.request_resolutions'::regclass,'employee_self.staff_receipts'::regclass] loop
  execute format('alter table %s enable row level security',item);
  execute format('alter table %s force row level security',item);
  execute format('revoke all on %s from public,anon,authenticated,service_role',item);
 end loop;
end $$;

create function employee_self.request_hash(t uuid,e uuid,b uuid,employee uuid,action text,body jsonb) returns text
language sql immutable set search_path='' as $$
 select encode(extensions.digest(convert_to(jsonb_build_array(t,e,b,employee,action,body)::text,'UTF8'),'sha256'),'hex')
$$;
create function employee_self.replay(command uuid,request_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$declare receipt employee_self.receipts%rowtype;begin
 if command is null then raise exception using errcode='22023',message='EMPLOYEE_COMMAND_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('employee-self-command:'||auth.uid()::text||command::text,0));
 if exists(select 1 from employee_self.abandoned_commands a where a.user_id=auth.uid() and a.command_id=command) then
  raise exception using errcode='55000',message='EMPLOYEE_COMMAND_ABANDONED';end if;
 select * into receipt from employee_self.receipts r where r.user_id=auth.uid() and r.command_id=command;
 if receipt.command_id is null then return null;end if;
 if receipt.request_hash<>request_hash then raise exception using errcode='22023',message='EMPLOYEE_COMMAND_REUSED';end if;
 if receipt.expires_at<=statement_timestamp() then raise exception using errcode='55000',message='EMPLOYEE_COMMAND_EXPIRED';end if;
 return receipt.response;
end $$;
create function employee_self.finish(t uuid,e uuid,b uuid,employee uuid,command uuid,request_hash text,response jsonb,p_rpc text) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 insert into employee_self.receipts(user_id,command_id,tenant_id,legal_entity_id,branch_id,employee_id,request_hash,response,rpc)
 values(auth.uid(),command,t,e,b,employee,request_hash,response,p_rpc);
 return response;
end $$;

create function api.employee_self_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_request_id uuid,p_rpc text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid;cap text;receipt employee_self.receipts%rowtype;closed employee_self.abandoned_commands%rowtype;begin
 cap:=case p_rpc when 'employee_self_attendance_request' then 'people.attendance.self.request'
  when 'employee_self_leave_submit' then 'people.leave.self.manage' when 'employee_self_leave_intent' then 'people.leave.self.manage' end;
 if cap is null or p_command_id is null or p_request_id is null then
  raise exception using errcode='22023',message='EMPLOYEE_RECEIPT_INVALID';end if;
 employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,cap);
 perform pg_advisory_xact_lock(hashtextextended('employee-self-command:'||auth.uid()::text||p_command_id::text,0));
 -- A queued lookup may have waited for an in-flight command to settle.
 perform employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 select * into receipt from employee_self.receipts r where r.user_id=auth.uid() and r.command_id=p_command_id;
 if found then
  if receipt.tenant_id<>p_tenant_id or receipt.legal_entity_id<>p_legal_entity_id or receipt.branch_id<>p_branch_id
   or receipt.employee_id<>employee or receipt.rpc<>p_rpc or receipt.response->>'request_id' is distinct from p_request_id::text then
   raise exception using errcode='42501',message='EMPLOYEE_RECEIPT_DENIED';end if;
  return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('command_id',p_command_id,
   'request_id',p_request_id,'rpc',p_rpc,'receipt',receipt.response,'abandoned',false);
 end if;
 select * into closed from employee_self.abandoned_commands a where a.user_id=auth.uid() and a.command_id=p_command_id;
 if found then
  if closed.tenant_id<>p_tenant_id or closed.legal_entity_id<>p_legal_entity_id or closed.branch_id<>p_branch_id
   or closed.employee_id<>employee or closed.rpc<>p_rpc or closed.request_id<>p_request_id then
   raise exception using errcode='42501',message='EMPLOYEE_RECEIPT_DENIED';end if;
 else
  insert into employee_self.abandoned_commands(user_id,command_id,tenant_id,legal_entity_id,branch_id,employee_id,rpc,request_id)
  values(auth.uid(),p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_rpc,p_request_id);
 end if;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('command_id',p_command_id,
  'request_id',p_request_id,'rpc',p_rpc,'receipt',null,'abandoned',true);
end $$;

create function employee_self.resolution_payload(p_kind text,p_id uuid) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',r.id,'status',r.decision,'canonical_id',r.canonical_id,
  'canonical_version',r.canonical_version,'reason',r.reason,'recorded_at',r.created_at)
 from employee_self.request_resolutions r where r.kind=p_kind
  and case when p_kind='attendance' then r.attendance_request_id=p_id else r.leave_intent_id=p_id end
$$;

create function api.employee_self_attendance(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;items jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_after is not null and not exists(select 1 from people.attendance_entries a where a.id=p_after
  and a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=employee) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(people.attendance_payload(q.id) order by q.id),'[]') into items
 from(select a.id from people.attendance_entries a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.branch_id=p_branch_id and a.employee_id=employee and (p_after is null or a.id>p_after) order by a.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

create function api.employee_self_attendance_requests(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;items jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_after is not null and not exists(select 1 from employee_self.attendance_requests a where a.id=p_after
  and a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=employee) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'action',q.action,'entry_id',q.entry_id,'expected_version',q.expected_version,
  'observed_at',q.observed_at,'reason',q.reason,'status',coalesce(employee_self.resolution_payload('attendance',q.id)->>'status',q.status),
  'version',case when employee_self.resolution_payload('attendance',q.id) is null then 1 else 2 end,
  'resolution',employee_self.resolution_payload('attendance',q.id),'created_at',q.created_at) order by q.id),'[]') into items
 from(select a.* from employee_self.attendance_requests a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.branch_id=p_branch_id and a.employee_id=employee and (p_after is null or a.id>p_after) order by a.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

create function api.employee_self_attendance_request(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_request_id uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare employee uuid;h text;answer jsonb;entry people.attendance_entries%rowtype;
 observed timestamptz;begin
 employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.self.request');
 perform people_private.fields(p_payload,array['action','entry_id','expected_version','observed_at','reason']);
 if p_request_id is null or coalesce(p_payload->>'action','') not in ('capture','correction')
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000
  or coalesce(p_payload->>'observed_at','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' then
  raise exception using errcode='22023',message='ATTENDANCE_REQUEST_INVALID';end if;
 h:=employee_self.request_hash(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'attendance_request',
  jsonb_build_array(p_request_id,p_payload));
 answer:=employee_self.replay(p_command_id,h);if answer is not null then return answer;end if;
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=employee for update;
 if (select count(*) from employee_self.attendance_requests a where a.employee_id=employee
  and a.created_at>statement_timestamp()-interval '31 days')>=500 then
  raise exception using errcode='54000',message='ATTENDANCE_REQUEST_LIMIT';end if;
 observed:=(p_payload->>'observed_at')::timestamptz;
 if not isfinite(observed) or observed>statement_timestamp()+interval '5 minutes' or observed<statement_timestamp()-interval '31 days' then
  raise exception using errcode='22023',message='ATTENDANCE_REQUEST_TIME_INVALID';end if;
 if p_payload->>'action'='correction' then
  if coalesce(p_payload->>'entry_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(p_payload->>'expected_version','') !~ '^[0-9]{1,16}$' then
   raise exception using errcode='22023',message='ATTENDANCE_REQUEST_INVALID';end if;
  select * into entry from people.attendance_entries a where a.id=(p_payload->>'entry_id')::uuid
   and a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=employee for update;
  if entry.id is null then raise exception using errcode='42501',message='EMPLOYEE_SUBJECT_DENIED';end if;
  perform core.wave3_assert_expected_version(entry.version,(p_payload->>'expected_version')::bigint,'{}');
 elsif p_payload ? 'entry_id' or p_payload ? 'expected_version' then
  raise exception using errcode='22023',message='ATTENDANCE_REQUEST_FIELDS_INVALID';end if;
 insert into employee_self.attendance_requests(id,tenant_id,legal_entity_id,branch_id,employee_id,action,entry_id,
  expected_version,observed_at,reason,created_by,command_id)
 values(p_request_id,p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_payload->>'action',entry.id,
  case when entry.id is not null then entry.version end,observed,btrim(p_payload->>'reason'),auth.uid(),p_command_id);
 answer:=employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object(
  'command_id',p_command_id,'request_id',p_request_id,'version',1,'status','pending_evidence','payable_time_changed',false);
 return employee_self.finish(p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_command_id,h,answer,'employee_self_attendance_request');
end $$;

create function api.employee_self_leave_policies(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_as_of date default null,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;items jsonb;as_of_date date;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 select coalesce(p_as_of,(statement_timestamp() at time zone b.timezone)::date) into as_of_date
 from core.branches b where b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id and b.id=p_branch_id;
 if as_of_date is null or not isfinite(as_of_date) then raise exception using errcode='22023',message='LEAVE_DATE_INVALID';end if;
 if p_after is not null and not exists(select 1 from people.leave_policies p where p.id=p_after
  and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(q.item order by q.id),'[]') into items from(
  select p.id,jsonb_build_object('id',p.id,'policy_version_id',v.id,'version',v.version,'code',p.code,'name',p.name,'as_of',as_of_date,
   'unit',v.unit,'day_seconds',v.day_seconds,'allow_unpaid',v.allow_unpaid,'start_date',v.start_date,'end_date_exclusive',v.end_date_exclusive,
   'calendar_version_id',c.id,'timezone',c.timezone,'weekly_intervals',c.weekly_intervals,'date_overrides',c.date_overrides) item
  from people.leave_policies p join people.leave_policy_versions v on v.tenant_id=p.tenant_id and v.legal_entity_id=p.legal_entity_id and v.policy_id=p.id
  join people.employment_assignments a on a.tenant_id=p.tenant_id and a.legal_entity_id=p.legal_entity_id and a.employee_id=employee and a.branch_id=p_branch_id
  join people.organization_assignments o on o.tenant_id=a.tenant_id and o.legal_entity_id=a.legal_entity_id and o.branch_id=a.branch_id and o.employee_id=a.employee_id
  join people.work_calendar_versions c on c.tenant_id=o.tenant_id and c.legal_entity_id=o.legal_entity_id and c.id=o.calendar_version_id
  where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and (p_after is null or p.id>p_after)
   and daterange(v.start_date,v.end_date_exclusive,'[)') @> as_of_date
   and daterange(a.start_date,a.end_date_exclusive,'[)') @> as_of_date and a.employment_type=any(v.eligible_types)
   and o.superseded_at is null and daterange(o.start_date,o.end_date_exclusive,'[)') @> as_of_date
   and daterange(c.start_date,c.end_date_exclusive,'[)') @> as_of_date order by p.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('as_of',as_of_date,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

create function api.employee_self_leave_balance(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_policy_id uuid,p_as_of date default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;account_version bigint;reserved bigint;as_of_date date;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 select coalesce(p_as_of,(statement_timestamp() at time zone b.timezone)::date) into as_of_date
 from core.branches b where b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id and b.id=p_branch_id;
 if as_of_date is null or not isfinite(as_of_date) or p_policy_id is null or not exists(select 1 from people.leave_policies p
  where p.id=p_policy_id and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id) then
  raise exception using errcode='22023',message='LEAVE_POLICY_INVALID';end if;
 select a.version into account_version from people.leave_accounts a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.employee_id=employee and a.policy_id=p_policy_id;
 select coalesce(sum(r.charge_seconds),0)::bigint into reserved from people.leave_requests r where r.tenant_id=p_tenant_id
  and r.legal_entity_id=p_legal_entity_id and r.employee_id=employee and r.policy_id=p_policy_id and r.status='submitted';
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('policy_id',p_policy_id,'as_of',as_of_date,
  'available_seconds',people.leave_available(p_tenant_id,p_legal_entity_id,employee,p_policy_id,as_of_date),
  'account_version',coalesce(account_version,0),'reserved_seconds',reserved,'approval_required',true);
end $$;

create function api.employee_self_leave_requests(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;items jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_after is not null and not exists(select 1 from people.leave_requests r where r.id=p_after and r.tenant_id=p_tenant_id
  and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.employee_id=employee) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(people.leave_request_private(q.id)||jsonb_build_object('cancellation_request',(
  select jsonb_build_object('id',i.id,'status',coalesce(employee_self.resolution_payload('leave_cancel',i.id)->>'status',i.status),
   'requested_at',i.created_at,'resolution',employee_self.resolution_payload('leave_cancel',i.id))
  from employee_self.leave_intents i where i.request_id=q.id and i.action='cancel_request' order by i.created_at desc,i.id desc limit 1)) order by q.id),'[]') into items from(
  select r.id from people.leave_requests r where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id
   and r.branch_id=p_branch_id and r.employee_id=employee and (p_after is null or r.id>p_after) order by r.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

create function api.employee_self_leave_submit(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_request_id uuid,p_payload jsonb,p_expected_balance_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid;policy people.leave_policy_versions%rowtype;calendar people.work_calendar_versions%rowtype;
 account people.leave_accounts%rowtype;v_start_local timestamp;v_end_local timestamp;v_start_utc timestamptz;v_end_utc timestamptz;
 charge bigint;reserved bigint;h text;answer jsonb;begin
 employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.self.manage');
 perform people_private.fields(p_payload,array['policy_version_id','calendar_version_id','start_local','end_local',
  'start_offset_seconds','end_offset_seconds','reason']);
 if p_request_id is null or p_expected_balance_version is null or p_expected_balance_version<0
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000
  or coalesce(p_payload->>'policy_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'calendar_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'start_local','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'
  or coalesce(p_payload->>'end_local','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'
  or coalesce(p_payload->>'start_offset_seconds','') !~ '^-?[0-9]{1,5}$'
  or coalesce(p_payload->>'end_offset_seconds','') !~ '^-?[0-9]{1,5}$' then
  raise exception using errcode='22023',message='LEAVE_SUBMISSION_INVALID';end if;
 h:=employee_self.request_hash(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'leave_submit',
  jsonb_build_array(p_request_id,p_payload,p_expected_balance_version));
 answer:=employee_self.replay(p_command_id,h);if answer is not null then return answer;end if;
 -- Same employee serialization lock as approval, grant and correction owners.
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=employee for update;
 if (select count(*) from people.leave_requests r where r.employee_id=employee and r.status='submitted')>=100 then
  raise exception using errcode='54000',message='LEAVE_PENDING_LIMIT';end if;
 select * into policy from people.leave_policy_versions v where v.tenant_id=p_tenant_id and v.legal_entity_id=p_legal_entity_id
  and v.id=(p_payload->>'policy_version_id')::uuid;
 select * into calendar from people.work_calendar_versions c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
  and c.id=(p_payload->>'calendar_version_id')::uuid;
 if policy.id is null or calendar.id is null then raise exception using errcode='22023',message='LEAVE_CONFIGURATION_INVALID';end if;
 v_start_local:=(p_payload->>'start_local')::timestamp;v_end_local:=(p_payload->>'end_local')::timestamp;
 v_start_utc:=people.resolve_local_instant(calendar.timezone,v_start_local,(p_payload->>'start_offset_seconds')::integer);
 v_end_utc:=people.resolve_local_instant(calendar.timezone,v_end_local,(p_payload->>'end_offset_seconds')::integer);
 if v_start_utc<statement_timestamp()-interval '31 days' or v_start_utc>statement_timestamp()+interval '366 days' then
  raise exception using errcode='22023',message='LEAVE_SUBMISSION_WINDOW_INVALID';end if;
 charge:=people.leave_slot_charge(p_tenant_id,p_legal_entity_id,p_branch_id,employee,policy.id,calendar.id,
  v_start_local,v_end_local,v_start_utc,v_end_utc);
 if exists(select 1 from people.leave_requests r where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id
  and r.employee_id=employee and r.status in ('submitted','approved')
  and tstzrange(r.start_utc,r.end_utc,'[)') && tstzrange(v_start_utc,v_end_utc,'[)'))
  or exists(select 1 from people.work_claim_segments s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id
   and s.employee_id=employee and s.active and tstzrange(s.start_utc,s.end_utc,'[)') && tstzrange(v_start_utc,v_end_utc,'[)')) then
  raise exception using errcode='23514',message='WORK_INTERVAL_CONFLICT';end if;
 insert into people.leave_accounts(tenant_id,legal_entity_id,employee_id,policy_id)
  values(p_tenant_id,p_legal_entity_id,employee,policy.policy_id) on conflict do nothing;
 select * into account from people.leave_accounts a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.employee_id=employee and a.policy_id=policy.policy_id for update;
 perform core.wave3_assert_expected_version(account.version,p_expected_balance_version,jsonb_build_object('account_version',account.version));
 select coalesce(sum(r.charge_seconds),0)::bigint into reserved from people.leave_requests r where r.tenant_id=p_tenant_id
  and r.legal_entity_id=p_legal_entity_id and r.employee_id=employee and r.policy_id=policy.policy_id and r.status='submitted';
 if not policy.allow_unpaid and people.leave_available(p_tenant_id,p_legal_entity_id,employee,policy.policy_id,v_start_local::date)-reserved<charge then
  raise exception using errcode='23514',message='LEAVE_BALANCE_INSUFFICIENT';end if;
 insert into people.leave_requests(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,policy_version_id,calendar_version_id,
  start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,charge_seconds,status,reason,submitted_by,created_by)
 values(p_request_id,p_tenant_id,p_legal_entity_id,p_branch_id,employee,policy.policy_id,policy.id,calendar.id,
  v_start_local,(p_payload->>'start_offset_seconds')::integer,v_end_local,(p_payload->>'end_offset_seconds')::integer,
  v_start_utc,v_end_utc,charge,'submitted',btrim(p_payload->>'reason'),auth.uid(),auth.uid());
 insert into people.leave_events(tenant_id,legal_entity_id,branch_id,employee_id,request_id,action,before_status,after_status,reason,actor_id,command_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_request_id,'submit',null,'submitted',btrim(p_payload->>'reason'),auth.uid(),p_command_id);
 insert into employee_self.leave_intents(id,tenant_id,legal_entity_id,branch_id,employee_id,request_id,request_version,action,status,reason,created_by,command_id)
 values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_request_id,1,'submit','submitted',btrim(p_payload->>'reason'),auth.uid(),p_command_id);
 answer:=employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('command_id',p_command_id,
  'request_id',p_request_id,'version',1,'status','submitted','charge_seconds',charge,'approval_required',true);
 return employee_self.finish(p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_command_id,h,answer,'employee_self_leave_submit');
end $$;

create function api.employee_self_leave_intent(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_request_id uuid,p_action text,p_expected_version bigint,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid;r people.leave_requests%rowtype;h text;answer jsonb;result_status text;begin
 employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.self.manage');
 if p_request_id is null or p_action is null or p_action not in ('withdraw','cancel_request')
  or p_expected_version is null or p_expected_version<1 or length(btrim(coalesce(p_reason,''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='LEAVE_INTENT_INVALID';end if;
 h:=employee_self.request_hash(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'leave_intent',
  jsonb_build_array(p_request_id,p_action,p_expected_version,p_reason));
 answer:=employee_self.replay(p_command_id,h);if answer is not null then return answer;end if;
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=employee for update;
 select * into r from people.leave_requests a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.branch_id=p_branch_id and a.employee_id=employee and a.id=p_request_id for update;
 if r.id is null then raise exception using errcode='42501',message='EMPLOYEE_SUBJECT_DENIED';end if;
 perform core.wave3_assert_expected_version(r.version,p_expected_version,'{}');
 if p_action='withdraw' then
  if r.status<>'submitted' or r.created_by<>auth.uid() or r.submitted_by<>auth.uid() or r.active_claim_id is not null
   or exists(select 1 from people.leave_effects x where x.request_id=r.id) then
   raise exception using errcode='55000',message='LEAVE_WITHDRAWAL_INVALID';end if;
  update people.leave_requests set status='cancelled',version=version+1 where id=r.id;
  insert into people.leave_events(tenant_id,legal_entity_id,branch_id,employee_id,request_id,action,before_status,after_status,reason,actor_id,command_id)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,employee,r.id,'cancel','submitted','cancelled',btrim(p_reason),auth.uid(),p_command_id);
  result_status:='withdrawn';
 else
  if r.status<>'approved' then raise exception using errcode='55000',message='LEAVE_CANCELLATION_REQUEST_INVALID';end if;
  if exists(select 1 from employee_self.leave_intents i where i.request_id=r.id and i.request_version=r.version and i.action='cancel_request') then
   raise exception using errcode='55000',message='LEAVE_CANCELLATION_ALREADY_REQUESTED';end if;
  result_status:='cancellation_requested';
 end if;
 insert into employee_self.leave_intents(id,tenant_id,legal_entity_id,branch_id,employee_id,request_id,request_version,action,status,reason,created_by,command_id)
 values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,p_branch_id,employee,r.id,r.version,p_action,result_status,btrim(p_reason),auth.uid(),p_command_id);
 answer:=employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('command_id',p_command_id,
  'request_id',r.id,'version',case when p_action='withdraw' then r.version+1 else r.version end,'status',result_status,'approval_required',p_action='cancel_request');
 return employee_self.finish(p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_command_id,h,answer,'employee_self_leave_intent');
end $$;

create function api.employee_self_reviews(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;items jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform people_private.content_available(p_tenant_id,p_legal_entity_id,employee);
 if p_after is not null and not exists(select 1 from people_private.reviews r where r.id=p_after and r.tenant_id=p_tenant_id
  and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.employee_id=employee and r.status in ('reviewed','acknowledged','closed')) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(q.item order by q.id),'[]') into items from(
  select r.id,jsonb_build_object('id',r.id,'version',r.version,'revision_id',r.revision_id,'reviewer_id',r.reviewer_id,
   'status',r.status,'start_date',r.start_date,'end_date_exclusive',r.end_date_exclusive,'body',v.body,
   'recorded_by',v.recorded_by,'recorded_at',v.recorded_at) item
  from people_private.reviews r join people_private.review_revisions v on v.id=r.revision_id
   and v.tenant_id=r.tenant_id and v.legal_entity_id=r.legal_entity_id and v.employee_id=r.employee_id and v.review_id=r.id
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.employee_id=employee
   and r.status in ('reviewed','acknowledged','closed') and r.erased_at is null and v.redacted_at is null
   and (p_after is null or r.id>p_after) order by r.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

-- Employee detail is a finite projection, not a recursive copy of calculator
-- output. Future internal input/accounting keys cannot become employee fields.
create function employee_self.public_pay_lines(p_lines jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('code',line->'code','classification',line->'classification',
  'amount',line->'amount') order by position),'[]'::jsonb)
 from jsonb_array_elements(case when jsonb_typeof(p_lines)='array' then p_lines else '[]'::jsonb end)
  with ordinality items(line,position)
$$;
create function employee_self.public_pay_calculation(p_body jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object('gross',p_body->'gross','deductions',p_body->'deductions',
  'employer_cost',p_body->'employer_cost','net',p_body->'net',
  'lines',employee_self.public_pay_lines(p_body->'lines'))
$$;
create function employee_self.public_pay_difference(p_body jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object('gross',p_body->'gross','deductions',p_body->'deductions',
  'employer_cost',p_body->'employer_cost','net',p_body->'net','lines',coalesce((
   select jsonb_agg(jsonb_build_object('code',line->'code','classification',line->'classification',
    'difference',line->'difference',
    'before',jsonb_build_object('code',line#>'{before,code}','classification',line#>'{before,classification}','amount',line#>'{before,amount}'),
    'after',jsonb_build_object('code',line#>'{after,code}','classification',line#>'{after,classification}','amount',line#>'{after,amount}')) order by position)
   from jsonb_array_elements(case when jsonb_typeof(p_body->'lines')='array' then p_body->'lines' else '[]'::jsonb end)
    with ordinality items(line,position)),'[]'::jsonb))
$$;

create function api.employee_self_payslips(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;items jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.payslip.self',true);
 if p_after is not null and not exists(select 1 from people_payroll.payslips p join people_payroll.runs r on r.id=p.run_id
  where p.id=p_after and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.branch_id=p_branch_id
  and p.employee_id=employee and r.status in ('posted','reversed')) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg((people_payroll.payslip_payload(q.id)-'lines')||jsonb_build_object('synthetic',true) order by q.id),'[]') into items
 from(select p.id from people_payroll.payslips p join people_payroll.runs r on r.id=p.run_id
  where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id
  and p.branch_id=p_branch_id and p.employee_id=employee and r.status in ('posted','reversed')
  and (p_after is null or p.id>p_after) order by p.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

-- Only immutable issued calculation lines; no staff exports, journals, bank data,
-- private calculation inputs or unapproved correction proposals are returned.
create function api.employee_self_payslip(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_payslip_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;answer jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.payslip.self',true);
 if p_payslip_id is null or not exists(select 1 from people_payroll.payslips p join people_payroll.runs r on r.id=p.run_id
  where p.id=p_payslip_id and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.branch_id=p_branch_id
  and p.employee_id=employee and r.status in ('posted','reversed')) then
  raise exception using errcode='42501',message='EMPLOYEE_SUBJECT_DENIED';end if;
 select (people_payroll.payslip_payload(p_payslip_id)-'lines')||jsonb_build_object('synthetic',true,
  'payslip_revision_id',c.revision_id,'lines',employee_self.public_pay_lines(c.calculation->'lines'))
 into answer from people_payroll.payslips p join people_payroll.employee_calculations c on c.id=p.calculation_id
 where p.id=p_payslip_id;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('payslip',answer);
end $$;

create function api.employee_self_payslip_corrections(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_payslip_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;calculation uuid;items jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.payslip.self',true);
 select p.calculation_id into calculation from people_payroll.payslips p join people_payroll.runs r on r.id=p.run_id
  where p.id=p_payslip_id and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.branch_id=p_branch_id
  and p.employee_id=employee and r.status in ('posted','reversed');
 if calculation is null then raise exception using errcode='42501',message='EMPLOYEE_SUBJECT_DENIED';end if;
 if p_after is not null and not exists(select 1 from people_payroll.correction_payslips p join people_payroll.corrections c on c.id=p.correction_id
  where p.id=p_after and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.branch_id=p_branch_id
   and p.employee_id=employee and c.employee_id=employee and c.original_calculation_id=calculation and c.status in ('posted','reversed')) then
  raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
 select coalesce(jsonb_agg(q.item order by q.id),'[]') into items from(
  select p.id,jsonb_build_object('id',p.id,'correction_id',c.id,'version',c.version,'status',c.status,
   'chain_version',c.chain_version,'predecessor_id',c.predecessor_id,'original_calculation_id',c.original_calculation_id,
   'issued_at',p.issued_at,'digest',p.digest,'synthetic',true,
   'payload',jsonb_build_object('employee_id',employee,'employee_code',p.payload->'employee_code','employee_name',p.payload->'employee_name',
    'start_date',p.payload->'start_date','end_date_exclusive',p.payload->'end_date_exclusive','posting_date',p.payload->'posting_date',
    'currency_code',p.payload->'currency_code','before',employee_self.public_pay_calculation(p.payload->'before'),
    'after',employee_self.public_pay_calculation(p.payload->'after'),
    'difference',employee_self.public_pay_difference(p.payload->'difference'))) item
  from people_payroll.correction_payslips p join people_payroll.corrections c on c.id=p.correction_id
   and c.tenant_id=p.tenant_id and c.legal_entity_id=p.legal_entity_id and c.branch_id=p.branch_id and c.employee_id=p.employee_id
  where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.branch_id=p_branch_id and p.employee_id=employee
   and c.original_calculation_id=calculation and c.status in ('posted','reversed') and (p_after is null or p.id>p_after)
  order by p.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('payslip_id',p_payslip_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

create function employee_self.require_workforce_staff(p_t uuid,p_e uuid,p_b uuid,p_cap text) returns void
language plpgsql security definer set search_path='' as $$declare sid uuid;begin
 if auth.uid() is null or coalesce(auth.jwt()->>'session_id','') !~*
  '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  raise exception using errcode='42501',message='EMPLOYEE_SESSION_REQUIRED';end if;
 sid:=(auth.jwt()->>'session_id')::uuid;
 if not exists(select 1 from auth.sessions s where s.id=sid and s.user_id=auth.uid()
  and (s.not_after is null or s.not_after>clock_timestamp())) then
  raise exception using errcode='42501',message='EMPLOYEE_SESSION_REQUIRED';end if;
 if p_cap is null or p_cap not in ('people.attendance.view','people.attendance.approve','people.leave.view','people.leave.approve') then
  raise exception using errcode='42501',message='EMPLOYEE_STAFF_CAPABILITY_INVALID';end if;
 perform people.require_access(p_t,p_e,p_b,p_cap);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='EMPLOYEE_MFA_REQUIRED';end if;
end $$;

create function api.employee_staff_request_access(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if p_kind is null or p_kind not in ('attendance','leave_cancel') then raise exception using errcode='22023',message='EMPLOYEE_STAFF_REQUEST_INVALID';end if;
 perform employee_self.require_workforce_staff(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when p_kind='attendance' then 'people.attendance.view' else 'people.leave.view' end);
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'actor_id',auth.uid(),'authorized',true,'kind',p_kind);
end $$;

create function api.employee_staff_requests(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare items jsonb;begin
 perform api.employee_staff_request_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_kind);
 if p_kind='attendance' then
  if p_after is not null and not exists(select 1 from employee_self.attendance_requests a where a.id=p_after
   and a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id) then
   raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
  select coalesce(jsonb_agg(q.item order by q.id),'[]') into items from(
   select a.id,jsonb_build_object('id',a.id,'kind','attendance','employee_id',a.employee_id,'employee_name',p.display_name,
    'version',1,'status','pending_evidence','action',a.action,'entry_id',a.entry_id,'source_version',a.expected_version,
    'observed_at',a.observed_at,'reason',a.reason,'created_at',a.created_at) item
   from employee_self.attendance_requests a join people.employees p on p.tenant_id=a.tenant_id
    and p.legal_entity_id=a.legal_entity_id and p.id=a.employee_id
   where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id
    and not exists(select 1 from employee_self.request_resolutions r where r.attendance_request_id=a.id)
    and (p_after is null or a.id>p_after) order by a.id limit 51) q;
 else
  if p_after is not null and not exists(select 1 from employee_self.leave_intents a where a.id=p_after and a.action='cancel_request'
   and a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id) then
   raise exception using errcode='22023',message='EMPLOYEE_CURSOR_INVALID';end if;
  select coalesce(jsonb_agg(q.item order by q.id),'[]') into items from(
   select i.id,jsonb_build_object('id',i.id,'kind','leave_cancel','employee_id',i.employee_id,'employee_name',p.display_name,
    'version',1,'status','cancellation_requested','source_id',l.id,'source_version',l.version,'source_status',l.status,
    'requested_source_version',i.request_version,'balance_version',coalesce(a.version,0),
    'start_local',l.start_local,'end_local',l.end_local,'reason',i.reason,'created_at',i.created_at) item
   from employee_self.leave_intents i join people.leave_requests l on l.id=i.request_id
    and l.tenant_id=i.tenant_id and l.legal_entity_id=i.legal_entity_id and l.employee_id=i.employee_id and l.branch_id=i.branch_id
   join people.employees p on p.tenant_id=i.tenant_id and p.legal_entity_id=i.legal_entity_id and p.id=i.employee_id
   left join people.leave_accounts a on a.tenant_id=l.tenant_id and a.legal_entity_id=l.legal_entity_id
    and a.employee_id=l.employee_id and a.policy_id=l.policy_id
   where i.tenant_id=p_tenant_id and i.legal_entity_id=p_legal_entity_id and i.branch_id=p_branch_id and i.action='cancel_request'
    and not exists(select 1 from employee_self.request_resolutions r where r.leave_intent_id=i.id)
    and (p_after is null or i.id>p_after) order by i.id limit 51) q;
 end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'actor_id',auth.uid(),'kind',p_kind,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;

-- A staff decision completes intake, never invents approved time. Attendance
-- resolution binds a real independently approved canonical entry. Approved
-- leave cancellation invokes the existing ledger/claim owner in this transaction.
create function api.employee_staff_request_resolve(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_kind text,p_request_id uuid,p_decision text,p_canonical_id uuid,p_expected_version bigint,
 p_expected_canonical_version bigint,p_expected_balance_version bigint,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid;creator uuid;h text;answer jsonb;receipt employee_self.staff_receipts%rowtype;
 evidence employee_self.attendance_requests%rowtype;intent employee_self.leave_intents%rowtype;
 entry people.attendance_entries%rowtype;revision people.attendance_revisions%rowtype;leave_row people.leave_requests%rowtype;
 canonical_version bigint;canonical_changed boolean:=false;begin
 if p_kind is null or p_kind not in ('attendance','leave_cancel') then raise exception using errcode='22023',message='EMPLOYEE_STAFF_REQUEST_INVALID';end if;
 perform employee_self.require_workforce_staff(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when p_kind='attendance' then 'people.attendance.approve' else 'people.leave.approve' end);
 if p_command_id is null or p_request_id is null or p_decision is null or p_decision not in ('resolved','declined')
  or p_expected_version is null or length(btrim(coalesce(p_reason,''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='EMPLOYEE_STAFF_REQUEST_INVALID';end if;
 if p_kind='attendance' then
  select * into evidence from employee_self.attendance_requests a where a.id=p_request_id and a.tenant_id=p_tenant_id
   and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id;
  employee:=evidence.employee_id;creator:=evidence.created_by;
 else
  select * into intent from employee_self.leave_intents i where i.id=p_request_id and i.tenant_id=p_tenant_id
   and i.legal_entity_id=p_legal_entity_id and i.branch_id=p_branch_id and i.action='cancel_request';
  employee:=intent.employee_id;creator:=intent.created_by;
 end if;
 if employee is null then raise exception using errcode='42501',message='EMPLOYEE_SUBJECT_DENIED';end if;
 if creator=auth.uid() or exists(select 1 from people_private.account_links l where l.tenant_id=p_tenant_id
  and l.legal_entity_id=p_legal_entity_id and l.employee_id=employee and l.user_id=auth.uid() and l.status='accepted') then
  raise exception using errcode='42501',message='EMPLOYEE_INDEPENDENT_REVIEW_REQUIRED';end if;
 h:=employee_self.request_hash(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'staff_request_resolve',
  jsonb_build_array(p_kind,p_request_id,p_decision,p_canonical_id,p_expected_version,p_expected_canonical_version,p_expected_balance_version,p_reason));
 perform pg_advisory_xact_lock(hashtextextended('employee-staff-command:'||auth.uid()::text||p_command_id::text,0));
 perform employee_self.require_workforce_staff(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when p_kind='attendance' then 'people.attendance.approve' else 'people.leave.approve' end);
 select * into receipt from employee_self.staff_receipts r where r.user_id=auth.uid() and r.command_id=p_command_id;
 if found then
  if receipt.request_hash<>h then raise exception using errcode='22023',message='EMPLOYEE_COMMAND_REUSED';end if;
  return receipt.response;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('employee-staff-request:'||p_kind||p_request_id::text,0));
 perform employee_self.require_workforce_staff(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when p_kind='attendance' then 'people.attendance.approve' else 'people.leave.approve' end);
 perform core.wave3_assert_expected_version(case when exists(select 1 from employee_self.request_resolutions r
  where r.attendance_request_id=p_request_id or r.leave_intent_id=p_request_id) then 2 else 1 end,p_expected_version,'{}');
 if p_decision='declined' then
  if p_canonical_id is not null or p_expected_canonical_version is not null or p_expected_balance_version is not null then
   raise exception using errcode='22023',message='EMPLOYEE_STAFF_REQUEST_INVALID';end if;
 elsif p_kind='attendance' then
  select * into entry from people.attendance_entries a where a.id=p_canonical_id and a.tenant_id=p_tenant_id
   and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and a.employee_id=employee for share;
  if entry.id is null or p_expected_canonical_version is null then raise exception using errcode='42501',message='EMPLOYEE_CANONICAL_RECORD_REQUIRED';end if;
  perform core.wave3_assert_expected_version(entry.version,p_expected_canonical_version,'{}');
  select * into revision from people.attendance_revisions r where r.id=entry.current_revision_id;
  if entry.status<>'approved' or entry.decided_by is null or entry.decided_by=creator or revision.recorded_at<evidence.created_at
   or evidence.observed_at not between revision.start_utc and revision.end_utc
   or (evidence.action='capture' and entry.created_at<evidence.created_at)
   or (evidence.action='correction' and (entry.id<>evidence.entry_id or entry.version<=evidence.expected_version))
   or not exists(select 1 from people.work_claims c where c.id=entry.active_claim_id and c.active
    and c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.branch_id=p_branch_id and c.employee_id=employee
    and c.source_kind='attendance' and c.source_id=revision.id and c.start_utc=revision.start_utc and c.end_utc=revision.end_utc
    and c.payable_seconds=revision.payable_seconds) then
   raise exception using errcode='55000',message='EMPLOYEE_CANONICAL_RECORD_REQUIRED';end if;
  canonical_version:=entry.version;
 else
  select * into leave_row from people.leave_requests l where l.id=intent.request_id and l.tenant_id=p_tenant_id
   and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.employee_id=employee;
  if p_canonical_id is distinct from leave_row.id or leave_row.id is null or p_expected_canonical_version is null then
   raise exception using errcode='42501',message='EMPLOYEE_CANONICAL_RECORD_REQUIRED';end if;
  perform core.wave3_assert_expected_version(leave_row.version,p_expected_canonical_version,'{}');
  if leave_row.status='approved' then
   perform core.wave3_assert_expected_version(leave_row.version,intent.request_version,'{}');
   perform api.people_leave_request_command(p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_command_id,clock_timestamp(),
    jsonb_build_object('action','cancel','id',leave_row.id,'employee_id',employee,'balance_version',p_expected_balance_version,'reason',btrim(p_reason)),leave_row.version);
   canonical_changed:=true;
  elsif leave_row.status<>'cancelled' or leave_row.version<>intent.request_version+1 or leave_row.active_claim_id is not null
   or not exists(select 1 from people.leave_events v where v.request_id=leave_row.id and v.action='cancel'
    and v.before_status='approved' and v.after_status='cancelled' and v.recorded_at>=intent.created_at and v.actor_id<>creator) then
   raise exception using errcode='55000',message='EMPLOYEE_CANONICAL_RECORD_REQUIRED';end if;
  select version into canonical_version from people.leave_requests where id=leave_row.id;
 end if;
 insert into employee_self.request_resolutions(kind,tenant_id,legal_entity_id,branch_id,employee_id,attendance_request_id,
  leave_intent_id,decision,canonical_id,canonical_version,reason,created_by,command_id)
 values(p_kind,p_tenant_id,p_legal_entity_id,p_branch_id,employee,case when p_kind='attendance' then p_request_id end,
  case when p_kind='leave_cancel' then p_request_id end,p_decision,case when p_decision='resolved' then p_canonical_id end,
  canonical_version,btrim(p_reason),auth.uid(),p_command_id);
 answer:=employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('command_id',p_command_id,
  'request_id',p_request_id,'kind',p_kind,'version',2,'status',p_decision,'canonical_id',case when p_decision='resolved' then p_canonical_id end,
  'canonical_version',canonical_version,'canonical_changed',canonical_changed,'payable_time_changed',false);
 insert into employee_self.staff_receipts(user_id,command_id,tenant_id,legal_entity_id,branch_id,request_hash,response)
 values(auth.uid(),p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,h,answer);
 return answer;
end $$;

revoke all on all functions in schema employee_self from public,anon,authenticated,service_role;
revoke all on function api.employee_staff_request_access(uuid,uuid,uuid,text),api.employee_staff_requests(uuid,uuid,uuid,text,uuid),
 api.employee_staff_request_resolve(uuid,uuid,uuid,uuid,text,uuid,text,uuid,bigint,bigint,bigint,text) from public,anon,authenticated,service_role;
grant execute on function api.employee_staff_request_access(uuid,uuid,uuid,text),api.employee_staff_requests(uuid,uuid,uuid,text,uuid),
 api.employee_staff_request_resolve(uuid,uuid,uuid,uuid,text,uuid,text,uuid,bigint,bigint,bigint,text) to authenticated;
revoke all on function api.employee_self_receipt(uuid,uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function api.employee_self_receipt(uuid,uuid,uuid,uuid,uuid,text) to authenticated;
revoke all on function api.employee_self_attendance(uuid,uuid,uuid,uuid),api.employee_self_attendance_requests(uuid,uuid,uuid,uuid),
 api.employee_self_attendance_request(uuid,uuid,uuid,uuid,uuid,jsonb),api.employee_self_leave_policies(uuid,uuid,uuid,date,uuid),
 api.employee_self_leave_balance(uuid,uuid,uuid,uuid,date),api.employee_self_leave_requests(uuid,uuid,uuid,uuid),
 api.employee_self_leave_submit(uuid,uuid,uuid,uuid,uuid,jsonb,bigint),api.employee_self_leave_intent(uuid,uuid,uuid,uuid,uuid,text,bigint,text),
 api.employee_self_reviews(uuid,uuid,uuid,uuid),api.employee_self_payslips(uuid,uuid,uuid,uuid),api.employee_self_payslip(uuid,uuid,uuid,uuid),
 api.employee_self_payslip_corrections(uuid,uuid,uuid,uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function api.employee_self_attendance(uuid,uuid,uuid,uuid),api.employee_self_attendance_requests(uuid,uuid,uuid,uuid),
 api.employee_self_attendance_request(uuid,uuid,uuid,uuid,uuid,jsonb),api.employee_self_leave_policies(uuid,uuid,uuid,date,uuid),
 api.employee_self_leave_balance(uuid,uuid,uuid,uuid,date),api.employee_self_leave_requests(uuid,uuid,uuid,uuid),
 api.employee_self_leave_submit(uuid,uuid,uuid,uuid,uuid,jsonb,bigint),api.employee_self_leave_intent(uuid,uuid,uuid,uuid,uuid,text,bigint,text),
 api.employee_self_reviews(uuid,uuid,uuid,uuid),api.employee_self_payslips(uuid,uuid,uuid,uuid),api.employee_self_payslip(uuid,uuid,uuid,uuid),
 api.employee_self_payslip_corrections(uuid,uuid,uuid,uuid,uuid)
 to authenticated;
notify pgrst,'reload schema';
