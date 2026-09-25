-- Exercises dated immutable mappings and the posted indirect method in rollback.
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.cash_flow.configure')
on conflict do nothing;
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,
 account_kind,account_id,currency_code,created_by,updated_by)
values(pg_temp.fid('report.bank'),pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),'RPT-CASH','Report cash account','bank',
 pg_temp.fid('report.cash'),'LKR',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.cashflow_call(n text) returns jsonb language sql as $$
select api.generate_financial_statement(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid(n||'.command'),pg_temp.fid(n||'.key'),
 '2026-09-25T00:00:00Z',pg_temp.report_payload(n,'cash_flow'),0)$$;
insert into procurement_responses values('cashflow.blocked',pg_temp.cashflow_call('cashflow.blocked'));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses
 where name='cashflow.blocked'),'blocked','cash flow without mappings freezes a blocking report');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,unmapped_count}' from procurement_responses
 where name='cashflow.blocked'),'1','cash flow reports missing mapped cash');
create function pg_temp.map_cashflow(n text,account_name text,category text,expected_version bigint default 0)
returns jsonb language sql as $$
select api.configure_cash_flow_mapping(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid(n||'.command'),pg_temp.fid(n||'.key'),
 '2026-09-25T00:00:00Z',jsonb_build_object('id',pg_temp.fid(n),
 'account_id',pg_temp.fid('report.'||account_name),'category',category,
 'effective_date','2026-07-01','reason','Approved cash flow classification'),expected_version)$$;
insert into procurement_responses values('cashflow.map.cash',
 pg_temp.map_cashflow('cashflow.map.cash','cash','cash'));
insert into procurement_test_results select is((select response#>>'{entity,version}' from procurement_responses
 where name='cashflow.map.cash'),'1','cash mapping begins at version one');
insert into procurement_test_results select is(pg_temp.map_cashflow('cashflow.map.cash','cash','cash'),
 (select response from procurement_responses where name='cashflow.map.cash'),
 'cash mapping replays the original receipt');
insert into procurement_responses values('cashflow.map.equity',
 pg_temp.map_cashflow('cashflow.map.equity','equity','financing'));
insert into procurement_responses values('cashflow.ready',pg_temp.cashflow_call('cashflow.ready'));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses
 where name='cashflow.ready'),'generated','fully mapped cash flow is generated');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,period_profit}' from procurement_responses
 where name='cashflow.ready'),'31.000000','cash flow starts from August posted profit');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,net_cash_change}' from procurement_responses
 where name='cashflow.ready'),'31.000000','August indirect change equals cash movement');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,opening_cash}' from procurement_responses
 where name='cashflow.ready'),'120.000000','August opening cash is posted July balance');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,closing_cash}' from procurement_responses
 where name='cashflow.ready'),'151.000000','closing cash reconciles mapped bank GL');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,difference}' from procurement_responses
 where name='cashflow.ready'),'0.000000','cash-flow bridge reconciles exactly');
insert into procurement_test_results select is((select response#>>'{entity,comparative,financing_cash}' from procurement_responses
 where name='cashflow.ready'),'100.000000','comparative period financing is frozen');
insert into procurement_test_results select is((select response#>>'{entity,comparative,net_cash_change}' from procurement_responses
 where name='cashflow.ready'),'120.000000','comparative cash flow bridges July profit and capital');
insert into procurement_test_results select is((select x->>'category' from jsonb_array_elements(
 api.cash_flow_mapping_options(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),'2026-08-31',null)->'items')x
 where x->>'account_id'=pg_temp.fid('report.cash')::text),
 'cash','mapping picker shows the dated bank classification');
insert into procurement_test_results select throws_ok($$select pg_temp.map_cashflow(
 'cashflow.invalid.cash','equity','cash')$$,'22023','CASH_FLOW_CASH_ACCOUNT_INVALID',
 'nonbank equity account cannot become mapped cash');
insert into procurement_test_results select throws_ok($$select pg_temp.map_cashflow(
 'cashflow.stale','cash','cash',0)$$,'40001',null,
 'stale mapping version cannot replace the current classification');
insert into procurement_test_results select throws_ok($$update finance.cash_flow_mapping_events
 set category='investing' where id=pg_temp.fid('cashflow.map.equity')$$,'55000',null,
 'cash mapping history is immutable');
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,
 created_by,updated_by)
values(pg_temp.fid('report.receivable'),pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 'RPT-REC','Report receivable','asset','debit',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.report_post('report.unmapped','2026-08-24','receivable','revenue',5);
insert into procurement_responses values('cashflow.unmapped',pg_temp.cashflow_call('cashflow.unmapped'));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses
 where name='cashflow.unmapped'),'blocked','unmapped working capital blocks a new report');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,unmapped_count}' from procurement_responses
 where name='cashflow.unmapped'),'1','unmapped account is counted');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,unmapped_accounts,0,code}' from procurement_responses
 where name='cashflow.unmapped'),'RPT-REC','unmapped account is named for close review');
insert into procurement_responses values('cashflow.map.receivable',
 pg_temp.map_cashflow('cashflow.map.receivable','receivable','working_capital'));
insert into procurement_responses values('cashflow.working',pg_temp.cashflow_call('cashflow.working'));
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,working_capital_change}' from procurement_responses
 where name='cashflow.working'),'-5.000000','receivable increase subtracts from operating cash');
insert into procurement_test_results select is((select response#>>'{entity,cash_flow,operating_cash}' from procurement_responses
 where name='cashflow.working'),'31.000000','cash flow bridges higher profit through working capital');
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses
 where name='cashflow.working'),'generated','new mapping clears the cash-flow blocker');
insert into procurement_test_results select is((select summary->>'status' from finance.financial_reports
 where id=pg_temp.fid('cashflow.unmapped')),'blocked','later mapping never rewrites blocked history');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.cash_flow_mapping_options(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),'2026-08-31',null)$$,
 '42501',null,'outsider cannot inspect cash-flow mappings');
insert into procurement_test_results select throws_ok($$select pg_temp.map_cashflow(
 'cashflow.denied','receivable','investing',1)$$,'42501',null,
 'outsider cannot reclassify cash-flow accounts');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.cash_flow_mapping_events$$,
 '42501',null,'authenticated direct mapping read denied');
reset role;
