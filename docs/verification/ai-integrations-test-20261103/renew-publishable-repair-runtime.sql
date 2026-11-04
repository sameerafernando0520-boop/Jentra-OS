-- PREPARED V12 repair window. NOT APPLIED: explicit owner approval required.
-- Only the existing synthetic branch scope is renewed. Edge/schedule authority,
-- accounts, business permissions, model budgets and all delivery rows are unchanged.
begin;
set local statement_timeout = '10s';
set local lock_timeout = '2s';
set local search_path = '';
do $renew$
declare s record; a record; changed integer; starts timestamptz := statement_timestamp();
begin
 select enabled,issued_at,expires_at into strict s
 from intelligence_control.runtime_worker_scopes
 where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid
 and tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid
 and legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid
 and branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid for update;
 if s.enabled is not true
 or s.issued_at is distinct from '2026-11-02T21:05:44.987115+00:00'::timestamptz
 or s.expires_at is distinct from '2026-11-02T21:35:44.987115+00:00'::timestamptz
 or s.expires_at>=starts then raise exception 'EXPIRED_SCOPE_PREIMAGE_CHANGED';end if;
 select enabled,issued_at,expires_at into strict a from intelligence_control.edge_authorities
 where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid for update;
 if a.enabled is not true
 or a.issued_at is distinct from '2026-10-13T09:57:07.481942+00:00'::timestamptz
 or a.expires_at is distinct from '2026-10-14T09:57:07.481942+00:00'::timestamptz
 or a.expires_at>=starts then raise exception 'EDGE_AUTHORITY_PREIMAGE_CHANGED';end if;
 if not exists(select 1 from intelligence_control.synthetic_tenants
  where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and allowed)
 then raise exception 'SYNTHETIC_TENANT_NOT_APPROVED';end if;
 if intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid,
  'babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid,
  '3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid) then raise exception 'SCOPE_ALREADY_ACTIVE';end if;
 if exists(select 1 from intelligence_control.model_invocations where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid)
 or exists(select 1 from intelligence_control.model_outcomes where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid)
 or exists(select 1 from intelligence_control.usage_reservations where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid)
 or exists(select 1 from intelligence_control.usage_events where invocation_id='bf887435-88db-4a1f-9df9-2e9ec326f9b4'::uuid)
 then raise exception 'PRESERVED_MODEL_RECORD_EXISTS';end if;
 if not exists(select 1 from billing.tenant_subscriptions where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid
 and version=5 and plan_code='w5_runtime_20261008' and seats=5 and status='trialing'
 and trial_started_at<=starts and trial_ends_at>starts)
 then raise exception 'APPROVED_TRIAL_MUST_BE_ACTIVE_FIRST';end if;
 update intelligence_control.runtime_worker_scopes set issued_at=starts,expires_at=starts+interval '30 minutes'
 where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid
 and tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid
 and legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid
 and branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid;
 get diagnostics changed=row_count;
 if changed<>1 then raise exception 'SCOPE_ROW_COUNT_MISMATCH';end if;
 if not intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid,
  'babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid,
  '3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid) then raise exception 'TARGET_SCOPE_NOT_ALLOWED';end if;
 if intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid,
  'babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid,
  '00000000-0000-4000-8000-000000000000'::uuid) then raise exception 'OTHER_BRANCH_NOT_DENIED';end if;
 if exists(select 1 from intelligence_control.edge_authorities
  where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid and enabled
  and issued_at<=statement_timestamp() and expires_at>statement_timestamp())
 then raise exception 'SCHEDULE_AUTHORITY_UNEXPECTEDLY_ACTIVE';end if;
end $renew$;
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
) as approved_test_setup_preflight;
rollback;
