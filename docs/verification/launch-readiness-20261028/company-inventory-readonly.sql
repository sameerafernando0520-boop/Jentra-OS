-- Run only through the renewed, project-confirmed administrative connection.
-- This lists names and scope IDs for human classification; it performs no cleanup.
-- Never infer deletion authority from a name containing "test" or from fixture SQL.
begin read only;
set local statement_timeout = '10s';

select
  t.id as company_group_id,
  t.name as company_group_name,
  t.slug as workspace_slug,
  t.status as group_status,
  t.created_at,
  (select count(*) from core.memberships m where m.tenant_id = t.id)
    as membership_count,
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', e.id, 'name', e.name, 'code', e.code, 'status', e.status,
      'posting_started_at', e.posting_started_at,
      'branches', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', b.id, 'name', b.name, 'code', b.code, 'status', b.status
        ) order by b.code, b.id)
        from core.branches b
        where b.tenant_id = t.id and b.legal_entity_id = e.id
      ), '[]'::jsonb)
    ) order by e.code, e.id)
    from core.legal_entities e where e.tenant_id = t.id
  ), '[]'::jsonb) as legal_entities
from core.tenants t
order by t.created_at, t.id
limit 201;

-- If 201 groups are returned, arrange a bounded paginated inventory before
-- treating this as a complete list. Keep results in the private rollout record.
rollback;
