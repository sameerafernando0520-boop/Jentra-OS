import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { runPacedWorkload, checkLoadResult } from '../../../../../tools/wave5/runtime_coordinator.mjs';
import { hashJson } from '../../../../../tools/wave5/runtime_contract.mjs';

const H = 'a'.repeat(64), id = () => crypto.randomUUID();
const plan = { requestsPerSecond: 20, maximumTimedRequests: 7200 };
let cached;
async function fixture() {
  if (!cached) {
    let t = 0;
    const clock = { wall: () => Date.parse('2026-10-17T00:00:00Z') + t, monotonic: () => t,
      sleep: async ms => { for (let i = 0; i < 16; i++) await Promise.resolve(); t += ms; await Promise.resolve(); } };
    const sessions = Array.from({ length: 2000 }, (_, i) => ({ kind: 'auth', actorLabel: i % 4 === 3 ? 'billing-admin' : 'proposer',
      actorId: id(), sessionId: id(), connectionId: `controlled-${i}`, independentConnectionVerified: true,
      onlineAuthVerified: true, connectionEvidenceSha256: H, verificationEvidenceSha256: H, scopeKey: `controlled-${Math.floor(i / 4)}` }));
    cached = await runPacedWorkload({ sessions, clock, journal: async () => {}, durationMs: 360000, warmupMs: 60000,
      requestsPerSecond: 20, maxRequests: 7200, maxInflight: 2000,
      call: async (_p, request, context) => { context.onTransportStart(); context.onTransportEnd();
        return { outcome: 'applied', originalCommandId: request.commandId, responseSha256: H, transportEvidenceSha256: H }; } });
    assert.equal(checkLoadResult(cached, plan), true);
  }
  return structuredClone(cached);
}
function rebound(result) { result.requestTraceSha256 = hashJson(result.samples); return result; }

test('a complete controlled dispatch trace passes without opening network or database connections', async () => {
  assert.equal(checkLoadResult(await fixture(), plan), true);
});
test('reported 2,000-session coverage cannot hide one actual measured session', async () => {
  const result = await fixture();
  for (const s of result.samples.filter(s => s.phase === 'measurement')) s.participant = result.samples[0].participant;
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('reported 500-scope coverage cannot hide one actual measured scope', async () => {
  const result = await fixture(); for (const s of result.samples) s.scopeKey = 'controlled-0';
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('reported good p95 cannot hide a slow read population', async () => {
  const result = await fixture();
  for (const s of result.samples.filter(s => s.class === 'indexedReads')) {
    s.elapsedMs = 501; s.finishedMonoMs = s.startedMonoMs + 501;
    s.transportFinishedMonoMs = s.finishedMonoMs;
  }
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('trace digest must match the actual sample population', async () => {
  const result = await fixture(); result.requestTraceSha256 = 'b'.repeat(64);
  assert.throws(() => checkLoadResult(result, plan));
});
test('duplicated attempt identity cannot be counted as two sends', async () => {
  const result = await fixture(); result.samples[1].attemptId = result.samples[0].attemptId;
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('phase labels must follow the recorded transport boundary', async () => {
  const result = await fixture();
  const warm = result.samples.find(s => s.phase === 'warmup'), measured = result.samples.find(s => s.phase === 'measurement');
  [warm.phase, measured.phase] = [measured.phase, warm.phase];
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('negative elapsed time cannot be hidden by a positive summary', async () => {
  const result = await fixture(); result.samples[0].elapsedMs = -1;
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('a duplicated scheduled slot cannot substitute for a missing one', async () => {
  const result = await fixture(); result.samples[1].scheduledDueMonoMs = result.samples[0].scheduledDueMonoMs;
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('misclassified actual operations cannot be hidden by correct mix totals', async () => {
  const result = await fixture(); result.samples.find(s => s.class === 'indexedReads').operation = 'analytics';
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('distinct session IDs cannot reuse one claimed independent connection', async () => {
  const result = await fixture(); for (const s of result.samples) s.participant.connectionId = 'one-shared-connection';
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
test('a maximum dispatch lag summary must match actual dispatch intervals', async () => {
  const result = await fixture(); result.maximumDispatchLagMs = 1;
  assert.throws(() => checkLoadResult(result, plan));
});
test('a reported peak cannot understate actual overlapping transports', async () => {
  const result = await fixture(); const sorted = result.samples.toSorted((a, b) => a.transportStartedMonoMs - b.transportStartedMonoMs);
  for (const s of sorted.slice(0, 3)) {
    s.transportFinishedMonoMs = s.transportStartedMonoMs + 200; s.finishedMonoMs = s.transportFinishedMonoMs; s.elapsedMs = 200;
  }
  result.peakInflightRequests = 1;
  assert.throws(() => checkLoadResult(rebound(result), plan));
});
