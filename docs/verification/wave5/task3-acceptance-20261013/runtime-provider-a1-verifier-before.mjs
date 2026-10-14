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
const publicSources = fs.readdirSync(path.resolve(root, 'tools/wave5')).filter(name => name.endsWith('.mjs')).map(name => `tools/wave5/${name}`);
const files = [...new Set([...publicSources, ...harnessSources, predecessor.runtimeReview.path, predecessorPath,
  `${output}/load-baseline-115-independent-review.json`, `${output}/review_load_baseline_115.mjs`,
  `${output}/verify_baseline_115_provider.mjs`,
  'docs/verification/wave5/task3-completion-20261013/load-baseline-115-source-application.json'])].sort();
const before = files.map(bind);
const command = ['--test', '--test-isolation=none', '--test-reporter=tap', ...tests];
const environment = Object.fromEntries(['SystemRoot', 'WINDIR', 'TEMP', 'TMP'].filter(key => process.env[key])
  .map(key => [key, process.env[key]]));
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
const passed = exitCode === 0 && childSignal === null && spawnFailure === null && summary.tests === 121
  && summary.passed === summary.tests && summary.failed === 0 && summary.skipped === 0
  && summary.cancelled === 0 && summary.todo === 0 && identities.length === summary.tests && unchanged && coordinatorAllPresent;
const stem = `${output}/runtime-provider-local-verification-20261014-acceptance-a1`;
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
  runtimeReview: predecessor.runtimeReview,
  independentBaselineReview: bind(`${output}/load-baseline-115-independent-review.json`),
  log: bind(`${stem}.tap`),
  writerAndWrapperTestsRepeated: false, executedLive: false, privateProviderLoaded: false,
  networkCalls: 0, privateCredentialsRead: false, SDKJobs: 0, SQLMutations: 0, acceptanceDecisionsAdded: 0,
  boundary: '121 actual local Node cases across the existing 11 public provider test files, including 41 coordinator cases. Controlled Auth, PostgreSQL, transport and virtual-time workloads prove implementation guards only; fresh live source/preflight, genuine sessions, actual contention/P95 and native acceptance remain required.',
};
fs.writeFileSync(path.resolve(root, `${stem}.json`), JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify({passed, summary, coordinatorCaseCount: 41, sourceCount: before.length,
  sourcesUnchangedDuringRun: unchanged, record: bind(`${stem}.json`), log: bind(`${stem}.tap`)}, null, 2));
if (!passed) process.exitCode = 1;
