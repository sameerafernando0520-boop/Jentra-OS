import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {artifactTag, writeNewJson} from './strict-candidate-evidence.mjs';

// This prepares inputs for the existing reviewed summarizer. It runs no tests.
const root = 'docs/verification/remaining-wave3/';
const build = 'build/remaining-wave3/';
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const prior = read(build + 'coverage-profile-source-checked-20261002.json');
const baselineScope = root + 'requirements-coverage-paths-20261003.txt';
const baselinePaths = fs.readFileSync(baselineScope, 'utf8').trim().split(/\r?\n/);
if (baselinePaths.length !== 189 || new Set(baselinePaths).size !== 189) throw Error('Expected independently reviewed cumulative 189-path baseline');
let scope = baselineScope;
let tag = '20261003';
const normalize = file => file.replaceAll('\\', '/');
const pairs = [
  ...prior.checked_inputs,
  { file: build + 'desktop-full-20261003.info', base: 'apps/jentra_desktop', source_fingerprint: root + 'client-sources-full-desktop-20261003.json' },
  { file: build + 'recovery-focused-final-20261003.info', base: 'apps/jentra_desktop', source_fingerprint: root + 'client-sources-final-green-20261003.json' },
];
const args = process.argv.slice(2);
for (let i = 0; i < args.length;) {
  if (args[i] === '--scope' && args[i+1]) {
    scope = normalize(args[i+1]); i += 2;
  } else if (args[i] === '--artifact-tag' && args[i+1]) {
    tag = artifactTag(args[i+1]); i += 2;
  } else if (args[i] === '--extend-profile' && args[i+1]) {
    const preservedPath=normalize(args[i+1]);
    if(!preservedPath.startsWith(build)||!preservedPath.endsWith('.json'))throw Error('Extend only an explicit saved local coverage profile.');
    const preserved=read(preservedPath);
    if(!Array.isArray(preserved.checked_inputs)||!preserved.checked_inputs.length)throw Error('Saved profile lacks actual paired inputs.');
    pairs.push(...preserved.checked_inputs);i+=2;
  } else if (args[i] === '--pair' && args[i+3]) {
    pairs.push({file: normalize(args[i + 1]), base: normalize(args[i + 2]), source_fingerprint: normalize(args[i + 3])}); i += 4;
  } else throw Error('Use --scope additive-path-list, --artifact-tag unique-tag, --extend-profile saved-profile, or --pair info-file package-base paired-source-fingerprint');
}
const paths = fs.readFileSync(scope, 'utf8').trim().split(/\r?\n/);
if (!scope.startsWith(root) || paths.length < baselinePaths.length || new Set(paths).size !== paths.length || baselinePaths.some(file=>!paths.includes(file))) throw Error('Additive coverage scope must retain all189 reviewed baseline paths');
// The locked summarizer requires every pure-domain source to match when using
// pure_domain_history. New policy support changed lead_to_cash.dart. Preserve
// both actual history pairs in its existing per-file checked-input mechanism,
// which accepts unchanged measured records and rejects stale records honestly.
const pureDomainHistory = [
  {file: build + 'desktop-read-access-full-coverage-20260930.info', base: 'apps/jentra_desktop', source_fingerprint: root + 'client-sources-read-access-start-20260930.json'},
  {file: build + 'platform-read-access-full-coverage-20260930.info', base: 'packages/jentra_platform', source_fingerprint: root + 'client-sources-read-access-start-20260930.json'},
];
pairs.push(...pureDomainHistory);
for (const entry of pairs) if (pairs.some(other=>other.file===entry.file && (other.base!==entry.base || other.source_fingerprint!==entry.source_fingerprint))) throw Error('The same executed LCOV must retain its original package/source capture.');
const checked = [...new Map(pairs.map(entry => [entry.file, entry])).values()];
for (const entry of checked) {
  if (!entry.file.startsWith(build) || !entry.file.endsWith('.info') ||
      !entry.source_fingerprint.startsWith(root) || !entry.source_fingerprint.endsWith('.json') ||
      !['apps/jentra_desktop', 'packages/jentra_platform', 'packages/jentra_domain'].includes(entry.base)) {
    throw Error('Unexpected coverage input boundary: ' + JSON.stringify(entry));
  }
  if (!fs.existsSync(entry.file) || !fs.existsSync(entry.source_fingerprint)) throw Error('Missing paired input: ' + JSON.stringify(entry));
  if (!Array.isArray(read(entry.source_fingerprint).files)) throw Error('Invalid source capture');
}
const sourceFingerprint = root + `requirements-coverage-current-sources-${tag}.json`;
const output = build + `requirements-coverage-profile-${tag}.json`;
const auditOutput = root + `requirements-coverage-input-audit-${tag}.json`;
if ([sourceFingerprint, output, auditOutput, root + `requirements-coverage-source-checked-${tag}.json`].some(file=>fs.existsSync(file))) throw Error('Retain the previous derivative; choose an unused --artifact-tag.');
// Current hashes only establish declaration-only inputs and current measurement
// scope. They never backdate an executed LCOV file; each has its own paired capture.
const fingerprint = {
  observed_at: new Date().toISOString(),
  boundary: 'Current source scope only. Executed records are accepted only against their own paired execution capture.',
  files: paths.map(file => ({file, sha256: hash(file)})),
};
writeNewJson(sourceFingerprint, fingerprint);
const profile = {
  inputs: checked.map(entry => [entry.file, entry.base]),
  checked_inputs: checked,
  source_fingerprint: sourceFingerprint,
  changed_paths: scope,
  output: root + `requirements-coverage-source-checked-${tag}.json`,
  pure_domain_history: [],
  historical_pure_domain_inputs_moved_to_checked_inputs: pureDomainHistory,
  source_overrides: [],
};
writeNewJson(output, profile);
const audit = checked.map(entry => {
  const sources = new Map(read(entry.source_fingerprint).files.map(row => [row.file, row.sha256]));
  const records = [...fs.readFileSync(entry.file, 'utf8').matchAll(/^SF:([^\r\n]+)/gm)].map(match =>
    normalize(path.relative(process.cwd(), path.isAbsolute(match[1]) ? match[1] : path.resolve(entry.base, match[1]))));
  return {...entry, info_sha256: hash(entry.file), paired_capture_sha256: hash(entry.source_fingerprint),
    measured_records: records.length,
    current_records: records.filter(file => fs.existsSync(file) && sources.get(file) === hash(file)).length,
    stale_or_missing_records: records.filter(file => !fs.existsSync(file) || sources.get(file) !== hash(file)),
  };
});
writeNewJson(auditOutput, {
  generated_at: new Date().toISOString(), scope: {file: scope, sha256: hash(scope), paths: paths.length, baseline_file:baselineScope, baseline_paths:baselinePaths.length, additional_paths:paths.filter(file=>!baselinePaths.includes(file))},
  locked_summarizer: {file: 'tools/wave3/summarize-final-coverage.mjs', sha256: hash('tools/wave3/summarize-final-coverage.mjs')},
  generator: {file: 'tools/wave3/prepare-checked-coverage-20261003.mjs', sha256: hash('tools/wave3/prepare-checked-coverage-20261003.mjs')},
  boundary: 'Coverage records measure executed code even where a suite failed. This profile asserts no suite pass, native acceptance or visual signoff. All stale records are rejected by the unchanged summarizer. Zero-executable declaration files remain separately labelled.',
  inputs: audit,
});
console.log(JSON.stringify({profile: output, checked_inputs: checked.length, current_source_scope: paths.length,
  next_command: 'node tools/wave3/summarize-final-coverage.mjs ' + output}));
