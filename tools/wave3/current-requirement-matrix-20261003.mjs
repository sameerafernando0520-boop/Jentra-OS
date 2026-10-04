import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {artifactTag, verifyCandidateOrder, verifyStrictExecution, writeNewJson} from './strict-candidate-evidence.mjs';

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
const tag=artifactTag(input.artifact_tag??'20261003');
const generatedOn=tag.slice(0,4)+'-'+tag.slice(4,6)+'-'+tag.slice(6,8);
const matrixPath=base+`requirement-matrix-${tag}.json`, markdownPath=base+`requirement-matrix-${tag}.md`;
if([matrixPath,markdownPath].some(file=>fs.existsSync(file)))throw Error('Retain the earlier matrix; choose an unused explicit artifact_tag.');
const review = read(base + 'requirements-review-20261003.json');
const head = execFileSync('git', ['rev-parse','HEAD'], {encoding:'utf8'}).trim();
if (input.head !== head) throw Error('Explicit completed evidence must bind the current observed HEAD.');
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
const baselineScopeFile = base + 'requirements-coverage-paths-20261003.txt';
const baselineScope = fs.readFileSync(baselineScopeFile, 'utf8').trim().split(/\r?\n/);
if (baselineScope.length !== 189 || new Set(baselineScope).size !== 189) throw Error('Cumulative baseline 189-file scope drift.');
const scopeFile = input.coverage_scope ?? baselineScopeFile;
const scope = fs.readFileSync(scopeFile, 'utf8').trim().split(/\r?\n/);
if (scope.length < 189 || new Set(scope).size !== scope.length || baselineScope.some(file=>!scope.includes(file))) throw Error('Cumulative coverage scope must preserve all baseline paths.');
const raw = read(input.coverage_raw), coverage = read(input.coverage_reviewed);
const changedCoverage = coverage.files.filter(row=>row.changed);
if (changedCoverage.length !== scope.length || coverage.changed_dart.files !== scope.length || changedCoverage.some(row=>!scope.includes(row.file)) || coverage.files.some(row => row.source_sha256 !== hash(row.file))) {
  throw Error('Current coverage/source scope drift.');
}
for (const key of ['files','lines','lines_hit','branches','branches_hit','line_percent','branch_percent']) {
  if (raw.changed_dart[key] !== coverage.changed_dart[key] || raw.pure_domain[key] !== coverage.pure_domain[key]) throw Error('Supplement changed measured counts.');
}
const additionalPure = input.coverage_additional_pure_domain ? read(input.coverage_additional_pure_domain) : null;
if (additionalPure && (additionalPure.report.sha256 !== hash(input.coverage_reviewed) || additionalPure.selection.sha256!==hash(additionalPure.selection.file) || JSON.stringify(additionalPure.locked_pure_domain)!==JSON.stringify(coverage.pure_domain) || additionalPure.additional_pure_domain.some(row=>row.source_sha256!==hash(row.file)))) throw Error('Additional pure-domain coverage/report/source mismatch.');
if (additionalPure) {
  const extras = additionalPure.additional_pure_domain;
  if (!extras.length || new Set(extras.map(row=>row.file)).size!==extras.length || extras.some(row=>{
    const measured=coverage.files.find(item=>item.file===row.file);
    return !measured || measured.pure_domain || !measured.changed || !measured.measured || !measured.execution_source_matches ||
      ['source_sha256','lines','lines_hit','branches','branches_hit'].some(key=>measured[key]!==row[key]);
  })) throw Error('Additional pure-domain rows differ from actual source-checked measurements.');
  for (const key of ['files','lines','lines_hit','branches','branches_hit']) {
    const expected=coverage.pure_domain[key]+(key==='files'?extras.length:extras.reduce((sum,row)=>sum+row[key],0));
    if (additionalPure.combined_pure_domain[key]!==expected) throw Error('Additional pure-domain denominator/hit drift.');
  }
  const combined=additionalPure.combined_pure_domain;
  if (combined.branch_percent!==100*combined.branches_hit/combined.branches ||
      additionalPure.gates.combined_pure_domain_branch_90!==(combined.branch_percent>=90&&!coverage.pure_domain.unmeasured_executable.length&&!coverage.pure_domain.source_mismatches.length)) throw Error('Additional pure-domain threshold/math drift.');
}
const coverageGates = {...coverage.gates,...(additionalPure?.gates??{})};
if (!Array.isArray(input.checks) || !input.checks.length) throw Error('Completed checks must be explicit.');
const checks = input.checks.map(check => {
  if (!check.kind || !check.file || check.complete !== true) throw Error('Uncompleted or unclassified check.');
  const result = {...check, sha256: hash(check.file), boundary: check.boundary ?? 'Recorded synthetic execution; not installed/native/owner acceptance.'};
  if (Number.isInteger(check.passed) && Number.isInteger(check.failed)) {
    const log=fs.readFileSync(check.file,'utf8');
    const progress = [...log.matchAll(/\+(\d+)(?:\s+-(\d+))?\s*:/g)].at(-1);
    if (!progress || Number(progress[1]) !== check.passed || Number(progress[2] ?? 0) !== check.failed ||
        !(check.failed ? /Some tests failed[.!]/ : /All tests passed[.!]/).test(log)) throw Error('Recorded test count or terminal outcome differs from completed log: ' + check.file);
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
      const subsetFile = base + 'requirements-execution-subset-' + check.kind.replace(/[^a-z0-9-]/gi,'-') + `-${tag}.json`;
      const subset = {generated_at:new Date().toISOString(), execution_observed_at:capture.observed_at,
        raw_capture:{file:check.source_capture,sha256:hash(check.source_capture)}, actual_executed_package_lib_roots:prefixes,files:selected,
        boundary:'Derivative dependency-only view of unchanged actual execution-start hashes. Raw capture/date remain intact. Test fixture execution is its recorded source revision; no current fixture, native, installation or owner acceptance is inferred.'};
      writeNewJson(subsetFile,subset);
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
const policy = input.policy;
if (!policy || policy.selection !== 'last_authoritative_positive_moving_average' || policy.approved !== true ||
    policy.owner_reply !== 'Approve interim issues at the last authoritative positive moving-average cost, block unknown cost basis, and post linked later-receipt variance corrections.') {
  throw Error('Bind the explicit owner-selected negative-stock policy without inferring it from continuation.');
}
const policySources = [policy.contract,policy.candidate,policy.assertions,...(policy.dart_sources??[])];
if (policySources.some(file=>!file || !fs.existsSync(file))) throw Error('Selected-policy source review requires explicit existing sources.');
const newPureSources = (policy.pure_domain_sources??[]).filter(file=>!coverage.files.some(row=>row.file===file&&row.pure_domain));
if (newPureSources.length && (!additionalPure || newPureSources.some(file=>!additionalPure.additional_pure_domain.some(row=>row.file===file)))) throw Error('New selected-policy pure domain source requires explicit extended branch coverage.');
let policyExecution = null;
if (policy.implemented === true) {
  if (!policy.execution || !policy.query) throw Error('Implemented selected policy requires fresh strict SQL execution evidence.');
  const executed = read(policy.execution), query = fs.readFileSync(policy.query,'utf8').replace(/^\uFEFF/,'');
  const tap=verifyStrictExecution(executed,query,hash(policy.query));
  if (!query.includes(fs.readFileSync(policy.candidate,'utf8')) || !query.includes(fs.readFileSync(policy.assertions,'utf8'))) throw Error('Selected-policy source mismatch.');
  policyExecution = {file:policy.execution,sha256:hash(policy.execution),query:policy.query,query_sha256:hash(policy.query),assertions:tap.assertions,observed_at:executed.observed_at,
    boundary:'Fresh selected-policy synthetic strict rollback execution; no installation, independent authenticated session, native acceptance or owner release.'};
}
const database = input.database_package ? read(input.database_package) : review.database;
if (database.head !== head) throw Error('Current database preparation must bind the refreshed HEAD.');
if (!Array.isArray(database.candidates) || database.candidates.length!==46 || database.candidates.some((row,index)=>row.ordinal!==index+1 || row.sha256!==hash(row.path) || row.installed_now===true || row.installed===true)) throw Error('Current 46-candidate package source/order/install drift.');
if (database.candidates.at(-1).path!==policy.candidate) throw Error('Selected-policy candidate must be the reviewed ordinal46 tail.');
if (policyExecution && (database.fresh_strict_execution?.suites?.length!==3 || database.fresh_strict_execution.suites.some(row=>row.candidates_source_matched!==46||row.strict_finish!==true||row.final_rollback!==true||row.failures!==0||row.query_sha256!==hash(row.query)||row.execution_sha256!==hash(row.execution)))) throw Error('Final selected-policy matrix needs fresh source-bound46stack proof from all3complete strict suites.');
if(policyExecution) {
  const suites=database.fresh_strict_execution.suites;
  if(new Set(suites.map(row=>row.suite)).size!==3||suites.some(row=>!['procurement','inventory','receivables'].includes(row.suite)))throw Error('Final matrix requires each of the three distinct strict suites.');
  for(const row of suites) {
    const query=fs.readFileSync(row.query,'utf8').replace(/^\uFEFF/,'');
    const tap=verifyStrictExecution(read(row.execution),query,hash(row.query));
    if(tap.assertions!==row.assertions)throw Error('Final matrix strict-suite plan mismatch.');
    verifyCandidateOrder(query,database.candidates);
  }
}
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
  ...(['FR-353','EC-323','FR-395','NFR-313'].includes(row.id) || ['inventory','order','receipt','control'].includes(row.review_group) ? policySources : []),
  ...(['FR-395','NFR-313'].includes(row.id) ? [sharedAccess, ...Object.values(additions).flat(), ...datedTests,
    'docs/blueprint/51_WAVE3_INVENTORY_EXTENSION_CONTRACT.md'].filter(file => fs.existsSync(file)) : []),
]);
const finalFiles = [inputPath, input.coverage_raw, input.coverage_reviewed,scopeFile,baselineScopeFile,...checks.map(check => check.file),
  ...(input.coverage_additional_pure_domain?[input.coverage_additional_pure_domain]:[]),
  base + 'requirements-dialog-findings-20261003.md', base + 'database-verification-reuse-20261003.json',
  ...(input.database_package ? [input.database_package] : []), ...(policyExecution ? [policy.execution,policy.query] : []),
  ...(input.additional_review ?? [])];
const requirements = prior.requirements.map(row => {
  const policyRow = ['FR-353','EC-323'].includes(row.id);
  const missing = policyRow && !policyExecution;
  return {...row,
    implementation: missing ? 'approved_selected_policy_development_and_verification_in_progress' : policyRow ? 'selected_policy_candidate_present_fresh_synthetic_regressions_recorded' : 'reviewed_current_candidate_source_present',
    missing_implementation: missing ? 'Owner approved last authoritative positive moving-average interim issues, unknown cost basis blocking and linked later-receipt variance corrections. Candidate development or its fresh enabled-policy regression remains incomplete.' : null,
    source_evidence: sourcesFor(row),
    verification_evidence: unique([...row.verification_evidence, ...finalFiles]),
    verification_evidence_historical: row.verification_evidence.map(file => ({file, sha256: hash(file), source_boundary: 'Historical artifact retained; current proof is recorded separately.'})),
    verification_evidence_current: checks,
    selected_policy_execution: policyRow ? policyExecution : null,
    missing_verification: missing ? 'Fresh source-matched strict rollback enabled deficit/receipt regressions remain pending for the approved policy.' : row.id === 'NFR-317'
      ? (Object.values(coverageGates).every(value=>value===true) ? 'Numerical/source-matched coverage gates pass, including explicitly selected new pure-domain code if present. Installed/native invariants and acceptance remain separately unverified.' : 'Current source-checked coverage gate remains open; see unchanged counts, actual missing/mismatched source and 80/90 thresholds in the raw/supplement reports.')
      : 'Completed checks establish only their named, captured synthetic scenarios. Failed whole-suite/visual cases and installed-role, native recovery, actual scale/session/load and owner acceptance remain separate gates.',
    external_acceptance: 'Concrete isolated installation/resources/fixtures and distinct existing authenticated sessions need explicit approval. Native profile/store/cold-launch acceptance, target-scale p95 and owner signoff remain separate.',
  };
});
const allFiles = unique([...requirements.flatMap(row => [...row.source_evidence,...row.verification_evidence]), ...checks.flatMap(check => check.source_capture ? [check.source_capture] : [])]);
const matrix = {
  generated_on: generatedOn, generated_at: new Date().toISOString(), generator: 'tools/wave3/current-requirement-matrix-20261003.mjs',
  generator_sha256: hash('tools/wave3/current-requirement-matrix-20261003.mjs'), head,
  spec: prior.spec, spec_sha256: hash(prior.spec), counts: prior.counts, requirements,
  current_checks: checks, coverage: {raw:input.coverage_raw, reviewed:input.coverage_reviewed, scope:scopeFile, selected_files:scope.length, changed_dart:coverage.changed_dart,pure_domain:coverage.pure_domain,additional_pure_domain:additionalPure,gates:coverageGates},
  candidate_boundary: database, source_sha256: Object.fromEntries(allFiles.map(file => [file,hash(file)])),
  confirmed_missing_development: requirements.filter(row => row.missing_implementation).map(row => ({id:row.id,description:row.missing_implementation})),
  policy_decision: {...policy, sources:Object.fromEntries(policySources.map(file=>[file,hash(file)])), execution:policyExecution}, historical_matrix: {file:base+'requirement-matrix-20261002.json',sha256:hash(base+'requirement-matrix-20261002.json')},
  boundary: 'Exact 181 approved IDs and normalized full wording preserved. Current source hashes and explicit completed outcomes supersede historical evidence only for their recorded scenarios. No inference of exhaustive implementation, installation, native/authenticated/load/visual acceptance or owner signoff.',
};
writeNewJson(matrixPath,matrix);
const cell = value => String(value ?? '').replaceAll('|','\\|').replace(/\r?\n/g,' ');
const rows = requirements.map(row => `| ${row.id} | ${cell(row.approved_behavior)} | ${cell(row.implementation)} | ${cell(row.missing_implementation ?? 'No additional confirmed accounting gap in this review; bounded current-source synthetic corrections recorded separately.')} | ${cell(row.missing_verification)} | ${cell(row.external_acceptance)} |`);
fs.writeFileSync(markdownPath,[
  `# Approved Wave 3 requirement matrix — ${generatedOn}`,'',
  'Exact 181 approved identifiers/full wording: 95 FR, 26 AC, 40 EC, 20 NFR. The companion JSON contains current source hashes, historical artifacts and explicit current outcomes per ID. No approved behavior is added or removed.','',
  `Current HEAD: ${head}. Current candidate preparation is ${input.database_package??'requirements-review-20261003.json'}; ${database.candidates.length} candidate bodies remain unapplied. The historical 1,328 rollback assertions apply to identical 45-stack bodies only. ${policyExecution?`Fresh selected-policy strict rollback execution records ${policyExecution.assertions} assertions at ${policyExecution.observed_at}.`:'Fresh selected-policy execution remains pending.'} These are not installed/native/authenticated/load or owner acceptance.`, '',
  `Current changed-Dart coverage: ${coverage.changed_dart.line_percent.toFixed(2)}%, ${coverage.changed_dart.lines_hit}/${coverage.changed_dart.lines} lines over ${scope.length} cumulative selected paths (all 189 baseline paths retained). Locked pure-domain branch coverage: ${coverage.pure_domain.branch_percent.toFixed(2)}%, ${coverage.pure_domain.branches_hit}/${coverage.pure_domain.branches} branches. ${additionalPure?`Combined with explicit new pure-domain files: ${additionalPure.combined_pure_domain.branch_percent.toFixed(2)}%, ${additionalPure.combined_pure_domain.branches_hit}/${additionalPure.combined_pure_domain.branches} branches.`:''} Gates: ${JSON.stringify(coverageGates)}. Exact reviewed declaration-only flags are corrected in separate supplements; raw history, scope, hits, denominators and thresholds remain unchanged.`, '',
  ...checks.map(check => `- ${check.kind}: ${check.file}; completed outcome ${cell(check.outcome ?? `${check.passed ?? '?'} passed / ${check.failed ?? '?'} failed`)}; current source match ${check.current_source_match} in explicit scope ${cell(JSON.stringify(check.current_source_match_scope ?? 'no capture'))}. Original fixture and complete-capture drift remain recorded separately.`), '',
  `FR-353/EC-323 have an explicit owner decision: last authoritative positive moving-average interim issues, blocking unknown cost basis and immutable linked later-receipt variance corrections. ${policyExecution?'Current candidate source and fresh bounded synthetic regressions are recorded.':'Implementation or fresh verification remains in progress.'} Whole-suite/visual failures and isolated installation, native cold launch/recovery, real independent authenticated contention, target-scale p95 and owner signoff remain explicit acceptance gates. Accounting-policy approval does not authorize acceptance operations.`, '',
  '| ID | Exact approved behavior | Current development | Confirmed missing implementation | Missing verification | External acceptance |',
  '|---|---|---|---|---|---|',...rows,'',
].join('\n'),{flag:'wx'});
console.log(JSON.stringify({matrix:matrixPath,markdown:markdownPath,approved_ids:requirements.length,selected_paths:scope.length,current_checks:checks.length,missing_policy_ids:matrix.confirmed_missing_development.map(row=>row.id),coverage_gates:coverageGates}));
