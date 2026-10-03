import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// Read-only repository/catalogue review. Outputs are additive dated artifacts;
// this script never sends SQL, HTTP, credentials or mutation commands.
const base = 'docs/verification/remaining-wave3/';
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const observedPath = base + 'requirements-git-observation-20261003.json';
const observed = read(observedPath);
let head = fs.readFileSync('.git/HEAD', 'utf8').trim();
if (head.startsWith('ref: ')) head = fs.readFileSync('.git/' + head.slice(5), 'utf8').trim();
if (observed.head !== head) throw Error('Refresh separately observed read-only Git evidence');
const refreshPath = process.argv[2] ?? base + 'refresh-resume-20261003.json';
const refresh = read(refreshPath);
if (refresh.head !== head || refresh.project_id !== 'xpdoufauvrbdmxgngetv' || !refresh.observed_at) throw Error('A fresh current-HEAD development refresh is required');
const priorPath = base + 'requirement-matrix-20261002.json', prior = read(priorPath);
const spec = fs.readFileSync(prior.spec, 'utf8');
const normalize = text => text.replace(/\s+/g, ' ').trim();
const approved = new Map([...spec.matchAll(/^(?:- |### )((?:FR|AC|EC|NFR)-\d{3}):\s*([\s\S]*?)(?=^(?:- |### )(?:FR|AC|EC|NFR)-\d{3}:|^## |^### [^A]|$(?![\s\S]))/gm)].map(m => [m[1], normalize(m[2])]));
const counts = { FR: 95, AC: 26, EC: 40, NFR: 20 };
if (approved.size !== 181 || prior.requirements.length !== 181 || new Set(prior.requirements.map(r => r.id)).size !== 181) throw Error('Approved identifier drift');
for (const [kind, count] of Object.entries(counts)) if ([...approved.keys()].filter(id => id.startsWith(kind + '-')).length !== count) throw Error('Approved count drift: ' + kind);
if (hash(prior.spec) !== prior.spec_sha256) throw Error('Approved specification hash drift');
for (const row of prior.requirements) if (approved.get(row.id) !== normalize(row.approved_behavior)) throw Error('Approved wording drift: ' + row.id);

const manifestPath = base + 'migration-order-final-20260930-45.json';
const manifest = read(manifestPath), installed = new Set(refresh.migrations.map(m => m.version));
const candidates = manifest.candidates.map(c => ({ ...c, current_sha256: hash(c.path), hash_matches: hash(c.path) === c.sha256, installed_now: installed.has(c.version) }));
if (candidates.length !== 45 || candidates.some((c, i) => c.ordinal !== i + 1 || !c.hash_matches || c.installed_now)) throw Error('Candidate hash/order/install drift');
// Candidate36 precedes37 despite timestamps; installation must use this order.
if (!candidates[35].path.includes('posted_journal_evidence') || !candidates[36].path.includes('operational_evidence')) throw Error('Nonlexical dependency order drift');
const expected = { flow_residual: 'c0933ed943663701bbc7e01a1c21831f', wave3_lock_open_period: 'a316c04eef62ba1a43d49ea4d5261ca2', flow_post_journal: 'bebe95827a7e5ac3f2192d0f7acd38b4', flow_allocate: 'e6e9f68ec7d8aca03be157816fe8eef6' };
const helpers = refresh.shared_helpers.map(h => ({ ...h, matches: expected[h.name] === h.source_md5 }));
if (helpers.length !== 4 || helpers.some(h => !h.matches)) throw Error('Installed finance helper drift');
const protectedPaths = read(base + 'protected-source-opening-20260928.json').map(r => ({ ...r, current_sha256: hash(r.path), matches: hash(r.path) === r.sha256.toLowerCase() }));
if (protectedPaths.some(r => /stock.?opening|\/goldens\//i.test(r.path) && !r.matches)) throw Error('Protected acceptance/golden source drift');
const priorHashes = prior.source_sha256 ?? {};
const sourceRows = [...new Set(prior.requirements.flatMap(r => r.source_evidence))].map(file => ({ file, sha256: hash(file), historical_sha256: priorHashes[file] ?? null, historical_source_matches: priorHashes[file] === hash(file) }));
const sourceMap = new Map(sourceRows.map(r => [r.file, r]));
const currentContracts = fs.readdirSync('docs/blueprint').filter(file => /^\d+_WAVE3_/.test(file)).map(file => 'docs/blueprint/' + file);

// Keep the approved-wave baseline explicit even after implementation is committed.
const baseline = observed.baseline;
const baselineSubject = observed.baseline_subject;
if (baselineSubject !== 'Approve Wave 3 commerce and finance specification') throw Error('Wave3 baseline identity drift');
const baselineSpec = observed.baseline_spec;
if (normalize(baselineSpec) !== normalize(spec)) throw Error('Wave3 baseline specification drift');
const previousPaths = fs.readFileSync('build/remaining-wave3/changed-dart-paths-final-20261002.txt', 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/);
const changedPaths = observed.changed_paths;
const untrackedPaths = observed.untracked_paths;
const wave4Or5 = /\/features\/(?:people|projects|assets|service)\/|\/analytics\/|jentra_(?:people|payroll|assets|projects|project_finance|service)(?:_platform)?\.dart$|(?:^|\/)(?:(?:supabase_)?(?:private_hr|payroll|employee|workforce|organization|calendar|project_finance|attendance|leave|service)|sensitive_payroll|sensitive_leave|work_time|work_calendar|clock_import|project_|projects_repository|supabase_projects|supabase_assets|assets_repository|assets_gateway|asset_|fixed_asset)(?:[^/]*\.dart)$/;
const selection = [...new Set([...previousPaths, ...changedPaths, ...untrackedPaths])].map(p => p.replaceAll('\\', '/')).filter(p => p.endsWith('.dart') && p.includes('/lib/') && fs.existsSync(p)).sort();
const exclusions = selection.filter(p => wave4Or5.test(p)).map(file => ({ file, reason: 'Concurrent Wave4/5 module outside approved Wave3. Shared main/router/provider/shell files remain complete in the denominator.' }));
const selected = selection.filter(p => !wave4Or5.test(p));
const historicalCoveragePath = base + 'coverage-source-checked-20261002.json';
const historicalCoverage = read(historicalCoveragePath), coverageMap = new Map(historicalCoverage.files.map(r => [r.file, r]));
const coverageRows = selected.map(file => {
  const priorRow = coverageMap.get(file), sha256 = hash(file);
  return { file, sha256, previous_denominator: previousPaths.includes(file), historical_coverage_source_matches: priorRow?.source_sha256 === sha256 && priorRow.execution_source_matches === true, historical_measured: priorRow?.measured ?? false };
});
const coverageScopePath = base + 'requirements-coverage-paths-20261003.txt';
fs.writeFileSync(coverageScopePath, selected.join('\n') + '\n');
const sourceCapturePath = base + 'requirements-client-sources-20261003.json';
fs.writeFileSync(sourceCapturePath, JSON.stringify({ observed_at: new Date().toISOString(), head, boundary: 'Coverage-scope source fingerprint only. Capture again immediately before execution; hashes alone prove no tests.', files: selected.map(file => ({ file, sha256: hash(file) })) }, null, 2) + '\n');
const absentRpcs = ['post_goods_receipt', 'post_manual_journal', 'period_governance_command', 'bank_reconciliation_command', 'allocate_supplier_credit', 'reverse_goods_receipt', 'transition_purchase_requisition'].filter(name => !refresh.api_catalogue.some(row => row.name === name));
const requirements = prior.requirements.map(row => ({
  id: row.id, approved_behavior: row.approved_behavior, review_group: row.review_group,
  source_evidence: row.source_evidence.map(file => sourceMap.get(file)),
  source_presence: 'Current source and exact hash captured; the named review scenarios do not prove exhaustive implementation.',
  missing_implementation: ['FR-353', 'EC-323'].includes(row.id) ? 'Enabled negative-stock audited valuation and later-receipt correction policy awaits explicit owner selection; current OFF checks do not fulfill this conditional behavior.' : row.id === 'FR-395' ? 'Independent current-source review found obsolete finance/inventory/control root confirmation and journal selector presentation. See requirements-dialog-findings-20261003.md; RED/correction/GREEN remains pending.' : null,
  verification_evidence_historical: row.verification_evidence.map(file => ({ file, sha256: hash(file), historical_artifact_matches: priorHashes[file] === hash(file) })),
  missing_verification: ['FR-353', 'EC-323'].includes(row.id) ? 'Selected-policy implementation and enabled deficit/receipt tests remain absent.' : row.id === 'NFR-317' ? 'Refreshed cumulative approved-wave denominator and per-run current-source coverage required. Oct2 coverage is historical and cannot close this gate.' : 'Current-source interrupted corrections and whole checks are being rerun by their owners. Historical logs establish only their recorded source and scenarios. Installed roles, native recovery, accessibility and genuine load/session gates remain separate.',
  external_acceptance: 'Concrete isolated installation/fixtures/resources and distinct existing sessions need separate approval; native profile/store/actor scope and owner signoff are separate gates.',
}));
const installation = {
  head, refresh_path: refreshPath, refresh_sha256: hash(refreshPath), observed_at: refresh.observed_at,
  installed_count: refresh.migrations.length, latest_installed: refresh.migrations.at(-1), api_functions: refresh.api_catalogue.length,
  shared_helpers: helpers, manifest_path: manifestPath, historical_manifest_sha256: hash(manifestPath), candidates,
  exact_order_sha256: crypto.createHash('sha256').update(JSON.stringify(candidates.map(({ ordinal, path, sha256 }) => ({ ordinal, path, sha256 })))).digest('hex'),
  compatibility: { evidence: base + 'schema-compatibility-final-20260930.json', sha256: hash(base + 'schema-compatibility-final-20260930.json'), status: 'historical_capture_same_candidate_bodies', breaking: 0, potential: 8, current_live_data_preflight_required: true, owner_decisions_pending: true,
    owner_decisions: read(base + 'schema-compatibility-final-20260930.json').issues.filter(issue=>issue.severity==='potentially_breaking').map((issue,index)=>({ordinal:index+1,type:issue.type,field_path:issue.field_path,exact_constraint:issue.new_value,owner_approval:null,current_isolated_data_preflight:null,status:'pending_explicit_owner_decision_and_preflight'})),
    concrete_decision_runbook: {file:base+'database-reuse-runbook-20261003.md',sha256:hash(base+'database-reuse-runbook-20261003.md')},
  },
  phases: read(base + 'migration-plan-reviewed-20260930-45.json').phases,
  rollback: read(base + 'rollback-reviewed-20260930-45.json').phases,
  absent_required_rpcs: absentRpcs,
  approval_binding_missing: ['separate isolated project/direct host/PostgreSQL version/region/resources', 'exact45candidate body hashes and nonlexical order', 'eight documented semantic compatibility decisions and older-client handling', 'named restore point/restore owner/window', 'persistent synthetic fixture and sequence/resource budget', 'existing distinct authenticated actors and session IDs', 'fresh exact workload/race/count/postflight hashes and permitted effect scope', 'separate isolated compiled Windows profile/native stores/Storage prefix/critical checks', 'owner signoff after evidence review'],
  boundary: 'Preparation only. No target created or installed; no authentication, persistent synthetic data, credentials, native launch, production or acceptance changes.'
};
const review = {
  generated_at: new Date().toISOString(), head, generator: 'tools/wave3/requirements-database-review-20261003.mjs', generator_sha256: hash('tools/wave3/requirements-database-review-20261003.mjs'),
  spec: prior.spec, spec_sha256: hash(prior.spec), counts, requirements, git_observation: { path: observedPath, sha256: hash(observedPath), observed_at: observed.observed_at },
  database: installation, protected_files: protectedPaths,
  reviewed_contracts: currentContracts.map(file => ({ file, sha256: hash(file) })),
  source_drift_since_oct2: sourceRows.filter(r => !r.historical_source_matches),
  coverage_scope: { baseline, baseline_subject: baselineSubject, previous_files: previousPaths.length, selected_files: selected.length, added_files: selected.filter(p => !previousPaths.includes(p)), exclusions, path: coverageScopePath, sha256: hash(coverageScopePath), current_source_capture: sourceCapturePath, historical_capture: historicalCoveragePath, historical_capture_sha256: hash(historicalCoveragePath), files: coverageRows, stale_or_unmeasured: coverageRows.filter(r => !r.historical_coverage_source_matches || !r.historical_measured).map(r => r.file), gate: 'open_pending_source_checked_execution' },
  boundary: 'Exact181approved identifiers/full wording and source fingerprints; source review plus historical test evidence does not establish current GREEN, exhaustive implementation, installed/native/real-load/owner acceptance.',
  new_dialog_findings: { evidence: base + 'requirements-dialog-findings-20261003.md', status: 'prepared_regressions_await_red_correction_green', source_or_test_evidence_is_not_resolution: true }
};
fs.writeFileSync(base + 'database-installation-package-20261003.json', JSON.stringify(installation, null, 2) + '\n');
fs.writeFileSync(base + 'requirements-review-20261003.json', JSON.stringify(review, null, 2) + '\n');
const link = file => `[${path.basename(file)}](../../../${file})`;
fs.writeFileSync(base + 'requirements-review-20261003.md', [
  '# Independent approved Wave3 requirements/database refresh — 2026-10-03', '',
  `All181 approved IDs and exact normalized full wording are independently re-extracted from the approved specification:95FR,26AC,40EC,20NFR. Current HEAD is ${head}. The companion JSON records current source hashes per ID and separately marks historical execution evidence. No requirement is added.`, '',
  `Fresh read-only ${link(refreshPath)} records ${refresh.migrations.length} installed migrations,${refresh.api_catalogue.length} API functions and four unchanged shared finance helpers. All45 candidate bodies match the prior reviewed SHA-256 and remain unapplied. Ordinal36 posted-journal evidence precedes37 operational evidence; lexical filename order is unsuitable.`, '',
  `The ${link(base + 'database-installation-package-20261003.json')} pins all45 hashes, exact order hash, eight phases, documented rollback decisions, historical compatibility capture and concrete missing approval bindings. Unchanged candidate bodies permit reuse of candidate source/dependency review; historical schema validity is not fresh live-data or exhaustive older-client compatibility. Zero breaking/eight potential warnings still need owner decisions. No persistent target, fixture or native action is performed.`, '',
  'Source review covers operational frozen reports and exact CSV/XLSX exports, contextual navigation/dashboard/private attachments, linked landed-value corrections across held/transit/consumed stock, immutable cutoff count partitions, disposition/reservation maintenance, retired AR/AP controls and linked allocation corrections. These paths are present in current candidate/source and public contracts49–58. This pass confirms no additional accounting development gap beyond the owner-dependent negative-stock policy. Independent screen review additionally finds obsolete root confirmations and journal selector evidence under FR-395; the dated dialog findings identify ownership and prepared regressions. Interrupted security/recovery corrections and their execution remain assigned to their owners; source presence alone does not certify every scenario.', '',
  'FR-353/EC-323 remains a confirmed conditional-policy development gap. The last-authoritative-positive moving-average/linked receipt-variance proposal remains unapproved. Owner selection must bind interim cost, deficit coverage order, unknown/zero-basis treatment and variance classification/account. Current negative-stock-OFF checks do not satisfy enabled-policy behavior. Generic continuation or silence cannot select accounting policy.', '',
  `Coverage denominator is refreshed from the explicit approved-wave baseline ${baseline} (${baselineSubject}), current working-tree/untracked lib changes and the historical119-file denominator. ${selected.length} current lib Dart files are selected;${selected.filter(p => !previousPaths.includes(p)).length} additions are explicitly listed. Every concurrent Wave4/5 exclusion is recorded with its reason; shared main/router/provider/shell files remain whole. A clean newer HEAD cannot reset this denominator to zero. ${link(coverageScopePath)} is suitable for the existing source-checked summarizer.`, '',
  `${coverageRows.filter(r => !r.historical_coverage_source_matches || !r.historical_measured).length} selected files lack usable source-matching historical measurement. No current coverage percentage or80% gate is claimed. Per-run start-source fingerprints and completed coverage logs must be paired, rejecting changed file hashes after execution. Declaration-only classification remains the summarizer's responsibility.`, '',
  'The current installed schema lacks these required race RPCs: ' + absentRpcs.join(', ') + '. Uncommitted candidate DDL/fixtures cannot be shared by independently authenticated sessions. Small rollback plans, copied SQL-role claims and preparation self-tests do not prove installed authentication, contention, target population or p95.', '',
  'Current-source GREEN regressions/analyzers, complete rendered accessibility/golden investigation, matched isolated Windows compilation, approved isolated installation/compatibility/data preflight, genuinely independent authenticated sessions, populated target-scale plans/p95, separately authorized native profile/store/cold-launch acceptance and owner signoff remain open. Wave3 is not fully complete.', ''
].join('\n'));
console.log(JSON.stringify({ head, approved_ids: approved.size, installed: refresh.migrations.length, api_functions: refresh.api_catalogue.length, candidates: candidates.length, current_source_drift: review.source_drift_since_oct2.length, coverage_files: selected.length, added_coverage_files: review.coverage_scope.added_files.length, stale_or_unmeasured: review.coverage_scope.stale_or_unmeasured.length }));
