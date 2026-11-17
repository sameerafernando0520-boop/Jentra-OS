-- CANDIDATE ONLY. Not installed anywhere. Needs the tracked People leave
-- ledger; install after 20261114100000_people_access_hardening.sql. The
-- Employee App range submit at the end is created only when the Employee
-- self-service candidate (20261025090000) is installed.
--
-- Multi-day leave. A leave request still covers exactly one work slot
-- (api.people_leave_request_command, people.leave_slot_charge). A range is
-- a batch of those one-slot requests, one per working day, created and then
-- submitted, approved, rejected or cancelled together through the existing
-- command, so every ledger, independence, MFA and self-decision rule applies
-- to each day unchanged. Each call is one transaction: a failure on any day
-- leaves nothing behind.
--
-- Working days come from the calendar version's weekly slots. A day without
-- a slot is skipped, and so is a day a date override closes. A working
-- override keeps the weekly slot, which is what the one-slot rule charges.

create table people.leave_request_batches(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,employee_id uuid not null,policy_id uuid not null,
 start_date date not null,end_date date not null,
 origin text not null check(origin in ('staff','self')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 check(end_date>=start_date and end_date-start_date<=30),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,policy_id) references people.leave_policies(tenant_id,legal_entity_id,id)
);
create index leave_request_batches_scope_idx on people.leave_request_batches(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index leave_request_batches_policy_idx on people.leave_request_batches(tenant_id,legal_entity_id,policy_id);
create index leave_request_batches_creator_idx on people.leave_request_batches(created_by);

create table people.leave_request_batch_days(
 tenant_id uuid not null,legal_entity_id uuid not null,employee_id uuid not null,
 batch_id uuid not null,request_id uuid not null unique,leave_date date not null,
 primary key(batch_id,leave_date),
 foreign key(tenant_id,legal_entity_id,batch_id) references people.leave_request_batches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,request_id)
  references people.leave_requests(tenant_id,legal_entity_id,employee_id,id)
);
create index leave_request_batch_days_scope_idx on people.leave_request_batch_days(tenant_id,legal_entity_id,batch_id);
create index leave_request_batch_days_request_idx on people.leave_request_batch_days(tenant_id,legal_entity_id,employee_id,request_id);

do $$declare v_table regclass;begin
 foreach v_table in array array['people.leave_request_batches'::regclass,'people.leave_request_batch_days'::regclass] loop
  execute format('alter table %s enable row level security',v_table);
  execute format('alter table %s force row level security',v_table);
  execute format('revoke all on %s from public,anon,authenticated',v_table);
 end loop;
end $$;
create trigger leave_request_batch_immutable before update or delete on people.leave_request_batches
 for each row execute function people.leave_history_guard();
create trigger leave_request_batch_day_immutable before update or delete on people.leave_request_batch_days
 for each row execute function people.leave_history_guard();

-- Request, command and idempotency ids for one day of a batch. Derived, so a
-- replayed range or batch action reaches the same per-day commands.
create function people.leave_range_id(p_kind text,p_seed uuid,p_day date) returns uuid
language sql immutable set search_path='' as $$
 select md5('jentra-leave-range:'||p_kind||':'||p_seed::text||':'||p_day::text)::uuid
$$;

-- The calendar version's work slot for every working day of an inclusive
-- range, with the UTC offset of each local boundary. An ambiguous start
-- takes its earlier instant and an ambiguous end its later one.
create function people.leave_range_slots(p_t uuid,p_e uuid,p_calendar_version uuid,p_start date,p_end date)
returns table(leave_date date,start_local timestamp,start_offset_seconds integer,end_local timestamp,end_offset_seconds integer)
language plpgsql stable security definer set search_path='' as $$
declare v_calendar people.work_calendar_versions%rowtype;v_day date;v_count integer;v_slot jsonb;v_candidates jsonb;begin
 select * into v_calendar from people.work_calendar_versions where tenant_id=p_t and legal_entity_id=p_e and id=p_calendar_version;
 if v_calendar.id is null then raise exception using errcode='P0002',message='LEAVE_CONFIGURATION_NOT_FOUND';end if;
 if p_start is null or p_end is null or p_end<p_start or p_end-p_start>30 then
  raise exception using errcode='22023',message='LEAVE_RANGE_INVALID';end if;
 if p_start<v_calendar.start_date or p_end>=v_calendar.end_date_exclusive then
  raise exception using errcode='55000',message='LEAVE_RANGE_CALENDAR_NOT_EFFECTIVE';end if;
 for v_day in select g::date from pg_catalog.generate_series(p_start::timestamp,p_end::timestamp,interval '1 day') g loop
  continue when exists(select 1 from jsonb_array_elements(v_calendar.date_overrides) o
   where o->>'date'=v_day::text and (o->>'is_working_day')::boolean=false);
  select count(*),jsonb_agg(value)->0 into v_count,v_slot from jsonb_array_elements(v_calendar.weekly_intervals) value
  where (value->>'day_of_week')::integer=extract(isodow from v_day)::integer;
  continue when v_count=0;
  if v_count>1 then raise exception using errcode='55000',message='LEAVE_SINGLE_WORK_SLOT_REQUIRED';end if;
  leave_date:=v_day;
  start_local:=v_day::timestamp+(v_slot->>'start_minute')::integer*interval '1 minute';
  end_local:=v_day::timestamp+(v_slot->>'end_day_offset')::integer*interval '1 day'
   +(v_slot->>'end_minute')::integer*interval '1 minute';
  v_candidates:=people.local_instant_candidates(v_calendar.timezone,start_local);
  if jsonb_array_length(v_candidates)=0 then
   raise exception using errcode='22023',message='CALENDAR_LOCAL_TIME_NONEXISTENT';end if;
  start_offset_seconds:=(v_candidates->0->>'offset_seconds')::integer;
  v_candidates:=people.local_instant_candidates(v_calendar.timezone,end_local);
  if jsonb_array_length(v_candidates)=0 then
   raise exception using errcode='22023',message='CALENDAR_LOCAL_TIME_NONEXISTENT';end if;
  end_offset_seconds:=(v_candidates->-1->>'offset_seconds')::integer;
  return next;
 end loop;
end $$;

-- A batch as one item with its days. Reasons are private and left out.
create function people.leave_batch_summary(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',b.id,'employee_id',b.employee_id,'policy_id',b.policy_id,
  'start_date',b.start_date,'end_date',b.end_date,'origin',b.origin,'created_by',b.created_by,
  'status',case when count(distinct r.status)=1 then min(r.status) else 'mixed' end,
  'charge_seconds',sum(r.charge_seconds),'unpaid_seconds',sum(r.unpaid_seconds),
  'days',jsonb_agg(jsonb_build_object('leave_date',d.leave_date,'request_id',r.id,'version',r.version,
   'status',r.status,'start_utc',r.start_utc,'end_utc',r.end_utc,
   'charge_seconds',r.charge_seconds,'unpaid_seconds',r.unpaid_seconds) order by d.leave_date))
 from people.leave_request_batches b
 join people.leave_request_batch_days d on d.batch_id=b.id
 join people.leave_requests r on r.id=d.request_id
 where b.id=p_id group by b.id
$$;

create function people.leave_range_payload_valid(p_payload jsonb,p_keys text[],p_uuids text[]) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(p_payload),'null')='object'
  and not exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(p_keys))
  and not exists(select 1 from unnest(p_uuids) k where coalesce(p_payload->>k,'')
   !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
$$;

create function api.people_leave_request_range(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_name text:='people.leave.batch.create';v_hash text;v_replay jsonb;v_batch uuid;v_employee uuid;
 v_policy people.leave_policy_versions%rowtype;v_slot record;v_days integer:=0;v_after jsonb;begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or not people.leave_range_payload_valid(p_payload,array['batch_id','employee_id','policy_version_id',
   'calendar_version_id','start_date','end_date','reason'],
   array['batch_id','employee_id','policy_version_id','calendar_version_id'])
  or coalesce(p_payload->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or coalesce(p_payload->>'end_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
  raise exception using errcode='22023',message='LEAVE_RANGE_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.manage');
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='LEAVE_MFA_REQUIRED';end if;
 v_hash:=core.wave3_request_hash(v_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,0);
 v_replay:=core.wave3_replay(p_tenant_id,v_name,p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 v_batch:=(p_payload->>'batch_id')::uuid;v_employee:=(p_payload->>'employee_id')::uuid;
 if not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee) then
  raise exception using errcode='42501',message='LEAVE_SCOPE_DENIED';end if;
 if exists(select 1 from people.leave_request_batches where id=v_batch) then
  raise exception using errcode='23505',message='LEAVE_BATCH_EXISTS';end if;
 select * into v_policy from people.leave_policy_versions where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=(p_payload->>'policy_version_id')::uuid;
 if v_policy.id is null then raise exception using errcode='P0002',message='LEAVE_CONFIGURATION_NOT_FOUND';end if;
 if (p_payload->>'end_date')::date<(p_payload->>'start_date')::date
  or (p_payload->>'end_date')::date-(p_payload->>'start_date')::date>30 then
  raise exception using errcode='22023',message='LEAVE_RANGE_INVALID';end if;
 insert into people.leave_request_batches(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,
  start_date,end_date,origin,created_by)
 values(v_batch,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_policy.policy_id,
  (p_payload->>'start_date')::date,(p_payload->>'end_date')::date,'staff',auth.uid());
 for v_slot in select * from people.leave_range_slots(p_tenant_id,p_legal_entity_id,
  (p_payload->>'calendar_version_id')::uuid,(p_payload->>'start_date')::date,(p_payload->>'end_date')::date)
  order by leave_date loop
  perform api.people_leave_request_command(p_tenant_id,p_legal_entity_id,p_branch_id,
   people.leave_range_id('create-command',p_command_id,v_slot.leave_date),
   people.leave_range_id('create-key',p_idempotency_key,v_slot.leave_date),p_client_timestamp,
   jsonb_build_object('action','create','id',people.leave_range_id('request',v_batch,v_slot.leave_date),
    'employee_id',v_employee,'policy_version_id',v_policy.id,
    'calendar_version_id',p_payload->>'calendar_version_id',
    'start_local',to_char(v_slot.start_local,'YYYY-MM-DD"T"HH24:MI:SS'),
    'start_offset_seconds',v_slot.start_offset_seconds,
    'end_local',to_char(v_slot.end_local,'YYYY-MM-DD"T"HH24:MI:SS'),
    'end_offset_seconds',v_slot.end_offset_seconds,'reason',p_payload->>'reason'),0);
  insert into people.leave_request_batch_days(tenant_id,legal_entity_id,employee_id,batch_id,request_id,leave_date)
  values(p_tenant_id,p_legal_entity_id,v_employee,v_batch,
   people.leave_range_id('request',v_batch,v_slot.leave_date),v_slot.leave_date);
  v_days:=v_days+1;
 end loop;
 if v_days=0 then raise exception using errcode='22023',message='LEAVE_RANGE_NO_WORKING_DAY';end if;
 v_after:=people.leave_batch_summary(v_batch);
 return core.wave3_finish_command(p_tenant_id,v_name,p_command_id,'people.leave.batch',v_batch,
  p_idempotency_key,v_hash,'{}'::jsonb,v_after,p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('employee_id',v_employee,'action','create','days',v_days));
end $$;

-- Applies one action to every day of a batch, in day order, through the
-- existing command. Each step re-reads the request's version and, for an
-- approval or cancellation, the leave account's balance version.
create function api.people_leave_batch_command(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_action text:=p_payload->>'action';v_name text;v_hash text;v_replay jsonb;v_batch people.leave_request_batches%rowtype;
 v_day record;v_request people.leave_requests%rowtype;v_balance bigint;v_step jsonb;v_before jsonb;v_after jsonb;begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or not people.leave_range_payload_valid(p_payload,array['action','batch_id','employee_id','reason'],
   array['batch_id','employee_id'])
  or v_action is null or v_action not in ('submit','approve','reject','cancel') then
  raise exception using errcode='22023',message='LEAVE_BATCH_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,
  case when v_action in ('approve','reject','cancel') then 'people.leave.approve' else 'people.leave.manage' end);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='LEAVE_MFA_REQUIRED';end if;
 v_name:='people.leave.batch.'||v_action;
 v_hash:=core.wave3_request_hash(v_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,0);
 v_replay:=core.wave3_replay(p_tenant_id,v_name,p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 select * into v_batch from people.leave_request_batches where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and employee_id=(p_payload->>'employee_id')::uuid and id=(p_payload->>'batch_id')::uuid;
 if v_batch.id is null then raise exception using errcode='P0002',message='LEAVE_BATCH_NOT_FOUND';end if;
 v_before:=people.leave_batch_summary(v_batch.id);
 for v_day in select d.request_id,d.leave_date from people.leave_request_batch_days d
  where d.batch_id=v_batch.id order by d.leave_date loop
  select * into v_request from people.leave_requests where id=v_day.request_id;
  v_step:=jsonb_build_object('action',v_action,'id',v_request.id,'employee_id',v_batch.employee_id,
   'reason',p_payload->>'reason');
  if v_action in ('approve','cancel') then
   select coalesce(max(a.version),0) into v_balance from people.leave_accounts a where a.tenant_id=p_tenant_id
    and a.legal_entity_id=p_legal_entity_id and a.employee_id=v_batch.employee_id and a.policy_id=v_request.policy_id;
   v_step:=v_step||jsonb_build_object('balance_version',v_balance);
  end if;
  perform api.people_leave_request_command(p_tenant_id,p_legal_entity_id,p_branch_id,
   people.leave_range_id(v_action||'-command',p_command_id,v_day.leave_date),
   people.leave_range_id(v_action||'-key',p_idempotency_key,v_day.leave_date),
   p_client_timestamp,v_step,v_request.version);
 end loop;
 v_after:=people.leave_batch_summary(v_batch.id);
 return core.wave3_finish_command(p_tenant_id,v_name,p_command_id,'people.leave.batch',v_batch.id,
  p_idempotency_key,v_hash,v_before,v_after,p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('employee_id',v_batch.employee_id,'action',v_action));
end $$;

create function api.people_leave_batches(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_employee_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.view');
 if p_employee_id is null or not exists(select 1 from people.employment_assignments
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='LEAVE_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(people.leave_batch_summary(q.id) order by q.id),'[]'::jsonb)
 into v_items from(select id from people.leave_request_batches where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id
  and (p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',p_employee_id,'items',v_items-50,
  'next_cursor',case when jsonb_array_length(v_items)>50 then v_items->49->>'id' end);
end $$;

revoke all on function people.leave_range_id(text,uuid,date),
 people.leave_range_slots(uuid,uuid,uuid,date,date),
 people.leave_batch_summary(uuid),people.leave_range_payload_valid(jsonb,text[],text[]),
 api.people_leave_request_range(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb),
 api.people_leave_batch_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb),
 api.people_leave_batches(uuid,uuid,uuid,uuid,uuid)
 from public,anon,authenticated;
grant execute on function api.people_leave_request_range(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb),
 api.people_leave_batch_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb),
 api.people_leave_batches(uuid,uuid,uuid,uuid,uuid)
 to authenticated;

-- Employee App: an employee submits their own range in one step. Each day
-- goes through api.employee_self_leave_submit, so its window, overlap,
-- pending-limit and balance checks apply per day. Staff decide the batch
-- with api.people_leave_batch_command.
do $outer$begin
 if to_regnamespace('employee_self') is null then return;end if;
 alter table employee_self.receipts drop constraint receipts_rpc_check;
 alter table employee_self.receipts add constraint receipts_rpc_check check(rpc in (
  'employee_self_attendance_request','employee_self_leave_submit','employee_self_leave_intent',
  'employee_self_leave_range_submit'));
 alter table employee_self.abandoned_commands drop constraint abandoned_commands_rpc_check;
 alter table employee_self.abandoned_commands add constraint abandoned_commands_rpc_check check(rpc in (
  'employee_self_attendance_request','employee_self_leave_submit','employee_self_leave_intent',
  'employee_case_command','employee_self_leave_range_submit'));
 -- A saved range request is reconciled like a single one: the batch id is
 -- its request id. Only the capability lookup gains the new command.
 execute $fn$
create or replace function api.employee_self_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_request_id uuid,p_rpc text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid;cap text;receipt employee_self.receipts%rowtype;closed employee_self.abandoned_commands%rowtype;begin
 cap:=case p_rpc when 'employee_self_attendance_request' then 'people.attendance.self.request'
  when 'employee_self_leave_submit' then 'people.leave.self.manage' when 'employee_self_leave_intent' then 'people.leave.self.manage'
  when 'employee_self_leave_range_submit' then 'people.leave.self.manage' end;
 if cap is null or p_command_id is null or p_request_id is null then
  raise exception using errcode='22023',message='EMPLOYEE_RECEIPT_INVALID';end if;
 employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,cap);
 perform pg_advisory_xact_lock(hashtextextended('employee-self-command:'||auth.uid()::text||p_command_id::text,0));
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
end $$
$fn$;
 execute $fn$
create function api.employee_self_leave_range_submit(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_request_id uuid,p_payload jsonb,p_expected_balance_version bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid;policy people.leave_policy_versions%rowtype;h text;answer jsonb;v_slot record;v_days integer:=0;begin
 employee:=employee_self.lock_subject(p_tenant_id,p_legal_entity_id,p_branch_id,'people.leave.self.manage');
 perform people_private.fields(p_payload,array['policy_version_id','calendar_version_id','start_date','end_date','reason']);
 if p_request_id is null or p_expected_balance_version is null or p_expected_balance_version<0
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000
  or coalesce(p_payload->>'policy_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'calendar_version_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or coalesce(p_payload->>'end_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
  raise exception using errcode='22023',message='LEAVE_SUBMISSION_INVALID';end if;
 h:=employee_self.request_hash(p_tenant_id,p_legal_entity_id,p_branch_id,employee,'leave_range_submit',
  jsonb_build_array(p_request_id,p_payload,p_expected_balance_version));
 answer:=employee_self.replay(p_command_id,h);if answer is not null then return answer;end if;
 if exists(select 1 from people.leave_request_batches b where b.id=p_request_id) then
  raise exception using errcode='23505',message='LEAVE_BATCH_EXISTS';end if;
 select * into policy from people.leave_policy_versions v where v.tenant_id=p_tenant_id and v.legal_entity_id=p_legal_entity_id
  and v.id=(p_payload->>'policy_version_id')::uuid;
 if policy.id is null then raise exception using errcode='22023',message='LEAVE_CONFIGURATION_INVALID';end if;
 if (p_payload->>'end_date')::date<(p_payload->>'start_date')::date
  or (p_payload->>'end_date')::date-(p_payload->>'start_date')::date>30 then
  raise exception using errcode='22023',message='LEAVE_RANGE_INVALID';end if;
 insert into people.leave_request_batches(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,
  start_date,end_date,origin,created_by)
 values(p_request_id,p_tenant_id,p_legal_entity_id,p_branch_id,employee,policy.policy_id,
  (p_payload->>'start_date')::date,(p_payload->>'end_date')::date,'self',auth.uid());
 for v_slot in select * from people.leave_range_slots(p_tenant_id,p_legal_entity_id,
  (p_payload->>'calendar_version_id')::uuid,(p_payload->>'start_date')::date,(p_payload->>'end_date')::date)
  order by leave_date loop
  perform api.employee_self_leave_submit(p_tenant_id,p_legal_entity_id,p_branch_id,
   people.leave_range_id('self-submit-command',p_command_id,v_slot.leave_date),
   people.leave_range_id('request',p_request_id,v_slot.leave_date),
   jsonb_build_object('policy_version_id',policy.id,'calendar_version_id',p_payload->>'calendar_version_id',
    'start_local',to_char(v_slot.start_local,'YYYY-MM-DD"T"HH24:MI:SS'),'start_offset_seconds',v_slot.start_offset_seconds,
    'end_local',to_char(v_slot.end_local,'YYYY-MM-DD"T"HH24:MI:SS'),'end_offset_seconds',v_slot.end_offset_seconds,
    'reason',p_payload->>'reason'),p_expected_balance_version);
  insert into people.leave_request_batch_days(tenant_id,legal_entity_id,employee_id,batch_id,request_id,leave_date)
  values(p_tenant_id,p_legal_entity_id,employee,p_request_id,people.leave_range_id('request',p_request_id,v_slot.leave_date),v_slot.leave_date);
  v_days:=v_days+1;
 end loop;
 if v_days=0 then raise exception using errcode='22023',message='LEAVE_RANGE_NO_WORKING_DAY';end if;
 answer:=employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('command_id',p_command_id)
  ||(people.leave_batch_summary(p_request_id)-'employee_id'-'created_by')||jsonb_build_object('request_id',p_request_id,'version',1,'approval_required',true);
 return employee_self.finish(p_tenant_id,p_legal_entity_id,p_branch_id,employee,p_command_id,h,answer,'employee_self_leave_range_submit');
end $$
$fn$;
 execute $fn$
create function api.employee_self_leave_batches(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare employee uuid;items jsonb;begin
 employee:=employee_self.require_subject(p_tenant_id,p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(people.leave_batch_summary(q.id)-'created_by' order by q.id),'[]') into items from(
  select b.id from people.leave_request_batches b where b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id
   and b.branch_id=p_branch_id and b.employee_id=employee and (p_after is null or b.id>p_after) order by b.id limit 51) q;
 return employee_self.envelope(p_tenant_id,p_legal_entity_id,p_branch_id,employee)||jsonb_build_object('items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$
$fn$;
 revoke all on function api.employee_self_leave_range_submit(uuid,uuid,uuid,uuid,uuid,jsonb,bigint),
  api.employee_self_leave_batches(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
 grant execute on function api.employee_self_leave_range_submit(uuid,uuid,uuid,uuid,uuid,jsonb,bigint),
  api.employee_self_leave_batches(uuid,uuid,uuid,uuid) to authenticated;
end $outer$;

-- Organization lifecycle guards cover every tenant-scoped table; put them on
-- the two new ones when that candidate is installed.
do $$begin
 if to_regprocedure('organization_lifecycle.install_write_guards()') is not null then
  perform organization_lifecycle.install_write_guards();
 end if;
end $$;

notify pgrst,'reload schema';
