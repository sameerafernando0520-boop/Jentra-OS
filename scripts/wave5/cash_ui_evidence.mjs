import { createHash } from 'node:crypto';
import { copyFile, lstat, mkdir, readFile, readdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
// Include every declared workspace member so dependency resolution is attributed
// to concurrent applications without changing their owned source files.
const workspaceManifest = await readFile(path.join(root, 'pubspec.yaml'), 'utf8');
const workspaceSection = workspaceManifest.match(/^workspace:\s*\r?\n((?:[ \t]+-[^\r\n]+\r?\n?)+)/m)?.[1];
if (!workspaceSection) throw new Error('Workspace members missing');
const packages = [...workspaceSection.matchAll(/^[ \t]+-[ \t]+([A-Za-z0-9_./-]+)[ \t]*$/gm)].map(m=>m[1]);
if (!packages.length || packages.some(p=>p.includes('..')||path.isAbsolute(p))) throw new Error('Workspace member path invalid');
const excluded = new Set(['.dart_tool', 'build', 'ephemeral', '.plugin_symlinks', 'failures', '.git', 'node_modules']);
const generated = new Set(['generated_plugin_registrant.cc', 'generated_plugin_registrant.h', 'generated_plugins.cmake']);
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const inside = (base, item) => {
  const relative = path.relative(base, item);
  return relative !== '' && !relative.startsWith('..') && !path.isAbsolute(relative);
};
const requireInside = (base, item) => {
  if (!inside(base, item)) throw new Error(`Path must remain within ${base}: ${item}`);
  return item;
};
const exists = async (item) => {
  try { await lstat(item); return true; } catch (e) { if (e.code === 'ENOENT') return false; throw e; }
};
const jsonWrite = async (item, value) => writeFile(item, `${JSON.stringify(value, null, 2)}\n`);
const jsonRead = async (item) => JSON.parse(await readFile(item, 'utf8'));

export async function sources(base) {
  const selected = [];
  async function add(item) {
    if (!await exists(item)) return;
    const stat = await lstat(item);
    if (stat.isSymbolicLink()) throw new Error(`Snapshot refuses source links: ${item}`);
    requireInside(base, await realpath(item));
    if (stat.isFile()) selected.push(item);
  }
  async function walk(directory) {
    if (!await exists(directory)) return;
    const stat = await lstat(directory);
    if (stat.isSymbolicLink()) throw new Error(`Snapshot refuses directory links: ${directory}`);
    requireInside(base, await realpath(directory));
    for (const item of await readdir(directory, { withFileTypes: true })) {
      if (excluded.has(item.name) || generated.has(item.name) || item.name.startsWith('.env')) continue;
      const full = path.join(directory, item.name);
      if (item.isDirectory()) await walk(full); else await add(full);
    }
  }
  for (const name of ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']) await add(path.join(base, name));
  for (const name of packages) {
    for (const file of ['pubspec.yaml', 'analysis_options.yaml', '.metadata']) await add(path.join(base, name, file));
    for (const directory of ['lib', 'test', 'assets', 'windows']) await walk(path.join(base, name, directory));
  }
  const hashes = {};
  for (const item of selected.sort()) hashes[path.relative(base, item).split(path.sep).join('/')] = sha(await readFile(item));
  return hashes;
}
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);

async function desktopMembers(base) {
  const manifests = new Map();
  for (const member of packages) {
    const text = await readFile(path.join(base, member, 'pubspec.yaml'), 'utf8');
    const name = text.match(/^name:[ \t]+([a-z0-9_]+)[ \t]*$/m)?.[1];
    if (!name || manifests.has(name)) throw new Error('Workspace package identity invalid');
    manifests.set(name, { member, text });
  }
  const visited = new Set();
  function visit(name) {
    if (visited.has(name)) return;
    const manifest = manifests.get(name);
    if (!manifest) throw new Error('Desktop workspace package missing');
    visited.add(name);
    let section = '';
    for (const line of manifest.text.split(/\r?\n/)) {
      const top = line.match(/^([a-z_]+):/);
      if (top) section = top[1];
      if (!['dependencies', 'dev_dependencies'].includes(section)) continue;
      const dependency = line.match(/^  ([a-z0-9_]+):/)?.[1];
      if (dependency && manifests.has(dependency)) visit(dependency);
    }
  }
  visit('jentra_desktop');
  return [...visited].map(name => manifests.get(name).member).sort();
}
const desktopSelection = (hashes, members) => Object.fromEntries(Object.entries(hashes).filter(([p]) =>
  ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'].includes(p) ||
  packages.some(member => p === `${member}/pubspec.yaml`) || members.some(member => p.startsWith(`${member}/`))));

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
const [mode, snapshotArgument, evidenceArgument, runArgument] = process.argv.slice(2);
if (!['snapshot', 'record'].includes(mode) || !snapshotArgument || !evidenceArgument) {
  throw new Error('Usage: cash_ui_evidence.mjs snapshot|record SNAPSHOT EVIDENCE [RUN_METADATA]');
}
const snapshot = requireInside(path.join(root, 'build'), path.resolve(snapshotArgument));
const evidence = requireInside(root, path.resolve(evidenceArgument));
await mkdir(path.dirname(evidence), { recursive: true });
if (mode === 'snapshot') {
  if (await exists(snapshot)) throw new Error('Snapshot destination must be absent; existing builds are preserved');
  const before = await sources(root);
  await mkdir(snapshot, { recursive: true });
  for (const name of Object.keys(before)) {
    const destination = path.join(snapshot, name);
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(path.join(root, name), destination);
  }
  const copied = await sources(snapshot), after = await sources(root);
  const stable = equal(before, copied) && equal(before, after);
  await jsonWrite(evidence, {
    capturedAt: new Date().toISOString(), workspace: root, snapshot,
    source_stable: stable, file_count: Object.keys(before).length,
    source_hashes: before, copied_hashes: copied, source_hashes_after: after,
    excludes_local_stores_and_generated_builds: true,
  });
  if (!stable) throw new Error('Source changed during snapshot creation');
  console.log(JSON.stringify({ snapshot, evidence, source_stable: stable, file_count: Object.keys(before).length }));
} else {
  const run = await jsonRead(requireInside(root, path.resolve(runArgument)));
  const before = await jsonRead(requireInside(root, path.resolve(run.snapshotEvidence)));
  const currentWorkspace = await sources(root), copiedWorkspace = await sources(snapshot);
  const currentMembers = await desktopMembers(root), copiedMembers = await desktopMembers(snapshot);
  const current = desktopSelection(currentWorkspace, currentMembers), copied = desktopSelection(copiedWorkspace, copiedMembers);
  const captured = desktopSelection(before.copied_hashes, copiedMembers);
  const match = before.source_stable && equal(currentMembers, copiedMembers) && equal(captured, copied) && equal(current, copied);
  const workspaceMatch = before.source_stable && equal(before.copied_hashes, copiedWorkspace) && equal(currentWorkspace, copiedWorkspace);
  const stages = {};
  for (const [name, file] of Object.entries(run.stages)) {
    const stage = await jsonRead(requireInside(root, path.resolve(file)));
    const log = await readFile(requireInside(root, path.resolve(stage.log)));
    if (path.resolve(stage.workingDirectory) !== (['analyzer', 'pubget'].includes(name) ? snapshot : path.join(snapshot, stage.package || 'apps/jentra_desktop'))) {
      throw new Error(`Unexpected working directory: ${name}`);
    }
    const text = log.toString('utf8');
    const counts = [...text.matchAll(/\+(\d+)(?:\s+[^:\r\n]*)?: All tests passed!/g)];
    stages[name] = { ...stage, logSha256: sha(log), passed: stage.exitCode === 0,
      ...(name.endsWith('Tests') ? { assertions: counts.length ? Number(counts.at(-1)[1]) : null } : {}) };
    if (stage.exitCode !== 0) throw new Error(`${name} failed; preserve the log before claiming success`);
    if (name.endsWith('Tests') && !counts.length) throw new Error(`No successful test count for ${name}`);
  }
  const release = path.join(snapshot, 'apps/jentra_desktop/build/windows/x64/runner/Release');
  const releaseHashes = {};
  async function releaseFiles(directory) {
    for (const item of await readdir(directory, { withFileTypes: true })) {
      const full = path.join(directory, item.name);
      if (item.isSymbolicLink()) throw new Error('Release evidence refuses links');
      requireInside(release, await realpath(full));
      if (item.isDirectory()) await releaseFiles(full); else releaseHashes[path.relative(release, full).split(path.sep).join('/')] = sha(await readFile(full));
    }
  }
  await releaseFiles(release);
  if (!releaseHashes['jentra_desktop.exe'] || !/Built build/.test(await readFile(path.resolve(stages.windowsBuild.log), 'utf8'))) throw new Error('Successful Windows executable/build log missing');
  const framesDirectory = requireInside(root, path.resolve(run.framesDirectory));
  const frames = [];
  for (const file of (await readdir(framesDirectory)).filter((f) => f.endsWith('.png')).sort()) {
    const bytes = await readFile(path.join(framesDirectory, file));
    if (bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error('Expected PNG');
    frames.push({ path: path.relative(root, path.join(framesDirectory, file)).split(path.sep).join('/'), sha256: sha(bytes), width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) });
  }
  const expectedFrames = run.expectedFrames ?? 36;
  if (frames.length !== expectedFrames) throw new Error(`Expected ${expectedFrames} current cash frames, received ${frames.length}`);
  const inspected = run.visualReview?.inspectedFrames || [];
  if (inspected.length === 0 || inspected.some((p) => !frames.some((f) => f.path === p))) throw new Error('Fresh frame inspection evidence missing');
  const report = {
    capturedAt: new Date().toISOString(), workspace: root, snapshot,
    snapshotEvidence: run.snapshotEvidence, sdk: run.sdk,
    current_source_match: match, sourceFileCount: Object.keys(current).length,
    sourceAttributionScope: { desktopTransitiveWorkspaceMembers: currentMembers, allWorkspaceDependencyManifestsIncluded: true,
      excludedOtherApplicationCode: packages.filter(member => !currentMembers.includes(member)), scopedTestsIncludeDevDependencies: true },
    workspace_source_match: workspaceMatch, workspaceSourceFileCount: Object.keys(currentWorkspace).length,
    workspaceSourceChangesSinceSnapshot: [...new Set([...Object.keys(currentWorkspace), ...Object.keys(copiedWorkspace)])].filter(p => currentWorkspace[p] !== copiedWorkspace[p]),
    sourceChangesSinceSnapshot: [...new Set([...Object.keys(current), ...Object.keys(copied)])].filter((p) => current[p] !== copied[p]),
    sourceHashes: current, stages, frames, visualReview: run.visualReview,
    buildSucceeded: true, releaseFileCount: Object.keys(releaseHashes).length, releaseHashes,
    executable: path.join(release, 'jentra_desktop.exe'), executableSha256: releaseHashes['jentra_desktop.exe'],
    nativeLaunched: false, authenticatedAcceptance: false, localStoresIncluded: false, installerCreated: false,
    installedSqlReverified: false, actualWorkerDelivery: false, independentSessionContention: false, targetScaleLoad: false, ownerAccepted: false,
    goldenFilesRegenerated: false, fullCashProviders: false,
  };
  await jsonWrite(evidence, report);
  console.log(JSON.stringify({ evidence, current_source_match: match, assertions: Object.fromEntries(Object.entries(stages).filter(([k]) => k.endsWith('Tests')).map(([k,v]) => [k, v.assertions])), frames: frames.length, releaseFileCount: report.releaseFileCount }));
  if (!match) throw new Error('Current source does not match verified snapshot');
}
}
