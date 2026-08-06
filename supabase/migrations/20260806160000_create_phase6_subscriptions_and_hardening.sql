begin;

-- 1. Table: plans
create table public.plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  price_cents bigint not null default 0,
  max_members integer not null default 5,
  max_monthly_invoices integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_plans_updated_at
before update on public.plans
for each row execute function private.set_updated_at();

alter table public.plans enable row level security;

create policy plans_select_authenticated on public.plans for select to authenticated using (true);

grant select on public.plans to authenticated;
grant select, insert, update, delete on public.plans to service_role;

-- Seed baseline plans
insert into public.plans (name, code, price_cents, max_members, max_monthly_invoices) values
  ('Starter Plan', 'starter', 2900, 3, 50),
  ('Growth Plan', 'growth', 7900, 10, 500),
  ('Enterprise Plan', 'enterprise', 19900, 100, 5000)
on conflict (code) do nothing;

-- 2. Table: company_subscriptions
create table public.company_subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  plan_id uuid not null references public.plans(id) on delete restrict,
  status text not null default 'trialing',
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz not null default (now() + interval '30 days'),
  trial_ends_at timestamptz default (now() + interval '14 days'),
  canceled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_subscriptions_company_id_id_unique unique (company_id, id),
  constraint company_subscriptions_company_id_unique unique (company_id)
);

create trigger set_company_subscriptions_updated_at
before update on public.company_subscriptions
for each row execute function private.set_updated_at();

alter table public.company_subscriptions enable row level security;

create policy company_subscriptions_select_member
  on public.company_subscriptions for select to authenticated
  using (private.is_company_member(company_id));

grant select on public.company_subscriptions to authenticated;
grant select, insert, update, delete on public.company_subscriptions to service_role;

-- 3. Table: subscription_events
create table public.subscription_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.subscription_events enable row level security;

create policy subscription_events_select_member
  on public.subscription_events for select to authenticated
  using (private.is_company_member(company_id));

grant select on public.subscription_events to authenticated;
grant select, insert, update, delete on public.subscription_events to service_role;

-- 4. Server Helper: private.check_subscription_entitlement
create or replace function private.check_subscription_entitlement(
  p_company_id uuid,
  p_feature text default 'general'
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_sub public.company_subscriptions;
begin
  select * into v_sub
  from public.company_subscriptions
  where company_id = p_company_id;

  if v_sub.id is null then
    return false;
  end if;

  if v_sub.status = 'active' then
    return true;
  end if;

  if v_sub.status = 'trialing' and v_sub.trial_ends_at is not null and now() <= v_sub.trial_ends_at then
    return true;
  end if;

  return false;
end;
$$;

-- 5. Public RPC: get_company_subscription_status
create or replace function public.get_company_subscription_status(
  p_company_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_sub public.company_subscriptions;
  v_plan public.plans;
  v_is_entitled boolean;
begin
  if not private.is_company_member(p_company_id) then
    raise exception 'Permission denied.' using errcode = '42501';
  end if;

  select * into v_sub
  from public.company_subscriptions
  where company_id = p_company_id;

  v_is_entitled := private.check_subscription_entitlement(p_company_id, 'general');

  if v_sub.id is null then
    return jsonb_build_object(
      'has_subscription', false,
      'status', 'none',
      'is_entitled', false
    );
  end if;

  select * into v_plan
  from public.plans
  where id = v_sub.plan_id;

  return jsonb_build_object(
    'has_subscription', true,
    'status', v_sub.status,
    'is_entitled', v_is_entitled,
    'plan_name', v_plan.name,
    'plan_code', v_plan.code,
    'max_members', v_plan.max_members,
    'max_monthly_invoices', v_plan.max_monthly_invoices,
    'current_period_end', v_sub.current_period_end,
    'trial_ends_at', v_sub.trial_ends_at
  );
end;
$$;

revoke all on function public.get_company_subscription_status(uuid) from public, anon;
grant execute on function public.get_company_subscription_status(uuid) to authenticated, service_role;

commit;
