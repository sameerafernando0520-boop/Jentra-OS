select pg_temp.actor('creator');
set constraints all deferred;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),p from unnest(array['finance.view','finance.bank.import','finance.bank.reconcile','finance.bank.adjust'])p on conflict do nothing;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.fid('bank.gl'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'BANK318','Bank test GL','asset','debit',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,reconciliation_rules,created_by,updated_by)
values(pg_temp.fid('bank.account'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'BANK318','Bank test account','bank',pg_temp.fid('bank.gl'),'LKR','{"tolerance":"1"}',pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.bank_import(n text default 'bank.statement',amt text default '100') returns jsonb language sql as $$select jsonb_build_object(
 'action','import','id',pg_temp.fid(n),'bank_id',pg_temp.fid('bank.account'),'identity',n,'start_date','2026-09-21','end_date','2026-09-21','opening','0','closing',amt,
 'lines',jsonb_build_array(jsonb_build_object('date','2026-09-21','reference',n,'description','Synthetic bank line','amount',amt)))$$;
create function pg_temp.bank_journal(n text,amount numeric) returns uuid language sql as $$select finance.flow_post_journal(
 jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),'document_date','2026-09-21','currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('bank.gl'),amount,amount),finance.flow_jline(pg_temp.fid('mj.credit'),-amount,-amount)),
 'bank_fixture',pg_temp.fid(n),gen_random_uuid(),gen_random_uuid())$$;
create function pg_temp.bank_match(n text default 'bank.match',s text default 'bank.statement',j text default 'bank.source') returns jsonb language sql as $$select jsonb_build_object(
 'action','match','id',pg_temp.fid(n),'bank_id',pg_temp.fid('bank.account'),'posting_date','2026-09-21','reason','Synthetic matching',
 'statement_line_ids',(select jsonb_agg(id) from finance.bank_statement_lines where statement_id=pg_temp.fid(s)),
 'journal_line_ids',(select jsonb_agg(l.id) from finance.journal_lines l join finance.journal_entries h on h.id=l.journal_entry_id where h.source_id=pg_temp.fid(j) and l.account_id=pg_temp.fid('bank.gl')))$$;
insert into procurement_responses values('bank.journal.before',jsonb_build_object('n',(select count(*) from finance.journal_entries)));
insert into procurement_responses values('bank.import',pg_temp.call('bank_reconciliation_command',pg_temp.bank_import(),0,'bank.import'));
insert into procurement_test_results select is((select count(*) from finance.journal_entries),(select (response->>'n')::bigint from procurement_responses where name='bank.journal.before'),'bank import creates no journal');
insert into procurement_test_results select is(pg_temp.call('bank_reconciliation_command',pg_temp.bank_import(),0,'bank.import'),(select response from procurement_responses where name='bank.import'),'bank import sealed replay');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import(),0)$$,'23505','BANK_STATEMENT_DUPLICATE','duplicate statement rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.statement.copy')||'{"identity":" BANK.STATEMENT "}',0)$$,'23505','BANK_STATEMENT_DUPLICATE','statement identity is unique after case and whitespace normalization');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bad')||'{"closing":"99"}',0)$$,'23514','BANK_BALANCE_MISMATCH','imbalanced statement rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',jsonb_set(pg_temp.bank_import('bad'),'{lines,0,amount}','100'),0)$$,'22023',null,'numeric JSON amount rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bad')||'{"lines":[]}',0)$$,'22023','BANK_STATEMENT_INVALID','empty import rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',jsonb_set(pg_temp.bank_import('bad'),'{lines,0,reference}','"bank.statement"'),0)$$,'23505',null,'overlapping reference rejected');
insert into procurement_test_results select is((select count(*) from finance.bank_statements where identity='bad'),0::bigint,'invalid import is atomic');
select pg_temp.bank_journal('bank.source',100);
insert into procurement_responses values('bank.match',pg_temp.call('bank_reconciliation_command',pg_temp.bank_match(),0,'bank.match'));
insert into procurement_test_results select is((select response#>>'{entity,difference}' from procurement_responses where name='bank.match'),'0.000000','exact match is decimal string');
insert into procurement_test_results select is((select adjustment_journal_id from finance.bank_matches where id=pg_temp.fid('bank.match')),null::uuid,'exact match creates no adjustment');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_match('bank.duplicate'),0)$$,'40001','BANK_LINE_ALREADY_MATCHED','second matcher cannot claim same line');
insert into procurement_test_results select throws_ok($$delete from finance.bank_matches where id=pg_temp.fid('bank.match')$$,'55000',null,'bank match evidence immutable');
insert into procurement_test_results select throws_ok($$update finance.cash_bank_accounts set account_id=pg_temp.fid('payment-cash-gl') where id=pg_temp.fid('bank.account')$$,'55000','BANK_BASIS_IN_USE','used bank mapping cannot move');
create function pg_temp.bank_reverse(n text default 'bank.reverse',m text default 'bank.match') returns jsonb language sql as $$select jsonb_build_object('action','reverse','id',pg_temp.fid(n),'match_id',pg_temp.fid(m),'posting_date','2026-09-21','reason','Wrong bank matching')$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_reverse(),0)$$,'40001','VERSION_CONFLICT','reverse checks expected version');
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_reverse(),1);
insert into procurement_test_results select is((select count(*) from finance.bank_match_claims where match_id=pg_temp.fid('bank.match')),0::bigint,'reversal releases both active claims');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_reverse('bank.reverse2'),1)$$,'55000','BANK_MATCH_ALREADY_REVERSED','duplicate reversal denied');
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.adjust.statement','99.50'),0);
select pg_temp.bank_journal('bank.adjust.source',100);
insert into procurement_responses values('bank.adjust',pg_temp.call('bank_reconciliation_command',pg_temp.bank_match('bank.adjust','bank.adjust.statement','bank.adjust.source')||jsonb_build_object('adjustment_account_id',pg_temp.fid('mj.debit')),0));
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l where l.journal_entry_id=(select adjustment_journal_id from finance.bank_matches where id=pg_temp.fid('bank.adjust'))),0::numeric,'tolerance adjustment journal balances');
insert into procurement_test_results select is((select base_credit from finance.journal_lines where journal_entry_id=(select adjustment_journal_id from finance.bank_matches where id=pg_temp.fid('bank.adjust')) and account_id=pg_temp.fid('bank.gl')),0.5::numeric,'adjustment reconciles exact bank amount');
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_reverse('bank.adjust.reverse','bank.adjust'),1);
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id where j.source_id in(pg_temp.fid('bank.adjust'),pg_temp.fid('bank.adjust.reverse')) and l.account_id=pg_temp.fid('bank.gl')),0::numeric,'linked correction negates original bank adjustment');
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.too.large','90'),0);
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_match('bank.too.large.match','bank.too.large','bank.adjust.source'),0)$$,'22023','BANK_TOLERANCE_EXCEEDED','out-of-tolerance match rejected');
create function pg_temp.fail_bank_outbox() returns trigger language plpgsql as $$begin raise exception using errcode='P0001',message='BANK_OUTBOX_FAILURE';end$$;
create trigger bank_failure before insert on core.outbox_events for each row execute function pg_temp.fail_bank_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.failed'),0)$$,'P0001','BANK_OUTBOX_FAILURE','late failure rolls back import');
drop trigger bank_failure on core.outbox_events;
insert into procurement_test_results select is((select count(*) from finance.bank_statements where identity='bank.failed'),0::bigint,'late failure leaves no header');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role') and permission_code='finance.bank.import';
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import(),0,'bank.import')$$,'42501',null,'replay checks revoked import permission');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'accounts')$$,'42501',null,'outsider cannot read bank references');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.bank_statements$$,'42501',null,'private statement tables denied');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),p from unnest(array['finance.bank.import','finance.bank.manage'])p on conflict do nothing;
-- Signed amounts are necessary for withdrawals and overdraft balances.
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.withdrawal','-25.000001'),0);
select pg_temp.bank_journal('bank.withdrawal.source',-25.000001);
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_match('bank.withdrawal.match','bank.withdrawal','bank.withdrawal.source'),0);
insert into procurement_test_results select is((select statement_total from finance.bank_matches where id=pg_temp.fid('bank.withdrawal.match')),-25.000001::numeric,'withdrawals and negative closing balances retain exact sign');
insert into procurement_test_results select cmp_ok(jsonb_array_length(api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'accounts')->'items'),'>=',1,'bank account options expose scoped references');
insert into procurement_test_results select lives_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'statements',pg_temp.fid('bank.account'))$$,'statement register works');
insert into procurement_test_results select lives_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'statement_lines',pg_temp.fid('bank.account'))$$,'statement source page works');
insert into procurement_test_results select lives_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'journal_lines',pg_temp.fid('bank.account'))$$,'posted source page works');
insert into procurement_test_results select lives_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'matches',pg_temp.fid('bank.account'))$$,'immutable match and reversal history page works');
insert into procurement_test_results select lives_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'rates')$$,'rate reference page works');
insert into procurement_test_results select lives_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'offset_accounts')$$,'offset reference page works');
select pg_temp.call('bank_reconciliation_command',jsonb_build_object('action','rules','id',pg_temp.fid('bank.rules'),'bank_id',pg_temp.fid('bank.account'),'tolerance','0.005','reason','Approved bank fee tolerance'),(select version from finance.cash_bank_accounts where id=pg_temp.fid('bank.account')));
insert into procurement_test_results select is((select reconciliation_rules->>'tolerance' from finance.cash_bank_accounts where id=pg_temp.fid('bank.account')),'0.005','governed exact tolerance configuration');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',jsonb_build_object('action','rules','id',pg_temp.fid('bank.rules.stale'),'bank_id',pg_temp.fid('bank.account'),'tolerance','1','reason','Stale version'),1)$$,'40001','VERSION_CONFLICT','tolerance cannot overwrite a concurrent configuration');
-- Many statement lines to one transaction, then one statement to many transactions.
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.multi')||jsonb_build_object('lines',jsonb_build_array(
 jsonb_build_object('date','2026-09-21','reference','MULTI1','description','Split deposit','amount','40'),
 jsonb_build_object('date','2026-09-21','reference','MULTI2','description','Split deposit','amount','60'))),0);
select pg_temp.bank_journal('bank.multi.source',100);
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_match('bank.multi.match','bank.multi','bank.multi.source'),0);
insert into procurement_test_results select is((select cardinality(statement_line_ids) from finance.bank_matches where id=pg_temp.fid('bank.multi.match')),2,'many-to-one claims both statement lines');
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.one'),0);
select pg_temp.bank_journal('bank.one.source1',25);
select pg_temp.bank_journal('bank.one.source2',75);
select pg_temp.call('bank_reconciliation_command',pg_temp.bank_match('bank.one.match','bank.one','bank.one.source1')||jsonb_build_object('journal_line_ids',
 (select jsonb_agg(l.id) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id where l.account_id=pg_temp.fid('bank.gl') and j.source_id in(pg_temp.fid('bank.one.source1'),pg_temp.fid('bank.one.source2')))),0);
insert into procurement_test_results select is((select cardinality(journal_line_ids) from finance.bank_matches where id=pg_temp.fid('bank.one.match')),2,'one-to-many claims both posted transactions');
insert into procurement_test_results select throws_ok($$select pg_temp.call('bank_reconciliation_command',pg_temp.bank_import('bank.2001')||jsonb_build_object('lines',(select jsonb_agg(jsonb_build_object('date','2026-09-21','reference','ROW'||n,'amount','1')) from generate_series(1,2001)n)),0)$$,'22023','BANK_STATEMENT_INVALID','server enforces 2000 row limit');
insert into procurement_test_results select throws_ok($$select api.bank_reconciliation_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('trace.hiddenbranch'),'statement_lines',pg_temp.fid('bank.account'))$$,'42501',null,'known bank ID cannot cross branch scope');
set constraints all immediate;
