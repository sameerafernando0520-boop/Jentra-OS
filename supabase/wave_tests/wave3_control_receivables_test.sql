set constraints all deferred;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid('actor'),'role','authenticated','aal','aal2')::text,true);
select set_config('request.jwt.claim.sub',pg_temp.fid('actor')::text,true);
create function pg_temp.control_ar(n text default 'control.ar',d text default '2026-09-21') returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fid(n),'kind','AR','as_of',d)$$;
create function pg_temp.reverse_ar(d text default '2026-09-21') returns jsonb language sql as $$select jsonb_build_object('allocation_id',(select id from finance.open_item_allocations where source_open_item_id=(select id from finance.open_items where source_id=pg_temp.fid('receipt')) order by id limit 1),'posting_date',d,'reason','Correct customer allocation')$$;
insert into flow_results values('control.ar',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_ar(),0,'control.ar'));
select is((select (result#>>'{entity,difference}')::numeric from flow_results where name='control.ar'),0::numeric,'AR report residual equals debit-positive controls');
select is((select (result#>>'{entity,difference_count}')::integer from flow_results where name='control.ar'),0,'AR source postings and realized FX reconcile by command');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('actor.role') and permission_code='finance.receipts.reverse';
select throws_ok($$select pg_temp.call('reverse_customer_allocation',pg_temp.reverse_ar())$$,'42501',null,'AR allocation permission does not imply reversal');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('actor.role'),'finance.receipts.reverse');
select throws_ok($$select pg_temp.call('reverse_customer_allocation',pg_temp.reverse_ar()||'{"reason":" "}')$$,'22023','ALLOCATION_REVERSAL_INVALID','AR reversal requires a reason');
select throws_ok($$select pg_temp.call('reverse_customer_allocation',pg_temp.reverse_ar('2026-09-01'))$$,'22023','ALLOCATION_REVERSAL_DATE_INVALID','AR reversal cannot predate original allocation');
insert into flow_results values('control.before.source',finance.flow_residual(pg_temp.fid('tenant'),(select id from finance.open_items where source_id=pg_temp.fid('receipt'))));
insert into flow_results values('control.reverse',pg_temp.call('reverse_customer_allocation',pg_temp.reverse_ar(),null,'control.reverse'));
select is(pg_temp.call('reverse_customer_allocation',pg_temp.reverse_ar(),null,'control.reverse'),(select result from flow_results where name='control.reverse'),'AR reversal exact retry creates no duplicates');
select throws_ok($$select pg_temp.call('reverse_customer_allocation',pg_temp.reverse_ar())$$,'55000','ALLOCATION_ALREADY_REVERSED','second AR reversal cannot reopen twice');
select is((select (result#>>'{entity,source_residual,base_amount}')::numeric from flow_results where name='control.reverse'),
 (select (result->>'base_amount')::numeric from flow_results where name='control.before.source')-(select source_base_amount from finance.open_item_allocations where id=(pg_temp.reverse_ar()->>'allocation_id')::uuid),'AR reversal restores exact source carrying value');
select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l where l.account_id=pg_temp.fid('exchange_gain') and l.journal_entry_id=(select journal_entry_id from finance.allocation_reversals where allocation_id=(pg_temp.reverse_ar()->>'allocation_id')::uuid)),
 (select exchange_difference from finance.open_item_allocations where id=(pg_temp.reverse_ar()->>'allocation_id')::uuid),'AR reversal negates exact realized exchange gain');
insert into flow_results values('control.ar.after',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_ar('control.ar.after'),0));
select is((select (result#>>'{entity,difference}')::numeric from flow_results where name='control.ar.after'),0::numeric,'AR controls remain reconciled after reversal');
select is((select (result#>>'{entity,difference_count}')::integer from flow_results where name='control.ar.after'),0,'AR reversal source effects reconcile individually');
insert into flow_results values('control.ar.old',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_ar('control.ar.old','2026-09-20'),0));
select is((select result#>>'{entity,subledger_value}' from flow_results where name='control.ar.old'),(select result#>>'{entity,subledger_value}' from flow_results where name='control.ar'),'earlier dated report retains original allocation effect');
select throws_ok($$select pg_temp.call('allocate_customer_receipt',jsonb_build_object('source_open_item_id',(select id from finance.open_items where source_id=pg_temp.fid('receipt')),'posting_date','2026-09-20','allocations',jsonb_build_array(jsonb_build_object('target_open_item_id',(select target_open_item_id from finance.open_item_allocations where id=(pg_temp.reverse_ar()->>'allocation_id')::uuid),'source_amount','1','transaction_amount','1'))))$$,'22023','ALLOCATION_DATE_BEFORE_LATEST','AR cannot backdate allocation ahead of reversal history');
-- Reallocate exact restored amount using remaining carrying values, not the original rounding distribution.
select lives_ok($$select pg_temp.call('allocate_customer_receipt',jsonb_build_object('source_open_item_id',(select source_open_item_id from finance.open_item_allocations where id=(pg_temp.reverse_ar()->>'allocation_id')::uuid),'posting_date','2026-09-21','allocations',jsonb_build_array((select jsonb_build_object('target_open_item_id',target_open_item_id,'source_amount',source_amount::text,'transaction_amount',transaction_amount::text) from finance.open_item_allocations where id=(pg_temp.reverse_ar()->>'allocation_id')::uuid))))$$,'AR restored carrying amount can be allocated again');
select is((select sum(base_debit-base_credit) from finance.journal_lines where account_id=pg_temp.fid('receivable_control')),(select sum((finance.flow_residual(tenant_id,id)->>'base_amount')::numeric) from finance.open_items where tenant_id=pg_temp.fid('tenant') and kind='AR'),'AR reallocation preserves exact control equality');

-- A newly mapped receipt settles an older-control invoice. Both controls must move.
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
 values(pg_temp.fid('control.new'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'AR-NEW','New AR control','asset','debit',pg_temp.fid('actor'),pg_temp.fid('actor'));
update finance.posting_mappings set account_id=pg_temp.fid('control.new') where tenant_id=pg_temp.fid('tenant') and purpose='receivable_control';
select pg_temp.save_submit('customer_receipt','control.receipt',pg_temp.header('control.receipt','2026-09-21')||jsonb_build_object('cash_bank_account_id',pg_temp.fid('bank.LKR'),'amount','50','external_reference','CONTROL-RECEIPT'));
select pg_temp.post('customer_receipt','control.receipt');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('actor.role'),'finance.receipts.adjust') on conflict do nothing;
insert into flow_results values('control.adjustment',pg_temp.call('allocate_customer_receipt',jsonb_build_object(
 'source_open_item_id',(select id from finance.open_items where source_id=pg_temp.fid('control.receipt')),'posting_date','2026-09-21',
 'allocations',jsonb_build_array(jsonb_build_object('target_open_item_id',(select id from finance.open_items where source_id=pg_temp.fid('invoice1')),
 'source_amount','50','transaction_amount','50','write_off','7.01','discount_amount','2.99','reason','Synthetic governed settlement adjustment')))));
insert into flow_results values('control.ar.remap',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_ar('control.ar.remap'),0));
select is((select (result#>>'{entity,difference_count}')::integer from flow_results where name='control.ar.remap'),0,'cross-control allocation and write-off reconcile by original account and command');
select is((select jsonb_array_length(result#>'{entity,accounts}') from flow_results where name='control.ar.remap'),2,'old and current mappings both appear in control basis');
select is((select count(*) from jsonb_array_elements((select result#>'{entity,accounts}' from flow_results where name='control.ar.remap'))x where (x->>'difference')::numeric<>0),0::bigint,'mapping changes cannot conceal account-level differences');
create function pg_temp.reverse_adjustment() returns jsonb language sql as $$select jsonb_build_object(
 'allocation_id',(select result#>>'{entity,allocations,0,allocation_id}' from flow_results where name='control.adjustment'),'posting_date','2026-09-21','reason','Reverse write-off and discount')$$;
create function pg_temp.reverse_in_locked_period() returns void language plpgsql as $$begin
 update finance.fiscal_periods set state='soft_locked' where id=pg_temp.fid('period');
 update finance.fiscal_periods set state='hard_locked' where id=pg_temp.fid('period');
 perform pg_temp.call('reverse_customer_allocation',pg_temp.reverse_adjustment());end $$;
select throws_ok($$select pg_temp.reverse_in_locked_period()$$,'55000',null,'hard period lock blocks AR correction and rolls back test lock');
insert into flow_results values('control.journal.count',jsonb_build_object('count',(select count(*) from finance.journal_entries where tenant_id=pg_temp.fid('tenant'))));
create trigger synthetic_control_reversal_failure before insert on core.outbox_events for each row execute function pg_temp.fail_outbox();
select throws_ok($$select pg_temp.call('reverse_customer_allocation',pg_temp.reverse_adjustment(),null,'control.adjustment.reverse')$$,'P0001','SYNTHETIC_OUTBOX_FAILURE','late AR reversal failure rolls back correction and journal');
drop trigger synthetic_control_reversal_failure on core.outbox_events;
select is((select count(*) from finance.journal_entries where tenant_id=pg_temp.fid('tenant')),(select (result->>'count')::bigint from flow_results where name='control.journal.count'),'late reversal failure leaves journal count unchanged');
select is((select count(*) from finance.allocation_reversals where allocation_id=(pg_temp.reverse_adjustment()->>'allocation_id')::uuid),0::bigint,'late reversal failure leaves no reversal history');
select lives_ok($$select pg_temp.call('reverse_customer_allocation',pg_temp.reverse_adjustment(),null,'control.adjustment.reverse')$$,'failed AR correction can retry same command successfully');
select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l where l.account_id in(pg_temp.fid('write_off'),pg_temp.fid('settlement_discount'))),0::numeric,'reversal negates both write-off and discount exactly');
insert into flow_results values('control.ar.corrected',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_ar('control.ar.corrected'),0));
select is((select (result#>>'{entity,difference_count}')::integer from flow_results where name='control.ar.corrected'),0,'corrected cross-control allocation still reconciles by source');

-- Synthetic orphan control lines must remain visible; report may never hide them.
select finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),
 'document_date','2026-09-21','customer_id',pg_temp.fid('customer'),'currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 (select jsonb_agg(line order by n,side) from generate_series(1,55)n cross join lateral(values
  (1,finance.flow_jline(pg_temp.fid('control.new'),0.000001,0.000001)),(2,finance.flow_jline(pg_temp.fid('revenue'),-0.000001,-0.000001)))x(side,line)),
 'synthetic_control_gap',pg_temp.fid('control.gap'),gen_random_uuid(),pg_temp.fid('control.gap.command'));
insert into flow_results values('control.ar.gap',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_ar('control.ar.gap'),0));
select is((select (result#>>'{entity,difference}')::numeric from flow_results where name='control.ar.gap'),-0.000055::numeric,'one-micro-unit orphan postings remain exact report differences');
select is((select (result#>>'{entity,difference_count}')::integer from flow_results where name='control.ar.gap'),1,'orphan GL command has a source difference');
select is(jsonb_array_length(api.control_reconciliation_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('control.ar.gap'),'journals',0,pg_temp.fid('control.new')::text)->'items'),50,'journal evidence page is bounded at fifty');
select is(api.control_reconciliation_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('control.ar.gap'),'journals',0,pg_temp.fid('control.new')::text)->>'next_cursor','50','journal evidence exposes continuation cursor');
select ok(jsonb_array_length(api.control_reconciliation_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('control.ar.gap'),'journals',50,pg_temp.fid('control.new')::text)->'items')>0,'later evidence page retains remaining journal lines');

-- Unequal cent distributions restored out of order must not strand carrying value.
create function pg_temp.cent_item(n text,sgn integer) returns void language plpgsql as $$
declare j uuid;c uuid:=gen_random_uuid();r uuid:=gen_random_uuid();begin
 j:=finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),
 'document_date','2026-09-21','customer_id',pg_temp.fid('customer'),'currency_code','USD','base_currency_code','LKR','exchange_rate','1.6666666667'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('control.new'),sgn*0.03,sgn*0.05),finance.flow_jline(pg_temp.fid('revenue'),-sgn*0.03,-sgn*0.05)),
 'synthetic_cent_item',pg_temp.fid(n),r,c);
 insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
 original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid(n),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'AR',pg_temp.fid('customer'),'synthetic_cent_item',pg_temp.fid(n),n,'USD','LKR',1.6666666667,
 sgn*0.03,sgn*0.05,'2026-09-21','2026-09-21',j,r,c,r,pg_temp.fid('actor'));end $$;
select pg_temp.cent_item('cent.source',-1);select pg_temp.cent_item('cent.target',1);
create function pg_temp.cent_allocate() returns jsonb language sql as $$select pg_temp.call('allocate_customer_receipt',jsonb_build_object(
 'source_open_item_id',pg_temp.fid('cent.source'),'posting_date','2026-09-21','allocations',jsonb_build_array(jsonb_build_object(
 'target_open_item_id',pg_temp.fid('cent.target'),'source_amount','0.01','transaction_amount','0.01'))))$$;
insert into flow_results values('cent.first',pg_temp.cent_allocate());select pg_temp.cent_allocate();
select pg_temp.call('reverse_customer_allocation',jsonb_build_object('allocation_id',(select result#>>'{entity,allocations,0,allocation_id}' from flow_results where name='cent.first'),
 'posting_date','2026-09-21','reason','Restore an earlier rounding share'));
select pg_temp.cent_allocate();select pg_temp.cent_allocate();
select is((finance.flow_residual(pg_temp.fid('tenant'),pg_temp.fid('cent.source'))->>'base_amount')::numeric,0::numeric,'out-of-order restored AR cents fully settle without stranded source base');
select is((finance.flow_residual(pg_temp.fid('tenant'),pg_temp.fid('cent.target'))->>'base_amount')::numeric,0::numeric,'out-of-order restored AR cents fully settle without stranded target base');
