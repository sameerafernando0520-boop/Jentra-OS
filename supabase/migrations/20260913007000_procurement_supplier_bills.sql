-- AC-311 candidate: receipt matching and AP; no persistent setup or business fixtures.
create table procurement.supplier_bill_controls(
 tenant_id uuid not null,legal_entity_id uuid primary key,payable_account_id uuid not null,input_tax_account_id uuid not null,variance_account_id uuid not null,
 amount_tolerance numeric(20,6) not null default 0 check(amount_tolerance>=0),price_percent_tolerance numeric(9,6) not null default 0 check(price_percent_tolerance between 0 and 100),
 version bigint not null default 1,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,payable_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,input_tax_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,variance_account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
create table procurement.supplier_bills(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,supplier_id uuid not null,
 supplier_reference text not null check(length(trim(supplier_reference)) between 1 and 140),document_date date not null,due_date date not null,
 document_number text,currency_code text not null references core.currencies(code),base_currency_code text not null references core.currencies(code),
 exchange_rate_id uuid,exchange_rate numeric(20,10) not null,subtotal numeric(20,6) not null,tax_total numeric(20,6) not null,total numeric(20,6) not null,base_total numeric(20,6) not null,
 status text not null default 'draft' check(status in('draft','posted','cancelled')),version bigint not null default 1,
 match_result jsonb not null,journal_entry_id uuid,open_item_id uuid,created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,supplier_id) references crm.parties(tenant_id,id),foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,exchange_rate_id) references finance.exchange_rates(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),foreign key(tenant_id,open_item_id) references finance.open_items(tenant_id,id),
 check(due_date>=document_date and total>=0 and base_total>=0 and exchange_rate>0)
);
create unique index supplier_reference_unique on procurement.supplier_bills(tenant_id,legal_entity_id,supplier_id,lower(trim(supplier_reference))) where status<>'cancelled';
create index supplier_bills_scope_page on procurement.supplier_bills(tenant_id,legal_entity_id,branch_id,id);
create index supplier_bills_party_date on procurement.supplier_bills(tenant_id,legal_entity_id,supplier_id,document_date,id);
create table procurement.supplier_bill_lines(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,bill_id uuid not null,
 receipt_line_id uuid,quantity numeric(20,6) not null check(quantity>0),detail jsonb not null,
 unique(tenant_id,id),unique(bill_id,receipt_line_id),
 foreign key(tenant_id,bill_id) references procurement.supplier_bills(tenant_id,id),
 foreign key(tenant_id,receipt_line_id) references procurement.goods_receipt_lines(tenant_id,id)
);
create index supplier_bill_receipt_qty on procurement.supplier_bill_lines(tenant_id,receipt_line_id,bill_id);
create table procurement.supplier_bill_history(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 bill_id uuid not null,version bigint not null,snapshot jsonb not null,actor_id uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(bill_id,version),foreign key(tenant_id,bill_id) references procurement.supplier_bills(tenant_id,id)
);
create table procurement.supplier_bill_match_approvals(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,bill_id uuid not null,
 bill_version bigint not null,match_hash text not null,control_version bigint not null,reason text not null,
 approved_by uuid not null references auth.users(id),created_at timestamptz not null default now(),unique(bill_id,bill_version,match_hash),
 foreign key(tenant_id,bill_id) references procurement.supplier_bills(tenant_id,id)
);
create table procurement.supplier_bill_control_history(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,version bigint not null,snapshot jsonb not null,
 actor_id uuid not null references auth.users(id),created_at timestamptz not null default now(),unique(legal_entity_id,version),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id)
);
create function procurement.bill_read_allowed(p_tenant uuid,p_entity uuid,p_branch uuid) returns boolean language sql stable security definer set search_path='' as $$
 select core.is_tenant_member(p_tenant) and (core.has_permission(p_tenant,'procurement.bills.view',p_entity,p_branch)
 or core.has_permission(p_tenant,'procurement.bills.manage',p_entity,p_branch) or core.has_permission(p_tenant,'procurement.bills.post',p_entity,p_branch))$$;
revoke all on function procurement.bill_read_allowed(uuid,uuid,uuid) from public,anon;
grant execute on function procurement.bill_read_allowed(uuid,uuid,uuid) to authenticated;
do $$declare t text;begin
 foreach t in array array['supplier_bills','supplier_bill_lines','supplier_bill_history','supplier_bill_match_approvals','supplier_bill_controls','supplier_bill_control_history'] loop
  execute format('alter table procurement.%I enable row level security',t);execute format('alter table procurement.%I force row level security',t);
  if t in('supplier_bill_controls','supplier_bill_control_history') then
   execute format('create policy bill_read on procurement.%I for select to authenticated using(core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,''finance.setup.manage'',legal_entity_id,null))',t);
  else execute format('create policy bill_read on procurement.%I for select to authenticated using(procurement.bill_read_allowed(tenant_id,legal_entity_id,branch_id))',t);end if;
  execute format('revoke all on procurement.%I from public,anon,authenticated',t);execute format('grant select on procurement.%I to authenticated',t);
  if t in('supplier_bill_history','supplier_bill_match_approvals','supplier_bill_control_history') then
   execute format('create trigger immutable before update or delete on procurement.%I for each row execute function workflow.reject_history_mutation()',t);end if;
 end loop;
end $$;
create trigger bill_immutable before update or delete on procurement.supplier_bills for each row execute function sales.flow_protect_document();
create function procurement.bill_line_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from procurement.supplier_bills where id=coalesce((to_jsonb(new)->>'bill_id')::uuid,(to_jsonb(old)->>'bill_id')::uuid) and status<>'draft') then
 raise exception using errcode='55000',message='BILL_NOT_EDITABLE';end if;return coalesce(new,old);end $$;
create trigger bill_line_immutable before insert or update or delete on procurement.supplier_bill_lines for each row execute function procurement.bill_line_guard();
revoke all on function procurement.bill_line_guard() from public,anon,authenticated;
create view api.supplier_bills with(security_invoker=true) as select b.tenant_id,b.legal_entity_id,b.branch_id,b.id,b.status,
 sales.flow_exact_json(to_jsonb(b))||jsonb_build_object('lines',coalesce((select jsonb_agg(l.detail order by l.id) from procurement.supplier_bill_lines l where l.bill_id=b.id),'[]'),
 'match_approvals',coalesce((select jsonb_agg(sales.flow_exact_json(to_jsonb(a)) order by a.created_at) from procurement.supplier_bill_match_approvals a where a.bill_id=b.id and a.bill_version=b.version),'[]')) detail
 from procurement.supplier_bills b;
grant select on api.supplier_bills to authenticated;
-- Preserve AR predicates while preventing receivables-only users from reading AP.
alter policy permitted_read on finance.open_items using(core.is_tenant_member(tenant_id) and
 ((kind='AR' and core.has_permission(tenant_id,'finance.receivables.view',legal_entity_id,branch_id))
 or (kind='AP' and procurement.bill_read_allowed(tenant_id,legal_entity_id,branch_id))));
create or replace function finance.flow_visible_residual(p_tenant uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_o finance.open_items%rowtype;begin
 select * into v_o from finance.open_items where tenant_id=p_tenant and id=p_id and kind='AR';
 if not found or not core.is_tenant_member(p_tenant) or not core.has_permission(p_tenant,'finance.receivables.view',v_o.legal_entity_id,v_o.branch_id) then return null;end if;
 return finance.flow_residual(p_tenant,p_id);end $$;
create or replace view api.receivable_balances with(security_invoker=true) as
select o.id,o.tenant_id,o.legal_entity_id,o.branch_id,o.party_id,o.currency_code,o.source_type,o.source_id,o.posting_date,o.due_date,
 sales.flow_exact_json(to_jsonb(o))||finance.flow_visible_residual(o.tenant_id,o.id) as detail from finance.open_items o where o.kind='AR';

create function api.upsert_supplier_bill_controls(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='procurement.bill_controls.upsert';v_hash text;v_result jsonb;v_old procurement.supplier_bill_controls%rowtype;v_base text;
 v_ap uuid:=(p_payload->>'payable_account_id')::uuid;v_tax uuid:=(p_payload->>'input_tax_account_id')::uuid;v_var uuid:=(p_payload->>'variance_account_id')::uuid;
 v_amount numeric;v_percent numeric;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.setup.manage',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'finance.setup.manage',p_legal_entity_id,null);
 if (p_payload->>'id')::uuid is distinct from p_legal_entity_id or p_client_timestamp is null then raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 perform pg_advisory_xact_lock(hashtextextended('bill.controls:'||p_legal_entity_id::text,0));
 select * into v_old from procurement.supplier_bill_controls where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id for update;
 if found then perform core.wave3_assert_expected_version(v_old.version,p_expected_entity_version,to_jsonb(v_old));
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 select currency_code into v_base from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_ap,'liability',v_base);perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_tax,'asset',v_base);
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_var,'expense',v_base);
 v_amount:=sales.wave3_decimal_string(p_payload->'amount_tolerance','amount_tolerance',6,true,0,null);
 v_percent:=sales.wave3_decimal_string(p_payload->'price_percent_tolerance','price_percent_tolerance',6,true,0,100);
 insert into procurement.supplier_bill_controls(tenant_id,legal_entity_id,payable_account_id,input_tax_account_id,variance_account_id,amount_tolerance,price_percent_tolerance,updated_by)
 values(p_tenant_id,p_legal_entity_id,v_ap,v_tax,v_var,v_amount,v_percent,auth.uid()) on conflict(legal_entity_id) do update set
 payable_account_id=excluded.payable_account_id,input_tax_account_id=excluded.input_tax_account_id,variance_account_id=excluded.variance_account_id,
 amount_tolerance=excluded.amount_tolerance,price_percent_tolerance=excluded.price_percent_tolerance,version=procurement.supplier_bill_controls.version+1,updated_by=auth.uid(),updated_at=clock_timestamp();
 select sales.flow_exact_json(to_jsonb(c))||jsonb_build_object('id',c.legal_entity_id) into v_result from procurement.supplier_bill_controls c where legal_entity_id=p_legal_entity_id;
 insert into procurement.supplier_bill_control_history(tenant_id,legal_entity_id,version,snapshot,actor_id) values(p_tenant_id,p_legal_entity_id,(v_result->>'version')::bigint,v_result,auth.uid());
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'supplier_bill_controls',p_legal_entity_id,p_idempotency_key,v_hash,to_jsonb(v_old),v_result,p_legal_entity_id,p_branch_id);
end $$;

-- Private normalization is shared by save, match approval and posting.
create function procurement.normalize_bill(p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_c procurement.supplier_bill_controls%rowtype;v_input jsonb;v_lines jsonb:='[]';v_exceptions jsonb:='[]';v_source jsonb;v_detail jsonb;
 v_rl procurement.goods_receipt_lines%rowtype;v_r procurement.goods_receipts%rowtype;v_tax finance.tax_definitions%rowtype;v_product inventory.products%rowtype;
 v_q numeric;v_price numeric;v_discount numeric;v_gross numeric;v_net numeric;v_tax_amount numeric;v_total numeric:=0;v_subtotal numeric:=0;v_tax_total numeric:=0;
 v_already numeric;v_available numeric;v_accrual numeric;v_accrual_base numeric;v_expected numeric;v_diff numeric;v_exception jsonb;
 v_currency text:=p_payload->>'currency_code';v_date date:=(p_payload->>'document_date')::date;v_due date:=(p_payload->>'due_date')::date;
 v_supplier uuid:=(p_payload->>'supplier_id')::uuid;v_id uuid:=(p_payload->>'id')::uuid;v_line_id uuid;v_seen uuid[]:='{}';v_receipts uuid[]:='{}';
 v_scale integer;v_base text;v_rate jsonb;v_account uuid;v_grni uuid;v_blocked boolean:=false;
begin
 if v_date is null or v_due is null or v_due<v_date or v_id is null or coalesce(length(trim(p_payload->>'supplier_reference')),0) not between 1 and 140
  or jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines') not between 1 and 500 then raise exception using errcode='22023',message='BILL_INPUT_INVALID';end if;
 if not exists(select 1 from crm.parties where id=v_supplier and tenant_id=p_tenant and status='active' and kind in('supplier','both')) then raise exception using errcode='22023',message='SUPPLIER_INVALID';end if;
 select * into v_c from procurement.supplier_bill_controls where tenant_id=p_tenant and legal_entity_id=p_entity;
 if not found then raise exception using errcode='55000',message='BILL_CONTROLS_REQUIRED';end if;
 select currency_code,rounding_scale into v_base,v_scale from core.legal_entities where id=p_entity and tenant_id=p_tenant;
 v_rate:=finance.flow_rate(p_tenant,p_entity,v_currency,v_date,(p_payload->>'exchange_rate_id')::uuid);
 for v_input in select value from jsonb_array_elements(p_payload->'lines') order by value->>'line_id' loop
  v_line_id:=(v_input->>'line_id')::uuid;
  if v_line_id is null or v_line_id=any(v_seen) then raise exception using errcode='22023',message='BILL_LINE_ID_INVALID';end if;
  v_seen:=array_append(v_seen,v_line_id);v_exception:='[]';v_rl:=null;v_r:=null;v_product:=null;v_source:='{}';v_account:=null;v_grni:=null;v_accrual:=0;v_accrual_base:=0;
  v_q:=sales.wave3_decimal_string(v_input->'quantity','quantity',6,true,0,null);if v_q<=0 then raise exception using errcode='22023',message='BILL_QUANTITY_INVALID';end if;
  v_price:=sales.wave3_decimal_string(v_input->'unit_price','unit_price',6,true,0,null);
  v_discount:=sales.wave3_decimal_string(v_input->'discount_percent','discount_percent',6,true,0,100);
  v_gross:=round(v_q*v_price,v_scale);v_net:=v_gross-round(v_gross*v_discount/100,v_scale);v_tax_amount:=0;v_tax:=null;
  if v_input->>'tax_definition_id' is not null then
   select * into v_tax from finance.tax_definitions where id=(v_input->>'tax_definition_id')::uuid and tenant_id=p_tenant and legal_entity_id=p_entity
    and status='active' and kind in('input','zero','exempt') and valid_from<=v_date and (valid_to is null or valid_to>=v_date);
   if not found then raise exception using errcode='22023',message='INPUT_TAX_INVALID';end if;
   v_tax_amount:=round(v_net*v_tax.rate/(case when v_tax.inclusive then 100+v_tax.rate else 100 end),v_scale);
   if v_tax.inclusive then v_net:=v_net-v_tax_amount;end if;
  end if;
  if v_input->>'receipt_line_id' is not null then
   if (v_input->>'receipt_line_id')::uuid=any(v_receipts) then raise exception using errcode='22023',message='DUPLICATE_RECEIPT_LINE';end if;
   v_receipts:=array_append(v_receipts,(v_input->>'receipt_line_id')::uuid);
   select * into v_rl from procurement.goods_receipt_lines where id=(v_input->>'receipt_line_id')::uuid and tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch;
   if not found then raise exception using errcode='22023',message='RECEIPT_SOURCE_INVALID';end if;
   select * into v_r from procurement.goods_receipts where id=v_rl.receipt_id;
   if (v_r.source_snapshot->>'supplier_id')::uuid<>v_supplier then raise exception using errcode='22023',message='RECEIPT_SUPPLIER_MISMATCH';end if;
   v_source:=v_rl.detail->'source_snapshot';
   select coalesce(sum(l.quantity),0) into v_already from procurement.supplier_bill_lines l join procurement.supplier_bills b on b.id=l.bill_id
    where l.receipt_line_id=v_rl.id and b.status='posted' and b.id<>v_id;
   v_available:=v_rl.accepted_quantity-v_already;
   if v_r.document_date>v_date or exists(select 1 from procurement.goods_receipt_reversals where receipt_id=v_r.id) or v_q>v_available or v_rl.accepted_quantity<=0 then
    v_blocked:=true;v_exception:=v_exception||jsonb_build_array(jsonb_build_object('code','RECEIPT_QUANTITY_UNAVAILABLE','available_quantity',greatest(v_available,0)::text,'requested_quantity',v_q::text));
   else
    v_accrual_base:=round(v_rl.base_amount*(v_already+v_q)/v_rl.accepted_quantity,v_scale)-round(v_rl.base_amount*v_already/v_rl.accepted_quantity,v_scale);
    v_accrual:=round(v_rl.net_amount*(v_already+v_q)/v_rl.accepted_quantity,v_scale)-round(v_rl.net_amount*v_already/v_rl.accepted_quantity,v_scale);
   end if;
   if not exists(select 1 from inventory.units where id=(v_source->>'unit_id')::uuid and tenant_id=p_tenant and status='active' and round(v_q,precision)=v_q) then raise exception using errcode='22023',message='BILL_UNIT_PRECISION_INVALID';end if;
   select account_id into v_grni from finance.journal_lines where journal_entry_id=v_r.journal_entry_id and base_credit>0 and source_line_id is null;
   if v_rl.base_amount<>0 and v_grni is null then raise exception using errcode='55000',message='RECEIPT_ACCRUAL_LINK_INVALID';end if;
   v_diff:=abs(v_price-(v_source->>'unit_price')::numeric);
   if v_diff>abs((v_source->>'unit_price')::numeric)*v_c.price_percent_tolerance/100 then
    v_exception:=v_exception||jsonb_build_array(jsonb_build_object('code','PRICE_VARIANCE','expected',v_source->>'unit_price','actual',v_price::text,'difference',v_diff::text));end if;
   if v_discount<>(v_source->>'discount_percent')::numeric then v_exception:=v_exception||jsonb_build_array(jsonb_build_object('code','DISCOUNT_VARIANCE','expected',v_source->>'discount_percent','actual',v_discount::text));end if;
   if (v_input->>'tax_definition_id') is distinct from (v_source->>'tax_definition_id') or coalesce(v_tax.rate,0)<>coalesce((v_source->>'tax_rate')::numeric,0)
    or coalesce(v_tax.inclusive,false)<>coalesce((v_source->>'tax_inclusive')::boolean,false) then
    v_exception:=v_exception||jsonb_build_array(jsonb_build_object('code','TAX_MISMATCH','expected_rate',v_source->>'tax_rate','actual_rate',coalesce(v_tax.rate,0)::text));end if;
   if v_currency<>v_r.currency_code then v_exception:=v_exception||jsonb_build_array(jsonb_build_object('code','CURRENCY_MISMATCH','expected',v_r.currency_code,'actual',v_currency));end if;
   v_expected:=case when v_currency=v_r.currency_code then v_accrual else round(v_accrual_base/(v_rate->>'exchange_rate')::numeric,v_scale) end;
   if abs(v_net-v_expected)>v_c.amount_tolerance then v_exception:=v_exception||jsonb_build_array(jsonb_build_object('code','TOTAL_VARIANCE','expected',v_expected::text,'actual',v_net::text,'difference',(v_net-v_expected)::text));end if;
  else
   perform core.require_permission(p_tenant,'procurement.bills.post',p_entity,p_branch);
   if v_input->>'product_id' is not null then
    select * into v_product from inventory.products where id=(v_input->>'product_id')::uuid and tenant_id=p_tenant and legal_entity_id=p_entity and status='active' and can_purchase and kind in('non_stocked','service');
    if not found then raise exception using errcode='22023',message='DIRECT_BILL_NONSTOCK_REQUIRED';end if;
   end if;
   if coalesce(length(trim(v_input->>'description')),0) not between 1 and 500 then raise exception using errcode='22023',message='DIRECT_BILL_DESCRIPTION_REQUIRED';end if;
   v_account:=finance.flow_account(p_tenant,p_entity,coalesce(v_product.expense_account_id,(v_input->>'expense_account_id')::uuid),'expense',v_currency);
  end if;
  v_detail:=jsonb_build_object('line_id',v_line_id,'receipt_line_id',v_rl.id,'order_id',v_r.order_id,'order_line_id',v_rl.order_line_id,
   'description',coalesce(v_source->>'description',v_input->>'description'),'product_id',coalesce(v_source->>'product_id',v_input->>'product_id'),
   'quantity',v_q::text,'unit_price',v_price::text,'discount_percent',v_discount::text,'tax_definition_id',v_tax.id,'tax_rate',coalesce(v_tax.rate,0)::text,'tax_inclusive',coalesce(v_tax.inclusive,false),
   'net_amount',v_net::text,'tax_amount',v_tax_amount::text,'line_total',(v_net+v_tax_amount)::text,'expense_account_id',v_account,
   'accrual_amount',v_accrual::text,'accrual_base_amount',v_accrual_base::text,'grni_account_id',v_grni,'source_snapshot',v_source,'exceptions',v_exception);
  v_lines:=v_lines||jsonb_build_array(v_detail);
  if jsonb_array_length(v_exception)>0 then v_exceptions:=v_exceptions||jsonb_build_array(jsonb_build_object('line_id',v_line_id,'exceptions',v_exception));end if;
  v_subtotal:=v_subtotal+v_net;v_tax_total:=v_tax_total+v_tax_amount;v_total:=v_total+v_net+v_tax_amount;
 end loop;
 return jsonb_build_object('lines',v_lines,'subtotal',v_subtotal::text,'tax_total',v_tax_total::text,'total',v_total::text,
  'base_total',round(v_total*(v_rate->>'exchange_rate')::numeric,v_scale)::text,'rate',v_rate,
  'match',jsonb_build_object('blocked',v_blocked,'exceptions',v_exceptions,'control_version',v_c.version,'amount_tolerance',v_c.amount_tolerance::text,'price_percent_tolerance',v_c.price_percent_tolerance::text));
end $$;
revoke all on function procurement.normalize_bill(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
create function procurement.bill_history(p_tenant uuid,p_id uuid) returns void language sql security definer set search_path='' as $$
 insert into procurement.supplier_bill_history(tenant_id,legal_entity_id,branch_id,bill_id,version,snapshot,actor_id)
 select tenant_id,legal_entity_id,branch_id,id,(detail->>'version')::bigint,detail,auth.uid() from api.supplier_bills where tenant_id=p_tenant and id=p_id$$;
revoke all on function procurement.bill_history(uuid,uuid) from public,anon,authenticated;

create function api.upsert_supplier_bill(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;v_command text:='procurement.supplier_bill.upsert';v_hash text;v_result jsonb;v_before jsonb;v_normal jsonb;v_line jsonb;v_old procurement.supplier_bills%rowtype;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.bills.manage',p_legal_entity_id,p_branch_id);
 if p_client_timestamp is null or p_legal_entity_id is null or p_branch_id is null or v_id is null then raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 perform pg_advisory_xact_lock(hashtextextended('supplier.bill:'||v_id::text,0));
 select * into v_old from procurement.supplier_bills where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if found then
  if v_old.status<>'draft' then raise exception using errcode='55000',message='BILL_NOT_EDITABLE';end if;
  select detail into v_before from api.supplier_bills where id=v_id;
  perform core.wave3_assert_expected_version(v_old.version,p_expected_entity_version,v_before);
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 v_normal:=procurement.normalize_bill(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 insert into procurement.supplier_bills(id,tenant_id,legal_entity_id,branch_id,supplier_id,supplier_reference,document_date,due_date,currency_code,base_currency_code,exchange_rate_id,exchange_rate,
  subtotal,tax_total,total,base_total,match_result,created_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'supplier_id')::uuid,trim(p_payload->>'supplier_reference'),(p_payload->>'document_date')::date,(p_payload->>'due_date')::date,
  p_payload->>'currency_code',v_normal#>>'{rate,base_currency_code}',(p_payload->>'exchange_rate_id')::uuid,(v_normal#>>'{rate,exchange_rate}')::numeric,
  (v_normal->>'subtotal')::numeric,(v_normal->>'tax_total')::numeric,(v_normal->>'total')::numeric,(v_normal->>'base_total')::numeric,v_normal->'match',auth.uid(),auth.uid())
 on conflict(id) do update set supplier_id=excluded.supplier_id,supplier_reference=excluded.supplier_reference,document_date=excluded.document_date,due_date=excluded.due_date,
 currency_code=excluded.currency_code,base_currency_code=excluded.base_currency_code,exchange_rate_id=excluded.exchange_rate_id,exchange_rate=excluded.exchange_rate,
 subtotal=excluded.subtotal,tax_total=excluded.tax_total,total=excluded.total,base_total=excluded.base_total,match_result=excluded.match_result,
 version=procurement.supplier_bills.version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
 where procurement.supplier_bills.tenant_id=p_tenant_id and procurement.supplier_bills.legal_entity_id=p_legal_entity_id and procurement.supplier_bills.branch_id=p_branch_id;
 if not found then raise exception using errcode='42501',message='BILL_SCOPE_INVALID';end if;
 delete from procurement.supplier_bill_lines where bill_id=v_id;
 for v_line in select value from jsonb_array_elements(v_normal->'lines') loop
  insert into procurement.supplier_bill_lines(id,tenant_id,legal_entity_id,branch_id,bill_id,receipt_line_id,quantity,detail)
  values((v_line->>'line_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,(v_line->>'receipt_line_id')::uuid,(v_line->>'quantity')::numeric,v_line);
 end loop;
 perform procurement.bill_history(p_tenant_id,v_id);select detail into v_result from api.supplier_bills where id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'supplier_bill',v_id,p_idempotency_key,v_hash,v_before,v_result,p_legal_entity_id,p_branch_id);
end $$;

create function procurement.bill_action(p_action text,p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'document_id')::uuid;v_command text:='procurement.supplier_bill.'||p_action;v_hash text;v_result jsonb;v_before jsonb;v_normal jsonb;v_match_hash text;
 v_b procurement.supplier_bills%rowtype;v_c procurement.supplier_bill_controls%rowtype;v_line jsonb;v_order uuid;v_jlines jsonb:='[]';v_request uuid:=gen_random_uuid();
 v_journal uuid;v_open uuid:=gen_random_uuid();v_number text;v_scale integer;v_net numeric;v_tax numeric;v_base_tax numeric;v_acc_base numeric;v_acc numeric;
 v_debits numeric:=0;v_base_debits numeric:=0;v_var numeric;v_base_var numeric;
begin
 perform core.wave3_require_scope(p_tenant_id,case when p_action='cancel' then 'procurement.bills.manage' else 'procurement.bills.post' end,p_legal_entity_id,p_branch_id);
 if p_action not in('post','approve','cancel') or v_id is null or p_client_timestamp is null or p_branch_id is null or p_legal_entity_id is null then raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 if p_action='approve' then perform core.wave3_require_scope(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id);end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_b from procurement.supplier_bills where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if not found then raise exception using errcode='P0002',message='BILL_NOT_FOUND';end if;
 select detail into v_before from api.supplier_bills where id=v_id;
 perform core.wave3_assert_expected_version(v_b.version,p_expected_entity_version,v_before);
 if v_b.status<>'draft' then raise exception using errcode='55000',message='BILL_NOT_EDITABLE';end if;
 if p_action='cancel' then
  if coalesce(length(trim(p_payload->>'reason')),0) not between 1 and 1000 then raise exception using errcode='22023',message='CANCELLATION_REASON_REQUIRED';end if;
  update procurement.supplier_bills set status='cancelled',version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_id;
 else
  for v_order in select distinct (detail->>'order_id')::uuid from procurement.supplier_bill_lines where bill_id=v_id and detail->>'order_id' is not null order by 1 loop
   perform 1 from procurement.purchase_orders where id=v_order for update;
   perform 1 from procurement.purchase_order_lines where order_id=v_order order by id for update;
  end loop;
  select * into v_c from procurement.supplier_bill_controls where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id for share;
  v_normal:=procurement.normalize_bill(p_tenant_id,p_legal_entity_id,p_branch_id,v_before);
  if (v_normal#>>'{match,blocked}')::boolean then raise exception using errcode='55000',message='RECEIPT_QUANTITY_UNAVAILABLE';end if;
  if (v_normal->>'total')::numeric is distinct from v_b.total or (v_normal#>>'{rate,exchange_rate}')::numeric<>v_b.exchange_rate then
   raise exception using errcode='40001',message='BILL_PRICING_CHANGED';end if;
  v_match_hash:=encode(extensions.digest((v_normal->'match')::text||'|'||(v_normal->'lines')::text,'sha256'),'hex');
  if p_action='approve' then
   if auth.uid() in(v_b.created_by,v_b.updated_by) then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
   if coalesce(length(trim(p_payload->>'reason')),0) not between 1 and 1000 then raise exception using errcode='22023',message='MATCH_REASON_REQUIRED';end if;
   insert into procurement.supplier_bill_match_approvals(tenant_id,legal_entity_id,branch_id,bill_id,bill_version,match_hash,control_version,reason,approved_by)
   values(p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_b.version,v_match_hash,v_c.version,trim(p_payload->>'reason'),auth.uid());
  else
   if jsonb_array_length(v_normal#>'{match,exceptions}')>0 and not exists(select 1 from procurement.supplier_bill_match_approvals
    where bill_id=v_id and bill_version=v_b.version and match_hash=v_match_hash and control_version=v_c.version) then raise exception using errcode='55000',message='MATCH_APPROVAL_REQUIRED';end if;
   if v_b.total<=0 or v_b.base_total<=0 then raise exception using errcode='22023',message='POSITIVE_BILL_REQUIRED';end if;
   perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_b.document_date);
   perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_c.payable_account_id,'liability',v_b.currency_code);
   perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_c.input_tax_account_id,'asset',v_b.currency_code);
   perform finance.flow_account(p_tenant_id,p_legal_entity_id,v_c.variance_account_id,'expense',v_b.currency_code);
   select rounding_scale into v_scale from core.legal_entities where id=p_legal_entity_id;
   for v_line in select value from jsonb_array_elements(v_normal->'lines') loop
    v_net:=(v_line->>'net_amount')::numeric;v_tax:=(v_line->>'tax_amount')::numeric;v_base_tax:=round(v_tax*v_b.exchange_rate,v_scale);
    if v_line->>'receipt_line_id' is not null then
     v_acc_base:=(v_line->>'accrual_base_amount')::numeric;
     v_acc:=round(v_acc_base/v_b.exchange_rate,v_scale);
     if v_acc_base<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline((v_line->>'grni_account_id')::uuid,v_acc,v_acc_base,(v_line->>'line_id')::uuid));end if;
     update procurement.purchase_order_lines set billed_quantity=billed_quantity+(v_line->>'quantity')::numeric where id=(v_line->>'order_line_id')::uuid;
    else
     v_acc:=v_net;v_acc_base:=round(v_net*v_b.exchange_rate,v_scale);
     if v_acc_base<>0 or v_acc<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline((v_line->>'expense_account_id')::uuid,v_acc,v_acc_base,(v_line->>'line_id')::uuid));end if;
    end if;
    if v_tax<>0 or v_base_tax<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_c.input_tax_account_id,v_tax,v_base_tax,(v_line->>'line_id')::uuid));end if;
    v_debits:=v_debits+v_acc+v_tax;v_base_debits:=v_base_debits+v_acc_base+v_base_tax;
    update procurement.supplier_bill_lines set detail=v_line where id=(v_line->>'line_id')::uuid and bill_id=v_id;
   end loop;
   v_var:=v_b.total-v_debits;v_base_var:=v_b.base_total-v_base_debits;
   if v_var<>0 or v_base_var<>0 then v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_c.variance_account_id,v_var,v_base_var));end if;
   v_jlines:=v_jlines||jsonb_build_array(finance.flow_jline(v_c.payable_account_id,-v_b.total,-v_b.base_total));
   v_journal:=finance.flow_post_journal(to_jsonb(v_b)||jsonb_build_object('customer_id',v_b.supplier_id),v_jlines,'supplier_bill',v_id,v_request,p_command_id);
   v_number:=sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,'supplier_bill',v_b.document_date,auth.uid());
   insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
    original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
   values(v_open,p_tenant_id,p_legal_entity_id,p_branch_id,'AP',v_b.supplier_id,'supplier_bill',v_id,v_number,v_b.currency_code,v_b.base_currency_code,v_b.exchange_rate,
    v_b.total,v_b.base_total,v_b.document_date,v_b.due_date,v_journal,v_request,p_command_id,v_request,auth.uid());
   update procurement.supplier_bills set status='posted',document_number=v_number,version=version+1,match_result=v_normal->'match',journal_entry_id=v_journal,open_item_id=v_open,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_id;
   for v_order in select distinct (detail->>'order_id')::uuid from procurement.supplier_bill_lines where bill_id=v_id and detail->>'order_id' is not null order by 1 loop
    update procurement.purchase_orders set version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_order;
    perform procurement.record_order_history(jsonb_build_object('entity',(select detail from api.purchase_orders where id=v_order)));
   end loop;
  end if;
 end if;
 if p_action<>'approve' then perform procurement.bill_history(p_tenant_id,v_id);end if;
 select detail into v_result from api.supplier_bills where id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'supplier_bill',v_id,p_idempotency_key,v_hash,v_before,v_result,p_legal_entity_id,p_branch_id,'{}',
  case when p_action='approve' then null else jsonb_build_object('from_status','draft','to_status',v_result->>'status','reason',p_payload->>'reason') end,
  jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('bill_id',v_id))),'[]',v_request,v_request);
end $$;
revoke all on function procurement.bill_action(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
do $$declare v_name text;v_action text;begin
 for v_name,v_action in select * from(values('post_supplier_bill','post'),('approve_supplier_bill_match','approve'),('cancel_supplier_bill','cancel')) x loop
 execute format('create function api.%I(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb language sql security definer set search_path='''' as $fn$select procurement.bill_action(%L,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version)$fn$',v_name,v_action);
 execute format('revoke all on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon',v_name);
 execute format('grant execute on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated',v_name);
 end loop;
end $$;
revoke all on function api.upsert_supplier_bill(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.upsert_supplier_bill_controls(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_supplier_bill(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.upsert_supplier_bill_controls(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function api.supplier_bill_reference_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_after uuid default null,p_search text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_items jsonb;v_next uuid;v_search text:=lower(trim(coalesce(p_search,'')));v_base text;begin
 if p_resource in('bill_controls','bill_accounts') then
  perform core.wave3_require_scope(p_tenant_id,'finance.setup.manage',p_legal_entity_id,p_branch_id);
  perform core.require_permission(p_tenant_id,'finance.setup.manage',p_legal_entity_id,null);
 else perform core.wave3_require_scope(p_tenant_id,'procurement.bills.manage',p_legal_entity_id,p_branch_id);end if;
 if p_legal_entity_id is null or p_branch_id is null or length(v_search)>100 then raise exception using errcode='22023',message='REFERENCE_SCOPE_INVALID';end if;
 select currency_code into v_base from core.legal_entities where id=p_legal_entity_id and tenant_id=p_tenant_id;
 if p_resource='bill_receipts' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'detail',detail) order by id) into v_items from (
   select l.id,r.document_number code,l.detail->>'description' name,l.detail||jsonb_build_object('receipt_line_id',l.id,
    'supplier_id',r.source_snapshot->>'supplier_id','currency_code',r.currency_code,'exchange_rate_id',r.source_snapshot->>'exchange_rate_id',
    'available_quantity',(l.accepted_quantity-coalesce((select sum(bl.quantity) from procurement.supplier_bill_lines bl join procurement.supplier_bills b on b.id=bl.bill_id
     where bl.receipt_line_id=l.id and b.status='posted'),0))::text) detail
   from procurement.goods_receipt_lines l join procurement.goods_receipts r on r.id=l.receipt_id
   where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.accepted_quantity>0
    and not exists(select 1 from procurement.goods_receipt_reversals x where x.receipt_id=r.id)
    and (p_after is null or l.id>p_after) and (v_search='' or position(v_search in lower(r.document_number||' '||(l.detail->>'description')))>0)
   order by l.id limit 51) x;
 elsif p_resource='bill_controls' then
  select jsonb_agg(sales.flow_exact_json(to_jsonb(c))||jsonb_build_object('id',c.legal_entity_id)) into v_items from procurement.supplier_bill_controls c
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id;
 elsif p_resource in('bill_accounts','bill_expenses') then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'account_type',account_type) order by id) into v_items from (
   select * from finance.accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and is_posting
    and (p_resource='bill_accounts' or account_type='expense') and (p_after is null or id>p_after)
    and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51) x;
 elsif p_resource='bill_suppliers' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',display_name) order by id) into v_items from (
   select * from crm.parties where tenant_id=p_tenant_id and status='active' and kind in('supplier','both') and (p_after is null or id>p_after)
   and (v_search='' or position(v_search in lower(code||' '||display_name))>0) order by id limit 51) x;
 elsif p_resource='bill_taxes' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'rate',rate::text,'inclusive',inclusive) order by id) into v_items from (
   select * from finance.tax_definitions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and kind in('input','zero','exempt')
    and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51) x;
 elsif p_resource='bill_rates' then
  select jsonb_agg(jsonb_build_object('id',id,'code',source_currency_code,'name',effective_date::text||' · '||rate::text,'currency_code',source_currency_code,'exchange_rate',rate::text) order by id) into v_items from (
   select * from finance.exchange_rates where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and target_currency_code=v_base
    and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(source_currency_code))>0) order by id limit 51) x;
 else raise exception using errcode='22023',message='REFERENCE_RESOURCE_INVALID';end if;
 v_items:=coalesce(v_items,'[]');if jsonb_array_length(v_items)>50 then v_next:=(v_items->49->>'id')::uuid;v_items:=v_items-50;end if;
 return jsonb_build_object('items',v_items,'next_cursor',v_next,'base_currency',v_base);
end $$;
revoke all on function api.supplier_bill_reference_options(uuid,uuid,uuid,text,uuid,text) from public,anon;
grant execute on function api.supplier_bill_reference_options(uuid,uuid,uuid,text,uuid,text) to authenticated;
