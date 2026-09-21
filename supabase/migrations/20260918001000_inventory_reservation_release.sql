-- Candidate only: governed release and immutable reservation history.
create table inventory.reservation_history_coverage (
 singleton boolean primary key default true check(singleton), starts_at timestamptz not null default clock_timestamp()
);
insert into inventory.reservation_history_coverage(singleton) values(true);
create table inventory.reservation_history (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, reservation_id uuid not null,
 legal_entity_id uuid not null, branch_id uuid not null, version bigint not null,
 recorded_at timestamptz not null, baseline boolean not null default false, actor_id uuid references auth.users(id),
 snapshot jsonb not null, unique(tenant_id,reservation_id,version),
 foreign key(tenant_id,reservation_id) references inventory.stock_reservations(tenant_id,id)
);
create index reservation_history_scope on inventory.reservation_history(tenant_id,legal_entity_id,branch_id,reservation_id,version);
create index reservation_history_actor on inventory.reservation_history(actor_id);
alter table inventory.reservation_history enable row level security;
alter table inventory.reservation_history force row level security;
alter table inventory.reservation_history_coverage enable row level security;
alter table inventory.reservation_history_coverage force row level security;
revoke all on inventory.reservation_history,inventory.reservation_history_coverage from public,anon,authenticated;
create trigger reservation_history_immutable before update or delete on inventory.reservation_history for each row execute function workflow.reject_history_mutation();
create function inventory.capture_reservation_history() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
  insert into inventory.reservation_history(tenant_id,reservation_id,legal_entity_id,branch_id,version,recorded_at,baseline,actor_id,snapshot)
  select old.tenant_id,old.id,old.legal_entity_id,old.branch_id,old.version,c.starts_at,true,null,
   sales.flow_exact_json(to_jsonb(old)) from inventory.reservation_history_coverage c
  on conflict(tenant_id,reservation_id,version) do nothing;
 end if;
 insert into inventory.reservation_history(tenant_id,reservation_id,legal_entity_id,branch_id,version,recorded_at,actor_id,snapshot)
 values(new.tenant_id,new.id,new.legal_entity_id,new.branch_id,new.version,clock_timestamp(),auth.uid(),sales.flow_exact_json(to_jsonb(new)));
 return new;
end $$;
revoke all on function inventory.capture_reservation_history() from public,anon,authenticated;
create trigger reservation_history_capture after insert or update on inventory.stock_reservations for each row execute function inventory.capture_reservation_history();

create function api.release_stock_reservation(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r inventory.stock_reservations%rowtype; o sales.sales_orders%rowtype; req uuid:=gen_random_uuid(); h text; result jsonb; before_doc jsonb;
 v_id uuid:=(p_payload->>'id')::uuid; mode text:=p_payload->>'mode';reason text:=trim(p_payload->>'reason'); next_status text;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.reservations.manage',p_legal_entity_id,p_branch_id);
 if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null or v_id is null
 or mode is null or mode not in('manual','expired','retired') or coalesce(length(reason),0) not between 3 and 1000 then
  raise exception using errcode='22023',message='RESERVATION_RELEASE_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('inventory.reservation.release',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 result:=core.wave3_replay(p_tenant_id,'inventory.reservation.release',p_command_id,p_idempotency_key,h);if result is not null then return result;end if;
 select * into r from inventory.stock_reservations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=v_id;
 if not found then raise exception using errcode='P0002',message='RESERVATION_NOT_FOUND';end if;
 select * into o from sales.sales_orders where tenant_id=p_tenant_id and id=r.sales_order_id for update;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||r.warehouse_id::text||':'||r.product_id::text,0));
 select * into r from inventory.stock_reservations where tenant_id=p_tenant_id and id=v_id for update;
 before_doc:=sales.flow_exact_json(to_jsonb(r));
 perform core.wave3_assert_expected_version(r.version,p_expected_entity_version,before_doc);
 if r.status<>'active' then raise exception using errcode='55000',message='RESERVATION_NOT_ACTIVE';end if;
 if mode='expired' and r.expires_at>clock_timestamp() then raise exception using errcode='55000',message='RESERVATION_NOT_EXPIRED';end if;
 if mode='retired' and exists(select 1 from inventory.products where tenant_id=p_tenant_id and id=r.product_id and status='active') then raise exception using errcode='55000',message='PRODUCT_STILL_ACTIVE';end if;
 update inventory.stock_balances set allocated_quantity=allocated_quantity-r.base_quantity,updated_by=auth.uid()
 where tenant_id=p_tenant_id and warehouse_id=r.warehouse_id and product_id=r.product_id and allocated_quantity>=r.base_quantity;
 if not found then raise exception using errcode='55000',message='RESERVATION_PROJECTION_MISMATCH';end if;
 update sales.sales_order_lines set allocated_quantity=allocated_quantity-r.base_quantity,updated_by=auth.uid(),request_id=req,command_id=p_command_id,correlation_id=req
 where tenant_id=p_tenant_id and id=r.sales_order_line_id and allocated_quantity>=r.base_quantity;
 if not found then raise exception using errcode='55000',message='RESERVATION_PROJECTION_MISMATCH';end if;
 update inventory.stock_reservations set status=case when mode='expired' then 'expired' else 'released' end,released_at=clock_timestamp(),release_reason=reason,
 updated_by=auth.uid(),request_id=req,command_id=p_command_id,correlation_id=req where id=v_id returning * into r;
 next_status:=o.status;
 if o.status in('confirmed','reserved','partially_reserved') then
  next_status:=case when exists(select 1 from sales.sales_order_lines where sales_order_id=o.id and allocated_quantity>0) then 'partially_reserved' else 'confirmed' end;
 end if;
 update sales.sales_orders set status=next_status,updated_by=auth.uid(),request_id=req,command_id=p_command_id,correlation_id=req,client_timestamp=p_client_timestamp where id=o.id;
 return core.wave3_finish_command(p_tenant_id,'inventory.reservation.release',p_command_id,'stock_reservation',v_id,p_idempotency_key,h,before_doc,
 sales.flow_exact_json(to_jsonb(r)),p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('from_status','active','to_status',r.status,'reason',reason),
 jsonb_build_array(jsonb_build_object('topic','inventory.reservation.release','payload',jsonb_build_object('id',v_id,'sales_order_id',o.id))),'[]',req,req);
end $$;
revoke all on function api.release_stock_reservation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.release_stock_reservation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function api.stock_reservation_queue(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_filter text default 'active',p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_id uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.reservations.manage',p_legal_entity_id,p_branch_id);
 if p_filter is null or p_filter not in('active','expired','retired','all') or p_branch_id is null then raise exception using errcode='22023',message='RESERVATION_FILTER_INVALID';end if;
 select coalesce(jsonb_agg(sales.flow_exact_json(to_jsonb(q)) order by q.id),'[]') into rows from
 (select r.id,r.version,r.status,r.base_quantity::text,r.expires_at,r.release_reason,r.sales_order_id,o.document_number,p.name product_name,w.name warehouse_name
  from inventory.stock_reservations r join sales.sales_orders o on o.id=r.sales_order_id join inventory.products p on p.id=r.product_id join core.warehouses w on w.id=r.warehouse_id
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and (p_after is null or r.id>p_after)
  and (p_filter='all' or r.status='active') and (p_filter<>'expired' or r.expires_at<=clock_timestamp()) and(p_filter<>'retired' or p.status<>'active') order by r.id limit 51)q;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',next_id);
end $$;
create function api.stock_reservation_history(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_before_version bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;next_version bigint;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.reservations.manage',p_legal_entity_id,p_branch_id);
 if not exists(select 1 from inventory.stock_reservations where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_id) then raise exception using errcode='P0002',message='RESERVATION_NOT_FOUND';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.version desc),'[]') into rows from
 (select version,recorded_at,baseline,actor_id,snapshot-'source_context' as snapshot from inventory.reservation_history
  where tenant_id=p_tenant_id and reservation_id=p_id and (p_before_version is null or version<p_before_version) order by version desc limit 51)q;
 if jsonb_array_length(rows)>50 then next_version:=(rows->49->>'version')::bigint;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_version',next_version,'coverage_start',(select starts_at from inventory.reservation_history_coverage));
end $$;
revoke all on function api.stock_reservation_queue(uuid,uuid,uuid,text,uuid),api.stock_reservation_history(uuid,uuid,uuid,uuid,bigint) from public,anon,authenticated;
grant execute on function api.stock_reservation_queue(uuid,uuid,uuid,text,uuid),api.stock_reservation_history(uuid,uuid,uuid,uuid,bigint) to authenticated;

create function api.stock_reservations_as_of(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_as_of timestamptz,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb; next_id uuid; coverage timestamptz;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.reservations.manage',p_legal_entity_id,p_branch_id);
 select starts_at into coverage from inventory.reservation_history_coverage;
 if p_branch_id is null or p_legal_entity_id is null or p_as_of is null or p_as_of<coverage or p_as_of>clock_timestamp() then
  raise exception using errcode='22023',message='RESERVATION_ASOF_OUTSIDE_COVERAGE';end if;
 select coalesce(jsonb_agg(q.detail order by q.id),'[]') into rows from (
  select r.id,jsonb_build_object('id',r.id,'version',(s.snapshot->>'version')::bigint,'status',s.snapshot->>'status',
   'base_quantity',s.snapshot->>'base_quantity','expires_at',s.snapshot->>'expires_at',
   'sales_order_id',r.sales_order_id,'document_number',o.document_number,'product_name',p.name,'warehouse_name',w.name) detail
  from inventory.stock_reservations r
  join sales.sales_orders o on o.tenant_id=r.tenant_id and o.id=r.sales_order_id
  join inventory.products p on p.tenant_id=r.tenant_id and p.id=r.product_id
  join core.warehouses w on w.tenant_id=r.tenant_id and w.id=r.warehouse_id
  cross join lateral (
   select coalesce(
    (select h.snapshot from inventory.reservation_history h where h.tenant_id=r.tenant_id and h.reservation_id=r.id
      and h.recorded_at<=p_as_of order by h.version desc limit 1),
    case when r.created_at<=coverage and not exists(select 1 from inventory.reservation_history h where h.tenant_id=r.tenant_id and h.reservation_id=r.id)
     then sales.flow_exact_json(to_jsonb(r)) end) snapshot
  ) s
  where r.tenant_id=p_tenant_id and r.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id
   and (p_after is null or r.id>p_after) and s.snapshot->>'status'='active'
  order by r.id limit 51
 )q;
 if jsonb_array_length(rows)>50 then next_id:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',next_id,'as_of',p_as_of,'coverage_start',coverage);
end $$;
revoke all on function api.stock_reservations_as_of(uuid,uuid,uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function api.stock_reservations_as_of(uuid,uuid,uuid,timestamptz,uuid) to authenticated;
