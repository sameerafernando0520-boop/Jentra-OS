-- Fixed development runtime only. Execute through a renewed, project-confirmed
-- privileged SQL connection. No secrets, request bodies, suggestions or payload
-- bytes are returned. Missing contracts/permissions fail; never install them here.
-- All ledger projections share the snapshot of the single WITH/SELECT below.
-- The SQL Editor may already have issued a query in its outer transaction.
begin read only;
set local transaction_read_only = on;
set local statement_timeout = '10s';
set local search_path = '';
with bindings as (
 select '778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid runtime_id
), scopes as (
 select s.* from intelligence_control.runtime_worker_scopes s join bindings b using(runtime_id)
), tenants as (select distinct tenant_id from scopes),
models as (
 select coalesce(o.state,'pending') state,r.reserved_units::text reserved,o.tokens::text tokens,u.quantity::text quantity,
  r.metric_code metric,coalesce(u.event_id::text=m.request->>'usageEventId',false) "eventMatches",
  coalesce(r.reserved_units::text=m.request->>'maxTokens' and r.period_start=(m.request->>'periodStart')::timestamptz
   and q.period_end=(m.request->>'periodEnd')::timestamptz,false) "reservationMatches",
  f.source_hash=m.source_hash "sourceMatches"
 from intelligence_control.model_invocations m
 join analytics.pipeline_forecasts f on f.tenant_id=m.tenant_id and f.id=m.source_id
 left join intelligence_control.model_outcomes o using(invocation_id)
 left join intelligence_control.usage_reservations r on r.tenant_id=m.tenant_id and r.invocation_id=m.invocation_id
 left join intelligence_control.usage_events u on u.tenant_id=m.tenant_id and u.invocation_id=m.invocation_id
 left join intelligence_control.quota_periods q on q.tenant_id=r.tenant_id and q.metric_code=r.metric_code and q.period_start=r.period_start
 where exists(select 1 from scopes s where s.tenant_id=f.tenant_id and s.legal_entity_id=f.legal_entity_id
  and s.branch_id is not distinct from f.branch_id)
 order by m.created_at,m.invocation_id limit 1001
), deliveries as (
 select d.state,d.attempt,o.state outcome,o.http_status "httpStatus",r.reserved_units::text reserved,
  u.quantity::text quantity,r.metric_code metric,coalesce(u.event_id=d.usage_event_id,false) "eventMatches",
  rc.event_id is not null "receiptPresent",
  coalesce(rc.sha256=encode(extensions.digest(rc.payload,'sha256'),'hex'),false) "receiptHashMatches",
  exists(select 1 from intelligence_control.delivery_heads prior
   join intelligence_control.delivery_attempts pa on pa.tenant_id=prior.tenant_id and pa.delivery_id=prior.id
   where prior.tenant_id=d.tenant_id and prior.subscription_id=d.subscription_id and prior.event_id=d.event_id
    and pa.key_version=rc.key_version and pa.claimed_at<=rc.received_at) "receiptKeyMatches"
 from intelligence_control.delivery_heads d
 join intelligence_control.integration_subscriptions sub on sub.tenant_id=d.tenant_id and sub.id=d.subscription_id
 left join intelligence_control.delivery_outcomes o on o.tenant_id=d.tenant_id and o.delivery_id=d.id and o.attempt=d.attempt
 left join intelligence_control.usage_reservations r on r.tenant_id=d.tenant_id and r.invocation_id=d.invocation_id
 left join intelligence_control.usage_events u on u.tenant_id=d.tenant_id and u.invocation_id=d.invocation_id
 left join intelligence_control.edge_receiver_receipts rc on rc.runtime_id=(select runtime_id from bindings)
  and rc.tenant_id=d.tenant_id and rc.subscription_id=d.subscription_id and rc.event_id=d.event_id
  and rc.legal_entity_id=sub.legal_entity_id and rc.branch_id is not distinct from sub.branch_id
 where exists(select 1 from scopes s where s.tenant_id=sub.tenant_id and s.legal_entity_id=sub.legal_entity_id
  and s.branch_id is not distinct from sub.branch_id)
 order by d.id limit 1001
), corrections as (
 select c.tenant_id,c.original_event_id,sum(c.quantity) units from intelligence_control.usage_corrections c
 join tenants t using(tenant_id) group by c.tenant_id,c.original_event_id
), totals as (
 select r.tenant_id,r.metric_code,r.period_start,
  coalesce(sum(r.reserved_units) filter(where u.invocation_id is null),0) expected_reserved,
  coalesce(sum(u.quantity-coalesce(c.units,0)),0) expected_settled
 from intelligence_control.usage_reservations r join tenants t using(tenant_id)
 left join intelligence_control.usage_events u on u.tenant_id=r.tenant_id and u.invocation_id=r.invocation_id
 left join corrections c on c.tenant_id=u.tenant_id and c.original_event_id=u.event_id
 group by r.tenant_id,r.metric_code,r.period_start
), quotas as (
 select q.settled_units::text settled,q.reserved_units::text reserved,
  coalesce(t.expected_reserved,0)::text "expectedReserved",coalesce(t.expected_settled,0)::text "expectedSettled"
 from intelligence_control.quota_periods q join tenants using(tenant_id)
 left join totals t on t.tenant_id=q.tenant_id and t.metric_code=q.metric_code and t.period_start=q.period_start
 order by q.tenant_id,q.metric_code,q.period_start limit 1001
)
select jsonb_build_object('contractRevision',1,'projectId','xpdoufauvrbdmxgngetv',
 'runtimeId',(select runtime_id from bindings),'observedAt',statement_timestamp(),
 'authorityActive',exists(select 1 from intelligence_control.edge_authorities a join bindings b using(runtime_id)
  where a.enabled and a.issued_at<=statement_timestamp() and a.expires_at>statement_timestamp()
   and exists(select 1 from scopes s join core.branches br on br.tenant_id=s.tenant_id and br.id=s.branch_id
    and br.legal_entity_id=s.legal_entity_id where s.enabled and s.issued_at<=statement_timestamp()
     and s.expires_at>statement_timestamp() and br.status='active')),
 'truncated',(select count(*)>1000 from models) or (select count(*)>1000 from deliveries) or (select count(*)>1000 from quotas),
 'models',coalesce((select jsonb_agg(to_jsonb(m)) from models m),'[]'::jsonb),
 'deliveries',coalesce((select jsonb_agg(to_jsonb(d)) from deliveries d),'[]'::jsonb),
 'quotas',coalesce((select jsonb_agg(to_jsonb(q)) from quotas q),'[]'::jsonb)) as hosted_accounting_snapshot;
rollback;
