// NEW r4 variant; preserved predecessor prepare_windows_userflow_20261010_r3.mjs SHA-256 0e5a126f669a4b88a1f9619270e0bfa31978d371772af4e97c500872a3657c4c.
// Source-only preparation and verification. This script never launches an SDK,
// executable, reads an acceptance store, or contacts Supabase.
import {copyFile, lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {fullDesktop} from './windows_delivery_inputs_20261010_r4.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const revision = 'r4', date = '20261010';
const buildRoot = path.join(root, 'build/w5win10r4');
const base = 'docs/verification/wave5/';
const approvedInput = `${base}desktop-verification-source-20261010-r4-approved.json`;
const publicBindingPath = `${base}current-public-build-binding-20261010-r4.json`;
const preparationPath = `${base}windows-userflow-preparation-${date}-${revision}.json`;
const scriptPath = 'scripts/wave5/prepare_windows_userflow_20261010_r4.mjs';
const runnerPath = 'scripts/wave5/run_windows_userflow_20261010_r4.ps1';
const wrapperPath = 'scripts/wave5/run_flutter_with_capture_env.mjs';
const sourceHelperPath = 'scripts/wave5/cash_ui_evidence.mjs';
const inputHelperPath = 'scripts/wave5/windows_delivery_inputs_20261010_r4.mjs';
const verificationHelperPath = 'scripts/wave5/desktop_verification_inputs_20261010_r4.mjs';
const guardedRunnerPath = 'scripts/wave5/run_windows_userflow_guarded_20261010_r4.mjs';
const sha = b => createHash('sha256').update(b).digest('hex');
const hash = async p => sha(await readFile(p));
const exists = async p => {try {await lstat(p); return true;} catch (e) {if (e.code === 'ENOENT') return false; throw e;}};
const readJson = async p => JSON.parse(await readFile(p, 'utf8'));
const jsonWriteNew = (p, value) => writeFile(p, JSON.stringify(value, null, 2) + '\n', {flag:'wx'});
const manifestPath = mode => `${base}windows-test-${mode.toLowerCase()}-source-${date}-${revision}.json`;
const canonical = o => JSON.stringify(Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b))));
const equal = (a, b) => canonical(a) === canonical(b);
const difference = (a, b) => [...new Set([...Object.keys(a), ...Object.keys(b)])].filter(p => a[p] !== b[p]).sort();
function inside(baseDirectory, item) {
  const rel = path.relative(baseDirectory, item);
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) throw Error('PATH_OUTSIDE_INTENDED_DIRECTORY');
  return item;
}
async function noLink(p) {
  if ((await lstat(p)).isSymbolicLink()) throw Error('SOURCE_OR_OUTPUT_LINK_REFUSED');
  return inside(root, await realpath(p));
}
async function selectedSources(directory) {
  const pubspec = await readFile(path.join(directory, 'pubspec.yaml'), 'utf8');
  const section = pubspec.match(/^workspace:\s*\r?\n((?:[ \t]+-[^\r\n]+\r?\n?)+)/m)?.[1];
  if (!section) throw Error('WORKSPACE_MEMBERS_REQUIRED');
  const members = [...section.matchAll(/^[ \t]+-[ \t]+([A-Za-z0-9_./-]+)[ \t]*$/gm)].map(m => m[1]);
  if (members.some(m => m.includes('..') || path.isAbsolute(m))) throw Error('WORKSPACE_MEMBER_PATH_INVALID');
  const byName = new Map();
  for (const member of members) {
    const text = await readFile(path.join(directory, member, 'pubspec.yaml'), 'utf8');
    const name = text.match(/^name:[ \t]+([a-z0-9_]+)[ \t]*$/m)?.[1];
    if (!name || byName.has(name)) throw Error('WORKSPACE_PACKAGE_IDENTITY_INVALID');
    byName.set(name, {member, text});
  }
  const visited = new Set();
  function visit(name) {
    if (visited.has(name)) return;
    const entry = byName.get(name);
    if (!entry) throw Error('DESKTOP_WORKSPACE_DEPENDENCY_MISSING');
    visited.add(name);
    let currentSection = '';
    for (const line of entry.text.split(/\r?\n/)) {
      const top = line.match(/^([a-z_]+):/);
      if (top) currentSection = top[1];
      if (!['dependencies', 'dev_dependencies'].includes(currentSection)) continue;
      const dependency = line.match(/^  ([a-z0-9_]+):/)?.[1];
      if (dependency && byName.has(dependency)) visit(dependency);
    }
  }
  visit('jentra_desktop');
  const desktopMembers = [...visited].map(name => byName.get(name).member).sort();
  const all = await sources(directory);
  return {
    members, desktopMembers,
    hashes: Object.fromEntries(Object.entries(all).filter(([p]) =>
      ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'].includes(p) ||
      members.some(m => p === `${m}/pubspec.yaml`) || desktopMembers.some(m => p.startsWith(`${m}/`)))),
  };
}
async function bindings() {
  return Object.fromEntries(await Promise.all([scriptPath, runnerPath, wrapperPath, sourceHelperPath,inputHelperPath,verificationHelperPath,guardedRunnerPath].map(async p => [p, await hash(path.join(root, p))])));
}
function replaceOne(text, from, to) {
  if (text.split(from).length !== 2) throw Error('RUNNER_IDENTITY_OVERLAY_EXPECTED_EXACTLY_ONCE');
  return text.replace(from, to);
}
function transformations(mode) {
  const company = 'com.jentra.test', product = `JentraOS_WindowsTest_${date}-${revision}_${mode}`;
  return {
    company, product,
    files: {
      'apps/jentra_desktop/windows/CMakeLists.txt': s => replaceOne(s, 'set(BINARY_NAME "jentra_desktop")', 'set(BINARY_NAME "Jentra_OS")'),
      'apps/jentra_desktop/windows/runner/Runner.rc': s => {
        s = replaceOne(s, 'VALUE "CompanyName", "com.jentra"', `VALUE "CompanyName", "${company}"`);
        s = replaceOne(s, 'VALUE "ProductName", "jentra_desktop"', `VALUE "ProductName", "${product}"`);
        s = replaceOne(s, 'VALUE "FileDescription", "jentra_desktop"', `VALUE "FileDescription", "Jentra OS Windows Test - ${date} ${revision} ${mode}"`);
        return replaceOne(s, 'VALUE "OriginalFilename", "jentra_desktop.exe"', 'VALUE "OriginalFilename", "Jentra_OS.exe"');
      },
      'apps/jentra_desktop/windows/runner/main.cpp': s => replaceOne(s, 'window.Create(L"jentra_desktop"', `window.Create(L"Jentra OS - ${date} ${revision} ${mode} test"`),
    },
  };
}
async function publicConfig(snapshot) {
  const configPath = path.join(snapshot, 'public-build-config.json');
  await noLink(configPath);
  const config = await readJson(configPath);
  const expectedKeys = ['JENTRA_ENVIRONMENT', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_URL'];
  if (!equal(Object.fromEntries(Object.keys(config).map(k => [k, true])), Object.fromEntries(expectedKeys.map(k => [k, true])))) throw Error('PUBLIC_CONFIG_EXACT_KEYS_REQUIRED');
  if (!['development', 'test', 'connected-test'].includes(config.JENTRA_ENVIRONMENT) || config.SUPABASE_URL !== 'https://xpdoufauvrbdmxgngetv.supabase.co') throw Error('PUBLIC_CONFIG_PROJECT_OR_ENVIRONMENT_INVALID');
  const key = config.SUPABASE_PUBLISHABLE_KEY;
  if (typeof key !== 'string' || key.length < 20) throw Error('PUBLIC_CONFIG_PUBLIC_KEY_REQUIRED');
  if (!key.startsWith('sb_publishable_')) {
    let payload;
    try {payload = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString('utf8'));} catch {throw Error('PUBLIC_CONFIG_PUBLIC_KEY_INVALID');}
    if (payload.role !== 'anon' || payload.ref !== 'xpdoufauvrbdmxgngetv') throw Error('PUBLIC_CONFIG_ANON_PROJECT_REQUIRED');
  }
  return {path:path.relative(root, configPath).split(path.sep).join('/'), sha256:await hash(configPath), publicOnly:true, projectId:'xpdoufauvrbdmxgngetv', environment:config.JENTRA_ENVIRONMENT};
}
async function verify(mode, checkConfig = false) {
  if (!['Preview', 'Connected'].includes(mode)) throw Error('PREVIEW_OR_CONNECTED_MODE_REQUIRED');
  if (checkConfig && mode !== 'Connected') throw Error('PUBLIC_CONFIG_ONLY_FOR_CONNECTED');
  const preparation = await readJson(path.join(root, preparationPath));
  const reference = preparation.manifests.find(m => m.mode === mode);
  if (!reference || await hash(path.join(root, reference.path)) !== reference.sha256) throw Error('SOURCE_MANIFEST_BINDING_CHANGED');
  const manifest = await readJson(path.join(root, reference.path));
  const expectedSnapshot = path.join(buildRoot, mode.toLowerCase());
  if (manifest.workspace !== root || manifest.snapshot !== expectedSnapshot || manifest.mode !== mode || manifest.revision !== revision || manifest.entrypoint !== 'lib/main.dart' || manifest.controlledEvidence !== false) throw Error('SOURCE_MANIFEST_IDENTITY_INVALID');
  await noLink(expectedSnapshot);
  if (!equal(await bindings(), preparation.scriptBindings)) throw Error('PREPARER_RUNNER_BINDING_CHANGED');
  if (await hash(path.join(root, approvedInput)) !== preparation.approvedInput.sha256) throw Error('APPROVED_INPUT_MANIFEST_CHANGED');
  if (await hash(path.join(root, publicBindingPath)) !== preparation.publicBuildBinding.sha256) throw Error('CURRENT_PUBLIC_BUILD_BINDING_CHANGED');
  const current = await selectedSources(root), copied = await selectedSources(expectedSnapshot);
  if (!equal(current.hashes, manifest.baseSourceHashes)) throw Error(`CURRENT_SOURCE_CHANGED:${difference(current.hashes, manifest.baseSourceHashes).join(',')}`);
  if (!equal(copied.hashes, manifest.buildSourceHashes)) throw Error(`BUILD_SOURCE_CHANGED:${difference(copied.hashes, manifest.buildSourceHashes).join(',')}`);
  const fullSuite = await fullDesktop(manifest);
  if (!equal(fullSuite,manifest.fullDesktopEvidence) || !equal(fullSuite,preparation.fullDesktopEvidence)) throw Error('POSTAPPROVAL_FULL_SUITE_BINDING_CHANGED');
  const transform = transformations(mode);
  const changed = difference(current.hashes, copied.hashes);
  if (changed.length !== 3 || changed.some(p => !(p in transform.files)) || manifest.overlays.length !== 3) throw Error('ONLY_THREE_RUNNER_IDENTITY_OVERLAYS_ALLOWED');
  for (const [p, apply] of Object.entries(transform.files)) {
    const original = await readFile(path.join(root, p), 'utf8');
    if (sha(Buffer.from(apply(original))) !== copied.hashes[p]) throw Error('RUNNER_OVERLAY_CONTENT_CHANGED');
  }
  if (manifest.stores.company !== transform.company || manifest.stores.product !== transform.product || manifest.stores.defaultStoresRead !== false) throw Error('ISOLATED_STORAGE_IDENTITY_INVALID');
  if (mode === 'Connected' && (!manifest.publicBuildConfigIncluded || await hash(path.join(expectedSnapshot, 'public-build-config.json')) !== preparation.publicBuildBinding.configSha256)) throw Error('PUBLIC_CONFIG_BINDING_CHANGED');
  return {checkedAt:new Date().toISOString(), mode, revision, snapshot:expectedSnapshot, manifest:reference, sourceFileCount:Object.keys(current.hashes).length, currentSourceMatches:true, snapshotSourceMatches:true, lockSha256:current.hashes['pubspec.lock'], runnerOverlayCount:3, fullDesktopEvidence:fullSuite, publicConfig:checkConfig ? await publicConfig(expectedSnapshot) : null, SDKExecuted:false, nativeLaunched:false, storesRead:false};
}

const [command, mode, option] = process.argv.slice(2);
if (command === 'verify') {
  if (option && option !== '--config') throw Error('VERIFY_OPTION_INVALID');
  console.log(JSON.stringify(await verify(mode, option === '--config')));
} else if (command === 'prepare' && !mode && !option) {
  const outputs = [buildRoot, ...['Preview', 'Connected'].map(m => path.join(root, manifestPath(m))), path.join(root, preparationPath)];
  if ((await Promise.all(outputs.map(exists))).some(Boolean)) throw Error('NEW_OUTPUTS_REQUIRED_PRESERVE_EXISTING_R4');
  const selected = await selectedSources(root);
  const inputBytes = await readFile(path.join(root, approvedInput));
  const approved = JSON.parse(inputBytes);
  if (approved.revision !== 'r4' || approved.postImageApproval !== true || !Number.isInteger(approved.selectedSources) || approved.selectedSources <= 0 ||
      Object.keys(approved.sourceHashes ?? {}).length !== approved.selectedSources ||
      approved.sourceInputsSha256 !== sha(Buffer.from(JSON.stringify(approved.sourceHashes))) ||
      !equal(selected.hashes, approved.sourceHashes)) throw Error('CURRENT_SOURCE_MUST_MATCH_FROZEN_R4_INPUTS');
  if (!equal(Object.fromEntries(selected.desktopMembers.map(p => [p, true])),
      Object.fromEntries((approved.dependencyScope ?? []).map(p => [p, true])))) throw Error('R4_DESKTOP_DEPENDENCY_SCOPE_CHANGED');
  if (approved.toolchain?.tooling?.length !== 4) throw Error('FOUR_FROZEN_R4_SDK_PINS_REQUIRED');
  for (const pin of approved.toolchain.tooling) if (await hash(pin.path) !== pin.sha256) throw Error('FROZEN_R4_SDK_CHANGED');
  const fullSuite = await fullDesktop({baseSourceHashes:selected.hashes});
  const publicBindingBytes = await readFile(path.join(root, publicBindingPath));
  const publicBinding = JSON.parse(publicBindingBytes);
  if (publicBinding.projectId !== 'xpdoufauvrbdmxgngetv' || publicBinding.projectUrl !== 'https://xpdoufauvrbdmxgngetv.supabase.co' || publicBinding.readOnly !== true || publicBinding.publicKeyOnly !== true || publicBinding.matchedEnabledPublicKeys !== 1 || publicBinding.keyValuesPrinted !== false || publicBinding.liveOperations !== false) throw Error('FRESH_PUBLIC_PROJECT_BINDING_REQUIRED');
  const configSource = inside(root, path.resolve(root, publicBinding.configPath));
  await noLink(configSource);
  if (await hash(configSource) !== publicBinding.configSha256) throw Error('FRESH_PUBLIC_BUILD_CONFIG_HASH_CHANGED');
  const scriptBindings = await bindings();
  await mkdir(buildRoot, {recursive:true});
  const manifests = [];
  for (const currentMode of ['Preview', 'Connected']) {
    const snapshot = path.join(buildRoot, currentMode.toLowerCase());
    await mkdir(snapshot);
    for (const [p, h] of Object.entries(selected.hashes)) {
      const target = inside(snapshot, path.join(snapshot, p));
      await mkdir(path.dirname(target), {recursive:true});
      await copyFile(path.join(root, p), target);
      if (await hash(target) !== h) throw Error('SOURCE_CHANGED_DURING_COPY');
    }
    const transform = transformations(currentMode), overlays = [];
    for (const [p, apply] of Object.entries(transform.files)) {
      const location = path.join(snapshot, p), original = await readFile(location, 'utf8'), updated = apply(original);
      await writeFile(location, updated);
      overlays.push({path:p, baseSha256:selected.hashes[p], buildSha256:sha(Buffer.from(updated)), purpose:'Isolated test runner identity only'});
    }
    const built = await selectedSources(snapshot);
    if (difference(selected.hashes, built.hashes).some(p => !(p in transform.files))) throw Error('UNEXPECTED_COPIED_SOURCE_DRIFT');
    let config = null;
    if (currentMode === 'Connected') {
      await copyFile(configSource, path.join(snapshot, 'public-build-config.json'));
      config = await publicConfig(snapshot);
      if (config.sha256 !== publicBinding.configSha256) throw Error('COPIED_PUBLIC_CONFIG_HASH_CHANGED');
    }
    const output = manifestPath(currentMode);
    await jsonWriteNew(path.join(root, output), {
      capturedAt:new Date().toISOString(), workspace:root, snapshot, mode:currentMode, revision, date, entrypoint:'lib/main.dart', controlledEvidence:false,
      baseSourceHashes:selected.hashes, buildSourceHashes:built.hashes, sourceFileCount:Object.keys(selected.hashes).length, overlays,
      desktopDependencyScope:selected.desktopMembers, allWorkspaceManifestsIncluded:true, otherApplicationSourceCopied:false,
      approvedSourceInput:{path:approvedInput, sha256:sha(inputBytes)}, scriptBindings,
      baseVerificationRevision:'r4', baseVerificationIsPreapproval:false,fullDesktopEvidence:fullSuite,
      publicBuildBinding:{path:publicBindingPath, sha256:sha(publicBindingBytes), observedAt:publicBinding.observedAt}, publicConfig:config,
      stores:{company:transform.company, product:transform.product,
        applicationSupport:`%APPDATA%\\${transform.company}\\${transform.product}`,
        applicationCache:`%LOCALAPPDATA%\\${transform.company}\\${transform.product}`,
        secureStorage:'DPAPI file under this unique applicationSupport identity; default WindowsOptions do not migrate legacy storage',
        defaultAcceptanceIdentity:'com.jentra/jentra_desktop', defaultStoresRead:false, localStoresCopied:false, newOsUserCreated:false,
        isolationLimit:'Distinct product directories on the same Windows account; this is not a separate OS security boundary. Native path observation is pending.'},
      projectId:currentMode === 'Connected' ? 'xpdoufauvrbdmxgngetv' : null, previewData:currentMode === 'Preview',
      previewAccountingGateways:currentMode === 'Preview' ? 'null; fail-closed operational screens, no actual posting' : null,
      publicBuildConfigIncluded:currentMode === 'Connected', SDKExecuted:false, buildSucceeded:false, nativeLaunched:false,
      authenticatedAcceptance:false, realMfa:false, actualDelivery:false, independentSessionContention:false, targetScaleLoad:false, ownerAccepted:false,
      boundary:'Source-only preparation. Root owns serialized SDK jobs and all native user actions. No live SQL, Auth, private secret, account, OS-target or acceptance-store operation occurred.',
    });
    manifests.push({mode:currentMode, path:output, sha256:await hash(path.join(root, output))});
  }
  const fresh = await selectedSources(root);
  if (!equal(fresh.hashes, selected.hashes)) throw Error('CURRENT_SOURCE_CHANGED_DURING_PREPARATION');
  if (!equal(await bindings(), scriptBindings)) throw Error('PREPARER_RUNNER_CHANGED_DURING_PREPARATION');
  if (!equal(await fullDesktop({baseSourceHashes:fresh.hashes}), fullSuite)) throw Error('POSTAPPROVAL_FULL_SUITE_CHANGED_DURING_PREPARATION');
  await jsonWriteNew(path.join(root, preparationPath), {
    capturedAt:new Date().toISOString(), revision, date, workspace:root, buildRoot, sourceFileCount:Object.keys(selected.hashes).length,
    sourceInputsSha256:sha(Buffer.from(canonical(selected.hashes))), lockSha256:selected.hashes['pubspec.lock'],
    sourceStable:true, sharedSourceChanged:false, approvedInput:{path:approvedInput, sha256:sha(inputBytes)}, scriptBindings, manifests,fullDesktopEvidence:fullSuite,
    publicBuildBinding:{path:publicBindingPath, sha256:sha(publicBindingBytes), configSha256:publicBinding.configSha256, observedAt:publicBinding.observedAt},
    SDKExecuted:false, nativeLaunched:false, localStoresRead:false, nativeTargetCollisionCheckPerformed:false, publicBuildConfigIncluded:true,
  });
  console.log(JSON.stringify({preparation:preparationPath, buildRoot, sourceFileCount:Object.keys(selected.hashes).length, manifests, sourceStable:true, SDKExecuted:false, nativeLaunched:false}));
} else {
  throw Error('Usage: prepare_windows_userflow_20261010_r4.mjs prepare | verify Preview|Connected [--config]');
}
