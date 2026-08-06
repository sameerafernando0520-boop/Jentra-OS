-- i Book Phase 1: hardened authentication and multi-company foundation.
-- This migration intentionally excludes CRM, finance, inventory, and UI-facing
-- modules until the tenant boundary has been validated independently.

begin;

create extension if not exists citext with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon;

-- Make future Data API exposure explicit. Grants are added at the end of this
-- migration only for objects the Flutter client actually needs.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$$;

create type public.member_status as enum (
  'invited',
  'active',
  'suspended',
  'removed'
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  avatar_url text,
  default_company_id uuid,
  locale text not null default 'en',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_locale_not_blank check (btrim(locale) <> '')
);

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  name text not null,
  legal_name text,
  registration_no text,
  tax_no text,
  email extensions.citext,
  phone text,
  website text,
  currency_code char(3) not null default 'LKR',
  country_code char(2) not null default 'LK',
  timezone text not null default 'Asia/Colombo',
  logo_url text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint companies_name_not_blank check (btrim(name) <> ''),
  constraint companies_currency_code_upper check (currency_code = upper(currency_code)),
  constraint companies_country_code_upper check (country_code = upper(country_code)),
  constraint companies_status_valid check (status in ('active', 'suspended', 'closed')),
  unique (id, owner_user_id)
);

alter table public.profiles
  add constraint profiles_default_company_fk
  foreign key (default_company_id) references public.companies(id) on delete set null;

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  code text,
  email extensions.citext,
  phone text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state text,
  postal_code text,
  country_code char(2) not null default 'LK',
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branches_name_not_blank check (btrim(name) <> ''),
  constraint branches_country_code_upper check (country_code = upper(country_code)),
  unique (company_id, id),
  unique (company_id, code)
);

create unique index branches_one_default_per_company_idx
  on public.branches(company_id)
  where is_default;

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  is_owner boolean not null default false,
  is_admin boolean not null default false,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roles_name_not_blank check (btrim(name) <> ''),
  constraint roles_owner_is_admin check (not is_owner or is_admin),
  unique (company_id, id),
  unique (company_id, name)
);

create unique index roles_one_owner_per_company_idx
  on public.roles(company_id)
  where is_owner;

create table public.permissions (
  code text primary key,
  description text not null,
  module text not null,
  constraint permissions_code_not_blank check (btrim(code) <> ''),
  constraint permissions_description_not_blank check (btrim(description) <> ''),
  constraint permissions_module_not_blank check (btrim(module) <> '')
);

create table public.role_permissions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  role_id uuid not null,
  permission_code text not null references public.permissions(code) on delete restrict,
  created_at timestamptz not null default now(),
  constraint role_permissions_role_company_fk
    foreign key (company_id, role_id)
    references public.roles(company_id, id)
    on delete cascade,
  unique (company_id, role_id, permission_code)
);

create table public.company_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null,
  status public.member_status not null default 'invited',
  invited_by uuid references auth.users(id) on delete set null,
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_memberships_role_company_fk
    foreign key (company_id, role_id)
    references public.roles(company_id, id)
    on delete restrict,
  constraint company_memberships_active_joined_at
    check (status <> 'active' or joined_at is not null),
  unique (company_id, id),
  unique (company_id, user_id)
);

create table public.company_member_branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  membership_id uuid not null,
  branch_id uuid not null,
  created_at timestamptz not null default now(),
  constraint company_member_branches_membership_company_fk
    foreign key (company_id, membership_id)
    references public.company_memberships(company_id, id)
    on delete cascade,
  constraint company_member_branches_branch_company_fk
    foreign key (company_id, branch_id)
    references public.branches(company_id, id)
    on delete cascade,
  unique (company_id, membership_id, branch_id)
);

create table public.company_settings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null unique references public.companies(id) on delete cascade,
  invoice_prefix text not null default 'INV',
  quotation_prefix text not null default 'QT',
  sales_order_prefix text not null default 'SO',
  purchase_order_prefix text not null default 'PO',
  bill_prefix text not null default 'BILL',
  next_invoice_no bigint not null default 1,
  next_quotation_no bigint not null default 1,
  next_sales_order_no bigint not null default 1,
  next_purchase_order_no bigint not null default 1,
  next_bill_no bigint not null default 1,
  default_payment_terms_days integer not null default 14,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_settings_prefixes_not_blank check (
    btrim(invoice_prefix) <> '' and
    btrim(quotation_prefix) <> '' and
    btrim(sales_order_prefix) <> '' and
    btrim(purchase_order_prefix) <> '' and
    btrim(bill_prefix) <> ''
  ),
  constraint company_settings_sequences_positive check (
    next_invoice_no > 0 and
    next_quotation_no > 0 and
    next_sales_order_no > 0 and
    next_purchase_order_no > 0 and
    next_bill_no > 0
  ),
  constraint company_settings_payment_terms_valid
    check (default_payment_terms_days between 0 and 3650),
  constraint company_settings_json_object
    check (jsonb_typeof(settings) = 'object')
);

create index companies_owner_user_idx on public.companies(owner_user_id);
create index branches_company_idx on public.branches(company_id);
create index roles_company_idx on public.roles(company_id);
create index role_permissions_role_idx on public.role_permissions(role_id);
create index company_memberships_user_status_idx
  on public.company_memberships(user_id, status);
create index company_memberships_role_idx on public.company_memberships(role_id);
create index company_member_branches_membership_idx
  on public.company_member_branches(membership_id);
create index company_member_branches_branch_idx
  on public.company_member_branches(branch_id);

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_auth_user();

create function private.is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select (select auth.uid()) is not null and (
    exists (
      select 1
      from public.company_memberships m
      where m.company_id = p_company_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
    )
    or exists (
      select 1
      from public.companies c
      where c.id = p_company_id
        and c.owner_user_id = (select auth.uid())
    )
  );
$$;

create function private.is_company_admin(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select (select auth.uid()) is not null and (
    exists (
      select 1
      from public.company_memberships m
      join public.roles r
        on r.company_id = m.company_id
       and r.id = m.role_id
      where m.company_id = p_company_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
        and (r.is_owner or r.is_admin)
    )
    or exists (
      select 1
      from public.companies c
      where c.id = p_company_id
        and c.owner_user_id = (select auth.uid())
    )
  );
$$;

create function private.has_permission(
  p_company_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.is_company_admin(p_company_id)
  or exists (
    select 1
    from public.company_memberships m
    join public.role_permissions rp
      on rp.company_id = m.company_id
     and rp.role_id = m.role_id
    where m.company_id = p_company_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and rp.permission_code = p_permission_code
  );
$$;

create function private.shares_company_with(p_other_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_other_user_id = (select auth.uid())
  or exists (
    select 1
    from public.company_memberships mine
    join public.company_memberships theirs
      on theirs.company_id = mine.company_id
    where mine.user_id = (select auth.uid())
      and mine.status = 'active'
      and theirs.user_id = p_other_user_id
      and theirs.status = 'active'
  );
$$;

create function private.prevent_company_owner_change()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.owner_user_id is distinct from old.owner_user_id then
    raise exception using
      errcode = '42501',
      message = 'Company ownership cannot be changed through a direct table update.';
  end if;
  return new;
end;
$$;

create trigger companies_prevent_owner_change
before update on public.companies
for each row execute function private.prevent_company_owner_change();

create function private.protect_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_owner_user_id uuid;
begin
  select c.owner_user_id
  into v_owner_user_id
  from public.companies c
  where c.id = old.company_id;

  if old.user_id = v_owner_user_id then
    raise exception using
      errcode = '42501',
      message = 'The company owner membership cannot be changed or removed.';
  end if;

  return new;
end;
$$;

create trigger company_memberships_protect_owner
before update on public.company_memberships
for each row execute function private.protect_owner_membership();

insert into public.permissions (code, description, module) values
  ('company.manage', 'Manage company profile, branches, and settings', 'core'),
  ('users.manage', 'Invite and manage users, roles, and permissions', 'core'),
  ('crm.write', 'Create and update CRM records', 'crm'),
  ('sales.write', 'Create and update sales records', 'sales'),
  ('purchase.write', 'Create and update purchase records', 'purchase'),
  ('inventory.write', 'Create and update inventory records', 'inventory'),
  ('finance.write', 'Create and update finance records', 'finance'),
  ('hr.write', 'Create and update HR and payroll records', 'hr'),
  ('projects.write', 'Create and update project records', 'projects'),
  ('ai.use', 'Use AI assistant capabilities', 'ai'),
  ('reports.view', 'View dashboards and reports', 'reports'),
  ('data.delete', 'Delete eligible business records', 'security');

create function private.initialize_company_defaults()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_branch_id uuid;
  v_owner_role_id uuid;
  v_admin_role_id uuid;
  v_accountant_role_id uuid;
  v_sales_role_id uuid;
  v_warehouse_role_id uuid;
  v_viewer_role_id uuid;
  v_owner_membership_id uuid;
begin
  insert into public.profiles (id)
  values (new.owner_user_id)
  on conflict (id) do nothing;

  insert into public.branches (company_id, name, code, is_default)
  values (new.id, 'Main Branch', 'MAIN', true)
  returning id into v_branch_id;

  insert into public.company_settings (company_id)
  values (new.id);

  insert into public.roles (
    company_id, name, description, is_owner, is_admin, is_system
  ) values (
    new.id, 'Owner', 'Full-access company owner', true, true, true
  ) returning id into v_owner_role_id;

  insert into public.roles (company_id, name, description, is_admin, is_system)
  values (new.id, 'Admin', 'Administrative access', true, true)
  returning id into v_admin_role_id;

  insert into public.roles (company_id, name, description, is_system)
  values (new.id, 'Accountant', 'Finance and reporting access', true)
  returning id into v_accountant_role_id;

  insert into public.roles (company_id, name, description, is_system)
  values (new.id, 'Sales', 'CRM and sales access', true)
  returning id into v_sales_role_id;

  insert into public.roles (company_id, name, description, is_system)
  values (new.id, 'Warehouse', 'Inventory and purchase access', true)
  returning id into v_warehouse_role_id;

  insert into public.roles (company_id, name, description, is_system)
  values (new.id, 'Viewer', 'Read-only reporting access', true)
  returning id into v_viewer_role_id;

  insert into public.role_permissions (company_id, role_id, permission_code)
  select new.id, v_owner_role_id, p.code from public.permissions p;

  insert into public.role_permissions (company_id, role_id, permission_code)
  select new.id, v_admin_role_id, p.code from public.permissions p;

  insert into public.role_permissions (company_id, role_id, permission_code)
  select new.id, v_accountant_role_id, p.code
  from public.permissions p
  where p.code in (
    'crm.write', 'sales.write', 'purchase.write', 'finance.write',
    'reports.view', 'ai.use'
  );

  insert into public.role_permissions (company_id, role_id, permission_code)
  select new.id, v_sales_role_id, p.code
  from public.permissions p
  where p.code in ('crm.write', 'sales.write', 'reports.view', 'ai.use');

  insert into public.role_permissions (company_id, role_id, permission_code)
  select new.id, v_warehouse_role_id, p.code
  from public.permissions p
  where p.code in ('purchase.write', 'inventory.write', 'reports.view');

  insert into public.role_permissions (company_id, role_id, permission_code)
  values (new.id, v_viewer_role_id, 'reports.view');

  insert into public.company_memberships (
    company_id, user_id, role_id, status, joined_at
  ) values (
    new.id, new.owner_user_id, v_owner_role_id, 'active', now()
  ) returning id into v_owner_membership_id;

  insert into public.company_member_branches (
    company_id, membership_id, branch_id
  ) values (
    new.id, v_owner_membership_id, v_branch_id
  );

  update public.profiles
  set default_company_id = coalesce(default_company_id, new.id)
  where id = new.owner_user_id;

  return new;
end;
$$;

create trigger companies_initialize_defaults
after insert on public.companies
for each row execute function private.initialize_company_defaults();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'profiles', 'companies', 'branches', 'roles',
    'company_memberships', 'company_settings'
  ] loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function private.set_updated_at()',
      'set_' || v_table || '_updated_at',
      v_table
    );
  end loop;
end;
$$;

alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.branches enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.company_memberships enable row level security;
alter table public.company_member_branches enable row level security;
alter table public.company_settings enable row level security;

create policy profiles_select_shared_company
on public.profiles for select
to authenticated
using (private.shares_company_with(id));

create policy profiles_update_own
on public.profiles for update
to authenticated
using (id = (select auth.uid()))
with check (
  id = (select auth.uid())
  and (
    default_company_id is null
    or private.is_company_member(default_company_id)
  )
);

create policy companies_select_member
on public.companies for select
to authenticated
using (private.is_company_member(id));

create policy companies_insert_owner
on public.companies for insert
to authenticated
with check (owner_user_id = (select auth.uid()));

create policy companies_update_admin
on public.companies for update
to authenticated
using (private.is_company_admin(id))
with check (private.is_company_admin(id));

create policy companies_delete_owner
on public.companies for delete
to authenticated
using (owner_user_id = (select auth.uid()));

create policy branches_select_member
on public.branches for select
to authenticated
using (private.is_company_member(company_id));

create policy branches_insert_admin
on public.branches for insert
to authenticated
with check (private.is_company_admin(company_id));

create policy branches_update_admin
on public.branches for update
to authenticated
using (private.is_company_admin(company_id))
with check (private.is_company_admin(company_id));

create policy branches_delete_admin
on public.branches for delete
to authenticated
using (private.is_company_admin(company_id));

create policy roles_select_member
on public.roles for select
to authenticated
using (private.is_company_member(company_id));

create policy roles_insert_admin
on public.roles for insert
to authenticated
with check (
  private.is_company_admin(company_id)
  and not is_owner
);

create policy roles_update_admin
on public.roles for update
to authenticated
using (
  private.is_company_admin(company_id)
  and not is_owner
)
with check (
  private.is_company_admin(company_id)
  and not is_owner
);

create policy roles_delete_admin
on public.roles for delete
to authenticated
using (
  private.is_company_admin(company_id)
  and not is_system
);

create policy permissions_select_authenticated
on public.permissions for select
to authenticated
using (true);

create policy role_permissions_select_member
on public.role_permissions for select
to authenticated
using (private.is_company_member(company_id));

create policy role_permissions_insert_admin
on public.role_permissions for insert
to authenticated
with check (private.is_company_admin(company_id));

create policy role_permissions_update_admin
on public.role_permissions for update
to authenticated
using (private.is_company_admin(company_id))
with check (private.is_company_admin(company_id));

create policy role_permissions_delete_admin
on public.role_permissions for delete
to authenticated
using (private.is_company_admin(company_id));

create policy company_memberships_select_member
on public.company_memberships for select
to authenticated
using (private.is_company_member(company_id));

create policy company_memberships_insert_admin
on public.company_memberships for insert
to authenticated
with check (
  private.is_company_admin(company_id)
  and not exists (
    select 1
    from public.roles r
    where r.company_id = company_id
      and r.id = role_id
      and r.is_owner
  )
);

create policy company_memberships_update_admin
on public.company_memberships for update
to authenticated
using (
  private.is_company_admin(company_id)
  and not exists (
    select 1
    from public.companies c
    where c.id = company_id
      and c.owner_user_id = user_id
  )
)
with check (
  private.is_company_admin(company_id)
  and not exists (
    select 1
    from public.roles r
    where r.company_id = company_id
      and r.id = role_id
      and r.is_owner
  )
);

create policy company_memberships_delete_admin
on public.company_memberships for delete
to authenticated
using (
  private.is_company_admin(company_id)
  and not exists (
    select 1
    from public.companies c
    where c.id = company_id
      and c.owner_user_id = user_id
  )
);

create policy company_member_branches_select_member
on public.company_member_branches for select
to authenticated
using (private.is_company_member(company_id));

create policy company_member_branches_insert_admin
on public.company_member_branches for insert
to authenticated
with check (private.is_company_admin(company_id));

create policy company_member_branches_update_admin
on public.company_member_branches for update
to authenticated
using (private.is_company_admin(company_id))
with check (private.is_company_admin(company_id));

create policy company_member_branches_delete_admin
on public.company_member_branches for delete
to authenticated
using (private.is_company_admin(company_id));

create policy company_settings_select_member
on public.company_settings for select
to authenticated
using (private.is_company_member(company_id));

create policy company_settings_update_admin
on public.company_settings for update
to authenticated
using (private.is_company_admin(company_id))
with check (private.is_company_admin(company_id));

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

grant usage on schema public to authenticated, service_role;
grant usage on schema private to authenticated, service_role;

grant select on public.profiles to authenticated;
grant update (full_name, phone, avatar_url, default_company_id, locale)
  on public.profiles to authenticated;

grant select, insert, delete on public.companies to authenticated;
grant update (
  name, legal_name, registration_no, tax_no, email, phone, website,
  currency_code, country_code, timezone, logo_url, status
) on public.companies to authenticated;

grant select, insert, delete on public.branches to authenticated;
grant update (
  name, code, email, phone, address_line_1, address_line_2,
  city, state, postal_code, country_code, is_default
) on public.branches to authenticated;
grant select, insert, delete on public.roles to authenticated;
grant update (name, description, is_admin, is_system)
  on public.roles to authenticated;
grant select on public.permissions to authenticated;
grant select, insert, delete on public.role_permissions to authenticated;
grant select, insert, delete on public.company_memberships to authenticated;
grant update (role_id, status, invited_by, joined_at)
  on public.company_memberships to authenticated;
grant select, insert, delete on public.company_member_branches to authenticated;
grant select on public.company_settings to authenticated;
grant update (
  invoice_prefix, quotation_prefix, sales_order_prefix,
  purchase_order_prefix, bill_prefix, default_payment_terms_days, settings
) on public.company_settings to authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.companies,
  public.branches,
  public.roles,
  public.permissions,
  public.role_permissions,
  public.company_memberships,
  public.company_member_branches,
  public.company_settings
to service_role;

grant execute on function private.is_company_member(uuid) to authenticated, service_role;
grant execute on function private.is_company_admin(uuid) to authenticated, service_role;
grant execute on function private.has_permission(uuid, text) to authenticated, service_role;
grant execute on function private.shares_company_with(uuid) to authenticated, service_role;

comment on schema private is
  'Internal database functions. This schema must not be exposed through the Data API.';
comment on table public.companies is
  'Top-level tenant records for the i Book multi-company SaaS platform.';
comment on table public.company_memberships is
  'Authoritative mapping between authenticated users, companies, and tenant-scoped roles.';

commit;
