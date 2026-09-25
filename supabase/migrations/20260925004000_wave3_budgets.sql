-- UNAPPLIED AC-320 budget candidate. Compose and exercise only in ROLLBACK.
-- Journal lines presently have account, branch and currency dimensions. Cost
-- centre and project inputs fail closed until governed models/postings exist.
insert into core.permissions(code,module,description,privileged) values
 ('finance.budgets.approve','finance','Independently approve submitted budgets.',true)
on conflict(code) do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select r.tenant_id,r.id,'finance.budgets.approve' from core.roles r
where r.code='tenant_owner' on conflict(role_id,permission_code) do nothing;

create table finance.budget_versions (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 root_id uuid not null,revision integer not null check(revision>0),
 period_id uuid,budget_year integer not null check(budget_year between 2000 and 2100),
 branch_id uuid,currency_code text not null references core.currencies(code),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 500),
 status text not null check(status in('draft','submitted','approved','rejected')),
 version bigint not null check(version>0),reason text not null
  check(length(trim(reason)) between 3 and 1000),
 created_by uuid not null references auth.users(id),submitted_by uuid references auth.users(id),
 decided_by uuid references auth.users(id),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),decided_at timestamptz,
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,root_id,revision),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,period_id)
  references finance.fiscal_periods(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id)
);
create index budget_scope on finance.budget_versions(tenant_id,legal_entity_id,id);
create index budget_root on finance.budget_versions(tenant_id,root_id,revision desc);
create index budget_actor on finance.budget_versions(created_by);
alter table finance.budget_versions enable row level security;
alter table finance.budget_versions force row level security;
revoke all on finance.budget_versions from public,anon,authenticated;
create function finance.guard_budget_mutation() returns trigger
language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or old.status in('approved','rejected')
  or new.tenant_id is distinct from old.tenant_id
  or new.legal_entity_id is distinct from old.legal_entity_id
  or new.root_id is distinct from old.root_id
  or new.revision is distinct from old.revision
  or new.period_id is distinct from old.period_id
  or new.budget_year is distinct from old.budget_year
  or new.branch_id is distinct from old.branch_id
  or new.currency_code is distinct from old.currency_code then
  raise exception using errcode='55000',message='BUDGET_HISTORY_IMMUTABLE';end if;
 return new;
end$$;
create trigger budget_guard before update or delete on finance.budget_versions
 for each row execute function finance.guard_budget_mutation();

create table finance.budget_events (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,
 legal_entity_id uuid not null,budget_id uuid not null,version bigint not null,
 action text not null,reason text not null,snapshot jsonb not null,
 actor_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),unique(tenant_id,budget_id,version),
 foreign key(tenant_id,budget_id) references finance.budget_versions(tenant_id,id)
);
create index budget_events_actor on finance.budget_events(actor_id);
alter table finance.budget_events enable row level security;
alter table finance.budget_events force row level security;
revoke all on finance.budget_events from public,anon,authenticated;
create trigger immutable before update or delete on finance.budget_events
 for each row execute function workflow.reject_history_mutation();

create function finance.validate_budget_lines(t uuid,e uuid,lines jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare x jsonb;out_rows jsonb:='[]';ids uuid[]:='{}';accounts uuid[]:='{}';
 id uuid;account uuid;amount text;begin
 if jsonb_typeof(lines)<>'array' or jsonb_array_length(lines) not between 1 and 500 then
  raise exception using errcode='22023',message='BUDGET_LINES_INVALID';end if;
 for x in select value from jsonb_array_elements(lines) loop
  if jsonb_typeof(x)<>'object' or x->>'cost_centre_id' is not null
   or x->>'project_id' is not null then
   raise exception using errcode='22023',message='BUDGET_DIMENSION_UNAVAILABLE';end if;
  id:=(x->>'id')::uuid;account:=(x->>'account_id')::uuid;amount:=x->>'amount';
  if id is null or account is null or id=any(ids) or account=any(accounts)
   or jsonb_typeof(x->'amount')<>'string' or amount is null
   or amount !~ '^\d+(\.\d{1,6})?$'
   or length(amount)>35 or amount::numeric>99999999999999 then
   raise exception using errcode='22023',message='BUDGET_LINE_INVALID';end if;
  if not exists(select 1 from finance.accounts a where a.tenant_id=t
   and a.legal_entity_id=e and a.id=account and a.status='active' and a.is_posting) then
   raise exception using errcode='22023',message='BUDGET_ACCOUNT_INVALID';end if;
  ids:=array_append(ids,id);accounts:=array_append(accounts,account);
  out_rows:=out_rows||jsonb_build_array(jsonb_build_object('id',id,
   'account_id',account,'amount',(amount::numeric(20,6))::text,
   'cost_centre_id',null,'project_id',null));
 end loop;
 return out_rows;
end$$;

create function api.budget_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;
 act text:=p_payload->>'action';v_id uuid:=(p_payload->>'id')::uuid;
 source_id uuid:=(p_payload->>'source_id')::uuid;
 budget finance.budget_versions%rowtype;source_budget finance.budget_versions%rowtype;
 period finance.fiscal_periods%rowtype;year_value integer;budget_branch uuid;
 currency text;reason text:=trim(p_payload->>'reason');v_lines jsonb;
 before_row jsonb;result jsonb;h text;r jsonb;req uuid:=gen_random_uuid();begin
 perform core.wave3_require_scope(t,case when act in('approve','reject') then
  'finance.budgets.approve' else 'finance.budgets.manage' end,e,null);
 perform core.wave3_require_scope(t,case when act in('approve','reject') then
  'finance.budgets.approve' else 'finance.budgets.manage' end,e,b);
 if act not in('create','save','submit','approve','reject','revise') or act is null
  or v_id is null or p_client_timestamp is null or reason is null
  or length(reason) not between 3 and 1000 then
  raise exception using errcode='22023',message='BUDGET_COMMAND_INVALID';end if;
 h:=core.wave3_request_hash('finance.budgets.'||act,p_command_id,t,e,b,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(t,'finance.budgets.'||act,p_command_id,p_idempotency_key,h);
 if r is not null then return r;end if;
 if act in('create','revise') then
  if act='revise' then
   select * into source_budget from finance.budget_versions where tenant_id=t and legal_entity_id=e
    and id=source_id and status='approved' for update;
   if not found then raise exception using errcode='55000',message='BUDGET_APPROVED_SOURCE_REQUIRED';end if;
   if source_budget.branch_id is not null and source_budget.branch_id<>b then
    raise exception using errcode='42501',message='BUDGET_BRANCH_SCOPE_REQUIRED';end if;
   perform core.wave3_assert_expected_version(source_budget.version,
    p_expected_entity_version,to_jsonb(source_budget));
   if exists(select 1 from finance.budget_versions where tenant_id=t and root_id=source_budget.root_id
    and revision>source_budget.revision) then
    raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
   v_lines:=source_budget.lines;budget_branch:=source_budget.branch_id;
   year_value:=source_budget.budget_year;currency:=source_budget.currency_code;
   budget.period_id:=source_budget.period_id;
  else
   perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
   budget.period_id:=(p_payload->>'period_id')::uuid;
   year_value:=(p_payload->>'budget_year')::integer;
   budget_branch:=(p_payload->>'branch_id')::uuid;
   currency:=p_payload->>'currency_code';
   if budget_branch is not null and budget_branch<>b then
    raise exception using errcode='42501',message='BUDGET_BRANCH_SCOPE_REQUIRED';end if;
   if budget_branch is not null and not exists(select 1 from core.branches
    where tenant_id=t and legal_entity_id=e and id=budget_branch and status='active') then
    raise exception using errcode='22023',message='BUDGET_BRANCH_INVALID';end if;
   if year_value not between 2000 and 2100 or year_value is null
    or currency is null or not exists(select 1 from core.currencies where code=currency) then
    raise exception using errcode='22023',message='BUDGET_BASIS_INVALID';end if;
   if budget.period_id is not null then
    select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
     and id=budget.period_id and status='active';
    if not found or extract(year from period.start_date)::integer<>year_value then
     raise exception using errcode='22023',message='BUDGET_PERIOD_INVALID';end if;
   end if;
   v_lines:=finance.validate_budget_lines(t,e,p_payload->'lines');
  end if;
  insert into finance.budget_versions(id,tenant_id,legal_entity_id,root_id,revision,
   period_id,budget_year,branch_id,currency_code,lines,status,version,reason,created_by)
  values(v_id,t,e,case when act='create' then v_id else source_budget.root_id end,
   case when act='create' then 1 else source_budget.revision+1 end,budget.period_id,
   year_value,budget_branch,currency,v_lines,'draft',1,reason,auth.uid());
 else
  select * into budget from finance.budget_versions where tenant_id=t and legal_entity_id=e
   and id=v_id for update;
  if not found then raise exception using errcode='42501',message='BUDGET_SCOPE_REQUIRED';end if;
  if budget.branch_id is not null and budget.branch_id<>b then
   raise exception using errcode='42501',message='BUDGET_BRANCH_SCOPE_REQUIRED';end if;
  perform core.wave3_assert_expected_version(budget.version,p_expected_entity_version,to_jsonb(budget));
  before_row:=to_jsonb(budget);
  if act in('save','submit') and budget.status<>'draft' or
   act in('approve','reject') and budget.status<>'submitted' then
   raise exception using errcode='55000',message='BUDGET_STATE_INVALID';end if;
  if act in('approve','reject') and auth.uid() in(budget.created_by,budget.submitted_by) then
   raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
  if act='save' then
   v_lines:=finance.validate_budget_lines(t,e,p_payload->'lines');
   update finance.budget_versions set lines=v_lines,version=version+1,updated_at=now()
    where tenant_id=t and id=budget.id;
  else
   update finance.budget_versions set status=case act when 'submit' then 'submitted'
    when 'approve' then 'approved' else 'rejected' end,version=version+1,
    submitted_by=case when act='submit' then auth.uid() else submitted_by end,
    decided_by=case when act in('approve','reject') then auth.uid() else decided_by end,
    decided_at=case when act in('approve','reject') then now() else decided_at end,
    updated_at=now() where tenant_id=t and id=budget.id;
  end if;
 end if;
 select * into budget from finance.budget_versions v where v.tenant_id=t and v.id=v_id;
 insert into finance.budget_events(tenant_id,legal_entity_id,budget_id,version,action,reason,snapshot,actor_id)
 values(t,e,budget.id,budget.version,act,reason,to_jsonb(budget),auth.uid());
 result:=jsonb_build_object('id',budget.id,'tenant_id',t,'legal_entity_id',e,
  'branch_id',b,'budget_branch_id',budget.branch_id,'root_id',budget.root_id,
  'revision',budget.revision,'period_id',budget.period_id,'budget_year',budget.budget_year,
  'currency_code',budget.currency_code,'line_count',jsonb_array_length(budget.lines),
  'lines',budget.lines,'status',budget.status,'version',budget.version,
  'reason',budget.reason,'created_by',budget.created_by);
 return core.wave3_finish_command(t,'finance.budgets.'||act,p_command_id,'budget',v_id,
  p_idempotency_key,h,before_row,result,e,b,
  jsonb_build_object('period_id',budget.period_id,'root_id',budget.root_id),
  jsonb_build_object('to_status',budget.status,'revision',budget.revision,'reason',reason),
  jsonb_build_array(jsonb_build_object('topic','finance.budgets.'||act,'payload',result)),
  '[]',req,req);
end$$;

create function api.budget_options(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from (
  select id,root_id,revision,period_id,budget_year,branch_id budget_branch_id,
   currency_code,status,version,lines,reason,created_by,submitted_by,decided_by,
   created_at,decided_at
  from finance.budget_versions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and (branch_id is null or branch_id=p_branch_id)
   and (p_after is null or id>p_after) order by id limit 51)q;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'items',rows,'next_cursor',cursor);
end$$;

create table finance.budget_variance_reports (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 requested_branch_id uuid not null,budget_id uuid not null,as_of date not null,
 generated_at timestamptz not null,summary jsonb not null,evidence jsonb not null,
 created_by uuid not null references auth.users(id),unique(tenant_id,id),
 foreign key(tenant_id,budget_id) references finance.budget_versions(tenant_id,id),
 check(jsonb_typeof(summary)='object' and jsonb_typeof(evidence)='object'
  and octet_length(evidence::text)<=16777216)
);
create index budget_variance_scope on finance.budget_variance_reports(tenant_id,legal_entity_id,id);
create index budget_variance_budget on finance.budget_variance_reports(tenant_id,budget_id,id);
create index budget_variance_actor on finance.budget_variance_reports(created_by);
alter table finance.budget_variance_reports enable row level security;
alter table finance.budget_variance_reports force row level security;
revoke all on finance.budget_variance_reports from public,anon,authenticated;
create trigger immutable before update or delete on finance.budget_variance_reports
 for each row execute function workflow.reject_history_mutation();

create function finance.build_budget_variance(t uuid,e uuid,b uuid,budget_id uuid,d date,report_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare budget finance.budget_versions%rowtype;period finance.fiscal_periods%rowtype;
 start_date date;end_date date;base_currency text;x jsonb;a finance.accounts%rowtype;
 actual numeric;planned numeric;total_budget numeric:=0;total_actual numeric:=0;
 rows jsonb:='[]';journals jsonb:='[]';source_rows jsonb;source_count integer;
 summary jsonb;result jsonb;begin
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 select * into budget from finance.budget_versions where tenant_id=t and legal_entity_id=e
  and id=budget_id and status='approved' and (branch_id is null or branch_id=b);
 if not found then raise exception using errcode='42501',message='APPROVED_BUDGET_REQUIRED';end if;
 if budget.period_id is not null then
  select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
   and id=budget.period_id;
  start_date:=period.start_date;end_date:=period.end_date;
 else start_date:=make_date(budget.budget_year,1,1);
  end_date:=make_date(budget.budget_year,12,31);end if;
 if d is null or d<start_date or d>end_date or d>(clock_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='BUDGET_VARIANCE_DATE_INVALID';end if;
 select currency_code into base_currency from core.legal_entities
  where tenant_id=t and id=e;
 for x in select value from jsonb_array_elements(budget.lines) loop
  select * into a from finance.accounts where tenant_id=t and legal_entity_id=e
   and id=(x->>'account_id')::uuid;
  select coalesce(sum(case when a.normal_balance='debit' then
    case when budget.currency_code=base_currency then l.base_debit-l.base_credit
     else l.transaction_debit-l.transaction_credit end
   else case when budget.currency_code=base_currency then l.base_credit-l.base_debit
     else l.transaction_credit-l.transaction_debit end end),0),
   coalesce(jsonb_agg(jsonb_build_object('id',l.id,'budget_line_id',x->>'id',
    'journal_entry_id',j.id,'posting_date',j.posting_date,'document_number',j.document_number,
    'account_id',a.id,'branch_id',j.branch_id,'currency_code',j.currency_code,
    'base_debit',l.base_debit::text,'base_credit',l.base_credit::text,
    'transaction_debit',l.transaction_debit::text,
    'transaction_credit',l.transaction_credit::text,'source_type',j.source_type,
    'source_id',j.source_id) order by j.posting_date,j.id,l.id),'[]')
   into actual,source_rows
  from finance.journal_lines l join finance.journal_entries j
   on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where l.tenant_id=t and l.legal_entity_id=e and l.account_id=a.id
   and j.status='posted' and j.posting_date between start_date and d
   and (budget.branch_id is null or j.branch_id=budget.branch_id)
   and (budget.currency_code=base_currency or j.currency_code=budget.currency_code);
  planned:=(x->>'amount')::numeric;total_budget:=total_budget+planned;
  total_actual:=total_actual+actual;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',x->>'id','account_id',a.id,
   'code',a.code,'name',a.name,'normal_balance',a.normal_balance,
   'budget_amount',planned::text,'actual_amount',actual::text,
   'variance',(actual-planned)::text,
   'variance_percent',case when planned=0 then null else round((actual-planned)*100/planned,6)::text end,
   'source_count',jsonb_array_length(source_rows)));
  journals:=journals||source_rows;
  if jsonb_array_length(journals)>10000 then
   raise exception using errcode='54000',message='BUDGET_VARIANCE_SOURCE_LIMIT';end if;
 end loop;
 source_count:=jsonb_array_length(journals);
 summary:=jsonb_build_object('id',report_id,'tenant_id',t,'legal_entity_id',e,
  'branch_id',b,'budget_id',budget_id,'budget_root_id',budget.root_id,
  'budget_revision',budget.revision,'period_id',budget.period_id,
  'budget_year',budget.budget_year,'budget_branch_id',budget.branch_id,
  'as_of',d,'period_start',start_date,'period_end',end_date,
  'currency_code',budget.currency_code,'base_currency_code',base_currency,
  'currency_basis',case when budget.currency_code=base_currency then 'base_all_posted'
   else 'matching_transaction_only' end,'generated_at',now(),
  'status','generated','version',1,'line_count',jsonb_array_length(rows),
  'journal_count',source_count,'budget_total',total_budget::text,
  'actual_total',total_actual::text,'variance_total',(total_actual-total_budget)::text,
  'variance_percent',case when total_budget=0 then null
   else round((total_actual-total_budget)*100/total_budget,6)::text end);
 result:=jsonb_build_object('summary',summary,'lines',rows,'journals',journals);
 if octet_length(result::text)>16777216 then
  raise exception using errcode='54000',message='BUDGET_VARIANCE_EVIDENCE_LIMIT';end if;
 return result;
end$$;

create function api.generate_budget_variance(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare id uuid:=(p_payload->>'id')::uuid;h text;r jsonb;data jsonb;
 summary jsonb;req uuid:=gen_random_uuid();begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if id is null or p_client_timestamp is null then
  raise exception using errcode='22023',message='BUDGET_VARIANCE_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.budgets.variance.generate',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.budgets.variance.generate',p_command_id,p_idempotency_key,h);
 if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 data:=finance.build_budget_variance(p_tenant_id,p_legal_entity_id,p_branch_id,
  (p_payload->>'budget_id')::uuid,(p_payload->>'as_of')::date,id);
 summary:=data->'summary';
 insert into finance.budget_variance_reports(id,tenant_id,legal_entity_id,requested_branch_id,
  budget_id,as_of,generated_at,summary,evidence,created_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'budget_id')::uuid,
  (p_payload->>'as_of')::date,(summary->>'generated_at')::timestamptz,summary,data,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'finance.budgets.variance.generate',p_command_id,
  'budget_variance_report',id,p_idempotency_key,h,null,summary,p_legal_entity_id,p_branch_id,
  jsonb_build_object('budget_id',p_payload->>'budget_id','as_of',p_payload->>'as_of'),
  jsonb_build_object('to_status','generated'),
  jsonb_build_array(jsonb_build_object('topic','finance.budgets.variance.generated','payload',summary)),
  '[]',req,req);
end$$;

create function api.budget_variance_reports(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(summary order by id),'[]') into rows from (
  select id,summary from finance.budget_variance_reports where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and requested_branch_id=p_branch_id
   and (p_after is null or id>p_after)
  order by id limit 51)q;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'items',rows,'next_cursor',cursor);
end$$;

create function api.budget_variance_page(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_report_id uuid,p_section text,p_offset integer default 0,
 p_budget_line_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare report finance.budget_variance_reports%rowtype;rows jsonb;n integer;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_section not in('lines','journals') or p_section is null or p_offset is null
  or p_offset<0 or p_offset>10000 then
  raise exception using errcode='22023',message='BUDGET_VARIANCE_PAGE_INVALID';end if;
 select * into report from finance.budget_variance_reports where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and requested_branch_id=p_branch_id
  and id=p_report_id;
 if not found then raise exception using errcode='42501',message='BUDGET_REPORT_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(value order by ord),'[]') into rows from (
  select value,ord from jsonb_array_elements(report.evidence->p_section) with ordinality x(value,ord)
  where p_budget_line_id is null or
   (p_section='lines' and value->>'id'=p_budget_line_id::text) or
   (p_section='journals' and value->>'budget_line_id'=p_budget_line_id::text)
  order by ord offset p_offset limit 51)q;
 n:=jsonb_array_length(rows);if n>50 then rows:=rows-50;end if;
 return jsonb_build_object('summary',report.summary,'section',p_section,
  'budget_line_id',p_budget_line_id,'items',rows,
  'next_offset',case when n>50 then p_offset+50 end);
end$$;

revoke all on function finance.guard_budget_mutation(),finance.validate_budget_lines(uuid,uuid,jsonb),
 finance.build_budget_variance(uuid,uuid,uuid,uuid,date,uuid),
 api.budget_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.budget_options(uuid,uuid,uuid,uuid),
 api.generate_budget_variance(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.budget_variance_reports(uuid,uuid,uuid,uuid),
 api.budget_variance_page(uuid,uuid,uuid,uuid,text,integer,uuid)
 from public,anon,authenticated;
grant execute on function api.budget_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.budget_options(uuid,uuid,uuid,uuid),
 api.generate_budget_variance(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.budget_variance_reports(uuid,uuid,uuid,uuid),
 api.budget_variance_page(uuid,uuid,uuid,uuid,text,integer,uuid)
 to authenticated;
notify pgrst,'reload schema';
