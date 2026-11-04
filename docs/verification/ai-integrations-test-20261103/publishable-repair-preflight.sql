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
 'preservedInvocationAbsent',not exists(select 1 from intelligence_control.model_invocations where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'preservedOutcomeAbsent',not exists(select 1 from intelligence_control.model_outcomes where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'preservedReservationAbsent',not exists(select 1 from intelligence_control.usage_reservations where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'preservedUsageAbsent',not exists(select 1 from intelligence_control.usage_events where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid),
 'forecastBasisUnchanged',exists(select 1 from analytics.pipeline_forecasts where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid and branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid and id='38742ecf-91fe-4cd3-93c5-9d6f726a59e5'::uuid and source_hash='0e9255bd3871c3ee8130ec94af09d1e21c4ec73191d8ade81f23923f21ca1e47'),
 'aiPlanEntitlementConfigured',exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code where s.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and p.entitlement_code='module.ai' and p.enabled),
 'futureQuotaPeriodCount',(select count(*) from intelligence_control.quota_periods where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and period_end>statement_timestamp()),
 'runtimeScopes',(select jsonb_agg(to_jsonb(s)) from intelligence_control.runtime_worker_scopes s where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid),
 'scheduleAuthorities',(select jsonb_agg(jsonb_build_object('enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at))
 from intelligence_control.edge_authorities where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid)
) as approved_test_setup_preflight;
rollback;
