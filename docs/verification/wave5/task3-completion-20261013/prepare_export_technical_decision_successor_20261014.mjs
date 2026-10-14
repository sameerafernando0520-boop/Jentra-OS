import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const evidence=[];
async function read(relative,expected){const b=await fs.readFile(path.join(root,relative));assert.equal(sha(b),expected);
 evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return JSON.parse(b);}
const original=await read('docs/verification/wave5/task3-completion-20261013/export-continuation-technical-decision-20261014-a1.json',
 '90b0d2c6767b983308bb4d8258583da26bd03b746941daac6fd1737d703bebee');
const independent=await read('docs/verification/wave5/task3-export-independent-20261014/export-budget-day-independent-review-a2.json',
 '7564bc4564fcbf1e68af2484373d3bd4571a2694c57f94d2633fbb88518a308b');
const metadata=await read('docs/verification/wave5/private-owner-input-ready-20261014-r5-a9.json',
 'd46ee968a50955e39154947f03833415bbe41e39b8771bb603bacd2ee52b615e');
const accounting=await read('docs/verification/wave5/finance-cumulative-read-accounting-20261014-r5-a5.json',
 'eee92e825eb457521a43054f19808e2ded729e0c9a80e53558e24ce4965753ee');
assert.equal(independent.passed,true);assert.equal(independent.checks.filter(x=>x.passed).length,13);
assert.equal(accounting.cumulativeChargedPriorCalls,131);
assert.ok(Date.now()>Date.parse(metadata.expiresAt),'A9 must actually be expired');
assert.equal(original.ordinaryContinuationAttempts,24);assert.equal(original.reservedReadOnlyResolutionAttempts,1);
const report={...original,kind:'delegated-source-only-export-continuation-technical-decision',decidedAt:new Date().toISOString(),
 successorOf:{path:evidence[0].path,sha256:evidence[0].sha256,maximumCumulativeAttemptLimit:156},
 successorReason:'A9 expired while work was interrupted. Preserve its actual charged request; require exactly one separately reviewed fresh readiness check after source review.',
 preservedPriorBeforeNewRefresh:131,requiredAdditionalReadOnlyOwnerRefreshAttempts:1,priorConservativeBoundAfterRequiredRefresh:132,
 ordinaryCumulativeLimit:156,maximumCumulativeAttemptLimit:157,explicitAdditionalCeiling:7,
 futureFreshScope:{metadataPath:'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json',
  refreshPath:'docs/verification/wave5/private-owner-scope-refresh-20261014-r5-a10.json',
  accountingPath:'docs/verification/wave5/finance-cumulative-read-accounting-20261014-r5-a6.json',
  proofExistsOrRequestAlreadyPerformedClaimed:false,exactHashesMustBeBoundInFinalGeneratedPlan:true,
  refreshOnlyAfterSourceAndIndependentReviewReady:true,numberOfReadinessRequestsAuthorizedForThisSuccessor:1,
  anyFailureOrAdditionalRefreshRequiresNewTransparentAccountingAndReview:true},
 expiredPredecessorMetadata:{path:evidence[2].path,sha256:evidence[2].sha256,expiresAt:metadata.expiresAt,eligibleForExecution:false},
 originalAttemptCountersReset:false,originalHumanApprovalAndConcrete150PlanPreserved:true,
 originalRuntimeExpiryUnchanged:'2026-10-14T09:57:07.481942Z',runtimeExpiryExtensionAuthorized:false,
 liveExecutionAuthorizedByThisDecision:false,sourceImplementationAuthorized:true,
 unchangedFromPriorDecision:['the same two original export commands','the exact two-currency pipeline and existing statement',
  '24 ordered ordinary requests and one conditional read-only resolution','UTC14 export day and UTC13 fixture day',
  'existing genuine MFA/user/session checks','45-second request and 900-second run deadlines','all earlier sources, attempts and consumed intents'],
 decision:'approve the additive source-only continuation with a transparent maximum cumulative157, conditional on exactly one newly charged readiness check and all existing final review gates',
 evidence:[...original.evidence,...evidence]};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'export-continuation-technical-decision-20261014-a2.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({sourceOnlyApproved:true,path:path.relative(root,output).replaceAll('\\','/'),bytes:b.length,sha256:sha(b)})+'\n');
