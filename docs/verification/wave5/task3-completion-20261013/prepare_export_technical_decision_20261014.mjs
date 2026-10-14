import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const evidence=[];
async function read(relative){const b=await fs.readFile(path.join(root,relative));evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return JSON.parse(b);}
const authority=await read('docs/verification/wave5/task3-completion-20261013/resumed-autonomy-delegation.json');
assert.equal(authority.technicalDecisionsDelegated,true);assert.equal(authority.evidenceRequirementsWaived,false);
const original=await read('docs/verification/wave5/runtime-owner-decision-20261012-r5.json');
assert.equal(original.decision,'approve');assert.equal(original.projectId,'xpdoufauvrbdmxgngetv');
assert.equal(original.runtimeBundleSha256,'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b');
const audit=await read('docs/verification/wave5/task3-export-continuation-20261014/budget-feasibility.json');
assert.equal(audit.originalAuthorization.approvedGovernedExportMaximum,8);
assert.equal(audit.originalAuthorization.explicit150AttemptNumberInRuntimePacket,false);
assert.equal(audit.originalAuthorization.concreteOriginalFinanceCap,150);
assert.equal(audit.consumedEvidence.a3CumulativeBound,128);
assert.equal(audit.consumedEvidence.trackedPipelineShapeQuery.cumulativeBound,129);
assert.equal(audit.consumedEvidence.sharedOwnerRefresh.cumulativeBoundAfterAttribution,130);
assert.equal(audit.ordinaryCallInventory.length,24);
assert.deepEqual(audit.ordinaryCallInventory.map(x=>x.ordinal),Array.from({length:24},(_,i)=>i+1));
assert.equal(audit.ordinaryCallInventory.reduce((n,x)=>n+x.attempts,0),24);
assert.ok(audit.ordinaryCallInventory.every(x=>x.automaticRetries===0));
assert.equal(audit.reservedResolution.maximumAttempts,1);assert.equal(audit.exactSource.exportIds.length,2);
assert.equal(audit.exactSource.originalFixtureDay,'2026-10-13');
const report={kind:'delegated-source-only-export-continuation-technical-decision',decidedAt:new Date().toISOString(),
 author:'/root, acting as the delegated technical owner',projectId:original.projectId,runtimeBundleSha256:original.runtimeBundleSha256,
 decision:'approve additive source implementation of the same two governed exports, subject to the independent and generated-plan gates below',
 sourceImplementationAuthorized:true,liveExecutionAuthorizedByThisDecision:false,personalHumanExactSourceSignatureClaimed:false,
 originalHumanApprovalAndConcrete150PlanPreserved:true,originalAttemptCountersReset:false,
 originalConcreteCumulativeCap:150,preservedPriorBeforeNewRefresh:130,
 requiredAdditionalReadOnlyOwnerRefreshAttempts:1,priorConservativeBoundAfterRequiredRefresh:131,
 ordinaryContinuationAttempts:24,ordinaryCumulativeLimit:155,reservedReadOnlyResolutionAttempts:1,
 maximumCumulativeAttemptLimit:156,explicitAdditionalCeiling:6,
 attemptedAndFailedRequestsChargedBeforeDispatch:true,transportRetries:0,unlistedCallsAllowed:0,
 maximumRunMs:900000,maximumSingleRequestMs:45000,ordinaryDispatchResolutionReserveMs:45000,
 originalRuntimeExpiryUnchanged:'2026-10-14T09:57:07.481942Z',runtimeExpiryExtensionAuthorized:false,
 originalFixtureUtcDay:'2026-10-13',requiredActualExportUtcDay:'2026-10-14',serverDayAndExpiryCheckedBeforeWrites:true,
 newSourcePaths:['tools/wave5/finance_exports_20261014_r5_a5.mjs','tools/wave5/prepare_finance_exports_20261014_r5_a5.mjs',
  'docs/verification/wave5/task3-export-continuation-20261014/finance_exports_20261014_r5_a5.test.mjs'],
 topology:'Additive relative imports beside unchanged A3 sources; live owner alone copies new files into the approved frozen execution snapshot.',
 exactSource:audit.exactSource,requiredBefore:audit.requiredBefore,requiredAfter:audit.requiredAfter,
 ordinaryCallInventory:audit.ordinaryCallInventory,reservedResolution:audit.reservedResolution,
 permittedExportRpcNames:['report_export_preview','record_report_export','wave5_export_reopen','financial_statement_page'],
 onlyPermittedBusinessCommands:audit.exactSource.exportIds,
 genuineSessionChecksRetained:['same existing actor and TOTP factor','actual password session','actual MFA challenge and verification',
  'server TOTP clock','online user verification','actual UUID session row','distinct writer and reopen session IDs'],
 freshScopeRequirements:{expiredA8Rejected:true,newAdditiveMetadataAndRefreshFilenames:true,
  existingCredentialReuseAuthorityPreserved:true,onlyOneBoundedReadOnlyProjectCheck:true,
  readinessRefreshAttemptChargedEvenIfPersistenceFails:true,finalMetadataAndRefreshHashesBoundInGeneratedPlan:true,
  expiredOrMismatchedMetadataRejectedBeforePrivateUnsealOrRequest:true},
 executionPrerequisites:['independent budget/day/query review with exact public artifact hash',
  'controlled source tests and independent successor source review','one new charged readiness refresh with public proof',
  'generated snapshot plan with exact metadata/source/consumed-intent/evidence hashes',
  'primary review of the generated plan and exact private adapter delta','exclusive new export-only once intent'],
 previouslyCompletedDateCommandsReexecuted:false,oldUncertainCommandReplayed:false,
 sourceOrAmountsOrCurrenciesOrExistingIdsChanged:false,dateScenarioModelDeliveryOrSchemaWritesAuthorized:false,
 privateOrLiveOperationsOwnedBy:'Continue Jentra OS Wave 5, thread 01a121e1-81f0-76c1-8060-699f36ec225e',
 registeredStatementReopenClaimed:false,statementFreshPageAndPreviewCsvReproductionRequired:true,
 nativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,networkCallsByDecisionRecorder:0,evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'export-continuation-technical-decision-20261014-a1.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({sourceOnlyApproved:true,path:path.relative(root,output).replaceAll('\\','/'),bytes:b.length,sha256:sha(b)})+'\n');
