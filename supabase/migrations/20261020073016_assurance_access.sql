-- Corporate Audit & Assurance A8: access.
-- CANDIDATE ONLY. Not installed. Requires A1-A5.
--
-- Tenants created before assurance was installed have no assurance.*
-- permission on any role, and the desktop has no way to give an existing
-- member a role. This candidate:
--   * grants every assurance permission to existing tenant owners, as a new
--     tenant's owner already receives at onboarding;
--   * seeds five assignable system roles in every trial or active tenant and,
--     through a trigger, in every new tenant;
--   * adds api.assurance_access (member list with assurance roles, also used
--     for people pickers) and api.assurance_set_role (grant or revoke one of
--     the five roles; tenant-wide role managers with recent MFA), with a
--     per-membership version and an immutable event history.
-- Every role that holds a privileged permission requires MFA, so the
-- ACCESS_PRIVILEGED_NO_MFA monitoring rule stays quiet for seeded roles.

create function assurance.role_catalogue()
returns table (code text, name text, description text, requires_mfa boolean, permissions text[])
language sql immutable set search_path = '' as $$
  values
   ('assurance_lead', 'Audit lead',
    'Plans audits, runs engagements, issues findings and reports, and exports audit packs.', true,
    array['assurance.engagement.close','assurance.engagement.manage','assurance.evidence.request',
      'assurance.evidence.view','assurance.finding.issue','assurance.plan.manage','assurance.report.export',
      'assurance.retention.manage','assurance.test.perform','assurance.test.review']),
   ('assurance_auditor', 'Auditor',
    'Requests and collects evidence, performs tests and raises findings.', true,
    array['assurance.evidence.request','assurance.evidence.view','assurance.finding.issue','assurance.test.perform']),
   ('assurance_reviewer', 'Reviewer',
    'Reviews workpapers, retests remediation and decides reports and risk acceptance.', true,
    array['assurance.engagement.close','assurance.evidence.view','assurance.retest.perform','assurance.test.review']),
   ('assurance_process_owner', 'Process owner',
    'Answers evidence requests, responds to findings and submits remediation.', false,
    array['assurance.evidence.submit','assurance.evidence.view','assurance.remediation.manage','assurance.response.manage']),
   ('assurance_external', 'External reviewer',
    'Time-bound read-only access for external auditors added to an engagement.', false,
    array['assurance.external_review'])
$$;

create function assurance.seed_roles(p_tenant_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into core.roles(tenant_id, code, name, description, requires_mfa, is_system)
  select p_tenant_id, c.code, c.name, c.description, c.requires_mfa, true
    from assurance.role_catalogue() c
  on conflict (tenant_id, code) do nothing;
  insert into core.role_permissions(tenant_id, role_id, permission_code)
  select r.tenant_id, r.id, p
    from assurance.role_catalogue() c
    join core.roles r on r.tenant_id = p_tenant_id and r.code = c.code and r.is_system
    cross join unnest(c.permissions) p
  on conflict (role_id, permission_code) do nothing;
  insert into core.role_permissions(tenant_id, role_id, permission_code)
  select r.tenant_id, r.id, p.code
    from core.roles r cross join core.permissions p
   where r.tenant_id = p_tenant_id and r.code = 'tenant_owner' and p.code like 'assurance.%'
  on conflict (role_id, permission_code) do nothing;
end $$;
revoke all on function assurance.seed_roles(uuid) from public, anon, authenticated, service_role;

create function assurance.seed_roles_on_tenant() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform assurance.seed_roles(new.id);
  return new;
end $$;
create trigger assurance_seed_roles_on_tenant after insert on core.tenants
  for each row execute function assurance.seed_roles_on_tenant();

select assurance.seed_roles(t.id) from core.tenants t where t.status in ('trial','active');

create table assurance.access_versions (
  membership_id uuid primary key,
  tenant_id uuid not null,
  version bigint not null default 0 check (version >= 0),
  foreign key (tenant_id, membership_id) references core.memberships(tenant_id, id)
);
create index assurance_access_versions_tenant_idx on assurance.access_versions(tenant_id, membership_id);

create table assurance.access_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  membership_id uuid not null,
  version bigint not null check (version > 0),
  action text not null check (action in ('grant','revoke')),
  role_code text not null,
  scope text not null check (scope in ('tenant','entity','branch')),
  legal_entity_id uuid,
  branch_id uuid,
  actor_id uuid not null references auth.users(id),
  occurred_at timestamptz not null default clock_timestamp(),
  unique (membership_id, version),
  foreign key (tenant_id, membership_id) references core.memberships(tenant_id, id)
);
create index assurance_access_events_tenant_idx on assurance.access_events(tenant_id, membership_id);
create index assurance_access_events_actor_idx on assurance.access_events(actor_id);
create trigger access_events_immutable before update or delete on assurance.access_events
  for each row execute function assurance.forbid_mutation();

alter table assurance.access_versions enable row level security;
alter table assurance.access_versions force row level security;
alter table assurance.access_events enable row level security;
alter table assurance.access_events force row level security;
revoke all on assurance.access_versions, assurance.access_events from public, anon, authenticated, service_role;

create function assurance.member_label(p_tenant_id uuid, p_membership_id uuid) returns text
language sql stable set search_path = '' as $$
  select coalesce(
    (select e.display_name from people_private.account_links l
       join people.employees e on e.tenant_id = l.tenant_id and e.legal_entity_id = l.legal_entity_id
        and e.id = l.employee_id
      where l.tenant_id = p_tenant_id and l.membership_id = p_membership_id and l.status = 'accepted'
      limit 1),
    'Unlinked member ····' || right(p_membership_id::text, 4));
$$;

create function api.assurance_access(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_after uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_manage boolean;
  v_members jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  v_manage := core.has_permission(p_tenant_id, 'core.roles.manage');
  if not v_manage
     and not core.has_permission(p_tenant_id, 'assurance.plan.manage', p_legal_entity_id, p_branch_id)
     and not core.has_permission(p_tenant_id, 'assurance.engagement.manage', p_legal_entity_id, p_branch_id) then
    perform assurance.deny('ASSURANCE_ACCESS_DENIED');
  end if;
  select coalesce(jsonb_agg(s.row order by s.id), '[]'::jsonb) into v_members
    from (select m.id, jsonb_build_object(
            'membership_id', m.id,
            'label', assurance.member_label(p_tenant_id, m.id),
            'linked', exists (select 1 from people_private.account_links l
                       where l.tenant_id = p_tenant_id and l.membership_id = m.id and l.status = 'accepted'),
            'version', coalesce((select v.version from assurance.access_versions v where v.membership_id = m.id), 0),
            'assignments', coalesce((select jsonb_agg(jsonb_build_object(
                'role_code', r.code,
                'scope', case when ra.legal_entity_id is null then 'tenant'
                              when ra.branch_id is null then 'entity' else 'branch' end,
                'legal_entity_id', ra.legal_entity_id,
                'branch_id', ra.branch_id) order by r.code, ra.legal_entity_id, ra.branch_id)
              from core.role_assignments ra
              join core.roles r on r.tenant_id = ra.tenant_id and r.id = ra.role_id
             where ra.tenant_id = p_tenant_id and ra.membership_id = m.id and r.is_system
               and r.code in (select c.code from assurance.role_catalogue() c)), '[]'::jsonb)) as row
            from core.memberships m
           where m.tenant_id = p_tenant_id and m.status = 'active'
             and (p_after is null or m.id > p_after)
           order by m.id
           limit 50) s;
  return jsonb_build_object(
    'can_manage', v_manage,
    'roles', (select jsonb_agg(jsonb_build_object('code', c.code, 'name', c.name,
                'description', c.description, 'requires_mfa', c.requires_mfa,
                'permissions', to_jsonb(c.permissions)) order by c.code)
                from assurance.role_catalogue() c),
    'members', v_members,
    'next_cursor', case when jsonb_array_length(v_members) = 50
                        then v_members->49->'membership_id' else 'null'::jsonb end);
end $$;

create function api.assurance_set_role(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_idempotency_key uuid,
  p_payload jsonb,
  p_expected_version bigint
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_hash text;
  v_receipt assurance.command_receipts%rowtype;
  v_member uuid;
  v_code text;
  v_granted boolean;
  v_scope text;
  v_entity uuid;
  v_branch uuid;
  v_role uuid;
  v_version bigint;
  v_response jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object'
     or exists (select 1 from jsonb_object_keys(p_payload) k
                 where k <> all (array['membership_id','role_code','granted','scope'])) then
    raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD';
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  -- Role management is tenant-wide: a branch-scoped role manager is refused.
  perform core.require_permission(p_tenant_id, 'core.roles.manage');
  if p_expected_version is null then
    raise exception using errcode = '22023', message = 'ASSURANCE_VERSION_REQUIRED';
  end if;
  v_hash := encode(extensions.digest(convert_to(jsonb_build_array(
    p_tenant_id, p_legal_entity_id, p_branch_id, p_expected_version, p_payload)::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt from assurance.command_receipts
   where actor_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    if v_receipt.request_hash <> v_hash or v_receipt.tenant_id <> p_tenant_id then
      raise exception using errcode = '22023', message = 'IDEMPOTENCY_MISMATCH';
    end if;
    return v_receipt.response;
  end if;
  if not assurance.recent_mfa() then
    perform assurance.deny('ASSURANCE_RECENT_MFA_REQUIRED');
  end if;
  v_member := assurance.uuid_field(p_payload, 'membership_id');
  v_code := p_payload->>'role_code';
  if coalesce(jsonb_typeof(p_payload->'role_code'), '') <> 'string'
     or not exists (select 1 from assurance.role_catalogue() c where c.code = v_code) then
    raise exception using errcode = '22023', message = 'ASSURANCE_ROLE_UNKNOWN';
  end if;
  if coalesce(jsonb_typeof(p_payload->'granted'), '') <> 'boolean' then
    raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'granted';
  end if;
  v_granted := (p_payload->>'granted')::boolean;
  v_scope := p_payload->>'scope';
  if coalesce(jsonb_typeof(p_payload->'scope'), '') <> 'string'
     or v_scope not in ('tenant','entity','branch')
     or (v_scope = 'branch' and p_branch_id is null) then
    raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID', detail = 'scope';
  end if;
  v_entity := case when v_scope = 'tenant' then null else p_legal_entity_id end;
  v_branch := case when v_scope = 'branch' then p_branch_id else null end;
  if not exists (select 1 from core.memberships m
                  where m.tenant_id = p_tenant_id and m.id = v_member and m.status = 'active') then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_MEMBER_NOT_FOUND';
  end if;
  insert into assurance.access_versions(membership_id, tenant_id) values (v_member, p_tenant_id)
  on conflict (membership_id) do nothing;
  select version into v_version from assurance.access_versions where membership_id = v_member for update;
  if v_version <> p_expected_version then
    raise exception using errcode = '40001', message = 'ASSURANCE_VERSION_CONFLICT';
  end if;
  select r.id into v_role from core.roles r
   where r.tenant_id = p_tenant_id and r.code = v_code and r.is_system;
  if v_role is null then
    raise exception using errcode = '55000', message = 'ASSURANCE_ROLE_NOT_SEEDED';
  end if;
  if v_granted then
    if not exists (select 1 from core.role_assignments ra
                    where ra.tenant_id = p_tenant_id and ra.membership_id = v_member and ra.role_id = v_role
                      and ra.legal_entity_id is not distinct from v_entity
                      and ra.branch_id is not distinct from v_branch) then
      insert into core.role_assignments(tenant_id, membership_id, role_id, legal_entity_id, branch_id, created_by)
      values (p_tenant_id, v_member, v_role, v_entity, v_branch, v_uid);
    end if;
  else
    delete from core.role_assignments ra
     where ra.tenant_id = p_tenant_id and ra.membership_id = v_member and ra.role_id = v_role
       and ra.legal_entity_id is not distinct from v_entity
       and ra.branch_id is not distinct from v_branch;
    if not found then
      raise exception using errcode = 'P0002', message = 'ASSURANCE_ASSIGNMENT_NOT_FOUND';
    end if;
  end if;
  update assurance.access_versions set version = version + 1
   where membership_id = v_member returning version into v_version;
  insert into assurance.access_events(tenant_id, membership_id, version, action, role_code, scope,
    legal_entity_id, branch_id, actor_id)
  values (p_tenant_id, v_member, v_version, case when v_granted then 'grant' else 'revoke' end,
    v_code, v_scope, v_entity, v_branch, v_uid);
  v_response := jsonb_build_object('membership_id', v_member, 'version', v_version,
    'role_code', v_code, 'granted', v_granted, 'scope', v_scope);
  insert into assurance.command_receipts(actor_id, idempotency_key, tenant_id, request_hash, response)
  values (v_uid, p_idempotency_key, p_tenant_id, v_hash, v_response);
  return v_response;
end $$;

revoke all on function assurance.role_catalogue() from public, anon, authenticated, service_role;
revoke all on function assurance.member_label(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function assurance.seed_roles_on_tenant() from public, anon, authenticated, service_role;
revoke all on function api.assurance_access(uuid, uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_access(uuid, uuid, uuid, uuid) to authenticated;
revoke all on function api.assurance_set_role(uuid, uuid, uuid, uuid, jsonb, bigint) from public, anon, service_role;
grant execute on function api.assurance_set_role(uuid, uuid, uuid, uuid, jsonb, bigint) to authenticated;
