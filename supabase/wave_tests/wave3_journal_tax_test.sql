-- Governed withholding/input/output journal tax declaration. Rollback only.
select pg_temp.actor('creator');
set constraints all deferred;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.fid('tax.withholding.account'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'WITHHOLD','Withholding liability','liability','credit',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,kind,rate,inclusive,valid_from,created_by,updated_by)
values(pg_temp.fid('tax.withholding'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'WHT25','Configured withholding','withholding',25,false,'2026-01-01',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.tax_journal(n text) returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fid(n),'document_date','2026-09-20','currency_code','LKR',
 'reason','Configured tax accrual reviewed','description','Synthetic withholding accrual','attachment_ids','[]'::jsonb,
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(n||'.debit'),
  'account_id',pg_temp.fid('expense-account'),'debit','25','credit','0'),
 jsonb_build_object('line_id',pg_temp.fid(n||'.tax'),'account_id',pg_temp.fid('tax.withholding.account'),
  'debit','0','credit','25','tax_definition_id',pg_temp.fid('tax.withholding'),'taxable_amount','100')))$$;
insert into procurement_test_results select ok((select exists(select 1 from jsonb_array_elements(
 api.manual_journal_tax_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-20')->'items')x
 where x->>'id'=pg_temp.fid('tax.withholding')::text and x->>'rate'='25.000000')),
 'journal tax picker exposes effective configured withholding as an exact decimal');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 jsonb_set(pg_temp.tax_journal('tax.bad.number'),'{lines,1,taxable_amount}','100'),0)$$,
 '22023','taxable_amount must be a decimal string.','journal taxable basis rejects numeric coercion');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 jsonb_set(pg_temp.tax_journal('tax.bad.basis'),'{lines,1,taxable_amount}','"99"'),0)$$,
 '22023','JOURNAL_TAX_AMOUNT_INVALID','tax declaration rejects a one-quarter-unit treatment mismatch');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 jsonb_set(pg_temp.tax_journal('tax.bad.account'),'{lines,1,account_id}',to_jsonb(pg_temp.fid('expense-account'))),0)$$,
 '22023','JOURNAL_TAX_ACCOUNT_SIDE_INVALID','withholding requires a liability credit line');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 jsonb_set(pg_temp.tax_journal('tax.bad.definition'),'{lines,1,tax_definition_id}',to_jsonb(pg_temp.fid('tax.no.definition'))),0)$$,
 '55000','JOURNAL_TAX_DEFINITION_INVALID','unknown tax definition cannot be declared');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 pg_temp.tax_journal('tax.no.definition')||jsonb_build_object('lines',jsonb_build_array(
 pg_temp.tax_journal('tax.no.definition')#>'{lines,0}',(pg_temp.tax_journal('tax.no.definition')#>'{lines,1}')-'tax_definition_id')),0)$$,
 '22023','JOURNAL_TAX_DEFINITION_REQUIRED','a taxable basis cannot be silently stripped');
insert into procurement_responses values('tax.journal.saved',pg_temp.call('upsert_manual_journal',pg_temp.tax_journal('tax.journal'),0,'tax.journal.save'));
insert into procurement_test_results select is(pg_temp.call('upsert_manual_journal',pg_temp.tax_journal('tax.journal'),0,'tax.journal.save'),
 (select response from procurement_responses where name='tax.journal.saved'),'governed tax draft command replays exactly');
insert into procurement_test_results select is((select snapshot#>>'{lines,1,tax_direction}'
 from finance.manual_journals where id=pg_temp.fid('tax.journal')),'-1','withholding freezes credit-positive treatment direction');
insert into procurement_test_results select is((select snapshot#>>'{lines,1,tax_definition_version}'
 from finance.manual_journals where id=pg_temp.fid('tax.journal')),'1','tax declaration freezes the approved definition version');
select pg_temp.mj_act('tax.journal','{"action":"submit"}');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('tax.journal','{"decision":"approved"}')$$,
 '42501','SEGREGATION_OF_DUTIES_VIOLATION','tax preparer cannot approve the declaration');
select pg_temp.actor('approver','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('tax.journal','{"decision":"approved"}')$$,
 '42501',null,'tax declaration inherits configured MFA approval');
select pg_temp.actor('approver');
select pg_temp.mj_act('tax.journal','{"decision":"approved"}');
update finance.tax_definitions set rate=30 where id=pg_temp.fid('tax.withholding');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('tax.journal','{}','post_manual_journal')$$,
 '55000','JOURNAL_REAPPROVAL_REQUIRED','a changed tax definition invalidates previous approval');
insert into procurement_test_results select is((select count(*) from finance.journal_entries
 where source_type='manual_journal' and source_id=pg_temp.fid('tax.journal')),0::bigint,
 'failed tax revalidation leaves no posted journal');
update finance.tax_definitions set rate=25 where id=pg_temp.fid('tax.withholding');
-- Even restoring the rate creates a new immutable definition version.
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('tax.journal','{}','post_manual_journal')$$,
 '55000','JOURNAL_REAPPROVAL_REQUIRED','restoring a rate does not bypass version reapproval');
select pg_temp.actor('creator');
select pg_temp.mj_act('tax.journal','{"action":"recall","reason":"Tax definition version changed"}');
select pg_temp.call('upsert_manual_journal',pg_temp.tax_journal('tax.journal'),
 (select version from finance.manual_journals where id=pg_temp.fid('tax.journal')));
select pg_temp.mj_act('tax.journal','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('tax.journal','{"decision":"approved"}');
create trigger synthetic_tax_journal_failure before insert on core.outbox_events for each row execute function pg_temp.fail_manual_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('tax.journal','{}','post_manual_journal')$$,
 'P0001','MANUAL_OUTBOX_FAILURE','late tax journal failure rolls back posting and declaration state');
drop trigger synthetic_tax_journal_failure on core.outbox_events;
insert into procurement_test_results select is((select status from finance.manual_journals where id=pg_temp.fid('tax.journal')),
 'approved','late tax failure retains the approved declaration');
insert into procurement_test_results select is((select count(*) from finance.journal_entries
 where source_type='manual_journal' and source_id=pg_temp.fid('tax.journal')),0::bigint,
 'late tax failure leaves no orphan tax-control posting');
select pg_temp.mj_act('tax.journal','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_responses values('tax.withholding.review',pg_temp.tax_call('tax.withholding.review',
 jsonb_build_object('id',pg_temp.fid('tax.withholding.review'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,withholding_tax_base}'
 from procurement_responses where name='tax.withholding.review'),'25.000000','only posted governed declarations enter withholding totals');
insert into procurement_test_results select is((select value->>'difference' from jsonb_array_elements(
 api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.withholding.review'),'controls',0,pg_temp.fid('tax.withholding.account'))->'items')value),
 '0.000000','withholding source agrees with all posted liability control activity');
insert into procurement_test_results select is((select value->>'review_code' from jsonb_array_elements(
 api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.withholding.review'),0,pg_temp.fid('tax.journal.tax'))->'items')value),null,
 'posted withholding retains exact version and journal lineage');
update finance.tax_definitions set status='inactive',valid_to='2026-09-20' where id=pg_temp.fid('tax.withholding');
select pg_temp.call('upsert_manual_journal',pg_temp.tax_journal('tax.journal.reverse')||
 jsonb_build_object('document_date','2026-09-25','reversal_of_id',pg_temp.fid('tax.journal'),'lines','[]'::jsonb),0);
insert into procurement_test_results select is((select snapshot#>>'{lines,1,tax_direction}'
 from finance.manual_journals where id=pg_temp.fid('tax.journal.reverse')),'1','linked tax reversal negates the original credit direction');
insert into procurement_test_results select is((select snapshot#>>'{lines,1,tax_basis_date}'
 from finance.manual_journals where id=pg_temp.fid('tax.journal.reverse')),'2026-09-20','linked tax reversal preserves the original effective date');
select pg_temp.mj_act('tax.journal.reverse','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('tax.journal.reverse','{"decision":"approved"}');
select pg_temp.mj_act('tax.journal.reverse','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_responses values('tax.withholding.reversed',pg_temp.tax_call('tax.withholding.reversed',
 jsonb_build_object('id',pg_temp.fid('tax.withholding.reversed'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,withholding_tax_base}'
 from procurement_responses where name='tax.withholding.reversed'),'0.000000','posted linked tax reversal cancels exact withholding treatment');
insert into procurement_test_results select is((select response#>>'{entity,withholding_tax_base}'
 from procurement_responses where name='tax.withholding.review'),'25.000000','later reversal cannot mutate a frozen withholding report');
insert into procurement_test_results select is((select value->>'review_code' from jsonb_array_elements(
 api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.withholding.reversed'),0,pg_temp.fid('tax.journal.tax'))->'items')value
 where value->>'source_id'=pg_temp.fid('tax.journal.reverse')::text),null,
 'retired current rate cannot reclassify a linked posted tax reversal');
insert into procurement_test_results select throws_ok($$update finance.manual_journals
 set snapshot=jsonb_set(snapshot,'{lines,1,tax_rate}','"99"') where id=pg_temp.fid('tax.journal')$$,
 '55000','POSTED_DOCUMENT_IMMUTABLE','posted tax declaration cannot be rewritten');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.manual_journal_tax_options(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-20')$$,
 '42501',null,'tax choices deny nonmembers');
select pg_temp.actor('creator');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role')
 and permission_code='finance.journals.post';
insert into procurement_test_results select throws_ok($$select api.manual_journal_tax_options(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'2026-09-20')$$,
 '42501',null,'finance read alone does not permit tax declaration choices');
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.journals.post');

-- Non-base-currency tax uses the journal engine's six-place cumulative FX,
-- while its source tax calculation uses the entity's two-place tax precision.
insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,kind,rate,inclusive,valid_from,created_by,updated_by)
values(pg_temp.fid('tax.fx.definition'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'WHTFX','FX withholding','withholding',2.5,false,'2026-01-01',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_manual_journal',pg_temp.tax_journal('tax.fx.journal')||jsonb_build_object(
 'currency_code','USD','exchange_rate_id',pg_temp.fid('mj.rate'),'lines',jsonb_build_array(
 jsonb_set(pg_temp.tax_journal('tax.fx.journal')#>'{lines,0}','{debit}','"0.03"'),
 (pg_temp.tax_journal('tax.fx.journal')#>'{lines,1}')||jsonb_build_object(
 'credit','0.03','tax_definition_id',pg_temp.fid('tax.fx.definition'),'taxable_amount','1'))),0);
insert into procurement_test_results select is((select snapshot#>>'{lines,1,expected_tax_base}'
 from finance.manual_journals where id=pg_temp.fid('tax.fx.journal')),'0.037037',
 'tax declaration preserves the existing six-place FX allocation after half-cent source rounding');
select pg_temp.mj_act('tax.fx.journal','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('tax.fx.journal','{"decision":"approved"}');
select pg_temp.mj_act('tax.fx.journal','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_responses values('tax.fx.review',pg_temp.tax_call('tax.fx.review',
 jsonb_build_object('id',pg_temp.fid('tax.fx.review'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,withholding_tax_base}'
 from procurement_responses where name='tax.fx.review'),'0.037037',
 'withholding summary uses exact posted base allocation rather than re-rounding FX');
insert into procurement_test_results select is((select value->>'currency_code' from jsonb_array_elements(
 api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.fx.review'),0,pg_temp.fid('tax.fx.journal.tax'))->'items')value),'USD',
 'FX withholding evidence retains the source currency');

insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,kind,rate,inclusive,valid_from,created_by,updated_by)
select pg_temp.fid('tax.manual.'||kind),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'MANUAL'||upper(kind),'Manual '||kind,kind,10,false,'2026-01-01',pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['input','output'])kind;
select pg_temp.call('upsert_manual_journal',pg_temp.tax_journal('tax.manual.output')||jsonb_build_object('lines',jsonb_build_array(
 jsonb_set(pg_temp.tax_journal('tax.manual.output')#>'{lines,0}','{debit}','"10"'),
 (pg_temp.tax_journal('tax.manual.output')#>'{lines,1}')||jsonb_build_object(
 'credit','10','tax_definition_id',pg_temp.fid('tax.manual.output')))),0);
select pg_temp.call('upsert_manual_journal',pg_temp.tax_journal('tax.manual.input')||jsonb_build_object('lines',jsonb_build_array(
 (pg_temp.tax_journal('tax.manual.input')#>'{lines,0}')||jsonb_build_object('debit','0','credit','10'),
 (pg_temp.tax_journal('tax.manual.input')#>'{lines,1}')||jsonb_build_object('account_id',pg_temp.fid('input-tax-account'),
 'debit','10','credit','0','tax_definition_id',pg_temp.fid('tax.manual.input')))),0);
select pg_temp.mj_act('tax.manual.input','{"action":"submit"}');
select pg_temp.mj_act('tax.manual.output','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('tax.manual.input','{"decision":"approved"}');
select pg_temp.mj_act('tax.manual.output','{"decision":"approved"}');
select pg_temp.mj_act('tax.manual.input','{}','post_manual_journal');
select pg_temp.mj_act('tax.manual.output','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_responses values('tax.manual.treatments',pg_temp.tax_call('tax.manual.treatments',
 jsonb_build_object('id',pg_temp.fid('tax.manual.treatments'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select (response#>>'{entity,input_tax_base}')::numeric
 from procurement_responses where name='tax.manual.treatments')-(select (response#>>'{entity,input_tax_base}')::numeric
 from procurement_responses where name='tax.fx.review'),10::numeric,
 'governed input tax contributes only its posted asset debit');
insert into procurement_test_results select is((select response#>>'{entity,output_tax_base}'
 from procurement_responses where name='tax.manual.treatments'),'10.000000',
 'governed output tax is separated from withholding on the same liability account');
insert into procurement_test_results select is((select value->>'tax_direction' from jsonb_array_elements(
 api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.manual.treatments'),0,pg_temp.fid('tax.manual.input.tax'))->'items')value),'1',
 'tax source evidence exposes exact input treatment direction');
insert into procurement_test_results select is((select value->>'difference' from jsonb_array_elements(
 api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.manual.treatments'),'controls',0,pg_temp.fid('tax.withholding.account'))->'items')value),
 '0.000000','separate output and withholding declarations reconcile to their complete shared liability GL');
