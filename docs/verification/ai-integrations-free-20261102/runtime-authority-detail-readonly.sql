begin read only;
set local transaction_read_only = on;
set local statement_timeout = '10s';
set local search_path = '';
with binding as (
 select '778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid runtime_id
), authorities as (
 select a.enabled, a.issued_at, a.expires_at
 from intelligence_control.edge_authorities a join binding b using(runtime_id)
 limit 10
), scopes as (
 select s.tenant_id,s.legal_entity_id,s.branch_id,s.enabled,s.issued_at,s.expires_at,br.status branch_state
 from intelligence_control.runtime_worker_scopes s join binding b using(runtime_id)
 join core.branches br on br.tenant_id=s.tenant_id and br.id=s.branch_id and br.legal_entity_id=s.legal_entity_id
 limit 10
)
select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv',
 'runtimeId',(select runtime_id from binding),'observedAt',statement_timestamp(),
 'authorities',coalesce((select jsonb_agg(to_jsonb(a)) from authorities a),'[]'::jsonb),
 'scopes',coalesce((select jsonb_agg(to_jsonb(s)) from scopes s),'[]'::jsonb)) as runtime_authority_detail;
rollback;
