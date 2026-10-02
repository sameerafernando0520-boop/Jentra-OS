import fs from 'node:fs';
import path from 'node:path';

const uuid = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const ids = values => Array.isArray(values) && values.length > 0 && values.every(value => uuid.test(value ?? ''));
const positive = value => typeof value === 'string' && /^(0|[1-9]\d{0,13})(\.\d{1,6})?$/.test(value) && /[1-9]/.test(value);
const requireValue = (condition, kind) => { if (!condition) throw Error('Concrete RPC and payload class required for race: ' + kind); };

// Reserve before HTTP dispatch. `wx` is atomic: a competing or existing file is
// preserved even if its contents are empty, and the losing runner sends no call.
export function openNewEvidence(filename, root, extension = '.json') {
  const output = path.resolve(filename), boundary = path.resolve(root);
  if (!output.startsWith(boundary + path.sep) || path.extname(output) !== extension)
    throw Error('Fresh task-owned evidence path required');
  fs.mkdirSync(path.dirname(output), {recursive: true});
  try { return fs.openSync(output, 'wx'); }
  catch { throw Error('Evidence path already exists or cannot be reserved; no command started'); }
}

export function assertRaceClass(kind, commands) {
  requireValue(commands?.length === 2, kind);
  const calls = commands.map(c => ({rpc: c.rpc, payload: c.params?.p_payload ?? c.payload}));
  requireValue(calls.every(c => c.payload && typeof c.payload === 'object' && !Array.isArray(c.payload)), kind);
  const same = field => calls[0].payload[field] === calls[1].payload[field];
  const valid = (rpcs, predicate) => calls.every(c => rpcs.includes(c.rpc) && predicate(c.payload));
  const document = p => uuid.test(p.document_id ?? '');
  switch (kind) {
    case 'number_reservation':
      requireValue(valid(['transition_purchase_requisition'], p => document(p) && p.action === 'submit' && p.decision == null) && !same('document_id'), kind); break;
    case 'order_allocation':
      requireValue(valid(['reserve_sales_order_stock'], p => uuid.test(p.sales_order_id ?? '') && Array.isArray(p.lines) && p.lines.length > 0 && p.lines.length <= 500 && p.lines.every(l => uuid.test(l.sales_order_line_id ?? '') && positive(l.requested_base_quantity))) && !same('sales_order_id'), kind); break;
    case 'stock_issue':
      requireValue(valid(['post_delivery'], document) && !same('document_id'), kind); break;
    case 'receipt':
      requireValue(valid(['post_goods_receipt'], p => ['id','order_id','warehouse_id'].every(k => uuid.test(p[k] ?? '')) && Array.isArray(p.lines) && p.lines.length > 0 && p.lines.length <= 500 && p.lines.every(l => uuid.test(l.order_line_id ?? '') && positive(l.accepted_quantity))) && !same('id') && same('order_id'), kind); break;
    case 'matching': {
      requireValue(valid(['bank_reconciliation_command'], p => p.action === 'match' && uuid.test(p.id ?? '') && uuid.test(p.bank_id ?? '') && ids(p.statement_line_ids) && ids(p.journal_line_ids)) && !same('id') && same('bank_id'), kind);
      const [a,b] = calls.map(c => c.payload);
      requireValue(a.statement_line_ids.some(id => b.statement_line_ids.includes(id)) && a.journal_line_ids.some(id => b.journal_line_ids.includes(id)), kind); break;
    }
    case 'allocation':
      requireValue(valid(['allocate_customer_receipt','allocate_supplier_credit'], p => uuid.test(p.source_open_item_id ?? '') && Array.isArray(p.allocations) && p.allocations.length === 1 && uuid.test(p.allocations[0].target_open_item_id ?? '')) && calls[0].rpc === calls[1].rpc && !same('source_open_item_id') && calls[0].payload.allocations[0].target_open_item_id === calls[1].payload.allocations[0].target_open_item_id, kind); break;
    case 'posting':
      requireValue(valid(['post_manual_journal'], document) && same('document_id'), kind); break;
    case 'close':
      requireValue(valid(['period_governance_command'], p => p.action === 'hard_lock' && uuid.test(p.id ?? '') && uuid.test(p.period_id ?? '')) && same('period_id'), kind); break;
    case 'reversal':
      requireValue(valid(['reverse_goods_receipt'], document) && same('document_id'), kind); break;
    default: throw Error('Unknown approved race class: ' + kind);
  }
}

export function assertRacePostflightBindings(config, input) {
  const cases = input.cases;
  if (!cases || !config.races) throw Error('Concrete race/postflight bindings required');
  const pairMatches = (actual, expected) => Array.isArray(expected) && expected.length === 2 && [...actual].sort().join(',') === [...expected].sort().join(',');
  for (const race of config.races) {
    assertRaceClass(race.kind, race.commands);
    const [a,b] = race.commands.map(c => c.params.p_payload);
    const c = cases[race.kind]; let matches = false;
    if (!c) throw Error('Postflight source case missing: ' + race.kind);
    switch (race.kind) {
      case 'number_reservation': case 'stock_issue': matches = pairMatches([a.document_id,b.document_id], c.document_ids); break;
      case 'order_allocation': matches = pairMatches([a.sales_order_id,b.sales_order_id], c.sales_order_ids); break;
      case 'receipt': matches = pairMatches([a.id,b.id], c.document_ids) && a.warehouse_id === c.warehouse_id && b.warehouse_id === c.warehouse_id; break;
      case 'matching': matches = pairMatches([a.id,b.id], c.match_ids) && [a,b].every(p => p.statement_line_ids.includes(c.statement_line_id) && p.journal_line_ids.includes(c.journal_line_id)); break;
      case 'allocation': matches = pairMatches([a.source_open_item_id,b.source_open_item_id], c.source_ids) && [a,b].every(p => p.allocations[0].target_open_item_id === c.target_id); break;
      case 'posting': matches = a.document_id === c.document_id; break;
      case 'close': matches = a.period_id === c.period_id; break;
      case 'reversal': matches = a.document_id === c.receipt_id; break;
    }
    if (!matches) throw Error('Postflight source IDs differ from the concrete race commands: ' + race.kind);
  }
}
