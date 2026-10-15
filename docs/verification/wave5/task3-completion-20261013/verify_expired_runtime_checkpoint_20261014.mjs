import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const folder=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(folder,'../../../..');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const evidence=[];
async function read(relative,expected){
  const bytes=await fs.readFile(path.join(root,relative));
  const binding={path:relative,bytes:bytes.length,sha256:hash(bytes)};
  if(expected)assert.equal(binding.sha256,expected,relative);
  evidence.push(binding);
  return bytes;
}
async function json(relative,expected){return JSON.parse(await read(relative,expected));}
const base='docs/verification/wave5/';
const originalExpiry='2026-10-14T09:57:07.481942Z';
const actual=await json(base+'runtime-global-readonly-snapshot-20261014-r5-a9.json',
  '4345c3d2fd850dc0ef49d4465487ed31c40d41f36fabfd06f41d4bbde660f8e3');
assert.equal(actual.result.isError,false);
const envelope=JSON.parse(actual.result.content.find(item=>item.type==='text').text);
// The data block is parsed only as JSON; explanatory text and SQL are never executed.
const match=envelope.result.match(/<untrusted-data-([a-f0-9-]+)>\s*(\[[\s\S]*?\])\s*<\/untrusted-data-\1>/);
assert.ok(match,'one saved SQL data block is required');
const rows=JSON.parse(match[2]);
assert.equal(rows.length,1);
const snapshot=rows[0].snapshot;
assert.equal(snapshot.observedAt,'2026-10-14T10:00:08.776229Z');
assert.equal(snapshot.migrationCount,115);
assert.equal(snapshot.apiFunctionCount,363);
assert.equal(Date.parse(snapshot.authority.expiresAt),Date.parse(originalExpiry));
assert.equal(snapshot.authority.enabled,true);
assert.equal(snapshot.authority.unexpired,false);
assert.deepEqual(snapshot.ownJobs.map(job=>[job.jobId,job.active]),[[4,false],[5,false],[6,false]]);
assert.equal(snapshot.netResponseCount,24);
assert.equal(snapshot.allKnownHandler404,true);
for(const key of ['ticks','deliveryOutcomes','receiverReceipts','quotaPeriods'])assert.equal(snapshot[key],0);
assert.deepEqual(snapshot.finance,{lines:18,exports:0,journals:9,scenarios:0,publications:3,
  dateDecisions:3,dateProposals:3,processEvents:7,classifications:1});
const rejected=await json(base+'runtime-global-readonly-snapshot-20261014-r5-a8.json');
assert.equal(rejected.result.isError,true);
const charge=actual.conservativeFinanceContinuationCharge;
assert.equal(charge.priorChargedCalls,131);
assert.equal(charge.failedConnectorValidationAttemptCharged,1);
assert.equal(charge.actualPostExpiryReadonlyFinanceSnapshotCalls,1);
assert.equal(charge.cumulativeChargedCalls,133);
assert.equal(charge.actualA10RefreshPerformed,false);
assert.equal(charge.priorChargedCalls+charge.failedConnectorValidationAttemptCharged+
  charge.actualPostExpiryReadonlyFinanceSnapshotCalls,charge.cumulativeChargedCalls);

const native=await json(base+'native-and-private-readiness-20261014-r5-a4.json',
  '1130db0d2425f6822b31900f33789616b1059e946eaf6883134a55729161c34e');
assert.equal(native.exactWindowsAccountReadExitCode,2);
for(const key of ['sealedDatabaseInputPresent','sealedModelInputPresent','publicInputReadyReportPresent',
  'currentTokenAdministrator','exactWindowsAccountPresent','exactWindowsProfileDirectoryPresent','privateSecretContentsRead'])
  assert.equal(native[key],false,key);
const worker=await json(base+'task3-completion-20261013/worker-v7-independent-actual-probe-result-20261014.json',
  '25297e420e7ac1fa62b2fef2e6b4e678a3ff13d7dd8fd59b6fadab2d46f8e236');
assert.equal(worker.deployedVersion,7);
assert.equal(worker.returnedSourceRowsVerified,25);
assert.equal(worker.status,403);
assert.equal(worker.code,'WORKER_ACCESS_DENIED');
assert.equal(worker.backendServiceKeyRoleOrValidityVerified,false);
const exportReview=await json(base+'task3-completion-20261013/export-source-package-independent-final-verification-20261014.json',
  '6cf53006775cd284e04ea7c3fc41f47f2b00ded618211dc63588295399eb6382');
assert.equal(exportReview.actualCombinedIndependentTestsPassed,64);
assert.equal(exportReview.actualLiveExportsVerified,false);
for(const binding of exportReview.sources)await read(binding.path,binding.sha256);

const audit=await json(base+'current-status-additive-audit-20261014-r5-a4.json',
  '6eba88f141a7687a0a0284199b625d368351b78e06f2a0d2b948be08f57904d4');
assert.equal(audit.passed,true);
assert.equal(audit.statementRowsVerified,109);
assert.equal(audit.totalAccepted,23);
assert.equal(audit.open,86);
assert.equal(audit.canonicalHistoricalRowsUnchanged,true);
assert.equal(audit.personalOwnerAcceptanceRecordUnchanged,true);
for(const binding of [...audit.inputBindings,...audit.outputs])await read(binding.path,binding.sha256);
const matrix=await json(base+'requirement-readiness-matrix-20261014-r5-a4.json',
  '18cd0a372fcae93a15df74b5e53d9b27977ec0f917ffe376ad3e2ef08b4f29f7');
assert.equal(matrix.currentRows.length,109);
assert.equal(new Set(matrix.currentRows.map(row=>row.id)).size,109);
assert.equal(matrix.currentRows.filter(row=>row.accepted).length,23);
assert.equal(matrix.personalHumanAcceptedCount,3);
assert.equal(matrix.delegatedTechnicalAcceptedCount,20);
assert.equal(matrix.remainingOpenCount,86);
assert.equal(matrix.wholeWaveComplete,false);

const report={kind:'primary-independent-expired-runtime-checkpoint-verification',checkedAt:new Date().toISOString(),
  projectId:'xpdoufauvrbdmxgngetv',passed:true,originalAuthorityExpiry:originalExpiry,
  actualServerObservation:snapshot,failedA8AttemptWasNotLiveSnapshot:true,
  conservativeFinanceChargedCalls:133,futureOneOwnerRefreshPlus24OperationsPlusOneResolutionCeiling:159,
  futureCeilingApproved:false,nativeMetadataObservation:native,
  acceptance:{total:109,originalHuman:3,delegatedTechnical:20,accepted:23,open:86},
  currentPublicationInputsVerified:audit.inputBindings.length,currentPublicationOutputsVerified:audit.outputs.length,
  exportSourceFilesVerified:exportReview.sources.length,exportControlledTestsPassed:64,
  v7UnsignedIngress:{version:7,modulesMatched:25,status:403,code:'WORKER_ACCESS_DENIED',
    actualBackendServiceKeyAuthorityEstablished:false},
  liveExecutionResumed:false,privateInputsRead:false,networkRequests:0,liveSQL:0,existingFilesChanged:0,
  completeAuthenticatedNative:false,completeTargetLoad:false,productionReleaseReady:false,evidence};
const bytes=Buffer.from(JSON.stringify(report,null,2)+'\n');
const relative=base+'task3-completion-20261013/expired-runtime-checkpoint-independent-verification-20261014.json';
await fs.writeFile(path.join(root,relative),bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({passed:true,path:relative,sha256:hash(bytes),evidenceBindings:evidence.length,
  publicationInputs:audit.inputBindings.length,accepted:23,open:86,chargedCalls:133})+'\n');
