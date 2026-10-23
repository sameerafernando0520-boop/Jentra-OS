import { createHash } from 'node:crypto';
import { copyFile, mkdir, readFile, readdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const allowedOrigin = 'https://xpdoufauvrbdmxgngetv.supabase.co';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const forbiddenName = /(^|\/)(\.[^/]+|node_modules)(\/|$)|firebase-adminsdk|service[-_]?account|google-services\.json|\.(?:map|pem|pfx|p12|key|env)$/i;

export function assertPublicContent(bytes, relativeName) {
  if (forbiddenName.test(relativeName)) throw new Error(`Private or debug file rejected: ${relativeName}`);
  if (!/\.(?:html|js|json|css|txt)$/.test(relativeName)) return;
  const text = bytes.toString('utf8');
  if (/-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|sb_secret_[A-Za-z0-9_-]{8,}/.test(text)) {
    throw new Error(`Secret material rejected in public artifact: ${relativeName}`);
  }
  for (const match of text.matchAll(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g)) {
    try {
      if (JSON.parse(Buffer.from(match[0].split('.')[1], 'base64url').toString()).role === 'service_role') {
        throw new Error(`Privileged server credential rejected in public artifact: ${relativeName}`);
      }
    } catch (error) {
      if (error.message.startsWith('Privileged server credential')) throw error;
    }
  }
}

export async function inspectBuild(buildDirectory) {
  const root = await realpath(buildDirectory);
  const files = [];
  async function visit(directory, prefix = '') {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const name = `${prefix}${entry.name}`;
      // Flutter records its local build identity here. This exact root file
      // is metadata, not a served app asset; other hidden files still fail.
      if (name === '.last_build_id' && entry.isFile()) continue;
      if (entry.isSymbolicLink()) throw new Error(`Symlink rejected in public artifact: ${name}`);
      if (entry.isDirectory()) {
        if (forbiddenName.test(`${name}/`)) throw new Error(`Private directory rejected: ${name}`);
        await visit(path.join(directory, entry.name), `${name}/`);
      } else if (entry.isFile()) {
        const bytes = await readFile(path.join(directory, entry.name));
        if (bytes.length > 128 * 1024 * 1024) throw new Error(`Oversized public artifact: ${name}`);
        assertPublicContent(bytes, name);
        files.push({ path: name, bytes: bytes.length, sha256: digest(bytes) });
      } else {
        throw new Error(`Unsupported filesystem entry: ${name}`);
      }
    }
  }
  await visit(root);
  files.sort((a, b) => a.path.localeCompare(b.path));
  const names = new Set(files.map(file => file.path));
  for (const required of ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'manifest.json', '404.html', 'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm']) {
    if (!names.has(required)) throw new Error(`Incomplete Flutter web build: ${required}`);
  }
  const bootstrap = await readFile(path.join(root, 'flutter_bootstrap.js'), 'utf8');
  if (bootstrap.includes('{{') || !bootstrap.includes("canvasKitBaseUrl: 'canvaskit/'") || /serviceWorkerSettings\s*:/.test(bootstrap)) {
    throw new Error('Build must use the reviewed local-engine, noncaching bootstrap.');
  }
  const index = await readFile(path.join(root, 'index.html'), 'utf8');
  if (index.includes('$FLUTTER_BASE_HREF') || !/<base href="\/">/.test(index)) {
    throw new Error('Build must target the Hosting origin root.');
  }
  const program = await readFile(path.join(root, 'main.dart.js'), 'utf8');
  if (!program.includes(allowedOrigin)) throw new Error('Compiled app is missing the approved Supabase public origin.');
  const foreignOrigins = [...program.matchAll(/https:\/\/[a-z0-9-]+\.supabase\.co/gi)].map(match => match[0]).filter(origin => origin !== allowedOrigin);
  if (foreignOrigins.length) throw new Error('Compiled app contains a different Supabase project origin.');
  return { root, files, buildSha256: digest(JSON.stringify(files)) };
}

export async function stageBuild(buildDirectory, outputParent = path.join(toolDirectory, '.staging')) {
  const inspected = await inspectBuild(buildDirectory);
  const releaseDirectory = path.resolve(outputParent, `${new Date().toISOString().replace(/[:.]/g, '-')}-${inspected.buildSha256.slice(0, 12)}`);
  const publicDirectory = path.join(releaseDirectory, 'public');
  // Fresh immutable staging avoids stale assets and never recursively clears an
  // existing installation, checkout or previous preview package.
  await mkdir(releaseDirectory, { recursive: false });
  await mkdir(publicDirectory);
  for (const file of inspected.files) {
    const destination = path.join(publicDirectory, ...file.path.split('/'));
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(path.join(inspected.root, ...file.path.split('/')), destination);
    if (digest(await readFile(destination)) !== file.sha256) throw new Error('Build changed while being staged.');
  }
  await copyFile(path.join(toolDirectory, 'firebase.json'), path.join(releaseDirectory, 'firebase.json'));
  const manifest = {
    schema: 1,
    site: 'jentra-os',
    project: 'jentra-os',
    deployment: 'preview-only',
    supabaseOrigin: allowedOrigin,
    createdAt: new Date().toISOString(),
    buildSha256: inspected.buildSha256,
    hostingConfigSha256: digest(await readFile(path.join(releaseDirectory, 'firebase.json'))),
    files: inspected.files,
  };
  await writeFile(path.join(releaseDirectory, 'release-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`, { flag: 'wx' });
  return { releaseDirectory, buildSha256: inspected.buildSha256, files: inspected.files.length };
}

export async function verifyStage(releaseDirectory) {
  const manifest = JSON.parse(await readFile(path.join(releaseDirectory, 'release-manifest.json'), 'utf8'));
  if (manifest.schema !== 1 || manifest.site !== 'jentra-os' || manifest.project !== 'jentra-os' || manifest.deployment !== 'preview-only' || manifest.supabaseOrigin !== allowedOrigin) {
    throw new Error('Preview package identity does not match this deployment tool.');
  }
  const inspected = await inspectBuild(path.join(releaseDirectory, 'public'));
  if (inspected.buildSha256 !== manifest.buildSha256 || JSON.stringify(inspected.files) !== JSON.stringify(manifest.files)) {
    throw new Error('Preview package files differ from the reviewed manifest.');
  }
  const actualConfig = await readFile(path.join(releaseDirectory, 'firebase.json'));
  const reviewedConfig = await readFile(path.join(toolDirectory, 'firebase.json'));
  if (digest(actualConfig) !== manifest.hostingConfigSha256 || !actualConfig.equals(reviewedConfig)) {
    throw new Error('Preview Hosting configuration differs from the reviewed configuration.');
  }
  return { buildSha256: inspected.buildSha256, files: inspected.files.length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [mode, directory] = process.argv.slice(2);
    if (!['stage', 'verify'].includes(mode) || !directory || process.argv.length !== 4) {
      throw new Error('Usage: node tools/employee-web/prepare.mjs stage <Flutter-build-directory> | verify <release-directory>');
    }
    if (mode === 'stage') await mkdir(path.join(toolDirectory, '.staging'), { recursive: true });
    console.log(JSON.stringify(mode === 'stage' ? await stageBuild(directory) : await verifyStage(directory)));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
