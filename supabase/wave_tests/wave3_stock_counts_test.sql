-- Included in the same rollback-only, separately namespaced inventory fixture.
select pg_temp.actor('actor');
-- Count cutoff uses today's UTC clock; supply only the missing synthetic day
-- without changing the original transfer period or its lifecycle.
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
select pg_temp.fid('count.current.period'),pg_temp.fid('t'),pg_temp.fid('e'),'Synthetic current count day',
 (current_timestamp at time zone 'UTC')::date,(current_timestamp at time zone 'UTC')::date,pg_temp.fid('actor'),pg_temp.fid('actor')
where not exists(select 1 from finance.fiscal_periods where tenant_id=pg_temp.fid('t') and legal_entity_id=pg_temp.fid('e')
 and (current_timestamp at time zone 'UTC')::date between start_date and end_date);
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('t'),pg_temp.fid('r'),'inventory.adjustments.post') on conflict do nothing;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid(n),pg_temp.fid('t'),pg_temp.fid('e'),c,n,k,b,pg_temp.fid('actor'),pg_temp.fid('actor')
from (values('inventory-account','1300','asset','debit'),('variance-account','5300','expense','debit'))v(n,c,k,b);
update inventory.products set inventory_account_id=pg_temp.fid('inventory-account') where tenant_id=pg_temp.fid('t');
create function pg_temp.count_payload(n text default 'count',q text default '8') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(n),'warehouse_id',pg_temp.fid('w'),'document_date',(clock_timestamp() at time zone 'UTC')::date,
 'reason','Cycle count discrepancy','offset_account_id',pg_temp.fid('variance-account'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(n||'.line'),'product_id',pg_temp.fid('plain'),'counted_quantity',q,'empty_unit_cost','0')))$$;
create function pg_temp.count_call(rpc text,p jsonb,v bigint default null,k text default null) returns jsonb language plpgsql as $$
declare r jsonb;key uuid:=coalesce(pg_temp.fid(k),gen_random_uuid());begin
 execute format('select api.%I($1,$2,$3,$4,$5,$6,$7,$8)',rpc) into r using pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),key,key,now(),p,v;
 return r;end $$;
create function pg_temp.count_version(n text default 'count') returns bigint language sql as $$select version from inventory.stock_counts where id=pg_temp.fid(n)$$;
create function pg_temp.count_action(a text,n text default 'count') returns jsonb language sql as $$select jsonb_build_object('document_id',pg_temp.fid(n),'action',a,'reason','Reviewed count action')$$;
insert into responses values('count',pg_temp.count_call('upsert_stock_count',pg_temp.count_payload(),null,'count-save'));
insert into transfer_results select is((select lines->0->>'baseline_quantity' from inventory.stock_counts where id=pg_temp.fid('count')),'10.000000','count captures exact cutoff baseline');
insert into transfer_results select is((select lines->0->>'variance_quantity' from inventory.stock_counts where id=pg_temp.fid('count')),'-2.000000','count computes signed exact variance');
insert into transfer_results select is(pg_temp.count_call('upsert_stock_count',pg_temp.count_payload(),null,'count-save'),(select r from responses where name='count'),'count save identical replay');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.count_payload('numeric-count'),'{lines,0,counted_quantity}','8'))$$,'22023','counted_quantity must be a decimal string.','count rejects numeric JSON');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.count_payload('tracked-count'),'{lines,0,product_id}',to_jsonb(pg_temp.fid('serial'))))$$,'22023','COUNT_TRACKED_CAPTURE_REQUIRED','tracked count requires explicit identity cutoff');
insert into transfer_results select throws_ok($$select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post'),1)$$,'55000','COUNT_APPROVAL_REQUIRED','unapproved count cannot post');
insert into transfer_results select throws_ok($$select pg_temp.count_call('transition_stock_count',pg_temp.count_action('submit'),1)$$,'55000','WORKFLOW_CONFIGURATION_ERROR','count requires configured workflow');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values(pg_temp.fid('approver'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','approver@count.jentra.test','',now(),now(),now());
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.fid('approver.member'),pg_temp.fid('t'),pg_temp.fid('approver'),'active');
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.fid('approver.role'),pg_temp.fid('t'),'count-approver','Count approver',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('t'),pg_temp.fid('approver.role'),p from unnest(array['inventory.cost.view','workflow.approvals.decide'])p;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('t'),pg_temp.fid('r'),'workflow.approvals.decide');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('t'),pg_temp.fid('approver.member'),pg_temp.fid('approver.role'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('actor'));
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.fid('count.workflow'),pg_temp.fid('t'),pg_temp.fid('e'),'stock_count','Count workflow','active',
'{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","posted"]],"posting_transitions":[["submitted","draft"],["approved","draft"]],"requires_approval":true}',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('count.step'),pg_temp.fid('t'),pg_temp.fid('count.workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'stock_count','COUNT-',pg_temp.fid('actor'),pg_temp.fid('actor'));
select pg_temp.count_call('transition_stock_count',pg_temp.count_action('submit'),1);
insert into transfer_results select throws_ok($$select pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('count'),'decision','approved'),2)$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','count creator cannot self approve');
select pg_temp.actor('approver','aal1');
insert into transfer_results select throws_ok($$select pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('count'),'decision','approved'),2)$$,'42501',null,'count approval requires MFA');
select pg_temp.actor('approver');
select pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('count'),'decision','approved'),2);
select pg_temp.actor('actor');
-- A real intervening movement must survive count posting: 10 - 1 - 2 = 7.
select pg_temp.call(pg_temp.payload('after-count','immediate','plain','1'));
insert into transfer_results select throws_ok($$select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post'),3)$$,'55000',null,'missing journal sequence rolls back stock adjustment');
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('plain.bal')),9::numeric,'failed count posting preserves intervening movement');
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'journal_entry','COUNT-JRN-',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into responses values('count-post',pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post'),3,'count-post'));
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('plain.bal')),7::numeric,'count applies cutoff variance instead of replacing current stock');
insert into transfer_results select is(pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post'),3,'count-post'),(select r from responses where name='count-post'),'count posting replay creates no second adjustment');
insert into transfer_results select is((select sum(base_debit-base_credit) from finance.journal_lines where tenant_id=pg_temp.fid('t')),0::numeric,'count journal balances exactly');
insert into transfer_results select is((select base_debit from finance.journal_lines where tenant_id=pg_temp.fid('t') and account_id=pg_temp.fid('variance-account')),20.024691::numeric,'count posts exact variance expense');
insert into transfer_results select throws_ok($$update inventory.stock_counts set reason='changed' where id=pg_temp.fid('count')$$,'55000',null,'posted count is immutable');
set constraints all immediate;
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',pg_temp.count_payload('bad-correction')||jsonb_build_object('corrects_count_id',pg_temp.fid('missing')))$$,'22023','COUNT_CORRECTION_SOURCE_INVALID','correction source must be a posted scoped count');
select pg_temp.count_call('upsert_stock_count',pg_temp.count_payload('correction','6')||jsonb_build_object('corrects_count_id',pg_temp.fid('count')));
insert into transfer_results select is((select corrects_count_id from inventory.stock_counts where id=pg_temp.fid('correction')),pg_temp.fid('count'),'correction retains original posted count link');
select pg_temp.count_call('transition_stock_count',pg_temp.count_action('submit','correction'),1);
select pg_temp.actor('approver');
select pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('correction'),'decision','approved'),2);
select pg_temp.actor('actor');
update inventory.stock_valuations set carrying_value=carrying_value+1 where stock_balance_id=pg_temp.fid('plain.bal');
insert into transfer_results select throws_ok($$select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','correction'),3)$$,'55000','COUNT_REAPPROVAL_REQUIRED','valuation drift cannot bypass approved amount');
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('plain.bal')),7::numeric,'valuation drift failure preserves stock');
update inventory.stock_valuations set carrying_value=carrying_value-1 where stock_balance_id=pg_temp.fid('plain.bal');
update inventory.stock_balances set allocated_quantity=7 where id=pg_temp.fid('plain.bal');
insert into transfer_results select throws_ok($$select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','correction'),3)$$,'55000','COUNT_RESERVED_STOCK_UNAVAILABLE','approved count still cannot consume new reservations');
update inventory.stock_balances set allocated_quantity=0 where id=pg_temp.fid('plain.bal');
select pg_temp.count_call('upsert_stock_count',pg_temp.count_payload('capture','0')||'{"capture_only":true}');
insert into transfer_results select is((select lines->0->>'counted_quantity' from inventory.stock_counts where id=pg_temp.fid('capture')),'7.000000','capture mode initializes physical count to locked baseline');
insert into transfer_results select is((select lines->0->>'variance_quantity' from inventory.stock_counts where id=pg_temp.fid('capture')),'0.000000','capturing cutoff creates no artificial shortage');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',pg_temp.count_payload('capture','6'),99)$$,'40001','VERSION_CONFLICT','stale count edit rejected');
select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.count_payload('capture','6'),'{lines,0,baseline_quantity}','"999"'),1);
insert into transfer_results select is((select lines->0->>'baseline_quantity' from inventory.stock_counts where id=pg_temp.fid('capture')),'7.000000','caller cannot replace captured baseline');
insert into transfer_results select throws_ok($$select pg_temp.count_call('upsert_stock_count',jsonb_set(pg_temp.count_payload('capture','6'),'{lines,0,line_id}',to_jsonb(pg_temp.fid('replacement'))),2)$$,'22023','COUNT_BASELINE_IMMUTABLE','captured line identity cannot be replaced');
insert into transfer_results select is(jsonb_array_length(api.stock_count_options(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'accounts')->'items'),1,'count picker only exposes eligible expense accounts');
select pg_temp.actor('outsider');
set local role authenticated;
insert into transfer_results select is((select count(*) from api.stock_counts),0::bigint,'count register RLS denies outsider');
insert into transfer_results select throws_ok($$insert into inventory.stock_counts(id) values(gen_random_uuid())$$,'42501',null,'direct count writes denied');
reset role;
select pg_temp.actor('actor');
insert into transfer_results select pass('count and transfer deferred constraints hold');
-- Exercise both other signed-delta paths through independent approval and posting.
set constraints all deferred;
select pg_temp.count_call('upsert_stock_count',pg_temp.count_payload('surplus','8'));
select pg_temp.count_call('transition_stock_count',pg_temp.count_action('submit','surplus'),1);
select pg_temp.actor('approver');
select pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('surplus'),'decision','approved'),2);
select pg_temp.actor('actor');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','surplus'),3);
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('plain.bal')),8::numeric,'approved surplus adds exact quantity');
insert into transfer_results select is((select jl.base_debit from finance.journal_lines jl join finance.journal_entries j on j.id=jl.journal_entry_id where j.source_id=pg_temp.fid('surplus') and jl.account_id=pg_temp.fid('inventory-account')),10.012346::numeric,'approved surplus debits inventory at frozen exact cost');
select pg_temp.count_call('upsert_stock_count',pg_temp.count_payload('zero','8'));
select pg_temp.count_call('transition_stock_count',pg_temp.count_action('submit','zero'),1);
select pg_temp.actor('approver');
select pg_temp.count_call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('zero'),'decision','approved'),2);
select pg_temp.actor('actor');
select pg_temp.count_call('post_stock_adjustment',pg_temp.count_action('post','zero'),3);
insert into transfer_results select is((select status from inventory.stock_counts where id=pg_temp.fid('zero')),'posted','zero variance count retains approved posted evidence');
insert into transfer_results select ok((select journal_entry_id is null and stock_movement_id is null from inventory.stock_counts where id=pg_temp.fid('zero')),'zero variance creates no artificial journal or movement');
set constraints all immediate;
