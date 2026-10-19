-- Governed control-only movements preserve treatment totals. Rollback only.
select pg_temp.actor('creator');
create function pg_temp.tax_movement(n text) returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fid(n),'document_date','2026-09-25','currency_code','LKR',
 'reason','Reviewed tax settlement entry','description','Synthetic recorded tax settlement',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(n||'.control'),
 'account_id',pg_temp.fid('tax.withholding.account'),'debit','10.037037','credit','0',
 'tax_control_movement','settlement'),jsonb_build_object('line_id',pg_temp.fid(n||'.cash'),
 'account_id',pg_temp.fid('payment-cash-gl'),'debit','0','credit','10.037037')))$$;
insert into procurement_test_results select ok((select exists(select 1 from jsonb_array_elements(
 api.manual_journal_tax_controls(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->'items')x
 where x->>'id'=pg_temp.fid('tax.withholding.account')::text and (x->>'is_tax_control')::boolean)),
 'tax-control picker retains an account proven by a retired withholding definition');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 jsonb_set(pg_temp.tax_movement('tax.bad.movement'),'{lines,0,tax_control_movement}','"other"'),0)$$,
 '22023','JOURNAL_TAX_MOVEMENT_INVALID','unknown tax-control movement cannot be silently stripped');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 jsonb_set(pg_temp.tax_movement('tax.bad.control'),'{lines,0,account_id}',to_jsonb(pg_temp.fid('payment-cash-gl'))),0)$$,
 '55000','JOURNAL_TAX_CONTROL_UNPROVEN','a cash account cannot be relabelled as a tax control');
select pg_temp.call('upsert_manual_journal',pg_temp.tax_movement('tax.settlement'),0);
insert into procurement_test_results select is((select snapshot#>>'{lines,0,expected_tax_base}'
 from finance.manual_journals where id=pg_temp.fid('tax.settlement')),'10.037037',
 'settlement freezes exact six-place source base independent of a tax rate');
select pg_temp.mj_act('tax.settlement','{"action":"submit"}');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('tax.settlement','{"decision":"approved"}')$$,
 '42501','SEGREGATION_OF_DUTIES_VIOLATION','tax-control settlement requires independent approval');
select pg_temp.actor('approver');
select pg_temp.mj_act('tax.settlement','{"decision":"approved"}');
create trigger synthetic_tax_movement_failure before insert on core.outbox_events
 for each row execute function pg_temp.fail_manual_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('tax.settlement','{}','post_manual_journal')$$,
 'P0001','MANUAL_OUTBOX_FAILURE','late settlement failure rolls back the control ledger');
drop trigger synthetic_tax_movement_failure on core.outbox_events;
insert into procurement_test_results select is((select count(*) from finance.journal_entries
 where source_type='manual_journal' and source_id=pg_temp.fid('tax.settlement')),0::bigint,
 'late settlement failure leaves no orphan journal');
select pg_temp.mj_act('tax.settlement','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_responses values('tax.settled.review',pg_temp.tax_call('tax.settled.review',
 jsonb_build_object('id',pg_temp.fid('tax.settled.review'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,withholding_tax_base}'
 from procurement_responses where name='tax.settled.review'),'0.037037',
 'settlement does not reduce the period withholding accrual');
insert into procurement_test_results select is((select response#>>'{entity,output_tax_base}'
 from procurement_responses where name='tax.settled.review'),'10.000000',
 'settlement does not reduce the period output tax accrual');
insert into procurement_test_results select is((select value->>'gl_closing_base' from jsonb_array_elements(
 api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.settled.review'),'controls',0,pg_temp.fid('tax.withholding.account'))->'items')value),
 '0.000000','recorded settlement clears the exact tax liability control balance');
insert into procurement_test_results select is((select value->>'difference' from jsonb_array_elements(
 api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.settled.review'),'controls',0,pg_temp.fid('tax.withholding.account'))->'items')value),
 '0.000000','settlement source independently reconciles the complete liability GL');
insert into procurement_test_results select is((select value->>'tax_control_movement' from jsonb_array_elements(
 api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.settled.review'),'control_sources',0,pg_temp.fid('tax.withholding.account'),
 'manual_journal:'||pg_temp.fid('tax.settlement')||':'||pg_temp.fid('tax.settlement.control'))->'items')value),
 'settlement','control source drill names the governed settlement operation');
select pg_temp.call('upsert_manual_journal',pg_temp.tax_movement('tax.settlement.reverse')||jsonb_build_object(
 'reversal_of_id',pg_temp.fid('tax.settlement'),'lines','[]'::jsonb),0);
select pg_temp.mj_act('tax.settlement.reverse','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('tax.settlement.reverse','{"decision":"approved"}');
select pg_temp.mj_act('tax.settlement.reverse','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_responses values('tax.settlement.reversed',pg_temp.tax_call('tax.settlement.reversed',
 jsonb_build_object('id',pg_temp.fid('tax.settlement.reversed'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,withholding_tax_base}'
 from procurement_responses where name='tax.settlement.reversed'),'0.037037',
 'settlement reversal restores the liability without changing withholding accrual');
insert into procurement_test_results select is((select value->>'gl_closing_base' from jsonb_array_elements(
 api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.settlement.reversed'),'controls',0,pg_temp.fid('tax.withholding.account'))->'items')value),
 '-10.037037','linked settlement reversal restores the original exact liability balance');
insert into procurement_test_results select is((select value->>'gl_closing_base' from jsonb_array_elements(
 api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.settled.review'),'controls',0,pg_temp.fid('tax.withholding.account'))->'items')value),
 '0.000000','settlement reversal cannot rewrite a saved control snapshot');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.manual_journal_tax_controls(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))$$,'42501',null,
 'tax-control choices deny unpermitted actors');
select pg_temp.actor('creator');
