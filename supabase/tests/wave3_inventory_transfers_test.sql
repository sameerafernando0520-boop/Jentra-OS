create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create temporary table transfer_results(message text);
grant insert on transfer_results to authenticated;
create function pg_temp.fid(p text) returns uuid language sql immutable as $$select md5('remaining-wave3-transfer-20260916:'||p)::uuid$$;
create function pg_temp.actor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fid(p),'role','authenticated','aal',p_aal)::text,true);
 perform set_config('request.jwt.claim.sub',pg_temp.fid(p)::text,true);end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.fid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x||'@transfer.jentra.test','',now(),now(),now() from unnest(array['actor','outsider'])x;
insert into core.tenants(id,name,slug,created_by) values(pg_temp.fid('t'),'Transfer test','remaining-w3-transfer',pg_temp.fid('actor'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,rounding_scale,created_by)
values(pg_temp.fid('e'),pg_temp.fid('t'),'Transfer entity','TRTEST','LKR',2,pg_temp.fid('actor'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),'Test '||x,'TEST-'||upper(x),pg_temp.fid('actor') from unnest(array['b','b2'])x;
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid(case when x='w2' then 'b2' else 'b' end),'Test '||x,'TEST-'||upper(x),pg_temp.fid('actor') from unnest(array['w','w2'])x;
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.fid('m'),pg_temp.fid('t'),pg_temp.fid('actor'),'active');
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.fid('r'),pg_temp.fid('t'),'transfer','Transfer',true);
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('t'),pg_temp.fid('r'),'inventory.transfers.post');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.fid('t'),pg_temp.fid('m'),pg_temp.fid('r'),pg_temp.fid('e'),pg_temp.fid(x),pg_temp.fid('actor') from unnest(array['b','b2'])x;
insert into finance.fiscal_periods(tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
values(pg_temp.fid('t'),pg_temp.fid('e'),'Transfer period','2026-09-01','2026-09-30',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
values(pg_temp.fid('u'),pg_temp.fid('t'),'EA','Each','ea','quantity',6,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,created_by,updated_by)
select pg_temp.fid(x),pg_temp.fid('t'),pg_temp.fid('e'),upper(x),x,'stocked',pg_temp.fid('u'),case when x='serial' then 'serial' when x='lot' then 'lot' else 'none' end,pg_temp.fid('actor'),pg_temp.fid('actor') from unnest(array['plain','lot','serial'])x;
insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
select pg_temp.fid(x||'.bal'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid(x),10,pg_temp.fid('actor'),pg_temp.fid('actor') from unnest(array['plain','lot','serial'])x;
insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
select pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid(x||'.bal'),100.123456,pg_temp.fid('actor'),pg_temp.fid('actor') from unnest(array['plain','lot','serial'])x;
insert into inventory.lots(id,tenant_id,legal_entity_id,product_id,code,expiry_date,created_by,updated_by)
values(pg_temp.fid('lot.id'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('lot'),'LOT-1','2027-01-01',pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
values(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid('lot'),pg_temp.fid('lot.id'),10,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.serials(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,code,created_by,updated_by)
select pg_temp.fid('s'||x),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid('serial'),'SER-'||x,pg_temp.fid('actor'),pg_temp.fid('actor') from generate_series(1,10)x;
create function pg_temp.payload(n text,op text default 'dispatch',product text default 'plain',quantity text default '3') returns jsonb language sql as $$select jsonb_build_object(
 'id',pg_temp.fid(n),'operation',op,'document_date','2026-09-15','reason','Move to receiving branch','reference','TR-TEST',
 'source_warehouse_id',pg_temp.fid('w'),'destination_warehouse_id',pg_temp.fid('w2'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid(n||'.line'),'product_id',pg_temp.fid(product),'unit_id',pg_temp.fid('u'),
 'quantity',quantity,'conversion_numerator','1','conversion_denominator','1','lot_id',case when product='lot' then pg_temp.fid('lot.id') end,
 'serial_ids',case when product='serial' then jsonb_build_array(pg_temp.fid('s1'),pg_temp.fid('s2'),pg_temp.fid('s3')) else '[]'::jsonb end)))$$;
create function pg_temp.call(payload jsonb,version bigint default null,key text default null) returns jsonb language sql as $$
 select api.transfer_stock(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),coalesce(pg_temp.fid(key),gen_random_uuid()),
 coalesce(pg_temp.fid(key),gen_random_uuid()),'2026-09-15T00:00:00Z',payload,version)$$;
select pg_temp.actor('actor');
insert into transfer_results select has_function('api','transfer_stock',array['uuid','uuid','uuid','uuid','uuid','timestamp with time zone','jsonb','bigint'],'transfer RPC exists');
create temporary table responses(name text,r jsonb);
insert into responses values('dispatch',pg_temp.call(pg_temp.payload('one'),null,'one'));
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('plain.bal')),7::numeric,'dispatch removes source quantity');
insert into transfer_results select is((select carrying_value from inventory.transfer_lines where transfer_id=pg_temp.fid('one')),30.037037::numeric,'dispatch freezes six decimal carrying cost');
insert into transfer_results select is((select sum(carrying_value) from inventory.stock_valuations where tenant_id=pg_temp.fid('t'))+(select sum(carrying_value) from inventory.transfer_lines l join inventory.transfers t on t.id=l.transfer_id where t.status='in_transit'),300.370368::numeric,'warehouse plus transit value conserved');
insert into transfer_results select is(pg_temp.call(pg_temp.payload('one'),null,'one'),(select r from responses where name='dispatch'),'dispatch identical replay');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('one')||'{"reason":"changed"}',null,'one')$$,'22023','IDEMPOTENCY_MISMATCH','changed body key rejected');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('one','receive'),99)$$,'40001','VERSION_CONFLICT','stale receive rejected');
select pg_temp.call(pg_temp.payload('one','receive'),1);
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where warehouse_id=pg_temp.fid('w2') and product_id=pg_temp.fid('plain')),3::numeric,'receive materializes destination quantity');
insert into transfer_results select is((select sum(carrying_value) from inventory.stock_valuations where tenant_id=pg_temp.fid('t')),300.370368::numeric,'receive conserves all value');
select pg_temp.call(pg_temp.payload('one','reverse'),2);
insert into transfer_results select is((select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('plain.bal')),10::numeric,'completed reversal restores source');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('one','reverse'),3)$$,'55000','TRANSFER_STATE_INVALID','second reversal denied');
select pg_temp.call(pg_temp.payload('two','dispatch','serial'));
insert into transfer_results select is((select status from inventory.serials where id=pg_temp.fid('s1')),'in_transit','serial unavailable in transit');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('duplicate','dispatch','serial'))$$,'55000','TRANSFER_SERIAL_UNAVAILABLE','serial cannot dispatch twice');
insert into transfer_results select is((select count(*) from inventory.transfers where id=pg_temp.fid('duplicate')),0::bigint,'failed tracking rolls back header and stock');
select pg_temp.call(pg_temp.payload('two','reverse','serial'),1);
insert into transfer_results select is((select status from inventory.serials where id=pg_temp.fid('s1')),'available','transit reversal restores serial');
select pg_temp.call(pg_temp.payload('three','immediate','lot'));
insert into transfer_results select is((select on_hand_quantity from inventory.lot_balances where warehouse_id=pg_temp.fid('w2') and lot_id=pg_temp.fid('lot.id')),3::numeric,'lot immediate transfer tracked');
update inventory.stock_balances set allocated_quantity=9 where id=pg_temp.fid('plain.bal');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('reserved'))$$,'55000','TRANSFER_STOCK_UNAVAILABLE','reservations protected');
update inventory.stock_balances set allocated_quantity=0 where id=pg_temp.fid('plain.bal');
insert into transfer_results select throws_ok($$select pg_temp.call(jsonb_set(pg_temp.payload('numeric'),'{lines,0,quantity}','3'))$$,'22023','quantity must be a decimal string.','numeric JSON rejected');
insert into transfer_results select throws_ok($$update inventory.transfer_lines set carrying_value=1$$,'55000',null,'transfer values immutable');
insert into transfer_results select is((select r::text like '%carrying_value%' from responses limit 1),false,'command receipt does not disclose cost');
insert into transfer_results select is(jsonb_array_length(api.inventory_transfers(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'))->'items'),3,'scoped transfer register');
insert into transfer_results select is(jsonb_array_length(api.inventory_transfer_options(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'products',pg_temp.fid('w'))->'items'),3,'source product picker reads exact available stock');
insert into transfer_results select is(jsonb_array_length(api.inventory_transfer_options(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'warehouses')->'items'),2,'both authorized warehouses visible');
delete from core.role_assignments where tenant_id=pg_temp.fid('t') and branch_id=pg_temp.fid('b2');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('no-destination-access'))$$,'42501',null,'destination branch permission required');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('one'),null,'one')$$,'42501',null,'replay rechecks destination branch permission');
insert into transfer_results select is(jsonb_array_length(api.inventory_transfers(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'))->'items'),0,'register hides revoked destination scope');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('t'),pg_temp.fid('m'),pg_temp.fid('r'),pg_temp.fid('e'),pg_temp.fid('b2'),pg_temp.fid('actor'));
select pg_temp.call(pg_temp.payload('four','dispatch','serial'));
select pg_temp.call(pg_temp.payload('four','receive','serial'),1);
insert into transfer_results select is((select warehouse_id from inventory.serials where id=pg_temp.fid('s1')),pg_temp.fid('w2'),'serial receipt moves identity to destination');
insert into transfer_results select is((select status from inventory.serials where id=pg_temp.fid('s1')),'available','received serial available once');
-- A real subsequent transfer issue is a consumption event, not a timestamp heuristic.
select pg_temp.call(pg_temp.payload('five','immediate','lot'));
insert into transfer_results select lives_ok($$select api.transfer_stock(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b2'),gen_random_uuid(),gen_random_uuid(),now(),
 pg_temp.payload('consume','immediate','lot','1')||jsonb_build_object('source_warehouse_id',pg_temp.fid('w2'),'destination_warehouse_id',pg_temp.fid('w')),null)$$,'subsequent transfer consumes destination stock');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('five','reverse','lot'),1)$$,'55000','TRANSFER_DESTINATION_CONSUMED','later destination issue prevents unsafe reversal');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('future')||'{"document_date":"2099-01-01"}')$$,'22023','FUTURE_POSTING_DATE','future movement rejected');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('closed')||'{"document_date":"2026-08-01"}')$$,'55000','PERIOD_CLOSED','closed period rejected');
update inventory.lots set expiry_date='2026-01-01' where id=pg_temp.fid('lot.id');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('expired','dispatch','lot'))$$,'22023','TRANSFER_TRACKING_INVALID','expired saleable dispatch denied');
update inventory.lots set expiry_date='2027-01-01' where id=pg_temp.fid('lot.id');
-- Fail after a first valid line has mutated stock: the second exceeds availability.
create temporary table before_failure as select sum(carrying_value) value from inventory.stock_valuations where tenant_id=pg_temp.fid('t');
insert into transfer_results select throws_ok($$select pg_temp.call(jsonb_set(pg_temp.payload('partial'),'{lines}',
 (pg_temp.payload('partial')->'lines')||(pg_temp.payload('partial-second','dispatch','plain','999')->'lines')))$$,'55000','TRANSFER_STOCK_UNAVAILABLE','later line failure rolls back earlier leg');
insert into transfer_results select is((select sum(carrying_value) from inventory.stock_valuations where tenant_id=pg_temp.fid('t')),(select value from before_failure),'failed multi-line transfer preserves carrying value');
insert into transfer_results select is((select count(*) from inventory.stock_movements where source_id=pg_temp.fid('partial')),0::bigint,'failed transfer leaves no movement');
insert into transfer_results select is((select count(*) from inventory.transfers where id=pg_temp.fid('partial')),0::bigint,'failed transfer leaves no header');
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,created_by,updated_by)
values(pg_temp.fid('dated-product'),pg_temp.fid('t'),pg_temp.fid('e'),'DATED','Dated stock','stocked',pg_temp.fid('u'),pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
values(pg_temp.fid('dated-bal'),pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('w'),pg_temp.fid('dated-product'),10,pg_temp.fid('actor'),pg_temp.fid('actor'));
insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
values(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),pg_temp.fid('dated-bal'),100.123456,pg_temp.fid('actor'),pg_temp.fid('actor'));
select pg_temp.call(pg_temp.payload('dated','dispatch','dated-product')||'{"document_date":"2026-09-14"}');
insert into transfer_results select is(jsonb_array_length(api.inventory_transfer_holdings(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-13')->'items'),0,'dated holdings exclude later dispatch');
insert into transfer_results select is(jsonb_array_length(api.inventory_transfer_holdings(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-14')->'items'),1,'dated holdings include outstanding dispatch');
insert into transfer_results select ok(not (api.inventory_transfer_holdings(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-14')::text like '%carrying_value%'),'transfer authority does not expose transit cost');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('t'),pg_temp.fid('r'),'inventory.cost.view');
insert into transfer_results select is(api.inventory_transfer_holdings(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-14')#>>'{items,0,lines,0,carrying_value}','30.037037','authorized transit cost remains exact string');
select pg_temp.call(pg_temp.payload('dated','receive'),1);
insert into transfer_results select is(jsonb_array_length(api.inventory_transfer_holdings(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-14')->'items'),1,'later receipt preserves historic holding');
insert into transfer_results select is(jsonb_array_length(api.inventory_transfer_holdings(pg_temp.fid('t'),pg_temp.fid('e'),pg_temp.fid('b'),'2026-09-15')->'items'),0,'receipt date clears dated holding');
select pg_temp.actor('actor','aal1');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('no-mfa'))$$,'42501',null,'MFA required');
select pg_temp.actor('outsider');
insert into transfer_results select throws_ok($$select pg_temp.call(pg_temp.payload('outside'))$$,'42501',null,'outsider denied');
set local role authenticated;
insert into transfer_results select throws_ok($$select * from inventory.transfer_lines$$,'42501',null,'raw value rows denied');
insert into transfer_results select throws_ok($$insert into inventory.transfers(id) values(gen_random_uuid())$$,'42501',null,'direct writes denied');
reset role;
insert into transfer_results select * from finish();
select jsonb_agg(message) results from transfer_results;
rollback;


