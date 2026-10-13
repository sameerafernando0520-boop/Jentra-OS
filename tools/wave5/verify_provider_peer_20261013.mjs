import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PROJECT_ID, hashBytes, hashJson } from './runtime_contract.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const attempt = process.argv[2];
const preparationPlanAttempt = process.argv[3] ?? 'a1';
if (![attempt, preparationPlanAttempt].every(value => /^a[1-9][0-9]*$/.test(value ?? ''))) throw new Error('NEW_LOCAL_ATTEMPT_REQUIRED');
const folder = 'docs/verification/wave5';
const prefix = `${folder}/independent-provider-local-verification-20261013-r5-${attempt}`;
const explicit = [
  'tools/wave5/supabase_http_transport.mjs', 'tools/wave5/supabase_read_store.mjs',
  'tools/wave5/supabase_membership_fixture.mjs', 'tools/wave5/supabase_runtime_provider.mjs',
  'tools/wave5/supabase_provider_plan.mjs', 'tools/wave5/supabase_provider_plan.test.mjs',
  'tools/wave5/supabase_provider.test.mjs', 'tools/wave5/SUPABASE_PROVIDER_IMPLEMENTATION.md',
  'tools/wave5/PRIVATE_PROVIDER_CONTRACT.md', 'tools/wave5/compose_supabase_provider_preparation.mjs',
  'tools/wave5/verify_supabase_provider.mjs',
  'tools/wave5/provider_live_response_regression_20261013_r5.test.mjs',
  'tools/wave5/source_workflow_management_20261013_r5.mjs',
  'tools/wave5/continue_source_workflows_20261013_r5_a3.mjs',
  'tools/wave5/synthetic_activation_contention_20261013_r5.mjs',
  'tools/wave5/genuine_delivery_lease_20261013_r5.mjs',
  'tools/wave5/prepare_actual_delivery_fixtures_20261013_r5.mjs',
  'tools/wave5/delivery_transport_20261013_r5.mjs',
  'tools/wave5/private_existing_actor_session_20261013_r5.mjs',
  'tools/wave5/verify_persistent_setup_committed_20261013_r5.mjs',
  'scripts/wave5/run_private_management_installer_20261013_r5.ps1',
  'tools/wave5/supabase_management_read.mjs', 'tools/wave5/supabase_management_read.test.mjs',
  'tools/wave5/runtime_contract.mjs', 'tools/wave5/runtime_coordinator.mjs',
  'tools/wave5/run_runtime_verification.mjs', 'tools/wave5/runtime_coordinator.test.mjs',
  'tools/wave5/runtime_fixture_spec.mjs', 'tools/wave5/supabase_provider_peer_20261013.test.mjs',
  'tools/wave5/preparation_journal.mjs', 'tools/wave5/preparation_journal.test.mjs',
  'tools/wave5/preparation_file_sink.mjs', 'tools/wave5/preparation_file_sink.test.mjs',
  'tools/wave5/preparation_file_sink_peer_20261013.test.mjs',
  'tools/wave5/preparation_journal_peer_20261013.test.mjs',
  'tools/wave5/membership_preparation_peer_20261013.test.mjs',
  'tools/wave5/verify_preparation_peer_20261013.mjs',
  'tools/wave5/probe_preparation_journal_20261013_r5.mjs',
  'tools/wave5/audit_installed_plan_peer_20261013_r5.mjs',
  'tools/wave5/write_provider_peer_review_20261013.mjs',
  'tools/wave5/verify_provider_peer_20261013.mjs',
  `${folder}/complete-app-runtime-review-20261010-r5.json`, `${folder}/runtime-owner-decision-20261012-r5.json`,
  `${folder}/runtime-harness-peer-review-20261012-r5.json`, `${folder}/runtime-fixture-contract-20261012-r5.json`,
  `${folder}/runtime-bootstrap-complete-app-20261009.sql`,
  `${folder}/installed-verification-plan-20261012-r5-a2.json`,
  `${folder}/installed-baseline-rename-fingerprints-20261012-r5.sql`,
  `${folder}/installed-catalog-verification-20261012-r5-a2.sql`,
  `${folder}/installed-strict-metadata-20261012-r5.sql`,
  `${folder}/installed-preservation-fingerprints-20261012-r5.sql`,
  `${folder}/supabase-provider-local-verification-20261012-r5-a8.json`,
  `${folder}/supabase-provider-local-verification-20261012-r5-a8.tap`,
  `${folder}/supabase-provider-preparation-plan-20261012-r5-a7.json`,
  `${folder}/supabase-provider-late-socket-probe-20261012-r5-a1.json`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a3.json`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a3.tap`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a4.json`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a4.tap`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a14.json`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a14.tap`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a16.json`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a16.tap`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a17.json`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a17.tap`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a19.json`,
  `${folder}/supabase-provider-local-verification-20261013-r5-a19.tap`,
  `${folder}/supabase-provider-preparation-plan-20261013-r5-a1.json`,
  `${folder}/supabase-provider-preparation-plan-20261013-r5-${preparationPlanAttempt}.json`,
  `${folder}/independent-provider-local-verification-20261013-r5-a3.json`,
  `${folder}/independent-provider-local-verification-20261013-r5-a3.tap`,
  `${folder}/preparation-journal-peer-probe-20261013-r5-a1.json`,
  `${folder}/preparation-journal-independent-verification-20261013-r5-a1.json`,
  `${folder}/preparation-journal-independent-verification-20261013-r5-a1.tap`,
  `${folder}/membership-preparation-independent-verification-20261013-r5-a1.json`,
  `${folder}/membership-preparation-independent-verification-20261013-r5-a1.tap`,
  `${folder}/installed-verification-plan-peer-audit-20261013-r5.json`,
];
const names = (await fs.readdir(path.join(root, 'tools/wave5'))).filter(name =>
  /\.mjs$/.test(name) && !explicit.includes(`tools/wave5/${name}`));
const sources = [...new Set([...explicit, ...names.map(name => `tools/wave5/${name}`)])];
const bind = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, sha256: hashBytes(bytes), bytes: bytes.length }; };
const before = await Promise.all(sources.map(bind));
const handle = await fs.open(path.join(root, `${prefix}.json`), 'wx', 0o600);
const logHandle = await fs.open(path.join(root, `${prefix}.tap`), 'wx', 0o600);
const testFiles = (await fs.readdir(path.join(root, 'tools/wave5')))
  .filter(name => /\.test\.mjs$/.test(name)).sort().map(name => `tools/wave5/${name}`);
const command = ['--test', '--test-isolation=none', '--test-reporter=tap', ...testFiles];
let output = '', childExitCode = null, childSignal = null, spawnFailure = null;
const actualStartedAt = new Date().toISOString();
try {
  await new Promise(resolve => {
    const child = spawn(process.execPath, command, { cwd: root, windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { SystemRoot: process.env.SystemRoot, WINDIR: process.env.WINDIR,
        TEMP: process.env.TEMP, TMP: process.env.TMP } });
    child.stdout.on('data', chunk => { output += chunk.toString('utf8'); });
    child.stderr.on('data', chunk => { output += chunk.toString('utf8'); });
    child.on('error', error => { spawnFailure = ['EPERM', 'EACCES', 'ENOENT'].includes(error.code) ? error.code : 'SPAWN_FAILED'; });
    child.on('close', (code, signal) => { childExitCode = code; childSignal = signal; resolve(); });
  });
  const actualFinishedAt = new Date().toISOString(), after = await Promise.all(sources.map(bind));
  const count = name => { const found = output.match(new RegExp(`^# ${name} (\\d+)$`, 'm'));
    return found ? Number(found[1]) : null; };
  const summary = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name => [name, count(name)]));
  const selectedSourcesUnchanged = hashJson(before) === hashJson(after);
  const passed = childExitCode === 0 && summary.tests > 0 && summary.tests === summary.pass
    && ['fail', 'cancelled', 'skipped', 'todo'].every(name => summary[name] === 0) && selectedSourcesUnchanged;
  await logHandle.writeFile(output); await logHandle.sync();
  const record = { kind: 'independent-controlled-wave5-provider-local-verification', projectId: PROJECT_ID,
    actualStartedAt, actualFinishedAt, nodeVersion: process.version, command: ['node', ...command],
    childExitCode, childSignal, spawnFailure, passed, summary, selectedSourcesUnchanged,
    filesBefore: before, filesAfter: after,
    log: { path: `${prefix}.tap`, sha256: hashBytes(output), bytes: Buffer.byteLength(output) },
    controlledInMemoryMutationProbes: ['mutable-db-tls', 'quota-date-truncation', 'always-true-synthetic-target'],
    earlierFailurePreserved: `${folder}/supabase-provider-local-verification-20261012-r5-a8.json`,
    executedLive: false, realPasswordsOrTokensRead: false, fabricatedJwtOrAuthRows: false,
    networkCalls: 0, authWrites: 0, databaseCalls: 0, sdkJobs: 0, nativeActions: 0,
    concretePrivateFactoryReviewed: false, completePrivateFacilitiesReady: false,
    publicEncryptedSinkSourceReviewed: true, controlledTemporaryFilesystemPersistenceTested: true,
    ownerAcceptedCriteria: 3, ownerCriteria: 109,
    gates: { installedSql: false, genuineMfa: false, authenticatedNative: false, actualDelivery: false,
      actualModelUsage: false, independentSessionContention: false, targetScaleLoad: false, ownerAcceptance: false },
    limitation: 'Fresh independent local controlled tests and in-memory regression mutations only. No source is replaced, no live/private facility is invoked and no runtime gate is promoted.' };
  const bytes = JSON.stringify(record, null, 2) + '\n';
  await handle.writeFile(bytes); await handle.sync();
  process.stdout.write(JSON.stringify({ path: `${prefix}.json`, sha256: hashBytes(bytes), passed, summary, selectedSourcesUnchanged }) + '\n');
  if (!passed) process.exitCode = 1;
} finally { await handle.close(); await logHandle.close(); }
