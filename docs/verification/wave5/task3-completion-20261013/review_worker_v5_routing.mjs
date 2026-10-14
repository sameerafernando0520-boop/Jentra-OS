import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url)), root = path.resolve(folder, '../../../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = async relative => {const bytes = await fs.readFile(path.join(root, relative));
  return {path: relative, bytes: bytes.length, sha256: sha(bytes), text: bytes.toString('utf8')};};
const ref = ({text, ...binding}) => binding;
const packet = await read('docs/verification/wave5/worker-v5-routing-source-preparation-20261014-r5.json');
const preparation = JSON.parse(packet.text);
assert.equal(preparation.projectId, 'xpdoufauvrbdmxgngetv');
assert.equal(preparation.sourceFiles.length, 5); assert.equal(preparation.predecessorFiles.length, 5);
assert.equal(preparation.handlerAuthenticationAndScopeUnchanged, true);
assert.equal(preparation.schedulesRemainPaused, true);
const sources = new Map();
for (const binding of [...preparation.sourceFiles, ...preparation.predecessorFiles, preparation.actualFiniteObservation]) {
  const actual = await read(binding.path); assert.equal(actual.sha256, binding.sha256, binding.path);
  if (binding.bytes !== undefined) assert.equal(actual.bytes, binding.bytes);
  sources.set(actual.path, actual);
}
const observedFile = sources.get(preparation.actualFiniteObservation.path), observed = JSON.parse(observedFile.text);
assert.equal(observed.requestIdMatchesSavedProbe, true);
assert.deepEqual(observed.actualFiniteTuple, {originClass: 'other', pathClass: 'function_namespace',
  hostnameClass: 'project_host', portClass: 'default', https: false, query: false, hash: false, userinfo: false, routeRecognized: false});
const old = sources.get('workers/wave5/edge_route_20261014_r5_v4.mjs').text;
const next = sources.get('workers/wave5/edge_route_20261014_r5_v5.mjs').text;
const extract = (source, start, end) => source.slice(source.indexOf(start), source.indexOf(end));
assert.equal(extract(old, 'const endpoints=', 'function parseUrl'), extract(next, 'const endpoints=', 'function parseUrl'));
assert.equal(extract(old, 'function parseUrl', 'function configuredEndpoint'),
  extract(next, 'function parseUrl', 'function exactRequestUrl'));
assert.equal(extract(old, 'function configuredEndpoint', 'export function edgeRoute'),
  extract(next, 'function configuredEndpoint', 'export function edgeRoute'));
const expectedRouting = extract(old, 'export function edgeRoute', '// A finite classification')
  .replace('!exactHttpsUrl(requestUrl,url)', '!exactRequestUrl(requestUrl,url)')
  .replace("  :url.origin===platformOrigin?[endpoint.namespace]:[];", "  :url.origin===projectHttpOrigin?[endpoint.namespace]\n  :url.origin===platformOrigin?[endpoint.namespace]:[];");
assert.equal(extract(next, 'export function edgeRoute', '// A finite classification'), expectedRouting);
for (const role of ['runtime', 'receiver']) {
  const oldFactory = sources.get(`workers/wave5/edge_${role}_20261014_r5_v4.mjs`).text;
  const newFactory = sources.get(`workers/wave5/edge_${role}_20261014_r5_v5.mjs`).text;
  assert.equal(newFactory, oldFactory.replace('./edge_route_20261014_r5_v4.mjs', './edge_route_20261014_r5_v5.mjs'));
  const oldEntry = sources.get(`supabase/functions/wave5-${role}/index_20261014_r5_v4.ts`).text;
  const newEntry = sources.get(`supabase/functions/wave5-${role}/index_20261014_r5_v5.ts`).text;
  assert.equal(newEntry, oldEntry.replaceAll('20261014_r5_v4', '20261014_r5_v5'));
}
const tests = await Promise.all(['workers/wave5/edge_route_project_http_20261014_r5_v5.test.mjs',
  'workers/wave5/edge_factory_project_http_20261014_r5_v5.test.mjs'].map(read));
const command = ['--test', '--test-isolation=none', '--test-reporter=tap', ...tests.map(row => row.path)];
const env = Object.fromEntries(['SystemRoot','WINDIR','TEMP','TMP'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
const startedAt = new Date().toISOString();
const run = spawnSync(process.execPath, command, {cwd: root, env, windowsHide: true, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024});
const output = (run.stdout ?? '') + (run.stderr ?? '');
const logPath = path.join(folder, 'worker-v5-independent-focused-tests.tap');
await fs.writeFile(logPath, output, {flag: 'wx'});
assert.equal(run.status, 0); assert.match(output, /^# tests 10$/m); assert.match(output, /^# pass 10$/m);
assert.match(output, /^# fail 0$/m); assert.match(output, /^# skipped 0$/m);
for (const source of [...sources.values(), ...tests]) assert.equal((await read(source.path)).sha256, source.sha256);
const report = {kind: 'independent-worker-v5-narrow-managed-hop-routing-source-review', reviewedAt: new Date().toISOString(),
  projectId: preparation.projectId, technicalVerdict: 'approve narrow existing-development worker source successor',
  inference: 'V4 proves non-HTTPS project hostname/default port/function namespace. HTTP is a source-bound hypothesis to be confirmed by the one bounded V5 probe.',
  routeChange: 'Only canonical HTTP on exact current project hostname and exact existing function namespace; public configured endpoints remain HTTPS.',
  publicHttpFunctionPrefixDenied: true, platformHttpDenied: true, foreignHostsPortsQueryHashUserinfoDenied: true,
  endpointsAndAllowedRoutesUnchanged: true, callerScheduleHmacMfaAndScopeChecksUnchanged: true,
  factoryAndEntrypointImportsOnly: true, finiteDiagnosticOnly: true, rawRequestValuesLogged: false,
  directDelegation: 'docs/verification/wave5/task3-completion-20261013/resumed-autonomy-delegation.json',
  personalHumanExactSourceSignatureClaimed: false,
  sourcePreparation: ref(packet), sourceBindings: [...sources.values()].map(ref),
  actualIndependentControlledRun: {startedAt, finishedAt: new Date().toISOString(), exitCode: run.status, tests: 10, passed: 10,
    log: {path: path.relative(root, logPath).replaceAll('\\','/'), bytes: Buffer.byteLength(output), sha256: sha(output)}, testSources: tests.map(ref)},
  deploymentPayloadReviewStillRequired: true, probesSentByReviewer: 0, schedulesResumedByReviewer: false,
  actualAuthenticatedWorkerSuccess: false, actualDelivery: false, nativeAcceptance: false, targetScaleLoad: false,
  productionReleaseReady: false, newPermissionsOrAccounts: 0, acceptanceRowsAdded: 0};
const bytes = Buffer.from(JSON.stringify(report, null, 2) + '\n');
const destination = path.join(folder, 'worker-v5-independent-source-review.json');
await fs.writeFile(destination, bytes, {flag: 'wx'});
process.stdout.write(JSON.stringify({sourceApproved: true, testsPassed: 10,
  report: {path: path.relative(root, destination).replaceAll('\\','/'), bytes: bytes.length, sha256: sha(bytes)}}) + '\n');
