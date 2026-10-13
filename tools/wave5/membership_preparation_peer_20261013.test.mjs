import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { PROJECT_ID, PROJECT_URL, hashJson, RACE_KINDS, freshId } from './runtime_contract.mjs';
import { createMembershipFixture, MEMBERSHIP_FIXTURE_SQL } from './supabase_membership_fixture.mjs';
import { createPreparationJournal } from './preparation_journal.mjs';
import { CASE_READ_RECIPES } from './supabase_runtime_provider.mjs';
import { READ_QUERY_SHA256, committedRecipeHash } from './supabase_read_store.mjs';

// Independent controlled local fixture. These objects are not Auth rows,
// credentials or live attestations. No SQL driver/network/server is invoked.
const review = JSON.parse(await fs.readFile(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json', import.meta.url)));
const approval = JSON.parse(await fs.readFile(new URL('../../docs/verification/wave5/runtime-owner-decision-20261012-r5.json', import.meta.url)));
const authIds = Object.fromEntries(review.accounts.map(actor => [actor.label, freshId()]));
function controlledContext() {
  const providerSha = hashJson('independent-local-private-factory-placeholder');
  const plan = { kind: 'wave5-runtime-harness-plan', projectId: PROJECT_ID, url: PROJECT_URL,
    production: false, realBilling: false, runtimeBundleSha256: review.bundleSha256,
    warmupMs: 60000, measuredMs: 300000, maxRunMs: 900000, maximumTimedRequests: 20000,
    maxInflight: 2000, requestsPerSecond: 20, providerCalendarSha256: hashJson('local-calendar'),
    postgresDriverSourceSha256: hashJson('local-driver'), preparationJournalSourceSha256: hashJson('local-sink'),
    cases: RACE_KINDS.map(kind => ({ kind, caseId: freshId(), scopeKey: ['seats', 'admissions', 'quota'].includes(kind) ? 'load-001' : 'runtime',
      participants: kind === 'duplicates' ? 100 : kind === 'quota' ? 20 : 2, noExternalSend: true,
      fixturePlanSha256: hashJson([kind, 'fixture']), committedQuerySha256: committedRecipeHash(CASE_READ_RECIPES[kind]),
      preparationSha256: hashJson([kind, 'preparation']), restorationSha256: hashJson([kind, 'restoration']) })),
    boundaries: ['10001Rows', '101Groups', '367DayWindow', '8MiBPlus1Byte'].map(kind => ({ kind, scopeKey: 'runtime', caseId: freshId(),
      fixturePlanSha256: hashJson([kind, 'fixture']), committedQuerySha256: READ_QUERY_SHA256.scopeSnapshot, expectedCode: 'LIMIT_EXCEEDED' })),
    loadCommittedQuerySha256: READ_QUERY_SHA256.loadLedgers, loadFixturePlanSha256: hashJson('local-load'),
    externalObservationSourceSha256: hashJson('local-observer') };
  const binding = { runtimeFileSha256: approval.runtimeFileSha256, harnessReviewSha256: hashJson('local-review'),
    planSha256: hashJson(plan), planBodySha256: hashJson(plan), privateProviderSha256: providerSha };
  const independentReview = { kind: 'wave5-runtime-harness-independent-preparation-review', result: 'approved-for-existing-bounded-scope',
    projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256,
    harnessReviewSha256: binding.harnessReviewSha256, planSha256: binding.planSha256, privateProviderSha256: providerSha,
    sourceBindingsVerified: true, operationScopeSha256: review.sourceContinuation.unchangedRuntimeOperationScopeSha256,
    sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
  binding.independentReviewBodySha256 = hashJson(independentReview);
  const preparation = { kind: 'wave5-runtime-harness-preparation', sourceBindingsVerified: true,
    runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: binding.runtimeFileSha256,
    harnessReviewSha256: binding.harnessReviewSha256, planSha256: binding.planSha256, privateProviderSha256: providerSha,
    independentReview: { result: independentReview.result, path: 'independent-controlled-placeholder.json', sha256: hashJson(independentReview) },
    sameApprovedOperationScope: true, additionalOwnerAuthorizationRequired: false, production: false, realBilling: false, installOriginalSix: false };
  return { review, approval, plan, binding, independentReview, preparation };
}

test('independent membership fixture never begins COMMIT after cancellation while its intent receipt waits', async () => {
  const input = controlledContext(), target = review.syntheticScopes.find(value => value.key === 'load-001'), roleId = freshId();
  const originalSubscription = { id: freshId(), seats: 4, version: '1' }, originalMembers = ['approver', 'executor']
    .map(label => ({ id: freshId(), user_id: authIds[label], status: 'active', version: '1' }));
  let subscription = structuredClone(originalSubscription), members = structuredClone(originalMembers), commits = 0, rollbacks = 0;
  const assignments = members.map(member => ({ id: freshId(), membership_id: member.id, role_id: roleId,
    legal_entity_id: target.entityId, branch_id: target.branchId }));
  class ControlledClient {
    async connect() {} async end() {}
    async query(sql, values) {
      if (sql === 'COMMIT') { commits++; return { rows: [] }; }
      if (sql === 'ROLLBACK') { rollbacks++; subscription = structuredClone(originalSubscription); members = structuredClone(originalMembers); return { rows: [] }; }
      if (sql === MEMBERSHIP_FIXTURE_SQL.subscription) return { rows: [structuredClone(subscription)] };
      if (sql === MEMBERSHIP_FIXTURE_SQL.memberships) return { rows: structuredClone(members) };
      if (sql === MEMBERSHIP_FIXTURE_SQL.assignments) return { rows: structuredClone(assignments) };
      if (sql === MEMBERSHIP_FIXTURE_SQL.occupied) return { rows: [{ occupied: String(2 + members.filter(member => member.status === 'active').length) }] };
      if (sql === MEMBERSHIP_FIXTURE_SQL.suspend) { const member = members.find(value => value.id === values[1]);
        member.status = 'suspended'; member.version = String(Number(member.version) + 1); return { rowCount: 1, rows: [{ id: member.id }] }; }
      if (sql === MEMBERSHIP_FIXTURE_SQL.seats) { subscription.seats = values[1]; subscription.version = String(Number(subscription.version) + 1);
        return { rowCount: 1, rows: [structuredClone(subscription)] }; }
      return { rows: [] };
    }
  }
  let acknowledgeCommit, observedCommitIntent;
  const commitIntentReached = new Promise(resolve => { observedCommitIntent = resolve; });
  const receipt = record => ({ durable: true, appendOnly: true, recordSha256: hashJson(record), storageEvidenceSha256: hashJson(['controlled-stored', record]) });
  const journal = createPreparationJournal({ projectId: PROJECT_ID, runtimeBundleSha256: review.bundleSha256,
    planBodySha256: input.binding.planBodySha256, sourceSha256: input.plan.preparationJournalSourceSha256,
    cases: [...input.plan.cases, ...input.plan.boundaries], appendPreparationEvidence: async record => {
      if (record.action === 'membership-commit' && record.phase === 'intent') {
        observedCommitIntent(); return new Promise(resolve => { acknowledgeCommit = () => resolve(receipt(record)); });
      }
      return receipt(record);
    } });
  const fixture = createMembershipFixture({ executionContext: input, authIds, PgClient: ControlledClient,
    databaseConfig: { host: `db.${PROJECT_ID}.supabase.co`, database: 'postgres', user: 'postgres',
      password: 'LOCAL_CONTROLLED_VALUE', ssl: { rejectUnauthorized: true } }, preparationJournal: journal });
  const signal = new AbortController(), pending = fixture.prepare({ signal: signal.signal });
  await commitIntentReached; signal.abort(); acknowledgeCommit();
  await assert.rejects(pending);
  assert.equal(commits, 0, 'No COMMIT may begin after the owner-bounded operation is cancelled.');
  assert.equal(rollbacks, 1);
  assert.deepEqual(subscription, originalSubscription);
  assert.deepEqual(members, originalMembers);
});
