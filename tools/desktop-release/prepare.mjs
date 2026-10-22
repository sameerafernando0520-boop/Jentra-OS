import { execFileSync } from 'node:child_process';
import { copyFile, lstat, mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [snapshotArgument, outputArgument, configArgument, channel, version, buildNumber, approvedProductionRef = ''] = process.argv.slice(2);
if (!snapshotArgument || !outputArgument || !configArgument || !['development', 'production'].includes(channel) ||
    !/^\d+\.\d+\.\d+$/.test(version ?? '') || !/^\d{1,5}$/.test(buildNumber ?? '') || Number(buildNumber) > 65535) {
  throw Error('RELEASE_ARGUMENTS_INVALID');
}
const snapshot = path.resolve(snapshotArgument), output = path.resolve(outputArgument);
for (const target of [snapshot, output]) {
  if (!target.startsWith(root + path.sep) || !path.relative(root, target).startsWith('build' + path.sep)) throw Error('OUTPUT_MUST_BE_UNDER_WORKSPACE_BUILD');
  try { await lstat(target); throw Error('NEW_OUTPUT_DIRECTORY_REQUIRED'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
const config = JSON.parse(await readFile(path.resolve(configArgument), 'utf8'));
const allowed = new Set(['JENTRA_ENVIRONMENT', 'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_PROJECT_REF']);
if (!config || typeof config !== 'object' || Array.isArray(config) || Object.keys(config).some(key => !allowed.has(key))) throw Error('PUBLIC_CONFIG_FIELDS_INVALID');
if (config.JENTRA_ENVIRONMENT !== channel || typeof config.SUPABASE_PUBLISHABLE_KEY !== 'string') throw Error('PUBLIC_CONFIG_CHANNEL_OR_KEY_INVALID');
const url = new URL(config.SUPABASE_URL);
const projectRef = url.hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)?.[1];
if (!projectRef || url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) throw Error('PUBLIC_CONFIG_URL_INVALID');
if (config.SUPABASE_PROJECT_REF && config.SUPABASE_PROJECT_REF !== projectRef) throw Error('PUBLIC_CONFIG_PROJECT_MISMATCH');
const key = config.SUPABASE_PUBLISHABLE_KEY;
if (!key.startsWith('sb_publishable_')) {
  let claims;
  try { claims = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString('utf8')); } catch { throw Error('PUBLIC_CONFIG_PUBLIC_KEY_REQUIRED'); }
  if (claims.role !== 'anon' || claims.ref !== projectRef) throw Error('PUBLIC_CONFIG_PUBLIC_KEY_REQUIRED');
}
if (channel === 'production' && (!approvedProductionRef || approvedProductionRef !== projectRef)) throw Error('EXPLICIT_APPROVED_PRODUCTION_REFERENCE_REQUIRED');

const git = args => execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const selected = relative => ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'].includes(relative) ||
  /^apps\/[^/]+\/pubspec.yaml$/.test(relative) ||
  /^apps\/jentra_desktop\/(pubspec.yaml|lib\/|windows\/)/.test(relative) ||
  /^packages\/(jentra_domain|jentra_platform|jentra_design_system)\/(pubspec.yaml|lib\/|assets\/|fonts\/)/.test(relative) ||
  relative.startsWith('tools/desktop-release/');
const forbidden = relative => /(^|\/)(build|\.dart_tool|ephemeral|\.plugin_symlinks|test|failures)(\/|$)/.test(relative) ||
  /(^|\/)(\.env[^/]*|[^/]*firebase-adminsdk[^/]*|[^/]*service[_-]?account[^/]*|[^/]*private[_-]?key[^/]*)$/i.test(relative) ||
  /generated_plugin_registrant\.(cc|h)$|generated_plugins\.cmake$/.test(relative);
const paths = [...new Set(git(['ls-files', '--cached', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean))]
  .filter(relative => selected(relative) && !forbidden(relative)).sort();
if (!paths.includes('apps/jentra_desktop/lib/src/build_identity.dart')) throw Error('BUILD_IDENTITY_SOURCE_REQUIRED');
await mkdir(snapshot, { recursive: true });
await mkdir(output, { recursive: true });
const inputs = [], overlays = [];
for (const relative of paths) {
  const source = path.join(root, relative), target = path.join(snapshot, relative);
  const item = await lstat(source);
  if (!item.isFile() || item.isSymbolicLink()) throw Error('SOURCE_REGULAR_FILE_REQUIRED');
  const bytes = await readFile(source);
  await mkdir(path.dirname(target), { recursive: true });
  await copyFile(source, target);
  if (sha256(await readFile(target)) !== sha256(bytes)) throw Error('SOURCE_CHANGED_DURING_COPY');
  inputs.push({ path: relative, bytes: bytes.length, sha256: sha256(bytes) });
}
if (channel === 'development') {
  const relative = 'apps/jentra_desktop/windows/runner/Runner.rc';
  const location = path.join(snapshot, relative), original = await readFile(location);
  const changed = original.toString('utf8').replace(/(VALUE "ProductName", ")Jentra OS(".*)/, '$1Jentra OS Development$2');
  if (changed === original.toString('utf8')) throw Error('DEVELOPMENT_PRODUCT_IDENTITY_OVERLAY_FAILED');
  await writeFile(location, changed);
  overlays.push({ path: relative, reason: 'Separate development ProductName; existing user stores are not migrated or erased', beforeSha256: sha256(original), afterSha256: sha256(Buffer.from(changed)) });
}
const buildFiles = [];
for (const file of inputs) {
  if (sha256(await readFile(path.join(root, file.path))) !== file.sha256) throw Error('SOURCE_CHANGED_DURING_PREPARATION');
  const bytes = await readFile(path.join(snapshot, file.path));
  buildFiles.push({ path: file.path, bytes: bytes.length, sha256: sha256(bytes) });
}
const sourceSha256 = sha256(Buffer.from(buildFiles.map(file => `${file.path}:${file.sha256}\n`).join('')));
const revision = git(['rev-parse', 'HEAD']).trim();
const preparedAtUtc = new Date().toISOString();
const identity = { version: `${version}+${buildNumber}`, versionName: version, buildNumber: Number(buildNumber), revision,
  sourceSha256, preparedAtUtc, channel, projectRef, sourceDirty: git(['status', '--porcelain', '--untracked-files=normal', '--', 'apps/jentra_desktop/lib', 'apps/jentra_desktop/windows', 'apps/jentra_desktop/pubspec.yaml', 'packages/jentra_domain/lib', 'packages/jentra_platform/lib', 'packages/jentra_design_system/lib', 'tools/desktop-release']).trim().length > 0,
  releaseId: `${version}-${buildNumber}-${channel}-${sourceSha256.slice(0, 12)}`, applicationProductName: channel === 'development' ? 'Jentra OS Development' : 'Jentra OS' };
const defines = { ...config, SUPABASE_PROJECT_REF: projectRef,
  JENTRA_BUILD_VERSION: identity.version, JENTRA_BUILD_REVISION: revision, JENTRA_BUILD_SOURCE_SHA256: sourceSha256,
  JENTRA_BUILD_TIME_UTC: preparedAtUtc, JENTRA_RELEASE_CHANNEL: channel, JENTRA_CONFIG_PROJECT_REF: projectRef };
await writeFile(path.join(snapshot, 'public-build-config.json'), JSON.stringify(defines, null, 2) + '\n');
await writeFile(path.join(output, 'source-manifest.json'), JSON.stringify({ schemaVersion: 1, identity, hashMethod: 'SHA-256 of sorted path:sha256 LF records for exact allowlisted build-file bytes after recorded overlay', entrypoint: 'apps/jentra_desktop/lib/main.dart', inputs, buildFiles, overlays, excluded: ['secrets and local configuration', 'test fixtures and golden failures', 'existing user data and acceptance stores', 'generated build output'], snapshot }, null, 2) + '\n');
await writeFile(path.join(output, 'build-identity.json'), JSON.stringify(identity, null, 2) + '\n');
console.log(JSON.stringify({ snapshot, output, identity, sourceFiles: buildFiles.length, publicConfigValuesPrinted: false }));
