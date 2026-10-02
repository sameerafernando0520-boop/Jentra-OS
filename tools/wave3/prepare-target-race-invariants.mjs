import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { digest } from './prepare-target-verification.mjs';

// Supplement fixed HTTP read assertions with cross-row/ledger invariants. This
// compiler never connects. Running generated SQL needs the separate target approval.
const uuid = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const id = value => { if (!uuid.test(value ?? '')) throw Error('Concrete synthetic UUID required'); return "'" + value + "'::uuid"; };
const pair = values => { if (values?.length !== 2 || values[0] === values[1]) throw Error('Two distinct concrete fixture IDs required'); return values.map(id).join(','); };
const amount = value => { if (typeof value !== 'string' || !/^-?(0|[1-9]\d{0,13})(\.\d{1,6})?$/.test(value)) throw Error('Exact decimal expected value required'); return "'" + value + "'::numeric"; };
export function racePostflightSql(input) {
  const scope = input.scope;
  const scoped = alias => `${alias}.tenant_id=${id(scope?.tenant_id)} and ${alias}.legal_entity_id=${id(scope?.legal_entity_id)} and ${alias}.branch_id=${id(scope?.branch_id)}`;
  const c = input.cases;
  if (!c) throw Error('Concrete nine-case postflight fixture bindings required');
  const onHand = x => `(select b.on_hand_quantity from inventory.stock_balances b where ${scoped('b')} and b.warehouse_id=${id(x.warehouse_id)} and b.product_id=${id(x.product_id)})=${amount(x.expected_on_hand_quantity)}`;
  const quantity = (x, sourceType, sourceIds) => `(select sum(l.base_quantity) from inventory.stock_movement_lines l join inventory.stock_movements m on m.tenant_id=l.tenant_id and m.id=l.stock_movement_id where ${scoped('l')} and m.source_type='${sourceType}' and m.source_id in(${sourceIds}) and l.warehouse_id=${id(x.warehouse_id)} and l.product_id=${id(x.product_id)})=${amount(x.expected_movement_quantity)}`;
  const queries = [
    ['number_reservation', `select count(*)=2 and count(document_number)=2 and count(distinct document_number)=2 as passed from procurement.requisitions r where ${scoped('r')} and r.id in(${pair(c.number_reservation.document_ids)}) and r.status in('approved','pending_approval')`],
    ['order_allocation', `select count(*)=1 and sum(base_quantity)=${amount(c.order_allocation.expected_allocated_quantity)} and (select b.allocated_quantity from inventory.stock_balances b where ${scoped('b')} and b.warehouse_id=${id(c.order_allocation.warehouse_id)} and b.product_id=${id(c.order_allocation.product_id)})=${amount(c.order_allocation.expected_allocated_quantity)} and ${onHand(c.order_allocation)} as passed from inventory.stock_reservations r where ${scoped('r')} and r.sales_order_id in(${pair(c.order_allocation.sales_order_ids)}) and r.warehouse_id=${id(c.order_allocation.warehouse_id)} and r.product_id=${id(c.order_allocation.product_id)} and r.status='active'`],
    ['stock_issue', `select ${onHand(c.stock_issue)} and ${quantity(c.stock_issue, 'delivery', pair(c.stock_issue.document_ids))} and (select count(*)=1 from inventory.stock_movements m where ${scoped('m')} and m.source_type='delivery' and m.source_id in(${pair(c.stock_issue.document_ids)})) as passed`],
    ['receipt', `select ${onHand(c.receipt)} and ${quantity(c.receipt, 'goods_receipt', pair(c.receipt.document_ids))} and (select count(*)=1 from procurement.goods_receipts r where ${scoped('r')} and r.id in(${pair(c.receipt.document_ids)})) as passed`],
    ['matching', `select (select count(*)=1 from finance.bank_matches m where ${scoped('m')} and m.id in(${pair(c.matching.match_ids)})) and (select count(*)=2 and count(distinct match_id)=1 from finance.bank_match_claims cl where cl.tenant_id=${id(scope.tenant_id)} and cl.match_id in(${pair(c.matching.match_ids)}) and ((cl.kind='statement' and cl.source_id=${id(c.matching.statement_line_id)}) or(cl.kind='journal' and cl.source_id=${id(c.matching.journal_line_id)}))) as passed`],
    ['allocation', `select (select count(*)=1 from finance.open_item_allocations a where ${scoped('a')} and a.source_open_item_id in(${pair(c.allocation.source_ids)}) and a.target_open_item_id=${id(c.allocation.target_id)}) and (finance.flow_residual(${id(scope.tenant_id)},${id(c.allocation.target_id)},null)->>'amount')::numeric=${amount(c.allocation.expected_target_residual)} as passed`],
    ['posting', `select count(*)=1 and bool_and(j.status='posted') and bool_and((select count(*)>=2 and sum(l.base_debit-l.base_credit)=0 from finance.journal_lines l where l.tenant_id=j.tenant_id and l.journal_entry_id=j.id)) as passed from finance.journal_entries j where ${scoped('j')} and j.source_type='manual_journal' and j.source_id=${id(c.posting.document_id)}`],
    ['close', `select p.state=${['soft_locked','hard_locked'].includes(c.close.expected_state) ? "'" + c.close.expected_state + "'" : (() => { throw Error('Closed state required'); })()} and p.version=${Number.isSafeInteger(c.close.expected_version) && c.close.expected_version > 1 ? c.close.expected_version : (() => { throw Error('Exact post-close version required'); })()} and (select count(*)=1 from finance.period_events ev where ev.tenant_id=p.tenant_id and ev.legal_entity_id=p.legal_entity_id and ev.period_id=p.id and ev.period_version=${c.close.expected_version - 1}) as passed from finance.fiscal_periods p where p.tenant_id=${id(scope.tenant_id)} and p.legal_entity_id=${id(scope.legal_entity_id)} and p.id=${id(c.close.period_id)}`],
    ['reversal', `select ${onHand(c.reversal)} and (select count(*)=1 and bool_and((select count(*)>=2 and sum(l.base_debit-l.base_credit)=0 from finance.journal_lines l where l.tenant_id=r.tenant_id and l.journal_entry_id=r.journal_entry_id)) from procurement.goods_receipt_reversals r where ${scoped('r')} and r.receipt_id=${id(c.reversal.receipt_id)}) and (select sum(l.base_quantity) from inventory.stock_movement_lines l join procurement.goods_receipt_reversals r on r.tenant_id=l.tenant_id and r.stock_movement_id=l.stock_movement_id where ${scoped('l')} and r.receipt_id=${id(c.reversal.receipt_id)} and l.product_id=${id(c.reversal.product_id)} and l.warehouse_id=${id(c.reversal.warehouse_id)})=${amount(c.reversal.expected_movement_quantity)} as passed`]
  ];
  const allowed = new Set(['finance.open_items', 'procurement.goods_receipts', 'finance.journal_entries', 'finance.journal_lines']);
  if (!input.immutable_rows?.length) throw Error('Pre-race original-row hashes required');
  for (const [relation, value] of [...c.allocation.source_ids.map(value => ['finance.open_items', value]),
    ['finance.open_items', c.allocation.target_id], ['procurement.goods_receipts', c.reversal.receipt_id]])
    if (!input.immutable_rows.some(row => row.relation === relation && row.id === value))
      throw Error('Every original allocation item and reversed receipt needs its pre-race immutable-row hash');
  for (const row of input.immutable_rows) {
    if (!allowed.has(row.relation) || !/^[a-f0-9]{32}$/.test(row.row_md5 ?? '')) throw Error('Reviewed immutable relation/hash required');
    queries.push([`immutable:${row.relation}:${row.id}`, `select count(*)=1 and bool_and(md5(to_jsonb(r)::text)='${row.row_md5}') as passed from ${row.relation} r where r.tenant_id=${id(scope.tenant_id)} and r.id=${id(row.id)}`]);
  }
  const results = queries.map(([kind, query]) => `select jsonb_build_object('kind','${kind}','query_sha256','${digest(query)}','passed',coalesce((select passed from(${query}) checked),false)) result`).join('\nunion all\n');
  return `-- PREPARED ONLY. Read-only supplemental invariants for the approved isolated target.
-- These SQL-role checks supplement two real HTTP sessions; they do not authenticate a desktop.
begin read only;
set local statement_timeout = '60s';
with results as(${results}) select jsonb_build_object('checks',jsonb_agg(result),'passed',bool_and((result->>'passed')::boolean)) from results;
rollback;
`;
}
const main = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (main) {
  const input = process.argv.slice(2).find(x => x.endsWith('.json'));
  const index = process.argv.indexOf('--output');
  if (!input || index < 0) throw Error('Usage: node tools/wave3/prepare-target-race-invariants.mjs concrete-postflight-bindings.json --output fresh-file.sql');
  const filename = path.resolve(process.argv[index + 1]);
  const root = path.resolve('docs/verification/remaining-wave3');
  if (!filename.startsWith(root + path.sep) || path.extname(filename) !== '.sql' || fs.existsSync(filename)) throw Error('Fresh task-owned SQL artifact required');
  const sql = racePostflightSql(JSON.parse(fs.readFileSync(input, 'utf8')));
  fs.writeFileSync(filename, sql, { flag: 'wx' });
  console.log(JSON.stringify({ filename, query_sha256: digest(sql), executed: false }));
}
