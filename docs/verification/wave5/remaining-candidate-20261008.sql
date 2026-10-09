begin;
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

-- UNAPPLIED. Private saved evidence only; never arbitrary tables or client rows.
insert into core.permissions(code,module,description,privileged) values
 ('finance.reports.export','finance','Export scoped frozen financial and inventory evidence.',false) on conflict(code) do nothing;

create function finance.report_export_document(t uuid,e uuid,b uuid,resource text,i uuid,section text,filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare probe jsonb;data jsonb;rows jsonb;meta jsonb;allowed text[];k text;v jsonb;result jsonb;begin
 perform core.wave3_require_scope(t,'finance.reports.export',e,null);
 perform core.wave3_require_scope(t,'finance.reports.export',e,b);
 if i is null or jsonb_typeof(filters) is distinct from 'object' then raise exception using errcode='22023',message='REPORT_EXPORT_INPUT_INVALID';end if;
 allowed:=case resource when 'statement' then array['account_id'] when 'control' then array['evidence_key']
  when 'inventory' then array['evidence_key'] when 'tax' then array['account_id','evidence_key','source_line_id']
  when 'budget' then array['budget_line_id'] when 'close' then array['component_key'] else null end;
 if allowed is null then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
 for k,v in select * from jsonb_each(filters) loop
  if not k=any(allowed) or (v<>'null'::jsonb and (jsonb_typeof(v)<>'string' or length(v#>>'{}')>220)) then
   raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
 end loop;
 case resource
 when 'statement' then
  probe:=api.financial_statement_page(t,e,b,i,section,0,(filters->>'account_id')::uuid);
  select evidence into data from finance.financial_reports where tenant_id=t and legal_entity_id=e and id=i;
 when 'control' then
  probe:=api.control_reconciliation_report_page(t,e,b,i,section,0,filters->>'evidence_key');
  select evidence into data from finance.control_reports where tenant_id=t and legal_entity_id=e and branch_id=b and id=i;
 when 'inventory' then
  probe:=api.inventory_valuation_report_page(t,e,b,i,section,0,filters->>'evidence_key');
  select evidence into data from inventory.valuation_reports where tenant_id=t and legal_entity_id=e and branch_id=b and id=i;
 when 'tax' then
  if section='lines' then
   if filters->>'account_id' is not null or filters->>'evidence_key' is not null then raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
   probe:=api.tax_summary_page(t,e,b,i,0,(filters->>'source_line_id')::uuid);
  else
   if filters->>'source_line_id' is not null then raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
   probe:=api.tax_control_page(t,e,b,i,section,0,(filters->>'account_id')::uuid,filters->>'evidence_key');
  end if;
  select evidence into data from finance.tax_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=i;
 when 'budget' then
  probe:=api.budget_variance_page(t,e,b,i,section,0,(filters->>'budget_line_id')::uuid);
  select evidence into data from finance.budget_variance_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=i;
 when 'close' then
  probe:=api.close_control_review_page(t,e,b,i,section,0,filters->>'component_key');
  select evidence into data from finance.close_control_reviews where tenant_id=t and legal_entity_id=e and id=i;
 end case;
 if data is null or jsonb_typeof(data->section) is distinct from 'array' then raise exception using errcode='42501',message='REPORT_EXPORT_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(x order by ord),'[]') into rows from jsonb_array_elements(data->section) with ordinality q(x,ord)
 where (filters->>'account_id' is null or x->>'account_id'=filters->>'account_id')
  and (filters->>'evidence_key' is null or x->>'evidence_key'=filters->>'evidence_key')
  and (filters->>'source_line_id' is null or x->>'source_line_id'=filters->>'source_line_id')
  and (filters->>'component_key' is null or x->>'component_key'=filters->>'component_key')
  and (filters->>'budget_line_id' is null or (section='lines' and x->>'id'=filters->>'budget_line_id')
   or (section='journals' and x->>'budget_line_id'=filters->>'budget_line_id'));
 if jsonb_array_length(rows)>10000 then raise exception using errcode='54000',message='REPORT_EXPORT_ROW_LIMIT';end if;
 select coalesce(jsonb_object_agg(key,value),'{}') into meta from jsonb_each(data->'summary')
  where key in('id','version','tenant_id','legal_entity_id','branch_id','requested_branch_id','scope','entity_name','branch_name','kind','status',
   'currency_code','base_currency_code','as_of','generated_at','period_id','period_name','period_start','period_end','period_version','period_state',
   'comparative_period_id','budget_id','budget_version','budget_name','branch_filter_id','cost_centre_filter_id','project_filter_id','notice');
 result:=jsonb_build_object('version',1,'metadata',meta||jsonb_build_object('actor_id',auth.uid(),'working_branch_id',b,
  'source_type',resource,'source_id',i,'section',section,'filters',filters,'row_count',jsonb_array_length(rows)), 'rows',rows);
 if octet_length(result::text)>8388608 then raise exception using errcode='54000',message='REPORT_EXPORT_EVIDENCE_LIMIT';end if;
 return result;
end $$;
create function api.report_export_preview(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_source_type text,p_source_id uuid,p_section text,p_filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare data jsonb;begin
 data:=finance.report_export_document(p_tenant_id,p_legal_entity_id,p_branch_id,p_source_type,p_source_id,p_section,p_filters);
 return jsonb_build_object('canonical_text',data::text,'source_hash',encode(extensions.digest(data::text,'sha256'),'hex'));
end $$;
create function api.record_report_export(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p jsonb:=p_payload;data jsonb;h text;r jsonb;id uuid:=(p->>'id')::uuid;req uuid:=gen_random_uuid();
 source_hash text;columns jsonb;filters jsonb;result jsonb;expected_columns jsonb;begin
 -- Current source permission and export permission precede every replay.
 data:=finance.report_export_document(p_tenant_id,p_legal_entity_id,p_branch_id,p->>'source_type',(p->>'source_id')::uuid,p->>'section',p->'filters');
 source_hash:=encode(extensions.digest(data::text,'sha256'),'hex');
 select jsonb_build_array('record_type')||
  (select jsonb_agg('report.'||key order by key) from (select jsonb_object_keys(data->'metadata') key
   union select unnest(array['export_id','export_prepared_at','source_hash','file_format']))q)||
  coalesce((select jsonb_agg('data.'||key order by key) from (select distinct key
   from jsonb_array_elements(data->'rows')x cross join lateral jsonb_object_keys(x)key)q),'[]'::jsonb)
 into expected_columns;
 if id is null or p_client_timestamp is null or p->>'source_hash' is distinct from source_hash
  or p->>'file_format' not in('csv','xlsx') or p->>'file_format' is null
  or coalesce(p->>'file_name','')!~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{1,180}$'
  or right(p->>'file_name',length(p->>'file_format')+1)<>'.'||(p->>'file_format')
  or coalesce(p->>'file_sha256','')!~ '^[a-f0-9]{64}$' or (p->>'file_size')::bigint not between 1 and 10485760
  or p->>'file_size' is null or jsonb_typeof(p->'columns') is distinct from 'array'
  or jsonb_array_length(p->'columns') not between 1 and 256 or p->>'prepared_at' is null
  or p->'columns' is distinct from expected_columns then
  raise exception using errcode='22023',message='REPORT_EXPORT_METADATA_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(p->'columns')x where jsonb_typeof(x)<>'string' or length(x#>>'{}') not between 1 and 100)
  or (select count(distinct x) from jsonb_array_elements_text(p->'columns')x)<>jsonb_array_length(p->'columns') then
  raise exception using errcode='22023',message='REPORT_EXPORT_METADATA_INVALID';end if;
 perform (p->>'prepared_at')::timestamptz;
 h:=core.wave3_request_hash('finance.report.export',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.report.export',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 filters:=data->'metadata'||jsonb_build_object('source_hash',source_hash,'file_sha256',p->>'file_sha256','prepared_at',p->>'prepared_at',
  'artifact_state','generated_local_delivery_unconfirmed');columns:=p->'columns';
 insert into core.export_jobs(id,tenant_id,actor_id,resource,file_format,filters,columns_json,status,row_count,file_name,file_size,request_id)
  values(id,p_tenant_id,auth.uid(),'wave3.'||(p->>'source_type'),p->>'file_format',filters,columns,'completed',
   jsonb_array_length(data->'rows'),p->>'file_name',(p->>'file_size')::bigint,req);
 result:=jsonb_build_object('id',id,'version',1,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'actor_id',auth.uid(),'status','registered','source_type',p->>'source_type','source_id',p->>'source_id',
  'section',p->>'section','filters',p->'filters','source_hash',source_hash,'file_sha256',p->>'file_sha256',
  'file_format',p->>'file_format','file_name',p->>'file_name','file_size',(p->>'file_size')::bigint,'row_count',jsonb_array_length(data->'rows'));
 return core.wave3_finish_command(p_tenant_id,'finance.report.export',p_command_id,'report_export',id,p_idempotency_key,h,null,result,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','registered'),
  jsonb_build_array(jsonb_build_object('topic','finance.report.exported','payload',result)),'[]',req,req);
end $$;
revoke all on function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb),
 api.report_export_preview(uuid,uuid,uuid,text,uuid,text,jsonb),
 api.record_report_export(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.report_export_preview(uuid,uuid,uuid,text,uuid,text,jsonb),
 api.record_report_export(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
notify pgrst,'reload schema';

-- Additive UNAPPLIED candidate. Uses the installed immutable CRM history.
-- No source history, entitlements, role assignments or acceptance fixtures seeded.
create function api.wave5_pipeline_history(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_as_of timestamptz,p_recorded_through timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;n integer;result jsonb;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_as_of is null or p_recorded_through is null or not isfinite(p_as_of) or not isfinite(p_recorded_through)
  or p_as_of>p_recorded_through or p_recorded_through>statement_timestamp() then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if exists(select 1 from crm.opportunities o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or o.branch_id=p_branch_id) and o.created_at<=p_as_of
  and not exists(select 1 from crm.pipeline_history h where h.tenant_id=o.tenant_id and h.entity_type='opportunity'
   and h.entity_id=o.id and h.recorded_at<=p_as_of and h.recorded_at<=p_recorded_through)) then
  raise exception using errcode='55000',message='HISTORY_COHORT_INCOMPLETE';end if;
 -- Retain all revisions up to the cutoff: a last-known row alone cannot certify
 -- stage entry. Recheck each historical branch, including a later scope move.
 select coalesce(jsonb_agg(jsonb_build_object('id',h.entity_id,'revisionId',h.id,'version',h.version::text,
  'tenantId',h.tenant_id,'legalEntityId',h.legal_entity_id,'branchId',h.branch_id,
  'recordedAt',analytics.process_utc(h.recorded_at),'createdAt',analytics.process_utc((h.snapshot->>'created_at')::timestamptz),
  'stage',h.snapshot->>'stage','status',h.snapshot->>'status','ownerId',h.snapshot->>'owner_id',
  'amount',h.snapshot->>'expected_value','probability',h.snapshot->>'probability',
  'currency',h.snapshot->>'currency_code') order by h.entity_id,h.version),'[]'),count(*) into rows,n
 from (select h.* from crm.pipeline_history h where h.tenant_id=p_tenant_id and h.legal_entity_id=p_legal_entity_id
  and h.entity_type='opportunity' and h.recorded_at<=p_as_of and h.recorded_at<=p_recorded_through
  and exists(select 1 from crm.pipeline_history selected where selected.tenant_id=h.tenant_id
   and selected.entity_type=h.entity_type and selected.entity_id=h.entity_id and selected.recorded_at<=p_as_of
   and selected.recorded_at<=p_recorded_through and (p_branch_id is null or selected.branch_id=p_branch_id))
  order by h.entity_id,h.version limit 10001) h;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 if exists(select 1 from jsonb_array_elements(rows) r group by r->>'id'
  having min((r->>'version')::bigint)<>1 or count(*)<>max((r->>'version')::bigint)) then
  raise exception using errcode='55000',message='HISTORY_REVISION_GAP';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where
  not (core.has_permission(p_tenant_id,'crm.opportunities.view',p_legal_entity_id,(r->>'branchId')::uuid)
   or core.has_permission(p_tenant_id,'crm.opportunities.manage',p_legal_entity_id,(r->>'branchId')::uuid))) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 result:=jsonb_build_object('contractRevision',1,'sourceContract','crm.pipeline_history.v1',
  'scope',jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
  'asOf',analytics.process_utc(p_as_of),'recordedThrough',analytics.process_utc(p_recorded_through),
  'complete',true,'revisions',rows);
 if octet_length(result::text)>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return jsonb_build_object('canonicalText',result::text,'sourceHash',encode(extensions.digest(result::text,'sha256'),'hex'));
end $$;
revoke all on function api.wave5_pipeline_history(uuid,uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function api.wave5_pipeline_history(uuid,uuid,uuid,timestamptz,timestamptz) to authenticated;

-- Realized result is explicitly posted invoice gross less posted credit-return
-- gross, grouped in original transaction currency. It is not ledger revenue.
create function api.wave5_pipeline_realized(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_forecast_id uuid,p_as_of timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare f jsonb;rows jsonb;n integer;begin
 f:=api.get_pipeline_forecast(p_tenant_id,p_legal_entity_id,p_branch_id,p_forecast_id);
 perform core.wave3_require_scope(p_tenant_id,'finance.receivables.view',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'sales.returns.view',p_legal_entity_id,p_branch_id);
 if p_as_of is null or not isfinite(p_as_of) or p_as_of>statement_timestamp()
  or p_as_of<(f#>>'{evidence,asOf}')::timestamptz then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_as_of<(f#>>'{evidence,horizonEnd}')::date::timestamptz then
  raise exception using errcode='55000',message='REALIZED_HORIZON_OPEN';end if;
 if (f#>>'{evidence,asOf}')::timestamptz>=(f#>>'{evidence,horizonEnd}')::date::timestamptz then
  raise exception using errcode='55000',message='FORECAST_NOT_PROSPECTIVE';end if;
 with cohort as (select (x->>'id')::uuid id from jsonb_array_elements(f#>'{evidence,observations}') x),
 documents as (
  select i.id,(o.source_snapshot->>'opportunity_id')::uuid opportunity_id,i.branch_id,i.currency_code,i.grand_total amount,i.version,'invoice' kind,i.posted_at
  from sales.sales_invoices i join sales.sales_orders o on o.tenant_id=i.tenant_id and o.id=i.sales_order_id
  join cohort c on c.id=(o.source_snapshot->>'opportunity_id')::uuid
  where i.tenant_id=p_tenant_id and i.legal_entity_id=p_legal_entity_id and (p_branch_id is null or i.branch_id=p_branch_id)
   and i.status='posted' and i.posted_at<=p_as_of and i.document_date>=(f#>>'{evidence,horizonStart}')::date
   and i.document_date<(f#>>'{evidence,horizonEnd}')::date
  union all
  select r.id,(o.source_snapshot->>'opportunity_id')::uuid,r.branch_id,r.currency_code,-r.grand_total,r.version,'credit_return',r.posted_at
  from sales.sales_returns r join sales.sales_orders o on o.tenant_id=r.tenant_id and o.id=r.sales_order_id
  join cohort c on c.id=(o.source_snapshot->>'opportunity_id')::uuid
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and (p_branch_id is null or r.branch_id=p_branch_id)
   and r.status='posted' and r.posted_at<=p_as_of and r.document_date>=(f#>>'{evidence,horizonStart}')::date
   and r.document_date<(f#>>'{evidence,horizonEnd}')::date
 ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'opportunityId',opportunity_id,'branchId',branch_id,
  'currency',currency_code,'amount',amount::text,'version',version::text,'kind',kind,'postedAt',analytics.process_utc(posted_at)) order by id),'[]'),count(*)
 into rows,n from (select * from documents order by id limit 10001) d;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 -- A line-linked return without an order header can affect the frozen cohort.
 -- Until an exact header/line apportionment exists, do not report a partial zero.
 if exists(select 1 from sales.sales_returns r join sales.sales_return_lines l on l.tenant_id=r.tenant_id and l.document_id=r.id
  join sales.sales_invoice_lines il on il.tenant_id=l.tenant_id and il.id=l.sales_invoice_line_id
  join sales.sales_invoices i on i.tenant_id=il.tenant_id and i.id=il.document_id
  join sales.sales_orders o on o.tenant_id=i.tenant_id and o.id=i.sales_order_id
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and (p_branch_id is null or r.branch_id=p_branch_id)
   and r.sales_order_id is null and r.status='posted' and r.posted_at<=p_as_of
   and r.document_date>=(f#>>'{evidence,horizonStart}')::date and r.document_date<(f#>>'{evidence,horizonEnd}')::date
   and exists(select 1 from jsonb_array_elements(f#>'{evidence,observations}') x where x->>'id'=o.source_snapshot->>'opportunity_id')) then
  raise exception using errcode='55000',message='REALIZED_MAPPING_INCOMPLETE';end if;
 if exists(select 1 from jsonb_array_elements(rows) r where
  not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid)
  or not core.has_permission(p_tenant_id,'sales.returns.view',p_legal_entity_id,(r->>'branchId')::uuid)) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 return jsonb_build_object('contractRevision',1,'forecastId',p_forecast_id,'sourceHash',f->>'sourceHash',
  'definition','posted_invoice_less_order_linked_credit_gross.v1','asOf',analytics.process_utc(p_as_of),'complete',true,'documents',rows);
end $$;
revoke all on function api.wave5_pipeline_realized(uuid,uuid,uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function api.wave5_pipeline_realized(uuid,uuid,uuid,uuid,timestamptz) to authenticated;

-- UNAPPLIED synthetic-development candidate. No hosts, keys, credentials,
-- subscriptions, worker deployment or entitlement activation are provisioned.
insert into core.permissions(code,module,description,privileged) values
 ('integrations.manage','integrations','Manage scoped reviewed integrations',true)
 on conflict(code) do nothing;
create table intelligence_control.integration_hosts(hostname text primary key,
 check(hostname ~ '^[a-z0-9][a-z0-9.-]{1,250}[a-z0-9]$'));
create table intelligence_control.integration_subscriptions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,
 created_by uuid not null references auth.users(id),url text not null,hostname text not null references intelligence_control.integration_hosts,
 version bigint not null default 1,key_version integer not null default 1,key_ref text not null,
 enabled boolean not null default true,created_at timestamptz not null default statement_timestamp(),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(version>0 and key_version>0 and key_ref ~ '^[a-zA-Z0-9_/-]{1,180}$'),
 check(url ~ '^https://[^/@:#?]+(:443)?(/[^#]*)?$' and length(url)<=2048));
create table intelligence_control.integration_changes(
 id uuid primary key,tenant_id uuid not null,subscription_id uuid not null,version bigint not null,
 actor_id uuid not null references auth.users(id),action text not null,evidence jsonb not null,
 recorded_at timestamptz not null default statement_timestamp(),unique(tenant_id,subscription_id,version),
 foreign key(tenant_id,subscription_id) references intelligence_control.integration_subscriptions(tenant_id,id));
create table intelligence_control.delivery_heads(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,subscription_id uuid not null,event_id uuid not null references core.outbox_events(id),
 invocation_id uuid not null default gen_random_uuid(),usage_event_id uuid not null default gen_random_uuid(),
 attempt integer not null default 0 check(attempt between 0 and 8),state text not null default 'pending'
 check(state in('pending','leased','retry','unknown','acknowledged','dead_letter')),
 available_at timestamptz not null default statement_timestamp(),lease_id uuid,lease_until timestamptz,
 period_start timestamptz,period_end timestamptz,generation integer not null default 0 check(generation>=0),replay_of uuid,
 unique(tenant_id,subscription_id,event_id,generation),unique(tenant_id,id),
 foreign key(tenant_id,replay_of) references intelligence_control.delivery_heads(tenant_id,id),
 foreign key(tenant_id,subscription_id) references intelligence_control.integration_subscriptions(tenant_id,id));
create table intelligence_control.delivery_attempts(
 tenant_id uuid not null,delivery_id uuid not null,attempt integer not null,lease_id uuid not null unique,
 key_version integer not null,subscription_version bigint not null,claimed_at timestamptz not null default statement_timestamp(),
 primary key(tenant_id,delivery_id,attempt),foreign key(tenant_id,delivery_id) references intelligence_control.delivery_heads(tenant_id,id));
create table intelligence_control.delivery_outcomes(
 tenant_id uuid not null,delivery_id uuid not null,attempt integer not null,state text not null,
 http_status integer,recorded_at timestamptz not null default statement_timestamp(),
 primary key(tenant_id,delivery_id,attempt),foreign key(tenant_id,delivery_id,attempt)
 references intelligence_control.delivery_attempts(tenant_id,delivery_id,attempt),
 check(state in('acknowledged','retry','unknown','dead_letter')),
 check(http_status is null or http_status between 100 and 599));
create table intelligence_control.delivery_reviews(
 id uuid primary key,tenant_id uuid not null,delivery_id uuid not null,actor_id uuid not null references auth.users(id),
 action text not null check(action in('replay','acknowledged','not_sent')),reason text not null check(length(trim(reason)) between 8 and 500),
 recorded_at timestamptz not null default statement_timestamp(),
 foreign key(tenant_id,delivery_id) references intelligence_control.delivery_heads(tenant_id,id));
do $$declare rel text;begin
 foreach rel in array array['integration_hosts','integration_subscriptions','integration_changes','delivery_heads','delivery_attempts','delivery_outcomes','delivery_reviews'] loop
  execute format('alter table intelligence_control.%I enable row level security',rel);
  execute format('alter table intelligence_control.%I force row level security',rel);
  execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
  if rel not in('integration_subscriptions','delivery_heads') then
   execute format('create trigger immutable before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);
  end if;
 end loop;
end $$;
create index delivery_ready_idx on intelligence_control.delivery_heads(state,available_at,id);
create index delivery_subscription_idx on intelligence_control.delivery_heads(tenant_id,subscription_id,id);
create index integration_scope_idx on intelligence_control.integration_subscriptions(tenant_id,legal_entity_id,branch_id,id);

create function api.wave5_integration_manage(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_action text,p_id uuid,p_expected_version bigint,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s intelligence_control.integration_subscriptions%rowtype;prior intelligence_control.integration_changes%rowtype;host text;h text;receipt jsonb;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 if p_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,58));
 if p_expected_version is null or p_expected_version<0 or p_action is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 h:=encode(extensions.digest(jsonb_build_object('scope',jsonb_build_array(p_tenant_id,p_legal_entity_id,p_branch_id),'action',p_action,'payload',p_payload)::text,'sha256'),'hex');
 select * into prior from intelligence_control.integration_changes where tenant_id=p_tenant_id and subscription_id=p_id and version=p_expected_version+1;
 if found then
  if prior.actor_id<>auth.uid() or prior.action<>p_action or prior.evidence->>'requestHash' is distinct from h then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  return prior.evidence->'receipt';end if;
 if p_action='register' then
  if p_expected_version<>0 or p_expected_version is null or (p_payload-array['url','keyRef'])<>'{}'
   or not(p_payload ?& array['url','keyRef']) or jsonb_typeof(p_payload->'url')<>'string' or jsonb_typeof(p_payload->'keyRef')<>'string' then
   raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
  host:=substring(p_payload->>'url' from '^https://([^/:?#]+)');
  if host is null or not exists(select 1 from intelligence_control.integration_hosts where hostname=host) then
   raise exception using errcode='42501',message='UNREVIEWED_DESTINATION';end if;
  insert into intelligence_control.integration_subscriptions(id,tenant_id,legal_entity_id,branch_id,created_by,url,hostname,key_ref)
   values(p_id,p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),p_payload->>'url',host,p_payload->>'keyRef') returning * into s;
 else
  select * into s from intelligence_control.integration_subscriptions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id is not distinct from p_branch_id and id=p_id for update;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
  if s.version is distinct from p_expected_version then raise exception using errcode='40001',message='CONFLICT';end if;
  if p_action='rotate' and (p_payload-'keyRef')='{}' and jsonb_typeof(p_payload->'keyRef')='string' then
   update intelligence_control.integration_subscriptions set key_ref=p_payload->>'keyRef',key_version=key_version+1,version=version+1 where id=p_id returning * into s;
  elsif p_action='revoke' and p_payload='{}' then
   update intelligence_control.integration_subscriptions set enabled=false,version=version+1 where id=p_id returning * into s;
  else raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 end if;
 receipt:=jsonb_build_object('id',s.id,'version',s.version::text,'keyVersion',s.key_version,'enabled',s.enabled);
 insert into intelligence_control.integration_changes values(gen_random_uuid(),p_tenant_id,p_id,s.version,auth.uid(),p_action,
  jsonb_build_object('requestHash',h,'receipt',receipt),statement_timestamp());
 return receipt;
end $$;

create function intelligence_control.delivery_authorize(p_delivery_id uuid,p_lease_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d intelligence_control.delivery_heads%rowtype;s intelligence_control.integration_subscriptions%rowtype;
 f analytics.pipeline_forecasts%rowtype;a intelligence_control.delivery_attempts%rowtype;saved_claims text;begin
 select * into d from intelligence_control.delivery_heads where id=p_delivery_id and lease_id=p_lease_id and state='leased' and lease_until>statement_timestamp();
 if not found then raise exception using errcode='42501',message='LEASE_UNAVAILABLE';end if;
 select * into s from intelligence_control.integration_subscriptions where tenant_id=d.tenant_id and id=d.subscription_id and enabled;
 select * into a from intelligence_control.delivery_attempts where tenant_id=d.tenant_id and delivery_id=d.id and attempt=d.attempt;
 if s.id is null or a.lease_id is null or s.version<>a.subscription_version or s.key_version<>a.key_version then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform intelligence_control.quota_limit(d.tenant_id,'webhook.deliveries');
 select f0.* into f from core.outbox_events o join analytics.pipeline_forecasts f0 on f0.tenant_id=o.tenant_id and f0.id=o.aggregate_id
 where o.id=d.event_id and o.tenant_id=s.tenant_id and o.topic='analytics.freeze_pipeline' and o.aggregate_type='pipeline_forecast'
  and f0.legal_entity_id=s.legal_entity_id and f0.branch_id is not distinct from s.branch_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 -- Explicit subscription delegation uses AAL1. It never fabricates human MFA;
 -- the installed scope, role, entitlement and every captured-branch check run.
 saved_claims:=current_setting('request.jwt.claims',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',s.created_by,'role','authenticated','aal','aal1')::text,true);
 perform core.wave3_require_scope(s.tenant_id,'integrations.manage',s.legal_entity_id,s.branch_id);
 perform api.get_pipeline_forecast(s.tenant_id,s.legal_entity_id,s.branch_id,f.id);
 perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
 return jsonb_build_object('event',jsonb_build_object('eventId',d.event_id,'type','analytics.forecast.frozen.v1',
  'tenantId',s.tenant_id,'legalEntityId',s.legal_entity_id,'branchId',s.branch_id,'forecastId',f.id,'definitionVersion',1,'sourceHash',f.source_hash),
  'subscription',jsonb_build_object('id',s.id,'scope',jsonb_build_object('tenantId',s.tenant_id,'legalEntityId',s.legal_entity_id,'branchId',s.branch_id),
  'enabled',true,'url',s.url,'allowedHosts',jsonb_build_array(s.hostname),'keyVersion',s.key_version),
  'deliveryId',d.id,'leaseId',d.lease_id,'invocationId',d.invocation_id,'usageEventId',d.usage_event_id,
  'periodStart',analytics.process_utc(d.period_start),'periodEnd',analytics.process_utc(d.period_end),'attempt',d.attempt);
end $$;
revoke all on function intelligence_control.delivery_authorize(uuid,uuid) from public,anon,authenticated;

create function api.wave5_delivery_worker(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d intelligence_control.delivery_heads%rowtype;s intelligence_control.integration_subscriptions%rowtype;
 o intelligence_control.delivery_outcomes%rowtype;subscription billing.tenant_subscriptions%rowtype;v_state text;status integer;begin
 perform intelligence_control.worker_required();
 if p_action='readiness' then return jsonb_build_object('contractRevision',1,'ready',true,'providers',jsonb_build_object('committed_webhook.v1',1,'synthetic_subscription.v1',1));end if;
 if p_action='claim' then
  -- A lease lost after send cannot be auto-retried. ACK rows can be reconciled
  -- separately; expired attempts with no outcome retain uncertain reservations.
  update intelligence_control.delivery_heads set state='unknown' where state='leased' and lease_until<=statement_timestamp();
  insert into intelligence_control.delivery_heads(tenant_id,subscription_id,event_id)
   select s0.tenant_id,s0.id,e.id from intelligence_control.integration_subscriptions s0
   join analytics.pipeline_forecasts f on f.tenant_id=s0.tenant_id and f.legal_entity_id=s0.legal_entity_id and f.branch_id is not distinct from s0.branch_id
   join core.outbox_events e on e.tenant_id=f.tenant_id and e.aggregate_id=f.id and e.aggregate_type='pipeline_forecast' and e.topic='analytics.freeze_pipeline'
   where s0.enabled and e.created_at>=s0.created_at and not exists(select 1 from intelligence_control.delivery_heads h
    where h.tenant_id=s0.tenant_id and h.subscription_id=s0.id and h.event_id=e.id and h.generation=0)
   order by e.created_at,e.id limit 1000 on conflict do nothing;
  select * into d from intelligence_control.delivery_heads where state in('pending','retry') and available_at<=statement_timestamp()
   and attempt<8 order by available_at,id for update skip locked limit 1;
  if not found then return null;end if;
  select * into s from intelligence_control.integration_subscriptions where tenant_id=d.tenant_id and id=d.subscription_id and enabled;
  if not found then update intelligence_control.delivery_heads set state='dead_letter' where id=d.id;return null;end if;
  select * into subscription from billing.tenant_subscriptions where tenant_id=d.tenant_id;
  if d.period_start is null then
   d.period_start:=case when subscription.status='trialing' then coalesce(subscription.trial_started_at,subscription.created_at)
    else coalesce((select period_start from intelligence_control.quota_periods where tenant_id=d.tenant_id and metric_code='webhook.deliveries'
     and period_end=subscription.current_period_ends_at limit 1),date_trunc('month',statement_timestamp())) end;
   d.period_end:=case when subscription.status='trialing' then subscription.trial_ends_at else subscription.current_period_ends_at end;
  end if;
  if d.period_end is null then raise exception using errcode='55000',message='BILLING_PERIOD_UNAVAILABLE';end if;
  update intelligence_control.delivery_heads set attempt=attempt+1,state='leased',lease_id=gen_random_uuid(),lease_until=statement_timestamp()+interval '60 seconds',
   period_start=d.period_start,period_end=d.period_end where id=d.id returning * into d;
  insert into intelligence_control.delivery_attempts values(d.tenant_id,d.id,d.attempt,d.lease_id,s.key_version,s.version,statement_timestamp());
  begin
   return intelligence_control.delivery_authorize(d.id,d.lease_id);
  exception when insufficient_privilege then
   -- No send occurred. Keep this denied item from starving another tenant's
   -- queue; replay still requires a reasoned MFA review after access is fixed.
   update intelligence_control.delivery_heads set state='dead_letter' where id=d.id;
   return null;
  end;
 end if;
 if p_action='authorize' then return intelligence_control.delivery_authorize((p_payload->>'deliveryId')::uuid,(p_payload->>'leaseId')::uuid);end if;
 if p_action='key_ref' then
  perform intelligence_control.delivery_authorize((p_payload->>'deliveryId')::uuid,(p_payload->>'leaseId')::uuid);
  return to_jsonb((select s0.key_ref from intelligence_control.delivery_heads d0 join intelligence_control.integration_subscriptions s0 on s0.tenant_id=d0.tenant_id and s0.id=d0.subscription_id where d0.id=(p_payload->>'deliveryId')::uuid));
 end if;
 if p_action='outcome' then
  select * into d from intelligence_control.delivery_heads where id=(p_payload->>'deliveryId')::uuid and lease_id=(p_payload->>'leaseId')::uuid for update;
  if not found then raise exception using errcode='42501',message='LEASE_UNAVAILABLE';end if;
  v_state:=p_payload->>'state';status:=(p_payload->>'httpStatus')::integer;
  if v_state not in('acknowledged','retry','unknown','dead_letter') or v_state is null
   or (v_state='acknowledged' and (status is null or status not between 200 and 299))
   or (v_state='unknown' and status is not null) or (v_state in('retry','dead_letter') and (status is null or status between 200 and 299))
   or (v_state='retry' and d.attempt>=8) or (v_state='dead_letter' and d.attempt<>8) then
   raise exception using errcode='22023',message='OUTCOME_MISMATCH';end if;
  select * into o from intelligence_control.delivery_outcomes where tenant_id=d.tenant_id and delivery_id=d.id and attempt=d.attempt;
  if found then
   if o.state<>v_state or o.http_status is distinct from status then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;return '{}'::jsonb;
  end if;
  insert into intelligence_control.delivery_outcomes values(d.tenant_id,d.id,d.attempt,v_state,status,statement_timestamp());
  update intelligence_control.delivery_heads set state=v_state,available_at=statement_timestamp()+make_interval(secs=>least(3600,15*power(2,d.attempt-1)::integer)) where id=d.id;
  return '{}'::jsonb;
 end if;
 if p_action='settle_acknowledged' then
  for d in select * from intelligence_control.delivery_heads h where h.state='acknowledged'
   and not exists(select 1 from intelligence_control.usage_events u where u.tenant_id=h.tenant_id and u.invocation_id=h.invocation_id)
   order by h.id for update skip locked limit 100 loop
   perform api.wave5_settle_usage(d.tenant_id,d.invocation_id,d.usage_event_id,'1');
  end loop;return '{}'::jsonb;
 end if;
 raise exception using errcode='22023',message='VALIDATION_ERROR';
end $$;
revoke all on function api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb) to authenticated;
revoke all on function api.wave5_delivery_worker(text,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_delivery_worker(text,jsonb) to service_role;

create function api.wave5_delivery_review(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_delivery_id uuid,p_review_id uuid,p_action text,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d intelligence_control.delivery_heads%rowtype;r intelligence_control.delivery_reviews%rowtype;next_id uuid;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 select h.* into d from intelligence_control.delivery_heads h join intelligence_control.integration_subscriptions s on s.tenant_id=h.tenant_id and s.id=h.subscription_id
 where h.tenant_id=p_tenant_id and h.id=p_delivery_id and s.legal_entity_id=p_legal_entity_id and s.branch_id is not distinct from p_branch_id for update of h;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 select * into r from intelligence_control.delivery_reviews where id=p_review_id;
 if found then
  if r.tenant_id<>p_tenant_id or r.delivery_id<>p_delivery_id or r.actor_id<>auth.uid() or r.action<>p_action or r.reason<>p_reason then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  select id into next_id from intelligence_control.delivery_heads where replay_of=d.id;
  if next_id is not null then return jsonb_build_object('id',next_id,'state','pending','replayOf',d.id);end if;
  return jsonb_build_object('id',d.id,'state',case when p_action='acknowledged' then 'acknowledged' else 'retry' end);
 end if;
 if p_action not in('replay','acknowledged','not_sent') or p_action is null or p_reason is null
  or length(trim(p_reason)) not between 8 and 500 or p_review_id is null
  or (d.state='unknown' and p_action='replay') or (p_action='replay' and d.state<>'dead_letter')
  or (p_action in('acknowledged','not_sent') and d.state<>'unknown') then
  raise exception using errcode='22023',message='OUTCOME_REVIEW_REQUIRED';end if;
 insert into intelligence_control.delivery_reviews values(p_review_id,p_tenant_id,p_delivery_id,auth.uid(),p_action,p_reason,statement_timestamp());
 -- Each reviewed replay creates a new generation. It preserves the committed
 -- event, original invocation/quota and all earlier immutable attempt identities.
 if p_action='replay' or (p_action='not_sent' and d.attempt>=8) then
  if exists(select 1 from intelligence_control.delivery_heads where replay_of=d.id) then
   raise exception using errcode='40001',message='REPLAY_ALREADY_REVIEWED';end if;
  insert into intelligence_control.delivery_heads(tenant_id,subscription_id,event_id,invocation_id,usage_event_id,period_start,period_end,generation,replay_of)
   values(d.tenant_id,d.subscription_id,d.event_id,d.invocation_id,d.usage_event_id,d.period_start,d.period_end,d.generation+1,d.id) returning id into next_id;
  return jsonb_build_object('id',next_id,'state','pending','replayOf',d.id);
 end if;
 update intelligence_control.delivery_heads set state=case when p_action='acknowledged' then 'acknowledged' else 'retry' end,
  available_at=statement_timestamp() where id=d.id returning * into d;
 return jsonb_build_object('id',d.id,'state',d.state);
end $$;
revoke all on function api.wave5_delivery_review(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function api.wave5_delivery_review(uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;

create function api.wave5_integration_list(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_subscription_after uuid default null,p_delivery_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;deliveries jsonb;subscription_next text;delivery_next text;begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 with selected as (select s.*,row_number() over(order by id) ordinal from intelligence_control.integration_subscriptions s
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id is not distinct from p_branch_id
  and (p_subscription_after is null or id>p_subscription_after) order by id limit 51)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'url',url,'version',version::text,'keyVersion',key_version,'enabled',enabled) order by id)
  filter(where ordinal<=50),'[]'),case when count(*)>50 then max(id::text) filter(where ordinal=50) end
 into rows,subscription_next from selected;
 with selected as (select d.*,row_number() over(order by d.id) ordinal from intelligence_control.delivery_heads d
  join intelligence_control.integration_subscriptions s on s.tenant_id=d.tenant_id and s.id=d.subscription_id
  where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.branch_id is not distinct from p_branch_id
  and (p_delivery_after is null or d.id>p_delivery_after) order by d.id limit 51)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'subscriptionId',subscription_id,'state',state,'attempt',attempt,'generation',generation) order by id)
  filter(where ordinal<=50),'[]'),case when count(*)>50 then max(id::text) filter(where ordinal=50) end
 into deliveries,delivery_next from selected;
 return jsonb_build_object('contractRevision',1,'subscriptions',rows,'deliveries',deliveries,
  'subscriptionNext',subscription_next,'deliveryNext',delivery_next);
end $$;
revoke all on function api.wave5_integration_list(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_integration_list(uuid,uuid,uuid,uuid,uuid) to authenticated;

create function api.wave5_integration_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 return auth.uid();end $$;
revoke all on function api.wave5_integration_authorize(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_integration_authorize(uuid,uuid,uuid) to authenticated;

-- Observations come from durable queue and metering rows, never desktop claims.
-- An absent current quota period remains unknown; it is not published as zero.
create function api.wave5_health_collect(p_collection_id uuid,p_tenant_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare lag_seconds numeric;retries bigint;dead bigint;quota numeric;used numeric;observations jsonb;prior jsonb;r jsonb;begin
 perform intelligence_control.worker_required();
 if p_collection_id is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_collection_id::text,530));
 select jsonb_agg(jsonb_build_object('code',code,'exactValue',exact_value::text,'observedAt',analytics.process_utc(observed_at)) order by code)
  into prior from intelligence_control.health_probes where tenant_id is not distinct from p_tenant_id and id in(
   select md5(p_collection_id::text||':'||code)::uuid from unnest(array['worker_lag_seconds','retry_count','dead_letter_count','quota_remaining'])code);
 if prior is not null then return jsonb_build_object('contractRevision',1,'probes',prior);end if;
 select coalesce(greatest(0,floor(extract(epoch from statement_timestamp()-min(available_at) filter(where state in('pending','retry') and available_at<=statement_timestamp())))),0),
  count(*) filter(where state='retry'),count(*) filter(where state='dead_letter') into lag_seconds,retries,dead
  from intelligence_control.delivery_heads where p_tenant_id is null or tenant_id=p_tenant_id;
 observations:=jsonb_build_array(jsonb_build_object('code','worker_lag_seconds','exactValue',lag_seconds::text),
  jsonb_build_object('code','retry_count','exactValue',retries::text),jsonb_build_object('code','dead_letter_count','exactValue',dead::text));
 if p_tenant_id is not null then
  begin
   quota:=intelligence_control.quota_limit(p_tenant_id,'webhook.deliveries');
   select settled_units+reserved_units into used from intelligence_control.quota_periods where tenant_id=p_tenant_id and metric_code='webhook.deliveries'
    and period_start<=statement_timestamp() and period_end>statement_timestamp();
   if used is not null then observations:=observations||jsonb_build_array(jsonb_build_object('code','quota_remaining','exactValue',greatest(0,quota-used)::text));end if;
  exception when insufficient_privilege then null;end;
 end if;
 select jsonb_agg(value||jsonb_build_object('observedAt',analytics.process_utc(statement_timestamp())) order by value->>'code')
  into observations from jsonb_array_elements(observations);
 for r in select * from jsonb_array_elements(observations) loop
  perform api.record_wave5_health_probe(md5(p_collection_id::text||':'||(r->>'code'))::uuid,p_tenant_id,r->>'code',r->>'exactValue',statement_timestamp());
 end loop;
 return jsonb_build_object('contractRevision',1,'probes',observations);
end $$;
revoke all on function api.wave5_health_collect(uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_health_collect(uuid,uuid) to service_role;

-- UNAPPLIED. No credential, model provider, secret or entitlement is enabled.
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
 select code,'quota.integration.commands',false from billing.plans on conflict do nothing;
create table intelligence_control.integration_credentials(
 id uuid primary key,token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'),
 tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,actor_id uuid not null references auth.users(id),
 starts_at timestamptz not null,expires_at timestamptz not null,revoked_at timestamptz,
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(isfinite(starts_at) and isfinite(expires_at) and expires_at>starts_at and expires_at-starts_at<=interval '366 days'));
create table intelligence_control.external_periods(
 tenant_id uuid not null references core.tenants(id),period_start timestamptz not null,period_end timestamptz not null,
 reserved numeric(20,0) not null default 0 check(reserved>=0),primary key(tenant_id,period_start),check(period_end>period_start));
create table intelligence_control.external_requests(
 tenant_id uuid not null,credential_id uuid not null,command_id uuid not null,idempotency_key uuid not null,
 request_hash text not null,request jsonb not null,period_start timestamptz not null,response jsonb,
 created_at timestamptz not null default statement_timestamp(),primary key(tenant_id,credential_id,command_id),
 unique(tenant_id,credential_id,idempotency_key),foreign key(tenant_id,credential_id) references intelligence_control.integration_credentials(tenant_id,id),
 foreign key(tenant_id,period_start) references intelligence_control.external_periods(tenant_id,period_start));
create table intelligence_control.external_throttles(
 credential_id uuid not null references intelligence_control.integration_credentials(id),window_start timestamptz not null,
 count integer not null check(count between 0 and 60),primary key(credential_id,window_start));
create table intelligence_control.model_invocations(
 invocation_id uuid primary key,tenant_id uuid not null references core.tenants(id),source_id uuid not null,
 source_hash text not null check(source_hash ~ '^[0-9a-f]{64}$'),manifest_hash text not null check(manifest_hash ~ '^[0-9a-f]{64}$'),
 request jsonb not null,created_at timestamptz not null default statement_timestamp(),
 foreign key(tenant_id,source_id) references analytics.pipeline_forecasts(tenant_id,id));
create table intelligence_control.model_outcomes(
 invocation_id uuid primary key references intelligence_control.model_invocations(invocation_id),state text not null check(state in('settled','unknown')),
 tokens numeric(20,0),suggestion jsonb,recorded_at timestamptz not null default statement_timestamp(),
 check((state='unknown' and tokens is null and suggestion is null) or (state='settled' and tokens is not null and tokens>=0 and suggestion is not null and jsonb_typeof(suggestion)='object')));
do $$declare rel text;begin foreach rel in array array['integration_credentials','external_periods','external_requests','external_throttles','model_invocations','model_outcomes'] loop
 execute format('alter table intelligence_control.%I enable row level security',rel);
 execute format('alter table intelligence_control.%I force row level security',rel);
 execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
 if rel in('model_invocations','model_outcomes') then
 execute format('create trigger immutable before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);end if;
end loop;end $$;
create index credential_scope_idx on intelligence_control.integration_credentials(tenant_id,legal_entity_id,branch_id,id);
create index model_source_idx on intelligence_control.model_invocations(tenant_id,source_id,invocation_id);

create function api.wave5_credential_manage(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_action text,p_id uuid,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command uuid;v_hash text;v_receipt jsonb;
begin
 if p_id is null then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform analytics.pipeline_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'integrations.manage',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 -- Each credential has one immutable registration and one revocation identity.
 -- Repeating the original request reopens its audited receipt after live access.
 v_command:=md5('wave5.credential:'||p_id::text||':'||p_action||':'||auth.uid()::text)::uuid;
 v_hash:=core.wave3_request_hash('integration.credential.'||p_action,v_command,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,null);
 v_receipt:=core.wave3_replay(p_tenant_id,'integration.credential.'||p_action,v_command,v_command,v_hash);
 if v_receipt is not null then return v_receipt;end if;
 if p_action='register' and (p_payload-array['tokenHash','startsAt','expiresAt'])='{}' and p_payload ?& array['tokenHash','startsAt','expiresAt'] then
  insert into intelligence_control.integration_credentials values(p_id,p_payload->>'tokenHash',p_tenant_id,p_legal_entity_id,p_branch_id,
   auth.uid(),(p_payload->>'startsAt')::timestamptz,(p_payload->>'expiresAt')::timestamptz,null);
 elsif p_action='revoke' and p_payload='{}' then
  update intelligence_control.integration_credentials set revoked_at=coalesce(revoked_at,statement_timestamp()) where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id is not distinct from p_branch_id and id=p_id;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 else raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 -- Immutable system audit plus outbox; never a token or hash in public receipt.
 return core.wave3_finish_command(p_tenant_id,'integration.credential.'||p_action,v_command,'integration_credential',p_id,v_command,
  v_hash,null,jsonb_build_object('id',p_id,'version','1','state',p_action),p_legal_entity_id,p_branch_id);
end $$;

create function api.wave5_external_worker(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c intelligence_control.integration_credentials%rowtype;r intelligence_control.external_requests%rowtype;
 req jsonb:=p_payload->'request';s jsonb;h text;v_period_start timestamptz;v_period_end timestamptz;cap numeric;used numeric;
 window_at timestamptz:=date_trunc('minute',statement_timestamp());throttle integer;saved_claims text;result jsonb;begin
 perform intelligence_control.worker_required();
 select * into c from intelligence_control.integration_credentials where token_hash=p_payload->>'tokenHash';
 if not found or c.revoked_at is not null or c.starts_at>statement_timestamp() or c.expires_at<=statement_timestamp() then
  raise exception using errcode='42501',message='INTEGRATION_ACCESS_DENIED';end if;
 if p_action='credential' then return jsonb_build_object('id',c.id,'tokenHash',c.token_hash,
  'scope',jsonb_build_object('tenantId',c.tenant_id,'legalEntityId',c.legal_entity_id,'branchId',c.branch_id),
  'startsAt',floor(extract(epoch from c.starts_at))::bigint,'expiresAt',floor(extract(epoch from c.expires_at))::bigint,'revokedAt',null,
  'commands',jsonb_build_array('analytics.freeze_pipeline.v1'));end if;
 if req is null or req->>'commandCode' is distinct from 'analytics.freeze_pipeline.v1' or req->>'schemaVersion' is distinct from '1'
  or (req-array['schemaVersion','scope','commandCode','commandId','idempotencyKey','clientTimestamp','horizonStart','horizonEnd'])<>'{}'
  or not(req ?& array['schemaVersion','scope','commandCode','commandId','idempotencyKey','clientTimestamp','horizonStart','horizonEnd'])
  or req->'scope' is distinct from jsonb_build_object('tenantId',c.tenant_id,'legalEntityId',c.legal_entity_id,'branchId',c.branch_id) then
  raise exception using errcode='42501',message='INTEGRATION_ACCESS_DENIED';end if;
 -- Credential-bound delegation uses AAL1 only. It cannot forge human MFA or
 -- cross into a privileged command. The named domain command rechecks authority.
 saved_claims:=current_setting('request.jwt.claims',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.actor_id,'role','authenticated','aal','aal1')::text,true);
 perform analytics.pipeline_access(c.tenant_id,c.legal_entity_id,c.branch_id);
 perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
 perform 1 from billing.tenant_subscriptions where tenant_id=c.tenant_id for update;
 select case when status='trialing' then coalesce(trial_started_at,created_at) else date_trunc('month',statement_timestamp()) end,
  case when status='trialing' then trial_ends_at else current_period_ends_at end into v_period_start,v_period_end
  from billing.tenant_subscriptions where tenant_id=c.tenant_id;
 if v_period_end is null then raise exception using errcode='55000',message='BILLING_PERIOD_UNAVAILABLE';end if;
 perform pg_advisory_xact_lock(hashtextextended(c.tenant_id::text||':integration.commands',58));
 cap:=intelligence_control.quota_limit(c.tenant_id,'integration.commands');
 h:=encode(extensions.digest(req::text,'sha256'),'hex');
 select * into r from intelligence_control.external_requests where tenant_id=c.tenant_id and credential_id=c.id
  and (command_id=(req->>'commandId')::uuid or idempotency_key=(req->>'idempotencyKey')::uuid) for update;
 if found then
  if r.request_hash<>h then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
 else
  if p_action<>'reserve' then raise exception using errcode='42501',message='RESERVATION_REQUIRED';end if;
  if exists(select 1 from intelligence_control.external_periods x where x.tenant_id=c.tenant_id and x.period_start<>v_period_start
   and x.period_start<v_period_end and x.period_end>v_period_start) then raise exception using errcode='22023',message='PERIOD_CONFLICT';end if;
  insert into intelligence_control.external_periods values(c.tenant_id,v_period_start,v_period_end,0) on conflict do nothing;
  select x.reserved into used from intelligence_control.external_periods x where x.tenant_id=c.tenant_id and x.period_start=v_period_start for update;
  if used+1>cap then raise exception using errcode='54000',message='QUOTA_EXCEEDED';end if;
  insert into intelligence_control.external_throttles values(c.id,window_at,0) on conflict do nothing;
  select count into throttle from intelligence_control.external_throttles where credential_id=c.id and window_start=window_at for update;
  if throttle>=60 then raise exception using errcode='54000',message='THROTTLED';end if;
  update intelligence_control.external_throttles set count=count+1 where credential_id=c.id and window_start=window_at;
  update intelligence_control.external_periods x set reserved=reserved+1 where x.tenant_id=c.tenant_id and x.period_start=v_period_start;
  insert into intelligence_control.external_requests values(c.tenant_id,c.id,(req->>'commandId')::uuid,(req->>'idempotencyKey')::uuid,h,req,v_period_start,null,statement_timestamp()) returning * into r;
 end if;
 if p_action='reserve' then return jsonb_build_object('quotaReserved',true,'throttleReserved',true);end if;
 if p_action<>'dispatch' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if r.response is not null then return r.response;end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c.actor_id,'role','authenticated','aal','aal1')::text,true);
 result:=api.freeze_pipeline_forecast(c.tenant_id,c.legal_entity_id,c.branch_id,(req->>'commandId')::uuid,(req->>'idempotencyKey')::uuid,
  (req->>'clientTimestamp')::timestamptz,(req->>'horizonStart')::date,(req->>'horizonEnd')::date);
 perform set_config('request.jwt.claims',coalesce(saved_claims,''),true);
 update intelligence_control.external_requests set response=result where tenant_id=c.tenant_id and credential_id=c.id and command_id=r.command_id;
 return result;
end $$;

create function api.wave5_model_worker(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i intelligence_control.model_invocations%rowtype;o intelligence_control.model_outcomes%rowtype;begin
 perform intelligence_control.worker_required();
 if p_action='readiness' then return jsonb_build_object('contractRevision',1,'ready',true);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_payload->>'invocationId',59));
 if p_action='begin' then
  select * into i from intelligence_control.model_invocations where invocation_id=(p_payload->>'invocationId')::uuid;
  if found then
   if i.request<>p_payload then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
   select * into o from intelligence_control.model_outcomes where invocation_id=i.invocation_id;
   return case when o.invocation_id is null then jsonb_build_object('state','pending')
    else jsonb_build_object('state',o.state,'tokens',o.tokens::text,'suggestion',o.suggestion) end;
  end if;
  if p_payload->>'policyRevision' is distinct from '1' or coalesce(p_payload->>'maxTokens','')!~ '^[1-9][0-9]{0,6}$'
   or not exists(select 1 from analytics.pipeline_forecasts where tenant_id=(p_payload->>'tenantId')::uuid
    and id=(p_payload->>'sourceId')::uuid and source_hash=p_payload->>'sourceHash') then raise exception using errcode='22023',message='MODEL_BASIS_MISMATCH';end if;
  insert into intelligence_control.model_invocations values((p_payload->>'invocationId')::uuid,(p_payload->>'tenantId')::uuid,
   (p_payload->>'sourceId')::uuid,p_payload->>'sourceHash',p_payload->>'manifestHash',p_payload,statement_timestamp());
  return jsonb_build_object('state','new');
 elsif p_action='outcome' then
  select * into i from intelligence_control.model_invocations where invocation_id=(p_payload->>'invocationId')::uuid;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
  if p_payload->>'state' is null or p_payload->>'state' not in('settled','unknown') or
   (p_payload->>'state'='unknown' and ((p_payload-array['invocationId','state'])<>'{}')) then
   raise exception using errcode='22023',message='MODEL_OUTCOME_MISMATCH';end if;
  if p_payload->>'state'='settled' and (
   (p_payload-array['invocationId','state','tokens','suggestion'])<>'{}' or not(p_payload ?& array['invocationId','state','tokens','suggestion'])
   or jsonb_typeof(p_payload->'tokens') is distinct from 'string' or coalesce(p_payload->>'tokens','')!~ '^(0|[1-9][0-9]{0,6})$'
   or (p_payload->>'tokens')::numeric>(i.request->>'maxTokens')::numeric
   or jsonb_typeof(p_payload->'suggestion') is distinct from 'object'
   or ((p_payload->'suggestion')-array['commandCode','sourceId','sourceHash','horizonStart','horizonEnd'])<>'{}'
   or not((p_payload->'suggestion') ?& array['commandCode','sourceId','sourceHash','horizonStart','horizonEnd'])
   or p_payload#>>'{suggestion,commandCode}' is distinct from 'analytics.freeze_pipeline.v1'
   or p_payload#>>'{suggestion,sourceId}' is distinct from i.source_id::text or p_payload#>>'{suggestion,sourceHash}' is distinct from i.source_hash
   or not exists(select 1 from analytics.pipeline_forecasts f where f.id=i.source_id and f.tenant_id=i.tenant_id
    and f.horizon_start::text=(p_payload#>>'{suggestion,horizonStart}') and f.horizon_end::text=(p_payload#>>'{suggestion,horizonEnd}'))) then
   raise exception using errcode='22023',message='MODEL_OUTCOME_MISMATCH';end if;
  select * into o from intelligence_control.model_outcomes where invocation_id=i.invocation_id;
  if found then
   if o.state<>p_payload->>'state' or o.tokens is distinct from (p_payload->>'tokens')::numeric
    or o.suggestion is distinct from p_payload->'suggestion' then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;return '{}'::jsonb;
  end if;
  insert into intelligence_control.model_outcomes values(i.invocation_id,p_payload->>'state',(p_payload->>'tokens')::numeric,p_payload->'suggestion',statement_timestamp());
  return '{}'::jsonb;
 end if;
 raise exception using errcode='22023',message='VALIDATION_ERROR';
end $$;
revoke all on function api.wave5_credential_manage(uuid,uuid,uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_credential_manage(uuid,uuid,uuid,text,uuid,jsonb) to authenticated;
revoke all on function api.wave5_external_worker(text,jsonb),api.wave5_model_worker(text,jsonb) from public,anon,authenticated;
grant execute on function api.wave5_external_worker(text,jsonb),api.wave5_model_worker(text,jsonb) to service_role;

create function api.wave5_worker_entitlement(p_scope jsonb) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare tenant uuid:=(p_scope->>'tenantId')::uuid;begin
 perform intelligence_control.worker_required();
 perform intelligence_control.quota_limit(tenant,'integration.commands');
 return exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=tenant and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp()))));
end $$;
revoke all on function api.wave5_worker_entitlement(jsonb) from public,anon,authenticated;
grant execute on function api.wave5_worker_entitlement(jsonb) to service_role;

-- Only explicitly allowlisted synthetic tenants enter scheduled application.
-- The existing installed apply RPC owns billing locks, MFA-grant revalidation,
-- seat admission and stable command identity. No tenant is enabled here.
create function api.wave5_subscription_due(p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;n integer;cursor uuid;begin
 perform intelligence_control.worker_required();
 select coalesce(jsonb_agg(jsonb_build_object('tenantId',tenant_id,'revisionId',id) order by id),'[]'),count(*) into rows,n
 from (select r.id,r.tenant_id from intelligence_control.subscription_revisions r
  join intelligence_control.synthetic_tenants t on t.tenant_id=r.tenant_id and t.allowed
  where r.trial_starts_at<=statement_timestamp() and r.trial_ends_at>statement_timestamp()
   and (p_after is null or r.id>p_after) and not exists(select 1 from intelligence_control.subscription_activations a
    where a.tenant_id=r.tenant_id and a.revision_id=r.id) order by r.id limit 51) q;
 if n>50 then cursor:=(rows->49->>'revisionId')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('contractRevision',1,'items',rows,'nextCursor',cursor);
end $$;
revoke all on function api.wave5_subscription_due(uuid) from public,anon,authenticated;
grant execute on function api.wave5_subscription_due(uuid) to service_role;

-- UNAPPLIED candidate. Uses posted journals, immutable AR items, and corrected
-- AP residuals. W4 payroll/project reimbursements lack authoritative payment
-- due dates and are explicitly unavailable from this provider.
create function analytics.cash_access(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or e is null then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform core.wave3_require_scope(t,'analytics.view',e,b);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 perform core.wave3_require_scope(t,'finance.receivables.view',e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';end if;
end $$;
revoke all on function analytics.cash_access(uuid,uuid,uuid) from public,anon,authenticated;

create function api.wave5_cash_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);return auth.uid();end $$;

-- Use separately owned AP read/reversal providers when installed. The fallback
-- only recognizes existing payment capabilities and never invents a bill API.
create function analytics.cash_payables_allowed(p_tenant uuid,p_entity uuid,p_branch uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$declare allowed boolean;begin
 if pg_catalog.to_regprocedure('finance.payable_read_allowed(uuid,uuid,uuid)') is not null then
  execute 'select finance.payable_read_allowed($1,$2,$3)' into allowed using p_tenant,p_entity,p_branch;
  return coalesce(allowed,false);
 end if;
 return core.is_tenant_member(p_tenant) and (core.has_permission(p_tenant,'finance.payments.manage',p_entity,p_branch)
  or core.has_permission(p_tenant,'finance.payments.post',p_entity,p_branch));
end $$;
create function analytics.cash_ap_reversal_evidence(p_tenant uuid,p_allocation uuid,p_before date,p_through timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare evidence jsonb;begin
 if pg_catalog.to_regclass('finance.allocation_reversals') is null then return null;end if;
 execute 'select jsonb_build_object(''id'',r.id,''postingDate'',r.posting_date::text) from finance.allocation_reversals r
  where r.tenant_id=$1 and r.allocation_id=$2 and r.posting_date<$3 and r.created_at<=$4 limit 1'
  into evidence using p_tenant,p_allocation,p_before,p_through;
 return evidence;
end $$;
revoke all on function analytics.cash_payables_allowed(uuid,uuid,uuid),analytics.cash_ap_reversal_evidence(uuid,uuid,date,timestamptz) from public,anon,authenticated;

create function api.wave5_cash_basis(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_start date,p_end date,p_recorded_through timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare controls jsonb;obligations jsonb;sources jsonb;result jsonb;n integer;
 can_read_payables boolean;providers jsonb:='["bank_cash","receivables"]'::jsonb;provider_status jsonb;begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 can_read_payables:=analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,p_branch_id);
 if can_read_payables then providers:=providers||jsonb_build_array('payables');end if;
 provider_status:=jsonb_build_object('bank_cash','available','receivables','available',
  'payables',case when can_read_payables then 'available' else 'permission_required' end,
  'payroll','missing_authoritative_due_date','project_reimbursements','missing_authoritative_due_date');
 if p_start is null or p_end is null or p_end<=p_start or p_end-p_start>366 or not isfinite(p_start) or not isfinite(p_end)
  or p_recorded_through is null or not isfinite(p_recorded_through) or p_recorded_through>statement_timestamp()
  or p_start::timestamptz>p_recorded_through then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 -- Current cash-account configuration has no historical mapping journal.
 -- Reject a date predating its latest revision instead of inventing that mapping.
 if exists(select 1 from finance.cash_bank_accounts c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or c.branch_id=p_branch_id) and c.updated_at>p_start::timestamptz) then
  raise exception using errcode='55000',message='CASH_MAPPING_HISTORY_REQUIRED';end if;
 if exists(select account_id from finance.cash_bank_accounts c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or c.branch_id=p_branch_id) and c.status='active' group by account_id having count(*)>1) then
  raise exception using errcode='55000',message='CASH_CONTROL_MAPPING_AMBIGUOUS';end if;
 if exists(select 1 from finance.cash_bank_accounts c join finance.journal_lines l on l.tenant_id=c.tenant_id and l.account_id=c.account_id
  join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and (p_branch_id is null or c.branch_id=p_branch_id)
   and (p_branch_id is null or l.branch_id=p_branch_id) and c.status='active' and j.status='posted'
   and l.posting_date<p_start and j.created_at<=p_recorded_through and l.currency_code<>c.currency_code
   and l.transaction_debit<>l.transaction_credit) then
  raise exception using errcode='55000',message='CASH_CURRENCY_MAPPING_REQUIRED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'accountId',c.account_id,'branchId',c.branch_id,'currency',c.currency_code,
  'version',c.version::text,'amount',coalesce((select sum(l.transaction_debit-l.transaction_credit)
   from finance.journal_lines l join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
   where l.tenant_id=c.tenant_id and l.legal_entity_id=c.legal_entity_id and l.account_id=c.account_id and l.currency_code=c.currency_code
    and (p_branch_id is null or l.branch_id=p_branch_id) and l.posting_date<p_start and j.status='posted' and j.created_at<=p_recorded_through),0)::text) order by c.id),'[]')
 into controls from finance.cash_bank_accounts c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or c.branch_id=p_branch_id) and c.status='active';
 with ar_remaining as (select o.*,o.original_amount+
  coalesce((select sum(a.source_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through),0)-
  coalesce((select sum(a.transaction_amount+a.write_off+a.discount_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through),0) remaining
  from finance.open_items o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and (p_branch_id is null or o.branch_id=p_branch_id)
   and o.kind='AR' and o.original_amount>0 and o.posting_date<p_start and o.created_at<=p_recorded_through and o.due_date>=p_start and o.due_date<p_end),
 ap_remaining as (select o.*,o.original_amount+
  coalesce((select sum(a.source_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through),0)-
  coalesce((select sum(a.transaction_amount+a.write_off+a.discount_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through
   and analytics.cash_ap_reversal_evidence(a.tenant_id,a.id,p_start,p_recorded_through) is null),0) remaining
  from finance.open_items o where can_read_payables and o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id
   and (p_branch_id is null or o.branch_id=p_branch_id) and o.kind='AP' and o.original_amount>0 and o.posting_date<p_start
   and o.created_at<=p_recorded_through and o.due_date>=p_start and o.due_date<p_end),
 all_rows as (select id,branch_id,currency_code,due_date,remaining,'receivables'::text provider from ar_remaining where remaining>0
  union all select id,branch_id,currency_code,due_date,remaining,'payables'::text provider from ap_remaining where remaining>0),
 bounded as (select * from all_rows order by provider,id limit 10001)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'branchId',branch_id,'currency',currency_code,'dueDate',due_date::text,
  'amount',remaining::text,'version','1','provider',provider) order by provider,id),'[]'),count(*) into obligations,n from bounded;
 if n+jsonb_array_length(controls)>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 -- Retain each contributing posted journal/allocation identity, bounded as a
 -- complete manifest. Mutable document text and customer PII are excluded.
 with refs as (
 select jsonb_build_object('kind','cash_journal','id',l.id,'branchId',l.branch_id,'version','1',
  'debit',l.transaction_debit::text,'credit',l.transaction_credit::text,'currency',l.currency_code) value
 from finance.journal_lines l join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
 where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and (p_branch_id is null or l.branch_id=p_branch_id)
  and l.posting_date<p_start and j.status='posted' and j.created_at<=p_recorded_through
  and exists(select 1 from jsonb_array_elements(controls) c where c->>'accountId'=l.account_id::text)
 union all select jsonb_build_object('kind','ar_allocation','id',a.id,'branchId',a.branch_id,'version','1',
  'sourceAmount',a.source_amount::text,'targetAmount',a.transaction_amount::text,'writeOff',a.write_off::text,'discount',a.discount_amount::text)
 from finance.open_item_allocations a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.posting_date<p_start and a.created_at<=p_recorded_through
  and exists(select 1 from jsonb_array_elements(obligations) o where o->>'provider'='receivables' and o->>'id' in(a.source_open_item_id::text,a.target_open_item_id::text))
 union all select jsonb_build_object('kind','ap_allocation','id',a.id,'branchId',a.branch_id,'version','1',
  'sourceAmount',a.source_amount::text,'targetAmount',a.transaction_amount::text,'writeOff',a.write_off::text,'discount',a.discount_amount::text,
  'reversal',analytics.cash_ap_reversal_evidence(a.tenant_id,a.id,p_start,p_recorded_through))
 from finance.open_item_allocations a where can_read_payables and a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.posting_date<p_start and a.created_at<=p_recorded_through
  and exists(select 1 from jsonb_array_elements(obligations) o where o->>'provider'='payables' and o->>'id' in(a.source_open_item_id::text,a.target_open_item_id::text)))
 select coalesce(jsonb_agg(value order by value->>'id'),'[]'),count(*) into sources,n from (select * from refs limit 10001) r;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 if exists(select 1 from jsonb_array_elements(controls||obligations||sources) r where not core.has_permission(p_tenant_id,'finance.view',p_legal_entity_id,(r->>'branchId')::uuid)
  or (r->>'provider'='receivables' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or (r->>'kind' like 'ar_%' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or ((r->>'provider'='payables' or r->>'kind' like 'ap_%') and not analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,(r->>'branchId')::uuid))) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 result:=jsonb_build_object('contractRevision',2,'definition','dated_transaction_cash_ar_and_ap.v2',
  'scope',jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
  'horizonStart',p_start::text,'horizonEnd',p_end::text,'recordedThrough',analytics.process_utc(p_recorded_through),
  'completeProviders',providers,'providerStatus',provider_status,'controls',controls,'obligations',obligations,'sources',sources,
  'exclusions',jsonb_build_array('overdue_before_horizon','unallocated_credits','payroll','project_reimbursements'));
 if octet_length(result::text)>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return jsonb_build_object('canonicalText',result::text,'sourceHash',encode(extensions.digest(result::text,'sha256'),'hex'));
end $$;
create table analytics.cash_scenario_revisions(id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,
 actor_id uuid not null references auth.users(id),source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
 canonical_text text not null,evidence jsonb not null,parameters jsonb not null,created_at timestamptz not null default statement_timestamp(),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(octet_length(canonical_text)<=8388608 and octet_length(parameters::text)<=8388608),
 check(source_hash=encode(extensions.digest(convert_to(canonical_text,'UTF8'),'sha256'),'hex') and evidence=canonical_text::jsonb));
alter table analytics.cash_scenario_revisions enable row level security;
alter table analytics.cash_scenario_revisions force row level security;
revoke all on analytics.cash_scenario_revisions from public,anon,authenticated;
create trigger immutable before update or delete on analytics.cash_scenario_revisions for each row execute function analytics.immutable_evidence();
create function api.wave5_cash_save(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_source_hash text,p_parameters jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare old analytics.cash_scenario_revisions%rowtype;basis jsonb;data jsonb;k text;v jsonb;begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_id is null or p_parameters is null or jsonb_typeof(p_parameters)<>'object' or (p_parameters-array['horizonStart','horizonEnd','recordedThrough','overrides'])<>'{}'
  or not(p_parameters ?& array['horizonStart','horizonEnd','recordedThrough','overrides']) or jsonb_typeof(p_parameters->'overrides')<>'object' then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,509));
 select * into old from analytics.cash_scenario_revisions where id=p_id;
 if found then
  if old.tenant_id<>p_tenant_id or old.legal_entity_id<>p_legal_entity_id or old.branch_id is distinct from p_branch_id or old.actor_id<>auth.uid()
   or old.source_hash is distinct from p_source_hash or old.parameters<>p_parameters then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  perform api.wave5_cash_get(p_tenant_id,p_legal_entity_id,p_branch_id,p_id);
  return jsonb_build_object('id',p_id,'sourceHash',p_source_hash,'version','1');end if;
 basis:=api.wave5_cash_basis(p_tenant_id,p_legal_entity_id,p_branch_id,(p_parameters->>'horizonStart')::date,(p_parameters->>'horizonEnd')::date,(p_parameters->>'recordedThrough')::timestamptz);
 if basis->>'sourceHash' is distinct from p_source_hash then raise exception using errcode='40001',message='SOURCE_BASIS_CHANGED';end if;
 data:=(basis->>'canonicalText')::jsonb;
 if not (data->'completeProviders' ? 'payables') then raise exception using errcode='42501',message='PAYABLES_PERMISSION_REQUIRED';end if;
 for k,v in select * from jsonb_each(p_parameters->'overrides') loop
  if not exists(select 1 from jsonb_array_elements(data->'obligations') o where o->>'id'=k)
   or jsonb_typeof(v)<>'object' or (v-array['dueDate','remainingUnits','reasonCode'])<>'{}' or not(v ?& array['dueDate','remainingUnits','reasonCode'])
   or jsonb_typeof(v->'remainingUnits')<>'string' or coalesce(v->>'remainingUnits','')!~ '^(0|[1-9][0-9]{0,19})$'
   or jsonb_typeof(v->'dueDate')<>'string' or coalesce(v->>'dueDate','')!~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(v->>'reasonCode','') not in('collection_delay','payment_delay','reviewed_amount')
   or (v->>'dueDate')::date<(p_parameters->>'horizonStart')::date or (v->>'dueDate')::date>=(p_parameters->>'horizonEnd')::date then
   raise exception using errcode='22023',message='INVALID_SCENARIO_OVERRIDE';end if;
 end loop;
 insert into analytics.cash_scenario_revisions values(p_id,p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),p_source_hash,basis->>'canonicalText',data,p_parameters,statement_timestamp());
 perform core.wave3_finish_command(p_tenant_id,'analytics.cash_scenario',p_id,'cash_scenario',p_id,p_id,
  core.wave3_request_hash('analytics.cash_scenario',p_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_parameters,null),null,
  jsonb_build_object('id',p_id,'sourceHash',p_source_hash,'version','1'),p_legal_entity_id,p_branch_id);
 return jsonb_build_object('id',p_id,'sourceHash',p_source_hash,'version','1');end $$;
create function api.wave5_cash_get(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare s analytics.cash_scenario_revisions%rowtype;begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 select * into s from analytics.cash_scenario_revisions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id is not distinct from p_branch_id and id=p_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 if (s.evidence->'completeProviders' ? 'payables') and not analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,p_branch_id) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 if exists(select 1 from jsonb_array_elements((s.evidence->'controls')||(s.evidence->'obligations')||(s.evidence->'sources')) r where
  not core.has_permission(p_tenant_id,'finance.view',p_legal_entity_id,(r->>'branchId')::uuid)
  or (r->>'provider'='receivables' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or (r->>'kind' like 'ar_%' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or ((r->>'provider'='payables' or r->>'kind' like 'ap_%') and not analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,(r->>'branchId')::uuid))) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 return jsonb_build_object('id',s.id,'sourceHash',s.source_hash,'canonicalText',s.canonical_text,'parameters',s.parameters);end $$;
revoke all on function api.wave5_cash_authorize(uuid,uuid,uuid),api.wave5_cash_basis(uuid,uuid,uuid,date,date,timestamptz),api.wave5_cash_save(uuid,uuid,uuid,uuid,text,jsonb),api.wave5_cash_get(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_cash_authorize(uuid,uuid,uuid),api.wave5_cash_basis(uuid,uuid,uuid,date,date,timestamptz),api.wave5_cash_save(uuid,uuid,uuid,uuid,text,jsonb),api.wave5_cash_get(uuid,uuid,uuid,uuid) to authenticated;

-- UNAPPLIED extension. Requires the existing reviewed Wave 3 governed-export
-- candidate 20260926009000 first. Reuses its command, jobs, audit and file codec.
alter function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) rename to wave3_report_export_document;
create function finance.report_export_document(t uuid,e uuid,b uuid,resource text,i uuid,section text,filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare f jsonb;s jsonb;data jsonb;rows jsonb;meta jsonb;start_date date;end_date date;n integer;begin
 if resource is null then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
 if resource not in('w5_pipeline','w5_cash') then return finance.wave3_report_export_document(t,e,b,resource,i,section,filters);end if;
 perform core.wave3_require_scope(t,'finance.reports.export',e,b);
 if i is null or filters is null or jsonb_typeof(filters)<>'object' or (filters-'currency')<>'{}'
  or (filters ? 'currency' and (jsonb_typeof(filters->'currency')<>'string' or coalesce(filters->>'currency','')!~ '^[A-Z]{3}$')) then
  raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
 if resource='w5_pipeline' then
  if section is distinct from 'currencies' then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
  f:=api.get_pipeline_forecast(t,e,b,i);data:=f->'evidence';
  select coalesce(jsonb_agg(x order by x->>'currency'),'[]') into rows from jsonb_array_elements(data->'currencies') x
   where filters->>'currency' is null or x->>'currency'=filters->>'currency';
  meta:=jsonb_build_object('as_of',data->>'asOf','generated_at',data->>'generatedAt','horizon_start',data->>'horizonStart','horizon_end',data->>'horizonEnd',
   'calculation','pipeline.current_weighted.v1','source_basis_hash',f->>'sourceHash');
 else
  if section is distinct from 'buckets' then raise exception using errcode='22023',message='REPORT_EXPORT_SOURCE_INVALID';end if;
  s:=api.wave5_cash_get(t,e,b,i);data:=(s->>'canonicalText')::jsonb;start_date:=(data->>'horizonStart')::date;end_date:=(data->>'horizonEnd')::date;
  if exists(select 1 from jsonb_array_elements(data->'obligations') o where not exists(select 1 from jsonb_array_elements(data->'controls') c where c->>'currency'=o->>'currency')) then
   raise exception using errcode='55000',message='CASH_CURRENCY_MAPPING_REQUIRED';end if;
  with opening as(select x->>'currency' currency,sum((x->>'amount')::numeric) balance from jsonb_array_elements(data->'controls') x group by x->>'currency'),
   flows as(select o->>'currency' currency,coalesce((s#>>array['parameters','overrides',o->>'id','dueDate'])::date,(o->>'dueDate')::date) due_date,
    case when o->>'provider'='receivables' then coalesce((s#>>array['parameters','overrides',o->>'id','remainingUnits'])::numeric/1000000,(o->>'amount')::numeric) else 0 end inflow,
    case when o->>'provider'='payables' then coalesce((s#>>array['parameters','overrides',o->>'id','remainingUnits'])::numeric/1000000,(o->>'amount')::numeric) else 0 end outflow
    from jsonb_array_elements(data->'obligations') o),
   days as(select c.currency,c.balance,d::date bucket_date from opening c cross join generate_series(start_date,end_date-1,interval '1 day') d
    where filters->>'currency' is null or c.currency=filters->>'currency'),
   buckets as(select d.currency,d.bucket_date,d.balance,coalesce(sum(f.inflow),0) inflow,coalesce(sum(f.outflow),0) outflow
    from days d left join flows f on f.currency=d.currency and f.due_date=d.bucket_date group by d.currency,d.bucket_date,d.balance)
  select coalesce(jsonb_agg(jsonb_build_object('date',bucket_date::text,'currency',currency,'inflow',inflow::text,'outflow',outflow::text,'balance',total::text) order by currency,bucket_date),'[]'),count(*) into rows,n
  from(select currency,bucket_date,inflow,outflow,balance+sum(inflow-outflow) over(partition by currency order by bucket_date) total from buckets order by currency,bucket_date limit 10001) projected;
  if n>10000 then raise exception using errcode='54000',message='REPORT_EXPORT_ROW_LIMIT';end if;
  meta:=jsonb_build_object('as_of',data->>'horizonStart','generated_at',data->>'recordedThrough','horizon_start',data->>'horizonStart','horizon_end',data->>'horizonEnd',
   'calculation','dated_transaction_cash_ar_and_ap.v2','source_basis_hash',s->>'sourceHash','scenario_parameters',s->'parameters','exclusions',data->'exclusions');
 end if;
 meta:=meta||jsonb_build_object('id',i,'version',1,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'actor_id',auth.uid(),'working_branch_id',b,
  'source_type',resource,'source_id',i,'section',section,'filters',filters,'row_count',jsonb_array_length(rows));
 f:=jsonb_build_object('version',1,'metadata',meta,'rows',rows);
 if octet_length(f::text)>8388608 then raise exception using errcode='54000',message='REPORT_EXPORT_EVIDENCE_LIMIT';end if;return f;
end $$;
revoke all on function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated;
create function api.wave5_export_reopen(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_export_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare job core.export_jobs%rowtype;data jsonb;begin
 select * into job from core.export_jobs where tenant_id=p_tenant_id and id=p_export_id and actor_id=auth.uid();
 if not found or job.filters->>'legal_entity_id' is distinct from p_legal_entity_id::text or job.filters->>'working_branch_id' is distinct from p_branch_id::text
  or job.filters->>'source_type' not in('w5_pipeline','w5_cash') then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 data:=finance.report_export_document(p_tenant_id,p_legal_entity_id,p_branch_id,job.filters->>'source_type',(job.filters->>'source_id')::uuid,job.filters->>'section',job.filters->'filters');
 if encode(extensions.digest(data::text,'sha256'),'hex')<>job.filters->>'source_hash' then raise exception using errcode='55000',message='EXPORT_BASIS_CHANGED';end if;
 return jsonb_build_object('id',job.id,'canonicalText',data::text,'sourceHash',job.filters->>'source_hash','fileHash',job.filters->>'file_sha256',
  'preparedAt',job.filters->>'prepared_at','format',job.file_format,'fileName',job.file_name);end $$;
revoke all on function api.wave5_export_reopen(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_export_reopen(uuid,uuid,uuid,uuid) to authenticated;

-- UNAPPLIED. Requires the separately owned Wave 3 financial-statement provider.
-- No classifications, financial publications, entitlements or roles are seeded.
insert into core.permissions(code,module,description,privileged) values
 ('finance.classifications.approve','finance','Approve immutable statement account classifications',true)
 on conflict(code) do nothing;
create table analytics.statement_classifications(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 profit_loss_id uuid not null,balance_sheet_id uuid not null,labels jsonb not null,
 reason text not null check(length(trim(reason)) between 8 and 500),actor_id uuid not null references auth.users(id),
 profit_loss_hash text not null,balance_sheet_hash text not null,created_at timestamptz not null default statement_timestamp(),
 unique(tenant_id,id),foreign key(tenant_id,profit_loss_id) references finance.financial_reports(tenant_id,id),
 foreign key(tenant_id,balance_sheet_id) references finance.financial_reports(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(jsonb_typeof(labels)='object' and octet_length(labels::text)<=1048576),
 check(profit_loss_hash ~ '^[a-f0-9]{64}$' and balance_sheet_hash ~ '^[a-f0-9]{64}$'));
alter table analytics.statement_classifications enable row level security;
alter table analytics.statement_classifications force row level security;
revoke all on analytics.statement_classifications from public,anon,authenticated;
create trigger immutable before update or delete on analytics.statement_classifications for each row execute function analytics.immutable_evidence();
create index statement_classification_scope on analytics.statement_classifications(tenant_id,legal_entity_id,branch_id,id);

create function analytics.statement_access(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or e is null or b is null then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform core.wave3_require_scope(t,'analytics.view',e,b);
 -- The Wave 3 statements are entity-wide, even when requested at a branch.
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';end if;
end $$;

create function analytics.statement_bundle(t uuid,e uuid,b uuid,p uuid,q uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare pl finance.financial_reports%rowtype;bs finance.financial_reports%rowtype;k text;begin
 perform analytics.statement_access(t,e,b);
 select * into pl from finance.financial_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=p and kind='profit_loss';
 select * into bs from finance.financial_reports where tenant_id=t and legal_entity_id=e and requested_branch_id=b and id=q and kind='balance_sheet';
 if pl.id is null or bs.id is null or pl.summary->>'status'<>'generated' or bs.summary->>'status'<>'generated'
  or pl.summary->>'version'<>'1' or bs.summary->>'version'<>'1' then
  raise exception using errcode='42501',message='STATEMENT_BUNDLE_REQUIRED';end if;
 foreach k in array array['tenant_id','legal_entity_id','branch_id','period_id','period_start','period_end','as_of','base_currency_code'] loop
  if pl.summary->k is distinct from bs.summary->k then raise exception using errcode='22023',message='STATEMENT_BUNDLE_MISMATCH';end if;
 end loop;
 if pl.evidence->'journals' is distinct from bs.evidence->'journals'
  or jsonb_array_length(pl.evidence->'accounts')<>jsonb_array_length(bs.evidence->'accounts')
  or exists(select 1 from jsonb_array_elements(pl.evidence->'accounts') a full join jsonb_array_elements(bs.evidence->'accounts') z
   on a->>'account_id'=z->>'account_id' where a is null or z is null or a->>'account_type' is distinct from z->>'account_type') then
  raise exception using errcode='22023',message='STATEMENT_SOURCE_MISMATCH';end if;
 return jsonb_build_object('profitLoss',pl.evidence,'balanceSheet',bs.evidence,
  'profitLossHash',encode(extensions.digest(pl.evidence::text,'sha256'),'hex'),
  'balanceSheetHash',encode(extensions.digest(bs.evidence::text,'sha256'),'hex'));
end $$;
revoke all on function analytics.statement_access(uuid,uuid,uuid),analytics.statement_bundle(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;

create function api.wave5_classification_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.statement_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'finance.classifications.approve',p_legal_entity_id,p_branch_id);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='APPROVAL_REQUIRED';end if;
 return auth.uid();end $$;

create function api.wave5_classification_publish(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_profit_loss_id uuid,p_balance_sheet_id uuid,p_labels jsonb,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare bundle jsonb;a jsonb;tag text;h text;receipt jsonb;payload jsonb;begin
 perform api.wave5_classification_authorize(p_tenant_id,p_legal_entity_id,p_branch_id);
 bundle:=analytics.statement_bundle(p_tenant_id,p_legal_entity_id,p_branch_id,p_profit_loss_id,p_balance_sheet_id);
 if p_id is null or jsonb_typeof(p_labels) is distinct from 'object' or octet_length(p_labels::text)>1048576
  or p_reason is null or length(trim(p_reason)) not between 8 and 500
  or (select count(*) from jsonb_object_keys(p_labels))<>jsonb_array_length(bundle#>'{profitLoss,accounts}') then
  raise exception using errcode='22023',message='CLASSIFICATION_COVERAGE_REQUIRED';end if;
 for a in select * from jsonb_array_elements(bundle#>'{profitLoss,accounts}') loop
  tag:=p_labels->>(a->>'account_id');
  if jsonb_typeof(p_labels->(a->>'account_id')) is distinct from 'string' or tag is null or
   not(case a->>'account_type' when 'asset' then tag in('current_asset','inventory','noncurrent_asset')
    when 'liability' then tag in('current_liability','noncurrent_liability') when 'revenue' then tag='revenue'
    when 'expense' then tag in('cost_of_sales','operating_expense') when 'equity' then tag='equity' else false end) then
   raise exception using errcode='22023',message='CLASSIFICATION_TYPE_MISMATCH';end if;
 end loop;
 payload:=jsonb_build_object('profitLossId',p_profit_loss_id,'balanceSheetId',p_balance_sheet_id,'labels',p_labels,'reason',p_reason,
  'profitLossHash',bundle->>'profitLossHash','balanceSheetHash',bundle->>'balanceSheetHash');
 h:=core.wave3_request_hash('analytics.classifications.publish',p_id,p_tenant_id,p_legal_entity_id,p_branch_id,payload,null);
 receipt:=core.wave3_replay(p_tenant_id,'analytics.classifications.publish',p_id,p_id,h);
 if receipt is not null then return receipt;end if;
 insert into analytics.statement_classifications values(p_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_profit_loss_id,p_balance_sheet_id,
  p_labels,p_reason,auth.uid(),bundle->>'profitLossHash',bundle->>'balanceSheetHash',statement_timestamp());
 return core.wave3_finish_command(p_tenant_id,'analytics.classifications.publish',p_id,'statement_classification',p_id,p_id,h,null,
  jsonb_build_object('id',p_id,'version','1','profitLossHash',bundle->>'profitLossHash','balanceSheetHash',bundle->>'balanceSheetHash'),p_legal_entity_id,p_branch_id);
end $$;

create function analytics.exact_named_ratio(n numeric,d numeric) returns jsonb
language sql immutable set search_path='' as $$select jsonb_build_object('numerator',n::text,'denominator',d::text,
 'exactValue',case when d>0 then round(n/d,6)::text else null end,
 'unavailableReason',case when d=0 then 'ZERO_DENOMINATOR' when d<0 then 'NEGATIVE_DENOMINATOR' end)$$;

create function api.wave5_financial_ratios(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_profit_loss_id uuid,p_balance_sheet_id uuid,p_classification_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare bundle jsonb;pl jsonb;bs jsonb;c analytics.statement_classifications%rowtype;ratios jsonb;result jsonb;
 revenue numeric;profit numeric;assets numeric;liabilities numeric;equity numeric;ca numeric;inventory numeric;cl numeric;cogs numeric;begin
 bundle:=analytics.statement_bundle(p_tenant_id,p_legal_entity_id,p_branch_id,p_profit_loss_id,p_balance_sheet_id);
 pl:=bundle#>'{profitLoss,summary}';bs:=bundle#>'{balanceSheet,summary}';
 revenue:=(pl->>'revenue')::numeric;profit:=(pl->>'net_profit')::numeric;
 assets:=(bs->>'assets')::numeric;liabilities:=(bs->>'liabilities')::numeric;equity:=(bs->>'equity')::numeric+(bs->>'current_earnings')::numeric;
 ratios:=jsonb_build_object('net_profit_margin',analytics.exact_named_ratio(profit,revenue),
  'liabilities_to_assets',analytics.exact_named_ratio(liabilities,assets),'assets_to_equity',analytics.exact_named_ratio(assets,equity));
 if p_classification_id is not null then
  select * into c from analytics.statement_classifications where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and id=p_classification_id and profit_loss_id=p_profit_loss_id and balance_sheet_id=p_balance_sheet_id;
  if not found or c.profit_loss_hash is distinct from bundle->>'profitLossHash' or c.balance_sheet_hash is distinct from bundle->>'balanceSheetHash' then
   raise exception using errcode='42501',message='CLASSIFICATION_PUBLICATION_REQUIRED';end if;
  select coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id') in('current_asset','inventory')),0),
   coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id')='inventory'),0),
   coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id')='current_liability'),0)
   into ca,inventory,cl from jsonb_array_elements(bundle#>'{balanceSheet,accounts}') a;
  select coalesce(sum((a->>'amount')::numeric) filter(where c.labels->>(a->>'account_id')='cost_of_sales'),0)
   into cogs from jsonb_array_elements(bundle#>'{profitLoss,accounts}') a;
  ratios:=ratios||jsonb_build_object('current_ratio',analytics.exact_named_ratio(ca,cl),
   'quick_ratio',analytics.exact_named_ratio(ca-inventory,cl),'gross_profit_margin',analytics.exact_named_ratio(revenue-cogs,revenue));
 end if;
 result:=jsonb_build_object('contractRevision',1,'formulaVersion',1,'scope',jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
  'profitLossId',p_profit_loss_id,'balanceSheetId',p_balance_sheet_id,'classificationId',p_classification_id,
  'profitLossHash',bundle->>'profitLossHash','balanceSheetHash',bundle->>'balanceSheetHash',
  'currency',pl->>'base_currency_code','periodStart',pl->>'period_start','asOf',pl->>'as_of','ratios',ratios);
 return jsonb_build_object('canonicalText',result::text,'sourceHash',encode(extensions.digest(result::text,'sha256'),'hex'));
end $$;
revoke all on function analytics.exact_named_ratio(numeric,numeric),api.wave5_classification_authorize(uuid,uuid,uuid),
 api.wave5_classification_publish(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),api.wave5_financial_ratios(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_classification_authorize(uuid,uuid,uuid),api.wave5_classification_publish(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),
 api.wave5_financial_ratios(uuid,uuid,uuid,uuid,uuid,uuid) to authenticated;

-- Synthetic namespace; included after the candidate inside one strict rollback.
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table w5_tap(message text);
create function pg_temp.fid(s text) returns uuid language sql immutable as $$select md5('wave5-process-20261006:'||s)::uuid$$;
create function pg_temp.actor(s text) returns void language plpgsql as $$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(s),'role','authenticated','aal','aal2')::text,true);end$$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.fid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@w5.jentra.test','',now(),now(),now()
from unnest(array['owner','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('t'),'Synthetic Wave 5','wave5-process-synthetic',pg_temp.fid('owner'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
values(pg_temp.fid('e'),pg_temp.fid('t'),'Synthetic Analytics','W5SYN','LKR','UTC',2,pg_temp.fid('owner'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),'Synthetic Branch '||x,'W5'||upper(x),pg_temp.fid('owner') from unnest(array['b','b2']) x;
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.fid('t'),'starter','trialing',5,now()+interval '1 day');
-- The existing plan is changed only within this rollback transaction.
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('starter','analytics',true)
on conflict(plan_code,entitlement_code) do update set enabled=true;
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.fid(x||'.member'),pg_temp.fid('t'),pg_temp.fid(x),'active' from unnest(array['owner','reader']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.fid(x||'.role'),pg_temp.fid('t'),x,x,false from unnest(array['owner','reader']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('t'),pg_temp.fid(x||'.role'),p from unnest(array['owner','reader']) x
cross join unnest(array['analytics.view','workflow.process.view','crm.opportunities.view']) p;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('t'),pg_temp.fid(x||'.member'),pg_temp.fid(x||'.role'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('owner')
from unnest(array['owner','reader']) x;
insert into crm.opportunities(id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,currency_code,created_by,updated_by,
 expected_close_date,request_id,command_id,correlation_id,client_timestamp)
values(pg_temp.fid('o'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'W5-O','Synthetic prospect',pg_temp.fid('owner'),'LKR',pg_temp.fid('owner'),pg_temp.fid('owner'),
 '2026-10-01',pg_temp.fid('o'),pg_temp.fid('o'),pg_temp.fid('o'),'2026-09-01');
insert into workflow.process_events(id,tenant_id,legal_entity_id,branch_id,document_type,document_id,to_status,actor_id,owner_id,
 entered_at,completed_at,request_id,command_id,correlation_id,created_at,reason)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'crm_opportunity',pg_temp.fid('o'),'qualified',
 pg_temp.fid('reader'),pg_temp.fid('reader'),'2026-09-01T00:00:00Z',
 case x when 'zero' then '2026-09-01T00:00:00Z'::timestamptz when 'closed' then '2026-09-01T00:00:00.000001Z'::timestamptz else null end,
 pg_temp.fid(x),pg_temp.fid(x),pg_temp.fid(x),'2026-09-02T00:00:00Z','PRIVATE TEST REASON'
from unnest(array['zero','closed','open']) x;
create function pg_temp.read(b text default 'b', ending timestamptz default '2026-10-01T00:00:00Z') returns jsonb language sql as $$
select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid(b),'2026-09-01T00:00:00Z',ending,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z')$$;
select pg_temp.actor('owner');
create temporary table w5_results(name text primary key,result jsonb);
insert into w5_tap select is(api.analytics_process_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),pg_temp.fid('owner'),'Recovery authorization returns actual authenticated actor');
insert into w5_results values('snapshot',pg_temp.read());
insert into w5_tap select is((select result#>>'{source,sourceCount}' from w5_results),'3','Complete authorized cohort captured');
insert into w5_tap select is((select result#>>'{source,complete}' from w5_results),'true','Complete manifest advertised only after bounded query');
insert into w5_tap select ok((select result#>>'{source,sourceManifestHash}' ~ '^[0-9a-f]{64}$' from w5_results),'Canonical SHA256 captured');
insert into w5_tap select ok((select result::text not like '%PRIVATE TEST REASON%' and result::text not like '%actorId%' and result::text not like '%ownerId%' from w5_results),'Private reason and identities omitted');
insert into w5_tap select is((select count(*) from jsonb_array_elements((select result->'observations' from w5_results)) x where x->>'completedAt'='2026-09-01T00:00:00.000001Z'),1::bigint,'Exact microsecond transport');
insert into w5_tap select is((pg_temp.read()->'source'->>'sourceManifestHash'),(select result#>>'{source,sourceManifestHash}' from w5_results),'Repeated basis digest stable');
insert into w5_tap select is((api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))->>'documentId'),pg_temp.fid('o')::text,'Drill-through rechecks actual source');
insert into w5_tap select throws_ok($$select pg_temp.read('b2')$$,'42501','Permission denied or multi-factor authentication required.','Foreign branch denied');
insert into w5_tap select throws_ok($$select pg_temp.read('b','2026-09-01')$$,'22023','VALIDATION_ERROR','Empty range rejected');
insert into w5_tap select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2024-01-01','2026-01-01','2026-01-01','2026-01-01')$$,'54000','LIMIT_EXCEEDED','366-day bound enforced');
insert into w5_tap select throws_ok($$select api.analytics_process_snapshot(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-01','2026-10-01','2026-10-01','2099-01-01')$$,'22023','VALIDATION_ERROR','Future recorded cutoff rejected');
delete from core.role_permissions where role_id=pg_temp.fid('reader.role') and permission_code='crm.opportunities.view';
select pg_temp.actor('reader');
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','PERMISSION_DENIED','Own/owned event is insufficient without source permission');
insert into w5_tap select throws_ok($$select api.analytics_process_event(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('zero'))$$,'42501','PERMISSION_DENIED','Revoked source blocks drill-through');
select pg_temp.actor('outsider');
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','Permission denied or multi-factor authentication required.','Foreign member denied before aggregate');
select set_config('request.jwt.claims','{}',true);
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','AUTH_REQUIRED','Anonymous denied');
select pg_temp.actor('owner');
update billing.plan_entitlements set enabled=false where plan_code='starter' and entitlement_code='analytics';
insert into w5_tap select throws_ok($$select pg_temp.read()$$,'42501','ENTITLEMENT_REQUIRED','Missing entitlement denies aggregate');
update billing.plan_entitlements set enabled=true where plan_code='starter' and entitlement_code='analytics';
insert into w5_tap select ok(not has_function_privilege('anon','api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)','execute'),'Anonymous cannot execute provider');
insert into w5_tap select ok(not has_function_privilege('authenticated','analytics.process_access(uuid,uuid,uuid)','execute'),'Private helper denied');
insert into w5_tap select throws_ok($test$do $body$begin
 insert into workflow.process_events(id,tenant_id,legal_entity_id,branch_id,document_type,document_id,to_status,actor_id,
  entered_at,completed_at,request_id,command_id,correlation_id,created_at)
 select pg_temp.fid('bound.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'crm_opportunity',pg_temp.fid('o'),'qualified',pg_temp.fid('owner'),
  '2026-09-01','2026-09-02',pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),pg_temp.fid('bound.'||i),'2026-09-02'
 from generate_series(1,9998) i;
 perform pg_temp.read();
end $body$$test$,'54000','LIMIT_EXCEEDED','10001 rows fail atomically without truncated totals');
insert into w5_tap select is((pg_temp.read()#>>'{source,sourceCount}'),'3','Excess-fixture failure leaves original cohort intact');

-- Follows installed process fixture; all rows and candidates roll back.
select pg_temp.actor('owner');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.view'),
 (pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.receivables.view'),
 (pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.payments.manage') on conflict do nothing;
-- Rollback-only shape shim for the separately owned Wave 3 correction source.
-- The real table is still uninstalled in the live project and is not created by W5.
create table if not exists finance.allocation_reversals(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 allocation_id uuid not null unique,posting_date date not null,reason text not null,
 journal_entry_id uuid,source_snapshot jsonb not null,request_id uuid not null,command_id uuid not null,
 created_by uuid not null,created_at timestamptz not null default statement_timestamp());
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
 select pg_temp.fid('cash.'||x),pg_temp.fid('t'),pg_temp.fid('e'),upper(x),'Synthetic '||x,
  case x when 'cash' then 'asset' else 'revenue' end,case x when 'cash' then 'debit' else 'credit' end,auth.uid(),auth.uid()
 from unnest(array['cash','offset']) x;
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by,updated_at)
 values(pg_temp.fid('cash.control'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'SYN-CASH','Synthetic cash','cash',pg_temp.fid('cash.cash'),'LKR',auth.uid(),auth.uid(),current_date-2);
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 values(pg_temp.fid('cash.period'),pg_temp.fid('t'),pg_temp.fid('e'),'Synthetic cash period',current_date-30,current_date+30,auth.uid(),auth.uid());
insert into finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,posting_date,source_type,source_id,currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid('cash.journal'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.period'),'SYN-CASH',current_date-1,'synthetic_cash_fixture',pg_temp.fid('cash.journal'),'LKR','LKR',1,
  pg_temp.fid('cash.journal'),pg_temp.fid('cash.journal'),pg_temp.fid('cash.journal'),auth.uid());
insert into finance.journal_lines(id,tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,currency_code,transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
 select pg_temp.fid('cash.line.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.journal'),case x when 'cash' then 1 else 2 end,pg_temp.fid('cash.'||x),'LKR',
  case x when 'cash' then 100 else 0 end,case x when 'offset' then 100 else 0 end,case x when 'cash' then 100 else 0 end,case x when 'offset' then 100 else 0 end,current_date-1,auth.uid()
 from unnest(array['cash','offset']) x;
update finance.journal_entries set status='posted' where id=pg_temp.fid('cash.journal');
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
 values(pg_temp.fid('cash.party'),pg_temp.fid('t'),'SYN-CASH','Synthetic cash customer','Synthetic cash customer','customer',auth.uid(),auth.uid());
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
 values(pg_temp.fid('cash.supplier'),pg_temp.fid('t'),'SYN-CASH-SUP','Synthetic cash supplier','Synthetic cash supplier','supplier',auth.uid(),auth.uid());
insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
 original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 select pg_temp.fid('cash.item.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'AR',pg_temp.fid('cash.party'),'synthetic_cash_'||x,pg_temp.fid('cash.item.'||x),'SYN-'||x,'LKR','LKR',1,
  case x when 'invoice' then 500 else -200 end,case x when 'invoice' then 500 else -200 end,current_date-1,current_date+1,pg_temp.fid('cash.journal'),pg_temp.fid('cash.item.'||x),pg_temp.fid('cash.item.'||x),pg_temp.fid('cash.item.'||x),auth.uid()
 from unnest(array['invoice','receipt']) x;
insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
 original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 select pg_temp.fid('cash.ap.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'AP',pg_temp.fid('cash.supplier'),'synthetic_cash_ap_'||x,
  pg_temp.fid('cash.ap.'||x),'SYN-AP-'||x,'LKR','LKR',1,case x when 'active_bill' then 150 else 80 end,case x when 'active_bill' then 150 else 80 end,
  current_date-3,current_date+2,pg_temp.fid('cash.journal'),pg_temp.fid('cash.ap.'||x),pg_temp.fid('cash.ap.'||x),pg_temp.fid('cash.ap.'||x),auth.uid()
 from unnest(array['active_bill','reversed_bill']) x;
insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
 original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 select pg_temp.fid('cash.ap.credit.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'AP',pg_temp.fid('cash.supplier'),'synthetic_cash_ap_credit_'||x,
  pg_temp.fid('cash.ap.credit.'||x),'SYN-AP-CREDIT-'||x,'LKR','LKR',1,case x when 'active' then -40 else -20 end,case x when 'active' then -40 else -20 end,
  current_date-3,current_date+2,pg_temp.fid('cash.journal'),pg_temp.fid('cash.ap.credit.'||x),pg_temp.fid('cash.ap.credit.'||x),pg_temp.fid('cash.ap.credit.'||x),auth.uid()
 from unnest(array['active','reversed']) x;
insert into finance.open_item_allocations(tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,source_amount,transaction_amount,source_base_amount,target_base_amount,posting_date,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.item.receipt'),pg_temp.fid('cash.item.invoice'),200,200,200,200,current_date-1,pg_temp.fid('cash.allocation'),pg_temp.fid('cash.allocation'),pg_temp.fid('cash.allocation'),auth.uid());
insert into finance.open_item_allocations(id,tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,source_amount,transaction_amount,source_base_amount,target_base_amount,posting_date,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid('cash.ap.alloc.active'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.ap.credit.active'),pg_temp.fid('cash.ap.active_bill'),40,40,40,40,current_date-2,
  pg_temp.fid('cash.ap.alloc.active'),pg_temp.fid('cash.ap.alloc.active'),pg_temp.fid('cash.ap.alloc.active'),auth.uid()),
 (pg_temp.fid('cash.ap.alloc.reversed'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.ap.credit.reversed'),pg_temp.fid('cash.ap.reversed_bill'),20,20,20,20,current_date-2,
  pg_temp.fid('cash.ap.alloc.reversed'),pg_temp.fid('cash.ap.alloc.reversed'),pg_temp.fid('cash.ap.alloc.reversed'),auth.uid());
insert into finance.allocation_reversals(id,tenant_id,legal_entity_id,branch_id,allocation_id,posting_date,reason,source_snapshot,request_id,command_id,created_by)
 values(pg_temp.fid('cash.ap.reversal'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.ap.alloc.reversed'),current_date-1,
  'Synthetic rollback reversal',jsonb_build_object('allocation_id',pg_temp.fid('cash.ap.alloc.reversed')),pg_temp.fid('cash.ap.reversal'),pg_temp.fid('cash.ap.reversal'),auth.uid());
create temporary table w5_cash as select api.wave5_cash_basis(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 current_date,current_date+30,statement_timestamp()) basis;
insert into w5_tap select is(((select basis->>'canonicalText' from w5_cash)::jsonb)->>'definition','dated_transaction_cash_ar_and_ap.v2','Cash authority names dated transaction, AR and AP basis');
insert into w5_tap select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{controls,0,amount}','100.000000','Dated cash control reconciles to posted journal transactions');
insert into w5_tap select is((select x->>'amount' from w5_cash,jsonb_array_elements((basis->>'canonicalText')::jsonb->'obligations') x where x->>'id'=pg_temp.fid('cash.item.invoice')::text),
 '300.000000','AR residual subtracts one immutable allocation without counting receipt as another inflow');
insert into w5_tap select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{completeProviders,2}','payables','Dated provider exposes AP only under payable read authority');
insert into w5_tap select is((select x->>'amount' from w5_cash,jsonb_array_elements((basis->>'canonicalText')::jsonb->'obligations') x where x->>'id'=pg_temp.fid('cash.ap.active_bill')::text),'110.000000','AP residual subtracts committed payment allocations');
insert into w5_tap select is((select x->>'amount' from w5_cash,jsonb_array_elements((basis->>'canonicalText')::jsonb->'obligations') x where x->>'id'=pg_temp.fid('cash.ap.reversed_bill')::text),'80.000000','Reversed AP allocation is restored to remaining obligations');
insert into w5_tap select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{providerStatus,payroll}','missing_authoritative_due_date','Payroll stays unavailable without a due-date source');
insert into w5_tap select is(((select basis->>'canonicalText' from w5_cash)::jsonb)#>>'{providerStatus,project_reimbursements}','missing_authoritative_due_date','Project reimbursements stay unavailable without a due-date source');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='finance.payments.manage';
create temporary table w5_cash_without_ap as select api.wave5_cash_basis(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),current_date,current_date+30,statement_timestamp()) basis;
insert into w5_tap select is(((select basis->>'canonicalText' from w5_cash_without_ap)::jsonb)#>>'{providerStatus,payables}','permission_required','Payables are withheld when the current actor loses their scoped capability');
insert into w5_tap select is(jsonb_array_length((select basis->>'canonicalText' from w5_cash_without_ap)::jsonb->'obligations'),1,'Unauthorized AP rows are not returned to the receivables-only reader');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.payments.manage') on conflict do nothing;
insert into w5_tap select is(api.wave5_cash_authorize(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')),auth.uid(),'Cash recovery revalidates current actor');
insert into w5_tap select is(api.wave5_cash_save(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cashscenario'),(select basis->>'sourceHash' from w5_cash),
 jsonb_build_object('horizonStart',current_date::text,'horizonEnd',(current_date+30)::text,'recordedThrough',analytics.process_utc(statement_timestamp()),'overrides','{}'::jsonb))->>'version','1','Cash scenario stores immutable version with captured source hash');
insert into w5_tap select is(api.wave5_cash_get(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cashscenario'))->>'sourceHash',(select basis->>'sourceHash' from w5_cash),'Scenario reopens identical captured source evidence');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='finance.payments.manage';
insert into w5_tap select throws_ok($$select api.wave5_cash_get(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cashscenario'))$$,'42501','PERMISSION_DENIED','Scenario reopen rechecks payable permission for frozen AP evidence');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.payments.manage') on conflict do nothing;
insert into w5_tap select throws_ok($$update analytics.cash_scenario_revisions set parameters='{}'$$,'55000','IMMUTABLE_EVIDENCE','Scenario parameters cannot be overwritten');
insert into w5_tap select ok(not has_table_privilege('authenticated','analytics.cash_scenario_revisions','select'),'Scenario evidence denied to direct client reads');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.reports.export');
create temporary table w5_export as select api.report_export_preview(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'w5_cash',pg_temp.fid('cashscenario'),'buckets','{}') preview;
insert into w5_tap select is(((select preview->>'canonical_text' from w5_export)::jsonb)#>>'{rows,1,balance}','400.000000','Governed cash export calculates exact dated scenario buckets');
insert into w5_tap select is(((select preview->>'canonical_text' from w5_export)::jsonb)#>>'{metadata,source_basis_hash}',(select basis->>'sourceHash' from w5_cash),'Export preserves frozen calculation source hash');
-- SQL tests register metadata only. Dart codec tests separately verify actual
-- bytes; this placeholder artifact is never written or externally delivered.
create temporary table w5_export_payload as select jsonb_build_object('id',pg_temp.fid('exportjob'),'source_type','w5_cash','source_id',pg_temp.fid('cashscenario'),
 'section','buckets','filters','{}'::jsonb,'source_hash',preview->>'source_hash','file_format','csv','file_name','synthetic.csv','file_size','1','file_sha256',repeat('a',64),
 'prepared_at',analytics.process_utc(statement_timestamp()),'columns',jsonb_build_array('record_type')||
  (select jsonb_agg('report.'||key order by key) from(select jsonb_object_keys((preview->>'canonical_text')::jsonb->'metadata') key
   union select unnest(array['export_id','export_prepared_at','source_hash','file_format']))x)||
  (select jsonb_agg('data.'||key order by key) from(select distinct key from jsonb_array_elements((preview->>'canonical_text')::jsonb->'rows')r
   cross join lateral jsonb_object_keys(r)key)x)) payload from w5_export;
create temporary table w5_export_receipt as select api.record_report_export(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'),pg_temp.fid('exportjob'),statement_timestamp(),(select payload from w5_export_payload),0) result;
insert into w5_tap select is(api.record_report_export(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'),pg_temp.fid('exportjob'),statement_timestamp(),(select payload from w5_export_payload),0),
 (select result from w5_export_receipt),'Governed export registration retries its original audited metadata receipt');
insert into w5_tap select is(api.wave5_export_reopen(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'))->>'sourceHash',(select preview->>'source_hash' from w5_export),
 'Governed export reopens the captured source hash under current access');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='finance.reports.export';
insert into w5_tap select throws_ok($$select api.wave5_export_reopen(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('exportjob'))$$,
 '42501','Permission denied or multi-factor authentication required.','Export source is rechecked after export capability revocation');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.reports.export');
insert into w5_tap select is((api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),statement_timestamp(),statement_timestamp())
 ->>'canonicalText')::jsonb->>'complete','true','History adapter advertises complete bounded revisions');
insert into w5_tap select is(jsonb_array_length(((api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),statement_timestamp(),statement_timestamp())
 ->>'canonicalText')::jsonb)->'revisions'),1,'Installed immutable CRM revision selected');
insert into w5_tap select throws_ok($$select api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),now(),now()+interval '1 day')$$,
 '22023','VALIDATION_ERROR','Future history cutoff denied');
insert into w5_tap select ok(not has_function_privilege('anon','api.wave5_pipeline_history(uuid,uuid,uuid,timestamptz,timestamptz)','execute'),'Anonymous history read denied');
insert into w5_tap select throws_ok($test$do $body$begin
 insert into crm.pipeline_history select (jsonb_populate_record(null::crm.pipeline_history,to_jsonb(h)||
  jsonb_build_object('id',pg_temp.fid('historygap'),'version',3,'recorded_at',statement_timestamp()))).* from crm.pipeline_history h
  where h.tenant_id=pg_temp.fid('t') and h.entity_type='opportunity' limit 1;
 perform api.wave5_pipeline_history(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),statement_timestamp(),statement_timestamp());
end $body$$test$,'55000','HISTORY_REVISION_GAP','Historical revision gap fails instead of reporting plausible partial conversion or stage age');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'integrations.manage');
insert into intelligence_control.integration_hosts values('events.jentra.test');
create temporary table w5_registered as select api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'register',pg_temp.fid('subscription'),0,'{"url":"https://events.jentra.test/hook","keyRef":"synthetic/key1"}') result;
insert into w5_tap select is((select result->>'version' from w5_registered),'1','Scoped MFA integration registration persists revision');
insert into w5_tap select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'register',pg_temp.fid('subscription'),0,'{"url":"https://events.jentra.test/hook","keyRef":"synthetic/key1"}'),
 (select result from w5_registered),'Registration uncertain retry reopens original receipt');
insert into w5_tap select throws_ok($$select api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'register',pg_temp.fid('unreviewed'),0,'{"url":"https://unreviewed.jentra.test/hook","keyRef":"synthetic/key1"}')$$,
 '42501','UNREVIEWED_DESTINATION','Destination must have explicit server review');
insert into w5_tap select throws_ok($$select api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'rotate',pg_temp.fid('subscription'),2,'{"keyRef":"synthetic/key2"}')$$,'40001','CONFLICT','Key rotation checks exact version');
insert into w5_tap select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'rotate',pg_temp.fid('subscription'),1,'{"keyRef":"synthetic/key2"}')->>'keyVersion','2','Key rotation creates next server version');
insert into w5_tap select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'rotate',pg_temp.fid('subscription'),1,'{"keyRef":"synthetic/key2"}')->>'keyVersion','2','Repeated rotation does not create another key version');
insert into w5_tap select throws_ok($$update intelligence_control.integration_changes set action='rewrite'$$,'55000','IMMUTABLE_EVIDENCE','Registration and rotation evidence immutable');
insert into w5_tap select ok(not has_table_privilege('authenticated','intelligence_control.delivery_heads','select'),'Desktop cannot read worker state');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.wave5_delivery_worker(text,jsonb)','execute'),'Worker API denied to authenticated desktop');
update billing.plan_entitlements set enabled=true,numeric_limit=10 where plan_code='starter' and entitlement_code='quota.webhook.deliveries';
select api.freeze_pipeline_forecast(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('leaseforecast'),pg_temp.fid('leaseforecast'),
 statement_timestamp(),'2026-10-01','2026-11-01');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into w5_tap select is(api.wave5_delivery_worker('readiness','{}')->>'ready','true','Composed candidate worker contract readiness');
create temporary table w5_claimed as select api.wave5_delivery_worker('claim','{}') job;
insert into w5_tap select is((select job#>>'{event,type}' from w5_claimed),'analytics.forecast.frozen.v1','Committed outbox maps to allowlisted redacted event');
insert into w5_tap select is((select job->>'attempt' from w5_claimed),'1','Atomic claim creates first immutable lease attempt');
insert into w5_tap select is(api.wave5_delivery_worker('claim','{}'),null::jsonb,'Leased delivery cannot be claimed again');
select api.wave5_delivery_worker('outcome',(select jsonb_build_object('deliveryId',job->>'deliveryId','leaseId',job->>'leaseId','state','unknown','httpStatus',null) from w5_claimed));
insert into w5_tap select is(api.wave5_delivery_worker('claim','{}'),null::jsonb,'Unknown outcome is never automatically retried');
insert into w5_tap select is((select count(*) from intelligence_control.delivery_outcomes),1::bigint,'Outcome remains immutable recorded evidence');
select pg_temp.actor('owner');
insert into w5_tap select throws_ok($$select api.wave5_delivery_review(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select job->>'deliveryId' from w5_claimed)::uuid,pg_temp.fid('review'),'replay','Synthetic review reason')$$,
 '22023','OUTCOME_REVIEW_REQUIRED','Unknown delivery cannot use ordinary dead-letter replay');
insert into w5_tap select is(api.wave5_delivery_review(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select job->>'deliveryId' from w5_claimed)::uuid,pg_temp.fid('review'),'not_sent','Synthetic receiver confirmed no send')->>'state',
 'retry','MFA reviewed no-send decision authorizes original delivery retry');
select pg_temp.actor('owner');
insert into w5_tap select is(api.wave5_integration_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 'revoke',pg_temp.fid('subscription'),2,'{}')->>'enabled','false','Revocation disables current subscription');
insert into w5_tap select is((select count(*) from intelligence_control.integration_changes),3::bigint,'All three reviewed changes retain immutable history');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.wave5_external_worker(text,jsonb)','execute'),'External dispatcher is server-only');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.wave5_model_worker(text,jsonb)','execute'),'Model metering port is server-only');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into w5_tap select is(api.wave5_model_worker('readiness','{}')->>'contractRevision','1','Persistent model contract revision verified');
create temporary table w5_model_request as select jsonb_build_object('invocationId',pg_temp.fid('model'),
 'usageEventId',pg_temp.fid('modelusage'),'tenantId',pg_temp.fid('t'),'sourceId',f.id,'sourceHash',f.source_hash,
 'manifestHash',repeat('a',64),'maxTokens','20','policyRevision',1) payload from analytics.pipeline_forecasts f where f.tenant_id=pg_temp.fid('t') limit 1;
insert into w5_tap select is(api.wave5_model_worker('begin',(select payload from w5_model_request))->>'state','new','Model invocation is durably created before provider send');
insert into w5_tap select is(api.wave5_model_worker('begin',(select payload from w5_model_request))->>'state','pending','Restart cannot silently resend a pending invocation');
insert into w5_tap select throws_ok($$select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model'),'state','settled'))$$,
 '22023','MODEL_OUTCOME_MISMATCH','Missing trusted usage cannot settle a pending model request');
insert into w5_tap select throws_ok($$select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model'),'state','settled','tokens','21','suggestion','{}'::jsonb))$$,
 '22023','MODEL_OUTCOME_MISMATCH','Model tokens cannot exceed the original reservation');
select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model'),'state','unknown'));
insert into w5_tap select is(api.wave5_model_worker('begin',(select payload from w5_model_request))->>'state','unknown','Unknown provider result persists across independent calls');
insert into w5_tap select throws_ok($$update intelligence_control.model_outcomes set state='settled'$$,'55000','IMMUTABLE_EVIDENCE','Model outcome cannot be overwritten');
insert into w5_tap select is(api.wave5_model_worker('begin',(select jsonb_set(payload,'{invocationId}',to_jsonb(pg_temp.fid('model2')::text)) from w5_model_request))->>'state','new','Another reviewed invocation has its own durable identity');
select api.wave5_model_worker('outcome',jsonb_build_object('invocationId',pg_temp.fid('model2'),'state','settled','tokens','7',
 'suggestion',(select jsonb_build_object('commandCode','analytics.freeze_pipeline.v1','sourceId',f.id,'sourceHash',f.source_hash,
  'horizonStart',f.horizon_start::text,'horizonEnd',f.horizon_end::text) from analytics.pipeline_forecasts f where f.id=(select (payload->>'sourceId')::uuid from w5_model_request))));
insert into w5_tap select is(api.wave5_model_worker('begin',(select jsonb_set(payload,'{invocationId}',to_jsonb(pg_temp.fid('model2')::text)) from w5_model_request))->>'tokens','7',
 'Settled durable model outcome reopens only validated suggestion and trusted usage');
insert into w5_tap select is(api.wave5_subscription_due(null)->>'contractRevision','1','Synthetic scheduler reads a bounded server-only due queue');
insert into w5_tap select is(api.wave5_health_collect(pg_temp.fid('health'),pg_temp.fid('t'))->>'contractRevision','1','Operator probe collector reads durable queue and quota data');
create temporary table w5_collected_health as select api.wave5_health_collect(pg_temp.fid('health'),pg_temp.fid('t')) result;
insert into w5_tap select is(api.wave5_health_collect(pg_temp.fid('health'),pg_temp.fid('t')),(select result from w5_collected_health),'Health collection retry retains original observation times and quantities');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.wave5_health_collect(uuid,uuid)','execute'),'Desktop cannot publish purported worker health');
insert into w5_tap select ok(not has_function_privilege('authenticated','api.wave5_subscription_due(uuid)','execute'),'Desktop cannot enumerate cross-tenant activation work');
select pg_temp.actor('owner');
select api.wave5_credential_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'register',pg_temp.fid('credential'),
 jsonb_build_object('tokenHash',repeat('b',64),'startsAt',analytics.process_utc(statement_timestamp()-interval '1 minute'),
 'expiresAt',analytics.process_utc(statement_timestamp()+interval '1 day')));
select api.wave5_credential_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'register',pg_temp.fid('credential'),
 jsonb_build_object('tokenHash',repeat('b',64),'startsAt',analytics.process_utc(statement_timestamp()-interval '1 minute'),
 'expiresAt',analytics.process_utc(statement_timestamp()+interval '1 day')));
insert into w5_tap select is((select count(*) from intelligence_control.integration_credentials),1::bigint,'Credential registration retry creates one hashed credential');
insert into w5_tap select is((select count(*) from core.command_receipts where command_name='integration.credential.register'),1::bigint,'Credential registration has one stable audited command');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into w5_tap select is(api.wave5_external_worker('credential',jsonb_build_object('tokenHash',repeat('b',64)))#>>'{scope,tenantId}',
 pg_temp.fid('t')::text,'Credential hash resolves exact scoped authority');
update billing.plan_entitlements set enabled=true,numeric_limit=2 where plan_code='starter' and entitlement_code='quota.integration.commands';
create temporary table w5_external_request as select jsonb_build_object('tokenHash',repeat('b',64),'request',jsonb_build_object(
 'schemaVersion',1,'scope',jsonb_build_object('tenantId',pg_temp.fid('t'),'legalEntityId',pg_temp.fid('e'),'branchId',pg_temp.fid('b')),
 'commandCode','analytics.freeze_pipeline.v1','commandId',pg_temp.fid('external'),'idempotencyKey',pg_temp.fid('external'),
 'clientTimestamp',analytics.process_utc(statement_timestamp()),'horizonStart','2026-10-01','horizonEnd','2026-11-01')) payload;
insert into w5_tap select is(api.wave5_external_worker('reserve',(select payload from w5_external_request))->>'quotaReserved','true','External reservation reads live billing hard cap');
insert into w5_tap select is(api.wave5_external_worker('reserve',(select payload from w5_external_request))->>'throttleReserved','true','Identical retry reuses its atomic throttle slot');
insert into w5_tap select is((select reserved::text from intelligence_control.external_periods where tenant_id=pg_temp.fid('t')),'1','Duplicate reservation consumes one unit');
create temporary table w5_external_receipt as select api.wave5_external_worker('dispatch',(select payload from w5_external_request)) result;
insert into w5_tap select is(api.wave5_external_worker('dispatch',(select payload from w5_external_request)),(select result from w5_external_receipt),'Named dispatch restart reopens original domain receipt');
insert into w5_tap select is((select count(*) from core.command_receipts where tenant_id=pg_temp.fid('t') and command_id=pg_temp.fid('external')),1::bigint,'External stable identity creates one actual domain command');
insert into w5_tap select throws_ok($$select api.wave5_external_worker('credential',jsonb_build_object('tokenHash',repeat('c',64)))$$,
 '42501','INTEGRATION_ACCESS_DENIED','Unknown credential hash is non-disclosing');
select pg_temp.actor('owner');
select api.wave5_credential_manage(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'revoke',pg_temp.fid('credential'),'{}');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into w5_tap select throws_ok($$select api.wave5_external_worker('credential',jsonb_build_object('tokenHash',repeat('b',64)))$$,
 '42501','INTEGRATION_ACCESS_DENIED','Credential revocation precedes dispatch or reservation');
select pg_temp.actor('owner');

-- Statement authority is entity-wide; branch-only finance access is insufficient.
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
 values(pg_temp.fid('t'),pg_temp.fid('owner.member'),pg_temp.fid('owner.role'),pg_temp.fid('e'),null,auth.uid());
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'finance.classifications.approve');
select api.generate_financial_statement(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('pl'),statement_timestamp(),
 jsonb_build_object('id',pg_temp.fid('pl'),'kind','profit_loss','period_id',pg_temp.fid('cash.period'),'as_of',current_date),0);
select api.generate_financial_statement(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('bs'),pg_temp.fid('bs'),statement_timestamp(),
 jsonb_build_object('id',pg_temp.fid('bs'),'kind','balance_sheet','period_id',pg_temp.fid('cash.period'),'as_of',current_date),0);
create temporary table w5_ratios as select (api.wave5_financial_ratios(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('bs'),null)->>'canonicalText')::jsonb value;
insert into w5_tap select is((select value#>>'{ratios,net_profit_margin,exactValue}' from w5_ratios),'1.000000','Named ratio consumes matching immutable P&L and balance-sheet ledger evidence');
insert into w5_tap select throws_ok($$select api.wave5_classification_publish(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('classification'),
 pg_temp.fid('pl'),pg_temp.fid('bs'),'{}','Synthetic classification review')$$,'22023','CLASSIFICATION_COVERAGE_REQUIRED','Missing classifications cannot guess current assets or cost of sales');
create temporary table w5_classified as select api.wave5_classification_publish(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('classification'),
 pg_temp.fid('pl'),pg_temp.fid('bs'),jsonb_build_object(pg_temp.fid('cash.cash')::text,'current_asset',pg_temp.fid('cash.offset')::text,'revenue'),'Synthetic classification review') value;
insert into w5_tap select is(api.wave5_classification_publish(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('classification'),
 pg_temp.fid('pl'),pg_temp.fid('bs'),jsonb_build_object(pg_temp.fid('cash.cash')::text,'current_asset',pg_temp.fid('cash.offset')::text,'revenue'),'Synthetic classification review'),
 (select value from w5_classified),'Classification publication retry reuses original audited receipt');
insert into w5_tap select is(((api.wave5_financial_ratios(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('bs'),pg_temp.fid('classification'))->>'canonicalText')::jsonb)#>>'{ratios,current_ratio,unavailableReason}',
 'ZERO_DENOMINATOR','Classified ratio distinguishes zero denominator from a zero ratio');
insert into w5_tap select is(((api.wave5_financial_ratios(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('pl'),pg_temp.fid('bs'),pg_temp.fid('classification'))->>'canonicalText')::jsonb)#>>'{ratios,gross_profit_margin,exactValue}',
 '1.000000','Classified cost-of-sales population provides exact gross margin');
insert into w5_tap select throws_ok($$update analytics.statement_classifications set labels='{}'$$,'55000','IMMUTABLE_EVIDENCE','Governed classifications cannot mutate');
insert into w5_tap select ok(not has_table_privilege('authenticated','analytics.statement_classifications','select'),'Classifications have forced RLS and deny direct client reads');

-- A synthetic prospectively dated frozen basis exercises the complete realized
-- SQL mapping. This fixture is rolled back; it is not a real past prediction.
insert into analytics.pipeline_forecasts(id,tenant_id,legal_entity_id,branch_id,created_by,horizon_start,horizon_end,observed_at,canonical_text,source_hash,evidence)
 select pg_temp.fid('realized'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),auth.uid(),current_date-30,current_date,current_date-2,
  data::text,encode(extensions.digest(data::text,'sha256'),'hex'),data from (
  select jsonb_set(jsonb_set(jsonb_set(evidence,'{asOf}',to_jsonb(analytics.process_utc((current_date-2)::timestamptz))),
   '{horizonStart}',to_jsonb((current_date-30)::text)),'{horizonEnd}',to_jsonb(current_date::text)) data
  from analytics.pipeline_forecasts where tenant_id=pg_temp.fid('t') limit 1) f;
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'sales.returns.view');
insert into w5_tap select is(api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),statement_timestamp())->>'complete',
 'true','Closed realized mapping queries installed invoice/order/return contracts completely');

-- Bounded keyset pages keep every captured scope check; no receiver or key is provisioned.
insert into intelligence_control.integration_subscriptions(id,tenant_id,legal_entity_id,branch_id,created_by,url,hostname,key_ref)
 select pg_temp.fid('page.'||i),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),auth.uid(),
 'https://events.jentra.test/hook','events.jentra.test','synthetic/key1' from generate_series(1,51)i;
create temporary table w5_subscription_page as select api.wave5_integration_list(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b')) result;
insert into w5_tap select is(jsonb_array_length((select result->'subscriptions' from w5_subscription_page)),50,'Integration interactive page defaults to exactly 50 bounded rows');
insert into w5_tap select ok((select result->>'subscriptionNext' is not null from w5_subscription_page),'Integration page advertises an exact scoped continuation cursor');
create temporary table w5_subscription_next as select api.wave5_integration_list(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 (select (result->>'subscriptionNext')::uuid from w5_subscription_page),null) result;
insert into w5_tap select is(jsonb_array_length((select result->'subscriptions' from w5_subscription_next)),2,'Continuation returns the remainder without dropping scoped rows');
insert into w5_tap select ok(not exists(select 1 from jsonb_array_elements((select result->'subscriptions' from w5_subscription_page)) a
 join jsonb_array_elements((select result->'subscriptions' from w5_subscription_next)) b on a->>'id'=b->>'id'),'Keyset continuation never repeats a row');
select set_config('request.jwt.claims',jsonb_build_object('sub',auth.uid(),'role','authenticated','aal','aal1')::text,true);
insert into w5_tap select throws_ok($$select api.wave5_integration_list(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'))$$,
 '42501','APPROVAL_REQUIRED','Integration storage projection itself requires real MFA assurance');
select pg_temp.actor('owner');
insert into w5_tap select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('analytics','intelligence_control') and c.relkind='r'),30::bigint,'Composed Wave 5 adds fifteen tables alongside the fifteen installed tables');
insert into w5_tap select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('analytics','intelligence_control') and c.relkind='r' and (not c.relrowsecurity or not c.relforcerowsecurity)),
 'Every installed and candidate Wave 5 table enables and forces RLS');
insert into w5_tap select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('analytics','intelligence_control') and c.relkind='r' and
 (has_table_privilege('authenticated',c.oid,'select,insert,update,delete') or has_table_privilege('anon',c.oid,'select,insert,update,delete'))),
 'All thirty Wave 5 tables deny direct client table access');

-- Nonempty realized-provider fixtures only; composed inside strict ROLLBACK.
-- Uses the installed quotation snapshot/header/line schema. These records are
-- synthetic projections, not real posted-command/MFA acceptance evidence.
select pg_temp.actor('owner');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'sales.quotations.view') on conflict do nothing;
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
 values(pg_temp.fid('realized.warehouse'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'Synthetic realized warehouse','SYN-REAL',auth.uid());
insert into crm.opportunities(id,tenant_id,legal_entity_id,branch_id,code,prospect_name,owner_id,currency_code,created_by,updated_by,
 expected_close_date,request_id,command_id,correlation_id,client_timestamp)
 values(pg_temp.fid('realized.other.opportunity'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'SYN-OTHER-REAL','Synthetic other cohort',auth.uid(),'LKR',auth.uid(),auth.uid(),
 current_date-1,pg_temp.fid('realized.other.opportunity'),pg_temp.fid('realized.other.opportunity'),pg_temp.fid('realized.other.opportunity'),statement_timestamp());
insert into sales.quotations(id,tenant_id,legal_entity_id,branch_id,document_number,customer_id,opportunity_id,quotation_date,valid_until,
 currency_code,base_currency_code,exchange_rate,rate_date,salesperson_id,request_id,command_id,correlation_id,client_timestamp,created_by,updated_by)
 select pg_temp.fid('realized.quote.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'SYN-REAL-'||x,pg_temp.fid('cash.party'),
 case x when 'cohort' then pg_temp.fid('o') else pg_temp.fid('realized.other.opportunity') end,current_date-5,current_date+5,
 'LKR','LKR',1,current_date-5,auth.uid(),pg_temp.fid('realized.quote.'||x),pg_temp.fid('realized.quote.'||x),pg_temp.fid('realized.quote.'||x),current_date-5,auth.uid(),auth.uid()
 from unnest(array['cohort','other']) x;
-- This is the same top-level quotation projection captured by the installed
-- submit/convert producers. Do not invent a mutable current-CRM mapping.
insert into sales.sales_orders(id,tenant_id,legal_entity_id,branch_id,source_quotation_id,source_quotation_revision,source_snapshot,
 customer_id,order_date,promised_date,warehouse_id,currency_code,base_currency_code,exchange_rate,rate_date,salesperson_id,
 request_id,command_id,correlation_id,client_timestamp,created_by,updated_by)
 select pg_temp.fid('realized.order.'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized.quote.'||x),1,
 sales.quotation_entity(pg_temp.fid('realized.quote.'||x)),pg_temp.fid('cash.party'),current_date-4,current_date-1,pg_temp.fid('realized.warehouse'),
 'LKR','LKR',1,current_date-4,auth.uid(),pg_temp.fid('realized.order.'||x),pg_temp.fid('realized.order.'||x),pg_temp.fid('realized.order.'||x),current_date-4,auth.uid(),auth.uid()
 from unnest(array['cohort','other']) x;
create function pg_temp.realized_header(n text,k text,o uuid,d date,amount numeric,p timestamptz default null) returns void
 language plpgsql as $$declare rel text:=case k when 'invoice' then 'sales_invoices' else 'sales_returns' end;begin
 execute format('insert into sales.%I(id,tenant_id,legal_entity_id,branch_id,customer_id,document_date,due_date,currency_code,base_currency_code,exchange_rate,rate_date,
 rounding_scale,sales_order_id,grand_total,base_total,request_id,command_id,correlation_id,client_timestamp,created_by,updated_by,created_at)
 values($1,$2,$3,$4,$5,$6,$6,''LKR'',''LKR'',1,$6,6,$7,$8,$8,$1,$1,$1,$9,$10,$10,$9)',rel)
 using pg_temp.fid('realized.'||n),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('cash.party'),d,o,amount,
 coalesce(p,current_date-1)-interval '1 minute',auth.uid();
 if n='invoice' then
  insert into sales.sales_invoice_lines(id,tenant_id,legal_entity_id,branch_id,document_id,line_number,description,quantity,base_quantity,line_total,snapshot,created_by)
   values(pg_temp.fid('realized.invoice.line'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized.invoice'),1,'Synthetic realized source',1,1,amount,'{}',auth.uid());
 elsif k='return' then
  insert into sales.sales_return_lines(id,tenant_id,legal_entity_id,branch_id,document_id,line_number,description,quantity,base_quantity,line_total,sales_invoice_line_id,snapshot,created_by)
   values(pg_temp.fid('realized.'||n||'.line'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized.'||n),1,'Synthetic realized credit',1,1,amount,pg_temp.fid('realized.invoice.line'),'{}',auth.uid());
 end if;
 if p is not null then execute format('update sales.%I set status=''posted'',posted_at=$2,posted_by=$3 where id=$1',rel)
  using pg_temp.fid('realized.'||n),p,auth.uid();end if;
end $$;
select pg_temp.realized_header('invoice','invoice',pg_temp.fid('realized.order.cohort'),current_date-1,12.000003,(current_date-1)::timestamptz+interval '10 hours');
select pg_temp.realized_header('credit','return',pg_temp.fid('realized.order.cohort'),current_date-1,2.000001,(current_date-1)::timestamptz+interval '11 hours');
select pg_temp.realized_header('draft','invoice',pg_temp.fid('realized.order.cohort'),current_date-1,99.000000);
select pg_temp.realized_header('before_horizon','invoice',pg_temp.fid('realized.order.cohort'),current_date-31,99.000000,(current_date-1)::timestamptz);
select pg_temp.realized_header('at_horizon_end','invoice',pg_temp.fid('realized.order.cohort'),current_date,99.000000,current_date::timestamptz);
select pg_temp.realized_header('other_cohort','invoice',pg_temp.fid('realized.order.other'),current_date-1,99.000000,(current_date-1)::timestamptz);
select pg_temp.realized_header('late_record','invoice',pg_temp.fid('realized.order.cohort'),current_date-1,99.000000,statement_timestamp()-interval '1 second');
create temporary table w5_realized_cutoff as select statement_timestamp()-interval '2 seconds' value;
create temporary table w5_realized_documents as select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),
 pg_temp.fid('realized'),(select value from w5_realized_cutoff)) result;
insert into w5_tap select is(jsonb_array_length((select result->'documents' from w5_realized_documents)),2,
 'Realized mapping includes exactly the posted frozen-cohort invoice and order-linked credit');
insert into w5_tap select is((select sum((d->>'amount')::numeric)::text from jsonb_array_elements((select result->'documents' from w5_realized_documents)) d),'10.000002',
 'Nonempty SQL realized gross is exact invoice minus credit with no duplicate line counting');
insert into w5_tap select ok((select bool_and(d->>'opportunityId'=pg_temp.fid('o')::text and d->>'currency'='LKR' and d->>'version'='2')
 from jsonb_array_elements((select result->'documents' from w5_realized_documents)) d),
 'Nonempty realized documents preserve original frozen opportunity, currency and immutable posted versions');
insert into w5_tap select is(api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),(select value from w5_realized_cutoff)),
 (select result from w5_realized_documents),'Identical realization cutoff retains the complete original document result');
insert into w5_tap select is((select sum((d->>'amount')::numeric) filter(where d->>'kind'='credit_return')::text
 from jsonb_array_elements((select result->'documents' from w5_realized_documents)) d),'-2.000001',
 'Credit-return gross retains its explicit negative sign');
delete from core.role_permissions where tenant_id=pg_temp.fid('t') and role_id=pg_temp.fid('owner.role') and permission_code='sales.returns.view';
insert into w5_tap select throws_ok($$select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),statement_timestamp())$$,
 '42501','Permission denied or multi-factor authentication required.','Realized results recheck revoked source-return authority');
insert into core.role_permissions values(pg_temp.fid('t'),pg_temp.fid('owner.role'),'sales.returns.view');
insert into w5_tap select throws_ok($$select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),(current_date-1)::timestamptz)$$,
 '55000','REALIZED_HORIZON_OPEN','Realization cannot publish while its half-open horizon remains open');
select pg_temp.realized_header('line_only_credit','return',null,current_date-1,1.000001,(current_date-1)::timestamptz+interval '12 hours');
insert into w5_tap select throws_ok($$select api.wave5_pipeline_realized(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('realized'),statement_timestamp())$$,
 '55000','REALIZED_MAPPING_INCOMPLETE','Invoice-line-linked credit without an order header rejects partial realized totals');

select * from finish(true);
select jsonb_agg(message) tap from w5_tap;
rollback;
