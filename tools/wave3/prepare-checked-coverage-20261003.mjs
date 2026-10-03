import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// This prepares inputs for the existing reviewed summarizer. It runs no tests.
const root = 'docs/verification/remaining-wave3/';
const build = 'build/remaining-wave3/';
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const prior = read(build + 'coverage-profile-source-checked-20261002.json');
const scope = root + 'requirements-coverage-paths-20261003.txt';
const paths = fs.readFileSync(scope, 'utf8').trim().split(/\r?\n/);
if (paths.length !== 189 || new Set(paths).size !== 189) throw Error('Expected independently reviewed 189-path scope');
const normalize = file => file.replaceAll('\\', '/');
const pairs = [
  ...prior.checked_inputs,
  { file: build + 'desktop-full-20261003.info', base: 'apps/jentra_desktop', source_fingerprint: root + 'client-sources-full-desktop-20261003.json' },
  { file: build + 'recovery-focused-final-20261003.info', base: 'apps/jentra_desktop', source_fingerprint: root + 'client-sources-final-green-20261003.json' },
];
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i += 4) {
  if (args[i] !== '--pair' || !args[i + 3]) throw Error('Use --pair info-file package-base paired-source-fingerprint');
  pairs.push({file: normalize(args[i + 1]), base: normalize(args[i + 2]), source_fingerprint: normalize(args[i + 3])});
}
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
const sourceFingerprint = root + 'requirements-coverage-current-sources-20261003.json';
// Current hashes only establish declaration-only inputs and current measurement
// scope. They never backdate an executed LCOV file; each has its own paired capture.
const fingerprint = {
  observed_at: new Date().toISOString(),
  boundary: 'Current source scope only. Executed records are accepted only against their own paired execution capture.',
  files: paths.map(file => ({file, sha256: hash(file)})),
};
fs.writeFileSync(sourceFingerprint, JSON.stringify(fingerprint, null, 2) + '\n');
const pureDomainHistory = [
  {file: build + 'desktop-read-access-full-coverage-20260930.info', base: 'apps/jentra_desktop', source_fingerprint: root + 'client-sources-read-access-start-20260930.json'},
  {file: build + 'platform-read-access-full-coverage-20260930.info', base: 'packages/jentra_platform', source_fingerprint: root + 'client-sources-read-access-start-20260930.json'},
];
for (const entry of pureDomainHistory) if (!fs.existsSync(entry.file) || !fs.existsSync(entry.source_fingerprint)) throw Error('Missing domain history');
const profile = {
  inputs: checked.map(entry => [entry.file, entry.base]),
  checked_inputs: checked,
  source_fingerprint: sourceFingerprint,
  changed_paths: scope,
  output: root + 'requirements-coverage-source-checked-20261003.json',
  pure_domain_history: pureDomainHistory,
  source_overrides: [],
};
const output = build + 'requirements-coverage-profile-20261003.json';
fs.writeFileSync(output, JSON.stringify(profile, null, 2) + '\n');
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
fs.writeFileSync(root + 'requirements-coverage-input-audit-20261003.json', JSON.stringify({
  generated_at: new Date().toISOString(), scope: {file: scope, sha256: hash(scope), paths: 189},
  locked_summarizer: {file: 'tools/wave3/summarize-final-coverage.mjs', sha256: hash('tools/wave3/summarize-final-coverage.mjs')},
  generator: {file: 'tools/wave3/prepare-checked-coverage-20261003.mjs', sha256: hash('tools/wave3/prepare-checked-coverage-20261003.mjs')},
  boundary: 'Coverage records measure executed code even where a suite failed. This profile asserts no suite pass, native acceptance or visual signoff. All stale records are rejected by the unchanged summarizer. Zero-executable declaration files remain separately labelled.',
  inputs: audit,
}, null, 2) + '\n');
console.log(JSON.stringify({profile: output, checked_inputs: checked.length, current_source_scope: paths.length,
  next_command: 'node tools/wave3/summarize-final-coverage.mjs ' + output}));
