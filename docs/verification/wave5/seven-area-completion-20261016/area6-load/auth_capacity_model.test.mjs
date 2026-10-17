import test from 'node:test';
import assert from 'node:assert/strict';
import { modelAuthCapacity } from './auth_capacity_model.mjs';
test('saved one-source settings cannot issue the complete fresh cohort', () => {
  const result = modelAuthCapacity(); assert.equal(result.minimumCohortIssuanceSeconds, '3940');
  assert.equal(result.maximumIssuanceSeconds, '2700'); assert.equal(result.maximumTokensPerSourceInWindow, '1380');
  assert.equal(result.minimumGenuineSourceGroups, '2'); assert.equal(result.arithmeticAllowsCohort, false);
});
test('two genuine sources give an optimistic necessary bound without claiming actual capacity', () => {
  const result = modelAuthCapacity({ sourceGroups: 2 }); assert.equal(result.minimumCohortIssuanceSeconds, '1940');
  assert.equal(result.arithmeticAllowsCohort, true); assert.equal(result.actualVerified, false); assert.equal(result.genuineSessionsCreated, 0);
});
test('reserving five minutes for final online verification still needs two sources', () => {
  const result = modelAuthCapacity({ sourceGroups: 2, verificationTailSeconds: 300 });
  assert.equal(result.maximumIssuanceSeconds, '2400'); assert.equal(result.maximumTokensPerSourceInWindow, '1230');
  assert.equal(result.minimumGenuineSourceGroups, '2'); assert.equal(result.arithmeticAllowsCohort, true);
});
test('uneven distribution rounds issuance upward with exact integer arithmetic', () => {
  assert.equal(modelAuthCapacity({ sessions: 2001, sourceGroups: 2 }).minimumCohortIssuanceSeconds, '1942');
});
test('invalid or exhausted freshness windows fail rather than imply capacity', () => {
  for (const change of [{ sourceGroups: 0 }, { quota: 0 }, { quota: 150.5 }, { verificationTailSeconds: 2700 }, { sessions: Infinity }])
    assert.throws(() => modelAuthCapacity(change), /INVALID_CAPACITY_MODEL/);
});
