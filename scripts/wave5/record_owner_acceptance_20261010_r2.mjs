// Prepare or publish only three complete pure-calculation criterion decisions.
// The caller must first authenticate the direct human reply in the conversation;
// a JSON file, browser draft or this script can never establish that provenance.
// Default preview does not write. Never invokes an SDK or changes a PNG/store.
import { access, copyFile, lstat, mkdir, open, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { auditGoldenInputs } from './golden_review_inputs_20261010_r2.mjs';
import { parseTestLog } from './record_continuation_windows.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const ids = ['AC-551', 'AC-552', 'AC-553'];
const args = process.argv.slice(2), publish = args.includes('--write');
const ownerPath = args.find(a => a !== '--write');
if (args.length !== (publish ? 2 : 1) || args.filter(a => a === '--write').length > 1 ||
    !ownerPath || !/^docs\/verification\/wave5\/owner-criterion-decision-[A-Za-z0-9_-]+\.json$/.test(ownerPath)) throw Error('DIRECT_OWNER_RECORD_ARGUMENT_REQUIRED');
const p = {
  matrix: base + 'requirement-matrix-20261008.json', markdown: base + 'requirement-matrix-20261008.md',
  status: 'docs/development/wave5-status.md', review: base + 'golden-owner-review-20261010-r2.json',
  readiness: base + 'owner-acceptance-readiness-20261010-r2.json', source: base + 'golden-review-source-20261010-r2.json',
  candidate: base + 'golden-review-candidate-20261010-r2.json', control: base + 'golden-review-controlAll-20261010-r2.json',
  candidateStage: base + 'golden-review-candidateGoldens-20261010-r2.json', domain: base + 'golden-review-processDomain-20261010-r2.json',
  analysis: base + 'golden-review-analyzer-20261010-r2.json', build: base + 'golden-review-build-20261010-r2.json',
  mapping: base + 'process-owner-review-coverage-20261010.json', comparison: base + 'continuation-goldens-comparison-20261009-r13.json',
  statusBefore: base + 'golden-owner-status-before-20261010-r2-guarded.json', statusAfter: base + 'golden-owner-status-after-20261010-r2-guarded.json',
  before: base + 'owner-criterion-acceptance-before-20261010-r2.json', after: base + 'owner-criterion-acceptance-after-20261010-r2.json',
};
const sha = b => createHash('sha256').update(b).digest('hex');
const parse = b => JSON.parse(b.toString('utf8').replace(/^\uFEFF/, ''));
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const identity = r => [r.id, r.bundle, r.specification, r.specificationLine, r.statement];
const living = [p.matrix, p.markdown, p.status];
function inside(relative) {
  if (typeof relative !== 'string' || path.isAbsolute(relative)) throw Error('RELATIVE_BOUND_PATH_REQUIRED');
  const resolved = path.resolve(root, relative), rel = path.relative(root, resolved);
  if (!rel || rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel)) throw Error('BOUND_PATH_ESCAPES:' + relative);
  return resolved;
}
async function bytes(relative) {
  const resolved = inside(relative);
  if ((await lstat(resolved)).isSymbolicLink()) throw Error('BOUND_LINK_REFUSED:' + relative);
  return readFile(resolved);
}
// Preserve exact current living bytes before deriving any change.
const original = new Map(await Promise.all(living.map(async file => [file, await bytes(file)])));
const expectedLiving = new Map([...original].map(([file, b]) => [file, sha(b)]));
const bound = new Map(), historical = new Map();
async function bind(file, expected) {
  const b = original.has(file) ? original.get(file) : await bytes(file), h = sha(b);
  if ((expected && h !== expected) || (bound.has(file) && bound.get(file).sha256 !== h)) throw Error('BOUND_INPUT_DRIFT:' + file);
  bound.set(file, { path: file, sha256: h });
  return b;
}
const json = async file => parse(await bind(file));
const matrix = parse(original.get(p.matrix)), priorMatrix = structuredClone(matrix);
if (matrix.requirementCount !== 109 || matrix.rows?.length !== 109 || new Set(matrix.rows.map(r => r.id)).size !== 109 ||
    matrix.ownerAcceptedCriteria !== 0 || matrix.wholeWaveComplete !== false || matrix.rows.some(r => r.ownerAccepted !== false) ||
    matrix.ownerCriterionAcceptance) throw Error('LIVING_OWNER_STATE_CHANGED');
const projection = matrix.rows.map(identity);
const [owner, review, ready, source, candidate, mapping, statusBefore, statusAfter] = await Promise.all([
  json(ownerPath), json(p.review), json(p.readiness), json(p.source), json(p.candidate), json(p.mapping), json(p.statusBefore), json(p.statusAfter),
]);
if (statusAfter.status !== 'complete' || statusAfter.fullPublication !== true || statusAfter.publicationError !== null || statusAfter.cleanupErrors?.length !== 0 ||
    statusAfter.postVerificationErrors?.length !== 0 || statusAfter.originalProjectionPreserved !== true ||
    statusAfter.before?.path !== p.statusBefore || statusAfter.before.sha256 !== bound.get(p.statusBefore).sha256 ||
    statusAfter.ownerAcceptedCriteria !== 0 || statusAfter.approvedBaselineImagesChanged !== false ||
    statusBefore.review?.path !== p.review || statusBefore.review.sha256 !== bound.get(p.review).sha256 ||
    statusBefore.reviewSha256 !== review.reviewSha256 || statusBefore.candidateBundleSha256 !== candidate.bundleSha256) throw Error('FINAL_STATUS_PUBLICATION_REQUIRED');
// Readiness intentionally binds the historical matrix used to compose the packet.
// Resolve it from the immutable status checkpoint, never from changed living bytes.
for (const entry of statusBefore.originalLivingDocuments ?? []) {
  if (!living.includes(entry.path) || historical.has(entry.path) || typeof entry.utf8Base64 !== 'string') throw Error('HISTORICAL_DOCUMENT_SCOPE_CHANGED');
  const b = Buffer.from(entry.utf8Base64, 'base64');
  if (sha(b) !== entry.sha256 || b.length !== entry.bytes) throw Error('HISTORICAL_DOCUMENT_HASH_DRIFT');
  historical.set(entry.path, { bytes: b, sha256: entry.sha256 });
}
if (historical.size !== 3 || ready.sourceMatrix?.path !== p.matrix || ready.sourceMatrix.sha256 !== historical.get(p.matrix).sha256) throw Error('READINESS_SOURCE_MATRIX_UNBOUND');
for (const file of living) {
  const planned=statusBefore.plannedDocuments?.find(d=>d.path===file), observed=statusAfter.observedDocuments?.find(d=>d.path===file);
  if (!planned || !observed || observed.matchesPlanned!==true || observed.sha256!==planned.sha256 || sha(original.get(file))!==planned.sha256) throw Error('CURRENT_LIVING_DOCUMENT_NOT_FINAL_STATUS:'+file);
}
const historicalMatrix = parse(historical.get(p.matrix).bytes);
if (!eq(historicalMatrix.rows?.map(identity), projection) || !eq(ready.rows?.map(identity), projection) ||
    ready.ownerAcceptedCriteria !== 0 || ready.wholeWaveComplete !== false || ready.rows.some(r => r.ownerAccepted !== false || r.ownerDecision !== null) ||
    ready.wholeCriterionReadyForOwnerReviewCount !== 3 || !eq(ready.rows.filter(r => r.wholeCriterionReadyForOwnerReview === true).map(r => r.id).sort(), ids) ||
    !eq(review.proposedCriterionIds?.slice().sort(), ids)) throw Error('EXACT_THREE_COMPLETE_READINESS_REQUIRED');
const extra = new Set(['reviewSha256','html','imageCount','embeddedImages','allDecisionsInitiallyPending','actualOwnerDecisionsRecorded','ownerAcceptanceCount','reviewCore']);
const core = Object.fromEntries(Object.entries(review).filter(([key]) => !extra.has(key)));
if (!eq(core, review.reviewCore) || sha(JSON.stringify(core)) !== review.reviewSha256 ||
    review.imageCount !== 83 || review.embeddedImages !== 249 || review.allDecisionsInitiallyPending !== true ||
    review.actualOwnerDecisionsRecorded !== 0 || review.ownerAcceptanceCount !== 0 || !eq(review.readiness, ready) ||
    review.requirements?.length !== 109 || new Set(review.requirements.map(r => r.id)).size !== 109 ||
    !eq(review.requirements.map(r => [r.id,r.bundle,r.specification]), matrix.rows.map(r => [r.id,r.bundle,r.specification])) ||
    review.requirements.some(r => r.ownerAccepted !== false)) throw Error('FINAL_REVIEW_CORE_CHANGED');
const html = (await bind(review.html?.path, review.html?.sha256)).toString('utf8');
const embeddedMatch = html.match(/<script id="review-data" type="application\/json">([\s\S]*?)<\/script>/);
if (!embeddedMatch) throw Error('HTML_EMBEDDED_REVIEW_MISSING');
const embedded = JSON.parse(embeddedMatch[1]);
const embeddedCore = Object.fromEntries(Object.entries(embedded).filter(([key]) => !['reviewSha256','cases'].includes(key)));
if (!eq(embeddedCore, core) || embedded.reviewSha256 !== review.reviewSha256 ||
    !eq(embedded.cases?.map(({approved,candidate,diff,...metadata}) => metadata), review.images)) throw Error('HTML_REVIEW_METADATA_DRIFT');
if (review.candidateBundleSha256 !== candidate.bundleSha256 || sha(JSON.stringify(candidate.bundle)) !== candidate.bundleSha256 ||
    !eq(candidate.sourceManifest, candidate.bundle.sourceManifest) || !eq(candidate.control, candidate.bundle.control) ||
    candidate.sourceManifest.path !== p.source || candidate.sourceManifest.sha256 !== bound.get(p.source).sha256 ||
    candidate.control.path !== p.control || !eq(review.images, candidate.cases) || candidate.cases.length !== 83 ||
    new Set(candidate.cases.map(c => c.stem)).size !== 83 || new Set(candidate.cases.map(c => c.approvedPath)).size !== 83 ||
    candidate.comparatorChanged !== false || candidate.fixturePermissionsChanged !== false ||
    candidate.approvedRepositoryImagesChanged !== false || candidate.ownerAccepted !== false) throw Error('CANDIDATE_SCOPE_CHANGED');
if (!eq(candidate.cases.map(({stem,approvedPath,approvedSha256,candidateSha256}) => ({stem,approvedPath,approvedSha256,candidateSha256})), candidate.bundle.cases) ||
    source.selectedSourceCount !== 1068 || Object.keys(source.sourceHashes ?? {}).length !== 1068 || source.sourceStable !== true) throw Error('EXACT1068_SOURCE_OR_IMAGE_PROJECTION_CHANGED');
for (const c of candidate.cases) {
  if (!/^apps\/jentra_desktop\/test\/goldens\/[A-Za-z0-9_-]+\.png$/.test(c.approvedPath) || source.sourceHashes[c.approvedPath] !== c.approvedSha256 || c.ownerAccepted !== false) throw Error('APPROVED_IMAGE_SCOPE_CHANGED');
  for (const [file,h] of [[c.approvedPath,c.approvedSha256],[c.approvedBackup,c.approvedSha256],[c.candidatePath,c.candidateSha256],[c.diffPath,c.diffSha256]]) await bind(file,h);
  const shown = embedded.cases.find(e => e.stem === c.stem);
  for (const [key,h] of [['approved',c.approvedSha256],['candidate',c.candidateSha256],['diff',c.diffSha256]]) {
    if (!shown[key]?.startsWith('data:image/png;base64,') || sha(Buffer.from(shown[key].slice(22),'base64')) !== h) throw Error('EMBEDDED_IMAGE_BINDING_DRIFT');
  }
}
// Bind readiness evidence to exact original bytes. Only known historical living
// inputs resolve through the immutable checkpoint; all other files stay current.
for (const b of [...review.refs, ...(ready.inputBindings ?? []), ...ready.rows.flatMap(r => r.evidence ?? [])]) {
  const old = historical.get(b.path);
  if (old && old.sha256 === b.sha256) continue;
  await bind(b.path,b.sha256);
}
for (const r of matrix.rows) {
  const lines = (await bind(r.specification)).toString('utf8').split(/\r?\n/), words = [];
  for (let i=r.specificationLine-1;i<lines.length;i++) {
    const line=lines[i];
    if (i>r.specificationLine-1 && (!line.trim() || /^(?:- |###? )?(?:FR|NFR|AC|EC)-\d+:/.test(line) || /^## /.test(line))) break;
    words.push(line.replace(/^(?:- |### )/,'').trim());
  }
  const statement=words.join(' '), readinessRow=ready.rows.find(x=>x.id===r.id), reviewRow=review.requirements.find(x=>x.id===r.id);
  if (!words[0]?.startsWith(r.id+':') || readinessRow.fullCriterionStatement!==statement || reviewRow.statement!==statement) throw Error('FULL_CRITERION_WORDING_DRIFT:'+r.id);
}
for (const id of ids) {
  const mapped=mapping.rows.find(r=>r.id===id), row=ready.rows.find(r=>r.id===id);
  if (!mapped || mapped.completeStatementMapping!==true || mapped.ownerAccepted!==false || mapped.fullStatement!==row.fullCriterionStatement) throw Error('COMPLETE_STATEMENT_MAPPING_REQUIRED:'+id);
  for (const b of mapped.sourceBindings) {
    if (source.sourceHashes[b.path]!==b.sha256) throw Error('MAPPED_SOURCE_NOT_IN_FROZEN_INPUTS');
    await bind(b.path,b.sha256);
  }
}
const expectedCopy={...source.sourceHashes};
for (const c of candidate.cases) expectedCopy[c.approvedPath]=c.candidateSha256;
function checkAudit(a, overlays=true) {
  if (!a || a.selectedSources!==1068 || a.snapshotMatchesDeclaredInputs!==true || a.currentWorkspaceMatchesFrozenBase!==true ||
      a.sourceManifest?.path!==p.source || a.sourceManifest.sha256!==bound.get(p.source).sha256 ||
      a.currentInputsSha256!==sha(JSON.stringify(source.sourceHashes)) || a.snapshotInputsSha256!==sha(JSON.stringify(overlays?expectedCopy:source.sourceHashes)) ||
      (overlays && (a.candidateManifest?.path!==p.candidate || a.candidateManifest.sha256!==bound.get(p.candidate).sha256 || a.candidateManifest.bundleSha256!==candidate.bundleSha256)) ||
      (!overlays && a.candidateManifest!==null) || a.overlays?.length!==(overlays?83:0) || new Set(a.overlays.map(o=>o.path)).size!==(overlays?83:0) ||
      a.overlays.some(o=>source.sourceHashes[o.path]!==o.baseSha256 || expectedCopy[o.path]!==o.candidateSha256)) throw Error('EXACT_SOURCE_AUDIT_NOT_GREEN');
}
async function stage(file,name,counts) {
  const s=await json(file), log=(await bind(s.log,s.logSha256)).toString('utf8');
  if (s.stage!==name || s.exitCode!==0 || s.integrityError!==null || !s.startedAt || !s.finishedAt ||
      !(Date.parse(s.startedAt)<=Date.parse(s.finishedAt)) || Date.parse(s.startedAt)<Date.parse(source.capturedAt)) throw Error('FRESH_STAGE_REQUIRED:'+name);
  checkAudit(s.inputAuditBefore);checkAudit(s.inputAuditAfter);
  if (!eq(s.inputAuditBefore.toolchain,s.inputAuditAfter.toolchain)) throw Error('STAGE_TOOLCHAIN_DRIFT');
  for (const b of [s.runner,s.inputAuditor]) await bind(b.path,b.sha256);
  if (counts) {
    const actual=parseTestLog(log);
    if (!eq(s.counts,counts) || !actual?.allTestsPassed || actual.passedTests!==counts.passed || actual.failedTests!==0 || actual.skippedTests!==0) throw Error('ACTUAL_STAGE_COUNTS_CHANGED:'+name);
  }
  return {s,log};
}
const domain=await stage(p.domain,'processDomain',{passed:27,failed:0,skipped:0});
const analysis=await stage(p.analysis,'analyzer');
const candidateStage=await stage(p.candidateStage,'candidateGoldens',{passed:83,failed:0,skipped:0});
const build=await stage(p.build,'build');
const targets=['apps/jentra_desktop/lib','apps/jentra_desktop/test','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'];
if (!eq(analysis.s.args,['analyze',...targets]) || analysis.s.workingDirectory!==source.snapshot || !/^\s*No issues found!\s*$/m.test(analysis.log) ||
    domain.s.workingDirectory!==path.join(source.snapshot,'packages/jentra_domain') || !domain.s.args.includes('test/analytics/process_metrics_test.dart') ||
    !domain.s.args.includes('test/analytics/process_filter_contract_test.dart') || !build.s.args.includes('--target=lib/main.dart') ||
    !build.s.args.includes('--dart-define=JENTRA_ENVIRONMENT=preview') || !/Built build[\\/]windows[\\/]x64[\\/]runner[\\/]Release[\\/].+\.exe/i.test(build.log)) throw Error('ANALYSIS_DOMAIN_BUILD_SCOPE_CHANGED');
const executions=[...domain.log.replace(/\r/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)].map(m=>({file:m[1].replaceAll('\\','/'),name:m[2]}));
for (const [file,count] of [['test/analytics/process_metrics_test.dart',25],['test/analytics/process_filter_contract_test.dart',2]]) {
  const content=await bind('packages/jentra_domain/'+file), names=[...content.toString('utf8').matchAll(/\btest\(\s*'([^']+)'/g)].map(m=>m[1]);
  if (names.length!==count || new Set(names).size!==count || names.some(n=>executions.filter(e=>e.file.endsWith(file)&&e.name===n).length!==1)) throw Error('EXACT27_DOMAIN_EXECUTIONS_REQUIRED');
}
const normalize=n=>n.replaceAll('\\','/').slice(n.replaceAll('\\','/').indexOf('/test/')+6);
const candidateIdentities=candidate.cases.map(c=>c.test).sort();
const candidateExecutions=[...candidateStage.log.replace(/\r/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)]
  .filter(m=>!m[2].startsWith('(')&&!m[2].endsWith('[E]')).map(m=>normalize(m[1]+': '+m[2])).sort();
if (!eq(candidateStage.s.expectedCaseIdentities,candidateIdentities) || !eq(candidateExecutions,candidateIdentities) ||
    review.run?.path!==p.candidateStage || review.run.sha256!==bound.get(p.candidateStage).sha256) throw Error('EXACT83_CANDIDATE_EXECUTIONS_REQUIRED');
const control=await json(p.control), comparison=await json(p.comparison), controlLog=(await bind(control.log,control.logSha256)).toString('utf8'), parsed=parseTestLog(controlLog);
await bind(p.control,candidate.control.sha256);
const pairs=rows=>rows.map(r=>normalize(r.name)+'|'+r.golden).sort();
if (control.stage!=='controlAll' || control.exitCode!==1 || control.integrityError!==null || !eq(control.counts,{passed:1921,failed:83,skipped:0}) ||
    parsed?.passedTests!==1921 || parsed.failedTests!==83 || parsed.skippedTests!==0 || parsed.failures.some(f=>f.kind!=='golden-comparison') ||
    !eq(pairs(parsed.failures),pairs(comparison.cases))) throw Error('FULL_APPROVED_CONTROL_BINDING_CHANGED');
checkAudit(control.inputAuditBefore,false);checkAudit(control.inputAuditAfter,false);
if (!eq(control.inputAuditBefore.toolchain,control.inputAuditAfter.toolchain) || !control.startedAt || !control.finishedAt ||
    !(Date.parse(control.startedAt)<=Date.parse(control.finishedAt)) || Date.parse(control.startedAt)<Date.parse(source.capturedAt)) throw Error('FULL_CONTROL_TIME_OR_TOOLCHAIN_DRIFT');
for (const b of [control.runner,control.inputAuditor]) await bind(b.path,b.sha256);
const falseGates=['actualModelUsage','realMfa','actualWorkerDelivery','authenticatedNativeAcceptance','independentSessionContention','targetScaleLoad','nativeKeyboardVerified','ownerSignoff','newRuntimeInstallationComplete'];
for (const key of falseGates) if (matrix[key]!==false) throw Error('SEPARATE_GATE_CHANGED:'+key);
if (matrix.runtimeReview?.ownerApproved!==false || matrix.runtimeReview.newInstalled!==false ||
    matrix.goldenOwnerReview?.reviewSha256!==review.reviewSha256 || matrix.goldenOwnerReview.candidateBundleSha256!==candidate.bundleSha256 ||
    matrix.goldenOwnerReview.ownerAcceptedCriteria!==0) throw Error('CURRENT_MATRIX_REVIEW_BINDING_CHANGED');
for (const b of statusAfter.validatedInputs ?? []) {
  const old=historical.get(b.path);
  if (old && old.sha256===b.sha256) continue;
  await bind(b.path,b.sha256);
}
checkAudit(statusAfter.finalSourceAndToolAudit);
for (const row of ready.rows) if (row.currentCriterionEvidence) {
  for (const b of [row.currentCriterionEvidence.domainStage,row.currentCriterionEvidence.analysisStage,row.currentCriterionEvidence.sourceManifest]) await bind(b.path,b.sha256);
}
// Reject every browser draft. Human provenance is an external caller obligation;
// explicit per-ID quotes and exact packet hashes make its audit record reviewable.
if (owner.kind!=='direct-human-owner-decision' || owner.authorizationKind!=='direct-human-message' || owner.submittedByOwner!==true ||
    typeof owner.messageVerbatim!=='string' || !owner.messageVerbatim.trim() || owner.messageSha256!==sha(Buffer.from(owner.messageVerbatim,'utf8')) ||
    owner.sourceMessage?.role!=='user' || typeof owner.sourceMessage.messageId!=='string' || !owner.sourceMessage.messageId.trim() ||
    typeof owner.sourceMessage.threadId!=='string' || !owner.sourceMessage.threadId.trim() || !Number.isFinite(Date.parse(owner.sourceMessage.receivedAt)) ||
    Date.parse(owner.sourceMessage.receivedAt)<Date.parse(review.generatedAt) || Date.parse(owner.sourceMessage.receivedAt)>Date.now()+300000 || owner.reviewSha256!==review.reviewSha256 ||
    owner.candidateBundleSha256!==candidate.bundleSha256 || owner.criteria?.length!==3 || !eq(owner.criteria.map(r=>r.id).sort(),ids)) throw Error('TRUSTED_DIRECT_HUMAN_DECISION_REQUIRED');
for (const decision of owner.criteria) {
  const row=ready.rows.find(r=>r.id===decision.id), quote=decision.decisionQuote;
  if (decision.decision!=='accept-complete-criterion' || decision.fullCriterionStatement!==row.fullCriterionStatement ||
      typeof quote!=='string' || !quote.trim() || !owner.messageVerbatim.includes(quote) || !quote.includes(decision.id) ||
      !/\b(?:accept|approve|accepted|approved)\b/i.test(quote) || /\b(?:not|never|reject|decline|defer|except|unless|if|partial|only part|do not|don't)\b/i.test(quote)) throw Error('EXPLICIT_COMPLETE_CRITERION_DECISION_REQUIRED:'+decision.id);
}
await bind('scripts/wave5/record_owner_acceptance_20261010_r2.mjs');
// Add exact raw source files as well as the aggregate audit. Each publication
// rechecks every bound file and both complete 1068-input maps.
for (const [file,h] of Object.entries(source.sourceHashes)) await bind(file,h);
const now=new Date().toISOString(), ownerBinding=bound.get(ownerPath);
for (const id of ids) {
  const row=matrix.rows.find(r=>r.id===id);
  row.ownerAccepted=true;
  row.remaining=`None for the complete ${id} pure calculation criterion accepted by the owner. Installed source authority, producer certification, authenticated native/MFA, delivery, contention/load and whole-system signoff remain separate unaccepted criteria.`;
}
matrix.updatedAt=now;matrix.ownerAcceptedCriteria=3;
matrix.goldenOwnerReview.ownerAcceptedCriteria=3;
matrix.ownerCriterionAcceptance={recordedAt:now,ownerDecision:ownerBinding,review:{path:p.review,sha256:bound.get(p.review).sha256,reviewSha256:review.reviewSha256},
  candidateBundleSha256:candidate.bundleSha256,criterionIds:ids,completeStatements:owner.criteria.map(r=>({id:r.id,fullCriterionStatement:r.fullCriterionStatement,decisionQuote:r.decisionQuote})),
  scope:'Exactly three complete pure-calculation criteria. No baseline, runtime, native, delivery, load, production, billing or whole-system acceptance.'};
// Verify the entire planned JSON delta, not only a projection of unchanged IDs.
const expected=structuredClone(priorMatrix);
expected.updatedAt=now;expected.ownerAcceptedCriteria=3;expected.goldenOwnerReview.ownerAcceptedCriteria=3;expected.ownerCriterionAcceptance=matrix.ownerCriterionAcceptance;
for (const id of ids) { const r=expected.rows.find(r=>r.id===id);r.ownerAccepted=true;r.remaining=matrix.rows.find(x=>x.id===id).remaining; }
if (!eq(matrix,expected) || !eq(matrix.rows.map(identity),projection) || matrix.rows.filter(r=>r.ownerAccepted).length!==3 ||
    matrix.wholeWaveComplete!==false || falseGates.some(k=>matrix[k]!==false)) throw Error('PLANNED_ACCEPTANCE_DELTA_ESCAPES');
const link=(from,label,target)=>`[${label}](<${path.posix.relative(path.posix.dirname(from),target)}>)`;
const summary=from=>`The owner explicitly accepted **3 of 109 complete criteria: AC-551, AC-552 and AC-553** against the ${link(from,'exact final review',p.review)} and ${link(from,'direct human decision record',ownerPath)}. **106 criteria remain unaccepted; Jentra OS and Wave 5 remain incomplete.** Image choices, runtime approval, genuine MFA, authenticated native/keyboard checks, actual delivery/model usage, contention/load and whole-system signoff remain separate gates.`;
let md=original.get(p.markdown).toString('utf8');
const marker='All 109 approved requirement identifiers and specification mappings are preserved. Zero IDs are owner-accepted; Jentra OS and Wave 5 remain incomplete.';
if (md.split(marker).length!==2) throw Error('MATRIX_CURRENT_COUNT_MARKER_CHANGED');
md=md.replace(marker,'All 109 approved requirement identifiers and specification mappings are preserved. Three complete pure calculation criteria are owner-accepted; 106 remain unaccepted. Jentra OS and Wave 5 remain incomplete.');
md=md.replace(/\*\*zero of 109 criteria are owner-accepted\*\*/g,'**3 of 109 criteria are owner-accepted (AC-551, AC-552 and AC-553)**');
const tableBefore=md.split(/\r?\n/).filter(l=>/^\| (?:FR|NFR|AC|EC)-\d+ \|/.test(l));
const lines=md.split(/\r?\n/);
for (const id of ids) {
  const indexes=lines.map((line,index)=>line.startsWith(`| ${id} |`)?index:-1).filter(index=>index>=0);
  if (indexes.length!==1) throw Error('EXACT_CRITERION_TABLE_ROW_REQUIRED:'+id);
  const index=indexes[0], parts=lines[index].split(' | ');
  if (parts.length!==3 || !parts[2].endsWith(' |')) throw Error('CRITERION_TABLE_LAYOUT_CHANGED:'+id);
  lines[index]=`${parts[0]} | ${parts[1]} | ${parts[2].slice(0,-2)} Owner accepted the complete pure calculation criterion; no dependent runtime/native acceptance is inferred. |`;
}
md=lines.join('\n');
const tableAfter=md.split(/\r?\n/).filter(l=>/^\| (?:FR|NFR|AC|EC)-\d+ \|/.test(l));
if (tableBefore.length!==109 || tableAfter.length!==109 || !eq(tableAfter.filter((l,i)=>l!==tableBefore[i]).map(l=>l.split(' | ')[0].slice(2)),ids)) throw Error('ONLY_THREE_TABLE_CELLS_MAY_CHANGE');
md+='\n## October 10 explicit criterion acceptance\n\n'+summary(p.markdown)+'\n\nThe preceding review and readiness records are immutable pre-decision evidence. Their zero-acceptance statements describe that earlier checkpoint. All other row content and evidence links are preserved.\n';
let status=original.get(p.status).toString('utf8');
if (!status.startsWith('# Wave 5 development status') || status.includes('## October 10 explicit criterion acceptance')) throw Error('STATUS_LAYOUT_OR_DUPLICATE_ACCEPTANCE');
status=status.replace(/\*\*zero of 109 criteria are owner-accepted\*\*/g,'**3 of 109 criteria are owner-accepted (AC-551, AC-552 and AC-553)**');
status=status.replace('all 109 owner decisions','the remaining 106 owner decisions');
const firstParagraphEnd=status.indexOf('\n\n',status.indexOf('\n\n')+2);
if (firstParagraphEnd<0) throw Error('STATUS_INTRODUCTION_MISSING');
status=status.slice(0,firstParagraphEnd)+'\n\n'+summary(p.status)+status.slice(firstParagraphEnd);
status+='\n## October 10 explicit criterion acceptance\n\n'+summary(p.status)+'\n\nEarlier review/status prose is preserved as pre-decision history. No approved PNG was promoted and no whole-system or runtime acceptance was recorded by this action.\n';
const outputs=new Map([[p.matrix,Buffer.from(JSON.stringify(matrix,null,2)+'\n')],[p.markdown,Buffer.from(md)],[p.status,Buffer.from(status)]]);
async function recheck(claimedFile=null) {
  for (const [file,h] of expectedLiving) if (file!==claimedFile && sha(await bytes(file))!==h) throw Error('CONCURRENT_LIVING_CHANGE:'+file);
  for (const b of bound.values()) if (!living.includes(b.path) && sha(await bytes(b.path))!==b.sha256) throw Error('CONCURRENT_BOUND_CHANGE:'+b.path);
  const audit=await auditGoldenInputs('processDomain');checkAudit(audit);
  for (const s of [domain.s,analysis.s,candidateStage.s,build.s]) if (!eq(audit.toolchain,s.inputAuditAfter.toolchain)) throw Error('CURRENT_TOOLCHAIN_CHANGED');
  return audit;
}
const audit=await recheck();
const before={preparedAt:now,kind:'explicit-three-criterion-acceptance-before',ownerDecision:ownerBinding,reviewSha256:review.reviewSha256,candidateBundleSha256:candidate.bundleSha256,
  criterionIds:ids,originalOwnerAcceptedCriteria:0,plannedOwnerAcceptedCriteria:3,originalLivingDocuments:[...original].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length,utf8Base64:b.toString('base64')})),
  plannedDocuments:[...outputs].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length})),boundInputs:[...bound.values()],historicalMatrix:ready.sourceMatrix,currentSourceAudit:audit,
  boundary:'Direct human acceptance of exactly three complete calculation criteria. No store, PNG, source, installed/runtime/native/delivery/load/production/billing change.'};
if (!publish) {
  console.log(JSON.stringify({write:false,ownerDecision:ownerBinding,reviewSha256:review.reviewSha256,criterionIds:ids,ownerAcceptedCriteriaBefore:0,ownerAcceptedCriteriaAfter:3,
    remainingUnacceptedCriteria:106,documents:before.plannedDocuments,immutableBefore:p.before,immutableAfter:p.after,currentSourceVerified:true,outputsWritten:false},null,2));
} else {
  for (const file of [p.before,p.after]) { try { await access(inside(file));throw Error('IMMUTABLE_RESULT_EXISTS:'+file); } catch(e) { if(e.code!=='ENOENT')throw e; } }
  await recheck();
  const recoveryDirectory=base+'owner-criterion-acceptance-recovery-20261010-r2-'+randomUUID();
  const states=[...outputs].map(([file,b])=>({path:file,target:inside(file),bytes:b,originalSha256:sha(original.get(file)),plannedSha256:sha(b),
    recoveryPath:recoveryDirectory+'/'+path.basename(file),recovery:inside(recoveryDirectory+'/'+path.basename(file)),temp:null,claimed:false,published:false,claimedSha256:null}));
  before.recoveryDirectory=recoveryDirectory;
  before.publicationPlans=states.map(({bytes,target,recovery,temp,...state})=>state);
  const beforeBytes=Buffer.from(JSON.stringify(before,null,2)+'\n');
  await writeFile(inside(p.before),beforeBytes,{flag:'wx'});
  // Reserve an owned result handle before any living file is claimed, so a
  // concurrent result file cannot prevent recording a partial publication.
  const resultHandle=await open(inside(p.after),'wx');
  await resultHandle.writeFile(JSON.stringify({kind:'explicit-three-criterion-acceptance-pending',before:{path:p.before,sha256:sha(beforeBytes)},
    fullPublication:false,recoveryDirectory,boundary:'Reserved before publication; an interrupted attempt has no complete acceptance claim.'},null,2)+'\n');
  const changed=[],cleanupErrors=[],postVerificationErrors=[];let publicationError=null,finalAudit=null;
  try {
    await mkdir(inside(recoveryDirectory));
    for (const state of states) {
      await recheck();
      state.temp=inside(state.path+'.'+randomUUID()+'.tmp');
      const temporary=await open(state.temp,'wx');state.tempOwned=true;
      try { await temporary.writeFile(state.bytes); } finally { await temporary.close(); }
      await recheck();
      // Claim the actual existing bytes into the owned recovery directory.
      // If they changed after the precheck, retain them and stop; never overwrite.
      await rename(state.target,state.recovery);state.claimed=true;
      state.claimedSha256=sha(await readFile(state.recovery));
      if (state.claimedSha256!==state.originalSha256) throw Error('CONCURRENT_CLAIMED_DOCUMENT_CHANGE:'+state.path);
      await recheck(state.path);
      if (sha(await readFile(state.recovery))!==state.originalSha256 || sha(await readFile(state.temp))!==state.plannedSha256) throw Error('OWNED_PUBLICATION_BYTES_CHANGED');
      // A new concurrent destination makes this fail without replacing it.
      await copyFile(state.temp,state.target,constants.COPYFILE_EXCL);
      state.published=true;expectedLiving.set(state.path,state.plannedSha256);changed.push(state.path);
      await recheck();
    }
    await recheck();
  } catch(e) { publicationError={message:e.message,code:e.code??null}; }
  for (const state of states.filter(s=>s.tempOwned)) try { await unlink(state.temp); } catch(e) { if(e.code!=='ENOENT')cleanupErrors.push({path:path.relative(root,state.temp),message:e.message,code:e.code??null}); }
  const observed=[];
  for (const file of living) try { const b=await bytes(file);observed.push({path:file,sha256:sha(b),matchesPlanned:sha(b)===sha(outputs.get(file))}); } catch(e) { observed.push({path:file,error:e.message}); }
  const recoveries=[];
  for (const state of states.filter(s=>s.claimed)) try {
    const actual=sha(await readFile(state.recovery));recoveries.push({path:state.recoveryPath,originalPath:state.path,sha256:actual,originalSha256:state.originalSha256,
      claimedSha256:state.claimedSha256,matchesOriginal:actual===state.originalSha256,published:state.published});
  } catch(e) { recoveries.push({path:state.recoveryPath,error:e.message}); }
  let observedOwnerAcceptedCriteria=null,observedOwnerAcceptedIds=null;
  try { const actual=parse(await bytes(p.matrix));observedOwnerAcceptedCriteria=actual.ownerAcceptedCriteria;observedOwnerAcceptedIds=actual.rows.filter(r=>r.ownerAccepted===true).map(r=>r.id); } catch {}
  try { finalAudit=await recheck(); } catch(e) {
    postVerificationErrors.push({gate:'finalLivingSourceBoundAndToolAudit',message:e.message,code:e.code??null});
    publicationError??={message:e.message,code:e.code??null};
  }
  if (observed.some(o=>o.matchesPlanned!==true) || observedOwnerAcceptedCriteria!==3 || !eq(observedOwnerAcceptedIds?.slice().sort(),ids)) {
    postVerificationErrors.push({gate:'actualDestinationHashesAndCriterionCount',message:'ACTUAL_ACCEPTANCE_DESTINATION_DRIFT'});
    publicationError??={message:'ACTUAL_ACCEPTANCE_DESTINATION_DRIFT',code:null};
  }
  if (recoveries.length!==states.filter(s=>s.claimed).length || recoveries.some(r=>r.matchesOriginal!==true||r.sha256!==r.claimedSha256)) {
    postVerificationErrors.push({gate:'actualRetainedRecoveryHashes',message:'ACTUAL_ACCEPTANCE_RECOVERY_DRIFT'});
    publicationError??={message:'ACTUAL_ACCEPTANCE_RECOVERY_DRIFT',code:null};
  }
  if (cleanupErrors.length) publicationError??={message:'OWNED_TEMP_CLEANUP_FAILED',code:null};
  const fullPublication=changed.length===3 && publicationError===null && cleanupErrors.length===0 && postVerificationErrors.length===0 && finalAudit!==null;
  const after={finishedAt:new Date().toISOString(),kind:'explicit-three-criterion-acceptance-result',before:{path:p.before,sha256:sha(beforeBytes)},ownerDecision:ownerBinding,
    criterionIds:ids,plannedOwnerAcceptedCriteria:3,fullPublication,changedDocuments:changed,remainingDocuments:living.filter(file=>!changed.includes(file)),observedDocuments:observed,publicationError,cleanupErrors,
    status:fullPublication?'complete':'failed',postVerificationErrors,finalSourceAndToolAudit:finalAudit,
    observedOwnerAcceptedCriteria,observedOwnerAcceptedIds,recoveryDirectory,retainedRecoveries:recoveries,
    claimedWithoutPublication:states.filter(s=>s.claimed&&!s.published).map(s=>({path:s.path,recoveryPath:s.recoveryPath,claimedSha256:s.claimedSha256})),
    exactCriterionProjectionPreserved:eq(matrix.rows.map(identity),projection),other106RowsUnchanged:matrix.rows.filter(r=>!ids.includes(r.id)).every(r=>eq(r,priorMatrix.rows.find(x=>x.id===r.id))),
    separateGatesUnchanged:falseGates.every(key=>matrix[key]===priorMatrix[key]),approvedBaselinesChanged:false,sourceEdits:0,acceptanceStoresTouched:false,
    boundary:'Partial publication errors are retained without rollback or overwriting concurrent edits. Counts are planned unless fullPublication is true; inspect observed matrix bytes before claiming recorded acceptance.'};
  try { await resultHandle.truncate(0);await resultHandle.write(JSON.stringify(after,null,2)+'\n',0,'utf8'); } finally { await resultHandle.close(); }
  console.log(JSON.stringify(after,null,2));
  if (!fullPublication) process.exitCode=1;
}
