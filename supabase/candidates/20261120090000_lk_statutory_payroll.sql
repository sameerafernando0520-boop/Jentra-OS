-- Candidate only. Not installed on any hosted database.
-- Sri Lanka statutory payroll on the payroll engine: EPF (employee and employer),
-- ETF (employer) and APIT Table 01. Contract:
-- docs/blueprint/70_LK_STATUTORY_PAYROLL_CONTRACT.md.
--
-- Statutory amounts are ordinary rule versions with basis 'statutory', so journal
-- posting, obligations, payslips and settlement work unchanged. Their inputs ride
-- in the frozen run inputs (and so in the input digest). A run without statutory
-- rules calculates exactly as before.

-- 1. Statutory basis on rule versions.
do $$declare c text;begin
 select conname into c from pg_constraint where conrelid='people_payroll.rule_versions'::regclass
  and contype='c' and pg_get_constraintdef(oid) like 'CHECK ((basis = ANY%';
 if c is null then raise exception using errcode='55000',message='PAYROLL_BASIS_CHECK_NOT_FOUND';end if;
 execute format('alter table people_payroll.rule_versions drop constraint %I',c);
end $$;
alter table people_payroll.rule_versions add constraint rule_versions_basis_check
 check(basis in('fixed','hourly','earnings_ratio','statutory'));

create function people_payroll.statutory_kind_valid(p_code text,p_class text) returns boolean
language sql immutable set search_path='' as $$
 select (p_code,p_class) in(('EPF_EE','deduction'),('APIT','deduction'),('EPF_ER','employer_cost'),('ETF_ER','employer_cost'))
$$;

create function people_payroll.statutory_rule_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_code text;v_class text;begin
 if new.basis<>'statutory' then return new;end if;
 select c.code,c.classification into v_code,v_class from people_payroll.components c where c.id=new.component_id;
 if not coalesce(people_payroll.statutory_kind_valid(v_code,v_class),false)
  or new.amount<>0 or new.proration<>'none' or new.currency_code<>'LKR' then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_RULE_INVALID';end if;
 return new;
end $$;
create trigger statutory_rule_guard before insert on people_payroll.rule_versions
 for each row execute function people_payroll.statutory_rule_guard();

-- 2. Dated, approved statutory rule sets.
create function people_payroll.statutory_bands_valid(p jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare b jsonb;i integer:=0;n integer;previous numeric:=null;amount text:='^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$';
 rate text:='^(0|[1-9][0-9]?|100)(\.[0-9]{1,6})?$';begin
 if coalesce(jsonb_typeof(p),'null')<>'array' then return false;end if;
 n:=jsonb_array_length(p);
 if n not between 1 and 20 then return false;end if;
 for b in select value from jsonb_array_elements(p) loop
  i:=i+1;
  if jsonb_typeof(b)<>'object' or exists(select 1 from jsonb_object_keys(b) k where k not in('upto','rate','reduction'))
   or coalesce(b->>'rate','') !~ rate or (b->>'rate')::numeric>100
   or coalesce(b->>'reduction','') !~ amount then return false;end if;
  if i=n then
   if b->'upto' is null or b->'upto'<>'null'::jsonb then return false;end if;
  else
   if coalesce(b->>'upto','') !~ amount or (previous is not null and (b->>'upto')::numeric<=previous) then return false;end if;
   previous:=(b->>'upto')::numeric;
  end if;
 end loop;
 return true;
end $$;

create table people_payroll.statutory_rule_sets(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 country_code text not null check(country_code='LK'),
 effective_from date not null,effective_to_exclusive date not null,
 epf_employee_percent numeric(9,6) not null check(epf_employee_percent between 0 and 100),
 epf_employer_percent numeric(9,6) not null check(epf_employer_percent between 0 and 100),
 etf_employer_percent numeric(9,6) not null check(etf_employer_percent between 0 and 100),
 apit_table text not null check(apit_table='LK_APIT_TABLE_01'),
 apit_bands jsonb not null check(people_payroll.statutory_bands_valid(apit_bands)),
 sources jsonb not null check(jsonb_typeof(sources)='object'),
 status text not null default 'pending' check(status in('pending','approved','retired')),
 proposed_by uuid not null references auth.users(id),proposed_at timestamptz not null default clock_timestamp(),
 approved_by uuid references auth.users(id),approved_at timestamptz,
 retired_by uuid references auth.users(id),retired_at timestamptz,
 check(effective_to_exclusive>effective_from and effective_to_exclusive-effective_from<=1830),
 check((status='pending')=(approved_by is null) and (approved_by is null)=(approved_at is null)),
 check((status='retired')=(retired_by is not null) and (retired_by is null)=(retired_at is null)),
 check(approved_by is null or approved_by<>proposed_by),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 exclude using gist(tenant_id extensions.gist_uuid_ops with =,legal_entity_id extensions.gist_uuid_ops with =,
  daterange(effective_from,effective_to_exclusive,'[)') with &&) where (status='approved')
);
create index payroll_statutory_sets_scope_idx on people_payroll.statutory_rule_sets(tenant_id,legal_entity_id,effective_from);
create index payroll_statutory_sets_proposer_idx on people_payroll.statutory_rule_sets(proposed_by);
create index payroll_statutory_sets_approver_idx on people_payroll.statutory_rule_sets(approved_by);
create index payroll_statutory_sets_retirer_idx on people_payroll.statutory_rule_sets(retired_by);

-- Values are immutable. Only pending -> approved -> retired transitions are allowed.
create function people_payroll.statutory_set_guard() returns trigger
language plpgsql set search_path='' as $$
declare state text[]:=array['status','approved_by','approved_at','retired_by','retired_at'];begin
 if tg_op='DELETE' or to_jsonb(old)-state<>to_jsonb(new)-state
  or not((old.status='pending' and new.status='approved') or (old.status='approved' and new.status='retired'))
  or (old.status='approved' and (new.approved_by,new.approved_at) is distinct from (old.approved_by,old.approved_at)) then
  raise exception using errcode='55000',message='PAYROLL_HISTORY_IMMUTABLE';end if;
 return new;
end $$;
create trigger statutory_set_guard before update or delete on people_payroll.statutory_rule_sets
 for each row execute function people_payroll.statutory_set_guard();

-- 3. Statutory classification of earning components (versioned).
create table people_payroll.component_statutory(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,component_id uuid not null,
 version bigint not null check(version between 1 and 9007199254740991),
 epf_liable boolean not null,etf_liable boolean not null,apit_regular_profit boolean not null,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,component_id,version),
 foreign key(tenant_id,legal_entity_id,component_id) references people_payroll.components(tenant_id,legal_entity_id,id)
);
create index payroll_component_statutory_actor_idx on people_payroll.component_statutory(recorded_by);

-- 4. Employee statutory details (versioned). Identifiers never enter run inputs.
create table people_payroll.employee_statutory(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,employee_id uuid not null,
 version bigint not null check(version between 1 and 9007199254740991),
 nic text check(nic ~ '^([0-9]{9}[VX]|[0-9]{12})$'),
 epf_member_number text check(epf_member_number ~ '^[A-Z0-9/-]{1,20}$'),
 coverage text not null check(coverage in('standard','exempt')),
 apit_case text not null check(apit_case in('regular_primary','lump_sum_or_arrears','terminal_benefit',
  'secondary_employment','employer_paid_tax','foreign_employer')),
 resident_or_citizen boolean not null,primary_employment_declared boolean not null,joined_or_left_in_year boolean not null,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,version),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create index payroll_employee_statutory_actor_idx on people_payroll.employee_statutory(recorded_by);

-- 5. Employer EPF and ETF registration numbers (versioned).
create table people_payroll.employer_registrations(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 version bigint not null check(version between 1 and 9007199254740991),
 epf_employer_number text not null check(epf_employer_number ~ '^[A-Z0-9/-]{1,20}$'),
 etf_employer_number text not null check(etf_employer_number ~ '^[A-Z0-9/-]{1,20}$'),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,version),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create index payroll_employer_registrations_actor_idx on people_payroll.employer_registrations(recorded_by);

do $$declare v_table text;begin
 foreach v_table in array array['statutory_rule_sets','component_statutory','employee_statutory','employer_registrations'] loop
  execute format('alter table people_payroll.%I enable row level security',v_table);
  execute format('alter table people_payroll.%I force row level security',v_table);
  execute format('revoke all on people_payroll.%I from public,anon,authenticated',v_table);
  if v_table<>'statutory_rule_sets' then
   execute format('create trigger immutable before update or delete on people_payroll.%I for each row execute function people_payroll.immutable()',v_table);
  end if;
 end loop;
end $$;

-- 6. Frozen statutory inputs. Null when the employee has no statutory rule.
create function people_payroll.statutory_inputs(t uuid,e uuid,employee uuid,period_start date,period_end date,p_rules jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rs people_payroll.statutory_rule_sets%rowtype;es people_payroll.employee_statutory%rowtype;
 comps jsonb;ay_start date;cumulative numeric;begin
 if coalesce(jsonb_typeof(p_rules),'null')<>'array'
  or not exists(select 1 from jsonb_array_elements(p_rules) x where x->>'basis'='statutory') then return null;end if;
 select * into rs from people_payroll.statutory_rule_sets s where s.tenant_id=t and s.legal_entity_id=e and s.status='approved'
  and daterange(s.effective_from,s.effective_to_exclusive,'[)') @> daterange(period_start,period_end,'[)');
 select * into es from people_payroll.employee_statutory s where s.tenant_id=t and s.legal_entity_id=e and s.employee_id=employee
  order by s.version desc limit 1;
 select coalesce(jsonb_object_agg(c.code,jsonb_build_object('component_id',c.id,'version',s.version,
  'epf',s.epf_liable,'etf',s.etf_liable,'apit',s.apit_regular_profit)),'{}'::jsonb) into comps
 from jsonb_array_elements(p_rules) x join people_payroll.components c
  on c.tenant_id=t and c.legal_entity_id=e and c.id=(x->>'component_id')::uuid
 cross join lateral(select * from people_payroll.component_statutory s where s.tenant_id=t and s.legal_entity_id=e
  and s.component_id=c.id order by s.version desc limit 1) s
 where x->>'classification'='earning';
 ay_start:=make_date(extract(year from period_start)::integer-case when extract(month from period_start)>=4 then 0 else 1 end,4,1);
 -- Year-to-date APIT regular profits from posted runs in the same year of assessment.
 select coalesce(sum((c.calculation->'statutory'->>'apit_base')::numeric),0) into cumulative
 from people_payroll.employee_calculations c join people_payroll.runs r
  on r.tenant_id=c.tenant_id and r.legal_entity_id=c.legal_entity_id and r.id=c.run_id and r.approved_revision_id=c.revision_id
 where c.tenant_id=t and c.legal_entity_id=e and c.employee_id=employee and r.status='posted'
  and r.start_date>=ay_start and r.start_date<period_start and c.calculation ? 'statutory';
 return jsonb_build_object(
  'rule_set',case when rs.id is null then null else jsonb_build_object('id',rs.id,'country_code',rs.country_code,
   'effective_from',rs.effective_from,'effective_to_exclusive',rs.effective_to_exclusive,
   'epf_employee_percent',rs.epf_employee_percent::text,'epf_employer_percent',rs.epf_employer_percent::text,
   'etf_employer_percent',rs.etf_employer_percent::text,'apit_table',rs.apit_table,'apit_bands',rs.apit_bands,
   'approved_by',rs.approved_by,'approved_at',rs.approved_at) end,
  'employee',case when es.id is null then null else jsonb_build_object('version',es.version,'coverage',es.coverage,
   'apit_case',es.apit_case,'resident_or_citizen',es.resident_or_citizen,
   'primary_employment_declared',es.primary_employment_declared,'joined_or_left_in_year',es.joined_or_left_in_year,
   'has_nic',es.nic is not null,'has_epf_member_number',es.epf_member_number is not null) end,
  'components',comps,'assessment_year_start',ay_start,'cumulative_regular_profits_before',round(cumulative,6)::text);
end $$;
revoke all on function people_payroll.statutory_inputs(uuid,uuid,uuid,date,date,jsonb) from public,anon,authenticated;

-- Callers resolve people_payroll.freeze by name at run time, so the wrapper
-- takes over preparation and correction without copying the original.
alter function people_payroll.freeze(uuid,uuid,uuid,uuid,date,date,text) rename to freeze_core;
create function people_payroll.freeze(t uuid,e uuid,b uuid,employee uuid,period_start date,period_end date,currency text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare base jsonb;stat jsonb;begin
 base:=people_payroll.freeze_core(t,e,b,employee,period_start,period_end,currency);
 stat:=people_payroll.statutory_inputs(t,e,employee,period_start,period_end,base->'rules');
 return case when stat is null then base else base||jsonb_build_object('statutory',stat) end;
end $$;
revoke all on function people_payroll.freeze(uuid,uuid,uuid,uuid,date,date,text) from public,anon,authenticated;

-- 7. Calculation. Blockers are explicit and carry a reason code in DETAIL.
create function people_payroll.statutory_blocked(p_reason text) returns void
language plpgsql immutable set search_path='' as $$begin
 raise exception using errcode='55000',message='PAYROLL_STATUTORY_BLOCKED',detail=p_reason;
end $$;

create function people_payroll.statutory_line(r jsonb,p_base numeric,p_percent numeric,p_reduction numeric)
returns jsonb language plpgsql immutable set search_path='' as $$
declare n numeric;d numeric:=100000000;units numeric;rounded numeric;cap numeric;capped boolean;amount numeric;
 v_precision integer:=(r->>'precision')::integer;begin
 -- (base x percent / 100) - reduction, in micro-units; never below zero.
 n:=p_base*1000000*p_percent*1000000-p_reduction*1000000*100*1000000;
 if n<0 then n:=0;end if;
 if n<>trunc(n) then raise exception using errcode='22023',message='PAYROLL_STATUTORY_PRECISION_INVALID';end if;
 units:=people_payroll.round_ratio(n,d,v_precision,r->>'rounding');rounded:=units/1000000;cap:=null;
 if r->'cap' is not null and r->'cap'<>'null'::jsonb then
  cap:=people_payroll.amount(r->'cap');
  if cap<>round(cap,v_precision) then raise exception using errcode='22023',message='PAYROLL_CAP_INVALID';end if;
 end if;
 capped:=cap is not null and rounded>cap;amount:=case when capped then cap else rounded end;
 return jsonb_build_object('rule_version_id',r->>'id','code',r->>'code','classification',r->>'classification',
  'basis','statutory','proration','none','raw_numerator_units',trunc(n)::text,'raw_denominator',trunc(d)::text,
  'rounding',r->>'rounding','precision',v_precision,'rounded_amount',round(rounded,6)::text,
  'cap',case when cap is not null then round(cap,6)::text end,'capped',capped,'amount',round(amount,6)::text,
  'statutory_base',round(p_base,6)::text,'statutory_percent',p_percent::text);
end $$;

alter function people_payroll.calculate(jsonb,jsonb,text) rename to calculate_core;
create function people_payroll.calculate(p_input jsonb,p_rules jsonb,p_currency text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare stat jsonb;rs jsonb;emp jsonb;comp jsonb;base jsonb;r jsonb;l jsonb;band jsonb;lines jsonb;
 core_rules jsonb;stat_rules jsonb;codes text[];has_epf boolean;has_apit boolean;
 epf_base numeric:=0;etf_base numeric:=0;apit_base numeric:=0;cumulative numeric;first_band numeric;
 gross numeric;deductions numeric;cost numeric;amount numeric;rate numeric:=0;reduction numeric:=0;
 period_start date;period_end date;begin
 if coalesce(jsonb_typeof(p_rules),'null')<>'array' or coalesce(jsonb_typeof(p_input),'null')<>'object' then
  raise exception using errcode='22023',message='PAYROLL_CALCULATION_INVALID';end if;
 select coalesce(jsonb_agg(x order by x->>'code'),'[]'::jsonb) into stat_rules
  from jsonb_array_elements(p_rules) x where x->>'basis'='statutory';
 if jsonb_array_length(stat_rules)=0 then return people_payroll.calculate_core(p_input,p_rules,p_currency);end if;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into core_rules from jsonb_array_elements(p_rules) x where x->>'basis' is distinct from 'statutory';
 select array_agg(x->>'code') into codes from jsonb_array_elements(stat_rules) x;
 if cardinality(codes)<>cardinality(array(select distinct unnest(codes)))
  or exists(select 1 from jsonb_array_elements(stat_rules) x where not coalesce(people_payroll.statutory_kind_valid(x->>'code',x->>'classification'),false)
   or x->>'currency_code' is distinct from 'LKR' or coalesce(x->>'precision','') !~ '^[0-6]$'
   or coalesce(x->>'rounding','') not in('half_away','half_even','truncate','floor')
   or coalesce(x->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(x->>'start_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(x->>'end_date_exclusive','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or (x->>'start_date')::date>(p_input->>'start_date')::date
   or (x->>'end_date_exclusive')::date<(p_input->>'end_date_exclusive')::date) then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_RULE_INVALID';end if;
 has_epf:='EPF_EE'=any(codes) or 'EPF_ER'=any(codes) or 'ETF_ER'=any(codes);has_apit:='APIT'=any(codes);
 if p_currency is distinct from 'LKR' then perform people_payroll.statutory_blocked('STATUTORY_LKR_REQUIRED');end if;
 stat:=p_input->'statutory';
 if coalesce(jsonb_typeof(stat),'null')<>'object' then perform people_payroll.statutory_blocked('STATUTORY_INPUTS_MISSING');end if;
 rs:=stat->'rule_set';emp:=stat->'employee';
 if coalesce(jsonb_typeof(rs),'null')<>'object' then perform people_payroll.statutory_blocked('STATUTORY_APPROVED_RULE_SET_REQUIRED');end if;
 period_start:=(p_input->>'start_date')::date;period_end:=(p_input->>'end_date_exclusive')::date;
 if (rs->>'effective_from')::date>period_start or (rs->>'effective_to_exclusive')::date<period_end
  or not people_payroll.statutory_bands_valid(rs->'apit_bands') then
  perform people_payroll.statutory_blocked('STATUTORY_APPROVED_RULE_SET_REQUIRED');end if;
 if coalesce(jsonb_typeof(emp),'null')<>'object' then perform people_payroll.statutory_blocked('STATUTORY_EMPLOYEE_DETAILS_REQUIRED');end if;
 if not coalesce((emp->>'has_nic')::boolean,false) then perform people_payroll.statutory_blocked('STATUTORY_NIC_REQUIRED');end if;
 if has_epf then
  if emp->>'coverage' is distinct from 'standard' then perform people_payroll.statutory_blocked('STATUTORY_COVERAGE_REVIEW_REQUIRED');end if;
  if not coalesce((emp->>'has_epf_member_number')::boolean,false) then
   perform people_payroll.statutory_blocked('STATUTORY_EPF_MEMBER_NUMBER_REQUIRED');end if;
 end if;
 if has_apit then
  if emp->>'apit_case' is distinct from 'regular_primary' then perform people_payroll.statutory_blocked('STATUTORY_APIT_OTHER_TABLE_REQUIRED');end if;
  if not coalesce((emp->>'resident_or_citizen')::boolean,false) then perform people_payroll.statutory_blocked('STATUTORY_APIT_NONRESIDENT_REVIEW_REQUIRED');end if;
  if not coalesce((emp->>'primary_employment_declared')::boolean,false) then
   perform people_payroll.statutory_blocked('STATUTORY_APIT_PRIMARY_DECLARATION_REQUIRED');end if;
  if coalesce((emp->>'joined_or_left_in_year')::boolean,true) then perform people_payroll.statutory_blocked('STATUTORY_APIT_TABLE_05_REQUIRED');end if;
  -- Table 01 is a monthly table.
  if extract(day from period_start)<>1 or period_end<>(period_start+interval '1 month')::date then
   perform people_payroll.statutory_blocked('STATUTORY_APIT_MONTHLY_PERIOD_REQUIRED');end if;
 end if;
 if jsonb_array_length(core_rules)=0 then perform people_payroll.statutory_blocked('STATUTORY_EARNINGS_REQUIRED');end if;
 base:=people_payroll.calculate_core(p_input,core_rules,p_currency);
 comp:=coalesce(stat->'components','{}'::jsonb);
 for l in select value from jsonb_array_elements(base->'lines') where value->>'classification'='earning' loop
  if coalesce(jsonb_typeof(comp->(l->>'code')),'null')<>'object' then
   perform people_payroll.statutory_blocked('STATUTORY_EARNINGS_UNCLASSIFIED');end if;
  amount:=(l->>'amount')::numeric;
  if (comp->(l->>'code')->>'epf')::boolean then epf_base:=epf_base+amount;end if;
  if (comp->(l->>'code')->>'etf')::boolean then etf_base:=etf_base+amount;end if;
  if (comp->(l->>'code')->>'apit')::boolean then apit_base:=apit_base+amount;end if;
 end loop;
 cumulative:=coalesce(people_payroll.amount(stat->'cumulative_regular_profits_before'),0)+apit_base;
 if has_apit then
  for band in select value from jsonb_array_elements(rs->'apit_bands') loop
   if band->'upto'='null'::jsonb or apit_base<=(band->>'upto')::numeric then
    rate:=(band->>'rate')::numeric;reduction:=(band->>'reduction')::numeric;exit;end if;
  end loop;
  first_band:=(rs->'apit_bands'->0->>'upto')::numeric;
  -- Low monthly profits with high year-to-date profits need the Table 05 method.
  if first_band is not null and apit_base<first_band and cumulative>first_band*12 then
   perform people_payroll.statutory_blocked('STATUTORY_APIT_TABLE_05_REQUIRED');end if;
 end if;
 lines:=base->'lines';gross:=(base->>'gross')::numeric;deductions:=(base->>'deductions')::numeric;cost:=(base->>'employer_cost')::numeric;
 for r in select value from jsonb_array_elements(stat_rules) loop
  l:=case r->>'code'
   when 'EPF_EE' then people_payroll.statutory_line(r,epf_base,(rs->>'epf_employee_percent')::numeric,0)
   when 'EPF_ER' then people_payroll.statutory_line(r,epf_base,(rs->>'epf_employer_percent')::numeric,0)
   when 'ETF_ER' then people_payroll.statutory_line(r,etf_base,(rs->>'etf_employer_percent')::numeric,0)
   else people_payroll.statutory_line(r,apit_base,rate,reduction) end;
  if l->>'classification'='deduction' then deductions:=deductions+(l->>'amount')::numeric;
  else cost:=cost+(l->>'amount')::numeric;end if;
  lines:=lines||jsonb_build_array(l);
 end loop;
 if deductions>gross then raise exception using errcode='55000',message='PAYROLL_NEGATIVE_NET';end if;
 if greatest(gross,deductions,cost)>99999999999999.999999 then
  raise exception using errcode='22023',message='PAYROLL_AMOUNT_OVERFLOW';end if;
 return jsonb_build_object('lines',lines,'gross',round(gross,6)::text,'deductions',round(deductions,6)::text,
  'employer_cost',round(cost,6)::text,'net',round(gross-deductions,6)::text,
  'statutory',jsonb_build_object('rule_set_id',rs->>'id','epf_base',round(epf_base,6)::text,
   'etf_base',round(etf_base,6)::text,'apit_base',round(apit_base,6)::text,'apit_rate',rate::text,
   'apit_reduction',round(reduction,6)::text,'cumulative_regular_profits',round(cumulative,6)::text));
end $$;
revoke all on function people_payroll.calculate(jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function people_payroll.calculate_core(jsonb,jsonb,text) from public,anon,authenticated;

-- 8. API. Writes require MFA; approval needs a second person.
create function people_payroll.statutory_set_payload(s people_payroll.statutory_rule_sets) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',s.id,'country_code',s.country_code,'effective_from',s.effective_from,
  'effective_to_exclusive',s.effective_to_exclusive,'epf_employee_percent',s.epf_employee_percent::text,
  'epf_employer_percent',s.epf_employer_percent::text,'etf_employer_percent',s.etf_employer_percent::text,
  'apit_table',s.apit_table,'apit_bands',s.apit_bands,'sources',s.sources,'status',s.status,
  'proposed_by',s.proposed_by,'proposed_at',s.proposed_at,'approved_by',s.approved_by,'approved_at',s.approved_at,
  'retired_by',s.retired_by,'retired_at',s.retired_at)
$$;

create function api.people_payroll_statutory_rule_sets(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 return coalesce((select jsonb_agg(people_payroll.statutory_set_payload(s) order by s.effective_from desc,s.proposed_at desc)
  from people_payroll.statutory_rule_sets s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id),'[]'::jsonb);
end $$;

-- Proposes the shipped Sri Lanka values as a pending set. Values were checked on
-- 2026-11-20 and stay pending until an approver confirms them against the sources.
create function api.people_payroll_statutory_propose_lk(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_effective_from date,p_effective_to_exclusive date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s people_payroll.statutory_rule_sets%rowtype;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.configure',true);
 perform core.require_permission(p_tenant_id,'people.payroll.configure',p_legal_entity_id,null);
 if p_id is null or p_effective_from is null or p_effective_to_exclusive is null
  or p_effective_from<'2025-04-01'::date or p_effective_to_exclusive>'2027-04-01'::date
  or p_effective_to_exclusive<=p_effective_from then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_PERIOD_INVALID';end if;
 select * into s from people_payroll.statutory_rule_sets where id=p_id;
 if s.id is not null then
  if s.tenant_id<>p_tenant_id or s.legal_entity_id<>p_legal_entity_id or s.effective_from<>p_effective_from
   or s.effective_to_exclusive<>p_effective_to_exclusive then
   raise exception using errcode='55000',message='PAYROLL_STATUTORY_ID_CONFLICT';end if;
  return people_payroll.statutory_set_payload(s);
 end if;
 insert into people_payroll.statutory_rule_sets(id,tenant_id,legal_entity_id,country_code,effective_from,effective_to_exclusive,
  epf_employee_percent,epf_employer_percent,etf_employer_percent,apit_table,apit_bands,sources,proposed_by)
 values(p_id,p_tenant_id,p_legal_entity_id,'LK',p_effective_from,p_effective_to_exclusive,8,12,3,'LK_APIT_TABLE_01',
  '[{"upto":"150000","rate":"0","reduction":"0"},{"upto":"233333","rate":"6","reduction":"9000"},
    {"upto":"275000","rate":"18","reduction":"37000"},{"upto":"316667","rate":"24","reduction":"53500"},
    {"upto":"358333","rate":"30","reduction":"72500"},{"upto":null,"rate":"36","reduction":"94000"}]'::jsonb,
  jsonb_build_object('checked_on','2026-11-20',
   'apit_index','https://www.ird.gov.lk/en/publications/APIT_Tax_Tables/2025-2026/Index/01.%20APIT_2526_Index.pdf',
   'apit_table_01','https://www.ird.gov.lk/en/publications/APIT_Tax_Tables/2025-2026/Table%20-%201/02.%20APIT_2526_Table_01_Text.pdf',
   'epf','https://epf.lk/?page_id=811','etf','https://etfb.lk/employer-details/',
   'note','APIT Table 01 in force from 2025-04-01; the IRD index applies it to later years of assessment unless other tables are specified. EPF 8% employee and 12% employer; ETF 3% employer. Verify every value against the sources before approving.'),
  auth.uid())
 returning * into s;
 return people_payroll.statutory_set_payload(s);
end $$;

create function api.people_payroll_statutory_decide(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s people_payroll.statutory_rule_sets%rowtype;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.approve',true);
 perform core.require_permission(p_tenant_id,'people.payroll.approve',p_legal_entity_id,null);
 if p_action is null or p_action not in('approve','retire') then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_ACTION_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll.statutory:'||p_tenant_id||':'||p_legal_entity_id,0));
 select * into s from people_payroll.statutory_rule_sets where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_id for update;
 if s.id is null then raise exception using errcode='42501',message='PAYROLL_SCOPE_DENIED';end if;
 if p_action='approve' then
  if s.status<>'pending' then raise exception using errcode='55000',message='PAYROLL_STATUTORY_STATE_INVALID';end if;
  if s.proposed_by=auth.uid() then raise exception using errcode='42501',message='PAYROLL_STATUTORY_SEPARATE_APPROVER_REQUIRED';end if;
  if exists(select 1 from people_payroll.statutory_rule_sets o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id
   and o.status='approved' and daterange(o.effective_from,o.effective_to_exclusive,'[)') && daterange(s.effective_from,s.effective_to_exclusive,'[)')) then
   raise exception using errcode='55000',message='PAYROLL_STATUTORY_OVERLAP';end if;
  update people_payroll.statutory_rule_sets set status='approved',approved_by=auth.uid(),approved_at=clock_timestamp()
   where id=p_id returning * into s;
 else
  if s.status<>'approved' then raise exception using errcode='55000',message='PAYROLL_STATUTORY_STATE_INVALID';end if;
  update people_payroll.statutory_rule_sets set status='retired',retired_by=auth.uid(),retired_at=clock_timestamp()
   where id=p_id returning * into s;
 end if;
 return people_payroll.statutory_set_payload(s);
end $$;

create function api.people_payroll_component_statutory_set(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_component_id uuid,p_epf_liable boolean,p_etf_liable boolean,p_apit_regular_profit boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v bigint;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.configure',true);
 perform core.require_permission(p_tenant_id,'people.payroll.configure',p_legal_entity_id,null);
 if p_id is null or p_epf_liable is null or p_etf_liable is null or p_apit_regular_profit is null
  or length(btrim(coalesce(p_reason,''))) not between 1 and 1000
  or not exists(select 1 from people_payroll.components c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
   and c.id=p_component_id and c.classification='earning') then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_CLASSIFICATION_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll.statutory:'||p_tenant_id||':'||p_legal_entity_id,0));
 select coalesce(max(version),0) into v from people_payroll.component_statutory
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and component_id=p_component_id;
 insert into people_payroll.component_statutory(id,tenant_id,legal_entity_id,component_id,version,epf_liable,etf_liable,
  apit_regular_profit,reason,recorded_by)
 values(p_id,p_tenant_id,p_legal_entity_id,p_component_id,v+1,p_epf_liable,p_etf_liable,p_apit_regular_profit,btrim(p_reason),auth.uid());
 return jsonb_build_object('id',p_id,'component_id',p_component_id,'version',v+1,'epf_liable',p_epf_liable,
  'etf_liable',p_etf_liable,'apit_regular_profit',p_apit_regular_profit);
end $$;

create function api.people_payroll_employee_statutory_set(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_employee_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v bigint;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.configure',true);
 if p_id is null or coalesce(jsonb_typeof(p_payload),'null')<>'object'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('nic','epf_member_number','coverage','apit_case',
   'resident_or_citizen','primary_employment_declared','joined_or_left_in_year','reason'))
  or jsonb_typeof(p_payload->'resident_or_citizen') is distinct from 'boolean'
  or jsonb_typeof(p_payload->'primary_employment_declared') is distinct from 'boolean'
  or jsonb_typeof(p_payload->'joined_or_left_in_year') is distinct from 'boolean'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_EMPLOYEE_INVALID';end if;
 if not exists(select 1 from people.employment_assignments a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.branch_id=p_branch_id and a.employee_id=p_employee_id) then
  raise exception using errcode='42501',message='PAYROLL_SCOPE_DENIED';end if;
 perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_employee_id for update;
 select coalesce(max(version),0) into v from people_payroll.employee_statutory
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and employee_id=p_employee_id;
 insert into people_payroll.employee_statutory(id,tenant_id,legal_entity_id,employee_id,version,nic,epf_member_number,coverage,
  apit_case,resident_or_citizen,primary_employment_declared,joined_or_left_in_year,reason,recorded_by)
 values(p_id,p_tenant_id,p_legal_entity_id,p_employee_id,v+1,nullif(upper(btrim(p_payload->>'nic')),''),
  nullif(upper(btrim(p_payload->>'epf_member_number')),''),p_payload->>'coverage',p_payload->>'apit_case',
  (p_payload->>'resident_or_citizen')::boolean,(p_payload->>'primary_employment_declared')::boolean,
  (p_payload->>'joined_or_left_in_year')::boolean,btrim(p_payload->>'reason'),auth.uid());
 return jsonb_build_object('id',p_id,'employee_id',p_employee_id,'version',v+1);
end $$;

-- Full identifiers only for configure holders; everyone else never reads them.
create function api.people_payroll_employee_statutory(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_employee_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s people_payroll.employee_statutory%rowtype;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.configure');
 if not exists(select 1 from people.employment_assignments a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.branch_id=p_branch_id and a.employee_id=p_employee_id) then
  raise exception using errcode='42501',message='PAYROLL_SCOPE_DENIED';end if;
 select * into s from people_payroll.employee_statutory where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and employee_id=p_employee_id order by version desc limit 1;
 if s.id is null then return null;end if;
 return jsonb_build_object('employee_id',s.employee_id,'version',s.version,'nic',s.nic,'epf_member_number',s.epf_member_number,
  'coverage',s.coverage,'apit_case',s.apit_case,'resident_or_citizen',s.resident_or_citizen,
  'primary_employment_declared',s.primary_employment_declared,'joined_or_left_in_year',s.joined_or_left_in_year,
  'recorded_by',s.recorded_by,'recorded_at',s.recorded_at);
end $$;

create function api.people_payroll_employer_registration_set(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_epf_employer_number text,p_etf_employer_number text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v bigint;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.configure',true);
 perform core.require_permission(p_tenant_id,'people.payroll.configure',p_legal_entity_id,null);
 if p_id is null or length(btrim(coalesce(p_reason,''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='PAYROLL_STATUTORY_REGISTRATION_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll.statutory:'||p_tenant_id||':'||p_legal_entity_id,0));
 select coalesce(max(version),0) into v from people_payroll.employer_registrations
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id;
 insert into people_payroll.employer_registrations(id,tenant_id,legal_entity_id,version,epf_employer_number,etf_employer_number,reason,recorded_by)
 values(p_id,p_tenant_id,p_legal_entity_id,v+1,upper(btrim(p_epf_employer_number)),upper(btrim(p_etf_employer_number)),btrim(p_reason),auth.uid());
 return jsonb_build_object('id',p_id,'version',v+1);
end $$;

create function api.people_payroll_employer_registration(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s people_payroll.employer_registrations%rowtype;begin
 perform people_payroll.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view');
 select * into s from people_payroll.employer_registrations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  order by version desc limit 1;
 if s.id is null then return null;end if;
 return jsonb_build_object('version',s.version,'epf_employer_number',s.epf_employer_number,
  'etf_employer_number',s.etf_employer_number,'recorded_by',s.recorded_by,'recorded_at',s.recorded_at);
end $$;

do $$declare f text;begin
 foreach f in array array[
  'api.people_payroll_statutory_rule_sets(uuid,uuid,uuid)',
  'api.people_payroll_statutory_propose_lk(uuid,uuid,uuid,uuid,date,date)',
  'api.people_payroll_statutory_decide(uuid,uuid,uuid,uuid,text)',
  'api.people_payroll_component_statutory_set(uuid,uuid,uuid,uuid,uuid,boolean,boolean,boolean,text)',
  'api.people_payroll_employee_statutory_set(uuid,uuid,uuid,uuid,uuid,jsonb)',
  'api.people_payroll_employee_statutory(uuid,uuid,uuid,uuid)',
  'api.people_payroll_employer_registration_set(uuid,uuid,uuid,uuid,text,text,text)',
  'api.people_payroll_employer_registration(uuid,uuid,uuid)'] loop
  execute format('revoke all on function %s from public,anon',f);
  execute format('grant execute on function %s to authenticated',f);
 end loop;
 foreach f in array array[
  'people_payroll.statutory_kind_valid(text,text)','people_payroll.statutory_bands_valid(jsonb)',
  'people_payroll.statutory_blocked(text)','people_payroll.statutory_line(jsonb,numeric,numeric,numeric)',
  'people_payroll.statutory_set_payload(people_payroll.statutory_rule_sets)'] loop
  execute format('revoke all on function %s from public,anon,authenticated',f);
 end loop;
end $$;
