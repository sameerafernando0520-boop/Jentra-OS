import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// The same instants straddle three different civil midnights. The production
// calls below use the actual statement clock and the complete posting workflow.
const boundaries = [
 ['2026-11-04T18:29:59Z', '2026-11-04', '2026-11-04', '2026-11-04'],
 ['2026-11-04T18:30:00Z', '2026-11-04', '2026-11-05', '2026-11-04'],
 ['2026-11-04T23:59:59Z', '2026-11-04', '2026-11-05', '2026-11-04'],
 ['2026-11-05T00:00:00Z', '2026-11-05', '2026-11-05', '2026-11-04'],
 ['2026-11-05T07:59:59Z', '2026-11-05', '2026-11-05', '2026-11-04'],
 ['2026-11-05T08:00:00Z', '2026-11-05', '2026-11-05', '2026-11-05'],
];
const dateColumn = {'UTC':1, 'Asia/Colombo':2, 'America/Los_Angeles':3};

export async function exerciseBusinessDate(db, checks, context, zone, postingDate) {
 const {tenantId, entityId, branchId, ownerId, orderId} = context;
 const scope = [tenantId, entityId, branchId];
 const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
 const value = async (sql, args = []) => Object.values(await one(sql, args))[0];
 function check(label, condition) {assert.ok(condition, label); checks.push(label);}
 async function deny(label, code, message, work) {
  await db.exec('savepoint business_date_denial');
  let caught;
  try {await work();} catch (error) {caught = error;}
  await db.exec('rollback to savepoint business_date_denial;release savepoint business_date_denial');
  assert.equal(caught?.code, code, label + ': ' + (caught?.message ?? 'allowed'));
  if (message) assert.equal(caught.message, message, label);
  checks.push(label);
 }
 await db.exec('reset role');
 await db.exec("savepoint connection_timezone;set local timezone='Pacific/Kiritimati'");
 for (const boundary of boundaries) {
  const actual = await value('select core.legal_entity_business_date($1,$2,$3)::text', [tenantId, entityId, boundary[0]]);
  check(`${zone} midnight projection at ${boundary[0]} ignores the connection timezone`, actual === boundary[dateColumn[zone]]);
 }
 await db.exec('rollback to savepoint connection_timezone;release savepoint connection_timezone');
 await deny('business date rejects a tenant/entity mismatch', '42501', 'BUSINESS_DATE_SCOPE_INVALID',
  () => value('select core.legal_entity_business_date($1,$2)', [randomUUID(), entityId]));
 await deny('business date rejects an explicit null instant', '22023', 'BUSINESS_INSTANT_REQUIRED',
  () => value('select core.legal_entity_business_date($1,$2,null)', [tenantId, entityId]));
 check('anonymous, authenticated and service roles cannot execute the date helper', await value(`select bool_and(not has_function_privilege(role_name,
  'core.legal_entity_business_date(uuid,uuid,timestamptz)','execute')) from unnest(array['anon','authenticated','service_role']::name[]) role_name`));
 check('default business date uses the statement clock and is marked STABLE', await value(`select provolatile='s'
  and core.legal_entity_business_date($1,$2)=core.legal_entity_business_date($1,$2,statement_timestamp())
  from pg_proc where oid='core.legal_entity_business_date(uuid,uuid,timestamptz)'::regprocedure`, [tenantId, entityId]));
 const order = await one('select order_date::text,currency_code,customer_id,warehouse_id from sales.sales_orders where id=$1', [orderId]);
 const orderLine = await value('select id from sales.sales_order_lines where sales_order_id=$1', [orderId]);
 const posting = await one(`select count(*)=2 and bool_and(document_date=$2::date) matched
  from sales.deliveries where tenant_id=$1 and status='posted'`, [tenantId, postingDate]);
 check('two governed partial deliveries retain their canonical legal-entity posting date', posting.matched && order.order_date <= postingDate);
 const {past, future} = await one('select ($1::date-1)::text past,($1::date+1)::text future', [postingDate]);
 const ownerSession = await value('select id from auth.sessions where user_id=$1', [ownerId]);
 await db.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({sub:ownerId, aal:'aal2', session_id:ownerSession})]);
 await db.exec('set local role authenticated');
 await deny('direct authenticated access to the private business-date helper fails', '42501', undefined,
  () => value('select core.legal_entity_business_date($1,$2)', [tenantId, entityId]));
 const draftId = randomUUID();
 const draft = await value('select api.upsert_delivery($1,$2,$3,$4,$5,now(),$6,null)', [...scope, randomUUID(), randomUUID(), {
  id:draftId, customer_id:order.customer_id, document_date:future, due_date:future, currency_code:order.currency_code,
  sales_order_id:orderId, warehouse_id:order.warehouse_id,
  lines:[{line_id:randomUUID(), sales_order_line_id:orderLine, base_quantity:'0.125000'}],
 }]);
 const submitted = await value('select api.transition_operational_document($1,$2,$3,$4,$5,now(),$6,$7)',
  [...scope, randomUUID(), randomUUID(), {document_type:'delivery', document_id:draftId, action:'submit'}, draft.entity.version]);
 const blockedCommand = randomUUID();
 await deny('canonical Sales delivery rejects local tomorrow even inside the open fiscal period', '22023', 'FUTURE_POSTING_DATE',
  () => value('select api.post_delivery($1,$2,$3,$4,$5,now(),$6,$7)', [...scope, blockedCommand, randomUUID(),
   {document_id:draftId}, submitted.entity.version]));
 await db.exec('reset role');
 check('future delivery leaves its submitted state, command and stock journals untouched', await value(`select status='submitted'
  and not exists(select 1 from core.command_receipts where command_id=$2)
  and not exists(select 1 from inventory.stock_movements where source_id=$1)
  and not exists(select 1 from finance.journal_entries where source_id=$1) from sales.deliveries where id=$1`, [draftId, blockedCommand]));

 const debit = randomUUID(), credit = randomUUID();
 for (const [id, code, type, balance] of [[debit,'DATE-AR','asset','debit'],[credit,'DATE-SALES','revenue','credit']]) {
  await db.query(`insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
   values($1,$2,$3,$4,$4,$5,$6,$7,$7)`, [id, tenantId, entityId, code, type, balance, ownerId]);
 }
 const journalLines = [{account_id:debit, amount:'2', base_amount:'2'}, {account_id:credit, amount:'-2', base_amount:'-2'}];
 const document = {tenant_id:tenantId, legal_entity_id:entityId, branch_id:branchId, customer_id:order.customer_id,
  currency_code:order.currency_code, base_currency_code:order.currency_code, exchange_rate:'1'};
 const sourceId = randomUUID(), journalRequest = randomUUID(), journalCommand = randomUUID();
 const postJournal = (date, source = sourceId) => value('select finance.flow_post_journal($1,$2,$3,$4,$5,$6)',
  [{...document, document_date:date}, JSON.stringify(journalLines), 'sales_invoice', source, journalRequest, journalCommand]);
 await deny('shared journal rejects a nonempty local-tomorrow posting', '22023', 'FUTURE_POSTING_DATE', () => postJournal(future));
 const journal = await postJournal(postingDate);
 check('shared journal accepts local today with two balanced immutable lines on that date', await value(`select status='posted'
  and posting_date=$2::date and (select count(*)=2 and bool_and(posting_date=$2::date)
   and sum(base_debit)=sum(base_credit) from finance.journal_lines where journal_entry_id=$1)
  from finance.journal_entries where id=$1`, [journal, postingDate]));
 for (const [reference, dueDate] of [['DATE-DUE',postingDate],['DATE-OVERDUE',past]]) {
  await db.query(`insert into finance.open_items(tenant_id,legal_entity_id,branch_id,party_id,source_type,source_id,document_number,
   currency_code,base_currency_code,exchange_rate,original_amount,original_base_amount,posting_date,due_date,journal_entry_id,
   request_id,command_id,correlation_id,created_by) values($1,$2,$3,$4,'sales_invoice',$5,$6,$7,$7,1,1,1,$8,$9,$10,$11,$12,$11,$13)`,
   [...scope, order.customer_id, randomUUID(), reference, order.currency_code, past, dueDate, journal, journalRequest, journalCommand, ownerId]);
 }
 await db.query('select finance.flow_refresh_credit($1)', [document]);
 check('credit refresh classifies yesterday as overdue and local today as due', await value(`select due_exposure=2 and overdue_exposure=1
  from sales.customer_credit_exposures where tenant_id=$1 and legal_entity_id=$2 and branch_id=$3 and customer_id=$4`, [...scope, order.customer_id]));

 // Post one stocked delivery through order confirmation, reservation and stock
 // accounting. A past document date cannot hide a lot expired as of local today.
 const stockedProduct = randomUUID(), cogs = randomUUID(), stockBalance = randomUUID();
 const unit = await value('select base_unit_id from inventory.products where tenant_id=$1 and sku=\'EMAIL-P\'', [tenantId]);
 await db.query(`insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
  values($1,$2,$3,'DATE-COGS','Date COGS','expense','debit',$4,$4)`, [cogs, tenantId, entityId, ownerId]);
 await db.query(`insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,tracking_mode,
  revenue_account_id,inventory_account_id,cogs_account_id,created_by,updated_by)
  values($1,$2,$3,'DATE-LOT','Posting date lot','stocked',$4,'lot',$5,$6,$7,$8,$8)`,
  [stockedProduct, tenantId, entityId, unit, credit, debit, cogs, ownerId]);
 await db.query(`insert into inventory.stock_balances(id,tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,on_hand_quantity,created_by,updated_by)
  values($1,$2,$3,$4,$5,$6,2,$7,$7)`, [stockBalance, ...scope, order.warehouse_id, stockedProduct, ownerId]);
 await db.query(`insert into inventory.stock_valuations(tenant_id,legal_entity_id,branch_id,stock_balance_id,carrying_value,created_by,updated_by)
  values($1,$2,$3,$4,6,$5,$5)`, [...scope, stockBalance, ownerId]);
 const expiredLot = randomUUID(), localTodayLot = randomUUID();
 for (const [id, code, expiry] of [[expiredLot,'DATE-EXPIRED',past],[localTodayLot,'DATE-LOCAL-TODAY',postingDate]]) {
  await db.query(`insert into inventory.lots(id,tenant_id,legal_entity_id,product_id,code,expiry_date,created_by,updated_by)
   values($1,$2,$3,$4,$5,$6,$7,$7)`, [id, tenantId, entityId, stockedProduct, code, expiry, ownerId]);
  await db.query(`insert into inventory.lot_balances(tenant_id,legal_entity_id,branch_id,warehouse_id,product_id,lot_id,on_hand_quantity,created_by,updated_by)
   values($1,$2,$3,$4,$5,$6,1,$7,$7)`, [...scope, order.warehouse_id, stockedProduct, id, ownerId]);
 }
 await db.exec('set local role authenticated');
 const stockOrder = randomUUID(), stockOrderLine = randomUUID();
 const rpc = (name, payload, version = null) => value(`select api.${name}($1,$2,$3,$4,$5,now(),$6,$7)`,
  [...scope, randomUUID(), randomUUID(), payload, version]);
 const stockDraft = await rpc('upsert_sales_order', {id:stockOrder, customer_id:order.customer_id,
  warehouse_id:order.warehouse_id, order_date:past, promised_date:postingDate, rate_date:past,
  currency_code:order.currency_code, exchange_rate:'1', ship_to:{address:'Synthetic stock address'},
  lines:[{line_id:stockOrderLine, product_id:stockedProduct, description:'Posting date lot', unit_id:unit,
   quantity:'2', base_quantity:'2', conversion_numerator:'1', conversion_denominator:'1', unit_price:'5'}]});
 const confirmed = await rpc('transition_operational_document', {document_type:'sales_order', document_id:stockOrder, action:'confirm'}, stockDraft.entity.version);
 await rpc('reserve_sales_order_stock', {sales_order_id:stockOrder, expires_at:new Date(Date.now()+86400000).toISOString(),
  lines:[{sales_order_line_id:stockOrderLine, requested_base_quantity:'2'}]}, confirmed.entity.version);
 const createDelivery = async (date, lotId) => {
  const id = randomUUID();
  const draft = await rpc('upsert_delivery', {id, customer_id:order.customer_id, document_date:date, due_date:date,
   currency_code:order.currency_code, sales_order_id:stockOrder, warehouse_id:order.warehouse_id,
   lines:[{line_id:randomUUID(), sales_order_line_id:stockOrderLine, base_quantity:'1', tracking:{lot_id:lotId}}]});
  const submitted = await rpc('transition_operational_document', {document_type:'delivery', document_id:id, action:'submit'}, draft.entity.version);
  return {id, version:submitted.entity.version};
 };
 const expiredDelivery = await createDelivery(past, expiredLot);
 await deny('backdated delivery cannot issue a lot already expired in the entity timezone', '22023', 'LOT_NOT_SALEABLE',
  () => rpc('post_delivery', {document_id:expiredDelivery.id}, expiredDelivery.version));
 const todayDelivery = await createDelivery(postingDate, localTodayLot);
 const issued = await rpc('post_delivery', {document_id:todayDelivery.id}, todayDelivery.version);
 check('a lot expiring on local today can post through canonical delivery', issued.entity.status === 'posted');
 await db.exec('reset role');
 check('tracked issue posts exact quantities, carrying cost and local stock and journal dates', await value(`select
  (select on_hand_quantity=1 and allocated_quantity=1 from inventory.stock_balances where id=$1)
  and (select carrying_value=3 from inventory.stock_valuations where stock_balance_id=$1)
  and (select on_hand_quantity=1 from inventory.lot_balances where lot_id=$2)
  and (select on_hand_quantity=0 from inventory.lot_balances where lot_id=$3)
  and exists(select 1 from inventory.stock_movements where source_id=$4 and posting_date=$5::date)
  and exists(select 1 from finance.journal_entries where source_id=$4 and source_type='delivery.stock' and posting_date=$5::date)
  and not exists(select 1 from inventory.stock_movements where source_id=$6)`,
  [stockBalance, expiredLot, localTodayLot, todayDelivery.id, postingDate, expiredDelivery.id]));
}
