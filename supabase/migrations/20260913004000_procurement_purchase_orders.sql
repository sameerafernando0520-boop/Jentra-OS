-- AC-309 / FR-338–339. Additive development candidate; no posting effects.
create table procurement.purchase_orders(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 supplier_id uuid not null,warehouse_id uuid not null,source_rfq_id uuid,source_quote_id uuid,source_requisition_id uuid,
 source_snapshot jsonb not null,document_date date not null,promised_date date not null,document_number text,
 currency_code text not null references core.currencies(code),exchange_rate_id uuid,exchange_rate numeric(20,10) not null,
 rate_date date not null,payment_terms text not null,delivery_terms text not null,
 subtotal numeric(20,6) not null,tax_total numeric(20,6) not null,total numeric(20,6) not null,base_total numeric(20,6) not null,
 status text not null default 'draft' check(status in('draft','pending_approval','approved','rejected','cancelled','closed')),
 version bigint not null default 1,revision integer not null default 1,revision_reason text,workflow_snapshot jsonb,
 submitted_by uuid references auth.users(id),submitted_at timestamptz,
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 commercial_editor_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,legal_entity_id,id),unique(source_quote_id),unique(source_rfq_id),
 unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id,source_rfq_id) references procurement.rfqs(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,source_quote_id) references procurement.supplier_quotes(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,source_requisition_id) references procurement.requisitions(tenant_id,legal_entity_id,id),
 check((source_rfq_id is not null and source_quote_id is not null and source_requisition_id is null)
  or (source_rfq_id is null and source_quote_id is null and source_requisition_id is not null)),
 foreign key(tenant_id,supplier_id) references crm.parties(tenant_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,exchange_rate_id) references finance.exchange_rates(tenant_id,legal_entity_id,id),
 check(promised_date>=document_date),check(exchange_rate>0),check(subtotal>=0 and tax_total>=0 and total>=0 and base_total>=0),
 check(length(trim(payment_terms)) between 1 and 1000 and length(trim(delivery_terms)) between 1 and 1000)
);
create table procurement.purchase_order_lines(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,order_id uuid not null,
 source_line_id uuid not null,product_id uuid,unit_id uuid not null,description text not null,
 quantity numeric(20,6) not null,unit_price numeric(20,6) not null,discount_percent numeric(9,6) not null,
 cancelled_quantity numeric(20,6) not null default 0,received_quantity numeric(20,6) not null default 0,
 billed_quantity numeric(20,6) not null default 0,detail jsonb not null,
 approved_extra_quantity numeric(20,6) not null default 0 check(approved_extra_quantity>=0),
 unique(tenant_id,legal_entity_id,id),unique(order_id,source_line_id),
 foreign key(tenant_id,legal_entity_id,order_id) references procurement.purchase_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,unit_id) references inventory.units(tenant_id,id),
 check(quantity>0 and unit_price>=0 and discount_percent between 0 and 100),
 check(cancelled_quantity>=0 and received_quantity>=0 and billed_quantity>=0),
 constraint purchase_order_lines_received_limit check(cancelled_quantity+received_quantity<=quantity+approved_extra_quantity)
);
create index purchase_orders_scope_page on procurement.purchase_orders(tenant_id,legal_entity_id,branch_id,id);
create index purchase_orders_scope_status on procurement.purchase_orders(tenant_id,legal_entity_id,branch_id,status,id);
create index purchase_orders_supplier on procurement.purchase_orders(tenant_id,legal_entity_id,supplier_id,status,id);
create table procurement.purchase_order_revisions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 order_id uuid not null,version bigint not null,revision integer not null,snapshot jsonb not null,
 actor_id uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(order_id,version),foreign key(tenant_id,legal_entity_id,order_id) references procurement.purchase_orders(tenant_id,legal_entity_id,id)
);
create function procurement.order_read_allowed(p_tenant uuid,p_entity uuid,p_order uuid) returns boolean
language sql stable security definer set search_path='' as $$select exists(select 1 from procurement.purchase_orders o
 where o.id=p_order and o.tenant_id=p_tenant and o.legal_entity_id=p_entity
 and core.has_permission(o.tenant_id,'procurement.orders.manage',o.legal_entity_id,o.branch_id))$$;
alter table procurement.purchase_orders enable row level security;alter table procurement.purchase_orders force row level security;
create policy order_read on procurement.purchase_orders for select to authenticated using(procurement.order_read_allowed(tenant_id,legal_entity_id,id));
do $$declare t text;begin
 foreach t in array array['purchase_order_lines','purchase_order_revisions'] loop
  execute format('alter table procurement.%I enable row level security',t);
  execute format('alter table procurement.%I force row level security',t);
  execute format('create policy order_read on procurement.%I for select to authenticated using(procurement.order_read_allowed(tenant_id,legal_entity_id,order_id))',t);
 end loop;
end $$;
create trigger order_revisions_immutable before update or delete on procurement.purchase_order_revisions
 for each row execute function workflow.reject_history_mutation();
revoke all on procurement.purchase_orders,procurement.purchase_order_lines,procurement.purchase_order_revisions from public,anon,authenticated;
grant select on procurement.purchase_orders,procurement.purchase_order_lines,procurement.purchase_order_revisions to authenticated;
revoke all on function procurement.order_read_allowed(uuid,uuid,uuid) from public,anon;
grant execute on function procurement.order_read_allowed(uuid,uuid,uuid) to authenticated;
create view api.purchase_orders with(security_invoker=true) as
select o.tenant_id,o.legal_entity_id,o.branch_id,o.id,o.status,
 sales.flow_exact_json(to_jsonb(o))||jsonb_build_object('lines',coalesce((select jsonb_agg(l.detail||jsonb_build_object(
  'line_id',l.id,'source_line_id',l.source_line_id,'quantity',l.quantity::text,'unit_price',l.unit_price::text,
  'cancelled_quantity',l.cancelled_quantity::text,'received_quantity',l.received_quantity::text,
  'billed_quantity',l.billed_quantity::text,'approved_extra_quantity',l.approved_extra_quantity::text,
  'remaining_quantity',greatest(0,l.quantity-l.cancelled_quantity-l.received_quantity)::text) order by l.id)
  from procurement.purchase_order_lines l where l.order_id=o.id),'[]')) detail from procurement.purchase_orders o;
grant select on api.purchase_orders to authenticated;
create function procurement.record_order_history(p_result jsonb) returns void language sql security definer set search_path='' as $$
 insert into procurement.purchase_order_revisions(tenant_id,legal_entity_id,order_id,version,revision,snapshot,actor_id)
 select (e->>'tenant_id')::uuid,(e->>'legal_entity_id')::uuid,(e->>'id')::uuid,(e->>'version')::bigint,
 (e->>'revision')::integer,e,auth.uid() from (select p_result->'entity' e) x
 on conflict(order_id,version) do nothing
$$;
revoke all on function procurement.record_order_history(jsonb) from public,anon,authenticated;

create function api.upsert_purchase_order(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_id uuid:=(p_payload->>'id')::uuid;v_command text:='procurement.order.upsert';v_hash text;v_result jsonb;v_before jsonb;v_entity jsonb;
 v_doc procurement.purchase_orders%rowtype;v_rfq procurement.rfqs%rowtype;v_quote procurement.supplier_quotes%rowtype;v_req procurement.requisitions%rowtype;v_source procurement.requisition_lines%rowtype;
 v_line jsonb;v_unit jsonb;v_old procurement.purchase_order_lines%rowtype;v_lines jsonb;v_snapshot jsonb;v_seen uuid[]:='{}';v_line_id uuid;
 v_supplier uuid;v_currency text;v_rate numeric;v_rate_id uuid;v_rate_date date;v_date date;v_promised date;v_warehouse uuid;
 v_q numeric;v_price numeric;v_discount numeric;v_gross numeric;v_net numeric;v_tax_amount numeric;v_tax finance.tax_definitions%rowtype;
 v_subtotal numeric:=0;v_tax_total numeric:=0;v_total numeric:=0;v_base text;v_scale integer;v_terms text;v_delivery text;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.orders.manage',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_id is null
 or jsonb_typeof(p_payload) is distinct from 'object' then raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);
 if v_result is not null then return v_result;end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('procurement.order:'||v_id::text,0));
 select * into v_doc from procurement.purchase_orders where id=v_id and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if found then
  select detail into v_before from api.purchase_orders where id=v_id;
  perform core.wave3_assert_expected_version(v_doc.version,p_expected_entity_version,v_before);
  if v_doc.status<>'draft' then raise exception using errcode='55000',message='ORDER_NOT_EDITABLE';end if;
  if (p_payload->>'source_rfq_id')::uuid is distinct from v_doc.source_rfq_id or (p_payload->>'source_quote_id')::uuid is distinct from v_doc.source_quote_id
   or (p_payload->>'source_requisition_id')::uuid is distinct from v_doc.source_requisition_id then
   raise exception using errcode='22023',message='SOURCE_IMMUTABLE';end if;
  v_lines:=p_payload->'lines';v_supplier:=(p_payload->>'supplier_id')::uuid;v_currency:=p_payload->>'currency_code';
  v_rate:=sales.wave3_decimal_string(p_payload->'exchange_rate','exchange_rate',10,true,0,null);
  v_rate_id:=(p_payload->>'exchange_rate_id')::uuid;v_rate_date:=(p_payload->>'rate_date')::date;
  v_terms:=trim(p_payload->>'payment_terms');v_delivery:=trim(p_payload->>'delivery_terms');
 else
  if p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  if p_payload->>'source_rfq_id' is null then
   select * into v_req from procurement.requisitions where id=(p_payload->>'source_requisition_id')::uuid and tenant_id=p_tenant_id
    and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for share;
   if not found or v_req.status<>'approved' then raise exception using errcode='55000',message='APPROVED_REQUISITION_REQUIRED';end if;
   perform core.wave3_assert_expected_version(v_req.version,(p_payload->>'source_requisition_version')::bigint,'{}');
   select detail into v_snapshot from api.purchase_requisitions where id=v_req.id;
   v_lines:=p_payload->'lines';v_supplier:=(p_payload->>'supplier_id')::uuid;v_currency:=p_payload->>'currency_code';
   v_rate:=sales.wave3_decimal_string(p_payload->'exchange_rate','exchange_rate',10,true,0,null);
   v_rate_id:=(p_payload->>'exchange_rate_id')::uuid;v_rate_date:=(p_payload->>'rate_date')::date;
   v_terms:=trim(p_payload->>'payment_terms');v_delivery:=trim(p_payload->>'delivery_terms');
  else
  select * into v_rfq from procurement.rfqs where id=(p_payload->>'source_rfq_id')::uuid and tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
  if v_rfq.status='ordered' then raise exception using errcode='55000',message='RFQ_ALREADY_ORDERED';end if;
  if v_rfq.id is null or v_rfq.status<>'selected' then raise exception using errcode='55000',message='SELECTED_RFQ_REQUIRED';end if;
  perform core.wave3_assert_expected_version(v_rfq.version,(p_payload->>'source_rfq_version')::bigint,'{}');
  select * into v_quote from procurement.supplier_quotes where id=v_rfq.selected_quote_id and rfq_id=v_rfq.id;
  if v_quote.id is distinct from (p_payload->>'source_quote_id')::uuid or not v_quote.complete or v_quote.valid_until<current_date then
   raise exception using errcode='55000',message='SELECTED_QUOTE_REQUIRED';end if;
  perform core.wave3_assert_expected_version(v_quote.version,(p_payload->>'source_quote_version')::bigint,'{}');
  select detail into v_snapshot from api.request_for_quotes where id=v_rfq.id;
  select jsonb_agg(detail||jsonb_build_object('line_id',gen_random_uuid())) into v_lines from procurement.supplier_quote_lines where quote_id=v_quote.id;
  v_supplier:=v_quote.supplier_id;v_currency:=v_quote.currency_code;v_rate:=v_quote.exchange_rate;v_rate_id:=v_quote.exchange_rate_id;
  v_rate_date:=v_quote.rate_date;v_terms:=v_quote.payment_terms;v_delivery:=v_quote.delivery_terms;
  end if;
 end if;
 v_warehouse:=(p_payload->>'warehouse_id')::uuid;v_date:=(p_payload->>'document_date')::date;v_promised:=(p_payload->>'promised_date')::date;
 if not exists(select 1 from core.warehouses where id=v_warehouse and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='active') then
  raise exception using errcode='22023',message='WAREHOUSE_INVALID';end if;
 if not exists(select 1 from crm.parties where id=v_supplier and tenant_id=p_tenant_id and status='active' and kind in('supplier','both')) then
  raise exception using errcode='22023',message='SUPPLIER_INVALID';end if;
 select currency_code,rounding_scale into v_base,v_scale from core.legal_entities where id=p_legal_entity_id and tenant_id=p_tenant_id;
 if v_rate<=0 or not exists(select 1 from core.currencies where code=v_currency and active) then raise exception using errcode='22023',message='CURRENCY_INVALID';end if;
 if v_currency=v_base then
  if v_rate<>1 or v_rate_id is not null then raise exception using errcode='22023',message='BASE_RATE_MUST_BE_ONE';end if;
 elsif not exists(select 1 from finance.exchange_rates where id=v_rate_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and status='active' and source_currency_code=v_currency and target_currency_code=v_base and rate=v_rate and effective_date=v_rate_date) then
  raise exception using errcode='22023',message='RATE_SNAPSHOT_INVALID';end if;
 if v_doc.id is not null and (v_doc.supplier_id<>v_supplier or v_doc.currency_code<>v_currency or v_doc.warehouse_id<>v_warehouse)
 and exists(select 1 from procurement.purchase_order_lines where order_id=v_id and (received_quantity>0 or billed_quantity>0)) then
  raise exception using errcode='55000',message='RECEIVED_ORDER_IDENTITY_IMMUTABLE';end if;
 if jsonb_typeof(v_lines) is distinct from 'array' or jsonb_array_length(v_lines) not between 1 and 500 then
  raise exception using errcode='22023',message='ORDER_LINES_REQUIRED';end if;
 if v_doc.id is null then
  insert into procurement.purchase_orders(id,tenant_id,legal_entity_id,branch_id,supplier_id,warehouse_id,source_rfq_id,source_quote_id,source_requisition_id,
   source_snapshot,document_date,promised_date,currency_code,exchange_rate_id,exchange_rate,rate_date,payment_terms,delivery_terms,
   subtotal,tax_total,total,base_total,created_by,updated_by,commercial_editor_id)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_supplier,v_warehouse,v_rfq.id,v_quote.id,v_req.id,v_snapshot,v_date,v_promised,
   v_currency,v_rate_id,v_rate,v_rate_date,v_terms,v_delivery,0,0,0,0,auth.uid(),auth.uid(),auth.uid());
 end if;
 for v_line in select value from jsonb_array_elements(v_lines) loop
  if v_req.id is not null then
   select * into v_source from procurement.requisition_lines where requisition_id=v_req.id and id=(v_line->>'source_line_id')::uuid;
   if not found then raise exception using errcode='22023',message='REQUISITION_SOURCE_LINE_INVALID';end if;
   v_line:=v_line||jsonb_build_object('product_id',v_source.product_id,'unit_id',v_source.unit_id,'description',v_source.description,
    'conversion_numerator',v_source.conversion_numerator::text,'conversion_denominator',v_source.conversion_denominator::text);
  end if;
  v_line_id:=(v_line->>'line_id')::uuid;
  if v_line_id is null or v_line_id=any(v_seen) then raise exception using errcode='22023',message='ORDER_LINE_ID_INVALID';end if;
  v_seen:=array_append(v_seen,v_line_id);
  select * into v_old from procurement.purchase_order_lines where id=v_line_id and order_id=v_id for update;
  if v_doc.id is not null and not found then raise exception using errcode='22023',message='ORDER_LINE_ID_INVALID';end if;
  if v_old.id is not null and ((v_line->>'source_line_id')::uuid is distinct from v_old.source_line_id
   or (v_line->>'product_id')::uuid is distinct from v_old.product_id or (v_line->>'unit_id')::uuid is distinct from v_old.unit_id) then
   raise exception using errcode='22023',message='SOURCE_LINE_IMMUTABLE';end if;
  v_q:=sales.wave3_decimal_string(v_line->'quantity','quantity',6,true,0,null);
  v_price:=sales.wave3_decimal_string(v_line->'unit_price','unit_price',6,true,0,null);
  v_discount:=sales.wave3_decimal_string(v_line->'discount_percent','discount_percent',6,true,0,100);
  if v_q<=0 or v_q<coalesce(v_old.received_quantity,0)+coalesce(v_old.cancelled_quantity,0) or v_q<coalesce(v_old.billed_quantity,0) then
   raise exception using errcode='22023',message='ORDER_QUANTITY_INVALID';end if;
  if not exists(select 1 from inventory.units where id=(v_line->>'unit_id')::uuid and tenant_id=p_tenant_id and status='active' and round(v_q,precision)=v_q)
  or (v_line->>'product_id' is not null and not exists(select 1 from inventory.products where id=(v_line->>'product_id')::uuid
   and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and can_purchase)) then
   raise exception using errcode='22023',message='PRODUCT_UNIT_INVALID';end if;
  v_unit:=inventory.resolve_product_unit(p_tenant_id,p_legal_entity_id,(v_line->>'product_id')::uuid,(v_line->>'unit_id')::uuid,
    v_line->'quantity',coalesce(v_old.detail->'conversion_numerator',v_line->'conversion_numerator'),coalesce(v_old.detail->'conversion_denominator',v_line->'conversion_denominator'));
  v_gross:=round(v_q*v_price,v_scale);v_discount:=round(v_gross*v_discount/100,v_scale);v_net:=v_gross-v_discount;v_tax_amount:=0;v_tax:=null;
  if v_line->>'tax_definition_id' is not null then
   select * into v_tax from finance.tax_definitions where id=(v_line->>'tax_definition_id')::uuid and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and status='active' and kind in('input','zero','exempt') and v_date>=valid_from and (valid_to is null or v_date<=valid_to);
   if not found then raise exception using errcode='22023',message='INPUT_TAX_INVALID';end if;
   v_tax_amount:=round(v_net*v_tax.rate/(case when v_tax.inclusive then 100+v_tax.rate else 100 end),v_scale);
   if v_tax.inclusive then v_net:=v_net-v_tax_amount;end if;
  end if;
  v_subtotal:=v_subtotal+v_net;v_tax_total:=v_tax_total+v_tax_amount;v_total:=v_total+v_net+v_tax_amount;
  v_line:=v_line||jsonb_build_object('discount_amount',v_discount::text,'tax_rate',coalesce(v_tax.rate,0)::text,
   'tax_inclusive',coalesce(v_tax.inclusive,false),'tax_definition_version',v_tax.version,
   'net_amount',v_net::text,'tax_amount',v_tax_amount::text,'line_total',(v_net+v_tax_amount)::text)||v_unit;
  insert into procurement.purchase_order_lines(id,tenant_id,legal_entity_id,order_id,source_line_id,product_id,unit_id,description,quantity,unit_price,discount_percent,detail)
  values(v_line_id,p_tenant_id,p_legal_entity_id,v_id,(v_line->>'source_line_id')::uuid,(v_line->>'product_id')::uuid,(v_line->>'unit_id')::uuid,
   v_line->>'description',v_q,v_price,(v_line->>'discount_percent')::numeric,v_line)
  on conflict(id) do update set quantity=excluded.quantity,unit_price=excluded.unit_price,discount_percent=excluded.discount_percent,detail=excluded.detail
  where procurement.purchase_order_lines.order_id=v_id;
  if not found then raise exception using errcode='22023',message='ORDER_LINE_ID_INVALID';end if;
 end loop;
 if exists(select 1 from procurement.purchase_order_lines where order_id=v_id and not(id=any(v_seen))) then raise exception using errcode='22023',message='ORDER_LINES_MUST_BE_RETAINED';end if;
 update procurement.purchase_orders set supplier_id=v_supplier,warehouse_id=v_warehouse,document_date=v_date,promised_date=v_promised,
  currency_code=v_currency,exchange_rate_id=v_rate_id,exchange_rate=v_rate,rate_date=v_rate_date,payment_terms=v_terms,delivery_terms=v_delivery,
  subtotal=v_subtotal,tax_total=v_tax_total,total=v_total,base_total=round(v_total*v_rate,v_scale),
  version=case when v_doc.id is null then version else version+1 end,updated_at=clock_timestamp(),updated_by=auth.uid(),commercial_editor_id=auth.uid() where id=v_id;
 if v_doc.id is null and v_rfq.id is not null then
  update procurement.rfqs set status='ordered',version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_rfq.id;
  insert into procurement.rfq_history(tenant_id,legal_entity_id,rfq_id,version,snapshot,actor_id)
  select tenant_id,legal_entity_id,id,(detail->>'version')::bigint,detail,auth.uid() from api.request_for_quotes where id=v_rfq.id;
 end if;
 select detail into v_entity from api.purchase_orders where id=v_id;
 v_result:=core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'purchase_order',v_id,p_idempotency_key,v_hash,v_before,v_entity,
  p_legal_entity_id,p_branch_id,'{}',null,jsonb_build_array(jsonb_build_object('topic','procurement.order.saved','payload','{}'::jsonb)));
 perform procurement.record_order_history(v_result);return v_result;
end $$;
revoke all on function api.upsert_purchase_order(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_purchase_order(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
