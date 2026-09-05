-- Wave 3 lead-to-cash foundation, part 4: quote-to-order conversion, direct
-- order drafts, auditable credit control, and bounded stock reservations.

create function sales.order_entity(p_sales_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(o) || jsonb_build_object(
    'lines', coalesce((
      select jsonb_agg(to_jsonb(l) order by l.line_number, l.id)
      from api.sales_order_lines as l
      where l.sales_order_id = o.id
    ), '[]'::jsonb)
  )
  from api.sales_orders as o
  where o.id = p_sales_order_id;
$$;

create function api.upsert_sales_order(
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
  v_command_name constant text := 'sales.order.upsert';
  v_request_hash text;
  v_replay jsonb;
  v_id uuid;
  v_existing sales.sales_orders%rowtype;
  v_before jsonb;
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_base_currency text;
  v_currency text;
  v_exchange_rate numeric(20, 10);
  v_exchange_rate_id uuid;
  v_order_date date;
  v_promised_date date;
  v_rate_date date;
  v_pricing jsonb;
  v_line jsonb;
  v_product_kind text;
  v_ordinal integer;
  v_entity jsonb;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'sales.orders.manage', p_legal_entity_id, p_branch_id
  );
  if p_branch_id is null or p_client_timestamp is null
     or jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(coalesce(p_payload->'ship_to', '{}'::jsonb)) <> 'object'
     or jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Sales-order command scope or payload is invalid.';
  end if;
  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id, p_payload, p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key, v_request_hash
  );
  if v_replay is not null then return v_replay; end if;
  v_id := coalesce(nullif(p_payload->>'id', '')::uuid, gen_random_uuid());
  select o.* into v_existing
  from sales.sales_orders as o
  where o.tenant_id = p_tenant_id and o.legal_entity_id = p_legal_entity_id
    and o.branch_id = p_branch_id and o.id = v_id
  for update;
  if found then
    v_before := sales.order_entity(v_id);
    perform core.wave3_assert_expected_version(
      v_existing.version, p_expected_entity_version, v_before
    );
    if v_existing.source_quotation_id is not null then
      raise exception using errcode = '55000', message = 'CONVERTED_ORDER_SOURCE_IMMUTABLE';
    end if;
    if v_existing.status not in ('draft', 'credit_hold') then
      raise exception using errcode = '55000', message = 'SALES_ORDER_NOT_EDITABLE';
    end if;
  else
    if p_expected_entity_version is not null then
      raise exception using errcode = '40001', message = 'VERSION_CONFLICT';
    end if;
    v_before := null;
  end if;

  select le.currency_code into v_base_currency
  from core.legal_entities as le
  where le.tenant_id = p_tenant_id and le.id = p_legal_entity_id;
  v_currency := p_payload->>'currency_code';
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Currency code is invalid.';
  end if;
  v_exchange_rate := sales.wave3_decimal_string(
    p_payload->'exchange_rate', 'Exchange rate', 10, true, 0, null
  )::numeric(20, 10);
  if v_exchange_rate <= 0 then
    raise exception using errcode = '22023', message = 'Exchange rate must be positive.';
  end if;
  v_exchange_rate_id := nullif(p_payload->>'exchange_rate_id', '')::uuid;
  v_order_date := (p_payload->>'order_date')::date;
  v_promised_date := (p_payload->>'promised_date')::date;
  v_rate_date := (p_payload->>'rate_date')::date;
  if v_promised_date < v_order_date then
    raise exception using errcode = '22023', message = 'Promised date precedes order date.';
  end if;
  if v_currency = v_base_currency then
    if v_exchange_rate <> 1 then
      raise exception using errcode = '22023', message = 'Base-currency exchange rate must be one.';
    end if;
    v_exchange_rate_id := null;
  elsif v_exchange_rate_id is null or not exists (
    select 1 from finance.exchange_rates as er
    where er.tenant_id = p_tenant_id and er.legal_entity_id = p_legal_entity_id
      and er.id = v_exchange_rate_id and er.status = 'active'
      and er.source_currency_code = v_currency
      and er.target_currency_code = v_base_currency
      and er.effective_date = v_rate_date and er.rate = v_exchange_rate
  ) then
    raise exception using errcode = '22023', message = 'Exchange-rate snapshot does not match governed setup.';
  end if;
  if not exists (
    select 1 from crm.parties as p
    where p.tenant_id = p_tenant_id
      and p.id = (p_payload->>'customer_id')::uuid
      and p.kind in ('customer', 'both') and p.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'Customer is outside scope or inactive.';
  end if;
  if nullif(p_payload->>'contact_id', '') is not null and not exists (
    select 1 from crm.contacts as c
    where c.tenant_id = p_tenant_id and c.id = (p_payload->>'contact_id')::uuid
      and c.party_id = (p_payload->>'customer_id')::uuid and c.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'Contact does not belong to the customer.';
  end if;
  if not exists (
    select 1 from core.warehouses as w
    where w.tenant_id = p_tenant_id and w.legal_entity_id = p_legal_entity_id
      and w.branch_id = p_branch_id and w.id = (p_payload->>'warehouse_id')::uuid
      and w.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'Warehouse is outside scope or inactive.';
  end if;
  v_pricing := sales.wave3_price_lines(
    p_tenant_id, p_legal_entity_id, v_order_date, v_currency,
    p_payload->'lines', p_payload->'header_discount_amount',
    p_payload->'header_discount_percent'
  );

  if v_existing.id is null then
    insert into sales.sales_orders (
      id, tenant_id, legal_entity_id, branch_id, customer_id, contact_id,
      order_date, promised_date, ship_to, warehouse_id, currency_code,
      base_currency_code, exchange_rate_id, exchange_rate, rate_date,
      payment_terms_days, delivery_terms, salesperson_id,
      header_discount_amount, header_discount_percent, subtotal,
      line_discount_total, header_discount_total, discount_total, tax_total,
      grand_total, base_total, notes, status, request_id, command_id,
      correlation_id, source_context, client_timestamp, created_by, updated_by
    ) values (
      v_id, p_tenant_id, p_legal_entity_id, p_branch_id,
      (p_payload->>'customer_id')::uuid,
      nullif(p_payload->>'contact_id', '')::uuid,
      v_order_date, v_promised_date, coalesce(p_payload->'ship_to', '{}'::jsonb),
      (p_payload->>'warehouse_id')::uuid, v_currency, v_base_currency,
      v_exchange_rate_id, v_exchange_rate, v_rate_date,
      coalesce((p_payload->>'payment_terms_days')::integer, 0),
      nullif(trim(p_payload->>'delivery_terms'), ''), v_actor,
      coalesce((p_payload->>'header_discount_amount')::numeric, 0),
      (p_payload->>'header_discount_percent')::numeric,
      (v_pricing->>'subtotal')::numeric,
      (v_pricing->>'line_discount_total')::numeric,
      (v_pricing->>'header_discount_total')::numeric,
      (v_pricing->>'discount_total')::numeric,
      (v_pricing->>'tax_total')::numeric,
      (v_pricing->>'grand_total')::numeric,
      round((v_pricing->>'grand_total')::numeric * v_exchange_rate,
        (select rounding_scale from core.legal_entities where id = p_legal_entity_id)),
      nullif(trim(p_payload->>'notes'), ''), 'draft', v_request_id,
      p_command_id, v_request_id, v_source_context, p_client_timestamp,
      v_actor, v_actor
    );
  else
    delete from sales.sales_order_lines
    where tenant_id = p_tenant_id and sales_order_id = v_id;
    update sales.sales_orders set
      customer_id = (p_payload->>'customer_id')::uuid,
      contact_id = nullif(p_payload->>'contact_id', '')::uuid,
      order_date = v_order_date, promised_date = v_promised_date,
      ship_to = coalesce(p_payload->'ship_to', '{}'::jsonb),
      warehouse_id = (p_payload->>'warehouse_id')::uuid,
      currency_code = v_currency, base_currency_code = v_base_currency,
      exchange_rate_id = v_exchange_rate_id, exchange_rate = v_exchange_rate,
      rate_date = v_rate_date,
      payment_terms_days = coalesce((p_payload->>'payment_terms_days')::integer, 0),
      delivery_terms = nullif(trim(p_payload->>'delivery_terms'), ''),
      header_discount_amount = coalesce((p_payload->>'header_discount_amount')::numeric, 0),
      header_discount_percent = (p_payload->>'header_discount_percent')::numeric,
      subtotal = (v_pricing->>'subtotal')::numeric,
      line_discount_total = (v_pricing->>'line_discount_total')::numeric,
      header_discount_total = (v_pricing->>'header_discount_total')::numeric,
      discount_total = (v_pricing->>'discount_total')::numeric,
      tax_total = (v_pricing->>'tax_total')::numeric,
      grand_total = (v_pricing->>'grand_total')::numeric,
      base_total = round((v_pricing->>'grand_total')::numeric * v_exchange_rate,
        (select rounding_scale from core.legal_entities where id = p_legal_entity_id)),
      notes = nullif(trim(p_payload->>'notes'), ''), status = 'draft',
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
  end if;

  for v_line, v_ordinal in
    select value, ordinality::integer
    from jsonb_array_elements(v_pricing->'lines') with ordinality
  loop
    select p.kind into v_product_kind
    from inventory.products as p
    where p.tenant_id = p_tenant_id and p.legal_entity_id = p_legal_entity_id
      and p.id = (v_line->>'product_id')::uuid;
    insert into sales.sales_order_lines (
      id, tenant_id, legal_entity_id, branch_id, sales_order_id, line_number,
      product_id, product_kind, description, unit_id, conversion_numerator,
      conversion_denominator, ordered_quantity, base_ordered_quantity,
      unit_price, gross_amount, line_discount_amount, discount_percent,
      header_discount_amount, net_amount, tax_definition_id, tax_code,
      tax_name, tax_kind, tax_rate, tax_inclusive, tax_definition_version,
      taxable_amount, tax_amount, line_total, currency_code,
      request_id, command_id, correlation_id, source_context,
      created_by, updated_by
    ) values (
      coalesce(nullif(v_line->>'line_id', '')::uuid,
        core.wave2_derived_uuid(p_command_id, v_ordinal)),
      p_tenant_id, p_legal_entity_id, p_branch_id, v_id, v_ordinal,
      (v_line->>'product_id')::uuid, v_product_kind, v_line->>'description',
      (v_line->>'unit_id')::uuid,
      (v_line->>'conversion_numerator')::bigint,
      (v_line->>'conversion_denominator')::bigint,
      (v_line->>'quantity')::numeric, (v_line->>'base_quantity')::numeric,
      (v_line->>'unit_price')::numeric, (v_line->>'gross_amount')::numeric,
      (v_line->>'line_discount_amount')::numeric,
      (v_line->>'discount_percent')::numeric,
      (v_line->>'header_discount_amount')::numeric,
      (v_line->>'net_amount')::numeric,
      nullif(v_line->>'tax_definition_id', '')::uuid,
      nullif(v_line->>'tax_code', ''), nullif(v_line->>'tax_name', ''),
      nullif(v_line->>'tax_kind', ''), (v_line->>'tax_rate')::numeric,
      (v_line->>'tax_inclusive')::boolean,
      (v_line->>'tax_definition_version')::bigint,
      (v_line->>'taxable_amount')::numeric, (v_line->>'tax_amount')::numeric,
      (v_line->>'line_total')::numeric, v_currency,
      v_request_id, p_command_id, v_request_id, v_source_context,
      v_actor, v_actor
    );
  end loop;
  v_entity := sales.order_entity(v_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_order', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    case when v_existing.id is null then jsonb_build_object(
      'to_status', 'draft', 'owner_id', v_actor
    ) else null end,
    jsonb_build_array(jsonb_build_object('topic', v_command_name, 'payload', '{}'::jsonb)),
    '[]'::jsonb, v_request_id, v_request_id
  );
end;
$$;

create function api.convert_quotation_to_order(
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
  v_command_name constant text := 'sales.quotation.convert';
  v_request_hash text;
  v_replay jsonb;
  v_quote_id uuid := (p_payload->>'quotation_id')::uuid;
  v_revision integer := (p_payload->>'quotation_revision')::integer;
  v_quote sales.quotations%rowtype;
  v_existing_order sales.sales_orders%rowtype;
  v_order_id uuid := gen_random_uuid();
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_before jsonb;
  v_entity jsonb;
  v_line sales.quotation_lines%rowtype;
  v_product_kind text;
  v_promised_date date := (p_payload->>'promised_date')::date;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'sales.orders.manage', p_legal_entity_id, p_branch_id
  );
  if p_branch_id is null or p_client_timestamp is null or v_revision < 1
     or jsonb_typeof(coalesce(p_payload->'ship_to', '{}'::jsonb)) <> 'object'
     or jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Quotation conversion payload is invalid.';
  end if;
  v_request_hash := core.wave3_request_hash(
    v_command_name, p_command_id, p_tenant_id, p_legal_entity_id,
    p_branch_id, p_payload, p_expected_entity_version
  );
  v_replay := core.wave3_replay(
    p_tenant_id, v_command_name, p_command_id, p_idempotency_key, v_request_hash
  );
  if v_replay is not null then return v_replay; end if;
  select q.* into v_quote
  from sales.quotations as q
  where q.tenant_id = p_tenant_id and q.legal_entity_id = p_legal_entity_id
    and q.branch_id = p_branch_id and q.id = v_quote_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Quotation was not found.';
  end if;
  select o.* into v_existing_order
  from sales.sales_orders as o
  where o.tenant_id = p_tenant_id and o.source_quotation_id = v_quote_id
    and o.source_quotation_revision = v_revision;
  if found then
    v_entity := sales.order_entity(v_existing_order.id);
    return core.wave3_finish_command(
      p_tenant_id, v_command_name, p_command_id, 'sales_order',
      v_existing_order.id, p_idempotency_key, v_request_hash,
      v_entity, v_entity, p_legal_entity_id, p_branch_id, v_source_context,
      null, jsonb_build_array(jsonb_build_object(
        'topic', 'sales.quotation.conversion_replayed',
        'payload', jsonb_build_object('quotation_id', v_quote_id, 'revision', v_revision)
      )), '[]'::jsonb, v_request_id, v_request_id
    );
  end if;
  v_before := sales.quotation_entity(v_quote_id);
  perform core.wave3_assert_expected_version(
    v_quote.version, p_expected_entity_version, v_before
  );
  if v_quote.status <> 'accepted' or v_quote.current_revision <> v_revision then
    raise exception using errcode = '55000', message = 'QUOTATION_NOT_CONVERTIBLE';
  end if;
  if v_quote.valid_until < greatest(
    current_date, (p_client_timestamp at time zone 'UTC')::date
  ) then
    raise exception using errcode = '55000', message = 'QUOTATION_EXPIRED';
  end if;
  if v_promised_date < (p_client_timestamp at time zone 'UTC')::date then
    raise exception using errcode = '22023', message = 'Promised date precedes order date.';
  end if;
  if not exists (
    select 1 from sales.quotation_revisions as qr
    where qr.tenant_id = p_tenant_id and qr.quotation_id = v_quote_id
      and qr.revision_number = v_revision
  ) then
    raise exception using errcode = '55000', message = 'QUOTATION_REVISION_NOT_SUBMITTED';
  end if;
  if not exists (
    select 1 from core.warehouses as w
    where w.tenant_id = p_tenant_id and w.legal_entity_id = p_legal_entity_id
      and w.branch_id = p_branch_id and w.id = (p_payload->>'warehouse_id')::uuid
      and w.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'Warehouse is outside scope or inactive.';
  end if;

  insert into sales.sales_orders (
    id, tenant_id, legal_entity_id, branch_id, source_quotation_id,
    source_quotation_revision, source_snapshot, customer_id, contact_id,
    order_date, promised_date, ship_to, warehouse_id, currency_code,
    base_currency_code, exchange_rate_id, exchange_rate, rate_date,
    payment_terms_days, delivery_terms, salesperson_id,
    header_discount_amount, header_discount_percent, subtotal,
    line_discount_total, header_discount_total, discount_total, tax_total,
    grand_total, base_total, notes, status, request_id, command_id,
    correlation_id, source_context, client_timestamp, created_by, updated_by
  ) values (
    v_order_id, p_tenant_id, p_legal_entity_id, p_branch_id, v_quote_id,
    v_revision, (select snapshot from sales.quotation_revisions
      where tenant_id = p_tenant_id and quotation_id = v_quote_id
        and revision_number = v_revision),
    v_quote.customer_id, v_quote.contact_id,
    (p_client_timestamp at time zone 'UTC')::date, v_promised_date,
    coalesce(p_payload->'ship_to', '{}'::jsonb),
    (p_payload->>'warehouse_id')::uuid, v_quote.currency_code,
    v_quote.base_currency_code, v_quote.exchange_rate_id, v_quote.exchange_rate,
    v_quote.rate_date, v_quote.payment_terms_days, v_quote.delivery_terms,
    v_quote.salesperson_id, v_quote.header_discount_amount,
    v_quote.header_discount_percent, v_quote.subtotal,
    v_quote.line_discount_total, v_quote.header_discount_total,
    v_quote.discount_total, v_quote.tax_total, v_quote.grand_total,
    v_quote.base_total, v_quote.notes, 'draft', v_request_id, p_command_id,
    v_request_id, v_source_context, p_client_timestamp, v_actor, v_actor
  );
  for v_line in
    select l.* from sales.quotation_lines as l
    where l.tenant_id = p_tenant_id and l.quotation_id = v_quote_id
      and l.revision_number = v_revision
    order by l.line_number, l.id
  loop
    select p.kind into v_product_kind
    from inventory.products as p
    where p.tenant_id = p_tenant_id and p.legal_entity_id = p_legal_entity_id
      and p.id = v_line.product_id;
    insert into sales.sales_order_lines (
      id, tenant_id, legal_entity_id, branch_id, sales_order_id, line_number,
      source_quotation_id, source_quotation_line_id, source_quotation_revision,
      product_id, product_kind, description, unit_id, conversion_numerator,
      conversion_denominator, ordered_quantity, base_ordered_quantity,
      unit_price, gross_amount, line_discount_amount, discount_percent,
      header_discount_amount, net_amount, tax_definition_id, tax_code,
      tax_name, tax_kind, tax_rate, tax_inclusive, tax_definition_version,
      taxable_amount, tax_amount, line_total, currency_code,
      request_id, command_id, correlation_id, source_context,
      created_by, updated_by
    ) values (
      gen_random_uuid(), p_tenant_id, p_legal_entity_id, p_branch_id,
      v_order_id, v_line.line_number, v_quote_id, v_line.id, v_revision,
      v_line.product_id, v_product_kind, v_line.description, v_line.unit_id,
      v_line.conversion_numerator, v_line.conversion_denominator,
      v_line.quantity, v_line.base_quantity, v_line.unit_price,
      v_line.gross_amount, v_line.line_discount_amount, v_line.discount_percent,
      v_line.header_discount_amount, v_line.net_amount,
      v_line.tax_definition_id, v_line.tax_code, v_line.tax_name,
      v_line.tax_kind, v_line.tax_rate, v_line.tax_inclusive,
      v_line.tax_definition_version, v_line.taxable_amount, v_line.tax_amount,
      v_line.line_total, v_line.currency_code, v_request_id, p_command_id,
      v_request_id, v_source_context, v_actor, v_actor
    );
  end loop;
  update sales.quotations set
    status = 'converted', request_id = v_request_id, command_id = p_command_id,
    correlation_id = v_request_id, source_context = v_source_context,
    client_timestamp = p_client_timestamp, updated_by = v_actor
  where id = v_quote_id;
  v_entity := sales.order_entity(v_order_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_order', v_order_id,
    p_idempotency_key, v_request_hash, null, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    jsonb_build_object('to_status', 'draft', 'owner_id', v_quote.salesperson_id),
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object('quotation_id', v_quote_id, 'revision', v_revision)
    )), '[]'::jsonb, v_request_id, v_request_id
  );
end;
$$;

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

create function api.reserve_sales_order_stock(
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
        - v_line.allocated_quantity,
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
      and l.base_ordered_quantity - l.cancelled_quantity - l.allocated_quantity > 0
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

revoke all on function sales.order_entity(uuid)
  from public, anon, authenticated;
revoke all on function api.upsert_sales_order(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.convert_quotation_to_order(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.transition_operational_document(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.reserve_sales_order_stock(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
grant execute on function api.upsert_sales_order(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.convert_quotation_to_order(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.transition_operational_document(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.reserve_sales_order_stock(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;

comment on function api.convert_quotation_to_order(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) is 'Idempotently converts one accepted quotation revision into one traced order.';
comment on function api.reserve_sales_order_stock(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) is 'Allocates available stock without inventory movement or accounting effects.';

notify pgrst, 'reload schema';
