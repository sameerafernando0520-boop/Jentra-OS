begin;

-- 1. Table: tax_rates
create table public.tax_rates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  rate numeric(5, 2) not null default 0.00,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tax_rates_company_id_id_unique unique (company_id, id),
  constraint tax_rates_name_not_blank check (btrim(name) <> ''),
  constraint tax_rates_rate_nonnegative check (rate >= 0)
);

create index tax_rates_company_idx on public.tax_rates (company_id, is_active, name);

create trigger set_tax_rates_updated_at
before update on public.tax_rates
for each row execute function private.set_updated_at();

alter table public.tax_rates enable row level security;

create policy tax_rates_select_member
  on public.tax_rates for select to authenticated
  using (private.is_company_member(company_id));

create policy tax_rates_insert_writer
  on public.tax_rates for insert to authenticated
  with check (private.has_permission(company_id, 'sales.write'));

create policy tax_rates_update_writer
  on public.tax_rates for update to authenticated
  using (private.has_permission(company_id, 'sales.write'))
  with check (private.has_permission(company_id, 'sales.write'));

grant select, insert, update on public.tax_rates to authenticated;
grant select, insert, update, delete on public.tax_rates to service_role;

-- 2. Table: stock_transfers & stock_transfer_items
create table public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  transfer_number text not null,
  from_warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  to_warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  status text not null default 'draft',
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_transfers_company_id_id_unique unique (company_id, id),
  constraint stock_transfers_number_not_blank check (btrim(transfer_number) <> ''),
  constraint stock_transfers_different_warehouses check (from_warehouse_id <> to_warehouse_id)
);

create index stock_transfers_company_idx on public.stock_transfers (company_id, created_at desc, id);

create trigger set_stock_transfers_updated_at
before update on public.stock_transfers
for each row execute function private.set_updated_at();

create table public.stock_transfer_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity numeric(18, 4) not null,
  created_at timestamptz not null default now(),
  constraint stock_transfer_items_company_id_id_unique unique (company_id, id),
  constraint stock_transfer_items_quantity_positive check (quantity > 0)
);

create index stock_transfer_items_company_transfer_idx on public.stock_transfer_items (company_id, transfer_id);

alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_items enable row level security;

create policy stock_transfers_select_member
  on public.stock_transfers for select to authenticated
  using (private.is_company_member(company_id));

create policy stock_transfers_insert_writer
  on public.stock_transfers for insert to authenticated
  with check (private.has_permission(company_id, 'inventory.write'));

create policy stock_transfer_items_select_member
  on public.stock_transfer_items for select to authenticated
  using (private.is_company_member(company_id));

create policy stock_transfer_items_insert_writer
  on public.stock_transfer_items for insert to authenticated
  with check (private.has_permission(company_id, 'inventory.write'));

grant select, insert, update on public.stock_transfers to authenticated;
grant select, insert on public.stock_transfer_items to authenticated;
grant select, insert, update, delete on public.stock_transfers to service_role;
grant select, insert, update, delete on public.stock_transfer_items to service_role;

-- 3. CRM: party_contacts, party_addresses, leads, activities, attachments
create table public.party_contacts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,
  first_name text not null,
  last_name text,
  email text,
  phone text,
  job_title text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint party_contacts_company_id_id_unique unique (company_id, id)
);

create index party_contacts_company_party_idx on public.party_contacts (company_id, party_id);

create trigger set_party_contacts_updated_at
before update on public.party_contacts
for each row execute function private.set_updated_at();

create table public.party_addresses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,
  address_type text not null default 'billing',
  street text not null,
  city text,
  state text,
  postal_code text,
  country text not null default 'US',
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint party_addresses_company_id_id_unique unique (company_id, id)
);

create index party_addresses_company_party_idx on public.party_addresses (company_id, party_id);

create trigger set_party_addresses_updated_at
before update on public.party_addresses
for each row execute function private.set_updated_at();

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  company_name text,
  email text,
  phone text,
  status text not null default 'new',
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leads_company_id_id_unique unique (company_id, id)
);

create index leads_company_idx on public.leads (company_id, status, created_at desc);

create trigger set_leads_updated_at
before update on public.leads
for each row execute function private.set_updated_at();

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid references public.parties(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,
  activity_type text not null default 'call',
  subject text not null,
  description text,
  due_date timestamptz,
  status text not null default 'pending',
  assigned_to uuid references auth.users(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activities_company_id_id_unique unique (company_id, id)
);

create index activities_company_party_idx on public.activities (company_id, party_id);
create index activities_company_lead_idx on public.activities (company_id, lead_id);

create trigger set_activities_updated_at
before update on public.activities
for each row execute function private.set_updated_at();

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  file_name text not null,
  storage_path text not null,
  file_size bigint not null default 0,
  mime_type text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint attachments_company_id_id_unique unique (company_id, id)
);

create index attachments_company_entity_idx on public.attachments (company_id, entity_type, entity_id);

alter table public.party_contacts enable row level security;
alter table public.party_addresses enable row level security;
alter table public.leads enable row level security;
alter table public.activities enable row level security;
alter table public.attachments enable row level security;

create policy party_contacts_select_member on public.party_contacts for select to authenticated using (private.is_company_member(company_id));
create policy party_contacts_insert_writer on public.party_contacts for insert to authenticated with check (private.has_permission(company_id, 'crm.write'));
create policy party_addresses_select_member on public.party_addresses for select to authenticated using (private.is_company_member(company_id));
create policy party_addresses_insert_writer on public.party_addresses for insert to authenticated with check (private.has_permission(company_id, 'crm.write'));
create policy leads_select_member on public.leads for select to authenticated using (private.is_company_member(company_id));
create policy leads_insert_writer on public.leads for insert to authenticated with check (private.has_permission(company_id, 'crm.write'));
create policy activities_select_member on public.activities for select to authenticated using (private.is_company_member(company_id));
create policy activities_insert_writer on public.activities for insert to authenticated with check (private.has_permission(company_id, 'crm.write'));
create policy attachments_select_member on public.attachments for select to authenticated using (private.is_company_member(company_id));
create policy attachments_insert_writer on public.attachments for insert to authenticated with check (private.is_company_member(company_id));

grant select, insert, update on public.party_contacts to authenticated;
grant select, insert, update on public.party_addresses to authenticated;
grant select, insert, update on public.leads to authenticated;
grant select, insert, update on public.activities to authenticated;
grant select, insert on public.attachments to authenticated;

grant select, insert, update, delete on public.party_contacts to service_role;
grant select, insert, update, delete on public.party_addresses to service_role;
grant select, insert, update, delete on public.leads to service_role;
grant select, insert, update, delete on public.activities to service_role;
grant select, insert, update, delete on public.attachments to service_role;

-- 4. Atomic RPC: post_stock_transfer
create or replace function public.post_stock_transfer(
  p_company_id uuid,
  p_from_warehouse_id uuid,
  p_to_warehouse_id uuid,
  p_items jsonb,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_transfer_id uuid;
  v_transfer_number text;
  v_item jsonb;
  v_prod_id uuid;
  v_qty numeric;
  v_out_res jsonb;
  v_in_res jsonb;
begin
  if not private.has_permission(p_company_id, 'inventory.write') then
    raise exception 'Permission denied.' using errcode = '42501';
  end if;

  if p_from_warehouse_id = p_to_warehouse_id then
    raise exception 'Source and destination warehouses must be different.';
  end if;

  select 'TRF-' || lpad((count(*) + 1001)::text, 5, '0')
  into v_transfer_number
  from public.stock_transfers
  where company_id = p_company_id;

  v_transfer_id := gen_random_uuid();

  insert into public.stock_transfers (
    id,
    company_id,
    transfer_number,
    from_warehouse_id,
    to_warehouse_id,
    status,
    notes,
    created_by
  ) values (
    v_transfer_id,
    p_company_id,
    v_transfer_number,
    p_from_warehouse_id,
    p_to_warehouse_id,
    'posted',
    p_notes,
    auth.uid()
  );

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_prod_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;

    if v_qty is null or v_qty <= 0 then
      raise exception 'Transfer item quantity must be positive.';
    end if;

    insert into public.stock_transfer_items (
      company_id,
      transfer_id,
      product_id,
      quantity
    ) values (
      p_company_id,
      v_transfer_id,
      v_prod_id,
      v_qty
    );

    v_out_res := public.post_stock_movement(
      p_company_id,
      v_prod_id,
      p_from_warehouse_id,
      'out',
      v_qty,
      null,
      'stock_transfer',
      v_transfer_id::text,
      'Transfer out to ' || v_transfer_number
    );

    v_in_res := public.post_stock_movement(
      p_company_id,
      v_prod_id,
      p_to_warehouse_id,
      'in',
      v_qty,
      null,
      'stock_transfer',
      v_transfer_id::text,
      'Transfer in from ' || v_transfer_number
    );
  end loop;

  perform private.log_audit_event(
    p_company_id,
    auth.uid(),
    'stock_transfer.posted',
    'stock_transfers',
    v_transfer_id::text,
    jsonb_build_object(
      'transfer_number', v_transfer_number,
      'from_warehouse_id', p_from_warehouse_id,
      'to_warehouse_id', p_to_warehouse_id
    )
  );

  return jsonb_build_object(
    'success', true,
    'transfer_id', v_transfer_id,
    'transfer_number', v_transfer_number
  );
end;
$$;

revoke all on function public.post_stock_transfer(uuid, uuid, uuid, jsonb, text) from public, anon;
grant execute on function public.post_stock_transfer(uuid, uuid, uuid, jsonb, text) to authenticated, service_role;

-- 5. Atomic RPC: convert_lead_to_party
create or replace function public.convert_lead_to_party(
  p_company_id uuid,
  p_lead_id uuid,
  p_party_type text default 'customer'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_lead public.leads;
  v_party_id uuid;
begin
  if not private.has_permission(p_company_id, 'crm.write') then
    raise exception 'Permission denied.' using errcode = '42501';
  end if;

  select * into v_lead
  from public.leads
  where company_id = p_company_id and id = p_lead_id;

  if v_lead.id is null then
    raise exception 'Lead not found.';
  end if;

  if v_lead.status = 'converted' then
    raise exception 'Lead is already converted.';
  end if;

  v_party_id := gen_random_uuid();

  insert into public.parties (
    id,
    company_id,
    name,
    party_type,
    email,
    phone,
    notes,
    created_by
  ) values (
    v_party_id,
    p_company_id,
    coalesce(v_lead.company_name, v_lead.name),
    p_party_type,
    v_lead.email,
    v_lead.phone,
    v_lead.notes,
    auth.uid()
  );

  if v_lead.name is not null and btrim(v_lead.name) <> '' then
    insert into public.party_contacts (
      company_id,
      party_id,
      first_name,
      email,
      phone,
      is_primary
    ) values (
      p_company_id,
      v_party_id,
      v_lead.name,
      v_lead.email,
      v_lead.phone,
      true
    );
  end if;

  update public.leads
  set status = 'converted'
  where id = p_lead_id;

  perform private.log_audit_event(
    p_company_id,
    auth.uid(),
    'lead.converted',
    'leads',
    p_lead_id::text,
    jsonb_build_object('party_id', v_party_id, 'party_type', p_party_type)
  );

  return jsonb_build_object(
    'success', true,
    'lead_id', p_lead_id,
    'party_id', v_party_id
  );
end;
$$;

revoke all on function public.convert_lead_to_party(uuid, uuid, text) from public, anon;
grant execute on function public.convert_lead_to_party(uuid, uuid, text) to authenticated, service_role;

-- 6. Report RPC: get_receivables_aging
create or replace function public.get_receivables_aging(
  p_company_id uuid,
  p_as_of_date date default current_date
)
returns table (
  customer_id uuid,
  customer_name text,
  current_amount numeric,
  days_1_30 numeric,
  days_31_60 numeric,
  days_61_90 numeric,
  days_90_plus numeric,
  total_due numeric
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
    d.customer_id,
    coalesce(p.name, 'Unknown Customer') as customer_name,
    sum(case when p_as_of_date <= d.due_date then (d.grand_total - d.paid_amount) else 0 end) as current_amount,
    sum(case when p_as_of_date > d.due_date and (p_as_of_date - d.due_date) between 1 and 30 then (d.grand_total - d.paid_amount) else 0 end) as days_1_30,
    sum(case when p_as_of_date > d.due_date and (p_as_of_date - d.due_date) between 31 and 60 then (d.grand_total - d.paid_amount) else 0 end) as days_31_60,
    sum(case when p_as_of_date > d.due_date and (p_as_of_date - d.due_date) between 61 and 90 then (d.grand_total - d.paid_amount) else 0 end) as days_90_plus,
    sum(d.grand_total - d.paid_amount) as total_due
  from public.sales_documents d
  left join public.parties p on p.company_id = p_company_id and p.id = d.customer_id
  where d.company_id = p_company_id
    and d.document_type = 'invoice'
    and d.status in ('posted', 'partially_paid')
    and (d.grand_total - d.paid_amount) > 0.001
    and d.issue_date <= p_as_of_date
  group by d.customer_id, p.name
  order by total_due desc;
end;
$$;

revoke all on function public.get_receivables_aging(uuid, date) from public, anon;
grant execute on function public.get_receivables_aging(uuid, date) to authenticated, service_role;

commit;
