-- Synthetic procurement fixture extension; enclosing builder finishes strictly and rolls back.
-- Actual reserve, delivery, saleable return and receipt RPCs exercise the paths.
select pg_temp.actor('creator');
set constraints all deferred;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),code from core.permissions
where code in('sales.orders.manage','sales.deliveries.view','sales.deliveries.manage','sales.deliveries.post','sales.returns.view','sales.returns.manage','sales.returns.post',
 'inventory.reservations.manage','inventory.stock.override','inventory.stock.view','inventory.cost.view','inventory.stock.policy.manage',
 'inventory.adjustments.post','inventory.transfers.post','finance.view','procurement.receipts.post') on conflict do nothing;
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,credit_limit,created_by,updated_by)
values(pg_temp.fid('negative.customer'),pg_temp.fid('tenant'),'NEGATIVE-CUSTOMER','Negative stock customer','Negative stock customer','customer',1000000,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.document_sequences(tenant_id,legal_entity_id,branch_id,document_type,prefix,created_by,updated_by)
select pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),x,'NS-'||x||'-',pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['sales_order','delivery','sales_return','stock_count'])x on conflict do nothing;
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
select pg_temp.fid('negative.'||x||'.workflow'),pg_temp.fid('tenant'),pg_temp.fid('entity'),x,'Negative stock '||x,'active',
 '{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["approved","posted"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"]],"posting_transitions":[["submitted","posted"],["submitted","draft"],["approved","draft"]],"requires_approval":false}',pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['delivery','sales_return'])x;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
select pg_temp.fid('negative.'||x),pg_temp.fid('tenant'),pg_temp.fid('entity'),'NS-'||upper(x),'Negative stock '||x,
 case when x='inventory' then 'asset' when x='revenue' then 'revenue' else 'expense' end,
 case when x='revenue' then 'credit' else 'debit' end,pg_temp.fid('creator'),pg_temp.fid('creator')
from unnest(array['inventory','cogs','revenue','replacement-cogs'])x;

create function pg_temp.ns_version() returns bigint language sql as $$select coalesce(max(version),0) from inventory.negative_stock_policy_versions where tenant_id=pg_temp.fid('tenant') and legal_entity_id=pg_temp.fid('entity')$$;
create function pg_temp.ns_policy(active boolean,k text) returns jsonb language sql as $$select pg_temp.call('configure_negative_stock_policy',jsonb_build_object('active',active,'reason','Approved synthetic policy decision'),pg_temp.ns_version(),k)$$;
create function pg_temp.ns_override(v text default null) returns jsonb language sql as $$select jsonb_build_object('policy_version',coalesce(v,pg_temp.ns_version()::text),'reason','Approved demand ahead of receipt')$$;
create function pg_temp.ns_product(n text,q numeric default 1,value numeric default 5,tracking text default 'none') returns void language plpgsql as $$begin
 insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,revenue_account_id,inventory_account_id,cogs_account_id,created_by,updated_by)
 values(pg_temp.fid('negative.'||n),pg_temp.fid('tenant'),pg_temp.fid('entity'),'NS-'||upper(n),'Negative stock '||n,'stocked',pg_temp.fid('unit'),tracking,
  pg_temp.fid('negative.revenue'),pg_temp.fid('negative.inventory'),pg_temp.fid('negative.cogs'),pg_temp.fid('creator'),pg_temp.fid('creator'));
 insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
 values(pg_temp.fid('negative.'||n||'.balance'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('negative.'||n),q,pg_temp.fid('creator'),pg_temp.fid('creator'));
 insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
 values(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('negative.'||n||'.balance'),value,pg_temp.fid('creator'),pg_temp.fid('creator'));
 if q>0 and tracking='none' then
  insert into inventory.stock_movements(id,tenant_id,legal_entity_id,branch_id,source_type,source_id,warehouse_id,posting_date,movement_kind,request_id,command_id,correlation_id,created_by)
  values(pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'opening',pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('warehouse'),'2026-09-29','opening',
   pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('creator'));
  insert into inventory.stock_movement_lines(id,tenant_id,legal_entity_id,branch_id,stock_movement_id,warehouse_id,product_id,source_line_id,base_quantity,base_value,posting_date,created_by)
  values(pg_temp.fid('negative.'||n||'.opening.line'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('warehouse'),pg_temp.fid('negative.'||n),
   pg_temp.fid('negative.'||n||'.opening.line'),q,value,'2026-09-29',pg_temp.fid('creator'));
  if value>0 then perform finance.flow_post_journal(jsonb_build_object('tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'branch_id',pg_temp.fid('branch'),
   'document_date','2026-09-29','currency_code','LKR','base_currency_code','LKR','exchange_rate','1'),
   jsonb_build_array(finance.flow_jline(pg_temp.fid('negative.inventory'),value,value),finance.flow_jline(pg_temp.fid('negative.cogs'),-value,-value)),
   'negative.synthetic_opening',pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('negative.'||n||'.opening'),pg_temp.fid('negative.'||n||'.opening'));end if;
 end if;
end $$;
create function pg_temp.ns_order(n text,product text,q text) returns jsonb language plpgsql as $$declare result jsonb;begin
 result:=pg_temp.call('upsert_sales_order',jsonb_build_object('id',pg_temp.fid('negative.'||n),'customer_id',pg_temp.fid('negative.customer'),
  'order_date','2026-09-29','promised_date','2026-09-30','warehouse_id',pg_temp.fid('warehouse'),'ship_to',jsonb_build_object('address','Synthetic'),
  'currency_code','LKR','exchange_rate','1','rate_date','2026-09-29','salesperson_id',pg_temp.fid('creator'),
  'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.'||n||'.line'),'product_id',pg_temp.fid('negative.'||product),'description',product,
   'unit_id',pg_temp.fid('unit'),'quantity',q,'base_quantity',q,'conversion_numerator','1','conversion_denominator','1','unit_price','1'))));
 return pg_temp.call('transition_operational_document',jsonb_build_object('document_type','sales_order','document_id',pg_temp.fid('negative.'||n),'action','confirm'),(result#>>'{entity,version}')::bigint);
end $$;
create function pg_temp.ns_reserve_payload(n text,q text,over boolean default true,v text default null) returns jsonb language sql as $$select
 jsonb_build_object('sales_order_id',pg_temp.fid('negative.'||n),'expires_at',clock_timestamp()+interval '30 days',
 'lines',jsonb_build_array(jsonb_build_object('sales_order_line_id',pg_temp.fid('negative.'||n||'.line'),'requested_base_quantity',q)))
 ||case when over then jsonb_build_object('negative_stock_override',pg_temp.ns_override(v)) else '{}'::jsonb end$$;
create function pg_temp.ns_reserve(n text,q text,over boolean default true,k text default null,v text default null) returns jsonb language sql as $$select pg_temp.call('reserve_sales_order_stock',
 pg_temp.ns_reserve_payload(n,q,over,v),(select version from sales.sales_orders where id=pg_temp.fid('negative.'||n)),k)$$;
create function pg_temp.ns_prepare(kind text,n text,source text,q text) returns jsonb language plpgsql as $$declare result jsonb;payload jsonb;begin
 payload:=jsonb_build_object('id',pg_temp.fid('negative.'||n),'customer_id',pg_temp.fid('negative.customer'),'document_date','2026-09-29','due_date','2026-09-29','currency_code','LKR');
 if kind='delivery' then payload:=payload||jsonb_build_object('sales_order_id',pg_temp.fid('negative.'||source),'warehouse_id',pg_temp.fid('warehouse'),
  'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.'||n||'.line'),'sales_order_line_id',pg_temp.fid('negative.'||source||'.line'),'base_quantity',q)));
 else payload:=payload||jsonb_build_object('reason','Synthetic source-linked return','lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.'||n||'.line'),
  'delivery_line_id',pg_temp.fid('negative.'||source||'.line'),'base_quantity',q,'disposition','saleable')));end if;
 result:=pg_temp.call(case kind when 'delivery' then 'upsert_delivery' else 'upsert_sales_return' end,payload);
 return pg_temp.call('transition_operational_document',jsonb_build_object('document_type',kind,'document_id',pg_temp.fid('negative.'||n),'action','submit'),(result#>>'{entity,version}')::bigint);
end $$;
create function pg_temp.ns_post(kind text,n text,k text default null) returns jsonb language sql as $$select pg_temp.call(case kind when 'delivery' then 'post_delivery' else 'post_sales_return' end,
 jsonb_build_object('document_id',pg_temp.fid('negative.'||n)),case kind when 'delivery' then (select version from sales.deliveries where id=pg_temp.fid('negative.'||n))
 else (select version from sales.sales_returns where id=pg_temp.fid('negative.'||n)) end,k)$$;
create function pg_temp.ns_issue(n text,product text,q text) returns jsonb language plpgsql as $$begin
 perform pg_temp.ns_order(n||'.order',product,q);perform pg_temp.ns_reserve(n||'.order',q);
 perform pg_temp.ns_prepare('delivery',n,n||'.order',q);return pg_temp.ns_post('delivery',n,n||'.post');end $$;

-- The PO is a labelled synthetic approved fixture; its receipt is the real API.
create function pg_temp.ns_po(n text,product text,q numeric,unitprice numeric) returns void language plpgsql as $$begin
 insert into procurement.purchase_orders(id,tenant_id,legal_entity_id,branch_id,supplier_id,warehouse_id,source_requisition_id,source_snapshot,
  document_date,promised_date,currency_code,exchange_rate,rate_date,payment_terms,delivery_terms,subtotal,tax_total,total,base_total,status,created_by,updated_by,commercial_editor_id)
 values(pg_temp.fid('negative.'||n),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('supplier_a'),pg_temp.fid('warehouse'),pg_temp.fid('request'),
  '{"synthetic_approved_fixture":true}','2026-09-29','2026-09-30','LKR',1,'2026-09-29','14 days','Warehouse',round(q*unitprice,2),0,round(q*unitprice,2),round(q*unitprice,2),
  'approved',pg_temp.fid('creator'),pg_temp.fid('creator'),pg_temp.fid('creator'));
 insert into procurement.purchase_order_lines(id,tenant_id,legal_entity_id,order_id,source_line_id,product_id,unit_id,description,quantity,unit_price,discount_percent,detail)
 values(pg_temp.fid('negative.'||n||'.line'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('negative.'||n),pg_temp.fid('request.line'),pg_temp.fid('negative.'||product),pg_temp.fid('unit'),
  product,q,unitprice,0,jsonb_build_object('base_unit_id',pg_temp.fid('unit'),'conversion_numerator','1','conversion_denominator','1','net_amount',round(q*unitprice,2)::text));
end $$;
create function pg_temp.ns_receipt_payload(n text,po text,q text) returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fid('negative.'||n),
 'order_id',pg_temp.fid('negative.'||po),'document_date','2026-09-29','warehouse_id',pg_temp.fid('warehouse'),'reference','Synthetic deficit cover receipt',
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.'||n||'.line'),'order_line_id',pg_temp.fid('negative.'||po||'.line'),
 'accepted_quantity',q,'rejected_quantity','0','serial_codes','[]'::jsonb)))$$;
create function pg_temp.ns_receipt(n text,po text,q text,k text default null) returns jsonb language sql as $$select pg_temp.call('post_goods_receipt',pg_temp.ns_receipt_payload(n,po,q),
 (select version from procurement.purchase_orders where id=pg_temp.fid('negative.'||po)),k)$$;
create function pg_temp.ns_q(n text) returns numeric language sql as $$select on_hand_quantity from inventory.stock_balances where id=pg_temp.fid('negative.'||n||'.balance')$$;
create function pg_temp.ns_v(n text) returns numeric language sql as $$select carrying_value from inventory.stock_valuations where stock_balance_id=pg_temp.fid('negative.'||n||'.balance')$$;
create function pg_temp.ns_open(n text) returns numeric language sql as $$select coalesce(sum(inventory.negative_stock_open_quantity(x.tenant_id,x.id)),0) from inventory.negative_stock_deficits x where x.product_id=pg_temp.fid('negative.'||n)$$;
create temporary table negative_stock_responses(name text primary key,response jsonb);

-- Existing quantity-only provenance remains usable without a valuation. It
-- must not establish a known zero-cost snapshot for a later shortage.
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_cost_bases where product_id=pg_temp.fid('legacy.product')),0::bigint,'quantity-only positive provenance does not invent a cost basis');
insert into procurement_test_results select throws_ok($$select inventory.capture_negative_stock_basis(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('legacy.product'),'{}')$$,'55000','INVENTORY_COST_UNAVAILABLE','strict shortage basis still rejects quantity-only legacy stock');

insert into procurement_test_results select is(api.negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'policy_version','0','FR353 policy defaults to version0');
insert into procurement_test_results select is(api.negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'active','false','FR353 policy defaults OFF');
insert into procurement_test_results select is(api.negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'tenant_id',pg_temp.fid('tenant')::text,'absent OFF policy identifies the requested tenant');
insert into procurement_test_results select is(api.negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'legal_entity_id',pg_temp.fid('entity')::text,'absent OFF policy identifies the requested legal entity');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_policy(true,'negative.enable.branch')$$,'42501',null,'branch-only assignment cannot change entity-wide policy');
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.fid('negative.policy.role'),pg_temp.fid('tenant'),'negative-policy-owner','Negative policy owner',true);
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('negative.policy.role'),'inventory.stock.policy.manage');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('negative.policy.role'),pg_temp.fid('entity'),null,pg_temp.fid('creator'));
select pg_temp.ns_product('main');select pg_temp.ns_order('main.order','main','4');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reserve_sales_order_stock',pg_temp.ns_reserve_payload('main.order','4',false)||
 '{"source_context":{"negative_stock_override":{"policy_version":"1","reason":"Forged nested client metadata"}}}',(select version from sales.sales_orders where id=pg_temp.fid('negative.main.order')))$$,'22023','NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID','normal reservation rejects client forgery of the reserved authorization key');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_reserve('main.order','4')$$,'55000','NEGATIVE_STOCK_POLICY_INACTIVE','OFF rejects explicit shortage override');
insert into negative_stock_responses values('normal.reserve',pg_temp.ns_reserve('main.order','4',false,'negative.normal.reserve'));
insert into procurement_test_results select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('negative.main.balance')),1::numeric,'OFF legacy reservation clamps to physical availability');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_overrides),0::bigint,'normal OFF path creates no override audit');
insert into negative_stock_responses values('enable',pg_temp.ns_policy(true,'negative.enable'));
insert into procurement_test_results select is((select response#>>'{entity,policy_version}' from negative_stock_responses where name='enable'),'1','activation appends version1');
insert into procurement_test_results select is((select jsonb_build_object('id',response#>'{entity,id}','tenant_id',response#>'{entity,tenant_id}','legal_entity_id',response#>'{entity,legal_entity_id}','created_by',response#>'{entity,created_by}') from negative_stock_responses where name='enable'),
 jsonb_build_object('id',pg_temp.fid('negative.enable'),'tenant_id',pg_temp.fid('tenant'),'legal_entity_id',pg_temp.fid('entity'),'created_by',pg_temp.fid('creator')),'confirmed policy identity belongs to the command original actor and requested scope');
-- Read-only diagnostic after the original activation; enclosing strict query
-- preserves its exact request and rolls back all candidate/fixture effects.
do $$declare stored core.command_receipts%rowtype;expected text;begin
 select * into stored from core.command_receipts where command_id=pg_temp.fid('negative.enable');
 expected:=core.wave3_request_hash('inventory.stock.policy.configure',pg_temp.fid('negative.enable'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
  '{"active":true,"reason":"Approved synthetic policy decision"}'::jsonb,0);
 if stored.request_hash is distinct from expected then
  raise exception using errcode='P0001',message='NEGATIVE_POLICY_REPLAY_HASH_DIAGNOSTIC',detail=jsonb_build_object(
   'stored_hash',stored.request_hash,'expected_zero_hash',expected,'actor',stored.actor_id,'expected_actor',pg_temp.fid('creator'),
   'command',stored.command_id,'expected_command',pg_temp.fid('negative.enable'),'command_name',stored.command_name,'current_policy_version',pg_temp.ns_version())::text;
 end if;
end $$;
insert into procurement_test_results select is(pg_temp.call('configure_negative_stock_policy','{"active":true,"reason":"Approved synthetic policy decision"}',0,'negative.enable'),
 (select response from negative_stock_responses where name='enable'),'diagnostic original policy activation replays unchanged');
