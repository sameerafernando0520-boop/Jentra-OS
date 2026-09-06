-- AC-303 additive quotation contracts. Published migrations remain unchanged.
-- Compatible expansion: one nullable snapshot column and new security-invoker
-- views. Existing command signatures and existing response fields are retained.
alter table sales.quotations add column workflow_snapshot jsonb
  check (workflow_snapshot is null or jsonb_typeof(workflow_snapshot)='object');

create function sales.assert_quotation_transition(p_lifecycle jsonb,p_from text,p_to text)
returns void language plpgsql set search_path='' as $$
begin
  if p_from='pending_approval' then p_from:='submitted'; end if;
  if p_to='pending_approval' then p_to:='submitted'; end if;
  if p_from=p_to then return; end if;
  if p_lifecycle is null or not (
    coalesce(p_lifecycle->'transitions','[]'::jsonb) ||
    coalesce(p_lifecycle->'quotation_transitions','[]'::jsonb)
  ) @> jsonb_build_array(jsonb_build_array(p_from,p_to)) then
    raise exception using errcode='55000',message='WORKFLOW_TRANSITION_INVALID';
  end if;
end;
$$;
revoke all on function sales.assert_quotation_transition(jsonb,text,text)
  from public,anon,authenticated;

create function sales.validate_quotation_submission(p_quote sales.quotations)
returns void language plpgsql security definer set search_path='' as $$
declare v_lines jsonb; v_price jsonb; v_scale integer;
begin
  if not exists(select 1 from crm.parties p where p.tenant_id=p_quote.tenant_id
    and p.id=p_quote.customer_id and p.kind in ('customer','both') and p.status='active')
    or (p_quote.contact_id is not null and not exists(select 1 from crm.contacts c
      where c.tenant_id=p_quote.tenant_id and c.id=p_quote.contact_id
        and c.party_id=p_quote.customer_id and c.status='active'))
    or not exists(select 1 from core.memberships m where m.tenant_id=p_quote.tenant_id
      and m.user_id=p_quote.salesperson_id and m.status='active') then
    raise exception using errcode='22023',message='QUOTATION_REFERENCE_INACTIVE';
  end if;
  if p_quote.exchange_rate_id is not null and not exists(
    select 1 from finance.exchange_rates er where er.id=p_quote.exchange_rate_id
      and er.tenant_id=p_quote.tenant_id and er.legal_entity_id=p_quote.legal_entity_id
      and er.status='active' and er.source_currency_code=p_quote.currency_code
      and er.target_currency_code=p_quote.base_currency_code
      and er.effective_date=p_quote.rate_date and er.rate=p_quote.exchange_rate) then
    raise exception using errcode='22023',message='QUOTATION_RATE_CHANGED';
  end if;
  select jsonb_agg(jsonb_strip_nulls(to_jsonb(l) || jsonb_build_object(
    'line_id',l.id,'discount_amount',
      case when l.discount_percent is null then l.line_discount_amount else null end
  )) order by l.line_number) into v_lines
  from api.sales_quotation_lines l where l.tenant_id=p_quote.tenant_id
    and l.quotation_id=p_quote.id and l.revision_number=p_quote.current_revision;
  v_price:=sales.wave3_price_lines(p_quote.tenant_id,p_quote.legal_entity_id,
    p_quote.quotation_date,p_quote.currency_code,v_lines,
    case when p_quote.header_discount_percent is null
      then to_jsonb(p_quote.header_discount_amount::text) else null end,
    case when p_quote.header_discount_percent is null then null
      else to_jsonb(p_quote.header_discount_percent::text) end);
  select rounding_scale into v_scale from core.legal_entities where id=p_quote.legal_entity_id;
  if (v_price->>'grand_total')::numeric<>p_quote.grand_total
    or (v_price->>'tax_total')::numeric<>p_quote.tax_total
    or (v_price->>'discount_total')::numeric<>p_quote.discount_total
    or round((v_price->>'grand_total')::numeric*p_quote.exchange_rate,v_scale)<>p_quote.base_total
    or exists (
      select 1 from jsonb_array_elements(v_price->'lines') n
      join api.sales_quotation_lines old on old.id=(n->>'line_id')::uuid
      where old.tax_definition_version is distinct from (n->>'tax_definition_version')::bigint
        or old.tax_amount::numeric<>(n->>'tax_amount')::numeric
        or old.line_total::numeric<>(n->>'line_total')::numeric
    ) then
    raise exception using errcode='55000',message='QUOTATION_RECALCULATION_REQUIRED',
      detail='Save the draft to recalculate its governed values before submitting.';
  end if;
end;
$$;
revoke all on function sales.validate_quotation_submission(sales.quotations)
  from public,anon,authenticated;

create or replace function api.upsert_sales_quotation(
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
      perform sales.assert_quotation_transition(v_existing.workflow_snapshot->'lifecycle',
        v_existing.status,'draft');
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
      workflow_snapshot = null,
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
      case when v_revision is distinct from v_existing.current_revision and v_existing.id is not null
        then core.wave2_derived_uuid(p_command_id, v_ordinal)
        else coalesce(nullif(v_line->>'line_id', '')::uuid,
          core.wave2_derived_uuid(p_command_id, v_ordinal)) end,
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
    ) when v_revision<>v_existing.current_revision then jsonb_build_object(
      'from_status',v_existing.status,'to_status','draft',
      'workflow_definition_id',v_existing.workflow_definition_id,
      'workflow_revision',v_existing.workflow_revision,
      'owner_id',(p_payload->>'salesperson_id')::uuid,
      'reason',p_payload->>'revision_reason'
    ) else null end,
    jsonb_build_array(jsonb_build_object(
      'topic', v_command_name,
      'payload', jsonb_build_object('revision', v_revision)
    )),
    '[]'::jsonb, v_request_id, v_request_id
  );
end;
$$;

create or replace function sales.transition_quotation(
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
  v_snapshot jsonb;
  v_lifecycle jsonb;
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

  v_lifecycle:=v_quote.workflow_snapshot->'lifecycle';
  if v_action = 'submit' then
    if v_quote.status <> 'draft' then
      raise exception using errcode = '55000', message = 'QUOTATION_NOT_DRAFT';
    end if;
    if v_quote.valid_until < greatest(
      (clock_timestamp() at time zone 'UTC')::date, (p_client_timestamp at time zone 'UTC')::date
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
    perform sales.validate_quotation_submission(v_quote);
    if v_quote.document_number is null then
      v_quote.document_number := sales.wave3_reserve_document_number(
        p_tenant_id, p_legal_entity_id, p_branch_id,
        'sales_quotation', v_quote.quotation_date, v_actor
      );
    end if;
    select wd.* into v_workflow
    from workflow.workflow_definitions wd
    where wd.tenant_id=p_tenant_id and wd.document_type='sales_quotation'
      and wd.status='active' and (wd.legal_entity_id=p_legal_entity_id or wd.legal_entity_id is null)
    order by (wd.legal_entity_id is not null) desc,wd.revision desc limit 1;
    if not found then
      raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';
    end if;
    if (select count(*) from workflow.workflow_definitions wd
      where wd.tenant_id=p_tenant_id and wd.document_type='sales_quotation'
        and wd.status='active' and wd.legal_entity_id is not distinct from v_workflow.legal_entity_id
        and wd.revision=v_workflow.revision)<>1 then
      raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';
    end if;
    v_lifecycle:=v_workflow.lifecycle;
    select jsonb_build_object('lifecycle',v_lifecycle,
      'definition_id',v_workflow.id,'revision',v_workflow.revision,
      'definition_version',v_workflow.version,'steps',coalesce(jsonb_agg(
        to_jsonb(am)||jsonb_build_object('minimum_amount',am.minimum_amount::text,
          'maximum_amount',am.maximum_amount::text) order by am.step_order),'[]'::jsonb))
      into v_snapshot
    from workflow.approval_matrix_steps am
    where am.tenant_id=p_tenant_id and am.workflow_definition_id=v_workflow.id
      and am.status='active'
      and (am.currency_code is null or am.currency_code=v_quote.currency_code)
      and (am.minimum_amount is null or v_quote.grand_total>=am.minimum_amount)
      and (am.maximum_amount is null or v_quote.grand_total<=am.maximum_amount);
    if v_lifecycle->'requires_approval' is distinct from 'false'::jsonb then
      select min((s->>'step_order')::integer) into v_first_step
      from jsonb_array_elements(v_snapshot->'steps') s;
      if v_first_step is null then
        raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';
      end if;
    end if;
    v_to_status:=case when v_first_step is null then 'submitted' else 'pending_approval' end;
    perform sales.assert_quotation_transition(v_lifecycle,'draft',v_to_status);
    update sales.quotations set
      document_number = v_quote.document_number, status = v_to_status,
      workflow_snapshot = v_snapshot,
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
      v_entity || jsonb_build_object('status', 'submitted','workflow_snapshot',v_snapshot),
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
  elsif v_action='recall' then
    if v_quote.status not in ('submitted','pending_approval','approved') then
      raise exception using errcode='55000',message='QUOTATION_NOT_RECALLABLE';
    end if;
    if length(trim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
      raise exception using errcode='22023',message='Recall reason is required.';
    end if;
    perform sales.assert_quotation_transition(v_lifecycle,v_quote.status,'draft');
    v_to_status:='draft';
    update sales.quotations set status='draft',current_revision=current_revision+1,
      revision_reason=trim(p_payload->>'reason'),submitted_at=null,approved_at=null,
      rejected_at=null,accepted_at=null,expired_at=null,cancelled_at=null,
      workflow_snapshot=null,workflow_definition_id=null,workflow_revision=null,
      request_id=v_request_id,command_id=p_command_id,
      correlation_id=v_request_id,source_context=v_source_context,
      client_timestamp=p_client_timestamp,updated_by=v_actor where id=v_id;
    insert into sales.quotation_lines
    select (jsonb_populate_record(null::sales.quotation_lines,to_jsonb(l)||jsonb_build_object(
      'id',gen_random_uuid(),'revision_number',v_quote.current_revision+1,
      'request_id',v_request_id,'command_id',p_command_id,'correlation_id',v_request_id,
      'source_context',v_source_context,'created_by',v_actor,'created_at',clock_timestamp()
    ))).* from sales.quotation_lines l
    where l.tenant_id=p_tenant_id and l.quotation_id=v_id
      and l.revision_number=v_quote.current_revision;
    update workflow.approval_requests set status='cancelled',decided_at=clock_timestamp(),
      decision_by=v_actor,decision_note=trim(p_payload->>'reason')
    where tenant_id=p_tenant_id and document_type='sales_quotation'
      and document_id=v_id and status='submitted';
  elsif v_action = 'accept' then
    if v_quote.status not in ('submitted', 'approved') then
      raise exception using errcode = '55000', message = 'QUOTATION_NOT_ACCEPTABLE';
    end if;
    if v_quote.valid_until < greatest(
      (clock_timestamp() at time zone 'UTC')::date, (p_client_timestamp at time zone 'UTC')::date
    ) then
      raise exception using errcode = '55000', message = 'QUOTATION_EXPIRED';
    end if;
    v_to_status := 'accepted';
    perform sales.assert_quotation_transition(v_lifecycle,v_quote.status,v_to_status);
    update sales.quotations set
      status = v_to_status, accepted_at = clock_timestamp(),
      request_id = v_request_id, command_id = p_command_id,
      correlation_id = v_request_id, source_context = v_source_context,
      client_timestamp = p_client_timestamp, updated_by = v_actor
    where id = v_id;
  elsif v_action = 'expire' then
    if v_quote.status not in ('submitted', 'pending_approval', 'approved')
       or v_quote.valid_until >= (clock_timestamp() at time zone 'UTC')::date then
      raise exception using errcode = '55000', message = 'QUOTATION_NOT_EXPIRABLE';
    end if;
    v_to_status := 'expired';
    perform sales.assert_quotation_transition(v_lifecycle,v_quote.status,v_to_status);
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
    if v_quote.status='draft' and v_lifecycle is null then
      select lifecycle into v_lifecycle from workflow.workflow_definitions
      where tenant_id=p_tenant_id and document_type='sales_quotation' and status='active'
        and (legal_entity_id=p_legal_entity_id or legal_entity_id is null)
      order by (legal_entity_id is not null) desc,revision desc limit 1;
    end if;
    v_to_status := 'cancelled';
    perform sales.assert_quotation_transition(v_lifecycle,v_quote.status,v_to_status);
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
      'workflow_definition_id', coalesce(v_entity->>'workflow_definition_id',v_quote.workflow_definition_id::text),
      'workflow_revision', coalesce(v_entity->>'workflow_revision',v_quote.workflow_revision::text),
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

create or replace function api.decide_operational_approval(
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
  if v_quote.workflow_snapshot is null then
    raise exception using errcode='55000',message='WORKFLOW_CONFIGURATION_ERROR';
  end if;
  perform sales.assert_quotation_transition(v_quote.workflow_snapshot->'lifecycle',
    v_quote.status,v_decision);
  select am.* into v_step
  from jsonb_populate_recordset(null::workflow.approval_matrix_steps,
    v_quote.workflow_snapshot->'steps') as am
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
    from jsonb_populate_recordset(null::workflow.approval_matrix_steps,
      v_quote.workflow_snapshot->'steps') as am
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

-- One statement yields a coherent header + current line revision.
create view api.sales_quotation_details with(security_invoker=true) as
select q.*,coalesce((select jsonb_agg(to_jsonb(l) order by l.line_number)
  from api.sales_quotation_lines l where l.tenant_id=q.tenant_id
    and l.quotation_id=q.id and l.revision_number=q.current_revision),'[]'::jsonb) as lines
from api.sales_quotations q;

-- A permitted quotation reader can inspect its decisions, but never another
-- aggregate's approvals. Preserve every existing owner/approver predicate in
-- one SELECT policy per table, avoiding overlapping permissive policies.
alter policy approval_requests_permitted_read on workflow.approval_requests
using(core.is_tenant_member(tenant_id) and (
  submitted_by=(select auth.uid()) or assigned_to=(select auth.uid())
  or decision_by=(select auth.uid())
  or core.has_permission(tenant_id,'workflow.approvals.view',legal_entity_id,branch_id)
  or core.has_permission(tenant_id,'workflow.approvals.decide',legal_entity_id,branch_id)
  or (document_type='sales_quotation' and exists(
    select 1 from sales.quotations q where q.tenant_id=approval_requests.tenant_id
      and q.legal_entity_id=approval_requests.legal_entity_id
      and q.branch_id=approval_requests.branch_id and q.id=approval_requests.document_id))));
alter policy approval_decisions_permitted_read on workflow.approval_decisions
using(core.is_tenant_member(tenant_id) and (
  actor_id=(select auth.uid()) or exists(
    select 1 from workflow.approval_requests ar
    where ar.id=approval_decisions.approval_request_id
      and ar.tenant_id=approval_decisions.tenant_id and (
        ar.submitted_by=(select auth.uid()) or ar.assigned_to=(select auth.uid())
        or ar.decision_by=(select auth.uid())
        or core.has_permission(ar.tenant_id,'workflow.approvals.view',ar.legal_entity_id,ar.branch_id)
        or core.has_permission(ar.tenant_id,'workflow.approvals.decide',ar.legal_entity_id,ar.branch_id)
        or (ar.document_type='sales_quotation' and exists(
          select 1 from sales.quotations q where q.tenant_id=ar.tenant_id
            and q.legal_entity_id=ar.legal_entity_id and q.branch_id=ar.branch_id
            and q.id=ar.document_id))))));

create view api.sales_quotation_decisions with(security_invoker=true) as
select d.id,q.tenant_id,q.legal_entity_id,q.branch_id,q.id as quotation_id,
  d.approval_request_id,ar.request_id as submission_request_id,
  r.revision_number,d.workflow_definition_id,d.workflow_revision,d.step_order,
  d.actor_id,d.decision,d.note,d.amount::text as amount,d.currency_code,
  d.request_id,d.command_id,d.correlation_id,d.decided_at
from workflow.approval_decisions d
join workflow.approval_requests ar on ar.tenant_id=d.tenant_id and ar.id=d.approval_request_id
join sales.quotations q on q.tenant_id=ar.tenant_id and q.legal_entity_id=ar.legal_entity_id
  and q.branch_id=ar.branch_id and q.id=ar.document_id
join sales.quotation_revisions r on r.tenant_id=q.tenant_id and r.quotation_id=q.id
  and r.command_id=ar.command_id
where ar.document_type='sales_quotation';

revoke all on api.sales_quotation_details,api.sales_quotation_decisions from public,anon,authenticated;
grant select on api.sales_quotation_details,api.sales_quotation_decisions to authenticated;
revoke all on function sales.transition_quotation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)
  from public,anon,authenticated;
revoke all on function api.upsert_sales_quotation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.decide_operational_approval(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
