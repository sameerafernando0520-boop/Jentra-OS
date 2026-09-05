-- Wave 3 lead-to-cash foundation, part 2: exact quotation pricing and
-- idempotent draft, revision, submission, acceptance, and approval commands.

create function sales.wave3_decimal_string(
  p_value jsonb,
  p_field text,
  p_scale integer,
  p_required boolean default true,
  p_min numeric default null,
  p_max numeric default null
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text;
  v_value numeric;
begin
  if p_value is null or p_value = 'null'::jsonb then
    if p_required then
      raise exception using errcode = '22023', message = p_field || ' is required.';
    end if;
    return null;
  end if;
  if jsonb_typeof(p_value) <> 'string' then
    raise exception using
      errcode = '22023', message = p_field || ' must be a decimal string.';
  end if;
  v_text := p_value #>> '{}';
  if p_scale < 0 or p_scale > 18
     or v_text !~ pg_catalog.format('^[0-9]+([.][0-9]{1,%s})?$', p_scale) then
    raise exception using
      errcode = '22023',
      message = p_field || ' must be a non-negative decimal string with at most '
        || p_scale::text || ' fractional digits.';
  end if;
  v_value := v_text::numeric;
  if p_min is not null and v_value < p_min then
    raise exception using errcode = '22023', message = p_field || ' is below its minimum.';
  end if;
  if p_max is not null and v_value > p_max then
    raise exception using errcode = '22023', message = p_field || ' exceeds its maximum.';
  end if;
  return v_value;
end;
$$;

create function sales.wave3_positive_bigint(p_value jsonb, p_field text)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text;
  v_value bigint;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'string' then
    raise exception using errcode = '22023', message = p_field || ' must be an integer string.';
  end if;
  v_text := p_value #>> '{}';
  if v_text !~ '^[1-9][0-9]*$' then
    raise exception using errcode = '22023', message = p_field || ' must be positive.';
  end if;
  v_value := v_text::bigint;
  return v_value;
exception
  when numeric_value_out_of_range then
    raise exception using errcode = '22023', message = p_field || ' is out of range.';
end;
$$;

create function sales.wave3_price_lines(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_document_date date,
  p_currency_code text,
  p_lines jsonb,
  p_header_discount_amount jsonb default null,
  p_header_discount_percent jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rounding_scale integer;
  v_line jsonb;
  v_ordinal integer;
  v_count integer;
  v_product inventory.products%rowtype;
  v_tax finance.tax_definitions%rowtype;
  v_quantity numeric(20, 6);
  v_base_quantity numeric(20, 6);
  v_numerator bigint;
  v_denominator bigint;
  v_unit_price numeric(20, 6);
  v_gross numeric(20, 6);
  v_line_discount numeric(20, 6);
  v_discount_percent numeric(12, 6);
  v_basis numeric(20, 6);
  v_basis_total numeric(20, 6) := 0;
  v_subtotal numeric(20, 6) := 0;
  v_line_discount_total numeric(20, 6) := 0;
  v_header_amount numeric(20, 6);
  v_header_percent numeric(12, 6);
  v_header_total numeric(20, 6) := 0;
  v_header_allocation numeric(20, 6);
  v_allocated numeric(20, 6) := 0;
  v_discounted_basis numeric(20, 6);
  v_tax_amount numeric(20, 6);
  v_net_amount numeric(20, 6);
  v_line_total numeric(20, 6);
  v_tax_total numeric(20, 6) := 0;
  v_grand_total numeric(20, 6) := 0;
  v_prepared jsonb := '[]'::jsonb;
  v_priced jsonb := '[]'::jsonb;
begin
  if p_document_date is null then
    raise exception using errcode = '22023', message = 'Document date is required.';
  end if;
  if p_currency_code !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Currency code is invalid.';
  end if;
  if jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'One to five hundred lines are required.';
  end if;
  select le.rounding_scale into v_rounding_scale
  from core.legal_entities as le
  where le.tenant_id = p_tenant_id and le.id = p_legal_entity_id
    and le.status = 'active';
  if not found then
    raise exception using errcode = '42501', message = 'LEGAL_ENTITY_SCOPE_INVALID';
  end if;

  for v_line, v_ordinal in
    select value, ordinality::integer
    from jsonb_array_elements(p_lines) with ordinality
  loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception using errcode = '22023', message = 'Each commercial line must be an object.';
    end if;
    if length(trim(coalesce(v_line->>'description', ''))) not between 1 and 1000 then
      raise exception using errcode = '22023', message = 'Line description is required.';
    end if;
    if nullif(v_line->>'product_id', '') is null then
      raise exception using errcode = '22023', message = 'Product is required.';
    end if;
    select p.* into v_product
    from inventory.products as p
    where p.tenant_id = p_tenant_id
      and p.legal_entity_id = p_legal_entity_id
      and p.id = (v_line->>'product_id')::uuid
      and p.status = 'active' and p.can_sell;
    if not found then
      raise exception using errcode = '22023', message = 'Product is outside scope or cannot be sold.';
    end if;
    if not exists (
      select 1 from inventory.units as u
      where u.tenant_id = p_tenant_id and u.id = (v_line->>'unit_id')::uuid
        and u.status = 'active'
    ) then
      raise exception using errcode = '22023', message = 'Unit is outside scope or inactive.';
    end if;

    v_quantity := sales.wave3_decimal_string(
      v_line->'quantity', 'Quantity', 6, true, 0, null
    )::numeric(20, 6);
    v_base_quantity := sales.wave3_decimal_string(
      v_line->'base_quantity', 'Base quantity', 6, true, 0, null
    )::numeric(20, 6);
    if v_quantity <= 0 or v_base_quantity <= 0 then
      raise exception using errcode = '22023', message = 'Quantities must be positive.';
    end if;
    v_numerator := sales.wave3_positive_bigint(
      v_line->'conversion_numerator', 'Conversion numerator'
    );
    v_denominator := sales.wave3_positive_bigint(
      v_line->'conversion_denominator', 'Conversion denominator'
    );
    if v_base_quantity * v_denominator <> v_quantity * v_numerator then
      raise exception using errcode = '22023', message = 'Base quantity does not match unit conversion.';
    end if;
    v_unit_price := sales.wave3_decimal_string(
      v_line->'unit_price', 'Unit price', 6, true, 0, null
    )::numeric(20, 6);
    v_gross := round(v_quantity * v_unit_price, v_rounding_scale)::numeric(20, 6);

    if v_line ? 'discount_amount' and v_line ? 'discount_percent' then
      raise exception using errcode = '22023', message = 'Choose one line discount type.';
    end if;
    v_discount_percent := null;
    if v_line ? 'discount_amount' then
      v_line_discount := round(sales.wave3_decimal_string(
        v_line->'discount_amount', 'Line discount amount', 6, true, 0, null
      ), v_rounding_scale)::numeric(20, 6);
    elsif v_line ? 'discount_percent' then
      v_discount_percent := sales.wave3_decimal_string(
        v_line->'discount_percent', 'Line discount percent', 6, true, 0, 100
      )::numeric(12, 6);
      v_line_discount := round(
        v_gross * v_discount_percent / 100, v_rounding_scale
      )::numeric(20, 6);
    else
      v_line_discount := 0;
    end if;
    if v_line_discount > v_gross then
      raise exception using errcode = '22023', message = 'Line discount exceeds gross amount.';
    end if;
    v_basis := v_gross - v_line_discount;

    v_tax := null;
    if nullif(v_line->>'tax_definition_id', '') is not null then
      select td.* into v_tax
      from finance.tax_definitions as td
      where td.tenant_id = p_tenant_id
        and td.legal_entity_id = p_legal_entity_id
        and td.id = (v_line->>'tax_definition_id')::uuid
        and td.status = 'active'
        and td.kind in ('output', 'zero', 'exempt')
        and p_document_date >= td.valid_from
        and (td.valid_to is null or p_document_date <= td.valid_to);
      if not found then
        raise exception using errcode = '22023', message = 'Tax definition is outside scope or date.';
      end if;
    end if;

    v_prepared := v_prepared || jsonb_build_array(jsonb_build_object(
      'line_id', nullif(v_line->>'line_id', ''),
      'product_id', v_product.id,
      'description', trim(v_line->>'description'),
      'unit_id', (v_line->>'unit_id')::uuid,
      'quantity', v_quantity::text,
      'base_quantity', v_base_quantity::text,
      'conversion_numerator', v_numerator::text,
      'conversion_denominator', v_denominator::text,
      'unit_price', v_unit_price::text,
      'gross_amount', v_gross::text,
      'line_discount_amount', v_line_discount::text,
      'discount_percent', case when v_discount_percent is null then null else v_discount_percent::text end,
      '_basis', v_basis,
      'tax_definition_id', v_tax.id,
      'tax_code', v_tax.code,
      'tax_name', v_tax.name,
      'tax_kind', v_tax.kind,
      'tax_rate', coalesce(v_tax.rate, 0)::numeric(12, 6)::text,
      'tax_inclusive', coalesce(v_tax.inclusive, false),
      'tax_definition_version', v_tax.version
    ));
    v_subtotal := v_subtotal + v_gross;
    v_line_discount_total := v_line_discount_total + v_line_discount;
    v_basis_total := v_basis_total + v_basis;
  end loop;

  if p_header_discount_amount is not null
     and p_header_discount_amount <> 'null'::jsonb
     and p_header_discount_percent is not null
     and p_header_discount_percent <> 'null'::jsonb then
    raise exception using errcode = '22023', message = 'Choose one header discount type.';
  end if;
  v_header_amount := sales.wave3_decimal_string(
    p_header_discount_amount, 'Header discount amount', 6, false, 0, null
  )::numeric(20, 6);
  v_header_percent := sales.wave3_decimal_string(
    p_header_discount_percent, 'Header discount percent', 6, false, 0, 100
  )::numeric(12, 6);
  if v_header_amount is not null then
    v_header_total := round(v_header_amount, v_rounding_scale)::numeric(20, 6);
  elsif v_header_percent is not null then
    v_header_total := round(
      v_basis_total * v_header_percent / 100, v_rounding_scale
    )::numeric(20, 6);
  end if;
  if v_header_total > v_basis_total then
    raise exception using errcode = '22023', message = 'Header discount exceeds line basis.';
  end if;

  v_count := jsonb_array_length(v_prepared);
  for v_line, v_ordinal in
    select value, ordinality::integer
    from jsonb_array_elements(v_prepared) with ordinality
  loop
    v_basis := (v_line->>'_basis')::numeric(20, 6);
    v_header_allocation := case
      when v_header_total = 0 then 0
      when v_ordinal = v_count then v_header_total - v_allocated
      else round(v_header_total * v_basis / nullif(v_basis_total, 0), v_rounding_scale)
    end::numeric(20, 6);
    v_allocated := v_allocated + v_header_allocation;
    v_discounted_basis := v_basis - v_header_allocation;
    if (v_line->>'tax_inclusive')::boolean then
      v_tax_amount := round(
        v_discounted_basis * (v_line->>'tax_rate')::numeric
          / (100 + (v_line->>'tax_rate')::numeric),
        v_rounding_scale
      )::numeric(20, 6);
      v_net_amount := v_discounted_basis - v_tax_amount;
      v_line_total := v_discounted_basis;
    else
      v_tax_amount := round(
        v_discounted_basis * (v_line->>'tax_rate')::numeric / 100,
        v_rounding_scale
      )::numeric(20, 6);
      v_net_amount := v_discounted_basis;
      v_line_total := v_discounted_basis + v_tax_amount;
    end if;
    v_tax_total := v_tax_total + v_tax_amount;
    v_grand_total := v_grand_total + v_line_total;
    v_priced := v_priced || jsonb_build_array(
      (v_line - '_basis') || jsonb_build_object(
        'header_discount_amount', v_header_allocation::text,
        'taxable_amount', v_net_amount::text,
        'net_amount', v_net_amount::text,
        'tax_amount', v_tax_amount::text,
        'line_total', v_line_total::text
      )
    );
  end loop;

  return jsonb_build_object(
    'lines', v_priced,
    'subtotal', v_subtotal::text,
    'line_discount_total', v_line_discount_total::text,
    'header_discount_total', v_header_total::text,
    'discount_total', (v_line_discount_total + v_header_total)::numeric(20, 6)::text,
    'tax_total', v_tax_total::text,
    'grand_total', v_grand_total::text
  );
end;
$$;

create function sales.wave3_reserve_document_number(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_document_type text,
  p_document_date date,
  p_actor uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sequence core.document_sequences%rowtype;
  v_reset_key text;
  v_value bigint;
  v_number text;
begin
  select ds.* into v_sequence
  from core.document_sequences as ds
  where ds.tenant_id = p_tenant_id
    and ds.legal_entity_id = p_legal_entity_id
    and ds.branch_id = p_branch_id
    and ds.document_type = p_document_type
    and ds.status = 'active'
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'DOCUMENT_SEQUENCE_NOT_CONFIGURED';
  end if;
  v_reset_key := case v_sequence.reset_policy
    when 'yearly' then to_char(p_document_date, 'YYYY')
    when 'monthly' then to_char(p_document_date, 'YYYY-MM')
    else null
  end;
  v_value := case
    when v_reset_key is not null
      and v_sequence.last_reset_key is distinct from v_reset_key then 1
    else v_sequence.next_value
  end;
  v_number := v_sequence.prefix || lpad(v_value::text, v_sequence.padding, '0')
    || v_sequence.suffix;
  update core.document_sequences set
    next_value = v_value + 1,
    last_reset_key = v_reset_key,
    updated_by = p_actor
  where id = v_sequence.id;
  return v_number;
end;
$$;

create function sales.quotation_entity(p_quotation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(q) || jsonb_build_object(
    'lines', coalesce((
      select jsonb_agg(to_jsonb(l) order by l.line_number, l.id)
      from api.sales_quotation_lines as l
      where l.quotation_id = q.id and l.revision_number = q.current_revision
    ), '[]'::jsonb)
  )
  from api.sales_quotations as q
  where q.id = p_quotation_id;
$$;

create function api.upsert_sales_quotation(
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
  v_command_name constant text := 'sales.quotation.upsert';
  v_request_hash text;
  v_replay jsonb;
  v_id uuid;
  v_existing sales.quotations%rowtype;
  v_before jsonb;
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_base_currency text;
  v_currency text;
  v_exchange_rate numeric(20, 10);
  v_exchange_rate_id uuid;
  v_quotation_date date;
  v_valid_until date;
  v_rate_date date;
  v_revision integer;
  v_pricing jsonb;
  v_line jsonb;
  v_ordinal integer;
  v_entity jsonb;
begin
  perform core.wave3_require_scope(
    p_tenant_id, 'sales.quotations.manage', p_legal_entity_id, p_branch_id
  );
  if p_branch_id is null or p_client_timestamp is null
     or jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Quotation command scope or payload is invalid.';
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
  select q.* into v_existing
  from sales.quotations as q
  where q.tenant_id = p_tenant_id and q.legal_entity_id = p_legal_entity_id
    and q.branch_id = p_branch_id and q.id = v_id
  for update;
  if found then
    v_before := sales.quotation_entity(v_id);
    perform core.wave3_assert_expected_version(
      v_existing.version, p_expected_entity_version, v_before
    );
    if v_existing.status in ('accepted', 'converted') then
      raise exception using errcode = '55000', message = 'ACCEPTED_QUOTATION_IMMUTABLE';
    end if;
    if coalesce((p_payload->>'create_revision')::boolean, false) then
      if v_existing.status not in ('submitted', 'approved', 'rejected', 'expired') then
        raise exception using errcode = '55000', message = 'QUOTATION_REVISION_NOT_ALLOWED';
      end if;
      if length(trim(coalesce(p_payload->>'revision_reason', ''))) not between 1 and 1000 then
        raise exception using errcode = '22023', message = 'Revision reason is required.';
      end if;
      v_revision := v_existing.current_revision + 1;
    elsif v_existing.status <> 'draft' then
      raise exception using errcode = '55000', message = 'QUOTATION_REVISION_REQUIRED';
    else
      v_revision := v_existing.current_revision;
    end if;
  else
    if p_expected_entity_version is not null then
      raise exception using errcode = '40001', message = 'VERSION_CONFLICT';
    end if;
    v_before := null;
    v_revision := 1;
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
  v_quotation_date := (p_payload->>'quotation_date')::date;
  v_valid_until := (p_payload->>'valid_until')::date;
  v_rate_date := (p_payload->>'rate_date')::date;
  if v_valid_until < v_quotation_date then
    raise exception using errcode = '22023', message = 'Quotation validity precedes its date.';
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
  if nullif(p_payload->>'opportunity_id', '') is not null and not exists (
    select 1 from crm.opportunities as o
    where o.tenant_id = p_tenant_id and o.legal_entity_id = p_legal_entity_id
      and o.id = (p_payload->>'opportunity_id')::uuid
      and (o.branch_id is null or o.branch_id = p_branch_id)
  ) then
    raise exception using errcode = '22023', message = 'Opportunity is outside scope.';
  end if;
  if not exists (
    select 1 from core.memberships as m
    where m.tenant_id = p_tenant_id
      and m.user_id = (p_payload->>'salesperson_id')::uuid and m.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'Salesperson is not an active tenant member.';
  end if;

  v_pricing := sales.wave3_price_lines(
    p_tenant_id, p_legal_entity_id, v_quotation_date, v_currency,
    p_payload->'lines', p_payload->'header_discount_amount',
    p_payload->'header_discount_percent'
  );

  if v_existing.id is null then
    insert into sales.quotations (
      id, tenant_id, legal_entity_id, branch_id, current_revision,
      customer_id, contact_id, opportunity_id, quotation_date, valid_until,
      currency_code, base_currency_code, exchange_rate_id, exchange_rate,
      rate_date, payment_terms_days, delivery_terms, salesperson_id,
      header_discount_amount, header_discount_percent, subtotal,
      line_discount_total, header_discount_total, discount_total, tax_total,
      grand_total, base_total, notes, revision_reason, status,
      request_id, command_id, correlation_id, source_context,
      client_timestamp, created_by, updated_by
    ) values (
      v_id, p_tenant_id, p_legal_entity_id, p_branch_id, v_revision,
      (p_payload->>'customer_id')::uuid,
      nullif(p_payload->>'contact_id', '')::uuid,
      nullif(p_payload->>'opportunity_id', '')::uuid,
      v_quotation_date, v_valid_until, v_currency, v_base_currency,
      v_exchange_rate_id, v_exchange_rate, v_rate_date,
      coalesce((p_payload->>'payment_terms_days')::integer, 0),
      nullif(trim(p_payload->>'delivery_terms'), ''),
      (p_payload->>'salesperson_id')::uuid,
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
      nullif(trim(p_payload->>'notes'), ''),
      nullif(trim(p_payload->>'revision_reason'), ''), 'draft',
      v_request_id, p_command_id, v_request_id, v_source_context,
      p_client_timestamp, v_actor, v_actor
    );
  else
    if v_revision <> v_existing.current_revision then
      update workflow.approval_requests set
        status = 'cancelled', decided_at = clock_timestamp(),
        decision_by = v_actor, decision_note = 'Superseded by quotation revision.'
      where tenant_id = p_tenant_id and document_type = 'sales_quotation'
        and document_id = v_id and status = 'submitted';
    else
      delete from sales.quotation_lines
      where tenant_id = p_tenant_id and quotation_id = v_id
        and revision_number = v_revision;
    end if;
    update sales.quotations set
      current_revision = v_revision,
      customer_id = (p_payload->>'customer_id')::uuid,
      contact_id = nullif(p_payload->>'contact_id', '')::uuid,
      opportunity_id = nullif(p_payload->>'opportunity_id', '')::uuid,
      quotation_date = v_quotation_date, valid_until = v_valid_until,
      currency_code = v_currency, base_currency_code = v_base_currency,
      exchange_rate_id = v_exchange_rate_id, exchange_rate = v_exchange_rate,
      rate_date = v_rate_date,
      payment_terms_days = coalesce((p_payload->>'payment_terms_days')::integer, 0),
      delivery_terms = nullif(trim(p_payload->>'delivery_terms'), ''),
      salesperson_id = (p_payload->>'salesperson_id')::uuid,
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
      notes = nullif(trim(p_payload->>'notes'), ''),
      revision_reason = nullif(trim(p_payload->>'revision_reason'), ''),
      status = 'draft', workflow_definition_id = null, workflow_revision = null,
      submitted_at = null, approved_at = null, rejected_at = null,
      accepted_at = null, expired_at = null, cancelled_at = null,
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
  end if;

  for v_line, v_ordinal in
    select value, ordinality::integer
    from jsonb_array_elements(v_pricing->'lines') with ordinality
  loop
    insert into sales.quotation_lines (
      id, tenant_id, legal_entity_id, branch_id, quotation_id,
      revision_number, line_number, product_id, description, unit_id,
      quantity, base_quantity, conversion_numerator, conversion_denominator,
      unit_price, gross_amount, line_discount_amount, discount_percent,
      header_discount_amount, net_amount, tax_definition_id, tax_code,
      tax_name, tax_kind, tax_rate, tax_inclusive, tax_definition_version,
      taxable_amount, tax_amount, line_total, currency_code,
      request_id, command_id, correlation_id, source_context,
      created_by
    ) values (
      coalesce(nullif(v_line->>'line_id', '')::uuid,
        core.wave2_derived_uuid(p_command_id, v_ordinal)),
      p_tenant_id, p_legal_entity_id, p_branch_id, v_id,
      v_revision, v_ordinal, (v_line->>'product_id')::uuid,
      v_line->>'description', (v_line->>'unit_id')::uuid,
      (v_line->>'quantity')::numeric, (v_line->>'base_quantity')::numeric,
      (v_line->>'conversion_numerator')::bigint,
      (v_line->>'conversion_denominator')::bigint,
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
      v_request_id, p_command_id, v_request_id, v_source_context, v_actor
    );
  end loop;

  v_entity := sales.quotation_entity(v_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_quotation', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    case when v_existing.id is null then jsonb_build_object(
      'to_status', 'draft', 'owner_id', (p_payload->>'salesperson_id')::uuid
    ) else null end,
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object('revision', v_revision)
    )),
    '[]'::jsonb, v_request_id, v_request_id
  );
end;
$$;

create function sales.transition_quotation(
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
  v_command_name constant text := 'sales.document.transition';
  v_request_hash text;
  v_replay jsonb;
  v_id uuid := (p_payload->>'document_id')::uuid;
  v_action text := p_payload->>'action';
  v_quote sales.quotations%rowtype;
  v_before jsonb;
  v_entity jsonb;
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_to_status text;
  v_workflow workflow.workflow_definitions%rowtype;
  v_first_step integer;
begin
  if p_payload->>'document_type' <> 'sales_quotation' then
    raise exception using errcode = '22023', message = 'Unsupported operational document type.';
  end if;
  perform core.wave3_require_scope(
    p_tenant_id, 'sales.quotations.manage', p_legal_entity_id, p_branch_id
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
  select q.* into v_quote
  from sales.quotations as q
  where q.tenant_id = p_tenant_id and q.legal_entity_id = p_legal_entity_id
    and q.branch_id = p_branch_id and q.id = v_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Quotation was not found.';
  end if;
  v_before := sales.quotation_entity(v_id);
  perform core.wave3_assert_expected_version(
    v_quote.version, p_expected_entity_version, v_before
  );

  if v_action = 'submit' then
    if v_quote.status <> 'draft' then
      raise exception using errcode = '55000', message = 'QUOTATION_NOT_DRAFT';
    end if;
    if v_quote.valid_until < greatest(
      current_date, (p_client_timestamp at time zone 'UTC')::date
    ) then
      raise exception using errcode = '55000', message = 'QUOTATION_EXPIRED';
    end if;
    if not exists (
      select 1 from sales.quotation_lines as l
      where l.tenant_id = p_tenant_id and l.quotation_id = v_id
        and l.revision_number = v_quote.current_revision
    ) then
      raise exception using errcode = '55000', message = 'QUOTATION_HAS_NO_LINES';
    end if;
    if v_quote.document_number is null then
      v_quote.document_number := sales.wave3_reserve_document_number(
        p_tenant_id, p_legal_entity_id, p_branch_id,
        'sales_quotation', v_quote.quotation_date, v_actor
      );
    end if;
    select wd.* into v_workflow
    from workflow.workflow_definitions as wd
    where wd.tenant_id = p_tenant_id
      and (wd.legal_entity_id = p_legal_entity_id or wd.legal_entity_id is null)
      and wd.document_type = 'sales_quotation' and wd.status = 'active'
    order by (wd.legal_entity_id is not null) desc, wd.revision desc
    limit 1;
    if found then
      select min(am.step_order) into v_first_step
      from workflow.approval_matrix_steps as am
      where am.tenant_id = p_tenant_id
        and am.workflow_definition_id = v_workflow.id and am.status = 'active'
        and (am.currency_code is null or am.currency_code = v_quote.currency_code)
        and (am.minimum_amount is null or v_quote.grand_total >= am.minimum_amount)
        and (am.maximum_amount is null or v_quote.grand_total <= am.maximum_amount);
    end if;
    v_to_status := case when v_first_step is null then 'submitted' else 'pending_approval' end;
    update sales.quotations set
      document_number = v_quote.document_number, status = v_to_status,
      workflow_definition_id = v_workflow.id,
      workflow_revision = v_workflow.revision,
      submitted_at = clock_timestamp(), request_id = v_request_id,
      command_id = p_command_id, correlation_id = v_request_id,
      source_context = v_source_context, client_timestamp = p_client_timestamp,
      updated_by = v_actor
    where id = v_id;
    v_entity := sales.quotation_entity(v_id);
    insert into sales.quotation_revisions (
      tenant_id, legal_entity_id, branch_id, quotation_id, revision_number,
      document_number, status, reason, snapshot, request_id, command_id,
      correlation_id, source_context, created_by
    ) values (
      p_tenant_id, p_legal_entity_id, p_branch_id, v_id,
      v_quote.current_revision, v_quote.document_number, 'submitted',
      nullif(trim(p_payload->>'reason'), ''),
      v_entity || jsonb_build_object('status', 'submitted'),
      v_request_id, p_command_id, v_request_id, v_source_context, v_actor
    );
    if v_first_step is not null then
      insert into workflow.approval_requests (
        tenant_id, legal_entity_id, branch_id, document_type, document_id,
        status, submitted_by, submitted_at, workflow_definition_id,
        workflow_revision, current_step, amount, currency_code,
        command_id, request_id, correlation_id
      ) values (
        p_tenant_id, p_legal_entity_id, p_branch_id, 'sales_quotation', v_id,
        'submitted', v_actor, clock_timestamp(), v_workflow.id,
        v_workflow.revision, v_first_step, v_quote.grand_total,
        v_quote.currency_code, p_command_id, v_request_id, v_request_id
      );
    end if;
  elsif v_action = 'accept' then
    if v_quote.status not in ('submitted', 'approved') then
      raise exception using errcode = '55000', message = 'QUOTATION_NOT_ACCEPTABLE';
    end if;
    if v_quote.valid_until < greatest(
      current_date, (p_client_timestamp at time zone 'UTC')::date
    ) then
      raise exception using errcode = '55000', message = 'QUOTATION_EXPIRED';
    end if;
    v_to_status := 'accepted';
    update sales.quotations set
      status = v_to_status, accepted_at = clock_timestamp(),
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
  elsif v_action = 'expire' then
    if v_quote.status not in ('submitted', 'pending_approval', 'approved')
       or v_quote.valid_until >= greatest(
         current_date, (p_client_timestamp at time zone 'UTC')::date
       ) then
      raise exception using errcode = '55000', message = 'QUOTATION_NOT_EXPIRABLE';
    end if;
    v_to_status := 'expired';
    update sales.quotations set
      status = v_to_status, expired_at = clock_timestamp(),
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
    update workflow.approval_requests set
      status = 'cancelled', decided_at = clock_timestamp(), decision_by = v_actor,
      decision_note = 'Quotation expired.'
    where tenant_id = p_tenant_id and document_type = 'sales_quotation'
      and document_id = v_id and status = 'submitted';
  elsif v_action = 'cancel' then
    if v_quote.status in ('cancelled', 'converted') then
      raise exception using errcode = '55000', message = 'QUOTATION_NOT_CANCELLABLE';
    end if;
    v_to_status := 'cancelled';
    update sales.quotations set
      status = v_to_status, cancelled_at = clock_timestamp(),
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
    update workflow.approval_requests set
      status = 'cancelled', decided_at = clock_timestamp(), decision_by = v_actor,
      decision_note = coalesce(nullif(trim(p_payload->>'reason'), ''), 'Quotation cancelled.')
    where tenant_id = p_tenant_id and document_type = 'sales_quotation'
      and document_id = v_id and status = 'submitted';
  else
    raise exception using errcode = '22023', message = 'Quotation action is invalid.';
  end if;

  v_entity := sales.quotation_entity(v_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_quotation', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    jsonb_build_object(
      'workflow_definition_id', v_entity->>'workflow_definition_id',
      'workflow_revision', v_entity->>'workflow_revision',
      'from_status', v_quote.status, 'to_status', v_to_status,
      'owner_id', v_quote.salesperson_id,
      'reason', nullif(trim(p_payload->>'reason'), '')
    ),
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object('action', v_action, 'status', v_to_status)
    )),
    '[]'::jsonb, v_request_id, v_request_id
  );
end;
$$;

create function api.transition_operational_document(
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
language sql
security definer
set search_path = ''
as $$
  select sales.transition_quotation(
    p_tenant_id, p_legal_entity_id, p_branch_id, p_command_id,
    p_idempotency_key, p_client_timestamp, p_payload,
    p_expected_entity_version
  );
$$;

create function api.decide_operational_approval(
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
  v_command_name constant text := 'workflow.operational_approval.decide';
  v_request_hash text;
  v_replay jsonb;
  v_id uuid := (p_payload->>'document_id')::uuid;
  v_decision text := p_payload->>'decision';
  v_quote sales.quotations%rowtype;
  v_approval workflow.approval_requests%rowtype;
  v_step workflow.approval_matrix_steps%rowtype;
  v_next_step integer;
  v_before jsonb;
  v_entity jsonb;
  v_request_id uuid := gen_random_uuid();
  v_source_context jsonb := coalesce(p_payload->'source_context', '{}'::jsonb);
  v_to_status text;
begin
  if p_payload->>'document_type' <> 'sales_quotation' then
    raise exception using errcode = '22023', message = 'Unsupported approval document type.';
  end if;
  perform core.wave3_require_scope(
    p_tenant_id, 'workflow.approvals.decide', p_legal_entity_id, p_branch_id
  );
  if v_decision not in ('approved', 'rejected')
     or (v_decision = 'rejected' and nullif(trim(p_payload->>'note'), '') is null)
     or jsonb_typeof(v_source_context) <> 'object' then
    raise exception using errcode = '22023', message = 'Approval decision is invalid.';
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
    and q.branch_id = p_branch_id and q.id = v_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Quotation was not found.';
  end if;
  v_before := sales.quotation_entity(v_id);
  perform core.wave3_assert_expected_version(
    v_quote.version, p_expected_entity_version, v_before
  );
  if v_quote.status <> 'pending_approval' then
    raise exception using errcode = '55000', message = 'APPROVAL_NOT_PENDING';
  end if;
  select ar.* into v_approval
  from workflow.approval_requests as ar
  where ar.tenant_id = p_tenant_id and ar.document_type = 'sales_quotation'
    and ar.document_id = v_id and ar.status = 'submitted'
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'APPROVAL_REQUEST_NOT_FOUND';
  end if;
  if v_approval.submitted_by = v_actor then
    raise exception using errcode = '42501', message = 'SEGREGATION_OF_DUTIES_VIOLATION';
  end if;
  select am.* into v_step
  from workflow.approval_matrix_steps as am
  where am.tenant_id = p_tenant_id
    and am.workflow_definition_id = v_approval.workflow_definition_id
    and am.step_order = v_approval.current_step and am.status = 'active';
  if not found or not exists (
    select 1
    from core.memberships as m
    join core.role_assignments as ra
      on ra.tenant_id = m.tenant_id and ra.membership_id = m.id
    where m.tenant_id = p_tenant_id and m.user_id = v_actor
      and m.status = 'active' and ra.role_id = v_step.role_id
      and (ra.legal_entity_id is null or ra.legal_entity_id = p_legal_entity_id)
      and (ra.branch_id is null or ra.branch_id = p_branch_id)
  ) then
    raise exception using errcode = '42501', message = 'APPROVAL_ROLE_REQUIRED';
  end if;

  insert into workflow.approval_decisions (
    tenant_id, approval_request_id, workflow_definition_id,
    workflow_revision, approval_matrix_step_id, step_order, actor_id,
    decision, note, amount, currency_code, request_id, command_id,
    correlation_id
  ) values (
    p_tenant_id, v_approval.id, v_approval.workflow_definition_id,
    v_approval.workflow_revision, v_step.id, v_step.step_order, v_actor,
    v_decision, nullif(trim(p_payload->>'note'), ''),
    v_approval.amount, v_approval.currency_code,
    v_request_id, p_command_id, v_request_id
  );

  if v_decision = 'rejected' then
    v_to_status := 'rejected';
    update workflow.approval_requests set
      status = 'rejected', decision_by = v_actor,
      decision_note = nullif(trim(p_payload->>'note'), ''),
      decided_at = clock_timestamp()
    where id = v_approval.id;
  else
    select min(am.step_order) into v_next_step
    from workflow.approval_matrix_steps as am
    where am.tenant_id = p_tenant_id
      and am.workflow_definition_id = v_approval.workflow_definition_id
      and am.status = 'active' and am.step_order > v_step.step_order
      and (am.currency_code is null or am.currency_code = v_approval.currency_code)
      and (am.minimum_amount is null or v_approval.amount >= am.minimum_amount)
      and (am.maximum_amount is null or v_approval.amount <= am.maximum_amount);
    if v_next_step is null then
      v_to_status := 'approved';
      update workflow.approval_requests set
        status = 'approved', decision_by = v_actor,
        decision_note = nullif(trim(p_payload->>'note'), ''),
        decided_at = clock_timestamp()
      where id = v_approval.id;
    else
      v_to_status := 'pending_approval';
      update workflow.approval_requests set current_step = v_next_step
      where id = v_approval.id;
    end if;
  end if;
  update sales.quotations set
    status = v_to_status,
    approved_at = case when v_to_status = 'approved' then clock_timestamp() else approved_at end,
    rejected_at = case when v_to_status = 'rejected' then clock_timestamp() else rejected_at end,
    request_id = v_request_id, command_id = p_command_id,
    correlation_id = v_request_id, source_context = v_source_context,
    client_timestamp = p_client_timestamp, updated_by = v_actor
  where id = v_id;
  v_entity := sales.quotation_entity(v_id);
  return core.wave3_finish_command(
    p_tenant_id, v_command_name, p_command_id, 'sales_quotation', v_id,
    p_idempotency_key, v_request_hash, v_before, v_entity,
    p_legal_entity_id, p_branch_id, v_source_context,
    case when v_quote.status = v_to_status then null else jsonb_build_object(
      'workflow_definition_id', v_approval.workflow_definition_id,
      'workflow_revision', v_approval.workflow_revision,
      'from_status', v_quote.status, 'to_status', v_to_status,
      'owner_id', v_quote.salesperson_id,
      'reason', nullif(trim(p_payload->>'note'), '')
    ) end,
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object(
        'decision', v_decision, 'step_order', v_step.step_order
      )
    )),
    '[]'::jsonb, v_request_id, v_request_id
  );
end;
$$;

revoke all on function sales.wave3_decimal_string(
  jsonb, text, integer, boolean, numeric, numeric
) from public, anon, authenticated;
revoke all on function sales.wave3_positive_bigint(jsonb, text)
  from public, anon, authenticated;
revoke all on function sales.wave3_price_lines(
  uuid, uuid, date, text, jsonb, jsonb, jsonb
) from public, anon, authenticated;
revoke all on function sales.wave3_reserve_document_number(
  uuid, uuid, uuid, text, date, uuid
) from public, anon, authenticated;
revoke all on function sales.quotation_entity(uuid)
  from public, anon, authenticated;
revoke all on function sales.transition_quotation(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.upsert_sales_quotation(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.transition_operational_document(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
revoke all on function api.decide_operational_approval(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) from public, anon, authenticated;
grant execute on function api.upsert_sales_quotation(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.transition_operational_document(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;
grant execute on function api.decide_operational_approval(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) to authenticated;

comment on function api.upsert_sales_quotation(
  uuid, uuid, uuid, uuid, uuid, timestamptz, jsonb, bigint
) is 'Idempotent, version-aware quotation draft and revision command.';

notify pgrst, 'reload schema';
