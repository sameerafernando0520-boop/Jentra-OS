import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const output = 'docs/verification/wave5/task3-acceptance-20261013';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = name => fs.readFileSync(path.resolve(root, name));
const bind = name => ({path: name, bytes: read(name).length, sha256: sha(read(name))});
const predecessorPath = 'docs/verification/wave5/task3-peer-review-20261013/runtime-harness-review-20261013-peer-a2.json';
const predecessor = JSON.parse(read(predecessorPath));
const harnessSources = [...predecessor.files, ...predecessor.contractSources].map(row => row.path);
assert.equal(harnessSources.length, 18);
const tests = ['tools/wave5/runtime_coordinator.test.mjs', 'tools/wave5/supabase_provider.test.mjs',
  'tools/wave5/supabase_provider_plan.test.mjs', 'tools/wave5/supabase_management_read.test.mjs',
  'tools/wave5/preparation_journal.test.mjs', 'tools/wave5/preparation_file_sink.test.mjs',
  'tools/wave5/supabase_provider_peer_20261013.test.mjs', 'tools/wave5/provider_live_response_regression_20261013_r5.test.mjs',
  'tools/wave5/membership_preparation_peer_20261013.test.mjs', 'tools/wave5/preparation_journal_peer_20261013.test.mjs',
  'tools/wave5/preparation_file_sink_peer_20261013.test.mjs'];
// Follow the actual relative static/dynamic module imports of these 11 tests.
// Unrelated other-owned finance tests are not dependencies of this suite.
const importedSources = new Set();
function collectImports(name) {
  if (importedSources.has(name)) return;
  importedSources.add(name);
  const source = read(name).toString('utf8');
  const relativeImports = [...source.matchAll(/(?:from\s*|import\s*\(\s*|import\s*)['"](\.[^'"]+\.mjs)['"]/g)].map(match => match[1]);
  for (const relative of relativeImports) {
    const child = path.posix.normalize(path.posix.join(path.posix.dirname(name), relative));
    assert.ok(child.startsWith('tools/wave5/'), 'TEST_SOURCE_IMPORT_OUTSIDE_REVIEWED_MODULES');
    collectImports(child);
  }
}
tests.forEach(collectImports);
const files = [...new Set([...importedSources, ...harnessSources, predecessor.runtimeReview.path, predecessorPath,
  `${output}/load-baseline-115-independent-review.json`, `${output}/review_load_baseline_115.mjs`,
  `${output}/verify_baseline_115_provider_a3.mjs`,
  'docs/verification/wave5/task3-completion-20261013/load-baseline-115-source-application.json'])].sort();
const before = files.map(bind);
const command = ['--test', '--test-isolation=none', '--test-reporter=tap', ...tests];
const environment = Object.fromEntries(['SystemRoot', 'WINDIR'].filter(key => process.env[key])
  .map(key => [key, process.env[key]]));
const temporaryRoot = 'C:/Users/sheha/.codex/visualizations/2026/10/13/01a13650-c557-70d3-bb66-3c40b2a71efb';
assert.equal(fs.realpathSync(temporaryRoot).toLowerCase(), path.resolve(temporaryRoot).toLowerCase());
assert.ok(path.relative(root, temporaryRoot).startsWith('..'), 'SYNTHETIC_PRIVATE_FIXTURE_TEMP_MUST_BE_OUTSIDE_SOURCE_REPOSITORY');
const temporaryDirectory = fs.mkdtempSync(path.join(temporaryRoot, 'baseline115-provider-a3-temp-'));
assert.ok(path.relative(temporaryRoot, fs.realpathSync(temporaryDirectory)).startsWith('baseline115-provider-a3-temp-'));
const probe = path.join(temporaryDirectory, 'write-probe.txt');
fs.writeFileSync(probe, 'controlled writable temporary input\n', {flag: 'wx'});
assert.equal(fs.readFileSync(probe, 'utf8'), 'controlled writable temporary input\n');
environment.TEMP = temporaryDirectory; environment.TMP = temporaryDirectory;
let stdout = '', stderr = '', exitCode = null, childSignal = null, spawnFailure = null;
const startedAt = new Date().toISOString();
await new Promise(resolve => {
  const child = spawn(process.execPath, command, {cwd: root, windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'], env: environment});
  const timer = setTimeout(() => { spawnFailure = 'LOCAL_TEST_TIMEOUT'; child.kill(); }, 60000);
  child.stdout.on('data', bytes => { stdout += bytes.toString('utf8'); });
  child.stderr.on('data', bytes => { stderr += bytes.toString('utf8'); });
  child.on('error', error => { spawnFailure = ['EPERM', 'EACCES', 'ENOENT'].includes(error.code) ? error.code : 'LOCAL_CHILD_SPAWN_FAILED'; });
  child.on('close', (code, signal) => { clearTimeout(timer); exitCode = code; childSignal = signal; resolve(); });
});
const finishedAt = new Date().toISOString(), log = stdout + stderr;
const count = name => Number(new RegExp(`^# ${name} (\\d+)$`, 'm').exec(log)?.[1] ?? -1);
const summary = {tests: count('tests'), passed: count('pass'), failed: count('fail'),
  skipped: count('skipped'), cancelled: count('cancelled'), todo: count('todo')};
const identities = [...stdout.matchAll(/^# Subtest: (.+)$/gm)].map(match => match[1]);
const coordinatorIdentities = [...read(tests[0]).toString().matchAll(/^test\('([^']+)'/gm)].map(match => match[1]);
assert.equal(coordinatorIdentities.length, 41);
const coordinatorAllPresent = coordinatorIdentities.every(name => identities.includes(name));
const after = files.map(bind), unchanged = JSON.stringify(before) === JSON.stringify(after);
const passed = exitCode === 0 && childSignal === null && spawnFailure === null && summary.tests === 122
  && summary.passed === summary.tests && summary.failed === 0 && summary.skipped === 0
  && summary.cancelled === 0 && summary.todo === 0 && identities.length === summary.tests && unchanged && coordinatorAllPresent;
const stem = `${output}/runtime-provider-local-verification-20261014-acceptance-a3`;
fs.writeFileSync(path.resolve(root, `${stem}.tap`), log, {flag: 'wx'});
const result = {
  kind: 'independent-current-115-public-runtime-provider-verification', projectId: 'xpdoufauvrbdmxgngetv',
  actualStartedAt: startedAt, actualFinishedAt: finishedAt, nodeVersion: process.version,
  command: ['node', ...command], childExitCode: exitCode, childSignal, spawnFailure,
  summary, testIdentities: identities, testFileCount: 11, coordinatorCaseCount: 41,
  exactAllCoordinatorIdentitiesObserved: coordinatorAllPresent,
  passed, testsExecuted: summary.tests > 0, selectedSourcesUnchanged: unchanged,
  sourcesUnchangedDuringRun: unchanged, filesBefore: before, filesAfter: after,
  currentHarnessBindingsBefore: harnessSources.map(name => before.find(row => row.path === name)),
  currentHarnessBindingsAfter: harnessSources.map(bind), harnessSourceCount: 18,
  importedTestSourceCount: importedSources.size,
  childOnlyTemporaryDirectory: path.relative(root, temporaryDirectory).replaceAll('\\', '/'),
  priorAttemptsPreserved: [1, 2].map(attempt => bind(`${output}/runtime-provider-local-verification-20261014-acceptance-a${attempt}.json`)),
  successorReason: 'a1 could not create a junction in sandbox AC/Temp; a2 correctly rejected repository TEMP destinations. This attempt uses only child TEMP/TMP in a new synthetic directory under the explicitly writable visualization root outside the source repository. The controlled junction test needs an unsandboxed run because sandbox creation there was denied. Product code, tested guard expectations and tests are unchanged.',
  executionBoundary: 'Approved controlled test execution outside the filesystem sandbox, with only SystemRoot/WINDIR and synthetic child TEMP/TMP environment inputs. No private credentials, accounts, existing profile/stores, network, live SQL or SDK operations.',
  runtimeReview: predecessor.runtimeReview,
  independentBaselineReview: bind(`${output}/load-baseline-115-independent-review.json`),
  log: bind(`${stem}.tap`),
  writerAndWrapperTestsRepeated: false, executedLive: false, privateProviderLoaded: false,
  networkCalls: 0, privateCredentialsRead: false, SDKJobs: 0, SQLMutations: 0, acceptanceDecisionsAdded: 0,
  boundary: '122 actual local Node cases across the existing 11 public provider test files, including 41 coordinator cases. Controlled Auth, PostgreSQL, transport and virtual-time workloads prove implementation guards only; fresh live source/preflight, genuine sessions, actual contention/P95 and native acceptance remain required.',
};
fs.writeFileSync(path.resolve(root, `${stem}.json`), JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify({passed, summary, coordinatorCaseCount: 41, sourceCount: before.length,
  sourcesUnchangedDuringRun: unchanged, record: bind(`${stem}.json`), log: bind(`${stem}.tap`)}, null, 2));
if (!passed) process.exitCode = 1;
