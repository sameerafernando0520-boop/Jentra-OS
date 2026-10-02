import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { amountText, assertTarget, digest, receiptCall, verifySources } from './prepare-target-verification.mjs';

// No execution takes place while preparing this tool. All connection data remain in
// environment variables; SQL evidence contains synthetic IDs, never passwords/JWTs.
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const uuid = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
export const ledgerSql = `begin read only;
select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]')
from supabase_migrations.schema_migrations;
rollback;`;
const literal = value => "'" + String(value).replaceAll("'", "''") + "'";
export function preflightSql(plan) {
  assertTarget(plan);
  const lanes = JSON.stringify(plan.receipt_lanes);
  return `begin read only;
with lane as(select * from jsonb_to_recordset(${literal(lanes)}::jsonb) as l(
 tenant_id uuid,legal_entity_id uuid,branch_id uuid,warehouse_id uuid,order_id uuid,
 order_line_id uuid,product_id uuid,expected_version bigint,receipt_count integer,
 quantity_per_receipt numeric,reviewed_remaining_quantity numeric,reviewed_value_per_receipt numeric)),
checks as(select l.order_id,
 coalesce(t.slug like 'wave3-scale-%',false) cohort,
 coalesce(o.status='approved' and o.version=l.expected_version and o.tenant_id=l.tenant_id
 and o.legal_entity_id=l.legal_entity_id and o.branch_id=l.branch_id and o.warehouse_id=l.warehouse_id
 and o.currency_code='LKR' and o.exchange_rate=1 and o.document_date<=${literal(plan.posting_date)}::date,false) approved_order,
 coalesce(ol.order_id=l.order_id and ol.tenant_id=l.tenant_id and ol.legal_entity_id=l.legal_entity_id
 and ol.product_id=l.product_id and ol.quantity-ol.cancelled_quantity-ol.received_quantity>=l.reviewed_remaining_quantity
 and ol.quantity-ol.cancelled_quantity-ol.received_quantity>=l.receipt_count*l.quantity_per_receipt
 and (ol.detail->>'net_amount')::numeric*l.quantity_per_receipt/ol.quantity=l.reviewed_value_per_receipt
 and round(l.reviewed_value_per_receipt,2)=l.reviewed_value_per_receipt,false) capacity_and_exact_value,
 coalesce(p.tenant_id=l.tenant_id and p.legal_entity_id=l.legal_entity_id and p.kind='stocked'
 and p.tracking_mode='none' and p.status='active' and p.can_purchase and p.inventory_account_id=inv.id
 and inv.account_type='asset' and inv.status='active' and inv.is_posting
 and (inv.currency_code is null or inv.currency_code='LKR'),false) stocked_product,
 coalesce(w.tenant_id=l.tenant_id and w.legal_entity_id=l.legal_entity_id and w.branch_id=l.branch_id
 and w.status='active',false) active_warehouse,
 coalesce(rc.tenant_id=l.tenant_id and grni.account_type='liability' and grni.status='active' and grni.is_posting
 and (grni.currency_code is null or grni.currency_code='LKR'),false) receipt_controls,
 coalesce(exists(select 1 from finance.fiscal_periods fp where fp.tenant_id=l.tenant_id
 and fp.legal_entity_id=l.legal_entity_id and fp.status='active' and fp.state='open'
 and ${literal(plan.posting_date)}::date between fp.start_date and fp.end_date),false) open_period,
 coalesce(exists(select 1 from core.memberships m where m.tenant_id=l.tenant_id
 and m.user_id=${literal(plan.actor_id)}::uuid and m.status='active'),false) existing_membership,
 not exists(select 1 from inventory.stock_movement_lines sm where sm.tenant_id=l.tenant_id
 and sm.warehouse_id=l.warehouse_id and sm.product_id=l.product_id
 and sm.posting_date>${literal(plan.posting_date)}::date) no_later_movement
 from lane l left join core.tenants t on t.id=l.tenant_id
 left join procurement.purchase_orders o on o.id=l.order_id
 left join procurement.purchase_order_lines ol on ol.id=l.order_line_id
 left join inventory.products p on p.id=l.product_id
 left join core.warehouses w on w.id=l.warehouse_id
 left join finance.accounts inv on inv.id=p.inventory_account_id
 left join procurement.receipt_controls rc on rc.legal_entity_id=l.legal_entity_id
 left join finance.accounts grni on grni.id=rc.grni_account_id)
select jsonb_build_object('lane_count',(select count(*) from checks),
 'valid_lanes',(select count(*) from checks where cohort and approved_order and capacity_and_exact_value
 and stocked_product and active_warehouse and receipt_controls and open_period and existing_membership and no_later_movement),
 'invalid_lanes',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from checks c where not(cohort and approved_order
 and capacity_and_exact_value and stocked_product and active_warehouse and receipt_controls and open_period and existing_membership and no_later_movement)),
 'journal_guards_enabled',(select count(*)=3 from pg_trigger where tgrelid in('finance.journal_entries'::regclass,'finance.journal_lines'::regclass)
 and tgname in('journal_balanced','journal_lines_balanced','protect_posted_lines') and tgenabled='O'),
 'rpc_source_md5',(select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='api' and p.proname='post_goods_receipt' and p.pronargs=8));
rollback;`;
}
export function approvedContext(plan, env = process.env) {
  assertTarget(plan); verifySources(plan);
  if (plan.approval_status !== 'explicit_user_approval' || !plan.approval_reference?.trim() ||
    plan.approved_source_bundle_sha256 !== plan.source_bundle_sha256 ||
    !/^[a-f0-9]{64}$/.test(plan.approved_ledger_sha256 ?? '') ||
    plan.approved_new_receipts !== plan.planned_receipts)
    throw Error('Specific isolated installation/fixture approval, source/ledger hashes and exact receipt budget required');
  if (env.WAVE3_ISOLATED_PGHOST !== `db.${plan.project_id}.supabase.co` ||
    env.WAVE3_ISOLATED_PGDATABASE !== 'postgres' || env.WAVE3_ISOLATED_PGUSER !== 'postgres' ||
    !env.WAVE3_ISOLATED_PGPASSWORD || !env.WAVE3_ISOLATED_PUBLIC_KEY || !env.WAVE3_FIXTURE_SESSION_TOKEN)
    throw Error('Approved direct isolated PostgreSQL host and existing authenticated session required');
  let claims;
  try { claims = JSON.parse(Buffer.from(env.WAVE3_FIXTURE_SESSION_TOKEN.split('.')[1], 'base64url').toString('utf8')); }
  catch { throw Error('Invalid existing session claims'); }
  if (claims.sub !== plan.actor_id || claims.role !== 'authenticated' || claims.iss !== plan.url + '/auth/v1' ||
    !uuid.test(claims.session_id ?? '') || !Number.isFinite(claims.exp) || claims.exp * 1000 <= Date.now())
    throw Error('Existing session actor/issuer/expiry/session ID differ from isolated approval');
  const root = path.join(repo, 'docs/verification/remaining-wave3/approved-runs');
  const output = path.resolve(repo, plan.evidence_path ?? '');
  if (!output.startsWith(root + path.sep) || path.extname(output) !== '.ndjson' || fs.existsSync(output))
    throw Error('Fresh task-owned approved-runs NDJSON evidence path required');
  return { claims, root, output, token: env.WAVE3_FIXTURE_SESSION_TOKEN, key: env.WAVE3_ISOLATED_PUBLIC_KEY,
    pgEnvironment: { ...env, PGHOST: env.WAVE3_ISOLATED_PGHOST, PGDATABASE: 'postgres', PGUSER: 'postgres',
      PGPORT: '5432', PGPASSWORD: env.WAVE3_ISOLATED_PGPASSWORD, PGSSLMODE: 'verify-full', PGCONNECT_TIMEOUT: '15' } };
}
export function readDatabase(sql, context, psql = 'psql') {
  // Child stderr can include details; emit a fixed redacted error on failure.
  try {
    const out = execFileSync(psql, ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'],
      { input: sql, encoding: 'utf8', env: context.pgEnvironment, timeout: 60000,
        maxBuffer: 32 * 1024 * 1024, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    return JSON.parse(out.trim());
  } catch { throw Error('Isolated read-only database preflight failed; no fixture command started'); }
}
async function execute(plan) {
  const context = approvedContext(plan);
  const ledger = readDatabase(ledgerSql, context, process.env.WAVE3_PSQL_PATH ?? 'psql');
  if (digest(ledger) !== plan.approved_ledger_sha256) throw Error('Installed isolated ledger differs from the specifically approved ledger');
  const preflight = readDatabase(preflightSql(plan), context, process.env.WAVE3_PSQL_PATH ?? 'psql');
  const schema = JSON.parse(fs.readFileSync(path.join(repo, 'docs/verification/remaining-wave3/schema-after-45-20260930.json'), 'utf8'));
  const expectedSource = schema.functions['api.post_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamp with time zone,jsonb,bigint)'].source_md5;
  if (preflight.valid_lanes !== plan.receipt_lanes.length || !preflight.journal_guards_enabled || preflight.rpc_source_md5 !== expectedSource)
    throw Error('Live lane capacity/scope/period/provenance/source or journal guards differ from the reviewed recipe');
  fs.mkdirSync(context.root, { recursive: true });
  const descriptor = fs.openSync(context.output, 'wx');
  const record = item => fs.writeSync(descriptor, JSON.stringify(item) + '\n');
  let count = 0, finished = false;
  record({ kind: 'start', executed: true, project_id: plan.project_id, plan_sha256: digest(plan),
    ledger_sha256: digest(ledger), source_bundle_sha256: plan.source_bundle_sha256,
    approval_reference: plan.approval_reference, authentication_session_id: context.claims.session_id,
    preflight_query_sha256: digest(preflightSql(plan)), preflight, planned_receipts: plan.planned_receipts,
    boundary: 'Fixture generation only; HTTP timings are setup timings, never target-load p95 or lock-contention proof.' });
  try {
    for (const lane of plan.receipt_lanes) for (let ordinal = 0; ordinal < lane.receipt_count; ordinal++) {
      // Verify source identity between lanes without restaging/replaying any unrelated document.
      if (ordinal === 0) verifySources(plan);
      const call = receiptCall(plan, lane, ordinal), sample = { kind: 'receipt', ordinal: ++count,
        command_id: call.params.p_command_id, document_id: call.params.p_payload.id,
        envelope_sha256: digest(call.params), started_at: new Date().toISOString(), success: false };
      const started = performance.now();
      try {
        const response = await fetch(plan.url + '/rest/v1/rpc/post_goods_receipt', { method: 'POST',
          headers: { apikey: context.key, Authorization: 'Bearer ' + context.token,
            'Content-Profile': 'api', 'Content-Type': 'application/json' },
          body: JSON.stringify(call.params), signal: AbortSignal.timeout(30000) });
        const raw = await response.text(); sample.response_sha256 = digest(raw); sample.http_status = response.status;
        const body = JSON.parse(raw), entity = body.entity;
        sample.success = response.ok && entity?.id === call.params.p_payload.id && entity.status === 'posted' &&
          entity.net_amount === amountText(lane.reviewed_value_per_receipt) && uuid.test(entity.stock_movement_id ?? '') && uuid.test(entity.journal_entry_id ?? '');
        sample.transport_state = 'response_received';
        if (sample.success) { sample.stock_movement_id = entity.stock_movement_id; sample.journal_entry_id = entity.journal_entry_id; }
      } catch { sample.transport_state = 'transport_uncertain'; }
      finally { sample.finished_at = new Date().toISOString(); sample.setup_elapsed_ms = performance.now() - started; record(sample); fs.fsyncSync(descriptor); }
      if (!sample.success) throw Error('Fixture receipt rejected or uncertain; preserve original envelope and isolated records for review. No automatic new command or rollback/delete is attempted.');
    }
    const countsSql = fs.readFileSync(path.join(repo, 'tools/wave3/verify-target-fixtures.sql'), 'utf8');
    const counts = readDatabase('begin read only;\n' + countsSql + '\nrollback;', context, process.env.WAVE3_PSQL_PATH ?? 'psql');
    record({ kind: 'measured_fixture_counts', query_sha256: digest(countsSql), result: counts });
    finished = true;
  } finally {
    record({ kind: 'finish', generation_finished: finished, attempted_receipts: count, finished_at: new Date().toISOString(),
      boundary: 'Generation results do not establish the six p95 classes, nine independent-session races, representative high-volume plans or native acceptance.' });
    fs.closeSync(descriptor);
  }
  console.log(JSON.stringify({ evidence_path: context.output, generation_finished: finished, attempted_receipts: count }));
}
const main = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (main) {
  const input = process.argv.slice(2).find(x => x.endsWith('.json'));
  if (!input) throw Error('Usage: node tools/wave3/run-target-fixture-generator.mjs prepared-fixture-plan.json [--execute]');
  const plan = JSON.parse(fs.readFileSync(input, 'utf8')); assertTarget(plan); verifySources(plan);
  if (process.argv.includes('--execute')) await execute(plan);
  else console.log(JSON.stringify({ executed: false, project_id: plan.project_id,
    planned_receipts: plan.planned_receipts, source_bundle_sha256: plan.source_bundle_sha256,
    preflight_query_sha256: digest(preflightSql(plan)), boundary: 'Offline recipe validation; no fixture installed.' }, null, 2));
}
