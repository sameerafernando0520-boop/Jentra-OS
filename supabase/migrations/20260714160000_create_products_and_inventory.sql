begin;

-- Product categories table
create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  code text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_categories_company_id_id_unique unique (company_id, id),
  constraint product_categories_name_not_blank check (btrim(name) <> ''),
  constraint product_categories_name_length check (char_length(name) <= 100),
  constraint product_categories_code_length check (code is null or char_length(code) <= 50)
);

create index product_categories_company_sort_idx
  on public.product_categories (company_id, name, id);

create trigger set_product_categories_updated_at
before update on public.product_categories
for each row execute function private.set_updated_at();

-- Products table
create table public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  category_id uuid references public.product_categories(id) on delete set null,
  name text not null,
  sku text,
  barcode text,
  description text,
  unit text not null default 'pcs',
  unit_price numeric(18, 2) not null default 0,
  cost_price numeric(18, 2) not null default 0,
  track_inventory boolean not null default true,
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_company_id_id_unique unique (company_id, id),
  constraint products_name_not_blank check (btrim(name) <> ''),
  constraint products_name_length check (char_length(name) <= 200),
  constraint products_sku_length check (sku is null or char_length(sku) <= 100),
  constraint products_barcode_length check (barcode is null or char_length(barcode) <= 100),
  constraint products_unit_not_blank check (btrim(unit) <> ''),
  constraint products_unit_price_nonnegative check (unit_price >= 0),
  constraint products_cost_price_nonnegative check (cost_price >= 0)
);

create index products_company_sort_idx
  on public.products (company_id, is_active, lower(name), id);

create index products_sku_idx
  on public.products (company_id, sku)
  where sku is not null;

create index products_barcode_idx
  on public.products (company_id, barcode)
  where barcode is not null;

create trigger set_products_updated_at
before update on public.products
for each row execute function private.set_updated_at();

-- Warehouses table
create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  code text,
  address text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouses_company_id_id_unique unique (company_id, id),
  constraint warehouses_name_not_blank check (btrim(name) <> ''),
  constraint warehouses_name_length check (char_length(name) <= 100),
  constraint warehouses_code_length check (code is null or char_length(code) <= 50)
);

create index warehouses_company_idx on public.warehouses (company_id, name);

create trigger set_warehouses_updated_at
before update on public.warehouses
for each row execute function private.set_updated_at();

-- Stock balances table
create table public.stock_balances (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  quantity_on_hand numeric(18, 4) not null default 0,
  quantity_allocated numeric(18, 4) not null default 0,
  quantity_available numeric(18, 4) generated always as (quantity_on_hand - quantity_allocated) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_balances_unique_product_warehouse unique (company_id, product_id, warehouse_id)
);

create index stock_balances_company_wh_idx on public.stock_balances (company_id, warehouse_id);
create index stock_balances_company_prod_idx on public.stock_balances (company_id, product_id);

create trigger set_stock_balances_updated_at
before update on public.stock_balances
for each row execute function private.set_updated_at();

-- Stock movements table (Ledger)
create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  movement_type text not null, -- 'in', 'out', 'adjustment', 'transfer', 'opening'
  quantity numeric(18, 4) not null,
  unit_cost numeric(18, 2),
  reference_type text,
  reference_id text,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index stock_movements_company_prod_idx on public.stock_movements (company_id, product_id, created_at desc);
create index stock_movements_company_wh_idx on public.stock_movements (company_id, warehouse_id, created_at desc);

-- RLS setup
alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.warehouses enable row level security;
alter table public.stock_balances enable row level security;
alter table public.stock_movements enable row level security;

-- Policies for product_categories
create policy product_categories_select_member
  on public.product_categories for select to authenticated
  using (private.is_company_member(company_id));

create policy product_categories_insert_writer
  on public.product_categories for insert to authenticated
  with check (private.has_permission(company_id, 'inventory.write'));

create policy product_categories_update_writer
  on public.product_categories for update to authenticated
  using (private.has_permission(company_id, 'inventory.write'))
  with check (private.has_permission(company_id, 'inventory.write'));

-- Policies for products
create policy products_select_member
  on public.products for select to authenticated
  using (private.is_company_member(company_id));

create policy products_insert_writer
  on public.products for insert to authenticated
  with check (private.has_permission(company_id, 'inventory.write'));

create policy products_update_writer
  on public.products for update to authenticated
  using (private.has_permission(company_id, 'inventory.write'))
  with check (private.has_permission(company_id, 'inventory.write'));

-- Policies for warehouses
create policy warehouses_select_member
  on public.warehouses for select to authenticated
  using (private.is_company_member(company_id));

create policy warehouses_insert_writer
  on public.warehouses for insert to authenticated
  with check (private.has_permission(company_id, 'inventory.write'));

create policy warehouses_update_writer
  on public.warehouses for update to authenticated
  using (private.has_permission(company_id, 'inventory.write'))
  with check (private.has_permission(company_id, 'inventory.write'));

-- Policies for stock_balances
create policy stock_balances_select_member
  on public.stock_balances for select to authenticated
  using (private.is_company_member(company_id));

create policy stock_balances_insert_writer
  on public.stock_balances for insert to authenticated
  with check (private.has_permission(company_id, 'inventory.write'));

create policy stock_balances_update_writer
  on public.stock_balances for update to authenticated
  using (private.has_permission(company_id, 'inventory.write'))
  with check (private.has_permission(company_id, 'inventory.write'));

-- Policies for stock_movements
create policy stock_movements_select_member
  on public.stock_movements for select to authenticated
  using (private.is_company_member(company_id));

create policy stock_movements_insert_writer
  on public.stock_movements for insert to authenticated
  with check (private.has_permission(company_id, 'inventory.write'));

-- Grants
grant select, insert, update on public.product_categories to authenticated;
grant select, insert, update on public.products to authenticated;
grant select, insert, update on public.warehouses to authenticated;
grant select, insert, update on public.stock_balances to authenticated;
grant select, insert on public.stock_movements to authenticated;

grant select, insert, update, delete on public.product_categories to service_role;
grant select, insert, update, delete on public.products to service_role;
grant select, insert, update, delete on public.warehouses to service_role;
grant select, insert, update, delete on public.stock_balances to service_role;
grant select, insert, update, delete on public.stock_movements to service_role;

-- Keyset pagination function for products search
create or replace function public.search_products(
  p_company_id uuid,
  p_search text default null,
  p_category_id uuid default null,
  p_include_inactive boolean default false,
  p_after_sort_name text default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns setof public.products
language sql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
  select p.*
  from public.products p
  where p.company_id = p_company_id
    and (select private.is_company_member(p_company_id))
    and (coalesce(p_include_inactive, false) or p.is_active)
    and (p_category_id is null or p.category_id = p_category_id)
    and (
      nullif(btrim(p_search), '') is null
      or p.name ilike '%' || btrim(p_search) || '%'
      or p.sku ilike '%' || btrim(p_search) || '%'
      or p.barcode ilike '%' || btrim(p_search) || '%'
    )
    and (
      p_after_sort_name is null
      or p_after_id is null
      or (
        lower(p.name),
        p.id
      ) > (lower(p_after_sort_name), p_after_id)
    )
  order by
    lower(p.name),
    p.id
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke all on function public.search_products(uuid, text, uuid, boolean, text, uuid, integer) from public, anon;
grant execute on function public.search_products(uuid, text, uuid, boolean, text, uuid, integer) to authenticated, service_role;

commit;
