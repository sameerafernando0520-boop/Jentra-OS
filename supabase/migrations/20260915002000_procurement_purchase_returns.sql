-- AC-312 candidate. Immutable physical returns and supplier debit effects.
create table procurement.purchase_returns(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 source_kind text not null check(source_kind in('bill','receipt')),source_id uuid not null,supplier_id uuid not null,
 document_date date not null,document_number text not null,reference text not null,reason text not null,
 currency_code text not null,base_currency_code text not null,exchange_rate numeric(20,10) not null,
 total numeric(20,6) not null,base_total numeric(20,6) not null,tax_total numeric(20,6) not null,
 stock_movement_id uuid,journal_entry_id uuid,open_item_id uuid,source_snapshot jsonb not null,
 request_id uuid not null,command_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),foreign key(tenant_id,supplier_id) references crm.parties(tenant_id,id),
 foreign key(tenant_id,stock_movement_id) references inventory.stock_movements(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,open_item_id) references finance.open_items(tenant_id,id)
);
create index purchase_returns_scope_page on procurement.purchase_returns(tenant_id,legal_entity_id,branch_id,id);
create index purchase_returns_source on procurement.purchase_returns(tenant_id,source_kind,source_id,document_date);
create table procurement.purchase_return_lines(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,return_id uuid not null,
 bill_line_id uuid,receipt_line_id uuid,quantity numeric(20,6) not null check(quantity>0),detail jsonb not null,
 foreign key(tenant_id,return_id) references procurement.purchase_returns(tenant_id,id) deferrable initially deferred,
 foreign key(tenant_id,bill_line_id) references procurement.supplier_bill_lines(tenant_id,id),
 foreign key(tenant_id,receipt_line_id) references procurement.goods_receipt_lines(tenant_id,id),
 check(bill_line_id is not null or receipt_line_id is not null)
);
create index purchase_return_line_parent on procurement.purchase_return_lines(tenant_id,return_id);
create index purchase_return_line_bill on procurement.purchase_return_lines(tenant_id,bill_line_id);
create index purchase_return_line_receipt on procurement.purchase_return_lines(tenant_id,receipt_line_id);
do $$declare t text;begin
 foreach t in array array['purchase_returns','purchase_return_lines'] loop
  execute format('alter table procurement.%I enable row level security',t);
  execute format('alter table procurement.%I force row level security',t);
  execute format('create policy return_read on procurement.%I for select to authenticated using(core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,''procurement.returns.post'',legal_entity_id,branch_id))',t);
  execute format('revoke all on procurement.%I from public,anon,authenticated',t);
  execute format('grant select on procurement.%I to authenticated',t);
  execute format('create trigger immutable before update or delete on procurement.%I for each row execute function workflow.reject_history_mutation()',t);
 end loop;
end $$;
create view api.purchase_returns with(security_invoker=true) as select r.id,r.tenant_id,r.legal_entity_id,r.branch_id,
 sales.flow_exact_json(to_jsonb(r))||jsonb_build_object('status','posted','lines',coalesce((select jsonb_agg(l.detail order by l.id) from procurement.purchase_return_lines l where l.return_id=r.id),'[]')) detail
 from procurement.purchase_returns r;
grant select on api.purchase_returns to authenticated;
alter table inventory.stock_movements drop constraint stock_movements_movement_kind_check;
alter table inventory.stock_movements add constraint stock_movements_movement_kind_check
 check(movement_kind in('opening','delivery','sales_return','goods_receipt','goods_receipt_reversal','purchase_return'));

-- Extend candidate helpers without changing installed migration files. Fail on drift.
do $$declare v text;v_old text;begin
 v:=pg_get_functiondef('procurement.normalize_bill(uuid,uuid,uuid,jsonb)'::regprocedure);
 v_old:='v_available:=v_rl.accepted_quantity-v_already;';
 if position(v_old in v)=0 then raise exception 'BILL_HELPER_CONTRACT_DRIFT';end if;
 v:=replace(v,v_old,$s$v_already:=v_already+coalesce((select sum(quantity) from procurement.purchase_return_lines where receipt_line_id=v_rl.id and bill_line_id is null),0);
   v_available:=v_rl.accepted_quantity-v_already;$s$);execute v;
 v:=pg_get_functiondef('api.reverse_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)'::regprocedure);
 v_old:='if exists(select 1 from procurement.purchase_order_lines l join procurement.goods_receipt_lines r';
 if position(v_old in v)=0 then raise exception 'RECEIPT_HELPER_CONTRACT_DRIFT';end if;
 v:=replace(v,v_old,$s$if exists(select 1 from procurement.purchase_return_lines l join procurement.goods_receipt_lines r on r.id=l.receipt_line_id where r.receipt_id=v_id) then
 raise exception using errcode='55000',message='RETURNED_RECEIPT_CANNOT_REVERSE';end if;
 if exists(select 1 from procurement.purchase_order_lines l join procurement.goods_receipt_lines r$s$);execute v;
end $$;

create function api.post_purchase_return(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;v_source_id uuid:=(p_payload->>'source_id')::uuid;v_kind text:=p_payload->>'source_kind';
 v_date date:=(p_payload->>'document_date')::date;v_reason text:=trim(p_payload->>'reason');v_ref text:=trim(p_payload->>'reference');
 v_command text:='procurement.purchase_return.post';v_hash text;v_result jsonb;v_request uuid:=gen_random_uuid();v_number text;
 v_bill procurement.supplier_bills%rowtype;v_bl procurement.supplier_bill_lines%rowtype;v_receipt procurement.goods_receipts%rowtype;v_rl procurement.goods_receipt_lines%rowtype;
 v_controls procurement.supplier_bill_controls%rowtype;v_balance inventory.stock_balances%rowtype;v_value inventory.stock_valuations%rowtype;v_original inventory.stock_movement_lines%rowtype;
 v_doc jsonb;v_input jsonb;v_detail jsonb;v_lines jsonb:='[]';v_jlines jsonb:='[]';v_seen uuid[]:='{}';v_source_line uuid;v_line uuid;v_order uuid;v_product uuid;
 v_q numeric;v_limit numeric;v_prior numeric;v_consumed numeric;v_net numeric;v_tax numeric;v_base_tax numeric;v_base_net numeric;v_base_q numeric;v_cost numeric;v_tx_cost numeric;
 v_total numeric:=0;v_base_total numeric:=0;v_tax_total numeric:=0;v_credits numeric:=0;v_base_credits numeric:=0;v_prior_total numeric;v_prior_base numeric;
 v_supplier uuid;v_currency text;v_base text;v_rate numeric;v_scale integer;v_account uuid;v_ap uuid;v_tax_account uuid;v_grni uuid;
 v_warehouse uuid;v_movement uuid;v_journal uuid;v_open uuid;v_serials uuid[];v_serial uuid;v_lot uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.returns.post',p_legal_entity_id,p_branch_id);
 if p_client_timestamp is null or v_id is null or v_source_id is null or v_kind is null or v_kind not in('bill','receipt') or v_date is null
 or coalesce(length(v_reason),0) not between 1 and 1000 or coalesce(length(v_ref),0) not between 1 and 140
 or jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines') not between 1 and 500
 then raise exception using errcode='22023',message='RETURN_INPUT_INVALID';end if;
 if p_expected_entity_version is not null then raise exception using errcode='22023',message='IMMUTABLE_SOURCE_VERSION_NOT_SUPPORTED';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 perform pg_advisory_xact_lock(hashtextextended('purchase.return:'||v_id::text,0));
 if exists(select 1 from procurement.purchase_returns where id=v_id) then raise exception using errcode='23505',message='RETURN_ALREADY_POSTED';end if;
 if v_date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 select currency_code,rounding_scale into v_base,v_scale from core.legal_entities where id=p_legal_entity_id;
 select * into v_controls from procurement.supplier_bill_controls where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id;
 if not found then raise exception using errcode='55000',message='BILL_CONTROLS_REQUIRED';end if;
 if v_kind='bill' then
  select * into v_bill from procurement.supplier_bills where id=v_source_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='posted' for update;
  if not found or v_bill.document_date>v_date then raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
  v_supplier:=v_bill.supplier_id;v_currency:=v_bill.currency_code;v_rate:=v_bill.exchange_rate;v_doc:=sales.flow_exact_json(to_jsonb(v_bill));
  select account_id into v_ap from finance.journal_lines where journal_entry_id=v_bill.journal_entry_id and source_line_id is null and base_credit>0
   and account_id in(select id from finance.accounts where account_type='liability');
  if v_ap is null then raise exception using errcode='55000',message='SOURCE_AP_LINK_INVALID';end if;
 else
  select * into v_receipt from procurement.goods_receipts where id=v_source_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id;
  if not found or v_receipt.document_date>v_date then raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
  v_supplier:=(v_receipt.source_snapshot->>'supplier_id')::uuid;v_currency:=v_receipt.currency_code;v_rate:=v_receipt.exchange_rate;v_doc:=sales.flow_exact_json(to_jsonb(v_receipt));
 end if;
 -- Same order as bill posting and receipt reversal. Lock every affected PO before stock.
 if v_doc->>'base_currency_code' is distinct from v_base then raise exception using errcode='55000',message='SOURCE_BASE_CURRENCY_CHANGED';end if;
 for v_order in select distinct r.order_id from procurement.goods_receipts r where
  (v_kind='receipt' and r.id=v_source_id) or (v_kind='bill' and r.id in(select l.receipt_id from procurement.goods_receipt_lines l join procurement.supplier_bill_lines b on b.receipt_line_id=l.id where b.bill_id=v_source_id)) order by 1 loop
  perform 1 from procurement.purchase_orders where id=v_order for update;
  perform 1 from procurement.purchase_order_lines where order_id=v_order order by id for update;
 end loop;
 if exists(select 1 from procurement.purchase_returns where source_kind=v_kind and source_id=v_source_id and document_date>v_date)
 then raise exception using errcode='55000',message='LATER_RETURN_REQUIRES_REVIEW';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_controls.variance_account_id,'expense',v_currency);
 -- Prelock warehouse/product pairs in the same canonical order as stock consumers.
 for v_detail in select d from (select distinct jsonb_build_object('warehouse_id',r.warehouse_id,'product_id',l.detail->>'product_id') d
  from procurement.goods_receipt_lines l join procurement.goods_receipts r on r.id=l.receipt_id
  where (v_kind='receipt' and r.id=v_source_id) or (v_kind='bill' and l.id in(select receipt_line_id from procurement.supplier_bill_lines where bill_id=v_source_id))) pairs
  order by d->>'warehouse_id',d->>'product_id' loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||(v_detail->>'warehouse_id')||':'||(v_detail->>'product_id'),0));
 end loop;
 for v_input in select value from jsonb_array_elements(p_payload->'lines') order by value->>'source_line_id' loop
  v_line:=(v_input->>'line_id')::uuid;v_source_line:=(v_input->>'source_line_id')::uuid;v_rl:=null;v_bl:=null;v_original:=null;v_tax:=0;v_base_tax:=0;v_base_net:=0;
  if v_line is null or v_source_line is null or v_source_line=any(v_seen) then raise exception using errcode='22023',message='RETURN_LINE_IDENTITIES_INVALID';end if;
  v_seen:=array_append(v_seen,v_source_line);
  v_q:=sales.wave3_decimal_string(v_input->'quantity','quantity',6,true,0,null);
  if v_q<=0 then raise exception using errcode='22023',message='RETURN_QUANTITY_UNAVAILABLE';end if;
  if v_kind='bill' then
   select * into v_bl from procurement.supplier_bill_lines where id=v_source_line and bill_id=v_source_id;
   if not found then raise exception using errcode='22023',message='RETURN_SOURCE_LINE_INVALID';end if;
   select coalesce(sum(quantity),0) into v_prior from procurement.purchase_return_lines where bill_line_id=v_bl.id;
   v_limit:=v_bl.quantity;
   if v_q>v_limit-v_prior then raise exception using errcode='22023',message='RETURN_QUANTITY_UNAVAILABLE';end if;
   v_net:=round((v_bl.detail->>'net_amount')::numeric*(v_prior+v_q)/v_limit,v_scale)-round((v_bl.detail->>'net_amount')::numeric*v_prior/v_limit,v_scale);
   v_tax:=round((v_bl.detail->>'tax_amount')::numeric*(v_prior+v_q)/v_limit,v_scale)-round((v_bl.detail->>'tax_amount')::numeric*v_prior/v_limit,v_scale);
   if (v_bl.detail->>'tax_amount')::numeric>0 then
    select j.account_id,j.base_debit into v_tax_account,v_base_tax from finance.journal_lines j join finance.accounts a on a.id=j.account_id
     where j.journal_entry_id=v_bill.journal_entry_id and j.source_line_id=v_bl.id and a.account_type='asset' and j.base_debit>0;
    if v_tax_account is null then raise exception using errcode='55000',message='SOURCE_TAX_LINK_INVALID';end if;
    v_base_tax:=round(v_base_tax*(v_prior+v_q)/v_limit,v_scale)-round(v_base_tax*v_prior/v_limit,v_scale);
   end if;
   if v_bl.receipt_line_id is not null then select * into v_rl from procurement.goods_receipt_lines where id=v_bl.receipt_line_id;
   else v_account:=(v_bl.detail->>'expense_account_id')::uuid;v_base_net:=round(v_net*v_rate,v_scale);end if;
  else
   select * into v_rl from procurement.goods_receipt_lines where id=v_source_line and receipt_id=v_source_id;
   if not found then raise exception using errcode='22023',message='RETURN_SOURCE_LINE_INVALID';end if;
   select coalesce(sum(l.quantity),0) into v_consumed from procurement.supplier_bill_lines l join procurement.supplier_bills b on b.id=l.bill_id where l.receipt_line_id=v_rl.id and b.status='posted';
   v_consumed:=v_consumed+coalesce((select sum(quantity) from procurement.purchase_return_lines where receipt_line_id=v_rl.id and bill_line_id is null),0);
   if v_q>v_rl.accepted_quantity-v_consumed then raise exception using errcode='22023',message='RETURN_QUANTITY_UNAVAILABLE';end if;
   v_net:=round(v_rl.net_amount*(v_consumed+v_q)/v_rl.accepted_quantity,v_scale)-round(v_rl.net_amount*v_consumed/v_rl.accepted_quantity,v_scale);
   v_base_net:=round(v_rl.base_amount*(v_consumed+v_q)/v_rl.accepted_quantity,v_scale)-round(v_rl.base_amount*v_consumed/v_rl.accepted_quantity,v_scale);
   select account_id into v_grni from finance.journal_lines where journal_entry_id=v_receipt.journal_entry_id and source_line_id is null and base_credit>0;
   if v_net<>0 or v_base_net<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_grni,v_net,v_base_net,v_line));end if;
   v_base_total:=v_base_total+v_base_net;
  end if;
  if v_rl.id is not null then
   select * into v_receipt from procurement.goods_receipts where id=v_rl.receipt_id;
   if exists(select 1 from procurement.goods_receipt_reversals where receipt_id=v_receipt.id) then raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
   if v_receipt.document_date>v_date or exists(select 1 from procurement.supplier_bill_lines l join procurement.supplier_bills b on b.id=l.bill_id where l.receipt_line_id=v_rl.id and b.status='posted' and b.document_date>v_date)
   then raise exception using errcode='55000',message='LATER_RECEIPT_EVENT_REQUIRES_REVIEW';end if;
   if v_q>v_rl.accepted_quantity-coalesce((select sum(quantity) from procurement.purchase_return_lines where receipt_line_id=v_rl.id),0)
   then raise exception using errcode='22023',message='RETURN_QUANTITY_UNAVAILABLE';end if;
   v_base_q:=v_q*(v_rl.detail->>'conversion_numerator')::numeric/(v_rl.detail->>'conversion_denominator')::numeric;
   perform inventory.resolve_product_unit(p_tenant_id,p_legal_entity_id,(v_rl.detail->>'product_id')::uuid,(v_rl.detail->>'unit_id')::uuid,
    v_input->'quantity',v_rl.detail->'conversion_numerator',v_rl.detail->'conversion_denominator');
   if round(v_base_q,6)<>v_base_q or not exists(select 1 from inventory.units where id=(v_rl.detail->>'unit_id')::uuid and round(v_q,precision)=v_q)
   then raise exception using errcode='22023',message='RETURN_UNIT_PRECISION_INVALID';end if;
   v_product:=(v_rl.detail->>'product_id')::uuid;v_account:=(v_rl.detail->>'account_id')::uuid;
   select * into v_original from inventory.stock_movement_lines where stock_movement_id=v_receipt.stock_movement_id and source_line_id=v_rl.id;
  end if;
  if jsonb_typeof(coalesce(v_input->'serial_ids','[]'))<>'array' or jsonb_array_length(coalesce(v_input->'serial_ids','[]'))>1000 then raise exception using errcode='22023',message='SERIAL_LIST_INVALID';end if;
  select coalesce(array_agg(x::uuid order by x),'{}') into v_serials from jsonb_array_elements_text(coalesce(v_input->'serial_ids','[]')) x;
  v_cost:=0;v_tx_cost:=0;v_lot:=null;
  if v_original.id is not null then
   if v_warehouse is not null and v_warehouse<>v_receipt.warehouse_id then raise exception using errcode='22023',message='RETURN_SINGLE_WAREHOUSE_REQUIRED';end if;
   v_warehouse:=v_receipt.warehouse_id;
   select * into v_balance from inventory.stock_balances where tenant_id=p_tenant_id and warehouse_id=v_warehouse and product_id=v_product for update;
   select * into v_value from inventory.stock_valuations where stock_balance_id=v_balance.id for update;
   if v_balance.id is null or v_value.id is null or v_balance.on_hand_quantity-v_balance.allocated_quantity<v_base_q then raise exception using errcode='55000',message='RETURN_STOCK_UNAVAILABLE';end if;
   if exists(select 1 from inventory.stock_movement_lines where tenant_id=p_tenant_id and warehouse_id=v_warehouse and product_id=v_product and posting_date>v_date)
   then raise exception using errcode='55000',message='BACKDATED_STOCK_RETURN_REQUIRES_REVIEW';end if;
   v_lot:=v_original.lot_id;
   if v_lot is not null then
    update inventory.lot_balances set on_hand_quantity=on_hand_quantity-v_base_q,updated_by=auth.uid() where tenant_id=p_tenant_id and warehouse_id=v_warehouse and lot_id=v_lot and on_hand_quantity>=v_base_q;
    if not found then raise exception using errcode='55000',message='RETURN_LOT_UNAVAILABLE';end if;
   end if;
   if cardinality(v_original.serial_ids)>0 then
    if trunc(v_base_q)<>v_base_q or cardinality(v_serials)<>v_base_q or cardinality(v_serials)<>(select count(distinct s) from unnest(v_serials)s)
    then raise exception using errcode='22023',message='RETURN_SERIAL_INVALID';end if;
    foreach v_serial in array v_serials loop
     if not v_serial=any(v_original.serial_ids) then raise exception using errcode='22023',message='RETURN_SERIAL_INVALID';end if;
     update inventory.serials set status='disposed',updated_by=auth.uid() where id=v_serial and tenant_id=p_tenant_id and warehouse_id=v_warehouse and status='available';
     if not found then raise exception using errcode='55000',message='RETURN_SERIAL_UNAVAILABLE';end if;
    end loop;
   elsif cardinality(v_serials)>0 then raise exception using errcode='22023',message='RETURN_SERIAL_INVALID';end if;
   v_cost:=case when v_base_q=v_balance.on_hand_quantity then v_value.carrying_value else round(v_value.carrying_value*v_base_q/v_balance.on_hand_quantity,6) end;
   v_tx_cost:=round(v_cost/v_rate,v_scale);
   update inventory.stock_balances set on_hand_quantity=on_hand_quantity-v_base_q,updated_by=auth.uid() where id=v_balance.id;
   update inventory.stock_valuations set carrying_value=carrying_value-v_cost,updated_by=auth.uid() where id=v_value.id;
   if v_movement is null then
    v_movement:=gen_random_uuid();
    insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
    values(v_movement,p_tenant_id,p_legal_entity_id,p_branch_id,'purchase_return',v_id,v_warehouse,v_date,'purchase_return',v_request,p_command_id,v_request,auth.uid());
   end if;
   insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,original_movement_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,v_movement,v_warehouse,v_product,v_line,v_original.id,-v_base_q,-v_cost,v_lot,v_serials,v_date,auth.uid());
  else
   if cardinality(v_serials)>0 then raise exception using errcode='22023',message='RETURN_SERIAL_INVALID';end if;
   v_tx_cost:=v_net;v_cost:=case when v_kind='receipt' then v_base_net else round(v_net*v_rate,v_scale) end;
  end if;
  if v_cost<>0 or v_tx_cost<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_account,-v_tx_cost,-v_cost,v_line));end if;
  if v_tax<>0 or v_base_tax<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_tax_account,-v_tax,-v_base_tax,v_line));end if;
  v_credits:=v_credits+v_tx_cost+v_tax;v_base_credits:=v_base_credits+v_cost+v_base_tax;
  v_total:=v_total+v_net+v_tax;v_tax_total:=v_tax_total+v_tax;
  v_detail:=jsonb_build_object('line_id',v_line,'source_line_id',v_source_line,'bill_line_id',v_bl.id,'receipt_line_id',v_rl.id,
   'description',coalesce(v_bl.detail->>'description',v_rl.detail->>'description'),'quantity',v_q::text,'base_quantity',case when v_original.id is not null then v_base_q else 0 end::text,
   'net_amount',v_net::text,'tax_amount',v_tax::text,'lot_id',v_lot,'serial_ids',to_jsonb(v_serials),'source_snapshot',coalesce(v_bl.detail,v_rl.detail));
  insert into procurement.purchase_return_lines(id,tenant_id,legal_entity_id,branch_id,return_id,bill_line_id,receipt_line_id,quantity,detail)
  values(v_line,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_bl.id,v_rl.id,v_q,v_detail);
 end loop;
 if v_kind='bill' then
  select coalesce(sum(total),0),coalesce(sum(base_total),0) into v_prior_total,v_prior_base from procurement.purchase_returns where source_kind='bill' and source_id=v_source_id;
  v_base_total:=round((v_prior_total+v_total)*v_rate,v_scale)-v_prior_base;
  if v_total<=0 or v_base_total<=0 then raise exception using errcode='22023',message='RETURN_AMOUNT_BELOW_PRECISION';end if;
  v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_ap,v_total,v_base_total));
 end if;
 if v_credits<>v_total or v_base_credits<>v_base_total then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_controls.variance_account_id,v_credits-v_total,v_base_credits-v_base_total));end if;
 v_journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'document_date',v_date,'currency_code',v_currency,'base_currency_code',v_base,'exchange_rate',v_rate::text,'customer_id',v_supplier),v_jlines,'purchase_return',v_id,v_request,p_command_id);
 v_number:=sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,'purchase_return',v_date,auth.uid());
 if v_kind='bill' then
  v_open:=gen_random_uuid();
  insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
   original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
  values(v_open,p_tenant_id,p_legal_entity_id,p_branch_id,'AP',v_supplier,'purchase_return',v_id,v_number,v_currency,v_base,v_rate,-v_total,-v_base_total,v_date,v_date,v_journal,v_request,p_command_id,v_request,auth.uid());
 end if;
 insert into procurement.purchase_returns(id,tenant_id,legal_entity_id,branch_id,source_kind,source_id,supplier_id,document_date,document_number,reference,reason,
  currency_code,base_currency_code,exchange_rate,total,base_total,tax_total,stock_movement_id,journal_entry_id,open_item_id,source_snapshot,request_id,command_id,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_kind,v_source_id,v_supplier,v_date,v_number,v_ref,v_reason,v_currency,v_base,v_rate,v_total,v_base_total,v_tax_total,v_movement,v_journal,v_open,v_doc,v_request,p_command_id,auth.uid());
 select detail into v_result from api.purchase_returns where id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'purchase_return',v_id,p_idempotency_key,v_hash,null,v_result,p_legal_entity_id,p_branch_id,'{}',
  jsonb_build_object('from_status','draft','to_status','posted','reason',v_reason),jsonb_build_array(jsonb_build_object('topic','procurement.return.posted','payload',jsonb_build_object('return_id',v_id))),'[]',v_request,v_request);
end $$;
revoke all on function api.post_purchase_return(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.post_purchase_return(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function api.purchase_return_sources(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;v_next uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.returns.post',p_legal_entity_id,p_branch_id);
 if p_kind not in('bill','receipt') or p_kind is null or length(coalesce(p_search,''))>100 then raise exception using errcode='22023',message='RETURN_SEARCH_INVALID';end if;
 with candidates as (
  select b.id,b.document_number,b.document_date,b.currency_code,p.display_name supplier_name from procurement.supplier_bills b join crm.parties p on p.id=b.supplier_id
  where p_kind='bill' and b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id and b.branch_id=p_branch_id and b.status='posted'
   and (p_after is null or b.id>p_after) and (coalesce(p_search,'')='' or b.document_number ilike '%'||p_search||'%' or p.display_name ilike '%'||p_search||'%')
   and exists(select 1 from procurement.supplier_bill_lines l where l.bill_id=b.id and l.quantity>coalesce((select sum(quantity) from procurement.purchase_return_lines where bill_line_id=l.id),0))
  union all
  select r.id,r.document_number,r.document_date,r.currency_code,p.display_name from procurement.goods_receipts r join crm.parties p on p.id=(r.source_snapshot->>'supplier_id')::uuid
  where p_kind='receipt' and r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
   and (p_after is null or r.id>p_after) and not exists(select 1 from procurement.goods_receipt_reversals where receipt_id=r.id)
   and (coalesce(p_search,'')='' or r.document_number ilike '%'||p_search||'%' or p.display_name ilike '%'||p_search||'%')
   and exists(select 1 from procurement.goods_receipt_lines l where l.receipt_id=r.id and l.accepted_quantity>
    coalesce((select sum(b.quantity) from procurement.supplier_bill_lines b join procurement.supplier_bills h on h.id=b.bill_id where b.receipt_line_id=l.id and h.status='posted'),0)
    +coalesce((select sum(quantity) from procurement.purchase_return_lines where receipt_line_id=l.id and bill_line_id is null),0))
 ), bounded as(select * from candidates order by id limit 51)
 select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into v_rows from bounded x;
 if jsonb_array_length(v_rows)>50 then v_next:=(v_rows->49->>'id')::uuid;v_rows:=v_rows-50;end if;
 return jsonb_build_object('items',v_rows,'next_cursor',v_next);
end $$;
create function api.purchase_return_source(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_source_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_header jsonb;v_line jsonb;v_rows jsonb:='[]';v_l record;v_receipt procurement.goods_receipt_lines%rowtype;v_prior numeric;v_available numeric;v_stock_available numeric;v_serials jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.returns.post',p_legal_entity_id,p_branch_id);
 if p_kind='bill' then
  select sales.flow_exact_json(to_jsonb(b))||jsonb_build_object('supplier_name',p.display_name) into v_header from procurement.supplier_bills b join crm.parties p on p.id=b.supplier_id
  where b.id=p_source_id and b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id and b.branch_id=p_branch_id and b.status='posted';
 elsif p_kind='receipt' then
  select sales.flow_exact_json(to_jsonb(r))||jsonb_build_object('supplier_name',p.display_name) into v_header from procurement.goods_receipts r join crm.parties p on p.id=(r.source_snapshot->>'supplier_id')::uuid
  where r.id=p_source_id and r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and not exists(select 1 from procurement.goods_receipt_reversals where receipt_id=r.id);
 else raise exception using errcode='22023',message='RETURN_SOURCE_INVALID';end if;
 if v_header is null then raise exception using errcode='P0002',message='RETURN_SOURCE_NOT_FOUND';end if;
 for v_l in select id,quantity,receipt_line_id,detail from procurement.supplier_bill_lines where p_kind='bill' and bill_id=p_source_id
  union all select id,accepted_quantity,id,detail from procurement.goods_receipt_lines where p_kind='receipt' and receipt_id=p_source_id order by id limit 501 loop
  if jsonb_array_length(v_rows)>=500 then raise exception using errcode='54000',message='RETURN_SOURCE_LIMIT_EXCEEDED';end if;
  v_receipt:=null;v_serials:='[]';
  if p_kind='bill' then select coalesce(sum(quantity),0) into v_prior from procurement.purchase_return_lines where bill_line_id=v_l.id;
  else
   select coalesce(sum(l.quantity),0) into v_prior from procurement.supplier_bill_lines l join procurement.supplier_bills b on b.id=l.bill_id where l.receipt_line_id=v_l.id and b.status='posted';
   v_prior:=v_prior+coalesce((select sum(quantity) from procurement.purchase_return_lines where receipt_line_id=v_l.id and bill_line_id is null),0);
  end if;
  v_available:=greatest(v_l.quantity-v_prior,0);
  if v_l.receipt_line_id is not null then
   select * into v_receipt from procurement.goods_receipt_lines where id=v_l.receipt_line_id;
   v_stock_available:=v_receipt.accepted_quantity-coalesce((select sum(quantity) from procurement.purchase_return_lines where receipt_line_id=v_receipt.id),0);
   v_available:=least(v_available,greatest(v_stock_available,0));
   select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'available',s.status='available' and s.warehouse_id=r.warehouse_id) order by s.code),'[]') into v_serials
    from inventory.serials s join procurement.goods_receipts r on r.id=v_receipt.receipt_id where s.id in(select value::uuid from jsonb_array_elements_text(v_receipt.detail->'serial_ids'));
  end if;
  v_line:=v_l.detail||jsonb_build_object('source_line_id',v_l.id,'eligible_quantity',v_available::text,'returned_quantity',v_prior::text,
   'conversion_numerator',coalesce(v_receipt.detail->>'conversion_numerator','1'),'conversion_denominator',coalesce(v_receipt.detail->>'conversion_denominator','1'),
   'lot_code',v_receipt.detail->>'lot_code','serial_options',v_serials);
  v_rows:=v_rows||jsonb_build_array(v_line);
 end loop;
 return v_header||jsonb_build_object('source_kind',p_kind,'source_id',p_source_id,'lines',v_rows,
  'rounding_scale',(select rounding_scale from core.legal_entities where id=p_legal_entity_id));
end $$;
revoke all on function api.purchase_return_sources(uuid,uuid,uuid,text,uuid,text),api.purchase_return_source(uuid,uuid,uuid,text,uuid) from public,anon;
grant execute on function api.purchase_return_sources(uuid,uuid,uuid,text,uuid,text),api.purchase_return_source(uuid,uuid,uuid,text,uuid) to authenticated;
