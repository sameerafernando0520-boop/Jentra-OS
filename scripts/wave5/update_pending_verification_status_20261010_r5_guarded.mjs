// NEW pending-evidence checkpoint. The completed r3 publisher is preserved at
// SHA-256 b9ad9812995bf5bb90c27b250c24a2deab1f5b31f29a7ffa55c9cd59ff52cc4e.
// Default check is read-only. Root alone invokes --write after actual r5 review.
import {constants} from 'node:fs';
import {copyFile,lstat,mkdir,open,readFile,realpath,rename,unlink,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  root,base,sourcePath,approvedSourcePath,ownerPath,promotionPath,stagePath,stageLog,stageExit,
  sha,eq,mapEq,must,parse,inside,bytes,exists,auditInputs,stableAudit,declaredDartPaths,
} from './desktop_verification_inputs_20261010_r5.mjs';
import {verifyExecution} from './accounting_execution_verifier_20261010_r3.mjs';
import {
  auditEight,auditPacket,auditDecodedGallery,packetPath,galleryPath,markdownPath,decodedGalleryPath,
} from './preview_guidance_review_inputs_20261010_r5.mjs';

const self='scripts/wave5/update_pending_verification_status_20261010_r5_guarded.mjs';
const p={matrix:base+'requirement-matrix-20261008.json',markdown:base+'requirement-matrix-20261008.md',status:'docs/development/wave5-status.md',
  predecessor:base+'current-verification-status-after-20261010-r3-guarded.json',predecessorBefore:base+'current-verification-status-before-20261010-r3-guarded.json',
  predecessorScript:'scripts/wave5/update_current_verification_status_20261010_r3_a2_guarded.mjs',
  decision:base+'owner-criterion-decision-20261010-r2.json',acceptance:base+'owner-criterion-acceptance-after-20261010-r2-serial.json',
  accounting:base+'accounting-checks-source-20261010-r2.json',domain:base+'accounting-checks-domain-20261010-r2.json',platform:base+'accounting-checks-platform-20261010-r2.json',
  live:base+'complete-live-preflight-20261010-r5-summary.json',liveIndex:base+'complete-live-preflight-20261010-r5-index.json',liveMd:base+'complete-live-preflight-20261010-r5.md',
  failedLive:base+'failed-live-recorder-attempt-20261010-r5-a1.json',
  before:base+'pending-verification-status-before-20261010-r5-guarded.json',after:base+'pending-verification-status-after-20261010-r5-guarded.json'};
const living=[p.matrix,p.markdown,p.status],acceptedIds=['AC-551','AC-552','AC-553'];
const stages=['analyzer','focusedNonGolden','goldens83','candidate8','candidate8Strict'];
const falseGates=['wholeWaveComplete','actualModelUsage','realMfa','actualWorkerDelivery','authenticatedNativeAcceptance',
  'independentSessionContention','targetScaleLoad','nativeKeyboardVerified','ownerSignoff','newRuntimeInstallationComplete'];
const predecessorPins=[
  {path:p.predecessor,sha256:'918f62e99960966c6ac9c34e2363bc16049c995ee3632794f4b6a8486c3ea8e6'},
  {path:p.predecessorBefore,sha256:'a3f21f3092b4089817788a1b737741ecb99e91d17c4d154d62db7045d504fb15'},
  {path:p.predecessorScript,sha256:'b9ad9812995bf5bb90c27b250c24a2deab1f5b31f29a7ffa55c9cd59ff52cc4e'},
];
const tableRows=text=>text.split(/\r?\n/).filter(line=>/^\| (?:FR|NFR|AC|EC)-\d+ \|/.test(line));
const projection=j=>Object.fromEntries(Object.entries(j).filter(([k])=>!['updatedAt','currentR5PendingVerification'].includes(k)));

async function readiness(){
  const required=[...living,...predecessorPins.map(r=>r.path),sourcePath,p.decision,p.acceptance,p.accounting,p.domain,p.platform,p.live,p.liveIndex,
    packetPath,galleryPath,markdownPath,decodedGalleryPath,decodedGalleryPath.replace(/\.json$/,'.md'),
    ...stages.flatMap(s=>[stagePath(s),stageLog(s),stageExit(s)])];
  const missing=[];for(const file of required)if(!await exists(file))missing.push(file);
  const incomplete=[];for(const stage of stages)if(await exists(stagePath(stage))){const r=parse(await bytes(root,stagePath(stage)));if(r.status!=='complete')incomplete.push({stage,status:r.status});}
  const subsequent=[];for(const file of [ownerPath,promotionPath,approvedSourcePath,stagePath('approvedAll')])if(await exists(file))subsequent.push(file);
  const SDKJobActive=await exists('build/wave5-flutter-job.lock');
  return{ready:missing.length===0&&incomplete.length===0&&subsequent.length===0&&!SDKJobActive,missing,incomplete,subsequent,SDKJobActive};
}

async function main(){
  const args=process.argv.slice(2);must(args.length<=1&&args.every(a=>a==='--write'),'PENDING_R5_ARGUMENT_INVALID');
  const publish=args.includes('--write'),ready=await readiness();
  if(!ready.ready){console.log(JSON.stringify({readyForPublication:false,...ready,outputsWritten:false,SDKJobsExecuted:false,liveOperations:false}));if(publish)process.exitCode=1;return;}
  const original=new Map();for(const file of living)original.set(file,await bytes(root,file));
  const expectedLiving=new Map([...original].map(([file,b])=>[file,sha(b)])),bound=new Map();
  async function bind(file,expected){
    const raw=original.has(file)?original.get(file):await bytes(root,file),actual=sha(raw);
    must((!expected||actual===expected)&&(!bound.has(file)||bound.get(file).sha256===actual),'PENDING_R5_BOUND_INPUT_DRIFT:'+file);
    bound.set(file,{path:file,sha256:actual});return raw;
  }
  const json=async(file,h)=>parse(await bind(file,h));
  for(const ref of predecessorPins)await bind(ref.path,ref.sha256);
  const matrix=parse(original.get(p.matrix)),priorMatrix=structuredClone(matrix),prior=await json(p.predecessor),priorBefore=await json(p.predecessorBefore);
  must(matrix.requirementCount===109&&matrix.rows?.length===109&&new Set(matrix.rows.map(r=>r.id)).size===109&&matrix.ownerAcceptedCriteria===3&&
    eq(matrix.rows.filter(r=>r.ownerAccepted===true).map(r=>r.id),acceptedIds)&&matrix.rows.filter(r=>r.ownerAccepted===false).length===106,'EXACT109_AND_EXISTING_THREE_DECISIONS_REQUIRED');
  for(const key of falseGates)must(matrix[key]===false,'PENDING_R5_SEPARATE_GATE_CHANGED:'+key);
  must(!Object.hasOwn(matrix,'currentR5PendingVerification')&&matrix.currentR3Verification,'NEW_PENDING_R5_METADATA_REQUIRED');
  must(prior.status==='complete'&&prior.fullPublication===true&&prior.publicationError===null&&prior.cleanupErrors?.length===0&&prior.postVerificationErrors?.length===0&&
    prior.observedOwnerAcceptedCriteria===3&&prior.all109RowsUnchanged===true&&prior.criterionAcceptanceUnchanged===true&&prior.separateGatesUnchanged===true&&
    eq(prior.before,bound.get(p.predecessorBefore))&&eq(matrix.currentR3Verification,prior.evidence),'COMPLETED_R3_PUBLICATION_PREDECESSOR_REQUIRED');
  for(const file of living){
    const observed=prior.observedDocuments.find(r=>r.path===file),old=priorBefore.originalLivingDocuments.find(r=>r.path===file),recovery=prior.retainedRecoveries.find(r=>r.originalPath===file);
    must(observed?.matchesPlanned===true&&observed.sha256===expectedLiving.get(file)&&old&&sha(Buffer.from(old.utf8Base64,'base64'))===old.sha256&&
      recovery?.matchesOriginal===true&&recovery.matchesClaimed===true&&recovery.published===true&&recovery.sha256===old.sha256,'EXACT_R3_LIVING_AND_RECOVERY_CHECKPOINT_REQUIRED:'+file);
    await bind(recovery.path,old.sha256);
  }
  for(const ref of prior.validatedInputs)await bind(ref.path,ref.sha256);
  const originalPriorMatrix=parse(Buffer.from(priorBefore.originalLivingDocuments.find(r=>r.path===p.matrix).utf8Base64,'base64'));
  must(eq(matrix.rows,originalPriorMatrix.rows)&&eq(matrix.ownerCriterionAcceptance,originalPriorMatrix.ownerCriterionAcceptance),'R3_ALL109_ROWS_AND_ACCEPTANCE_CHANGED');
  const decision=await json(p.decision),acceptance=await json(p.acceptance);
  must(decision.kind==='direct-human-owner-decision'&&decision.authorizationKind==='direct-human-message'&&decision.submittedByOwner===true&&decision.sourceMessage?.role==='user'&&
    decision.messageSha256===sha(Buffer.from(decision.messageVerbatim))&&eq(decision.criteria.map(c=>c.id),acceptedIds)&&decision.criteria.every(c=>c.decision==='accept-complete-criterion')&&
    eq(matrix.ownerCriterionAcceptance.criterionIds,acceptedIds)&&eq(matrix.ownerCriterionAcceptance.ownerDecision,bound.get(p.decision))&&
    acceptance.status==='complete'&&acceptance.fullPublication===true&&acceptance.observedOwnerAcceptedCriteria===3&&eq(acceptance.observedOwnerAcceptedIds,acceptedIds),'DIRECT_EXISTING_OWNER_ACCEPTANCE_REQUIRED');
  for(const row of matrix.rows){must(typeof row.specification==='string'&&Number.isInteger(row.specificationLine)&&typeof row.statement==='string'&&Array.isArray(row.evidence),'ROW_PROJECTION_CHANGED:'+row.id);await bind(row.specification);}

  const eight=await auditEight(),packet=await auditPacket(eight),decoded=await auditDecodedGallery(eight,packet.packet,packet.binding);
  for(const ref of (await eight.reader.recheck()).bindings)await bind(ref.path,ref.sha256);
  const manifest=eight.manifest,sourceAudit=await auditInputs();
  must(manifest.revision==='r5'&&manifest.postImageApproval===false&&manifest.expectedTestIdentities.length===2010&&manifest.newTestIdentities.length===6&&
    eq(manifest.declaredDartDelta.map(r=>r.path),declaredDartPaths)&&sourceAudit.generatedImageChanges.length===0,'EXACT_UNAPPROVED_R5_SOURCE_SCOPE_REQUIRED');
  const stageEvidence=eight.stages.map(s=>({stage:s.stage,result:s.record,log:s.log,sdkExit:{path:s.recordData.sdkExitRecord,sha256:s.recordData.sdkExitRecordSha256},
    actualSDKExit:s.recordData.exitCode,counts:s.counts,actualTestIdentities:s.actualTestIdentities,strictGoldenComparisonPassed:s.recordData.strictGoldenComparisonPassed,
    expectedGoldenFailuresObserved:s.recordData.expectedGoldenFailuresObserved,goldenFilesRegenerated:s.recordData.goldenFilesRegenerated}));
  must(eq(stageEvidence.find(s=>s.stage==='focusedNonGolden').counts,{passed:23,failed:0,skipped:0})&&
    eq(stageEvidence.find(s=>s.stage==='goldens83').counts,{passed:75,failed:8,skipped:0})&&
    ['candidate8','candidate8Strict'].every(stage=>eq(stageEvidence.find(s=>s.stage===stage).counts,{passed:8,failed:0,skipped:0})),'EXACT_CURRENT_R5_STAGE_COUNTS_REQUIRED');

  const accounting=await json(p.accounting),historicalSource=await json(manifest.originalApprovedSource.path,manifest.originalApprovedSource.sha256);
  must(accounting.kind==='accounting_calculation_gateway_source_manifest'&&accounting.selectedSources===1068&&mapEq(accounting.sourceHashes,historicalSource.sourceHashes)&&
    accounting.sourceInputsSha256===historicalSource.sourceInputsSha256,'DATED_ACCOUNTING_SOURCE_REQUIRED');
  const dependencyChanges=Object.keys(accounting.sourceHashes).filter(file=>(file.startsWith('packages/jentra_domain/')||file.startsWith('packages/jentra_platform/'))&&accounting.sourceHashes[file]!==manifest.sourceHashes[file]);
  must(dependencyChanges.length===0&&accounting.sourceHashes['pubspec.lock']===manifest.sourceHashes['pubspec.lock'],'DATED_ACCOUNTING_SCOPE_OR_LOCK_CHANGED');
  const accountingStages=[];
  for(const [stage,file,count,fileCount] of [['domain',p.domain,122,16],['platform',p.platform,406,22]]){
    const record=await json(file),spec=accounting.stages.find(s=>s.stage===stage);
    must(record.status==='complete'&&record.stage===stage&&record.stagePassed===true&&record.exitCode===0&&record.spawnError===null&&record.integrityError===null&&
      eq(record.counts,{passed:count,failed:0,skipped:0})&&eq(record.sourceManifest,bound.get(p.accounting))&&spec?.files.length===fileCount,'DATED_ACCOUNTING_RESULT_REQUIRED:'+stage);
    const actual=verifyExecution(await bind(record.log,record.logSha256),record.workingDirectory,spec.files,record.exitCode);
    must(actual.identities.length===count&&eq(actual.identities,record.actualTestIdentities)&&eq(actual.actualFiles,record.actualExecutedFiles),'DATED_ACCOUNTING_LOG_REQUIRED:'+stage);
    accountingStages.push({stage,result:bound.get(file),log:bound.get(record.log),passed:count,testFiles:fileCount,finishedAt:record.finishedAt});
  }
  const live=await json(p.live),index=await json(p.liveIndex),liveReportPresent=await exists(p.liveMd);if(liveReportPresent)await bind(p.liveMd);
  must(index.kind==='read_only_r5_live_preflight_artifact_index'&&index.projectId==='xpdoufauvrbdmxgngetv'&&index.readOnly===true&&index.summaryPublished===true&&
    index.summary.path===p.live&&index.summary.sha256===bound.get(p.live).sha256,'DATED_LATEST_SAVED_LIVE_INDEX_REQUIRED');
  for(const ref of index.immutableInputs)await bind(ref.path,ref.sha256);
  must(live.kind==='read_only_r5_live_preflight_comparison'&&live.projectId==='xpdoufauvrbdmxgngetv'&&live.observedAt===index.observedAt&&live.migrationCount===43&&live.apiFunctions===107&&
    live.comparedFields===40&&eq(live.onlyChangedFields,['observed_at'])&&live.allPriorCollisionFieldsUnchanged===true&&
    live.checkedProviders===120&&live.unchangedProviders===120&&live.changedProviders.length===0&&live.wave5ForcedAndEnabledRlsTables===15&&
    Object.keys(live.collisionCounters).length===14&&Object.values(live.collisionCounters).every(n=>n===0)&&live.readOnly===true&&
    live.originalSixLedger.migrationLedgerListReread===true&&live.originalSixLedger.ledgerRows===43&&live.originalSixLedger.sixOriginalEntriesMatch===true&&live.originalSixLedger.preservedEntries.length===6&&
    live.originalSixLedger.preservedEntries.every(e=>e.currentMatches===1&&e.reinstalled===false)&&live.originalSixLedger.sourceMigrationNamesReplayed===false&&
    live.fullRuntimePreflightComplete===false&&live.runtimeOwnerApproved===false&&live.newRuntimeInstallationComplete===false,'DATED43_107_LIVE_AND_SIX_LEDGER_PRESERVATION_REQUIRED');
  const failedLive=await json(p.failedLive,'3017eb26a35ecc09484d6653702736f8ff5a8d5e4ddddf534aae3863dce8c969');
  must(failedLive.kind==='failed-read-only-metadata-recorder-attempt'&&failedLive.actualExitCode===1&&failedLive.outputsWritten===false&&failedLive.sqlWrites===false&&
    failedLive.SDKJobsExecuted===false&&failedLive.ownerAcceptanceChanged===false&&failedLive.script?.path==='scripts/wave5/record_live_preflight_20261010_r5.mjs'&&
    failedLive.script.sha256==='8f3186a88829a6719df62a900f2300169e148e5e7e86415299637a3b4d8cc47d','PRESERVED_FAILED_LIVE_RECORDER_HISTORY_REQUIRED');
  await bind(failedLive.script.path,failedLive.script.sha256);
  await bind(self);
  const now=new Date().toISOString(),evidence={recordedAt:now,phase:'preapproval-review-ready',sourceManifest:eight.sourceManifest,selectedSources:1068,
    sourceInputsSha256:manifest.sourceInputsSha256,declaredDartDelta:manifest.declaredDartDelta,newBehaviorCases:6,expectedFullDesktopCases:2010,
    actualCompletedStages:stageEvidence,fullCurrentDesktopSuiteExecuted:false,fullCurrentDesktopSuitePassed:false,
    approvedImageControl:{passed:75,failed:8,skipped:0,expectedFailuresOnly:true,strictGoldenComparisonPassed:false},
    candidateImages:{count:8,candidateBundleSha256:eight.candidateBundleSha256,generatedOnlyInIsolatedCopy:true,strictComparisonPassed:true,approvedRepositoryImagesChanged:false,
      ownerReview:packet.binding,gallery:packet.packet.html,decodedGalleryIntegrity:decoded.binding,ownerImageDecisionPending:true,ownerApprovalRecorded:false,promoted:false},
    historicalR3:{publication:bound.get(p.predecessor),sourceManifest:manifest.originalApprovedSource,fullDesktopRun:manifest.originalApprovedFullRun,passedDesktopTests:2004,
      pairedNativeBuild:matrix.currentR3Verification.pairedNativeBuild,delivery:matrix.currentR3Verification.delivery,actualNativePreview:matrix.currentR3Verification.actualNativePreview,
      currentR5SourceMatch:false,historicalEvidenceOnly:true,reason:'The current r5 desktop source differs in the five declared Dart inputs; r3 builds and native observations belong to the earlier source.'},
    historicalAccounting:{sourceManifest:bound.get(p.accounting),stages:accountingStages,passed:528,failed:0,skipped:0,testFiles:38,
      currentDomainAndPlatformSourceUnchanged:true,dependencyLockUnchanged:true,affectedDomainOrPlatformFiles:dependencyChanges,
      currentR5FullSourceMatch:false,reexecutedInR5:false,scope:'Dated controlled calculations and injected gateways; unchanged domain/platform inputs do not prove an authenticated user transaction.'},
    failedR4History:manifest.priorR4Verification,latestSavedLiveObservation:{summary:bound.get(p.live),index:bound.get(p.liveIndex),report:liveReportPresent?bound.get(p.liveMd):null,observedAt:live.observedAt,
      migrations:43,apiFunctions:107,unchangedProviders:120,forcedRlsTables:15,zeroCollisionCounters:14,originalSixLedgerPreserved:true,
      failedRecorderAttempt:bound.get(p.failedLive),failedRecorderScript:failedLive.script,failedRecorderOutputsWritten:false,
      fullRuntimePreflightComplete:false,runtimeOwnerApproved:false,refreshedByThisPublisher:false},
    currentR5WindowsBuildExecuted:false,currentR5PackageDelivered:false,currentR5NativeActionsExecuted:false,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,
    all109RowsAndDirectAcceptancePreserved:true,authenticatedNativeAcceptance:false,nativeKeyboardVerified:false,realMfa:false,actualDelivery:false,actualModelUsage:false,
    independentSessionContention:false,targetScaleLoad:false,newRuntimeInstallationComplete:false,ownerSignoff:false,wholeWaveComplete:false,
    boundary:'Current preapproval verification and review preparation only. Eight strict failures remain failed approved comparisons. No new owner image decision, promotion, full suite, Windows/native, installation, MFA, delivery, model, load, production or billing claim.'};
  matrix.updatedAt=now;matrix.currentR5PendingVerification=evidence;
  must(eq(projection(matrix),projection(priorMatrix))&&eq(matrix.rows,priorMatrix.rows)&&eq(matrix.ownerCriterionAcceptance,priorMatrix.ownerCriterionAcceptance),'ONLY_PENDING_R5_METADATA_MAY_CHANGE');
  const link=(from,label,to)=>`[${label}](<${path.relative(path.dirname(from),to).split(path.sep).join('/')}>)`;
  function amended(file){
    const text=original.get(file).toString('utf8');must(!text.includes('## Pending r5 verification amendment — October 10, 2026'),'DUPLICATE_PENDING_R5_AMENDMENT');
    return text.replace(/\s*$/,'')+'\n\n## Pending r5 verification amendment — October 10, 2026\n\n'+
      'The current desktop source has exactly five declared Dart changes across the approved 1,068-input scope, with six new behavior tests. '+link(file,'The frozen r5 source',sourcePath)+
      ' and actual SDK logs establish clean scoped analysis and 23/0/0 focused cases. The strict earlier 83-image control records 75 passed and eight failed comparisons; these eight failures are limited to the changed Preview guidance and warehouse form.\n\n'+
      'Exactly eight candidates were generated in an isolated copy and then passed an independent strict 8/0/0 comparison. '+link(file,'The exact eight-image owner review',packetPath)+' and '+link(file,'self-contained comparison gallery',galleryPath)+
      ' bind the approved, candidate and diff bytes. All 24 embedded images passed decoded integrity checks. The eight candidates remain unapproved and unpromoted; the earlier 83-image approval remains preserved. A fresh complete 2,010-case suite and current Windows builds/native checks remain pending after that exact image decision.\n\n'+
      'The earlier r3 full 2,004-case suite, Windows package and 10-pass/2-fail/2-blocked native Preview observations belong to the earlier source. Their records and previous prose remain historical; they do not establish a current r5 build or native result. Both earlier Ctrl+K cases remain unresolved, and native keyboard acceptance remains false.\n\n'+
      'The separately dated 528/0/0 controlled accounting checks retain exact logs and 38 test-file identities. Their domain/platform inputs and dependency lock remain unchanged, but the full desktop source has changed and these checks were not rerun as r5. Actual accounting transactions and authoritative reports remain pending. The failed r4 timer fixture, incomplete cases, owned tester interruption and initial SDK permission failure remain preserved as failed historical evidence.\n\n'+
      link(file,'The latest saved read-only live observation',liveReportPresent?p.liveMd:p.live)+` observed 43 migrations and 107 API functions at ${live.observedAt}, with 120 unchanged providers, 15 forced/enabled RLS tables and 14 zero collision counters. `+
      'Its reread ledger preserves the exact six installed Wave 5 entries without replay. This status publisher performed no new live operation. Additional runtime approval and installation remain pending.\n\n'+
      'Owner acceptance remains exactly 3/109 (AC-551, AC-552, AC-553), with the other 106 criteria and every row, specification, evidence mapping and direct decision unchanged. Authenticated native acceptance, full native keyboard, genuine MFA, actual delivery/model usage, independent-session contention, target-scale load and owner signoff remain false. '+
      link(file,'The immutable pending checkpoint',p.before)+' and '+link(file,'actual publication result',p.after)+' retain originals and observed publication outcomes. Production and real billing remain excluded.\n';
  }
  const outputs=new Map([[p.matrix,Buffer.from(JSON.stringify(matrix,null,2)+'\n')],[p.markdown,Buffer.from(amended(p.markdown))],[p.status,Buffer.from(amended(p.status))]]);
  must(tableRows(original.get(p.markdown).toString()).length===109&&eq(tableRows(outputs.get(p.markdown).toString()),tableRows(original.get(p.markdown).toString())),'ALL109_MARKDOWN_CELLS_MUST_REMAIN_EXACT');
  async function recheck(claimedFile=null){
    for(const [file,h]of expectedLiving)if(file!==claimedFile)must(sha(await bytes(root,file))===h,'CONCURRENT_PENDING_LIVING_CHANGE:'+file);
    for(const ref of bound.values())if(!living.includes(ref.path))must(sha(await bytes(root,ref.path))===ref.sha256,'CONCURRENT_PENDING_BOUND_CHANGE:'+ref.path);
    for(const file of [ownerPath,promotionPath,approvedSourcePath,stagePath('approvedAll')])must(!await exists(file),'PENDING_PHASE_ALREADY_ADVANCED:'+file);
    must(!await exists('build/wave5-flutter-job.lock'),'SDK_STAGE_ACTIVE_DURING_PENDING_PUBLICATION');
    const current=await auditInputs();must(eq(stableAudit(current),stableAudit(sourceAudit)),'PENDING_R5_CURRENT_SOURCE_TOOL_OR_RESOLUTION_DRIFT');
    return{checkedAt:new Date().toISOString(),sourceManifest:current.sourceManifest,selectedSources:1068,sourceInputsSha256:current.currentInputsSha256,
      currentAndWarmSourcesMatch:true,sourceAndToolchainAudit:current,predecessor:bound.get(p.predecessor),ownerImageDecisionPending:true};
  }
  const initialAudit=await recheck(),before={preparedAt:now,kind:'pending-r5-verification-evidence-before',evidence,predecessor:bound.get(p.predecessor),script:bound.get(self),
    originalLivingDocuments:[...original].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length,utf8Base64:b.toString('base64')})),
    plannedDocuments:[...outputs].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length})),boundInputs:[...bound.values()],currentSourceAudit:initialAudit,
    all109RowsUnchanged:true,criterionAcceptanceUnchanged:true,separateGatesUnchanged:true,ownerAcceptedCriteria:3,
    boundary:'Only new pending r5 evidence metadata and appended prose in three named living documents. No source, approved PNG, acceptance-store, SDK, live or native action.'};
  if(!publish){console.log(JSON.stringify({readyForPublication:true,write:false,phase:evidence.phase,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,
    counts:stageEvidence.map(s=>({stage:s.stage,actualSDKExit:s.actualSDKExit,counts:s.counts})),candidateBundleSha256:eight.candidateBundleSha256,
    sourceManifest:eight.sourceManifest,documents:before.plannedDocuments,immutableBefore:p.before,immutableAfter:p.after,
    all109RowsUnchanged:true,directOwnerAcceptanceUnchanged:true,separateGatesUnchanged:true,outputsWritten:false,SDKJobsExecuted:false,liveOperations:false}));return;}
  for(const file of [p.before,p.after])must(!await exists(file),'IMMUTABLE_PENDING_RESULT_EXISTS:'+file);
  await recheck();
  const recoveryDirectory=base+'pending-verification-status-recovery-20261010-r5-'+randomUUID();
  const parent=inside(root,base.slice(0,-1));must(await realpath(parent)===parent&&!(await lstat(parent)).isSymbolicLink(),'PENDING_PUBLICATION_PARENT_LINK_REFUSED');
  const states=[...outputs].map(([file,b])=>({path:file,target:inside(root,file),bytes:b,originalSha256:sha(original.get(file)),plannedSha256:sha(b),
    recoveryPath:recoveryDirectory+'/'+path.basename(file),recovery:inside(root,recoveryDirectory+'/'+path.basename(file)),temp:null,tempOwned:false,claimed:false,published:false,claimedSha256:null}));
  before.recoveryDirectory=recoveryDirectory;before.publicationPlans=states.map(({bytes,target,recovery,temp,...s})=>s);
  const beforeBytes=Buffer.from(JSON.stringify(before,null,2)+'\n');await writeFile(inside(root,p.before),beforeBytes,{flag:'wx'});
  const resultHandle=await open(inside(root,p.after),'wx');
  await resultHandle.writeFile(JSON.stringify({kind:'pending-r5-verification-evidence-reserved',before:{path:p.before,sha256:sha(beforeBytes)},fullPublication:false,
    recoveryDirectory,boundary:'Reserved before publication; interruption never establishes complete status publication.'},null,2)+'\n');await resultHandle.sync();
  const changed=[],cleanupErrors=[],postVerificationErrors=[];let publicationError=null,finalAudit=null;
  try{
    await mkdir(inside(root,recoveryDirectory));
    for(const state of states){
      await recheck();state.temp=inside(root,state.path+'.'+randomUUID()+'.tmp');const temp=await open(state.temp,'wx');state.tempOwned=true;
      try{await temp.writeFile(state.bytes);await temp.sync();}finally{await temp.close();}
      await recheck();await rename(state.target,state.recovery);state.claimed=true;state.claimedSha256=sha(await readFile(state.recovery));
      must(state.claimedSha256===state.originalSha256,'CONCURRENT_CLAIMED_PENDING_DOCUMENT_CHANGE:'+state.path);await recheck(state.path);
      must(sha(await readFile(state.recovery))===state.originalSha256&&sha(await readFile(state.temp))===state.plannedSha256,'OWNED_PENDING_PUBLICATION_BYTES_CHANGED');
      await copyFile(state.temp,state.target,constants.COPYFILE_EXCL);state.published=true;expectedLiving.set(state.path,state.plannedSha256);changed.push(state.path);await recheck();
    }
  }catch(error){publicationError={message:error.message,code:error.code??null};}
  for(const state of states.filter(s=>s.tempOwned))try{await unlink(state.temp);}catch(error){if(error.code!=='ENOENT')cleanupErrors.push({path:path.relative(root,state.temp),message:error.message,code:error.code??null});}
  const observed=[],recoveries=[];
  for(const file of living)try{const raw=await bytes(root,file);observed.push({path:file,sha256:sha(raw),bytes:raw.length,matchesPlanned:sha(raw)===sha(outputs.get(file))});}catch(error){observed.push({path:file,error:error.message});}
  for(const state of states.filter(s=>s.claimed))try{const h=sha(await bytes(root,state.recoveryPath));recoveries.push({path:state.recoveryPath,originalPath:state.path,sha256:h,originalSha256:state.originalSha256,
    claimedSha256:state.claimedSha256,matchesOriginal:h===state.originalSha256,matchesClaimed:h===state.claimedSha256,published:state.published});}catch(error){recoveries.push({path:state.recoveryPath,error:error.message});}
  let accepted=null,rowsPreserved=false,acceptancePreserved=false,gatesPreserved=false,otherMetadataPreserved=false,markdownRowsPreserved=false;
  try{
    const actual=parse(await bytes(root,p.matrix));accepted=actual.ownerAcceptedCriteria;rowsPreserved=eq(actual.rows,priorMatrix.rows);
    acceptancePreserved=eq(actual.ownerCriterionAcceptance,priorMatrix.ownerCriterionAcceptance);gatesPreserved=falseGates.every(k=>actual[k]===priorMatrix[k]);
    otherMetadataPreserved=eq(projection(actual),projection(priorMatrix));markdownRowsPreserved=eq(tableRows((await bytes(root,p.markdown)).toString()),tableRows(original.get(p.markdown).toString()));
  }catch{}
  try{finalAudit=await recheck();}catch(error){postVerificationErrors.push({gate:'finalPendingSourceBoundAndToolAudit',message:error.message});publicationError??={message:error.message,code:error.code??null};}
  if(observed.some(r=>r.matchesPlanned!==true)||accepted!==3||!rowsPreserved||!acceptancePreserved||!gatesPreserved||!otherMetadataPreserved||!markdownRowsPreserved){
    postVerificationErrors.push({gate:'actualDestinationsAnd109Projection',message:'ACTUAL_PENDING_STATUS_DRIFT'});publicationError??={message:'ACTUAL_PENDING_STATUS_DRIFT',code:null};}
  if(recoveries.length!==states.filter(s=>s.claimed).length||recoveries.some(r=>r.matchesOriginal!==true||r.matchesClaimed!==true)){
    postVerificationErrors.push({gate:'actualRetainedRecoveries',message:'ACTUAL_PENDING_RECOVERY_DRIFT'});publicationError??={message:'ACTUAL_PENDING_RECOVERY_DRIFT',code:null};}
  if(cleanupErrors.length)publicationError??={message:'OWNED_PENDING_TEMP_CLEANUP_FAILED',code:null};
  const fullPublication=changed.length===3&&publicationError===null&&cleanupErrors.length===0&&postVerificationErrors.length===0&&finalAudit!==null;
  const after={finishedAt:new Date().toISOString(),kind:'pending-r5-verification-evidence-result',before:{path:p.before,sha256:sha(beforeBytes)},predecessor:bound.get(p.predecessor),
    script:bound.get(self),status:fullPublication?'complete':'failed',fullPublication,changedDocuments:changed,remainingDocuments:living.filter(file=>!changed.includes(file)),
    observedDocuments:observed,retainedRecoveries:recoveries,claimedWithoutPublication:states.filter(s=>s.claimed&&!s.published).map(s=>({path:s.path,recoveryPath:s.recoveryPath,claimedSha256:s.claimedSha256})),
    publicationError,cleanupErrors,postVerificationErrors,finalSourceAndToolAudit:finalAudit,validatedInputs:[...bound.values()],recoveryDirectory,evidence,
    observedOwnerAcceptedCriteria:accepted,all109RowsUnchanged:rowsPreserved,criterionAcceptanceUnchanged:acceptancePreserved,separateGatesUnchanged:gatesPreserved,
    allExistingMatrixMetadataPreserved:otherMetadataPreserved,all109MarkdownCellsUnchanged:markdownRowsPreserved,sourceEdits:0,approvedBaselineEdits:0,
    acceptanceStoresTouched:false,SDKJobsExecuted:false,liveOperations:false,nativeActionsPerformed:false,
    boundary:'Only pending r5 evidence metadata and an appended amendment in three exact living documents changed. Originals and observed partial outcomes are retained; no new approval or gate was granted.'};
  try{await resultHandle.truncate(0);await resultHandle.write(JSON.stringify(after,null,2)+'\n',0,'utf8');await resultHandle.sync();}finally{await resultHandle.close();}
  console.log(JSON.stringify({status:after.status,fullPublication,changedDocuments:changed,publicationError,cleanupErrors,postVerificationErrors,
    ownerAcceptedCriteria:accepted,all109RowsUnchanged:rowsPreserved,criterionAcceptanceUnchanged:acceptancePreserved,separateGatesUnchanged:gatesPreserved,
    before:p.before,after:p.after,SDKJobsExecuted:false,nativeActionsPerformed:false}));if(!fullPublication)process.exitCode=1;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
