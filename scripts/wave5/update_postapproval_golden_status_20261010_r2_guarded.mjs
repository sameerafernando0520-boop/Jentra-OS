// Evidence publication only. Preview is read-only; root may explicitly use --write.
// Preserve all 109 rows and existing owner/runtime authority. No SDK/live operation.
import {access,copyFile,lstat,mkdir,open,readFile,realpath,rename,unlink,writeFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),base='docs/verification/wave5/';
const publish=process.argv.includes('--write');
if(process.argv.slice(2).some(a=>a!=='--write')||process.argv.slice(2).length>1)throw Error('UNKNOWN_ARGUMENT');
const self='scripts/wave5/update_postapproval_golden_status_20261010_r2_guarded.mjs';
const p={matrix:base+'requirement-matrix-20261008.json',markdown:base+'requirement-matrix-20261008.md',status:'docs/development/wave5-status.md',
  manifest:base+'golden-review-postapproval-source-20261010-r2.json',run:base+'golden-review-approvedAll-20261010-r2.json',
  priorSource:base+'golden-review-source-20261010-r2.json',candidate:base+'golden-review-candidate-20261010-r2.json',
  review:base+'golden-owner-review-20261010-r2.json',readiness:base+'owner-acceptance-readiness-20261010-r2.json',
  promotion:base+'golden-promotion-result-20261010-r2.json',imageDecision:base+'owner-golden-decision-20261010-r2.json',
  criterionDecision:base+'owner-criterion-decision-20261010-r2.json',acceptBefore:base+'owner-criterion-acceptance-before-20261010-r2-serial.json',
  acceptAfter:base+'owner-criterion-acceptance-after-20261010-r2-serial.json',live:base+'complete-live-preflight-20261010-r2-summary.json',
  liveRaw:base+'complete-live-preflight-20261010-r2-raw.json',liveSql:base+'complete-live-preflight-20261010-r2.sql',
  liveQueries:base+'complete-live-preflight-20261010-r2-query-hashes.json',liveCompare:base+'complete-live-preflight-20261010-r2-fingerprint-comparison.json',
  liveNative:base+'complete-live-preflight-20261010-r2-native.json',liveMd:base+'complete-live-preflight-20261010-r2.md',
  liveNativeNet:base+'complete-live-preflight-20261010-r2-native-net.json',
  before:base+'postapproval-golden-status-before-20261010-r2-guarded.json',after:base+'postapproval-golden-status-after-20261010-r2-guarded.json'};
const living=[p.matrix,p.markdown,p.status],ids=['AC-551','AC-552','AC-553'];
const sha=b=>createHash('sha256').update(b).digest('hex'),eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const must=(c,m)=>{if(!c)throw Error(m);};
const parse=b=>JSON.parse(b.toString('utf8').replace(/^\uFEFF/,''));
function inside(file){
  must(typeof file==='string'&&!path.isAbsolute(file),'RELATIVE_PATH_REQUIRED');
  const absolute=path.resolve(root,file),rel=path.relative(root,absolute);
  must(rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'PATH_ESCAPES:'+file);
  return absolute;
}
async function bytes(file){
  const absolute=inside(file),stat=await lstat(absolute),resolved=await realpath(absolute),rel=path.relative(root,resolved);
  must(stat.isFile()&&!stat.isSymbolicLink()&&rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'REGULAR_INPUT_REQUIRED:'+file);
  return readFile(absolute);
}
const original=new Map(await Promise.all(living.map(async file=>[file,await bytes(file)])));
const expectedLiving=new Map([...original].map(([file,b])=>[file,sha(b)])),bound=new Map();
async function bind(file,h){
  const b=original.has(file)?original.get(file):await bytes(file),actual=sha(b);
  must((!h||h===actual)&&(!bound.has(file)||bound.get(file).sha256===actual),'BOUND_INPUT_DRIFT:'+file);
  bound.set(file,{path:file,sha256:actual});return b;
}
const json=async(file,h)=>parse(await bind(file,h));
const matrix=parse(original.get(p.matrix)),priorMatrix=structuredClone(matrix);
must(matrix.requirementCount===109&&matrix.rows?.length===109&&new Set(matrix.rows.map(r=>r.id)).size===109&&matrix.ownerAcceptedCriteria===3&&
  eq(matrix.rows.filter(r=>r.ownerAccepted===true).map(r=>r.id),ids)&&matrix.rows.filter(r=>r.ownerAccepted===false).length===106,'EXACT_THREE_ACCEPTED_REQUIRED');
const falseGates=['wholeWaveComplete','actualModelUsage','realMfa','actualWorkerDelivery','authenticatedNativeAcceptance',
  'independentSessionContention','targetScaleLoad','nativeKeyboardVerified','ownerSignoff','newRuntimeInstallationComplete'];
for(const k of falseGates)must(matrix[k]===false,'SEPARATE_GATE_CHANGED:'+k);
const [manifest,run,priorSource,candidate,review,readiness,promotion,ownerImages,ownerCriteria,acceptBefore,acceptAfter,live,liveRaw,queries,comparison,native,nativeNet]=await Promise.all([
  json(p.manifest),json(p.run),json(p.priorSource),json(p.candidate),json(p.review),json(p.readiness),json(p.promotion),json(p.imageDecision),
  json(p.criterionDecision),json(p.acceptBefore),json(p.acceptAfter),json(p.live),json(p.liveRaw),json(p.liveQueries),json(p.liveCompare),json(p.liveNative),json(p.liveNativeNet)]);
await bind(p.liveSql);await bind(p.liveMd);
must(acceptAfter.status==='complete'&&acceptAfter.fullPublication===true&&acceptAfter.publicationError===null&&acceptAfter.cleanupErrors?.length===0&&
  acceptAfter.postVerificationErrors?.length===0&&acceptAfter.observedOwnerAcceptedCriteria===3&&eq(acceptAfter.observedOwnerAcceptedIds,ids)&&
  acceptAfter.exactCriterionProjectionPreserved===true&&acceptAfter.other106RowsUnchanged===true&&acceptAfter.separateGatesUnchanged===true&&
  eq(acceptAfter.criterionIds,ids)&&acceptAfter.claimedWithoutPublication?.length===0,'ACTUAL_ACCEPTANCE_PUBLICATION_REQUIRED');
await bind(acceptAfter.before.path,acceptAfter.before.sha256);
must(acceptAfter.before.path===p.acceptBefore&&eq(acceptAfter.ownerDecision,{path:p.criterionDecision,sha256:bound.get(p.criterionDecision).sha256}), 'ACCEPTANCE_RECORD_BINDING_CHANGED');
must(acceptAfter.observedDocuments?.length===3&&acceptAfter.retainedRecoveries?.length===3&&acceptBefore.originalLivingDocuments?.length===3,'ACCEPTANCE_RECOVERY_SCOPE_CHANGED');
for(const file of living){
  const actual=acceptAfter.observedDocuments.find(x=>x.path===file),old=acceptBefore.originalLivingDocuments.find(x=>x.path===file);
  must(actual?.matchesPlanned===true&&actual.sha256===expectedLiving.get(file)&&old&&sha(Buffer.from(old.utf8Base64,'base64'))===old.sha256,'ACCEPTANCE_DESTINATION_CHANGED:'+file);
  const r=acceptAfter.retainedRecoveries.find(x=>x.originalPath===file);
  must(r?.matchesOriginal===true&&r.published===true&&r.sha256===old.sha256&&r.claimedSha256===old.sha256&&r.originalSha256===old.sha256,'ACCEPTANCE_RECOVERY_CHANGED:'+file);
  await bind(r.path,old.sha256);
}
function checkOwner(o,file){
  must(o.kind==='direct-human-owner-decision'&&o.authorizationKind==='direct-human-message'&&o.submittedByOwner===true&&o.sourceMessage?.role==='user'&&
    typeof o.sourceMessage.messageId==='string'&&o.sourceMessage.messageId.trim()&&typeof o.sourceMessage.threadId==='string'&&o.sourceMessage.threadId.trim()&&
    Number.isFinite(Date.parse(o.sourceMessage.receivedAt))&&typeof o.messageVerbatim==='string'&&o.messageVerbatim.trim()&&
    o.messageSha256===sha(Buffer.from(o.messageVerbatim))&&o.reviewSha256===review.reviewSha256&&o.candidateBundleSha256===candidate.bundleSha256,'DIRECT_OWNER_RECORD_CHANGED:'+file);
  must(o.packet?.path===p.review&&o.packet.sha256===bound.get(p.review).sha256,'OWNER_PACKET_CHANGED:'+file);
}
checkOwner(ownerImages,p.imageDecision);checkOwner(ownerCriteria,p.criterionDecision);
must(eq(ownerCriteria.criteria?.map(x=>x.id),ids)&&matrix.ownerCriterionAcceptance&&eq(matrix.ownerCriterionAcceptance.criterionIds,ids)&&
  eq(matrix.ownerCriterionAcceptance.ownerDecision,{path:p.criterionDecision,sha256:bound.get(p.criterionDecision).sha256})&&
  matrix.ownerCriterionAcceptance.review.reviewSha256===review.reviewSha256,'OWNER_ACCEPTANCE_SCOPE_CHANGED');
const reviewExtras=new Set(['reviewSha256','html','imageCount','embeddedImages','allDecisionsInitiallyPending','actualOwnerDecisionsRecorded','ownerAcceptanceCount','reviewCore']);
must(eq(Object.fromEntries(Object.entries(review).filter(([k])=>!reviewExtras.has(k))),review.reviewCore)&&
  sha(Buffer.from(JSON.stringify(review.reviewCore)))===review.reviewSha256&&review.imageCount===83&&review.embeddedImages===249&&
  review.actualOwnerDecisionsRecorded===0&&review.ownerAcceptanceCount===0&&review.allDecisionsInitiallyPending===true&&
  review.requirements?.length===109&&review.requirements.every(r=>r.ownerAccepted===false),'PRESERVED_PREDECISION_PACKET_CHANGED');
await bind(review.html.path,review.html.sha256);
must(eq(review.readiness,readiness)&&readiness.rows?.length===109&&readiness.ownerAcceptedCriteria===0&&readiness.wholeWaveComplete===false&&
  readiness.rows.every(r=>r.ownerAccepted===false)&&eq(readiness.rows.filter(r=>r.wholeCriterionReadyForOwnerReview===true).map(r=>r.id),ids),'PRESERVED_READINESS_CHANGED');
for(const row of matrix.rows){
  const historical=review.requirements.find(r=>r.id===row.id),ready=readiness.rows.find(r=>r.id===row.id);
  must(historical&&ready&&historical.bundle===row.bundle&&historical.specification===row.specification&&ready.specificationLine===row.specificationLine&&
    ready.statement===row.statement,'IDENTITY_OR_SPECIFICATION_CHANGED:'+row.id);
  const lines=(await bind(row.specification)).toString('utf8').split(/\r?\n/),words=[];
  for(let i=row.specificationLine-1;i<lines.length;i++){const line=lines[i];if(i>row.specificationLine-1&&(!line.trim()||/^(?:- |###? )?(?:FR|NFR|AC|EC)-\d+:/.test(line)||/^## /.test(line)))break;words.push(line.replace(/^(?:- |### )/,'').trim());}
  must(words[0]?.startsWith(row.id+':')&&ready.fullCriterionStatement===words.join(' ')&&historical.statement===words.join(' '),'FULL_STATEMENT_CHANGED:'+row.id);
}
for(const d of ownerCriteria.criteria){
  const ready=readiness.rows.find(r=>r.id===d.id);
  must(d.decision==='accept-complete-criterion'&&d.fullCriterionStatement===ready.fullCriterionStatement&&typeof d.decisionQuote==='string'&&
    ownerCriteria.messageVerbatim.includes(d.decisionQuote)&&d.decisionQuote.includes(d.id),'CRITERION_DECISION_CHANGED:'+d.id);
}
const stableKeys=['snapshot','workingDirectory','sourceHashes','selectedSources','sourceInputsSha256','priorSourceManifest','candidate','packet','promotion','ownerDecision',
  'exactApprovedImageDelta','expectedTestIdentities','toolchain','bindings'];
must(run.stage==='approvedAll'&&run.status==='complete'&&run.fullSuitePassed===true&&run.exitCode===0&&run.integrityError===null&&run.spawnError===null&&
  eq(run.counts,{passed:2004,failed:0,skipped:0})&&run.sourceManifest.path===p.manifest&&run.sourceManifest.sha256===bound.get(p.manifest).sha256&&
  run.workingDirectory===manifest.workingDirectory&&Date.parse(run.startedAt)>=Date.parse(manifest.frozenAt)&&Date.parse(run.finishedAt)>=Date.parse(run.startedAt), 'ACTUAL_FULL2004_NOT_GREEN');
must(manifest.kind==='postapproval_desktop1068_source_manifest'&&manifest.selectedSources===1068&&Object.keys(manifest.sourceHashes).length===1068&&
  manifest.sourceInputsSha256===sha(Buffer.from(JSON.stringify(manifest.sourceHashes)))&&manifest.currentSourceMatchesApprovedInputs===true&&manifest.warmSourceMatchesApprovedInputs===true&&
  manifest.priorSourceManifest.path===p.priorSource&&manifest.priorSourceManifest.sha256===bound.get(p.priorSource).sha256&&
  manifest.packet.path===p.review&&manifest.packet.sha256===bound.get(p.review).sha256&&manifest.packet.reviewSha256===review.reviewSha256&&
  manifest.promotion.path===p.promotion&&manifest.promotion.sha256===bound.get(p.promotion).sha256&&manifest.ownerDecision.path===p.imageDecision&&
  manifest.ownerDecision.sha256===bound.get(p.imageDecision).sha256,'POSTAPPROVAL_MANIFEST_BINDING_CHANGED');
for(const k of stableKeys)must(eq(manifest[k],run.inputAuditBefore?.[k])&&eq(manifest[k],run.inputAuditAfter?.[k]),'FULL_SUITE_SOURCE_AUDIT_DRIFT:'+k);
must(eq(run.expectedTestIdentities,manifest.expectedTestIdentities)&&eq(run.actualTestIdentities,manifest.expectedTestIdentities)&&
  run.actualTestIdentities.length===2004&&new Set(run.actualTestIdentities).size===2004,'EXACT2004_RECORDED_IDENTITIES_REQUIRED');
const text=(await bind(run.log,run.logSha256)).toString('utf8'),parsed=parseTestLog(text);
must(parsed?.allTestsPassed&&parsed.passedTests===2004&&parsed.failedTests===0&&parsed.skippedTests===0&&parsed.failures.length===0,'FULL2004_LOG_NOT_GREEN');
const prefix=path.join(manifest.workingDirectory,'test').replaceAll('\\','/')+'/';
const executed=[...text.replace(/\r/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)]
  .filter(m=>m[2]!=='(setUpAll)'&&m[2]!=='(tearDownAll)').map(m=>{const f=m[1].replaceAll('\\','/');must(f.startsWith(prefix),'TEST_SCOPE_CHANGED');return f.slice(prefix.length)+': '+m[2];}).sort();
must(executed.length===2004&&new Set(executed).size===2004&&eq(executed,manifest.expectedTestIdentities),'EXACT2004_ACTUAL_IDENTITIES_REQUIRED');
must(eq(run.args,['C:/src/flutter/bin/cache/flutter_tools.snapshot','--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded'])&&
  run.executable==='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe','FULL_SUITE_COMMAND_CHANGED');
must(candidate.cases?.length===83&&new Set(candidate.cases.map(r=>r.approvedPath)).size===83&&eq(candidate.cases,review.images)&&
  sha(Buffer.from(JSON.stringify(candidate.bundle)))===candidate.bundleSha256&&candidate.bundleSha256===manifest.candidate.bundleSha256&&
  manifest.candidate.path===p.candidate&&manifest.candidate.sha256===bound.get(p.candidate).sha256&&ownerImages.images?.length===83,'EXACT83_SCOPE_CHANGED');
must(promotion.status==='complete'&&promotion.fullPromotion===true&&promotion.failure===null&&promotion.cleanupErrors?.length===0&&promotion.postVerificationErrors?.length===0&&
  promotion.publishedImageCount===83&&promotion.retainedRecoveries?.length===83&&promotion.changedImages?.length===83&&promotion.remainingImages?.length===0&&
  promotion.claimedWithoutPublication?.length===0&&eq(promotion.ownerDecision,{path:p.imageDecision,sha256:bound.get(p.imageDecision).sha256})&&promotion.candidateBundleSha256===candidate.bundleSha256,
  'ACTUAL83_PROMOTION_NOT_COMPLETE');
const decisions=new Map(ownerImages.images.map(r=>[r.approvedPath,r]));must(decisions.size===83,'IMAGE_DECISIONS_NOT_UNIQUE');
const approved={...priorSource.sourceHashes};
for(const r of candidate.cases){
  const d=decisions.get(r.approvedPath),recovery=promotion.retainedRecoveries.find(x=>x.path.endsWith('/'+path.basename(r.approvedPath)));
  must(/^apps\/jentra_desktop\/test\/goldens\/[A-Za-z0-9_-]+\.png$/.test(r.approvedPath)&&approved[r.approvedPath]===r.approvedSha256&&
    d?.decision==='accept'&&d.candidateSha256===r.candidateSha256&&recovery?.sha256===r.approvedSha256&&recovery.claimedSha256===r.approvedSha256&&
    recovery.originalSha256===r.approvedSha256&&recovery.originalMatched===true&&recovery.published===true,'EXACT_APPROVED_IMAGE_CHANGED:'+r.stem);
  await bind(recovery.path,r.approvedSha256);await bind(r.approvedBackup,r.approvedSha256);await bind(r.candidatePath,r.candidateSha256);
  approved[r.approvedPath]=r.candidateSha256;
}
must(eq(approved,manifest.sourceHashes)&&promotion.sourceAfter?.sha256===manifest.sourceInputsSha256&&promotion.sourceAfter.selectedSources===1068,'ONLY83_PROMOTION_DELTA_REQUIRED');
for(const binding of [...manifest.bindings,...promotion.validatedBindings,...promotion.bindingsAfter.bindings])await bind(binding.path,binding.sha256);
for(const ref of review.refs)await bind(ref.path,ref.sha256);
must(live.projectId==='xpdoufauvrbdmxgngetv'&&live.migrationCount===43&&live.apiFunctions===107&&live.checkedProviders===120&&live.unchangedProviders===120&&
  live.changedProviders?.length===0&&live.missingProviders?.length===0&&live.addedProviders?.length===0&&live.wave5Tables?.length===15&&live.wave5Tables.every(t=>t.rlsEnabled&&t.rlsForced)&&
  live.wave5RlsFlagsUnchanged===true&&live.databaseMetadataAndExactCollisionPreflightClean===true&&Object.values(live.collisions).every(n=>n===0)&&
  live.rolePermissions===87&&live.roleAssignments===1&&live.entitlements===28&&live.memberships===1&&live.readOnly===true,'SAVED_LIVE_PREFLIGHT_CHANGED');
for(const key of ['fullRuntimePreflightComplete','currentRuntimeApprovalReady','runtimeOwnerApproved','authenticatedNative','nativeKeyboardVerified','realMfa','actualDelivery',
  'independentSessionContention','targetScaleLoad','migrationInstallationPerformed','originalSixReinstalled','AuthUsersCreatedOrDeleted','privateSecretsRead','SDKJobsExecuted'])must(live[key]===false,'LIVE_GATE_CHANGED:'+key);
must(live.ownerAcceptedCriteria===0&&native.accountExistenceVerified===false&&native.accountExists===null&&live.nativeTarget.accountCollisionVerified===false&&
  live.nativeTarget.accountCollisionClear===null&&live.historicalAccessRowHashComparisonAvailable===false&&live.historicalPolicyGrantHashComparisonAvailable===false,'HISTORICAL_NATIVE_BOUNDARY_CHANGED');
must(nativeNet.method==='Windows net.exe user exact local account'&&nativeNet.accountName==='jentra-w5-runtime'&&nativeNet.accountExistenceVerified===true&&
  nativeNet.accountExists===false&&nativeNet.exitCode===2&&nativeNet.namedError==='NERR_UserNotFound / NET HELPMSG 2221'&&
  typeof nativeNet.rawOutput==='string'&&nativeNet.rawOutput.includes('The user name could not be found.')&&nativeNet.rawOutput.includes('2221')&&
  nativeNet.packageDirectoryExists===false&&nativeNet.profileDirectoryExists===false&&nativeNet.readOnly===true&&nativeNet.provisionedByThisCheck===false&&
  nativeNet.accountOrSessionContentsRead===false&&nativeNet.previousUnverifiedRecordPreserved===p.liveNative&&
  Date.parse(nativeNet.observedAt)>Date.parse(native.observedAt),'NEW_EXACT_NATIVE_METADATA_CHANGED');
for(const file of ['rawEvidence','query','queryHashManifest','nativeTarget','sourceManifest','previousFullSummary']){
  const b=file==='nativeTarget'?live.nativeTarget.observation:live[file];if(b?.path&&b.sha256)await bind(b.path,b.sha256);
}
must(liveRaw.query.sha256===bound.get(p.liveSql).sha256&&queries.mainSql.sha256===bound.get(p.liveSql).sha256&&
  queries.metadataSql.sha256===sha(Buffer.from(liveRaw.metadataQuery))&&comparison.currentRead.sha256===bound.get(p.liveRaw).sha256&&comparison.unchangedProviders===120,
  'EXACT_PREFLIGHT_QUERY_BINDING_CHANGED');
for(const b of [comparison.previousRead,queries.sourceProposal])await bind(b.path,b.sha256);
await bind(self);await bind('scripts/wave5/cash_ui_evidence.mjs');await bind('scripts/wave5/record_continuation_windows.mjs');
const now=new Date().toISOString(),priorRows=JSON.stringify(matrix.rows),priorAcceptance=JSON.stringify(matrix.ownerCriterionAcceptance);
matrix.updatedAt=now;
matrix.goldenOwnerReview={...matrix.goldenOwnerReview,approvedBaselineImagesChanged:true,postApprovalFullSuiteRequired:false,
  imageOwnerDecision:{path:p.imageDecision,sha256:bound.get(p.imageDecision).sha256},promotion:{path:p.promotion,sha256:bound.get(p.promotion).sha256,promoted:83},
  postApprovalSourceManifest:{path:p.manifest,sha256:bound.get(p.manifest).sha256},postApprovalFullDesktopSuite:{path:p.run,sha256:bound.get(p.run).sha256,passed:2004,failed:0,skipped:0},
  packetIsHistoricalPreDecisionEvidence:true,packetOwnerAcceptanceCountAtPreparation:0,recordedCriterionAcceptanceCount:3};
matrix.continuationChecks={...matrix.continuationChecks,sourceRevision:'golden-postapproval-20261010-r2',sourceManifest:p.manifest,
  priorGoldenReviewSourceManifest:p.priorSource,broadDesktopApprovedControlCurrent:false,strictCandidateGoldenCasesCurrent:false,
  priorApprovedControlAndFocusedCandidateAreHistorical:true,broadDesktopApprovedSuiteCurrent:true,
  approvedDesktopFullSuite:{record:p.run,passed:2004,failed:0,skipped:0,sourceManifest:p.manifest},
  approvedGoldensRegenerated:true,approvedGoldensRegenerationScope:'Exactly 83 human-approved PNG substitutions; strict comparator unchanged.',
  analyzerCurrentSource:false,windowsPreviewBuildCurrentSourceMatch:false,
  priorAnalysisAndPreviewBuildScope:'Fresh r2 pre-promotion analysis/build remain valid evidence for unchanged Dart inputs; exact full 1068-input hashes differ only by 83 approved PNGs. Current paired native packages remain a separate pending gate.'};
matrix.postApprovalGoldenEvidence={recordedAt:now,ownerDecision:bound.get(p.imageDecision),promotion:bound.get(p.promotion),fullDesktopSuite:bound.get(p.run),
  sourceManifest:bound.get(p.manifest),passed:2004,failed:0,skipped:0,promotedImages:83,remainingGoldenFailures:0,
  ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,rowsAndAcceptancePreserved:true,
  boundary:'Owner-approved images and full strict desktop tests only; no installation, native keyboard/MFA, delivery/model usage, contention/load or whole-system acceptance.'};
matrix.currentLivePreflight={summary:bound.get(p.live),report:bound.get(p.liveMd),raw:bound.get(p.liveRaw),query:bound.get(p.liveSql),queryHashes:bound.get(p.liveQueries),
  fingerprintComparison:bound.get(p.liveCompare),nativeMetadata:bound.get(p.liveNative),observedAt:live.observedAt,migrations:43,apiFunctions:107,unchangedProviders:120,
  scope:'Read-only database metadata and exact proposed SQL-resource collision observations; all collisions zero at the saved observation.',
  fullRuntimePreflightComplete:false,nativeAccountExistenceVerified:false,runtimeOwnerApproved:false,
  latestNativeAccountMetadata:{record:bound.get(p.liveNativeNet),observedAt:nativeNet.observedAt,accountName:nativeNet.accountName,accountExistenceVerified:true,accountExists:false,
    packageDirectoryExists:false,profileDirectoryExists:false,scope:'Exact Windows account/path metadata only; no provisioning, session access or authenticated native acceptance.'},
  boundary:'Older installed/runtime/readiness records remain historical. Recheck live state immediately before any separately approved operation.'};
must(JSON.stringify(matrix.rows)===priorRows&&JSON.stringify(matrix.ownerCriterionAcceptance)===priorAcceptance&&matrix.ownerAcceptedCriteria===3,'ROWS_OR_ACCEPTANCE_CHANGED');
for(const key of falseGates)must(matrix[key]===false&&matrix[key]===priorMatrix[key],'SEPARATE_GATE_MUTATED:'+key);
const allowedTop=new Set(['updatedAt','goldenOwnerReview','continuationChecks','postApprovalGoldenEvidence','currentLivePreflight']);
for(const key of Object.keys(priorMatrix).filter(k=>!allowedTop.has(k)))must(eq(matrix[key],priorMatrix[key]),'UNAUTHORIZED_TOP_LEVEL_CHANGE:'+key);
const relative=(from,file)=>path.posix.relative(path.posix.dirname(from),file),link=(from,label,file)=>`[${label}](<${relative(from,file)}>)`;
function summary(from){return `The owner approved and replaced **exactly 83 golden PNGs** against ${link(from,'the direct human image decision',p.imageDecision)} and ${link(from,'the completed promotion with retained originals',p.promotion)}. The fresh ${link(from,'full strict desktop suite',p.run)} passes **2004 tests / 0 failures / 0 skips**, with all 2004 unique identities and all 1068 ${link(from,'post-approval source inputs',p.manifest)} audited before and after. **3 of 109 complete criteria remain accepted: AC-551, AC-552 and AC-553; the other 106 remain unaccepted. Jentra OS and Wave 5 remain incomplete.** Native keyboard/authentication/MFA, actual export/worker delivery/model usage, independent contention/load, runtime installation/approval and whole-system signoff remain separate open gates.`;}
function liveSummary(from){return `The ${link(from,'saved read-only live preflight',p.liveMd)} at ${live.observedAt} records **43 migrations / 107 API functions**, 120/120 unchanged protected function hashes, 87/1/28/1 access counts and 15 unchanged enabled/forced RLS tables. Exact reviewed SQL-resource collision counts were zero. Access-row/policy/grant hashes establish first baselines. The earlier Windows account lookups failed and remain preserved as unverified history. The later ${link(from,'exact net.exe account read',p.liveNativeNet)} at ${nativeNet.observedAt} verifies that jentra-w5-runtime does not exist (exit 2, NERR_UserNotFound / 2221); package/profile paths were also absent. This resolves only that account metadata check. Full runtime preflight and approval remain incomplete. These observations do not rerun installed SQL, change accounts/migrations or authorize runtime operations; recheck immediately before a separately approved operation.`;}
function publishProse(file,title){
  const text=original.get(file).toString('utf8'),firstBreak=text.indexOf('\n');
  must(firstBreak>0&&text.startsWith('# '),'DOCUMENT_HEADING_CHANGED:'+file);
  must(!text.includes('## October 10 post-approval golden evidence'),'DUPLICATE_FINAL_GOLDEN_STATUS');
  const intro='\n\n## October 10 post-approval golden evidence\n\n'+summary(file)+'\n\n'+liveSummary(file)+
    '\n\nThe self-contained owner packet, readiness, old 83-failure control and preceding status prose below are preserved **historical pre-decision/pre-promotion checkpoints**. Their zero-acceptance or unchanged-PNG statements describe those checkpoints. The current facts are 83 approved images, 2004 passing strict tests and 3 accepted criteria. All 109 matrix rows, specification mappings, evidence links and exact existing criterion decision records are preserved. Earlier r2 scoped analysis/build bind unchanged Dart sources before image promotion; their full input manifests remain historical. Paired final native packaging and authenticated native checks remain separate.\n\n'+
    link(file,'Immutable before/after publication checkpoint',p.before)+'; '+link(file,'actual publication result',p.after)+'. Production and real billing remain excluded.\n\n## Preserved earlier checkpoint prose\n';
  return title+intro+text.slice(firstBreak);
}
const md=publishProse(p.markdown,'# Wave 5 requirement matrix — current evidence October 10, 2026'),status=publishProse(p.status,'# Wave 5 development status — current evidence October 10, 2026');
const tableRows=text=>text.split(/\r?\n/).filter(x=>/^\| (?:FR|NFR|AC|EC)-\d+ \|/.test(x));
must(tableRows(md).length===109&&eq(tableRows(md),tableRows(original.get(p.markdown).toString('utf8'))),'ALL109_TABLE_CELLS_MUST_REMAIN_EXACT');
const outputs=new Map([[p.matrix,Buffer.from(JSON.stringify(matrix,null,2)+'\n')],[p.markdown,Buffer.from(md)],[p.status,Buffer.from(status)]]);
const selected=h=>Object.fromEntries(Object.entries(h).filter(([file])=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(file)||
  priorSource.dependencyScope.some(s=>file.startsWith(s+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(file)));
const toolPaths=['C:/src/flutter/bin/cache/flutter.version.json','C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe','C:/src/flutter/bin/cache/flutter_tools.snapshot',
  'C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe'];
must(eq(manifest.toolchain.tooling.map(x=>x.path),toolPaths),'EXACT_TOOLCHAIN_REQUIRED');
must(path.resolve(manifest.snapshot)===path.join(root,'build/w5goldens20261010/r1')&&manifest.workingDirectory===path.join(manifest.snapshot,'apps/jentra_desktop'),'SNAPSHOT_SCOPE_CHANGED');
async function recheck(claimedFile=null){
  for(const[file,h]of expectedLiving)if(file!==claimedFile)must(sha(await bytes(file))===h,'CONCURRENT_LIVING_CHANGE:'+file);
  for(const b of bound.values())if(!living.includes(b.path))must(sha(await bytes(b.path))===b.sha256,'CONCURRENT_BOUND_CHANGE:'+b.path);
  const [current,warm]=await Promise.all([sources(root),sources(manifest.snapshot)]);
  must(eq(selected(current),manifest.sourceHashes)&&eq(selected(warm),manifest.sourceHashes),'CURRENT_OR_WARM1068_DRIFT');
  for(const t of manifest.toolchain.tooling)must(sha(await readFile(t.path))===t.sha256,'TOOLCHAIN_DRIFT:'+t.path);
  const sdkMetadata=parse(await readFile(toolPaths[0]));must(eq(sdkMetadata,manifest.toolchain.sdkMetadata),'TOOLCHAIN_METADATA_DRIFT');
  return {checkedAt:new Date().toISOString(),sourceManifest:bound.get(p.manifest),selectedSources:1068,sourceInputsSha256:manifest.sourceInputsSha256,
    currentSourceMatchesApprovedInputs:true,warmSourceMatchesApprovedInputs:true,toolchain:manifest.toolchain,fullSuite:bound.get(p.run),promotion:bound.get(p.promotion)};
}
const audit=await recheck();
const before={preparedAt:now,kind:'postapproval-golden-evidence-before',ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,rowsAndAcceptancePreserved:true,
  imageOwnerDecision:bound.get(p.imageDecision),criterionOwnerDecision:bound.get(p.criterionDecision),criterionAcceptanceResult:bound.get(p.acceptAfter),
  fullSuite:bound.get(p.run),sourceManifest:bound.get(p.manifest),promotion:bound.get(p.promotion),livePreflight:bound.get(p.live),
  originalLivingDocuments:[...original].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length,utf8Base64:b.toString('base64')})),
  plannedDocuments:[...outputs].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length})),boundInputs:[...bound.values()],currentSourceAudit:audit,
  boundary:'Evidence/status publication only. All109 rows and three existing direct owner acceptances unchanged; no PNG/source/store/live/native/SDK operation.'};
if(!publish){
  console.log(JSON.stringify({write:false,fullSuitePassed:true,passed:2004,failed:0,skipped:0,promotedImages:83,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,
    documents:before.plannedDocuments,immutableBefore:p.before,immutableAfter:p.after,current1068AndBindingsVerified:true,all109RowsUnchanged:true,
    criterionAcceptanceUnchanged:true,separateGatesUnchanged:true,outputsWritten:false,sdkExecuted:false},null,2));
}else{
  for(const file of [p.before,p.after]){try{await access(inside(file));throw Error('IMMUTABLE_RESULT_EXISTS:'+file);}catch(e){if(e.code!=='ENOENT')throw e;}}
  await recheck();
  const recoveryDirectory=base+'postapproval-golden-status-recovery-20261010-r2-'+randomUUID();
  const states=[...outputs].map(([file,b])=>({path:file,target:inside(file),bytes:b,originalSha256:sha(original.get(file)),plannedSha256:sha(b),
    recoveryPath:recoveryDirectory+'/'+path.basename(file),recovery:inside(recoveryDirectory+'/'+path.basename(file)),temp:null,tempOwned:false,claimed:false,published:false,claimedSha256:null}));
  before.recoveryDirectory=recoveryDirectory;before.publicationPlans=states.map(({bytes,target,recovery,temp,...s})=>s);
  const beforeBytes=Buffer.from(JSON.stringify(before,null,2)+'\n');await writeFile(inside(p.before),beforeBytes,{flag:'wx'});
  const resultHandle=await open(inside(p.after),'wx');
  await resultHandle.writeFile(JSON.stringify({kind:'postapproval-golden-evidence-pending',before:{path:p.before,sha256:sha(beforeBytes)},fullPublication:false,
    recoveryDirectory,boundary:'Reserved before publication; interruption does not establish complete status publication.'},null,2)+'\n');
  const changed=[],cleanupErrors=[],postVerificationErrors=[];let publicationError=null,finalAudit=null;
  try{
    await mkdir(inside(recoveryDirectory));
    for(const s of states){
      await recheck();s.temp=inside(s.path+'.'+randomUUID()+'.tmp');const temp=await open(s.temp,'wx');s.tempOwned=true;
      try{await temp.writeFile(s.bytes);}finally{await temp.close();}
      await recheck();await rename(s.target,s.recovery);s.claimed=true;s.claimedSha256=sha(await readFile(s.recovery));
      must(s.claimedSha256===s.originalSha256,'CONCURRENT_CLAIMED_DOCUMENT_CHANGE:'+s.path);
      await recheck(s.path);
      must(sha(await readFile(s.recovery))===s.originalSha256&&sha(await readFile(s.temp))===s.plannedSha256,'OWNED_PUBLICATION_BYTES_CHANGED');
      await copyFile(s.temp,s.target,constants.COPYFILE_EXCL);s.published=true;expectedLiving.set(s.path,s.plannedSha256);changed.push(s.path);await recheck();
    }
  }catch(e){publicationError={message:e.message,code:e.code??null};}
  for(const s of states.filter(s=>s.tempOwned))try{await unlink(s.temp);}catch(e){if(e.code!=='ENOENT')cleanupErrors.push({path:path.relative(root,s.temp),message:e.message,code:e.code??null});}
  const observed=[],recoveries=[];
  for(const file of living)try{const b=await bytes(file);observed.push({path:file,sha256:sha(b),matchesPlanned:sha(b)===sha(outputs.get(file))});}catch(e){observed.push({path:file,error:e.message});}
  for(const s of states.filter(s=>s.claimed))try{const h=sha(await bytes(s.recoveryPath));recoveries.push({path:s.recoveryPath,originalPath:s.path,sha256:h,originalSha256:s.originalSha256,
    claimedSha256:s.claimedSha256,matchesOriginal:h===s.originalSha256,matchesClaimed:h===s.claimedSha256,published:s.published});}catch(e){recoveries.push({path:s.recoveryPath,error:e.message});}
  let actualOwnerAccepted=null,actualRowsPreserved=false,actualAcceptancePreserved=false,actualGatesPreserved=false;
  try{const actual=parse(await bytes(p.matrix));actualOwnerAccepted=actual.ownerAcceptedCriteria;actualRowsPreserved=eq(actual.rows,priorMatrix.rows);
    actualAcceptancePreserved=eq(actual.ownerCriterionAcceptance,priorMatrix.ownerCriterionAcceptance);actualGatesPreserved=falseGates.every(k=>actual[k]===priorMatrix[k]);}catch{}
  try{finalAudit=await recheck();}catch(e){postVerificationErrors.push({gate:'finalLivingSourceBoundAndToolAudit',message:e.message});publicationError??={message:e.message,code:e.code??null};}
  if(observed.some(x=>x.matchesPlanned!==true)||actualOwnerAccepted!==3||!actualRowsPreserved||!actualAcceptancePreserved||!actualGatesPreserved){
    postVerificationErrors.push({gate:'actualDestinationHashesRowsAndAcceptance',message:'ACTUAL_STATUS_DESTINATION_DRIFT'});publicationError??={message:'ACTUAL_STATUS_DESTINATION_DRIFT',code:null};}
  if(recoveries.length!==states.filter(s=>s.claimed).length||recoveries.some(r=>r.matchesOriginal!==true||r.matchesClaimed!==true)){
    postVerificationErrors.push({gate:'actualRetainedRecoveryHashes',message:'ACTUAL_STATUS_RECOVERY_DRIFT'});publicationError??={message:'ACTUAL_STATUS_RECOVERY_DRIFT',code:null};}
  if(cleanupErrors.length)publicationError??={message:'OWNED_TEMP_CLEANUP_FAILED',code:null};
  const fullPublication=changed.length===3&&publicationError===null&&cleanupErrors.length===0&&postVerificationErrors.length===0&&finalAudit!==null;
  const after={finishedAt:new Date().toISOString(),kind:'postapproval-golden-evidence-result',before:{path:p.before,sha256:sha(beforeBytes)},status:fullPublication?'complete':'failed',
    fullPublication,changedDocuments:changed,remainingDocuments:living.filter(file=>!changed.includes(file)),observedDocuments:observed,retainedRecoveries:recoveries,
    claimedWithoutPublication:states.filter(s=>s.claimed&&!s.published).map(s=>({path:s.path,recoveryPath:s.recoveryPath,claimedSha256:s.claimedSha256})),
    publicationError,cleanupErrors,postVerificationErrors,finalSourceAndToolAudit:finalAudit,validatedInputs:[...bound.values()],recoveryDirectory,
    observedOwnerAcceptedCriteria:actualOwnerAccepted,all109RowsUnchanged:actualRowsPreserved,criterionAcceptanceUnchanged:actualAcceptancePreserved,separateGatesUnchanged:actualGatesPreserved,
    fullSuite:bound.get(p.run),promotion:bound.get(p.promotion),sourceManifest:bound.get(p.manifest),livePreflight:bound.get(p.live),
    approvedBaselinesChangedByThisAction:false,sourceEdits:0,acceptanceStoresTouched:false,SDKJobsExecuted:false,liveOperations:false,
    boundary:'Only evidence pointers/prose in the three named living documents change. Actual partial outcomes and uniquely owned originals/concurrent bytes are retained; no rollback, retry or extra acceptance.'};
  try{await resultHandle.truncate(0);await resultHandle.write(JSON.stringify(after,null,2)+'\n',0,'utf8');}finally{await resultHandle.close();}
  console.log(JSON.stringify(after,null,2));if(!fullPublication)process.exitCode=1;
}
