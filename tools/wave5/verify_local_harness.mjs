import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hashBytes, hashJson, requireGuard, safeFailure, PROJECT_ID } from './runtime_contract.mjs';

const root = path.resolve(fileURLToPath(new URL('../../', import.meta.url)));
const evidence = path.join(root, 'docs', 'verification', 'wave5');
const files = ['tools/wave5/runtime_contract.mjs', 'tools/wave5/runtime_coordinator.mjs',
  'tools/wave5/run_runtime_verification.mjs', 'tools/wave5/runtime_coordinator.test.mjs',
  'tools/wave5/PRIVATE_PROVIDER_CONTRACT.md', 'tools/wave5/verify_local_harness.mjs'];
const contracts = [
  'docs/verification/wave5/integrated-runtime-protocol-20261006.md',
  'docs/verification/wave5/runtime-bootstrap-complete-app-20261009.sql',
  'supabase/migrations/20260831193714_create_greenfield_foundation.sql',
  'supabase/migrations/20260904121647_wave3_operational_foundation.sql',
  'supabase/migrations/20261006140000_wave5_process_metrics.sql',
  'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql',
  'supabase/migrations/20261006150000_wave5_trusted_metering.sql',
  'supabase/migrations/20261006160000_wave5_human_proposals.sql',
  'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql',
  'supabase/migrations/20261008093000_wave5_persistent_delivery.sql',
  'supabase/migrations/20261008123000_wave5_runtime_scope.sql',
];
const runtimePath = 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json';
const runtimeFileSha = 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3';
const runtimeBundleSha = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
const attempt = process.argv[2];
requireGuard(/^a[2-9][0-9]*$/.test(attempt ?? ''), 'NEW_LOCAL_ATTEMPT_REQUIRED');
const prefix = `runtime-harness-local-verification-20261012-r5-${attempt}`;
const ref = async file => { const bytes = await fs.readFile(path.join(root, file)); return { path: file, sha256: hashBytes(bytes), bytes: bytes.length }; };
const before = await Promise.all([...files, ...contracts, runtimePath].map(ref));
requireGuard(before.at(-1).sha256 === runtimeFileSha, 'CURRENT_RUNTIME_FILE_CHANGED');
const runtime = JSON.parse((await fs.readFile(path.join(root, runtimePath))).toString('utf8'));
requireGuard(runtime.bundleSha256 === runtimeBundleSha && runtime.ownerApproved === false, 'CURRENT_RUNTIME_BUNDLE_CHANGED');
const recordPath = path.join(evidence, prefix + '.json'), logPath = path.join(evidence, prefix + '.tap');
const recordHandle = await fs.open(recordPath, 'wx', 0o600), logHandle = await fs.open(logPath, 'wx', 0o600);
let output = '', spawnFailure = null;
const startedAt = new Date().toISOString();
let exitCode = null, signal = null;
try {
  await new Promise(resolve => {
    const child = spawn(process.execPath, ['--test', '--test-isolation=none', '--test-reporter=tap', 'tools/wave5/runtime_coordinator.test.mjs'],
      { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: { SystemRoot: process.env.SystemRoot,
        WINDIR: process.env.WINDIR, TEMP: process.env.TEMP, TMP: process.env.TMP } });
    child.stdout.on('data', data => { output += data.toString('utf8'); });
    child.stderr.on('data', data => { output += data.toString('utf8'); });
    child.on('error', error => { spawnFailure = ['EPERM', 'EACCES', 'ENOENT'].includes(error.code) ? error.code : 'SPAWN_FAILED'; });
    child.on('close', (code, terminatedBy) => { exitCode = code; signal = terminatedBy; resolve(); });
  });
  await logHandle.writeFile(output); await logHandle.sync();
  const after = await Promise.all([...files, ...contracts, runtimePath].map(ref));
  const match = name => { const value = output.match(new RegExp(`^# ${name} (\\d+)$`, 'm')); return value ? Number(value[1]) : null; };
  const summary = { tests: match('tests'), passed: match('pass'), failed: match('fail'), skipped: match('skipped'), cancelled: match('cancelled'), todo: match('todo') };
  const record = { kind: 'controlled-wave5-harness-local-verification', projectId: PROJECT_ID, observedAt: new Date().toISOString(),
    actualStartedAt: startedAt, actualFinishedAt: new Date().toISOString(), nodeVersion: process.version,
    command: ['node', '--test', '--test-isolation=none', '--test-reporter=tap', 'tools/wave5/runtime_coordinator.test.mjs'],
    childExitCode: exitCode, childSignal: signal, spawnFailure, summary, testsExecuted: summary.tests !== null,
    passed: exitCode === 0 && summary.tests > 0 && summary.tests === summary.passed && summary.failed === 0
      && summary.skipped === 0 && summary.cancelled === 0 && summary.todo === 0 && hashJson(before) === hashJson(after),
    filesBefore: before, filesAfter: after, selectedSourcesUnchanged: hashJson(before) === hashJson(after),
    log: { path: path.relative(root, logPath).split(path.sep).join('/'), sha256: hashBytes(output), bytes: Buffer.byteLength(output) },
    runtimeReview: { path: runtimePath, sha256: runtimeFileSha, bundleSha256: runtimeBundleSha },
    executedLive: false, privateProviderImplemented: false, privateProviderLoaded: false, credentialsRead: false,
    networkCalls: 0, sdkJobs: 0, nativeActions: 0, installations: 0, authWrites: 0, modifiedExistingFiles: [],
    gates: { independentSessionContention: false, targetScaleLoad: false, authenticatedNative: false, ownerAcceptance: false },
    boundary: 'Controlled orchestration/guard tests, including virtual-time population/mix checks; not genuine Auth, installed contracts, real contention or target-scale latency.' };
  await recordHandle.writeFile(JSON.stringify(record, null, 2) + '\n'); await recordHandle.sync();
  process.stdout.write(JSON.stringify({ recordPath: path.relative(root, recordPath).split(path.sep).join('/'), childExitCode: exitCode,
    passed: record.passed, summary, spawnFailure }) + '\n');
  if (!record.passed) process.exitCode = 1;
} catch (error) {
  await recordHandle.writeFile(JSON.stringify({ kind: 'controlled-wave5-harness-verification-error', failureCode: safeFailure(error),
    observedAt: new Date().toISOString(), executedLive: false, before }) + '\n'); process.exitCode = 1;
} finally { await logHandle.close(); await recordHandle.close(); }
