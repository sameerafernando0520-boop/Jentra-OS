import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(folder, '../../../..');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = async relative => {
  assert.ok(!path.isAbsolute(relative) && !relative.split('/').includes('..'));
  const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, bytes: bytes.length, sha256: hash(bytes), text: bytes.toString('utf8') };
};
const ref = ({ text, ...binding }) => binding;
const packet = await read('docs/verification/wave5/worker-v4-diagnostic-source-preparation-20261014-r5.json');
const preparation = JSON.parse(packet.text);
assert.equal(preparation.projectId, 'xpdoufauvrbdmxgngetv');
assert.equal(preparation.sourceFiles.length, 5);
assert.equal(preparation.originalV3SourceFiles.length, 5);
const actual = new Map();
for (const binding of [...preparation.sourceFiles, ...preparation.originalV3SourceFiles]) {
  const source = await read(binding.path);
  assert.equal(source.sha256, binding.sha256, binding.path);
  if (binding.bytes !== undefined) assert.equal(source.bytes, binding.bytes);
  actual.set(binding.path, source);
}
const oldRoute = actual.get('workers/wave5/edge_route_20261013_r5_v3.mjs').text;
const newRoute = actual.get('workers/wave5/edge_route_20261014_r5_v4.mjs').text;
const routingBody = source => source.slice(source.indexOf('export function edgeRoute('), source.indexOf('// A finite classification'));
assert.equal(routingBody(newRoute), routingBody(oldRoute));
for (const role of ['runtime', 'receiver']) {
  const oldFactory = actual.get(`workers/wave5/edge_${role}_20261013_r5_v3.mjs`).text;
  const newFactory = actual.get(`workers/wave5/edge_${role}_20261014_r5_v4.mjs`).text;
  assert.equal(newFactory, oldFactory.replace('./edge_route_20261013_r5_v3.mjs', './edge_route_20261014_r5_v4.mjs'));
  const oldEntry = actual.get(`supabase/functions/wave5-${role}/index_20261013_r5_v3.ts`).text;
  const newEntry = actual.get(`supabase/functions/wave5-${role}/index_20261014_r5_v4.ts`).text;
  assert.equal(newEntry, oldEntry.replaceAll('20261013_r5_v3', '20261014_r5_v4'));
}
const test = await read('workers/wave5/edge_route_finite_http_diagnostic_20261014_r5_v4.test.mjs');
const command = ['--test', '--test-isolation=none', '--test-reporter=tap', test.path];
const startedAt = new Date().toISOString();
const run = spawnSync(process.execPath, command, { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 30000, maxBuffer: 1024 * 1024 });
const finishedAt = new Date().toISOString();
const output = (run.stdout ?? '') + (run.stderr ?? '');
await fs.writeFile(path.join(folder, 'worker-v4-independent-focused-tests.tap'), output, { flag: 'wx' });
assert.equal(run.status, 0);
assert.match(output, /^# tests 6$/m);
assert.match(output, /^# pass 6$/m);
assert.match(output, /^# fail 0$/m);
assert.match(output, /^# skipped 0$/m);
for (const source of actual.values()) assert.equal((await read(source.path)).sha256, source.sha256);
const result = {
  kind: 'independent-primary-worker-v4-diagnostic-source-review',
  reviewedAt: new Date().toISOString(), projectId: preparation.projectId,
  technicalVerdict: 'approved for the bounded diagnostic-only development successor',
  scope: 'Two existing Wave 5 workers, five changed source files and one finite observation per isolate.',
  directDelegation: 'docs/verification/wave5/task3-completion-20261013/resumed-autonomy-delegation.json',
  personalHumanSignatureClaimed: false,
  noRouteAllowlistExpansion: true, httpRoutesRemainDenied: true,
  exactRoutingFunctionUnchanged: true,
  factoryImportsOnly: true, entrypointImportsOnly: true,
  downstreamCustomAuthenticationUnchanged: true,
  finiteFieldsReviewed: ['originClass', 'pathClass', 'hostnameClass', 'portClass', 'https', 'query', 'hash', 'userinfo', 'routeRecognized'],
  rawRequestValuesLogged: false,
  maximumDiagnosticsPerIsolate: 1,
  noDiagnosticReadOfHeadersBodyOrMethod: true,
  reasoning: 'Only finite classifications and the diagnostic marker change. Canonical routing and every schedule, caller, HMAC, scoped RPC and authority check retain their exact v3 source. A sink failure cannot alter the handler response. The diagnostic identifies the actual internal origin without logging a URL, host value or private request field.',
  sourcePreparation: ref(packet),
  sourceBindings: [...actual.values()].map(ref),
  actualIndependentLocalRun: { startedAt, finishedAt, nodeVersion: process.version, command: ['node', ...command], exitCode: run.status, tests: 6, passed: 6, failed: 0, skipped: 0, log: { path: 'docs/verification/wave5/task3-completion-20261013/worker-v4-independent-focused-tests.tap', sha256: hash(output), bytes: Buffer.byteLength(output) }, testSource: ref(test) },
  deployedByThisReview: false, probesSentByThisReview: 0,
  schedulesResumedByThisReview: false,
  authenticatedWorkerSuccessEstablished: false,
  actualDeliveryEstablished: false,
  production: false, realBilling: false,
  boundary: 'This approves the reviewed diagnostic source, not a routing fix, successful delivery or a new personal human signoff. The live owner must bind the complete deployment payload and verify returned sources before its single scoped probe.'
};
const text = JSON.stringify(result, null, 2) + '\n';
await fs.writeFile(path.join(folder, 'worker-v4-independent-source-review.json'), text, { flag: 'wx' });
process.stdout.write(JSON.stringify({ technicalApproved: true, sourceBindings: actual.size, localTests: 6, passed: 6, sourceReviewSha256: hash(text) }) + '\n');
