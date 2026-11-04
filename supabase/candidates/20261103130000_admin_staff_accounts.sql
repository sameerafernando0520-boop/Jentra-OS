-- Candidate only. Requires company_access_administration and session_mfa_policy.
-- Passwords are handled solely by Supabase Auth's server-side Admin API.
create table workspace_admin.staff_accounts (
  request_id uuid primary key,
  tenant_id uuid not null references core.tenants(id),
  created_by uuid not null references auth.users(id),
  username text not null unique check (username ~ '^[a-z0-9][a-z0-9_-]{2,39}$'),
  display_name text not null check (length(display_name) between 1 and 100),
  role_ids uuid[] not null check (cardinality(role_ids) between 1 and 16),
  user_id uuid unique references auth.users(id),
  membership_id uuid unique references core.memberships(id),
  created_at timestamptz not null default now(),
  check ((user_id is null) = (membership_id is null))
);
alter table workspace_admin.staff_accounts enable row level security;
revoke all on workspace_admin.staff_accounts from public, anon, authenticated, service_role;

create table workspace_admin.staff_login_attempts (
  key text primary key,
  bucket bigint not null,
  attempts integer not null
);
alter table workspace_admin.staff_login_attempts enable row level security;
revoke all on workspace_admin.staff_login_attempts from public, anon, authenticated, service_role;

create function api.workspace_staff_reserve(p_tenant_id uuid, p_request_id uuid,
  p_username text, p_display_name text, p_role_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); reservation workspace_admin.staff_accounts%rowtype;
  normalized text := lower(trim(p_username)); roles uuid[]; role_id uuid; existing_user uuid;
begin
  perform workspace_admin.require_admin(p_tenant_id, 'core.members.invite');
  perform workspace_admin.require_admin(p_tenant_id, 'core.roles.manage');
  if not core.session_has_mfa() then
    raise exception using errcode='42501', message='ADMIN_RECENT_MFA_REQUIRED';
  end if;
  if p_request_id is null or normalized is null or normalized !~ '^[a-z0-9][a-z0-9_-]{2,39}$'
    or p_display_name is null or trim(p_display_name) = '' or length(p_display_name)>100
    or p_display_name ~ '[[:cntrl:]]' or p_role_ids is null or cardinality(p_role_ids) not between 1 and 16
    or array_position(p_role_ids, null) is not null then
    raise exception using errcode='22023', message='STAFF_ACCOUNT_INVALID';
  end if;
  select array_agg(distinct id order by id) into roles from unnest(p_role_ids) id;
  perform 1 from core.tenants where id=p_tenant_id for update;
  -- The caller may have waited behind a concurrent access revocation.
  perform workspace_admin.require_admin(p_tenant_id, 'core.members.invite');
  perform workspace_admin.require_admin(p_tenant_id, 'core.roles.manage');
  if not core.session_has_mfa() then
    raise exception using errcode='42501', message='ADMIN_RECENT_MFA_REQUIRED';
  end if;
  -- Reclaim expired requests only when Auth never created an identity. Never
  -- delete or adopt an Auth account, including a partially completed account.
  delete from workspace_admin.staff_accounts a where a.tenant_id=p_tenant_id
    and a.user_id is null and a.created_at<now()-interval '24 hours'
    and not exists(select 1 from auth.users u
      where lower(u.email)='staff.'||replace(a.request_id::text,'-','')||'@accounts.jentra.invalid');
  foreach role_id in array roles loop
    perform workspace_admin.require_role(p_tenant_id, role_id, null, null);
  end loop;
  select * into reservation from workspace_admin.staff_accounts where request_id=p_request_id for update;
  if found then
    if reservation.tenant_id<>p_tenant_id or reservation.created_by<>actor
      or reservation.username<>normalized or reservation.display_name<>trim(p_display_name)
      or reservation.role_ids<>roles then
      raise exception using errcode='22023', message='STAFF_REQUEST_CHANGED';
    end if;
  else
    perform workspace_admin.require_seat(p_tenant_id, gen_random_uuid());
    if (select count(*) from workspace_admin.staff_accounts
        where tenant_id=p_tenant_id and created_by=actor and user_id is null)>=20
      or (select count(*) from workspace_admin.staff_accounts where tenant_id=p_tenant_id and user_id is null)
        +(select count(*) from core.memberships where tenant_id=p_tenant_id and status in('active','invited'))
        >=(select seats from billing.tenant_subscriptions where tenant_id=p_tenant_id) then
      raise exception using errcode='23514', message='STAFF_RESERVATION_LIMIT';
    end if;
    insert into workspace_admin.staff_accounts(request_id,tenant_id,created_by,username,display_name,role_ids)
      values(p_request_id,p_tenant_id,actor,normalized,trim(p_display_name),roles)
      returning * into reservation;
  end if;
  select u.id into existing_user from auth.users u
    where lower(u.email)='staff.'||replace(p_request_id::text,'-','')||'@accounts.jentra.invalid'
      and u.raw_app_meta_data->>'jentra_staff_request'=p_request_id::text
      and u.raw_app_meta_data->>'jentra_tenant_id'=p_tenant_id::text
      and u.raw_app_meta_data->>'jentra_created_by'=actor::text
      and u.raw_app_meta_data->>'jentra_username'=normalized;
  if reservation.user_id is not null and existing_user is distinct from reservation.user_id then
    raise exception using errcode='42501', message='STAFF_IDENTITY_UNAVAILABLE';
  end if;
  return jsonb_build_object('request_id',p_request_id,'tenant_id',p_tenant_id,'created_by',actor,
    'username',normalized,'display_name',reservation.display_name,'role_ids',to_jsonb(roles),
    'email','staff.'||replace(p_request_id::text,'-','')||'@accounts.jentra.invalid',
    'user_id',existing_user,'completed',reservation.membership_id is not null,
    'membership_id',reservation.membership_id);
end;
$$;

create function api.workspace_staff_complete(p_tenant_id uuid, p_request_id uuid, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); reservation workspace_admin.staff_accounts%rowtype;
  role_id uuid; member_id uuid; result jsonb;
begin
  perform workspace_admin.require_admin(p_tenant_id, 'core.members.invite');
  perform workspace_admin.require_admin(p_tenant_id, 'core.roles.manage');
  if not core.session_has_mfa() then
    raise exception using errcode='42501', message='ADMIN_RECENT_MFA_REQUIRED';
  end if;
  perform 1 from core.tenants where id=p_tenant_id for update;
  perform workspace_admin.require_admin(p_tenant_id, 'core.members.invite');
  perform workspace_admin.require_admin(p_tenant_id, 'core.roles.manage');
  if not core.session_has_mfa() then
    raise exception using errcode='42501', message='ADMIN_RECENT_MFA_REQUIRED';
  end if;
  select * into reservation from workspace_admin.staff_accounts
    where request_id=p_request_id and tenant_id=p_tenant_id and created_by=actor for update;
  if not found or p_user_id is null or not exists (
    select 1 from auth.users u where u.id=p_user_id and u.email_confirmed_at is not null
      and lower(u.email)='staff.'||replace(p_request_id::text,'-','')||'@accounts.jentra.invalid'
      and u.raw_app_meta_data->>'jentra_staff_request'=p_request_id::text
      and u.raw_app_meta_data->>'jentra_tenant_id'=p_tenant_id::text
      and u.raw_app_meta_data->>'jentra_created_by'=actor::text
      and u.raw_app_meta_data->>'jentra_username'=reservation.username
  ) then
    raise exception using errcode='42501', message='STAFF_IDENTITY_UNAVAILABLE';
  end if;
  foreach role_id in array reservation.role_ids loop
    perform workspace_admin.require_role(p_tenant_id,role_id,null,null);
  end loop;
  if reservation.membership_id is not null then
    if reservation.user_id<>p_user_id or not exists (
      select 1 from core.memberships m where m.id=reservation.membership_id
        and m.tenant_id=p_tenant_id and m.user_id=p_user_id and m.status='active'
    ) then
      raise exception using errcode='42501', message='STAFF_IDENTITY_UNAVAILABLE';
    end if;
    if exists(select 1 from core.role_assignments a
        where a.tenant_id=p_tenant_id and a.membership_id=reservation.membership_id
          and (a.legal_entity_id is not null or a.branch_id is not null
            or not a.role_id=any(reservation.role_ids)))
      or exists(select 1 from unnest(reservation.role_ids) expected
        where not exists(select 1 from core.role_assignments a
          where a.tenant_id=p_tenant_id and a.membership_id=reservation.membership_id
            and a.role_id=expected and a.legal_entity_id is null and a.branch_id is null)) then
      raise exception using errcode='42501', message='STAFF_ACCESS_CHANGED';
    end if;
    member_id := reservation.membership_id;
  else
    if exists(select 1 from core.memberships where user_id=p_user_id) then
      raise exception using errcode='42501', message='STAFF_EXISTING_MEMBERSHIP';
    end if;
    perform workspace_admin.require_seat(p_tenant_id,p_user_id);
    insert into core.memberships(tenant_id,user_id,status,invited_by,joined_at)
      values(p_tenant_id,p_user_id,'active',actor,now()) returning id into member_id;
    foreach role_id in array reservation.role_ids loop
      insert into core.role_assignments(tenant_id,membership_id,role_id,created_by)
        values(p_tenant_id,member_id,role_id,actor);
    end loop;
    update workspace_admin.staff_accounts set user_id=p_user_id,membership_id=member_id
      where request_id=p_request_id;
    insert into audit.events(tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id,after_context)
      values(p_tenant_id,actor,p_request_id,'membership.staff_account_created','membership',member_id,
        jsonb_build_object('username',reservation.username,'user_id',p_user_id,'role_ids',reservation.role_ids));
  end if;
  result := jsonb_build_object('request_id',p_request_id,'tenant_id',p_tenant_id,
    'username',reservation.username,'display_name',reservation.display_name,
    'user_id',p_user_id,'membership_id',member_id,'status','active');
  return result;
end;
$$;

-- Only the Edge service resolves usernames. No anonymous table reads or public
-- username -> Auth identity endpoint. Rate limits count unknown names too.
create function api.workspace_staff_login_target(p_username text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare normalized text := lower(trim(p_username)); name_count integer;
  window_id bigint := floor(extract(epoch from clock_timestamp())/900)::bigint;
  target text;
begin
  if normalized is null or normalized !~ '^[a-z0-9][a-z0-9_-]{2,39}$' then
    return jsonb_build_object('email',null,'limited',false);
  end if;
  -- Do not retain attacker-chosen usernames or grow one row per guessed name.
  -- 65536 fixed hash slots impose bounded storage and count unknown accounts.
  -- There is no shared counter that can lock every organization's sign-in.
  insert into workspace_admin.staff_login_attempts(key,bucket,attempts)
    values('name.'||((hashtextextended(normalized,0) & 65535)::text),window_id,1)
    on conflict(key) do update set bucket=excluded.bucket,
      attempts=case when staff_login_attempts.bucket=excluded.bucket then staff_login_attempts.attempts+1 else 1 end
    returning attempts into name_count;
  if name_count>12 then
    return jsonb_build_object('email',null,'limited',true);
  end if;
  select lower(u.email) into target from workspace_admin.staff_accounts a
    join auth.users u on u.id=a.user_id
    join core.memberships m on m.id=a.membership_id and m.tenant_id=a.tenant_id and m.user_id=a.user_id
    join core.tenants t on t.id=a.tenant_id
    where a.username=normalized and m.status='active' and t.status in('active','trial');
  return jsonb_build_object('email',target,'limited',false);
end;
$$;

revoke all on function api.workspace_staff_reserve(uuid,uuid,text,text,uuid[]),
  api.workspace_staff_complete(uuid,uuid,uuid),api.workspace_staff_login_target(text)
  from public,anon,authenticated,service_role;
grant execute on function api.workspace_staff_reserve(uuid,uuid,text,text,uuid[]),
  api.workspace_staff_complete(uuid,uuid,uuid) to authenticated;
grant execute on function api.workspace_staff_login_target(text) to service_role;
grant usage on schema api to service_role;

-- Preserve the existing register contract while showing staff usernames rather
-- than internal Auth addresses, including already-installed company backends.
create or replace function api.workspace_admin_list(p_tenant_id uuid,p_resource text,p_after text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb; more boolean;begin
 perform workspace_admin.require_admin(p_tenant_id,case
  when p_resource in('entities','branches') and core.has_permission(p_tenant_id,'core.tenant.manage') then 'core.tenant.manage'
  when p_resource in('entities','branches','roles') and not core.has_permission(p_tenant_id,'core.roles.manage') then 'core.members.invite'
  when p_resource='invitations' then 'core.members.invite' else 'core.roles.manage' end);
 if p_resource is null or p_resource not in('entities','branches','members','roles','permissions','invitations')
  or p_limit is null or p_limit not between 1 and 200 or length(coalesce(p_after,''))>100 then
  raise exception using errcode='22023',message='ADMIN_PAGE_INVALID';end if;
 with records as (
  select e.id::text key,jsonb_build_object('id',e.id,'tenant_id',e.tenant_id,'name',e.name,'code',e.code,
   'currency_code',e.currency_code,'timezone',e.timezone,'registration_number',e.registration_number,
   'tax_identifier',e.tax_identifier,'status',e.status,'version',e.version) item
   from core.legal_entities e where p_resource='entities' and e.tenant_id=p_tenant_id
  union all select b.id::text,jsonb_build_object('id',b.id,'tenant_id',b.tenant_id,'legal_entity_id',b.legal_entity_id,
   'name',b.name,'code',b.code,'timezone',b.timezone,'status',b.status,'version',b.version)
   from core.branches b where p_resource='branches' and b.tenant_id=p_tenant_id
  union all select m.id::text,jsonb_build_object('id',m.id,'tenant_id',m.tenant_id,'user_id',m.user_id,
   'name',left(coalesce(nullif(u.raw_user_meta_data->>'full_name',''),u.email,m.id::text),100),
   'username',u.raw_app_meta_data->>'jentra_username',
   'email',case when u.raw_app_meta_data->>'jentra_username' is null then u.email else null end,
   'status',m.status,'version',m.version,
   'owner',exists(select 1 from core.role_assignments a join core.roles r on r.tenant_id=a.tenant_id and r.id=a.role_id
    where a.tenant_id=m.tenant_id and a.membership_id=m.id and r.code='tenant_owner'),
   'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'role_id',a.role_id,
    'legal_entity_id',a.legal_entity_id,'branch_id',a.branch_id) order by a.id)
    from core.role_assignments a where a.tenant_id=m.tenant_id and a.membership_id=m.id),'[]'::jsonb))
   from core.memberships m join auth.users u on u.id=m.user_id where p_resource='members' and m.tenant_id=p_tenant_id
  union all select r.id::text,jsonb_build_object('id',r.id,'tenant_id',r.tenant_id,'code',r.code,'name',r.name,
   'requires_mfa',r.requires_mfa,'is_system',r.is_system,'version',r.version,
   'permissions',coalesce((select jsonb_agg(rp.permission_code order by rp.permission_code)
    from core.role_permissions rp where rp.tenant_id=r.tenant_id and rp.role_id=r.id),'[]'::jsonb))
   from core.roles r where p_resource='roles' and r.tenant_id=p_tenant_id
  union all select p.code,jsonb_build_object('id',p.code,'name',p.description,'code',p.code,'privileged',p.privileged)
   from core.permissions p where p_resource='permissions' and core.has_permission(p_tenant_id,p.code)
  union all select i.id::text,jsonb_build_object('id',i.id,'tenant_id',i.tenant_id,'email',i.email,'role_id',i.role_id,
   'legal_entity_id',i.legal_entity_id,'branch_id',i.branch_id,'status',
   case when i.status='pending' and i.expires_at<=now() then 'expired' else i.status end,
   'expires_at',i.expires_at,'version',case when i.status='pending' then 1 else 2 end)
   from core.invitations i where p_resource='invitations' and i.tenant_id=p_tenant_id
 ), page as(select key,item from records where p_after is null or key collate "C">p_after collate "C"
  order by key collate "C" limit p_limit+1)
 select coalesce(jsonb_agg(item order by key collate "C"),'[]'::jsonb),count(*)>p_limit into rows,more from page;
 if more then rows:=rows- p_limit;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'resource',p_resource,'items',rows,
  'next_cursor',case when more then rows->(jsonb_array_length(rows)-1)->>'id' else null end);
end $$;
