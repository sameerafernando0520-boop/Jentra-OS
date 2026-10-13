import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PROJECT_ID, hashBytes, hashJson, requireGuard, safeFailure } from './runtime_contract.mjs';

const root = path.resolve(fileURLToPath(new URL('../../', import.meta.url))), attempt = process.argv[2], evidenceDate = process.argv[3] ?? '20261012';
requireGuard(/^a[1-9][0-9]*$/.test(attempt ?? '') && /^20[0-9]{6}$/.test(evidenceDate), 'NEW_LOCAL_ATTEMPT_REQUIRED');
const folder = 'docs/verification/wave5', prefix = `${folder}/supabase-provider-local-verification-${evidenceDate}-r5-${attempt}`;
const sources = ['tools/wave5/supabase_http_transport.mjs', 'tools/wave5/supabase_read_store.mjs',
  'tools/wave5/supabase_management_read.mjs', 'tools/wave5/supabase_management_read.test.mjs',
  'tools/wave5/preparation_journal.mjs', 'tools/wave5/preparation_journal.test.mjs',
  'tools/wave5/preparation_file_sink.mjs', 'tools/wave5/preparation_file_sink.test.mjs',
  'tools/wave5/supabase_membership_fixture.mjs', 'tools/wave5/supabase_runtime_provider.mjs', 'tools/wave5/supabase_provider.test.mjs',
  'tools/wave5/SUPABASE_PROVIDER_IMPLEMENTATION.md', 'tools/wave5/verify_supabase_provider.mjs',
  'tools/wave5/supabase_provider_plan.mjs', 'tools/wave5/supabase_provider_plan.test.mjs',
  'tools/wave5/compose_supabase_provider_preparation.mjs',
  'tools/wave5/runtime_contract.mjs', 'tools/wave5/runtime_coordinator.mjs', 'tools/wave5/run_runtime_verification.mjs',
  'tools/wave5/runtime_coordinator.test.mjs', 'tools/wave5/runtime_fixture_spec.mjs',
  `${folder}/complete-app-runtime-review-20261010-r5.json`, `${folder}/runtime-owner-decision-20261012-r5.json`,
  `${folder}/runtime-harness-peer-review-20261012-r5.json`, `${folder}/runtime-fixture-contract-20261012-r5.json`,
  `${folder}/runtime-bootstrap-complete-app-20261009.sql`,
  'supabase/migrations/20260831193714_create_greenfield_foundation.sql',
  'supabase/migrations/20260904121647_wave3_operational_foundation.sql',
  'supabase/migrations/20261006140000_wave5_process_metrics.sql', 'supabase/migrations/20261006143000_wave5_pipeline_forecasts.sql',
  'supabase/migrations/20261006150000_wave5_trusted_metering.sql', 'supabase/migrations/20261006160000_wave5_human_proposals.sql',
  'supabase/migrations/20261006170000_wave5_synthetic_subscriptions.sql', 'supabase/migrations/20261008093000_wave5_persistent_delivery.sql',
  'supabase/migrations/20261008123000_wave5_runtime_scope.sql'];
const binding = async relative => { const bytes = await fs.readFile(path.join(root, relative)); return { path: relative, bytes: bytes.length, sha256: hashBytes(bytes) }; };
const before = await Promise.all(sources.map(binding));
const recordFile = await fs.open(path.join(root, prefix + '.json'), 'wx', 0o600), logFile = await fs.open(path.join(root, prefix + '.tap'), 'wx', 0o600);
const command = ['--test', '--test-isolation=none', '--test-reporter=tap', 'tools/wave5/runtime_coordinator.test.mjs',
  'tools/wave5/supabase_provider.test.mjs', 'tools/wave5/supabase_provider_plan.test.mjs', 'tools/wave5/supabase_management_read.test.mjs',
  'tools/wave5/preparation_journal.test.mjs', 'tools/wave5/preparation_file_sink.test.mjs'];
let output = '', childExitCode = null, childSignal = null, spawnFailure = null;
const startedAt = new Date().toISOString();
try {
  await new Promise(resolve => {
    const child = spawn(process.execPath, command, { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
      env: { SystemRoot: process.env.SystemRoot, WINDIR: process.env.WINDIR, TEMP: process.env.TEMP, TMP: process.env.TMP } });
    child.stdout.on('data', chunk => { output += chunk.toString('utf8'); }); child.stderr.on('data', chunk => { output += chunk.toString('utf8'); });
    child.on('error', error => { spawnFailure = ['EPERM', 'EACCES', 'ENOENT'].includes(error.code) ? error.code : 'SPAWN_FAILED'; });
    child.on('close', (code, signal) => { childExitCode = code; childSignal = signal; resolve(); });
  });
  const finishedAt = new Date().toISOString(), after = await Promise.all(sources.map(binding));
  const count = name => { const found = output.match(new RegExp(`^# ${name} (\\d+)$`, 'm')); return found ? Number(found[1]) : null; };
  const summary = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name => [name, count(name)]));
  const passed = childExitCode === 0 && summary.tests > 0 && summary.tests === summary.pass
    && ['fail', 'cancelled', 'skipped', 'todo'].every(name => summary[name] === 0) && hashJson(before) === hashJson(after);
  await logFile.writeFile(output); await logFile.sync();
  const record = { kind: 'controlled-wave5-supabase-provider-local-verification', projectId: PROJECT_ID,
    actualStartedAt: startedAt, actualFinishedAt: finishedAt, nodeVersion: process.version, command: ['node', ...command],
    childExitCode, childSignal, spawnFailure, passed, summary, filesBefore: before, filesAfter: after,
    selectedSourcesUnchanged: hashJson(before) === hashJson(after), log: { path: prefix + '.tap', sha256: hashBytes(output), bytes: Buffer.byteLength(output) },
    runtimeBundleSha256: 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b',
    publicTransportPathsImplemented: true, concreteConfiguredPrivateProviderReady: false,
    executedLive: false, networkCalls: 0, authWrites: 0, installedSqlWrites: 0, sdkJobs: 0, nativeActions: 0,
    realPasswordsOrTokensRead: false, fabricatedJwtOrAuthRows: false, additionalOwnerDecisionRequired: false,
    gates: { installedSql: false, genuineMfa: false, independentSessionContention: false, targetScaleLoad: false,
      authenticatedNative: false, actualDelivery: false, ownerAcceptance: false },
    boundary: 'Actual local Node tests using controlled HTTP/driver objects, actual encrypted temp-file persistence of synthetic records and existing virtual-time coordinator tests. No real Auth, PostgreSQL, MFA, worker trace or latency evidence.' };
  await recordFile.writeFile(JSON.stringify(record, null, 2) + '\n'); await recordFile.sync();
  process.stdout.write(JSON.stringify({ path: prefix + '.json', sha256: hashBytes(JSON.stringify(record, null, 2) + '\n'), summary, passed }) + '\n');
  if (!passed) process.exitCode = 1;
} catch (error) { await recordFile.writeFile(JSON.stringify({ kind: 'controlled-wave5-provider-verification-error', code: safeFailure(error),
  actualStartedAt: startedAt, filesBefore: before, executedLive: false }) + '\n'); process.exitCode = 1; }
finally { await recordFile.close(); await logFile.close(); }
