select pg_temp.actor('creator');
insert into procurement_test_results select has_function('api','wave3_observability_status',
 'read-only scoped Wave 3 diagnostic depth exists');
insert into procurement_test_results select ok(not has_function_privilege('anon',
 'api.wave3_observability_status(uuid,uuid,uuid)','execute'),'anonymous diagnostics are forbidden');
create temp table wave3_depth_before as select api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch')) body;
insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload,status,
 actor_id,request_id,command_id,correlation_id)
select tenant_id,'synthetic.wave3.dead_letter','goods_receipt',pg_temp.fid('landed.receipt'),
 jsonb_build_object('bank_credentials','DO_NOT_EXPOSE','contact','private@example.test'),
 'dead_letter',actor_id,request_id,command_id,correlation_id
from core.command_receipts where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')
 and branch_id=pg_temp.fid('branch') order by id limit 1;
create temp table wave3_depth_after as select api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch')) body;
insert into procurement_test_results select is((select body->>'dead_letter_depth' from wave3_depth_after),
 ((select (body->>'dead_letter_depth')::int from wave3_depth_before)+1)::text,
 'one dead-letter event increments only the current immutable receipt scope');
insert into procurement_test_results select ok((select not body::text like '%DO_NOT_EXPOSE%'
 and not body::text like '%private@example.test%' from wave3_depth_after),
 'diagnostic depth never reveals payload or bank/contact data');
insert into procurement_test_results select is((select count(*)::int from wave3_depth_after,
 jsonb_object_keys(body)k),5,'diagnostic response contains only scope, observation date and count');
insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload,status,
 actor_id,request_id,command_id,correlation_id)
select tenant_id,'synthetic.wave4.dead_letter','private_hr_request',pg_temp.fid('landed.receipt'),
 '{}','dead_letter',actor_id,request_id,command_id,correlation_id
from core.command_receipts where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')
 and branch_id=pg_temp.fid('branch') order by id limit 1;
insert into procurement_test_results select is(api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'dead_letter_depth',
 (select body->>'dead_letter_depth' from wave3_depth_after),'private Wave 4 events are outside Wave 3 diagnostics');
insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload,status,
 actor_id,request_id,command_id,correlation_id)
select r.tenant_id,'synthetic.wave3.dead_letter',k,pg_temp.fid('landed.receipt'),
 '{}','dead_letter',r.actor_id,r.request_id,r.command_id,r.correlation_id
from (select * from core.command_receipts where tenant_id=pg_temp.fid('tenant')
 and legal_entity_id=pg_temp.fid('entity') and branch_id=pg_temp.fid('branch') order by id limit 1)r,
 unnest(array['crm_lead','customer_allocation_reversal','financial_statement_report','bank_match',
 'wave3_notification_subscription'])k;
insert into procurement_test_results select is(api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'dead_letter_depth',
 ((select (body->>'dead_letter_depth')::int from wave3_depth_after)+5)::text,
 'CRM, allocation corrections, financial reports, bank matching and subscriptions are counted');
insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload,status,
 actor_id,request_id,command_id,correlation_id)
select tenant_id,'synthetic.opening.dead_letter','stock_opening',pg_temp.fid('landed.receipt'),
 '{}','dead_letter',actor_id,request_id,command_id,correlation_id
from core.command_receipts where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')
 and branch_id=pg_temp.fid('branch') order by id limit 1;
insert into procurement_test_results select is(api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'dead_letter_depth',
 ((select (body->>'dead_letter_depth')::int from wave3_depth_after)+5)::text,
 'acceptance-owned stock-opening events are outside Wave 3 diagnostic count');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role')
 and permission_code='core.roles.manage';
insert into procurement_test_results select throws_ok($$select api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))$$,'42501',null,
 'revoked current scope permission closes diagnostic access');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'core.roles.manage') on conflict do nothing;
insert into procurement_test_results select throws_ok($$select api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('other.entity'),pg_temp.fid('branch'))$$,null,null,
 'foreign entity scope never reveals local queue depth');
insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload,status,
 actor_id,request_id,command_id,correlation_id)
select r.tenant_id,'synthetic.wave3.dead_letter','goods_receipt',pg_temp.fid('landed.receipt'),
 '{}','dead_letter',r.actor_id,r.request_id,r.command_id,r.correlation_id
from (select * from core.command_receipts where tenant_id=pg_temp.fid('tenant')
 and legal_entity_id=pg_temp.fid('entity') and branch_id=pg_temp.fid('branch') order by id limit 1)r,
 generate_series(1,10001);
insert into procurement_test_results select throws_ok($$select api.wave3_observability_status(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))$$,'54000','LIMIT_EXCEEDED',
 'oversized diagnostic depth fails explicitly instead of returning a partial count');
