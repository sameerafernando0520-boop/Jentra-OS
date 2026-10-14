import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(folder, '../../../..');
const base = 'docs/verification/wave5/task3-load-release-20261013';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = async relative => {
  const bytes = await fs.readFile(path.join(root, relative));
  return {path: relative, bytes: bytes.length, sha256: sha(bytes), text: bytes.toString('utf8')};
};
const ref = ({text, ...binding}) => binding;
const names = ['fixture_writer.mjs', 'fixture_writer.test.mjs', 'fixture_writer_test_support.mjs',
  'provider_operation_wrapper.mjs', 'provider_operation_wrapper.test.mjs', 'provider_pg_factory.mjs',
  'postgres_transport.mjs', 'transport_helpers.test.mjs', 'readonly_credential_lifecycle.test.mjs', 'external_observer.mjs', 'package.json', 'package-lock.json', 'node_modules/pg/package.json'];
const publicNames = ['runtime_contract.mjs', 'runtime_fixture_spec.mjs', 'supabase_runtime_provider.mjs', 'supabase_read_store.mjs',
  'supabase_membership_fixture.mjs', 'preparation_journal.mjs', 'supabase_http_transport.mjs'];
const files = [...names.map(name => `${base}/${name}`), ...publicNames.map(name => `tools/wave5/${name}`),
  'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',
  'docs/verification/wave5/runtime-owner-decision-20261012-r5.json',
  'docs/verification/wave5/task3-completion-20261013/load-baseline-115-source-application.json'];
const before = await Promise.all(files.map(read));
const fixed = {
  'fixture_writer.mjs': 'ff9b4a3788b11c4558b8be0fb79e0e565d2ea4b7c137473d531df388cd4c1298',
  'provider_operation_wrapper.mjs': 'dba663a72081027615089c6abe58f1af2763da8107fe2b2af537ae8dc534f6de',
  'provider_pg_factory.mjs': '1ed26789894554d2462017a6234e56ae6b131d004152d8eb73300d858f919730',
  'postgres_transport.mjs': 'ca0e3a8373160058aa8b929efbfeaab624ecb04fc2016919568f823262f25c07',
};
for (const [name, expected] of Object.entries(fixed)) assert.equal(before.find(row => row.path === `${base}/${name}`).sha256, expected);
assert.match(before.find(row => row.path === 'tools/wave5/runtime_contract.mjs').text, /proof\.installedMigrationCount === 115/);
const command = ['--test', '--test-isolation=none', '--test-reporter=tap',
  `${base}/fixture_writer.test.mjs`, `${base}/provider_operation_wrapper.test.mjs`, `${base}/transport_helpers.test.mjs`, `${base}/readonly_credential_lifecycle.test.mjs`];
const env = Object.fromEntries(['SystemRoot', 'WINDIR', 'TEMP', 'TMP'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
const startedAt = new Date().toISOString();
let output = '', exitCode, signal, spawnError = false;
await new Promise(resolve => {
  const child = spawn(process.execPath, command, {cwd: root, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  const timer = setTimeout(() => { output += '\nCONTROLLED_INTEGRATION_DEADLINE\n'; child.kill(); }, 60000);
  child.stdout.on('data', bytes => { output += bytes.toString('utf8'); });
  child.stderr.on('data', bytes => { output += bytes.toString('utf8'); });
  child.on('error', () => { spawnError = true; });
  child.on('close', (code, why) => {clearTimeout(timer); exitCode = code; signal = why; resolve();});
});
const after = await Promise.all(files.map(read));
const counts = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name =>
  [name, Number(output.match(new RegExp(`^# ${name} (\\d+)$`, 'm'))?.[1] ?? -1)]));
const logPath = path.join(folder, 'provider-integration-independent-tests-20261014-a2.tap');
const logBytes = Buffer.from(output);
await fs.writeFile(logPath, logBytes, {flag: 'wx'});
const passed = !spawnError && exitCode === 0 && signal === null && counts.tests === 61 && counts.pass === counts.tests
  && ['fail', 'cancelled', 'skipped', 'todo'].every(key => counts[key] === 0)
  && sha(JSON.stringify(before.map(ref))) === sha(JSON.stringify(after.map(ref)));
const report = {kind: 'independent-current-reader-writer-provider-controlled-integration-review', startedAt,
  finishedAt: new Date().toISOString(), passed, command: [process.execPath, ...command], exitCode, signal, counts,
  sourcesUnchangedDuringRun: sha(JSON.stringify(before.map(ref))) === sha(JSON.stringify(after.map(ref))),
  sourceBindingsBefore: before.map(ref), sourceBindingsAfter: after.map(ref),
  log: {path: path.relative(root, logPath).replaceAll('\\', '/'), bytes: logBytes.length, sha256: sha(logBytes)},
  reviewedBehavior: ['separate exact reader and membership-writer roles', 'TLS and deadline enforcement',
    'exact reviewed tenant, original identities, versions and SQL', 'both legitimate admission restoration outcomes',
    'durable original private invitation record verified before token-free adoption',
    'actual source verification before private configuration', 'public factory and unchanged fixture/journal integration',
    'pending acquisition/BEGIN cancellation destroys leases', 'uncertain COMMIT is never replayed',
    'both pools close on public-provider close failure'],
  installedCountRequired: 115, historicalInstallCountRetained: 114,
  livePostgresConnections: 0, liveSqlMutations: 0, credentialsRead: false, SDKJobs: 0,
  genuineAuthSessionsCreated: 0, actualLoadPerformed: false, productionReleaseReady: false,
  boundary: 'Actual local controlled tests with fake transports and real provider/fixture/journal code; no actual network, Auth, TLS handshake, database or full-load acceptance.'};
const reportPath = path.join(folder, 'provider-integration-independent-review-20261014-a2.json');
const bytes = Buffer.from(JSON.stringify(report, null, 2) + '\n');
await fs.writeFile(reportPath, bytes, {flag: 'wx'});
process.stdout.write(JSON.stringify({passed, counts, report: {path: path.relative(root, reportPath).replaceAll('\\', '/'), bytes: bytes.length, sha256: sha(bytes)}}) + '\n');
if (!passed) process.exitCode = 1;
