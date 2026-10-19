insert into procurement_test_results select has_function('core','wave3_source_descriptor','allowlisted source catalogue');
insert into procurement_test_results select has_function('core','wave3_source_header','actual-source access check');
insert into procurement_test_results select has_function('core','wave3_document_rows','bounded filtered source rows');
insert into procurement_test_results select has_function('api','wave3_document_page','current operational page');
insert into procurement_test_results select has_function('api','wave3_document_evidence','permission-scoped source evidence');
insert into procurement_test_results select has_function('api','generate_operational_report','frozen operational report command');
insert into procurement_test_results select has_function('api','operational_report_page','frozen operational report page');
insert into procurement_test_results select has_function('api','wave3_dashboard','capability-aware dashboard read');
insert into procurement_test_results select has_table('core','operational_reports','private immutable operational reports');
insert into procurement_test_results select has_function('finance','build_branch_cash_controls','scoped bank report basis');
insert into procurement_test_results select has_function('core','wave3_attachment_access','source-bound file access');
insert into procurement_test_results select has_function('core','wave3_storage_access','private Storage source check');
insert into procurement_test_results select has_function('api','reject_wave3_attachment','audited file rejection');
insert into procurement_test_results select is((select count(*)::bigint from unnest(array[
 'lead','opportunity','quotation','sales_order','delivery','sales_invoice','customer_receipt','sales_return',
 'purchase_requisition','rfq','purchase_order','goods_receipt','supplier_bill','payment_proposal','supplier_payment',
 'purchase_return','inventory_transfer','stock_count','inventory_value_adjustment','manual_journal','budget',
 'bank_statement','bank_match']) k
 cross join lateral (select core.wave3_source_descriptor(k) d) x
 where x.d is null or to_regclass(format('%I.%I',x.d->>'schema',x.d->>'table')) is null),0::bigint,
 'every allowlisted source resolves to a candidate table');
insert into procurement_test_results select is((select count(*)::bigint from unnest(array[
 'quotation','sales_order','delivery','sales_invoice','customer_receipt','sales_return',
 'purchase_requisition','rfq','purchase_order','goods_receipt','supplier_bill','purchase_return',
 'inventory_transfer','stock_count','bank_statement']) k
 cross join lateral (select core.wave3_source_descriptor(k) d) x
 where x.d->>'child' is not null and
  (to_regclass(format('%I.%I',x.d->>'schema',x.d->>'child')) is null or
   not exists(select 1 from pg_attribute a where a.attrelid=to_regclass(format('%I.%I',x.d->>'schema',x.d->>'child'))
    and a.attname=x.d->>'parent' and a.attnum>0 and not a.attisdropped))),0::bigint,
 'every child link resolves to a real source foreign-key column');
-- Fixture-only behavior assertions. The structural smoke builder stops above.
select pg_temp.actor('creator');
insert into procurement_test_results select ok(exists(
 select 1 from finance.control_account_basis basis where basis.tenant_id=pg_temp.fid('tenant')
 and basis.legal_entity_id=pg_temp.fid('entity') and basis.kind='AP'
 and basis.account_id=pg_temp.fid('ap-account') and basis.source_type='future_mapping_new'),
 'supplier control configuration appends a typed AP basis observation');
insert into procurement_test_results select throws_ok($$update procurement.supplier_bill_controls
 set payable_account_id=pg_temp.fid('input-tax-account') where tenant_id=pg_temp.fid('tenant')
 and legal_entity_id=pg_temp.fid('entity')$$,'22023','CONTROL_ACCOUNT_TYPE_INVALID',
 'historical basis trigger rejects an asset as a new AP control');
create function pg_temp.operational_page(kind text,filters jsonb default '{}') returns jsonb language sql as $$
 select api.wave3_document_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),kind,filters)$$;
create function pg_temp.operational_evidence(kind text,id uuid) returns jsonb language sql as $$
 select api.wave3_document_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),kind,id)$$;
insert into procurement_test_results select ok(jsonb_array_length(pg_temp.operational_page('supplier_bill')->'items')>0,
 'current supplier bill list reads actual scoped documents');
insert into procurement_test_results select is(pg_temp.operational_evidence('supplier_bill',pg_temp.fid('bill'))#>>'{header,id}',
 pg_temp.fid('bill')::text,'known supplier bill drill-through resolves immutable source identity');
insert into procurement_test_results select ok(jsonb_array_length(pg_temp.operational_evidence('supplier_bill',pg_temp.fid('bill'))->'items')>0,
 'supplier bill drill-through pages real line records');
insert into procurement_test_results select is(
 pg_temp.operational_evidence('inventory_value_adjustment',pg_temp.fid('landed.adjust'))#>>'{header,receipt_id}',
 pg_temp.fid('landed.receipt')::text,
 'landed-value contextual link resolves the parent goods-receipt document from its movement line');
insert into procurement_test_results select throws_ok($$select pg_temp.operational_evidence('supplier_bill',pg_temp.fid('unknown'))$$,
 '42501','SOURCE_UNAVAILABLE','unknown source ID has uniform unavailable result');
insert into procurement_test_results select throws_ok($$select pg_temp.operational_page('supplier_bill','{"sql":"select secret"}')$$,
 '22023','DOCUMENT_FILTER_INVALID','current list rejects arbitrary filter fields');
insert into procurement_test_results select throws_ok($$select pg_temp.operational_page('arbitrary_table')$$,
 '22023','DOCUMENT_FILTER_INVALID','current list rejects arbitrary table names');
insert into procurement_test_results select is(pg_temp.operational_page('supplier_bill')#>>'{basis}','current',
 'operational list never claims dated historical state');
insert into procurement_test_results select ok(jsonb_array_length(api.wave3_dashboard(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'))->'cards')>0,'dashboard returns actual permission-scoped queues');
insert into procurement_test_results select throws_ok($$select api.wave3_document_evidence(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),'supplier_bill',pg_temp.fid('bill'),pg_temp.fid('unknown'))$$,
 '22023',null,'invalid source line cursor fails closed');
create function pg_temp.generate_operational(kind text,id text,more jsonb default '{}') returns jsonb language sql as $$
 select api.generate_operational_report(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 pg_temp.fid(id||'.command'),pg_temp.fid(id||'.key'),statement_timestamp(),
 jsonb_build_object('id',pg_temp.fid(id),'kind',kind,'as_of',(statement_timestamp() at time zone 'UTC')::date)||more,0)$$;
create temp table operational_result as select pg_temp.generate_operational('current_list','operational.bills',
 jsonb_build_object('document_kind','supplier_bill','filters','{}'::jsonb)) body;
insert into procurement_test_results select is((select body#>>'{entity,id}' from operational_result),pg_temp.fid('operational.bills')::text,
 'current list report is an attributable command');
insert into procurement_test_results select ok((select evidence#>>'{summary,row_count}' from core.operational_reports
 where id=pg_temp.fid('operational.bills'))::integer>0,'frozen operational report stores complete source rows');
insert into procurement_test_results select is(api.operational_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('operational.bills'))#>>'{summary,basis}','current',
 'frozen current list page declares its true basis');
insert into procurement_test_results select is(((api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),'operational',pg_temp.fid('operational.bills'),'rows','{}')->>'canonical_text')::jsonb#>>
 '{metadata,source_id}'),pg_temp.fid('operational.bills')::text,'governed export retains frozen report identity');
insert into procurement_test_results select throws_ok($$select api.report_export_preview(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),'operational',pg_temp.fid('operational.bills'),'rows','{"sql":"unsafe"}')$$,
 '22023','REPORT_EXPORT_FILTER_INVALID','operational export cannot accept arbitrary filters');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role')
 and permission_code='procurement.bills.view';
insert into procurement_test_results select throws_ok($$select pg_temp.operational_evidence('supplier_bill',pg_temp.fid('bill'))$$,
 '42501','SOURCE_UNAVAILABLE','known source rechecks revoked document access');
insert into procurement_test_results select throws_ok($$select api.operational_report_page(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('operational.bills'))$$,
 '42501',null,'frozen report cannot bypass revoked source access');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'procurement.bills.view');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select pg_temp.operational_evidence('supplier_bill',pg_temp.fid('bill'))$$,
 '42501','SOURCE_UNAVAILABLE','outsider gets the same unavailable source state');
insert into procurement_test_results select throws_ok($$select api.operational_report_page(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('operational.bills'))$$,
 '42501',null,'outsider cannot read a saved operational report');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select count(*) from core.operational_reports$$,
 '42501',null,'direct authenticated read cannot enumerate private frozen reports');
reset role;

select pg_temp.generate_operational('supplier_statement','operational.ap',jsonb_build_object(
 'party_id',pg_temp.fid('supplier_b'),'currency_code','LKR','as_of','2026-09-13'));
insert into procurement_test_results select is((select evidence#>>'{summary,open_amount}' from core.operational_reports
 where id=pg_temp.fid('operational.ap')),api.supplier_statement(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('supplier_b'),'LKR','2026-09-13')->>'open_amount',
 'frozen supplier statement exactly matches authoritative dated residuals with default aging buckets');
insert into procurement_test_results select throws_ok($$select pg_temp.generate_operational('current_list','operational.past',
 jsonb_build_object('document_kind','supplier_bill','as_of','2026-09-01'))$$,'22023',
 'CURRENT_LIST_HAS_NO_HISTORICAL_BASIS','current list cannot pretend to reconstruct a past cutoff');
insert into procurement_test_results select throws_ok($$select api.operational_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),pg_temp.fid('operational.ap'),'rows',null)$$,'22023','OPERATIONAL_REPORT_PAGE_INVALID',
 'null cursor cannot silently produce a partial statement');
insert into core.roles(id,tenant_id,code,name) values(pg_temp.fid('operational.files.role'),pg_temp.fid('tenant'),
 'operational_fixture_files','Synthetic file manager');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.fid('tenant'),pg_temp.fid('operational.files.role'),p from unnest(array['core.files.view','core.files.manage'])p;
insert into core.role_assignments(tenant_id,membership_id,role_id,created_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('operational.files.role'),pg_temp.fid('creator'));
create function pg_temp.operational_file_payload() returns jsonb language sql as $$select jsonb_build_object(
 'aggregate_type','supplier_bill','aggregate_id',pg_temp.fid('bill'),'file_name','supplier-evidence.pdf',
 'mime_type','application/pdf','byte_size',100)$$;
insert into procurement_responses values('operational.file.register',api.register_attachment(pg_temp.fid('tenant'),
 pg_temp.operational_file_payload(),pg_temp.fid('operational.file.key')));
create function pg_temp.operational_file_id() returns uuid language sql as $$
 select (response#>>'{entity,id}')::uuid from procurement_responses where name='operational.file.register'$$;
create function pg_temp.operational_file_path() returns text language sql as $$
 select response#>>'{entity,object_path}' from procurement_responses where name='operational.file.register'$$;
grant select on procurement_responses to authenticated;
set local role authenticated;
insert into procurement_test_results select is((select count(*) from core.attachments where id=pg_temp.operational_file_id()),
 1::bigint,'authenticated RLS permits file metadata only with source and file access');
insert into procurement_test_results select ok(core.wave3_storage_access(pg_temp.operational_file_path(),false),
 'registered staged path is eligible for one source-authorized upload');
insert into procurement_test_results select ok(not core.wave3_storage_access(pg_temp.operational_file_path(),true),
 'staged metadata cannot authorize reading an incomplete file');
reset role;
-- Synthetic Storage metadata only; no bytes are uploaded and the row rolls back.
insert into storage.objects(bucket_id,name) values('jentra-attachments',pg_temp.operational_file_path());
select api.complete_attachment(pg_temp.fid('tenant'),pg_temp.operational_file_id(),repeat('a',64),1,
 pg_temp.fid('operational.file.complete'));
set local role authenticated;
insert into procurement_test_results select is((select count(*) from storage.objects where name=pg_temp.operational_file_path()),
 1::bigint,'ready file is visible through the actual Storage read policy');
reset role;
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='procurement.bills.view';
set local role authenticated;
insert into procurement_test_results select is((select count(*) from core.attachments where id=pg_temp.operational_file_id()),
 0::bigint,'file metadata disappears when underlying source access is revoked');
insert into procurement_test_results select is((select count(*) from storage.objects where name=pg_temp.operational_file_path()),
 0::bigint,'private Storage read cannot bypass revoked source access');
insert into procurement_test_results select throws_ok($$select api.register_attachment(pg_temp.fid('tenant'),
 pg_temp.operational_file_payload(),pg_temp.fid('operational.file.key'))$$,'42501','SOURCE_UNAVAILABLE',
 'file registration replay rechecks underlying source access');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'procurement.bills.view');
insert into procurement_responses values('operational.file.reject',pg_temp.call('reject_wave3_attachment',
 jsonb_build_object('id',pg_temp.operational_file_id(),'reason','Superseded supporting file'),2,'operational.file.reject'));
insert into procurement_test_results select is(pg_temp.call('reject_wave3_attachment',
 jsonb_build_object('id',pg_temp.operational_file_id(),'reason','Superseded supporting file'),2,'operational.file.reject'),
 (select response from procurement_responses where name='operational.file.reject'),'reasoned rejection retries the exact original receipt');
set local role authenticated;
insert into procurement_test_results select is((select count(*) from storage.objects where name=pg_temp.operational_file_path()),
 0::bigint,'rejected attachment remains audited but its private file is unavailable');
reset role;
