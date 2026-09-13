-- FR-350 dependency for procurement receipts. No existing product or stock rows changed.
create table inventory.product_unit_conversions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,product_id uuid not null,
 unit_id uuid not null,base_unit_id uuid not null,numerator bigint not null check(numerator>0),denominator bigint not null check(denominator>0),
 status text not null check(status in('active','inactive')),version bigint not null default 1,
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,product_id,unit_id),
 foreign key(tenant_id,legal_entity_id,product_id) references inventory.products(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,unit_id) references inventory.units(tenant_id,id),
 foreign key(tenant_id,base_unit_id) references inventory.units(tenant_id,id),check(unit_id<>base_unit_id)
);
create table inventory.product_unit_history(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,conversion_id uuid not null,
 version bigint not null,snapshot jsonb not null,actor_id uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(conversion_id,version),foreign key(tenant_id,legal_entity_id,conversion_id) references inventory.product_unit_conversions(tenant_id,legal_entity_id,id)
);
alter table inventory.product_unit_conversions enable row level security;alter table inventory.product_unit_conversions force row level security;
alter table inventory.product_unit_history enable row level security;alter table inventory.product_unit_history force row level security;
create policy product_units_read on inventory.product_unit_conversions for select to authenticated
 using(core.has_permission(tenant_id,'inventory.catalog.view',legal_entity_id,null) or core.has_permission(tenant_id,'inventory.catalog.manage',legal_entity_id,null));
create policy product_units_read on inventory.product_unit_history for select to authenticated
 using(exists(select 1 from inventory.product_unit_conversions c where c.id=conversion_id and c.tenant_id=product_unit_history.tenant_id));
create trigger product_unit_history_immutable before update or delete on inventory.product_unit_history for each row execute function workflow.reject_history_mutation();
revoke all on inventory.product_unit_conversions,inventory.product_unit_history from public,anon,authenticated;
grant select on inventory.product_unit_conversions,inventory.product_unit_history to authenticated;
create view api.product_unit_conversions with(security_invoker=true) as
select c.tenant_id,c.legal_entity_id,c.id,c.product_id,c.status,sales.flow_exact_json(to_jsonb(c))||jsonb_build_object(
 'numerator',c.numerator::text,'denominator',c.denominator::text) detail from inventory.product_unit_conversions c;
grant select on api.product_unit_conversions to authenticated;

create function api.upsert_product_unit_conversion(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;v_hash text;v_result jsonb;v_old inventory.product_unit_conversions%rowtype;
 v_product inventory.products%rowtype;v_num bigint;v_den bigint;v_before jsonb;v_entity jsonb;v_unit uuid:=(p_payload->>'unit_id')::uuid;
begin
 perform core.wave3_require_scope(p_tenant_id,'inventory.catalog.manage',p_legal_entity_id,p_branch_id);
 perform core.require_permission(p_tenant_id,'inventory.catalog.manage',p_legal_entity_id,null);
 if p_legal_entity_id is null or p_branch_id is null or v_id is null or p_client_timestamp is null or jsonb_typeof(p_payload) is distinct from 'object' then
  raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 v_hash:=core.wave3_request_hash('inventory.product_unit.upsert',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,'inventory.product_unit.upsert',p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_product from inventory.products where id=(p_payload->>'product_id')::uuid and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' for share;
 if not found then raise exception using errcode='22023',message='PRODUCT_INVALID';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('product-unit:'||v_product.id::text||':'||v_unit::text,0));
 select * into v_old from inventory.product_unit_conversions where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id for update;
 if found then
  v_before:=sales.flow_exact_json(to_jsonb(v_old))||jsonb_build_object('numerator',v_old.numerator::text,'denominator',v_old.denominator::text);
  perform core.wave3_assert_expected_version(v_old.version,p_expected_entity_version,v_before);
  if v_old.product_id<>v_product.id or v_old.unit_id<>v_unit or v_old.base_unit_id<>v_product.base_unit_id then raise exception using errcode='22023',message='CONVERSION_IDENTITY_IMMUTABLE';end if;
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 if v_unit=v_product.base_unit_id or not exists(select 1 from inventory.units u join inventory.units b on b.id=v_product.base_unit_id and b.tenant_id=u.tenant_id
  where u.id=v_unit and u.tenant_id=p_tenant_id and u.status='active' and b.status='active' and u.category=b.category) then
  raise exception using errcode='22023',message='CONVERSION_UNIT_INVALID';end if;
 v_num:=sales.wave3_positive_bigint(p_payload->'numerator','numerator');v_den:=sales.wave3_positive_bigint(p_payload->'denominator','denominator');
 insert into inventory.product_unit_conversions(id,tenant_id,legal_entity_id,product_id,unit_id,base_unit_id,numerator,denominator,status,created_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,v_product.id,v_unit,v_product.base_unit_id,v_num,v_den,p_payload->>'status',auth.uid(),auth.uid())
 on conflict(id) do update set numerator=excluded.numerator,denominator=excluded.denominator,status=excluded.status,version=inventory.product_unit_conversions.version+1,
  updated_by=auth.uid(),updated_at=clock_timestamp() where inventory.product_unit_conversions.tenant_id=p_tenant_id and inventory.product_unit_conversions.legal_entity_id=p_legal_entity_id;
 if not found then raise exception using errcode='22023',message='CONVERSION_IDENTITY_INVALID';end if;
 select sales.flow_exact_json(to_jsonb(c))||jsonb_build_object('numerator',c.numerator::text,'denominator',c.denominator::text) into v_entity
  from inventory.product_unit_conversions c where c.id=v_id;
 v_result:=core.wave3_finish_command(p_tenant_id,'inventory.product_unit.upsert',p_command_id,'product_unit_conversion',v_id,p_idempotency_key,v_hash,v_before,v_entity,
  p_legal_entity_id,p_branch_id,'{}',null,jsonb_build_array(jsonb_build_object('topic','inventory.product_unit.updated','payload','{}'::jsonb)));
 insert into inventory.product_unit_history(tenant_id,legal_entity_id,conversion_id,version,snapshot,actor_id)
 values(p_tenant_id,p_legal_entity_id,v_id,(v_entity->>'version')::bigint,v_entity,auth.uid());return v_result;
end $$;
revoke all on function api.upsert_product_unit_conversion(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_product_unit_conversion(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function inventory.resolve_product_unit(p_tenant uuid,p_entity uuid,p_product uuid,p_unit uuid,p_quantity jsonb,p_numerator jsonb,p_denominator jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_product inventory.products%rowtype;v_conversion inventory.product_unit_conversions%rowtype;v_quantity numeric;v_base numeric;
 v_num bigint;v_den bigint;v_precision integer;v_base_precision integer;
begin
 if auth.uid() is null or not core.is_tenant_member(p_tenant) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 v_quantity:=sales.wave3_decimal_string(p_quantity,'quantity',6,true,0,null);
 v_num:=sales.wave3_positive_bigint(p_numerator,'conversion_numerator');v_den:=sales.wave3_positive_bigint(p_denominator,'conversion_denominator');
 select precision into v_precision from inventory.units where id=p_unit and tenant_id=p_tenant and status='active';
 if not found or v_quantity<=0 or round(v_quantity,v_precision)<>v_quantity then raise exception using errcode='22023',message='TRANSACTION_UNIT_PRECISION_INVALID';end if;
 if p_product is null then
  if v_num<>1 or v_den<>1 then raise exception using errcode='22023',message='FREE_TEXT_UNIT_MUST_BE_BASE';end if;
  v_base_precision:=v_precision;
 else
  select * into v_product from inventory.products where id=p_product and tenant_id=p_tenant and legal_entity_id=p_entity and status='active';
  if not found then raise exception using errcode='22023',message='PRODUCT_INVALID';end if;
  select precision into v_base_precision from inventory.units where id=v_product.base_unit_id and tenant_id=p_tenant and status='active';
  if not found then raise exception using errcode='22023',message='BASE_UNIT_INVALID';end if;
  if p_unit=v_product.base_unit_id then
   if v_num<>1 or v_den<>1 then raise exception using errcode='22023',message='BASE_CONVERSION_MUST_BE_ONE';end if;
  else
   select * into v_conversion from inventory.product_unit_conversions where tenant_id=p_tenant and legal_entity_id=p_entity and product_id=p_product
    and unit_id=p_unit and base_unit_id=v_product.base_unit_id and status='active' for share;
   if not found or v_conversion.numerator<>v_num or v_conversion.denominator<>v_den then raise exception using errcode='22023',message='GOVERNED_CONVERSION_REQUIRED';end if;
  end if;
 end if;
 if mod(v_quantity*1000000*v_num,v_den)<>0 then raise exception using errcode='22023',message='BASE_QUANTITY_PRECISION_INVALID';end if;
 v_base:=v_quantity*v_num/v_den;
 if round(v_base,v_base_precision)<>v_base or v_base>=100000000000000 then raise exception using errcode='22023',message='BASE_QUANTITY_PRECISION_INVALID';end if;
 return jsonb_build_object('base_quantity',v_base::numeric(20,6)::text,'base_unit_id',coalesce(v_product.base_unit_id,p_unit),
  'conversion_numerator',v_num::text,'conversion_denominator',v_den::text,'conversion_id',v_conversion.id,'conversion_version',v_conversion.version);
end $$;
revoke all on function inventory.resolve_product_unit(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb) from public,anon,authenticated;
create index product_unit_unit on inventory.product_unit_conversions(tenant_id,unit_id);
create index product_unit_base on inventory.product_unit_conversions(tenant_id,base_unit_id);
create index product_unit_creator on inventory.product_unit_conversions(created_by);
create index product_unit_editor on inventory.product_unit_conversions(updated_by);
create index product_unit_history_source on inventory.product_unit_history(tenant_id,legal_entity_id,conversion_id);
create index product_unit_history_actor on inventory.product_unit_history(actor_id);
