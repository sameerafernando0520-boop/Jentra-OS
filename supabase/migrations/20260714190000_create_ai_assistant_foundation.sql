begin;

-- Table: ai_conversations
create table public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null default 'New Conversation',
  created_by uuid default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_conversations_company_id_id_unique unique (company_id, id),
  constraint ai_conversations_title_not_blank check (btrim(title) <> '')
);

create index ai_conversations_company_idx on public.ai_conversations (company_id, updated_at desc, id);

create trigger set_ai_conversations_updated_at
before update on public.ai_conversations
for each row execute function private.set_updated_at();

-- Table: ai_messages
create table public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  conversation_id uuid not null references public.ai_conversations(id) on delete cascade,
  sender_role text not null, -- 'user', 'assistant', 'system'
  content text not null,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ai_messages_company_id_id_unique unique (company_id, id),
  constraint ai_messages_content_not_blank check (btrim(content) <> '')
);

create index ai_messages_company_conv_idx on public.ai_messages (company_id, conversation_id, created_at);

-- Table: ai_insights
create table public.ai_insights (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  summary text not null,
  category text not null default 'general', -- 'sales', 'cash_flow', 'inventory', 'customers', 'general'
  severity text not null default 'info', -- 'info', 'warning', 'action_required'
  action_label text,
  action_target text,
  is_dismissed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_insights_company_id_id_unique unique (company_id, id),
  constraint ai_insights_title_not_blank check (btrim(title) <> '')
);

create index ai_insights_company_idx on public.ai_insights (company_id, is_dismissed, created_at desc);

create trigger set_ai_insights_updated_at
before update on public.ai_insights
for each row execute function private.set_updated_at();

-- RLS Setup
alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;
alter table public.ai_insights enable row level security;

-- RLS Policies
create policy ai_conversations_select_member
  on public.ai_conversations for select to authenticated
  using (private.is_company_member(company_id));

create policy ai_conversations_insert_member
  on public.ai_conversations for insert to authenticated
  with check (private.is_company_member(company_id));

create policy ai_conversations_update_member
  on public.ai_conversations for update to authenticated
  using (private.is_company_member(company_id))
  with check (private.is_company_member(company_id));

create policy ai_conversations_delete_member
  on public.ai_conversations for delete to authenticated
  using (private.is_company_member(company_id));

create policy ai_messages_select_member
  on public.ai_messages for select to authenticated
  using (private.is_company_member(company_id));

create policy ai_messages_insert_member
  on public.ai_messages for insert to authenticated
  with check (private.is_company_member(company_id));

create policy ai_insights_select_member
  on public.ai_insights for select to authenticated
  using (private.is_company_member(company_id));

create policy ai_insights_update_member
  on public.ai_insights for update to authenticated
  using (private.is_company_member(company_id))
  with check (private.is_company_member(company_id));

-- Grants
grant select, insert, update, delete on public.ai_conversations to authenticated;
grant select, insert on public.ai_messages to authenticated;
grant select, update on public.ai_insights to authenticated;

grant select, insert, update, delete on public.ai_conversations to service_role;
grant select, insert, update, delete on public.ai_messages to service_role;
grant select, insert, update, delete on public.ai_insights to service_role;

-- RPC: get_company_business_summary
create or replace function public.get_company_business_summary(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_customers_count bigint := 0;
  v_products_count bigint := 0;
  v_invoices_count bigint := 0;
  v_total_revenue numeric(18, 2) := 0;
  v_receivables numeric(18, 2) := 0;
  v_cash_balance numeric(18, 2) := 0;
begin
  -- Permission check
  if not private.is_company_member(p_company_id) then
    raise exception 'Permission denied to view company AI summary.'
      using errcode = '42501';
  end if;

  -- Customers count
  select count(*) into v_customers_count
  from public.parties
  where company_id = p_company_id and party_type in ('customer', 'both');

  -- Active products count
  select count(*) into v_products_count
  from public.products
  where company_id = p_company_id and is_active = true;

  -- Total non-draft sales invoices count
  select count(*) into v_invoices_count
  from public.sales_documents
  where company_id = p_company_id and document_type = 'invoice' and status != 'draft';

  -- Total Revenue
  select coalesce(sum(grand_total), 0) into v_total_revenue
  from public.sales_documents
  where company_id = p_company_id and document_type = 'invoice' and status not in ('draft', 'cancelled', 'void');

  -- Total Outstanding Receivables
  select coalesce(sum(balance_due), 0) into v_receivables
  from public.sales_documents
  where company_id = p_company_id and document_type = 'invoice' and status in ('issued', 'partially_paid');

  -- Total Cash & Bank Balance
  select coalesce(sum(balance), 0) into v_cash_balance
  from public.money_accounts
  where company_id = p_company_id and is_active = true;

  return jsonb_build_object(
    'company_id', p_company_id,
    'customers_count', v_customers_count,
    'products_count', v_products_count,
    'invoices_count', v_invoices_count,
    'total_revenue', v_total_revenue,
    'outstanding_receivables', v_receivables,
    'cash_balance', v_cash_balance
  );
end;
$$;

revoke all on function public.get_company_business_summary(uuid) from public, anon;
grant execute on function public.get_company_business_summary(uuid) to authenticated, service_role;

commit;
