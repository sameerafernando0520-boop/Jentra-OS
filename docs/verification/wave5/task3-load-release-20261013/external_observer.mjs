import { PROJECT_ID, hashJson, isSha, isUuid } from '../../../../tools/wave5/runtime_contract.mjs';
import { PrivatePgError } from './postgres_transport.mjs';

const must = (ok, code) => { if (!ok) throw new PrivatePgError(code); };
const instant = value => typeof value === 'string' ? Date.parse(value) : NaN;

// This adapter requires a trusted source-bound egress capture. SQL outcome counts,
// missing logs and an empty receiver inbox cannot populate its trace input.
export function createCompleteExternalObserver({ runtimeId, runtimeBundleSha256, scopeDigestSha256,
  observerSourceSha256, reviewedWorkerSources, traceReader, verifyTrustedCapture, jobsReader,
  reviewedJobIds = [4, 5, 6] }) {
  must(isUuid(runtimeId) && [runtimeBundleSha256, scopeDigestSha256, observerSourceSha256].every(isSha),
    'EXACT_EXTERNAL_OBSERVER_BINDING_REQUIRED');
  must(reviewedWorkerSources && Object.keys(reviewedWorkerSources).length > 0
    && Object.entries(reviewedWorkerSources).every(([worker, hash]) => /^[a-z0-9-]{1,80}$/.test(worker) && isSha(hash)),
    'EXACT_EXTERNAL_WORKER_SOURCES_REQUIRED');
  must([traceReader, verifyTrustedCapture, jobsReader].every(fn => typeof fn === 'function')
    && reviewedJobIds.length === 3 && new Set(reviewedJobIds).size === 3
    && reviewedJobIds.every(Number.isSafeInteger), 'PRIVATE_COMPLETE_CAPTURE_CALLBACKS_REQUIRED');
  const sources = Object.freeze({ ...reviewedWorkerSources });
  const wantedCoverage = Object.keys(sources).flatMap(worker => [`${worker}/model`, `${worker}/webhook`]).sort();
  return async function observe({ review, plan, window, signal }) {
    must(review?.projectId === PROJECT_ID && review.bundleSha256 === runtimeBundleSha256
      && hashJson(review.syntheticScopes) === scopeDigestSha256
      && plan?.externalObservationSourceSha256 === observerSourceSha256, 'EXTERNAL_OBSERVER_CONTEXT_DRIFT');
    const from = instant(window?.startedAt), until = instant(window?.finishedAt);
    must(Number.isFinite(from) && Number.isFinite(until) && from <= until && !signal?.aborted,
      'EXTERNAL_OBSERVER_WINDOW_INVALID');
    const trace = await traceReader({ projectId: PROJECT_ID, runtimeId, window, signal });
    must(trace?.kind === 'trusted-complete-egress-capture' && trace.projectId === PROJECT_ID
      && trace.runtimeId === runtimeId && trace.observerSourceSha256 === observerSourceSha256
      && ['egress-gateway-capture', 'source-bound-worker-transport-capture'].includes(trace.captureMethod)
      && hashJson(trace.workerSourceBindings) === hashJson(sources)
      && instant(trace.observedFromAt) <= from && instant(trace.observedUntilAt) >= until
      && trace.droppedEvents === 0 && trace.captureStoppedUnexpectedly === false
      && isSha(trace.captureIdentitySha256) && Array.isArray(trace.records) && trace.records.length >= 2,
      'COMPLETE_EXTERNAL_TRANSPORT_CAPTURE_REQUIRED');
    must(Array.isArray(trace.coveredTransports) && new Set(trace.coveredTransports).size === wantedCoverage.length
      && hashJson([...trace.coveredTransports].sort()) === hashJson(wantedCoverage),
      'ALL_REVIEWED_EGRESS_TRANSPORTS_REQUIRED');
    must(trace.records[0]?.kind === 'capture-open' && trace.records.at(-1)?.kind === 'capture-close',
      'COMPLETE_CAPTURE_BOUNDARIES_REQUIRED');
    let previousAt = -Infinity;
    for (let index = 0; index < trace.records.length; index++) {
      const record = trace.records[index], at = instant(record?.observedAt);
      must(record?.sequence === index + 1 && Number.isFinite(at) && at >= previousAt
        && at >= instant(trace.observedFromAt) && at <= instant(trace.observedUntilAt)
        && ['capture-open', 'capture-close', 'heartbeat', 'transport-dispatch'].includes(record.kind)
        && isSha(record.evidenceSha256), 'EXTERNAL_CAPTURE_GAP_OR_MALFORMED_RECORD');
      if (record.kind === 'transport-dispatch') must(wantedCoverage.includes(`${record.worker}/${record.transport}`)
        && isUuid(record.attemptId), 'UNKNOWN_EXTERNAL_TRANSPORT_DISPATCH');
      previousAt = at;
    }
    must(instant(trace.records[0].observedAt) <= from && instant(trace.records.at(-1).observedAt) >= until,
      'COMPLETE_CAPTURE_BOUNDARIES_REQUIRED');
    const traceSha256 = hashJson(trace);
    const verified = await verifyTrustedCapture({ trace, traceSha256, expectedSources: sources, window, signal });
    must(verified?.kind === 'independently-verified-complete-egress-capture'
      && verified.captureAuthentic === true && verified.traceSha256 === traceSha256
      && verified.completeReviewedTransports === true && verified.continuousWindow === true
      && isSha(verified.verificationEvidenceSha256), 'TRUSTED_CAPTURE_AUTHENTICITY_REQUIRED');
    const jobs = await jobsReader({ projectId: PROJECT_ID, runtimeId, reviewedJobIds: [...reviewedJobIds], window, signal });
    must(jobs?.kind === 'actual-continuous-job-and-worker-quiescence' && jobs.projectId === PROJECT_ID
      && jobs.runtimeId === runtimeId && instant(jobs.observedFromAt) <= from && instant(jobs.observedUntilAt) >= until
      && jobs.inflightWorkerCount === 0 && jobs.continuousWindowVerified === true
      && isSha(jobs.queryEvidenceSha256) && isSha(jobs.observationEvidenceSha256)
      && Array.isArray(jobs.jobs) && jobs.jobs.length === reviewedJobIds.length
      && jobs.jobs.every(job => reviewedJobIds.includes(job.id) && job.active === false)
      && new Set(jobs.jobs.map(job => job.id)).size === reviewedJobIds.length,
      'ACTUAL_JOB_AND_WORKER_QUIESCENCE_REQUIRED');
    const inWindow = trace.records.filter(record => record.kind === 'transport-dispatch'
      && instant(record.observedAt) >= from && instant(record.observedAt) <= until);
    const modelDispatchesObserved = inWindow.filter(record => record.transport === 'model').length;
    const webhookDispatchesObserved = inWindow.filter(record => record.transport === 'webhook').length;
    must(modelDispatchesObserved === 0 && webhookDispatchesObserved === 0 && !signal?.aborted,
      'EXTERNAL_TRANSPORT_DISPATCH_OBSERVED');
    return Object.freeze({ kind: 'online-no-external-transport-observation', projectId: PROJECT_ID,
      runtimeBundleSha256, scopeDigestSha256, observerSourceSha256,
      observedFromAt: trace.observedFromAt, observedUntilAt: trace.observedUntilAt,
      transportTraceSha256: hashJson({ traceSha256, verification: verified.verificationEvidenceSha256 }),
      jobsStateEvidenceSha256: hashJson(jobs), allReviewedModelDeliveryWorkersCovered: true,
      reviewedJobsInactiveAndNoInflight: true, modelDispatchesObserved, webhookDispatchesObserved });
  };
}
