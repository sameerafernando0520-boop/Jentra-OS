import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { digest, verifySources } from './prepare-target-verification.mjs';
import { approvedContext, ledgerSql, readDatabase } from './run-target-fixture-generator.mjs';
import { racePostflightSql } from './prepare-target-race-invariants.mjs';
import { assertRaceClass, assertRacePostflightBindings } from './target_review_guards.mjs';

// Future execution wrapper: refresh the isolated database rather than accepting
// self-reported actual-ledger/count fields. Existing harnesses remain untouched.
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const evidenceRoot = path.join(repo, 'docs/verification/remaining-wave3');
const contained = filename => {
  const result = path.resolve(repo, filename ?? '');
  if (!result.startsWith(evidenceRoot + path.sep) || path.extname(result) !== '.json') throw Error('Task-owned JSON binding/config artifact required');
  return result;
};
export function liveRpcSourceSql(config) {
  const calls = config.workloads?.flatMap(w => w.calls) ?? config.races?.flatMap(r => [...r.commands, ...r.invariants]);
  if (!calls?.length) throw Error('Concrete calls required');
  const schema = JSON.parse(fs.readFileSync(path.join(repo, 'docs/verification/remaining-wave3/schema-after-45-20260930.json'), 'utf8'));
  const expected = {};
  for (const name of new Set(calls.flatMap(c => c.aging?[c.rpc,'control_reconciliation_report_page']:[c.rpc]))) {
    if (!/^[a-z][a-z0-9_]*$/.test(name ?? '')) throw Error('Reviewed RPC identifier required');
    const signatures = Object.keys(schema.functions).filter(signature => signature.startsWith('api.' + name + '('));
    if (signatures.length !== 1) throw Error('Exactly one reviewed RPC signature required: ' + name);
    expected[signatures[0]] = schema.functions[signatures[0]].source_md5;
  }
  const signatures = Object.keys(expected).map(value => "'" + value.replaceAll("'", "''") + "'").join(',');
  return { expected, sql: `begin read only; select coalesce(jsonb_object_agg(p.oid::regprocedure::text,md5(pg_get_functiondef(p.oid))),'{}') from pg_proc p where p.oid=any(array[${signatures}]::regprocedure[]); rollback;` };
}
export function countGate(counts) {
  const minimum = { tenants: 500, legal_entities: 5000, warehouses: 125000,
    minimum_legal_entities_per_tenant: 10, minimum_warehouses_per_entity: 25, large_tenants: 1,
    products_per_large_tenant: 100000, stock_movements: 10000000, journal_lines: 20000000 };
  for (const [key, value] of Object.entries(minimum)) if (!Number.isSafeInteger(counts?.[key]) || counts[key] < value)
    throw Error('Live isolated fixture count below NFR-309: ' + key);
}
export function verifyCountEvidence(kind, counts, config, binding) {
  if (kind === 'load') {
    countGate(counts);
    if (digest(config.fixture_counts) !== digest(counts)) throw Error('Prepared load counts differ from fresh live counts');
  } else if (kind === 'races') {
    if (!/^[a-f0-9]{64}$/.test(binding.approved_fixture_counts_sha256 ?? '') ||
      digest(counts) !== binding.approved_fixture_counts_sha256)
      throw Error('Race fixture counts differ from the specifically approved fresh cohort');
  } else {
    throw Error('Unknown verification kind');
  }
}
const main = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (main) {
  const filename = process.argv.slice(2).find(x => x.endsWith('.json'));
  if (!filename) throw Error('Usage: node tools/wave3/run-reviewed-target-verification.mjs reviewed-run-binding.json [--execute]');
  const binding = JSON.parse(fs.readFileSync(contained(filename), 'utf8'));
  if (!['load', 'races'].includes(binding.kind)) throw Error('Choose the reviewed load or independent-race run');
  const fixture = JSON.parse(fs.readFileSync(contained(binding.fixture_plan_path), 'utf8'));
  verifySources(fixture);
  const config = JSON.parse(fs.readFileSync(contained(binding.prepared_config_path), 'utf8'));
  if (config.project_id !== fixture.project_id || config.url !== fixture.url) throw Error('Fixture and verification target differ');
  if (binding.kind === 'races') for (const race of config.races ?? []) assertRaceClass(race.kind, race.commands);
  const rpcSources = liveRpcSourceSql(config);
  if (!process.argv.includes('--execute')) {
    console.log(JSON.stringify({ executed: false, kind: binding.kind, project_id: config.project_id,
      source_bundle_sha256: fixture.source_bundle_sha256, rpc_source_query_sha256: digest(rpcSources.sql),
      boundary: 'Offline wrapper validation only. Before execution, explicit approval, direct isolated host, live ledger/RPC-source/fixture-count checks and existing authenticated sessions are required.' }, null, 2));
  } else {
    if (binding.approval_status !== 'explicit_user_approval' || !binding.approval_reference?.trim() ||
      binding.approved_source_bundle_sha256 !== fixture.source_bundle_sha256 ||
      !/^[a-f0-9]{64}$/.test(binding.approved_config_sha256 ?? '') || digest(config) !== binding.approved_config_sha256)
      throw Error('Explicit approval for this exact source bundle and concrete verification config required');
    const context = approvedContext({ ...fixture, approval_status: binding.approval_status,
      approval_reference: binding.approval_reference, approved_source_bundle_sha256: binding.approved_source_bundle_sha256,
      approved_ledger_sha256: binding.approved_ledger_sha256, approved_new_receipts: fixture.planned_receipts,
      evidence_path: binding.preflight_evidence_path });
    const ledger = readDatabase(ledgerSql, context, process.env.WAVE3_PSQL_PATH ?? 'psql');
    if (digest(ledger) !== binding.approved_ledger_sha256) throw Error('Fresh installed isolated ledger differs from approval');
    const liveSources = readDatabase(rpcSources.sql, context, process.env.WAVE3_PSQL_PATH ?? 'psql');
    if (digest(liveSources) !== digest(rpcSources.expected)) throw Error('Live RPC source differs from the reviewed candidate schema');
    const countsQuery = fs.readFileSync(path.join(repo, 'tools/wave3/verify-target-fixtures.sql'), 'utf8');
    const counts = readDatabase('begin read only;\n' + countsQuery + '\nrollback;', context, process.env.WAVE3_PSQL_PATH ?? 'psql');
    verifyCountEvidence(binding.kind, counts, config, binding);
    let postflightSql = null;
    if (binding.kind === 'races') {
      const invariants = JSON.parse(fs.readFileSync(contained(binding.postflight_bindings_path), 'utf8'));
      if (digest(invariants.scope) !== digest(config.scope)) throw Error('Postflight scope differs from the two-session race scope');
      assertRacePostflightBindings(config, invariants);
      postflightSql = racePostflightSql(invariants);
      if (digest(postflightSql) !== binding.approved_postflight_sql_sha256) throw Error('Exact supplemental invariants must be approved with the race config');
    }
    const approvedConfig = { ...config, approval_status: binding.approval_status,
      approval_reference: binding.approval_reference, approved_ledger_sha256: digest(ledger), actual_ledger_sha256: digest(ledger) };
    fs.mkdirSync(context.root, { recursive: true });
    const derived = context.output.replace(/\.ndjson$/, '.runtime-config.json');
    if (fs.existsSync(derived)) throw Error('Fresh derived runtime config required');
    fs.writeFileSync(derived, JSON.stringify(approvedConfig, null, 2) + '\n', { flag: 'wx' });
    const descriptor = fs.openSync(context.output, 'wx');
    const record = item => fs.writeSync(descriptor, JSON.stringify(item) + '\n');
    record({ kind: 'live_preflight', executed: true, project_id: config.project_id, source_bundle_sha256: fixture.source_bundle_sha256,
      installed_ledger_sha256: digest(ledger), rpc_source_query_sha256: digest(rpcSources.sql), actual_rpc_source_md5: liveSources,
      fixture_counts_query_sha256: digest(countsQuery), fixture_counts: counts,
      approved_config_sha256: binding.approved_config_sha256, approval_reference: binding.approval_reference });
    let exitCode = null, invariantResult = null;
    try {
      const tool = binding.kind === 'load' ? 'run-target-load.mjs' : 'run-independent-sessions.mjs';
      exitCode = await new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(repo, 'tools/wave3', tool), derived, '--execute'],
          { cwd: repo, env: process.env, windowsHide: true, stdio: ['ignore', 'inherit', 'inherit'] });
        child.once('error', () => reject(Error('Reviewed verification child could not start')));
        child.once('exit', code => resolve(code));
      });
      if (postflightSql) {
        invariantResult = readDatabase(postflightSql, context, process.env.WAVE3_PSQL_PATH ?? 'psql');
        record({ kind: 'race_ledger_postflight', query_sha256: digest(postflightSql), result: invariantResult,
          boundary: 'Read-only SQL-role invariant checks supplement the separately recorded two signed HTTP sessions.' });
      }
    } finally {
      record({ kind: 'finish', passed: exitCode === 0 && (!postflightSql || invariantResult?.passed === true),
        child_exit_code: exitCode, finished_at: new Date().toISOString(),
        boundary: 'Installed isolated verification only; no native acceptance or owner signoff claim.' });
      fs.closeSync(descriptor);
    }
    if (exitCode !== 0 || (postflightSql && invariantResult?.passed !== true)) throw Error('Approved isolated verification gate failed; preserve records and original command identities');
  }
}
