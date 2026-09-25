select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid(x||'.role'),p from unnest(array['creator','approver'])x
cross join unnest(array['finance.view','finance.period.close','finance.period.reopen','finance.controls.reconcile','finance.fx.post'])p on conflict do nothing;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('tenant'),pg_temp.fid(x||'.membership'),pg_temp.fid(x||'.role'),
 pg_temp.fid('entity'),null,pg_temp.fid('creator') from unnest(array['creator','approver'])x;
create function pg_temp.period_id() returns uuid language sql stable as $$
 select id from finance.fiscal_periods where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')
 and date '2026-09-21' between start_date and end_date and status='active' limit 1$$;
create function pg_temp.period_payload(a text,n text) returns jsonb language sql as $$
 select jsonb_build_object('action',a,'id',pg_temp.fid(n),'period_id',pg_temp.period_id(),
 'reason','Synthetic governed period transition')$$;
create function pg_temp.period_actor(p text,age_seconds integer default 0,aal text default 'aal2')
returns void language plpgsql as $$begin
 perform pg_temp.actor(p,aal);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(p),'role','authenticated',
 'aal',aal,'amr',jsonb_build_array(jsonb_build_object('method','totp',
 'timestamp',extract(epoch from clock_timestamp())::bigint-age_seconds)))::text,true);
end$$;
insert into procurement_test_results select is(
 (select jsonb_array_length(api.period_governance_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'periods')->'items')>0),
 true,'period options expose scoped active periods');
insert into procurement_test_results select throws_ok(
 $$update finance.fiscal_periods set state='soft_locked' where id=pg_temp.period_id()$$,
 '55000','PERIOD_TRANSITION_COMMAND_REQUIRED','setup and direct writes cannot bypass period command');
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
values(pg_temp.fid('fx.party'),pg_temp.fid('tenant'),'FXTEST','FX Test Customer','FX Test Customer',
 'customer',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.fid('fx.control'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'FXCONTROL','FX test control',
 'asset','debit',pg_temp.fid('creator'),pg_temp.fid('creator')),
(pg_temp.fid('fx.revenue'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'FXREVENUE','FX test revenue',
 'revenue','credit',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,target_currency_code,
 rate,effective_date,rate_type,created_by,updated_by)
values(pg_temp.fid('fx.rate.12'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'USD','LKR',1.2,
 '2026-09-19','closing',pg_temp.fid('creator'),pg_temp.fid('creator')),
(pg_temp.fid('fx.rate.13'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'USD','LKR',1.3,
 '2026-09-20','closing',pg_temp.fid('creator'),pg_temp.fid('creator'));
select finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),
 'branch_id',pg_temp.fid('branch'),'document_date','2026-09-21','currency_code','USD',
 'base_currency_code','LKR','exchange_rate','1'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('fx.control'),100,100),
 finance.flow_jline(pg_temp.fid('fx.revenue'),-100,-100)),
 'fx_open_fixture',pg_temp.fid('fx.open.source'),gen_random_uuid(),pg_temp.fid('fx.open.command'));
insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,
 document_number,currency_code,base_currency_code,exchange_rate,original_amount,original_base_amount,
 posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
select pg_temp.fid('fx.open.item'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'AR',
 pg_temp.fid('fx.party'),'fx_open_fixture',pg_temp.fid('fx.open.source'),'FX-OPEN-1','USD','LKR',1,100,100,
 '2026-09-21','2026-10-21',j.id,gen_random_uuid(),pg_temp.fid('fx.open.command'),gen_random_uuid(),pg_temp.fid('creator')
from finance.journal_entries j where j.tenant_id=pg_temp.fid('tenant') and j.source_id=pg_temp.fid('fx.open.source');
create function pg_temp.fx_payload(n text,rate text,action text default 'post') returns jsonb language sql as $$
 select jsonb_build_object('action',action,'id',pg_temp.fid(n),'period_id',pg_temp.period_id(),
 'as_of','2026-09-21','currency_code','USD','exchange_rate_id',pg_temp.fid(rate),
 'reason','Synthetic period-end rate correction')$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_exchange_revaluation',
 pg_temp.fx_payload('fx.bad.reason','fx.rate.12')-'reason',0)$$,
 '22023','FX_REVALUATION_INPUT_INVALID','FX command rejects a missing reason');
insert into procurement_test_results select throws_ok($$select pg_temp.call('period_governance_command',
 pg_temp.period_payload('soft_lock','period.bad.reason')-'reason',
 (select version from finance.fiscal_periods where id=pg_temp.period_id()))$$,
 '22023','PERIOD_COMMAND_INVALID','period command rejects a missing reason');
select pg_temp.bank_journal('period.unmatched.source',1);
insert into procurement_responses values('period.version.before',jsonb_build_object('version',
 (select version from finance.fiscal_periods where id=pg_temp.period_id())));
insert into procurement_responses values('period.soft',pg_temp.call('period_governance_command',
 pg_temp.period_payload('soft_lock','period.soft'),
 (select (response->>'version')::bigint from procurement_responses where name='period.version.before'),'period.soft'));
insert into procurement_test_results select is((select state from finance.fiscal_periods where id=pg_temp.period_id()),
 'soft_locked','authorized soft lock changes period state');
insert into procurement_test_results select is(pg_temp.call('period_governance_command',
 pg_temp.period_payload('soft_lock','period.soft'),
 (select (response->>'version')::bigint from procurement_responses where name='period.version.before'),'period.soft'),
 (select response from procurement_responses where name='period.soft'),'sealed soft-lock replay returns original receipt');
insert into procurement_test_results select throws_ok(
 $$select pg_temp.bank_journal('period.soft.post',1)$$,'55000','PERIOD_CLOSED',
 'soft lock rejects ordinary journal posting');
insert into procurement_responses values('fx.run.12',pg_temp.call('post_exchange_revaluation',
 pg_temp.fx_payload('fx.run.12','fx.rate.12'),0,'fx.run.12'));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses where name='fx.run.12'),
 'posted','soft lock permits an exact closing-rate FX adjustment');
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l
 where l.account_id=pg_temp.fid('fx.control') and l.journal_entry_id=(select journal_entry_id from finance.fx_revaluation_runs
 where id=pg_temp.fid('fx.run.12'))),20::numeric,'unrealized gain debits the frozen AR control basis');
insert into procurement_test_results select is((select count(*) from jsonb_array_elements(
 finance.period_control_fx_variance(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 'AR','2026-09-21',finance.build_control_report(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),jsonb_build_object('kind','AR','as_of','2026-09-21'))))x
 where x->>'evidence_key'=pg_temp.fid('fx.control')::text),0::bigint,
 'independent FX snapshot explains only its control-command variance');
insert into procurement_test_results select is((select sum(l.transaction_debit+l.transaction_credit) from finance.journal_lines l
 where l.journal_entry_id=(select journal_entry_id from finance.fx_revaluation_runs where id=pg_temp.fid('fx.run.12'))),
 0::numeric,'unrealized revaluation never changes source-currency principal');
insert into procurement_test_results select is((select original_amount::text||':'||original_base_amount::text
 from finance.open_items where id=pg_temp.fid('fx.open.item')),'100.000000:100.000000',
 'FX posting leaves the immutable open-item original untouched');
insert into procurement_test_results select is(pg_temp.call('post_exchange_revaluation',
 pg_temp.fx_payload('fx.run.12','fx.rate.12'),0,'fx.run.12'),
 (select response from procurement_responses where name='fx.run.12'),'FX sealed replay returns original receipt');
insert into procurement_responses values('fx.run.13',pg_temp.call('post_exchange_revaluation',
 pg_temp.fx_payload('fx.run.13','fx.rate.13'),0));
insert into procurement_test_results select is((select replacement_run_id from finance.fx_revaluation_reversals
 where run_id=pg_temp.fid('fx.run.12')),pg_temp.fid('fx.run.13'),
 'new rate automatically links prior unrealized reversal');
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l
 join finance.journal_entries j on j.id=l.journal_entry_id
 where l.account_id=pg_temp.fid('fx.control') and j.source_type in('exchange_revaluation','exchange_revaluation_reversal')),
 30::numeric,'replacement produces one deterministic net control valuation');
insert into procurement_test_results select throws_ok($$delete from finance.fx_revaluation_runs
 where id=pg_temp.fid('fx.run.12')$$,'55000',null,'FX run and rate evidence are immutable');
select pg_temp.call('post_exchange_revaluation',pg_temp.fx_payload('fx.run.13.reverse','fx.rate.13','reverse')
 ||jsonb_build_object('run_id',pg_temp.fid('fx.run.13')),1);
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l
 join finance.journal_entries j on j.id=l.journal_entry_id
 where l.account_id=pg_temp.fid('fx.control') and j.source_type in('exchange_revaluation','exchange_revaluation_reversal')),
 0::numeric,'explicit linked FX reversal restores original base control');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_exchange_revaluation',
 pg_temp.fx_payload('fx.run.13.reverse.2','fx.rate.13','reverse')
 ||jsonb_build_object('run_id',pg_temp.fid('fx.run.13')),1)$$,
 '55000','FX_RUN_NOT_ACTIVE','duplicate FX reversal denied');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_exchange_revaluation',
 pg_temp.fx_payload('fx.backdated','fx.rate.12')||jsonb_build_object('as_of','2026-09-20'),0)$$,
 '22023','FX_DATE_BEFORE_ACTIVE_RUN','past FX run cannot be inserted after later historical runs');
insert into procurement_test_results select cmp_ok(jsonb_array_length(api.exchange_revaluation_options(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'runs')->'items'),'>=',2,
 'scoped FX run register retains both rates');
insert into procurement_test_results select is((select exists(select 1 from jsonb_array_elements(
 api.exchange_revaluation_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('fx.run.12'))->'items')x where x->>'id'=pg_temp.fid('fx.open.item')::text)),
 true,'bounded FX detail retains source open-item lineage');

-- A separate past period has configured AR/AP controls and no unresolved
-- postings. Exercise the real close path, rather than forging the state.
insert into core.legal_entities(id,tenant_id,name,code,currency_code,rounding_scale,created_by)
values(pg_temp.fid('clean.entity'),pg_temp.fid('tenant'),'Clean Close Entity','CLOSE','LKR',2,pg_temp.fid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('clean.branch'),pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),
 'Clean Close Branch','CLOSE',pg_temp.fid('creator'));
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('creator.role'),
 pg_temp.fid('clean.entity'),null,pg_temp.fid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid('clean.'||x),pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),upper(x),x||' control',
 case when x='payable' then 'liability' when x='variance' then 'expense' else 'asset' end,
 case when x='payable' then 'credit' else 'debit' end,pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['receivable','payable','input_tax','variance'])x;
insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),'receivable_control',
 pg_temp.fid('clean.receivable'),pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into procurement.supplier_bill_controls(tenant_id,legal_entity_id,payable_account_id,
 input_tax_account_id,variance_account_id,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),pg_temp.fid('clean.payable'),
 pg_temp.fid('clean.input_tax'),pg_temp.fid('clean.variance'),pg_temp.fid('creator'));
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.fid('clean.period'),pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),'Closed August',
 '2026-08-01','2026-08-31',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.clean_close_call(a text,n text) returns jsonb language sql as $$
 select api.period_governance_command(pg_temp.fid('tenant'),pg_temp.fid('clean.entity'),
 pg_temp.fid('clean.branch'),pg_temp.fid(n),pg_temp.fid(n),'2026-09-25T00:00:00Z',
 jsonb_build_object('action',a,'id',pg_temp.fid(n),'period_id',pg_temp.fid('clean.period'),
 'reason','Synthetic reconciled period close'),
 (select version from finance.fiscal_periods where id=pg_temp.fid('clean.period')))$$;
select pg_temp.clean_close_call('soft_lock','clean.soft');
insert into procurement_test_results select is((select state from finance.fiscal_periods
 where id=pg_temp.fid('clean.period')),'soft_locked','clean configured period enters soft lock');
insert into procurement_responses values('clean.hard',pg_temp.clean_close_call('hard_lock','clean.hard'));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses
 where name='clean.hard'),'hard_locked','reconciled past period reaches real hard close');
insert into procurement_test_results select is((select exceptions from finance.period_events
 where id=pg_temp.fid('clean.hard')),'[]'::jsonb,'successful hard close records empty exception evidence');

insert into procurement_responses values('period.blocked',pg_temp.call('period_governance_command',
 pg_temp.period_payload('hard_lock','period.blocked'),
 (select version from finance.fiscal_periods where id=pg_temp.period_id())));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses where name='period.blocked'),
 'blocked','hard close records unresolved checks instead of locking');
insert into procurement_test_results select cmp_ok((select jsonb_array_length(exceptions) from finance.period_events
 where id=pg_temp.fid('period.blocked')),'>',0,'blocked close preserves exception evidence');
insert into procurement_test_results select is((select exists(select 1 from finance.period_events ev
 cross join lateral jsonb_array_elements(ev.exceptions) issue
 where ev.id=pg_temp.fid('period.blocked') and issue->>'code'='FX_REVALUATION_REQUIRED'
 and issue->>'currency_code'='USD')),true,
 'hard close requires a current period-end FX run after prior reversal');
insert into procurement_test_results select is((select state from finance.fiscal_periods where id=pg_temp.period_id()),
 'soft_locked','blocked close leaves state unchanged');
-- The fixture contains deliberate unreconciled bank evidence. Create a hard state
-- with a private event solely to exercise the independent reopen path.
insert into finance.period_events(id,tenant_id,legal_entity_id,period_id,action,from_state,to_state,period_version,
 reason,exceptions,actor_id,transaction_id)
values(pg_temp.fid('period.fixture.hard'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.period_id(),
 'hard_lock','soft_locked','hard_locked',(select version from finance.fiscal_periods where id=pg_temp.period_id()),
 'Synthetic hard state for reopen test','[]',pg_temp.fid('creator'),txid_current());
update finance.fiscal_periods set state='hard_locked',updated_by=pg_temp.fid('creator') where id=pg_temp.period_id();
insert into procurement_test_results select throws_ok($$select pg_temp.bank_journal('period.hard.post',1)$$,
 '55000','PERIOD_CLOSED','hard lock rejects ordinary posting');
insert into procurement_test_results select throws_ok($$select pg_temp.call('period_governance_command',
 pg_temp.period_payload('request_reopen','period.reopen.request'),
 (select version from finance.fiscal_periods where id=pg_temp.period_id()))$$,
 '42501','RECENT_MFA_REQUIRED','AAL2 without recent second-factor evidence is insufficient');
select pg_temp.period_actor('creator',901);
insert into procurement_test_results select throws_ok($$select pg_temp.call('period_governance_command',
 pg_temp.period_payload('request_reopen','period.reopen.request'),
 (select version from finance.fiscal_periods where id=pg_temp.period_id()))$$,
 '42501','RECENT_MFA_REQUIRED','stale MFA cannot request reopen');
select pg_temp.period_actor('creator');
insert into procurement_responses values('period.reopen.request',pg_temp.call('period_governance_command',
 pg_temp.period_payload('request_reopen','period.reopen.request'),
 (select version from finance.fiscal_periods where id=pg_temp.period_id())));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses where name='period.reopen.request'),
 'pending_approval','recent-MFA requester records immutable reopen request');
insert into procurement_test_results select throws_ok($$select pg_temp.call('period_governance_command',
 pg_temp.period_payload('approve_reopen','period.reopen.approval')||jsonb_build_object('request_id',pg_temp.fid('period.reopen.request')),
 (select version from finance.fiscal_periods where id=pg_temp.period_id()))$$,
 '42501','PERIOD_REOPEN_APPROVAL_INVALID','requester cannot approve own reopen');
select pg_temp.period_actor('approver');
insert into procurement_responses values('period.reopen.approval',pg_temp.call('period_governance_command',
 pg_temp.period_payload('approve_reopen','period.reopen.approval')||jsonb_build_object('request_id',pg_temp.fid('period.reopen.request')),
 (select version from finance.fiscal_periods where id=pg_temp.period_id())));
insert into procurement_test_results select is((select state from finance.fiscal_periods where id=pg_temp.period_id()),
 'open','independent recent-MFA approval reopens hard period');
insert into procurement_test_results select is((select r.requested_by<>ev.actor_id from finance.period_events ev
 join finance.period_reopen_requests r on r.id=ev.reopen_request_id where ev.id=pg_temp.fid('period.reopen.approval')),
 true,'reopen event preserves distinct requester and approver');
insert into procurement_test_results select is((select count(*) from finance.period_events where period_id=pg_temp.period_id()
 and action='hard_lock'),1::bigint,'reopen retains prior hard close event');
insert into procurement_test_results select throws_ok($$delete from finance.period_events
 where id=pg_temp.fid('period.reopen.approval')$$,'55000',null,'period events are immutable');
insert into procurement_test_results select throws_ok($$select pg_temp.call('period_governance_command',
 pg_temp.period_payload('approve_reopen','period.reopen.duplicate')||jsonb_build_object('request_id',pg_temp.fid('period.reopen.request')),
 3)$$,'40001','VERSION_CONFLICT','stale approval cannot reopen twice');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.period_governance_options(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'periods')$$,
 '42501',null,'outsider cannot read period governance');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.period_events$$,
 '42501',null,'period event table is private');
reset role;
