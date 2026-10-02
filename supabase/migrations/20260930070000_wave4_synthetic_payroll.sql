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
