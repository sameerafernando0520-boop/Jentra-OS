// Prepare a narrow living-document update from the final exact-image owner review.
// Default is a read-only preview. The root may pass --write after evidence freeze.
// No SDK job, native launch, baseline promotion, acceptance or live operation occurs.
import { access, copyFile, lstat, mkdir, open, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { auditGoldenInputs } from './golden_review_inputs_20261010_r2.mjs';
import { parseTestLog } from './record_continuation_windows.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const write = process.argv.includes('--write');
if (process.argv.slice(2).some(a => a !== '--write')) throw Error('UNKNOWN_ARGUMENT');
const paths = {
  matrix: base + 'requirement-matrix-20261008.json',
  markdown: base + 'requirement-matrix-20261008.md',
  status: 'docs/development/wave5-status.md',
  review: base + 'golden-owner-review-20261010-r2.json',
  readiness: base + 'owner-acceptance-readiness-20261010-r2.json',
  source: base + 'golden-review-source-20261010-r2.json',
  candidate: base + 'golden-review-candidate-20261010-r2.json',
  control: base + 'golden-review-controlAll-20261010-r2.json',
  candidateStage: base + 'golden-review-candidateGoldens-20261010-r2.json',
  analyzer: base + 'golden-review-analyzer-20261010-r2.json',
  domain: base + 'golden-review-processDomain-20261010-r2-serial.json',
  build: base + 'golden-review-build-20261010-r2.json',
  comparison: base + 'continuation-goldens-comparison-20261009-r13.json',
  before: base + 'golden-owner-status-before-20261010-r2-guarded-serial.json',
  after: base + 'golden-owner-status-after-20261010-r2-guarded-serial.json',
};
const readyIds = ['AC-551', 'AC-552', 'AC-553'];
const sha = b => createHash('sha256').update(b).digest('hex');
const parse = b => JSON.parse(b.toString('utf8').replace(/^\uFEFF/, ''));
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const ordered = o => Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b)));
const project = r => [r.id, r.bundle, r.specification, r.specificationLine, r.statement, r.ownerAccepted];
function inside(p) {
  if (typeof p !== 'string' || path.isAbsolute(p)) throw Error('RELATIVE_EVIDENCE_PATH_REQUIRED');
  const resolved = path.resolve(root, p), rel = path.relative(root, resolved);
  if (!rel || rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel)) throw Error('EVIDENCE_PATH_ESCAPES:' + p);
  return resolved;
}
async function bytes(p) {
  const resolved = inside(p);
  if ((await lstat(resolved)).isSymbolicLink()) throw Error('EVIDENCE_LINK_REFUSED:' + p);
  return readFile(resolved);
}
const living = [paths.matrix, paths.markdown, paths.status];
// Capture the exact starting documents before reading the review or deriving rows.
const originalBytes = new Map(await Promise.all(living.map(async p => [p, await bytes(p)])));
const originalHashes = new Map([...originalBytes].map(([p, b]) => [p, sha(b)]));
const expectedLivingHashes = new Map(originalHashes);
const matrix = parse(originalBytes.get(paths.matrix));
const originalProjection = matrix.rows?.map(project);
if (matrix.requirementCount !== 109 || matrix.rows?.length !== 109 || new Set(matrix.rows.map(r => r.id)).size !== 109 ||
    matrix.ownerAcceptedCriteria !== 0 || matrix.wholeWaveComplete !== false || matrix.rows.some(r => r.ownerAccepted !== false)) throw Error('OWNER_OR_REQUIREMENT_STATE_CHANGED');
const bound = new Map();
async function bind(p, expected) {
  const b = originalBytes.has(p) ? originalBytes.get(p) : await bytes(p), h = sha(b);
  if ((expected && h !== expected) || (bound.has(p) && bound.get(p).sha256 !== h)) throw Error('BOUND_INPUT_DRIFT:' + p);
  bound.set(p, { path: p, sha256: h });
  return b;
}
async function json(p) { return parse(await bind(p)); }
const [review, readiness, source, candidate, comparison] = await Promise.all([
  json(paths.review), json(paths.readiness), json(paths.source), json(paths.candidate), json(paths.comparison),
]);
const reviewExtra = new Set(['reviewSha256', 'html', 'imageCount', 'embeddedImages',
  'allDecisionsInitiallyPending', 'actualOwnerDecisionsRecorded', 'ownerAcceptanceCount', 'reviewCore']);
const projectedReviewCore = Object.fromEntries(Object.entries(review).filter(([k]) => !reviewExtra.has(k)));
const reviewCore = review.reviewCore ?? projectedReviewCore;
if (!eq(reviewCore, projectedReviewCore) || sha(JSON.stringify(reviewCore)) !== review.reviewSha256 || review.imageCount !== 83 || review.embeddedImages !== 249 ||
    review.allDecisionsInitiallyPending !== true || review.actualOwnerDecisionsRecorded !== 0 || review.ownerAcceptanceCount !== 0) throw Error('FINAL_REVIEW_BOUNDARY_OR_HASH_CHANGED');
await bind(review.html?.path, review.html?.sha256);
if (review.candidateBundleSha256 !== candidate.bundleSha256 || sha(JSON.stringify(candidate.bundle)) !== candidate.bundleSha256 ||
    !eq(candidate.sourceManifest, candidate.bundle.sourceManifest) || !eq(candidate.control, candidate.bundle.control) ||
    candidate.sourceManifest.path !== paths.source || candidate.sourceManifest.sha256 !== bound.get(paths.source).sha256 ||
    candidate.control.path !== paths.control || candidate.cases?.length !== 83 || new Set(candidate.cases.map(c => c.stem)).size !== 83 ||
    new Set(candidate.cases.map(c => c.approvedPath)).size !== 83 || candidate.approvedRepositoryImagesChanged !== false ||
    candidate.comparatorChanged !== false || candidate.fixturePermissionsChanged !== false || candidate.ownerAccepted !== false) throw Error('EXACT_CANDIDATE_SCOPE_CHANGED');
const candidateProjection = candidate.cases.map(({ stem, approvedPath, approvedSha256, candidateSha256 }) => ({ stem, approvedPath, approvedSha256, candidateSha256 }));
if (!eq(candidateProjection, candidate.bundle.cases) || !eq(review.images, candidate.cases) || review.requirements?.length !== 109 ||
    !eq(review.requirements.map(r => [r.id, r.bundle, r.specification, r.ownerAccepted]), matrix.rows.map(r => [r.id, r.bundle, r.specification, r.ownerAccepted]))) throw Error('REVIEW_CASE_OR_REQUIREMENT_BINDING_CHANGED');
const classificationCounts = {};
for (const c of candidate.cases) {
  if (!/^apps\/jentra_desktop\/test\/goldens\/[A-Za-z0-9_-]+\.png$/.test(c.approvedPath) || source.sourceHashes?.[c.approvedPath] !== c.approvedSha256 || c.ownerAccepted !== false) throw Error('UNAPPROVED_BASELINE_SCOPE_CHANGED');
  classificationCounts[c.classification] = (classificationCounts[c.classification] ?? 0) + 1;
  for (const [p, h] of [[c.approvedPath, c.approvedSha256], [c.approvedBackup, c.approvedSha256],
    [c.candidatePath, c.candidateSha256], [c.diffPath, c.diffSha256]]) await bind(p, h);
}
if (!eq(ordered(classificationCounts), ordered({ 'localized-border-raster': 65, 'capability-navigation-and-border-raster': 16, 'payroll-content-change': 2 }))) throw Error('CLASSIFICATION_COUNTS_CHANGED');
if (Object.keys(source.sourceHashes ?? {}).length !== 1068 || source.selectedSourceCount !== 1068 ||
    !source.deltaFromR13?.some(d => d.path === 'pubspec.lock') || source.sourceStable !== true) throw Error('CURRENT_DEPENDENCY_SNAPSHOT_REQUIRED');
if (readiness.sourceMatrix?.path !== paths.matrix || readiness.sourceMatrix.sha256 !== originalHashes.get(paths.matrix) ||
    readiness.rows?.length !== 109 || !eq(readiness.rows.map(project), originalProjection) || readiness.ownerAcceptedCriteria !== 0 ||
    readiness.wholeWaveComplete !== false || readiness.rows.some(r => r.ownerAccepted !== false || r.ownerDecision !== null) ||
    !eq(readiness.rows.filter(r => r.wholeCriterionReadyForOwnerReview).map(r => r.id).sort(), readyIds) ||
    !eq(review.proposedCriterionIds?.slice().sort(), readyIds) || readiness.wholeCriterionReadyForOwnerReviewCount !== 3) throw Error('THREE_COMPLETE_CALCULATION_REVIEW_ROWS_REQUIRED');
for (const b of [...review.refs, ...(readiness.inputBindings ?? []), ...readiness.rows.flatMap(r => r.evidence ?? [])]) await bind(b.path, b.sha256);
if (!eq(review.readiness, readiness)) throw Error('REVIEW_READINESS_CHANGED');
for (const row of matrix.rows) {
  const lines = (await bind(row.specification)).toString('utf8').split(/\r?\n/), statement = [];
  for (let i = row.specificationLine - 1; i < lines.length; i++) {
    const line = lines[i];
    if (i > row.specificationLine - 1 && (!line.trim() || /^(?:- |###? )?(?:FR|NFR|AC|EC)-\d+:/.test(line) || /^## /.test(line))) break;
    statement.push(line.replace(/^(?:- |### )/, '').trim());
  }
  if (!statement[0]?.startsWith(row.id + ':') || readiness.rows.find(r => r.id === row.id).fullCriterionStatement !== statement.join(' ') ||
      review.requirements.find(r => r.id === row.id).statement !== statement.join(' ')) throw Error('FULL_CRITERION_WORDING_DRIFT:' + row.id);
}
const expectedCurrentHash = sha(JSON.stringify(source.sourceHashes));
const expectedCopy = { ...source.sourceHashes };
for (const c of candidate.cases) expectedCopy[c.approvedPath] = c.candidateSha256;
const expectedCopyHash = sha(JSON.stringify(expectedCopy));
function checkAudit(a) {
  if (!a || a.selectedSources !== 1068 || a.snapshotMatchesDeclaredInputs !== true || a.currentWorkspaceMatchesFrozenBase !== true ||
      a.sourceManifest?.path !== paths.source || a.sourceManifest.sha256 !== bound.get(paths.source).sha256 ||
      a.currentInputsSha256 !== expectedCurrentHash || a.snapshotInputsSha256 !== expectedCopyHash ||
      a.candidateManifest?.path !== paths.candidate || a.candidateManifest.sha256 !== bound.get(paths.candidate).sha256 ||
      a.candidateManifest.bundleSha256 !== candidate.bundleSha256 || a.overlays?.length !== 83 ||
      new Set(a.overlays.map(o => o.path)).size !== 83 || a.overlays.some(o => source.sourceHashes[o.path] !== o.baseSha256 || expectedCopy[o.path] !== o.candidateSha256)) throw Error('EXACT_SOURCE_AUDIT_NOT_GREEN');
}
async function stage(p, name, counts) {
  const s = await json(p), log = await bind(s.log, s.logSha256), text = log.toString('utf8');
  if (s.stage !== name || s.exitCode !== 0 || s.integrityError !== null || !s.startedAt || !s.finishedAt ||
      Date.parse(s.startedAt) < Date.parse(source.capturedAt) || Date.parse(s.startedAt) > Date.parse(s.finishedAt)) throw Error('FRESH_STAGE_NOT_GREEN:' + name);
  checkAudit(s.inputAuditBefore); checkAudit(s.inputAuditAfter);
  if (!eq(s.inputAuditBefore.toolchain, s.inputAuditAfter.toolchain)) throw Error('STAGE_TOOLCHAIN_DRIFT:' + name);
  for (const b of [s.runner, s.inputAuditor]) await bind(b.path, b.sha256);
  if (counts) {
    const parsed = parseTestLog(text);
    if (!s.counts || ['passed', 'failed', 'skipped'].some(k => s.counts[k] !== counts[k]) || !parsed?.allTestsPassed || parsed.passedTests !== counts.passed ||
        parsed.failedTests !== 0 || parsed.skippedTests !== 0) throw Error('FRESH_TEST_SUMMARY_DRIFT:' + name);
  }
  return { s, text };
}
const control = await json(paths.control), controlLog = await bind(control.log, control.logSha256), controlParsed = parseTestLog(controlLog.toString('utf8'));
await bind(paths.control, candidate.control.sha256);
const normalized = n => n.replaceAll('\\', '/').slice(n.replaceAll('\\', '/').indexOf('/test/') + 6);
const pairs = cases => cases.map(c => normalized(c.name) + '|' + c.golden).sort();
if (control.stage !== 'controlAll' || control.exitCode !== 1 || !controlParsed || controlParsed.passedTests !== 1921 ||
    controlParsed.failedTests !== 83 || controlParsed.skippedTests !== 0 || controlParsed.failures.length !== 83 ||
    controlParsed.failures.some(f => f.kind !== 'golden-comparison') || !eq(pairs(controlParsed.failures), pairs(comparison.cases))) throw Error('APPROVED_CONTROL_FAILURE_SET_CHANGED');
const candidateStage = await stage(paths.candidateStage, 'candidateGoldens', { passed: 83, skipped: 0, failed: 0 });
const analysis = await stage(paths.analyzer, 'analyzer');
const domain = await stage(paths.domain, 'processDomain', { passed: 27, skipped: 0, failed: 0 });
const build = await stage(paths.build, 'build');
const identities = candidate.cases.map(c => c.test).sort();
const executedIdentities = [...new Set([...candidateStage.text.replace(/\r/g, '').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)]
  .map(m => normalized(m[1] + ': ' + m[2])))].sort();
if (!eq(candidateStage.s.expectedCaseIdentities?.slice().sort(), identities) ||
    !eq(executedIdentities, identities)) throw Error('EXACT83_EXECUTED_IDENTITIES_REQUIRED');
if (!/^\s*No issues found!\s*$/m.test(analysis.text) || !domain.s.args.includes('test/analytics/process_metrics_test.dart') ||
    !domain.s.args.includes('test/analytics/process_filter_contract_test.dart') ||
    !build.s.args.includes('--target=lib/main.dart') || !build.s.args.includes('--dart-define=JENTRA_ENVIRONMENT=preview') ||
    !/Built build[\\/]windows[\\/]x64[\\/]runner[\\/]Release[\\/].+\.exe/i.test(build.text)) throw Error('ANALYSIS_DOMAIN_OR_BUILD_SCOPE_CHANGED');
if (review.run?.path !== paths.candidateStage || review.run.sha256 !== bound.get(paths.candidateStage).sha256) throw Error('OWNER_REVIEW_EXECUTION_BINDING_CHANGED');
for (const p of [base + 'complete-app-runtime-review-20261009.json', base + 'complete-app-runtime-review-20261009.md',
  base + 'complete-app-runtime-review-20261009-r13.json', base + 'complete-app-runtime-review-20261009-r13.md',
  base + 'windows-test-verification-20261009-r10.json', base + 'windows-test-verification-20261009-r13.json']) await bind(p);
for (const key of ['actualModelUsage', 'realMfa', 'actualWorkerDelivery', 'authenticatedNativeAcceptance',
  'independentSessionContention', 'targetScaleLoad', 'nativeKeyboardVerified', 'ownerSignoff', 'newRuntimeInstallationComplete']) {
  if (matrix[key] !== false) throw Error('SEPARATE_RECORDED_GATE_CHANGED:' + key);
}

const now = new Date().toISOString();
const evidencePaths = [paths.review, paths.readiness, paths.source, paths.candidate, paths.control, paths.candidateStage,
  paths.analyzer, paths.domain, paths.build];
const addEvidence = (row, additions) => { for (const p of additions) if (!row.evidence.includes(p)) row.evidence.push(p); };
for (const id of readyIds) {
  const row = matrix.rows.find(r => r.id === id), ready = readiness.rows.find(r => r.id === id);
  row.developmentStatus = `Fresh exact-source process.event_duration.v1 pure calculation evidence: 25 metric tests plus 2 filter tests pass (27 passed / 0 failed / 0 skipped) and scoped analysis reports no issues. ${ready.rationale} Complete ${id} is ready for an explicit owner calculation decision; owner acceptance remains absent.`;
  row.remaining = 'Explicit owner review and acceptance of this complete named pure calculation criterion. Installed source access, certified producer semantics, authenticated native/MFA, delivery and load remain separate criteria and are not inferred from these fixtures.';
  addEvidence(row, [paths.readiness, paths.domain, domain.s.log, paths.analyzer, analysis.s.log, paths.source, paths.review]);
}
for (const id of ['FR-536', 'AC-517']) addEvidence(matrix.rows.find(r => r.id === id), evidencePaths);
if (!eq(matrix.rows.map(project), originalProjection)) throw Error('SPECIFICATION_OR_OWNER_FLAGS_CHANGED');
matrix.updatedAt = now;
matrix.goldenReviewPriorContinuationChecks ??= structuredClone(matrix.continuationChecks);
matrix.goldenOwnerReview = { path: paths.review, reviewSha256: review.reviewSha256, candidateBundleSha256: candidate.bundleSha256,
  sourceManifest: paths.source, selectedSourceInputs: 1068, dependencyDeltaFromR13: source.deltaFromR13,
  approvedControl: { record: paths.control, passed: 1921, failed: 83, skipped: 0, baselineOwnerApproved: false },
  candidateImages: { record: paths.candidateStage, passed: 83, failed: 0, skipped: 0, scope: 'Exactly 83 image cases in an isolated copy; no full candidate suite claimed.' },
  analyzer: paths.analyzer, processDomain: paths.domain, previewBuild: paths.build,
  fullCalculationCriteriaReadyForOwnerReview: readyIds, ownerAcceptedCriteria: 0,
  approvedBaselineImagesChanged: false, postApprovalFullSuiteRequired: true,
  originalMatrixCheckpoint: { path: paths.before, matrixSha256: originalHashes.get(paths.matrix) },
  authenticatedNative: false, nativeKeyboard: false, realMfa: false, actualGovernedExportDelivery: false,
  actualModelUsage: false, actualWorkerDelivery: false, independentSessionContention: false, targetScaleLoad: false,
  runtimeApproval: false, ownerSignoff: false, production: false, realBilling: false };
matrix.continuationChecks = { sourceRevision: 'golden-review-20261010-r2', sourceFileCount: 1068,
  sourceManifest: paths.source, currentSourceScope: 'Frozen desktop and its three package dependencies, plus workspace manifests.',
  wholeWorkspaceSourceMatch: false, analyzerCurrentSource: true, analyzerScope: analysis.s.args,
  windowsPreviewBuildCurrentSourceMatch: true, windowsConnectedBuildCurrentSourceMatch: false,
  domainEvidenceCurrent: true, domainEvidenceScope: 'Only 25 process metric and 2 filter tests; 27 pass / zero failures/skips.',
  broadDesktopApprovedControlCurrent: true, approvedDesktopControl: { record: paths.control, passed: 1921, failed: 83, skipped: 0 },
  strictCandidateGoldenCasesCurrent: true, candidateGoldenCases: { record: paths.candidateStage, passed: 83, failed: 0, skipped: 0 },
  fullCandidateDesktopSuiteRerun: false, approvedGoldensRegenerated: false,
  historicalPriorEvidence: base + 'windows-test-verification-20261009-r13.json',
  historicalPriorEvidenceCurrentSourceMatch: false, dependencyDeltaFromR13: source.deltaFromR13,
  nativeKeyboardVerified: false, authenticatedNativeAcceptance: false, realMfa: false,
  actualGovernedExportDelivery: false, actualModelUsage: false, actualWorkerDelivery: false,
  independentSessionContention: false, targetScaleLoad: false, ownerAcceptance: false };
matrix.windowsUserTestPackage = { ...matrix.windowsUserTestPackage, historicalSourceRevision: 'r13', currentSourceMatch: false,
  currentSourceDelta: source.deltaFromR13, boundary: 'Preserved r13 Preview/Connected packages; dependency lock and two golden test asset-wait helpers have since changed. The new Preview build is separately recorded and is not native or Connected acceptance.' };
if (!eq(matrix.rows.map(project), originalProjection) || matrix.ownerAcceptedCriteria !== 0 || matrix.wholeWaveComplete !== false) throw Error('PUBLICATION_ACCEPTANCE_BOUNDARY_CHANGED');

const relative = (from, p) => path.posix.relative(path.posix.dirname(from), p);
const link = (from, label, p) => `[${label}](<${relative(from, p)}>)`;
function replaceOnce(text, before, after, label) {
  const index = text.indexOf(before);
  if (index < 0 || text.indexOf(before, index + before.length) >= 0) throw Error('DOCUMENT_LAYOUT_DRIFT:' + label);
  return text.slice(0, index) + after + text.slice(index + before.length);
}
const summary = from => `Fresh ${link(from, 'approved-baseline control', paths.control)} records **1921 passed / 83 failed / 0 skipped**. The ${link(from, 'strict candidate-image run', paths.candidateStage)} passes **exactly 83 cases / 0 failures / 0 skips** in an isolated copy with the declared PNG overlays; it is a focused run, not a 2004-test candidate suite. All 83 approved repository PNGs remain unchanged and unapproved for replacement. The ${link(from, 'self-contained owner review', review.html.path)} binds image bundle \`${candidate.bundleSha256}\` and packet \`${review.reviewSha256}\`; it records no owner decision.`;
const calculation = from => `${link(from, 'Fresh process-domain evidence', paths.domain)} is 27 passed / zero failed / zero skipped (25 metrics plus 2 filters), with ${link(from, 'clean scoped analysis', paths.analyzer)} and a ${link(from, 'fresh ordinary Preview Windows build', paths.build)}. Exactly three complete pure calculation criteria—AC-551, AC-552 and AC-553—are ${link(from, 'ready for explicit owner review', paths.readiness)}; **zero of 109 criteria are owner-accepted**. The other 106 criteria remain open. Image choices and calculation decisions are independent.`;
const historical = 'The new r2 1068-input snapshot preserves the concurrent pubspec.lock change and records exactly two authorized test-helper asset waits. It reuses the guarded warm r1 execution tree after restoring all 83 approved PNGs in that copy. The r1 focused candidate result (80 passed / 3 cold-logo failures) and its nine diagnostic images remain preserved. r13 source/test/build/render records and packages are historical for their older dependency lock and test helpers; their bytes remain preserved. The new checks do not establish authenticated native use or keyboard/MFA, actual model/export/worker delivery, independent-session contention, target-scale load or owner acceptance. The additional 71-migration runtime review remains unapproved; production and real billing remain excluded.';
let markdown = originalBytes.get(paths.markdown).toString('utf8');
markdown = replaceOnce(markdown, '# Wave 5 requirement matrix — updated October 10, 2026', '# Wave 5 requirement matrix — updated October 10, 2026', 'matrix title');
const matrixIntro = 'All 109 approved requirement identifiers and specification mappings are preserved. Zero IDs are owner-accepted; Jentra OS and Wave 5 remain incomplete.';
markdown = replaceOnce(markdown, matrixIntro, matrixIntro + '\n\n' + summary(paths.markdown) + '\n\n' + calculation(paths.markdown) + '\n\n' + historical + '\n\nPreserved row descriptions and r13 paragraphs below retain historical context; only the three named calculation rows have updated implementation status.', 'matrix introduction');
markdown = replaceOnce(markdown, '[Current native evidence](windows-test-verification-20261009-r13.md)', '[Historical r13 native evidence](windows-test-verification-20261009-r13.md)', 'historical matrix native label');
markdown = replaceOnce(markdown, 'bind the current source. The old review/r10 evidence remain preserved.', 'bind the preserved r13 source. The dependency-lock change is bound by the new golden review; original reviews/r10 evidence remain preserved.', 'historical matrix source claim');
for (const id of readyIds) {
  const row = matrix.rows.find(r => r.id === id), lines = markdown.split(/\r?\n/), indices = lines.map((l, i) => l.startsWith(`| ${id} |`) ? i : -1).filter(i => i >= 0);
  if (indices.length !== 1) throw Error('MATRIX_TABLE_ROW_DRIFT:' + id);
  const parts = lines[indices[0]].split(' | ');
  if (parts.length !== 3 || !parts[2].endsWith(' |')) throw Error('MATRIX_TABLE_LAYOUT_DRIFT:' + id);
  lines[indices[0]] = `${parts[0]} | ${parts[1]} | ${row.developmentStatus.replaceAll('|', '\\|')} |`;
  markdown = lines.join('\n');
}
const matrixAppend = '\n## October 10 exact-image and calculation review\n\n' + summary(paths.markdown) + '\n\n' + calculation(paths.markdown) + '\n\n' +
  readyIds.map(id => { const r = matrix.rows.find(r => r.id === id); return `**${id}:** ${r.developmentStatus}\n\nRemaining: ${r.remaining}`; }).join('\n\n') +
  '\n\nNew evidence for the three process rows and the reporting criteria FR-536/AC-517:\n\n' + evidencePaths.map(p => `- ${link(paths.markdown, p, p)}`).join('\n') +
  '\n\nThe exact starting matrix/status bytes and hashes are preserved by ' + link(paths.markdown, 'the immutable before checkpoint', paths.before) + '. Existing row IDs, bundles, specification paths/lines, statements, owner flags and evidence links are retained.\n';
if (markdown.includes('## October 10 exact-image and calculation review')) throw Error('STATUS_UPDATE_ALREADY_PRESENT');
markdown += matrixAppend;
let status = originalBytes.get(paths.status).toString('utf8');
const firstParagraph = status.split(/\r?\n\r?\n/)[1];
if (!firstParagraph?.startsWith('Updated October 10, 2026. **Jentra OS and Wave 5 remain incomplete.**')) throw Error('STATUS_INTRODUCTION_LAYOUT_DRIFT');
status = replaceOnce(status, firstParagraph, 'Updated October 10, 2026. **Jentra OS and Wave 5 remain incomplete.**\n\n' + summary(paths.status) + '\n\n' + calculation(paths.status) + '\n\n' + historical + '\n\nHistorical r13 checkpoint: ' + firstParagraph, 'status introduction');
status = status.replace('Fresh scoped r13 source/build/render evidence; trial r10 sign-in corroborated; all 83 retained goldens classified', 'Fresh 1068-input scoped analysis, 27 domain tests, approved control1921/83 and candidate83/0; trial r10 sign-in corroborated; all 83 image causes diagnosed');
status = status.replace('The payroll cases require the separately owned Wave 4 visual decision; the 16 navigation cases require intended fixture/capability policy reconciliation.', 'The two payroll content changes and all 16 capability-navigation cases retain their authorized source and limited fixture permissions; exact owner image decisions remain pending.');
status = status.replace('The [refreshed operation review]', 'The [preserved r13 operation review]');
status += '\nOctober 10 image decisions, three complete calculation review proposals and all remaining gates are bound by ' +
  link(paths.status, 'the owner review record', paths.review) + ' and ' + link(paths.status, 'the immutable starting-document checkpoint', paths.before) + '. No baseline promotion or criterion acceptance occurred.\n';
const outputs = new Map([[paths.matrix, Buffer.from(JSON.stringify(matrix, null, 2) + '\n')], [paths.markdown, Buffer.from(markdown)], [paths.status, Buffer.from(status)]]);
const selfPath = 'scripts/wave5/update_golden_owner_status_20261010_r2_guarded_serial.mjs';
await bind(selfPath);
async function verifyBeforePublication() {
  for (const [p, h] of expectedLivingHashes) if (sha(await bytes(p)) !== h) throw Error('CONCURRENT_LIVING_DOCUMENT_CHANGE:' + p);
  for (const b of bound.values()) if (!living.includes(b.path) && sha(await bytes(b.path)) !== b.sha256) throw Error('CONCURRENT_BOUND_INPUT_CHANGE:' + b.path);
  const audit = await auditGoldenInputs('build');
  checkAudit(audit);
  if (!eq(audit.toolchain, build.s.inputAuditAfter.toolchain)) throw Error('CURRENT_TOOLCHAIN_DRIFT');
  return audit;
}
// Retain the exact existing document before publication. The exclusive copy
// cannot replace a concurrently created destination. Failures never restore or retry.
async function claimAndPublishDocument(state) {
  await rename(state.target, state.recovery);
  state.claimed = true;
  state.recoverySha256 = sha(await readFile(state.recovery));
  if (state.recoverySha256 !== state.originalSha256) throw Error('CONCURRENT_CLAIMED_DOCUMENT_CHANGE:' + state.path);
  await copyFile(state.temp, state.target, constants.COPYFILE_EXCL);
  state.published = true;
  expectedLivingHashes.set(state.path, state.plannedSha256);
}
async function observePublicationDocuments(states) {
  const observed = [];
  for (const state of states) {
    try {
      const b = await bytes(state.path), h = sha(b);
      observed.push({ path: state.path, sha256: h, bytes: b.length, exists: true,
        matchesOriginal: h === state.originalSha256, matchesPlanned: h === state.plannedSha256 });
    } catch (e) {
      observed.push({ path: state.path, sha256: null, exists: e.code !== 'ENOENT', observationError: e.message, code: e.code ?? null });
    }
  }
  return observed;
}
async function observePublicationRecoveries(states) {
  const observed = [];
  for (const state of states.filter(s => s.claimed)) {
    try {
      const b = await bytes(state.recoveryPath), h = sha(b);
      observed.push({ path: state.recoveryPath, sha256: h, bytes: b.length,
        claimedSha256: state.recoverySha256, originalSha256: state.originalSha256,
        matchesClaimed: h === state.recoverySha256, originalMatched: h === state.originalSha256, published: state.published });
    } catch (e) {
      observed.push({ path: state.recoveryPath, sha256: null, observationError: e.message, code: e.code ?? null, published: state.published });
    }
  }
  return observed;
}
const initialAudit = await verifyBeforePublication();
const before = { preparedAt: now, kind: 'living-status-before-checkpoint', ownerAcceptedCriteria: 0,
  approvedBaselineImagesChanged: false, review: bound.get(paths.review), reviewSha256: review.reviewSha256,
  candidateBundleSha256: candidate.bundleSha256, readiness: bound.get(paths.readiness), sourceManifest: bound.get(paths.source),
  inputs: [...bound.values()], currentSourceAudit: initialAudit,
  originalLivingDocuments: [...originalBytes].map(([p, b]) => ({ path: p, sha256: sha(b), bytes: b.length, utf8Base64: b.toString('base64') })),
  plannedDocuments: [...outputs].map(([p, b]) => ({ path: p, sha256: sha(b), bytes: b.length })),
  changedCriterionStatusIds: readyIds, addedReportingEvidenceIds: ['FR-536', 'AC-517'],
  boundary: 'Exact original public living-document bytes, preserved before a narrow status update. No owner decision, baseline promotion, installation, native use or delivery is recorded.' };
if (write) {
  for (const p of [paths.before, paths.after]) { try { await access(inside(p)); throw Error('IMMUTABLE_OUTCOME_EXISTS:' + p); } catch (e) { if (e.code !== 'ENOENT') throw e; } }
  await verifyBeforePublication();
  const recoveryDirectory = base + 'golden-owner-status-recovery-20261010-r2-guarded-serial-' + randomUUID();
  const states = [...outputs].map(([p, b]) => ({ path: p, target: inside(p), originalSha256: originalHashes.get(p),
    plannedSha256: sha(b), recoveryPath: recoveryDirectory + '/' + path.basename(p),
    recovery: inside(recoveryDirectory + '/' + path.basename(p)), temp: null, tempOwned: false,
    claimed: false, published: false, recoverySha256: null }));
  const preparedBefore = { ...before, recoveryDirectory,
    plannedPublication: states.map(s => ({ path: s.path, originalSha256: s.originalSha256, plannedSha256: s.plannedSha256, recoveryPath: s.recoveryPath })) };
  const beforeBytes = Buffer.from(JSON.stringify(preparedBefore, null, 2) + '\n');
  await writeFile(inside(paths.before), beforeBytes, { flag: 'wx' });
  // Reserve a unique attempt journal before changing any living document.
  const outcome = await open(inside(paths.after), 'wx');
  const cleanupErrors = [], postVerificationErrors = [];
  let publicationError = null, finalAudit = null;
  try {
    await outcome.writeFile(JSON.stringify({ status: 'in_progress', startedAt: now, kind: 'living-status-after-result',
      before: { path: paths.before, sha256: sha(beforeBytes) }, recoveryDirectory, plannedPublication: preparedBefore.plannedPublication,
      boundary: 'An interrupted attempt requires actual destination and recovery reconciliation. This journal does not claim zero changes.' }, null, 2) + '\n');
    await mkdir(inside(recoveryDirectory));
    for (const state of states) {
      await verifyBeforePublication();
      state.temp = inside(state.path + '.' + randomUUID() + '.tmp');
      const temporary = await open(state.temp, 'wx'); state.tempOwned = true;
      try { await temporary.writeFile(outputs.get(state.path)); } finally { await temporary.close(); }
      await verifyBeforePublication();
      await claimAndPublishDocument(state);
    }
    await verifyBeforePublication();
  } catch (e) { publicationError = { message: e.message, code: e.code ?? null }; }
  for (const state of states) if (state.tempOwned) {
    try { await unlink(state.temp); } catch (e) { if (e.code !== 'ENOENT') cleanupErrors.push({ path: path.relative(root, state.temp), message: e.message, code: e.code ?? null }); }
  }
  const observedDocuments = await observePublicationDocuments(states);
  const retainedRecoveries = await observePublicationRecoveries(states);
  try { finalAudit = await verifyBeforePublication(); } catch (e) {
    postVerificationErrors.push({ gate: 'finalLivingBoundSourceAndToolAudit', message: e.message, code: e.code ?? null });
    publicationError ??= { message: e.message, code: e.code ?? null };
  }
  if (observedDocuments.some(d => d.matchesPlanned !== true)) {
    postVerificationErrors.push({ gate: 'actualDestinationHashes', message: 'DESTINATION_DOCUMENT_DRIFT_AFTER_PUBLICATION' });
    publicationError ??= { message: 'DESTINATION_DOCUMENT_DRIFT_AFTER_PUBLICATION', code: null };
  }
  if (retainedRecoveries.some(r => r.originalMatched !== true || r.matchesClaimed !== true)) {
    postVerificationErrors.push({ gate: 'actualRecoveryHashes', message: 'RECOVERY_DOCUMENT_DRIFT_AFTER_PUBLICATION' });
    publicationError ??= { message: 'RECOVERY_DOCUMENT_DRIFT_AFTER_PUBLICATION', code: null };
  }
  if (cleanupErrors.length) publicationError ??= { message: 'OWNED_TEMP_CLEANUP_FAILED', code: null };
  const changed = states.filter(s => s.published).map(s => s.path);
  const observations = new Map(observedDocuments.map(d => [d.path, d]));
  const after = { startedAt: now, finishedAt: new Date().toISOString(), kind: 'living-status-after-result',
    status: publicationError ? 'failed' : 'complete', before: { path: paths.before, sha256: sha(beforeBytes) }, recoveryDirectory,
    changedDocuments: changed, remainingDocuments: living.filter(p => !changed.includes(p)), observedDocuments, retainedRecoveries,
    publishedDocuments: states.filter(s => s.published).map(s => ({ path: s.path, plannedSha256: s.plannedSha256, observed: observations.get(s.path) })),
    claimedWithoutPublication: states.filter(s => s.claimed && !s.published).map(s => ({ path: s.path, recoveryPath: s.recoveryPath,
      claimedSha256: s.recoverySha256, observedDestination: observations.get(s.path) })),
    fullPublication: changed.length === living.length && publicationError === null && cleanupErrors.length === 0 &&
      observedDocuments.every(d => d.matchesPlanned === true) && retainedRecoveries.every(r => r.originalMatched === true && r.matchesClaimed === true) && finalAudit !== null,
    publicationError, cleanupErrors, postVerificationErrors, finalSourceAndToolAudit: finalAudit, validatedInputs: [...bound.values()],
    ownerAcceptedCriteria: 0, approvedBaselineImagesChanged: false, originalProjectionPreserved: eq(matrix.rows.map(project), originalProjection),
    boundary: 'Only the named living status/matrix documents may change. Actual partial outcomes and uniquely owned original/concurrent bytes remain retained; no automatic restoration or retry, baseline promotion, acceptance or live operation occurs.' };
  try { await outcome.truncate(0); await outcome.write(JSON.stringify(after, null, 2) + '\n', 0, 'utf8'); } finally { await outcome.close(); }
  console.log(JSON.stringify({ write, ...after }, null, 2));
  if (!after.fullPublication) process.exitCode = 1;
} else {
  console.log(JSON.stringify({ write, reviewSha256: review.reviewSha256, candidateBundleSha256: candidate.bundleSha256,
    approvedControl: { passed: 1921, failed: 83 }, focusedCandidate: { passed: 83, failed: 0 },
    calculationReadyIds: readyIds, ownerAcceptedCriteria: 0, documents: before.plannedDocuments,
    immutableBefore: paths.before, immutableAfter: paths.after, currentSourceVerified: true,
    originalProjectionPreserved: true, outputsWritten: false }, null, 2));
}
