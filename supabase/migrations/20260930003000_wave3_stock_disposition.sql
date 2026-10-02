-- UNAPPLIED candidate. Contract 51. No transfer ledger helper or movement labels.
insert into core.permissions(code,module,description,privileged)
values('inventory.dispositions.post','inventory','Post approved inventory disposition and linked corrections.',true)
on conflict(code) do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select tenant_id,id,'inventory.dispositions.post' from core.roles where code='tenant_owner'
on conflict(role_id,permission_code) do nothing;
-- Stock disposition candidate. Independent aggregate; reuses installed governance and ledger primitives.
create table inventory.stock_dispositions (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references core.tenants(id),
 legal_entity_id uuid not null, branch_id uuid not null, warehouse_id uuid not null,
 document_type text not null default 'inventory_disposition' check(document_type='inventory_disposition'), corrects_disposition_id uuid, reverses_disposition_id uuid, post_state jsonb,
 cutoff_at timestamptz not null, document_number text, document_date date not null, reason text not null check(length(trim(reason)) between 3 and 1000),
 currency_code text not null references core.currencies(code), offset_account_id uuid not null,
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 grand_total numeric(20,6) not null check(grand_total>=0),
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','rejected','cancelled','posted')),
 version bigint not null default 1, workflow_snapshot jsonb, submitted_by uuid references auth.users(id),
 posted_by uuid references auth.users(id), posted_at timestamptz, stock_movement_id uuid, journal_entry_id uuid,
 request_id uuid not null, command_id uuid not null, correlation_id uuid not null, client_timestamp timestamptz not null,
 prepared_by uuid not null references auth.users(id),
 created_by uuid not null references auth.users(id), updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tenant_id,id), unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,warehouse_id) references core.warehouses(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,offset_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,stock_movement_id) references inventory.stock_movements(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,corrects_disposition_id) references inventory.stock_dispositions(tenant_id,id),
 foreign key(tenant_id,reverses_disposition_id) references inventory.stock_dispositions(tenant_id,id),
 check(corrects_disposition_id is null or reverses_disposition_id is null),
 check((status='posted')=(posted_at is not null)),
 check(status<>'posted' or posted_by is not null)
);
alter table inventory.stock_dispositions enable row level security;
alter table inventory.stock_dispositions force row level security;
create policy disposition_permitted_read on inventory.stock_dispositions for select to authenticated using (
 core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,'inventory.cost.view',legal_entity_id,branch_id)
 and (core.has_permission(tenant_id,'inventory.dispositions.post',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'workflow.approvals.decide',legal_entity_id,branch_id))
);
create trigger disposition_immutable_posted before update or delete on inventory.stock_dispositions
 for each row execute function sales.flow_protect_document();
create trigger disposition_touch before update on inventory.stock_dispositions
 for each row execute function core.touch_mutable_record();
create index stock_dispositions_scope_idx on inventory.stock_dispositions(tenant_id,legal_entity_id,branch_id,status,id);
-- Lead each FK index with its referencing columns; retain the scoped register index.
do $$ declare f record; begin
 for f in select c.conname, (select string_agg(quote_ident(a.attname),',' order by k.n)
 from unnest(c.conkey) with ordinality k(num,n) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols
 from pg_constraint c where c.conrelid='inventory.stock_dispositions'::regclass and c.contype='f' loop
 execute format('create index %I on inventory.stock_dispositions(%s)',f.conname||'_idx',f.cols);
 end loop;
end $$;

create function api.post_stock_disposition(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'document_id')::uuid; req uuid:=gen_random_uuid(); h text; result jsonb; d jsonb; x jsonb;
 jlines jsonb:='[]'; j uuid; m uuid:=gen_random_uuid(); q numeric; amount numeric; v_date date; sid uuid; state jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.dispositions.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null or v_id is null then
 raise exception using errcode='22023',message='DISPOSITION_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.stock_disposition.post',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'inventory.stock_disposition.post',p_command_id,p_idempotency_key,h);if result is not null then return result;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':disposition:'||v_id::text,0));
 d:=inventory.disposition_document('inventory_disposition',p_tenant_id,v_id,true);
 if d is null or d->>'legal_entity_id'<>p_legal_entity_id::text or d->>'branch_id'<>p_branch_id::text then
 raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((d->>'version')::bigint,p_expected_entity_version,d);
 if d->>'status'<>'approved' then raise exception using errcode='55000',message='DISPOSITION_APPROVAL_REQUIRED';end if;
 perform sales.flow_assert_transition(d#>'{workflow_snapshot,lifecycle}','approved','posted');
 if d#>'{workflow_snapshot,lifecycle,separate_poster}'='true'::jsonb and (d->>'submitted_by')::uuid=auth.uid() then
 raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 v_date:=(d->>'document_date')::date;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 perform inventory.disposition_revalidate('inventory_disposition',d);
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,
 posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(m,p_tenant_id,p_legal_entity_id,p_branch_id,'inventory_disposition',v_id,(d->>'warehouse_id')::uuid,
 v_date,case when d->>'reverses_disposition_id' is null then 'disposition' else 'disposition_reversal' end,req,p_command_id,req,auth.uid());
 for x in select value from jsonb_array_elements(d->'lines') order by value->>'product_id',value->>'line_id' loop
  q:=(x->>'base_quantity')::numeric;amount:=(x->>'carrying_value')::numeric;
  if d->>'reverses_disposition_id' is null then q:=-q;amount:=-amount;end if;
  update inventory.stock_balances set on_hand_quantity=on_hand_quantity+q,updated_by=auth.uid()
  where tenant_id=p_tenant_id and warehouse_id=(d->>'warehouse_id')::uuid and product_id=(x->>'product_id')::uuid
  and available_quantity+q>=0;
  if not found then raise exception using errcode='55000',message='DISPOSITION_STOCK_UNAVAILABLE';end if;
  update inventory.stock_valuations v set carrying_value=carrying_value+amount,updated_by=auth.uid()
  from inventory.stock_balances b where v.tenant_id=p_tenant_id and v.stock_balance_id=b.id
  and b.tenant_id=p_tenant_id and b.warehouse_id=(d->>'warehouse_id')::uuid and b.product_id=(x->>'product_id')::uuid
  and v.carrying_value+amount>=0 and (b.on_hand_quantity<>0 or v.carrying_value+amount=0);
  if not found then raise exception using errcode='55000',message='DISPOSITION_VALUE_UNAVAILABLE';end if;
  if x->>'lot_id' is not null then
   update inventory.lot_balances set on_hand_quantity=on_hand_quantity+q,updated_by=auth.uid()
   where tenant_id=p_tenant_id and warehouse_id=(d->>'warehouse_id')::uuid and lot_id=(x->>'lot_id')::uuid
   and on_hand_quantity+q>=0;
   if not found then raise exception using errcode='55000',message='DISPOSITION_LOT_UNAVAILABLE';end if;
  end if;
  for sid in select value::uuid from jsonb_array_elements_text(x->'serial_ids') loop
   update inventory.serials set status='disposed',updated_by=auth.uid()
   where tenant_id=p_tenant_id and id=sid and warehouse_id=(d->>'warehouse_id')::uuid and status in('available','quarantine');
   if not found then raise exception using errcode='55000',message='DISPOSITION_SERIAL_UNAVAILABLE';end if;
  end loop;
  -- The existing receipt-provenance trigger consumes/restores exact source cohorts atomically.
  insert into inventory.stock_movement_lines(tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,
  product_id,source_line_id,original_movement_line_id,base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,m,(d->>'warehouse_id')::uuid,(x->>'product_id')::uuid,
  (x->>'line_id')::uuid,(x->>'original_movement_line_id')::uuid,q,amount,(x->>'lot_id')::uuid,
  array(select value::uuid from jsonb_array_elements_text(x->'serial_ids')),v_date,auth.uid());
  if amount<>0 then jlines:=jlines||jsonb_build_array(finance.flow_jline((x->>'inventory_account_id')::uuid,amount,amount,(x->>'line_id')::uuid),
  finance.flow_jline((d->>'offset_account_id')::uuid,-amount,-amount,(x->>'line_id')::uuid));end if;
 end loop;
 j:=finance.flow_post_journal(d||jsonb_build_object('base_currency_code',d->>'currency_code','exchange_rate','1'),jlines,'inventory_disposition',v_id,req,p_command_id);
 select jsonb_object_agg(b.product_id::text,jsonb_build_object('balance_version',b.version,'valuation_version',v.version,
 'on_hand_quantity',b.on_hand_quantity::text,'carrying_value',v.carrying_value::text)) into state
 from inventory.stock_balances b join inventory.stock_valuations v on v.stock_balance_id=b.id and v.tenant_id=b.tenant_id
 where b.tenant_id=p_tenant_id and b.warehouse_id=(d->>'warehouse_id')::uuid
 and b.product_id in(select (value->>'product_id')::uuid from jsonb_array_elements(d->'lines'));
 update inventory.stock_dispositions set status='posted',posted_at=clock_timestamp(),posted_by=auth.uid(),updated_by=auth.uid(),
 stock_movement_id=m,journal_entry_id=j,post_state=state,request_id=req,command_id=p_command_id,correlation_id=req,client_timestamp=p_client_timestamp
 where tenant_id=p_tenant_id and id=v_id;
 return core.wave3_finish_command(p_tenant_id,'inventory.stock_disposition.post',p_command_id,'inventory_disposition',v_id,p_idempotency_key,h,d,
 inventory.disposition_document('inventory_disposition',p_tenant_id,v_id),p_legal_entity_id,p_branch_id,'{}',
 jsonb_build_object('from_status','approved','to_status','posted','reason',d->>'reason'),
 jsonb_build_array(jsonb_build_object('topic','inventory.stock_disposition.post','payload',jsonb_build_object('id',v_id))),'[]',req,req);
end $$;


-- Preserve every existing movement kind; this additive kind describes the actual source.
do $$declare c text;begin
 select pg_get_constraintdef(oid) into c from pg_constraint where conrelid='inventory.stock_movements'::regclass
 and conname='stock_movements_movement_kind_check';
 if c is null then raise exception 'MOVEMENT_CONSTRAINT_DRIFT';end if;
 alter table inventory.stock_movements drop constraint stock_movements_movement_kind_check;
 execute 'alter table inventory.stock_movements add constraint stock_movements_movement_kind_check CHECK ('||substring(c from 7)||' OR movement_kind IN (''disposition'',''disposition_reversal''))';
end $$;
create unique index one_posted_disposition_reversal on inventory.stock_dispositions(tenant_id,reverses_disposition_id)
where status='posted' and reverses_disposition_id is not null;
-- A disposed serial remains disposed even if a future command attempts to receive/return it.
create function inventory.disposition_protect_serial() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then
  if old.status='disposed' then raise exception using errcode='55000',message='DISPOSED_SERIAL_IMMUTABLE';end if;
  return old;
 end if;
 if old.status='disposed' and (new.status<>'disposed' or new.warehouse_id<>old.warehouse_id or new.product_id<>old.product_id
 or new.tenant_id<>old.tenant_id or new.lot_id is distinct from old.lot_id) then
 raise exception using errcode='55000',message='DISPOSED_SERIAL_IMMUTABLE';end if;
 return new;
end $$;
create trigger disposition_serial_permanent before update or delete on inventory.serials
for each row execute function inventory.disposition_protect_serial();
revoke all on function inventory.disposition_protect_serial() from public,anon,authenticated;

-- Normalize under the same sorted locks used by delivery, transfers and valuation.
-- Exact cumulative allocation avoids a rounding leak when several selected lots share one pool.
create function inventory.disposition_normalize(p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb,p_old jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare wh uuid:=(p_payload->>'warehouse_id')::uuid; x jsonb; z jsonb; source jsonb; source_line jsonb;
 product inventory.products%rowtype; b inventory.stock_balances%rowtype; val inventory.stock_valuations%rowtype;
 lot inventory.lots%rowtype; lb inventory.lot_balances%rowtype; s inventory.serials%rowtype;
 resolved jsonb; q numeric; amount numeric; cumulative numeric; prior_amount numeric; total numeric:=0;
 lines jsonb:='[]'; serial_rows jsonb; serial_ids uuid[]; seen_serials uuid[]:='{}'; seen_lines uuid[]:='{}';
 seen_lots uuid[]:='{}'; line_id uuid; sid uuid; lid uuid; currency text; previous_product uuid;
 reversal uuid:=(p_payload->>'reverses_disposition_id')::uuid; correction uuid:=(p_payload->>'corrects_disposition_id')::uuid;
 serial_count integer:=0; original uuid; state jsonb;
begin
 if wh is null or not exists(select 1 from core.warehouses where tenant_id=p_tenant and legal_entity_id=p_entity
 and branch_id=p_branch and id=wh and status='active') or coalesce(length(trim(p_payload->>'reason')),0) not between 3 and 1000
 or p_payload->>'document_date' is null or (reversal is not null and correction is not null)
 then raise exception using errcode='22023',message='DISPOSITION_INPUT_INVALID';end if;
 if (p_payload->>'document_date')::date>(clock_timestamp() at time zone 'UTC')::date then
 raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 if p_old is not null and (p_old->>'warehouse_id' is distinct from p_payload->>'warehouse_id'
 or p_old->>'corrects_disposition_id' is distinct from p_payload->>'corrects_disposition_id'
 or p_old->>'reverses_disposition_id' is distinct from p_payload->>'reverses_disposition_id') then
 raise exception using errcode='22023',message='DISPOSITION_LINK_IMMUTABLE';end if;
 select currency_code into currency from core.legal_entities where tenant_id=p_tenant and id=p_entity;
 perform finance.flow_account(p_tenant,p_entity,(p_payload->>'offset_account_id')::uuid,'expense',currency);
 if coalesce(reversal,correction) is not null then
  perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||':disposition:'||coalesce(reversal,correction)::text,0));
  select sales.flow_exact_json(to_jsonb(d)) into source from inventory.stock_dispositions d
  where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and warehouse_id=wh
  and id=coalesce(reversal,correction) and status='posted' and reverses_disposition_id is null for share;
  if source is null or (p_payload->>'document_date')::date<(source->>'document_date')::date then
  raise exception using errcode='22023',message='DISPOSITION_CORRECTION_SOURCE_INVALID';end if;
 end if;
 if reversal is not null then
  if exists(select 1 from inventory.stock_dispositions where tenant_id=p_tenant and reverses_disposition_id=reversal and status='posted') then
  raise exception using errcode='55000',message='DISPOSITION_ALREADY_REVERSED';end if;
  if exists(select 1 from jsonb_array_elements(source->'lines') l where l->>'tracking_mode'='serial') then
  raise exception using errcode='55000',message='DISPOSITION_SERIAL_REVERSAL_DENIED';end if;
  if p_payload->'lines' is not null and p_old is null then raise exception using errcode='22023',message='DISPOSITION_REVERSAL_LINES_SERVER_OWNED';end if;
  if (p_payload->>'offset_account_id')::uuid<>(source->>'offset_account_id')::uuid then
  raise exception using errcode='22023',message='DISPOSITION_REVERSAL_ACCOUNT_IMMUTABLE';end if;
 end if;
 z:=case when reversal is not null then source->'lines' else p_payload->'lines' end;
 if jsonb_typeof(z) is distinct from 'array' or jsonb_array_length(z) not between 1 and 100 then
 raise exception using errcode='22023',message='DISPOSITION_LINES_INVALID';end if;
 for x in select value from jsonb_array_elements(z) order by value->>'product_id',value->>'line_id' loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||':'||wh::text||':'||(x->>'product_id'),0));
 end loop;
 for x in select value from jsonb_array_elements(z) order by value->>'product_id',value->>'line_id' loop
  line_id:=case when reversal is null then (x->>'line_id')::uuid else md5((p_payload->>'id')||':'||(x->>'line_id'))::uuid end;
  select * into product from inventory.products where tenant_id=p_tenant and legal_entity_id=p_entity
  and id=(x->>'product_id')::uuid and kind='stocked' and status='active' for share;
  if not found or line_id is null or line_id=any(seen_lines) then raise exception using errcode='22023',message='DISPOSITION_PRODUCT_INVALID';end if;
  seen_lines:=array_append(seen_lines,line_id);
  if previous_product is distinct from product.id then cumulative:=0;prior_amount:=0;end if;
  previous_product:=product.id;
  select * into b from inventory.stock_balances where tenant_id=p_tenant and warehouse_id=wh and product_id=product.id for update;
  select * into val from inventory.stock_valuations where tenant_id=p_tenant and stock_balance_id=b.id for update;
  if b.id is null or val.id is null then raise exception using errcode='55000',message='DISPOSITION_BALANCE_REQUIRED';end if;
  if exists(select 1 from inventory.stock_movement_lines where tenant_id=p_tenant and warehouse_id=wh
  and product_id=product.id and posting_date>(p_payload->>'document_date')::date) then
  raise exception using errcode='55000',message='BACKDATED_DISPOSITION_REQUIRES_REVIEW';end if;
  perform finance.flow_account(p_tenant,p_entity,product.inventory_account_id,'asset',currency);
  original:=null;
  if reversal is null then
   resolved:=inventory.resolve_product_unit(p_tenant,p_entity,product.id,(x->>'unit_id')::uuid,x->'quantity',x->'conversion_numerator',x->'conversion_denominator');
   q:=(resolved->>'base_quantity')::numeric;
   cumulative:=cumulative+q;
   if b.available_quantity<cumulative then raise exception using errcode='55000',message='DISPOSITION_STOCK_UNAVAILABLE';end if;
   amount:=case when cumulative=b.on_hand_quantity then val.carrying_value else round(val.carrying_value*cumulative/nullif(b.on_hand_quantity,0),6) end-prior_amount;
   prior_amount:=prior_amount+amount;
  else
   q:=(x->>'base_quantity')::numeric;amount:=(x->>'carrying_value')::numeric;
   state:=source->'post_state'->product.id::text;
   if state is null or b.version<>(state->>'balance_version')::bigint or val.version<>(state->>'valuation_version')::bigint
   or b.on_hand_quantity<>(state->>'on_hand_quantity')::numeric or val.carrying_value<>(state->>'carrying_value')::numeric then
   raise exception using errcode='55000',message='DISPOSITION_LATER_HISTORY';end if;
   select ml.id into original from inventory.stock_movement_lines ml where tenant_id=p_tenant
   and stock_movement_id=(source->>'stock_movement_id')::uuid and source_line_id=(x->>'line_id')::uuid;
   if original is null then raise exception using errcode='55000',message='DISPOSITION_SOURCE_MOVEMENT_MISSING';end if;
   resolved:=x;
  end if;
  lid:=(x->>'lot_id')::uuid;serial_rows:='[]';serial_ids:='{}';lot:=null;lb:=null;
  if product.tracking_mode='none' and (lid is not null or coalesce(jsonb_array_length(x->'serial_ids'),0)>0) then
  raise exception using errcode='22023',message='DISPOSITION_TRACKING_INVALID';end if;
  if lid is not null then
   select * into lot from inventory.lots where tenant_id=p_tenant and legal_entity_id=p_entity and product_id=product.id and id=lid for update;
   select * into lb from inventory.lot_balances where tenant_id=p_tenant and warehouse_id=wh and product_id=product.id and lot_id=lid for update;
   if lot.id is null or lb.id is null or lot.status='disposed' or (reversal is null and lb.on_hand_quantity<q) or lid=any(seen_lots) then
   raise exception using errcode='55000',message='DISPOSITION_LOT_UNAVAILABLE';end if;
   -- Expiry is deliberately accepted here; saleable deliveries retain their expiry guard.
   seen_lots:=array_append(seen_lots,lid);
  elsif product.tracking_mode='lot' then raise exception using errcode='22023',message='DISPOSITION_TRACKING_INVALID';end if;
  if product.tracking_mode='serial' then
   if jsonb_typeof(x->'serial_ids') is distinct from 'array' or jsonb_array_length(x->'serial_ids')<>q or q<>trunc(q) then
   raise exception using errcode='22023',message='DISPOSITION_SERIAL_QUANTITY_INVALID';end if;
   for sid in select value::text::uuid from jsonb_array_elements_text(x->'serial_ids') order by value loop
    serial_count:=serial_count+1;
    if sid=any(seen_serials) or serial_count>500 then raise exception using errcode='22023',message='DISPOSITION_SERIAL_DUPLICATE_OR_LIMIT';end if;
    select * into s from inventory.serials where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch
    and warehouse_id=wh and product_id=product.id and id=sid and status in('available','quarantine') for update;
    if not found or s.lot_id is distinct from lid then raise exception using errcode='55000',message='DISPOSITION_SERIAL_UNAVAILABLE';end if;
    seen_serials:=array_append(seen_serials,sid);serial_ids:=array_append(serial_ids,sid);
    serial_rows:=serial_rows||jsonb_build_array(jsonb_build_object('id',sid,'version',s.version,'status',s.status));
   end loop;
  elsif coalesce(jsonb_array_length(x->'serial_ids'),0)<>0 then raise exception using errcode='22023',message='DISPOSITION_TRACKING_INVALID';end if;
  total:=total+amount;
  lines:=lines||jsonb_build_array(resolved||jsonb_build_object('line_id',line_id,'product_id',product.id,'product_name',product.name,
   'unit_id',coalesce(x->>'unit_id',product.base_unit_id::text),'quantity',coalesce(x->>'quantity',q::text),
   'conversion_numerator',coalesce(x->>'conversion_numerator','1'),'conversion_denominator',coalesce(x->>'conversion_denominator','1'),
   'base_quantity',q::text,'carrying_value',amount::text,'tracking_mode',product.tracking_mode,'inventory_account_id',product.inventory_account_id,
   'lot_id',lid,'lot_version',lot.version,'lot_balance_version',lb.version,'serial_ids',to_jsonb(serial_ids),'serial_snapshot',serial_rows,
   'baseline_version',b.version,'valuation_version',val.version,'original_movement_line_id',original));
 end loop;
 return jsonb_build_object('warehouse_id',wh,'document_date',p_payload->>'document_date','reason',trim(p_payload->>'reason'),
 'currency_code',currency,'offset_account_id',p_payload->>'offset_account_id','cutoff_at',coalesce(p_old->>'cutoff_at',clock_timestamp()::text),
 'lines',sales.flow_exact_json(lines),'grand_total',total::text);
end $$;

create function inventory.disposition_revalidate(p_kind text,p_doc jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;begin
 if p_kind<>'inventory_disposition' then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 d:=inventory.disposition_normalize((p_doc->>'tenant_id')::uuid,(p_doc->>'legal_entity_id')::uuid,(p_doc->>'branch_id')::uuid,p_doc,p_doc);
 if d->'lines'<>p_doc->'lines' or d->>'currency_code'<>p_doc->>'currency_code' then
 raise exception using errcode='55000',message='DISPOSITION_REAPPROVAL_REQUIRED';end if;
 return d;
end $$;

create function api.upsert_stock_disposition(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare id uuid:=(p_payload->>'id')::uuid;req uuid:=gen_random_uuid();h text;result jsonb;old_doc jsonb;d jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.dispositions.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null or id is null then raise exception using errcode='22023',message='DISPOSITION_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.stock_disposition.upsert',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'inventory.stock_disposition.upsert',p_command_id,p_idempotency_key,h);if result is not null then return result;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':count:'||id::text,0));
 old_doc:=inventory.disposition_document('inventory_disposition',p_tenant_id,id,true);
 if old_doc is not null then
  if old_doc->>'legal_entity_id'<>p_legal_entity_id::text or old_doc->>'branch_id'<>p_branch_id::text then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
  perform core.wave3_assert_expected_version((old_doc->>'version')::bigint,p_expected_entity_version,old_doc);
  if old_doc->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 d:=inventory.disposition_normalize(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,old_doc);
 insert into inventory.stock_dispositions(id,tenant_id,legal_entity_id,branch_id,warehouse_id,cutoff_at,document_date,reason,currency_code,offset_account_id,lines,grand_total,corrects_disposition_id,reverses_disposition_id,
 request_id,command_id,correlation_id,client_timestamp,prepared_by,created_by,updated_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(d->>'warehouse_id')::uuid,(d->>'cutoff_at')::timestamptz,(d->>'document_date')::date,d->>'reason',d->>'currency_code',
 (d->>'offset_account_id')::uuid,d->'lines',(d->>'grand_total')::numeric,(p_payload->>'corrects_disposition_id')::uuid,(p_payload->>'reverses_disposition_id')::uuid,req,p_command_id,req,p_client_timestamp,auth.uid(),auth.uid(),auth.uid())
 on conflict on constraint stock_dispositions_pkey do update set document_date=excluded.document_date,reason=excluded.reason,offset_account_id=excluded.offset_account_id,
 lines=excluded.lines,grand_total=excluded.grand_total,prepared_by=auth.uid(),updated_by=auth.uid(),request_id=req,command_id=p_command_id,correlation_id=req,client_timestamp=p_client_timestamp
 where inventory.stock_dispositions.tenant_id=excluded.tenant_id and inventory.stock_dispositions.legal_entity_id=excluded.legal_entity_id and inventory.stock_dispositions.branch_id=excluded.branch_id;
 if not found then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 return core.wave3_finish_command(p_tenant_id,'inventory.stock_disposition.upsert',p_command_id,'inventory_disposition',id,p_idempotency_key,h,old_doc,
 inventory.disposition_document('inventory_disposition',p_tenant_id,id),p_legal_entity_id,p_branch_id,'{}',null,'[]','[]',req,req);
end $$;
revoke all on inventory.stock_dispositions from public,anon,authenticated;
grant select on inventory.stock_dispositions to authenticated;
create view api.stock_dispositions with(security_invoker=true) as
 select id,tenant_id,legal_entity_id,branch_id,warehouse_id,document_number,document_date,status,version,
 sales.flow_exact_json(to_jsonb(o)) as detail from inventory.stock_dispositions o;
revoke all on api.stock_dispositions from public,anon,authenticated;
grant select on api.stock_dispositions to authenticated;

create function inventory.disposition_document(p_kind text,p_tenant uuid,p_id uuid,p_lock boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d inventory.stock_dispositions%rowtype; begin
 if p_kind is distinct from 'inventory_disposition' then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 if p_lock then select * into d from inventory.stock_dispositions where tenant_id=p_tenant and id=p_id for update;
 else select * into d from inventory.stock_dispositions where tenant_id=p_tenant and id=p_id;end if;
 if not found then return null;end if;
 return sales.flow_exact_json(to_jsonb(d))||jsonb_build_object('warehouse_name',(select name from core.warehouses where id=d.warehouse_id),
  'offset_account_name',(select name from finance.accounts where id=d.offset_account_id));
end $$;


create function api.transition_stock_disposition(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_kind text:='inventory_disposition';v_id uuid:=(p_payload->>'document_id')::uuid;
 v_action text:=p_payload->>'action';v_decision text:=p_payload->>'decision';v_command text;
 v_doc jsonb;v_before jsonb;v_hash text;v_replay jsonb;v_to text;v_snapshot jsonb;
 v_workflow workflow.workflow_definitions%rowtype;v_request uuid:=gen_random_uuid();v_first integer;
 v_ar workflow.approval_requests%rowtype;v_step jsonb;v_number text;
begin
 v_command:='inventory.'||v_kind||case when v_decision is null then '.transition' else '.decide' end;
 perform core.wave3_require_scope(p_tenant_id,case when v_decision is null then 'inventory.dispositions.post' else 'workflow.approvals.decide' end,p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null
 or (p_payload ? 'document_type' and p_payload->>'document_type' is distinct from 'inventory_disposition')
 or (v_decision is not null and v_action is not null) then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=inventory.disposition_document(v_kind,p_tenant_id,v_id,true);v_before:=v_doc;
 if v_doc is null or (v_doc->>'legal_entity_id')::uuid<>p_legal_entity_id or (v_doc->>'branch_id')::uuid<>p_branch_id then
 raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((v_doc->>'version')::bigint,p_expected_entity_version,v_doc);
 if v_doc->>'status'='posted' then raise exception using errcode='55000',message='POSTED_DOCUMENT_IMMUTABLE';end if;
 v_snapshot:=v_doc->'workflow_snapshot';v_number:=v_doc->>'document_number';
 if v_decision is not null then
 if v_decision not in ('approved','rejected') or v_doc->>'status'<>'pending_approval' then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING';end if;
 select * into v_ar from workflow.approval_requests where tenant_id=p_tenant_id and document_type=v_kind and document_id=v_id and status='submitted' for update;
 if not found then raise exception using errcode='55000',message='APPROVAL_REQUEST_NOT_FOUND';end if;
 if v_ar.submitted_by=auth.uid() or (v_doc->>'created_by')::uuid=auth.uid() or (v_doc->>'prepared_by')::uuid=auth.uid() then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 select x into v_step from jsonb_array_elements(v_snapshot->'steps') x where (x->>'step_order')::integer=v_ar.current_step;
 if v_step is null or not exists(select 1 from core.memberships m join core.role_assignments ra on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
 join core.roles r on r.id=ra.role_id and r.tenant_id=m.tenant_id
 where m.tenant_id=p_tenant_id and m.user_id=auth.uid() and m.status='active' and ra.role_id=(v_step->>'role_id')::uuid
 and (ra.legal_entity_id is null or ra.legal_entity_id=p_legal_entity_id) and (ra.branch_id is null or ra.branch_id=p_branch_id)
 and (not r.requires_mfa or auth.jwt()->>'aal'='aal2')) then raise exception using errcode='42501',message='APPROVAL_ROLE_REQUIRED';end if;
 if v_decision='rejected' and nullif(trim(p_payload->>'note'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
 perform sales.flow_assert_transition(v_snapshot->'lifecycle','submitted',v_decision);
 insert into workflow.approval_decisions(tenant_id,approval_request_id,workflow_definition_id,workflow_revision,
 approval_matrix_step_id,step_order,actor_id,decision,note,amount,currency_code,request_id,command_id,correlation_id)
 values(p_tenant_id,v_ar.id,v_ar.workflow_definition_id,v_ar.workflow_revision,(v_step->>'id')::uuid,v_ar.current_step,
 auth.uid(),v_decision,p_payload->>'note',v_ar.amount,v_ar.currency_code,v_request,p_command_id,v_request);
 if v_decision='approved' then select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x
 where (x->>'step_order')::integer>v_ar.current_step;end if;
 v_to:=case when v_decision='rejected' then 'rejected' when v_first is null then 'approved' else 'pending_approval' end;
 if v_first is null then update workflow.approval_requests set status=v_to,decision_by=auth.uid(),decision_note=p_payload->>'note',decided_at=clock_timestamp() where id=v_ar.id;
 else update workflow.approval_requests set current_step=v_first where id=v_ar.id;end if;
 elsif v_action='submit' then
 if v_doc->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 perform inventory.disposition_revalidate(v_kind,v_doc);
 select * into v_workflow from workflow.workflow_definitions where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 if not found then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
 select jsonb_build_object('definition_id',v_workflow.id,'revision',v_workflow.revision,'lifecycle',v_workflow.lifecycle,
 'steps',coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(s)) order by s.step_order),'[]'::jsonb)) into v_snapshot
 from workflow.approval_matrix_steps s where s.tenant_id=p_tenant_id and s.workflow_definition_id=v_workflow.id and s.status='active'
 and (s.currency_code is null or s.currency_code=v_doc->>'currency_code')
 and (s.minimum_amount is null or (v_doc->>'grand_total')::numeric>=s.minimum_amount)
 and (s.maximum_amount is null or (v_doc->>'grand_total')::numeric<=s.maximum_amount);
 if v_workflow.lifecycle->'requires_approval' is distinct from 'true'::jsonb then
 raise exception using errcode='55000',message='DISPOSITION_APPROVAL_REQUIRED';end if;
 select min((x->>'step_order')::integer) into v_first from jsonb_array_elements(v_snapshot->'steps') x;
 if v_first is null then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
 v_to:='pending_approval';
 perform sales.flow_assert_transition(v_workflow.lifecycle,'draft','submitted');
 v_number:=coalesce(v_number,sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,v_kind,(v_doc->>'document_date')::date,auth.uid()));
 if v_first is not null then insert into workflow.approval_requests(tenant_id,legal_entity_id,branch_id,document_type,document_id,status,
 submitted_by,workflow_definition_id,workflow_revision,current_step,amount,currency_code,command_id,request_id,correlation_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,v_kind,v_id,'submitted',auth.uid(),v_workflow.id,v_workflow.revision,v_first,
 (v_doc->>'grand_total')::numeric,v_doc->>'currency_code',p_command_id,v_request,v_request);end if;
 elsif v_action in ('recall','cancel') then
 if nullif(trim(p_payload->>'reason'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;
 if (v_snapshot is null or v_snapshot='null'::jsonb) and v_doc->>'status'='draft' then
 select jsonb_build_object('lifecycle',lifecycle) into v_snapshot from workflow.workflow_definitions
 where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 end if;
 v_to:=case when v_action='recall' then 'draft' else 'cancelled' end;
 perform sales.flow_assert_transition(v_snapshot->'lifecycle',v_doc->>'status',v_to);
 update workflow.approval_requests set status='cancelled',decision_by=auth.uid(),decision_note=p_payload->>'reason',decided_at=clock_timestamp()
 where tenant_id=p_tenant_id and document_type=v_kind and document_id=v_id and status='submitted';
 if v_action='recall' then v_snapshot:=null;end if;
 else raise exception using errcode='22023',message='DOCUMENT_ACTION_INVALID';end if;
 execute format('update inventory.%I set status=$1,workflow_snapshot=$2,document_number=$3,submitted_by=case when $4=''submit'' then $5 else submitted_by end,updated_by=$5,request_id=$6,command_id=$7,correlation_id=$6,client_timestamp=$8 where tenant_id=$9 and id=$10','stock_dispositions')
 using v_to,v_snapshot,v_number,v_action,auth.uid(),v_request,p_command_id,p_client_timestamp,p_tenant_id,v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_kind,v_id,p_idempotency_key,v_hash,v_before,
 inventory.disposition_document(v_kind,p_tenant_id,v_id),p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 case when v_doc->>'status'=v_to then null else
 jsonb_build_object('from_status',v_doc->>'status','to_status',v_to,'reason',coalesce(p_payload->>'reason',p_payload->>'note')) end,
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status',v_to))),'[]',v_request,v_request);
end $$;




create function api.stock_dispositions_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if not core.has_permission(p_tenant_id,'inventory.dispositions.post',p_legal_entity_id,p_branch_id) and not core.has_permission(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'document_number',q.document_number,'document_date',q.document_date,'status',q.status,
  'version',q.version,'currency_code',q.currency_code,'grand_total',q.grand_total::text,'warehouse_name',(select name from core.warehouses where id=q.warehouse_id)) order by q.id),'[]') into rows
 from (select * from inventory.stock_dispositions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and (p_after is null or id>p_after) order by id limit 51)q;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'items',rows,'next_cursor',next_id);
end $$;
create function api.stock_disposition_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d jsonb;begin
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if not core.has_permission(p_tenant_id,'inventory.dispositions.post',p_legal_entity_id,p_branch_id) and not core.has_permission(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 d:=inventory.disposition_document('inventory_disposition',p_tenant_id,p_id);
 if d is null or d->>'legal_entity_id' is distinct from p_legal_entity_id::text or d->>'branch_id' is distinct from p_branch_id::text then raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 return d;
end $$;
revoke all on function api.stock_disposition_detail(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.stock_disposition_detail(uuid,uuid,uuid,uuid) to authenticated;

-- Bounded picker. A product is mandatory for lot/serial identities; expired held lots are visible.
create function api.stock_disposition_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,
 p_warehouse_id uuid default null,p_product_id uuid default null,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.dispositions.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 if p_resource in('products','lots','serials') and not exists(select 1 from core.warehouses where tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_warehouse_id and status='active') then
 raise exception using errcode='42501',message='DISPOSITION_WAREHOUSE_SCOPE_REQUIRED';end if;
 if p_resource in('lots','serials') and not exists(select 1 from inventory.products where tenant_id=p_tenant_id
 and legal_entity_id=p_legal_entity_id and id=p_product_id and status='active' and kind='stocked') then
 raise exception using errcode='22023',message='DISPOSITION_PRODUCT_REQUIRED';end if;
 if p_resource='warehouses' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from(select id,name,code from core.warehouses
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='active'
  and(p_after is null or id>p_after) order by id limit 51)q;
 elsif p_resource='products' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from(select p.id,p.name,p.sku,p.base_unit_id,
  p.tracking_mode,b.available_quantity::text available_quantity from inventory.products p join inventory.stock_balances b
  on b.product_id=p.id and b.tenant_id=p.tenant_id and b.warehouse_id=p_warehouse_id
  where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.kind='stocked' and p.status='active'
  and b.available_quantity>0 and(p_after is null or p.id>p_after) order by p.id limit 51)q;
 elsif p_resource='lots' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from(select l.id,l.code,l.expiry_date,l.status,
  b.on_hand_quantity::text held_quantity,l.version,b.version balance_version from inventory.lots l join inventory.lot_balances b
  on b.tenant_id=l.tenant_id and b.lot_id=l.id and b.warehouse_id=p_warehouse_id
  where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and l.product_id=p_product_id
  and l.status in('saleable','quarantine') and b.on_hand_quantity>0 and(p_after is null or l.id>p_after) order by l.id limit 51)q;
 elsif p_resource='serials' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from(select id,code,lot_id,status,version from inventory.serials
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and warehouse_id=p_warehouse_id
  and product_id=p_product_id and status in('available','quarantine') and(p_after is null or id>p_after) order by id limit 51)q;
 elsif p_resource='accounts' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from(select id,name,code from finance.accounts
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and account_type='expense' and is_posting and status='active'
  and (currency_code is null or currency_code=(select currency_code from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id))
  and(p_after is null or id>p_after) order by id limit 51)q;
 else raise exception using errcode='22023',message='RESOURCE_INVALID';end if;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'resource',p_resource,'items',rows,'next_cursor',next_id);
end $$;

revoke all on function inventory.disposition_document(text,uuid,uuid,boolean),
 inventory.disposition_normalize(uuid,uuid,uuid,jsonb,jsonb),inventory.disposition_revalidate(text,jsonb)
from public,anon,authenticated;
revoke all on function api.stock_dispositions_page(uuid,uuid,uuid,uuid),
 api.stock_disposition_options(uuid,uuid,uuid,text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.stock_dispositions_page(uuid,uuid,uuid,uuid),
 api.stock_disposition_options(uuid,uuid,uuid,text,uuid,uuid,uuid) to authenticated;
do $$declare f text;begin
 foreach f in array array['upsert_stock_disposition','transition_stock_disposition','post_stock_disposition'] loop
  execute format('revoke all on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated',f);
  execute format('grant execute on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated',f);
 end loop;
end $$;
notify pgrst,'reload schema';
