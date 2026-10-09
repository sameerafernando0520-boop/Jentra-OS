import { createHash } from 'node:crypto';
import { lstat, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateRawSync } from 'node:zlib';
import { sources } from './cash_ui_evidence.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const relative = item => path.relative(root, item).split(path.sep).join('/');
const equal = (a, b) => JSON.stringify(Object.entries(a).sort()) === JSON.stringify(Object.entries(b).sort());
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const inside = item => {
  const resolved = path.resolve(root, item);
  const rel = path.relative(root, resolved);
  assert(rel !== '' && !rel.startsWith('..') && !path.isAbsolute(rel), 'EVIDENCE_PATH_ESCAPES_WORKSPACE');
  return resolved;
};
const bytes = async item => {
  const resolved = inside(item);
  assert(!(await lstat(resolved)).isSymbolicLink(), 'EVIDENCE_LINK_REFUSED');
  return readFile(resolved);
};
const json = async item => JSON.parse((await bytes(item)).toString('utf8').replace(/^\uFEFF/, ''));
const exists = async item => {
  try { await lstat(inside(item)); return true; }
  catch (error) { if (error.code === 'ENOENT') return false; throw error; }
};

export function parseTestLog(raw) {
  const text = raw.replace(/\x1b\[[0-9;]*m/g, '').replace(/\r/g, '');
  const summaries = [...text.matchAll(/^.*\+(\d+)((?:\s+[~-]\d+)*)\s*:\s*(All tests passed!|Some tests failed\.)\s*$/gm)];
  const summary = summaries.at(-1);
  if (!summary) return null;
  const errors = [...text.matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.*?)\s+\[E\]\s*$/gm)];
  let previousEnd = 0;
  const failures = errors.map(error => {
    const segment = text.slice(previousEnd, error.index);
    previousEnd = error.index + error[0].length;
    const goldens = [...segment.matchAll(/Golden "(goldens\/[^"\r\n]+\.png)":\s*Pixel\s+test\s+failed/g)];
    return { name: error[1], kind: goldens.length ? 'golden-comparison' : 'other', golden: goldens.at(-1)?.[1] ?? null };
  });
  return {
    passedTests: Number(summary[1]),
    failedTests: Number(summary[2].match(/-(\d+)/)?.[1] ?? 0),
    skippedTests: Number(summary[2].match(/~(\d+)/)?.[1] ?? 0),
    allTestsPassed: summary[3] === 'All tests passed!', failures,
  };
}

export function parsePlatformStoreExecutions(raw) {
  const summary = parseTestLog(raw);
  assert(summary?.allTestsPassed && summary.failedTests === 0 && summary.skippedTests === 0,
    'PASSED_UNSKIPPED_PLATFORM_SUITE_REQUIRED_FOR_STORE_ATTRIBUTION');
  const text = raw.replace(/\x1b\[[0-9;]*m/g, '').replace(/\r/g, '');
  return ['cash_scenario_store_test.dart', 'wave5_command_store_test.dart'].map(file => {
    const entries = [...text.matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\/test\/analytics\/([^/:]+\.dart)):\s+(.+)$/gm)]
      .filter(match => match[2] === file).map(match => ({ file: match[1], name: match[3] }));
    assert(entries.length > 0 && entries.every(entry => !/\[E\]|\(skipped\)|loading /.test(entry.name)), 'ACTUAL_STORE_TEST_EXECUTIONS_MISSING');
    assert(new Set(entries.map(entry => entry.name)).size === entries.length, 'DUPLICATE_STORE_TEST_EXECUTION_NAMES');
    return { file: `packages/jentra_platform/test/analytics/${file}`, passedCases: entries.length, failedCases: 0, entries,
      boundary: 'Named executed entries in the successful zero-skipped full platform suite; not a separate focused test run.' };
  });
}

// Read ZIP entries without extraction. Each requested release entry is inflated
// with its already-verified manifest byte count as the output bound.
export function readZipEntries(archive) {
  let end = -1;
  for (let offset = archive.length - 22; offset >= Math.max(0, archive.length - 65557); offset--) {
    if (archive.readUInt32LE(offset) === 0x06054b50 && offset + 22 + archive.readUInt16LE(offset + 20) === archive.length) {
      end = offset; break;
    }
  }
  assert(end >= 0, 'ZIP_END_MISSING');
  assert(archive.readUInt16LE(end + 4) === 0 && archive.readUInt16LE(end + 6) === 0, 'MULTI_DISK_ZIP_REFUSED');
  const count = archive.readUInt16LE(end + 10);
  let offset = archive.readUInt32LE(end + 16);
  assert(count !== 0xffff && offset !== 0xffffffff, 'ZIP64_UNSUPPORTED');
  const entries = new Map();
  for (let index = 0; index < count; index++) {
    assert(archive.readUInt32LE(offset) === 0x02014b50, 'ZIP_DIRECTORY_INVALID');
    const nameLength = archive.readUInt16LE(offset + 28);
    const extraLength = archive.readUInt16LE(offset + 30);
    const commentLength = archive.readUInt16LE(offset + 32);
    const name = archive.subarray(offset + 46, offset + 46 + nameLength).toString('utf8').replaceAll('\\', '/');
    assert(!entries.has(name), 'ZIP_DUPLICATE_ENTRY');
    entries.set(name, {
      flags: archive.readUInt16LE(offset + 8), method: archive.readUInt16LE(offset + 10),
      compressedBytes: archive.readUInt32LE(offset + 20), uncompressedBytes: archive.readUInt32LE(offset + 24),
      localOffset: archive.readUInt32LE(offset + 42),
    });
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

export function zipEntryBytes(archive, entry, expectedBytes) {
  assert(!(entry.flags & 1) && [0, 8].includes(entry.method), 'ZIP_ENCRYPTION_OR_COMPRESSION_UNSUPPORTED');
  assert(entry.uncompressedBytes === expectedBytes, 'ZIP_ENTRY_SIZE_MISMATCH');
  const offset = entry.localOffset;
  assert(archive.readUInt32LE(offset) === 0x04034b50, 'ZIP_LOCAL_HEADER_INVALID');
  const start = offset + 30 + archive.readUInt16LE(offset + 26) + archive.readUInt16LE(offset + 28);
  const compressed = archive.subarray(start, start + entry.compressedBytes);
  const result = entry.method === 0 ? compressed : inflateRawSync(compressed, { maxOutputLength: expectedBytes });
  assert(result.length === expectedBytes, 'ZIP_INFLATED_SIZE_MISMATCH');
  return result;
}

export async function workspaceScope() {
  const text = (await bytes('pubspec.yaml')).toString('utf8');
  const section = text.match(/^workspace:\s*\r?\n((?:[ \t]+-[^\r\n]+\r?\n?)+)/m)?.[1];
  assert(section, 'WORKSPACE_MEMBERS_MISSING');
  const members = [...section.matchAll(/^[ \t]+-[ \t]+([A-Za-z0-9_./-]+)[ \t]*$/gm)].map(match => match[1]);
  const manifests = new Map();
  for (const member of members) {
    const manifest = (await bytes(`${member}/pubspec.yaml`)).toString('utf8');
    const name = manifest.match(/^name:[ \t]+([a-z0-9_]+)[ \t]*$/m)?.[1];
    assert(name && !manifests.has(name), 'WORKSPACE_PACKAGE_IDENTITY_INVALID');
    manifests.set(name, { member, text: manifest });
  }
  const visited = new Set();
  function visit(name) {
    if (visited.has(name)) return;
    const manifest = manifests.get(name);
    assert(manifest, 'DESKTOP_PACKAGE_MISSING');
    visited.add(name);
    let sectionName = '';
    for (const line of manifest.text.split(/\r?\n/)) {
      const top = line.match(/^([a-z_]+):/);
      if (top) sectionName = top[1];
      if (!['dependencies', 'dev_dependencies'].includes(sectionName)) continue;
      const dependency = line.match(/^  ([a-z0-9_]+):/)?.[1];
      if (dependency && manifests.has(dependency)) visit(dependency);
    }
  }
  visit('jentra_desktop');
  return { members, desktop: [...visited].map(name => manifests.get(name).member).sort() };
}

async function main() {
  const args = process.argv.slice(2);
  const revision = args[args.indexOf('--revision') + 1];
  const inspectionArgument = args[args.indexOf('--inspection') + 1];
  assert(args.includes('--revision') && revision === 'r13' && args.includes('--inspection') && inspectionArgument,
    'Usage: record_continuation_windows.mjs --revision r13 --inspection INSPECTED_FRAMES_JSON');
  const output = `${base}windows-test-verification-20261009-${revision}.json`;
  const markdownOutput = output.replace(/\.json$/, '.md');
  assert(!await exists(output) && !await exists(markdownOutput), 'REPORT_ALREADY_EXISTS_PRESERVE_EVIDENCE');
  const inspection = await json(inspectionArgument);
  assert(inspection.revision === revision && Array.isArray(inspection.inspectedFrames) && inspection.inspectedFrames.length,
    'EXPLICIT_CURRENT_INSPECTION_LIST_REQUIRED');
  const scope = await workspaceScope();
  const allCurrent = await sources(root);
  const selected = Object.fromEntries(Object.entries(allCurrent).filter(([name]) =>
    ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'].includes(name) ||
    scope.members.some(member => name === `${member}/pubspec.yaml`) || scope.desktop.some(member => name.startsWith(`${member}/`))));
  const builds = [];
  const sourceManifests = new Map();
  const packageManifests = new Map();
  for (const mode of ['preview', 'connected']) {
    const sourcePath = `${base}windows-test-${mode}-source-20261009-${revision}.json`;
    const packagePath = `${base}windows-test-${mode}-package-20261009-${revision}.json`;
    const source = await json(sourcePath), packaged = await json(packagePath);
    const snapshot = inside(`build/w5win9${revision}/${mode}`);
    const projectId = mode === 'connected' ? 'xpdoufauvrbdmxgngetv' : null;
    assert(packaged.mode === mode && String(source.mode).toLowerCase() === mode &&
      packaged.projectId === projectId && source.projectId === projectId, 'PACKAGE_MODE_OR_PROJECT_MISMATCH');
    assert(source.controlledEvidence === false && packaged.controlledEvidence === false &&
      packaged.base_source_match === true && packaged.current_source_match === true, 'ORDINARY_CURRENT_BUILD_EVIDENCE_REQUIRED');
    assert(packaged.sourceManifest === sourcePath && packaged.buildEvidence === `${base}windows-test-${mode}-build-20261009-${revision}.json`,
      'PACKAGE_MANIFEST_LINKS_WRONG_REVISION');
    assert(path.resolve(packaged.releaseDirectory) === path.join(snapshot, 'apps/jentra_desktop/build/windows/x64/runner/Release') &&
      path.resolve(packaged.packageDirectory) === inside(`dist/Jentra OS Windows Test 20261009 ${revision}/${mode === 'preview' ? 'Preview' : 'Connected'}`),
      'RELEASE_DIRECTORY_WRONG_REVISION');
    assert(path.resolve(source.snapshot) === snapshot && source.revision === revision, 'SOURCE_SNAPSHOT_REVISION_MISMATCH');
    assert(Array.isArray(source.desktopDependencyScope) &&
      new Set(source.desktopDependencyScope).size === source.desktopDependencyScope.length &&
      JSON.stringify([...source.desktopDependencyScope].sort()) === JSON.stringify(scope.desktop),
      'DESKTOP_DEPENDENCY_SCOPE_CHANGED');
    assert(source.allWorkspaceManifestsIncluded === true && equal(selected, source.baseSourceHashes), 'CURRENT_SOURCE_DRIFT');
    const copied = await sources(snapshot);
    const selectedCopy = Object.fromEntries(Object.entries(copied).filter(([name]) =>
      ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'].includes(name) ||
      scope.members.some(member => name === `${member}/pubspec.yaml`) || scope.desktop.some(member => name.startsWith(`${member}/`))));
    assert(equal(selectedCopy, source.buildSourceHashes), 'SNAPSHOT_BUILD_SOURCE_DRIFT');
    assert(equal(packaged.sourceHashes, selected) && equal(packaged.buildSourceHashes, selectedCopy), 'PACKAGE_SOURCE_BINDING_CHANGED');
    assert(source.entrypoint === 'lib/main.dart' && packaged.entrypoint === 'lib/main.dart', 'ORDINARY_ENTRYPOINT_REQUIRED');
    const overlayPaths = source.overlays.map(overlay => overlay.path).sort();
    assert(JSON.stringify(overlayPaths) === JSON.stringify([
      'apps/jentra_desktop/windows/CMakeLists.txt', 'apps/jentra_desktop/windows/runner/Runner.rc',
      'apps/jentra_desktop/windows/runner/main.cpp',
    ]), 'RUNNER_OVERLAY_SCOPE_INVALID');
    for (const [name, hash] of Object.entries(selectedCopy)) {
      const overlay = source.overlays.find(item => item.path === name);
      assert(overlay ? overlay.baseSha256 === selected[name] && overlay.buildSha256 === hash : selected[name] === hash,
        'UNDECLARED_SOURCE_OVERLAY');
    }
    for (const file of packaged.releaseFiles) {
      for (const directory of [packaged.releaseDirectory, packaged.packageDirectory]) {
        const content = await bytes(path.join(directory, file.path));
        assert(sha(content) === file.sha256 && content.length === file.bytes, 'RELEASE_FILE_HASH_OR_SIZE_DRIFT');
      }
    }
    assert(packaged.releaseFiles.some(file => file.path === 'Jentra_OS.exe'), 'ORDINARY_NATIVE_EXECUTABLE_MISSING');
    builds.push({ mode, sourceManifest: sourcePath, sourceManifestSha256: sha(await bytes(sourcePath)),
      packageManifest: packagePath, packageManifestSha256: sha(await bytes(packagePath)),
      sourceFileCount: Object.keys(selected).length, sourceHashesVerified: true, releaseFiles: packaged.releaseFiles.length,
      nativeLaunched: false, nativeInspected: false, entrypoint: packaged.entrypoint, storageIdentity: packaged.storageIdentity });
    sourceManifests.set(mode, source); packageManifests.set(mode, packaged);
  }

  const stages = [];
  const stageFiles = (await readdir(inside(base))).filter(name => /^windows-test-(preview|connected)-.+-20261009-r13\.json$/.test(name)).sort();
  for (const file of stageFiles) {
    const recordPath = base + file, record = await json(recordPath);
    if (!record.stage || !record.log || record.exitCode === undefined) continue;
    const mode = String(record.mode).toLowerCase();
    assert(sourceManifests.has(mode) && file === `windows-test-${mode}-${record.stage}-20261009-${revision}.json`, 'STAGE_IDENTITY_MISMATCH');
    const snapshot = sourceManifests.get(mode).snapshot;
    const working = path.resolve(record.workingDirectory);
    assert([snapshot, path.join(snapshot, 'apps/jentra_desktop'), path.join(snapshot, 'packages/jentra_platform')].includes(working),
      'STAGE_WORKING_DIRECTORY_MISMATCH');
    const log = await bytes(record.log), text = log.toString('utf8');
    const testResult = parseTestLog(text);
    if (!['analyzer', 'pubget', 'build'].includes(record.stage)) {
      assert(testResult && testResult.failedTests === testResult.failures.length, 'TEST_SUMMARY_OR_FULL_FAILURE_LIST_MISSING');
      if (record.stage === 'cashEpochRed') {
        assert(record.exitCode === 1 && testResult.failedTests > 0 && !testResult.allTestsPassed, 'EXPECTED_RED_REGRESSION_NOT_OBSERVED');
      } else if (record.stage !== 'desktopAll') {
        assert(record.exitCode === 0 && testResult.allTestsPassed && !testResult.failedTests, 'REQUIRED_TEST_STAGE_FAILED');
      } else assert(record.exitCode === (testResult.failedTests ? 1 : 0), 'DESKTOP_EXIT_SUMMARY_MISMATCH');
    } else {
      assert(record.exitCode === 0, 'REQUIRED_ANALYSIS_OR_BUILD_STAGE_FAILED');
      if (record.stage === 'analyzer') assert(text.includes('No issues found!'), 'ANALYSIS_SUCCESS_TEXT_MISSING');
      if (record.stage === 'build') assert(text.includes('Built build') && record.command.includes('--target=lib/main.dart'), 'ORDINARY_BUILD_SUCCESS_MISSING');
    }
    stages.push({ ...record, record: recordPath, recordSha256: sha(await bytes(recordPath)), logSha256: sha(log),
      passedTests: testResult?.passedTests ?? null, failedTests: testResult?.failedTests ?? null,
      skippedTests: testResult?.skippedTests ?? null, failures: testResult?.failures ?? [],
      expectedRed: record.stage === 'cashEpochRed',
      sourceAttribution: record.stage === 'cashEpochRed' ? 'Historical original r10 controller/store control with new r13 regression fixture; final source restored afterward.' : 'Final verified r13 source snapshot' });
  }
  const stage = (name, mode = 'preview') => stages.find(item => String(item.mode).toLowerCase() === mode && item.stage === name);
  for (const name of ['analyzer', 'cashEpochTests', 'cashTests', 'cashFrames', 'modelGatewayTests', 'modelTests', 'modelFrames',
    'authGatewayTests', 'authTests', 'authFrames', 'startupTests', 'keyboardTests', 'platformAll', 'desktopAll', 'build']) {
    assert(stage(name), `REQUIRED_STAGE_MISSING:${name}`);
  }
  assert(stage('build', 'connected'), 'CONNECTED_BUILD_STAGE_MISSING');
  const storeExecutions = parsePlatformStoreExecutions((await bytes(stage('platformAll').log)).toString('utf8'));
  const redPath = `${base}cash-epoch-red-20261009-${revision}.json`, red = await json(redPath);
  const r10Source = await json(`${base}windows-test-preview-source-20261009-r10.json`);
  assert(stage('cashEpochRed') && red.revision === revision && red.originalControlRevision === 'r10' &&
    red.sourceRestored === true && red.redObserved === true && red.exitCode === 1 && red.log === stage('cashEpochRed').log,
    'RED_SOURCE_RESTORATION_RECORD_REQUIRED');
  for (const binding of red.bindings) {
    assert(selected[binding.path] === binding.finalSha256 && sourceManifests.get('preview').buildSourceHashes[binding.path] === binding.finalSha256,
      'REGRESSION_FINAL_SOURCE_NOT_RESTORED');
    assert(r10Source.baseSourceHashes[binding.path] === binding.originalR10Sha256, 'REGRESSION_ORIGINAL_CONTROL_BINDING_INVALID');
  }

  const deliveryPath = `${base}windows-test-delivery-20261009-${revision}.json`;
  const delivery = await json(deliveryPath), archive = await bytes(delivery.zip);
  assert(path.resolve(delivery.packageDirectory) === inside(`dist/Jentra OS Windows Test 20261009 ${revision}`) &&
    path.resolve(delivery.zip) === inside(`dist/Jentra OS Windows Test 20261009 ${revision}.zip`), 'DELIVERY_WRONG_REVISION');
  assert(sha(archive) === delivery.zipSha256 && archive.length === delivery.zipBytes, 'DELIVERY_ZIP_HASH_OR_SIZE_DRIFT');
  const zipEntries = readZipEntries(archive);
  let releaseEntriesVerified = 0;
  for (const [mode, packaged] of packageManifests) {
    for (const file of packaged.releaseFiles) {
      const name = `${path.basename(delivery.packageDirectory)}/${mode === 'preview' ? 'Preview' : 'Connected'}/${file.path}`;
      const entry = zipEntries.get(name);
      assert(entry && sha(zipEntryBytes(archive, entry, file.bytes)) === file.sha256, 'ZIP_RELEASE_ENTRY_HASH_MISMATCH');
      releaseEntriesVerified++;
    }
  }
  assert(releaseEntriesVerified === delivery.verifiedReleaseEntries, 'DELIVERY_RELEASE_COUNT_MISMATCH');

  const framesByFamily = {};
  for (const family of ['cash', 'model', 'auth']) {
    const directory = `${base}windows-test-${family}-frames-20261009-${revision}`;
    const frames = [];
    for (const name of (await readdir(inside(directory))).filter(name => name.endsWith('.png')).sort()) {
      const framePath = `${directory}/${name}`, content = await bytes(framePath);
      assert(content.subarray(0, 8).toString('hex') === '89504e470d0a1a0a', 'RENDER_PNG_REQUIRED');
      frames.push({ path: framePath, sha256: sha(content), width: content.readUInt32BE(16), height: content.readUInt32BE(20), visuallyInspected: false });
    }
    const frameStage = stage(`${family}Frames`);
    const locationsPerCase = family === 'cash' ? 5 : family === 'model' ? 2 : 1;
    assert(frames.length === frameStage.passedTests * locationsPerCase, 'CAPTURE_COUNT_DOES_NOT_MATCH_EXECUTED_CASES');
    framesByFamily[family] = frames;
  }
  const allFrames = Object.values(framesByFamily).flat();
  const inspectedPaths = new Set();
  for (const item of inspection.inspectedFrames) {
    const frame = allFrames.find(frame => frame.path === item.path);
    assert(frame && !inspectedPaths.has(item.path) && item.sha256 === frame.sha256, 'INSPECTION_FRAME_IDENTITY_OR_HASH_MISMATCH');
    assert(typeof item.observation === 'string' && item.observation.trim() && !Number.isNaN(Date.parse(item.inspectedAt)), 'INSPECTION_DETAILS_REQUIRED');
    const family = Object.keys(framesByFamily).find(name => framesByFamily[name].includes(frame));
    assert(Date.parse(item.inspectedAt) >= Date.parse(stage(`${family}Frames`).finishedAt), 'INSPECTION_PRECEDES_COMPLETED_CAPTURE_STAGE');
    frame.visuallyInspected = true; frame.inspection = item; inspectedPaths.add(item.path);
  }
  assert(Object.values(framesByFamily).every(frames => frames.some(frame => frame.visuallyInspected)), 'CASH_MODEL_AUTH_INSPECTION_REQUIRED');

  const retainedPath = `${base}continuation-goldens-native-20261009.json`, retained = await json(retainedPath);
  const desktop = stage('desktopAll'), goldenFailures = desktop.failures.filter(failure => failure.kind === 'golden-comparison');
  const freshGoldens = [];
  for (const failure of goldenFailures) {
    const stem = path.basename(failure.golden, '.png');
    const previous = retained.cases.find(item => item.stem === stem);
    const renders = [];
    for (const kind of ['testImage', 'masterImage', 'isolatedDiff']) {
      const renderPath = relative(path.join(sourceManifests.get('preview').snapshot, 'apps/jentra_desktop/test/failures', `${stem}_${kind}.png`));
      const hash = sha(await bytes(renderPath));
      renders.push({ kind, path: renderPath, sha256: hash,
        identicalToR10: hash === previous?.renders.find(item => item.kind === kind)?.sha256 });
    }
    const approvedPath = `apps/jentra_desktop/test/${failure.golden}`, approvedSha256 = sha(await bytes(approvedPath));
    assert(!previous || approvedSha256 === previous.approvedSha256, 'APPROVED_GOLDEN_HASH_CHANGED');
    assert(renders.find(item => item.kind === 'masterImage').sha256 === approvedSha256, 'FAILURE_MASTER_DOES_NOT_MATCH_APPROVED');
    freshGoldens.push({ ...failure, approved: approvedPath, approvedSha256, renders,
      retainedClassification: previous?.classification ?? null, ownerAccepted: false });
  }
  const spacingPath = 'apps/jentra_desktop/test/wave5_continuation_test.dart';
  const spacingText = (await bytes(path.join(sourceManifests.get('preview').snapshot, spacingPath))).toString('utf8');
  const gapAssertions = [
    ['Horizon start (YYYY-MM-DD)', 'Horizon end, exclusive (YYYY-MM-DD)'],
    ['Issued obligation', 'Authoritative payment date (YYYY-MM-DD)'],
    ['Authoritative payment date (YYYY-MM-DD)', 'Date authority reason'],
  ];
  assert(spacingText.includes('greaterThanOrEqualTo(16)') && spacingText.includes('widget is InputDecorator') &&
    gapAssertions.every(pair => pair.every(label => spacingText.includes(label))) && spacingText.includes('TextScaler.linear(2)'),
    'EXECUTED_SPACING_ASSERTION_SOURCE_MISSING');
  const report = {
    observedAt: new Date().toISOString(), revision, currentSourceMatch: true, sourceFilesPerApp: Object.keys(selected).length,
    sourceScope: 'All current desktop transitive workspace inputs plus all workspace dependency manifests; three verified runner identity overlays per build copy',
    ordinaryEntrypoint: 'lib/main.dart', previewBuilt: true, connectedBuilt: true, releaseEntriesVerified, stages, builds,
    delivery: deliveryPath, deliveryManifestSha256: sha(await bytes(deliveryPath)), zip: delivery.zip,
    zipSha256: delivery.zipSha256, zipBytes: archive.length,
    cashRenderCases: stage('cashFrames').passedTests, cashFrames: framesByFamily.cash,
    modelRenderCases: stage('modelFrames').passedTests, modelFrames: framesByFamily.model, authFrames: framesByFamily.auth,
    cashFramesInspected: framesByFamily.cash.filter(frame => frame.visuallyInspected).length,
    modelFramesInspected: framesByFamily.model.filter(frame => frame.visuallyInspected).length,
    authFramesInspected: framesByFamily.auth.filter(frame => frame.visuallyInspected).length,
    inspectionEvidence: relative(inside(inspectionArgument)), inspectionEvidenceSha256: sha(await bytes(inspectionArgument)),
    textScale: 2, cashSpacing: { minimumInputDecoratorGap: 16, executedInPassedCaptureStage: true,
      fixture: spacingPath, fixtureSha256: selected[spacingPath], assertions: gapAssertions.map(([before, after]) => ({ before, after, minimumLogicalGap: 16 })),
      sourceBoundary: 'Widget geometry and explicitly inspected renders; no authenticated native acceptance.' },
    cashEpochRegression: { record: redPath, recordSha256: sha(await bytes(redPath)), originalControlRevision: 'r10',
      expectedRed: true, redPassedTests: stage('cashEpochRed').passedTests, redFailedTests: stage('cashEpochRed').failedTests,
      finalPassedTests: stage('cashEpochTests').passedTests, currentSourceRestorationVerified: true,
      bindings: red.bindings, boundary: 'Intentional original-control regression is separate from final green verification.' },
    storeTests: { stage: 'platformAll', record: stage('platformAll').record, log: stage('platformAll').log,
      logSha256: stage('platformAll').logSha256, suitePassedTests: stage('platformAll').passedTests,
      files: storeExecutions.map(item => ({ ...item, sourceSha256: selected[item.file] })) },
    broaderSuites: { platformAll: stage('platformAll'), desktopAll: desktop },
    fullDesktopFailures: desktop.failures, goldenFailures: freshGoldens,
    goldenFailureSetMatchesR10: goldenFailures.length === retained.cases.length && goldenFailures.every(failure => retained.cases.some(item => item.golden === failure.golden)),
    goldenCurrentImagesIdenticalToR10: freshGoldens.filter(item => item.renders.find(render => render.kind === 'testImage').identicalToR10).length,
    retainedGoldenInvestigation: retainedPath, retainedGoldenInvestigationSha256: sha(await bytes(retainedPath)),
    sharedGoldensRerun: true, approvedGoldensRegenerated: false,
    nativeLaunched: false, nativeFramesInspected: 0, authenticatedNative: false, authenticatedNativeAcceptance: false,
    nativeKeyboardVerified: false, nativeKeyboardReason: 'Native UI API is disabled in this session; no r13 native input/launch inspection was performed. R10 startup/focus evidence is historical only.',
    historicalNativeEvidence: `${base}windows-test-verification-20261009-r10.json`,
    realMfa: false, actualModelUsage: false, actualWorkerDelivery: false, independentSessionContention: false,
    targetScaleLoad: false, ownerAccepted: false, newMigrationsInstalled: false, formalRuntimeProfileProvisioned: false,
    acceptanceStoresReadOrCopied: false,
  };
  const summaries = stages.map(item => `| ${item.mode} | ${item.stage} | ${item.exitCode} | ${item.passedTests ?? '—'} | ${item.failedTests ?? '—'} |`).join('\n');
  const inspected = inspection.inspectedFrames.map(item => `- [${path.basename(item.path)}](${item.path.replace(base, '')}): ${item.observation}`).join('\n');
  const failureList = desktop.failures.map(item => `- ${item.name}${item.golden ? ` — ${item.golden}` : ''}`).join('\n');
  const markdown = `# Windows continuation verification — ${revision}\n\n` +
    `Two ordinary Windows apps were built and packaged from ${report.sourceFilesPerApp} verified current inputs per app; ${releaseEntriesVerified} shipped release entries were independently hashed in the build directories, portable directories and ZIP. The [machine report](${path.basename(output)}) binds every stage/log, source/package/delivery manifest, render and full-suite failure.\n\n` +
    `Native launch/input/authentication was not verified in this session because the native UI API is disabled. R10 startup inspection is historical. Genuine MFA, delivery, contention/load and owner acceptance remain separate open gates. Approved goldens were preserved.\n\n` +
    `| Mode | Stage | Exit | Passed tests | Failed tests |\n|---|---|---:|---:|---:|\n${summaries}\n\n` +
    `The successful full platform suite includes ${storeExecutions.map(item => `${item.passedCases} named cases from \`${path.basename(item.file)}\``).join(' and ')}; exact executed names and the suite log hash are recorded, without claiming a separate focused run.\n\n` +
    `The cash capture fixture at 200% text asserts a minimum 16 logical pixel gap for the three named InputDecorator pairs in the machine report. ${report.cashRenderCases} cash render cases produced ${report.cashFrames.length} PNGs; ${report.modelRenderCases} model cases produced ${report.modelFrames.length}; auth produced ${report.authFrames.length}. Exactly ${report.cashFramesInspected} cash, ${report.modelFramesInspected} model and ${report.authFramesInspected} auth images were explicitly inspected:\n\n${inspected}\n\n` +
    `Full desktop: ${desktop.passedTests} pass / ${desktop.failedTests} fail. ${goldenFailures.length} failures are golden comparisons; ${report.goldenCurrentImagesIdenticalToR10} current failure images exactly match r10 bytes. Every actual failure is retained below. Investigation or stable image bytes do not provide visual acceptance.\n\n${failureList || 'No desktop failures recorded.'}\n\n` +
    `Portable ZIP: [${path.basename(delivery.zip)}](<../../../dist/${path.basename(delivery.zip)}>)\n\nSHA-256: \`${delivery.zipSha256}\`. The ZIP contains both apps. No installer, acceptance-store copy, native profile, backend installation or real billing operation is established by this report.\n`;
  const finalCurrent = Object.fromEntries(Object.entries(await sources(root)).filter(([name]) =>
    ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'].includes(name) ||
    scope.members.some(member => name === `${member}/pubspec.yaml`) || scope.desktop.some(member => name.startsWith(`${member}/`))));
  assert(equal(selected, finalCurrent), 'SOURCE_CHANGED_DURING_REPORT_VERIFICATION');
  await writeFile(inside(output), JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  await writeFile(inside(markdownOutput), markdown, { flag: 'wx' });
  console.log(JSON.stringify({ report: output, revision, currentSourceMatch: true, sourceFilesPerApp: report.sourceFilesPerApp,
    releaseEntriesVerified, previewBuilt: true, connectedBuilt: true, desktopPassed: desktop.passedTests,
    desktopFailed: desktop.failedTests, inspections: inspectedPaths.size, nativeLaunched: false, nativeKeyboardVerified: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
