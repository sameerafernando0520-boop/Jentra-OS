import fs from 'node:fs';
import crypto from 'node:crypto';

// Final derivative only: it requires explicit completed-check evidence and never
// guesses a test result, edits the approved specification, or resets the scope.
const base = 'docs/verification/remaining-wave3/';
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const unique = values => [...new Set(values)];
const normalized = value => value.replace(/\s+/g, ' ').trim();
const inputPath = process.argv[2];
if (!inputPath) throw Error('Pass an explicit final completed-evidence JSON input; no outputs generated.');
const input = read(inputPath), prior = read(base + 'requirement-matrix-20261002.json');
const review = read(base + 'requirements-review-20261003.json');
const specification = fs.readFileSync(prior.spec, 'utf8');
const approved = new Map([...specification.matchAll(/^(?:- |### )((?:FR|AC|EC|NFR)-\d{3}):\s*([\s\S]*?)(?=^(?:- |### )(?:FR|AC|EC|NFR)-\d{3}:|^## |^### [^A]|$(?![\s\S]))/gm)].map(match => [match[1], normalized(match[2])]));
if (approved.size !== 181 || prior.requirements.length !== 181 || review.requirements.length !== 181 ||
    hash(prior.spec) !== prior.spec_sha256) throw Error('Approved specification/count/hash drift.');
for (const [kind, count] of Object.entries({FR:95, AC:26, EC:40, NFR:20})) {
  if ([...approved.keys()].filter(id => id.startsWith(kind + '-')).length !== count) throw Error('Approved category count drift.');
}
for (const row of prior.requirements) {
  if (approved.get(row.id) !== normalized(row.approved_behavior)) throw Error('Approved full wording drift: ' + row.id);
}
const scopeFile = base + 'requirements-coverage-paths-20261003.txt';
const scope = fs.readFileSync(scopeFile, 'utf8').trim().split(/\r?\n/);
if (scope.length !== 189 || new Set(scope).size !== 189) throw Error('Approved cumulative 189-file scope drift.');
const raw = read(input.coverage_raw), coverage = read(input.coverage_reviewed);
if (coverage.files.length !== 189 || coverage.files.some(row => !scope.includes(row.file) || row.source_sha256 !== hash(row.file))) {
  throw Error('Current coverage/source scope drift.');
}
for (const key of ['files','lines','lines_hit','branches','branches_hit','line_percent','branch_percent']) {
  if (raw.changed_dart[key] !== coverage.changed_dart[key] || raw.pure_domain[key] !== coverage.pure_domain[key]) throw Error('Supplement changed measured counts.');
}
if (!Array.isArray(input.checks) || !input.checks.length) throw Error('Completed checks must be explicit.');
const checks = input.checks.map(check => {
  if (!check.kind || !check.file || check.complete !== true) throw Error('Uncompleted or unclassified check.');
  const result = {...check, sha256: hash(check.file), boundary: check.boundary ?? 'Recorded synthetic execution; not installed/native/owner acceptance.'};
  if (Number.isInteger(check.passed) && Number.isInteger(check.failed)) {
    const progress = [...fs.readFileSync(check.file,'utf8').matchAll(/\+(\d+)(?:\s+-(\d+))?\s*:/g)].at(-1);
    if (!progress || Number(progress[1]) !== check.passed || Number(progress[2] ?? 0) !== check.failed) throw Error('Recorded test count differs from completed log: ' + check.file);
  }
  if (check.source_capture) {
    const capture = read(check.source_capture);
    result.source_capture_sha256 = hash(check.source_capture);
    result.full_capture_source_mismatches = capture.files.filter(row => !fs.existsSync(row.file) || row.sha256 !== hash(row.file)).map(row => row.file);
    const prefixes = check.source_capture_include_prefixes;
    if (prefixes && (!Array.isArray(prefixes) || !prefixes.length || prefixes.some(prefix => !/^packages\/[a-z_]+\/lib\/$/.test(prefix)))) throw Error('Dependency subset must name explicit package lib roots.');
    const selected = prefixes ? capture.files.filter(row => prefixes.some(prefix => row.file.startsWith(prefix))) : capture.files;
    if (!selected.length || (prefixes && prefixes.some(prefix=>!selected.some(row=>row.file.startsWith(prefix))))) throw Error('Actual execution capture lacks dependency subset.');
    result.current_source_match_scope = prefixes ?? 'complete_actual_execution_capture';
    result.source_mismatches = selected.filter(row => !fs.existsSync(row.file) || row.sha256 !== hash(row.file)).map(row => row.file);
    if (prefixes) {
      const subsetFile = base + 'requirements-execution-subset-' + check.kind.replace(/[^a-z0-9-]/gi,'-') + '-20261003.json';
      const subset = {generated_at:new Date().toISOString(), execution_observed_at:capture.observed_at,
        raw_capture:{file:check.source_capture,sha256:hash(check.source_capture)}, actual_executed_package_lib_roots:prefixes,files:selected,
        boundary:'Derivative dependency-only view of unchanged actual execution-start hashes. Raw capture/date remain intact. Test fixture execution is its recorded source revision; no current fixture, native, installation or owner acceptance is inferred.'};
      fs.writeFileSync(subsetFile,JSON.stringify(subset,null,2)+'\n');
      result.dependency_subset = {file:subsetFile,sha256:hash(subsetFile),files:selected.length};
    }
    result.current_source_match = result.source_mismatches.length === 0;
  } else if (check.build_source_hashes) {
    const saved = read(check.build_source_hashes), build = read(check.file);
    if (!Array.isArray(saved) || build.status !== 'compiled' || build.exit_code !== 0 || build.source_files !== saved.length || hash(build.binary) !== build.sha256.toLowerCase()) throw Error('Compiled binary/source ledger mismatch.');
    result.build_source_hashes_sha256 = hash(check.build_source_hashes);
    result.source_mismatches = saved.filter(row => hash(row.path.replaceAll('\\','/')) !== row.sha256.toLowerCase()).map(row=>row.path);
    result.current_source_match_scope = 'actual isolated compilation source ledger and binary hash; no native launch';
    result.current_source_match = result.source_mismatches.length === 0;
  } else {
    result.current_source_match = false;
    result.source_boundary = 'No paired execution-start source capture supplied; log outcome remains recorded, not source-matched current proof.';
  }
  return result;
});
const client = 'apps/jentra_desktop/lib/src/features/';
const tests = 'apps/jentra_desktop/test/';
const procurementPath = file => client+'procurement/'+file;
const procurementTests = ['procurement_inflight_recovery_20261003_test.dart','procurement_dialog_access_20261003_test.dart','procurement_connectivity_provider_20261003_test.dart'].map(file=>tests+file);
const procurementShared = [procurementPath('procurement_picker.dart'), 'docs/blueprint/56_WAVE3_PROCUREMENT_REFERENCE_ACCESS_CONTRACT.md', ...procurementTests];
const additions = {
  requisition: ['procurement_controller.dart','procurement_screen.dart'].map(procurementPath).concat(procurementShared),
  po: ['purchase_order_controller.dart','purchase_order_screen.dart','sourcing_controller.dart','sourcing_screen.dart'].map(procurementPath).concat(procurementShared),
  receipt: ['goods_receipt_controller.dart','goods_receipt_screen.dart'].map(procurementPath).concat(procurementShared),
  bill: ['supplier_bill_controller.dart','supplier_bill_screen.dart','purchase_return_controller.dart'].map(procurementPath).concat(procurementShared),
  settlement: ['supplier_payment_controller.dart','supplier_payment_screen.dart'].map(procurementPath).concat(procurementShared, [tests+'supplier_payment_lifecycle_20261003_test.dart']),
  units: [procurementPath('product_unit_controller.dart'), ...procurementShared],
  inventory: [
    'stock_count/stock_count_controller.dart','stock_count/stock_count_screen.dart',
    'disposition/disposition_controller.dart','disposition/disposition_screen.dart',
    'landed_extension/landed_extension_controller.dart','landed_extension/landed_extension_screen.dart',
    'reservations/reservation_controller.dart','reservations/reservation_screen.dart',
    'landed_value/landed_value_controller.dart','landed_value/landed_value_screen.dart',
  ].map(file => client + file).filter(file => fs.existsSync(file)),
  control: ['control_reconciliation/control_reconciliation_controller.dart','control_reconciliation/control_reconciliation_screen.dart'].map(file => client + file),
  quotation: ['quotation_scope_guard.dart','quotation_reference_picker.dart','quotation_screen.dart','quotation_editor.dart'].map(file => client + 'sales/' + file).concat(['docs/blueprint/52_WAVE3_COMMERCIAL_CLIENT_VALIDATION_CONTRACT.md']),
  order: ['quotation_scope_guard.dart','quotation_reference_picker.dart','quotation_editor.dart','sales_order_screen.dart','sales_order_dialogs.dart'].map(file => client + 'sales/' + file).concat(['docs/blueprint/52_WAVE3_COMMERCIAL_CLIENT_VALIDATION_CONTRACT.md']),
  journal: ['manual_journal/manual_journal_controller.dart','manual_journal/manual_journal_screen.dart'].map(file => client + file),
  period: ['period_fx/period_fx_controller.dart','period_fx/period_fx_screen.dart'].map(file => client + file),
  bank: ['bank_reconciliation/bank_reconciliation_controller.dart','bank_reconciliation/bank_reconciliation_screen.dart'].map(file => client + file),
};
const datedTests = fs.readdirSync(tests).filter(file => file.endsWith('_20261003_test.dart')).map(file => tests + file);
const sharedAccess = client + 'operations/operational_read_access.dart';
const sourcesFor = row => unique([
  ...row.source_evidence, ...(additions[row.review_group] ?? []),
  ...(['FR-395','NFR-313'].includes(row.id) ? [sharedAccess, ...Object.values(additions).flat(), ...datedTests,
    'docs/blueprint/51_WAVE3_INVENTORY_EXTENSION_CONTRACT.md'].filter(file => fs.existsSync(file)) : []),
]);
const finalFiles = [inputPath, input.coverage_raw, input.coverage_reviewed, ...checks.map(check => check.file),
  base + 'requirements-dialog-findings-20261003.md', base + 'database-verification-reuse-20261003.json',
  ...(input.additional_review ?? [])];
const requirements = prior.requirements.map(row => {
  const missing = ['FR-353','EC-323'].includes(row.id);
  return {...row,
    implementation: missing ? 'missing_owner_selected_enabled_negative_stock_policy' : 'reviewed_current_candidate_source_present',
    missing_implementation: missing ? 'Enabled negative-stock interim valuation, deficit cover ordering and immutable later-receipt correction await explicit owner policy selection. Negative-stock OFF checks do not satisfy enabled-policy behavior.' : null,
    source_evidence: sourcesFor(row),
    verification_evidence: unique([...row.verification_evidence, ...finalFiles]),
    verification_evidence_historical: row.verification_evidence.map(file => ({file, sha256: hash(file), source_boundary: 'Historical artifact retained; current proof is recorded separately.'})),
    verification_evidence_current: checks,
    missing_verification: missing ? 'Selected-policy implementation and enabled deficit/receipt regressions remain absent.' : row.id === 'NFR-317'
      ? (coverage.gates.changed_dart_line_80 && coverage.gates.pure_domain_branch_90 ? 'Numerical/source-matched coverage gates pass. Installed/native invariants and acceptance remain separately unverified.' : 'Current source-checked coverage gate remains open; see unchanged counts, actual missing/mismatched source and 80/90 thresholds in the raw/supplement reports.')
      : 'Completed checks establish only their named, captured synthetic scenarios. Failed whole-suite/visual cases and installed-role, native recovery, actual scale/session/load and owner acceptance remain separate gates.',
    external_acceptance: 'Concrete isolated installation/resources/fixtures and distinct existing authenticated sessions need explicit approval. Native profile/store/cold-launch acceptance, target-scale p95 and owner signoff remain separate.',
  };
});
const allFiles = unique([...requirements.flatMap(row => [...row.source_evidence,...row.verification_evidence]), ...checks.flatMap(check => check.source_capture ? [check.source_capture] : [])]);
const matrix = {
  generated_on: '2026-10-03', generated_at: new Date().toISOString(), generator: 'tools/wave3/current-requirement-matrix-20261003.mjs',
  generator_sha256: hash('tools/wave3/current-requirement-matrix-20261003.mjs'), head: review.head,
  spec: prior.spec, spec_sha256: hash(prior.spec), counts: prior.counts, requirements,
  current_checks: checks, coverage: {raw:input.coverage_raw, reviewed:input.coverage_reviewed, scope:scopeFile, selected_files:189, changed_dart:coverage.changed_dart,pure_domain:coverage.pure_domain,gates:coverage.gates},
  candidate_boundary: review.database, source_sha256: Object.fromEntries(allFiles.map(file => [file,hash(file)])),
  confirmed_missing_development: requirements.filter(row => row.missing_implementation).map(row => ({id:row.id,description:row.missing_implementation})),
  policy_decision: prior.policy_decision, historical_matrix: {file:base+'requirement-matrix-20261002.json',sha256:hash(base+'requirement-matrix-20261002.json')},
  boundary: 'Exact 181 approved IDs and normalized full wording preserved. Current source hashes and explicit completed outcomes supersede historical evidence only for their recorded scenarios. No inference of exhaustive implementation, installation, native/authenticated/load/visual acceptance or owner signoff.',
};
fs.writeFileSync(base+'requirement-matrix-20261003.json',JSON.stringify(matrix,null,2)+'\n');
const cell = value => String(value ?? '').replaceAll('|','\\|').replace(/\r?\n/g,' ');
const rows = requirements.map(row => `| ${row.id} | ${cell(row.approved_behavior)} | ${cell(row.implementation)} | ${cell(row.missing_implementation ?? 'No additional confirmed accounting gap in this review; bounded current-source synthetic corrections recorded separately.')} | ${cell(row.missing_verification)} | ${cell(row.external_acceptance)} |`);
fs.writeFileSync(base+'requirement-matrix-20261003.md',[
  '# Approved Wave 3 requirement matrix — 2026-10-03','',
  'Exact 181 approved identifiers/full wording: 95 FR, 26 AC, 40 EC, 20 NFR. The companion JSON contains current source hashes, historical artifacts and explicit current outcomes per ID. No approved behavior is added or removed.','',
  `Current HEAD: ${review.head}. All 45 candidate bodies remain source-matched and unapplied; 1,328 rollback assertions are reused only for identical executed SQL bodies. These are not installed/native/authenticated/load or owner acceptance.`, '',
  `Current changed-Dart coverage: ${coverage.changed_dart.line_percent.toFixed(2)}%, ${coverage.changed_dart.lines_hit}/${coverage.changed_dart.lines} lines over the unchanged 189 selected paths. Pure-domain branch coverage: ${coverage.pure_domain.branch_percent.toFixed(2)}%, ${coverage.pure_domain.branches_hit}/${coverage.pure_domain.branches} branches. Gates: ${JSON.stringify(coverage.gates)}. Exact two declaration-only flags are corrected in a separate supplement; raw history, scope, hits, denominators and thresholds remain unchanged.`, '',
  ...checks.map(check => `- ${check.kind}: ${check.file}; completed outcome ${cell(check.outcome ?? `${check.passed ?? '?'} passed / ${check.failed ?? '?'} failed`)}; current source match ${check.current_source_match} in explicit scope ${cell(JSON.stringify(check.current_source_match_scope ?? 'no capture'))}. Original fixture and complete-capture drift remain recorded separately.`), '',
  'FR-353/EC-323 remain owner-policy-dependent development gaps. Whole-suite/visual failures and isolated installation, native cold launch/recovery, real independent authenticated contention, target-scale p95 and owner signoff remain explicit acceptance gates. Generic continuation does not authorize accounting policy or acceptance operations.', '',
  '| ID | Exact approved behavior | Current development | Confirmed missing implementation | Missing verification | External acceptance |',
  '|---|---|---|---|---|---|',...rows,'',
].join('\n'));
console.log(JSON.stringify({approved_ids:requirements.length,selected_paths:scope.length,current_checks:checks.length,missing_policy_ids:matrix.confirmed_missing_development.map(row=>row.id),coverage_gates:coverage.gates}));
