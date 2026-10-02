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
