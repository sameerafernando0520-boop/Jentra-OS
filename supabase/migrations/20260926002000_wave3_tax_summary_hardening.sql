-- Additive correction after the committed tax-summary candidate.
-- Preserve its original migration hash and install both candidates in order.
create or replace function finance.build_tax_summary(t uuid,e uuid,b uuid,p jsonb)
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
  if filter_branch<>b or not exists(select 1 from core.branches
   where tenant_id=t and legal_entity_id=e and id=filter_branch) then
   raise exception using errcode='22023',message='TAX_REPORT_BRANCH_INVALID';end if;
  perform core.wave3_require_scope(t,'finance.view',e,filter_branch);
 end if;
 select rounding_scale into scale from core.legal_entities where tenant_id=t and id=e;
 for r in
  select 'sales_invoice'::text source_type,s.id source_line_id,s.document_id source_id,
   s.branch_id,s.snapshot source_snapshot,s.taxable_amount,s.tax_amount,
   j.id journal_id,j.document_number,coalesce(j.posting_date,doc.document_date) posting_date,
   coalesce(j.currency_code,doc.currency_code) currency_code,
   coalesce(j.base_currency_code,doc.base_currency_code) base_currency_code,
   coalesce(j.exchange_rate,doc.exchange_rate) exchange_rate
  from sales.sales_invoice_lines s join sales.sales_invoices doc on doc.tenant_id=s.tenant_id and doc.id=s.document_id
  left join finance.journal_entries j on j.tenant_id=t and j.legal_entity_id=e and j.source_type='sales_invoice'
   and j.source_id=doc.id and j.status='posted'
  where s.tenant_id=t and s.legal_entity_id=e and doc.status='posted'
   and doc.document_date between period.start_date and d
   and (filter_branch is null or s.branch_id=filter_branch)
   and s.snapshot->>'tax_definition_id' is not null
  union all
  select 'sales_return',s.id,s.document_id,s.branch_id,s.snapshot,s.taxable_amount,s.tax_amount,
   j.id,j.document_number,coalesce(j.posting_date,doc.document_date),
   coalesce(j.currency_code,doc.currency_code),coalesce(j.base_currency_code,doc.base_currency_code),
   coalesce(j.exchange_rate,doc.exchange_rate)
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
   j.id,j.document_number,coalesce(j.posting_date,bill.document_date),
   coalesce(j.currency_code,bill.currency_code),coalesce(j.base_currency_code,bill.base_currency_code),
   coalesce(j.exchange_rate,bill.exchange_rate)
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
  'version',1,
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
