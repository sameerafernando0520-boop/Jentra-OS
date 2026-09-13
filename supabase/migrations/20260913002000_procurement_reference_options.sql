-- AC-309 bounded reference reads. No role, membership or master-record mutations.
create function api.procurement_reference_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_resource text,p_after uuid default null,p_search text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_items jsonb;v_more boolean;v_currency text;v_search text;
begin
 if core.has_permission(p_tenant_id,'procurement.requisitions.manage',p_legal_entity_id,p_branch_id) then
  perform core.wave3_require_scope(p_tenant_id,'procurement.requisitions.manage',p_legal_entity_id,p_branch_id);
 elsif core.has_permission(p_tenant_id,'procurement.rfq.manage',p_legal_entity_id,p_branch_id) then
  perform core.wave3_require_scope(p_tenant_id,'procurement.rfq.manage',p_legal_entity_id,p_branch_id);
 elsif core.has_permission(p_tenant_id,'inventory.catalog.manage',p_legal_entity_id,p_branch_id) then
  perform core.wave3_require_scope(p_tenant_id,'inventory.catalog.manage',p_legal_entity_id,p_branch_id);
 else perform core.wave3_require_scope(p_tenant_id,'procurement.orders.manage',p_legal_entity_id,p_branch_id);end if;
 if p_legal_entity_id is null or p_branch_id is null or length(coalesce(p_search,''))>100 then
  raise exception using errcode='22023',message='REFERENCE_SCOPE_INVALID';end if;
 v_search:=lower(trim(coalesce(p_search,'')));
 select currency_code into v_currency from core.legal_entities where id=p_legal_entity_id and tenant_id=p_tenant_id;
 if p_resource='units' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'precision',precision) order by id)
  into v_items from(select * from inventory.units where tenant_id=p_tenant_id and status='active'
   and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51) x;
 elsif p_resource='unit_conversions' then
  perform core.require_permission(p_tenant_id,'inventory.catalog.manage',p_legal_entity_id,null);
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'detail',detail) order by id)
  into v_items from(select c.id,p.sku code,u.name,p.name||' · '||u.name label,
   c.detail||jsonb_build_object('_product_name',p.name,'_unit_name',u.name) detail
   from api.product_unit_conversions c join inventory.products p on p.id=c.product_id and p.tenant_id=c.tenant_id
   join inventory.units u on u.id=(c.detail->>'unit_id')::uuid and u.tenant_id=c.tenant_id
   where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and (p_after is null or c.id>p_after)
   and (v_search='' or position(v_search in lower(p.sku||' '||p.name||' '||u.name))>0) order by c.id limit 51) x;
 elsif p_resource like 'product_units:%' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'conversion_numerator',numerator::text,
    'conversion_denominator',denominator::text,'conversion_id',conversion_id,'conversion_version',version) order by id)
  into v_items from(select * from (
   select u.id,u.code,u.name,1::bigint numerator,1::bigint denominator,null::uuid conversion_id,null::bigint version
   from inventory.products p join inventory.units u on u.id=p.base_unit_id and u.tenant_id=p.tenant_id
   where p.id=substring(p_resource from 15)::uuid and p.tenant_id=p_tenant_id and p.legal_entity_id=p_legal_entity_id and p.status='active' and u.status='active'
   union all
   select u.id,u.code,u.name,c.numerator,c.denominator,c.id,c.version from inventory.product_unit_conversions c
   join inventory.units u on u.id=c.unit_id and u.tenant_id=c.tenant_id
   where c.product_id=substring(p_resource from 15)::uuid and c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and c.status='active' and u.status='active'
  ) q where (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51) x;
 elsif p_resource='requisitions' then
  select jsonb_agg(jsonb_build_object('id',id,'code',detail->>'document_number','name',detail->>'justification','detail',detail) order by id)
  into v_items from(select * from api.purchase_requisitions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and status='approved' and (p_after is null or id>p_after)
   and (v_search='' or position(v_search in lower(detail->>'justification'))>0) order by id limit 51) x;
 elsif p_resource='selected_rfqs' then
  select jsonb_agg(jsonb_build_object('id',id,'code',detail->>'document_number','name',detail->>'title','detail',detail) order by id)
  into v_items from(select * from api.request_for_quotes where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and status='selected' and (p_after is null or id>p_after)
   and (v_search='' or position(v_search in lower(detail->>'title'))>0) order by id limit 51) x;
 elsif p_resource='rates' then
  select jsonb_agg(jsonb_build_object('id',id,'code',source_currency_code,'name',effective_date::text||' · '||rate::text,
   'currency_code',source_currency_code,'exchange_rate',rate::text,'rate_date',effective_date) order by id)
  into v_items from(select * from finance.exchange_rates where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and status='active' and target_currency_code=v_currency and (p_after is null or id>p_after)
   and (v_search='' or position(v_search in lower(source_currency_code))>0) order by id limit 51) x;
 elsif p_resource='taxes' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'rate',rate::text,'inclusive',inclusive) order by id)
  into v_items from(select * from finance.tax_definitions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and status='active' and kind in('input','zero','exempt') and (p_after is null or id>p_after)
   and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51) x;
 elsif p_resource in('products','catalogue_products') then
  if p_resource='catalogue_products' then perform core.require_permission(p_tenant_id,'inventory.catalog.manage',p_legal_entity_id,null);end if;
  select jsonb_agg(jsonb_build_object('id',id,'code',sku,'name',name,'unit_id',base_unit_id) order by id)
  into v_items from(select * from inventory.products where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and status='active' and (can_purchase or p_resource='catalogue_products') and (p_after is null or id>p_after)
   and (v_search='' or position(v_search in lower(sku||' '||name))>0) order by id limit 51) x;
 elsif p_resource='suppliers' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',display_name) order by id)
  into v_items from(select * from crm.parties where tenant_id=p_tenant_id and status='active' and kind in('supplier','both')
   and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(code||' '||display_name))>0) order by id limit 51) x;
 elsif p_resource='warehouses' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by id)
  into v_items from(select * from core.warehouses where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and branch_id=p_branch_id and status='active' and (p_after is null or id>p_after)
   and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51) x;
 else raise exception using errcode='22023',message='REFERENCE_RESOURCE_INVALID';end if;
 v_items:=coalesce(v_items,'[]');v_more:=jsonb_array_length(v_items)>50;
 if v_more then v_items:=v_items-50;end if;
 return jsonb_build_object('items',v_items,'next_cursor',case when v_more then v_items#>>'{49,id}' else null end,
  'base_currency',v_currency,'limit',50);
end $$;
revoke all on function api.procurement_reference_options(uuid,uuid,uuid,text,uuid,text) from public,anon;
grant execute on function api.procurement_reference_options(uuid,uuid,uuid,text,uuid,text) to authenticated;
