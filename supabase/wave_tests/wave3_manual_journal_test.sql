select pg_temp.actor('creator');
set constraints all deferred;
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.fid('tenant'),pg_temp.fid(who||'.role'),p from unnest(array['creator','approver'])who cross join unnest(array['finance.view','finance.journals.post','finance.reversals.post','core.files.view'])p on conflict do nothing;
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'manual_journal','MJ-',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,is_posting,created_by,updated_by)
 select pg_temp.fid(n),pg_temp.fid('tenant'),pg_temp.fid('entity'),replace(upper(n),'.','-'),n,'expense','debit',true,pg_temp.fid('creator'),pg_temp.fid('creator') from unnest(array['mj.debit','mj.credit'])n;
create function pg_temp.mj_payload(n text default 'mj.first') returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fid(n),'document_date','2026-09-20',
 'description','Accrued freight correction','reason','Supplier estimate reconciled','currency_code','LKR','attachment_ids','[]'::jsonb,
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(n||'.debit'),'account_id',pg_temp.fid('mj.debit'),'debit','123.456789','credit','0','cost_center','Distribution'),
 jsonb_build_object('line_id',pg_temp.fid(n||'.credit'),'account_id',pg_temp.fid('mj.credit'),'debit','0','credit','123.456789','project','Warehouse')) )$$;
create function pg_temp.mj_act(n text,p jsonb,rpc text default 'transition_manual_journal') returns jsonb language sql as $$select pg_temp.call(rpc,
 jsonb_build_object('document_id',pg_temp.fid(n))||p,(select version from finance.manual_journals where id=pg_temp.fid(n)))$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',pg_temp.mj_payload(),1)$$,'40001','VERSION_CONFLICT','manual creation requires version zero');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',jsonb_set(pg_temp.mj_payload(),'{lines,0,debit}','123.456789'),0)$$,'22023','debit must be a decimal string.','manual journal numeric coercion rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',jsonb_set(pg_temp.mj_payload(),'{lines,1,credit}','"123.456788"'),0)$$,'23514','UNBALANCED_JOURNAL','one micro-unit imbalance rejected');
insert into procurement_responses values('mj.save',pg_temp.call('upsert_manual_journal',pg_temp.mj_payload(),0,'mj.save'));
insert into procurement_test_results select is(pg_temp.call('upsert_manual_journal',pg_temp.mj_payload(),0,'mj.save'),(select response from procurement_responses where name='mj.save'),'journal draft replay is exact');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.first','{"action":"submit"}')$$,'55000','WORKFLOW_CONFIGURATION_ERROR','manual journal fails closed without approval setup');
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
 values(pg_temp.fid('mj.workflow'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'manual_journal','Journal approval','active',
 '{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","posted"]],"posting_transitions":[["submitted","draft"],["approved","draft"]],"requires_approval":true}',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
 values(pg_temp.fid('mj.step'),pg_temp.fid('tenant'),pg_temp.fid('mj.workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.mj_act('mj.first','{"action":"submit"}');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.first','{"decision":"approved"}')$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','journal preparer cannot approve');
select pg_temp.actor('approver','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.first','{"decision":"approved"}')$$,'42501',null,'journal approval enforces MFA role');
select pg_temp.actor('approver');
select pg_temp.mj_act('mj.first','{"decision":"approved"}');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.first','{}','post_manual_journal')$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','preparer cannot post own journal');
select pg_temp.actor('approver');
insert into procurement_responses values('mj.post',pg_temp.mj_act('mj.first','{}','post_manual_journal'));
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where journal_entry_id=(select journal_entry_id from finance.manual_journals where id=pg_temp.fid('mj.first'))),0::numeric,'manual uses balanced existing ledger');
insert into procurement_test_results select is((select sum(base_debit) from finance.journal_lines where journal_entry_id=(select journal_entry_id from finance.manual_journals where id=pg_temp.fid('mj.first'))),123.456789::numeric,'manual journal preserves six-place amount');
insert into procurement_test_results select throws_ok($$update finance.manual_journals set reason='Rewrite history' where id=pg_temp.fid('mj.first')$$,'55000','POSTED_DOCUMENT_IMMUTABLE','manual source history immutable');
insert into procurement_test_results select is(jsonb_array_length(api.manual_journal_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('mj.first'))->'ledger_lines'),2,'manual detail exposes actual ledger source lines');
select pg_temp.actor('creator');
insert into procurement_responses values('mj.reverse.save',pg_temp.call('upsert_manual_journal',pg_temp.mj_payload('mj.reverse')||jsonb_build_object('reversal_of_id',pg_temp.fid('mj.first'),'lines','[]'::jsonb),0));
insert into procurement_test_results select is((select response#>>'{entity,lines,0,amount}' from procurement_responses where name='mj.reverse.save'),'-123.456789','reversal ignores client amounts and negates original');
select pg_temp.mj_act('mj.reverse','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('mj.reverse','{"decision":"approved"}');
select pg_temp.mj_act('mj.reverse','{}','post_manual_journal');
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where account_id=pg_temp.fid('mj.debit')),0::numeric,'linked reversal cancels exact original account effect');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',pg_temp.mj_payload('mj.duplicate')||jsonb_build_object('reversal_of_id',pg_temp.fid('mj.first')),0)$$,'55000','JOURNAL_ALREADY_REVERSED','second manual reversal rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',pg_temp.mj_payload('mj.chain')||jsonb_build_object('reversal_of_id',pg_temp.fid('mj.reverse')),0)$$,'55000','JOURNAL_REVERSAL_INVALID','reversal chain rejected');
-- FX and late-failure coverage uses only this outer rollback transaction.
select pg_temp.actor('creator');
insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,target_currency_code,rate,effective_date,rate_type,created_by,updated_by)
 values(pg_temp.fid('mj.rate'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'USD','LKR',1.2345678912,'2026-09-01','custom',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into procurement_responses values('mj.fx',pg_temp.call('upsert_manual_journal',pg_temp.mj_payload('mj.fx')||jsonb_build_object('currency_code','USD','exchange_rate_id',pg_temp.fid('mj.rate')),0));
insert into procurement_test_results select is((select (response#>>'{entity,base_total}')::numeric from procurement_responses where name='mj.fx'),round(123.456789*1.2345678912,6),'manual FX recomputed with exact six-place base rounding');
select pg_temp.mj_act('mj.fx','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('mj.fx','{"decision":"approved"}');
update finance.exchange_rates set rate=2 where id=pg_temp.fid('mj.rate');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.fx','{}','post_manual_journal')$$,'55000','JOURNAL_REAPPROVAL_REQUIRED','changed FX invalidates approved journal');
update finance.exchange_rates set rate=1.2345678912 where id=pg_temp.fid('mj.rate');
update finance.fiscal_periods set state='soft_locked' where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity') and '2026-09-20' between start_date and end_date;
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.fx','{}','post_manual_journal')$$,'55000','PERIOD_CLOSED','approved manual journal cannot bypass period lock');
update finance.fiscal_periods set state='open' where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity') and '2026-09-20' between start_date and end_date;
create function pg_temp.fail_manual_outbox() returns trigger language plpgsql as $$begin
 if new.topic='finance.manual_journal.post' then raise exception using errcode='P0001',message='MANUAL_OUTBOX_FAILURE';end if;return new;end$$;
create trigger synthetic_manual_failure before insert on core.outbox_events for each row execute function pg_temp.fail_manual_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.fx','{}','post_manual_journal')$$,'P0001','MANUAL_OUTBOX_FAILURE','late manual outbox failure rolls back ledger posting');
drop trigger synthetic_manual_failure on core.outbox_events;
insert into procurement_test_results select is((select status from finance.manual_journals where id=pg_temp.fid('mj.fx')),'approved','late failure retains approved state');
insert into procurement_test_results select is((select count(*) from finance.journal_entries where source_type='manual_journal' and source_id=pg_temp.fid('mj.fx')),0::bigint,'late failure leaves no orphan journal');
select pg_temp.mj_act('mj.fx','{}','post_manual_journal');
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines where journal_entry_id=(select journal_entry_id from finance.manual_journals where id=pg_temp.fid('mj.fx'))),0::numeric,'FX posting balances exactly after retry');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',jsonb_set(pg_temp.mj_payload('mj.control'),'{lines,0,account_id}',to_jsonb((select payable_account_id from procurement.supplier_bill_controls where tenant_id=pg_temp.fid('tenant'))::text)),0)$$,'55000','SUBLEDGER_CONTROL_REQUIRES_SOURCE','manual AP control entry is blocked');
insert into core.attachments(id,tenant_id,aggregate_type,aggregate_id,file_name,mime_type,byte_size,object_path,checksum_sha256,upload_status,created_by,updated_by)
 values(pg_temp.fid('mj.file'),pg_temp.fid('tenant'),'legal_entity',pg_temp.fid('entity'),'freight.pdf','application/pdf',42,'synthetic/manual/freight.pdf',repeat('a',64),'ready',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.mj_file_payload() returns jsonb language sql as $$select pg_temp.mj_payload('mj.filejournal')||jsonb_build_object('attachment_ids',jsonb_build_array(pg_temp.fid('mj.file')))$$;
select pg_temp.call('upsert_manual_journal',pg_temp.mj_file_payload(),0,'mj.file.save');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role') and permission_code='core.files.view';
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',pg_temp.mj_file_payload(),0,'mj.file.save')$$,'42501',null,'replay cannot expose attachments after file permission revocation');
insert into procurement_test_results select throws_ok($$select api.manual_journal_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('mj.filejournal'))$$,'42501',null,'journal detail checks attachment permission');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'core.files.view');
select pg_temp.mj_act('mj.filejournal','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('mj.filejournal','{"decision":"approved"}');
update core.attachments set checksum_sha256=repeat('b',64) where id=pg_temp.fid('mj.file');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('mj.filejournal','{}','post_manual_journal')$$,'55000','JOURNAL_REAPPROVAL_REQUIRED','attachment content change invalidates prior approval');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.manual_journal_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('mj.first'))$$,'42501',null,'manual source details deny nonmembers');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select api.manual_journal_detail(pg_temp.fid('tenant'),null,pg_temp.fid('branch'),pg_temp.fid('mj.first'))$$,'42501',null,'manual detail requires explicit entity scope');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.manual_journals$$,'42501',null,'manual private table is not client-readable');
reset role;
set constraints all immediate;
