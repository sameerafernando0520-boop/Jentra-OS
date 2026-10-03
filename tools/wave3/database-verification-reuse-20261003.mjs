import fs from 'node:fs';
import crypto from 'node:crypto';
const base = 'docs/verification/remaining-wave3/';
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const refresh = read(base + 'refresh-resume-20261003.json');
const manifest = read(base + 'migration-order-final-20260930-45.json');
const plans = read(base + 'representative-plans-residual-20261002.json');
const sqlSources = Object.entries(plans.source_sha256).filter(([file]) => /^supabase\/(?:migrations|tests)\//.test(file));
const compared = sqlSources.map(([file, sha256]) => ({ file, sha256, current_sha256: hash(file), matches: hash(file) === sha256 }));
const suites = ['procurement', 'inventory', 'receivables'].map(suite => {
  const path = base + `database-strict-${suite}-20261003.sql`;
  const query = fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '');
  if (!/^\s*begin;/i.test(query) || !query.includes('finish(true)') || !/rollback;\s*$/i.test(query) || /^\s*commit\s*;/im.test(query)) throw Error('Strict rollback guard: ' + suite);
  const historicalPath = base + `observability-final-${suite}-20260930.json`, historical = read(historicalPath);
  const candidates = manifest.candidates.map(row => ({ path: row.path, ordinal: row.ordinal, offset: query.indexOf(fs.readFileSync(row.path, 'utf8')), source_matches: hash(row.path) === row.sha256 }));
  if (candidates.some((r, i) => r.offset < 0 || !r.source_matches || (i && r.offset <= candidates[i - 1].offset))) throw Error('Candidate source/order drift: ' + suite);
  return { suite, path, sha256: hash(path), strict_finish: true, final_rollback: true, candidates_source_matched: candidates.length,
    historical_execution: { path: historicalPath, sha256: hash(historicalPath), started_at: historical.started_at, finished_at: historical.finished_at, assertions: historical.assertions, failures: historical.failures },
    exact_executed_query_matches: hash(path) === historical.query_sha256,
    reusable_for_source_matched_synthetic_scenarios: hash(path) === historical.query_sha256 && historical.failures.length === 0 && historical.strict_finish === true && historical.rollback === true,
    optional_rerun_command: `node tools/wave3/run-candidate.mjs ${path} ${base}database-executed-${suite}-20261003-fresh.json` };
});
const review = read(base + 'requirements-review-20261003.json');
const declarations = review.coverage_scope.files.map(row => {
  const text = fs.readFileSync(row.file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '').replace(/^\s*(?:library|import|export)\b[^;]*;/gm, '').trim();
  return { file: row.file, sha256: hash(row.file), declarations_only: text === '' || /^abstract interface class \w+(?: implements \w+)?\s*\{[^{}=]*\}$/.test(text), generated: row.file.endsWith('.g.dart') };
});
const candidateHashes = manifest.candidates.map(row => ({ ...row, current_sha256: hash(row.path), matches: hash(row.path) === row.sha256 }));
const out = { generated_at: new Date().toISOString(), head: refresh.head, refresh_path: base + 'refresh-resume-20261003.json', refresh_sha256: hash(base + 'refresh-resume-20261003.json'),
  installed: refresh.migrations.length, api_functions: refresh.api_catalogue.length, installed_baseline_matches_historical: refresh.migrations.length === 37 && refresh.migrations.at(-1).version === '20260929224939',
  candidates: candidateHashes, suites, total_distinct_suite_assertions: suites.reduce((n, r) => n + r.historical_execution.assertions, 0),
  representative_plan_reuse: { historical: base + 'representative-plans-residual-20261002.json', evidence_sha256: hash(base + 'representative-plans-residual-20261002.json'), query: plans.query, current_query_matches: hash(plans.query.path) === plans.query.sha256, assertions: plans.assertions, sql_sources: compared,
    caveat: '1005 overlapping assertions are not added to1328. Four components remain unpopulated; synthetic SQL-role claims and privileged bank plans do not prove actual authentication, load/p95 or independent-session contention.' },
  offline_preparation: { evidence: base + 'database-offline-checks-20261003.json', sha256: hash(base + 'database-offline-checks-20261003.json'), tests: 68, database_or_http_calls: 0 },
  coverage_classification: { selected: declarations.length, declaration_only: declarations.filter(r => r.declarations_only), generated: declarations.filter(r => r.generated), caveat: 'Declaration/import/export-only files contribute zero executable lines. Every other selected file needs actual current-source measurement; no executable path is discarded to meet80%.' },
  boundary: 'Exact source/query-matched historical strict rollback evidence, refreshed candidate/installed baseline and new offline self-tests only. No SQL executed by this script. Repeated unchanged synthetic execution is unnecessary without new source, failure or unresolved scenario. No installed/native/load/signoff evidence.' };
if (candidateHashes.some(r => !r.matches) || compared.some(r => !r.matches) || suites.some(r => !r.reusable_for_source_matched_synthetic_scenarios)) throw Error('Historical candidate reuse denied on source/query drift');
fs.writeFileSync(base + 'database-verification-reuse-20261003.json', JSON.stringify(out, null, 2) + '\n');
fs.writeFileSync(base + 'requirements-coverage-declarations-20261003.json', JSON.stringify(out.coverage_classification, null, 2) + '\n');
console.log(JSON.stringify({ suites: suites.map(r => ({ suite: r.suite, assertions: r.historical_execution.assertions, exact_query_match: r.exact_executed_query_matches })), total: out.total_distinct_suite_assertions, representative_sql_source_matches: compared.length, declaration_only: out.coverage_classification.declaration_only.length, generated: out.coverage_classification.generated.length }));
