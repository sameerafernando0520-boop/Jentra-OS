-- Unapplied candidate. Exact value-only ledger entries; no second accounting engine.
create table inventory.value_adjustments (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 receipt_line_id uuid not null,reverse_of uuid,document_date date not null,reference text not null,reason text not null,
 amount numeric(20,6) not null check(amount<>0),currency_code text not null,
 offset_account_id uuid not null,variance_account_id uuid not null,detail jsonb not null,
 request_id uuid not null,command_id uuid not null,created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),unique(tenant_id,id),unique(tenant_id,reverse_of),
 foreign key(tenant_id,receipt_line_id) references inventory.stock_movement_lines(tenant_id,id),
 foreign key(tenant_id,reverse_of) references inventory.value_adjustments(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,offset_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,variance_account_id) references finance.accounts(tenant_id,legal_entity_id,id)
);
alter table inventory.value_adjustments enable row level security;
alter table inventory.value_adjustments force row level security;
revoke all on inventory.value_adjustments from public,anon,authenticated;
create trigger immutable before update or delete on inventory.value_adjustments for each row execute function workflow.reject_history_mutation();
create index value_adjustments_scope on inventory.value_adjustments(tenant_id,legal_entity_id,branch_id,id);
create index value_adjustments_receipt on inventory.value_adjustments(tenant_id,receipt_line_id);
create index value_adjustments_actor on inventory.value_adjustments(created_by);
create index value_adjustments_offset on inventory.value_adjustments(tenant_id,legal_entity_id,offset_account_id);
create index value_adjustments_variance on inventory.value_adjustments(tenant_id,legal_entity_id,variance_account_id);
create index value_adjustments_branch on inventory.value_adjustments(tenant_id,branch_id);

alter table inventory.stock_movement_lines drop constraint stock_movement_lines_base_quantity_check;
alter table inventory.stock_movement_lines drop constraint stock_movement_lines_check;
alter table inventory.stock_movement_lines add constraint stock_movement_lines_base_quantity_check check(base_quantity<>0 or base_value<>0);
alter table inventory.stock_movement_lines add constraint stock_movement_lines_check check(base_quantity=0 or base_value=0 or sign(base_quantity)=sign(base_value));
do $$declare c text;begin
 select pg_get_constraintdef(oid) into c from pg_constraint where conrelid='inventory.stock_movements'::regclass and conname='stock_movements_movement_kind_check';
 if c is null then raise exception 'MOVEMENT_CONSTRAINT_DRIFT';end if;
 alter table inventory.stock_movements drop constraint stock_movements_movement_kind_check;
 execute 'alter table inventory.stock_movements add constraint stock_movements_movement_kind_check CHECK ('||substring(c from 7)||' OR movement_kind=''value_adjustment'')';
end $$;
create function inventory.guard_value_movement() returns trigger language plpgsql security definer set search_path='' as $$
declare m inventory.stock_movements%rowtype; seq bigint;begin
 select * into strict m from inventory.stock_movements where id=new.stock_movement_id;
 if (new.base_quantity=0) is distinct from (m.movement_kind='value_adjustment') then raise exception using errcode='23514',message='VALUE_MOVEMENT_KIND_REQUIRED';end if;
 if m.source_type='goods_receipt_reversal' and exists(select 1 from inventory.value_adjustments a
  where a.tenant_id=new.tenant_id and a.receipt_line_id=new.original_movement_line_id and a.reverse_of is null
  and not exists(select 1 from inventory.value_adjustments r where r.reverse_of=a.id)) then
  raise exception using errcode='55000',message='REVERSE_LANDED_VALUE_FIRST';end if;
 if m.source_type='transfer.reverse.issue' then
  select coalesce(max(e.id),0) into seq from inventory.receipt_provenance_entries e join inventory.stock_movement_lines ml on ml.id=e.movement_line_id
   join inventory.stock_movements sm on sm.id=ml.stock_movement_id where sm.tenant_id=new.tenant_id and sm.source_type='transfer.receive'
   and sm.source_id=m.source_id and ml.source_line_id=new.source_line_id;
  if exists(select 1 from inventory.value_adjustments a,jsonb_array_elements(a.detail->'legs') leg where a.tenant_id=new.tenant_id and a.reverse_of is null
   and not exists(select 1 from inventory.value_adjustments r where r.reverse_of=a.id)
   and leg->>'warehouse_id'=new.warehouse_id::text and leg->>'product_id'=new.product_id::text and (leg->>'provenance_sequence')::bigint>=seq) then
   raise exception using errcode='55000',message='TRANSFER_VALUE_CHANGED';end if;
 end if;
 return new;
end $$;
revoke all on function inventory.guard_value_movement() from public,anon,authenticated;
create trigger guard_value_movement before insert on inventory.stock_movement_lines for each row execute function inventory.guard_value_movement();

create function inventory.value_basis(p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ml inventory.stock_movement_lines%rowtype; receipt procurement.goods_receipts%rowtype; product inventory.products%rowtype;
 trace jsonb; row record; legs jsonb:='[]'; q numeric:=0; previous numeric:=0; next_value numeric; amount numeric; currency text; d date;
 offset_id uuid:=(p_payload->>'offset_account_id')::uuid; variance_id uuid:=(p_payload->>'variance_account_id')::uuid; result jsonb;
begin
 perform core.wave3_require_scope(p_tenant,'inventory.valuation.post',p_entity,p_branch);
 perform core.wave3_require_scope(p_tenant,'inventory.cost.view',p_entity,p_branch);
 if p_entity is null or p_branch is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 select x.* into ml from inventory.stock_movement_lines x join inventory.stock_movements m on m.id=x.stock_movement_id and m.source_type='goods_receipt'
  where x.tenant_id=p_tenant and x.legal_entity_id=p_entity and x.branch_id=p_branch and x.id=(p_payload->>'receipt_line_id')::uuid;
 if not found then raise exception using errcode='22023',message='LANDED_RECEIPT_INVALID';end if;
 select r.* into receipt from procurement.goods_receipts r where r.stock_movement_id=ml.stock_movement_id;
 if not found or exists(select 1 from procurement.goods_receipt_reversals where receipt_id=receipt.id) then raise exception using errcode='22023',message='LANDED_RECEIPT_INVALID';end if;
 select * into product from inventory.products where id=ml.product_id and status='active';
 if not found then raise exception using errcode='22023',message='LANDED_PRODUCT_INACTIVE';end if;
 select currency_code into currency from core.legal_entities where id=p_entity and tenant_id=p_tenant;
 amount:=sales.wave3_decimal_string(p_payload->'amount','amount',6,true,0.000001,null);
 d:=(p_payload->>'document_date')::date;
 if d is null or d<ml.posting_date or d>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='LANDED_DATE_INVALID';end if;
 perform finance.flow_account(p_tenant,p_entity,offset_id,'expense',currency);
 perform finance.flow_account(p_tenant,p_entity,variance_id,'expense',currency);
 perform finance.flow_account(p_tenant,p_entity,product.inventory_account_id,'asset',currency);
 if (select count(*) from core.warehouses where tenant_id=p_tenant and legal_entity_id=p_entity)>500 then raise exception using errcode='54000',message='LANDED_WAREHOUSE_LIMIT';end if;
 -- Same sorted lock keys as transfers/receipts. Lock before reading the projection.
 for row in select id from core.warehouses where tenant_id=p_tenant and legal_entity_id=p_entity order by id loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||':'||row.id::text||':'||ml.product_id::text,0));
 end loop;
 trace:=api.receipt_trace_detail(p_tenant,p_entity,p_branch,ml.id);
 if trace->>'covered'<>'true' or (trace->>'held_quantity')::numeric<=0 then raise exception using errcode='22023',message='LANDED_RECEIPT_CONSUMED_OR_UNCOVERED',detail=ml.id::text;end if;
 if (trace->>'in_transit_quantity')::numeric<>0 then raise exception using errcode='55000',message='LANDED_RECEIPT_IN_TRANSIT',detail=ml.id::text;end if;
 if exists(select 1 from inventory.receipt_provenance_entries e join inventory.stock_movement_lines x on x.id=e.movement_line_id
  join inventory.stock_movements m on m.id=x.stock_movement_id where e.tenant_id=p_tenant and e.origin_line_id=ml.id
  and m.source_type not in('goods_receipt','delivery','sales_return','transfer.dispatch','transfer.receive','transfer.reverse.issue','transfer.reverse.receipt')) then
  raise exception using errcode='55000',message='LANDED_RECEIPT_DISPOSITION_REVIEW',detail=ml.id::text;end if;
 for row in select p.warehouse_id,w.branch_id,w.name warehouse_name,sum(p.quantity) quantity,b.id balance_id,v.id valuation_id,v.version valuation_version,v.carrying_value,
  coalesce((select max(e.id) from inventory.receipt_provenance_entries e where e.tenant_id=p_tenant and e.warehouse_id=p.warehouse_id and e.product_id=ml.product_id),0) provenance_sequence
  from inventory.receipt_provenance_positions p join core.warehouses w on w.id=p.warehouse_id
  join inventory.stock_balances b on b.tenant_id=p_tenant and b.warehouse_id=p.warehouse_id and b.product_id=ml.product_id
  join inventory.stock_valuations v on v.stock_balance_id=b.id
  where p.tenant_id=p_tenant and p.origin_line_id=ml.id and p.quantity>0
  group by p.warehouse_id,w.branch_id,w.name,b.id,v.id,v.version,v.carrying_value order by p.warehouse_id loop
  perform core.wave3_require_scope(p_tenant,'inventory.valuation.post',p_entity,row.branch_id);
  perform core.wave3_require_scope(p_tenant,'inventory.cost.view',p_entity,row.branch_id);
  if exists(select 1 from inventory.stock_movement_lines where tenant_id=p_tenant and warehouse_id=row.warehouse_id and product_id=ml.product_id and posting_date>d) then
   raise exception using errcode='55000',message='LANDED_BACKDATED_VALUE_REVIEW';end if;
  q:=q+row.quantity;next_value:=round(amount*q/ml.base_quantity,6);
  legs:=legs||jsonb_build_array(jsonb_build_object('warehouse_id',row.warehouse_id,'warehouse_name',row.warehouse_name,'branch_id',row.branch_id,
   'product_id',ml.product_id,'quantity',row.quantity::text,'value',(next_value-previous)::text,'valuation_id',row.valuation_id,
   'valuation_version',row.valuation_version::text,'carrying_value',row.carrying_value::text,'provenance_sequence',row.provenance_sequence::text,'inventory_account_id',product.inventory_account_id));
  previous:=next_value;
 end loop;
 if q>ml.base_quantity or q<=0 or q<>(trace->>'held_quantity')::numeric then raise exception using errcode='55000',message='LANDED_PROVENANCE_MISMATCH';end if;
 result:=jsonb_build_object('receipt_line_id',ml.id,'receipt_number',receipt.document_number,'product_name',product.name,'currency_code',currency,'document_date',d,
  'received_quantity',ml.base_quantity::text,'held_quantity',q::text,'consumed_quantity',(ml.base_quantity-q)::text,'amount',amount::text,
  'inventory_amount',previous::text,'variance_amount',(amount-previous)::text,'offset_account_id',offset_id,'variance_account_id',variance_id,'legs',legs,
  'provenance_version',(select max(id)::text from inventory.receipt_provenance_entries where tenant_id=p_tenant and origin_line_id=ml.id));
 return result||jsonb_build_object('basis_hash',md5(result::text));
end $$;
revoke all on function inventory.value_basis(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
create function api.preview_inventory_value_adjustment(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_payload jsonb) returns jsonb
language sql security definer set search_path='' as $$select inventory.value_basis(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload)$$;

create function api.post_inventory_value_adjustment(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid; parent uuid:=(p_payload->>'reverse_of')::uuid; original inventory.value_adjustments%rowtype;
 h text; result jsonb; basis jsonb; leg jsonb; posted jsonb:='[]'; journals jsonb:='[]'; v numeric; variance numeric; amount numeric;
 req uuid:=gen_random_uuid(); mid uuid; jid uuid; version bigint; d date:=(p_payload->>'document_date')::date; doc jsonb; row record;
 reason text:=trim(p_payload->>'reason');reference text:=trim(p_payload->>'reference');offset_id uuid;variance_id uuid;currency text;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or v_id is null or p_client_timestamp is null or d is null
  or d>(clock_timestamp() at time zone 'UTC')::date or coalesce(length(reason),0) not between 3 and 1000 or coalesce(length(reference),0) not between 1 and 140 then
  raise exception using errcode='22023',message='LANDED_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.value.adjust',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'inventory.value.adjust',p_command_id,p_idempotency_key,h);
 if result is not null then
  for leg in select value from jsonb_array_elements(result#>'{entity,legs}') loop
   perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,(leg->>'branch_id')::uuid);
   perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,(leg->>'branch_id')::uuid);
  end loop;return result;
 end if;
 if parent is null then
  perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
  basis:=inventory.value_basis(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
  if p_payload->>'basis_hash' is distinct from basis->>'basis_hash' then raise exception using errcode='40001',message='LANDED_PREVIEW_CHANGED';end if;
 else
  select * into original from inventory.value_adjustments where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=parent for update;
  if not found or original.reverse_of is not null then raise exception using errcode='22023',message='LANDED_REVERSAL_SOURCE_INVALID';end if;
  perform core.wave3_assert_expected_version(case when exists(select 1 from inventory.value_adjustments where reverse_of=parent) then 2 else 1 end,p_expected_entity_version,'{}');
  if d<original.document_date then raise exception using errcode='22023',message='LANDED_DATE_INVALID';end if;
  basis:=original.detail;basis:=jsonb_set(basis,'{document_date}',to_jsonb(d));
  for leg in select value from jsonb_array_elements(basis->'legs') order by value->>'warehouse_id' loop
   perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,(leg->>'branch_id')::uuid);
   perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,(leg->>'branch_id')::uuid);
   perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||(leg->>'warehouse_id')||':'||(leg->>'product_id'),0));
   select v2.version into version from inventory.stock_valuations v2 where v2.id=(leg->>'valuation_id')::uuid for update;
   if version is distinct from (leg->>'posted_valuation_version')::bigint then raise exception using errcode='55000',message='LANDED_REVERSAL_STOCK_CHANGED';end if;
  end loop;
 end if;
 currency:=basis->>'currency_code';offset_id:=(basis->>'offset_account_id')::uuid;variance_id:=(basis->>'variance_account_id')::uuid;
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,offset_id,'expense',currency);
 perform finance.flow_account(p_tenant_id,p_legal_entity_id,variance_id,'expense',currency);
 amount:=(basis->>'amount')::numeric*case when parent is null then 1 else -1 end;
 variance:=(basis->>'variance_amount')::numeric*case when parent is null then 1 else -1 end;
 doc:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'document_date',d,'currency_code',currency,'base_currency_code',currency,'exchange_rate','1');
 for leg in select value from jsonb_array_elements(basis->'legs') order by value->>'warehouse_id' loop
  v:=(leg->>'value')::numeric*case when parent is null then 1 else -1 end;
  perform finance.flow_account(p_tenant_id,p_legal_entity_id,(leg->>'inventory_account_id')::uuid,'asset',currency);
  if v<>0 then
   update inventory.stock_valuations set carrying_value=carrying_value+v,updated_by=auth.uid()
    where id=(leg->>'valuation_id')::uuid and carrying_value+v>=0 returning stock_valuations.version into version;
   if not found then raise exception using errcode='55000',message='LANDED_VALUE_UNAVAILABLE';end if;
   mid:=gen_random_uuid();
   insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
    values(mid,p_tenant_id,p_legal_entity_id,(leg->>'branch_id')::uuid,'inventory_value_adjustment',mid,(leg->>'warehouse_id')::uuid,d,'value_adjustment',req,p_command_id,req,auth.uid());
   insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,original_movement_line_id,base_quantity,base_value,posting_date,created_by)
    values(p_tenant_id,p_legal_entity_id,(leg->>'branch_id')::uuid,mid,(leg->>'warehouse_id')::uuid,(leg->>'product_id')::uuid,v_id,(basis->>'receipt_line_id')::uuid,0,v,d,auth.uid());
   jid:=finance.flow_post_journal(doc||jsonb_build_object('branch_id',leg->>'branch_id'),jsonb_build_array(
    finance.flow_jline((leg->>'inventory_account_id')::uuid,v,v,v_id),finance.flow_jline(offset_id,-v,-v,v_id)),
    'inventory_value_adjustment',mid,req,p_command_id);
   journals:=journals||jsonb_build_array(jid);
  else version:=(leg->>'valuation_version')::bigint;end if;
  posted:=posted||jsonb_build_array(leg||jsonb_build_object('value',v::text,'posted_valuation_version',version::text,'stock_movement_id',mid));mid:=null;
 end loop;
 if variance<>0 then
  jid:=finance.flow_post_journal(doc,jsonb_build_array(finance.flow_jline(variance_id,variance,variance,v_id),finance.flow_jline(offset_id,-variance,-variance,v_id)),
   'inventory_value_variance',v_id,req,p_command_id);journals:=journals||jsonb_build_array(jid);
 end if;
 result:=basis||jsonb_build_object('id',v_id,'version',1,'status','posted','reverse_of',parent,'amount',amount::text,
  'inventory_amount',(amount-variance)::text,'variance_amount',variance::text,'legs',posted,'journal_ids',journals,'reason',reason,'reference',reference,'document_date',d);
 insert into inventory.value_adjustments(id,tenant_id,legal_entity_id,branch_id,receipt_line_id,reverse_of,document_date,reference,reason,amount,currency_code,offset_account_id,variance_account_id,detail,request_id,command_id,created_by)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,(basis->>'receipt_line_id')::uuid,parent,d,reference,reason,amount,currency,offset_id,variance_id,result,req,p_command_id,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'inventory.value.adjust',p_command_id,'inventory_value_adjustment',v_id,p_idempotency_key,h,null,result,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','posted','operation',case when parent is null then 'post' else 'reverse' end,'reason',reason),
  jsonb_build_array(jsonb_build_object('topic','inventory.value.adjust','payload',jsonb_build_object('id',v_id))),'[]',req,req);
end $$;
revoke all on function api.preview_inventory_value_adjustment(uuid,uuid,uuid,jsonb),api.post_inventory_value_adjustment(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.preview_inventory_value_adjustment(uuid,uuid,uuid,jsonb),api.post_inventory_value_adjustment(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function api.inventory_value_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 if p_resource='receipts' then return api.receipt_trace_page(p_tenant_id,p_legal_entity_id,p_branch_id,p_after);
 elsif p_resource='accounts' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from (select a.id,a.code,a.name from finance.accounts a join core.legal_entities e on e.id=a.legal_entity_id
   where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.account_type='expense' and a.is_posting and a.status='active'
   and(a.currency_code is null or a.currency_code=e.currency_code) and(p_after is null or a.id>p_after) order by a.id limit 51)q;
 elsif p_resource='posted' then
  select coalesce(jsonb_agg(q.detail order by q.id),'[]') into rows from (
   select a.id,a.detail||jsonb_build_object('version',case when exists(select 1 from inventory.value_adjustments r where r.reverse_of=a.id) then 2 else 1 end,
    'reversed',exists(select 1 from inventory.value_adjustments r where r.reverse_of=a.id)) detail from inventory.value_adjustments a
   where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and(p_after is null or a.id>p_after)
   and not exists(select 1 from jsonb_array_elements(a.detail->'legs') l where not core.has_permission(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,(l->>'branch_id')::uuid)
    or not core.has_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,(l->>'branch_id')::uuid)) order by a.id limit 51)q;
 else raise exception using errcode='22023',message='LANDED_RESOURCE_INVALID';end if;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',cursor);
end $$;
revoke all on function api.inventory_value_options(uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function api.inventory_value_options(uuid,uuid,uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';

