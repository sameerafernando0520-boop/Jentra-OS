import {createHash} from 'node:crypto';
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const hash=/^[0-9a-f]{64}$/;
const exact=/^(0|[1-9][0-9]{0,19})(\.[0-9]{1,6})?$/;
function requireValue(v,code='MODEL_CONTRACT_MISMATCH'){if(!v)throw Error(code);}

/** Reviewed model policy 1 accepts the exact redacted publication projection.
 * Free text is rejected rather than sanitized into executable instructions. */
export function redactForecastEvidence(input) {
 const fields=['contractRevision','modelProvider','sourceId','sourceHash','scope','currencies','horizonStart','horizonEnd'];
 requireValue(input && Object.keys(input).length===fields.length && fields.every(k=>Object.hasOwn(input,k)) &&
  input.contractRevision===1 && uuid.test(input.sourceId) && hash.test(input.sourceHash));
 const scope=input.scope;
 requireValue(scope && Object.keys(scope).length===3 && uuid.test(scope.tenantId) && uuid.test(scope.legalEntityId) &&
  (scope.branchId===null||uuid.test(scope.branchId)));
 requireValue(Array.isArray(input.currencies) && input.currencies.length<=100);
 const currencies=[],seen=new Set();
 for(const row of input.currencies){
  requireValue(row && Object.keys(row).length===4 && /^[A-Z]{3}$/.test(row.currency) && !seen.has(row.currency) &&
   Number.isSafeInteger(row.population) && row.population>=0 && row.population<=10000 &&
   typeof row.amount==='string' && exact.test(row.amount) && typeof row.weightedAmount==='string' && exact.test(row.weightedAmount));
  seen.add(row.currency);currencies.push({currency:row.currency,population:row.population,amount:row.amount,weightedAmount:row.weightedAmount});
 }
 for(const value of [input.horizonStart,input.horizonEnd]) requireValue(typeof value==='string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(Date.parse(value)) && new Date(value).toISOString().startsWith(value));
 const days=(Date.parse(input.horizonEnd)-Date.parse(input.horizonStart))/86400000;requireValue(days>0&&days<=366);
 return Object.freeze({policyVersion:1,projection:'pipeline.current_weighted.v1',sourceId:input.sourceId,sourceHash:input.sourceHash,
  scope:Object.freeze({...scope}),currencies:Object.freeze(currencies.map(Object.freeze)),horizonStart:input.horizonStart,horizonEnd:input.horizonEnd});
}

/** Provider suggestions remain data. Only an explicit human submission through
 * the installed proposal command can enter the distinct-MFA approval lifecycle. */
export function validateModelSuggestion(output,evidence) {
 requireValue(output && Object.keys(output).length===5 && output.commandCode==='analytics.freeze_pipeline.v1' &&
  output.sourceId===evidence.sourceId && output.sourceHash===evidence.sourceHash &&
  output.horizonStart===evidence.horizonStart && output.horizonEnd===evidence.horizonEnd);
 return Object.freeze({...output});
}

export async function invokeReviewedModel({reader,control,provider,request,policy}) {
 requireValue(policy?.revision===1 && policy?.approved===true && provider?.policyRevision===1,'MODEL_PROVIDER_UNAVAILABLE');
 requireValue(request && uuid.test(request.invocationId) && uuid.test(request.usageEventId) &&
  typeof request.maxTokens==='string' && /^[1-9][0-9]{0,6}$/.test(request.maxTokens),'VALIDATION_ERROR');
 const evidence=redactForecastEvidence(await reader.forecast(request));
 const manifest=JSON.stringify(evidence),digest=createHash('sha256').update(manifest,'utf8').digest('hex');
 const invocation=await control.beginModelInvocation({...request,tenantId:evidence.scope.tenantId,sourceId:evidence.sourceId,sourceHash:evidence.sourceHash,
  manifestHash:digest,policyRevision:1});
 // Persisted settled output can reopen; pending/unknown never issues a new send.
 if(invocation.state==='settled') {
  await reader.authorize(request,evidence);
  await control.settleUsage({tenantId:evidence.scope.tenantId,invocationId:request.invocationId,eventId:request.usageEventId,quantity:invocation.tokens});
  return validateModelSuggestion(invocation.suggestion,evidence);
 }
 requireValue(invocation.state==='new','MODEL_OUTCOME_REQUIRES_REVIEW');
 await control.reserveUsage({tenantId:evidence.scope.tenantId,invocationId:request.invocationId,metric:'ai.tokens',
  periodStart:request.periodStart,periodEnd:request.periodEnd,quantity:request.maxTokens});
 await reader.authorize(request,evidence);
 let response;
 try{response=await provider.generate({evidence,maxTokens:request.maxTokens,invocationId:request.invocationId});}
 catch{
  await control.recordModelOutcome(request.invocationId,{state:'unknown'});
  throw Error('MODEL_OUTCOME_UNKNOWN');
 }
 // Token counts come only from a reviewed provider adapter; a desktop report
 // or generated JSON usage field cannot settle the trusted reservation.
 let suggestion;
 try {
  requireValue(provider.trustedUsage===true && typeof response.tokens==='string' && /^(0|[1-9][0-9]{0,6})$/.test(response.tokens) &&
   BigInt(response.tokens)<=BigInt(request.maxTokens),'TRUSTED_USAGE_MISMATCH');
  suggestion=validateModelSuggestion(response.suggestion,evidence);
 } catch(error) {await control.recordModelOutcome(request.invocationId,{state:'unknown'});throw error;}
 await control.recordModelOutcome(request.invocationId,{state:'settled',tokens:response.tokens,suggestion});
 await control.settleUsage({tenantId:evidence.scope.tenantId,invocationId:request.invocationId,eventId:request.usageEventId,quantity:response.tokens});
 await reader.authorize(request,evidence);
 return suggestion;
}
