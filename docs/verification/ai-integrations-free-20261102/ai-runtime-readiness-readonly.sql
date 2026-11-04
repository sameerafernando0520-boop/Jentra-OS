begin read only;
set local transaction_read_only = on;
set local statement_timeout = '10s';
set local search_path = '';
with source_candidates as (
 select f.id,f.source_hash from analytics.pipeline_forecasts f
 where f.tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid
 and f.legal_entity_id='caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid
 and f.branch_id='3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid
 order by f.id limit 10
)
select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),
 'runtimeId','778237e3-3d4e-4871-8cc9-e08b07b989c7',
 'syntheticTenantAllowed',exists(select 1 from intelligence_control.synthetic_tenants
 where tenant_id='babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid and allowed),
 'sourceCountAtMostTen',(select count(*) from source_candidates),
 'sourceCandidates',coalesce((select jsonb_agg(to_jsonb(f)) from source_candidates f),'[]'::jsonb)) as ai_runtime_readiness;
rollback;
