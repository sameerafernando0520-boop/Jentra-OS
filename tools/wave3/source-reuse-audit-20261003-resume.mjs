import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';

// Read-only current source comparison. The captures keep their original dates;
// this audit never backdates executions or treats a commit as a test run.
const base = 'docs/verification/remaining-wave3/';
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const normalize = file => file.replaceAll('\\', '/');
const compare = (file, rows, field = 'file') => ({
  file, sha256: hash(file), files: rows.length,
  mismatches: rows.filter(row => !fs.existsSync(normalize(row[field])) || hash(normalize(row[field])) !== row.sha256.toLowerCase())
    .map(row => ({file: normalize(row[field]), captured_sha256: row.sha256.toLowerCase(),
      current_sha256: fs.existsSync(normalize(row[field])) ? hash(normalize(row[field])) : null})),
});
const desktopFile = base + 'client-sources-desktop-final-20261003.json';
const domainFile = base + 'client-sources-domain-final-20261003.json';
const platformFile = base + 'client-sources-platform-20261003.json';
const buildFile = base + 'windows-source-hashes-20261003-final.json';
const coverageFile = base + 'requirements-coverage-pre-policy-reviewed-20261003.json';
const domain = read(domainFile), platform = read(platformFile);
const report = {
  generated_at: new Date().toISOString(),
  head: execFileSync('git', ['rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
  desktop_actual_execution: {...compare(desktopFile, read(desktopFile).files), execution_observed_at: read(desktopFile).observed_at},
  domain_actual_execution: {...compare(domainFile, domain.files), execution_observed_at: domain.observed_at},
  domain_package_libs: compare(domainFile, domain.files.filter(row => row.file.startsWith('packages/jentra_domain/lib/'))),
  platform_actual_execution: {...compare(platformFile, platform.files), execution_observed_at: platform.observed_at},
  platform_package_libs: compare(platformFile, platform.files.filter(row => row.file.startsWith('packages/jentra_platform/lib/'))),
  isolated_windows_compilation: compare(buildFile, read(buildFile), 'path'),
  prior_coverage_source_comparison: compare(coverageFile, read(coverageFile).files.map(row => ({file:row.file,sha256:row.source_sha256}))),
  boundary:'Current read-only comparison against unchanged original execution/compilation/coverage captures. A matching source can retain that recorded synthetic result; a mismatch requires fresh evidence. This report supplies no new execution, installed/authenticated/native/load/visual acceptance or owner signoff.',
};
const output = base + 'source-reuse-audit-20261003-resume.json';
fs.writeFileSync(output, JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({head:report.head,...Object.fromEntries(Object.entries(report).filter(([,value])=>value?.mismatches).map(([key,value])=>[key,{files:value.files,mismatches:value.mismatches.map(row=>row.file)}]))}));
