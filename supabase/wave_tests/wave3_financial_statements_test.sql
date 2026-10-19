-- Synthetic dated entity. All report and accounting fixtures roll back.
select pg_temp.actor('creator');
insert into core.legal_entities(id,tenant_id,name,code,currency_code,rounding_scale,created_by)
values(pg_temp.fid('report.entity'),pg_temp.fid('tenant'),'Report Fixture Entity','RPT','LKR',2,pg_temp.fid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('report.branch'),pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 'Report Fixture Branch','RPT',pg_temp.fid('creator'));
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('creator.role'),
 pg_temp.fid('report.entity'),null,pg_temp.fid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid('report.'||x),pg_temp.fid('tenant'),pg_temp.fid('report.entity'),upper(x),
 x||' fixture account',case x when 'cash' then 'asset' when 'equity' then 'equity'
 when 'revenue' then 'revenue' else 'expense' end,
 case when x in('cash','expense') then 'debit' else 'credit' end,
 pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['cash','equity','revenue','expense'])x;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.fid('report.july'),pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 'Report July','2026-07-01','2026-07-31',pg_temp.fid('creator'),pg_temp.fid('creator')),
(pg_temp.fid('report.august'),pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 'Report August','2026-08-01','2026-08-31',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 'journal_entry','RPT-',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.report_post(n text,d date,debit text,credit text,amount numeric)
returns uuid language sql as $$select finance.flow_post_journal(jsonb_build_object(
 'tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('report.entity'),
 'branch_id',pg_temp.fid('report.branch'),'document_date',d,
 'currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('report.'||debit),amount,amount),
 finance.flow_jline(pg_temp.fid('report.'||credit),-amount,-amount)),
 'report_fixture',pg_temp.fid(n),pg_temp.fid(n||'.request'),pg_temp.fid(n||'.command'))$$;
select pg_temp.report_post('report.opening','2026-07-01','cash','equity',100);
select pg_temp.report_post('report.july.sale','2026-07-10','cash','revenue',30);
select pg_temp.report_post('report.july.cost','2026-07-15','expense','cash',10);
select pg_temp.report_post('report.august.sale','2026-08-05','cash','revenue',50);
select pg_temp.report_post('report.august.cost','2026-08-07','expense','cash',20);
create function pg_temp.report_payload(n text,k text) returns jsonb language sql as $$
select jsonb_build_object('id',pg_temp.fid(n),'kind',k,'period_id',pg_temp.fid('report.august'),
 'as_of','2026-08-31','comparative_period_id',pg_temp.fid('report.july'))$$;
create function pg_temp.report_call(n text,k text) returns jsonb language sql as $$
select api.generate_financial_statement(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid(n||'.command'),pg_temp.fid(n||'.key'),
 '2026-09-25T00:00:00Z',pg_temp.report_payload(n,k),0)$$;
insert into procurement_responses values('report.trial',pg_temp.report_call('report.trial','trial_balance'));
insert into procurement_test_results select is((select response#>>'{entity,period_debit}' from procurement_responses
 where name='report.trial'),'70.000000','trial balance freezes August exact debits');
insert into procurement_test_results select is((select response#>>'{entity,period_credit}' from procurement_responses
 where name='report.trial'),'70.000000','trial balance freezes August exact credits');
insert into procurement_test_results select is((select response#>>'{entity,closing_debit}' from procurement_responses
 where name='report.trial'),'180.000000','trial balance carries earlier posted balances');
insert into procurement_test_results select is((select response#>>'{entity,difference}' from procurement_responses
 where name='report.trial'),'0.000000','trial balance is balanced');
insert into procurement_test_results select is(pg_temp.report_call('report.trial','trial_balance'),
 (select response from procurement_responses where name='report.trial'),
 'financial report replays sealed receipt');
insert into procurement_responses values('report.pnl',pg_temp.report_call('report.pnl','profit_loss'));
insert into procurement_test_results select is((select response#>>'{entity,net_profit}' from procurement_responses
 where name='report.pnl'),'30.000000','P&L uses August movements only');
insert into procurement_test_results select is((select response#>>'{entity,comparative,net_profit}' from procurement_responses
 where name='report.pnl'),'20.000000','P&L comparison uses July movements');
insert into procurement_responses values('report.balance',pg_temp.report_call('report.balance','balance_sheet'));
insert into procurement_test_results select is((select response#>>'{entity,assets}' from procurement_responses
 where name='report.balance'),'150.000000','balance sheet uses closing asset basis');
insert into procurement_test_results select is((select response#>>'{entity,current_earnings}' from procurement_responses
 where name='report.balance'),'50.000000','balance sheet includes unclosed cumulative earnings');
insert into procurement_test_results select is((select response#>>'{entity,comparative,current_earnings}' from procurement_responses
 where name='report.balance'),'20.000000','comparative balance includes prior earnings');
insert into procurement_test_results select is((select response#>>'{entity,difference}' from procurement_responses
 where name='report.balance'),'0.000000','balance sheet equation reconciles exactly');
insert into procurement_test_results select is((api.financial_statement_page(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 pg_temp.fid('report.balance'),'accounts',0,pg_temp.fid('report.cash'))#>>'{items,0,comparative_amount}'),
 '120.000000','comparative account drill uses earlier closing balance');
insert into procurement_test_results select is((select jsonb_array_length(
 api.financial_statement_page(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid('report.trial'),'journals',0,
 pg_temp.fid('report.cash'))->'items')),5,'account drill-through retains posted source lines');
select pg_temp.report_post('report.late','2026-08-20','cash','revenue',1);
insert into procurement_test_results select is((select response#>>'{entity,period_debit}' from procurement_responses
 where name='report.trial'),'70.000000','later backdated posting cannot rewrite saved report receipt');
insert into procurement_test_results select is((select summary->>'journal_count' from finance.financial_reports
 where id=pg_temp.fid('report.trial')),'10','later backdated posting cannot rewrite frozen journal evidence');
insert into procurement_test_results select is((select jsonb_array_length(
 api.financial_statement_page(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid('report.trial'),'journals',0,null)->'items')),
 10,'later backdated posting does not alter saved drill-through');
insert into procurement_test_results select throws_ok($$select pg_temp.report_call('report.invalid','cash_flow')$$,
 '22023','FINANCIAL_REPORT_INPUT_INVALID','unsupported statement is rejected');
insert into procurement_test_results select throws_ok($$select api.generate_financial_statement(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 pg_temp.fid('report.bad.comparison.command'),pg_temp.fid('report.bad.comparison.key'),
 '2026-09-25T00:00:00Z',pg_temp.report_payload('report.bad.comparison','trial_balance')
 ||jsonb_build_object('comparative_period_id',pg_temp.fid('report.august')),0)$$,
 '22023','FINANCIAL_REPORT_COMPARISON_INVALID','current period cannot compare with itself');
insert into procurement_test_results select throws_ok($$delete from finance.financial_reports
 where id=pg_temp.fid('report.trial')$$,'55000',null,'financial report evidence is immutable');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.financial_statement_page(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 pg_temp.fid('report.trial'),'accounts',0,null)$$,
 '42501',null,'outsider cannot page frozen journal evidence');
insert into procurement_test_results select throws_ok($$select api.financial_statement_reports(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'))$$,
 '42501',null,'outsider cannot read entity financial reports');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.financial_reports$$,
 '42501',null,'authenticated direct financial evidence read denied');
reset role;
