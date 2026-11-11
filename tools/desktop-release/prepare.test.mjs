import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, readFile, writeFile, copyFile, rm, lstat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isReleaseBuildPath } from './source_boundaries.mjs';

const exec = promisify(execFile);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = path.join(root, 'build', 'desktop-release-prepare-test-' + randomUUID());
await mkdir(fixture, { recursive: true });
after(async () => {
  assert.equal(path.dirname(fixture), path.join(root, 'build'));
  assert.ok(path.basename(fixture).startsWith('desktop-release-prepare-test-'));
  assert.equal((await lstat(fixture)).isSymbolicLink(), false);
  await rm(fixture, { recursive: true });
});
// Exercise the actual preparer in a tiny disposable repository. Real app/font
// trees are not needed to test selection, feature defines and release identity.
const fixtureRepo = path.join(fixture, 'repository');
for (const directory of ['tools/desktop-release', 'apps/jentra_desktop/lib/src', 'apps/jentra_desktop/windows/runner']) {
  await mkdir(path.join(fixtureRepo, directory), { recursive: true });
}
await copyFile(path.join(root, 'tools/desktop-release/prepare.mjs'), path.join(fixtureRepo, 'tools/desktop-release/prepare.mjs'));
await copyFile(path.join(root, 'tools/desktop-release/source_boundaries.mjs'), path.join(fixtureRepo, 'tools/desktop-release/source_boundaries.mjs'));
await writeFile(path.join(fixtureRepo, 'apps/jentra_desktop/lib/src/build_identity.dart'), '// Synthetic release input.\n');
await writeFile(path.join(fixtureRepo, 'apps/jentra_desktop/windows/runner/Runner.rc'), 'VALUE "ProductName", "Jentra OS"\n');
await writeFile(path.join(fixtureRepo, 'apps/jentra_desktop/windows/firebase-adminsdk-synthetic.json'), '{"private_key":"SYNTHETIC_ONLY"}');
await writeFile(path.join(fixtureRepo, 'pubspec.yaml'), 'name: release_preparation_fixture\n');
await exec('git', ['init', '--quiet', '--initial-branch=codex/release-fixture'], { cwd: fixtureRepo });
await exec('git', ['add', '--all'], { cwd: fixtureRepo });
await exec('git', ['-c', 'user.name=Synthetic Fixture', '-c', 'user.email=fixture@example.invalid',
  '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Synthetic release fixture'], { cwd: fixtureRepo });
const ref = 'abcdefghijklmnopqrst';
const config = { JENTRA_ENVIRONMENT: 'development', SUPABASE_URL: `https://${ref}.supabase.co`,
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_synthetic_fixture_only' };
async function prepare({ enabled = false, channel = 'development', approved, patch = {}, flags = [] } = {}) {
  const name = randomUUID();
  const configPath = path.join(fixture, name + '.json');
  const snapshot = path.join(fixtureRepo, 'build', name + '-source');
  const output = path.join(fixtureRepo, 'build', name + '-output');
  await writeFile(configPath, JSON.stringify({ ...config, JENTRA_ENVIRONMENT: channel, ...patch }));
  const args = ['tools/desktop-release/prepare.mjs', snapshot, output, configPath, channel, '0.2.0', '2202'];
  if (approved !== undefined) args.push(approved);
  if (enabled) args.push('--finance-opening-import');
  args.push(...flags);
  const { stdout } = await exec(process.execPath, args, { cwd: fixtureRepo, maxBuffer: 4 * 1024 * 1024 });
  assert.ok(!stdout.includes(config.SUPABASE_PUBLISHABLE_KEY));
  return { snapshot, output, manifest: JSON.parse(await readFile(path.join(output, 'source-manifest.json'), 'utf8')),
    defines: JSON.parse(await readFile(path.join(snapshot, 'public-build-config.json'), 'utf8')) };
}

test('explicit opening feature reaches compiler definitions and changes the exact release identity', async () => {
  const normal = await prepare();
  const opening = await prepare({ enabled: true });
  for (const [result, expected] of [[normal, false], [opening, true]]) {
    assert.equal(result.defines.FINANCE_OPENING_IMPORT_ENABLED, expected);
    assert.ok(result.manifest.inputs.every(file => !file.path.includes('firebase-adminsdk')));
    assert.deepEqual(result.manifest.identity.buildFeatures, { FINANCE_OPENING_IMPORT_ENABLED: expected });
    const feature = result.manifest.buildFiles.find(file => file.path === 'build-features.json');
    assert.ok(feature);
    const bytes = await readFile(path.join(result.snapshot, feature.path));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), feature.sha256);
    assert.deepEqual(JSON.parse(bytes), result.manifest.identity.buildFeatures);
    const records = result.manifest.buildFiles.map(file => `${file.path}:${file.sha256}\n`).join('');
    assert.equal(createHash('sha256').update(records).digest('hex'), result.manifest.identity.sourceSha256);
  }
  assert.notEqual(normal.manifest.identity.sourceSha256, opening.manifest.identity.sourceSha256);
  assert.notEqual(normal.manifest.identity.releaseId, opening.manifest.identity.releaseId);
  assert.deepEqual(normal.manifest.inputs, opening.manifest.inputs);
});

test('enabling opening routes does not bypass explicit production project selection', async () => {
  await assert.rejects(prepare({ channel: 'production', enabled: true }), /EXPLICIT_APPROVED_PRODUCTION_REFERENCE_REQUIRED/);
  await assert.rejects(prepare({ channel: 'production', enabled: true, approved: 'wrongproject' }), /EXPLICIT_APPROVED_PRODUCTION_REFERENCE_REQUIRED/);
  const approved = await prepare({ channel: 'production', enabled: true, approved: ref });
  assert.equal(approved.defines.FINANCE_OPENING_IMPORT_ENABLED, true);
  assert.equal(approved.manifest.identity.projectRef, ref);
});

test('connection JSON cannot inject compiler features', async () => {
  await assert.rejects(prepare({ patch: { FINANCE_OPENING_IMPORT_ENABLED: true } }), /PUBLIC_CONFIG_FIELDS_INVALID/);
});

test('unknown or repeated feature switches are refused', async () => {
  await assert.rejects(prepare({ flags: ['--unknown-feature'] }), /RELEASE_ARGUMENTS_INVALID/);
  await assert.rejects(prepare({ enabled: true, flags: ['--finance-opening-import'] }), /RELEASE_ARGUMENTS_INVALID/);
});

for (const [name, paths, workspace, target, expected] of [
  ['mapped drive root', path.win32, 'Q:\\', 'Q:\\build\\snapshot', true],
  ['nested Windows workspace', path.win32, 'C:\\work\\app', 'C:\\work\\app\\build\\snapshot', true],
  ['adjacent Windows workspace', path.win32, 'C:\\work\\app', 'C:\\work\\app-other\\build\\snapshot', false],
  ['another drive', path.win32, 'Q:\\', 'C:\\build\\snapshot', false],
  ['build folder itself', path.win32, 'Q:\\', 'Q:\\build', false],
  ['parent traversal', path.win32, 'Q:\\work', 'Q:\\work\\build\\..\\..\\snapshot', false],
  ['POSIX root', path.posix, '/', '/build/snapshot', true],
  ['POSIX sibling', path.posix, '/workspace/app', '/workspace/app-other/build/snapshot', false],
]) {
  test(`release output boundary: ${name}`, () => assert.equal(isReleaseBuildPath(workspace, target, paths), expected));
}
