-- UNAPPLIED AC-320 financial-statement candidate. Verify only inside ROLLBACK.
-- This first slice freezes trial balance, P&L and balance-sheet evidence.
create table finance.financial_reports (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 requested_branch_id uuid not null,kind text not null
  check(kind in('trial_balance','profit_loss','balance_sheet')),
 period_id uuid not null,comparative_period_id uuid,as_of date not null,
 generated_at timestamptz not null,summary jsonb not null,evidence jsonb not null,
 created_by uuid not null references auth.users(id),unique(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,requested_branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,period_id) references finance.fiscal_periods(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,comparative_period_id) references finance.fiscal_periods(tenant_id,legal_entity_id,id),
 check(jsonb_typeof(summary)='object' and jsonb_typeof(evidence)='object'
  and octet_length(evidence::text)<=16777216)
);
create index financial_reports_scope on finance.financial_reports(tenant_id,legal_entity_id,id);
create index financial_reports_period on finance.financial_reports(tenant_id,period_id,id);
create index financial_reports_actor on finance.financial_reports(created_by);
alter table finance.financial_reports enable row level security;
alter table finance.financial_reports force row level security;
revoke all on finance.financial_reports from public,anon,authenticated;
create trigger immutable before update or delete on finance.financial_reports
 for each row execute function workflow.reject_history_mutation();

create function finance.build_financial_statement(t uuid,e uuid,b uuid,p jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare k text:=p->>'kind';d date:=(p->>'as_of')::date;
 period finance.fiscal_periods%rowtype;comparison finance.fiscal_periods%rowtype;
 compare_end date;account_rows jsonb;journal_rows jsonb;summary jsonb;result jsonb;
 current_debit numeric;current_credit numeric;closing_debit numeric;closing_credit numeric;
 revenue numeric;expense numeric;assets numeric;liabilities numeric;equity numeric;earnings numeric;
 comp_revenue numeric;comp_expense numeric;comp_assets numeric;comp_liabilities numeric;comp_equity numeric;comp_earnings numeric;
begin
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 if k not in('trial_balance','profit_loss','balance_sheet') or k is null or d is null
  or d>(clock_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='FINANCIAL_REPORT_INPUT_INVALID';end if;
 select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
  and id=(p->>'period_id')::uuid and status='active';
 if not found or d not between period.start_date and period.end_date then
  raise exception using errcode='22023',message='FINANCIAL_REPORT_PERIOD_INVALID';end if;
 if p->>'comparative_period_id' is not null then
  select * into comparison from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
   and id=(p->>'comparative_period_id')::uuid and status='active';
  if not found or comparison.id=period.id or comparison.end_date>=period.start_date then
   raise exception using errcode='22023',message='FINANCIAL_REPORT_COMPARISON_INVALID';end if;
  compare_end:=comparison.end_date;
 end if;
 with source_lines as (
  select l.account_id,j.posting_date,l.base_debit,l.base_credit from finance.journal_lines l
  join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where l.tenant_id=t and l.legal_entity_id=e and j.status='posted'
   and j.posting_date<=greatest(d,coalesce(compare_end,d))
 ), balances as (
  select a.id,a.code,a.name,a.account_type,a.normal_balance,a.parent_id,
   coalesce(sum(s.base_debit-s.base_credit) filter(where s.posting_date<period.start_date),0) opening_signed,
   coalesce(sum(s.base_debit) filter(where s.posting_date between period.start_date and d),0) period_debit,
   coalesce(sum(s.base_credit) filter(where s.posting_date between period.start_date and d),0) period_credit,
   coalesce(sum(s.base_debit-s.base_credit) filter(where s.posting_date<=d),0) closing_signed,
   coalesce(sum(s.base_debit-s.base_credit) filter(where compare_end is not null and s.posting_date<=compare_end),0) compare_closing,
   coalesce(sum(s.base_debit-s.base_credit) filter(where compare_end is not null
    and s.posting_date between comparison.start_date and compare_end),0) compare_movement
  from finance.accounts a left join source_lines s on s.account_id=a.id
  where a.tenant_id=t and a.legal_entity_id=e and a.is_posting
  group by a.id,a.code,a.name,a.account_type,a.normal_balance,a.parent_id
  order by a.code,a.id limit 5001
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'account_id',id,'code',code,'name',name,
  'account_type',account_type,'normal_balance',normal_balance,'parent_id',parent_id,
  'opening_balance',opening_signed::text,'period_debit',period_debit::text,
  'period_credit',period_credit::text,'closing_balance',closing_signed::text,
  'comparative_closing_balance',case when compare_end is null then null else compare_closing::text end,
  'amount',(case k when 'trial_balance' then closing_signed
   when 'profit_loss' then case account_type when 'revenue' then period_credit-period_debit
    when 'expense' then period_debit-period_credit else 0 end
   else case account_type when 'asset' then closing_signed
    when 'liability' then -closing_signed when 'equity' then -closing_signed else 0 end end)::text,
  'comparative_amount',(case when compare_end is null then null
   when k='trial_balance' then compare_closing
   when k='profit_loss' then case account_type when 'revenue' then -compare_movement
    when 'expense' then compare_movement else 0 end
   else case account_type when 'asset' then compare_closing
    when 'liability' then -compare_closing when 'equity' then -compare_closing else 0 end end)::text)
  order by code,id),'[]'::jsonb) into account_rows from balances;
 if jsonb_array_length(account_rows)>5000 then
  raise exception using errcode='54000',message='FINANCIAL_ACCOUNT_LIMIT';end if;

 select coalesce(jsonb_agg(to_jsonb(q) order by posting_date,id),'[]'::jsonb) into journal_rows from (
  select l.id,l.account_id,j.id journal_entry_id,j.document_number,j.source_type,j.source_id,
   j.command_id,j.posting_date,j.fiscal_period_id,l.line_number,l.source_line_id,l.party_id,
   l.branch_id,l.currency_code,l.transaction_debit::text transaction_debit,
   l.transaction_credit::text transaction_credit,l.base_debit::text base_debit,
   l.base_credit::text base_credit
  from finance.journal_lines l join finance.journal_entries j
   on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where l.tenant_id=t and l.legal_entity_id=e and j.status='posted'
   and j.posting_date<=greatest(d,coalesce(compare_end,d))
  order by j.posting_date,l.id limit 10001)q;
 if jsonb_array_length(journal_rows)>10000 then
  raise exception using errcode='54000',message='FINANCIAL_JOURNAL_LIMIT';end if;
 select coalesce(sum((x->>'period_debit')::numeric),0),
  coalesce(sum((x->>'period_credit')::numeric),0),
  coalesce(sum(greatest((x->>'closing_balance')::numeric,0)),0),
  coalesce(sum(greatest(-(x->>'closing_balance')::numeric,0)),0),
  coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='revenue'),0),
  coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='expense'),0),
  coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='asset'),0),
  coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='liability'),0),
  coalesce(sum((x->>'amount')::numeric) filter(where x->>'account_type'='equity'),0)
 into current_debit,current_credit,closing_debit,closing_credit,revenue,expense,
  assets,liabilities,equity from jsonb_array_elements(account_rows)x;
 if current_debit<>current_credit or closing_debit<>closing_credit then
  raise exception using errcode='23514',message='FINANCIAL_LEDGER_UNBALANCED';end if;
 if k='balance_sheet' then
  select coalesce(sum(-(x->>'closing_balance')::numeric) filter(where x->>'account_type'='revenue'),0)
   -coalesce(sum((x->>'closing_balance')::numeric) filter(where x->>'account_type'='expense'),0)
   into earnings from jsonb_array_elements(account_rows)x;
  select coalesce(sum((x->>'comparative_amount')::numeric) filter(where x->>'account_type'='asset'),0),
   coalesce(sum((x->>'comparative_amount')::numeric) filter(where x->>'account_type'='liability'),0),
   coalesce(sum((x->>'comparative_amount')::numeric) filter(where x->>'account_type'='equity'),0),
   coalesce(sum(-(x->>'comparative_closing_balance')::numeric) filter(where x->>'account_type'='revenue'),0)
    -coalesce(sum((x->>'comparative_closing_balance')::numeric) filter(where x->>'account_type'='expense'),0)
  into comp_assets,comp_liabilities,comp_equity,comp_earnings
  from jsonb_array_elements(account_rows)x;
 elsif k='profit_loss' then
  select coalesce(sum((x->>'comparative_amount')::numeric) filter(where x->>'account_type'='revenue'),0),
   coalesce(sum((x->>'comparative_amount')::numeric) filter(where x->>'account_type'='expense'),0)
  into comp_revenue,comp_expense from jsonb_array_elements(account_rows)x;
 end if;
 summary:=jsonb_build_object('id',p->>'id','version',1,'status','generated','kind',k,
  'tenant_id',t,'legal_entity_id',e,'branch_id',b,'period_id',period.id,
  'period_start',period.start_date,'period_end',period.end_date,'as_of',d,
  'comparative_period_id',comparison.id,'comparative_start',comparison.start_date,
  'comparative_end',compare_end,'base_currency_code',
  (select currency_code from core.legal_entities where tenant_id=t and id=e),
  'generated_at',statement_timestamp(),'account_count',jsonb_array_length(account_rows),
  'journal_count',jsonb_array_length(journal_rows),
  'period_debit',current_debit::text,'period_credit',current_credit::text,
  'closing_debit',closing_debit::text,'closing_credit',closing_credit::text,
  'revenue',case when k='profit_loss' then revenue::text end,
  'expenses',case when k='profit_loss' then expense::text end,
  'net_profit',case when k='profit_loss' then (revenue-expense)::text end,
  'assets',case when k='balance_sheet' then assets::text end,
  'liabilities',case when k='balance_sheet' then liabilities::text end,
  'equity',case when k='balance_sheet' then equity::text end,
  'current_earnings',case when k='balance_sheet' then earnings::text end,
  'difference',case when k='balance_sheet' then (assets-liabilities-equity-earnings)::text
   else (closing_debit-closing_credit)::text end,
  'comparative',case when compare_end is null then null
   when k='profit_loss' then jsonb_build_object('revenue',comp_revenue::text,
    'expenses',comp_expense::text,'net_profit',(comp_revenue-comp_expense)::text)
   when k='balance_sheet' then jsonb_build_object('assets',comp_assets::text,
    'liabilities',comp_liabilities::text,'equity',comp_equity::text,
    'current_earnings',comp_earnings::text,
    'difference',(comp_assets-comp_liabilities-comp_equity-comp_earnings)::text)
   else null end);
 if k='balance_sheet' and assets<>liabilities+equity+earnings then
  raise exception using errcode='23514',message='FINANCIAL_BALANCE_SHEET_UNBALANCED';end if;
 result:=jsonb_build_object('summary',summary,'accounts',account_rows,'journals',journal_rows);
 if octet_length(result::text)>16777216 then
  raise exception using errcode='54000',message='FINANCIAL_REPORT_EVIDENCE_LIMIT';end if;
 return result;
end$$;

create function api.generate_financial_statement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare id uuid:=(p_payload->>'id')::uuid;h text;r jsonb;data jsonb;summary jsonb;req uuid:=gen_random_uuid();begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if id is null or p_client_timestamp is null then
  raise exception using errcode='22023',message='FINANCIAL_REPORT_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.statements.generate',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.statements.generate',p_command_id,p_idempotency_key,h);
 if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 data:=finance.build_financial_statement(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 summary:=data->'summary';
 insert into finance.financial_reports values(id,p_tenant_id,p_legal_entity_id,p_branch_id,
  summary->>'kind',(summary->>'period_id')::uuid,(summary->>'comparative_period_id')::uuid,
  (summary->>'as_of')::date,(summary->>'generated_at')::timestamptz,summary,data,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'finance.statements.generate',p_command_id,
  'financial_statement_report',id,p_idempotency_key,h,null,summary,p_legal_entity_id,p_branch_id,
  '{}',jsonb_build_object('to_status','generated'),
  jsonb_build_array(jsonb_build_object('topic','finance.statements.generated','payload',summary)),
  '[]',req,req);
end$$;

create function api.financial_statement_reports(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(summary order by id),'[]') into rows from (
  select id,summary from finance.financial_reports where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and (p_after is null or id>p_after)
  order by id limit 51)q;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'items',rows,'next_cursor',cursor);
end$$;

create function api.financial_statement_page(p_tenant_id uuid,p_legal_entity_id uuid,
 p_branch_id uuid,p_report_id uuid,p_section text,p_offset integer default 0,
 p_account_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare report finance.financial_reports%rowtype;rows jsonb;n integer;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_section not in('accounts','journals') or p_section is null or p_offset is null
  or p_offset<0 or p_offset>10000 then
  raise exception using errcode='22023',message='FINANCIAL_REPORT_PAGE_INVALID';end if;
 select * into report from finance.financial_reports where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=p_report_id;
 if not found then raise exception using errcode='42501',message='FINANCIAL_REPORT_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(value order by ord),'[]') into rows from (
  select value,ord from jsonb_array_elements(report.evidence->p_section) with ordinality x(value,ord)
  where p_account_id is null or value->>'account_id'=p_account_id::text
  order by ord offset p_offset limit 51)q;
 n:=jsonb_array_length(rows);if n>50 then rows:=rows-50;end if;
 return jsonb_build_object('summary',report.summary,'section',p_section,'account_id',p_account_id,
  'items',rows,'next_offset',case when n>50 then p_offset+50 end);
end$$;

revoke all on function finance.build_financial_statement(uuid,uuid,uuid,jsonb),
 api.generate_financial_statement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.financial_statement_reports(uuid,uuid,uuid,uuid),
 api.financial_statement_page(uuid,uuid,uuid,uuid,text,integer,uuid)
 from public,anon,authenticated;
grant execute on function api.generate_financial_statement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.financial_statement_reports(uuid,uuid,uuid,uuid),
 api.financial_statement_page(uuid,uuid,uuid,uuid,text,integer,uuid) to authenticated;
notify pgrst,'reload schema';
