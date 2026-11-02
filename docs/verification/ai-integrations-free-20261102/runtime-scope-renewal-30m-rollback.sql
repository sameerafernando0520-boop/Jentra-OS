-- ROLLBACK-ONLY PROOF. No permission change is committed or exposed to other sessions.
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
 or s.issued_at is distinct from '2026-10-13T08:13:04.144135+00:00'::timestamptz
 or s.expires_at is distinct from '2026-10-14T08:13:04.144135+00:00'::timestamptz
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
rollback;

select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv','runtimeId','778237e3-3d4e-4871-8cc9-e08b07b989c7',
 'observedAt',statement_timestamp(),'rollbackOnly',true,'privateTargetAllowAssertionPassed',true,'otherBranchDenyAssertionPassed',true,
 'baselineRestored',exists(select 1 from intelligence_control.runtime_worker_scopes
  where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid and tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid
  and legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid and branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid
  and enabled and issued_at='2026-10-13T08:13:04.144135+00:00'::timestamptz and expires_at='2026-10-14T08:13:04.144135+00:00'::timestamptz),
 'targetStillInactive',not intelligence_control.runtime_scope_allowed('778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid,
  'babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid,'3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid),
 'scheduleAuthorityStillInactive',not exists(select 1 from intelligence_control.edge_authorities
  where runtime_id='778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid and enabled and issued_at<=statement_timestamp() and expires_at>statement_timestamp()))
 as runtime_scope_renewal_trial;
