// NEW final-r5 successor. Default check is read-only; root alone owns --write.
// The completed r3 and pending-r5 publishers and all original records are retained.
// Only three living evidence documents may change. No SDK, UI, SQL or store operation.
import {constants} from 'node:fs';
import {copyFile,lstat,mkdir,open,readFile,realpath,rename,unlink,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {root,base,sha,eq,must,parse,inside,bytes,exists} from './desktop_verification_inputs_20261010_r5.mjs';
import {helperPath,finalPaths,finalPrerequisites,auditFinalEvidence,recheckFinalSource} from './final_verification_inputs_20261010_r5.mjs';

export const publisherPath='scripts/wave5/update_current_verification_status_20261010_r5_guarded.mjs';
export const publicationPaths={matrix:base+'requirement-matrix-20261008.json',markdown:base+'requirement-matrix-20261008.md',status:'docs/development/wave5-status.md',
  predecessor:base+'pending-verification-status-after-20261010-r5-guarded.json',predecessorBefore:base+'pending-verification-status-before-20261010-r5-guarded.json',
  predecessorScript:'scripts/wave5/update_pending_verification_status_20261010_r5_guarded.mjs',
  resumeLive:base+'resume-live-metadata-20261011-r5.json',
  before:base+'current-verification-status-before-20261010-r5-guarded.json',after:base+'current-verification-status-after-20261010-r5-guarded.json'};
export const livingPaths=[publicationPaths.matrix,publicationPaths.markdown,publicationPaths.status];
export const acceptedIds=['AC-551','AC-552','AC-553'];
export const falseGates=['wholeWaveComplete','actualModelUsage','realMfa','actualWorkerDelivery','authenticatedNativeAcceptance',
  'independentSessionContention','targetScaleLoad','nativeKeyboardVerified','ownerSignoff','newRuntimeInstallationComplete'];
const helperSha='a037a25f5ed7c7fd5b456bffc6db95e50b7645aa9b97409b692d2561f30ab306';
const resumeLiveSha='1d799b91f9c652bd85565c4356db04596244c5168f9021870ecdfb7e7df237f4';
const predecessorPins=[
  {path:publicationPaths.predecessor,sha256:'bdb8d28b1e9f60036a5e86f18b0226cfba0774809e438436404d83f59ab10cae'},
  {path:publicationPaths.predecessorBefore,sha256:'356b690a16c7f4669c0c80d00491ead1512dc7b334cf584425caac0ee8f0d29e'},
  {path:publicationPaths.predecessorScript,sha256:'6be3404895cd6c8aae1a457604d2774ce909ddb1d9d6cb28af0ed5f79be35eb9'},
];
const predecessorLiving=new Map([
  [publicationPaths.matrix,'e4327453a0de8c8ede991be82e9438ce0ad06ee114f4be61e0684ba7e2d20923'],
  [publicationPaths.markdown,'cb4ef50bb9888397dea66d870d9ca6cc459167d24128d7f151ef8b4d69e337b3'],
  [publicationPaths.status,'5c80f50fa77c4bb10a12102ee8cfd0b9f14d449232bbc4463a3e67d93e0b70b7'],
]);
const projection=j=>Object.fromEntries(Object.entries(j).filter(([key])=>!['updatedAt','currentR5Verification'].includes(key)));
const tableRows=text=>text.split(/\r?\n/).filter(line=>/^\| (?:FR|NFR|AC|EC)-\d+ \|/.test(line));
function exactAcceptance(matrix){
  must(matrix.requirementCount===109&&matrix.rows?.length===109&&new Set(matrix.rows.map(row=>row.id)).size===109&&matrix.ownerAcceptedCriteria===3&&
    eq(matrix.rows.filter(row=>row.ownerAccepted===true).map(row=>row.id),acceptedIds)&&matrix.rows.filter(row=>row.ownerAccepted===false).length===106&&
    eq(matrix.ownerCriterionAcceptance?.criterionIds,acceptedIds),'EXACT_109_AND_DIRECT_THREE_REQUIRED');
  for(const key of falseGates)must(matrix[key]===false,'FINAL_SEPARATE_GATE_CHANGED:'+key);
}
function reader(original=new Map()){
  const bound=new Map();
  async function bind(file,expected){const raw=original.has(file)?original.get(file):await bytes(root,file),actual=sha(raw);
    must((!expected||expected===actual)&&(!bound.has(file)||bound.get(file).sha256===actual),'FINAL_BOUND_INPUT_DRIFT:'+file);
    bound.set(file,{path:file,sha256:actual});return raw;}
  return{bound,bind,json:async(file,h)=>parse(await bind(file,h))};
}
async function idle(){must(!await exists('build/wave5-flutter-job.lock'),'SDK_ACTIVE_DURING_FINAL_STATUS');}
async function auditResumeLive(r){
  const record=await r.json(publicationPaths.resumeLive,resumeLiveSha);
  must(record.kind==='read-only-resume-live-counts-and-public-key-observation'&&record.projectId==='xpdoufauvrbdmxgngetv'&&record.readOnly===true&&
    record.observedAt==='2026-10-11 10:26:01.347929+00'&&record.migrationCount===43&&record.apiFunctions===107&&record.ledgerRows===43&&record.edgeInventoryCount===2&&
    record.edgeMetadataMatchesPrior===true&&record.originalSixPreserved?.length===6&&record.originalSixPreserved.every(row=>row.currentMatches===1&&row.reinstalled===false)&&
    record.publicBuild?.publicKeyOnly===true&&record.publicBuild.keyValuesPrinted===false&&record.publicBuild.matchedEnabledPublicKeys===1&&record.publicBuild.environment==='development',
    'EXACT_ADDITIONAL_NARROW_RESUME_OBSERVATION_REQUIRED');
  for(const key of ['edgeFunctionSourceBodiesReread','providersRehashed','accessCountsRequeried','trialAccountMembershipRequeried','privateCredentialsOrSecretsInspected','sqlInstalled',
    'AuthAccountsChanged','SDKJobsExecutedByThisRead','nativeActionsPerformed','ownerAcceptanceChanged','runtimeOwnerApproved','fullRuntimeImmediatePreflightComplete'])must(record[key]===false,'RESUME_NARROW_READ_BOUNDARY_CHANGED:'+key);
  must(record.priorFullMetadata?.path===finalPaths.live&&record.priorFullMetadata.sha256==='04db48a15b4e5ceee6ac25f15d91702739dde04f983fc5ae63b9826bab6634ed'&&
    record.priorFullMetadata.observedAt==='2026-10-10 13:25:31.725204+00','DATED_FULL_PREFLIGHT_MUST_REMAIN_SEPARATE');
  await r.bind(record.publicBuild.configPath,record.publicBuild.configSha256);
  await r.bind(base+'current-public-build-binding-20261010-r5.json',record.publicBuild.existingBuildBindingSha256);
  return record;
}

// Shared read-only validation of an actually completed publication for the handoff.
// Importing this module performs no publication or prerequisite evaluation.
export async function auditPublishedFinalStatus(){
  const p=publicationPaths,r=reader();await idle();
  const before=await r.json(p.before),after=await r.json(p.after),matrix=await r.json(p.matrix);
  await r.bind(publisherPath);await r.bind(helperPath,helperSha);
  must(before.kind==='current-r5-verification-evidence-before'&&after.kind==='current-r5-verification-evidence-result'&&after.status==='complete'&&after.fullPublication===true&&
    after.publicationError===null&&after.cleanupErrors?.length===0&&after.postVerificationErrors?.length===0&&after.remainingDocuments?.length===0&&after.claimedWithoutPublication?.length===0&&
    eq(after.before,r.bound.get(p.before))&&eq(before.evidence,after.evidence)&&eq(after.script,r.bound.get(publisherPath))&&eq(before.script,r.bound.get(publisherPath)),
    'ACTUAL_COMPLETE_FINAL_R5_PUBLICATION_REQUIRED');
  for(const key of ['all109RowsUnchanged','criterionAcceptanceUnchanged','separateGatesUnchanged','allExistingMatrixMetadataPreserved','all109MarkdownCellsUnchanged'])must(after[key]===true,'FINAL_PUBLICATION_PRESERVATION_REQUIRED:'+key);
  must(after.sourceEdits===0&&after.approvedBaselineEdits===0&&after.acceptanceStoresTouched===false&&after.SDKJobsExecuted===false&&after.liveOperations===false&&after.nativeActionsPerformed===false,'FINAL_PUBLICATION_SCOPE_REQUIRED');
  exactAcceptance(matrix);must(eq(matrix.currentR5Verification,after.evidence),'FINAL_MATRIX_METADATA_NOT_ACTUAL_PUBLICATION');
  const originals=before.originalLivingDocuments;must(originals?.length===3&&before.plannedDocuments?.length===3&&after.observedDocuments?.length===3&&after.retainedRecoveries?.length===3&&eq(after.changedDocuments,livingPaths),'EXACT_THREE_FINAL_DOCUMENTS_REQUIRED');
  for(const file of livingPaths){const old=originals.find(row=>row.path===file),planned=before.plannedDocuments.find(row=>row.path===file),observed=after.observedDocuments.find(row=>row.path===file),recovery=after.retainedRecoveries.find(row=>row.originalPath===file);
    must(old&&sha(Buffer.from(old.utf8Base64,'base64'))===old.sha256&&old.sha256===predecessorLiving.get(file)&&planned&&observed?.matchesPlanned===true&&observed.sha256===planned.sha256&&observed.bytes===planned.bytes&&
      recovery?.matchesOriginal===true&&recovery.matchesClaimed===true&&recovery.published===true&&recovery.sha256===old.sha256,'FINAL_ACTUAL_DESTINATION_AND_RECOVERY_REQUIRED:'+file);
    await r.bind(file,observed.sha256);await r.bind(recovery.path,old.sha256);
  }
  const oldMatrix=parse(Buffer.from(originals.find(row=>row.path===p.matrix).utf8Base64,'base64'));
  must(eq(projection(matrix),projection(oldMatrix))&&eq(matrix.currentR5PendingVerification,oldMatrix.currentR5PendingVerification)&&
    eq(matrix.ownerCriterionAcceptance,oldMatrix.ownerCriterionAcceptance)&&eq(tableRows((await bytes(root,p.markdown)).toString()),tableRows(Buffer.from(originals.find(row=>row.path===p.markdown).utf8Base64,'base64').toString())),
    'FINAL_ROWS_DIRECT_ACCEPTANCE_PENDING_HISTORY_OR_OTHER_METADATA_CHANGED');
  for(const ref of after.validatedInputs.filter(row=>!livingPaths.includes(row.path)))await r.bind(ref.path,ref.sha256);
  const evidence=await auditFinalEvidence(r);
  const resume=await auditResumeLive(r);
  must(eq(after.evidence.sourceManifest,r.bound.get(finalPaths.source))&&eq(after.evidence.pairedNativeBuild,r.bound.get(finalPaths.paired))&&
    eq(after.evidence.actualNativePreview.record,r.bound.get(finalPaths.native))&&eq(after.evidence.actualNativePreview.report,r.bound.get(finalPaths.nativeMd))&&
    eq(after.evidence.actualNativePreview.counts,evidence.counts)&&eq(after.evidence.additionalReadOnlyLiveObservation.record,r.bound.get(p.resumeLive))&&
    after.evidence.additionalReadOnlyLiveObservation.observedAt===resume.observedAt,'FINAL_PUBLISHED_EVIDENCE_BINDINGS_REQUIRED');
  await recheckFinalSource(evidence);await idle();
  for(const ref of r.bound.values())must(sha(await bytes(root,ref.path))===ref.sha256,'PUBLISHED_FINAL_INPUT_DRIFT:'+ref.path);
  return{...r,before,after,matrix,evidence};
}

async function main(){
  const args=process.argv.slice(2);must(args.length<=1&&args.every(arg=>arg==='--write'),'FINAL_R5_ARGUMENT_INVALID');const publish=args.includes('--write'),p=publicationPaths;
  const missing=[];for(const file of [...livingPaths,...predecessorPins.map(ref=>ref.path),helperPath,p.resumeLive,...finalPrerequisites])if(!await exists(file))missing.push(file);
  const SDKJobActive=await exists('build/wave5-flutter-job.lock'),nativeProbe=await exists(finalPaths.native)?parse(await bytes(root,finalPaths.native)):null;
  if(missing.length||SDKJobActive||nativeProbe?.status!=='complete'){
    console.log(JSON.stringify({readyForPublication:false,missing,SDKJobActive,nativeStatus:nativeProbe?.status??'absent',outputsWritten:false,SDKJobsExecuted:false,liveOperations:false}));if(publish)process.exitCode=1;return;
  }
  const original=new Map();for(const file of livingPaths){const raw=await bytes(root,file);must(sha(raw)===predecessorLiving.get(file),'EXACT_PENDING_PREDECESSOR_LIVING_REQUIRED:'+file);original.set(file,raw);}
  const expectedLiving=new Map([...original].map(([file,raw])=>[file,sha(raw)])),r=reader(original),{bound,bind,json}=r;
  for(const ref of predecessorPins)await bind(ref.path,ref.sha256);await bind(helperPath,helperSha);
  const prior=await json(p.predecessor),priorBefore=await json(p.predecessorBefore),matrix=parse(original.get(p.matrix)),priorMatrix=structuredClone(matrix);
  exactAcceptance(matrix);must(!Object.hasOwn(matrix,'currentR5Verification')&&matrix.currentR5PendingVerification&&matrix.currentR3Verification,'NEW_FINAL_R5_METADATA_AND_PRESERVED_HISTORY_REQUIRED');
  must(prior.kind==='pending-r5-verification-evidence-result'&&prior.status==='complete'&&prior.fullPublication===true&&prior.publicationError===null&&prior.cleanupErrors?.length===0&&prior.postVerificationErrors?.length===0&&
    prior.observedOwnerAcceptedCriteria===3&&prior.all109RowsUnchanged===true&&prior.criterionAcceptanceUnchanged===true&&prior.separateGatesUnchanged===true&&prior.allExistingMatrixMetadataPreserved===true&&
    prior.all109MarkdownCellsUnchanged===true&&eq(prior.before,bound.get(p.predecessorBefore))&&eq(prior.evidence,priorBefore.evidence)&&eq(matrix.currentR5PendingVerification,prior.evidence),'ACTUAL_PENDING_R5_PREDECESSOR_REQUIRED');
  for(const file of livingPaths){const observed=prior.observedDocuments.find(row=>row.path===file),old=priorBefore.originalLivingDocuments.find(row=>row.path===file),recovery=prior.retainedRecoveries.find(row=>row.originalPath===file);
    must(observed?.matchesPlanned===true&&observed.sha256===expectedLiving.get(file)&&old&&sha(Buffer.from(old.utf8Base64,'base64'))===old.sha256&&
      recovery?.matchesOriginal===true&&recovery.matchesClaimed===true&&recovery.published===true&&recovery.sha256===old.sha256,'PENDING_CHECKPOINT_AND_ORIGINAL_RECOVERY_REQUIRED:'+file);await bind(recovery.path,old.sha256);}
  for(const ref of prior.validatedInputs)await bind(ref.path,ref.sha256);
  const priorOriginalMatrix=parse(Buffer.from(priorBefore.originalLivingDocuments.find(row=>row.path===p.matrix).utf8Base64,'base64'));
  must(eq(matrix.rows,priorOriginalMatrix.rows)&&eq(matrix.ownerCriterionAcceptance,priorOriginalMatrix.ownerCriterionAcceptance),'EXACT_109_AND_DIRECT_ACCEPTANCE_HISTORY_REQUIRED');
  for(const row of matrix.rows){must(typeof row.specification==='string'&&Number.isInteger(row.specificationLine)&&typeof row.statement==='string'&&Array.isArray(row.evidence),'ROW_PROJECTION_CHANGED:'+row.id);await bind(row.specification);}
  const a=await auditFinalEvidence(r),resume=await auditResumeLive(r);must(eq(matrix.ownerCriterionAcceptance.ownerDecision,bound.get(finalPaths.criterion)),'DIRECT_THREE_OWNER_DECISION_BINDING_CHANGED');await bind(publisherPath);
  const now=new Date().toISOString(),evidence={recordedAt:now,revision:'r5',phase:'postapproval-native-preview-evidence-ready',sourceManifest:bound.get(finalPaths.source),sourceFileCount:1068,
    sourceInputsSha256:a.source.sourceInputsSha256,declaredDartDelta:a.source.declaredDartDelta,newBehaviorCases:6,expectedFullDesktopCases:2010,
    pendingPredecessor:{publication:bound.get(p.predecessor),before:bound.get(p.predecessorBefore),metadataPreserved:true,historicalPhase:'preapproval-review-ready'},
    original83ImageApproval:a.source.original83Approval,original83Promotion:a.source.original83Promotion,laterEightImageApproval:bound.get(finalPaths.owner),laterEightImagePromotion:bound.get(finalPaths.promotion),
    candidateBundleSha256:a.owner.candidateBundleSha256,approvedImageDelta:a.source.exactApprovedImageDelta,approvedGoldenFailures:0,
    pairedNativeBuild:bound.get(finalPaths.paired),pairedReport:bound.get(finalPaths.pairedMd),delivery:bound.get(finalPaths.delivery),
    zip:{path:a.zipPath,sha256:a.delivery.zipSha256,bytes:a.delivery.zipBytes},runnerIdentityOverlaysPerApp:3,previewAndConnectedOrdinaryBuilds:true,
    fullDesktopMatchingBase:{record:bound.get(finalPaths.full),log:{path:a.desktop.log,sha256:a.desktop.logSha256},sdkExit:a.desktop.sdkExitRecord,passed:2010,failed:0,skipped:0,
      finishedAt:a.desktop.finishedAt,actualUniqueTestIdentities:2010,all83ApprovedGoldenComparisonsIncluded:true,rerunInIdentityOverlayTrees:false,executedByThisPublisher:false},
    actualNativePreview:{record:bound.get(finalPaths.native),report:bound.get(finalPaths.nativeMd),counts:a.counts,cases:a.native.observations.length,screenshots:a.screenshotCount,
      uniqueScreenshotHashes:a.uniqueScreenshotHashes,startedAt:a.native.startedAt,finishedAt:a.native.finishedAt,observedCaseIds:a.native.observations.map(row=>row.id),
      failedCaseIds:a.native.observations.filter(row=>row.result==='fail').map(row=>row.id),blockedCaseIds:a.native.observations.filter(row=>row.result==='blocked').map(row=>row.id),
      inputToolEvidence:a.native.inputToolEvidence,productSuiteObservedAt:a.native.productSuiteObservedAt,exactNewExecutableAndBoundWindows:true,
      prelaunchPathObservation:bound.get(finalPaths.storage),postlaunchPathObservation:bound.get(finalPaths.postStorage),actualAccountingTransactions:false,authenticated:false,
      scope:'Actual ordinary offline Preview cases only. Their observed pass/fail/blocked outcomes do not close authenticated keyboard, login, accounting, MFA or owner gates.'},
    workerAdapter:{record:bound.get(finalPaths.worker),workerFiles:26,sourceUnchanged:true,controlledTests:71,denoEntrypoints:2,testsRerun:false,denoChecksRerun:false,
      historicalComponent:bound.get(finalPaths.component),historicalObservedAt:a.component.preparedAt,deploymentSourceFileCounts:[14,8],deployed:false,actualDelivery:false,actualModelUsage:false},
    accounting:{report:bound.get(finalPaths.accountingMd),sourceManifest:bound.get(finalPaths.accounting),stages:a.accountingStages,passed:528,failed:0,skipped:0,exactFiles:38,
      currentDomainAndPlatformSourceUnchanged:true,dependencyLockUnchanged:true,reexecutedInR5:false,currentFullDesktopSourceMatch:false,actualTransactions:false,
      scope:'Dated controlled calculations and injected gateways. The unchanged domain/platform scope does not establish an authenticated user transaction.'},
    readOnlyLivePreflight:{index:bound.get(finalPaths.liveIndex),summary:bound.get(finalPaths.live),observedAt:a.live.observedAt,migrations:43,apiFunctions:107,unchangedProviders:120,
      forcedRlsTables:15,zeroCollisionCounters:14,originalSixLedgerPreserved:true,fullRuntimePreflightComplete:false,runtimeOwnerApproved:false,refreshedByThisPublisher:false},
    additionalReadOnlyLiveObservation:{record:bound.get(p.resumeLive),observedAt:resume.observedAt,migrations:43,apiFunctions:107,ledgerRows:43,edgeMetadataObjects:2,
      originalSixPreserved:true,matchedEnabledPublicKeys:1,publicKeyValuesPrinted:false,providersRehashed:false,rlsAccessOrCollisionsRequeried:false,trialAccountMembershipRequeried:false,
      fullRuntimeImmediatePreflightComplete:false,runtimeOwnerApproved:false,refreshedByThisPublisher:false,
      scope:'Separate October 11 narrow read of three SQL fields, the ledger, Edge metadata and public-key match. The full October 10 provider/RLS/access/collision observation retains its original date.'},
    failedR4History:a.source.priorR4Verification,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,all109RowsAndExistingAcceptanceUnchanged:true,currentR5PendingVerificationPreserved:true,
    authenticatedNativeAcceptance:false,nativeKeyboardVerified:false,realMfa:false,actualDelivery:false,actualModelUsage:false,independentSessionContention:false,targetScaleLoad:false,
    newRuntimeInstallationComplete:false,ownerSignoff:false,wholeWaveComplete:false,
    boundary:'Current source-bound controlled verification, paired packages and actual offline Preview evidence only. SDK, native and live observation dates remain separate. No new criterion decision, installation, private operation, production or real billing.'};
  matrix.updatedAt=now;matrix.currentR5Verification=evidence;
  must(eq(projection(matrix),projection(priorMatrix))&&eq(matrix.rows,priorMatrix.rows)&&eq(matrix.ownerCriterionAcceptance,priorMatrix.ownerCriterionAcceptance)&&eq(matrix.currentR5PendingVerification,priorMatrix.currentR5PendingVerification),'ONLY_NEW_FINAL_METADATA_MAY_CHANGE');
  const link=(from,label,to)=>`[${label}](<${path.relative(path.dirname(from),to).split(path.sep).join('/')}>)`;
  function amended(file){const text=original.get(file).toString('utf8');must(!text.includes('## Current r5 verification amendment'),'DUPLICATE_FINAL_R5_AMENDMENT');
    return text.replace(/\s*$/,'')+'\n\n## Current r5 verification amendment\n\n'+`Recorded at ${now}; the 20261010 r5 labels identify the preserved revision, not the observation date. `+
      link(file,'The exact approved r5 source',finalPaths.source)+` and actual complete SDK log establish **2,010 passed / 0 failed / 0 skipped**, finished at ${a.desktop.finishedAt}. All 83 approved golden comparisons are included. `+
      'The original 83-image decision and separate exact eight-image decision/promotion are preserved. The earlier pending 75/8 comparison remains historical; its failures were not relabeled as passing.\n\n'+
      link(file,'Paired ordinary Preview and Connected packages',finalPaths.paired)+` bind ${a.releaseCount} release entries, ${a.inputs.packageFiles.length} portable files and every decoded ZIP byte. `+
      'Both copies use the same 1,068 base inputs with exactly three runner identity overlays each. The full suite was not rerun in those identity copies. Packaging checkpoint nativeLaunched=false remains intact.\n\n'+
      link(file,'The subsequent actual offline Preview session',finalPaths.nativeMd)+` recorded ${a.native.observations.length} closed cases: ${a.counts.pass} pass, ${a.counts.fail} fail, ${a.counts.blocked} blocked, with ${a.screenshotCount} screenshots. `+
      `Failed IDs: ${evidence.actualNativePreview.failedCaseIds.join(', ')||'none'}. Blocked IDs: ${evidence.actualNativePreview.blockedCaseIds.join(', ')||'none'}. `+
      'These actual outcomes and exact windows are retained. The input tool documentation/version, product SDK, completed suite, builds and native-action times remain distinct. Preview authenticates no user and posts no accounting transaction; authenticated native keyboard and accounting acceptance remain open.\n\n'+
      link(file,'Postlaunch directory metadata',finalPaths.postStorage)+' checks only the same four isolated product paths. No directory contents, credentials, sessions or existing acceptance stores were read or copied.\n\n'+
      link(file,'The current worker source adapter',finalPaths.worker)+' revalidates 26 unchanged worker files and the 14/8-file payloads. Its 71 controlled tests and two Deno checks retain their dated r14 observations and were not rerun. '+
      link(file,'The dated accounting checks',finalPaths.accountingMd)+' retain 528/0/0 cases across 38 files; domain/platform inputs and the dependency lock remain unchanged, but the full desktop source changed and these checks were not rerun as r5. No delivery, model call, installed provider, posting or report acceptance follows from this evidence.\n\n'+
      link(file,'The frozen r5 read-only Supabase preflight',finalPaths.live)+` observed 43 migrations / 107 API functions at ${a.live.observedAt}; 120 providers, 15 forced/enabled RLS tables, 14 zero collision counters and the six exact installed ledger entries are preserved. `+
      'This publisher did not refresh live state. Re-query immediately before relying on a runtime contract. The additional 71 operations remain unapproved and uninstalled; hosting is the existing Supabase project.\n\n'+
      link(file,'A separate narrow October 11 live observation',p.resumeLive)+` observed 43 migrations / 107 API functions at ${resume.observedAt}, reread 43 ledger rows with the six exact installed entries preserved, retained the same two Edge metadata objects and matched one enabled public key without printing values. `+
      'It did not rehash the 120 providers or repeat RLS/access/collision or trial-account checks. It grants no runtime approval or complete immediate operation preflight.\n\n'+
      'Owner acceptance remains exactly **3/109** (AC-551, AC-552, AC-553); the other **106 criteria remain open**. Every row, statement, specification line, evidence mapping, direct decision and currentR5PendingVerification checkpoint is preserved. '+
      'Authenticated native acceptance, full native keyboard, genuine MFA, actual exports/worker delivery/model usage, independent-session contention, target-scale load, runtime installation and owner signoff remain false. '+
      link(file,'The immutable final publication checkpoint',p.before)+' and '+link(file,'actual publication result',p.after)+' retain the original documents and partial/complete outcome. Earlier prose remains dated historical evidence. Production and real billing remain excluded.\n';}
  const outputs=new Map([[p.matrix,Buffer.from(JSON.stringify(matrix,null,2)+'\n')],[p.markdown,Buffer.from(amended(p.markdown))],[p.status,Buffer.from(amended(p.status))]]);
  must(tableRows(original.get(p.markdown).toString()).length===109&&eq(tableRows(outputs.get(p.markdown).toString()),tableRows(original.get(p.markdown).toString())),'EXACT_ALL109_MARKDOWN_CELLS_REQUIRED');
  async function recheck(claimedFile=null){await idle();for(const [file,h]of expectedLiving)if(file!==claimedFile)must(sha(await bytes(root,file))===h,'CONCURRENT_FINAL_LIVING_CHANGE:'+file);
    for(const ref of bound.values())if(!livingPaths.includes(ref.path))must(sha(await bytes(root,ref.path))===ref.sha256,'CONCURRENT_FINAL_BOUND_CHANGE:'+ref.path);return recheckFinalSource(a);}
  const initialAudit=await recheck(),before={preparedAt:now,kind:'current-r5-verification-evidence-before',evidence,predecessor:bound.get(p.predecessor),script:bound.get(publisherPath),helper:bound.get(helperPath),
    originalLivingDocuments:[...original].map(([file,raw])=>({path:file,sha256:sha(raw),bytes:raw.length,utf8Base64:raw.toString('base64')})),plannedDocuments:[...outputs].map(([file,raw])=>({path:file,sha256:sha(raw),bytes:raw.length})),
    boundInputs:[...bound.values()],currentSourceAudit:initialAudit,all109RowsUnchanged:true,criterionAcceptanceUnchanged:true,separateGatesUnchanged:true,ownerAcceptedCriteria:3,currentR5PendingVerificationPreserved:true,
    boundary:'Only new current-r5 metadata and appended prose in three exact living documents. No source, approved image, SDK, UI, live, private store or owner-decision action.'};
  if(!publish){console.log(JSON.stringify({readyForPublication:true,write:false,phase:evidence.phase,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,fullDesktopCounts:{passed:2010,failed:0,skipped:0},
    fullDesktopFinishedAt:a.desktop.finishedAt,nativeCounts:a.counts,nativeScreenshots:a.screenshotCount,documents:before.plannedDocuments,before:p.before,after:p.after,all109RowsUnchanged:true,
    directAcceptanceUnchanged:true,pendingHistoryPreserved:true,separateGatesUnchanged:true,outputsWritten:false,SDKJobsExecuted:false,liveOperations:false}));return;}
  for(const file of [p.before,p.after])must(!await exists(file),'IMMUTABLE_FINAL_OUTPUT_EXISTS:'+file);await recheck();
  for(const folder of ['docs/development',base.slice(0,-1)]){const full=inside(root,folder);must(await realpath(full)===full&&!(await lstat(full)).isSymbolicLink(),'FINAL_OUTPUT_PARENT_LINK_REFUSED');}
  const recoveryDirectory=base+'current-verification-status-recovery-20261010-r5-'+randomUUID();
  const states=[...outputs].map(([file,raw])=>({path:file,target:inside(root,file),bytes:raw,originalSha256:sha(original.get(file)),plannedSha256:sha(raw),recoveryPath:recoveryDirectory+'/'+path.basename(file),
    recovery:inside(root,recoveryDirectory+'/'+path.basename(file)),temp:null,tempOwned:false,claimed:false,published:false,claimedSha256:null}));
  before.recoveryDirectory=recoveryDirectory;before.publicationPlans=states.map(({bytes,target,recovery,temp,...state})=>state);
  const beforeBytes=Buffer.from(JSON.stringify(before,null,2)+'\n');await writeFile(inside(root,p.before),beforeBytes,{flag:'wx'});const handle=await open(inside(root,p.after),'wx');
  await handle.writeFile(JSON.stringify({kind:'current-r5-verification-evidence-reserved',before:{path:p.before,sha256:sha(beforeBytes)},fullPublication:false,recoveryDirectory,
    boundary:'Reserved before living publication. Interruption never establishes completion.'},null,2)+'\n');await handle.sync();
  const changed=[],cleanupErrors=[],postVerificationErrors=[];let publicationError=null,finalAudit=null;
  try{await mkdir(inside(root,recoveryDirectory));for(const state of states){await recheck();state.temp=inside(root,state.path+'.'+randomUUID()+'.tmp');const temp=await open(state.temp,'wx');state.tempOwned=true;
      try{await temp.writeFile(state.bytes);await temp.sync();}finally{await temp.close();}await recheck();await rename(state.target,state.recovery);state.claimed=true;state.claimedSha256=sha(await readFile(state.recovery));
      must(state.claimedSha256===state.originalSha256,'CONCURRENT_CLAIMED_FINAL_DOCUMENT_CHANGE:'+state.path);await recheck(state.path);
      must(sha(await readFile(state.recovery))===state.originalSha256&&sha(await readFile(state.temp))===state.plannedSha256,'OWNED_FINAL_PUBLICATION_BYTES_CHANGED');
      await copyFile(state.temp,state.target,constants.COPYFILE_EXCL);state.published=true;expectedLiving.set(state.path,state.plannedSha256);changed.push(state.path);await recheck();}}
  catch(error){publicationError={message:error.message,code:error.code??null};}
  for(const state of states.filter(item=>item.tempOwned))try{await unlink(state.temp);}catch(error){if(error.code!=='ENOENT')cleanupErrors.push({path:path.relative(root,state.temp),message:error.message,code:error.code??null});}
  const observed=[],recoveries=[];for(const file of livingPaths)try{const raw=await bytes(root,file);observed.push({path:file,sha256:sha(raw),bytes:raw.length,matchesPlanned:sha(raw)===sha(outputs.get(file))});}catch(error){observed.push({path:file,error:error.message});}
  for(const state of states.filter(item=>item.claimed))try{const h=sha(await bytes(root,state.recoveryPath));recoveries.push({path:state.recoveryPath,originalPath:state.path,sha256:h,originalSha256:state.originalSha256,
      claimedSha256:state.claimedSha256,matchesOriginal:h===state.originalSha256,matchesClaimed:h===state.claimedSha256,published:state.published});}catch(error){recoveries.push({path:state.recoveryPath,error:error.message});}
  let accepted=null,rowsPreserved=false,acceptancePreserved=false,gatesPreserved=false,metadataPreserved=false,markdownPreserved=false,pendingPreserved=false;
  try{const actual=parse(await bytes(root,p.matrix));accepted=actual.ownerAcceptedCriteria;rowsPreserved=eq(actual.rows,priorMatrix.rows);acceptancePreserved=eq(actual.ownerCriterionAcceptance,priorMatrix.ownerCriterionAcceptance);
    gatesPreserved=falseGates.every(key=>actual[key]===priorMatrix[key]);metadataPreserved=eq(projection(actual),projection(priorMatrix));pendingPreserved=eq(actual.currentR5PendingVerification,priorMatrix.currentR5PendingVerification);
    markdownPreserved=eq(tableRows((await bytes(root,p.markdown)).toString()),tableRows(original.get(p.markdown).toString()));}catch{}
  try{finalAudit=await recheck();}catch(error){postVerificationErrors.push({gate:'finalLivingSourceAndToolAudit',message:error.message});publicationError??={message:error.message,code:error.code??null};}
  if(observed.some(item=>item.matchesPlanned!==true)||accepted!==3||!rowsPreserved||!acceptancePreserved||!gatesPreserved||!metadataPreserved||!markdownPreserved||!pendingPreserved){postVerificationErrors.push({gate:'actualDestinationsAnd109Projection',message:'ACTUAL_FINAL_STATUS_DRIFT'});publicationError??={message:'ACTUAL_FINAL_STATUS_DRIFT',code:null};}
  if(recoveries.length!==states.filter(item=>item.claimed).length||recoveries.some(item=>item.matchesOriginal!==true||item.matchesClaimed!==true)){postVerificationErrors.push({gate:'actualRetainedRecoveries',message:'ACTUAL_FINAL_RECOVERY_DRIFT'});publicationError??={message:'ACTUAL_FINAL_RECOVERY_DRIFT',code:null};}
  if(cleanupErrors.length)publicationError??={message:'OWNED_FINAL_TEMP_CLEANUP_FAILED',code:null};
  const fullPublication=changed.length===3&&publicationError===null&&cleanupErrors.length===0&&postVerificationErrors.length===0&&finalAudit!==null;
  const after={finishedAt:new Date().toISOString(),kind:'current-r5-verification-evidence-result',before:{path:p.before,sha256:sha(beforeBytes)},predecessor:bound.get(p.predecessor),script:bound.get(publisherPath),helper:bound.get(helperPath),
    status:fullPublication?'complete':'failed',fullPublication,changedDocuments:changed,remainingDocuments:livingPaths.filter(file=>!changed.includes(file)),observedDocuments:observed,retainedRecoveries:recoveries,
    claimedWithoutPublication:states.filter(item=>item.claimed&&!item.published).map(item=>({path:item.path,recoveryPath:item.recoveryPath,claimedSha256:item.claimedSha256})),publicationError,cleanupErrors,postVerificationErrors,
    finalSourceAndToolAudit:finalAudit,validatedInputs:[...bound.values()],recoveryDirectory,evidence,observedOwnerAcceptedCriteria:accepted,all109RowsUnchanged:rowsPreserved,criterionAcceptanceUnchanged:acceptancePreserved,
    separateGatesUnchanged:gatesPreserved,allExistingMatrixMetadataPreserved:metadataPreserved,all109MarkdownCellsUnchanged:markdownPreserved,currentR5PendingVerificationPreserved:pendingPreserved,
    sourceEdits:0,approvedBaselineEdits:0,acceptanceStoresTouched:false,SDKJobsExecuted:false,liveOperations:false,nativeActionsPerformed:false,
    boundary:'Only current-r5 evidence metadata and appended prose changed. Originals and actual partial outcomes are retained; no new approval or independent gate is granted.'};
  try{await handle.truncate(0);await handle.write(JSON.stringify(after,null,2)+'\n',0,'utf8');await handle.sync();}finally{await handle.close();}
  console.log(JSON.stringify({status:after.status,fullPublication,changedDocuments:changed,publicationError,cleanupErrors,postVerificationErrors,ownerAcceptedCriteria:accepted,all109RowsUnchanged:rowsPreserved,
    directAcceptanceUnchanged:acceptancePreserved,separateGatesUnchanged:gatesPreserved,pendingHistoryPreserved:pendingPreserved,before:p.before,after:p.after,SDKJobsExecuted:false,nativeActionsPerformed:false}));if(!fullPublication)process.exitCode=1;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
