import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {MEMBERSHIP_FIXTURE_SQL} from '../../../../tools/wave5/supabase_membership_fixture.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const folder = 'docs/verification/wave5/task3-load-release-20261013';
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const bind = name => { const bytes = fs.readFileSync(path.resolve(root, name)); return {path: name.replaceAll('\\', '/'), bytes: bytes.length, sha256: sha(bytes)}; };
const require = createRequire(import.meta.url), pgPackagePath = require.resolve('pg/package.json');
const pgVersion = JSON.parse(fs.readFileSync(pgPackagePath, 'utf8')).version;
assert.equal(pgVersion, '8.23.1');
const sources = fs.readdirSync(path.resolve(root, folder)).filter(name => /^fixture_writer.*\.mjs$/.test(name))
  .map(name => `${folder}/${name}`).concat([
    `${folder}/postgres_transport.mjs`, `${folder}/provider_pg_factory.mjs`, `${folder}/package.json`, `${folder}/package-lock.json`,
    'tools/wave5/supabase_membership_fixture.mjs', 'tools/wave5/preparation_journal.mjs',
    'tools/wave5/runtime_contract.mjs', 'tools/wave5/runtime_fixture_spec.mjs',
    'tools/wave5/supabase_read_store.mjs', 'tools/wave5/supabase_runtime_provider.mjs',
    'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',
    'docs/verification/wave5/runtime-owner-decision-20261012-r5.json',
    path.relative(root, pgPackagePath).replaceAll('\\', '/'),
  ]).sort();
const before = sources.map(bind), startedAt = new Date().toISOString();
const executed = spawnSync(process.execPath, ['--test', '--test-reporter=tap', `${folder}/fixture_writer.test.mjs`],
  {cwd: root, encoding: 'utf8', timeout: 30000, maxBuffer: 2 * 1024 * 1024, windowsHide: true});
const finishedAt = new Date().toISOString();
const log = `${executed.stdout ?? ''}${executed.stderr ?? ''}`;
const logPath = `${folder}/fixture_writer-verification.tap`;
fs.writeFileSync(path.resolve(root, logPath), log);
const after = sources.map(bind), unchanged = JSON.stringify(before) === JSON.stringify(after);
const count = key => Number(new RegExp(`^# ${key} (\\d+)$`, 'm').exec(log)?.[1] ?? -1);
const counts = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(key => [key, count(key)]));
const identities = [...log.matchAll(/^# Subtest: (.+)$/gm)].map(match => match[1]);
const passed = executed.status === 0 && unchanged && counts.tests === 28 && counts.pass === 28
  && counts.fail === 0 && counts.cancelled === 0 && counts.skipped === 0 && counts.todo === 0 && identities.length === 28;
const result = {
  kind: 'bounded-membership-fixture-writer-controlled-verification', startedAt, finishedAt,
  passed, sourcesUnchangedDuringRun: unchanged, counts, actualControlledTestIdentities: identities,
  exitCode: executed.status, nodeVersion: process.version, pinnedPgVersion: pgVersion,
  sourceBindings: before, sourceBindingsAfter: after, log: bind(logPath),
  exactSourceSqlHashes: Object.fromEntries(Object.entries(MEMBERSHIP_FIXTURE_SQL).map(([name, sql]) => [name, sha(sql)])),
  interface: {
    factory: 'createBoundedMembershipFixturePgDriver({executionContext,authIds,credentialProvider,PoolClass?,maximumConnections?,acquireTimeoutMs?,statementTimeoutMs?})',
    operation: 'runWithSignal(signal,callback,{caseId,action}) where action is prepare or restore and case is reviewed seats/admissions',
    invitationObservation: 'observeInvitationJournalRecord(tokenFreeObservation,acknowledgment): acknowledged source-bound intent/confirmed pair; original raw digest verified only inside the private sink wrapper',
    close: 'Idempotent; close cancels pending client I/O, destroys open transactions and closes the pool without aborting the owner signal.',
  },
  implementedPolicy: {
    separateExplicitWriterRole: true, existingReadOnlyPolicyUnchanged: true, originalPublicFixtureUnchanged: true,
    exactLoad001TenantOnly: true, exactSixAuthIdsAndApproverExecutorRows: true,
    originalFourSeatsAndSameRowVersions: true, preparedCapThreeOnly: true,
    restorationCaps: 'seats: 3 to 4; admissions: 3 to 4, or observed cap 2 with both suspended and occupied=2 to 4',
    tlsChainAndHostnameRequired: true, credentialCallbackOnlyAtConnect: true,
    boundedPoolMaximum: 8, defaultPoolMaximum: 2, acquireTimeoutMaximumMs: 10000, statementTimeoutMaximumMs: 25000,
    abortDestroysPendingBeginOrOpenTransaction: true, unknownCommitStopsWithoutReplay: true,
    rawInvitationTokensExcludedFromWriter: true, invitationIdsRequireAcknowledgedIntentConfirmedPair: true,
    finalRestoreRequiresFreshReadback: true, errorsSanitized: true,
  },
  evidenceBoundary: '28 local controlled cases with a fake pg Pool, the unchanged real createMembershipFixture and preparation journal. Controlled identities/receipts are not real Auth, actual PostgreSQL, delivered network, load or acceptance results. Runtime private wiring and independent source review remain required before coordinated approved fixture execution.',
  liveQueriesOrWritesPerformed: 0, actualPostgresConnections: 0, networkCalls: 0,
  privateCredentialsRead: false, globalAuthChanged: false, SDKExecuted: false,
  personalHumanSignatureClaimed: false, acceptanceDecisionsAdded: 0, productionActionsPerformed: 0,
};
const resultPath = `${folder}/fixture_writer-verification.json`;
fs.writeFileSync(path.resolve(root, resultPath), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({passed, sourcesUnchangedDuringRun: unchanged, counts, sourceCount: before.length,
  result: bind(resultPath), log: bind(logPath)}, null, 2));
assert.equal(passed, true);
