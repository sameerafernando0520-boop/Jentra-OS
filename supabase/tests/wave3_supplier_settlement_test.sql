set constraints all deferred;
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select api.supplier_payment_reference_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'payment_banks')$$,'42501',null,'payment references require the payment capability');
insert into procurement_test_results select has_function('api','upsert_payment_proposal',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-312 payment proposal command exists');
insert into procurement_test_results select has_function('api','post_supplier_payment',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'AC-312 recorded payment command exists');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid(x||'.role'),p from unnest(array['creator','approver']) x
cross join unnest(array['finance.payments.manage','finance.payments.post']) p on conflict do nothing;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.fid('payment-cash-gl'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'1100','Synthetic bank','asset','debit',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
values(pg_temp.fid('payment-bank'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'PAYTEST','Synthetic payment bank','bank',pg_temp.fid('payment-cash-gl'),'LKR',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),t,'PAYTEST-',pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['payment_proposal','supplier_payment']) t;
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.fid('payment-workflow'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'payment_proposal','Synthetic payment approval','active',
'{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","cancelled"]],"posting_transitions":[["submitted","draft"],["approved","draft"],["approved","posted"]],"requires_approval":true}',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('payment-step'),pg_temp.fid('tenant'),pg_temp.fid('payment-workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('creator'),pg_temp.fid('creator'));
create function pg_temp.proposal(p_name text default 'payment',p_amount text default '100') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(p_name),'supplier_id',pg_temp.fid('supplier_b'),'cash_bank_account_id',pg_temp.fid('payment-bank'),'document_date','2026-09-14','exchange_rate_id',null,
 'lines',jsonb_build_array(jsonb_build_object('open_item_id',(select id from finance.open_items where source_id=pg_temp.fid('direct-bill')),'amount',p_amount)))$$;
create function pg_temp.payment_transition(p_name text,p_extra jsonb) returns jsonb language sql as $$select pg_temp.call('transition_payment_proposal',
 jsonb_build_object('document_id',pg_temp.fid(p_name))||p_extra,(select version from procurement.payment_proposals where id=pg_temp.fid(p_name)))$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_payment_proposal',pg_temp.proposal()||'{"document_date":"2026-09-13"}')$$,'22023','PAYABLE_ITEM_INELIGIBLE','payment proposal excludes not-yet-due bill');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_payment_proposal',jsonb_set(pg_temp.proposal(),'{lines,0,amount}','100'))$$,'22023',null,'payment rejects floating JSON numbers');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_payment_proposal',pg_temp.proposal('payment','295.31'))$$,'22023','PROPOSAL_AMOUNT_EXCEEDED','payment cannot exceed exact AP residual');
insert into procurement_responses values('payment-save',pg_temp.call('upsert_payment_proposal',pg_temp.proposal(),null,'payment-save'));
insert into procurement_test_results select is(pg_temp.call('upsert_payment_proposal',pg_temp.proposal(),null,'payment-save'),(select response from procurement_responses where name='payment-save'),'payment proposal save is replay safe');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_payment_proposal',pg_temp.proposal('competing-payment'))$$,'55000','PAYABLE_ITEM_ALREADY_SELECTED','two active proposals cannot claim the same payable');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_supplier_payment',jsonb_build_object('document_id',pg_temp.fid('payment'),'reference','Synthetic recorded transfer'),1)$$,'55000','PAYMENT_APPROVAL_REQUIRED','draft proposal cannot record a payment');
select pg_temp.payment_transition('payment','{"action":"submit"}');
insert into procurement_test_results select throws_ok($$select pg_temp.payment_transition('payment','{"decision":"approved"}')$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','proposal creator cannot self approve');
select pg_temp.actor('approver','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.payment_transition('payment','{"decision":"approved"}')$$,'42501',null,'payment approval enforces MFA role');
select pg_temp.actor('approver');select pg_temp.payment_transition('payment','{"decision":"approved"}');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_payment_proposal',pg_temp.proposal('payment','50'),3)$$,'55000','PROPOSAL_NOT_EDITABLE','approved payment cannot change without recall and reapproval');
-- A late failure must roll back the journal, AP item, allocations and state together.
update core.document_sequences set status='inactive' where tenant_id=pg_temp.fid('tenant') and document_type='supplier_payment';
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_supplier_payment',jsonb_build_object('document_id',pg_temp.fid('payment'),'reference','Synthetic recorded transfer'),3)$$,'55000',null,'missing payment number fails atomically after journal construction');
insert into procurement_test_results select is((select count(*)::integer from finance.journal_entries where source_type='supplier_payment' and source_id=pg_temp.fid('payment')),0,'failed payment leaves no journal');
insert into procurement_test_results select is((select count(*)::integer from finance.open_items where source_type='supplier_payment'),0,'failed payment leaves no AP credit');
update core.document_sequences set status='active' where tenant_id=pg_temp.fid('tenant') and document_type='supplier_payment';
insert into procurement_responses values('payment-post',pg_temp.call('post_supplier_payment',jsonb_build_object('document_id',pg_temp.fid('payment'),'reference','Synthetic recorded transfer'),3,'payment-post'));
insert into procurement_test_results select is(pg_temp.call('post_supplier_payment',jsonb_build_object('document_id',pg_temp.fid('payment'),'reference','Synthetic recorded transfer'),3,'payment-post'),(select response from procurement_responses where name='payment-post'),'recorded payment replay retains original allocations');
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'amount' from finance.open_items where source_id=pg_temp.fid('direct-bill'))::numeric,195.30::numeric,'partial payment leaves exact bill residual');
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'amount' from finance.open_items where source_id=pg_temp.fid('payment'))::numeric,0::numeric,'recorded payment is fully allocated');
insert into procurement_test_results select is((select base_credit from finance.journal_lines where journal_entry_id=(select journal_entry_id from procurement.supplier_payments where id=pg_temp.fid('payment')) and account_id=pg_temp.fid('payment-cash-gl')),100::numeric,'recorded payment credits configured bank exactly');
insert into procurement_test_results select is((select count(*)::integer from procurement.payment_claims where proposal_id=pg_temp.fid('payment') and active),0,'recording releases active claims');
insert into procurement_test_results select throws_ok($$update procurement.supplier_payments set reference='overwrite' where id=pg_temp.fid('payment')$$,'55000',null,'recorded payment evidence is immutable');
insert into procurement_test_results select lives_ok('set constraints all immediate','payment journal and allocation constraints hold');
set constraints all deferred;
select pg_temp.call('upsert_payment_proposal',pg_temp.proposal('recall-payment','50'));
select pg_temp.payment_transition('recall-payment','{"action":"submit"}');
select pg_temp.payment_transition('recall-payment','{"action":"recall","reason":"Review selected amount"}');
insert into procurement_test_results select is((select count(*)::integer from procurement.payment_claims where proposal_id=pg_temp.fid('recall-payment') and active),0,'recall releases payment claims');
select pg_temp.call('upsert_payment_proposal',pg_temp.proposal('other-payment','50'));
insert into procurement_test_results select throws_ok($$select pg_temp.payment_transition('recall-payment','{"action":"submit"}')$$,'55000','PAYABLE_ITEM_ALREADY_SELECTED','resubmission cannot reacquire another proposal claim');
select pg_temp.payment_transition('other-payment','{"action":"cancel","reason":"No longer required"}');
select pg_temp.payment_transition('recall-payment','{"action":"submit"}');
select pg_temp.actor('approver');select pg_temp.payment_transition('recall-payment','{"decision":"rejected","reason":"Payment date incorrect"}');
insert into procurement_test_results select is((select count(*)::integer from procurement.payment_claims where proposal_id=pg_temp.fid('recall-payment') and active),0,'rejection releases payment claims without deleting history');
select pg_temp.actor('creator');
insert into procurement_test_results select is((api.supplier_statement(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('supplier_b'),'LKR','2026-09-13')->>'open_amount')::numeric,295.30::numeric,'dated AP statement excludes the later payment and its allocation');
insert into procurement_test_results select is(jsonb_array_length(api.supplier_statement(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('supplier_b'),'LKR','2026-09-13')->'rows'),1,'supplier statement retains only posted AP documents as of its date');
insert into procurement_test_results select throws_ok($$select api.supplier_statement(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('supplier_b'),'LKR','2026-09-14',array[60,30])$$,'22023','STATEMENT_FILTER_INVALID','AP aging rejects unsorted buckets');
-- Additional AP aging and permission checks use only this rollback fixture.
select pg_temp.call('upsert_supplier_bill',jsonb_set(jsonb_set(jsonb_set(jsonb_set(pg_temp.direct_bill('overdue-bill'),'{document_date}','"2026-09-01"'),'{due_date}','"2026-09-01"'),'{lines,0,unit_price}','"10"'),'{lines,0,tax_definition_id}','null'));
select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('overdue-bill')),1);
insert into procurement_test_results select is((select (x->>'amount')::numeric from jsonb_array_elements(api.supplier_statement(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('supplier_b'),'LKR','2026-09-14',array[7,14,30])->'aging') x where x->>'bucket'='2'),20::numeric,'AP aging places thirteen-day overdue balance in configured 8-14 day bucket');
insert into procurement_test_results select is((api.supplier_payment_reference_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'payment_banks')#>>'{items,0,currency_code}'),'LKR','payment bank picker returns the scoped account currency');
insert into procurement_test_results select is(jsonb_array_length(api.supplier_payment_reference_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'payment_items',null,'',pg_temp.fid('supplier_b'),pg_temp.fid('payment-bank'),'2026-09-30')->'items'),2,'due picker returns exact open bills without settled payment');
select pg_temp.actor('outsider');set local role authenticated;
insert into procurement_test_results select is((select count(*)::integer from api.payment_proposals),0,'outsider cannot read payment proposals');
insert into procurement_test_results select is((select count(*)::integer from api.supplier_payments),0,'outsider cannot read recorded payments');
insert into procurement_test_results select is((select count(*)::integer from api.payable_balances),0,'outsider cannot read AP balances');
insert into procurement_test_results select throws_ok($$insert into procurement.payment_claims(id) values(gen_random_uuid())$$,'42501',null,'authenticated direct payment-claim writes denied');
insert into procurement_test_results select throws_ok($$select api.supplier_statement(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('supplier_b'),'LKR','2026-09-14')$$,'42501',null,'known supplier ID does not bypass statement scope');
reset role;select pg_temp.actor('creator');
insert into procurement_test_results select lives_ok('set constraints all immediate','settlement and aging fixtures retain all deferred invariants');
set constraints all deferred;
select pg_temp.call('upsert_payment_proposal',pg_temp.proposal('future-payment','50')||jsonb_build_object('document_date',((clock_timestamp() at time zone 'UTC')::date+1)::text));
select pg_temp.payment_transition('future-payment','{"action":"submit"}');
select pg_temp.actor('approver');select pg_temp.payment_transition('future-payment','{"decision":"approved"}');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_supplier_payment',jsonb_build_object('document_id',pg_temp.fid('future-payment'),'reference','Future instruction'),3)$$,'22023','FUTURE_POSTING_DATE','future-dated approved proposal cannot record a completed payment');
select pg_temp.payment_transition('future-payment','{"action":"cancel","reason":"Future instruction only"}');
insert into procurement_test_results select lives_ok('set constraints all immediate','future payment rejection has no ledger side effects');
set constraints all deferred;
create function pg_temp.reverse_allocation_payload() returns jsonb language sql as $$select jsonb_build_object(
 'allocation_id',(select (allocations->0->>'allocation_id')::uuid from procurement.supplier_payments where id=pg_temp.fid('payment')),
 'posting_date','2026-09-14','reason','Correct settlement allocation')$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_supplier_allocation',pg_temp.reverse_allocation_payload())$$,'42501',null,'payment posting permission does not imply allocation reversal');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),p from unnest(array['finance.payments.allocate','finance.payments.reverse'])p;
insert into procurement_responses values('allocation-reversal',pg_temp.call('reverse_supplier_allocation',pg_temp.reverse_allocation_payload(),null,'allocation-reversal'));
insert into procurement_test_results select is(pg_temp.call('reverse_supplier_allocation',pg_temp.reverse_allocation_payload(),null,'allocation-reversal'),(select response from procurement_responses where name='allocation-reversal'),'allocation reversal exact replay');
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'amount' from finance.open_items where source_id=pg_temp.fid('direct-bill'))::numeric,295.30::numeric,'reversal reopens exact original bill allocation');
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'amount' from finance.open_items where source_id=pg_temp.fid('payment'))::numeric,-100::numeric,'reversal restores unapplied supplier payment');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_supplier_allocation',pg_temp.reverse_allocation_payload())$$,'55000','ALLOCATION_ALREADY_REVERSED','second reversal cannot reopen balances twice');
insert into procurement_test_results select throws_ok($$delete from finance.allocation_reversals where tenant_id=pg_temp.fid('tenant')$$,'55000',null,'allocation reversal history is immutable');
create function pg_temp.allocate_ap(p_amount text default '100') returns jsonb language sql as $$select jsonb_build_object('source_open_item_id',
 (select id from finance.open_items where source_id=pg_temp.fid('payment')),'posting_date','2026-09-14','reason','Allocate corrected payment',
 'allocations',jsonb_build_array(jsonb_build_object('target_open_item_id',(select id from finance.open_items where source_id=pg_temp.fid('direct-bill')),
 'source_amount',p_amount,'transaction_amount',p_amount)))$$;
insert into procurement_test_results select throws_ok($$select pg_temp.call('allocate_supplier_credit',pg_temp.allocate_ap('100.01'))$$,'22023','ALLOCATION_EXCEEDED','independent AP allocation cannot exceed reopened credit');
insert into procurement_responses values('allocation-corrected',pg_temp.call('allocate_supplier_credit',pg_temp.allocate_ap(),null,'allocation-corrected'));
insert into procurement_test_results select is(pg_temp.call('allocate_supplier_credit',pg_temp.allocate_ap(),null,'allocation-corrected'),(select response from procurement_responses where name='allocation-corrected'),'independent AP allocation exact replay');
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'amount' from finance.open_items where source_id=pg_temp.fid('direct-bill'))::numeric,195.30::numeric,'corrected AP allocation closes only selected exact amount');
insert into procurement_test_results select is((select count(*)::integer from finance.open_item_allocations where tenant_id=pg_temp.fid('tenant')),2,'original and corrected allocations are both retained');
insert into procurement_test_results select lives_ok('set constraints all immediate','allocation corrections retain ledger constraints');
set constraints all deferred;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid(n),pg_temp.fid('tenant'),pg_temp.fid('entity'),c,n,t,b,pg_temp.fid('creator'),pg_temp.fid('creator')
from(values('payment-fx-loss','5900','expense','debit'),('payment-fx-gain','4900','revenue','credit'))x(n,c,t,b);
insert into finance.posting_mappings(tenant_id,legal_entity_id,purpose,account_id,created_by,updated_by)
select pg_temp.fid('tenant'),pg_temp.fid('entity'),p,pg_temp.fid(n),pg_temp.fid('creator'),pg_temp.fid('creator') from(values('exchange_loss','payment-fx-loss'),('exchange_gain','payment-fx-gain'))x(p,n);
insert into finance.exchange_rates(id,tenant_id,legal_entity_id,source_currency_code,target_currency_code,rate,effective_date,created_by,updated_by)
values(pg_temp.fid('pay-rate300'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'USD','LKR',300,'2026-09-01',pg_temp.fid('creator'),pg_temp.fid('creator')),
(pg_temp.fid('pay-rate310'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'USD','LKR',310,'2026-09-02',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into finance.cash_bank_accounts(id,tenant_id,legal_entity_id,branch_id,code,name,account_kind,account_id,currency_code,created_by,updated_by)
values(pg_temp.fid('payment-usd-bank'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'PAYUSD','Synthetic USD bank','bank',pg_temp.fid('payment-cash-gl'),'USD',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_supplier_bill',jsonb_set(jsonb_set(pg_temp.direct_bill('usd-bill')||jsonb_build_object('currency_code','USD','exchange_rate_id',pg_temp.fid('pay-rate300'),'due_date','2026-09-13'),'{lines,0,unit_price}','"10"'),'{lines,0,tax_definition_id}','null'));
select pg_temp.call('post_supplier_bill',jsonb_build_object('document_id',pg_temp.fid('usd-bill')),1);
select pg_temp.call('upsert_payment_proposal',jsonb_set(pg_temp.proposal('usd-payment','20')||jsonb_build_object('cash_bank_account_id',pg_temp.fid('payment-usd-bank'),'exchange_rate_id',pg_temp.fid('pay-rate310'),'document_date','2026-09-13'),
 '{lines,0,open_item_id}',to_jsonb((select id from finance.open_items where source_id=pg_temp.fid('usd-bill')))));
select pg_temp.payment_transition('usd-payment','{"action":"submit"}');select pg_temp.actor('approver');select pg_temp.payment_transition('usd-payment','{"decision":"approved"}');select pg_temp.actor('creator');
select pg_temp.call('post_supplier_payment',jsonb_build_object('document_id',pg_temp.fid('usd-payment'),'reference','USD bank reference'),3);
insert into procurement_test_results select is((select (allocations->0->>'exchange_difference')::numeric from procurement.supplier_payments where id=pg_temp.fid('usd-payment')),200::numeric,'supplier payment recognizes original-versus-settlement FX loss');
select pg_temp.call('reverse_supplier_allocation',jsonb_build_object('allocation_id',(select (allocations->0->>'allocation_id')::uuid from procurement.supplier_payments where id=pg_temp.fid('usd-payment')),'posting_date','2026-09-14','reason','Reallocate foreign-currency payment'));
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l where l.account_id=pg_temp.fid('payment-fx-loss')),0::numeric,'FX reversal offsets the original exchange loss exactly');
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'base_amount' from finance.open_items where source_id=pg_temp.fid('usd-payment'))::numeric,-6200::numeric,'FX reversal restores original payment carrying value');
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'base_amount' from finance.open_items where source_id=pg_temp.fid('usd-bill'))::numeric,6000::numeric,'FX reversal restores original bill carrying value');
insert into procurement_test_results select lives_ok('set constraints all immediate','FX allocation and reversal journals balance');
insert into procurement_test_results select is((api.supplier_statement(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('supplier_b'),'USD','2026-09-13')->>'open_base_amount')::numeric,0::numeric,'statement before FX reversal retains original settled base balance');
insert into procurement_test_results select is((api.payable_item_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),(select open_item_id from procurement.supplier_payments where id=pg_temp.fid('usd-payment')))#>>'{allocations,0,reversal,reason}'),'Reallocate foreign-currency payment','AP detail exposes immutable linked reversal evidence');
insert into procurement_test_results select is(jsonb_array_length(api.payable_allocation_rates(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'USD','LKR','2026-09-14')->'items'),2,'cross-currency allocation picker returns governed dated conversion rates');
set constraints all deferred;
select pg_temp.call('allocate_supplier_credit',jsonb_build_object('source_open_item_id',(select open_item_id from procurement.supplier_payments where id=pg_temp.fid('usd-payment')),
 'posting_date','2026-09-14','reason','Apply USD credit to LKR bill','allocations',jsonb_build_array(jsonb_build_object(
 'target_open_item_id',(select id from finance.open_items where source_id=pg_temp.fid('direct-bill')),'source_amount','0.5','transaction_amount','150','exchange_rate_id',pg_temp.fid('pay-rate300')))));
insert into procurement_test_results select is((select finance.flow_residual(tenant_id,id)->>'amount' from finance.open_items where source_id=pg_temp.fid('direct-bill'))::numeric,45.30::numeric,'cross-currency allocation consumes the exact converted bill amount');
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l where l.account_id=pg_temp.fid('payment-fx-loss')),5::numeric,'cross-currency allocation recognizes exact carrying-value difference');
insert into procurement_test_results select lives_ok('set constraints all immediate','cross-currency correction balances all journals');
