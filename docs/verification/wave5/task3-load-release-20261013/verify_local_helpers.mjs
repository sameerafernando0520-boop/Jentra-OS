import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

const folder = path.dirname(fileURLToPath(import.meta.url)), root = path.resolve(folder, '../../../..');
const attempt = process.argv[2] ?? 'a1';
if (!/^a[1-9][0-9]*$/.test(attempt)) throw Error('NEW_LOCAL_ATTEMPT_REQUIRED');
const suffix = attempt === 'a1' ? '' : '-' + attempt;
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const tests = ['tools/wave5/runtime_coordinator.test.mjs', 'tools/wave5/supabase_provider.test.mjs',
  'tools/wave5/supabase_provider_plan.test.mjs', 'tools/wave5/supabase_management_read.test.mjs',
  'tools/wave5/preparation_journal.test.mjs', 'tools/wave5/preparation_file_sink.test.mjs',
  'tools/wave5/supabase_provider_peer_20261013.test.mjs', 'tools/wave5/provider_live_response_regression_20261013_r5.test.mjs',
  'tools/wave5/membership_preparation_peer_20261013.test.mjs', 'tools/wave5/preparation_journal_peer_20261013.test.mjs',
  'tools/wave5/preparation_file_sink_peer_20261013.test.mjs'];
const publicModules = (await fs.readdir(path.join(root, 'tools/wave5'))).filter(name => name.endsWith('.mjs')).map(name => 'tools/wave5/' + name);
const localSources = ['postgres_transport.mjs', 'external_observer.mjs', 'transport_helpers.test.mjs',
  'verify_local_helpers.mjs', 'package.json', 'package-lock.json'].map(name => path.relative(root, path.join(folder, name)).replaceAll('\\', '/'));
const reviews = ['docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',
  'docs/verification/wave5/runtime-owner-decision-20261012-r5.json', 'docs/verification/wave5/runtime-harness-review-20261012-r6.json'];
const sources = [...publicModules, ...localSources, ...reviews].sort();
const snapshots = async () => Promise.all(sources.map(async name => { const bytes = await fs.readFile(path.join(root, name));
  return { path: name, bytes: bytes.length, sha256: hash(bytes) }; }));
const publicEnvironment = Object.fromEntries(['SystemRoot', 'WINDIR', 'TEMP', 'TMP'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
async function run(command) {
  const startedAt = new Date().toISOString(); let output = '', exitCode = null;
  await new Promise(resolve => {
    const child = spawn(process.execPath, command, { cwd: root, windowsHide: true, env: publicEnvironment, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.on('data', chunk => { output += chunk.toString('utf8'); });
    child.stderr.on('data', chunk => { output += chunk.toString('utf8'); });
    child.on('error', () => { output += '\nLOCAL_CHILD_SPAWN_FAILED\n'; });
    child.on('close', code => { exitCode = code; resolve(); });
  });
  const counts = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name =>
    [name, Number(output.match(new RegExp(`^# ${name} (\\d+)$`, 'm'))?.[1] ?? NaN)]));
  return { command: ['node', ...command], startedAt, finishedAt: new Date().toISOString(), exitCode,
    counts: Number.isFinite(counts.tests) ? counts : null, output };
}
const before = await snapshots();
const helper = await run(['--test', '--test-isolation=none', '--test-reporter=tap', ...localSources.filter(p => p.endsWith('.test.mjs'))]);
const provider = await run(['--test', '--test-isolation=none', '--test-reporter=tap', ...tests]);
const offline = await run(['tools/wave5/run_runtime_verification.mjs', '--review', reviews[0], '--harness-review', reviews[2]]);
const after = await snapshots();
const same = hash(JSON.stringify(before)) === hash(JSON.stringify(after));
const log = `Helper controlled tests\n${helper.output}\nPublic provider controlled tests\n${provider.output}\nOffline harness validation\n${offline.output}`;
const save = async (name, bytes) => { const handle = await fs.open(path.join(folder, name), 'wx');
  try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); } return hash(bytes); };
const logSha256 = await save(`local-verification${suffix}.tap`, log);
const summary = run => ({ ...run, output: undefined, outputSha256: hash(run.output) });
const hardware = { platform: os.platform(), release: os.release(), cpuModel: os.cpus()[0]?.model,
  logicalCpuCount: os.cpus().length, totalMemoryBytes: os.totalmem(), availableMemoryBytes: os.freemem() };
const record = { kind: 'controlled-local-load-release-helper-verification', observedAt: new Date().toISOString(),
  nodeVersion: process.version, helper: summary(helper), provider: summary(provider), offlineHarness: summary(offline),
  helperPassed: helper.exitCode === 0 && helper.counts?.tests === helper.counts?.pass && helper.counts?.fail === 0,
  providerPassed: provider.exitCode === 0 && provider.counts?.tests === provider.counts?.pass && provider.counts?.fail === 0,
  offlineHarnessPassed: offline.exitCode === 0, sourcesUnchangedDuringRun: same,
  filesBefore: before, filesAfter: after, log: { path: path.relative(root, path.join(folder, `local-verification${suffix}.tap`)).replaceAll('\\', '/'), sha256: logSha256 },
  hardware, hardwareSha256: hash(JSON.stringify(hardware)), actualPostgresConnection: false,
  liveAuthCreated: 0, genuineLoadSessionsCreated: 0, liveSqlWrites: 0, SDKJobs: 0, actualLoadPerformed: false,
  completeExternalTransportCaptureConfigured: false, productionReleased: false,
  boundary: 'Controlled Node tests and offline source bindings only. No private database credential, real Auth session, actual egress capture, P95 or load result is manufactured.' };
const recordSha256 = await save(`local-verification${suffix}.json`, JSON.stringify(record, null, 2) + '\n');
console.log(JSON.stringify({ record: `local-verification${suffix}.json`, sha256: recordSha256,
  helper: helper.counts, provider: provider.counts, helperPassed: record.helperPassed,
  providerPassed: record.providerPassed, offlineHarnessPassed: record.offlineHarnessPassed, sourcesUnchangedDuringRun: same }));
