-- Synthetic dimensions; used by both phased and final-stack rollback builders.
set constraints all deferred;
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select pg_temp.fid('tenant'),pg_temp.fid(who||'.role'),p from unnest(array['creator','approver'])who
 cross join unnest(array['finance.dimensions.manage','finance.budgets.manage','finance.budgets.approve'])p on conflict do nothing;
create function pg_temp.dim_payload(n text,k text default 'cost_centre',branch uuid default null) returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fid(n),'kind',k,'code',upper(replace(n,'.','-')),
 'name','Governed '||n,'status','active','reason','Synthetic governed dimension','dimension_branch_id',branch)$$;
create function pg_temp.dim_call(n text,p jsonb,v bigint) returns jsonb language sql as $$
 select pg_temp.call('financial_dimension_command',p,v,n)$$;
insert into procurement_responses values('dim.a',pg_temp.dim_call('dim.a',pg_temp.dim_payload('dim.a'),0));
select pg_temp.dim_call('dim.b',pg_temp.dim_payload('dim.b','cost_centre',pg_temp.fid('branch')),0);
select pg_temp.dim_call('dim.p',pg_temp.dim_payload('dim.p','project'),0);
insert into procurement_test_results select is(pg_temp.dim_call('dim.a',pg_temp.dim_payload('dim.a'),0),
 (select response from procurement_responses where name='dim.a'),'dimension command replays exactly');
insert into procurement_test_results select throws_ok($$select pg_temp.dim_call('dim.a',pg_temp.dim_payload('dim.a')||'{"name":"Changed replay"}',0)$$,
 '22023',null,'dimension changed replay rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.dim_call('dim.stale',pg_temp.dim_payload('dim.a'),0)$$,
 '40001',null,'dimension optimistic version enforced');
insert into procurement_test_results select throws_ok($$select pg_temp.dim_call('dim.kind',pg_temp.dim_payload('dim.a','project'),1)$$,
 '22023','DIMENSION_IDENTITY_IMMUTABLE','dimension kind cannot change');
insert into procurement_test_results select throws_ok($$select pg_temp.dim_call('dim.cross',pg_temp.dim_payload('dim.cross','cost_centre',pg_temp.fid('budget.other.branch')),0)$$,
 '42501',null,'cross-branch dimension creation denied');
insert into procurement_test_results select throws_ok($$delete from finance.dimensions where id=pg_temp.fid('dim.a')$$,
 '55000',null,'dimension identity cannot be deleted');
insert into procurement_test_results select throws_ok($$update finance.dimension_events set snapshot='{}' where dimension_id=pg_temp.fid('dim.a')$$,
 '55000',null,'dimension events are immutable');
insert into procurement_test_results select is(jsonb_array_length(api.financial_dimensions(pg_temp.fid('tenant'),pg_temp.fid('entity'),
 pg_temp.fid('branch'),'cost_centre')->'items'),2,'bounded named picker includes entity and selected branch dimensions');

create function pg_temp.dim_mj(n text,cost text) returns jsonb language sql as $$
 select jsonb_set(jsonb_set(pg_temp.mj_payload(n),'{lines,0,cost_centre_id}',to_jsonb(pg_temp.fid(cost))),
 '{lines,0,project_id}',to_jsonb(pg_temp.fid('dim.p')))$$;
select pg_temp.call('upsert_manual_journal',pg_temp.dim_mj('dim.journal.a','dim.a'),0);
insert into procurement_test_results select is((select snapshot#>>'{lines,0,dimension_snapshot,cost_centre,version}'
 from finance.manual_journals where id=pg_temp.fid('dim.journal.a')),'1','journal freezes the governed dimension version');
select pg_temp.mj_act('dim.journal.a','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('dim.journal.a','{"decision":"approved"}');
select pg_temp.mj_act('dim.journal.a','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_test_results select is((select cost_centre_id from finance.journal_lines where source_line_id=pg_temp.fid('dim.journal.a.debit')),
 pg_temp.fid('dim.a'),'posted journal receives source-proven cost centre identity');
insert into procurement_test_results select is((select project_id from finance.journal_lines where source_line_id=pg_temp.fid('dim.journal.a.debit')),
 pg_temp.fid('dim.p'),'posted journal receives source-proven project identity');
insert into procurement_test_results select is((select base_debit from finance.journal_lines where source_line_id=pg_temp.fid('dim.journal.a.debit')),
 123.456789::numeric,'governed dimensions preserve exact journal amounts');
insert into procurement_test_results select ok(not exists(select 1 from finance.journal_lines where source_line_id=pg_temp.fid('mj.first.debit')
 and cost_centre_id is not null),'legacy descriptive label acquires no invented identity');
insert into procurement_test_results select throws_ok($$update finance.journal_lines set cost_centre_id=null
 where source_line_id=pg_temp.fid('dim.journal.a.debit')$$,'55000',null,'posted dimension attribution is immutable');
select pg_temp.call('upsert_manual_journal',pg_temp.dim_mj('dim.journal.b','dim.b'),0);
select pg_temp.mj_act('dim.journal.b','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('dim.journal.b','{"decision":"approved"}');
select pg_temp.mj_act('dim.journal.b','{}','post_manual_journal');
select pg_temp.actor('creator');
create function pg_temp.dim_budget(n text) returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fid(n),'action','create','budget_year',2026,'branch_id',pg_temp.fid('branch'),
 'currency_code','LKR','reason','Dimension-specific annual budget','lines',jsonb_build_array(
 jsonb_build_object('id',pg_temp.fid(n||'.a'),'account_id',pg_temp.fid('mj.debit'),'amount','123.456789',
  'cost_centre_id',pg_temp.fid('dim.a'),'project_id',pg_temp.fid('dim.p')),
 jsonb_build_object('id',pg_temp.fid(n||'.b'),'account_id',pg_temp.fid('mj.debit'),'amount','125',
  'cost_centre_id',pg_temp.fid('dim.b'),'project_id',pg_temp.fid('dim.p'))))$$;
select pg_temp.call('budget_command',pg_temp.dim_budget('dim.budget'),0);
insert into procurement_test_results select is(jsonb_array_length((select lines from finance.budget_versions where id=pg_temp.fid('dim.budget'))),2,
 'disjoint dimension budget can repeat a posting account');
insert into procurement_test_results select throws_ok($$select pg_temp.call('budget_command',
 jsonb_set(pg_temp.dim_budget('dim.overlap'),'{lines,1,cost_centre_id}','null'),0)$$,
 '22023','BUDGET_DIMENSION_OVERLAP','aggregate wildcard cannot double-count a targeted budget line');
insert into procurement_test_results select throws_ok($$select pg_temp.call('budget_command',
 jsonb_set(pg_temp.dim_budget('dim.entity.plan'),'{branch_id}','null'),0)$$,
 '22023','BUDGET_DIMENSION_UNAVAILABLE','entity-wide budget cannot consume a branch-only dimension');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',
 jsonb_set(pg_temp.dim_mj('dim.wrong.kind','dim.p'),'{lines,0,project_id}','null'),0)$$,
 '22023','BUDGET_DIMENSION_UNAVAILABLE','project identity cannot impersonate a cost centre');
select pg_temp.call('budget_command',pg_temp.dim_budget('dim.budget')||'{"action":"submit"}',1);
select pg_temp.actor('approver');
select pg_temp.call('budget_command',pg_temp.dim_budget('dim.budget')||'{"action":"approve"}',2);
select pg_temp.actor('creator');
insert into procurement_responses values('dim.variance',pg_temp.call('generate_budget_variance',jsonb_build_object('id',pg_temp.fid('dim.variance'),
 'budget_id',pg_temp.fid('dim.budget'),'as_of','2026-09-25'),0));
insert into procurement_test_results select is((select response#>>'{entity,actual_total}' from procurement_responses where name='dim.variance'),
 '246.913578','variance includes governed exact actuals and excludes unassigned history');
insert into procurement_test_results select is((select evidence#>>'{lines,0,actual_amount}' from finance.budget_variance_reports where id=pg_temp.fid('dim.variance')),
 '123.456789','individual cost centre actual does not include a different cost centre');
insert into procurement_test_results select ok(not exists(select 1 from finance.budget_variance_reports r,
 lateral jsonb_array_elements(r.evidence->'journals')x where r.id=pg_temp.fid('dim.variance') and x->>'dimension_snapshot' is null),
 'dimension variance journal evidence retains its frozen master basis');

-- Rename blocks approval reuse, while a linked reversal uses original historical identity.
select pg_temp.call('upsert_manual_journal',pg_temp.dim_mj('dim.drift','dim.a'),0);
select pg_temp.mj_act('dim.drift','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('dim.drift','{"decision":"approved"}');
select pg_temp.actor('creator');
select pg_temp.dim_call('dim.rename',pg_temp.dim_payload('dim.a')||'{"name":"Renamed governed centre"}',1);
select pg_temp.actor('approver');
insert into procurement_test_results select throws_ok($$select pg_temp.mj_act('dim.drift','{}','post_manual_journal')$$,
 '55000','JOURNAL_REAPPROVAL_REQUIRED','renamed master invalidates approved journal basis');
select pg_temp.actor('creator');
select pg_temp.dim_call('dim.retire',pg_temp.dim_payload('dim.a')||'{"name":"Renamed governed centre","status":"retired"}',2);
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_manual_journal',pg_temp.dim_mj('dim.retired.source','dim.a'),0)$$,
 '22023','BUDGET_DIMENSION_UNAVAILABLE','retired master cannot enter a new posting basis');
select pg_temp.call('upsert_manual_journal',pg_temp.mj_payload('dim.reverse')||jsonb_build_object('reversal_of_id',pg_temp.fid('dim.journal.a')),0);
insert into procurement_test_results select is((select snapshot#>>'{lines,0,dimension_snapshot,cost_centre,version}'
 from finance.manual_journals where id=pg_temp.fid('dim.reverse')),'1','linked reversal retains original master version after retirement');
select pg_temp.mj_act('dim.reverse','{"action":"submit"}');
select pg_temp.actor('approver');
select pg_temp.mj_act('dim.reverse','{"decision":"approved"}');
select pg_temp.mj_act('dim.reverse','{}','post_manual_journal');
select pg_temp.actor('creator');
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines
 where cost_centre_id=pg_temp.fid('dim.a') and account_id=pg_temp.fid('mj.debit')),0::numeric,'linked reversal cancels original exact dimensional actual');
insert into procurement_test_results select is((select summary->>'actual_total' from finance.budget_variance_reports where id=pg_temp.fid('dim.variance')),
 '246.913578','later reversal leaves the saved variance unchanged');
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='finance.dimensions.manage';
insert into procurement_test_results select throws_ok($$select pg_temp.dim_call('dim.a',pg_temp.dim_payload('dim.a'),0)$$,
 '42501',null,'known dimension receipt replay rechecks current management access');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.financial_dimensions(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'cost_centre')$$,
 '42501',null,'dimension catalog denies nonmembers');
select pg_temp.actor('creator');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select * from finance.dimensions$$,'42501',null,'private dimensions are not directly readable');
insert into procurement_test_results select throws_ok($$select finance.dimension_basis(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('dim.b'),'cost_centre')$$,
 '42501',null,'private dimension helper is not client-callable');
reset role;
set constraints all deferred;

-- A late command failure cannot retain a master or its history.
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.dimensions.manage') on conflict do nothing;
create function pg_temp.fail_dimension_outbox() returns trigger language plpgsql as $$begin
 if new.topic='finance.dimension.saved' then raise exception using errcode='P0001',message='DIMENSION_OUTBOX_FAILURE';end if;return new;end$$;
create trigger fail_dimension_outbox before insert on core.outbox_events for each row execute function pg_temp.fail_dimension_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.dim_call('dim.fault',pg_temp.dim_payload('dim.fault'),0)$$,
 'P0001','DIMENSION_OUTBOX_FAILURE','late dimension failure rolls back master creation');
drop trigger fail_dimension_outbox on core.outbox_events;
insert into procurement_test_results select is((select count(*)::integer from finance.dimensions where id=pg_temp.fid('dim.fault')),0,
 'late dimension failure retains no master');
insert into procurement_test_results select is((select count(*)::integer from finance.dimension_events where dimension_id=pg_temp.fid('dim.fault')),0,
 'late dimension failure retains no event');

-- A renamed master requires a newly saved budget basis before submission.
select pg_temp.call('budget_command',pg_temp.dim_budget('dim.budget.drift')||
 jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('id',pg_temp.fid('dim.budget.drift.line'),
  'account_id',pg_temp.fid('mj.debit'),'amount','0.000001','cost_centre_id',pg_temp.fid('dim.b')))),0);
select pg_temp.dim_call('dim.b.rename',pg_temp.dim_payload('dim.b','cost_centre',pg_temp.fid('branch'))||'{"name":"Renamed branch centre"}',1);
insert into procurement_test_results select throws_ok($$select pg_temp.call('budget_command',
 pg_temp.dim_budget('dim.budget.drift')||'{"action":"submit"}',1)$$,
 '55000','BUDGET_DIMENSION_REAPPROVAL_REQUIRED','master rename blocks submission of a stale budget basis');

-- Export preserves dimensional source identity and exact money from the saved report.
select pg_temp.call('budget_command',pg_temp.dim_budget('dim.budget.approval.drift')||
 jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('id',pg_temp.fid('dim.budget.approval.drift.line'),
  'account_id',pg_temp.fid('mj.debit'),'amount','0.000001','cost_centre_id',pg_temp.fid('dim.b')))),0);
select pg_temp.call('budget_command',pg_temp.dim_budget('dim.budget.approval.drift')||'{"action":"submit"}',1);
select pg_temp.dim_call('dim.b.rename.after.submit',pg_temp.dim_payload('dim.b','cost_centre',pg_temp.fid('branch'))||'{"name":"Changed after budget submission"}',2);
select pg_temp.actor('approver');
insert into procurement_test_results select throws_ok($$select pg_temp.call('budget_command',
 pg_temp.dim_budget('dim.budget.approval.drift')||'{"action":"approve"}',2)$$,
 '55000','BUDGET_DIMENSION_REAPPROVAL_REQUIRED','master drift after submission cannot obtain budget approval');
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.reports.export') on conflict do nothing;
insert into procurement_test_results select ok((api.report_export_preview(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 'budget',pg_temp.fid('dim.variance'),'journals','{}')->>'canonical_text')::jsonb#>>'{rows,0,dimension_snapshot,cost_centre,id}' is not null,
 'bounded export retains frozen dimensional journal evidence');
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.dim_call('dim.mfa',pg_temp.dim_payload('dim.mfa'),0)$$,
 '42501',null,'privileged dimension management retains existing MFA requirements');
select pg_temp.actor('creator');
set constraints all deferred;
