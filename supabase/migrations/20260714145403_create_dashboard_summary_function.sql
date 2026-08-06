begin;

-- Stable dashboard contract for the Foundation phase. Sales, invoice,
-- payment, and cash-account tables are introduced by later modules. Their
-- migrations can replace this function body without changing Flutter code.
create or replace function public.get_dashboard_summary(p_company_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private
as $$
begin
  if p_company_id is null then
    raise exception using
      errcode = '22004',
      message = 'A company ID is required.';
  end if;

  if not private.is_company_member(p_company_id) then
    raise exception using
      errcode = '42501',
      message = 'You do not have access to this company.';
  end if;

  return jsonb_build_object(
    'company_id', p_company_id,
    'today_sales', 0,
    'month_sales', 0,
    'outstanding_invoices', 0,
    'outstanding_invoice_count', 0,
    'cash_balance', 0,
    'recent_activity', '[]'::jsonb,
    'data_status', 'foundation',
    'generated_at', now()
  );
end;
$$;

revoke all on function public.get_dashboard_summary(uuid)
  from public, anon;
grant execute on function public.get_dashboard_summary(uuid)
  to authenticated, service_role;

comment on function public.get_dashboard_summary(uuid) is
  'Returns the authorized company dashboard contract. Foundation values are zero until source modules are deployed.';

commit;
