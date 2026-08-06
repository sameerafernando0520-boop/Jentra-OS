begin;

create extension if not exists citext with schema extensions;

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'party_type'
      and typnamespace = 'public'::regnamespace
  ) then
    create type public.party_type as enum (
      'lead',
      'customer',
      'supplier',
      'both'
    );
  end if;
end;
$$;

create table public.parties (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_type public.party_type not null,
  name text not null,
  display_name text,
  email extensions.citext,
  phone text,
  mobile text,
  tax_no text,
  credit_limit numeric(18, 2) not null default 0,
  payment_terms_days integer,
  opening_balance numeric(18, 2) not null default 0,
  notes text,
  tags text[] not null default array[]::text[],
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint parties_company_id_id_unique unique (company_id, id),
  constraint parties_name_not_blank check (btrim(name) <> ''),
  constraint parties_name_length check (char_length(name) <= 200),
  constraint parties_display_name_length check (
    display_name is null or char_length(display_name) <= 200
  ),
  constraint parties_email_length check (
    email is null or char_length(email::text) <= 320
  ),
  constraint parties_phone_length check (
    phone is null or char_length(phone) <= 50
  ),
  constraint parties_mobile_length check (
    mobile is null or char_length(mobile) <= 50
  ),
  constraint parties_tax_no_length check (
    tax_no is null or char_length(tax_no) <= 100
  ),
  constraint parties_credit_limit_nonnegative check (credit_limit >= 0),
  constraint parties_payment_terms_valid check (
    payment_terms_days is null
    or payment_terms_days between 0 and 3650
  ),
  constraint parties_tags_limit check (cardinality(tags) <= 30)
);

create index parties_company_type_status_sort_idx
  on public.parties (
    company_id,
    party_type,
    is_active,
    lower(coalesce(nullif(btrim(display_name), ''), name)),
    id
  );

create index parties_active_customers_sort_idx
  on public.parties (
    company_id,
    lower(coalesce(nullif(btrim(display_name), ''), name)),
    id
  )
  where is_active and party_type in ('customer', 'both');

create trigger set_parties_updated_at
before update on public.parties
for each row execute function private.set_updated_at();

alter table public.parties enable row level security;

create policy parties_select_member
on public.parties for select
to authenticated
using ((select private.is_company_member(parties.company_id)));

create policy parties_insert_crm_writer
on public.parties for insert
to authenticated
with check ((select private.has_permission(parties.company_id, 'crm.write')));

create policy parties_update_crm_writer
on public.parties for update
to authenticated
using ((select private.has_permission(parties.company_id, 'crm.write')))
with check ((select private.has_permission(parties.company_id, 'crm.write')));

create or replace function public.search_customers(
  p_company_id uuid,
  p_search text default null,
  p_include_inactive boolean default false,
  p_after_sort_name text default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns setof public.parties
language sql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
  select p.*
  from public.parties p
  where p.company_id = p_company_id
    and (select private.is_company_member(p_company_id))
    and p.party_type in ('customer', 'both')
    and (coalesce(p_include_inactive, false) or p.is_active)
    and (
      nullif(btrim(p_search), '') is null
      or p.name ilike '%' || btrim(p_search) || '%'
      or p.display_name ilike '%' || btrim(p_search) || '%'
      or p.email::text ilike '%' || btrim(p_search) || '%'
      or p.phone ilike '%' || btrim(p_search) || '%'
      or p.mobile ilike '%' || btrim(p_search) || '%'
      or p.tax_no ilike '%' || btrim(p_search) || '%'
    )
    and (
      p_after_sort_name is null
      or p_after_id is null
      or (
        lower(coalesce(nullif(btrim(p.display_name), ''), p.name)),
        p.id
      ) > (lower(p_after_sort_name), p_after_id)
    )
  order by
    lower(coalesce(nullif(btrim(p.display_name), ''), p.name)),
    p.id
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke all on public.parties from public, anon, authenticated;
grant select, insert on public.parties to authenticated;
grant update (
  name,
  display_name,
  email,
  phone,
  mobile,
  tax_no,
  credit_limit,
  payment_terms_days,
  opening_balance,
  notes,
  tags,
  is_active
) on public.parties to authenticated;

grant select, insert, update, delete on public.parties to service_role;

revoke all on function public.search_customers(
  uuid,
  text,
  boolean,
  text,
  uuid,
  integer
) from public, anon;
grant execute on function public.search_customers(
  uuid,
  text,
  boolean,
  text,
  uuid,
  integer
) to authenticated, service_role;

comment on table public.parties is
  'Company-scoped CRM parties. Customers use party_type customer or both.';
comment on function public.search_customers(uuid, text, boolean, text, uuid, integer) is
  'Returns one authorized company customer page using bounded keyset pagination.';

commit;
