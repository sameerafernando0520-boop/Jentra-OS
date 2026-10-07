begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
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

-- Legitimate approved worked geometry changes are a distinct linked vertical.
insert into core.role_permissions(tenant_id,role_id,permission_code) values
 (pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'people.payroll.post') on conflict do nothing;
create function pg_temp.geometry_prepare() returns jsonb language sql security definer as $$
 select pg_temp.correction_prepare(7200,'corr.geometry')||jsonb_build_object('replacements',jsonb_build_array(
 (pg_temp.correction_prepare(7200,'corr.geometry')->'replacements'->0)||jsonb_build_object('impact',jsonb_build_object(
  'mode','geometry','expected_source_version',a.version,'start_local',to_char(r.start_local,'YYYY-MM-DD"T"HH24:MI:SS'),
  'end_local',to_char(r.end_local+interval '1 hour','YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',r.start_offset_seconds,'end_offset_seconds',r.end_offset_seconds,'breaks',r.breaks))))
 from people.attendance_entries a join people.attendance_revisions r on r.id=a.current_revision_id where a.id=pg_temp.wid('corr.attendance') $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.geometry_prepare(),0,'corr.geometry.prepare');
insert into payroll_assertions select is(pg_temp.cdetail('calculation','corr.geometry')->'items'->0->'difference'->>'net','100.000000','geometry difference can increase legitimate approved worked seconds');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','corr.geometry'),1,'corr.geometry.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','corr.geometry'),2,'corr.fail.post')$q$,'P0001','SYNTHETIC_CORRECTION_LATE_FAILURE','late geometry posting failure rolls back source and payroll together');
reset role;
insert into payroll_assertions select is((select payable_seconds from people.attendance_revisions where id=(select current_revision_id from people.attendance_entries where id=pg_temp.wid('corr.attendance'))),3600::bigint,'failed geometry post retains original worked duration');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','corr.geometry'),2,'corr.geometry.post');
reset role;
create function pg_temp.geometry_reverse_credits() returns jsonb language sql security definer as $$
 select pg_temp.correction_action('reverse','corr.geometry')||jsonb_build_object('current_billing_impacts',jsonb_build_array(
  jsonb_build_object('seal_id',s.seal_id,'source_revision_id',state.body->>'operational_source_id',
   'expected_source_version',(state.body->>'operational_source_version')::bigint,
   'billing_credit_line_ids','[]'::jsonb,'allocation_credits','[]'::jsonb)))
 from people_payroll.correction_sources s cross join lateral(select people_payroll.correction_source_state(s.seal_id) body) state
 where s.correction_id=pg_temp.wid('corr.geometry') $$;
insert into payroll_assertions select is((select payable_seconds from people.attendance_revisions where id=(select current_revision_id from people.attendance_entries where id=pg_temp.wid('corr.attendance'))),7200::bigint,'geometry post appends authoritative approved attendance revision');
insert into payroll_assertions select is((select count(*)::integer from people.attendance_revisions where entry_id=pg_temp.wid('corr.attendance')),2,'original attendance revision remains immutable');
insert into payroll_assertions select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and active),1,'geometry replacement has one current payable owner');
insert into payroll_assertions select throws_ok($q$select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),
 (select active_claim_id from people.attendance_entries where id=pg_temp.wid('corr.attendance')))$q$,'55000','PAYROLL_INPUT_SEALED','replacement source retains ordinary payroll seal guard');
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.geometry_reverse_credits()||jsonb_build_object('current_billing_impacts',jsonb_build_array(
 (pg_temp.geometry_reverse_credits()->'current_billing_impacts'->0)||jsonb_build_object('expected_source_version',1))),3,'corr.geometry.stale.current')$q$,
 '40001','PAYROLL_CORRECTION_SOURCE_CHANGED','current reverse source version is authoritative before credit proof');
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.geometry_reverse_credits()||jsonb_build_object('current_billing_impacts',jsonb_build_array(
 (pg_temp.geometry_reverse_credits()->'current_billing_impacts'->0)||jsonb_build_object('billing_credit_line_ids',jsonb_build_array(pg_temp.wid('foreign.credit'))))),3,'corr.geometry.foreign.current')$q$,
 '22023','PAYROLL_CURRENT_BILLING_IMPACT_INVALID','attendance cannot claim direct customer credit proof');
select pg_temp.cc(pg_temp.geometry_reverse_credits(),3,'corr.geometry.reverse');
reset role;
insert into payroll_assertions select is((select payable_seconds from people.attendance_revisions where id=(select current_revision_id from people.attendance_entries where id=pg_temp.wid('corr.attendance'))),3600::bigint,'geometry reversal appends original-basis geometry as a fresh approved revision');
insert into payroll_assertions select is((select count(*)::integer from people.attendance_revisions where entry_id=pg_temp.wid('corr.attendance')),3,'geometry reversal never rewrites prior revisions');
insert into payroll_assertions select is((select count(*)::integer from people.attendance_events where entry_id=pg_temp.wid('corr.attendance') and action='correct'),2,'native attendance history retains linked apply and original-basis reversal');
insert into payroll_assertions select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and active),1,'geometry reversal retains exactly one current payable owner');
insert into payroll_assertions select ok(not has_function_privilege('authenticated','people_payroll.replace_claim(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,timestamptz,timestamptz,jsonb,uuid)','EXECUTE'),'trusted claim replacement unavailable to clients');
insert into payroll_assertions select ok(not has_function_privilege('authenticated','people_payroll.source_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)','EXECUTE'),'trusted source impact unavailable to clients');

-- Approved paid leave: corrections reverse original grant effects atomically.
create function pg_temp.clp(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_leave_policy_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
create function pg_temp.clr(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.people_leave_request_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
create function pg_temp.clreq(key text,day_offset integer) returns jsonb language sql as $$
 select jsonb_build_object('action','create','id',pg_temp.wid(key),'employee_id',pg_temp.wid('manager'),
  'policy_version_id',pg_temp.wid('corr.leave.policy.v1'),'calendar_version_id',pg_temp.wid('calendar-version'),
  'start_local',to_char((pg_temp.wdate()+day_offset)::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),
  'end_local',to_char((pg_temp.wdate()+day_offset)::timestamp+interval '10 hours','YYYY-MM-DD"T"HH24:MI:SS'),
  'start_offset_seconds',19800,'end_offset_seconds',19800,'reason','Synthetic original paid leave') $$;
create function pg_temp.clstate(act text,key text,balance bigint default null) returns jsonb language sql as $$
 select jsonb_build_object('action',act,'id',pg_temp.wid(key),'employee_id',pg_temp.wid('manager'),'reason','Synthetic leave decision')||
 case when balance is null then '{}'::jsonb else jsonb_build_object('balance_version',balance) end $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.clp(jsonb_build_object('action','create','id',pg_temp.wid('corr.leave.policy'),'version_id',pg_temp.wid('corr.leave.policy.v1'),
 'code','CORRLEAVE','name','Synthetic correction leave','start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,
 'unit','hours','day_seconds',28800,'accrual_frequency','once','accrual_seconds',3600,'carry_cap_seconds',3600,'expiry_days',365,
 'eligible_types',jsonb_build_array('permanent'),'allow_unpaid',false,'reason','Synthetic leave policy'),0,'corr.leave.policy.create');
select api.people_leave_grant_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('corr.leave.grant'),pg_temp.wid('corr.leave.grant'),now(),
 jsonb_build_object('action','adjust','id',pg_temp.wid('corr.leave.grant'),'employee_id',pg_temp.wid('manager'),
 'policy_version_id',pg_temp.wid('corr.leave.policy.v1'),'effective_date',pg_temp.wdate(),'source_key','CORR-LEAVE-GRANT','seconds',3600,'reason','Synthetic original grant'),0);
select pg_temp.clr(pg_temp.clreq('corr.leave.request',7),0,'corr.leave.create');
select pg_temp.clr(pg_temp.clstate('submit','corr.leave.request'),1,'corr.leave.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.clr(pg_temp.clstate('approve','corr.leave.request',1),2,'corr.leave.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_create('corr.leave.run')||jsonb_build_object('start_date',pg_temp.wdate()+7,'end_date_exclusive',pg_temp.wdate()+8,
 'posting_date',pg_temp.wdate()+8,'employee_ids',jsonb_build_array(pg_temp.wid('manager'))),0,'corr.leave.run.create');
select pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('corr.leave.run'),'reason','Synthetic leave freeze'),1,'corr.leave.run.prepare');
select pg_temp.pcmd(pg_temp.run_action('submit','corr.leave.run'),2,'corr.leave.run.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('approve','corr.leave.run'),3,'corr.leave.run.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('post','corr.leave.run'),4,'corr.leave.run.post');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.clr(pg_temp.clstate('cancel','corr.leave.request',2),3,'corr.leave.ordinary.cancel')$q$,'55000','PAYROLL_INPUT_SEALED','ordinary cancellation of payroll sealed leave remains guarded');
reset role;
create function pg_temp.leave_correction_prepare() returns jsonb language sql security definer as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid('corr.leave.cancel'),'original_calculation_id',c.id,'posting_date',pg_temp.wdate()+8,
 'reason','Synthetic linked original paid leave cancellation','replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,
 'before_revision_id',people_payroll.correction_source_state(s.id)->>'revision_id','expected_version',(people_payroll.correction_source_state(s.id)->>'version')::bigint,
 'paid_seconds',0,'impact',jsonb_build_object('mode','cancel_leave','expected_source_version',l.version))))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 join people.leave_requests l on l.active_claim_id=s.claim_id where c.run_id=pg_temp.wid('corr.leave.run') $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.leave_correction_prepare(),0,'corr.leave.cancel.prepare');
insert into payroll_assertions select is(pg_temp.cdetail('calculation','corr.leave.cancel')->'items'->0->'difference'->>'net','-100.000000','paid leave correction recomputes original rounded payroll basis');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','corr.leave.cancel'),1,'corr.leave.cancel.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','corr.leave.cancel'),2,'corr.fail.post')$q$,'P0001','SYNTHETIC_CORRECTION_LATE_FAILURE','late paid leave post failure rolls back source balance and journal');
reset role;
insert into payroll_assertions select is((select status from people.leave_requests where id=pg_temp.wid('corr.leave.request')),'approved','failed paid leave impact retains approved request');
insert into payroll_assertions select is((select sum(seconds) from people.leave_effects where request_id=pg_temp.wid('corr.leave.request')),-3600::numeric,'failed paid leave impact retains original debit');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','corr.leave.cancel'),2,'corr.leave.cancel.post');
insert into payroll_assertions select is(api.people_leave_balance(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),pg_temp.wid('corr.leave.policy'),pg_temp.wdate()+7)->>'available_seconds','3600','linked cancellation restores original grant balance');
insert into payroll_assertions select is(jsonb_array_length(api.people_payroll_correction_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select response->'entity'->>'original_calculation_id' from correction_client_samples where name='prepared')::uuid)->'items'),1,'source picker retains original identity after unrelated linked correction');
select pg_temp.clr(pg_temp.clreq('corr.leave.consumer',14),0,'corr.leave.consumer.create');
select pg_temp.clr(pg_temp.clstate('submit','corr.leave.consumer'),1,'corr.leave.consumer.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.clr(pg_temp.clstate('approve','corr.leave.consumer',3),2,'corr.leave.consumer.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('reverse','corr.leave.cancel')||jsonb_build_object('posting_date',pg_temp.wdate()+15),3,'corr.leave.cancel.blocked.reverse')$q$,'55000','LEAVE_ORIGINAL_BALANCE_IMPACT_REQUIRED','reversal refuses a restored original grant already consumed by later leave');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.clr(pg_temp.clstate('cancel','corr.leave.consumer',4),3,'corr.leave.consumer.cancel');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','corr.leave.cancel')||jsonb_build_object('posting_date',pg_temp.wdate()+15),3,'corr.leave.cancel.reverse');
insert into payroll_assertions select is(api.people_leave_balance(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),pg_temp.wid('corr.leave.policy'),pg_temp.wdate()+7)->>'available_seconds','0','reversal reconsumes exact original grant with a new negative effect');
reset role;
insert into payroll_assertions select is((select status from people.leave_requests where id=pg_temp.wid('corr.leave.request')),'approved','leave reversal restores original approved operational request');
insert into payroll_assertions select is((select count(*)::integer from people.leave_effects where request_id=pg_temp.wid('corr.leave.request')),3,'original debit cancellation and reversal remain immutable');
insert into payroll_assertions select is((select count(*)::integer from people.leave_events where request_id=pg_temp.wid('corr.leave.request')),5,'native leave history retains linked cancellation and original-basis reversal');
insert into payroll_assertions select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and source_kind='leave' and active),1,'leave reversal restores exactly one active payable owner');
insert into payroll_assertions select is((select net from people_payroll.employee_calculations where run_id=pg_temp.wid('corr.leave.run')),100::numeric,'original posted leave calculation remains unchanged');
insert into payroll_assertions select throws_ok($q$select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),
 (select active_claim_id from people.leave_requests where id=pg_temp.wid('corr.leave.request')))$q$,'55000','PAYROLL_INPUT_SEALED','restored paid leave remains sealed against ordinary cancellation');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.attendance.approve';
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_action('post','corr.geometry'),2,'corr.geometry.post')$q$,'42501',null,'source authority is rechecked before confirmed post replay');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'people.attendance.approve') on conflict do nothing;
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code in('people.payroll.correction.prepare','people.attendance.manage');
select pg_temp.wactor('creator');set local role authenticated;
insert into payroll_assertions select ok(jsonb_array_length(api.people_payroll_correction_sources(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 (select response->'entity'->>'original_calculation_id' from correction_client_samples where name='prepared')::uuid)->'items')>0,
 'independent source reader can inspect current facts without preparation authority');
insert into payroll_assertions select throws_ok($q$select pg_temp.cc(pg_temp.correction_prepare(1800),0,'corr.prepare')$q$,'42501',null,
 'preparation authority remains required before confirmed prepare replay');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('creator.role'),p from unnest(array['people.payroll.correction.prepare','people.attendance.manage']) p on conflict do nothing;
-- Real scoped common ownership rows exercise the bound before module effects.
create temporary table correction_bound_claim as
 select people.make_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),
 'attendance',pg_temp.wid('corr.bound.source'),((pg_temp.wdate()+28)::timestamp+interval '9 hours') at time zone 'Asia/Colombo',
 ((pg_temp.wdate()+28)::timestamp+interval '10 hours') at time zone 'Asia/Colombo','[]',pg_temp.wid('calendar-version'),pg_temp.wid('creator')) id;
insert into people.work_allocations(id,tenant_id,legal_entity_id,branch_id,employee_id,claim_id,source_kind,source_id,start_utc,end_utc,created_by)
select pg_temp.wid('corr.bound.allocation.'||i),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),c.id,
 'project',pg_temp.wid('corr.bound.project.source.'||i),w.start_utc+make_interval(secs=>i*2),w.start_utc+make_interval(secs=>i*2+1),pg_temp.wid('creator')
from generate_series(1,51) i cross join correction_bound_claim c join people.work_claims w on w.id=c.id;
insert into payroll_assertions select throws_ok($q$select people_payroll.linked_allocation_bound(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('manager'),(select id from correction_bound_claim),'[]')$q$,'55000','WORK_ALLOCATION_IMPACT_BOUND_REQUIRED',
 '51 scoped distinct allocated sources fail before linked module effects');
select people.revoke_work_allocation(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),pg_temp.wid('corr.bound.allocation.51'));
create function pg_temp.cbound_ok() returns boolean language plpgsql as $$begin
 perform people_payroll.linked_allocation_bound(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('manager'),(select id from correction_bound_claim),'[]');return true;end $$;
insert into payroll_assertions select ok(pg_temp.cbound_ok(),'50 scoped distinct allocated sources remain within bound');
insert into payroll_assertions select throws_ok($q$select people_payroll.linked_allocation_bound(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),null,
 (select jsonb_agg(jsonb_build_object('source_kind','project','impact',jsonb_build_object('entry_id',pg_temp.wid('corr.bound.project.entry.'||i))))
  from generate_series(1,51) i))$q$,'55000','WORK_ALLOCATION_IMPACT_BOUND_REQUIRED',
 '51 frozen removed origins fail the reversal bound without truncation');
select people.revoke_work_allocation(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),a.id)
from people.work_allocations a where a.claim_id=(select id from correction_bound_claim) and a.active order by a.id;
select people.revoke_work_claim(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('manager'),(select id from correction_bound_claim));

do $$declare failed text;begin
 select string_agg(message,chr(10)) into failed from payroll_assertions where message like 'not ok%';
 if failed is not null then raise exception using errcode='P0001',message=failed;end if;
end $$;
set constraints all immediate;
select * from finish(true);
rollback;