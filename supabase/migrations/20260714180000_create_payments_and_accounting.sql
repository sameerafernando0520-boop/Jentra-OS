begin;

-- Table: money_accounts
create table public.money_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  account_type text not null default 'bank', -- 'cash', 'bank'
  account_number text,
  currency text not null default 'USD',
  balance numeric(18, 2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint money_accounts_company_id_id_unique unique (company_id, id),
  constraint money_accounts_name_not_blank check (btrim(name) <> '')
);

create index money_accounts_company_idx on public.money_accounts (company_id, is_active, name);

create trigger set_money_accounts_updated_at
before update on public.money_accounts
for each row execute function private.set_updated_at();

-- Table: chart_of_accounts
create table public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name text not null,
  type text not null, -- 'asset', 'liability', 'equity', 'revenue', 'expense'
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chart_of_accounts_company_id_id_unique unique (company_id, id),
  constraint chart_of_accounts_company_code_unique unique (company_id, code),
  constraint chart_of_accounts_code_not_blank check (btrim(code) <> ''),
  constraint chart_of_accounts_name_not_blank check (btrim(name) <> '')
);

create index chart_of_accounts_company_idx on public.chart_of_accounts (company_id, code);

create trigger set_chart_of_accounts_updated_at
before update on public.chart_of_accounts
for each row execute function private.set_updated_at();

-- Table: payments
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_number text not null,
  payment_type text not null default 'incoming', -- 'incoming', 'outgoing'
  party_id uuid references public.parties(id) on delete set null,
  money_account_id uuid references public.money_accounts(id) on delete set null,
  payment_method text not null default 'cash', -- 'cash', 'bank_transfer', 'check', 'card'
  amount numeric(18, 2) not null default 0,
  payment_date date not null default current_date,
  reference text,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_company_id_id_unique unique (company_id, id),
  constraint payments_amount_positive check (amount > 0),
  constraint payments_number_not_blank check (btrim(payment_number) <> '')
);

create index payments_company_date_idx on public.payments (company_id, payment_date desc, id);

create trigger set_payments_updated_at
before update on public.payments
for each row execute function private.set_updated_at();

-- Table: payment_allocations
create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  payment_id uuid not null references public.payments(id) on delete cascade,
  document_id uuid not null references public.sales_documents(id) on delete cascade,
  allocated_amount numeric(18, 2) not null default 0,
  created_at timestamptz not null default now(),
  constraint payment_allocations_company_id_id_unique unique (company_id, id),
  constraint payment_allocations_amount_positive check (allocated_amount > 0)
);

create index payment_allocations_company_doc_idx on public.payment_allocations (company_id, document_id);
create index payment_allocations_company_pmt_idx on public.payment_allocations (company_id, payment_id);

-- Table: journal_entries
create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entry_number text not null,
  entry_date date not null default current_date,
  source_type text not null, -- 'payment', 'invoice', etc.
  source_id text,
  narration text,
  status text not null default 'posted',
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint journal_entries_company_id_id_unique unique (company_id, id),
  constraint journal_entries_number_not_blank check (btrim(entry_number) <> '')
);

create index journal_entries_company_date_idx on public.journal_entries (company_id, entry_date desc, id);

create trigger set_journal_entries_updated_at
before update on public.journal_entries
for each row execute function private.set_updated_at();

-- Table: journal_lines
create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  journal_id uuid not null references public.journal_entries(id) on delete cascade,
  account_id uuid references public.chart_of_accounts(id) on delete set null,
  account_code text not null,
  account_name text not null,
  debit numeric(18, 2) not null default 0,
  credit numeric(18, 2) not null default 0,
  description text,
  created_at timestamptz not null default now(),
  constraint journal_lines_company_id_id_unique unique (company_id, id),
  constraint journal_lines_debit_nonnegative check (debit >= 0),
  constraint journal_lines_credit_nonnegative check (credit >= 0)
);

create index journal_lines_company_journal_idx on public.journal_lines (company_id, journal_id);

-- RLS setup
alter table public.money_accounts enable row level security;
alter table public.chart_of_accounts enable row level security;
alter table public.payments enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

-- RLS policies
create policy money_accounts_select_member
  on public.money_accounts for select to authenticated
  using (private.is_company_member(company_id));

create policy money_accounts_insert_writer
  on public.money_accounts for insert to authenticated
  with check (private.has_permission(company_id, 'finance.write'));

create policy money_accounts_update_writer
  on public.money_accounts for update to authenticated
  using (private.has_permission(company_id, 'finance.write'))
  with check (private.has_permission(company_id, 'finance.write'));

create policy chart_of_accounts_select_member
  on public.chart_of_accounts for select to authenticated
  using (private.is_company_member(company_id));

create policy chart_of_accounts_insert_writer
  on public.chart_of_accounts for insert to authenticated
  with check (private.has_permission(company_id, 'finance.write'));

create policy payments_select_member
  on public.payments for select to authenticated
  using (private.is_company_member(company_id));

create policy payments_insert_writer
  on public.payments for insert to authenticated
  with check (private.has_permission(company_id, 'finance.write'));

create policy payment_allocations_select_member
  on public.payment_allocations for select to authenticated
  using (private.is_company_member(company_id));

create policy payment_allocations_insert_writer
  on public.payment_allocations for insert to authenticated
  with check (private.has_permission(company_id, 'finance.write'));

create policy journal_entries_select_member
  on public.journal_entries for select to authenticated
  using (private.is_company_member(company_id));

create policy journal_entries_insert_writer
  on public.journal_entries for insert to authenticated
  with check (private.has_permission(company_id, 'finance.write'));

create policy journal_lines_select_member
  on public.journal_lines for select to authenticated
  using (private.is_company_member(company_id));

create policy journal_lines_insert_writer
  on public.journal_lines for insert to authenticated
  with check (private.has_permission(company_id, 'finance.write'));

-- Grants
grant select, insert, update on public.money_accounts to authenticated;
grant select, insert, update on public.chart_of_accounts to authenticated;
grant select, insert, update on public.payments to authenticated;
grant select, insert on public.payment_allocations to authenticated;
grant select, insert on public.journal_entries to authenticated;
grant select, insert on public.journal_lines to authenticated;

grant select, insert, update, delete on public.money_accounts to service_role;
grant select, insert, update, delete on public.chart_of_accounts to service_role;
grant select, insert, update, delete on public.payments to service_role;
grant select, insert, update, delete on public.payment_allocations to service_role;
grant select, insert, update, delete on public.journal_entries to service_role;
grant select, insert, update, delete on public.journal_lines to service_role;

-- Helper function to seed company accounts if missing
create or replace function private.ensure_company_default_accounts(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- Seed Chart of Accounts
  insert into public.chart_of_accounts (company_id, code, name, type)
  values
    (p_company_id, '1010', 'Cash Account', 'asset'),
    (p_company_id, '1020', 'Bank Account', 'asset'),
    (p_company_id, '1100', 'Accounts Receivable', 'asset'),
    (p_company_id, '4000', 'Sales Revenue', 'revenue')
  on conflict (company_id, code) do nothing;

  -- Seed Default Money Account if none exist
  if not exists (select 1 from public.money_accounts where company_id = p_company_id) then
    insert into public.money_accounts (company_id, name, account_type, currency, balance)
    values (p_company_id, 'Main Cash Account', 'cash', 'USD', 0);
  end if;
end;
$$;

-- Atomic RPC function: record_invoice_payment
create or replace function public.record_invoice_payment(
  p_company_id uuid,
  p_invoice_id uuid,
  p_money_account_id uuid,
  p_payment_method text,
  p_amount numeric,
  p_payment_date date default current_date,
  p_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_invoice public.sales_documents;
  v_money_acc public.money_accounts;
  v_payment_id uuid;
  v_journal_id uuid;
  v_payment_number text;
  v_journal_number text;
  v_new_paid_amount numeric;
  v_new_balance numeric;
  v_new_status public.sales_document_status;
  v_cash_acc_id uuid;
  v_ar_acc_id uuid;
  v_acc_code text;
  v_acc_name text;
begin
  -- 1. Permission check
  if not private.has_permission(p_company_id, 'finance.write') then
    raise exception 'Permission denied to record payments.'
      using errcode = '42501';
  end if;

  -- 2. Validate amount
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  -- 3. Fetch & lock invoice header
  select * into v_invoice
  from public.sales_documents
  where company_id = p_company_id
    and id = p_invoice_id
    and document_type = 'invoice'
  for update;

  if v_invoice.id is null then
    raise exception 'Invoice not found or does not belong to company.';
  end if;

  -- 4. Validate amount against outstanding balance
  if p_amount > (v_invoice.grand_total - v_invoice.paid_amount) + 0.001 then
    raise exception 'Payment amount (%) cannot be greater than outstanding balance (%).',
      p_amount, (v_invoice.grand_total - v_invoice.paid_amount);
  end if;

  -- 5. Ensure company default accounts exist
  perform private.ensure_company_default_accounts(p_company_id);

  -- 6. Fetch money account
  select * into v_money_acc
  from public.money_accounts
  where company_id = p_company_id and id = p_money_account_id;

  if v_money_acc.id is null then
    -- Fallback to first available money account
    select * into v_money_acc
    from public.money_accounts
    where company_id = p_company_id and is_active = true
    limit 1;
  end if;

  -- 7. Generate Payment Number & Record Payment
  select 'PMT-' || lpad((count(*) + 1001)::text, 5, '0')
  into v_payment_number
  from public.payments
  where company_id = p_company_id;

  v_payment_id := gen_random_uuid();

  insert into public.payments (
    id,
    company_id,
    payment_number,
    payment_type,
    party_id,
    money_account_id,
    payment_method,
    amount,
    payment_date,
    reference,
    notes
  ) values (
    v_payment_id,
    p_company_id,
    v_payment_number,
    'incoming',
    v_invoice.customer_id,
    v_money_acc.id,
    coalesce(p_payment_method, 'cash'),
    p_amount,
    p_payment_date,
    p_reference,
    p_notes
  );

  -- 8. Create Payment Allocation
  insert into public.payment_allocations (
    company_id,
    payment_id,
    document_id,
    allocated_amount
  ) values (
    p_company_id,
    v_payment_id,
    p_invoice_id,
    p_amount
  );

  -- 9. Update Sales Document Paid Amount & Status
  v_new_paid_amount := v_invoice.paid_amount + p_amount;
  v_new_balance := v_invoice.grand_total - v_new_paid_amount;
  if v_new_balance <= 0.001 then
    v_new_status := 'paid';
  else
    v_new_status := 'partially_paid';
  end if;

  update public.sales_documents
  set paid_amount = v_new_paid_amount,
      status = v_new_status
  where id = v_invoice.id;

  -- 10. Update Money Account Balance
  if v_money_acc.id is not null then
    update public.money_accounts
    set balance = balance + p_amount
    where id = v_money_acc.id;
  end if;

  -- 11. Post Double-Entry Journal Entry
  -- Debit: Cash/Bank Account (Asset)
  -- Credit: Accounts Receivable (Asset)
  select id, code, name into v_cash_acc_id, v_acc_code, v_acc_name
  from public.chart_of_accounts
  where company_id = p_company_id
    and code = case when coalesce(p_payment_method, 'cash') = 'cash' then '1010' else '1020' end
  limit 1;

  select id into v_ar_acc_id
  from public.chart_of_accounts
  where company_id = p_company_id and code = '1100'
  limit 1;

  select 'JRN-' || lpad((count(*) + 1001)::text, 5, '0')
  into v_journal_number
  from public.journal_entries
  where company_id = p_company_id;

  v_journal_id := gen_random_uuid();

  insert into public.journal_entries (
    id,
    company_id,
    entry_number,
    entry_date,
    source_type,
    source_id,
    narration,
    status
  ) values (
    v_journal_id,
    p_company_id,
    v_journal_number,
    p_payment_date,
    'payment',
    v_payment_id::text,
    'Customer payment recorded against invoice ' || v_invoice.document_number,
    'posted'
  );

  -- Debit line (Cash/Bank)
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
    v_cash_acc_id,
    coalesce(v_acc_code, '1010'),
    coalesce(v_acc_name, 'Cash Account'),
    p_amount,
    0,
    'Payment received for invoice ' || v_invoice.document_number
  );

  -- Credit line (Accounts Receivable)
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
    v_ar_acc_id,
    '1100',
    'Accounts Receivable',
    0,
    p_amount,
    'Settlement of invoice ' || v_invoice.document_number
  );

  return jsonb_build_object(
    'success', true,
    'payment_id', v_payment_id,
    'payment_number', v_payment_number,
    'journal_id', v_journal_id,
    'journal_number', v_journal_number,
    'invoice_status', v_new_status,
    'paid_amount', v_new_paid_amount,
    'balance_due', v_new_balance
  );
end;
$$;

revoke all on function public.record_invoice_payment(uuid, uuid, uuid, text, numeric, date, text, text) from public, anon;
grant execute on function public.record_invoice_payment(uuid, uuid, uuid, text, numeric, date, text, text) to authenticated, service_role;

commit;
