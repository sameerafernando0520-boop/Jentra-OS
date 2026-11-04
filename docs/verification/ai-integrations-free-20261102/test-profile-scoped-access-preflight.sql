begin read only;
set local transaction_read_only=on;
set local statement_timeout='10s';
set local search_path='';
with binding as (
 select '89f63c7a-dc28-4f33-859e-eae277193522'::uuid user_id,
 'babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid tenant_id,
 'caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid legal_entity_id,
 '3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid branch_id,
 '778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid runtime_id
), scoped_roles as (
 select r.id,r.code,r.name,r.requires_mfa,r.is_system,
 coalesce((select jsonb_agg(rp.permission_code order by rp.permission_code)
 from core.role_permissions rp where rp.tenant_id=r.tenant_id and rp.role_id=r.id),'[]'::jsonb) permissions
 from core.roles r join binding b using(tenant_id)
), selected_permissions as (
 select code,module,privileged from core.permissions
 where code in ('analytics.view','crm.opportunities.view','ai.proposals.view')
)
select jsonb_build_object(
 'projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),
 'testUser',(select jsonb_build_object('id',u.id,'email',u.email,
 'confirmed',u.email_confirmed_at is not null,'name',u.raw_user_meta_data->>'full_name')
 from auth.users u join binding b on u.id=b.user_id
 where u.email='jentra-test-4dd40f8b1f69@fldubai.com'),
 'membershipCount',(select count(*) from core.memberships m join binding b on m.user_id=b.user_id),
 'tenant',(select jsonb_build_object('id',t.id,'name',t.name,'status',t.status,
 'syntheticAllowed',exists(select 1 from intelligence_control.synthetic_tenants s where s.tenant_id=t.id and s.allowed),
 'createdBy',t.created_by) from core.tenants t join binding b on t.id=b.tenant_id),
 'branch',(select jsonb_build_object('id',br.id,'legalEntityId',br.legal_entity_id,'status',br.status)
 from core.branches br join binding b on br.tenant_id=b.tenant_id and br.id=b.branch_id and br.legal_entity_id=b.legal_entity_id),
 'roles',coalesce((select jsonb_agg(to_jsonb(r) order by r.code) from scoped_roles r),'[]'::jsonb),
 'requestedPermissions',coalesce((select jsonb_agg(to_jsonb(p) order by p.code) from selected_permissions p),'[]'::jsonb),
 'businessListAuthenticatedAllowed',pg_catalog.has_function_privilege('authenticated','api.list_my_tenants()','execute'),
 'businessListAnonymousAllowed',pg_catalog.has_function_privilege('anon','api.list_my_tenants()','execute'),
 'runtimeScope',(select to_jsonb(s) from intelligence_control.runtime_worker_scopes s join binding b using(runtime_id,tenant_id,legal_entity_id,branch_id)),
 'scheduleAuthority',(select jsonb_build_object('enabled',a.enabled,'issuedAt',a.issued_at,'expiresAt',a.expires_at)
 from intelligence_control.edge_authorities a join binding b using(runtime_id))
) as test_profile_access_preflight;
rollback;
