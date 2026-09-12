-- Narrow governed access setup; no persistent users, roles or invitations seeded.
create function core.stock_opening_approver_role_valid(p_tenant_id uuid, p_role_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from core.roles r where r.tenant_id=p_tenant_id
    and r.id=p_role_id and r.code='stock_opening_approver' and r.requires_mfa
    and not r.is_system
    and (select array_agg(rp.permission_code order by rp.permission_code)
         from core.role_permissions rp where rp.role_id=r.id and rp.tenant_id=r.tenant_id)
      = array['inventory.cost.view','workflow.approvals.decide']::text[]);
$$;

create function core.invite_stock_opening_approver_impl(
  p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid,
  p_email text, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid := (select auth.uid());
  v_email text := lower(trim(p_email));
  v_role uuid;
  v_hash text;
  v_replay jsonb;
  v_created jsonb;
  v_invitation core.invitations%rowtype;
begin
  perform core.require_permission(p_tenant_id,'core.roles.manage');
  perform core.require_permission(p_tenant_id,'core.members.invite');
  if coalesce((select auth.jwt()->>'aal'),'aal1') <> 'aal2' then
    raise exception using errcode='42501',message='Multi-factor authentication required.';
  end if;
  if coalesce(v_email,'') !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
     or length(v_email)>254 then
    raise exception using errcode='22023',message='Enter a valid email address.';
  end if;
  if exists(select 1 from auth.users where id=v_actor and lower(email)=v_email) then
    raise exception using errcode='22023',message='Choose an independent approver.';
  end if;
  v_hash := core.wave2_request_hash('invite_stock_opening_approver',p_tenant_id,p_legal_entity_id,
    jsonb_build_object('branch_id',p_branch_id,'email',v_email),null);
  v_replay := core.wave2_replay(p_tenant_id,'invite_stock_opening_approver',p_idempotency_key,v_hash);
  if v_replay is not null then return v_replay; end if;
  perform 1 from core.branches b join core.legal_entities le
    on le.tenant_id=b.tenant_id and le.id=b.legal_entity_id
    join core.tenants t on t.id=le.tenant_id
    where b.id=p_branch_id and b.tenant_id=p_tenant_id and b.legal_entity_id=p_legal_entity_id
      and b.status='active' and le.status='active' and t.status='active' for share of b,le,t;
  if not found then
    raise exception using errcode='22023',message='Choose an active branch in this legal entity.';
  end if;
  if exists(select 1 from core.memberships m join auth.users u on u.id=m.user_id
    where m.tenant_id=p_tenant_id and lower(u.email)=v_email) then
    raise exception using errcode='22023',message='This account already has workspace membership; review its access separately.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text||':stock_opening_approver',0));
  select id into v_role from core.roles where tenant_id=p_tenant_id and code='stock_opening_approver' for update;
  if not found then
    insert into core.roles(tenant_id,code,name,description,requires_mfa)
      values(p_tenant_id,'stock_opening_approver','Stock opening approver',
        'Scoped stock-opening cost review and independent approval.',true) returning id into v_role;
    insert into core.role_permissions(tenant_id,role_id,permission_code)
      select p_tenant_id,v_role,x from unnest(array['inventory.cost.view','workflow.approvals.decide']) x;
  end if;
  if not core.stock_opening_approver_role_valid(p_tenant_id,v_role) then
    raise exception using errcode='22023',message='Stock opening approver role differs from the governed permission set.';
  end if;
  v_created := core.create_invitation_impl(p_tenant_id,v_email,v_role,p_legal_entity_id,p_branch_id,72);
  select * into strict v_invitation from core.invitations where id=(v_created->>'invitation_id')::uuid;
  return core.wave2_finish_command(p_tenant_id,'invite_stock_opening_approver','invitation',v_invitation.id,
    p_idempotency_key,v_hash,null,jsonb_build_object('id',v_invitation.id,'email',v_email,
      'role_id',v_role,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
      'status',v_invitation.status,'expires_at',v_invitation.expires_at),p_legal_entity_id,p_branch_id);
end;
$$;

create function core.accept_stock_opening_invitation_impl(p_invitation_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid := (select auth.uid());
  v_email text := lower(coalesce((select auth.jwt()->>'email'),''));
  v_i core.invitations%rowtype;
  v_member uuid;
  v_hash text;
  v_replay jsonb;
begin
  if v_actor is null or not exists(select 1 from auth.users u where u.id=v_actor
    and lower(u.email)=v_email and u.email_confirmed_at is not null) then
    raise exception using errcode='42501',message='Sign in with the confirmed invitation email.';
  end if;
  select * into v_i from core.invitations where id=p_invitation_id and lower(email)=v_email for update;
  if not found then
    raise exception using errcode='42501',message='Invitation is not available to this account.';
  end if;
  v_hash := core.wave2_request_hash('accept_stock_opening_invitation',v_i.tenant_id,v_i.legal_entity_id,
    jsonb_build_object('invitation_id',p_invitation_id),null);
  v_replay := core.wave2_replay(v_i.tenant_id,'accept_stock_opening_invitation',p_idempotency_key,v_hash);
  if v_replay is not null then return v_replay; end if;
  if v_i.status <> 'pending' or v_i.expires_at<=now() then
    raise exception using errcode='22023',message='Invitation is no longer pending or has expired.';
  end if;
  perform 1 from core.roles where tenant_id=v_i.tenant_id and id=v_i.role_id for share;
  if v_i.invited_by=v_actor or not core.stock_opening_approver_role_valid(v_i.tenant_id,v_i.role_id) then
    raise exception using errcode='42501',message='Invitation does not grant governed independent approval access.';
  end if;
  perform 1 from core.branches b join core.legal_entities le on le.tenant_id=b.tenant_id and le.id=b.legal_entity_id
    join core.tenants t on t.id=le.tenant_id
    where b.id=v_i.branch_id and b.tenant_id=v_i.tenant_id and b.legal_entity_id=v_i.legal_entity_id
    and b.status='active' and le.status='active' and t.status='active' for share of b,le,t;
  if not found then raise exception using errcode='22023',message='Invitation business scope is no longer active.'; end if;
  -- Deliberately do not upsert: existing, suspended or revoked access is never reactivated.
  insert into core.memberships(tenant_id,user_id,status,invited_by,joined_at)
    values(v_i.tenant_id,v_actor,'active',v_i.invited_by,now()) returning id into v_member;
  insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
    values(v_i.tenant_id,v_member,v_i.role_id,v_i.legal_entity_id,v_i.branch_id,v_i.invited_by);
  update core.invitations set status='accepted',accepted_by=v_actor,accepted_at=now() where id=v_i.id;
  return core.wave2_finish_command(v_i.tenant_id,'accept_stock_opening_invitation','membership',v_member,
    p_idempotency_key,v_hash,null,jsonb_build_object('id',v_member,'invitation_id',v_i.id,
      'tenant_id',v_i.tenant_id,'role_id',v_i.role_id,'legal_entity_id',v_i.legal_entity_id,
      'branch_id',v_i.branch_id,'status','active'),v_i.legal_entity_id,v_i.branch_id);
end;
$$;

create function api.list_my_stock_opening_invitations()
returns table(id uuid,tenant_name text,legal_entity_name text,branch_name text,expires_at timestamptz)
language sql stable security definer set search_path='' as $$
  select i.id,t.name,le.name,b.name,i.expires_at from core.invitations i
  join core.tenants t on t.id=i.tenant_id
  join core.legal_entities le on le.tenant_id=i.tenant_id and le.id=i.legal_entity_id
  join core.branches b on b.tenant_id=i.tenant_id and b.id=i.branch_id and b.legal_entity_id=le.id
  where lower(i.email)=lower((select auth.jwt()->>'email')) and i.status='pending' and i.expires_at>now()
    and t.status='active' and le.status='active' and b.status='active'
    and exists(select 1 from auth.users u where u.id=(select auth.uid())
      and lower(u.email)=lower(i.email) and u.email_confirmed_at is not null)
    and core.stock_opening_approver_role_valid(i.tenant_id,i.role_id)
  order by i.created_at desc,i.id limit 50;
$$;
create function api.invite_stock_opening_approver(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_email text,p_idempotency_key uuid)
returns jsonb language sql security definer set search_path='' as $$
  select core.invite_stock_opening_approver_impl(p_tenant_id,p_legal_entity_id,p_branch_id,p_email,p_idempotency_key);
$$;
create function api.accept_stock_opening_invitation(p_invitation_id uuid,p_idempotency_key uuid)
returns jsonb language sql security definer set search_path='' as $$
  select core.accept_stock_opening_invitation_impl(p_invitation_id,p_idempotency_key);
$$;
revoke all on function core.stock_opening_approver_role_valid(uuid,uuid),
  core.invite_stock_opening_approver_impl(uuid,uuid,uuid,text,uuid),
  core.accept_stock_opening_invitation_impl(uuid,uuid) from public,anon,authenticated;
revoke all on function api.invite_stock_opening_approver(uuid,uuid,uuid,text,uuid),
  api.accept_stock_opening_invitation(uuid,uuid),api.list_my_stock_opening_invitations() from public,anon;
grant execute on function api.invite_stock_opening_approver(uuid,uuid,uuid,text,uuid),
  api.accept_stock_opening_invitation(uuid,uuid),api.list_my_stock_opening_invitations() to authenticated;
