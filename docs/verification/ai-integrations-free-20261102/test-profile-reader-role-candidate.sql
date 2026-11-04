-- NOT APPLIED. Requires explicit owner approval before COMMIT.
-- Creates one unassigned synthetic role with exactly three existing read rights.
-- Membership is granted separately through the normal MFA-checked invitation API.
begin;
set local statement_timeout='10s';
set local lock_timeout='2s';
set local search_path='';
do $role$
declare t constant uuid := 'babe6c86-a764-4d3a-80a3-952a7c096c2c';
 r constant uuid := '28d81f05-27c5-4673-85d5-eeb51a515f27';
begin
 perform 1 from core.tenants where id=t and name='Synthetic Wave 5 runtime' and status in('trial','active') for update;
 if not found then raise exception 'SYNTHETIC_TENANT_PREIMAGE_CHANGED';end if;
 if not exists(select 1 from intelligence_control.synthetic_tenants where tenant_id=t and allowed)
 or not exists(select 1 from core.branches where tenant_id=t
 and id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid
 and legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid and status='active')
 then raise exception 'APPROVED_SYNTHETIC_BRANCH_REQUIRED';end if;
 if not exists(select 1 from auth.users where id='89f63c7a-dc28-4f33-859e-eae277193522'::uuid
 and email='jentra-test-4dd40f8b1f69@fldubai.com' and email_confirmed_at is not null and deleted_at is null)
 or exists(select 1 from core.memberships where user_id='89f63c7a-dc28-4f33-859e-eae277193522'::uuid)
 then raise exception 'EXACT_UNASSIGNED_TEST_PROFILE_REQUIRED';end if;
 if exists(select 1 from core.roles where id=r or (tenant_id=t and code='w5_temp_ai_reader_20261102'))
 then raise exception 'TEST_ROLE_ALREADY_EXISTS_NO_RETRY';end if;
 if (select count(*) from core.permissions where code in('analytics.view','crm.opportunities.view','ai.proposals.view') and not privileged)<>3
 then raise exception 'EXACT_THREE_NONPRIVILEGED_READ_PERMISSIONS_REQUIRED';end if;
 insert into core.roles(id,tenant_id,code,name,description,requires_mfa,is_system)
 values(r,t,'w5_temp_ai_reader_20261102','Temporary AI test reader',
 'Owner-approved synthetic test reader. Assignment must use the normal MFA-checked invitation API and the reviewed RT1 entity/branch scope.',false,false);
 insert into core.role_permissions(tenant_id,role_id,permission_code)
 select t,r,code from core.permissions where code in('analytics.view','crm.opportunities.view','ai.proposals.view') and not privileged;
 if (select array_agg(permission_code order by permission_code) from core.role_permissions where tenant_id=t and role_id=r)
 is distinct from array['ai.proposals.view','analytics.view','crm.opportunities.view']::text[]
 then raise exception 'TEST_ROLE_PERMISSION_SET_MISMATCH';end if;
 if exists(select 1 from core.role_assignments where role_id=r)
 then raise exception 'NEW_ROLE_MUST_REMAIN_UNASSIGNED';end if;
end $role$;
commit;
