import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root = fileURLToPath(new URL('../../', import.meta.url));
const attempt = process.argv[2];
if (!/^a[1-9][0-9]*$/.test(attempt ?? '') || process.argv.length !== 3) throw Error('NEW_ATTEMPT_REQUIRED');
const prefix = `docs/verification/wave5/management-installer-local-verification-20261013-r5-${attempt}`;
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const sourceNames = ['tools/wave5/approved_management_installer.mjs', 'tools/wave5/approved_management_installer.test.mjs',
  'scripts/wave5/verify_management_installer_20261013_r5.mjs', 'scripts/wave5/prepare_private_owner_access_20261013_r5.ps1',
  'dist/Jentra OS Private Owner Access 20261013 r5.cmd', 'tools/wave5/runtime_contract.mjs',
  'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',
  'docs/verification/wave5/runtime-owner-decision-20261012-r5.json',
  'docs/verification/wave5/approved-live-resume-20261013-r5-raw.json',
  'docs/verification/wave5/complete-live-preflight-20261010-r2.sql',
  'docs/verification/wave5/installed-baseline-rename-fingerprints-20261012-r5.sql'];
const bind = async file => { const bytes = await fs.readFile(path.join(root, file)); return { path: file, bytes: bytes.length, sha256: sha(bytes) }; };
const before = await Promise.all(sourceNames.map(bind));
const record = await fs.open(path.join(root, prefix + '.json'), 'wx');
const actualStartedAt = new Date().toISOString();
const runs = [];
try {
  for (const command of [
    ['--test', '--test-isolation=none', '--test-reporter=tap', 'tools/wave5/approved_management_installer.test.mjs'],
    ['tools/wave5/approved_management_installer.mjs', '--validate']
  ]) {
    let output = '', exitCode = null, spawnFailure = null;
    await new Promise(resolve => {
      const child = spawn(process.execPath, command, { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
        env: { SystemRoot: process.env.SystemRoot, WINDIR: process.env.WINDIR, TEMP: process.env.TEMP, TMP: process.env.TMP } });
      child.stdout.on('data', bytes => { output += bytes.toString('utf8'); });
      child.stderr.on('data', bytes => { output += bytes.toString('utf8'); });
      child.on('error', error => { spawnFailure = ['EPERM', 'EACCES', 'ENOENT'].includes(error.code) ? error.code : 'SPAWN_FAILED'; });
      child.on('close', code => { exitCode = code; resolve(); });
    });
    const logPath = prefix + '-run' + (runs.length + 1) + '.txt';
    await fs.writeFile(path.join(root, logPath), output, { flag: 'wx' });
    runs.push({ command: ['node', ...command], exitCode, spawnFailure, output,
      log: { path: logPath, sha256: sha(output), bytes: Buffer.byteLength(output) } });
  }
  const after = await Promise.all(sourceNames.map(bind));
  const testCount = name => Number(runs[0].output.match(new RegExp(`^# ${name} (\\d+)$`, 'm'))?.[1] ?? NaN);
  let validation; try { validation = JSON.parse(runs[1].output.trim()); } catch { validation = null; }
  const passed = runs.every(run => run.exitCode === 0) && testCount('tests') === 6 && testCount('pass') === 6
    && ['fail', 'cancelled', 'skipped', 'todo'].every(name => testCount(name) === 0)
    && validation?.passed === true && validation.inspectedBindings === 5539 && validation.networkCalls === 0
    && JSON.stringify(before) === JSON.stringify(after);
  const value = { kind: 'wave5-management-installer-local-verification', actualStartedAt, actualFinishedAt: new Date().toISOString(),
    executedBy: 'root following delegated agent usage limit', passed, tests: { total: testCount('tests'), passed: testCount('pass'), failed: testCount('fail') },
    sourceBefore: before, sourceAfter: after, selectedSourcesUnchanged: JSON.stringify(before) === JSON.stringify(after),
    validation, runs: runs.map(({ output, ...run }) => run), credentialsRead: false, networkCalls: 0, databaseWrites: 0,
    authWrites: 0, sdkJobs: 0, nativeActions: 0, liveInstallerUsed: false,
    limitation: 'Controlled guards/TLS late-socket tests and exact approved-file validation only. No valid private token or live Management API request.' };
  const text = JSON.stringify(value, null, 2) + '\n'; await record.writeFile(text); await record.sync();
  process.stdout.write(JSON.stringify({ path: prefix + '.json', sha256: sha(text), passed, tests: value.tests, validation }) + '\n');
  if (!passed) process.exitCode = 1;
} finally { await record.close(); }
