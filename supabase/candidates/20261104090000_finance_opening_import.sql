-- Governed customer/supplier opening-document import. Additive release candidate.
insert into core.permissions(code, module, description, privileged) values
  ('finance.openings.view', 'finance', 'View scoped opening balances.', true),
  ('finance.openings.prepare', 'finance', 'Prepare and submit opening imports.', true),
  ('finance.openings.approve', 'finance', 'Independently approve opening imports.', true),
  ('finance.openings.post', 'finance', 'Post approved opening imports.', true);

create table finance.opening_batches (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  status text not null check (status in ('draft','pending_approval','approved','posted','cancelled')),
  version bigint not null check (version > 0),
  input jsonb not null,
  snapshot jsonb not null,
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  approved_content_hash text,
  created_by uuid not null references auth.users(id),
  prepared_by uuid not null references auth.users(id),
  preparer_ids uuid[] not null,
  submitted_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  posted_by uuid references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  submitted_at timestamptz,
  approved_at timestamptz,
  posted_at timestamptz,
  unique (tenant_id, legal_entity_id, branch_id, id),
  foreign key (tenant_id, legal_entity_id) references core.legal_entities(tenant_id, id),
  foreign key (tenant_id, branch_id) references core.branches(tenant_id, id),
  check (status not in ('approved','posted') or
    (approved_by is not null and approved_at is not null and approved_content_hash = content_hash)),
  check ((status = 'posted') = (posted_at is not null and posted_by is not null))
);

create table finance.opening_lines (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  batch_id uuid not null,
  kind text not null check (kind in ('AR','AP')),
  source_system_key text not null,
  external_document_key text not null,
  party_id uuid not null,
  row_number integer not null check (row_number between 2 and 501),
  data jsonb not null,
  journal_entry_id uuid,
  open_item_id uuid,
  unique (batch_id, row_number),
  unique (batch_id, party_id, external_document_key),
  foreign key (tenant_id, legal_entity_id, branch_id, batch_id)
    references finance.opening_batches(tenant_id, legal_entity_id, branch_id, id),
  foreign key (tenant_id, party_id) references crm.parties(tenant_id, id),
  foreign key (tenant_id, journal_entry_id) references finance.journal_entries(tenant_id, id),
  foreign key (tenant_id, open_item_id) references finance.open_items(tenant_id, id),
  check ((journal_entry_id is null) = (open_item_id is null))
);

-- Drafts may overlap while being reviewed. The irreversible identity is global
-- within the intended company/branch/kind/source/party regardless of cutoff.
create unique index opening_posted_document_identity
  on finance.opening_lines
  (tenant_id, legal_entity_id, branch_id, kind, source_system_key, party_id, external_document_key)
  where open_item_id is not null;

alter table finance.opening_batches enable row level security;
alter table finance.opening_batches force row level security;
alter table finance.opening_lines enable row level security;
alter table finance.opening_lines force row level security;
revoke all on finance.opening_batches, finance.opening_lines from public, anon, authenticated, service_role;

create function finance.opening_protect_posted() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'opening_batches' then
    if old.status = 'posted' then
      raise exception using errcode = '55000', message = 'OPENING_POSTED_IMMUTABLE';
    end if;
  elsif old.open_item_id is not null then
    raise exception using errcode = '55000', message = 'OPENING_POSTED_IMMUTABLE';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;

create trigger opening_batch_immutable before update or delete on finance.opening_batches
  for each row execute function finance.opening_protect_posted();
create trigger opening_line_immutable before update or delete on finance.opening_lines
  for each row execute function finance.opening_protect_posted();

create function finance.opening_require_scope(t uuid, e uuid, b uuid, permission text, mfa boolean default false)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if t is null or e is null or b is null then
    raise exception using errcode = '42501', message = 'OPERATIONAL_SCOPE_REQUIRED';
  end if;
  perform core.wave3_require_scope(t, 'finance.openings.view', e, b);
  if permission <> 'finance.openings.view' then
    perform core.wave3_require_scope(t, permission, e, b);
  end if;
  if mfa then
    perform finance.period_require_recent_mfa();
  end if;
end $$;

create function finance.opening_issue(row_number integer, field_name text, code text, message text)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_array(jsonb_build_object(
    'row', row_number, 'field', field_name, 'code', code, 'message', message));
$$;

create function finance.opening_date(value jsonb) returns date
language plpgsql immutable set search_path = '' as $$
declare parsed date;
begin
  if jsonb_typeof(value) is distinct from 'string'
      or value #>> '{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    return null;
  end if;
  parsed := (value #>> '{}')::date;
  if to_char(parsed, 'YYYY-MM-DD') <> value #>> '{}' then
    return null;
  end if;
  return parsed;
exception when datetime_field_overflow or invalid_datetime_format then
  return null;
end $$;

create function finance.opening_amount(value jsonb, precision_scale integer) returns numeric
language sql immutable set search_path = '' as $$
  select case
    when jsonb_typeof(value) = 'string'
      and value #>> '{}' ~ '^-?[0-9]{1,14}(\.[0-9]{1,6})?$'
      then case when (value #>> '{}')::numeric=trunc((value #>> '{}')::numeric,precision_scale)
    then (value #>> '{}')::numeric(20,6) end
  end;
$$;

-- Resolve the actual control mapping and bind its revision. Its selected
-- account and the equity account are checked again against the journal rules.
create function finance.opening_control_mapping(t uuid, e uuid, kind text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case kind
    when 'AR' then (select jsonb_build_object('account_id', account_id, 'version', version)
      from finance.posting_mappings
      where tenant_id=t and legal_entity_id=e and purpose='receivable_control' and status='active')
    when 'AP' then (select jsonb_build_object('account_id', payable_account_id, 'version', version)
      from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e)
  end;
$$;

create function finance.opening_preview(t uuid, e uuid, b uuid, p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  issues jsonb := '[]';
  rows jsonb := '[]';
  normalized jsonb;
  source_row jsonb;
  row_number integer;
  row_ordinal bigint;
  batch_kind text := p->>'kind';
  source_system text := btrim(p->>'source_system');
  cutoff date := finance.opening_date(p->'cutoff_date');
  batch_currency text := p->>'currency_code';
  base_code text;
  base_scale integer;
  transaction_scale integer;
  mapping jsonb;
  control finance.accounts%rowtype;
  clearing finance.accounts%rowtype;
  period finance.fiscal_periods%rowtype;
  party crm.parties%rowtype;
  key_text text;
  document_number text;
  document_date date;
  due_date date;
  outstanding numeric;
  carrying numeric;
  legacy_original numeric;
  legacy_settled numeric;
  exchange_rate numeric;
  duplicate_key text;
  seen_keys text[] := '{}';
  total_outstanding numeric := 0.000000;
  total_carrying numeric := 0.000000;
  start_issue_count integer;
  total_rows integer := 0;
  totals jsonb;
begin
  if jsonb_typeof(p) is distinct from 'object' or octet_length(p::text) > 2097152 then
    return jsonb_build_object('valid', false, 'issues',
      finance.opening_issue(null,'file','OPENING_PAYLOAD_INVALID','Select a supported opening import file.'));
  end if;

  select entity.currency_code, least(entity.rounding_scale, currency.minor_units)
  into base_code, base_scale
  from core.legal_entities entity join core.currencies currency on currency.code=entity.currency_code
  where entity.tenant_id=t and entity.id=e and currency.active;
  -- Downstream AR/AP allocations enforce the entity's rounding scale.
  select least(currency.minor_units, entity.rounding_scale) into transaction_scale
  from core.currencies currency cross join core.legal_entities entity
  where currency.code=batch_currency and currency.active and entity.tenant_id=t and entity.id=e;

  if batch_kind is null or batch_kind not in ('AR','AP') then
    issues := issues || finance.opening_issue(null,'kind','OPENING_KIND_INVALID','Choose receivables or payables.');
  end if;
  if jsonb_typeof(p->'source_system') is distinct from 'string'
      or coalesce(length(source_system),0) not between 1 and 80 or source_system ~ '[[:cntrl:]]' then
    issues := issues || finance.opening_issue(null,'source_system','OPENING_SOURCE_INVALID','Enter the source system name.');
  end if;
  if cutoff is null or cutoff > (statement_timestamp() at time zone 'UTC')::date then
    issues := issues || finance.opening_issue(null,'cutoff_date','OPENING_CUTOFF_INVALID','Enter a cutoff date in YYYY-MM-DD format.');
  else
    select fp.* into period from finance.fiscal_periods fp where fp.tenant_id=t and fp.legal_entity_id=e
      and fp.status='active' and fp.state='open' and cutoff between fp.start_date and fp.end_date;
    if not found then
      issues := issues || finance.opening_issue(null,'cutoff_date','PERIOD_CLOSED','Select a cutoff in an open period.');
    end if;
  end if;
  if transaction_scale is null or base_scale is null then
    issues := issues || finance.opening_issue(null,'currency_code','OPENING_CURRENCY_INVALID','Choose an active transaction currency.');
  end if;
  if jsonb_typeof(p->'file_sha256') is distinct from 'string' or p->>'file_sha256' !~ '^[0-9a-f]{64}$' then
    issues := issues || finance.opening_issue(null,'file_sha256','OPENING_FILE_HASH_INVALID','Select the import file again.');
  end if;

  mapping := finance.opening_control_mapping(t,e,batch_kind);
  select a.* into control from finance.accounts a
  where a.tenant_id=t and a.legal_entity_id=e and a.id::text=p->>'control_account_id'
    and a.id::text=mapping->>'account_id' and a.status='active' and a.is_posting
    and a.account_type=case batch_kind when 'AR' then 'asset' else 'liability' end
    and (a.currency_code is null or a.currency_code=batch_currency);
  if not found then
    issues := issues || finance.opening_issue(null,'control_account_id','OPENING_CONTROL_INVALID',
      'Choose the active configured control account for this currency.');
  end if;
  select a.* into clearing from finance.accounts a
  where a.tenant_id=t and a.legal_entity_id=e and a.id::text=p->>'clearing_account_id'
    and a.status='active' and a.is_posting and a.account_type='equity'
    and (a.currency_code is null or a.currency_code=batch_currency);
  if not found then
    issues := issues || finance.opening_issue(null,'clearing_account_id','OPENING_CLEARING_INVALID',
      'Choose an active posting account of type equity for this currency.');
  end if;

  if jsonb_typeof(p->'lines') is distinct from 'array' then
    issues := issues || finance.opening_issue(null,'lines','OPENING_ROW_LIMIT','Include between 1 and 500 rows.');
  else
    total_rows := jsonb_array_length(p->'lines');
    if total_rows not between 1 and 500 then
      issues := issues || finance.opening_issue(null,'lines','OPENING_ROW_LIMIT','Include between 1 and 500 rows.');
    end if;
  end if;

  if total_rows between 1 and 500 then
    for source_row, row_ordinal in select value, ordinality from jsonb_array_elements(p->'lines') with ordinality
    loop
      row_number := row_ordinal::integer+1;
      start_issue_count := jsonb_array_length(issues);
      if jsonb_typeof(source_row) is distinct from 'object' then
        issues := issues || finance.opening_issue(row_number,'row','OPENING_ROW_INVALID','Supply an opening document row.');
        continue;
      end if;

      key_text := btrim(source_row->>'external_document_key');
      document_number := btrim(source_row->>'document_number');
      document_date := finance.opening_date(source_row->'document_date');
      due_date := finance.opening_date(source_row->'due_date');
      outstanding := finance.opening_amount(source_row->'outstanding_amount', transaction_scale);
      carrying := finance.opening_amount(source_row->'carrying_base_amount', base_scale);
      legacy_original := finance.opening_amount(source_row->'legacy_original_amount', transaction_scale);
      legacy_settled := finance.opening_amount(source_row->'legacy_settled_amount', transaction_scale);

      if jsonb_typeof(source_row->'external_document_key') is distinct from 'string'
          or coalesce(length(key_text),0) not between 1 and 140 or key_text ~ '[[:cntrl:]]' then
        issues := issues || finance.opening_issue(row_number,'external_document_key','OPENING_KEY_INVALID','Enter a stable source document key.');
      end if;
      if jsonb_typeof(source_row->'document_number') is distinct from 'string'
          or coalesce(length(document_number),0) not between 1 and 140 or document_number ~ '[[:cntrl:]]' then
        issues := issues || finance.opening_issue(row_number,'document_number','OPENING_DOCUMENT_NUMBER_INVALID','Enter the original document number.');
      end if;
      if document_date is null or document_date > cutoff then
        issues := issues || finance.opening_issue(row_number,'document_date','OPENING_DOCUMENT_DATE_INVALID','Enter the original date on or before cutoff.');
      end if;
      if due_date is null or due_date < document_date then
        issues := issues || finance.opening_issue(row_number,'due_date','OPENING_DUE_DATE_INVALID','Enter a due date on or after the original document date.');
      end if;
      if source_row->>'currency' is distinct from batch_currency or transaction_scale is null then
        issues := issues || finance.opening_issue(row_number,'currency','OPENING_ROW_CURRENCY_INVALID','Use the batch transaction currency.');
      end if;
      if outstanding is null or outstanding=0 then
        issues := issues || finance.opening_issue(row_number,'outstanding_amount','OPENING_OUTSTANDING_INVALID','Enter a nonzero exact amount in the transaction currency.');
      end if;
      if carrying is null or carrying=0 or sign(carrying)<>sign(outstanding)
          or (batch_currency=base_code and carrying<>outstanding) then
        issues := issues || finance.opening_issue(row_number,'carrying_base_amount','OPENING_CARRYING_INVALID','Enter the exact base carrying amount with the matching sign.');
      end if;
      if source_row->>'legacy_original_amount' is not null and legacy_original is null then
        issues := issues || finance.opening_issue(row_number,'legacy_original_amount','OPENING_LEGACY_AMOUNT_INVALID','Use an exact amount or leave this field empty.');
      end if;
      if source_row->>'legacy_settled_amount' is not null and legacy_settled is null then
        issues := issues || finance.opening_issue(row_number,'legacy_settled_amount','OPENING_LEGACY_AMOUNT_INVALID','Use an exact amount or leave this field empty.');
      end if;

      select pr.* into party from crm.parties pr
      where pr.tenant_id=t and pr.code=upper(btrim(source_row->>'party_code')) and pr.status='active'
        and pr.kind in ('both',case batch_kind when 'AR' then 'customer' when 'AP' then 'supplier' end);
      if not found or jsonb_typeof(source_row->'party_code') is distinct from 'string' then
        issues := issues || finance.opening_issue(row_number,'party_code','OPENING_PARTY_INVALID','Use the code of an active customer or supplier of the selected kind.');
      end if;

      if party.id is not null and key_text is not null and length(key_text) between 1 and 140 then
        duplicate_key := party.id::text || ':' || key_text;
        if duplicate_key = any(seen_keys) or exists (
          select 1 from finance.opening_lines line
          where line.tenant_id=t and line.legal_entity_id=e and line.branch_id=b
            and line.kind=batch_kind and line.source_system_key=lower(source_system)
            and line.party_id=party.id and line.external_document_key=key_text and line.open_item_id is not null
        ) then
          issues := issues || finance.opening_issue(row_number,'external_document_key','OPENING_DUPLICATE_DOCUMENT','This source document is already in the file or posted.');
        end if;
        seen_keys := array_append(seen_keys,duplicate_key);
      end if;

      if outstanding is not null and outstanding<>0 and carrying is not null then
        exchange_rate := round(abs(carrying/outstanding),10);
        if exchange_rate<=0 or exchange_rate>=10000000000 then
          issues := issues || finance.opening_issue(row_number,'carrying_base_amount','OPENING_RATE_RANGE','The implied carrying rate exceeds the supported precision.');
        end if;
      end if;
      if jsonb_array_length(issues)<>start_issue_count then
        continue;
      end if;

      rows := rows || jsonb_build_array(jsonb_build_object(
        'row_number',row_number,'external_document_key',key_text,'party_code',party.code,
        'party_id',party.id,'party_name',party.display_name,'party_version',party.version,
        'document_number',document_number,'document_date',document_date,'due_date',due_date,
        'currency',batch_currency,'outstanding_amount',outstanding::text,'carrying_base_amount',carrying::text,
        'exchange_rate',exchange_rate::text,'legacy_original_amount',legacy_original::text,
        'legacy_settled_amount',legacy_settled::text));
      total_outstanding := total_outstanding+outstanding;
      total_carrying := total_carrying+carrying;
    end loop;
  end if;

  totals := jsonb_build_object('row_count',total_rows,'outstanding_amount',total_outstanding::text,
    'carrying_base_amount',total_carrying::text);
  normalized := jsonb_build_object(
    'kind',batch_kind,'source_system',source_system,'cutoff_date',cutoff,'currency_code',batch_currency,
    'period_id',period.id,'period_version',period.version,
    'base_scale',base_scale,'transaction_scale',transaction_scale,
    'base_currency_code',base_code,'control_account_id',control.id,'clearing_account_id',clearing.id,
    'control_account_version',control.version,'clearing_account_version',clearing.version,
    'control_mapping_version',mapping->'version','file_sha256',p->>'file_sha256',
    'row_count',total_rows,'totals',totals,'lines',rows);
  return jsonb_build_object('valid',jsonb_array_length(issues)=0,'issues',issues,
    'entity',normalized,'totals',totals,
    'content_hash',case when jsonb_array_length(issues)=0
      then encode(extensions.digest(normalized::text,'sha256'),'hex') end);
end $$;

create function finance.opening_batch_entity(batch finance.opening_batches, include_lines boolean) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  result jsonb;
  lines jsonb;
begin
  result := (batch.snapshot - 'lines') || (to_jsonb(batch) - 'input' - 'snapshot' - 'approved_content_hash');
  if include_lines then
    select coalesce(jsonb_agg(line.data || jsonb_build_object(
      'id',line.id,'open_item_id',line.open_item_id,'journal_entry_id',line.journal_entry_id)
      order by line.row_number),'[]'::jsonb) into lines
    from finance.opening_lines line where line.batch_id=batch.id;
    result := result || jsonb_build_object('lines',lines);
    if batch.status='posted' then
      result := result || jsonb_build_object(
        'open_item_ids',(select jsonb_agg(value->'open_item_id' order by ordinality)
          from jsonb_array_elements(lines) with ordinality),
        'journal_entry_ids',(select jsonb_agg(value->'journal_entry_id' order by ordinality)
          from jsonb_array_elements(lines) with ordinality));
    end if;
  end if;
  return result;
end $$;

create function finance.opening_lock_batch(t uuid, e uuid, b uuid, batch_id uuid, idempotency_key uuid)
returns finance.opening_batches language plpgsql security definer set search_path = '' as $$
declare
  batch finance.opening_batches%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || idempotency_key::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(t::text || ':finance-opening:' || batch_id::text, 0));
  select * into batch from finance.opening_batches row
  where row.id=batch_id and row.tenant_id=t and row.legal_entity_id=e and row.branch_id=b for update;
  return batch;
end $$;

-- All source rows read during posting are held until the command commits.
-- Lock the period before accounts, matching the ordinary journal path.
create function finance.opening_lock_sources(batch finance.opening_batches, posting boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  source finance.opening_lines%rowtype;
begin
  if posting and batch.input->>'kind'='AR' then
    perform 1 from crm.parties p where p.tenant_id=batch.tenant_id and p.id in
      (select line.party_id from finance.opening_lines line where line.batch_id=batch.id)
      order by p.id for update;
  else
    perform 1 from crm.parties p where p.tenant_id=batch.tenant_id and p.id in
      (select line.party_id from finance.opening_lines line where line.batch_id=batch.id)
      order by p.id for share;
  end if;
  perform finance.wave3_lock_open_period(batch.tenant_id,batch.legal_entity_id,(batch.input->>'cutoff_date')::date);
  perform 1 from core.legal_entities e where e.tenant_id=batch.tenant_id and e.id=batch.legal_entity_id for share;
  perform 1 from core.currencies c where c.code in
    (batch.snapshot->>'currency_code',batch.snapshot->>'base_currency_code') order by c.code for share;
  if batch.input->>'kind'='AR' then
    perform 1 from finance.posting_mappings m where m.tenant_id=batch.tenant_id
      and m.legal_entity_id=batch.legal_entity_id and m.purpose='receivable_control' for share;
  else
    perform 1 from procurement.supplier_bill_controls c
      where c.tenant_id=batch.tenant_id and c.legal_entity_id=batch.legal_entity_id for share;
  end if;
  perform 1 from finance.accounts a where a.tenant_id=batch.tenant_id and a.legal_entity_id=batch.legal_entity_id
    and a.id in ((batch.input->>'control_account_id')::uuid,(batch.input->>'clearing_account_id')::uuid)
    order by a.id for share;
  if posting then
    for source in
      select * from finance.opening_lines line where line.batch_id=batch.id
      order by line.party_id,line.external_document_key
    loop
      perform pg_advisory_xact_lock(hashtextextended(jsonb_build_array(
        source.tenant_id,source.legal_entity_id,source.branch_id,source.kind,
        source.source_system_key,source.party_id,source.external_document_key)::text,0));
    end loop;
  end if;
end $$;

create function finance.opening_require_snapshot(batch finance.opening_batches) returns void
language plpgsql stable security definer set search_path = '' as $$
declare
  preview jsonb;
begin
  preview := finance.opening_preview(batch.tenant_id,batch.legal_entity_id,batch.branch_id,batch.input);
  if exists (select 1 from jsonb_array_elements(preview->'issues') item where item->>'code'='OPENING_DUPLICATE_DOCUMENT') then
    raise exception using errcode = '23505', message = 'OPENING_DUPLICATE_DOCUMENT';
  end if;
  if exists (select 1 from jsonb_array_elements(preview->'issues') item where item->>'code'='PERIOD_CLOSED') then
    raise exception using errcode = '55000', message = 'PERIOD_CLOSED';
  end if;
  if preview->>'content_hash' is distinct from batch.content_hash then
    raise exception using errcode = '40001', message = 'OPENING_SOURCE_CHANGED';
  end if;
end $$;

create function api.preview_finance_opening_batch(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_payload jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.prepare');
  return finance.opening_preview(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
end $$;

create function api.upsert_finance_opening_batch(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
  p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  command_name constant text := 'finance.opening.upsert';
  batch_id uuid := coalesce((p_payload->>'id')::uuid,p_command_id);
  batch finance.opening_batches%rowtype;
  preview jsonb;
  v_snapshot jsonb;
  line_ids jsonb;
  previous jsonb;
  request_hash text;
  replay jsonb;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.prepare',true);
  if batch_id is null or p_client_timestamp is null or p_command_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'OPENING_COMMAND_INVALID';
  end if;
  batch := finance.opening_lock_batch(p_tenant_id,p_legal_entity_id,p_branch_id,batch_id,p_idempotency_key);
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.prepare',true);
  request_hash := core.wave3_request_hash(command_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,
    p_payload,p_expected_entity_version);
  replay := core.wave3_replay(p_tenant_id,command_name,p_command_id,p_idempotency_key,request_hash);
  if replay is not null then
    return replay;
  end if;

  preview := finance.opening_preview(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);
  if not (preview->>'valid')::boolean then
    raise exception using errcode = '22023', message = 'OPENING_VALIDATION_FAILED', detail = (preview->'issues')::text;
  end if;
  v_snapshot := preview->'entity';
  if batch.id is not null then
    perform core.wave3_assert_expected_version(batch.version,p_expected_entity_version,finance.opening_batch_entity(batch,false));
    if batch.status<>'draft' then
      raise exception using errcode = '55000', message = 'OPENING_DRAFT_REQUIRED';
    end if;
    previous := finance.opening_batch_entity(batch,false);
    select coalesce(jsonb_object_agg(jsonb_build_array(party_id,external_document_key)::text,id),'{}')
    into line_ids from finance.opening_lines line where line.batch_id=batch.id;
    delete from finance.opening_lines line where line.batch_id=batch.id;
    update finance.opening_batches row
    set input=p_payload,snapshot=v_snapshot,content_hash=preview->>'content_hash',prepared_by=auth.uid(),
        preparer_ids=case when auth.uid()=any(row.preparer_ids) then row.preparer_ids
          else array_append(row.preparer_ids,auth.uid()) end,
        version=row.version+1,updated_at=clock_timestamp()
    where row.id=batch.id returning * into batch;
  else
    if p_expected_entity_version is not null and p_expected_entity_version<>0 then
      raise exception using errcode = '40001', message = 'VERSION_CONFLICT';
    end if;
    insert into finance.opening_batches(id,tenant_id,legal_entity_id,branch_id,status,version,input,snapshot,
      content_hash,created_by,prepared_by,preparer_ids)
    values(batch_id,p_tenant_id,p_legal_entity_id,p_branch_id,'draft',1,p_payload,v_snapshot,
      preview->>'content_hash',auth.uid(),auth.uid(),array[auth.uid()]) returning * into batch;
  end if;
  insert into finance.opening_lines(id,tenant_id,legal_entity_id,branch_id,batch_id,kind,source_system_key,
    external_document_key,party_id,row_number,data)
  select coalesce((line_ids->>jsonb_build_array(value->'party_id',value->'external_document_key')::text)::uuid,gen_random_uuid()),
    batch.tenant_id,batch.legal_entity_id,batch.branch_id,batch.id,v_snapshot->>'kind',lower(v_snapshot->>'source_system'),
    value->>'external_document_key',(value->>'party_id')::uuid,(value->>'row_number')::integer,value
  from jsonb_array_elements(v_snapshot->'lines');
  return core.wave3_finish_command(p_tenant_id,command_name,p_command_id,'finance_opening',batch.id,
    p_idempotency_key,request_hash,previous,finance.opening_batch_entity(batch,true),p_legal_entity_id,p_branch_id);
end $$;

create function api.transition_finance_opening_batch(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
  p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  action text := p_payload->>'action';
  reason text := btrim(p_payload->>'reason');
  batch_id uuid := (p_payload->>'document_id')::uuid;
  batch finance.opening_batches%rowtype;
  command_name text;
  permission text;
  next_status text;
  previous jsonb;
  request_hash text;
  replay jsonb;
begin
  if action is null or action not in ('submit','approve','reject','recall','cancel')
      or batch_id is null or p_client_timestamp is null or p_command_id is null or p_idempotency_key is null
      or coalesce(length(reason),0)>1000
      or (action in ('reject','recall','cancel') and coalesce(length(reason),0)<3) then
    raise exception using errcode = '22023', message = 'OPENING_COMMAND_INVALID';
  end if;
  permission := case when action in ('approve','reject') then 'finance.openings.approve' else 'finance.openings.prepare' end;
  command_name := 'finance.opening.' || action;
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,permission,true);
  batch := finance.opening_lock_batch(p_tenant_id,p_legal_entity_id,p_branch_id,batch_id,p_idempotency_key);
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,permission,true);
  request_hash := core.wave3_request_hash(command_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,
    p_payload,p_expected_entity_version);
  replay := core.wave3_replay(p_tenant_id,command_name,p_command_id,p_idempotency_key,request_hash);
  if replay is not null then
    return replay;
  end if;
  if batch.id is null then
    raise exception using errcode = 'P0002', message = 'OPENING_BATCH_NOT_FOUND';
  end if;
  perform core.wave3_assert_expected_version(batch.version,p_expected_entity_version,finance.opening_batch_entity(batch,false));
  previous := finance.opening_batch_entity(batch,false);

  if action='submit' and batch.status='draft' then
    next_status := 'pending_approval';
  elsif action in ('approve','reject') and batch.status='pending_approval' then
    if auth.uid()=any(batch.preparer_ids) or auth.uid()=batch.submitted_by then
      raise exception using errcode = '42501', message = 'SEGREGATION_OF_DUTIES_VIOLATION';
    end if;
    next_status := case action when 'approve' then 'approved' else 'draft' end;
  elsif action='recall' and batch.status in ('pending_approval','approved') then
    next_status := 'draft';
  elsif action='cancel' and batch.status in ('draft','pending_approval','approved') then
    next_status := 'cancelled';
  else
    raise exception using errcode = '55000', message = 'OPENING_TRANSITION_INVALID';
  end if;
  if action in ('submit','approve') then
    perform finance.opening_lock_sources(batch,false);
    perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,permission,true);
    perform finance.opening_require_snapshot(batch);
  end if;

  update finance.opening_batches row
  set status=next_status,version=row.version+1,updated_at=clock_timestamp(),
      submitted_by=case when action='submit' then auth.uid() when next_status='draft' then null else row.submitted_by end,
      submitted_at=case when action='submit' then clock_timestamp() when next_status='draft' then null else row.submitted_at end,
      approved_by=case when action='approve' then auth.uid() else null end,
      approved_at=case when action='approve' then clock_timestamp() else null end,
      approved_content_hash=case when action='approve' then row.content_hash else null end
  where row.id=batch.id returning * into batch;
  return core.wave3_finish_command(p_tenant_id,command_name,p_command_id,'finance_opening',batch.id,
    p_idempotency_key,request_hash,previous,finance.opening_batch_entity(batch,true),p_legal_entity_id,p_branch_id,
    '{}',jsonb_build_object('from_status',previous->>'status','to_status',next_status,'reason',reason));
end $$;

create function api.post_finance_opening_batch(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,
  p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  command_name constant text := 'finance.opening.post';
  batch_id uuid := (p_payload->>'document_id')::uuid;
  batch finance.opening_batches%rowtype;
  source finance.opening_lines%rowtype;
  previous jsonb;
  request_hash text;
  replay jsonb;
  request_id uuid := gen_random_uuid();
  source_type text;
  journal_id uuid;
  item_id uuid;
  party_id uuid;
  transaction_amount numeric;
  carrying_amount numeric;
  direction integer;
  journal_document jsonb;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.post',true);
  if batch_id is null or p_client_timestamp is null or p_command_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'OPENING_COMMAND_INVALID';
  end if;
  batch := finance.opening_lock_batch(p_tenant_id,p_legal_entity_id,p_branch_id,batch_id,p_idempotency_key);
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.post',true);
  request_hash := core.wave3_request_hash(command_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,
    p_payload,p_expected_entity_version);
  replay := core.wave3_replay(p_tenant_id,command_name,p_command_id,p_idempotency_key,request_hash);
  if replay is not null then
    return replay;
  end if;
  if batch.id is null then
    raise exception using errcode = 'P0002', message = 'OPENING_BATCH_NOT_FOUND';
  end if;
  perform core.wave3_assert_expected_version(batch.version,p_expected_entity_version,finance.opening_batch_entity(batch,false));
  if batch.status<>'approved' or batch.approved_content_hash is distinct from batch.content_hash then
    raise exception using errcode = '55000', message = 'OPENING_APPROVAL_REQUIRED';
  end if;
  previous := finance.opening_batch_entity(batch,false);
  perform finance.opening_lock_sources(batch,true);
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.post',true);
  perform finance.opening_require_snapshot(batch);
  direction := case batch.input->>'kind' when 'AR' then 1 else -1 end;
  source_type := case direction when 1 then 'opening_receivable' else 'opening_payable' end;
  for source in select * from finance.opening_lines line where line.batch_id=batch.id order by line.row_number
  loop
    transaction_amount := (source.data->>'outstanding_amount')::numeric;
    carrying_amount := (source.data->>'carrying_base_amount')::numeric;
    journal_document := jsonb_build_object(
      'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
      'document_date',batch.input->>'cutoff_date','customer_id',source.party_id,
      'currency_code',batch.snapshot->>'currency_code','base_currency_code',batch.snapshot->>'base_currency_code',
      'exchange_rate',source.data->>'exchange_rate');
    journal_id := finance.flow_post_journal(journal_document,jsonb_build_array(
      finance.flow_jline((batch.snapshot->>'control_account_id')::uuid,direction*transaction_amount,direction*carrying_amount,source.id),
      finance.flow_jline((batch.snapshot->>'clearing_account_id')::uuid,-direction*transaction_amount,-direction*carrying_amount,source.id)
    ),source_type,source.id,request_id,p_command_id);
    insert into finance.open_items(tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,
      document_number,currency_code,base_currency_code,exchange_rate,original_amount,original_base_amount,
      posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
    values(p_tenant_id,p_legal_entity_id,p_branch_id,source.kind,source.party_id,source_type,source.id,
      source.data->>'document_number',batch.snapshot->>'currency_code',batch.snapshot->>'base_currency_code',
      (source.data->>'exchange_rate')::numeric,transaction_amount,carrying_amount,(batch.input->>'cutoff_date')::date,
      (source.data->>'due_date')::date,journal_id,request_id,p_command_id,request_id,auth.uid())
    returning id into item_id;
    update finance.opening_lines set journal_entry_id=journal_id,open_item_id=item_id where id=source.id;
  end loop;
  if direction=1 then
    for party_id in select distinct line.party_id from finance.opening_lines line where line.batch_id=batch.id order by line.party_id
    loop
      perform finance.flow_refresh_credit(jsonb_build_object(
        'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'customer_id',party_id));
    end loop;
  end if;
  -- Sequencing, credit refresh and row updates can wait on shared locks.
  -- Recheck the caller before finalizing. An error rolls back every posting.
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.post',true);
  update finance.opening_batches row
  set status='posted',version=row.version+1,updated_at=clock_timestamp(),posted_at=clock_timestamp(),posted_by=auth.uid()
  where row.id=batch.id returning * into batch;
  return core.wave3_finish_command(p_tenant_id,command_name,p_command_id,'finance_opening',batch.id,
    p_idempotency_key,request_hash,previous,finance.opening_batch_entity(batch,true),p_legal_entity_id,p_branch_id,
    '{}',jsonb_build_object('from_status','approved','to_status','posted'),'[]','[]',request_id,request_id);
end $$;

create function api.finance_opening_batch(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare batch finance.opening_batches%rowtype;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.view');
  select * into batch from finance.opening_batches
  where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'OPENING_BATCH_NOT_FOUND';
  end if;
  return finance.opening_batch_entity(batch,true);
end $$;

create function api.finance_opening_batches(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare items jsonb; next_cursor uuid;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.view');
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception using errcode = '22023', message = 'OPENING_PAGE_INVALID';
  end if;
  select coalesce(jsonb_agg(finance.opening_batch_entity(q.batch,false) order by q.id),'[]') into items
  from (select batch.id,batch from finance.opening_batches batch
    where batch.tenant_id=p_tenant_id and batch.legal_entity_id=p_legal_entity_id and batch.branch_id=p_branch_id
      and (p_after is null or batch.id>p_after)
    order by batch.id limit p_limit+1) q;
  if jsonb_array_length(items)>p_limit then
    items := items-p_limit;
    next_cursor := (items->(p_limit-1)->>'id')::uuid;
  end if;
  return jsonb_build_object('items',items,'next_cursor',next_cursor);
end $$;

create function api.finance_opening_source(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_source_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare source jsonb;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.view');
  select line.data || jsonb_build_object(
    'id',line.id,'batch_id',batch.id,'kind',line.kind,
    'cutoff_date',batch.snapshot->'cutoff_date','source_system',batch.snapshot->'source_system',
    'base_currency_code',batch.snapshot->'base_currency_code','file_sha256',batch.snapshot->'file_sha256',
    'posted_at',batch.posted_at,'journal_entry_id',line.journal_entry_id,'open_item_id',line.open_item_id)
  into source from finance.opening_lines line join finance.opening_batches batch on batch.id=line.batch_id
  where line.tenant_id=p_tenant_id and line.legal_entity_id=p_legal_entity_id and line.branch_id=p_branch_id
    and line.id=p_source_id and batch.status='posted';
  if not found then
    raise exception using errcode = 'P0002', message = 'OPENING_SOURCE_NOT_FOUND';
  end if;
  return source;
end $$;

create function api.finance_opening_reference_options(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_currency_code text,
  p_resource text,p_after text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  items jsonb;
  next_cursor text;
  base_currency text;
  base_scale integer;
  entity_scale integer;
  control_id text;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.view');
  if p_limit is null or p_limit not between 1 and 50 or p_kind is null or p_kind not in ('AR','AP')
      or p_resource is null or p_resource not in ('control_accounts','clearing_accounts','currencies','parties')
      or coalesce(length(p_after),0)>36 then
    raise exception using errcode = '22023', message = 'OPENING_REFERENCE_INVALID';
  end if;
  select entity.currency_code,least(entity.rounding_scale,currency.minor_units),entity.rounding_scale
    into base_currency,base_scale,entity_scale
  from core.legal_entities entity join core.currencies currency on currency.code=entity.currency_code
  where entity.tenant_id=p_tenant_id and entity.id=p_legal_entity_id;
  if p_resource='currencies' then
    select coalesce(jsonb_agg(jsonb_build_object('id',code,'code',code,'name',name,'minor_units',minor_units) order by code),'[]')
      into items
    from (select code,name,least(minor_units,entity_scale) as minor_units from core.currencies
      where active and (p_after is null or code>p_after) order by code limit p_limit+1) currency;
  elsif p_resource='parties' then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'code',code,'name',display_name,'version',version) order by id),'[]')
      into items
    from (select id,code,display_name,version from crm.parties where tenant_id=p_tenant_id and status='active'
      and kind in ('both',case p_kind when 'AR' then 'customer' else 'supplier' end)
      and (p_after is null or id::text>p_after) order by id limit p_limit+1) party;
  else
    control_id := finance.opening_control_mapping(p_tenant_id,p_legal_entity_id,p_kind)->>'account_id';
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'version',version) order by id),'[]')
      into items
    from (select id,code,name,version from finance.accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
      and status='active' and is_posting and (currency_code is null or currency_code=p_currency_code)
      and (p_after is null or id::text>p_after)
      and ((p_resource='control_accounts' and id::text=control_id and account_type=case p_kind when 'AR' then 'asset' else 'liability' end)
        or (p_resource='clearing_accounts' and account_type='equity'))
      order by id limit p_limit+1) account;
  end if;
  if jsonb_array_length(items)>p_limit then
    items := items-p_limit;
    next_cursor := items->(p_limit-1)->>'id';
  end if;
  return jsonb_build_object('items',items,'next_cursor',next_cursor,
    'base_currency_code',base_currency,'base_scale',base_scale);
end $$;

revoke all on function
  finance.opening_protect_posted(),finance.opening_require_scope(uuid,uuid,uuid,text,boolean),
  finance.opening_issue(integer,text,text,text),finance.opening_date(jsonb),finance.opening_amount(jsonb,integer),
  finance.opening_control_mapping(uuid,uuid,text),finance.opening_preview(uuid,uuid,uuid,jsonb),
  finance.opening_batch_entity(finance.opening_batches,boolean),finance.opening_lock_batch(uuid,uuid,uuid,uuid,uuid),
  finance.opening_lock_sources(finance.opening_batches,boolean),finance.opening_require_snapshot(finance.opening_batches)
from public,anon,authenticated,service_role;

revoke all on function
  api.preview_finance_opening_batch(uuid,uuid,uuid,jsonb),
  api.upsert_finance_opening_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.transition_finance_opening_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.post_finance_opening_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.finance_opening_batch(uuid,uuid,uuid,uuid),api.finance_opening_batches(uuid,uuid,uuid,uuid,integer),
  api.finance_opening_source(uuid,uuid,uuid,uuid),
  api.finance_opening_reference_options(uuid,uuid,uuid,text,text,text,text,integer)
from public,anon,authenticated,service_role;
grant execute on function
  api.preview_finance_opening_batch(uuid,uuid,uuid,jsonb),
  api.upsert_finance_opening_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.transition_finance_opening_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.post_finance_opening_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.finance_opening_batch(uuid,uuid,uuid,uuid),api.finance_opening_batches(uuid,uuid,uuid,uuid,integer),
  api.finance_opening_source(uuid,uuid,uuid,uuid),
  api.finance_opening_reference_options(uuid,uuid,uuid,text,text,text,text,integer)
to authenticated;
