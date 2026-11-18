-- Bridge between company administration (20261028130000) and managed sign-ins.
--
-- Company administration guards every new core.memberships row: the caller
-- must be a signed-in company administrator with recent MFA. Organization
-- handover, department accounts, managed HR identities and the system owner
-- cutover create the membership of a managed sign-in from a service worker or
-- a platform operator, so that guard rejects them.
--
-- A managed sign-in is already governed on insert by
-- core.organization_check_managed_membership, and its login row can only be
-- written by the provisioning functions, which authorize the caller
-- themselves. Skip the company administration guard for the INSERT of exactly
-- that membership: the managed user, in the tenant its login is assigned to.
-- Every membership of an ordinary account stays under the company
-- administration guard, with one exception below.
--
-- Rolling back a completed system cutover restores the legacy memberships that
-- the cutover revoked. A platform operator runs it, not a company
-- administrator. Skip the guard for that reactivation only: the membership is
-- recorded as revoked by a completed cutover, and the caller passes the
-- operator check for organization management.
--
-- Without company administration installed this candidate only adds the helper.
-- Installing company administration after this candidate is not supported.
create function core.organization_membership_is_managed(p_tenant_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from core.organization_administrator_logins as l
    join auth.users as u on u.id = l.user_id
    where l.user_id = p_user_id and l.tenant_id = p_tenant_id
      and u.raw_app_meta_data->>'managed_org_admin' = 'true'
  );
$$;

revoke all on function core.organization_membership_is_managed(uuid,uuid) from public, anon;
grant execute on function core.organization_membership_is_managed(uuid,uuid) to authenticated, service_role;

create function core.organization_membership_cutover_restore(p_tenant_id uuid, p_membership_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from core.system_cutover_roster as r
    join core.system_cutovers as c on (c.tenant_id, c.id) = (r.tenant_id, r.migration_id)
    where r.tenant_id = p_tenant_id and r.legacy_membership_id = p_membership_id
      and r.kind = 'owner' and r.legacy_membership_revoked and c.status = 'completed'
  ) and not exists (
    select 1 from people_private.managed_staff_identities as i
    join core.system_cutovers as c on (c.tenant_id, c.id) = (i.tenant_id, i.migration_id)
    where i.tenant_id = p_tenant_id and i.supersedes_membership_id = p_membership_id
      and i.status = 'active' and i.legacy_membership_revoked and c.status = 'completed'
  ) then
    return false;
  end if;
  perform intelligence_control.operator_required('organization');
  return true;
exception when insufficient_privilege then
  return false;
end;
$$;

revoke all on function core.organization_membership_cutover_restore(uuid,uuid) from public, anon;
grant execute on function core.organization_membership_cutover_restore(uuid,uuid) to authenticated, service_role;

do $bridge$
begin
  if to_regprocedure('workspace_admin.guard_membership_activation()') is not null then
    drop trigger workspace_admin_membership_activation_guard on core.memberships;
    create trigger workspace_admin_membership_activation_guard before update on core.memberships
      for each row when (not (old.status = 'revoked' and new.status = 'active'
        and core.organization_membership_cutover_restore(new.tenant_id, new.id)))
      execute function workspace_admin.guard_membership_activation();
    create trigger workspace_admin_membership_insert_guard before insert on core.memberships
      for each row when (not core.organization_membership_is_managed(new.tenant_id, new.user_id))
      execute function workspace_admin.guard_membership_activation();
  end if;
end;
$bridge$;
