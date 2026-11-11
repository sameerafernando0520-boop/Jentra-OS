-- Live organization state is checked for every tenant membership lookup.
create function core.organization_available(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from core.tenants
    where id = p_tenant_id and status in ('trial', 'active')
  );
$$;
revoke all on function core.organization_available(uuid) from public, anon, authenticated;
grant execute on function core.organization_available(uuid) to authenticated;

create or replace function core.is_tenant_member(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.organization_available(p_tenant_id) and exists (
    select 1 from core.memberships as m
    where m.tenant_id = p_tenant_id and m.user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;
