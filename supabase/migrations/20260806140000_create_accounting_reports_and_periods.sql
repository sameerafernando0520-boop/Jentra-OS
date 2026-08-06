begin;

-- 1. Table: accounting_periods
create table public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period_name text not null,
  start_date date not null,
  end_date date not null,
  is_closed boolean not null default false,
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_periods_company_id_id_unique unique (company_id, id),
  constraint accounting_periods_period_name_not_blank check (btrim(period_name) <> ''),
  constraint accounting_periods_date_range_valid check (start_date <= end_date)
);

create index accounting_periods_company_dates_idx
  on public.accounting_periods (company_id, start_date, end_date);

create trigger set_accounting_periods_updated_at
before update on public.accounting_periods
for each row execute function private.set_updated_at();

alter table public.accounting_periods enable row level security;

create policy accounting_periods_select_member
  on public.accounting_periods for select to authenticated
  using (private.is_company_member(company_id));

create policy accounting_periods_insert_writer
  on public.accounting_periods for insert to authenticated
  with check (private.has_permission(company_id, 'finance.write'));

create policy accounting_periods_update_writer
  on public.accounting_periods for update to authenticated
  using (private.has_permission(company_id, 'finance.write'))
  with check (private.has_permission(company_id, 'finance.write'));

grant select, insert, update on public.accounting_periods to authenticated;
grant select, insert, update, delete on public.accounting_periods to service_role;

-- 2. Private Helper: check if a date falls in a closed accounting period
create or replace function private.is_period_closed(
  p_company_id uuid,
  p_date date
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_is_closed boolean := false;
begin
  select exists (
    select 1
    from public.accounting_periods
    where company_id = p_company_id
      and is_closed = true
      and p_date >= start_date
      and p_date <= end_date
  ) into v_is_closed;

  return v_is_closed;
end;
$$;

-- 3. Atomic RPC: post_manual_journal
create or replace function public.post_manual_journal(
  p_company_id uuid,
  p_entry_date date,
  p_narration text,
  p_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_journal_id uuid;
  v_entry_number text;
  v_line jsonb;
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
  v_line_count integer := 0;
  v_line_debit numeric;
  v_line_credit numeric;
  v_acc_id uuid;
  v_acc_code text;
  v_acc_name text;
begin
  -- 1. Permission check
  if not private.has_permission(p_company_id, 'finance.write') then
    raise exception 'Permission denied to post manual journals.'
      using errcode = '42501';
  end if;

  -- 2. Period lock check
  if private.is_period_closed(p_company_id, p_entry_date) then
    raise exception 'Cannot post journal into a closed accounting period.'
      using errcode = '22000';
  end if;

  -- 3. Validate line items array
  v_line_count := jsonb_array_length(p_lines);
  if v_line_count < 2 then
    raise exception 'A journal entry must contain at least two line items.';
  end if;

  -- 4. Calculate total debits & credits
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_debit := coalesce((v_line->>'debit')::numeric, 0);
    v_line_credit := coalesce((v_line->>'credit')::numeric, 0);
    if v_line_debit < 0 or v_line_credit < 0 then
      raise exception 'Journal line debit and credit amounts must be non-negative.';
    end if;
    v_total_debit := v_total_debit + v_line_debit;
    v_total_credit := v_total_credit + v_line_credit;
  end loop;

  -- 5. Balanced entry check (total debits == total credits)
  if abs(v_total_debit - v_total_credit) > 0.001 then
    raise exception 'Journal entry is not balanced. Total debits (%) must equal total credits (%).',
      v_total_debit, v_total_credit;
  end if;

  -- 6. Generate entry number
  select 'JRN-' || lpad((count(*) + 1001)::text, 5, '0')
  into v_entry_number
  from public.journal_entries
  where company_id = p_company_id;

  v_journal_id := gen_random_uuid();

  -- 7. Insert Header
  insert into public.journal_entries (
    id,
    company_id,
    entry_number,
    entry_date,
    source_type,
    source_id,
    narration,
    status,
    created_by
  ) values (
    v_journal_id,
    p_company_id,
    v_entry_number,
    p_entry_date,
    'manual',
    null,
    p_narration,
    'posted',
    auth.uid()
  );

  -- 8. Insert Lines
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_acc_code := btrim(coalesce(v_line->>'account_code', ''));
    v_acc_name := btrim(coalesce(v_line->>'account_name', ''));
    v_acc_id := nullif(v_line->>'account_id', '')::uuid;

    insert into public.journal_lines (
      company_id,
      journal_id,
      account_id,
      account_code,
      account_name,
      debit,
      credit,
      description
    ) values (
      p_company_id,
      v_journal_id,
      v_acc_id,
      v_acc_code,
      v_acc_name,
      coalesce((v_line->>'debit')::numeric, 0),
      coalesce((v_line->>'credit')::numeric, 0),
      v_line->>'description'
    );
  end loop;

  -- 9. Audit log entry
  perform private.log_audit_event(
    p_company_id,
    auth.uid(),
    'manual_journal.posted',
    'journal_entries',
    v_journal_id::text,
    jsonb_build_object(
      'entry_number', v_entry_number,
      'total_debit', v_total_debit,
      'total_credit', v_total_credit,
      'line_count', v_line_count
    )
  );

  return jsonb_build_object(
    'success', true,
    'journal_id', v_journal_id,
    'journal_number', v_entry_number,
    'total_amount', v_total_debit
  );
end;
$$;

revoke all on function public.post_manual_journal(uuid, date, text, jsonb) from public, anon;
grant execute on function public.post_manual_journal(uuid, date, text, jsonb) to authenticated, service_role;

-- 4. Atomic RPC: reverse_journal_entry
create or replace function public.reverse_journal_entry(
  p_company_id uuid,
  p_journal_id uuid,
  p_reversal_date date default current_date,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_orig_journal public.journal_entries;
  v_line record;
  v_reversal_id uuid;
  v_reversal_number text;
begin
  -- 1. Permission check
  if not private.has_permission(p_company_id, 'finance.write') then
    raise exception 'Permission denied to reverse journal entries.'
      using errcode = '42501';
  end if;

  -- 2. Period lock check
  if private.is_period_closed(p_company_id, p_reversal_date) then
    raise exception 'Cannot reverse journal into a closed accounting period.'
      using errcode = '22000';
  end if;

  -- 3. Fetch original journal header
  select * into v_orig_journal
  from public.journal_entries
  where company_id = p_company_id and id = p_journal_id;

  if v_orig_journal.id is null then
    raise exception 'Journal entry not found or does not belong to company.';
  end if;

  if v_orig_journal.status = 'reversed' then
    raise exception 'Journal entry is already reversed.';
  end if;

  -- 4. Generate reversal number
  select 'JRN-' || lpad((count(*) + 1001)::text, 5, '0')
  into v_reversal_number
  from public.journal_entries
  where company_id = p_company_id;

  v_reversal_id := gen_random_uuid();

  -- 5. Insert Reversing Header
  insert into public.journal_entries (
    id,
    company_id,
    entry_number,
    entry_date,
    source_type,
    source_id,
    narration,
    status,
    created_by
  ) values (
    v_reversal_id,
    p_company_id,
    v_reversal_number,
    p_reversal_date,
    'reversal',
    p_journal_id::text,
    'Reversal of ' || v_orig_journal.entry_number || coalesce(': ' || p_reason, ''),
    'posted',
    auth.uid()
  );

  -- 6. Insert Reversing Lines (Swap Debits and Credits)
  for v_line in
    select * from public.journal_lines
    where company_id = p_company_id and journal_id = p_journal_id
  loop
    insert into public.journal_lines (
      company_id,
      journal_id,
      account_id,
      account_code,
      account_name,
      debit,
      credit,
      description
    ) values (
      p_company_id,
      v_reversal_id,
      v_line.account_id,
      v_line.account_code,
      v_line.account_name,
      v_line.credit,
      v_line.debit,
      'Reversal: ' || coalesce(v_line.description, '')
    );
  end loop;

  -- 7. Update original journal status to reversed
  update public.journal_entries
  set status = 'reversed'
  where id = p_journal_id;

  -- 8. Audit log entry
  perform private.log_audit_event(
    p_company_id,
    auth.uid(),
    'journal.reversed',
    'journal_entries',
    p_journal_id::text,
    jsonb_build_object(
      'original_number', v_orig_journal.entry_number,
      'reversal_id', v_reversal_id,
      'reversal_number', v_reversal_number
    )
  );

  return jsonb_build_object(
    'success', true,
    'reversal_id', v_reversal_id,
    'reversal_number', v_reversal_number
  );
end;
$$;

revoke all on function public.reverse_journal_entry(uuid, uuid, date, text) from public, anon;
grant execute on function public.reverse_journal_entry(uuid, uuid, date, text) to authenticated, service_role;

-- 5. Report RPC: get_trial_balance
create or replace function public.get_trial_balance(
  p_company_id uuid,
  p_as_of_date date default current_date
)
returns table (
  account_code text,
  account_name text,
  account_type text,
  total_debit numeric,
  total_credit numeric,
  net_balance numeric
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if not private.is_company_member(p_company_id) then
    raise exception 'Permission denied.' using errcode = '42501';
  end if;

  return query
  select
    jl.account_code,
    jl.account_name,
    coalesce(ca.type, 'other') as account_type,
    sum(jl.debit) as total_debit,
    sum(jl.credit) as total_credit,
    sum(jl.debit - jl.credit) as net_balance
  from public.journal_lines jl
  join public.journal_entries je on je.id = jl.journal_id
  left join public.chart_of_accounts ca on ca.company_id = p_company_id and ca.code = jl.account_code
  where jl.company_id = p_company_id
    and je.entry_date <= p_as_of_date
    and je.status = 'posted'
  group by jl.account_code, jl.account_name, ca.type
  order by jl.account_code;
end;
$$;

revoke all on function public.get_trial_balance(uuid, date) from public, anon;
grant execute on function public.get_trial_balance(uuid, date) to authenticated, service_role;

-- 6. Report RPC: get_profit_and_loss
create or replace function public.get_profit_and_loss(
  p_company_id uuid,
  p_start_date date,
  p_end_date date
)
returns table (
  account_code text,
  account_name text,
  account_type text,
  amount numeric
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if not private.is_company_member(p_company_id) then
    raise exception 'Permission denied.' using errcode = '42501';
  end if;

  return query
  select
    jl.account_code,
    jl.account_name,
    ca.type as account_type,
    case
      when ca.type = 'revenue' then sum(jl.credit - jl.debit)
      when ca.type = 'expense' then sum(jl.debit - jl.credit)
      else sum(jl.credit - jl.debit)
    end as amount
  from public.journal_lines jl
  join public.journal_entries je on je.id = jl.journal_id
  join public.chart_of_accounts ca on ca.company_id = p_company_id and ca.code = jl.account_code
  where jl.company_id = p_company_id
    and ca.type in ('revenue', 'expense')
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
  group by jl.account_code, jl.account_name, ca.type
  order by ca.type desc, jl.account_code;
end;
$$;

revoke all on function public.get_profit_and_loss(uuid, date, date) from public, anon;
grant execute on function public.get_profit_and_loss(uuid, date, date) to authenticated, service_role;

-- 7. Report RPC: get_balance_sheet
create or replace function public.get_balance_sheet(
  p_company_id uuid,
  p_as_of_date date default current_date
)
returns table (
  account_code text,
  account_name text,
  account_type text,
  amount numeric
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if not private.is_company_member(p_company_id) then
    raise exception 'Permission denied.' using errcode = '42501';
  end if;

  return query
  select
    jl.account_code,
    jl.account_name,
    ca.type as account_type,
    case
      when ca.type = 'asset' then sum(jl.debit - jl.credit)
      when ca.type in ('liability', 'equity') then sum(jl.credit - jl.debit)
      else sum(jl.debit - jl.credit)
    end as amount
  from public.journal_lines jl
  join public.journal_entries je on je.id = jl.journal_id
  join public.chart_of_accounts ca on ca.company_id = p_company_id and ca.code = jl.account_code
  where jl.company_id = p_company_id
    and ca.type in ('asset', 'liability', 'equity')
    and je.entry_date <= p_as_of_date
    and je.status = 'posted'
  group by jl.account_code, jl.account_name, ca.type
  order by ca.type, jl.account_code;
end;
$$;

revoke all on function public.get_balance_sheet(uuid, date) from public, anon;
grant execute on function public.get_balance_sheet(uuid, date) to authenticated, service_role;

commit;
