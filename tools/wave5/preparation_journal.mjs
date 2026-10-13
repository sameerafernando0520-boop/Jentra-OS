import { PROJECT_ID, GuardError, requireGuard, isUuid, isSha, hashJson, immutableJson, freshId, safeFailure } from './runtime_contract.mjs';

// Records can contain private invitation recovery tokens. They are sent only to
// the source-reviewed private durable sink, never to the public CLI journal.
const bindings = new WeakMap(), PHASES = new Set(['checkpoint', 'intent', 'confirmed', 'uncertain']);
export function createPreparationJournal({ projectId, runtimeBundleSha256, planBodySha256, sourceSha256, cases, appendPreparationEvidence }) {
  requireGuard(projectId === PROJECT_ID && [runtimeBundleSha256, planBodySha256, sourceSha256].every(isSha)
    && typeof appendPreparationEvidence === 'function' && Array.isArray(cases) && cases.length > 0
    && cases.every(value => isUuid(value.caseId) && ['runtime', 'load-001'].includes(value.scopeKey))
    && new Set(cases.map(value => value.caseId)).size === cases.length, 'REVIEWED_PREPARATION_REQUIRED');
  const allowed = immutableJson(cases.map(({ caseId, scopeKey }) => ({ caseId, scopeKey }))),
    byId = new Map(allowed.map(value => [value.caseId, value.scopeKey]));
  let sequence = 0, blocked = null;
  const healthy = () => requireGuard(!blocked, blocked ?? 'EVIDENCE_WRITE_FAILED');
  function record(entry) {
    requireGuard(byId.get(entry.caseId) === entry.scopeKey && PHASES.has(entry.phase)
      && typeof entry.action === 'string' && /^[a-z][a-z0-9-]{0,95}$/.test(entry.action), 'REVIEWED_CASE_BINDING_REQUIRED');
    const value = immutableJson({ kind: 'wave5-private-preparation-journal-record', projectId, runtimeBundleSha256,
      planBodySha256, sourceSha256, sequence: ++sequence, recordId: freshId(), observedAt: new Date().toISOString(),
      caseId: entry.caseId, scopeKey: entry.scopeKey, action: entry.action, phase: entry.phase,
      ...(entry.operationId === undefined ? {} : { operationId: entry.operationId }), details: entry.details });
    requireGuard(Buffer.byteLength(JSON.stringify(value)) <= 8 * 1024 * 1024 + 1, 'LIMIT_EXCEEDED'); return value;
  }
  async function persist(entry, retainUnknown = false) {
    if (!retainUnknown) healthy();
    const value = record(entry);
    try {
      const receipt = await appendPreparationEvidence(value);
      requireGuard(receipt?.durable === true && receipt.appendOnly === true && receipt.recordSha256 === hashJson(value)
        && isSha(receipt.storageEvidenceSha256), 'EVIDENCE_WRITE_FAILED');
      return Object.freeze({ recordSha256: receipt.recordSha256, storageEvidenceSha256: receipt.storageEvidenceSha256 });
    } catch {
      blocked ??= 'EVIDENCE_WRITE_FAILED'; throw new GuardError('EVIDENCE_WRITE_FAILED');
    }
  }
  const journal = Object.freeze({ kind: 'wave5-private-preparation-journal', sourceSha256, planBodySha256,
    assertHealthy: healthy, append: entry => persist(entry),
    async perform({ caseId, scopeKey, action, intent, operation }) {
      healthy(); requireGuard(typeof operation === 'function', 'REVIEWED_PREPARATION_REQUIRED');
      const operationId = freshId(), original = { caseId, scopeKey, action, operationId };
      await persist({ ...original, phase: 'intent', details: intent });
      // Another concurrently waiting setup may have become uncertain while this
      // receipt was pending. Acknowledgement cannot override that stop condition.
      healthy();
      let result;
      try {
        result = await operation();
        await persist({ ...original, phase: 'confirmed', details: { result } });
        return result;
      } catch (error) {
        // A send/COMMIT or its acknowledgement may have occurred. Preserve the
        // original intent and any returned IDs; neither retry nor restore here.
        blocked = 'UNCERTAIN_MUTATION_REQUIRES_REVIEW';
        try { await persist({ ...original, phase: 'uncertain', details: { failureCode: safeFailure(error),
          ...(result === undefined ? {} : { result }) } }, true); } catch {}
        throw new GuardError('UNCERTAIN_MUTATION_REQUIRES_REVIEW');
      }
    } });
  bindings.set(journal, { projectId, runtimeBundleSha256, planBodySha256, sourceSha256, casesSha256: hashJson(allowed) });
  return journal;
}

export function requireBoundPreparationJournal(journal, context) {
  const actual = bindings.get(journal), expected = [...context.plan.cases, ...context.plan.boundaries]
    .map(({ caseId, scopeKey }) => ({ caseId, scopeKey }));
  requireGuard(actual && actual.projectId === context.review.projectId && actual.runtimeBundleSha256 === context.review.bundleSha256
    && actual.planBodySha256 === context.binding.planBodySha256 && actual.sourceSha256 === context.plan.preparationJournalSourceSha256
    && actual.casesSha256 === hashJson(expected), 'PREPARATION_BINDING_MISMATCH'); return journal;
}
