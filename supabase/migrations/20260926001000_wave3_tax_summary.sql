-- UNAPPLIED AC-320 tax summary candidate. Exercise only inside ROLLBACK.
-- Existing posted bills without a versioned tax snapshot remain review blockers.
create table finance.tax_definition_versions (
 tenant_id uuid not null,legal_entity_id uuid not null,definition_id uuid not null,
 version bigint not null,code text not null,name text not null,kind text not null,
 rate numeric(12,6) not null,inclusive boolean not null,recoverable boolean not null,
 valid_from date not null,valid_to date,status text not null,captured_at timestamptz not null default clock_timestamp(),
 primary key(tenant_id,legal_entity_id,definition_id,version)
);
alter table finance.tax_definition_versions enable row level security;
alter table finance.tax_definition_versions force row level security;
revoke all on finance.tax_definition_versions from public,anon,authenticated;
create trigger immutable before update or delete on finance.tax_definition_versions
 for each row execute function workflow.reject_history_mutation();

create function finance.capture_tax_definition_version() returns trigger
language plpgsql security definer set search_path='' as $$begin
 insert into finance.tax_definition_versions(tenant_id,legal_entity_id,definition_id,version,
 code,name,kind,rate,inclusive,recoverable,valid_from,valid_to,status)
 values(new.tenant_id,new.legal_entity_id,new.id,new.version,new.code,new.name,new.kind,
 new.rate,new.inclusive,new.recoverable,new.valid_from,new.valid_to,new.status);
 return new;
end$$;
revoke all on function finance.capture_tax_definition_version() from public,anon,authenticated;
insert into finance.tax_definition_versions(tenant_id,legal_entity_id,definition_id,version,
 code,name,kind,rate,inclusive,recoverable,valid_from,valid_to,status)
select tenant_id,legal_entity_id,id,version,code,name,kind,rate,inclusive,recoverable,
 valid_from,valid_to,status from finance.tax_definitions;
create trigger tax_definition_version_snapshot after insert or update on finance.tax_definitions
 for each row execute function finance.capture_tax_definition_version();

-- The bill posting command rewrites draft line detail immediately before the
-- journal and status transition. Capture the effective definition on that write.
create function finance.snapshot_bill_tax() returns trigger
language plpgsql security definer set search_path='' as $$
declare d finance.tax_definitions%rowtype;bill procurement.supplier_bills%rowtype;
begin
 if new.detail->>'tax_definition_id' is null then return new;end if;
 select * into bill from procurement.supplier_bills where tenant_id=new.tenant_id and id=new.bill_id;
 select * into d from finance.tax_definitions where tenant_id=new.tenant_id
  and legal_entity_id=new.legal_entity_id and id=(new.detail->>'tax_definition_id')::uuid
  and status='active' and kind in('input','zero','exempt')
  and bill.document_date between valid_from and coalesce(valid_to,'infinity'::date);
 if not found or d.rate is distinct from (new.detail->>'tax_rate')::numeric
  or d.inclusive is distinct from (new.detail->>'tax_inclusive')::boolean then
  raise exception using errcode='55000',message='BILL_TAX_SNAPSHOT_CHANGED';end if;
 new.detail:=new.detail||jsonb_build_object('tax_code',d.code,'tax_name',d.name,
  'tax_kind',d.kind,'tax_definition_version',d.version,'tax_valid_from',d.valid_from,
  'tax_valid_to',d.valid_to,'tax_recoverable',d.recoverable);
 return new;
end$$;
revoke all on function finance.snapshot_bill_tax() from public,anon,authenticated;
create trigger bill_tax_snapshot before insert or update of detail on procurement.supplier_bill_lines
 for each row execute function finance.snapshot_bill_tax();

create table finance.tax_reports(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 requested_branch_id uuid not null,period_id uuid not null,as_of date not null,
 branch_filter_id uuid,generated_at timestamptz not null,summary jsonb not null,evidence jsonb not null,
 created_by uuid not null references auth.users(id),unique(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,requested_branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,branch_filter_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,period_id) references finance.fiscal_periods(tenant_id,legal_entity_id,id),
 check(jsonb_typeof(summary)='object' and jsonb_typeof(evidence)='object'
  and octet_length(evidence::text)<=16777216)
);
create index tax_reports_scope on finance.tax_reports(tenant_id,legal_entity_id,requested_branch_id,id);
create index tax_reports_period on finance.tax_reports(tenant_id,period_id,id);
create index tax_reports_actor on finance.tax_reports(created_by);
alter table finance.tax_reports enable row level security;
alter table finance.tax_reports force row level security;
revoke all on finance.tax_reports from public,anon,authenticated;
create trigger immutable before update or delete on finance.tax_reports
 for each row execute function workflow.reject_history_mutation();

create function finance.build_tax_summary(t uuid,e uuid,b uuid,p jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare period finance.fiscal_periods%rowtype;d date:=(p->>'as_of')::date;
 filter_branch uuid:=(p->>'branch_filter_id')::uuid;scale integer;generated timestamptz:=clock_timestamp();
 r record;definition finance.tax_definition_versions%rowtype;journal_lines jsonb;
 tax_transaction numeric;tax_base numeric;expected_transaction numeric;expected_base numeric;
 taxable_base numeric;output_base numeric:=0;input_base numeric:=0;withholding_base numeric:=0;
 zero_taxable numeric:=0;exempt_taxable numeric:=0;unverified_base numeric:=0;
 line_rows jsonb:='[]';blockers jsonb:='[]';reason text;line_count integer:=0;blocked_count integer:=0;
 summary jsonb;
begin
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 if d is null or d>(clock_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='TAX_REPORT_DATE_INVALID';end if;
 select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
  and id=(p->>'period_id')::uuid and status='active';
 if not found or d not between period.start_date and period.end_date then
  raise exception using errcode='22023',message='TAX_REPORT_PERIOD_INVALID';end if;
 if filter_branch is not null then
  if not exists(select 1 from core.branches where tenant_id=t and legal_entity_id=e and id=filter_branch) then
   raise exception using errcode='22023',message='TAX_REPORT_BRANCH_INVALID';end if;
  perform core.wave3_require_scope(t,'finance.view',e,filter_branch);
 end if;
 select rounding_scale into scale from core.legal_entities where tenant_id=t and id=e;
 for r in
  select 'sales_invoice'::text source_type,s.id source_line_id,s.document_id source_id,
   s.branch_id,s.snapshot source_snapshot,s.taxable_amount,s.tax_amount,
   j.id journal_id,j.document_number,j.posting_date,j.currency_code,j.base_currency_code,j.exchange_rate
  from sales.sales_invoice_lines s join sales.sales_invoices doc on doc.tenant_id=s.tenant_id and doc.id=s.document_id
  left join finance.journal_entries j on j.tenant_id=t and j.legal_entity_id=e and j.source_type='sales_invoice'
   and j.source_id=doc.id and j.status='posted'
  where s.tenant_id=t and s.legal_entity_id=e and doc.status='posted'
   and doc.document_date between period.start_date and d
   and (filter_branch is null or s.branch_id=filter_branch)
   and s.snapshot->>'tax_definition_id' is not null
  union all
  select 'sales_return',s.id,s.document_id,s.branch_id,s.snapshot,s.taxable_amount,s.tax_amount,
   j.id,j.document_number,j.posting_date,j.currency_code,j.base_currency_code,j.exchange_rate
  from sales.sales_return_lines s join sales.sales_returns doc on doc.tenant_id=s.tenant_id and doc.id=s.document_id
  left join finance.journal_entries j on j.tenant_id=t and j.legal_entity_id=e and j.source_type='sales_return'
   and j.source_id=doc.id and j.status='posted'
  where s.tenant_id=t and s.legal_entity_id=e and doc.status='posted'
   and doc.document_date between period.start_date and d
   and (filter_branch is null or s.branch_id=filter_branch)
   and s.snapshot->>'tax_definition_id' is not null
  union all
  select 'supplier_bill',l.id,l.bill_id,l.branch_id,l.detail,
   (l.detail->>'net_amount')::numeric,(l.detail->>'tax_amount')::numeric,
   j.id,j.document_number,j.posting_date,j.currency_code,j.base_currency_code,j.exchange_rate
  from procurement.supplier_bill_lines l join procurement.supplier_bills bill on bill.tenant_id=l.tenant_id and bill.id=l.bill_id
  left join finance.journal_entries j on j.tenant_id=t and j.legal_entity_id=e and j.source_type='supplier_bill'
   and j.source_id=bill.id and j.status='posted'
  where l.tenant_id=t and l.legal_entity_id=e and bill.status='posted'
   and bill.document_date between period.start_date and d
   and (filter_branch is null or l.branch_id=filter_branch)
   and l.detail->>'tax_definition_id' is not null
  order by posting_date,source_type,source_id,source_line_id
 loop
  line_count:=line_count+1;
  if line_count>10000 then raise exception using errcode='54000',message='TAX_REPORT_LINE_LIMIT';end if;
  reason:=null;definition:=null;
  if r.source_snapshot->>'tax_definition_version' is null then reason:='MISSING_DEFINITION_VERSION';
  else
   select * into definition from finance.tax_definition_versions where tenant_id=t
    and legal_entity_id=e and definition_id=(r.source_snapshot->>'tax_definition_id')::uuid
    and version=(r.source_snapshot->>'tax_definition_version')::bigint;
   if not found then reason:='DEFINITION_VERSION_UNAVAILABLE';
   elsif r.posting_date not between definition.valid_from and coalesce(definition.valid_to,'infinity'::date)
    or definition.status<>'active' then reason:='DEFINITION_OUTSIDE_POSTING_DATE';
   elsif definition.kind is distinct from r.source_snapshot->>'tax_kind'
    or definition.rate is distinct from (r.source_snapshot->>'tax_rate')::numeric
    or definition.inclusive is distinct from (r.source_snapshot->>'tax_inclusive')::boolean
    or definition.code is distinct from r.source_snapshot->>'tax_code' then
    reason:='DEFINITION_SNAPSHOT_MISMATCH';end if;
  end if;
  select coalesce(sum(case when r.source_type='sales_invoice' then l.transaction_credit-l.transaction_debit
    when r.source_type='sales_return' then l.transaction_debit-l.transaction_credit
    else l.transaction_debit-l.transaction_credit end),0),
   coalesce(sum(case when r.source_type='sales_invoice' then l.base_credit-l.base_debit
    when r.source_type='sales_return' then l.base_debit-l.base_credit
    else l.base_debit-l.base_credit end),0),
   coalesce(jsonb_agg(jsonb_build_object('id',l.id,'journal_entry_id',r.journal_id,
    'account_id',l.account_id,'transaction_debit',l.transaction_debit::text,
    'transaction_credit',l.transaction_credit::text,'base_debit',l.base_debit::text,
    'base_credit',l.base_credit::text) order by l.line_number),'[]'::jsonb)
   into tax_transaction,tax_base,journal_lines
  from finance.journal_lines l join finance.accounts a on a.tenant_id=l.tenant_id and a.id=l.account_id
  where l.tenant_id=t and l.journal_entry_id=r.journal_id and l.source_line_id=r.source_line_id
   and a.account_type=case when r.source_type='supplier_bill' then 'asset' else 'liability' end;
  expected_transaction:=r.tax_amount;
  expected_base:=round(expected_transaction*coalesce(r.exchange_rate,0),scale);
  taxable_base:=round(r.taxable_amount*coalesce(r.exchange_rate,0),scale);
  if reason is null and (r.journal_id is null and (r.taxable_amount<>0 or r.tax_amount<>0)) then
   reason:='POSTED_JOURNAL_MISSING';end if;
  if reason is null and (tax_transaction<>expected_transaction or tax_base<>expected_base) then
   reason:='TAX_JOURNAL_MISMATCH';end if;
  if reason is null and definition.kind in('zero','exempt') and r.tax_amount<>0 then
   reason:='ZERO_TAX_TREATMENT_MISMATCH';end if;
  if reason is null and r.source_type='supplier_bill' and definition.kind not in('input','zero','exempt') then
   reason:='INPUT_TREATMENT_MISMATCH';end if;
  if reason is null and r.source_type<>'supplier_bill' and definition.kind not in('output','zero','exempt') then
   reason:='OUTPUT_TREATMENT_MISMATCH';end if;
  if reason is not null then
   blocked_count:=blocked_count+1;unverified_base:=unverified_base+expected_base;
   if blocked_count<=100 then
    blockers:=blockers||jsonb_build_array(jsonb_build_object('source_type',r.source_type,
     'source_id',r.source_id,'source_line_id',r.source_line_id,'code',reason));end if;
  else
   if definition.kind='output' then output_base:=output_base+case when r.source_type='sales_return' then -tax_base else tax_base end;
   elsif definition.kind='input' then input_base:=input_base+tax_base;
   elsif definition.kind='withholding' then withholding_base:=withholding_base+tax_base;
   elsif definition.kind='zero' then zero_taxable:=zero_taxable+case when r.source_type='sales_return' then -taxable_base else taxable_base end;
   else exempt_taxable:=exempt_taxable+case when r.source_type='sales_return' then -taxable_base else taxable_base end;end if;
  end if;
  line_rows:=line_rows||jsonb_build_array(jsonb_build_object('source_type',r.source_type,
   'source_id',r.source_id,'source_line_id',r.source_line_id,'branch_id',r.branch_id,
   'journal_entry_id',r.journal_id,'document_number',r.document_number,
   'posting_date',r.posting_date,'currency_code',r.currency_code,
   'base_currency_code',r.base_currency_code,'definition_id',r.source_snapshot->>'tax_definition_id',
   'definition_version',r.source_snapshot->>'tax_definition_version',
   'tax_code',r.source_snapshot->>'tax_code','tax_kind',r.source_snapshot->>'tax_kind',
   'tax_rate',r.source_snapshot->>'tax_rate','taxable_amount',r.taxable_amount::numeric(20,6)::text,
   'tax_amount',r.tax_amount::numeric(20,6)::text,'taxable_base',taxable_base::numeric(20,6)::text,
   'tax_base',tax_base::numeric(20,6)::text,'expected_tax_base',expected_base::numeric(20,6)::text,
   'review_code',reason,'journal_lines',journal_lines));
 end loop;
 summary:=jsonb_build_object('id',p->>'id','tenant_id',t,'legal_entity_id',e,'branch_id',b,
  'period_id',period.id,'period_start',period.start_date,'period_end',period.end_date,
  'as_of',d,'branch_filter_id',filter_branch,'base_currency_code',
  (select currency_code from core.legal_entities where id=e),
  'generated_at',generated,'status',case when blocked_count>0 then 'blocked' else 'generated' end,
  'notice','NON-CERTIFIED • STATUTORY REVIEW REQUIRED',
  'line_count',line_count,'blocked_count',blocked_count,'blockers',blockers,
  'output_tax_base',output_base::numeric(20,6)::text,
  'input_tax_base',input_base::numeric(20,6)::text,
  'withholding_tax_base',withholding_base::numeric(20,6)::text,
  'zero_taxable_base',zero_taxable::numeric(20,6)::text,
  'exempt_taxable_base',exempt_taxable::numeric(20,6)::text,
  'unverified_tax_base',unverified_base::numeric(20,6)::text);
 return jsonb_build_object('summary',summary,'lines',line_rows);
end$$;
revoke all on function finance.build_tax_summary(uuid,uuid,uuid,jsonb) from public,anon,authenticated;

create function api.generate_tax_summary(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare id uuid:=(p_payload->>'id')::uuid;h text;r jsonb;data jsonb;summary jsonb;req uuid:=gen_random_uuid();
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if id is null or p_client_timestamp is null then raise exception using errcode='22023',message='TAX_REPORT_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.tax_summary.generate',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.tax_summary.generate',p_command_id,p_idempotency_key,h);
 if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 data:=finance.build_tax_summary(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 summary:=data->'summary';
 insert into finance.tax_reports values(id,p_tenant_id,p_legal_entity_id,p_branch_id,
  (summary->>'period_id')::uuid,(summary->>'as_of')::date,
  (summary->>'branch_filter_id')::uuid,(summary->>'generated_at')::timestamptz,
  summary,data,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'finance.tax_summary.generate',p_command_id,
  'tax_summary_report',id,p_idempotency_key,h,null,summary,p_legal_entity_id,p_branch_id,
  '{}',jsonb_build_object('to_status',summary->>'status'),
  jsonb_build_array(jsonb_build_object('topic','finance.tax_summary.generated','payload',summary)),
  '[]',req,req);
end$$;

create function api.tax_summary_reports(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_after uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(summary order by id),'[]') into rows from (
  select id,summary from finance.tax_reports where tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and requested_branch_id=p_branch_id
   and (p_after is null or id>p_after) order by id limit 51)q;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'items',rows,'next_cursor',cursor);
end$$;

create function api.tax_summary_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_report_id uuid,p_offset integer default 0,p_source_line_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare report finance.tax_reports%rowtype;rows jsonb;n integer;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_offset is null or p_offset<0 or p_offset>10000 then
  raise exception using errcode='22023',message='TAX_REPORT_PAGE_INVALID';end if;
 select * into report from finance.tax_reports where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and requested_branch_id=p_branch_id and id=p_report_id;
 if not found then raise exception using errcode='42501',message='TAX_REPORT_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(value order by ord),'[]') into rows from (
  select value,ord from jsonb_array_elements(report.evidence->'lines') with ordinality x(value,ord)
  where p_source_line_id is null or value->>'source_line_id'=p_source_line_id::text
  order by ord offset p_offset limit 51)q;
 n:=jsonb_array_length(rows);if n>50 then rows:=rows-50;end if;
 return jsonb_build_object('summary',report.summary,'items',rows,
  'next_offset',case when n>50 then p_offset+50 end);
end$$;

revoke all on function api.generate_tax_summary(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.tax_summary_reports(uuid,uuid,uuid,uuid),
 api.tax_summary_page(uuid,uuid,uuid,uuid,integer,uuid) from public,anon,authenticated;
grant execute on function api.generate_tax_summary(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.tax_summary_reports(uuid,uuid,uuid,uuid),
 api.tax_summary_page(uuid,uuid,uuid,uuid,integer,uuid) to authenticated;
