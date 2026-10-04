-- Synthetic procurement fixture extension; enclosing builder finishes strictly and rolls back.
-- Actual reserve, delivery, saleable return and receipt RPCs exercise the paths.
select pg_temp.actor('creator');
set constraints all deferred;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('creator.role'),code from core.permissions
where code in('sales.orders.manage','sales.deliveries.view','sales.deliveries.manage','sales.deliveries.post','sales.returns.view','sales.returns.manage','sales.returns.post',
 'inventory.reservations.manage','inventory.stock.override','inventory.stock.view','inventory.cost.view',
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
-- Earlier full-suite fixtures grant creator.role entity-wide authority. Use a
-- distinct branch-only role so this denial probes its actual intended scope.
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.fid('negative.policy.branch.role'),pg_temp.fid('tenant'),
 'negative-policy-branch-owner','Negative policy branch owner',true);
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('negative.policy.branch.role'),'inventory.stock.policy.manage');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('negative.policy.branch.role'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('creator'));
insert into procurement_test_results select is((select count(*) from core.role_assignments where tenant_id=pg_temp.fid('tenant')
 and membership_id=pg_temp.fid('creator.membership') and role_id=pg_temp.fid('negative.policy.branch.role')
 and legal_entity_id=pg_temp.fid('entity') and branch_id=pg_temp.fid('branch')),1::bigint,'denial fixture has exactly its intended branch-only policy assignment');
insert into procurement_test_results select is((select count(*) from core.role_assignments where tenant_id=pg_temp.fid('tenant')
 and membership_id=pg_temp.fid('creator.membership') and role_id=pg_temp.fid('negative.policy.branch.role')
 and (legal_entity_id is null or branch_id is null)),0::bigint,'branch-only policy role has no entity-wide or tenant-wide assignment');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_policy(true,'negative.enable.branch')$$,'42501',null,'branch-only assignment cannot change entity-wide policy');
insert into procurement_test_results select is(pg_temp.ns_version(),0::bigint,'branch-only policy refusal leaves the absent policy unchanged');
insert into procurement_test_results select is((select count(*) from core.command_receipts where command_id=pg_temp.fid('negative.enable.branch')),0::bigint,
 'branch-only policy refusal cannot leave a completed configuration receipt');
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
insert into procurement_test_results select is(pg_temp.call('configure_negative_stock_policy','{"active":true,"reason":"Approved synthetic policy decision"}',0,'negative.enable'),(select response from negative_stock_responses where name='enable'),'configuration identical replay retains version1');
insert into procurement_test_results select is((select from_status||':'||to_status from workflow.process_events where command_id=pg_temp.fid('negative.enable')),'inactive:active','policy activation records typed immutable process statuses');
insert into procurement_test_results select ok((select actor_id=pg_temp.fid('creator') and owner_id=actor_id and reason='Approved synthetic policy decision' from workflow.process_events where command_id=pg_temp.fid('negative.enable')),'policy process event identifies owner actor and attributable reason');
insert into procurement_test_results select is((select count(*) from workflow.process_events where command_id=pg_temp.fid('negative.enable')),1::bigint,'identical policy replay creates one process event');
insert into procurement_test_results select is((select count(*) from audit.events where command_id=pg_temp.fid('negative.enable') and before_context->>'policy_version'='0' and after_context->>'policy_version'='1'),1::bigint,'policy audit preserves exactly one before and after version');
insert into procurement_test_results select is((select count(*) from core.outbox_events where command_id=pg_temp.fid('negative.enable') and topic='inventory.stock.policy.configured'),1::bigint,'policy replay creates one scoped outbox event');
insert into procurement_test_results select is((select count(*) from core.command_receipts where command_id=pg_temp.fid('negative.enable')),1::bigint,'policy replay retains exactly one command receipt');
create function pg_temp.ns_fail_policy_outbox() returns trigger language plpgsql as $$begin if new.tenant_id=pg_temp.fid('tenant') and new.topic='inventory.stock.policy.configured' then raise exception using errcode='P0001',message='NEGATIVE_STOCK_POLICY_OUTBOX_FAILURE';end if;return new;end $$;
create trigger negative_stock_policy_synthetic_outbox before insert on core.outbox_events for each row execute function pg_temp.ns_fail_policy_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.ns_policy(true,'negative.policy.failed')$$,'P0001','NEGATIVE_STOCK_POLICY_OUTBOX_FAILURE','same-state policy version reaches late outbox failure without invalid process transition');
drop trigger negative_stock_policy_synthetic_outbox on core.outbox_events;
insert into procurement_test_results select is(pg_temp.ns_version(),1::bigint,'late policy failure preserves the previous immutable version');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_policy_versions where command_id=pg_temp.fid('negative.policy.failed')),0::bigint,'late failure rolls back new policy version');
insert into procurement_test_results select is((select count(*) from workflow.process_events where command_id=pg_temp.fid('negative.policy.failed')),0::bigint,'late failure rolls back policy process event');
insert into procurement_test_results select is((select count(*) from audit.events where command_id=pg_temp.fid('negative.policy.failed')),0::bigint,'late failure rolls back policy audit');
insert into procurement_test_results select is((select count(*) from core.outbox_events where command_id=pg_temp.fid('negative.policy.failed')),0::bigint,'late failure leaves no policy outbox event');
insert into procurement_test_results select is((select count(*) from core.command_receipts where command_id=pg_temp.fid('negative.policy.failed')),0::bigint,'late failure leaves no completed policy receipt');
insert into procurement_test_results select throws_ok($$select pg_temp.call('configure_negative_stock_policy','{"active":true,"reason":"different"}',0,'negative.enable')$$,'22023','IDEMPOTENCY_MISMATCH','configuration changed-body retry rejected');
insert into procurement_test_results select throws_ok($$select pg_temp.call('configure_negative_stock_policy','{"active":false,"reason":"stale"}',0)$$,'40001','VERSION_CONFLICT','configuration requires exact current version');
insert into procurement_test_results select throws_ok($$select pg_temp.call('configure_negative_stock_policy','{"active":"true","reason":"invalid"}',1)$$,'22023','NEGATIVE_STOCK_POLICY_INPUT_INVALID','policy requires boolean active');
insert into procurement_test_results select throws_ok($$select pg_temp.call('configure_negative_stock_policy','{"active":true,"reason":" "}',1)$$,'22023','NEGATIVE_STOCK_POLICY_INPUT_INVALID','policy requires attributable reason');
select pg_temp.actor('creator','aal1');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_policy(false,'negative.no.mfa')$$,'42501',null,'policy requires configured MFA');
select pg_temp.actor('creator');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_reserve('main.order','3',true,null,'999')$$,'40001','NEGATIVE_STOCK_POLICY_VERSION_CONFLICT','override binds current policy version');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reserve_sales_order_stock',jsonb_set(pg_temp.ns_reserve_payload('main.order','3'),'{negative_stock_override,policy_version}','1'),(select version from sales.sales_orders where id=pg_temp.fid('negative.main.order')))$$,'22023','NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID','policy version must be exact decimal string');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reserve_sales_order_stock',jsonb_set(pg_temp.ns_reserve_payload('main.order','3'),'{negative_stock_override,reason}','" "'),(select version from sales.sales_orders where id=pg_temp.fid('negative.main.order')))$$,'22023','NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID','override requires its own reason');
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='inventory.stock.override';
insert into procurement_test_results select throws_ok($$select pg_temp.ns_reserve('main.order','3')$$,'42501',null,'reservation capability alone cannot override');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.stock.override');
insert into negative_stock_responses values('override.reserve',pg_temp.ns_reserve('main.order','3',true,'negative.override.reserve'));
insert into procurement_test_results select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('negative.main.balance')),4::numeric,'active scoped override reserves full remaining demand');
insert into procurement_test_results select is((select available_quantity from inventory.stock_balances where id=pg_temp.fid('negative.main.balance')),-3::numeric,'negative available is explicit signed projection');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_overrides where effect='reserve'),1::bigint,'reservation shortage has separate immutable audit');
insert into procurement_test_results select is((select positive_quantity from inventory.negative_stock_cost_bases where product_id=pg_temp.fid('negative.main') order by id desc limit 1),1::numeric,'basis preserves authoritative positive quantity');
insert into procurement_test_results select is((select carrying_value from inventory.negative_stock_cost_bases where product_id=pg_temp.fid('negative.main') order by id desc limit 1),5::numeric,'basis preserves exact carrying numerator');
select pg_temp.ns_prepare('delivery','main.issue','main.order','4');
update inventory.stock_reservations set command_id=pg_temp.fid('negative.synthetic.unaudited.reservation') where sales_order_id=pg_temp.fid('negative.main.order') and status='active';
insert into procurement_test_results select throws_ok($$select pg_temp.ns_post('delivery','main.issue')$$,'55000','NEGATIVE_STOCK_RESERVATION_AUTHORIZATION_REQUIRED','actual deficit issue rejects metadata without matching immutable reservation authorization');
update inventory.stock_reservations set command_id=(select command_id from inventory.negative_stock_overrides where source_line_id=pg_temp.fid('negative.main.order.line') and effect='reserve' order by id desc limit 1)
 where sales_order_id=pg_temp.fid('negative.main.order') and status='active';
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='inventory.stock.override';
insert into procurement_test_results select throws_ok($$select pg_temp.ns_post('delivery','main.issue')$$,'42501',null,'delivery rechecks actual actor override');
insert into procurement_test_results select is(pg_temp.ns_q('main'),1::numeric,'denied delivery preserves stock');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.stock.override');
insert into negative_stock_responses values('main.issue',pg_temp.ns_post('delivery','main.issue','negative.main.issue.post'));
insert into procurement_test_results select is(pg_temp.ns_q('main'),-3::numeric,'approved real delivery reaches on-hand deficit3');
insert into procurement_test_results select is(pg_temp.ns_v('main'),-15::numeric,'interim deficit carries last positive cost5');
insert into procurement_test_results select is(pg_temp.ns_open('main'),3::numeric,'immutable deficit quantity3');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_overrides where effect='issue'),1::bigint,'actual issue audit is separate from reservation');
insert into procurement_test_results select is((select provisional_value from inventory.negative_stock_deficits where product_id=pg_temp.fid('negative.main')),15::numeric,'deficit provisional cost is exact');
insert into procurement_test_results select is((select base_value from inventory.stock_movement_lines where source_line_id=pg_temp.fid('negative.main.issue.line')),-20::numeric,'positive1 and deficit3 issue retains original value20');
insert into procurement_test_results select is((select sum(base_debit-base_credit) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id where j.source_type='delivery.stock' and j.source_id=pg_temp.fid('negative.main.issue')),0::numeric,'deficit delivery journal balances exactly');
insert into procurement_test_results select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('negative.main.balance')),0::numeric,'real delivery consumes reservation');
insert into procurement_test_results select ok(not exists(select 1 from inventory.receipt_provenance_positions where quantity<0),'deficit never invents negative physical cohort');

-- Unsupported inbound transfer/count cannot implicitly settle the deficit.
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_count',jsonb_build_object('id',pg_temp.fid('negative.bad.count'),'warehouse_id',pg_temp.fid('warehouse'),
 'document_date','2026-09-29','reason','Synthetic recount','offset_account_id',pg_temp.fid('negative.cogs'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.bad.count.line'),'product_id',pg_temp.fid('negative.main'),'counted_quantity','2','empty_unit_cost','5'))))$$,
 '55000','NEGATIVE_STOCK_OPERATION_REQUIRES_REVIEW','positive stock count into deficit requires lineage review');
insert into procurement_test_results select is((select count(*) from inventory.stock_counts where id=pg_temp.fid('negative.bad.count')),0::bigint,'unsupported count leaves no document');
insert into procurement_test_results select throws_ok($$select pg_temp.call('transfer_stock',jsonb_build_object('id',pg_temp.fid('negative.bad.transfer'),'operation','immediate','document_date','2026-09-29',
 'reason','Synthetic transfer','reference','NS-TRANSFER','source_warehouse_id',pg_temp.fid('trace.destination'),'destination_warehouse_id',pg_temp.fid('warehouse'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.bad.transfer.line'),'product_id',pg_temp.fid('negative.main'),'base_quantity','4','quantity','4',
  'unit_id',pg_temp.fid('unit'),'conversion_numerator','1','conversion_denominator','1'))))$$,'55000','NEGATIVE_STOCK_OPERATION_REQUIRES_REVIEW','inbound transfer cannot silently cover deficit');
insert into procurement_test_results select is((select count(*) from inventory.transfers where id=pg_temp.fid('negative.bad.transfer')),0::bigint,'unsupported inbound transfer creates no header');
insert into procurement_test_results select is(pg_temp.ns_open('main'),3::numeric,'unsupported operations leave deficit unchanged');

select pg_temp.ns_po('main.po2','main',2,7);
insert into negative_stock_responses values('main.receipt2',pg_temp.ns_receipt('main.receipt2','main.po2','2','negative.main.receipt2'));
insert into procurement_test_results select is(pg_temp.ns_q('main'),-1::numeric,'partial receipt2 leaves signed quantity-1');
insert into procurement_test_results select is(pg_temp.ns_v('main'),-5::numeric,'partial receipt2@7 corrects carrying value to provisional-5');
insert into procurement_test_results select is(pg_temp.ns_open('main'),1::numeric,'partial receipt covers2 exactly');
insert into procurement_test_results select is((select sum(variance) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.main')),4::numeric,'partial linked COGS variance4 exposed');
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
 where j.source_type='negative_stock.cover' and l.account_id=pg_temp.fid('negative.inventory')),-4::numeric,'partial cover credits inventory4');
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
 where j.source_type='negative_stock.cover' and l.account_id=pg_temp.fid('negative.cogs')),4::numeric,'partial cover debits original COGS4');
insert into procurement_test_results select is(pg_temp.call('post_goods_receipt',pg_temp.ns_receipt_payload('main.receipt2','main.po2','2'),1,'negative.main.receipt2'),
 (select response from negative_stock_responses where name='main.receipt2'),'exact receipt replay creates no second cover');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.main')),1::bigint,'receipt replay preserves one cover');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reverse_goods_receipt',jsonb_build_object('document_id',pg_temp.fid('negative.main.receipt2'),'document_date','2026-09-29','reason','Synthetic reversal'),1)$$,
 '55000','NEGATIVE_STOCK_RECEIPT_REVERSAL_REQUIRES_CORRECTION','covered receipt is not reversible as unused stock');
insert into procurement_test_results select is(pg_temp.ns_q('main'),-1::numeric,'refused receipt reversal retains deficit projection');

-- Closed-period and late outbox failures roll back receipt, cover, journal, PO.
select pg_temp.ns_po('main.po1','main',1,9);
update finance.fiscal_periods set state='closed' where id=pg_temp.fid('period');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_receipt('main.receipt1','main.po1','1')$$,'55000','PERIOD_CLOSED','receipt correction cannot rewrite closed period');
update finance.fiscal_periods set state='open' where id=pg_temp.fid('period');
update finance.accounts set status='inactive' where id=pg_temp.fid('negative.cogs');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_receipt('main.receipt1','main.po1','1')$$,'55000','ACCOUNT_MAPPING_INVALID','inactive original posting account rejects correction without fallback');
update finance.accounts set status='active' where id=pg_temp.fid('negative.cogs');
insert into procurement_test_results select is(pg_temp.ns_v('main'),-5::numeric,'inactive account refusal retains original carrying value');
insert into procurement_test_results select is(pg_temp.ns_open('main'),1::numeric,'inactive account refusal leaves deficit uncovered');
create function pg_temp.ns_fail_outbox() returns trigger language plpgsql as $$begin if new.tenant_id=pg_temp.fid('tenant') then raise exception using errcode='P0001',message='NEGATIVE_STOCK_SYNTHETIC_OUTBOX_FAILURE';end if;return new;end $$;
create trigger negative_stock_synthetic_outbox before insert on core.outbox_events for each row execute function pg_temp.ns_fail_outbox();
insert into procurement_test_results select throws_ok($$select pg_temp.ns_receipt('main.receipt1','main.po1','1')$$,'P0001','NEGATIVE_STOCK_SYNTHETIC_OUTBOX_FAILURE','late outbox rolls back whole receipt and variance');
drop trigger negative_stock_synthetic_outbox on core.outbox_events;
insert into procurement_test_results select is(pg_temp.ns_q('main'),-1::numeric,'late failure leaves quantity-1');
insert into procurement_test_results select is(pg_temp.ns_v('main'),-5::numeric,'late failure leaves carrying-5');
insert into procurement_test_results select is(pg_temp.ns_open('main'),1::numeric,'late failure leaves open deficit1');
insert into procurement_test_results select is((select version from procurement.purchase_orders where id=pg_temp.fid('negative.main.po1')),1::bigint,'late failure preserves PO version');
insert into procurement_test_results select is((select count(*) from procurement.goods_receipts where id=pg_temp.fid('negative.main.receipt1')),0::bigint,'late failure creates no receipt');
insert into negative_stock_responses values('disable',pg_temp.ns_policy(false,'negative.disable'));
insert into procurement_test_results select is(pg_temp.ns_version(),2::bigint,'deactivation appends version2');
insert into procurement_test_results select is((select from_status||':'||to_status from workflow.process_events where command_id=pg_temp.fid('negative.disable')),'active:inactive','policy deactivation records typed immutable process statuses');
update inventory.products set cogs_account_id=pg_temp.fid('negative.replacement-cogs') where id=pg_temp.fid('negative.main');
insert into negative_stock_responses values('main.receipt1',pg_temp.ns_receipt('main.receipt1','main.po1','1','negative.main.receipt1'));
insert into procurement_test_results select is(pg_temp.ns_q('main'),0::numeric,'final receipt fully covers deficit');
insert into procurement_test_results select is(pg_temp.ns_v('main'),0::numeric,'final receipt leaves exact zero carrying value');
insert into procurement_test_results select is(pg_temp.ns_open('main'),0::numeric,'policy OFF still covers prior immutable deficit');
insert into procurement_test_results select is((select sum(l.base_debit-l.base_credit) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id
 where j.source_type='negative_stock.cover' and l.account_id=pg_temp.fid('negative.cogs')),8::numeric,'final receipt9 retains original COGS account totalvariance8');
insert into procurement_test_results select is((select count(*) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id where j.source_type='negative_stock.cover'
 and l.account_id=pg_temp.fid('negative.replacement-cogs')),0::bigint,'current changed product mapping cannot redirect correction');
insert into procurement_test_results select is((select base_value from inventory.stock_movement_lines where source_line_id=pg_temp.fid('negative.main.issue.line')),-20::numeric,'receipt corrections never rewrite original issue');
insert into procurement_test_results select is((select sum(base_debit) from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id where j.source_type='delivery.stock' and j.source_id=pg_temp.fid('negative.main.issue')),20::numeric,'receipt corrections never rewrite original journal');

-- Covered source-linked return restores actual7+9, never the current mapping.
select pg_temp.ns_prepare('sales_return','main.return','main.issue','3');
insert into negative_stock_responses values('main.return',pg_temp.ns_post('sales_return','main.return','negative.main.return'));
insert into procurement_test_results select is(pg_temp.ns_q('main'),3::numeric,'covered source return restores quantity3');
insert into procurement_test_results select is(pg_temp.ns_v('main'),23::numeric,'covered return restores actual receipt cost14+9');
insert into procurement_test_results select is((select sum(value) from inventory.negative_stock_return_allocations where return_movement_line_id in(select id from inventory.stock_movement_lines where source_line_id=pg_temp.fid('negative.main.return.line'))),23::numeric,'return retains linked corrected source allocation23');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_return_allocations where cover_id is not null and return_movement_line_id in(select id from inventory.stock_movement_lines where source_line_id=pg_temp.fid('negative.main.return.line'))),2::bigint,'return holds both immutable receipt cover links');

insert into negative_stock_responses values('reenable',pg_temp.ns_policy(true,'negative.reenable'));
select pg_temp.ns_product('unknown',0,0);select pg_temp.ns_order('unknown.order','unknown','1');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_reserve('unknown.order','1')$$,'55000','NEGATIVE_STOCK_COST_BASIS_UNKNOWN','unknown zero quantity basis rejects');
insert into procurement_test_results select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('negative.unknown.balance')),0::numeric,'unknown basis rejection reserves nothing');
select pg_temp.ns_product('zero',1,0);
insert into procurement_test_results select lives_ok($$select pg_temp.ns_issue('zero.issue','zero','2')$$,'known authoritative zero cost can reach deficit');
insert into procurement_test_results select is(pg_temp.ns_q('zero'),-1::numeric,'known-zero deficit quantity retained');
insert into procurement_test_results select is(pg_temp.ns_v('zero'),0::numeric,'known-zero provisional carrying stays zero');
select pg_temp.ns_product('tracked',1,5,'lot');select pg_temp.ns_order('tracked.order','tracked','2');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_reserve('tracked.order','2')$$,'55000','NEGATIVE_STOCK_TRACKING_REQUIRED','negative policy cannot fabricate missing lot identity');

-- Uncovered return cancels its source deficit before any later receipt.
select pg_temp.ns_product('uncovered');select pg_temp.ns_issue('uncovered.issue','uncovered','4');
select pg_temp.ns_prepare('sales_return','uncovered.return','uncovered.issue','2');select pg_temp.ns_post('sales_return','uncovered.return');
insert into procurement_test_results select is(pg_temp.ns_q('uncovered'),-1::numeric,'uncovered source return cancels2 units');
insert into procurement_test_results select is(pg_temp.ns_v('uncovered'),-5::numeric,'uncovered return restores original provisional10');
insert into procurement_test_results select is(pg_temp.ns_open('uncovered'),1::numeric,'uncovered cancellation reduces only its source deficit');
insert into procurement_test_results select is((select kind from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.uncovered')),'customer_return','uncovered cancellation is immutable source cover');
select pg_temp.ns_po('uncovered.po','uncovered',1,7);select pg_temp.ns_receipt('uncovered.receipt','uncovered.po','1');
insert into procurement_test_results select is(pg_temp.ns_v('uncovered'),0::numeric,'later receipt covers only uncancelled unit');
insert into procurement_test_results select is((select sum(variance) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.uncovered')),2::numeric,'later correction excludes returned deficit units');

-- Receipt beyond deficit leaves the genuine positive balance at actual cost.
select pg_temp.ns_product('excess');select pg_temp.ns_issue('excess.issue','excess','4');
select pg_temp.ns_po('excess.po','excess',5,7);select pg_temp.ns_receipt('excess.receipt','excess.po','5');
insert into procurement_test_results select is(pg_temp.ns_q('excess'),2::numeric,'receipt5 against deficit3 leaves positive2');
insert into procurement_test_results select is(pg_temp.ns_v('excess'),14::numeric,'receipt excess values remaining2 at actual7');
insert into procurement_test_results select is(pg_temp.ns_open('excess'),0::numeric,'excess receipt fully settles deficit');
insert into procurement_test_results select is((select sum(quantity) from inventory.receipt_provenance_positions where product_id=pg_temp.fid('negative.excess')),2::numeric,'only unconsumed actual receipt becomes physical cohort');

-- Immutable ledger order, not transaction timestamps, controls competing deficits.
select pg_temp.ns_product('fifo');select pg_temp.ns_issue('fifo.first','fifo','2');select pg_temp.ns_issue('fifo.second','fifo','2');
select pg_temp.ns_po('fifo.po','fifo',3,7);select pg_temp.ns_receipt('fifo.receipt1','fifo.po','1');
insert into procurement_test_results select is((select inventory.negative_stock_open_quantity(d.tenant_id,d.id) from inventory.negative_stock_deficits d join inventory.stock_movement_lines ml on ml.id=d.issue_movement_line_id
 where ml.source_line_id=pg_temp.fid('negative.fifo.first.line')),0::numeric,'first receipt covers earliest immutable issue completely');
insert into procurement_test_results select is((select inventory.negative_stock_open_quantity(d.tenant_id,d.id) from inventory.negative_stock_deficits d join inventory.stock_movement_lines ml on ml.id=d.issue_movement_line_id
 where ml.source_line_id=pg_temp.fid('negative.fifo.second.line')),2::numeric,'first receipt leaves later issue deficit untouched');
select pg_temp.ns_receipt('fifo.receipt2','fifo.po','2');
insert into procurement_test_results select is(pg_temp.ns_q('fifo'),0::numeric,'FIFO receipts cover all three units');
insert into procurement_test_results select is(pg_temp.ns_v('fifo'),0::numeric,'FIFO cover corrections leave exact zero value');
insert into procurement_test_results select is((select sum(variance) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.fifo')),6::numeric,'two deficits retain total actual minus provisional variance6');

-- One known basis7/3 and deficit3 is covered by three quantity1 receipts. The
-- final portion receives the six-place rounding residue rather than losing it.
select pg_temp.ns_product('rounded',3,7);select pg_temp.ns_issue('rounded.issue','rounded','6');
select pg_temp.ns_po('rounded.po','rounded',3,2.333333);
select pg_temp.ns_receipt('rounded.receipt1','rounded.po','1');select pg_temp.ns_receipt('rounded.receipt2','rounded.po','1');select pg_temp.ns_receipt('rounded.receipt3','rounded.po','1');
insert into procurement_test_results select is((select array_agg(c.provisional_value order by c.id) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.rounded')),
 array[2.333333,2.333334,2.333333]::numeric[],'cumulative provisional allocation preserves final minor unit');
insert into procurement_test_results select is((select sum(provisional_value) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.rounded')),7::numeric,'partial covers sum to exact original provisional7');
insert into procurement_test_results select is((select sum(actual_value) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.rounded')),7::numeric,'receipt rounded shares sum to approved receipt7');
insert into procurement_test_results select is(pg_temp.ns_v('rounded'),0::numeric,'partial rounding corrections leave no carrying residue');

-- Deactivation and reactivation invalidate an old shortage reservation version.
select pg_temp.ns_product('paused');select pg_temp.ns_order('paused.order','paused','2');select pg_temp.ns_reserve('paused.order','2');select pg_temp.ns_prepare('delivery','paused.issue','paused.order','2');
select pg_temp.ns_policy(false,'negative.paused.disable');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_post('delivery','paused.issue')$$,'55000','NEGATIVE_STOCK_POLICY_INACTIVE','policy deactivation blocks already reserved deficit issue');
insert into procurement_test_results select is(pg_temp.ns_q('paused'),1::numeric,'policy change leaves original physical stock intact');
select pg_temp.ns_policy(true,'negative.paused.reenable');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_post('delivery','paused.issue')$$,'40001','NEGATIVE_STOCK_POLICY_VERSION_CONFLICT','old reservation authorization does not revive after reactivation');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_deficits where product_id=pg_temp.fid('negative.paused')),0::bigint,'refused stale reservation creates no deficit');

-- Zero interim cost still holds the original account identities even when no
-- nonzero issue journal existed, and a later actual cost can be returned safely.
select pg_temp.ns_po('zero.po','zero',1,7);select pg_temp.ns_receipt('zero.receipt','zero.po','1');
select pg_temp.ns_prepare('sales_return','zero.return','zero.issue','1');
insert into procurement_test_results select lives_ok($$select pg_temp.ns_post('sales_return','zero.return')$$,'known-zero issue return uses retained original account identities');
insert into procurement_test_results select is(pg_temp.ns_v('zero'),7::numeric,'known-zero covered return restores corrected actual7');

-- An ordinary actual receipt and transfer can exhaust stock before the first
-- override. Retained snapshots must precede quantity/value divergence.
select pg_temp.ns_product('retained',0,0);select pg_temp.ns_po('retained.po','retained',1,11);select pg_temp.ns_receipt('retained.receipt','retained.po','1');
insert into procurement_test_results select is((select carrying_value from inventory.negative_stock_cost_bases where product_id=pg_temp.fid('negative.retained') order by id desc limit 1),11::numeric,'ordinary positive receipt retains aligned authoritative cost11');
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,code,name,created_by)
values(pg_temp.fid('negative.destination'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'NS-DESTINATION','Negative-stock positive transfer destination',pg_temp.fid('creator'));
insert into negative_stock_responses values('retained.transfer.payload',jsonb_build_object('id',pg_temp.fid('negative.retained.transfer'),'operation','immediate','document_date','2026-09-29',
 'reason','Ordinary positive transfer','reference','NS-POSITIVE','source_warehouse_id',pg_temp.fid('warehouse'),'destination_warehouse_id',pg_temp.fid('negative.destination'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.retained.transfer.line'),'product_id',pg_temp.fid('negative.retained'),'quantity','1',
 'unit_id',pg_temp.fid('unit'),'conversion_numerator','1','conversion_denominator','1','serial_ids','[]'::jsonb))));
insert into procurement_test_results select lives_ok($$insert into negative_stock_responses values('retained.transfer',pg_temp.call('transfer_stock',(select response from negative_stock_responses where name='retained.transfer.payload'),null,'negative.retained.transfer'))$$,'ordinary positive transfer remains reachable');
insert into procurement_test_results select is(pg_temp.ns_q('retained'),0::numeric,'ordinary transfer exhausts original source quantity');
insert into procurement_test_results select is(pg_temp.ns_v('retained'),0::numeric,'ordinary transfer exhausts original source value');
insert into procurement_test_results select lives_ok($$select pg_temp.ns_issue('retained.issue','retained','1')$$,'first override after ordinary transfer uses retained authoritative basis');
insert into procurement_test_results select is(pg_temp.ns_v('retained'),-11::numeric,'exhausted source uses last genuine positive11');
insert into procurement_test_results select is(pg_temp.call('transfer_stock',(select response from negative_stock_responses where name='retained.transfer.payload'),null,'negative.retained.transfer'),
 (select response from negative_stock_responses where name='retained.transfer'),'completed positive transfer replays identically after later deficit');
insert into procurement_test_results select throws_ok($$select pg_temp.call('transfer_stock',jsonb_set((select response from negative_stock_responses where name='retained.transfer.payload'),'{lines,0,quantity}','"2"'),null,'negative.retained.transfer')$$,'22023','IDEMPOTENCY_MISMATCH','completed transfer changed-body retry still checks exact hash');
select pg_temp.ns_po('retained.cover.po','retained',1,9);select pg_temp.ns_receipt('retained.cover.receipt','retained.cover.po','1');
insert into procurement_test_results select is(pg_temp.ns_v('retained'),0::numeric,'lower-cost receipt correction leaves zero carrying value');
insert into procurement_test_results select is((select sum(variance) from inventory.negative_stock_covers c join inventory.negative_stock_deficits d on d.id=c.deficit_id where d.product_id=pg_temp.fid('negative.retained')),-2::numeric,'lower-cost actual receipt exposes signed negative variance');

-- A genuinely approved ordinary count can exhaust positive stock and preserve
-- its basis. The later override does not invent a historical cost.
select pg_temp.ns_product('count-basis',0,0);select pg_temp.ns_po('count-basis.po','count-basis',1,13);select pg_temp.ns_receipt('count-basis.receipt','count-basis.po','1');
insert into workflow.workflow_definitions(id,tenant_id,legal_entity_id,document_type,name,status,lifecycle,created_by,updated_by)
values(pg_temp.fid('negative.count.workflow'),pg_temp.fid('tenant'),pg_temp.fid('entity'),'stock_count','Negative-stock normal count','active',
 '{"states":["draft","submitted","approved","rejected","posted","settled","fulfilled","closed","cancelled","reversed"],"transitions":[["draft","submitted"],["submitted","approved"],["submitted","rejected"],["approved","posted"],["rejected","draft"],["draft","cancelled"],["submitted","cancelled"]],"posting_transitions":[["submitted","draft"],["approved","draft"]],"requires_approval":true}',pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into workflow.approval_matrix_steps(id,tenant_id,workflow_definition_id,role_id,step_order,created_by,updated_by)
values(pg_temp.fid('negative.count.step'),pg_temp.fid('tenant'),pg_temp.fid('negative.count.workflow'),pg_temp.fid('approver.role'),1,pg_temp.fid('creator'),pg_temp.fid('creator'));
insert into core.role_permissions(tenant_id,role_id,permission_code)
values(pg_temp.fid('tenant'),pg_temp.fid('approver.role'),'inventory.cost.view') on conflict do nothing;
insert into negative_stock_responses values('normal.count.payload',jsonb_build_object('id',pg_temp.fid('negative.normal.count'),'warehouse_id',pg_temp.fid('warehouse'),'document_date','2026-09-29',
 'reason','Approved normal count loss','offset_account_id',pg_temp.fid('negative.cogs'),
 'lines',jsonb_build_array(jsonb_build_object('line_id',pg_temp.fid('negative.normal.count.line'),'product_id',pg_temp.fid('negative.count-basis'),'counted_quantity','0','empty_unit_cost','0'))));
insert into negative_stock_responses values('normal.count.upsert',pg_temp.call('upsert_stock_count',(select response from negative_stock_responses where name='normal.count.payload'),null,'negative.normal.count.upsert'));
select pg_temp.call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('negative.normal.count'),'action','submit'),1);
select pg_temp.actor('approver');select pg_temp.call('transition_stock_count',jsonb_build_object('document_id',pg_temp.fid('negative.normal.count'),'decision','approved'),2);select pg_temp.actor('creator');
insert into procurement_test_results select lives_ok($$select pg_temp.call('post_stock_adjustment',jsonb_build_object('document_id',pg_temp.fid('negative.normal.count'),'action','post'),3)$$,'approved ordinary count retains posting behavior');
insert into procurement_test_results select is(pg_temp.ns_q('count-basis'),0::numeric,'approved count exhausts physical quantity');
insert into procurement_test_results select is(pg_temp.ns_v('count-basis'),0::numeric,'approved count exhausts original carrying value');
insert into procurement_test_results select lives_ok($$select pg_temp.ns_issue('count-basis.issue','count-basis','1')$$,'override after normal count retains known authoritative basis');
insert into procurement_test_results select is(pg_temp.ns_v('count-basis'),-13::numeric,'count exhaustion retains aligned previous positive13');
insert into procurement_test_results select is(pg_temp.call('upsert_stock_count',(select response from negative_stock_responses where name='normal.count.payload'),null,'negative.normal.count.upsert'),
 (select response from negative_stock_responses where name='normal.count.upsert'),'completed positive count upsert replays identically after later deficit');
delete from core.role_permissions where role_id=pg_temp.fid('creator.role') and permission_code='inventory.cost.view';
insert into procurement_test_results select throws_ok($$select pg_temp.call('upsert_stock_count',(select response from negative_stock_responses where name='normal.count.payload'),null,'negative.normal.count.upsert')$$,'42501',null,'saved count retry rechecks current cost permission');
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.fid('tenant'),pg_temp.fid('creator.role'),'inventory.cost.view');

-- Dated reports and exact source account reconciliation include immutable covers.
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.fid('negative.report.role'),pg_temp.fid('tenant'),'negative-report-reader','Negative report reader',true);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('negative.report.role'),p from unnest(array['inventory.stock.view','inventory.cost.view','finance.view'])p;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.fid('tenant'),pg_temp.fid('creator.membership'),pg_temp.fid('negative.report.role'),pg_temp.fid('entity'),null,pg_temp.fid('creator'));
insert into negative_stock_responses values('report',inventory.build_valuation_report(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 jsonb_build_object('id',pg_temp.fid('negative.report'),'as_of','2026-09-29','account_ids',jsonb_build_array(pg_temp.fid('negative.inventory')))));
insert into negative_stock_responses values('report.original',inventory.negative_stock_original_valuation_report(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 jsonb_build_object('id',pg_temp.fid('negative.report'),'as_of','2026-09-29','account_ids',jsonb_build_array(pg_temp.fid('negative.inventory')))));
insert into procurement_test_results select ok(not exists(select 1 from negative_stock_responses r cross join jsonb_array_elements(r.response->'lots')x
 where r.name='report' and not exists(select 1 from inventory.negative_stock_deficits nd where nd.warehouse_id::text=split_part(x->>'id',':',1) and nd.product_id::text=split_part(x->>'id',':',2))
 and x is distinct from(select oldx from negative_stock_responses oldr cross join jsonb_array_elements(oldr.response->'lots')oldx where oldr.name='report.original' and oldx->>'id'=x->>'id')),'ordinary lot allocations remain identical to the authoritative existing report');
insert into procurement_test_results select ok(not exists(select 1 from negative_stock_responses r cross join jsonb_array_elements(r.response->'stock')s
 where r.name='report' and (s->>'quantity')::numeric<>0 and (s->>'value')::numeric is distinct from(select sum((lot->>'value')::numeric) from jsonb_array_elements(r.response->'lots')lot where lot->>'id' like (s->>'id')||':%')),'negative cover report conserves every nonempty product lot value');
insert into procurement_test_results select is((select x->>'value' from negative_stock_responses r cross join jsonb_array_elements(r.response->'stock')x where r.name='report' and x->>'product_id'=pg_temp.fid('negative.excess')::text),'14.000000','valuation report includes linked negative-cover value correction');
insert into procurement_test_results select ok(not exists(select 1 from negative_stock_responses r cross join jsonb_array_elements(r.response->'stock')x where r.name='report' and (x->>'quantity')::numeric<=0 and x->>'average_cost' is not null),'nonpositive quantities never expose ordinary average cost');
insert into procurement_test_results select ok(not exists(select 1 from negative_stock_responses r cross join jsonb_array_elements(r.response->'differences')x
 where r.name='report' and x->>'evidence_key' in(select 'command:'||m.command_id from inventory.stock_movements m join inventory.stock_movement_lines ml on ml.stock_movement_id=m.id
  join inventory.products pr on pr.id=ml.product_id where pr.sku like 'NS-%')),'negative stock commands reconcile exactly without claiming unrelated synthetic legacy openings');
insert into procurement_test_results select ok(jsonb_array_length(api.negative_stock_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'covers')->'items')>0,'scoped cost evidence exposes cover variance');
insert into procurement_test_results select ok((api.negative_stock_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'deficits')->'items'->0->>'id')~'^[0-9]+$','server ledger cursor ID crosses as string');
insert into procurement_test_results select throws_ok($$update inventory.negative_stock_policy_versions set active=false$$,'55000',null,'policy versions immutable');
insert into procurement_test_results select throws_ok($$update inventory.negative_stock_deficits set quantity=quantity+1$$,'55000',null,'posted deficits immutable');
insert into procurement_test_results select throws_ok($$delete from inventory.negative_stock_covers$$,'55000',null,'cover links immutable');
insert into procurement_test_results select throws_ok($$update inventory.negative_stock_cost_bases set carrying_value=999$$,'55000',null,'basis snapshots immutable');
insert into procurement_test_results select throws_ok($$update inventory.negative_stock_overrides set reason='replacement'$$,'55000',null,'every override audit immutable');
insert into procurement_test_results select throws_ok($$delete from inventory.negative_stock_return_allocations$$,'55000',null,'corrected return allocations remain immutable');
insert into procurement_test_results select ok(not exists(select 1 from inventory.receipt_provenance_positions where quantity<0),'all scenarios preserve nonnegative real cohorts');
insert into procurement_test_results select throws_ok($$select inventory.require_negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 '{"policy_version":"9223372036854775808","reason":"Overflow input"}')$$,'22023','NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID','policy input above signed64 fails canonically');
insert into procurement_test_results select throws_ok($$select inventory.require_negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 '{"policy_version":"01","reason":"Noncanonical input"}')$$,'22023','NEGATIVE_STOCK_OVERRIDE_INPUT_INVALID','policy version leading zero rejected');
insert into procurement_test_results select throws_ok($$select inventory.require_negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 '{"policy_version":"9223372036854775807","reason":"Valid signed64 boundary"}')$$,'40001','NEGATIVE_STOCK_POLICY_VERSION_CONFLICT','valid signed64 maximum reaches actual policy comparison');
insert into inventory.negative_stock_policy_versions(id,tenant_id,legal_entity_id,branch_id,version,active,reason,command_id,request_id,created_by)
values(pg_temp.fid('negative.maximum.policy'),pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),9223372036854775807,true,'Explicit synthetic maximum-version boundary',
 pg_temp.fid('negative.maximum.policy'),pg_temp.fid('negative.maximum.policy'),pg_temp.fid('creator'));
insert into procurement_test_results select is((inventory.require_negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),
 '{"policy_version":"9223372036854775807","reason":"Valid signed64 boundary"}')).version,9223372036854775807::bigint,'actual signed64 policy maximum remains exact');
insert into procurement_test_results select is(api.negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))->>'policy_version','9223372036854775807','policy maximum crosses as exact string');
insert into procurement_test_results select throws_ok($$select pg_temp.ns_policy(false,'negative.maximum.exhausted')$$,'55000','NEGATIVE_STOCK_POLICY_VERSION_EXHAUSTED','exhausted policy sequence rejects explicitly rather than wrapping');
select pg_temp.actor('outsider');
insert into procurement_test_results select throws_ok($$select api.negative_stock_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'))$$,'42501',null,'outsider policy read denied');
insert into procurement_test_results select throws_ok($$select api.negative_stock_evidence(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),'covers')$$,'42501',null,'outsider cost variance evidence denied');
set local role authenticated;
insert into procurement_test_results select throws_ok($$insert into inventory.negative_stock_policy_versions(id) values(gen_random_uuid())$$,'42501',null,'authenticated direct policy writes denied');
insert into procurement_test_results select throws_ok($$select inventory.capture_negative_stock_basis(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),pg_temp.fid('warehouse'),pg_temp.fid('negative.main'),'{}')$$,'42501',null,'authenticated internal basis helper denied');
insert into procurement_test_results select throws_ok($$select api.reserve_sales_order_stock_without_negative_policy(pg_temp.fid('tenant'),pg_temp.fid('entity'),pg_temp.fid('branch'),gen_random_uuid(),gen_random_uuid(),now(),'{}',null)$$,'42501',null,'alternate legacy reservation entrypoint denied');
reset role;
select pg_temp.actor('creator');

-- An immutable authorization survives a different poster editing the active
-- reservation projection. This was independently observed as one strict RED.
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.fid('tenant'),pg_temp.fid('approver.role'),p
from unnest(array['sales.deliveries.post','inventory.stock.override'])p on conflict do nothing;
select pg_temp.ns_product('multi-actor',1,5);
select pg_temp.ns_order('multi-actor.order','multi-actor','4');
select pg_temp.ns_reserve('multi-actor.order','4',true,'negative.multi-actor.reserve');
select pg_temp.ns_prepare('delivery','multi-actor.first','multi-actor.order','2');
select pg_temp.ns_prepare('delivery','multi-actor.second','multi-actor.order','2');
select pg_temp.actor('approver');
insert into procurement_test_results select lives_ok($$select pg_temp.ns_post('delivery','multi-actor.first','negative.multi-actor.first.post')$$,
 'another currently authorized actor can post the first partial deficit delivery');
insert into procurement_test_results select is(pg_temp.ns_q('multi-actor'),-1::numeric,'first partial delivery consumes positive stock and one provisional unit');
insert into procurement_test_results select is(pg_temp.ns_v('multi-actor'),-5::numeric,'first partial deficit retains the authoritative cost basis');
insert into procurement_test_results select is((select updated_by from inventory.stock_reservations where sales_order_id=pg_temp.fid('negative.multi-actor.order') and status='active'),
 pg_temp.fid('approver'),'reservation last editor becomes the partial delivery actor');
insert into procurement_test_results select is((select created_by from inventory.negative_stock_overrides where effect='reserve' and command_id=pg_temp.fid('negative.multi-actor.reserve')),
 pg_temp.fid('creator'),'immutable shortage authorization retains the original reserve actor');
select pg_temp.actor('creator');
insert into procurement_test_results select lives_ok($$select pg_temp.ns_post('delivery','multi-actor.second','negative.multi-actor.second.post')$$,
 'remaining delivery retains original reservation authority after another actor edits its projection');
insert into procurement_test_results select is(pg_temp.ns_q('multi-actor'),-3::numeric,'both independently authored deliveries exhaust the full authorized reservation');
insert into procurement_test_results select is(pg_temp.ns_v('multi-actor'),-15::numeric,'multi-actor deficit retains exact original provisional carrying value');

-- Public client metadata cannot nominate the author of reserve authorization.
select pg_temp.ns_product('author-forgery',1,5);
select pg_temp.ns_order('author-forgery.order','author-forgery','2');
insert into procurement_test_results select lives_ok($$select pg_temp.call('reserve_sales_order_stock',
 jsonb_set(pg_temp.ns_reserve_payload('author-forgery.order','2'),'{negative_stock_override,authorized_by}',to_jsonb(pg_temp.fid('approver')::text))
 ||jsonb_build_object('source_context',jsonb_build_object('negative_stock_override',jsonb_build_object('authorized_by',pg_temp.fid('approver')))),
 (select version from sales.sales_orders where id=pg_temp.fid('negative.author-forgery.order')),'negative.author-forgery.reserve')$$,
 'server canonicalizes explicit and nested forged client authorization authors');
insert into procurement_test_results select is((select source_context#>>'{negative_stock_override,authorized_by}' from inventory.stock_reservations
 where sales_order_id=pg_temp.fid('negative.author-forgery.order') and status='active'),pg_temp.fid('creator')::text,'reservation author comes from the authenticated session');
insert into procurement_test_results select is((select created_by from inventory.negative_stock_overrides where command_id=pg_temp.fid('negative.author-forgery.reserve') and effect='reserve'),
 pg_temp.fid('creator'),'immutable reserve authorization rejects nominated client authors');
select pg_temp.ns_prepare('delivery','author-forgery.issue','author-forgery.order','2');
update inventory.stock_reservations set source_context=jsonb_set(source_context,'{negative_stock_override,authorized_by}',to_jsonb(pg_temp.fid('approver')::text))
 where sales_order_id=pg_temp.fid('negative.author-forgery.order') and status='active';
insert into procurement_test_results select throws_ok($$select pg_temp.ns_post('delivery','author-forgery.issue')$$,'55000','NEGATIVE_STOCK_RESERVATION_AUTHORIZATION_REQUIRED',
 'even trusted synthetic tampering cannot substitute a different original author');
insert into procurement_test_results select is(pg_temp.ns_q('author-forgery'),1::numeric,'forged author refusal leaves physical stock unchanged');
insert into procurement_test_results select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('negative.author-forgery.balance')),2::numeric,
 'forged author refusal preserves the original authorized allocation');
update inventory.stock_reservations set source_context=jsonb_set(source_context,'{negative_stock_override,authorized_by}',to_jsonb(pg_temp.fid('creator')::text))
 where sales_order_id=pg_temp.fid('negative.author-forgery.order') and status='active';
insert into procurement_test_results select lives_ok($$select pg_temp.ns_post('delivery','author-forgery.issue','negative.author-forgery.issue.post')$$,
 'restored original server author matches immutable authority');
insert into procurement_test_results select is(pg_temp.ns_q('author-forgery'),-1::numeric,'canonical-author delivery records the exact deficit quantity');
insert into procurement_test_results select is(pg_temp.ns_v('author-forgery'),-5::numeric,'canonical-author delivery records the exact deficit value');

-- Repeated reservation can change a command version without changing status.
-- It must preserve a typed resulting process status and exact replay semantics.
select pg_temp.ns_product('same-state-normal',1,5);
select pg_temp.ns_order('same-state-normal.order','same-state-normal','1');
insert into negative_stock_responses values('same-state.normal.first',pg_temp.ns_reserve('same-state-normal.order','1',false,'negative.same-state.normal.first'));
insert into negative_stock_responses values('same-state.normal.payload',pg_temp.ns_reserve_payload('same-state-normal.order','1',false));
insert into procurement_test_results select lives_ok($$insert into negative_stock_responses values('same-state.normal.second',pg_temp.call('reserve_sales_order_stock',
 (select response from negative_stock_responses where name='same-state.normal.payload'),
 (select (response#>>'{entity,version}')::bigint from negative_stock_responses where name='same-state.normal.first'),'negative.same-state.normal.second'))$$,
 'positive-only repeated reservation does not create a reserved-to-reserved transition');
insert into procurement_test_results select ok((select from_status is null and to_status='reserved' from workflow.process_events
 where command_id=pg_temp.fid('negative.same-state.normal.second')),'unchanged positive-only reservation keeps the typed resulting status');
insert into procurement_test_results select is((select count(*) from inventory.stock_reservations where sales_order_id=pg_temp.fid('negative.same-state-normal.order')),1::bigint,
 'positive-only same-state command creates no second reservation');
insert into procurement_test_results select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('negative.same-state-normal.balance')),1::numeric,
 'positive-only same-state command cannot allocate a second physical unit');
insert into procurement_test_results select is(pg_temp.call('reserve_sales_order_stock',(select response from negative_stock_responses where name='same-state.normal.payload'),
 (select (response#>>'{entity,version}')::bigint from negative_stock_responses where name='same-state.normal.first'),'negative.same-state.normal.second'),
 (select response from negative_stock_responses where name='same-state.normal.second'),'same-state positive-only receipt replays the exact original result');
insert into procurement_test_results select is((select count(*) from workflow.process_events where command_id=pg_temp.fid('negative.same-state.normal.second')),1::bigint,
 'same-state positive-only replay retains one process event');
insert into procurement_test_results select throws_ok($$select pg_temp.call('reserve_sales_order_stock',jsonb_set(
 (select response from negative_stock_responses where name='same-state.normal.payload'),'{lines,0,requested_base_quantity}','"2"'),
 (select (response#>>'{entity,version}')::bigint from negative_stock_responses where name='same-state.normal.first'),'negative.same-state.normal.second')$$,
 '22023','IDEMPOTENCY_MISMATCH','same-state positive-only changed-body retry remains rejected');

select pg_temp.ns_product('same-state-override',1,5);
select pg_temp.ns_order('same-state-override.order','same-state-override','2');
insert into negative_stock_responses values('same-state.override.first',pg_temp.ns_reserve('same-state-override.order','2',true,'negative.same-state.override.first'));
insert into negative_stock_responses values('same-state.override.payload',pg_temp.ns_reserve_payload('same-state-override.order','1'));
insert into procurement_test_results select lives_ok($$insert into negative_stock_responses values('same-state.override.second',pg_temp.call('reserve_sales_order_stock',
 (select response from negative_stock_responses where name='same-state.override.payload'),
 (select (response#>>'{entity,version}')::bigint from negative_stock_responses where name='same-state.override.first'),'negative.same-state.override.second'))$$,
 'explicit override repeated reservation keeps a valid unchanged-state event');
insert into procurement_test_results select ok((select from_status is null and to_status='reserved' from workflow.process_events
 where command_id=pg_temp.fid('negative.same-state.override.second')),'unchanged override reservation keeps the typed resulting status');
insert into procurement_test_results select is((select count(*) from inventory.negative_stock_overrides where effect='reserve' and source_id=pg_temp.fid('negative.same-state-override.order')),1::bigint,
 'no-op override command cannot manufacture another shortage authorization');
insert into procurement_test_results select is((select allocated_quantity from inventory.stock_balances where id=pg_temp.fid('negative.same-state-override.balance')),2::numeric,
 'same-state override retains exactly the original authorized quantity');
insert into procurement_test_results select is(pg_temp.call('reserve_sales_order_stock',(select response from negative_stock_responses where name='same-state.override.payload'),
 (select (response#>>'{entity,version}')::bigint from negative_stock_responses where name='same-state.override.first'),'negative.same-state.override.second'),
 (select response from negative_stock_responses where name='same-state.override.second'),'same-state override receipt replays exactly');
