-- Stock-count candidate. Independent aggregate; reuses installed governance and ledger primitives.
create table inventory.stock_counts (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references core.tenants(id),
 legal_entity_id uuid not null, branch_id uuid not null, warehouse_id uuid not null,
 document_type text not null default 'stock_count' check(document_type='stock_count'), corrects_count_id uuid,
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
 foreign key(tenant_id,corrects_count_id) references inventory.stock_counts(tenant_id,id),
 check((status='posted')=(posted_at is not null)),
 check(status<>'posted' or posted_by is not null)
);
alter table inventory.stock_counts enable row level security;
alter table inventory.stock_counts force row level security;
create policy count_permitted_read on inventory.stock_counts for select to authenticated using (
 core.is_tenant_member(tenant_id) and core.has_permission(tenant_id,'inventory.cost.view',legal_entity_id,branch_id)
 and (core.has_permission(tenant_id,'inventory.adjustments.post',legal_entity_id,branch_id)
 or core.has_permission(tenant_id,'workflow.approvals.decide',legal_entity_id,branch_id))
);
create trigger count_immutable_posted before update or delete on inventory.stock_counts
 for each row execute function sales.flow_protect_document();
create trigger count_touch before update on inventory.stock_counts
 for each row execute function core.touch_mutable_record();
create index stock_counts_scope_idx on inventory.stock_counts(tenant_id,legal_entity_id,branch_id,status,id);
-- Lead each FK index with its referencing columns; retain the scoped register index.
do $$ declare f record; begin
 for f in select c.conname, (select string_agg(quote_ident(a.attname),',' order by k.n)
 from unnest(c.conkey) with ordinality k(num,n) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) cols
 from pg_constraint c where c.conrelid='inventory.stock_counts'::regclass and c.contype='f' loop
 execute format('create index %I on inventory.stock_counts(%s)',f.conname||'_idx',f.cols);
 end loop;
end $$;

-- Candidate extension: a count loss never impersonates a delivery or destroys identity.
alter table inventory.serials add column count_previous_status text check(count_previous_status in ('available','quarantine'));
alter table inventory.serials drop constraint serials_status_check;
alter table inventory.serials add constraint serials_status_check check(status in ('available','issued','quarantine','disposed','in_transit','count_missing'));
alter table inventory.serials add constraint serial_count_disposition check((status='count_missing')=(count_previous_status is not null));

create function inventory.count_identities(p_tenant uuid,p_warehouse uuid,p_product uuid,p_mode text,p_input jsonb,p_old jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb; r jsonb; supplied jsonb; result jsonb:='[]'; q numeric; delta numeric; s inventory.serials%rowtype; lb inventory.lot_balances%rowtype;
begin
 if p_old is null then
  if p_mode='lot' then
   select coalesce(jsonb_agg(jsonb_build_object('id',x.lot_id,'code',x.code,'baseline_quantity',x.on_hand_quantity::text,
    'counted_quantity',x.on_hand_quantity::text,'baseline_version',x.version,'disposition',x.status) order by x.lot_id),'[]') into rows
   from (select b.*,l.code,l.status from inventory.lot_balances b join inventory.lots l on l.id=b.lot_id
    where b.tenant_id=p_tenant and b.warehouse_id=p_warehouse and b.product_id=p_product order by b.lot_id limit 501 for update of b,l)x;
  else
   select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'code',x.code,'baseline_quantity',case when x.status='count_missing' then '0' else '1' end,
    'counted_quantity',case when x.status='count_missing' then '0' else '1' end,'baseline_version',x.version,'disposition',x.status,
    'restore_status',coalesce(x.count_previous_status,x.status),'lot_id',x.lot_id) order by x.id),'[]') into rows
   from (select * from inventory.serials where tenant_id=p_tenant and warehouse_id=p_warehouse and product_id=p_product
    and status in ('available','quarantine','count_missing') order by id limit 501 for update)x;
  end if;
  if jsonb_array_length(rows)>500 then raise exception using errcode='22023',message='COUNT_IDENTITY_LIMIT';end if;
 else
  rows:=p_old;
  if jsonb_typeof(p_input) is distinct from 'array' or jsonb_array_length(p_input)<>jsonb_array_length(rows)
   or (select count(distinct value->>'id') from jsonb_array_elements(p_input))<>jsonb_array_length(rows) then
   raise exception using errcode='22023',message='COUNT_IDENTITIES_IMMUTABLE';end if;
 end if;
 for r in select value from jsonb_array_elements(rows) order by value->>'id' loop
  supplied:=r;
  if p_old is not null then
   select value into supplied from jsonb_array_elements(p_input) where value->>'id'=r->>'id';
   if supplied is null then raise exception using errcode='22023',message='COUNT_IDENTITIES_IMMUTABLE';end if;
  end if;
  q:=sales.wave3_decimal_string(supplied->'counted_quantity','identity_counted_quantity',6,true,0,null);
  delta:=q-(r->>'baseline_quantity')::numeric;
  if p_mode='serial' then
   if q not in(0,1) then raise exception using errcode='22023',message='COUNT_SERIAL_PRESENCE_REQUIRED';end if;
   select * into s from inventory.serials where tenant_id=p_tenant and warehouse_id=p_warehouse and product_id=p_product and id=(r->>'id')::uuid for update;
   if not found or s.version<>(r->>'baseline_version')::bigint or s.status<>r->>'disposition' then
    raise exception using errcode='55000',message='COUNT_SERIAL_CHANGED';end if;
  else
   select * into lb from inventory.lot_balances where tenant_id=p_tenant and warehouse_id=p_warehouse and product_id=p_product and lot_id=(r->>'id')::uuid for update;
   if not found or lb.on_hand_quantity+delta<0 then raise exception using errcode='55000',message='COUNT_LOT_UNAVAILABLE';end if;
  end if;
  result:=result||jsonb_build_array(r||jsonb_build_object('counted_quantity',q::text,'variance_quantity',delta::text));
 end loop;
 return result;
end $$;
revoke all on function inventory.count_identities(uuid,uuid,uuid,text,jsonb,jsonb) from public,anon,authenticated;

create function inventory.count_normalize(p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb,p_old jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare wh uuid:=(p_payload->>'warehouse_id')::uuid; x jsonb; old_line jsonb; product inventory.products%rowtype;
 b inventory.stock_balances%rowtype; val inventory.stock_valuations%rowtype; q numeric; baseline numeric; delta numeric; amount numeric;
 unit_cost numeric; total numeric:=0; lines jsonb:='[]'; seen uuid[]:='{}'; seen_lines uuid[]:='{}'; line_id uuid; currency text; cutoff timestamptz;
 identities jsonb; identity_row jsonb; allocated jsonb; cumulative numeric; prior_amount numeric; next_amount numeric; identity_value numeric; identity_count integer:=0;
begin
 if wh is null or not exists(select 1 from core.warehouses where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=wh and status='active')
 or coalesce(length(trim(p_payload->>'reason')),0) not between 3 and 1000
 or jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines') not between 1 and 100
 or p_payload->>'document_date' is null then raise exception using errcode='22023',message='COUNT_INPUT_INVALID';end if;
 select currency_code into currency from core.legal_entities where tenant_id=p_tenant and id=p_entity;
 perform finance.flow_account(p_tenant,p_entity,(p_payload->>'offset_account_id')::uuid,'expense',currency);
 if p_payload->>'corrects_count_id' is not null and not exists(select 1 from inventory.stock_counts c where c.tenant_id=p_tenant and c.legal_entity_id=p_entity
  and c.branch_id=p_branch and c.warehouse_id=wh and c.id=(p_payload->>'corrects_count_id')::uuid and c.status='posted') then
  raise exception using errcode='22023',message='COUNT_CORRECTION_SOURCE_INVALID';end if;
 if p_old is not null and p_old->>'corrects_count_id' is distinct from p_payload->>'corrects_count_id' then raise exception using errcode='22023',message='COUNT_BASELINE_IMMUTABLE';end if;
 if p_old is not null and ((p_old->>'warehouse_id')::uuid<>wh or jsonb_array_length(p_old->'lines')<>jsonb_array_length(p_payload->'lines')) then
  raise exception using errcode='22023',message='COUNT_BASELINE_IMMUTABLE';end if;
 for x in select value from jsonb_array_elements(p_payload->'lines') order by value->>'product_id' loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant::text||':'||wh::text||':'||(x->>'product_id'),0));
 end loop;
 cutoff:=coalesce((p_old->>'cutoff_at')::timestamptz,clock_timestamp());
 if (p_payload->>'document_date')::date<(cutoff at time zone 'UTC')::date then raise exception using errcode='22023',message='COUNT_DATE_BEFORE_CUTOFF';end if;
 for x in select value from jsonb_array_elements(p_payload->'lines') order by value->>'product_id' loop
  line_id:=(x->>'line_id')::uuid;
  select * into product from inventory.products where tenant_id=p_tenant and legal_entity_id=p_entity and id=(x->>'product_id')::uuid and kind='stocked' and status='active' for share;
  if not found or line_id is null or product.id=any(seen) or line_id=any(seen_lines) then raise exception using errcode='22023',message='COUNT_PRODUCT_INVALID';end if;
  seen:=array_append(seen,product.id);seen_lines:=array_append(seen_lines,line_id);
  q:=sales.wave3_decimal_string(x->'counted_quantity','counted_quantity',6,true,0,null);
  if not exists(select 1 from inventory.units where tenant_id=p_tenant and id=product.base_unit_id and status='active' and round(q,precision)=q) then
   raise exception using errcode='22023',message='COUNT_UNIT_PRECISION_INVALID';end if;
  select * into b from inventory.stock_balances where tenant_id=p_tenant and warehouse_id=wh and product_id=product.id for update;
  select * into val from inventory.stock_valuations where tenant_id=p_tenant and stock_balance_id=b.id for update;
  if b.id is null or val.id is null then raise exception using errcode='55000',message='COUNT_BALANCE_REQUIRED';end if;
  old_line:=null;
  if p_old is not null then
   select value into old_line from jsonb_array_elements(p_old->'lines') where value->>'line_id'=line_id::text and value->>'product_id'=product.id::text;
   if old_line is null or old_line->>'base_unit_id'<>product.base_unit_id::text then raise exception using errcode='22023',message='COUNT_BASELINE_IMMUTABLE';end if;
  end if;
  baseline:=coalesce((old_line->>'baseline_quantity')::numeric,b.on_hand_quantity);
  identities:=null;
  if product.tracking_mode<>'none' then
   if old_line is null and p_payload->'capture_only' is distinct from 'true'::jsonb then raise exception using errcode='22023',message='COUNT_TRACKED_CAPTURE_REQUIRED';end if;
   if old_line is not null and old_line->>'tracking_mode' is distinct from product.tracking_mode then raise exception using errcode='22023',message='COUNT_BASELINE_IMMUTABLE';end if;
   identities:=inventory.count_identities(p_tenant,wh,product.id,product.tracking_mode,x->'identities',old_line->'identities');
   identity_count:=identity_count+jsonb_array_length(identities);
   if identity_count>500 then raise exception using errcode='22023',message='COUNT_IDENTITY_LIMIT';end if;
   if old_line is null and coalesce((select sum((value->>'baseline_quantity')::numeric) from jsonb_array_elements(identities)),0)<>baseline then
    raise exception using errcode='55000',message='COUNT_TRACKING_BALANCE_MISMATCH';end if;
   select coalesce(sum((value->>'counted_quantity')::numeric),0) into q from jsonb_array_elements(identities);
   if exists(select 1 from jsonb_array_elements(identities) z,inventory.units u where u.id=product.base_unit_id and round((z->>'counted_quantity')::numeric,u.precision)<>(z->>'counted_quantity')::numeric) then
    raise exception using errcode='22023',message='COUNT_UNIT_PRECISION_INVALID';end if;
  elsif old_line is not null and old_line->>'tracking_mode' not in ('none') then raise exception using errcode='22023',message='COUNT_BASELINE_IMMUTABLE';end if;
  if p_old is null and p_payload->'capture_only'='true'::jsonb then q:=baseline;end if;
  delta:=q-baseline;
  unit_cost:=sales.wave3_decimal_string(coalesce(x->'empty_unit_cost','"0"'::jsonb),'empty_unit_cost',6,true,0,null);
  if delta>0 and b.on_hand_quantity=0 and (x->>'empty_unit_cost' is null or trim(x->>'empty_unit_cost')='') then
   raise exception using errcode='22023',message='COUNT_EMPTY_STOCK_COST_REQUIRED';end if;
  if b.available_quantity+delta<0 then raise exception using errcode='55000',message='COUNT_RESERVED_STOCK_UNAVAILABLE';end if;
  amount:=case when delta=0 then 0 when b.on_hand_quantity=0 then round(delta*unit_cost,6)
   when delta=-b.on_hand_quantity then -val.carrying_value else round(val.carrying_value*delta/b.on_hand_quantity,6) end;
  perform finance.flow_account(p_tenant,p_entity,product.inventory_account_id,'asset',currency);
  if identities is null then total:=total+abs(amount);
  else
   cumulative:=0;prior_amount:=0;allocated:='[]';
   for identity_row in select value from jsonb_array_elements(identities) order by (value->>'variance_quantity')::numeric desc,value->>'id' loop
    cumulative:=cumulative+(identity_row->>'variance_quantity')::numeric;
    next_amount:=case when cumulative=delta then amount when b.on_hand_quantity=0 then round(cumulative*unit_cost,6) else round(val.carrying_value*cumulative/b.on_hand_quantity,6) end;
    identity_value:=next_amount-prior_amount;prior_amount:=next_amount;
    allocated:=allocated||jsonb_build_array(identity_row||jsonb_build_object('variance_value',identity_value::text));
    total:=total+abs(identity_value);
   end loop;
   select coalesce(jsonb_agg(z order by z->>'id'),'[]') into identities from jsonb_array_elements(allocated)z;
  end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('line_id',line_id,'product_id',product.id,'product_name',product.name,'base_unit_id',product.base_unit_id,
   'baseline_quantity',baseline::text,'baseline_version',coalesce(old_line->'baseline_version',to_jsonb(b.version)),
   'counted_quantity',q::text,'variance_quantity',delta::text,'variance_value',amount::text,'empty_unit_cost',unit_cost::text,'inventory_account_id',product.inventory_account_id)
   ||case when identities is null then '{}'::jsonb else jsonb_build_object('tracking_mode',product.tracking_mode,'identities',identities) end);
 end loop;
 return jsonb_build_object('warehouse_id',wh,'document_date',p_payload->>'document_date','reason',trim(p_payload->>'reason'),
  'currency_code',currency,'offset_account_id',p_payload->>'offset_account_id','cutoff_at',cutoff,'lines',lines,'grand_total',total::text);
end $$;

create function inventory.count_revalidate(p_kind text,p_doc jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;begin
 if p_kind<>'stock_count' then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 d:=inventory.count_normalize((p_doc->>'tenant_id')::uuid,(p_doc->>'legal_entity_id')::uuid,(p_doc->>'branch_id')::uuid,p_doc,p_doc);
 if d->'lines'<>p_doc->'lines' or d->>'currency_code'<>p_doc->>'currency_code' then
  raise exception using errcode='55000',message='COUNT_REAPPROVAL_REQUIRED';end if;
 return d;
end $$;

create function api.upsert_stock_count(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare id uuid:=(p_payload->>'id')::uuid;req uuid:=gen_random_uuid();h text;result jsonb;old_doc jsonb;d jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null or id is null then raise exception using errcode='22023',message='COUNT_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.stock_count.upsert',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'inventory.stock_count.upsert',p_command_id,p_idempotency_key,h);if result is not null then return result;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':count:'||id::text,0));
 old_doc:=inventory.count_document('stock_count',p_tenant_id,id,true);
 if old_doc is not null then
  if old_doc->>'legal_entity_id'<>p_legal_entity_id::text or old_doc->>'branch_id'<>p_branch_id::text then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
  perform core.wave3_assert_expected_version((old_doc->>'version')::bigint,p_expected_entity_version,old_doc);
  if old_doc->>'status'<>'draft' then raise exception using errcode='55000',message='DOCUMENT_NOT_EDITABLE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 d:=inventory.count_normalize(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,old_doc);
 insert into inventory.stock_counts(id,tenant_id,legal_entity_id,branch_id,warehouse_id,cutoff_at,document_date,reason,currency_code,offset_account_id,lines,grand_total,corrects_count_id,
 request_id,command_id,correlation_id,client_timestamp,prepared_by,created_by,updated_by)
 values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(d->>'warehouse_id')::uuid,(d->>'cutoff_at')::timestamptz,(d->>'document_date')::date,d->>'reason',d->>'currency_code',
 (d->>'offset_account_id')::uuid,d->'lines',(d->>'grand_total')::numeric,(p_payload->>'corrects_count_id')::uuid,req,p_command_id,req,p_client_timestamp,auth.uid(),auth.uid(),auth.uid())
 on conflict on constraint stock_counts_pkey do update set document_date=excluded.document_date,reason=excluded.reason,offset_account_id=excluded.offset_account_id,
 lines=excluded.lines,grand_total=excluded.grand_total,prepared_by=auth.uid(),updated_by=auth.uid(),request_id=req,command_id=p_command_id,correlation_id=req,client_timestamp=p_client_timestamp
 where inventory.stock_counts.tenant_id=excluded.tenant_id and inventory.stock_counts.legal_entity_id=excluded.legal_entity_id and inventory.stock_counts.branch_id=excluded.branch_id;
 if not found then raise exception using errcode='42501',message='DOCUMENT_SCOPE_INVALID';end if;
 return core.wave3_finish_command(p_tenant_id,'inventory.stock_count.upsert',p_command_id,'stock_count',id,p_idempotency_key,h,old_doc,
 inventory.count_document('stock_count',p_tenant_id,id),p_legal_entity_id,p_branch_id,'{}',null,'[]','[]',req,req);
end $$;
revoke all on inventory.stock_counts from public,anon,authenticated;
grant select on inventory.stock_counts to authenticated;
create view api.stock_counts with(security_invoker=true) as
 select id,tenant_id,legal_entity_id,branch_id,warehouse_id,document_number,document_date,status,version,
 sales.flow_exact_json(to_jsonb(o)) as detail from inventory.stock_counts o;
revoke all on api.stock_counts from public,anon,authenticated;
grant select on api.stock_counts to authenticated;

create function inventory.count_document(p_kind text,p_tenant uuid,p_id uuid,p_lock boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d inventory.stock_counts%rowtype; begin
 if p_kind is distinct from 'stock_count' then raise exception using errcode='22023',message='DOCUMENT_TYPE_INVALID';end if;
 if p_lock then select * into d from inventory.stock_counts where tenant_id=p_tenant and id=p_id for update;
 else select * into d from inventory.stock_counts where tenant_id=p_tenant and id=p_id;end if;
 if not found then return null;end if;
 return sales.flow_exact_json(to_jsonb(d))||jsonb_build_object('warehouse_name',(select name from core.warehouses where id=d.warehouse_id),
  'offset_account_name',(select name from finance.accounts where id=d.offset_account_id));
end $$;


create function api.transition_stock_count(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_kind text:='stock_count';v_id uuid:=(p_payload->>'document_id')::uuid;
 v_action text:=p_payload->>'action';v_decision text:=p_payload->>'decision';v_command text;
 v_doc jsonb;v_before jsonb;v_hash text;v_replay jsonb;v_to text;v_snapshot jsonb;
 v_workflow workflow.workflow_definitions%rowtype;v_request uuid:=gen_random_uuid();v_first integer;
 v_ar workflow.approval_requests%rowtype;v_step jsonb;v_number text;
begin
 v_command:='inventory.'||v_kind||case when v_decision is null then '.transition' else '.decide' end;
 perform core.wave3_require_scope(p_tenant_id,case when v_decision is null then 'inventory.adjustments.post' else 'workflow.approvals.decide' end,p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null
 or (p_payload ? 'document_type' and p_payload->>'document_type' is distinct from 'stock_count')
 or (v_decision is not null and v_action is not null) then raise exception using errcode='22023',message='DOCUMENT_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_replay is not null then return v_replay;end if;
 v_doc:=inventory.count_document(v_kind,p_tenant_id,v_id,true);v_before:=v_doc;
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
 perform inventory.count_revalidate(v_kind,v_doc);
 select * into v_workflow from workflow.workflow_definitions where tenant_id=p_tenant_id and document_type=v_kind and status='active'
 and (legal_entity_id is null or legal_entity_id=p_legal_entity_id) order by (legal_entity_id is not null) desc limit 1;
 if not found then raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';end if;
 select jsonb_build_object('definition_id',v_workflow.id,'revision',v_workflow.revision,'lifecycle',v_workflow.lifecycle,
 'steps',coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(s)) order by s.step_order),'[]'::jsonb)) into v_snapshot
 from workflow.approval_matrix_steps s where s.tenant_id=p_tenant_id and s.workflow_definition_id=v_workflow.id and s.status='active'
 and (s.currency_code is null or s.currency_code=v_doc->>'currency_code')
 and (s.minimum_amount is null or (v_doc->>'grand_total')::numeric>=s.minimum_amount)
 and (s.maximum_amount is null or (v_doc->>'grand_total')::numeric<=s.maximum_amount);
 if v_workflow.lifecycle->'requires_approval'='false'::jsonb then
 raise exception using errcode='55000',message='COUNT_APPROVAL_REQUIRED';end if;
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
 if v_snapshot is null and v_doc->>'status'='draft' then
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
 execute format('update inventory.%I set status=$1,workflow_snapshot=$2,document_number=$3,submitted_by=case when $4=''submit'' then $5 else submitted_by end,updated_by=$5,request_id=$6,command_id=$7,correlation_id=$6,client_timestamp=$8 where tenant_id=$9 and id=$10','stock_counts')
 using v_to,v_snapshot,v_number,v_action,auth.uid(),v_request,p_command_id,p_client_timestamp,p_tenant_id,v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,v_kind,v_id,p_idempotency_key,v_hash,v_before,
 inventory.count_document(v_kind,p_tenant_id,v_id),p_legal_entity_id,p_branch_id,coalesce(p_payload->'source_context','{}'),
 case when v_doc->>'status'=v_to then null else
 jsonb_build_object('from_status',v_doc->>'status','to_status',v_to,'reason',coalesce(p_payload->>'reason',p_payload->>'note')) end,
 jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('status',v_to))),'[]',v_request,v_request);
end $$;




create function api.post_stock_adjustment(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
 p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'document_id')::uuid;req uuid:=gen_random_uuid();h text;result jsonb;d jsonb;x jsonb;
 l inventory.transfer_lines%rowtype;jlines jsonb:='[]';j uuid;m uuid;q numeric;amount numeric;v_date date;identity_row jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null or v_id is null then raise exception using errcode='22023',message='COUNT_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.stock_count.post',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'inventory.stock_count.post',p_command_id,p_idempotency_key,h);if result is not null then return result;end if;
 d:=inventory.count_document('stock_count',p_tenant_id,v_id,true);
 if d is null or d->>'legal_entity_id'<>p_legal_entity_id::text or d->>'branch_id'<>p_branch_id::text then raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 perform core.wave3_assert_expected_version((d->>'version')::bigint,p_expected_entity_version,d);
 if d->>'status'<>'approved' then raise exception using errcode='55000',message='COUNT_APPROVAL_REQUIRED';end if;
 perform sales.flow_assert_transition(d#>'{workflow_snapshot,lifecycle}','approved','posted');
 if d#>'{workflow_snapshot,lifecycle,separate_poster}'='true'::jsonb and (d->>'submitted_by')::uuid=auth.uid() then raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
 v_date:=(d->>'document_date')::date;
 if v_date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 perform inventory.count_revalidate('stock_count',d);
 for x in select value from jsonb_array_elements(d->'lines') order by value->>'product_id' loop
  for identity_row in select value from jsonb_array_elements(coalesce(x->'identities',jsonb_build_array(x)))
   order by (value->>'variance_quantity')::numeric desc,value->>'id' loop
  q:=(identity_row->>'variance_quantity')::numeric;amount:=(identity_row->>'variance_value')::numeric;
  if q=0 then continue;end if;
  l:=null;l.id:=(x->>'line_id')::uuid;l.product_id:=(x->>'product_id')::uuid;l.serial_ids:='{}';
  if x ? 'identities' then l.id:=md5((x->>'line_id')||':'||(identity_row->>'id'))::uuid;end if;
  if x->>'tracking_mode'='lot' then l.lot_id:=(identity_row->>'id')::uuid;
  elsif x->>'tracking_mode'='serial' then
   l.serial_ids:=array[(identity_row->>'id')::uuid];l.lot_id:=(identity_row->>'lot_id')::uuid;
  end if;
  perform inventory.transfer_leg(p_tenant_id,p_legal_entity_id,p_branch_id,(d->>'warehouse_id')::uuid,v_id,l,v_date,q,amount,'stock_count',req,p_command_id);
  if x->>'tracking_mode'='serial' then
   update inventory.serials set status=case when q<0 then 'count_missing' else identity_row->>'restore_status' end,
    count_previous_status=case when q<0 then status else null end,updated_by=auth.uid()
    where tenant_id=p_tenant_id and id=(identity_row->>'id')::uuid and warehouse_id=(d->>'warehouse_id')::uuid
     and version=(identity_row->>'baseline_version')::bigint and status=identity_row->>'disposition';
   if not found then raise exception using errcode='55000',message='COUNT_SERIAL_CHANGED';end if;
  end if;
  if amount<>0 then jlines:=jlines||jsonb_build_array(finance.flow_jline((x->>'inventory_account_id')::uuid,amount,amount,l.id),
   finance.flow_jline((d->>'offset_account_id')::uuid,-amount,-amount,l.id));end if;
  end loop;
 end loop;
 j:=finance.flow_post_journal(d||jsonb_build_object('base_currency_code',d->>'currency_code','exchange_rate','1'),jlines,'stock_count',v_id,req,p_command_id);
 select id into m from inventory.stock_movements where tenant_id=p_tenant_id and source_type='stock_count' and source_id=v_id;
 update inventory.stock_counts set status='posted',posted_at=clock_timestamp(),posted_by=auth.uid(),updated_by=auth.uid(),stock_movement_id=m,journal_entry_id=j,
 request_id=req,command_id=p_command_id,correlation_id=req,client_timestamp=p_client_timestamp where tenant_id=p_tenant_id and id=v_id;
 return core.wave3_finish_command(p_tenant_id,'inventory.stock_count.post',p_command_id,'stock_count',v_id,p_idempotency_key,h,d,
 inventory.count_document('stock_count',p_tenant_id,v_id),p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('from_status','approved','to_status','posted','reason',d->>'reason'),
 jsonb_build_array(jsonb_build_object('topic','inventory.stock_count.post','payload',jsonb_build_object('id',v_id))),'[]',req,req);
end $$;
revoke all on function inventory.count_document(text,uuid,uuid,boolean),inventory.count_normalize(uuid,uuid,uuid,jsonb,jsonb),inventory.count_revalidate(text,jsonb) from public,anon,authenticated;
do $$declare f text;begin
 foreach f in array array['upsert_stock_count','transition_stock_count','post_stock_adjustment'] loop
  execute format('revoke all on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated',f);
  execute format('grant execute on function api.%I(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated',f);
 end loop;
end $$;

create function api.stock_counts_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if not core.has_permission(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id) and not core.has_permission(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'document_number',q.document_number,'document_date',q.document_date,'status',q.status,
  'version',q.version,'currency_code',q.currency_code,'grand_total',q.grand_total::text,'warehouse_name',(select name from core.warehouses where id=q.warehouse_id)) order by q.id),'[]') into rows
 from (select * from inventory.stock_counts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and (p_after is null or id>p_after) order by id limit 51)q;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',next_id);
end $$;
create function api.stock_count_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d jsonb;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if not core.has_permission(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id) and not core.has_permission(p_tenant_id,'workflow.approvals.decide',p_legal_entity_id,p_branch_id) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 d:=inventory.count_document('stock_count',p_tenant_id,p_id);
 if d is null or d->>'legal_entity_id' is distinct from p_legal_entity_id::text or d->>'branch_id' is distinct from p_branch_id::text then raise exception using errcode='P0002',message='DOCUMENT_NOT_FOUND';end if;
 return d;
end $$;
revoke all on function api.stock_count_detail(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.stock_count_detail(uuid,uuid,uuid,uuid) to authenticated;
create function api.stock_count_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_warehouse_id uuid default null,p_after uuid default null,p_search text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.adjustments.post',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.cost.view',p_legal_entity_id,p_branch_id);
 if coalesce(length(p_search),0)>100 then raise exception using errcode='22023',message='SEARCH_TOO_LONG';end if;
 if p_resource='warehouses' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from
  (select id,name,code from core.warehouses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='active'
   and (p_after is null or id>p_after) and (name ilike '%'||p_search||'%' or code ilike '%'||p_search||'%') order by id limit 51)q;
 elsif p_resource='accounts' then
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from
  (select a.id,a.name,a.code from finance.accounts a join core.legal_entities e on e.id=a.legal_entity_id where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
   and a.status='active' and a.is_posting and a.account_type='expense' and (a.currency_code is null or a.currency_code=e.currency_code)
   and (p_after is null or a.id>p_after) and (a.name ilike '%'||p_search||'%' or a.code ilike '%'||p_search||'%') order by a.id limit 51)q;
 elsif p_resource='products' then
  if not exists(select 1 from core.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='active') then raise exception using errcode='42501',message='WAREHOUSE_SCOPE_INVALID';end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into rows from
  (select p.id,p.name,p.sku,b.on_hand_quantity::text from inventory.products p join inventory.stock_balances b on b.product_id=p.id and b.warehouse_id=p_warehouse_id
   where p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.status='active' and p.kind='stocked'
   and (p_after is null or p.id>p_after) and (p.name ilike '%'||p_search||'%' or p.sku ilike '%'||p_search||'%') order by p.id limit 51)q;
 else raise exception using errcode='22023',message='COUNT_RESOURCE_INVALID';end if;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',next_id);
end $$;
revoke all on function api.stock_counts_page(uuid,uuid,uuid,uuid),api.stock_count_options(uuid,uuid,uuid,text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.stock_counts_page(uuid,uuid,uuid,uuid),api.stock_count_options(uuid,uuid,uuid,text,uuid,uuid,text) to authenticated;
