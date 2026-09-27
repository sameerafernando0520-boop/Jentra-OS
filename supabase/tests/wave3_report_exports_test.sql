set constraints all deferred;
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.reports.export');
create function pg_temp.export_preview(resource text default 'close',source_name text default 'close.main',section text default 'controls',filters jsonb default '{}')
returns jsonb language sql as $$ select api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),resource,pg_temp.fid(source_name),section,filters)$$;
create function pg_temp.export_payload(n text) returns jsonb language plpgsql as $$declare preview jsonb;data jsonb;cols jsonb;begin
 preview:=pg_temp.export_preview();data:=(preview->>'canonical_text')::jsonb;
 select jsonb_build_array('record_type')||
  (select jsonb_agg('report.'||key order by key) from (select jsonb_object_keys(data->'metadata') key
   union select unnest(array['export_id','export_prepared_at','source_hash','file_format']))q)||
  coalesce((select jsonb_agg('data.'||key order by key) from (select distinct key
   from jsonb_array_elements(data->'rows')x cross join lateral jsonb_object_keys(x)key)q),'[]'::jsonb) into cols;
 return jsonb_build_object('id',pg_temp.fid(n),'source_type','close','source_id',pg_temp.fid('close.main'),
  'section','controls','filters','{}'::jsonb,'source_hash',preview->>'source_hash','file_format','csv','file_name','close-review.csv',
  'file_sha256',repeat('a',64),'file_size',1234,'columns',cols,'prepared_at','2026-09-26T00:00:00Z');end $$;
insert into procurement_test_results select is(pg_temp.export_preview()->>'source_hash',encode(extensions.digest(pg_temp.export_preview()->>'canonical_text','sha256'),'hex'),'export canonical evidence SHA matches server bytes');
insert into procurement_test_results select is(((pg_temp.export_preview()->>'canonical_text')::jsonb#>>'{metadata,source_id}'),pg_temp.fid('close.main')::text,'export metadata retains source report identity');
insert into procurement_test_results select is(((pg_temp.export_preview()->>'canonical_text')::jsonb#>>'{metadata,actor_id}'),pg_temp.fid('creator')::text,'export attribution is authenticated actor');
insert into procurement_test_results select is(((pg_temp.export_preview()->>'canonical_text')::jsonb#>>'{metadata,as_of}'),'2026-09-25','export cutoff comes from frozen source');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements((pg_temp.export_preview('close','close.main','sources',jsonb_build_object('component_key','GRNI:'||pg_temp.fid('branch')))->>'canonical_text')::jsonb->'rows')x
 where x->>'component_key'<>'GRNI:'||pg_temp.fid('branch')),'export includes complete frozen component filter only');
insert into procurement_test_results select throws_ok($$select pg_temp.export_preview('close','close.main','controls','{"sql":"select secret"}')$$,'22023','REPORT_EXPORT_FILTER_INVALID','arbitrary export filter rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.export_preview('arbitrary_table')$$,'22023','REPORT_EXPORT_SOURCE_INVALID','arbitrary source table rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.export_preview('close','close.main','unsupported')$$,'22023',null,'unsupported section rejected by source contract');
insert into procurement_responses values('export.register',pg_temp.call('record_report_export',pg_temp.export_payload('export.register'),0,'export.register'));
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses where name='export.register'),'registered','registration does not claim native file delivery');
insert into procurement_test_results select is((select filters->>'artifact_state' from core.export_jobs where id=pg_temp.fid('export.register')),'generated_local_delivery_unconfirmed','Wave 2 export ledger records honest artifact state');
insert into procurement_test_results select is((select row_count from core.export_jobs where id=pg_temp.fid('export.register')),jsonb_array_length((pg_temp.export_preview()->>'canonical_text')::jsonb->'rows'),'registered row count comes from server evidence');
insert into procurement_test_results select is(pg_temp.call('record_report_export',pg_temp.export_payload('export.register'),0,'export.register'),(select response from procurement_responses where name='export.register'),'exact export retry creates one attributable job');
insert into procurement_test_results select is((select count(*)::integer from core.export_jobs where id=pg_temp.fid('export.register')),1,'replay creates no duplicate export job');
insert into procurement_test_results select throws_ok($$select pg_temp.call('record_report_export',pg_temp.export_payload('export.register')||'{"file_size":999}',0,'export.register')$$,'22023',null,'changed-byte metadata key reuse rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('record_report_export',pg_temp.export_payload('export.bad')||jsonb_build_object('source_hash',repeat('0',64)),0)$$,'22023','REPORT_EXPORT_METADATA_INVALID','unverified source hash cannot be registered');
insert into procurement_test_results select throws_ok($$select pg_temp.call('record_report_export',pg_temp.export_payload('export.bad')||'{"columns":["secret"]}',0)$$,'22023','REPORT_EXPORT_METADATA_INVALID','invented columns cannot bypass source schema');
insert into procurement_test_results select throws_ok($$select pg_temp.call('record_report_export',pg_temp.export_payload('export.bad')||'{"file_size":10485761}',0)$$,'22023','REPORT_EXPORT_METADATA_INVALID','oversized file fails before job insert');
insert into procurement_test_results select throws_ok($$select pg_temp.call('record_report_export',pg_temp.export_payload('export.bad')||'{"file_name":"../secret.csv"}',0)$$,'22023','REPORT_EXPORT_METADATA_INVALID','path traversal is not an export filename');
-- Exercise all supported report permissions and canonical sources, not only close.
insert into procurement_test_results select ok((api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 'control',pg_temp.fid('grni.d24'),'items','{}')->>'canonical_text')::jsonb#>'{rows}' is not null,'GRNI receipt section can export exact source evidence');
insert into procurement_test_results select ok((api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 'inventory',pg_temp.fid('valuation.first'),'stock','{}')->>'canonical_text')::jsonb#>'{rows}' is not null,'inventory frozen stock section exports at original cutoff');
insert into procurement_test_results select ok((api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 'tax',pg_temp.fid('tax.legacy'),'lines','{}')->>'canonical_text')::jsonb#>'{rows}' is not null,'tax review export retains statutory review metadata');
insert into procurement_test_results select ok((api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 'budget',pg_temp.fid('budget.variance'),'lines','{}')->>'canonical_text')::jsonb#>'{rows}' is not null,'approved-budget variance lineage exports');
insert into procurement_test_results select ok((api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 'statement',(select id from finance.financial_reports where legal_entity_id=pg_temp.fid('report.entity') limit 1),'accounts','{}')->>'canonical_text')::jsonb#>'{rows}' is not null,'posted statements export scoped frozen account evidence');
create function pg_temp.export_bound_probe() returns boolean language plpgsql as $$begin
 begin
  alter table finance.close_control_reviews disable trigger immutable;
  update finance.close_control_reviews set evidence=jsonb_set(evidence,'{blockers}',(select jsonb_agg(jsonb_build_object('id','huge:'||x,'code','SYNTHETIC')) from generate_series(1,10001)x)) where id=pg_temp.fid('close.main');
  perform pg_temp.export_preview('close','close.main','blockers');raise exception 'oversized evidence did not fail';
 exception when sqlstate '54000' then return true;end;return false;
end $$;
insert into procurement_test_results select ok(pg_temp.export_bound_probe(),'10001-row export fails without truncation or partial jobs');
create function pg_temp.fail_export_outbox() returns trigger language plpgsql as $$begin
 if new.topic='finance.report.exported' then raise exception using errcode='P0001',message='EXPORT_OUTBOX_FAILURE';end if;return new;end $$;
create trigger fail_export_outbox before insert on core.outbox_events for each row execute function pg_temp.fail_export_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.call('record_report_export',pg_temp.export_payload('export.fault'),0,'export.fault')$$,'P0001','EXPORT_OUTBOX_FAILURE','late export outbox failure rolls back registration');
drop trigger fail_export_outbox on core.outbox_events;
insert into procurement_test_results select is((select count(*)::integer from core.export_jobs where id=pg_temp.fid('export.fault')),0,'late export failure leaves no Wave 2 job');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role') and permission_code='finance.reports.export';
insert into procurement_test_results select throws_ok($$select pg_temp.export_preview()$$,'42501',null,'revocation blocks export preview');
-- Seal before revocation so constructing the test body does not mask the replay check.
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.reports.export');
create temporary table export_sealed as select pg_temp.export_payload('export.register') p;
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role') and permission_code='finance.reports.export';
insert into procurement_test_results select throws_ok($$select pg_temp.call('record_report_export',(select p from export_sealed),0,'export.register')$$,'42501',null,'registered export replay rechecks current access');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.reports.export');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select pg_temp.export_preview()$$,'42501',null,'known frozen report cannot leak through export endpoint');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select finance.report_export_document(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'close',pg_temp.fid('close.main'),'controls','{}')$$,'42501',null,'private export builder cannot bypass public permission checks');
reset role;
