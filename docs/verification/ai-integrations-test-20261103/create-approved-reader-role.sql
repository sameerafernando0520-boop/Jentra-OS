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

begin read only;
set local transaction_read_only=on;
set local statement_timeout='10s';
set local search_path='';
select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),
 'syntheticAllowed',exists(select 1 from intelligence_control.synthetic_tenants where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and allowed),
 'branchActive',exists(select 1 from core.branches where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid
 and id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid and legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid and status='active'),
 'nonFixtureBillingMemberships',(select count(*) from core.memberships m join core.tenants t on t.id=m.tenant_id
 where m.user_id='c6aa32c0-d91f-4555-8687-e77fdf878e0c'::uuid and t.slug!~'^jentra-w5-(runtime|load-[0-9]{3})-20261008$'),
 'activeMemberCount',(select count(*) from core.memberships where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and status='active'),
 'viewerMembershipCount',(select count(*) from core.memberships where user_id='89f63c7a-dc28-4f33-859e-eae277193522'::uuid),
 'seats',(select seats from billing.tenant_subscriptions where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'subscription',(select jsonb_build_object('id',id,'version',version::text,'plan',plan_code,'status',status,'trialStart',trial_started_at,'trialEnd',trial_ends_at)
 from billing.tenant_subscriptions where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'roleCreated',exists(select 1 from core.roles where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and id='28d81f05-27c5-4673-85d5-eeb51a515f27'::uuid),
 'roleId','28d81f05-27c5-4673-85d5-eeb51a515f27',
 'permissions',coalesce((select jsonb_agg(permission_code order by permission_code) from core.role_permissions where role_id='28d81f05-27c5-4673-85d5-eeb51a515f27'::uuid),'[]'::jsonb),
 'profileMembershipCount',(select count(*) from core.memberships where user_id='89f63c7a-dc28-4f33-859e-eae277193522'::uuid),
 'modelInvocationCount',(select count(*) from intelligence_control.model_invocations where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),
 'futureQuotaPeriodCount',(select count(*) from intelligence_control.quota_periods where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and period_end>statement_timestamp()),
 'runtimeScopes',(select jsonb_agg(to_jsonb(s)) from intelligence_control.runtime_worker_scopes s where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid),
 'scheduleAuthorities',(select jsonb_agg(jsonb_build_object('enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at))
 from intelligence_control.edge_authorities where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid)
) || jsonb_build_object('recoveredMfaSessionVerified',exists(select 1 from auth.sessions s join auth.mfa_factors f on f.id=s.factor_id and f.user_id=s.user_id where s.id='fabbe711-8b69-4b7e-abf8-ad34b14d729a'::uuid and s.user_id='c6aa32c0-d91f-4555-8687-e77fdf878e0c'::uuid and s.aal::text='aal2' and f.id='f1aff352-1c36-4326-8e2e-0f96e4fb6bca'::uuid and f.status::text='verified' and f.factor_type::text='totp' and (s.not_after is null or s.not_after>statement_timestamp()))) as approved_test_setup_preflight;
rollback;
