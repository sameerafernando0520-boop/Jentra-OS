// Offline successor; the original preparation and all frozen review bytes stay intact.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = relative => fs.readFileSync(path.join(root, relative));
const originalPlan = 'docs/verification/wave5/installed-verification-plan-20261012-r5.json';
assert.equal(hash(read(originalPlan)), '17aa5cb966070f2766f2ec9460b29a6bcad0d2fa3b6ed027f8790b88868c6ea1');
const plan = JSON.parse(read(originalPlan));
assert.equal(plan.review.bundleSha256, 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b');
assert.equal(plan.review.operationScopeSha256, 'fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63');
for (const item of plan.queries) assert.equal(hash(read(item.path)), item.sha256);
assert.equal(hash(read(plan.preparationTool.path)), plan.preparationTool.sha256);
let sql = read(plan.queries.find(item => item.id === 'catalog').path).toString('utf8');
const corrections = [
  ["p.provolatile=e.volatility", "p.provolatile::text=e.volatility"],
  ["'config',p.proconfig,", "'configFingerprint',encode(extensions.digest(coalesce(p.proconfig::text,''),'sha256'),'hex'),"],
];
for (const [before, after] of corrections) {
  assert.equal(sql.split(before).length - 1, 1, 'Exact successor predicate required');
  sql = sql.replace(before, after);
}
assert.equal(sql.includes("'config',p.proconfig,"), false);
const sqlPath = 'docs/verification/wave5/installed-catalog-verification-20261012-r5-a2.sql';
const queries = plan.queries.map(item => item.id === 'catalog' ? { ...item, path: sqlPath, sha256: hash(sql), bytes: Buffer.byteLength(sql) } : item);
const successor = {
  kind: 'offline_prepared_installed_verification_successor', preparedAt: new Date().toISOString(), projectId: plan.projectId,
  originalPlan: { path: originalPlan, sha256: hash(read(originalPlan)), bytes: read(originalPlan).length, preserved: true },
  review: plan.review,
  originalPreparationTool: plan.preparationTool,
  successorPreparationTool: { path: 'tools/wave5/prepare_installed_verification_successor_20261012_r5_a2.mjs', sha256: hash(read('tools/wave5/prepare_installed_verification_successor_20261012_r5_a2.mjs')) },
  originalCatalog: plan.queries.find(item => item.id === 'catalog'),
  corrections: [
    'Explicit provolatile::text comparison to the expected VALUES text column.',
    'Hash-only configuration fingerprint replaces raw proconfig values; no configuration/private body is returned.',
  ],
  unchanged: ['541 final source function-body expectations', '215 directly created tables', '72 explicit/reviewed force-RLS predicates', '18 exact grant predicates', '33 rename/schema moves with three genuine baseline preservation prerequisites', 'all historical query bytes and actual failed local-check records', 'all frozen review/status/matrix/app and primary harness source'],
  queries,
  serialExecution: plan.serialExecution,
  rollbackBehaviorBatches: plan.rollbackBehaviorBatches,
  transactionSemantics: plan.transactionSemantics,
  prerequisites: 'Use the original bound source inventory and preservation prerequisites. Root records actual before/after live context, ledger and account creation separately. No source mapping is an installed proof.',
  execution: plan.execution,
  gates: plan.gates,
};
const jsonPath = 'docs/verification/wave5/installed-verification-plan-20261012-r5-a2.json';
const mdPath = 'docs/verification/wave5/installed-verification-plan-20261012-r5-a2.md';
const md = `# Installed verification preparation successor a2

Use the a2 catalog query below, together with the unchanged baseline-rename, strict metadata and preservation queries. The original [plan](installed-verification-plan-20261012-r5.md), source inventory and SQL stay preserved. This successor makes the volatility comparison explicitly text and returns a configuration hash instead of raw configuration values. It performs no SQL and adds no live scope.

| Stage | Query | SHA-256 |
|---|---|---|
${queries.map(item => '| ' + item.order + ' | [' + item.path.split('/').at(-1) + '](' + item.path.split('/').at(-1) + ') | `' + item.sha256 + '` |').join('\n')}

Record genuine hashes of the three installed baseline bodies before order58 and compare their renamed aliases afterward. Then run the catalog, strict metadata and preservation queries serially, each as its complete read-only transaction ending in ROLLBACK. Actual connector error/result and immediate after-state fingerprints are required. Source/body/table expectations are preparation until actual installed observations match; dynamic RLS coverage and business behavior remain separate checks.

Do not replay the historical 105/25 bundles, fabricate Auth/MFA or add a permission shim. Genuine account-bound rollback behavior remains incomplete until six actual private Auth Admin IDs and real MFA exist. Vault/cron/network setup and actual delivery/model use do not belong in rollback-only tests.

This preparation leaves owner acceptance3/109 and all runtime gates incomplete. Approval of the exact71-migration runtime setup is recorded separately by root; this document grants no additional approval.
`;
const outputs = [[sqlPath, sql], [jsonPath, JSON.stringify(successor, null, 2) + '\n'], [mdPath, md]];
for (const [relative] of outputs) assert.equal(fs.existsSync(path.join(root, relative)), false, 'Successor output already exists');
for (const [relative, content] of outputs) fs.writeFileSync(path.join(root, relative), content, { flag: 'wx' });
console.log(JSON.stringify({ prepared: true, databaseCalls: 0, corrections: successor.corrections, artifacts: outputs.map(([relative, content]) => ({ path: relative, sha256: hash(content), bytes: Buffer.byteLength(content) })) }, null, 2));
