-- Candidate: quantity attribution only; existing valuation/journal engines are unchanged.
create table inventory.receipt_provenance_entries (
 id bigint generated always as identity primary key,
 tenant_id uuid not null, legal_entity_id uuid not null, branch_id uuid not null,
 movement_line_id uuid not null, origin_line_id uuid, restores_entry_id bigint,
 warehouse_id uuid not null, product_id uuid not null, lot_id uuid, serial_id uuid,
 quantity numeric(20,6) not null check(quantity<>0), recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,id),
 foreign key(tenant_id,movement_line_id) references inventory.stock_movement_lines(tenant_id,id),
 foreign key(tenant_id,origin_line_id) references inventory.stock_movement_lines(tenant_id,id),
 foreign key(tenant_id,restores_entry_id) references inventory.receipt_provenance_entries(tenant_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(product_id) references inventory.products(id),
 foreign key(tenant_id,lot_id) references inventory.lots(tenant_id,id),
 foreign key(tenant_id,serial_id) references inventory.serials(tenant_id,id)
);
create table inventory.receipt_provenance_positions (
 id bigint generated always as identity primary key,
 tenant_id uuid not null, warehouse_id uuid not null, product_id uuid not null,
 lot_id uuid, serial_id uuid, origin_line_id uuid, entry_id bigint,
 quantity numeric(20,6) not null check(quantity>=0),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(product_id) references inventory.products(id),
 foreign key(tenant_id,lot_id) references inventory.lots(tenant_id,id),
 foreign key(tenant_id,serial_id) references inventory.serials(tenant_id,id),
 foreign key(tenant_id,origin_line_id) references inventory.stock_movement_lines(tenant_id,id),
 foreign key(tenant_id,entry_id) references inventory.receipt_provenance_entries(tenant_id,id)
);
create table inventory.receipt_provenance_pools (
 tenant_id uuid not null,warehouse_id uuid not null,product_id uuid not null,lot_id uuid,serial_id uuid,
 captured_at timestamptz not null default clock_timestamp(), baseline_quantity numeric(20,6) not null check(baseline_quantity>=0),
 unique nulls not distinct(tenant_id,warehouse_id,product_id,lot_id,serial_id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(product_id) references inventory.products(id),
 foreign key(tenant_id,lot_id) references inventory.lots(tenant_id,id),
 foreign key(tenant_id,serial_id) references inventory.serials(tenant_id,id)
);
create index provenance_position_pool on inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,lot_id,serial_id,id) where quantity>0;
create index provenance_entry_movement on inventory.receipt_provenance_entries(tenant_id,movement_line_id,id);
create index provenance_entry_origin on inventory.receipt_provenance_entries(tenant_id,origin_line_id,id);
create index provenance_entry_restore on inventory.receipt_provenance_entries(tenant_id,restores_entry_id);
create index provenance_position_origin on inventory.receipt_provenance_positions(tenant_id,origin_line_id);
do $$declare t text; f record; begin
 foreach t in array array['receipt_provenance_entries','receipt_provenance_positions','receipt_provenance_pools'] loop
  execute format('alter table inventory.%I enable row level security',t);
  execute format('alter table inventory.%I force row level security',t);
  execute format('revoke all on inventory.%I from public,anon,authenticated',t);
  for f in select c.conname,c.conkey,(select string_agg(quote_ident(a.attname),',' order by k.n) from unnest(c.conkey) with ordinality k(num,n)
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols from pg_constraint c
   where c.conrelid=format('inventory.%I',t)::regclass and c.contype='f' loop
   if exists(select 1 from pg_index i where i.indrelid=format('inventory.%I',t)::regclass and i.indisvalid and i.indpred is null
    and (select array_agg(k.num::smallint order by k.n) from unnest(i.indkey) with ordinality k(num,n) where k.n<=cardinality(f.conkey))=f.conkey) then continue;end if;
   execute format('create index %I on inventory.%I(%s)',left(t,19)||'_'||md5(f.conname)||'_fk',t,f.cols);
  end loop;
 end loop;
end $$;
create trigger immutable before update or delete on inventory.receipt_provenance_entries for each row execute function workflow.reject_history_mutation();
create trigger immutable before update or delete on inventory.receipt_provenance_pools for each row execute function workflow.reject_history_mutation();

create function inventory.record_receipt_provenance() returns trigger language plpgsql security definer set search_path='' as $$
declare m inventory.stock_movements%rowtype; related uuid; sid uuid; ids uuid[]; q numeric; prior numeric; available numeric;
 remaining numeric; take numeric; eid bigint; origin uuid; pos record; entry record; v_source_type text; steps integer:=0;
begin
 if new.base_quantity=0 then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text||':'||new.warehouse_id::text||':'||new.product_id::text,0));
 select * into strict m from inventory.stock_movements where tenant_id=new.tenant_id and id=new.stock_movement_id;
 related:=new.original_movement_line_id;
 if m.source_type in('transfer.receive','transfer.reverse.receipt','transfer.reverse.issue') then
  v_source_type:=case when m.source_type='transfer.receive' then 'transfer.dispatch'
   when m.source_type='transfer.reverse.issue' then 'transfer.receive'
   when exists(select 1 from inventory.stock_movements x where x.tenant_id=new.tenant_id and x.source_id=m.source_id and x.source_type='transfer.reverse.issue') then 'transfer.reverse.issue'
   else 'transfer.dispatch' end;
  select l.id into related from inventory.stock_movement_lines l join inventory.stock_movements x on x.id=l.stock_movement_id
   where x.tenant_id=new.tenant_id and x.source_id=m.source_id and x.source_type=v_source_type and l.source_line_id=new.source_line_id;
  if related is null then raise exception using errcode='55000',message='PROVENANCE_TRANSFER_SOURCE_MISSING';end if;
 end if;
 ids:=case when cardinality(new.serial_ids)>0 then new.serial_ids else array[null::uuid] end;
 if cardinality(new.serial_ids)>0 and abs(new.base_quantity)<>cardinality(new.serial_ids) then raise exception using errcode='55000',message='PROVENANCE_SERIAL_QUANTITY_MISMATCH';end if;
 foreach sid in array ids loop
  q:=case when sid is null then new.base_quantity else sign(new.base_quantity) end;
  if sid is not null and q>0 and m.source_type='stock_count' then
   -- A governed recount restores the same missing serial, not an invented receipt.
   select e.movement_line_id into related from inventory.receipt_provenance_entries e
    join inventory.stock_movement_lines ml on ml.id=e.movement_line_id join inventory.stock_movements sm on sm.id=ml.stock_movement_id
    where e.tenant_id=new.tenant_id and e.serial_id=sid and e.warehouse_id=new.warehouse_id and e.quantity<0 and sm.source_type='stock_count'
    and not exists(select 1 from inventory.receipt_provenance_entries r where r.restores_entry_id=e.id) order by e.id desc limit 1;
  end if;
  -- Transfer validates serial disposition after its ledger leg; preserve that public error.
  if sid is not null and m.source_type='transfer.dispatch' and not exists(select 1 from inventory.serials s
   where s.tenant_id=new.tenant_id and s.id=sid and s.warehouse_id=new.warehouse_id and s.status='available') then
   raise exception using errcode='55000',message='TRANSFER_SERIAL_UNAVAILABLE';end if;
  if not exists(select 1 from inventory.receipt_provenance_pools p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id
   and p.lot_id is not distinct from new.lot_id and p.serial_id is not distinct from sid) then
   if sid is not null then prior:=case when q<0 then 1 else 0 end;
   elsif new.lot_id is not null then
    select on_hand_quantity-q into prior from inventory.lot_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and lot_id=new.lot_id;
   else
    select on_hand_quantity-q into prior from inventory.stock_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and product_id=new.product_id;
    -- Untracked pool excludes independently tracked pools if legacy synthetic data mixed tracking modes.
    prior:=prior-coalesce((select sum(quantity) from inventory.receipt_provenance_positions p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id and (p.lot_id is not null or p.serial_id is not null)),0);
   end if;
   if prior is null or prior<0 then raise exception using errcode='55000',message='PROVENANCE_BASELINE_INVALID';end if;
   insert into inventory.receipt_provenance_pools(tenant_id,warehouse_id,product_id,lot_id,serial_id,baseline_quantity)
    values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,prior);
   if prior>0 then insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,lot_id,serial_id,quantity)
    values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,prior);end if;
  end if;
  remaining:=abs(q);
  if sid is not null then
   select coalesce(sum(p.quantity),0)+q into available from inventory.receipt_provenance_positions p
    where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id and p.serial_id=sid;
   if available not in(0,1) then raise exception using errcode='55000',message='PROVENANCE_SERIAL_QUANTITY_MISMATCH';end if;
  end if;
  if sid is null then
   select coalesce(sum(p.quantity),0)+q into available from inventory.receipt_provenance_positions p
    where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id
    and p.lot_id is not distinct from new.lot_id and p.serial_id is null;
   if new.lot_id is not null then
    select on_hand_quantity into prior from inventory.lot_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and lot_id=new.lot_id;
   else
    select on_hand_quantity-coalesce((select sum(p.quantity) from inventory.receipt_provenance_positions p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id and (p.lot_id is not null or p.serial_id is not null)),0)
     into prior from inventory.stock_balances where tenant_id=new.tenant_id and warehouse_id=new.warehouse_id and product_id=new.product_id;
   end if;
   if available is distinct from prior then raise exception using errcode='55000',message='PROVENANCE_STOCK_MISMATCH';end if;
  end if;
  if q<0 then
   for pos in select * from inventory.receipt_provenance_positions p where p.tenant_id=new.tenant_id and p.warehouse_id=new.warehouse_id and p.product_id=new.product_id
    and p.lot_id is not distinct from new.lot_id and p.serial_id is not distinct from sid and p.quantity>0
    order by case when related is not null and (p.origin_line_id=related or p.entry_id in(select e.id from inventory.receipt_provenance_entries e where e.movement_line_id=related)) then 0 else 1 end,p.id for update loop
    take:=least(remaining,pos.quantity);
    steps:=steps+1;if steps>1000 then raise exception using errcode='54000',message='PROVENANCE_MOVEMENT_LIMIT';end if;
    insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,warehouse_id,product_id,lot_id,serial_id,quantity)
     values(new.tenant_id,new.legal_entity_id,new.branch_id,new.id,pos.origin_line_id,new.warehouse_id,new.product_id,new.lot_id,sid,-take);
    update inventory.receipt_provenance_positions set quantity=quantity-take where id=pos.id;
    remaining:=remaining-take;exit when remaining=0;
   end loop;
   if remaining<>0 then raise exception using errcode='55000',message='PROVENANCE_STOCK_MISMATCH';end if;
  else
   -- Returns and transfer receipts restore the exact recorded negative attribution.
   if related is not null then
    for entry in select e.*, -e.quantity-coalesce((select sum(r.quantity) from inventory.receipt_provenance_entries r where r.restores_entry_id=e.id),0) restorable
     from inventory.receipt_provenance_entries e where e.tenant_id=new.tenant_id and e.movement_line_id=related and e.quantity<0 and e.serial_id is not distinct from sid order by e.id loop
     take:=least(remaining,entry.restorable);if take<=0 then continue;end if;
     steps:=steps+1;if steps>1000 then raise exception using errcode='54000',message='PROVENANCE_MOVEMENT_LIMIT';end if;
     insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,restores_entry_id,warehouse_id,product_id,lot_id,serial_id,quantity)
      values(new.tenant_id,new.legal_entity_id,new.branch_id,new.id,entry.origin_line_id,entry.id,new.warehouse_id,new.product_id,new.lot_id,sid,take) returning id into eid;
     insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,lot_id,serial_id,origin_line_id,entry_id,quantity)
      values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,entry.origin_line_id,eid,take);
     remaining:=remaining-take;exit when remaining=0;
    end loop;
    if remaining<>0 and exists(select 1 from inventory.receipt_provenance_entries e where e.tenant_id=new.tenant_id and e.movement_line_id=related) then
     raise exception using errcode='55000',message='PROVENANCE_RESTORE_EXCEEDS_SOURCE';end if;
   end if;
   if remaining>0 then
    origin:=case when m.source_type='goods_receipt' then new.id end;
    insert into inventory.receipt_provenance_entries(tenant_id,legal_entity_id,branch_id,movement_line_id,origin_line_id,warehouse_id,product_id,lot_id,serial_id,quantity)
     values(new.tenant_id,new.legal_entity_id,new.branch_id,new.id,origin,new.warehouse_id,new.product_id,new.lot_id,sid,remaining) returning id into eid;
    insert into inventory.receipt_provenance_positions(tenant_id,warehouse_id,product_id,lot_id,serial_id,origin_line_id,entry_id,quantity)
     values(new.tenant_id,new.warehouse_id,new.product_id,new.lot_id,sid,origin,eid,remaining);
   end if;
  end if;
 end loop;
 return new;
end $$;
revoke all on function inventory.record_receipt_provenance() from public,anon,authenticated;
create trigger receipt_provenance after insert on inventory.stock_movement_lines for each row execute function inventory.record_receipt_provenance();

create function api.receipt_trace_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb; cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from (
  select l.id,m.source_id receipt_id,coalesce(r.document_number,m.source_id::text) document_number,p.name product_name,w.name warehouse_name,
   l.base_quantity::text received_quantity,l.posting_date,exists(select 1 from inventory.receipt_provenance_entries e where e.tenant_id=l.tenant_id and e.origin_line_id=l.id) covered
  from inventory.stock_movement_lines l join inventory.stock_movements m on m.id=l.stock_movement_id and m.source_type='goods_receipt'
  join inventory.products p on p.id=l.product_id join core.warehouses w on w.id=l.warehouse_id
  left join procurement.goods_receipts r on r.id=m.source_id
  where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.branch_id=p_branch_id and l.base_quantity>0 and(p_after is null or l.id>p_after)
  order by l.id limit 51)q;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',cursor);
end $$;
create function api.receipt_trace_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_after bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare l inventory.stock_movement_lines%rowtype; holdings jsonb; history jsonb; cursor bigint; held numeric; transit numeric; covered boolean;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,p_branch_id);
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 select x.* into l from inventory.stock_movement_lines x join inventory.stock_movements m on m.id=x.stock_movement_id and m.source_type='goods_receipt'
  where x.id=p_id and x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.base_quantity>0;
 if not found then raise exception using errcode='P0002',message='RECEIPT_TRACE_NOT_FOUND';end if;
 if exists(select 1 from inventory.receipt_provenance_entries e where e.tenant_id=p_tenant_id and e.origin_line_id=p_id
  and (not core.has_permission(p_tenant_id,'inventory.valuation.post',p_legal_entity_id,e.branch_id)
   or not core.has_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,e.branch_id))) then
  raise exception using errcode='42501',message='RECEIPT_TRACE_BRANCH_SCOPE_REQUIRED';end if;
 covered:=exists(select 1 from inventory.receipt_provenance_entries e where e.tenant_id=p_tenant_id and e.origin_line_id=p_id);
 select coalesce(jsonb_agg(to_jsonb(q) order by q.warehouse_id),'[]') into holdings from (
  select p.warehouse_id,w.name warehouse_name,sum(p.quantity)::text quantity from inventory.receipt_provenance_positions p join core.warehouses w on w.id=p.warehouse_id
  where p.tenant_id=p_tenant_id and p.origin_line_id=p_id and p.quantity>0 group by p.warehouse_id,w.name order by p.warehouse_id limit 101)q;
 if jsonb_array_length(holdings)>100 then raise exception using errcode='54000',message='RECEIPT_TRACE_WAREHOUSE_LIMIT';end if;
 select coalesce(sum(quantity),0) into held from inventory.receipt_provenance_positions where tenant_id=p_tenant_id and origin_line_id=p_id;
 select coalesce(sum(-e.quantity-coalesce((select sum(r.quantity) from inventory.receipt_provenance_entries r where r.restores_entry_id=e.id),0)),0)
  into transit from inventory.receipt_provenance_entries e join inventory.stock_movement_lines ml on ml.id=e.movement_line_id
  join inventory.stock_movements m on m.id=ml.stock_movement_id where e.tenant_id=p_tenant_id and e.origin_line_id=p_id and e.quantity<0 and m.source_type in('transfer.dispatch','transfer.reverse.issue');
 select coalesce(jsonb_agg(to_jsonb(q) order by q.sequence),'[]') into history from (
  select e.id::text sequence,e.quantity::text quantity,e.recorded_at,m.source_type,m.source_id,ml.posting_date,w.name warehouse_name,
   lot.code lot_code,s.code serial_code,e.restores_entry_id::text restores_sequence
  from inventory.receipt_provenance_entries e join inventory.stock_movement_lines ml on ml.id=e.movement_line_id
  join inventory.stock_movements m on m.id=ml.stock_movement_id join core.warehouses w on w.id=e.warehouse_id
  left join inventory.lots lot on lot.id=e.lot_id left join inventory.serials s on s.id=e.serial_id
  where e.tenant_id=p_tenant_id and e.origin_line_id=p_id and (p_after is null or e.id>p_after) order by e.id limit 51)q;
 -- Preserve numeric sequence order, while exposing bigint as strings to clients.
 select coalesce(jsonb_agg(x order by (x->>'sequence')::bigint),'[]') into history from jsonb_array_elements(history)x;
 if jsonb_array_length(history)>50 then cursor:=(history->49->>'sequence')::bigint;history:=history-50;end if;
 return jsonb_build_object('id',p_id,'covered',covered,'received_quantity',l.base_quantity::text,
  'held_quantity',case when covered then held::text end,'in_transit_quantity',case when covered then transit::text end,
  'net_issued_quantity',case when covered then (l.base_quantity-held-transit)::text end,
  'holdings',holdings,'items',history,'next_cursor',cursor::text,'observed_at',statement_timestamp(),
  'attribution_rule','Oldest recorded cohort within each lot or untracked pool; exact serial identity. Weighted-average valuation is unchanged.');
end $$;
revoke all on function api.receipt_trace_page(uuid,uuid,uuid,uuid),api.receipt_trace_detail(uuid,uuid,uuid,uuid,bigint) from public,anon,authenticated;
grant execute on function api.receipt_trace_page(uuid,uuid,uuid,uuid),api.receipt_trace_detail(uuid,uuid,uuid,uuid,bigint) to authenticated;
notify pgrst, 'reload schema';


