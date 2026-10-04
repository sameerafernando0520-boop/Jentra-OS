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
 service_date date not null,purpose text not null,evidence_reference text not null,original_currency text not null references core.currencies(code),base_currency text not null references core.currencies(code),
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
 if status='cancelled' then update projects.billable_units set status='cancelled' where tenant_id=t and legal_entity_id=e and provider_source_id=labor and source_kind='service' and status='available';end if;
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
 perform projects.text(terms->'payment_terms',500);
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
 fxdata jsonb;taxdata jsonb:='{}';allocation jsonb;weight_total numeric;weight_sum numeric:=0;allocated numeric:=0;part numeric;ord integer:=0;digest text;
 lines jsonb:='[]';doc jsonb;answer jsonb;outcome jsonb;before_state jsonb:='{}';journal uuid;request uuid:=gen_random_uuid();posting_date date;amount numeric;outstanding numeric;invoice uuid;invoice_version bigint;unit_ids uuid[];line uuid;service_ids uuid[];service_employees uuid[];
begin
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>65536 or id is null or project is null or p_command_id is null or p_idempotency_key is null or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 then raise exception using errcode='22023',message='PROJECT_FINANCE_COMMAND_INVALID';end if;
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,projects.finance_cap(act));reason:=projects.text(p_payload->'reason',1000);
 allowed:=case when act in('expense_create','expense_correct') then array['action','id','project_id','employee_id','external_reference','service_date','purpose','evidence_reference','original_currency','original_precision','net','tax','gross','tax_definition_id','tax_version','no_tax_reason','exchange_rate_id','exchange_rate_version','expense_account_id','tax_account_id','liability_account_id','billable','bill_amount','allocations','reason']
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
 hash:=core.wave3_request_hash('projects.finance.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'projects.finance.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 -- Shared provider lock order: payroll -> projects -> service advisories,
 -- then sorted employees, tickets, work orders, labor and project source rows.
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
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
   digest:=encode(extensions.digest(convert_to((p_payload-array['action','reason'])::text,'UTF8'),'sha256'),'hex');
   if act='expense_create' then insert into projects.expenses(id,tenant_id,legal_entity_id,branch_id,project_id,employee_id,current_revision_id,external_reference,created_by)
    values(id,p_tenant_id,p_legal_entity_id,p_branch_id,project,(p_payload->>'employee_id')::uuid,new_revision,p_payload->>'external_reference',auth.uid());
   else update projects.expenses set version=version+1,current_revision_id=new_revision,status='draft',submitted_by=null where expenses.id=id;end if;
   insert into projects.expense_revisions(id,tenant_id,legal_entity_id,project_id,expense_id,version,service_date,purpose,evidence_reference,original_currency,base_currency,original_precision,base_precision,
    net,tax,gross,base_net,base_tax,base_gross,tax_rounding_residue,tax_definition_id,tax_version,tax_basis,no_tax_reason,exchange_rate_id,exchange_rate_version,fx_numerator,fx_denominator,fx_basis,
    expense_account_id,tax_account_id,liability_account_id,billable,bill_amount,digest,reason,recorded_by,supersedes_id)
   values(new_revision,p_tenant_id,p_legal_entity_id,project,id,p_expected_version+1,posting_date,p_payload->>'purpose',p_payload->>'evidence_reference',p_payload->>'original_currency',base,original_scale,scale,
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
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability);
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'actor_id',auth.uid(),'capability',p_capability,'authorized',true,'supplier_ap_available',false,'attachments_available',false,'sales_available',true);
end $$;
create function api.projects_finance_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_kind text,p_after uuid default null,p_target_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;cap text;begin
 cap:=case when p_kind in('billing','units') then 'projects.billing.manage' when p_kind='obligations' or p_kind='settlements' then 'projects.expenses.settle' else 'projects.cost.view' end;
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap);
 if not exists(select 1 from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_project_id) then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 if p_kind='expenses' then
  select coalesce(jsonb_agg(q.body order by q.id),'[]') into items from(select x.id,
   projects.expense_summary(x.id)||jsonb_build_object('employee_name',emp.display_name,'external_reference',x.external_reference,'purpose',v.purpose,'service_date',v.service_date,'evidence_reference',v.evidence_reference,
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
returns jsonb language plpgsql stable security definer set search_path='' as $$declare response jsonb;begin
 perform projects.finance_access(p_tenant_id,p_legal_entity_id,p_branch_id,projects.finance_cap(p_action));
 select r.response into response from core.command_receipts r where r.tenant_id=p_tenant_id and r.command_name='projects.finance.'||p_action and r.command_id=p_command_id and r.actor_id=auth.uid();
 if response is null then return null;end if;
 if(response#>>'{entity,tenant_id}')::uuid<>p_tenant_id or(response#>>'{entity,legal_entity_id}')::uuid<>p_legal_entity_id or(response#>>'{entity,branch_id}')::uuid<>p_branch_id then raise exception using errcode='42501',message='PROJECT_FINANCE_SCOPE_DENIED';end if;return response;
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
 select coalesce(sum(q.amount),0) into service_cost from(select distinct on(c.provider_source_id) c.amount from projects.service_cost_revisions c
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.branch_id=p_branch_id and c.project_id=p_project_id and c.recorded_at<=p_as_of
   and c.service_date<=p_effective_date order by c.provider_source_id,c.source_version desc,c.recorded_at desc) q;
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
