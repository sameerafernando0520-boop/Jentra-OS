import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const directory = 'docs/verification/wave5/seven-area-completion-20261016/area2-finance/';
const matrixPath = 'docs/verification/wave5/task3-acceptance-20261013/delegated-technical-acceptance-matrix.json';
const ids = ['FR-505','FR-506','FR-509','FR-510','FR-511','FR-512','FR-513','FR-514','NFR-502','NFR-510','AC-504','AC-505','EC-504','EC-505','FR-552'];
const next = {
  'FR-505': 'Retain full canonical manifest and basis for every process, history, ratio, cash and export result; statement summaries alone do not reproduce canonical statement hashes.',
  'FR-506': 'Run late source commit/backfill after a captured complete server snapshot and reproduce retained cutoff and transition manifests under current authorization.',
  'FR-509': 'Run complete historical stage/amount/probability/owner source cases and the missing-history/gap rejection against installed providers.',
  'FR-510': 'Retain genuine frozen opportunity revisions and assumptions with separate currencies; test source changes, missing FX and freeze/reopen.',
  'FR-511': 'Capture a nonempty realized cohort after its horizon and verify exact invoice/credit mapping, zero denominator and incomplete mapping states through genuine actors.',
  'FR-512': 'Retain full immutable statements and governed account classifications, reproduce classified operands and formulas, and verify matching scope/period/currency.',
  'FR-513': 'Retain dated bank/cash controls and each AR/AP/payroll/project residual with settlements, reversals and duplicate-allocation rejection.',
  'FR-514': 'Execute actual scenario revision/freeze/reopen and compare before/after journal, stock, obligation and source fingerprints; actual scenarios remain unproved.',
  'NFR-502': 'Complete exact decimal cross-provider and export reproduction, including usage/probabilities and negative/zero states; this audit covers nine retained ratio rows only.',
  'NFR-510': 'Replay each installed provider with reordered complete snapshots and current permission checks; retain stable exact values and recorded cutoff.',
  'AC-504': 'Complete authoritative frozen forecast/history/realized cohorts and all missing-history, mixed-currency and zero-denominator cases.',
  'AC-505': 'Reproduce classified numerator/denominator from account-level authoritative publications, not just precomputed operands or summaries.',
  'EC-504': 'Exercise installed empty/negative/zero/mixed-currency/missing-FX/missing-history paths; the client now rejects per-opportunity currency substitution.',
  'EC-505': 'Execute settled/reversed/credited/payroll/AP residual coverage against installed providers; reject any incomplete or duplicated obligation basis.',
  'FR-552': 'Retain a complete bounded authorized event snapshot manifest and reject truncation at the installed provider boundary, with source revision/count/cutoffs bound.',
};
const matrix = JSON.parse(await readFile(matrixPath, 'utf8'));
const rows = ids.map(id => {
  const row = matrix.rows.find(r => r.id === id);
  assert.ok(row && row.accepted === false, `${id}: baseline changed, review again`);
  return { id, fullStatement: row.fullStatement, statementSha256: row.statementSha256, decision: 'open_missing_evidence', recommendation: next[id] };
});
const testLog = await readFile(directory + 'platform-focused-test-final.log', 'utf8');
const analysisLog = await readFile(directory + 'scoped-analysis.log', 'utf8');
assert.match(testLog, /\+6: All tests passed!/);
assert.match(analysisLog, /No issues found!/);
const paths = [matrixPath,
  'packages/jentra_platform/lib/src/analytics/historical_pipeline_gateway.dart',
  'packages/jentra_platform/test/analytics/historical_pipeline_gateway_test.dart',
  directory + 'audit_financial_evidence.mjs', directory + 'audit_financial_evidence.test.mjs',
  directory + 'financial-evidence-reproduction.json', directory + 'platform-focused-test.log',
  directory + 'platform-focused-test-unsandboxed.log', directory + 'platform-focused-test-final.log',
  directory + 'scoped-analysis.log',
  'supabase/migrations/20261008090000_wave5_historical_pipeline.sql',
];
const inputBindings = await Promise.all(paths.map(async path => {
  const bytes = await readFile(path);
  return { path, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };
}));
const report = {
  kind: 'area2-finance-development-and-evidence-review',
  recordedAt: new Date().toISOString(),
  projectId: 'xpdoufauvrbdmxgngetv',
  area: 'Authoritative analytics history and exact financial basis',
  sourceFixes: [
    'Reject realized documents whose currency differs from the specific frozen opportunity, even if both currencies exist elsewhere in the forecast.',
    'Parse and reject malformed/reversed history cutoffs before invoking the RPC; use those parsed instants when checking the response.',
  ],
  scopedFlutterTests: { passed: 6, failed: 0, exitCode: 0, toolChunk: '1874e6' },
  scopedAnalysis: { exitCode: 0, issues: 0 },
  controlledFinancialAuditTests: { passed: 8, failed: 0, exitCode: 0, toolChunk: 'edd013' },
  historicalRatioRowsReproduced: 9,
  historicalStatementOperandPairsReproduced: 6,
  preservedFailures: [
    'Sandboxed format produced formatted files but exited 1 on the inaccessible telemetry cache; authorized rerun exited 0.',
    'Sandboxed Flutter test could not open SDK lockfile; preserved platform-focused-test.log.',
    'First authorized focused test had five passes and one incorrect matcher expectation; preserved platform-focused-test-unsandboxed.log; strict UTC parser throws DomainError VALIDATION_ERROR and final test matches it.',
  ],
  openRows: rows,
  acceptanceDecisionsAdded: 0,
  liveQueries: 0,
  privateInputsRead: false,
  migrationsApplied: false,
  financialSourcePostingPerformed: false,
  inputBindings,
  sourceDocumentation: [
    { url: 'https://supabase.com/changelog', note: 'Reviewed current change index; recent HTTP TLS deprecation does not alter this local DTO validation patch.' },
    { url: 'https://supabase.com/docs/guides/database/postgres/row-level-security', note: 'Authorization remains the installed provider responsibility; no client hash or this offline audit grants access.' },
  ],
};
await writeFile(directory + 'area2-report.json', JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ passed: true, openRows: rows.length, bindings: inputBindings.length, acceptanceDecisionsAdded: 0 }));
