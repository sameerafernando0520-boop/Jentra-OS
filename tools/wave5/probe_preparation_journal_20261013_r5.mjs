import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runRace } from './runtime_coordinator.mjs';
import { PROJECT_ID, GuardError, freshId, hashBytes, hashJson } from './runtime_contract.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const attempt = process.argv[2];
if (!/^a[1-9][0-9]*$/.test(attempt ?? '')) throw new Error('NEW_LOCAL_ATTEMPT_REQUIRED');
const destination = `docs/verification/wave5/preparation-journal-peer-probe-20261013-r5-${attempt}.json`;
const sourcePaths = ['tools/wave5/runtime_coordinator.mjs', 'tools/wave5/supabase_runtime_provider.mjs',
  'tools/wave5/supabase_membership_fixture.mjs', 'tools/wave5/probe_preparation_journal_20261013_r5.mjs'];
const bind = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, sha256: hashBytes(bytes), bytes: bytes.length }; };
const before = await Promise.all(sourcePaths.map(bind));
const review = JSON.parse(await fs.readFile(path.join(root, 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json')));
const target = review.syntheticScopes.find(scope => scope.key === 'load-001');
const race = { kind: 'seats', caseId: freshId(), scopeKey: target.key, participants: 2,
  noExternalSend: true, fixturePlanSha256: hashJson('controlled-fixture'), preparationSha256: hashJson('controlled-preparation'),
  restorationSha256: hashJson('controlled-restoration'), committedQuerySha256: hashJson('controlled-query') };
const entries = []; let simulatedMutations = 0, entriesBeforePreparation = null, failureCode = null;
const actualStartedAt = new Date().toISOString();
try {
  await runRace({ race, review, preflight: {}, sessions: [], provider: {
    async prepareRace() {
      entriesBeforePreparation = entries.length;
      // Local marker only: this imitates a committed prepare followed by an unknown
      // result. It is not an SQL, RPC, Auth or actual administrative mutation.
      simulatedMutations++;
      throw new GuardError('UNCERTAIN_MUTATION_REQUIRES_REVIEW');
    },
  }, journal: async entry => { entries.push(entry); } });
} catch (error) { failureCode = error instanceof GuardError ? error.code : 'PROVIDER_FAILURE'; }
const actualFinishedAt = new Date().toISOString(), after = await Promise.all(sourcePaths.map(bind));
const passed = entriesBeforePreparation > 0 && hashJson(before) === hashJson(after);
const report = { kind: 'controlled-wave5-preparation-journal-peer-probe', projectId: PROJECT_ID,
  actualStartedAt, actualFinishedAt, filesBefore: before, filesAfter: after,
  selectedSourcesUnchanged: hashJson(before) === hashJson(after),
  expectedCaseIntentBeforePreparation: true, entriesBeforePreparation, entriesAfterUnknownPreparation: entries.length,
  entryTypes: entries.map(entry => entry.type), simulatedMutations, failureCode, passed,
  observedOriginalCaseIdInJournal: entries.some(entry => JSON.stringify(entry).includes(race.caseId)),
  controlledOnly: true, executedLive: false, networkCalls: 0, databaseCalls: 0, authWrites: 0,
  realCredentialsRead: false, fabricatedJwtOrAuthRows: false, sdkJobs: 0, nativeActions: 0,
  limitation: 'Tests coordinator ordering with a local preparer marker that throws. No actual fixture or server operation occurs. Membership baseline and individual setup RPC evidence need separate regression tests in the provider implementation.' };
const bytes = JSON.stringify(report, null, 2) + '\n';
await fs.writeFile(path.join(root, destination), bytes, { flag: 'wx', mode: 0o600 });
process.stdout.write(JSON.stringify({ path: destination, sha256: hashBytes(bytes), passed, entriesBeforePreparation,
  entriesAfterUnknownPreparation: entries.length, failureCode }) + '\n');
if (!passed) process.exitCode = 1;
