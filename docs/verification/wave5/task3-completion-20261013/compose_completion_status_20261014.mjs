import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const attempt=process.argv[2]??'a1';assert.match(attempt,/^a[1-9][0-9]*$/);
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const evidence=[];
async function load(relative){const bytes=await fs.readFile(path.join(root,relative));
 const binding={path:relative,bytes:bytes.length,sha256:sha(bytes)};evidence.push(binding);return JSON.parse(bytes);}
const acceptance=await load('docs/verification/wave5/task3-acceptance-20261013/delegated-technical-acceptance-matrix.json');
assert.equal(acceptance.requirementCount,109);assert.equal(acceptance.rows.length,109);
assert.equal(acceptance.rows.filter(row=>row.accepted).length,23);
assert.equal(acceptance.originalHumanAcceptedCount,3);assert.equal(acceptance.delegatedTechnicalAcceptedCount,20);
const prerequisites=await load('docs/verification/wave5/task3-acceptance-20261013/open-requirement-prerequisites.json');
assert.equal(prerequisites.groupedRowCount,86);
const desktop=await load('docs/verification/wave5/task3-completion-20261013/desktop-partitioned-independent-verification-20261014.json');
const integration=await load('docs/verification/wave5/task3-completion-20261013/provider-integration-independent-review-20261014-a2.json');
const provider=await load('docs/verification/wave5/task3-acceptance-20261013/runtime-provider-local-verification-20261014-acceptance-a3.json');
const offline=await load('docs/verification/wave5/task3-acceptance-20261013/runtime-harness-offline-validation-20261014-acceptance-a1.json');
assert.equal(desktop.testCasesPassed,2026);assert.equal(integration.counts.pass,61);
assert.equal(provider.summary.passed,122);assert.equal(offline.passed,true);
const installed=await load('docs/verification/wave5/task3-completion-20261013/installed-cash-independent-verification-20261014.json');
const localPackage=await load('docs/verification/wave5/task3-completion-20261013/load-package-independent-final-review-20261014.json');
const protocol=await load('docs/verification/wave5/task3-load-release-20261013/protocol-result-a2.json');
const release=await load('docs/verification/wave5/task3-load-release-20261013/source-release-checks.json');
const auth=await load('docs/verification/wave5/auth-token-quota-actual-private-readiness-20261014-r5.json');
assert.equal(installed.installedMigrations,115);assert.equal(installed.apiFunctions,363);
assert.equal(protocol.actualLoadPerformed,false);assert.equal(auth.jwtLifetimeSeconds,3600);
const native=await load('docs/verification/wave5/task3-completion-20261013/native-account-final-readonly-observation-20261014.json');
assert.equal(native.approvedReadOnlyProbe.accountExistenceConclusion,'absent');
const privateInputs=await load('docs/verification/wave5/task3-completion-20261013/private-readiness-current-metadata-20261014-a2.json');
const financeDirectory='build/wave5-approved-execution-20261013-r5-a2/docs/verification/wave5/genuine-finance-remaining-20261014-r5-a3-1791928284337';
const stop=await load(`${financeDirectory}/99-stop.json`);
assert.equal(stop.totalRequestBound,128);assert.equal(stop.completed.length,6);assert.equal(stop.lastOriginalCommand,null);
assert.equal(stop.staleOriginalCommandReplayed,false);
const dates=[];
for(const kind of ['payroll_correction','project_reimbursement']){
 const record=await load(`${financeDirectory}/date-${kind}.json`);
 assert.equal(record.readback.sourceKind,kind);assert.equal(record.readback.decision,'approved');
 assert.notEqual(record.readback.preparedBy,record.actualDistinctApprover);
 assert.equal(record.readback.currentApproval.version,'1');assert.equal(record.canonicalFullValueIdentical,true);
 assert.equal(record.rawResponseSha256Identical,true);
 assert.equal(record.originalPreparedResponseSha256,record.originalReplayResponseSha256);
 dates.push({sourceKind:kind,proposalId:record.readback.id,distinctApprover:record.actualDistinctApprover,
  originalPreparedReplayIdentical:true,approved:true,authenticatedNative:false});
}
const shape=await load('docs/verification/wave5/finance-pipeline-shape-readonly-investigation-20261014-r5-a4.json');
assert.equal(shape.cumulativeConservativeWorkflowRequestBound,129);
const workerDeployment=await load('docs/verification/wave5/worker-v5-routing-deployment-source-verification-20261014-r5.json');
const workerProbe=await load('docs/verification/wave5/worker-v5-routing-fixed-unauthenticated-probe-20261014-r5.json');
await load('docs/verification/wave5/worker-v5-routing-actual-finite-ingress-20261014-r5.json');
const releaseTotals=release.checks.reduce((out,row)=>{out[row.status]=(out[row.status]??0)+1;return out;},{});
const report={kind:'three-task-resumed-development-completion-status',recordedAt:new Date().toISOString(),
 userFacingDate:'2026-10-14',timezone:'Asia/Colombo',projectId:'xpdoufauvrbdmxgngetv',
 overallComplete:false,threeRequestedFullOutcomesComplete:false,productionReleaseReady:false,
 authority:'Direct user delegated technical decisions and requested resuming stalled agents without further questions.',
 personalHumanExactSourceSignatureClaimed:false,
 verification:{fullDesktop:{files:138,passed:2026,failed:0,skipped:0,currentSourceInputs:1069},
  currentPublicRuntime:{passed:122,failed:0},readerWriterIntegration:{passed:61,failed:0},offlineHarnessPassed:true,
  installedMigrations:115,apiFunctions:363,reviewedDependencies:localPackage.dependencyFilesVerified},
 requestedTasks:{authenticatedWindows:{complete:false,nativeTestAccount:'absent at current approved read-only observation',
   sealedDatabaseInputPresent:privateInputs.sealedDatabaseInputPresent,publicInputReadyReportPresent:privateInputs.publicInputReadyReportPresent,
   actualAuthenticatedWorkflowKeyboardRestartRecoveryVerified:false,
   historicalReadbacksRemainDated:true,skillBoundary:{path:'C:/Users/sheha/.codex/plugins/cache/openai-bundled/computer-use/26.1007.21434/skills/computer-use/SKILL.md',
    quotedGuidance:'Do not automate user authentication dialogs.',permissionDialogAutomationPerformed:false}},
  fullConcurrencyAndRelease:{complete:false,localInfrastructurePackageComplete:true,actualTargetScaleLoadPassed:false,
   requiredGenuineSessionCount:2000,scopeCount:500,quotaPerFiveMinutes:auth.tokenRefreshGrantQuotaPerFiveMinutes,
   jwtLifetimeSeconds:auth.jwtLifetimeSeconds,burstAllowanceFromOfficialDocs:30,
   singleIpCohortIssuanceLowerBoundSeconds:3940,maximumIssuanceWindowFor900SecondMargin:2700,
   configuredSingleIpIssuanceFeasible:false,actualCompleteCapturePresent:false,releaseAuditTotals:releaseTotals,
   productionPrerequisites:['separate staging/production and rehearsal','isolated backup restore','monitoring and delivered alert',
    'genuine performance/accessibility evidence','signed MSIX and installation/upgrade/rollback','controlled pilot and release decision']},
  requirementAcceptance:{complete:false,fullStatementsReviewed:109,originalOwnerAccepted:3,delegatedTechnicalAccepted:20,
   combinedAccepted:23,open:86,allOpenRowsHavePrerequisiteMapping:true}},
 otherCoordinatedProgress:{cashConflictRepair:{installed:true,exactErrorSites:5,routineCount:2,nonbodyMetadataPreserved:true},
  finance:{actualAdditionalDateApprovals:dates,preparedCommandReplaysVerified:2,exportsNotYetRegisteredInA3:true,
   stoppedSafelyBeforeExportWrite:true,stopCode:stop.failureCode,preservedCumulativeRequestBound:129,
   original150CapPreserved:true,oldUncertainCommandReplayed:false,originalUtc13WindowExpired:true},
  workers:{deployedRevision:5,returnedSourceModulesMatched:workerDeployment.independentlyReturnedSourceModules,
   routingRecognizedByMatchingLiveDiagnostic:true,latestBoundProbeStatus:workerProbe.status,
   latestBoundProbeCode:workerProbe.code,schedulesRemainPaused:true,providerDiagnosticSuccessorPending:true,
   actualDeliveryOrTrustedModelSuccessEstablished:false}},
 nextAuthorizedWork:'Finish the separately reviewed finite provider diagnostic and export-only feasibility/continuation. Missing private/native/capacity and production evidence remain explicit; no acceptance waiver.',
 preservedFailuresAndHistoricReviews:true,credentialsPublished:false,evidence};
const jsonBytes=Buffer.from(JSON.stringify(report,null,2)+'\n');
const jsonPath=path.join(folder,`completion-status-20261014-${attempt}.json`);
await fs.writeFile(jsonPath,jsonBytes,{flag:'wx'});
const markdown=`# Jentra OS resumed work — 14 October 2026\n\nJentra OS is not fully complete or ready for production. The resumed engineering slices have verified results; the three full requested outcomes remain open.\n\n| Requested work | Current result | Remaining evidence |\n| --- | --- | --- |\n| Authenticated Windows, keyboard, restart and recovery | Exact desktop suite: 2,026 cases pass across all 138 files, all 1,069 inputs verified. Native test account is absent. | Actual isolated Connected sign-in/MFA, workflow, keyboard and restart/recovery observations. |\n| Full concurrency/load and production checks | Reader/writer integration 61/61; current runtime provider 122/122; offline harness passes; local dependency/driver composition independently reviewed. | Private database input, 2,000 fresh genuine sessions, complete capture, seven actual races and measured workload; staging/restore/alerts/signing/pilot. |\n| Wave 5 owner review | All 109 complete statements reviewed; 3 original owner plus 20 delegated technical acceptances = **23 accepted, 86 open**. | The complete stated behavior and prerequisite evidence for every remaining row. |\n\nThe cash repair is installed: five custom error sites across two routines, with other metadata unchanged. The live baseline is 115 migrations and 363 API functions. Both remaining payment-date approvals and their exact replays completed through genuine actors. Export registration stopped before writing because the immutable forecast has separate LKR and USD rows; its single-currency test assumption was wrong. The preserved request bound is 129, under the original 150 cap.\n\nWorker V5 routing is resolved by an actual matching server diagnostic, but the handler returns provider-unavailable (503). The schedules remain paused while a diagnostic-only successor is reviewed. No actual delivery or model success is claimed.\n\nThe observed Auth token quota is 150 per five minutes and JWT lifetime is one hour. Using the documented 30-request burst, one IP needs at least 3,940 seconds to issue 2,000 tokens, beyond the 2,700-second issuance window that retains the required 900-second margin. This is a feasibility inference from actual settings and the [official rate-limit contract](https://supabase.com/docs/guides/auth/rate-limits), not a measured full-load result.\n\nThe [acceptance matrix](../task3-acceptance-20261013/delegated-technical-acceptance-matrix.md), [open-row prerequisite map](../task3-acceptance-20261013/open-requirement-prerequisites.md), [release audit](../task3-load-release-20261013/release-audit.md), [protocol result](../task3-load-release-20261013/protocol-result-a2.json) and this report's JSON retain dated evidence and exact hashes. Old failures and decisions are preserved.\n\nThe [Computer Use skill](C:/Users/sheha/.codex/plugins/cache/openai-bundled/computer-use/26.1007.21434/skills/computer-use/SKILL.md) requires guidance that says “Do not automate user authentication dialogs.” No authentication or security-permission dialog was automated; missing private setup is not marked accepted.\n`;
const mdPath=path.join(folder,`completion-status-20261014-${attempt}.md`);
await fs.writeFile(mdPath,markdown,{flag:'wx'});
process.stdout.write(JSON.stringify({json:{path:path.relative(root,jsonPath).replaceAll('\\','/'),sha256:sha(jsonBytes)},
 markdown:{path:path.relative(root,mdPath).replaceAll('\\','/'),sha256:sha(markdown)},allThreeComplete:false})+'\n');
