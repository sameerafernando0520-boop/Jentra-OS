import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const dir = 'docs/verification/wave5/seven-area-completion-20261016/area5-subscriptions';
const ids = ['FR-524', 'FR-525', 'FR-526', 'AC-512', 'AC-513', 'EC-511'];
const matrixPath = 'docs/verification/wave5/task3-acceptance-20261013/delegated-technical-acceptance-matrix.json';
const matrix = JSON.parse(fs.readFileSync(matrixPath));
const binding = file => {
  const bytes = fs.readFileSync(file);
  return { path: file, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };
};
const historical = [
  ['docs/verification/wave5/subscription-development-result-20261006.json', 124],
  ['docs/verification/wave5/subscription-native-development-result-20261006.json', 126],
].map(([file, count]) => {
  const saved = JSON.parse(fs.readFileSync(file));
  const tap = saved.result[0].tap;
  assert.equal(saved.strict_finish, true);
  assert.equal(saved.rollback, true);
  assert.equal(tap.length, count);
  assert.ok(tap.every((line, index) => line.startsWith(`ok ${index + 1} - `)));
  return { ...binding(file), assertions: count, failed: 0, originalRunDate: '2026-10-06', rollback: true,
    currentRun: false, installedAcceptanceClaimed: false, independentContentionClaimed: false };
});
const red = fs.readFileSync(`${dir}/red-regression-20261017.log`, 'utf8');
const green = fs.readFileSync(`${dir}/green-regression-20261017.log`, 'utf8');
const analysis = fs.readFileSync(`${dir}/analyze-20261017.log`, 'utf8');
assert.match(red, /\+3 -2: Some tests failed\./);
assert.match(red, /rejects an empty authoritative allowance period \[E\]/);
assert.match(red, /rejects an inverted authoritative allowance period \[E\]/);
assert.match(green, /\+5: All tests passed!/);
assert.match(analysis, /No issues found!/);
const before = `${dir}/wave5_control_gateway.before.dart`;
const source = 'packages/jentra_platform/lib/src/analytics/wave5_control_gateway.dart';
assert.equal(binding(before).sha256, '5f0992c128f48814b475a61fc6e5532a9789d90b85b289ae881727b2ef7e1029');
const rows = ids.map(id => {
  const prior = matrix.rows.find(row => row.id === id);
  assert.ok(prior?.fullStatement && prior.accepted === false);
  return { id, fullStatement: prior.fullStatement, statementSha256: prior.statementSha256,
    accepted: false, decision: 'open_missing_live_evidence', remaining: prior.nextEvidence };
});
const files = [source, 'packages/jentra_platform/test/analytics/wave5_usage_period_20261016_test.dart', before,
  `${dir}/red-regression.log`, `${dir}/red-regression-20261017.log`, `${dir}/green-regression-20261017.log`,
  `${dir}/analyze-20261017.log`, `${dir}/format.log`, matrixPath,
  'supabase/migrations/20261006150000_wave5_trusted_metering.sql',
  'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql',
  'supabase/tests/wave5_trusted_metering_test.sql', 'supabase/tests/wave5_synthetic_subscriptions_test.sql',
  'tools/wave5/runtime_fixture_spec.mjs', 'tools/wave5/runtime_contract.mjs', `${dir}/verify_area5.mjs`, `${dir}/README.md`];
const report = {
  kind: 'wave5-area5-subscriptions-development-and-evidence-review', recordedAt: new Date().toISOString(),
  projectId: 'xpdoufauvrbdmxgngetv', productFix: 'Reject empty or inverted available allowance periods while retaining historical observation timestamps.',
  tests: { actualFocusedCases: 5, before: { exitCode: 1, passed: 3, failed: 2 },
    after: { exitCode: 0, passed: 5, failed: 0 }, scopedAnalysisExitCode: 0, formattedFiles: 2,
    initialSdkLockfileFailureCountedAsTestFailure: false },
  historicalEvidence: historical, requirements: rows, newAcceptanceCount: 0,
  allSixComplete: false, wholeWaveComplete: false, liveCalls: 0, privateInputsRead: false,
  independentReservationRaceExecuted: false, billingProviderEnabled: false, realBillingPerformed: false,
  migrationsInstalled: false, sources: files.map(binding),
  documentation: [
    'https://supabase.com/docs/guides/local-development/testing/overview',
    'https://supabase.com/docs/guides/database/postgres/row-level-security',
  ],
  documentationCaveat: 'Supabase changelog markdown fetch returned unsupported content type; official testing and RLS documentation were read successfully.',
};
fs.writeFileSync(path.join(dir, 'sourceproof.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ passed: true, sources: report.sources.length, actualFocusedCases: 5,
  allSixComplete: false, newAcceptanceCount: 0, sourceproof: binding(`${dir}/sourceproof.json`) }));
