import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { PROJECT_ID, hashBytes, hashJson } from './runtime_contract.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url)), attempt = process.argv[2], mode = process.argv[3] ?? 'journal';
if (!/^a[1-9][0-9]*$/.test(attempt ?? '') || !['journal', 'membership'].includes(mode)) throw new Error('NEW_LOCAL_ATTEMPT_REQUIRED');
const prefix = `docs/verification/wave5/${mode === 'journal' ? 'preparation-journal' : 'membership-preparation'}-independent-verification-20261013-r5-${attempt}`;
const sources = ['tools/wave5/preparation_journal.mjs', 'tools/wave5/preparation_journal_peer_20261013.test.mjs',
  'tools/wave5/verify_preparation_peer_20261013.mjs', 'tools/wave5/runtime_contract.mjs',
  ...(mode === 'membership' ? ['tools/wave5/supabase_membership_fixture.mjs', 'tools/wave5/supabase_read_store.mjs',
    'tools/wave5/supabase_runtime_provider.mjs', 'tools/wave5/membership_preparation_peer_20261013.test.mjs',
    'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',
    'docs/verification/wave5/runtime-owner-decision-20261012-r5.json'] : [])];
const bind = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, sha256: hashBytes(bytes), bytes: bytes.length }; };
const before = await Promise.all(sources.map(bind)), actualStartedAt = new Date().toISOString();
const recordHandle = await fs.open(path.join(root, `${prefix}.json`), 'wx', 0o600),
  tapHandle = await fs.open(path.join(root, `${prefix}.tap`), 'wx', 0o600);
let output = '', childExitCode = null, childSignal = null;
const command = ['--test', '--test-isolation=none', '--test-reporter=tap',
  mode === 'journal' ? 'tools/wave5/preparation_journal_peer_20261013.test.mjs' : 'tools/wave5/membership_preparation_peer_20261013.test.mjs'];
try {
  await new Promise(resolve => {
    const child = spawn(process.execPath, command, { cwd: root, windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'], env: { SystemRoot: process.env.SystemRoot, WINDIR: process.env.WINDIR,
        TEMP: process.env.TEMP, TMP: process.env.TMP } });
    child.stdout.on('data', chunk => { output += chunk.toString('utf8'); });
    child.stderr.on('data', chunk => { output += chunk.toString('utf8'); });
    child.on('error', () => { output += '\nPEER_TEST_SPAWN_FAILED\n'; });
    child.on('close', (code, signal) => { childExitCode = code; childSignal = signal; resolve(); });
  });
  const actualFinishedAt = new Date().toISOString(), after = await Promise.all(sources.map(bind));
  const count = name => { const found = output.match(new RegExp(`^# ${name} (\\d+)$`, 'm'));
    return found ? Number(found[1]) : null; };
  const summary = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name => [name, count(name)]));
  const selectedSourcesUnchanged = hashJson(before) === hashJson(after), passed = childExitCode === 0
    && summary.tests === (mode === 'journal' ? 2 : 1) && summary.pass === summary.tests && summary.fail === 0 && selectedSourcesUnchanged;
  await tapHandle.writeFile(output); await tapHandle.sync();
  const value = { kind: `independent-controlled-wave5-${mode}-preparation-verification`, projectId: PROJECT_ID,
    actualStartedAt, actualFinishedAt, nodeVersion: process.version, command: ['node', ...command],
    childExitCode, childSignal, summary, selectedSourcesUnchanged, passed, filesBefore: before, filesAfter: after,
    log: { path: `${prefix}.tap`, sha256: hashBytes(output), bytes: Buffer.byteLength(output) },
    controlledOnly: true, executedLive: false, realCredentialsRead: false, databaseCalls: 0, authWrites: 0,
    networkCalls: 0, sdkJobs: 0, nativeActions: 0, concretePrivateSinkReviewed: false,
    limitation: 'Actual local independent assertions over controlled in-memory receipts only. No durable private facility or real fixture was invoked.' };
  const bytes = JSON.stringify(value, null, 2) + '\n'; await recordHandle.writeFile(bytes); await recordHandle.sync();
  process.stdout.write(JSON.stringify({ path: `${prefix}.json`, sha256: hashBytes(bytes), passed, summary, selectedSourcesUnchanged }) + '\n');
  if (!passed) process.exitCode = 1;
} finally { await recordHandle.close(); await tapHandle.close(); }
