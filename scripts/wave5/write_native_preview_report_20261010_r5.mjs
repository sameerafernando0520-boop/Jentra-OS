// Human-readable report from the actual completed, source-bound native record.
// No UI, SDK, account, store, live operation or acceptance decision occurs here.
import {open, readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = 'docs/verification/wave5/';
const source = base + 'native-preview-userflows-20261010-r5.json';
const output = base + 'native-preview-userflows-20261010-r5.md';
const raw = await readFile(path.join(root, source));
const record = JSON.parse(raw);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const must = (ok, label) => {if (!ok) throw Error(label);};
const cell = value => String(value).replaceAll('|', '\\|').replaceAll('\n', ' ');
must(process.argv.length === 2 && record.kind === 'actual-native-preview-userflow-observations' &&
  record.revision === 'r5' && record.mode === 'Preview' && record.status === 'complete' &&
  record.nativeLaunched === true && record.observations.length > 0, 'ACTUAL_COMPLETED_NATIVE_RECORD_REQUIRED');
for (const gate of ['authenticatedNative', 'fullNativeKeyboardGate', 'accountingTransactionsPosted',
  'authoritativeReportsGenerated', 'actualDelivery', 'realMfa', 'actualModelUsage',
  'independentSessionContention', 'targetScaleLoad', 'ownerAcceptanceChanged'])
  must(record[gate] === false, 'PREVIEW_BROADER_GATE_CHANGED:' + gate);
for (const result of ['pass', 'fail', 'blocked', 'observed'])
  must(record.observations.filter(row => row.result === result).length === record.counts[result], 'ACTUAL_CASE_COUNTS_REQUIRED');
must(record.counts.observed === 0, 'NO_OPEN_NATIVE_CASES_ALLOWED');
const references = [record.package, record.sourceManifest, record.prelaunchPathObservation,
  record.recorder, record.predecessor, record.historicalPredecessor, record.productBuildEvidence];
for (const ref of references)
  must(sha(await readFile(path.resolve(root, ref.path))) === ref.sha256, 'NATIVE_BOUND_INPUT_DRIFT:' + ref.path);
must(sha(await readFile(record.executable)) === record.executableSha256, 'ACTUAL_NATIVE_EXECUTABLE_DRIFT');
for (const row of record.observations) for (const image of row.screenshots) {
  must(image.path.startsWith(base + 'native-preview-20261010-r5/' + row.id + '-'), 'SCOPED_NATIVE_SCREENSHOT_REQUIRED');
  const bytes = await readFile(path.join(root, image.path));
  must(bytes.length === image.bytes && sha(bytes) === image.sha256, 'ACTUAL_SCREENSHOT_DRIFT:' + image.path);
}
const rows = record.observations.map(row => `| ${cell(row.id)} | ${row.result} | ${cell(row.action)} | ${cell(row.observed)} | ${row.screenshots.map(image => `[Image](${path.relative(path.join(root, base), path.join(root, image.path)).split(path.sep).join('/')})`).join(', ')} |`).join('\n');
const report = Buffer.from(`# Actual ordinary Windows Preview observations — r5\n\n[Exact completed record](${path.basename(source)}), SHA-256 \`${sha(raw)}\`. Actual UI actions ran from ${record.startedAt} to ${record.finishedAt}. The 20261010 label identifies the planned r5 product and evidence paths; these timestamps identify when each action occurred.\n\n${record.observations.length} closed cases: ${record.counts.pass} passed, ${record.counts.fail} failed, ${record.counts.blocked} blocked. These observations concern the ordinary offline Preview executable and supported \`@oai/sky\` input API. They do not establish authenticated native acceptance, a complete native keyboard gate, actual accounting posting, reports, MFA, governed exports, delivery, trusted model usage, independent-session contention, target-scale load or additional owner acceptance.\n\nInput-tool documentation observed: ${record.inputToolEvidence.documentationObservedAt}. Input-package version: ${record.inputToolEvidence.packageVersion ?? 'not independently verified'}; verified: ${record.inputToolEvidence.packageVersionVerified}. Product SDK: Flutter ${record.productSdk.frameworkVersion}, Dart ${record.productSdk.dartSdkVersion}. The matching controlled desktop suite finished at ${record.productSuiteObservedAt}; no rerun is inferred from this native session.\n\n| Case | Result | Actual action | Observed outcome | Evidence |\n| --- | --- | --- | --- | --- |\n${rows}\n\nThe exact returned process/window identities, package/build/source bindings and native screenshots are recorded separately from build-only evidence. Prelaunch checks examined existence of four exact new product paths, with no session or acceptance-store contents read or copied. Postlaunch path metadata is a separate later artifact. Existing accounts, sessions and Wave 3/4/Employee work remain preserved. Exactly AC-551, AC-552 and AC-553 remain directly accepted; the other 106 criteria are open. Production and real billing remain excluded.\n`);
must(sha(await readFile(path.join(root, source))) === sha(raw), 'NATIVE_RECORD_CHANGED_DURING_REPORT');
const handle = await open(path.join(root, output), 'wx');
try {await handle.writeFile(report); await handle.sync();} finally {await handle.close();}
must(sha(await readFile(path.join(root, output))) === sha(report), 'NATIVE_REPORT_WRITE_DRIFT');
console.log(JSON.stringify({path: output, sha256: sha(report), cases: record.observations.length,
  counts: record.counts, SDKExecuted: false, nativeActionsPerformed: false, ownerAcceptanceChanged: false}));
