-- Private, exact posting helpers. All mutations run inside the calling RPC transaction.
create function sales.flow_assert_transition(p_lifecycle jsonb,p_from text,p_to text) returns void
language plpgsql immutable set search_path='' as $$ begin
 if p_from='pending_approval' then p_from:='submitted';end if;
 if p_to='pending_approval' then p_to:='submitted';end if;
 if p_lifecycle is null or not (coalesce(p_lifecycle->'transitions','[]'::jsonb)||coalesce(p_lifecycle->'posting_transitions','[]'::jsonb))
 @> jsonb_build_array(jsonb_build_array(p_from,p_to)) then raise exception using errcode='55000',message='WORKFLOW_TRANSITION_INVALID';end if;end $$;
create function sales.flow_document(p_kind text,p_tenant uuid,p_id uuid,p_lock boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_doc jsonb;v_lines jsonb;v_table text:=sales.flow_table(p_kind);begin
 if v_table is null then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 execute format('select sales.flow_exact_json(to_jsonb(d)) from sales.%I d where tenant_id=$1 and id=$2%s',v_table,
 case when p_lock then ' for update' else '' end) into v_doc using p_tenant,p_id;
 if v_doc is null then return null;end if;
 v_doc:=v_doc||jsonb_build_object('customer_name',(select coalesce(display_name,legal_name) from crm.parties where tenant_id=p_tenant and id=(v_doc->>'customer_id')::uuid));
 execute format('select coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(l)) order by line_number),''[]''::jsonb) from sales.%I l where tenant_id=$1 and document_id=$2',sales.flow_lines_table(p_kind))
 into v_lines using p_tenant,p_id;return v_doc||jsonb_build_object('lines',v_lines);end $$;

create function finance.flow_account(p_tenant uuid,p_entity uuid,p_account uuid,p_type text,p_currency text default null)
returns uuid language plpgsql security definer set search_path='' as $$
begin if p_account is null or not exists(select 1 from finance.accounts a
 where a.tenant_id=p_tenant and a.legal_entity_id=p_entity and a.id=p_account
 and a.status='active' and a.is_posting and a.account_type=p_type
 and (a.currency_code is null or a.currency_code=p_currency)) then
 raise exception using errcode='55000',message='ACCOUNT_MAPPING_INVALID';end if;return p_account;end $$;
create function finance.flow_mapping(p_tenant uuid,p_entity uuid,p_purpose text,p_currency text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;begin select account_id into v_id from finance.posting_mappings
 where tenant_id=p_tenant and legal_entity_id=p_entity and purpose=p_purpose and status='active';
 return finance.flow_account(p_tenant,p_entity,v_id,case p_purpose when 'receivable_control' then 'asset'
 when 'output_tax' then 'liability' when 'exchange_gain' then 'revenue' else 'expense' end,p_currency);end $$;

create function finance.flow_rate(p_tenant uuid,p_entity uuid,p_currency text,p_date date,p_rate_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_base text;v_rate finance.exchange_rates%rowtype;begin
 select currency_code into v_base from core.legal_entities where tenant_id=p_tenant and id=p_entity;
 if not exists(select 1 from core.currencies where code=p_currency and active) then
 raise exception using errcode='22023',message='CURRENCY_INVALID';end if;
 if p_currency=v_base then
 if p_rate_id is not null then raise exception using errcode='22023',message='EXCHANGE_RATE_INVALID';end if;
 return jsonb_build_object('base_currency_code',v_base,'exchange_rate','1.0000000000','exchange_rate_id',null,'rate_date',p_date);
 end if;
 select * into v_rate from finance.exchange_rates where tenant_id=p_tenant and legal_entity_id=p_entity
 and id=p_rate_id and source_currency_code=p_currency and target_currency_code=v_base and status='active' and effective_date<=p_date;
 if not found then raise exception using errcode='22023',message='EXCHANGE_RATE_INVALID';end if;
 return jsonb_build_object('base_currency_code',v_base,'exchange_rate',v_rate.rate::text,
 'exchange_rate_id',v_rate.id,'rate_date',v_rate.effective_date);end $$;

create function finance.flow_residual(p_tenant uuid,p_id uuid,p_as_of date default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('amount',(o.original_amount+
 coalesce((select sum(a.source_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0)-
 coalesce((select sum(a.transaction_amount+a.write_off+a.discount_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0))::text,
 'base_amount',(o.original_base_amount+
 coalesce((select sum(a.source_base_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0)-
 coalesce((select sum(a.target_base_amount+a.adjustment_base_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id and (p_as_of is null or a.posting_date<=p_as_of)),0))::text)
 from finance.open_items o where o.tenant_id=p_tenant and o.id=p_id and (p_as_of is null or o.posting_date<=p_as_of) $$;

create function finance.flow_journal_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_status text;v_count bigint;v_diff numeric;begin
 v_id:=case when tg_table_name='journal_entries' then new.id else (to_jsonb(new)->>'journal_entry_id')::uuid end;
 select status into v_status from finance.journal_entries where id=v_id;
 select count(*),sum(base_debit-base_credit) into v_count,v_diff from finance.journal_lines where journal_entry_id=v_id;
 if v_status<>'posted' or v_count<2 or v_diff is distinct from 0 then
 raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;return null;end $$;
create constraint trigger journal_balanced after insert or update on finance.journal_entries
deferrable initially deferred for each row execute function finance.flow_journal_guard();
create constraint trigger journal_lines_balanced after insert on finance.journal_lines
deferrable initially deferred for each row execute function finance.flow_journal_guard();
create function finance.flow_journal_line_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin if not exists(select 1 from finance.journal_entries j where j.id=new.journal_entry_id
 and j.tenant_id=new.tenant_id and j.legal_entity_id=new.legal_entity_id and j.branch_id=new.branch_id and j.status='draft') then
 raise exception using errcode='55000',message='POSTED_JOURNAL_IMMUTABLE';end if;return new;end $$;
create trigger protect_posted_lines before insert on finance.journal_lines
for each row execute function finance.flow_journal_line_guard();

-- Each input contains account_id and signed transaction/base amounts (debits positive).
create function finance.flow_post_journal(p_doc jsonb,p_lines jsonb,p_source_type text,p_source_id uuid,p_request uuid,p_command uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid();v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;
 v_b uuid:=(p_doc->>'branch_id')::uuid;v_date date:=(p_doc->>'document_date')::date;v_period uuid;v_item jsonb;
 v_diff numeric;v_transaction numeric;v_base numeric;v_ord integer:=0;v_account finance.accounts%rowtype;begin
 if jsonb_array_length(p_lines)=0 then return null;end if;
 select sum((x->>'base_amount')::numeric) into v_diff from jsonb_array_elements(p_lines) x;
 if v_diff<>0 then raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;
 v_period:=finance.wave3_lock_open_period(v_t,v_e,v_date);
 insert into finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,
 posting_date,source_type,source_id,currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
 values(v_id,v_t,v_e,v_b,v_period,sales.wave3_reserve_document_number(v_t,v_e,v_b,'journal_entry',v_date,auth.uid()),
 v_date,p_source_type,p_source_id,p_doc->>'currency_code',p_doc->>'base_currency_code',(p_doc->>'exchange_rate')::numeric,
 p_request,p_command,p_request,auth.uid());
 for v_item in select value from jsonb_array_elements(p_lines) loop
 v_base:=(v_item->>'base_amount')::numeric;v_transaction:=(v_item->>'amount')::numeric;
 if v_base=0 then
 if v_transaction<>0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;continue;end if;
 select * into v_account from finance.accounts where tenant_id=v_t and legal_entity_id=v_e
 and id=(v_item->>'account_id')::uuid and is_posting and status='active'
 and (currency_code is null or currency_code=p_doc->>'currency_code');
 if not found then raise exception using errcode='55000',message='ACCOUNT_MAPPING_INVALID';end if;
 v_ord:=v_ord+1;
 insert into finance.journal_lines(tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,party_id,
 source_line_id,currency_code,transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
 values(v_t,v_e,v_b,v_id,v_ord,v_account.id,(p_doc->>'customer_id')::uuid,(v_item->>'source_line_id')::uuid,
 p_doc->>'currency_code',greatest(v_transaction,0),greatest(-v_transaction,0),greatest(v_base,0),greatest(-v_base,0),v_date,auth.uid());
 end loop;
 if v_ord<2 then raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;
 update finance.journal_entries set status='posted' where id=v_id;return v_id;end $$;

create function finance.flow_jline(p_account uuid,p_amount numeric,p_base numeric,p_source uuid default null)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('account_id',p_account,'amount',p_amount::text,'base_amount',p_base::text,'source_line_id',p_source) $$;

create function sales.flow_price(p_kind text,p_doc jsonb,p_inputs jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;v_b uuid:=(p_doc->>'branch_id')::uuid;
 v_scale integer:=(p_doc->>'rounding_scale')::integer;v_input jsonb;v_result jsonb:='[]';v_line jsonb;
 v_product inventory.products%rowtype;v_order sales.sales_orders%rowtype;v_order_line sales.sales_order_lines%rowtype;
 v_delivery sales.deliveries%rowtype;v_dl sales.delivery_lines%rowtype;v_invoice sales.sales_invoices%rowtype;v_il sales.sales_invoice_lines%rowtype;
 v_q numeric;v_txq numeric;v_prior numeric;v_limit numeric;v_net numeric;v_tax numeric;v_price jsonb;v_ord integer:=0;
 v_amount numeric;v_total numeric:=0;v_tax_total numeric:=0;v_subtotal numeric:=0;v_discount numeric:=0;
 v_fraction numeric;v_gross numeric;v_discount_line numeric;
 v_prior_credit numeric;v_return_base numeric:=0;
begin
 if p_kind='customer_receipt' then
 v_amount:=sales.wave3_decimal_string(p_doc->'amount','Receipt amount',6,true,0,null)::numeric;
 if v_amount<=0 or v_amount<>round(v_amount,v_scale) then raise exception using errcode='22023',message='RECEIPT_AMOUNT_INVALID';end if;
 return jsonb_build_object('lines','[]'::jsonb,'subtotal',v_amount::text,'discount_total','0','tax_total','0','grand_total',v_amount::text,
 'base_total',round(v_amount*(p_doc->>'exchange_rate')::numeric,v_scale)::text);end if;
 if jsonb_typeof(p_inputs) is distinct from 'array' or jsonb_array_length(p_inputs) not between 1 and 500 then
 raise exception using errcode='22023',message='DOCUMENT_LINES_INVALID';end if;
 if (select count(*)<>count(distinct coalesce(x->>'line_id',x->>'id')) from jsonb_array_elements(p_inputs) x) then
 raise exception using errcode='22023',message='LINE_IDENTITIES_INVALID';end if;
 for v_input in select value from jsonb_array_elements(p_inputs) loop
 v_ord:=v_ord+1;v_order_line:=null;v_dl:=null;v_il:=null;v_line:=null;v_net:=0;v_tax:=0;
 v_q:=sales.wave3_decimal_string(v_input->'base_quantity','Base quantity',6,true,0,null)::numeric;
 if v_q<=0 then raise exception using errcode='22023',message='QUANTITY_INVALID';end if;
 if p_kind='sales_return' then
 if nullif(trim(p_doc->>'reason'),'') is null or coalesce(v_input->>'disposition','') not in ('saleable','no_restock') then
 raise exception using errcode='22023',message='RETURN_REASON_DISPOSITION_REQUIRED';end if;
 if v_input->>'sales_invoice_line_id' is not null then
 select l.* into v_il from sales.sales_invoice_lines l join sales.sales_invoices i on i.tenant_id=l.tenant_id and i.id=l.document_id
 where l.tenant_id=v_t and l.id=(v_input->>'sales_invoice_line_id')::uuid and i.legal_entity_id=v_e and i.branch_id=v_b
 and i.customer_id=(p_doc->>'customer_id')::uuid and i.status='posted' and i.document_date<=(p_doc->>'document_date')::date;
 if not found then raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
 select * into v_invoice from sales.sales_invoices where id=v_il.document_id;
 if v_invoice.currency_code<>p_doc->>'currency_code' then raise exception using errcode='22023',message='SOURCE_CURRENCY_MISMATCH';end if;
 if v_invoice.exchange_rate<>(p_doc->>'exchange_rate')::numeric then
 raise exception using errcode='22023',message='RETURN_ORIGINAL_RATE_REQUIRED';end if;
 v_line:=v_il.snapshot;v_limit:=v_il.base_quantity;
 select coalesce(sum(l.base_quantity),0) into v_prior from sales.sales_return_lines l join sales.sales_returns r on r.id=l.document_id and r.tenant_id=l.tenant_id
 where l.tenant_id=v_t and l.sales_invoice_line_id=v_il.id and r.status='posted';
 v_net:=round(v_il.taxable_amount*(v_prior+v_q)/v_limit,v_scale)-round(v_il.taxable_amount*v_prior/v_limit,v_scale);
 v_tax:=round(v_il.tax_amount*(v_prior+v_q)/v_limit,v_scale)-round(v_il.tax_amount*v_prior/v_limit,v_scale);
 select coalesce(sum(rl.line_total),0) into v_prior_credit from sales.sales_return_lines rl
 join sales.sales_returns r on r.tenant_id=rl.tenant_id and r.id=rl.document_id
 join sales.sales_invoice_lines il on il.tenant_id=rl.tenant_id and il.id=rl.sales_invoice_line_id
 where rl.tenant_id=v_t and il.document_id=v_invoice.id and r.status='posted';
 v_prior_credit:=v_prior_credit+coalesce((select sum((x->>'line_total')::numeric) from jsonb_array_elements(v_result) x
 join sales.sales_invoice_lines il on il.tenant_id=v_t and il.id=(x->>'sales_invoice_line_id')::uuid where il.document_id=v_invoice.id),0);
 if v_invoice.grand_total>0 then
 v_return_base:=v_return_base+round(v_invoice.base_total*(v_prior_credit+v_net+v_tax)/v_invoice.grand_total,v_scale)
 -round(v_invoice.base_total*v_prior_credit/v_invoice.grand_total,v_scale);end if;
 v_input:=v_input||jsonb_build_object('delivery_line_id',v_il.delivery_line_id,'sales_order_line_id',v_il.sales_order_line_id);
 else
 select l.* into v_dl from sales.delivery_lines l join sales.deliveries d on d.id=l.document_id and d.tenant_id=l.tenant_id
 where l.tenant_id=v_t and l.id=(v_input->>'delivery_line_id')::uuid and d.legal_entity_id=v_e and d.branch_id=v_b
 and d.customer_id=(p_doc->>'customer_id')::uuid and d.status='posted' and d.document_date<=(p_doc->>'document_date')::date;
 if not found then raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
 -- An invoiced delivery must be credited against its invoice, preserving AR links.
 if exists(select 1 from sales.sales_invoice_lines l join sales.sales_invoices i on i.id=l.document_id
 where l.tenant_id=v_t and l.delivery_line_id=v_dl.id and i.status='posted') then
 raise exception using errcode='22023',message='RETURN_INVOICE_SOURCE_REQUIRED';end if;
 v_line:=v_dl.snapshot;v_limit:=v_dl.base_quantity;
 select coalesce(sum(l.base_quantity),0) into v_prior from sales.sales_return_lines l join sales.sales_returns r on r.id=l.document_id
 where l.tenant_id=v_t and l.delivery_line_id=v_dl.id and r.status='posted';
 v_input:=v_input||jsonb_build_object('sales_order_line_id',v_dl.sales_order_line_id);
 end if;
 if v_prior+v_q>v_limit then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 else
 if v_input->>'delivery_line_id' is not null then
 select l.* into v_dl from sales.delivery_lines l join sales.deliveries d on d.id=l.document_id and d.tenant_id=l.tenant_id
 where l.tenant_id=v_t and l.id=(v_input->>'delivery_line_id')::uuid and d.legal_entity_id=v_e and d.branch_id=v_b
 and d.customer_id=(p_doc->>'customer_id')::uuid and d.status='posted' and d.document_date<=(p_doc->>'document_date')::date;
 if not found then raise exception using errcode='22023',message='DELIVERY_SOURCE_INVALID';end if;
 if v_input->>'sales_order_line_id' is not null and (v_input->>'sales_order_line_id')::uuid<>v_dl.sales_order_line_id then
 raise exception using errcode='22023',message='SOURCE_LINE_MISMATCH';end if;
 v_input:=v_input||jsonb_build_object('sales_order_line_id',v_dl.sales_order_line_id);
 select coalesce(sum(l.base_quantity),0) into v_prior from sales.sales_invoice_lines l join sales.sales_invoices i on i.id=l.document_id
 where l.tenant_id=v_t and l.delivery_line_id=v_dl.id and i.status='posted';
 if v_prior+v_q>v_dl.base_quantity then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 end if;
 if v_input->>'sales_order_line_id' is not null then
 select * into v_order_line from sales.sales_order_lines where tenant_id=v_t and legal_entity_id=v_e and branch_id=v_b
 and id=(v_input->>'sales_order_line_id')::uuid;
 select * into v_order from sales.sales_orders where tenant_id=v_t and id=v_order_line.sales_order_id;
 if v_order.id is null or v_order.customer_id<>(p_doc->>'customer_id')::uuid
 or v_order.status not in ('confirmed','partially_reserved','reserved','fulfilled')
 or v_order.order_date>(p_doc->>'document_date')::date
 or (p_doc->>'sales_order_id' is not null and v_order.id<>(p_doc->>'sales_order_id')::uuid)
 or v_order.currency_code<>p_doc->>'currency_code' then raise exception using errcode='22023',message='ORDER_SOURCE_INVALID';end if;
 v_line:=sales.flow_exact_json(to_jsonb(v_order_line));
 if p_kind='delivery' then
 if v_order.id<>(p_doc->>'sales_order_id')::uuid or v_order.warehouse_id<>(p_doc->>'warehouse_id')::uuid then
 raise exception using errcode='22023',message='DELIVERY_WAREHOUSE_INVALID';end if;
 v_limit:=v_order_line.base_ordered_quantity-v_order_line.cancelled_quantity;v_prior:=v_order_line.delivered_quantity;
 else
 if v_order_line.product_kind='stocked' and v_dl.id is null then raise exception using errcode='22023',message='STOCKED_INVOICE_REQUIRES_DELIVERY';end if;
 v_limit:=case when v_order_line.product_kind='stocked' then v_order_line.delivered_quantity else v_order_line.base_ordered_quantity-v_order_line.cancelled_quantity end;
 v_prior:=v_order_line.invoiced_quantity;
 v_net:=round(v_order_line.taxable_amount*(v_prior+v_q)/v_order_line.base_ordered_quantity,v_scale)-round(v_order_line.taxable_amount*v_prior/v_order_line.base_ordered_quantity,v_scale);
 v_tax:=round(v_order_line.tax_amount*(v_prior+v_q)/v_order_line.base_ordered_quantity,v_scale)-round(v_order_line.tax_amount*v_prior/v_order_line.base_ordered_quantity,v_scale);
 end if;
 if v_prior+v_q>v_limit then raise exception using errcode='22023',message='SOURCE_QUANTITY_EXCEEDED';end if;
 elsif p_kind='sales_invoice' then
 -- Saved snapshots use line_discount_amount and nullable percentage keys;
 -- reconstruct the public pricing input without treating JSON null as a value.
 v_input:=jsonb_strip_nulls(v_input);
 if not (v_input ? 'discount_percent') and not (v_input ? 'discount_amount') and v_input ? 'line_discount_amount' then
 v_input:=v_input||jsonb_build_object('discount_amount',v_input->'line_discount_amount');end if;
 v_price:=sales.wave3_price_lines(v_t,v_e,(p_doc->>'document_date')::date,p_doc->>'currency_code',jsonb_build_array(v_input),null,null);
 v_line:=v_price->'lines'->0;
 if v_line->>'product_kind'='stocked' then raise exception using errcode='22023',message='STOCKED_INVOICE_REQUIRES_DELIVERY';end if;
 v_net:=(v_line->>'taxable_amount')::numeric;v_tax:=(v_line->>'tax_amount')::numeric;
 else raise exception using errcode='22023',message='ORDER_SOURCE_REQUIRED';end if;
 end if;
 select * into v_product from inventory.products where tenant_id=v_t and legal_entity_id=v_e and id=(v_line->>'product_id')::uuid and status='active' and can_sell;
 if not found then raise exception using errcode='22023',message='PRODUCT_REFERENCE_INACTIVE';end if;
 if p_kind='sales_invoice' and v_order_line.id is null and v_product.kind='stocked' then
 raise exception using errcode='22023',message='STOCKED_INVOICE_REQUIRES_DELIVERY';end if;
 v_line:=v_line||jsonb_build_object('product_kind',v_product.kind);
 if not exists(select 1 from inventory.units where tenant_id=v_t and id=(v_line->>'unit_id')::uuid and status='active') then
 raise exception using errcode='22023',message='UNIT_REFERENCE_INACTIVE';end if;
 if p_kind<>'sales_return' and v_line->>'tax_definition_id' is not null and not exists(
 select 1 from finance.tax_definitions t where t.tenant_id=v_t and t.legal_entity_id=v_e and t.id=(v_line->>'tax_definition_id')::uuid
 and t.status='active' and t.version=(v_line->>'tax_definition_version')::bigint
 and (p_doc->>'document_date')::date>=t.valid_from and (t.valid_to is null or (p_doc->>'document_date')::date<=t.valid_to)) then
 raise exception using errcode='22023',message='SOURCE_TAX_CHANGED';end if;
 v_txq:=v_q*(v_line->>'conversion_denominator')::numeric/(v_line->>'conversion_numerator')::numeric;
 if v_txq<>round(v_txq,6) then raise exception using errcode='22023',message='UNIT_CONVERSION_INEXACT';end if;
 -- Prorate source gross and discount snapshots just as net/tax amounts are
 -- prorated, so a partial document never displays the full original discount.
 v_fraction:=case when v_il.id is not null then v_il.base_quantity when v_order_line.id is not null then v_order_line.base_ordered_quantity else v_q end;
 if p_kind='delivery' or (p_kind='sales_return' and v_il.id is null) then v_gross:=0;v_discount_line:=0;
 elsif v_il.id is not null or v_order_line.id is not null then
 v_gross:=round(coalesce((v_line->>'gross_amount')::numeric,0)*(v_prior+v_q)/v_fraction,v_scale)-round(coalesce((v_line->>'gross_amount')::numeric,0)*v_prior/v_fraction,v_scale);
 v_discount_line:=round((coalesce((v_line->>'line_discount_amount')::numeric,0)+coalesce((v_line->>'header_discount_amount')::numeric,0))*(v_prior+v_q)/v_fraction,v_scale)
 -round((coalesce((v_line->>'line_discount_amount')::numeric,0)+coalesce((v_line->>'header_discount_amount')::numeric,0))*v_prior/v_fraction,v_scale);
 else v_gross:=(v_line->>'gross_amount')::numeric;v_discount_line:=coalesce((v_line->>'line_discount_amount')::numeric,0);end if;
 v_line:=v_line||jsonb_build_object('line_id',coalesce(v_input->>'line_id',v_input->>'id'),
 'line_number',v_ord,'quantity',v_txq::numeric(20,6)::text,'base_quantity',v_q::numeric(20,6)::text,'tracking_mode',v_product.tracking_mode,
 'sales_order_line_id',v_input->>'sales_order_line_id','delivery_line_id',v_input->>'delivery_line_id',
 'sales_invoice_line_id',v_input->>'sales_invoice_line_id','tracking',coalesce(v_input->'tracking','{}'::jsonb),
 'disposition',v_input->>'disposition','taxable_amount',v_net::text,'tax_amount',v_tax::text,'line_total',(v_net+v_tax)::text,
 'gross_amount',v_gross::text,'line_discount_amount',v_discount_line::text,'header_discount_amount','0');
 v_total:=v_total+v_net+v_tax;v_tax_total:=v_tax_total+v_tax;v_subtotal:=v_subtotal+v_gross;v_discount:=v_discount+v_discount_line;
 v_result:=v_result||jsonb_build_array(v_line);
 end loop;
 -- Repeated source lines could each pass an independent residual check: reject them.
 if exists(select 1 from jsonb_array_elements(v_result) x where x->>'sales_invoice_line_id' is not null
 group by x->>'sales_invoice_line_id' having count(*)>1)
 or exists(select 1 from jsonb_array_elements(v_result) x where x->>'delivery_line_id' is not null
 group by x->>'delivery_line_id' having count(*)>1)
 or exists(select 1 from jsonb_array_elements(v_result) x where x->>'sales_order_line_id' is not null
 group by x->>'sales_order_line_id' having count(*)>1) then raise exception using errcode='22023',message='DUPLICATE_SOURCE_LINE';end if;
 return jsonb_build_object('lines',v_result,'subtotal',v_subtotal::text,'discount_total',v_discount::text,
 'tax_total',v_tax_total::text,'grand_total',v_total::text,'base_total',case when p_kind='sales_return' then v_return_base::text else round(v_total*(p_doc->>'exchange_rate')::numeric,v_scale)::text end);
end $$;

-- Explicit grants only; private helpers are invoked by the named command owner.
do $$ declare v_proc record;begin for v_proc in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('sales','finance') and p.proname like 'flow_%'
 and p.proname not in ('flow_read_allowed','flow_exact_json') loop
 execute format('revoke all on function %I.%I(%s) from public,anon,authenticated',v_proc.nspname,v_proc.proname,v_proc.args);
end loop;end $$;
