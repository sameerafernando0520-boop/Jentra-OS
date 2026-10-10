import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { auditGoldenInputs } from './golden_review_inputs_20261010.mjs';
import { parseTestLog } from './record_continuation_windows.mjs';

// Emits new review artifacts only after genuine, hash-bound fresh evidence exists.
// Never runs an SDK, updates a golden, or writes the living requirement matrix.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const paths = {
  initial: `${base}owner-acceptance-readiness-20261010.json`,
  initialMarkdown: `${base}owner-acceptance-readiness-20261010.md`,
  matrix: `${base}requirement-matrix-20261008.json`,
  mapping: `${base}process-owner-review-coverage-20261010.json`,
  process: `${base}golden-review-processDomain-20261010-r1.json`,
  analyzer: `${base}golden-review-analyzer-20261010-r1.json`,
  source: `${base}golden-review-source-20261010-r1.json`,
  candidate: `${base}golden-review-candidate-20261010-r1.json`,
  output: `${base}owner-acceptance-readiness-20261010-r1.json`,
  markdown: `${base}owner-acceptance-readiness-20261010-r1.md`,
};
const readyIds = ['AC-551', 'AC-552', 'AC-553'];
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const read = p => fs.readFile(path.resolve(root, p));
const bound = new Map();
async function bind(p) {
  const bytes = await read(p), item = { path: p, sha256: sha(bytes) };
  if (bound.has(p) && bound.get(p).sha256 !== item.sha256) throw Error(`INPUT_CHANGED:${p}`);
  bound.set(p, item);
  return { bytes, item };
}
async function load(p) {
  const { bytes, item } = await bind(p);
  return { data: JSON.parse(bytes), item };
}
const initial = await load(paths.initial), matrix = await load(paths.matrix), mapping = await load(paths.mapping);
await bind(paths.initialMarkdown);
const project = r => [r.id, r.bundle, r.specification, r.specificationLine, r.statement];
if (matrix.data.rows.length !== 109 || matrix.data.rows.some(r => r.ownerAccepted) || matrix.data.ownerAcceptedCriteria !== 0) throw Error('OWNER_STATE_CHANGED');
if (initial.data.rows.length !== 109 || JSON.stringify(initial.data.rows.map(project)) !== JSON.stringify(matrix.data.rows.map(project))) throw Error('INITIAL_MATRIX_PROJECTION_DRIFT');
if (initial.data.sourceMatrix.sha256 !== matrix.item.sha256 || initial.data.rows.some(r => r.ownerAccepted || r.wholeCriterionReadyForOwnerReview)) throw Error('INITIAL_PACKET_CHANGED');
if (mapping.data.sourceMatrix.sha256 !== matrix.item.sha256 || JSON.stringify(mapping.data.conditionalFullStatementMappedIds) !== JSON.stringify(readyIds)) throw Error('MAPPING_SCOPE_DRIFT');
for (const b of initial.data.inputBindings) {
  const current = await bind(b.path);
  if (current.item.sha256 !== b.sha256) throw Error(`INITIAL_BOUND_EVIDENCE_DRIFT:${b.path}`);
}
for (const r of matrix.data.rows) {
  const { bytes } = await bind(r.specification), lines = bytes.toString('utf8').split(/\r?\n/), statement = [];
  for (let i = r.specificationLine - 1; i < lines.length; i++) {
    const line = lines[i];
    if (i > r.specificationLine - 1 && (!line.trim() || /^(?:- |###? )?(?:FR|NFR|AC|EC)-\d+:/.test(line) || /^## /.test(line))) break;
    statement.push(line.replace(/^(?:- |### )/, '').trim());
  }
  const old = initial.data.rows.find(o => o.id === r.id);
  if (!statement[0]?.startsWith(`${r.id}:`) || statement.join(' ') !== old.fullStatement || old.fullCriterionStatement !== old.fullStatement) throw Error(`CURRENT_FULL_STATEMENT_DRIFT:${r.id}`);
}

const source = await load(paths.source), candidate = await load(paths.candidate);
if (Object.keys(source.data.sourceHashes).length !== 1068) throw Error('EXACT1068_SOURCE_SCOPE_REQUIRED');
if (candidate.data.sourceManifest.path !== paths.source || candidate.data.sourceManifest.sha256 !== source.item.sha256 || sha(Buffer.from(JSON.stringify(candidate.data.bundle))) !== candidate.data.bundleSha256) throw Error('CANDIDATE_MANIFEST_BINDING_DRIFT');
if (candidate.data.cases.length !== 83 || new Set(candidate.data.cases.map(c => c.approvedPath)).size !== 83) throw Error('EXACT83_OVERLAYS_REQUIRED');
const expectedSnapshot = { ...source.data.sourceHashes };
for (const c of candidate.data.cases) {
  if (expectedSnapshot[c.approvedPath] !== c.approvedSha256) throw Error('OVERLAY_BASE_DRIFT');
  expectedSnapshot[c.approvedPath] = c.candidateSha256;
}
const expectedCurrentHash = sha(Buffer.from(JSON.stringify(source.data.sourceHashes)));
const expectedSnapshotHash = sha(Buffer.from(JSON.stringify(expectedSnapshot)));

function checkAudit(a) {
  if (!a || a.selectedSources !== 1068 || a.snapshotMatchesDeclaredInputs !== true || a.currentWorkspaceMatchesFrozenBase !== true) throw Error('STAGE_SOURCE_AUDIT_NOT_GREEN');
  if (a.sourceManifest.path !== paths.source || a.sourceManifest.sha256 !== source.item.sha256 || a.currentInputsSha256 !== expectedCurrentHash || a.snapshotInputsSha256 !== expectedSnapshotHash) throw Error('STAGE_SOURCE_MANIFEST_DRIFT');
  if (a.candidateManifest.path !== paths.candidate || a.candidateManifest.sha256 !== candidate.item.sha256 || a.candidateManifest.bundleSha256 !== candidate.data.bundleSha256) throw Error('STAGE_CANDIDATE_DRIFT');
  if (!Array.isArray(a.overlays) || a.overlays.length !== 83 || new Set(a.overlays.map(o => o.path)).size !== 83) throw Error('STAGE_OVERLAY_SCOPE_DRIFT');
  for (const o of a.overlays) {
    if (source.data.sourceHashes[o.path] !== o.baseSha256 || expectedSnapshot[o.path] !== o.candidateSha256) throw Error('STAGE_OVERLAY_HASH_DRIFT');
  }
}

async function checkStage(p, name) {
  const stage = await load(p), s = stage.data;
  if (s.stage !== name || s.exitCode !== 0 || s.integrityError !== null || !Array.isArray(s.args)) throw Error(`STAGE_NOT_GREEN:${name}`);
  if (!s.startedAt || !s.finishedAt || !(Date.parse(s.startedAt) <= Date.parse(s.finishedAt)) || Date.parse(s.startedAt) < Date.parse(source.data.capturedAt)) throw Error(`STAGE_TIME_BINDING:${name}`);
  checkAudit(s.inputAuditBefore); checkAudit(s.inputAuditAfter);
  if (JSON.stringify(s.inputAuditBefore.toolchain) !== JSON.stringify(s.inputAuditAfter.toolchain)) throw Error(`TOOLCHAIN_DRIFT:${name}`);
  const log = await bind(s.log);
  if (log.item.sha256 !== s.logSha256) throw Error(`LOG_DRIFT:${name}`);
  for (const b of [s.runner, s.inputAuditor]) {
    if (!b?.path || !b.sha256) throw Error(`STAGE_TOOL_BINDING_MISSING:${name}`);
    const now = await bind(b.path);
    if (now.item.sha256 !== b.sha256) throw Error(`STAGE_TOOL_DRIFT:${name}`);
  }
  return { record: stage, log: log.item, text: log.bytes.toString('utf8') };
}
const processStage = await checkStage(paths.process, 'processDomain');
const analysisStage = await checkStage(paths.analyzer, 'analyzer');
const process = processStage.record.data, analysis = analysisStage.record.data;
const metricTest = 'packages/jentra_domain/test/analytics/process_metrics_test.dart';
const filterTest = 'packages/jentra_domain/test/analytics/process_filter_contract_test.dart';
const metricsBytes = await bind(metricTest), filtersBytes = await bind(filterTest);
const names = bytes => [...bytes.toString('utf8').matchAll(/\btest\(\s*'([^']+)'/g)].map(m => m[1]);
const metricNames = names(metricsBytes.bytes), filterNames = names(filtersBytes.bytes);
if (metricNames.length !== 25 || filterNames.length !== 2 || new Set([...metricNames, ...filterNames]).size !== 27) throw Error('FOCUSED_FIXTURE_SCOPE_DRIFT');
if (!process.args.includes('test/analytics/process_metrics_test.dart') || !process.args.includes('test/analytics/process_filter_contract_test.dart') || process.workingDirectory !== path.join(source.data.snapshot, 'packages/jentra_domain')) throw Error('DOMAIN_STAGE_TARGET_DRIFT');
if (!process.counts || process.counts.passed !== 27 || process.counts.failed !== 0 || process.counts.skipped !== 0) throw Error('FOCUSED_DOMAIN_NOT27_GREEN');
const parsed = parseTestLog(processStage.text);
if (!parsed || parsed.passedTests !== 27 || parsed.failedTests !== 0 || parsed.skippedTests !== 0 || !processStage.text.includes('All tests passed!')) throw Error('ACTUAL_LOG_NOT27_GREEN');
const executions = [...processStage.text.replace(/\r/g, '').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)].map(m => ({ file: m[1].replaceAll('\\', '/'), name: m[2] }));
for (const [file, expected] of [['test/analytics/process_metrics_test.dart', metricNames], ['test/analytics/process_filter_contract_test.dart', filterNames]]) {
  for (const name of expected) if (!executions.some(e => e.file.endsWith(file) && e.name === name)) throw Error(`ACTUAL_FOCUSED_EXECUTION_MISSING:${name}`);
}
const analyzerTargets = ['apps/jentra_desktop/lib','apps/jentra_desktop/test','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'];
if (JSON.stringify(analysis.args) !== JSON.stringify(['analyze', ...analyzerTargets]) || analysis.workingDirectory !== source.data.snapshot || !/^\s*No issues found!\s*$/m.test(analysisStage.text)) throw Error('ANALYSIS_SCOPE_OR_RESULT_DRIFT');

// Source mapping is retained separately; no real digest/provider claim is inferred.
for (const id of readyIds) {
  const row = initial.data.rows.find(r => r.id === id), mapped = mapping.data.rows.find(r => r.id === id);
  if (!row || !mapped || mapped.completeStatementMapping !== true || mapped.ownerAccepted || mapped.fullStatement !== row.fullStatement || row.fullCriterionStatement !== row.fullStatement) throw Error(`FULL_STATEMENT_MAPPING_DRIFT:${id}`);
  for (const b of mapped.sourceBindings) {
    const current = await bind(b.path);
    if (current.item.sha256 !== b.sha256 || source.data.sourceHashes[b.path] !== b.sha256) throw Error(`MAPPED_SOURCE_DRIFT:${b.path}`);
  }
  for (const t of mapped.tests) if (!metricNames.includes(t.name)) throw Error(`MAPPED_TEST_DRIFT:${id}`);
}
for (const specification of new Set(matrix.data.rows.map(r => r.specification))) await bind(specification);

// A fresh read-only audit validates the same complete source/overlay/toolchain set now.
const currentAudit = await auditGoldenInputs('processDomain');
checkAudit(currentAudit);
if (JSON.stringify(currentAudit.toolchain) !== JSON.stringify(process.inputAuditAfter.toolchain) || JSON.stringify(currentAudit.toolchain) !== JSON.stringify(analysis.inputAuditAfter.toolchain)) throw Error('CURRENT_TOOLCHAIN_DRIFT');
const selfPath = 'scripts/wave5/refine_owner_readiness_20261010.mjs';
await bind(selfPath);
const stageEvidence = [processStage.record.item, processStage.log, analysisStage.record.item, analysisStage.log, source.item, candidate.item, mapping.item];
const rows = structuredClone(initial.data.rows);
for (const id of readyIds) {
  const r = rows.find(r => r.id === id), mapped = mapping.data.rows.find(r => r.id === id);
  r.wholeCriterionReadyForOwnerReview = true;
  r.reviewReadiness = 'whole_calculation_criterion_ready_for_explicit_owner_review';
  r.decisionScope = 'Complete stated pure-domain process.event_duration.v1 calculation criterion. Installed source access, certified producer semantics, native behavior and release acceptance remain separate criteria.';
  r.rationale = `${mapped.mappedBehavior} Fresh 25 metric tests plus 2 filter tests passed with zero failures/skips; fresh scoped analyzer reports no issues. All 1068 current/frozen inputs and the 83 declared image overlays are hash-audited before, after and at packet preparation.`;
  r.unresolvedObligations = 'Owner must explicitly accept this complete named calculation criterion against its statement and bound evidence. No acceptance is recorded by preparation; dependent adapter/native/runtime criteria remain open.';
  r.blockingGates = ['explicit_owner_acceptance'];
  r.evidence.push(...stageEvidence);
  r.currentCriterionEvidence = {
    kind: 'fresh_exact_source_domain_calculation_and_scoped_analysis',
    metricTests: 25, filterTests: 2, passed: 27, failed: 0, skipped: 0,
    domainStage: processStage.record.item, analysisStage: analysisStage.record.item,
    sourceManifest: source.item, testExecutions: mapped.tests,
    sourceBindings: mapped.sourceBindings,
    scopeBoundary: 'Fixture input verifies pure calculation. No installed permission/provider/source certification, native/MFA, delivery, contention/load or owner decision is inferred.',
  };
  r.historicalDomainBoundary = 'Fresh evidence here supersedes historical tests for this calculation decision only. Real digest transport and installed source authority remain separate.';
}
const record = {
  ...initial.data,
  observedAt: new Date().toISOString(),
  boundary: 'Refined owner review proposal from actual exact-source controlled domain tests and scoped analysis. No owner decision, baseline update, living matrix change, runtime approval or installed/native claim.',
  initialPacket: initial.item,
  sourceMatrix: matrix.item,
  sourceManifest: source.item,
  wholeCriterionReadyForOwnerReviewCount: 3,
  wholeCriterionReadyForOwnerReviewIds: readyIds,
  fullAcceptanceBlockedCount: 106,
  ownerAcceptedCriteria: 0,
  wholeWaveComplete: false,
  inputBindings: [...initial.data.inputBindings, ...[...bound.values()].filter(b => !initial.data.inputBindings.some(i => i.path === b.path))],
  freshProcessEvidence: {
    domainStage: processStage.record.item, domainLog: processStage.log,
    analysisStage: analysisStage.record.item, analysisLog: analysisStage.log,
    metricTests: 25, filterTests: 2, passed: 27, failed: 0, skipped: 0,
    sourceManifest: source.item, candidateManifest: candidate.item,
    currentInputAudit: currentAudit,
    initialRuntimeBundleSuperseded: false,
    goldenBaselineApprovalInferred: false,
  },
  rows,
};
if (rows.length !== 109 || rows.some(r => r.ownerAccepted || r.ownerDecision !== null) || JSON.stringify(rows.map(project)) !== JSON.stringify(matrix.data.rows.map(project))) throw Error('OUTPUT_ACCEPTANCE_OR_IDENTITY_DRIFT');
if (rows.filter(r => r.wholeCriterionReadyForOwnerReview).length !== 3) throw Error('OUTPUT_READY_SCOPE_DRIFT');

const absolute = p => path.resolve(root,p).replaceAll('\\','/');
const link = b => `[${path.basename(b.path)}](<${absolute(b.path)}>)`;
let md = '# Owner acceptance readiness — fresh calculation evidence, October 10, 2026\n\n';
md += 'Three complete pure calculation criteria are now ready for an explicit owner review: AC-551, AC-552 and AC-553. All 109 ownerAccepted flags remain false. The other 106 criteria remain open; the nine earlier governance checkpoint proposals remain partial and non-counting.\n\n';
md += `Fresh evidence: 25 process metric tests and 2 filter tests, 27 passed / zero failed / zero skipped, plus scoped Dart analysis with no issues. The domain/analyzer stages and this packet independently bind the same 1,068 selected inputs and exactly 83 candidate image overlays in a frozen copy. Images and the new dependency-lock snapshot are review inputs; no approved baseline changes occur.\n\n`;
md += `${link(processStage.record.item)} · ${link(processStage.log)} · ${link(analysisStage.record.item)} · ${link(analysisStage.log)} · ${link(source.item)} · ${link(mapping.item)}\n\n`;
md += '## Full calculation statements proposed for decision\n\n';
for (const r of rows.filter(r => r.wholeCriterionReadyForOwnerReview)) {
  md += `### ${r.id}\n\n${r.fullStatement}\n\n${r.rationale}\n\n${r.unresolvedObligations}\n\n`;
}
md += '## Every criterion remains unaccepted\n\n| ID | Full criterion statement | Readiness for a whole criterion |\n|---|---|---|\n';
for (const r of rows) md += `| ${r.id} | ${r.fullStatement.replaceAll('|','\\|')} | ${r.wholeCriterionReadyForOwnerReview?'Ready for explicit calculation-only decision; unaccepted':'Open; '+r.blockingGates.join('; ').replaceAll('_',' ')} |\n`;
md += `\nThe preserved initial packet is ${link(initial.item)}. The living matrix SHA-256 remains \`${matrix.item.sha256}\`. Runtime review approval, installed providers, genuine MFA, native keyboard/recovery, actual model/export/worker delivery, independent contention/load and all remaining owner decisions stay open. Production and real billing remain excluded.\n`;
for (const b of bound.values()) if (sha(await read(b.path)) !== b.sha256) throw Error(`CONCURRENT_BOUND_INPUT_DRIFT:${b.path}`);
if (sha(await read(paths.matrix)) !== matrix.item.sha256) throw Error('CONCURRENT_MATRIX_DRIFT');
if (process.argv.includes('--validate-only')) {
  console.log(JSON.stringify({ validated: true, wholeCriterionReadyForOwnerReviewIds: readyIds, ownerAccepted: 0, outputsWritten: false }));
} else {
  for (const p of [paths.output, paths.markdown]) {
    try { await fs.access(path.resolve(root,p)); throw Error(`REFUSING_OVERWRITE:${p}`); }
    catch (e) { if (e.code !== 'ENOENT') throw e; }
  }
  await fs.writeFile(path.resolve(root,paths.output),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
  await fs.writeFile(path.resolve(root,paths.markdown),md,{flag:'wx'});
  console.log(JSON.stringify({ outputs:[paths.output,paths.markdown], wholeCriterionReadyForOwnerReviewIds:readyIds, ownerAccepted:0, sourceMatrixSha256:matrix.item.sha256 }));
}
