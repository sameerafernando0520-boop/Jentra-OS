select pg_temp.actor('creator');
insert into procurement_test_results select has_function('finance','wave3_dashboard_aging',
 'dashboard uses one bounded dated open-item residual helper');
insert into procurement_test_results select function_lang_is('api','wave3_dashboard','plpgsql',
 'dashboard metrics are resolved on the server');
create temp table wave3_dashboard_result as select api.wave3_dashboard(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch')) body;
insert into procurement_test_results select ok(exists(select 1 from wave3_dashboard_result,
 jsonb_array_elements(body->'metrics')m where m->>'kind'='ap_aging'),
 'permitted payment role receives currency-separated AP aging');
insert into procurement_test_results select ok(exists(select 1 from wave3_dashboard_result,
 jsonb_array_elements(body->'metrics')m where m->>'kind'='cash_bank'),
 'finance role receives branch cash and bank controls');
insert into procurement_test_results select ok(not exists(select 1 from wave3_dashboard_result,
 jsonb_array_elements(body->'metrics')m where m->>'tenant_id'<>pg_temp.fid('tenant')::text
 or m->>'legal_entity_id'<>pg_temp.fid('entity')::text or m->>'branch_id'<>pg_temp.fid('branch')::text
 or m->>'generated_at' is null or m->>'as_of' is null),
 'every metric carries the selected scope and explicit cutoff/time');
insert into procurement_test_results select is(
 (select coalesce(sum((r->>'amount')::numeric),0)::text from wave3_dashboard_result,
 jsonb_array_elements(body->'metrics')m,jsonb_array_elements(m#>'{data,buckets}')r where m->>'kind'='ap_aging'),
 (select coalesce(sum((finance.flow_residual(tenant_id,id,(statement_timestamp() at time zone 'UTC')::date)->>'amount')::numeric),0)::text
  from finance.open_items where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')
   and branch_id=pg_temp.fid('branch') and kind='AP' and posting_date<=(statement_timestamp() at time zone 'UTC')::date),
 'AP dashboard sums exactly to dated immutable residuals including credits');
insert into procurement_test_results select is((select m->'data' from wave3_dashboard_result,
 jsonb_array_elements(body->'metrics')m where m->>'kind'='cash_bank'),
 finance.build_branch_cash_controls(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 (statement_timestamp() at time zone 'UTC')::date)->'controls',
 'dashboard cash evidence equals authoritative branch reconciliation basis');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant')
 and role_id=pg_temp.fid('creator.role') and permission_code='finance.payments.manage';
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(
 api.wave3_dashboard(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->'metrics')m
 where m->>'kind'='ap_aging'),'revoked payment permission removes AP aging rather than returning stale evidence');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.payments.manage');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant')
 and role_id=pg_temp.fid('creator.role') and permission_code='inventory.stock.view';
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(
 api.wave3_dashboard(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->'cards')m
 where m->>'kind' in('goods_receipt','delivery','stock_count','inventory_transfer')),
 'cost source queue requires stock as well as cost and source permission');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.stock.view');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok(
 $$select api.wave3_dashboard(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))$$,
 '42501','SOURCE_UNAVAILABLE','nonmember cannot resolve known dashboard scope');
select pg_temp.actor('creator');
insert into procurement_test_results select is((select provolatile::text from pg_proc
 where oid='api.wave3_dashboard(uuid,uuid,uuid)'::regprocedure),'s',
 'nested dashboard metrics share a stable statement snapshot');
