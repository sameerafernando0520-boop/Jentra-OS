-- UNAPPLIED bounded reservation lifecycle maintenance. All effects use the
-- existing release command, which locks order, product/warehouse and projection.
create index reservation_maintenance_cursor on inventory.stock_reservations
 (tenant_id,legal_entity_id,branch_id,status,sales_order_id,id)
 include(expires_at,product_id);

create function api.maintain_stock_reservations(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;v_mode text:=p_payload->>'mode';
 v_reason text:=btrim(coalesce(p_payload->>'reason',''));
 v_limit integer:=(p_payload->>'limit')::integer;
 v_after_order uuid:=(p_payload->>'after_order_id')::uuid;
 v_after_reservation uuid:=(p_payload->>'after_reservation_id')::uuid;
 v_last_order uuid:=v_after_order;v_last_reservation uuid:=v_after_reservation;
 v_hash text;v_replay jsonb;v_child jsonb;v_result jsonb;v_rows jsonb:='[]';
 v_count integer:=0;v_more boolean;v_request uuid:=gen_random_uuid();r record;begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.reservations.manage',p_legal_entity_id,p_branch_id);
 if v_id is null or p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null
  or p_command_id is null or p_idempotency_key is null or v_mode is null
  or v_mode not in('expired','retired') or v_limit is null
  or v_limit not between 1 and 50 or length(v_reason) not between 3 and 1000
  or (v_after_order is null) is distinct from (v_after_reservation is null)
  or jsonb_typeof(p_payload) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(p_payload) key
   where key not in('id','mode','reason','limit','after_order_id','after_reservation_id')) then
  raise exception using errcode='22023',message='RESERVATION_MAINTENANCE_INPUT_INVALID';end if;
 v_hash:=core.wave3_request_hash('inventory.reservation.maintain',p_command_id,p_tenant_id,
  p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_replay:=core.wave3_replay(p_tenant_id,'inventory.reservation.maintain',p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 for r in
  select res.id,res.version,res.sales_order_id from inventory.stock_reservations res
  join inventory.products product on product.tenant_id=res.tenant_id and product.id=res.product_id
  where res.tenant_id=p_tenant_id and res.legal_entity_id=p_legal_entity_id and res.branch_id=p_branch_id
   and res.status='active'
   and (v_after_order is null or (res.sales_order_id,res.id)>(v_after_order,v_after_reservation))
   and ((v_mode='expired' and res.expires_at<=statement_timestamp())
    or (v_mode='retired' and product.status<>'active'))
  order by res.sales_order_id,res.id limit v_limit
 loop
  v_child:=api.release_stock_reservation(p_tenant_id,p_legal_entity_id,p_branch_id,
   gen_random_uuid(),gen_random_uuid(),p_client_timestamp,
   jsonb_build_object('id',r.id,'mode',v_mode,'reason',v_reason),r.version);
  v_rows:=v_rows||jsonb_build_array(jsonb_build_object('reservation_id',r.id,
   'sales_order_id',r.sales_order_id,'receipt_id',v_child->>'request_id'));
  v_last_order:=r.sales_order_id;v_last_reservation:=r.id;v_count:=v_count+1;
 end loop;
 select exists(
  select 1 from inventory.stock_reservations res
  join inventory.products product on product.tenant_id=res.tenant_id and product.id=res.product_id
  where res.tenant_id=p_tenant_id and res.legal_entity_id=p_legal_entity_id and res.branch_id=p_branch_id
   and res.status='active'
   and (v_last_order is null or (res.sales_order_id,res.id)>(v_last_order,v_last_reservation))
   and ((v_mode='expired' and res.expires_at<=statement_timestamp())
    or (v_mode='retired' and product.status<>'active'))
 ) into v_more;
 v_result:=jsonb_build_object('id',v_id,'status','completed','tenant_id',p_tenant_id,
  'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'mode',v_mode,
  'processed_count',v_count,'processed',v_rows,'has_more',v_more,
  'next_cursor',case when v_more and v_count>0 then
   jsonb_build_object('after_order_id',v_last_order,'after_reservation_id',v_last_reservation) end);
 return core.wave3_finish_command(p_tenant_id,'inventory.reservation.maintain',p_command_id,
  'reservation_maintenance',v_id,p_idempotency_key,v_hash,null,v_result,
  p_legal_entity_id,p_branch_id,'{}',null,
  jsonb_build_array(jsonb_build_object('topic','inventory.reservation.maintained','payload',
   jsonb_build_object('id',v_id,'mode',v_mode,'processed_count',v_count))),
  '[]',v_request,v_request);
end $$;
revoke all on function api.maintain_stock_reservations(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 from public,anon,authenticated;
grant execute on function api.maintain_stock_reservations(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
 to authenticated;
notify pgrst,'reload schema';
