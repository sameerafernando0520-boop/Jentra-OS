-- UNAPPLIED additive candidate. Receipt attribution is quantity evidence, never
-- original carrying-cost provenance. All amounts are exact six-place decimals.
create table inventory.landed_extensions (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 correction_of uuid,root_id uuid not null,document_date date not null,
 reference text not null,reason text not null,total_amount numeric(20,6) not null check(total_amount>=0),
 amount numeric(20,6) not null check(amount<>0),detail jsonb not null,
 request_id uuid not null,command_id uuid not null,created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),unique(tenant_id,id),unique(tenant_id,correction_of),
 foreign key(tenant_id,correction_of) references inventory.landed_extensions(tenant_id,id),
 foreign key(tenant_id,root_id) references inventory.landed_extensions(tenant_id,id) deferrable initially deferred,
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(octet_length(detail::text)<=1048576)
);
create table inventory.landed_extension_transit (
 id uuid primary key,tenant_id uuid not null,extension_id uuid not null,
 origin_line_id uuid not null,transfer_id uuid not null,transfer_line_id uuid not null,
 dispatch_entry_id bigint not null references inventory.receipt_provenance_entries(id),
 amount numeric(20,6) not null check(amount<>0),inventory_account_id uuid not null,
 posting_date date not null,branch_id uuid not null,
 foreign key(tenant_id,extension_id) references inventory.landed_extensions(tenant_id,id) deferrable initially deferred,
 foreign key(tenant_id,origin_line_id) references inventory.stock_movement_lines(tenant_id,id),
 foreign key(tenant_id,transfer_id) references inventory.transfers(tenant_id,id),
 foreign key(transfer_line_id) references inventory.transfer_lines(id)
);
create table inventory.landed_extension_settlements (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,transit_id uuid not null,
 operation text not null check(operation in('transfer.receive','transfer.reverse.issue','transfer.reverse.receipt')),
 posting_date date not null,movement_line_id uuid not null,amount numeric(20,6) not null check(amount<>0),
 foreign key(transit_id) references inventory.landed_extension_transit(id),
 foreign key(tenant_id,movement_line_id) references inventory.stock_movement_lines(tenant_id,id),
 unique(transit_id,operation)
);
create index landed_extensions_scope on inventory.landed_extensions(tenant_id,legal_entity_id,branch_id,id);
create index landed_extensions_root on inventory.landed_extensions(tenant_id,root_id);
create index landed_extension_transit_transfer on inventory.landed_extension_transit(tenant_id,transfer_id,transfer_line_id);
create index landed_extension_transit_origin on inventory.landed_extension_transit(tenant_id,origin_line_id);
create index landed_extension_settlement_movement on inventory.landed_extension_settlements(tenant_id,movement_line_id);
do $$declare n text;begin
 foreach n in array array['landed_extensions','landed_extension_transit','landed_extension_settlements'] loop
  execute format('alter table inventory.%I enable row level security',n);
  execute format('alter table inventory.%I force row level security',n);
  execute format('revoke all on inventory.%I from public,anon,authenticated',n);
  execute format('create trigger immutable before update or delete on inventory.%I for each row execute function workflow.reject_history_mutation()',n);
 end loop;
end $$;

-- Called only under existing sorted warehouse/product locks and an open period.
-- A value movement changes pooled carrying value without touching quantities.
create function inventory.landed_extension_stock_value(t uuid,e uuid,b uuid,w uuid,p uuid,origin uuid,
 source uuid,d date,v numeric,req uuid,cmd uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare balance uuid;mid uuid:=gen_random_uuid();lid uuid:=gen_random_uuid();begin
 if v=0 then return null;end if;
 select id into balance from inventory.stock_balances where tenant_id=t and warehouse_id=w and product_id=p for update;
 update inventory.stock_valuations set carrying_value=carrying_value+v,updated_by=auth.uid()
 where tenant_id=t and stock_balance_id=balance and carrying_value+v>=0;
 if not found then raise exception using errcode='55000',message='LANDED_EXTENSION_VALUE_UNAVAILABLE';end if;
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,warehouse_id,source_type,source_id,
 posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(mid,t,e,b,w,'landed_extension',mid,d,'value_adjustment',req,cmd,req,auth.uid());
 insert into inventory.stock_movement_lines(id,tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,
 product_id,source_line_id,original_movement_line_id,base_quantity,base_value,posting_date,created_by)
 values(lid,t,e,b,mid,w,p,source,origin,0,v,d,auth.uid());
 return lid;
end $$;
revoke all on function inventory.landed_extension_stock_value(uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,numeric,uuid,uuid) from public,anon,authenticated;

create function inventory.landed_extension_basis(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prior inventory.landed_extensions%rowtype;ml inventory.stock_movement_lines%rowtype;prod inventory.products%rowtype;
 receipts jsonb:='[]';legs jsonb:='[]';inputs jsonb;item jsonb;trace jsonb;r record;
 locked_transfers uuid[];mode text;currency text;d date:=(p->>'document_date')::date;
 target numeric;delta numeric;weight numeric;weight_total numeric:=0;running numeric:=0;previous numeric:=0;share numeric;
 held numeric;transit numeric;consumed numeric;q numeric;prev numeric;nextv numeric;held_value numeric:=0;transit_value numeric:=0;
 offset_id uuid;variance_id uuid;account_id uuid;result jsonb;root uuid;begin
 perform core.wave3_require_scope(t,'inventory.valuation.post',e,b);
 perform core.wave3_require_scope(t,'inventory.cost.view',e,b);
 if e is null or b is null or d is null or d>(clock_timestamp() at time zone 'UTC')::date
  or jsonb_typeof(p) is distinct from 'object' then raise exception using errcode='22023',message='LANDED_EXTENSION_INPUT_INVALID';end if;
 target:=sales.wave3_decimal_string(p->'total_amount','total_amount',6,true,0,99999999999999.999999);
 if p->>'correction_of' is not null then
  select * into prior from inventory.landed_extensions where tenant_id=t and legal_entity_id=e and branch_id=b and id=(p->>'correction_of')::uuid;
  if not found then raise exception using errcode='22023',message='LANDED_EXTENSION_CORRECTION_INVALID';end if;
  if exists(select 1 from inventory.landed_extensions where tenant_id=t and correction_of=prior.id) then
   raise exception using errcode='40001',message='LANDED_EXTENSION_CORRECTION_CHANGED';end if;
  if d<prior.document_date then raise exception using errcode='22023',message='LANDED_EXTENSION_DATE_INVALID';end if;
  inputs:=prior.detail->'receipts';mode:=prior.detail->>'basis_mode';offset_id:=(prior.detail->>'offset_account_id')::uuid;
  variance_id:=(prior.detail->>'variance_account_id')::uuid;root:=prior.root_id;delta:=target-prior.total_amount;
  if p ? 'receipts' or p ? 'basis_mode' or p ? 'offset_account_id' or p ? 'variance_account_id' then
   raise exception using errcode='22023',message='LANDED_EXTENSION_CORRECTION_BASIS_IMMUTABLE';end if;
 else
  inputs:=p->'receipts';mode:=p->>'basis_mode';offset_id:=(p->>'offset_account_id')::uuid;variance_id:=(p->>'variance_account_id')::uuid;
  delta:=target;root:=(p->>'id')::uuid;
  if mode is null or mode not in('quantity','original_value','manual') then raise exception using errcode='22023',message='LANDED_EXTENSION_BASIS_INVALID';end if;
 end if;
 if delta=0 or jsonb_typeof(inputs) is distinct from 'array' or jsonb_array_length(inputs) not between 1 and 50
  or exists(select 1 from jsonb_array_elements(inputs)x where x->>'receipt_line_id' is null)
  or (select count(*)<>count(distinct x->>'receipt_line_id') from jsonb_array_elements(inputs)x) then
  raise exception using errcode='22023',message='LANDED_EXTENSION_RECEIPTS_INVALID';end if;
 select currency_code into currency from core.legal_entities where tenant_id=t and id=e;
 perform finance.flow_account(t,e,offset_id,'expense',currency);
 perform finance.flow_account(t,e,variance_id,'expense',currency);
 if (select count(*) from core.warehouses where tenant_id=t and legal_entity_id=e)>500 then raise exception using errcode='54000',message='LANDED_EXTENSION_WAREHOUSE_LIMIT';end if;
 -- Transfer command locks transfer identity, then period, then warehouse/product.
 -- Acquire every known transfer identity first. A newly discovered dispatch after
 -- these keys were enumerated fails rather than acquiring an inverted lock.
 select coalesce(array_agg(distinct m.source_id order by m.source_id),'{}') into locked_transfers
 from inventory.receipt_provenance_entries pe join inventory.stock_movement_lines x on x.id=pe.movement_line_id
 join inventory.stock_movements m on m.id=x.stock_movement_id
 where pe.tenant_id=t and pe.origin_line_id in(select (x->>'receipt_line_id')::uuid from jsonb_array_elements(inputs)x)
 and m.source_type like 'transfer.%';
 if cardinality(locked_transfers)>500 then raise exception using errcode='54000',message='LANDED_EXTENSION_TRANSFER_LIMIT';end if;
 for r in select unnest(locked_transfers) id order by id loop
  perform pg_advisory_xact_lock(hashtextextended('inventory.transfer:'||r.id::text,0));
 end loop;
 perform finance.wave3_lock_open_period(t,e,d);
 for r in select distinct w.id warehouse_id,x.product_id from core.warehouses w cross join inventory.stock_movement_lines x
 where w.tenant_id=t and w.legal_entity_id=e and x.tenant_id=t and x.legal_entity_id=e
 and x.id in(select (i->>'receipt_line_id')::uuid from jsonb_array_elements(inputs)i) order by w.id,x.product_id loop
  perform pg_advisory_xact_lock(hashtextextended(t::text||':'||r.warehouse_id::text||':'||r.product_id::text,0));
 end loop;
 if exists(select 1 from inventory.receipt_provenance_entries pe join inventory.stock_movement_lines x on x.id=pe.movement_line_id
 join inventory.stock_movements m on m.id=x.stock_movement_id where pe.tenant_id=t
 and pe.origin_line_id in(select (x->>'receipt_line_id')::uuid from jsonb_array_elements(inputs)x)
 and m.source_type like 'transfer.%' and not(m.source_id=any(locked_transfers))) then
  raise exception using errcode='40001',message='LANDED_EXTENSION_PREVIEW_CHANGED';end if;
 for item in select value from jsonb_array_elements(inputs) order by value->>'receipt_line_id' loop
  select x.* into ml from inventory.stock_movement_lines x join inventory.stock_movements m on m.id=x.stock_movement_id
   join procurement.goods_receipts gr on gr.stock_movement_id=m.id
   where x.tenant_id=t and x.legal_entity_id=e and x.branch_id=b and x.id=(item->>'receipt_line_id')::uuid
   and m.source_type='goods_receipt' and x.base_quantity>0
   and not exists(select 1 from procurement.goods_receipt_reversals rr where rr.receipt_id=gr.id);
  if not found then raise exception using errcode='22023',message='LANDED_EXTENSION_RECEIPT_INVALID',detail=item->>'receipt_line_id';end if;
  if d<ml.posting_date then raise exception using errcode='22023',message='LANDED_EXTENSION_DATE_INVALID',detail=ml.id::text;end if;
  select * into prod from inventory.products where tenant_id=t and legal_entity_id=e and id=ml.product_id;
  if prior.id is null and prod.status<>'active' then raise exception using errcode='22023',message='LANDED_EXTENSION_PRODUCT_INACTIVE',detail=ml.id::text;end if;
  account_id:=case when prior.id is not null then (item->>'inventory_account_id')::uuid else prod.inventory_account_id end;
  perform finance.flow_account(t,e,account_id,'asset',currency);
  weight:=case when prior.id is not null then (item->>'weight')::numeric when mode='quantity' then ml.base_quantity when mode='original_value' then ml.base_value
   else sales.wave3_decimal_string(item->'weight','weight',6,true,0.000001,99999999999999.999999) end;
  if weight is null or weight<=0 then raise exception using errcode='22023',message='LANDED_EXTENSION_WEIGHT_INVALID',detail=ml.id::text;end if;
  trace:=api.receipt_trace_detail(t,e,b,ml.id);
  held:=(trace->>'held_quantity')::numeric;transit:=(trace->>'in_transit_quantity')::numeric;consumed:=ml.base_quantity-held-transit;
  if trace->>'covered'<>'true' or held is null or held<0 or transit<0 or consumed<0
   or (prior.id is null and held+transit<=0) then
   raise exception using errcode='22023',message='LANDED_EXTENSION_CONSUMED_OR_UNCOVERED',detail=ml.id::text;end if;
  if (select count(*) from inventory.receipt_provenance_entries where tenant_id=t and origin_line_id=ml.id)>10000 then
   raise exception using errcode='54000',message='LANDED_EXTENSION_PROVENANCE_LIMIT',detail=ml.id::text;end if;
  if exists(select 1 from inventory.stock_movement_lines where tenant_id=t and product_id=ml.product_id and posting_date>d) then
   raise exception using errcode='55000',message='LANDED_EXTENSION_BACKDATED_REVIEW',detail=ml.id::text;end if;
  weight_total:=weight_total+weight;
  receipts:=receipts||jsonb_build_array(jsonb_build_object('receipt_line_id',ml.id,'product_id',ml.product_id,'weight',weight::text,
   'inventory_account_id',account_id,'received_quantity',ml.base_quantity::text,'original_value',ml.base_value::text,
   'held_quantity',held::text,'transit_quantity',transit::text,'consumed_quantity',consumed::text,
   'previous_allocation',coalesce(item->>'target_allocation','0'),
   'provenance_version',(select coalesce(max(id),0)::text from inventory.receipt_provenance_entries where tenant_id=t and origin_line_id=ml.id)));
 end loop;
 inputs:=receipts;receipts:='[]';
 for item in select value from jsonb_array_elements(inputs) order by value->>'receipt_line_id' loop
  running:=running+(item->>'weight')::numeric;
  nextv:=round(target*running/weight_total,6);share:=nextv-previous-(item->>'previous_allocation')::numeric;
  item:=item||jsonb_build_object('target_allocation',(nextv-previous)::text,'incremental_amount',share::text);previous:=nextv;
  receipts:=receipts||jsonb_build_array(item);q:=0;prev:=0;
  for r in select pos.warehouse_id,w.branch_id,sum(pos.quantity) quantity,sb.version balance_version,sv.id valuation_id,sv.version valuation_version,sv.carrying_value
   from inventory.receipt_provenance_positions pos join core.warehouses w on w.id=pos.warehouse_id
   left join inventory.stock_balances sb on sb.tenant_id=t and sb.warehouse_id=pos.warehouse_id and sb.product_id=pos.product_id
   left join inventory.stock_valuations sv on sv.tenant_id=t and sv.stock_balance_id=sb.id
   where pos.tenant_id=t and pos.origin_line_id=(item->>'receipt_line_id')::uuid and pos.quantity>0
   group by pos.warehouse_id,w.branch_id,sb.version,sv.id,sv.version,sv.carrying_value order by pos.warehouse_id loop
   if r.valuation_id is null then raise exception using errcode='55000',message='LANDED_EXTENSION_PROJECTION_REQUIRED';end if;
   perform core.wave3_require_scope(t,'inventory.valuation.post',e,r.branch_id);perform core.wave3_require_scope(t,'inventory.cost.view',e,r.branch_id);
   q:=q+r.quantity;nextv:=round(share*q/(item->>'received_quantity')::numeric,6);
   legs:=legs||jsonb_build_array(item||jsonb_build_object('kind','held','warehouse_id',r.warehouse_id,'branch_id',r.branch_id,'quantity',r.quantity::text,
    'value',(nextv-prev)::text,'valuation_id',r.valuation_id,'valuation_version',r.valuation_version::text,'balance_version',r.balance_version::text,'carrying_value',r.carrying_value::text));
   held_value:=held_value+nextv-prev;prev:=nextv;
  end loop;
  if q<>(item->>'held_quantity')::numeric then raise exception using errcode='55000',message='LANDED_EXTENSION_PROJECTION_REQUIRED';end if;
  for r in select pe.id,sm.source_id transfer_id,x.source_line_id transfer_line_id,tr.branch_id,tr.destination_branch_id,tr.version transfer_version,
    -pe.quantity-coalesce((select sum(rest.quantity) from inventory.receipt_provenance_entries rest where rest.restores_entry_id=pe.id),0) quantity
   from inventory.receipt_provenance_entries pe join inventory.stock_movement_lines x on x.id=pe.movement_line_id
   join inventory.stock_movements sm on sm.id=x.stock_movement_id join inventory.transfers tr on tr.tenant_id=t and tr.id=sm.source_id
   where pe.tenant_id=t and pe.origin_line_id=(item->>'receipt_line_id')::uuid and pe.quantity<0 and sm.source_type in('transfer.dispatch','transfer.reverse.issue')
   order by pe.id loop
   if r.quantity=0 then continue;end if;
   if r.quantity<0 or not exists(select 1 from inventory.transfers where tenant_id=t and id=r.transfer_id and status='in_transit') then
    raise exception using errcode='55000',message='LANDED_EXTENSION_TRANSIT_BASIS_REQUIRED';end if;
   perform core.wave3_require_scope(t,'inventory.valuation.post',e,r.branch_id);perform core.wave3_require_scope(t,'inventory.cost.view',e,r.branch_id);
   perform core.wave3_require_scope(t,'inventory.valuation.post',e,r.destination_branch_id);perform core.wave3_require_scope(t,'inventory.cost.view',e,r.destination_branch_id);
   q:=q+r.quantity;nextv:=round(share*q/(item->>'received_quantity')::numeric,6);
   legs:=legs||jsonb_build_array(item||jsonb_build_object('kind','transit','transfer_id',r.transfer_id,'transfer_line_id',r.transfer_line_id,
    'dispatch_entry_id',r.id::text,'branch_id',r.branch_id,'destination_branch_id',r.destination_branch_id,'transfer_version',r.transfer_version::text,'quantity',r.quantity::text,'value',(nextv-prev)::text));
   transit_value:=transit_value+nextv-prev;prev:=nextv;
  end loop;
  if q<>(item->>'held_quantity')::numeric+(item->>'transit_quantity')::numeric then raise exception using errcode='55000',message='LANDED_EXTENSION_TRANSIT_BASIS_REQUIRED';end if;
  legs:=legs||jsonb_build_array(item||jsonb_build_object('kind','consumed','branch_id',b,'quantity',item->>'consumed_quantity','value',(share-prev)::text));
 end loop;
 if jsonb_array_length(legs)>1000 then raise exception using errcode='54000',message='LANDED_EXTENSION_LEG_LIMIT';end if;
 result:=jsonb_build_object('tenant_id',t,'legal_entity_id',e,'branch_id',b,'root_id',root,'correction_of',prior.id,'document_date',d,'currency_code',currency,'basis_mode',mode,
  'offset_account_id',offset_id,'variance_account_id',variance_id,'total_amount',target::text,'amount',delta::text,
  'inventory_amount',held_value::text,'transit_amount',transit_value::text,'variance_amount',(delta-held_value-transit_value)::text,
  'receipts',receipts,'legs',legs,'attribution_rule','Recorded receipt quantities; original receipt value is an allocation weight, not carrying-cost provenance.');
 if octet_length(result::text)>1048576 then raise exception using errcode='54000',message='LANDED_EXTENSION_EVIDENCE_LIMIT';end if;
 return result||jsonb_build_object('basis_hash',md5(result::text));
end $$;
revoke all on function inventory.landed_extension_basis(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
create function api.preview_landed_extension(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_payload jsonb) returns jsonb
language sql security definer set search_path='' as $$select inventory.landed_extension_basis(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload)$$;

create function api.post_landed_extension(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;parent uuid:=(p_payload->>'correction_of')::uuid;basis jsonb;h text;result jsonb;leg jsonb;
 req uuid:=gen_random_uuid();lid uuid;jid uuid;journals jsonb:='[]';v numeric;doc jsonb;account uuid;reason text:=btrim(p_payload->>'reason');reference text:=btrim(p_payload->>'reference');begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if v_id is null or p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or coalesce(length(reason),0) not between 3 and 1000 or coalesce(length(reference),0) not between 1 and 140 then
  raise exception using errcode='22023',message='LANDED_EXTENSION_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.landed.extension',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'inventory.landed.extension',p_command_id,p_idempotency_key,h);
 if result is not null then
  for leg in select value from jsonb_array_elements(result#>'{entity,legs}') loop
   perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,(leg->>'branch_id')::uuid);
   perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,(leg->>'branch_id')::uuid);
   if leg->>'destination_branch_id' is not null then
    perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,(leg->>'destination_branch_id')::uuid);
    perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,(leg->>'destination_branch_id')::uuid);
   end if;
  end loop;return result;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('landed.extension:'||coalesce(parent,v_id)::text,0));
 perform core.wave3_assert_expected_version(case when parent is null then 0 else 1 end,p_expected_entity_version,'{}');
 basis:=inventory.landed_extension_basis(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
 if basis->>'basis_hash' is distinct from p_payload->>'basis_hash' then raise exception using errcode='40001',message='LANDED_EXTENSION_PREVIEW_CHANGED';end if;
 doc:=jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'document_date',basis->>'document_date',
  'currency_code',basis->>'currency_code','base_currency_code',basis->>'currency_code','exchange_rate','1');
 for leg in select value from jsonb_array_elements(basis->'legs') loop
  v:=(leg->>'value')::numeric;if v=0 then continue;end if;
  account:=case when leg->>'kind'='consumed' then (basis->>'variance_account_id')::uuid else (leg->>'inventory_account_id')::uuid end;
  if leg->>'kind'='held' then
   lid:=inventory.landed_extension_stock_value(p_tenant_id,p_legal_entity_id,(leg->>'branch_id')::uuid,(leg->>'warehouse_id')::uuid,
    (leg->>'product_id')::uuid,(leg->>'receipt_line_id')::uuid,v_id,(basis->>'document_date')::date,v,req,p_command_id);
  elsif leg->>'kind'='transit' then
   if v<0 and (select l.carrying_value+coalesce((select sum(s.amount) from inventory.landed_extension_transit s where s.tenant_id=p_tenant_id and s.transfer_line_id=l.id
    and not exists(select 1 from inventory.landed_extension_settlements z where z.transit_id=s.id)),0)+v from inventory.transfer_lines l where l.id=(leg->>'transfer_line_id')::uuid)<0 then
    raise exception using errcode='55000',message='LANDED_EXTENSION_TRANSIT_VALUE_UNAVAILABLE';end if;
   insert into inventory.landed_extension_transit(id,tenant_id,extension_id,origin_line_id,transfer_id,transfer_line_id,dispatch_entry_id,amount,inventory_account_id,posting_date,branch_id)
   values(gen_random_uuid(),p_tenant_id,v_id,(leg->>'receipt_line_id')::uuid,(leg->>'transfer_id')::uuid,(leg->>'transfer_line_id')::uuid,
    (leg->>'dispatch_entry_id')::bigint,v,account,(basis->>'document_date')::date,(leg->>'branch_id')::uuid);
  end if;
  jid:=finance.flow_post_journal(doc||jsonb_build_object('branch_id',leg->>'branch_id'),jsonb_build_array(
   finance.flow_jline(account,v,v,v_id),finance.flow_jline((basis->>'offset_account_id')::uuid,-v,-v,v_id)),
   'landed_extension',gen_random_uuid(),req,p_command_id);journals:=journals||jsonb_build_array(jid);
 end loop;
 result:=basis||jsonb_build_object('id',v_id,'version',1,'status','posted','reference',reference,'reason',reason,'journal_ids',journals);
 insert into inventory.landed_extensions(id,tenant_id,legal_entity_id,branch_id,correction_of,root_id,document_date,reference,reason,total_amount,amount,detail,request_id,command_id,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,parent,(basis->>'root_id')::uuid,(basis->>'document_date')::date,reference,reason,
  (basis->>'total_amount')::numeric,(basis->>'amount')::numeric,result,req,p_command_id,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'inventory.landed.extension',p_command_id,'landed_extension',v_id,p_idempotency_key,h,null,result,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','posted','operation',case when parent is null then 'post' else 'correct' end,'reason',reason),
  jsonb_build_array(jsonb_build_object('topic','inventory.landed.extension','payload',jsonb_build_object('id',v_id))),'[]',req,req);
end $$;

-- Delegate transfer quantity/original cost to the established primitive. Separate
-- value-only settlement movements preserve the dispatch line and trace identities.
alter function inventory.transfer_leg(uuid,uuid,uuid,uuid,uuid,inventory.transfer_lines,date,numeric,numeric,text,uuid,uuid) rename to landed_extension_original_transfer_leg;
create function inventory.transfer_leg(p_tenant uuid,p_entity uuid,p_branch uuid,p_warehouse uuid,p_transfer uuid,p_line inventory.transfer_lines,
 p_date date,p_quantity numeric,p_value numeric,p_operation text,p_request uuid,p_command uuid) returns void
language plpgsql security definer set search_path='' as $$declare r record;lid uuid;v numeric;begin
 if p_operation='transfer.reverse.issue' and exists(select 1 from inventory.landed_extensions a,jsonb_array_elements(a.detail->'legs') leg
  where a.tenant_id=p_tenant and leg->>'kind'='held' and leg->>'warehouse_id'=p_warehouse::text and leg->>'product_id'=p_line.product_id::text
  and (leg->>'value')::numeric<>0 and a.created_at>(select min(created_at) from inventory.transfer_events where tenant_id=p_tenant and transfer_id=p_transfer and operation in('receive','immediate'))) then
  raise exception using errcode='55000',message='LANDED_EXTENSION_TRANSFER_CORRECTION_REVIEW';end if;
 if p_operation='transfer.reverse.issue' then
  for r in select s.*,a.command_id,a.request_id from inventory.landed_extension_transit s join inventory.landed_extensions a on a.id=s.extension_id
   where s.tenant_id=p_tenant and s.transfer_line_id=p_line.id and exists(select 1 from inventory.landed_extension_settlements z where z.transit_id=s.id and z.operation='transfer.receive') order by s.id loop
   if p_date<r.posting_date then raise exception using errcode='55000',message='LANDED_EXTENSION_BACKDATED_REVIEW';end if;
   lid:=inventory.landed_extension_stock_value(p_tenant,p_entity,p_branch,p_warehouse,p_line.product_id,r.origin_line_id,r.extension_id,p_date,-r.amount,p_request,p_command);
   insert into inventory.landed_extension_settlements(tenant_id,transit_id,operation,posting_date,movement_line_id,amount)
   values(p_tenant,r.id,p_operation,p_date,lid,-r.amount);
  end loop;
 end if;
 perform inventory.landed_extension_original_transfer_leg(p_tenant,p_entity,p_branch,p_warehouse,p_transfer,p_line,p_date,p_quantity,p_value,p_operation,p_request,p_command);
 if p_operation in('transfer.receive','transfer.reverse.receipt') then
  for r in select s.* from inventory.landed_extension_transit s where s.tenant_id=p_tenant and s.transfer_line_id=p_line.id
   and (not exists(select 1 from inventory.landed_extension_settlements z where z.transit_id=s.id)
    or (p_operation='transfer.reverse.receipt' and exists(select 1 from inventory.landed_extension_settlements z where z.transit_id=s.id and z.operation='transfer.reverse.issue')))
   order by s.id loop
   if p_date<r.posting_date then raise exception using errcode='55000',message='LANDED_EXTENSION_BACKDATED_REVIEW';end if;
   lid:=inventory.landed_extension_stock_value(p_tenant,p_entity,p_branch,p_warehouse,p_line.product_id,r.origin_line_id,r.extension_id,p_date,r.amount,p_request,p_command);
   insert into inventory.landed_extension_settlements(tenant_id,transit_id,operation,posting_date,movement_line_id,amount)
   values(p_tenant,r.id,p_operation,p_date,lid,r.amount);
  end loop;
 end if;
end $$;
revoke all on function inventory.transfer_leg(uuid,uuid,uuid,uuid,uuid,inventory.transfer_lines,date,numeric,numeric,text,uuid,uuid) from public,anon,authenticated;

-- Original-cost receipt reversal must not strand an incremental charge. A chain
-- reduced to zero may proceed through the existing independent stock guards.
create function inventory.guard_landed_extension_receipt() returns trigger language plpgsql security definer set search_path='' as $$
declare m inventory.stock_movements%rowtype;begin
 select * into m from inventory.stock_movements where id=new.stock_movement_id;
 if m.source_type='goods_receipt_reversal' and exists(select 1 from inventory.landed_extensions a,jsonb_array_elements(a.detail->'receipts') r
  where a.tenant_id=new.tenant_id and r->>'receipt_line_id'=new.original_movement_line_id::text and (r->>'target_allocation')::numeric<>0
  and not exists(select 1 from inventory.landed_extensions c where c.tenant_id=a.tenant_id and c.correction_of=a.id)) then
  raise exception using errcode='55000',message='LANDED_EXTENSION_CORRECT_FIRST';end if;
 return new;
end $$;
revoke all on function inventory.guard_landed_extension_receipt() from public,anon,authenticated;
create trigger guard_landed_extension_receipt before insert on inventory.stock_movement_lines for each row execute function inventory.guard_landed_extension_receipt();

-- Dated reports include immutable supplements until their first settlement. The
-- same wrapper is used by close controls; no saved historical report is changed.
alter function inventory.build_valuation_report(uuid,uuid,uuid,jsonb) rename to landed_extension_original_valuation_report;
create function inventory.build_valuation_report(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;extra jsonb;movements jsonb;diffs jsonb;transit jsonb;held numeric;tv numeric;gv numeric;d date:=(p->>'as_of')::date;begin
 result:=inventory.landed_extension_original_valuation_report(t,e,b,p);
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'evidence_key','command:'||a.command_id,'extension_id',a.id,'transfer_id',s.transfer_id,
  'transfer_line_id',s.transfer_line_id,'receipt_line_id',s.origin_line_id,'quantity','0','value',s.amount::text,'posting_date',s.posting_date,
  'kind','landed_extension_transit') order by s.id),'[]') into extra
 from inventory.landed_extension_transit s join inventory.landed_extensions a on a.id=s.extension_id
 where s.tenant_id=t and a.legal_entity_id=e and s.posting_date<=d
 and not exists(select 1 from inventory.landed_extension_settlements z where z.transit_id=s.id and z.posting_date<=d);
 transit:=(result->'transit')||extra;
 -- Settlement movements are real ledger evidence of an already posted charge;
 -- attribute them to that charge while preserving the actual transfer command.
 select coalesce(jsonb_agg(case when s.id is null then x else x||jsonb_build_object('transfer_command_id',x->>'command_id',
  'evidence_key','command:'||a.command_id,'landed_extension_id',a.id) end order by x->>'id'),'[]') into movements
 from jsonb_array_elements(result->'movements')x left join inventory.landed_extension_settlements z on z.tenant_id=t and z.movement_line_id=(x->>'id')::uuid
 left join inventory.landed_extension_transit s on s.id=z.transit_id left join inventory.landed_extensions a on a.id=s.extension_id;
 if greatest(jsonb_array_length(transit),jsonb_array_length(movements))>10000 then raise exception using errcode='54000',message='VALUATION_INPUT_LIMIT';end if;
 with entries as(select x->>'evidence_key' k,(x->>'value')::numeric v,0::numeric g from jsonb_array_elements(movements)x
  union all select x->>'evidence_key',(x->>'value')::numeric,0 from jsonb_array_elements(transit)x
  union all select x->>'evidence_key',0,(x->>'value')::numeric from jsonb_array_elements(result->'journals')x),totals as(select k,sum(v)v,sum(g)g from entries group by k)
 select coalesce(jsonb_agg(jsonb_build_object('id',k,'evidence_key',k,'inventory_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by k),'[]') into diffs from totals where v<>g;
 select coalesce(sum((x->>'value')::numeric),0) into tv from jsonb_array_elements(transit)x;
 held:=(result#>>'{summary,warehouse_value}')::numeric;gv:=(result#>>'{summary,gl_value}')::numeric;
 result:=result||jsonb_build_object('movements',movements,'transit',transit,'differences',diffs,'summary',(result->'summary')||
  jsonb_build_object('transit_value',tv::text,'inventory_value',(held+tv)::text,'difference',(held+tv-gv)::text,'difference_count',jsonb_array_length(diffs)));
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='VALUATION_EVIDENCE_LIMIT';end if;
 return result;
end $$;
revoke all on function inventory.build_valuation_report(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
create function api.landed_extension_documents(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(x.detail order by x.id),'[]') into rows from(
  select a.id,a.detail||jsonb_build_object('has_correction',exists(select 1 from inventory.landed_extensions c where c.tenant_id=a.tenant_id and c.correction_of=a.id)) detail
  from inventory.landed_extensions a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id and a.branch_id=p_branch_id and (p_after is null or a.id>p_after)
  and not exists(select 1 from jsonb_array_elements(a.detail->'legs')leg
   where not core.has_permission(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,(leg->>'branch_id')::uuid)
    or not core.has_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,(leg->>'branch_id')::uuid)
    or (leg->>'destination_branch_id' is not null and (
     not core.has_permission(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,(leg->>'destination_branch_id')::uuid)
     or not core.has_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,(leg->>'destination_branch_id')::uuid))))
  order by a.id limit 51)x;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',cursor);
end $$;
revoke all on function api.landed_extension_documents(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.landed_extension_documents(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function api.preview_landed_extension(uuid,uuid,uuid,jsonb),api.post_landed_extension(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.preview_landed_extension(uuid,uuid,uuid,jsonb),api.post_landed_extension(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
notify pgrst,'reload schema';
