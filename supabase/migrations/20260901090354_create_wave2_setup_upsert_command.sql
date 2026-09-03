-- Wave 2 normalized setup upsert dispatcher. Named api functions wrap this
-- private implementation; resource dispatch is explicit and contains no
-- dynamic SQL.

create function core.upsert_setup_record_impl(
  p_resource text,
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_payload jsonb,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_command_name text;
  v_aggregate_type text;
  v_permission text;
  v_request_hash text;
  v_replay jsonb;
  v_id uuid;
  v_is_update boolean;
  v_before jsonb;
  v_entity jsonb;
  v_current_version bigint;
  v_current_bigint bigint;
  v_legal_entity_id uuid := p_legal_entity_id;
  v_branch_id uuid;
  v_parent_id uuid;
  v_workflow_id uuid;
  v_previous_state text;
  v_start_date date;
  v_end_date date;
  v_minimum numeric(20, 6);
  v_maximum numeric(20, 6);
  v_default_currency text;
  v_owner_id uuid;
  v_row record;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'Command payload must be an object.';
  end if;

  v_aggregate_type := case p_resource
    when 'exchange_rates' then 'exchange_rate'
    when 'tax_definitions' then 'tax_definition'
    when 'accounts' then 'account'
    when 'fiscal_periods' then 'fiscal_period'
    when 'parties' then 'party'
    when 'contacts' then 'contact'
    when 'units' then 'unit'
    when 'products' then 'product'
    when 'document_sequences' then 'document_sequence'
    when 'workflow_definitions' then 'workflow_definition'
    when 'approval_matrix_steps' then 'approval_matrix_step'
    when 'report_definitions' then 'report_definition'
    else null
  end;
  if v_aggregate_type is null then
    raise exception using errcode = '22023', message = 'Setup resource is not supported.';
  end if;
  v_command_name := 'upsert_' || v_aggregate_type;

  if p_resource = 'document_sequences' then
    v_legal_entity_id := nullif(p_payload->>'legal_entity_id', '')::uuid;
    v_branch_id := nullif(p_payload->>'branch_id', '')::uuid;
  elsif p_resource = 'approval_matrix_steps' then
    v_workflow_id := nullif(p_payload->>'workflow_definition_id', '')::uuid;
    select wd.legal_entity_id into v_legal_entity_id
    from workflow.workflow_definitions as wd
    where wd.tenant_id = p_tenant_id and wd.id = v_workflow_id;
    if not found then
      raise exception using errcode = '22023', message = 'Workflow definition is invalid.';
    end if;
  end if;

  if v_legal_entity_id is not null and not exists (
    select 1 from core.legal_entities as le
    where le.tenant_id = p_tenant_id and le.id = v_legal_entity_id
  ) then
    raise exception using errcode = '22023', message = 'Legal entity scope is invalid.';
  end if;
  if v_branch_id is not null and not exists (
    select 1 from core.branches as b
    where b.tenant_id = p_tenant_id
      and b.id = v_branch_id
      and b.legal_entity_id = v_legal_entity_id
  ) then
    raise exception using errcode = '22023', message = 'Branch scope is invalid.';
  end if;

  v_permission := core.wave2_permission(p_resource, true);
  perform core.require_permission(
    p_tenant_id, v_permission, v_legal_entity_id, v_branch_id
  );

  v_request_hash := core.wave2_request_hash(
    v_command_name,
    p_tenant_id,
    v_legal_entity_id,
    p_payload,
    p_expected_version
  );
  v_replay := core.wave2_replay(
    p_tenant_id, v_command_name, p_idempotency_key, v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  v_is_update := nullif(p_payload->>'id', '') is not null;
  v_id := case
    when v_is_update then (p_payload->>'id')::uuid
    else gen_random_uuid()
  end;
  if not v_is_update and p_expected_version is not null then
    raise exception using
      errcode = '22023',
      message = 'Expected version is only valid for an existing entity.';
  end if;

  select t.default_currency_code into v_default_currency
  from core.tenants as t where t.id = p_tenant_id;
  if not found then
    raise exception using errcode = '22023', message = 'Tenant scope is invalid.';
  end if;

  -- -------------------------------------------------------------------------
  -- Finance setup
  -- -------------------------------------------------------------------------
  if p_resource = 'exchange_rates' then
    if coalesce(p_payload->>'source_currency_code', '') !~ '^[A-Za-z]{3}$'
       or coalesce(p_payload->>'target_currency_code', '') !~ '^[A-Za-z]{3}$' then
      raise exception using errcode = '22023', message = 'Currency code is invalid.';
    end if;
    if upper(p_payload->>'source_currency_code') = upper(p_payload->>'target_currency_code') then
      raise exception using
        errcode = '22023',
        message = 'Source and target currencies must differ.';
    end if;
    if (p_payload->>'rate')::numeric <= 0 then
      raise exception using errcode = '22023', message = 'Exchange rate must be positive.';
    end if;
    if not exists (
      select 1 from core.currencies as c
      where c.code = upper(p_payload->>'source_currency_code') and c.active
    ) or not exists (
      select 1 from core.currencies as c
      where c.code = upper(p_payload->>'target_currency_code') and c.active
    ) then
      raise exception using errcode = '22023', message = 'Currency code is invalid.';
    end if;

    if v_is_update then
      select to_jsonb(er), er.version into v_before, v_current_version
      from finance.exchange_rates as er
      where er.id = v_id
        and er.tenant_id = p_tenant_id
        and er.legal_entity_id = v_legal_entity_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Exchange rate was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update finance.exchange_rates set
        source_currency_code = upper(p_payload->>'source_currency_code'),
        target_currency_code = upper(p_payload->>'target_currency_code'),
        rate = (p_payload->>'rate')::numeric,
        effective_date = (p_payload->>'effective_date')::date,
        rate_type = coalesce(nullif(p_payload->>'rate_type', ''), 'spot'),
        source = coalesce(nullif(trim(p_payload->>'source'), ''), 'manual'),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into finance.exchange_rates (
        id, tenant_id, legal_entity_id, source_currency_code,
        target_currency_code, rate, effective_date, rate_type, source,
        status, created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_legal_entity_id,
        upper(p_payload->>'source_currency_code'),
        upper(p_payload->>'target_currency_code'),
        (p_payload->>'rate')::numeric,
        (p_payload->>'effective_date')::date,
        coalesce(nullif(p_payload->>'rate_type', ''), 'spot'),
        coalesce(nullif(trim(p_payload->>'source'), ''), 'manual'),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object(
      'code', v_row.source_currency_code || '/' || v_row.target_currency_code,
      'name', v_row.source_currency_code || ' to ' || v_row.target_currency_code,
      'rate', v_row.rate::text
    );

  elsif p_resource = 'tax_definitions' then
    if coalesce(trim(p_payload->>'code'), '') = ''
       or coalesce(trim(p_payload->>'name'), '') = '' then
      raise exception using errcode = '22023', message = 'Tax code and name are required.';
    end if;
    if (p_payload->>'rate')::numeric < 0 or (p_payload->>'rate')::numeric > 100 then
      raise exception using errcode = '22023', message = 'Tax rate must be between zero and one hundred.';
    end if;
    v_start_date := (p_payload->>'valid_from')::date;
    v_end_date := nullif(p_payload->>'valid_to', '')::date;
    if v_end_date is not null and v_end_date < v_start_date then
      raise exception using errcode = '22023', message = 'Tax validity dates are invalid.';
    end if;

    if v_is_update then
      select to_jsonb(td), td.version into v_before, v_current_version
      from finance.tax_definitions as td
      where td.id = v_id
        and td.tenant_id = p_tenant_id
        and td.legal_entity_id = v_legal_entity_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Tax definition was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update finance.tax_definitions set
        code = upper(trim(p_payload->>'code')),
        name = trim(p_payload->>'name'),
        rate = (p_payload->>'rate')::numeric,
        kind = p_payload->>'kind',
        inclusive = coalesce((p_payload->>'inclusive')::boolean, false),
        recoverable = coalesce((p_payload->>'recoverable')::boolean, false),
        valid_from = v_start_date,
        valid_to = v_end_date,
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into finance.tax_definitions (
        id, tenant_id, legal_entity_id, code, name, rate, kind,
        inclusive, recoverable, valid_from, valid_to, status,
        created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_legal_entity_id,
        upper(trim(p_payload->>'code')), trim(p_payload->>'name'),
        (p_payload->>'rate')::numeric, p_payload->>'kind',
        coalesce((p_payload->>'inclusive')::boolean, false),
        coalesce((p_payload->>'recoverable')::boolean, false),
        v_start_date, v_end_date,
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object('rate', v_row.rate::text);

  elsif p_resource = 'accounts' then
    if coalesce(trim(p_payload->>'code'), '') = ''
       or coalesce(trim(p_payload->>'name'), '') = '' then
      raise exception using errcode = '22023', message = 'Account code and name are required.';
    end if;
    v_parent_id := nullif(p_payload->>'parent_id', '')::uuid;
    if v_parent_id = v_id then
      raise exception using errcode = '22023', message = 'Account cannot be its own parent.';
    end if;
    if v_parent_id is not null and not exists (
      select 1 from finance.accounts as parent
      where parent.tenant_id = p_tenant_id
        and parent.legal_entity_id = v_legal_entity_id
        and parent.id = v_parent_id
        and not parent.is_posting
        and parent.status = 'active'
    ) then
      raise exception using
        errcode = '22023',
        message = 'Parent account must be an active non-posting account in this entity.';
    end if;
    if v_parent_id is not null and exists (
      with recursive ancestors as (
        select a.id, a.parent_id
        from finance.accounts as a
        where a.tenant_id = p_tenant_id
          and a.legal_entity_id = v_legal_entity_id
          and a.id = v_parent_id
        union all
        select parent.id, parent.parent_id
        from finance.accounts as parent
        join ancestors on parent.id = ancestors.parent_id
        where parent.tenant_id = p_tenant_id
          and parent.legal_entity_id = v_legal_entity_id
      )
      select 1 from ancestors where id = v_id
    ) then
      raise exception using errcode = '22023', message = 'Account hierarchy contains a cycle.';
    end if;

    if v_is_update then
      select to_jsonb(a), a.version into v_before, v_current_version
      from finance.accounts as a
      where a.id = v_id
        and a.tenant_id = p_tenant_id
        and a.legal_entity_id = v_legal_entity_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Account was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update finance.accounts set
        code = upper(trim(p_payload->>'code')),
        name = trim(p_payload->>'name'),
        account_type = p_payload->>'account_type',
        normal_balance = p_payload->>'normal_balance',
        parent_id = v_parent_id,
        is_posting = coalesce((p_payload->>'is_posting')::boolean, true),
        currency_code = nullif(upper(p_payload->>'currency_code'), ''),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into finance.accounts (
        id, tenant_id, legal_entity_id, code, name, account_type,
        normal_balance, parent_id, is_posting, currency_code, status,
        created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_legal_entity_id,
        upper(trim(p_payload->>'code')), trim(p_payload->>'name'),
        p_payload->>'account_type', p_payload->>'normal_balance', v_parent_id,
        coalesce((p_payload->>'is_posting')::boolean, true),
        nullif(upper(p_payload->>'currency_code'), ''),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row);

  elsif p_resource = 'fiscal_periods' then
    if coalesce(trim(p_payload->>'name'), '') = '' then
      raise exception using errcode = '22023', message = 'Fiscal period name is required.';
    end if;
    v_start_date := (p_payload->>'start_date')::date;
    v_end_date := (p_payload->>'end_date')::date;
    if v_end_date < v_start_date then
      raise exception using errcode = '22023', message = 'Fiscal period dates are invalid.';
    end if;
    if coalesce(nullif(p_payload->>'status', ''), 'active') = 'active'
       and exists (
        select 1 from finance.fiscal_periods as fp
        where fp.tenant_id = p_tenant_id
          and fp.legal_entity_id = v_legal_entity_id
          and fp.id <> v_id
          and fp.status = 'active'
          and daterange(fp.start_date, fp.end_date, '[]')
              && daterange(v_start_date, v_end_date, '[]')
      ) then
      raise exception using errcode = '22023', message = 'Fiscal period dates overlap.';
    end if;

    if v_is_update then
      select to_jsonb(fp), fp.version, fp.state
        into v_before, v_current_version, v_previous_state
      from finance.fiscal_periods as fp
      where fp.id = v_id
        and fp.tenant_id = p_tenant_id
        and fp.legal_entity_id = v_legal_entity_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Fiscal period was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      if v_previous_state = 'hard_locked'
         and p_payload->>'state' <> 'hard_locked' then
        raise exception using
          errcode = '55000',
          message = 'A hard-locked fiscal period cannot be reopened.';
      end if;
      if v_previous_state = 'open' and p_payload->>'state' = 'hard_locked' then
        raise exception using
          errcode = '55000',
          message = 'A fiscal period must be soft-locked before hard lock.';
      end if;
      update finance.fiscal_periods set
        name = trim(p_payload->>'name'),
        start_date = v_start_date,
        end_date = v_end_date,
        state = p_payload->>'state',
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into finance.fiscal_periods (
        id, tenant_id, legal_entity_id, name, start_date, end_date,
        state, status, created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_legal_entity_id, trim(p_payload->>'name'),
        v_start_date, v_end_date,
        coalesce(nullif(p_payload->>'state', ''), 'open'),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object('code', v_row.name);

  -- -------------------------------------------------------------------------
  -- Parties and catalogue
  -- -------------------------------------------------------------------------
  elsif p_resource = 'parties' then
    if coalesce(trim(p_payload->>'code'), '') = ''
       or coalesce(trim(p_payload->>'legal_name'), '') = ''
       or coalesce(trim(p_payload->>'display_name'), '') = '' then
      raise exception using errcode = '22023', message = 'Party code and names are required.';
    end if;

    if v_is_update then
      select to_jsonb(p), p.version into v_before, v_current_version
      from crm.parties as p
      where p.id = v_id and p.tenant_id = p_tenant_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Party was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update crm.parties set
        code = upper(trim(p_payload->>'code')),
        legal_name = trim(p_payload->>'legal_name'),
        display_name = trim(p_payload->>'display_name'),
        kind = p_payload->>'kind',
        tax_identifier = nullif(trim(p_payload->>'tax_identifier'), ''),
        email = nullif(lower(trim(p_payload->>'email')), ''),
        phone = nullif(trim(p_payload->>'phone'), ''),
        address_line_1 = nullif(trim(p_payload->>'address_line_1'), ''),
        address_line_2 = nullif(trim(p_payload->>'address_line_2'), ''),
        city = nullif(trim(p_payload->>'city'), ''),
        country_code = coalesce(nullif(upper(p_payload->>'country_code'), ''), 'LK'),
        credit_limit = coalesce((p_payload->>'credit_limit')::numeric, 0),
        credit_currency_code = coalesce(
          nullif(upper(p_payload->>'credit_currency_code'), ''), v_default_currency
        ),
        payment_terms_days = coalesce((p_payload->>'payment_terms_days')::integer, 0),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into crm.parties (
        id, tenant_id, code, legal_name, display_name, kind, tax_identifier,
        email, phone, address_line_1, address_line_2, city, country_code,
        credit_limit, credit_currency_code, payment_terms_days, status,
        created_by, updated_by
      ) values (
        v_id, p_tenant_id, upper(trim(p_payload->>'code')),
        trim(p_payload->>'legal_name'), trim(p_payload->>'display_name'),
        p_payload->>'kind', nullif(trim(p_payload->>'tax_identifier'), ''),
        nullif(lower(trim(p_payload->>'email')), ''),
        nullif(trim(p_payload->>'phone'), ''),
        nullif(trim(p_payload->>'address_line_1'), ''),
        nullif(trim(p_payload->>'address_line_2'), ''),
        nullif(trim(p_payload->>'city'), ''),
        coalesce(nullif(upper(p_payload->>'country_code'), ''), 'LK'),
        coalesce((p_payload->>'credit_limit')::numeric, 0),
        coalesce(nullif(upper(p_payload->>'credit_currency_code'), ''), v_default_currency),
        coalesce((p_payload->>'payment_terms_days')::integer, 0),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object(
      'name', v_row.display_name,
      'credit_limit', v_row.credit_limit::text
    );

  elsif p_resource = 'contacts' then
    v_parent_id := nullif(p_payload->>'party_id', '')::uuid;
    if coalesce(trim(p_payload->>'name'), '') = '' or v_parent_id is null then
      raise exception using errcode = '22023', message = 'Contact party and name are required.';
    end if;
    if not exists (
      select 1 from crm.parties as p
      where p.tenant_id = p_tenant_id and p.id = v_parent_id
    ) then
      raise exception using errcode = '22023', message = 'Contact party is invalid.';
    end if;
    if coalesce((p_payload->>'is_primary')::boolean, false)
       and coalesce(nullif(p_payload->>'status', ''), 'active') = 'active'
       and exists (
        select 1 from crm.contacts as c
        where c.tenant_id = p_tenant_id
          and c.party_id = v_parent_id
          and c.id <> v_id
          and c.is_primary
          and c.status = 'active'
      ) then
      raise exception using
        errcode = '22023',
        message = 'An active primary contact already exists.';
    end if;

    if v_is_update then
      select to_jsonb(c), c.version into v_before, v_current_version
      from crm.contacts as c
      where c.id = v_id and c.tenant_id = p_tenant_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Contact was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update crm.contacts set
        party_id = v_parent_id,
        name = trim(p_payload->>'name'),
        role = nullif(trim(p_payload->>'role'), ''),
        email = nullif(lower(trim(p_payload->>'email')), ''),
        phone = nullif(trim(p_payload->>'phone'), ''),
        is_primary = coalesce((p_payload->>'is_primary')::boolean, false),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into crm.contacts (
        id, tenant_id, party_id, name, role, email, phone,
        is_primary, status, created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_parent_id, trim(p_payload->>'name'),
        nullif(trim(p_payload->>'role'), ''),
        nullif(lower(trim(p_payload->>'email')), ''),
        nullif(trim(p_payload->>'phone'), ''),
        coalesce((p_payload->>'is_primary')::boolean, false),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object(
      'code', left(v_row.name, 24)
    );

  elsif p_resource = 'units' then
    if coalesce(trim(p_payload->>'code'), '') = ''
       or coalesce(trim(p_payload->>'name'), '') = ''
       or coalesce(trim(p_payload->>'symbol'), '') = '' then
      raise exception using errcode = '22023', message = 'Unit code, name, and symbol are required.';
    end if;

    if v_is_update then
      select to_jsonb(u), u.version into v_before, v_current_version
      from inventory.units as u
      where u.id = v_id and u.tenant_id = p_tenant_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Unit was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update inventory.units set
        code = upper(trim(p_payload->>'code')),
        name = trim(p_payload->>'name'),
        symbol = trim(p_payload->>'symbol'),
        category = p_payload->>'category',
        precision = coalesce((p_payload->>'precision')::smallint, 0),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into inventory.units (
        id, tenant_id, code, name, symbol, category, precision,
        status, created_by, updated_by
      ) values (
        v_id, p_tenant_id, upper(trim(p_payload->>'code')),
        trim(p_payload->>'name'), trim(p_payload->>'symbol'),
        p_payload->>'category', coalesce((p_payload->>'precision')::smallint, 0),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row);

  elsif p_resource = 'products' then
    v_parent_id := nullif(p_payload->>'base_unit_id', '')::uuid;
    if coalesce(trim(p_payload->>'sku'), '') = ''
       or coalesce(trim(p_payload->>'name'), '') = ''
       or v_parent_id is null then
      raise exception using errcode = '22023', message = 'Product SKU, name, and base unit are required.';
    end if;
    if not exists (
      select 1 from inventory.units as u
      where u.tenant_id = p_tenant_id
        and u.id = v_parent_id
        and u.status = 'active'
    ) then
      raise exception using errcode = '22023', message = 'Product base unit is invalid.';
    end if;

    if v_is_update then
      select to_jsonb(p), p.version into v_before, v_current_version
      from inventory.products as p
      where p.id = v_id
        and p.tenant_id = p_tenant_id
        and p.legal_entity_id = v_legal_entity_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Product was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update inventory.products set
        sku = upper(trim(p_payload->>'sku')),
        name = trim(p_payload->>'name'),
        description = nullif(trim(p_payload->>'description'), ''),
        kind = p_payload->>'kind',
        base_unit_id = v_parent_id,
        tracking_mode = coalesce(nullif(p_payload->>'tracking_mode', ''), 'none'),
        can_sell = coalesce((p_payload->>'can_sell')::boolean, true),
        can_purchase = coalesce((p_payload->>'can_purchase')::boolean, true),
        tax_definition_id = nullif(p_payload->>'tax_definition_id', '')::uuid,
        revenue_account_id = nullif(p_payload->>'revenue_account_id', '')::uuid,
        expense_account_id = nullif(p_payload->>'expense_account_id', '')::uuid,
        inventory_account_id = nullif(p_payload->>'inventory_account_id', '')::uuid,
        cogs_account_id = nullif(p_payload->>'cogs_account_id', '')::uuid,
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into inventory.products (
        id, tenant_id, legal_entity_id, sku, name, description, kind,
        base_unit_id, tracking_mode, can_sell, can_purchase,
        tax_definition_id, revenue_account_id, expense_account_id,
        inventory_account_id, cogs_account_id, status, created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_legal_entity_id,
        upper(trim(p_payload->>'sku')), trim(p_payload->>'name'),
        nullif(trim(p_payload->>'description'), ''), p_payload->>'kind',
        v_parent_id, coalesce(nullif(p_payload->>'tracking_mode', ''), 'none'),
        coalesce((p_payload->>'can_sell')::boolean, true),
        coalesce((p_payload->>'can_purchase')::boolean, true),
        nullif(p_payload->>'tax_definition_id', '')::uuid,
        nullif(p_payload->>'revenue_account_id', '')::uuid,
        nullif(p_payload->>'expense_account_id', '')::uuid,
        nullif(p_payload->>'inventory_account_id', '')::uuid,
        nullif(p_payload->>'cogs_account_id', '')::uuid,
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object('code', v_row.sku);

  -- -------------------------------------------------------------------------
  -- Numbering, workflow, and saved reports
  -- -------------------------------------------------------------------------
  elsif p_resource = 'document_sequences' then
    if coalesce(p_payload->>'document_type', '') !~ '^[a-z][a-z0-9_.-]{2,79}$' then
      raise exception using errcode = '22023', message = 'Document type is invalid.';
    end if;
    if coalesce((p_payload->>'padding')::integer, 6) not between 1 and 12 then
      raise exception using errcode = '22023', message = 'Document padding is invalid.';
    end if;
    if coalesce((p_payload->>'next_value')::bigint, 1) <= 0 then
      raise exception using errcode = '22023', message = 'Next document number must be positive.';
    end if;

    if v_is_update then
      select to_jsonb(ds), ds.version, ds.next_value
        into v_before, v_current_version, v_current_bigint
      from core.document_sequences as ds
      where ds.id = v_id and ds.tenant_id = p_tenant_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Document sequence was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update core.document_sequences set
        legal_entity_id = v_legal_entity_id,
        branch_id = v_branch_id,
        document_type = p_payload->>'document_type',
        prefix = coalesce(p_payload->>'prefix', ''),
        suffix = coalesce(p_payload->>'suffix', ''),
        padding = coalesce((p_payload->>'padding')::smallint, 6),
        reset_policy = coalesce(nullif(p_payload->>'reset_policy', ''), 'never'),
        next_value = coalesce((p_payload->>'next_value')::bigint, v_current_bigint),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into core.document_sequences (
        id, tenant_id, legal_entity_id, branch_id, document_type,
        prefix, suffix, padding, reset_policy, next_value, status,
        created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_legal_entity_id, v_branch_id,
        p_payload->>'document_type', coalesce(p_payload->>'prefix', ''),
        coalesce(p_payload->>'suffix', ''),
        coalesce((p_payload->>'padding')::smallint, 6),
        coalesce(nullif(p_payload->>'reset_policy', ''), 'never'),
        coalesce((p_payload->>'next_value')::bigint, 1),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object(
      'code', v_row.document_type,
      'name', replace(initcap(replace(v_row.document_type, '_', ' ')), '.', ' ')
    );

  elsif p_resource = 'workflow_definitions' then
    if coalesce(p_payload->>'document_type', '') !~ '^[a-z][a-z0-9_.-]{2,79}$'
       or coalesce(trim(p_payload->>'name'), '') = '' then
      raise exception using errcode = '22023', message = 'Workflow document type and name are required.';
    end if;
    if jsonb_typeof(p_payload->'lifecycle') <> 'object'
       or jsonb_typeof(p_payload->'lifecycle'->'states') <> 'array'
       or jsonb_typeof(p_payload->'lifecycle'->'transitions') <> 'array'
       or not ((p_payload->'lifecycle'->'states') @> '["draft","submitted","approved","rejected","posted","closed"]'::jsonb) then
      raise exception using errcode = '22023', message = 'Workflow lifecycle is invalid.';
    end if;

    if v_is_update then
      select to_jsonb(wd), wd.version, wd.revision
        into v_before, v_current_version, v_current_bigint
      from workflow.workflow_definitions as wd
      where wd.id = v_id and wd.tenant_id = p_tenant_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Workflow definition was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update workflow.workflow_definitions set
        legal_entity_id = v_legal_entity_id,
        document_type = p_payload->>'document_type',
        name = trim(p_payload->>'name'),
        revision = coalesce((p_payload->>'revision')::integer, v_current_bigint::integer),
        lifecycle = p_payload->'lifecycle',
        status = coalesce(nullif(p_payload->>'status', ''), 'draft'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into workflow.workflow_definitions (
        id, tenant_id, legal_entity_id, document_type, name, revision,
        lifecycle, status, created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_legal_entity_id, p_payload->>'document_type',
        trim(p_payload->>'name'), coalesce((p_payload->>'revision')::integer, 1),
        p_payload->'lifecycle', coalesce(nullif(p_payload->>'status', ''), 'draft'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object('code', v_row.document_type);

  elsif p_resource = 'approval_matrix_steps' then
    if v_workflow_id is null
       or nullif(p_payload->>'role_id', '')::uuid is null
       or coalesce((p_payload->>'step_order')::integer, 0) not between 1 and 100 then
      raise exception using errcode = '22023', message = 'Approval step scope and order are required.';
    end if;
    if not exists (
      select 1 from core.roles as r
      where r.tenant_id = p_tenant_id
        and r.id = (p_payload->>'role_id')::uuid
    ) then
      raise exception using errcode = '22023', message = 'Approval role is invalid.';
    end if;
    v_minimum := nullif(p_payload->>'minimum_amount', '')::numeric;
    v_maximum := nullif(p_payload->>'maximum_amount', '')::numeric;
    if v_minimum is not null and v_maximum is not null and v_minimum > v_maximum then
      raise exception using errcode = '22023', message = 'Approval amount range is invalid.';
    end if;
    if (v_minimum is not null or v_maximum is not null)
       and coalesce(p_payload->>'currency_code', '') !~ '^[A-Za-z]{3}$' then
      raise exception using errcode = '22023', message = 'Approval currency is required.';
    end if;
    if coalesce(nullif(p_payload->>'status', ''), 'active') = 'active'
       and exists (
        select 1 from workflow.approval_matrix_steps as am
        where am.tenant_id = p_tenant_id
          and am.workflow_definition_id = v_workflow_id
          and am.id <> v_id
          and am.status = 'active'
          and am.currency_code is not distinct from nullif(upper(p_payload->>'currency_code'), '')
          and numrange(am.minimum_amount, am.maximum_amount, '[]')
              && numrange(v_minimum, v_maximum, '[]')
      ) then
      raise exception using errcode = '22023', message = 'Approval amount ranges overlap.';
    end if;

    if v_is_update then
      select to_jsonb(am), am.version into v_before, v_current_version
      from workflow.approval_matrix_steps as am
      where am.id = v_id and am.tenant_id = p_tenant_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Approval step was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      update workflow.approval_matrix_steps set
        workflow_definition_id = v_workflow_id,
        role_id = (p_payload->>'role_id')::uuid,
        step_order = (p_payload->>'step_order')::integer,
        minimum_amount = v_minimum,
        maximum_amount = v_maximum,
        currency_code = nullif(upper(p_payload->>'currency_code'), ''),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into workflow.approval_matrix_steps (
        id, tenant_id, workflow_definition_id, role_id, step_order,
        minimum_amount, maximum_amount, currency_code, status,
        created_by, updated_by
      ) values (
        v_id, p_tenant_id, v_workflow_id, (p_payload->>'role_id')::uuid,
        (p_payload->>'step_order')::integer, v_minimum, v_maximum,
        nullif(upper(p_payload->>'currency_code'), ''),
        coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object(
      'code', 'STEP-' || v_row.step_order::text,
      'name', 'Approval step ' || v_row.step_order::text,
      'minimum_amount', case when v_row.minimum_amount is null then null else v_row.minimum_amount::text end,
      'maximum_amount', case when v_row.maximum_amount is null then null else v_row.maximum_amount::text end
    );

  elsif p_resource = 'report_definitions' then
    if coalesce(trim(p_payload->>'code'), '') = ''
       or coalesce(trim(p_payload->>'title'), '') = '' then
      raise exception using errcode = '22023', message = 'Report code and title are required.';
    end if;
    if not core.report_contract_allowed(
      p_payload->>'source_view',
      p_payload->'columns',
      coalesce(p_payload->'filters', '{}'::jsonb),
      coalesce(p_payload->'sort', '[]'::jsonb)
    ) then
      raise exception using
        errcode = '22023',
        message = 'Report source or columns are not allowed.';
    end if;

    if v_is_update then
      select to_jsonb(rd), rd.version, rd.owner_id
        into v_before, v_current_version, v_owner_id
      from core.report_definitions as rd
      where rd.id = v_id and rd.tenant_id = p_tenant_id
      for update;
      if v_before is null then
        raise exception using errcode = 'P0002', message = 'Report definition was not found.';
      end if;
      perform core.wave2_assert_expected_version(v_current_version, p_expected_version);
      if v_owner_id <> v_actor
         and not core.has_permission(p_tenant_id, 'analytics.reports.manage') then
        raise exception using errcode = '42501', message = 'Permission denied.';
      end if;
      update core.report_definitions set
        code = upper(trim(p_payload->>'code')),
        title = trim(p_payload->>'title'),
        source_view = p_payload->>'source_view',
        columns_json = p_payload->'columns',
        filters = coalesce(p_payload->'filters', '{}'::jsonb),
        sort_json = coalesce(p_payload->'sort', '[]'::jsonb),
        row_limit = coalesce((p_payload->>'row_limit')::integer, 100),
        is_shared = coalesce((p_payload->>'is_shared')::boolean, false),
        status = coalesce(nullif(p_payload->>'status', ''), 'active'),
        updated_by = v_actor
      where id = v_id
      returning * into v_row;
    else
      insert into core.report_definitions (
        id, tenant_id, code, title, source_view, columns_json,
        filters, sort_json, row_limit, is_shared, owner_id, status,
        created_by, updated_by
      ) values (
        v_id, p_tenant_id, upper(trim(p_payload->>'code')),
        trim(p_payload->>'title'), p_payload->>'source_view',
        p_payload->'columns', coalesce(p_payload->'filters', '{}'::jsonb),
        coalesce(p_payload->'sort', '[]'::jsonb),
        coalesce((p_payload->>'row_limit')::integer, 100),
        coalesce((p_payload->>'is_shared')::boolean, false),
        v_actor, coalesce(nullif(p_payload->>'status', ''), 'active'),
        v_actor, v_actor
      ) returning * into v_row;
    end if;
    v_entity := to_jsonb(v_row) || jsonb_build_object(
      'name', v_row.title,
      'columns', v_row.columns_json,
      'sort', v_row.sort_json
    ) - 'columns_json' - 'sort_json';
  end if;

  return core.wave2_finish_command(
    p_tenant_id,
    v_command_name,
    v_aggregate_type,
    v_id,
    p_idempotency_key,
    v_request_hash,
    v_before,
    v_entity,
    v_legal_entity_id,
    v_branch_id
  );
end;
$$;

revoke execute on function core.upsert_setup_record_impl(
  text, uuid, uuid, jsonb, bigint, uuid
) from public, anon, authenticated;
