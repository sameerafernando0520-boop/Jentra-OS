-- Cumulative control-account and posted purchase-return evidence. Rollback only.
select pg_temp.actor('creator');
insert into procurement_test_results select has_function('api','tax_control_page',
 array['uuid','uuid','uuid','uuid','text','integer','uuid','text'],
 'tax control evidence has a scoped bounded public page');
select pg_temp.call('post_purchase_return',
 pg_temp.purchase_return('tax.input.return','tax.future.bill','tax.future.bill.line','1'));
insert into procurement_test_results select is((select detail->>'expected_tax_base'
 from procurement.purchase_return_lines where id=pg_temp.fid('tax.input.return.line')),
 '22.530000','purchase return freezes cumulative-rounded original tax base');
insert into procurement_test_results select is((select detail->>'tax_basis_date'
 from procurement.purchase_return_lines where id=pg_temp.fid('tax.input.return.line')),
 '2026-09-13','purchase return preserves original bill tax date');
insert into procurement_responses values('tax.return.review',pg_temp.tax_call('tax.return.review',
 jsonb_build_object('id',pg_temp.fid('tax.return.review'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,input_tax_base}'
 from procurement_responses where name='tax.return.review'),'22.520000',
 'purchase return reduces input tax after current definition changes');
insert into procurement_test_results select is((select value->>'review_code'
 from jsonb_array_elements(api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('tax.return.review'),0,pg_temp.fid('tax.input.return.line'))->'items')value),
 null,'posted return uses its immutable original definition version');
insert into procurement_test_results select is((select value->>'expected_base'
 from jsonb_array_elements(api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.return.review'),'control_sources',0,pg_temp.fid('input-tax-account'),
 'purchase_return:'||pg_temp.fid('tax.input.return')||':'||pg_temp.fid('tax.input.return.line'))->'items')value),
 '-22.530000','input-tax credit drills to an exact signed control source');
insert into procurement_test_results select ok((select
 (response#>>'{entity,control_unassigned_source_count}')::integer>0
 from procurement_responses where name='tax.return.review'),
 'missing journal is visible as an unassigned control source');
insert into procurement_test_results select is((select value->>'difference'
 from jsonb_array_elements(api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.return.review'),'controls',0,pg_temp.fid('input-tax-account'),null)->'items')value),
 '0.000000','posted input-tax control agrees with cumulative supported source amounts');

select finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),
 'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),'document_date','2026-09-16',
 'currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('input-tax-account'),0.01,0.01),
 finance.flow_jline(pg_temp.fid('expense-account'),-0.01,-0.01)),
 'manual_tax',pg_temp.fid('tax.manual'),pg_temp.fid('tax.manual.request'),pg_temp.fid('tax.manual.command'));
insert into procurement_responses values('tax.manual.review',pg_temp.tax_call('tax.manual.review',
 jsonb_build_object('id',pg_temp.fid('tax.manual.review'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select ok((select
 (response#>>'{entity,unattributed_journal_count}')::integer>0
 from procurement_responses where name='tax.manual.review'),
 'manual tax-control journal is not silently omitted');
insert into procurement_test_results select is((select value->>'difference'
 from jsonb_array_elements(api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.manual.review'),'controls',0,pg_temp.fid('input-tax-account'),null)->'items')value),
 '-0.010000','one-cent unattributed tax posting is an exact control difference');
insert into procurement_test_results select is((select value->>'difference'
 from jsonb_array_elements(api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.return.review'),'controls',0,pg_temp.fid('input-tax-account'),null)->'items')value),
 '0.000000','later manual posting cannot change a frozen control report');
insert into procurement_test_results select is((select value->>'source_type'
 from jsonb_array_elements(api.tax_control_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.manual.review'),'control_journals',0,pg_temp.fid('input-tax-account'),null)->'items')value
 where value->>'source_id'=pg_temp.fid('tax.manual')::text),'manual_tax',
 'unattributed difference retains its posted journal source');
insert into procurement_test_results select throws_ok($$select api.tax_control_page(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('tax.other.branch'),pg_temp.fid('tax.manual.review'),'controls')$$,
 '42501','TAX_REPORT_SCOPE_REQUIRED','another branch cannot inspect saved tax controls');
insert into procurement_test_results select throws_ok($$select api.tax_control_page(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('tax.manual.review'),'controls',10001)$$,
 '22023','TAX_CONTROL_PAGE_INVALID','tax control page rejects oversized offset');

insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,rate,kind,inclusive,valid_from,valid_to,created_by,updated_by)
values(pg_temp.fid('tax.expiring'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'EXPIRE18','Original dated input treatment',18,'input',false,'2026-01-01','2026-09-13',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_supplier_bill',jsonb_set(pg_temp.direct_bill('tax.expiring.bill'),
 '{lines,0,tax_definition_id}',to_jsonb(pg_temp.fid('tax.expiring'))));
select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('tax.expiring.bill')),1);
select pg_temp.call('post_purchase_return',pg_temp.purchase_return('tax.expiring.return','tax.expiring.bill','tax.expiring.bill.line','1'));
insert into procurement_responses values('tax.expired.review',pg_temp.tax_call('tax.expired.review',
 jsonb_build_object('id',pg_temp.fid('tax.expired.review'),'period_id',pg_temp.fid('period'),'as_of','2026-09-25')));
insert into procurement_test_results select is((select value->>'review_code'
 from jsonb_array_elements(api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.expired.review'),0,pg_temp.fid('tax.expiring.return.line'))->'items')value),null,
 'later return validates definition at original tax date rather than return date');
insert into procurement_test_results select is((select value->>'tax_basis_date'
 from jsonb_array_elements(api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.expired.review'),0,pg_temp.fid('tax.expiring.return.line'))->'items')value),'2026-09-13',
 'return evidence exposes original effective-date basis');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.tax_control_page(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('tax.manual.review'),'controls')$$,
 '42501',null,'unpermitted actor cannot access tax-control ledger evidence');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.tax_posted_sources(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),'2026-09-25')$$,'42501',null,
 'private cumulative tax-source helper cannot bypass API scope');
reset role;

-- An ended period containing only an undeclared mapped tax-control posting
-- must still fail its tax review, even without a tax-defined source document.
insert into core.legal_entities(id,tenant_id,name,code,currency_code,rounding_scale,created_by)
values(pg_temp.fid('tax.close.entity'),pg_temp.fid('tenant'),'Tax close fixture','TAXCLOSE','LKR',2,pg_temp.fid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('tax.close.branch'),pg_temp.fid('tenant'),pg_temp.fid('tax.close.entity'),
 'Tax close branch','TAXCLOSE',pg_temp.fid('creator'));
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('creator.role'),
 pg_temp.fid('tax.close.entity'),null,pg_temp.fid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid('tax.close.'||x),pg_temp.fid('tenant'),pg_temp.fid('tax.close.entity'),upper(x),x,
 case when x='output' then 'liability' else 'expense' end,
 case when x='output' then 'credit' else 'debit' end,pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['output','expense'])x;
insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('tax.close.entity'),'output_tax',
 pg_temp.fid('tax.close.output'),pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.fid('tax.close.period'),pg_temp.fid('tenant'),pg_temp.fid('tax.close.entity'),'Tax August',
 '2026-08-01','2026-08-31',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('tax.close.entity'),pg_temp.fid('tax.close.branch'),
 'journal_entry','TAXJE-',pg_temp.fid('creator'),pg_temp.fid('creator'));
select finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),
 'legal_entity_id',pg_temp.fid('tax.close.entity'),'branch_id',pg_temp.fid('tax.close.branch'),
 'document_date','2026-08-16','currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('tax.close.expense'),0.01,0.01),
 finance.flow_jline(pg_temp.fid('tax.close.output'),-0.01,-0.01)),
 'manual_tax',pg_temp.fid('tax.close.source'),gen_random_uuid(),gen_random_uuid());
insert into procurement_responses select 'tax.close.exceptions',finance.period_close_exceptions(
 pg_temp.fid('tenant'),pg_temp.fid('tax.close.entity'),p)
from finance.fiscal_periods p where p.id=pg_temp.fid('tax.close.period');
insert into procurement_test_results select is((select count(*) from procurement_responses,
 jsonb_array_elements(response)x where name='tax.close.exceptions' and x->>'code'='TAX_REVIEW_BLOCKED'),
 1::bigint,'close exceptions include undeclared mapped tax-control activity without tax sources');
insert into procurement_test_results select is((select count(*) from procurement_responses,
 jsonb_array_elements(response)x where name='tax.close.exceptions' and x->>'code'='TAX_REVIEW_CHECK_FAILED'),
 0::bigint,'close tax evidence is a real exact difference rather than a swallowed query failure');
insert into procurement_test_results select is((select count(*) from finance.tax_reports
 where legal_entity_id=pg_temp.fid('tax.close.entity')),0::bigint,
 'close preview does not create a report or persistent review command');
