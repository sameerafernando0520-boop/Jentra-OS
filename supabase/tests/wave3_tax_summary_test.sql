-- Legacy tax lines are deliberately not silently certified. All fixtures roll back.
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.view') on conflict do nothing;
insert into procurement_test_results select has_table('finance','tax_definition_versions',
 'tax definition versions retain immutable effective-date snapshots');
insert into procurement_test_results select has_function('api','generate_tax_summary',
 array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],
 'permission-scoped tax summary command exists');
insert into procurement_test_results select is((select version from finance.tax_definition_versions
 where tenant_id=pg_temp.fid('tenant') and definition_id=pg_temp.fid('input-tax')),1::bigint,
 'current Wave 2 definition is captured on candidate installation');
insert into procurement_test_results select is((select detail->>'tax_definition_version'
 from procurement.supplier_bill_lines where id=pg_temp.fid('direct-bill.line')),null,
 'pre-candidate posted bill lacks provable tax definition version');

create function pg_temp.tax_call(n text,p jsonb) returns jsonb language sql as $$
 select api.generate_tax_summary(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid(n||'.command'),pg_temp.fid(n||'.key'),
 '2026-09-26T00:00:00Z',p,0)$$;
insert into procurement_responses values('tax.legacy',pg_temp.tax_call('tax.legacy',
 jsonb_build_object('id',pg_temp.fid('tax.legacy'),'period_id',pg_temp.fid('period'),
 'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,status}'
 from procurement_responses where name='tax.legacy'),'blocked',
 'legacy bill with no posting-time definition version blocks tax certification');
insert into procurement_test_results select is((select response#>>'{entity,notice}'
 from procurement_responses where name='tax.legacy'),
 'NON-CERTIFIED • STATUTORY REVIEW REQUIRED',
 'tax report always carries explicit statutory review notice');
insert into procurement_test_results select ok((select (response#>>'{entity,blocked_count}')::integer>0
 from procurement_responses where name='tax.legacy'),
 'legacy tax review counts unsupported provenance');
insert into procurement_test_results select is((
 select value->>'review_code' from jsonb_array_elements(api.tax_summary_page(
  pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
  pg_temp.fid('tax.legacy'),0,null)->'items') value
 where value->>'source_line_id'=pg_temp.fid('direct-bill.line')::text),
 'MISSING_DEFINITION_VERSION','legacy line exposes its exact review reason and source identity');
insert into procurement_test_results select ok((
 select (response#>>'{entity,unverified_tax_base}')::numeric>=45.05
 from procurement_responses where name='tax.legacy'),
 'unverified posted tax stays outside certified treatment totals');
insert into procurement_test_results select is(pg_temp.tax_call('tax.legacy',
 jsonb_build_object('id',pg_temp.fid('tax.legacy'),'period_id',pg_temp.fid('period'),
 'as_of','2026-09-25')),(select response from procurement_responses where name='tax.legacy'),
 'tax report replay retains original frozen receipt');
insert into procurement_test_results select is((select jsonb_array_length(
 api.tax_summary_reports(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->'items')),
 1,'requesting branch can list its own frozen tax summary');

select pg_temp.call('upsert_supplier_bill',pg_temp.direct_bill('tax.future.bill'));
insert into procurement_test_results select is((select detail->>'tax_kind'
 from procurement.supplier_bill_lines where id=pg_temp.fid('tax.future.bill.line')),
 'input','new draft bill captures source tax treatment');
insert into procurement_test_results select is((select detail->>'tax_definition_version'
 from procurement.supplier_bill_lines where id=pg_temp.fid('tax.future.bill.line')),
 '1','new bill captures effective definition version');
select pg_temp.call('post_supplier_bill',
 jsonb_build_object('document_id',pg_temp.fid('tax.future.bill')),1);
insert into procurement_test_results select is((select detail->>'tax_kind'
 from procurement.supplier_bill_lines where id=pg_temp.fid('tax.future.bill.line')),
 'input','posted bill freezes the versioned input treatment');
insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,rate,kind,
 inclusive,valid_from,created_by,updated_by)
values(pg_temp.fid('tax.zero.definition'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'ZERO0','Synthetic zero treatment',0,'zero',false,'2026-01-01',
 pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_supplier_bill',jsonb_set(pg_temp.direct_bill('tax.zero.bill'),
 '{lines,0,tax_definition_id}',to_jsonb(pg_temp.fid('tax.zero.definition'))));
select pg_temp.call('post_supplier_bill',
 jsonb_build_object('document_id',pg_temp.fid('tax.zero.bill')),1);
insert into procurement_responses values('tax.prospective',pg_temp.tax_call('tax.prospective',
 jsonb_build_object('id',pg_temp.fid('tax.prospective'),'period_id',pg_temp.fid('period'),
 'as_of','2026-09-25')));
insert into procurement_test_results select is((select response#>>'{entity,input_tax_base}'
 from procurement_responses where name='tax.prospective'),'45.050000',
 'versioned posted input tax reconciles to its journal asset debit');
insert into procurement_test_results select is((select response#>>'{entity,zero_taxable_base}'
 from procurement_responses where name='tax.prospective'),'250.250000',
 'zero-rated posted source line contributes taxable basis without inventing a tax journal');
insert into procurement_test_results select is((select value->>'review_code'
 from jsonb_array_elements(api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('tax.prospective'),0,
 pg_temp.fid('tax.future.bill.line'))->'items') value),null,
 'prospective posted input line has no provenance blocker');
insert into procurement_test_results select is((select value->>'tax_kind'
 from jsonb_array_elements(api.tax_summary_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('tax.prospective'),0,
 pg_temp.fid('tax.zero.bill.line'))->'items') value),'zero',
 'zero-rated treatment is explicit in line drill');
update finance.tax_definitions set rate=19 where id=pg_temp.fid('input-tax');
insert into procurement_test_results select is((select count(*) from finance.tax_definition_versions
 where definition_id=pg_temp.fid('input-tax')),2::bigint,
 'definition edit preserves both immutable effective-date versions');
insert into procurement_test_results select is((select rate from finance.tax_definition_versions
 where definition_id=pg_temp.fid('input-tax') and version=1),18::numeric,
 'historical definition rate is not rewritten by Wave 2 setup edit');
insert into procurement_test_results select is((select summary->>'status' from finance.tax_reports
 where id=pg_temp.fid('tax.legacy')),'blocked',
 'later definition edit cannot rewrite frozen tax review outcome');
insert into procurement_test_results select throws_ok($$delete from finance.tax_reports
 where id=pg_temp.fid('tax.legacy')$$,'55000',null,'tax report evidence is immutable');
insert into procurement_test_results select throws_ok($$delete from finance.tax_definition_versions
 where definition_id=pg_temp.fid('input-tax')$$,'55000',null,
 'effective-dated definition history is immutable');

insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
values(pg_temp.fid('tax.other.branch'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'Tax review other branch','TAX-B',pg_temp.fid('creator'));
insert into procurement_test_results select is((select jsonb_array_length(
 api.tax_summary_reports(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('tax.other.branch'))->'items')),0,
 'another permitted branch cannot list this branch report');
insert into procurement_test_results select throws_ok($$select api.tax_summary_page(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('tax.other.branch'),
 pg_temp.fid('tax.legacy'),0,null)$$,'42501','TAX_REPORT_SCOPE_REQUIRED',
 'another branch cannot read frozen tax line evidence');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.tax_summary_page(
 pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid('tax.legacy'),0,null)$$,'42501',null,
 'unpermitted actor cannot read tax report');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.tax_reports$$,
 '42501',null,'direct authenticated tax evidence read is denied');
reset role;
