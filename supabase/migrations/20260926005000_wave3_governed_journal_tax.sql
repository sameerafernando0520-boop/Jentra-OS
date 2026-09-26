-- UNAPPLIED additive AC-320 candidate. Governed tax declarations reuse manual
-- journal approval, posting, reversal and immutable ledger engines unchanged.
alter function finance.manual_normalize(uuid,uuid,uuid,jsonb) rename to manual_normalize_before_tax;
create function finance.manual_normalize(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare normalized jsonb;rawlines jsonb;lines jsonb:='[]';line jsonb;raw jsonb;
 definition finance.tax_definitions%rowtype;version bigint;basis numeric;amount numeric;
 scale integer;direction integer;reversal uuid:=(p->>'reversal_of_id')::uuid;
begin
 normalized:=finance.manual_normalize_before_tax(t,e,b,p);
 select rounding_scale into scale from core.legal_entities where tenant_id=t and id=e;
 if reversal is null then rawlines:=p->'lines';
 else select snapshot->'lines' into rawlines from finance.manual_journals
  where tenant_id=t and legal_entity_id=e and branch_id=b and id=reversal and status='posted';end if;
 for line in select value from jsonb_array_elements(normalized->'lines') loop
  select value into raw from jsonb_array_elements(rawlines) where value->>'line_id'=line->>'line_id';
  if raw->>'tax_definition_id' is not null then
   if reversal is not null then
    -- A reversal cancels the original declaration, even after rate retirement.
    -- Client replacement metadata is deliberately ignored.
    line:=line||jsonb_build_object('tax_definition_id',raw->'tax_definition_id',
     'tax_definition_version',raw->'tax_definition_version','tax_code',raw->'tax_code',
     'tax_kind',raw->'tax_kind','tax_rate',raw->'tax_rate','tax_inclusive',raw->'tax_inclusive',
     'taxable_amount',raw->'taxable_amount','tax_basis_date',raw->'tax_basis_date',
     'tax_rounding_scale',raw->'tax_rounding_scale','tax_direction',-(raw->>'tax_direction')::integer,
     'expected_tax_base',abs((line->>'base_amount')::numeric)::numeric(20,6)::text);
   else
    select * into definition from finance.tax_definitions where tenant_id=t and legal_entity_id=e
     and id=(raw->>'tax_definition_id')::uuid and status='active'
     and (normalized->>'document_date')::date between valid_from and coalesce(valid_to,'infinity'::date)
     and kind in('input','output','withholding') for share;
    if not found then raise exception using errcode='55000',message='JOURNAL_TAX_DEFINITION_INVALID';end if;
    select max(v.version) into version from finance.tax_definition_versions v
     where v.tenant_id=t and v.legal_entity_id=e and v.definition_id=definition.id;
    if version is null then raise exception using errcode='55000',message='JOURNAL_TAX_VERSION_UNAVAILABLE';end if;
    basis:=sales.wave3_decimal_string(raw->'taxable_amount','taxable_amount',6,true,0,null)::numeric;
    amount:=abs((line->>'amount')::numeric);
    direction:=case when definition.kind='input' then 1 else -1 end;
    if basis<=0 or amount<>round(basis*definition.rate/100,scale) then
     raise exception using errcode='22023',message='JOURNAL_TAX_AMOUNT_INVALID';end if;
    if sign((line->>'amount')::numeric)<>direction or not exists(select 1 from finance.accounts
     where tenant_id=t and id=(line->>'account_id')::uuid
      and account_type=case when definition.kind='input' then 'asset' else 'liability' end) then
     raise exception using errcode='22023',message='JOURNAL_TAX_ACCOUNT_SIDE_INVALID';end if;
    line:=line||jsonb_build_object('tax_definition_id',definition.id,'tax_definition_version',version,
     'tax_code',definition.code,'tax_kind',definition.kind,'tax_rate',definition.rate::text,
     'tax_inclusive',definition.inclusive,'taxable_amount',basis::numeric(20,6)::text,
     'tax_basis_date',normalized->>'document_date','tax_rounding_scale',scale,'tax_direction',direction,
     'expected_tax_base',abs((line->>'base_amount')::numeric)::numeric(20,6)::text);
   end if;
  elsif raw->>'taxable_amount' is not null then
   raise exception using errcode='22023',message='JOURNAL_TAX_DEFINITION_REQUIRED';
  end if;
  lines:=lines||jsonb_build_array(line);
 end loop;
 return normalized||jsonb_build_object('lines',lines);
end$$;
revoke all on function finance.manual_normalize_before_tax(uuid,uuid,uuid,jsonb),
 finance.manual_normalize(uuid,uuid,uuid,jsonb) from public,anon,authenticated;

create or replace function finance.manual_revalidate(p_kind text,d jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare fresh jsonb;failure text;begin
 begin
  fresh:=finance.manual_normalize((d->>'tenant_id')::uuid,(d->>'legal_entity_id')::uuid,(d->>'branch_id')::uuid,d);
 exception when sqlstate '22023' or sqlstate '55000' then
  get stacked diagnostics failure=message_text;
  if failure like 'JOURNAL_TAX_%' then
   raise exception using errcode='55000',message='JOURNAL_REAPPROVAL_REQUIRED';end if;
  raise;
 end;
 if fresh-'reason'-'description'-'document_date' is distinct from (select snapshot-'reason'-'description'-'document_date'
  from finance.manual_journals where id=(d->>'id')::uuid) then
  raise exception using errcode='55000',message='JOURNAL_REAPPROVAL_REQUIRED';end if;
 return fresh;
end$$;
revoke all on function finance.manual_revalidate(text,jsonb) from public,anon,authenticated;

create function api.manual_journal_tax_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_document_date date,p_after uuid default null,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;n integer;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'finance.journals.post',p_legal_entity_id,p_branch_id);
 if p_document_date is null or p_document_date>(statement_timestamp() at time zone 'UTC')::date
  or length(coalesce(p_search,''))>100 then raise exception using errcode='22023',message='JOURNAL_TAX_OPTIONS_INVALID';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from (
  select d.id,d.code,d.name,d.kind,d.rate::text,d.inclusive,d.valid_from,d.valid_to,
   (select max(version) from finance.tax_definition_versions v where v.tenant_id=d.tenant_id
    and v.legal_entity_id=d.legal_entity_id and v.definition_id=d.id) version
  from finance.tax_definitions d where d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id
   and d.status='active' and d.kind in('input','output','withholding') and d.rate>0
   and p_document_date between d.valid_from and coalesce(d.valid_to,'infinity'::date)
   and (p_after is null or d.id>p_after)
   and (coalesce(p_search,'')='' or d.code ilike '%'||p_search||'%' or d.name ilike '%'||p_search||'%')
  order by d.id limit 51)q;
 n:=jsonb_array_length(rows);if n>50 then rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'document_date',p_document_date,'rounding_scale',(select rounding_scale from core.legal_entities
   where tenant_id=p_tenant_id and id=p_legal_entity_id),'items',rows,
  'next_cursor',case when n>50 then rows->49->>'id' end);
end$$;
revoke all on function api.manual_journal_tax_options(uuid,uuid,uuid,date,uuid,text) from public,anon,authenticated;
grant execute on function api.manual_journal_tax_options(uuid,uuid,uuid,date,uuid,text) to authenticated;


create or replace function finance.tax_posted_sources(t uuid,e uuid,d date)
returns table(source_type text,source_id uuid,source_line_id uuid,branch_id uuid,
 posting_date date,tax_basis_date date,currency_code text,base_currency_code text,
 exchange_rate numeric,source_snapshot jsonb,taxable_amount numeric,tax_amount numeric,
 expected_tax_base numeric,expected_base_verified boolean,journal_entry_id uuid,document_number text)
language sql stable security definer set search_path='' as $$
 select 'sales_invoice',doc.id,s.id,s.branch_id,doc.document_date,doc.document_date,
  doc.currency_code,doc.base_currency_code,doc.exchange_rate,s.snapshot,s.taxable_amount,s.tax_amount,
  round(s.tax_amount*doc.exchange_rate,entity.rounding_scale),true,j.id,doc.document_number
 from sales.sales_invoice_lines s join sales.sales_invoices doc on doc.tenant_id=s.tenant_id and doc.id=s.document_id
 join core.legal_entities entity on entity.tenant_id=doc.tenant_id and entity.id=doc.legal_entity_id
 left join finance.journal_entries j on j.tenant_id=t and j.source_type='sales_invoice' and j.source_id=doc.id and j.status='posted'
 where doc.tenant_id=t and doc.legal_entity_id=e and doc.status='posted' and doc.document_date<=d
  and (s.snapshot->>'tax_definition_id' is not null or s.tax_amount<>0)
 union all
 select 'sales_return',doc.id,s.id,s.branch_id,doc.document_date,invoice.document_date,
  doc.currency_code,doc.base_currency_code,doc.exchange_rate,s.snapshot,s.taxable_amount,s.tax_amount,
  round(s.tax_amount*doc.exchange_rate,entity.rounding_scale),true,j.id,doc.document_number
 from sales.sales_return_lines s join sales.sales_returns doc on doc.tenant_id=s.tenant_id and doc.id=s.document_id
 join core.legal_entities entity on entity.tenant_id=doc.tenant_id and entity.id=doc.legal_entity_id
 left join sales.sales_invoice_lines original on original.tenant_id=s.tenant_id and original.id=s.sales_invoice_line_id
 left join sales.sales_invoices invoice on invoice.tenant_id=original.tenant_id and invoice.id=original.document_id
 left join finance.journal_entries j on j.tenant_id=t and j.source_type='sales_return' and j.source_id=doc.id and j.status='posted'
 where doc.tenant_id=t and doc.legal_entity_id=e and doc.status='posted' and doc.document_date<=d
  and (s.snapshot->>'tax_definition_id' is not null or s.tax_amount<>0)
 union all
 select 'supplier_bill',doc.id,s.id,s.branch_id,doc.document_date,doc.document_date,
  doc.currency_code,doc.base_currency_code,doc.exchange_rate,s.detail,
  (s.detail->>'net_amount')::numeric,(s.detail->>'tax_amount')::numeric,
  round((s.detail->>'tax_amount')::numeric*doc.exchange_rate,entity.rounding_scale),true,j.id,doc.document_number
 from procurement.supplier_bill_lines s join procurement.supplier_bills doc on doc.tenant_id=s.tenant_id and doc.id=s.bill_id
 join core.legal_entities entity on entity.tenant_id=doc.tenant_id and entity.id=doc.legal_entity_id
 left join finance.journal_entries j on j.tenant_id=t and j.source_type='supplier_bill' and j.source_id=doc.id and j.status='posted'
 where doc.tenant_id=t and doc.legal_entity_id=e and doc.status='posted' and doc.document_date<=d
  and (s.detail->>'tax_definition_id' is not null or (s.detail->>'tax_amount')::numeric<>0)
 union all
 select 'purchase_return',doc.id,s.id,s.branch_id,doc.document_date,
  coalesce((s.detail->>'tax_basis_date')::date,bill.document_date),
  doc.currency_code,doc.base_currency_code,doc.exchange_rate,s.detail->'source_snapshot',
  (s.detail->>'net_amount')::numeric,(s.detail->>'tax_amount')::numeric,
  coalesce((s.detail->>'expected_tax_base')::numeric,
   round((s.detail->>'tax_amount')::numeric*doc.exchange_rate,entity.rounding_scale)),
  s.detail->>'expected_tax_base' is not null or (s.detail->>'tax_amount')::numeric=0,j.id,doc.document_number
 from procurement.purchase_return_lines s join procurement.purchase_returns doc on doc.tenant_id=s.tenant_id and doc.id=s.return_id
 join core.legal_entities entity on entity.tenant_id=doc.tenant_id and entity.id=doc.legal_entity_id
 left join procurement.supplier_bill_lines original on original.tenant_id=s.tenant_id and original.id=s.bill_line_id
 left join procurement.supplier_bills bill on bill.tenant_id=original.tenant_id and bill.id=original.bill_id
 left join finance.journal_entries j on j.tenant_id=t and j.id=doc.journal_entry_id and j.status='posted'
 where doc.tenant_id=t and doc.legal_entity_id=e and doc.document_date<=d
  and (s.detail#>>'{source_snapshot,tax_definition_id}' is not null or (s.detail->>'tax_amount')::numeric<>0)
 union all
 select 'manual_journal',doc.id,(x->>'line_id')::uuid,doc.branch_id,doc.document_date,(x->>'tax_basis_date')::date,
  doc.currency_code,doc.snapshot->>'base_currency_code',(doc.snapshot->>'exchange_rate')::numeric,
  x||jsonb_build_object('reversal_of_id',doc.reversal_of_id),
  (x->>'taxable_amount')::numeric,abs((x->>'amount')::numeric),
  (x->>'expected_tax_base')::numeric,true,j.id,doc.document_number
 from finance.manual_journals doc cross join lateral jsonb_array_elements(doc.snapshot->'lines')x
 left join finance.journal_entries j on j.tenant_id=doc.tenant_id and j.id=doc.journal_entry_id and j.status='posted'
 where doc.tenant_id=t and doc.legal_entity_id=e and doc.status='posted' and doc.document_date<=d
  and x->>'tax_definition_id' is not null
$$;
revoke all on function finance.tax_posted_sources(uuid,uuid,date) from public,anon,authenticated;

create or replace function finance.build_tax_summary(t uuid,e uuid,b uuid,p jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare period finance.fiscal_periods%rowtype;d date:=(p->>'as_of')::date;
 filter_branch uuid:=(p->>'branch_filter_id')::uuid;scale integer;r record;
 definition finance.tax_definition_versions%rowtype;journal_lines jsonb;
 line_rows jsonb:='[]';sources jsonb:='[]';journals jsonb;controls jsonb;diffs jsonb;
 blockers jsonb:='[]';reason text;control_reason text;account uuid;account_count integer;ids uuid[];
 tax_transaction numeric;tax_base numeric;taxable_base numeric;direction integer;
 output_base numeric:=0;input_base numeric:=0;withholding_base numeric:=0;zero_base numeric:=0;exempt_base numeric:=0;unverified numeric:=0;
 line_count integer:=0;blocked_count integer:=0;source_count integer:=0;unassigned integer;unattributed integer;reviews integer;
 source_total numeric;gl_total numeric;summary jsonb;result jsonb;
begin
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 if d is null or d>(statement_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='TAX_REPORT_DATE_INVALID';end if;
 select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
  and id=(p->>'period_id')::uuid and status='active';
 if not found or d not between period.start_date and period.end_date then
  raise exception using errcode='22023',message='TAX_REPORT_PERIOD_INVALID';end if;
 if filter_branch is not null and (filter_branch<>b or not exists(select 1 from core.branches
  where tenant_id=t and legal_entity_id=e and id=filter_branch)) then
  raise exception using errcode='22023',message='TAX_REPORT_BRANCH_INVALID';end if;
 select rounding_scale into scale from core.legal_entities where tenant_id=t and id=e;
 for r in select * from finance.tax_posted_sources(t,e,d)
  where filter_branch is null or branch_id=filter_branch order by posting_date,source_type,source_line_id loop
  source_count:=source_count+1;
  if source_count>10000 then raise exception using errcode='54000',message='TAX_REPORT_LINE_LIMIT';end if;
  direction:=case when r.source_type='manual_journal' then (r.source_snapshot->>'tax_direction')::integer when r.source_type in('sales_invoice','purchase_return') then -1 else 1 end;
  select coalesce(sum(direction*(l.transaction_debit-l.transaction_credit)),0),
   coalesce(sum(direction*(l.base_debit-l.base_credit)),0),count(distinct l.account_id),
   (array_agg(l.account_id order by l.line_number))[1],
   coalesce(jsonb_agg(jsonb_build_object('id',l.id,'journal_entry_id',r.journal_entry_id,
    'account_id',l.account_id,'transaction_debit',l.transaction_debit::text,
    'transaction_credit',l.transaction_credit::text,'base_debit',l.base_debit::text,
    'base_credit',l.base_credit::text) order by l.line_number),'[]')
   into tax_transaction,tax_base,account_count,account,journal_lines
  from finance.journal_lines l join finance.accounts a on a.tenant_id=l.tenant_id and a.id=l.account_id
  where l.tenant_id=t and l.journal_entry_id=r.journal_entry_id and l.source_line_id=r.source_line_id
   and a.account_type=case when r.source_type='manual_journal' then case when r.source_snapshot->>'tax_kind'='input' then 'asset' else 'liability' end when r.source_type in('supplier_bill','purchase_return') then 'asset' else 'liability' end;
  if account_count<>1 then account:=null;end if;
  control_reason:=case when not r.expected_base_verified then 'RETURN_TAX_BASE_UNVERIFIED'
   when r.tax_amount<>0 and account is null then 'TAX_CONTROL_ACCOUNT_UNPROVEN'
   when tax_transaction<>r.tax_amount or tax_base<>r.expected_tax_base then 'TAX_CONTROL_JOURNAL_MISMATCH' end;
  if r.tax_amount<>0 or tax_base<>0 then
   sources:=sources||jsonb_build_array(jsonb_build_object('id',r.source_line_id,
    'evidence_key',r.source_type||':'||r.source_id||':'||r.source_line_id,
    'source_type',r.source_type,'source_id',r.source_id,'source_line_id',r.source_line_id,
    'journal_entry_id',r.journal_entry_id,'document_number',r.document_number,'branch_id',r.branch_id,
    'posting_date',r.posting_date,'phase',case when r.posting_date<period.start_date then 'opening' else 'period' end,
    'account_id',account,'currency_code',r.currency_code,'base_currency_code',r.base_currency_code,
    'expected_base',(direction*r.expected_tax_base)::numeric(20,6)::text,
    'posted_base',(direction*tax_base)::numeric(20,6)::text,'review_code',control_reason));
  end if;
  if r.posting_date<period.start_date then continue;end if;
  line_count:=line_count+1;reason:=null;definition:=null;
  if r.source_snapshot->>'tax_definition_version' is null then reason:='MISSING_DEFINITION_VERSION';
  else
   select * into definition from finance.tax_definition_versions where tenant_id=t and legal_entity_id=e
    and definition_id=(r.source_snapshot->>'tax_definition_id')::uuid
    and version=(r.source_snapshot->>'tax_definition_version')::bigint;
   if not found then reason:='DEFINITION_VERSION_UNAVAILABLE';
   elsif r.tax_basis_date is null then reason:='SOURCE_TAX_DATE_UNAVAILABLE';
   elsif r.tax_basis_date not between definition.valid_from and coalesce(definition.valid_to,'infinity'::date)
    or definition.status<>'active' then reason:='DEFINITION_OUTSIDE_SOURCE_DATE';
   elsif definition.kind is distinct from r.source_snapshot->>'tax_kind'
    or definition.rate is distinct from (r.source_snapshot->>'tax_rate')::numeric
    or definition.inclusive is distinct from (r.source_snapshot->>'tax_inclusive')::boolean
    or definition.code is distinct from r.source_snapshot->>'tax_code' then reason:='DEFINITION_SNAPSHOT_MISMATCH';end if;
  end if;
  if reason is null and r.journal_entry_id is null and (r.taxable_amount<>0 or r.tax_amount<>0) then
   reason:='POSTED_JOURNAL_MISSING';end if;
  if reason is null then reason:=control_reason;end if;
  if reason is null and definition.kind in('zero','exempt') and r.tax_amount<>0 then reason:='ZERO_TAX_TREATMENT_MISMATCH';end if;
  if reason is null and r.source_type in('supplier_bill','purchase_return') and definition.kind not in('input','zero','exempt') then
   reason:='INPUT_TREATMENT_MISMATCH';end if;
  if reason is null and r.source_type in('sales_invoice','sales_return') and definition.kind not in('output','zero','exempt') then
   reason:='OUTPUT_TREATMENT_MISMATCH';end if;
  taxable_base:=round(r.taxable_amount*r.exchange_rate,scale);
  if reason is not null then
   blocked_count:=blocked_count+1;unverified:=unverified+abs(r.expected_tax_base);
   if blocked_count<=100 then blockers:=blockers||jsonb_build_array(jsonb_build_object('source_type',r.source_type,
    'source_id',r.source_id,'source_line_id',r.source_line_id,'code',reason));end if;
  elsif definition.kind='output' then output_base:=output_base+case when r.source_type='manual_journal' then -direction*tax_base when r.source_type='sales_return' then -tax_base else tax_base end;
  elsif definition.kind='input' then input_base:=input_base+case when r.source_type='manual_journal' then direction*tax_base when r.source_type='purchase_return' then -tax_base else tax_base end;
  elsif definition.kind='withholding' then withholding_base:=withholding_base-direction*tax_base;
  elsif definition.kind='zero' then zero_base:=zero_base+case when r.source_type in('sales_return','purchase_return') then -taxable_base else taxable_base end;
  else exempt_base:=exempt_base+case when r.source_type in('sales_return','purchase_return') then -taxable_base else taxable_base end;end if;
  line_rows:=line_rows||jsonb_build_array(jsonb_build_object('source_type',r.source_type,'source_id',r.source_id,
   'source_line_id',r.source_line_id,'branch_id',r.branch_id,'journal_entry_id',r.journal_entry_id,
   'document_number',r.document_number,'posting_date',r.posting_date,'tax_basis_date',r.tax_basis_date,
   'tax_direction',direction,'reversal_of_id',r.source_snapshot->'reversal_of_id',
   'currency_code',r.currency_code,'base_currency_code',r.base_currency_code,
   'definition_id',r.source_snapshot->>'tax_definition_id','definition_version',r.source_snapshot->>'tax_definition_version',
   'tax_code',r.source_snapshot->>'tax_code','tax_kind',r.source_snapshot->>'tax_kind','tax_rate',r.source_snapshot->>'tax_rate',
   'taxable_amount',r.taxable_amount::numeric(20,6)::text,'tax_amount',r.tax_amount::numeric(20,6)::text,
   'taxable_base',taxable_base::numeric(20,6)::text,'tax_base',tax_base::numeric(20,6)::text,
   'expected_tax_base',r.expected_tax_base::numeric(20,6)::text,'review_code',reason,'journal_lines',journal_lines));
 end loop;
 select coalesce(array_agg(distinct id),'{}') into ids from (
  select (x->>'account_id')::uuid id from jsonb_array_elements(sources)x where x->>'account_id' is not null
  union select account_id from finance.posting_mappings where tenant_id=t and legal_entity_id=e and purpose='output_tax'
  union select input_tax_account_id from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e
  union select (snapshot->>'input_tax_account_id')::uuid from procurement.supplier_bill_control_history
   where tenant_id=t and legal_entity_id=e and snapshot->>'input_tax_account_id' is not null
 ) all_accounts;
 if cardinality(ids)>50 then raise exception using errcode='54000',message='TAX_CONTROL_ACCOUNT_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into journals from (
  select l.id,l.account_id,j.id journal_entry_id,j.command_id,j.source_type,j.source_id,l.source_line_id,
   j.document_number,l.branch_id,l.posting_date,l.currency_code,j.base_currency_code,
   j.source_type||':'||j.source_id||':'||coalesce(l.source_line_id::text,'journal-'||l.id) evidence_key,
   case when l.posting_date<period.start_date then 'opening' else 'period' end phase,
   l.transaction_debit::text,l.transaction_credit::text,l.base_debit::text,l.base_credit::text,
   (l.base_debit-l.base_credit)::numeric(20,6)::text posted_base
  from finance.journal_lines l join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where l.tenant_id=t and l.legal_entity_id=e and j.status='posted' and l.posting_date<=d and l.account_id=any(ids)
   and (filter_branch is null or l.branch_id=filter_branch) order by l.id limit 10001)q;
 if jsonb_array_length(journals)>10000 then raise exception using errcode='54000',message='TAX_CONTROL_JOURNAL_LIMIT';end if;
 with entries as (
  select (x->>'account_id')::uuid id,(x->>'expected_base')::numeric v,0::numeric g,x->>'phase' phase
   from jsonb_array_elements(sources)x where x->>'account_id' is not null
  union all select (x->>'account_id')::uuid,0,(x->>'posted_base')::numeric,x->>'phase' from jsonb_array_elements(journals)x),
 totals as(select id,coalesce(sum(v) filter(where phase='opening'),0) so,coalesce(sum(g) filter(where phase='opening'),0) go,
  coalesce(sum(v) filter(where phase='period'),0) sp,coalesce(sum(g) filter(where phase='period'),0) gp from entries group by id)
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'account_id',a.id,'code',a.code,'name',a.name,'account_type',a.account_type,
  'source_opening_base',coalesce(so,0)::numeric(20,6)::text,'gl_opening_base',coalesce(go,0)::numeric(20,6)::text,
  'source_period_base',coalesce(sp,0)::numeric(20,6)::text,'gl_period_base',coalesce(gp,0)::numeric(20,6)::text,
  'source_closing_base',(coalesce(so,0)+coalesce(sp,0))::numeric(20,6)::text,
  'gl_closing_base',(coalesce(go,0)+coalesce(gp,0))::numeric(20,6)::text,
  'difference',(coalesce(so,0)+coalesce(sp,0)-coalesce(go,0)-coalesce(gp,0))::numeric(20,6)::text) order by a.id),'[]') into controls
 from finance.accounts a left join totals using(id) where a.tenant_id=t and a.legal_entity_id=e and a.id=any(ids);
 with entries as (
  select x->>'account_id' account_id,x->>'evidence_key' k,(x->>'expected_base')::numeric v,0::numeric g
   from jsonb_array_elements(sources)x
  union all select x->>'account_id',x->>'evidence_key',0,(x->>'posted_base')::numeric from jsonb_array_elements(journals)x),
 totals as(select account_id,k,sum(v) v,sum(g) g from entries group by account_id,k)
 select coalesce(jsonb_agg(jsonb_build_object('id',coalesce(account_id,'unassigned')||':'||k,'account_id',account_id,
  'evidence_key',k,'expected_base',v::numeric(20,6)::text,'posted_base',g::numeric(20,6)::text,
  'difference',(v-g)::numeric(20,6)::text) order by account_id,k),'[]') into diffs from totals where v<>g;
 if jsonb_array_length(diffs)>10000 then raise exception using errcode='54000',message='TAX_CONTROL_DIFFERENCE_LIMIT';end if;
 select count(*) filter(where x->>'account_id' is null),count(*) filter(where x->>'review_code' is not null)
  into unassigned,reviews from jsonb_array_elements(sources)x;
 select count(*) into unattributed from jsonb_array_elements(journals)x where (x->>'posted_base')::numeric<>0
  and not exists(select 1 from jsonb_array_elements(sources)s where s->>'evidence_key'=x->>'evidence_key' and s->>'account_id'=x->>'account_id');
 select coalesce(sum((x->>'source_closing_base')::numeric),0),coalesce(sum((x->>'gl_closing_base')::numeric),0)
  into source_total,gl_total from jsonb_array_elements(controls)x;
 summary:=jsonb_build_object('id',p->>'id','version',2,'tenant_id',t,'legal_entity_id',e,'branch_id',b,
  'period_id',period.id,'period_start',period.start_date,'period_end',period.end_date,'as_of',d,
  'branch_filter_id',filter_branch,'base_currency_code',(select currency_code from core.legal_entities where tenant_id=t and id=e),
  'generated_at',statement_timestamp(),'status',case when blocked_count>0 or jsonb_array_length(diffs)>0 or reviews>0 then 'blocked' else 'generated' end,
  'notice','NON-CERTIFIED • STATUTORY REVIEW REQUIRED','line_count',line_count,'blocked_count',blocked_count,'blockers',blockers,
  'output_tax_base',output_base::numeric(20,6)::text,'input_tax_base',input_base::numeric(20,6)::text,
  'withholding_tax_base',withholding_base::numeric(20,6)::text,'zero_taxable_base',zero_base::numeric(20,6)::text,'exempt_taxable_base',exempt_base::numeric(20,6)::text,
  'unverified_tax_base',unverified::numeric(20,6)::text,'controls',controls,
  'control_status',case when jsonb_array_length(diffs)>0 or reviews>0 then 'blocked' else 'reconciled' end,
  'control_source_count',jsonb_array_length(sources),'control_journal_count',jsonb_array_length(journals),
  'control_difference_count',jsonb_array_length(diffs),'control_review_count',reviews,
  'control_unassigned_source_count',unassigned,'unattributed_journal_count',unattributed,
  'control_source_base',source_total::numeric(20,6)::text,'control_gl_base',gl_total::numeric(20,6)::text,
  'control_difference',(source_total-gl_total)::numeric(20,6)::text);
 result:=jsonb_build_object('summary',summary,'lines',line_rows,'controls',controls,
  'control_sources',sources,'control_journals',journals,'control_differences',diffs);
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='TAX_REPORT_EVIDENCE_LIMIT';end if;
 return result;
end$$;
revoke all on function finance.build_tax_summary(uuid,uuid,uuid,jsonb) from public,anon,authenticated;

-- Cumulative tax sources retain retired manual tax-control account coverage.
create or replace function finance.period_close_exceptions(t uuid,e uuid,p finance.fiscal_periods)
returns jsonb language plpgsql security definer set search_path='' as $$
declare issues jsonb;report jsonb;branch uuid;begin
 issues:=finance.period_close_exceptions_before_tax(t,e,p);
 if p.end_date<(statement_timestamp() at time zone 'UTC')::date and (exists(
  select 1 from finance.tax_posted_sources(t,e,p.end_date)) or exists(
  select 1 from finance.journal_lines l join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where l.tenant_id=t and l.legal_entity_id=e and j.status='posted' and l.posting_date between p.start_date and p.end_date
   and l.account_id in(select account_id from finance.posting_mappings where tenant_id=t and legal_entity_id=e and purpose='output_tax'
    union select input_tax_account_id from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e
    union select (snapshot->>'input_tax_account_id')::uuid from procurement.supplier_bill_control_history
     where tenant_id=t and legal_entity_id=e and snapshot->>'input_tax_account_id' is not null))) then
  begin
   select id into branch from core.branches where tenant_id=t and legal_entity_id=e and status='active' order by id limit 1;
   report:=finance.build_tax_summary(t,e,branch,jsonb_build_object('id',gen_random_uuid(),'period_id',p.id,'as_of',p.end_date))->'summary';
   if report->>'status'='blocked' then issues:=issues||jsonb_build_array(jsonb_build_object('code','TAX_REVIEW_BLOCKED',
    'blocked_count',report->'blocked_count','control_difference_count',report->'control_difference_count',
    'control_review_count',report->'control_review_count','control_difference',report->>'control_difference'));end if;
  exception when others then issues:=issues||jsonb_build_array(jsonb_build_object('code','TAX_REVIEW_CHECK_FAILED','sqlstate',sqlstate));end;
 end if;
 return issues;
end$$;
revoke all on function finance.period_close_exceptions(uuid,uuid,finance.fiscal_periods) from public,anon,authenticated;
notify pgrst,'reload schema';
