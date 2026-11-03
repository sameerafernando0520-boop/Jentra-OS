import {readFile,writeFile} from 'node:fs/promises';
const base='docs/verification/ai-integrations-test-20261103/';
const load=async n=>JSON.parse(await readFile(base+n,'utf8'));
const [response,ledger,before,trial,deployment]=await Promise.all([
 load('publishable-repair-model-response-verified.json'),load('publishable-repair-accounting.json'),
 load('publishable-repair-preflight-before-model.json'),load('publishable-repair-trial-activated.json'),load('publishable-repair-deployed.json')]);
const units=value=>{if(typeof value!=='string'||!/^(0|[1-9][0-9]*)(?:\.0+)?$/.test(value))throw Error('EXACT_INTEGER_TOKEN_UNITS_REQUIRED');return BigInt(value.split('.')[0]);};
const timeEqual=(a,b)=>Date.parse(a)===Date.parse(b);
const suggestionEqual=(a,b)=>['commandCode','sourceId','sourceHash','horizonStart','horizonEnd'].every(k=>a?.[k]===b?.[k])&&Object.keys(a??{}).length===5&&Object.keys(b??{}).length===5;
const q=ledger.quotaPeriods?.find(p=>p.metric==='ai.tokens'&&timeEqual(p.periodStart,response.request.periodStart));
const checks={
 approvedV12SourceVerified:deployment.sourceVerified&&deployment.runtimeAfter.version===12&&deployment.modules.length===17&&deployment.modules.every(m=>m.sha256Matched)&&deployment.receiverUnchanged,
 genuineAuthenticatedResponse:response.httpStatus===200&&response.caller.aal==='aal2'&&response.caller.realChallengeAndVerification&&response.caller.constructedClaims===false,
 priorFourRecordsAbsent:before.preservedInvocationAbsent&&before.preservedReservationAbsent&&before.preservedOutcomeAbsent&&before.preservedUsageAbsent&&before.modelInvocationCount===0,
 preservedInvocation:response.request.invocationId==='bf887435-88db-4a1f-9df9-2e9ec326f9b4'&&ledger.invocationId===response.request.invocationId,
 preservedUsageEvent:response.request.usageEventId==='287f1f6a-fe5d-4cfe-aec0-bbe710eb8e9d'&&ledger.usage?.eventId===response.request.usageEventId,
 sourceBasisMatched:ledger.invocation?.sourceId===response.request.sourceId&&ledger.invocation?.sourceHash===response.suggestion.sourceHash&&response.sourceHashBeforeAfterMatched,
 outcomeSettled:ledger.outcome?.state==='settled',
 storedSuggestionMatched:suggestionEqual(ledger.outcome?.suggestion,response.suggestion),
 trustedTokensWithinReservation:units(ledger.outcome.tokens)>0n&&units(ledger.outcome.tokens)<=units(response.request.maxTokens)&&units(ledger.reservation.reservedUnits)===units(response.request.maxTokens),
 usageExactlyMatchesTrustedOutcome:units(ledger.usage.quantity)===units(ledger.outcome.tokens),
 quotaExactlySettled:!!q&&units(q.settled)===units(ledger.outcome.tokens)&&units(q.reserved)===0n&&ledger.quotaPeriods.length===1,
 approvedPeriodMatched:timeEqual(ledger.invocation.periodStart,trial.after.trialStart)&&timeEqual(ledger.invocation.periodEnd,trial.after.trialEnd)&&timeEqual(q?.periodStart,trial.after.trialStart)&&timeEqual(q?.periodEnd,trial.after.trialEnd),
 onlyOnePersistedInvocation:ledger.modelInvocationCount===1,
 planAndSeatsPreserved:ledger.subscription.plan==='w5_runtime_20261008'&&ledger.subscription.seats===5&&ledger.subscription.version==='5',
 readPermissionsPreserved:JSON.stringify(ledger.readerPermissions)===JSON.stringify(['ai.proposals.view','analytics.view','crm.opportunities.view']),
 genuineSiblingDenial:response.siblingDenied===true,
 noAutomaticRetry:response.controlledReopenAttempts===1&&response.automaticRetries===0,
 originalDeliveryUnchanged:ledger.originalDeliveries.length===1&&ledger.originalDeliveries[0].id==='091e0c08-5038-4169-8e28-ffde9e0d51c8'&&ledger.originalDeliveries[0].state==='retry'&&ledger.originalDeliveries[0].attempt===1&&ledger.receiverReceipts===0&&response.deliveryResent===false
};
const passed=Object.values(checks).every(Boolean);
const report={kind:'actual-hosted-v12-model-and-usage-reconciliation',observedAt:new Date().toISOString(),ledgerObservedAt:ledger.observedAt,passed,checks,
 httpStatus:response.httpStatus,trustedProviderTokens:ledger.outcome.tokens,recordedUsageTokens:ledger.usage.quantity,outstandingQuotaReservation:q?.reserved??null,
 persistedUsageVerified:passed,hostedDatabaseQueried:true,syntheticRT1:true,uiModelSubmissionVerified:false,externalDeliveryAccepted:false,
 invocationId:response.request.invocationId,usageEventId:response.request.usageEventId,trialEndsAt:trial.after.trialEnd,runtimeScopeEndsAt:ledger.runtimeScope.expiresAt,
 responseArtifact:'publishable-repair-model-response-verified.json',accountingArtifact:'publishable-repair-accounting.json',automaticRetries:0};
await writeFile(base+'publishable-repair-usage-reconciled.json',JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(report));if(!passed)process.exitCode=1;
