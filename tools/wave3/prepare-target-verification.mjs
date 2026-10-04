import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { assertRaceClass } from './target_review_guards.mjs';
import { assertOrdinaryReportBinding, ordinaryReportMetrics } from './target_review_aging.mjs';
import { reviewedCandidateSelection } from './target_review_selection.mjs';

// This compiler performs no network calls. Planned counts are never installed counts.
export const forbiddenProject = 'xpdoufauvrbdmxgngetv';
const ordered = value => Array.isArray(value) ? value.map(ordered) :
  value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k => [k, ordered(value[k])])) : value;
export const digest = value => crypto.createHash('sha256')
  .update(typeof value === 'string' ? value : JSON.stringify(ordered(value))).digest('hex');
const uuidPattern = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const hashPattern = /^[a-f0-9]{64}$/i;
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const orderPath = 'docs/verification/remaining-wave3/migration-order-final-20260930-45.json';
const schemaPath = 'docs/verification/remaining-wave3/schema-after-45-20260930.json';
const fixtureQueryPath = 'tools/wave3/verify-target-fixtures.sql';
const raceKinds = ['number_reservation', 'order_allocation', 'stock_issue', 'receipt',
  'matching', 'allocation', 'posting', 'close', 'reversal'];
const workloadKinds = ['read', 'save', 'transition', 'post', 'ordinary_report', 'complex_report'];
const sourceFiles = [orderPath, schemaPath, fixtureQueryPath,
  'docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md',
  'tools/wave3/run-independent-sessions.mjs', 'tools/wave3/run-target-load.mjs',
  'tools/wave3/prepare-target-verification.mjs', 'tools/wave3/run-target-fixture-generator.mjs',
  'tools/wave3/prepare-target-race-invariants.mjs',
  'tools/wave3/prepare-target-query-plans.mjs',
  'tools/wave3/run-reviewed-target-verification.mjs',
  'tools/wave3/target_review_guards.mjs',
  'tools/wave3/target_review_aging.mjs',
  'tools/wave3/target_review_selection.mjs',
  'tools/wave3/strict-candidate-evidence.mjs',
  'docs/blueprint/57_WAVE3_TARGET_VERIFICATION_CONTRACT.md',
  'packages/jentra_platform/lib/src/wave3_observability_allowlist.dart'];

export function stableId(seed, identity) {
  assert.equal(typeof seed, 'string'); assert.ok(seed.length >= 8 && seed.length <= 100);
  const bytes = crypto.createHash('sha256').update(seed + '\0' + identity).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
export function exactPositive(value, label) {
  if (typeof value !== 'string' || !/^(0|[1-9]\d{0,13})(\.\d{1,6})?$/.test(value))
    throw Error(`${label} must be a positive exact decimal string within numeric(20,6)`);
  const [whole, decimal = ''] = value.split('.');
  const micro = BigInt(whole) * 1000000n + BigInt(decimal.padEnd(6, '0'));
  if (micro <= 0n) throw Error(`${label} must be positive`);
  return micro;
}
export function amountText(value) {
  const micro = exactPositive(value, 'amount');
  return `${micro / 1000000n}.${String(micro % 1000000n).padStart(6, '0')}`;
}
export function assertTarget(config) {
  if (config.synthetic !== true || config.is_production !== false ||
    !/^[a-z]{20}$/.test(config.project_id ?? '') || config.project_id === forbiddenProject ||
    config.url !== `https://${config.project_id}.supabase.co`)
    throw Error('A separately approved isolated synthetic project is required');
  if (!/^[a-zA-Z0-9_.-]{8,100}$/.test(config.seed ?? '')) throw Error('A bounded deterministic seed is required');
  if (!uuidPattern.test(config.actor_id ?? '')) throw Error('Existing synthetic actor ID required');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(config.posting_date ?? '') ||
    !Number.isFinite(Date.parse(config.posting_date + 'T00:00:00Z')) ||
    new Date(config.posting_date + 'T00:00:00Z').toISOString().slice(0, 10) !== config.posting_date)
    throw Error('Exact reviewed posting date required');
  if (!config.receipt_lanes?.length || config.receipt_lanes.length > 250000)
    throw Error('Existing approved purchase-order receipt lanes required');
  const seen = new Set(); let planned = 0;
  for (const lane of config.receipt_lanes) {
    for (const key of ['tenant_id', 'legal_entity_id', 'branch_id', 'warehouse_id', 'order_id',
      'order_line_id', 'product_id']) if (!uuidPattern.test(lane[key] ?? '')) throw Error(`Invalid ${key}`);
    if (seen.has(lane.order_id)) throw Error('One lane per purchase order preserves independent version progression');
    seen.add(lane.order_id);
    if (!Number.isSafeInteger(lane.expected_version) || lane.expected_version < 1 ||
      !Number.isSafeInteger(lane.receipt_count) || lane.receipt_count < 1 || lane.receipt_count > 1000000)
      throw Error('Bounded receipt count and exact expected version required');
    if (BigInt(lane.expected_version) + BigInt(lane.receipt_count) - 1n > BigInt(Number.MAX_SAFE_INTEGER))
      throw Error('Receipt lane exceeds the exact optimistic version range');
    const quantity = exactPositive(lane.quantity_per_receipt, 'quantity_per_receipt');
    const capacity = exactPositive(lane.reviewed_remaining_quantity, 'reviewed_remaining_quantity');
    if (BigInt(lane.receipt_count) * quantity > capacity) throw Error('Receipt lane exceeds reviewed remaining quantity');
    exactPositive(lane.reviewed_value_per_receipt, 'reviewed_value_per_receipt');
    planned += lane.receipt_count;
  }
  if (!Number.isSafeInteger(planned) || planned > 10000000) throw Error('Approved fixture budget is at most ten million new receipts');
  return planned;
}
export function reviewedSchema(selection) { return reviewedCandidateSelection(selection).schema; }
export function reviewedSources(selection) {
  const selected=reviewedCandidateSelection(selection),order=selected.manifest;
  const common=sourceFiles.filter(file=>file!==orderPath&&file!==schemaPath);
  const sources = Object.fromEntries([...new Set([...common, ...selected.artifact_paths, ...order.candidates.map(c => c.path)])]
    .map(filename => [filename, digest(fs.readFileSync(path.join(repo, filename), 'utf8'))]));
  for (const c of order.candidates) if (sources[c.path] !== c.sha256)
    throw Error('Candidate migration differs from the reviewed dependency manifest: ' + c.path);
  return sources;
}
export function command(config, label, scope, rpc, payload, expectedVersion = null) {
  return { rpc, params: { p_tenant_id: scope.tenant_id, p_legal_entity_id: scope.legal_entity_id,
    p_branch_id: scope.branch_id, p_command_id: stableId(config.seed, label + ':command'),
    p_idempotency_key: stableId(config.seed, label + ':idempotency'),
    p_client_timestamp: config.posting_date + 'T12:00:00.000Z',
    p_payload: payload, p_expected_entity_version: expectedVersion } };
}
export function receiptCall(config, lane, ordinal) {
  if (!Number.isInteger(ordinal) || ordinal < 0 || ordinal >= lane.receipt_count) throw Error('Receipt ordinal outside lane');
  if (!Number.isSafeInteger(lane.expected_version) || lane.expected_version < 1 ||
    BigInt(lane.expected_version) + BigInt(ordinal) > BigInt(Number.MAX_SAFE_INTEGER)) throw Error('Receipt expected version is outside the exact integer range');
  const label = `receipt:${lane.order_id}:${ordinal}`;
  const id = stableId(config.seed, label + ':document');
  return { ...command(config, label, lane, 'post_goods_receipt', {
    id, order_id: lane.order_id, warehouse_id: lane.warehouse_id, document_date: config.posting_date,
    reference: `W3-SCALE-${ordinal}-${lane.order_id.slice(0, 8)}`,
    lines: [{ line_id: stableId(config.seed, label + ':line'), order_line_id: lane.order_line_id,
      accepted_quantity: lane.quantity_per_receipt, rejected_quantity: '0', serial_codes: [] }]
  }, lane.expected_version + ordinal), checks: [{ pointer: '/entity/id', equals: id },
    { pointer: '/entity/status', equals: 'posted' },
    { pointer: '/entity/net_amount', equals: amountText(lane.reviewed_value_per_receipt) }] };
}
export function fixturePlan(config) {
  const planned = assertTarget(config), sources = reviewedSources(config.candidate_review);
  return { ...config, source_hashes: sources, source_bundle_sha256: digest(sources),
    fixture_counts_query_sha256: sources[fixtureQueryPath], planned_receipts: planned,
    planned_minimum_journal_lines: planned * 2, executed: false,
    boundary: 'Recipe only. Existing hierarchy/products/approved orders require actual isolated-target preflight. Receipts create real source links and balanced journals through authenticated candidate commands. No count, timing, authentication or concurrency result is claimed.',
    first_receipt: receiptCall(config, config.receipt_lanes[0], 0) };
}

// A fresh, rolled-back foundation fixture, with deterministic hierarchy and accounts.
// Its output never installs users, permissions, sequences, migrations or ledger rows.
export function foundationSql(config, dimensions = { tenants: 500, entities: 10, warehouses: 25, largeProducts: 100000 }) {
  if (!uuidPattern.test(config.actor_id ?? '') || !/^[a-zA-Z0-9_.-]{8,100}$/.test(config.seed ?? ''))
    throw Error('Existing actor and deterministic seed required');
  const { tenants, entities, warehouses, largeProducts } = dimensions;
  for (const n of Object.values(dimensions)) if (!Number.isSafeInteger(n) || n < 1) throw Error('Positive bounded dimensions required');
  if (tenants > 500 || entities > 10 || warehouses > 25 || largeProducts > 100000) throw Error('Foundation dimensions exceed the reviewed target');
  const seed = config.seed.replaceAll("'", "''"), actor = config.actor_id;
  const schema = reviewedSchema(config.candidate_review);
  const columns = {
    'core.tenants': ['id', 'name', 'slug', 'created_by'],
    'core.legal_entities': ['id', 'tenant_id', 'name', 'code', 'created_by'],
    'core.branches': ['id', 'tenant_id', 'legal_entity_id', 'name', 'code', 'created_by'],
    'core.warehouses': ['id', 'tenant_id', 'legal_entity_id', 'branch_id', 'name', 'code', 'created_by'],
    'inventory.units': ['id', 'tenant_id', 'code', 'name', 'symbol', 'category', 'precision', 'created_by', 'updated_by'],
    'finance.accounts': ['id', 'tenant_id', 'legal_entity_id', 'code', 'name', 'account_type', 'normal_balance', 'currency_code', 'created_by', 'updated_by'],
    'inventory.products': ['id', 'tenant_id', 'legal_entity_id', 'sku', 'name', 'kind', 'base_unit_id', 'inventory_account_id', 'created_by', 'updated_by'],
    'finance.fiscal_periods': ['id', 'tenant_id', 'legal_entity_id', 'name', 'start_date', 'end_date', 'created_by', 'updated_by'],
    'crm.parties': ['id', 'tenant_id', 'code', 'legal_name', 'display_name', 'kind', 'created_by', 'updated_by']
  };
  for (const [table, used] of Object.entries(columns)) {
    if (!schema.tables[table]) throw Error('Unreviewed fixture relation ' + table);
    for (const column of used) if (!schema.tables[table].columns[column]) throw Error('Unreviewed fixture column ' + table + '.' + column);
    for (const [name, col] of Object.entries(schema.tables[table].columns))
      if (!col.nullable && col.default === null && !used.includes(name)) throw Error('Required fixture column omitted: ' + table + '.' + name);
  }
  const id = expression => `pg_temp.w3_id(${expression})`;
  return `-- PREPARED ONLY: no execution under the current authorization.
-- Synthetic foundation rollback rehearsal; source commands create all valuation provenance later.
-- No auth/users/roles, document sequences, stock opening, ledger or trigger bypass changes.
begin;
set local statement_timeout = '30min';
set local search_path = public, extensions, pg_temp;
select plan(6);
create function pg_temp.w3_id(label text) returns uuid language sql immutable as $$
 select (substr(md5('${seed}'||':'||label),1,8)||'-'||substr(md5('${seed}'||':'||label),9,4)||'-5'||substr(md5('${seed}'||':'||label),14,3)||'-8'||substr(md5('${seed}'||':'||label),18,3)||'-'||substr(md5('${seed}'||':'||label),21,12))::uuid;
$$;
do $$begin
 if not exists(select 1 from auth.users where id='${actor}'::uuid) then raise exception 'EXISTING_SYNTHETIC_ACTOR_REQUIRED';end if;
 if exists(select 1 from core.tenants where slug like 'wave3-scale-%') then raise exception 'FRESH_SCALE_COHORT_REQUIRED';end if;
 if not exists(select 1 from core.currencies where code='LKR' and active) then raise exception 'ACTIVE_LKR_REQUIRED';end if;
end$$;
create temporary table w3_scopes as select t,e,${id("'tenant:'||t")} tenant_id,
 ${id("'entity:'||t||':'||e")} legal_entity_id,${id("'branch:'||t||':'||e")} branch_id
 from generate_series(1,${tenants}) t cross join generate_series(1,${entities}) e;
insert into core.tenants(id,name,slug,created_by)
 select ${id("'tenant:'||t")},'Wave 3 synthetic tenant '||t,
 case when t=1 then 'wave3-scale-large-' else 'wave3-scale-' end||t,'${actor}'::uuid from generate_series(1,${tenants}) t;
insert into core.legal_entities(id,tenant_id,name,code,created_by)
 select legal_entity_id,tenant_id,'Synthetic entity '||e,'E'||e,'${actor}'::uuid from w3_scopes;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
 select branch_id,tenant_id,legal_entity_id,'Synthetic branch '||e,'BR'||e,'${actor}'::uuid from w3_scopes;
insert into core.warehouses(id,tenant_id,legal_entity_id,branch_id,name,code,created_by)
 select ${id("'warehouse:'||s.t||':'||s.e||':'||w")},tenant_id,legal_entity_id,branch_id,
 'Synthetic warehouse '||w,'WH'||w,'${actor}'::uuid from w3_scopes s cross join generate_series(1,${warehouses}) w;
insert into inventory.units(id,tenant_id,code,name,symbol,category,precision,created_by,updated_by)
 select ${id("'unit:'||t")},${id("'tenant:'||t")},'EA','Synthetic each','ea','quantity',6,'${actor}'::uuid,'${actor}'::uuid from generate_series(1,${tenants}) t;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,currency_code,created_by,updated_by)
 select ${id("'account:'||s.t||':'||s.e||':'||a.code")},tenant_id,legal_entity_id,a.code,a.name,a.kind,a.balance,'LKR','${actor}'::uuid,'${actor}'::uuid
 from w3_scopes s cross join(values ('INV','Synthetic inventory','asset','debit'),('GRNI','Synthetic GRNI','liability','credit'),('EXP','Synthetic expense','expense','debit')) a(code,name,kind,balance);
insert into inventory.products(id,tenant_id,legal_entity_id,sku,name,kind,base_unit_id,inventory_account_id,created_by,updated_by)
 select ${id("'product:'||s.t||':'||s.e||':'||p")},tenant_id,legal_entity_id,'E'||e||'.P'||p,'Synthetic product '||e||'.'||p,'stocked',${id("'unit:'||s.t")},${id("'account:'||s.t||':'||s.e||':INV'")},'${actor}'::uuid,'${actor}'::uuid
 from w3_scopes s cross join lateral generate_series(1,case when s.t=1 then ${Math.floor(largeProducts / entities)}+case when s.e<=${largeProducts % entities} then 1 else 0 end else 1 end) p;
insert into finance.fiscal_periods(id,tenant_id,legal_entity_id,name,start_date,end_date,created_by,updated_by)
 select ${id("'period:'||s.t||':'||s.e")},tenant_id,legal_entity_id,'Synthetic September 2026','2026-09-01','2026-09-30','${actor}'::uuid,'${actor}'::uuid from w3_scopes s;
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,created_by,updated_by)
 select ${id("'supplier:'||t")},${id("'tenant:'||t")},'SCALE-SUPPLIER','Synthetic supplier '||t,'Synthetic supplier '||t,'supplier','${actor}'::uuid,'${actor}'::uuid from generate_series(1,${tenants}) t;
select ok((select count(*) from core.tenants where slug like 'wave3-scale-%')=${tenants},'Exact synthetic tenant cohort');
select ok((select count(*) from core.legal_entities e join core.tenants t on t.id=e.tenant_id where t.slug like 'wave3-scale-%')=${tenants * entities},'Exact entity cohort');
select ok((select count(*) from core.warehouses w join core.tenants t on t.id=w.tenant_id where t.slug like 'wave3-scale-%')=${tenants * entities * warehouses},'Exact warehouse cohort');
select ok((select count(*) from inventory.products p join core.tenants t on t.id=p.tenant_id where t.slug like 'wave3-scale-large-%')=${largeProducts},'Exact large tenant product cohort');
select ok(not exists(select 1 from inventory.stock_movements m join core.tenants t on t.id=m.tenant_id where t.slug like 'wave3-scale-%'),'Foundation invents no stock movement provenance');
select ok(not exists(select 1 from finance.journal_lines l join core.tenants t on t.id=l.tenant_id where t.slug like 'wave3-scale-%'),'Foundation invents no posted journals');
select jsonb_build_object('planned_only',true,'tenants',${tenants},'entities',${tenants * entities},'warehouses',${tenants * entities * warehouses},'large_products',${largeProducts},'boundary','All rows rolled back; not installed scale evidence');
select * from finish(true);
rollback;
`;
}

// Concrete reviewed fixture bindings are inputs, rather than invented document IDs.
// Every mutation receives a new deterministic identity and exact checks.
export function workloadConfig(input) {
  assertTarget(input.fixture);
  const target = input.fixture, scope = input.scope;
  for (const k of ['tenant_id', 'legal_entity_id', 'branch_id']) if (!uuidPattern.test(scope?.[k] ?? '')) throw Error('Workload scope required');
  if (!input.workloads?.length || workloadKinds.some(k => !input.workloads.some(w => w.kind === k))) throw Error('Six concrete workload classes required');
  const metrics = ordinaryReportMetrics;
  if (metrics.some(metric => !input.workloads.some(w => w.kind === 'ordinary_report' && w.metric === metric)))
    throw Error('All five NFR-320 ordinary-report measurements required');
  const workloads = input.workloads.map(w => {
    if (!workloadKinds.includes(w.kind) || !w.calls || w.calls.length < 110) throw Error('At least 110 concrete calls per workload required');
    return { name: w.name, kind: w.kind, metric: w.metric ?? null, warmup: 10, calls: w.calls.map((binding, index) => {
      if (!binding.checks?.length) throw Error('Reviewed exact response checks required');
      if (w.kind === 'ordinary_report') {
        assertOrdinaryReportBinding(w.metric,binding);
      }
      const call = binding.read_params ? { rpc: binding.rpc, params: { ...binding.read_params,
        ...Object.fromEntries(Object.entries(scope).map(([k, v]) => ['p_' + k, v])) } } :
        command(target, `load:${w.name}:${index}`, scope, binding.rpc, binding.payload, binding.expected_version ?? null);
      return { ...call, checks: binding.checks, ...(binding.aging?{aging:binding.aging}:{}) };
    }) };
  });
  return { synthetic: true, is_production: false, project_id: target.project_id, url: target.url,
    actor_id: target.actor_id, scope, fixture_counts: input.measured_fixture_counts,
    fixture_counts_query_sha256: digest(fs.readFileSync(path.join(repo, fixtureQueryPath), 'utf8')),
    fixture_source_sha256: digest(fixturePlan(target)), environment: input.environment, workloads,
    ...(target.candidate_review?{candidate_review:target.candidate_review}:{}),
    evidence_path: input.evidence_path, approval_status: 'not_requested', executed: false };
}
export function raceConfig(input) {
  assertTarget(input.fixture);
  if (!input.scope || !['tenant_id', 'legal_entity_id', 'branch_id'].every(k => uuidPattern.test(input.scope[k] ?? '')))
    throw Error('Exact race scope required');
  if (!input.actors?.every(x => uuidPattern.test(x)) || input.actors.length !== 2 || input.actors[0] === input.actors[1]) throw Error('Two distinct existing actors required');
  if (input.races?.length !== 9 || raceKinds.some(k => input.races.filter(r => r.kind === k).length !== 1)) throw Error('Nine concrete race bindings required');
  const schema = reviewedSchema(input.fixture.candidate_review);
  const races = input.races.map(r => {
    if (r.commands?.length !== 2 || !r.invariants?.length || !Number.isInteger(r.expected_successes)) throw Error('Two commands and exact invariants required');
    assertRaceClass(r.kind, r.commands);
    return { ...r, commands: r.commands.map((c, i) => {
      if (!Object.keys(schema.functions).some(signature => signature.startsWith('api.' + c.rpc + '('))) throw Error('Unreviewed RPC signature');
      return command(input.fixture, `race:${r.kind}:${i}`, input.scope, c.rpc, c.payload, c.expected_version ?? null);
    }), invariants: r.invariants.map(c => ({ ...c, params: { ...c.params,
      ...Object.fromEntries(Object.entries(input.scope).map(([k, v]) => ['p_' + k, v])) } })) };
  });
  return { synthetic: true, is_production: false, project_id: input.fixture.project_id,
    url: input.fixture.url, actors: input.actors, scope: input.scope, races,
    ...(input.fixture.candidate_review?{candidate_review:input.fixture.candidate_review}:{}),
    evidence_path: input.evidence_path, approval_status: 'not_requested', executed: false };
}
export function verifySources(plan) {
  if (!plan.source_hashes || !hashPattern.test(plan.source_bundle_sha256 ?? '') || digest(plan.source_hashes) !== plan.source_bundle_sha256) throw Error('Reviewed source bundle required');
  const required=reviewedSources(plan.candidate_review);
  if(digest(Object.keys(plan.source_hashes).sort())!==digest(Object.keys(required).sort()))throw Error('Complete explicitly selected candidate/artifact source bundle required.');
  for (const [filename, expected] of Object.entries(plan.source_hashes)) {
    const resolved = path.resolve(repo, filename);
    if (!resolved.startsWith(repo + path.sep) || !hashPattern.test(expected) || digest(fs.readFileSync(resolved, 'utf8')) !== expected)
      throw Error('Source drift or invalid source path: ' + filename);
  }
}

const main = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (main) {
  const inputFile = process.argv.slice(2).find(x => x.endsWith('.json'));
  const outputIndex = process.argv.indexOf('--output');
  if (!inputFile || outputIndex < 0 || !process.argv[outputIndex + 1])
    throw Error('Usage: node tools/wave3/prepare-target-verification.mjs concrete-bindings.json --output task-owned-directory');
  const input = JSON.parse(fs.readFileSync(inputFile, 'utf8'));
  if(input.fixture?.candidate_review?.candidate_count!==46)throw Error('Current Wave3 target preparation requires an explicit complete46 candidate selection. Historical45 library recipes remain separate.');
  const output = path.resolve(process.argv[outputIndex + 1]);
  const evidenceRoot = path.join(repo, 'docs/verification/remaining-wave3');
  if (!output.startsWith(evidenceRoot + path.sep)) throw Error('Task-owned verification output directory required');
  if (fs.existsSync(output)) throw Error('Fresh output directory required; existing evidence is preserved');
  const fixture = fixturePlan(input.fixture); verifySources(fixture);
  const load = workloadConfig(input), races = raceConfig(input);
  fs.mkdirSync(output, { recursive: false });
  fs.writeFileSync(path.join(output, 'fixture-plan.json'), JSON.stringify(fixture, null, 2) + '\n');
  fs.writeFileSync(path.join(output, 'load-plan.json'), JSON.stringify(load, null, 2) + '\n');
  fs.writeFileSync(path.join(output, 'race-plan.json'), JSON.stringify(races, null, 2) + '\n');
  fs.writeFileSync(path.join(output, 'foundation-rehearsal.sql'), foundationSql(input.fixture));
  console.log(JSON.stringify({ output, executed: false, planned_receipts: fixture.planned_receipts,
    source_bundle_sha256: fixture.source_bundle_sha256, boundary: 'Offline preparation only; no count or p95/concurrency evidence.' }));
}
