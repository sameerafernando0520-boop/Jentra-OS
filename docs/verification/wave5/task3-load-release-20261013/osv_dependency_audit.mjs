import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url)), root = path.resolve(folder, '../../../..');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const lockBytes = await fs.readFile(path.join(root, 'pubspec.lock'));
const lock = lockBytes.toString('utf8'), matches = [...lock.matchAll(/^  ([a-z0-9_]+):\r?$/gm)], dependencies = [];
for (let index = 0; index < matches.length; index++) {
  const match = matches[index], block = lock.slice(match.index, matches[index + 1]?.index ?? lock.length);
  if (!/^    source: hosted\r?$/m.test(block)) continue;
  const version = block.match(/^    version: "([^"]+)"\r?$/m)?.[1];
  if (!version || !/^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9.+-]*$/.test(version)) throw Error('EXACT_HOSTED_DEPENDENCY_REQUIRED');
  dependencies.push({ name: match[1], version });
}
if (!dependencies.length) throw Error('HOSTED_DEPENDENCY_POPULATION_REQUIRED');
const startedAt = new Date().toISOString();
const queries = dependencies.map(({ name, version }) => ({ package: { name, ecosystem: 'Pub' }, version }));
let outcome = { completed: false, failureCode: 'DEPENDENCY_ADVISORY_LOOKUP_UNAVAILABLE' };
try {
  const response = await fetch('https://api.osv.dev/v1/querybatch', { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ queries }), signal: AbortSignal.timeout(20000), redirect: 'error' });
  const raw = await response.text();
  if (!response.ok || raw.length > 2000000) throw Error('UNEXPECTED_ADVISORY_RESPONSE');
  const data = JSON.parse(raw);
  if (!Array.isArray(data.results) || data.results.length !== dependencies.length) throw Error('INCOMPLETE_ADVISORY_RESPONSE');
  outcome = { completed: true, httpStatus: response.status, responseSha256: hash(raw),
    dependencies: dependencies.map((dependency, index) => ({ ...dependency,
      advisoryIds: (data.results[index].vulns ?? []).map(vulnerability => vulnerability.id) })),
    packagesWithAdvisories: data.results.filter(result => (result.vulns ?? []).length > 0).length,
    advisoryCount: data.results.reduce((count, result) => count + (result.vulns ?? []).length, 0),
    noKnownAdvisoriesAtLookup: data.results.every(result => (result.vulns ?? []).length === 0) };
} catch { /* Only the fixed public failure code is preserved. No retries or settings changes. */ }
const after = await fs.readFile(path.join(root, 'pubspec.lock'));
const record = { kind: 'actual-readonly-osv-hosted-dart-dependency-audit', startedAt, finishedAt: new Date().toISOString(),
  endpoint: 'https://api.osv.dev/v1/querybatch', ecosystem: 'Pub', hostedDependencyCount: dependencies.length,
  requestSha256: hash(JSON.stringify({ queries })), lockfileSha256: hash(lockBytes), lockfilePreserved: hash(lockBytes) === hash(after),
  requestContainsPublicPackageNamesAndVersionsOnly: true, SDKJobs: 0, installationPerformed: false, ...outcome,
  limitation: 'Known advisory database lookup for exact hosted lockfile versions. It does not audit Flutter/Dart engine, path dependencies, new undisclosed defects, transitive native binaries or production configuration.' };
const bytes = JSON.stringify(record, null, 2) + '\n';
const handle = await fs.open(path.join(folder, 'dart-dependency-audit.json'), 'wx');
try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
console.log(JSON.stringify({ path: 'dart-dependency-audit.json', sha256: hash(bytes), hostedDependencyCount: dependencies.length,
  completed: outcome.completed, packagesWithAdvisories: outcome.packagesWithAdvisories,
  advisoryCount: outcome.advisoryCount, lockfilePreserved: record.lockfilePreserved }));
