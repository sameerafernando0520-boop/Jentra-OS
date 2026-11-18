import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { lstat, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [snapshotArgument, outputArgument, configPath, approvedProject, version, buildNumber] = process.argv.slice(2);
if (process.argv.length !== 8 || !/^\d+\.\d+\.\d+$/.test(version) ||
    !/^\d{1,5}$/.test(buildNumber) || Number(buildNumber) < 1 || Number(buildNumber) > 65535) {
  throw Error('ADMIN_RELEASE_ARGUMENTS_INVALID');
}

const snapshot = path.resolve(snapshotArgument);
const output = path.resolve(outputArgument);
for (const directory of [snapshot, output]) {
  if (!path.relative(root, directory).startsWith(`build${path.sep}`)) throw Error('OUTPUT_MUST_BE_UNDER_WORKSPACE_BUILD');
  try {
    await lstat(directory);
    throw Error('NEW_OUTPUT_DIRECTORY_REQUIRED');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

const config = { JENTRA_ENVIRONMENT: 'development' };
let projectRef = null;
if (configPath !== '-') {
  const input = JSON.parse(await readFile(configPath, 'utf8'));
  const allowed = new Set(['JENTRA_ENVIRONMENT', 'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_PROJECT_REF']);
  if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some((key) => !allowed.has(key)) ||
      input.JENTRA_ENVIRONMENT !== 'development' || typeof input.SUPABASE_PUBLISHABLE_KEY !== 'string') {
    throw Error('DEVELOPMENT_PUBLIC_CONFIG_REQUIRED');
  }
  const url = new URL(input.SUPABASE_URL);
  projectRef = url.hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)?.[1];
  if (!projectRef || url.origin !== `https://${projectRef}.supabase.co` || url.pathname !== '/' ||
      url.username || url.password || url.search || url.hash ||
      projectRef !== approvedProject || (input.SUPABASE_PROJECT_REF && input.SUPABASE_PROJECT_REF !== projectRef)) {
    throw Error('EXPLICIT_APPROVED_DEVELOPMENT_PROJECT_REQUIRED');
  }
  const key = input.SUPABASE_PUBLISHABLE_KEY;
  if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) {
    let claims;
    try {
      claims = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString('utf8'));
    } catch {
      throw Error('PUBLIC_CONFIG_PUBLIC_KEY_REQUIRED');
    }
    if (claims.role !== 'anon' || claims.ref !== projectRef) throw Error('PUBLIC_CONFIG_PUBLIC_KEY_REQUIRED');
  }
  config.SUPABASE_URL = url.origin;
  config.SUPABASE_PUBLISHABLE_KEY = key;
} else if (approvedProject !== '-') {
  throw Error('APPROVED_PROJECT_REQUIRES_PUBLIC_CONFIG');
}

const git = (args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const selected = (relative) => ['pubspec.yaml', 'pubspec.lock'].includes(relative) ||
  /^apps\/[^/]+\/pubspec.yaml$/.test(relative) ||
  /^apps\/jentra_desktop\/(lib|windows)\//.test(relative) ||
  /^packages\/(jentra_domain|jentra_platform|jentra_design_system)\/(pubspec\.yaml|lib\/|assets\/|fonts\/)/.test(relative) ||
  relative.startsWith('tools/admin-release/');
const forbidden = (relative) => /(^|\/)(build|\.dart_tool|ephemeral|\.plugin_symlinks|test|failures)(\/|$)/.test(relative) ||
  /(^|\/)(\.env[^/]*|[^/]*firebase-adminsdk[^/]*|[^/]*service[_-]?account[^/]*|[^/]*private[_-]?key[^/]*)$/i.test(relative) ||
  /generated_plugin_registrant\.(cc|h)$|generated_plugins\.cmake$|\.(pfx|p12|pem|key)$/i.test(relative);
const sourcePaths = [...new Set(git(['ls-files', '--cached', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean))]
  .filter((relative) => selected(relative) && !forbidden(relative)).sort();
const entrypoint = 'apps/jentra_desktop/lib/main_admin.dart';
if (!sourcePaths.includes(entrypoint)) throw Error('ADMIN_ENTRYPOINT_SOURCE_REQUIRED');
const icon = 'apps/jentra_desktop/windows/runner/resources/j_panel.ico';
if (!sourcePaths.includes(icon)) throw Error('ADMIN_ICON_SOURCE_REQUIRED');

const product = 'J panel';
const executable = 'jentra_administrator.exe';
const inputs = [];
const buildFiles = [];
const overlays = [];
await mkdir(snapshot, { recursive: true });
await mkdir(output, { recursive: true });
for (const relative of sourcePaths) {
  const source = path.join(root, relative);
  const target = path.join(snapshot, relative);
  if (!(await lstat(source)).isFile()) throw Error('SOURCE_REGULAR_FILE_REQUIRED');
  const original = await readFile(source);
  const windows = 'apps/jentra_desktop/windows/';
  let content = original;
  if (relative === `${windows}CMakeLists.txt`) {
    content = Buffer.from(original.toString().replace(/set\(BINARY_NAME "jentra_desktop"\)/, 'set(BINARY_NAME "jentra_administrator")'));
  } else if (relative === `${windows}runner/main.cpp`) {
    content = Buffer.from(original.toString().replace(/window\.Create\(L"[^"]+", origin, size\)/, `window.Create(L"${product}", origin, size)`));
  } else if (relative === `${windows}runner/Runner.rc`) {
    content = Buffer.from(original.toString().replace(/(VALUE "(?:FileDescription|ProductName)", ")[^"]+/g, `$1${product}`)
      .replace(/(VALUE "InternalName", ")[^"]+/, '$1jentra_administrator')
      .replace(/(VALUE "OriginalFilename", ")[^"]+/, `$1${executable}`)
      .replace('app_icon.ico', 'j_panel.ico'));
  }
  const before = sha256(original);
  const after = sha256(content);
  if (content !== original) {
    if (before === after) throw Error(`ADMIN_PRODUCT_OVERLAY_FAILED: ${relative}`);
    overlays.push({ path: relative, beforeSha256: before, afterSha256: after });
  }
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, content);
  inputs.push({ path: relative, bytes: original.length, sha256: before });
  buildFiles.push({ path: relative, bytes: content.length, sha256: after });
}
if (overlays.length !== 3) throw Error('ADMIN_PRODUCT_OVERLAYS_REQUIRED');
for (const item of inputs) {
  if (sha256(await readFile(path.join(root, item.path))) !== item.sha256) throw Error('SOURCE_CHANGED_DURING_PREPARATION');
}
const configBytes = Buffer.from(JSON.stringify(config, null, 2) + '\n');
await writeFile(path.join(snapshot, 'public-build-config.json'), configBytes);
buildFiles.push({ path: 'public-build-config.json', bytes: configBytes.length, sha256: sha256(configBytes) });
buildFiles.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
const sourceSha256 = sha256(Buffer.from(buildFiles.map((file) => `${file.path}:${file.sha256}\n`).join('')));
const revision = git(['rev-parse', 'HEAD']).trim();
const preparedAtUtc = new Date().toISOString();
const identity = {
  version: `${version}+${buildNumber}`,
  versionName: version,
  buildNumber: Number(buildNumber),
  revision,
  sourceSha256,
  preparedAtUtc,
  channel: 'development',
  projectRef,
  sourceDirty: git(['status', '--porcelain', '--untracked-files=normal', '--', 'apps/jentra_desktop', 'packages', 'tools/admin-release']).trim().length > 0,
  releaseId: `${version}-${buildNumber}-development-${sourceSha256.slice(0, 12)}`,
  applicationProductName: product,
  executable,
};
await writeFile(path.join(output, 'source-manifest.json'), JSON.stringify({ schemaVersion: 1, identity, entrypoint, inputs, buildFiles, overlays, snapshot }, null, 2) + '\n');
console.log(JSON.stringify({ snapshot, output, identity, sourceFiles: buildFiles.length }));
