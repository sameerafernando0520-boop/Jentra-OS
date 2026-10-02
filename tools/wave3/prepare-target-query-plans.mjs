import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { digest } from './prepare-target-verification.mjs';

const uuid = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const id = value => { if (!uuid.test(value ?? '')) throw Error('Concrete scoped UUID required'); return "'" + value + "'::uuid"; };
const date = value => { if (!/^\d{4}-\d{2}-\d{2}$/.test(value ?? '') || !Number.isFinite(Date.parse(value + 'T00:00:00Z')) || new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) !== value) throw Error('Valid reviewed ISO date required'); return "'" + value + "'::date"; };
export function targetQueries(input) {
  const t = id(input.scope?.tenant_id), e = id(input.scope?.legal_entity_id), b = id(input.scope?.branch_id);
  const product = id(input.product_id), warehouse = id(input.warehouse_id), account = id(input.account_id);
  const party = id(input.party_id), bank = id(input.bank_id), item = id(input.open_item_id);
  const start = date(input.start_date), end = date(input.end_date);
  if (input.start_date > input.end_date) throw Error('Ordered period dates required');
  const queries = [
    ['open_item_aging', `select id,posting_date,due_date,original_amount from finance.open_items where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} and party_id=${party} and currency_code='LKR' and posting_date<=${end} order by posting_date,due_date,id limit 200`],
    ['allocation_history', `select id,source_amount,transaction_amount from finance.open_item_allocations where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} and (source_open_item_id=${item} or target_open_item_id=${item}) and posting_date<=${end} order by posting_date,id limit 500`],
    ['stock_asof', `select id,base_quantity,base_value from inventory.stock_movement_lines where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} and warehouse_id=${warehouse} and product_id=${product} and posting_date<=${end} order by posting_date,id limit 200`],
    ['journal_report_filter', `select id,base_debit,base_credit from finance.journal_lines where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} and account_id=${account} and posting_date between ${start} and ${end} order by posting_date,id limit 200`],
    ['requisition_queue', `select id,status from procurement.requisitions where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} and status='pending_approval' order by id limit 50`],
    ['reservation_queue', `select id,sales_order_id,base_quantity from inventory.stock_reservations where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} and status='active' and expires_at<=${end} order by sales_order_id,id limit 50`],
    ['availability', `select id,available_quantity from api.stock_availability where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} order by id limit 200`],
    // Select residual fields explicitly, rather than allowing projection pruning to omit expensive basis.
    ['receivable_balances', `select * from api.receivable_balances where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} order by id limit 200`],
    ['payable_balances', `select * from api.payable_balances where tenant_id=${t} and legal_entity_id=${e} and branch_id=${b} order by id limit 200`],
    ['bank_matching_private_basis', `select id,reference,amount from finance.bank_statement_lines where tenant_id=${t} and bank_id=${bank} and posting_date<=${end} order by posting_date,id limit 200`],
    ['bank_claim_private_basis', `select source_id,match_id from finance.bank_match_claims where tenant_id=${t} and kind='journal' order by source_id limit 200`]
  ];
  return queries.map(([name, sql]) => ({ name, sql, query_sha256: digest(sql),
    database_role: name.includes('private_basis') ? 'postgres' : 'authenticated',
    boundary: name.includes('private_basis') ? 'Private bank query basis under approved privileged fixture role; public RPC/RLS authentication remains a separate check.' :
      'SQL role plus copied synthetic claims; query plan only, not signed-session authentication or nested PL/pgSQL report proof.' }));
}
export function reviewPlan(raw) {
  if (!Array.isArray(raw) || raw.length !== 1 || !raw[0].Plan) throw Error('Unmodified EXPLAIN JSON array required');
  const unbounded = [], nodes = [];
  const highVolume = new Set(['stock_movements', 'stock_movement_lines', 'journal_entries', 'journal_lines',
    'open_items', 'open_item_allocations', 'stock_reservations', 'bank_statement_lines', 'bank_match_claims']);
  const walk = node => {
    nodes.push({ node_type: node['Node Type'], relation: node['Relation Name'] ?? null,
      index: node['Index Name'] ?? null, actual_rows: node['Actual Rows'] ?? null,
      actual_loops: node['Actual Loops'] ?? null, removed_by_filter: node['Rows Removed by Filter'] ?? 0,
      shared_hit_blocks: node['Shared Hit Blocks'] ?? null, shared_read_blocks: node['Shared Read Blocks'] ?? null,
      filter: node.Filter ?? null, index_condition: node['Index Cond'] ?? null });
    if (['Seq Scan', 'Parallel Seq Scan'].includes(node['Node Type']) && highVolume.has(node['Relation Name']))
      unbounded.push({ relation: node['Relation Name'], node_type: node['Node Type'] });
    for (const child of node.Plans ?? []) walk(child);
  };
  walk(raw[0].Plan);
  return { execution_ms: raw[0]['Execution Time'] ?? null, planning_ms: raw[0]['Planning Time'] ?? null,
    no_high_volume_sequential_scan: unbounded.length === 0, flagged_nodes: unbounded, nodes,
    boundary: 'Conservative plan review. Missing/empty fixtures, opaque function internals and target counts need linked evidence; one EXPLAIN timing is not p95.' };
}
const main = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (main) {
  const input = process.argv.slice(2).find(x => x.endsWith('.json'));
  const index = process.argv.indexOf('--output');
  if (!input || index < 0) throw Error('Usage: node tools/wave3/prepare-target-query-plans.mjs concrete-query-bindings.json --output fresh-directory');
  const output = path.resolve(process.argv[index + 1]), root = path.resolve('docs/verification/remaining-wave3');
  if (!output.startsWith(root + path.sep) || fs.existsSync(output)) throw Error('Fresh task-owned plan directory required');
  const binding = JSON.parse(fs.readFileSync(input, 'utf8')), queries = targetQueries(binding);
  if (!uuid.test(binding.actor_id ?? '')) throw Error('Existing synthetic actor required');
  fs.mkdirSync(output);
  for (const [i, query] of queries.entries()) {
    const claims = JSON.stringify({ sub: binding.actor_id, role: 'authenticated', aal: 'aal2' }).replaceAll("'", "''");
    const setup = query.database_role === 'authenticated' ? `set local role authenticated;\nselect set_config('request.jwt.claims','${claims}',true);\n` : '';
    const text = `-- ${query.name}; source query SHA256 ${query.query_sha256}\n-- ${query.boundary}\nbegin read only;\nset local statement_timeout='60s';\n${setup}explain(analyze,buffers,settings,format json) ${query.sql};\nrollback;\n`;
    fs.writeFileSync(path.join(output, `${String(i + 1).padStart(2, '0')}-${query.name}.sql`), text);
  }
  fs.writeFileSync(path.join(output, 'queries.json'), JSON.stringify({ executed: false, scope: binding.scope, queries,
    boundary: 'Prepared source components only. No target plans, counts or load timing measured.' }, null, 2) + '\n');
  console.log(JSON.stringify({ output, queries: queries.length, executed: false }));
}
