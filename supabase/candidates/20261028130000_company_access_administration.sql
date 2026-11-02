-- Additive, uninstalled candidate for blueprint 69. No backfill or activation.
-- Existing core identity, permission, receipt, audit and outbox authority is reused.
create schema workspace_admin;
revoke all on schema workspace_admin from public,anon,authenticated,service_role;

create function workspace_admin.require_admin(t uuid, permission text) returns void
language plpgsql security definer set search_path='' as $$begin
 perform core.require_permission(t,permission);
 if not exists(select 1 from core.tenants where id=t and status in('active','trial')) then
  raise exception using errcode='42501',message='ADMIN_ACCESS_DENIED';end if;
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' or not exists(
  select 1 from jsonb_array_elements(case when jsonb_typeof(auth.jwt()->'amr')='array'
   then auth.jwt()->'amr' else '[]'::jsonb end) a
  where a->>'method' in('totp','webauthn','phone') and a->>'timestamp' ~ '^[0-9]{1,12}$'
   and (a->>'timestamp')::bigint between extract(epoch from now())::bigint-900
    and extract(epoch from now())::bigint+30) then
  raise exception using errcode='42501',message='ADMIN_RECENT_MFA_REQUIRED';end if;
end $$;

create function workspace_admin.fields(p jsonb, allowed text[], required text[]) returns void
language plpgsql immutable set search_path='' as $$begin
 if jsonb_typeof(p) is distinct from 'object' or octet_length(p::text)>16384
  or exists(select 1 from jsonb_object_keys(p) k where not k=any(allowed))
  or not p ?& required then raise exception using errcode='22023',message='ADMIN_PAYLOAD_INVALID';end if;
end $$;
create function workspace_admin.text_field(p jsonb,k text,minimum integer,maximum integer,optional boolean default false) returns text
language plpgsql immutable set search_path='' as $$declare v text;begin
 if optional and (not p?k or p->k='null'::jsonb) then return null;end if;
 v:=trim(p->>k);
 if jsonb_typeof(p->k) is distinct from 'string' or length(v) not between minimum and maximum
  or p->>k ~ '[[:cntrl:]]' then raise exception using errcode='22023',message='ADMIN_FIELD_INVALID',detail=k;end if;
 return nullif(v,'');
end $$;
create function workspace_admin.uuid_field(p jsonb,k text,optional boolean default false) returns uuid
language plpgsql immutable set search_path='' as $$declare v text;begin
 if optional and (not p?k or p->k='null'::jsonb) then return null;end if;
 v:=workspace_admin.text_field(p,k,36,36);
 if v !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' then
  raise exception using errcode='22023',message='ADMIN_ID_INVALID';end if;return v::uuid;
end $$;
create function workspace_admin.require_scope(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if (e is not null and not exists(select 1 from core.legal_entities where tenant_id=t and id=e and status='active'))
  or (b is not null and (e is null or not exists(select 1 from core.branches
   where tenant_id=t and legal_entity_id=e and id=b and status='active'))) then
  raise exception using errcode='22023',message='ADMIN_SCOPE_INVALID';end if;
end $$;
create function workspace_admin.require_role(t uuid,r uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from core.roles where tenant_id=t and id=r and code<>'tenant_owner')
  or exists(select 1 from core.role_permissions rp where rp.tenant_id=t and rp.role_id=r
   and not core.has_permission(t,rp.permission_code,e,b)) then
  raise exception using errcode='42501',message='ADMIN_ROLE_NOT_DELEGABLE';end if;
 if exists(select 1 from core.role_permissions rp join core.permissions p on p.code=rp.permission_code
  join core.roles ro on ro.tenant_id=rp.tenant_id and ro.id=rp.role_id
  where rp.tenant_id=t and rp.role_id=r and p.privileged and not ro.requires_mfa) then
  raise exception using errcode='42501',message='ADMIN_PRIVILEGED_ROLE_REQUIRES_MFA';end if;
end $$;
create function workspace_admin.require_seat(t uuid,target_user uuid) returns void
language plpgsql security definer set search_path='' as $$declare s billing.tenant_subscriptions%rowtype;begin
 select * into s from billing.tenant_subscriptions where tenant_id=t for update;
 if not found or s.status not in('active','trialing') or
  (s.status='trialing' and (s.trial_ends_at is null or s.trial_ends_at<=now())) then
  raise exception using errcode='42501',message='ADMIN_SUBSCRIPTION_UNAVAILABLE';end if;
 if not exists(select 1 from core.memberships where tenant_id=t and user_id=target_user and status in('active','invited'))
  and (select count(*) from core.memberships where tenant_id=t and status in('active','invited'))>=s.seats then
  raise exception using errcode='23514',message='ADMIN_SEAT_LIMIT';end if;
end $$;

-- A live inviter check is shared by verified-email and legacy token acceptance.
-- It reads current table-backed authority without impersonating the inviter.
create function workspace_admin.require_inviter(t uuid,inviter uuid,r uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 perform workspace_admin.require_scope(t,e,b);
 if not exists(select 1 from core.tenants where id=t and status in('active','trial'))
  or not exists(select 1 from core.memberships m join core.role_assignments a on a.tenant_id=m.tenant_id and a.membership_id=m.id
   join core.role_permissions rp on rp.tenant_id=a.tenant_id and rp.role_id=a.role_id
   where m.tenant_id=t and m.user_id=inviter and m.status='active'
    and a.legal_entity_id is null and a.branch_id is null and rp.permission_code='core.members.invite')
  or not exists(select 1 from core.roles ro where ro.tenant_id=t and ro.id=r and ro.code<>'tenant_owner')
  or exists(select 1 from core.role_permissions target where target.tenant_id=t and target.role_id=r
   and not exists(select 1 from core.memberships m join core.role_assignments a on a.tenant_id=m.tenant_id and a.membership_id=m.id
    join core.role_permissions rp on rp.tenant_id=a.tenant_id and rp.role_id=a.role_id
    where m.tenant_id=t and m.user_id=inviter and m.status='active' and rp.permission_code=target.permission_code
     and (a.legal_entity_id is null or a.legal_entity_id=e) and (a.branch_id is null or a.branch_id=b)))
  or exists(select 1 from core.roles ro where ro.tenant_id=t and ro.id=r and not ro.requires_mfa
   and exists(select 1 from core.role_permissions rp join core.permissions p on p.code=rp.permission_code
    where rp.tenant_id=t and rp.role_id=r and p.privileged)) then
  raise exception using errcode='42501',message='ADMIN_INVITER_ACCESS_REVOKED';end if;
end $$;

create function api.workspace_admin_list(p_tenant_id uuid,p_resource text,p_after text default null,p_limit integer default 50)
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
   'email',u.email,'status',m.status,'version',m.version,
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

create function api.workspace_admin_command(p_tenant_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_action text,p_payload jsonb,p_expected_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
<<admin_command>>
declare actor uuid:=auth.uid(); id uuid; entity_id uuid; branch_id uuid; role_id uuid;
 name text; code text; zone text; currency text; permissions text[]; mfa boolean; granted boolean;
 before_value jsonb; result jsonb; replay jsonb; request_hash text; command_name text;
 member core.memberships%rowtype; role_record core.roles%rowtype; subscription billing.tenant_subscriptions%rowtype;
 invitation core.invitations%rowtype; counter integer;begin
 perform workspace_admin.require_admin(p_tenant_id,case when p_action in('create_entity','update_entity','create_branch','update_branch')
  then 'core.tenant.manage' when p_action in('create_invitation','revoke_invitation') then 'core.members.invite' else 'core.roles.manage' end);
 if p_command_id is null or p_client_timestamp is null or p_client_timestamp>now()+interval '5 minutes'
  or p_action is null or p_action not in('create_entity','update_entity','create_branch','update_branch',
   'create_role','update_role','set_assignment','set_member_status','create_invitation','revoke_invitation') then
  raise exception using errcode='22023',message='ADMIN_COMMAND_INVALID';end if;
 perform workspace_admin.fields(p_payload,array(select jsonb_object_keys(p_payload)),array[]::text[]);
 -- One tenant lock serializes role edits, assignments, invitations and status changes.
 perform 1 from core.tenants t where t.id=p_tenant_id for update;
 command_name:='workspace_admin.'||p_action;
 request_hash:=core.wave2_request_hash(command_name,p_tenant_id,null,
  jsonb_build_object('command_id',p_command_id,'client_timestamp',p_client_timestamp,'payload',p_payload),p_expected_version);
 replay:=core.wave2_replay(p_tenant_id,command_name,p_idempotency_key,request_hash);
 if replay is not null then return replay;end if;
 if p_action like 'create_%' and p_expected_version is not null then
  raise exception using errcode='22023',message='ADMIN_VERSION_INVALID';end if;

 if p_action in('create_entity','update_entity') then
  perform workspace_admin.fields(p_payload,case when p_action='create_entity' then
   array['name','code','currency_code','timezone','registration_number','tax_identifier'] else
   array['id','name','registration_number','tax_identifier'] end,
   case when p_action='create_entity' then array['name','code','currency_code','timezone'] else array['id','name'] end);
  name:=workspace_admin.text_field(p_payload,'name',2,180);
  if p_action='create_entity' then
   code:=workspace_admin.text_field(p_payload,'code',2,20);
   currency:=workspace_admin.text_field(p_payload,'currency_code',3,3);
   zone:=workspace_admin.text_field(p_payload,'timezone',1,100);
   if code !~ '^[A-Z0-9][A-Z0-9_-]{1,19}$' or currency !~ '^[A-Z]{3}$'
    or not exists(select 1 from core.currencies c where c.code=currency and c.active)
    or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=zone) then
    raise exception using errcode='22023',message='ADMIN_COMPANY_INVALID';end if;
   select * into subscription from billing.tenant_subscriptions where tenant_id=p_tenant_id for update;
   if not found or subscription.status not in('active','trialing') or
    (subscription.status='trialing' and (subscription.trial_ends_at is null or subscription.trial_ends_at<=now())) then
    raise exception using errcode='42501',message='ADMIN_SUBSCRIPTION_UNAVAILABLE';end if;
   if not exists(select 1 from billing.plan_entitlements p where p.plan_code=subscription.plan_code
    and p.entitlement_code='legal_entities' and p.enabled and
    (p.numeric_limit is null or p.numeric_limit>=(select count(*)+1 from core.legal_entities where tenant_id=p_tenant_id and status='active'))) then
    raise exception using errcode='23514',message='ADMIN_COMPANY_LIMIT';end if;
   insert into core.legal_entities(tenant_id,name,code,currency_code,timezone,registration_number,tax_identifier,created_by)
    values(p_tenant_id,name,code,currency,zone,workspace_admin.text_field(p_payload,'registration_number',0,100,true),
     workspace_admin.text_field(p_payload,'tax_identifier',0,100,true),actor) returning to_jsonb(legal_entities.*) into result;
  else
   id:=workspace_admin.uuid_field(p_payload,'id');
   select to_jsonb(e.*) into before_value from core.legal_entities e where e.tenant_id=p_tenant_id and e.id=id for update;
   if before_value is null then raise exception using errcode='P0002',message='ADMIN_RECORD_NOT_FOUND';end if;
   perform core.wave2_assert_expected_version((before_value->>'version')::bigint,p_expected_version);
   update core.legal_entities e set name=admin_command.name,
    registration_number=case when p_payload?'registration_number' then workspace_admin.text_field(p_payload,'registration_number',0,100,true) else e.registration_number end,
    tax_identifier=case when p_payload?'tax_identifier' then workspace_admin.text_field(p_payload,'tax_identifier',0,100,true) else e.tax_identifier end
    where e.tenant_id=p_tenant_id and e.id=id returning to_jsonb(e.*) into result;
  end if;
 elsif p_action in('create_branch','update_branch') then
  perform workspace_admin.fields(p_payload,case when p_action='create_branch' then array['name','code','legal_entity_id','timezone']
   else array['id','name'] end,case when p_action='create_branch' then array['name','code','legal_entity_id','timezone'] else array['id','name'] end);
  name:=workspace_admin.text_field(p_payload,'name',2,160);
  if p_action='create_branch' then
   entity_id:=workspace_admin.uuid_field(p_payload,'legal_entity_id');
   perform workspace_admin.require_scope(p_tenant_id,entity_id,null);
   code:=workspace_admin.text_field(p_payload,'code',2,20);zone:=workspace_admin.text_field(p_payload,'timezone',1,100);
   if code !~ '^[A-Z0-9][A-Z0-9_-]{1,19}$' or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=zone) then
    raise exception using errcode='22023',message='ADMIN_BRANCH_INVALID';end if;
   insert into core.branches(tenant_id,legal_entity_id,name,code,timezone,created_by)
    values(p_tenant_id,entity_id,name,code,zone,actor) returning to_jsonb(branches.*) into result;
  else
   id:=workspace_admin.uuid_field(p_payload,'id');
   select to_jsonb(b.*) into before_value from core.branches b where b.tenant_id=p_tenant_id and b.id=id for update;
   if before_value is null then raise exception using errcode='P0002',message='ADMIN_RECORD_NOT_FOUND';end if;
   perform core.wave2_assert_expected_version((before_value->>'version')::bigint,p_expected_version);
   update core.branches b set name=admin_command.name where b.tenant_id=p_tenant_id and b.id=id
    returning to_jsonb(b.*) into result;
  end if;
 elsif p_action in('create_role','update_role') then
  perform workspace_admin.fields(p_payload,case when p_action='create_role' then array['name','code','permissions','requires_mfa']
   else array['id','name','permissions','requires_mfa'] end,
   case when p_action='create_role' then array['name','code','permissions','requires_mfa'] else array['id','name','permissions','requires_mfa'] end);
  name:=workspace_admin.text_field(p_payload,'name',2,100);
  if jsonb_typeof(p_payload->'permissions') is distinct from 'array' or
   jsonb_array_length(p_payload->'permissions') not between 1 and 200 or
   exists(select 1 from jsonb_array_elements(p_payload->'permissions') p where jsonb_typeof(p)<>'string')
   or jsonb_typeof(p_payload->'requires_mfa') is distinct from 'boolean' then
   raise exception using errcode='22023',message='ADMIN_ROLE_INVALID';end if;
  select array_agg(distinct p order by p) into permissions from jsonb_array_elements_text(p_payload->'permissions') p;
  if exists(select 1 from unnest(permissions) p where not core.has_permission(p_tenant_id,p)) then
   raise exception using errcode='42501',message='ADMIN_PERMISSION_NOT_DELEGABLE';end if;
  mfa:=(p_payload->>'requires_mfa')::boolean;
  if not mfa and exists(select 1 from core.permissions p where p.code=any(permissions) and p.privileged) then
   raise exception using errcode='22023',message='ADMIN_PRIVILEGED_ROLE_REQUIRES_MFA';end if;
  if p_action='create_role' then
   code:=workspace_admin.text_field(p_payload,'code',2,64);
   if code !~ '^[a-z][a-z0-9_.-]{1,63}$' or code='tenant_owner' then
    raise exception using errcode='22023',message='ADMIN_ROLE_INVALID';end if;
   insert into core.roles(tenant_id,code,name,requires_mfa,is_system)
    values(p_tenant_id,code,name,mfa,false) returning roles.id into role_id;
  else
   role_id:=workspace_admin.uuid_field(p_payload,'id');
   select * into role_record from core.roles r where r.tenant_id=p_tenant_id and r.id=role_id for update;
   if not found then raise exception using errcode='P0002',message='ADMIN_RECORD_NOT_FOUND';end if;
   if role_record.is_system or role_record.code='tenant_owner' or exists(select 1 from core.role_assignments a
    join core.memberships m on m.tenant_id=a.tenant_id and m.id=a.membership_id
    where a.tenant_id=p_tenant_id and a.role_id=role_id and m.user_id=actor) then
    raise exception using errcode='42501',message='ADMIN_PROTECTED_ROLE';end if;
   perform core.wave2_assert_expected_version(role_record.version,p_expected_version);
   before_value:=to_jsonb(role_record)||jsonb_build_object('permissions',coalesce((select jsonb_agg(rp.permission_code order by rp.permission_code)
    from core.role_permissions rp where rp.tenant_id=p_tenant_id and rp.role_id=role_id),'[]'::jsonb));
   update core.roles r set name=admin_command.name,requires_mfa=mfa where r.tenant_id=p_tenant_id and r.id=role_id;
   delete from core.role_permissions rp where rp.tenant_id=p_tenant_id and rp.role_id=role_id;
  end if;
  insert into core.role_permissions(tenant_id,role_id,permission_code) select p_tenant_id,role_id,p from unnest(permissions) p;
  select to_jsonb(r.*)||jsonb_build_object('permissions',to_jsonb(permissions)) into result
   from core.roles r where r.tenant_id=p_tenant_id and r.id=role_id;
 elsif p_action in('set_assignment','set_member_status') then
  perform workspace_admin.fields(p_payload,case when p_action='set_assignment' then
   array['id','role_id','legal_entity_id','branch_id','granted'] else array['id','status'] end,
   case when p_action='set_assignment' then array['id','role_id','granted'] else array['id','status'] end);
  id:=workspace_admin.uuid_field(p_payload,'id');
  select * into member from core.memberships m where m.tenant_id=p_tenant_id and m.id=id for update;
  if not found then raise exception using errcode='P0002',message='ADMIN_RECORD_NOT_FOUND';end if;
  if member.user_id=actor or exists(select 1 from core.role_assignments a join core.roles r on r.tenant_id=a.tenant_id and r.id=a.role_id
   where a.tenant_id=p_tenant_id and a.membership_id=id and r.code='tenant_owner') then
   raise exception using errcode='42501',message='ADMIN_PROTECTED_MEMBERSHIP';end if;
  perform core.wave2_assert_expected_version(member.version,p_expected_version);before_value:=to_jsonb(member);
  if p_action='set_assignment' then
   role_id:=workspace_admin.uuid_field(p_payload,'role_id');entity_id:=workspace_admin.uuid_field(p_payload,'legal_entity_id',true);
   branch_id:=workspace_admin.uuid_field(p_payload,'branch_id',true);
   perform workspace_admin.require_scope(p_tenant_id,entity_id,branch_id);
   if member.status<>'active' or jsonb_typeof(p_payload->'granted') is distinct from 'boolean' then
    raise exception using errcode='22023',message='ADMIN_ASSIGNMENT_INVALID';end if;
   perform workspace_admin.require_role(p_tenant_id,role_id,entity_id,branch_id);granted:=(p_payload->>'granted')::boolean;
   if granted then
    if not exists(select 1 from core.role_assignments a where a.tenant_id=p_tenant_id and a.membership_id=id
     and a.role_id=role_id and a.legal_entity_id is not distinct from entity_id and a.branch_id is not distinct from branch_id) then
     insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
      values(p_tenant_id,id,role_id,entity_id,branch_id,actor);end if;
   else
    delete from core.role_assignments a where a.tenant_id=p_tenant_id and a.membership_id=id and a.role_id=role_id
     and a.legal_entity_id is not distinct from entity_id and a.branch_id is not distinct from branch_id;
    if not found then raise exception using errcode='P0002',message='ADMIN_ASSIGNMENT_NOT_FOUND';end if;
   end if;
   update core.memberships m set status=m.status where m.tenant_id=p_tenant_id and m.id=id;
  else
   name:=workspace_admin.text_field(p_payload,'status',6,9);
   if name not in('active','suspended','revoked') then raise exception using errcode='22023',message='ADMIN_STATUS_INVALID';end if;
   if name='active' then
    perform workspace_admin.require_seat(p_tenant_id,member.user_id);
    for role_id,entity_id,branch_id in select a.role_id,a.legal_entity_id,a.branch_id from core.role_assignments a
     where a.tenant_id=p_tenant_id and a.membership_id=id loop
     perform workspace_admin.require_scope(p_tenant_id,entity_id,branch_id);
     perform workspace_admin.require_role(p_tenant_id,role_id,entity_id,branch_id);end loop;
   else
    update core.invitations i set status='revoked' where i.tenant_id=p_tenant_id and i.status='pending'
     and lower(i.email)=(select lower(u.email) from auth.users u where u.id=member.user_id);
   end if;
   update core.memberships m set status=name where m.tenant_id=p_tenant_id and m.id=id;
  end if;
  select to_jsonb(m.*)||jsonb_build_object('action',p_action,'change',p_payload) into result
   from core.memberships m where m.tenant_id=p_tenant_id and m.id=id;
 elsif p_action='create_invitation' then
  perform workspace_admin.fields(p_payload,array['email','role_id','legal_entity_id','branch_id'],array['email','role_id']);
  name:=lower(workspace_admin.text_field(p_payload,'email',3,254));
  if name !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
   raise exception using errcode='22023',message='ADMIN_EMAIL_INVALID';end if;
  if exists(select 1 from core.memberships m join auth.users u on u.id=m.user_id
   where m.tenant_id=p_tenant_id and lower(u.email)=name and m.status<>'active') then
   raise exception using errcode='42501',message='ADMIN_MEMBERSHIP_RESTORE_REQUIRED';end if;
  role_id:=workspace_admin.uuid_field(p_payload,'role_id');entity_id:=workspace_admin.uuid_field(p_payload,'legal_entity_id',true);
  branch_id:=workspace_admin.uuid_field(p_payload,'branch_id',true);
  perform workspace_admin.require_scope(p_tenant_id,entity_id,branch_id);
  perform workspace_admin.require_role(p_tenant_id,role_id,entity_id,branch_id);
  -- The existing helper owns token generation, original invitation audit and outbox.
  -- Its raw token is deliberately discarded; the invitee accepts by verified email/ID.
  result:=core.create_invitation_impl(p_tenant_id,name,role_id,entity_id,branch_id,72);
  id:=(result->>'invitation_id')::uuid;
  select jsonb_build_object('id',i.id,'tenant_id',i.tenant_id,'email',i.email,'role_id',i.role_id,
   'legal_entity_id',i.legal_entity_id,'branch_id',i.branch_id,'expires_at',i.expires_at,'status',i.status,'version',1) into result
   from core.invitations i where i.tenant_id=p_tenant_id and i.id=id;
 elsif p_action='revoke_invitation' then
  perform workspace_admin.fields(p_payload,array['id'],array['id']);id:=workspace_admin.uuid_field(p_payload,'id');
  select * into invitation from core.invitations i where i.tenant_id=p_tenant_id and i.id=id for update;
  if not found then raise exception using errcode='P0002',message='ADMIN_RECORD_NOT_FOUND';end if;
  if invitation.status<>'pending' or p_expected_version is distinct from 1::bigint then
   raise exception using errcode='40001',message='ADMIN_VERSION_CONFLICT';end if;
  before_value:=jsonb_build_object('id',id,'status',invitation.status);
  update core.invitations i set status='revoked' where i.tenant_id=p_tenant_id and i.id=id;
  result:=jsonb_build_object('id',id,'tenant_id',p_tenant_id,'status','revoked','version',2);
 end if;
 result:=result||jsonb_build_object('action',p_action);
 return core.wave2_finish_command(p_tenant_id,command_name,'workspace_administration',(result->>'id')::uuid,
  p_idempotency_key,request_hash,before_value,result,null,null,'[]'::jsonb,p_command_id);
end $$;

create function api.workspace_my_invitations(p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare v_email text;rows jsonb;more boolean;begin
 select lower(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null or v_email<>lower(coalesce(auth.jwt()->>'email','')) then
  raise exception using errcode='42501',message='ADMIN_VERIFIED_EMAIL_REQUIRED';end if;
 with page as(select i.id,jsonb_build_object('id',i.id,'tenant_id',i.tenant_id,'tenant_name',t.name,
  'role_name',r.name,'legal_entity_id',i.legal_entity_id,'branch_id',i.branch_id,
  'legal_entity_name',(select e.name from core.legal_entities e where e.tenant_id=i.tenant_id and e.id=i.legal_entity_id),
  'branch_name',(select b.name from core.branches b where b.tenant_id=i.tenant_id and b.legal_entity_id=i.legal_entity_id and b.id=i.branch_id),
  'expires_at',i.expires_at) item
  from core.invitations i join core.tenants t on t.id=i.tenant_id join core.roles r on r.tenant_id=i.tenant_id and r.id=i.role_id
  where lower(i.email)=v_email and i.status='pending' and i.expires_at>now() and t.status in('active','trial')
   and (p_after is null or i.id>p_after) order by i.id limit 51)
 select coalesce(jsonb_agg(item order by id),'[]'::jsonb),count(*)>50 into rows,more from page;
 if more then rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',case when more then rows->49->>'id' else null end);
end $$;

create function api.workspace_accept_invitation(p_invitation_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i core.invitations%rowtype;actor uuid:=auth.uid();v_email text;member_id uuid;hash text;replay jsonb;result jsonb;begin
 select lower(u.email) into v_email from auth.users u where u.id=actor and u.email_confirmed_at is not null;
 if v_email is null or v_email<>lower(coalesce(auth.jwt()->>'email','')) then
  raise exception using errcode='42501',message='ADMIN_VERIFIED_EMAIL_REQUIRED';end if;
 select * into i from core.invitations where id=p_invitation_id and lower(core.invitations.email)=v_email;
 if not found then raise exception using errcode='42501',message='ADMIN_INVITATION_UNAVAILABLE';end if;
 perform 1 from core.tenants where id=i.tenant_id for update;
 select * into i from core.invitations where id=p_invitation_id for update;
 if not exists(select 1 from core.tenants t where t.id=i.tenant_id and t.status in('active','trial')) then
  raise exception using errcode='42501',message='ADMIN_INVITATION_UNAVAILABLE';end if;
 hash:=core.wave2_request_hash('workspace_admin.accept_invitation',i.tenant_id,null,jsonb_build_object('id',i.id),null);
 if i.status='accepted' and i.accepted_by=actor and core.is_tenant_member(i.tenant_id) then
  replay:=core.wave2_replay(i.tenant_id,'workspace_admin.accept_invitation',p_idempotency_key,hash);
  if replay is not null then return replay;end if;
 end if;
 if i.status<>'pending' or i.expires_at<=now() or not exists(select 1 from core.tenants
  where id=i.tenant_id and status in('active','trial')) then
  raise exception using errcode='42501',message='ADMIN_INVITATION_UNAVAILABLE';end if;
 perform workspace_admin.require_scope(i.tenant_id,i.legal_entity_id,i.branch_id);
 if exists(select 1 from core.memberships m where m.tenant_id=i.tenant_id and m.user_id=actor and m.status<>'active') then
  raise exception using errcode='42501',message='ADMIN_MEMBERSHIP_RESTORE_REQUIRED';end if;
 perform workspace_admin.require_inviter(i.tenant_id,i.invited_by,i.role_id,i.legal_entity_id,i.branch_id);
 perform workspace_admin.require_seat(i.tenant_id,actor);
 replay:=core.wave2_replay(i.tenant_id,'workspace_admin.accept_invitation',p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 insert into core.memberships(tenant_id,user_id,status,invited_by,joined_at)
  values(i.tenant_id,actor,'active',i.invited_by,now()) on conflict(tenant_id,user_id)
  do update set status='active',joined_at=now() returning id into member_id;
 if not exists(select 1 from core.role_assignments a where a.tenant_id=i.tenant_id and a.membership_id=member_id and a.role_id=i.role_id
  and a.legal_entity_id is not distinct from i.legal_entity_id and a.branch_id is not distinct from i.branch_id) then
  insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
   values(i.tenant_id,member_id,i.role_id,i.legal_entity_id,i.branch_id,i.invited_by);end if;
 update core.invitations set status='accepted',accepted_by=actor,accepted_at=now() where id=i.id;
 select jsonb_build_object('id',m.id,'tenant_id',m.tenant_id,'user_id',m.user_id,'status',m.status,'version',m.version,
  'invitation_id',i.id,'action','accept_invitation') into result from core.memberships m where m.id=member_id;
 return core.wave2_finish_command(i.tenant_id,'workspace_admin.accept_invitation','membership',member_id,p_idempotency_key,
  hash,null,result,i.legal_entity_id,i.branch_id);
end $$;

-- Guard the original token APIs too. These additive triggers preserve their
-- definitions/signatures/grants while preventing a caller from bypassing the
-- new administration checks through an older endpoint. Trusted SQL maintenance
-- remains possible; Data API callers cannot select those database roles.
create function workspace_admin.guard_invitation() returns trigger
language plpgsql security definer set search_path='' as $$declare actor uuid:=auth.uid();v_email text;begin
 if session_user in('postgres','supabase_admin') and current_setting('role') in('none','postgres','supabase_admin') then return new;end if;
 if tg_op='INSERT' then
  perform workspace_admin.require_admin(new.tenant_id,'core.members.invite');
  if new.invited_by is distinct from actor or new.status<>'pending' or new.expires_at<=now()
   or new.expires_at>now()+interval '168 hours' then
   raise exception using errcode='22023',message='ADMIN_INVITATION_UNAVAILABLE';end if;
  perform workspace_admin.require_scope(new.tenant_id,new.legal_entity_id,new.branch_id);
  perform workspace_admin.require_role(new.tenant_id,new.role_id,new.legal_entity_id,new.branch_id);
  if exists(select 1 from core.memberships m join auth.users u on u.id=m.user_id
   where m.tenant_id=new.tenant_id and lower(u.email)=lower(new.email) and m.status<>'active') then
   raise exception using errcode='42501',message='ADMIN_MEMBERSHIP_RESTORE_REQUIRED';end if;
 elsif new.status='accepted' and old.status is distinct from 'accepted' then
  if new.tenant_id is distinct from old.tenant_id or new.email is distinct from old.email
   or new.role_id is distinct from old.role_id or new.legal_entity_id is distinct from old.legal_entity_id
   or new.branch_id is distinct from old.branch_id or new.invited_by is distinct from old.invited_by
   or new.token_hash is distinct from old.token_hash or new.expires_at is distinct from old.expires_at
   or old.status<>'pending' or old.expires_at<=now() or new.accepted_by is distinct from actor then
   raise exception using errcode='42501',message='ADMIN_INVITATION_UNAVAILABLE';end if;
  select lower(u.email) into v_email from auth.users u where u.id=actor and u.email_confirmed_at is not null;
  if v_email is null or v_email<>lower(new.email) or v_email<>lower(coalesce(auth.jwt()->>'email','')) then
   raise exception using errcode='42501',message='ADMIN_VERIFIED_EMAIL_REQUIRED';end if;
  perform workspace_admin.require_inviter(new.tenant_id,new.invited_by,new.role_id,new.legal_entity_id,new.branch_id);
  perform workspace_admin.require_seat(new.tenant_id,actor);
 end if;
 return new;
end $$;

create function workspace_admin.guard_membership_activation() returns trigger
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();v_email text;i core.invitations%rowtype;a record;begin
 if session_user in('postgres','supabase_admin') and current_setting('role') in('none','postgres','supabase_admin') then return new;end if;
 if new.status<>'active' then return new;end if;
 if tg_op='UPDATE' then
  if old.status='active' then return new;end if;
  perform workspace_admin.require_admin(new.tenant_id,'core.roles.manage');
  if new.user_id=actor then raise exception using errcode='42501',message='ADMIN_PROTECTED_MEMBERSHIP';end if;
  perform workspace_admin.require_seat(new.tenant_id,new.user_id);
  for a in select ra.role_id,ra.legal_entity_id,ra.branch_id from core.role_assignments ra
   where ra.tenant_id=new.tenant_id and ra.membership_id=new.id loop
   perform workspace_admin.require_scope(new.tenant_id,a.legal_entity_id,a.branch_id);
   perform workspace_admin.require_role(new.tenant_id,a.role_id,a.legal_entity_id,a.branch_id);end loop;
  return new;
 end if;
 -- The existing first-workspace bootstrap creates its own first owner seat.
 if actor=new.user_id and exists(select 1 from core.tenants t where t.id=new.tenant_id and t.created_by=actor
  and t.status in('active','trial')) and not exists(select 1 from core.memberships m where m.tenant_id=new.tenant_id) then return new;end if;
 if exists(select 1 from core.memberships m where m.tenant_id=new.tenant_id and m.user_id=new.user_id and m.status<>'active') then
  raise exception using errcode='42501',message='ADMIN_MEMBERSHIP_RESTORE_REQUIRED';end if;
 if new.user_id<>actor or actor is null then
  perform workspace_admin.require_admin(new.tenant_id,'core.roles.manage');
  perform workspace_admin.require_seat(new.tenant_id,new.user_id);return new;
 end if;
 select lower(u.email) into v_email from auth.users u where u.id=actor and u.email_confirmed_at is not null;
 if v_email is null or v_email<>lower(coalesce(auth.jwt()->>'email','')) then
  raise exception using errcode='42501',message='ADMIN_VERIFIED_EMAIL_REQUIRED';end if;
 select * into i from core.invitations iv where iv.tenant_id=new.tenant_id and lower(iv.email)=v_email
  and iv.status='pending' and iv.expires_at>now() order by iv.id limit 1;
 if not found then raise exception using errcode='42501',message='ADMIN_INVITATION_UNAVAILABLE';end if;
 perform workspace_admin.require_inviter(i.tenant_id,i.invited_by,i.role_id,i.legal_entity_id,i.branch_id);
 perform workspace_admin.require_seat(new.tenant_id,actor);
 return new;
end $$;

create trigger workspace_admin_invitation_guard before insert or update on core.invitations
 for each row execute function workspace_admin.guard_invitation();
create trigger workspace_admin_membership_activation_guard before insert or update on core.memberships
 for each row execute function workspace_admin.guard_membership_activation();

revoke all on all functions in schema workspace_admin from public,anon,authenticated,service_role;
revoke all on function api.workspace_admin_list(uuid,text,text,integer),
 api.workspace_admin_command(uuid,uuid,uuid,timestamptz,text,jsonb,bigint),
 api.workspace_my_invitations(uuid),api.workspace_accept_invitation(uuid,uuid) from public,anon,service_role;
grant execute on function api.workspace_admin_list(uuid,text,text,integer),
 api.workspace_admin_command(uuid,uuid,uuid,timestamptz,text,jsonb,bigint),
 api.workspace_my_invitations(uuid),api.workspace_accept_invitation(uuid,uuid) to authenticated;
