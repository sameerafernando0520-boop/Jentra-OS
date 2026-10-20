-- Corporate Audit & Assurance A14: people for pickers.
-- CANDIDATE ONLY. Not installed. Requires A1-A5 and A8 (assurance.member_label).
--
-- Planning and engagement commands name an area owner or a lead auditor by
-- user id. This read lets planners and engagement managers choose them by
-- name instead: the tenant's active members with their display label (the
-- linked employee's name, or "Unlinked member ····1234", never an e-mail),
-- ordered by label, at most 500.

create function api.assurance_people(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if not core.has_permission(p_tenant_id, 'core.roles.manage')
     and not core.has_permission(p_tenant_id, 'assurance.plan.manage', p_legal_entity_id, p_branch_id)
     and not core.has_permission(p_tenant_id, 'assurance.engagement.manage', p_legal_entity_id, p_branch_id) then
    perform assurance.deny('ASSURANCE_ACCESS_DENIED');
  end if;
  return jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', s.user_id, 'label', s.label) order by s.label, s.user_id)
        from (select m.user_id, assurance.member_label(p_tenant_id, m.id) as label
                from core.memberships m
               where m.tenant_id = p_tenant_id and m.status = 'active'
               order by 2, 1
               limit 500) s), '[]'::jsonb),
    'truncated', (select count(*) > 500 from core.memberships m
                   where m.tenant_id = p_tenant_id and m.status = 'active'));
end $$;

revoke all on function api.assurance_people(uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_people(uuid, uuid, uuid) to authenticated;
