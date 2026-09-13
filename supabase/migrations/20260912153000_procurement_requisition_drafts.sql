-- Candidate only: AC-309 / FR-335. Not applied. Published migrations are immutable.
-- Requisition save is deliberately separate from workflow submission/approval.
create table procurement.requisitions (
  id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  legal_entity_id uuid not null,
  branch_id uuid not null,
  requester_id uuid not null references auth.users(id),
  need_by date not null,
  justification text not null check (length(trim(justification)) between 1 and 4000),
  currency_code text not null references core.currencies(code),
  estimated_total numeric(20,6) not null check (estimated_total >= 0),
  status text not null default 'draft' check (status in ('draft','pending_approval','approved','rejected','cancelled')),
  version bigint not null default 1 check (version > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, id),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id,id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id,id)
);
create table procurement.requisition_lines (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  requisition_id uuid not null,
  ordinal integer not null check (ordinal between 1 and 500),
  product_id uuid,
  description text not null check (length(trim(description)) between 1 and 1000),
  unit_id uuid not null,
  quantity numeric(20,6) not null check (quantity > 0),
  base_quantity numeric(20,6) not null check(base_quantity>0),
  conversion_numerator bigint not null check(conversion_numerator>0),
  conversion_denominator bigint not null check(conversion_denominator>0),
  conversion_id uuid,conversion_version bigint,
  estimated_unit_price numeric(20,6) not null check (estimated_unit_price >= 0),
  estimated_total numeric(20,6) not null check (estimated_total >= 0),
  unique (requisition_id,ordinal),
  foreign key (tenant_id,legal_entity_id,requisition_id)
    references procurement.requisitions(tenant_id,legal_entity_id,id),
  foreign key (tenant_id,legal_entity_id,product_id)
    references inventory.products(tenant_id,legal_entity_id,id),
  foreign key (tenant_id,unit_id) references inventory.units(tenant_id,id)
);
create index requisitions_scope_page on procurement.requisitions(tenant_id,legal_entity_id,branch_id,id);
create index requisitions_requester on procurement.requisitions(requester_id);
create index requisitions_branch on procurement.requisitions(tenant_id,branch_id);
create index requisition_lines_source on procurement.requisition_lines(tenant_id,legal_entity_id,requisition_id);
create index requisition_lines_product on procurement.requisition_lines(tenant_id,legal_entity_id,product_id);
create index requisition_lines_unit on procurement.requisition_lines(tenant_id,unit_id);
alter table procurement.requisitions enable row level security;
alter table procurement.requisitions force row level security;
alter table procurement.requisition_lines enable row level security;
alter table procurement.requisition_lines force row level security;
create policy requisitions_read on procurement.requisitions for select to authenticated
using (core.has_permission(tenant_id,'procurement.requisitions.manage',legal_entity_id,branch_id));
create policy requisition_lines_read on procurement.requisition_lines for select to authenticated
using (exists (select 1 from procurement.requisitions r where r.id=requisition_id
  and r.tenant_id=requisition_lines.tenant_id and r.legal_entity_id=requisition_lines.legal_entity_id));
revoke all on procurement.requisitions,procurement.requisition_lines from public,anon,authenticated;
grant usage on schema procurement to authenticated;
grant select on procurement.requisitions,procurement.requisition_lines to authenticated;

create view api.purchase_requisitions with (security_invoker=true) as
select r.tenant_id,r.legal_entity_id,r.branch_id,r.id,r.status,
  jsonb_build_object('id',r.id,'requester_id',r.requester_id,'need_by',r.need_by,
    'justification',r.justification,'currency_code',r.currency_code,
    'estimated_total',r.estimated_total::text,'status',r.status,'version',r.version,
    'lines',coalesce((select jsonb_agg(jsonb_build_object(
      'line_id',l.id,'product_id',l.product_id,'description',l.description,
      'unit_id',l.unit_id,'quantity',l.quantity::text,
      'estimated_unit_price',l.estimated_unit_price::text,
      'estimated_total',l.estimated_total::text,
      'base_quantity',l.base_quantity::text,'conversion_numerator',l.conversion_numerator::text,
      'conversion_denominator',l.conversion_denominator::text,'conversion_id',l.conversion_id,'conversion_version',l.conversion_version) order by l.ordinal)
      from procurement.requisition_lines l where l.requisition_id=r.id),'[]'::jsonb)) detail
from procurement.requisitions r;
grant select on api.purchase_requisitions to authenticated;

create function api.upsert_purchase_requisition(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
  p_payload jsonb,p_expected_entity_version bigint default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid := (select auth.uid());
  v_id uuid; v_hash text; v_replay jsonb; v_before jsonb; v_entity jsonb;
  v_old procurement.requisitions%rowtype;
  v_line jsonb; v_unit jsonb; v_quantity numeric; v_price numeric; v_total numeric := 0;
  v_ordinal integer := 0; v_need_by date; v_currency text;
begin
  perform core.wave3_require_scope(p_tenant_id,'procurement.requisitions.manage',p_legal_entity_id,p_branch_id);
  if p_branch_id is null or p_legal_entity_id is null or p_client_timestamp is null
    or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception using errcode='22023',message='INVALID_COMMAND';
  end if;
  v_hash := core.wave3_request_hash('procurement.requisition.upsert',p_command_id,
    p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
  v_replay := core.wave3_replay(p_tenant_id,'procurement.requisition.upsert',p_command_id,p_idempotency_key,v_hash);
  if v_replay is not null then return v_replay; end if;
  v_id := (p_payload->>'id')::uuid;
  if v_id is null then raise exception using errcode='22023',message='DOCUMENT_ID_REQUIRED'; end if;
  -- Serialize create/update for the same stable document identity, including different keys.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('procurement.requisition:'||v_id::text,0));
  select * into v_old from procurement.requisitions where id=v_id
    and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
  if found then
    select detail into v_before from api.purchase_requisitions where id=v_id;
    perform core.wave3_assert_expected_version(v_old.version,p_expected_entity_version,v_before);
    if v_old.status <> 'draft' then
      raise exception using errcode='55000',message='REQUISITION_NOT_EDITABLE';
    end if;
  elsif p_expected_entity_version is not null then
    raise exception using errcode='40001',message='VERSION_CONFLICT';
  end if;
  if jsonb_typeof(p_payload->'lines') is distinct from 'array' then
    raise exception using errcode='22023',message='LINES_REQUIRED';
  end if;
  if jsonb_array_length(p_payload->'lines') not between 1 and 500
    or length(trim(coalesce(p_payload->>'justification',''))) not between 1 and 4000 then
    raise exception using errcode='22023',message='INVALID_REQUISITION';
  end if;
  if coalesce(p_payload->>'need_by','') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception using errcode='22023',message='NEED_BY_REQUIRED';
  end if;
  v_need_by := (p_payload->>'need_by')::date;
  select currency_code into v_currency from core.legal_entities
    where id=p_legal_entity_id and tenant_id=p_tenant_id;
  if p_payload->>'currency_code' is distinct from v_currency then
    raise exception using errcode='22023',message='ESTIMATE_BASE_CURRENCY_REQUIRED';
  end if;
  for v_line in select value from jsonb_array_elements(p_payload->'lines') loop
    v_quantity := sales.wave3_decimal_string(v_line->'quantity','quantity',6,true,0,null);
    v_price := sales.wave3_decimal_string(v_line->'estimated_unit_price','estimated_unit_price',6,true,0,null);
    if v_quantity <= 0 or v_quantity >= 100000000000000 or v_price >= 100000000000000 then
      raise exception using errcode='22023',message='BASE_UNIT_ESTIMATE_REQUIRED';
    end if;
    if not exists(select 1 from inventory.units u where u.id=(v_line->>'unit_id')::uuid
      and u.tenant_id=p_tenant_id and u.status='active'
      and round(v_quantity,u.precision)=v_quantity) then
      raise exception using errcode='22023',message='UNIT_INVALID';
    end if;
    if v_line->>'product_id' is not null and not exists(select 1 from inventory.products p
      where p.id=(v_line->>'product_id')::uuid and p.tenant_id=p_tenant_id
      and p.legal_entity_id=p_legal_entity_id and p.status='active' and p.can_purchase) then
      raise exception using errcode='22023',message='PRODUCT_INVALID';
    end if;
    v_total := v_total + round(v_quantity*v_price,6);
  end loop;
  if v_old.id is null then
    insert into procurement.requisitions(id,tenant_id,legal_entity_id,branch_id,requester_id,
      need_by,justification,currency_code,estimated_total,created_by,updated_by)
    values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_actor,v_need_by,
      trim(p_payload->>'justification'),v_currency,v_total,v_actor,v_actor);
  else
    update procurement.requisitions set need_by=v_need_by,justification=trim(p_payload->>'justification'),
      estimated_total=v_total,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() where id=v_id;
    delete from procurement.requisition_lines where requisition_id=v_id;
  end if;
  for v_line in select value from jsonb_array_elements(p_payload->'lines') loop
    v_ordinal := v_ordinal+1;
    v_quantity := (v_line->>'quantity')::numeric; v_price := (v_line->>'estimated_unit_price')::numeric;
    v_unit:=inventory.resolve_product_unit(p_tenant_id,p_legal_entity_id,(v_line->>'product_id')::uuid,(v_line->>'unit_id')::uuid,
      v_line->'quantity',v_line->'conversion_numerator',v_line->'conversion_denominator');
    insert into procurement.requisition_lines(id,tenant_id,legal_entity_id,requisition_id,ordinal,
      product_id,description,unit_id,quantity,estimated_unit_price,estimated_total,base_quantity,conversion_numerator,conversion_denominator,conversion_id,conversion_version)
    values((v_line->>'line_id')::uuid,p_tenant_id,p_legal_entity_id,v_id,v_ordinal,
      (v_line->>'product_id')::uuid,trim(v_line->>'description'),(v_line->>'unit_id')::uuid,
      v_quantity,v_price,round(v_quantity*v_price,6),(v_unit->>'base_quantity')::numeric,(v_unit->>'conversion_numerator')::bigint,
      (v_unit->>'conversion_denominator')::bigint,(v_unit->>'conversion_id')::uuid,(v_unit->>'conversion_version')::bigint);
  end loop;
  select detail into v_entity from api.purchase_requisitions where id=v_id;
  return core.wave3_finish_command(p_tenant_id,'procurement.requisition.upsert',p_command_id,
    'purchase_requisition',v_id,p_idempotency_key,v_hash,v_before,v_entity,p_legal_entity_id,p_branch_id,
    '{}'::jsonb,null,jsonb_build_array(jsonb_build_object('topic','procurement.requisition.saved',
      'payload',jsonb_build_object('version',v_entity->'version'))));
end;
$$;
revoke all on function api.upsert_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_purchase_requisition(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
