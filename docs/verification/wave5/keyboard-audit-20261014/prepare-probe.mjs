import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// Copies only explicitly named public runner files into a NEW isolated project.
// It runs no SDK, native input, network, credential, account or store operation.
const auditRoot = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(auditRoot, '../../../..');
const destination = path.resolve(workspace, 'build/w5kbdprobe20261014');
const manifestPath = path.join(auditRoot, 'probe-preparation.json');
const binaryName = 'Jentra_Keyboard_Probe';
const title = 'Jentra Keyboard Probe - TEST ONLY';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const inside = (parent, child) => {
  const relative = path.relative(parent, child);
  return relative === '' || (!relative.startsWith(`..${path.sep}`)
    && relative !== '..' && !path.isAbsolute(relative));
};
const exists = async candidate => {
  try { await fs.stat(candidate); return true; }
  catch (error) { if (error.code === 'ENOENT') return false; throw error; }
};
const binding = async candidate => {
  const bytes = await fs.readFile(candidate);
  return { path: candidate.replaceAll('\\', '/'), bytes: bytes.length, sha256: sha(bytes) };
};
const copyFiles = [
  'windows/CMakeLists.txt', 'windows/flutter/CMakeLists.txt',
  'windows/runner/CMakeLists.txt', 'windows/runner/flutter_window.cpp',
  'windows/runner/flutter_window.h', 'windows/runner/main.cpp',
  'windows/runner/utils.cpp', 'windows/runner/utils.h',
  'windows/runner/win32_window.cpp', 'windows/runner/win32_window.h',
  'windows/runner/Runner.rc', 'windows/runner/resource.h',
  'windows/runner/runner.exe.manifest', 'windows/runner/resources/app_icon.ico',
];

async function verify() {
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  if (manifest.projectRoot !== destination.replaceAll('\\', '/')) throw new Error('UNEXPECTED_PROBE_ROOT');
  for (const ref of manifest.projectSources) {
    const actual = await binding(path.join(destination, ref.relativePath));
    if (actual.sha256 !== ref.sha256 || actual.bytes !== ref.bytes) throw new Error(`PROBE_SOURCE_CHANGED:${ref.relativePath}`);
  }
  for (const ref of manifest.originSources) {
    const actual = await binding(ref.path);
    if (actual.sha256 !== ref.sha256 || actual.bytes !== ref.bytes) throw new Error('ORIGIN_SOURCE_CHANGED');
  }
  return { mode: 'verify-only', verifiedAt: new Date().toISOString(),
    sources: manifest.projectSources.length, origins: manifest.originSources.length,
    sdkJobs: 0, nativeActions: 0, manifest: await binding(manifestPath) };
}

async function prepare() {
  if (!inside(path.join(workspace, 'build'), destination)) throw new Error('PROBE_PATH_BOUNDARY');
  if (await exists(destination) || await exists(manifestPath)) throw new Error('NEW_PROBE_TARGET_REQUIRED');
  const origins = [], sources = [];
  const queued = [];
  const probePath = path.join(auditRoot, 'probe.dart');
  const probe = await fs.readFile(probePath);
  origins.push(await binding(probePath), await binding(fileURLToPath(import.meta.url)));
  queued.push({ relativePath: 'lib/main.dart', bytes: probe, origin: probePath });
  for (const relativePath of copyFiles) {
    const source = path.join(workspace, 'apps/jentra_desktop', relativePath);
    const bytes = await fs.readFile(source);
    origins.push(await binding(source));
    let copied = bytes;
    if (relativePath === 'windows/CMakeLists.txt') {
      const text = bytes.toString('utf8');
      if (!text.includes('project(jentra_desktop') || !text.includes('set(BINARY_NAME "jentra_desktop")')) throw new Error('WINDOWS_TEMPLATE_CHANGED');
      copied = Buffer.from(text.replace('project(jentra_desktop', 'project(jentra_keyboard_probe')
        .replace('set(BINARY_NAME "jentra_desktop")', `set(BINARY_NAME "${binaryName}")`));
    } else if (relativePath === 'windows/runner/main.cpp') {
      const text = bytes.toString('utf8');
      if (!text.includes('window.Create(L"jentra_desktop"')) throw new Error('WINDOW_TITLE_TEMPLATE_CHANGED');
      copied = Buffer.from(text.replace('window.Create(L"jentra_desktop"', `window.Create(L"${title}"`));
    } else if (relativePath === 'windows/runner/Runner.rc') {
      copied = Buffer.from(bytes.toString('utf8').replaceAll('jentra_desktop', binaryName));
    }
    queued.push({ relativePath, bytes: copied, origin: source });
  }
  const pubspec = [
    'name: jentra_keyboard_probe', 'description: Standalone synthetic Windows keyboard receiver.',
    'publish_to: none', 'version: 0.0.1+1', 'environment:', "  sdk: '>=3.13.0 <4.0.0'",
    'dependencies:', '  flutter:', '    sdk: flutter', 'flutter:',
    '  uses-material-design: true', '',
  ].join('\n');
  queued.push({ relativePath: 'pubspec.yaml', bytes: Buffer.from(pubspec), origin: 'new-sdk-only-manifest' });
  queued.push({ relativePath: 'windows/flutter/generated_plugin_registrant.h', origin: 'new-empty-plugin-registry', bytes: Buffer.from(
    '#ifndef GENERATED_PLUGIN_REGISTRANT_\n#define GENERATED_PLUGIN_REGISTRANT_\n#include <flutter/plugin_registry.h>\nvoid RegisterPlugins(flutter::PluginRegistry* registry);\n#endif\n') });
  queued.push({ relativePath: 'windows/flutter/generated_plugin_registrant.cc', origin: 'new-empty-plugin-registry', bytes: Buffer.from(
    '#include "generated_plugin_registrant.h"\nvoid RegisterPlugins(flutter::PluginRegistry* registry) { (void)registry; }\n') });
  queued.push({ relativePath: 'windows/flutter/generated_plugins.cmake', origin: 'new-empty-plugin-registry', bytes: Buffer.from(
    'list(APPEND FLUTTER_PLUGIN_LIST)\nlist(APPEND FLUTTER_FFI_PLUGIN_LIST)\nset(PLUGIN_BUNDLED_LIBRARIES)\n') });
  await fs.mkdir(path.dirname(destination), { recursive: true });
  await fs.mkdir(destination);
  for (const item of queued) {
    const target = path.join(destination, item.relativePath);
    if (!inside(destination, target)) throw new Error('PROBE_FILE_BOUNDARY');
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, item.bytes, { flag: 'wx' });
    sources.push({ relativePath: item.relativePath, bytes: item.bytes.length, sha256: sha(item.bytes),
      sourceOrigin: item.origin.replaceAll('\\', '/') });
  }
  const record = { kind: 'standalone-keyboard-probe-preparation', preparedAt: new Date().toISOString(),
    projectRoot: destination.replaceAll('\\', '/'), binaryName, windowTitle: title,
    originSources: origins, projectSources: sources, dependencyBoundary: 'Flutter SDK only; no product Dart/config/plugins or private files copied.',
    diagnosticBoundary: 'Only allowlisted Flutter key metadata while this receiver text field is focused and its window is active; eight in-memory rows, no character payload capture or persistence.',
    sdkJobs: 0, nativeActions: 0, networkCalls: 0, secretOrStoreReads: 0, productEdits: 0,
    analysisOrBuildPassed: false, nativeDiagnosisEstablished: false, nativeKeyboardWholeGatePassed: false,
    commandsForRootOnly: [
      'C:/src/flutter/bin/flutter.bat pub get --offline',
      'C:/src/flutter/bin/flutter.bat analyze --no-pub lib/main.dart',
      'C:/src/flutter/bin/flutter.bat build windows --release --no-pub --target=lib/main.dart',
    ],
    expectedExecutable: path.join(destination, 'build/windows/x64/runner/Release', `${binaryName}.exe`).replaceAll('\\', '/'),
  };
  await fs.writeFile(manifestPath, JSON.stringify(record, null, 2) + '\n', { flag: 'wx' });
  return { mode: 'prepared-not-built', projectRoot: record.projectRoot, sources: sources.length,
    manifest: await binding(manifestPath), analysisOrBuildPassed: false, nativeDiagnosisEstablished: false };
}

const argumentsList = process.argv.slice(2);
if (argumentsList.length > 1 || (argumentsList.length === 1 && argumentsList[0] !== '--verify')) throw new Error('INVALID_ARGUMENT');
process.stdout.write(JSON.stringify(argumentsList.length ? await verify() : await prepare()) + '\n');
