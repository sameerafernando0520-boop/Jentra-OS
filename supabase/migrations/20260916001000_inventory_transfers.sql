-- Candidate only. Reuses the installed stock ledger; no applied migration is edited.
create table inventory.transfers (
 id uuid primary key, tenant_id uuid not null, legal_entity_id uuid not null,
 branch_id uuid not null, destination_branch_id uuid not null,
 source_warehouse_id uuid not null, destination_warehouse_id uuid not null,
 status text not null check(status in ('in_transit','completed','reversed')),
 version bigint not null default 1, document_date date not null, last_posting_date date not null,
 reference text not null, reason text not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(tenant_id,id), check(source_warehouse_id<>destination_warehouse_id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,destination_branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,source_warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,destination_warehouse_id) references core.warehouses(tenant_id,id)
);
create table inventory.transfer_lines (
 id uuid primary key, tenant_id uuid not null, transfer_id uuid not null,
 product_id uuid not null, base_quantity numeric(20,6) not null check(base_quantity>0),
 carrying_value numeric(20,6) not null check(carrying_value>=0),
 lot_id uuid, serial_ids uuid[] not null, detail jsonb not null,
 foreign key(tenant_id,transfer_id) references inventory.transfers(tenant_id,id),
 foreign key(tenant_id,lot_id) references inventory.lots(tenant_id,id)
);
create table inventory.transfer_events (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, transfer_id uuid not null,
 version bigint not null, operation text not null, posting_date date not null, reason text not null, reference text not null,
 command_id uuid not null, request_id uuid not null, destination_issue_snapshot jsonb not null default '{}', created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), unique(tenant_id,transfer_id,version),
 foreign key(tenant_id,transfer_id) references inventory.transfers(tenant_id,id)
);
create index transfers_scope_page on inventory.transfers(tenant_id,legal_entity_id,branch_id,id);
create index transfers_destination on inventory.transfers(tenant_id,legal_entity_id,destination_branch_id,id);
create index transfer_lines_parent on inventory.transfer_lines(tenant_id,transfer_id);
create index transfer_lines_lot on inventory.transfer_lines(tenant_id,lot_id);
create index transfer_lines_product on inventory.transfer_lines(tenant_id,product_id);
create index transfers_source_warehouse on inventory.transfers(tenant_id,source_warehouse_id);
create index transfers_destination_warehouse on inventory.transfers(tenant_id,destination_warehouse_id);
create index transfers_creator on inventory.transfers(created_by);
create index transfer_events_creator on inventory.transfer_events(created_by);
do $$declare t text;begin
 foreach t in array array['transfers','transfer_lines','transfer_events'] loop
  execute format('alter table inventory.%I enable row level security',t);
  execute format('alter table inventory.%I force row level security',t);
  execute format('revoke all on inventory.%I from public,anon,authenticated',t);
 end loop;
 foreach t in array array['transfer_lines','transfer_events'] loop
  execute format('create trigger immutable before update or delete on inventory.%I for each row execute function workflow.reject_history_mutation()',t);
 end loop;
end $$;
-- A disjoint constraint adds transfer kinds while preserving installed/candidate kinds.
do $$declare c text;begin
 select pg_get_constraintdef(oid) into c from pg_constraint
 where conrelid='inventory.stock_movements'::regclass and conname='stock_movements_movement_kind_check';
 if c is null then raise exception 'MOVEMENT_CONSTRAINT_DRIFT';end if;
 alter table inventory.stock_movements drop constraint stock_movements_movement_kind_check;
 execute 'alter table inventory.stock_movements add constraint stock_movements_movement_kind_check CHECK ('||substring(c from 7)||' OR movement_kind IN (''transfer_issue'',''transfer_receipt'',''stock_adjustment''))';
end $$;
alter table inventory.serials drop constraint serials_status_check;
alter table inventory.serials add constraint serials_status_check check(status in('available','issued','quarantine','disposed','in_transit'));

-- Private read projection deliberately excludes carrying value from command receipts.
create function inventory.transfer_document(p_tenant uuid,p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select to_jsonb(t)||jsonb_build_object('lines',coalesce((select jsonb_agg(l.detail order by l.id)
 from inventory.transfer_lines l where l.tenant_id=p_tenant and l.transfer_id=t.id),'[]'),
 'source_warehouse_name',(select name from core.warehouses where id=t.source_warehouse_id),
 'destination_warehouse_name',(select name from core.warehouses where id=t.destination_warehouse_id),
 'events',coalesce((select jsonb_agg(to_jsonb(e)-'destination_issue_snapshot' order by e.version) from inventory.transfer_events e
 where e.tenant_id=p_tenant and e.transfer_id=t.id),'[]'))
 from inventory.transfers t where t.tenant_id=p_tenant and t.id=p_id $$;
revoke all on function inventory.transfer_document(uuid,uuid) from public,anon,authenticated;

-- Apply one ledger leg under the caller's sorted warehouse/product locks.
create function inventory.transfer_leg(p_tenant uuid,p_entity uuid,p_branch uuid,p_warehouse uuid,
 p_transfer uuid,p_line inventory.transfer_lines,p_date date,p_quantity numeric,p_value numeric,
 p_operation text,p_request uuid,p_command uuid) returns void
language plpgsql security definer set search_path='' as $$
declare b inventory.stock_balances%rowtype; v inventory.stock_valuations%rowtype; m uuid;
begin
 if exists(select 1 from inventory.stock_movement_lines where tenant_id=p_tenant and warehouse_id=p_warehouse
 and product_id=p_line.product_id and posting_date>p_date) then
 raise exception using errcode='55000',message='BACKDATED_TRANSFER_REQUIRES_REVIEW';end if;
 insert into inventory.stock_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,created_by,updated_by)
 values(p_tenant,p_entity,p_branch,p_warehouse,p_line.product_id,auth.uid(),auth.uid())
 on conflict(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id) do nothing;
 select * into b from inventory.stock_balances where tenant_id=p_tenant and warehouse_id=p_warehouse and product_id=p_line.product_id for update;
 insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
 values(p_tenant,p_entity,p_branch,b.id,0,auth.uid(),auth.uid()) on conflict(tenant_id,stock_balance_id) do nothing;
 select * into v from inventory.stock_valuations where tenant_id=p_tenant and stock_balance_id=b.id for update;
 if b.available_quantity+p_quantity<0 or v.carrying_value+p_value<0
 or (b.on_hand_quantity+p_quantity=0 and v.carrying_value+p_value<>0) then
 raise exception using errcode='55000',message='TRANSFER_STOCK_UNAVAILABLE';end if;
 update inventory.stock_balances set on_hand_quantity=on_hand_quantity+p_quantity,updated_by=auth.uid() where id=b.id;
 update inventory.stock_valuations set carrying_value=carrying_value+p_value,updated_by=auth.uid() where id=v.id;
 if p_line.lot_id is not null then
  insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
  values(p_tenant,p_entity,p_branch,p_warehouse,p_line.product_id,p_line.lot_id,0,auth.uid(),auth.uid())
  on conflict(tenant_id,warehouse_id,lot_id) do nothing;
  update inventory.lot_balances set on_hand_quantity=on_hand_quantity+p_quantity,updated_by=auth.uid()
  where tenant_id=p_tenant and warehouse_id=p_warehouse and lot_id=p_line.lot_id and on_hand_quantity+p_quantity>=0;
  if not found then raise exception using errcode='55000',message='TRANSFER_LOT_UNAVAILABLE';end if;
 end if;
 select id into m from inventory.stock_movements where tenant_id=p_tenant and source_type=p_operation and source_id=p_transfer;
 if m is null then
  m:=gen_random_uuid();
  insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
  values(m,p_tenant,p_entity,p_branch,p_operation,p_transfer,p_warehouse,p_date,
   case when p_operation='stock_count' then 'stock_adjustment' when p_quantity<0 then 'transfer_issue' else 'transfer_receipt' end,p_request,p_command,p_request,auth.uid());
 end if;
 insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
 values(p_tenant,p_entity,p_branch,m,p_warehouse,p_line.product_id,p_line.id,p_quantity,p_value,p_line.lot_id,p_line.serial_ids,p_date,auth.uid());
end $$;
revoke all on function inventory.transfer_leg(uuid,uuid,uuid,uuid,uuid,inventory.transfer_lines,date,numeric,numeric,text,uuid,uuid) from public,anon,authenticated;

create function api.transfer_stock(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare t inventory.transfers%rowtype; l inventory.transfer_lines%rowtype; product inventory.products%rowtype;
 b inventory.stock_balances%rowtype; v inventory.stock_valuations%rowtype;
 id uuid:=(p_payload->>'id')::uuid; op text:=p_payload->>'operation'; d date:=(p_payload->>'document_date')::date;
 reason text:=trim(p_payload->>'reason'); reference text:=trim(p_payload->>'reference');
 h text; result jsonb; before_doc jsonb; req uuid:=gen_random_uuid(); x jsonb; resolved jsonb;
 wh uuid; prod uuid; serial uuid; from_wh uuid; to_wh uuid; from_branch uuid; to_branch uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null or id is null or d is null
 or op is null or op not in('dispatch','immediate','receive','reverse')
 or coalesce(length(reason),0) not between 1 and 1000 or coalesce(length(reference),0) not between 1 and 140 then
 raise exception using errcode='22023',message='TRANSFER_INPUT_INVALID';end if;
 if d>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 h:=core.wave3_request_hash('inventory.transfer',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 -- Check both scopes even for replay, before returning any saved document.
 perform pg_advisory_xact_lock(hashtextextended('inventory.transfer:'||id::text,0));
 select * into t from inventory.transfers where tenant_id=p_tenant_id and transfers.id=id for update;
 if t.id is not null then
  if t.legal_entity_id<>p_legal_entity_id or p_branch_id not in(t.branch_id,t.destination_branch_id) then
   raise exception using errcode='42501',message='TRANSFER_SCOPE_INVALID';end if;
  perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,t.branch_id);
  perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,t.destination_branch_id);
 end if;
 result:=core.wave3_replay(p_tenant_id,'inventory.transfer',p_command_id,p_idempotency_key,h);
 if result is not null then return result;end if;
 before_doc:=inventory.transfer_document(p_tenant_id,id);
 if op in('dispatch','immediate') then
  if t.id is not null then raise exception using errcode='55000',message='TRANSFER_ALREADY_EXISTS';end if;
  if p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
  t.id:=id;t.tenant_id:=p_tenant_id;t.legal_entity_id:=p_legal_entity_id;t.branch_id:=p_branch_id;
  t.source_warehouse_id:=(p_payload->>'source_warehouse_id')::uuid;t.destination_warehouse_id:=(p_payload->>'destination_warehouse_id')::uuid;
  select branch_id into t.destination_branch_id from core.warehouses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and warehouses.id=t.destination_warehouse_id;
  if t.destination_branch_id is null then raise exception using errcode='22023',message='TRANSFER_WAREHOUSE_INVALID';end if;
  perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,t.destination_branch_id);
  if jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines') not between 1 and 500 then
   raise exception using errcode='22023',message='TRANSFER_LINES_INVALID';end if;
 else
  if t.id is null then raise exception using errcode='P0002',message='TRANSFER_NOT_FOUND';end if;
  perform core.wave3_assert_expected_version(t.version,p_expected_entity_version,before_doc);
  if t.status='reversed' or (op='receive' and t.status<>'in_transit') then raise exception using errcode='55000',message='TRANSFER_STATE_INVALID';end if;
  if d<t.last_posting_date then raise exception using errcode='55000',message='BACKDATED_TRANSFER_REQUIRES_REVIEW';end if;
 end if;
 if t.source_warehouse_id is null or t.source_warehouse_id=t.destination_warehouse_id
 or not exists(select 1 from core.warehouses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=t.branch_id and warehouses.id=t.source_warehouse_id and status='active')
 or not exists(select 1 from core.warehouses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=t.destination_branch_id and warehouses.id=t.destination_warehouse_id and status='active')
 then raise exception using errcode='22023',message='TRANSFER_WAREHOUSE_INVALID';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,d);
 for wh,prod in select distinct w,p from unnest(array[t.source_warehouse_id,t.destination_warehouse_id]) w
 cross join (select (value->>'product_id')::uuid p from jsonb_array_elements(case when op in('dispatch','immediate') then p_payload->'lines' else before_doc->'lines' end)) q order by w,p loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||wh::text||':'||prod::text,0));
 end loop;
 if op in('dispatch','immediate') then
  insert into inventory.transfers(id,tenant_id,legal_entity_id,branch_id,destination_branch_id,source_warehouse_id,destination_warehouse_id,status,document_date,last_posting_date,reference,reason,created_by)
  values(id,p_tenant_id,p_legal_entity_id,t.branch_id,t.destination_branch_id,t.source_warehouse_id,t.destination_warehouse_id,'in_transit',d,d,reference,reason,auth.uid());
  for x in select value from jsonb_array_elements(p_payload->'lines') order by value->>'product_id',value->>'line_id' loop
   l:=null;l.id:=(x->>'line_id')::uuid;l.tenant_id:=p_tenant_id;l.transfer_id:=id;l.product_id:=(x->>'product_id')::uuid;
   select * into product from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and products.id=l.product_id and kind='stocked' and status='active' for share;
   if not found or l.id is null then raise exception using errcode='22023',message='TRANSFER_PRODUCT_INVALID';end if;
   resolved:=inventory.resolve_product_unit(p_tenant_id,p_legal_entity_id,l.product_id,(x->>'unit_id')::uuid,x->'quantity',x->'conversion_numerator',x->'conversion_denominator');
   l.base_quantity:=(resolved->>'base_quantity')::numeric;l.lot_id:=(x->>'lot_id')::uuid;
   if jsonb_typeof(coalesce(x->'serial_ids','[]'))<>'array' or jsonb_array_length(coalesce(x->'serial_ids','[]'))>1000 then raise exception using errcode='22023',message='TRANSFER_TRACKING_INVALID';end if;
   select coalesce(array_agg(s::uuid order by s),'{}') into l.serial_ids from jsonb_array_elements_text(coalesce(x->'serial_ids','[]')) s;
   if (product.tracking_mode='lot' and not exists(select 1 from inventory.lots where tenant_id=p_tenant_id and product_id=l.product_id and lots.id=l.lot_id and status='saleable' and (expiry_date is null or expiry_date>=greatest(d,(clock_timestamp() at time zone 'UTC')::date))))
    or (product.tracking_mode<>'lot' and l.lot_id is not null)
    or (product.tracking_mode<>'serial' and cardinality(l.serial_ids)>0)
    or (product.tracking_mode='serial' and (cardinality(l.serial_ids)<>l.base_quantity or cardinality(l.serial_ids)<>(select count(distinct s) from unnest(l.serial_ids)s))) then
    raise exception using errcode='22023',message='TRANSFER_TRACKING_INVALID';end if;
   select * into b from inventory.stock_balances where tenant_id=p_tenant_id and warehouse_id=t.source_warehouse_id and product_id=l.product_id for update;
   select * into v from inventory.stock_valuations where tenant_id=p_tenant_id and stock_balance_id=b.id for update;
   if b.id is null or v.id is null or b.available_quantity<l.base_quantity then raise exception using errcode='55000',message='TRANSFER_STOCK_UNAVAILABLE';end if;
   l.carrying_value:=case when l.base_quantity=b.on_hand_quantity then v.carrying_value else round(v.carrying_value*l.base_quantity/b.on_hand_quantity,6) end;
   l.detail:=jsonb_build_object('line_id',l.id,'product_id',l.product_id,'product_name',product.name,'unit_id',x->>'unit_id','quantity',x->>'quantity','lot_id',l.lot_id,'serial_ids',to_jsonb(l.serial_ids))||resolved;
   insert into inventory.transfer_lines select l.*;
   perform inventory.transfer_leg(p_tenant_id,p_legal_entity_id,t.branch_id,t.source_warehouse_id,id,l,d,-l.base_quantity,-l.carrying_value,'transfer.dispatch',req,p_command_id);
   foreach serial in array l.serial_ids loop
    update inventory.serials set status='in_transit',updated_by=auth.uid() where tenant_id=p_tenant_id and serials.id=serial and product_id=l.product_id and warehouse_id=t.source_warehouse_id and status='available';
    if not found then raise exception using errcode='55000',message='TRANSFER_SERIAL_UNAVAILABLE';end if;
   end loop;
  end loop;
 end if;
 if op in('receive','immediate','reverse') then
  to_wh:=case when op='reverse' then t.source_warehouse_id else t.destination_warehouse_id end;
  to_branch:=case when op='reverse' then t.branch_id else t.destination_branch_id end;
  for l in select * from inventory.transfer_lines where tenant_id=p_tenant_id and transfer_id=id order by product_id,transfer_lines.id loop
   if op='reverse' and t.status='completed' then
    -- Conservative correction guard: any later issue of this product requires review.
    if coalesce((select sum(-ml.base_quantity) from inventory.stock_movement_lines ml join inventory.stock_movements m on m.id=ml.stock_movement_id
     where ml.tenant_id=p_tenant_id and ml.warehouse_id=t.destination_warehouse_id and ml.product_id=l.product_id and ml.base_quantity<0 and m.command_id<>p_command_id),0)
     > coalesce((select (e.destination_issue_snapshot->>l.product_id::text)::numeric from inventory.transfer_events e
       where e.transfer_id=id and e.operation in('receive','immediate') limit 1),0) then
     raise exception using errcode='55000',message='TRANSFER_DESTINATION_CONSUMED';end if;
    perform inventory.transfer_leg(p_tenant_id,p_legal_entity_id,t.destination_branch_id,t.destination_warehouse_id,id,l,d,-l.base_quantity,-l.carrying_value,'transfer.reverse.issue',req,p_command_id);
   end if;
   perform inventory.transfer_leg(p_tenant_id,p_legal_entity_id,to_branch,to_wh,id,l,d,l.base_quantity,l.carrying_value,
    case when op='reverse' then 'transfer.reverse.receipt' else 'transfer.receive' end,req,p_command_id);
   foreach serial in array l.serial_ids loop
    from_wh:=case when op='reverse' and t.status='completed' then t.destination_warehouse_id else t.source_warehouse_id end;
    update inventory.serials set status='available',warehouse_id=to_wh,branch_id=to_branch,updated_by=auth.uid()
     where tenant_id=p_tenant_id and serials.id=serial and product_id=l.product_id and warehouse_id=from_wh
     and status=case when op='reverse' and t.status='completed' then 'available' else 'in_transit' end;
    if not found then raise exception using errcode='55000',message='TRANSFER_SERIAL_UNAVAILABLE';end if;
   end loop;
  end loop;
 end if;
 update inventory.transfers set status=case when op='reverse' then 'reversed' when op in('receive','immediate') then 'completed' else 'in_transit' end,
  version=case when op in('dispatch','immediate') then 1 else version+1 end,last_posting_date=d where tenant_id=p_tenant_id and transfers.id=id returning * into t;
 insert into inventory.transfer_events(tenant_id,transfer_id,version,operation,posting_date,reason,reference,command_id,request_id,destination_issue_snapshot,created_by)
 values(p_tenant_id,id,t.version,op,d,reason,reference,p_command_id,req,
  coalesce((select jsonb_object_agg(q.product_id,q.quantity::text) from
   (select ml.product_id,sum(-ml.base_quantity) quantity from inventory.stock_movement_lines ml
    where ml.tenant_id=p_tenant_id and ml.warehouse_id=t.destination_warehouse_id and ml.base_quantity<0 group by ml.product_id)q),'{}'),auth.uid());
 return core.wave3_finish_command(p_tenant_id,'inventory.transfer',p_command_id,'inventory_transfer',id,p_idempotency_key,h,before_doc,
 inventory.transfer_document(p_tenant_id,id),p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('from_status',before_doc->>'status','to_status',t.status,'operation',op,'reason',reason),
 jsonb_build_array(jsonb_build_object('topic','inventory.transfer','payload',jsonb_build_object('id',id,'status',t.status))),'[]',req,req);
end $$;
revoke all on function api.transfer_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.transfer_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function api.inventory_transfers(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,p_branch_id);
 select coalesce(jsonb_agg(inventory.transfer_document(p_tenant_id,t.id) order by t.id),'[]') into rows from
 (select * from inventory.transfers where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and p_branch_id in(branch_id,destination_branch_id) and (p_after is null or id>p_after)
 and core.has_permission(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,branch_id)
 and core.has_permission(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,destination_branch_id) order by id limit 51)t;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',next_id);
end $$;
revoke all on function api.inventory_transfers(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.inventory_transfers(uuid,uuid,uuid,uuid) to authenticated;

create function api.inventory_transfer_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,
 p_warehouse_id uuid default null,p_product_id uuid default null,p_after uuid default null,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,p_branch_id);
 if length(coalesce(p_search,''))>100 then raise exception using errcode='22023',message='SEARCH_TOO_LONG';end if;
 if p_resource='warehouses' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from
  (select w.id,w.name,w.code,w.branch_id from core.warehouses w where w.tenant_id=p_tenant_id and w.legal_entity_id=p_legal_entity_id
   and w.status='active' and core.has_permission(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,w.branch_id)
   and (p_after is null or w.id>p_after) and (w.name ilike '%'||p_search||'%' or w.code ilike '%'||p_search||'%') order by w.id limit 51)q;
 else
  if not exists(select 1 from core.warehouses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_warehouse_id and status='active') then
   raise exception using errcode='42501',message='TRANSFER_SCOPE_INVALID';end if;
  if p_resource='products' then
   select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from
   (select p.id,p.name,p.sku,p.base_unit_id,p.tracking_mode,b.available_quantity::text,u.name unit_name,
    jsonb_build_array(jsonb_build_object('id',u.id,'name',u.name,'numerator','1','denominator','1'))||
    coalesce((select jsonb_agg(jsonb_build_object('id',c.unit_id,'name',cu.name,'numerator',c.numerator::text,'denominator',c.denominator::text))
     from inventory.product_unit_conversions c join inventory.units cu on cu.id=c.unit_id where c.product_id=p.id and c.status='active' and cu.status='active'),'[]') units
    from inventory.products p join inventory.stock_balances b on b.product_id=p.id and b.warehouse_id=p_warehouse_id
    join inventory.units u on u.id=p.base_unit_id and u.status='active'
    where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.status='active' and p.kind='stocked' and b.available_quantity>0
    and (p_after is null or p.id>p_after) and (p.name ilike '%'||p_search||'%' or p.sku ilike '%'||p_search||'%') order by p.id limit 51)q;
  elsif p_resource='lots' then
   select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from
   (select l.id,l.code,l.expiry_date,b.on_hand_quantity::text from inventory.lots l join inventory.lot_balances b on b.lot_id=l.id and b.warehouse_id=p_warehouse_id
    where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.product_id=p_product_id and l.status='saleable' and b.on_hand_quantity>0
    and (l.expiry_date is null or l.expiry_date>=(clock_timestamp() at time zone 'UTC')::date)
    and (p_after is null or l.id>p_after) and l.code ilike '%'||p_search||'%' order by l.id limit 51)q;
  elsif p_resource='serials' then
   select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from
   (select s.id,s.code from inventory.serials s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.warehouse_id=p_warehouse_id
    and s.product_id=p_product_id and s.status='available' and (p_after is null or s.id>p_after) and s.code ilike '%'||p_search||'%' order by s.id limit 51)q;
  else raise exception using errcode='22023',message='TRANSFER_RESOURCE_INVALID';end if;
 end if;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',next_id);
end $$;
revoke all on function api.inventory_transfer_options(uuid,uuid,uuid,text,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.inventory_transfer_options(uuid,uuid,uuid,text,uuid,uuid,uuid,text) to authenticated;

create function api.inventory_transfer_holdings(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_as_of date,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,p_branch_id);
 if p_as_of is null or p_as_of>(clock_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='AS_OF_DATE_INVALID';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'reference',t.reference,'document_date',t.document_date,
  'source_warehouse_name',(select name from core.warehouses where id=t.source_warehouse_id),
  'destination_warehouse_name',(select name from core.warehouses where id=t.destination_warehouse_id),
  'currency_code',(select currency_code from core.legal_entities where id=t.legal_entity_id),
  'lines',(select jsonb_agg(l.detail||case when core.has_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,t.branch_id)
    and core.has_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,t.destination_branch_id)
    then jsonb_build_object('carrying_value',l.carrying_value::text) else '{}'::jsonb end order by l.id)
   from inventory.transfer_lines l where l.transfer_id=t.id)) order by t.id),'[]') into rows
 from (select tr.* from inventory.transfers tr where tr.tenant_id=p_tenant_id and tr.legal_entity_id=p_legal_entity_id
  and p_branch_id in(tr.branch_id,tr.destination_branch_id) and (p_after is null or tr.id>p_after)
  and tr.document_date<=p_as_of
  and exists(select 1 from inventory.transfer_events e where e.transfer_id=tr.id and e.operation='dispatch')
  and not exists(select 1 from inventory.transfer_events e where e.transfer_id=tr.id and e.operation in('receive','reverse') and e.posting_date<=p_as_of)
  and core.has_permission(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,tr.branch_id)
  and core.has_permission(p_tenant_id,'inventory.transfers.post',p_legal_entity_id,tr.destination_branch_id)
  order by tr.id limit 51)t;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('as_of',p_as_of,'items',rows,'next_cursor',next_id);
end $$;
revoke all on function api.inventory_transfer_holdings(uuid,uuid,uuid,date,uuid) from public,anon,authenticated;
grant execute on function api.inventory_transfer_holdings(uuid,uuid,uuid,date,uuid) to authenticated;

