begin read only;
set local transaction_read_only=on;
set local statement_timeout='10s';
set local search_path='';
select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),
 'tenantId','babe6c86-a764-4d3a-80a3-952a7c096c2c',
 'subscriptions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'planCode',s.plan_code,
 'status',s.status,'seats',s.seats,'createdAt',s.created_at,'trialStartedAt',s.trial_started_at,
 'trialEndsAt',s.trial_ends_at,'periodEndsAt',s.current_period_ends_at,
 'activeNow',(s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
 or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())),
 'requiredEntitlements',(select jsonb_agg(jsonb_build_object('code',p.entitlement_code,'enabled',p.enabled) order by p.entitlement_code)
 from billing.plan_entitlements p where p.plan_code=s.plan_code and p.entitlement_code in ('analytics','module.ai'))))
 from billing.tenant_subscriptions s where s.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid),'[]'::jsonb),
 'activeMemberCount',(select count(*) from core.memberships where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and status='active'),
 'observedNativeUserPresent',exists(select 1 from auth.users where id='626e2632-5887-4550-92e9-d4c6d45d1aa0'::uuid and email_confirmed_at is not null and deleted_at is null)
) as test_profile_billing_readiness;
rollback;
