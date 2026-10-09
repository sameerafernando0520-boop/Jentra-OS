import { deliverForecast, forecastEvent, attemptOutcome, validateIntegrationIdentity, validateIntegrationCredential } from './integration_policy.mjs';
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
function requireValue(condition,code='WORKER_CONTRACT_MISMATCH') {if(!condition) throw Error(code);}
async function ready(control,code) {
 const state=await control.readiness();
 requireValue(state?.contractRevision===1 && state.ready===true && state.providers?.[code]===1,'PROVIDER_UNAVAILABLE');
}

/**
 * Ports are trusted server adapters, never desktop claims. claimCommittedDelivery
 * must atomically persist a lease/attempt before returning a committed outbox job.
 * Lease expiry requires outcome review; it must not blindly resend an unknown
 * attempt. No adapter or scheduler is configured by this source module.
 */
export async function runDelivery({control,secrets,resolve,post,now,signal}) {
 signal?.throwIfAborted();
 requireValue(Number.isSafeInteger(now) && now>0);
 await ready(control,'committed_webhook.v1');
 const job=await control.claimCommittedDelivery(now);
 if(job===null) return {state:'idle'};
 requireValue(job && uuid.test(job.invocationId) && uuid.test(job.usageEventId) &&
  typeof job.periodStart==='string' && typeof job.periodEnd==='string');
 forecastEvent(job.event,job.subscription.scope);
 attemptOutcome(job.event.eventId,job.subscription.id,job.attempt,null);
 await control.authorizeDelivery(job);
 signal?.throwIfAborted();
 // Reservations are durable and bind the same invocation across worker restart.
 await control.reserveUsage({tenantId:job.event.tenantId,invocationId:job.invocationId,
  metric:'webhook.deliveries',periodStart:job.periodStart,periodEnd:job.periodEnd,quantity:'1'});
 signal?.throwIfAborted();
 const key=await secrets.deliveryKey(job.event.tenantId,job.subscription.keyVersion);
 const outcome=await deliverForecast({event:job.event,subscription:job.subscription,attempt:job.attempt,timestamp:now,key,
  authorizeCommittedEvent:()=>control.authorizeDelivery(job),resolve,signal,...(post?{post}:{})});
 // Persist outcome before settlement. Reconciliation can settle a known ACK
 // after a crash without sending the request again. Unknown outcomes keep quota.
 await control.recordDeliveryOutcome(job,outcome);
 if(outcome.state==='acknowledged') await control.settleUsage({tenantId:job.event.tenantId,
  invocationId:job.invocationId,eventId:job.usageEventId,quantity:'1'});
 return outcome;
}

/** Exact requests dispatch only through a configured server command adapter. */
export async function runExternalForecast({control,token,request,now}) {
 await ready(control,'external_forecast.v1');
 const fields=['schemaVersion','scope','commandCode','commandId','idempotencyKey','clientTimestamp','horizonStart','horizonEnd'];
 requireValue(request && Object.keys(request).length===fields.length && fields.every(k=>Object.hasOwn(request,k)) &&
  request.schemaVersion===1 && request.commandCode==='analytics.freeze_pipeline.v1' &&
  uuid.test(request.commandId) && uuid.test(request.idempotencyKey),'VALIDATION_ERROR');
 const utc=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/;
 requireValue(typeof request.clientTimestamp==='string' && utc.test(request.clientTimestamp) && Number.isFinite(Date.parse(request.clientTimestamp)) &&
  new Date(request.clientTimestamp).toISOString().slice(0,19)===request.clientTimestamp.slice(0,19),'VALIDATION_ERROR');
 for(const k of ['horizonStart','horizonEnd']) {
  requireValue(typeof request[k]==='string' && /^\d{4}-\d{2}-\d{2}$/.test(request[k]) &&
   Number.isFinite(Date.parse(request[k])) && new Date(request[k]).toISOString().startsWith(request[k]),'VALIDATION_ERROR');
 }
 const days=(Date.parse(request.horizonEnd)-Date.parse(request.horizonStart))/86400000;
 requireValue(days>0 && days<=366,'VALIDATION_ERROR');
 const credential=await control.findCredential(token);
 // This read validates authority before throttle/quota reservation. The final
 // transactional adapter rechecks the same authority, reservation and payload.
 const entitlement=await control.entitlement(request.scope);
 validateIntegrationIdentity({token,credential,scope:request.scope,commandCode:request.commandCode,now,
  liveEntitlement:entitlement,schemaVersion:1});
 const reservation=await control.reserveExternalRequest(credential,request,now);
 validateIntegrationCredential({token,credential:await control.findCredential(token),scope:request.scope,
  commandCode:request.commandCode,now,liveEntitlement:await control.entitlement(request.scope),
  quotaReserved:reservation?.quotaReserved,throttleReserved:reservation?.throttleReserved,schemaVersion:1});
 return control.dispatchForecast(credential,request,reservation);
}

export async function activateScheduledTrial({control,tenantId,revisionId,signal}) {
 requireValue(uuid.test(tenantId) && uuid.test(revisionId),'VALIDATION_ERROR');
 signal?.throwIfAborted();
 await ready(control,'synthetic_subscription.v1');
 signal?.throwIfAborted();
 // Server-side apply RPC owns effective dates, current actor/MFA, version,
 // seat admission, receipt, audit and outbox. This worker cannot bypass them.
 return control.applySyntheticSubscription(tenantId,revisionId);
}
