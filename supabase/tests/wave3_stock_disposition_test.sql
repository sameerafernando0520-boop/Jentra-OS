-- Procurement suite synthetic identities only. The outer builder finishes strictly and rolls back.
select pg_temp.actor('creator');
set constraints all deferred;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),p from unnest(array['inventory.dispositions.post','inventory.cost.view'])p on conflict do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('approver.role'),'inventory.cost.view') on conflict do nothing;
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,inventory_account_id,created_by,updated_by)
select pg_temp.fid('disp.'||p),pg_temp.fid('tenant'),pg_temp.fid('entity'),'DISP-'||upper(p),'Disposition '||p,'stocked',
pg_temp.fid('unit'),case when p='plain' then 'none' else p end,pg_temp.fid('inventory-account'),pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['plain','lot','serial'])p;
insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
select pg_temp.fid('disp.'||p||'.balance'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),
pg_temp.fid('disp.'||p),0,pg_temp.fid('creator'),pg_temp.fid('creator') from unnest(array['plain','lot','serial'])p;
insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
select pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('disp.'||p||'.balance'),100.123456,
pg_temp.fid('creator'),pg_temp.fid('creator') from unnest(array['plain','lot','serial'])p;
insert into inventory.lots(id,tenant_id,legal_entity_id,product_id,code,expiry_date,created_by,updated_by)
values(pg_temp.fid('disp.lot.id'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('disp.lot'),'DISP-EXPIRED','2026-01-01',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('disp.lot'),pg_temp.fid('disp.lot.id'),0,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into inventory.serials(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,code,created_by,updated_by)
select pg_temp.fid('disp.s'||i),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('disp.serial'),
'DISP-S'||i,pg_temp.fid('creator'),pg_temp.fid('creator') from generate_series(1,10)i;
-- Receipt movements seed the same provenance trigger as posted procurement receipts.
do $$declare p text;begin
foreach p in array array['plain','lot','serial'] loop
 update inventory.stock_balances set on_hand_quantity=10 where id=pg_temp.fid('disp.'||p||'.balance');
 if p='lot' then update inventory.lot_balances set on_hand_quantity=10 where lot_id=pg_temp.fid('disp.lot.id');end if;
 insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
 values(pg_temp.fid('disp.'||p||'.receipt'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'goods_receipt',pg_temp.fid('disp.'||p||'.receipt'),
 pg_temp.fid('warehouse'),'2026-09-29','goods_receipt',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),pg_temp.fid('creator'));
 insert into inventory.stock_movement_lines(id,tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,
 base_quantity,base_value,lot_id,serial_ids,posting_date,created_by)
 values(pg_temp.fid('disp.'||p||'.receipt.line'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('disp.'||p||'.receipt'),
 pg_temp.fid('warehouse'),pg_temp.fid('disp.'||p),pg_temp.fid('disp.'||p||'.receipt.line'),10,100.123456,
 case when p='lot' then pg_temp.fid('disp.lot.id') end,
 case when p='serial' then array(select pg_temp.fid('disp.s'||i) from generate_series(1,10)i) else '{}'::uuid[] end,'2026-09-29',pg_temp.fid('creator'));
end loop;end $$;
create function pg_temp.disposition_payload(n text,p text default 'plain',q text default '3') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(n),'warehouse_id',pg_temp.fid('warehouse'),'document_date','2026-09-29','reason','Damaged or expired stock reviewed',
 'offset_account_id',pg_temp.fid('expense-account'),'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(n||'.line'),
 'product_id',pg_temp.fid('disp.'||p),'unit_id',pg_temp.fid('unit'),'quantity',q,'conversion_numerator','1','conversion_denominator','1',
 'lot_id',case when p='lot' then pg_temp.fid('disp.lot.id') end,
 'serial_ids',case when p='serial' then jsonb_build_array(pg_temp.fid('disp.s1'),pg_temp.fid('disp.s2'),pg_temp.fid('disp.s3')) else '[]'::jsonb end)))$$;
create function pg_temp.disposition_version(n text) returns bigint language sql as $$select version from inventory.stock_dispositions where id=pg_temp.fid(n)$$;
create function pg_temp.disposition_action(n text,a text) returns jsonb language sql as $$select jsonb_build_object('document_id',pg_temp.fid(n),'action',a,'reason','Reviewed disposition command')$$;
create function pg_temp.disposition_reverse(n text,source text) returns jsonb language sql as $$select (pg_temp.disposition_payload(n)-'lines')||jsonb_build_object('reverses_disposition_id',pg_temp.fid(source))$$;
create function pg_temp.disposition_approve(n text) returns void language plpgsql as $$begin
 perform pg_temp.actor('creator');
 perform pg_temp.call('transition_stock_disposition',pg_temp.disposition_action(n,'submit'),pg_temp.disposition_version(n));
 perform pg_temp.actor('approver');
 perform pg_temp.call('transition_stock_disposition',jsonb_build_object('document_id',pg_temp.fid(n),'decision','approved'),pg_temp.disposition_version(n));
 perform pg_temp.actor('creator');
end $$;
insert into procurement_test_results select has_function('api','post_stock_disposition',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'permitted disposition RPC exists');
insert into procurement_responses values('disp.save',pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.one'),null,'disp.save'));
insert into procurement_test_results select is(pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.one'),null,'disp.save'),(select response from procurement_responses where name='disp.save'),'disposition draft replay identical');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.one')||'{"reason":"Changed reason"}',null,'disp.save')$$,'22023','IDEMPOTENCY_MISMATCH','changed replay rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',jsonb_set(pg_temp.disposition_payload('disp.numeric'),'{lines,0,quantity}','3'))$$,'22023','quantity must be a decimal string.','disposition rejects numeric JSON');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.one','post'),1)$$,'55000','DISPOSITION_APPROVAL_REQUIRED','unapproved disposition cannot post');
insert into procurement_test_results select throws_ok($$select pg_temp.call('transition_stock_disposition',pg_temp.disposition_action('disp.one','submit'),1)$$,'55000','WORKFLOW_CONFIGURATION_ERROR','missing configuration fails closed');
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.fid('disp.workflow'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'inventory_disposition','Disposition workflow','active',
'{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"],["approved","posted"]],"posting_transitions":[["submitted","draft"],["approved","draft"]],"requires_approval":true}',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into procurement_test_results select throws_ok($$select pg_temp.call('transition_stock_disposition',pg_temp.disposition_action('disp.one','submit'),1)$$,'55000','WORKFLOW_CONFIGURATION_ERROR','approval requires configured matrix');
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('disp.step'),pg_temp.fid('tenant'),pg_temp.fid('disp.workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.cancel.draft'));
select pg_temp.call('transition_stock_disposition',pg_temp.disposition_action('disp.cancel.draft','cancel'),1);
insert into procurement_test_results select is((select status from inventory.stock_dispositions where id=pg_temp.fid('disp.cancel.draft')),'cancelled','draft cancellation resolves configured lifecycle despite JSON null snapshot');
insert into procurement_test_results select is(api.stock_dispositions_page(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'branch_id',pg_temp.fid('branch')::text,'disposition register echoes exact requested branch');
insert into procurement_test_results select is(api.stock_disposition_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'accounts')->>'resource','accounts','disposition picker echoes approved resource');
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'inventory_disposition','DISP-',pg_temp.fid('creator'),pg_temp.fid('creator'));
select pg_temp.call('transition_stock_disposition',pg_temp.disposition_action('disp.one','submit'),1);
insert into procurement_test_results select throws_ok($$select pg_temp.call('transition_stock_disposition',jsonb_build_object('document_id',pg_temp.fid('disp.one'),'decision','approved'),2)$$,'42501','SEGREGATION_OF_DUTIES_VIOLATION','creator cannot approve disposition');
select pg_temp.actor('approver','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.call('transition_stock_disposition',jsonb_build_object('document_id',pg_temp.fid('disp.one'),'decision','approved'),2)$$,'42501',null,'approval enforces configured MFA');
select pg_temp.actor('approver');
select pg_temp.call('transition_stock_disposition',jsonb_build_object('document_id',pg_temp.fid('disp.one'),'decision','approved'),2);
select pg_temp.actor('creator');
insert into procurement_test_results select is((select grand_total from inventory.stock_dispositions where id=pg_temp.fid('disp.one')),30.037037::numeric,'approved preview freezes exact pre-issue pooled cost');
create function pg_temp.disposition_late_failure() returns trigger language plpgsql as $$begin
 if new.topic='inventory.stock_disposition.post' then raise exception 'DISPOSITION_OUTBOX_FAILURE';end if;return new;end $$;
create trigger disposition_late_failure before insert on core.outbox_events for each row execute function pg_temp.disposition_late_failure();
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.one','post'),3)$$,'P0001','DISPOSITION_OUTBOX_FAILURE','late failure rolls back stock value tracking provenance journal audit receipt');
drop trigger disposition_late_failure on core.outbox_events;
insert into procurement_test_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('disp.plain.balance')),10::numeric,'late failure preserves quantity');
insert into procurement_test_results select is((select sum(quantity) from inventory.receipt_provenance_positions where origin_line_id=pg_temp.fid('disp.plain.receipt.line')),10::numeric,'late failure preserves receipt attribution');
insert into procurement_test_results select is((select count(*) from finance.journal_entries where source_type='inventory_disposition'),0::bigint,'late failure leaves no posted journal');
insert into procurement_responses values('disp.post',pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.one','post'),3,'disp.post'));
insert into procurement_test_results select is(pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.one','post'),3,'disp.post'),(select response from procurement_responses where name='disp.post'),'posting replay creates no duplicate effects');
insert into procurement_test_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('disp.plain.balance')),7::numeric,'disposition consumes selected available quantity');
insert into procurement_test_results select is((select carrying_value from inventory.stock_valuations where stock_balance_id=pg_temp.fid('disp.plain.balance')),70.086419::numeric,'disposition removes exact carrying value');
insert into procurement_test_results select is((select sum(quantity) from inventory.receipt_provenance_positions where origin_line_id=pg_temp.fid('disp.plain.receipt.line')),7::numeric,'disposition consumes receipt provenance');
insert into procurement_test_results select is((select source_type from inventory.stock_movements where source_id=pg_temp.fid('disp.one')),'inventory_disposition','disposition retains its actual source type');
insert into procurement_test_results select is((select movement_kind from inventory.stock_movements where source_id=pg_temp.fid('disp.one')),'disposition','disposition does not impersonate transfer');
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id where j.source_id=pg_temp.fid('disp.one')),0::numeric,'inventory/variance journal balances exactly');
insert into procurement_test_results select throws_ok($$update inventory.stock_dispositions set reason='Rewrite history' where id=pg_temp.fid('disp.one')$$,'55000',null,'posted disposition immutable');
select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_reverse('disp.reverse','disp.one'));
select pg_temp.disposition_approve('disp.reverse');
select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.reverse','post'),3);
insert into procurement_test_results select is((select carrying_value from inventory.stock_valuations where stock_balance_id=pg_temp.fid('disp.plain.balance')),100.123456::numeric,'linked reversal restores original exact value');
insert into procurement_test_results select is((select sum(quantity) from inventory.receipt_provenance_positions where origin_line_id=pg_temp.fid('disp.plain.receipt.line')),10::numeric,'linked reversal restores original cohort');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_reverse('disp.reverse.again','disp.one'))$$,'55000','DISPOSITION_ALREADY_REVERSED','source restoration occurs once only');
select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.expired','lot'));
select pg_temp.disposition_approve('disp.expired');
select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.expired','post'),3);
insert into procurement_test_results select is((select on_hand_quantity from inventory.lot_balances where lot_id=pg_temp.fid('disp.lot.id')),7::numeric,'permitted command consumes expired held lot');
insert into procurement_test_results select is((select sum(quantity) from inventory.receipt_provenance_positions where origin_line_id=pg_temp.fid('disp.lot.receipt.line')),7::numeric,'expired lot remains attributed');
insert into procurement_test_results select throws_ok($$select pg_temp.call('transfer_stock',jsonb_build_object('id',pg_temp.fid('disp.expired.transfer'),'operation','dispatch','document_date','2026-09-29','reason','Normal saleable transfer','reference','EXPIRED','source_warehouse_id',pg_temp.fid('warehouse'),'destination_warehouse_id',pg_temp.fid('trace.destination'),'lines',pg_temp.disposition_payload('disp.expired','lot')->'lines'))$$,'22023','TRANSFER_TRACKING_INVALID','ordinary saleable transfer still rejects expired lot');
select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.serial.doc','serial'));
select pg_temp.disposition_approve('disp.serial.doc');
select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.serial.doc','post'),3);
insert into procurement_test_results select is((select status from inventory.serials where id=pg_temp.fid('disp.s1')),'disposed','selected serial becomes permanently disposed');
insert into procurement_test_results select is((select sum(quantity) from inventory.receipt_provenance_positions where origin_line_id=pg_temp.fid('disp.serial.receipt.line')),7::numeric,'serial disposition consumes exact identities');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.serial.again','serial'))$$,'55000','DISPOSITION_SERIAL_UNAVAILABLE','disposed serial cannot be consumed twice');
insert into procurement_test_results select throws_ok($$update inventory.serials set status='available',warehouse_id=pg_temp.fid('trace.destination') where id=pg_temp.fid('disp.s1')$$,'55000','DISPOSED_SERIAL_IMMUTABLE','disposed serial cannot reappear in another warehouse');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_reverse('disp.serial.reverse','disp.serial.doc'))$$,'55000','DISPOSITION_SERIAL_REVERSAL_DENIED','linked reverse cannot resurrect disposed serial');
select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.additional')||jsonb_build_object('corrects_disposition_id',pg_temp.fid('disp.one')));
select pg_temp.disposition_approve('disp.additional');
select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.additional','post'),3);
select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.later','plain','1'));
select pg_temp.disposition_approve('disp.later');
select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.later','post'),3);
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_reverse('disp.unsafe.reverse','disp.additional'))$$,'55000','DISPOSITION_LATER_HISTORY','later issue prevents stale physical/value reversal');
select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.drift','plain','1'));
select pg_temp.disposition_approve('disp.drift');
update inventory.stock_valuations set carrying_value=carrying_value+1 where stock_balance_id=pg_temp.fid('disp.plain.balance');
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.drift','post'),3)$$,'55000','DISPOSITION_REAPPROVAL_REQUIRED','value drift requires fresh approval');
update inventory.stock_balances set allocated_quantity=on_hand_quantity where id=pg_temp.fid('disp.plain.balance');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.reserved','plain','1'))$$,'55000','DISPOSITION_STOCK_UNAVAILABLE','reservation protects held stock');
update inventory.stock_balances set allocated_quantity=0 where id=pg_temp.fid('disp.plain.balance');
insert into procurement_test_results select ok(jsonb_array_length(api.stock_disposition_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'lots',pg_temp.fid('warehouse'),pg_temp.fid('disp.lot'))->'items')=1,'expired held lot available in scoped picker');
insert into procurement_test_results select is(jsonb_array_length(api.stock_disposition_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'serials',pg_temp.fid('warehouse'),pg_temp.fid('disp.serial'))->'items'),7,'disposed serials excluded from picker');
insert into procurement_test_results select throws_ok($$select api.stock_disposition_options(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'lots',pg_temp.fid('warehouse'))$$,'22023','DISPOSITION_PRODUCT_REQUIRED','lot picker requires scoped product');
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='inventory.dispositions.post';
insert into procurement_test_results select throws_ok($$select pg_temp.call('post_stock_disposition',pg_temp.disposition_action('disp.one','post'),3,'disp.post')$$,'42501',null,'saved posting replay rechecks disposition permission');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.dispositions.post');
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_disposition',pg_temp.disposition_payload('disp.no.mfa'))$$,'42501',null,'dedicated privileged capability enforces MFA');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.stock_disposition_detail(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('disp.one'))$$,'42501',null,'outsider cannot read disposition costs');
select pg_temp.actor('creator');
