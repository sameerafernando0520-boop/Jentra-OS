// NEW handoff for the actual pending r5 checkpoint. Default is read-only.
// Root alone may --write absent artifacts after the pending publication completes.
import {lstat,open,realpath,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  root,base,sourcePath,approvedSourcePath,ownerPath,promotionPath,stagePath,
  sha,eq,must,parse,inside,bytes,exists,auditInputs,stableAudit,
} from './desktop_verification_inputs_20261010_r5.mjs';
import {auditEight,auditPacket,auditDecodedGallery} from './preview_guidance_review_inputs_20261010_r5.mjs';

const self='scripts/wave5/prepare_pending_handoff_20261010_r5.mjs';
const p={before:base+'pending-verification-status-before-20261010-r5-guarded.json',after:base+'pending-verification-status-after-20261010-r5-guarded.json',
  matrix:base+'requirement-matrix-20261008.json',markdown:base+'requirement-matrix-20261008.md',status:'docs/development/wave5-status.md',
  publisher:'scripts/wave5/update_pending_verification_status_20261010_r5_guarded.mjs',
  handoff:'docs/development/wave5-next-session-20261010-r5-pending.md',index:base+'pending-handoff-20261010-r5.json',publication:base+'pending-handoff-publication-20261010-r5.json'};
const living=[p.matrix,p.markdown,p.status],acceptedIds=['AC-551','AC-552','AC-553'];
const gates=['wholeWaveComplete','actualModelUsage','realMfa','actualWorkerDelivery','authenticatedNativeAcceptance',
  'independentSessionContention','targetScaleLoad','nativeKeyboardVerified','ownerSignoff','newRuntimeInstallationComplete'];
const publisherSha='6be3404895cd6c8aae1a457604d2774ce909ddb1d9d6cb28af0ed5f79be35eb9';

async function main(){
  const args=process.argv.slice(2);must(args.length<=1&&args.every(a=>a==='--write'),'PENDING_HANDOFF_ARGUMENT_INVALID');const publish=args.includes('--write');
  const missing=[];for(const file of [p.before,p.after,...living,p.publisher,sourcePath])if(!await exists(file))missing.push(file);
  const subsequent=[];for(const file of [ownerPath,promotionPath,approvedSourcePath,stagePath('approvedAll')])if(await exists(file))subsequent.push(file);
  const SDKJobActive=await exists('build/wave5-flutter-job.lock');
  const pendingProbe=await exists(p.after)?parse(await bytes(root,p.after)):null;
  if(missing.length||subsequent.length||SDKJobActive||pendingProbe?.status!=='complete'){
    console.log(JSON.stringify({readyForHandoff:false,missing,subsequent,SDKJobActive,pendingPublicationStatus:pendingProbe?.status??'absent',outputsWritten:false,SDKJobsExecuted:false}));
    if(publish)process.exitCode=1;return;
  }
  const bound=new Map();
  async function bind(file,h){const raw=await bytes(root,file),actual=sha(raw);must((!h||h===actual)&&(!bound.has(file)||bound.get(file).sha256===actual),'HANDOFF_BOUND_INPUT_DRIFT:'+file);bound.set(file,{path:file,sha256:actual});return raw;}
  const json=async(file,h)=>parse(await bind(file,h));
  const before=await json(p.before),after=await json(p.after),matrix=await json(p.matrix);await bind(p.publisher,publisherSha);
  must(before.kind==='pending-r5-verification-evidence-before'&&after.kind==='pending-r5-verification-evidence-result'&&after.status==='complete'&&after.fullPublication===true&&
    after.publicationError===null&&after.cleanupErrors?.length===0&&after.postVerificationErrors?.length===0&&after.remainingDocuments?.length===0&&after.claimedWithoutPublication?.length===0&&
    eq(after.before,bound.get(p.before))&&eq(before.evidence,after.evidence)&&eq(after.script,bound.get(p.publisher))&&eq(before.script,bound.get(p.publisher)),'ACTUAL_COMPLETE_PENDING_PUBLICATION_REQUIRED');
  for(const key of ['all109RowsUnchanged','criterionAcceptanceUnchanged','separateGatesUnchanged','allExistingMatrixMetadataPreserved','all109MarkdownCellsUnchanged'])must(after[key]===true,'PENDING_PUBLICATION_PRESERVATION_REQUIRED:'+key);
  must(after.sourceEdits===0&&after.approvedBaselineEdits===0&&after.acceptanceStoresTouched===false&&after.SDKJobsExecuted===false&&after.liveOperations===false&&after.nativeActionsPerformed===false,'PENDING_PUBLICATION_SCOPE_REQUIRED');
  must(matrix.requirementCount===109&&matrix.rows.length===109&&new Set(matrix.rows.map(r=>r.id)).size===109&&matrix.ownerAcceptedCriteria===3&&
    eq(matrix.rows.filter(r=>r.ownerAccepted===true).map(r=>r.id),acceptedIds)&&matrix.rows.filter(r=>r.ownerAccepted===false).length===106&&
    eq(matrix.ownerCriterionAcceptance.criterionIds,acceptedIds)&&eq(matrix.currentR5PendingVerification,after.evidence),'ACTUAL109_AND_DIRECT_THREE_PENDING_METADATA_REQUIRED');
  for(const key of gates)must(matrix[key]===false,'HANDOFF_SEPARATE_GATE_CHANGED:'+key);
  const originalMatrix=parse(Buffer.from(before.originalLivingDocuments.find(r=>r.path===p.matrix).utf8Base64,'base64'));
  must(eq(matrix.rows,originalMatrix.rows)&&eq(matrix.ownerCriterionAcceptance,originalMatrix.ownerCriterionAcceptance)&&eq(matrix.currentR3Verification,originalMatrix.currentR3Verification),'ALL109_DIRECT_ACCEPTANCE_AND_R3_HISTORY_REQUIRED');
  must(before.originalLivingDocuments.length===3&&after.observedDocuments.length===3&&after.retainedRecoveries.length===3&&eq(after.changedDocuments,living),'EXACT_THREE_PENDING_DOCUMENTS_REQUIRED');
  for(const file of living){
    const original=before.originalLivingDocuments.find(r=>r.path===file),planned=before.plannedDocuments.find(r=>r.path===file),observed=after.observedDocuments.find(r=>r.path===file),recovery=after.retainedRecoveries.find(r=>r.originalPath===file);
    must(original&&sha(Buffer.from(original.utf8Base64,'base64'))===original.sha256&&planned&&observed?.matchesPlanned===true&&observed.sha256===planned.sha256&&
      recovery?.matchesOriginal===true&&recovery.matchesClaimed===true&&recovery.published===true&&recovery.sha256===original.sha256,'EXACT_PENDING_PUBLICATION_AND_ORIGINAL_RECOVERY_REQUIRED:'+file);
    await bind(file,observed.sha256);await bind(recovery.path,original.sha256);
  }
  for(const ref of after.validatedInputs.filter(r=>!living.includes(r.path)))await bind(ref.path,ref.sha256);
  const decision=await json(matrix.ownerCriterionAcceptance.ownerDecision.path,matrix.ownerCriterionAcceptance.ownerDecision.sha256);
  must(decision.kind==='direct-human-owner-decision'&&decision.submittedByOwner===true&&decision.sourceMessage?.role==='user'&&
    eq(decision.criteria.map(r=>r.id),acceptedIds)&&decision.criteria.every(r=>r.decision==='accept-complete-criterion'),'DIRECT_OWNER_DECISION_REQUIRED');
  const eight=await auditEight(),packet=await auditPacket(eight),decoded=await auditDecodedGallery(eight,packet.packet,packet.binding);
  for(const ref of (await eight.reader.recheck()).bindings)await bind(ref.path,ref.sha256);
  const auditBefore=await auditInputs(),evidence=after.evidence;
  must(evidence.phase==='preapproval-review-ready'&&eq(evidence.sourceManifest,eight.sourceManifest)&&evidence.selectedSources===1068&&evidence.sourceInputsSha256===auditBefore.currentInputsSha256&&
    evidence.newBehaviorCases===6&&evidence.expectedFullDesktopCases===2010&&evidence.fullCurrentDesktopSuiteExecuted===false&&evidence.fullCurrentDesktopSuitePassed===false&&
    evidence.currentR5WindowsBuildExecuted===false&&evidence.currentR5PackageDelivered===false&&evidence.currentR5NativeActionsExecuted===false,'EXACT_PENDING_PHASE_WITHOUT_FUTURE_EXECUTION_CLAIMS_REQUIRED');
  for(const stage of eight.stages){
    const actual=evidence.actualCompletedStages.find(s=>s.stage===stage.stage);
    must(actual&&eq(actual.result,stage.record)&&eq(actual.log,stage.log)&&eq(actual.counts,stage.counts)&&actual.actualSDKExit===stage.recordData.exitCode&&
      eq(actual.actualTestIdentities,stage.actualTestIdentities),'HANDOFF_ACTUAL_STAGE_REQUIRED:'+stage.stage);
  }
  must(eq(evidence.approvedImageControl,{passed:75,failed:8,skipped:0,expectedFailuresOnly:true,strictGoldenComparisonPassed:false})&&
    evidence.candidateImages.count===8&&evidence.candidateImages.candidateBundleSha256===eight.candidateBundleSha256&&evidence.candidateImages.ownerImageDecisionPending===true&&
    evidence.candidateImages.ownerApprovalRecorded===false&&evidence.candidateImages.promoted===false&&eq(evidence.candidateImages.ownerReview,packet.binding)&&
    eq(evidence.candidateImages.decodedGalleryIntegrity,decoded.binding),'ACTUAL_EIGHT_IMAGE_APPROVAL_PENDING_REQUIRED');
  must(evidence.historicalR3.passedDesktopTests===2004&&evidence.historicalR3.currentR5SourceMatch===false&&evidence.historicalR3.historicalEvidenceOnly===true&&
    evidence.historicalAccounting.passed===528&&evidence.historicalAccounting.testFiles===38&&evidence.historicalAccounting.currentDomainAndPlatformSourceUnchanged===true&&
    evidence.historicalAccounting.dependencyLockUnchanged===true&&evidence.historicalAccounting.reexecutedInR5===false,'DATED_2004_BUILD_NATIVE_AND528_SCOPE_REQUIRED');
  const live=await json(evidence.latestSavedLiveObservation.summary.path,evidence.latestSavedLiveObservation.summary.sha256);
  must(live.kind==='read_only_r5_live_preflight_comparison'&&live.projectId==='xpdoufauvrbdmxgngetv'&&live.observedAt===evidence.latestSavedLiveObservation.observedAt&&
    live.observedAt==='2026-10-10 13:25:31.725204+00'&&live.migrationCount===43&&live.apiFunctions===107&&live.unchangedProviders===120&&live.wave5ForcedAndEnabledRlsTables===15&&
    Object.keys(live.collisionCounters).length===14&&Object.values(live.collisionCounters).every(n=>n===0)&&live.originalSixLedger.sixOriginalEntriesMatch===true,'EXACT_SAVED13_25_LIVE_OBSERVATION_REQUIRED');
  await bind(self);
  const now=new Date().toISOString(),link=(label,to)=>`[${label}](<${path.relative(path.dirname(p.handoff),to).split(path.sep).join('/')}>)`;
  const handoffText='# Jentra OS — pending r5 continuation, October 10, 2026\n\n'+
    `Prepared at ${now} from the actual completed pending status publication. Workspace: C:\\Users\\sheha\\Desktop\\Jentra OS. Supabase project: xpdoufauvrbdmxgngetv.\n\n`+
    'First read '+link('the exact pending publication result',p.after)+', '+link('its preserved originals and inputs',p.before)+', '+link('the current requirement matrix',p.matrix)+', '+link('the living status',p.status)+', '+
    link('the frozen r5 source',sourcePath)+', '+link('the exact eight-image review',packet.binding.path)+' and '+link('the decoded gallery audit',decoded.binding.path)+'. Read every status, review, verification and contract referenced by those records before relying on a completion claim.\n\n'+
    'Owner acceptance is exactly **3/109**: AC-551, AC-552 and AC-553. The other **106 criteria remain open**. Every requirement row, statement, specification line, evidence mapping and direct owner decision was preserved. Testing delegated to agents does not create additional owner decisions.\n\n'+
    'The current r5 source has 1,068 selected inputs, exactly five declared Dart changes and six new behavior cases. Actual scoped analysis is clean. The focused run passed **23/0/0** with all 23 unique identities. The earlier 83-image strict control has **75 pass / 8 fail / 0 skip**, actual SDK exit 1. These eight failed approved comparisons remain failures. Exactly eight candidates were generated in an isolated tree and passed a separate strict **8/0/0** run. Their self-contained gallery contains 24 decoded and hash-bound images.\n\n'+
    'The eight proposed images remain **unapproved and unpromoted**. Candidate bundle SHA-256: `'+eight.candidateBundleSha256+'`. Source manifest SHA-256: `'+eight.sourceManifest.sha256+'`. '+link('Open the proposed comparisons',packet.packet.html.path)+'. The earlier 83-image owner approval and its promotion are preserved.\n\n'+
    'The previous r3 full **2,004/0/0** suite, Windows builds/package and native Preview observations belong to the earlier source and remain historical. The native record has 10 pass, 2 fail and 2 blocked; both Ctrl+K cases remain unresolved, with the application-versus-input-tool cause unconfirmed. No r5 Windows build, native action or complete **2,010-case** suite is claimed. The dated **528/0/0** controlled accounting checks retain their 38 exact files; domain/platform inputs and the dependency lock are unchanged, but these checks were not rerun as r5 and do not prove real transactions or reports.\n\n'+
    'The failed r4 focused attempt, pending auth timer, duplicate starts, missing cases and exact owned tester interruption are retained. Its raw 18/1 summary does not establish full 23-case coverage. The initial SDK cache permission failure and the failed r5 live-recorder schema attempt are also retained as failures. No failed attempt was discarded or converted to a pass.\n\n'+
    link('The latest saved live preflight',evidence.latestSavedLiveObservation.summary.path)+' observed **43 migrations / 107 API functions** at **'+live.observedAt+'**. All 120 checked providers, 15 forced/enabled RLS tables and 14 zero collision counters match the prior state. The reread ledger preserves the exact six installed Wave 5 migrations; do not replay their source names or reinstall them. Refresh live state before relying on these recorded counts or a runtime contract. Additional runtime approval/install remains open. Hosting is the existing Supabase project. Use Superpowers, Plugin Management and connected Supabase tools where appropriate.\n\n'+
    'Preserve the confirmed desktop-test-20261009@jentra.invalid test account and the existing account. Prior owner login is separate evidence; current authenticated native acceptance remains open. Use private owner Auth Admin access for any necessary account action. Never fabricate auth.users rows or request, expose or log passwords/MFA codes. Permanent deletion requires explicit confirmation of the exact account.\n\n'+
    'Next, obtain a direct owner decision for the exact eight-image packet and bundle. The guarded promotion helper must verify that decision and retained originals before replacing only those eight baselines. Root then performs the separate approved source freeze and a genuine fresh complete 2,010-case suite. Root alone runs SDK work, with per-invocation analytics suppression and serialized heavy Flutter jobs. Keep every r4/r5 frozen artifact and prior failure unchanged.\n\n'+
    'After actual image approval, promotion and a clean full suite, continue the guarded ordinary Preview/Connected Windows builds and source-bound packages, then actual native user checks. The final runtime review, final status publication and final handoff have distinct contracts; this pending checkpoint cannot satisfy them. Do not substitute old r3 records, injected gateways, rollback fixtures, browser observations or generated images for current authenticated native, genuine MFA, actual delivery/model use, independent-session contention or target-scale load.\n\n'+
    'Continue every unblocked provider, cash-date, scenario/recovery, governed-export, persistent-worker and trusted-model implementation/investigation with agents. A new runtime installation or private delivery/model exercise needs its required exact approval and current source-bound review. Keep implementation, installed SQL, authenticated native, actual delivery, contention/load and owner acceptance as separate gates. All those pending runtime/acceptance gates remain false; whole-system signoff remains open. Production and real billing are excluded.\n\n'+
    'Preserve concurrent Wave 3/4 and Employee work, acceptance stores and sessions. Do not reset, clean, broadly stage, commit or push. Do not copy acceptance-store contents into test trees. After source edits, collect fresh analysis, tests, builds and render evidence rather than relabeling previous results. Publish further status changes only through guarded successors that retain current originals and all 109 rows.\n';
  const handoffBytes=Buffer.from(handoffText),index={kind:'actual-pending-r5-handoff',revision:'r5',preparedAt:now,sourceManifest:eight.sourceManifest,
    pendingPublication:bound.get(p.after),pendingBefore:bound.get(p.before),publisher:bound.get(p.publisher),generator:bound.get(self),
    handoff:{path:p.handoff,sha256:sha(handoffBytes),bytes:handoffBytes.length},currentLivingDocuments:living.map(file=>bound.get(file)),
    ownerAcceptedCriteria:3,unacceptedCriteria:106,approvedImageComparisons:{passed:75,failed:8,skipped:0},newImagesAwaitingApproval:8,
    candidateBundleSha256:eight.candidateBundleSha256,focusedPassedTests:23,currentFullSuiteExecuted:false,currentWindowsBuildExecuted:false,currentNativeActionsExecuted:false,
    historicalDesktopPassedTests:2004,historicalAccountingPassedTests:528,latestSavedLiveObservedAt:live.observedAt,migrations:43,apiFunctions:107,
    refs:[...bound.values()],evidence,SDKJobsExecuted:false,liveOperations:false,acceptanceStoresTouched:false,ownerAcceptanceChanged:false,
    boundary:'New handoff for an actually published pending checkpoint. It grants no image/runtime/criterion approval and claims no future SDK, native or private operation.'};
  const indexBytes=Buffer.from(JSON.stringify(index,null,2)+'\n'),outputs=new Map([[p.handoff,handoffBytes],[p.index,indexBytes]]);
  async function recheck(){
    for(const ref of bound.values())must(sha(await bytes(root,ref.path))===ref.sha256,'CONCURRENT_PENDING_HANDOFF_INPUT_DRIFT:'+ref.path);
    for(const file of [ownerPath,promotionPath,approvedSourcePath,stagePath('approvedAll')])must(!await exists(file),'HANDOFF_PENDING_PHASE_ADVANCED:'+file);
    must(!await exists('build/wave5-flutter-job.lock'),'SDK_ACTIVE_DURING_PENDING_HANDOFF');
    const actual=await auditInputs();must(eq(stableAudit(actual),stableAudit(auditBefore)),'HANDOFF_CURRENT_SOURCE_SDK_OR_RESOLUTION_DRIFT');
    return{checkedAt:new Date().toISOString(),sourceManifest:actual.sourceManifest,currentAndWarmSourcesMatch:true,selectedSources:1068,pendingPublication:bound.get(p.after)};
  }
  await recheck();
  if(!publish){console.log(JSON.stringify({readyForHandoff:true,write:false,ownerAcceptedCriteria:3,unacceptedCriteria:106,newImagesAwaitingApproval:8,
    currentFullSuiteExecuted:false,currentWindowsBuildExecuted:false,currentNativeActionsExecuted:false,sourceManifest:eight.sourceManifest,
    pendingPublication:bound.get(p.after),plannedOutputs:[...outputs].map(([path,raw])=>({path,sha256:sha(raw),bytes:raw.length})),publication:p.publication,
    outputsWritten:false,SDKJobsExecuted:false}));return;}
  for(const file of [...outputs.keys(),p.publication])must(!await exists(file),'NEW_PENDING_HANDOFF_OUTPUT_REQUIRED:'+file);
  for(const folder of ['docs/development',base.slice(0,-1)]){const full=inside(root,folder);must(await realpath(full)===full&&!(await lstat(full)).isSymbolicLink(),'HANDOFF_OUTPUT_PARENT_LINK_REFUSED');}
  const journal=await open(inside(root,p.publication),'wx');
  await journal.writeFile(JSON.stringify({kind:'pending-r5-handoff-reserved',revision:'r5',startedAt:now,pendingPublication:bound.get(p.after),fullPublication:false,
    plannedOutputs:[...outputs].map(([path,raw])=>({path,sha256:sha(raw),bytes:raw.length})),boundary:'Reserved before writing; incomplete work makes no complete handoff claim.'},null,2)+'\n');await journal.sync();
  const written=[],observed=[];let failure=null,finalAudit=null;
  try{for(const [file,raw]of outputs){await recheck();await writeFile(inside(root,file),raw,{flag:'wx'});written.push(file);}finalAudit=await recheck();}catch(error){failure={message:error.message,code:error.code??null};}
  for(const [file,raw]of outputs)try{const actual=await bytes(root,file);observed.push({path:file,sha256:sha(actual),bytes:actual.length,matchesPlanned:sha(actual)===sha(raw)&&actual.length===raw.length});}catch(error){observed.push({path:file,error:error.message});}
  if(observed.some(r=>r.matchesPlanned!==true))failure??={message:'ACTUAL_PENDING_HANDOFF_OUTPUT_DRIFT',code:null};
  const fullPublication=written.length===2&&failure===null&&finalAudit!==null;
  const result={kind:'pending-r5-handoff-publication-result',revision:'r5',finishedAt:new Date().toISOString(),status:fullPublication?'complete':'failed',fullPublication,
    writtenOutputs:written,observedOutputs:observed,failure,finalSourceAudit:finalAudit,pendingPublication:bound.get(p.after),generator:bound.get(self),
    validatedInputs:[...bound.values()],ownerAcceptedCriteria:3,newImagesAwaitingApproval:8,currentFullSuiteExecuted:false,currentWindowsBuildExecuted:false,
    currentNativeActionsExecuted:false,SDKJobsExecuted:false,liveOperations:false,acceptanceStoresTouched:false,livingDocumentsChanged:false,ownerAcceptanceChanged:false,
    boundary:'Only two new handoff artifacts were attempted; originals, living documents, image baselines and acceptance were not changed. Actual partial output is retained.'};
  try{await journal.truncate(0);await journal.write(JSON.stringify(result,null,2)+'\n',0,'utf8');await journal.sync();}finally{await journal.close();}
  console.log(JSON.stringify({status:result.status,fullPublication,writtenOutputs:written,failure,publication:p.publication,ownerAcceptedCriteria:3,newImagesAwaitingApproval:8,
    currentFullSuiteExecuted:false,currentWindowsBuildExecuted:false,currentNativeActionsExecuted:false,SDKJobsExecuted:false,livingDocumentsChanged:false}));if(!fullPublication)process.exitCode=1;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
