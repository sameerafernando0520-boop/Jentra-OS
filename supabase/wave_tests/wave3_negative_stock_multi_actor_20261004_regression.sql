-- Additive synthetic regression proposal. Append after the frozen policy suite
-- only when root has retained its execution result. No enclosing transaction,
-- persistent installation, independent-session or native acceptance claim.
-- The existing fixture supplies creator and approver as synthetic active users.
select pg_temp.actor('creator');
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('approver.role'),p
from unnest(array['sales.deliveries.post','inventory.stock.override'])p
on conflict do nothing;

select pg_temp.ns_product('multi-actor',1,5);
select pg_temp.ns_order('multi-actor.order','multi-actor','4');
select pg_temp.ns_reserve('multi-actor.order','4',true,'negative.multi-actor.reserve');
select pg_temp.ns_prepare('delivery','multi-actor.first','multi-actor.order','2');
select pg_temp.ns_prepare('delivery','multi-actor.second','multi-actor.order','2');

select pg_temp.actor('approver');
insert into procurement_test_results select lives_ok(
 $$select pg_temp.ns_post('delivery','multi-actor.first','negative.multi-actor.first.post')$$,
 'another currently authorized actor can post the first partial deficit delivery');
insert into procurement_test_results select is(pg_temp.ns_q('multi-actor'),-1::numeric,
 'first partial delivery consumes positive stock and one provisional unit');
insert into procurement_test_results select is(pg_temp.ns_v('multi-actor'),-5::numeric,
 'first partial deficit retains the authoritative cost basis');
insert into procurement_test_results select is(
 (select updated_by from inventory.stock_reservations
  where sales_order_id=pg_temp.fid('negative.multi-actor.order') and status='active'),
 pg_temp.fid('approver'),'reservation last editor becomes the partial delivery actor');
insert into procurement_test_results select is(
 (select created_by from inventory.negative_stock_overrides
  where effect='reserve' and command_id=pg_temp.fid('negative.multi-actor.reserve')),
 pg_temp.fid('creator'),'immutable shortage authorization retains the original reserve actor');

select pg_temp.actor('creator');
insert into procurement_test_results select lives_ok(
 $$select pg_temp.ns_post('delivery','multi-actor.second','negative.multi-actor.second.post')$$,
 'remaining delivery retains original reservation authority after another actor edits its projection');
