-- Real synthetic commands and deliberately damaged copies exist only until rollback.
set constraints all deferred;
select pg_temp.actor('creator');
insert into procurement_responses values('grni.baseline',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.baseline','GRNI','2026-09-25'),0));
insert into procurement_test_results select is((select (response#>>'{entity,difference}')::numeric from procurement_responses where name='grni.baseline'),0::numeric,'GRNI legacy receipts matches unbilled returns and reversals reconcile');
insert into procurement_test_results select is((select (response#>>'{entity,difference_count}')::integer from procurement_responses where name='grni.baseline'),0,'GRNI legacy source identities reconcile individually');
insert into procurement_test_results select is(jsonb_array_length(pg_temp.control_page('grni.baseline','allocations')->'items'),0,'GRNI has no AR/AP allocation corrections');
insert into procurement_test_results select is((select value->>'open_base_amount' from jsonb_array_elements(pg_temp.control_page('grni.baseline','items')->'items')value where value->>'id'=pg_temp.fid('unbilled-receipt')::text),'0.000000','unbilled return plus subsequent bill exhaust original receipt exactly');
insert into procurement_test_results select ok(not exists(select 1 from jsonb_array_elements(pg_temp.control_page('grni.baseline','entries')->'items')value where value->>'source_id'=pg_temp.fid('purchase-return')::text),'bill-linked return never reduces GRNI a second time');

create function pg_temp.grni_order(n text,c text default 'LKR',r text default '1') returns void language plpgsql as $$begin
 perform pg_temp.call('upsert_purchase_requisition',jsonb_set(pg_temp.header(n||'.req'),'{lines,0,product_id}',to_jsonb(pg_temp.fid('product'))));
 perform pg_temp.transition(n||'.req','{"action":"submit"}');
 perform pg_temp.actor('approver');perform pg_temp.transition(n||'.req','{"decision":"approved"}');perform pg_temp.actor('creator');
 if c<>'LKR' then
  insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,target_currency_code,rate,effective_date,created_by,updated_by)
  values(pg_temp.fid(n||'.rate'),pg_temp.fid('tenant'),pg_temp.fid('entity'),c,'LKR',r::numeric,'2026-09-22',pg_temp.fid('creator'),pg_temp.fid('creator'));
 end if;
 perform pg_temp.call('upsert_purchase_order',pg_temp.direct_po()||jsonb_build_object('id',pg_temp.fid(n),'source_requisition_id',pg_temp.fid(n||'.req'),
  'document_date','2026-09-22','rate_date','2026-09-22','currency_code',c,'exchange_rate',r,'exchange_rate_id',case when c<>'LKR' then pg_temp.fid(n||'.rate') end,
  'lines',jsonb_build_array((pg_temp.direct_po()#>'{lines,0}')||jsonb_build_object(
  'line_id',pg_temp.fid(n||'.line'),'source_line_id',pg_temp.fid(n||'.req.line'),'unit_price','0.111111'))));
 perform pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid(n),'action','submit'),1);
 perform pg_temp.actor('approver');perform pg_temp.call('transition_purchase_order',jsonb_build_object('document_id',pg_temp.fid(n),'decision','approved'),2);perform pg_temp.actor('creator');
end $$;
create function pg_temp.grni_receipt(n text,o text,q text,d text) returns jsonb language sql as $$select pg_temp.gr(n,q,'0')||jsonb_build_object(
 'order_id',pg_temp.fid(o),'document_date',d,'lines',jsonb_build_array((pg_temp.gr(n,q,'0')#>'{lines,0}')||jsonb_build_object('order_line_id',pg_temp.fid(o||'.line'))))$$;
update inventory.products set tracking_mode='none' where id=pg_temp.fid('product');
select pg_temp.grni_order('grni.po','USD','3.333333');
select pg_temp.call('post_goods_receipt',pg_temp.grni_receipt('grni.receipt','grni.po','3','2026-09-22'),3);
insert into procurement_test_results select is((select grni_account_id from procurement.goods_receipts where id=pg_temp.fid('grni.receipt')),pg_temp.fid('grni-account'),'new receipt freezes its original journal GRNI account');
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.fid('grni.new.account'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'2399','New GRNI','liability','credit',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_receipt_controls',jsonb_build_object('id',pg_temp.fid('entity'),'grni_account_id',pg_temp.fid('grni.new.account'),'expense_account_id',pg_temp.fid('expense-account')),
 (select version from procurement.receipt_controls where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')));
select pg_temp.call('post_purchase_return',pg_temp.purchase_return('grni.return','grni.receipt','grni.receipt.line','1','receipt')||'{"document_date":"2026-09-23"}');
insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,target_currency_code,rate,effective_date,created_by,updated_by)
values(pg_temp.fid('grni.bill.rate'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'USD','LKR',4,'2026-09-24',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_supplier_bill',pg_temp.bill('grni.bill','0.111111')||jsonb_build_object('supplier_id',pg_temp.fid('supplier_b'),
 'document_date','2026-09-24','currency_code','USD','exchange_rate_id',pg_temp.fid('grni.bill.rate'),
 'lines',jsonb_build_array((pg_temp.bill('grni.bill','0.111111')#>'{lines,0}')||jsonb_build_object('receipt_line_id',pg_temp.fid('grni.receipt.line'),'quantity','2','discount_percent','0'))));
select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('grni.bill')),1);
insert into procurement_responses values('grni.d22',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.d22','GRNI','2026-09-22'),0));
insert into procurement_responses values('grni.d23',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.d23','GRNI','2026-09-23'),0));
insert into procurement_responses values('grni.d24',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.d24','GRNI','2026-09-24'),0));
insert into procurement_test_results select is((select (value->>'open_base_amount')::numeric from jsonb_array_elements(pg_temp.control_page('grni.d22','items')->'items')value where value->>'id'=pg_temp.fid('grni.receipt')::text),1.100000::numeric,'FX receipt before dated return and bill remains fully accrued at entity precision');
insert into procurement_test_results select is((select (value->>'open_base_amount')::numeric from jsonb_array_elements(pg_temp.control_page('grni.d23','items')->'items')value where value->>'id'=pg_temp.fid('grni.receipt')::text),0.730000::numeric,'cutoff includes exact original-rate return but excludes later bill');
insert into procurement_test_results select is((select (value->>'open_base_amount')::numeric from jsonb_array_elements(pg_temp.control_page('grni.d24','items')->'items')value where value->>'id'=pg_temp.fid('grni.receipt')::text),0::numeric,'return and different-rate bill exhaust cumulative original GRNI basis');
insert into procurement_test_results select is((select detail->>'grni_account_id' from procurement.supplier_bill_lines where id=pg_temp.fid('grni.bill.line')),pg_temp.fid('grni-account')::text,'bill keeps original GRNI despite setup change');
insert into procurement_test_results select is((select (response#>>'{entity,difference_count}')::integer from procurement_responses where name='grni.d24'),0,'different-rate bill and original-basis return reconcile every source');
insert into procurement_test_results select is(pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.replay','GRNI','2026-09-24'),0,'grni.replay'),pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.replay','GRNI','2026-09-24'),0,'grni.replay'),'GRNI command exact replay preserves saved snapshot');
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.replay','GRNI','2026-09-23'),0,'grni.replay')$$,'22023',null,'GRNI replay refuses a changed cutoff');

select pg_temp.grni_order('grni.reverse.po');
select pg_temp.call('post_goods_receipt',pg_temp.grni_receipt('grni.reverse.receipt','grni.reverse.po','1','2026-09-23'),3);
select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('grni.reverse.receipt'),'document_date','2026-09-24','reason','Synthetic duplicate receipt'),1);
insert into procurement_responses values('grni.reversed',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.reversed','GRNI','2026-09-24'),0));
insert into procurement_test_results select is((select (value->>'open_base_amount')::numeric from jsonb_array_elements(pg_temp.control_page('grni.reversed','items')->'items')value where value->>'id'=pg_temp.fid('grni.reverse.receipt')::text),0::numeric,'dated linked reversal clears receipt without deleting history');
insert into procurement_test_results select is((select (response#>>'{entity,difference_count}')::integer from procurement_responses where name='grni.reversed'),0,'reversal original account and source GL reconcile');
insert into procurement_test_results select is((select (value->>'open_base_amount')::numeric from jsonb_array_elements(pg_temp.control_page('grni.d22','items')->'items')value where value->>'id'=pg_temp.fid('grni.receipt')::text),1.100000::numeric,'later backdated activity cannot rewrite the saved cutoff');

-- Independent GL adjustments offset at account level but remain two differences.
select finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),
 'document_date','2026-09-24','currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('grni.new.account'),-1,-1),finance.flow_jline(pg_temp.fid('expense-account'),1,1)),
 'grni_control_fixture',pg_temp.fid('grni.extra.1'),gen_random_uuid(),gen_random_uuid());
select finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),
 'document_date','2026-09-24','currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('grni.new.account'),1,1),finance.flow_jline(pg_temp.fid('expense-account'),-1,-1)),
 'grni_control_fixture',pg_temp.fid('grni.extra.2'),gen_random_uuid(),gen_random_uuid());
insert into procurement_responses values('grni.offset',pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.offset','GRNI','2026-09-24'),0));
insert into procurement_test_results select is((select (response#>>'{entity,difference}')::numeric from procurement_responses where name='grni.offset'),0::numeric,'offsetting journals can have a zero aggregate difference');
insert into procurement_test_results select is((select (response#>>'{entity,difference_count}')::integer from procurement_responses where name='grni.offset'),2,'offsetting unrelated journal sources remain two explicit differences');
insert into procurement_test_results select is(jsonb_array_length(pg_temp.control_page('grni.offset','differences',pg_temp.fid('grni.new.account')::text)->'items'),2,'account drill preserves both net-zero differences');
-- Damage only synthetic copies, then roll back to the savepoint before invariants.
set constraints all immediate;
create function pg_temp.grni_damage_probe() returns jsonb language plpgsql as $$declare r jsonb;begin
 begin
  alter table finance.journal_lines disable trigger user;
  delete from finance.journal_lines where journal_entry_id=(select journal_entry_id from procurement.goods_receipts where id=pg_temp.fid('grni.receipt')) and account_id=pg_temp.fid('grni-account');
  r:=finance.build_control_report(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.control_payload('grni.missing','GRNI','2026-09-24'));
  raise exception using errcode='Z0001',message='ROLL_BACK_SYNTHETIC_DAMAGE';
 exception when sqlstate 'Z0001' then null;end;
 return r;end $$;
insert into procurement_responses values('grni.missing',pg_temp.grni_damage_probe());
insert into procurement_test_results select is((select (response#>>'{summary,difference}')::numeric from procurement_responses where name='grni.missing'),1.100000::numeric,'frozen receipt basis exposes a missing original GL credit independently');
insert into procurement_test_results select is((select count(*) from procurement_responses,jsonb_array_elements(response->'differences')value where name='grni.missing' and value->>'source_id'=pg_temp.fid('grni.receipt')::text),1::bigint,'missing receipt journal keeps operational source attribution');

set constraints all deferred;
insert into procurement_test_results select throws_ok($$select finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),
 'document_date','2026-09-24','currency_code','USD','base_currency_code','LKR','exchange_rate','0.000001'),
 jsonb_build_array(finance.flow_jline(pg_temp.fid('grni-account'),-0.01,0),finance.flow_jline(pg_temp.fid('expense-account'),0.01,0)),
 'goods_receipt',pg_temp.fid('grni.zero.base'),gen_random_uuid(),gen_random_uuid())$$,
 '22023','AMOUNT_BELOW_BASE_PRECISION','GRNI extension preserves the journal engine minimum base precision guard');
insert into procurement_test_results select is((select count(*) from finance.journal_entries where source_id=pg_temp.fid('grni.zero.base')),0::bigint,'below-base-precision receipt leaves no partial journal');
set constraints all immediate;

-- A large synthetic receipt population must abort rather than truncate evidence.
create function pg_temp.grni_input_limit_probe() returns void language plpgsql as $$begin
 insert into procurement.goods_receipts(id,tenant_id,legal_entity_id,branch_id,order_id,order_revision,warehouse_id,document_date,document_number,reference,source_snapshot,
  currency_code,base_currency_code,exchange_rate,net_amount,base_amount,stock_movement_id,journal_entry_id,request_id,command_id,created_by)
 select gen_random_uuid(),r.tenant_id,r.legal_entity_id,r.branch_id,r.order_id,r.order_revision,r.warehouse_id,r.document_date,'BOUND-'||n,r.reference,r.source_snapshot,
  r.currency_code,r.base_currency_code,r.exchange_rate,0,0,null,null,gen_random_uuid(),gen_random_uuid(),r.created_by
 from procurement.goods_receipts r cross join generate_series(1,10001)n where r.id=pg_temp.fid('grni.receipt');
 perform pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.oversized','GRNI','2026-09-24'),0);
end $$;
insert into procurement_test_results select throws_ok($$select pg_temp.grni_input_limit_probe()$$,'54000','CONTROL_REPORT_INPUT_LIMIT','oversized GRNI source population aborts without a partial report');
insert into procurement_test_results select is((select count(*) from finance.control_reports where id=pg_temp.fid('grni.oversized')),0::bigint,'oversized command leaves no saved report');
set constraints all deferred;
do $$begin for i in 1..51 loop
 perform finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),
  'document_date','2026-09-24','currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
  jsonb_build_array(finance.flow_jline(pg_temp.fid('grni.new.account'),-1,-1),finance.flow_jline(pg_temp.fid('expense-account'),1,1)),
  'grni_control_fixture',pg_temp.fid('grni.page.'||i),gen_random_uuid(),gen_random_uuid());
end loop;end $$;
select pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.paged','GRNI','2026-09-24'),0);
insert into procurement_test_results select is(jsonb_array_length(pg_temp.control_page('grni.paged','differences',pg_temp.fid('grni.new.account')::text)->'items'),50,'GRNI evidence returns at most fifty source differences');
insert into procurement_test_results select is(pg_temp.control_page('grni.paged','differences',pg_temp.fid('grni.new.account')::text)->>'next_cursor','50','GRNI account drill exposes an independent deterministic continuation');
insert into procurement_test_results select is(jsonb_array_length(api.control_reconciliation_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('grni.paged'),'differences',50,pg_temp.fid('grni.new.account')::text)->'items'),3,'second GRNI page retains every remaining source difference');
insert into procurement_test_results select throws_ok($$select api.control_reconciliation_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('grni.paged'),'entries',50001)$$,'22023','CONTROL_REPORT_PAGE_INVALID','GRNI page refuses an oversized offset');
set constraints all immediate;

create trigger synthetic_grni_outbox_failure before insert on core.outbox_events for each row execute function pg_temp.fail_control_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.call('generate_control_reconciliation_report',pg_temp.control_payload('grni.failed','GRNI'),0)$$,'P0001','CONTROL_OUTBOX_FAILURE','late GRNI outbox failure rolls back the snapshot');
drop trigger synthetic_grni_outbox_failure on core.outbox_events;
insert into procurement_test_results select is((select count(*) from finance.control_reports where id=pg_temp.fid('grni.failed')),0::bigint,'late GRNI failure leaves no private report');
insert into procurement_test_results select throws_ok($$update finance.control_reports set summary='{}' where id=pg_temp.fid('grni.offset')$$,'55000',null,'GRNI saved evidence is immutable');
insert into procurement_test_results select throws_ok($$select api.control_reconciliation_report_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('trace.hiddenbranch'),pg_temp.fid('grni.offset'),'items')$$,'42501',null,'known GRNI report cannot cross branch scope');
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.control_page('grni.offset','items')$$,'42501',null,'GRNI reads enforce existing privileged MFA policy');
select pg_temp.actor('creator');
delete from core.role_permissions where tenant_id=pg_temp.fid('tenant') and role_id=pg_temp.fid('creator.role') and permission_code='finance.controls.reconcile';
insert into procurement_test_results select throws_ok($$select pg_temp.control_page('grni.offset','entries')$$,'42501',null,'revocation denies frozen GRNI evidence');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'finance.controls.reconcile');
set local role authenticated;
insert into procurement_test_results select throws_ok($$select finance.receipt_grni_control(pg_temp.fid('tenant'),pg_temp.fid('grni.receipt'))$$,'42501',null,'private GRNI basis helper cannot bypass public scope checks');
reset role;
set constraints all immediate;
