import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {artifactTag, writeNewJson} from './strict-candidate-evidence.mjs';

const reviewed = new Map([
  ['packages/jentra_domain/lib/src/crm_repository.dart', '74a23abff32478905d6a72c6ffa217ba069943cea18a19002cba4ec11531e1c1'],
  ['packages/jentra_domain/lib/src/lead_to_cash_repository.dart', '051259583fcd7aa4d9e570903a28dc0719916457a174e8bea92ffe2557e79fe1'],
]);
export function supplement(raw, diagnostic, captures) {
  const copy = structuredClone(raw);
  const changed = [];
  for (const [file, sha256] of reviewed) {
    const row = copy.files.find(row => row.file === file);
    const certified = diagnostic.rows.find(row => row.file === file);
    if (!row || !certified?.declarations_only || certified.sha256 !== sha256 ||
        row.source_sha256 !== sha256 || !captures.some(capture => capture.files.some(row => row.file === file && row.sha256 === sha256))) {
      throw Error('Exact reviewed declaration/source capture mismatch: ' + file);
    }
    if (row.measured || row.lines !== 0 || row.branches !== 0) throw Error('Unexpected executable measurement in interface: ' + file);
    row.declarations_only = true;
    row.execution_source_matches = true;
    changed.push(file);
  }
  for (const total of [copy.changed_dart, copy.pure_domain]) {
    total.unmeasured_executable = total.unmeasured_executable.filter(file => !changed.includes(file));
    total.source_mismatches = total.source_mismatches.filter(file => !changed.includes(file));
  }
  copy.gates.changed_dart_line_80 = copy.changed_dart.line_percent >= 80 && !copy.changed_dart.unmeasured_executable.length && !copy.changed_dart.source_mismatches.length;
  copy.gates.pure_domain_branch_90 = copy.pure_domain.branch_percent >= 90 && !copy.pure_domain.unmeasured_executable.length && !copy.pure_domain.source_mismatches.length;
  copy.declaration_correction = {
    exact_reviewed_files: changed,
    boundary: 'Only exact two reviewed declaration flags and paired current-source match flags are corrected. Selected scope, measured hits, executable lines, branches, numerators, denominators and thresholds are identical to the unchanged locked raw report. Compilation remains separately executed suite evidence.',
    raw_gates: raw.gates,
  };
  for (const key of ['files', 'lines', 'lines_hit', 'branches', 'branches_hit', 'line_percent', 'branch_percent']) {
    assert.equal(copy.changed_dart[key], raw.changed_dart[key]);
    assert.equal(copy.pure_domain[key], raw.pure_domain[key]);
  }
  assert.equal(copy.files.length, raw.files.length);
  return copy;
}

if (process.argv.includes('--self-test')) {
  const files = [...reviewed].map(([file, source_sha256]) => ({file, source_sha256, measured: false, declarations_only: false, execution_source_matches: false, lines: 0, branches: 0}));
  const total = {files: 189, lines: 100, lines_hit: 80, branches: 10, branches_hit: 9, line_percent: 80, branch_percent: 90, unmeasured_executable: [...reviewed.keys()], source_mismatches: [...reviewed.keys()]};
  const raw = {files, changed_dart: total, pure_domain: {...total, files: 25}, gates: {changed_dart_line_80: false, pure_domain_branch_90: false}};
  const diagnostic = {rows: [...reviewed].map(([file, sha256]) => ({file, sha256, declarations_only: true}))};
  const capture = {files: diagnostic.rows};
  const result = supplement(raw, diagnostic, [capture]);
  assert.equal(result.gates.changed_dart_line_80, true);
  assert.equal(raw.gates.changed_dart_line_80, false);
  assert.equal(result.files.length, 2);
  const low = structuredClone(raw); low.changed_dart.line_percent = 79.99;
  assert.equal(supplement(low, diagnostic, [capture]).gates.changed_dart_line_80, false);
  const pending = structuredClone(raw); pending.changed_dart.unmeasured_executable.push('executable.dart');
  assert.equal(supplement(pending, diagnostic, [capture]).gates.changed_dart_line_80, false);
  const altered = structuredClone(raw); altered.files[0].source_sha256 = 'changed';
  assert.throws(() => supplement(altered, diagnostic, [capture]), /mismatch/);
  assert.throws(() => supplement(raw, diagnostic, []), /mismatch/);
  console.log('Supplement self-test passed: exact classification only; raw retained; threshold, remaining-executable and mismatched-source safeguards');
} else {
  const root = 'docs/verification/remaining-wave3/';
  const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
  const [rawFile = root + 'requirements-coverage-source-checked-20261003.json', diagnosticFile = root + 'requirements-declaration-diagnostic-20261003.json', captureFile = root + 'client-sources-full-desktop-20261003.json', selectedTag = '20261003'] = process.argv.slice(2);
  const tag = artifactTag(selectedTag);
  for (const [file, expected] of reviewed) if (crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') !== expected) throw Error('Reviewed source changed');
  const out = supplement(read(rawFile), read(diagnosticFile), [read(captureFile)]);
  out.raw_report = {file: rawFile, sha256: crypto.createHash('sha256').update(fs.readFileSync(rawFile)).digest('hex')};
  out.declaration_diagnostic = diagnosticFile;
  out.declaration_paired_execution_capture = captureFile;
  out.generated_at = new Date().toISOString();
  const output = root + `requirements-coverage-declaration-reviewed-${tag}.json`;
  writeNewJson(output, out);
  console.log(JSON.stringify({output, gates: out.gates, remaining_unmeasured: out.changed_dart.unmeasured_executable, line_percent: out.changed_dart.line_percent}));
}
