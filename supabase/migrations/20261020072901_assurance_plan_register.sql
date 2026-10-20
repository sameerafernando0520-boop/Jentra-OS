-- Corporate Audit & Assurance: audit plan register (desktop planning screens).
-- CANDIDATE ONLY. Not installed. Requires A1-A5.
--
-- api.assurance_plan reads one plan by id; nothing listed the plans in a
-- scope, so the desktop could not find existing plans. This read-only API
-- pages them (50 per page, ordered by id) under the same authority as
-- api.assurance_plan: planning managers, or anyone who may view evidence.
-- It adds no tables and changes no existing function.

create function api.assurance_plans(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_after uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_items jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if not core.has_permission(p_tenant_id, 'assurance.plan.manage', p_legal_entity_id, p_branch_id) then
    perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  end if;
  select coalesce(jsonb_agg(s.row order by s.id), '[]'::jsonb) into v_items
    from (select p.id, jsonb_build_object('id', p.id, 'name', p.name, 'status', p.status,
            'version', p.version, 'period_start', p.period_start, 'period_end', p.period_end,
            'created_by', p.created_by, 'submitted_by', p.submitted_by, 'approved_by', p.approved_by,
            'active_items', (select count(*) from assurance.plan_items i
                              where i.plan_id = p.id and i.status = 'active')) as row
            from assurance.plans p
           where p.tenant_id = p_tenant_id and p.legal_entity_id = p_legal_entity_id
             and p.branch_id is not distinct from p_branch_id
             and (p_after is null or p.id > p_after)
           order by p.id
           limit 50) s;
  return jsonb_build_object('items', v_items,
    'next_cursor', case when jsonb_array_length(v_items) = 50 then v_items->49->'id' else 'null'::jsonb end);
end $$;

revoke all on function api.assurance_plans(uuid, uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_plans(uuid, uuid, uuid, uuid) to authenticated;
