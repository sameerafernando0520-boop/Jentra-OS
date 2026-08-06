begin;

-- Enums for sales documents
do $$
begin
  if not exists (select 1 from pg_type where typname = 'sales_document_type' and typnamespace = 'public'::regnamespace) then
    create type public.sales_document_type as enum (
      'quotation',
      'sales_order',
      'invoice'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'sales_document_status' and typnamespace = 'public'::regnamespace) then
    create type public.sales_document_status as enum (
      'draft',
      'issued',
      'paid',
      'partially_paid',
      'void',
      'cancelled'
    );
  end if;
end;
$$;

-- Table: sales_documents
create table public.sales_documents (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  customer_id uuid not null references public.parties(id) on delete restrict,
  document_type public.sales_document_type not null default 'invoice',
  document_number text not null,
  status public.sales_document_status not null default 'draft',
  issue_date date not null default current_date,
  due_date date,
  subtotal numeric(18, 2) not null default 0,
  discount_amount numeric(18, 2) not null default 0,
  tax_amount numeric(18, 2) not null default 0,
  grand_total numeric(18, 2) not null default 0,
  paid_amount numeric(18, 2) not null default 0,
  balance_due numeric(18, 2) generated always as (grand_total - paid_amount) stored,
  notes text,
  terms_and_conditions text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_documents_company_id_id_unique unique (company_id, id),
  constraint sales_documents_unique_number unique (company_id, document_type, document_number),
  constraint sales_documents_number_not_blank check (btrim(document_number) <> ''),
  constraint sales_documents_subtotal_nonnegative check (subtotal >= 0),
  constraint sales_documents_discount_nonnegative check (discount_amount >= 0),
  constraint sales_documents_tax_nonnegative check (tax_amount >= 0),
  constraint sales_documents_grand_total_nonnegative check (grand_total >= 0),
  constraint sales_documents_paid_nonnegative check (paid_amount >= 0)
);

create index sales_documents_company_type_idx
  on public.sales_documents (company_id, document_type, issue_date desc, id);

create index sales_documents_customer_idx
  on public.sales_documents (company_id, customer_id);

create trigger set_sales_documents_updated_at
before update on public.sales_documents
for each row execute function private.set_updated_at();

-- Table: sales_document_items
create table public.sales_document_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  document_id uuid not null references public.sales_documents(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  description text not null,
  quantity numeric(18, 4) not null default 1,
  unit_price numeric(18, 2) not null default 0,
  discount_amount numeric(18, 2) not null default 0,
  tax_rate numeric(5, 2) not null default 0,
  tax_amount numeric(18, 2) not null default 0,
  line_total numeric(18, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_document_items_company_id_id_unique unique (company_id, id),
  constraint sales_document_items_description_not_blank check (btrim(description) <> ''),
  constraint sales_document_items_quantity_positive check (quantity > 0),
  constraint sales_document_items_unit_price_nonnegative check (unit_price >= 0),
  constraint sales_document_items_discount_nonnegative check (discount_amount >= 0),
  constraint sales_document_items_tax_rate_nonnegative check (tax_rate >= 0),
  constraint sales_document_items_tax_amount_nonnegative check (tax_amount >= 0),
  constraint sales_document_items_line_total_nonnegative check (line_total >= 0)
);

create index sales_document_items_document_idx
  on public.sales_document_items (company_id, document_id);

create trigger set_sales_document_items_updated_at
before update on public.sales_document_items
for each row execute function private.set_updated_at();

-- RLS setup
alter table public.sales_documents enable row level security;
alter table public.sales_document_items enable row level security;

create policy sales_documents_select_member
  on public.sales_documents for select to authenticated
  using (private.is_company_member(company_id));

create policy sales_documents_insert_writer
  on public.sales_documents for insert to authenticated
  with check (private.has_permission(company_id, 'sales.write'));

create policy sales_documents_update_writer
  on public.sales_documents for update to authenticated
  using (private.has_permission(company_id, 'sales.write'))
  with check (private.has_permission(company_id, 'sales.write'));

create policy sales_document_items_select_member
  on public.sales_document_items for select to authenticated
  using (private.is_company_member(company_id));

create policy sales_document_items_insert_writer
  on public.sales_document_items for insert to authenticated
  with check (private.has_permission(company_id, 'sales.write'));

create policy sales_document_items_update_writer
  on public.sales_document_items for update to authenticated
  using (private.has_permission(company_id, 'sales.write'))
  with check (private.has_permission(company_id, 'sales.write'));

create policy sales_document_items_delete_writer
  on public.sales_document_items for delete to authenticated
  using (private.has_permission(company_id, 'sales.write'));

-- Grants
grant select, insert, update on public.sales_documents to authenticated;
grant select, insert, update, delete on public.sales_document_items to authenticated;

grant select, insert, update, delete on public.sales_documents to service_role;
grant select, insert, update, delete on public.sales_document_items to service_role;

-- Keyset search for invoices
create or replace function public.search_invoices(
  p_company_id uuid,
  p_search text default null,
  p_status text default null,
  p_customer_id uuid default null,
  p_after_date date default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns setof public.sales_documents
language sql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
  select d.*
  from public.sales_documents d
  where d.company_id = p_company_id
    and d.document_type = 'invoice'
    and (select private.is_company_member(p_company_id))
    and (p_status is null or d.status::text = p_status)
    and (p_customer_id is null or d.customer_id = p_customer_id)
    and (
      nullif(btrim(p_search), '') is null
      or d.document_number ilike '%' || btrim(p_search) || '%'
    )
    and (
      p_after_date is null
      or p_after_id is null
      or (d.issue_date, d.id) < (p_after_date, p_after_id)
    )
  order by
    d.issue_date desc,
    d.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke all on function public.search_invoices(uuid, text, text, uuid, date, uuid, integer) from public, anon;
grant execute on function public.search_invoices(uuid, text, text, uuid, date, uuid, integer) to authenticated, service_role;

-- Transactional RPC to save invoice header & line items atomically
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

  return v_invoice;
end;
$$;

revoke all on function public.save_sales_invoice(uuid, uuid, uuid, text, text, date, date, numeric, numeric, numeric, numeric, text, jsonb) from public, anon;
grant execute on function public.save_sales_invoice(uuid, uuid, uuid, text, text, date, date, numeric, numeric, numeric, numeric, text, jsonb) to authenticated, service_role;

commit;
