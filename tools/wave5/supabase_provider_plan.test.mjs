import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { hashJson, RACE_KINDS } from './runtime_contract.mjs';
import { makeSupabaseProviderPlan } from './supabase_provider_plan.mjs';
import { CASE_READ_RECIPES } from './supabase_runtime_provider.mjs';
import { committedRecipeHash } from './supabase_read_store.mjs';

const review = JSON.parse(fs.readFileSync(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json', import.meta.url)));
const calendar = { horizonStart: '2026-10-01', horizonEnd: '2026-11-01', windowStart: '2026-10-01T00:00:00Z',
  windowEnd: '2026-10-08T00:00:00Z', asOf: '2026-10-08T00:00:00Z', recordedThrough: '2026-10-08T00:00:00Z', clientTimestamp: '2026-10-12T00:00:00Z' };
const sources = Object.fromEntries(['supabase_http_transport.mjs', 'supabase_read_store.mjs', 'supabase_membership_fixture.mjs', 'preparation_journal.mjs', 'preparation_file_sink.mjs',
  'supabase_runtime_provider.mjs', 'runtime_fixture_spec.mjs', 'supabase_provider_plan.mjs'].map(name => [name, hashJson(name)]));
const input = { review, calendar, sourceBindings: sources, privateFactorySha256: hashJson('controlled-factory-source'),
  postgresDriverSourceSha256: hashJson('controlled-driver-source'), externalObserverSourceSha256: hashJson('controlled-observer-source'),
  preparationJournalSourceSha256: sources['preparation_journal.mjs'] };
test('pure source-bound plan retains exact seven races/four truthful boundaries/full load bounds and freezes nested sources', () => {
  const plan = makeSupabaseProviderPlan(input);
  assert.deepEqual(plan.cases.map(c => c.kind), RACE_KINDS);
  assert.equal(plan.maximumTimedRequests, 100000); assert.equal(plan.maxInflight, 2000); assert.equal(plan.warmupMs, 60000); assert.equal(plan.measuredMs, 300000);
  assert.equal(new Set([...plan.cases, ...plan.boundaries].map(c => c.caseId)).size, 11);
  assert.equal(plan.providerCalendarSha256, hashJson(calendar)); assert.equal(plan.additionalOwnerDecisionRequired, false);
  assert.equal(plan.preparationJournalSourceSha256, input.preparationJournalSourceSha256);
  for (const race of plan.cases) assert.equal(race.committedQuerySha256, committedRecipeHash(CASE_READ_RECIPES[race.kind]));
  assert.equal(plan.boundaries.find(b => b.kind === '10001Rows').availability, 'unavailable-with-reviewed-caps');
  assert.ok(Object.isFrozen(plan.publicProviderSourceBindings)); assert.throws(() => { plan.publicProviderSourceBindings['supabase_read_store.mjs'] = 'changed'; });
});
test('pure plan rejects absent actual private source hashes, source omission and out-of-scope load rate without any provider import/run', () => {
  for (const extra of [{ privateFactorySha256: null }, { postgresDriverSourceSha256: 'missing' },
    { preparationJournalSourceSha256: hashJson('another-journal') },
    { sourceBindings: Object.fromEntries(Object.entries(sources).filter(([name]) => name !== 'preparation_file_sink.mjs')) },
    { sourceBindings: { 'supabase_http_transport.mjs': hashJson('source') } }, { requestsPerSecond: 300 }]) {
    assert.throws(() => makeSupabaseProviderPlan({ ...input, ...extra }));
  }
});
