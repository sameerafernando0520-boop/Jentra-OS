import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const audit = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(audit, '../../../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = relative => fs.readFileSync(path.resolve(workspace, relative));
const json = relative => JSON.parse(read(relative));
const binding = candidate => {
  const absolute = path.resolve(workspace, candidate);
  const bytes = fs.readFileSync(absolute);
  return { path: candidate.replaceAll('\\', '/'), bytes: bytes.length, sha256: sha(bytes) };
};
const observedAt = new Date().toISOString();
const evidencePaths = [
  'docs/verification/wave5/fresh-desktop-verification-20261014-o13r7.json',
  'docs/verification/wave5/native-preview-keyboard-observation-20261014-o13r7.json',
  'docs/verification/wave5/native-keyboard-failure-investigation-20261012-r5.json',
  'docs/verification/wave5/native-keyboard-artifact-review-20261013-r5.json',
  'docs/verification/wave5/native-preview-userflows-20261010-r5.json',
  'docs/verification/wave5/keyboard-audit-20261014/probe-preparation.json',
  'docs/verification/wave5/keyboard-audit-20261014/probe-source-repair-a3.json',
];
const sdkPaths = [
  'C:/src/flutter/packages/flutter/lib/src/widgets/shortcuts.dart',
  'C:/src/flutter/packages/flutter/lib/src/widgets/default_text_editing_shortcuts.dart',
  'C:/src/flutter/packages/flutter/lib/src/services/hardware_keyboard.dart',
  'C:/src/flutter/engine/src/flutter/shell/platform/windows/keyboard_manager.cc',
  'C:/src/flutter/engine/src/flutter/shell/platform/windows/keyboard_key_embedder_handler.cc',
  'C:/src/flutter/engine/src/flutter/shell/platform/windows/flutter_window.cc',
  'C:/src/flutter/bin/cache/flutter.version.json',
];
const documentationPaths = [
  'C:/Users/sheha/.codex/plugins/cache/openai-bundled/computer-use/26.1007.21434/docs/api.md',
  'C:/Users/sheha/.codex/plugins/cache/openai-bundled/computer-use/26.1007.21434/docs/guidance.md',
  'C:/Users/sheha/.codex/plugins/cache/openai-curated-remote/superpowers/6.4.2/skills/systematic-debugging/SKILL.md',
  'C:/Users/sheha/.codex/plugins/cache/openai-curated-remote/superpowers/6.4.2/skills/using-superpowers/SKILL.md',
];
const productPaths = [
  'apps/jentra_desktop/lib/src/shell/jentra_shell.dart',
  'apps/jentra_desktop/lib/src/app.dart',
  'apps/jentra_desktop/lib/src/router.dart',
  'apps/jentra_desktop/test/command_palette_keyboard_test.dart',
  'apps/jentra_desktop/test/jentra_app_test.dart',
  'apps/jentra_desktop/lib/src/features/setup/business_setup_screen.dart',
  'apps/jentra_desktop/windows/runner/flutter_window.cpp',
  'apps/jentra_desktop/windows/runner/flutter_window.h',
  'apps/jentra_desktop/windows/runner/win32_window.cpp',
  'apps/jentra_desktop/windows/runner/main.cpp',
];
const manifests = [
  'docs/verification/wave5/windows-test-preview-source-20261009-o13r7.json',
  'docs/verification/wave5/windows-test-connected-source-20261009-o13r7.json',
];
const guards = manifests.map(candidate => {
  const manifest = json(candidate);
  const mismatches = [];
  for (const [relative, expected] of Object.entries(manifest.baseSourceHashes)) {
    if (sha(read(relative)) !== expected) mismatches.push({ kind: 'workspace', path: relative });
  }
  for (const [relative, expected] of Object.entries(manifest.buildSourceHashes)) {
    if (sha(fs.readFileSync(path.join(manifest.snapshot, relative))) !== expected) {
      mismatches.push({ kind: 'snapshot', path: relative });
    }
  }
  return { ...binding(candidate), mode: manifest.mode, snapshot: manifest.snapshot,
    baseInputs: Object.keys(manifest.baseSourceHashes).length,
    buildInputs: Object.keys(manifest.buildSourceHashes).length,
    overlays: manifest.overlays, mismatches };
});
if (guards.some(guard => guard.mismatches.length)) throw new Error('CURRENT_O13R7_SOURCE_DRIFT');
const preview = guards[0].snapshot;
const executablePath = path.join(preview, 'apps/jentra_desktop/build/windows/x64/runner/Release/Jentra_OS.exe');
const enginePath = path.join(preview, 'apps/jentra_desktop/build/windows/x64/runner/Release/flutter_windows.dll');
const sdkEnginePath = 'C:/src/flutter/bin/cache/artifacts/engine/windows-x64-release/flutter_windows.dll';
const observation = json(evidencePaths[1]);
const fresh = json(evidencePaths[0]);
const repair = json(evidencePaths[6]);
const currentProbe = binding('build/w5kbdprobe20261014/lib/main.dart');
if (currentProbe.sha256 !== repair.after.sha256) throw new Error('REPAIRED_PROBE_SOURCE_DRIFT');
const source = read('docs/verification/wave5/keyboard-audit-20261014/probe.dart')
  .toString('utf8').replaceAll('\r\n', '\n');
const expectedRepair = source.replace('static const _allowed = <LogicalKeyboardKey>{',
  'static final _allowed = <LogicalKeyboardKey>{').trimEnd() + '\n}\n';
if (read(currentProbe.path).toString('utf8').replaceAll('\r\n', '\n') !== expectedRepair) {
  throw new Error('UNEXPECTED_PROBE_REPAIR_DIFF');
}
const report = {
  kind: 'source-bound-native-keyboard-investigation',
  dateAsiaColombo: '2026-10-14', revision: 'o13r7',
  startedAt: observedAt, finishedAt: new Date().toISOString(),
  result: 'Cause not yet established; standalone receiver prepared and analyzer source errors repaired.',
  directObservationBoundary: 'Root performed the actual sky calls and inspected tool screenshots. This investigator did not perform or replay native actions; no fresh screenshot file was persisted by root.',
  rootObservation: { binding: binding(evidencePaths[1]), record: observation },
  terminology: 'Key-style means sky.press_key; a human physical keyboard has not been independently tested.',
  rootFreshVerification: { binding: binding(evidencePaths[0]),
    fullDesktopTests: fresh.fullDesktopTests, freshRenderTestCases: fresh.freshRenderTestCases,
    freshPngs: fresh.freshPngs, builds: fresh.builds,
    boundary: 'Existing root evidence read and hashed; no SDK analysis/test/build/render run by this investigator.' },
  currentReadOnlySourceGuards: guards,
  earlierReadOnlyAudit: {
    beforeToolChunk: '42de56', beforeObservedAt: '2026-10-14T01:14:07.918Z',
    afterToolChunk: 'd4e069', afterStartedAt: '2026-10-14T01:22:17.181Z',
    afterFinishedAt: '2026-10-14T01:22:24.463Z',
    result: 'Zero mismatches in 1069 workspace and 1069 snapshot inputs for each Preview/Connected manifest, and all selected public evidence/SDK/documentation/binary bindings unchanged.',
  },
  productSourceBindings: productPaths.map(candidate => ({
    workspace: binding(candidate),
    previewSnapshot: binding(path.join(preview, candidate)),
    bytesEqual: sha(read(candidate)) === sha(fs.readFileSync(path.join(preview, candidate))),
    identityOverlayExpected: candidate === 'apps/jentra_desktop/windows/runner/main.cpp',
  })),
  sdkSourceBindings: sdkPaths.map(binding),
  documentationAndSkills: documentationPaths.map(binding),
  sdkMetadata: json(sdkPaths.at(-1)),
  previewExecutable: binding(executablePath),
  previewEngine: binding(enginePath), currentSdkEngine: binding(sdkEnginePath),
  previewMatchesCurrentSdkEngine: sha(fs.readFileSync(enginePath)) === sha(fs.readFileSync(sdkEnginePath)),
  versionBoundary: 'Local source bytes and DLL identity are distinct evidence from binary instrumentation; external report tool/SDK versions differ.',
  preservedEvidence: evidencePaths.map(binding),
  productFindings: [
    { source: productPaths[0], lines: '34-40', finding: 'Standard CallbackShortcuts SingleActivator(keyK,control:true) with autofocus child Focus; no Control remapping.' },
    { source: productPaths[0], lines: '618-651,687-694', finding: 'Palette handles arrow/Enter, ignores other keys, and uses normal autofocus TextField without formatter explaining whole-string loss.' },
    { source: productPaths[3], lines: '61-63', finding: 'Widget fixture holds Control, sends K, releases Control; it bypasses Windows/tool delivery. enterText bypasses native literal delivery.' },
    { source: productPaths[6], lines: '54-60', finding: 'Normal Flutter message forwarding; no custom keyboard normalization/filter.' },
    { source: productPaths[9], finding: 'Normal TranslateMessage/DispatchMessage Windows loop; only title differs in the approved snapshot overlay.' },
    { source: productPaths[8], lines: '210-213,249', finding: 'Normal native child focus setup; UIA categories alone do not identify Dart focus ancestry or actual modifier state.' },
  ],
  frameworkFindings: [
    { source: sdkPaths[0], lines: '576-580,1212-1215', finding: 'Activator requires correct trigger down/repeat and pressed modifiers.' },
    { source: sdkPaths[1], lines: '318-320', finding: 'Default Control+A maps to SelectAllTextIntent; modifier loss can affect both product shortcut and standard editor.' },
    { source: sdkPaths[4], lines: '115-121,160-175,227-245', finding: 'Physical fallback identity derives from scan code; zero scan ordinary keys can share identity and pressed records.' },
    { source: sdkPaths[3], lines: '223-237,246-247,387-398', finding: 'Packet keys bypass ordinary key events, but standalone printable WM_CHAR dispatches text. Packet bypass alone does not show Unicode unsupported.' },
    { source: sdkPaths[4], lines: '425-496', finding: 'Modifier synchronization consults native key state and can synthesize corrections; actual trace remains necessary.' },
  ],
  primaryWebSources: [
    { title: 'Flutter SingleActivator', url: 'https://api.flutter.dev/flutter/widgets/SingleActivator-class.html', claim: 'Trigger event with required modifier state.' },
    { title: 'Flutter HardwareKeyboard', url: 'https://api.flutter.dev/flutter/services/HardwareKeyboard-class.html', claim: 'Native event regularization and possible synthesized corrections.' },
    { title: 'Windows KEYBDINPUT', url: 'https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-keybdinput', claim: 'Packet/Unicode text and scan-code injection are distinct routes.' },
    { title: 'Windows SendInput', url: 'https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput', claim: 'Existing keyboard state and integrity boundaries affect injection.' },
    { title: 'First-hand Computer Use receiver report', url: 'https://github.com/openai/codex/issues/43575',
      inspectedState: 'Open when read', evidenceType: 'External first-hand receiver trace; not a current Jentra observation or confirmed maintainer diagnosis.',
      versionBoundary: 'Reported Flutter3.44.9/bundle26.901.51231 differs from Jentra3.47.5/documentation26.1007.21434.',
      claim: 'Same literal-empty/key-style-success/Control-selection failure; report traces zero scan fields and compares supplying scan information.' },
    { title: 'Flutter equal-scan-code proposal', url: 'https://github.com/flutter/flutter/issues/99198',
      inspectedState: 'Open when read', claim: 'Distinct logical keys may share zero scan codes in emulated Windows shortcuts.' },
  ],
  hypotheses: [
    { id: 'H1', priority: 'leading', hypothesis: 'Zero ordinary-key scan fields collapse modifier/trigger physical identity and lose Control at K/A/V.',
      support: 'External receiver report plus compatible current engine fallback and correlated Jentra failures.',
      stillMissing: 'Current Jentra native scan fields/Flutter event trace.',
      distinguishingResult: 'Probe Control and letter show the same fallback physical ID, trigger Control false; single key works.' },
    { id: 'H2', priority: 'alternative', hypothesis: 'Activation/sequence changes native or Flutter modifier/focus state.',
      distinguishingResult: 'Distinct physical IDs with incorrect modifier state or missing local focused key delivery.' },
    { id: 'H3', priority: 'conditional product path', hypothesis: 'Correctly delivered chord does not reach shell Focus ancestor.',
      distinguishingResult: 'Default receiver accepts the chord; product receives correct K/Control state but binding does not fire.' },
    { id: 'H4', priority: 'literal route alternative', hypothesis: 'Literal input uses a different text/paste route from key-style input.',
      stillMissing: 'Current sky implementation is uninspected; do not assume clipboard or Unicode.',
      distinguishingResult: 'Visible Ctrl/V without text, absent literal events or differing text route in local receiver.' },
  ],
  standaloneReceiver: {
    projectRoot: 'C:/Users/sheha/Desktop/Jentra OS/build/w5kbdprobe20261014',
    windowTitle: 'Jentra Keyboard Probe - TEST ONLY', currentMain: currentProbe,
    initialPreparation: binding(evidencePaths[5]), successorRepair: binding(evidencePaths[6]),
    exactTwoChangeRepairVerified: true,
    historicalRootAnalysis: { attempt: 'a2', exitCode: 1, issues: 20,
      errors: '19 constant LogicalKeyboardKey set elements plus missing class-closing brace.',
      outputs: repair.preservedSdkEvidence, preserved: true },
    preparationBoundary: 'Original docs/probe.dart and initial preparation retain failing source. Successor repair binds corrected main and root-SDK-regenerated plugin files.',
    scope: 'SDK-only default MaterialApp/TextField, no product imports/config/plugins/storage.',
    UI: 'Eight local allowlisted KeyDown/KeyUp metadata rows, physical/logical IDs, Control/pressed state, accepted CtrlK count, synthetic text/selection.',
    privacy: 'No character payload, clipboard/device/global-input capture, persistence or network; observer returns false, gated by field focus/window lifecycle and removed on dispose.',
    pendingRootActions: [
      'Run scoped analyze --no-pub lib/main.dart, then build windows --release --no-pub --target=lib/main.dart serially.',
      'Bind actual built EXE/DLL and final managed/generated project files.',
      'Select actual unique probe window, click/observe synthetic field and separately observe key-style k, Control_L+k and literal Finance.',
      'Compare IDs/modifier/acceptance counter/text/selection before proposing product changes.',
    ],
    analysisOrBuildRunByThisInvestigator: false, nativeRunByThisInvestigator: false,
  },
  fixBoundary: [
    'If zero-scan collisions are confirmed, address the injection/scan-code compatibility boundary; never weaken Control+K to plain K.',
    'A missing-scan normalization comparison belongs first in an isolated receiver, preserves nonzero/extended data, excludes packet/IME paths, and is not a production patch.',
    'Correct received chord with product-only failure justifies a narrow Focus/binding diagnostic rather than speculative global shortcut duplication.',
  ],
  skills: {
    initiallyUnavailable: true, restoredBeforeProbeSourceRepair: true,
    applied: 'Superpowers systematic-debugging: actual failed analysis read, exact two source errors isolated, narrow repair, red evidence preserved and real validation pending.',
    usingSuperpowersBoundary: 'Read skill explicitly exempts dispatched subagents from orchestration workflow.',
  },
  preservedNativeGates: {
    originalNativeReport: { cases: 33, passed: 27, failed: 4, blocked: 2,
      sha256: '4a8783db056143e7cf6d8031bc30dba7ff7707e315324892acf05fa2fac42840' },
    historicalFailuresRelabeled: false, fullNativeKeyboard: false, authenticatedNative: false,
    ownerAcceptanceGranted: false, rootCauseProven: false,
  },
  investigatorActions: {
    sdkJobs: 0, nativeActions: 0, liveProjectCalls: 0, credentialsOrStoresOrSessionsRead: false,
    productSourceEdits: 0, existingSnapshotEdits: 0, existingBuildOutputEdits: 0,
    baselinesChanged: false, acceptanceChanges: 0, gitMutation: false,
    standaloneSourceRepaired: true, newStandaloneProjectPrepared: true,
    publicSourceAndDocumentationReads: true,
  },
};
const jsonPath = path.join(audit, 'investigation-o13r7.json');
const mdPath = path.join(audit, 'investigation-o13r7.md');
if (fs.existsSync(jsonPath) || fs.existsSync(mdPath)) throw new Error('NEW_REPORTS_REQUIRED');
const md = [
  '# Native keyboard investigation and isolated receiver - 14 October 2026', '',
  '**Native keyboard remains unverified.** The source review identifies a concrete injection/scan-code hypothesis and prepares a standalone receiver. It does not establish a Jentra root cause, change product shortcuts or grant acceptance.', '',
  'Root separately observed failed Control+K from dashboard and Finance, literal Finance text remaining invisible, visible Search opening the palette, and key-style f followed by Return navigating to Finance. The [root observation](../native-preview-keyboard-observation-20261014-o13r7.json) is bound at SHA-256 6ed4d9a165f5a726baaed5f2a0586ef36255ec09ac45121932e3392029e3cca7. This investigator did not repeat UI actions; root inspected tool screenshots without saving a screenshot file. Key-style input means sky.press_key, not a tested human keyboard.', '',
  'The app uses the standard Control+K SingleActivator, autofocus Focus and normal TextField. Widget tests hold Control, send K and release Control, bypassing native injection. The runner forwards and translates Windows messages normally.', '',
  'The leading hypothesis is zero ordinary-key scan fields collapsing Control and the trigger to one fallback physical identity. An [external first-hand receiver report](https://github.com/openai/codex/issues/43575) reproduces the same pattern, while [Flutter issue99198](https://github.com/flutter/flutter/issues/99198) documents equal zero scan codes in emulated Windows shortcuts. Current local engine source has the compatible fallback. External tool/SDK versions differ; this remains corroboration, not a Jentra diagnosis.', '',
  '[SingleActivator](https://api.flutter.dev/flutter/widgets/SingleActivator-class.html) requires a trigger event with matching modifier state; [HardwareKeyboard](https://api.flutter.dev/flutter/services/HardwareKeyboard-class.html) regularizes native events. Actual Jentra modifier delivery remains untraced. [Windows packet/Unicode input](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-keybdinput) has a text route distinct from scan-code keys. Packet-key bypass alone does not establish unsupported Unicode. The current sky.type_text implementation was not inspected.', '',
  'Read-only guards matched 1,069 workspace inputs and 1,069 snapshot inputs for each Preview/Connected o13r7 manifest, with three recorded identity overlays and zero mismatches. Existing [fresh desktop verification](../fresh-desktop-verification-20261014-o13r7.json) records 2,026 passing tests across 138 files, 26 render cases / 86 PNGs and two builds; those jobs were not rerun by this investigator. Preview EXE SHA-256: 88ffac37c5d4b7ae5b4b83ceb91ba939c420753223979ca0061acc46581c8e74; its DLL matches the current SDK release DLL at SHA-256 8bd7b61eee31aa436edb182db41624d1cd3b2688a7e03622320dbeae067b5251.', '',
  'The SDK-only receiver project is C:/Users/sheha/Desktop/Jentra OS/build/w5kbdprobe20261014, title Jentra Keyboard Probe - TEST ONLY. It shows one synthetic TextField, text/selection, accepted Control+K count and eight in-memory rows of allowlisted local key metadata. The observer returns false and records only with test-field focus and active receiver window. No character payload, clipboard/device/global-input capture, persistence, network or product storage is included.', '',
  'Root a2 analysis exited 1 with 19 constant-set-element errors and a missing class brace. The narrow repair changed standalone lib/main.dart only: static const to static final, plus the closing brace. Exact two-change comparison passed fe9aab. Original docs/probe.dart, initial preparation and all failed SDK outputs remain preserved. [Successor repair evidence](probe-source-repair-a3.json), SHA-256 a1705863b306b3b58dc5a37997c7abbc6eadde0d5aa9be2cf8f7e4d2f7ed1c6f, binds corrected main SHA-256 49a57c93ad6c14c14943a760ffa04e4a386c2d6ce8a28b54359c44674800229d and root-regenerated plugin files. This source check is not an analyzer/build pass.', '',
  'Root must serialize scoped analysis and Windows release build in that project, bind actual EXE/DLL/final managed files, then select the actual probe window. Click and freshly observe the synthetic field; separately observe key-style k, Control_L+k and literal Finance. Compare physical/logical IDs, Control state, accepted count and visible text/selection. Same fallback identity with Control false implicates the compatibility boundary; correct distinct IDs/modifier state with product-only failure justifies a narrow Focus/binding investigation.', '',
  'Do not weaken Control+K to plain K. Any scan normalization comparison belongs first in the isolated receiver, preserves nonzero/extended input and excludes packet/IME paths; it is not a product patch.', '',
  'Superpowers systematic-debugging was unavailable at the initial source review and restored before repair. It was read and applied to the actual analyzer failure. No SDK/native/live/private operation was performed by this investigator. The original 33-case report remains 27 pass / 4 fail / 2 blocked; full keyboard, authenticated native and owner acceptance remain separate open gates.', '',
  '[Exact source/evidence bindings and hypotheses](investigation-o13r7.json)', '',
].join('\n');
fs.writeFileSync(jsonPath, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
fs.writeFileSync(mdPath, md, { flag: 'wx' });
process.stdout.write(JSON.stringify({published: true, observedAt, sourceGuards: guards.map(g => ({
  mode: g.mode, baseInputs: g.baseInputs, buildInputs: g.buildInputs, mismatches: g.mismatches.length,
})), currentProbe, files: [binding(jsonPath), binding(mdPath)], rootCauseProven: false,
sdkJobs: 0, nativeActions: 0}) + '\n');
