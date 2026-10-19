-- Final stack posted ledger drill-through; all synthetic identities roll back.
select pg_temp.actor('creator');
set constraints all deferred;
create function pg_temp.journal_page(n text,a integer default 0) returns jsonb language sql as $$
 select api.posted_journal_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
  (select journal_entry_id from finance.manual_journals where id=pg_temp.fid(n)),a)$$;
insert into procurement_test_results select is(pg_temp.journal_page('dim.journal.a')#>>'{journal,base_debit}',
 '123.456789','posted journal exact six-place whole balance survives serialization');
insert into procurement_test_results select is(pg_temp.journal_page('mj.fx')#>>'{journal,exchange_rate}',
 '1.2345678912','posted journal retains all ten exchange-rate places');
insert into procurement_test_results select is(pg_temp.journal_page('dim.journal.a')#>>'{items,0,dimension_snapshot,cost_centre,name}',
 'Governed dim.a','posted journal retains original dimension name after master rename and retirement');
insert into procurement_test_results select is(pg_temp.journal_page('dim.reverse')#>>'{items,0,dimension_snapshot,cost_centre,version}',
 '1','reversal drill-through retains original dimension version');
insert into procurement_test_results select is(pg_temp.journal_page('mj.first')#>>'{items,0,cost_centre_id}',
 null,'legacy posted label gains no invented dimension identity');
insert into procurement_test_results select is(pg_temp.journal_page('dim.journal.a')#>>'{journal,label_basis}',
 'current_catalogue','account and branch labels are explicitly current catalogue evidence');
insert into procurement_test_results select is(pg_temp.journal_page('dim.journal.a',2)->'items','[]'::jsonb,
 'valid final cursor returns a bounded empty terminal page');
insert into procurement_test_results select throws_ok($$select pg_temp.journal_page('dim.journal.a',3)$$,
 '22023','JOURNAL_CURSOR_INVALID','cursor cannot skip missing lines');
insert into procurement_test_results select throws_ok($$select pg_temp.journal_page('dim.journal.a',-1)$$,
 '22023','JOURNAL_CURSOR_INVALID','negative cursor fails closed');
insert into procurement_test_results select throws_ok($$select api.posted_journal_evidence(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('journal.unknown'))$$,
 '42501','JOURNAL_UNAVAILABLE','missing posted identity is non-disclosing');
insert into procurement_test_results select throws_ok($$select api.posted_journal_evidence(pg_temp.fid('tenant'),
 pg_temp.fid('entity'),pg_temp.fid('branch'),(select id from finance.journal_entries where legal_entity_id<>pg_temp.fid('entity') limit 1))$$,
 '42501','JOURNAL_UNAVAILABLE','other entity identity has the same unavailable response');
-- Exercise the real shared posting engine, without a synthetic manual source.
create function pg_temp.evidence_large(n text,c integer,b uuid default null) returns uuid language plpgsql as $$declare lines jsonb;begin
 select jsonb_agg(jsonb_build_object('account_id',pg_temp.fid(case when x%2=0 then 'mj.credit' else 'mj.debit' end),
  'amount',case when x%2=0 then '-0.000001' else '0.000001' end,
  'base_amount',case when x%2=0 then '-0.000001' else '0.000001' end)) into lines from generate_series(1,c)x;
 return finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),
 'branch_id',coalesce(b,pg_temp.fid('branch')),'document_date','2026-09-20','currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 lines,'journal_evidence_fixture',pg_temp.fid(n),pg_temp.fid(n||'.request'),pg_temp.fid(n||'.command'));
end$$;
create temp table journal_evidence_fixture(id uuid);
insert into journal_evidence_fixture values(pg_temp.evidence_large('evidence.paged',102));
create function pg_temp.evidence_page(a integer default 0) returns jsonb language sql as $$
 select api.posted_journal_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 (select id from journal_evidence_fixture),a)$$;
insert into procurement_test_results select is(jsonb_array_length(pg_temp.evidence_page()->'items'),50,
 'large posted evidence page is bounded to fifty lines');
insert into procurement_test_results select is(pg_temp.evidence_page()->>'next_cursor','50','cursor binds the final returned line');
insert into procurement_test_results select is(pg_temp.evidence_page(50)#>>'{items,0,line_number}','51','next page preserves ledger ordering');
insert into procurement_test_results select is(jsonb_array_length(pg_temp.evidence_page(100)->'items'),2,'terminal page returns only remaining lines');
-- Current access on every read, including permission in a historical retired branch.
update core.branches set status='inactive' where id=pg_temp.fid('branch');
insert into procurement_test_results select throws_ok($$select pg_temp.journal_page('dim.journal.a')$$,
 '42501',null,'a retired branch cannot be the working context');
update core.branches set status='active' where id=pg_temp.fid('branch');
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
 values(pg_temp.fid('evidence.history.branch'),pg_temp.fid('tenant'),pg_temp.fid('entity'),
 'Historical ledger branch','EVD-H',pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('evidence.history.branch'),'journal_entry','EVD-',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.evidence_large('evidence.history',2,pg_temp.fid('evidence.history.branch'));
update core.branches set status='inactive' where id=pg_temp.fid('evidence.history.branch');
insert into procurement_test_results select ok(exists(select 1 from finance.journal_entries j
 where j.branch_id=pg_temp.fid('evidence.history.branch') and
 api.posted_journal_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),j.id)#>>'{journal,branch_status}'='inactive'),
 'permitted historical source branch stays readable after retirement');
update core.branches set status='active' where id=pg_temp.fid('evidence.history.branch');
-- Roll back temporary role narrowing even if a permission assertion fails.
create function pg_temp.evidence_branch_denial() returns boolean language plpgsql as $$declare denied boolean:=false;begin
 begin
  delete from core.role_assignments where tenant_id=pg_temp.fid('tenant') and membership_id=pg_temp.fid('creator.membership')
   and (legal_entity_id is null or branch_id is distinct from pg_temp.fid('branch'));
  begin
   perform api.posted_journal_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
    (select id from finance.journal_entries where source_id=pg_temp.fid('evidence.history')));
  exception when insufficient_privilege then denied:=true;end;
  raise exception using errcode='P0099',message='ROLLBACK_SYNTHETIC_SCOPE_PROBE';
 exception when sqlstate 'P0099' then null;end;
 return denied;
end$$;
insert into procurement_test_results select ok(pg_temp.evidence_branch_denial(),
 'finance permission in the working branch cannot authorize another source branch');
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='finance.view';
insert into procurement_test_results select throws_ok($$select pg_temp.journal_page('dim.journal.a')$$,
 '42501',null,'known posted journal rechecks revoked finance permission');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.view');
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='inventory.cost.view';
insert into procurement_test_results select throws_ok($$select api.posted_journal_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),(select j.id from finance.journal_entries j where j.tenant_id=pg_temp.fid('tenant')
 and j.legal_entity_id=pg_temp.fid('entity') and exists(select 1 from inventory.stock_movements m where m.tenant_id=j.tenant_id
 and m.legal_entity_id=j.legal_entity_id and m.command_id=j.command_id) limit 1))$$,
 '42501',null,'stock-linked ledger read cannot bypass revoked cost permission');
insert into procurement_test_results select is(pg_temp.journal_page('dim.journal.a')#>>'{journal,stock_cost_access_required}',
 'false','ordinary financial journal does not invent stock provenance');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.cost.view');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select pg_temp.journal_page('dim.journal.a')$$,'42501',null,'nonmember cannot resolve known journal');
set local role authenticated;
insert into procurement_test_results select is((select count(*) from finance.journal_entries),0::bigint,'existing raw header RLS still denies nonmembers');
insert into procurement_test_results select is((select count(*) from finance.journal_lines),0::bigint,'existing raw line RLS still denies nonmembers');
insert into procurement_test_results select throws_ok($$delete from finance.journal_lines$$,'42501',null,'reader grants no direct ledger mutation');
reset role;
select pg_temp.actor('creator');
insert into procurement_test_results select is((select provolatile::text from pg_proc where oid=
 'api.posted_journal_evidence(uuid,uuid,uuid,uuid,integer)'::regprocedure),'s','journal evidence uses one stable statement snapshot');

