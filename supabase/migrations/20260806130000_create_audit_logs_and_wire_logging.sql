begin;

-- 1. Create audit_logs table
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint audit_logs_company_id_id_unique unique (company_id, id),
  constraint audit_logs_action_not_blank check (btrim(action) <> ''),
  constraint audit_logs_entity_type_not_blank check (btrim(entity_type) <> ''),
  constraint audit_logs_entity_id_not_blank check (btrim(entity_id) <> '')
);

create index audit_logs_company_created_idx
  on public.audit_logs (company_id, created_at desc, id);

create index audit_logs_company_entity_idx
  on public.audit_logs (company_id, entity_type, entity_id);

-- RLS setup
alter table public.audit_logs enable row level security;

create policy audit_logs_select_member
  on public.audit_logs for select to authenticated
  using (private.is_company_member(company_id));

grant select on public.audit_logs to authenticated;
grant select, insert, update, delete on public.audit_logs to service_role;

-- 2. Create private audit helper function
create or replace function private.log_audit_event(
  p_company_id uuid,
  p_actor_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id text,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_log_id uuid := gen_random_uuid();
begin
  insert into public.audit_logs (
    id,
    company_id,
    actor_id,
    action,
    entity_type,
    entity_id,
    payload
  ) values (
    v_log_id,
    p_company_id,
    p_actor_id,
    p_action,
    p_entity_type,
    p_entity_id,
    coalesce(p_payload, '{}'::jsonb)
  );

  return v_log_id;
end;
$$;

-- 3. Update save_sales_invoice RPC with audit logging
create or replace function public.save_sales_invoice(
  p_company_id uuid,
  p_invoice_id uuid default null,
  p_customer_id uuid default null,
  p_document_number text default null,
  p_status text default 'draft',
  p_issue_date date default current_date,
  p_due_date date default null,
  p_subtotal numeric default 0,
  p_discount_amount numeric default 0,
  p_tax_amount numeric default 0,
  p_grand_total numeric default 0,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns public.sales_documents
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_invoice public.sales_documents;
  v_item jsonb;
  v_number text;
  v_target_id uuid;
  v_status_enum public.sales_document_status;
begin
  -- Permission check
  if not private.has_permission(p_company_id, 'sales.write') then
    raise exception 'Permission denied to create or update sales invoices.'
      using errcode = '42501';
  end if;

  v_target_id := coalesce(p_invoice_id, gen_random_uuid());
  v_status_enum := coalesce(p_status, 'draft')::public.sales_document_status;

  -- Generate document number if missing
  if p_document_number is null or btrim(p_document_number) = '' then
    select 'INV-' || lpad((count(*) + 1001)::text, 5, '0')
    into v_number
    from public.sales_documents
    where company_id = p_company_id and document_type = 'invoice';
  else
    v_number := btrim(p_document_number);
  end if;

  -- Insert or update header
  insert into public.sales_documents (
    id,
    company_id,
    customer_id,
    document_type,
    document_number,
    status,
    issue_date,
    due_date,
    subtotal,
    discount_amount,
    tax_amount,
    grand_total,
    notes
  ) values (
    v_target_id,
    p_company_id,
    p_customer_id,
    'invoice',
    v_number,
    v_status_enum,
    p_issue_date,
    p_due_date,
    p_subtotal,
    p_discount_amount,
    p_tax_amount,
    p_grand_total,
    p_notes
  )
  on conflict (company_id, id) do update set
    customer_id = excluded.customer_id,
    status = excluded.status,
    issue_date = excluded.issue_date,
    due_date = excluded.due_date,
    subtotal = excluded.subtotal,
    discount_amount = excluded.discount_amount,
    tax_amount = excluded.tax_amount,
    grand_total = excluded.grand_total,
    notes = excluded.notes
  returning * into v_invoice;

  -- Delete existing items if updating
  delete from public.sales_document_items
  where company_id = p_company_id and document_id = v_invoice.id;

  -- Insert new line items
  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into public.sales_document_items (
      company_id,
      document_id,
      product_id,
      description,
      quantity,
      unit_price,
      discount_amount,
      tax_rate,
      tax_amount,
      line_total
    ) values (
      p_company_id,
      v_invoice.id,
      nullif(v_item->>'product_id', '')::uuid,
      coalesce(v_item->>'description', 'Item'),
      coalesce((v_item->>'quantity')::numeric, 1),
      coalesce((v_item->>'unit_price')::numeric, 0),
      coalesce((v_item->>'discount_amount')::numeric, 0),
      coalesce((v_item->>'tax_rate')::numeric, 0),
      coalesce((v_item->>'tax_amount')::numeric, 0),
      coalesce((v_item->>'line_total')::numeric, 0)
    );
  end loop;

  -- Audit log entry
  perform private.log_audit_event(
    p_company_id,
    auth.uid(),
    'sales_invoice.saved',
    'sales_documents',
    v_invoice.id::text,
    jsonb_build_object(
      'document_number', v_number,
      'status', v_status_enum,
      'grand_total', p_grand_total
    )
  );

  return v_invoice;
end;
$$;

revoke all on function public.save_sales_invoice(uuid, uuid, uuid, text, text, date, date, numeric, numeric, numeric, numeric, text, jsonb) from public, anon;
grant execute on function public.save_sales_invoice(uuid, uuid, uuid, text, text, date, date, numeric, numeric, numeric, numeric, text, jsonb) to authenticated, service_role;

-- 4. Update record_invoice_payment RPC with audit logging
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

  -- Audit log entry
  perform private.log_audit_event(
    p_company_id,
    auth.uid(),
    'invoice_payment.recorded',
    'payments',
    v_payment_id::text,
    jsonb_build_object(
      'payment_number', v_payment_number,
      'invoice_id', p_invoice_id,
      'journal_id', v_journal_id,
      'amount', p_amount,
      'invoice_status', v_new_status
    )
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

-- 5. Update post_stock_movement RPC with audit logging
create or replace function public.post_stock_movement(
  p_company_id uuid,
  p_product_id uuid,
  p_warehouse_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_unit_cost numeric default null,
  p_reference_type text default null,
  p_reference_id text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_movement_id uuid;
  v_balance_id uuid;
  v_delta numeric;
  v_balance public.stock_balances;
begin
  -- 1. Permission check
  if not private.is_company_member(p_company_id) then
    raise exception 'Permission denied.'
      using errcode = '42501';
  end if;

  -- 2. Validate quantity
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Stock movement quantity must be greater than zero.';
  end if;

  -- 3. Calculate delta
  if p_movement_type = 'out' then
    v_delta := -abs(p_quantity);
  else
    v_delta := p_quantity;
  end if;

  -- 4. Create movement record
  v_movement_id := gen_random_uuid();
  insert into public.stock_movements (
    id,
    company_id,
    product_id,
    warehouse_id,
    movement_type,
    quantity,
    unit_cost,
    reference_type,
    reference_id,
    notes,
    created_by
  ) values (
    v_movement_id,
    p_company_id,
    p_product_id,
    p_warehouse_id,
    p_movement_type,
    p_quantity,
    p_unit_cost,
    p_reference_type,
    p_reference_id,
    p_notes,
    auth.uid()
  );

  -- 5. Lock balance row if it exists (FOR UPDATE) and upsert balance
  select * into v_balance
  from public.stock_balances
  where company_id = p_company_id
    and product_id = p_product_id
    and warehouse_id = p_warehouse_id
  for update;

  if v_balance.id is null then
    insert into public.stock_balances (
      company_id,
      product_id,
      warehouse_id,
      quantity_on_hand,
      quantity_allocated
    ) values (
      p_company_id,
      p_product_id,
      p_warehouse_id,
      v_delta,
      0
    ) returning id into v_balance_id;
  else
    update public.stock_balances
    set quantity_on_hand = quantity_on_hand + v_delta
    where id = v_balance.id;
    v_balance_id := v_balance.id;
  end if;

  -- Audit log entry
  perform private.log_audit_event(
    p_company_id,
    auth.uid(),
    'stock_movement.posted',
    'stock_movements',
    v_movement_id::text,
    jsonb_build_object(
      'product_id', p_product_id,
      'warehouse_id', p_warehouse_id,
      'movement_type', p_movement_type,
      'quantity', p_quantity,
      'quantity_delta', v_delta
    )
  );

  return jsonb_build_object(
    'success', true,
    'movement_id', v_movement_id,
    'balance_id', v_balance_id
  );
end;
$$;

revoke all on function public.post_stock_movement(uuid, uuid, uuid, text, numeric, numeric, text, text, text) from public, anon;
grant execute on function public.post_stock_movement(uuid, uuid, uuid, text, numeric, numeric, text, text, text) to authenticated, service_role;

commit;
