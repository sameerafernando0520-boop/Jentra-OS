-- Correct proportional header-discount rounding without rewriting applied migrations.
-- Cumulative rounding makes every allocation non-negative and the final sum exact.
create or replace function sales.wave3_price_lines(
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
  v_cumulative_basis numeric(20, 6) := 0;
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
    v_cumulative_basis := v_cumulative_basis + v_basis;
    v_header_allocation := case
      when v_header_total = 0 then 0
      when v_ordinal = v_count then v_header_total - v_allocated
      else round(
        v_header_total * v_cumulative_basis / nullif(v_basis_total, 0),
        v_rounding_scale
      ) - v_allocated
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

revoke all on function sales.wave3_price_lines(
  uuid, uuid, date, text, jsonb, jsonb, jsonb
) from public, anon, authenticated;
