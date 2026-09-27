-- Synthetic-only, strict outer rollback. Real shared commands, no persistent DDL.
set constraints all deferred;
select pg_temp.actor('creator');
create function pg_temp.close_payload(n text) returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fid(n),'period_id',(select id from finance.fiscal_periods
 where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')
 and '2026-09-25'::date between start_date and end_date limit 1),'as_of','2026-09-25')$$;
create function pg_temp.close_page(n text,s text,k text default null,o integer default 0) returns jsonb language sql as $$
 select api.close_control_review_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid(n),s,o,k)$$;
insert into procurement_responses values('close.main',pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.main'),0,'close.main'));
insert into procurement_test_results select is((select response#>>'{entity,scope}' from procurement_responses where name='close.main'),'all_entity_branches','close review freezes entity-wide scope');
insert into procurement_test_results select is((select response#>>'{entity,status}' from procurement_responses where name='close.main'),'blocked','known GRNI source differences are blocked instead of waived');
insert into procurement_test_results select ok(exists(select 1 from jsonb_array_elements(pg_temp.close_page('close.main','controls')->'items')x where x->>'kind'='GRNI'),'GRNI appears with existing AR AP inventory and cash controls');
insert into procurement_test_results select ok(exists(select 1 from jsonb_array_elements(pg_temp.close_page('close.main','controls')->'items')x where x->>'kind'='INVENTORY'),'inventory including transit is consolidated');
insert into procurement_test_results select ok(exists(select 1 from jsonb_array_elements(pg_temp.close_page('close.main','blockers')->'items')x where x->>'code'='GRNI_CONTROL_DIFFERENCE'),'close exceptions retain net-zero GRNI source discrepancies');
insert into procurement_test_results select is(pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.main'),0,'close.main'),(select response from procurement_responses where name='close.main'),'exact replay returns the original frozen review');
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.main')||'{"as_of":"2026-09-24"}',0,'close.main')$$,'22023',null,'changed replay cutoff rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.version'),1)$$,'40001',null,'creation expected version must be zero');
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.future')||'{"as_of":"2099-09-25"}',0)$$,'22023',null,'future cutoff fails before save');
insert into procurement_test_results select throws_ok($$select pg_temp.close_page('close.main','controls',null,50001)$$,'22023',null,'oversized cursor fails');
insert into procurement_test_results select throws_ok($$select pg_temp.close_page('close.main','invented')$$,'22023',null,'unsupported section fails');
insert into procurement_test_results select throws_ok($$select pg_temp.close_page('close.main','sources','invented')$$,'22023',null,'undisclosed component fails');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(pg_temp.close_page('close.main','sources','GRNI:'||pg_temp.fid('branch'))->'items')x where x->>'component_key'<>'GRNI:'||pg_temp.fid('branch')),'component filter cannot return other source evidence');
insert into procurement_test_results select throws_ok($$update finance.close_control_reviews set summary='{}' where id=pg_temp.fid('close.main')$$,'55000',null,'saved close summary is immutable');
insert into procurement_test_results select throws_ok($$delete from finance.close_control_reviews where id=pg_temp.fid('close.main')$$,'55000',null,'saved close review cannot be deleted');
-- Current product mapping changes cannot omit the original stock account.
insert into procurement_test_results select ok(exists(select 1 from jsonb_array_elements_text(finance.close_inventory_accounts(pg_temp.fid('tenant'),pg_temp.fid('entity'),'2026-09-25'))x
 where x::uuid=(select account_id from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
 join finance.accounts a on a.id=l.account_id and a.account_type='asset'
 where j.tenant_id=pg_temp.fid('tenant') and j.source_type='goods_receipt' limit 1)),'original posted stock asset remains in disclosed control basis');

-- Isolated reporting entity has a real bank GL and complete dated statement.
insert into finance.bank_statements(id,tenant_id,legal_entity_id,branch_id,bank_id,account_id,currency_code,
 identity,start_date,end_date,opening,closing,total,row_count,created_by)
values(pg_temp.fid('close.bank.statement'),pg_temp.fid('tenant'),pg_temp.fid('report.entity'),pg_temp.fid('report.branch'),
 pg_temp.fid('report.bank'),pg_temp.fid('report.cash'),'LKR','close-review-synthetic','2026-08-01','2026-08-31',
 0,151,151,1,pg_temp.fid('creator'));
insert into finance.bank_statement_lines(id,tenant_id,statement_id,bank_id,line_number,posting_date,reference,description,amount)
values(pg_temp.fid('close.bank.line'),pg_temp.fid('tenant'),pg_temp.fid('close.bank.statement'),pg_temp.fid('report.bank'),1,
 '2026-08-31','close-synthetic-1','Synthetic bank movement',151);
insert into procurement_test_results select is((finance.build_cash_controls(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),'2026-08-31')#>>'{controls,0,gl_value}')::numeric,150::numeric,'book balance includes the later backdated one-unit correction');
insert into procurement_test_results select is((finance.build_cash_controls(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),'2026-08-31')#>>'{controls,0,difference}')::numeric,0::numeric,'exact adjusted statement equation reconciles unmatched movements');
insert into procurement_test_results select is(finance.build_cash_controls(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),'2026-08-30')#>>'{controls,0,status}','statement_coverage_required','future-ended statement cannot imply current coverage');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(finance.build_cash_controls(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),'2026-08-30')->'sources')x where x->>'origin'='bank'),'future-ended statement lines are excluded from dated evidence');
create function pg_temp.close_bank_damage_probe() returns boolean language plpgsql as $$declare data jsonb;begin
 begin
  alter table finance.bank_statements disable trigger immutable;
  update finance.bank_statements set opening=1,closing=152 where id=pg_temp.fid('close.bank.statement');
  data:=finance.build_cash_controls(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),'2026-08-31');
  if data#>>'{controls,0,difference}'<>'1.000000' then raise exception 'independent bank balance was hidden';end if;
  if not exists(select 1 from finance.fiscal_periods p cross join lateral
   jsonb_array_elements(finance.period_close_exceptions(pg_temp.fid('tenant'),pg_temp.fid('report.entity'),p))x
   where p.id=pg_temp.fid('report.august') and x->>'code'='CASH_CONTROL_BLOCKED') then
   raise exception 'bank difference failed to block close';end if;
  raise exception using errcode='Z0001',message='rollback synthetic damage';
 exception when sqlstate 'Z0001' then return true;end;
 return false;
end $$;
insert into procurement_test_results select ok(pg_temp.close_bank_damage_probe(),'live close reruns independent bank evidence and blocks new differences');
insert into procurement_test_results select is((select closing from finance.bank_statements where id=pg_temp.fid('close.bank.statement')),151.000000::numeric,'deliberate bank damage rolls back before leaving probe');

-- Fault after snapshot insert must roll back evidence, receipts, audit and outbox.
create function pg_temp.fail_close_outbox() returns trigger language plpgsql as $$begin
 if new.topic='finance.close.reviewed' then raise exception using errcode='P0001',message='SYNTHETIC_CLOSE_OUTBOX_FAILURE';end if;return new;end $$;
create trigger fail_close_outbox before insert on core.outbox_events for each row execute function pg_temp.fail_close_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.fault'),0,'close.fault')$$,'P0001','SYNTHETIC_CLOSE_OUTBOX_FAILURE','late outbox failure aborts whole review command');
insert into procurement_test_results select is((select count(*)::integer from finance.close_control_reviews where id=pg_temp.fid('close.fault')),0,'late failure leaves no partial saved review');
drop trigger fail_close_outbox on core.outbox_events;
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.close_page('close.main','controls')$$,'42501',null,'MFA downgrade hides known close report');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select pg_temp.close_page('close.main','sources')$$,'42501',null,'known report ID cannot bypass entity and branch access');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.close_control_reviews$$,'42501',null,'application role cannot read private snapshot table');
insert into procurement_test_results select throws_ok($$select finance.build_cash_controls(pg_temp.fid('tenant'),pg_temp.fid('entity'),'2026-09-25')$$,'42501',null,'private cash builder cannot bypass permissions');
reset role;
-- Scope is checked again on read and replay; possession of a sealed ID is insufficient.
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role') and permission_code='inventory.cost.view';
insert into procurement_test_results select throws_ok($$select pg_temp.close_page('close.main','sources')$$,'42501',null,'cost revocation denies all consolidated source evidence');
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.main'),0,'close.main')$$,'42501',null,'exact replay rechecks entity-wide cost access');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.cost.view');
insert into procurement_test_results select is((select p.provolatile::text from pg_proc p where p.oid='finance.period_close_exceptions(uuid,uuid,finance.fiscal_periods)'::regprocedure),'s','close review check graph uses stable statement snapshots');
-- More than fifty historical stock control accounts must abort the command.
create function pg_temp.close_bound_probe() returns boolean language plpgsql as $$declare sample finance.journal_lines%rowtype;begin
 begin
  select l.* into sample from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
   join finance.accounts a on a.id=l.account_id and a.account_type='asset'
   where j.tenant_id=pg_temp.fid('tenant') and j.source_type='goods_receipt' limit 1;
  insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
   select pg_temp.fid('close.bound.account.'||x),pg_temp.fid('tenant'),pg_temp.fid('entity'),'BOUND-'||x,
    'Synthetic historical asset','asset','debit',pg_temp.fid('creator'),pg_temp.fid('creator') from generate_series(1,51)x;
  alter table finance.journal_lines disable trigger protect_posted_lines;
  insert into finance.journal_lines(id,tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,currency_code,
   transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
   select gen_random_uuid(),sample.tenant_id,sample.legal_entity_id,sample.branch_id,sample.journal_entry_id,
    10000+x,pg_temp.fid('close.bound.account.'||x),sample.currency_code,1,0,1,0,sample.posting_date,pg_temp.fid('creator') from generate_series(1,51)x;
  perform pg_temp.call('generate_close_control_review',pg_temp.close_payload('close.bound'),0,'close.bound');
  raise exception 'oversized account basis failed to abort';
 exception when sqlstate '54000' then return true;end;
 return false;
end $$;
insert into procurement_test_results select ok(pg_temp.close_bound_probe(),'oversized historical stock account basis fails atomically');
insert into procurement_test_results select is((select count(*)::integer from finance.close_control_reviews where id=pg_temp.fid('close.bound')),0,'oversized review saves no partial snapshot');
insert into procurement_test_results select is((select count(*)::integer from finance.accounts where code like 'BOUND-%'),0,'bound probe restores all deliberate synthetic ledger inputs');
