import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sources } from './cash_ui_evidence.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const reportPath = 'docs/verification/wave5/cash-ui-verification-20261008.json';
const reportMd = 'docs/verification/wave5/cash-ui-verification-20261008.md';
const read = (p) => readFile(path.join(root, p), 'utf8');
const readJson = async (p) => JSON.parse(await read(p));
const write = (p, text) => writeFile(path.join(root, p), `${text.trimEnd()}\n`);
const writeJson = (p, value) => write(p, JSON.stringify(value, null, 2));
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');

export async function updateCashUiStatus({ allowStale = false } = {}) {
  let report;
  try { report = await readJson(reportPath); } catch (e) {
    if (allowStale && e.code === 'ENOENT') return false;
    throw e;
  }
  const current = await sources(root);
  if (!report.current_source_match || JSON.stringify(current) !== JSON.stringify(report.sourceHashes)) {
    if (allowStale) return false;
    throw new Error('Current source no longer matches the cash verification report');
  }
  if (!report.buildSucceeded || report.frames.length !== 36 || !report.visualReview.passed || report.authenticatedAcceptance || report.ownerAccepted) {
    throw new Error('Cash development verification gates are inconsistent');
  }
  for (const stage of Object.values(report.stages)) {
    if (!stage.passed || stage.exitCode !== 0 || sha(await readFile(path.join(root, stage.log))) !== stage.logSha256) throw new Error('Verification log changed or a stage failed');
  }
  for (const frame of report.frames) {
    if (sha(await readFile(path.join(root, frame.path))) !== frame.sha256) throw new Error('Rendered frame changed');
  }
  const domain = report.stages.domainTests.assertions;
  const platform = report.stages.platformTests.assertions;
  const native = report.stages.nativeTests.assertions;
  const now = new Date().toISOString();
  const description = `Current-source Dart analysis is clean; ${domain} domain, ${platform} platform and ${native} desktop/controller/render tests pass. Windows release compilation matches all ${report.sourceFileCount.toLocaleString('en-US')} selected source files and ${report.releaseFileCount} release files. Twelve cash render variants cover 1024x720, 1440x900 and 1920x1080, both themes/densities and 200% text, with 36 fresh top/provider/lower frames. These are development tests and fixture renders; authenticated native acceptance is still open.`;

  const matrixPath = 'docs/verification/wave5/requirement-matrix-20261008.json';
  const matrixMdPath = 'docs/verification/wave5/requirement-matrix-20261008.md';
  const matrix = await readJson(matrixPath);
  const matrixText = await read(matrixMdPath);
  const titles = Object.fromEntries([...matrixText.matchAll(/<a id="evidence-([^"]+)"><\/a>\s*## ([^\n]+)/g)].map((m) => [m[1], m[2].trim()]));
  if (matrix.rows.length !== 109 || matrix.rows.some((r) => r.ownerAccepted)) throw new Error('Requirement or owner-acceptance identity changed');
  for (const row of matrix.rows) {
    if (row.bundle === 'cash') {
      row.developmentStatus = 'Uninstalled candidates cover dated bank cash and permission-gated residual AR/AP with allocation/reversal evidence, immutable assumptions/overrides, encrypted recovery and governed export metadata/reopen. Current cash analysis, adapter/controller tests, Windows compilation and fixture renders pass. Payroll and project-reimbursement payment dates remain unavailable.';
      row.remaining = 'Full cash forecasting remains incomplete because payroll and approved project-reimbursement sources lack authoritative payment due dates. Candidates remain uninstalled. Real authenticated scenario/export creation, downloaded bytes/reopen, native restart and revocation still require evidence.';
    }
    if (row.bundle === 'native') {
      row.developmentStatus = `Seven analytics workspaces are implemented; ${native} current-source desktop/controller/render tests pass. Cash has twelve fresh font-loaded variants at the three prescribed viewports, both themes/densities and 200% text. The Windows release build matches current source.`;
      row.remaining = 'Real authenticated native launch, restart, delayed revocation, export creation/download/reopen, complete keyboard navigation and owner review remain open. The 13 shared dashboard/setup golden failures remain investigated but unresolved.';
    }
    if (row.bundle === 'quality') {
      row.developmentStatus = `Strict candidate SQL passes 116 rollback assertions; current Dart analysis is clean and ${domain} domain/${platform} platform/${native} desktop tests pass. Fresh cash frames were inspected and the Windows release build matches current source. The prior 31 controlled worker checks retain their original scope.`;
      row.remaining = 'Keep the 13 shared golden failures visible; no approved golden was regenerated. Authenticated runtime, actual worker/model delivery, export/model/log privacy verification, independent-session contention, target-scale load and owner signoff remain open.';
    }
    if (['cash', 'native', 'quality'].includes(row.bundle)) {
      for (const evidence of [reportMd, reportPath]) if (!row.evidence.includes(evidence)) row.evidence.push(evidence);
    }
  }
  matrix.updatedAt = now;
  matrix.continuationChecks = {
    ...matrix.continuationChecks, domainLastVerified: domain, platformLastVerified: platform, nativeLastVerified: native,
    platformAndNativeCurrentSource: true, analyzerCurrentSource: true, windowsBuildCurrentSourceMatch: true,
    currentCashRenderAvailable: true, cashUiVerification: reportPath,
    analyzerScope: report.stages.analyzer.command,
    testScope: 'Wave 5 test/analytics packages and process_metric_workspace/wave5_workspaces/wave5_continuation desktop suites',
  };
  matrix.wholeWaveComplete = false;
  matrix.ownerAcceptedCriteria = 0;
  await writeJson(matrixPath, matrix);
  const lines = [
    '# Wave 5 requirement matrix - October 8, 2026', '',
    'All 109 approved identifiers remain mapped, with zero owner-accepted criteria. The last connected refresh confirms 43 installed migrations and 107 API functions; the eight review migrations and candidate cash table remain absent. The original installation report holds 126 installed SQL checks. The separate candidate composition passes 116 strict rollback checks and remains uninstalled under the owner decision. [Live refresh](live-refresh-confirmed-20261008.json) and [candidate review](continuation-review-20261008.md).', '',
    `${description} [Cash verification](cash-ui-verification-20261008.md). Actual worker delivery, contention, target-scale load and owner signoff remain open; full cash provider coverage remains incomplete.`, '',
    '| ID | Evidence bundle | Current status |', '|---|---|---|',
  ];
  for (const row of matrix.rows) lines.push(`| ${row.id} | [${titles[row.bundle]}](#evidence-${row.bundle}) | ${row.developmentStatus} |`);
  for (const bundle of Object.keys(titles)) {
    const rows = matrix.rows.filter((r) => r.bundle === bundle);
    lines.push('', `<a id="evidence-${bundle}"></a>`, `## ${titles[bundle]}`, '', rows[0].developmentStatus, '', `Remaining: ${rows[0].remaining}`, '', 'Evidence:', '');
    for (const file of [...new Set(rows.flatMap((r) => r.evidence))]) lines.push(`- [${file}](${path.posix.relative('docs/verification/wave5', file)})`);
  }
  await write(matrixMdPath, lines.join('\n'));

  const statusPath = 'docs/development/wave5-status.md';
  let status = (await read(statusPath)).replace(/\r\n/g, '\n');
  status = status.replace('Post-edit Flutter analysis/tests/render/build, 13 shared golden failures,', '13 shared golden failures,');
  status = status.replace('The cash UI/gateway changed after the latest Flutter checks. Earlier domain 71 and worker 31 checks remain in scope; platform 41/native 90 counts, analyzer, rendered frames and Windows build are historical for the previous source and must be rerun before current-source claims.', `${description} The 31 controlled worker checks retain their prior scope. [Current cash verification](../verification/wave5/cash-ui-verification-20261008.md).`);
  if (!status.includes('cash-ui-verification-20261008.md')) throw new Error('Expected cash freshness paragraph absent');
  await write(statusPath, status);

  const reviewMdPath = 'docs/verification/wave5/continuation-review-20261008.md';
  let review = (await read(reviewMdPath)).replace(/\r\n/g, '\n');
  review = review.replace('- Native workspaces exist, but the latest cash-screen and gateway edits postdate the previous platform/native tests, analyzer, font-loaded frames and Windows build. Those results are historical for the prior source and do not verify this cash change. Current-source Flutter verification and a fresh cash-workspace render are pending; the last Windows executable no longer matches current source.', `- ${description} [Current cash verification](cash-ui-verification-20261008.md).`);
  review = review.replace('- The last domain and worker runs passed 71 and 31 checks; domain and worker sources were unchanged by the latest cash edit. The prior 41 platform and 90 native checks, analyzer and source-attributed build predate the edit and are stale for current Dart source. Flutter rechecks were not run after automatic approval review failed due to the usage limit. The 13 shared dashboard/setup golden failures have a separate investigation; no approved golden was changed.', `- The current SDK rerun passed ${domain} domain/${platform} platform/${native} desktop checks, clean scoped analysis, source-matched Windows compilation and inspected fresh cash frames. The prior 31 controlled worker checks retain their original scope. The 13 shared dashboard/setup golden failures remain investigated; no approved golden was changed.`);
  await write(reviewMdPath, review);
  const reviewJsonPath = 'docs/verification/wave5/continuation-review-20261008.json';
  const reviewJson = await readJson(reviewJsonPath);
  reviewJson.developmentChecks = {
    ...reviewJson.developmentChecks,
    candidateSql: reviewJson.candidateVerification.passed,
    domain, platform, native, analyzerClean: true, buildSourceMatches: true,
    platformAndNativeCurrentSource: true,
  };
  reviewJson.candidateQuerySha256 = reviewJson.candidateVerification.querySha256;
  reviewJson.nonemptyRealizedSqlEvidence = true;
  reviewJson.cashUiVerification = reportPath;
  reviewJson.currentSourceSdkEvidence = { currentSource: true, developmentOnly: true, domain, platform, native, analyzer: true, windowsBuild: true, cashFrames: 36, authenticatedNative: false };
  if (!reviewJson.historicalRenderedFrames) reviewJson.historicalRenderedFrames = reviewJson.renderedFrames;
  reviewJson.renderedFrames = Object.fromEntries(report.frames.map((frame) => [frame.path, frame.sha256]));
  reviewJson.renderedFrameScope = 'Current cash fixture renders; historical frames are retained separately';
  for (const file of [...Object.keys(reviewJson.evidenceHashes).map((f) => `docs/verification/wave5/${f}`), reportPath, reportMd, report.snapshotEvidence, ...Object.values(report.stages).map((stage) => stage.log)]) {
    reviewJson.evidenceHashes[path.basename(file)] = sha(await readFile(path.join(root, file)));
  }
  await writeJson(reviewJsonPath, reviewJson);

  const protocolPath = 'docs/verification/wave5/integrated-runtime-protocol-20261006.md';
  let protocol = (await read(protocolPath)).replace(/\r\n/g, '\n');
  protocol = protocol.replace('passed 100 separate strict rollback checks', 'passed 116 separate strict rollback checks');
  protocol = protocol.replace('The new dated cash provider implements only posted bank transaction cash and positive AR residuals.', 'The candidate dated cash provider implements posted bank transaction cash and permission-gated positive AR/AP residuals after posted allocations and reversals.');
  protocol = protocol.replace('Full cash forecasting still needs complete corrected AP and dated payroll/project obligation adapters.', 'Full cash forecasting still needs authoritative dated payroll/project obligation adapters and installed corrected allocation providers.');
  protocol = protocol.replace('Future allocation-reversal installation also requires extending the AR-only cash basis.', 'The AR/AP allocation-reversal contract is verified only in the strict rollback candidate fixture; installed provider evidence remains open.');
  protocol = protocol.replace(/The final source-scoped analyzer is clean,[\s\S]*?Earlier coverage\/privacy scans retain their original scope\./, `${description} [Cash verification](cash-ui-verification-20261008.md). The 13 shared dashboard/setup golden failures remain unresolved; approved goldens were preserved. Earlier worker, coverage and privacy scans retain their original scope.`);
  await write(protocolPath, protocol);

  const summaryPath = 'docs/verification/wave5/continuation-evidence-summary-20261008.json';
  const summary = await readJson(summaryPath);
  Object.assign(summary, { updatedAt: now, domainLastVerified: domain, platformLastVerified: platform, nativeLastVerified: native,
    platformEvidenceCurrentSource: true, nativeEvidenceCurrentSource: true, analyzerCurrentSource: true,
    windowsBuildCurrentSourceMatch: true, currentCashRenderAvailable: true, cashUiVerification: reportPath,
    sdkEvidenceScope: matrix.continuationChecks.testScope, authenticatedNative: false, actualDelivery: false,
    contention: false, load: false, ownerAccepted: 0, wholeWaveComplete: false,
  });
  for (const file of [matrixPath, matrixMdPath, statusPath, reviewMdPath, reviewJsonPath, protocolPath, reportPath, reportMd]) {
    summary.evidenceHashes[path.basename(file)] = sha(await readFile(path.join(root, file)));
  }
  await writeJson(summaryPath, summary);
  console.log(JSON.stringify({ cashUiCurrentSource: true, domain, platform, native, matrixRows: matrix.rows.length, ownerAccepted: 0 }));
  return true;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await updateCashUiStatus();
