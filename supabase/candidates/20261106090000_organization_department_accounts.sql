alter table core.organization_administrator_logins
  add column department_code text,
  add column display_name text,
  add constraint organization_department_name_required check (
    department_code is null or
      (department_code in ('hr', 'sales', 'procurement', 'finance', 'inventory', 'projects', 'service')
        and display_name is not null and char_length(display_name) between 1 and 100)
  );

create function core.organization_can_manage_staff(p_tenant_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.organization_available(p_tenant_id) and exists (
    select 1 from core.memberships as m
    join core.role_assignments as a on (a.tenant_id, a.membership_id) = (m.tenant_id, m.id)
    join core.roles as r on (r.tenant_id, r.id) = (a.tenant_id, a.role_id)
    where m.tenant_id = p_tenant_id and m.user_id = p_user_id and m.status = 'active'
      and a.legal_entity_id is null and a.branch_id is null
      and r.is_system and r.code in ('tenant_owner', 'tenant_admin')
  );
$$;
revoke all on function core.organization_can_manage_staff(uuid, uuid) from public, anon, authenticated;

create function api.organization_staff_can_provision(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select core.is_tenant_member(p_tenant_id)
    and core.organization_can_manage_staff(p_tenant_id, auth.uid());
$$;

create function api.organization_department_staff(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not api.organization_staff_can_provision(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Organization administrator required.';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'username', l.username, 'name', l.display_name, 'department', l.department_code,
      'status', m.status, 'must_change_password', l.must_change_password
    ) order by l.display_name, l.username), '[]'::jsonb)
    from core.organization_administrator_logins as l
    join core.memberships as m on (m.tenant_id, m.user_id) = (l.tenant_id, l.user_id)
    where l.tenant_id = p_tenant_id and l.department_code is not null
  );
end;
$$;

create function api.organization_register_department_staff(
  p_actor_id uuid, p_tenant_id uuid, p_user_id uuid, p_username text,
  p_display_name text, p_department text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_module text := case p_department when 'hr' then 'people' else p_department end;
  v_role_id uuid;
  v_membership_id uuid;
  v_seats integer;
begin
  perform 1 from core.tenants where id = p_tenant_id for update;
  if not core.organization_can_manage_staff(p_tenant_id, p_actor_id) then
    raise exception using errcode = '42501', message = 'Organization administrator required.';
  end if;
  if p_department is null or p_department not in ('hr', 'sales', 'procurement', 'finance', 'inventory', 'projects', 'service')
      or not exists (select 1 from core.permissions where module = v_module)
      or p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 100
      or p_display_name ~ '[[:cntrl:]]' or p_username is null
      or p_username !~ '^[a-z0-9][a-z0-9._-]{2,47}$' or right(p_username, 1) = '.' or position('..' in p_username) > 0 then
    raise exception using errcode = '22023', message = 'Invalid department account.';
  end if;
  if not exists (select 1 from auth.users as u where u.id = p_user_id
      and u.email = p_username || '@admin.jentra.invalid' and u.email_confirmed_at is not null
      and u.raw_app_meta_data->>'managed_org_admin' = 'true'
      and u.raw_app_meta_data->>'provisioned_tenant_id' = p_tenant_id::text
      and u.raw_app_meta_data->>'department_account' = p_department)
      or exists (select 1 from core.memberships where user_id = p_user_id) then
    raise exception using errcode = '42501', message = 'Department identity does not match the organization.';
  end if;
  select max(s.seats) into v_seats from billing.tenant_subscriptions as s
    where s.tenant_id = p_tenant_id and s.status in ('trialing', 'active');
  if v_seats is null or (select count(*) from core.memberships
      where tenant_id = p_tenant_id and status in ('active', 'invited')) >= v_seats then
    raise exception using errcode = '22023', message = 'No available seats.';
  end if;

  insert into core.roles (tenant_id, code, name, is_system)
    values (p_tenant_id, 'department.' || p_department,
      case p_department when 'hr' then 'HR manager' else initcap(p_department) || ' manager' end, true)
    on conflict (tenant_id, code) do nothing;
  select id into v_role_id from core.roles
    where tenant_id = p_tenant_id and code = 'department.' || p_department and is_system;
  if v_role_id is null or exists (select 1 from core.role_permissions as rp
      join core.permissions as p on p.code = rp.permission_code
      where rp.role_id = v_role_id and p.module <> v_module) then
    raise exception using errcode = '42501', message = 'Department role has incompatible permissions.';
  end if;
  insert into core.role_permissions (tenant_id, role_id, permission_code)
    select p_tenant_id, v_role_id, code from core.permissions where module = v_module
    on conflict (role_id, permission_code) do nothing;
  insert into core.organization_administrator_logins (tenant_id, user_id, username, department_code, display_name)
    values (p_tenant_id, p_user_id, p_username, p_department, btrim(p_display_name));
  insert into core.memberships (tenant_id, user_id, invited_by, joined_at)
    values (p_tenant_id, p_user_id, p_actor_id, statement_timestamp()) returning id into v_membership_id;
  insert into core.role_assignments (tenant_id, membership_id, role_id, created_by)
    values (p_tenant_id, v_membership_id, v_role_id, p_actor_id);
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (p_tenant_id, p_actor_id, gen_random_uuid(), 'organization.department_account_created', 'membership', v_membership_id);
  return v_membership_id;
end;
$$;

revoke all on function api.organization_staff_can_provision(uuid), api.organization_department_staff(uuid)
  from public, anon, authenticated;
grant execute on function api.organization_staff_can_provision(uuid), api.organization_department_staff(uuid) to authenticated;
revoke all on function api.organization_register_department_staff(uuid, uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function api.organization_register_department_staff(uuid, uuid, uuid, text, text, text) to service_role;

create or replace function core.organization_recovery_target(p_login_email text)
returns table (user_id uuid, email text) language sql stable security definer set search_path = '' as $$
  select u.id, r.email from auth.users as u
  join core.organization_account_recovery as r on r.user_id = u.id and r.verified_at is not null
  left join core.organization_administrator_logins as l on l.user_id = u.id
  where u.email = p_login_email and u.deleted_at is null and coalesce(u.encrypted_password, '') <> ''
    and (u.banned_until is null or u.banned_until <= statement_timestamp())
    and (u.raw_app_meta_data->>'managed_org_admin' is distinct from 'true'
      or (core.organization_available(l.tenant_id) and exists (
        select 1 from core.memberships m
        where (m.tenant_id, m.user_id) = (l.tenant_id, l.user_id) and m.status = 'active'
      )));
$$;

create or replace function api.platform_organization_activity(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  if not exists (select 1 from core.tenants where id = p_tenant_id) then
    raise exception using errcode = '22023', message = 'ORGANIZATION_UNAVAILABLE';
  end if;
  return jsonb_build_object(
    'administrators', (select coalesce(jsonb_agg(jsonb_build_object(
      'username', l.username, 'status', m.status, 'password_changed_at', l.password_changed_at,
      'must_change_password', l.must_change_password, 'handover_sent_at', l.handover_sent_at
    ) order by l.username), '[]'::jsonb)
    from core.organization_administrator_logins l
    join core.memberships m on (m.tenant_id, m.user_id) = (l.tenant_id, l.user_id)
    where l.tenant_id = p_tenant_id and l.department_code is null),
    'recent_activity', (select coalesce(jsonb_agg(jsonb_build_object(
      'event_type', a.event_type, 'occurred_at', a.occurred_at
    ) order by a.occurred_at desc), '[]'::jsonb) from (
      select event_type, occurred_at from audit.events where tenant_id = p_tenant_id
        and event_type like 'organization.%' order by occurred_at desc, id limit 20
    ) a)
  );
end;
$$;
