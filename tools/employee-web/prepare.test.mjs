import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { assertPublicContent, inspectBuild, stageBuild, verifyStage, reviewedApplicationLoad } from './prepare.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
async function fixture(t) {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'jentra-employee-hosting-'));
  t.after(async () => {
    // Remove only this exact directory returned by mkdtemp; never computed app
    // or repository paths. Node owns the entire temporary fixture tree.
    await rm(temporary, { recursive: true, force: true });
  });
  const build = path.join(temporary, 'build'), stages = path.join(temporary, 'stages');
  await mkdir(path.join(build, 'canvaskit'), { recursive: true });
  await mkdir(stages);
  for (const [name, content] of Object.entries({
    'index.html': '<base href="/">',
    'main.dart.js': 'const api = "https://xpdoufauvrbdmxgngetv.supabase.co";',
    'flutter_bootstrap.js': reviewedApplicationLoad,
    'manifest.json': '{}',
    '404.html': '<title>Unavailable</title>',
    'canvaskit/canvaskit.js': '// engine fixture',
    'canvaskit/canvaskit.wasm': 'synthetic-binary',
  })) await writeFile(path.join(build, name), content);
  return { build, stages };
}

test('staging hashes and verifies an immutable public-only preview package', async t => {
  const { build, stages } = await fixture(t);
  const staged = await stageBuild(build, stages);
  assert.equal(staged.files, 7);
  assert.deepEqual(await verifyStage(staged.releaseDirectory), { buildSha256: staged.buildSha256, files: 7 });
});

for (const [name, content] of [
  ['PEM', '-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----'],
  ['Supabase server secret', 'sb_secret_syntheticnotarealkey'],
  ['privileged JWT', `${Buffer.from('{"alg":"synthetic"}').toString('base64url')}.${Buffer.from('{"role":"service_role"}').toString('base64url')}.synthetic`],
]) test(`rejects ${name} before public staging`, () => {
  assert.throws(() => assertPublicContent(Buffer.from(content), 'main.dart.js'), /rejected/);
});

test('rejects a Firebase admin credential filename even without readable text content', async t => {
  const { build } = await fixture(t);
  await writeFile(path.join(build, 'jentra-os-firebase-adminsdk-synthetic.json'), '{}');
  await assert.rejects(inspectBuild(build), /Private or debug file rejected/);
});

test('rejects maps and local environment configuration from the public artifact', () => {
  for (const name of ['main.dart.js.map', '.env.production.json', 'config/server.key', 'node_modules/package/index.js']) {
    assert.throws(() => assertPublicContent(Buffer.from('synthetic'), name), /Private or debug file/);
  }
});

test('omits only exact root Flutter build metadata while retaining hidden-file rejection', async t => {
  const { build, stages } = await fixture(t);
  await writeFile(path.join(build, '.last_build_id'), 'synthetic build identity');
  const staged = await stageBuild(build, stages);
  assert.equal(staged.files, 7);
  const manifest = JSON.parse(await readFile(path.join(staged.releaseDirectory, 'release-manifest.json'), 'utf8'));
  assert.equal(manifest.files.some(file => file.path === '.last_build_id'), false);
  await writeFile(path.join(build, '.unexpected'), 'reject this');
  await assert.rejects(inspectBuild(build), /Private or debug file/);
});

test('rejects a build configured for another Supabase project', async t => {
  const { build } = await fixture(t);
  await writeFile(path.join(build, 'main.dart.js'), 'https://different-project.supabase.co');
  await assert.rejects(inspectBuild(build), /approved Supabase public origin/);
});

test('rejects an extra Supabase origin alongside the approved one', async t => {
  const { build } = await fixture(t);
  await writeFile(path.join(build, 'main.dart.js'), 'https://xpdoufauvrbdmxgngetv.supabase.co https://different-project.supabase.co');
  await assert.rejects(inspectBuild(build), /different Supabase project origin/);
});

test('rejects unrendered bootstrap templates and caching worker registration', async t => {
  const { build } = await fixture(t);
  for (const bootstrap of ["{{flutter_js}} canvasKitBaseUrl: 'canvaskit/'", "canvasKitBaseUrl: 'canvaskit/'; serviceWorkerSettings: {};"]) {
    await writeFile(path.join(build, 'flutter_bootstrap.js'), bootstrap);
    await assert.rejects(inspectBuild(build), /reviewed local-engine, noncaching bootstrap/);
  }
});

test('accepts bundled SDK worker-option definitions without enabling an application worker', async t => {
  const { build } = await fixture(t);
  await writeFile(path.join(build, 'flutter_bootstrap.js'), `const internalSdkOptions = {serviceWorkerSettings: null};\n${reviewedApplicationLoad}\n`);
  assert.equal((await inspectBuild(build)).files.length, 7);
});

test('rejects actual application worker settings and duplicate loader invocations', async t => {
  const { build } = await fixture(t);
  const configuredWorker = reviewedApplicationLoad.replace('  config:', '  serviceWorkerSettings: {serviceWorkerVersion: 1},\n  config:');
  for (const bootstrap of [configuredWorker, `${reviewedApplicationLoad}\n${reviewedApplicationLoad}`, `${reviewedApplicationLoad}\n_flutter.loader.load({serviceWorkerSettings: {}});`]) {
    await writeFile(path.join(build, 'flutter_bootstrap.js'), bootstrap);
    await assert.rejects(inspectBuild(build), /reviewed local-engine, noncaching bootstrap/);
  }
});

test('reviewed application invocation matches the checked-in web bootstrap tail', async () => {
  const template = await readFile(path.join(here, '../../apps/jentra_employee/web/flutter_bootstrap.js'), 'utf8');
  assert.equal(template.replaceAll('\r\n', '\n').trimEnd().endsWith(reviewedApplicationLoad), true);
});

test('detects mutation of a staged compiled app before preview deployment', async t => {
  const { build, stages } = await fixture(t);
  const staged = await stageBuild(build, stages);
  await writeFile(path.join(staged.releaseDirectory, 'public', 'main.dart.js'), 'https://xpdoufauvrbdmxgngetv.supabase.co altered');
  await assert.rejects(verifyStage(staged.releaseDirectory), /differ from the reviewed manifest/);
});

test('detects a Hosting config changed after package review', async t => {
  const { build, stages } = await fixture(t);
  const staged = await stageBuild(build, stages);
  await writeFile(path.join(staged.releaseDirectory, 'firebase.json'), '{"hosting":{"site":"other-site"}}');
  await assert.rejects(verifyStage(staged.releaseDirectory), /configuration differs/);
});

test('hosting limits active origins, prevents framing and avoids cached callback URLs', async () => {
  const config = JSON.parse(await readFile(path.join(here, 'firebase.json'), 'utf8'));
  assert.equal(config.hosting.site, 'jentra-os');
  assert.equal(config.hosting.public, 'public');
  const headers = Object.fromEntries(config.hosting.headers[0].headers.map(header => [header.key, header.value]));
  assert.match(headers['Cache-Control'], /no-store/);
  assert.equal(headers['Referrer-Policy'], 'no-referrer');
  assert.match(headers['Content-Security-Policy'], /frame-ancestors 'none'/);
  assert.match(headers['Content-Security-Policy'], /connect-src 'self' https:\/\/xpdoufauvrbdmxgngetv\.supabase\.co wss:\/\/xpdoufauvrbdmxgngetv\.supabase\.co;/);
  assert.doesNotMatch(headers['Content-Security-Policy'], /'unsafe-eval'|https:\/\/\*|firebaseio|googleapis/);
  assert.match(config.hosting.rewrites[0].source, /assets\/\*\*/);
  assert.match(config.hosting.rewrites[0].source, /main\.dart\.\*/);
});

test('deployment wrapper has only a bounded named preview channel path', async () => {
  const script = await readFile(path.join(here, 'preview.ps1'), 'utf8');
  assert.match(script, /hosting:channel:deploy/);
  assert.match(script, /employee-\(qa\|preview\)/);
  assert.match(script, /--project jentra-os --config firebase.json/);
  assert.doesNotMatch(script, /hosting:clone|\bdeploy --only hosting|--only functions/);
});
