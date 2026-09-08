-- AC-304: coherent order workspace, safe fulfillment revisions and credit/stock guards.
-- Existing migrations are immutable. No production use or seeded data is included.

create view api.sales_order_details with (security_invoker = true) as
select o.*, coalesce((
  select jsonb_agg(to_jsonb(l) order by l.line_number,l.id)
  from api.sales_order_lines l
  where l.tenant_id=o.tenant_id and l.legal_entity_id=o.legal_entity_id
    and l.branch_id=o.branch_id and l.sales_order_id=o.id
), '[]'::jsonb) as lines
from api.sales_orders o;
revoke all on api.sales_order_details from public, anon, authenticated;
grant select on api.sales_order_details to authenticated;

create function api.get_sales_order_credit_preview(
  p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_sales_order_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_order sales.sales_orders%rowtype;
  v_customer crm.parties%rowtype;
  v_projection sales.customer_credit_exposures%rowtype;
  v_existing numeric(20,6);
  v_due numeric(20,6);
  v_overdue numeric(20,6);
  v_total numeric(20,6);
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'sales.orders.manage', p_legal_entity_id, p_branch_id);
  if p_branch_id is null then
    raise exception using errcode='22023', message='Branch is required.';
  end if;
  select * into v_order from sales.sales_orders
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and id=p_sales_order_id;
  if not found then
    raise exception using errcode='P0002', message='Sales order was not found.';
  end if;
  select * into v_customer from crm.parties
  where tenant_id=p_tenant_id and id=v_order.customer_id;
  select * into v_projection from sales.customer_credit_exposures
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and customer_id=v_order.customer_id
    and currency_code=v_order.currency_code;
  v_due := coalesce(v_projection.due_exposure,0);
  v_overdue := coalesce(v_projection.overdue_exposure,0);
  select coalesce(sum(grand_total),0) into v_existing from sales.sales_orders
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and customer_id=v_order.customer_id
    and currency_code=v_order.currency_code and id<>v_order.id
    and status in ('confirmed','partially_reserved','reserved');
  v_total := v_due + v_existing + v_order.grand_total;
  return jsonb_build_object(
    'sales_order_id',v_order.id,'order_version',v_order.version,
    'customer_id',v_order.customer_id,'customer_status',v_customer.status,
    'currency_code',v_order.currency_code,
    'credit_currency_code',v_customer.credit_currency_code,
    'credit_limit',v_customer.credit_limit::text,
    'due_exposure',v_due::text,'overdue_exposure',v_overdue::text,
    'existing_order_exposure',v_existing::text,
    'current_order_exposure',v_order.grand_total::text,'total_exposure',v_total::text,
    'projection_available',v_projection.id is not null,
    'credit_as_of_at',v_projection.as_of_at,'checked_at',statement_timestamp(),
    'reason',case
      when v_customer.status<>'active' or v_customer.kind not in ('customer','both')
        then 'CUSTOMER_INACTIVE'
      when v_customer.credit_currency_code<>v_order.currency_code
        then 'CREDIT_CURRENCY_MISMATCH'
      when v_total>v_customer.credit_limit then 'CREDIT_LIMIT_EXCEEDED'
      else null end);
end;
$$;
revoke all on function api.get_sales_order_credit_preview(uuid,uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function api.get_sales_order_credit_preview(uuid,uuid,uuid,uuid)
  to authenticated;

create function api.update_sales_order_fulfillment(
  p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_command_id uuid, p_idempotency_key uuid, p_client_timestamp timestamptz,
  p_payload jsonb, p_expected_entity_version bigint default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := (select auth.uid());
  v_name constant text := 'sales.order.fulfillment.update';
  v_order sales.sales_orders%rowtype;
  v_hash text;
  v_replay jsonb;
  v_before jsonb;
  v_entity jsonb;
  v_request_id uuid := gen_random_uuid();
  v_context jsonb := coalesce(p_payload->'source_context','{}'::jsonb);
  v_promised date;
  v_warehouse uuid;
begin
  perform core.wave3_require_scope(
    p_tenant_id,'sales.orders.manage',p_legal_entity_id,p_branch_id);
  if p_branch_id is null or p_client_timestamp is null
    or jsonb_typeof(p_payload) is distinct from 'object'
    or jsonb_typeof(v_context) is distinct from 'object' then
    raise exception using errcode='22023',message='Invalid fulfillment command.';
  end if;
  if exists(select 1 from jsonb_object_keys(p_payload) as k(key)
    where key not in ('id','promised_date','warehouse_id','ship_to','source_context')) then
    raise exception using errcode='22023',message='FULFILLMENT_FIELDS_ONLY';
  end if;
  v_hash := core.wave3_request_hash(v_name,p_command_id,p_tenant_id,
    p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
  v_replay := core.wave3_replay(
    p_tenant_id,v_name,p_command_id,p_idempotency_key,v_hash);
  if v_replay is not null then return v_replay; end if;
  select * into v_order from sales.sales_orders
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and id=(p_payload->>'id')::uuid for update;
  if not found then
    raise exception using errcode='P0002',message='Sales order was not found.';
  end if;
  v_before := sales.order_entity(v_order.id);
  perform core.wave3_assert_expected_version(
    v_order.version,p_expected_entity_version,v_before);
  if v_order.status not in ('draft','credit_hold') then
    raise exception using errcode='55000',message='SALES_ORDER_NOT_EDITABLE';
  end if;
  v_promised := (p_payload->>'promised_date')::date;
  v_warehouse := (p_payload->>'warehouse_id')::uuid;
  if v_promised is null or v_promised<v_order.order_date
    or jsonb_typeof(p_payload->'ship_to') is distinct from 'object' then
    raise exception using errcode='22023',message='Invalid promised date or ship-to.';
  end if;
  if not exists(select 1 from core.warehouses w
    where w.tenant_id=p_tenant_id and w.legal_entity_id=p_legal_entity_id
      and w.branch_id=p_branch_id and w.id=v_warehouse and w.status='active') then
    raise exception using errcode='22023',message='Warehouse is outside scope or inactive.';
  end if;
  update sales.sales_orders set promised_date=v_promised,warehouse_id=v_warehouse,
    ship_to=p_payload->'ship_to',request_id=v_request_id,command_id=p_command_id,
    correlation_id=v_request_id,source_context=v_context,
    client_timestamp=p_client_timestamp,updated_by=v_actor where id=v_order.id;
  v_entity := sales.order_entity(v_order.id);
  return core.wave3_finish_command(
    p_tenant_id,v_name,p_command_id,'sales_order',v_order.id,p_idempotency_key,
    v_hash,v_before,v_entity,p_legal_entity_id,p_branch_id,v_context,null,
    jsonb_build_array(jsonb_build_object('topic',v_name,'payload','{}'::jsonb)),
    '[]'::jsonb,v_request_id,v_request_id);
end;
$$;
revoke all on function api.update_sales_order_fulfillment(
  uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.update_sales_order_fulfillment(
  uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

alter table sales.sales_order_lines add constraint sales_order_lines_unfulfilled_allocation_check
  check (allocated_quantity + delivered_quantity <= base_ordered_quantity - cancelled_quantity);

create or replace function api.transition_operational_document(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_command_id uuid,
  p_idempotency_key uuid,
  p_client_timestamp timestamptz,
  p_payload jsonb,
  p_expected_entity_version bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_document_type text := p_payload->>'document_type';
  v_command_name constant text := 'sales.document.transition';
  v_request_hash text;
  v_replay jsonb;
  v_id uuid;
  v_action text;
  v_order sales.sales_orders%rowtype;
  v_customer crm.parties%rowtype;
  v_before jsonb;
  v_entity jsonb;
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_credit sales.customer_credit_exposures%rowtype;
  v_due numeric(20, 6) := 0;
  v_overdue numeric(20, 6) := 0;
  v_existing_orders numeric(20, 6) := 0;
  v_total numeric(20, 6);
  v_decision text;
  v_to_status text;
  v_warnings jsonb := '[]'::jsonb;
  v_reservation inventory.stock_reservations%rowtype;
begin
  if v_document_type = 'sales_quotation' then
    return sales.transition_quotation(
      p_tenant_id, p_legal_entity_id, p_branch_id, p_command_id,
      p_idempotency_key, p_client_timestamp, p_payload,
      p_expected_entity_version
    );
  end if;
  if v_document_type <> 'sales_order' then
    raise exception using errcode = '22023', message = 'Unsupported operational document type.';
  end if;
  perform core.wave3_require_scope(
    p_tenant_id, 'sales.orders.manage', p_legal_entity_id, p_branch_id
  );
  if p_branch_id is null or p_client_timestamp is null
     or jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Transition scope is invalid.';
  end if;
  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id, p_payload, p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key, v_request_hash
  );
  if v_replay is not null then return v_replay; end if;
  v_id := (p_payload->>'document_id')::uuid;
  v_action := p_payload->>'action';
  select o.* into v_order
  from sales.sales_orders as o
  where o.tenant_id = p_tenant_id and o.legal_entity_id = p_legal_entity_id
    and o.branch_id = p_branch_id and o.id = v_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Sales order was not found.';
  end if;
  v_before := sales.order_entity(v_id);
  perform core.wave3_assert_expected_version(
    v_order.version, p_expected_entity_version, v_before
  );

  if v_action = 'confirm' then
    if v_order.status not in ('draft', 'credit_hold') then
      raise exception using errcode = '55000', message = 'SALES_ORDER_NOT_CONFIRMABLE';
    end if;
    select p.* into v_customer
    from crm.parties as p
    where p.tenant_id = p_tenant_id and p.id = v_order.customer_id
    for update;
    if not found or v_customer.status <> 'active'
       or v_customer.kind not in ('customer', 'both') then
      raise exception using errcode = '55000', message = 'CUSTOMER_INACTIVE';
    end if;
    if v_customer.credit_currency_code <> v_order.currency_code then
      raise exception using errcode = '55000', message = 'CREDIT_CURRENCY_MISMATCH';
    end if;
    select ce.* into v_credit
    from sales.customer_credit_exposures as ce
    where ce.tenant_id = p_tenant_id and ce.legal_entity_id = p_legal_entity_id
      and ce.branch_id = p_branch_id and ce.customer_id = v_order.customer_id
      and ce.currency_code = v_order.currency_code
    for update;
    if found then
      v_due := v_credit.due_exposure;
      v_overdue := v_credit.overdue_exposure;
    end if;
    select coalesce(sum(o.grand_total), 0)::numeric(20, 6)
      into v_existing_orders
    from sales.sales_orders as o
    where o.tenant_id = p_tenant_id and o.legal_entity_id = p_legal_entity_id
      and o.branch_id = p_branch_id and o.customer_id = v_order.customer_id
      and o.currency_code = v_order.currency_code and o.id <> v_order.id
      and o.status in ('confirmed', 'partially_reserved', 'reserved');
    v_total := v_due + v_existing_orders + v_order.grand_total;
    if v_total > v_customer.credit_limit then
      if coalesce((p_payload->>'override_credit')::boolean, false) then
        perform core.wave3_require_scope(
          p_tenant_id, 'sales.credit.override', p_legal_entity_id, p_branch_id
        );
        if length(trim(coalesce(p_payload->>'override_reason', ''))) not between 1 and 1000 then
          raise exception using errcode = '22023', message = 'Credit override reason is required.';
        end if;
        v_decision := 'overridden';
        v_to_status := 'confirmed';
      else
        v_decision := 'blocked';
        v_to_status := 'credit_hold';
        v_warnings := jsonb_build_array('CREDIT_LIMIT_EXCEEDED');
      end if;
    else
      v_decision := 'approved';
      v_to_status := 'confirmed';
    end if;
    if v_order.document_number is null then
      v_order.document_number := sales.wave3_reserve_document_number(
        p_tenant_id, p_legal_entity_id, p_branch_id,
        'sales_order', v_order.order_date, v_actor
      );
    end if;
    insert into sales.credit_decisions (
      tenant_id, legal_entity_id, branch_id, sales_order_id, customer_id,
      currency_code, credit_limit, due_exposure, overdue_exposure,
      existing_order_exposure, current_order_exposure, total_exposure,
      decision, override_applied, override_reason, override_by,
      request_id, command_id, correlation_id, source_context, created_by
    ) values (
      p_tenant_id, p_legal_entity_id, p_branch_id, v_order.id,
      v_order.customer_id, v_order.currency_code, v_customer.credit_limit,
      v_due, v_overdue, v_existing_orders, v_order.grand_total, v_total,
      v_decision, v_decision = 'overridden',
      case when v_decision = 'overridden' then trim(p_payload->>'override_reason') end,
      case when v_decision = 'overridden' then v_actor end,
      v_request_id, p_command_id, v_request_id, v_source_context, v_actor
    );
    update sales.sales_orders set
      document_number = v_order.document_number, status = v_to_status,
      confirmed_at = case when v_to_status = 'confirmed' then clock_timestamp() else confirmed_at end,
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
  elsif v_action = 'cancel' then
    if v_order.status not in (
      'draft', 'credit_hold', 'confirmed', 'partially_reserved', 'reserved'
    ) then
      raise exception using errcode = '55000', message = 'SALES_ORDER_NOT_CANCELLABLE';
    end if;
    if exists (
      select 1 from sales.sales_order_lines as l
      where l.sales_order_id = v_id
        and (l.delivered_quantity > 0 or l.invoiced_quantity > 0)
    ) then
      raise exception using errcode = '55000', message = 'FULFILLED_ORDER_NOT_CANCELLABLE';
    end if;
    for v_reservation in
      select r.* from inventory.stock_reservations as r
      where r.tenant_id = p_tenant_id and r.sales_order_id = v_id
        and r.status = 'active'
      order by r.product_id, r.id
      for update
    loop
      update inventory.stock_balances set
        allocated_quantity = allocated_quantity - v_reservation.base_quantity,
        updated_by = v_actor,
        source_context = v_source_context
      where tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
        and branch_id = p_branch_id
        and warehouse_id = v_reservation.warehouse_id
        and product_id = v_reservation.product_id;
      update sales.sales_order_lines set
        allocated_quantity = allocated_quantity - v_reservation.base_quantity,
        updated_by = v_actor, request_id = v_request_id,
        command_id = p_command_id, correlation_id = v_request_id,
        source_context = v_source_context
      where id = v_reservation.sales_order_line_id;
      update inventory.stock_reservations set
        status = 'released', released_at = clock_timestamp(),
        release_reason = coalesce(nullif(trim(p_payload->>'reason'), ''), 'Sales order cancelled.'),
        request_id = v_request_id, command_id = p_command_id,
        correlation_id = v_request_id, source_context = v_source_context,
        updated_by = v_actor
      where id = v_reservation.id;
    end loop;
    update sales.sales_order_lines set
      cancelled_quantity = base_ordered_quantity,
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      updated_by = v_actor
    where tenant_id = p_tenant_id and sales_order_id = v_id;
    v_to_status := 'cancelled';
    update sales.sales_orders set
      status = v_to_status, cancelled_at = clock_timestamp(),
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
  else
    raise exception using errcode = '22023', message = 'Sales-order action is invalid.';
  end if;
  v_entity := sales.order_entity(v_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_order', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    jsonb_build_object(
      'from_status', v_order.status, 'to_status', v_to_status,
      'owner_id', v_order.salesperson_id,
      'reason', coalesce(nullif(trim(p_payload->>'reason'), ''),
        nullif(trim(p_payload->>'override_reason'), ''))
    ),
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object('action', v_action, 'status', v_to_status)
    )), v_warnings, v_request_id, v_request_id
  );
end;
$$;

create or replace function api.reserve_sales_order_stock(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_command_id uuid,
  p_idempotency_key uuid,
  p_client_timestamp timestamptz,
  p_payload jsonb,
  p_expected_entity_version bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_command_name constant text := 'inventory.sales_order.reserve';
  v_request_hash text;
  v_replay jsonb;
  v_order_id uuid := (p_payload->>'sales_order_id')::uuid;
  v_order sales.sales_orders%rowtype;
  v_line sales.sales_order_lines%rowtype;
  v_balance inventory.stock_balances%rowtype;
  v_reservation inventory.stock_reservations%rowtype;
  v_item jsonb;
  v_ordinal integer;
  v_requested numeric(20, 6);
  v_remaining numeric(20, 6);
  v_available numeric(20, 6);
  v_allocate numeric(20, 6);
  v_shortfall boolean := false;
  v_before jsonb;
  v_entity jsonb;
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_to_status text;
  v_warnings jsonb := '[]'::jsonb;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'inventory.reservations.manage', p_legal_entity_id, p_branch_id
  );
  if p_branch_id is null or p_client_timestamp is null
     or jsonb_typeof(p_payload->'lines') <> 'array'
     or jsonb_array_length(p_payload->'lines') not between 1 and 500
     or (p_payload->>'expires_at')::timestamptz <= greatest(clock_timestamp(), p_client_timestamp)
     or jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Stock reservation payload is invalid.';
  end if;
  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id, p_payload, p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key, v_request_hash
  );
  if v_replay is not null then return v_replay; end if;
  select o.* into v_order
  from sales.sales_orders as o
  where o.tenant_id = p_tenant_id and o.legal_entity_id = p_legal_entity_id
    and o.branch_id = p_branch_id and o.id = v_order_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Sales order was not found.';
  end if;
  v_before := sales.order_entity(v_order_id);
  perform core.wave3_assert_expected_version(
    v_order.version, p_expected_entity_version, v_before
  );
  if v_order.status not in ('confirmed', 'partially_reserved', 'reserved') then
    raise exception using errcode = '55000', message = 'SALES_ORDER_NOT_RESERVABLE';
  end if;

  if not exists (
    select 1 from core.warehouses w
    where w.tenant_id = p_tenant_id and w.legal_entity_id = p_legal_entity_id
      and w.branch_id = p_branch_id and w.id = v_order.warehouse_id
      and w.status = 'active'
  ) then
    raise exception using errcode = '55000', message = 'WAREHOUSE_INACTIVE';
  end if;

  -- Deterministic product locks serialize competing reservations without
  -- creating an inventory movement or changing on-hand quantity.
  for v_line in
    select distinct on (l.product_id) l.*
    from jsonb_array_elements(p_payload->'lines') as item
    join sales.sales_order_lines as l
      on l.id = (item->>'sales_order_line_id')::uuid
    where l.tenant_id = p_tenant_id and l.sales_order_id = v_order_id
    order by l.product_id, l.id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_tenant_id::text || ':' || v_order.warehouse_id::text || ':' || v_line.product_id::text,
        0
      )
    );
  end loop;

  for v_item, v_ordinal in
    select value, ordinality::integer
    from jsonb_array_elements(p_payload->'lines') with ordinality
  loop
    select l.* into v_line
    from sales.sales_order_lines as l
    where l.tenant_id = p_tenant_id and l.sales_order_id = v_order_id
      and l.id = (v_item->>'sales_order_line_id')::uuid
    for update;
    if not found then
      raise exception using errcode = '22023', message = 'Sales-order line is outside scope.';
    end if;
    if v_line.product_kind <> 'stocked' then
      raise exception using errcode = '22023', message = 'Only stocked products can be reserved.';
    end if;
    if not exists (
      select 1 from inventory.products p
      where p.tenant_id = p_tenant_id and p.legal_entity_id = p_legal_entity_id
        and p.id = v_line.product_id and p.kind = 'stocked' and p.status = 'active'
    ) then
      raise exception using errcode = '55000', message = 'PRODUCT_NOT_RESERVABLE';
    end if;
    v_requested := sales.wave3_decimal_string(
      v_item->'requested_base_quantity', 'Requested base quantity', 6, true, 0, null
    )::numeric(20, 6);
    if v_requested <= 0 then
      raise exception using errcode = '22023', message = 'Requested quantity must be positive.';
    end if;
    select b.* into v_balance
    from inventory.stock_balances as b
    where b.tenant_id = p_tenant_id and b.legal_entity_id = p_legal_entity_id
      and b.branch_id = p_branch_id and b.warehouse_id = v_order.warehouse_id
      and b.product_id = v_line.product_id
    for update;
    v_remaining := greatest(
      v_line.base_ordered_quantity - v_line.cancelled_quantity
        - v_line.allocated_quantity - v_line.delivered_quantity,
      0
    )::numeric(20, 6);
    v_available := case when v_balance.id is null then 0
      else greatest(v_balance.available_quantity, 0) end::numeric(20, 6);
    v_allocate := least(v_requested, v_remaining, v_available)::numeric(20, 6);
    if v_allocate < v_requested then v_shortfall := true; end if;
    if v_allocate > 0 then
      select r.* into v_reservation
      from inventory.stock_reservations as r
      where r.tenant_id = p_tenant_id and r.warehouse_id = v_order.warehouse_id
        and r.sales_order_line_id = v_line.id and r.status = 'active'
      for update;
      if found then
        update inventory.stock_reservations set
          base_quantity = base_quantity + v_allocate,
          expires_at = greatest(expires_at, (p_payload->>'expires_at')::timestamptz),
          request_id = v_request_id, command_id = p_command_id,
          correlation_id = v_request_id, source_context = v_source_context,
          updated_by = v_actor
        where id = v_reservation.id;
      else
        insert into inventory.stock_reservations (
          id, tenant_id, legal_entity_id, branch_id, warehouse_id, product_id,
          sales_order_id, sales_order_line_id, base_quantity, status,
          expires_at, request_id, command_id, correlation_id, source_context,
          created_by, updated_by
        ) values (
          core.wave2_derived_uuid(p_command_id, v_ordinal),
          p_tenant_id, p_legal_entity_id, p_branch_id, v_order.warehouse_id,
          v_line.product_id, v_order_id, v_line.id, v_allocate, 'active',
          (p_payload->>'expires_at')::timestamptz,
          v_request_id, p_command_id, v_request_id, v_source_context,
          v_actor, v_actor
        );
      end if;
      update inventory.stock_balances set
        allocated_quantity = allocated_quantity + v_allocate,
        updated_by = v_actor, source_context = v_source_context
      where id = v_balance.id;
      update sales.sales_order_lines set
        allocated_quantity = allocated_quantity + v_allocate,
        request_id = v_request_id, command_id = p_command_id,
        correlation_id = v_request_id, source_context = v_source_context,
        updated_by = v_actor
      where id = v_line.id;
    end if;
  end loop;
  if exists (
    select 1 from sales.sales_order_lines as l
    where l.tenant_id = p_tenant_id and l.sales_order_id = v_order_id
      and l.product_kind = 'stocked'
      and l.base_ordered_quantity - l.cancelled_quantity - l.allocated_quantity - l.delivered_quantity > 0
  ) then
    v_to_status := 'partially_reserved';
  else
    v_to_status := 'reserved';
  end if;
  if v_shortfall then
    v_warnings := jsonb_build_array('PARTIAL_STOCK_RESERVATION');
  end if;
  update sales.sales_orders set
    status = v_to_status, request_id = v_request_id, command_id = p_command_id,
    correlation_id = v_request_id, source_context = v_source_context,
    client_timestamp = p_client_timestamp, updated_by = v_actor
  where id = v_order_id;
  v_entity := sales.order_entity(v_order_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_order', v_order_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    jsonb_build_object(
      'from_status', v_order.status, 'to_status', v_to_status,
      'owner_id', v_order.salesperson_id
    ),
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object('status', v_to_status)
    )), v_warnings, v_request_id, v_request_id
  );
end;
$$;

notify pgrst, 'reload schema';
