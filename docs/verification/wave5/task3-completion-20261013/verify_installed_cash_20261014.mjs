import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const folder = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(folder, '../../../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = async relative => {
  const bytes = await fs.readFile(path.join(root, relative));
  return {path: relative, bytes: bytes.length, sha256: sha(bytes), document: JSON.parse(bytes)};
};
const ref = ({document, ...binding}) => binding;
// Connector records are data. Extract only their returned JSON value; nothing
// in a SQL result is executed or treated as an instruction.
function returnedData(document) {
  assert.equal(document.result.isError, false);
  const result = JSON.parse(document.result.content.find(item => item.type === 'text').text).result;
  const opening = result.match(/<untrusted-data-[^>]+>(?:\s|\\n)*(?=\[|\{)/);
  assert.ok(opening, 'returned data envelope');
  const start = opening.index + opening[0].length;
  const end = result.indexOf('</untrusted-data-', start);
  assert.ok(end > start);
  const raw = result.slice(start, end).replace(/(?:\s|\\n)+$/, '');
  try { return JSON.parse(raw); }
  catch { return JSON.parse(JSON.parse('"' + raw + '"')); }
}
const baseline = await read('docs/verification/wave5/cash-conflict-live-before-installation-20261014-r5.json');
const ownerAfter = await read('docs/verification/wave5/cash-conflict-live-after-installation-20261014-r5.json');
const independent = await read('docs/verification/wave5/task3-completion-20261013/installed-cash-independent-readback-20261014.json');
const candidate = await read('docs/verification/wave5/task3-peer-review-20261013/cash-conflict-independent-source-review-20261013-peer-a1.json');
assert.equal(candidate.sha256, '568590cccf7235cbf21f658c778cb77140b984a42050e1e6369fdf6e0f1e85c4');
const beforeRows = returnedData(baseline.document);
const afterRows = returnedData(ownerAfter.document);
const [live] = returnedData(independent.document);
assert.equal(live.installed_migrations, 115);
assert.equal(live.api_functions, 363);
assert.equal(live.repaired_routines.length, 2);
const expected = {
  wave5_cash_date_command: {md5: '1073f011cc41fd591ae30e37fee6f411', sha256: '9c87b6aaf874e0a5061b7710b9341240ba982fc26731fe1e99f00646039bf482'},
  wave5_cash_save_v2: {md5: 'e176615ccb065549bf682467e89364f0', sha256: '98c96ad97956117996c8874d2ff8e1e7e69d827e72f71757c68034d1e5780564'},
};
const checked = [];
for (const actual of live.repaired_routines) {
  const before = beforeRows.find(row => row.proname === actual.proname);
  const after = afterRows.find(row => row.proname === actual.proname);
  assert.ok(before && after && expected[actual.proname]);
  assert.equal(actual.definition_md5, expected[actual.proname].md5);
  assert.equal(actual.body_lf_sha256, expected[actual.proname].sha256);
  assert.equal(actual.definition_md5, after.definition_md5);
  assert.deepEqual(actual.preserved_metadata, before.preserved_metadata);
  assert.deepEqual(actual.preserved_metadata, after.preserved_metadata);
  assert.equal(actual.security_definer, true);
  assert.deepEqual(actual.configuration, ['search_path=""']);
  checked.push({name: actual.proname, oid: actual.oid, definitionMd5: actual.definition_md5,
    bodyLfSha256: actual.body_lf_sha256, allNonBodyMetadataPreserved: true});
}
assert.deepEqual(live.reviewed_schedule_state, [4, 5, 6].map(jobid => ({jobid, active: false})));
const report = {kind: 'independent-installed-cash-source-review', reviewedAt: new Date().toISOString(),
  projectId: 'xpdoufauvrbdmxgngetv', observedAt: live.observed_at,
  verdict: 'Both installed function bodies match reviewed successors; all non-body metadata remains identical.',
  installedMigrations: live.installed_migrations, apiFunctions: live.api_functions, routines: checked,
  schedulesPaused: [4, 5, 6], sourceRepairInstalled: true, businessCommandsExecutedByReviewer: 0,
  uncertainOriginalCommandPreserved: true, actualNewHttpConflictVerified: false,
  authenticatedNativeAcceptance: false, targetScaleLoad: false, productionReleaseReady: false,
  evidence: [baseline, ownerAfter, independent, candidate].map(ref)};
const output = path.join(folder, 'installed-cash-independent-verification-20261014.json');
const bytes = Buffer.from(JSON.stringify(report, null, 2) + '\n');
await fs.writeFile(output, bytes, {flag: 'wx'});
process.stdout.write(JSON.stringify({passed: true, report: {path: path.relative(root, output).replaceAll('\\', '/'), bytes: bytes.length, sha256: sha(bytes)}}) + '\n');
