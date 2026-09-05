-- Complete FR-318 by adding explicit as-of opportunity aging to the CRM
-- pipeline summary. Preserve the published v1 calculation as a private,
-- security-invoker base so currency, stage, forecast, conversion, win/loss,
-- and activity calculations remain unchanged.

alter function api.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  set schema crm;
alter function crm.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  rename to wave3_pipeline_summary_base;

revoke all on function crm.wave3_pipeline_summary_base(uuid, uuid, uuid, date)
  from public, anon, authenticated;
grant execute on function crm.wave3_pipeline_summary_base(
  uuid, uuid, uuid, date
) to authenticated;

create function api.get_crm_pipeline_summary(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_as_of_date date
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_summary jsonb;
  v_open_count bigint;
  v_average_age numeric(20, 6);
  v_oldest_age integer;
  v_stale_count bigint;
  v_stale_after_days constant integer := 90;
begin
  v_summary := crm.wave3_pipeline_summary_base(
    p_tenant_id, p_legal_entity_id, p_branch_id, p_as_of_date
  );

  select
    count(*) filter (where o.status = 'open'),
    coalesce(
      round(avg(greatest(p_as_of_date - o.created_at::date, 0))
        filter (where o.status = 'open'), 6),
      0
    )::numeric(20, 6),
    coalesce(
      max(greatest(p_as_of_date - o.created_at::date, 0))
        filter (where o.status = 'open'),
      0
    ),
    count(*) filter (
      where o.status = 'open'
        and p_as_of_date - o.created_at::date > v_stale_after_days
    )
    into v_open_count, v_average_age, v_oldest_age, v_stale_count
  from api.crm_opportunities as o
  where o.tenant_id = p_tenant_id
    and o.legal_entity_id = p_legal_entity_id
    and (p_branch_id is null or o.branch_id = p_branch_id)
    and o.created_at::date <= p_as_of_date;

  return v_summary || jsonb_build_object(
    'aging', jsonb_build_object(
      'age_basis', 'created_at',
      'stale_after_days', v_stale_after_days,
      'open_opportunity_count', v_open_count,
      'average_age_days', v_average_age::text,
      'oldest_age_days', v_oldest_age,
      'stale_opportunity_count', v_stale_count
    )
  );
end;
$$;

revoke all on function api.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  from public, anon, authenticated;
grant execute on function api.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  to authenticated;

comment on function crm.wave3_pipeline_summary_base(uuid, uuid, uuid, date)
  is 'Private security-invoker base for the Wave 3 CRM pipeline summary.';
comment on function api.get_crm_pipeline_summary(uuid, uuid, uuid, date)
  is 'Currency-separated exact CRM pipeline totals and aging for an explicit as-of date.';

notify pgrst, 'reload schema';
