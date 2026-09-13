-- AC-310 candidate. Reuses established inventory and journal tables; no business seed data.
create table procurement.receipt_controls(
 tenant_id uuid not null,legal_entity_id uuid primary key,grni_account_id uuid not null,expense_account_id uuid not null,
 maximum_over_receipt_percent numeric(9,6) not null default 0 check(maximum_over_receipt_percent between 0 and 100),
 version bigint not null default 1,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,grni_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,expense_account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
create table procurement.receipt_control_history(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,version bigint not null,
 snapshot jsonb not null,actor_id uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(legal_entity_id,version),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create table procurement.goods_receipts(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,order_id uuid not null,
 order_revision integer not null,warehouse_id uuid not null,document_date date not null,document_number text not null,
 reference text not null,source_snapshot jsonb not null,currency_code text not null,base_currency_code text not null,
 exchange_rate numeric(20,10) not null,net_amount numeric(20,6) not null,base_amount numeric(20,6) not null,
 stock_movement_id uuid,journal_entry_id uuid,request_id uuid not null,command_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id,order_id) references procurement.purchase_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,stock_movement_id) references inventory.stock_movements(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id)
);
create table procurement.receipt_allowances(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 order_id uuid not null,order_line_id uuid not null,order_version bigint not null,
 maximum_received_quantity numeric(20,6) not null,control_version bigint not null,reason text not null,
 approved_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(order_line_id,order_version),
 foreign key(tenant_id,legal_entity_id,order_id) references procurement.purchase_orders(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,order_line_id) references procurement.purchase_order_lines(tenant_id,legal_entity_id,id)
);
alter table procurement.receipt_allowances enable row level security;
alter table procurement.receipt_allowances force row level security;
create policy allowance_read on procurement.receipt_allowances for select to authenticated using(
 core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,'procurement.receipts.post',legal_entity_id,branch_id));
create trigger allowance_immutable before update or delete on procurement.receipt_allowances
 for each row execute function workflow.reject_history_mutation();
revoke all on procurement.receipt_allowances from public,anon,authenticated;
grant select on procurement.receipt_allowances to authenticated;
create index receipt_allowances_order on procurement.receipt_allowances(tenant_id,legal_entity_id,order_id,order_version);
create function api.approve_receipt_allowance(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='procurement.receipt_allowance.approve';v_hash text;v_result jsonb;v_po procurement.purchase_orders%rowtype;
 v_l procurement.purchase_order_lines%rowtype;v_c procurement.receipt_controls%rowtype;v_extra numeric;v_max numeric;v_id uuid:=(p_payload->>'id')::uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.receipts.post',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id);
 if v_id is null or p_client_timestamp is null or coalesce(length(trim(p_payload->>'reason')),0) not between 1 and 1000 then raise exception using errcode='22023',message='ALLOWANCE_REASON_REQUIRED';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_po from procurement.purchase_orders where id=(p_payload->>'order_id')::uuid and tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if not found then raise exception using errcode='P0002',message='ORDER_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version(v_po.version,p_expected_entity_version,to_jsonb(v_po));
 if v_po.status<>'approved' then raise exception using errcode='55000',message='APPROVED_ORDER_REQUIRED';end if;
 if auth.uid() in(v_po.created_by,v_po.commercial_editor_id,v_po.submitted_by) then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 select * into v_l from procurement.purchase_order_lines where id=(p_payload->>'order_line_id')::uuid and order_id=v_po.id for update;
 if not found then raise exception using errcode='22023',message='RECEIPT_SOURCE_INVALID';end if;
 select * into v_c from procurement.receipt_controls where legal_entity_id=p_legal_entity_id and tenant_id=p_tenant_id for share;
 if not found then raise exception using errcode='55000',message='RECEIPT_CONTROLS_REQUIRED';end if;
 v_extra:=sales.wave3_decimal_string(p_payload->'extra_quantity','extra_quantity',6,true,0,null);
 v_max:=v_l.quantity-v_l.cancelled_quantity+v_extra;
 if v_extra<=0 or v_c.maximum_over_receipt_percent<=0 or v_extra>v_l.quantity*v_c.maximum_over_receipt_percent/100
  or v_max<=v_l.received_quantity then raise exception using errcode='22023',message='ALLOWANCE_EXCEEDS_CONTROL';end if;
 insert into procurement.receipt_allowances(id,tenant_id,legal_entity_id,branch_id,order_id,order_line_id,order_version,maximum_received_quantity,control_version,reason,approved_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_po.id,v_l.id,v_po.version,v_max,v_c.version,trim(p_payload->>'reason'),auth.uid());
 select sales.flow_exact_json(to_jsonb(a)) into v_result from procurement.receipt_allowances a where id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'receipt_allowance',v_id,p_idempotency_key,v_hash,null,v_result,p_legal_entity_id,p_branch_id,
  jsonb_build_object('purchase_order_id',v_po.id),null,jsonb_build_array(jsonb_build_object('topic','procurement.receipt.allowance','payload',jsonb_build_object('order_id',v_po.id))));
end $$;
revoke all on function api.approve_receipt_allowance(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.approve_receipt_allowance(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
create table procurement.goods_receipt_lines(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,receipt_id uuid not null,
 order_line_id uuid not null,accepted_quantity numeric(20,6) not null,rejected_quantity numeric(20,6) not null,
 base_quantity numeric(20,6) not null,net_amount numeric(20,6) not null,base_amount numeric(20,6) not null,
 detail jsonb not null,unique(tenant_id,id),unique(receipt_id,order_line_id),
 foreign key(tenant_id,receipt_id) references procurement.goods_receipts(tenant_id,id) deferrable initially deferred,
 foreign key(tenant_id,legal_entity_id,order_line_id) references procurement.purchase_order_lines(tenant_id,legal_entity_id,id),
 check(accepted_quantity>=0 and rejected_quantity>=0 and accepted_quantity+rejected_quantity>0 and base_quantity>=0)
);
create table procurement.goods_receipt_reversals(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,receipt_id uuid not null unique,
 document_date date not null,reason text not null,stock_movement_id uuid,journal_entry_id uuid,
 request_id uuid not null,command_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 foreign key(tenant_id,receipt_id) references procurement.goods_receipts(tenant_id,id),
 foreign key(tenant_id,stock_movement_id) references inventory.stock_movements(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id)
);
create index goods_receipts_scope_page on procurement.goods_receipts(tenant_id,legal_entity_id,branch_id,id);
create index goods_receipts_order on procurement.goods_receipts(tenant_id,legal_entity_id,order_id,order_revision,id);
create index goods_receipt_source_line on procurement.goods_receipt_lines(tenant_id,legal_entity_id,order_line_id,receipt_id);
create index receipt_reversals_scope on procurement.goods_receipt_reversals(tenant_id,legal_entity_id,branch_id,id);
create index receipt_control_grni_fk on procurement.receipt_controls(tenant_id,legal_entity_id,grni_account_id);
create index receipt_control_expense_fk on procurement.receipt_controls(tenant_id,legal_entity_id,expense_account_id);
do $$declare t text;begin
 foreach t in array array['goods_receipts','goods_receipt_lines','goods_receipt_reversals','receipt_control_history'] loop
  execute format('create trigger immutable_receipt before update or delete on procurement.%I for each row execute function workflow.reject_history_mutation()',t);
 end loop;
 foreach t in array array['goods_receipts','goods_receipt_lines','goods_receipt_reversals','receipt_controls','receipt_control_history'] loop
  execute format('alter table procurement.%I enable row level security',t);
  execute format('alter table procurement.%I force row level security',t);
  if t in('receipt_controls','receipt_control_history') then
   execute format('create policy receipt_read on procurement.%I for select to authenticated using(core.is_tenant_member(tenant_id) and (core.has_permission(tenant_id,''finance.setup.manage'',legal_entity_id,null) or core.has_permission(tenant_id,''procurement.receipts.post'',legal_entity_id,null)))',t);
  else
   execute format('create policy receipt_read on procurement.%I for select to authenticated using(core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,''procurement.receipts.post'',legal_entity_id,branch_id))',t);
  end if;
  execute format('revoke all on procurement.%I from public,anon,authenticated',t);
  execute format('grant select on procurement.%I to authenticated',t);
 end loop;
end $$;
create view api.goods_receipts with(security_invoker=true) as select r.tenant_id,r.legal_entity_id,r.branch_id,r.id,
 sales.flow_exact_json(to_jsonb(r))||jsonb_build_object('status',case when x.id is null then 'posted' else 'reversed' end,
 'version',case when x.id is null then 1 else 2 end,'reversal',sales.flow_exact_json(to_jsonb(x)),
 'lines',coalesce((select jsonb_agg(l.detail order by l.id) from procurement.goods_receipt_lines l where l.receipt_id=r.id),'[]')) detail
 from procurement.goods_receipts r left join procurement.goods_receipt_reversals x on x.receipt_id=r.id;
grant select on api.goods_receipts to authenticated;
-- Additive constraint expansion preserves all existing permitted movement kinds.
alter table inventory.stock_movements drop constraint stock_movements_movement_kind_check;
alter table inventory.stock_movements add constraint stock_movements_movement_kind_check
 check(movement_kind in('opening','delivery','sales_return','goods_receipt','goods_receipt_reversal'));

create function api.upsert_receipt_controls(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='procurement.receipt_controls.upsert';v_hash text;v_result jsonb;v_before jsonb;v_entity jsonb;v_base text;
 v_old procurement.receipt_controls%rowtype;v_grni uuid:=(p_payload->>'grni_account_id')::uuid;v_expense uuid:=(p_payload->>'expense_account_id')::uuid;v_percent numeric;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.setup.manage',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'finance.setup.manage',p_legal_entity_id,null);
 if p_client_timestamp is null or (p_payload->>'id')::uuid is distinct from p_legal_entity_id then raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 perform pg_advisory_xact_lock(hashtextextended('receipt.controls:'||p_legal_entity_id::text,0));
 select * into v_old from procurement.receipt_controls where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id for update;
 if found then perform core.wave3_assert_expected_version(v_old.version,p_expected_entity_version,to_jsonb(v_old));
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 v_before:=to_jsonb(v_old);
 select currency_code into v_base from core.legal_entities where id=p_legal_entity_id and tenant_id=p_tenant_id;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_grni,'liability',v_base);
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_expense,'expense',v_base);
 v_percent:=sales.wave3_decimal_string(coalesce(p_payload->'maximum_over_receipt_percent','"0"'),'maximum_over_receipt_percent',6,true,0,100);
 insert into procurement.receipt_controls(tenant_id,legal_entity_id,grni_account_id,expense_account_id,maximum_over_receipt_percent,updated_by)
 values(p_tenant_id,p_legal_entity_id,v_grni,v_expense,v_percent,auth.uid()) on conflict(legal_entity_id) do update set
 grni_account_id=excluded.grni_account_id,expense_account_id=excluded.expense_account_id,maximum_over_receipt_percent=excluded.maximum_over_receipt_percent,version=procurement.receipt_controls.version+1,updated_by=auth.uid(),updated_at=clock_timestamp();
 select sales.flow_exact_json(to_jsonb(c))||jsonb_build_object('id',c.legal_entity_id) into v_entity from procurement.receipt_controls c where legal_entity_id=p_legal_entity_id;
 insert into procurement.receipt_control_history(tenant_id,legal_entity_id,version,snapshot,actor_id)
 values(p_tenant_id,p_legal_entity_id,(v_entity->>'version')::bigint,v_entity,auth.uid());
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'receipt_controls',p_legal_entity_id,p_idempotency_key,v_hash,v_before,v_entity,p_legal_entity_id,p_branch_id);
end $$;

create function api.post_goods_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;v_request uuid:=gen_random_uuid();v_command text:='procurement.goods_receipt.post';
 v_hash text;v_result jsonb;v_po procurement.purchase_orders%rowtype;v_ol procurement.purchase_order_lines%rowtype;
 v_controls procurement.receipt_controls%rowtype;v_product inventory.products%rowtype;v_balance inventory.stock_balances%rowtype;
 v_input jsonb;v_lines jsonb;v_detail jsonb;v_source jsonb;v_jlines jsonb:='[]';v_seen uuid[]:='{}';v_line_id uuid;
 v_q numeric;v_reject numeric;v_base_q numeric;v_prior numeric;v_amount numeric;v_base_amount numeric;v_total numeric:=0;v_base_total numeric:=0;
 v_scale integer;v_base text;v_date date:=(p_payload->>'document_date')::date;v_warehouse uuid:=(p_payload->>'warehouse_id')::uuid;
 v_movement uuid;v_journal uuid;v_account uuid;v_lot uuid;v_serial uuid;v_serials uuid[];v_code text;v_product_id uuid;
 v_num numeric;v_den numeric;v_precision integer;v_ref text:=trim(p_payload->>'reference');
 v_allowance procurement.receipt_allowances%rowtype;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.receipts.post',p_legal_entity_id,p_branch_id);
 if v_id is null or p_client_timestamp is null or p_legal_entity_id is null or p_branch_id is null or v_date is null
 or jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines') not between 1 and 500
 or coalesce(length(v_ref),0) not between 1 and 140 then raise exception using errcode='22023',message='INVALID_RECEIPT';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_po from procurement.purchase_orders where id=(p_payload->>'order_id')::uuid and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if not found then raise exception using errcode='P0002',message='ORDER_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version(v_po.version,p_expected_entity_version,to_jsonb(v_po));
 if v_po.status<>'approved' then raise exception using errcode='55000',message='APPROVED_ORDER_REQUIRED';end if;
 if v_warehouse is distinct from v_po.warehouse_id or not exists(select 1 from core.warehouses where id=v_warehouse and tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='active') then raise exception using errcode='22023',message='RECEIVING_WAREHOUSE_INVALID';end if;
 if v_date<v_po.document_date then raise exception using errcode='22023',message='RECEIPT_DATE_INVALID';end if;
 select currency_code,rounding_scale into v_base,v_scale from core.legal_entities where id=p_legal_entity_id and tenant_id=p_tenant_id;
 select * into v_controls from procurement.receipt_controls where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id for share;
 if not found then raise exception using errcode='55000',message='RECEIPT_CONTROLS_REQUIRED';end if;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_controls.grni_account_id,'liability',v_po.currency_code);
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 select detail into v_source from api.purchase_orders where id=v_po.id;
 v_source:=v_source||jsonb_build_object('_prior_negative_quantities','{}'::jsonb);
 -- Lock all source lines, then all stock keys in deterministic order before mutation.
 perform 1 from procurement.purchase_order_lines where order_id=v_po.id order by id for update;
 for v_product_id in select distinct l.product_id from procurement.purchase_order_lines l
 join jsonb_array_elements(p_payload->'lines') x on (x->>'order_line_id')::uuid=l.id
 where l.order_id=v_po.id and l.product_id is not null order by 1 loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||v_warehouse::text||':'||v_product_id::text,0));
 end loop;
 for v_input in select value from jsonb_array_elements(p_payload->'lines') order by value->>'order_line_id' loop
  v_line_id:=(v_input->>'line_id')::uuid;
  if v_line_id is null or v_line_id=any(v_seen) then raise exception using errcode='22023',message='RECEIPT_LINE_ID_INVALID';end if;
  v_seen:=array_append(v_seen,v_line_id);
  select * into v_ol from procurement.purchase_order_lines where id=(v_input->>'order_line_id')::uuid and order_id=v_po.id;
  if not found then raise exception using errcode='22023',message='RECEIPT_SOURCE_INVALID';end if;
  v_q:=sales.wave3_decimal_string(v_input->'accepted_quantity','accepted_quantity',6,true,0,null);
  v_reject:=sales.wave3_decimal_string(v_input->'rejected_quantity','rejected_quantity',6,true,0,null);
  if v_q+v_reject<=0 then raise exception using errcode='22023',message='RECEIPT_QUANTITY_REQUIRED';end if;
  v_allowance:=null;
  if v_q>greatest(0,v_ol.quantity-v_ol.cancelled_quantity-v_ol.received_quantity) then
   select * into v_allowance from procurement.receipt_allowances where order_line_id=v_ol.id and order_version=v_po.version
    and control_version=v_controls.version and approved_by<>auth.uid()
    and maximum_received_quantity>=v_ol.received_quantity+v_q;
   if not found then raise exception using errcode='22023',message='RECEIPT_EXCEEDS_REMAINING';end if;
  end if;
  if v_reject>0 and coalesce(length(trim(v_input->>'rejection_reason')),0) not between 1 and 1000 then raise exception using errcode='22023',message='REJECTION_REASON_REQUIRED';end if;
  select precision into v_precision from inventory.units where id=v_ol.unit_id and tenant_id=p_tenant_id and status='active';
  if not found or round(v_q,v_precision)<>v_q or round(v_reject,v_precision)<>v_reject then raise exception using errcode='22023',message='RECEIPT_UNIT_PRECISION_INVALID';end if;
  v_num:=(v_ol.detail->>'conversion_numerator')::numeric;v_den:=(v_ol.detail->>'conversion_denominator')::numeric;
  if v_num is null or v_den is null or v_num<=0 or v_den<=0 or mod(v_q*1000000*v_num,v_den)<>0 then raise exception using errcode='22023',message='BASE_QUANTITY_PRECISION_INVALID';end if;
  v_base_q:=v_q*v_num/v_den;v_product:=null;v_lot:=null;v_serials:='{}';
  if v_ol.product_id is not null then
   select * into v_product from inventory.products where id=v_ol.product_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and can_purchase for share;
   if not found or v_product.base_unit_id is distinct from (v_ol.detail->>'base_unit_id')::uuid then raise exception using errcode='22023',message='RECEIPT_PRODUCT_INVALID';end if;
   select precision into v_precision from inventory.units where id=v_product.base_unit_id and tenant_id=p_tenant_id and status='active';
   if not found or round(v_base_q,v_precision)<>v_base_q then raise exception using errcode='22023',message='BASE_QUANTITY_PRECISION_INVALID';end if;
  end if;
  -- EC-320: keep the historical ratio, but never accept a changed/inactive master
  -- as implicit approval for a new stock quantity.
  if v_q>0 then
   perform inventory.resolve_product_unit(p_tenant_id,p_legal_entity_id,v_ol.product_id,v_ol.unit_id,
    v_input->'accepted_quantity',v_ol.detail->'conversion_numerator',v_ol.detail->'conversion_denominator');
  end if;
  select coalesce(sum(l.accepted_quantity),0) into v_prior from procurement.goods_receipt_lines l join procurement.goods_receipts r on r.id=l.receipt_id
   where l.order_line_id=v_ol.id and r.order_revision=v_po.revision and not exists(select 1 from procurement.goods_receipt_reversals x where x.receipt_id=r.id);
  v_amount:=round((v_ol.detail->>'net_amount')::numeric*(v_prior+v_q)/v_ol.quantity,v_scale)-round((v_ol.detail->>'net_amount')::numeric*v_prior/v_ol.quantity,v_scale);
  v_base_amount:=round(round((v_ol.detail->>'net_amount')::numeric*(v_prior+v_q)/v_ol.quantity,v_scale)*v_po.exchange_rate,v_scale)
    -round(round((v_ol.detail->>'net_amount')::numeric*v_prior/v_ol.quantity,v_scale)*v_po.exchange_rate,v_scale);
  v_account:=case when v_product.kind='stocked' then finance.flow_account(p_tenant_id,p_legal_entity_id,v_product.inventory_account_id,'asset',v_po.currency_code)
   else finance.flow_account(p_tenant_id,p_legal_entity_id,coalesce(v_product.expense_account_id,v_controls.expense_account_id),'expense',v_po.currency_code) end;
  if jsonb_typeof(coalesce(v_input->'serial_codes','[]'))<>'array' or jsonb_array_length(coalesce(v_input->'serial_codes','[]'))>1000 then raise exception using errcode='22023',message='SERIAL_LIST_INVALID';end if;
  if v_q>0 and v_product.kind='stocked' then
   -- Match delivery lock order: balance then valuation, before lot/serial rows.
   insert into inventory.stock_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,v_warehouse,v_product.id,0,auth.uid(),auth.uid())
   on conflict(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id) do nothing;
   select * into v_balance from inventory.stock_balances where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and warehouse_id=v_warehouse and product_id=v_product.id for update;
   insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,v_balance.id,0,auth.uid(),auth.uid()) on conflict(tenant_id,stock_balance_id) do nothing;
   perform 1 from inventory.stock_valuations where stock_balance_id=v_balance.id for update;
   if exists(select 1 from inventory.stock_movement_lines where tenant_id=p_tenant_id and warehouse_id=v_warehouse
    and product_id=v_product.id and posting_date>v_date) then raise exception using errcode='55000',message='BACKDATED_STOCK_RECEIPT_REQUIRES_REVIEW';end if;
   -- Immutable negative movement totals distinguish later consumption without
   -- relying on transaction-start timestamps or retaining an unbounded ID list.
   v_source:=jsonb_set(v_source,array['_prior_negative_quantities',v_product.id::text],
    to_jsonb((select coalesce(sum(-base_quantity),0)::text from inventory.stock_movement_lines
     where tenant_id=p_tenant_id and warehouse_id=v_warehouse and product_id=v_product.id and base_quantity<0)));
   if v_product.tracking_mode='lot' then
    if coalesce(length(trim(v_input->>'lot_code')),0) not between 1 and 100 or jsonb_array_length(coalesce(v_input->'serial_codes','[]'))<>0
     or (v_input->>'expiry_date')::date<v_date then raise exception using errcode='22023',message='LOT_IDENTITY_INVALID';end if;
    insert into inventory.lots(tenant_id,legal_entity_id,product_id,code,manufacture_date,expiry_date,created_by,updated_by)
    values(p_tenant_id,p_legal_entity_id,v_product.id,trim(v_input->>'lot_code'),(v_input->>'manufacture_date')::date,(v_input->>'expiry_date')::date,auth.uid(),auth.uid())
    on conflict(tenant_id,product_id,code) do nothing;
    select id into v_lot from inventory.lots where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and product_id=v_product.id
     and code=trim(v_input->>'lot_code') and status='saleable' and manufacture_date is not distinct from (v_input->>'manufacture_date')::date
     and expiry_date is not distinct from (v_input->>'expiry_date')::date for update;
    if not found then raise exception using errcode='22023',message='LOT_METADATA_CONFLICT';end if;
    insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
    values(p_tenant_id,p_legal_entity_id,p_branch_id,v_warehouse,v_product.id,v_lot,v_base_q,auth.uid(),auth.uid())
    on conflict(tenant_id,warehouse_id,lot_id) do update set on_hand_quantity=inventory.lot_balances.on_hand_quantity+excluded.on_hand_quantity,updated_by=auth.uid();
   elsif v_product.tracking_mode='serial' then
    if v_input->>'lot_code' is not null or trunc(v_base_q)<>v_base_q or jsonb_array_length(coalesce(v_input->'serial_codes','[]'))<>v_base_q then raise exception using errcode='22023',message='SERIAL_COUNT_INVALID';end if;
    for v_code in select value#>>'{}' from jsonb_array_elements(v_input->'serial_codes') where jsonb_typeof(value)='string' order by 1 loop
     if length(trim(v_code)) not between 1 and 100 or v_code<>trim(v_code) then raise exception using errcode='22023',message='SERIAL_IDENTITY_INVALID';end if;
     insert into inventory.serials(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,code,created_by,updated_by)
     values(p_tenant_id,p_legal_entity_id,p_branch_id,v_warehouse,v_product.id,v_code,auth.uid(),auth.uid()) returning id into v_serial;
     v_serials:=array_append(v_serials,v_serial);
    end loop;
    if cardinality(v_serials)<>v_base_q then raise exception using errcode='22023',message='SERIAL_IDENTITY_INVALID';end if;
   elsif v_input->>'lot_code' is not null or jsonb_array_length(coalesce(v_input->'serial_codes','[]'))<>0 then raise exception using errcode='22023',message='TRACKING_NOT_ALLOWED';end if;
   if v_movement is null then
    v_movement:=gen_random_uuid();
    insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
    values(v_movement,p_tenant_id,p_legal_entity_id,p_branch_id,'goods_receipt',v_id,v_warehouse,v_date,'goods_receipt',v_request,p_command_id,v_request,auth.uid());
   end if;
   insert into inventory.stock_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,v_warehouse,v_product.id,v_base_q,auth.uid(),auth.uid())
   on conflict(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id) do update set on_hand_quantity=inventory.stock_balances.on_hand_quantity+excluded.on_hand_quantity,updated_by=auth.uid() returning * into v_balance;
   insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,v_balance.id,v_base_amount,auth.uid(),auth.uid())
   on conflict(tenant_id,stock_balance_id) do update set carrying_value=inventory.stock_valuations.carrying_value+excluded.carrying_value,updated_by=auth.uid();
   insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,v_movement,v_warehouse,v_product.id,v_line_id,v_base_q,v_base_amount,v_lot,v_serials,v_date,auth.uid());
  end if;
  v_detail:=jsonb_build_object('line_id',v_line_id,'order_line_id',v_ol.id,'product_id',v_ol.product_id,'description',v_ol.description,
   'unit_id',v_ol.unit_id,'conversion_numerator',v_num::text,'conversion_denominator',v_den::text,
   'accepted_quantity',v_q::text,'rejected_quantity',v_reject::text,'rejection_reason',v_input->>'rejection_reason',
   'base_quantity',v_base_q::text,'net_amount',v_amount::text,'base_amount',v_base_amount::text,'account_id',v_account,
   'lot_id',v_lot,'lot_code',v_input->>'lot_code','serial_ids',to_jsonb(v_serials),'serial_codes',coalesce(v_input->'serial_codes','[]'),'source_snapshot',v_ol.detail,
   'allowance',sales.flow_exact_json(to_jsonb(v_allowance)));
  insert into procurement.goods_receipt_lines(id,tenant_id,legal_entity_id,branch_id,receipt_id,order_line_id,accepted_quantity,rejected_quantity,base_quantity,net_amount,base_amount,detail)
  values(v_line_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_ol.id,v_q,v_reject,v_base_q,v_amount,v_base_amount,v_detail);
  update procurement.purchase_order_lines set received_quantity=received_quantity+v_q,
   approved_extra_quantity=greatest(approved_extra_quantity,received_quantity+v_q+cancelled_quantity-quantity) where id=v_ol.id;
  if v_amount<>0 or v_base_amount<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_account,v_amount,v_base_amount,v_line_id));end if;
  v_total:=v_total+v_amount;v_base_total:=v_base_total+v_base_amount;
 end loop;
 if v_total<>0 or v_base_total<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_controls.grni_account_id,-v_total,-v_base_total));end if;
 v_journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'document_date',v_date,'currency_code',v_po.currency_code,'base_currency_code',v_base,'exchange_rate',v_po.exchange_rate::text,'customer_id',v_po.supplier_id),v_jlines,'goods_receipt',v_id,v_request,p_command_id);
 insert into procurement.goods_receipts(id,tenant_id,legal_entity_id,branch_id,order_id,order_revision,warehouse_id,document_date,document_number,reference,
  source_snapshot,currency_code,base_currency_code,exchange_rate,net_amount,base_amount,stock_movement_id,journal_entry_id,request_id,command_id,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_po.id,v_po.revision,v_warehouse,v_date,
  sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,'goods_receipt',v_date,auth.uid()),v_ref,v_source,v_po.currency_code,v_base,v_po.exchange_rate,v_total,v_base_total,v_movement,v_journal,v_request,p_command_id,auth.uid());
 update procurement.purchase_orders set version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_po.id;
 perform procurement.record_order_history(jsonb_build_object('entity',(select detail from api.purchase_orders where id=v_po.id)));
 select detail into v_result from api.goods_receipts where id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'goods_receipt',v_id,p_idempotency_key,v_hash,null,v_result,p_legal_entity_id,p_branch_id,
  jsonb_build_object('purchase_order_id',v_po.id),jsonb_build_object('from_status','draft','to_status','posted'),
  jsonb_build_array(jsonb_build_object('topic','procurement.receipt.posted','payload',jsonb_build_object('receipt_id',v_id))),'[]',v_request,v_request);
end $$;

create function api.reverse_goods_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'document_id')::uuid;v_reverse uuid:=gen_random_uuid();v_request uuid:=gen_random_uuid();
 v_command text:='procurement.goods_receipt.reverse';v_hash text;v_result jsonb;v_before jsonb;v_r procurement.goods_receipts%rowtype;
 v_po procurement.purchase_orders%rowtype;v_line procurement.goods_receipt_lines%rowtype;v_m inventory.stock_movement_lines%rowtype;
 v_balance inventory.stock_balances%rowtype;v_value inventory.stock_valuations%rowtype;v_movement uuid;v_journal uuid;v_jlines jsonb:='[]';
 v_date date:=(p_payload->>'document_date')::date;v_reason text:=trim(p_payload->>'reason');v_product uuid;v_serial uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.receipts.post',p_legal_entity_id,p_branch_id);
 if p_client_timestamp is null or v_id is null or v_date is null or coalesce(length(v_reason),0) not between 1 and 1000 then raise exception using errcode='22023',message='REVERSAL_REASON_DATE_REQUIRED';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_r from procurement.goods_receipts where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id;
 if not found then raise exception using errcode='P0002',message='RECEIPT_NOT_FOUND';end if;
 -- Same aggregate lock order as posting; a receipt row is immutable.
 select * into v_po from procurement.purchase_orders where id=v_r.order_id for update;
 select detail into v_before from api.goods_receipts where id=v_id;
 perform core.wave3_assert_expected_version((v_before->>'version')::bigint,p_expected_entity_version,v_before);
 if v_before->>'status'<>'posted' then raise exception using errcode='55000',message='RECEIPT_ALREADY_REVERSED';end if;
 if v_date<v_r.document_date then raise exception using errcode='22023',message='REVERSAL_DATE_INVALID';end if;
 perform 1 from procurement.purchase_order_lines where order_id=v_po.id order by id for update;
 if exists(select 1 from procurement.purchase_order_lines l join procurement.goods_receipt_lines r on r.order_line_id=l.id where r.receipt_id=v_id and l.billed_quantity>0)
 then raise exception using errcode='55000',message='BILLED_RECEIPT_REQUIRES_RETURN';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 for v_product in select distinct product_id from inventory.stock_movement_lines where stock_movement_id=v_r.stock_movement_id order by 1 loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||v_r.warehouse_id::text||':'||v_product::text,0));
 end loop;
 for v_m in select * from inventory.stock_movement_lines where stock_movement_id=v_r.stock_movement_id order by product_id,id loop
  select * into v_balance from inventory.stock_balances where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and warehouse_id=v_r.warehouse_id and product_id=v_m.product_id for update;
  select * into v_value from inventory.stock_valuations where stock_balance_id=v_balance.id for update;
  if v_balance.id is null or v_value.id is null or v_balance.on_hand_quantity-v_balance.allocated_quantity<v_m.base_quantity
   or v_value.carrying_value<v_m.base_value or (v_balance.on_hand_quantity=v_m.base_quantity and v_value.carrying_value<>v_m.base_value)
   or (select coalesce(sum(-base_quantity),0) from inventory.stock_movement_lines
      where tenant_id=p_tenant_id and warehouse_id=v_r.warehouse_id and product_id=v_m.product_id and base_quantity<0
       and (v_movement is null or stock_movement_id<>v_movement))
     is distinct from (v_r.source_snapshot#>>array['_prior_negative_quantities',v_m.product_id::text])::numeric
  then raise exception using errcode='55000',message='CONSUMED_RECEIPT_REQUIRES_RETURN';end if;
  if v_m.lot_id is not null then
   update inventory.lot_balances set on_hand_quantity=on_hand_quantity-v_m.base_quantity,updated_by=auth.uid()
   where tenant_id=p_tenant_id and warehouse_id=v_r.warehouse_id and lot_id=v_m.lot_id and on_hand_quantity>=v_m.base_quantity;
   if not found then raise exception using errcode='55000',message='RECEIPT_LOT_UNAVAILABLE';end if;
  end if;
  foreach v_serial in array v_m.serial_ids loop
   update inventory.serials set status='disposed',updated_by=auth.uid() where id=v_serial and tenant_id=p_tenant_id
    and warehouse_id=v_r.warehouse_id and status='available';
   if not found then raise exception using errcode='55000',message='RECEIPT_SERIAL_UNAVAILABLE';end if;
  end loop;
  update inventory.stock_balances set on_hand_quantity=on_hand_quantity-v_m.base_quantity,updated_by=auth.uid() where id=v_balance.id;
  update inventory.stock_valuations set carrying_value=carrying_value-v_m.base_value,updated_by=auth.uid() where id=v_value.id;
  if v_movement is null then
   v_movement:=gen_random_uuid();
   insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
   values(v_movement,p_tenant_id,p_legal_entity_id,p_branch_id,'goods_receipt_reversal',v_reverse,v_r.warehouse_id,v_date,'goods_receipt_reversal',v_request,p_command_id,v_request,auth.uid());
  end if;
  insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,original_movement_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,v_movement,v_r.warehouse_id,v_m.product_id,v_m.source_line_id,v_m.id,-v_m.base_quantity,-v_m.base_value,v_m.lot_id,v_m.serial_ids,v_date,auth.uid());
 end loop;
 for v_line in select * from procurement.goods_receipt_lines where receipt_id=v_id order by order_line_id loop
  update procurement.purchase_order_lines set received_quantity=received_quantity-v_line.accepted_quantity where id=v_line.order_line_id;
 end loop;
 select coalesce(jsonb_agg(finance.flow_jline(account_id,transaction_credit-transaction_debit,base_credit-base_debit,source_line_id) order by line_number),'[]')
 into v_jlines from finance.journal_lines where journal_entry_id=v_r.journal_entry_id;
 v_journal:=finance.flow_post_journal(to_jsonb(v_r)||jsonb_build_object('document_date',v_date,'customer_id',v_po.supplier_id),v_jlines,'goods_receipt_reversal',v_reverse,v_request,p_command_id);
 insert into procurement.goods_receipt_reversals(id,tenant_id,legal_entity_id,branch_id,receipt_id,document_date,reason,stock_movement_id,journal_entry_id,request_id,command_id,created_by)
 values(v_reverse,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_date,v_reason,v_movement,v_journal,v_request,p_command_id,auth.uid());
 update procurement.purchase_orders set version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_po.id;
 perform procurement.record_order_history(jsonb_build_object('entity',(select detail from api.purchase_orders where id=v_po.id)));
 select detail into v_result from api.goods_receipts where id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'goods_receipt',v_id,p_idempotency_key,v_hash,v_before,v_result,p_legal_entity_id,p_branch_id,'{}',
 jsonb_build_object('from_status','posted','to_status','reversed','reason',v_reason),jsonb_build_array(jsonb_build_object('topic','procurement.receipt.reversed','payload',jsonb_build_object('receipt_id',v_id))),'[]',v_request,v_request);
end $$;
revoke all on function api.upsert_receipt_controls(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.post_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.reverse_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_receipt_controls(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.post_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.reverse_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function api.goods_receipt_reference_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_resource text,p_after uuid default null,p_search text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_items jsonb;v_search text:=lower(trim(coalesce(p_search,'')));v_next uuid;begin
 if p_resource='receipt_orders' then
  perform core.wave3_require_scope(p_tenant_id,'procurement.receipts.post',p_legal_entity_id,p_branch_id);
 else
  perform core.wave3_require_scope(p_tenant_id,'finance.setup.manage',p_legal_entity_id,p_branch_id);
  perform core.require_permission(p_tenant_id,'finance.setup.manage',p_legal_entity_id,null);
 end if;
 if p_legal_entity_id is null or p_branch_id is null or length(v_search)>100 then raise exception using errcode='22023',message='REFERENCE_SCOPE_INVALID';end if;
 if p_resource='receipt_orders' then
  select jsonb_agg(jsonb_build_object('id',id,'code',detail->>'document_number','name',detail->>'payment_terms','detail',detail) order by id)
  into v_items from(select * from api.purchase_orders where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and status='approved' and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(detail->>'document_number'))>0) order by id limit 51) x;
 elsif p_resource='receipt_accounts' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'account_type',account_type) order by id)
  into v_items from(select * from finance.accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and is_posting and status='active'
   and account_type in('expense','liability') and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51) x;
 elsif p_resource='receipt_controls' then
  select jsonb_agg(sales.flow_exact_json(to_jsonb(c))||jsonb_build_object('id',c.legal_entity_id)) into v_items from procurement.receipt_controls c
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id;
 else raise exception using errcode='22023',message='REFERENCE_RESOURCE_INVALID';end if;
 v_items:=coalesce(v_items,'[]');
 if p_resource='receipt_orders' then
  select coalesce(jsonb_agg(jsonb_set(item,'{detail,lines}',coalesce((select jsonb_agg(line||jsonb_build_object('_tracking_mode',coalesce(p.tracking_mode,'none'),
   '_allowance',coalesce((select sales.flow_exact_json(to_jsonb(a)) from procurement.receipt_allowances a
     join procurement.receipt_controls c on c.legal_entity_id=a.legal_entity_id and c.tenant_id=a.tenant_id
     where a.order_line_id=(line->>'line_id')::uuid and a.order_version=(item#>>'{detail,version}')::bigint and a.control_version=c.version),'null'::jsonb)) order by line->>'line_id')
   from jsonb_array_elements(item#>'{detail,lines}') line left join inventory.products p
    on p.id=(line->>'product_id')::uuid and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id),'[]')) order by item->>'id'),'[]')
   into v_items from jsonb_array_elements(v_items) item;
 end if;
 if jsonb_array_length(v_items)>50 then v_next:=(v_items->49->>'id')::uuid;v_items:=v_items-50;end if;
 return jsonb_build_object('items',v_items,'next_cursor',v_next);
end $$;
revoke all on function api.goods_receipt_reference_options(uuid,uuid,uuid,text,uuid,text) from public,anon;
grant execute on function api.goods_receipt_reference_options(uuid,uuid,uuid,text,uuid,text) to authenticated;
