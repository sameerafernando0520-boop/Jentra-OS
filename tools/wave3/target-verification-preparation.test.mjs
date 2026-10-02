import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { amountText, assertTarget, digest, exactPositive, fixturePlan, foundationSql,
  receiptCall, reviewedSources, stableId, verifySources, workloadConfig, raceConfig } from './prepare-target-verification.mjs';
import { approvedContext, ledgerSql, preflightSql } from './run-target-fixture-generator.mjs';
import { racePostflightSql } from './prepare-target-race-invariants.mjs';
import { reviewPlan, targetQueries } from './prepare-target-query-plans.mjs';
import { countGate, liveRpcSourceSql, verifyCountEvidence } from './run-reviewed-target-verification.mjs';

// All IDs and claims below are deliberately fictitious OFFLINE fixtures. No JWT
// signature, real authentication, installed fixture, race or timing is implied.
const seed = 'offline-wave3-20261001';
const uid = name => stableId(seed, name);
const scope = { tenant_id: uid('tenant'), legal_entity_id: uid('entity'), branch_id: uid('branch') };
const fixture = { synthetic: true, is_production: false, project_id: 'abcdefghijklmnopqrst',
  url: 'https://abcdefghijklmnopqrst.supabase.co', actor_id: uid('actor'), seed,
  posting_date: '2026-09-30', receipt_lanes: [{ ...scope, warehouse_id: uid('warehouse'),
    order_id: uid('order'), order_line_id: uid('order-line'), product_id: uid('product'),
    expected_version: 4, receipt_count: 3, quantity_per_receipt: '0.000001',
    reviewed_remaining_quantity: '0.000003', reviewed_value_per_receipt: '1.000000' }] };
let assertions = 0;
const check = (name, fn) => test(name, () => { fn(); assertions++; });
check('Exact micro units and values beyond JavaScript safe integer range remain strings', () => {
  assert.equal(exactPositive('90071992547409.123456', 'amount'), 90071992547409123456n);
  assert.equal(amountText('90071992547409.123456'), '90071992547409.123456');
  assert.equal(amountText('1'), '1.000000');
  for (const value of [0.1, '1e-6', '-1', '0', '0.0000001', '100000000000000']) assert.throws(() => exactPositive(value, 'amount'));
});
check('Bounded deterministic receipt IDs, original exact quantities and purchase-order versions', () => {
  assert.equal(assertTarget(fixture), 3);
  const lane = fixture.receipt_lanes[0], first = receiptCall(fixture, lane, 0), third = receiptCall(fixture, lane, 2);
  assert.deepEqual(receiptCall(fixture, lane, 0), first);
  assert.equal(first.rpc, 'post_goods_receipt'); assert.equal(first.params.p_payload.lines[0].accepted_quantity, '0.000001');
  assert.equal(first.params.p_expected_entity_version, 4); assert.equal(third.params.p_expected_entity_version, 6);
  assert.notEqual(first.params.p_command_id, third.params.p_command_id);
  assert.notEqual(first.params.p_command_id, first.params.p_idempotency_key);
  assert.equal(first.checks[2].equals, '1.000000');
  assert.throws(() => receiptCall(fixture, lane, 3), /outside/);
});
check('Development/production and wrong target URLs are rejected offline', () => {
  assert.throws(() => assertTarget({ ...fixture, project_id: 'xpdoufauvrbdmxgngetv' }), /isolated/);
  assert.throws(() => assertTarget({ ...fixture, is_production: true }), /isolated/);
  assert.throws(() => assertTarget({ ...fixture, url: 'https://xpdoufauvrbdmxgngetv.supabase.co' }), /isolated/);
});
check('Invalid dates, stale versions, duplicate order lanes and capacity overflow reject', () => {
  assert.throws(() => assertTarget({ ...fixture, posting_date: '2026-02-31' }), /date/);
  const clone = structuredClone(fixture); clone.receipt_lanes[0].receipt_count = 4;
  assert.throws(() => assertTarget(clone), /remaining quantity/);
  clone.receipt_lanes[0].receipt_count = 3; clone.receipt_lanes[0].expected_version = 0;
  assert.throws(() => assertTarget(clone), /version/);
  assert.throws(() => assertTarget({ ...fixture, receipt_lanes: [...fixture.receipt_lanes, ...fixture.receipt_lanes] }), /One lane/);
});
check('Source fingerprints include all 45 candidate bodies and reject drift', () => {
  const sources = reviewedSources(), order = JSON.parse(fs.readFileSync('docs/verification/remaining-wave3/migration-order-final-20260930-45.json', 'utf8'));
  assert.equal(order.candidates.length, 45);
  for (const c of order.candidates) assert.equal(sources[c.path], c.sha256);
  const plan = fixturePlan(fixture); verifySources(plan); assert.equal(plan.executed, false);
  const clone = structuredClone(plan); clone.source_hashes['tools/wave3/run-target-load.mjs'] = '0'.repeat(64);
  clone.source_bundle_sha256 = digest(clone.source_hashes); assert.throws(() => verifySources(clone), /Source drift/);
  assert.equal(digest({ b: 1, a: 2 }), digest({ a: 2, b: 1 }));
});
check('Foundation generation checks actual candidate columns and always finishes rollback', () => {
  const sql = foundationSql(fixture, { tenants: 2, entities: 2, warehouses: 2, largeProducts: 5 });
  assert.match(sql, /from generate_series\(1,2\) t cross join generate_series\(1,2\) e/);
  assert.match(sql, /insert into core.warehouses/); assert.match(sql, /insert into inventory.products/);
  assert.match(sql, /FRESH_SCALE_COHORT_REQUIRED/); assert.match(sql, /EXISTING_SYNTHETIC_ACTOR_REQUIRED/);
  assert.match(sql, /rollback;\s*$/i);
  assert.match(sql, /select plan\(6\);/);
  assert.equal((sql.match(/select ok\(/g) ?? []).length, 6);
  assert.match(sql, /select \* from finish\(true\);\s*rollback;\s*$/i);
  assert.doesNotMatch(sql, /insert into auth\.|insert into core\.(roles|memberships|document_sequences)|disable trigger|session_replication_role|insert into inventory\.stock|insert into finance\.journal/i);
  assert.throws(() => foundationSql(fixture, { tenants: 501, entities: 10, warehouses: 25, largeProducts: 100000 }), /exceed/);
});
check('Default target foundation recipe plans the exact per-cohort dimensions, without filling installed counts', () => {
  const sql = foundationSql(fixture);
  assert.match(sql, /generate_series\(1,500\) t/); assert.match(sql, /generate_series\(1,10\) e/);
  assert.match(sql, /generate_series\(1,25\) w/); assert.match(sql, /'large_products',100000/);
  assert.match(sql, /'warehouses',125000/);
  const plan = fixturePlan(fixture); assert.equal(plan.fixture_counts, undefined);
});
check('Fixture preflight verifies real approved sources, exact value/capacity, membership, period and guards', () => {
  const sql = preflightSql(fixture);
  for (const value of ['procurement.purchase_orders', 'procurement.purchase_order_lines', 'inventory.products',
    'journal_guards_enabled', 'approved_order', 'capacity_and_exact_value', 'stocked_product',
    'existing_membership', 'no_later_movement', 'rpc_source_md5']) assert.ok(sql.includes(value));
  assert.match(sql, /^begin read only;/); assert.match(sql, /rollback;$/);
  assert.doesNotMatch(sql + ledgerSql, /\b(insert|update|delete|alter|drop|truncate)\b/i);
});
check('Persistent execution rejects silence, absent approval, wrong host and expired sessions', () => {
  const plan = fixturePlan(fixture); assert.throws(() => approvedContext(plan, {}), /Specific/);
  Object.assign(plan, { approval_status: 'explicit_user_approval', approval_reference: 'OFFLINE GUARD TEST ONLY',
    approved_source_bundle_sha256: plan.source_bundle_sha256, approved_ledger_sha256: 'a'.repeat(64),
    approved_new_receipts: plan.planned_receipts, evidence_path: 'docs/verification/remaining-wave3/approved-runs/offline-never-executed.ndjson' });
  assert.throws(() => approvedContext(plan, {}), /direct isolated/);
  const claims = { sub: fixture.actor_id, role: 'authenticated', iss: fixture.url + '/auth/v1', session_id: uid('session'), exp: 1 };
  const env = { WAVE3_ISOLATED_PGHOST: 'db.abcdefghijklmnopqrst.supabase.co', WAVE3_ISOLATED_PGDATABASE: 'postgres',
    WAVE3_ISOLATED_PGUSER: 'postgres', WAVE3_ISOLATED_PGPASSWORD: 'OFFLINE', WAVE3_ISOLATED_PUBLIC_KEY: 'OFFLINE',
    WAVE3_FIXTURE_SESSION_TOKEN: 'header.' + Buffer.from(JSON.stringify(claims)).toString('base64url') + '.unsigned' };
  assert.throws(() => approvedContext(plan, env), /expiry/);
  assert.throws(() => approvedContext(plan, { ...env, WAVE3_ISOLATED_PGHOST: 'db.xpdoufauvrbdmxgngetv.supabase.co' }), /direct isolated/);
});
const queryBindings = { scope, actor_id: fixture.actor_id, product_id: uid('product'), warehouse_id: uid('warehouse'),
  account_id: uid('account'), party_id: uid('party'), bank_id: uid('bank'), open_item_id: uid('item'),
  start_date: '2026-09-01', end_date: '2026-09-30' };
check('Eleven source query plans are scoped and bounded; bank private basis is labelled separately', () => {
  const queries = targetQueries(queryBindings); assert.equal(queries.length, 11);
  for (const q of queries) { assert.ok(q.sql.includes(scope.tenant_id)); assert.match(q.sql, /limit (50|200|500)$/); }
  assert.equal(queries.filter(q => q.database_role === 'authenticated').length, 9);
  assert.equal(queries.filter(q => q.database_role === 'postgres').length, 2);
  assert.match(queries.find(q => q.name === 'payable_balances').sql, /select \*/);
  assert.throws(() => targetQueries({ ...queryBindings, product_id: "x');drop table finance.journal_lines;--" }), /UUID/);
});
check('Plan walker flags high-volume parallel/ordinary sequential scans without changing planner settings', () => {
  const raw = [{ Plan: { 'Node Type': 'Gather', Plans: [{ 'Node Type': 'Parallel Seq Scan', 'Relation Name': 'journal_lines', 'Actual Rows': 1000, 'Rows Removed by Filter': 999999 }] }, 'Execution Time': 12 }];
  const review = reviewPlan(raw); assert.equal(review.no_high_volume_sequential_scan, false);
  assert.equal(review.flagged_nodes[0].relation, 'journal_lines'); assert.equal(review.nodes[1].removed_by_filter, 999999);
  const indexed = [{ Plan: { 'Node Type': 'Index Scan', 'Relation Name': 'journal_lines', 'Index Name': 'tenant_leading', 'Actual Rows': 200 } }];
  assert.equal(reviewPlan(indexed).no_high_volume_sequential_scan, true);
  assert.throws(() => reviewPlan({ fake: true }), /EXPLAIN/);
});
const postflight = { scope, cases: {
  number_reservation: { document_ids: [uid('req1'), uid('req2')] },
  order_allocation: { sales_order_ids: [uid('so1'), uid('so2')], warehouse_id: uid('wh-res'), product_id: uid('product-res'), expected_allocated_quantity: '1', expected_on_hand_quantity: '1' },
  stock_issue: { document_ids: [uid('delivery1'), uid('delivery2')], warehouse_id: uid('wh-issue'), product_id: uid('product-issue'), expected_on_hand_quantity: '0', expected_movement_quantity: '-1' },
  receipt: { document_ids: [uid('receipt1'), uid('receipt2')], warehouse_id: uid('wh-receipt'), product_id: uid('product-receipt'), expected_on_hand_quantity: '1', expected_movement_quantity: '1' },
  matching: { match_ids: [uid('match1'), uid('match2')], statement_line_id: uid('statement-line'), journal_line_id: uid('bank-journal-line') },
  allocation: { source_ids: [uid('ap-credit1'), uid('ap-credit2')], target_id: uid('ap-debit'), expected_target_residual: '0' },
  posting: { document_id: uid('manual') }, close: { period_id: uid('period-close'), expected_state: 'hard_locked', expected_version: 3 },
  reversal: { receipt_id: uid('original-receipt'), warehouse_id: uid('wh-reversal'), product_id: uid('product-reversal'), expected_on_hand_quantity: '0', expected_movement_quantity: '-1' }
}, immutable_rows: [uid('ap-credit1'), uid('ap-credit2'), uid('ap-debit')].map(id => ({ relation: 'finance.open_items', id, row_md5: 'a'.repeat(32) }))
  .concat({ relation: 'procurement.goods_receipts', id: uid('original-receipt'), row_md5: 'b'.repeat(32) }) };
check('All nine postflight classes include relational uniqueness, balances, source links and immutable originals', () => {
  const sql = racePostflightSql(postflight);
  for (const kind of ['number_reservation', 'order_allocation', 'stock_issue', 'receipt', 'matching', 'allocation', 'posting', 'close', 'reversal']) assert.ok(sql.includes("'kind','" + kind + "'"));
  assert.match(sql, /count\(distinct document_number\)=2/); assert.match(sql, /b\.allocated_quantity/);
  assert.match(sql, /sum\(l\.base_debit-l\.base_credit\)=0/); assert.match(sql, /md5\(to_jsonb\(r\)::text\)/);
  assert.match(sql, /^-- PREPARED ONLY/); assert.match(sql, /rollback;\s*$/);
  assert.doesNotMatch(sql, /\b(insert|update|delete|alter|drop|truncate)\b/i);
  const missing = structuredClone(postflight); missing.immutable_rows.pop();
  assert.throws(() => racePostflightSql(missing), /Every original/);
});
check('Postflight refuses arbitrary relation SQL, inexact quantities and malformed source IDs', () => {
  const clone = structuredClone(postflight); clone.immutable_rows.push({ relation: 'auth.users', id: uid('forbidden'), row_md5: 'a'.repeat(32) });
  assert.throws(() => racePostflightSql(clone), /immutable relation/);
  clone.immutable_rows.pop(); clone.cases.stock_issue.expected_on_hand_quantity = 0;
  assert.throws(() => racePostflightSql(clone), /Exact decimal/);
  clone.cases.stock_issue.expected_on_hand_quantity = '0'; clone.cases.matching.statement_line_id = 'bad';
  assert.throws(() => racePostflightSql(clone), /UUID/);
});
check('Preparation requires the five actual ordinary reports and two distinct race actors', () => {
  assert.throws(() => workloadConfig({ fixture, scope, workloads: [] }), /Six/);
  const input = { fixture, scope, workloads: ['read','save','transition','post','ordinary_report','complex_report'].map(kind => ({ kind, calls: [] })) };
  assert.throws(() => workloadConfig(input), /five/);
  assert.throws(() => raceConfig({ fixture, scope, actors: [fixture.actor_id, fixture.actor_id], races: [] }), /distinct/);
});
check('Wrapper uses actual unwrapped SQL count values and verifies actual deployed RPC definitions', () => {
  const counts = { tenants: 500, legal_entities: 5000, warehouses: 125000, minimum_legal_entities_per_tenant: 10,
    minimum_warehouses_per_entity: 25, large_tenants: 1, products_per_large_tenant: 100000,
    stock_movements: 10000000, journal_lines: 20000000 };
  countGate(counts);
  assert.throws(() => countGate({ ...counts, minimum_warehouses_per_entity: 24 }), /warehouses_per_entity/);
  assert.throws(() => countGate({ fixture_counts: counts }), /tenants/);
  const source = liveRpcSourceSql({ workloads: [{ calls: [receiptCall(fixture, fixture.receipt_lanes[0], 0)] }] });
  assert.equal(Object.keys(source.expected).length, 1); assert.match(source.sql, /pg_get_functiondef/);
  assert.match(source.sql, /^begin read only;/); assert.match(source.sql, /rollback;$/);
  assert.throws(() => liveRpcSourceSql({ workloads: [{ calls: [{ rpc: 'unknown_rpc' }] }] }), /reviewed RPC/);
});
check('Genuine small-cohort races require their exact approved counts without inventing a performance population gate', () => {
  const counts = { tenants: 2, legal_entities: 2, warehouses: 2, stock_movements: 3, journal_lines: 6 };
  verifyCountEvidence('races', counts, {}, { approved_fixture_counts_sha256: digest(counts) });
  assert.throws(() => verifyCountEvidence('races', counts, {}, {}), /specifically approved/);
  assert.throws(() => verifyCountEvidence('races', {...counts, journal_lines: 7}, {}, { approved_fixture_counts_sha256: digest(counts) }), /specifically approved/);
  assert.throws(() => verifyCountEvidence('load', counts, {fixture_counts: counts}, {}), /NFR-309/);
});
process.on('exit', () => console.log(JSON.stringify({ offline_preparation_checks: assertions,
  executed_database_or_http_calls: 0, boundary: 'Fictitious tiny recipes and guard/structural tests only; no target authentication, fixture installation, p95 or lock-concurrency evidence.' })));
