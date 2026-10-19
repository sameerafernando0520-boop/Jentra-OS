-- Posted August journal lines were created by the financial-statement and
-- cash-flow fixtures. All commands and reports roll back with this suite.
select pg_temp.actor('creator');
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('budget.other.branch'),pg_temp.fid('tenant'),
 pg_temp.fid('report.entity'),'Other budget fixture branch','RPT-B',pg_temp.fid('creator'));
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.budgets.manage'),
 (pg_temp.fid('tenant'),pg_temp.fid('approver.role'),'finance.budgets.approve')
on conflict do nothing;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('approver.membership'),
 pg_temp.fid('approver.role'),pg_temp.fid('report.entity'),null,pg_temp.fid('creator'));

create function pg_temp.budget_payload(n text,action text,amount text default '50')
returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fid(n),
 'action',action,'period_id',pg_temp.fid('report.august'),'budget_year',2026,
 'branch_id',pg_temp.fid('report.branch'),'currency_code','LKR',
 'reason','Approved August operating budget',
 'lines',jsonb_build_array(jsonb_build_object('id',pg_temp.fid('budget.revenue.line'),
  'account_id',pg_temp.fid('report.revenue'),'amount',amount),
  jsonb_build_object('id',pg_temp.fid('budget.expense.line'),
  'account_id',pg_temp.fid('report.expense'),'amount','25')))
$$;
create function pg_temp.budget_call(n text,payload jsonb,expected bigint)
returns jsonb language sql as $$select api.budget_command(pg_temp.fid('tenant'),
 pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),pg_temp.fid(n||'.command'),
 pg_temp.fid(n||'.key'),'2026-09-25T00:00:00Z',payload,expected)$$;

insert into procurement_responses values('budget.create',pg_temp.budget_call('budget.create',
 pg_temp.budget_payload('budget.one','create'),0));
insert into procurement_test_results select is((select response#>>'{entity,status}'
 from procurement_responses where name='budget.create'),'draft',
 'versioned budget starts in draft state');
insert into procurement_test_results select is(pg_temp.budget_call('budget.create',
 pg_temp.budget_payload('budget.one','create'),0),
 (select response from procurement_responses where name='budget.create'),
 'budget create replays the exact command receipt');
insert into procurement_test_results select throws_ok($$select pg_temp.budget_call(
 'budget.dimension',jsonb_set(pg_temp.budget_payload('budget.dimension','create'),
 '{lines,0,cost_centre_id}',to_jsonb(pg_temp.fid('unavailable.cost.centre'))),0)$$,
 '22023','BUDGET_DIMENSION_UNAVAILABLE',
 'unavailable cost-centre model cannot accept invented dimensions');
insert into procurement_test_results select throws_ok($$select pg_temp.budget_call(
 'budget.numeric',jsonb_set(pg_temp.budget_payload('budget.numeric','create'),
 '{lines,0,amount}','50'::jsonb),0)$$,'22023','BUDGET_LINE_INVALID',
 'budget amounts reject JSON numbers');
insert into procurement_test_results select throws_ok($$select pg_temp.budget_call(
 'budget.stale',pg_temp.budget_payload('budget.one','save','55'),0)$$,
 '40001','VERSION_CONFLICT','stale budget edit retains server version');
select pg_temp.budget_call('budget.save',pg_temp.budget_payload('budget.one','save','55'),1);
insert into procurement_test_results select is((select lines#>>'{0,amount}'
 from finance.budget_versions where id=pg_temp.fid('budget.one')),'55.000000',
 'budget save canonicalizes exact string amount');
select pg_temp.budget_call('budget.submit',pg_temp.budget_payload('budget.one','submit'),2);
insert into procurement_test_results select is((select reason from finance.budget_events
 where budget_id=pg_temp.fid('budget.one') and action='submit'),
 'Approved August operating budget','budget transition retains its governed reason');
insert into procurement_test_results select is((select status from finance.budget_versions
 where id=pg_temp.fid('budget.one')),'submitted','submitted budget freezes editable line state');
insert into procurement_test_results select throws_ok($$select pg_temp.budget_call(
 'budget.self.approve',pg_temp.budget_payload('budget.one','approve'),3)$$,
 '42501',null,'creator cannot approve own submitted budget');
select pg_temp.actor('approver');
insert into procurement_responses values('budget.approve',pg_temp.budget_call('budget.approve',
 pg_temp.budget_payload('budget.one','approve'),3));
insert into procurement_test_results select is((select response#>>'{entity,status}'
 from procurement_responses where name='budget.approve'),'approved',
 'independent approver freezes selected budget version');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.budget_call(
 'budget.edit.approved',pg_temp.budget_payload('budget.one','save','60'),4)$$,
 '55000','BUDGET_STATE_INVALID','approved budget cannot be edited');
insert into procurement_test_results select throws_ok($$update finance.budget_versions
 set status='draft' where id=pg_temp.fid('budget.one')$$,'55000',
 'BUDGET_HISTORY_IMMUTABLE','approved budget remains immutable for trusted caller');
insert into procurement_responses values('budget.revise',pg_temp.budget_call('budget.revise',
 pg_temp.budget_payload('budget.two','revise')||
 jsonb_build_object('source_id',pg_temp.fid('budget.one')),4));
insert into procurement_test_results select is((select response#>>'{entity,revision}'
 from procurement_responses where name='budget.revise'),'2',
 'approved budget revision creates a new draft version');
insert into procurement_test_results select is((select status from finance.budget_versions
 where id=pg_temp.fid('budget.one')),'approved',
 'revision does not rewrite the approved source');

create function pg_temp.variance_call(n text) returns jsonb language sql as $$
select api.generate_budget_variance(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid(n||'.command'),pg_temp.fid(n||'.key'),
 '2026-09-25T00:00:00Z',jsonb_build_object('id',pg_temp.fid(n),
 'budget_id',pg_temp.fid('budget.one'),'as_of','2026-08-31'),0)$$;
insert into procurement_responses values('budget.variance',pg_temp.variance_call('budget.variance'));
insert into procurement_test_results select is((select response#>>'{entity,budget_total}'
 from procurement_responses where name='budget.variance'),'80.000000',
 'variance freezes the approved exact budget amount');
insert into procurement_test_results select is((select response#>>'{entity,actual_total}'
 from procurement_responses where name='budget.variance'),'76.000000',
 'variance uses posted August actual in normal-balance direction');
insert into procurement_test_results select is((select response#>>'{entity,variance_total}'
 from procurement_responses where name='budget.variance'),'-4.000000',
 'variance total is exact actual less approved budget');
insert into procurement_test_results select is((select response#>>'{entity,variance_percent}'
 from procurement_responses where name='budget.variance'),'-5.000000',
 'variance percentage uses exact decimal division');
insert into procurement_test_results select is((api.budget_variance_page(pg_temp.fid('tenant'),
 pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),pg_temp.fid('budget.variance'),
 'lines',0,null)#>>'{items,0,actual_amount}'),'56.000000',
 'bounded variance line page uses deterministic frozen account order');
insert into procurement_test_results select is((select jsonb_array_length(
 api.budget_variance_page(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid('budget.variance'),'journals',0,
 pg_temp.fid('budget.revenue.line'))->'items')),3,
 'budget revenue drill retains three posted source journal lines');
insert into procurement_test_results select is((select jsonb_array_length(
 api.budget_variance_page(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('report.branch'),pg_temp.fid('budget.variance'),'lines',0,
 pg_temp.fid('budget.revenue.line'))->'items')),1,
 'budget line filter returns only its frozen account');
insert into procurement_test_results select is((select jsonb_array_length(
 api.budget_variance_reports(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),
 pg_temp.fid('budget.other.branch'))->'items')),0,
 'another permitted branch cannot list this branch report');
insert into procurement_test_results select throws_ok($$select api.budget_variance_page(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('budget.other.branch'),
 pg_temp.fid('budget.variance'),'lines',0,null)$$,'42501','BUDGET_REPORT_SCOPE_REQUIRED',
 'another permitted branch cannot open this branch report');
select pg_temp.report_post('budget.backdated','2026-08-25','cash','revenue',2);
insert into procurement_test_results select is((select summary->>'actual_total'
 from finance.budget_variance_reports where id=pg_temp.fid('budget.variance')),
 '76.000000','backdated posting cannot rewrite frozen variance evidence');
insert into procurement_test_results select is((select response#>>'{entity,actual_total}'
 from procurement_responses where name='budget.variance'),'76.000000',
 'saved command receipt stays immutable after later posting');
insert into procurement_test_results select throws_ok($$delete from finance.budget_events
 where budget_id=pg_temp.fid('budget.one')$$,'55000',null,
 'budget transition history cannot be deleted');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.budget_options(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'))$$,
 '42501',null,'outsider cannot browse budget versions');
insert into procurement_test_results select throws_ok($$select api.budget_variance_page(
 pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 pg_temp.fid('budget.variance'),'lines',0,null)$$,'42501',null,
 'outsider cannot inspect posted actual drill-through');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.budget_versions$$,
 '42501',null,'authenticated direct budget read denied');
insert into procurement_test_results select throws_ok($$select * from finance.budget_variance_reports$$,
 '42501',null,'authenticated direct variance read denied');
reset role;
