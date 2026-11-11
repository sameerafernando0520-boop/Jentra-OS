create table core.system_cutovers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  request_id uuid not null,
  created_by uuid not null references auth.users(id),
  status text not null default 'preparing'
    check (status in ('preparing', 'completed', 'rolled_back')),
  created_at timestamptz not null default statement_timestamp(),
  completed_at timestamptz,
  rolled_back_at timestamptz,
  unique (tenant_id, id),
  unique (created_by, request_id),
  unique (tenant_id)
);

create table core.system_cutover_roster (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  migration_id uuid not null,
  kind text not null check (kind in ('owner', 'hr_manager', 'employee')),
  source_id uuid not null,
  legacy_membership_id uuid not null,
  legacy_link_id uuid,
  legacy_user_id uuid not null references auth.users(id),
  snapshot jsonb not null,
  owner_target_id uuid,
  replacement_id uuid,
  new_membership_id uuid,
  legacy_membership_revoked boolean not null default false,
  unique (migration_id, kind, source_id),
  foreign key (tenant_id, migration_id) references core.system_cutovers(tenant_id, id),
  foreign key (tenant_id, legacy_membership_id) references core.memberships(tenant_id, id)
);

alter table core.system_cutovers enable row level security;
alter table core.system_cutover_roster enable row level security;
revoke all on core.system_cutovers, core.system_cutover_roster
  from public, anon, authenticated, service_role;

-- Capture only the grant or self-service link being replaced. Existing users
-- can legitimately hold another role in the same system or in another system.
create function core.system_cutover_sources(p_tenant_id uuid)
returns table (
  kind text, source_id uuid, membership_id uuid, link_id uuid,
  user_id uuid, snapshot jsonb
)
language sql stable set search_path = '' as $$
  select case r.code when 'tenant_owner' then 'owner' else 'hr_manager' end,
    case r.code when 'tenant_owner' then a.id else m.id end,
    m.id, null::uuid, m.user_id,
    jsonb_build_object(
      'display_name', coalesce(nullif(u.raw_user_meta_data->>'display_name', ''), t.name),
      'email', coalesce(rec.email,
        case when u.email_confirmed_at is not null and u.email not like '%@admin.jentra.invalid' then u.email end),
      'grant', to_jsonb(a)
    )
  from core.role_assignments a
  join core.roles r on (r.tenant_id,r.id) = (a.tenant_id,a.role_id)
  join core.memberships m on (m.tenant_id,m.id) = (a.tenant_id,a.membership_id)
  join core.tenants t on t.id = a.tenant_id
  join auth.users u on u.id = m.user_id
  left join core.organization_account_recovery rec on rec.user_id = m.user_id and rec.verified_at is not null
  where a.tenant_id = p_tenant_id and m.status = 'active'
    and a.legal_entity_id is null and a.branch_id is null
    and r.is_system and r.code in ('tenant_owner', 'department.hr')
  union all
  select 'employee', l.id, m.id, l.id, l.user_id,
    jsonb_build_object(
      'display_name', coalesce(to_jsonb(e)->>'display_name', to_jsonb(e)->>'full_name',
        to_jsonb(e)->>'employee_code', l.employee_id::text),
      'email', coalesce(rec.email,
        case when u.email_confirmed_at is not null and u.email not like '%@admin.jentra.invalid' then u.email end),
      'employee_id', l.employee_id, 'legal_entity_id', l.legal_entity_id,
      'branch_id', l.branch_id, 'link_version', l.version
    )
  from people_private.account_links l
  join core.memberships m on (m.tenant_id,m.id) = (l.tenant_id,l.membership_id)
  join people.employees e on (e.tenant_id,e.legal_entity_id,e.id) = (l.tenant_id,l.legal_entity_id,l.employee_id)
  join auth.users u on u.id = l.user_id
  left join core.organization_account_recovery rec on rec.user_id = l.user_id and rec.verified_at is not null
  where l.tenant_id = p_tenant_id and l.status = 'accepted' and m.status = 'active'
    and people_private.managed_employee_is_current(l.tenant_id,l.legal_entity_id,l.branch_id,l.employee_id)
    and not exists (select 1 from people_private.managed_staff_identities i where i.link_id = l.id);
$$;

create function api.platform_system_cutover_stage_target(
  p_migration_id uuid, p_legacy_membership_id uuid, p_legacy_link_id uuid, p_kind text
) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  return exists (
    select 1 from core.system_cutovers c join core.system_cutover_roster r on r.migration_id = c.id
    where c.id = p_migration_id and c.status = 'preparing'
      and r.legacy_membership_id = p_legacy_membership_id
      and r.legacy_link_id is not distinct from p_legacy_link_id and r.kind = p_kind
  );
end;
$$;

create function api.platform_system_cutover_status(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_cutover core.system_cutovers;
  v_serial text;
  v_primary uuid;
  v_owners integer;
begin
  perform intelligence_control.operator_required('organization');
  select system_serial, primary_owner_user_id into v_serial, v_primary
    from core.tenants where id = p_tenant_id;
  if not found then raise exception using errcode = '22023', message = 'SYSTEM_UNAVAILABLE'; end if;
  select * into v_cutover from core.system_cutovers where tenant_id = p_tenant_id;
  select count(*) into v_owners from core.system_cutover_sources(p_tenant_id) where kind = 'owner';
  return jsonb_build_object(
    'tenant_id', p_tenant_id, 'serial', v_serial, 'migration_id', v_cutover.id,
    'status', coalesce(v_cutover.status, 'not_started'),
    'legacy_owner_count', v_owners,
    'can_start', v_cutover.id is null and v_serial is not null and v_primary is null and v_owners = 1,
    'entities', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name,id)
      from core.legal_entities where tenant_id = p_tenant_id and status = 'active'), '[]'),
    'roster', coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'kind', r.kind, 'legacy_membership_id', r.legacy_membership_id,
      'legacy_link_id', r.legacy_link_id, 'display_name', r.snapshot->>'display_name',
      'email', r.snapshot->>'email', 'employee_id', r.snapshot->>'employee_id',
      'legal_entity_id', r.snapshot->>'legal_entity_id', 'branch_id', r.snapshot->>'branch_id',
      'username', coalesce(t.username, i.username), 'replacement_id', coalesce(t.id, i.id),
      'verification_id', t.id, 'delivery', i.delivery,
      'credential_status', case when t.id is not null and t.verified_at is null
        then 'verification_required' else coalesce(j.status, i.status, 'unassigned') end,
      'ready', case when r.kind = 'owner' then coalesce(j.status = 'completed', false)
        else coalesce(i.status in ('ready','active') and i.password_ready_at is not null, false) end
      ) order by case r.kind when 'owner' then 0 when 'hr_manager' then 1 else 2 end,
        r.snapshot->>'display_name', r.id)
      from core.system_cutover_roster r
      left join billing.system_owner_handover_targets t on t.id = r.owner_target_id and t.tenant_id = r.tenant_id
      left join billing.subscription_handover_jobs j on j.order_id = t.id and j.tenant_id = t.tenant_id
      left join lateral (
        select s.* from people_private.managed_staff_identities s
        where s.tenant_id = r.tenant_id and s.migration_id = r.migration_id and s.kind = r.kind
          and s.supersedes_membership_id = r.legacy_membership_id
          and s.supersedes_link_id is not distinct from r.legacy_link_id
          and s.status <> 'revoked'
        order by s.created_at desc, s.id limit 1
      ) i on true
      where r.migration_id = v_cutover.id), '[]')
  );
end;
$$;

create function api.platform_begin_system_cutover(p_tenant_id uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant core.tenants;
  v_cutover uuid;
begin
  perform intelligence_control.operator_required('organization');
  select * into v_tenant from core.tenants where id = p_tenant_id for update;
  if not found or not core.organization_available(p_tenant_id)
      or v_tenant.system_serial is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'SYSTEM_CUTOVER_UNAVAILABLE';
  end if;
  if exists (select 1 from core.system_cutovers where tenant_id = p_tenant_id) then
    return api.platform_system_cutover_status(p_tenant_id);
  end if;
  if v_tenant.primary_owner_user_id is not null or
    (select count(*) from core.system_cutover_sources(p_tenant_id) where kind = 'owner') <> 1 then
    raise exception using errcode = '22023', message = 'SYSTEM_CUTOVER_OWNER_AMBIGUOUS';
  end if;
  if exists (
    select 1 from core.system_cutover_sources(p_tenant_id)
    group by kind, source_id having count(*) > 1
  ) then raise exception using errcode = '22023', message = 'SYSTEM_CUTOVER_ROSTER_AMBIGUOUS'; end if;
  insert into core.system_cutovers (tenant_id, request_id, created_by)
    values (p_tenant_id, p_request_id, auth.uid()) returning id into v_cutover;
  insert into core.system_cutover_roster
    (tenant_id,migration_id,kind,source_id,legacy_membership_id,legacy_link_id,legacy_user_id,snapshot)
  select p_tenant_id,v_cutover,kind,source_id,membership_id,link_id,user_id,snapshot
    from core.system_cutover_sources(p_tenant_id);
  insert into audit.events(tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id)
    values (p_tenant_id,auth.uid(),p_request_id,'system.cutover_prepared','system_cutover',v_cutover);
  return api.platform_system_cutover_status(p_tenant_id);
end;
$$;

create function api.platform_stage_system_owner_cutover(p_migration_id uuid,p_owner_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_cutover core.system_cutovers; v_result jsonb;
begin
  perform intelligence_control.operator_required('organization');
  select * into v_cutover from core.system_cutovers where id = p_migration_id for update;
  if not found or v_cutover.status <> 'preparing' then
    raise exception using errcode = '22023', message = 'SYSTEM_CUTOVER_UNAVAILABLE';
  end if;
  v_result := billing.stage_system_owner_cutover(v_cutover.tenant_id,auth.uid(),p_owner_email);
  update core.system_cutover_roster r set owner_target_id = (
    select id from billing.system_owner_handover_targets
    where tenant_id = v_cutover.tenant_id and source = 'cutover'
  ) where r.migration_id = p_migration_id and r.kind = 'owner';
  return v_result;
end;
$$;

create function api.system_replacement_status() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when exists (
    select 1 from core.system_cutovers c
    join core.system_cutover_roster r on r.migration_id = c.id
    join billing.subscription_handover_jobs j on (j.order_id,j.tenant_id) = (r.owner_target_id,r.tenant_id)
    where c.status in ('preparing','rolled_back') and j.user_id = auth.uid()
  ) or exists (
    select 1 from people_private.managed_staff_identities i
    join core.system_cutovers c on c.id = i.migration_id and c.tenant_id = i.tenant_id
    where c.status in ('preparing','rolled_back') and i.user_id = auth.uid()
  ) then jsonb_build_object('replacement_pending',true) end;
$$;

create function api.platform_commit_system_cutover(p_migration_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_cutover core.system_cutovers;
  v_roster core.system_cutover_roster;
  v_replacement uuid;
  v_user uuid;
  v_membership uuid;
  v_revoked boolean;
begin
  perform intelligence_control.operator_required('organization');
  select * into v_cutover from core.system_cutovers where id = p_migration_id for update;
  if not found then raise exception using errcode = '22023', message = 'SYSTEM_CUTOVER_UNAVAILABLE'; end if;
  if v_cutover.status = 'completed' then return api.platform_system_cutover_status(v_cutover.tenant_id); end if;
  if v_cutover.status <> 'preparing' or not core.organization_available(v_cutover.tenant_id) then
    raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_UNAVAILABLE';
  end if;
  perform 1 from core.tenants where id = v_cutover.tenant_id
    and primary_owner_user_id is null for update;
  if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_ROSTER_CHANGED'; end if;

  if exists (
    with live as (
      select kind,source_id,membership_id,link_id,user_id,snapshot->>'link_version' as link_version
        from core.system_cutover_sources(v_cutover.tenant_id)
    ), planned as (
      select kind,source_id,legacy_membership_id,legacy_link_id,legacy_user_id,snapshot->>'link_version'
        from core.system_cutover_roster where migration_id = p_migration_id
    )
    (select * from live except select * from planned)
    union all
    (select * from planned except select * from live)
  ) then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_ROSTER_CHANGED'; end if;

  for v_roster in select * from core.system_cutover_roster
    where migration_id = p_migration_id order by case kind when 'owner' then 0 when 'hr_manager' then 1 else 2 end,id
    for update
  loop
    if v_roster.kind = 'owner' then
      select j.user_id into v_user
      from billing.system_owner_handover_targets t
      join billing.subscription_handover_jobs j on (j.order_id,j.tenant_id) = (t.id,t.tenant_id)
      join core.organization_administrator_logins l on (l.user_id,l.tenant_id,l.checkout_order_id)
        = (j.user_id,t.tenant_id,t.id)
      where t.id = v_roster.owner_target_id and t.tenant_id = v_cutover.tenant_id and t.source = 'cutover'
        and t.verified_at is not null and j.status = 'completed' and not l.must_change_password
      for update of j,l;
      if v_user is null then raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_NOT_READY'; end if;
      insert into core.memberships(tenant_id,user_id,invited_by,joined_at)
        values(v_cutover.tenant_id,v_user,auth.uid(),statement_timestamp()) returning id into v_membership;
      update core.role_assignments set membership_id = v_membership
        where id = v_roster.source_id and tenant_id = v_cutover.tenant_id
          and membership_id = v_roster.legacy_membership_id;
      if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_ROSTER_CHANGED'; end if;
      update core.memberships m set status = 'revoked', version = version+1
        where m.id = v_roster.legacy_membership_id and m.status = 'active'
          and not exists (select 1 from core.role_assignments a where a.membership_id = m.id)
          and not exists (select 1 from people_private.account_links l
            where l.membership_id = m.id and l.status in ('accepted','pending'));
      v_revoked := found;
      update core.tenants set primary_owner_user_id = v_user, version = version+1
        where id = v_cutover.tenant_id;
      update core.system_cutover_roster
        set new_membership_id = v_membership, legacy_membership_revoked = v_revoked
        where id = v_roster.id;
    else
      select id into v_replacement from people_private.managed_staff_identities i
        where i.tenant_id = v_cutover.tenant_id and i.migration_id = p_migration_id and i.kind = v_roster.kind
          and i.supersedes_membership_id = v_roster.legacy_membership_id
          and i.supersedes_link_id is not distinct from v_roster.legacy_link_id
          and i.status = 'ready' and i.password_ready_at is not null
        for update;
      if v_replacement is null then raise exception using errcode = '42501', message = 'SYSTEM_CUTOVER_NOT_READY'; end if;
      perform people_private.activate_managed_staff_identity(v_replacement,auth.uid());
      if not exists (select 1 from people_private.managed_staff_identities
        where id = v_replacement and status = 'active') then
        raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_STAFF_NOT_ACTIVE';
      end if;
      update core.system_cutover_roster set replacement_id = v_replacement where id = v_roster.id;
    end if;
  end loop;
  update core.system_cutovers set status = 'completed', completed_at = statement_timestamp() where id = p_migration_id;
  insert into audit.events(tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id)
    values(v_cutover.tenant_id,auth.uid(),gen_random_uuid(),'system.cutover_completed','system_cutover',p_migration_id);
  return api.platform_system_cutover_status(v_cutover.tenant_id);
end;
$$;

create function api.platform_rollback_system_cutover(p_migration_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_cutover core.system_cutovers;
  v_roster core.system_cutover_roster;
  v_new_owner uuid;
begin
  perform intelligence_control.operator_required('organization');
  select * into v_cutover from core.system_cutovers where id = p_migration_id for update;
  if not found then raise exception using errcode = '22023', message = 'SYSTEM_CUTOVER_UNAVAILABLE'; end if;
  if v_cutover.status = 'rolled_back' then return api.platform_system_cutover_status(v_cutover.tenant_id); end if;
  if v_cutover.status <> 'completed' or not core.organization_available(v_cutover.tenant_id)
    or p_reason is null or length(trim(p_reason)) not between 5 and 500 then
    raise exception using errcode = '22023', message = 'SYSTEM_CUTOVER_ROLLBACK_REQUIRED';
  end if;
  perform 1 from core.tenants where id = v_cutover.tenant_id for update;
  for v_roster in select * from core.system_cutover_roster
    where migration_id = p_migration_id order by case kind when 'employee' then 0 when 'hr_manager' then 1 else 2 end,id
    for update
  loop
    if v_roster.kind = 'owner' then
      select user_id into v_new_owner from core.memberships
        where id = v_roster.new_membership_id and tenant_id = v_cutover.tenant_id;
      if v_new_owner is null then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_ROSTER_CHANGED'; end if;
      update core.tenants set primary_owner_user_id = null, version = version+1
        where id = v_cutover.tenant_id and primary_owner_user_id = v_new_owner;
      if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_ROSTER_CHANGED'; end if;
      update core.role_assignments set membership_id = v_roster.legacy_membership_id
        where id = v_roster.source_id and membership_id = v_roster.new_membership_id;
      if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_ROSTER_CHANGED'; end if;
      if v_roster.legacy_membership_revoked then
        update core.memberships set status = 'active', version = version+1
          where id = v_roster.legacy_membership_id and status = 'revoked';
        if not found then raise exception using errcode = '40001', message = 'SYSTEM_CUTOVER_ROSTER_CHANGED'; end if;
      end if;
      update core.memberships m set status = 'revoked', version = version+1
        where m.id = v_roster.new_membership_id and m.status = 'active'
          and not exists (select 1 from core.role_assignments a where a.membership_id = m.id)
          and not exists (select 1 from people_private.account_links l
            where l.membership_id = m.id and l.status in ('accepted','pending'));
    else
      perform people_private.rollback_managed_staff_identity(v_roster.replacement_id,auth.uid());
    end if;
  end loop;
  update core.system_cutovers set status = 'rolled_back', rolled_back_at = statement_timestamp() where id = p_migration_id;
  insert into audit.events(tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id,after_context)
    values(v_cutover.tenant_id,auth.uid(),gen_random_uuid(),'system.cutover_rolled_back','system_cutover',p_migration_id,
      jsonb_build_object('reason',trim(p_reason)));
  return api.platform_system_cutover_status(v_cutover.tenant_id);
end;
$$;

revoke all on function core.system_cutover_sources(uuid),
  api.platform_system_cutover_stage_target(uuid,uuid,uuid,text),
  api.platform_system_cutover_status(uuid), api.platform_begin_system_cutover(uuid,uuid),
  api.platform_stage_system_owner_cutover(uuid,text), api.system_replacement_status(),
  api.platform_commit_system_cutover(uuid), api.platform_rollback_system_cutover(uuid,text)
  from public,anon,authenticated,service_role;

grant execute on function api.platform_system_cutover_stage_target(uuid,uuid,uuid,text),
  api.platform_system_cutover_status(uuid), api.platform_begin_system_cutover(uuid,uuid),
  api.platform_stage_system_owner_cutover(uuid,text), api.system_replacement_status(),
  api.platform_commit_system_cutover(uuid), api.platform_rollback_system_cutover(uuid,text)
  to authenticated;

select organization_lifecycle.install_write_guards();
