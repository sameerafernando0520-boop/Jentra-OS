create function api.platform_organization_activity(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  if not exists (select 1 from core.tenants where id = p_tenant_id) then
    raise exception using errcode = '22023', message = 'ORGANIZATION_UNAVAILABLE';
  end if;
  return jsonb_build_object(
    'administrators', (select coalesce(jsonb_agg(jsonb_build_object(
      'username', l.username, 'status', m.status,
      'password_changed_at', l.password_changed_at,
      'must_change_password', l.must_change_password,
      'handover_sent_at', l.handover_sent_at
    ) order by l.username), '[]'::jsonb)
    from core.organization_administrator_logins l
    join core.memberships m on m.tenant_id = l.tenant_id and m.user_id = l.user_id
    where l.tenant_id = p_tenant_id),
    'recent_activity', (select coalesce(jsonb_agg(jsonb_build_object(
      'event_type', a.event_type, 'occurred_at', a.occurred_at
    ) order by a.occurred_at desc), '[]'::jsonb) from (
      select event_type, occurred_at from audit.events
      where tenant_id = p_tenant_id and event_type like 'organization.%'
      order by occurred_at desc, id limit 20
    ) a)
  );
end;
$$;
revoke all on function api.platform_organization_activity(uuid)
  from public, anon, authenticated;
grant execute on function api.platform_organization_activity(uuid) to authenticated;
